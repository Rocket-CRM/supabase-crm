-- Audience reports: hash-join planning for metrics, size series from bucketed entry/exit events

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

  PERFORM set_config('enable_nestloop', 'off', true);

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

  PERFORM set_config('enable_nestloop', 'off', true);

  SELECT jsonb_object_agg(COALESCE(m.audience_id::text, 'baseline'), m.metrics)
  INTO v_all
  FROM fn_report_audience_metrics(v_mid, ARRAY[p_audience_id], p_from, p_to) m;
  v_metrics := v_all -> (p_audience_id::text);
  v_baseline := v_all -> 'baseline';

  WITH buckets AS (
    SELECT
      gs::date AS bucket_date,
      (gs::timestamp AT TIME ZONE 'Asia/Bangkok') AS bucket_start
    FROM generate_series(
      date_trunc(v_freq, (p_from AT TIME ZONE 'Asia/Bangkok')::timestamp),
      date_trunc(v_freq, ((p_to - interval '1 microsecond') AT TIME ZONE 'Asia/Bangkok')::timestamp),
      v_step
    ) gs
  ),
  ev AS (
    SELECT am.entered_at AS ts, 1 AS d
    FROM amp_audience_member am
    WHERE am.audience_id = p_audience_id
    UNION ALL
    SELECT am.exited_at, -1
    FROM amp_audience_member am
    WHERE am.audience_id = p_audience_id
      AND am.exited_at IS NOT NULL
  ),
  opening AS (
    SELECT COALESCE(sum(ev.d), 0)::bigint AS n
    FROM ev
    WHERE ev.ts < (SELECT min(bucket_start) FROM buckets)
  ),
  ev_bucket AS (
    SELECT
      date_trunc(v_freq, (ev.ts AT TIME ZONE 'Asia/Bangkok'))::date AS bucket_date,
      count(*) FILTER (WHERE ev.d = 1)::bigint AS joined,
      count(*) FILTER (WHERE ev.d = -1)::bigint AS left_count
    FROM ev
    WHERE ev.ts >= (SELECT min(bucket_start) FROM buckets)
    GROUP BY 1
  ),
  size_rows AS (
    SELECT
      b.bucket_date,
      (SELECT n FROM opening)
        + sum(COALESCE(eb.joined, 0) - COALESCE(eb.left_count, 0)) OVER (ORDER BY b.bucket_date) AS members,
      COALESCE(eb.joined, 0) AS joined,
      COALESCE(eb.left_count, 0) AS left_count
    FROM buckets b
    LEFT JOIN ev_bucket eb ON eb.bucket_date = b.bucket_date
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'bucket', to_char(sr.bucket_date, 'YYYY-MM-DD'),
    'members', sr.members,
    'joined', sr.joined,
    'left', sr.left_count
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
