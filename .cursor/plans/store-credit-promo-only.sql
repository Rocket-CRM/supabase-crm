CREATE OR REPLACE FUNCTION public.bff_store_credit_promo(p_mode text, p_id uuid DEFAULT NULL, p_data jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_mode text := lower(trim(COALESCE(p_mode, '')));
  v_row store_credit_promo%ROWTYPE;
  v_id uuid;
  v_items jsonb;
  v_active_only boolean := COALESCE((p_data->>'active_only')::boolean, false);
  v_event_id uuid := NULLIF(trim(p_data->>'event_id'), '')::uuid;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error('No merchant context', 'Unable to resolve merchant for this request.', 'NO_MERCHANT_CONTEXT');
  END IF;

  IF v_mode = 'list' THEN
    IF NOT (
      check_admin_permission('store_credit_promo', 'read')
      OR check_admin_permission('store_credit_promo', 'update')
      OR check_admin_permission('frontline_store_credit', 'read')
      OR check_admin_permission('frontline_store_credit', 'update')
      OR check_admin_permission('frontline_store_credit', 'create')
    ) THEN
      RETURN fn_response_error('Forbidden', 'Insufficient permission to list store credit promos.', 'FORBIDDEN');
    END IF;

    SELECT COALESCE(jsonb_agg(to_jsonb(scp) ORDER BY scp.min_topup_amount DESC), '[]'::jsonb)
    INTO v_items
    FROM store_credit_promo scp
    WHERE scp.merchant_id = v_merchant_id
      AND (NOT v_active_only OR (
        scp.is_active
        AND (scp.window_start IS NULL OR now() >= scp.window_start)
        AND (scp.window_end IS NULL OR now() <= scp.window_end)
      ))
      AND (v_event_id IS NULL OR scp.event_id IS NULL OR scp.event_id = v_event_id);

    RETURN fn_response_success('Store credit promos', 'Promo list loaded.', jsonb_build_object('items', v_items));
  END IF;

  IF v_mode = 'get' THEN
    IF NOT (
      check_admin_permission('store_credit_promo', 'read')
      OR check_admin_permission('store_credit_promo', 'update')
    ) THEN
      RETURN fn_response_error('Forbidden', 'Insufficient permission to view store credit promos.', 'FORBIDDEN');
    END IF;

    IF p_id IS NULL OR COALESCE(p_data->>'template', '') = 'new' THEN
      RETURN fn_response_success('New store credit promo', 'Empty promo template.', jsonb_build_object(
        'promo', jsonb_build_object(
          'id', NULL,
          'name', '',
          'is_active', true,
          'window_start', NULL,
          'window_end', NULL,
          'event_id', NULL,
          'min_topup_amount', NULL,
          'bonus_type', 'fixed',
          'bonus_amount', NULL,
          'bonus_percent', NULL,
          'max_bonus_amount', NULL,
          'max_bonus_per_topup', NULL
        )
      ));
    END IF;

    SELECT * INTO v_row FROM store_credit_promo WHERE id = p_id AND merchant_id = v_merchant_id;
    IF v_row.id IS NULL THEN
      RETURN fn_response_error('Not found', 'Store credit promo not found.', 'NOT_FOUND');
    END IF;

    RETURN fn_response_success('Store credit promo', 'Promo loaded.', jsonb_build_object('promo', to_jsonb(v_row)));
  END IF;

  IF v_mode = 'upsert' THEN
    IF NOT check_admin_permission('store_credit_promo', 'update') THEN
      RETURN fn_response_error('Forbidden', 'Insufficient permission to save store credit promos.', 'FORBIDDEN');
    END IF;

    v_id := COALESCE(p_id, NULLIF(trim(p_data->>'id'), '')::uuid);

    IF NULLIF(trim(p_data->>'name'), '') IS NULL THEN
      RETURN fn_response_error('Validation error', 'Name is required.', 'VALIDATION_ERROR');
    END IF;
    IF COALESCE((p_data->>'min_topup_amount')::integer, 0) <= 0 THEN
      RETURN fn_response_error('Validation error', 'min_topup_amount must be positive.', 'VALIDATION_ERROR');
    END IF;
    IF COALESCE(p_data->>'bonus_type', '') NOT IN ('fixed', 'percent') THEN
      RETURN fn_response_error('Validation error', 'bonus_type must be fixed or percent.', 'VALIDATION_ERROR');
    END IF;
    IF p_data->>'bonus_type' = 'fixed' AND COALESCE((p_data->>'bonus_amount')::integer, -1) < 0 THEN
      RETURN fn_response_error('Validation error', 'bonus_amount is required for fixed promos.', 'VALIDATION_ERROR');
    END IF;
    IF p_data->>'bonus_type' = 'percent' AND COALESCE((p_data->>'bonus_percent')::numeric, -1) < 0 THEN
      RETURN fn_response_error('Validation error', 'bonus_percent is required for percent promos.', 'VALIDATION_ERROR');
    END IF;

    IF v_id IS NULL THEN
      INSERT INTO store_credit_promo (
        merchant_id, name, is_active, window_start, window_end, event_id,
        min_topup_amount, bonus_type, bonus_amount, bonus_percent,
        max_bonus_amount, max_bonus_per_topup
      ) VALUES (
        v_merchant_id,
        trim(p_data->>'name'),
        COALESCE((p_data->>'is_active')::boolean, true),
        NULLIF(trim(p_data->>'window_start'), '')::timestamptz,
        NULLIF(trim(p_data->>'window_end'), '')::timestamptz,
        NULLIF(trim(p_data->>'event_id'), '')::uuid,
        (p_data->>'min_topup_amount')::integer,
        p_data->>'bonus_type',
        CASE WHEN p_data->>'bonus_type' = 'fixed' THEN (p_data->>'bonus_amount')::integer ELSE NULL END,
        CASE WHEN p_data->>'bonus_type' = 'percent' THEN (p_data->>'bonus_percent')::numeric ELSE NULL END,
        NULLIF(trim(p_data->>'max_bonus_amount'), '')::integer,
        NULLIF(trim(p_data->>'max_bonus_per_topup'), '')::integer
      )
      RETURNING id INTO v_id;
    ELSE
      UPDATE store_credit_promo SET
        name = trim(p_data->>'name'),
        is_active = COALESCE((p_data->>'is_active')::boolean, is_active),
        window_start = CASE WHEN p_data ? 'window_start' THEN NULLIF(trim(p_data->>'window_start'), '')::timestamptz ELSE window_start END,
        window_end = CASE WHEN p_data ? 'window_end' THEN NULLIF(trim(p_data->>'window_end'), '')::timestamptz ELSE window_end END,
        event_id = CASE WHEN p_data ? 'event_id' THEN NULLIF(trim(p_data->>'event_id'), '')::uuid ELSE event_id END,
        min_topup_amount = (p_data->>'min_topup_amount')::integer,
        bonus_type = p_data->>'bonus_type',
        bonus_amount = CASE WHEN p_data->>'bonus_type' = 'fixed' THEN (p_data->>'bonus_amount')::integer ELSE NULL END,
        bonus_percent = CASE WHEN p_data->>'bonus_type' = 'percent' THEN (p_data->>'bonus_percent')::numeric ELSE NULL END,
        max_bonus_amount = CASE WHEN p_data ? 'max_bonus_amount' THEN NULLIF(trim(p_data->>'max_bonus_amount'), '')::integer ELSE max_bonus_amount END,
        max_bonus_per_topup = CASE WHEN p_data ? 'max_bonus_per_topup' THEN NULLIF(trim(p_data->>'max_bonus_per_topup'), '')::integer ELSE max_bonus_per_topup END,
        updated_at = now()
      WHERE id = v_id AND merchant_id = v_merchant_id
      RETURNING id INTO v_id;

      IF v_id IS NULL THEN
        RETURN fn_response_error('Not found', 'Store credit promo not found.', 'NOT_FOUND');
      END IF;
    END IF;

    SELECT * INTO v_row FROM store_credit_promo WHERE id = v_id;
    RETURN fn_response_success('Store credit promo saved', 'Promo saved successfully.', jsonb_build_object('promo', to_jsonb(v_row)));
  END IF;

  IF v_mode = 'delete' THEN
    IF NOT check_admin_permission('store_credit_promo', 'update') THEN
      RETURN fn_response_error('Forbidden', 'Insufficient permission to delete store credit promos.', 'FORBIDDEN');
    END IF;

    IF p_id IS NULL THEN
      RETURN fn_response_error('Validation error', 'p_id is required for delete.', 'VALIDATION_ERROR');
    END IF;

    DELETE FROM store_credit_promo WHERE id = p_id AND merchant_id = v_merchant_id;
    IF NOT FOUND THEN
      RETURN fn_response_error('Not found', 'Store credit promo not found.', 'NOT_FOUND');
    END IF;

    RETURN fn_response_success('Store credit promo deleted', 'Promo deleted.', jsonb_build_object('id', p_id));
  END IF;

  RETURN fn_response_error('Invalid mode', 'Supported modes: list, get, upsert, delete.', 'INVALID_MODE');
EXCEPTION
  WHEN OTHERS THEN
    RETURN fn_response_error('Store credit promo failed', SQLERRM, 'STORE_CREDIT_PROMO_FAILED');
END;
$function$;