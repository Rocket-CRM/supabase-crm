-- Tier ranking: auto-assign on create, insert-at-slot shift, repair duplicate-zero merchants

-- 1) Repair merchants where every tier was stuck at ranking = 0 (admin create default bug)
WITH merchants AS (
    SELECT merchant_id
    FROM tier_master
    GROUP BY merchant_id
    HAVING count(*) FILTER (WHERE ranking = 0) > 1
),
ordered AS (
    SELECT tm.id,
           ROW_NUMBER() OVER (
               PARTITION BY tm.merchant_id
               ORDER BY tm.created_at, tm.tier_name, tm.id
           ) - 1 AS new_rank
    FROM tier_master tm
    JOIN merchants m ON m.merchant_id = tm.merchant_id
)
UPDATE tier_master tm
SET ranking = o.new_rank
FROM ordered o
WHERE tm.id = o.id;

-- 2) Suggest next ranking in new-tier form template
CREATE OR REPLACE FUNCTION public.get_tier_conditions_by_type(p_mode text DEFAULT 'edit'::text, p_tier_id uuid DEFAULT NULL::uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_merchant_id uuid;
    v_tier_record record;
    v_upgrade_conditions jsonb;
    v_maintain_conditions jsonb;
    v_suggested_ranking smallint;
BEGIN
    v_merchant_id := get_current_merchant_id();

    IF v_merchant_id IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'No merchant context found');
    END IF;

    IF p_mode = 'new' THEN
        SELECT COALESCE(MAX(ranking), -1) + 1
        INTO v_suggested_ranking
        FROM tier_master
        WHERE merchant_id = v_merchant_id;

        RETURN json_build_object(
            'mode', 'new', 'tier_id', NULL, 'tier_name', NULL, 'user_type', NULL,
            'persona_id', NULL, 'persona_ids', '[]'::jsonb, 'personas', '[]'::jsonb,
            'ranking', v_suggested_ranking, 'entry_tier', NULL, 'created_at', NULL,
            'upgrade', '[]'::jsonb, 'maintain', '[]'::jsonb
        );
    END IF;

    IF p_tier_id IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'tier_id is required for edit mode');
    END IF;

    SELECT id, tier_name, user_type, persona_id, ranking, entry_tier, created_at
    INTO v_tier_record
    FROM tier_master
    WHERE id = p_tier_id AND merchant_id = v_merchant_id;

    IF v_tier_record.id IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'Tier not found or access denied');
    END IF;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', tc.id,
        'condition_type', tc.condition_type,
        'metric', tc.metric,
        'amount', tc.amount,
        'window_type', tc.window_type,
        'window_months', tc.window_months,
        'frequency', tc.frequency,
        'window_start', tc.window_start,
        'window_start_field', tc.window_start_field,
        'active_status', tc.active_status,
        'upgrade_evaluation_timing', tc.upgrade_evaluation_timing,
        'upgrade_evaluation_value', tc.upgrade_evaluation_value
    ) ORDER BY tc.metric), '[]'::jsonb)
    INTO v_upgrade_conditions
    FROM tier_conditions tc
    WHERE tc.tier_id = p_tier_id
      AND tc.merchant_id = v_merchant_id
      AND tc.condition_type = 'upgrade';

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', tc.id,
        'condition_type', tc.condition_type,
        'metric', tc.metric,
        'amount', tc.amount,
        'window_type', tc.window_type,
        'window_months', tc.window_months,
        'frequency', tc.frequency,
        'window_start', tc.window_start,
        'window_start_field', tc.window_start_field,
        'active_status', tc.active_status
    ) ORDER BY tc.metric), '[]'::jsonb)
    INTO v_maintain_conditions
    FROM tier_conditions tc
    WHERE tc.tier_id = p_tier_id
      AND tc.merchant_id = v_merchant_id
      AND tc.condition_type = 'maintain';

    RETURN json_build_object(
        'mode', 'edit',
        'tier_id', v_tier_record.id,
        'tier_name', v_tier_record.tier_name,
        'user_type', v_tier_record.user_type,
        'persona_id', v_tier_record.persona_id,
        'persona_ids', fn_tier_persona_ids(v_tier_record.id),
        'personas', fn_tier_personas_json(v_tier_record.id),
        'ranking', v_tier_record.ranking,
        'entry_tier', v_tier_record.entry_tier,
        'created_at', v_tier_record.created_at,
        'upgrade', v_upgrade_conditions,
        'maintain', v_maintain_conditions
    );
END;
$function$;

-- 3) Auto-assign ranking + insert-at-slot shift on save
CREATE OR REPLACE FUNCTION public.bff_upsert_tier_with_conditions(tier_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_tier_id uuid;
    v_merchant_id uuid;
    v_tier_name text;
    v_persona_ids uuid[] := ARRAY[]::uuid[];
    v_personas_provided boolean := false;
    v_burn_rate numeric;
    v_is_create boolean := false;
    v_entry_tier boolean;
    v_effective_entry_tier boolean;
    v_effective_user_type user_type;
    v_sync_result jsonb;
    v_condition jsonb;
    v_condition_id uuid;
    v_upgrade_ids uuid[] := ARRAY[]::uuid[];
    v_maintain_ids uuid[] := ARRAY[]::uuid[];
    v_upgrade_created int := 0;
    v_upgrade_updated int := 0;
    v_upgrade_deleted int := 0;
    v_maintain_created int := 0;
    v_maintain_updated int := 0;
    v_maintain_deleted int := 0;
    v_ranking smallint;
    v_old_ranking smallint;
    v_ranking_provided boolean := false;
BEGIN
    v_merchant_id := get_current_merchant_id();
    IF v_merchant_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'NO_MERCHANT_CONTEXT', 'title', 'Error', 'description', 'No merchant context found');
    END IF;

    v_tier_id := COALESCE(
        NULLIF(tier_data->>'tier_id', '')::uuid,
        NULLIF(tier_data->>'id', '')::uuid
    );
    v_tier_name := COALESCE(tier_data->>'tier_name', 'Untitled Tier');
    v_burn_rate := NULLIF(tier_data->>'burn_rate', '')::numeric;
    v_entry_tier := NULLIF(tier_data->>'entry_tier', '')::boolean;
    v_ranking_provided := tier_data ? 'ranking' AND NULLIF(tier_data->>'ranking', '') IS NOT NULL;

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
            RETURN jsonb_build_object('success', false, 'code', 'INVALID_PERSONAS', 'title', 'Invalid Personas', 'description', 'persona_ids must be an array');
        END IF;
    ELSIF tier_data ? 'persona_id' THEN
        v_personas_provided := true;
        v_persona_ids := CASE
            WHEN NULLIF(tier_data->>'persona_id', '') IS NULL THEN ARRAY[]::uuid[]
            ELSE ARRAY[NULLIF(tier_data->>'persona_id', '')::uuid]
        END;
    END IF;

    IF v_burn_rate IS NOT NULL AND v_burn_rate < 0 THEN
        RETURN jsonb_build_object('success', false, 'code', 'INVALID_BURN_RATE', 'title', 'Invalid Burn Rate', 'description', 'Burn rate must be zero or greater');
    END IF;

    IF array_length(v_persona_ids, 1) IS NOT NULL THEN
        IF EXISTS (
            SELECT 1
            FROM unnest(v_persona_ids) AS persona_id
            WHERE NOT EXISTS (
                SELECT 1
                FROM persona_master pm
                WHERE pm.id = persona_id
                  AND pm.merchant_id = v_merchant_id
                  AND COALESCE(pm.active_status, true) = true
            )
        ) THEN
            RETURN jsonb_build_object('success', false, 'code', 'INVALID_PERSONA', 'title', 'Invalid Persona', 'description', 'One or more personas were not found or inactive');
        END IF;
    END IF;

    IF v_tier_id IS NULL THEN
        v_is_create := true;

        IF v_ranking_provided THEN
            v_ranking := (tier_data->>'ranking')::smallint;
        ELSE
            SELECT COALESCE(MAX(ranking), -1) + 1
            INTO v_ranking
            FROM tier_master
            WHERE merchant_id = v_merchant_id;
        END IF;

        IF v_ranking IS NULL OR v_ranking < 0 THEN
            RETURN jsonb_build_object('success', false, 'code', 'INVALID_RANKING', 'title', 'Invalid Ranking', 'description', 'Ranking must be zero or greater');
        END IF;

        UPDATE tier_master
        SET ranking = ranking + 1
        WHERE merchant_id = v_merchant_id
          AND ranking >= v_ranking;

        INSERT INTO tier_master (
            merchant_id, tier_name, user_type, persona_id, ranking, entry_tier, icon, color, burn_rate
        ) VALUES (
            v_merchant_id,
            v_tier_name,
            COALESCE(tier_data->>'user_type', 'buyer')::user_type,
            CASE WHEN array_length(v_persona_ids, 1) IS NULL THEN NULL ELSE v_persona_ids[1] END,
            v_ranking,
            COALESCE(v_entry_tier, false),
            tier_data->>'icon',
            tier_data->>'color',
            v_burn_rate
        )
        RETURNING id INTO v_tier_id;
    ELSE
        IF NOT EXISTS (SELECT 1 FROM tier_master WHERE id = v_tier_id AND merchant_id = v_merchant_id) THEN
            RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND', 'title', 'Not Found', 'description', 'Tier not found or access denied');
        END IF;

        SELECT ranking
        INTO v_old_ranking
        FROM tier_master
        WHERE id = v_tier_id;

        IF v_ranking_provided THEN
            v_ranking := (tier_data->>'ranking')::smallint;

            IF v_ranking IS NULL OR v_ranking < 0 THEN
                RETURN jsonb_build_object('success', false, 'code', 'INVALID_RANKING', 'title', 'Invalid Ranking', 'description', 'Ranking must be zero or greater');
            END IF;

            IF v_ranking IS DISTINCT FROM v_old_ranking THEN
                IF v_ranking < v_old_ranking THEN
                    UPDATE tier_master
                    SET ranking = ranking + 1
                    WHERE merchant_id = v_merchant_id
                      AND id <> v_tier_id
                      AND ranking >= v_ranking
                      AND ranking < v_old_ranking;
                ELSIF v_ranking > v_old_ranking THEN
                    UPDATE tier_master
                    SET ranking = ranking - 1
                    WHERE merchant_id = v_merchant_id
                      AND id <> v_tier_id
                      AND ranking > v_old_ranking
                      AND ranking <= v_ranking;
                END IF;
            END IF;
        ELSE
            v_ranking := v_old_ranking;
        END IF;

        UPDATE tier_master SET
            tier_name = COALESCE(NULLIF(tier_data->>'tier_name', ''), tier_name),
            user_type = COALESCE(NULLIF(tier_data->>'user_type', '')::user_type, user_type),
            ranking = v_ranking,
            entry_tier = COALESCE(v_entry_tier, entry_tier),
            icon = COALESCE(tier_data->>'icon', icon),
            color = COALESCE(tier_data->>'color', color),
            burn_rate = CASE WHEN tier_data ? 'burn_rate' THEN v_burn_rate ELSE burn_rate END
        WHERE id = v_tier_id;

        SELECT tier_name INTO v_tier_name FROM tier_master WHERE id = v_tier_id;
    END IF;

    IF v_is_create OR v_personas_provided THEN
        v_sync_result := fn_sync_tier_persona_assignments(v_tier_id, v_merchant_id, v_persona_ids);
    ELSE
        v_sync_result := jsonb_build_object('tier_id', v_tier_id, 'persona_ids', to_jsonb(fn_tier_persona_ids(v_tier_id)), 'deleted', 0, 'inserted', 0);
    END IF;

    SELECT entry_tier, user_type, ranking
    INTO v_effective_entry_tier, v_effective_user_type, v_ranking
    FROM tier_master
    WHERE id = v_tier_id;

    IF COALESCE(v_effective_entry_tier, false) THEN
        UPDATE tier_master tm
        SET entry_tier = false
        WHERE tm.merchant_id = v_merchant_id
          AND tm.id <> v_tier_id
          AND tm.user_type IS NOT DISTINCT FROM v_effective_user_type
          AND fn_tier_persona_ids(tm.id) = fn_tier_persona_ids(v_tier_id);
    END IF;

    -- ========== UPGRADE conditions ==========
    IF tier_data->'upgrade' IS NOT NULL AND jsonb_typeof(tier_data->'upgrade') = 'array' THEN
        FOR v_condition IN SELECT * FROM jsonb_array_elements(tier_data->'upgrade') LOOP
            v_condition_id := NULLIF(v_condition->>'id', '')::uuid;

            IF v_condition_id IS NOT NULL AND EXISTS (SELECT 1 FROM tier_conditions WHERE id = v_condition_id AND tier_id = v_tier_id) THEN
                UPDATE tier_conditions SET
                    metric = COALESCE(NULLIF(v_condition->>'metric', '')::metric, metric),
                    amount = COALESCE((v_condition->>'amount')::numeric, amount),
                    frequency = CASE WHEN v_condition ? 'frequency'
                        THEN NULLIF(v_condition->>'frequency', '')::tier_execution_frequency
                        ELSE frequency END,
                    window_type = COALESCE(NULLIF(v_condition->>'window_type', '')::tier_evaluation_window_type, window_type),
                    window_months = COALESCE((v_condition->>'window_months')::smallint, window_months),
                    window_start = COALESCE(v_condition->>'window_start', window_start),
                    window_start_field = CASE WHEN v_condition ? 'window_start_field'
                        THEN NULLIF(v_condition->>'window_start_field', '')::anniversary_fields
                        ELSE window_start_field END,
                    active_status = COALESCE((v_condition->>'active_status')::boolean, active_status),
                    upgrade_evaluation_timing = CASE WHEN v_condition ? 'upgrade_evaluation_timing'
                        THEN NULLIF(v_condition->>'upgrade_evaluation_timing', '')
                        ELSE upgrade_evaluation_timing END,
                    upgrade_evaluation_value = CASE WHEN v_condition ? 'upgrade_evaluation_value'
                        THEN NULLIF(v_condition->>'upgrade_evaluation_value', '')
                        ELSE upgrade_evaluation_value END
                WHERE id = v_condition_id AND merchant_id = v_merchant_id;
                v_upgrade_updated := v_upgrade_updated + 1;
            ELSE
                INSERT INTO tier_conditions (
                    merchant_id, tier_id, condition_type, metric, amount, frequency,
                    window_type, window_months, window_start, window_start_field, active_status,
                    upgrade_evaluation_timing, upgrade_evaluation_value
                ) VALUES (
                    v_merchant_id,
                    v_tier_id,
                    'upgrade'::tier_conditions_type,
                    COALESCE(NULLIF(v_condition->>'metric', '')::metric, 'ticket'),
                    COALESCE((v_condition->>'amount')::numeric, 0),
                    NULLIF(v_condition->>'frequency', '')::tier_execution_frequency,
                    COALESCE(NULLIF(v_condition->>'window_type', '')::tier_evaluation_window_type, 'rolling'),
                    (v_condition->>'window_months')::smallint,
                    v_condition->>'window_start',
                    NULLIF(v_condition->>'window_start_field', '')::anniversary_fields,
                    COALESCE((v_condition->>'active_status')::boolean, true),
                    NULLIF(v_condition->>'upgrade_evaluation_timing', ''),
                    NULLIF(v_condition->>'upgrade_evaluation_value', '')
                )
                RETURNING id INTO v_condition_id;
                v_upgrade_created := v_upgrade_created + 1;
            END IF;
            v_upgrade_ids := array_append(v_upgrade_ids, v_condition_id);
        END LOOP;

        DELETE FROM tier_conditions
        WHERE tier_id = v_tier_id
          AND condition_type = 'upgrade'
          AND NOT (id = ANY(v_upgrade_ids));
        GET DIAGNOSTICS v_upgrade_deleted = ROW_COUNT;
    END IF;

    -- ========== MAINTAIN conditions ==========
    IF tier_data->'maintain' IS NOT NULL AND jsonb_typeof(tier_data->'maintain') = 'array' THEN
        FOR v_condition IN SELECT * FROM jsonb_array_elements(tier_data->'maintain') LOOP
            v_condition_id := NULLIF(v_condition->>'id', '')::uuid;

            IF v_condition_id IS NOT NULL AND EXISTS (SELECT 1 FROM tier_conditions WHERE id = v_condition_id AND tier_id = v_tier_id) THEN
                UPDATE tier_conditions SET
                    metric = COALESCE(NULLIF(v_condition->>'metric', '')::metric, metric),
                    amount = COALESCE((v_condition->>'amount')::numeric, amount),
                    frequency = CASE WHEN v_condition ? 'frequency'
                        THEN NULLIF(v_condition->>'frequency', '')::tier_execution_frequency
                        ELSE frequency END,
                    window_type = COALESCE(NULLIF(v_condition->>'window_type', '')::tier_evaluation_window_type, window_type),
                    window_months = COALESCE((v_condition->>'window_months')::smallint, window_months),
                    window_start = COALESCE(v_condition->>'window_start', window_start),
                    window_start_field = CASE WHEN v_condition ? 'window_start_field'
                        THEN NULLIF(v_condition->>'window_start_field', '')::anniversary_fields
                        ELSE window_start_field END,
                    active_status = COALESCE((v_condition->>'active_status')::boolean, active_status)
                WHERE id = v_condition_id AND merchant_id = v_merchant_id;
                v_maintain_updated := v_maintain_updated + 1;
            ELSE
                INSERT INTO tier_conditions (
                    merchant_id, tier_id, condition_type, metric, amount, frequency,
                    window_type, window_months, window_start, window_start_field, active_status
                ) VALUES (
                    v_merchant_id,
                    v_tier_id,
                    'maintain'::tier_conditions_type,
                    COALESCE(NULLIF(v_condition->>'metric', '')::metric, 'ticket'),
                    COALESCE((v_condition->>'amount')::numeric, 0),
                    NULLIF(v_condition->>'frequency', '')::tier_execution_frequency,
                    COALESCE(NULLIF(v_condition->>'window_type', '')::tier_evaluation_window_type, 'rolling'),
                    (v_condition->>'window_months')::smallint,
                    v_condition->>'window_start',
                    NULLIF(v_condition->>'window_start_field', '')::anniversary_fields,
                    COALESCE((v_condition->>'active_status')::boolean, true)
                )
                RETURNING id INTO v_condition_id;
                v_maintain_created := v_maintain_created + 1;
            END IF;
            v_maintain_ids := array_append(v_maintain_ids, v_condition_id);
        END LOOP;

        DELETE FROM tier_conditions
        WHERE tier_id = v_tier_id
          AND condition_type = 'maintain'
          AND NOT (id = ANY(v_maintain_ids));
        GET DIAGNOSTICS v_maintain_deleted = ROW_COUNT;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'code', CASE WHEN v_is_create THEN 'CREATED' ELSE 'UPDATED' END,
        'title', CASE WHEN v_is_create THEN 'Tier Created' ELSE 'Tier Updated' END,
        'description', format('Tier "%s" %s successfully', v_tier_name, CASE WHEN v_is_create THEN 'created' ELSE 'updated' END),
        'data', jsonb_build_object(
            'tier_id', v_tier_id,
            'operation', CASE WHEN v_is_create THEN 'created' ELSE 'updated' END,
            'ranking', v_ranking,
            'persona_ids', fn_tier_persona_ids(v_tier_id),
            'personas', fn_tier_personas_json(v_tier_id),
            'burn_rate', v_burn_rate,
            'stats', jsonb_build_object(
                'personas', v_sync_result,
                'upgrade', jsonb_build_object('created', v_upgrade_created, 'updated', v_upgrade_updated, 'deleted', v_upgrade_deleted),
                'maintain', jsonb_build_object('created', v_maintain_created, 'updated', v_maintain_updated, 'deleted', v_maintain_deleted)
            )
        )
    );
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'code', 'ERROR', 'title', 'Error', 'description', SQLERRM, 'detail', SQLSTATE);
END;
$function$;
