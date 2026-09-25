CREATE OR REPLACE FUNCTION public.bff_upsert_basic_currency_config(p_config jsonb, p_language text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_lang text;
  v_merchant_id UUID;
  v_target_currency currency;
  v_target_entity_id UUID;
  v_group_id UUID;
  v_rate_config JSONB;
  v_multipliers_config JSONB;
  v_stackable BOOLEAN;
  v_different_rate_per_tier BOOLEAN;
  v_single_rate NUMERIC;
  v_excluded_products JSONB;
  v_factor_ids_to_keep UUID[] := '{}';
  v_old_cond_group_ids UUID[] := '{}';
  v_factor_id UUID;
  v_conditions_group_id UUID;
  v_rate JSONB;
  v_multiplier JSONB;
  v_product JSONB;
  v_tier_ids UUID[];
  v_timing JSONB;
  v_factors_created INT := 0;
  v_factors_updated INT := 0;
  v_factors_deleted INT := 0;
  v_conditions_groups_created INT := 0;
  v_conditions_groups_deleted INT := 0;
  v_group_created BOOLEAN := false;
  v_i INT;
  v_has_timing BOOLEAN;
  v_rate_level_statuses TEXT[];
  v_norm_statuses TEXT[];
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', fn_admin_envelope_message('no_merchant_found_title', v_lang),
    'title', fn_admin_envelope_message('error_title', v_lang),
    'description', fn_admin_envelope_message('no_merchant_found_title', v_lang));
  END IF;

  v_target_currency := (p_config->>'target_currency')::currency;
  v_target_entity_id := NULLIF(p_config->>'target_entity_id', '')::UUID;
  v_group_id := NULLIF(p_config->>'earn_factor_group_id', '')::UUID;

  v_rate_config := p_config->'earn_rate';
  v_multipliers_config := p_config->'multipliers';
  v_stackable := COALESCE((v_multipliers_config->>'stackable')::BOOLEAN, true);

  v_rate_level_statuses := ARRAY(
    SELECT lower(x)
    FROM jsonb_array_elements_text(v_rate_config->'allowed_purchase_statuses') AS x
    WHERE lower(x) IN ('pending', 'processing', 'completed')
  );
  IF array_length(v_rate_level_statuses, 1) IS NULL THEN
    v_rate_level_statuses := ARRAY['completed']::text[];
  END IF;

  IF v_group_id IS NOT NULL THEN
    SELECT COALESCE(array_agg(DISTINCT ef.earn_conditions_group_id), '{}')
    INTO v_old_cond_group_ids
    FROM earn_factor ef
    WHERE ef.earn_factor_group_id = v_group_id
      AND ef.merchant_id = v_merchant_id
      AND ef.target_currency = v_target_currency
      AND ((v_target_entity_id IS NULL AND ef.target_entity_id IS NULL) OR ef.target_entity_id = v_target_entity_id)
      AND ef.earn_conditions_group_id IS NOT NULL;
  END IF;

  -- ===== UPSERT EARN FACTOR GROUP =====
  IF v_group_id IS NULL THEN
    v_group_id := gen_random_uuid();
    INSERT INTO earn_factor_group (id, merchant_id, name, stackable, active_status)
    VALUES (v_group_id, v_merchant_id,
            'Basic ' || v_target_currency::text || ' config',
            v_stackable, true);
    v_group_created := true;
  ELSE
    UPDATE earn_factor_group
    SET stackable = v_stackable
    WHERE id = v_group_id AND merchant_id = v_merchant_id;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'error', fn_admin_envelope_message('earn_factor_group_not_found_desc', v_lang),
    'title', fn_admin_envelope_message('not_found_title', v_lang),
    'description', fn_admin_envelope_message('earn_factor_group_not_found_desc', v_lang));
    END IF;
  END IF;

  -- ===== PROCESS EARN RATES =====
  v_different_rate_per_tier := COALESCE((v_rate_config->>'different_rate_per_tier')::BOOLEAN, false);
  v_excluded_products := COALESCE(v_rate_config->'excluded_products', '[]'::jsonb);

  IF v_different_rate_per_tier AND v_rate_config->'rates' IS NOT NULL
     AND jsonb_typeof(v_rate_config->'rates') = 'array' THEN
    FOR v_rate IN SELECT * FROM jsonb_array_elements(v_rate_config->'rates')
    LOOP
      v_factor_id := NULLIF(v_rate->>'factor_id', '')::UUID;
      v_conditions_group_id := NULLIF(v_rate->>'earn_conditions_group_id', '')::UUID;

      v_norm_statuses := ARRAY(
        SELECT lower(x)
        FROM jsonb_array_elements_text(v_rate->'allowed_purchase_statuses') AS x
        WHERE lower(x) IN ('pending', 'processing', 'completed')
      );
      IF array_length(v_norm_statuses, 1) IS NULL THEN
        v_norm_statuses := v_rate_level_statuses;
      END IF;

      IF v_conditions_group_id IS NULL THEN
        v_conditions_group_id := gen_random_uuid();
        INSERT INTO earn_conditions_group (id, name, merchant_id)
        VALUES (v_conditions_group_id, 'Rate tier condition', v_merchant_id);
        v_conditions_groups_created := v_conditions_groups_created + 1;
      END IF;

      DELETE FROM earn_conditions WHERE group_id = v_conditions_group_id AND merchant_id = v_merchant_id;

      INSERT INTO earn_conditions (id, group_id, entity, entity_ids, merchant_id, exclude, operator)
      VALUES (gen_random_uuid(), v_conditions_group_id, 'tier',
              ARRAY[(v_rate->>'tier_id')::UUID], v_merchant_id, false, 'OR');

      IF jsonb_typeof(v_excluded_products) = 'array' AND jsonb_array_length(v_excluded_products) > 0 THEN
        FOR v_product IN SELECT * FROM jsonb_array_elements(v_excluded_products)
        LOOP
          INSERT INTO earn_conditions (id, group_id, entity, entity_ids, merchant_id, exclude, operator)
          VALUES (gen_random_uuid(), v_conditions_group_id,
                  (v_product->>'entity')::earn_factor_entity_type,
                  ARRAY(SELECT jsonb_array_elements_text(v_product->'entity_ids'))::UUID[],
                  v_merchant_id, true, 'OR');
        END LOOP;
      END IF;

      IF v_factor_id IS NOT NULL THEN
        UPDATE earn_factor
        SET earn_factor_amount = NULLIF(v_rate->>'earn_factor_amount', '')::NUMERIC,
            earn_conditions_group_id = v_conditions_group_id,
            allowed_purchase_statuses = v_norm_statuses,
            active_status = true
        WHERE id = v_factor_id AND earn_factor_group_id = v_group_id AND merchant_id = v_merchant_id;
        IF FOUND THEN
          v_factors_updated := v_factors_updated + 1;
        ELSE
          INSERT INTO earn_factor (id, merchant_id, earn_factor_group_id, earn_factor_type,
            earn_factor_amount, target_currency, target_entity_id, public, active_status,
            earn_conditions_group_id, allowed_purchase_statuses)
          VALUES (v_factor_id, v_merchant_id, v_group_id, 'rate',
            NULLIF(v_rate->>'earn_factor_amount', '')::NUMERIC,
            v_target_currency, v_target_entity_id, true, true, v_conditions_group_id, v_norm_statuses);
          v_factors_created := v_factors_created + 1;
        END IF;
      ELSE
        v_factor_id := gen_random_uuid();
        INSERT INTO earn_factor (id, merchant_id, earn_factor_group_id, earn_factor_type,
          earn_factor_amount, target_currency, target_entity_id, public, active_status,
          earn_conditions_group_id, allowed_purchase_statuses)
        VALUES (v_factor_id, v_merchant_id, v_group_id, 'rate',
          NULLIF(v_rate->>'earn_factor_amount', '')::NUMERIC,
          v_target_currency, v_target_entity_id, true, true, v_conditions_group_id, v_norm_statuses);
        v_factors_created := v_factors_created + 1;
      END IF;

      v_factor_ids_to_keep := array_append(v_factor_ids_to_keep, v_factor_id);
    END LOOP;

  ELSIF NOT v_different_rate_per_tier THEN
    v_single_rate := NULLIF(v_rate_config->>'single_rate', '')::NUMERIC;

    IF v_single_rate IS NOT NULL THEN
      v_factor_id := NULLIF(v_rate_config->>'single_rate_factor_id', '')::UUID;
      v_conditions_group_id := NULL;

      IF v_factor_id IS NOT NULL THEN
        SELECT earn_conditions_group_id INTO v_conditions_group_id
        FROM earn_factor
        WHERE id = v_factor_id AND earn_factor_group_id = v_group_id AND merchant_id = v_merchant_id;
      END IF;

      IF jsonb_typeof(v_excluded_products) = 'array' AND jsonb_array_length(v_excluded_products) > 0 THEN
        IF v_conditions_group_id IS NULL THEN
          v_conditions_group_id := gen_random_uuid();
          INSERT INTO earn_conditions_group (id, name, merchant_id)
          VALUES (v_conditions_group_id, 'Rate excluded products', v_merchant_id);
          v_conditions_groups_created := v_conditions_groups_created + 1;
        END IF;

        DELETE FROM earn_conditions WHERE group_id = v_conditions_group_id AND merchant_id = v_merchant_id;

        FOR v_product IN SELECT * FROM jsonb_array_elements(v_excluded_products)
        LOOP
          INSERT INTO earn_conditions (id, group_id, entity, entity_ids, merchant_id, exclude, operator)
          VALUES (gen_random_uuid(), v_conditions_group_id,
                  (v_product->>'entity')::earn_factor_entity_type,
                  ARRAY(SELECT jsonb_array_elements_text(v_product->'entity_ids'))::UUID[],
                  v_merchant_id, true, 'OR');
        END LOOP;
      ELSE
        -- No excluded products: just unlink here. The end-of-function orphan
        -- cleanup (v_old_cond_group_ids loop) deletes the now-unreferenced
        -- group AFTER earn_factor no longer points at it, satisfying the
        -- earn_factor -> earn_conditions_group ON DELETE RESTRICT FK.
        v_conditions_group_id := NULL;
      END IF;

      IF v_factor_id IS NOT NULL THEN
        UPDATE earn_factor
        SET earn_factor_amount = v_single_rate,
            earn_conditions_group_id = v_conditions_group_id,
            allowed_purchase_statuses = v_rate_level_statuses,
            active_status = true
        WHERE id = v_factor_id AND earn_factor_group_id = v_group_id AND merchant_id = v_merchant_id;
        IF FOUND THEN
          v_factors_updated := v_factors_updated + 1;
        ELSE
          v_factor_id := gen_random_uuid();
          INSERT INTO earn_factor (id, merchant_id, earn_factor_group_id, earn_factor_type,
            earn_factor_amount, target_currency, target_entity_id, public, active_status,
            earn_conditions_group_id, allowed_purchase_statuses)
          VALUES (v_factor_id, v_merchant_id, v_group_id, 'rate', v_single_rate,
            v_target_currency, v_target_entity_id, true, true, v_conditions_group_id, v_rate_level_statuses);
          v_factors_created := v_factors_created + 1;
        END IF;
      ELSE
        v_factor_id := gen_random_uuid();
        INSERT INTO earn_factor (id, merchant_id, earn_factor_group_id, earn_factor_type,
          earn_factor_amount, target_currency, target_entity_id, public, active_status,
          earn_conditions_group_id, allowed_purchase_statuses)
        VALUES (v_factor_id, v_merchant_id, v_group_id, 'rate', v_single_rate,
          v_target_currency, v_target_entity_id, true, true, v_conditions_group_id, v_rate_level_statuses);
        v_factors_created := v_factors_created + 1;
      END IF;

      v_factor_ids_to_keep := array_append(v_factor_ids_to_keep, v_factor_id);
    END IF;
  END IF;

  -- ===== PROCESS MULTIPLIERS =====
  IF v_multipliers_config->'items' IS NOT NULL
     AND jsonb_typeof(v_multipliers_config->'items') = 'array' THEN
    FOR v_multiplier IN SELECT * FROM jsonb_array_elements(v_multipliers_config->'items')
    LOOP
      v_factor_id := NULLIF(v_multiplier->>'factor_id', '')::UUID;
      v_conditions_group_id := NULLIF(v_multiplier->>'earn_conditions_group_id', '')::UUID;

      v_norm_statuses := ARRAY(
        SELECT lower(x)
        FROM jsonb_array_elements_text(v_multiplier->'allowed_purchase_statuses') AS x
        WHERE lower(x) IN ('pending', 'processing', 'completed')
      );
      IF array_length(v_norm_statuses, 1) IS NULL THEN
        v_norm_statuses := v_rate_level_statuses;
      END IF;

      v_tier_ids := COALESCE(
        ARRAY(
          SELECT (t->>'tier_id')::UUID
          FROM jsonb_array_elements(COALESCE(v_multiplier->'tiers', '[]'::jsonb)) t
          WHERE t->>'tier_id' IS NOT NULL AND t->>'tier_id' != ''
        ),
        '{}'::UUID[]
      );

      IF array_length(v_tier_ids, 1) > 0
         OR (v_multiplier->'include_products' IS NOT NULL
             AND jsonb_typeof(v_multiplier->'include_products') = 'array'
             AND jsonb_array_length(v_multiplier->'include_products') > 0) THEN

        IF v_conditions_group_id IS NULL THEN
          v_conditions_group_id := gen_random_uuid();
          INSERT INTO earn_conditions_group (id, name, merchant_id)
          VALUES (v_conditions_group_id, 'Multiplier condition', v_merchant_id);
          v_conditions_groups_created := v_conditions_groups_created + 1;
        END IF;

        DELETE FROM earn_conditions WHERE group_id = v_conditions_group_id AND merchant_id = v_merchant_id;

        IF array_length(v_tier_ids, 1) > 0 THEN
          INSERT INTO earn_conditions (id, group_id, entity, entity_ids, merchant_id, exclude, operator)
          VALUES (gen_random_uuid(), v_conditions_group_id, 'tier',
                  v_tier_ids, v_merchant_id, false, 'OR');
        END IF;

        IF v_multiplier->'include_products' IS NOT NULL
           AND jsonb_typeof(v_multiplier->'include_products') = 'array' THEN
          FOR v_product IN SELECT * FROM jsonb_array_elements(v_multiplier->'include_products')
          LOOP
            IF v_product->>'entity' IS NOT NULL
               AND v_product->'entity_ids' IS NOT NULL
               AND jsonb_array_length(v_product->'entity_ids') > 0 THEN
              INSERT INTO earn_conditions (id, group_id, entity, entity_ids, merchant_id, exclude, operator)
              VALUES (gen_random_uuid(), v_conditions_group_id,
                      (v_product->>'entity')::earn_factor_entity_type,
                      ARRAY(SELECT jsonb_array_elements_text(v_product->'entity_ids'))::UUID[],
                      v_merchant_id, false, 'OR');
            END IF;
          END LOOP;
        END IF;
      ELSE
        v_conditions_group_id := NULL;
      END IF;

      v_timing := v_multiplier->'timing';
      v_has_timing := (
        v_timing IS NOT NULL
        AND v_timing != 'null'::jsonb
        AND v_timing->'day_of_week' IS NOT NULL
        AND jsonb_typeof(v_timing->'day_of_week') = 'array'
        AND jsonb_array_length(v_timing->'day_of_week') > 0
      );

      IF v_factor_id IS NOT NULL THEN
        UPDATE earn_factor
        SET earn_factor_amount = NULLIF(v_multiplier->>'earn_factor_amount', '')::NUMERIC,
            window_start = NULLIF(v_multiplier->>'window_start', '')::TIMESTAMPTZ,
            window_end = NULLIF(v_multiplier->>'window_end', '')::TIMESTAMPTZ,
            active_status = COALESCE((v_multiplier->>'active_status')::BOOLEAN, true),
            earn_conditions_group_id = v_conditions_group_id,
            has_time_conditions = v_has_timing,
            allowed_purchase_statuses = v_norm_statuses
        WHERE id = v_factor_id AND earn_factor_group_id = v_group_id AND merchant_id = v_merchant_id;
        IF FOUND THEN
          v_factors_updated := v_factors_updated + 1;
        ELSE
          v_factor_id := gen_random_uuid();
          INSERT INTO earn_factor (id, merchant_id, earn_factor_group_id, earn_factor_type,
            earn_factor_amount, target_currency, target_entity_id, public, active_status,
            window_start, window_end, earn_conditions_group_id, has_time_conditions,
            allowed_purchase_statuses)
          VALUES (v_factor_id, v_merchant_id, v_group_id, 'multiplier',
            NULLIF(v_multiplier->>'earn_factor_amount', '')::NUMERIC,
            v_target_currency, v_target_entity_id, true,
            COALESCE((v_multiplier->>'active_status')::BOOLEAN, true),
            NULLIF(v_multiplier->>'window_start', '')::TIMESTAMPTZ,
            NULLIF(v_multiplier->>'window_end', '')::TIMESTAMPTZ,
            v_conditions_group_id, v_has_timing, v_norm_statuses);
          v_factors_created := v_factors_created + 1;
        END IF;
      ELSE
        v_factor_id := gen_random_uuid();
        INSERT INTO earn_factor (id, merchant_id, earn_factor_group_id, earn_factor_type,
          earn_factor_amount, target_currency, target_entity_id, public, active_status,
          window_start, window_end, earn_conditions_group_id, has_time_conditions,
          allowed_purchase_statuses)
        VALUES (v_factor_id, v_merchant_id, v_group_id, 'multiplier',
          NULLIF(v_multiplier->>'earn_factor_amount', '')::NUMERIC,
          v_target_currency, v_target_entity_id, true,
          COALESCE((v_multiplier->>'active_status')::BOOLEAN, true),
          NULLIF(v_multiplier->>'window_start', '')::TIMESTAMPTZ,
          NULLIF(v_multiplier->>'window_end', '')::TIMESTAMPTZ,
          v_conditions_group_id, v_has_timing, v_norm_statuses);
        v_factors_created := v_factors_created + 1;
      END IF;

      v_factor_ids_to_keep := array_append(v_factor_ids_to_keep, v_factor_id);

      DELETE FROM earn_factor_time_conditions WHERE earn_factor_id = v_factor_id;

      IF v_has_timing THEN
        INSERT INTO earn_factor_time_conditions (earn_factor_id, day_of_week, hour_start, hour_end)
        VALUES (
          v_factor_id,
          ARRAY(SELECT jsonb_array_elements_text(v_timing->'day_of_week'))::INT[],
          COALESCE(NULLIF(v_timing->>'hour_start', '')::INT, 0),
          COALESCE(NULLIF(v_timing->>'hour_end', '')::INT, 23)
        );
      END IF;
    END LOOP;
  END IF;

  -- ===== CLEANUP =====
  DELETE FROM earn_factor
  WHERE earn_factor_group_id = v_group_id
    AND merchant_id = v_merchant_id
    AND target_currency = v_target_currency
    AND ((v_target_entity_id IS NULL AND target_entity_id IS NULL) OR target_entity_id = v_target_entity_id)
    AND (array_length(v_factor_ids_to_keep, 1) IS NULL OR id != ALL(v_factor_ids_to_keep));
  GET DIAGNOSTICS v_factors_deleted = ROW_COUNT;

  DELETE FROM earn_factor_time_conditions
  WHERE earn_factor_id NOT IN (SELECT id FROM earn_factor);

  IF array_length(v_old_cond_group_ids, 1) > 0 THEN
    FOR v_i IN 1..array_length(v_old_cond_group_ids, 1)
    LOOP
      IF v_old_cond_group_ids[v_i] IS NOT NULL
         AND NOT EXISTS (
           SELECT 1 FROM earn_factor WHERE earn_conditions_group_id = v_old_cond_group_ids[v_i]
         ) THEN
        DELETE FROM earn_conditions WHERE group_id = v_old_cond_group_ids[v_i];
        DELETE FROM earn_conditions_group WHERE id = v_old_cond_group_ids[v_i];
        v_conditions_groups_deleted := v_conditions_groups_deleted + 1;
      END IF;
    END LOOP;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM earn_factor WHERE earn_factor_group_id = v_group_id) THEN
    DELETE FROM earn_factor_group WHERE id = v_group_id AND merchant_id = v_merchant_id;
    v_group_id := NULL;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'code', CASE WHEN v_group_created THEN 'CREATED' ELSE 'UPDATED' END,
    'title', CASE WHEN v_group_created THEN fn_admin_envelope_message('basic_currency_created_title', v_lang) ELSE fn_admin_envelope_message('basic_currency_updated_title', v_lang) END,
    'description', fn_admin_envelope_message('basic_currency_config_saved_desc', v_lang, ARRAY[v_target_currency::text]),
    'earn_factor_group_id', v_group_id,
    'factors_created', v_factors_created,
    'factors_updated', v_factors_updated,
    'factors_deleted', v_factors_deleted,
    'conditions_groups_created', v_conditions_groups_created,
    'conditions_groups_deleted', v_conditions_groups_deleted
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM, 'detail', SQLSTATE);
END;
$function$;
