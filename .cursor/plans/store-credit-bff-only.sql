CREATE OR REPLACE FUNCTION public.bff_store_credit(p_mode text, p_data jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_mode text := lower(trim(COALESCE(p_mode, '')));
  v_user_id uuid := NULLIF(trim(p_data->>'user_id'), '')::uuid;
  v_amount integer := COALESCE((p_data->>'amount')::integer, (p_data->>'store_credit_amount')::integer, 0);
  v_event_id uuid := NULLIF(trim(p_data->>'event_id'), '')::uuid;
  v_ticket_type_id uuid;
  v_balance integer := 0;
  v_admin_user_id uuid;
  v_admin_auth uuid := auth.uid();
  v_promo jsonb;
  v_bonus integer := 0;
  v_session_id uuid;
  v_spend_session_id uuid;
  v_base_ledger_id uuid;
  v_bonus_ledger_id uuid;
  v_burn_ledger_id uuid;
  v_applicable integer;
  v_reason text := NULLIF(trim(p_data->>'reason'), '');
  v_paid_amount integer := NULLIF(trim(p_data->>'paid_amount'), '')::integer;
  v_limit integer := LEAST(GREATEST(COALESCE((p_data->>'limit')::integer, 20), 1), 100);
  v_topup_sessions jsonb;
  v_ledger jsonb;
  v_history jsonb;
  v_expiry jsonb;
  v_order jsonb;
  v_total_to_reverse integer;
  v_reversal_id uuid;
  v_original wallet_ledger%ROWTYPE;
  v_code text;
  v_can_reverse boolean := false;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error('No merchant context', 'Unable to resolve merchant for this request.', 'NO_MERCHANT_CONTEXT');
  END IF;

  SELECT au.id INTO v_admin_user_id
  FROM admin_users au
  WHERE au.auth_user_id = v_admin_auth
    AND au.merchant_id = v_merchant_id
    AND au.active_status = true;

  IF v_mode IN ('list_promos') THEN
    RETURN bff_store_credit_promo('list', NULL, COALESCE(p_data, '{}'::jsonb) || jsonb_build_object('active_only', true));
  END IF;

  IF v_mode IN ('get', 'preview_topup', 'preview_spend', 'expiry', 'list_promos') THEN
    IF NOT (
      check_admin_permission('frontline_store_credit', 'read')
      OR check_admin_permission('frontline_store_credit', 'update')
      OR check_admin_permission('frontline_store_credit', 'create')
    ) THEN
      RETURN fn_response_error('Forbidden', 'Insufficient permission to view store credit.', 'FORBIDDEN');
    END IF;
  END IF;

  IF v_mode IN ('topup', 'spend', 'submit_event_order') THEN
    IF NOT (
      check_admin_permission('frontline_store_credit', 'create')
      OR check_admin_permission('frontline_store_credit', 'update')
    ) THEN
      RETURN fn_response_error('Forbidden', 'Insufficient permission for store credit write.', 'FORBIDDEN');
    END IF;
  END IF;

  IF v_mode IN ('reverse_topup', 'reverse_spend') THEN
    IF NOT (
      check_admin_permission('frontline_store_credit', 'create')
      OR check_admin_permission('frontline_store_credit', 'update')
      OR check_admin_permission('currency', 'update')
    ) THEN
      RETURN fn_response_error('Forbidden', 'Insufficient permission to reverse store credit.', 'FORBIDDEN');
    END IF;
  END IF;

  IF v_mode = 'reverse_expiry' THEN
    IF NOT check_admin_permission('currency', 'update') THEN
      RETURN fn_response_error('Forbidden', 'Insufficient permission to reverse expiry.', 'FORBIDDEN');
    END IF;
  END IF;

  v_ticket_type_id := fn_resolve_internal_store_credit_ticket_type(v_merchant_id, true);

  IF v_mode = 'get' THEN
    IF v_user_id IS NULL THEN
      RETURN fn_response_error('Validation error', 'user_id is required.', 'VALIDATION_ERROR');
    END IF;

    SELECT COALESCE(utb.balance, 0) INTO v_balance
    FROM user_ticket_balances utb
    WHERE utb.user_id = v_user_id AND utb.merchant_id = v_merchant_id AND utb.ticket_type_id = v_ticket_type_id;

    v_can_reverse := (
      check_admin_permission('frontline_store_credit', 'create')
      OR check_admin_permission('frontline_store_credit', 'update')
      OR check_admin_permission('currency', 'update')
    );

    v_history := fn_store_credit_wallet_history(
      v_merchant_id, v_user_id, v_ticket_type_id, COALESCE(v_balance, 0), v_can_reverse, v_limit
    );

    SELECT COALESCE(jsonb_agg(x ORDER BY x->>'created_at' DESC), '[]'::jsonb) INTO v_topup_sessions
    FROM (
      SELECT jsonb_build_object(
        'topup_session_id', wl.metadata->>'topup_session_id',
        'base_amount', SUM(CASE WHEN wl.metadata->>'operation' = 'store_credit_topup' THEN wl.amount ELSE 0 END),
        'bonus_amount', SUM(CASE WHEN wl.metadata->>'operation' = 'store_credit_topup_bonus' THEN wl.amount ELSE 0 END),
        'total_amount', SUM(wl.amount),
        'paid_amount', MAX(wl.metadata->>'paid_amount'),
        'event_id', MAX(wl.metadata->>'event_id'),
        'status', COALESCE(MAX(wl.metadata->>'status'), 'active'),
        'is_reversed', (COALESCE(MAX(wl.metadata->>'status'), '') = 'reversed'),
        'can_reverse', (
          COALESCE(MAX(wl.metadata->>'status'), '') <> 'reversed'
          AND v_can_reverse
          AND COALESCE(v_balance, 0) >= SUM(wl.amount)
        ),
        'reversal_wallet_ledger_id', MAX(wl.metadata->>'reversal_wallet_ledger_id'),
        'reversed_at', MAX(wl.metadata->>'reversed_at'),
        'reversal_reason', MAX(wl.metadata->>'reversal_reason'),
        'created_at', MIN(wl.created_at)
      ) AS x
      FROM wallet_ledger wl
      WHERE wl.merchant_id = v_merchant_id AND wl.user_id = v_user_id AND wl.target_entity_id = v_ticket_type_id
        AND wl.transaction_type = 'earn' AND wl.metadata ? 'topup_session_id'
      GROUP BY wl.metadata->>'topup_session_id'
      ORDER BY MIN(wl.created_at) DESC
      LIMIT v_limit
    ) s;

    SELECT COALESCE(jsonb_agg(to_jsonb(wl) ORDER BY wl.created_at DESC), '[]'::jsonb) INTO v_ledger
    FROM (
      SELECT wl.id, wl.created_at, wl.transaction_type, wl.component, wl.amount, wl.balance_after,
             wl.source_type, wl.source_id, wl.description, wl.expiry_date, wl.metadata, wl.code
      FROM wallet_ledger wl
      WHERE wl.merchant_id = v_merchant_id AND wl.user_id = v_user_id AND wl.target_entity_id = v_ticket_type_id
      ORDER BY wl.created_at DESC
      LIMIT v_limit
    ) wl;

    RETURN fn_response_success('Store credit', 'Wallet loaded.', jsonb_build_object(
      'user_id', v_user_id,
      'ticket_type_id', v_ticket_type_id,
      'balance', COALESCE(v_balance, 0),
      'history', COALESCE(v_history, '[]'::jsonb),
      'topup_sessions', COALESCE(v_topup_sessions, '[]'::jsonb),
      'ledger', COALESCE(v_ledger, '[]'::jsonb)
    ));
  END IF;

  IF v_mode = 'preview_topup' THEN
    IF v_user_id IS NULL OR v_amount <= 0 THEN
      RETURN fn_response_error('Validation error', 'user_id and positive amount are required.', 'VALIDATION_ERROR');
    END IF;
    v_promo := fn_calc_store_credit_promo_bonus(v_merchant_id, v_amount, v_event_id);
    v_bonus := COALESCE((v_promo->>'bonus_amount')::integer, 0);
    RETURN fn_response_success('Top-up preview', 'Bonus calculated.', jsonb_build_object(
      'user_id', v_user_id,
      'base_amount', v_amount,
      'bonus_amount', v_bonus,
      'total_credit', v_amount + v_bonus,
      'promo', v_promo
    ));
  END IF;

  IF v_mode = 'topup' THEN
    IF v_user_id IS NULL OR v_amount <= 0 THEN
      RETURN fn_response_error('Validation error', 'user_id and positive amount are required.', 'VALIDATION_ERROR');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM user_accounts ua WHERE ua.id = v_user_id AND ua.merchant_id = v_merchant_id AND COALESCE(ua.is_active, true) AND ua.deleted_at IS NULL) THEN
      RETURN fn_response_error('Customer not found', 'Customer does not belong to this merchant.', 'CUSTOMER_NOT_FOUND');
    END IF;

    v_promo := fn_calc_store_credit_promo_bonus(v_merchant_id, v_amount, v_event_id);
    v_bonus := COALESCE((v_promo->>'bonus_amount')::integer, 0);
    v_session_id := COALESCE(NULLIF(trim(p_data->>'topup_session_id'), '')::uuid, gen_random_uuid());

    v_base_ledger_id := chokepoint_post_wallet_transaction(
      v_user_id, 'ticket'::currency, 'manual'::wallet_transaction_source_type, 'base'::currency_component,
      'earn'::currency_transaction_type, v_amount, v_session_id, v_merchant_id,
      COALESCE(v_reason, 'Store credit top-up'),
      jsonb_build_object(
        'operation', 'store_credit_topup',
        'topup_session_id', v_session_id,
        'paid_amount', v_paid_amount,
        'event_id', v_event_id,
        'admin_user_id', v_admin_user_id,
        'admin_auth_user_id', v_admin_auth
      ),
      v_ticket_type_id,
      'store_credit_topup:' || v_session_id::text || ':base'
    );

    IF v_bonus > 0 THEN
      v_bonus_ledger_id := chokepoint_post_wallet_transaction(
        v_user_id, 'ticket'::currency, 'campaign'::wallet_transaction_source_type, 'bonus'::currency_component,
        'earn'::currency_transaction_type, v_bonus, v_session_id, v_merchant_id,
        COALESCE(v_reason, 'Store credit top-up bonus'),
        jsonb_build_object(
          'operation', 'store_credit_topup_bonus',
          'topup_session_id', v_session_id,
          'promo_id', v_promo->>'promo_id',
          'event_id', v_event_id,
          'admin_user_id', v_admin_user_id
        ),
        v_ticket_type_id,
        'store_credit_topup:' || v_session_id::text || ':bonus'
      );
      UPDATE wallet_ledger SET source_id = (v_promo->>'promo_id')::uuid
      WHERE id = v_bonus_ledger_id AND merchant_id = v_merchant_id;
    END IF;

    SELECT COALESCE(utb.balance, 0) INTO v_balance
    FROM user_ticket_balances utb
    WHERE utb.user_id = v_user_id AND utb.merchant_id = v_merchant_id AND utb.ticket_type_id = v_ticket_type_id;

    RETURN fn_response_success('Store credit topped up', 'Top-up posted to wallet.', jsonb_build_object(
      'topup_session_id', v_session_id,
      'user_id', v_user_id,
      'base_amount', v_amount,
      'bonus_amount', v_bonus,
      'total_credit', v_amount + v_bonus,
      'balance', v_balance,
      'base_wallet_ledger_id', v_base_ledger_id,
      'bonus_wallet_ledger_id', v_bonus_ledger_id,
      'promo', v_promo
    ));
  END IF;

  IF v_mode = 'preview_spend' THEN
    IF v_user_id IS NULL OR v_amount <= 0 THEN
      RETURN fn_response_error('Validation error', 'user_id and positive amount are required.', 'VALIDATION_ERROR');
    END IF;
    SELECT COALESCE(utb.balance, 0) INTO v_balance
    FROM user_ticket_balances utb
    WHERE utb.user_id = v_user_id AND utb.merchant_id = v_merchant_id AND utb.ticket_type_id = v_ticket_type_id;
    v_applicable := LEAST(v_balance, v_amount);
    RETURN fn_response_success('Spend preview', 'Applicable store credit calculated.', jsonb_build_object(
      'user_id', v_user_id,
      'requested_amount', v_amount,
      'available_balance', v_balance,
      'applicable_amount', v_applicable,
      'remaining_balance', GREATEST(v_balance - v_applicable, 0)
    ));
  END IF;

  IF v_mode IN ('spend', 'submit_event_order') THEN
    IF v_user_id IS NULL OR v_amount <= 0 THEN
      RETURN fn_response_error('Validation error', 'user_id and positive amount are required.', 'VALIDATION_ERROR');
    END IF;

    v_spend_session_id := COALESCE(NULLIF(trim(p_data->>'spend_session_id'), '')::uuid, gen_random_uuid());

    v_burn_ledger_id := chokepoint_post_wallet_transaction(
      v_user_id, 'ticket'::currency,
      CASE WHEN v_mode = 'submit_event_order' THEN 'purchase'::wallet_transaction_source_type ELSE COALESCE(NULLIF(trim(p_data->>'source_type'), ''), 'manual')::wallet_transaction_source_type END,
      'base'::currency_component, 'burn'::currency_transaction_type, v_amount, v_spend_session_id, v_merchant_id,
      COALESCE(NULLIF(trim(p_data->>'description'), ''), 'Store credit spend'),
      jsonb_build_object(
        'operation', 'store_credit_spend',
        'spend_session_id', v_spend_session_id,
        'event_id', v_event_id,
        'admin_user_id', v_admin_user_id,
        'purchase_id', NULLIF(trim(p_data->>'purchase_id'), '')
      ),
      v_ticket_type_id,
      'store_credit_spend:' || v_spend_session_id::text
    );

    v_code := fn_generate_store_credit_spend_code(v_merchant_id);

    UPDATE wallet_ledger
    SET code = v_code,
        discount_amount = v_amount,
        metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object('scan_code', v_code, 'status', 'issued'),
        created_by = COALESCE(v_admin_auth::text, created_by)
    WHERE id = v_burn_ledger_id AND merchant_id = v_merchant_id;

    UPDATE wallet_ledger
    SET metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object('scan_code', v_code, 'status', 'issued')
    WHERE merchant_id = v_merchant_id
      AND metadata->>'spend_session_id' = v_spend_session_id::text
      AND transaction_type = 'burn'
      AND id <> v_burn_ledger_id;

    IF v_mode = 'spend' THEN
      SELECT COALESCE(utb.balance, 0) INTO v_balance
      FROM user_ticket_balances utb
      WHERE utb.user_id = v_user_id AND utb.merchant_id = v_merchant_id AND utb.ticket_type_id = v_ticket_type_id;
      RETURN fn_response_success('Store credit spent', 'Burn posted to wallet.', jsonb_build_object(
        'spend_session_id', v_spend_session_id,
        'wallet_ledger_id', v_burn_ledger_id,
        'code', v_code,
        'amount', v_amount,
        'balance', v_balance
      ));
    END IF;

    v_order := api_create_manual_purchase_order(
      v_merchant_id,
      v_user_id,
      COALESCE(p_data->'items', '[]'::jsonb),
      COALESCE(NULLIF(trim(p_data->>'payment_method'), ''), 'mixed'),
      NULLIF(trim(p_data->>'notes'), ''),
      COALESCE(p_data->'metadata', '{}'::jsonb) || jsonb_build_object(
        'store_credit_amount', v_amount,
        'store_credit_spend_session_id', v_spend_session_id,
        'store_credit_wallet_ledger_id', v_burn_ledger_id,
        'store_credit_code', v_code
      ),
      COALESCE(NULLIF(trim(p_data->>'transaction_source'), ''), 'event_order'),
      COALESCE(NULLIF(trim(p_data->>'transaction_source_id'), '')::uuid, v_event_id),
      NULLIF(trim(p_data->>'seller_id'), '')::uuid,
      p_data->'chosen_freebies'
    );

    IF COALESCE((v_order->>'success')::boolean, false) = false THEN
      PERFORM reverse_tickets(v_user_id, v_merchant_id, v_ticket_type_id, v_amount, 'Auto-reverse store credit after failed order', v_spend_session_id);
      UPDATE wallet_ledger SET code = NULL, discount_amount = NULL,
        metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object('status', 'cancelled')
      WHERE merchant_id = v_merchant_id AND metadata->>'spend_session_id' = v_spend_session_id::text;
      RETURN fn_response_error('Order failed', COALESCE(v_order->>'description', 'Event order creation failed; store credit was reversed.'), 'EVENT_ORDER_FAILED', v_order);
    END IF;

    UPDATE wallet_ledger SET metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object('purchase_id', v_order->'data'->>'id')
    WHERE merchant_id = v_merchant_id AND metadata->>'spend_session_id' = v_spend_session_id::text;

    UPDATE purchase_ledger SET wallet_ledger_code = v_code
    WHERE id = (v_order->'data'->>'id')::uuid AND merchant_id = v_merchant_id;

    RETURN fn_response_success('Event order created', 'Store credit applied and order created.', jsonb_build_object(
      'spend_session_id', v_spend_session_id,
      'store_credit_amount', v_amount,
      'wallet_ledger_id', v_burn_ledger_id,
      'code', v_code,
      'order', v_order
    ));
  END IF;

  IF v_mode = 'reverse_topup' THEN
    v_session_id := NULLIF(trim(p_data->>'topup_session_id'), '')::uuid;
    IF v_session_id IS NULL THEN
      RETURN fn_response_error('Validation error', 'topup_session_id is required.', 'VALIDATION_ERROR');
    END IF;

    SELECT wl.user_id INTO v_user_id
    FROM wallet_ledger wl
    WHERE wl.merchant_id = v_merchant_id AND wl.metadata->>'topup_session_id' = v_session_id::text
    LIMIT 1;

    IF v_user_id IS NULL THEN
      RETURN fn_response_error('Not found', 'Top-up session not found.', 'NOT_FOUND');
    END IF;

    IF EXISTS (
      SELECT 1 FROM wallet_ledger wl
      WHERE wl.merchant_id = v_merchant_id AND wl.metadata->>'topup_session_id' = v_session_id::text
        AND COALESCE(wl.metadata->>'status', '') = 'reversed'
    ) THEN
      RETURN fn_response_error('Already reversed', 'This top-up session was already reversed.', 'ALREADY_REVERSED');
    END IF;

    SELECT COALESCE(SUM(wl.amount), 0) INTO v_total_to_reverse
    FROM wallet_ledger wl
    WHERE wl.merchant_id = v_merchant_id AND wl.user_id = v_user_id AND wl.target_entity_id = v_ticket_type_id
      AND wl.transaction_type = 'earn' AND wl.metadata->>'topup_session_id' = v_session_id::text
      AND COALESCE(wl.metadata->>'operation', '') IN ('store_credit_topup', 'store_credit_topup_bonus');

    v_reversal_id := reverse_tickets(v_user_id, v_merchant_id, v_ticket_type_id, v_total_to_reverse, COALESCE(v_reason, 'Store credit top-up reversal'), v_session_id);

    UPDATE wallet_ledger SET metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object(
      'status', 'reversed', 'reversed_at', now(), 'reversal_reason', v_reason, 'reversal_wallet_ledger_id', v_reversal_id
    )
    WHERE merchant_id = v_merchant_id AND metadata->>'topup_session_id' = v_session_id::text AND transaction_type = 'earn';

    RETURN fn_response_success('Top-up reversed', 'Store credit top-up was reversed.', jsonb_build_object(
      'topup_session_id', v_session_id,
      'reversed_amount', v_total_to_reverse,
      'reversal_wallet_ledger_id', v_reversal_id
    ));
  END IF;

  IF v_mode = 'reverse_spend' THEN
    v_spend_session_id := COALESCE(
      NULLIF(trim(p_data->>'spend_session_id'), '')::uuid,
      (
        SELECT (wl.metadata->>'spend_session_id')::uuid
        FROM wallet_ledger wl
        WHERE wl.merchant_id = v_merchant_id AND wl.code = NULLIF(trim(p_data->>'code'), '')
        LIMIT 1
      )
    );
    IF v_spend_session_id IS NULL THEN
      RETURN fn_response_error('Validation error', 'spend_session_id or code is required.', 'VALIDATION_ERROR');
    END IF;

    SELECT COALESCE(SUM(wl.amount), 0), MIN(wl.user_id) INTO v_total_to_reverse, v_user_id
    FROM wallet_ledger wl
    WHERE wl.merchant_id = v_merchant_id AND wl.metadata->>'spend_session_id' = v_spend_session_id::text
      AND wl.transaction_type = 'burn' AND wl.metadata->>'operation' = 'store_credit_spend';

    IF v_total_to_reverse <= 0 OR v_user_id IS NULL THEN
      RETURN fn_response_error('Not found', 'Spend session not found.', 'NOT_FOUND');
    END IF;

    IF EXISTS (
      SELECT 1 FROM wallet_ledger wl
      WHERE wl.merchant_id = v_merchant_id AND wl.metadata->>'spend_session_id' = v_spend_session_id::text
        AND COALESCE(wl.metadata->>'status', '') = 'reversed'
        AND wl.transaction_type = 'burn'
    ) THEN
      RETURN fn_response_error('Already reversed', 'This spend session was already reversed.', 'ALREADY_REVERSED');
    END IF;

    v_reversal_id := chokepoint_post_wallet_transaction(
      v_user_id, 'ticket'::currency, 'redemption_cancellation'::wallet_transaction_source_type, 'reversal'::currency_component,
      'earn'::currency_transaction_type, v_total_to_reverse, v_spend_session_id, v_merchant_id,
      COALESCE(v_reason, 'Store credit spend reversal'),
      jsonb_build_object('operation', 'store_credit_spend_reversal', 'spend_session_id', v_spend_session_id),
      v_ticket_type_id,
      'store_credit_spend_reversal:' || v_spend_session_id::text
    );

    UPDATE wallet_ledger SET metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object(
      'status', 'reversed', 'reversed_at', now(), 'reversal_reason', v_reason, 'reversal_wallet_ledger_id', v_reversal_id
    )
    WHERE merchant_id = v_merchant_id AND metadata->>'spend_session_id' = v_spend_session_id::text AND transaction_type = 'burn';

    RETURN fn_response_success('Spend reversed', 'Store credit returned to wallet.', jsonb_build_object(
      'spend_session_id', v_spend_session_id,
      'restored_amount', v_total_to_reverse,
      'reversal_wallet_ledger_id', v_reversal_id
    ));
  END IF;

  IF v_mode = 'expiry' THEN
    IF v_user_id IS NULL THEN
      RETURN fn_response_error('Validation error', 'user_id is required.', 'VALIDATION_ERROR');
    END IF;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'wallet_ledger_id', wl.id,
      'amount', wl.amount,
      'deductible_balance', wl.deductible_balance,
      'expiry_date', wl.expiry_date,
      'expired_amount', wl.expired_amount,
      'created_at', wl.created_at
    ) ORDER BY wl.expiry_date NULLS LAST, wl.created_at), '[]'::jsonb)
    INTO v_expiry
    FROM wallet_ledger wl
    WHERE wl.merchant_id = v_merchant_id AND wl.user_id = v_user_id AND wl.target_entity_id = v_ticket_type_id
      AND wl.transaction_type = 'earn' AND wl.currency = 'ticket' AND COALESCE(wl.deductible_balance, 0) > 0;

    RETURN fn_response_success('Store credit expiry', 'Expiry rows loaded.', jsonb_build_object('items', v_expiry));
  END IF;

  IF v_mode = 'reverse_expiry' THEN
    SELECT wl.* INTO v_original FROM wallet_ledger wl
    WHERE wl.id = NULLIF(trim(p_data->>'wallet_ledger_id'), '')::uuid AND wl.merchant_id = v_merchant_id;

    IF v_original.id IS NULL THEN
      RETURN fn_response_error('Not found', 'Wallet ledger row not found.', 'NOT_FOUND');
    END IF;

    v_amount := COALESCE((p_data->>'amount')::integer, v_original.expired_amount, 0);
    IF v_amount <= 0 THEN
      RETURN fn_response_error('Validation error', 'No expired amount to restore.', 'VALIDATION_ERROR');
    END IF;

    v_reversal_id := chokepoint_post_wallet_transaction(
      v_original.user_id, 'ticket'::currency, 'manual'::wallet_transaction_source_type, 'adjustment'::currency_component,
      'earn'::currency_transaction_type, v_amount, v_original.id, v_merchant_id,
      COALESCE(v_reason, 'Restore expired store credit'),
      jsonb_build_object('operation', 'store_credit_expiry_reversal', 'restores_wallet_ledger_id', v_original.id),
      v_ticket_type_id,
      'store_credit_expiry_reversal:' || v_original.id::text
    );

    UPDATE wallet_ledger SET expired_amount = GREATEST(COALESCE(expired_amount, 0) - v_amount, 0),
      deductible_balance = LEAST(COALESCE(deductible_balance, 0) + v_amount, amount)
    WHERE id = v_original.id AND merchant_id = v_merchant_id;

    RETURN fn_response_success('Expiry reversed', 'Expired store credit restored.', jsonb_build_object(
      'wallet_ledger_id', v_original.id,
      'restored_amount', v_amount,
      'adjustment_wallet_ledger_id', v_reversal_id
    ));
  END IF;

  RETURN fn_response_error('Invalid mode', 'Supported modes: get, list_promos, preview_topup, topup, preview_spend, spend, submit_event_order, reverse_topup, reverse_spend, expiry, reverse_expiry.', 'INVALID_MODE');
EXCEPTION
  WHEN OTHERS THEN
    RETURN fn_response_error('Store credit failed', SQLERRM, 'STORE_CREDIT_FAILED');
END;
$function$;