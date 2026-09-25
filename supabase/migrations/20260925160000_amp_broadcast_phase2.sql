-- AMP targeted broadcast Phase 2: attribution, LINE stats, clicker audiences, broadcast postbacks

ALTER TABLE public.amp_engagement_event
  ADD COLUMN IF NOT EXISTS broadcast_id uuid REFERENCES public.amp_broadcast_master(id) ON DELETE SET NULL;

ALTER TABLE public.amp_broadcast_master
  ADD COLUMN IF NOT EXISTS line_request_id text,
  ADD COLUMN IF NOT EXISTS line_stats jsonb NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE public.amp_broadcast_batch
  ADD COLUMN IF NOT EXISTS line_request_id text;

CREATE INDEX IF NOT EXISTS amp_engagement_event_broadcast_event_idx
  ON public.amp_engagement_event (broadcast_id, event_type)
  WHERE broadcast_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS amp_engagement_event_broadcast_session_dedupe_idx
  ON public.amp_engagement_event (broadcast_id, user_id, session_id, event_type)
  WHERE broadcast_id IS NOT NULL
    AND user_id IS NOT NULL
    AND session_id IS NOT NULL
    AND event_type IN ('page_view', 'scroll_depth');

CREATE OR REPLACE FUNCTION public.fn_amp_record_broadcast_beacon(
  p_broadcast_id uuid,
  p_user_id uuid,
  p_session_id text,
  p_events jsonb,
  p_user_agent text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_broadcast RECORD;
  v_merchant_id uuid;
  v_ev jsonb;
  v_type text;
  v_value numeric;
  v_inserted int := 0;
  v_session text;
BEGIN
  IF p_broadcast_id IS NULL OR p_user_id IS NULL OR p_events IS NULL OR jsonb_typeof(p_events) <> 'array' THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_params');
  END IF;

  SELECT id, merchant_id INTO v_broadcast
  FROM amp_broadcast_master
  WHERE id = p_broadcast_id;
  IF v_broadcast.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'broadcast_not_found');
  END IF;

  SELECT ua.merchant_id INTO v_merchant_id
  FROM user_accounts ua
  WHERE ua.id = p_user_id;
  IF v_merchant_id IS NULL OR v_merchant_id <> v_broadcast.merchant_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'merchant_mismatch');
  END IF;

  v_session := nullif(left(coalesce(p_session_id, ''), 64), '');

  FOR v_ev IN SELECT * FROM jsonb_array_elements(p_events) LIMIT 20
  LOOP
    v_type := v_ev->>'type';
    IF v_type NOT IN ('page_view', 'page_time', 'scroll_depth') THEN
      CONTINUE;
    END IF;
    v_value := NULL;
    IF (v_ev ? 'value') AND jsonb_typeof(v_ev->'value') = 'number' THEN
      v_value := (v_ev->>'value')::numeric;
      IF v_type = 'page_time' THEN
        v_value := LEAST(GREATEST(v_value, 0), 86400);
      ELSIF v_type = 'scroll_depth' THEN
        v_value := LEAST(GREATEST(v_value, 0), 100);
      END IF;
    END IF;

    IF v_type = 'page_time' THEN
      UPDATE amp_engagement_event e
      SET value = GREATEST(coalesce(e.value, 0), coalesce(v_value, 0))
      WHERE e.broadcast_id = p_broadcast_id
        AND e.user_id = p_user_id
        AND e.session_id IS NOT DISTINCT FROM v_session
        AND e.event_type = 'page_time';
      IF NOT FOUND THEN
        INSERT INTO amp_engagement_event (
          token, event_type, value, session_id, merchant_id, user_id, broadcast_id, user_agent
        ) VALUES (
          NULL, v_type, v_value, v_session, v_broadcast.merchant_id, p_user_id, p_broadcast_id,
          nullif(left(coalesce(p_user_agent, ''), 500), '')
        );
      END IF;
      v_inserted := v_inserted + 1;
    ELSE
      INSERT INTO amp_engagement_event (
        token, event_type, value, session_id, merchant_id, user_id, broadcast_id, user_agent
      ) VALUES (
        NULL, v_type, v_value, v_session, v_broadcast.merchant_id, p_user_id, p_broadcast_id,
        nullif(left(coalesce(p_user_agent, ''), 500), '')
      )
      ON CONFLICT (broadcast_id, user_id, session_id, event_type)
        WHERE broadcast_id IS NOT NULL
          AND user_id IS NOT NULL
          AND session_id IS NOT NULL
          AND event_type IN ('page_view', 'scroll_depth')
      DO UPDATE SET value = CASE
        WHEN EXCLUDED.event_type = 'scroll_depth' THEN GREATEST(coalesce(amp_engagement_event.value, 0), coalesce(EXCLUDED.value, 0))
        ELSE amp_engagement_event.value
      END;
      v_inserted := v_inserted + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'inserted', v_inserted);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_amp_record_broadcast_beacon(uuid, uuid, text, jsonb, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_amp_record_broadcast_beacon(uuid, uuid, text, jsonb, text) TO service_role, authenticated;

CREATE OR REPLACE FUNCTION public.fn_amp_record_broadcast_postback(
  p_merchant_id uuid,
  p_line_user_id text,
  p_webhook_event_id text,
  p_broadcast_id uuid,
  p_action_key text,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_broadcast RECORD;
  v_user_id uuid;
  v_dedupe_key text;
  v_event_id uuid;
  v_existing_id uuid;
  v_meta jsonb;
BEGIN
  IF p_merchant_id IS NULL OR nullif(p_line_user_id, '') IS NULL OR nullif(p_webhook_event_id, '') IS NULL
     OR p_broadcast_id IS NULL OR nullif(p_action_key, '') IS NULL THEN
    RETURN jsonb_build_object('accepted', false, 'reason', 'invalid_params');
  END IF;

  IF length(p_action_key) > 64 THEN
    RETURN jsonb_build_object('accepted', false, 'reason', 'action_key_too_long');
  END IF;

  SELECT id, merchant_id, sent_at INTO v_broadcast
  FROM amp_broadcast_master
  WHERE id = p_broadcast_id
  FOR UPDATE;

  IF v_broadcast.id IS NULL THEN
    RETURN jsonb_build_object('accepted', false, 'reason', 'broadcast_not_found');
  END IF;
  IF v_broadcast.merchant_id <> p_merchant_id THEN
    RETURN jsonb_build_object('accepted', false, 'reason', 'merchant_mismatch');
  END IF;
  IF v_broadcast.sent_at IS NOT NULL AND v_broadcast.sent_at < now() - interval '90 days' THEN
    RETURN jsonb_build_object('accepted', false, 'reason', 'broadcast_expired');
  END IF;

  SELECT id INTO v_existing_id
  FROM amp_engagement_event
  WHERE webhook_event_id = p_webhook_event_id
  LIMIT 1;
  IF v_existing_id IS NOT NULL THEN
    RETURN jsonb_build_object('accepted', false, 'reason', 'duplicate_webhook', 'engagement_event_id', v_existing_id);
  END IF;

  v_dedupe_key := p_merchant_id::text || '|bc|' || p_broadcast_id::text || '|' || p_line_user_id || '|' || p_action_key;

  SELECT id INTO v_existing_id
  FROM amp_engagement_event
  WHERE dedupe_key = v_dedupe_key AND event_type = 'postback'
  LIMIT 1;
  IF v_existing_id IS NOT NULL THEN
    RETURN jsonb_build_object('accepted', false, 'reason', 'duplicate_selection', 'engagement_event_id', v_existing_id);
  END IF;

  v_user_id := public.fn_amp_resolve_user_by_line_id(p_merchant_id, p_line_user_id);
  v_meta := coalesce(p_metadata, '{}'::jsonb) - 'channel_secret' - 'access_token' - 'signature' - 'raw_body';

  INSERT INTO amp_engagement_event (
    token, event_type, merchant_id, user_id, line_user_id, action_key,
    broadcast_id, webhook_event_id, dedupe_key, metadata
  ) VALUES (
    NULL, 'postback', p_merchant_id, v_user_id, p_line_user_id, p_action_key,
    p_broadcast_id, p_webhook_event_id, v_dedupe_key, v_meta
  )
  RETURNING id INTO v_event_id;

  RETURN jsonb_build_object(
    'accepted', true,
    'engagement_event_id', v_event_id,
    'merchant_id', p_merchant_id,
    'broadcast_id', p_broadcast_id,
    'action_key', p_action_key,
    'line_user_id', p_line_user_id,
    'user_id', v_user_id,
    'workflow_id', NULL,
    'workflow_log_id', NULL,
    'message_node_id', NULL,
    'route_snapshot', '{}'::jsonb
  );
EXCEPTION
  WHEN unique_violation THEN
    SELECT id INTO v_existing_id FROM amp_engagement_event
    WHERE webhook_event_id = p_webhook_event_id OR dedupe_key = v_dedupe_key
    LIMIT 1;
    RETURN jsonb_build_object('accepted', false, 'reason', 'duplicate_race', 'engagement_event_id', v_existing_id);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_amp_record_broadcast_postback(uuid, text, text, uuid, text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_amp_record_broadcast_postback(uuid, text, text, uuid, text, jsonb) TO service_role;

CREATE OR REPLACE FUNCTION public.bff_amp_refresh_broadcast_line_stats(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_row amp_broadcast_master%ROWTYPE;
  v_base_url text := 'https://messaging-service-li40.onrender.com';
  v_auth text;
  v_req bigint;
  v_resp record;
  v_body jsonb;
  v_stats jsonb := '{}'::jsonb;
  v_date text;
  v_from text;
  v_to text;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error('Error', 'No merchant context', 'NO_MERCHANT_CONTEXT');
  END IF;

  SELECT * INTO v_row FROM amp_broadcast_master WHERE id = p_id AND merchant_id = v_merchant_id;
  IF NOT FOUND THEN
    RETURN fn_response_error('Error', 'Broadcast not found', 'NOT_FOUND');
  END IF;

  v_auth := public.get_messaging_auth_key();
  v_date := to_char(coalesce(v_row.sent_at, now()) AT TIME ZONE 'Asia/Bangkok', 'YYYYMMDD');
  v_from := to_char((coalesce(v_row.sent_at, now()) - interval '1 day') AT TIME ZONE 'Asia/Bangkok', 'YYYYMMDD');
  v_to := to_char((coalesce(v_row.sent_at, now()) + interval '1 day') AT TIME ZONE 'Asia/Bangkok', 'YYYYMMDD');

  IF v_row.audience_type = 'all_line_friends' AND nullif(v_row.line_request_id, '') IS NOT NULL THEN
    v_req := net.http_get(
      v_base_url || '/line/insight/delivery',
      jsonb_build_object('merchant_id', v_merchant_id::text, 'date', v_date, 'request_id', v_row.line_request_id),
      jsonb_build_object('Authorization', 'Bearer ' || v_auth),
      20000
    );
    SELECT * INTO v_resp FROM net.http_collect_response(v_req, false);
    IF v_resp.status_code BETWEEN 200 AND 299 THEN
      v_body := v_resp.body::jsonb;
      v_stats := v_stats || jsonb_build_object('delivery', v_body);
    ELSE
      v_stats := v_stats || jsonb_build_object('delivery_error', coalesce(v_resp.body, v_resp.status_code::text));
    END IF;
  ELSIF v_row.audience_type <> 'all_line_friends' THEN
    v_req := net.http_get(
      v_base_url || '/line/insight/aggregation',
      jsonb_build_object(
        'merchant_id', v_merchant_id::text,
        'unit', p_id::text,
        'from', v_from,
        'to', v_to
      ),
      jsonb_build_object('Authorization', 'Bearer ' || v_auth),
      20000
    );
    SELECT * INTO v_resp FROM net.http_collect_response(v_req, false);
    IF v_resp.status_code BETWEEN 200 AND 299 THEN
      v_body := v_resp.body::jsonb;
      v_stats := v_stats || jsonb_build_object('aggregation', v_body);
    ELSE
      v_stats := v_stats || jsonb_build_object('aggregation_error', coalesce(v_resp.body, v_resp.status_code::text));
    END IF;
  END IF;

  v_stats := v_stats || jsonb_build_object('refreshed_at', now());
  UPDATE amp_broadcast_master SET line_stats = v_stats, updated_at = now() WHERE id = p_id;

  PERFORM public.fn_log_admin_bff_write('bff_amp_refresh_broadcast_line_stats');
  RETURN fn_response_success('Success', NULL, jsonb_build_object('broadcast_id', p_id, 'line_stats', v_stats));
EXCEPTION WHEN OTHERS THEN
  RETURN fn_response_error('Error', SQLERRM, 'ERROR');
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_amp_create_audience_from_broadcast_clickers(
  p_broadcast_id uuid,
  p_name text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_broadcast RECORD;
  v_audience_id uuid;
  v_name text;
  v_count int;
  v_activate jsonb;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error('Error', 'No merchant context', 'NO_MERCHANT_CONTEXT');
  END IF;

  SELECT id, merchant_id, name INTO v_broadcast
  FROM amp_broadcast_master
  WHERE id = p_broadcast_id AND merchant_id = v_merchant_id;
  IF NOT FOUND THEN
    RETURN fn_response_error('Error', 'Broadcast not found', 'NOT_FOUND');
  END IF;

  v_name := coalesce(nullif(trim(p_name), ''), 'Clickers — ' || left(v_broadcast.name, 80));

  INSERT INTO amp_audience_master (
    merchant_id, name, description, audience_type, is_active, member_count, conditions
  ) VALUES (
    v_merchant_id,
    v_name,
    'Members who clicked or opened from broadcast ' || p_broadcast_id::text,
    'static',
    false,
    0,
    '{"groups": []}'::jsonb
  )
  RETURNING id INTO v_audience_id;

  INSERT INTO amp_audience_member (audience_id, user_id, entered_at)
  SELECT DISTINCT v_audience_id, e.user_id, now()
  FROM amp_engagement_event e
  WHERE e.broadcast_id = p_broadcast_id
    AND e.user_id IS NOT NULL
    AND e.event_type IN ('click', 'page_view');

  SELECT count(*)::int INTO v_count
  FROM amp_audience_member am
  WHERE am.audience_id = v_audience_id AND am.exited_at IS NULL;

  UPDATE amp_audience_master
  SET member_count = v_count, updated_at = now()
  WHERE id = v_audience_id;

  v_activate := public.bff_activate_audience(v_audience_id, false, 'en');
  IF coalesce(v_activate->>'success', 'true') <> 'true' THEN
    UPDATE amp_audience_master SET is_active = true, updated_at = now() WHERE id = v_audience_id;
  END IF;

  PERFORM public.fn_log_admin_bff_write('bff_amp_create_audience_from_broadcast_clickers');
  RETURN fn_response_success('Success', NULL, jsonb_build_object(
    'audience_id', v_audience_id,
    'member_count', v_count,
    'name', v_name
  ));
EXCEPTION WHEN OTHERS THEN
  RETURN fn_response_error('Error', SQLERRM, 'ERROR');
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_get_amp_broadcast_details(
  p_id uuid,
  p_mode text DEFAULT 'view'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_row jsonb;
  v_batches jsonb;
  v_engagement jsonb;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error('Error', 'No merchant context', 'NO_MERCHANT_CONTEXT');
  END IF;

  SELECT to_jsonb(b) || jsonb_build_object('audience_name', a.name)
  INTO v_row
  FROM amp_broadcast_master b
  LEFT JOIN amp_audience_master a ON a.id = b.audience_id
  WHERE b.id = p_id AND b.merchant_id = v_merchant_id;

  IF v_row IS NULL THEN
    RETURN fn_response_error('Error', 'Broadcast not found', 'NOT_FOUND');
  END IF;

  SELECT jsonb_build_object(
    'clickers', (
      SELECT count(DISTINCT e.user_id)::int FROM amp_engagement_event e
      WHERE e.broadcast_id = p_id AND e.user_id IS NOT NULL AND e.event_type IN ('click', 'page_view')
    ),
    'viewers', (
      SELECT count(DISTINCT e.user_id)::int FROM amp_engagement_event e
      WHERE e.broadcast_id = p_id AND e.user_id IS NOT NULL AND e.event_type = 'page_view'
    ),
    'postbacks', (
      SELECT count(DISTINCT e.line_user_id)::int FROM amp_engagement_event e
      WHERE e.broadcast_id = p_id AND e.event_type = 'postback'
    )
  ) INTO v_engagement;

  v_row := v_row || jsonb_build_object('engagement_summary', v_engagement);

  IF p_mode = 'results' OR (v_row->>'status') IN ('sent', 'partially_failed', 'failed', 'sending') THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(bb) ORDER BY bb.batch_no), '[]'::jsonb)
    INTO v_batches
    FROM amp_broadcast_batch bb
    WHERE bb.broadcast_id = p_id;
    v_row := v_row || jsonb_build_object('batches', v_batches);
  END IF;

  PERFORM public.fn_log_admin_bff_write('bff_get_amp_broadcast_details');
  RETURN fn_response_success('Success', NULL, jsonb_build_object('broadcast', v_row));
EXCEPTION WHEN OTHERS THEN
  RETURN fn_response_error('Error', SQLERRM, 'ERROR');
END;
$function$;

REVOKE ALL ON FUNCTION public.bff_amp_refresh_broadcast_line_stats(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.bff_amp_create_audience_from_broadcast_clickers(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bff_amp_refresh_broadcast_line_stats(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_amp_create_audience_from_broadcast_clickers(uuid, text) TO authenticated, service_role;
