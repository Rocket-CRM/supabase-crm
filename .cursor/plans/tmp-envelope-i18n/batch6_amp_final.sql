CREATE OR REPLACE FUNCTION public.bff_upsert_amp_workflow_with_graph(p_workflow jsonb, p_nodes jsonb DEFAULT '[]'::jsonb, p_edges jsonb DEFAULT '[]'::jsonb, p_triggers jsonb DEFAULT '[]'::jsonb, p_run_batch boolean DEFAULT false, p_language text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_lang text;
  v_merchant_id UUID;
  v_workflow_id UUID;
  v_workflow_name TEXT;
  v_is_new BOOLEAN := false;
  v_node JSONB;
  v_edge JSONB;
  v_trigger JSONB;
  v_node_id UUID;
  v_node_ids UUID[] := '{}';
  v_edge_ids UUID[] := '{}';
  v_trigger_ids UUID[] := '{}';
  v_nodes_created INT := 0;
  v_nodes_updated INT := 0;
  v_nodes_deleted INT := 0;
  v_edges_created INT := 0;
  v_edges_deleted INT := 0;
  v_triggers_created INT := 0;
  v_triggers_updated INT := 0;
  v_triggers_deleted INT := 0;
  v_auto_triggers JSONB := '[]'::jsonb;
  v_collections TEXT[] := '{}';
  v_collection TEXT;
  v_group JSONB;
  v_is_active BOOLEAN;
  v_batch_result JSONB := NULL;
  v_audience_id UUID;
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'NO_MERCHANT_CONTEXT', 'title', fn_admin_envelope_message('error_title', v_lang), 'description', fn_admin_envelope_message('no_merchant_found_title', v_lang));
  END IF;

  v_workflow_id := (p_workflow->>'id')::UUID;
  v_workflow_name := COALESCE(p_workflow->>'name', 'Untitled Workflow');
  v_is_active := COALESCE((p_workflow->>'is_active')::boolean, false);

  IF v_workflow_id IS NULL THEN
    v_is_new := true;
    INSERT INTO workflow_master (merchant_id, workflow_code, name, description, is_active, run_mode, scope, domain, created_by)
    VALUES (v_merchant_id, COALESCE(NULLIF(p_workflow->>'workflow_code', ''), 'wf_' || gen_random_uuid()::text), v_workflow_name, p_workflow->>'description', v_is_active, COALESCE(p_workflow->>'run_mode', 'on_event'), COALESCE(p_workflow->>'scope', 'user'), COALESCE(p_workflow->>'domain', 'campaign'), (p_workflow->>'created_by')::UUID)
    RETURNING id INTO v_workflow_id;
  ELSE
    UPDATE workflow_master SET workflow_code = COALESCE(NULLIF(p_workflow->>'workflow_code', ''), workflow_code), name = COALESCE(p_workflow->>'name', name), description = p_workflow->>'description', is_active = v_is_active, run_mode = COALESCE(p_workflow->>'run_mode', run_mode), scope = COALESCE(p_workflow->>'scope', scope), domain = COALESCE(p_workflow->>'domain', domain), updated_at = now()
    WHERE id = v_workflow_id AND merchant_id = v_merchant_id;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND', 'title', fn_admin_envelope_message('not_found_title', v_lang), 'description', fn_admin_envelope_message('workflow_not_found_desc', v_lang));
    END IF;
    SELECT name INTO v_workflow_name FROM workflow_master WHERE id = v_workflow_id;
  END IF;

  FOR v_node IN SELECT * FROM jsonb_array_elements(p_nodes) LOOP
    v_node_id := COALESCE((v_node->>'id')::UUID, gen_random_uuid());
    INSERT INTO workflow_node (id, workflow_id, merchant_id, node_type, node_name, node_config, position_x, position_y)
    VALUES (v_node_id, v_workflow_id, v_merchant_id, v_node->>'node_type', v_node->>'node_name', COALESCE((v_node->'node_config')::jsonb, '{}'::jsonb), COALESCE((v_node->>'position_x')::numeric, 0), COALESCE((v_node->>'position_y')::numeric, 0))
    ON CONFLICT (id) DO UPDATE SET node_type = COALESCE(EXCLUDED.node_type, workflow_node.node_type), node_name = EXCLUDED.node_name, node_config = COALESCE(EXCLUDED.node_config, workflow_node.node_config), position_x = COALESCE(EXCLUDED.position_x, workflow_node.position_x), position_y = COALESCE(EXCLUDED.position_y, workflow_node.position_y), updated_at = now()
    WHERE workflow_node.workflow_id = v_workflow_id AND workflow_node.merchant_id = v_merchant_id;
    v_node_ids := array_append(v_node_ids, v_node_id);
    v_nodes_created := v_nodes_created + 1;
    IF v_node->>'node_type' = 'condition' THEN
      FOR v_group IN SELECT * FROM jsonb_array_elements(v_node->'node_config'->'groups') LOOP
        v_collection := v_group->>'collection';
        IF v_collection IS NOT NULL AND NOT (v_collection = ANY(v_collections)) THEN
          v_collections := array_append(v_collections, v_collection);
        END IF;
      END LOOP;
    END IF;
    IF (v_node->'node_config'->>'entry_type') = 'audience' THEN
      v_audience_id := (v_node->'node_config'->>'audience_id')::UUID;
    END IF;
  END LOOP;

  DELETE FROM workflow_node WHERE workflow_id = v_workflow_id AND merchant_id = v_merchant_id AND (array_length(v_node_ids, 1) IS NULL OR id != ALL(v_node_ids));
  GET DIAGNOSTICS v_nodes_deleted = ROW_COUNT;
  DELETE FROM workflow_edge WHERE workflow_id = v_workflow_id AND merchant_id = v_merchant_id;
  GET DIAGNOSTICS v_edges_deleted = ROW_COUNT;

  FOR v_edge IN SELECT * FROM jsonb_array_elements(p_edges) LOOP
    INSERT INTO workflow_edge (id, workflow_id, merchant_id, from_node_id, to_node_id, source_handle, edge_label)
    VALUES (COALESCE((v_edge->>'id')::UUID, gen_random_uuid()), v_workflow_id, v_merchant_id, (v_edge->>'from_node_id')::UUID, (v_edge->>'to_node_id')::UUID, COALESCE(v_edge->>'source_handle', 'default'), v_edge->>'edge_label');
    v_edges_created := v_edges_created + 1;
  END LOOP;

  IF jsonb_array_length(p_triggers) = 0 THEN
    IF v_audience_id IS NOT NULL THEN
      v_auto_triggers := v_auto_triggers || jsonb_build_object('trigger_type', 'audience_entered', 'trigger_table', 'amp_audience_member', 'trigger_operation', 'INSERT', 'trigger_conditions', jsonb_build_object('audience_id', v_audience_id), 'is_active', true);
    END IF;
    IF array_length(v_collections, 1) > 0 THEN
      FOR i IN 1..array_length(v_collections, 1) LOOP
        v_collection := v_collections[i];
        IF v_collection = 'wallet_ledger' THEN
          v_auto_triggers := v_auto_triggers || jsonb_build_object('trigger_type', 'points_earned', 'trigger_table', 'wallet_ledger', 'trigger_operation', 'INSERT', 'trigger_conditions', jsonb_build_object('transaction_type', 'earn'), 'is_active', true);
        ELSIF v_collection = 'purchase_ledger' OR v_collection = 'purchase_items_ledger' THEN
          IF NOT v_auto_triggers @> '[{"trigger_table": "purchase_ledger"}]'::jsonb THEN
            v_auto_triggers := v_auto_triggers || jsonb_build_object('trigger_type', 'purchase_completed', 'trigger_table', 'purchase_ledger', 'trigger_operation', 'INSERT', 'trigger_conditions', jsonb_build_object(), 'is_active', true);
          END IF;
        ELSIF v_collection = 'user_accounts' THEN
          IF NOT v_auto_triggers @> '[{"trigger_table": "user_accounts"}]'::jsonb THEN
            v_auto_triggers := v_auto_triggers || jsonb_build_object('trigger_type', 'database', 'trigger_table', 'user_accounts', 'trigger_operation', 'INSERT', 'trigger_conditions', jsonb_build_object(), 'is_active', true);
          END IF;
        END IF;
      END LOOP;
    END IF;
    p_triggers := v_auto_triggers;
  END IF;

  DELETE FROM workflow_trigger WHERE workflow_id = v_workflow_id AND merchant_id = v_merchant_id;
  FOR v_trigger IN SELECT * FROM jsonb_array_elements(p_triggers) LOOP
    INSERT INTO workflow_trigger (id, workflow_id, merchant_id, trigger_type, trigger_table, trigger_operation, trigger_conditions, is_active)
    VALUES (COALESCE((v_trigger->>'id')::UUID, gen_random_uuid()), v_workflow_id, v_merchant_id, v_trigger->>'trigger_type', v_trigger->>'trigger_table', v_trigger->>'trigger_operation', COALESCE(v_trigger->'trigger_conditions', '{}'::jsonb), COALESCE((v_trigger->>'is_active')::boolean, true));
    v_trigger_ids := array_append(v_trigger_ids, COALESCE((v_trigger->>'id')::UUID, gen_random_uuid()));
    v_triggers_created := v_triggers_created + 1;
  END LOOP;

  IF p_run_batch AND v_is_active THEN
    v_batch_result := bff_amp_batch_run(v_workflow_id);
  END IF;

  BEGIN
    PERFORM extensions.amp_cache_del('triggers:' || v_merchant_id::TEXT);
    PERFORM extensions.amp_cache_del('workflow:' || v_workflow_id::TEXT);
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN jsonb_build_object(
    'success', true,
    'code', CASE WHEN v_is_new THEN 'CREATED' ELSE 'UPDATED' END,
    'title', CASE WHEN v_is_new THEN fn_admin_envelope_message('workflow_created_title', v_lang) ELSE fn_admin_envelope_message('workflow_updated_title', v_lang) END,
    'description', fn_admin_envelope_message('workflow_action_desc', v_lang, ARRAY[v_workflow_name, CASE WHEN v_is_new THEN fn_admin_envelope_message('word_created', v_lang) ELSE fn_admin_envelope_message('word_updated', v_lang) END, v_nodes_created::text, v_triggers_created::text]),
    'workflow_id', v_workflow_id,
    'is_new', v_is_new,
    'auto_triggers_detected', v_collections,
    'audience_trigger', v_audience_id,
    'batch_run', v_batch_result,
    'operations', jsonb_build_object('nodes_created', v_nodes_created, 'nodes_updated', v_nodes_updated, 'nodes_deleted', v_nodes_deleted, 'edges_created', v_edges_created, 'edges_deleted', v_edges_deleted, 'triggers_created', v_triggers_created, 'triggers_updated', v_triggers_updated, 'triggers_deleted', v_triggers_deleted)
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'code', 'ERROR', 'title', fn_admin_envelope_message('error_title', v_lang), 'description', SQLERRM, 'detail', SQLSTATE);
END;
$function$;

DROP FUNCTION IF EXISTS public.bff_upsert_amp_workflow_with_graph(jsonb, jsonb, jsonb, jsonb, boolean);
