-- Helper: validate member selection against reward.variant_config and build ledger snapshot.
CREATE OR REPLACE FUNCTION public.fn_resolve_reward_variant_selection(
  p_variant_config jsonb,
  p_selected jsonb,
  p_enforce boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
  v_dims jsonb;
  v_dim jsonb;
  v_sel_map jsonb := '{}'::jsonb;
  v_sel_item jsonb;
  v_code text;
  v_opt_code text;
  v_opt jsonb;
  v_found jsonb;
  v_snapshot_dims jsonb := '[]'::jsonb;
  v_required boolean;
BEGIN
  IF p_variant_config IS NULL
     OR p_variant_config = 'null'::jsonb
     OR jsonb_typeof(p_variant_config->'dimensions') IS DISTINCT FROM 'array'
     OR jsonb_array_length(p_variant_config->'dimensions') = 0 THEN
    RETURN jsonb_build_object('ok', true, 'snapshot', NULL);
  END IF;

  v_dims := p_variant_config->'dimensions';

  IF p_selected IS NOT NULL AND p_selected <> 'null'::jsonb THEN
    IF jsonb_typeof(p_selected->'dimensions') = 'array' THEN
      FOR v_sel_item IN SELECT * FROM jsonb_array_elements(p_selected->'dimensions')
      LOOP
        v_code := NULLIF(btrim(COALESCE(v_sel_item->>'code', '')), '');
        v_opt_code := NULLIF(btrim(COALESCE(v_sel_item->>'option_code', v_sel_item->>'option', '')), '');
        IF v_code IS NOT NULL AND v_opt_code IS NOT NULL THEN
          v_sel_map := v_sel_map || jsonb_build_object(v_code, v_opt_code);
        END IF;
      END LOOP;
    ELSIF jsonb_typeof(p_selected) = 'object' THEN
      v_sel_map := p_selected - 'dimensions';
    END IF;
  END IF;

  FOR v_dim IN SELECT * FROM jsonb_array_elements(v_dims)
  LOOP
    v_code := NULLIF(btrim(COALESCE(v_dim->>'code', '')), '');
    IF v_code IS NULL THEN
      CONTINUE;
    END IF;

    v_required := COALESCE((v_dim->>'required')::boolean, true);
    v_opt_code := NULLIF(btrim(COALESCE(v_sel_map->>v_code, '')), '');

    IF v_opt_code IS NULL THEN
      IF v_required AND p_enforce THEN
        RETURN jsonb_build_object(
          'ok', false,
          'error_code', 'VARIANT_REQUIRED',
          'dimension_code', v_code,
          'dimension_label', COALESCE(NULLIF(btrim(COALESCE(v_dim->>'label', '')), ''), v_code)
        );
      ELSE
        CONTINUE;
      END IF;
    END IF;

    v_found := NULL;
    FOR v_opt IN SELECT * FROM jsonb_array_elements(COALESCE(v_dim->'options', '[]'::jsonb))
    LOOP
      IF v_opt->>'code' = v_opt_code THEN
        v_found := v_opt;
        EXIT;
      END IF;
    END LOOP;

    IF v_found IS NULL THEN
      IF p_enforce THEN
        RETURN jsonb_build_object(
          'ok', false,
          'error_code', 'VARIANT_INVALID',
          'dimension_code', v_code,
          'option_code', v_opt_code
        );
      ELSE
        CONTINUE;
      END IF;
    END IF;

    v_snapshot_dims := v_snapshot_dims || jsonb_build_array(jsonb_build_object(
      'code', v_code,
      'label', COALESCE(NULLIF(btrim(COALESCE(v_dim->>'label', '')), ''), v_code),
      'option_code', v_opt_code,
      'option_label', COALESCE(NULLIF(btrim(COALESCE(v_found->>'label', '')), ''), v_opt_code)
    ));
  END LOOP;

  IF jsonb_array_length(v_snapshot_dims) = 0 THEN
    RETURN jsonb_build_object('ok', true, 'snapshot', NULL);
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'snapshot', jsonb_build_object('dimensions', v_snapshot_dims)
  );
END;
$function$;

COMMENT ON FUNCTION public.fn_resolve_reward_variant_selection(jsonb, jsonb, boolean) IS
  'Validates reward variant selection against variant_config; returns {ok, snapshot|error_code}. p_enforce=false skips required checks (system grants).';
