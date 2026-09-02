-- Moderately aggressive catch-up: 6 x 500 users per 5-minute tick (~3k / tick).

CREATE OR REPLACE FUNCTION public.fn_loyalty_cache_catchup_ticks(
  p_merchant_id uuid,
  p_max_chunks integer DEFAULT 6,
  p_as_of_date date DEFAULT (timezone('Asia/Bangkok'::text, now()))::date,
  p_batch_size integer DEFAULT 500
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_catchup jsonb;
  v_iter int := 0;
  v_total int := 0;
  v_has_more boolean := true;
BEGIN
  IF p_max_chunks IS NULL OR p_max_chunks < 1 THEN
    RAISE EXCEPTION 'p_max_chunks must be a positive integer';
  END IF;
  IF p_batch_size IS NULL OR p_batch_size < 1 THEN
    RAISE EXCEPTION 'p_batch_size must be a positive integer';
  END IF;

  LOOP
    v_catchup := public.fn_loyalty_cache_catchup_chunk(p_merchant_id, p_as_of_date, p_batch_size);
    v_iter := v_iter + 1;
    v_total := v_total + COALESCE((v_catchup->>'users_refreshed')::int, 0);
    v_has_more := COALESCE((v_catchup->>'has_more')::boolean, false);
    EXIT WHEN NOT v_has_more;
    EXIT WHEN v_iter >= p_max_chunks;
  END LOOP;

  RETURN jsonb_build_object(
    'chunks', v_iter,
    'users_refreshed', v_total,
    'has_more', v_has_more,
    'backlog_complete', NOT v_has_more
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_loyalty_cache_refresh_5m()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_locked boolean;
  v_merchant record;
  v_cutoff timestamptz;
  v_scan_from timestamptz;
  v_now timestamptz := now();
  v_as_of date := (timezone('Asia/Bangkok', now()))::date;
  v_users uuid[];
  v_chunk uuid[];
  v_i int;
  v_iter int;
  v_merchants int := 0;
  v_users_total int := 0;
  v_catchup_total int := 0;
  v_merchant_catchup_total int := 0;
  v_failed boolean := false;
  v_err text;
  v_result jsonb;
  v_catchup jsonb;
  v_catchup_pass jsonb;
  v_details jsonb := '[]'::jsonb;
  v_internal_chunk_size constant integer := 500;
  v_catchup_chunks_per_tick constant integer := 6;
BEGIN
  v_locked := pg_try_advisory_lock(hashtext('loyalty_cache_refresh_5m'));
  IF NOT v_locked THEN
    RETURN jsonb_build_object('ok', true, 'locked', true);
  END IF;

  BEGIN
    FOR v_merchant IN
      SELECT DISTINCT mm.id AS merchant_id, mm.merchant_code
      FROM public.merchant_master mm
      WHERE public.fn_loyalty_is_custom_tier(mm.id)
         OR public.fn_loyalty_is_custom_expiry(mm.id)
    LOOP
      v_merchants := v_merchants + 1;

      INSERT INTO public.system_cron (job_name, merchant_id, cutoff_at, status, updated_at)
      VALUES ('loyalty_cache_refresh', v_merchant.merchant_id, v_now - interval '1 day', 'running', v_now)
      ON CONFLICT (job_name, merchant_id) DO UPDATE SET
        status = 'running',
        updated_at = v_now;

      SELECT sc.cutoff_at INTO v_cutoff
      FROM public.system_cron sc
      WHERE sc.job_name = 'loyalty_cache_refresh'
        AND sc.merchant_id = v_merchant.merchant_id;

      v_cutoff := COALESCE(v_cutoff, v_now - interval '1 day');
      v_scan_from := v_cutoff - interval '5 minutes';

      BEGIN
        SELECT COALESCE(array_agg(DISTINCT d.user_id), ARRAY[]::uuid[])
        INTO v_users
        FROM (
          SELECT wl.user_id
          FROM public.wallet_ledger wl
          WHERE wl.merchant_id = v_merchant.merchant_id
            AND wl.currency = 'points'::public.currency
            AND wl.transaction_type = ANY (
              ARRAY[
                'earn'::public.currency_transaction_type,
                'burn'::public.currency_transaction_type
              ]
            )
            AND wl.created_at >= v_scan_from
          UNION
          SELECT pr.user_id
          FROM public.purchase_receipt_upload pr
          WHERE pr.merchant_id = v_merchant.merchant_id
            AND pr.status = 'approved'
            AND pr.crm_sync_status = 'confirmed'
            AND pr.updated_at >= v_scan_from
            AND pr.user_id IS NOT NULL
        ) d;

        IF cardinality(v_users) > 0 THEN
          v_i := 1;
          WHILE v_i <= cardinality(v_users) LOOP
            v_chunk := v_users[v_i : LEAST(v_i + v_internal_chunk_size - 1, cardinality(v_users))];
            v_result := public.fn_loyalty_cache_refresh_users(v_merchant.merchant_id, v_chunk, v_as_of);
            v_users_total := v_users_total + cardinality(v_chunk);
            v_i := v_i + v_internal_chunk_size;
          END LOOP;
        END IF;

        IF public.fn_loyalty_cache_catchup_due(v_merchant.merchant_id) THEN
          v_iter := 0;
          v_merchant_catchup_total := 0;

          LOOP
            v_catchup := public.fn_loyalty_cache_catchup_chunk(
              v_merchant.merchant_id,
              v_as_of,
              v_internal_chunk_size
            );
            v_iter := v_iter + 1;
            v_merchant_catchup_total := v_merchant_catchup_total
              + COALESCE((v_catchup->>'users_refreshed')::int, 0);

            EXIT WHEN NOT COALESCE((v_catchup->>'has_more')::boolean, false);
            EXIT WHEN v_iter >= v_catchup_chunks_per_tick;
          END LOOP;

          v_catchup_total := v_catchup_total + v_merchant_catchup_total;
          v_catchup_pass := jsonb_build_object(
            'ran', true,
            'iterations', v_iter,
            'users_refreshed', v_merchant_catchup_total,
            'backlog_complete', COALESCE((v_catchup->>'backlog_complete')::boolean, false),
            'paced', true
          );
        ELSE
          v_catchup_pass := jsonb_build_object(
            'ran', false,
            'reason', 'daily_gate',
            'users_refreshed', 0
          );
        END IF;

        UPDATE public.system_cron
        SET cutoff_at = v_now,
            last_finished_at = v_now,
            status = 'success',
            updated_at = v_now
        WHERE job_name = 'loyalty_cache_refresh'
          AND merchant_id = v_merchant.merchant_id;

        v_details := v_details || jsonb_build_array(jsonb_build_object(
          'merchant_id', v_merchant.merchant_id,
          'merchant_code', v_merchant.merchant_code,
          'dirty_users', COALESCE(cardinality(v_users), 0),
          'catchup', v_catchup_pass,
          'status', 'success'
        ));
      EXCEPTION WHEN OTHERS THEN
        v_failed := true;
        v_err := SQLERRM;
        UPDATE public.system_cron
        SET status = 'failed',
            last_finished_at = v_now,
            updated_at = v_now
        WHERE job_name = 'loyalty_cache_refresh'
          AND merchant_id = v_merchant.merchant_id;
        v_details := v_details || jsonb_build_array(jsonb_build_object(
          'merchant_id', v_merchant.merchant_id,
          'merchant_code', v_merchant.merchant_code,
          'status', 'failed',
          'error', v_err
        ));
      END;
    END LOOP;
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_advisory_unlock(hashtext('loyalty_cache_refresh_5m'));
    RAISE;
  END;

  PERFORM pg_advisory_unlock(hashtext('loyalty_cache_refresh_5m'));

  RETURN jsonb_build_object(
    'ok', NOT v_failed,
    'locked', false,
    'merchants', v_merchants,
    'users_refreshed', v_users_total,
    'catchup_users_refreshed', v_catchup_total,
    'details', v_details
  );
END;
$function$;

