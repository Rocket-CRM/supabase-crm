-- Migration name: mkp_items_repair_rpcs
-- Items-only repair path used by the marketplace-items-repair edge function.
-- Never touches order_ledger_mkp headers (status, amounts, claim flags stay as-is).

-- 1) Attempt log so orders the platform no longer returns do not loop forever.
CREATE TABLE IF NOT EXISTS public.stg_mkp_items_repair_log (
  platform        text        NOT NULL,
  order_sn        text        NOT NULL,
  attempts        int         NOT NULL DEFAULT 0,
  last_error      text,
  last_attempt_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (platform, order_sn)
);
ALTER TABLE public.stg_mkp_items_repair_log ENABLE ROW LEVEL SECURITY; -- service role only

CREATE OR REPLACE FUNCTION public.fn_mkp_items_repair_log(p_platform text, p_order_sn text, p_error text)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path TO 'public' AS $$
  INSERT INTO stg_mkp_items_repair_log(platform, order_sn, attempts, last_error, last_attempt_at)
  VALUES (p_platform, p_order_sn, 1, LEFT(p_error, 500), now())
  ON CONFLICT (platform, order_sn) DO UPDATE
    SET attempts = stg_mkp_items_repair_log.attempts + 1,
        last_error = LEFT(EXCLUDED.last_error, 500),
        last_attempt_at = now();
$$;

-- 2) Pick the next batch of item-less orders for one shop, by tier.
--    tier = 'claimed' -> synced_to_transaction = true (already claimed; Lucky Fans impact)
--    tier = 'active'  -> not claimed, not cancelled/unpaid (may be claimed later)
--    tier = 'all'     -> everything else not claimed (cancelled/unpaid leftovers)
--    p_partitions / p_partition: split the backlog by hash(order_sn) so N workers can run in parallel
--    without picking the same orders (worker k of N passes p_partitions=N, p_partition=k-1).
CREATE OR REPLACE FUNCTION public.fn_mkp_items_repair_pick(
  p_merchant_id uuid, p_platform text, p_shop_id text, p_tier text, p_limit int DEFAULT 50,
  p_partitions int DEFAULT 1, p_partition int DEFAULT 0)
RETURNS TABLE(order_sn text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT o.order_sn
  FROM order_ledger_mkp o
  WHERE o.merchant_id = p_merchant_id
    AND o.platform = p_platform
    AND o.shop_id = p_shop_id
    AND o.updated_at >= '2026-09-03 15:25:00+00'          -- net-earnable rollout (22:25 BKK)
    AND (COALESCE(p_partitions, 1) <= 1 OR abs(hashtext(o.order_sn)) % p_partitions = COALESCE(p_partition, 0))
    AND NOT EXISTS (SELECT 1 FROM order_items_ledger_mkp i WHERE i.order_id = o.id)
    AND NOT EXISTS (SELECT 1 FROM stg_mkp_items_repair_log l
                    WHERE l.platform = o.platform AND l.order_sn = o.order_sn AND l.attempts >= 3)
    AND CASE p_tier
          WHEN 'claimed' THEN o.synced_to_transaction IS TRUE
          WHEN 'active'  THEN o.synced_to_transaction IS NOT TRUE
                              AND upper(o.order_status) NOT IN ('CANCELLED','CANCEL','IN_CANCEL','CANCELED','UNPAID','TO_RETURN')
          ELSE o.synced_to_transaction IS NOT TRUE
        END
  ORDER BY o.transaction_date DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 50);
$$;

-- 3) Remaining counts per tier (for the driver loop / verification).
CREATE OR REPLACE FUNCTION public.fn_mkp_items_repair_remaining(p_merchant_id uuid, p_platform text, p_shop_id text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  WITH bad AS (
    SELECT o.synced_to_transaction, upper(o.order_status) AS st,
           EXISTS (SELECT 1 FROM stg_mkp_items_repair_log l
                   WHERE l.platform = o.platform AND l.order_sn = o.order_sn AND l.attempts >= 3) AS gave_up
    FROM order_ledger_mkp o
    WHERE o.merchant_id = p_merchant_id AND o.platform = p_platform AND o.shop_id = p_shop_id
      AND o.updated_at >= '2026-09-03 15:25:00+00'
      AND NOT EXISTS (SELECT 1 FROM order_items_ledger_mkp i WHERE i.order_id = o.id)
  )
  SELECT jsonb_build_object(
    'claimed', COUNT(*) FILTER (WHERE synced_to_transaction IS TRUE AND NOT gave_up),
    'active',  COUNT(*) FILTER (WHERE synced_to_transaction IS NOT TRUE AND NOT gave_up
                                AND st NOT IN ('CANCELLED','CANCEL','IN_CANCEL','CANCELED','UNPAID','TO_RETURN')),
    'all_unclaimed', COUNT(*) FILTER (WHERE synced_to_transaction IS NOT TRUE AND NOT gave_up),
    'gave_up_after_3_attempts', COUNT(*) FILTER (WHERE gave_up)
  ) FROM bad;
$$;

-- 4) Items-only writer. Input = the same NormalizedOrder JSON the ingest adapters produce.
CREATE OR REPLACE FUNCTION public.fn_mkp_repair_order_items(p_order jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_order_id uuid; v_merchant_id uuid; v_inserted int := 0;
  v_sn text := p_order->>'order_sn'; v_platform text := p_order->>'platform';
BEGIN
  SELECT id, merchant_id INTO v_order_id, v_merchant_id
  FROM order_ledger_mkp WHERE order_sn = v_sn AND platform = v_platform;
  IF v_order_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'ORDER_NOT_FOUND', 'order_sn', v_sn);
  END IF;
  IF v_merchant_id <> (p_order->>'merchant_id')::uuid THEN
    RETURN jsonb_build_object('success', false, 'code', 'MERCHANT_MISMATCH', 'order_sn', v_sn);
  END IF;
  IF NOT (p_order ? 'items' AND jsonb_typeof(p_order->'items') = 'array' AND jsonb_array_length(p_order->'items') > 0) THEN
    RETURN jsonb_build_object('success', false, 'code', 'NO_ITEMS_IN_PAYLOAD', 'order_sn', v_sn);
  END IF;

  INSERT INTO order_items_ledger_mkp(order_id, merchant_id, platform, order_sn, platform_item_id, variant_id, platform_sku, variant_sku,
                                     item_name, variant_name, quantity, currency, unit_price, discount_amount, line_total, earnable_amount, financial_details)
  SELECT v_order_id, v_merchant_id, v_platform, v_sn,
         item->>'platform_item_id', item->>'variant_id', item->>'platform_sku', item->>'variant_sku',
         item->>'item_name', item->>'variant_name',
         (item->>'quantity')::numeric, COALESCE(item->>'currency', 'THB'),
         (item->>'unit_price')::numeric, COALESCE((item->>'discount_amount')::numeric, 0),
         (item->>'line_total')::numeric, (item->>'earnable_amount')::numeric,
         COALESCE(item->'financial_details', '{}'::jsonb)
  FROM (
    SELECT DISTINCT ON (item->>'platform_item_id') item
    FROM jsonb_array_elements(p_order->'items') WITH ORDINALITY AS t(item, ord)
    ORDER BY item->>'platform_item_id', ord DESC
  ) deduped
  ON CONFLICT (platform, platform_item_id, order_id) DO NOTHING;
  GET DIAGNOSTICS v_inserted = ROW_COUNT;

  RETURN jsonb_build_object('success', true, 'order_id', v_order_id, 'order_sn', v_sn, 'items_inserted', v_inserted);
END;
$$;

-- 5) Batch wrapper: one RPC round-trip per fetched batch (up to 50 orders) instead of 50.
--    Failures are logged into stg_mkp_items_repair_log here so the edge function stays thin.
CREATE OR REPLACE FUNCTION public.fn_mkp_repair_order_items_batch(p_orders jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_order jsonb; v_res jsonb; v_results jsonb := '[]'::jsonb;
  v_repaired int := 0; v_items int := 0; v_failed int := 0;
BEGIN
  IF p_orders IS NULL OR jsonb_typeof(p_orders) <> 'array' THEN
    RETURN jsonb_build_object('success', false, 'code', 'INVALID_INPUT');
  END IF;
  FOR v_order IN SELECT value FROM jsonb_array_elements(p_orders) LOOP
    BEGIN
      v_res := public.fn_mkp_repair_order_items(v_order);
    EXCEPTION WHEN OTHERS THEN
      v_res := jsonb_build_object('success', false, 'code', 'EXCEPTION', 'error', SQLERRM, 'order_sn', v_order->>'order_sn');
    END;
    IF (v_res->>'success')::boolean THEN
      v_repaired := v_repaired + 1;
      v_items := v_items + COALESCE((v_res->>'items_inserted')::int, 0);
    ELSE
      v_failed := v_failed + 1;
      PERFORM public.fn_mkp_items_repair_log(v_order->>'platform', v_order->>'order_sn',
                                             COALESCE(v_res->>'code', 'repair_failed') || COALESCE(': ' || (v_res->>'error'), ''));
      v_results := v_results || jsonb_build_array(v_res);
    END IF;
  END LOOP;
  RETURN jsonb_build_object('success', true, 'repaired', v_repaired, 'items_inserted', v_items,
                            'failed', v_failed, 'failures', v_results);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_mkp_items_repair_log(text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_mkp_items_repair_pick(uuid, text, text, text, int, int, int) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_mkp_repair_order_items_batch(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_mkp_items_repair_remaining(uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_mkp_repair_order_items(jsonb) FROM PUBLIC, anon, authenticated;
