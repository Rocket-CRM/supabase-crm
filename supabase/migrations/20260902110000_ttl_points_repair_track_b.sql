-- Track B hold apply: resolution-scoped manifest build for A/B/C holds.
-- Uses ttl_points_repair_hold_resolution (seeded from hold-resolution-table.csv).
-- Reuses fn_ttl_points_repair_apply_step{1,2,3} — hold users are is_clean=true in their run.

CREATE TABLE IF NOT EXISTS public.ttl_points_repair_hold_resolution (
  merchant_id uuid NOT NULL REFERENCES public.merchant_master(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  resolution text NOT NULL CHECK (resolution IN ('A', 'B', 'C', 'E', 'F')),
  hold_reasons text[] NOT NULL DEFAULT '{}',
  last_ts timestamptz,
  revised_last_ts timestamptz,
  step1_pts integer NOT NULL DEFAULT 0,
  step2_pts integer NOT NULL DEFAULT 0,
  step3_pts integer NOT NULL DEFAULT 0,
  investigation_notes text,
  PRIMARY KEY (merchant_id, user_id)
);

CREATE INDEX IF NOT EXISTS ttl_points_repair_hold_resolution_resolution_idx
  ON public.ttl_points_repair_hold_resolution (merchant_id, resolution);

REVOKE ALL ON public.ttl_points_repair_hold_resolution FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.ttl_points_repair_hold_resolution TO postgres, service_role;

ALTER TABLE public.ttl_points_repair_run
  ADD COLUMN IF NOT EXISTS track text;

ALTER TABLE public.ttl_points_repair_user
  ADD COLUMN IF NOT EXISTS resolution text,
  ADD COLUMN IF NOT EXISTS anchor_ts timestamptz;

CREATE OR REPLACE FUNCTION public.fn_ttl_points_repair_build_hold_manifest(
  p_merchant_id uuid,
  p_resolution text
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
  v_anchor_ts timestamptz;
  v_anchor_day date;
BEGIN
  IF p_resolution NOT IN ('A', 'B', 'C') THEN
    RAISE EXCEPTION 'p_resolution must be A, B, or C (got %)', p_resolution;
  END IF;

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

  IF NOT EXISTS (
    SELECT 1 FROM ttl_points_repair_hold_resolution
    WHERE merchant_id = p_merchant_id AND resolution = p_resolution
  ) THEN
    RAISE EXCEPTION 'no hold resolutions for merchant % resolution %', p_merchant_id, p_resolution;
  END IF;

  INSERT INTO ttl_points_repair_run (merchant_id, merchant_mongo, as_of_date, status, track)
  VALUES (p_merchant_id, v_mongo, v_today, 'manifest', 'hold_' || p_resolution)
  RETURNING id INTO v_run_id;

  INSERT INTO ttl_points_repair_user (
    run_id, user_id, is_clean, hold_reasons, last_ts, last_day, wallet_balance,
    step1_lots, step2_excess, step3_both, step3_wallet_only,
    resolution, anchor_ts
  )
  WITH
  targets AS (
    SELECT
      hr.user_id,
      hr.hold_reasons,
      hr.last_ts AS orig_last_ts,
      CASE
        WHEN p_resolution = 'A' THEN COALESCE(hr.revised_last_ts, hr.last_ts)
        WHEN p_resolution = 'C' THEN COALESCE(hr.revised_last_ts, hr.last_ts)
        ELSE hr.last_ts
      END AS anchor_ts
    FROM ttl_points_repair_hold_resolution hr
    WHERE hr.merchant_id = p_merchant_id
      AND hr.resolution = p_resolution
  ),
  earn AS (
    SELECT
      t.user_id,
      t.anchor_ts,
      t.anchor_ts::date AS anchor_day,
      coalesce(sum(wl.deductible_balance) FILTER (
        WHERE t.anchor_ts IS NOT NULL AND wl.expiry_date IS NOT NULL
          AND wl.expiry_date <= t.anchor_ts::date
      ), 0)::integer AS step1_lots,
      coalesce(sum(wl.deductible_balance) FILTER (
        WHERE t.anchor_ts IS NOT NULL AND wl.expiry_date IS NOT NULL
          AND wl.expiry_date > t.anchor_ts::date AND wl.expiry_date < v_today
      ), 0)::integer AS due_after_last,
      coalesce(sum(wl.deductible_balance) FILTER (
        WHERE t.anchor_ts IS NULL OR wl.expiry_date IS NULL
          OR (wl.expiry_date > t.anchor_ts::date AND wl.expiry_date >= v_today)
      ), 0)::integer AS valid_lots
    FROM targets t
    JOIN wallet_ledger wl ON wl.user_id = t.user_id
    WHERE wl.merchant_id = p_merchant_id
      AND wl.currency = 'points'
      AND wl.transaction_type = 'earn'::currency_transaction_type
    GROUP BY t.user_id, t.anchor_ts
  ),
  sim AS (
    SELECT
      t.user_id,
      t.hold_reasons,
      t.orig_last_ts,
      t.anchor_ts,
      e.anchor_day,
      w.points_balance AS wallet_0,
      coalesce(e.step1_lots, 0) AS step1_lots,
      coalesce(e.due_after_last, 0) AS due_after_last,
      coalesce(e.valid_lots, 0) AS valid_lots,
      coalesce(e.due_after_last, 0) + coalesce(e.valid_lots, 0) AS lots_after_1,
      GREATEST(coalesce(e.due_after_last, 0) + coalesce(e.valid_lots, 0) - w.points_balance, 0)::integer AS step2_excess
    FROM targets t
    JOIN user_wallet w ON w.user_id = t.user_id AND w.merchant_id = p_merchant_id
    LEFT JOIN earn e ON e.user_id = t.user_id
  ),
  sim2 AS (
    SELECT s.*,
      GREATEST(s.due_after_last - s.step2_excess, 0)::integer AS due_after_after_2,
      GREATEST(s.step2_excess - s.due_after_last, 0)::integer AS excess_into_valid
    FROM sim s
  ),
  sim3 AS (
    SELECT s.*,
      CASE WHEN p_resolution = 'B' THEN 0
           ELSE GREATEST(s.due_after_after_2, 0)::integer END AS step3_both,
      CASE WHEN p_resolution = 'B' THEN 0
           ELSE GREATEST(
             (s.wallet_0 - s.due_after_after_2)
             - GREATEST(s.valid_lots - s.excess_into_valid, 0),
             0
           )::integer END AS step3_wallet_only
    FROM sim2 s
  )
  SELECT
    v_run_id,
    s3.user_id,
    true AS is_clean,
    coalesce(s3.hold_reasons, '{}'),
    s3.orig_last_ts,
    s3.anchor_day,
    s3.wallet_0,
    s3.step1_lots,
    s3.step2_excess,
    s3.step3_both,
    s3.step3_wallet_only,
    p_resolution,
    s3.anchor_ts
  FROM sim3 s3
  WHERE s3.step1_lots > 0 OR s3.step2_excess > 0 OR s3.step3_both > 0 OR s3.step3_wallet_only > 0;

  FOR v_u IN
    SELECT u.user_id, u.anchor_ts, u.last_day, u.wallet_balance,
           u.step1_lots, u.step2_excess, u.step3_both, u.step3_wallet_only
    FROM ttl_points_repair_user u
    WHERE u.run_id = v_run_id
      AND (u.step1_lots > 0 OR u.step2_excess > 0 OR u.step3_both > 0 OR u.step3_wallet_only > 0)
  LOOP
    v_anchor_ts := v_u.anchor_ts;
    v_anchor_day := v_u.last_day;
    v_need := v_u.step2_excess;
    v_due_after_after_2 := 0;
    v_valid_after_2 := 0;

    FOR v_lot IN
      SELECT
        wl.id AS ledger_id,
        wl.expiry_date,
        wl.deductible_balance::integer AS open_balance,
        CASE
          WHEN v_anchor_day IS NOT NULL AND wl.expiry_date IS NOT NULL AND wl.expiry_date <= v_anchor_day
            THEN 'step1'
          WHEN v_anchor_day IS NOT NULL AND wl.expiry_date IS NOT NULL
               AND wl.expiry_date > v_anchor_day AND wl.expiry_date < v_today
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
          WHEN v_anchor_day IS NOT NULL AND wl.expiry_date IS NOT NULL AND wl.expiry_date <= v_anchor_day THEN 0
          WHEN v_anchor_day IS NOT NULL AND wl.expiry_date IS NOT NULL
               AND wl.expiry_date > v_anchor_day AND wl.expiry_date < v_today THEN 1
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

    IF p_resolution <> 'B' THEN
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
    END IF;
  END LOOP;

  SELECT jsonb_build_object(
    'run_id', v_run_id,
    'track', 'hold_' || p_resolution,
    'merchant_id', p_merchant_id,
    'resolution', p_resolution,
    'as_of_date', v_today,
    'users', (SELECT count(*) FROM ttl_points_repair_user WHERE run_id = v_run_id),
    'step1_users', (SELECT count(*) FROM ttl_points_repair_user WHERE run_id = v_run_id AND step1_lots > 0),
    'step1_pts', (SELECT coalesce(sum(step1_lots), 0) FROM ttl_points_repair_user WHERE run_id = v_run_id),
    'step2_users', (SELECT count(*) FROM ttl_points_repair_user WHERE run_id = v_run_id AND step2_excess > 0),
    'step2_pts', (SELECT coalesce(sum(step2_excess), 0) FROM ttl_points_repair_user WHERE run_id = v_run_id),
    'step3_users', (SELECT count(*) FROM ttl_points_repair_user WHERE run_id = v_run_id AND (step3_both > 0 OR step3_wallet_only > 0)),
    'step3_pts', (SELECT coalesce(sum(step3_both + step3_wallet_only), 0) FROM ttl_points_repair_user WHERE run_id = v_run_id),
    'lots', (SELECT count(*) FROM ttl_points_repair_lot WHERE run_id = v_run_id),
    'burns', (SELECT count(*) FROM ttl_points_repair_burn WHERE run_id = v_run_id)
  ) INTO v_summary;

  UPDATE ttl_points_repair_run SET summary = v_summary WHERE id = v_run_id;
  RETURN v_summary;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_ttl_points_repair_build_hold_manifest(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_ttl_points_repair_build_hold_manifest(uuid, text) TO postgres, service_role;
