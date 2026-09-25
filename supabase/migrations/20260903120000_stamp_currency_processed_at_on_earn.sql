-- Stamp purchase / purchase_item currency_processed_at when earn rows land in wallet_ledger.
-- The Inngest currency/award path calls chokepoint_post_wallet_transaction; this was the
-- missing close-out step after wallet earn writes.

CREATE OR REPLACE FUNCTION public.fn_stamp_currency_processed_for_earn(
  p_source_type wallet_transaction_source_type,
  p_source_id uuid,
  p_merchant_id uuid,
  p_processed_at timestamptz DEFAULT clock_timestamp()
)
RETURNS void
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
BEGIN
  IF p_source_id IS NULL OR p_merchant_id IS NULL THEN
    RETURN;
  END IF;

  IF p_source_type = 'purchase'::wallet_transaction_source_type THEN
    UPDATE public.purchase_ledger
    SET currency_processed_at = p_processed_at,
        currency_error = NULL,
        updated_at = now()
    WHERE id = p_source_id
      AND merchant_id = p_merchant_id
      AND currency_processed_at IS NULL;
    RETURN;
  END IF;

  IF p_source_type = 'purchase_item'::wallet_transaction_source_type THEN
    UPDATE public.purchase_items_ledger
    SET currency_processed_at = p_processed_at,
        currency_error = NULL,
        updated_at = now()
    WHERE id = p_source_id
      AND merchant_id = p_merchant_id
      AND currency_processed_at IS NULL;
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_stamp_currency_processed_for_earn(
  wallet_transaction_source_type, uuid, uuid, timestamptz
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_stamp_currency_processed_for_earn(
  wallet_transaction_source_type, uuid, uuid, timestamptz
) TO postgres, service_role;

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
    v_metadata jsonb;
    v_lots_before integer;
    v_lots_after integer;
    v_shortfall_before integer;
    v_unallocated integer;
    v_shortfall_after integer;
    v_skip_emit boolean;
    v_repair_run_id text;
    v_effective_text text;
    v_ledger_created_at timestamptz;
BEGIN
    IF p_currency = 'ticket'::currency AND p_target_entity_id IS NULL THEN
        RAISE EXCEPTION 'target_entity_id is required for ticket transactions';
    END IF;

    IF p_currency = 'points'::currency AND p_target_entity_id IS NOT NULL THEN
        RAISE EXCEPTION 'target_entity_id must be NULL for points transactions';
    END IF;

    v_metadata := COALESCE(p_metadata, '{}'::jsonb);
    v_skip_emit := COALESCE(v_metadata->>'_skip_emit', 'false') = 'true';
    v_repair_run_id := NULLIF(btrim(COALESCE(v_metadata->>'_repair_run_id', '')), '');
    v_effective_text := NULLIF(btrim(COALESCE(v_metadata->>'_effective_created_at', '')), '');
    v_ledger_created_at := clock_timestamp();

    IF v_repair_run_id IS NOT NULL AND NOT v_skip_emit THEN
        RAISE EXCEPTION 'repair run requires metadata._skip_emit=true';
    END IF;

    IF v_effective_text IS NOT NULL THEN
        IF p_source_type IS DISTINCT FROM 'expiry'::wallet_transaction_source_type THEN
            RAISE EXCEPTION '_effective_created_at is allowed only for expiry repairs';
        END IF;
        IF NOT v_skip_emit THEN
            RAISE EXCEPTION '_effective_created_at requires metadata._skip_emit=true';
        END IF;
        IF v_repair_run_id IS NULL THEN
            RAISE EXCEPTION '_effective_created_at requires metadata._repair_run_id';
        END IF;
        BEGIN
            v_ledger_created_at := v_effective_text::timestamptz;
        EXCEPTION WHEN OTHERS THEN
            RAISE EXCEPTION 'invalid _effective_created_at: %', v_effective_text;
        END;
        IF v_ledger_created_at > clock_timestamp() THEN
            RAISE EXCEPTION '_effective_created_at cannot be in the future';
        END IF;
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
            v_lots_before := util.fn_allocatable_lot_balance(
                p_user_id, p_merchant_id, p_currency, p_target_entity_id
            );
            v_shortfall_before := GREATEST(v_balance_before - v_lots_before, 0);
            v_unallocated := util.fn_allocate_fifo_burn(
                p_user_id,
                p_merchant_id,
                p_currency,
                p_target_entity_id,
                p_amount
            );
            IF v_unallocated > v_shortfall_before THEN
                RAISE EXCEPTION
                    'Insufficient matching earn lots to allocate burn of % for user % merchant % currency %. Unallocated: %, pre-existing shortfall: %',
                    p_amount, p_user_id, p_merchant_id, p_currency, v_unallocated, v_shortfall_before;
            END IF;
            v_lots_after := v_lots_before - (p_amount - v_unallocated);
            v_shortfall_after := GREATEST((v_balance_before - p_amount) - v_lots_after, 0);
            IF v_shortfall_after > v_shortfall_before THEN
                RAISE EXCEPTION
                    'FIFO allocation would increase wallet-lot shortfall for user % merchant % currency % from % to %',
                    p_user_id, p_merchant_id, p_currency, v_shortfall_before, v_shortfall_after;
            END IF;
            IF v_unallocated > 0 THEN
                PERFORM util.fn_upsert_wallet_reconciliation_issue(
                    'burn_unallocated_shortfall',
                    p_merchant_id,
                    p_user_id,
                    p_currency,
                    p_target_entity_id,
                    NULL,
                    v_balance_before,
                    v_lots_before,
                    v_unallocated,
                    jsonb_build_object('burn_amount', p_amount)
                );
                v_metadata := v_metadata || jsonb_build_object(
                    'unallocated_fifo_amount', v_unallocated,
                    'allocatable_lots_before', v_lots_before,
                    'fifo_shortfall_before', v_shortfall_before
                );
            END IF;
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
                description, metadata, target_entity_id, expiry_date, created_by, dedup_key, code,
                created_at
            ) VALUES (
                p_user_id, p_merchant_id, p_currency, p_transaction_type, p_component, 1, v_unit_signed,
                v_unit_balance_before, v_unit_balance_after, 1, p_source_type, p_transaction_id,
                p_description, v_metadata, p_target_entity_id, v_expiry_date, p_user_id, v_unit_dedup, v_code,
                v_ledger_created_at
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

            IF NOT v_skip_emit THEN
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

        IF p_transaction_type = 'earn'::currency_transaction_type THEN
            PERFORM public.fn_stamp_currency_processed_for_earn(
                p_source_type,
                p_transaction_id,
                p_merchant_id,
                v_ledger_created_at
            );
        END IF;

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
        v_lots_before := util.fn_allocatable_lot_balance(
            p_user_id, p_merchant_id, p_currency, p_target_entity_id
        );
        v_shortfall_before := GREATEST(v_balance_before - v_lots_before, 0);
        v_unallocated := util.fn_allocate_fifo_burn(
            p_user_id,
            p_merchant_id,
            p_currency,
            p_target_entity_id,
            p_amount
        );
        IF v_unallocated > v_shortfall_before THEN
            RAISE EXCEPTION
                'Insufficient matching earn lots to allocate burn of % for user % merchant % currency %. Unallocated: %, pre-existing shortfall: %',
                p_amount, p_user_id, p_merchant_id, p_currency, v_unallocated, v_shortfall_before;
        END IF;
        v_lots_after := v_lots_before - (p_amount - v_unallocated);
        v_shortfall_after := GREATEST((v_balance_before - p_amount) - v_lots_after, 0);
        IF v_shortfall_after > v_shortfall_before THEN
            RAISE EXCEPTION
                'FIFO allocation would increase wallet-lot shortfall for user % merchant % currency % from % to %',
                p_user_id, p_merchant_id, p_currency, v_shortfall_before, v_shortfall_after;
        END IF;
        IF v_unallocated > 0 THEN
            PERFORM util.fn_upsert_wallet_reconciliation_issue(
                'burn_unallocated_shortfall',
                p_merchant_id,
                p_user_id,
                p_currency,
                p_target_entity_id,
                NULL,
                v_balance_before,
                v_lots_before,
                v_unallocated,
                jsonb_build_object('burn_amount', p_amount)
            );
            v_metadata := v_metadata || jsonb_build_object(
                'unallocated_fifo_amount', v_unallocated,
                'allocatable_lots_before', v_lots_before,
                'fifo_shortfall_before', v_shortfall_before
            );
        END IF;
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
        description, metadata, target_entity_id, expiry_date, created_by, dedup_key,
        created_at
    ) VALUES (
        p_user_id, p_merchant_id, p_currency, p_transaction_type, p_component, p_amount, v_signed_amount,
        v_balance_before, v_balance_after, v_deductible_balance, p_source_type, p_transaction_id,
        p_description, v_metadata, p_target_entity_id, v_expiry_date, p_user_id, p_dedup_key,
        v_ledger_created_at
    )
    RETURNING id INTO v_ledger_id;

    IF NOT v_skip_emit THEN
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

    IF p_transaction_type = 'earn'::currency_transaction_type THEN
        PERFORM public.fn_stamp_currency_processed_for_earn(
            p_source_type,
            p_transaction_id,
            p_merchant_id,
            v_ledger_created_at
        );
    END IF;

    RETURN v_ledger_id;
END;
$function$;

-- Backfill purchases that already earned but never got stamped (chokepoint gap).
UPDATE public.purchase_ledger pl
SET currency_processed_at = sub.first_earn_at,
    updated_at = now()
FROM (
  SELECT wl.source_id AS purchase_id, MIN(wl.created_at) AS first_earn_at
  FROM public.wallet_ledger wl
  WHERE wl.source_type = 'purchase'::wallet_transaction_source_type
    AND wl.transaction_type = 'earn'::currency_transaction_type
  GROUP BY wl.source_id
) sub
WHERE pl.id = sub.purchase_id
  AND pl.earn_currency = true
  AND pl.status = 'completed'::purchase_status
  AND pl.currency_processed_at IS NULL;

UPDATE public.purchase_items_ledger pil
SET currency_processed_at = sub.first_earn_at,
    updated_at = now()
FROM (
  SELECT wl.source_id AS item_id, MIN(wl.created_at) AS first_earn_at
  FROM public.wallet_ledger wl
  WHERE wl.source_type = 'purchase_item'::wallet_transaction_source_type
    AND wl.transaction_type = 'earn'::currency_transaction_type
  GROUP BY wl.source_id
) sub
WHERE pil.id = sub.item_id
  AND pil.currency_processed_at IS NULL;
