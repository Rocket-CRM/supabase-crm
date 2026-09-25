CREATE OR REPLACE FUNCTION public.bff_get_agent_full(p_agent_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_merchant_id UUID;
  v_agent JSONB;
  v_actions JSONB;
  v_outcomes JSONB;
BEGIN
  v_merchant_id := get_current_merchant_id();

  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'title', 'Error', 'description', 'No merchant context found', 'data', null);
  END IF;

  SELECT to_jsonb(a) INTO v_agent
  FROM amp_agent a
  WHERE a.id = p_agent_id AND a.merchant_id = v_merchant_id;

  IF v_agent IS NULL THEN
    RETURN jsonb_build_object('success', false, 'title', 'Not Found', 'description', 'Agent not found or access denied', 'data', null);
  END IF;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', acc.id,
      'action', acc.action,
      'action_type', acc.action,
      'is_enabled', acc.is_enabled,
      'variable_config', acc.variable_config,
      'rules_code', acc.rules_code,
      'sort_order', acc.sort_order,
      'registry', jsonb_build_object(
        'domain', r.domain,
        'tool_type', r.tool_type,
        'action_category', r.action_category,
        'applicable_variables', r.applicable_variables
      )
    ) ORDER BY acc.sort_order
  ), '[]'::jsonb) INTO v_actions
  FROM action_caller_config acc
  JOIN action_registry r ON r.action = acc.action
  WHERE acc.caller_type = 'amp_agent'
    AND acc.caller_id = p_agent_id
    AND acc.merchant_id = v_merchant_id;

  SELECT COALESCE(jsonb_agg(
    to_jsonb(ao) ORDER BY ao.sort_order, ao.created_at
  ), '[]'::jsonb) INTO v_outcomes
  FROM amp_agent_outcome ao
  WHERE ao.agent_id = p_agent_id AND ao.merchant_id = v_merchant_id;

  RETURN jsonb_build_object(
    'success', true,
    'title', null,
    'description', null,
    'data', v_agent || jsonb_build_object(
      'actions', v_actions,
      'outcomes', v_outcomes
    )
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'title', 'Error', 'description', SQLERRM, 'data', null);
END;
$function$
