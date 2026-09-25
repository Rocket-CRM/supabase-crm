-- B7: keep workflow_node ids for lifecycle action slots; return actions[].id

CREATE OR REPLACE FUNCTION public.bff_get_lifecycle_automation(p_workflow_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_workflow jsonb;
  v_nodes jsonb;
  v_edges jsonb;
  v_triggers jsonb;
  v_actions jsonb;
BEGIN
  v_merchant_id := get_current_merchant_id();

  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error('Not authenticated', 'No merchant context found', 'NO_MERCHANT_CONTEXT');
  END IF;

  IF NOT (check_admin_permission('workflow-builder', 'read') OR check_admin_permission('amp', 'read')) THEN
    RETURN fn_response_error('Forbidden', 'Insufficient permissions', 'FORBIDDEN');
  END IF;

  SELECT jsonb_build_object(
    'id', w.id,
    'workflow_id', w.id,
    'workflow_code', w.workflow_code,
    'name', w.name,
    'description', w.description,
    'is_active', w.is_active,
    'run_mode', w.run_mode,
    'scope', w.scope,
    'domain', w.domain,
    'config', w.config,
    'lifecycle_event', w.config->>'lifecycle_event',
    'created_at', w.created_at,
    'updated_at', w.updated_at
  )
  INTO v_workflow
  FROM workflow_master w
  WHERE w.id = p_workflow_id
    AND w.merchant_id = v_merchant_id
    AND w.config->>'surface' = 'lifecycle_automation';

  IF v_workflow IS NULL THEN
    RETURN fn_response_error('Not found', 'Lifecycle automation not found', 'NOT_FOUND');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', n.id,
    'node_type', n.node_type,
    'node_name', n.node_name,
    'node_config', n.node_config,
    'position_x', n.position_x,
    'position_y', n.position_y
  ) ORDER BY n.position_y, n.position_x, n.created_at), '[]'::jsonb)
  INTO v_nodes
  FROM workflow_node n
  WHERE n.workflow_id = p_workflow_id;

  SELECT COALESCE(jsonb_agg(
    (n.node_config - 'id' - 'node_name' - '_key') || jsonb_build_object('id', n.id)
    ORDER BY n.position_y, n.position_x, n.created_at
  ), '[]'::jsonb)
  INTO v_actions
  FROM workflow_node n
  WHERE n.workflow_id = p_workflow_id
    AND n.node_type = 'action';

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', e.id,
    'from_node_id', e.from_node_id,
    'to_node_id', e.to_node_id,
    'source_handle', e.source_handle,
    'edge_label', e.edge_label
  ) ORDER BY e.created_at), '[]'::jsonb)
  INTO v_edges
  FROM workflow_edge e
  WHERE e.workflow_id = p_workflow_id;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', t.id,
    'trigger_type', t.trigger_type,
    'trigger_table', t.trigger_table,
    'trigger_operation', t.trigger_operation,
    'trigger_conditions', t.trigger_conditions,
    'is_active', t.is_active,
    'next_run_at', t.next_run_at,
    'last_run_at', t.last_run_at,
    'schedule_status', t.schedule_status
  ) ORDER BY t.created_at), '[]'::jsonb)
  INTO v_triggers
  FROM workflow_trigger t
  WHERE t.workflow_id = p_workflow_id;

  RETURN fn_response_success(
    'Lifecycle Automation',
    'Lifecycle automation loaded',
    jsonb_build_object(
      'workflow', v_workflow,
      'nodes', v_nodes,
      'edges', v_edges,
      'triggers', v_triggers,
      'actions', v_actions
    )
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_upsert_lifecycle_automation(p_config jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_workflow_id uuid;
  v_is_new boolean;
  v_event text;
  v_name text;
  v_tier_name text;
  v_description text;
  v_is_active boolean;
  v_timezone text;
  v_days_offset int;
  v_schedule jsonb;
  v_actions jsonb;
  v_action jsonb;
  v_action_type text;
  v_node_config jsonb;
  v_node_id uuid;
  v_previous_node_id uuid;
  v_condition_node_id uuid;
  v_position_y int := 0;
  v_trigger_type text;
  v_trigger_table text;
  v_trigger_operation text := 'INSERT';
  v_trigger_conditions jsonb := '{}'::jsonb;
  v_to_tier_id uuid;
  v_condition_field text;
  v_condition_operator text;
  v_workflow_config jsonb;
  v_permission_action text;
  v_action_count int := 0;
  v_saved_actions jsonb := '[]'::jsonb;
  v_keep_ids uuid[] := ARRAY[]::uuid[];
  v_existing_workflow_id uuid;
  v_existing_reward_id text;
BEGIN
  v_merchant_id := get_current_merchant_id();

  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error('Not authenticated', 'No merchant context found', 'NO_MERCHANT_CONTEXT');
  END IF;

  v_workflow_id := NULLIF(p_config->>'id', '')::uuid;
  v_is_new := v_workflow_id IS NULL;
  v_permission_action := CASE WHEN v_is_new THEN 'create' ELSE 'update' END;

  IF NOT (check_admin_permission('workflow-builder', v_permission_action) OR check_admin_permission('amp', v_permission_action)) THEN
    RETURN fn_response_error('Forbidden', 'Insufficient permissions', 'FORBIDDEN');
  END IF;

  v_event := p_config->>'lifecycle_event';
  v_description := p_config->>'description';
  v_is_active := COALESCE((p_config->>'is_active')::boolean, false);
  v_timezone := COALESCE(NULLIF(p_config->>'timezone', ''), p_config->'schedule'->>'timezone', 'Asia/Bangkok');
  v_days_offset := COALESCE((p_config->>'days_offset')::int, (p_config->>'days_before')::int, 0);
  v_schedule := COALESCE(p_config->'schedule', jsonb_build_object('type', 'daily', 'time_of_day', '09:00', 'timezone', v_timezone));

  IF v_event NOT IN ('signup', 'tier_upgrade', 'tier_downgrade', 'birthday', 'membership_anniversary') THEN
    RETURN fn_response_error('Invalid lifecycle event', 'Unsupported lifecycle_event', 'INVALID_LIFECYCLE_EVENT', jsonb_build_object('lifecycle_event', v_event));
  END IF;

  v_to_tier_id := NULL;
  IF v_event IN ('tier_upgrade', 'tier_downgrade') THEN
    v_to_tier_id := NULLIF(p_config->>'to_tier_id', '')::uuid;
    IF v_to_tier_id IS NOT NULL AND NOT EXISTS (
      SELECT 1
      FROM tier_master tm
      WHERE tm.id = v_to_tier_id
        AND tm.merchant_id = v_merchant_id
    ) THEN
      RETURN fn_response_error(
        'Invalid tier',
        'The selected tier was not found for this merchant',
        'INVALID_TIER',
        jsonb_build_object('to_tier_id', v_to_tier_id)
      );
    END IF;
  END IF;

  v_name := CASE v_event
    WHEN 'signup' THEN 'Signup'
    WHEN 'tier_upgrade' THEN 'Tier upgraded'
    WHEN 'tier_downgrade' THEN 'Tier downgraded'
    WHEN 'birthday' THEN 'Birthday'
    WHEN 'membership_anniversary' THEN 'Membership anniversary'
    ELSE 'Lifecycle Automation'
  END;

  IF v_to_tier_id IS NOT NULL THEN
    SELECT tm.tier_name
    INTO v_tier_name
    FROM tier_master tm
    WHERE tm.id = v_to_tier_id
      AND tm.merchant_id = v_merchant_id;

    IF v_tier_name IS NOT NULL THEN
      v_name := v_name || ' → ' || v_tier_name;
    END IF;
  END IF;

  v_actions := COALESCE(p_config->'actions', CASE WHEN p_config ? 'action' THEN jsonb_build_array(p_config->'action') ELSE '[]'::jsonb END);
  IF jsonb_typeof(v_actions) <> 'array' OR jsonb_array_length(v_actions) = 0 THEN
    RETURN fn_response_error('Actions required', 'At least one action is required', 'ACTIONS_REQUIRED');
  END IF;

  IF v_event = 'signup' THEN
    v_trigger_type := 'database';
    v_trigger_table := 'user_accounts';
    v_trigger_conditions := jsonb_build_object('skip_cdc', false, 'mongo_id', null);
  ELSIF v_event = 'tier_upgrade' THEN
    v_trigger_type := 'database';
    v_trigger_table := 'tier_change_ledger';
    v_trigger_conditions := jsonb_build_object('change_type', 'upgrade');
    IF v_to_tier_id IS NOT NULL THEN
      v_trigger_conditions := v_trigger_conditions || jsonb_build_object('to_tier_id', v_to_tier_id);
    END IF;
  ELSIF v_event = 'tier_downgrade' THEN
    v_trigger_type := 'database';
    v_trigger_table := 'tier_change_ledger';
    v_trigger_conditions := jsonb_build_object('change_type', 'downgrade');
    IF v_to_tier_id IS NOT NULL THEN
      v_trigger_conditions := v_trigger_conditions || jsonb_build_object('to_tier_id', v_to_tier_id);
    END IF;
  ELSIF v_event = 'birthday' THEN
    v_trigger_type := 'scheduled';
    v_trigger_table := 'user_accounts';
    v_trigger_conditions := jsonb_build_object('schedule', v_schedule, 'lifecycle_event', v_event);
    v_condition_field := 'birth_date';
    v_condition_operator := 'birthday_today';
  ELSE
    v_trigger_type := 'scheduled';
    v_trigger_table := 'user_accounts';
    v_trigger_conditions := jsonb_build_object('schedule', v_schedule, 'lifecycle_event', v_event);
    v_condition_field := 'created_at';
    v_condition_operator := 'anniversary_today';
  END IF;

  v_workflow_config := jsonb_build_object(
    'surface', 'lifecycle_automation',
    'lifecycle_event', v_event,
    'timezone', v_timezone,
    'days_offset', v_days_offset,
    'schedule', CASE WHEN v_trigger_type = 'scheduled' THEN v_schedule ELSE NULL END,
    'admin_config', p_config - 'id'
  );

  IF v_is_new THEN
    INSERT INTO workflow_master (
      merchant_id, workflow_code, name, description, is_active, run_mode, scope, domain, created_by, config
    ) VALUES (
      v_merchant_id,
      COALESCE(NULLIF(p_config->>'workflow_code', ''), 'lifecycle_' || v_event || '_' || replace(gen_random_uuid()::text, '-', '')),
      v_name,
      v_description,
      v_is_active,
      CASE WHEN v_trigger_type = 'scheduled' THEN 'scheduled' ELSE 'on_event' END,
      'user',
      'loyalty',
      auth.uid(),
      v_workflow_config
    )
    RETURNING id INTO v_workflow_id;
  ELSE
    UPDATE workflow_master
    SET name = v_name,
        description = v_description,
        is_active = v_is_active,
        run_mode = CASE WHEN v_trigger_type = 'scheduled' THEN 'scheduled' ELSE 'on_event' END,
        scope = 'user',
        domain = 'loyalty',
        config = v_workflow_config,
        updated_at = now()
    WHERE id = v_workflow_id
      AND merchant_id = v_merchant_id
      AND config->>'surface' = 'lifecycle_automation';

    IF NOT FOUND THEN
      RETURN fn_response_error('Not found', 'Lifecycle automation not found', 'NOT_FOUND');
    END IF;
  END IF;

  DELETE FROM workflow_edge WHERE workflow_id = v_workflow_id AND merchant_id = v_merchant_id;
  DELETE FROM workflow_trigger WHERE workflow_id = v_workflow_id AND merchant_id = v_merchant_id;
  DELETE FROM workflow_node
  WHERE workflow_id = v_workflow_id
    AND merchant_id = v_merchant_id
    AND node_type IS DISTINCT FROM 'action';

  IF v_trigger_type = 'scheduled' THEN
    v_condition_node_id := gen_random_uuid();
    INSERT INTO workflow_node (id, workflow_id, merchant_id, node_type, node_name, node_config, position_x, position_y)
    VALUES (
      v_condition_node_id,
      v_workflow_id,
      v_merchant_id,
      'condition',
      CASE WHEN v_event = 'birthday' THEN 'Birthday is today' ELSE 'Membership anniversary is today' END,
      jsonb_build_object(
        'groups_operator', 'AND',
        'groups', jsonb_build_array(jsonb_build_object(
          'type', 'simple',
          'collection', 'user_accounts',
          'conditions', jsonb_build_array(jsonb_build_object(
            'field', v_condition_field,
            'operator', v_condition_operator,
            'timezone', v_timezone,
            'days_offset', v_days_offset
          ))
        ))
      ),
      0,
      v_position_y
    );
    v_previous_node_id := v_condition_node_id;
    v_position_y := v_position_y + 200;
  END IF;

  FOR v_action IN SELECT * FROM jsonb_array_elements(v_actions)
  LOOP
    v_action_type := COALESCE(v_action->>'action_type', v_action->'node_config'->>'action_type');
    IF v_action_type IS NULL THEN
      RETURN fn_response_error('Invalid action', 'Each action requires action_type', 'INVALID_ACTION');
    END IF;

    v_node_config := COALESCE(v_action->'node_config', v_action) - 'id' - 'node_name' - '_key';

    IF v_action_type IN ('award_currency', 'award_points', 'award_tickets') AND NOT (v_node_config ? 'dedup_key') THEN
      v_node_config := v_node_config || jsonb_build_object('dedup_key', 'lifecycle:' || v_workflow_id::text || ':{{user_id}}');
    END IF;

    BEGIN
      v_node_id := COALESCE(NULLIF(v_action->>'id', '')::uuid, gen_random_uuid());
    EXCEPTION WHEN invalid_text_representation THEN
      RETURN fn_response_error('Invalid action', 'Action id must be a uuid', 'INVALID_ACTION');
    END;

    SELECT wn.workflow_id, wn.node_config->>'reward_id'
    INTO v_existing_workflow_id, v_existing_reward_id
    FROM workflow_node wn
    WHERE wn.id = v_node_id;

    IF FOUND THEN
      IF v_existing_workflow_id IS DISTINCT FROM v_workflow_id THEN
        RETURN fn_response_error('Invalid action', 'Action id belongs to another automation', 'INVALID_ACTION');
      END IF;
      IF v_action_type = 'push_reward'
        AND NOT (v_node_config ? 'reward_id')
        AND v_existing_reward_id IS NOT NULL
      THEN
        v_node_config := v_node_config || jsonb_build_object('reward_id', v_existing_reward_id);
      END IF;

      UPDATE workflow_node
      SET node_config = v_node_config,
          node_name = COALESCE(v_action->>'node_name', replace(v_action_type, '_', ' ')),
          position_x = 300,
          position_y = v_position_y,
          updated_at = now()
      WHERE id = v_node_id
        AND workflow_id = v_workflow_id
        AND merchant_id = v_merchant_id
        AND node_type = 'action';

      IF NOT FOUND THEN
        RETURN fn_response_error('Invalid action', 'Action node could not be updated', 'INVALID_ACTION');
      END IF;
    ELSE
      INSERT INTO workflow_node (id, workflow_id, merchant_id, node_type, node_name, node_config, position_x, position_y)
      VALUES (
        v_node_id,
        v_workflow_id,
        v_merchant_id,
        COALESCE(v_action->>'node_type', 'action'),
        COALESCE(v_action->>'node_name', replace(v_action_type, '_', ' ')),
        v_node_config,
        300,
        v_position_y
      );
    END IF;

    IF v_previous_node_id IS NOT NULL THEN
      INSERT INTO workflow_edge (workflow_id, merchant_id, from_node_id, to_node_id, source_handle, edge_label)
      VALUES (
        v_workflow_id,
        v_merchant_id,
        v_previous_node_id,
        v_node_id,
        CASE WHEN v_previous_node_id = v_condition_node_id THEN 'output-true' ELSE 'default' END,
        NULL
      );
    END IF;

    v_keep_ids := array_append(v_keep_ids, v_node_id);
    v_saved_actions := v_saved_actions || jsonb_build_array(
      v_node_config || jsonb_build_object('id', v_node_id)
    );

    v_previous_node_id := v_node_id;
    v_position_y := v_position_y + 200;
    v_action_count := v_action_count + 1;
  END LOOP;

  DELETE FROM workflow_node
  WHERE workflow_id = v_workflow_id
    AND merchant_id = v_merchant_id
    AND node_type = 'action'
    AND NOT (id = ANY (v_keep_ids));

  v_workflow_config := jsonb_set(
    v_workflow_config,
    '{admin_config,actions}',
    v_saved_actions
  );
  UPDATE workflow_master
  SET config = v_workflow_config, updated_at = now()
  WHERE id = v_workflow_id AND merchant_id = v_merchant_id;

  INSERT INTO workflow_trigger (
    workflow_id, merchant_id, trigger_type, trigger_table, trigger_operation, trigger_conditions, is_active, domain
  ) VALUES (
    v_workflow_id,
    v_merchant_id,
    v_trigger_type,
    v_trigger_table,
    v_trigger_operation,
    v_trigger_conditions,
    true,
    'loyalty'
  );

  BEGIN
    PERFORM extensions.amp_cache_del('triggers:' || v_merchant_id::text);
    PERFORM extensions.amp_cache_del('workflow:' || v_workflow_id::text);
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  PERFORM public.fn_invalidate_earn_channels_cache(v_merchant_id);

  RETURN fn_response_success(
    CASE WHEN v_is_new THEN 'Lifecycle Automation Created' ELSE 'Lifecycle Automation Updated' END,
    format('Lifecycle automation "%s" saved', v_name),
    jsonb_build_object(
      'workflow_id', v_workflow_id,
      'is_new', v_is_new,
      'lifecycle_event', v_event,
      'action_count', v_action_count,
      'actions', v_saved_actions
    )
  );
EXCEPTION WHEN OTHERS THEN
  RETURN fn_response_error('Error', SQLERRM, SQLSTATE);
END;
$function$;
