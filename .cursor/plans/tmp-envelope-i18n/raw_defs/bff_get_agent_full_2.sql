CREATE OR REPLACE FUNCTION public.bff_get_agent_full(p_agent_id uuid DEFAULT NULL::uuid, p_mode text DEFAULT 'new'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_merchant_id uuid := public.get_current_merchant_id();
  v_agent jsonb;
  v_actions jsonb;
  v_outcomes jsonb;
BEGIN
  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  IF p_mode = 'new' OR p_agent_id IS NULL THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'action', r.action, 'domain', r.domain, 'tool_type', r.tool_type,
      'action_category', r.action_category, 'applicable_variables', r.applicable_variables
    ) ORDER BY r.action), '[]'::jsonb) INTO v_actions
    FROM action_registry r WHERE r.domain = 'loyalty';

    RETURN jsonb_build_object('success', true, 'data', jsonb_build_object(
      'agent', NULL, 'actions', v_actions, 'outcomes', '[]'::jsonb,
      'available_actions', v_actions
    ));
  END IF;

  SELECT to_jsonb(a) INTO v_agent FROM amp_agent a
  WHERE a.id = p_agent_id AND a.merchant_id = v_merchant_id;

  IF v_agent IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Agent not found');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', acc.id, 'action', acc.action,
    'is_enabled', acc.is_enabled, 'variable_config', acc.variable_config,
    'rules_code', acc.rules_code, 'sort_order', acc.sort_order,
    'registry', jsonb_build_object('domain', r.domain, 'tool_type', r.tool_type,
      'action_category', r.action_category, 'applicable_variables', r.applicable_variables)
  ) ORDER BY acc.sort_order), '[]'::jsonb) INTO v_actions
  FROM action_caller_config acc
  JOIN action_registry r ON r.action = acc.action
  WHERE acc.caller_type = 'amp_agent' AND acc.caller_id = p_agent_id AND acc.merchant_id = v_merchant_id;

  SELECT COALESCE(jsonb_agg(to_jsonb(o)), '[]'::jsonb) INTO v_outcomes
  FROM amp_agent_outcome o WHERE o.agent_id = p_agent_id;

  RETURN jsonb_build_object('success', true, 'data', jsonb_build_object(
    'agent', v_agent, 'actions', v_actions, 'outcomes', v_outcomes
  ));
END;
$function$
