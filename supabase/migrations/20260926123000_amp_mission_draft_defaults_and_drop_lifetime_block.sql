-- AMP mission drafts: same repeat defaults as admin (loop on + 1 per member all time).
-- Then remove legacy once-per-member guard tied to allow_progress_loop = false.

CREATE OR REPLACE FUNCTION public.fn_amp_analysis_create_mission_draft(p_merchant_id uuid, p_config jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_mission_id uuid;
  v_mission_name text;
  v_conditions_created int := 0;
  v_outcomes_created int := 0;
  v_item jsonb;
  v_item_id uuid;
  v_mission_type mission_type;
  v_reset_frequency mission_progress_reset_frequency;
  v_single_sum boolean := false;
BEGIN
  v_mission_name := COALESCE(NULLIF(p_config->>'name', ''), 'AI Draft Mission');
  v_mission_type := COALESCE(NULLIF(p_config->>'type', '')::mission_type, 'standard');
  v_reset_frequency := CASE
    WHEN v_mission_type = 'milestone' THEN NULL
    ELSE NULLIF(p_config->>'reset_frequency', '')::mission_progress_reset_frequency
  END;

  v_mission_id := gen_random_uuid();

  INSERT INTO mission (
    id, merchant_id, mission_code, mission_name,
    mission_type, progress_activation_type, claim_type,
    progress_reset_frequency,
    allow_progress_loop,
    start_date, end_date, is_active
  ) VALUES (
    v_mission_id, p_merchant_id,
    'AMP_DRAFT_' || extract(epoch from now())::bigint::text,
    v_mission_name,
    v_mission_type,
    COALESCE(NULLIF(p_config->>'activation_type', '')::activation_type, 'auto'),
    COALESCE(NULLIF(p_config->>'claim_type', '')::activation_type, 'auto'),
    v_reset_frequency,
    v_mission_type <> 'milestone',
    NULLIF(p_config->>'start_date', '')::timestamptz,
    NULLIF(p_config->>'end_date', '')::timestamptz,
    false
  );

  IF p_config->'conditions' IS NOT NULL AND jsonb_typeof(p_config->'conditions') = 'array' THEN
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_config->'conditions') LOOP
      IF v_item->>'condition_type' IS NULL THEN CONTINUE; END IF;
      INSERT INTO mission_conditions (
        id, mission_id, operator, condition_type, measurement_type, target_value,
        milestone_level, min_transaction_amount
      ) VALUES (
        gen_random_uuid(), v_mission_id,
        COALESCE(NULLIF(v_item->>'operator', '')::logical_operator, 'AND'),
        (v_item->>'condition_type')::mission_condition_type,
        COALESCE(NULLIF(v_item->>'measurement_type', '')::measurement_type_enum, 'count'),
        (v_item->>'target_value')::numeric,
        (v_item->>'milestone_level')::integer,
        (v_item->>'min_transaction_amount')::numeric
      );
      v_conditions_created := v_conditions_created + 1;
    END LOOP;
  END IF;

  IF v_mission_type <> 'milestone' THEN
    SELECT COUNT(*) = 1
       AND COUNT(*) FILTER (WHERE measurement_type::text = 'sum') = 1
      INTO v_single_sum
      FROM mission_conditions
     WHERE mission_id = v_mission_id;

    UPDATE mission
       SET max_loops_per_transaction = CASE WHEN v_single_sum THEN 1 ELSE NULL END
     WHERE id = v_mission_id;

    INSERT INTO mission_limit_progress (mission_id, scope, amount, time_unit, time_value)
    VALUES (v_mission_id, 'user', 1, 'all_time', 1);
  END IF;

  IF p_config->'outcomes' IS NOT NULL AND jsonb_typeof(p_config->'outcomes') = 'array' THEN
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_config->'outcomes') LOOP
      IF v_item->>'outcome_type' IS NULL THEN CONTINUE; END IF;
      INSERT INTO mission_outcomes (id, mission_id, outcome_type, amount, milestone_level, entity_id)
      VALUES (
        gen_random_uuid(), v_mission_id,
        (v_item->>'outcome_type')::mission_outcome_type,
        (v_item->>'amount')::integer,
        (v_item->>'milestone_level')::integer,
        NULLIF(v_item->>'entity_id', '')::uuid
      );
      v_outcomes_created := v_outcomes_created + 1;
    END LOOP;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'data', jsonb_build_object(
      'mission_id', v_mission_id,
      'conditions_created', v_conditions_created,
      'outcomes_created', v_outcomes_created
    )
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM, 'detail', SQLSTATE);
END;
$function$;

-- Safety sweep before dropping the loop-off lifetime guard (idempotent with step 1).
CREATE TEMP TABLE _mission_once ON COMMIT DROP AS
SELECT m.id,
  (SELECT COUNT(*) = 1 AND COUNT(*) FILTER (WHERE c.measurement_type::text = 'sum') = 1
   FROM mission_conditions c WHERE c.mission_id = m.id) AS single_sum
FROM mission m
WHERE m.mission_type::text <> 'milestone'
  AND COALESCE(m.allow_progress_loop, false) = false;

DELETE FROM mission_limit_progress l
USING _mission_once o
WHERE l.mission_id = o.id AND l.scope::text = 'user';

INSERT INTO mission_limit_progress (mission_id, scope, amount, time_unit, time_value)
SELECT id, 'user', 1, 'all_time', 1 FROM _mission_once;

UPDATE mission m SET
  allow_progress_loop = true,
  max_loops_per_transaction = CASE WHEN o.single_sum THEN 1 ELSE NULL END
FROM _mission_once o
WHERE m.id = o.id;

DO $do$
DECLARE
  v_def text;
  v_old text;
  v_new text;
  v_hits int;
BEGIN
  SELECT pg_get_functiondef('public.fn_update_mission_progress(uuid,uuid,uuid,jsonb,text,uuid)'::regprocedure) INTO v_def;
  v_old := E'      v_loops_completed := CASE\n        WHEN v_progress_remaining <= 0 THEN 0\n        WHEN NOT COALESCE(v_mission.allow_progress_loop, false)\n             AND COALESCE(v_progress.lifetime_completions, 0) >= 1 THEN 0\n        ELSE 1\n      END;';
  v_new := E'      v_loops_completed := CASE\n        WHEN v_progress_remaining <= 0 THEN 0\n        ELSE 1\n      END;';
  v_hits := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF v_hits <> 1 THEN
    RAISE EXCEPTION 'fn_update_mission_progress lifetime-block patch matched % times (expected 1)', v_hits;
  END IF;
  EXECUTE replace(v_def, v_old, v_new);
END
$do$;
