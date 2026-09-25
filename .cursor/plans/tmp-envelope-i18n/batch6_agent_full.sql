-- bff_get_agent_full: create 3-arg first, drop both old, then create 2-arg language overload

CREATE OR REPLACE FUNCTION public.bff_get_agent_full(p_agent_id uuid DEFAULT NULL::uuid, p_mode text DEFAULT 'new'::text, p_language text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_lang text;
  v_merchant_id uuid := public.get_current_merchant_id();
  v_agent jsonb;
  v_actions jsonb;
  v_outcomes jsonb;
BEGIN
  v_lang := fn_normalize_ui_language(p_language);

  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'title', fn_admin_envelope_message('not_authenticated_title', v_lang),
      'description', null,
      'data', null,
      'error', fn_admin_envelope_message('not_authenticated_title', v_lang)
    );
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
    RETURN jsonb_build_object(
      'success', false,
      'title', fn_admin_envelope_message('not_found_title', v_lang),
      'description', fn_admin_envelope_message('agent_not_found_short_desc', v_lang),
      'data', null,
      'error', fn_admin_envelope_message('agent_not_found_short_desc', v_lang)
    );
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
$function$;

DROP FUNCTION IF EXISTS public.bff_get_agent_full(uuid);
DROP FUNCTION IF EXISTS public.bff_get_agent_full(uuid, text);

CREATE OR REPLACE FUNCTION public.bff_get_agent_full(p_agent_id uuid, p_language text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_lang text;
  v_merchant_id UUID;
  v_agent JSONB;
  v_actions JSONB;
  v_outcomes JSONB;
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
  v_merchant_id := get_current_merchant_id();

  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'title', fn_admin_envelope_message('error_title', v_lang),
      'description', fn_admin_envelope_message('no_merchant_found_title', v_lang),
      'data', null
    );
  END IF;

  SELECT to_jsonb(a) INTO v_agent
  FROM amp_agent a
  WHERE a.id = p_agent_id AND a.merchant_id = v_merchant_id;

  IF v_agent IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'title', fn_admin_envelope_message('not_found_title', v_lang),
      'description', fn_admin_envelope_message('agent_not_found_desc', v_lang),
      'data', null
    );
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
  RETURN jsonb_build_object(
    'success', false,
    'title', fn_admin_envelope_message('error_title', COALESCE(v_lang, 'en')),
    'description', SQLERRM,
    'data', null
  );
END;
$function$;
