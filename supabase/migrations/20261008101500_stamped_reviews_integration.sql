-- Stamped Reviews → loyalty points (inbound webhook + app event earn)

INSERT INTO public.integration_type_master (
  integration_key,
  display_name,
  description,
  public_fields,
  sensitive_fields,
  platform_key,
  platform_name,
  platform_order
)
VALUES (
  'stamped',
  'Stamped.io',
  'Reward customers with points when they write a product review.',
  ARRAY['store_hash', 'shop_domain'],
  ARRAY['private_api_key', 'inbound_webhook_secret'],
  'stamped',
  'Stamped.io',
  8
)
ON CONFLICT (integration_key) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.stamped_review_award (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES public.merchant_master (id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.user_accounts (id) ON DELETE CASCADE,
  review_id text NOT NULL,
  product_external_id text,
  review_type text NOT NULL,
  points_awarded integer NOT NULL DEFAULT 0,
  wallet_ledger_ids uuid[] NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT stamped_review_award_merchant_id_review_id_key UNIQUE (merchant_id, review_id)
);

CREATE INDEX IF NOT EXISTS stamped_review_award_user_product_idx
  ON public.stamped_review_award (merchant_id, user_id, product_external_id);

DROP TRIGGER IF EXISTS set_updated_at ON public.stamped_review_award;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON public.stamped_review_award
  FOR EACH ROW
  EXECUTE FUNCTION public.trigger_set_updated_at();

CREATE UNIQUE INDEX IF NOT EXISTS merchant_credentials_one_stamped_uidx
  ON public.merchant_credentials (merchant_id)
  WHERE service_name = 'stamped';

CREATE OR REPLACE FUNCTION public.fn_integration_stamped_award_review(
  p_merchant_id uuid,
  p_event_key text,
  p_payload jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_review_id text;
  v_email text;
  v_rating numeric;
  v_product_id text;
  v_review_type text;
  v_rule public.app_event_earn_rule%ROWTYPE;
  v_user_id uuid;
  v_points integer := 0;
  v_type_cfg jsonb;
  v_existing public.stamped_review_award%ROWTYPE;
  v_delta integer;
  v_ledger_id uuid;
  v_dedup text;
  v_topic text;
  v_has_media text;
BEGIN
  IF p_merchant_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'missing_merchant');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.merchant_credentials
    WHERE merchant_id = p_merchant_id
      AND service_name = 'stamped'
      AND is_active IS TRUE
      AND COALESCE(
        NULLIF(TRIM(credentials->>'private_api_key'), ''),
        NULLIF(TRIM(credentials->>'api_token'), ''),
        ''
      ) <> ''
  ) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_connected');
  END IF;

  v_topic := lower(COALESCE(NULLIF(TRIM(p_event_key), ''), ''));
  IF v_topic <> '' AND v_topic NOT LIKE '%review%' THEN
    RETURN jsonb_build_object('ok', true, 'reason', 'topic_skipped');
  END IF;

  v_review_id := NULLIF(TRIM(p_payload->>'id'), '');
  IF v_review_id IS NULL THEN
    v_review_id := NULLIF(TRIM(p_payload->>'reviewId'), '');
  END IF;
  IF v_review_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'missing_review_id');
  END IF;

  v_email := NULLIF(TRIM(p_payload->>'customerEmail'), '');
  IF v_email IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'missing_email');
  END IF;

  BEGIN
    v_rating := NULLIF(TRIM(p_payload->>'reviewRating'), '')::numeric;
  EXCEPTION
    WHEN OTHERS THEN
      v_rating := NULL;
  END;
  IF v_rating IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'missing_rating');
  END IF;

  v_has_media := lower(COALESCE(p_payload->>'reviewUserVideos', 'null'));
  IF v_has_media NOT IN ('', 'null', '[]') THEN
    v_review_type := 'video';
  ELSE
    v_has_media := lower(COALESCE(p_payload->>'reviewUserPhotos', 'null'));
    IF v_has_media NOT IN ('', 'null', '[]') THEN
      v_review_type := 'photo';
    ELSE
      v_review_type := 'text';
    END IF;
  END IF;

  SELECT * INTO v_rule
  FROM public.app_event_earn_rule
  WHERE merchant_id = p_merchant_id
    AND provider = 'stamped'
    AND event_key = 'product_review'
    AND is_active IS TRUE;

  IF v_rule.id IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'reason', 'rule_inactive');
  END IF;

  v_product_id := NULLIF(TRIM(p_payload->>'productId'), '');

  v_user_id := public.fn_match_marketplace_user(
    p_merchant_id,
    'shopify',
    NULL,
    v_email,
    NULL
  );
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'reason', 'member_not_found');
  END IF;

  IF v_rule.earn_limit = 'once_lifetime' THEN
    IF EXISTS (
      SELECT 1
      FROM public.stamped_review_award a
      WHERE a.merchant_id = p_merchant_id
        AND a.user_id = v_user_id
        AND a.review_id <> v_review_id
        AND a.points_awarded > 0
    ) THEN
      RETURN jsonb_build_object('ok', true, 'reason', 'lifetime_limit');
    END IF;
  ELSIF v_rule.earn_limit = 'once_per_product' AND v_product_id IS NOT NULL THEN
    IF EXISTS (
      SELECT 1
      FROM public.stamped_review_award a
      WHERE a.merchant_id = p_merchant_id
        AND a.user_id = v_user_id
        AND a.product_external_id = v_product_id
        AND a.review_id <> v_review_id
        AND a.points_awarded > 0
    ) THEN
      RETURN jsonb_build_object('ok', true, 'reason', 'product_limit');
    END IF;
  END IF;

  v_type_cfg := CASE
    WHEN v_rule.split_by_review_type THEN COALESCE(v_rule.points_by_type->v_review_type, '{}'::jsonb)
    ELSE COALESCE(
      v_rule.points_by_type->'_all',
      v_rule.points_by_type->'text',
      jsonb_build_object('default', v_rule.points_default)
    )
  END;

  IF v_rule.split_by_tier THEN
    v_points := COALESCE(
      (
        SELECT (v_type_cfg->'tiers'->>ua.tier_id::text)::integer
        FROM public.user_accounts ua
        WHERE ua.id = v_user_id
      ),
      (v_type_cfg->>'default')::integer,
      v_rule.points_default,
      0
    );
  ELSE
    v_points := COALESCE(
      (v_type_cfg->>'default')::integer,
      v_rule.points_default,
      0
    );
  END IF;

  IF v_points IS NULL OR v_points <= 0 THEN
    RETURN jsonb_build_object('ok', true, 'reason', 'zero_points', 'review_type', v_review_type);
  END IF;

  SELECT * INTO v_existing
  FROM public.stamped_review_award
  WHERE merchant_id = p_merchant_id
    AND review_id = v_review_id
  FOR UPDATE;

  IF v_existing.id IS NOT NULL THEN
    IF v_existing.points_awarded >= v_points THEN
      RETURN jsonb_build_object(
        'ok', true,
        'reason', 'already_awarded',
        'points', v_existing.points_awarded,
        'review_type', v_existing.review_type
      );
    END IF;
    v_delta := v_points - v_existing.points_awarded;
    v_dedup := 'stamped:' || v_review_id || ':to:' || v_points::text;
  ELSE
    v_delta := v_points;
    v_dedup := 'stamped:' || v_review_id;
  END IF;

  BEGIN
    v_ledger_id := public.chokepoint_post_wallet_transaction(
      p_user_id := v_user_id,
      p_currency := 'points',
      p_source_type := 'activity',
      p_component := 'bonus',
      p_transaction_type := 'earn',
      p_amount := v_delta,
      p_transaction_id := v_rule.id,
      p_merchant_id := p_merchant_id,
      p_description := 'Stamped ' || v_review_type || ' review',
      p_metadata := jsonb_build_object(
        'provider', 'stamped',
        'event_key', 'product_review',
        'review_id', v_review_id,
        'review_type', v_review_type,
        'product_external_id', v_product_id
      ),
      p_dedup_key := v_dedup
    );
  EXCEPTION
    WHEN unique_violation THEN
      RETURN jsonb_build_object('ok', true, 'reason', 'dedup');
  END;

  IF v_existing.id IS NULL THEN
    INSERT INTO public.stamped_review_award (
      merchant_id, user_id, review_id, product_external_id,
      review_type, points_awarded, wallet_ledger_ids
    )
    VALUES (
      p_merchant_id, v_user_id, v_review_id, v_product_id,
      v_review_type, v_points, ARRAY[v_ledger_id]
    );
  ELSE
    UPDATE public.stamped_review_award
       SET review_type = v_review_type,
           points_awarded = v_points,
           wallet_ledger_ids = CASE
             WHEN v_ledger_id IS NULL THEN wallet_ledger_ids
             ELSE wallet_ledger_ids || v_ledger_id
           END,
           updated_at = now()
     WHERE id = v_existing.id;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'reason', 'awarded',
    'points', v_delta,
    'total_points', v_points,
    'review_type', v_review_type,
    'user_id', v_user_id
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_integration_stamped_get_connection(p_language text DEFAULT 'en'::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_lang text;
  v_merchant_id uuid;
  v_cred record;
  v_has_key boolean;
  v_shop_domain text;
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error(
      fn_admin_envelope_message('merchant_context_not_found_title', v_lang),
      fn_admin_envelope_message('unable_identify_merchant_token_desc', v_lang)
    );
  END IF;

  SELECT mc.id, mc.is_active, mc.health_status, mc.last_health_check, mc.credentials
    INTO v_cred
    FROM public.merchant_credentials mc
   WHERE mc.merchant_id = v_merchant_id
     AND mc.service_name = 'stamped'
   ORDER BY mc.updated_at DESC NULLS LAST
   LIMIT 1;

  v_has_key := COALESCE(
    NULLIF(TRIM(v_cred.credentials->>'private_api_key'), ''),
    NULLIF(TRIM(v_cred.credentials->>'api_token'), ''),
    ''
  ) <> '';

  v_shop_domain := NULLIF(TRIM(v_cred.credentials->>'shop_domain'), '');
  IF v_shop_domain IS NULL THEN
    SELECT NULLIF(TRIM(sc.credentials->>'shop_domain'), '') INTO v_shop_domain
    FROM public.merchant_credentials sc
    WHERE sc.merchant_id = v_merchant_id
      AND sc.service_name = 'shopify_app'
      AND sc.is_active IS TRUE
    ORDER BY sc.updated_at DESC NULLS LAST
    LIMIT 1;
  END IF;

  RETURN fn_response_success(NULL, NULL, jsonb_build_object(
    'connected', COALESCE(v_cred.is_active, false) AND v_has_key,
    'shop_domain', v_shop_domain,
    'store_hash', NULLIF(TRIM(v_cred.credentials->>'store_hash'), ''),
    'health_status', COALESCE(v_cred.health_status, 'disconnected'),
    'last_health_check', v_cred.last_health_check,
    'credential_id', v_cred.id,
    'webhook_url', NULLIF(TRIM(v_cred.credentials->>'webhook_url'), ''),
    'inbound_webhook_secret', NULLIF(TRIM(v_cred.credentials->>'inbound_webhook_secret'), '')
  ));
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_integration_stamped_disconnect(p_language text DEFAULT 'en'::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_lang text;
  v_merchant_id uuid;
  v_id uuid;
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error(
      fn_admin_envelope_message('merchant_context_not_found_title', v_lang),
      fn_admin_envelope_message('unable_identify_merchant_token_desc', v_lang)
    );
  END IF;

  UPDATE public.merchant_credentials
     SET is_active = false,
         health_status = 'disconnected',
         last_health_check = now(),
         updated_at = now()
   WHERE merchant_id = v_merchant_id
     AND service_name = 'stamped'
     AND is_active IS TRUE
   RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    RETURN fn_response_error('Not connected', 'Stamped is not connected for this merchant');
  END IF;

  PERFORM public.fn_log_admin_bff_write('bff_integration_stamped_disconnect');
  RETURN fn_response_success(
    'Disconnected',
    'Stamped reviews will no longer earn points until you reconnect.',
    jsonb_build_object('credential_id', v_id, 'connected', false)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_upsert_app_event_earn_rule(p_data jsonb, p_language text DEFAULT 'en'::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_lang text;
  v_merchant_id uuid;
  v_provider text;
  v_event_key text;
  v_points_default integer;
  v_earn_limit text;
  v_icon_mode text;
  v_row public.app_event_earn_rule%ROWTYPE;
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error(
      fn_admin_envelope_message('merchant_context_not_found_title', v_lang),
      fn_admin_envelope_message('unable_identify_merchant_token_desc', v_lang)
    );
  END IF;

  v_provider := NULLIF(TRIM(p_data->>'provider'), '');
  v_event_key := NULLIF(TRIM(p_data->>'event_key'), '');
  IF v_provider IS NULL OR v_event_key IS NULL THEN
    RETURN fn_response_error('Invalid request', 'Provider and event are required');
  END IF;

  IF v_provider NOT IN ('judgeme', 'stamped') OR v_event_key NOT IN ('product_review') THEN
    RETURN fn_response_error('Invalid request', 'Unknown app event');
  END IF;

  v_points_default := COALESCE((p_data->>'points_default')::integer, 0);
  IF v_points_default < 0 THEN
    RETURN fn_response_error('Invalid request', 'Points cannot be negative');
  END IF;

  v_earn_limit := COALESCE(NULLIF(TRIM(p_data->>'earn_limit'), ''), 'once_per_product');
  IF v_earn_limit NOT IN ('once_per_product', 'once_lifetime', 'unlimited') THEN
    RETURN fn_response_error('Invalid request', 'Unknown earning limit');
  END IF;

  v_icon_mode := COALESCE(NULLIF(TRIM(p_data->>'icon_mode'), ''), 'default');
  IF v_icon_mode NOT IN ('default', 'custom') THEN
    RETURN fn_response_error('Invalid request', 'Unknown icon mode');
  END IF;

  INSERT INTO public.app_event_earn_rule (
    merchant_id, provider, event_key, is_active, points_default,
    split_by_review_type, split_by_tier, points_by_type, earn_limit, icon_mode, icon_url
  ) VALUES (
    v_merchant_id, v_provider, v_event_key,
    COALESCE((p_data->>'is_active')::boolean, true), v_points_default,
    COALESCE((p_data->>'split_by_review_type')::boolean, false),
    COALESCE((p_data->>'split_by_tier')::boolean, false),
    COALESCE(p_data->'points_by_type', '{}'::jsonb), v_earn_limit, v_icon_mode,
    NULLIF(TRIM(p_data->>'icon_url'), '')
  )
  ON CONFLICT (merchant_id, provider, event_key) DO UPDATE SET
    is_active = EXCLUDED.is_active,
    points_default = EXCLUDED.points_default,
    split_by_review_type = EXCLUDED.split_by_review_type,
    split_by_tier = EXCLUDED.split_by_tier,
    points_by_type = EXCLUDED.points_by_type,
    earn_limit = EXCLUDED.earn_limit,
    icon_mode = EXCLUDED.icon_mode,
    icon_url = EXCLUDED.icon_url,
    updated_at = now()
  RETURNING * INTO v_row;

  PERFORM public.fn_log_admin_bff_write('bff_upsert_app_event_earn_rule');
  RETURN fn_response_success(
    'Saved',
    'Review earning is updated.',
    jsonb_build_object(
      'id', v_row.id,
      'provider', v_row.provider,
      'event_key', v_row.event_key,
      'is_active', v_row.is_active
    )
  );
END;
$function$;
