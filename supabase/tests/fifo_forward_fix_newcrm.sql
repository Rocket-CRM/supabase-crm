-- Synthetic NewCRM fixtures. Intended to run in a transaction that rolls back.
-- Sentinel success: RAISE EXCEPTION 'FIFO_FORWARD_FIX_TESTS_PASSED'

DO $test$
DECLARE
  v_merchant_id uuid := '09b45463-3812-42fb-9c7f-9d43b6fd3eb9';
  v_user_id uuid;
  v_ticket_a uuid;
  v_ticket_b uuid;
  v_lot_early uuid;
  v_lot_late uuid;
  v_lot_ghost uuid;
  v_lot_unrelated uuid;
  v_unrelated_user uuid;
  v_wallet_before integer;
  v_wallet_after integer;
  v_early_after numeric;
  v_late_after numeric;
  v_ghost_after numeric;
  v_ticket_a_left numeric;
  v_ticket_b_left numeric;
  v_fail_sqlstate text;
  v_fail_lots numeric;
  v_fail_wallet integer;
  v_fail_burns integer;
  v_fail_events integer;
  v_expire_lot uuid;
  v_expire_unrelated uuid;
  v_points_burns integer;
  v_ticket_burns integer;
  v_batch_cleared integer;
  v_api jsonb;
  v_api_lot numeric;
  v_dedup_wallet integer;
  v_dedup_lot numeric;
  v_expiry_guard numeric;
  v_trigger_left integer;
  v_fn_left integer;
  v_other_triggers integer;
  v_allocator_anon boolean;
  v_allocator_auth boolean;
  v_allocator_service boolean;
  v_skip_meta jsonb := jsonb_build_object('_skip_emit', 'true');
  v_expire_date date := DATE '2099-01-15';
  v_run_id text := replace(gen_random_uuid()::text, '-', '');
  v_shortfall_before integer;
  v_shortfall_after integer;
  v_unallocated integer;
  v_issue_n integer;
  v_mismatch_user uuid;
  v_batch jsonb;
  v_cutover_lot uuid;
  v_allocator_left integer;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM merchant_master
    WHERE id = v_merchant_id AND merchant_code = 'newcrm'
  ) THEN
    RAISE EXCEPTION 'newcrm merchant % not found', v_merchant_id;
  END IF;

  INSERT INTO user_accounts (merchant_id, firstname, lastname, fullname, email, external_user_id, skip_cdc)
  VALUES (
    v_merchant_id,
    'FIFO',
    'Test',
    'FIFO Test',
    'fifo-test-' || v_run_id || '@example.invalid',
    'fifo-test-' || v_run_id,
    true
  )
  RETURNING id INTO v_user_id;

  INSERT INTO user_accounts (merchant_id, firstname, lastname, fullname, email, external_user_id, skip_cdc)
  VALUES (
    v_merchant_id,
    'FIFO',
    'Unrelated',
    'FIFO Unrelated',
    'fifo-unrelated-' || v_run_id || '@example.invalid',
    'fifo-unrelated-' || v_run_id,
    true
  )
  RETURNING id INTO v_unrelated_user;

  DELETE FROM wallet_ledger WHERE user_id IN (v_user_id, v_unrelated_user);
  DELETE FROM chokepoint_event_outbox
  WHERE payload->>'user_id' IN (v_user_id::text, v_unrelated_user::text);
  UPDATE user_wallet
  SET points_balance = 0
  WHERE user_id IN (v_user_id, v_unrelated_user) AND merchant_id = v_merchant_id;
  DELETE FROM user_ticket_balances
  WHERE user_id IN (v_user_id, v_unrelated_user) AND merchant_id = v_merchant_id;

  INSERT INTO ticket_type (merchant_id, ticket_code, name, active, expiry_mode, is_credit)
  VALUES (v_merchant_id, 'fifo_a_' || substr(v_run_id, 1, 12), 'FIFO Ticket A', true, 'none', false)
  RETURNING id INTO v_ticket_a;

  INSERT INTO ticket_type (merchant_id, ticket_code, name, active, expiry_mode, is_credit)
  VALUES (v_merchant_id, 'fifo_b_' || substr(v_run_id, 1, 12), 'FIFO Ticket B', true, 'none', false)
  RETURNING id INTO v_ticket_b;

  -- ------------------------------------------------------------------
  -- Points FIFO: earliest expiry first; ghost lot unchanged
  -- ------------------------------------------------------------------
  PERFORM chokepoint_post_wallet_transaction(
    v_user_id, 'points'::currency, 'manual'::wallet_transaction_source_type,
    'base'::currency_component, 'earn'::currency_transaction_type, 40,
    gen_random_uuid(), v_merchant_id, 'fifo early lot', v_skip_meta, NULL,
    'fifo-early-' || v_run_id
  );
  UPDATE wallet_ledger
  SET expiry_date = DATE '2099-01-01', created_at = now() - interval '3 days'
  WHERE user_id = v_user_id AND dedup_key = 'fifo-early-' || v_run_id
  RETURNING id INTO v_lot_early;

  PERFORM chokepoint_post_wallet_transaction(
    v_user_id, 'points'::currency, 'manual'::wallet_transaction_source_type,
    'base'::currency_component, 'earn'::currency_transaction_type, 50,
    gen_random_uuid(), v_merchant_id, 'fifo late lot', v_skip_meta, NULL,
    'fifo-late-' || v_run_id
  );
  UPDATE wallet_ledger
  SET expiry_date = DATE '2099-06-01', created_at = now() - interval '1 day'
  WHERE user_id = v_user_id AND dedup_key = 'fifo-late-' || v_run_id
  RETURNING id INTO v_lot_late;

  PERFORM chokepoint_post_wallet_transaction(
    v_user_id, 'points'::currency, 'manual'::wallet_transaction_source_type,
    'base'::currency_component, 'earn'::currency_transaction_type, 25,
    gen_random_uuid(), v_merchant_id, 'fifo ghost lot', v_skip_meta, NULL,
    'fifo-ghost-' || v_run_id
  );
  UPDATE wallet_ledger
  SET expiry_date = DATE '2098-01-01',
      expiry_processed_at = now() - interval '30 days',
      created_at = now() - interval '10 days'
  WHERE user_id = v_user_id AND dedup_key = 'fifo-ghost-' || v_run_id
  RETURNING id INTO v_lot_ghost;

  SELECT points_balance INTO v_wallet_before
  FROM user_wallet WHERE user_id = v_user_id AND merchant_id = v_merchant_id;

  PERFORM chokepoint_post_wallet_transaction(
    v_user_id, 'points'::currency, 'manual'::wallet_transaction_source_type,
    'base'::currency_component, 'burn'::currency_transaction_type, 55,
    gen_random_uuid(), v_merchant_id, 'fifo cross-lot burn', v_skip_meta, NULL,
    'fifo-burn-cross-' || v_run_id
  );

  SELECT points_balance INTO v_wallet_after
  FROM user_wallet WHERE user_id = v_user_id AND merchant_id = v_merchant_id;
  SELECT deductible_balance INTO v_early_after FROM wallet_ledger WHERE id = v_lot_early;
  SELECT deductible_balance INTO v_late_after FROM wallet_ledger WHERE id = v_lot_late;
  SELECT deductible_balance INTO v_ghost_after FROM wallet_ledger WHERE id = v_lot_ghost;

  IF v_wallet_after <> v_wallet_before - 55 THEN
    RAISE EXCEPTION 'points FIFO wallet expected % got %', v_wallet_before - 55, v_wallet_after;
  END IF;
  IF v_early_after <> 0 THEN
    RAISE EXCEPTION 'early lot should be fully consumed, got %', v_early_after;
  END IF;
  IF v_late_after <> 35 THEN
    RAISE EXCEPTION 'late lot should be 35, got %', v_late_after;
  END IF;
  IF v_ghost_after <> 25 THEN
    RAISE EXCEPTION 'ghost lot should stay 25, got %', v_ghost_after;
  END IF;

  BEGIN
    PERFORM chokepoint_post_wallet_transaction(
      v_user_id, 'points'::currency, 'manual'::wallet_transaction_source_type,
      'base'::currency_component, 'burn'::currency_transaction_type, 10,
      gen_random_uuid(), v_merchant_id, 'fifo cross-lot burn retry', v_skip_meta, NULL,
      'fifo-burn-cross-' || v_run_id
    );
    RAISE EXCEPTION 'duplicate dedup burn should have failed';
  EXCEPTION
    WHEN unique_violation THEN
      NULL;
    WHEN OTHERS THEN
      IF SQLERRM LIKE 'duplicate dedup burn should have failed' THEN
        RAISE;
      END IF;
      IF SQLSTATE <> '23505' THEN
        RAISE EXCEPTION 'duplicate dedup expected unique_violation, got % %', SQLSTATE, SQLERRM;
      END IF;
  END;

  IF (SELECT points_balance FROM user_wallet WHERE user_id = v_user_id AND merchant_id = v_merchant_id)
     <> v_wallet_after THEN
    RAISE EXCEPTION 'dedup retry mutated wallet';
  END IF;
  IF (SELECT deductible_balance FROM wallet_ledger WHERE id = v_lot_late) <> 35 THEN
    RAISE EXCEPTION 'dedup retry mutated lots';
  END IF;

  -- ------------------------------------------------------------------
  -- Ticket isolation
  -- ------------------------------------------------------------------
  PERFORM chokepoint_post_wallet_transaction(
    v_user_id, 'ticket'::currency, 'manual'::wallet_transaction_source_type,
    'base'::currency_component, 'earn'::currency_transaction_type, 3,
    gen_random_uuid(), v_merchant_id, 'fifo ticket A earn', v_skip_meta, v_ticket_a,
    'fifo-tix-a-' || v_run_id
  );
  PERFORM chokepoint_post_wallet_transaction(
    v_user_id, 'ticket'::currency, 'manual'::wallet_transaction_source_type,
    'base'::currency_component, 'earn'::currency_transaction_type, 3,
    gen_random_uuid(), v_merchant_id, 'fifo ticket B earn', v_skip_meta, v_ticket_b,
    'fifo-tix-b-' || v_run_id
  );
  PERFORM chokepoint_post_wallet_transaction(
    v_user_id, 'ticket'::currency, 'manual'::wallet_transaction_source_type,
    'base'::currency_component, 'burn'::currency_transaction_type, 2,
    gen_random_uuid(), v_merchant_id, 'fifo ticket A burn', v_skip_meta, v_ticket_a,
    'fifo-tix-a-burn-' || v_run_id
  );

  SELECT COALESCE(SUM(deductible_balance), 0) INTO v_ticket_a_left
  FROM wallet_ledger
  WHERE user_id = v_user_id AND currency = 'ticket' AND transaction_type = 'earn'
    AND target_entity_id = v_ticket_a;
  SELECT COALESCE(SUM(deductible_balance), 0) INTO v_ticket_b_left
  FROM wallet_ledger
  WHERE user_id = v_user_id AND currency = 'ticket' AND transaction_type = 'earn'
    AND target_entity_id = v_ticket_b;

  IF v_ticket_a_left <> 1 THEN
    RAISE EXCEPTION 'ticket A lots should be 1, got %', v_ticket_a_left;
  END IF;
  IF v_ticket_b_left <> 3 THEN
    RAISE EXCEPTION 'ticket B lots should stay 3, got %', v_ticket_b_left;
  END IF;

  -- ------------------------------------------------------------------
  -- Transitional burn: wallet > lots succeeds; shortfall does not grow
  -- ------------------------------------------------------------------
  SELECT COALESCE(SUM(deductible_balance), 0)::integer INTO v_fail_lots
  FROM wallet_ledger
  WHERE user_id = v_user_id AND currency = 'points' AND transaction_type = 'earn'
    AND expiry_processed_at IS NULL;
  SELECT points_balance INTO v_fail_wallet
  FROM user_wallet WHERE user_id = v_user_id AND merchant_id = v_merchant_id;

  v_shortfall_before := GREATEST(v_fail_wallet - v_fail_lots, 0);
  UPDATE user_wallet
  SET points_balance = points_balance + 80
  WHERE user_id = v_user_id AND merchant_id = v_merchant_id;
  SELECT points_balance INTO v_fail_wallet
  FROM user_wallet WHERE user_id = v_user_id AND merchant_id = v_merchant_id;
  v_shortfall_before := GREATEST(v_fail_wallet - v_fail_lots, 0);

  PERFORM chokepoint_post_wallet_transaction(
    v_user_id, 'points'::currency, 'manual'::wallet_transaction_source_type,
    'base'::currency_component, 'burn'::currency_transaction_type, (v_fail_lots + 20)::integer,
    gen_random_uuid(), v_merchant_id, 'fifo shortfall burn', v_skip_meta, NULL,
    'fifo-shortfall-burn-' || v_run_id
  );

  SELECT COALESCE(SUM(deductible_balance), 0)::integer INTO v_fail_lots
  FROM wallet_ledger
  WHERE user_id = v_user_id AND currency = 'points' AND transaction_type = 'earn'
    AND expiry_processed_at IS NULL;
  SELECT points_balance INTO v_wallet_after
  FROM user_wallet WHERE user_id = v_user_id AND merchant_id = v_merchant_id;
  v_shortfall_after := GREATEST(v_wallet_after - v_fail_lots, 0);
  IF v_fail_lots <> 0 THEN
    RAISE EXCEPTION 'transitional burn should consume all live lots, leftover %', v_fail_lots;
  END IF;
  IF v_shortfall_after > v_shortfall_before THEN
    RAISE EXCEPTION 'transitional burn increased shortfall from % to %', v_shortfall_before, v_shortfall_after;
  END IF;
  SELECT count(*) INTO v_issue_n
  FROM wallet_reconciliation_issue
  WHERE user_id = v_user_id AND merchant_id = v_merchant_id
    AND issue_type = 'burn_unallocated_shortfall' AND resolved_at IS NULL;
  IF v_issue_n <> 1 THEN
    RAISE EXCEPTION 'expected 1 burn shortfall issue, got %', v_issue_n;
  END IF;
  IF (SELECT (metadata->>'unallocated_fifo_amount')::integer
      FROM wallet_ledger WHERE dedup_key = 'fifo-shortfall-burn-' || v_run_id) <> 20 THEN
    RAISE EXCEPTION 'burn metadata should record unallocated_fifo_amount=20';
  END IF;

  v_allocator_left := util.fn_allocate_fifo_burn(
    v_user_id, v_merchant_id, 'points'::currency, NULL, 5
  );
  IF v_allocator_left <> 5 THEN
    RAISE EXCEPTION 'allocator should return full remainder when no live lots, got %', v_allocator_left;
  END IF;

  -- ------------------------------------------------------------------
  -- Partial redemption followed by expiry
  -- ------------------------------------------------------------------
  PERFORM chokepoint_post_wallet_transaction(
    v_unrelated_user, 'points'::currency, 'manual'::wallet_transaction_source_type,
    'base'::currency_component, 'earn'::currency_transaction_type, 80,
    gen_random_uuid(), v_merchant_id, 'unrelated live lot', v_skip_meta, NULL,
    'fifo-unrelated-' || v_run_id
  );
  UPDATE wallet_ledger
  SET expiry_date = DATE '2099-03-01'
  WHERE dedup_key = 'fifo-unrelated-' || v_run_id
  RETURNING id INTO v_expire_unrelated;

  PERFORM chokepoint_post_wallet_transaction(
    v_user_id, 'points'::currency, 'manual'::wallet_transaction_source_type,
    'base'::currency_component, 'earn'::currency_transaction_type, 100,
    gen_random_uuid(), v_merchant_id, 'partial then expire', v_skip_meta, NULL,
    'fifo-partial-earn-' || v_run_id
  );
  UPDATE wallet_ledger
  SET expiry_date = v_expire_date
  WHERE dedup_key = 'fifo-partial-earn-' || v_run_id
  RETURNING id INTO v_expire_lot;

  PERFORM chokepoint_post_wallet_transaction(
    v_user_id, 'points'::currency, 'manual'::wallet_transaction_source_type,
    'base'::currency_component, 'burn'::currency_transaction_type, 60,
    gen_random_uuid(), v_merchant_id, 'partial burn', v_skip_meta, NULL,
    'fifo-partial-burn-' || v_run_id
  );

  SELECT points_balance INTO v_wallet_before
  FROM user_wallet WHERE user_id = v_user_id AND merchant_id = v_merchant_id;

  PERFORM process_currency_expiry_batch(v_expire_date, v_expire_date, 1000, 'fifo-exp-' || v_run_id);

  IF (SELECT deductible_balance FROM wallet_ledger WHERE id = v_expire_lot) <> 0 THEN
    RAISE EXCEPTION 'expired lot deductible_balance should be 0';
  END IF;
  IF (SELECT expired_amount FROM wallet_ledger WHERE id = v_expire_lot) <> 40 THEN
    RAISE EXCEPTION 'expired lot expired_amount should be 40, got %',
      (SELECT expired_amount FROM wallet_ledger WHERE id = v_expire_lot);
  END IF;
  IF (SELECT points_balance FROM user_wallet WHERE user_id = v_user_id AND merchant_id = v_merchant_id)
     <> v_wallet_before - 40 THEN
    RAISE EXCEPTION 'expiry should reduce wallet by 40';
  END IF;
  IF (SELECT deductible_balance FROM wallet_ledger WHERE id = v_expire_unrelated) <> 80 THEN
    RAISE EXCEPTION 'unrelated lot should stay 80, got %',
      (SELECT deductible_balance FROM wallet_ledger WHERE id = v_expire_unrelated);
  END IF;
  IF (SELECT COALESCE(expired_amount, 0) FROM wallet_ledger WHERE id = v_expire_unrelated) <> 0 THEN
    RAISE EXCEPTION 'unrelated lot should not expire';
  END IF;
  IF (SELECT count(*) FROM wallet_ledger
      WHERE user_id = v_user_id AND source_type = 'expiry' AND currency = 'points'
        AND dedup_key = 'expiry_' || v_user_id::text || '_' || v_expire_date::text) <> 1 THEN
    RAISE EXCEPTION 'expected one points expiry burn for the test user';
  END IF;

  -- ------------------------------------------------------------------
  -- Multi-batch expiry: points and tickets
  -- ------------------------------------------------------------------
  INSERT INTO wallet_ledger (
    user_id, merchant_id, currency, transaction_type, component, amount, signed_amount,
    balance_before, balance_after, deductible_balance, expired_amount, source_type, source_id,
    description, target_entity_id, expiry_date, created_by, skip_cdc
  )
  SELECT
    v_user_id, v_merchant_id, 'points'::currency, 'earn'::currency_transaction_type,
    'base'::currency_component, 1, 1, 0, 1, 1, 0, 'manual'::wallet_transaction_source_type,
    gen_random_uuid(), 'fifo batch points', NULL, DATE '2099-02-01', v_user_id::text, true
  FROM generate_series(1, 1005);

  UPDATE user_wallet
  SET points_balance = points_balance + 1005
  WHERE user_id = v_user_id AND merchant_id = v_merchant_id;

  INSERT INTO wallet_ledger (
    user_id, merchant_id, currency, transaction_type, component, amount, signed_amount,
    balance_before, balance_after, deductible_balance, expired_amount, source_type, source_id,
    description, target_entity_id, expiry_date, created_by, skip_cdc
  )
  SELECT
    v_user_id, v_merchant_id, 'ticket'::currency, 'earn'::currency_transaction_type,
    'base'::currency_component, 1, 1, 0, 1, 1, 0, 'manual'::wallet_transaction_source_type,
    gen_random_uuid(), 'fifo batch tickets', v_ticket_a, DATE '2099-02-01', v_user_id::text, true
  FROM generate_series(1, 1005);

  INSERT INTO user_ticket_balances (user_id, merchant_id, ticket_type_id, balance)
  VALUES (v_user_id, v_merchant_id, v_ticket_a, 0)
  ON CONFLICT (user_id, merchant_id, ticket_type_id)
  DO UPDATE SET balance = user_ticket_balances.balance + 1005;

  PERFORM process_currency_expiry_batch(DATE '2099-02-01', DATE '2099-02-01', 1000, 'fifo-batch-' || v_run_id);

  SELECT count(*) INTO v_points_burns
  FROM wallet_ledger
  WHERE user_id = v_user_id AND source_type = 'expiry' AND currency = 'points'
    AND dedup_key = 'expiry_' || v_user_id::text || '_2099-02-01';
  SELECT count(*) INTO v_ticket_burns
  FROM wallet_ledger
  WHERE user_id = v_user_id AND source_type = 'expiry' AND currency = 'ticket'
    AND target_entity_id = v_ticket_a
    AND (dedup_key = 'expiry_ticket_' || v_user_id::text || '_' || v_ticket_a::text || '_2099-02-01'
         OR dedup_key LIKE 'expiry_ticket_' || v_user_id::text || '_' || v_ticket_a::text || '_2099-02-01%');
  SELECT count(*) INTO v_batch_cleared
  FROM wallet_ledger
  WHERE user_id = v_user_id
    AND expiry_date = DATE '2099-02-01'
    AND transaction_type = 'earn'
    AND description IN ('fifo batch points', 'fifo batch tickets')
    AND deductible_balance = 0
    AND expiry_processed_at IS NOT NULL;

  IF v_points_burns <> 1 THEN
    RAISE EXCEPTION 'multi-batch points expiry should write 1 burn, got %', v_points_burns;
  END IF;
  IF (SELECT amount FROM wallet_ledger
      WHERE user_id = v_user_id AND dedup_key = 'expiry_' || v_user_id::text || '_2099-02-01') <> 1005 THEN
    RAISE EXCEPTION 'multi-batch points expiry amount should be 1005';
  END IF;
  IF v_ticket_burns <> 1005 THEN
    RAISE EXCEPTION 'ticket expiry chokepoint writes one row per unit; expected 1005, got %', v_ticket_burns;
  END IF;
  IF v_batch_cleared <> 2010 THEN
    RAISE EXCEPTION 'expected 2010 cleared batch lots, got %', v_batch_cleared;
  END IF;

  -- ------------------------------------------------------------------
  -- Expiry source guard
  -- ------------------------------------------------------------------
  PERFORM chokepoint_post_wallet_transaction(
    v_user_id, 'points'::currency, 'manual'::wallet_transaction_source_type,
    'base'::currency_component, 'earn'::currency_transaction_type, 12,
    gen_random_uuid(), v_merchant_id, 'expiry guard lot', v_skip_meta, NULL,
    'fifo-guard-earn-' || v_run_id
  );
  SELECT deductible_balance INTO v_expiry_guard
  FROM wallet_ledger WHERE dedup_key = 'fifo-guard-earn-' || v_run_id;

  PERFORM chokepoint_post_wallet_transaction(
    v_user_id, 'points'::currency, 'expiry'::wallet_transaction_source_type,
    'adjustment'::currency_component, 'burn'::currency_transaction_type, 12,
    gen_random_uuid(), v_merchant_id, 'expiry guard burn', v_skip_meta, NULL,
    'fifo-guard-expiry-' || v_run_id
  );

  IF (SELECT deductible_balance FROM wallet_ledger WHERE dedup_key = 'fifo-guard-earn-' || v_run_id)
     <> v_expiry_guard THEN
    RAISE EXCEPTION 'expiry-source burn must not consume earn lots';
  END IF;

  -- ------------------------------------------------------------------
  -- Public API path
  -- ------------------------------------------------------------------
  v_api := api_post_wallet_transaction(
    p_merchant_id := v_merchant_id,
    p_transaction_type := 'earn',
    p_amount := 20,
    p_dedup_key := 'fifo-api-earn-' || substr(v_run_id, 1, 16),
    p_user_id := v_user_id,
    p_description := 'fifo api earn',
    p_currency := 'points'
  );
  IF COALESCE((v_api->>'success')::boolean, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'api earn failed: %', v_api;
  END IF;

  UPDATE wallet_ledger
  SET expiry_date = DATE '2000-01-01'
  WHERE merchant_id = v_merchant_id
    AND dedup_key = 'openapi:' || v_merchant_id::text || ':fifo-api-earn-' || substr(v_run_id, 1, 16);

  v_api := api_post_wallet_transaction(
    p_merchant_id := v_merchant_id,
    p_transaction_type := 'burn',
    p_amount := 8,
    p_dedup_key := 'fifo-api-burn-' || substr(v_run_id, 1, 16),
    p_user_id := v_user_id,
    p_description := 'fifo api burn',
    p_currency := 'points'
  );
  IF COALESCE((v_api->>'success')::boolean, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'api burn failed: %', v_api;
  END IF;

  SELECT deductible_balance INTO v_api_lot
  FROM wallet_ledger
  WHERE merchant_id = v_merchant_id
    AND dedup_key = 'openapi:' || v_merchant_id::text || ':fifo-api-earn-' || substr(v_run_id, 1, 16);
  IF v_api_lot <> 12 THEN
    RAISE EXCEPTION 'api burn should reduce the api earn lot to 12, got %', v_api_lot;
  END IF;

  v_api := api_post_wallet_transaction(
    p_merchant_id := v_merchant_id,
    p_transaction_type := 'earn',
    p_amount := 2,
    p_dedup_key := 'fifo-api-tix-' || substr(v_run_id, 1, 16),
    p_user_id := v_user_id,
    p_description := 'fifo api ticket earn',
    p_currency := 'ticket',
    p_ticket_type_id := v_ticket_b
  );
  IF COALESCE((v_api->>'success')::boolean, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'api ticket earn failed: %', v_api;
  END IF;

  v_api := api_post_wallet_transaction(
    p_merchant_id := v_merchant_id,
    p_transaction_type := 'burn',
    p_amount := 1,
    p_dedup_key := 'fifo-api-tix-burn-' || substr(v_run_id, 1, 16),
    p_user_id := v_user_id,
    p_description := 'fifo api ticket burn',
    p_currency := 'ticket',
    p_ticket_type_id := v_ticket_b
  );
  IF COALESCE((v_api->>'success')::boolean, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'api ticket burn failed: %', v_api;
  END IF;

  -- ------------------------------------------------------------------
  -- Expiry mismatch isolation + cutover exclusion
  -- ------------------------------------------------------------------
  INSERT INTO user_accounts (merchant_id, firstname, lastname, fullname, email, external_user_id, skip_cdc)
  VALUES (
    v_merchant_id, 'FIFO', 'Mismatch', 'FIFO Mismatch',
    'fifo-mismatch-' || v_run_id || '@example.invalid',
    'fifo-mismatch-' || v_run_id, true
  )
  RETURNING id INTO v_mismatch_user;

  PERFORM chokepoint_post_wallet_transaction(
    v_mismatch_user, 'points'::currency, 'manual'::wallet_transaction_source_type,
    'base'::currency_component, 'earn'::currency_transaction_type, 50,
    gen_random_uuid(), v_merchant_id, 'mismatch lots', v_skip_meta, NULL,
    'fifo-mismatch-earn-' || v_run_id
  );
  UPDATE wallet_ledger
  SET expiry_date = DATE '2099-04-01', deductible_balance = 80
  WHERE dedup_key = 'fifo-mismatch-earn-' || v_run_id;
  UPDATE user_wallet
  SET points_balance = 30
  WHERE user_id = v_mismatch_user AND merchant_id = v_merchant_id;

  PERFORM chokepoint_post_wallet_transaction(
    v_unrelated_user, 'points'::currency, 'manual'::wallet_transaction_source_type,
    'base'::currency_component, 'earn'::currency_transaction_type, 15,
    gen_random_uuid(), v_merchant_id, 'valid expiry neighbor', v_skip_meta, NULL,
    'fifo-valid-exp-' || v_run_id
  );
  UPDATE wallet_ledger
  SET expiry_date = DATE '2099-04-01'
  WHERE dedup_key = 'fifo-valid-exp-' || v_run_id;

  PERFORM chokepoint_post_wallet_transaction(
    v_unrelated_user, 'points'::currency, 'manual'::wallet_transaction_source_type,
    'base'::currency_component, 'earn'::currency_transaction_type, 9,
    gen_random_uuid(), v_merchant_id, 'pre-cutover lot', v_skip_meta, NULL,
    'fifo-cutover-' || v_run_id
  );
  UPDATE wallet_ledger
  SET expiry_date = DATE '2099-03-01'
  WHERE dedup_key = 'fifo-cutover-' || v_run_id
  RETURNING id INTO v_cutover_lot;

  SELECT points_balance INTO v_wallet_before
  FROM user_wallet WHERE user_id = v_mismatch_user AND merchant_id = v_merchant_id;

  v_batch := process_currency_expiry_batch(
    DATE '2099-04-01', DATE '2099-04-01', 1000, 'fifo-mismatch-' || v_run_id
  );

  IF COALESCE((v_batch->>'groups_skipped')::integer, 0) < 1 THEN
    RAISE EXCEPTION 'mismatch batch should skip the drifted member: %', v_batch;
  END IF;
  IF (SELECT deductible_balance FROM wallet_ledger WHERE dedup_key = 'fifo-mismatch-earn-' || v_run_id) <> 80 THEN
    RAISE EXCEPTION 'mismatched lots must stay unchanged';
  END IF;
  IF (SELECT points_balance FROM user_wallet WHERE user_id = v_mismatch_user AND merchant_id = v_merchant_id)
     <> v_wallet_before THEN
    RAISE EXCEPTION 'mismatched wallet must stay unchanged';
  END IF;
  IF (SELECT deductible_balance FROM wallet_ledger WHERE dedup_key = 'fifo-valid-exp-' || v_run_id) <> 0 THEN
    RAISE EXCEPTION 'valid neighbor should expire';
  END IF;
  IF (SELECT deductible_balance FROM wallet_ledger WHERE id = v_cutover_lot) <> 9 THEN
    RAISE EXCEPTION 'pre-cutover lot should be ignored';
  END IF;
  SELECT count(*) INTO v_issue_n
  FROM wallet_reconciliation_issue
  WHERE user_id = v_mismatch_user AND issue_type = 'expiry_lots_exceed_wallet'
    AND expiry_date = DATE '2099-04-01' AND resolved_at IS NULL;
  IF v_issue_n <> 1 THEN
    RAISE EXCEPTION 'expected 1 expiry mismatch issue, got %', v_issue_n;
  END IF;

  v_batch := process_currency_expiry_batch(
    DATE '2099-04-01', DATE '2099-04-01', 1000, 'fifo-mismatch-retry-' || v_run_id
  );
  IF COALESCE((v_batch->>'has_more')::boolean, true) THEN
    RAISE EXCEPTION 'retry after recording the issue should have no remaining work: %', v_batch;
  END IF;

  -- ------------------------------------------------------------------
  -- Structural verification
  -- ------------------------------------------------------------------
  SELECT count(*) INTO v_trigger_left
  FROM pg_trigger t
  JOIN pg_class c ON c.oid = t.tgrelid
  WHERE NOT tgisinternal AND tgname = 'trg_fifo_burn_tracking';

  SELECT count(*) INTO v_fn_left
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'fn_apply_fifo_burn';

  SELECT count(*) INTO v_other_triggers
  FROM pg_trigger t
  JOIN pg_class c ON c.oid = t.tgrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'wallet_ledger' AND NOT tgisinternal
    AND tgname IN ('set_dedup_key_on_wallet', 'trg_enqueue_shopify_store_credit_issue');

  SELECT has_function_privilege('anon', 'util.fn_allocate_fifo_burn(uuid,uuid,currency,uuid,integer)', 'EXECUTE')
    INTO v_allocator_anon;
  SELECT has_function_privilege('authenticated', 'util.fn_allocate_fifo_burn(uuid,uuid,currency,uuid,integer)', 'EXECUTE')
    INTO v_allocator_auth;
  SELECT has_function_privilege('service_role', 'util.fn_allocate_fifo_burn(uuid,uuid,currency,uuid,integer)', 'EXECUTE')
    INTO v_allocator_service;

  IF v_trigger_left <> 0 THEN
    RAISE EXCEPTION 'FIFO trigger still exists';
  END IF;
  IF v_fn_left <> 0 THEN
    RAISE EXCEPTION 'fn_apply_fifo_burn still exists';
  END IF;
  IF v_other_triggers <> 2 THEN
    RAISE EXCEPTION 'unrelated wallet_ledger triggers missing; found %', v_other_triggers;
  END IF;
  IF NOT v_allocator_service THEN
    RAISE EXCEPTION 'allocator is not executable by service_role';
  END IF;
  IF NOT v_allocator_service THEN
    RAISE EXCEPTION 'allocator is not executable by service_role';
  END IF;
  SELECT has_function_privilege('anon', 'public.process_currency_expiry_batch(date,date,integer,text)', 'EXECUTE')
    INTO v_allocator_anon;
  IF v_allocator_anon THEN
    RAISE EXCEPTION 'expiry batch RPC is executable by anon';
  END IF;
  IF to_regprocedure('public.process_currency_expiry(date,integer)') IS NOT NULL THEN
    RAISE EXCEPTION 'legacy process_currency_expiry(date,integer) still exists';
  END IF;
  IF to_regprocedure('public.process_expiry_if_needed()') IS NULL THEN
    RAISE EXCEPTION 'process_expiry_if_needed procedure missing';
  END IF;

  RAISE EXCEPTION 'FIFO_FORWARD_FIX_TESTS_PASSED';
END;
$test$;
