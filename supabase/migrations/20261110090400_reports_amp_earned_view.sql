-- Package 3: reports + AMP analytics use v_wallet_ledger_flow earned_delta / used_delta

CREATE OR REPLACE FUNCTION public.bff_report_points_snapshot(p_as_of date, p_currency text DEFAULT 'points'::text, p_ticket_type_id uuid DEFAULT NULL::uuid, p_filters jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_mid           uuid := get_current_merchant_id();
  v_tier_id       uuid := NULLIF(p_filters->>'tier_id','')::uuid;
  v_persona_id    uuid := NULLIF(p_filters->>'persona_id','')::uuid;
  v_period_start  timestamptz;
  v_period_end    timestamptz;
  v_period_start_d date;
  v_window_start_d date;
  v_window_start  timestamptz;
  v_data          jsonb;
BEGIN
  IF v_mid IS NULL THEN
    RETURN fn_response_error('Forbidden','No active merchant','FORBIDDEN', NULL);
  END IF;
  IF p_as_of IS NULL THEN
    RETURN fn_response_error('Invalid as_of','p_as_of is required','VALIDATION', NULL);
  END IF;
  IF p_currency NOT IN ('points','ticket') THEN
    RETURN fn_response_error('Invalid currency','Must be points or ticket','VALIDATION', NULL);
  END IF;

  v_period_start_d := date_trunc('month', p_as_of)::date;
  v_period_start   := (v_period_start_d::timestamp AT TIME ZONE 'Asia/Bangkok');
  v_period_end     := ((p_as_of + 1)::timestamp AT TIME ZONE 'Asia/Bangkok');
  v_window_start_d := (date_trunc('month', p_as_of) - interval '11 months')::date;
  v_window_start   := (v_window_start_d::timestamp AT TIME ZONE 'Asia/Bangkok');

  WITH
  scoped_users AS (
    SELECT id FROM user_accounts
    WHERE merchant_id = v_mid
      AND (v_tier_id    IS NULL OR tier_id    = v_tier_id)
      AND (v_persona_id IS NULL OR persona_id = v_persona_id)
  ),
  ledger_all AS (
    SELECT wl.user_id, wl.created_at, wl.signed_amount::numeric AS signed_amount,
           wl.source_type::text AS source_type,
           wl.component::text   AS component,
           wl.earned_delta::numeric AS earned_delta,
           wl.used_delta::numeric   AS used_delta
    FROM v_wallet_ledger_flow wl
    WHERE wl.merchant_id = v_mid
      AND wl.currency::text = p_currency
      AND wl.created_at < v_period_end
      AND (p_ticket_type_id IS NULL OR (p_currency='ticket' AND wl.target_entity_id = p_ticket_type_id))
      AND ((v_tier_id IS NULL AND v_persona_id IS NULL) OR EXISTS (SELECT 1 FROM scoped_users su WHERE su.id = wl.user_id))
  ),
  agg_period AS (
    SELECT
      SUM(signed_amount) FILTER (WHERE created_at <  v_period_start)                                                       AS opening,
      SUM(earned_delta) FILTER (WHERE created_at >= v_period_start)                                                          AS earned,
      abs(SUM(used_delta) FILTER (WHERE created_at >= v_period_start AND source_type <> 'expiry'))                         AS burned,
      abs(SUM(signed_amount) FILTER (WHERE created_at >= v_period_start AND source_type = 'expiry'))                        AS expired,
      SUM(signed_amount) FILTER (WHERE created_at >= v_period_start AND component = 'adjustment')                           AS adjustments,
      SUM(signed_amount) FILTER (WHERE created_at >= v_period_start AND component = 'reversal')                             AS reversals,
      SUM(signed_amount)                                                                                                    AS closing
    FROM ledger_all
  ),
  by_source AS (
    SELECT source_type,
           SUM(earned_delta)::numeric                                                                      AS earned,
           abs(SUM(used_delta) FILTER (WHERE source_type <> 'expiry'))::numeric                            AS burned,
           abs(SUM(signed_amount) FILTER (WHERE source_type = 'expiry'))::numeric                        AS expired,
           COUNT(*)::int AS txn_count
    FROM ledger_all
    WHERE created_at >= v_period_start
    GROUP BY source_type
  ),
  by_component AS (
    SELECT component, SUM(signed_amount)::numeric AS amount, COUNT(*)::int AS txn_count
    FROM ledger_all
    WHERE created_at >= v_period_start
    GROUP BY component
  ),
  per_user AS (
    SELECT user_id,
           SUM(signed_amount) FILTER (WHERE created_at <  v_period_start) AS opening,
           SUM(earned_delta) FILTER (WHERE created_at >= v_period_start) AS earned,
           abs(SUM(used_delta) FILTER (WHERE created_at >= v_period_start AND source_type <> 'expiry')) AS burned,
           abs(SUM(signed_amount) FILTER (WHERE created_at >= v_period_start AND source_type = 'expiry')) AS expired,
           SUM(signed_amount) AS closing
    FROM ledger_all
    GROUP BY user_id
  ),
  by_tier AS (
    SELECT tm.id AS tier_id, tm.tier_name,
           SUM(COALESCE(pu.opening, 0))::numeric AS opening,
           SUM(COALESCE(pu.earned,  0))::numeric AS earned,
           SUM(COALESCE(pu.burned,  0))::numeric AS burned,
           SUM(COALESCE(pu.expired, 0))::numeric AS expired,
           SUM(COALESCE(pu.closing, 0))::numeric AS closing,
           SUM(CASE WHEN p_currency='points' THEN COALESCE(uw.points_balance,0)
                    ELSE COALESCE(uw.ticket_balance,0) END)::numeric AS outstanding_liability,
           COUNT(*) FILTER (
             WHERE (p_currency='points' AND COALESCE(uw.points_balance,0) > 0)
                OR (p_currency='ticket' AND COALESCE(uw.ticket_balance,0) > 0)
           )::int AS wallets
    FROM user_wallet uw
    LEFT JOIN user_accounts ua ON ua.id = uw.user_id AND ua.merchant_id = v_mid
    LEFT JOIN tier_master tm   ON tm.id = ua.tier_id
    LEFT JOIN per_user pu      ON pu.user_id = uw.user_id
    WHERE uw.merchant_id = v_mid
      AND (v_tier_id    IS NULL OR ua.tier_id    = v_tier_id)
      AND (v_persona_id IS NULL OR ua.persona_id = v_persona_id)
    GROUP BY tm.id, tm.tier_name
  ),
  liability_total AS (
    SELECT SUM(CASE WHEN p_currency='points' THEN COALESCE(uw.points_balance,0)
                    ELSE COALESCE(uw.ticket_balance,0) END)::numeric AS outstanding_liability,
           COUNT(*) FILTER (
             WHERE (p_currency='points' AND COALESCE(uw.points_balance,0) > 0)
                OR (p_currency='ticket' AND COALESCE(uw.ticket_balance,0) > 0)
           )::int AS active_wallets
    FROM user_wallet uw
    LEFT JOIN user_accounts ua ON ua.id = uw.user_id AND ua.merchant_id = v_mid
    WHERE uw.merchant_id = v_mid
      AND (v_tier_id    IS NULL OR ua.tier_id    = v_tier_id)
      AND (v_persona_id IS NULL OR ua.persona_id = v_persona_id)
  ),
  expiry_waterfall AS (
    SELECT
      CASE
        WHEN wl.expiry_date IS NULL                  THEN 'no_expiry'
        WHEN wl.expiry_date - p_as_of <=  30         THEN '<=30d'
        WHEN wl.expiry_date - p_as_of <=  60         THEN '31-60d'
        WHEN wl.expiry_date - p_as_of <=  90         THEN '61-90d'
        WHEN wl.expiry_date - p_as_of <= 180         THEN '91-180d'
        WHEN wl.expiry_date - p_as_of <= 365         THEN '181-365d'
        ELSE                                              '>365d'
      END AS bucket,
      SUM(wl.deductible_balance)::numeric AS amount,
      COUNT(*)::int                       AS wallet_rows
    FROM wallet_ledger wl
    WHERE wl.merchant_id = v_mid
      AND wl.currency::text = p_currency
      AND wl.transaction_type::text = 'earn'
      AND wl.signed_amount > 0
      AND wl.deductible_balance > 0
      AND wl.expiry_processed_at IS NULL
      AND (wl.expiry_date IS NULL OR wl.expiry_date > p_as_of)
      AND (p_ticket_type_id IS NULL OR (p_currency='ticket' AND wl.target_entity_id = p_ticket_type_id))
      AND ((v_tier_id IS NULL AND v_persona_id IS NULL) OR EXISTS (SELECT 1 FROM scoped_users su WHERE su.id = wl.user_id))
    GROUP BY 1
  ),
  ledger_by_month AS (
    SELECT
      date_trunc('month', created_at AT TIME ZONE 'Asia/Bangkok')::date AS m_start,
      SUM(earned_delta)::numeric                                                                    AS earned_m,
      abs(SUM(used_delta) FILTER (WHERE source_type <> 'expiry'))::numeric                          AS burned_m,
      abs(SUM(signed_amount) FILTER (WHERE source_type = 'expiry'))::numeric                        AS expired_m,
      SUM(signed_amount)::numeric                                                                   AS net_m
    FROM ledger_all
    WHERE created_at >= v_window_start
    GROUP BY 1
  ),
  pre_window AS (
    SELECT COALESCE(SUM(signed_amount), 0)::numeric AS pre_balance
    FROM ledger_all
    WHERE created_at < v_window_start
  ),
  month_series AS (
    SELECT (date_trunc('month', p_as_of)::date - (n || ' months')::interval)::date AS m_start
    FROM generate_series(0, 11) n
  ),
  monthly_filled AS (
    SELECT ms.m_start,
           COALESCE(lbm.earned_m,  0) AS earned,
           COALESCE(lbm.burned_m,  0) AS burned,
           COALESCE(lbm.expired_m, 0) AS expired,
           COALESCE(lbm.net_m,     0) AS net
    FROM month_series ms
    LEFT JOIN ledger_by_month lbm ON lbm.m_start = ms.m_start
  ),
  monthly_trend AS (
    SELECT
      to_char(mf.m_start, 'YYYY-MM') AS month,
      (pw.pre_balance + COALESCE(SUM(mf.net) OVER (ORDER BY mf.m_start ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0))::numeric AS opening,
      mf.earned, mf.burned, mf.expired,
      (pw.pre_balance + SUM(mf.net) OVER (ORDER BY mf.m_start ROWS UNBOUNDED PRECEDING))::numeric                                       AS closing
    FROM monthly_filled mf
    CROSS JOIN pre_window pw
    ORDER BY mf.m_start
  )
  SELECT jsonb_build_object(
    'as_of',        to_char(p_as_of, 'YYYY-MM-DD'),
    'period_start', to_char(v_period_start_d, 'YYYY-MM-DD'),
    'currency',     p_currency,
    'aggregate', jsonb_build_object(
      'opening_balance',       COALESCE((SELECT opening FROM agg_period), 0),
      'earned',                COALESCE((SELECT earned  FROM agg_period), 0),
      'burned',                COALESCE((SELECT burned  FROM agg_period), 0),
      'expired',               COALESCE((SELECT expired FROM agg_period), 0),
      'adjustments',           COALESCE((SELECT adjustments FROM agg_period), 0),
      'reversals',             COALESCE((SELECT reversals   FROM agg_period), 0),
      'closing_balance',       COALESCE((SELECT closing FROM agg_period), 0),
      'walk_diff',             COALESCE((SELECT opening + earned - burned - expired - closing FROM agg_period), 0),
      'outstanding_liability', COALESCE((SELECT outstanding_liability FROM liability_total), 0),
      'active_wallets',        COALESCE((SELECT active_wallets        FROM liability_total), 0)
    ),
    'by_source',    COALESCE((SELECT jsonb_agg(jsonb_build_object('source_type',source_type,'earned',earned,'burned',burned,'expired',expired,'txn_count',txn_count)) FROM by_source), '[]'::jsonb),
    'by_component', COALESCE((SELECT jsonb_agg(jsonb_build_object('component',component,'amount',amount,'txn_count',txn_count)) FROM by_component), '[]'::jsonb),
    'by_tier',      COALESCE((SELECT jsonb_agg(jsonb_build_object('tier_id',tier_id,'tier_name',tier_name,'opening_balance',opening,'earned',earned,'burned',burned,'expired',expired,'closing_balance',closing,'outstanding_liability',outstanding_liability,'wallets',wallets) ORDER BY closing DESC NULLS LAST) FROM by_tier), '[]'::jsonb),
    'expiry_waterfall', jsonb_build_object(
      'as_of',  to_char(p_as_of, 'YYYY-MM-DD'),
      'buckets', COALESCE((SELECT jsonb_agg(jsonb_build_object('bucket',bucket,'amount',amount,'wallet_rows',wallet_rows) ORDER BY CASE bucket WHEN '<=30d' THEN 1 WHEN '31-60d' THEN 2 WHEN '61-90d' THEN 3 WHEN '91-180d' THEN 4 WHEN '181-365d' THEN 5 WHEN '>365d' THEN 6 WHEN 'no_expiry' THEN 7 END) FROM expiry_waterfall), '[]'::jsonb),
      'total_to_expire',     COALESCE((SELECT SUM(amount) FROM expiry_waterfall), 0),
      'reconciliation_gap',  COALESCE((SELECT SUM(amount) FROM expiry_waterfall WHERE bucket <> 'no_expiry'), 0) - COALESCE((SELECT outstanding_liability FROM liability_total), 0)
    ),
    'monthly_trend', COALESCE((SELECT jsonb_agg(jsonb_build_object('month',month,'opening',opening,'earned',earned,'burned',burned,'expired',expired,'closing',closing,'liability_eom',closing) ORDER BY month) FROM monthly_trend), '[]'::jsonb)
  ) INTO v_data;

  RETURN fn_response_success(NULL, NULL, v_data);
EXCEPTION WHEN OTHERS THEN
  RETURN fn_response_error('Snapshot failed', SQLERRM, 'INTERNAL_ERROR', NULL);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.bff_report_points_snapshot_rows(p_as_of date, p_currency text DEFAULT 'points'::text, p_ticket_type_id uuid DEFAULT NULL::uuid, p_filters jsonb DEFAULT '{}'::jsonb, p_limit integer DEFAULT 100, p_offset integer DEFAULT 0, p_sort text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_mid          uuid := get_current_merchant_id();
  v_tier_id      uuid := NULLIF(p_filters->>'tier_id','')::uuid;
  v_persona_id   uuid := NULLIF(p_filters->>'persona_id','')::uuid;
  v_period_start timestamptz;
  v_period_end   timestamptz;
  v_limit        int  := LEAST(GREATEST(COALESCE(p_limit,100),1), 50000);
  v_offset       int  := GREATEST(COALESCE(p_offset,0),0);
  v_sort_col     text;
  v_sort_dir     text;
  v_data         jsonb;
BEGIN
  IF v_mid IS NULL THEN
    RETURN fn_response_error('Forbidden','No active merchant','FORBIDDEN', NULL);
  END IF;
  IF p_currency NOT IN ('points','ticket') THEN
    RETURN fn_response_error('Invalid currency','Must be points or ticket','VALIDATION', NULL);
  END IF;

  v_period_start := (date_trunc('month', p_as_of)::timestamp AT TIME ZONE 'Asia/Bangkok');
  v_period_end   := ((p_as_of + 1)::timestamp AT TIME ZONE 'Asia/Bangkok');

  v_sort_col := lower(split_part(COALESCE(p_sort,'closing_balance desc'),' ',1));
  v_sort_dir := CASE WHEN lower(split_part(COALESCE(p_sort,'closing_balance desc'),' ',2)) = 'asc' THEN 'asc' ELSE 'desc' END;
  IF v_sort_col NOT IN ('closing_balance','earned','burned','expired','total_to_expire','member_name') THEN
    v_sort_col := 'closing_balance';
  END IF;

  WITH
  scoped_users AS (
    SELECT id, fullname, member_code, tier_id
    FROM user_accounts
    WHERE merchant_id = v_mid
      AND (v_tier_id    IS NULL OR tier_id    = v_tier_id)
      AND (v_persona_id IS NULL OR persona_id = v_persona_id)
  ),
  per_user AS (
    SELECT
      wl.user_id,
      SUM(wl.signed_amount) FILTER (WHERE wl.created_at <  v_period_start)::numeric AS opening_balance,
      SUM(wl.earned_delta) FILTER (WHERE wl.created_at >= v_period_start)::numeric AS earned,
      abs(SUM(wl.used_delta) FILTER (WHERE wl.created_at >= v_period_start AND wl.source_type::text <> 'expiry'))::numeric AS burned,
      abs(SUM(wl.signed_amount) FILTER (WHERE wl.created_at >= v_period_start AND wl.source_type::text = 'expiry'))::numeric AS expired,
      SUM(wl.signed_amount) FILTER (WHERE wl.created_at >= v_period_start AND wl.component::text = 'adjustment')::numeric AS adjustments,
      SUM(wl.signed_amount) FILTER (WHERE wl.created_at >= v_period_start AND wl.component::text = 'reversal')::numeric AS reversals,
      SUM(wl.signed_amount)::numeric AS closing_balance
    FROM v_wallet_ledger_flow wl
    WHERE wl.merchant_id = v_mid
      AND wl.currency::text = p_currency
      AND wl.created_at < v_period_end
      AND (p_ticket_type_id IS NULL OR (p_currency='ticket' AND wl.target_entity_id = p_ticket_type_id))
      AND ((v_tier_id IS NULL AND v_persona_id IS NULL) OR EXISTS (SELECT 1 FROM scoped_users su WHERE su.id = wl.user_id))
    GROUP BY wl.user_id
  ),
  expire_per_user AS (
    SELECT wl.user_id,
           SUM(CASE WHEN wl.expiry_date IS NULL THEN 0 WHEN wl.expiry_date - p_as_of <=  30 THEN wl.deductible_balance ELSE 0 END)::numeric AS to_expire_30d,
           SUM(CASE WHEN wl.expiry_date IS NULL THEN 0 WHEN wl.expiry_date - p_as_of  > 30 AND wl.expiry_date - p_as_of <=  60 THEN wl.deductible_balance ELSE 0 END)::numeric AS to_expire_60d,
           SUM(CASE WHEN wl.expiry_date IS NULL THEN 0 WHEN wl.expiry_date - p_as_of  > 60 AND wl.expiry_date - p_as_of <=  90 THEN wl.deductible_balance ELSE 0 END)::numeric AS to_expire_90d,
           SUM(CASE WHEN wl.expiry_date IS NULL THEN 0 WHEN wl.expiry_date - p_as_of  > 90 AND wl.expiry_date - p_as_of <= 180 THEN wl.deductible_balance ELSE 0 END)::numeric AS to_expire_180d,
           SUM(CASE WHEN wl.expiry_date IS NULL THEN 0 WHEN wl.expiry_date - p_as_of >180 AND wl.expiry_date - p_as_of <= 365 THEN wl.deductible_balance ELSE 0 END)::numeric AS to_expire_365d,
           SUM(CASE WHEN wl.expiry_date IS NULL THEN 0 WHEN wl.expiry_date - p_as_of >365 THEN wl.deductible_balance ELSE 0 END)::numeric AS to_expire_gt365d,
           SUM(CASE WHEN wl.expiry_date IS NULL THEN wl.deductible_balance ELSE 0 END)::numeric AS to_expire_no_expiry,
           SUM(wl.deductible_balance)::numeric AS total_to_expire
    FROM wallet_ledger wl
    WHERE wl.merchant_id = v_mid
      AND wl.currency::text = p_currency
      AND wl.transaction_type::text = 'earn'
      AND wl.signed_amount > 0
      AND wl.deductible_balance > 0
      AND wl.expiry_processed_at IS NULL
      AND (wl.expiry_date IS NULL OR wl.expiry_date > p_as_of)
      AND (p_ticket_type_id IS NULL OR (p_currency='ticket' AND wl.target_entity_id = p_ticket_type_id))
      AND ((v_tier_id IS NULL AND v_persona_id IS NULL) OR EXISTS (SELECT 1 FROM scoped_users su WHERE su.id = wl.user_id))
    GROUP BY wl.user_id
  ),
  joined AS (
    SELECT
      su.id AS user_id, su.member_code, su.fullname AS member_name, su.tier_id,
      tm.tier_name,
      COALESCE(pu.opening_balance, 0) AS opening_balance,
      COALESCE(pu.earned, 0)          AS earned,
      COALESCE(pu.burned, 0)          AS burned,
      COALESCE(pu.expired, 0)         AS expired,
      COALESCE(pu.adjustments, 0)     AS adjustments,
      COALESCE(pu.reversals, 0)       AS reversals,
      COALESCE(pu.closing_balance, 0) AS closing_balance,
      (COALESCE(pu.opening_balance,0) + COALESCE(pu.earned,0) - COALESCE(pu.burned,0) - COALESCE(pu.expired,0) - COALESCE(pu.closing_balance,0)) AS walk_diff,
      CASE WHEN p_currency='points' THEN COALESCE(uw.points_balance,0)::numeric
           ELSE COALESCE(uw.ticket_balance,0)::numeric END AS current_wallet_balance,
      (COALESCE(pu.closing_balance, 0) - CASE WHEN p_currency='points' THEN COALESCE(uw.points_balance,0)
                                              ELSE COALESCE(uw.ticket_balance,0) END) AS balance_diff,
      COALESCE(eu.to_expire_30d, 0)        AS to_expire_30d,
      COALESCE(eu.to_expire_60d, 0)        AS to_expire_60d,
      COALESCE(eu.to_expire_90d, 0)        AS to_expire_90d,
      COALESCE(eu.to_expire_180d, 0)       AS to_expire_180d,
      COALESCE(eu.to_expire_365d, 0)       AS to_expire_365d,
      COALESCE(eu.to_expire_gt365d, 0)     AS to_expire_gt365d,
      COALESCE(eu.to_expire_no_expiry, 0)  AS to_expire_no_expiry,
      COALESCE(eu.total_to_expire, 0)      AS total_to_expire,
      COUNT(*) OVER ()                     AS total_count
    FROM scoped_users su
    LEFT JOIN per_user pu        ON pu.user_id = su.id
    LEFT JOIN expire_per_user eu ON eu.user_id = su.id
    LEFT JOIN user_wallet uw     ON uw.user_id = su.id AND uw.merchant_id = v_mid
    LEFT JOIN tier_master tm     ON tm.id = su.tier_id
    WHERE pu.user_id IS NOT NULL OR eu.user_id IS NOT NULL OR uw.user_id IS NOT NULL
  ),
  ordered AS (
    SELECT * FROM joined
    ORDER BY
      CASE WHEN v_sort_col='closing_balance' AND v_sort_dir='asc'  THEN closing_balance END ASC  NULLS LAST,
      CASE WHEN v_sort_col='closing_balance' AND v_sort_dir='desc' THEN closing_balance END DESC NULLS LAST,
      CASE WHEN v_sort_col='earned'          AND v_sort_dir='asc'  THEN earned          END ASC  NULLS LAST,
      CASE WHEN v_sort_col='earned'          AND v_sort_dir='desc' THEN earned          END DESC NULLS LAST,
      CASE WHEN v_sort_col='burned'          AND v_sort_dir='asc'  THEN burned          END ASC  NULLS LAST,
      CASE WHEN v_sort_col='burned'          AND v_sort_dir='desc' THEN burned          END DESC NULLS LAST,
      CASE WHEN v_sort_col='expired'         AND v_sort_dir='asc'  THEN expired         END ASC  NULLS LAST,
      CASE WHEN v_sort_col='expired'         AND v_sort_dir='desc' THEN expired         END DESC NULLS LAST,
      CASE WHEN v_sort_col='total_to_expire' AND v_sort_dir='asc'  THEN total_to_expire END ASC  NULLS LAST,
      CASE WHEN v_sort_col='total_to_expire' AND v_sort_dir='desc' THEN total_to_expire END DESC NULLS LAST,
      CASE WHEN v_sort_col='member_name'     AND v_sort_dir='asc'  THEN member_name     END ASC  NULLS LAST,
      CASE WHEN v_sort_col='member_name'     AND v_sort_dir='desc' THEN member_name     END DESC NULLS LAST
    LIMIT v_limit OFFSET v_offset
  )
  SELECT jsonb_build_object(
    'rows', COALESCE(jsonb_agg(jsonb_build_object(
      'user_id', user_id, 'member_code', member_code, 'member_name', member_name,
      'tier_id', tier_id, 'tier_name', tier_name,
      'opening_balance', opening_balance, 'earned', earned, 'burned', burned, 'expired', expired,
      'adjustments', adjustments, 'reversals', reversals,
      'closing_balance', closing_balance, 'walk_diff', walk_diff,
      'current_wallet_balance', current_wallet_balance, 'balance_diff', balance_diff,
      'to_expire_30d', to_expire_30d, 'to_expire_60d', to_expire_60d, 'to_expire_90d', to_expire_90d,
      'to_expire_180d', to_expire_180d, 'to_expire_365d', to_expire_365d, 'to_expire_gt365d', to_expire_gt365d,
      'to_expire_no_expiry', to_expire_no_expiry, 'total_to_expire', total_to_expire
    )), '[]'::jsonb),
    'total_count', COALESCE(MAX(total_count), 0)
  )
  INTO v_data
  FROM ordered;

  RETURN fn_response_success(NULL, NULL, v_data);
EXCEPTION WHEN OTHERS THEN
  RETURN fn_response_error('Snapshot rows failed', SQLERRM, 'INTERNAL_ERROR', NULL);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.fn_amp_analysis_refresh_earn_activity(p_merchant_id uuid, p_periods integer[] DEFAULT '{30,90,180}'::integer[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_period integer;
  v_period_text text;
  v_rows integer;
  v_total integer := 0;
BEGIN
  FOREACH v_period IN ARRAY p_periods LOOP
    v_period_text := v_period || 'd';

    -- Total earn events for pct calculation
    WITH period_earn AS (
      SELECT
        wl.source_type::text                                       AS source_type,
        COUNT(*)::integer                                          AS event_count,
        COUNT(DISTINCT wl.user_id)::integer                        AS unique_earners,
        COALESCE(SUM(CASE WHEN wl.currency::text = 'points'  THEN wl.earned_delta ELSE 0 END), 0)::bigint AS total_points,
        COALESCE(SUM(CASE WHEN wl.currency::text = 'tickets' THEN wl.earned_delta ELSE 0 END), 0)::bigint AS total_tickets,
        ROUND(AVG(CASE WHEN wl.currency::text = 'points' THEN wl.earned_delta END), 2) AS avg_pts_per_event
      FROM v_wallet_ledger_flow wl
      WHERE wl.merchant_id = p_merchant_id
        AND wl.earned_delta > 0
        AND wl.created_at >= now() - (v_period || ' days')::interval
      GROUP BY wl.source_type::text
    ),
    total_events AS (
      SELECT SUM(event_count) AS grand_total FROM period_earn
    )
    INSERT INTO mv_amp_analysis_earn_activity
      (merchant_id, period, source_type, event_count, unique_earners,
       total_points_earned, total_tickets_earned, avg_points_per_event,
       pct_of_total_earn_events, last_updated_at)
    SELECT
      p_merchant_id,
      v_period_text,
      pe.source_type,
      pe.event_count,
      pe.unique_earners,
      pe.total_points,
      pe.total_tickets,
      pe.avg_pts_per_event,
      ROUND(100.0 * pe.event_count / NULLIF(te.grand_total, 0), 2),
      now()
    FROM period_earn pe, total_events te
    ON CONFLICT (merchant_id, period, source_type) DO UPDATE SET
      event_count              = EXCLUDED.event_count,
      unique_earners           = EXCLUDED.unique_earners,
      total_points_earned      = EXCLUDED.total_points_earned,
      total_tickets_earned     = EXCLUDED.total_tickets_earned,
      avg_points_per_event     = EXCLUDED.avg_points_per_event,
      pct_of_total_earn_events = EXCLUDED.pct_of_total_earn_events,
      last_updated_at          = EXCLUDED.last_updated_at;

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    v_total := v_total + v_rows;
  END LOOP;

  RETURN jsonb_build_object('rows_upserted', v_total, 'periods', p_periods);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.fn_amp_analysis_get_member_snapshot(p_merchant_id uuid, p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'user_ref',         LEFT(p_user_id::text, 8) || '-****',
    'tier_name',        tm.tier_name,
    'persona_name',     pm.persona_name,
    'user_stage',       ua.user_stage,
    'member_since',     ua.created_at,
    'days_since_join',  (CURRENT_DATE - ua.created_at::date),

    'wallet', jsonb_build_object(
      'points_balance',           uw.points_balance,
      'ticket_balance',           uw.ticket_balance,
      'lifetime_points_earned',   (
        SELECT COALESCE(SUM(wl.earned_delta), 0)
        FROM v_wallet_ledger_flow wl
        WHERE wl.merchant_id = p_merchant_id AND wl.user_id = p_user_id
      ),
      'lifetime_points_burned',   (
        SELECT COALESCE(SUM(ABS(wl.signed_amount)), 0)
        FROM wallet_ledger wl
        WHERE wl.merchant_id = p_merchant_id AND wl.user_id = p_user_id
          AND wl.source_type::text = 'reward_redemption'
      ),
      'points_expiring_30d',      (
        SELECT COALESCE(SUM(wl.amount), 0)
        FROM wallet_ledger wl
        WHERE wl.merchant_id = p_merchant_id AND wl.user_id = p_user_id
          AND wl.expiry_date IS NOT NULL
          AND wl.expiry_date <= CURRENT_DATE + 30
          AND wl.expiry_processed_at IS NULL
      )
    ),

    'activity', jsonb_build_object(
      'activity_bucket',    ma.activity_bucket,
      'days_since_last_txn', ma.days_since_last_txn,
      'txn_count_30d',      (
        SELECT COUNT(*) FROM purchase_ledger
        WHERE merchant_id = p_merchant_id AND user_id = p_user_id
          AND status = 'completed' AND transaction_date >= now() - INTERVAL '30 days'
      ),
      'txn_count_90d',      ma.txn_count_90d,
      'txn_count_lifetime', (
        SELECT COUNT(*) FROM purchase_ledger
        WHERE merchant_id = p_merchant_id AND user_id = p_user_id AND status = 'completed'
      ),
      'spend_30d',          (
        SELECT COALESCE(SUM(final_amount), 0) FROM purchase_ledger
        WHERE merchant_id = p_merchant_id AND user_id = p_user_id
          AND status = 'completed' AND transaction_date >= now() - INTERVAL '30 days'
      ),
      'spend_90d',          ma.spend_90d,
      'spend_lifetime',     ma.lifetime_spend,
      'avg_order_value',    CASE WHEN ma.txn_count_90d > 0
                              THEN ROUND(ma.spend_90d / ma.txn_count_90d, 2)
                              ELSE NULL END
    ),

    'tier_progress', jsonb_build_object(
      'next_tier_name',         next_tm.tier_name,
      'upgrade_progress_pct',   tp.upgrade_progress_percent,
      'days_until_evaluation',  (
        CASE WHEN tp.maintain_deadline IS NOT NULL
          THEN (tp.maintain_deadline - CURRENT_DATE)
          ELSE NULL
        END
      ),
      'is_at_downgrade_risk',   ma.is_at_tier_risk
    ),

    'earn_history', (
      SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
          'created_at',  wl.created_at,
          'amount',      wl.amount,
          'source_type', wl.source_type,
          'currency',    wl.currency
        ) ORDER BY wl.created_at DESC
      ), '[]'::jsonb)
      FROM (
        SELECT * FROM v_wallet_ledger_flow wl
        WHERE wl.merchant_id = p_merchant_id AND wl.user_id = p_user_id
          AND wl.earned_delta > 0
        ORDER BY wl.created_at DESC LIMIT 5
      ) wl
    ),

    'redemption_history', (
      SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
          'redeemed_at',       rrl.redeemed_at,
          'reward_id',         rrl.reward_id,
          'qty',               rrl.qty,
          'fulfillment_status', rrl.fulfillment_status,
          'cancelled',         COALESCE(rrl.cancelled, false)
        ) ORDER BY rrl.redeemed_at DESC
      ), '[]'::jsonb)
      FROM (
        SELECT * FROM reward_redemptions_ledger
        WHERE merchant_id = p_merchant_id AND user_id = p_user_id
        ORDER BY redeemed_at DESC NULLS LAST LIMIT 3
      ) rrl
    ),

    'missions', jsonb_build_object(
      'active_count',        (
        SELECT COUNT(*) FROM mission_progress mp
        JOIN mission m ON m.id = mp.mission_id AND m.merchant_id = p_merchant_id
        WHERE mp.user_id = p_user_id AND mp.is_active = true
      ),
      'completed_lifetime',  (
        SELECT COUNT(*) FROM mission_log_completion
        WHERE merchant_id = p_merchant_id AND user_id = p_user_id
      ),
      'active', (
        SELECT COALESCE(jsonb_agg(
          jsonb_build_object(
            'mission_name',          m.mission_name,
            'completion_pct',        ROUND(
              100.0 * mp.current_progress / NULLIF(mp.current_target_value, 0), 1
            ),
            'current_milestone_level', mp.current_milestone_level,
            'last_progress_at',      mp.last_progress_at
          ) ORDER BY mp.last_progress_at DESC NULLS LAST
        ), '[]'::jsonb)
        FROM mission_progress mp
        JOIN mission m ON m.id = mp.mission_id AND m.merchant_id = p_merchant_id
        WHERE mp.user_id = p_user_id AND mp.is_active = true
      )
    ),

    'referral', jsonb_build_object(
      'was_referred',    EXISTS (
        SELECT 1 FROM referral_ledger
        WHERE invitee_user_id = p_user_id AND merchant_id = p_merchant_id
      ),
      'referrals_made',  (
        SELECT COUNT(*) FROM referral_ledger
        WHERE inviter_user_id = p_user_id AND merchant_id = p_merchant_id
      )
    )
  )
  INTO v_result
  FROM user_accounts ua
  LEFT JOIN amp_analysis_member_attrs ma
    ON ma.merchant_id = p_merchant_id AND ma.user_id = p_user_id
  LEFT JOIN tier_progress tp
    ON tp.user_id = p_user_id AND tp.merchant_id = p_merchant_id
  LEFT JOIN tier_master tm ON tm.id = tp.current_tier_id
  LEFT JOIN tier_master next_tm ON next_tm.id = tp.next_tier_id
  LEFT JOIN persona_master pm ON pm.id = ua.persona_id
  LEFT JOIN user_wallet uw
    ON uw.user_id = p_user_id AND uw.merchant_id = p_merchant_id
  WHERE ua.id = p_user_id AND ua.merchant_id = p_merchant_id;

  IF v_result IS NULL THEN
    RETURN jsonb_build_object('error', 'member_not_found');
  END IF;

  RETURN v_result;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.fn_amp_analysis_refresh_member_attrs(p_merchant_id uuid, p_since timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_params          amp_analysis_params%ROWTYPE;
  v_rows_upserted   integer;
BEGIN
  INSERT INTO amp_analysis_params (merchant_id)
  VALUES (p_merchant_id)
  ON CONFLICT (merchant_id) DO NOTHING;

  SELECT * INTO v_params
  FROM amp_analysis_params
  WHERE merchant_id = p_merchant_id;

  WITH active_users AS (
    SELECT DISTINCT user_id
    FROM (
      SELECT user_id FROM purchase_ledger
      WHERE merchant_id = p_merchant_id
        AND (p_since IS NULL OR updated_at >= p_since)
      UNION
      SELECT user_id FROM wallet_ledger
      WHERE merchant_id = p_merchant_id
        AND (p_since IS NULL OR created_at >= p_since)
    ) sub
  ),
  purchase_agg AS (
    SELECT
      pl.user_id,
      MAX(pl.transaction_date)                                            AS last_txn_date,
      SUM(pl.final_amount)                                                AS lifetime_spend,
      SUM(CASE WHEN pl.transaction_date >= now() - INTERVAL '90 days'
               THEN pl.final_amount ELSE 0 END)                          AS spend_90d,
      COUNT(CASE WHEN pl.transaction_date >= now() - INTERVAL '90 days'
                 THEN 1 END)::integer                                     AS txn_count_90d
    FROM purchase_ledger pl
    WHERE pl.merchant_id = p_merchant_id
      AND pl.status = 'completed'
      AND pl.user_id IN (SELECT user_id FROM active_users)
    GROUP BY pl.user_id
  ),
  wallet_agg AS (
    SELECT
      wl.user_id,
      COUNT(CASE WHEN wl.earned_delta > 0
                      AND wl.source_type::text != 'reward_redemption' THEN 1 END)::integer  AS earn_events,
      COUNT(CASE WHEN wl.source_type::text = 'reward_redemption'      THEN 1 END)::integer  AS burn_events
    FROM v_wallet_ledger_flow wl
    WHERE wl.merchant_id = p_merchant_id
      AND wl.created_at >= now() - (v_params.engagement_window_days || ' days')::interval
      AND wl.user_id IN (SELECT user_id FROM active_users)
    GROUP BY wl.user_id
  ),
  tier_info AS (
    SELECT
      tp.user_id,
      tp.current_tier_id               AS tier_id,
      tm.tier_name,
      (
        tp.maintain_progress < v_params.tier_risk_maintain_pct_threshold
        AND tp.maintain_deadline IS NOT NULL
        AND tp.maintain_deadline <= (CURRENT_DATE + (v_params.tier_risk_days_until_eval || ' days')::interval)::date
      )                                 AS is_at_tier_risk
    FROM tier_progress tp
    JOIN tier_master tm ON tm.id = tp.current_tier_id
    WHERE tp.merchant_id = p_merchant_id
      AND tp.user_id IN (SELECT user_id FROM active_users)
  )
  INSERT INTO amp_analysis_member_attrs (
    merchant_id, user_id,
    tier_id, tier_name, persona_id,
    activity_bucket, spend_bucket, engagement_type,
    days_since_last_txn, lifetime_spend, spend_90d, txn_count_90d,
    points_balance, ticket_balance,
    has_line, has_email, has_push,
    is_at_tier_risk,
    updated_at
  )
  SELECT
    p_merchant_id,
    ua.id,
    ti.tier_id,
    ti.tier_name,
    ua.persona_id,
    CASE
      WHEN pa.last_txn_date IS NULL THEN 'never_bought'
      WHEN (CURRENT_DATE - pa.last_txn_date::date) <= v_params.active_days_max   THEN 'active'
      WHEN (CURRENT_DATE - pa.last_txn_date::date) <= v_params.at_risk_days_max  THEN 'at_risk'
      WHEN (CURRENT_DATE - pa.last_txn_date::date) <= v_params.lapsed_days_max   THEN 'lapsed'
      ELSE 'churned'
    END,
    CASE
      WHEN sq.p90_threshold IS NULL OR COALESCE(pa.lifetime_spend, 0) = 0 THEN 'low'
      WHEN pa.lifetime_spend > sq.p90_threshold THEN 'whale'
      WHEN pa.lifetime_spend > sq.p75_threshold THEN 'high'
      WHEN pa.lifetime_spend > sq.p40_threshold THEN 'mid'
      ELSE 'low'
    END,
    CASE
      WHEN COALESCE(wa.earn_events, 0) >= v_params.earn_min_events
           AND COALESCE(wa.burn_events, 0) > 0 THEN 'earn_and_burn'
      WHEN COALESCE(wa.earn_events, 0) >= v_params.earn_min_events THEN 'earn_only'
      WHEN COALESCE(wa.burn_events, 0) > 0 THEN 'burn_only'
      ELSE 'disengaged'
    END,
    CASE WHEN pa.last_txn_date IS NULL THEN NULL
         ELSE (CURRENT_DATE - pa.last_txn_date::date)
    END,
    COALESCE(pa.lifetime_spend, 0),
    COALESCE(pa.spend_90d, 0),
    COALESCE(pa.txn_count_90d, 0),
    COALESCE(uw.points_balance, 0),
    COALESCE(uw.ticket_balance, 0),
    COALESCE(ua.channel_line,  false),
    COALESCE(ua.channel_email, false),
    COALESCE(ua.channel_push,  false),
    COALESCE(ti.is_at_tier_risk, false),
    now()
  FROM user_accounts ua
  JOIN active_users au ON au.user_id = ua.id
  LEFT JOIN purchase_agg    pa ON pa.user_id = ua.id
  LEFT JOIN wallet_agg      wa ON wa.user_id = ua.id
  LEFT JOIN tier_info       ti ON ti.user_id = ua.id
  LEFT JOIN user_wallet     uw ON uw.user_id = ua.id AND uw.merchant_id = p_merchant_id
  LEFT JOIN amp_analysis_spend_quartiles sq ON sq.merchant_id = p_merchant_id
  WHERE ua.merchant_id = p_merchant_id
    AND ua.user_type = 'buyer'
  ON CONFLICT (merchant_id, user_id) DO UPDATE SET
    tier_id             = EXCLUDED.tier_id,
    tier_name           = EXCLUDED.tier_name,
    persona_id          = EXCLUDED.persona_id,
    activity_bucket     = EXCLUDED.activity_bucket,
    spend_bucket        = EXCLUDED.spend_bucket,
    engagement_type     = EXCLUDED.engagement_type,
    days_since_last_txn = EXCLUDED.days_since_last_txn,
    lifetime_spend      = EXCLUDED.lifetime_spend,
    spend_90d           = EXCLUDED.spend_90d,
    txn_count_90d       = EXCLUDED.txn_count_90d,
    points_balance      = EXCLUDED.points_balance,
    ticket_balance      = EXCLUDED.ticket_balance,
    has_line            = EXCLUDED.has_line,
    has_email           = EXCLUDED.has_email,
    has_push            = EXCLUDED.has_push,
    is_at_tier_risk     = EXCLUDED.is_at_tier_risk,
    updated_at          = EXCLUDED.updated_at;

  GET DIAGNOSTICS v_rows_upserted = ROW_COUNT;

  RETURN jsonb_build_object(
    'merchant_id',    p_merchant_id,
    'rows_upserted',  v_rows_upserted,
    'since',          p_since,
    'computed_at',    now()
  );
END;
$function$
;
