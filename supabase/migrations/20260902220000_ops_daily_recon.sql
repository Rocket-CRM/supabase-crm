-- Daily merchant ops reconciliation: compact JSON for automation / manual runs.
-- Area-first output; merchant breakdown only inside each area when something is wrong.

CREATE OR REPLACE FUNCTION public.fn_ops_daily_recon(p_day date DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_day date := COALESCE(
    p_day,
    (timezone('Asia/Bangkok', now()) - interval '1 day')::date
  );
  v_day_start timestamptz := (v_day::timestamp AT TIME ZONE 'Asia/Bangkok');
  v_day_end timestamptz := ((v_day + 1)::timestamp AT TIME ZONE 'Asia/Bangkok');
  v_baseline_start date := v_day - 28;
  v_result jsonb;
  v_status text := 'ok';
BEGIN
  WITH
  scoped AS (
    SELECT
      m.id,
      m.name,
      m.merchant_code,
      m.points_expiry_active,
      (m.mongo_id IS NOT NULL) AS migrated,
      EXISTS (
        SELECT 1
        FROM public.merchant_credentials mc
        WHERE mc.merchant_id = m.id
          AND mc.is_active
          AND mc.service_name = ANY (
            ARRAY['shopee', 'lazada', 'tiktok', 'shopify_app']::text[]
          )
      ) AS has_marketplace,
      EXISTS (
        SELECT 1
        FROM public.merchant_credentials mc
        WHERE mc.merchant_id = m.id
          AND mc.is_active
          AND mc.service_name = 'shopify_app'
      ) AS has_shopify
    FROM public.merchant_master m
    WHERE lower(m.merchant_code) <> ALL (
      ARRAY[
        'futurepark',
        'kaosmileclub',
        'rocket-demo',
        'ausiris',
        'newcrm',
        'samitivej',
        'qatest'
      ]::text[]
    )
      AND COALESCE(m.key, '') <> 'kao-smile-club'
      AND NOT (
        lower(m.merchant_code) LIKE 'qa-%'
        OR lower(m.merchant_code) LIKE '%.myshopify.com'
        OR lower(m.name) LIKE 'qa-%'
        OR lower(m.name) LIKE 'reproduce%'
        OR lower(m.name) LIKE '%newcrm%'
      )
      AND (
        m.mongo_id IS NULL
        OR lower(m.merchant_code) = ANY (
          ARRAY['herhynessreward', 'jorakay', 'kovet']::text[]
        )
      )
  ),
  migrated_ttl AS (
    SELECT *
    FROM scoped s
    WHERE lower(s.merchant_code) = ANY (
      ARRAY['herhynessreward', 'jorakay', 'kovet']::text[]
    )
  ),
  native_merchants AS (
    SELECT *
    FROM scoped s
    WHERE lower(s.merchant_code) <> ALL (
      ARRAY['herhynessreward', 'jorakay', 'kovet']::text[]
    )
  ),
  lot_sums AS (
    SELECT
      wl.user_id,
      wl.merchant_id,
      SUM(COALESCE(wl.deductible_balance, 0))::bigint AS lot_balance
    FROM public.wallet_ledger wl
    JOIN migrated_ttl s ON s.id = wl.merchant_id
    WHERE wl.currency = 'points'::public.currency
      AND wl.transaction_type = 'earn'::public.currency_transaction_type
    GROUP BY wl.user_id, wl.merchant_id
  ),
  lot_mismatch AS (
    SELECT
      s.merchant_code,
      s.name,
      COUNT(*)::integer AS mismatch_users,
      COALESCE(SUM(ABS(uw.points_balance - COALESCE(ls.lot_balance, 0))), 0)::bigint AS total_delta
    FROM migrated_ttl s
    JOIN public.user_wallet uw ON uw.merchant_id = s.id
    LEFT JOIN lot_sums ls
      ON ls.user_id = uw.user_id
     AND ls.merchant_id = uw.merchant_id
    WHERE uw.points_balance <> COALESCE(ls.lot_balance, 0)
    GROUP BY s.merchant_code, s.name
  ),
  ledger_sums AS (
    SELECT
      wl.user_id,
      wl.merchant_id,
      SUM(wl.signed_amount)::bigint AS ledger_balance
    FROM public.wallet_ledger wl
    JOIN scoped s ON s.id = wl.merchant_id
    WHERE wl.currency = 'points'::public.currency
    GROUP BY wl.user_id, wl.merchant_id
  ),
  ledger_mismatch AS (
    SELECT
      s.merchant_code,
      s.name,
      COUNT(*)::integer AS mismatch_users,
      COALESCE(SUM(ABS(uw.points_balance - COALESCE(ls.ledger_balance, 0))), 0)::bigint AS total_delta
    FROM native_merchants s
    JOIN public.user_wallet uw ON uw.merchant_id = s.id
    LEFT JOIN ledger_sums ls
      ON ls.user_id = uw.user_id
     AND ls.merchant_id = uw.merchant_id
    WHERE uw.points_balance <> COALESCE(ls.ledger_balance, 0)
    GROUP BY s.merchant_code, s.name
  ),
  ledger_audit_gap AS (
    SELECT
      s.merchant_code,
      s.name,
      COUNT(*)::integer AS gap_users,
      COALESCE(SUM(ABS(uw.points_balance - COALESCE(ls.ledger_balance, 0))), 0)::bigint AS total_delta
    FROM migrated_ttl s
    JOIN public.user_wallet uw ON uw.merchant_id = s.id
    LEFT JOIN ledger_sums ls
      ON ls.user_id = uw.user_id
     AND ls.merchant_id = uw.merchant_id
    WHERE uw.points_balance <> COALESCE(ls.ledger_balance, 0)
    GROUP BY s.merchant_code, s.name
  ),
  open_recon AS (
    SELECT
      s.merchant_code,
      s.name,
      wri.issue_type,
      COUNT(*)::integer AS open_count,
      COUNT(*) FILTER (
        WHERE wri.last_seen_at >= v_day_start
          AND wri.last_seen_at < v_day_end
      )::integer AS seen_on_day
    FROM public.wallet_reconciliation_issue wri
    JOIN scoped s ON s.id = wri.merchant_id
    WHERE wri.resolved_at IS NULL
    GROUP BY s.merchant_code, s.name, wri.issue_type
  ),
  stale_expired_lots AS (
    SELECT
      s.merchant_code,
      s.name,
      COUNT(*)::integer AS stale_lots,
      COALESCE(SUM(wl.deductible_balance), 0)::bigint AS stale_points
    FROM scoped s
    JOIN public.wallet_ledger wl ON wl.merchant_id = s.id
    WHERE s.points_expiry_active
      AND wl.currency = 'points'::public.currency
      AND wl.transaction_type = 'earn'::public.currency_transaction_type
      AND wl.expiry_date IS NOT NULL
      AND wl.expiry_date < v_day
      AND COALESCE(wl.expired_amount, 0) = 0
      AND COALESCE(wl.deductible_balance, 0) > 0
      AND wl.expiry_processed_at IS NULL
    GROUP BY s.merchant_code, s.name
    HAVING COUNT(*) > 0
  ),
  open_recon_agg AS (
    SELECT
      merchant_code,
      name,
      jsonb_object_agg(
        issue_type,
        jsonb_build_object('open', open_count, 'seen_on_day', seen_on_day)
      ) AS issues
    FROM open_recon
    GROUP BY merchant_code, name
  ),
  wallet_keys AS (
    SELECT merchant_code, name FROM lot_mismatch
    UNION
    SELECT merchant_code, name FROM ledger_mismatch
    UNION
    SELECT merchant_code, name FROM open_recon_agg
    UNION
    SELECT merchant_code, name FROM stale_expired_lots
  ),
  wallet_merchants AS (
    SELECT
      wk.merchant_code,
      wk.name,
      jsonb_strip_nulls(
        jsonb_build_object(
          'balance_vs_lots',
            CASE
              WHEN lm.mismatch_users IS NOT NULL THEN jsonb_build_object(
                'users', lm.mismatch_users,
                'total_delta', lm.total_delta
              )
            END,
          'balance_vs_ledger',
            CASE
              WHEN ldm.mismatch_users IS NOT NULL THEN jsonb_build_object(
                'users', ldm.mismatch_users,
                'total_delta', ldm.total_delta
              )
            END,
          'ledger_audit_gap',
            CASE
              WHEN lag.gap_users IS NOT NULL THEN jsonb_build_object(
                'users', lag.gap_users,
                'total_delta', lag.total_delta,
                'note', 'expected post-migration; not operational drift'
              )
            END,
          'open_recon_issues', ora.issues,
          'stale_expired_lots',
            CASE
              WHEN sel.stale_lots IS NOT NULL THEN jsonb_build_object(
                'lots', sel.stale_lots,
                'points', sel.stale_points
              )
            END
        )
      ) AS issues
    FROM wallet_keys wk
    LEFT JOIN lot_mismatch lm USING (merchant_code, name)
    LEFT JOIN ledger_mismatch ldm USING (merchant_code, name)
    LEFT JOIN ledger_audit_gap lag USING (merchant_code, name)
    LEFT JOIN open_recon_agg ora USING (merchant_code, name)
    LEFT JOIN stale_expired_lots sel USING (merchant_code, name)
    WHERE lm.mismatch_users IS NOT NULL
       OR ldm.mismatch_users IS NOT NULL
       OR ora.issues IS NOT NULL
       OR sel.stale_lots IS NOT NULL
  ),
  expiry_due AS (
    SELECT public.should_run_expiry_today(v_day) AS should_run
  ),
  expiry_log AS (
    SELECT
      epl.run_date,
      epl.error_message,
      epl.users_affected,
      epl.amount_expired,
      epl.completed_at
    FROM public.expiry_processing_log epl
    WHERE epl.run_date = v_day
    ORDER BY epl.started_at DESC
    LIMIT 1
  ),
  expiry_burn_day AS (
    SELECT COALESCE(SUM(ABS(wl.signed_amount)), 0)::bigint AS burn_total
    FROM public.wallet_ledger wl
    JOIN scoped s ON s.id = wl.merchant_id
    WHERE wl.currency = 'points'::public.currency
      AND wl.transaction_type = 'burn'::public.currency_transaction_type
      AND wl.source_type = 'expiry'::public.wallet_transaction_source_type
      AND wl.created_at >= v_day_start
      AND wl.created_at < v_day_end
  ),
  stale_tier_pending AS (
    SELECT
      s.merchant_code,
      s.name,
      COUNT(*)::integer AS stale_pending
    FROM public.tier_pending_upgrades tpu
    JOIN scoped s ON s.id = tpu.merchant_id
    WHERE tpu.effective_at < v_day
    GROUP BY s.merchant_code, s.name
  ),
  cache_jobs AS (
    SELECT
      s.merchant_code,
      s.name,
      sc.job_name,
      sc.status,
      sc.last_finished_at,
      EXTRACT(EPOCH FROM (now() - sc.last_finished_at)) / 3600.0 AS hours_since_finish
    FROM public.system_cron sc
    JOIN scoped s ON s.id = sc.merchant_id
    WHERE sc.job_name = ANY (
      ARRAY['loyalty_cache_refresh', 'loyalty_cache_daily_catchup']::text[]
    )
      AND (
        public.fn_loyalty_is_custom_tier(s.id)
        OR public.fn_loyalty_is_custom_expiry(s.id)
      )
  ),
  cache_stale AS (
    SELECT
      cj.merchant_code,
      cj.name,
      jsonb_agg(
        jsonb_build_object(
          'job', cj.job_name,
          'status', cj.status,
          'hours_since_finish', round(cj.hours_since_finish::numeric, 1)
        )
        ORDER BY cj.job_name
      ) AS cache_issues
    FROM cache_jobs cj
    WHERE cj.status IS DISTINCT FROM 'success'
       OR cj.last_finished_at IS NULL
       OR cj.last_finished_at < (now() - interval '26 hours')
    GROUP BY cj.merchant_code, cj.name
  ),
  cron_merchants AS (
    SELECT
      COALESCE(stp.merchant_code, cs.merchant_code) AS merchant_code,
      COALESCE(stp.name, cs.name) AS name,
      jsonb_strip_nulls(
        jsonb_build_object(
          'stale_tier_pending', stp.stale_pending,
          'cache_jobs', cs.cache_issues
        )
      ) AS issues
    FROM stale_tier_pending stp
    FULL OUTER JOIN cache_stale cs USING (merchant_code, name)
    WHERE stp.stale_pending IS NOT NULL
       OR cs.cache_issues IS NOT NULL
  ),
  earn_counts AS (
    SELECT
      s.merchant_code,
      s.name,
      s.has_marketplace,
      gs.day::date AS day,
      COUNT(wl.id)::numeric AS cnt
    FROM scoped s
    CROSS JOIN generate_series(v_baseline_start, v_day, interval '1 day') AS gs(day)
    LEFT JOIN public.wallet_ledger wl
      ON wl.merchant_id = s.id
     AND wl.currency = 'points'::public.currency
     AND wl.transaction_type = 'earn'::public.currency_transaction_type
     AND (timezone('Asia/Bangkok', wl.created_at))::date = gs.day::date
    GROUP BY s.merchant_code, s.name, s.has_marketplace, gs.day
  ),
  burn_counts AS (
    SELECT
      s.merchant_code,
      s.name,
      s.has_marketplace,
      gs.day::date AS day,
      COUNT(wl.id)::numeric AS cnt
    FROM scoped s
    CROSS JOIN generate_series(v_baseline_start, v_day, interval '1 day') AS gs(day)
    LEFT JOIN public.wallet_ledger wl
      ON wl.merchant_id = s.id
     AND wl.currency = 'points'::public.currency
     AND wl.transaction_type = 'burn'::public.currency_transaction_type
     AND (timezone('Asia/Bangkok', wl.created_at))::date = gs.day::date
    GROUP BY s.merchant_code, s.name, s.has_marketplace, gs.day
  ),
  purchase_counts AS (
    SELECT
      s.merchant_code,
      s.name,
      s.has_marketplace,
      gs.day::date AS day,
      COUNT(pl.id)::numeric AS cnt
    FROM scoped s
    CROSS JOIN generate_series(v_baseline_start, v_day, interval '1 day') AS gs(day)
    LEFT JOIN public.purchase_ledger pl
      ON pl.merchant_id = s.id
     AND (timezone('Asia/Bangkok', pl.created_at))::date = gs.day::date
    GROUP BY s.merchant_code, s.name, s.has_marketplace, gs.day
  ),
  mkp_counts AS (
    SELECT
      s.merchant_code,
      s.name,
      s.has_marketplace,
      gs.day::date AS day,
      COUNT(ol.id)::numeric AS cnt
    FROM scoped s
    CROSS JOIN generate_series(v_baseline_start, v_day, interval '1 day') AS gs(day)
    LEFT JOIN public.order_ledger_mkp ol
      ON ol.merchant_id = s.id
     AND (timezone('Asia/Bangkok', COALESCE(ol.updated_at, ol.transaction_date)))::date = gs.day::date
    WHERE s.has_marketplace
    GROUP BY s.merchant_code, s.name, s.has_marketplace, gs.day
  ),
  redemption_counts AS (
    SELECT
      s.merchant_code,
      s.name,
      s.has_marketplace,
      gs.day::date AS day,
      COUNT(rr.id)::numeric AS cnt
    FROM scoped s
    CROSS JOIN generate_series(v_baseline_start, v_day, interval '1 day') AS gs(day)
    LEFT JOIN public.reward_redemptions_ledger rr
      ON rr.merchant_id = s.id
     AND (timezone('Asia/Bangkok', rr.created_at))::date = gs.day::date
    GROUP BY s.merchant_code, s.name, s.has_marketplace, gs.day
  ),
  receipt_counts AS (
    SELECT
      s.merchant_code,
      s.name,
      s.has_marketplace,
      gs.day::date AS day,
      COUNT(pr.id)::numeric AS cnt
    FROM scoped s
    CROSS JOIN generate_series(v_baseline_start, v_day, interval '1 day') AS gs(day)
    LEFT JOIN public.purchase_receipt_upload pr
      ON pr.merchant_id = s.id
     AND (timezone('Asia/Bangkok', pr.created_at))::date = gs.day::date
    GROUP BY s.merchant_code, s.name, s.has_marketplace, gs.day
  ),
  daily_metric AS (
    SELECT merchant_code, name, has_marketplace, 'earn' AS metric,
      MAX(cnt) FILTER (WHERE day = v_day) AS day_count,
      percentile_cont(0.5) WITHIN GROUP (ORDER BY cnt) FILTER (WHERE day < v_day) AS baseline_median
    FROM earn_counts
    GROUP BY merchant_code, name, has_marketplace
    UNION ALL
    SELECT merchant_code, name, has_marketplace, 'burn',
      MAX(cnt) FILTER (WHERE day = v_day),
      percentile_cont(0.5) WITHIN GROUP (ORDER BY cnt) FILTER (WHERE day < v_day)
    FROM burn_counts
    GROUP BY merchant_code, name, has_marketplace
    UNION ALL
    SELECT merchant_code, name, has_marketplace, 'purchases',
      MAX(cnt) FILTER (WHERE day = v_day),
      percentile_cont(0.5) WITHIN GROUP (ORDER BY cnt) FILTER (WHERE day < v_day)
    FROM purchase_counts
    GROUP BY merchant_code, name, has_marketplace
    UNION ALL
    SELECT merchant_code, name, has_marketplace, 'mkp_orders',
      MAX(cnt) FILTER (WHERE day = v_day),
      percentile_cont(0.5) WITHIN GROUP (ORDER BY cnt) FILTER (WHERE day < v_day)
    FROM mkp_counts
    GROUP BY merchant_code, name, has_marketplace
    UNION ALL
    SELECT merchant_code, name, has_marketplace, 'redemptions',
      MAX(cnt) FILTER (WHERE day = v_day),
      percentile_cont(0.5) WITHIN GROUP (ORDER BY cnt) FILTER (WHERE day < v_day)
    FROM redemption_counts
    GROUP BY merchant_code, name, has_marketplace
    UNION ALL
    SELECT merchant_code, name, has_marketplace, 'receipt_uploads',
      MAX(cnt) FILTER (WHERE day = v_day),
      percentile_cont(0.5) WITHIN GROUP (ORDER BY cnt) FILTER (WHERE day < v_day)
    FROM receipt_counts
    GROUP BY merchant_code, name, has_marketplace
  ),
  silence_flags AS (
    SELECT
      dm.merchant_code,
      dm.name,
      jsonb_agg(
        jsonb_build_object(
          'metric', dm.metric,
          'day_count', dm.day_count,
          'baseline_median', round(COALESCE(dm.baseline_median, 0)::numeric, 1)
        )
        ORDER BY dm.metric
      ) AS silent_metrics
    FROM daily_metric dm
    WHERE dm.day_count = 0
      AND COALESCE(dm.baseline_median, 0) >= 1
      AND NOT (dm.metric = 'mkp_orders' AND NOT dm.has_marketplace)
    GROUP BY dm.merchant_code, dm.name
  ),
  mkp_errors AS (
    SELECT
      s.merchant_code,
      s.name,
      COUNT(*)::integer AS error_events
    FROM public.marketplace_connect_events mce
    JOIN scoped s ON s.id = mce.merchant_id
    WHERE mce.created_at >= v_day_start
      AND mce.created_at < v_day_end
      AND mce.outcome IS DISTINCT FROM 'success'
    GROUP BY s.merchant_code, s.name
    HAVING COUNT(*) > 0
  ),
  cred_unhealthy AS (
    SELECT
      s.merchant_code,
      s.name,
      COUNT(*)::integer AS unhealthy_credentials
    FROM public.merchant_credentials mc
    JOIN scoped s ON s.id = mc.merchant_id
    WHERE mc.is_active
      AND (
        lower(COALESCE(mc.health_status, '')) IN ('unhealthy', 'error', 'failed')
        OR (mc.expires_at IS NOT NULL AND mc.expires_at < now() + interval '3 days')
      )
    GROUP BY s.merchant_code, s.name
    HAVING COUNT(*) > 0
  ),
  stuck_earn AS (
    SELECT
      s.merchant_code,
      s.name,
      COUNT(*)::integer AS stuck_purchases
    FROM public.purchase_ledger pl
    JOIN scoped s ON s.id = pl.merchant_id
    WHERE pl.earn_currency = true
      AND pl.currency_processed_at IS NULL
      AND pl.created_at < now() - interval '6 hours'
      AND pl.status = 'completed'::public.purchase_status
    GROUP BY s.merchant_code, s.name
    HAVING COUNT(*) > 0
  ),
  failed_redemptions AS (
    SELECT
      s.merchant_code,
      s.name,
      COUNT(*)::integer AS failed_count
    FROM public.reward_redemptions_ledger rr
    JOIN scoped s ON s.id = rr.merchant_id
    WHERE rr.created_at >= v_day_start
      AND rr.created_at < v_day_end
      AND rr.success = false
    GROUP BY s.merchant_code, s.name
  ),
  pipeline_merchants AS (
    SELECT
      COALESCE(me.merchant_code, cu.merchant_code, se.merchant_code, fr.merchant_code) AS merchant_code,
      COALESCE(me.name, cu.name, se.name, fr.name) AS name,
      jsonb_strip_nulls(
        jsonb_build_object(
          'marketplace_errors', me.error_events,
          'unhealthy_credentials', cu.unhealthy_credentials,
          'stuck_earn_purchases', se.stuck_purchases,
          'failed_redemptions', fr.failed_count
        )
      ) AS issues
    FROM mkp_errors me
    FULL OUTER JOIN cred_unhealthy cu USING (merchant_code, name)
    FULL OUTER JOIN stuck_earn se USING (merchant_code, name)
    FULL OUTER JOIN failed_redemptions fr USING (merchant_code, name)
    WHERE me.error_events IS NOT NULL
       OR cu.unhealthy_credentials IS NOT NULL
       OR se.stuck_purchases IS NOT NULL
       OR fr.failed_count IS NOT NULL
  ),
  outbox_backlog AS (
    SELECT COUNT(*)::integer AS unpublished
    FROM public.chokepoint_event_outbox
    WHERE published_at IS NULL
      AND created_at < now() - interval '15 minutes'
  ),
  scoped_count AS (
    SELECT COUNT(*)::integer AS n FROM scoped
  )
  SELECT jsonb_build_object(
    'day', v_day,
    'generated_at', timezone('Asia/Bangkok', now()),
    'scope', jsonb_build_object(
      'merchant_count', (SELECT n FROM scoped_count),
      'day_window_bkk', jsonb_build_array(v_day_start, v_day_end),
      'migrated_allowlist', jsonb_build_array('herhynessreward', 'jorakay', 'kovet'),
      'always_excluded', jsonb_build_array(
        'futurepark', 'kaosmileclub', 'rocket-demo',
        'ausiris', 'newcrm', 'samitivej', 'qatest', 'qa-*'
      )
    ),
    'areas', jsonb_build_object(
      'wallet_integrity', jsonb_build_object(
        'status',
          CASE
            WHEN EXISTS (SELECT 1 FROM wallet_merchants) THEN 'warn'
            ELSE 'ok'
          END,
        'merchants', COALESCE(
          (
            SELECT jsonb_agg(
              jsonb_build_object(
                'merchant_code', wm.merchant_code,
                'name', wm.name,
                'issues', wm.issues
              )
              ORDER BY wm.name
            )
            FROM wallet_merchants wm
          ),
          '[]'::jsonb
        )
      ),
      'daily_crons', jsonb_build_object(
        'status',
          CASE
            WHEN (SELECT error_message FROM expiry_log) IS NOT NULL
              OR (
                (SELECT should_run FROM expiry_due)
                AND NOT EXISTS (SELECT 1 FROM expiry_log)
              )
              OR EXISTS (SELECT 1 FROM cron_merchants)
              OR EXISTS (SELECT 1 FROM stale_tier_pending)
              OR (SELECT unpublished FROM outbox_backlog) > 0
            THEN 'warn'
            ELSE 'ok'
          END,
        'global', jsonb_strip_nulls(
          jsonb_build_object(
            'currency_expiry_log',
              CASE
                WHEN NOT EXISTS (SELECT 1 FROM expiry_log) THEN jsonb_build_object(
                  'status',
                    CASE
                      WHEN (SELECT should_run FROM expiry_due) THEN 'missing'
                      ELSE 'skipped'
                    END,
                  'run_date', v_day
                )
                WHEN (SELECT error_message FROM expiry_log) IS NOT NULL THEN jsonb_build_object(
                  'status', 'error',
                  'run_date', v_day,
                  'error', (SELECT error_message FROM expiry_log)
                )
                ELSE jsonb_build_object(
                  'status', 'ok',
                  'run_date', v_day,
                  'users_affected', (SELECT users_affected FROM expiry_log),
                  'amount_expired', (SELECT amount_expired FROM expiry_log),
                  'burn_on_day', (SELECT burn_total FROM expiry_burn_day)
                )
              END,
            'chokepoint_outbox_unpublished_15m',
              (SELECT unpublished FROM outbox_backlog),
            'tier_pending_stale_total',
              COALESCE((SELECT SUM(stale_pending) FROM stale_tier_pending), 0)
          )
        ),
        'merchants', COALESCE(
          (
            SELECT jsonb_agg(
              jsonb_build_object(
                'merchant_code', cm.merchant_code,
                'name', cm.name,
                'issues', cm.issues
              )
              ORDER BY cm.name
            )
            FROM cron_merchants cm
          ),
          '[]'::jsonb
        )
      ),
      'activity_silence', jsonb_build_object(
        'status',
          CASE
            WHEN EXISTS (SELECT 1 FROM silence_flags) THEN 'warn'
            ELSE 'ok'
          END,
        'merchants', COALESCE(
          (
            SELECT jsonb_agg(
              jsonb_build_object(
                'merchant_code', sf.merchant_code,
                'name', sf.name,
                'silent_metrics', sf.silent_metrics
              )
              ORDER BY sf.name
            )
            FROM silence_flags sf
          ),
          '[]'::jsonb
        )
      ),
      'pipeline_health', jsonb_build_object(
        'status',
          CASE
            WHEN EXISTS (SELECT 1 FROM pipeline_merchants) THEN 'warn'
            ELSE 'ok'
          END,
        'merchants', COALESCE(
          (
            SELECT jsonb_agg(
              jsonb_build_object(
                'merchant_code', pm.merchant_code,
                'name', pm.name,
                'issues', pm.issues
              )
              ORDER BY pm.name
            )
            FROM pipeline_merchants pm
          ),
          '[]'::jsonb
        )
      )
    )
  )
  INTO v_result
  FROM scoped_count;

  IF v_result #>> '{areas,wallet_integrity,status}' = 'warn'
     OR v_result #>> '{areas,daily_crons,status}' = 'warn'
     OR v_result #>> '{areas,activity_silence,status}' = 'warn'
     OR v_result #>> '{areas,pipeline_health,status}' = 'warn' THEN
    v_status := 'warn';
  END IF;

  IF v_result #>> '{areas,daily_crons,global,currency_expiry_log,status}' = 'error' THEN
    v_status := 'error';
  END IF;

  RETURN v_result || jsonb_build_object('status', v_status);
END;
$function$;

COMMENT ON FUNCTION public.fn_ops_daily_recon(date) IS
  'Daily ops reconciliation for live merchants. Area-first JSON: wallet_integrity, daily_crons, activity_silence, pipeline_health.';

REVOKE ALL ON FUNCTION public.fn_ops_daily_recon(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_ops_daily_recon(date) TO service_role, authenticated;
