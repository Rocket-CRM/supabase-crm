-- Broadcast send log: paginated batch rows per broadcast, audience-scoped broadcast list.

CREATE INDEX IF NOT EXISTS amp_broadcast_master_merchant_audience_idx
  ON public.amp_broadcast_master (merchant_id, audience_id, updated_at DESC)
  WHERE audience_id IS NOT NULL;

-- Drop the zero-arg version so the defaulted version is the only candidate.
DROP FUNCTION IF EXISTS public.bff_list_amp_broadcasts();

CREATE OR REPLACE FUNCTION public.bff_list_amp_broadcasts(
  p_audience_id uuid DEFAULT NULL,
  p_limit integer DEFAULT 200,
  p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_items jsonb;
  v_total integer;
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 200), 1), 200);
  v_offset integer := GREATEST(COALESCE(p_offset, 0), 0);
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error('Error', 'No merchant context', 'NO_MERCHANT_CONTEXT');
  END IF;

  SELECT count(*)::int INTO v_total
  FROM amp_broadcast_master b
  WHERE b.merchant_id = v_merchant_id
    AND (p_audience_id IS NULL OR b.audience_id = p_audience_id);

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
      AND (p_audience_id IS NULL OR b.audience_id = p_audience_id)
    ORDER BY b.updated_at DESC
    LIMIT v_limit OFFSET v_offset
  ) t;

  PERFORM public.fn_log_admin_bff_write('bff_list_amp_broadcasts');
  RETURN fn_response_success('Success', 'Broadcasts loaded', jsonb_build_object(
    'items', v_items,
    'total', v_total,
    'has_more', v_offset + v_limit < v_total
  ));
EXCEPTION WHEN OTHERS THEN
  RETURN fn_response_error('Error', SQLERRM, 'ERROR');
END;
$function$;

GRANT EXECUTE ON FUNCTION public.bff_list_amp_broadcasts(uuid, integer, integer) TO authenticated, service_role;

-- Detail returns a batch summary; full rows (with up to 500 LINE ids each) come from
-- bff_list_amp_broadcast_batches.
CREATE OR REPLACE FUNCTION public.bff_get_amp_broadcast_details(p_id uuid, p_mode text DEFAULT 'view'::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_row jsonb;
  v_batch_summary jsonb;
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
    SELECT jsonb_build_object(
      'total', count(*)::int,
      'sent', count(*) FILTER (WHERE bb.status = 'sent')::int,
      'failed', count(*) FILTER (WHERE bb.status = 'failed')::int,
      'pending', count(*) FILTER (WHERE bb.status = 'pending')::int
    )
    INTO v_batch_summary
    FROM amp_broadcast_batch bb
    WHERE bb.broadcast_id = p_id;
    v_row := v_row || jsonb_build_object('batch_summary', v_batch_summary);
  END IF;

  PERFORM public.fn_log_admin_bff_write('bff_get_amp_broadcast_details');
  RETURN fn_response_success('Success', NULL, jsonb_build_object('broadcast', v_row));
EXCEPTION WHEN OTHERS THEN
  RETURN fn_response_error('Error', SQLERRM, 'ERROR');
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_list_amp_broadcast_batches(
  p_broadcast_id uuid,
  p_status text DEFAULT NULL,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_audience_type text;
  v_items jsonb;
  v_summary jsonb;
  v_total integer;
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);
  v_offset integer := GREATEST(COALESCE(p_offset, 0), 0);
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error('Error', 'No merchant context', 'NO_MERCHANT_CONTEXT');
  END IF;

  IF p_status IS NOT NULL AND p_status NOT IN ('pending', 'sent', 'failed') THEN
    RETURN fn_response_error('Error', 'Invalid status filter', 'INVALID_STATUS');
  END IF;

  SELECT b.audience_type::text INTO v_audience_type
  FROM amp_broadcast_master b
  WHERE b.id = p_broadcast_id AND b.merchant_id = v_merchant_id;

  IF v_audience_type IS NULL THEN
    RETURN fn_response_error('Error', 'Broadcast not found', 'NOT_FOUND');
  END IF;

  SELECT jsonb_build_object(
    'total', count(*)::int,
    'sent', count(*) FILTER (WHERE bb.status = 'sent')::int,
    'failed', count(*) FILTER (WHERE bb.status = 'failed')::int,
    'pending', count(*) FILTER (WHERE bb.status = 'pending')::int
  )
  INTO v_summary
  FROM amp_broadcast_batch bb
  WHERE bb.broadcast_id = p_broadcast_id;

  SELECT count(*)::int INTO v_total
  FROM amp_broadcast_batch bb
  WHERE bb.broadcast_id = p_broadcast_id
    AND (p_status IS NULL OR bb.status = p_status);

  SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.batch_no), '[]'::jsonb)
  INTO v_items
  FROM (
    SELECT
      bb.id,
      bb.batch_no,
      -- LINE broadcast mode (all friends) stores no ids: recipient_count is null.
      CASE WHEN v_audience_type = 'all_line_friends' THEN NULL
           ELSE cardinality(bb.line_user_ids) END AS recipient_count,
      bb.status,
      bb.attempt_count,
      bb.error,
      bb.sent_at,
      bb.line_request_id,
      bb.updated_at
    FROM amp_broadcast_batch bb
    WHERE bb.broadcast_id = p_broadcast_id
      AND (p_status IS NULL OR bb.status = p_status)
    ORDER BY bb.batch_no
    LIMIT v_limit OFFSET v_offset
  ) t;

  PERFORM public.fn_log_admin_bff_write('bff_list_amp_broadcast_batches');
  RETURN fn_response_success('Success', 'Batches loaded', jsonb_build_object(
    'audience_type', v_audience_type,
    'summary', v_summary,
    'items', v_items,
    'total', v_total,
    'has_more', v_offset + v_limit < v_total
  ));
EXCEPTION WHEN OTHERS THEN
  RETURN fn_response_error('Error', SQLERRM, 'ERROR');
END;
$function$;

GRANT EXECUTE ON FUNCTION public.bff_list_amp_broadcast_batches(uuid, text, integer, integer) TO authenticated, service_role;
