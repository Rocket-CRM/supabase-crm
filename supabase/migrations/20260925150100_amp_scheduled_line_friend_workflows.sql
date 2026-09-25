-- Scheduled runs for All LINE Friends entry types (Phase 1b)

CREATE OR REPLACE FUNCTION public.fn_amp_run_due_scheduled_workflows(p_run_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_trigger RECORD;
  v_workflow RECORD;
  v_user_ids uuid[];
  v_user_count int;
  v_processed int := 0;
  v_dispatched int := 0;
  v_skipped int := 0;
  v_failed int := 0;
  v_supabase_url text;
  v_service_role_key text;
  v_dispatch_url text;
  v_request_ids bigint[];
  v_next_run_at timestamptz;
  v_feature_key text;
  v_entry_type text;
  v_request_id bigint;
BEGIN
  SELECT decrypted_secret INTO v_supabase_url FROM vault.decrypted_secrets WHERE name = 'supabase_url' LIMIT 1;
  SELECT decrypted_secret INTO v_service_role_key FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;

  IF v_supabase_url IS NULL OR v_service_role_key IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Missing supabase_url or service_role_key in vault');
  END IF;

  v_dispatch_url := rtrim(v_supabase_url, '/') || '/functions/v1/amp-dispatch-workflow-batch';

  FOR v_trigger IN
    SELECT t.*
    FROM public.workflow_trigger t
    WHERE t.trigger_type = 'scheduled'
      AND t.is_active = true
      AND t.next_run_at IS NOT NULL
      AND t.next_run_at <= p_run_at
      AND t.schedule_status = 'idle'
    ORDER BY t.next_run_at
    FOR UPDATE SKIP LOCKED
  LOOP
    v_processed := v_processed + 1;

    BEGIN
      SELECT id, merchant_id, name, is_active, config
      INTO v_workflow
      FROM public.workflow_master
      WHERE id = v_trigger.workflow_id;

      IF v_workflow IS NULL OR v_workflow.is_active = false THEN
        v_skipped := v_skipped + 1;
        UPDATE public.workflow_trigger
        SET schedule_status = 'idle',
            last_run_at = p_run_at,
            next_run_at = fn_amp_compute_next_run_at(v_trigger.trigger_conditions->'schedule', p_run_at)
        WHERE id = v_trigger.id;
        CONTINUE;
      END IF;

      SELECT COALESCE(n.node_config->>'entry_type', 'condition')
      INTO v_entry_type
      FROM workflow_node n
      WHERE n.workflow_id = v_trigger.workflow_id AND n.node_type = 'condition'
      ORDER BY n.position_y, n.position_x
      LIMIT 1;

      IF v_workflow.config->>'surface' = 'lifecycle_automation' THEN
        v_feature_key := public.fn_lifecycle_event_shopify_feature_key(
          v_workflow.config->>'lifecycle_event'
        );
        IF v_feature_key IS NOT NULL
           AND NOT public.fn_merchant_shopify_feature_enabled(
             v_trigger.merchant_id, 'lifecycle', v_feature_key
           ) THEN
          v_skipped := v_skipped + 1;
          v_next_run_at := fn_amp_compute_next_run_at(v_trigger.trigger_conditions->'schedule', p_run_at);
          UPDATE public.workflow_trigger
          SET schedule_status = 'idle',
              last_run_at = p_run_at,
              next_run_at = v_next_run_at
          WHERE id = v_trigger.id;
          CONTINUE;
        END IF;
      END IF;

      UPDATE public.workflow_trigger
      SET schedule_status = 'running'
      WHERE id = v_trigger.id;

      v_next_run_at := fn_amp_compute_next_run_at(v_trigger.trigger_conditions->'schedule', p_run_at);

      IF v_entry_type = 'all_line_friends' THEN
        INSERT INTO public.workflow_log (
          merchant_id, workflow_id, user_id, inngest_run_id,
          event_type, event_data, run_scope
        ) VALUES (
          v_trigger.merchant_id, v_trigger.workflow_id, NULL,
          'scheduled_run_' || gen_random_uuid()::text,
          'scheduled_run_dispatched',
          jsonb_build_object(
            'trigger_id', v_trigger.id,
            'run_at', p_run_at,
            'next_run_at', v_next_run_at,
            'entry_type', 'all_line_friends',
            'run_scope', 'broadcast'
          ),
          'broadcast'
        );

        v_request_id := net.http_post(
          url := v_dispatch_url,
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || v_service_role_key
          ),
          body := jsonb_build_object(
            'workflow_id', v_trigger.workflow_id,
            'merchant_id', v_trigger.merchant_id,
            'entry_type', 'all_line_friends',
            'run_scope', 'broadcast',
            'trigger_data', jsonb_build_object(
              'source', 'scheduled_run',
              'entry_type', 'all_line_friends'
            )
          )
        );
        v_dispatched := v_dispatched + 1;

        UPDATE public.workflow_trigger
        SET schedule_status = 'idle',
            last_run_at = p_run_at,
            next_run_at = v_next_run_at
        WHERE id = v_trigger.id;
        CONTINUE;
      END IF;

      IF v_entry_type = 'all_line_friends_exclude_members' THEN
        INSERT INTO public.workflow_log (
          merchant_id, workflow_id, user_id, inngest_run_id,
          event_type, event_data, run_scope
        ) VALUES (
          v_trigger.merchant_id, v_trigger.workflow_id, NULL,
          'scheduled_run_' || gen_random_uuid()::text,
          'scheduled_run_dispatched',
          jsonb_build_object(
            'trigger_id', v_trigger.id,
            'run_at', p_run_at,
            'next_run_at', v_next_run_at,
            'entry_type', 'all_line_friends_exclude_members',
            'run_scope', 'line'
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
            'workflow_id', v_trigger.workflow_id,
            'merchant_id', v_trigger.merchant_id,
            'entry_type', 'all_line_friends_exclude_members',
            'run_scope', 'line',
            'trigger_data', jsonb_build_object(
              'source', 'scheduled_run',
              'entry_type', 'all_line_friends_exclude_members'
            )
          )
        );
        v_dispatched := v_dispatched + 1;

        UPDATE public.workflow_trigger
        SET schedule_status = 'idle',
            last_run_at = p_run_at,
            next_run_at = v_next_run_at
        WHERE id = v_trigger.id;
        CONTINUE;
      END IF;

      SELECT array_agg(user_id) INTO v_user_ids
      FROM public.fn_amp_find_matching_users(v_trigger.workflow_id);
      v_user_count := COALESCE(array_length(v_user_ids, 1), 0);

      IF v_user_count = 0 THEN
        v_skipped := v_skipped + 1;
        INSERT INTO public.workflow_log (
          merchant_id, workflow_id, user_id, inngest_run_id,
          event_type, event_data
        ) VALUES (
          v_trigger.merchant_id, v_trigger.workflow_id,
          '00000000-0000-0000-0000-000000000000'::uuid,
          'scheduled_run_' || gen_random_uuid()::text,
          'scheduled_run_no_users',
          jsonb_build_object(
            'trigger_id', v_trigger.id,
            'run_at', p_run_at,
            'next_run_at', v_next_run_at
          )
        );
      ELSE
        v_request_ids := fn_amp_dispatch_batch_chunks(
          v_trigger.workflow_id, v_trigger.merchant_id, v_user_ids,
          v_dispatch_url, v_service_role_key, 500
        );
        v_dispatched := v_dispatched + v_user_count;

        INSERT INTO public.workflow_log (
          merchant_id, workflow_id, user_id, inngest_run_id,
          event_type, event_data
        ) VALUES (
          v_trigger.merchant_id, v_trigger.workflow_id,
          '00000000-0000-0000-0000-000000000000'::uuid,
          'scheduled_run_' || gen_random_uuid()::text,
          'scheduled_run_dispatched',
          jsonb_build_object(
            'trigger_id', v_trigger.id,
            'run_at', p_run_at,
            'next_run_at', v_next_run_at,
            'matching_users', v_user_count,
            'batch_count', COALESCE(array_length(v_request_ids, 1), 0),
            'pg_net_request_ids', to_jsonb(v_request_ids)
          )
        );
      END IF;

      UPDATE public.workflow_trigger
      SET schedule_status = 'idle',
          last_run_at = p_run_at,
          next_run_at = v_next_run_at
      WHERE id = v_trigger.id;

    EXCEPTION WHEN OTHERS THEN
      v_failed := v_failed + 1;
      UPDATE public.workflow_trigger
      SET schedule_status = 'failed',
          last_run_at = p_run_at
      WHERE id = v_trigger.id;

      INSERT INTO public.workflow_log (
        merchant_id, workflow_id, user_id, inngest_run_id,
        event_type, event_data, error_message
      ) VALUES (
        v_trigger.merchant_id, v_trigger.workflow_id,
        '00000000-0000-0000-0000-000000000000'::uuid,
        'scheduled_run_' || gen_random_uuid()::text,
        'scheduled_run_failed',
        jsonb_build_object('trigger_id', v_trigger.id, 'run_at', p_run_at),
        SQLERRM
      );
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'run_at', p_run_at,
    'processed_triggers', v_processed,
    'dispatched_users', v_dispatched,
    'skipped_triggers', v_skipped,
    'failed_triggers', v_failed
  );
END;
$function$;
