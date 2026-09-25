-- FIFO lot tracking forward fix:
-- allocate burns in the wallet chokepoint, correct expiry arithmetic,
-- aggregate multi-batch expiry before posting, and drop the AFTER INSERT trigger.

-- 1. Internal allocator (non-exposed schema)
CREATE OR REPLACE FUNCTION util.fn_allocate_fifo_burn(
  p_user_id uuid,
  p_merchant_id uuid,
  p_currency currency,
  p_target_entity_id uuid,
  p_amount integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'public'
AS $function$
DECLARE
  v_remaining integer;
  v_lot record;
  v_deduct integer;
BEGIN
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'FIFO allocation amount must be a positive integer';
  END IF;

  v_remaining := p_amount;

  FOR v_lot IN
    SELECT id, deductible_balance
    FROM public.wallet_ledger
    WHERE user_id = p_user_id
      AND merchant_id = p_merchant_id
      AND currency = p_currency
      AND transaction_type = 'earn'::currency_transaction_type
      AND COALESCE(deductible_balance, 0) > 0
      AND expiry_processed_at IS NULL
      AND (
        CASE
          WHEN p_currency = 'points'::currency THEN target_entity_id IS NULL
          ELSE target_entity_id IS NOT DISTINCT FROM p_target_entity_id
        END
      )
    ORDER BY expiry_date ASC NULLS LAST, created_at ASC, id ASC
    FOR UPDATE
  LOOP
    v_deduct := LEAST(COALESCE(v_lot.deductible_balance, 0), v_remaining)::integer;
    IF v_deduct <= 0 THEN
      CONTINUE;
    END IF;

    UPDATE public.wallet_ledger
    SET deductible_balance = deductible_balance - v_deduct
    WHERE id = v_lot.id;

    v_remaining := v_remaining - v_deduct;
    EXIT WHEN v_remaining <= 0;
  END LOOP;

  IF v_remaining > 0 THEN
    RAISE EXCEPTION
      'Insufficient matching earn lots to allocate burn of % for user % merchant % currency %. Remaining: %',
      p_amount, p_user_id, p_merchant_id, p_currency, v_remaining;
  END IF;
END;
$function$;

COMMENT ON FUNCTION util.fn_allocate_fifo_burn(uuid, uuid, currency, uuid, integer) IS
  'Internal FIFO earn-lot allocator for chokepoint burns. SECURITY INVOKER; not a public writer.';

REVOKE ALL ON FUNCTION util.fn_allocate_fifo_burn(uuid, uuid, currency, uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION util.fn_allocate_fifo_burn(uuid, uuid, currency, uuid, integer) TO postgres, service_role;
GRANT USAGE ON SCHEMA util TO service_role;

-- 2. Chokepoint: allocate matching lots on non-expiry burns
CREATE OR REPLACE FUNCTION public.chokepoint_post_wallet_transaction(
  p_user_id uuid,
  p_currency currency,
  p_source_type wallet_transaction_source_type,
  p_component currency_component,
  p_transaction_type currency_transaction_type,
  p_amount integer,
  p_transaction_id uuid,
  p_merchant_id uuid,
  p_description text DEFAULT NULL::text,
  p_metadata jsonb DEFAULT '{}'::jsonb,
  p_target_entity_id uuid DEFAULT NULL::uuid,
  p_dedup_key text DEFAULT NULL::text
)
RETURNS uuid
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
    v_ledger_id uuid;
    v_first_ledger_id uuid;
    v_balance_before integer;
    v_balance_after integer;
    v_signed_amount integer;
    v_unit_signed integer;
    v_deductible_balance integer DEFAULT 0;
    v_expiry_date date;
    v_expiry_active boolean;
    v_expiry_mode text;
    v_is_pooled_type boolean;
    v_pool_available integer;
    v_unit_i integer;
    v_unit_balance_before integer;
    v_unit_balance_after integer;
    v_code text;
    v_unit_dedup text;
    v_assign_result jsonb;
    v_expiry_feature_enabled boolean;
BEGIN
    IF p_currency = 'ticket'::currency AND p_target_entity_id IS NULL THEN
        RAISE EXCEPTION 'target_entity_id is required for ticket transactions';
    END IF;

    IF p_currency = 'points'::currency AND p_target_entity_id IS NOT NULL THEN
        RAISE EXCEPTION 'target_entity_id must be NULL for points transactions';
    END IF;

    v_expiry_feature_enabled := public.fn_merchant_shopify_feature_enabled(
      p_merchant_id, 'currency', 'currency.expiry'
    );

    IF p_currency = 'ticket'::currency THEN
        IF p_amount IS NULL OR p_amount <= 0 THEN
            RAISE EXCEPTION 'Ticket transaction amount must be positive';
        END IF;

        v_unit_signed := CASE
            WHEN p_transaction_type = 'earn'::currency_transaction_type THEN 1
            WHEN p_transaction_type = 'burn'::currency_transaction_type THEN -1
            ELSE p_amount
        END;

        IF p_transaction_type = 'earn'::currency_transaction_type THEN
            SELECT
                expiry_mode,
                CASE
                    WHEN expiry_mode IS NULL OR expiry_mode = 'none' THEN NULL
                    WHEN expiry_mode = 'ttl' THEN CURRENT_DATE + (ttl_months || ' months')::INTERVAL
                    WHEN expiry_mode = 'fixed_frequency' THEN get_next_fiscal_period_end(CURRENT_DATE, frequency, fiscal_year_end_month, minimum_period_months)
                    WHEN expiry_mode = 'absolute_date' THEN absolute_expiry_date
                    ELSE NULL
                END
            INTO v_expiry_mode, v_expiry_date
            FROM ticket_type
            WHERE id = p_target_entity_id;
        ELSE
            v_expiry_date := NULL;
        END IF;

        INSERT INTO public.user_ticket_balances (user_id, merchant_id, ticket_type_id, balance)
        VALUES (p_user_id, p_merchant_id, p_target_entity_id, 0)
        ON CONFLICT (user_id, merchant_id, ticket_type_id) DO NOTHING;

        SELECT COALESCE(balance, 0)
        INTO v_balance_before
        FROM public.user_ticket_balances
        WHERE user_id = p_user_id
          AND merchant_id = p_merchant_id
          AND ticket_type_id = p_target_entity_id
        FOR UPDATE;

        v_balance_after := v_balance_before + (p_amount * v_unit_signed);

        IF v_balance_after < 0 THEN
            RAISE EXCEPTION 'Insufficient ticket balance for ticket type %. Current: %, Required: %',
                p_target_entity_id, v_balance_before, p_amount;
        END IF;

        IF p_transaction_type = 'burn'::currency_transaction_type
           AND p_source_type IS DISTINCT FROM 'expiry'::wallet_transaction_source_type
        THEN
            PERFORM util.fn_allocate_fifo_burn(
                p_user_id,
                p_merchant_id,
                p_currency,
                p_target_entity_id,
                p_amount
            );
        END IF;

        SELECT EXISTS (
            SELECT 1
            FROM ticket_code tc
            WHERE tc.merchant_id = p_merchant_id
              AND tc.ticket_type_id = p_target_entity_id
        )
        INTO v_is_pooled_type;

        IF v_is_pooled_type AND p_transaction_type = 'earn'::currency_transaction_type THEN
            SELECT COUNT(*)
            INTO v_pool_available
            FROM ticket_code tc
            WHERE tc.merchant_id = p_merchant_id
              AND tc.ticket_type_id = p_target_entity_id
              AND tc.assigned_status = false;

            IF v_pool_available < p_amount THEN
                RAISE EXCEPTION 'Insufficient ticket codes in pool for ticket type %. Available: %, Required: %',
                    p_target_entity_id, v_pool_available, p_amount;
            END IF;
        END IF;

        FOR v_unit_i IN 1..p_amount LOOP
            v_unit_balance_before := v_balance_before + ((v_unit_i - 1) * v_unit_signed);
            v_unit_balance_after := v_unit_balance_before + v_unit_signed;
            v_code := generate_random_wallet_ticket_code(p_merchant_id, p_transaction_type);
            v_unit_dedup := CASE
                WHEN p_dedup_key IS NULL THEN NULL
                WHEN p_amount = 1 THEN p_dedup_key
                ELSE p_dedup_key || ':u' || v_unit_i::text
            END;

            INSERT INTO public.wallet_ledger (
                user_id, merchant_id, currency, transaction_type, component, amount, signed_amount,
                balance_before, balance_after, deductible_balance, source_type, source_id,
                description, metadata, target_entity_id, expiry_date, created_by, dedup_key, code
            ) VALUES (
                p_user_id, p_merchant_id, p_currency, p_transaction_type, p_component, 1, v_unit_signed,
                v_unit_balance_before, v_unit_balance_after, 1, p_source_type, p_transaction_id,
                p_description, p_metadata, p_target_entity_id, v_expiry_date, p_user_id, v_unit_dedup, v_code
            )
            RETURNING id INTO v_ledger_id;

            v_first_ledger_id := COALESCE(v_first_ledger_id, v_ledger_id);

            IF v_is_pooled_type AND p_transaction_type = 'earn'::currency_transaction_type THEN
                v_assign_result := fn_assign_ticket_codes(
                    p_merchant_id,
                    p_target_entity_id,
                    p_user_id,
                    1,
                    v_ledger_id,
                    p_transaction_id
                );

                IF NOT COALESCE((v_assign_result->>'success')::boolean, false) THEN
                    RAISE EXCEPTION 'Failed to assign ticket pool code: %', COALESCE(v_assign_result->>'error', 'unknown error');
                END IF;
            END IF;

            IF COALESCE(p_metadata->>'_skip_emit', 'false') <> 'true' THEN
                PERFORM public.fn_chokepoint_emit_event(
                    'crm.events.wallet',
                    p_user_id::text,
                    jsonb_build_object(
                        'event', 'wallet_transaction',
                        'merchant_id', p_merchant_id,
                        'user_id', p_user_id,
                        'wallet_ledger_id', v_ledger_id,
                        'currency', p_currency::text,
                        'component', p_component::text,
                        'transaction_type', p_transaction_type::text,
                        'amount', 1,
                        'source_type', p_source_type::text,
                        'source_id', p_transaction_id,
                        'description', p_description,
                        'target_entity_id', p_target_entity_id,
                        'wallet_code', v_code,
                        'unit_index', v_unit_i,
                        'unit_total', p_amount,
                        'occurred_at', to_jsonb(now()),
                        'source', 'chokepoint_post_wallet_transaction'
                    )
                );
            END IF;
        END LOOP;

        UPDATE public.user_ticket_balances
        SET balance = v_balance_after,
            updated_at = now()
        WHERE user_id = p_user_id
          AND merchant_id = p_merchant_id
          AND ticket_type_id = p_target_entity_id;

        RETURN v_first_ledger_id;
    END IF;

    v_signed_amount := CASE
        WHEN p_transaction_type = 'earn'::currency_transaction_type THEN p_amount
        WHEN p_transaction_type = 'burn'::currency_transaction_type THEN -p_amount
        ELSE p_amount
    END;

    IF p_transaction_type = 'earn'::currency_transaction_type THEN
        SELECT
            points_expiry_active, points_expiry_mode,
            CASE
                WHEN NOT v_expiry_feature_enabled THEN NULL
                WHEN NOT points_expiry_active OR points_expiry_mode = 'none' OR points_expiry_mode IS NULL THEN NULL
                WHEN points_expiry_mode = 'ttl' THEN CURRENT_DATE + (points_ttl_months || ' months')::INTERVAL
                WHEN points_expiry_mode = 'fixed_frequency' THEN get_next_fiscal_period_end(CURRENT_DATE, points_frequency, points_fiscal_year_end_month, points_minimum_period_months)
                ELSE NULL
            END
        INTO v_expiry_active, v_expiry_mode, v_expiry_date
        FROM merchant_master
        WHERE id = p_merchant_id;
    END IF;

    INSERT INTO public.user_wallet (user_id, merchant_id, points_balance, ticket_balance)
    VALUES (p_user_id, p_merchant_id, 0, 0)
    ON CONFLICT (user_id, merchant_id) DO NOTHING;

    SELECT COALESCE(points_balance, 0)
    INTO v_balance_before
    FROM public.user_wallet
    WHERE user_id = p_user_id AND merchant_id = p_merchant_id
    FOR UPDATE;

    v_balance_after := v_balance_before + v_signed_amount;

    IF v_balance_after < 0 THEN
        RAISE EXCEPTION 'Insufficient points balance. Current: %, Required: %', v_balance_before, p_amount;
    END IF;

    IF p_transaction_type = 'burn'::currency_transaction_type
       AND p_source_type IS DISTINCT FROM 'expiry'::wallet_transaction_source_type
    THEN
        PERFORM util.fn_allocate_fifo_burn(
            p_user_id,
            p_merchant_id,
            p_currency,
            p_target_entity_id,
            p_amount
        );
    END IF;

    UPDATE public.user_wallet
    SET points_balance = v_balance_after
    WHERE user_id = p_user_id AND merchant_id = p_merchant_id;

    v_deductible_balance := CASE
        WHEN p_transaction_type = 'burn'::currency_transaction_type THEN p_amount
        WHEN p_transaction_type = 'earn'::currency_transaction_type THEN p_amount
        ELSE 0
    END;

    INSERT INTO public.wallet_ledger (
        user_id, merchant_id, currency, transaction_type, component, amount, signed_amount,
        balance_before, balance_after, deductible_balance, source_type, source_id,
        description, metadata, target_entity_id, expiry_date, created_by, dedup_key
    ) VALUES (
        p_user_id, p_merchant_id, p_currency, p_transaction_type, p_component, p_amount, v_signed_amount,
        v_balance_before, v_balance_after, v_deductible_balance, p_source_type, p_transaction_id,
        p_description, p_metadata, p_target_entity_id, v_expiry_date, p_user_id, p_dedup_key
    )
    RETURNING id INTO v_ledger_id;

    IF COALESCE(p_metadata->>'_skip_emit', 'false') <> 'true' THEN
        PERFORM public.fn_chokepoint_emit_event(
            'crm.events.wallet',
            p_user_id::text,
            jsonb_build_object(
                'event', 'wallet_transaction',
                'merchant_id', p_merchant_id,
                'user_id', p_user_id,
                'wallet_ledger_id', v_ledger_id,
                'currency', p_currency::text,
                'component', p_component::text,
                'transaction_type', p_transaction_type::text,
                'amount', p_amount,
                'source_type', p_source_type::text,
                'source_id', p_transaction_id,
                'description', p_description,
                'target_entity_id', p_target_entity_id,
                'occurred_at', to_jsonb(now()),
                'source', 'chokepoint_post_wallet_transaction'
            )
        );
    END IF;

    RETURN v_ledger_id;
END;
$function$;

-- 3. Expiry: remaining deductible, zero lots, post once after all batches
CREATE OR REPLACE FUNCTION public.should_run_expiry_today(p_date date DEFAULT CURRENT_DATE)
RETURNS boolean
LANGUAGE plpgsql
AS $function$
DECLARE
    v_month INTEGER;
    v_is_month_end BOOLEAN;
BEGIN
    IF EXISTS (
        SELECT 1 FROM wallet_ledger
        WHERE transaction_type = 'earn'::currency_transaction_type
          AND expiry_date = p_date
          AND expiry_processed_at IS NULL
          AND COALESCE(deductible_balance, 0) > 0
        LIMIT 1
    ) THEN
        RETURN true;
    END IF;

    v_month := EXTRACT(MONTH FROM p_date);
    v_is_month_end := (EXTRACT(DAY FROM p_date + INTERVAL '1 day') = 1);

    IF v_is_month_end THEN
        IF EXISTS (
            SELECT 1 FROM merchant_master
            WHERE points_expiry_mode = 'fixed_frequency'
              AND points_frequency = 'monthly'
              AND points_expiry_active = true
            LIMIT 1
        ) OR EXISTS (
            SELECT 1 FROM ticket_type
            WHERE expiry_mode = 'fixed_frequency'
              AND frequency = 'monthly'
              AND active = true
            LIMIT 1
        ) THEN
            RETURN true;
        END IF;

        IF EXISTS (
            SELECT 1 FROM merchant_master
            WHERE points_expiry_mode = 'fixed_frequency'
              AND points_frequency = 'quarterly'
              AND points_expiry_active = true
              AND ((v_month - points_fiscal_year_end_month + 12) % 3) = 0
            LIMIT 1
        ) OR EXISTS (
            SELECT 1 FROM ticket_type
            WHERE expiry_mode = 'fixed_frequency'
              AND frequency = 'quarterly'
              AND active = true
              AND ((v_month - fiscal_year_end_month + 12) % 3) = 0
            LIMIT 1
        ) THEN
            RETURN true;
        END IF;

        IF EXISTS (
            SELECT 1 FROM merchant_master
            WHERE points_expiry_mode = 'fixed_frequency'
              AND points_frequency = 'semi_annual'
              AND points_expiry_active = true
              AND (points_fiscal_year_end_month = v_month
                   OR ((points_fiscal_year_end_month + 6 - 1) % 12) + 1 = v_month)
            LIMIT 1
        ) OR EXISTS (
            SELECT 1 FROM ticket_type
            WHERE expiry_mode = 'fixed_frequency'
              AND frequency = 'semi_annual'
              AND active = true
              AND (fiscal_year_end_month = v_month
                   OR ((fiscal_year_end_month + 6 - 1) % 12) + 1 = v_month)
            LIMIT 1
        ) THEN
            RETURN true;
        END IF;

        IF EXISTS (
            SELECT 1 FROM merchant_master
            WHERE points_expiry_mode = 'fixed_frequency'
              AND points_frequency = 'annual'
              AND points_fiscal_year_end_month = v_month
              AND points_expiry_active = true
            LIMIT 1
        ) OR EXISTS (
            SELECT 1 FROM ticket_type
            WHERE expiry_mode = 'fixed_frequency'
              AND frequency = 'annual'
              AND fiscal_year_end_month = v_month
              AND active = true
            LIMIT 1
        ) THEN
            RETURN true;
        END IF;
    END IF;

    RETURN false;
END;
$function$;

CREATE OR REPLACE FUNCTION public.process_currency_expiry(
  p_date date DEFAULT CURRENT_DATE,
  p_batch_size integer DEFAULT 1000
)
RETURNS TABLE(currency_type currency, users_affected integer, amount_expired integer)
LANGUAGE plpgsql
AS $function$
DECLARE
    v_batch_count INTEGER;
    v_total_processed INTEGER := 0;
    v_batch_ids UUID[];
    v_user_rec RECORD;
BEGIN
    CREATE TEMP TABLE IF NOT EXISTS _expiry_deductions (
        ledger_id UUID,
        user_id UUID,
        merchant_id UUID,
        currency currency,
        target_entity_id UUID,
        deduct_amount NUMERIC
    ) ON COMMIT DROP;
    TRUNCATE _expiry_deductions;

    LOOP
        SELECT ARRAY_AGG(id) INTO v_batch_ids
        FROM (
            SELECT id
            FROM wallet_ledger
            WHERE transaction_type = 'earn'::currency_transaction_type
              AND expiry_date = p_date
              AND expiry_processed_at IS NULL
              AND COALESCE(deductible_balance, 0) > 0
            LIMIT p_batch_size
            FOR UPDATE SKIP LOCKED
        ) t;

        IF v_batch_ids IS NULL OR array_length(v_batch_ids, 1) IS NULL THEN
            EXIT;
        END IF;

        INSERT INTO _expiry_deductions (ledger_id, user_id, merchant_id, currency, target_entity_id, deduct_amount)
        SELECT id, user_id, merchant_id, currency, target_entity_id,
               deductible_balance
        FROM wallet_ledger
        WHERE id = ANY(v_batch_ids)
          AND COALESCE(deductible_balance, 0) > 0;

        UPDATE wallet_ledger
        SET expired_amount = COALESCE(expired_amount, 0) + COALESCE(deductible_balance, 0),
            deductible_balance = 0,
            expiry_processed_at = NOW()
        WHERE id = ANY(v_batch_ids);

        GET DIAGNOSTICS v_batch_count = ROW_COUNT;
        v_total_processed := v_total_processed + v_batch_count;
    END LOOP;

    FOR v_user_rec IN
        SELECT ed.user_id, ed.merchant_id, SUM(ed.deduct_amount)::integer AS expire_amount
        FROM _expiry_deductions ed
        WHERE ed.currency = 'points'
        GROUP BY ed.user_id, ed.merchant_id
        HAVING SUM(ed.deduct_amount) > 0
    LOOP
        PERFORM chokepoint_post_wallet_transaction(
            p_user_id := v_user_rec.user_id,
            p_currency := 'points'::currency,
            p_source_type := 'expiry'::wallet_transaction_source_type,
            p_component := 'adjustment'::currency_component,
            p_transaction_type := 'burn'::currency_transaction_type,
            p_amount := v_user_rec.expire_amount,
            p_transaction_id := gen_random_uuid(),
            p_merchant_id := v_user_rec.merchant_id,
            p_description := 'Currency expiry for ' || p_date::text,
            p_dedup_key := 'expiry_' || v_user_rec.user_id::text || '_' || p_date::text
        );
    END LOOP;

    FOR v_user_rec IN
        SELECT ed.user_id, ed.merchant_id, ed.target_entity_id,
               SUM(ed.deduct_amount)::integer AS expire_amount
        FROM _expiry_deductions ed
        WHERE ed.currency = 'ticket'
        GROUP BY ed.user_id, ed.merchant_id, ed.target_entity_id
        HAVING SUM(ed.deduct_amount) > 0
    LOOP
        PERFORM chokepoint_post_wallet_transaction(
            p_user_id := v_user_rec.user_id,
            p_currency := 'ticket'::currency,
            p_source_type := 'expiry'::wallet_transaction_source_type,
            p_component := 'adjustment'::currency_component,
            p_transaction_type := 'burn'::currency_transaction_type,
            p_amount := v_user_rec.expire_amount,
            p_transaction_id := gen_random_uuid(),
            p_merchant_id := v_user_rec.merchant_id,
            p_description := 'Ticket expiry for ' || p_date::text,
            p_dedup_key := 'expiry_ticket_' || v_user_rec.user_id::text || '_' || COALESCE(v_user_rec.target_entity_id::text, '') || '_' || p_date::text,
            p_target_entity_id := v_user_rec.target_entity_id
        );
    END LOOP;

    RETURN QUERY
    SELECT
        ed.currency,
        COUNT(DISTINCT ed.user_id)::INTEGER,
        SUM(ed.deduct_amount)::INTEGER
    FROM _expiry_deductions ed
    GROUP BY ed.currency;
END;
$function$;

CREATE OR REPLACE FUNCTION public.process_expiry_if_needed()
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_run_date DATE;
    v_should_run BOOLEAN;
    v_result RECORD;
BEGIN
    -- Business timezone is not confirmed yet. Database timezone is UTC.
    -- Do not switch to Asia/Bangkok until product/operations confirms.
    v_run_date := CURRENT_DATE;

    v_should_run := should_run_expiry_today(v_run_date);

    IF NOT v_should_run THEN
        INSERT INTO expiry_processing_log (run_date, completed_at, users_affected, amount_expired)
        VALUES (v_run_date, NOW(), 0, 0);
        RETURN;
    END IF;

    BEGIN
        FOR v_result IN
            SELECT * FROM process_currency_expiry(v_run_date, 1000)
        LOOP
            INSERT INTO expiry_processing_log (
                run_date,
                currency_type,
                users_affected,
                amount_expired,
                completed_at
            ) VALUES (
                v_run_date,
                v_result.currency_type,
                v_result.users_affected,
                v_result.amount_expired,
                NOW()
            );
        END LOOP;

        IF NOT FOUND THEN
            INSERT INTO expiry_processing_log (run_date, completed_at, users_affected, amount_expired)
            VALUES (v_run_date, NOW(), 0, 0);
        END IF;

    EXCEPTION WHEN OTHERS THEN
        INSERT INTO expiry_processing_log (run_date, error_message)
        VALUES (v_run_date, SQLERRM);
        RAISE;
    END;
END;
$function$;

-- 4. Drop trigger business logic atomically with the chokepoint replacement
DROP TRIGGER IF EXISTS trg_fifo_burn_tracking ON public.wallet_ledger;
DROP FUNCTION IF EXISTS public.fn_apply_fifo_burn();

-- 5. Restrict expiry helpers; keep chokepoint grants unchanged
REVOKE ALL ON FUNCTION public.should_run_expiry_today(date) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.process_currency_expiry(date, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.process_expiry_if_needed() FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.should_run_expiry_today(date) TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.process_currency_expiry(date, integer) TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.process_expiry_if_needed() TO postgres, service_role;
