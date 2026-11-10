-- Package 1: tier evaluation reads earned via v_wallet_ledger_flow (points earned rule).
-- Depends on 20261110090000_wallet_ledger_flow_view.sql.

CREATE OR REPLACE FUNCTION public.calculate_tier_metric_value(
  p_user_id uuid,
  p_merchant_id uuid,
  p_metric metric,
  p_user_type user_type,
  p_window_start date,
  p_window_end date
)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  CASE
    WHEN p_metric = 'points' THEN
      RETURN (
        SELECT GREATEST(0, COALESCE(SUM(earned_delta), 0))
        FROM public.v_wallet_ledger_flow
        WHERE user_id = p_user_id
          AND merchant_id = p_merchant_id
          AND currency = 'points'
          AND created_at >= p_window_start
          AND created_at < p_window_end + INTERVAL '1 day'
      );

    WHEN p_metric = 'ticket' THEN
      RETURN (
        SELECT GREATEST(0, COALESCE(SUM(earned_delta), 0))
        FROM public.v_wallet_ledger_flow
        WHERE user_id = p_user_id
          AND merchant_id = p_merchant_id
          AND currency = 'ticket'
          AND created_at >= p_window_start
          AND created_at < p_window_end + INTERVAL '1 day'
      );

    WHEN p_metric = 'sales' THEN
      RETURN (
        SELECT COALESCE(SUM(final_amount), 0)
        FROM purchase_ledger
        WHERE merchant_id = p_merchant_id
          AND CASE
            WHEN p_user_type = 'buyer' THEN user_id = p_user_id
            WHEN p_user_type = 'seller' THEN seller_id = p_user_id
          END
          AND created_at >= p_window_start
          AND created_at < p_window_end + INTERVAL '1 day'
      );

    WHEN p_metric = 'orders' THEN
      RETURN (
        SELECT COUNT(*)
        FROM purchase_ledger
        WHERE merchant_id = p_merchant_id
          AND final_amount > 0
          AND CASE
            WHEN p_user_type = 'buyer' THEN user_id = p_user_id
            WHEN p_user_type = 'seller' THEN seller_id = p_user_id
          END
          AND created_at >= p_window_start
          AND created_at < p_window_end + INTERVAL '1 day'
      );

    ELSE
      RETURN 0;
  END CASE;
END;
$function$;

CREATE OR REPLACE FUNCTION custom_function.futurepark_tier_progress(
  p_merchant_id uuid,
  p_user_ids uuid[],
  p_as_of_date date
)
 RETURNS TABLE(
  user_id uuid,
  point_earn numeric,
  current_tier_id uuid,
  recommended_tier_id uuid,
  recommended_action text,
  next_tier_id uuid,
  upgrade_metric_needed metric,
  upgrade_progress_percent numeric,
  upgrade_deadline date,
  maintain_metric_needed metric,
  maintain_progress numeric,
  maintain_deadline date
)
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'custom_function', 'public'
AS $function$
BEGIN
  RETURN QUERY
  WITH users AS (
    SELECT
      ua.id AS uid,
      ua.tier_id AS cur_tier_id,
      CASE
        WHEN (ua.created_at AT TIME ZONE 'Asia/Bangkok')::date
             BETWEEN DATE '2025-12-16' AND DATE '2025-12-31'
          THEN DATE '2025-12-16'
        ELSE DATE '2025-12-31'
      END AS bucket1_start
    FROM public.user_accounts ua
    WHERE ua.merchant_id = p_merchant_id
      AND ua.id = ANY (p_user_ids)
  ),
  bucket1 AS (
    SELECT
      u.uid AS user_id,
      COALESCE(SUM(wl.signed_amount), 0)::numeric AS amount
    FROM users u
    JOIN public.wallet_ledger wl
      ON wl.user_id = u.uid
     AND wl.merchant_id = p_merchant_id
    JOIN public.purchase_ledger pl
      ON pl.id = wl.source_id
     AND pl.merchant_id = p_merchant_id
    WHERE wl.currency = 'points'::public.currency
      AND wl.transaction_type = 'earn'::public.currency_transaction_type
      AND wl.source_type = 'purchase'::public.wallet_transaction_source_type
      AND wl.source_id IS NOT NULL
      AND (pl.transaction_date AT TIME ZONE 'Asia/Bangkok')::date >= u.bucket1_start
      AND (pl.transaction_date AT TIME ZONE 'Asia/Bangkok')::date <= p_as_of_date
      AND EXISTS (
        SELECT 1
        FROM public.purchase_receipt_upload r
        WHERE r.purchase_ledger_id = wl.source_id
          AND r.status = 'approved'
          AND r.crm_sync_status = 'confirmed'
      )
    GROUP BY u.uid
  ),
  bucket2 AS (
    SELECT
      u.uid AS user_id,
      COALESCE(SUM(wl.signed_amount), 0)::numeric AS amount
    FROM users u
    JOIN public.wallet_ledger wl
      ON wl.user_id = u.uid
     AND wl.merchant_id = p_merchant_id
    WHERE wl.currency = 'points'::public.currency
      AND wl.transaction_type = 'earn'::public.currency_transaction_type
      AND wl.source_type = 'purchase'::public.wallet_transaction_source_type
      AND wl.source_id IS NULL
      AND (wl.created_at AT TIME ZONE 'Asia/Bangkok')::date >= DATE '2026-01-01'
      AND (wl.created_at AT TIME ZONE 'Asia/Bangkok')::date <= p_as_of_date
    GROUP BY u.uid
  ),
  bucket3 AS (
    SELECT
      u.uid AS user_id,
      COALESCE(SUM(wl.earned_delta), 0)::numeric AS amount
    FROM users u
    JOIN public.v_wallet_ledger_flow wl
      ON wl.user_id = u.uid
     AND wl.merchant_id = p_merchant_id
    WHERE wl.currency = 'points'::public.currency
      AND NOT (
        wl.transaction_type = 'earn'::public.currency_transaction_type
        AND wl.source_type = 'purchase'::public.wallet_transaction_source_type
      )
      AND (wl.created_at AT TIME ZONE 'Asia/Bangkok')::date >= DATE '2026-01-01'
      AND (wl.created_at AT TIME ZONE 'Asia/Bangkok')::date <= p_as_of_date
    GROUP BY u.uid
  ),
  -- Bucket 4 (migrated purchases): legacy earns migrated from Mongo now link to a
  -- purchase_ledger row (api_source = 'migration') but have no receipt row, so they
  -- match neither bucket 1 (needs a confirmed receipt) nor bucket 2 (source_id IS NULL).
  -- Dated by the purchase's own transaction_date, floor 2026-01-01.
  bucket4 AS (
    SELECT
      u.uid AS user_id,
      COALESCE(SUM(wl.signed_amount), 0)::numeric AS amount
    FROM users u
    JOIN public.wallet_ledger wl
      ON wl.user_id = u.uid
     AND wl.merchant_id = p_merchant_id
    JOIN public.purchase_ledger pl
      ON pl.id = wl.source_id
     AND pl.merchant_id = p_merchant_id
    WHERE wl.currency = 'points'::public.currency
      AND wl.transaction_type = 'earn'::public.currency_transaction_type
      AND wl.source_type = 'purchase'::public.wallet_transaction_source_type
      AND wl.source_id IS NOT NULL
      AND pl.api_source = 'migration'
      AND (pl.transaction_date AT TIME ZONE 'Asia/Bangkok')::date >= DATE '2026-01-01'
      AND (pl.transaction_date AT TIME ZONE 'Asia/Bangkok')::date <= p_as_of_date
      AND NOT EXISTS (
        SELECT 1
        FROM public.purchase_receipt_upload r
        WHERE r.purchase_ledger_id = wl.source_id
          AND r.status = 'approved'
          AND r.crm_sync_status = 'confirmed'
      )
    GROUP BY u.uid
  ),
  earns AS (
    SELECT
      u.uid AS user_id,
      u.cur_tier_id AS current_tier_id,
      GREATEST(0, COALESCE(b1.amount, 0) + COALESCE(b2.amount, 0) + COALESCE(b3.amount, 0) + COALESCE(b4.amount, 0)) AS point_earn
    FROM users u
    LEFT JOIN bucket1 b1 ON b1.user_id = u.uid
    LEFT JOIN bucket2 b2 ON b2.user_id = u.uid
    LEFT JOIN bucket3 b3 ON b3.user_id = u.uid
    LEFT JOIN bucket4 b4 ON b4.user_id = u.uid
  ),
  eval AS (
    SELECT
      e.user_id,
      e.point_earn,
      e.current_tier_id,
      entry.tier_id AS entry_tier_id,
      entry.ladder_position AS entry_position,
      curr.ladder_position AS current_position,
      qual.tier_id AS qualifying_tier_id,
      qual.ladder_position AS qualifying_position,
      nxt.tier_id AS computed_next_tier_id,
      nxt.upgrade_amount AS next_upgrade_amount
    FROM earns e
    LEFT JOIN LATERAL (
      SELECT l.tier_id, l.ladder_position
      FROM public.fn_tier_ladder_for_user(e.user_id, p_merchant_id) l
      ORDER BY CASE WHEN l.is_entry THEN 0 ELSE 1 END, l.ladder_position ASC
      LIMIT 1
    ) entry ON TRUE
    LEFT JOIN LATERAL (
      SELECT l.ladder_position
      FROM public.fn_tier_ladder_for_user(e.user_id, p_merchant_id) l
      WHERE l.tier_id = e.current_tier_id
      LIMIT 1
    ) curr ON TRUE
    LEFT JOIN LATERAL (
      SELECT l.tier_id, l.ladder_position
      FROM public.fn_tier_ladder_for_user(e.user_id, p_merchant_id) l
      WHERE COALESCE(l.upgrade_amount, 0) <= e.point_earn
      ORDER BY l.ladder_position DESC
      LIMIT 1
    ) qual ON TRUE
    LEFT JOIN LATERAL (
      SELECT l.tier_id, l.upgrade_amount
      FROM public.fn_tier_ladder_for_user(e.user_id, p_merchant_id) l
      WHERE l.ladder_position > COALESCE(curr.ladder_position, entry.ladder_position, 0)
      ORDER BY l.ladder_position ASC
      LIMIT 1
    ) nxt ON TRUE
  )
  SELECT
    ev.user_id,
    ev.point_earn,
    ev.current_tier_id,
    CASE
      WHEN ev.current_tier_id IS NULL OR ev.current_position IS NULL THEN ev.entry_tier_id
      ELSE COALESCE(ev.qualifying_tier_id, ev.entry_tier_id)
    END,
    CASE
      WHEN ev.current_tier_id IS NULL OR ev.current_position IS NULL THEN 'assign_entry'
      WHEN COALESCE(ev.qualifying_position, ev.entry_position, 0) > ev.current_position THEN 'upgrade'
      WHEN COALESCE(ev.qualifying_position, ev.entry_position, 0) < ev.current_position THEN 'downgrade'
      ELSE 'maintain'
    END,
    ev.computed_next_tier_id,
    CASE WHEN ev.computed_next_tier_id IS NOT NULL THEN 'points'::public.metric ELSE NULL END,
    CASE
      WHEN ev.computed_next_tier_id IS NOT NULL AND COALESCE(ev.next_upgrade_amount, 0) > 0
        THEN LEAST(100, ROUND(ev.point_earn * 100.0 / ev.next_upgrade_amount, 2))
      WHEN ev.computed_next_tier_id IS NOT NULL THEN 100::numeric
      ELSE NULL
    END,
    make_date(EXTRACT(YEAR FROM p_as_of_date)::int, 12, 31),
    NULL::public.metric,
    NULL::numeric,
    NULL::date
  FROM eval ev;
END;
$function$;
