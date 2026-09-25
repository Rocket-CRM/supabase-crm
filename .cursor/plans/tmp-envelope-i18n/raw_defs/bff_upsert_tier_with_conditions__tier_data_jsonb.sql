CREATE OR REPLACE FUNCTION public.bff_upsert_tier_with_conditions(tier_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_tier_id uuid;
  v_merchant_id uuid;
  v_tier_name text;
  v_user_type public.user_type;
  v_persona_ids uuid[] := ARRAY[]::uuid[];
  v_personas_provided boolean := false;
  v_burn_rate numeric;
  v_is_create boolean := false;
  v_sync_result jsonb;
  v_condition jsonb;
  v_condition_id uuid;
  v_upgrade_ids uuid[] := ARRAY[]::uuid[];
  v_upgrade_created int := 0;
  v_upgrade_updated int := 0;
  v_upgrade_deleted int := 0;
  v_rejected text[] := ARRAY[]::text[];
  v_key text;
BEGIN
  v_merchant_id := public.get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'NO_MERCHANT_CONTEXT',
      'title', 'Error', 'description', 'No merchant context found');
  END IF;

  -- Ladder order and entry tier are derived from upgrade amounts; the clock lives on
  -- tier_program_config. Reject any caller still sending the retired fields.
  FOREACH v_key IN ARRAY ARRAY['ranking', 'entry_tier', 'maintain'] LOOP
    IF tier_data ? v_key THEN
      v_rejected := array_append(v_rejected, v_key);
    END IF;
  END LOOP;

  FOR v_condition IN
    SELECT value
    FROM jsonb_array_elements(
      CASE WHEN jsonb_typeof(tier_data->'upgrade') = 'array' THEN tier_data->'upgrade' ELSE '[]'::jsonb END
    ) AS value
  LOOP
    FOREACH v_key IN ARRAY ARRAY['metric', 'window_type', 'window_months', 'window_start',
                                 'frequency', 'window_start_field',
                                 'upgrade_evaluation_timing', 'upgrade_evaluation_value'] LOOP
      IF v_condition ? v_key AND NOT (v_key = ANY(v_rejected)) THEN
        v_rejected := array_append(v_rejected, v_key);
      END IF;
    END LOOP;
  END LOOP;

  IF array_length(v_rejected, 1) IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'UNSUPPORTED_FIELDS',
      'title', 'Unsupported Fields',
      'description', format(
        'These fields are no longer set per tier: %s. Metric, period, upgrade timing and maintain_mode belong to the tier program config; maintain amount equals the tier upgrade amount; ladder order and entry tier are derived from upgrade amounts.',
        array_to_string(v_rejected, ', ')),
      'data', jsonb_build_object('rejected_fields', to_jsonb(v_rejected)));
  END IF;

  v_tier_id := COALESCE(
    NULLIF(tier_data->>'tier_id', '')::uuid,
    NULLIF(tier_data->>'id', '')::uuid
  );
  v_tier_name := COALESCE(tier_data->>'tier_name', 'Untitled Tier');
  v_burn_rate := NULLIF(tier_data->>'burn_rate', '')::numeric;

  IF tier_data ? 'persona_ids' THEN
    v_personas_provided := true;
    IF tier_data->'persona_ids' IS NULL OR jsonb_typeof(tier_data->'persona_ids') = 'null' THEN
      v_persona_ids := ARRAY[]::uuid[];
    ELSIF jsonb_typeof(tier_data->'persona_ids') = 'array' THEN
      SELECT COALESCE(array_agg(value_text::uuid), ARRAY[]::uuid[])
      INTO v_persona_ids
      FROM (
        SELECT NULLIF(value, '') AS value_text
        FROM jsonb_array_elements_text(tier_data->'persona_ids') AS value
      ) s
      WHERE value_text IS NOT NULL;
    ELSE
      RETURN jsonb_build_object('success', false, 'code', 'INVALID_PERSONAS',
        'title', 'Invalid Personas', 'description', 'persona_ids must be an array');
    END IF;
  ELSIF tier_data ? 'persona_id' THEN
    v_personas_provided := true;
    v_persona_ids := CASE
      WHEN NULLIF(tier_data->>'persona_id', '') IS NULL THEN ARRAY[]::uuid[]
      ELSE ARRAY[NULLIF(tier_data->>'persona_id', '')::uuid]
    END;
  END IF;

  IF v_burn_rate IS NOT NULL AND v_burn_rate < 0 THEN
    RETURN jsonb_build_object('success', false, 'code', 'INVALID_BURN_RATE',
      'title', 'Invalid Burn Rate', 'description', 'Burn rate must be zero or greater');
  END IF;

  IF array_length(v_persona_ids, 1) IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM unnest(v_persona_ids) AS persona_id
      WHERE NOT EXISTS (
        SELECT 1 FROM public.persona_master pm
        WHERE pm.id = persona_id AND pm.merchant_id = v_merchant_id
          AND COALESCE(pm.active_status, true) = true
      )
    ) THEN
      RETURN jsonb_build_object('success', false, 'code', 'INVALID_PERSONA',
        'title', 'Invalid Persona', 'description', 'One or more personas were not found or inactive');
    END IF;
  END IF;

  IF v_tier_id IS NULL THEN
    v_user_type := COALESCE(NULLIF(tier_data->>'user_type', ''), 'buyer')::public.user_type;
  ELSE
    SELECT tm.user_type INTO v_user_type FROM public.tier_master tm WHERE tm.id = v_tier_id;
    v_user_type := COALESCE(NULLIF(tier_data->>'user_type', '')::public.user_type, v_user_type);
  END IF;

  -- D5: thresholds are meaningless without a program clock to measure them against.
  IF jsonb_typeof(tier_data->'upgrade') = 'array'
     AND NOT EXISTS (
       SELECT 1 FROM public.tier_program_config c
       WHERE c.merchant_id = v_merchant_id AND c.user_type = v_user_type
     ) THEN
    RETURN jsonb_build_object('success', false, 'code', 'NO_PROGRAM_CONFIG',
      'title', 'Tier Program Not Configured',
      'description', 'Set up the tier program (metric and period) before saving tier thresholds.');
  END IF;

  IF v_tier_id IS NULL THEN
    v_is_create := true;

    INSERT INTO public.tier_master (
      merchant_id, tier_name, user_type, persona_id, icon, color, burn_rate
    ) VALUES (
      v_merchant_id,
      v_tier_name,
      v_user_type,
      CASE WHEN array_length(v_persona_ids, 1) IS NULL THEN NULL ELSE v_persona_ids[1] END,
      tier_data->>'icon',
      tier_data->>'color',
      v_burn_rate
    )
    RETURNING id INTO v_tier_id;
  ELSE
    IF NOT EXISTS (SELECT 1 FROM public.tier_master WHERE id = v_tier_id AND merchant_id = v_merchant_id) THEN
      RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND',
        'title', 'Not Found', 'description', 'Tier not found or access denied');
    END IF;

    UPDATE public.tier_master SET
      tier_name = COALESCE(NULLIF(tier_data->>'tier_name', ''), tier_name),
      user_type = v_user_type,
      icon = COALESCE(tier_data->>'icon', icon),
      color = COALESCE(tier_data->>'color', color),
      burn_rate = CASE WHEN tier_data ? 'burn_rate' THEN v_burn_rate ELSE burn_rate END
    WHERE id = v_tier_id;

    SELECT tier_name INTO v_tier_name FROM public.tier_master WHERE id = v_tier_id;
  END IF;

  IF v_is_create OR v_personas_provided THEN
    v_sync_result := public.fn_sync_tier_persona_assignments(v_tier_id, v_merchant_id, v_persona_ids);
  ELSE
    v_sync_result := jsonb_build_object('tier_id', v_tier_id,
      'persona_ids', to_jsonb(public.fn_tier_persona_ids(v_tier_id)), 'deleted', 0, 'inserted', 0);
  END IF;

  -- ========== UPGRADE amounts ==========
  IF jsonb_typeof(tier_data->'upgrade') = 'array' THEN
    FOR v_condition IN SELECT * FROM jsonb_array_elements(tier_data->'upgrade') LOOP
      v_condition_id := NULLIF(v_condition->>'id', '')::uuid;

      IF v_condition_id IS NOT NULL
         AND EXISTS (SELECT 1 FROM public.tier_conditions WHERE id = v_condition_id AND tier_id = v_tier_id) THEN
        UPDATE public.tier_conditions SET
          amount = COALESCE((v_condition->>'amount')::numeric, amount),
          active_status = COALESCE((v_condition->>'active_status')::boolean, active_status)
        WHERE id = v_condition_id AND merchant_id = v_merchant_id;
        v_upgrade_updated := v_upgrade_updated + 1;
      ELSE
        INSERT INTO public.tier_conditions (
          merchant_id, tier_id, condition_type, amount, active_status
        ) VALUES (
          v_merchant_id, v_tier_id, 'upgrade'::tier_conditions_type,
          COALESCE((v_condition->>'amount')::numeric, 0),
          COALESCE((v_condition->>'active_status')::boolean, true)
        )
        RETURNING id INTO v_condition_id;
        v_upgrade_created := v_upgrade_created + 1;
      END IF;
      v_upgrade_ids := array_append(v_upgrade_ids, v_condition_id);
    END LOOP;

    DELETE FROM public.tier_conditions
    WHERE tier_id = v_tier_id AND condition_type = 'upgrade'
      AND NOT (id = ANY(v_upgrade_ids));
    GET DIAGNOSTICS v_upgrade_deleted = ROW_COUNT;
  END IF;


  RETURN jsonb_build_object(
    'success', true,
    'code', CASE WHEN v_is_create THEN 'CREATED' ELSE 'UPDATED' END,
    'title', CASE WHEN v_is_create THEN 'Tier Created' ELSE 'Tier Updated' END,
    'description', format('Tier "%s" %s successfully', v_tier_name,
      CASE WHEN v_is_create THEN 'created' ELSE 'updated' END),
    'data', jsonb_build_object(
      'tier_id', v_tier_id,
      'operation', CASE WHEN v_is_create THEN 'created' ELSE 'updated' END,
      'persona_ids', public.fn_tier_persona_ids(v_tier_id),
      'personas', public.fn_tier_personas_json(v_tier_id),
      'burn_rate', v_burn_rate,
      'stats', jsonb_build_object(
        'personas', v_sync_result,
        'upgrade', jsonb_build_object('created', v_upgrade_created, 'updated', v_upgrade_updated, 'deleted', v_upgrade_deleted)
      )
    )
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'code', 'ERROR', 'title', 'Error',
    'description', SQLERRM, 'detail', SQLSTATE);
END;
$function$
