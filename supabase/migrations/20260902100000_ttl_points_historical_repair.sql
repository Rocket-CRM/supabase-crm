-- TTL merchant historical points lot repair (Track A clean cohort).
-- Merchant-scoped manifest + batched apply for steps 1–3.
-- Uses fn_repair_wallet_expiry_burn for step 3 (backdated, _skip_emit).
-- Do not use for Her Hyness (fn_hh_repair_*).

CREATE TABLE IF NOT EXISTS public.ttl_points_repair_run (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES public.merchant_master(id),
  merchant_mongo text NOT NULL,
  as_of_date date NOT NULL,
  status text NOT NULL DEFAULT 'manifest',
  summary jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.ttl_points_repair_user (
  run_id uuid NOT NULL REFERENCES public.ttl_points_repair_run(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  is_clean boolean NOT NULL DEFAULT false,
  hold_reasons text[] NOT NULL DEFAULT '{}',
  last_ts timestamptz,
  last_day date,
  wallet_balance integer NOT NULL,
  step1_lots integer NOT NULL DEFAULT 0,
  step2_excess integer NOT NULL DEFAULT 0,
  step3_both integer NOT NULL DEFAULT 0,
  step3_wallet_only integer NOT NULL DEFAULT 0,
  step1_applied_at timestamptz,
  step2_applied_at timestamptz,
  step3_applied_at timestamptz,
  PRIMARY KEY (run_id, user_id)
);

CREATE INDEX IF NOT EXISTS ttl_points_repair_user_clean_idx
  ON public.ttl_points_repair_user (run_id) WHERE is_clean;

CREATE TABLE IF NOT EXISTS public.ttl_points_repair_lot (
  run_id uuid NOT NULL REFERENCES public.ttl_points_repair_run(id) ON DELETE CASCADE,
  ledger_id uuid NOT NULL,
  user_id uuid NOT NULL,
  expiry_date date,
  lot_bucket text NOT NULL,
  open_balance integer NOT NULL,
  step1_delta integer NOT NULL DEFAULT 0,
  step2_delta integer NOT NULL DEFAULT 0,
  PRIMARY KEY (run_id, ledger_id)
);

CREATE INDEX IF NOT EXISTS ttl_points_repair_lot_user_idx
  ON public.ttl_points_repair_lot (run_id, user_id);

CREATE TABLE IF NOT EXISTS public.ttl_points_repair_burn (
  run_id uuid NOT NULL REFERENCES public.ttl_points_repair_run(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  expiry_date date NOT NULL,
  burn_amount integer NOT NULL,
  burn_kind text NOT NULL CHECK (burn_kind IN ('both', 'wallet_only')),
  dedup_key text NOT NULL,
  ledger_id uuid,
  applied_at timestamptz,
  PRIMARY KEY (run_id, user_id, expiry_date, burn_kind)
);

REVOKE ALL ON public.ttl_points_repair_run FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.ttl_points_repair_user FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.ttl_points_repair_lot FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.ttl_points_repair_burn FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_ttl_points_repair_build_manifest(
  p_merchant_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  v_run_id uuid;
  v_mongo text;
  v_mode text;
  v_sync_active boolean;
  v_today date := CURRENT_DATE;
  v_u record;
  v_lot record;
  v_need integer;
  v_step1_delta integer;
  v_step2_delta integer;
  v_remain integer;
  v_due_after_after_2 integer;
  v_valid_after_2 integer;
  v_step3_wallet_only integer;
  v_summary jsonb;
BEGIN
  SELECT m.mongo_id, m.points_expiry_mode, COALESCE(s.sync_active, false)
    INTO v_mongo, v_mode, v_sync_active
  FROM merchant_master m
  LEFT JOIN migration_merchant_status s ON s.merchant_uuid = m.id
  WHERE m.id = p_merchant_id;

  IF v_mongo IS NULL THEN
    RAISE EXCEPTION 'merchant % not found', p_merchant_id;
  END IF;
  IF v_mode IS NULL OR v_mode = 'none' THEN
    RAISE EXCEPTION 'merchant % points_expiry_mode is none — not eligible', p_merchant_id;
  END IF;
  IF v_sync_active THEN
    RAISE EXCEPTION 'migration sync_active is true for merchant % — pause sync first', p_merchant_id;
  END IF;

  INSERT INTO ttl_points_repair_run (merchant_id, merchant_mongo, as_of_date, status)
  VALUES (p_merchant_id, v_mongo, v_today, 'manifest')
  RETURNING id INTO v_run_id;

  INSERT INTO ttl_points_repair_user (
    run_id, user_id, is_clean, hold_reasons, last_ts, last_day, wallet_balance,
    step1_lots, step2_excess, step3_both, step3_wallet_only
  )
  WITH
  last_old AS (
    SELECT wl.user_id,
           max(wl.created_at) AS last_ts,
           max(wl.created_at)::date AS last_day
    FROM wallet_ledger wl
    WHERE wl.merchant_id = p_merchant_id
      AND wl.currency = 'points'
      AND wl.mongo_id IS NOT NULL
      AND wl.source_type IS DISTINCT FROM 'expiry'::wallet_transaction_source_type
    GROUP BY 1
  ),
  earn AS (
    SELECT wl.user_id,
      coalesce(sum(wl.deductible_balance) FILTER (
        WHERE lo.last_day IS NOT NULL AND wl.expiry_date IS NOT NULL AND wl.expiry_date <= lo.last_day
      ), 0)::integer AS step1_lots,
      coalesce(sum(wl.deductible_balance) FILTER (
        WHERE lo.last_day IS NOT NULL AND wl.expiry_date IS NOT NULL
          AND wl.expiry_date > lo.last_day AND wl.expiry_date < v_today
      ), 0)::integer AS due_after_last,
      coalesce(sum(wl.deductible_balance) FILTER (
        WHERE lo.last_day IS NULL OR wl.expiry_date IS NULL
           OR (wl.expiry_date > lo.last_day AND wl.expiry_date >= v_today)
      ), 0)::integer AS valid_lots
    FROM wallet_ledger wl
    LEFT JOIN last_old lo ON lo.user_id = wl.user_id
    WHERE wl.merchant_id = p_merchant_id
      AND wl.currency = 'points'
      AND wl.transaction_type = 'earn'::currency_transaction_type
    GROUP BY wl.user_id
  ),
  sim AS (
    SELECT w.user_id, w.points_balance AS wallet_0,
      coalesce(e.step1_lots, 0) AS step1_lots,
      coalesce(e.due_after_last, 0) AS due_after_last,
      coalesce(e.valid_lots, 0) AS valid_lots,
      coalesce(e.due_after_last, 0) + coalesce(e.valid_lots, 0) AS lots_after_1,
      GREATEST(coalesce(e.due_after_last, 0) + coalesce(e.valid_lots, 0) - w.points_balance, 0)::integer AS step2_excess
    FROM user_wallet w
    LEFT JOIN earn e ON e.user_id = w.user_id
    WHERE w.merchant_id = p_merchant_id
  ),
  sim2 AS (
    SELECT s.*,
      GREATEST(s.due_after_last - s.step2_excess, 0)::integer AS due_after_after_2,
      GREATEST(s.step2_excess - s.due_after_last, 0)::integer AS excess_into_valid
    FROM sim s
  ),
  sim3 AS (
    SELECT s.*,
      GREATEST(s.valid_lots - s.excess_into_valid, 0)::integer AS valid_after_2,
      GREATEST(s.due_after_last - s.step2_excess, 0)::integer AS step3_both,
      GREATEST(
        (s.wallet_0 - GREATEST(s.due_after_last - s.step2_excess, 0))
        - GREATEST(s.valid_lots - GREATEST(s.step2_excess - s.due_after_last, 0), 0),
        0
      )::integer AS step3_wallet_only,
      s.wallet_0 - GREATEST(s.due_after_last - s.step2_excess, 0)
        - GREATEST(
            (s.wallet_0 - GREATEST(s.due_after_last - s.step2_excess, 0))
            - GREATEST(s.valid_lots - GREATEST(s.step2_excess - s.due_after_last, 0), 0),
            0
          ) AS final_wallet,
      GREATEST(s.valid_lots - s.excess_into_valid, 0)::integer AS final_lots
    FROM sim2 s
  ),
  holds AS (
    SELECT
      w.user_id,
      lo.last_ts,
      lo.last_day,
      w.points_balance,
      coalesce(s3.step1_lots, 0) AS step1_lots,
      coalesce(s3.step2_excess, 0) AS step2_excess,
      coalesce(s3.step3_both, 0) AS step3_both,
      coalesce(s3.step3_wallet_only, 0) AS step3_wallet_only,
      array_remove(array[
        CASE WHEN s3.final_wallet IS DISTINCT FROM s3.final_lots OR s3.final_wallet < 0
             THEN 'sim_reconcile' END,
        CASE WHEN EXISTS (
          SELECT 1 FROM wallet_ledger wl
          WHERE wl.merchant_id = p_merchant_id AND wl.user_id = w.user_id
            AND wl.currency = 'points'
            AND wl.source_type IS DISTINCT FROM 'expiry'
            AND wl.mongo_id IS NULL AND wl.created_at > lo.last_ts
        ) THEN 'later_newcrm' END,
        CASE WHEN EXISTS (
          SELECT 1 FROM stg_mongo_points mp
          JOIN user_accounts ua ON ua.id = w.user_id
          WHERE mp.merchant_ref = v_mongo
            AND mp.raw->>'userId' = ua.mongo_id
            AND mp.raw->>'type' IN ('GIVEN', 'REDEEMED')
            AND (mp.raw->>'createdAt')::timestamptz > lo.last_ts
        ) THEN 'mongo_sync_gap' END
      ], NULL) AS hold_reasons
    FROM user_wallet w
    LEFT JOIN last_old lo ON lo.user_id = w.user_id
    LEFT JOIN sim3 s3 ON s3.user_id = w.user_id
    WHERE w.merchant_id = p_merchant_id
  )
  SELECT
    v_run_id,
    h.user_id,
    coalesce(cardinality(h.hold_reasons), 0) = 0 AS is_clean,
    coalesce(h.hold_reasons, '{}'),
    h.last_ts,
    h.last_day,
    h.points_balance,
    h.step1_lots,
    h.step2_excess,
    h.step3_both,
    h.step3_wallet_only
  FROM holds h
  WHERE h.step1_lots > 0 OR h.step2_excess > 0 OR h.step3_both > 0 OR h.step3_wallet_only > 0
     OR coalesce(cardinality(h.hold_reasons), 0) > 0;

  FOR v_u IN
    SELECT u.user_id, u.last_ts, u.last_day, u.wallet_balance,
           u.step1_lots, u.step2_excess, u.step3_both, u.step3_wallet_only
    FROM ttl_points_repair_user u
    WHERE u.run_id = v_run_id AND u.is_clean
      AND (u.step1_lots > 0 OR u.step2_excess > 0 OR u.step3_both > 0 OR u.step3_wallet_only > 0)
  LOOP
    v_need := v_u.step2_excess;
    v_due_after_after_2 := 0;
    v_valid_after_2 := 0;

    FOR v_lot IN
      SELECT
        wl.id AS ledger_id,
        wl.expiry_date,
        wl.deductible_balance::integer AS open_balance,
        CASE
          WHEN v_u.last_day IS NOT NULL AND wl.expiry_date IS NOT NULL AND wl.expiry_date <= v_u.last_day
            THEN 'step1'
          WHEN v_u.last_day IS NOT NULL AND wl.expiry_date IS NOT NULL
               AND wl.expiry_date > v_u.last_day AND wl.expiry_date < v_today
            THEN 'due_after'
          ELSE 'valid'
        END AS lot_bucket
      FROM wallet_ledger wl
      WHERE wl.merchant_id = p_merchant_id
        AND wl.user_id = v_u.user_id
        AND wl.currency = 'points'
        AND wl.transaction_type = 'earn'::currency_transaction_type
        AND COALESCE(wl.deductible_balance, 0) > 0
      ORDER BY
        CASE
          WHEN v_u.last_day IS NOT NULL AND wl.expiry_date IS NOT NULL AND wl.expiry_date <= v_u.last_day THEN 0
          WHEN v_u.last_day IS NOT NULL AND wl.expiry_date IS NOT NULL
               AND wl.expiry_date > v_u.last_day AND wl.expiry_date < v_today THEN 1
          ELSE 2
        END,
        wl.expiry_date NULLS LAST,
        wl.created_at,
        wl.id
    LOOP
      v_step1_delta := 0;
      v_step2_delta := 0;

      IF v_lot.lot_bucket = 'step1' THEN
        v_step1_delta := v_lot.open_balance;
        v_remain := 0;
      ELSIF v_lot.lot_bucket IN ('due_after', 'valid') THEN
        v_step2_delta := CASE WHEN v_need > 0 THEN LEAST(v_need, v_lot.open_balance) ELSE 0 END;
        v_need := v_need - v_step2_delta;
        v_remain := v_lot.open_balance - v_step2_delta;
      ELSE
        v_remain := v_lot.open_balance;
      END IF;

      INSERT INTO ttl_points_repair_lot (
        run_id, ledger_id, user_id, expiry_date, lot_bucket,
        open_balance, step1_delta, step2_delta
      ) VALUES (
        v_run_id, v_lot.ledger_id, v_u.user_id, v_lot.expiry_date, v_lot.lot_bucket,
        v_lot.open_balance, v_step1_delta, v_step2_delta
      );

      IF v_lot.lot_bucket = 'due_after' THEN
        v_due_after_after_2 := v_due_after_after_2 + v_remain;
      ELSIF v_lot.lot_bucket = 'valid' THEN
        v_valid_after_2 := v_valid_after_2 + v_remain;
      END IF;
    END LOOP;

    v_step3_wallet_only := GREATEST(v_u.wallet_balance - v_due_after_after_2 - v_valid_after_2, 0);

    INSERT INTO ttl_points_repair_burn (run_id, user_id, expiry_date, burn_amount, burn_kind, dedup_key)
    SELECT v_run_id, v_u.user_id, rl.expiry_date,
           sum(rl.open_balance - rl.step1_delta - rl.step2_delta)::integer,
           'both',
           'ttl_repair:' || v_run_id::text || ':both:' || v_u.user_id::text || ':' || rl.expiry_date::text
    FROM ttl_points_repair_lot rl
    WHERE rl.run_id = v_run_id
      AND rl.user_id = v_u.user_id
      AND rl.lot_bucket = 'due_after'
      AND rl.open_balance - rl.step1_delta - rl.step2_delta > 0
    GROUP BY rl.expiry_date
    HAVING sum(rl.open_balance - rl.step1_delta - rl.step2_delta) > 0;

    IF v_step3_wallet_only > 0 THEN
      INSERT INTO ttl_points_repair_burn (
        run_id, user_id, expiry_date, burn_amount, burn_kind, dedup_key
      ) VALUES (
        v_run_id, v_u.user_id, v_today - 1, v_step3_wallet_only, 'wallet_only',
        'ttl_repair:' || v_run_id::text || ':wonly:' || v_u.user_id::text
      );
    END IF;
  END LOOP;

  SELECT jsonb_build_object(
    'run_id', v_run_id,
    'merchant_id', p_merchant_id,
    'as_of_date', v_today,
    'manifest_users', (SELECT count(*) FROM ttl_points_repair_user WHERE run_id = v_run_id),
    'clean_users', (SELECT count(*) FROM ttl_points_repair_user WHERE run_id = v_run_id AND is_clean),
    'held_users', (SELECT count(*) FROM ttl_points_repair_user WHERE run_id = v_run_id AND NOT is_clean),
    'clean_step1_users', (SELECT count(*) FROM ttl_points_repair_user WHERE run_id = v_run_id AND is_clean AND step1_lots > 0),
    'clean_step1_pts', (SELECT coalesce(sum(step1_lots), 0) FROM ttl_points_repair_user WHERE run_id = v_run_id AND is_clean),
    'clean_step2_users', (SELECT count(*) FROM ttl_points_repair_user WHERE run_id = v_run_id AND is_clean AND step2_excess > 0),
    'clean_step2_pts', (SELECT coalesce(sum(step2_excess), 0) FROM ttl_points_repair_user WHERE run_id = v_run_id AND is_clean),
    'clean_step3_users', (SELECT count(*) FROM ttl_points_repair_user WHERE run_id = v_run_id AND is_clean AND (step3_both > 0 OR step3_wallet_only > 0)),
    'clean_step3_pts', (SELECT coalesce(sum(step3_both + step3_wallet_only), 0) FROM ttl_points_repair_user WHERE run_id = v_run_id AND is_clean),
    'clean_lots', (SELECT count(*) FROM ttl_points_repair_lot WHERE run_id = v_run_id),
    'clean_burns', (SELECT count(*) FROM ttl_points_repair_burn WHERE run_id = v_run_id)
  ) INTO v_summary;

  UPDATE ttl_points_repair_run SET summary = v_summary WHERE id = v_run_id;
  RETURN v_summary;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_ttl_points_repair_apply_step1(
  p_run_id uuid,
  p_limit integer DEFAULT 500,
  p_dry_run boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_n integer := 0;
  v_pts integer := 0;
  v_lot record;
BEGIN
  SELECT merchant_id INTO v_merchant_id FROM ttl_points_repair_run WHERE id = p_run_id;
  IF v_merchant_id IS NULL THEN
    RAISE EXCEPTION 'run % not found', p_run_id;
  END IF;

  FOR v_lot IN
    SELECT rl.ledger_id, rl.step1_delta
    FROM ttl_points_repair_lot rl
    JOIN ttl_points_repair_user u ON u.run_id = rl.run_id AND u.user_id = rl.user_id
    WHERE rl.run_id = p_run_id
      AND u.is_clean
      AND u.step1_applied_at IS NULL
      AND rl.step1_delta > 0
    ORDER BY rl.user_id, rl.ledger_id
    LIMIT p_limit
  LOOP
    v_n := v_n + 1;
    v_pts := v_pts + v_lot.step1_delta;
    IF NOT p_dry_run THEN
      UPDATE wallet_ledger wl
      SET expired_amount = COALESCE(wl.expired_amount, 0) + v_lot.step1_delta,
          deductible_balance = GREATEST(COALESCE(wl.deductible_balance, 0) - v_lot.step1_delta, 0),
          expiry_processed_at = COALESCE(wl.expiry_processed_at, now())
      WHERE wl.id = v_lot.ledger_id
        AND wl.merchant_id = v_merchant_id;
    END IF;
  END LOOP;

  IF NOT p_dry_run THEN
    UPDATE ttl_points_repair_user u
    SET step1_applied_at = now()
    WHERE u.run_id = p_run_id AND u.is_clean AND u.step1_applied_at IS NULL
      AND (
        u.step1_lots = 0
        OR NOT EXISTS (
          SELECT 1
          FROM ttl_points_repair_lot rl
          JOIN wallet_ledger wl ON wl.id = rl.ledger_id
          WHERE rl.run_id = p_run_id
            AND rl.user_id = u.user_id
            AND rl.step1_delta > 0
            AND COALESCE(wl.deductible_balance, 0) > 0
        )
      );
  END IF;

  RETURN jsonb_build_object(
    'step', 1,
    'dry_run', p_dry_run,
    'lots_updated', v_n,
    'pts_zeroed', v_pts
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_ttl_points_repair_apply_step2(
  p_run_id uuid,
  p_limit integer DEFAULT 500,
  p_dry_run boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_n integer := 0;
  v_pts integer := 0;
  v_lot record;
BEGIN
  SELECT merchant_id INTO v_merchant_id FROM ttl_points_repair_run WHERE id = p_run_id;
  IF v_merchant_id IS NULL THEN
    RAISE EXCEPTION 'run % not found', p_run_id;
  END IF;

  IF NOT p_dry_run THEN
    UPDATE ttl_points_repair_user u
    SET step2_applied_at = now()
    WHERE u.run_id = p_run_id AND u.is_clean
      AND u.step1_applied_at IS NOT NULL
      AND u.step2_applied_at IS NULL
      AND u.step2_excess = 0;
  END IF;

  FOR v_lot IN
    SELECT rl.ledger_id, rl.step2_delta
    FROM ttl_points_repair_lot rl
    JOIN ttl_points_repair_user u ON u.run_id = rl.run_id AND u.user_id = rl.user_id
    WHERE rl.run_id = p_run_id
      AND u.is_clean
      AND (p_dry_run OR u.step1_applied_at IS NOT NULL)
      AND (p_dry_run OR u.step2_applied_at IS NULL)
      AND rl.step2_delta > 0
    ORDER BY rl.user_id, rl.ledger_id
    LIMIT p_limit
  LOOP
    v_n := v_n + 1;
    v_pts := v_pts + v_lot.step2_delta;
    IF NOT p_dry_run THEN
      UPDATE wallet_ledger wl
      SET deductible_balance = GREATEST(COALESCE(wl.deductible_balance, 0) - v_lot.step2_delta, 0)
      WHERE wl.id = v_lot.ledger_id
        AND wl.merchant_id = v_merchant_id;
    END IF;
  END LOOP;

  IF NOT p_dry_run THEN
    UPDATE ttl_points_repair_user u
    SET step2_applied_at = now()
    WHERE u.run_id = p_run_id AND u.is_clean AND u.step2_applied_at IS NULL
      AND u.step1_applied_at IS NOT NULL
      AND (
        u.step2_excess = 0
        OR NOT EXISTS (
          SELECT 1
          FROM ttl_points_repair_lot rl
          JOIN wallet_ledger wl ON wl.id = rl.ledger_id
          WHERE rl.run_id = p_run_id
            AND rl.user_id = u.user_id
            AND rl.step2_delta > 0
            AND COALESCE(wl.deductible_balance, 0) > 0
        )
      );
  END IF;

  RETURN jsonb_build_object(
    'step', 2,
    'dry_run', p_dry_run,
    'lots_updated', v_n,
    'pts_reduced', v_pts
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_ttl_points_repair_apply_step3(
  p_run_id uuid,
  p_limit integer DEFAULT 200,
  p_dry_run boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_n integer := 0;
  v_pts integer := 0;
  v_burn record;
  v_lid uuid;
BEGIN
  SELECT merchant_id INTO v_merchant_id FROM ttl_points_repair_run WHERE id = p_run_id;
  IF v_merchant_id IS NULL THEN
    RAISE EXCEPTION 'run % not found', p_run_id;
  END IF;

  IF NOT p_dry_run THEN
    UPDATE ttl_points_repair_user u
    SET step3_applied_at = now()
    WHERE u.run_id = p_run_id AND u.is_clean
      AND u.step2_applied_at IS NOT NULL
      AND u.step3_applied_at IS NULL
      AND u.step3_both = 0 AND u.step3_wallet_only = 0;
  END IF;

  FOR v_burn IN
    SELECT b.user_id, b.expiry_date, b.burn_amount, b.burn_kind, b.dedup_key
    FROM ttl_points_repair_burn b
    JOIN ttl_points_repair_user u ON u.run_id = b.run_id AND u.user_id = b.user_id
    WHERE b.run_id = p_run_id
      AND u.is_clean
      AND (p_dry_run OR u.step2_applied_at IS NOT NULL)
      AND (p_dry_run OR b.applied_at IS NULL)
    ORDER BY b.user_id, b.expiry_date, b.burn_kind
    LIMIT p_limit
  LOOP
    v_n := v_n + 1;
    v_pts := v_pts + v_burn.burn_amount;

    IF NOT p_dry_run THEN
      IF v_burn.burn_kind = 'both' THEN
        UPDATE wallet_ledger wl
        SET expired_amount = COALESCE(wl.expired_amount, 0) + GREATEST(COALESCE(wl.deductible_balance, 0), 0),
            deductible_balance = 0,
            expiry_processed_at = COALESCE(wl.expiry_processed_at, now())
        FROM ttl_points_repair_lot rl
        WHERE rl.run_id = p_run_id
          AND rl.user_id = v_burn.user_id
          AND rl.lot_bucket = 'due_after'
          AND rl.expiry_date = v_burn.expiry_date
          AND wl.id = rl.ledger_id
          AND wl.merchant_id = v_merchant_id
          AND COALESCE(wl.deductible_balance, 0) > 0;
      END IF;

      v_lid := fn_repair_wallet_expiry_burn(
        p_user_id := v_burn.user_id,
        p_merchant_id := v_merchant_id,
        p_amount := v_burn.burn_amount,
        p_expiry_date := v_burn.expiry_date,
        p_repair_run_id := p_run_id::text,
        p_dedup_key := v_burn.dedup_key,
        p_description := CASE
          WHEN v_burn.burn_kind = 'wallet_only' THEN 'TTL historical repair wallet-only'
          ELSE 'TTL historical repair expiry for ' || v_burn.expiry_date::text
        END
      );

      UPDATE ttl_points_repair_burn
      SET applied_at = now(), ledger_id = v_lid
      WHERE run_id = p_run_id
        AND user_id = v_burn.user_id
        AND expiry_date = v_burn.expiry_date
        AND burn_kind = v_burn.burn_kind;
    END IF;
  END LOOP;

  IF NOT p_dry_run THEN
    UPDATE ttl_points_repair_user u
    SET step3_applied_at = now()
    WHERE u.run_id = p_run_id AND u.is_clean AND u.step3_applied_at IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM ttl_points_repair_burn b
        WHERE b.run_id = p_run_id AND b.user_id = u.user_id AND b.applied_at IS NULL
      );

    UPDATE ttl_points_repair_run
    SET status = 'complete'
    WHERE id = p_run_id
      AND NOT EXISTS (
        SELECT 1 FROM ttl_points_repair_user u
        WHERE u.run_id = p_run_id AND u.is_clean AND u.step3_applied_at IS NULL
      );
  END IF;

  RETURN jsonb_build_object(
    'step', 3,
    'dry_run', p_dry_run,
    'burns', v_n,
    'wallet_pts_down', v_pts
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_ttl_points_repair_build_manifest(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_ttl_points_repair_apply_step1(uuid, integer, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_ttl_points_repair_apply_step2(uuid, integer, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_ttl_points_repair_apply_step3(uuid, integer, boolean) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.fn_ttl_points_repair_build_manifest(uuid) TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.fn_ttl_points_repair_apply_step1(uuid, integer, boolean) TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.fn_ttl_points_repair_apply_step2(uuid, integer, boolean) TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.fn_ttl_points_repair_apply_step3(uuid, integer, boolean) TO postgres, service_role;
