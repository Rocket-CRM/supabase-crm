-- Storefront "Points on product page" earn preview.
-- Runs the purchase earn engine (calc_currency_core) for one SKU so the product page
-- shows the same points a purchase would award: tier rate, excluded products, multipliers.

-- 1. Guests have no user row, so tier conditions can never match. Let a caller with no
--    user supply a tier for the current transaction only (rocket.preview_tier_id).
--    Purchases always pass a user, so their evaluation is unchanged.
DO $migration$
DECLARE
  v_def text := pg_get_functiondef('public.evaluate_earn_conditions_core'::regproc);
  v_old text := E'WHERE id = p_user_id AND tier_id = ANY(v_condition.entity_ids)\n                      AND merchant_id = p_merchant_id\n                ) THEN';
  v_new text := E'WHERE id = p_user_id AND tier_id = ANY(v_condition.entity_ids)\n                      AND merchant_id = p_merchant_id\n                ) AND NOT coalesce(\n                    p_user_id IS NULL\n                    AND NULLIF(current_setting(''rocket.preview_tier_id'', true), '''')::uuid = ANY(v_condition.entity_ids),\n                    false\n                ) THEN';
BEGIN
  IF position(v_new in v_def) > 0 THEN
    RETURN;
  END IF;
  IF (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 THEN
    RAISE EXCEPTION 'evaluate_earn_conditions_core tier branch not found exactly once';
  END IF;
  EXECUTE replace(v_def, v_old, v_new);
END
$migration$;

-- 2. Preview RPC. Member = auth.uid() with an account at this merchant (PostgREST with the
--    storefront crm_token). Anyone else previews as the lowest-earning tier.
CREATE OR REPLACE FUNCTION public.api_get_product_earn_preview(
  p_merchant_code text,
  p_sku_code text,
  p_amount numeric
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_merchant_id uuid;
  v_user_id uuid;
  v_preview_tier_id uuid;
  v_base integer;
  v_bonus integer;
BEGIN
  IF coalesce(p_merchant_code, '') = '' OR coalesce(p_sku_code, '') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'merchant_code and sku_code required');
  END IF;
  IF p_amount IS NULL OR p_amount < 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid amount');
  END IF;

  SELECT id INTO v_merchant_id FROM merchant_master WHERE merchant_code = p_merchant_code;
  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'merchant not found');
  END IF;

  IF auth.uid() IS NOT NULL THEN
    SELECT ua.id INTO v_user_id
    FROM user_accounts ua
    WHERE ua.auth_user_id = auth.uid() AND ua.merchant_id = v_merchant_id;
  END IF;

  IF v_user_id IS NULL THEN
    SELECT ec.entity_ids[1] INTO v_preview_tier_id
    FROM earn_factor ef
    JOIN earn_factor_group efg ON efg.id = ef.earn_factor_group_id
    JOIN earn_conditions ec
      ON ec.group_id = ef.earn_conditions_group_id
     AND ec.entity::text = 'tier'
     AND coalesce(ec.exclude, false) = false
     AND cardinality(ec.entity_ids) >= 1
    WHERE ef.merchant_id = v_merchant_id
      AND ef.active_status IS TRUE
      AND ef.earn_factor_type = 'rate'
      AND ef.target_currency = 'points'
      AND ef.earn_factor_amount > 0
      AND efg.active_status IS TRUE
      AND coalesce(efg.perspective, 'buyer') = 'buyer'
      AND (ef.window_start IS NULL OR ef.window_start <= now())
      AND (ef.window_end IS NULL OR ef.window_end >= now())
    ORDER BY ef.earn_factor_amount DESC
    LIMIT 1;

    PERFORM set_config('rocket.preview_tier_id', coalesce(v_preview_tier_id::text, ''), true);
  END IF;

  SELECT
    coalesce(sum(c.amount) FILTER (WHERE c.component = 'base'), 0),
    coalesce(sum(c.amount) FILTER (WHERE c.component = 'bonus'), 0)
  INTO v_base, v_bonus
  FROM calc_currency_core(
    v_merchant_id,
    v_user_id,
    p_amount,
    NULL,
    jsonb_build_array(jsonb_build_object('sku_code', p_sku_code, 'quantity', 1, 'line_total', p_amount)),
    NULL,
    'buyer'
  ) c
  WHERE c.currency_type = 'points';

  PERFORM set_config('rocket.preview_tier_id', '', true);

  RETURN jsonb_build_object(
    'ok', true,
    'points', v_base + v_bonus,
    'base_points', v_base,
    'bonus_points', v_bonus,
    'is_member', v_user_id IS NOT NULL
  );
END;
$$;

REVOKE ALL ON FUNCTION public.api_get_product_earn_preview(text, text, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.api_get_product_earn_preview(text, text, numeric) TO anon, authenticated, service_role;
