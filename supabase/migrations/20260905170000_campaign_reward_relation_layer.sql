-- Campaign reward relation layer: one attach / detach / references / atomic-save
-- for referral, tier_entry, and lifecycle slots. Also keeps lifecycle action
-- node ids stable on upsert.

ALTER TABLE public.referral_reward_save_requests
  ADD COLUMN IF NOT EXISTS slot jsonb;

-- ---------------------------------------------------------------------------
-- B1 attach
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_campaign_reward_slot_attach(
  p_slot jsonb,
  p_reward_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_source text;
  v_target jsonb;
  v_extra jsonb;
  v_kind text;
  v_party text;
  v_db_party text;
  v_tier_id uuid;
  v_workflow_id uuid;
  v_node_id uuid;
  v_visibility text;
  v_previous_reward_id uuid;
  v_sort_order int;
  v_offer jsonb;
  v_discount_type text;
  v_discount_value numeric;
  v_min_spend numeric;
  v_mother_discount_id text;
BEGIN
  v_merchant_id := public.get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN public.fn_response_error('No merchant', 'No merchant context', 'NO_MERCHANT');
  END IF;

  IF p_slot IS NULL OR jsonb_typeof(p_slot) <> 'object' THEN
    RETURN public.fn_response_error('Invalid slot', 'p_slot object required', 'INVALID_SLOT');
  END IF;

  IF p_reward_id IS NULL THEN
    RETURN public.fn_response_error('Invalid reward', 'p_reward_id required', 'INVALID_REWARD');
  END IF;

  SELECT rm.visibility::text
  INTO v_visibility
  FROM public.reward_master rm
  WHERE rm.id = p_reward_id AND rm.merchant_id = v_merchant_id;

  IF v_visibility IS NULL THEN
    RETURN public.fn_response_error('Reward not found', 'Reward does not belong to this merchant', 'REWARD_NOT_FOUND');
  END IF;
  IF v_visibility IS DISTINCT FROM 'campaign' THEN
    RETURN public.fn_response_error('Invalid reward', 'Reward visibility must be campaign', 'INVALID_REWARD');
  END IF;

  v_source := p_slot->>'source';
  v_target := COALESCE(p_slot->'target', '{}'::jsonb);
  v_extra := COALESCE(p_slot->'extra', '{}'::jsonb);

  IF v_source = 'referral' THEN
    v_kind := v_target->>'kind';
    v_party := v_target->>'party';
    IF v_kind NOT IN ('signup', 'purchase') OR v_party NOT IN ('referrer', 'friend') THEN
      RETURN public.fn_response_error(
        'Invalid slot',
        'Referral slot needs kind signup|purchase and party referrer|friend',
        'INVALID_SLOT'
      );
    END IF;

    IF v_kind = 'purchase' AND v_party = 'friend' THEN
      SELECT rp.friend_offer, nullif(rp.friend_offer->>'reward_id', '')::uuid
      INTO v_offer, v_previous_reward_id
      FROM public.referral_program rp
      WHERE rp.merchant_id = v_merchant_id
      LIMIT 1;

      IF NOT FOUND THEN
        RETURN public.fn_response_error('Program not found', 'Referral program is missing', 'PROGRAM_NOT_FOUND');
      END IF;

      v_offer := COALESCE(v_offer, '{}'::jsonb);
      v_discount_type := COALESCE(
        nullif(v_extra->>'shopify_discount_type', ''),
        nullif(v_extra->>'discountType', ''),
        v_offer->>'shopify_discount_type'
      );
      v_discount_value := COALESCE(
        nullif(v_extra->>'value', '')::numeric,
        nullif(v_extra->>'discountValue', '')::numeric,
        nullif(v_offer->>'value', '')::numeric
      );
      v_min_spend := COALESCE(
        nullif(v_extra->>'min_spend', '')::numeric,
        nullif(v_extra->>'minSpend', '')::numeric,
        nullif(v_offer->>'min_spend', '')::numeric
      );
      v_mother_discount_id := COALESCE(
        nullif(v_extra->>'shopify_mother_discount_id', ''),
        nullif(v_extra->>'shopifyDiscountId', '')
      );

      v_offer := v_offer || jsonb_build_object(
        'reward_id', p_reward_id,
        'shopify_discount_type', v_discount_type,
        'discount_type', CASE WHEN v_discount_type = 'percentage' THEN 'percent' ELSE 'amount' END,
        'value', v_discount_value,
        'min_spend', v_min_spend
      );

      UPDATE public.referral_program
      SET
        friend_offer = v_offer,
        shopify_mother_discount_id = COALESCE(v_mother_discount_id, shopify_mother_discount_id),
        updated_at = now()
      WHERE merchant_id = v_merchant_id;
    ELSE
      v_db_party := CASE WHEN v_party = 'referrer' THEN 'inviter' ELSE 'invitee' END;
      IF NOT EXISTS (
        SELECT 1
        FROM public.referral_outcomes ro
        WHERE ro.merchant_id = v_merchant_id
          AND ro.kind = v_kind
          AND ro.party = v_db_party
          AND ro.outcome_type = 'reward'
          AND ro.entity_id = p_reward_id
      ) THEN
        INSERT INTO public.referral_outcomes (
          merchant_id, kind, party, outcome_type, entity_id
        ) VALUES (
          v_merchant_id, v_kind, v_db_party, 'reward', p_reward_id
        );
      END IF;
    END IF;

  ELSIF v_source = 'tier_entry' THEN
    v_tier_id := nullif(v_target->>'tier_id', '')::uuid;
    IF v_tier_id IS NULL THEN
      RETURN public.fn_response_error('Invalid slot', 'tier_entry slot needs tier_id', 'INVALID_SLOT');
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM public.tier_master tm
      WHERE tm.id = v_tier_id AND tm.merchant_id = v_merchant_id
    ) THEN
      RETURN public.fn_response_error('Invalid tier', 'Tier not found for this merchant', 'INVALID_TIER');
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM public.tier_entry_rewards ter
      WHERE ter.merchant_id = v_merchant_id
        AND ter.tier_id = v_tier_id
        AND ter.reward_kind = 'reward'
        AND ter.reward_id = p_reward_id
    ) THEN
      SELECT COALESCE(MAX(ter.sort_order), 0) + 1
      INTO v_sort_order
      FROM public.tier_entry_rewards ter
      WHERE ter.merchant_id = v_merchant_id AND ter.tier_id = v_tier_id;

      INSERT INTO public.tier_entry_rewards (
        merchant_id, tier_id, reward_kind, reward_id, quantity, sort_order, active_status
      ) VALUES (
        v_merchant_id, v_tier_id, 'reward', p_reward_id, 1, v_sort_order, true
      );
    END IF;

  ELSIF v_source = 'lifecycle' THEN
    v_workflow_id := nullif(v_target->>'workflow_id', '')::uuid;
    v_node_id := nullif(v_target->>'node_id', '')::uuid;
    IF v_workflow_id IS NULL OR v_node_id IS NULL THEN
      RETURN public.fn_response_error(
        'Invalid slot',
        'lifecycle slot needs workflow_id and node_id',
        'INVALID_SLOT'
      );
    END IF;

    SELECT nullif(wn.node_config->>'reward_id', '')::uuid
    INTO v_previous_reward_id
    FROM public.workflow_node wn
    WHERE wn.id = v_node_id
      AND wn.workflow_id = v_workflow_id
      AND wn.merchant_id = v_merchant_id
      AND wn.node_type = 'action'
      AND wn.node_config->>'action_type' = 'push_reward';

    IF NOT FOUND THEN
      RETURN public.fn_response_error(
        'Invalid slot',
        'Lifecycle push_reward action not found',
        'INVALID_SLOT'
      );
    END IF;

    UPDATE public.workflow_node
    SET
      node_config = node_config || jsonb_build_object('reward_id', p_reward_id),
      updated_at = now()
    WHERE id = v_node_id
      AND workflow_id = v_workflow_id
      AND merchant_id = v_merchant_id;

  ELSE
    RETURN public.fn_response_error(
      'Invalid slot',
      'source must be referral, tier_entry, or lifecycle',
      'INVALID_SLOT'
    );
  END IF;

  RETURN public.fn_response_success(
    'Reward attached',
    'Campaign reward attached to slot',
    jsonb_build_object(
      'source', v_source,
      'target', v_target,
      'reward_id', p_reward_id,
      'attached', true,
      'previous_reward_id', v_previous_reward_id
    )
  );
END;
$function$;

-- ---------------------------------------------------------------------------
-- B2 detach — never touches reward_master
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_campaign_reward_slot_detach(
  p_slot jsonb,
  p_reward_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_source text;
  v_target jsonb;
  v_kind text;
  v_party text;
  v_db_party text;
  v_tier_id uuid;
  v_workflow_id uuid;
  v_node_id uuid;
  v_deleted int := 0;
BEGIN
  v_merchant_id := public.get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN public.fn_response_error('No merchant', 'No merchant context', 'NO_MERCHANT');
  END IF;

  IF p_slot IS NULL OR jsonb_typeof(p_slot) <> 'object' OR p_reward_id IS NULL THEN
    RETURN public.fn_response_error('Invalid slot', 'p_slot and p_reward_id required', 'INVALID_SLOT');
  END IF;

  v_source := p_slot->>'source';
  v_target := COALESCE(p_slot->'target', '{}'::jsonb);

  IF v_source = 'referral' THEN
    v_kind := v_target->>'kind';
    v_party := v_target->>'party';
    IF v_kind NOT IN ('signup', 'purchase') OR v_party NOT IN ('referrer', 'friend') THEN
      RETURN public.fn_response_error('Invalid slot', 'Referral slot is incomplete', 'INVALID_SLOT');
    END IF;

    IF v_kind = 'purchase' AND v_party = 'friend' THEN
      UPDATE public.referral_program
      SET
        friend_offer = friend_offer || jsonb_build_object('reward_id', NULL),
        updated_at = now()
      WHERE merchant_id = v_merchant_id
        AND friend_offer->>'reward_id' = p_reward_id::text;
      GET DIAGNOSTICS v_deleted = ROW_COUNT;
    ELSE
      v_db_party := CASE WHEN v_party = 'referrer' THEN 'inviter' ELSE 'invitee' END;
      DELETE FROM public.referral_outcomes
      WHERE merchant_id = v_merchant_id
        AND kind = v_kind
        AND party = v_db_party
        AND outcome_type = 'reward'
        AND entity_id = p_reward_id;
      GET DIAGNOSTICS v_deleted = ROW_COUNT;
    END IF;

  ELSIF v_source = 'tier_entry' THEN
    v_tier_id := nullif(v_target->>'tier_id', '')::uuid;
    IF v_tier_id IS NULL THEN
      RETURN public.fn_response_error('Invalid slot', 'tier_entry slot needs tier_id', 'INVALID_SLOT');
    END IF;
    DELETE FROM public.tier_entry_rewards
    WHERE merchant_id = v_merchant_id
      AND tier_id = v_tier_id
      AND reward_kind = 'reward'
      AND reward_id = p_reward_id;
    GET DIAGNOSTICS v_deleted = ROW_COUNT;

  ELSIF v_source = 'lifecycle' THEN
    v_workflow_id := nullif(v_target->>'workflow_id', '')::uuid;
    v_node_id := nullif(v_target->>'node_id', '')::uuid;
    IF v_workflow_id IS NULL OR v_node_id IS NULL THEN
      RETURN public.fn_response_error('Invalid slot', 'lifecycle slot needs workflow_id and node_id', 'INVALID_SLOT');
    END IF;
    UPDATE public.workflow_node
    SET
      node_config = node_config - 'reward_id',
      updated_at = now()
    WHERE id = v_node_id
      AND workflow_id = v_workflow_id
      AND merchant_id = v_merchant_id
      AND node_type = 'action'
      AND node_config->>'action_type' = 'push_reward'
      AND node_config->>'reward_id' = p_reward_id::text;
    GET DIAGNOSTICS v_deleted = ROW_COUNT;

  ELSE
    RETURN public.fn_response_error('Invalid slot', 'source must be referral, tier_entry, or lifecycle', 'INVALID_SLOT');
  END IF;

  RETURN public.fn_response_success(
    'Reward detached',
    'Campaign reward removed from this slot',
    jsonb_build_object(
      'source', v_source,
      'target', v_target,
      'reward_id', p_reward_id,
      'detached', true,
      'removed', v_deleted
    )
  );
END;
$function$;

-- ---------------------------------------------------------------------------
-- B3 references
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_reward_references(p_reward_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_reward_ok boolean;
  v_referral_outcomes int := 0;
  v_referral_signup int := 0;
  v_referral_purchase int := 0;
  v_referral_friend_offer int := 0;
  v_tier_entry int := 0;
  v_lifecycle int := 0;
  v_redemptions int := 0;
  v_total int := 0;
  v_parts text[] := ARRAY[]::text[];
  v_summary text;
BEGIN
  v_merchant_id := public.get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN public.fn_response_error('No merchant', 'No merchant context', 'NO_MERCHANT');
  END IF;
  IF p_reward_id IS NULL THEN
    RETURN public.fn_response_error('Invalid reward', 'p_reward_id required', 'INVALID_REWARD');
  END IF;

  SELECT true INTO v_reward_ok
  FROM public.reward_master rm
  WHERE rm.id = p_reward_id AND rm.merchant_id = v_merchant_id;
  IF NOT FOUND THEN
    RETURN public.fn_response_error('Reward not found', 'Reward does not belong to this merchant', 'REWARD_NOT_FOUND');
  END IF;

  SELECT
    COUNT(*) FILTER (WHERE ro.kind = 'signup'),
    COUNT(*) FILTER (WHERE ro.kind = 'purchase'),
    COUNT(*)
  INTO v_referral_signup, v_referral_purchase, v_referral_outcomes
  FROM public.referral_outcomes ro
  WHERE ro.merchant_id = v_merchant_id
    AND ro.outcome_type = 'reward'
    AND ro.entity_id = p_reward_id;

  SELECT COUNT(*)
  INTO v_referral_friend_offer
  FROM public.referral_program rp
  WHERE rp.merchant_id = v_merchant_id
    AND rp.friend_offer->>'reward_id' = p_reward_id::text;

  SELECT COUNT(*)
  INTO v_tier_entry
  FROM public.tier_entry_rewards ter
  WHERE ter.merchant_id = v_merchant_id
    AND ter.reward_kind = 'reward'
    AND ter.reward_id = p_reward_id;

  SELECT COUNT(*)
  INTO v_lifecycle
  FROM public.workflow_node wn
  JOIN public.workflow_master wm ON wm.id = wn.workflow_id
  WHERE wn.merchant_id = v_merchant_id
    AND wn.node_type = 'action'
    AND wn.node_config->>'action_type' = 'push_reward'
    AND wn.node_config->>'reward_id' = p_reward_id::text
    AND wm.config->>'surface' = 'lifecycle_automation';

  SELECT COUNT(*)
  INTO v_redemptions
  FROM public.reward_redemptions_ledger rrl
  WHERE rrl.merchant_id = v_merchant_id
    AND rrl.reward_id = p_reward_id;

  v_total := v_referral_outcomes + v_referral_friend_offer + v_tier_entry + v_lifecycle + v_redemptions;

  IF v_referral_signup > 0 THEN
    v_parts := array_append(v_parts, 'Referral (signup)');
  END IF;
  IF v_referral_purchase > 0 THEN
    v_parts := array_append(v_parts, 'Referral (purchase)');
  END IF;
  IF v_referral_friend_offer > 0 THEN
    v_parts := array_append(v_parts, 'Referral (friend offer)');
  END IF;
  IF v_tier_entry > 0 THEN
    v_parts := array_append(v_parts, format('%s tier', v_tier_entry));
  END IF;
  IF v_lifecycle > 0 THEN
    v_parts := array_append(v_parts, format('%s automation', v_lifecycle));
  END IF;
  IF v_redemptions > 0 THEN
    v_parts := array_append(v_parts, format('%s redemptions', v_redemptions));
  END IF;

  v_summary := CASE
    WHEN v_total = 0 THEN 'Not referenced'
    ELSE array_to_string(v_parts, ', ')
  END;

  RETURN public.fn_response_success(
    'Reward references',
    v_summary,
    jsonb_build_object(
      'referral_outcomes', v_referral_outcomes,
      'referral_signup', v_referral_signup,
      'referral_purchase', v_referral_purchase,
      'referral_friend_offer', v_referral_friend_offer,
      'tier_entry_rewards', v_tier_entry,
      'lifecycle', v_lifecycle,
      'redemptions', v_redemptions,
      'total', v_total,
      'summary', v_summary
    )
  );
END;
$function$;

-- ---------------------------------------------------------------------------
-- B5 public wrappers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.bff_attach_campaign_reward(
  p_slot jsonb,
  p_reward_id uuid,
  p_language text DEFAULT 'en'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
BEGIN
  PERFORM public.fn_normalize_ui_language(p_language);
  v_merchant_id := public.get_current_merchant_id();
  IF v_merchant_id IS NULL
    OR NOT EXISTS (
      SELECT 1 FROM public.admin_users au
      WHERE au.auth_user_id = auth.uid()
        AND au.merchant_id = v_merchant_id
        AND au.active_status = true
    )
  THEN
    RETURN public.fn_response_error('Forbidden', 'Active merchant admin access required', 'FORBIDDEN');
  END IF;
  RETURN public.fn_campaign_reward_slot_attach(p_slot, p_reward_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_detach_campaign_reward(
  p_slot jsonb,
  p_reward_id uuid,
  p_language text DEFAULT 'en'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
BEGIN
  PERFORM public.fn_normalize_ui_language(p_language);
  v_merchant_id := public.get_current_merchant_id();
  IF v_merchant_id IS NULL
    OR NOT EXISTS (
      SELECT 1 FROM public.admin_users au
      WHERE au.auth_user_id = auth.uid()
        AND au.merchant_id = v_merchant_id
        AND au.active_status = true
    )
  THEN
    RETURN public.fn_response_error('Forbidden', 'Active merchant admin access required', 'FORBIDDEN');
  END IF;
  RETURN public.fn_campaign_reward_slot_detach(p_slot, p_reward_id);
END;
$function$;

-- ---------------------------------------------------------------------------
-- B4 atomic save + attach
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.bff_upsert_campaign_reward_atomic(
  p_reward jsonb,
  p_slot jsonb,
  p_request_id uuid,
  p_language text DEFAULT 'en'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_existing_reward_id uuid;
  v_reward_result jsonb;
  v_reward_id uuid;
  v_attach_result jsonb;
BEGIN
  PERFORM public.fn_normalize_ui_language(COALESCE(p_language, p_reward->>'p_language', 'en'));

  IF NOT EXISTS (
    SELECT 1 FROM public.admin_users au
    WHERE au.auth_user_id = auth.uid() AND au.active_status = true
  ) THEN
    RETURN public.fn_response_error('Forbidden', 'Admin access required', 'FORBIDDEN');
  END IF;

  v_merchant_id := public.get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN public.fn_response_error('No merchant', 'No merchant context', 'NO_MERCHANT');
  END IF;

  IF p_reward IS NULL OR jsonb_typeof(p_reward) <> 'object' THEN
    RETURN public.fn_response_error('Invalid reward', 'p_reward object required', 'INVALID_REWARD');
  END IF;

  IF p_slot IS NULL OR jsonb_typeof(p_slot) <> 'object' THEN
    RETURN public.fn_response_error('Invalid slot', 'p_slot object required', 'INVALID_SLOT');
  END IF;

  IF p_request_id IS NULL THEN
    RETURN public.fn_response_error('Invalid request', 'Request id required', 'INVALID_REQUEST_ID');
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(v_merchant_id::text || ':' || p_request_id::text, 0)
  );

  SELECT requests.reward_id
  INTO v_existing_reward_id
  FROM public.referral_reward_save_requests requests
  WHERE requests.merchant_id = v_merchant_id
    AND requests.request_id = p_request_id;

  IF v_existing_reward_id IS NOT NULL THEN
    RETURN public.fn_response_success(
      'Campaign reward saved',
      'This campaign reward was already saved.',
      jsonb_build_object(
        'reward_id', v_existing_reward_id,
        'operation', 'replayed',
        'slot', p_slot,
        'attached', true
      )
    );
  END IF;

  BEGIN
    v_reward_result := public.bff_upsert_reward_with_conditions_and_limits(
      p_reward_id => nullif(p_reward->>'p_reward_id', '')::uuid,
      p_name => p_reward->>'p_name',
      p_description_headline => p_reward->>'p_description_headline',
      p_description_body => p_reward->>'p_description_body',
      p_description_tc => p_reward->>'p_description_tc',
      p_description_slip => p_reward->>'p_description_slip',
      p_image => p_reward->'p_image',
      p_category_id => p_reward->'p_category_id',
      p_visibility => nullif(p_reward->>'p_visibility', '')::public.reward_visibility,
      p_redeem_window_start => nullif(p_reward->>'p_redeem_window_start', '')::timestamptz,
      p_redeem_window_end => nullif(p_reward->>'p_redeem_window_end', '')::timestamptz,
      p_stock_control => coalesce((p_reward->>'p_stock_control')::boolean, false),
      p_assign_promocode => coalesce((p_reward->>'p_assign_promocode')::boolean, false),
      p_use_expire_mode => nullif(p_reward->>'p_use_expire_mode', '')::public.reward_expire_mode,
      p_use_expire_date => nullif(p_reward->>'p_use_expire_date', '')::timestamptz,
      p_use_expire_ttl => nullif(p_reward->>'p_use_expire_ttl', '')::numeric,
      p_fulfillment_method => nullif(p_reward->>'p_fulfillment_method', '')::public.reward_fulfillment_method,
      p_allowed_tier => p_reward->'p_allowed_tier',
      p_allowed_persona => p_reward->'p_allowed_persona',
      p_allowed_tags => p_reward->'p_allowed_tags',
      p_allowed_birthmonth => p_reward->'p_allowed_birthmonth',
      p_fallback_points => nullif(p_reward->>'p_fallback_points', '')::numeric,
      p_require_points_match => coalesce((p_reward->>'p_require_points_match')::boolean, false),
      p_points_conditions => p_reward->'p_points_conditions',
      p_transaction_limits => p_reward->'p_transaction_limits',
      p_external_id_shopify => p_reward->>'p_external_id_shopify',
      p_online_store => p_reward->'p_online_store',
      p_reward_group_ids => p_reward->'p_reward_group_ids',
      p_shopify_discount_type => p_reward->>'p_shopify_discount_type',
      p_shopify_discount_label => p_reward->>'p_shopify_discount_label',
      p_variant_config => p_reward->'p_variant_config',
      p_physical_draw_name => p_reward->>'p_physical_draw_name',
      p_physical_draw_description => p_reward->>'p_physical_draw_description',
      p_language => coalesce(nullif(p_reward->>'p_language', ''), nullif(p_language, ''), 'en')
    );

    IF NOT coalesce((v_reward_result->>'success')::boolean, false) THEN
      RAISE EXCEPTION USING errcode = 'P0001', message = coalesce(v_reward_result->>'description', 'Reward save failed');
    END IF;

    v_reward_id := coalesce(
      nullif(v_reward_result#>>'{data,reward_id}', '')::uuid,
      nullif(v_reward_result->>'reward_id', '')::uuid
    );
    IF v_reward_id IS NULL THEN
      RAISE EXCEPTION USING errcode = 'P0001', message = 'Reward save returned no reward id';
    END IF;

    IF p_reward ? 'p_shopify_free_product_id'
      OR p_reward ? 'p_shopify_free_product_amount'
      OR p_reward ? 'p_shopify_free_product_sync_price'
    THEN
      UPDATE public.reward_master rm
      SET
        shopify_free_product_id = CASE
          WHEN p_reward ? 'p_shopify_free_product_id' THEN nullif(p_reward->>'p_shopify_free_product_id', '')
          ELSE rm.shopify_free_product_id
        END,
        shopify_free_product_amount = CASE
          WHEN p_reward ? 'p_shopify_free_product_amount' THEN nullif(p_reward->>'p_shopify_free_product_amount', '')::numeric
          ELSE rm.shopify_free_product_amount
        END,
        shopify_free_product_sync_price = CASE
          WHEN p_reward ? 'p_shopify_free_product_sync_price' THEN coalesce((p_reward->>'p_shopify_free_product_sync_price')::boolean, true)
          ELSE rm.shopify_free_product_sync_price
        END
      WHERE rm.id = v_reward_id AND rm.merchant_id = v_merchant_id;
    END IF;

    v_attach_result := public.fn_campaign_reward_slot_attach(p_slot, v_reward_id);
    IF NOT coalesce((v_attach_result->>'success')::boolean, false) THEN
      RAISE EXCEPTION USING errcode = 'P0001', message = coalesce(v_attach_result->>'description', 'Failed to attach reward');
    END IF;

    INSERT INTO public.referral_reward_save_requests (merchant_id, request_id, reward_id, slot)
    VALUES (v_merchant_id, p_request_id, v_reward_id, p_slot);
  EXCEPTION
    WHEN others THEN
      RETURN public.fn_response_error('Campaign reward not saved', SQLERRM, 'CAMPAIGN_REWARD_SAVE_FAILED');
  END;

  RETURN public.fn_response_success(
    'Campaign reward saved',
    'Reward saved and attached to the campaign slot.',
    jsonb_build_object(
      'reward_id', v_reward_id,
      'operation', lower(coalesce(v_reward_result->>'code', 'saved')),
      'slot', p_slot,
      'attached', true,
      'previous_reward_id', v_attach_result#>'{data,previous_reward_id}'
    )
  );
END;
$function$;

-- Old referral atomic becomes a purchase-slot wrapper (cut-over).
CREATE OR REPLACE FUNCTION public.bff_upsert_referral_reward_atomic_core(
  p_reward jsonb,
  p_referral jsonb,
  p_request_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
  RETURN public.bff_upsert_campaign_reward_atomic(
    p_reward,
    jsonb_build_object(
      'source', 'referral',
      'target', jsonb_build_object(
        'kind', 'purchase',
        'party', p_referral->>'party'
      ),
      'extra', COALESCE(p_referral, '{}'::jsonb)
    ),
    p_request_id,
    COALESCE(p_reward->>'p_language', 'en')
  );
END;
$function$;

-- ---------------------------------------------------------------------------
-- B6 delete guard
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_delete_reward(p_reward_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_reward_name text;
  v_limits_removed int := 0;
  v_translations_cleaned int := 0;
  v_refs jsonb;
  v_total int := 0;
BEGIN
  v_merchant_id := public.get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'title', 'No merchant context', 'description', null, 'data', null);
  END IF;

  SELECT name INTO v_reward_name
  FROM public.reward_master
  WHERE id = p_reward_id AND merchant_id = v_merchant_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'title', 'Reward not found',
      'description', 'Reward does not exist or does not belong to your merchant',
      'data', null
    );
  END IF;

  v_refs := public.fn_reward_references(p_reward_id);
  v_total := COALESCE((v_refs#>>'{data,total}')::int, 0);
  IF v_total > 0 THEN
    RETURN jsonb_build_object(
      'success', false,
      'title', 'Reward is in use',
      'description', COALESCE(v_refs#>>'{data,summary}', v_refs->>'description'),
      'data', v_refs->'data'
    );
  END IF;

  DELETE FROM public.transaction_limits
  WHERE entity_type = 'reward' AND entity_id = p_reward_id AND merchant_id = v_merchant_id;
  GET DIAGNOSTICS v_limits_removed = ROW_COUNT;

  DELETE FROM public.translations
  WHERE entity_type = 'reward' AND entity_id = p_reward_id AND merchant_id = v_merchant_id;
  GET DIAGNOSTICS v_translations_cleaned = ROW_COUNT;

  DELETE FROM public.reward_master WHERE id = p_reward_id AND merchant_id = v_merchant_id;

  RETURN jsonb_build_object(
    'success', true,
    'title', format('Reward "%s" deleted', v_reward_name),
    'description', null,
    'data', jsonb_build_object(
      'reward_id', p_reward_id,
      'reward_name', v_reward_name,
      'limits_removed', v_limits_removed,
      'translations_cleaned', v_translations_cleaned
    )
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_campaign_reward_slot_attach(jsonb, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_campaign_reward_slot_detach(jsonb, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_reward_references(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_attach_campaign_reward(jsonb, uuid, text) TO authenticated, service_role, anon;
GRANT EXECUTE ON FUNCTION public.bff_detach_campaign_reward(jsonb, uuid, text) TO authenticated, service_role, anon;
GRANT EXECUTE ON FUNCTION public.bff_upsert_campaign_reward_atomic(jsonb, jsonb, uuid, text) TO authenticated, service_role, anon;
