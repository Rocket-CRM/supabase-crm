-- Targeted broadcast (Phase 1a) + workflow friend-entry helpers (Phase 1b partial)

CREATE TYPE public.amp_broadcast_status AS ENUM (
  'draft',
  'scheduled',
  'sending',
  'sent',
  'partially_failed',
  'failed',
  'cancelled'
);

CREATE TYPE public.amp_broadcast_audience_type AS ENUM (
  'audience',
  'all_line_friends',
  'line_friends_non_members'
);

CREATE TABLE public.amp_broadcast_master (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES public.merchant_master(id) ON DELETE CASCADE,
  name text NOT NULL,
  audience_type public.amp_broadcast_audience_type NOT NULL,
  audience_id uuid REFERENCES public.amp_audience_master(id) ON DELETE SET NULL,
  message_config jsonb NOT NULL DEFAULT '{}'::jsonb,
  resolved_messages jsonb,
  status public.amp_broadcast_status NOT NULL DEFAULT 'draft',
  scheduled_at timestamptz,
  sent_at timestamptz,
  recipient_count integer NOT NULL DEFAULT 0,
  sent_count integer NOT NULL DEFAULT 0,
  failed_count integer NOT NULL DEFAULT 0,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT amp_broadcast_master_audience_chk CHECK (
    (audience_type = 'audience' AND audience_id IS NOT NULL)
    OR (audience_type <> 'audience' AND audience_id IS NULL)
  )
);

CREATE INDEX amp_broadcast_master_merchant_status_idx
  ON public.amp_broadcast_master (merchant_id, status, updated_at DESC);

CREATE TABLE public.amp_broadcast_batch (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  broadcast_id uuid NOT NULL REFERENCES public.amp_broadcast_master(id) ON DELETE CASCADE,
  batch_no integer NOT NULL,
  line_user_ids text[] NOT NULL DEFAULT '{}'::text[],
  status text NOT NULL DEFAULT 'pending',
  attempt_count integer NOT NULL DEFAULT 0,
  error text,
  sent_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (broadcast_id, batch_no)
);

CREATE INDEX amp_broadcast_batch_broadcast_idx ON public.amp_broadcast_batch (broadcast_id, batch_no);

ALTER TABLE public.amp_broadcast_master ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.amp_broadcast_batch ENABLE ROW LEVEL SECURITY;

CREATE POLICY amp_broadcast_master_select_authenticated ON public.amp_broadcast_master
  FOR SELECT TO authenticated USING (merchant_id = get_current_merchant_id());
CREATE POLICY amp_broadcast_master_insert_authenticated ON public.amp_broadcast_master
  FOR INSERT TO authenticated WITH CHECK (merchant_id = get_current_merchant_id());
CREATE POLICY amp_broadcast_master_update_authenticated ON public.amp_broadcast_master
  FOR UPDATE TO authenticated USING (merchant_id = get_current_merchant_id());
CREATE POLICY amp_broadcast_master_delete_authenticated ON public.amp_broadcast_master
  FOR DELETE TO authenticated USING (merchant_id = get_current_merchant_id());
CREATE POLICY amp_broadcast_master_service_role ON public.amp_broadcast_master
  FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE POLICY amp_broadcast_batch_select_authenticated ON public.amp_broadcast_batch
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.amp_broadcast_master m
    WHERE m.id = broadcast_id AND m.merchant_id = get_current_merchant_id()
  ));
CREATE POLICY amp_broadcast_batch_service_role ON public.amp_broadcast_batch
  FOR ALL TO service_role USING (true) WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.amp_broadcast_master TO authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.amp_broadcast_batch TO authenticated, service_role;

-- Drop LINE friends already enrolled in workflow (re-enrollment off fan-out)
CREATE OR REPLACE FUNCTION public.fn_amp_filter_enrolled_line_ids(
  p_workflow_id uuid,
  p_line_user_ids text[]
)
RETURNS text[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT COALESCE(array_agg(x), ARRAY[]::text[])
  FROM unnest(COALESCE(p_line_user_ids, ARRAY[]::text[])) AS x
  WHERE x IS NOT NULL AND x <> ''
    AND NOT EXISTS (
      SELECT 1 FROM workflow_log wl
      WHERE wl.workflow_id = p_workflow_id
        AND wl.line_user_id = x
        AND wl.event_type = 'execution_started'
    );
$function$;

REVOKE ALL ON FUNCTION public.fn_amp_filter_enrolled_line_ids(uuid, text[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_amp_filter_enrolled_line_ids(uuid, text[]) TO service_role;

CREATE OR REPLACE FUNCTION public.fn_amp_segment_broadcast_line_ids(
  p_merchant_id uuid,
  p_audience_id uuid
)
RETURNS text[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT COALESCE(array_agg(DISTINCT ua.line_id), ARRAY[]::text[])
  FROM amp_audience_member am
  JOIN amp_audience_master a ON a.id = am.audience_id AND a.merchant_id = p_merchant_id
  JOIN user_accounts ua ON ua.id = am.user_id AND ua.merchant_id = p_merchant_id
  WHERE am.audience_id = p_audience_id
    AND am.exited_at IS NULL
    AND ua.line_id IS NOT NULL AND ua.line_id <> ''
    AND COALESCE(ua.channel_line, true) IS NOT FALSE;
$function$;

REVOKE ALL ON FUNCTION public.fn_amp_segment_broadcast_line_ids(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_amp_segment_broadcast_line_ids(uuid, uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.bff_amp_estimate_audience(
  p_audience_type text,
  p_audience_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_total int;
  v_line int;
  v_last_refreshed timestamptz;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error('Error', 'No merchant context', 'NO_MERCHANT_CONTEXT');
  END IF;

  IF p_audience_type = 'audience' THEN
    IF p_audience_id IS NULL THEN
      RETURN fn_response_error('Error', 'audience_id required', 'INVALID_REQUEST');
    END IF;
    SELECT COUNT(*)::int, COUNT(*) FILTER (
      WHERE ua.line_id IS NOT NULL AND ua.line_id <> '' AND COALESCE(ua.channel_line, true) IS NOT FALSE
    )::int
    INTO v_total, v_line
    FROM amp_audience_member am
    JOIN user_accounts ua ON ua.id = am.user_id AND ua.merchant_id = v_merchant_id
    WHERE am.audience_id = p_audience_id AND am.exited_at IS NULL;

    SELECT MAX(am.entered_at) INTO v_last_refreshed
    FROM amp_audience_member am WHERE am.audience_id = p_audience_id;

    RETURN fn_response_success('Success', NULL, jsonb_build_object(
      'audience_type', 'audience',
      'member_count', v_total,
      'line_deliverable_count', v_line,
      'last_refreshed_at', v_last_refreshed
    ));
  END IF;

  IF p_audience_type IN ('all_line_friends', 'line_friends_non_members') THEN
    RETURN fn_response_success('Success', NULL, jsonb_build_object(
      'audience_type', p_audience_type,
      'member_count', NULL,
      'line_deliverable_count', NULL,
      'note', 'Exact LINE friend count is determined when you send.'
    ));
  END IF;

  RETURN fn_response_error('Error', 'Invalid audience_type', 'INVALID_REQUEST');
EXCEPTION WHEN OTHERS THEN
  RETURN fn_response_error('Error', SQLERRM, 'ERROR');
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_list_amp_broadcasts()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_items jsonb;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error('Error', 'No merchant context', 'NO_MERCHANT_CONTEXT');
  END IF;

  SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.updated_at DESC), '[]'::jsonb)
  INTO v_items
  FROM (
    SELECT
      b.id,
      b.name,
      b.audience_type,
      b.audience_id,
      a.name AS audience_name,
      b.status,
      b.scheduled_at,
      b.sent_at,
      b.recipient_count,
      b.sent_count,
      b.failed_count,
      b.created_at,
      b.updated_at
    FROM amp_broadcast_master b
    LEFT JOIN amp_audience_master a ON a.id = b.audience_id
    WHERE b.merchant_id = v_merchant_id
    ORDER BY b.updated_at DESC
    LIMIT 200
  ) t;

  PERFORM public.fn_log_admin_bff_write('bff_list_amp_broadcasts');
  RETURN fn_response_success('Success', 'Broadcasts loaded', jsonb_build_object('items', v_items));
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

CREATE OR REPLACE FUNCTION public.bff_upsert_amp_broadcast(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_id uuid;
  v_audience_type public.amp_broadcast_audience_type;
  v_status public.amp_broadcast_status;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error('Error', 'No merchant context', 'NO_MERCHANT_CONTEXT');
  END IF;

  v_id := NULLIF(p_payload->>'id', '')::uuid;
  v_audience_type := (p_payload->>'audience_type')::public.amp_broadcast_audience_type;

  IF v_id IS NOT NULL THEN
    SELECT status INTO v_status FROM amp_broadcast_master WHERE id = v_id AND merchant_id = v_merchant_id;
    IF v_status IS NULL THEN
      RETURN fn_response_error('Error', 'Broadcast not found', 'NOT_FOUND');
    END IF;
    IF v_status NOT IN ('draft', 'scheduled') THEN
      RETURN fn_response_error('Error', 'Cannot edit broadcast in current status', 'INVALID_STATE');
    END IF;
    UPDATE amp_broadcast_master SET
      name = COALESCE(p_payload->>'name', name),
      audience_type = COALESCE(v_audience_type, audience_type),
      audience_id = CASE
        WHEN p_payload ? 'audience_id' THEN NULLIF(p_payload->>'audience_id', '')::uuid
        ELSE audience_id
      END,
      message_config = COALESCE(p_payload->'message_config', message_config),
      scheduled_at = CASE WHEN p_payload ? 'scheduled_at' THEN NULLIF(p_payload->>'scheduled_at', '')::timestamptz ELSE scheduled_at END,
      updated_at = now()
    WHERE id = v_id AND merchant_id = v_merchant_id;
  ELSE
    IF COALESCE(p_payload->>'name', '') = '' THEN
      RETURN fn_response_error('Error', 'name is required', 'INVALID_REQUEST');
    END IF;
    IF v_audience_type IS NULL THEN
      RETURN fn_response_error('Error', 'audience_type is required', 'INVALID_REQUEST');
    END IF;
    INSERT INTO amp_broadcast_master (
      merchant_id, name, audience_type, audience_id, message_config, status, scheduled_at, created_by
    ) VALUES (
      v_merchant_id,
      p_payload->>'name',
      v_audience_type,
      NULLIF(p_payload->>'audience_id', '')::uuid,
      COALESCE(p_payload->'message_config', '{}'::jsonb),
      'draft',
      NULLIF(p_payload->>'scheduled_at', '')::timestamptz,
      auth.uid()
    ) RETURNING id INTO v_id;
  END IF;

  PERFORM public.fn_log_admin_bff_write('bff_upsert_amp_broadcast');
  RETURN fn_response_success('Success', 'Saved', jsonb_build_object('id', v_id));
EXCEPTION WHEN OTHERS THEN
  RETURN fn_response_error('Error', SQLERRM, 'ERROR');
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_amp_cancel_broadcast(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_status public.amp_broadcast_status;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error('Error', 'No merchant context', 'NO_MERCHANT_CONTEXT');
  END IF;

  SELECT status INTO v_status FROM amp_broadcast_master WHERE id = p_id AND merchant_id = v_merchant_id;
  IF v_status IS NULL THEN
    RETURN fn_response_error('Error', 'Broadcast not found', 'NOT_FOUND');
  END IF;
  IF v_status NOT IN ('draft', 'scheduled') THEN
    RETURN fn_response_error('Error', 'Cannot cancel after sending has started', 'INVALID_STATE');
  END IF;

  UPDATE amp_broadcast_master SET status = 'cancelled', updated_at = now()
  WHERE id = p_id AND merchant_id = v_merchant_id;

  PERFORM public.fn_log_admin_bff_write('bff_amp_cancel_broadcast');
  RETURN fn_response_success('Success', 'Cancelled', jsonb_build_object('id', p_id));
EXCEPTION WHEN OTHERS THEN
  RETURN fn_response_error('Error', SQLERRM, 'ERROR');
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_amp_send_broadcast(
  p_id uuid,
  p_scheduled_at timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_row amp_broadcast_master%ROWTYPE;
  v_request_id bigint;
  v_new_status public.amp_broadcast_status;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error('Error', 'No merchant context', 'NO_MERCHANT_CONTEXT');
  END IF;

  SELECT * INTO v_row FROM amp_broadcast_master WHERE id = p_id AND merchant_id = v_merchant_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN fn_response_error('Error', 'Broadcast not found', 'NOT_FOUND');
  END IF;
  IF v_row.status NOT IN ('draft', 'scheduled') THEN
    RETURN fn_response_error('Error', 'Broadcast already sent or in progress', 'INVALID_STATE');
  END IF;
  IF v_row.message_config IS NULL OR v_row.message_config = '{}'::jsonb THEN
    RETURN fn_response_error('Error', 'Message content is required', 'INVALID_REQUEST');
  END IF;

  IF p_scheduled_at IS NOT NULL AND p_scheduled_at > now() THEN
    UPDATE amp_broadcast_master SET status = 'scheduled', scheduled_at = p_scheduled_at, updated_at = now()
    WHERE id = p_id;
    PERFORM public.fn_log_admin_bff_write('bff_amp_send_broadcast');
    RETURN fn_response_success('Success', 'Scheduled', jsonb_build_object('id', p_id, 'status', 'scheduled'));
  END IF;

  UPDATE amp_broadcast_master SET status = 'sending', scheduled_at = COALESCE(p_scheduled_at, scheduled_at), updated_at = now()
  WHERE id = p_id;

  v_request_id := fn_emit_inngest_event(
    'amp/broadcast.send',
    jsonb_build_object('broadcast_id', p_id, 'merchant_id', v_merchant_id)
  );

  PERFORM public.fn_log_admin_bff_write('bff_amp_send_broadcast');
  RETURN fn_response_success('Success', 'Sending', jsonb_build_object(
    'id', p_id,
    'status', 'sending',
    'inngest_request_id', v_request_id
  ));
EXCEPTION WHEN OTHERS THEN
  RETURN fn_response_error('Error', SQLERRM, 'ERROR');
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_amp_test_send_broadcast(
  p_id uuid,
  p_user_ids uuid[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_count int;
  v_request_id bigint;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error('Error', 'No merchant context', 'NO_MERCHANT_CONTEXT');
  END IF;
  v_count := COALESCE(array_length(p_user_ids, 1), 0);
  IF v_count = 0 OR v_count > 5 THEN
    RETURN fn_response_error('Error', 'Select 1–5 members for test send', 'INVALID_REQUEST');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM amp_broadcast_master WHERE id = p_id AND merchant_id = v_merchant_id) THEN
    RETURN fn_response_error('Error', 'Broadcast not found', 'NOT_FOUND');
  END IF;

  v_request_id := fn_emit_inngest_event(
    'amp/broadcast.send',
    jsonb_build_object(
      'broadcast_id', p_id,
      'merchant_id', v_merchant_id,
      'test_user_ids', to_jsonb(p_user_ids)
    )
  );

  PERFORM public.fn_log_admin_bff_write('bff_amp_test_send_broadcast');
  RETURN fn_response_success('Success', 'Test send queued', jsonb_build_object('inngest_request_id', v_request_id));
EXCEPTION WHEN OTHERS THEN
  RETURN fn_response_error('Error', SQLERRM, 'ERROR');
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_amp_run_due_broadcasts(p_run_at timestamptz DEFAULT now())
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_row RECORD;
  v_processed int := 0;
  v_dispatched int := 0;
  v_request_id bigint;
BEGIN
  FOR v_row IN
    SELECT id, merchant_id
    FROM amp_broadcast_master
    WHERE status = 'scheduled'
      AND scheduled_at IS NOT NULL
      AND scheduled_at <= p_run_at
    ORDER BY scheduled_at
    FOR UPDATE SKIP LOCKED
  LOOP
    v_processed := v_processed + 1;
    UPDATE amp_broadcast_master SET status = 'sending', updated_at = now() WHERE id = v_row.id;
    v_request_id := fn_emit_inngest_event(
      'amp/broadcast.send',
      jsonb_build_object('broadcast_id', v_row.id, 'merchant_id', v_row.merchant_id)
    );
    v_dispatched := v_dispatched + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'run_at', p_run_at,
    'processed', v_processed,
    'dispatched', v_dispatched
  );
END;
$function$;

-- Admin menu (after audience builder)
INSERT INTO public.admin_menu_config (
  id, label, href, image, parent_id, display_order, active_status, category, resource
) VALUES (
  'targeted-broadcast',
  'Targeted broadcast',
  '/targeted-broadcast',
  'https://api.iconify.design/lucide/megaphone.svg',
  NULL,
  123,
  true,
  'amp',
  'targeted-broadcast'
) ON CONFLICT (id) DO UPDATE SET
  label = EXCLUDED.label,
  href = EXCLUDED.href,
  image = EXCLUDED.image,
  display_order = EXCLUDED.display_order,
  active_status = true;

SELECT cron.unschedule(jobid)
FROM cron.job
WHERE jobname = 'amp_run_due_broadcasts';

SELECT cron.schedule(
  'amp_run_due_broadcasts',
  '* * * * *',
  $$SELECT public.fn_amp_run_due_broadcasts();$$
);

REVOKE ALL ON FUNCTION public.bff_list_amp_broadcasts() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.bff_get_amp_broadcast_details(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.bff_upsert_amp_broadcast(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.bff_amp_estimate_audience(text, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.bff_amp_send_broadcast(uuid, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.bff_amp_cancel_broadcast(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.bff_amp_test_send_broadcast(uuid, uuid[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_amp_run_due_broadcasts(timestamptz) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.bff_list_amp_broadcasts() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_get_amp_broadcast_details(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_upsert_amp_broadcast(jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_amp_estimate_audience(text, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_amp_send_broadcast(uuid, timestamptz) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_amp_cancel_broadcast(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_amp_test_send_broadcast(uuid, uuid[]) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_amp_run_due_broadcasts(timestamptz) TO service_role;
