-- Open API wallet: extend points-only RPCs to ticket currency.
-- DROP + CREATE because new default args would otherwise create an ambiguous overload.

DROP FUNCTION IF EXISTS public.api_post_wallet_transaction(uuid, text, integer, text, uuid, text, text, text, text, text, jsonb);
DROP FUNCTION IF EXISTS public.api_get_wallet_transactions(uuid, uuid, text, text, text, text, timestamp with time zone, timestamp with time zone, text, integer, integer);

CREATE OR REPLACE FUNCTION public.api_post_wallet_transaction(
  p_merchant_id uuid,
  p_transaction_type text,
  p_amount integer,
  p_dedup_key text,
  p_user_id uuid DEFAULT NULL::uuid,
  p_external_user_id text DEFAULT NULL::text,
  p_tel text DEFAULT NULL::text,
  p_email text DEFAULT NULL::text,
  p_line_id text DEFAULT NULL::text,
  p_description text DEFAULT NULL::text,
  p_metadata jsonb DEFAULT NULL::jsonb,
  p_currency text DEFAULT 'points'::text,
  p_ticket_type_id uuid DEFAULT NULL::uuid,
  p_ticket_code text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_id_count integer;
  v_user_id uuid;
  v_txn_type currency_transaction_type;
  v_client_key text;
  v_internal_key text;
  v_like_pattern text;
  v_existing wallet_ledger%ROWTYPE;
  v_first wallet_ledger%ROWTYPE;
  v_last wallet_ledger%ROWTYPE;
  v_partner_meta jsonb;
  v_meta jsonb;
  v_ledger_id uuid;
  v_row wallet_ledger%ROWTYPE;
  v_points_balance integer;
  v_ticket_balance integer;
  v_err text;
  v_currency currency;
  v_currency_text text;
  v_ticket_id_set boolean;
  v_ticket_code_set boolean;
  v_ticket_type_id uuid;
  v_ticket_code text;
  v_ticket_active boolean;
  v_ticket_is_credit boolean;
  v_ticket_valid_from timestamptz;
  v_ticket_valid_until timestamptz;
  v_family_count integer;
  v_payload_match boolean;
BEGIN
  IF p_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'merchant_id is required', 'code', 'VALIDATION_FAILED');
  END IF;

  v_id_count :=
    (CASE WHEN p_user_id IS NOT NULL THEN 1 ELSE 0 END)
    + (CASE WHEN p_external_user_id IS NOT NULL AND btrim(p_external_user_id) <> '' THEN 1 ELSE 0 END)
    + (CASE WHEN p_tel IS NOT NULL AND btrim(p_tel) <> '' THEN 1 ELSE 0 END)
    + (CASE WHEN p_email IS NOT NULL AND btrim(p_email) <> '' THEN 1 ELSE 0 END)
    + (CASE WHEN p_line_id IS NOT NULL AND btrim(p_line_id) <> '' THEN 1 ELSE 0 END);

  IF v_id_count = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Exactly one user identifier is required', 'code', 'MISSING_IDENTIFIER');
  END IF;
  IF v_id_count > 1 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Provide exactly one user identifier', 'code', 'MULTIPLE_IDENTIFIERS');
  END IF;

  IF p_transaction_type IS NULL OR lower(btrim(p_transaction_type)) NOT IN ('earn', 'burn') THEN
    RETURN jsonb_build_object('success', false, 'error', 'transaction_type must be earn or burn', 'code', 'INVALID_TRANSACTION_TYPE');
  END IF;
  v_txn_type := lower(btrim(p_transaction_type))::currency_transaction_type;

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'amount must be a positive integer', 'code', 'INVALID_AMOUNT');
  END IF;

  IF p_dedup_key IS NULL OR char_length(btrim(p_dedup_key)) < 1 OR char_length(p_dedup_key) > 200 THEN
    RETURN jsonb_build_object('success', false, 'error', 'dedup_key must be 1-200 characters', 'code', 'INVALID_DEDUP_KEY');
  END IF;
  v_client_key := btrim(p_dedup_key);

  v_currency_text := lower(btrim(COALESCE(p_currency, 'points')));
  IF v_currency_text NOT IN ('points', 'ticket') THEN
    RETURN jsonb_build_object('success', false, 'error', 'currency must be points or ticket', 'code', 'INVALID_CURRENCY');
  END IF;
  v_currency := v_currency_text::currency;

  v_ticket_id_set := p_ticket_type_id IS NOT NULL;
  v_ticket_code_set := p_ticket_code IS NOT NULL AND btrim(p_ticket_code) <> '';

  IF v_currency = 'points'::currency THEN
    IF v_ticket_id_set OR v_ticket_code_set THEN
      RETURN jsonb_build_object('success', false, 'error', 'ticket_type_id and ticket_code must be omitted for points', 'code', 'VALIDATION_FAILED');
    END IF;
  ELSE
    IF v_ticket_id_set AND v_ticket_code_set THEN
      RETURN jsonb_build_object('success', false, 'error', 'Provide exactly one of ticket_type_id or ticket_code', 'code', 'MULTIPLE_TICKET_IDENTIFIERS');
    END IF;
    IF NOT v_ticket_id_set AND NOT v_ticket_code_set THEN
      RETURN jsonb_build_object('success', false, 'error', 'ticket_type_id or ticket_code is required for ticket currency', 'code', 'TICKET_TYPE_REQUIRED');
    END IF;

    SELECT tt.id, tt.ticket_code, tt.active, tt.is_credit, tt.valid_from, tt.valid_until
    INTO v_ticket_type_id, v_ticket_code, v_ticket_active, v_ticket_is_credit, v_ticket_valid_from, v_ticket_valid_until
    FROM ticket_type tt
    WHERE tt.merchant_id = p_merchant_id
      AND (
        (v_ticket_id_set AND tt.id = p_ticket_type_id)
        OR (v_ticket_code_set AND tt.ticket_code = btrim(p_ticket_code))
      )
    LIMIT 1;

    IF v_ticket_type_id IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'Ticket type not found', 'code', 'TICKET_TYPE_NOT_FOUND');
    END IF;
    IF COALESCE(v_ticket_is_credit, false) THEN
      RETURN jsonb_build_object('success', false, 'error', 'Credit ticket types cannot be posted via Open API', 'code', 'TICKET_TYPE_CREDIT_FORBIDDEN');
    END IF;
    IF NOT COALESCE(v_ticket_active, false) THEN
      RETURN jsonb_build_object('success', false, 'error', 'Ticket type is not available', 'code', 'TICKET_TYPE_NOT_AVAILABLE');
    END IF;
    IF v_txn_type = 'earn'::currency_transaction_type THEN
      IF (v_ticket_valid_from IS NOT NULL AND v_ticket_valid_from > now())
         OR (v_ticket_valid_until IS NOT NULL AND v_ticket_valid_until < now()) THEN
        RETURN jsonb_build_object('success', false, 'error', 'Ticket type is not available', 'code', 'TICKET_TYPE_NOT_AVAILABLE');
      END IF;
    END IF;
  END IF;

  IF p_metadata IS NOT NULL THEN
    IF jsonb_typeof(p_metadata) <> 'object' THEN
      RETURN jsonb_build_object('success', false, 'error', 'metadata must be a JSON object', 'code', 'VALIDATION_FAILED');
    END IF;
    IF EXISTS (
      SELECT 1 FROM jsonb_object_keys(p_metadata) k WHERE k LIKE '\_%' ESCAPE '\'
    ) THEN
      RETURN jsonb_build_object('success', false, 'error', 'metadata keys beginning with _ are reserved', 'code', 'RESERVED_METADATA_KEY');
    END IF;
    v_partner_meta := p_metadata;
  ELSE
    v_partner_meta := '{}'::jsonb;
  END IF;

  v_user_id := api_find_user(
    p_merchant_id,
    p_user_id,
    NULLIF(btrim(p_external_user_id), ''),
    NULLIF(btrim(p_email), ''),
    NULLIF(btrim(p_tel), ''),
    NULLIF(btrim(p_line_id), '')
  );
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'User not found', 'code', 'USER_NOT_FOUND');
  END IF;

  v_internal_key := 'openapi:' || p_merchant_id::text || ':' || v_client_key;
  v_like_pattern :=
    replace(replace(replace(v_internal_key, '\', '\\'), '%', '\%'), '_', '\_') || ':u%';

  IF v_currency = 'points'::currency THEN
    SELECT * INTO v_existing
    FROM wallet_ledger
    WHERE merchant_id = p_merchant_id
      AND dedup_key = v_internal_key
    LIMIT 1;
    v_family_count := CASE WHEN FOUND THEN 1 ELSE 0 END;
    IF FOUND THEN
      v_first := v_existing;
      v_last := v_existing;
    END IF;
  ELSE
    SELECT count(*) INTO v_family_count
    FROM wallet_ledger
    WHERE merchant_id = p_merchant_id
      AND (dedup_key = v_internal_key OR dedup_key LIKE v_like_pattern ESCAPE '\');

    IF v_family_count > 0 THEN
      SELECT * INTO v_first
      FROM wallet_ledger
      WHERE merchant_id = p_merchant_id
        AND (dedup_key = v_internal_key OR dedup_key LIKE v_like_pattern ESCAPE '\')
      ORDER BY created_at ASC, id ASC
      LIMIT 1;

      SELECT * INTO v_last
      FROM wallet_ledger
      WHERE merchant_id = p_merchant_id
        AND (dedup_key = v_internal_key OR dedup_key LIKE v_like_pattern ESCAPE '\')
      ORDER BY created_at DESC, id DESC
      LIMIT 1;

      v_existing := v_first;
    END IF;
  END IF;

  IF v_family_count > 0 THEN
    IF v_currency = 'points'::currency THEN
      v_payload_match :=
        v_existing.user_id = v_user_id
        AND v_existing.transaction_type = v_txn_type
        AND v_existing.currency = 'points'::currency
        AND v_existing.amount = p_amount;
    ELSE
      v_payload_match :=
        v_existing.user_id = v_user_id
        AND v_existing.transaction_type = v_txn_type
        AND v_existing.currency = 'ticket'::currency
        AND v_existing.target_entity_id IS NOT DISTINCT FROM v_ticket_type_id
        AND v_family_count = p_amount;
    END IF;

    IF v_payload_match THEN
      IF v_currency = 'points'::currency THEN
        SELECT points_balance INTO v_points_balance
        FROM user_wallet
        WHERE user_id = v_user_id AND merchant_id = p_merchant_id;

        RETURN jsonb_build_object(
          'success', true,
          'already_processed', true,
          'wallet_ledger_id', v_existing.id,
          'user_id', v_user_id,
          'transaction_type', v_existing.transaction_type::text,
          'amount', v_existing.amount,
          'currency', 'points',
          'balance_after', v_existing.balance_after,
          'points_balance', COALESCE(v_points_balance, 0),
          'dedup_key', v_client_key,
          'created_at', v_existing.created_at
        );
      END IF;

      SELECT COALESCE(balance, 0) INTO v_ticket_balance
      FROM user_ticket_balances
      WHERE user_id = v_user_id
        AND merchant_id = p_merchant_id
        AND ticket_type_id = v_ticket_type_id;

      RETURN jsonb_build_object(
        'success', true,
        'already_processed', true,
        'wallet_ledger_id', v_first.id,
        'user_id', v_user_id,
        'transaction_type', v_first.transaction_type::text,
        'amount', p_amount,
        'currency', 'ticket',
        'ticket_type_id', v_ticket_type_id,
        'ticket_code', v_ticket_code,
        'balance_after', v_last.balance_after,
        'ticket_balance', COALESCE(v_ticket_balance, 0),
        'dedup_key', v_client_key,
        'created_at', v_first.created_at
      );
    END IF;

    RETURN jsonb_build_object(
      'success', false,
      'error', 'Idempotency key already used with a different payload',
      'code', 'IDEMPOTENCY_CONFLICT',
      'dedup_key', v_client_key
    );
  END IF;

  v_meta := jsonb_build_object(
    'channel', 'openapi',
    'client_dedup_key', v_client_key,
    'partner', v_partner_meta
  );

  BEGIN
    v_ledger_id := chokepoint_post_wallet_transaction(
      p_user_id := v_user_id,
      p_currency := v_currency,
      p_source_type := 'manual'::wallet_transaction_source_type,
      p_component := 'adjustment'::currency_component,
      p_transaction_type := v_txn_type,
      p_amount := p_amount,
      p_transaction_id := gen_random_uuid(),
      p_merchant_id := p_merchant_id,
      p_description := p_description,
      p_metadata := v_meta,
      p_target_entity_id := v_ticket_type_id,
      p_dedup_key := v_internal_key
    );
  EXCEPTION
    WHEN unique_violation THEN
      IF v_currency = 'points'::currency THEN
        SELECT * INTO v_existing
        FROM wallet_ledger
        WHERE merchant_id = p_merchant_id
          AND dedup_key = v_internal_key
        LIMIT 1;
        v_family_count := CASE WHEN FOUND THEN 1 ELSE 0 END;
        v_first := v_existing;
        v_last := v_existing;
      ELSE
        SELECT count(*) INTO v_family_count
        FROM wallet_ledger
        WHERE merchant_id = p_merchant_id
          AND (dedup_key = v_internal_key OR dedup_key LIKE v_like_pattern ESCAPE '\');

        IF v_family_count > 0 THEN
          SELECT * INTO v_first
          FROM wallet_ledger
          WHERE merchant_id = p_merchant_id
            AND (dedup_key = v_internal_key OR dedup_key LIKE v_like_pattern ESCAPE '\')
          ORDER BY created_at ASC, id ASC
          LIMIT 1;

          SELECT * INTO v_last
          FROM wallet_ledger
          WHERE merchant_id = p_merchant_id
            AND (dedup_key = v_internal_key OR dedup_key LIKE v_like_pattern ESCAPE '\')
          ORDER BY created_at DESC, id DESC
          LIMIT 1;

          v_existing := v_first;
        END IF;
      END IF;

      IF v_family_count = 0 THEN
        RETURN jsonb_build_object('success', false, 'error', 'Concurrent dedup conflict could not be resolved', 'code', 'IDEMPOTENCY_CONFLICT');
      END IF;

      IF v_currency = 'points'::currency THEN
        v_payload_match :=
          v_existing.user_id = v_user_id
          AND v_existing.transaction_type = v_txn_type
          AND v_existing.currency = 'points'::currency
          AND v_existing.amount = p_amount;
      ELSE
        v_payload_match :=
          v_existing.user_id = v_user_id
          AND v_existing.transaction_type = v_txn_type
          AND v_existing.currency = 'ticket'::currency
          AND v_existing.target_entity_id IS NOT DISTINCT FROM v_ticket_type_id
          AND v_family_count = p_amount;
      END IF;

      IF v_payload_match THEN
        IF v_currency = 'points'::currency THEN
          SELECT points_balance INTO v_points_balance
          FROM user_wallet
          WHERE user_id = v_user_id AND merchant_id = p_merchant_id;

          RETURN jsonb_build_object(
            'success', true,
            'already_processed', true,
            'wallet_ledger_id', v_existing.id,
            'user_id', v_user_id,
            'transaction_type', v_existing.transaction_type::text,
            'amount', v_existing.amount,
            'currency', 'points',
            'balance_after', v_existing.balance_after,
            'points_balance', COALESCE(v_points_balance, 0),
            'dedup_key', v_client_key,
            'created_at', v_existing.created_at
          );
        END IF;

        SELECT COALESCE(balance, 0) INTO v_ticket_balance
        FROM user_ticket_balances
        WHERE user_id = v_user_id
          AND merchant_id = p_merchant_id
          AND ticket_type_id = v_ticket_type_id;

        RETURN jsonb_build_object(
          'success', true,
          'already_processed', true,
          'wallet_ledger_id', v_first.id,
          'user_id', v_user_id,
          'transaction_type', v_first.transaction_type::text,
          'amount', p_amount,
          'currency', 'ticket',
          'ticket_type_id', v_ticket_type_id,
          'ticket_code', v_ticket_code,
          'balance_after', v_last.balance_after,
          'ticket_balance', COALESCE(v_ticket_balance, 0),
          'dedup_key', v_client_key,
          'created_at', v_first.created_at
        );
      END IF;

      RETURN jsonb_build_object(
        'success', false,
        'error', 'Idempotency key already used with a different payload',
        'code', 'IDEMPOTENCY_CONFLICT',
        'dedup_key', v_client_key
      );
    WHEN OTHERS THEN
      v_err := SQLERRM;
      IF v_err LIKE 'Insufficient points balance%'
         OR v_err LIKE 'Insufficient ticket balance%' THEN
        RETURN jsonb_build_object(
          'success', false,
          'error', v_err,
          'code', 'INSUFFICIENT_BALANCE'
        );
      END IF;
      IF v_err LIKE 'Insufficient ticket codes in pool%' THEN
        RETURN jsonb_build_object(
          'success', false,
          'error', v_err,
          'code', 'INSUFFICIENT_TICKET_POOL'
        );
      END IF;
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Wallet transaction failed',
        'code', 'WALLET_OPERATION_FAILED',
        'details', v_err
      );
  END;

  SELECT * INTO v_row FROM wallet_ledger WHERE id = v_ledger_id;

  IF v_currency = 'points'::currency THEN
    SELECT points_balance INTO v_points_balance
    FROM user_wallet
    WHERE user_id = v_user_id AND merchant_id = p_merchant_id;

    RETURN jsonb_build_object(
      'success', true,
      'already_processed', false,
      'wallet_ledger_id', v_ledger_id,
      'user_id', v_user_id,
      'transaction_type', v_row.transaction_type::text,
      'amount', v_row.amount,
      'currency', 'points',
      'balance_after', v_row.balance_after,
      'points_balance', COALESCE(v_points_balance, 0),
      'dedup_key', v_client_key,
      'created_at', v_row.created_at
    );
  END IF;

  SELECT COALESCE(balance, 0) INTO v_ticket_balance
  FROM user_ticket_balances
  WHERE user_id = v_user_id
    AND merchant_id = p_merchant_id
    AND ticket_type_id = v_ticket_type_id;

  RETURN jsonb_build_object(
    'success', true,
    'already_processed', false,
    'wallet_ledger_id', v_ledger_id,
    'user_id', v_user_id,
    'transaction_type', v_row.transaction_type::text,
    'amount', p_amount,
    'currency', 'ticket',
    'ticket_type_id', v_ticket_type_id,
    'ticket_code', v_ticket_code,
    'balance_after', COALESCE(v_ticket_balance, 0),
    'ticket_balance', COALESCE(v_ticket_balance, 0),
    'dedup_key', v_client_key,
    'created_at', v_row.created_at
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.api_get_wallet_transactions(
  p_merchant_id uuid,
  p_user_id uuid DEFAULT NULL::uuid,
  p_external_user_id text DEFAULT NULL::text,
  p_tel text DEFAULT NULL::text,
  p_email text DEFAULT NULL::text,
  p_line_id text DEFAULT NULL::text,
  p_from timestamp with time zone DEFAULT NULL::timestamp with time zone,
  p_to timestamp with time zone DEFAULT NULL::timestamp with time zone,
  p_transaction_type text DEFAULT NULL::text,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0,
  p_currency text DEFAULT 'points'::text,
  p_ticket_type_id uuid DEFAULT NULL::uuid,
  p_ticket_code text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_id_count integer;
  v_user_id uuid;
  v_limit integer;
  v_offset integer;
  v_txn_type currency_transaction_type;
  v_total bigint;
  v_rows jsonb;
  v_currency currency;
  v_currency_text text;
  v_ticket_id_set boolean;
  v_ticket_code_set boolean;
  v_ticket_type_id uuid;
BEGIN
  IF p_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'merchant_id is required', 'code', 'VALIDATION_FAILED');
  END IF;

  v_id_count :=
    (CASE WHEN p_user_id IS NOT NULL THEN 1 ELSE 0 END)
    + (CASE WHEN p_external_user_id IS NOT NULL AND btrim(p_external_user_id) <> '' THEN 1 ELSE 0 END)
    + (CASE WHEN p_tel IS NOT NULL AND btrim(p_tel) <> '' THEN 1 ELSE 0 END)
    + (CASE WHEN p_email IS NOT NULL AND btrim(p_email) <> '' THEN 1 ELSE 0 END)
    + (CASE WHEN p_line_id IS NOT NULL AND btrim(p_line_id) <> '' THEN 1 ELSE 0 END);

  IF v_id_count = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Exactly one user identifier is required', 'code', 'MISSING_IDENTIFIER');
  END IF;
  IF v_id_count > 1 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Provide exactly one user identifier', 'code', 'MULTIPLE_IDENTIFIERS');
  END IF;

  v_limit := COALESCE(p_limit, 50);
  v_offset := COALESCE(p_offset, 0);
  IF v_limit < 1 OR v_limit > 100 THEN
    RETURN jsonb_build_object('success', false, 'error', 'limit must be between 1 and 100', 'code', 'VALIDATION_FAILED');
  END IF;
  IF v_offset < 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'offset must be >= 0', 'code', 'VALIDATION_FAILED');
  END IF;

  IF p_from IS NOT NULL AND p_to IS NOT NULL AND NOT (p_from < p_to) THEN
    RETURN jsonb_build_object('success', false, 'error', 'from must be earlier than to', 'code', 'VALIDATION_FAILED');
  END IF;

  IF p_transaction_type IS NOT NULL AND btrim(p_transaction_type) <> '' THEN
    IF lower(btrim(p_transaction_type)) NOT IN ('earn', 'burn') THEN
      RETURN jsonb_build_object('success', false, 'error', 'transaction_type must be earn or burn', 'code', 'INVALID_TRANSACTION_TYPE');
    END IF;
    v_txn_type := lower(btrim(p_transaction_type))::currency_transaction_type;
  END IF;

  v_currency_text := lower(btrim(COALESCE(NULLIF(p_currency, ''), 'points')));
  IF v_currency_text NOT IN ('points', 'ticket') THEN
    RETURN jsonb_build_object('success', false, 'error', 'currency must be points or ticket', 'code', 'INVALID_CURRENCY');
  END IF;
  v_currency := v_currency_text::currency;

  v_ticket_id_set := p_ticket_type_id IS NOT NULL;
  v_ticket_code_set := p_ticket_code IS NOT NULL AND btrim(p_ticket_code) <> '';

  IF v_currency = 'points'::currency THEN
    IF v_ticket_id_set OR v_ticket_code_set THEN
      RETURN jsonb_build_object('success', false, 'error', 'ticket_type_id and ticket_code apply only when currency=ticket', 'code', 'VALIDATION_FAILED');
    END IF;
  ELSIF v_ticket_id_set OR v_ticket_code_set THEN
    IF v_ticket_id_set AND v_ticket_code_set THEN
      RETURN jsonb_build_object('success', false, 'error', 'Provide exactly one of ticket_type_id or ticket_code', 'code', 'MULTIPLE_TICKET_IDENTIFIERS');
    END IF;

    SELECT tt.id INTO v_ticket_type_id
    FROM ticket_type tt
    WHERE tt.merchant_id = p_merchant_id
      AND (
        (v_ticket_id_set AND tt.id = p_ticket_type_id)
        OR (v_ticket_code_set AND tt.ticket_code = btrim(p_ticket_code))
      )
    LIMIT 1;

    IF v_ticket_type_id IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'Ticket type not found', 'code', 'TICKET_TYPE_NOT_FOUND');
    END IF;
  END IF;

  v_user_id := api_find_user(
    p_merchant_id,
    p_user_id,
    NULLIF(btrim(p_external_user_id), ''),
    NULLIF(btrim(p_email), ''),
    NULLIF(btrim(p_tel), ''),
    NULLIF(btrim(p_line_id), '')
  );
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'User not found', 'code', 'USER_NOT_FOUND');
  END IF;

  SELECT count(*) INTO v_total
  FROM wallet_ledger wl
  WHERE wl.merchant_id = p_merchant_id
    AND wl.user_id = v_user_id
    AND wl.currency = v_currency
    AND (p_from IS NULL OR wl.created_at >= p_from)
    AND (p_to IS NULL OR wl.created_at < p_to)
    AND (v_txn_type IS NULL OR wl.transaction_type = v_txn_type)
    AND (v_ticket_type_id IS NULL OR wl.target_entity_id = v_ticket_type_id);

  SELECT COALESCE(jsonb_agg(row_to_json(t)::jsonb ORDER BY t.created_at DESC, t.id DESC), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT
      wl.id,
      wl.created_at,
      wl.currency::text AS currency,
      wl.transaction_type::text AS transaction_type,
      wl.component::text AS component,
      wl.amount,
      wl.signed_amount,
      wl.source_type::text AS source_type,
      wl.description,
      wl.balance_before,
      wl.balance_after,
      wl.expiry_date,
      COALESCE(wl.metadata->>'client_dedup_key', NULL) AS dedup_key,
      CASE WHEN v_currency = 'ticket'::currency THEN wl.target_entity_id ELSE NULL END AS target_entity_id,
      CASE WHEN v_currency = 'ticket'::currency THEN tt.ticket_code ELSE NULL END AS ticket_code,
      CASE WHEN v_currency = 'ticket'::currency THEN tt.name ELSE NULL END AS ticket_name
    FROM wallet_ledger wl
    LEFT JOIN ticket_type tt
      ON tt.id = wl.target_entity_id
     AND tt.merchant_id = wl.merchant_id
    WHERE wl.merchant_id = p_merchant_id
      AND wl.user_id = v_user_id
      AND wl.currency = v_currency
      AND (p_from IS NULL OR wl.created_at >= p_from)
      AND (p_to IS NULL OR wl.created_at < p_to)
      AND (v_txn_type IS NULL OR wl.transaction_type = v_txn_type)
      AND (v_ticket_type_id IS NULL OR wl.target_entity_id = v_ticket_type_id)
    ORDER BY wl.created_at DESC, wl.id DESC
    LIMIT v_limit
    OFFSET v_offset
  ) t;

  RETURN jsonb_build_object(
    'success', true,
    'user_id', v_user_id,
    'total_count', v_total,
    'limit', v_limit,
    'offset', v_offset,
    'transactions', v_rows
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.api_get_user(
  p_merchant_id uuid,
  p_user_id uuid DEFAULT NULL::uuid,
  p_external_user_id text DEFAULT NULL::text,
  p_email text DEFAULT NULL::text,
  p_tel text DEFAULT NULL::text,
  p_line_id text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_user_id UUID;
    v_user RECORD;
    v_addresses JSONB;
    v_latest_profile JSONB;
    v_points_balance NUMERIC;
    v_ticket_balances JSONB;
BEGIN
    v_user_id := api_find_user(
        p_merchant_id => p_merchant_id,
        p_user_id => p_user_id,
        p_external_user_id => p_external_user_id,
        p_email => p_email,
        p_tel => p_tel,
        p_line_id => p_line_id
    );

    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'User not found', 'code', 'USER_NOT_FOUND');
    END IF;

    SELECT * INTO v_user FROM user_accounts WHERE id = v_user_id;

    SELECT COALESCE(points_balance, 0) INTO v_points_balance
    FROM user_wallet
    WHERE user_id = v_user_id AND merchant_id = p_merchant_id;

    IF v_points_balance IS NULL THEN
        v_points_balance := 0;
    END IF;

    SELECT COALESCE(jsonb_agg(
      jsonb_build_object(
        'ticket_type_id', s.entity_id,
        'ticket_code', s.entity_code,
        'name', s.entity_name,
        'balance', s.balance
      )
      ORDER BY s.entity_name
    ), '[]'::jsonb)
    INTO v_ticket_balances
    FROM get_user_wallet_summary(v_user_id, p_merchant_id) s
    WHERE s.currency_type = 'ticket';

    SELECT jsonb_agg(jsonb_build_object(
        'address_line_1', addressline_1, 'address_line_2', addressline_2,
        'state', state, 'city', city, 'district', district,
        'subdistrict', subdistrict, 'postcode', postcode
    )) INTO v_addresses
    FROM user_address WHERE user_id = v_user_id AND merchant_id = p_merchant_id;

    SELECT jsonb_object_agg(ff.field_key, COALESCE(fr.text_value, fr.array_value::text)) INTO v_latest_profile
    FROM (
        SELECT id, form_id, submitted_at FROM form_submissions
        WHERE user_id = v_user_id AND merchant_id = p_merchant_id
        ORDER BY submitted_at DESC LIMIT 1
    ) fs
    JOIN form_responses fr ON fr.submission_id = fs.id
    JOIN form_fields ff ON fr.field_id = ff.id;

    RETURN jsonb_build_object(
        'success', true,
        'user', jsonb_build_object(
            'user_id', v_user.id, 'external_user_id', v_user.external_user_id,
            'fullname', v_user.fullname, 'firstname', v_user.firstname, 'lastname', v_user.lastname,
            'email', v_user.email, 'tel', v_user.tel,
            'line_id', v_user.line_id, 'id_card', v_user.id_card, 'birth_date', v_user.birth_date,
            'user_type', v_user.user_type, 'user_stage', v_user.user_stage,
            'tier_id', v_user.tier_id, 'persona_id', v_user.persona_id,
            'points_balance', v_points_balance,
            'ticket_balances', COALESCE(v_ticket_balances, '[]'::jsonb),
            'channel_email', v_user.channel_email,
            'channel_sms', v_user.channel_sms, 'channel_line', v_user.channel_line,
            'channel_push', v_user.channel_push, 'created_at', v_user.created_at,
            'addresses', COALESCE(v_addresses, '[]'::jsonb),
            'custom_fields', COALESCE(v_latest_profile, '{}'::jsonb)
        )
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', 'Failed to retrieve user', 'code', 'USER_FETCH_FAILED', 'details', SQLERRM);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.api_post_wallet_transaction(uuid, text, integer, text, uuid, text, text, text, text, text, jsonb, text, uuid, text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.api_get_wallet_transactions(uuid, uuid, text, text, text, text, timestamp with time zone, timestamp with time zone, text, integer, integer, text, uuid, text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.api_get_user(uuid, uuid, text, text, text, text) TO anon, authenticated, service_role;
