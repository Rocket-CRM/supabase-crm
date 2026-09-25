-- Synthetic newcrm FIFO matrix. Runs as one DO block so fixture writes roll back.
-- Success: exception SQLERRM starts with FIFO_TEST_OK
-- Failure: any other exception

DO $test$
DECLARE
  c_merchant uuid := '09b45463-3812-42fb-9c7f-9d43b6fd3eb9';
  c_ticket_a uuid := '85862017-de7d-479f-9c92-50b27fb593dd';
  c_ticket_b uuid := '780545b9-0710-4d72-bfbc-2fccfda3c6cf';
  c_expiry date := DATE '2099-12-31';
  v_user uuid;
  v_user_exp uuid;
  v_user_batch uuid;
  v_user_tkt uuid;
  v_lot_old uuid := 'aaaaaaaa-0001-4000-8000-000000000001';
  v_lot_mid uuid := 'aaaaaaaa-0001-4000-8000-000000000002';
  v_lot_new uuid := 'aaaaaaaa-0001-4000-8000-000000000003';
  v_lot_ghost uuid := 'aaaaaaaa-0001-4000-8000-000000000004';
  v_lot_t1 uuid := 'aaaaaaaa-0001-4000-8000-000000000011';
  v_lot_t2 uuid := 'aaaaaaaa-0001-4000-8000-000000000012';
  v_lot_partial uuid := 'aaaaaaaa-0001-4000-8000-000000000021';
  v_lot_unrelated uuid := 'aaaaaaaa-0001-4000-8000-000000000022';
  v_wallet integer;
  v_db numeric;
  v_db2 numeric;
  v_expired numeric;
  v_bal integer;
  v_burn_count integer;
  v_event_count integer;
  v_i integer;
  v_failed boolean;
  v_err text;
  v_dedup text;
  v_api jsonb;
  v_wallet_before integer;
  rec record;
BEGIN
  INSERT INTO user_accounts (merchant_id, firstname, lastname, fullname, skip_cdc, is_active)
  VALUES (c_merchant, 'FIFO', 'ForwardFix', 'FIFO ForwardFix', true, true)
  RETURNING id INTO v_user;

  INSERT INTO user_wallet (user_id, merchant_id, points_balance, ticket_balance)
  VALUES (v_user, c_merchant, 0, 0);

  -- ---------------------------------------------------------------------
  -- Points FIFO
  -- ---------------------------------------------------------------------
  INSERT INTO wallet_ledger (
    id, user_id, merchant_id, currency, transaction_type, component, amount, signed_amount,
    balance_before, balance_after, deductible_balance, expired_amount, expiry_date,
    expiry_processed_at, source_type, source_id, description, created_at, skip_cdc
  ) VALUES
    (v_lot_old, v_user, c_merchant, 'points', 'earn', 'base', 40, 40, 0, 40, 40, 0, DATE '2030-01-01',
     NULL, 'manual', gen_random_uuid(), 'fifo old', TIMESTAMPTZ '2026-01-01 00:00:00+00', true),
    (v_lot_mid, v_user, c_merchant, 'points', 'earn', 'base', 30, 30, 40, 70, 30, 0, DATE '2030-06-01',
     NULL, 'manual', gen_random_uuid(), 'fifo mid', TIMESTAMPTZ '2026-01-02 00:00:00+00', true),
    (v_lot_new, v_user, c_merchant, 'points', 'earn', 'base', 50, 50, 70, 120, 50, 0, DATE '2031-01-01',
     NULL, 'manual', gen_random_uuid(), 'fifo new', TIMESTAMPTZ '2026-01-03 00:00:00+00', true),
    (v_lot_ghost, v_user, c_merchant, 'points', 'earn', 'base', 25, 25, 120, 145, 25, 0, DATE '2029-01-01',
     TIMESTAMPTZ '2026-01-01 00:00:00+00', 'manual', gen_random_uuid(), 'fifo ghost', TIMESTAMPTZ '2025-12-01 00:00:00+00', true);

  UPDATE user_wallet SET points_balance = 120 WHERE user_id = v_user AND merchant_id = c_merchant;

  PERFORM chokepoint_post_wallet_transaction(
    v_user, 'points'::currency, 'manual'::wallet_transaction_source_type,
    'adjustment'::currency_component, 'burn'::currency_transaction_type,
    55, gen_random_uuid(), c_merchant, 'fifo points burn',
    jsonb_build_object('_skip_emit', 'true')
  );

  SELECT points_balance INTO v_wallet FROM user_wallet WHERE user_id = v_user AND merchant_id = c_merchant;
  IF v_wallet <> 65 THEN
    RAISE EXCEPTION 'points_fifo: wallet % expected 65', v_wallet;
  END IF;
  SELECT deductible_balance INTO v_db FROM wallet_ledger WHERE id = v_lot_old;
  IF v_db <> 0 THEN RAISE EXCEPTION 'points_fifo: old lot % expected 0', v_db; END IF;
  SELECT deductible_balance INTO v_db FROM wallet_ledger WHERE id = v_lot_mid;
  IF v_db <> 15 THEN RAISE EXCEPTION 'points_fifo: mid lot % expected 15', v_db; END IF;
  SELECT deductible_balance INTO v_db FROM wallet_ledger WHERE id = v_lot_new;
  IF v_db <> 50 THEN RAISE EXCEPTION 'points_fifo: new lot % expected 50', v_db; END IF;
  SELECT deductible_balance INTO v_db FROM wallet_ledger WHERE id = v_lot_ghost;
  IF v_db <> 25 THEN RAISE EXCEPTION 'points_fifo: ghost lot % expected 25', v_db; END IF;

  -- ---------------------------------------------------------------------
  -- Ticket isolation
  -- ---------------------------------------------------------------------
  INSERT INTO user_ticket_balances (user_id, merchant_id, ticket_type_id, balance)
  VALUES (v_user, c_merchant, c_ticket_a, 5), (v_user, c_merchant, c_ticket_b, 4);

  INSERT INTO wallet_ledger (
    id, user_id, merchant_id, currency, transaction_type, component, amount, signed_amount,
    balance_before, balance_after, deductible_balance, expired_amount, expiry_date,
    source_type, source_id, description, target_entity_id, created_at, skip_cdc
  ) VALUES
    (v_lot_t1, v_user, c_merchant, 'ticket', 'earn', 'base', 5, 5, 0, 5, 5, 0, DATE '2030-02-01',
     'manual', gen_random_uuid(), 'ticket A lot', c_ticket_a, TIMESTAMPTZ '2026-02-01 00:00:00+00', true),
    (v_lot_t2, v_user, c_merchant, 'ticket', 'earn', 'base', 4, 4, 0, 4, 4, 0, DATE '2029-02-01',
     'manual', gen_random_uuid(), 'ticket B lot', c_ticket_b, TIMESTAMPTZ '2026-02-01 00:00:00+00', true);

  PERFORM chokepoint_post_wallet_transaction(
    v_user, 'ticket'::currency, 'manual'::wallet_transaction_source_type,
    'adjustment'::currency_component, 'burn'::currency_transaction_type,
    3, gen_random_uuid(), c_merchant, 'fifo ticket A burn',
    jsonb_build_object('_skip_emit', 'true'), c_ticket_a,
    'fifo-ticket-a-' || v_user::text
  );

  SELECT deductible_balance INTO v_db FROM wallet_ledger WHERE id = v_lot_t1;
  SELECT deductible_balance INTO v_db2 FROM wallet_ledger WHERE id = v_lot_t2;
  IF v_db <> 2 THEN RAISE EXCEPTION 'ticket_isolation: A lot % expected 2', v_db; END IF;
  IF v_db2 <> 4 THEN RAISE EXCEPTION 'ticket_isolation: B lot % expected 4', v_db2; END IF;
  SELECT balance INTO v_bal FROM user_ticket_balances
  WHERE user_id = v_user AND merchant_id = c_merchant AND ticket_type_id = c_ticket_a;
  IF v_bal <> 2 THEN RAISE EXCEPTION 'ticket_isolation: A wallet % expected 2', v_bal; END IF;

  -- ---------------------------------------------------------------------
  -- Atomic insufficient-lot failure
  -- ---------------------------------------------------------------------
  UPDATE user_wallet SET points_balance = 200 WHERE user_id = v_user AND merchant_id = c_merchant;
  SELECT points_balance INTO v_wallet_before FROM user_wallet WHERE user_id = v_user AND merchant_id = c_merchant;
  SELECT COUNT(*) INTO v_burn_count FROM wallet_ledger
  WHERE user_id = v_user AND merchant_id = c_merchant AND transaction_type = 'burn' AND currency = 'points';
  SELECT COUNT(*) INTO v_event_count FROM chokepoint_event_outbox
  WHERE payload->>'user_id' = v_user::text;

  v_failed := false;
  BEGIN
    PERFORM chokepoint_post_wallet_transaction(
      v_user, 'points'::currency, 'manual'::wallet_transaction_source_type,
      'adjustment'::currency_component, 'burn'::currency_transaction_type,
      80, gen_random_uuid(), c_merchant, 'fifo insufficient lots', '{}'::jsonb
    );
  EXCEPTION WHEN OTHERS THEN
    v_failed := true;
    v_err := SQLERRM;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'insufficient_lots: burn should have failed'; END IF;
  IF v_err NOT ILIKE '%Insufficient%lot%' THEN
    RAISE EXCEPTION 'insufficient_lots: unexpected error %', v_err;
  END IF;
  SELECT points_balance INTO v_wallet FROM user_wallet WHERE user_id = v_user AND merchant_id = c_merchant;
  IF v_wallet <> v_wallet_before THEN RAISE EXCEPTION 'insufficient_lots: wallet mutated to %', v_wallet; END IF;
  SELECT deductible_balance INTO v_db FROM wallet_ledger WHERE id = v_lot_mid;
  SELECT deductible_balance INTO v_db2 FROM wallet_ledger WHERE id = v_lot_new;
  IF v_db <> 15 OR v_db2 <> 50 THEN
    RAISE EXCEPTION 'insufficient_lots: lots mutated mid=% new=%', v_db, v_db2;
  END IF;
  SELECT COUNT(*) INTO v_i FROM wallet_ledger
  WHERE user_id = v_user AND merchant_id = c_merchant AND transaction_type = 'burn' AND currency = 'points';
  IF v_i <> v_burn_count THEN RAISE EXCEPTION 'insufficient_lots: burn ledger leaked'; END IF;
  SELECT COUNT(*) INTO v_i FROM chokepoint_event_outbox WHERE payload->>'user_id' = v_user::text;
  IF v_i <> v_event_count THEN RAISE EXCEPTION 'insufficient_lots: outbox leaked'; END IF;
  UPDATE user_wallet SET points_balance = 65 WHERE user_id = v_user AND merchant_id = c_merchant;

  -- ---------------------------------------------------------------------
  -- Partial redemption then expiry
  -- ---------------------------------------------------------------------
  INSERT INTO user_accounts (merchant_id, firstname, lastname, fullname, skip_cdc, is_active)
  VALUES (c_merchant, 'FIFO', 'PartialExpiry', 'FIFO PartialExpiry', true, true)
  RETURNING id INTO v_user_exp;

  INSERT INTO user_wallet (user_id, merchant_id, points_balance, ticket_balance)
  VALUES (v_user_exp, c_merchant, 100, 0);

  INSERT INTO wallet_ledger (
    id, user_id, merchant_id, currency, transaction_type, component, amount, signed_amount,
    balance_before, balance_after, deductible_balance, expired_amount, expiry_date,
    source_type, source_id, description, created_at, skip_cdc
  ) VALUES
    (v_lot_partial, v_user_exp, c_merchant, 'points', 'earn', 'base', 100, 100, 0, 100, 100, 0, c_expiry,
     'manual', gen_random_uuid(), 'partial earn', TIMESTAMPTZ '2026-03-01 00:00:00+00', true),
    (v_lot_unrelated, v_user, c_merchant, 'points', 'earn', 'base', 20, 20, 0, 20, 20, 0, DATE '2032-01-01',
     'manual', gen_random_uuid(), 'unrelated live lot', TIMESTAMPTZ '2026-03-02 00:00:00+00', true);

  UPDATE user_wallet SET points_balance = 85 WHERE user_id = v_user AND merchant_id = c_merchant;

  PERFORM chokepoint_post_wallet_transaction(
    v_user_exp, 'points'::currency, 'manual'::wallet_transaction_source_type,
    'adjustment'::currency_component, 'burn'::currency_transaction_type,
    60, gen_random_uuid(), c_merchant, 'partial burn',
    jsonb_build_object('_skip_emit', 'true')
  );

  PERFORM process_currency_expiry(c_expiry, 1000);

  SELECT deductible_balance, expired_amount INTO v_db, v_expired
  FROM wallet_ledger WHERE id = v_lot_partial;
  IF v_db <> 0 THEN RAISE EXCEPTION 'partial_expiry: deductible % expected 0', v_db; END IF;
  IF v_expired <> 40 THEN RAISE EXCEPTION 'partial_expiry: expired_amount % expected 40', v_expired; END IF;

  SELECT points_balance INTO v_wallet FROM user_wallet WHERE user_id = v_user_exp AND merchant_id = c_merchant;
  IF v_wallet <> 0 THEN RAISE EXCEPTION 'partial_expiry: wallet % expected 0', v_wallet; END IF;

  SELECT deductible_balance INTO v_db FROM wallet_ledger WHERE id = v_lot_unrelated;
  IF v_db <> 20 THEN RAISE EXCEPTION 'partial_expiry: unrelated lot changed to %', v_db; END IF;

  SELECT COUNT(*) INTO v_i FROM wallet_ledger
  WHERE user_id = v_user_exp AND source_type = 'expiry' AND currency = 'points';
  IF v_i <> 1 THEN RAISE EXCEPTION 'partial_expiry: expected 1 expiry burn, got %', v_i; END IF;

  -- ---------------------------------------------------------------------
  -- Multi-batch expiry (points)
  -- ---------------------------------------------------------------------
  INSERT INTO user_accounts (merchant_id, firstname, lastname, fullname, skip_cdc, is_active)
  VALUES (c_merchant, 'FIFO', 'MultiBatch', 'FIFO MultiBatch', true, true)
  RETURNING id INTO v_user_batch;

  INSERT INTO user_wallet (user_id, merchant_id, points_balance, ticket_balance)
  VALUES (v_user_batch, c_merchant, 11, 0);

  INSERT INTO wallet_ledger (
    user_id, merchant_id, currency, transaction_type, component, amount, signed_amount,
    balance_before, balance_after, deductible_balance, expired_amount, expiry_date,
    source_type, source_id, description, skip_cdc
  )
  SELECT v_user_batch, c_merchant, 'points', 'earn', 'base', 1, 1,
         gs - 1, gs, 1, 0, c_expiry, 'manual', gen_random_uuid(), 'batch lot', true
  FROM generate_series(1, 11) gs;

  PERFORM process_currency_expiry(c_expiry, 10);

  SELECT COUNT(*) INTO v_i FROM wallet_ledger
  WHERE user_id = v_user_batch AND source_type = 'expiry' AND currency = 'points';
  IF v_i <> 1 THEN RAISE EXCEPTION 'multi_batch_points: expiry burns % expected 1', v_i; END IF;

  SELECT amount INTO v_i FROM wallet_ledger
  WHERE user_id = v_user_batch AND source_type = 'expiry' AND currency = 'points';
  SELECT amount INTO v_i FROM wallet_ledger
  WHERE user_id = v_user_batch AND source_type = 'expiry' AND currency = 'points';
  IF v_i <> 11 THEN RAISE EXCEPTION 'multi_batch_points: amount % expected 11', v_i; END IF;

  SELECT COUNT(*) INTO v_i FROM wallet_ledger
  WHERE user_id = v_user_batch AND transaction_type = 'earn' AND COALESCE(deductible_balance, 0) > 0;
  IF v_i <> 0 THEN RAISE EXCEPTION 'multi_batch_points: % lots still deductible', v_i; END IF;

  SELECT points_balance INTO v_wallet FROM user_wallet WHERE user_id = v_user_batch AND merchant_id = c_merchant;
  IF v_wallet <> 0 THEN RAISE EXCEPTION 'multi_batch_points: wallet % expected 0', v_wallet; END IF;

  -- ---------------------------------------------------------------------
  -- Multi-batch expiry (tickets by target_entity_id)
  -- ---------------------------------------------------------------------
  INSERT INTO user_accounts (merchant_id, firstname, lastname, fullname, skip_cdc, is_active)
  VALUES (c_merchant, 'FIFO', 'TicketBatch', 'FIFO TicketBatch', true, true)
  RETURNING id INTO v_user_tkt;

  INSERT INTO user_ticket_balances (user_id, merchant_id, ticket_type_id, balance)
  VALUES (v_user_tkt, c_merchant, c_ticket_a, 11), (v_user_tkt, c_merchant, c_ticket_b, 3);

  INSERT INTO wallet_ledger (
    user_id, merchant_id, currency, transaction_type, component, amount, signed_amount,
    balance_before, balance_after, deductible_balance, expired_amount, expiry_date,
    source_type, source_id, description, target_entity_id, skip_cdc
  )
  SELECT v_user_tkt, c_merchant, 'ticket', 'earn', 'base', 1, 1,
         gs - 1, gs, 1, 0, c_expiry, 'manual', gen_random_uuid(), 'ticket batch A', c_ticket_a, true
  FROM generate_series(1, 11) gs;

  INSERT INTO wallet_ledger (
    user_id, merchant_id, currency, transaction_type, component, amount, signed_amount,
    balance_before, balance_after, deductible_balance, expired_amount, expiry_date,
    source_type, source_id, description, target_entity_id, skip_cdc
  ) VALUES
    (v_user_tkt, c_merchant, 'ticket', 'earn', 'base', 3, 3, 0, 3, 3, 0, c_expiry,
     'manual', gen_random_uuid(), 'ticket batch B', c_ticket_b, true);

  PERFORM process_currency_expiry(c_expiry, 10);

  SELECT COUNT(*) INTO v_i FROM wallet_ledger
  WHERE user_id = v_user_tkt AND source_type = 'expiry' AND currency = 'ticket' AND target_entity_id = c_ticket_a;
  IF v_i <> 11 THEN RAISE EXCEPTION 'multi_batch_tickets: A expiry rows % expected 11', v_i; END IF;

  SELECT COUNT(*) INTO v_i FROM wallet_ledger
  WHERE user_id = v_user_tkt AND source_type = 'expiry' AND currency = 'ticket' AND target_entity_id = c_ticket_b;
  IF v_i <> 3 THEN RAISE EXCEPTION 'multi_batch_tickets: B expiry rows % expected 3', v_i; END IF;

  SELECT COUNT(*) INTO v_i FROM wallet_ledger
  WHERE user_id = v_user_tkt AND transaction_type = 'earn' AND COALESCE(deductible_balance, 0) > 0;
  IF v_i <> 0 THEN RAISE EXCEPTION 'multi_batch_tickets: % lots still deductible', v_i; END IF;

  SELECT balance INTO v_bal FROM user_ticket_balances
  WHERE user_id = v_user_tkt AND ticket_type_id = c_ticket_a;
  IF v_bal <> 0 THEN RAISE EXCEPTION 'multi_batch_tickets: A wallet % expected 0', v_bal; END IF;

  -- ---------------------------------------------------------------------
  -- Idempotency and expiry source guard
  -- ---------------------------------------------------------------------
  v_dedup := 'fifo-test-dedup-' || v_user::text;
  SELECT points_balance INTO v_wallet_before FROM user_wallet WHERE user_id = v_user AND merchant_id = c_merchant;
  SELECT deductible_balance INTO v_db FROM wallet_ledger WHERE id = v_lot_mid;

  PERFORM chokepoint_post_wallet_transaction(
    v_user, 'points'::currency, 'manual'::wallet_transaction_source_type,
    'adjustment'::currency_component, 'burn'::currency_transaction_type,
    5, gen_random_uuid(), c_merchant, 'idempotent burn',
    jsonb_build_object('_skip_emit', 'true'), NULL, v_dedup
  );

  v_failed := false;
  BEGIN
    PERFORM chokepoint_post_wallet_transaction(
      v_user, 'points'::currency, 'manual'::wallet_transaction_source_type,
      'adjustment'::currency_component, 'burn'::currency_transaction_type,
      5, gen_random_uuid(), c_merchant, 'idempotent burn retry',
      jsonb_build_object('_skip_emit', 'true'), NULL, v_dedup
    );
  EXCEPTION WHEN unique_violation THEN
    v_failed := true;
  WHEN OTHERS THEN
    RAISE EXCEPTION 'idempotency: unexpected error %', SQLERRM;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'idempotency: retry should unique_violation'; END IF;

  SELECT points_balance INTO v_wallet FROM user_wallet WHERE user_id = v_user AND merchant_id = c_merchant;
  IF v_wallet <> v_wallet_before - 5 THEN
    RAISE EXCEPTION 'idempotency: wallet % expected %', v_wallet, v_wallet_before - 5;
  END IF;
  SELECT deductible_balance INTO v_db2 FROM wallet_ledger WHERE id = v_lot_mid;
  IF v_db2 <> v_db - 5 THEN RAISE EXCEPTION 'idempotency: lot mutated twice % from %', v_db2, v_db; END IF;

  -- expiry burn must not consume lots
  SELECT deductible_balance INTO v_db FROM wallet_ledger WHERE id = v_lot_new;
  PERFORM chokepoint_post_wallet_transaction(
    v_user, 'points'::currency, 'expiry'::wallet_transaction_source_type,
    'adjustment'::currency_component, 'burn'::currency_transaction_type,
    10, gen_random_uuid(), c_merchant, 'expiry guard',
    jsonb_build_object('_skip_emit', 'true'), NULL, 'expiry-guard-' || v_user::text
  );
  SELECT deductible_balance INTO v_db2 FROM wallet_ledger WHERE id = v_lot_new;
  IF v_db2 <> v_db THEN RAISE EXCEPTION 'expiry_guard: lot changed % -> %', v_db, v_db2; END IF;

  -- ---------------------------------------------------------------------
  -- Public API path
  -- ---------------------------------------------------------------------
  UPDATE user_wallet SET points_balance = points_balance + 8 WHERE user_id = v_user AND merchant_id = c_merchant;
  INSERT INTO wallet_ledger (
    user_id, merchant_id, currency, transaction_type, component, amount, signed_amount,
    balance_before, balance_after, deductible_balance, source_type, source_id, description, skip_cdc
  ) VALUES (
    v_user, c_merchant, 'points', 'earn', 'base', 8, 8, 0, 8, 8, 'manual', gen_random_uuid(), 'api cover lot', true
  );

  v_api := api_post_wallet_transaction(
    p_merchant_id := c_merchant,
    p_transaction_type := 'burn',
    p_amount := 3,
    p_dedup_key := 'fifo-api-' || v_user::text,
    p_user_id := v_user,
    p_description := 'openapi fifo burn'
  );
  IF COALESCE((v_api->>'success')::boolean, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'api_path: %', v_api;
  END IF;

  -- ---------------------------------------------------------------------
  -- Structural checks
  -- ---------------------------------------------------------------------
  IF EXISTS (
    SELECT 1 FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    WHERE NOT t.tgisinternal AND t.tgname = 'trg_fifo_burn_tracking'
  ) THEN
    RAISE EXCEPTION 'structural: fifo trigger still present';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'fn_apply_fifo_burn'
  ) THEN
    RAISE EXCEPTION 'structural: fn_apply_fifo_burn still present';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
    WHERE c.relname = 'wallet_ledger' AND t.tgname = 'set_dedup_key_on_wallet' AND NOT t.tgisinternal
  ) THEN
    RAISE EXCEPTION 'structural: set_dedup_key_on_wallet missing';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
    WHERE c.relname = 'wallet_ledger' AND t.tgname = 'trg_enqueue_shopify_store_credit_issue' AND NOT t.tgisinternal
  ) THEN
    RAISE EXCEPTION 'structural: shopify trigger missing';
  END IF;
  IF has_function_privilege('anon', 'util.fn_allocate_fifo_burn(uuid,uuid,currency,uuid,integer)', 'EXECUTE') THEN
    RAISE EXCEPTION 'structural: anon can execute allocator';
  END IF;
  IF has_function_privilege('authenticated', 'util.fn_allocate_fifo_burn(uuid,uuid,currency,uuid,integer)', 'EXECUTE') THEN
    RAISE EXCEPTION 'structural: authenticated can execute allocator';
  END IF;

  RAISE EXCEPTION 'FIFO_TEST_OK';
END;
$test$;
