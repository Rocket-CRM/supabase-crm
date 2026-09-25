-- AMP entry: all_line_friends_exclude_members

CREATE OR REPLACE FUNCTION public.fn_amp_filter_non_member_line_ids(
  p_merchant_id uuid,
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
  WHERE x IS NOT NULL
    AND x <> ''
    AND NOT EXISTS (
      SELECT 1 FROM user_accounts ua
      WHERE ua.merchant_id = p_merchant_id
        AND ua.line_id = x
    );
$function$;

REVOKE ALL ON FUNCTION public.fn_amp_filter_non_member_line_ids(uuid, text[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_amp_filter_non_member_line_ids(uuid, text[]) TO service_role;

DO $migrate$
DECLARE
  v_def text;
  v_marker text := E'  END IF;\n\n  -- ── Immediate LINE option: enrolls on postback, not batch ────────────────';
  v_block text := $block$
  IF v_entry_type = 'all_line_friends_exclude_members' THEN
    INSERT INTO workflow_log (
      merchant_id, workflow_id, user_id, inngest_run_id,
      event_type, event_data, run_scope
    ) VALUES (
      v_merchant_id, p_workflow_id, NULL,
      'batch_run_' || gen_random_uuid()::text,
      'batch_run_requested',
      jsonb_build_object(
        'entry_type', 'all_line_friends_exclude_members',
        'run_scope', 'line',
        'requested_at', now()
      ),
      'line'
    );

    v_request_id := net.http_post(
      url := v_dispatch_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_service_role_key
      ),
      body := jsonb_build_object(
        'workflow_id', p_workflow_id,
        'merchant_id', v_merchant_id,
        'entry_type', 'all_line_friends_exclude_members',
        'run_scope', 'line',
        'trigger_data', jsonb_build_object(
          'source', 'batch_run',
          'entry_type', 'all_line_friends_exclude_members'
        )
      )
    );

    RETURN jsonb_build_object(
      'success', true,
      'workflow_id', p_workflow_id,
      'entry_type', 'all_line_friends_exclude_members',
      'run_scope', 'line',
      'matching_users', 0,
      'dispatched', 0,
      'batch_count', 1,
      'pg_net_request_ids', jsonb_build_array(v_request_id),
      'message', 'Started sending to LINE friends who are not members. Friends are enrolled as the follower list is scanned.'
    );
  END IF;

$block$;
BEGIN
  v_def := pg_get_functiondef('public.bff_amp_batch_run(uuid)'::regprocedure);
  IF position('all_line_friends_exclude_members' in v_def) > 0 THEN
    RETURN;
  END IF;
  IF position(v_marker in v_def) = 0 THEN
    RAISE EXCEPTION 'bff_amp_batch_run insert marker not found';
  END IF;
  v_def := replace(v_def, v_marker, '  END IF;' || E'\n\n' || v_block || E'\n  -- ── Immediate LINE option: enrolls on postback, not batch ────────────────');
  EXECUTE v_def;
END;
$migrate$;
