-- Outbound integrations v1: webhook + Klaviyo.
-- Reuses integration_type_master / field_definitions / merchant_credentials.
-- Partner firehose is outbox-cursor based, not Inngest.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.integration_delivery_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES public.merchant_master(id),
  credential_id uuid NOT NULL REFERENCES public.merchant_credentials(id),
  integration_key text NOT NULL,
  outbox_id bigint NOT NULL,
  event_key text NOT NULL,
  status text NOT NULL CHECK (status IN ('delivered', 'failed')),
  attempts integer NOT NULL DEFAULT 1 CHECK (attempts BETWEEN 1 AND 3),
  last_error text,
  response_status integer,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS integration_delivery_log_outbox_cred_uidx
  ON public.integration_delivery_log (outbox_id, credential_id);

CREATE INDEX IF NOT EXISTS integration_delivery_log_merchant_created_idx
  ON public.integration_delivery_log (merchant_id, created_at DESC);

CREATE INDEX IF NOT EXISTS integration_delivery_log_credential_created_idx
  ON public.integration_delivery_log (credential_id, created_at DESC);

ALTER TABLE public.integration_delivery_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY merchant_isolation ON public.integration_delivery_log
  FOR ALL
  USING (merchant_id = get_current_merchant_id());

CREATE TABLE IF NOT EXISTS public.integration_outbox_cursor (
  consumer_key text PRIMARY KEY,
  last_id bigint NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.integration_outbox_cursor ENABLE ROW LEVEL SECURITY;
-- No merchant policy: service_role (bypasses RLS) only.

CREATE TABLE IF NOT EXISTS public.integration_sync_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES public.merchant_master(id),
  integration_key text NOT NULL,
  status text NOT NULL DEFAULT 'queued'
    CHECK (status IN ('queued', 'running', 'done', 'failed')),
  members_total integer,
  members_synced integer NOT NULL DEFAULT 0,
  members_skipped_no_email integer NOT NULL DEFAULT 0,
  last_error text,
  partner_job_ids jsonb NOT NULL DEFAULT '[]'::jsonb,
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS integration_sync_jobs_merchant_created_idx
  ON public.integration_sync_jobs (merchant_id, created_at DESC);

CREATE INDEX IF NOT EXISTS integration_sync_jobs_claim_idx
  ON public.integration_sync_jobs (status, created_at)
  WHERE status IN ('queued', 'running');

ALTER TABLE public.integration_sync_jobs ENABLE ROW LEVEL SECURITY;

CREATE POLICY merchant_isolation ON public.integration_sync_jobs
  FOR ALL
  USING (merchant_id = get_current_merchant_id());

DROP TRIGGER IF EXISTS trigger_set_updated_at ON public.integration_sync_jobs;
CREATE TRIGGER trigger_set_updated_at
  BEFORE UPDATE ON public.integration_sync_jobs
  FOR EACH ROW
  EXECUTE FUNCTION public.trigger_set_updated_at();

INSERT INTO public.integration_outbox_cursor (consumer_key, last_id, updated_at)
SELECT key, COALESCE((SELECT MAX(id) FROM public.chokepoint_event_outbox), 0), now()
FROM (VALUES ('webhook'), ('klaviyo_events')) AS k(key)
ON CONFLICT (consumer_key) DO NOTHING;

CREATE UNIQUE INDEX IF NOT EXISTS merchant_credentials_one_webhook_uidx
  ON public.merchant_credentials (merchant_id)
  WHERE service_name = 'webhook';

CREATE UNIQUE INDEX IF NOT EXISTS merchant_credentials_one_klaviyo_uidx
  ON public.merchant_credentials (merchant_id)
  WHERE service_name = 'klaviyo';

REVOKE ALL ON TABLE public.integration_delivery_log FROM PUBLIC, anon;
REVOKE ALL ON TABLE public.integration_outbox_cursor FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.integration_sync_jobs FROM PUBLIC, anon;

GRANT SELECT, INSERT, UPDATE ON TABLE public.integration_delivery_log TO authenticated, service_role;
GRANT SELECT, INSERT, UPDATE ON TABLE public.integration_outbox_cursor TO service_role;
GRANT SELECT, INSERT, UPDATE ON TABLE public.integration_sync_jobs TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Type master + field definitions
-- ---------------------------------------------------------------------------

INSERT INTO public.integration_type_master (
  integration_key, display_name, description,
  platform_key, platform_name, platform_order,
  public_fields, sensitive_fields
)
SELECT v.integration_key, v.display_name, v.description,
       v.platform_key, v.platform_name, v.platform_order,
       v.public_fields, v.sensitive_fields
FROM (
  VALUES
    (
      'webhook',
      'Custom Webhook',
      'Send canonical loyalty events to an HTTPS endpoint you control.',
      'webhook',
      'Webhook',
      8,
      ARRAY['webhook_url', 'subscribed_events']::text[],
      ARRAY['signing_secret']::text[]
    ),
    (
      'klaviyo',
      'Klaviyo',
      'Sync member profiles and loyalty metrics to Klaviyo via OAuth.',
      'klaviyo',
      'Klaviyo',
      9,
      ARRAY['sync_new_members', 'account_name']::text[],
      ARRAY['access_token', 'refresh_token']::text[]
    )
) AS v(
  integration_key, display_name, description,
  platform_key, platform_name, platform_order,
  public_fields, sensitive_fields
)
WHERE NOT EXISTS (
  SELECT 1
  FROM public.integration_type_master existing
  WHERE existing.integration_key = v.integration_key
);

INSERT INTO public.integration_field_definitions (
  integration_type_id, field_path, field_name, data_type, is_required,
  expose_in_public_api, display_title, input_type, select_options,
  group_key, group_name, group_order, field_order
)
SELECT
  t.id,
  f.field_path,
  f.field_name,
  f.data_type,
  f.is_required,
  f.expose_in_public_api,
  f.display_title,
  f.input_type,
  f.select_options,
  f.group_key,
  f.group_name,
  f.group_order,
  f.field_order
FROM public.integration_type_master t
JOIN (
  VALUES
    (
      'webhook', 'webhook.webhook_url', 'webhook_url', 'string', true, true,
      'Endpoint URL', 'normal', NULL::jsonb,
      'endpoint', 'Endpoint', 0, 0
    ),
    (
      'webhook', 'webhook.signing_secret', 'signing_secret', 'string', true, false,
      'Signing secret', 'password', NULL::jsonb,
      'endpoint', 'Endpoint', 0, 1
    ),
    (
      'webhook', 'webhook.subscribed_events', 'subscribed_events', 'array', false, true,
      'Events', 'multi-select',
      '[{"label":"Points earned","value":"points.earned"},{"label":"Points burned","value":"points.burned"},{"label":"Points expired","value":"points.expired"},{"label":"Points adjusted","value":"points.adjusted"},{"label":"Reward redeemed","value":"reward.redeemed"},{"label":"VIP tier achieved","value":"tier.upgraded"},{"label":"VIP tier downgraded","value":"tier.downgraded"},{"label":"Referral friend claimed","value":"referral.friend_claimed"},{"label":"Referral completed","value":"referral.completed"},{"label":"Member created","value":"member.created"},{"label":"Member updated","value":"member.updated"},{"label":"Birthday reward issued","value":"birthday.reward_issued"}]'::jsonb,
      'events', 'Events', 1, 0
    ),
    (
      'klaviyo', 'klaviyo.sync_new_members', 'sync_new_members', 'boolean', false, true,
      'Sync new members', 'select',
      '[{"label":"On","value":"true"},{"label":"Off","value":"false"}]'::jsonb,
      'settings', 'Settings', 0, 0
    )
) AS f(
  integration_key, field_path, field_name, data_type, is_required,
  expose_in_public_api, display_title, input_type, select_options,
  group_key, group_name, group_order, field_order
) ON t.integration_key = f.integration_key
WHERE NOT EXISTS (
  SELECT 1
  FROM public.integration_field_definitions existing
  WHERE existing.integration_type_id = t.id
    AND existing.field_name = f.field_name
);

-- ---------------------------------------------------------------------------
-- Webhook URL guard (save-time hostname check; send-time resolves DNS)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_integration_webhook_url_is_public(p_url text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO 'public'
AS $function$
DECLARE
  v_host text;
BEGIN
  IF p_url IS NULL OR btrim(p_url) = '' THEN
    RETURN false;
  END IF;
  IF p_url !~* '^https://' THEN
    RETURN false;
  END IF;
  v_host := lower(split_part(split_part(regexp_replace(btrim(p_url), '^https://', ''), '/', 1), ':', 1));
  v_host := regexp_replace(v_host, '^\[|\]$', '', 'g');
  IF v_host IN ('localhost', '127.0.0.1', '::1', '0.0.0.0') THEN
    RETURN false;
  END IF;
  IF v_host LIKE '%.local' OR v_host LIKE '%.internal' OR v_host LIKE '%.localhost' THEN
    RETURN false;
  END IF;
  IF v_host ~ '^10\.'
     OR v_host ~ '^192\.168\.'
     OR v_host ~ '^127\.'
     OR v_host ~ '^169\.254\.'
     OR v_host ~ '^0\.'
     OR v_host ~ '^172\.(1[6-9]|2[0-9]|3[0-1])\.'
     OR v_host ~ '^100\.(6[4-9]|[7-9][0-9]|1[0-1][0-9]|12[0-7])\.' THEN
    RETURN false;
  END IF;
  RETURN true;
END;
$function$;

CREATE OR REPLACE FUNCTION public.trigger_integration_webhook_credential()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.service_name IS DISTINCT FROM 'webhook' THEN
    RETURN NEW;
  END IF;
  IF NEW.credentials ? 'webhook_url'
     AND NOT public.fn_integration_webhook_url_is_public(NEW.credentials->>'webhook_url') THEN
    RAISE EXCEPTION 'Webhook URL must be https and a public host'
      USING ERRCODE = '22023';
  END IF;
  IF TG_OP = 'INSERT'
     OR NEW.credentials IS DISTINCT FROM OLD.credentials THEN
    NEW.health_status := 'connected';
    NEW.last_health_check := now();
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trigger_integration_webhook_credential ON public.merchant_credentials;
CREATE TRIGGER trigger_integration_webhook_credential
  BEFORE INSERT OR UPDATE ON public.merchant_credentials
  FOR EACH ROW
  EXECUTE FUNCTION public.trigger_integration_webhook_credential();

-- ---------------------------------------------------------------------------
-- Internal RPCs
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_integration_resolve_member_snapshot(
  p_merchant_id uuid,
  p_user_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user record;
  v_wallet numeric;
  v_burn jsonb;
  v_burn_rate numeric;
  v_tier jsonb;
  v_expiry_date date;
  v_expiry_amount numeric;
  v_next_reward_cost numeric;
  v_referral_hop text;
  v_referral_url text;
  v_cash numeric;
BEGIN
  IF p_merchant_id IS NULL OR p_user_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT
    ua.id,
    ua.email,
    ua.firstname,
    ua.lastname,
    ua.tel,
    ua.birth_date,
    ua.created_at,
    ua.user_stage,
    ua.user_type,
    ua.member_code,
    ua.tier_id,
    ua.is_freeze,
    ua.is_active,
    ua.deleted_at
  INTO v_user
  FROM public.user_accounts ua
  WHERE ua.id = p_user_id
    AND ua.merchant_id = p_merchant_id;

  IF NOT FOUND OR v_user.deleted_at IS NOT NULL THEN
    RETURN NULL;
  END IF;

  SELECT COALESCE(uw.points_balance, 0)
  INTO v_wallet
  FROM public.user_wallet uw
  WHERE uw.user_id = p_user_id
    AND uw.merchant_id = p_merchant_id;

  v_wallet := COALESCE(v_wallet, 0);

  v_burn := public.fn_resolve_burn_rate(p_merchant_id, v_user.tier_id);
  v_burn_rate := NULLIF(v_burn->>'effective_rate', '')::numeric;
  IF COALESCE((v_burn->>'is_enabled')::boolean, false) AND v_burn_rate IS NOT NULL THEN
    v_cash := round(v_wallet * v_burn_rate, 2);
  END IF;

  v_tier := COALESCE(
    public.fn_get_tier_progress_from_cache(p_user_id, p_merchant_id),
    '{}'::jsonb
  );

  SELECT n.next_expiry_date, n.amount
  INTO v_expiry_date, v_expiry_amount
  FROM public.fn_loyalty_next_expiry_for_user(p_user_id, p_merchant_id) n;

  SELECT MIN(rm.fallback_points)
  INTO v_next_reward_cost
  FROM public.reward_master rm
  WHERE rm.merchant_id = p_merchant_id
    AND rm.active_status IS TRUE
    AND rm.visibility IN ('user'::reward_visibility, 'user_only'::reward_visibility)
    AND rm.fallback_points IS NOT NULL
    AND rm.fallback_points > v_wallet;

  v_referral_hop := public.fn_referral_share_hop(p_merchant_id);
  IF v_referral_hop IS NOT NULL AND NULLIF(btrim(v_user.member_code), '') IS NOT NULL THEN
    v_referral_url := v_referral_hop || '?r=' || btrim(v_user.member_code);
  END IF;

  RETURN jsonb_build_object(
    'user_id', v_user.id,
    'email', v_user.email,
    'first_name', v_user.firstname,
    'last_name', v_user.lastname,
    'phone', v_user.tel,
    'birth_date', v_user.birth_date,
    'joined_at', v_user.created_at,
    'status', v_user.user_stage,
    'user_type', v_user.user_type,
    'member_code', v_user.member_code,
    'is_freeze', COALESCE(v_user.is_freeze, false),
    'is_active', COALESCE(v_user.is_active, true),
    'points_balance', v_wallet,
    'burn_rate', v_burn_rate,
    'points_as_cash', v_cash,
    'current_tier_id', v_tier->'current_tier_id',
    'current_tier_name', v_tier->'current_tier_name',
    'next_tier_id', v_tier->'next_tier_id',
    'next_tier_name', v_tier->'next_tier_name',
    'amount_needed_for_next_tier', v_tier->'amount_to_next_tier',
    'referral_url', to_jsonb(v_referral_url),
    'next_expiry_date', to_jsonb(v_expiry_date),
    'next_expiry_amount', to_jsonb(v_expiry_amount),
    'points_to_next_reward', to_jsonb(
      CASE
        WHEN v_next_reward_cost IS NULL THEN NULL
        ELSE v_next_reward_cost - v_wallet
      END
    )
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_integration_lock_credential(p_credential_id uuid)
RETURNS public.merchant_credentials
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_row public.merchant_credentials;
BEGIN
  SELECT *
  INTO v_row
  FROM public.merchant_credentials
  WHERE id = p_credential_id
  FOR UPDATE;

  RETURN v_row;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_integration_webhook_url_is_public(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_integration_resolve_member_snapshot(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_integration_lock_credential(uuid) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.fn_integration_webhook_url_is_public(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_integration_resolve_member_snapshot(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_integration_lock_credential(uuid) TO service_role;

-- ---------------------------------------------------------------------------
-- Admin BFF RPCs
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.bff_integration_klaviyo_get_connection(
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
  v_job record;
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
    mc.expires_at,
    mc.updated_at,
    mc.credentials
  INTO v_cred
  FROM public.merchant_credentials mc
  WHERE mc.merchant_id = v_merchant_id
    AND mc.service_name = 'klaviyo'
  ORDER BY mc.updated_at DESC NULLS LAST
  LIMIT 1;

  SELECT
    j.id,
    j.status,
    j.members_total,
    j.members_synced,
    j.members_skipped_no_email,
    j.last_error,
    j.started_at,
    j.finished_at,
    j.created_at
  INTO v_job
  FROM public.integration_sync_jobs j
  WHERE j.merchant_id = v_merchant_id
    AND j.integration_key = 'klaviyo'
  ORDER BY j.created_at DESC
  LIMIT 1;

  RETURN fn_response_success(
    NULL,
    NULL,
    jsonb_build_object(
      'connected', COALESCE(v_cred.is_active, false),
      'account_name', v_cred.credentials->>'account_name',
      'health_status', COALESCE(v_cred.health_status, 'disconnected'),
      'last_health_check', v_cred.last_health_check,
      'sync_new_members', COALESCE((v_cred.credentials->>'sync_new_members')::boolean, true),
      'expires_at', v_cred.expires_at,
      'credential_id', v_cred.id,
      'latest_sync_job', CASE
        WHEN v_job.id IS NULL THEN NULL
        ELSE jsonb_build_object(
          'job_id', v_job.id,
          'status', v_job.status,
          'members_total', v_job.members_total,
          'members_synced', v_job.members_synced,
          'members_skipped_no_email', v_job.members_skipped_no_email,
          'last_error', v_job.last_error,
          'started_at', v_job.started_at,
          'finished_at', v_job.finished_at,
          'created_at', v_job.created_at
        )
      END
    )
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_integration_klaviyo_disconnect(
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
    AND service_name = 'klaviyo'
    AND is_active IS TRUE
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    RETURN fn_response_error('Not connected', 'Klaviyo is not connected for this merchant');
  END IF;

  RETURN fn_response_success(
    'Disconnected',
    'Klaviyo writes have stopped. Reconnect with OAuth, then run Sync all to restore profiles.',
    jsonb_build_object('credential_id', v_id, 'connected', false)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_integration_klaviyo_start_sync_all(
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
  v_active boolean;
  v_existing uuid;
  v_job_id uuid;
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error(
      fn_admin_envelope_message('merchant_context_not_found_title', v_lang),
      fn_admin_envelope_message('unable_identify_merchant_token_desc', v_lang)
    );
  END IF;

  SELECT mc.is_active
  INTO v_active
  FROM public.merchant_credentials mc
  WHERE mc.merchant_id = v_merchant_id
    AND mc.service_name = 'klaviyo'
  ORDER BY mc.updated_at DESC NULLS LAST
  LIMIT 1;

  IF COALESCE(v_active, false) IS NOT TRUE THEN
    RETURN fn_response_error('Not connected', 'Connect Klaviyo before running Sync all');
  END IF;

  SELECT j.id
  INTO v_existing
  FROM public.integration_sync_jobs j
  WHERE j.merchant_id = v_merchant_id
    AND j.integration_key = 'klaviyo'
    AND j.status IN ('queued', 'running')
  LIMIT 1;

  IF v_existing IS NOT NULL THEN
    RETURN fn_response_error(
      'Sync already running',
      'Wait for the current Sync all job to finish',
      'SYNC_IN_PROGRESS',
      jsonb_build_object('job_id', v_existing)
    );
  END IF;

  INSERT INTO public.integration_sync_jobs (
    merchant_id, integration_key, status
  ) VALUES (
    v_merchant_id, 'klaviyo', 'queued'
  )
  RETURNING id INTO v_job_id;

  RETURN fn_response_success(
    'Sync queued',
    'Profiles with email will be imported in the background',
    jsonb_build_object('job_id', v_job_id)
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.bff_integration_klaviyo_get_connection(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.bff_integration_klaviyo_disconnect(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.bff_integration_klaviyo_start_sync_all(text) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.bff_integration_klaviyo_get_connection(text)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_integration_klaviyo_disconnect(text)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_integration_klaviyo_start_sync_all(text)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 30-day log purge
-- ---------------------------------------------------------------------------

SELECT cron.schedule(
  'integration_delivery_log_cleanup',
  '15 3 * * *',
  $cron$
    DELETE FROM public.integration_delivery_log
     WHERE created_at < now() - interval '30 days'
  $cron$
)
WHERE NOT EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'integration_delivery_log_cleanup'
);
