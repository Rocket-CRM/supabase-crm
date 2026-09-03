-- Expiry reminders: channel-aware merchant gate.
--
-- fn_list_due_expiry_reminder_merchants gains p_channel DEFAULT 'line'. The
-- caller (Render cron `expiry-reminder-batch`) delivers on one channel per
-- run; a merchant whose expiring_soon events are enabled only on another
-- channel must not reach the finders. Default-enabled falls back to the
-- catalog default for that channel (default_enabled / default_enabled_email).
--
-- The previous signature (p_now, p_after_merchant_id, p_limit) is dropped so
-- PostgREST does not see two overloads.

DROP FUNCTION IF EXISTS public.fn_list_due_expiry_reminder_merchants(timestamptz, uuid, integer);

CREATE OR REPLACE FUNCTION public.fn_list_due_expiry_reminder_merchants(
  p_now timestamptz DEFAULT now(),
  p_after_merchant_id uuid DEFAULT NULL,
  p_limit integer DEFAULT 50,
  p_channel text DEFAULT 'line'
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
DECLARE
  v_channel text;
BEGIN
  IF p_limit IS NULL OR p_limit < 1 THEN
    p_limit := 50;
  END IF;
  IF p_limit > 200 THEN
    p_limit := 200;
  END IF;

  v_channel := lower(COALESCE(NULLIF(btrim(p_channel), ''), 'line'));

  RETURN QUERY
  WITH catalog AS (
    SELECT
      c.event_key,
      CASE WHEN v_channel = 'email' THEN c.default_enabled_email ELSE c.default_enabled END AS default_enabled
    FROM public.notification_event_catalog c
    WHERE c.is_active = true
      AND c.sub_event = 'expiring_soon'
      AND c.event_key IN ('currency', 'redemption')
  ),
  enabled AS (
    SELECT
      m.id AS merchant_id,
      bool_or(cat.event_key = 'currency'   AND COALESCE(ns.enabled, cat.default_enabled)) AS points_enabled,
      bool_or(cat.event_key = 'redemption' AND COALESCE(ns.enabled, cat.default_enabled)) AS rewards_enabled
    FROM public.merchant_master m
    CROSS JOIN catalog cat
    LEFT JOIN public.merchant_notification_settings ns
      ON ns.merchant_id = m.id
     AND ns.event_key = cat.event_key
     AND ns.sub_event = 'expiring_soon'
     AND ns.channel = v_channel
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

REVOKE ALL ON FUNCTION public.fn_list_due_expiry_reminder_merchants(timestamptz, uuid, integer, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_list_due_expiry_reminder_merchants(timestamptz, uuid, integer, text) TO service_role;
