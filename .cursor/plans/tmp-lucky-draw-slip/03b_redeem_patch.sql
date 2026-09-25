
DO $patch$
DECLARE
  v_def text;
  v_count1 int;
  v_count2 int;
  v_marker1 text := $m$'fulfillment_status', v_redemption.fulfillment_status));$m$;
  v_marker2 text := $m$'fulfillment_status', v_redemption.fulfillment_status)];$m$;
  v_rep1 text := $m$'fulfillment_status', v_redemption.fulfillment_status, 'lucky_draw_slip', fn_build_lucky_draw_slip(v_merchant_id, v_reward.id, v_redemption.code, v_target_user_id, v_redemption.redeemed_at));$m$;
  v_rep2 text := $m$'fulfillment_status', v_redemption.fulfillment_status, 'lucky_draw_slip', fn_build_lucky_draw_slip(v_merchant_id, v_reward.id, v_redemption.code, v_target_user_id, v_redemption.redeemed_at)];$m$;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
  FROM pg_proc p
  JOIN pg_namespace n ON p.pronamespace = n.oid
  WHERE n.nspname = 'public'
    AND p.proname = 'redeem_reward_with_points';

  IF position('lucky_draw_slip' in v_def) > 0 THEN
    RAISE NOTICE 'already patched';
    RETURN;
  END IF;

  v_count1 := (length(v_def) - length(replace(v_def, v_marker1, ''))) / length(v_marker1);
  v_count2 := (length(v_def) - length(replace(v_def, v_marker2, ''))) / length(v_marker2);

  IF v_count1 <> 1 OR v_count2 <> 1 THEN
    RAISE EXCEPTION 'unexpected marker counts: % / %', v_count1, v_count2;
  END IF;

  v_def := replace(v_def, v_marker1, v_rep1);
  v_def := replace(v_def, v_marker2, v_rep2);

  -- Sanity: CREATE header still present
  IF left(v_def, 6) <> 'CREATE' THEN
    RAISE EXCEPTION 'patched def lost CREATE header: %', left(v_def, 80);
  END IF;

  EXECUTE v_def;
END;
$patch$;
