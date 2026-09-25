-- Phase 1a: audience refresh BFF fields + broadcast refresh_before_send upsert

CREATE OR REPLACE FUNCTION public.bff_list_audiences(p_language text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_lang text;
  v_merchant_id UUID;
  v_audiences JSONB;
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
  v_merchant_id := get_current_merchant_id();

  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'NO_MERCHANT_CONTEXT',
      'title', fn_admin_envelope_message('no_merchant_title', v_lang),
      'description', 'No merchant context found');
  END IF;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', a.id,
      'name', a.name,
      'description', a.description,
      'is_active', a.is_active,
      'audience_type', a.audience_type,
      'member_count', a.member_count,
      'workflow_id', a.workflow_id,
      'refresh_schedule', a.refresh_schedule,
      'refresh_time', a.refresh_time,
      'last_refreshed_at', a.last_refreshed_at,
      'next_refresh_at', a.next_refresh_at,
      'created_at', a.created_at,
      'updated_at', a.updated_at
    ) ORDER BY a.created_at DESC
  ), '[]'::jsonb)
  INTO v_audiences
  FROM amp_audience_master a
  WHERE a.merchant_id = v_merchant_id;

  RETURN jsonb_build_object(
    'success', true,
    'data', v_audiences,
    'count', jsonb_array_length(v_audiences)
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'code', 'ERROR',
    'title', fn_admin_envelope_message('error_title', v_lang),
    'description', SQLERRM, 'detail', SQLSTATE);
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_create_audience(
  p_name text,
  p_description text DEFAULT NULL::text,
  p_conditions jsonb DEFAULT '{"groups": []}'::jsonb,
  p_audience_type text DEFAULT 'dynamic'::text,
  p_language text DEFAULT 'en'::text,
  p_refresh_schedule text DEFAULT 'manual'::text,
  p_refresh_time time DEFAULT NULL::time
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_lang text;
  v_merchant_id UUID;
  v_audience_id UUID;
  v_condition_node_id UUID := gen_random_uuid();
  v_action_node_id UUID := gen_random_uuid();
  v_workflow_result JSONB;
  v_workflow_id UUID;
  v_conditions jsonb;
  v_schedule text;
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
  v_merchant_id := get_current_merchant_id();

  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'NO_MERCHANT_CONTEXT',
      'title', fn_admin_envelope_message('no_merchant_title', v_lang),
      'description', 'No merchant context found');
  END IF;

  IF p_audience_type NOT IN ('dynamic', 'static', 'imported') THEN
    RETURN jsonb_build_object('success', false, 'code', 'INVALID_TYPE',
      'title', fn_admin_envelope_message('invalid_type_title', v_lang),
      'description', 'audience_type must be dynamic, static, or imported');
  END IF;

  v_schedule := CASE
    WHEN p_refresh_schedule IN ('manual', 'daily') THEN p_refresh_schedule
    ELSE 'manual'
  END;

  IF p_audience_type = 'static' AND v_schedule = 'daily' AND p_refresh_time IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'INVALID_SCHEDULE',
      'title', fn_admin_envelope_message('error_title', v_lang),
      'description', 'Daily refresh requires a refresh time');
  END IF;

  v_conditions := CASE
    WHEN p_audience_type = 'imported' THEN '{"groups": []}'::jsonb
    ELSE COALESCE(p_conditions, '{"groups": []}'::jsonb)
  END;

  INSERT INTO amp_audience_master (
    merchant_id, name, description, is_active, audience_type,
    refresh_schedule, refresh_time
  )
  VALUES (
    v_merchant_id, p_name, p_description, false, p_audience_type,
    CASE WHEN p_audience_type = 'static' THEN v_schedule ELSE 'manual' END,
    CASE WHEN p_audience_type = 'static' AND v_schedule = 'daily' THEN p_refresh_time ELSE NULL END
  )
  RETURNING id INTO v_audience_id;

  v_workflow_result := bff_upsert_amp_workflow_with_graph(
    p_workflow := jsonb_build_object(
      'name', format('[System] Audience: %s', p_name),
      'workflow_code', 'aud_' || v_audience_id::text,
      'description', format('Auto-created system workflow for audience: %s', p_name),
      'is_active', false
    ),
    p_nodes := jsonb_build_array(
      jsonb_build_object(
        'id', v_condition_node_id,
        'node_type', 'condition',
        'node_name', 'Audience Conditions',
        'node_config', v_conditions,
        'position_x', 250,
        'position_y', 100
      ),
      jsonb_build_object(
        'id', v_action_node_id,
        'node_type', 'action',
        'node_name', 'Add to Audience',
        'node_config', jsonb_build_object(
          'action_type', 'add_to_audience',
          'audience_id', v_audience_id
        ),
        'position_x', 250,
        'position_y', 300
      )
    ),
    p_edges := jsonb_build_array(
      jsonb_build_object(
        'from_node_id', v_condition_node_id,
        'to_node_id', v_action_node_id,
        'source_handle', 'true'
      )
    )
  );

  IF NOT (v_workflow_result->>'success')::boolean THEN
    DELETE FROM amp_audience_master WHERE id = v_audience_id;
    RETURN v_workflow_result;
  END IF;

  v_workflow_id := (v_workflow_result->>'workflow_id')::UUID;

  UPDATE workflow_master
  SET scope = 'system', domain = 'audience'
  WHERE id = v_workflow_id;

  UPDATE amp_audience_master
  SET workflow_id = v_workflow_id
  WHERE id = v_audience_id;

  PERFORM public.fn_log_admin_bff_write('bff_create_audience');
  RETURN jsonb_build_object(
    'success', true,
    'code', 'CREATED',
    'title', fn_admin_envelope_message('audience_created_title', v_lang),
    'description', format('Audience "%s" created with system workflow', p_name),
    'audience_id', v_audience_id,
    'audience_type', p_audience_type,
    'workflow_id', v_workflow_id
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'code', 'ERROR',
    'title', fn_admin_envelope_message('error_title', v_lang),
    'description', SQLERRM, 'detail', SQLSTATE);
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_update_audience(
  p_audience_id uuid,
  p_name text DEFAULT NULL::text,
  p_description text DEFAULT NULL::text,
  p_conditions jsonb DEFAULT NULL::jsonb,
  p_language text DEFAULT 'en'::text,
  p_refresh_schedule text DEFAULT NULL::text,
  p_refresh_time time DEFAULT NULL::time
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_lang text;
  v_merchant_id UUID;
  v_audience RECORD;
  v_condition_node RECORD;
  v_action_node RECORD;
  v_workflow_result JSONB;
  v_schedule text;
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
  v_merchant_id := get_current_merchant_id();

  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'NO_MERCHANT_CONTEXT',
      'title', fn_admin_envelope_message('no_merchant_title', v_lang),
      'description', 'No merchant context found');
  END IF;

  SELECT * INTO v_audience
  FROM amp_audience_master
  WHERE id = p_audience_id AND merchant_id = v_merchant_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND',
      'title', fn_admin_envelope_message('not_found_title', v_lang),
      'description', 'Audience not found or access denied');
  END IF;

  IF v_audience.audience_type = 'static' AND p_refresh_schedule IS NOT NULL THEN
    v_schedule := CASE
      WHEN p_refresh_schedule IN ('manual', 'daily') THEN p_refresh_schedule
      ELSE v_audience.refresh_schedule
    END;
    IF v_schedule = 'daily' AND COALESCE(p_refresh_time, v_audience.refresh_time) IS NULL THEN
      RETURN jsonb_build_object('success', false, 'code', 'INVALID_SCHEDULE',
        'title', fn_admin_envelope_message('error_title', v_lang),
        'description', 'Daily refresh requires a refresh time');
    END IF;
  END IF;

  UPDATE amp_audience_master
  SET
    name = COALESCE(p_name, name),
    description = COALESCE(p_description, description),
    refresh_schedule = CASE
      WHEN v_audience.audience_type = 'static' AND p_refresh_schedule IS NOT NULL THEN v_schedule
      ELSE refresh_schedule
    END,
    refresh_time = CASE
      WHEN v_audience.audience_type = 'static' AND p_refresh_schedule = 'daily' THEN COALESCE(p_refresh_time, refresh_time)
      WHEN v_audience.audience_type = 'static' AND p_refresh_schedule = 'manual' THEN NULL
      WHEN v_audience.audience_type = 'static' AND p_refresh_time IS NOT NULL THEN p_refresh_time
      ELSE refresh_time
    END,
    updated_at = now()
  WHERE id = p_audience_id;

  IF p_name IS NOT NULL AND v_audience.workflow_id IS NOT NULL THEN
    UPDATE workflow_master
    SET name = format('[System] Audience: %s', p_name), updated_at = now()
    WHERE id = v_audience.workflow_id;
  END IF;

  IF p_conditions IS NOT NULL AND v_audience.workflow_id IS NOT NULL THEN
    SELECT * INTO v_condition_node
    FROM workflow_node
    WHERE workflow_id = v_audience.workflow_id
      AND node_type = 'condition'
    LIMIT 1;

    SELECT * INTO v_action_node
    FROM workflow_node
    WHERE workflow_id = v_audience.workflow_id
      AND node_type = 'action'
    LIMIT 1;

    IF v_condition_node.id IS NOT NULL AND v_action_node.id IS NOT NULL THEN
      v_workflow_result := bff_upsert_amp_workflow_with_graph(
        p_workflow := jsonb_build_object(
          'id', v_audience.workflow_id,
          'name', format('[System] Audience: %s', COALESCE(p_name, v_audience.name)),
          'is_active', v_audience.is_active
        ),
        p_nodes := jsonb_build_array(
          jsonb_build_object(
            'id', v_condition_node.id,
            'node_type', 'condition',
            'node_name', 'Audience Conditions',
            'node_config', p_conditions,
            'position_x', v_condition_node.position_x,
            'position_y', v_condition_node.position_y
          ),
          jsonb_build_object(
            'id', v_action_node.id,
            'node_type', 'action',
            'node_name', 'Add to Audience',
            'node_config', v_action_node.node_config,
            'position_x', v_action_node.position_x,
            'position_y', v_action_node.position_y
          )
        ),
        p_edges := jsonb_build_array(
          jsonb_build_object(
            'from_node_id', v_condition_node.id,
            'to_node_id', v_action_node.id,
            'source_handle', 'true'
          )
        )
      );

      IF NOT (v_workflow_result->>'success')::boolean THEN
        RETURN v_workflow_result;
      END IF;
    END IF;
  END IF;

  PERFORM public.fn_amp_apply_audience_refresh_schedule(p_audience_id);

  PERFORM public.fn_log_admin_bff_write('bff_update_audience');
  RETURN jsonb_build_object(
    'success', true,
    'code', 'UPDATED',
    'title', fn_admin_envelope_message('audience_updated_title', v_lang),
    'description', format('Audience "%s" updated', COALESCE(p_name, v_audience.name)),
    'audience_id', p_audience_id,
    'workflow_id', v_audience.workflow_id
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'code', 'ERROR',
    'title', fn_admin_envelope_message('error_title', v_lang),
    'description', SQLERRM, 'detail', SQLSTATE);
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_activate_audience(p_audience_id uuid, p_run_backfill boolean DEFAULT true, p_language text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_lang text;
  v_merchant_id UUID;
  v_audience RECORD;
  v_backfill JSONB;
  v_is_static BOOLEAN;
  v_is_imported BOOLEAN;
  v_do_backfill BOOLEAN;
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
  v_merchant_id := get_current_merchant_id();

  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'NO_MERCHANT_CONTEXT',
      'title', fn_admin_envelope_message('no_merchant_title', v_lang),
      'description', 'No merchant context found');
  END IF;

  SELECT * INTO v_audience
  FROM amp_audience_master
  WHERE id = p_audience_id AND merchant_id = v_merchant_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND',
      'title', fn_admin_envelope_message('not_found_title', v_lang),
      'description', 'Audience not found or access denied');
  END IF;

  IF v_audience.is_active THEN
    RETURN jsonb_build_object('success', false, 'code', 'ALREADY_ACTIVE',
      'title', fn_admin_envelope_message('already_active_title', v_lang),
      'description', 'Audience is already active');
  END IF;

  IF v_audience.workflow_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'NO_WORKFLOW',
      'title', fn_admin_envelope_message('error_title', v_lang),
      'description', 'Audience has no linked system workflow');
  END IF;

  v_is_static := v_audience.audience_type = 'static';
  v_is_imported := v_audience.audience_type = 'imported';
  v_do_backfill := p_run_backfill AND NOT v_is_imported;

  UPDATE amp_audience_master
  SET is_active = true, updated_at = now()
  WHERE id = p_audience_id;

  UPDATE workflow_master
  SET is_active = true, updated_at = now()
  WHERE id = v_audience.workflow_id;

  IF NOT v_is_static AND NOT v_is_imported THEN
    UPDATE workflow_trigger
    SET is_active = true
    WHERE workflow_id = v_audience.workflow_id;
  END IF;

  IF v_do_backfill THEN
    v_backfill := bff_amp_batch_run(v_audience.workflow_id);
    IF v_is_static THEN
      UPDATE amp_audience_master SET last_refreshed_at = now() WHERE id = p_audience_id;
    END IF;
  END IF;

  PERFORM public.fn_amp_apply_audience_refresh_schedule(p_audience_id);

  PERFORM public.fn_log_admin_bff_write('bff_activate_audience');
  RETURN jsonb_build_object(
    'success', true,
    'code', 'ACTIVATED',
    'title', fn_admin_envelope_message('audience_activated_title', v_lang),
    'description', format('Audience "%s" activated%s. %s',
      v_audience.name,
      CASE
        WHEN v_is_imported THEN ' (imported list — conditions are not evaluated)'
        WHEN v_is_static THEN ' (static snapshot, realtime triggers off)'
        ELSE ''
      END,
      CASE
        WHEN v_is_imported THEN 'Import members from a CSV. Then attach a workflow that checks membership of this audience.'
        WHEN NOT v_do_backfill THEN 'No backfill requested.'
        WHEN COALESCE((v_backfill->>'success')::boolean, false)
          THEN format('Backfill dispatched for %s matching user(s).', COALESCE(v_backfill->>'matching_users', '0'))
        ELSE format('Backfill dispatch failed: %s', COALESCE(v_backfill->>'error', 'unknown error'))
      END
    ),
    'audience_id', p_audience_id,
    'audience_type', v_audience.audience_type,
    'workflow_id', v_audience.workflow_id,
    'run_backfill', v_do_backfill,
    'triggers_activated', (NOT v_is_static AND NOT v_is_imported),
    'backfill', v_backfill
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'code', 'ERROR',
    'title', fn_admin_envelope_message('error_title', v_lang),
    'description', SQLERRM, 'detail', SQLSTATE);
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_deactivate_audience(p_audience_id uuid, p_language text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_lang text;
  v_merchant_id UUID;
  v_audience RECORD;
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
  v_merchant_id := get_current_merchant_id();

  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'NO_MERCHANT_CONTEXT',
      'title', fn_admin_envelope_message('no_merchant_title', v_lang),
      'description', 'No merchant context found');
  END IF;

  SELECT * INTO v_audience
  FROM amp_audience_master
  WHERE id = p_audience_id AND merchant_id = v_merchant_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND',
      'title', fn_admin_envelope_message('not_found_title', v_lang),
      'description', 'Audience not found or access denied');
  END IF;

  IF NOT v_audience.is_active THEN
    RETURN jsonb_build_object('success', false, 'code', 'ALREADY_INACTIVE',
      'title', fn_admin_envelope_message('already_inactive_title', v_lang),
      'description', 'Audience is already inactive');
  END IF;

  UPDATE amp_audience_master
  SET is_active = false, updated_at = now()
  WHERE id = p_audience_id;

  IF v_audience.workflow_id IS NOT NULL THEN
    UPDATE workflow_master
    SET is_active = false, updated_at = now()
    WHERE id = v_audience.workflow_id;

    UPDATE workflow_trigger
    SET is_active = false
    WHERE workflow_id = v_audience.workflow_id;
  END IF;

  PERFORM public.fn_amp_apply_audience_refresh_schedule(p_audience_id);

  PERFORM public.fn_log_admin_bff_write('bff_deactivate_audience');
  RETURN jsonb_build_object(
    'success', true,
    'code', 'DEACTIVATED',
    'title', fn_admin_envelope_message('audience_deactivated_title', v_lang),
    'description', format('Audience "%s" deactivated. %s members retained.', v_audience.name, v_audience.member_count),
    'audience_id', p_audience_id,
    'member_count', v_audience.member_count
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'code', 'ERROR',
    'title', fn_admin_envelope_message('error_title', v_lang),
    'description', SQLERRM, 'detail', SQLSTATE);
END;
$function$;

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

    SELECT a.last_refreshed_at INTO v_last_refreshed
    FROM amp_audience_master a
    WHERE a.id = p_audience_id AND a.merchant_id = v_merchant_id;

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
  v_refresh_before boolean;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error('Error', 'No merchant context', 'NO_MERCHANT_CONTEXT');
  END IF;

  v_id := NULLIF(p_payload->>'id', '')::uuid;
  v_audience_type := (p_payload->>'audience_type')::public.amp_broadcast_audience_type;
  v_refresh_before := COALESCE((p_payload->>'refresh_before_send')::boolean, true);

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
      refresh_before_send = CASE WHEN p_payload ? 'refresh_before_send' THEN v_refresh_before ELSE refresh_before_send END,
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
      merchant_id, name, audience_type, audience_id, message_config, status, scheduled_at, created_by, refresh_before_send
    ) VALUES (
      v_merchant_id,
      p_payload->>'name',
      v_audience_type,
      NULLIF(p_payload->>'audience_id', '')::uuid,
      COALESCE(p_payload->'message_config', '{}'::jsonb),
      'draft',
      NULLIF(p_payload->>'scheduled_at', '')::timestamptz,
      auth.uid(),
      v_refresh_before
    ) RETURNING id INTO v_id;
  END IF;

  PERFORM public.fn_log_admin_bff_write('bff_upsert_amp_broadcast');
  RETURN fn_response_success('Success', 'Saved', jsonb_build_object('id', v_id));
EXCEPTION WHEN OTHERS THEN
  RETURN fn_response_error('Error', SQLERRM, 'ERROR');
END;
$function$;
