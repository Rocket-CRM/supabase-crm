-- Purchase referral friend slot: when attaching an existing campaign reward, copy
-- Shopify mother discount from reward_master so storefront claim can mint codes.

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
  v_reward_external_id text;
  v_reward_shopify_type text;
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

      SELECT
        nullif(rm.external_id_shopify, ''),
        rm.shopify_discount_type::text
      INTO v_reward_external_id, v_reward_shopify_type
      FROM public.reward_master rm
      WHERE rm.id = p_reward_id AND rm.merchant_id = v_merchant_id;

      IF v_mother_discount_id IS NULL THEN
        v_mother_discount_id := v_reward_external_id;
      END IF;
      IF v_discount_type IS NULL THEN
        v_discount_type := v_reward_shopify_type;
      END IF;

      IF nullif(v_mother_discount_id, '') IS NULL THEN
        RETURN public.fn_response_error(
          'No Shopify discount',
          'This reward has no Shopify discount for friend referral codes',
          'NO_MOTHER_DISCOUNT'
        );
      END IF;

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
        shopify_mother_discount_id = v_mother_discount_id,
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
