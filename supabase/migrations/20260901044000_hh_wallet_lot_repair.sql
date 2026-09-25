-- Her Hyness wallet/lot repair manifest + step runners.
-- Merchant-scoped one-off. Dry-run by default (p_apply false).

CREATE TABLE IF NOT EXISTS public.hh_wallet_repair_run (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL,
  extract_checksum text NOT NULL,
  extract_instant timestamptz NOT NULL,
  manifest_cutoff_at timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'dry_run',
  summary jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.hh_wallet_repair_lot (
  run_id uuid NOT NULL REFERENCES public.hh_wallet_repair_run(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  ledger_id uuid NOT NULL,
  expiry_date date,
  current_deductible integer NOT NULL,
  expired_amount integer,
  expiry_processed_at timestamptz,
  extract_remaining integer,
  extract_expiry date,
  start_remaining integer,
  fifo_replay integer NOT NULL DEFAULT 0,
  target_remaining integer,
  step1_delta integer NOT NULL DEFAULT 0,
  intended_after_lot_repairs integer,
  is_future_restore boolean NOT NULL DEFAULT false,
  is_legacy_expiry boolean NOT NULL DEFAULT false,
  is_august boolean NOT NULL DEFAULT false,
  hold_reason text,
  PRIMARY KEY (run_id, ledger_id)
);

CREATE INDEX IF NOT EXISTS hh_wallet_repair_lot_user_idx
  ON public.hh_wallet_repair_lot (run_id, user_id);

CREATE TABLE IF NOT EXISTS public.hh_wallet_repair_user (
  run_id uuid NOT NULL REFERENCES public.hh_wallet_repair_run(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  wallet_balance integer NOT NULL,
  current_lots integer NOT NULL,
  signed_sum integer,
  expected_lots integer,
  step1_excess integer NOT NULL DEFAULT 0,
  step1_eligible boolean NOT NULL DEFAULT false,
  proven_legacy_expiry integer NOT NULL DEFAULT 0,
  identity_ok boolean NOT NULL DEFAULT false,
  later_activity boolean NOT NULL DEFAULT false,
  hold_reason text,
  PRIMARY KEY (run_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.hh_wallet_repair_date (
  run_id uuid NOT NULL REFERENCES public.hh_wallet_repair_run(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  expiry_date date NOT NULL,
  burn_amount integer NOT NULL,
  later_activity boolean NOT NULL DEFAULT false,
  hold_reason text,
  PRIMARY KEY (run_id, user_id, expiry_date)
);

REVOKE ALL ON public.hh_wallet_repair_run FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.hh_wallet_repair_lot FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.hh_wallet_repair_user FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.hh_wallet_repair_date FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_hh_repair_build_manifest(
  p_merchant_id uuid DEFAULT 'ffe8519e-49a2-467b-a0ec-57d28ba8be49'::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  v_run_id uuid;
  v_cutoff timestamptz := clock_timestamp();
  v_extract_instant timestamptz := timestamptz '2026-08-09 20:16:29.644+00';
  v_checksum text := '835742086ed4cbb5c2bf7746278e6cc2';
  v_mongo_id text;
  v_live_checksum text;
  v_summary jsonb;
  v_burn record;
  v_need integer;
  v_lot record;
  v_take integer;
  v_u record;
  v_left integer;
BEGIN
  SELECT mongo_id INTO v_mongo_id FROM merchant_master WHERE id = p_merchant_id;
  IF v_mongo_id IS NULL THEN
    RAISE EXCEPTION 'merchant % not found', p_merchant_id;
  END IF;

  SELECT md5(string_agg(
           p.mongo_id || chr(31) || COALESCE(p.raw->>'balance','') || chr(31)
           || COALESCE(p.raw->>'expiredDate','') || chr(31) || COALESCE(p.raw->>'type',''),
           chr(30) ORDER BY p.mongo_id))
    INTO v_live_checksum
  FROM stg_mongo_points p
  WHERE p.merchant_ref = v_mongo_id;

  IF v_live_checksum IS DISTINCT FROM v_checksum THEN
    RAISE EXCEPTION 'staging extract checksum changed: expected %, got %', v_checksum, v_live_checksum;
  END IF;

  INSERT INTO hh_wallet_repair_run (
    merchant_id, extract_checksum, extract_instant, manifest_cutoff_at, status
  ) VALUES (
    p_merchant_id, v_checksum, v_extract_instant, v_cutoff, 'dry_run'
  ) RETURNING id INTO v_run_id;

  INSERT INTO hh_wallet_repair_lot (
    run_id, user_id, ledger_id, expiry_date, current_deductible, expired_amount,
    expiry_processed_at, extract_remaining, extract_expiry, start_remaining,
    is_future_restore, is_legacy_expiry, is_august, hold_reason
  )
  SELECT
    v_run_id,
    wl.user_id,
    wl.id,
    wl.expiry_date,
    COALESCE(wl.deductible_balance, 0)::integer,
    COALESCE(wl.expired_amount, 0),
    wl.expiry_processed_at,
    CASE WHEN p.raw ? 'balance' THEN (p.raw->>'balance')::integer ELSE NULL END,
    CASE WHEN (p.raw->>'expiredDate') ~ '^[0-9]{13}$'
         THEN (to_timestamp((p.raw->>'expiredDate')::numeric / 1000.0))::date
         ELSE NULL END,
    CASE
      WHEN p.raw ? 'balance' THEN (p.raw->>'balance')::integer
      WHEN wl.mongo_id IS NULL AND wl.created_at > v_extract_instant THEN wl.amount
      ELSE NULL
    END,
    false, false, false,
    CASE
      WHEN p.mongo_id IS NOT NULL AND (p.raw->>'expiredDate') IS NOT NULL
           AND (p.raw->>'expiredDate') !~ '^[0-9]{13}$' THEN 'unparseable_extract_expiry'
      WHEN p.mongo_id IS NOT NULL AND NOT (p.raw ? 'balance') THEN 'missing_extract_remaining'
      WHEN p.mongo_id IS NULL AND wl.created_at <= v_extract_instant THEN 'no_extract_for_precutover_lot'
      ELSE NULL
    END
  FROM wallet_ledger wl
  LEFT JOIN stg_mongo_points p
    ON p.mongo_id = wl.mongo_id AND p.raw->>'type' = 'GIVEN'
  WHERE wl.merchant_id = p_merchant_id
    AND wl.currency = 'points'::currency
    AND wl.transaction_type = 'earn'::currency_transaction_type;

  UPDATE hh_wallet_repair_lot l
  SET hold_reason = COALESCE(l.hold_reason, 'extract_expiry_mismatch')
  WHERE l.run_id = v_run_id
    AND l.extract_expiry IS NOT NULL
    AND l.expiry_date IS NOT NULL
    AND l.extract_expiry IS DISTINCT FROM l.expiry_date;

  -- Time-respecting FIFO of the few post-cutover non-expiry burns.
  BEGIN
    FOR v_burn IN
      SELECT wl.user_id, wl.created_at, wl.id, wl.amount
      FROM wallet_ledger wl
      WHERE wl.merchant_id = p_merchant_id
        AND wl.currency = 'points'::currency
        AND wl.transaction_type = 'burn'::currency_transaction_type
        AND wl.source_type IS DISTINCT FROM 'expiry'::wallet_transaction_source_type
        AND wl.created_at > v_extract_instant
      ORDER BY wl.user_id, wl.created_at, wl.id
    LOOP
      v_need := v_burn.amount;
      FOR v_lot IN
        SELECT ledger_id, GREATEST(COALESCE(start_remaining, 0) - fifo_replay, 0) AS open_rem
        FROM hh_wallet_repair_lot
        WHERE run_id = v_run_id
          AND user_id = v_burn.user_id
          AND hold_reason IS NULL
          AND start_remaining IS NOT NULL
          AND GREATEST(COALESCE(start_remaining, 0) - fifo_replay, 0) > 0
          AND EXISTS (
            SELECT 1 FROM wallet_ledger e
            WHERE e.id = hh_wallet_repair_lot.ledger_id
              AND e.created_at <= v_burn.created_at
          )
        ORDER BY expiry_date NULLS LAST, (
          SELECT e.created_at FROM wallet_ledger e WHERE e.id = hh_wallet_repair_lot.ledger_id
        ), ledger_id
      LOOP
        EXIT WHEN v_need <= 0;
        v_take := LEAST(v_need, v_lot.open_rem);
        UPDATE hh_wallet_repair_lot
        SET fifo_replay = fifo_replay + v_take
        WHERE run_id = v_run_id AND ledger_id = v_lot.ledger_id;
        v_need := v_need - v_take;
      END LOOP;
    END LOOP;
  END;

  UPDATE hh_wallet_repair_lot
  SET target_remaining = GREATEST(start_remaining - fifo_replay, 0)
  WHERE run_id = v_run_id
    AND start_remaining IS NOT NULL
    AND hold_reason IS NULL;

  UPDATE hh_wallet_repair_lot
  SET is_future_restore = (expiry_date > DATE '2026-08-31'),
      is_legacy_expiry = (expiry_date < DATE '2026-08-10'),
      is_august = (expiry_date BETWEEN DATE '2026-08-10' AND DATE '2026-08-31')
  WHERE run_id = v_run_id;

  -- Step 1: 15 over-lotted users whose wallet equals signed ledger sum.
  INSERT INTO hh_wallet_repair_user (
    run_id, user_id, wallet_balance, current_lots, signed_sum, step1_excess, step1_eligible
  )
  SELECT
    v_run_id,
    w.user_id,
    w.points_balance,
    COALESCE(l.lot_sum, 0),
    s.signed_sum,
    GREATEST(COALESCE(l.lot_sum, 0) - w.points_balance, 0),
    (COALESCE(l.lot_sum, 0) > w.points_balance
     AND w.points_balance IS NOT DISTINCT FROM s.signed_sum)
  FROM user_wallet w
  LEFT JOIN (
    SELECT user_id, sum(deductible_balance)::int AS lot_sum
    FROM wallet_ledger
    WHERE merchant_id = p_merchant_id AND currency = 'points' AND transaction_type = 'earn'
    GROUP BY 1
  ) l ON l.user_id = w.user_id
  LEFT JOIN (
    SELECT user_id, sum(signed_amount)::int AS signed_sum
    FROM wallet_ledger
    WHERE merchant_id = p_merchant_id AND currency = 'points'
    GROUP BY 1
  ) s ON s.user_id = w.user_id
  WHERE w.merchant_id = p_merchant_id
    AND (
      COALESCE(l.lot_sum, 0) <> w.points_balance
      OR EXISTS (
        SELECT 1 FROM hh_wallet_repair_lot x
        WHERE x.run_id = v_run_id AND x.user_id = w.user_id
          AND (
            x.hold_reason IS NOT NULL
            OR x.target_remaining IS DISTINCT FROM x.current_deductible
          )
      )
    );

  -- FIFO shrink deltas for eligible step-1 users.
  BEGIN
    FOR v_u IN
      SELECT user_id, step1_excess
      FROM hh_wallet_repair_user
      WHERE run_id = v_run_id AND step1_eligible AND step1_excess > 0
    LOOP
      v_left := v_u.step1_excess;
      FOR v_lot IN
        SELECT l.ledger_id, l.current_deductible
        FROM hh_wallet_repair_lot l
        JOIN wallet_ledger e ON e.id = l.ledger_id
        WHERE l.run_id = v_run_id AND l.user_id = v_u.user_id AND l.current_deductible > 0
        ORDER BY l.expiry_date NULLS LAST, e.created_at, l.ledger_id
      LOOP
        EXIT WHEN v_left <= 0;
        v_take := LEAST(v_left, v_lot.current_deductible);
        UPDATE hh_wallet_repair_lot
        SET step1_delta = -v_take
        WHERE run_id = v_run_id AND ledger_id = v_lot.ledger_id;
        v_left := v_left - v_take;
      END LOOP;
    END LOOP;
  END;

  UPDATE hh_wallet_repair_lot l
  SET intended_after_lot_repairs = CASE
        WHEN l.hold_reason IS NOT NULL THEN l.current_deductible
        WHEN l.is_future_restore AND l.target_remaining IS NOT NULL THEN l.target_remaining
        ELSE l.current_deductible + l.step1_delta
      END,
      is_future_restore = CASE
        WHEN l.is_future_restore AND l.target_remaining IS NOT NULL
             AND l.target_remaining IS DISTINCT FROM (l.current_deductible + l.step1_delta)
        THEN true
        ELSE false
      END
  WHERE l.run_id = v_run_id;

  -- Hold processed future restores unless we can CAS-clear processed_at (proven by target > 0).
  UPDATE hh_wallet_repair_lot l
  SET hold_reason = COALESCE(l.hold_reason, 'processed_future_lot')
  WHERE l.run_id = v_run_id
    AND l.is_future_restore
    AND COALESCE(l.target_remaining, 0) > 0
    AND l.expiry_processed_at IS NOT NULL;

  INSERT INTO hh_wallet_repair_date (run_id, user_id, expiry_date, burn_amount)
  SELECT
    v_run_id, l.user_id, l.expiry_date, SUM(COALESCE(l.target_remaining, 0))::integer
  FROM hh_wallet_repair_lot l
  WHERE l.run_id = v_run_id
    AND l.is_legacy_expiry
    AND l.hold_reason IS NULL
    AND l.target_remaining IS NOT NULL
    AND l.target_remaining > 0
  GROUP BY l.user_id, l.expiry_date;

  -- Later-activity on legacy dates: any non-expiry points row after that night.
  UPDATE hh_wallet_repair_date d
  SET later_activity = true,
      hold_reason = 'later_activity'
  WHERE d.run_id = v_run_id
    AND EXISTS (
      SELECT 1 FROM wallet_ledger wl
      WHERE wl.merchant_id = p_merchant_id
        AND wl.user_id = d.user_id
        AND wl.currency = 'points'::currency
        AND wl.source_type IS DISTINCT FROM 'expiry'::wallet_transaction_source_type
        AND wl.created_at > ((d.expiry_date::timestamp + time '19:00:00') AT TIME ZONE 'UTC')
        AND COALESCE(wl.metadata->>'_repair_run_id', '') = ''
    );

  UPDATE hh_wallet_repair_user u
  SET
    expected_lots = COALESCE((
      SELECT sum(l.intended_after_lot_repairs)
      FROM hh_wallet_repair_lot l
      WHERE l.run_id = v_run_id AND l.user_id = u.user_id AND l.hold_reason IS NULL
    ), 0),
    proven_legacy_expiry = COALESCE((
      SELECT sum(d.burn_amount)
      FROM hh_wallet_repair_date d
      WHERE d.run_id = v_run_id AND d.user_id = u.user_id AND d.hold_reason IS NULL
    ), 0),
    later_activity = EXISTS (
      SELECT 1 FROM hh_wallet_repair_date d
      WHERE d.run_id = v_run_id AND d.user_id = u.user_id AND d.later_activity
    )
  WHERE u.run_id = v_run_id;

  -- Users with only future restores / legacy burns may be missing from the mismatch insert.
  INSERT INTO hh_wallet_repair_user (
    run_id, user_id, wallet_balance, current_lots, signed_sum, expected_lots, proven_legacy_expiry
  )
  SELECT
    v_run_id, l.user_id, w.points_balance, COALESCE(x.lot_sum, 0), s.signed_sum,
    SUM(l.intended_after_lot_repairs) FILTER (WHERE l.hold_reason IS NULL),
    COALESCE((
      SELECT sum(d.burn_amount) FROM hh_wallet_repair_date d
      WHERE d.run_id = v_run_id AND d.user_id = l.user_id AND d.hold_reason IS NULL
    ), 0)
  FROM hh_wallet_repair_lot l
  JOIN user_wallet w ON w.user_id = l.user_id AND w.merchant_id = p_merchant_id
  LEFT JOIN (
    SELECT user_id, sum(deductible_balance)::int AS lot_sum
    FROM wallet_ledger
    WHERE merchant_id = p_merchant_id AND currency = 'points' AND transaction_type = 'earn'
    GROUP BY 1
  ) x ON x.user_id = l.user_id
  LEFT JOIN (
    SELECT user_id, sum(signed_amount)::int AS signed_sum
    FROM wallet_ledger
    WHERE merchant_id = p_merchant_id AND currency = 'points'
    GROUP BY 1
  ) s ON s.user_id = l.user_id
  WHERE l.run_id = v_run_id
  GROUP BY l.user_id, w.points_balance, x.lot_sum, s.signed_sum
  ON CONFLICT (run_id, user_id) DO NOTHING;

  UPDATE hh_wallet_repair_user u
  SET identity_ok = (
        u.wallet_balance - COALESCE(u.expected_lots, 0) = COALESCE(u.proven_legacy_expiry, 0)
      ),
      hold_reason = CASE
        WHEN EXISTS (
          SELECT 1 FROM wallet_ledger wl
          WHERE wl.merchant_id = p_merchant_id AND wl.user_id = u.user_id
            AND wl.currency = 'points'
            AND wl.created_at > v_cutoff
        ) THEN 'stale_manifest_new_activity'
        WHEN NOT step1_eligible AND step1_excess > 0
          AND u.wallet_balance IS DISTINCT FROM u.signed_sum THEN 'wallet_ne_ledger'
        WHEN EXISTS (
          SELECT 1 FROM hh_wallet_repair_lot l
          WHERE l.run_id = v_run_id AND l.user_id = u.user_id AND l.hold_reason IS NOT NULL
            AND (
              l.is_future_restore OR l.is_legacy_expiry
              OR l.target_remaining IS DISTINCT FROM l.current_deductible
            )
        ) THEN 'lot_unproven'
        WHEN later_activity THEN 'later_activity'
        WHEN NOT (u.wallet_balance - COALESCE(u.expected_lots, 0) = COALESCE(u.proven_legacy_expiry, 0))
        THEN 'identity_mismatch'
        ELSE NULL
      END
  WHERE u.run_id = v_run_id
    AND (
      COALESCE(u.expected_lots, 0) <> u.current_lots
      OR COALESCE(u.proven_legacy_expiry, 0) <> 0
      OR u.step1_excess > 0
      OR u.later_activity
    );

  SELECT jsonb_build_object(
    'run_id', v_run_id,
    'manifest_cutoff_at', v_cutoff,
    'extract_instant', v_extract_instant,
    'extract_checksum', v_checksum,
    'lots', (SELECT count(*) FROM hh_wallet_repair_lot WHERE run_id = v_run_id),
    'held_lots', (SELECT count(*) FROM hh_wallet_repair_lot WHERE run_id = v_run_id AND hold_reason IS NOT NULL),
    'step1_eligible_users', (SELECT count(*) FROM hh_wallet_repair_user WHERE run_id = v_run_id AND step1_eligible),
    'step1_excess_pts', (SELECT coalesce(sum(step1_excess),0) FROM hh_wallet_repair_user WHERE run_id = v_run_id AND step1_eligible),
    'step1_held_users', (SELECT count(*) FROM hh_wallet_repair_user WHERE run_id = v_run_id AND step1_excess > 0 AND NOT step1_eligible),
    'future_restore_lots', (SELECT count(*) FROM hh_wallet_repair_lot WHERE run_id = v_run_id AND is_future_restore AND hold_reason IS NULL),
    'future_restore_pts', (SELECT coalesce(sum(target_remaining - (current_deductible + step1_delta)),0)
                           FROM hh_wallet_repair_lot WHERE run_id = v_run_id AND is_future_restore AND hold_reason IS NULL),
    'legacy_burn_users', (SELECT count(DISTINCT user_id) FROM hh_wallet_repair_date WHERE run_id = v_run_id AND hold_reason IS NULL),
    'legacy_burn_pts', (SELECT coalesce(sum(burn_amount),0) FROM hh_wallet_repair_date WHERE run_id = v_run_id AND hold_reason IS NULL),
    'identity_ok_users', (SELECT count(*) FROM hh_wallet_repair_user WHERE run_id = v_run_id AND identity_ok AND hold_reason IS NULL),
    'identity_hold_users', (SELECT count(*) FROM hh_wallet_repair_user WHERE run_id = v_run_id AND hold_reason IS NOT NULL),
    'aug_open_now', (
      SELECT coalesce(sum(deductible_balance),0)
      FROM wallet_ledger
      WHERE merchant_id = p_merchant_id AND currency = 'points' AND transaction_type = 'earn'
        AND expiry_date BETWEEN DATE '2026-08-10' AND DATE '2026-08-31'
    ),
    'aug_open_after_lot_repairs', (
      SELECT coalesce(sum(intended_after_lot_repairs),0)
      FROM hh_wallet_repair_lot
      WHERE run_id = v_run_id AND is_august AND hold_reason IS NULL
    )
  ) INTO v_summary;

  UPDATE hh_wallet_repair_run SET summary = v_summary WHERE id = v_run_id;
  RETURN v_summary;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_hh_repair_build_manifest(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_hh_repair_build_manifest(uuid) TO postgres, service_role;
