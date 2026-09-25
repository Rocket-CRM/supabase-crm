-- Her Hyness marketplace earn correction (Aug 2026 claimed purchases).
-- Applies staged financial reconciliation: mkp + purchase ledgers, then wallet burns.
-- Idempotent via dedup_key per purchase. Dry-run by default.

CREATE TABLE IF NOT EXISTS public.mkp_financial_repair_run (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_run_id uuid NOT NULL,
  merchant_id uuid NOT NULL REFERENCES public.merchant_master(id),
  status text NOT NULL DEFAULT 'dry_run',
  summary jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  applied_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.mkp_financial_repair_order (
  repair_run_id uuid NOT NULL REFERENCES public.mkp_financial_repair_run(id) ON DELETE CASCADE,
  purchase_id uuid NOT NULL,
  order_sn text NOT NULL,
  platform text NOT NULL,
  points_before integer NOT NULL,
  points_after integer NOT NULL,
  points_deducted integer NOT NULL DEFAULT 0,
  points_shortfall integer NOT NULL DEFAULT 0,
  baht_before numeric NOT NULL,
  baht_after numeric NOT NULL,
  wallet_ledger_id uuid,
  applied_at timestamptz,
  error text,
  PRIMARY KEY (repair_run_id, purchase_id)
);

REVOKE ALL ON public.mkp_financial_repair_run FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.mkp_financial_repair_order FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.mkp_financial_repair_run TO service_role;
GRANT ALL ON public.mkp_financial_repair_order TO service_role;

CREATE OR REPLACE FUNCTION public.fn_mkp_financial_repair_apply(
  p_source_run_id uuid,
  p_merchant_id uuid DEFAULT 'ffe8519e-49a2-467b-a0ec-57d28ba8be49'::uuid,
  p_apply boolean DEFAULT false,
  p_limit integer DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_repair_run_id uuid;
  v_row record;
  v_item jsonb;
  v_user_id uuid;
  v_balance integer;
  v_deduct integer;
  v_shortfall integer;
  v_wallet_id uuid;
  v_processed integer := 0;
  v_corrected integer := 0;
  v_wallet_posted integer := 0;
  v_shortfall_total integer := 0;
  v_baht_delta numeric := 0;
  v_points_delta integer := 0;
  v_gross numeric;
  v_discount numeric;
BEGIN
  IF p_source_run_id IS NULL THEN
    RAISE EXCEPTION 'p_source_run_id is required';
  END IF;

  INSERT INTO mkp_financial_repair_run (source_run_id, merchant_id, status)
  VALUES (p_source_run_id, p_merchant_id, CASE WHEN p_apply THEN 'applying' ELSE 'dry_run' END)
  RETURNING id INTO v_repair_run_id;

  FOR v_row IN
    SELECT s.*, pl.user_id
    FROM stg_marketplace_financial_reconciliation s
    JOIN purchase_ledger pl ON pl.id = s.purchase_id
    WHERE s.run_id = p_source_run_id
      AND s.merchant_id = p_merchant_id
      AND s.fetch_status = 'fetched'
      AND s.proposed_earnable_amount IS NOT NULL
      AND s.purchase_id IS NOT NULL
    ORDER BY s.purchase_id
    LIMIT p_limit
  LOOP
    v_processed := v_processed + 1;
    v_deduct := GREATEST(COALESCE(v_row.current_points, 0) - COALESCE(v_row.proposed_points, 0), 0);
    v_shortfall := 0;
    v_wallet_id := NULL;
    v_user_id := v_row.user_id;

    IF p_apply AND v_row.order_id IS NOT NULL THEN
      v_gross := COALESCE((v_row.proposed_financials->>'gross_merchandise_amount')::numeric, v_row.proposed_earnable_amount);
      v_discount := GREATEST(v_gross - v_row.proposed_earnable_amount, 0);

      -- Purchase lines first: bridge via unchanged mkp line totals.
      UPDATE purchase_items_ledger pil
      SET unit_price = src.unit_price,
          discount_amount = src.discount_amount,
          line_total = src.line_total
      FROM (
        SELECT pil2.id,
               (pi.elem->>'unit_price')::numeric AS unit_price,
               COALESCE((pi.elem->>'discount_amount')::numeric, 0) AS discount_amount,
               COALESCE((pi.elem->>'earnable_amount')::numeric, (pi.elem->>'line_total')::numeric) AS line_total
        FROM purchase_items_ledger pil2
        JOIN order_items_ledger_mkp oi
          ON oi.order_id = v_row.order_id
         AND pil2.quantity = oi.quantity
         AND pil2.unit_price = oi.unit_price
         AND pil2.line_total = oi.line_total
        JOIN LATERAL jsonb_array_elements(COALESCE(v_row.proposed_items, '[]'::jsonb)) AS pi(elem) ON true
        WHERE pil2.transaction_id = v_row.purchase_id
          AND oi.platform_item_id = pi.elem->>'platform_item_id'
      ) src
      WHERE pil.id = src.id;

      UPDATE order_ledger_mkp
      SET earnable_amount = v_row.proposed_earnable_amount,
          financial_details = COALESCE(v_row.proposed_financials, '{}'::jsonb),
          total_amount = v_gross,
          discount_amount = v_discount,
          final_amount = COALESCE((v_row.proposed_financials->>'buyer_total_amount')::numeric, final_amount),
          updated_at = now()
      WHERE id = v_row.order_id;

      FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(v_row.proposed_items, '[]'::jsonb))
      LOOP
        UPDATE order_items_ledger_mkp oi
        SET unit_price = COALESCE((v_item->>'unit_price')::numeric, oi.unit_price),
            quantity = COALESCE((v_item->>'quantity')::numeric, oi.quantity),
            discount_amount = COALESCE((v_item->>'discount_amount')::numeric, 0),
            line_total = COALESCE((v_item->>'line_total')::numeric, oi.line_total),
            earnable_amount = COALESCE((v_item->>'earnable_amount')::numeric, (v_item->>'line_total')::numeric),
            financial_details = COALESCE(v_item->'financial_details', '{}'::jsonb)
        WHERE oi.order_id = v_row.order_id
          AND oi.platform_item_id = v_item->>'platform_item_id';
      END LOOP;
    END IF;

    IF p_apply THEN
      UPDATE purchase_ledger
      SET total_amount = COALESCE((v_row.proposed_financials->>'gross_merchandise_amount')::numeric, v_row.proposed_earnable_amount),
          final_amount = v_row.proposed_earnable_amount,
          earnable_amount = v_row.proposed_earnable_amount,
          discount_amount = GREATEST(
            COALESCE((v_row.proposed_financials->>'gross_merchandise_amount')::numeric, v_row.proposed_earnable_amount)
            - v_row.proposed_earnable_amount,
            0
          ),
          metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object(
            'mkp_financial_repair_run_id', v_repair_run_id,
            'mkp_financial_repair_source_run_id', p_source_run_id,
            'marketplace_financial_details', COALESCE(v_row.proposed_financials, '{}'::jsonb)
          ),
          updated_at = now()
      WHERE id = v_row.purchase_id;
    END IF;

    v_corrected := v_corrected + 1;
    v_baht_delta := v_baht_delta + (v_row.current_purchase_amount - v_row.proposed_earnable_amount);
    v_points_delta := v_points_delta + v_deduct;

    IF p_apply AND v_deduct > 0 AND v_user_id IS NOT NULL THEN
      SELECT COALESCE(points_balance, 0)
      INTO v_balance
      FROM user_wallet
      WHERE user_id = v_user_id AND merchant_id = p_merchant_id
      FOR UPDATE;

      v_deduct := LEAST(v_deduct, GREATEST(v_balance, 0));
      v_shortfall := GREATEST((COALESCE(v_row.current_points, 0) - COALESCE(v_row.proposed_points, 0)) - v_deduct, 0);

      IF v_deduct > 0 THEN
        BEGIN
          SELECT chokepoint_post_wallet_transaction(
            p_user_id := v_user_id,
            p_currency := 'points',
            p_source_type := 'purchase',
            p_component := 'reversal',
            p_transaction_type := 'burn',
            p_amount := v_deduct,
            p_transaction_id := v_row.purchase_id,
            p_merchant_id := p_merchant_id,
            p_description := format('Marketplace earn correction (%s %s)', v_row.platform, v_row.order_sn),
            p_metadata := jsonb_build_object(
              'reason', 'mkp_voucher_earn_correction',
              'repair_run_id', v_repair_run_id,
              'source_run_id', p_source_run_id,
              'platform', v_row.platform,
              'order_sn', v_row.order_sn,
              'points_before', v_row.current_points,
              'points_after', v_row.proposed_points
            ),
            p_dedup_key := 'mkp-fin-repair:' || v_row.purchase_id::text
          ) INTO v_wallet_id;
          v_wallet_posted := v_wallet_posted + 1;
        EXCEPTION
          WHEN unique_violation THEN
            SELECT id INTO v_wallet_id
            FROM wallet_ledger
            WHERE dedup_key = 'mkp-fin-repair:' || v_row.purchase_id::text
            LIMIT 1;
          WHEN OTHERS THEN
            INSERT INTO mkp_financial_repair_order (
              repair_run_id, purchase_id, order_sn, platform,
              points_before, points_after, points_deducted, points_shortfall,
              baht_before, baht_after, error
            ) VALUES (
              v_repair_run_id, v_row.purchase_id, v_row.order_sn, v_row.platform,
              v_row.current_points, v_row.proposed_points, 0, v_deduct,
              v_row.current_purchase_amount, v_row.proposed_earnable_amount, SQLERRM
            );
            CONTINUE;
        END;
      END IF;

      v_shortfall_total := v_shortfall_total + v_shortfall;
    END IF;

    INSERT INTO mkp_financial_repair_order (
      repair_run_id, purchase_id, order_sn, platform,
      points_before, points_after, points_deducted, points_shortfall,
      baht_before, baht_after, wallet_ledger_id, applied_at
    ) VALUES (
      v_repair_run_id, v_row.purchase_id, v_row.order_sn, v_row.platform,
      v_row.current_points, v_row.proposed_points, v_deduct, v_shortfall,
      v_row.current_purchase_amount, v_row.proposed_earnable_amount, v_wallet_id,
      CASE WHEN p_apply THEN now() ELSE NULL END
    )
    ON CONFLICT (repair_run_id, purchase_id) DO UPDATE SET
      points_deducted = EXCLUDED.points_deducted,
      points_shortfall = EXCLUDED.points_shortfall,
      wallet_ledger_id = COALESCE(EXCLUDED.wallet_ledger_id, mkp_financial_repair_order.wallet_ledger_id),
      applied_at = EXCLUDED.applied_at,
      error = EXCLUDED.error;
  END LOOP;

  UPDATE mkp_financial_repair_run
  SET status = CASE WHEN p_apply THEN 'applied' ELSE 'dry_run' END,
      applied_at = CASE WHEN p_apply THEN now() ELSE NULL END,
      summary = jsonb_build_object(
        'processed', v_processed,
        'ledger_corrected', v_corrected,
        'wallet_posted', v_wallet_posted,
        'points_deducted', v_points_delta,
        'points_shortfall', v_shortfall_total,
        'baht_reduced', v_baht_delta,
        'apply', p_apply
      )
  WHERE id = v_repair_run_id;

  RETURN jsonb_build_object(
    'success', true,
    'repair_run_id', v_repair_run_id,
    'source_run_id', p_source_run_id,
    'apply', p_apply,
    'processed', v_processed,
    'ledger_corrected', v_corrected,
    'wallet_posted', v_wallet_posted,
    'points_deducted', v_points_delta,
    'points_shortfall', v_shortfall_total,
    'baht_reduced', v_baht_delta
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_mkp_financial_repair_apply(uuid, uuid, boolean, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_mkp_financial_repair_apply(uuid, uuid, boolean, integer) TO service_role;
