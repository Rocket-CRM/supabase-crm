-- Wallet drift expiry: bounded batches, mismatch isolation, transitional FIFO.

-- 1. Reconciliation issue table
CREATE TABLE IF NOT EXISTS public.wallet_reconciliation_issue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  issue_type text NOT NULL
    CHECK (issue_type IN ('expiry_lots_exceed_wallet', 'burn_unallocated_shortfall')),
  merchant_id uuid NOT NULL REFERENCES public.merchant_master(id),
  user_id uuid NOT NULL,
  currency public.currency NOT NULL,
  target_entity_id uuid,
  expiry_date date,
  wallet_balance integer NOT NULL,
  lot_amount integer NOT NULL,
  difference integer NOT NULL,
  first_seen_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb
);

COMMENT ON TABLE public.wallet_reconciliation_issue IS
  'Exception log for wallet/lot mismatches. Not a job queue and not a wallet writer.';

CREATE UNIQUE INDEX IF NOT EXISTS wallet_reconciliation_issue_open_uniq
  ON public.wallet_reconciliation_issue (
    issue_type,
    user_id,
    merchant_id,
    currency,
    (COALESCE(target_entity_id, '00000000-0000-0000-0000-000000000000'::uuid)),
    (COALESCE(expiry_date, DATE '0001-01-01'))
  )
  WHERE resolved_at IS NULL;

CREATE INDEX IF NOT EXISTS wallet_reconciliation_issue_open_merchant_idx
  ON public.wallet_reconciliation_issue (merchant_id, last_seen_at DESC)
  WHERE resolved_at IS NULL;

ALTER TABLE public.wallet_reconciliation_issue ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.wallet_reconciliation_issue FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.wallet_reconciliation_issue TO postgres, service_role;

ALTER TABLE public.expiry_processing_log
  ADD COLUMN IF NOT EXISTS skipped_users integer,
  ADD COLUMN IF NOT EXISTS details jsonb NOT NULL DEFAULT '{}'::jsonb;

CREATE INDEX IF NOT EXISTS idx_wallet_ledger_expiry_unprocessed
  ON public.wallet_ledger (expiry_date, currency, user_id, merchant_id)
  WHERE transaction_type = 'earn'::currency_transaction_type
    AND expiry_processed_at IS NULL
    AND deductible_balance > 0;

-- 2. Internal helpers
CREATE OR REPLACE FUNCTION util.fn_allocatable_lot_balance(
  p_user_id uuid,
  p_merchant_id uuid,
  p_currency currency,
  p_target_entity_id uuid
)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'public'
AS $function$
  SELECT COALESCE(SUM(deductible_balance), 0)::integer
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
    );
$function$;

COMMENT ON FUNCTION util.fn_allocatable_lot_balance(uuid, uuid, currency, uuid) IS
  'Sum of live unprocessed earn lots available for FIFO allocation.';

CREATE OR REPLACE FUNCTION util.fn_upsert_wallet_reconciliation_issue(
  p_issue_type text,
  p_merchant_id uuid,
  p_user_id uuid,
  p_currency currency,
  p_target_entity_id uuid,
  p_expiry_date date,
  p_wallet_balance integer,
  p_lot_amount integer,
  p_difference integer,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO public.wallet_reconciliation_issue (
    issue_type, merchant_id, user_id, currency, target_entity_id, expiry_date,
    wallet_balance, lot_amount, difference, metadata
  ) VALUES (
    p_issue_type, p_merchant_id, p_user_id, p_currency, p_target_entity_id, p_expiry_date,
    p_wallet_balance, p_lot_amount, p_difference, COALESCE(p_metadata, '{}'::jsonb)
  )
  ON CONFLICT (
    issue_type,
    user_id,
    merchant_id,
    currency,
    (COALESCE(target_entity_id, '00000000-0000-0000-0000-000000000000'::uuid)),
    (COALESCE(expiry_date, DATE '0001-01-01'))
  ) WHERE resolved_at IS NULL
  DO UPDATE SET
    last_seen_at = now(),
    wallet_balance = EXCLUDED.wallet_balance,
    lot_amount = EXCLUDED.lot_amount,
    difference = EXCLUDED.difference,
    metadata = COALESCE(public.wallet_reconciliation_issue.metadata, '{}'::jsonb)
               || COALESCE(EXCLUDED.metadata, '{}'::jsonb);
END;
$function$;

DROP FUNCTION IF EXISTS util.fn_allocate_fifo_burn(uuid, uuid, currency, uuid, integer);

CREATE FUNCTION util.fn_allocate_fifo_burn(
  p_user_id uuid,
  p_merchant_id uuid,
  p_currency currency,
  p_target_entity_id uuid,
  p_amount integer
)
RETURNS integer
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

  RETURN v_remaining;
END;
$function$;

COMMENT ON FUNCTION util.fn_allocate_fifo_burn(uuid, uuid, currency, uuid, integer) IS
  'Internal FIFO earn-lot allocator. Returns the unallocated remainder. Not a public writer.';

REVOKE ALL ON FUNCTION util.fn_allocatable_lot_balance(uuid, uuid, currency, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION util.fn_upsert_wallet_reconciliation_issue(text, uuid, uuid, currency, uuid, date, integer, integer, integer, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION util.fn_allocate_fifo_burn(uuid, uuid, currency, uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION util.fn_allocatable_lot_balance(uuid, uuid, currency, uuid) TO postgres, service_role;
GRANT EXECUTE ON FUNCTION util.fn_upsert_wallet_reconciliation_issue(text, uuid, uuid, currency, uuid, date, integer, integer, integer, jsonb) TO postgres, service_role;
GRANT EXECUTE ON FUNCTION util.fn_allocate_fifo_burn(uuid, uuid, currency, uuid, integer) TO postgres, service_role;

-- 3. Chokepoint with non-increasing shortfall handling
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
BEGIN
    IF p_currency = 'ticket'::currency AND p_target_entity_id IS NULL THEN
        RAISE EXCEPTION 'target_entity_id is required for ticket transactions';
    END IF;

    IF p_currency = 'points'::currency AND p_target_entity_id IS NOT NULL THEN
        RAISE EXCEPTION 'target_entity_id must be NULL for points transactions';
    END IF;

    v_metadata := COALESCE(p_metadata, '{}'::jsonb);

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
                description, metadata, target_entity_id, expiry_date, created_by, dedup_key, code
            ) VALUES (
                p_user_id, p_merchant_id, p_currency, p_transaction_type, p_component, 1, v_unit_signed,
                v_unit_balance_before, v_unit_balance_after, 1, p_source_type, p_transaction_id,
                p_description, v_metadata, p_target_entity_id, v_expiry_date, p_user_id, v_unit_dedup, v_code
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
        description, metadata, target_entity_id, expiry_date, created_by, dedup_key
    ) VALUES (
        p_user_id, p_merchant_id, p_currency, p_transaction_type, p_component, p_amount, v_signed_amount,
        v_balance_before, v_balance_after, v_deductible_balance, p_source_type, p_transaction_id,
        p_description, v_metadata, p_target_entity_id, v_expiry_date, p_user_id, p_dedup_key
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

-- 4. Expiry date checker uses the cutover window and skips open mismatches
DROP FUNCTION IF EXISTS public.should_run_expiry_today(date);

CREATE FUNCTION public.should_run_expiry_today(
  p_date date DEFAULT CURRENT_DATE,
  p_cutover_date date DEFAULT DATE '2026-08-31'
)
RETURNS boolean
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
    v_month INTEGER;
    v_is_month_end BOOLEAN;
BEGIN
    IF EXISTS (
        SELECT 1
        FROM wallet_ledger wl
        WHERE wl.transaction_type = 'earn'::currency_transaction_type
          AND wl.expiry_date >= p_cutover_date
          AND wl.expiry_date <= p_date
          AND wl.expiry_processed_at IS NULL
          AND COALESCE(wl.deductible_balance, 0) > 0
          AND NOT EXISTS (
            SELECT 1
            FROM wallet_reconciliation_issue i
            WHERE i.resolved_at IS NULL
              AND i.issue_type = 'expiry_lots_exceed_wallet'
              AND i.user_id = wl.user_id
              AND i.merchant_id = wl.merchant_id
              AND i.currency = wl.currency
              AND i.target_entity_id IS NOT DISTINCT FROM wl.target_entity_id
              AND i.expiry_date = wl.expiry_date
          )
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

-- 5. One bounded batch transaction
CREATE OR REPLACE FUNCTION public.process_currency_expiry_batch(
  p_run_date date,
  p_cutover_date date,
  p_batch_size integer DEFAULT 1000,
  p_run_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  v_run_id text;
  v_expiry_date date;
  v_locked integer := 0;
  v_remaining integer;
  v_skipped integer := 0;
  v_valid integer := 0;
  v_amount_expired integer := 0;
  v_users integer := 0;
  v_has_more boolean := false;
  v_user_rec record;
BEGIN
  IF p_run_date IS NULL OR p_cutover_date IS NULL THEN
    RAISE EXCEPTION 'p_run_date and p_cutover_date are required';
  END IF;
  IF p_cutover_date > p_run_date THEN
    RAISE EXCEPTION 'p_cutover_date % is after p_run_date %', p_cutover_date, p_run_date;
  END IF;
  IF p_batch_size IS NULL OR p_batch_size < 1 THEN
    RAISE EXCEPTION 'p_batch_size must be a positive integer';
  END IF;

  v_run_id := COALESCE(NULLIF(btrim(p_run_id), ''), gen_random_uuid()::text);

  CREATE TEMP TABLE IF NOT EXISTS _expiry_due_points (
    user_id uuid NOT NULL,
    merchant_id uuid NOT NULL,
    due_amount integer NOT NULL
  ) ON COMMIT DROP;
  CREATE TEMP TABLE IF NOT EXISTS _expiry_due_tickets (
    user_id uuid NOT NULL,
    merchant_id uuid NOT NULL,
    target_entity_id uuid NOT NULL,
    due_amount integer NOT NULL
  ) ON COMMIT DROP;
  CREATE TEMP TABLE IF NOT EXISTS _expiry_batch_groups (
    user_id uuid NOT NULL,
    merchant_id uuid NOT NULL,
    currency currency NOT NULL,
    target_entity_id uuid,
    wallet_balance integer NOT NULL,
    due_amount integer NOT NULL,
    is_valid boolean NOT NULL
  ) ON COMMIT DROP;
  CREATE TEMP TABLE IF NOT EXISTS _expiry_deductions (
    ledger_id uuid,
    user_id uuid,
    merchant_id uuid,
    currency currency,
    target_entity_id uuid,
    deduct_amount integer
  ) ON COMMIT DROP;

  TRUNCATE _expiry_due_points;
  TRUNCATE _expiry_due_tickets;
  TRUNCATE _expiry_batch_groups;
  TRUNCATE _expiry_deductions;

  SELECT MIN(wl.expiry_date) INTO v_expiry_date
  FROM wallet_ledger wl
  WHERE wl.transaction_type = 'earn'::currency_transaction_type
    AND wl.expiry_date >= p_cutover_date
    AND wl.expiry_date <= p_run_date
    AND wl.expiry_processed_at IS NULL
    AND COALESCE(wl.deductible_balance, 0) > 0
    AND NOT EXISTS (
      SELECT 1
      FROM wallet_reconciliation_issue i
      WHERE i.resolved_at IS NULL
        AND i.issue_type = 'expiry_lots_exceed_wallet'
        AND i.user_id = wl.user_id
        AND i.merchant_id = wl.merchant_id
        AND i.currency = wl.currency
        AND i.target_entity_id IS NOT DISTINCT FROM wl.target_entity_id
        AND i.expiry_date = wl.expiry_date
    );

  IF v_expiry_date IS NULL THEN
    INSERT INTO expiry_processing_log (
      run_date, completed_at, users_affected, amount_expired, skipped_users, details
    ) VALUES (
      p_run_date, now(), 0, 0, 0,
      jsonb_build_object('run_id', v_run_id, 'has_more', false, 'reason', 'no_due_lots')
    );
    RETURN jsonb_build_object(
      'has_more', false,
      'expiry_date', NULL,
      'groups_processed', 0,
      'groups_skipped', 0,
      'users_affected', 0,
      'amount_expired', 0,
      'run_id', v_run_id
    );
  END IF;

  INSERT INTO _expiry_due_points (user_id, merchant_id, due_amount)
  SELECT wl.user_id, wl.merchant_id, SUM(wl.deductible_balance)::integer
  FROM wallet_ledger wl
  WHERE wl.transaction_type = 'earn'::currency_transaction_type
    AND wl.currency = 'points'::currency
    AND wl.expiry_date = v_expiry_date
    AND wl.expiry_processed_at IS NULL
    AND COALESCE(wl.deductible_balance, 0) > 0
    AND NOT EXISTS (
      SELECT 1
      FROM wallet_reconciliation_issue i
      WHERE i.resolved_at IS NULL
        AND i.issue_type = 'expiry_lots_exceed_wallet'
        AND i.user_id = wl.user_id
        AND i.merchant_id = wl.merchant_id
        AND i.currency = wl.currency
        AND i.target_entity_id IS NOT DISTINCT FROM wl.target_entity_id
        AND i.expiry_date = wl.expiry_date
    )
  GROUP BY wl.user_id, wl.merchant_id;

  INSERT INTO public.user_wallet (user_id, merchant_id, points_balance, ticket_balance)
  SELECT d.user_id, d.merchant_id, 0, 0
  FROM _expiry_due_points d
  ON CONFLICT (user_id, merchant_id) DO NOTHING;

  INSERT INTO _expiry_batch_groups (
    user_id, merchant_id, currency, target_entity_id, wallet_balance, due_amount, is_valid
  )
  SELECT d.user_id, d.merchant_id, 'points'::currency, NULL,
         uw.points_balance, d.due_amount,
         (d.due_amount <= uw.points_balance)
  FROM _expiry_due_points d
  JOIN public.user_wallet uw
    ON uw.user_id = d.user_id AND uw.merchant_id = d.merchant_id
  ORDER BY d.user_id, d.merchant_id
  LIMIT p_batch_size
  FOR UPDATE OF uw SKIP LOCKED;

  GET DIAGNOSTICS v_locked = ROW_COUNT;
  v_remaining := p_batch_size - v_locked;

  IF v_remaining > 0 THEN
    INSERT INTO _expiry_due_tickets (user_id, merchant_id, target_entity_id, due_amount)
    SELECT wl.user_id, wl.merchant_id, wl.target_entity_id, SUM(wl.deductible_balance)::integer
    FROM wallet_ledger wl
    WHERE wl.transaction_type = 'earn'::currency_transaction_type
      AND wl.currency = 'ticket'::currency
      AND wl.expiry_date = v_expiry_date
      AND wl.expiry_processed_at IS NULL
      AND COALESCE(wl.deductible_balance, 0) > 0
      AND wl.target_entity_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1
        FROM wallet_reconciliation_issue i
        WHERE i.resolved_at IS NULL
          AND i.issue_type = 'expiry_lots_exceed_wallet'
          AND i.user_id = wl.user_id
          AND i.merchant_id = wl.merchant_id
          AND i.currency = wl.currency
          AND i.target_entity_id IS NOT DISTINCT FROM wl.target_entity_id
          AND i.expiry_date = wl.expiry_date
      )
    GROUP BY wl.user_id, wl.merchant_id, wl.target_entity_id;

    INSERT INTO public.user_ticket_balances (user_id, merchant_id, ticket_type_id, balance)
    SELECT d.user_id, d.merchant_id, d.target_entity_id, 0
    FROM _expiry_due_tickets d
    ON CONFLICT (user_id, merchant_id, ticket_type_id) DO NOTHING;

    INSERT INTO _expiry_batch_groups (
      user_id, merchant_id, currency, target_entity_id, wallet_balance, due_amount, is_valid
    )
    SELECT d.user_id, d.merchant_id, 'ticket'::currency, d.target_entity_id,
           utb.balance, d.due_amount,
           (d.due_amount <= utb.balance)
    FROM _expiry_due_tickets d
    JOIN public.user_ticket_balances utb
      ON utb.user_id = d.user_id
     AND utb.merchant_id = d.merchant_id
     AND utb.ticket_type_id = d.target_entity_id
    ORDER BY d.user_id, d.merchant_id, d.target_entity_id
    LIMIT v_remaining
    FOR UPDATE OF utb SKIP LOCKED;
  END IF;

  INSERT INTO public.wallet_reconciliation_issue (
    issue_type, merchant_id, user_id, currency, target_entity_id, expiry_date,
    wallet_balance, lot_amount, difference, metadata
  )
  SELECT
    'expiry_lots_exceed_wallet',
    g.merchant_id,
    g.user_id,
    g.currency,
    g.target_entity_id,
    v_expiry_date,
    g.wallet_balance,
    g.due_amount,
    g.due_amount - g.wallet_balance,
    jsonb_build_object('run_id', v_run_id)
  FROM _expiry_batch_groups g
  WHERE NOT g.is_valid
  ON CONFLICT (
    issue_type,
    user_id,
    merchant_id,
    currency,
    (COALESCE(target_entity_id, '00000000-0000-0000-0000-000000000000'::uuid)),
    (COALESCE(expiry_date, DATE '0001-01-01'))
  ) WHERE resolved_at IS NULL
  DO UPDATE SET
    last_seen_at = now(),
    wallet_balance = EXCLUDED.wallet_balance,
    lot_amount = EXCLUDED.lot_amount,
    difference = EXCLUDED.difference,
    metadata = COALESCE(public.wallet_reconciliation_issue.metadata, '{}'::jsonb)
               || COALESCE(EXCLUDED.metadata, '{}'::jsonb);

  GET DIAGNOSTICS v_skipped = ROW_COUNT;

  INSERT INTO _expiry_deductions (ledger_id, user_id, merchant_id, currency, target_entity_id, deduct_amount)
  SELECT wl.id, wl.user_id, wl.merchant_id, wl.currency, wl.target_entity_id,
         wl.deductible_balance::integer
  FROM wallet_ledger wl
  JOIN _expiry_batch_groups g
    ON g.is_valid
   AND g.user_id = wl.user_id
   AND g.merchant_id = wl.merchant_id
   AND g.currency = wl.currency
   AND g.target_entity_id IS NOT DISTINCT FROM wl.target_entity_id
  WHERE wl.transaction_type = 'earn'::currency_transaction_type
    AND wl.expiry_date = v_expiry_date
    AND wl.expiry_processed_at IS NULL
    AND COALESCE(wl.deductible_balance, 0) > 0;

  UPDATE wallet_ledger wl
  SET expired_amount = COALESCE(wl.expired_amount, 0) + COALESCE(wl.deductible_balance, 0),
      deductible_balance = 0,
      expiry_processed_at = now()
  FROM _expiry_deductions d
  WHERE wl.id = d.ledger_id;

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
      p_description := 'Currency expiry for ' || v_expiry_date::text,
      p_dedup_key := 'expiry_' || v_user_rec.user_id::text || '_' || v_expiry_date::text
    );
    v_valid := v_valid + 1;
    v_amount_expired := v_amount_expired + v_user_rec.expire_amount;
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
      p_description := 'Ticket expiry for ' || v_expiry_date::text,
      p_dedup_key := 'expiry_ticket_' || v_user_rec.user_id::text || '_'
                     || COALESCE(v_user_rec.target_entity_id::text, '') || '_'
                     || v_expiry_date::text,
      p_target_entity_id := v_user_rec.target_entity_id
    );
    v_valid := v_valid + 1;
    v_amount_expired := v_amount_expired + v_user_rec.expire_amount;
  END LOOP;

  SELECT COUNT(DISTINCT (user_id, merchant_id))::integer
  INTO v_users
  FROM _expiry_deductions;

  SELECT EXISTS (
    SELECT 1
    FROM wallet_ledger wl
    WHERE wl.transaction_type = 'earn'::currency_transaction_type
      AND wl.expiry_date >= p_cutover_date
      AND wl.expiry_date <= p_run_date
      AND wl.expiry_processed_at IS NULL
      AND COALESCE(wl.deductible_balance, 0) > 0
      AND NOT EXISTS (
        SELECT 1
        FROM wallet_reconciliation_issue i
        WHERE i.resolved_at IS NULL
          AND i.issue_type = 'expiry_lots_exceed_wallet'
          AND i.user_id = wl.user_id
          AND i.merchant_id = wl.merchant_id
          AND i.currency = wl.currency
          AND i.target_entity_id IS NOT DISTINCT FROM wl.target_entity_id
          AND i.expiry_date = wl.expiry_date
      )
  ) INTO v_has_more;

  INSERT INTO expiry_processing_log (
    run_date, currency_type, users_affected, amount_expired, skipped_users, completed_at, details
  )
  SELECT
    p_run_date,
    g.currency,
    COUNT(DISTINCT g.user_id)::integer,
    COALESCE(SUM(g.due_amount) FILTER (WHERE g.is_valid), 0)::integer,
    COUNT(*) FILTER (WHERE NOT g.is_valid)::integer,
    now(),
    jsonb_build_object(
      'run_id', v_run_id,
      'expiry_date', v_expiry_date,
      'has_more', v_has_more,
      'groups_processed', COUNT(*) FILTER (WHERE g.is_valid),
      'groups_skipped', COUNT(*) FILTER (WHERE NOT g.is_valid)
    )
  FROM _expiry_batch_groups g
  GROUP BY g.currency;

  IF NOT FOUND THEN
    INSERT INTO expiry_processing_log (
      run_date, completed_at, users_affected, amount_expired, skipped_users, details
    ) VALUES (
      p_run_date, now(), 0, 0, 0,
      jsonb_build_object('run_id', v_run_id, 'expiry_date', v_expiry_date, 'has_more', v_has_more, 'reason', 'no_groups_locked')
    );
  END IF;

  RETURN jsonb_build_object(
    'has_more', v_has_more,
    'expiry_date', v_expiry_date,
    'groups_processed', v_valid,
    'groups_skipped', v_skipped,
    'users_affected', COALESCE(v_users, 0),
    'amount_expired', v_amount_expired,
    'run_id', v_run_id
  );
END;
$function$;

DROP FUNCTION IF EXISTS public.process_currency_expiry(date, integer);
DROP FUNCTION IF EXISTS public.process_expiry_if_needed();

CREATE PROCEDURE public.process_expiry_if_needed()
LANGUAGE plpgsql
SET search_path TO 'public'
AS $procedure$
DECLARE
  v_run_date date;
  v_cutover date := DATE '2026-08-31';
  v_result jsonb;
  v_loops integer := 0;
BEGIN
  v_run_date := (timezone('Asia/Bangkok', now()))::date;

  LOOP
    SELECT public.process_currency_expiry_batch(v_run_date, v_cutover, 1000, NULL)
      INTO v_result;
    v_loops := v_loops + 1;
    COMMIT;
    EXIT WHEN NOT COALESCE((v_result->>'has_more')::boolean, false);
    IF COALESCE((v_result->>'groups_processed')::integer, 0) = 0
       AND COALESCE((v_result->>'groups_skipped')::integer, 0) = 0 THEN
      PERFORM pg_sleep(0.25);
    END IF;
    IF v_loops > 100000 THEN
      RAISE EXCEPTION 'process_expiry_if_needed exceeded 100000 batches for %', v_run_date;
    END IF;
  END LOOP;
END;
$procedure$;

REVOKE ALL ON FUNCTION public.should_run_expiry_today(date, date) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.process_currency_expiry_batch(date, date, integer, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON PROCEDURE public.process_expiry_if_needed() FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.should_run_expiry_today(date, date) TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.process_currency_expiry_batch(date, date, integer, text) TO postgres, service_role;
GRANT EXECUTE ON PROCEDURE public.process_expiry_if_needed() TO postgres, service_role;

SELECT cron.alter_job(26, command := 'CALL process_expiry_if_needed()');
