CREATE OR REPLACE FUNCTION public.fn_check_reward_group_limits(p_user_id uuid, p_reward_id uuid, p_quantity integer, p_merchant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_group_ids UUID[];
    v_group_id  UUID;
    v_group_name TEXT;
    v_limit RECORD;
    v_limit_window_start TIMESTAMPTZ;
    v_limit_count NUMERIC;
    v_sibling_reward_ids UUID[];
    v_will_add_distinct INT;
BEGIN
    SELECT reward_group_ids INTO v_group_ids
    FROM reward_master
    WHERE id = p_reward_id AND merchant_id = p_merchant_id;

    IF v_group_ids IS NULL OR array_length(v_group_ids, 1) IS NULL THEN
        RETURN jsonb_build_object('allowed', true);
    END IF;

    FOREACH v_group_id IN ARRAY v_group_ids LOOP
        SELECT rg.name INTO v_group_name
        FROM reward_group rg
        WHERE rg.id = v_group_id
          AND rg.merchant_id = p_merchant_id
          AND rg.is_active = true;

        IF v_group_name IS NULL THEN CONTINUE; END IF;

        SELECT ARRAY_AGG(rm.id) INTO v_sibling_reward_ids
        FROM reward_master rm
        WHERE rm.merchant_id = p_merchant_id
          AND rm.reward_group_ids @> ARRAY[v_group_id];

        FOR v_limit IN
            SELECT * FROM transaction_limits
            WHERE entity_id = v_group_id
              AND entity_type = 'reward_group'
              AND merchant_id = p_merchant_id
              AND active_status = true
        LOOP
            v_limit_window_start := CASE v_limit.time_unit
                WHEN 'day'      THEN date_trunc('day',   CURRENT_TIMESTAMP)
                WHEN 'week'     THEN date_trunc('week',  CURRENT_TIMESTAMP)
                WHEN 'month'    THEN date_trunc('month', CURRENT_TIMESTAMP)
                WHEN 'year'     THEN date_trunc('year',  CURRENT_TIMESTAMP)
                WHEN 'all_time' THEN NULL
                ELSE NULL
            END;

            IF v_limit.window_start IS NOT NULL AND CURRENT_TIMESTAMP < v_limit.window_start THEN CONTINUE; END IF;
            IF v_limit.window_end   IS NOT NULL AND CURRENT_TIMESTAMP > v_limit.window_end   THEN CONTINUE; END IF;
            IF v_limit.window_start IS NOT NULL AND v_limit_window_start IS NOT NULL THEN
                v_limit_window_start := GREATEST(v_limit_window_start, v_limit.window_start);
            ELSIF v_limit.window_start IS NOT NULL THEN
                v_limit_window_start := v_limit.window_start;
            END IF;

            IF v_limit.metric = 'distinct_reward' THEN
                -- Count how many distinct reward_ids the user has redeemed in this group
                -- within the window. Only scope='user' reaches here (CHECK constraint).
                SELECT COUNT(DISTINCT reward_id) INTO v_limit_count
                FROM reward_redemptions_ledger
                WHERE user_id = p_user_id
                  AND reward_id = ANY(v_sibling_reward_ids)
                  AND redeemed_status = true
                  AND (cancelled IS NOT TRUE)
                  AND (source_type IS NULL OR source_type NOT IN ('package_assignment','persona_entitlement'))
                  AND (v_limit_window_start IS NULL OR created_at >= v_limit_window_start);

                -- Only increment the distinct count if this reward is NEW to the user within
                -- the window. Re-redeeming a reward they already hold does not grow distinct.
                v_will_add_distinct := CASE
                    WHEN EXISTS (
                        SELECT 1 FROM reward_redemptions_ledger
                        WHERE user_id = p_user_id
                          AND reward_id = p_reward_id
                          AND redeemed_status = true
                          AND (cancelled IS NOT TRUE)
                          AND (source_type IS NULL OR source_type NOT IN ('package_assignment','persona_entitlement'))
                          AND (v_limit_window_start IS NULL OR created_at >= v_limit_window_start)
                    ) THEN 0 ELSE 1
                END;

                IF v_limit_count + v_will_add_distinct > v_limit.count THEN
                    RETURN jsonb_build_object(
                        'allowed', false,
                        'group_id', v_group_id,
                        'group_name', v_group_name,
                        'metric', 'distinct_reward',
                        'limit_scope', v_limit.scope::text,
                        'limit_count', v_limit.count,
                        'time_unit', v_limit.time_unit::text,
                        'current_count', v_limit_count,
                        'remaining', GREATEST(v_limit.count - v_limit_count, 0),
                        'requested', v_will_add_distinct,
                        'title', 'Reward type limit reached',
                        'description', format(
                            'You can pick up to %s distinct reward(s) in %s. You have already picked %s.',
                            v_limit.count, v_group_name, v_limit_count)
                    );
                END IF;

            ELSE
                -- metric = 'quantity' (existing behavior)
                IF v_limit.scope = 'user' THEN
                    SELECT COALESCE(SUM(qty), 0) INTO v_limit_count
                    FROM reward_redemptions_ledger
                    WHERE user_id = p_user_id
                      AND reward_id = ANY(v_sibling_reward_ids)
                      AND redeemed_status = true
                      AND (cancelled IS NOT TRUE)
                      AND (source_type IS NULL OR source_type NOT IN ('package_assignment','persona_entitlement'))
                      AND (v_limit_window_start IS NULL OR created_at >= v_limit_window_start);
                ELSIF v_limit.scope = 'total' THEN
                    SELECT COALESCE(SUM(qty), 0) INTO v_limit_count
                    FROM reward_redemptions_ledger
                    WHERE reward_id = ANY(v_sibling_reward_ids)
                      AND merchant_id = p_merchant_id
                      AND redeemed_status = true
                      AND (cancelled IS NOT TRUE)
                      AND (v_limit_window_start IS NULL OR created_at >= v_limit_window_start);
                END IF;

                IF v_limit_count + p_quantity > v_limit.count THEN
                    RETURN jsonb_build_object(
                        'allowed', false,
                        'group_id', v_group_id,
                        'group_name', v_group_name,
                        'metric', 'quantity',
                        'limit_scope', v_limit.scope::text,
                        'limit_count', v_limit.count,
                        'time_unit', v_limit.time_unit::text,
                        'current_count', v_limit_count,
                        'remaining', GREATEST(v_limit.count - v_limit_count, 0),
                        'requested', p_quantity
                    );
                END IF;
            END IF;
        END LOOP;
    END LOOP;

    RETURN jsonb_build_object('allowed', true);
END;
$function$
