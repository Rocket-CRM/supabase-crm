-- Earn conditions: drop AND/OR/EACH as merchant config.
-- Group cards are always ALL. Listed IDs match any line.
-- Thresholds apply only on multiplier evaluation, EACH per listed entity.

-- 1) Split AND multi-id cards into one row per id (group ALL = old AND)
INSERT INTO earn_conditions (
    id, group_id, entity, entity_ids, merchant_id, created_at,
    threshold_unit, min_threshold, max_threshold, apply_to_excess_only, operator, exclude
)
SELECT
    gen_random_uuid(),
    c.group_id,
    c.entity,
    ARRAY[extra_id]::uuid[],
    c.merchant_id,
    c.created_at,
    c.threshold_unit,
    c.min_threshold,
    c.max_threshold,
    c.apply_to_excess_only,
    'OR',
    c.exclude
FROM earn_conditions c
CROSS JOIN LATERAL unnest(c.entity_ids[2:array_length(c.entity_ids, 1)]) AS extra_id
WHERE c.operator = 'AND'
  AND COALESCE(array_length(c.entity_ids, 1), 0) > 1;

UPDATE earn_conditions
SET entity_ids = entity_ids[1:1],
    operator = 'OR'
WHERE operator = 'AND'
  AND COALESCE(array_length(entity_ids, 1), 0) > 1;

-- 2) Dummy thresholds (unit set, min missing or 0) are not bars
UPDATE earn_conditions
SET threshold_unit = NULL,
    min_threshold = NULL,
    max_threshold = NULL,
    apply_to_excess_only = false
WHERE threshold_unit IS NOT NULL
  AND (min_threshold IS NULL OR min_threshold = 0);

-- 3) Rates cannot carry a bar — strip when the group has no multiplier
UPDATE earn_conditions c
SET threshold_unit = NULL,
    min_threshold = NULL,
    max_threshold = NULL,
    apply_to_excess_only = false
WHERE (c.min_threshold IS NOT NULL OR c.threshold_unit IS NOT NULL)
  AND EXISTS (
      SELECT 1 FROM earn_factor f
      WHERE f.earn_conditions_group_id = c.group_id
        AND f.earn_factor_type = 'rate'
  )
  AND NOT EXISTS (
      SELECT 1 FROM earn_factor f
      WHERE f.earn_conditions_group_id = c.group_id
        AND f.earn_factor_type = 'multiplier'
  );

DROP FUNCTION IF EXISTS public.evaluate_earn_conditions_core(uuid, uuid, uuid, jsonb, uuid);

CREATE FUNCTION public.evaluate_earn_conditions_core(
    p_merchant_id uuid,
    p_user_id uuid,
    p_store_id uuid,
    p_items jsonb,
    p_earn_conditions_group_id uuid,
    p_apply_thresholds boolean DEFAULT false
)
RETURNS TABLE(conditions_met boolean, matched_items uuid[], matched_amounts numeric[])
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_all_conditions_met       BOOLEAN   := TRUE;
    v_matched_items            UUID[]    := '{}';
    v_matched_amounts          NUMERIC[] := '{}';
    v_matched_ords             INTEGER[] := '{}';
    v_exclude_ords             INTEGER[] := '{}';
    v_has_include_product_cond BOOLEAN   := FALSE;
    v_has_exclude_cond         BOOLEAN   := FALSE;
    v_condition                RECORD;
    v_temp_items               UUID[];
    v_temp_amounts             NUMERIC[];
    v_temp_ords                INTEGER[];
    v_store_uuid               UUID;
    v_total_quantity           NUMERIC;
    v_total_amount             NUMERIC;
    v_threshold_value          NUMERIC;
    v_entity_id                UUID;
    v_i                        INTEGER;
    v_measured_total           NUMERIC;
    v_proportion               NUMERIC;
    v_use_each                 BOOLEAN;
    v_card_items               UUID[];
    v_card_amounts             NUMERIC[];
    v_card_ords                INTEGER[];
BEGIN
    IF p_earn_conditions_group_id IS NULL THEN
        RETURN QUERY SELECT TRUE, NULL::UUID[], NULL::NUMERIC[];
        RETURN;
    END IF;

    v_store_uuid := p_store_id;

    FOR v_condition IN
        SELECT ec.entity, ec.entity_ids, ec.threshold_unit, ec.min_threshold,
               ec.max_threshold, ec.apply_to_excess_only
        FROM earn_conditions ec
        WHERE ec.group_id       = p_earn_conditions_group_id
          AND ec.merchant_id    = p_merchant_id
          AND ec.exclude        = false
    LOOP
        CASE v_condition.entity
            WHEN 'tier' THEN
                IF NOT EXISTS (
                    SELECT 1 FROM user_accounts
                    WHERE id = p_user_id AND tier_id = ANY(v_condition.entity_ids)
                      AND merchant_id = p_merchant_id
                ) THEN
                    v_all_conditions_met := FALSE; EXIT;
                END IF;

            WHEN 'type' THEN
                IF NOT EXISTS (
                    SELECT 1 FROM user_accounts
                    WHERE id = p_user_id AND type_id = ANY(v_condition.entity_ids)
                      AND merchant_id = p_merchant_id
                ) THEN
                    v_all_conditions_met := FALSE; EXIT;
                END IF;

            WHEN 'persona' THEN
                IF NOT EXISTS (
                    SELECT 1 FROM user_accounts
                    WHERE id = p_user_id AND persona_id = ANY(v_condition.entity_ids)
                      AND merchant_id = p_merchant_id
                ) THEN
                    v_all_conditions_met := FALSE; EXIT;
                END IF;

            WHEN 'store' THEN
                IF v_store_uuid IS NULL OR NOT (v_store_uuid = ANY(v_condition.entity_ids)) THEN
                    v_all_conditions_met := FALSE; EXIT;
                END IF;

            WHEN 'store_attribute_set' THEN
                IF v_store_uuid IS NULL OR NOT store_matches_any_attribute_set(v_store_uuid, v_condition.entity_ids) THEN
                    v_all_conditions_met := FALSE; EXIT;
                END IF;

            WHEN 'product_sku', 'product_product', 'product_brand', 'product_category' THEN
                v_has_include_product_cond := TRUE;
                v_use_each := p_apply_thresholds
                    AND v_condition.min_threshold IS NOT NULL
                    AND v_condition.min_threshold <> 0;

                IF v_use_each THEN
                    v_card_items := '{}';
                    v_card_amounts := '{}';
                    v_card_ords := '{}';
                    FOR v_entity_id IN SELECT unnest(v_condition.entity_ids) LOOP
                        WITH resolved_items AS (
                            SELECT
                                itm.ordinality AS ord,
                                NULLIF(itm.value->>'item_id','')::uuid AS item_id,
                                psm.id as sku_id, pm.id as product_id, pm.brand_id, pm.category_id,
                                (itm.value->>'quantity')::numeric as quantity,
                                COALESCE((itm.value->>'quantity_secondary')::numeric, 0) as quantity_secondary,
                                (itm.value->>'line_total')::numeric as line_total
                            FROM jsonb_array_elements(p_items) WITH ORDINALITY AS itm(value, ordinality)
                            LEFT JOIN product_sku_master psm ON psm.sku_code = itm.value->>'sku_code' AND psm.merchant_id = p_merchant_id
                            LEFT JOIN product_master pm ON psm.product_id = pm.id
                        )
                        SELECT array_agg(ri.item_id), array_agg(ri.line_total), array_agg(ri.ord),
                               SUM(CASE WHEN v_condition.threshold_unit = 'quantity_secondary' THEN ri.quantity_secondary ELSE ri.quantity END),
                               SUM(ri.line_total)
                        INTO v_temp_items, v_temp_amounts, v_temp_ords, v_total_quantity, v_total_amount
                        FROM resolved_items ri
                        WHERE (
                            (v_condition.entity = 'product_sku'      AND ri.sku_id      = v_entity_id) OR
                            (v_condition.entity = 'product_product'  AND ri.product_id  = v_entity_id) OR
                            (v_condition.entity = 'product_brand'    AND ri.brand_id    = v_entity_id) OR
                            (v_condition.entity = 'product_category' AND ri.category_id = v_entity_id)
                        );

                        IF v_temp_items IS NULL OR array_length(v_temp_items, 1) = 0 THEN CONTINUE; END IF;

                        v_threshold_value := CASE WHEN v_condition.threshold_unit = 'amount' THEN v_total_amount ELSE v_total_quantity END;
                        IF v_threshold_value < v_condition.min_threshold THEN CONTINUE; END IF;

                        IF v_condition.max_threshold IS NOT NULL THEN
                            v_measured_total := CASE WHEN v_condition.threshold_unit = 'amount' THEN v_total_amount ELSE v_total_quantity END;
                            IF v_measured_total > v_condition.max_threshold THEN
                                v_proportion := v_condition.max_threshold / v_measured_total;
                                FOR v_i IN 1..array_length(v_temp_amounts, 1) LOOP
                                    v_temp_amounts[v_i] := v_temp_amounts[v_i] * v_proportion;
                                END LOOP;
                            END IF;
                        END IF;

                        IF COALESCE(v_condition.apply_to_excess_only, false) THEN
                            v_measured_total := CASE WHEN v_condition.threshold_unit = 'amount' THEN v_total_amount ELSE v_total_quantity END;
                            v_proportion := GREATEST(0, v_measured_total - v_condition.min_threshold) / NULLIF(v_measured_total, 0);
                            IF v_proportion IS NULL THEN CONTINUE; END IF;
                            FOR v_i IN 1..array_length(v_temp_amounts, 1) LOOP
                                v_temp_amounts[v_i] := v_temp_amounts[v_i] * v_proportion;
                            END LOOP;
                        END IF;

                        v_card_items   := v_card_items   || v_temp_items;
                        v_card_amounts := v_card_amounts || v_temp_amounts;
                        v_card_ords    := v_card_ords    || v_temp_ords;
                    END LOOP;

                    IF array_length(v_card_items, 1) IS NULL OR array_length(v_card_items, 1) = 0 THEN
                        v_all_conditions_met := FALSE; EXIT;
                    END IF;
                    v_matched_items   := v_matched_items   || v_card_items;
                    v_matched_amounts := v_matched_amounts || v_card_amounts;
                    v_matched_ords    := v_matched_ords    || v_card_ords;

                ELSE
                    WITH resolved_items AS (
                        SELECT
                            itm.ordinality AS ord,
                            NULLIF(itm.value->>'item_id','')::uuid AS item_id,
                            psm.id as sku_id, pm.id as product_id, pm.brand_id, pm.category_id,
                            (itm.value->>'line_total')::numeric as line_total
                        FROM jsonb_array_elements(p_items) WITH ORDINALITY AS itm(value, ordinality)
                        LEFT JOIN product_sku_master psm ON psm.sku_code = itm.value->>'sku_code' AND psm.merchant_id = p_merchant_id
                        LEFT JOIN product_master pm ON psm.product_id = pm.id
                    )
                    SELECT array_agg(ri.item_id), array_agg(ri.line_total), array_agg(ri.ord)
                    INTO v_temp_items, v_temp_amounts, v_temp_ords
                    FROM resolved_items ri
                    WHERE (
                        (v_condition.entity = 'product_sku'      AND ri.sku_id      = ANY(v_condition.entity_ids)) OR
                        (v_condition.entity = 'product_product'  AND ri.product_id  = ANY(v_condition.entity_ids)) OR
                        (v_condition.entity = 'product_brand'    AND ri.brand_id    = ANY(v_condition.entity_ids)) OR
                        (v_condition.entity = 'product_category' AND ri.category_id = ANY(v_condition.entity_ids))
                    );

                    IF v_temp_items IS NULL OR array_length(v_temp_items, 1) = 0 THEN
                        v_all_conditions_met := FALSE; EXIT;
                    END IF;
                    v_matched_items   := v_matched_items   || v_temp_items;
                    v_matched_amounts := v_matched_amounts || v_temp_amounts;
                    v_matched_ords    := v_matched_ords    || v_temp_ords;
                END IF;

            ELSE NULL;
        END CASE;
    END LOOP;

    IF v_all_conditions_met THEN
        FOR v_condition IN
            SELECT ec.entity, ec.entity_ids
            FROM earn_conditions ec
            WHERE ec.group_id    = p_earn_conditions_group_id
              AND ec.merchant_id = p_merchant_id
              AND ec.exclude     = true
              AND ec.entity IN ('product_sku', 'product_product', 'product_brand', 'product_category')
        LOOP
            v_has_exclude_cond := TRUE;

            WITH resolved AS (
                SELECT
                    itm.ordinality AS ord,
                    psm.id as sku_id, pm.id as product_id, pm.brand_id, pm.category_id
                FROM jsonb_array_elements(p_items) WITH ORDINALITY AS itm(value, ordinality)
                LEFT JOIN product_sku_master psm ON psm.sku_code = itm.value->>'sku_code' AND psm.merchant_id = p_merchant_id
                LEFT JOIN product_master pm ON psm.product_id = pm.id
            )
            SELECT array_agg(r.ord)
            INTO v_temp_ords
            FROM resolved r
            WHERE (
                (v_condition.entity = 'product_sku'      AND r.sku_id      = ANY(v_condition.entity_ids)) OR
                (v_condition.entity = 'product_product'  AND r.product_id  = ANY(v_condition.entity_ids)) OR
                (v_condition.entity = 'product_brand'    AND r.brand_id    = ANY(v_condition.entity_ids)) OR
                (v_condition.entity = 'product_category' AND r.category_id = ANY(v_condition.entity_ids))
            );

            IF v_temp_ords IS NOT NULL THEN
                v_exclude_ords := v_exclude_ords || v_temp_ords;
            END IF;
        END LOOP;

        IF v_has_exclude_cond THEN
            IF NOT v_has_include_product_cond THEN
                WITH all_items AS (
                    SELECT
                        itm.ordinality AS ord,
                        NULLIF(itm.value->>'item_id','')::uuid AS item_id,
                        (itm.value->>'line_total')::numeric as amount
                    FROM jsonb_array_elements(p_items) WITH ORDINALITY AS itm(value, ordinality)
                )
                SELECT array_agg(item_id), array_agg(amount)
                INTO v_matched_items, v_matched_amounts
                FROM all_items
                WHERE ord <> ALL(v_exclude_ords);
            ELSE
                WITH paired AS (
                    SELECT unnest(v_matched_ords)    AS ord,
                           unnest(v_matched_items)   AS item_id,
                           unnest(v_matched_amounts) AS amount
                )
                SELECT array_agg(item_id), array_agg(amount)
                INTO v_matched_items, v_matched_amounts
                FROM paired
                WHERE ord <> ALL(v_exclude_ords);
            END IF;

            IF v_matched_items IS NULL OR array_length(v_matched_items, 1) = 0 THEN
                v_all_conditions_met := FALSE;
                v_matched_items   := '{}';
                v_matched_amounts := '{}';
            END IF;
        END IF;
    END IF;

    RETURN QUERY SELECT
        v_all_conditions_met,
        CASE WHEN array_length(v_matched_items,   1) > 0 THEN v_matched_items   ELSE NULL END,
        CASE WHEN array_length(v_matched_amounts, 1) > 0 THEN v_matched_amounts ELSE NULL END;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.evaluate_earn_conditions_core(uuid, uuid, uuid, jsonb, uuid, boolean) TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.evaluate_earn_conditions(
    p_merchant_id uuid,
    p_user_id uuid,
    p_transaction_id uuid,
    p_earn_conditions_group_id uuid
)
RETURNS TABLE(conditions_met boolean, matched_items uuid[], matched_amounts numeric[])
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_store_id UUID;
    v_items JSONB := '[]'::jsonb;
    v_apply_thresholds BOOLEAN := false;
BEGIN
    SELECT sm.id INTO v_store_id
    FROM purchase_ledger pl
    LEFT JOIN store_master sm ON pl.store_code = sm.store_code AND sm.merchant_id = p_merchant_id
    WHERE pl.id = p_transaction_id;

    IF v_store_id IS NULL THEN
        SELECT pl.store_id INTO v_store_id
        FROM purchase_ledger pl WHERE pl.id = p_transaction_id;
    END IF;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'sku_code', pil.sku_code,
        'quantity', pil.quantity,
        'quantity_secondary', pil.quantity_secondary,
        'unit_price', pil.unit_price,
        'line_total', pil.line_total,
        'item_id', pil.id
    )), '[]'::jsonb)
    INTO v_items
    FROM purchase_items_ledger pil
    WHERE pil.transaction_id = p_transaction_id AND pil.merchant_id = p_merchant_id;

    SELECT EXISTS (
        SELECT 1 FROM earn_factor f
        WHERE f.earn_conditions_group_id = p_earn_conditions_group_id
          AND f.earn_factor_type = 'multiplier'
    ) AND NOT EXISTS (
        SELECT 1 FROM earn_factor f
        WHERE f.earn_conditions_group_id = p_earn_conditions_group_id
          AND f.earn_factor_type = 'rate'
    )
    INTO v_apply_thresholds;

    RETURN QUERY
    SELECT ecc.conditions_met, ecc.matched_items, ecc.matched_amounts
    FROM evaluate_earn_conditions_core(
        p_merchant_id, p_user_id, v_store_id, v_items,
        p_earn_conditions_group_id, v_apply_thresholds
    ) ecc;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_eligible_earn_factors_core(
    p_merchant_id uuid,
    p_user_id uuid,
    p_store_id uuid,
    p_items jsonb DEFAULT '[]'::jsonb,
    p_purchase_status text DEFAULT NULL::text,
    p_perspective text DEFAULT 'buyer'::text
)
RETURNS TABLE(
    earn_factor_id uuid,
    earn_factor_type text,
    target_currency currency,
    earn_factor_amount numeric,
    earn_factor_group_id uuid,
    earn_conditions_group_id uuid,
    group_stackable boolean,
    matched_item_ids uuid[],
    matched_amounts numeric[]
)
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
declare
    v_factor record;
    v_eval_result record;
    v_has_product_conditions boolean;
begin
    if coalesce(p_perspective, 'buyer') not in ('buyer', 'seller') then
      raise exception 'Invalid earn perspective: %', p_perspective;
    end if;

    for v_factor in
        select
            mv.earn_factor_id as id,
            mv.earn_factor_type::text,
            mv.target_currency,
            mv.earn_factor_amount,
            mv.earn_factor_group_id,
            mv.earn_conditions_group_id,
            mv.group_stackable as stackable
        from public.mv_earn_factors_complete mv
        join public.earn_factor_group efg on efg.id = mv.earn_factor_group_id
        where
            mv.merchant_id = p_merchant_id
            and mv.active_status = true
            and mv.public = true
            and coalesce(efg.perspective, 'buyer') = coalesce(p_perspective, 'buyer')
            and (mv.window_start is null or mv.window_start <= current_timestamp)
            and (mv.window_end is null or mv.window_end >= current_timestamp)
            and (
              p_purchase_status is null
              or p_purchase_status = any(coalesce(mv.allowed_purchase_statuses, array['completed']::text[]))
            )

        union all

        select
            mvu.earn_factor_id as id,
            mvu.earn_factor_type::text,
            mvu.target_currency,
            mvu.earn_factor_amount,
            mvu.earn_factor_group_id,
            mvu.earn_conditions_group_id,
            coalesce(efg.stackable, true) as stackable
        from public.mv_earn_factor_users mvu
        left join public.earn_factor_group efg on mvu.earn_factor_group_id = efg.id
        where
            mvu.merchant_id = p_merchant_id
            and mvu.user_id = p_user_id
            and coalesce(efg.perspective, 'buyer') = coalesce(p_perspective, 'buyer')
            and mvu.window_end >= current_timestamp
            and (
              p_purchase_status is null
              or p_purchase_status = any(coalesce(mvu.allowed_purchase_statuses, array['completed']::text[]))
            )
    loop
        if v_factor.earn_factor_type = 'multiplier'
           and not public.fn_merchant_shopify_feature_enabled(p_merchant_id, 'earn', 'earn.multiplier') then
            continue;
        end if;

        if v_factor.earn_factor_type = 'multiplier'
           and v_factor.earn_conditions_group_id is not null
           and not public.fn_merchant_shopify_feature_enabled(p_merchant_id, 'currency', 'currency.multiplier_by_product') then
            select exists (
                select 1
                from public.earn_conditions ec
                where ec.group_id = v_factor.earn_conditions_group_id
                  and ec.merchant_id = p_merchant_id
                  and ec.exclude = false
                  and ec.entity in (
                    'product_sku', 'product_product', 'product_brand', 'product_category'
                  )
            ) into v_has_product_conditions;

            if v_has_product_conditions then
                continue;
            end if;
        end if;

        if v_factor.earn_factor_type = 'rate'
           and not public.fn_merchant_shopify_feature_enabled(p_merchant_id, 'tier', 'tier.per_tier_earn_rate')
           and exists (
                select 1
                from public.earn_factor ef
                where ef.id = v_factor.id
                  and ef.target_entity_id is not null
                  and ef.target_currency = 'points'::currency
           ) then
            continue;
        end if;

        if v_factor.earn_conditions_group_id is not null then
            select * into v_eval_result
            from evaluate_earn_conditions_core(
                p_merchant_id,
                p_user_id,
                p_store_id,
                p_items,
                v_factor.earn_conditions_group_id,
                v_factor.earn_factor_type = 'multiplier'
            );

            if not coalesce(v_eval_result.conditions_met, false) then
                continue;
            end if;

            return query
            select
                v_factor.id,
                v_factor.earn_factor_type,
                v_factor.target_currency,
                v_factor.earn_factor_amount,
                v_factor.earn_factor_group_id,
                v_factor.earn_conditions_group_id,
                v_factor.stackable,
                v_eval_result.matched_items,
                v_eval_result.matched_amounts;
        else
            return query
            select
                v_factor.id,
                v_factor.earn_factor_type,
                v_factor.target_currency,
                v_factor.earn_factor_amount,
                v_factor.earn_factor_group_id,
                v_factor.earn_conditions_group_id,
                v_factor.stackable,
                null::uuid[],
                null::numeric[];
        end if;
    end loop;

    return;
end;
$function$;
