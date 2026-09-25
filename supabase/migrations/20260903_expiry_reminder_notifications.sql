-- Expiry reminders on the shared notification engine.
-- Clock + remaining-balance scan. Does not subscribe to wallet/redemption expire events.

-- ---------------------------------------------------------------------------
-- 1. Merchant schedule (one row per merchant; lead days stored, not merchant-editable in v1 UI)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.merchant_expiry_reminder_settings (
  merchant_id uuid PRIMARY KEY REFERENCES public.merchant_master(id) ON DELETE CASCADE,
  run_local_time time WITHOUT TIME ZONE NOT NULL DEFAULT '09:00:00',
  timezone text NOT NULL DEFAULT 'Asia/Bangkok',
  points_lead_days integer NOT NULL DEFAULT 7,
  rewards_lead_days integer NOT NULL DEFAULT 3,
  last_ran_local_date date,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT merchant_expiry_reminder_settings_points_lead_chk
    CHECK (points_lead_days BETWEEN 1 AND 30),
  CONSTRAINT merchant_expiry_reminder_settings_rewards_lead_chk
    CHECK (rewards_lead_days BETWEEN 1 AND 30)
);

CREATE INDEX IF NOT EXISTS ix_merchant_expiry_reminder_settings_last_ran
  ON public.merchant_expiry_reminder_settings (last_ran_local_date);

ALTER TABLE public.merchant_expiry_reminder_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS merchant_isolation ON public.merchant_expiry_reminder_settings;
CREATE POLICY merchant_isolation ON public.merchant_expiry_reminder_settings
  FOR ALL USING (merchant_id = get_current_merchant_id());

DROP TRIGGER IF EXISTS set_updated_at_merchant_expiry_reminder_settings
  ON public.merchant_expiry_reminder_settings;
CREATE TRIGGER set_updated_at_merchant_expiry_reminder_settings
  BEFORE UPDATE ON public.merchant_expiry_reminder_settings
  FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

CREATE INDEX IF NOT EXISTS ix_reward_redemptions_use_expire_reminder
  ON public.reward_redemptions_ledger (merchant_id, use_expire_date, id)
  WHERE cancelled IS NOT TRUE
    AND used_status = false
    AND use_expire_date IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 2. Catalog + system Flex templates
-- ---------------------------------------------------------------------------
INSERT INTO public.notification_event_catalog (
  event_key, sub_event, source_topic, description,
  available_fields, default_selected_fields, default_enabled, is_active
) VALUES
  (
    'currency', 'expiring_soon', 'crm.jobs.expiry_reminder',
    'Unused points whose expiry date is exactly N days away (default 7). One message per member per expiry date.',
    '["amount","expiry_date","currency","points_unit_label","lead_days"]'::jsonb,
    '["amount","expiry_date","points_unit_label"]'::jsonb,
    false, true
  ),
  (
    'redemption', 'expiring_soon', 'crm.jobs.expiry_reminder',
    'Unused reward whose use-by date is exactly N days away (default 3). One message per reward (name + code).',
    '["reward_name","redemption_code","use_expire_date","lead_days"]'::jsonb,
    '["reward_name","redemption_code","use_expire_date"]'::jsonb,
    false, true
  )
ON CONFLICT (event_key, sub_event) DO UPDATE SET
  source_topic = EXCLUDED.source_topic,
  description = EXCLUDED.description,
  available_fields = EXCLUDED.available_fields,
  default_selected_fields = EXCLUDED.default_selected_fields,
  is_active = true,
  updated_at = now();

INSERT INTO public.notification_template (
  merchant_id, event_key, sub_event, flex_template, is_active
)
SELECT NULL, 'currency', 'expiring_soon',
  '{
    "type": "bubble",
    "size": "kilo",
    "hero": {
      "type": "image",
      "url": "${hero_image_url}",
      "size": "full",
      "aspectMode": "cover",
      "aspectRatio": "20:13",
      "_field": "hero_image_url"
    },
    "body": {
      "type": "box",
      "layout": "vertical",
      "spacing": "md",
      "contents": [
        {"type": "text", "text": "Points expiring soon", "weight": "bold", "size": "lg"},
        {
          "type": "box",
          "_field": "amount",
          "layout": "baseline",
          "spacing": "sm",
          "contents": [
            {"type": "text", "text": "Amount", "size": "sm", "color": "#666666", "flex": 0},
            {"type": "text", "text": "${amount}", "size": "sm", "wrap": true, "align": "end"}
          ]
        },
        {
          "type": "box",
          "_field": "points_unit_label",
          "layout": "baseline",
          "spacing": "sm",
          "contents": [
            {"type": "text", "text": "Unit", "size": "sm", "color": "#666666", "flex": 0},
            {"type": "text", "text": "${points_unit_label}", "size": "sm", "wrap": true, "align": "end"}
          ]
        },
        {
          "type": "box",
          "_field": "expiry_date",
          "layout": "baseline",
          "spacing": "sm",
          "contents": [
            {"type": "text", "text": "Expires on", "size": "sm", "color": "#666666", "flex": 0},
            {"type": "text", "text": "${expiry_date}", "size": "sm", "wrap": true, "align": "end"}
          ]
        }
      ]
    },
    "footer": {
      "type": "box",
      "_field": "detail_url",
      "layout": "vertical",
      "spacing": "sm",
      "contents": [
        {"type": "button", "style": "primary", "action": {"type": "uri", "label": "View wallet", "uri": "${detail_url}"}}
      ]
    }
  }'::jsonb,
  true
WHERE NOT EXISTS (
  SELECT 1 FROM public.notification_template t
  WHERE t.merchant_id IS NULL AND t.event_key = 'currency' AND t.sub_event = 'expiring_soon' AND t.is_active
);

INSERT INTO public.notification_template (
  merchant_id, event_key, sub_event, flex_template, is_active
)
SELECT NULL, 'redemption', 'expiring_soon',
  '{
    "type": "bubble",
    "size": "kilo",
    "hero": {
      "type": "image",
      "url": "${hero_image_url}",
      "size": "full",
      "aspectMode": "cover",
      "aspectRatio": "20:13",
      "_field": "hero_image_url"
    },
    "body": {
      "type": "box",
      "layout": "vertical",
      "spacing": "md",
      "contents": [
        {"type": "text", "text": "Reward expiring soon", "weight": "bold", "size": "lg"},
        {
          "type": "box",
          "_field": "reward_name",
          "layout": "baseline",
          "spacing": "sm",
          "contents": [
            {"type": "text", "text": "Reward", "size": "sm", "color": "#666666", "flex": 0},
            {"type": "text", "text": "${reward_name}", "size": "sm", "wrap": true, "align": "end"}
          ]
        },
        {
          "type": "box",
          "_field": "redemption_code",
          "layout": "baseline",
          "spacing": "sm",
          "contents": [
            {"type": "text", "text": "Code", "size": "sm", "color": "#666666", "flex": 0},
            {"type": "text", "text": "${redemption_code}", "size": "sm", "wrap": true, "align": "end"}
          ]
        },
        {
          "type": "box",
          "_field": "use_expire_date",
          "layout": "baseline",
          "spacing": "sm",
          "contents": [
            {"type": "text", "text": "Use by", "size": "sm", "color": "#666666", "flex": 0},
            {"type": "text", "text": "${use_expire_date}", "size": "sm", "wrap": true, "align": "end"}
          ]
        }
      ]
    },
    "footer": {
      "type": "box",
      "_field": "detail_url",
      "layout": "vertical",
      "spacing": "sm",
      "contents": [
        {"type": "button", "style": "primary", "action": {"type": "uri", "label": "View reward", "uri": "${detail_url}"}}
      ]
    }
  }'::jsonb,
  true
WHERE NOT EXISTS (
  SELECT 1 FROM public.notification_template t
  WHERE t.merchant_id IS NULL AND t.event_key = 'redemption' AND t.sub_event = 'expiring_soon' AND t.is_active
);

-- ---------------------------------------------------------------------------
-- 3. Idempotency UUID + finder / schedule RPCs (service_role)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_expiry_reminder_source_event_id(
  p_merchant_id uuid,
  p_event_key text,
  p_sub_event text,
  p_user_id uuid,
  p_channel text,
  p_expiry_date date,
  p_lead_days integer,
  p_entitlement_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT md5(concat_ws(
    '|',
    'expiry_reminder',
    p_merchant_id::text,
    p_event_key,
    p_sub_event,
    p_user_id::text,
    lower(COALESCE(p_channel, 'line')),
    p_expiry_date::text,
    p_lead_days::text,
    COALESCE(p_entitlement_id::text, '')
  ))::uuid;
$function$;

CREATE OR REPLACE FUNCTION public.fn_list_due_expiry_reminder_merchants(
  p_now timestamptz DEFAULT now(),
  p_after_merchant_id uuid DEFAULT NULL,
  p_limit integer DEFAULT 50
)
RETURNS TABLE (
  merchant_id uuid,
  timezone text,
  run_local_time time,
  local_date date,
  points_lead_days integer,
  rewards_lead_days integer,
  points_enabled boolean,
  rewards_enabled boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF p_limit IS NULL OR p_limit < 1 THEN
    p_limit := 50;
  END IF;
  IF p_limit > 200 THEN
    p_limit := 200;
  END IF;

  RETURN QUERY
  WITH enabled AS (
    SELECT
      m.id AS merchant_id,
      bool_or(c.event_key = 'currency' AND COALESCE(ns.enabled, c.default_enabled)) AS points_enabled,
      bool_or(c.event_key = 'redemption' AND COALESCE(ns.enabled, c.default_enabled)) AS rewards_enabled
    FROM public.merchant_master m
    JOIN public.notification_event_catalog c
      ON c.is_active = true
     AND c.sub_event = 'expiring_soon'
     AND c.event_key IN ('currency', 'redemption')
    LEFT JOIN public.merchant_notification_settings ns
      ON ns.merchant_id = m.id
     AND ns.event_key = c.event_key
     AND ns.sub_event = c.sub_event
    GROUP BY m.id
  )
  SELECT
    m.id,
    COALESCE(s.timezone, 'Asia/Bangkok')::text,
    COALESCE(s.run_local_time, '09:00:00'::time),
    timezone(COALESCE(s.timezone, 'Asia/Bangkok'), p_now)::date,
    COALESCE(s.points_lead_days, 7),
    COALESCE(s.rewards_lead_days, 3),
    e.points_enabled,
    e.rewards_enabled
  FROM public.merchant_master m
  JOIN enabled e ON e.merchant_id = m.id
  LEFT JOIN public.merchant_expiry_reminder_settings s ON s.merchant_id = m.id
  WHERE (e.points_enabled OR e.rewards_enabled)
    AND EXISTS (
      SELECT 1 FROM pg_timezone_names n
      WHERE n.name = COALESCE(s.timezone, 'Asia/Bangkok')
    )
    AND timezone(COALESCE(s.timezone, 'Asia/Bangkok'), p_now)::time
        >= COALESCE(s.run_local_time, '09:00:00'::time)
    AND s.last_ran_local_date IS DISTINCT FROM
        timezone(COALESCE(s.timezone, 'Asia/Bangkok'), p_now)::date
    AND (p_after_merchant_id IS NULL OR m.id > p_after_merchant_id)
  ORDER BY m.id
  LIMIT p_limit;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_find_points_expiring_soon(
  p_merchant_id uuid,
  p_as_of_date date,
  p_lead_days integer DEFAULT 7,
  p_channel text DEFAULT 'line',
  p_after_user_id uuid DEFAULT NULL,
  p_limit integer DEFAULT 75
)
RETURNS TABLE (
  user_id uuid,
  expiry_date date,
  amount numeric,
  source_event_id uuid,
  points_unit_label text,
  lead_days integer,
  currency text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_target date;
  v_label text;
BEGIN
  IF p_merchant_id IS NULL OR p_as_of_date IS NULL OR p_lead_days IS NULL THEN
    RETURN;
  END IF;
  IF p_limit IS NULL OR p_limit < 1 THEN
    p_limit := 75;
  END IF;
  IF p_limit > 200 THEN
    p_limit := 200;
  END IF;

  v_target := p_as_of_date + p_lead_days;

  SELECT COALESCE(NULLIF(btrim(ds.points_unit_label), ''), 'Points')
    INTO v_label
  FROM public.merchant_display_settings ds
  WHERE ds.merchant_id = p_merchant_id;

  v_label := COALESCE(v_label, 'Points');

  RETURN QUERY
  SELECT
    wl.user_id,
    wl.expiry_date,
    SUM(wl.deductible_balance)::numeric AS amount,
    public.fn_expiry_reminder_source_event_id(
      p_merchant_id, 'currency', 'expiring_soon', wl.user_id,
      p_channel, wl.expiry_date, p_lead_days, NULL
    ) AS source_event_id,
    v_label AS points_unit_label,
    p_lead_days AS lead_days,
    'points'::text AS currency
  FROM public.wallet_ledger wl
  WHERE wl.merchant_id = p_merchant_id
    AND wl.transaction_type = 'earn'::currency_transaction_type
    AND wl.currency = 'points'::currency
    AND wl.expiry_date = v_target
    AND wl.expiry_processed_at IS NULL
    AND COALESCE(wl.deductible_balance, 0) > 0
    AND wl.user_id IS NOT NULL
    AND (p_after_user_id IS NULL OR wl.user_id > p_after_user_id)
  GROUP BY wl.user_id, wl.expiry_date
  HAVING SUM(wl.deductible_balance) > 0
  ORDER BY wl.user_id
  LIMIT p_limit;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_find_rewards_expiring_soon(
  p_merchant_id uuid,
  p_as_of_date date,
  p_timezone text DEFAULT 'Asia/Bangkok',
  p_lead_days integer DEFAULT 3,
  p_channel text DEFAULT 'line',
  p_after_id uuid DEFAULT NULL,
  p_limit integer DEFAULT 75
)
RETURNS TABLE (
  entitlement_id uuid,
  user_id uuid,
  reward_id uuid,
  reward_name text,
  redemption_code text,
  expiry_date date,
  source_event_id uuid,
  lead_days integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_target date;
  v_tz text;
BEGIN
  IF p_merchant_id IS NULL OR p_as_of_date IS NULL OR p_lead_days IS NULL THEN
    RETURN;
  END IF;
  IF p_limit IS NULL OR p_limit < 1 THEN
    p_limit := 75;
  END IF;
  IF p_limit > 200 THEN
    p_limit := 200;
  END IF;

  v_tz := COALESCE(NULLIF(btrim(p_timezone), ''), 'Asia/Bangkok');
  IF NOT EXISTS (SELECT 1 FROM pg_timezone_names n WHERE n.name = v_tz) THEN
    v_tz := 'Asia/Bangkok';
  END IF;

  v_target := p_as_of_date + p_lead_days;

  RETURN QUERY
  SELECT
    r.id AS entitlement_id,
    r.user_id,
    r.reward_id,
    rm.name AS reward_name,
    r.code AS redemption_code,
    timezone(v_tz, r.use_expire_date)::date AS expiry_date,
    public.fn_expiry_reminder_source_event_id(
      p_merchant_id, 'redemption', 'expiring_soon', r.user_id,
      p_channel, timezone(v_tz, r.use_expire_date)::date, p_lead_days, r.id
    ) AS source_event_id,
    p_lead_days AS lead_days
  FROM public.reward_redemptions_ledger r
  LEFT JOIN public.reward_master rm ON rm.id = r.reward_id
  WHERE r.merchant_id = p_merchant_id
    AND r.cancelled IS NOT TRUE
    AND r.used_status = false
    AND COALESCE(r.used_qty, 0) < COALESCE(r.qty, 0)
    AND r.use_expire_date IS NOT NULL
    AND r.user_id IS NOT NULL
    AND timezone(v_tz, r.use_expire_date)::date = v_target
    AND (p_after_id IS NULL OR r.id > p_after_id)
  ORDER BY r.id
  LIMIT p_limit;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_mark_expiry_reminder_ran(
  p_merchant_id uuid,
  p_local_date date
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF p_merchant_id IS NULL OR p_local_date IS NULL THEN
    RETURN;
  END IF;

  INSERT INTO public.merchant_expiry_reminder_settings (
    merchant_id, last_ran_local_date
  ) VALUES (
    p_merchant_id, p_local_date
  )
  ON CONFLICT (merchant_id) DO UPDATE SET
    last_ran_local_date = EXCLUDED.last_ran_local_date,
    updated_at = now();
END;
$function$;

-- ---------------------------------------------------------------------------
-- 4. Admin BFFs
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.bff_get_expiry_reminder_settings()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_row public.merchant_expiry_reminder_settings%ROWTYPE;
BEGIN
  v_merchant_id := public.get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN public.fn_response_error('No merchant context', NULL, 'NO_MERCHANT_CONTEXT', NULL);
  END IF;

  SELECT * INTO v_row
  FROM public.merchant_expiry_reminder_settings
  WHERE merchant_id = v_merchant_id;

  RETURN public.fn_response_success(
    'Expiry reminder schedule loaded',
    NULL,
    jsonb_build_object(
      'run_local_time', COALESCE(v_row.run_local_time, '09:00:00'::time)::text,
      'timezone', COALESCE(v_row.timezone, 'Asia/Bangkok'),
      'points_lead_days', COALESCE(v_row.points_lead_days, 7),
      'rewards_lead_days', COALESCE(v_row.rewards_lead_days, 3),
      'last_ran_local_date', v_row.last_ran_local_date,
      'is_customized', v_row.merchant_id IS NOT NULL
    )
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_upsert_expiry_reminder_settings(
  p_run_local_time time,
  p_timezone text,
  p_language text DEFAULT 'en'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_tz text;
  v_time time;
BEGIN
  v_merchant_id := public.get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN public.fn_response_error('No merchant context', NULL, 'NO_MERCHANT_CONTEXT', NULL);
  END IF;

  v_tz := NULLIF(btrim(COALESCE(p_timezone, '')), '');
  IF v_tz IS NULL THEN
    RETURN public.fn_response_error('Timezone is required', NULL, 'INVALID_INPUT', NULL);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_timezone_names n WHERE n.name = v_tz) THEN
    RETURN public.fn_response_error('Unknown timezone', v_tz, 'INVALID_TIMEZONE', NULL);
  END IF;

  v_time := COALESCE(p_run_local_time, '09:00:00'::time);

  INSERT INTO public.merchant_expiry_reminder_settings (
    merchant_id, run_local_time, timezone
  ) VALUES (
    v_merchant_id, v_time, v_tz
  )
  ON CONFLICT (merchant_id) DO UPDATE SET
    run_local_time = EXCLUDED.run_local_time,
    timezone = EXCLUDED.timezone,
    updated_at = now();

  RETURN public.bff_get_expiry_reminder_settings();
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_expiry_reminder_source_event_id(uuid, text, text, uuid, text, date, integer, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_expiry_reminder_source_event_id(uuid, text, text, uuid, text, date, integer, uuid) TO service_role;

REVOKE ALL ON FUNCTION public.fn_list_due_expiry_reminder_merchants(timestamptz, uuid, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_list_due_expiry_reminder_merchants(timestamptz, uuid, integer) TO service_role;

REVOKE ALL ON FUNCTION public.fn_find_points_expiring_soon(uuid, date, integer, text, uuid, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_find_points_expiring_soon(uuid, date, integer, text, uuid, integer) TO service_role;

REVOKE ALL ON FUNCTION public.fn_find_rewards_expiring_soon(uuid, date, text, integer, text, uuid, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_find_rewards_expiring_soon(uuid, date, text, integer, text, uuid, integer) TO service_role;

REVOKE ALL ON FUNCTION public.fn_mark_expiry_reminder_ran(uuid, date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_mark_expiry_reminder_ran(uuid, date) TO service_role;

GRANT EXECUTE ON FUNCTION public.bff_get_expiry_reminder_settings() TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_upsert_expiry_reminder_settings(time, text, text) TO anon, authenticated, service_role;
