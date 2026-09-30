-- Audience Edit hydration: single audience + saved conditions (list payload omits them). AUDIENCE-0072

CREATE OR REPLACE FUNCTION public.bff_get_audience_details(p_audience_id uuid, p_language text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
AS $function$
DECLARE
  v_lang text;
  v_merchant_id uuid;
  v_audience jsonb;
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
  v_merchant_id := get_current_merchant_id();

  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'NO_MERCHANT_CONTEXT',
      'title', fn_admin_envelope_message('no_merchant_title', v_lang),
      'description', 'No merchant context found');
  END IF;

  SELECT jsonb_build_object(
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
    'updated_at', a.updated_at,
    'conditions', (SELECT n.node_config FROM workflow_node n
                   WHERE n.workflow_id = a.workflow_id AND n.node_type = 'condition' LIMIT 1)
  )
  INTO v_audience
  FROM amp_audience_master a
  WHERE a.id = p_audience_id AND a.merchant_id = v_merchant_id;

  IF v_audience IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND',
      'title', fn_admin_envelope_message('not_found_title', v_lang),
      'description', 'Audience not found or access denied');
  END IF;

  RETURN jsonb_build_object('success', true, 'data', v_audience);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'code', 'ERROR',
    'title', fn_admin_envelope_message('error_title', v_lang),
    'description', SQLERRM, 'detail', SQLSTATE);
END;
$function$;
