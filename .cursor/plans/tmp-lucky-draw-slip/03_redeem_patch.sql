-- 3) redeem_reward_with_points — attach lucky_draw_slip on each redemption object
DO $patch$
DECLARE
  v_def text;
  v_old1 text;
  v_new1 text;
  v_old2 text;
  v_new2 text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
  FROM pg_proc p
  JOIN pg_namespace n ON p.pronamespace = n.oid
  WHERE n.nspname = 'public'
    AND p.proname = 'redeem_reward_with_points';

  IF v_def IS NULL THEN
    RAISE EXCEPTION 'redeem_reward_with_points not found';
  END IF;

  IF position('lucky_draw_slip' in v_def) > 0 THEN
    RAISE NOTICE 'redeem already has lucky_draw_slip';
    RETURN;
  END IF;

  v_old1 := '''fulfillment_status'', v_redemption.fulfillment_status));';
  v_new1 := '''fulfillment_status'', v_redemption.fulfillment_status, ''lucky_draw_slip'', fn_build_lucky_draw_slip(v_merchant_id, v_reward.id, v_redemption.code, v_target_user_id, v_redemption.redeemed_at));';

  v_old2 := '''fulfillment_status'', v_redemption.fulfillment_status)];';
  v_new2 := '''fulfillment_status'', v_redemption.fulfillment_status, ''lucky_draw_slip'', fn_build_lucky_draw_slip(v_merchant_id, v_reward.id, v_redemption.code, v_target_user_id, v_redemption.redeemed_at)];';

  IF position(v_old1 in v_def) = 0 OR position(v_old2 in v_def) = 0 THEN
    RAISE EXCEPTION 'redeem patch markers not found (promocode loop / single insert)';
  END IF;

  v_def := replace(v_def, v_old1, v_new1);
  v_def := replace(v_def, v_old2, v_new2);

  EXECUTE v_def;
END;
$patch$;

