-- Direct-grant rewards (referral settle, missions, tier entry, AMP, etc.) redeem in Postgres
-- via fn_dispatch_outcome → redeem_reward_with_points(mode := direct). Mint Shopify codes
-- synchronously through shopify-issue-reward-code (parity with referral-claim + verified issue).

CREATE OR REPLACE FUNCTION public.fn_shopify_issue_reward_code_sync(
  p_merchant_id uuid,
  p_code text,
  p_redemption_id uuid,
  p_discount_id text DEFAULT NULL,
  p_reward_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $function$
DECLARE
  v_supabase_url text;
  v_service_key text;
  v_payload jsonb;
  v_res public.http_response;
  v_body jsonb;
  v_path text;
  v_external_ref text;
  v_verified boolean;
BEGIN
  IF p_merchant_id IS NULL OR NULLIF(btrim(p_code), '') IS NULL OR p_redemption_id IS NULL THEN
    RAISE EXCEPTION 'fn_shopify_issue_reward_code_sync: merchant_id, code, and redemption_id are required';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.reward_redemptions_ledger r
    WHERE r.id = p_redemption_id
      AND r.external_ref_id IS NOT NULL
  ) THEN
    RETURN jsonb_build_object('success', true, 'skipped', true, 'reason', 'already_synced');
  END IF;

  SELECT decrypted_secret INTO v_supabase_url
  FROM vault.decrypted_secrets
  WHERE name = 'supabase_url';

  SELECT decrypted_secret INTO v_service_key
  FROM vault.decrypted_secrets
  WHERE name = 'service_role_key';

  IF v_supabase_url IS NULL OR v_service_key IS NULL THEN
    RAISE EXCEPTION 'fn_shopify_issue_reward_code_sync: vault secrets supabase_url / service_role_key missing';
  END IF;

  v_payload := jsonb_strip_nulls(jsonb_build_object(
    'merchant_id', p_merchant_id,
    'code', btrim(p_code),
    'redemption_id', p_redemption_id,
    'discount_id', NULLIF(btrim(p_discount_id), ''),
    'reward_id', p_reward_id
  ));

  PERFORM public.http_set_curlopt('CURLOPT_TIMEOUT', '45');

  SELECT * INTO v_res
  FROM public.http((
    'POST',
    v_supabase_url || '/functions/v1/shopify-issue-reward-code',
    ARRAY[
      public.http_header('Content-Type', 'application/json'),
      public.http_header('Authorization', 'Bearer ' || v_service_key)
    ],
    'application/json',
    v_payload::text
  )::public.http_request);

  IF v_res.status < 200 OR v_res.status >= 300 THEN
    RAISE EXCEPTION 'Shopify issue HTTP %: %', v_res.status, left(coalesce(v_res.content, ''), 500);
  END IF;

  BEGIN
    v_body := v_res.content::jsonb;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'Shopify issue invalid JSON: %', left(coalesce(v_res.content, ''), 500);
  END;

  v_path := v_body->>'path';
  v_external_ref := COALESCE(v_body->>'redeem_code_gid', v_body->>'external_ref_id');
  v_verified :=
    coalesce((v_body->>'success')::boolean, false)
    AND coalesce(v_path, '') IS DISTINCT FROM 'graphql_no_gid'
    AND (
      NULLIF(v_external_ref, '') IS NOT NULL
      OR coalesce((v_body->>'code_verified')::boolean, false)
    );

  IF NOT v_verified THEN
    RAISE EXCEPTION 'Shopify issue not verified: %',
      COALESCE(v_body->>'error', v_body::text);
  END IF;

  IF NULLIF(v_external_ref, '') IS NOT NULL THEN
    UPDATE public.reward_redemptions_ledger
    SET external_ref_id = v_external_ref
    WHERE id = p_redemption_id
      AND external_ref_id IS NULL;
  END IF;

  RETURN v_body;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_sync_shopify_codes_for_redeem_result(
  p_merchant_id uuid,
  p_reward_id uuid,
  p_redeem_result jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $function$
DECLARE
  v_discount_id text;
  v_elem jsonb;
  v_code text;
  v_redemption_id uuid;
BEGIN
  v_discount_id := NULLIF(btrim(p_redeem_result->'data'->>'external_id_shopify'), '');
  IF v_discount_id IS NULL THEN
    RETURN;
  END IF;

  FOR v_elem IN
    SELECT elem
    FROM jsonb_array_elements(COALESCE(p_redeem_result->'data'->'redemptions', '[]'::jsonb)) AS elem
  LOOP
    v_code := NULLIF(btrim(v_elem->>'redemption_code'), '');
    v_redemption_id := NULLIF(v_elem->>'redemption_id', '')::uuid;
    IF v_code IS NULL OR v_redemption_id IS NULL THEN
      CONTINUE;
    END IF;

    PERFORM public.fn_shopify_issue_reward_code_sync(
      p_merchant_id := p_merchant_id,
      p_code := v_code,
      p_redemption_id := v_redemption_id,
      p_discount_id := v_discount_id,
      p_reward_id := p_reward_id
    );
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_backfill_shopify_redemption_codes(p_limit integer DEFAULT 50)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $function$
DECLARE
  v_row record;
  v_ok integer := 0;
  v_fail integer := 0;
  v_errors jsonb := '[]'::jsonb;
BEGIN
  FOR v_row IN
    SELECT
      rrl.id AS redemption_id,
      rrl.merchant_id,
      rrl.reward_id,
      rrl.code,
      rm.external_id_shopify AS discount_id
    FROM public.reward_redemptions_ledger rrl
    JOIN public.reward_master rm ON rm.id = rrl.reward_id
    WHERE rrl.external_ref_id IS NULL
      AND rm.external_id_shopify IS NOT NULL
      AND coalesce(rrl.success, true) = true
      AND coalesce(rrl.cancelled, false) = false
      AND NULLIF(btrim(rrl.code), '') IS NOT NULL
    ORDER BY rrl.created_at ASC
    LIMIT greatest(p_limit, 1)
  LOOP
    BEGIN
      PERFORM public.fn_shopify_issue_reward_code_sync(
        p_merchant_id := v_row.merchant_id,
        p_code := v_row.code,
        p_redemption_id := v_row.redemption_id,
        p_discount_id := v_row.discount_id,
        p_reward_id := v_row.reward_id
      );
      v_ok := v_ok + 1;
    EXCEPTION WHEN OTHERS THEN
      v_fail := v_fail + 1;
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'redemption_id', v_row.redemption_id,
        'code', v_row.code,
        'error', SQLERRM
      ));
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'success', v_fail = 0,
    'synced', v_ok,
    'failed', v_fail,
    'errors', v_errors
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_dispatch_outcome(
  p_user_id uuid,
  p_merchant_id uuid,
  p_outcome_type outcome_type_enum,
  p_entity_id uuid DEFAULT NULL::uuid,
  p_amount numeric DEFAULT NULL::numeric,
  p_source_type text DEFAULT NULL::text,
  p_source_id uuid DEFAULT NULL::uuid,
  p_metadata jsonb DEFAULT NULL::jsonb,
  p_dedup_key text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_amount           numeric;
  v_window_end       timestamptz;
  v_source_enum      wallet_transaction_source_type;
  v_ticket_type_id   uuid;
  v_description      text;
  v_meta             jsonb;
  v_ledger_id        uuid;
  v_redeem_result    jsonb;
  v_redemption_id    uuid;
  v_redemption_ids   uuid[] := ARRAY[]::uuid[];
  v_ef_user_id       uuid;
  v_distribution_id  uuid;
  v_error            text;
  v_success          boolean := true;
  v_rid              uuid;
BEGIN
  v_amount := coalesce(p_amount, CASE p_outcome_type WHEN 'reward' THEN 1 ELSE 0 END);
  v_meta   := COALESCE(p_metadata, '{}'::jsonb);
  v_description := COALESCE(v_meta->>'description',
                            'Outcome from ' || COALESCE(p_source_type, 'system'));
  v_source_enum := COALESCE(p_source_type, 'campaign')::wallet_transaction_source_type;

  <<dispatch>>
  BEGIN
    CASE p_outcome_type

      WHEN 'points' THEN
        IF v_amount <= 0 THEN
          RAISE EXCEPTION 'Amount must be > 0 for points outcome';
        END IF;
        v_ledger_id := chokepoint_post_wallet_transaction(
          p_user_id,
          'points'::currency,
          v_source_enum,
          'base'::currency_component,
          'earn'::currency_transaction_type,
          v_amount::integer,
          COALESCE(p_source_id, p_user_id),
          p_merchant_id,
          v_description,
          v_meta || jsonb_build_object('source', p_source_type, 'dedup_key', p_dedup_key),
          NULL::uuid,
          p_dedup_key
        );

      WHEN 'tickets' THEN
        IF v_amount <= 0 THEN
          RAISE EXCEPTION 'Amount must be > 0 for tickets outcome';
        END IF;
        v_ticket_type_id := p_entity_id;
        IF v_ticket_type_id IS NULL THEN
          RAISE EXCEPTION 'ticket_type_id (p_entity_id) is required for tickets outcome';
        END IF;
        IF NOT EXISTS (
          SELECT 1 FROM ticket_type tt
          WHERE tt.id = v_ticket_type_id
            AND tt.merchant_id = p_merchant_id
            AND tt.active IS TRUE
        ) THEN
          RAISE EXCEPTION 'ticket_type_id % not found or inactive for merchant %',
                          v_ticket_type_id, p_merchant_id;
        END IF;
        v_ledger_id := chokepoint_post_wallet_transaction(
          p_user_id,
          'ticket'::currency,
          v_source_enum,
          'base'::currency_component,
          'earn'::currency_transaction_type,
          v_amount::integer,
          COALESCE(p_source_id, p_user_id),
          p_merchant_id,
          v_description,
          v_meta || jsonb_build_object('source', p_source_type, 'dedup_key', p_dedup_key),
          v_ticket_type_id,
          p_dedup_key
        );

      WHEN 'reward' THEN
        IF p_entity_id IS NULL THEN
          RAISE EXCEPTION 'reward_id (p_entity_id) is required for reward outcome';
        END IF;
        IF v_amount <= 0 THEN
          RAISE EXCEPTION 'quantity must be > 0 for reward outcome';
        END IF;
        SELECT redeem_reward_with_points(
                 p_reward_id    := p_entity_id,
                 p_quantity     := v_amount::integer,
                 p_user_id      := p_user_id,
                 p_merchant_id  := p_merchant_id,
                 p_mode         := 'direct',
                 p_source_type  := p_source_type,
                 p_source_id    := p_source_id
               ) INTO v_redeem_result;
        IF NOT coalesce((v_redeem_result->>'success')::boolean, false) THEN
          RAISE EXCEPTION 'redeem_reward_with_points failed: %',
                          COALESCE(v_redeem_result->>'error', v_redeem_result::text);
        END IF;
        FOR v_rid IN
          SELECT (elem->>'redemption_id')::uuid
          FROM jsonb_array_elements(COALESCE(v_redeem_result->'data'->'redemptions', '[]'::jsonb)) AS elem
          WHERE NULLIF(elem->>'redemption_id', '') IS NOT NULL
        LOOP
          v_redemption_ids := array_append(v_redemption_ids, v_rid);
        END LOOP;
        IF cardinality(v_redemption_ids) > 0 THEN
          v_redemption_id := v_redemption_ids[1];
        END IF;

        IF NULLIF(btrim(v_redeem_result->'data'->>'external_id_shopify'), '') IS NOT NULL THEN
          PERFORM public.fn_sync_shopify_codes_for_redeem_result(
            p_merchant_id,
            p_entity_id,
            v_redeem_result
          );
        END IF;

      WHEN 'earn_factor' THEN
        IF p_entity_id IS NULL THEN
          RAISE EXCEPTION 'earn_factor_id (p_entity_id) is required for earn_factor outcome';
        END IF;
        v_window_end := now() + (COALESCE(NULLIF(v_meta->>'window_days',''), '30') || ' days')::interval;
        INSERT INTO earn_factor_user
          (earn_factor_id, user_id, merchant_id, window_end, source_type, source_id)
        VALUES
          (p_entity_id, p_user_id, p_merchant_id, v_window_end, p_source_type, p_source_id)
        RETURNING id INTO v_ef_user_id;

      ELSE
        RAISE EXCEPTION 'Unknown outcome_type: %', p_outcome_type;
    END CASE;
  EXCEPTION WHEN OTHERS THEN
    v_success := false;
    v_error   := SQLERRM;
  END;

  INSERT INTO outcome_distribution_log
    (user_id, merchant_id, source_type, source_id, outcome_type, entity_id, amount,
     wallet_ledger_id, redemption_id, earn_factor_user_id, success, error_message,
     distribution_metadata)
  VALUES
    (p_user_id, p_merchant_id, COALESCE(p_source_type,'system'), p_source_id, p_outcome_type,
     p_entity_id, v_amount, v_ledger_id, v_redemption_id, v_ef_user_id, v_success, v_error,
     v_meta)
  RETURNING id INTO v_distribution_id;

  RETURN jsonb_build_object(
    'success',          v_success,
    'outcome_type',     p_outcome_type,
    'transaction_id',   COALESCE(v_ledger_id, v_redemption_id),
    'wallet_ledger_id', v_ledger_id,
    'redemption_id',    v_redemption_id,
    'redemption_ids',   to_jsonb(v_redemption_ids),
    'earn_factor_user_id', v_ef_user_id,
    'distribution_id',  v_distribution_id,
    'error',            v_error
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_shopify_issue_reward_code_sync(uuid, text, uuid, text, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_sync_shopify_codes_for_redeem_result(uuid, uuid, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_backfill_shopify_redemption_codes(integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_shopify_issue_reward_code_sync(uuid, text, uuid, text, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_sync_shopify_codes_for_redeem_result(uuid, uuid, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_backfill_shopify_redemption_codes(integer) TO service_role;
