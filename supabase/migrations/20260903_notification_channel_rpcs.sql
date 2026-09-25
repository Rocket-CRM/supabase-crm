-- Channel-aware notification BFFs + resolver.
-- fn_resolve_notification_for_event gains p_channel DEFAULT 'line' so existing
-- Inngest routers keep working without a deploy.

DROP FUNCTION IF EXISTS public.fn_resolve_notification_for_event(uuid, text, text, uuid, uuid);

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

  -- Log unique is still (merchant, event, sub_event, source) — LINE-only idempotency.
  -- Email send will add channel to this key when the router ships.
  SELECT EXISTS (
    SELECT 1 FROM public.notification_log
     WHERE merchant_id     = p_merchant_id
       AND event_key       = p_event_key
       AND sub_event       = p_sub_event
       AND source_event_id = p_source_event_id
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

CREATE OR REPLACE FUNCTION public.bff_get_notification_settings()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_merchant_id uuid;
  v_rows jsonb;
  v_appearance jsonb;
BEGIN
  v_merchant_id := public.get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN public.fn_response_error('No merchant context', NULL, 'NO_MERCHANT_CONTEXT', NULL);
  END IF;

  SELECT jsonb_agg(row_obj ORDER BY row_obj->>'event_key', row_obj->>'sub_event')
    INTO v_rows
    FROM (
      SELECT jsonb_build_object(
        'event_key',                c.event_key,
        'sub_event',                c.sub_event,
        'source_topic',             c.source_topic,
        'description',              c.description,
        'available_fields',         c.available_fields,
        'template_field_allowlist', public.fn_notification_template_field_allowlist(c.event_key, c.sub_event),
        'line', jsonb_build_object(
          'default_enabled',         c.default_enabled,
          'enabled',                 COALESCE(ls.enabled, c.default_enabled),
          'default_selected_fields', c.default_selected_fields,
          'selected_fields',         COALESCE(ls.selected_fields, c.default_selected_fields),
          'is_customized',           ls.id IS NOT NULL,
          'default_flex_template',   line_sys.flex_template,
          'flex_template',           line_merch.flex_template,
          'has_custom_template',     line_merch.id IS NOT NULL
        ),
        'email', jsonb_build_object(
          'default_enabled',           c.default_enabled_email,
          'enabled',                   COALESCE(es.enabled, c.default_enabled_email),
          'is_customized',             es.id IS NOT NULL,
          'default_email_template',    email_sys.email_template,
          'email_template',            email_merch.email_template,
          'has_custom_template',       email_merch.id IS NOT NULL
        )
      ) AS row_obj
      FROM public.notification_event_catalog c
      LEFT JOIN public.merchant_notification_settings ls
        ON ls.merchant_id = v_merchant_id
       AND ls.event_key  = c.event_key
       AND ls.sub_event  = c.sub_event
       AND ls.channel    = 'line'
      LEFT JOIN public.merchant_notification_settings es
        ON es.merchant_id = v_merchant_id
       AND es.event_key  = c.event_key
       AND es.sub_event  = c.sub_event
       AND es.channel    = 'email'
      LEFT JOIN public.notification_template line_sys
        ON line_sys.event_key = c.event_key
       AND line_sys.sub_event = c.sub_event
       AND line_sys.merchant_id IS NULL
       AND line_sys.channel = 'line'
       AND line_sys.is_active = true
      LEFT JOIN public.notification_template line_merch
        ON line_merch.event_key = c.event_key
       AND line_merch.sub_event = c.sub_event
       AND line_merch.merchant_id = v_merchant_id
       AND line_merch.channel = 'line'
       AND line_merch.is_active = true
      LEFT JOIN public.notification_template email_sys
        ON email_sys.event_key = c.event_key
       AND email_sys.sub_event = c.sub_event
       AND email_sys.merchant_id IS NULL
       AND email_sys.channel = 'email'
       AND email_sys.is_active = true
      LEFT JOIN public.notification_template email_merch
        ON email_merch.event_key = c.event_key
       AND email_merch.sub_event = c.sub_event
       AND email_merch.merchant_id = v_merchant_id
       AND email_merch.channel = 'email'
       AND email_merch.is_active = true
     WHERE c.is_active = true
    ) q;

  SELECT jsonb_build_object(
    'from_name',     COALESCE(NULLIF(btrim(a.from_name), ''), NULLIF(btrim(m.name), ''), m.merchant_code),
    'logo_url',      COALESCE(a.logo_url, NULLIF(d.logo::text, '')),
    'primary_color', COALESCE(a.primary_color, d.primary_color),
    'is_customized', a.merchant_id IS NOT NULL
  )
    INTO v_appearance
    FROM public.merchant_master m
    LEFT JOIN public.merchant_display_settings d ON d.merchant_id = m.id
    LEFT JOIN public.merchant_notification_appearance a ON a.merchant_id = m.id
   WHERE m.id = v_merchant_id;

  RETURN public.fn_response_success(
    'Notification settings loaded',
    NULL,
    jsonb_build_object(
      'settings', COALESCE(v_rows, '[]'::jsonb),
      'appearance', COALESCE(v_appearance, '{}'::jsonb),
      'system_template_fields', to_jsonb(public.fn_notification_system_template_fields())
    )
  );
EXCEPTION WHEN OTHERS THEN
  RETURN public.fn_response_error('Failed to load notification settings', SQLERRM, 'UNKNOWN', NULL);
END;
$function$;

DROP FUNCTION IF EXISTS public.bff_upsert_notification_settings(jsonb, text);

CREATE OR REPLACE FUNCTION public.bff_upsert_notification_settings(
  p_rows jsonb,
  p_language text DEFAULT 'en'::text,
  p_appearance jsonb DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_merchant_id         uuid;
  v_row                 jsonb;
  v_event_key           text;
  v_sub_event           text;
  v_channel             text;
  v_enabled             boolean;
  v_selected            jsonb;
  v_available           jsonb;
  v_default_enabled     boolean;
  v_default_selected    jsonb;
  v_existing_enabled    boolean;
  v_existing_selected   jsonb;
  v_invalid_fields      text[];
  v_count               integer := 0;
  v_touch_settings      boolean;
  v_touch_template      boolean;
  v_flex_template       jsonb;
  v_email_template      jsonb;
  v_validation          jsonb;
  v_lang                text;
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
  v_merchant_id := public.get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN public.fn_response_error(fn_admin_envelope_message('no_merchant_title', v_lang), NULL, 'NO_MERCHANT_CONTEXT', NULL);
  END IF;

  IF p_appearance IS NOT NULL AND jsonb_typeof(p_appearance) = 'object' THEN
    INSERT INTO public.merchant_notification_appearance (merchant_id, from_name, logo_url, primary_color)
    VALUES (
      v_merchant_id,
      NULLIF(btrim(p_appearance->>'from_name'), ''),
      NULLIF(btrim(p_appearance->>'logo_url'), ''),
      NULLIF(btrim(p_appearance->>'primary_color'), '')
    )
    ON CONFLICT (merchant_id) DO UPDATE SET
      from_name     = EXCLUDED.from_name,
      logo_url      = EXCLUDED.logo_url,
      primary_color = EXCLUDED.primary_color,
      updated_at    = now();
  END IF;

  IF p_rows IS NULL OR jsonb_typeof(p_rows) IS DISTINCT FROM 'array' THEN
    RETURN public.fn_response_error('p_rows must be a JSON array', NULL, 'INVALID_INPUT', NULL);
  END IF;

  IF jsonb_array_length(p_rows) = 0 THEN
    RETURN public.fn_response_success(
      fn_admin_envelope_message('notification_settings_saved_title', v_lang),
      'appearance only',
      jsonb_build_object('count', 0)
    );
  END IF;

  FOR v_row IN SELECT jsonb_array_elements(p_rows)
  LOOP
    v_event_key := v_row->>'event_key';
    v_sub_event := v_row->>'sub_event';
    v_channel := COALESCE(NULLIF(btrim(v_row->>'channel'), ''), 'line');
    v_touch_settings := (v_row ? 'enabled') OR (v_row ? 'selected_fields');
    v_touch_template := (v_row ? 'flex_template') OR (v_row ? 'email_template');

    IF v_event_key IS NULL OR v_sub_event IS NULL THEN
      RETURN public.fn_response_error(
        'Each row requires event_key and sub_event',
        format('Missing in row: %s', v_row::text),
        'INVALID_INPUT', NULL);
    END IF;

    IF v_channel NOT IN ('line', 'email') THEN
      RETURN public.fn_response_error(
        'channel must be line or email',
        format('Event %s.%s', v_event_key, v_sub_event),
        'INVALID_INPUT', NULL);
    END IF;

    IF NOT v_touch_settings AND NOT v_touch_template THEN
      RETURN public.fn_response_error(
        'Each row requires enabled/selected_fields and/or a template',
        format('Event %s.%s', v_event_key, v_sub_event),
        'INVALID_INPUT', NULL);
    END IF;

    SELECT
      c.available_fields,
      CASE WHEN v_channel = 'email' THEN c.default_enabled_email ELSE c.default_enabled END,
      c.default_selected_fields
      INTO v_available, v_default_enabled, v_default_selected
      FROM public.notification_event_catalog c
     WHERE c.event_key = v_event_key
       AND c.sub_event = v_sub_event
       AND c.is_active = true;

    IF v_available IS NULL THEN
      RETURN public.fn_response_error(
        'Unknown notification event',
        format('Event %s.%s not in catalog or inactive', v_event_key, v_sub_event),
        'UNKNOWN_EVENT', NULL);
    END IF;

    SELECT s.enabled, s.selected_fields
      INTO v_existing_enabled, v_existing_selected
      FROM public.merchant_notification_settings s
     WHERE s.merchant_id = v_merchant_id
       AND s.event_key = v_event_key
       AND s.sub_event = v_sub_event
       AND s.channel = v_channel;

    IF v_touch_settings THEN
      IF v_row ? 'enabled' THEN
        v_enabled := (v_row->>'enabled')::boolean;
      ELSE
        v_enabled := COALESCE(v_existing_enabled, v_default_enabled);
      END IF;

      IF v_row ? 'selected_fields' THEN
        v_selected := v_row->'selected_fields';
      ELSE
        v_selected := COALESCE(v_existing_selected, v_default_selected);
      END IF;

      IF jsonb_typeof(v_selected) IS DISTINCT FROM 'array' THEN
        RETURN public.fn_response_error(
          'selected_fields must be a JSON array',
          format('Event %s.%s', v_event_key, v_sub_event),
          'INVALID_INPUT', NULL);
      END IF;

      SELECT array_agg(f.field)
        INTO v_invalid_fields
        FROM jsonb_array_elements_text(v_selected) AS f(field)
       WHERE NOT (v_available ? f.field);

      IF v_invalid_fields IS NOT NULL AND array_length(v_invalid_fields, 1) > 0 THEN
        RETURN public.fn_response_error(
          'Some selected fields are not in the catalog allowlist',
          format('Event %s.%s: invalid %s', v_event_key, v_sub_event, v_invalid_fields::text),
          'INVALID_FIELDS', NULL);
      END IF;

      INSERT INTO public.merchant_notification_settings
        (merchant_id, event_key, sub_event, channel, enabled, selected_fields)
      VALUES
        (v_merchant_id, v_event_key, v_sub_event, v_channel, v_enabled, v_selected)
      ON CONFLICT (merchant_id, event_key, sub_event, channel)
      DO UPDATE SET
        enabled         = EXCLUDED.enabled,
        selected_fields = EXCLUDED.selected_fields,
        updated_at      = now();
    END IF;

    IF v_touch_template AND v_channel = 'line' THEN
      IF v_row->'flex_template' IS NULL OR jsonb_typeof(v_row->'flex_template') = 'null' THEN
        UPDATE public.notification_template
           SET is_active = false,
               updated_at = now()
         WHERE merchant_id = v_merchant_id
           AND event_key = v_event_key
           AND sub_event = v_sub_event
           AND channel = 'line'
           AND is_active = true;
      ELSE
        v_flex_template := v_row->'flex_template';

        IF jsonb_typeof(v_flex_template) IS DISTINCT FROM 'object' THEN
          RETURN public.fn_response_error(
            'flex_template must be a JSON object or null',
            format('Event %s.%s', v_event_key, v_sub_event),
            'INVALID_INPUT', NULL);
        END IF;

        v_validation := public.fn_validate_notification_flex_template(
          v_event_key,
          v_sub_event,
          v_flex_template
        );

        IF COALESCE((v_validation->>'valid')::boolean, false) IS NOT TRUE THEN
          RETURN public.fn_response_error(
            v_validation->>'title',
            v_validation->>'description',
            v_validation->>'error_code',
            NULL);
        END IF;

        UPDATE public.notification_template
           SET flex_template = v_flex_template,
               updated_at = now(),
               is_active = true
         WHERE merchant_id = v_merchant_id
           AND event_key = v_event_key
           AND sub_event = v_sub_event
           AND channel = 'line'
           AND is_active = true;

        IF NOT FOUND THEN
          INSERT INTO public.notification_template
            (merchant_id, event_key, sub_event, channel, flex_template, is_active)
          VALUES
            (v_merchant_id, v_event_key, v_sub_event, 'line', v_flex_template, true);
        END IF;
      END IF;
    END IF;

    IF v_touch_template AND v_channel = 'email' THEN
      IF v_row->'email_template' IS NULL OR jsonb_typeof(v_row->'email_template') = 'null' THEN
        UPDATE public.notification_template
           SET is_active = false,
               updated_at = now()
         WHERE merchant_id = v_merchant_id
           AND event_key = v_event_key
           AND sub_event = v_sub_event
           AND channel = 'email'
           AND is_active = true;
      ELSE
        v_email_template := v_row->'email_template';

        IF jsonb_typeof(v_email_template) IS DISTINCT FROM 'object' THEN
          RETURN public.fn_response_error(
            'email_template must be a JSON object or null',
            format('Event %s.%s', v_event_key, v_sub_event),
            'INVALID_INPUT', NULL);
        END IF;

        v_validation := public.fn_validate_notification_email_template(
          v_event_key,
          v_sub_event,
          v_email_template
        );

        IF COALESCE((v_validation->>'valid')::boolean, false) IS NOT TRUE THEN
          RETURN public.fn_response_error(
            v_validation->>'title',
            v_validation->>'description',
            v_validation->>'error_code',
            NULL);
        END IF;

        UPDATE public.notification_template
           SET email_template = v_email_template,
               updated_at = now(),
               is_active = true
         WHERE merchant_id = v_merchant_id
           AND event_key = v_event_key
           AND sub_event = v_sub_event
           AND channel = 'email'
           AND is_active = true;

        IF NOT FOUND THEN
          INSERT INTO public.notification_template
            (merchant_id, event_key, sub_event, channel, email_template, is_active)
          VALUES
            (v_merchant_id, v_event_key, v_sub_event, 'email', v_email_template, true);
        END IF;
      END IF;
    END IF;

    v_count := v_count + 1;
  END LOOP;

  RETURN public.fn_response_success(
    fn_admin_envelope_message('notification_settings_saved_title', v_lang),
    format('%s rows', v_count),
    jsonb_build_object('count', v_count)
  );
EXCEPTION WHEN OTHERS THEN
  RETURN public.fn_response_error(fn_admin_envelope_message('notification_settings_failed_title', v_lang), SQLERRM, 'UNKNOWN', NULL);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.bff_get_notification_settings() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_upsert_notification_settings(jsonb, text, jsonb) TO authenticated, service_role;
