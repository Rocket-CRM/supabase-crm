-- Audience reports: compute metrics for baseline + all requested audiences in one pass

DROP FUNCTION IF EXISTS public.fn_report_audience_metrics(uuid, uuid, timestamp with time zone, timestamp with time zone);

CREATE OR REPLACE FUNCTION public.fn_report_audience_metrics(
  p_merchant_id uuid,
  p_audience_ids uuid[],
  p_from timestamp with time zone,
  p_to timestamp with time zone
)
RETURNS TABLE(audience_id uuid, metrics jsonb)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH facts AS (
    SELECT
      ua.id AS user_id,
      (
        ua.line_id IS NOT NULL
        AND btrim(ua.line_id) <> ''
        AND COALESCE(ua.channel_line, true) IS NOT FALSE
      ) AS line_ok,
      uw.points_balance AS points,
      b.revenue,
      (b.user_id IS NOT NULL) AS bought,
      (rd.user_id IS NOT NULL) AS redeemed
    FROM user_accounts ua
    LEFT JOIN user_wallet uw ON uw.user_id = ua.id AND uw.merchant_id = p_merchant_id
    LEFT JOIN (
      SELECT pl.user_id, SUM(pl.final_amount) AS revenue
      FROM purchase_ledger pl
      WHERE pl.merchant_id = p_merchant_id
        AND pl.status = 'completed'::purchase_status
        AND pl.transaction_date >= p_from
        AND pl.transaction_date < p_to
        AND pl.user_id IS NOT NULL
      GROUP BY pl.user_id
    ) b ON b.user_id = ua.id
    LEFT JOIN (
      SELECT DISTINCT r.user_id
      FROM reward_redemptions_ledger r
      WHERE r.merchant_id = p_merchant_id
        AND r.redeemed_at >= p_from
        AND r.redeemed_at < p_to
    ) rd ON rd.user_id = ua.id
    WHERE ua.merchant_id = p_merchant_id
      AND ua.deleted_at IS NULL
  ),
  scoped AS (
    SELECT NULL::uuid AS audience_id, f.* FROM facts f
    UNION ALL
    SELECT am.audience_id, f.*
    FROM amp_audience_member am
    JOIN facts f ON f.user_id = am.user_id
    WHERE am.audience_id = ANY (p_audience_ids)
      AND am.exited_at IS NULL
  ),
  agg AS (
    SELECT
      s.audience_id,
      count(*)::bigint AS members,
      count(*) FILTER (WHERE s.line_ok)::bigint AS line_reachable,
      avg(s.points)::numeric AS avg_points,
      count(*) FILTER (WHERE s.bought)::bigint AS buyers,
      COALESCE(sum(s.revenue), 0)::numeric AS revenue,
      count(*) FILTER (WHERE s.redeemed)::bigint AS redeemers
    FROM scoped s
    GROUP BY s.audience_id
  ),
  moves AS (
    SELECT
      am.audience_id,
      count(*) FILTER (WHERE am.entered_at >= p_from AND am.entered_at < p_to)::bigint AS joined,
      count(*) FILTER (WHERE am.exited_at >= p_from AND am.exited_at < p_to)::bigint AS left_count
    FROM amp_audience_member am
    WHERE am.audience_id = ANY (p_audience_ids)
    GROUP BY am.audience_id
  ),
  base_joined AS (
    SELECT count(*)::bigint AS joined
    FROM user_accounts ua
    WHERE ua.merchant_id = p_merchant_id
      AND ua.deleted_at IS NULL
      AND COALESCE(ua.acquired_at, ua.created_at) >= p_from
      AND COALESCE(ua.acquired_at, ua.created_at) < p_to
  ),
  keys AS (
    SELECT NULL::uuid AS audience_id
    UNION
    SELECT unnest(p_audience_ids)
  )
  SELECT
    k.audience_id,
    jsonb_build_object(
      'members', COALESCE(a.members, 0),
      'joined', CASE WHEN k.audience_id IS NULL THEN bj.joined ELSE COALESCE(mv.joined, 0) END,
      'left', CASE WHEN k.audience_id IS NULL THEN NULL ELSE COALESCE(mv.left_count, 0) END,
      'line_reachable', COALESCE(a.line_reachable, 0),
      'line_reachable_pct', CASE WHEN COALESCE(a.members, 0) > 0 THEN ROUND(100.0 * a.line_reachable / a.members, 1) ELSE 0 END,
      'buyers', COALESCE(a.buyers, 0),
      'buyers_pct', CASE WHEN COALESCE(a.members, 0) > 0 THEN ROUND(100.0 * a.buyers / a.members, 1) ELSE 0 END,
      'revenue', ROUND(COALESCE(a.revenue, 0), 2),
      'revenue_per_member', CASE WHEN COALESCE(a.members, 0) > 0 THEN ROUND(a.revenue / a.members, 2) ELSE 0 END,
      'avg_points_balance', ROUND(COALESCE(a.avg_points, 0), 2),
      'redeemers', COALESCE(a.redeemers, 0),
      'redeemers_pct', CASE WHEN COALESCE(a.members, 0) > 0 THEN ROUND(100.0 * a.redeemers / a.members, 1) ELSE 0 END
    )
  FROM keys k
  CROSS JOIN base_joined bj
  LEFT JOIN agg a ON a.audience_id IS NOT DISTINCT FROM k.audience_id
  LEFT JOIN moves mv ON mv.audience_id = k.audience_id;
$function$;

REVOKE EXECUTE ON FUNCTION public.fn_report_audience_metrics(uuid, uuid[], timestamp with time zone, timestamp with time zone) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.bff_report_audience_compare(
  p_from timestamp with time zone,
  p_to timestamp with time zone
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_mid uuid := get_current_merchant_id();
  v_ids uuid[];
  v_all jsonb;
  v_baseline jsonb;
  v_baseline_revenue numeric;
  v_audiences jsonb;
BEGIN
  IF v_mid IS NULL THEN
    RETURN fn_response_error('Forbidden', 'No active merchant', 'FORBIDDEN', NULL);
  END IF;

  IF p_from IS NULL OR p_to IS NULL OR p_from >= p_to THEN
    RETURN fn_response_error('Invalid range', 'p_from/p_to required as half-open [from, to)', 'VALIDATION', NULL);
  END IF;

  SELECT COALESCE(array_agg(a.id), '{}'::uuid[])
  INTO v_ids
  FROM amp_audience_master a
  WHERE a.merchant_id = v_mid
    AND (
      a.is_active
      OR EXISTS (
        SELECT 1
        FROM amp_audience_member am
        WHERE am.audience_id = a.id
          AND am.exited_at IS NULL
      )
    );

  SELECT jsonb_object_agg(COALESCE(m.audience_id::text, 'baseline'), m.metrics)
  INTO v_all
  FROM fn_report_audience_metrics(v_mid, v_ids, p_from, p_to) m;

  v_baseline := v_all -> 'baseline';
  v_baseline_revenue := COALESCE((v_baseline ->> 'revenue')::numeric, 0);

  SELECT COALESCE(jsonb_agg(row_data ORDER BY (row_data ->> 'members')::bigint DESC), '[]'::jsonb)
  INTO v_audiences
  FROM (
    SELECT
      jsonb_build_object(
        'audience_id', a.id,
        'name', a.name,
        'audience_type', a.audience_type,
        'is_active', a.is_active
      )
      || (v_all -> (a.id::text))
      || jsonb_build_object(
        'revenue_share_pct', CASE
          WHEN v_baseline_revenue > 0 THEN
            ROUND(100.0 * COALESCE((v_all -> (a.id::text) ->> 'revenue')::numeric, 0) / v_baseline_revenue, 1)
          ELSE 0
        END
      ) AS row_data
    FROM amp_audience_master a
    WHERE a.id = ANY (v_ids)
  ) x;

  RETURN fn_response_success(
    'Audience compare report',
    NULL,
    jsonb_build_object(
      'baseline', v_baseline,
      'audiences', v_audiences
    )
  );
EXCEPTION WHEN OTHERS THEN
  RETURN fn_response_error('Audience compare report failed', SQLERRM, 'INTERNAL_ERROR', NULL);
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_report_audience(
  p_audience_id uuid,
  p_from timestamp with time zone,
  p_to timestamp with time zone,
  p_frequency text DEFAULT 'day'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_mid uuid := get_current_merchant_id();
  v_audience RECORD;
  v_freq text := lower(COALESCE(NULLIF(p_frequency, ''), 'day'));
  v_step interval;
  v_metrics jsonb;
  v_baseline jsonb;
  v_size_series jsonb;
  v_revenue_series jsonb;
  v_tier_mix jsonb;
  v_rfm_mix jsonb;
  v_broadcasts jsonb;
  v_rfm_active boolean := false;
  v_all jsonb;
BEGIN
  IF v_mid IS NULL THEN
    RETURN fn_response_error('Forbidden', 'No active merchant', 'FORBIDDEN', NULL);
  END IF;

  IF p_from IS NULL OR p_to IS NULL OR p_from >= p_to THEN
    RETURN fn_response_error('Invalid range', 'p_from/p_to required as half-open [from, to)', 'VALIDATION', NULL);
  END IF;

  IF v_freq NOT IN ('day', 'week', 'month', 'quarter') THEN
    RETURN fn_response_error('Invalid frequency', 'Must be day/week/month/quarter', 'VALIDATION', NULL);
  END IF;

  SELECT * INTO v_audience
  FROM amp_audience_master
  WHERE id = p_audience_id AND merchant_id = v_mid;

  IF NOT FOUND THEN
    RETURN fn_response_error('Not found', 'Audience not found or access denied', 'NOT_FOUND', NULL);
  END IF;

  v_step := CASE v_freq
    WHEN 'day' THEN interval '1 day'
    WHEN 'week' THEN interval '1 week'
    WHEN 'month' THEN interval '1 month'
    ELSE interval '3 months'
  END;

  SELECT COALESCE(c.is_active, false)
  INTO v_rfm_active
  FROM rfm_config c
  WHERE c.merchant_id = v_mid;

  SELECT jsonb_object_agg(COALESCE(m.audience_id::text, 'baseline'), m.metrics)
  INTO v_all
  FROM fn_report_audience_metrics(v_mid, ARRAY[p_audience_id], p_from, p_to) m;
  v_metrics := v_all -> (p_audience_id::text);
  v_baseline := v_all -> 'baseline';

  PERFORM set_config('enable_nestloop', 'off', true);

  WITH buckets AS (
    SELECT
      gs::date AS bucket_date,
      (gs::timestamp AT TIME ZONE 'Asia/Bangkok') AS bucket_start,
      ((gs + v_step)::timestamp AT TIME ZONE 'Asia/Bangkok') AS bucket_end
    FROM generate_series(
      date_trunc(v_freq, (p_from AT TIME ZONE 'Asia/Bangkok')::timestamp),
      date_trunc(v_freq, ((p_to - interval '1 microsecond') AT TIME ZONE 'Asia/Bangkok')::timestamp),
      v_step
    ) gs
  ),
  size_rows AS (
    SELECT
      b.bucket_date,
      count(*) FILTER (
        WHERE am.entered_at <= b.bucket_end
          AND (am.exited_at IS NULL OR am.exited_at > b.bucket_end)
      )::bigint AS members,
      count(*) FILTER (
        WHERE am.entered_at >= b.bucket_start AND am.entered_at < b.bucket_end
      )::bigint AS joined,
      count(*) FILTER (
        WHERE am.exited_at IS NOT NULL
          AND am.exited_at >= b.bucket_start
          AND am.exited_at < b.bucket_end
      )::bigint AS left
    FROM buckets b
    CROSS JOIN amp_audience_member am
    WHERE am.audience_id = p_audience_id
    GROUP BY b.bucket_date, b.bucket_start, b.bucket_end
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'bucket', to_char(sr.bucket_date, 'YYYY-MM-DD'),
    'members', sr.members,
    'joined', sr.joined,
    'left', sr.left
  ) ORDER BY sr.bucket_date), '[]'::jsonb)
  INTO v_size_series
  FROM size_rows sr;

  WITH members AS (
    SELECT ua.id AS user_id
    FROM user_accounts ua
    JOIN amp_audience_member am
      ON am.user_id = ua.id
      AND am.audience_id = p_audience_id
      AND am.exited_at IS NULL
    WHERE ua.merchant_id = v_mid
      AND ua.deleted_at IS NULL
  ),
  buckets AS (
    SELECT
      gs::date AS bucket_date,
      (gs::timestamp AT TIME ZONE 'Asia/Bangkok') AS bucket_start,
      ((gs + v_step)::timestamp AT TIME ZONE 'Asia/Bangkok') AS bucket_end
    FROM generate_series(
      date_trunc(v_freq, (p_from AT TIME ZONE 'Asia/Bangkok')::timestamp),
      date_trunc(v_freq, ((p_to - interval '1 microsecond') AT TIME ZONE 'Asia/Bangkok')::timestamp),
      v_step
    ) gs
  ),
  purchase_bucket AS (
    SELECT
      date_trunc(v_freq, (pl.transaction_date AT TIME ZONE 'Asia/Bangkok'))::date AS bucket_date,
      COALESCE(SUM(pl.final_amount), 0)::numeric AS revenue,
      count(DISTINCT pl.user_id)::bigint AS buyers
    FROM purchase_ledger pl
    WHERE pl.merchant_id = v_mid
      AND pl.status = 'completed'::purchase_status
      AND pl.transaction_date >= p_from
      AND pl.transaction_date < p_to
      AND pl.user_id IN (SELECT user_id FROM members)
    GROUP BY 1
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'bucket', to_char(b.bucket_date, 'YYYY-MM-DD'),
    'revenue', ROUND(COALESCE(pb.revenue, 0), 2),
    'buyers', COALESCE(pb.buyers, 0)
  ) ORDER BY b.bucket_date), '[]'::jsonb)
  INTO v_revenue_series
  FROM buckets b
  LEFT JOIN purchase_bucket pb ON pb.bucket_date = b.bucket_date;

  WITH aud AS (
    SELECT ua.tier_id, count(*)::numeric AS n
    FROM user_accounts ua
    JOIN amp_audience_member am
      ON am.user_id = ua.id
      AND am.audience_id = p_audience_id
      AND am.exited_at IS NULL
    WHERE ua.merchant_id = v_mid
      AND ua.deleted_at IS NULL
    GROUP BY ua.tier_id
  ),
  base AS (
    SELECT ua.tier_id, count(*)::numeric AS n
    FROM user_accounts ua
    WHERE ua.merchant_id = v_mid
      AND ua.deleted_at IS NULL
    GROUP BY ua.tier_id
  ),
  totals AS (
    SELECT
      (SELECT COALESCE(sum(n), 0) FROM aud) AS aud_n,
      (SELECT COALESCE(sum(n), 0) FROM base) AS base_n
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'tier_id', k.tier_id,
    'tier_name', COALESCE(tm.tier_name, 'No tier'),
    'audience_pct', CASE
      WHEN t.aud_n > 0 THEN ROUND(100.0 * COALESCE(a.n, 0) / t.aud_n, 1)
      ELSE 0
    END,
    'baseline_pct', CASE
      WHEN t.base_n > 0 THEN ROUND(100.0 * COALESCE(b.n, 0) / t.base_n, 1)
      ELSE 0
    END
  ) ORDER BY COALESCE(tm.tier_name, 'No tier')), '[]'::jsonb)
  INTO v_tier_mix
  FROM (SELECT tier_id FROM aud UNION SELECT tier_id FROM base) k
  CROSS JOIN totals t
  LEFT JOIN aud a ON a.tier_id IS NOT DISTINCT FROM k.tier_id
  LEFT JOIN base b ON b.tier_id IS NOT DISTINCT FROM k.tier_id
  LEFT JOIN tier_master tm ON tm.id = k.tier_id AND tm.merchant_id = v_mid;

  IF v_rfm_active THEN
    WITH aud AS (
      SELECT COALESCE(s.rfm_segment, 'Unsegmented') AS segment, count(*)::numeric AS n
      FROM amp_audience_member am
      JOIN user_accounts ua ON ua.id = am.user_id AND ua.merchant_id = v_mid AND ua.deleted_at IS NULL
      JOIN rfm_user_score s ON s.user_id = am.user_id AND s.merchant_id = v_mid
      WHERE am.audience_id = p_audience_id
        AND am.exited_at IS NULL
      GROUP BY 1
    ),
    base AS (
      SELECT COALESCE(s.rfm_segment, 'Unsegmented') AS segment, count(*)::numeric AS n
      FROM user_accounts ua
      JOIN rfm_user_score s ON s.user_id = ua.id AND s.merchant_id = v_mid
      WHERE ua.merchant_id = v_mid
        AND ua.deleted_at IS NULL
      GROUP BY 1
    ),
    totals AS (
      SELECT
        (SELECT COALESCE(sum(n), 0) FROM aud) AS aud_n,
        (SELECT COALESCE(sum(n), 0) FROM base) AS base_n
    )
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'segment', k.segment,
      'audience_pct', CASE
        WHEN t.aud_n > 0 THEN ROUND(100.0 * COALESCE(a.n, 0) / t.aud_n, 1)
        ELSE 0
      END,
      'baseline_pct', CASE
        WHEN t.base_n > 0 THEN ROUND(100.0 * COALESCE(b.n, 0) / t.base_n, 1)
        ELSE 0
      END
    ) ORDER BY k.segment), '[]'::jsonb)
    INTO v_rfm_mix
    FROM (SELECT segment FROM aud UNION SELECT segment FROM base) k
    CROSS JOIN totals t
    LEFT JOIN aud a ON a.segment = k.segment
    LEFT JOIN base b ON b.segment = k.segment;
  ELSE
    v_rfm_mix := NULL;
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'broadcast_id', b.id,
    'name', b.name,
    'status', b.status,
    'sent_at', b.sent_at,
    'recipient_count', COALESCE(b.recipient_count, 0),
    'sent_count', COALESCE(b.sent_count, 0),
    'failed_count', COALESCE(b.failed_count, 0),
    'unique_clickers', COALESCE(clk.unique_clickers, 0),
    'click_rate_pct', CASE
      WHEN COALESCE(b.sent_count, 0) > 0 THEN
        ROUND(100.0 * COALESCE(clk.unique_clickers, 0) / b.sent_count, 1)
      ELSE 0
    END
  ) ORDER BY b.sent_at DESC NULLS LAST, b.created_at DESC), '[]'::jsonb)
  INTO v_broadcasts
  FROM (
    SELECT *
    FROM amp_broadcast_master
    WHERE merchant_id = v_mid
      AND audience_id = p_audience_id
    ORDER BY sent_at DESC NULLS LAST, created_at DESC
    LIMIT 20
  ) b
  LEFT JOIN LATERAL (
    SELECT count(DISTINCT COALESCE(e.user_id::text, e.line_user_id))::bigint AS unique_clickers
    FROM amp_engagement_event e
    WHERE e.broadcast_id = b.id
      AND e.event_type = 'click'
  ) clk ON true;

  RETURN fn_response_success(
    'Audience report',
    NULL,
    jsonb_build_object(
      'audience', jsonb_build_object(
        'audience_id', v_audience.id,
        'name', v_audience.name,
        'audience_type', v_audience.audience_type,
        'is_active', v_audience.is_active
      ),
      'metrics', v_metrics,
      'baseline', v_baseline,
      'size_series', v_size_series,
      'revenue_series', v_revenue_series,
      'tier_mix', v_tier_mix,
      'rfm_mix', v_rfm_mix,
      'broadcasts', v_broadcasts
    )
  );
EXCEPTION WHEN OTHERS THEN
  RETURN fn_response_error('Audience report failed', SQLERRM, 'INTERNAL_ERROR', NULL);
END;
$function$;
