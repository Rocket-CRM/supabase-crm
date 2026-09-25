CREATE OR REPLACE FUNCTION public.bff_get_signup_code_prefillable_fields(p_field_config_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_pool record;
  v_pool_persona_ids uuid[];
  v_schema_default text[];
  v_schema_custom text[];
  v_available_default jsonb;
  v_available_custom jsonb;
  v_selected_default jsonb;
  v_selected_custom jsonb;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'title', 'No merchant context', 'description', null, 'data', null);
  END IF;

  IF NOT check_admin_permission('form', 'read') THEN
    RETURN jsonb_build_object('success', false, 'title', 'Forbidden', 'description', 'Insufficient permissions', 'data', jsonb_build_object('error_code', 'FORBIDDEN'));
  END IF;

  SELECT * INTO v_pool FROM user_field_config WHERE id = p_field_config_id;

  IF v_pool.id IS NULL OR v_pool.merchant_id != v_merchant_id THEN
    RETURN jsonb_build_object('success', false, 'title', 'Pool not found', 'description', null, 'data', jsonb_build_object('error_code', 'FIELD_NOT_FOUND'));
  END IF;

  IF v_pool.field_type != 'external_code' THEN
    RETURN jsonb_build_object('success', false, 'title', 'Wrong field type', 'description', 'Pool must be field_type=external_code', 'data', jsonb_build_object('error_code', 'WRONG_FIELD_TYPE'));
  END IF;

  v_pool_persona_ids := v_pool.persona_ids;

  v_schema_default := COALESCE(
    ARRAY(SELECT jsonb_array_elements_text(v_pool.config #> '{external_code,prefill_schema,default}')),
    ARRAY[]::text[]
  );
  v_schema_custom := COALESCE(
    ARRAY(SELECT jsonb_array_elements_text(v_pool.config #> '{external_code,prefill_schema,custom}')),
    ARRAY[]::text[]
  );

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'field_key', uf.field_key,
      'field_label', uf.field_label,
      'field_type', uf.field_type,
      'is_required', uf.is_required,
      'persona_ids', COALESCE(to_jsonb(uf.persona_ids), '[]'::jsonb),
      'options', COALESCE(uf.options, '[]'::jsonb),
      'help_text', uf.help_text,
      'placeholder', uf.placeholder
    )
    ORDER BY uf.order_index NULLS LAST, uf.field_label
  ), '[]'::jsonb) INTO v_available_default
  FROM user_field_config uf
  WHERE uf.merchant_id = v_merchant_id
    AND uf.id != p_field_config_id
    AND uf.active_status = true
    AND uf.visible_to_user = true
    AND uf.field_type != 'external_code'
    AND (
      v_pool_persona_ids IS NULL OR array_length(v_pool_persona_ids,1) IS NULL
      OR uf.persona_ids IS NULL OR array_length(uf.persona_ids,1) IS NULL
      OR uf.persona_ids && v_pool_persona_ids
    );

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'field_key', f.field_key,
      'field_label', f.label,
      'field_type', f.field_type,
      'is_required', f.is_required,
      'persona_ids', COALESCE(to_jsonb(f.persona_ids), '[]'::jsonb),
      'options', COALESCE(
        (SELECT jsonb_agg(jsonb_build_object('value', fo.option_value, 'label', fo.option_label)
                          ORDER BY fo.order_index)
         FROM form_field_options fo
         WHERE fo.field_id = f.id), '[]'::jsonb),
      'help_text', f.help_text,
      'placeholder', f.placeholder
    )
    ORDER BY f.order_index NULLS LAST, f.label
  ), '[]'::jsonb) INTO v_available_custom
  FROM form_fields f
  JOIN form_templates t ON t.id = f.form_id
  WHERE t.merchant_id = v_merchant_id
    AND t.code = 'USER_PROFILE'
    AND f.deleted_at IS NULL
    AND f.visible_to_user = true
    AND (
      v_pool_persona_ids IS NULL OR array_length(v_pool_persona_ids,1) IS NULL
      OR f.persona_ids IS NULL OR array_length(f.persona_ids,1) IS NULL
      OR f.persona_ids && v_pool_persona_ids
    );

  SELECT COALESCE(jsonb_agg(elem ORDER BY array_position(v_schema_default, elem->>'field_key')), '[]'::jsonb)
    INTO v_selected_default
  FROM jsonb_array_elements(v_available_default) elem
  WHERE elem->>'field_key' = ANY(v_schema_default);

  SELECT COALESCE(jsonb_agg(elem ORDER BY array_position(v_schema_custom, elem->>'field_key')), '[]'::jsonb)
    INTO v_selected_custom
  FROM jsonb_array_elements(v_available_custom) elem
  WHERE elem->>'field_key' = ANY(v_schema_custom);

  RETURN jsonb_build_object(
    'success', true,
    'title', null,
    'description', null,
    'data', jsonb_build_object(
      'pool', jsonb_build_object(
        'id', v_pool.id,
        'field_key', v_pool.field_key,
        'field_label', v_pool.field_label,
        'persona_ids', COALESCE(to_jsonb(v_pool_persona_ids), '[]'::jsonb)
      ),
      'available', jsonb_build_object(
        'default', v_available_default,
        'custom', v_available_custom
      ),
      'selected', jsonb_build_object(
        'default', v_selected_default,
        'custom', v_selected_custom
      )
    )
  );
END;
$function$
