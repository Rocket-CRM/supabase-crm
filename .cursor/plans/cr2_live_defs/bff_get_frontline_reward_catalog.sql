CREATE OR REPLACE FUNCTION public.bff_get_frontline_reward_catalog(p_language text DEFAULT NULL::text, p_user_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id UUID;
  v_language TEXT;
  v_result JSONB;
  v_price_map JSONB;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'No merchant context', 'code', 'NO_MERCHANT_CONTEXT');
  END IF;

  IF NOT (
    check_admin_permission('frontline_redemption_reward', 'read')
    OR check_admin_permission('front_line', 'read')
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Permission denied', 'code', 'ACCESS_DENIED');
  END IF;

  SELECT language_code INTO v_language
  FROM merchant_languages
  WHERE merchant_id = v_merchant_id AND is_default = true
  LIMIT 1;
  v_language := COALESCE(p_language, v_language, 'en');

  IF p_user_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM user_accounts ua
    WHERE ua.id = p_user_id AND ua.merchant_id = v_merchant_id AND ua.deleted_at IS NULL
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'User not found in merchant');
  END IF;

  WITH reward_trans AS (
    SELECT
      t.entity_id,
      MAX(CASE WHEN t.field_name = 'name' THEN t.translated_value END) AS t_name,
      MAX(CASE WHEN t.field_name = 'description_headline' THEN t.translated_value END) AS t_headline,
      MAX(CASE WHEN t.field_name = 'description_body' THEN t.translated_value END) AS t_body,
      MAX(CASE WHEN t.field_name = 'description_tc' THEN t.translated_value END) AS t_tc,
      MAX(CASE WHEN t.field_name = 'description_slip' THEN t.translated_value END) AS t_slip
    FROM translations t
    WHERE t.entity_type = 'reward' AND t.language_code = v_language
    GROUP BY t.entity_id
  )
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', r.id,
        'name', COALESCE(rt.t_name, r.name),
        'description_headline', COALESCE(rt.t_headline, r.description_headline),
        'description_body', COALESCE(rt.t_body, r.description_body),
        'description_tc', COALESCE(rt.t_tc, r.description_tc),
        'description_slip', COALESCE(rt.t_slip, r.description_slip),
        'category_id', r.category_id,
        'points', jsonb_build_object('fallback', COALESCE(r.fallback_points, 0)),
        'image', to_jsonb(COALESCE(r.image, ARRAY[]::TEXT[])),
        'visibility', r.visibility,
        'ranking', r.ranking,
        'is_featured', COALESCE(r.is_featured, false),
        'active_status', r.active_status,
        'redeem_window_start', r.redeem_window_start,
        'redeem_window_end', r.redeem_window_end,
        'eligibility', jsonb_build_object(
          'allowed_tiers', (
            SELECT COALESCE(jsonb_agg(jsonb_build_object('id', t.id, 'name', t.tier_name, 'icon', t.icon, 'color', t.color)), '[]'::jsonb)
            FROM unnest(COALESCE(r.allowed_tier, ARRAY[]::uuid[])) AS tier_id
            JOIN tier_master t ON t.id = tier_id WHERE t.merchant_id = v_merchant_id
          ),
          'allowed_personas', (
            SELECT COALESCE(jsonb_agg(jsonb_build_object('id', p.id, 'name', p.persona_name, 'image', p.image)), '[]'::jsonb)
            FROM unnest(COALESCE(r.allowed_persona, ARRAY[]::uuid[])) AS persona_id
            JOIN persona_master p ON p.id = persona_id WHERE p.merchant_id = v_merchant_id
          ),
          'allowed_tags', (
            SELECT COALESCE(jsonb_agg(jsonb_build_object('id', tg.id, 'name', tg.tag_name)), '[]'::jsonb)
            FROM unnest(COALESCE(r.allowed_tags, ARRAY[]::uuid[])) AS tag_id
            JOIN tag_master tg ON tg.id = tag_id WHERE tg.merchant_id = v_merchant_id
          ),
          'allowed_birthmonths', to_jsonb(COALESCE(r.allowed_birthmonth, ARRAY[]::text[]))
        ),
        'stock_control', r.stock_control,
        'use_expire_mode', r.use_expire_mode,
        'use_expire_date', r.use_expire_date,
        'use_expire_ttl', r.use_expire_ttl,
        'fulfillment_method', r.fulfillment_method,
        'assign_promocode', r.assign_promocode,
        'promo_code', r.promo_code,
        'require_points_match', r.require_points_match,
        'online_store', to_jsonb(COALESCE(r.online_store, ARRAY[]::text[])),
        'reward_group_ids', to_jsonb(COALESCE(r.reward_group_ids, ARRAY[]::uuid[]))
      )
      ORDER BY r.ranking NULLS LAST, r.name
    ),
    '[]'::jsonb
  )
  INTO v_result
  FROM reward_master r
  LEFT JOIN reward_trans rt ON rt.entity_id = r.id
  WHERE r.merchant_id = v_merchant_id
    AND r.active_status = true
    AND r.visibility IN ('user', 'admin')
    AND (r.redeem_window_end IS NULL OR now() <= r.redeem_window_end);

  IF p_user_id IS NOT NULL THEN
    WITH user_attrs AS (
      SELECT ua.tier_id, ua.user_type, ua.persona_id, ua.birth_date,
        COALESCE((SELECT array_agg(ut.tag_id) FROM user_tags ut WHERE ut.user_id = ua.id), ARRAY[]::uuid[]) AS tag_ids
      FROM user_accounts ua
      WHERE ua.id = p_user_id AND ua.merchant_id = v_merchant_id
    ),
    best_cond AS (
      SELECT DISTINCT ON (rpc.reward_id)
        rpc.reward_id,
        rpc.points_required
      FROM reward_points_conditions rpc
      CROSS JOIN user_attrs u
      WHERE rpc.active_status = true
        AND (rpc.tier_id IS NULL OR rpc.tier_id = u.tier_id)
        AND (rpc.user_type IS NULL OR rpc.user_type = u.user_type)
        AND (rpc.persona_id IS NULL OR rpc.persona_id = u.persona_id)
        AND (rpc.tag_ids IS NULL OR u.tag_ids IS NULL OR rpc.tag_ids && u.tag_ids)
      ORDER BY rpc.reward_id,
        ((rpc.tier_id IS NOT NULL)::int + (rpc.user_type IS NOT NULL)::int
          + (rpc.persona_id IS NOT NULL)::int + (rpc.tag_ids IS NOT NULL)::int) DESC,
        rpc.priority DESC NULLS LAST,
        rpc.points_required ASC
    ),
    priced AS (
      SELECT r.id::text AS reward_id,
        (
          (r.allowed_tier IS NULL OR cardinality(r.allowed_tier) = 0 OR u.tier_id = ANY (r.allowed_tier))
          AND (r.allowed_persona IS NULL OR cardinality(r.allowed_persona) = 0 OR (u.persona_id IS NOT NULL AND u.persona_id = ANY (r.allowed_persona)))
          AND (r.allowed_tags IS NULL OR cardinality(r.allowed_tags) = 0 OR (u.tag_ids && r.allowed_tags))
          AND (r.allowed_birthmonth IS NULL OR cardinality(r.allowed_birthmonth) = 0 OR (u.birth_date IS NOT NULL AND EXTRACT(MONTH FROM u.birth_date)::int::text = ANY (r.allowed_birthmonth)))
          AND (r.redeem_window_start IS NULL OR now() >= r.redeem_window_start)
          AND (r.redeem_window_end IS NULL OR now() <= r.redeem_window_end)
        ) AS user_eligible,
        COALESCE(bc.points_required, r.fallback_points, 0) AS points_required
      FROM reward_master r
      CROSS JOIN user_attrs u
      LEFT JOIN best_cond bc ON bc.reward_id = r.id
      WHERE r.merchant_id = v_merchant_id
        AND r.active_status = true
        AND r.visibility IN ('user', 'admin')
        AND (r.redeem_window_end IS NULL OR now() <= r.redeem_window_end)
    )
    SELECT COALESCE(jsonb_object_agg(reward_id, jsonb_build_object(
      'user_eligible', user_eligible,
      'points_required', CASE WHEN user_eligible THEN points_required ELSE COALESCE(points_required, 0) END
    )), '{}'::jsonb)
    INTO v_price_map
    FROM priced;

    SELECT COALESCE(jsonb_agg(
      elem || jsonb_build_object(
        'user_eligible', COALESCE((v_price_map->(elem->>'id')->>'user_eligible')::boolean, true),
        'points_required', COALESCE(
          (v_price_map->(elem->>'id')->>'points_required')::numeric,
          (elem#>>'{points,fallback}')::numeric,
          0
        )
      )
    ), '[]'::jsonb)
    INTO v_result
    FROM jsonb_array_elements(COALESCE(v_result, '[]'::jsonb)) elem;
  END IF;

  RETURN jsonb_build_object('success', true, 'data', v_result);
END;
$function$
