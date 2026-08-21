-- Attach a Shopify shop to an existing CRM merchant without creating a second
-- merchant_master row. Resolve shops by credentials.shop_domain first.
-- Uninstall must not disable portal admins on a linked (non-Shopify-native) merchant.

CREATE UNIQUE INDEX IF NOT EXISTS ux_merchant_credentials_shopify_active_shop_domain
  ON public.merchant_credentials ((credentials->>'shop_domain'))
  WHERE service_name = 'shopify_app'
    AND is_active IS TRUE
    AND nullif(credentials->>'shop_domain', '') IS NOT NULL;

CREATE OR REPLACE FUNCTION public.shopify_resolve_merchant_id(p_shop_domain text)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    (
      SELECT mc.merchant_id
      FROM merchant_credentials mc
      WHERE mc.service_name = 'shopify_app'
        AND mc.is_active IS TRUE
        AND mc.credentials->>'shop_domain' = p_shop_domain
      LIMIT 1
    ),
    (
      SELECT mm.id
      FROM merchant_master mm
      WHERE mm.merchant_code = p_shop_domain
      LIMIT 1
    )
  );
$function$;

REVOKE ALL ON FUNCTION public.shopify_resolve_merchant_id(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.shopify_resolve_merchant_id(text) TO service_role;

CREATE OR REPLACE FUNCTION public.shopify_webhook_deactivate_shop(
  p_shop_domain text,
  p_topic text DEFAULT 'shop/redact'::text,
  p_payload jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_request_id uuid;
  v_sessions_deleted int := 0;
  v_credentials_deactivated int := 0;
  v_admins_deactivated int := 0;
BEGIN
  v_merchant_id := shopify_resolve_merchant_id(p_shop_domain);

  DELETE FROM shopify_session WHERE shop = p_shop_domain;
  GET DIAGNOSTICS v_sessions_deleted = ROW_COUNT;

  UPDATE merchant_credentials
  SET is_active = false, updated_at = now()
  WHERE service_name = 'shopify_app'
    AND is_active IS TRUE
    AND (
      credentials->>'shop_domain' = p_shop_domain
      OR (
        v_merchant_id IS NOT NULL
        AND merchant_id = v_merchant_id
        AND nullif(credentials->>'shop_domain', '') IS NULL
      )
    );
  GET DIAGNOSTICS v_credentials_deactivated = ROW_COUNT;

  -- Only Shopify-staff admin rows. Portal owners on a linked merchant stay active.
  IF v_merchant_id IS NOT NULL THEN
    UPDATE admin_users
    SET active_status = false, updated_at = now()
    WHERE merchant_id = v_merchant_id
      AND active_status IS TRUE
      AND shopify_user_id IS NOT NULL;
    GET DIAGNOSTICS v_admins_deactivated = ROW_COUNT;
  END IF;

  INSERT INTO shopify_webhook_requests (
    topic, shop_domain, merchant_id, payload, status, export_payload, processed_at
  ) VALUES (
    p_topic,
    p_shop_domain,
    v_merchant_id,
    p_payload,
    'completed',
    jsonb_build_object(
      'sessions_deleted', v_sessions_deleted,
      'credentials_deactivated', v_credentials_deactivated,
      'admins_deactivated', v_admins_deactivated
    ),
    now()
  )
  RETURNING id INTO v_request_id;

  RETURN jsonb_build_object(
    'success', true,
    'request_id', v_request_id,
    'merchant_id', v_merchant_id,
    'sessions_deleted', v_sessions_deleted,
    'credentials_deactivated', v_credentials_deactivated,
    'admins_deactivated', v_admins_deactivated
  );
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'UNEXPECTED_ERROR',
      'error_message', SQLERRM
    );
END;
$function$;

DROP FUNCTION IF EXISTS public.shopify_upsert_merchant_with_credentials(text, text, jsonb);

CREATE OR REPLACE FUNCTION public.shopify_upsert_merchant_with_credentials(
  p_merchant_code text,
  p_merchant_name text,
  p_shopify_credentials jsonb,
  p_target_merchant_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_existing_merchant record;
  v_credentials_exist boolean := false;
  v_is_new boolean := false;
  v_is_attach boolean := false;
  v_credential_id uuid;
  v_default_plan_id uuid;
  v_shopify_free_plan_id uuid;
  v_shop_domain text;
  v_other_merchant_id uuid;
BEGIN
  IF p_merchant_code IS NULL OR p_merchant_code = '' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'INVALID_MERCHANT_CODE',
      'error_message', 'merchant_code is required'
    );
  END IF;

  IF p_shopify_credentials IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'INVALID_CREDENTIALS',
      'error_message', 'shopify_credentials is required'
    );
  END IF;

  v_shop_domain := coalesce(
    nullif(p_shopify_credentials->>'shop_domain', ''),
    p_merchant_code
  );

  SELECT id
  INTO v_shopify_free_plan_id
  FROM merchant_plan
  WHERE key = 'shopify_free'
    AND platform_id = 'shopify'
    AND active_status IS TRUE
  LIMIT 1;

  -- Another merchant already owns this shop.
  SELECT merchant_id
  INTO v_other_merchant_id
  FROM merchant_credentials
  WHERE service_name = 'shopify_app'
    AND is_active IS TRUE
    AND credentials->>'shop_domain' = v_shop_domain
    AND (p_target_merchant_id IS NULL OR merchant_id <> p_target_merchant_id)
  LIMIT 1;

  IF v_other_merchant_id IS NOT NULL
     AND (p_target_merchant_id IS NULL OR v_other_merchant_id <> p_target_merchant_id) THEN
    -- Create path: also conflict if merchant_code row is a different merchant
    -- than the shop_domain owner. Attach path: always refuse a foreign owner.
    IF p_target_merchant_id IS NOT NULL THEN
      RETURN jsonb_build_object(
        'success', false,
        'error_code', 'SHOP_ALREADY_LINKED',
        'error_message', 'This Shopify shop is already linked to another merchant'
      );
    END IF;
  END IF;

  IF p_target_merchant_id IS NOT NULL THEN
    SELECT id, merchant_code, name
    INTO v_existing_merchant
    FROM merchant_master
    WHERE id = p_target_merchant_id;

    IF v_existing_merchant.id IS NULL THEN
      RETURN jsonb_build_object(
        'success', false,
        'error_code', 'TARGET_MERCHANT_NOT_FOUND',
        'error_message', 'Target merchant does not exist'
      );
    END IF;

    IF v_other_merchant_id IS NOT NULL AND v_other_merchant_id <> p_target_merchant_id THEN
      RETURN jsonb_build_object(
        'success', false,
        'error_code', 'SHOP_ALREADY_LINKED',
        'error_message', 'This Shopify shop is already linked to another merchant'
      );
    END IF;

    v_merchant_id := v_existing_merchant.id;
    v_is_attach := true;
    v_is_new := false;

    SELECT EXISTS (
      SELECT 1
      FROM merchant_credentials
      WHERE merchant_id = v_merchant_id
        AND service_name = 'shopify_app'
        AND is_active IS TRUE
    ) INTO v_credentials_exist;

    IF v_credentials_exist THEN
      UPDATE merchant_credentials
      SET
        credentials = p_shopify_credentials,
        external_id = v_shop_domain,
        updated_at = now()
      WHERE merchant_id = v_merchant_id
        AND service_name = 'shopify_app'
        AND is_active IS TRUE;
    ELSE
      INSERT INTO merchant_credentials (
        merchant_id,
        service_name,
        credentials,
        environment,
        is_active,
        external_id
      ) VALUES (
        v_merchant_id,
        'shopify_app',
        p_shopify_credentials,
        'production',
        true,
        v_shop_domain
      );
      v_credentials_exist := true;
    END IF;

  ELSE
    SELECT id
    INTO v_default_plan_id
    FROM merchant_plan
    WHERE key = 'enterprise'
      AND active_status IS TRUE
    ORDER BY display_order ASC NULLS LAST, created_at ASC
    LIMIT 1;

    IF v_default_plan_id IS NULL THEN
      RETURN jsonb_build_object(
        'success', false,
        'error_code', 'DEFAULT_PLAN_NOT_FOUND',
        'error_message', 'Default Shopify merchant plan enterprise is not active or does not exist'
      );
    END IF;

    SELECT id, merchant_code, name
    INTO v_existing_merchant
    FROM merchant_master
    WHERE merchant_code = p_merchant_code;

    IF v_existing_merchant.id IS NOT NULL THEN
      v_merchant_id := v_existing_merchant.id;
      v_is_new := false;

      UPDATE merchant_master
      SET plan_id = v_default_plan_id
      WHERE id = v_merchant_id
        AND plan_id IS NULL;

      SELECT EXISTS (
        SELECT 1
        FROM merchant_credentials
        WHERE merchant_id = v_merchant_id
          AND service_name = 'shopify_app'
          AND is_active IS TRUE
      ) INTO v_credentials_exist;

      IF v_credentials_exist THEN
        UPDATE merchant_credentials
        SET
          credentials = p_shopify_credentials,
          external_id = coalesce(external_id, v_shop_domain),
          updated_at = now()
        WHERE merchant_id = v_merchant_id
          AND service_name = 'shopify_app'
          AND is_active IS TRUE;
      ELSE
        INSERT INTO merchant_credentials (
          merchant_id,
          service_name,
          credentials,
          environment,
          is_active,
          external_id
        ) VALUES (
          v_merchant_id,
          'shopify_app',
          p_shopify_credentials,
          'production',
          true,
          v_shop_domain
        );
      END IF;

    ELSE
      INSERT INTO merchant_master (
        merchant_code,
        name,
        auth_methods,
        plan_id
      ) VALUES (
        p_merchant_code,
        p_merchant_name,
        ARRAY['line', 'tel'],
        v_default_plan_id
      )
      RETURNING id INTO v_merchant_id;

      INSERT INTO merchant_credentials (
        merchant_id,
        service_name,
        credentials,
        environment,
        is_active,
        external_id
      ) VALUES (
        v_merchant_id,
        'shopify_app',
        p_shopify_credentials,
        'production',
        true,
        v_shop_domain
      )
      RETURNING id INTO v_credential_id;

      v_is_new := true;
      v_credentials_exist := true;
    END IF;
  END IF;

  IF v_shopify_free_plan_id IS NOT NULL THEN
    INSERT INTO merchant_plan_assignment (merchant_id, plan_id, platform_id)
    VALUES (v_merchant_id, v_shopify_free_plan_id, 'shopify')
    ON CONFLICT (merchant_id, platform_id) DO NOTHING;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM merchant_languages
    WHERE merchant_id = v_merchant_id AND is_default IS TRUE
  ) THEN
    INSERT INTO merchant_languages (
      merchant_id, language_code, language_name,
      is_default, is_active, display_order
    ) VALUES (
      v_merchant_id, 'en', 'English', true, true, 1
    )
    ON CONFLICT (merchant_id, language_code)
    DO UPDATE SET is_default = true, is_active = true, updated_at = now();
  END IF;

  BEGIN
    PERFORM public.shopify_seed_default_earn_channel(
      v_merchant_id,
      coalesce(v_existing_merchant.merchant_code, p_merchant_code)
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN jsonb_build_object(
    'success', true,
    'is_new', v_is_new,
    'is_attach', v_is_attach,
    'merchant_id', v_merchant_id,
    'merchant_code', coalesce(v_existing_merchant.merchant_code, p_merchant_code),
    'merchant_name', coalesce(v_existing_merchant.name, p_merchant_name),
    'credentials_exist', v_credentials_exist,
    'message', CASE
      WHEN v_is_attach THEN 'Shopify shop attached to existing merchant'
      WHEN v_is_new THEN 'Merchant created with Shopify credentials'
      ELSE 'Merchant found, credentials updated'
    END
  );

EXCEPTION
  WHEN unique_violation THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'MERCHANT_CODE_EXISTS',
      'error_message', 'Merchant code already exists or this shop is already linked'
    );
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'UNEXPECTED_ERROR',
      'error_message', SQLERRM
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.shopify_upsert_merchant_with_credentials(text, text, jsonb, uuid)
  TO anon, authenticated, service_role;
