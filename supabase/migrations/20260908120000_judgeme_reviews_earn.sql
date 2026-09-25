-- Judge.me reviews → points.
-- Connect stores a private API token; earn config lives on app_event_earn_rule;
-- inbound webhooks call fn_award_judgeme_review.

-- ---------------------------------------------------------------------------
-- Type master
-- ---------------------------------------------------------------------------

INSERT INTO public.integration_type_master (
  integration_key, display_name, description,
  platform_key, platform_name, platform_order,
  public_fields, sensitive_fields
)
SELECT
  'judgeme',
  'Judge.me',
  'Reward customers with points when they write a product review.',
  'judgeme',
  'Judge.me',
  7,
  ARRAY['shop_domain']::text[],
  ARRAY['api_token']::text[]
WHERE NOT EXISTS (
  SELECT 1
  FROM public.integration_type_master existing
  WHERE existing.integration_key = 'judgeme'
);

INSERT INTO public.integration_field_definitions (
  integration_type_id, field_path, field_name, data_type, is_required,
  expose_in_public_api, display_title, input_type, select_options,
  group_key, group_name, group_order, field_order
)
SELECT
  t.id,
  'judgeme.api_token',
  'api_token',
  'string',
  true,
  false,
  'Private API token',
  'password',
  NULL::jsonb,
  'connection',
  'Connection',
  0,
  0
FROM public.integration_type_master t
WHERE t.integration_key = 'judgeme'
  AND NOT EXISTS (
    SELECT 1
    FROM public.integration_field_definitions existing
    WHERE existing.integration_type_id = t.id
      AND existing.field_name = 'api_token'
  );

CREATE UNIQUE INDEX IF NOT EXISTS merchant_credentials_one_judgeme_uidx
  ON public.merchant_credentials (merchant_id)
  WHERE service_name = 'judgeme';

-- ---------------------------------------------------------------------------
-- Earn rule + award ledger
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.app_event_earn_rule (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES public.merchant_master(id),
  provider text NOT NULL,
  event_key text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  points_default integer NOT NULL DEFAULT 0 CHECK (points_default >= 0),
  split_by_review_type boolean NOT NULL DEFAULT false,
  split_by_tier boolean NOT NULL DEFAULT false,
  points_by_type jsonb NOT NULL DEFAULT '{}'::jsonb,
  earn_limit text NOT NULL DEFAULT 'once_per_product'
    CHECK (earn_limit IN ('once_per_product', 'once_lifetime', 'unlimited')),
  icon_mode text NOT NULL DEFAULT 'default'
    CHECK (icon_mode IN ('default', 'custom')),
  icon_url text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (merchant_id, provider, event_key)
);

CREATE INDEX IF NOT EXISTS app_event_earn_rule_merchant_idx
  ON public.app_event_earn_rule (merchant_id);

ALTER TABLE public.app_event_earn_rule ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS merchant_isolation ON public.app_event_earn_rule;
CREATE POLICY merchant_isolation ON public.app_event_earn_rule
  FOR ALL
  USING (merchant_id = get_current_merchant_id())
  WITH CHECK (merchant_id = get_current_merchant_id());

DROP TRIGGER IF EXISTS trigger_set_updated_at ON public.app_event_earn_rule;
CREATE TRIGGER trigger_set_updated_at
  BEFORE UPDATE ON public.app_event_earn_rule
  FOR EACH ROW
  EXECUTE FUNCTION public.trigger_set_updated_at();

CREATE TABLE IF NOT EXISTS public.judgeme_review_award (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES public.merchant_master(id),
  user_id uuid NOT NULL,
  review_id text NOT NULL,
  product_external_id text,
  review_type text NOT NULL CHECK (review_type IN ('text', 'photo', 'video')),
  points_awarded integer NOT NULL DEFAULT 0,
  wallet_ledger_ids uuid[] NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (merchant_id, review_id)
);

CREATE INDEX IF NOT EXISTS judgeme_review_award_user_product_idx
  ON public.judgeme_review_award (merchant_id, user_id, product_external_id);

ALTER TABLE public.judgeme_review_award ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS merchant_isolation ON public.judgeme_review_award;
CREATE POLICY merchant_isolation ON public.judgeme_review_award
  FOR ALL
  USING (merchant_id = get_current_merchant_id())
  WITH CHECK (merchant_id = get_current_merchant_id());

DROP TRIGGER IF EXISTS trigger_set_updated_at ON public.judgeme_review_award;
CREATE TRIGGER trigger_set_updated_at
  BEFORE UPDATE ON public.judgeme_review_award
  FOR EACH ROW
  EXECUTE FUNCTION public.trigger_set_updated_at();

REVOKE ALL ON TABLE public.app_event_earn_rule FROM PUBLIC, anon;
REVOKE ALL ON TABLE public.judgeme_review_award FROM PUBLIC, anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.app_event_earn_rule
  TO authenticated, service_role;
GRANT SELECT, INSERT, UPDATE ON TABLE public.judgeme_review_award
  TO service_role;

-- ---------------------------------------------------------------------------
-- Connection RPCs
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.bff_integration_judgeme_get_connection(
  p_language text DEFAULT 'en'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_lang text;
  v_merchant_id uuid;
  v_cred record;
  v_has_token boolean;
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

  SELECT
    mc.id,
    mc.is_active,
    mc.health_status,
    mc.last_health_check,
    mc.credentials
  INTO v_cred
  FROM public.merchant_credentials mc
  WHERE mc.merchant_id = v_merchant_id
    AND mc.service_name = 'judgeme'
  ORDER BY mc.updated_at DESC NULLS LAST
  LIMIT 1;

  v_has_token := COALESCE(NULLIF(TRIM(v_cred.credentials->>'api_token'), ''), '') <> '';

  v_shop_domain := NULLIF(TRIM(v_cred.credentials->>'shop_domain'), '');
  IF v_shop_domain IS NULL THEN
    SELECT NULLIF(TRIM(sc.credentials->>'shop_domain'), '')
    INTO v_shop_domain
    FROM public.merchant_credentials sc
    WHERE sc.merchant_id = v_merchant_id
      AND sc.service_name = 'shopify_app'
      AND sc.is_active IS TRUE
    ORDER BY sc.updated_at DESC NULLS LAST
    LIMIT 1;
  END IF;

  IF v_shop_domain IS NULL THEN
    SELECT NULLIF(TRIM(mm.merchant_code), '')
    INTO v_shop_domain
    FROM public.merchant_master mm
    WHERE mm.id = v_merchant_id
      AND mm.merchant_code ILIKE '%.myshopify.com';
  END IF;

  RETURN fn_response_success(
    NULL,
    NULL,
    jsonb_build_object(
      'connected', COALESCE(v_cred.is_active, false) AND v_has_token,
      'shop_domain', v_shop_domain,
      'health_status', COALESCE(v_cred.health_status, 'disconnected'),
      'last_health_check', v_cred.last_health_check,
      'credential_id', v_cred.id
    )
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_integration_judgeme_disconnect(
  p_language text DEFAULT 'en'::text
)
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
     AND service_name = 'judgeme'
     AND is_active IS TRUE
   RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    RETURN fn_response_error('Not connected', 'Judge.me is not connected for this merchant');
  END IF;

  RETURN fn_response_success(
    'Disconnected',
    'Judge.me reviews will no longer earn points until you reconnect.',
    jsonb_build_object('credential_id', v_id, 'connected', false)
  );
END;
$function$;

-- ---------------------------------------------------------------------------
-- Earn-rule RPCs
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.bff_list_app_event_earn_rules(
  p_language text DEFAULT 'en'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_lang text;
  v_merchant_id uuid;
  v_rows jsonb;
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error(
      fn_admin_envelope_message('merchant_context_not_found_title', v_lang),
      fn_admin_envelope_message('unable_identify_merchant_token_desc', v_lang)
    );
  END IF;

  SELECT COALESCE(jsonb_agg(row_to_json(r)::jsonb ORDER BY r.created_at), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT
      id,
      provider,
      event_key,
      is_active,
      points_default,
      split_by_review_type,
      split_by_tier,
      points_by_type,
      earn_limit,
      icon_mode,
      icon_url,
      created_at,
      updated_at
    FROM public.app_event_earn_rule
    WHERE merchant_id = v_merchant_id
  ) r;

  RETURN fn_response_success(NULL, NULL, jsonb_build_object('rules', v_rows));
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_get_app_event_earn_rule(
  p_provider text,
  p_event_key text,
  p_language text DEFAULT 'en'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_lang text;
  v_merchant_id uuid;
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

  IF COALESCE(NULLIF(TRIM(p_provider), ''), '') = ''
     OR COALESCE(NULLIF(TRIM(p_event_key), ''), '') = '' THEN
    RETURN fn_response_error('Invalid request', 'Provider and event are required');
  END IF;

  SELECT * INTO v_row
  FROM public.app_event_earn_rule
  WHERE merchant_id = v_merchant_id
    AND provider = p_provider
    AND event_key = p_event_key;

  IF v_row.id IS NULL THEN
    RETURN fn_response_success(
      NULL,
      NULL,
      jsonb_build_object('rule', NULL)
    );
  END IF;

  RETURN fn_response_success(
    NULL,
    NULL,
    jsonb_build_object(
      'rule', jsonb_build_object(
        'id', v_row.id,
        'provider', v_row.provider,
        'event_key', v_row.event_key,
        'is_active', v_row.is_active,
        'points_default', v_row.points_default,
        'split_by_review_type', v_row.split_by_review_type,
        'split_by_tier', v_row.split_by_tier,
        'points_by_type', v_row.points_by_type,
        'earn_limit', v_row.earn_limit,
        'icon_mode', v_row.icon_mode,
        'icon_url', v_row.icon_url
      )
    )
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_upsert_app_event_earn_rule(
  p_data jsonb,
  p_language text DEFAULT 'en'::text
)
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

  IF v_provider NOT IN ('judgeme') OR v_event_key NOT IN ('product_review') THEN
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
    split_by_review_type, split_by_tier, points_by_type, earn_limit,
    icon_mode, icon_url
  )
  VALUES (
    v_merchant_id,
    v_provider,
    v_event_key,
    COALESCE((p_data->>'is_active')::boolean, true),
    v_points_default,
    COALESCE((p_data->>'split_by_review_type')::boolean, false),
    COALESCE((p_data->>'split_by_tier')::boolean, false),
    COALESCE(p_data->'points_by_type', '{}'::jsonb),
    v_earn_limit,
    v_icon_mode,
    NULLIF(TRIM(p_data->>'icon_url'), '')
  )
  ON CONFLICT (merchant_id, provider, event_key) DO UPDATE
    SET is_active = EXCLUDED.is_active,
        points_default = EXCLUDED.points_default,
        split_by_review_type = EXCLUDED.split_by_review_type,
        split_by_tier = EXCLUDED.split_by_tier,
        points_by_type = EXCLUDED.points_by_type,
        earn_limit = EXCLUDED.earn_limit,
        icon_mode = EXCLUDED.icon_mode,
        icon_url = EXCLUDED.icon_url,
        updated_at = now()
  RETURNING * INTO v_row;

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

CREATE OR REPLACE FUNCTION public.bff_delete_app_event_earn_rule(
  p_rule_id uuid,
  p_language text DEFAULT 'en'::text
)
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

  DELETE FROM public.app_event_earn_rule
   WHERE id = p_rule_id
     AND merchant_id = v_merchant_id
   RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    RETURN fn_response_error('Not found', 'That earning rule does not exist');
  END IF;

  RETURN fn_response_success('Deleted', 'Review earning was removed.', jsonb_build_object('id', v_id));
END;
$function$;

-- ---------------------------------------------------------------------------
-- Award path (service_role / webhook)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_award_judgeme_review(
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
  v_review jsonb;
  v_review_id text;
  v_email text;
  v_external_id text;
  v_product_id text;
  v_hidden boolean;
  v_review_type text;
  v_rule public.app_event_earn_rule%ROWTYPE;
  v_user_id uuid;
  v_points integer := 0;
  v_type_cfg jsonb;
  v_existing public.judgeme_review_award%ROWTYPE;
  v_delta integer;
  v_ledger_id uuid;
  v_dedup text;
  v_event text;
BEGIN
  IF p_merchant_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'missing_merchant');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.merchant_credentials
    WHERE merchant_id = p_merchant_id
      AND service_name = 'judgeme'
      AND is_active IS TRUE
      AND COALESCE(NULLIF(TRIM(credentials->>'api_token'), ''), '') <> ''
  ) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_connected');
  END IF;

  v_event := COALESCE(NULLIF(TRIM(p_event_key), ''), p_payload->>'key', '');
  IF v_event = 'review/unpublished' THEN
    RETURN jsonb_build_object('ok', true, 'reason', 'unpublished_skipped');
  END IF;

  v_review := COALESCE(p_payload->'review', p_payload);
  IF v_review IS NULL OR jsonb_typeof(v_review) <> 'object' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'missing_review');
  END IF;

  v_review_id := NULLIF(TRIM(v_review->>'id'), '');
  IF v_review_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'missing_review_id');
  END IF;

  v_hidden := COALESCE((v_review->>'hidden')::boolean, false);
  IF v_hidden THEN
    RETURN jsonb_build_object('ok', true, 'reason', 'hidden_skipped');
  END IF;

  IF COALESCE(v_review->>'has_published_videos', 'false') IN ('true', 't') THEN
    v_review_type := 'video';
  ELSIF COALESCE(v_review->>'has_published_pictures', 'false') IN ('true', 't') THEN
    v_review_type := 'photo';
  ELSE
    v_review_type := 'text';
  END IF;

  SELECT * INTO v_rule
  FROM public.app_event_earn_rule
  WHERE merchant_id = p_merchant_id
    AND provider = 'judgeme'
    AND event_key = 'product_review'
    AND is_active IS TRUE;

  IF v_rule.id IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'reason', 'rule_inactive');
  END IF;

  v_email := NULLIF(TRIM(COALESCE(v_review->'reviewer'->>'email', v_review->>'email')), '');
  v_external_id := NULLIF(TRIM(COALESCE(
    v_review->'reviewer'->>'external_id',
    v_review->>'customer_external_id'
  )), '');
  v_product_id := NULLIF(TRIM(COALESCE(
    v_review->>'product_external_id',
    v_review->>'product_id'
  )), '');

  v_user_id := public.fn_match_marketplace_user(
    p_merchant_id,
    'shopify',
    v_external_id,
    v_email,
    NULL
  );
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'reason', 'member_not_found');
  END IF;

  IF v_rule.earn_limit = 'once_lifetime' THEN
    IF EXISTS (
      SELECT 1
      FROM public.judgeme_review_award a
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
      FROM public.judgeme_review_award a
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
  FROM public.judgeme_review_award
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
    v_dedup := 'judgeme:' || v_review_id || ':to:' || v_points::text;
  ELSE
    v_delta := v_points;
    v_dedup := 'judgeme:' || v_review_id;
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
      p_description := 'Judge.me ' || v_review_type || ' review',
      p_metadata := jsonb_build_object(
        'provider', 'judgeme',
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
    INSERT INTO public.judgeme_review_award (
      merchant_id, user_id, review_id, product_external_id,
      review_type, points_awarded, wallet_ledger_ids
    )
    VALUES (
      p_merchant_id, v_user_id, v_review_id, v_product_id,
      v_review_type, v_points, ARRAY[v_ledger_id]
    );
  ELSE
    UPDATE public.judgeme_review_award
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

REVOKE ALL ON FUNCTION public.bff_integration_judgeme_get_connection(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.bff_integration_judgeme_disconnect(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.bff_list_app_event_earn_rules(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.bff_get_app_event_earn_rule(text, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.bff_upsert_app_event_earn_rule(jsonb, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.bff_delete_app_event_earn_rule(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_award_judgeme_review(uuid, text, jsonb) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.bff_integration_judgeme_get_connection(text)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_integration_judgeme_disconnect(text)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_list_app_event_earn_rules(text)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_get_app_event_earn_rule(text, text, text)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_upsert_app_event_earn_rule(jsonb, text)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_delete_app_event_earn_rule(uuid, text)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_award_judgeme_review(uuid, text, jsonb)
  TO service_role;
