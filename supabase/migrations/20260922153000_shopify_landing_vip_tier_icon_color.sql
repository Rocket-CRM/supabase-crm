-- Landing VIP matrix: pass tier icon + color from hub into landing payload

CREATE OR REPLACE FUNCTION public.fn_shopify_landing_vip_tiers_from_hub(
  p_hub_tiers jsonb,
  p_current_tier_id uuid DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
  v_labels text[] := ARRAY[]::text[];
  v_label text;
  v_tier jsonb;
  v_out jsonb := '[]'::jsonb;
  v_benefits jsonb;
  v_row jsonb;
  v_perk text;
  v_reward text;
  v_has boolean;
BEGIN
  IF p_hub_tiers IS NULL OR jsonb_typeof(p_hub_tiers) <> 'array' THEN
    RETURN '[]'::jsonb;
  END IF;
  FOR v_tier IN SELECT * FROM jsonb_array_elements(p_hub_tiers)
  LOOP
    FOR v_reward IN SELECT jsonb_array_elements_text(COALESCE(v_tier -> 'entry_rewards', '[]'::jsonb))
    LOOP
      IF v_reward IS NOT NULL AND btrim(v_reward) <> '' AND NOT (v_reward = ANY (v_labels)) THEN
        v_labels := array_append(v_labels, v_reward);
      END IF;
    END LOOP;
    FOR v_perk IN SELECT jsonb_array_elements_text(COALESCE(v_tier -> 'perks', '[]'::jsonb))
    LOOP
      IF v_perk IS NOT NULL AND btrim(v_perk) <> '' AND NOT (v_perk = ANY (v_labels)) THEN
        v_labels := array_append(v_labels, v_perk);
      END IF;
    END LOOP;
  END LOOP;
  FOR v_tier IN SELECT * FROM jsonb_array_elements(p_hub_tiers)
  LOOP
    v_benefits := '[]'::jsonb;
    FOREACH v_label IN ARRAY v_labels
    LOOP
      SELECT EXISTS (
        SELECT 1
        FROM jsonb_array_elements_text(COALESCE(v_tier -> 'entry_rewards', '[]'::jsonb)) er(v)
        WHERE er.v = v_label
      ) INTO v_has;
      IF v_has THEN
        v_row := jsonb_build_object('label', v_label, 'state', 'value', 'value', v_label);
      ELSIF EXISTS (
        SELECT 1
        FROM jsonb_array_elements_text(COALESCE(v_tier -> 'perks', '[]'::jsonb)) pk(v)
        WHERE pk.v = v_label
      ) THEN
        v_row := jsonb_build_object('label', v_label, 'state', 'included');
      ELSE
        v_row := jsonb_build_object('label', v_label, 'state', 'excluded');
      END IF;
      v_benefits := v_benefits || jsonb_build_array(v_row);
    END LOOP;
    v_out := v_out || jsonb_build_array(
      jsonb_build_object(
        'id', v_tier ->> 'id',
        'name', v_tier ->> 'name',
        'icon_url', COALESCE(v_tier ->> 'icon', ''),
        'color', COALESCE(v_tier ->> 'color', ''),
        'threshold_label', COALESCE(v_tier ->> 'threshold_label', ''),
        'description', '',
        'badge', NULL,
        'highlight', false,
        'current',
          (p_current_tier_id IS NOT NULL AND (v_tier ->> 'id')::uuid = p_current_tier_id)
          OR COALESCE((v_tier ->> 'is_current')::boolean, false),
        'benefits', v_benefits
      )
    );
  END LOOP;
  RETURN v_out;
END;
$function$;

-- Hub tiers: include tier_master.color for landing column tints
CREATE OR REPLACE FUNCTION public.fn_compose_shopify_hub_unbranded(p_merchant_id uuid, p_user_id uuid, p_language text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_language text;
  v_store_name text;
  v_store_url text;
  v_points_name text;
  v_symbol_type text;
  v_symbol_icon text;
  v_symbol_image text;
  v_hero text;
  v_header_type text;
  v_header_items jsonb;
  v_earn_rate jsonb;
  v_member jsonb;
  v_my_rewards jsonb;
  v_spend jsonb;
  v_shop jsonb;
  v_tiers jsonb;
  v_earn jsonb;
  v_referral jsonb;
  v_ua public.user_accounts;
  v_balance numeric := 0;
  v_expiry date;
  v_expiring numeric;
  v_expiry_json jsonb;
  v_as_of date := (timezone('Asia/Bangkok', now()))::date;
  v_tp record;
  v_program public.referral_program;
  v_member_code text;
  v_hop text;
  v_share_url text;
BEGIN
  IF p_merchant_id IS NULL THEN
    RETURN jsonb_build_object('error_code', 'NO_MERCHANT_CONTEXT');
  END IF;

  SELECT language_code INTO v_language
  FROM public.merchant_languages
  WHERE merchant_id = p_merchant_id AND is_default = true
  LIMIT 1;
  v_language := COALESCE(NULLIF(trim(p_language), ''), v_language, 'en');

  SELECT mm.name INTO v_store_name FROM public.merchant_master mm WHERE mm.id = p_merchant_id;

  SELECT 'https://' || (mc.credentials->>'shop_domain')
  INTO v_store_url
  FROM public.merchant_credentials mc
  WHERE mc.merchant_id = p_merchant_id
    AND mc.service_name = 'shopify_app'
    AND mc.is_active IS TRUE
    AND NULLIF(mc.credentials->>'shop_domain', '') IS NOT NULL
  LIMIT 1;

  SELECT
    mds.points_unit_label,
    mds.points_symbol_type,
    mds.points_symbol_icon,
    mds.points_symbol_image_url
  INTO v_points_name, v_symbol_type, v_symbol_icon, v_symbol_image
  FROM public.merchant_display_settings mds
  WHERE mds.merchant_id = p_merchant_id;
  v_points_name := COALESCE(NULLIF(btrim(v_points_name), ''), 'Points');

  SELECT
    mws.config #>> '{header,background,type}',
    mws.config #> '{header,background,image,items}'
  INTO v_header_type, v_header_items
  FROM public.merchant_widget_settings mws
  WHERE mws.merchant_id = p_merchant_id
    AND mws.widget_type = 'shopify'
    AND mws.active_status IS TRUE
  LIMIT 1;

  IF v_header_type = 'image' AND jsonb_typeof(v_header_items) = 'array' THEN
    SELECT item->>'url'
    INTO v_hero
    FROM jsonb_array_elements(v_header_items) AS item
    WHERE NULLIF(item->>'url', '') IS NOT NULL
    ORDER BY COALESCE((item->>'order')::int, 0)
    LIMIT 1;
  END IF;

  v_earn_rate := public.fn_resolve_widget_earn_rate(p_merchant_id);

  IF p_user_id IS NOT NULL THEN
    SELECT * INTO v_ua FROM public.user_accounts
    WHERE id = p_user_id AND merchant_id = p_merchant_id AND deleted_at IS NULL;
  END IF;

  IF v_ua.id IS NOT NULL THEN
    SELECT COALESCE(uw.points_balance, 0) INTO v_balance
    FROM public.user_wallet uw
    WHERE uw.user_id = v_ua.id AND uw.merchant_id = p_merchant_id;

    IF public.fn_loyalty_expiry_display_enabled(p_merchant_id) THEN
      v_expiry_json := public.fn_loyalty_expiry_envelope(v_ua.id, p_merchant_id, v_as_of);
      v_expiry := NULLIF(v_expiry_json -> 'next' ->> 'expiry_date', '')::date;
      v_expiring := COALESCE((v_expiry_json -> 'next' ->> 'amount')::numeric, 0);
    END IF;

    SELECT
      tp.next_tier_id,
      nt.tier_name AS next_tier_name,
      tp.upgrade_progress_percent,
      tp.upgrade_metric_current,
      tp.upgrade_threshold,
      tp.maintain_deadline,
      GREATEST(0, COALESCE(tp.upgrade_threshold, 0) - COALESCE(tp.upgrade_metric_current, 0)) AS amount_to_next
    INTO v_tp
    FROM public.tier_progress tp
    LEFT JOIN public.tier_master nt ON nt.id = tp.next_tier_id
    WHERE tp.user_id = v_ua.id AND tp.merchant_id = p_merchant_id;

    SELECT jsonb_build_object(
      'first_name', v_ua.firstname,
      'points_balance', v_balance,
      'points_expiry_date', v_expiry,
      'points_expiring_next', v_expiring,
      'tier', CASE WHEN tm.id IS NULL THEN NULL ELSE jsonb_build_object(
        'id', tm.id,
        'name', tm.tier_name,
        'icon', tm.icon,
        'attained_until', v_tp.maintain_deadline,
        'next_tier_name', v_tp.next_tier_name,
        'amount_to_next', v_tp.amount_to_next,
        'progress_value', COALESCE(v_tp.upgrade_metric_current, 0),
        'progress_max', COALESCE(v_tp.upgrade_threshold, 0),
        'metric', NULL
      ) END
    )
    INTO v_member
    FROM (SELECT 1) s
    LEFT JOIN public.tier_master tm ON tm.id = v_ua.tier_id;
  END IF;

  IF v_ua.id IS NOT NULL THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'redemption_id', rrl.id,
      'reward_name', rm.name,
      'discount_label', rm.shopify_discount_label,
      'code', COALESCE(NULLIF(rrl.promo_code, ''), rrl.code),
      'use_expire_date', rrl.use_expire_date,
      'terms', rm.description_tc
    ) ORDER BY rrl.created_at DESC), '[]'::jsonb)
    INTO v_my_rewards
    FROM public.reward_redemptions_ledger rrl
    LEFT JOIN public.reward_master rm ON rm.id = rrl.reward_id
    WHERE rrl.merchant_id = p_merchant_id
      AND rrl.user_id = v_ua.id
      AND rrl.redeemed_status = true
      AND COALESCE(rrl.used_status, false) = false
      AND COALESCE(rrl.cancelled, false) = false
      AND (rrl.use_expire_date IS NULL OR rrl.use_expire_date > now());
  ELSE
    v_my_rewards := '[]'::jsonb;
  END IF;

  WITH priced AS (
    SELECT
      r.id,
      r.name,
      r.shopify_discount_label,
      r.shopify_discount_type,
      r.shopify_free_product_id,
      CASE WHEN r.image IS NOT NULL AND cardinality(r.image) > 0 THEN r.image[1] ELSE NULL END AS image_url,
      CASE
        WHEN best_match.id IS NOT NULL THEN best_match.points_required
        WHEN r.fallback_points IS NOT NULL THEN r.fallback_points
        ELSE 0
      END AS cost
    FROM public.reward_master r
    LEFT JOIN LATERAL (
      SELECT rpc.id, rpc.points_required
      FROM public.reward_points_conditions rpc
      WHERE v_ua.id IS NOT NULL
        AND rpc.reward_id = r.id
        AND rpc.active_status = true
        AND (rpc.tier_id IS NULL OR rpc.tier_id = v_ua.tier_id)
        AND (rpc.user_type IS NULL OR rpc.user_type = v_ua.user_type)
        AND (rpc.persona_id IS NULL OR rpc.persona_id = v_ua.persona_id)
      ORDER BY
        (CASE WHEN rpc.tier_id IS NOT NULL THEN 1 ELSE 0 END
         + CASE WHEN rpc.user_type IS NOT NULL THEN 1 ELSE 0 END
         + CASE WHEN rpc.persona_id IS NOT NULL THEN 1 ELSE 0 END) DESC,
        rpc.priority DESC NULLS LAST,
        rpc.points_required ASC
      LIMIT 1
    ) best_match ON true
    WHERE r.merchant_id = p_merchant_id
      AND r.active_status IS TRUE
      AND COALESCE(r.visibility::text, 'user') = 'user'
      AND r.shopify_discount_type IN ('percentage', 'fixed_amount', 'free_shipping', 'free_product')
  )
  SELECT
    COALESCE(jsonb_agg(jsonb_build_object(
      'reward_id', p.id,
      'name', p.name,
      'discount_label', p.shopify_discount_label,
      'cost', p.cost,
      'affordable', v_ua.id IS NOT NULL AND v_balance >= COALESCE(p.cost, 0),
      'image_url', p.image_url
    ) ORDER BY p.name) FILTER (WHERE p.shopify_discount_type IN ('percentage', 'fixed_amount', 'free_shipping')), '[]'::jsonb),
    COALESCE(jsonb_agg(jsonb_build_object(
      'reward_id', p.id,
      'name', p.name,
      'discount_label', p.shopify_discount_label,
      'cost', p.cost,
      'affordable', v_ua.id IS NOT NULL AND v_balance >= COALESCE(p.cost, 0),
      'image_url', p.image_url,
      'shopify_product_id', p.shopify_free_product_id
    ) ORDER BY p.name) FILTER (WHERE p.shopify_discount_type = 'free_product'), '[]'::jsonb)
  INTO v_spend, v_shop
  FROM priced p;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', tm.id,
    'name', tm.tier_name,
    'icon', tm.icon,
    'color', tm.color,
    'threshold_label', CASE WHEN tcu.amount IS NULL THEN NULL ELSE tcu.amount::text END,
    'is_current', v_ua.tier_id IS NOT NULL AND tm.id = v_ua.tier_id,
    'entry_rewards', COALESCE((
      SELECT jsonb_agg(
        COALESCE(NULLIF(btrim(ter.description), ''), rm.name, (ter.points_amount::text || ' ' || v_points_name))
        ORDER BY ter.sort_order, ter.created_at
      )
      FROM public.tier_entry_rewards ter
      LEFT JOIN public.reward_master rm ON rm.id = ter.reward_id
      WHERE ter.merchant_id = p_merchant_id
        AND ter.tier_id = tm.id
        AND ter.active_status IS TRUE
    ), '[]'::jsonb),
    'perks', COALESCE((
      SELECT jsonb_agg(COALESCE(perk->>'name', perk->>'title', perk->>'label', perk->>'description'))
      FROM jsonb_array_elements(public.fn_tier_composed_perks_json(tm.id)) perk
      WHERE COALESCE(perk->>'name', perk->>'title', perk->>'label', perk->>'description') IS NOT NULL
    ), '[]'::jsonb)
  ) ORDER BY tcu.amount ASC NULLS FIRST, tm.tier_name), '[]'::jsonb)
  INTO v_tiers
  FROM public.tier_master tm
  LEFT JOIN public.tier_conditions tcu
    ON tcu.tier_id = tm.id AND tcu.condition_type = 'upgrade' AND tcu.active_status IS TRUE
  WHERE tm.merchant_id = p_merchant_id
    AND tm.tier_name IS NOT NULL
    AND btrim(tm.tier_name) <> '';

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', c.id,
    'method', CASE
      WHEN c.channel_code = 'shopify_store' THEN 'purchase'
      WHEN c.method_type = 'referral' OR c.channel_code ILIKE '%referral%' THEN 'referral'
      WHEN c.channel_code ILIKE '%birthday%' THEN 'birthday'
      WHEN c.method_type = 'social' THEN 'social'
      WHEN c.method_type = 'external_link' THEN 'external_link'
      ELSE COALESCE(c.method_type, 'external_link')
    END,
    'title', COALESCE(c.headline, c.channel_name),
    'description', c.description,
    'reward_copy', CASE
      WHEN c.channel_code = 'shopify_store' AND (v_earn_rate->>'base_points_per_unit') IS NOT NULL THEN
        trim(to_char(COALESCE((v_earn_rate->>'base_points_per_unit')::numeric, 0), 'FM999990.099999'))
        || ' ' || v_points_name || ' for every '
        || CASE
             WHEN NULLIF(v_earn_rate->>'currency', '') IS NULL THEN '1'
             ELSE (v_earn_rate->>'currency') || '1'
           END
        || ' spent'
      ELSE COALESCE(c.howto_description, c.description)
    END,
    'cta_label', COALESCE(c.button_action->>'label', 'Learn more'),
    'cta_url', CASE
      WHEN c.channel_code = 'shopify_store' THEN v_store_url
      WHEN c.method_type = 'referral' OR c.channel_code ILIKE '%referral%' THEN '#referrals'
      WHEN c.method_type = 'external_link' THEN COALESCE(c.config->>'value', c.button_action->>'value')
      ELSE COALESCE(c.config->>'value', c.button_action->>'value')
    END,
    'icon_url', COALESCE(
      c.icon_url,
      (
        SELECT r.default_icon_url
        FROM public.earn_channel_registry r
        WHERE r.channel_code = c.channel_code
          AND COALESCE(r.is_active, true) = true
        LIMIT 1
      )
    )
  ) ORDER BY c.display_order ASC, c.channel_name ASC), '[]'::jsonb)
  INTO v_earn
  FROM public.fn_get_effective_earn_channels(p_merchant_id, v_language, false) c
  WHERE c.active = true
    AND c.channel_type <> 'campaign'
    AND NOT (c.channel_type = 'purchase' AND c.channel_code <> 'shopify_store');

  SELECT * INTO v_program FROM public.referral_program WHERE merchant_id = p_merchant_id;
  IF v_program.id IS NOT NULL AND v_program.is_active AND 'shopify' = ANY (COALESCE(v_program.platforms, '{}'::text[])) THEN
    IF v_ua.id IS NOT NULL AND COALESCE(v_program.purchase_enabled, false) THEN
      v_member_code := public.fn_ensure_member_code(v_ua.id, p_merchant_id);
      v_hop := public.fn_referral_share_hop(p_merchant_id);
      IF v_hop IS NOT NULL AND v_member_code IS NOT NULL THEN
        v_share_url := v_hop || '?p=shopify&r=' || v_member_code;
      END IF;
    END IF;
    v_referral := jsonb_build_object(
      'active', true,
      'share_url', v_share_url,
      'you_get', COALESCE(v_program.friend_offer->>'referrer_label', v_program.friend_offer->>'you_get', 'A thank-you reward'),
      'they_get', COALESCE(v_program.friend_offer->>'headline', v_program.friend_offer->>'label', v_program.friend_offer->>'they_get', 'A welcome reward'),
      'intro', COALESCE(v_program.friend_offer->>'intro', 'Share your link. They get a reward, you get one when they order.')
    );
  ELSE
    v_referral := NULL;
  END IF;

  RETURN jsonb_build_object(
    'branding', jsonb_build_object(
      'store_name', COALESCE(v_store_name, ''),
      'store_url', v_store_url,
      'points_name', v_points_name,
      'points_symbol', jsonb_build_object(
        'type', v_symbol_type,
        'icon', v_symbol_icon,
        'image_url', v_symbol_image
      ),
      'hero_image_url', v_hero
    ),
    'member', v_member,
    'my_rewards', COALESCE(v_my_rewards, '[]'::jsonb),
    'spend', COALESCE(v_spend, '[]'::jsonb),
    'shop', COALESCE(v_shop, '[]'::jsonb),
    'tiers', COALESCE(v_tiers, '[]'::jsonb),
    'earn', COALESCE(v_earn, '[]'::jsonb),
    'referral', v_referral,
    'earn_rate', v_earn_rate
  );
END;
$function$;

