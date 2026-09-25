-- Email last-mile: log unique is per channel so LINE and Email do not block each other.
-- Existing rows default to line. Resolver ALREADY_SENT follows the same key.

ALTER TABLE public.notification_log
  ADD COLUMN IF NOT EXISTS channel text NOT NULL DEFAULT 'line';

ALTER TABLE public.notification_log
  DROP CONSTRAINT IF EXISTS notification_log_channel_check;

ALTER TABLE public.notification_log
  ADD CONSTRAINT notification_log_channel_check
  CHECK (channel IN ('line', 'email', 'sms'));

DROP INDEX IF EXISTS public.uq_notification_log_idempotency;

CREATE UNIQUE INDEX uq_notification_log_idempotency
  ON public.notification_log (merchant_id, event_key, sub_event, source_event_id, channel);

CREATE OR REPLACE FUNCTION public.fn_resolve_notification_for_event(
  p_merchant_id uuid,
  p_event_key text,
  p_sub_event text,
  p_user_id uuid,
  p_source_event_id uuid,
  p_channel text DEFAULT 'line'
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_catalog          public.notification_event_catalog%ROWTYPE;
  v_channel          text;
  v_enabled          boolean;
  v_selected_fields  jsonb;
  v_line_id          text;
  v_channel_line     boolean;
  v_email            text;
  v_channel_email    boolean;
  v_flex_template    jsonb;
  v_email_template   jsonb;
  v_token            text;
  v_already          boolean;
BEGIN
  v_channel := COALESCE(NULLIF(btrim(p_channel), ''), 'line');
  IF v_channel NOT IN ('line', 'email') THEN
    RETURN jsonb_build_object('should_send', false, 'skip_reason', 'INVALID_INPUT', 'channel', v_channel);
  END IF;

  IF p_merchant_id IS NULL OR p_event_key IS NULL OR p_sub_event IS NULL OR p_source_event_id IS NULL THEN
    RETURN jsonb_build_object('should_send', false, 'skip_reason', 'INVALID_INPUT', 'channel', v_channel);
  END IF;

  SELECT * INTO v_catalog
    FROM public.notification_event_catalog
   WHERE event_key = p_event_key
     AND sub_event = p_sub_event
     AND is_active = true;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('should_send', false, 'skip_reason', 'NO_CATALOG', 'channel', v_channel);
  END IF;

  SELECT s.enabled, s.selected_fields
    INTO v_enabled, v_selected_fields
    FROM public.merchant_notification_settings s
   WHERE s.merchant_id = p_merchant_id
     AND s.event_key   = p_event_key
     AND s.sub_event   = p_sub_event
     AND s.channel     = v_channel;

  IF NOT FOUND THEN
    IF v_channel = 'email' THEN
      v_enabled := v_catalog.default_enabled_email;
    ELSE
      v_enabled := v_catalog.default_enabled;
    END IF;
    v_selected_fields := v_catalog.default_selected_fields;
  END IF;

  IF NOT v_enabled THEN
    RETURN jsonb_build_object('should_send', false, 'skip_reason', 'DISABLED', 'channel', v_channel);
  END IF;

  IF p_user_id IS NULL THEN
    RETURN jsonb_build_object('should_send', false, 'skip_reason', 'NO_USER', 'channel', v_channel);
  END IF;

  SELECT u.line_id, COALESCE(u.channel_line, false), u.email, COALESCE(u.channel_email, false)
    INTO v_line_id, v_channel_line, v_email, v_channel_email
    FROM public.user_accounts u
   WHERE u.id = p_user_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('should_send', false, 'skip_reason', 'USER_NOT_FOUND', 'channel', v_channel);
  END IF;

  IF v_channel = 'line' THEN
    IF v_line_id IS NULL OR v_line_id = '' THEN
      RETURN jsonb_build_object('should_send', false, 'skip_reason', 'NO_LINE_ID', 'channel', v_channel);
    END IF;
    IF NOT v_channel_line THEN
      RETURN jsonb_build_object('should_send', false, 'skip_reason', 'USER_CHANNEL_OFF', 'channel', v_channel);
    END IF;
  ELSE
    IF v_email IS NULL OR v_email = '' THEN
      RETURN jsonb_build_object('should_send', false, 'skip_reason', 'NO_EMAIL', 'channel', v_channel);
    END IF;
    IF NOT v_channel_email THEN
      RETURN jsonb_build_object('should_send', false, 'skip_reason', 'USER_CHANNEL_OFF', 'channel', v_channel);
    END IF;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.notification_log
     WHERE merchant_id     = p_merchant_id
       AND event_key       = p_event_key
       AND sub_event       = p_sub_event
       AND source_event_id = p_source_event_id
       AND channel         = v_channel
       AND status          = 'sent'
  ) INTO v_already;

  IF v_already THEN
    RETURN jsonb_build_object('should_send', false, 'skip_reason', 'ALREADY_SENT', 'channel', v_channel);
  END IF;

  IF v_channel = 'line' THEN
    SELECT flex_template INTO v_flex_template
      FROM public.notification_template
     WHERE event_key = p_event_key
       AND sub_event = p_sub_event
       AND is_active = true
       AND channel = 'line'
       AND (merchant_id = p_merchant_id OR merchant_id IS NULL)
     ORDER BY merchant_id NULLS LAST
     LIMIT 1;

    IF v_flex_template IS NULL THEN
      RETURN jsonb_build_object('should_send', false, 'skip_reason', 'NO_TEMPLATE', 'channel', v_channel);
    END IF;

    SELECT credentials->>'messaging_channel_access_token' INTO v_token
      FROM public.merchant_credentials
     WHERE merchant_id = p_merchant_id
       AND is_active = true
       AND service_name IN ('line_messaging', 'line_login')
       AND credentials ? 'messaging_channel_access_token'
     ORDER BY (service_name = 'line_messaging') DESC
     LIMIT 1;

    IF v_token IS NULL THEN
      RETURN jsonb_build_object('should_send', false, 'skip_reason', 'NO_MERCHANT_TOKEN', 'channel', v_channel);
    END IF;

    RETURN jsonb_build_object(
      'should_send',          true,
      'channel',              'line',
      'line_id',              v_line_id,
      'channel_access_token', v_token,
      'flex_template',        v_flex_template,
      'selected_fields',      v_selected_fields,
      'event_key',            p_event_key,
      'sub_event',            p_sub_event,
      'source_topic',         v_catalog.source_topic
    );
  END IF;

  SELECT email_template INTO v_email_template
    FROM public.notification_template
   WHERE event_key = p_event_key
     AND sub_event = p_sub_event
     AND is_active = true
     AND channel = 'email'
     AND (merchant_id = p_merchant_id OR merchant_id IS NULL)
   ORDER BY merchant_id NULLS LAST
   LIMIT 1;

  IF v_email_template IS NULL THEN
    RETURN jsonb_build_object('should_send', false, 'skip_reason', 'NO_TEMPLATE', 'channel', v_channel);
  END IF;

  RETURN jsonb_build_object(
    'should_send',      true,
    'channel',          'email',
    'email',            v_email,
    'email_template',   v_email_template,
    'selected_fields',  v_selected_fields,
    'event_key',        p_event_key,
    'sub_event',        p_sub_event,
    'source_topic',     v_catalog.source_topic
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('should_send', false, 'skip_reason', 'ERROR', 'channel', COALESCE(v_channel, p_channel), 'error', SQLERRM);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_resolve_notification_for_event(uuid, text, text, uuid, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_resolve_notification_for_event(uuid, text, text, uuid, uuid, text) TO service_role;
