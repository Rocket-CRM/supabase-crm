CREATE OR REPLACE FUNCTION public.api_get_rewards_full_cached(p_language text DEFAULT NULL::text, p_persona_id uuid DEFAULT NULL::uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_merchant_id UUID;
  v_language TEXT;
  v_cache_key TEXT;
  v_cached_result TEXT;
  v_cached_data JSONB;
  v_result JSON;
  v_categories JSON;
  v_groups JSONB;
  v_total_count INT;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RAISE EXCEPTION 'No merchant context found';
  END IF;

  SELECT language_code INTO v_language
  FROM merchant_languages
  WHERE merchant_id = v_merchant_id AND is_default = true
  LIMIT 1;

  v_language := COALESCE(p_language, v_language, 'en');

  IF p_persona_id IS NULL THEN
    v_cache_key := 'merchant:' || v_merchant_id::TEXT || ':rewards:' || v_language;
  ELSE
    v_cache_key := 'merchant:' || v_merchant_id::TEXT || ':rewards:persona:' || p_persona_id::TEXT || ':' || v_language;
  END IF;

  BEGIN
    v_cached_result := extensions.rewards_cache_get(v_cache_key);
    IF v_cached_result IS NOT NULL THEN
      v_cached_data := v_cached_result::JSONB;
      RETURN v_cached_data || jsonb_build_object(
        'cache_hit', true,
        'timestamp', NOW()
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  WITH reward_trans AS (
    SELECT
      t.entity_id,
      MAX(CASE WHEN t.field_name = 'name' THEN t.translated_value END) as t_name,
      MAX(CASE WHEN t.field_name = 'description_headline' THEN t.translated_value END) as t_headline,
      MAX(CASE WHEN t.field_name = 'description_body' THEN t.translated_value END) as t_body,
      MAX(CASE WHEN t.field_name = 'description_tc' THEN t.translated_value END) as t_tc,
      MAX(CASE WHEN t.field_name = 'description_slip' THEN t.translated_value END) as t_slip
    FROM translations t
    WHERE t.entity_type = 'reward'
      AND t.language_code = v_language
    GROUP BY t.entity_id
  )
  SELECT json_agg(
    json_build_object(
      'id', r.id,
      'name', COALESCE(rt.t_name, r.name),
      'description_headline', COALESCE(rt.t_headline, r.description_headline),
      'description_body', COALESCE(rt.t_body, r.description_body),
      'description_tc', COALESCE(rt.t_tc, r.description_tc),
      'description_slip', COALESCE(rt.t_slip, r.description_slip),
      'category_id', r.category_id,
      'points', json_build_object('fallback', COALESCE(r.fallback_points, 0)),
      'image', COALESCE(r.image, ARRAY[]::TEXT[]),
      'visibility', r.visibility,
      'ranking', r.ranking,
      'is_featured', COALESCE(r.is_featured, false),
      'active_status', r.active_status,
      'redeem_window_start', r.redeem_window_start,
      'redeem_window_end', r.redeem_window_end,
      'eligibility', json_build_object(
        'allowed_tiers', (
          SELECT COALESCE(json_agg(json_build_object(
            'id', t.id,
            'name', t.tier_name,
            'icon', t.icon,
            'color', t.color
          )), '[]'::json)
          FROM unnest(COALESCE(r.allowed_tier, ARRAY[]::uuid[])) AS tier_id
          JOIN tier_master t ON t.id = tier_id
          WHERE t.merchant_id = v_merchant_id
        ),
        'allowed_personas', (
          SELECT COALESCE(json_agg(json_build_object(
            'id', p.id,
            'name', p.persona_name,
            'image', p.image
          )), '[]'::json)
          FROM unnest(COALESCE(r.allowed_persona, ARRAY[]::uuid[])) AS persona_id
          JOIN persona_master p ON p.id = persona_id
          WHERE p.merchant_id = v_merchant_id
        ),
        'allowed_tags', (
          SELECT COALESCE(json_agg(json_build_object(
            'id', tg.id,
            'name', tg.tag_name
          )), '[]'::json)
          FROM unnest(COALESCE(r.allowed_tags, ARRAY[]::uuid[])) AS tag_id
          JOIN tag_master tg ON tg.id = tag_id
          WHERE tg.merchant_id = v_merchant_id
        ),
        'allowed_birthmonths', COALESCE(r.allowed_birthmonth, ARRAY[]::text[])
      ),
      'stock_control', r.stock_control,
      'use_expire_mode', r.use_expire_mode,
      'use_expire_date', r.use_expire_date,
      'use_expire_ttl', r.use_expire_ttl,
      'fulfillment_method', r.fulfillment_method,
      'assign_promocode', r.assign_promocode,
      'promo_code', r.promo_code,
      'require_points_match', r.require_points_match,
      'online_store', COALESCE(r.online_store, ARRAY[]::text[]),
      'reward_group_ids', COALESCE(r.reward_group_ids, ARRAY[]::uuid[])
    )
  ) INTO v_result
  FROM reward_master r
  LEFT JOIN reward_trans rt ON rt.entity_id = r.id
  WHERE r.merchant_id = v_merchant_id
    AND r.active_status = true
    AND r.visibility IN ('user', 'user_only')
    AND (r.redeem_window_end IS NULL OR now() <= r.redeem_window_end)
    AND (
      p_persona_id IS NULL
      OR r.allowed_persona IS NULL
      OR r.allowed_persona = '{}'
      OR p_persona_id = ANY(r.allowed_persona)
    );

  SELECT COUNT(*)::INT INTO v_total_count
  FROM reward_master r
  WHERE r.merchant_id = v_merchant_id
    AND r.active_status = true
    AND r.visibility IN ('user', 'user_only')
    AND (r.redeem_window_end IS NULL OR now() <= r.redeem_window_end)
    AND (
      p_persona_id IS NULL
      OR r.allowed_persona IS NULL
      OR r.allowed_persona = '{}'
      OR p_persona_id = ANY(r.allowed_persona)
    );

  SELECT COALESCE(
    jsonb_object_agg(
      rg.id::text,
      jsonb_build_object(
        'id',          rg.id,
        'name',        rg.name,
        'is_featured', rg.is_featured,
        'limits',      COALESCE(gl.limits_arr, '[]'::jsonb)
      )
    ),
    '{}'::jsonb
  ) INTO v_groups
  FROM reward_group rg
  LEFT JOIN LATERAL (
    SELECT jsonb_agg(
      jsonb_build_object(
        'metric',    tl.metric::text,
        'count',     tl.count,
        'scope',     tl.scope::text,
        'time_unit', tl.time_unit::text
      )
    ) AS limits_arr
    FROM transaction_limits tl
    WHERE tl.entity_id    = rg.id
      AND tl.entity_type  = 'reward_group'
      AND tl.merchant_id  = v_merchant_id
      AND tl.active_status = true
  ) gl ON true
  WHERE rg.merchant_id = v_merchant_id
    AND rg.is_active   = true
    AND EXISTS (
      SELECT 1 FROM reward_master rm
      WHERE rm.merchant_id  = v_merchant_id
        AND rm.active_status = true
        AND rm.visibility IN ('user', 'user_only')
        AND (rm.redeem_window_end IS NULL OR now() <= rm.redeem_window_end)
        AND rm.reward_group_ids @> ARRAY[rg.id]
        AND (
          p_persona_id IS NULL
          OR rm.allowed_persona IS NULL
          OR rm.allowed_persona = '{}'
          OR p_persona_id = ANY(rm.allowed_persona)
        )
    );

  SELECT json_agg(cat_obj ORDER BY sort_order, name) INTO v_categories
  FROM (
    SELECT
      0 as sort_order,
      json_build_object(
        'id', '',
        'name', CASE
          WHEN v_language = 'th' THEN 'ทั้งหมด'
          ELSE 'All'
        END,
        'reward_count', v_total_count
      ) as cat_obj,
      'All' as name
    UNION ALL
    SELECT
      1 as sort_order,
      json_build_object(
        'id', rc.id,
        'name', COALESCE(
          (SELECT translated_value FROM translations
           WHERE entity_id = rc.id AND entity_type = 'reward_category'
           AND field_name = 'name' AND language_code = v_language),
          rc.name
        ),
        'reward_count', COALESCE((
          SELECT COUNT(*)::INT FROM reward_master r
          WHERE r.category_id @> ARRAY[rc.id]
            AND r.merchant_id = v_merchant_id
            AND r.active_status = true
            AND r.visibility IN ('user', 'user_only')
            AND (r.redeem_window_end IS NULL OR now() <= r.redeem_window_end)
            AND (
              p_persona_id IS NULL
              OR r.allowed_persona IS NULL
              OR r.allowed_persona = '{}'
              OR p_persona_id = ANY(r.allowed_persona)
            )
        ), 0)
      ) as cat_obj,
      rc.name as name
    FROM reward_category rc
    WHERE rc.merchant_id = v_merchant_id
  ) all_cats;

  BEGIN
    PERFORM extensions.rewards_cache_set(
      v_cache_key,
      json_build_object(
        'data',             COALESCE(v_result, '[]'::json),
        'categories',       COALESCE(v_categories, '[]'::json),
        'groups',           v_groups,
        'cache_key',        v_cache_key,
        'default_language', v_language,
        'persona_filter',   p_persona_id
      )::TEXT,
      'EX',
      300
    );
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN json_build_object(
    'data',             COALESCE(v_result, '[]'::json),
    'categories',       COALESCE(v_categories, '[]'::json),
    'groups',           v_groups,
    'cache_hit',        false,
    'cache_key',        v_cache_key,
    'timestamp',        NOW(),
    'default_language', v_language,
    'persona_filter',   p_persona_id
  );
END;
$function$
