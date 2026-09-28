-- CR2: reward_group_member junction (canonical group membership) + retire reward_master.reward_group_ids

CREATE TABLE IF NOT EXISTS public.reward_group_member (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id uuid NOT NULL REFERENCES public.merchant_master(id) ON DELETE CASCADE,
    reward_group_id uuid NOT NULL REFERENCES public.reward_group(id) ON DELETE CASCADE,
    reward_id uuid NOT NULL REFERENCES public.reward_master(id) ON DELETE CASCADE,
    display_order integer NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT reward_group_member_reward_group_reward_unique UNIQUE (reward_group_id, reward_id),
    CONSTRAINT reward_group_member_reward_group_display_order_unique UNIQUE (reward_group_id, display_order) DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX IF NOT EXISTS idx_reward_group_member_merchant_reward
    ON public.reward_group_member (merchant_id, reward_id);

CREATE INDEX IF NOT EXISTS idx_reward_group_member_group_order
    ON public.reward_group_member (reward_group_id, display_order);

DROP TRIGGER IF EXISTS trg_reward_group_member_updated_at ON public.reward_group_member;
CREATE TRIGGER trg_reward_group_member_updated_at
    BEFORE UPDATE ON public.reward_group_member
    FOR EACH ROW
    EXECUTE FUNCTION public.trigger_set_updated_at();

ALTER TABLE public.reward_group_member ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "merchant_isolation" ON public.reward_group_member;
CREATE POLICY "merchant_isolation" ON public.reward_group_member
    FOR ALL
    USING (merchant_id = public.get_current_merchant_id())
    WITH CHECK (merchant_id = public.get_current_merchant_id());

COMMENT ON TABLE public.reward_group_member IS
    'Canonical reward membership in a reward group; display_order is per-group catalog ordering.';

-- Backfill from legacy reward_master.reward_group_ids (ordered by reward name within each group)
INSERT INTO public.reward_group_member (merchant_id, reward_group_id, reward_id, display_order)
SELECT
    src.merchant_id,
    src.reward_group_id,
    src.reward_id,
    src.display_order
FROM (
    SELECT
        rm.merchant_id,
        gid.reward_group_id,
        rm.id AS reward_id,
        ROW_NUMBER() OVER (PARTITION BY gid.reward_group_id ORDER BY rm.name, rm.id) AS display_order
    FROM public.reward_master rm
    CROSS JOIN LATERAL unnest(COALESCE(rm.reward_group_ids, ARRAY[]::uuid[])) AS gid(reward_group_id)
    INNER JOIN public.reward_group rg
        ON rg.id = gid.reward_group_id
       AND rg.merchant_id = rm.merchant_id
) src
ON CONFLICT (reward_group_id, reward_id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.fn_reward_group_ids_for_reward(p_reward_id uuid)
RETURNS uuid[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
    SELECT COALESCE(
        array_agg(rgm.reward_group_id ORDER BY rg.name, rgm.reward_group_id),
        ARRAY[]::uuid[]
    )
    FROM public.reward_group_member rgm
    INNER JOIN public.reward_group rg ON rg.id = rgm.reward_group_id
    WHERE rgm.reward_id = p_reward_id;
$$;

CREATE OR REPLACE FUNCTION public.fn_sync_reward_group_members_for_reward(
    p_merchant_id uuid,
    p_reward_id uuid,
    p_desired_group_ids uuid[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
    v_group_id uuid;
    v_next_order integer;
BEGIN
    DELETE FROM public.reward_group_member rgm
    WHERE rgm.merchant_id = p_merchant_id
      AND rgm.reward_id = p_reward_id
      AND NOT (rgm.reward_group_id = ANY(COALESCE(p_desired_group_ids, ARRAY[]::uuid[])));

    IF p_desired_group_ids IS NULL OR array_length(p_desired_group_ids, 1) IS NULL THEN
        RETURN;
    END IF;

    FOREACH v_group_id IN ARRAY p_desired_group_ids LOOP
        IF NOT EXISTS (
            SELECT 1 FROM public.reward_group rg
            WHERE rg.id = v_group_id AND rg.merchant_id = p_merchant_id
        ) THEN
            CONTINUE;
        END IF;

        IF EXISTS (
            SELECT 1 FROM public.reward_group_member rgm
            WHERE rgm.reward_group_id = v_group_id
              AND rgm.reward_id = p_reward_id
        ) THEN
            CONTINUE;
        END IF;

        SELECT COALESCE(MAX(rgm.display_order), 0) + 1
        INTO v_next_order
        FROM public.reward_group_member rgm
        WHERE rgm.reward_group_id = v_group_id;

        INSERT INTO public.reward_group_member (merchant_id, reward_group_id, reward_id, display_order)
        VALUES (p_merchant_id, v_group_id, p_reward_id, v_next_order);
    END LOOP;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.fn_sync_reward_group_members_for_group(
    p_merchant_id uuid,
    p_reward_group_id uuid,
    p_member_reward_ids uuid[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
BEGIN
    IF p_member_reward_ids IS NULL THEN
        RETURN;
    END IF;

    DELETE FROM public.reward_group_member rgm
    WHERE rgm.merchant_id = p_merchant_id
      AND rgm.reward_group_id = p_reward_group_id
      AND (
        array_length(p_member_reward_ids, 1) IS NULL
        OR NOT (rgm.reward_id = ANY(p_member_reward_ids))
      );

    IF array_length(p_member_reward_ids, 1) IS NULL THEN
        RETURN;
    END IF;

    INSERT INTO public.reward_group_member (merchant_id, reward_group_id, reward_id, display_order)
    SELECT
        p_merchant_id,
        p_reward_group_id,
        wanted.reward_id,
        wanted.display_order
    FROM (
        SELECT
            rid AS reward_id,
            ord::integer AS display_order
        FROM unnest(p_member_reward_ids) WITH ORDINALITY AS t(rid, ord)
        INNER JOIN public.reward_master rm
            ON rm.id = rid
           AND rm.merchant_id = p_merchant_id
    ) wanted
    ON CONFLICT (reward_group_id, reward_id)
    DO UPDATE SET
        display_order = EXCLUDED.display_order,
        updated_at = now();
END;
$fn$;



-- api_get_my_reward_group_usage
CREATE OR REPLACE FUNCTION public.api_get_my_reward_group_usage()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_merchant_id        UUID;
  v_user_id            UUID;
  v_rows               JSONB := '[]'::jsonb;

  -- per-group loop
  v_group              RECORD;
  v_sibling_ids        UUID[];
  v_redeemed_ids       UUID[];
  v_limits_arr         JSONB;

  -- per-limit inner loop
  v_limit              RECORD;
  v_limit_window_start TIMESTAMPTZ;
  v_current_usage      NUMERIC;
  v_limit_rows         JSONB;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RAISE EXCEPTION 'No merchant context found';
  END IF;

  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'No authenticated user found';
  END IF;

  -- Iterate every active reward group that has at least one distinct_reward limit
  FOR v_group IN
    SELECT DISTINCT
      rg.id          AS group_id,
      rg.name        AS group_name,
      rg.is_featured AS is_featured
    FROM reward_group rg
    JOIN transaction_limits tl
      ON tl.entity_id    = rg.id
     AND tl.entity_type  = 'reward_group'
     AND tl.merchant_id  = v_merchant_id
     AND tl.metric       = 'distinct_reward'
     AND tl.scope        = 'user'
     AND tl.active_status = true
    WHERE rg.merchant_id = v_merchant_id
      AND rg.is_active   = true
  LOOP
    -- All reward IDs that belong to this group
    SELECT ARRAY_AGG(rgm.reward_id) INTO v_sibling_ids
    FROM public.reward_group_member rgm
    WHERE rgm.merchant_id = v_merchant_id
      AND rgm.reward_group_id = v_group.group_id;

    IF v_sibling_ids IS NULL OR array_length(v_sibling_ids, 1) IS NULL THEN
      v_redeemed_ids := ARRAY[]::UUID[];
    ELSE
      -- Collect distinct reward IDs the user has redeemed across all limits' windows.
      -- We use all_time as the widest window here; per-limit current_usage below uses each limit's own window.
      SELECT ARRAY_AGG(DISTINCT reward_id) INTO v_redeemed_ids
      FROM reward_redemptions_ledger
      WHERE user_id         = v_user_id
        AND reward_id       = ANY(v_sibling_ids)
        AND redeemed_status = true
        AND (cancelled IS NOT TRUE)
        AND (source_type IS NULL OR source_type NOT IN ('package_assignment', 'persona_entitlement'));
    END IF;

    -- Build per-limit usage rows for this group
    v_limit_rows := '[]'::jsonb;

    FOR v_limit IN
      SELECT
        tl.id            AS limit_id,
        tl.count         AS limit_count,
        tl.time_unit,
        tl.window_start  AS limit_window_start,
        tl.window_end    AS limit_window_end,
        tl.metric
      FROM transaction_limits tl
      WHERE tl.entity_id    = v_group.group_id
        AND tl.entity_type  = 'reward_group'
        AND tl.merchant_id  = v_merchant_id
        AND tl.metric       = 'distinct_reward'
        AND tl.scope        = 'user'
        AND tl.active_status = true
        AND (tl.window_start IS NULL OR CURRENT_TIMESTAMP >= tl.window_start)
        AND (tl.window_end   IS NULL OR CURRENT_TIMESTAMP <= tl.window_end)
    LOOP
      -- Rolling window floor (same logic as fn_check_reward_group_limits)
      v_limit_window_start := CASE v_limit.time_unit
        WHEN 'day'      THEN date_trunc('day',   CURRENT_TIMESTAMP)
        WHEN 'week'     THEN date_trunc('week',  CURRENT_TIMESTAMP)
        WHEN 'month'    THEN date_trunc('month', CURRENT_TIMESTAMP)
        WHEN 'year'     THEN date_trunc('year',  CURRENT_TIMESTAMP)
        WHEN 'all_time' THEN NULL
        ELSE NULL
      END;

      IF v_limit.limit_window_start IS NOT NULL AND v_limit_window_start IS NOT NULL THEN
        v_limit_window_start := GREATEST(v_limit_window_start, v_limit.limit_window_start);
      ELSIF v_limit.limit_window_start IS NOT NULL THEN
        v_limit_window_start := v_limit.limit_window_start;
      END IF;

      IF v_sibling_ids IS NULL OR array_length(v_sibling_ids, 1) IS NULL THEN
        v_current_usage := 0;
      ELSE
        SELECT COUNT(DISTINCT reward_id) INTO v_current_usage
        FROM reward_redemptions_ledger
        WHERE user_id         = v_user_id
          AND reward_id       = ANY(v_sibling_ids)
          AND redeemed_status = true
          AND (cancelled IS NOT TRUE)
          AND (source_type IS NULL OR source_type NOT IN ('package_assignment', 'persona_entitlement'))
          AND (v_limit_window_start IS NULL OR created_at >= v_limit_window_start);
      END IF;

      v_limit_rows := v_limit_rows || jsonb_build_array(
        jsonb_build_object(
          'metric',        v_limit.metric::text,
          'count',         v_limit.limit_count,
          'time_unit',     v_limit.time_unit::text,
          'current_usage', v_current_usage,
          'remaining',     GREATEST(v_limit.limit_count - v_current_usage, 0)
        )
      );
    END LOOP;

    v_rows := v_rows || jsonb_build_array(
      jsonb_build_object(
        'group_id',           v_group.group_id,
        'group_name',         v_group.group_name,
        'is_featured',        v_group.is_featured,
        'limits',             v_limit_rows,
        'redeemed_reward_ids', COALESCE(v_redeemed_ids, ARRAY[]::UUID[])
      )
    );
  END LOOP;

  RETURN v_rows;
END;
$function$;

-- api_get_rewards_full_cached
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
      'reward_group_ids', public.fn_reward_group_ids_for_reward(r.id)
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
        'limits',      COALESCE(gl.limits_arr, '[]'::jsonb),
        'reward_ids',  COALESCE(gm.reward_ids, ARRAY[]::uuid[])
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
  LEFT JOIN LATERAL (
    SELECT array_agg(rgm.reward_id ORDER BY rgm.display_order) AS reward_ids
    FROM public.reward_group_member rgm
    INNER JOIN public.reward_master rm ON rm.id = rgm.reward_id
    WHERE rgm.reward_group_id = rg.id
      AND rgm.merchant_id = v_merchant_id
      AND rm.active_status = true
      AND rm.visibility IN ('user', 'user_only')
      AND (rm.redeem_window_end IS NULL OR now() <= rm.redeem_window_end)
      AND (
        p_persona_id IS NULL
        OR rm.allowed_persona IS NULL
        OR rm.allowed_persona = '{}'
        OR p_persona_id = ANY(rm.allowed_persona)
      )
  ) gm ON true
  WHERE rg.merchant_id = v_merchant_id
    AND rg.is_active   = true
    AND gm.reward_ids IS NOT NULL
    AND array_length(gm.reward_ids, 1) > 0;

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
$function$;

-- bff_delete_reward_group
CREATE OR REPLACE FUNCTION public.bff_delete_reward_group(p_group_id uuid, p_language text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_lang text;
    v_merchant_id UUID;
    v_group_name TEXT;
    v_rewards_updated INT;
BEGIN
    v_lang := fn_normalize_ui_language(p_language);
    v_merchant_id := get_current_merchant_id();
    IF v_merchant_id IS NULL THEN
        RETURN fn_response_error(
          fn_admin_envelope_message('no_merchant_title', v_lang),
          'No merchant context found',
          'NO_MERCHANT_CONTEXT'
        );
    END IF;

    SELECT name INTO v_group_name
    FROM reward_group
    WHERE id = p_group_id AND merchant_id = v_merchant_id;

    IF v_group_name IS NULL THEN
        RETURN fn_response_error(
          fn_admin_envelope_message('not_found_title', v_lang),
          'Reward group not found or access denied',
          'NOT_FOUND'
        );
    END IF;

    DELETE FROM public.reward_group_member
    WHERE merchant_id = v_merchant_id
      AND reward_group_id = p_group_id;
    GET DIAGNOSTICS v_rewards_updated = ROW_COUNT;

    DELETE FROM transaction_limits
    WHERE entity_id = p_group_id
      AND entity_type = 'reward_group'
      AND merchant_id = v_merchant_id;

    DELETE FROM reward_group
    WHERE id = p_group_id AND merchant_id = v_merchant_id;

    RETURN jsonb_build_object(
        'success', true,
        'code', 'DELETED',
        'title', fn_admin_envelope_message('reward_group_deleted_title', v_lang),
        'description', format('Reward group "%s" deleted. %s rewards updated.', v_group_name, v_rewards_updated),
        'rewards_updated', v_rewards_updated
    );

EXCEPTION WHEN OTHERS THEN
    RETURN fn_response_error(
      fn_admin_envelope_message('error_title', v_lang),
      SQLERRM,
      'ERROR'
    );
END;
$function$;

-- bff_get_frontline_reward_catalog
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
        'reward_group_ids', to_jsonb(public.fn_reward_group_ids_for_reward(r.id))
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
$function$;

-- bff_get_reward_details
CREATE OR REPLACE FUNCTION public.bff_get_reward_details(p_mode text DEFAULT 'edit'::text, p_reward_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_merchant_id UUID;
    v_reward RECORD;
    v_reward_group_ids uuid[];
    v_points_conditions JSONB;
    v_transaction_limits JSONB;
    v_reward_groups JSONB;
BEGIN
    v_merchant_id := get_current_merchant_id();

    IF v_merchant_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'No merchant context found');
    END IF;

    IF p_mode = 'new' THEN
        RETURN jsonb_build_object(
            'mode', 'new',
            'id', NULL,
            'name', NULL,
            'visibility', NULL,
            'description_headline', NULL,
            'description_body', NULL,
            'description_tc', NULL,
            'description_slip', NULL,
            'physical_draw_name', NULL,
            'physical_draw_description', NULL,
            'image', NULL,
            'category_id', NULL,
            'stock_control', false,
            'assign_promocode', false,
            'fulfillment_method', NULL,
            'redeem_window_start', NULL,
            'redeem_window_end', NULL,
            'use_expire_mode', NULL,
            'use_expire_date', NULL,
            'use_expire_ttl', NULL,
            'allowed_tier', '[]'::jsonb,
            'allowed_persona', '[]'::jsonb,
            'allowed_tags', '[]'::jsonb,
            'allowed_birthmonth', '[]'::jsonb,
            'fallback_points', NULL,
            'require_points_match', false,
            'ranking', NULL,
            'online_store', NULL,
            'external_id_shopify', NULL,
            'merchant_id', v_merchant_id,
            'created_at', NULL,
            'points_conditions', '[]'::jsonb,
            'transaction_limits', '[]'::jsonb,
            'reward_group_ids', NULL,
            'reward_groups', '[]'::jsonb,
            'variant_config', NULL
        );
    END IF;

    IF p_reward_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'reward_id is required for edit mode');
    END IF;

    SELECT * INTO v_reward
    FROM reward_master
    WHERE id = p_reward_id AND merchant_id = v_merchant_id;

    IF v_reward.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Reward not found or access denied');
    END IF;

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'id', pc.id,
                'tier_id', pc.tier_id,
                'user_type', pc.user_type,
                'persona_id', pc.persona_id,
                'tag_ids', pc.tag_ids,
                'points_required', pc.points_required,
                'priority', pc.priority,
                'condition_name', pc.condition_name,
                'description', pc.description,
                'active_status', pc.active_status,
                'created_at', pc.created_at
            ) ORDER BY pc.priority DESC, pc.created_at
        ),
        '[]'::jsonb
    ) INTO v_points_conditions
    FROM reward_points_conditions pc
    WHERE pc.reward_id = p_reward_id AND pc.merchant_id = v_merchant_id;

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'id', tl.id,
                'scope', tl.scope,
                'count', tl.count,
                'time_unit', tl.time_unit,
                'window_start', tl.window_start,
                'window_end', tl.window_end,
                'active_status', tl.active_status,
                'created_at', tl.created_at
            ) ORDER BY tl.created_at
        ),
        '[]'::jsonb
    ) INTO v_transaction_limits
    FROM transaction_limits tl
    WHERE tl.entity_id = p_reward_id
      AND tl.entity_type = 'reward'
      AND tl.merchant_id = v_merchant_id;

    v_reward_group_ids := public.fn_reward_group_ids_for_reward(p_reward_id);

    IF v_reward_group_ids IS NOT NULL AND array_length(v_reward_group_ids, 1) > 0 THEN
        SELECT COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'id', rg.id,
                    'name', rg.name,
                    'group_code', rg.group_code,
                    'is_active', rg.is_active
                ) ORDER BY rg.name
            ),
            '[]'::jsonb
        ) INTO v_reward_groups
        FROM reward_group rg
        WHERE rg.id = ANY(v_reward_group_ids)
          AND rg.merchant_id = v_merchant_id;
    ELSE
        v_reward_groups := '[]'::jsonb;
    END IF;

    RETURN jsonb_build_object(
        'mode', 'edit',
        'id', v_reward.id,
        'name', v_reward.name,
        'visibility', v_reward.visibility,
        'description_headline', v_reward.description_headline,
        'description_body', v_reward.description_body,
        'description_tc', v_reward.description_tc,
        'description_slip', v_reward.description_slip,
        'physical_draw_name', v_reward.physical_draw_name,
        'physical_draw_description', v_reward.physical_draw_description,
        'image', v_reward.image,
        'category_id', v_reward.category_id,
        'stock_control', v_reward.stock_control,
        'assign_promocode', v_reward.assign_promocode,
        'fulfillment_method', v_reward.fulfillment_method,
        'redeem_window_start', v_reward.redeem_window_start,
        'redeem_window_end', v_reward.redeem_window_end,
        'use_expire_mode', v_reward.use_expire_mode,
        'use_expire_date', v_reward.use_expire_date,
        'use_expire_ttl', v_reward.use_expire_ttl,
        'allowed_tier', v_reward.allowed_tier,
        'allowed_persona', v_reward.allowed_persona,
        'allowed_tags', v_reward.allowed_tags,
        'allowed_birthmonth', v_reward.allowed_birthmonth,
        'fallback_points', v_reward.fallback_points,
        'require_points_match', v_reward.require_points_match,
        'ranking', v_reward.ranking,
        'online_store', v_reward.online_store,
        'external_id_shopify', v_reward.external_id_shopify,
        'merchant_id', v_reward.merchant_id,
        'created_at', v_reward.created_at,
        'points_conditions', v_points_conditions,
        'transaction_limits', v_transaction_limits,
        'reward_group_ids', v_reward_group_ids,
        'reward_groups', v_reward_groups,
        'variant_config', v_reward.variant_config
    );
END;
$function$;

-- bff_get_reward_group_details
CREATE OR REPLACE FUNCTION public.bff_get_reward_group_details(p_group_id uuid DEFAULT NULL::uuid, p_mode text DEFAULT 'new'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_merchant_id UUID;
    v_group RECORD;
    v_limits JSONB;
    v_member_rewards JSONB;
BEGIN
    v_merchant_id := get_current_merchant_id();
    IF v_merchant_id IS NULL THEN
        RETURN fn_response_error('Error', 'No merchant context found', 'NO_MERCHANT_CONTEXT');
    END IF;

    IF p_mode = 'new' THEN
        RETURN jsonb_build_object(
            'success', true,
            'data', jsonb_build_object(
                'mode', 'new',
                'id', NULL,
                'merchant_id', v_merchant_id,
                'group_code', NULL,
                'name', NULL,
                'description', NULL,
                'is_active', true,
                'is_featured', false,
                'transaction_limits', '[]'::jsonb,
                'member_rewards', '[]'::jsonb
            )
        );
    END IF;

    IF p_group_id IS NULL THEN
        RETURN fn_response_error('Error', 'group_id is required for edit mode', 'MISSING_PARAM');
    END IF;

    SELECT rg.id, rg.merchant_id, rg.group_code, rg.name, rg.description,
           rg.is_active, rg.is_featured, rg.created_at, rg.updated_at
    INTO v_group
    FROM reward_group rg
    WHERE rg.id = p_group_id AND rg.merchant_id = v_merchant_id;

    IF v_group IS NULL THEN
        RETURN fn_response_error('Not Found', 'Reward group not found or access denied', 'NOT_FOUND');
    END IF;

    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', tl.id,
            'metric', tl.metric::text,
            'scope', tl.scope::text,
            'count', tl.count,
            'time_unit', tl.time_unit::text,
            'window_start', tl.window_start,
            'window_end', tl.window_end,
            'active_status', tl.active_status
        )
    ), '[]'::jsonb)
    INTO v_limits
    FROM transaction_limits tl
    WHERE tl.entity_id = p_group_id
      AND tl.entity_type = 'reward_group'
      AND tl.merchant_id = v_merchant_id;

    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', rm.id,
            'name', rm.name,
            'visibility', rm.visibility::text,
            'active_status', rm.active_status,
            'is_featured', rm.is_featured,
            'category_id', rm.category_id
        ) ORDER BY rgm.display_order
    ), '[]'::jsonb)
    INTO v_member_rewards
    FROM public.reward_group_member rgm
    INNER JOIN reward_master rm ON rm.id = rgm.reward_id
    WHERE rgm.merchant_id = v_merchant_id
      AND rgm.reward_group_id = p_group_id;

    RETURN jsonb_build_object(
        'success', true,
        'data', jsonb_build_object(
            'mode', 'edit',
            'id', v_group.id,
            'merchant_id', v_group.merchant_id,
            'group_code', v_group.group_code,
            'name', v_group.name,
            'description', v_group.description,
            'is_active', v_group.is_active,
            'is_featured', v_group.is_featured,
            'created_at', v_group.created_at,
            'updated_at', v_group.updated_at,
            'transaction_limits', v_limits,
            'member_rewards', v_member_rewards
        )
    );

EXCEPTION WHEN OTHERS THEN
    RETURN fn_response_error('Error', SQLERRM, 'ERROR');
END;
$function$;

-- bff_list_reward_groups
CREATE OR REPLACE FUNCTION public.bff_list_reward_groups()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_merchant_id UUID;
    v_groups JSONB;
BEGIN
    v_merchant_id := get_current_merchant_id();
    IF v_merchant_id IS NULL THEN
        RETURN fn_response_error('Error', 'No merchant context found', 'NO_MERCHANT_CONTEXT');
    END IF;

    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', rg.id,
            'group_code', rg.group_code,
            'name', rg.name,
            'description', rg.description,
            'is_active', rg.is_active,
            'is_featured', rg.is_featured,
            'created_at', rg.created_at,
            'updated_at', rg.updated_at,
            'member_count', COALESCE(mc.cnt, 0),
            'limits', COALESCE(lm.limits_arr, '[]'::jsonb)
        ) ORDER BY rg.created_at DESC
    ), '[]'::jsonb)
    INTO v_groups
    FROM reward_group rg
    LEFT JOIN LATERAL (
        SELECT COUNT(*) as cnt
        FROM public.reward_group_member rgm
        WHERE rgm.merchant_id = v_merchant_id
          AND rgm.reward_group_id = rg.id
    ) mc ON true
    LEFT JOIN LATERAL (
        SELECT jsonb_agg(
            jsonb_build_object(
                'metric', tl.metric::text,
                'scope', tl.scope::text,
                'count', tl.count,
                'time_unit', tl.time_unit::text
            )
        ) as limits_arr
        FROM transaction_limits tl
        WHERE tl.entity_id = rg.id
          AND tl.entity_type = 'reward_group'
          AND tl.merchant_id = v_merchant_id
          AND tl.active_status = true
    ) lm ON true
    WHERE rg.merchant_id = v_merchant_id;

    RETURN jsonb_build_object(
        'success', true,
        'data', v_groups
    );

EXCEPTION WHEN OTHERS THEN
    RETURN fn_response_error('Error', SQLERRM, 'ERROR');
END;
$function$;

-- fn_check_reward_group_limits
CREATE OR REPLACE FUNCTION public.fn_check_reward_group_limits(p_user_id uuid, p_reward_id uuid, p_quantity integer, p_merchant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_group_ids UUID[];
    v_group_id  UUID;
    v_group_name TEXT;
    v_limit RECORD;
    v_limit_window_start TIMESTAMPTZ;
    v_limit_count NUMERIC;
    v_sibling_reward_ids UUID[];
    v_will_add_distinct INT;
BEGIN
    v_group_ids := public.fn_reward_group_ids_for_reward(p_reward_id);

    IF v_group_ids IS NULL OR array_length(v_group_ids, 1) IS NULL THEN
        RETURN jsonb_build_object('allowed', true);
    END IF;

    FOREACH v_group_id IN ARRAY v_group_ids LOOP
        SELECT rg.name INTO v_group_name
        FROM reward_group rg
        WHERE rg.id = v_group_id
          AND rg.merchant_id = p_merchant_id
          AND rg.is_active = true;

        IF v_group_name IS NULL THEN CONTINUE; END IF;

        SELECT ARRAY_AGG(rgm.reward_id) INTO v_sibling_reward_ids
        FROM public.reward_group_member rgm
        WHERE rgm.merchant_id = p_merchant_id
          AND rgm.reward_group_id = v_group_id;

        FOR v_limit IN
            SELECT * FROM transaction_limits
            WHERE entity_id = v_group_id
              AND entity_type = 'reward_group'
              AND merchant_id = p_merchant_id
              AND active_status = true
        LOOP
            v_limit_window_start := CASE v_limit.time_unit
                WHEN 'day'      THEN date_trunc('day',   CURRENT_TIMESTAMP)
                WHEN 'week'     THEN date_trunc('week',  CURRENT_TIMESTAMP)
                WHEN 'month'    THEN date_trunc('month', CURRENT_TIMESTAMP)
                WHEN 'year'     THEN date_trunc('year',  CURRENT_TIMESTAMP)
                WHEN 'all_time' THEN NULL
                ELSE NULL
            END;

            IF v_limit.window_start IS NOT NULL AND CURRENT_TIMESTAMP < v_limit.window_start THEN CONTINUE; END IF;
            IF v_limit.window_end   IS NOT NULL AND CURRENT_TIMESTAMP > v_limit.window_end   THEN CONTINUE; END IF;
            IF v_limit.window_start IS NOT NULL AND v_limit_window_start IS NOT NULL THEN
                v_limit_window_start := GREATEST(v_limit_window_start, v_limit.window_start);
            ELSIF v_limit.window_start IS NOT NULL THEN
                v_limit_window_start := v_limit.window_start;
            END IF;

            IF v_limit.metric = 'distinct_reward' THEN
                -- Count how many distinct reward_ids the user has redeemed in this group
                -- within the window. Only scope='user' reaches here (CHECK constraint).
                SELECT COUNT(DISTINCT reward_id) INTO v_limit_count
                FROM reward_redemptions_ledger
                WHERE user_id = p_user_id
                  AND reward_id = ANY(v_sibling_reward_ids)
                  AND redeemed_status = true
                  AND (cancelled IS NOT TRUE)
                  AND (source_type IS NULL OR source_type NOT IN ('package_assignment','persona_entitlement'))
                  AND (v_limit_window_start IS NULL OR created_at >= v_limit_window_start);

                -- Only increment the distinct count if this reward is NEW to the user within
                -- the window. Re-redeeming a reward they already hold does not grow distinct.
                v_will_add_distinct := CASE
                    WHEN EXISTS (
                        SELECT 1 FROM reward_redemptions_ledger
                        WHERE user_id = p_user_id
                          AND reward_id = p_reward_id
                          AND redeemed_status = true
                          AND (cancelled IS NOT TRUE)
                          AND (source_type IS NULL OR source_type NOT IN ('package_assignment','persona_entitlement'))
                          AND (v_limit_window_start IS NULL OR created_at >= v_limit_window_start)
                    ) THEN 0 ELSE 1
                END;

                IF v_limit_count + v_will_add_distinct > v_limit.count THEN
                    RETURN jsonb_build_object(
                        'allowed', false,
                        'group_id', v_group_id,
                        'group_name', v_group_name,
                        'metric', 'distinct_reward',
                        'limit_scope', v_limit.scope::text,
                        'limit_count', v_limit.count,
                        'time_unit', v_limit.time_unit::text,
                        'current_count', v_limit_count,
                        'remaining', GREATEST(v_limit.count - v_limit_count, 0),
                        'requested', v_will_add_distinct,
                        'title', 'Reward type limit reached',
                        'description', format(
                            'You can pick up to %s distinct reward(s) in %s. You have already picked %s.',
                            v_limit.count, v_group_name, v_limit_count)
                    );
                END IF;

            ELSE
                -- metric = 'quantity' (existing behavior)
                IF v_limit.scope = 'user' THEN
                    SELECT COALESCE(SUM(qty), 0) INTO v_limit_count
                    FROM reward_redemptions_ledger
                    WHERE user_id = p_user_id
                      AND reward_id = ANY(v_sibling_reward_ids)
                      AND redeemed_status = true
                      AND (cancelled IS NOT TRUE)
                      AND (source_type IS NULL OR source_type NOT IN ('package_assignment','persona_entitlement'))
                      AND (v_limit_window_start IS NULL OR created_at >= v_limit_window_start);
                ELSIF v_limit.scope = 'total' THEN
                    SELECT COALESCE(SUM(qty), 0) INTO v_limit_count
                    FROM reward_redemptions_ledger
                    WHERE reward_id = ANY(v_sibling_reward_ids)
                      AND merchant_id = p_merchant_id
                      AND redeemed_status = true
                      AND (cancelled IS NOT TRUE)
                      AND (v_limit_window_start IS NULL OR created_at >= v_limit_window_start);
                END IF;

                IF v_limit_count + p_quantity > v_limit.count THEN
                    RETURN jsonb_build_object(
                        'allowed', false,
                        'group_id', v_group_id,
                        'group_name', v_group_name,
                        'metric', 'quantity',
                        'limit_scope', v_limit.scope::text,
                        'limit_count', v_limit.count,
                        'time_unit', v_limit.time_unit::text,
                        'current_count', v_limit_count,
                        'remaining', GREATEST(v_limit.count - v_limit_count, 0),
                        'requested', p_quantity
                    );
                END IF;
            END IF;
        END LOOP;
    END LOOP;

    RETURN jsonb_build_object('allowed', true);
END;
$function$;

-- fn_reward_redemption_quote
CREATE OR REPLACE FUNCTION public.fn_reward_redemption_quote(p_user_id uuid, p_reward_id uuid, p_merchant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user public.user_accounts;
  v_reward public.reward_master;
  v_user_tag_ids uuid[];
  v_points_calc jsonb;
  v_points_per_unit numeric := 0;
  v_balance numeric := 0;
  v_hard_cap integer := 1000;
  v_max_selectable integer := 1000;
  v_can_redeem boolean := true;
  v_quantity_binding text := 'unlimited';
  v_blocking_reason text;
  v_redeem_limit jsonb;
  v_available jsonb;
  v_limit record;
  v_limit_window timestamptz;
  v_limit_count numeric;
  v_remaining numeric;
  v_pool_remaining numeric;
  v_pool_time_unit text;
  v_has_pool boolean := false;
  v_group_ids uuid[];
  v_group_id uuid;
  v_sibling_ids uuid[];
  v_group_check jsonb;
  v_promo_remaining integer;
  v_stock_remaining numeric;
  v_points_cap integer;
  v_tightest_user_remaining numeric;
  v_tightest_user_used numeric;
  v_tightest_user_cap numeric;
  v_tightest_user_time_unit text;
BEGIN
  IF p_user_id IS NULL OR p_reward_id IS NULL OR p_merchant_id IS NULL THEN
    RETURN jsonb_build_object(
      'max_selectable_quantity', 0,
      'can_redeem', false,
      'quantity_binding_reason', 'hard_cap',
      'blocking_reason', 'ineligible',
      'points_per_unit', 0,
      'qty_hard_cap', v_hard_cap
    );
  END IF;

  SELECT * INTO v_user
  FROM public.user_accounts
  WHERE id = p_user_id AND merchant_id = p_merchant_id;

  SELECT * INTO v_reward
  FROM public.reward_master
  WHERE id = p_reward_id AND merchant_id = p_merchant_id;

  IF v_user.id IS NULL OR v_reward.id IS NULL THEN
    RETURN jsonb_build_object(
      'max_selectable_quantity', 0,
      'can_redeem', false,
      'quantity_binding_reason', 'hard_cap',
      'blocking_reason', 'ineligible',
      'points_per_unit', 0,
      'qty_hard_cap', v_hard_cap
    );
  END IF;

  SELECT ARRAY_AGG(tag_id) INTO v_user_tag_ids FROM public.user_tags WHERE user_id = p_user_id;

  IF public.fn_merchant_shopify_feature_enabled(p_merchant_id, 'reward', 'reward.tier_reward_eligibility')
     AND v_reward.allowed_tier IS NOT NULL AND array_length(v_reward.allowed_tier, 1) > 0 THEN
    IF v_user.tier_id IS NULL OR NOT (v_user.tier_id = ANY(v_reward.allowed_tier)) THEN
      v_can_redeem := false;
      v_blocking_reason := 'ineligible';
    END IF;
  END IF;

  IF v_blocking_reason IS NULL AND v_reward.allowed_persona IS NOT NULL AND array_length(v_reward.allowed_persona, 1) > 0 THEN
    IF v_user.persona_id IS NULL OR NOT (v_user.persona_id = ANY(v_reward.allowed_persona)) THEN
      v_can_redeem := false;
      v_blocking_reason := 'ineligible';
    END IF;
  END IF;

  IF v_blocking_reason IS NULL AND v_reward.allowed_tags IS NOT NULL AND array_length(v_reward.allowed_tags, 1) > 0 THEN
    IF v_user_tag_ids IS NULL OR NOT (v_reward.allowed_tags && v_user_tag_ids) THEN
      v_can_redeem := false;
      v_blocking_reason := 'ineligible';
    END IF;
  END IF;

  IF v_blocking_reason IS NULL AND v_reward.allowed_birthmonth IS NOT NULL AND array_length(v_reward.allowed_birthmonth, 1) > 0 THEN
    IF EXTRACT(MONTH FROM v_user.birth_date)::INT::TEXT IS NULL
       OR NOT (EXTRACT(MONTH FROM v_user.birth_date)::INT::TEXT = ANY(v_reward.allowed_birthmonth)) THEN
      v_can_redeem := false;
      v_blocking_reason := 'ineligible';
    END IF;
  END IF;

  IF v_blocking_reason IS NULL AND v_reward.redeem_window_start IS NOT NULL AND CURRENT_TIMESTAMP < v_reward.redeem_window_start THEN
    v_can_redeem := false;
    v_blocking_reason := 'ineligible';
  END IF;

  IF v_blocking_reason IS NULL AND v_reward.redeem_window_end IS NOT NULL AND CURRENT_TIMESTAMP > v_reward.redeem_window_end THEN
    v_can_redeem := false;
    v_blocking_reason := 'ineligible';
  END IF;

  v_points_calc := public.calculate_redemption_points_fast(
    v_user.tier_id, v_user.user_type, v_user.persona_id, v_user_tag_ids,
    p_reward_id, v_reward.fallback_points, v_reward.require_points_match
  );

  IF NOT COALESCE((v_points_calc->>'success')::boolean, false) THEN
    v_can_redeem := false;
    v_blocking_reason := COALESCE(v_blocking_reason, 'ineligible');
  ELSE
    v_points_per_unit := COALESCE((v_points_calc->>'points_required')::numeric, 0);
    IF COALESCE(v_reward.require_points_match, false)
       AND COALESCE(v_points_calc->>'match_type', '') = 'blocked' THEN
      v_can_redeem := false;
      v_blocking_reason := COALESCE(v_blocking_reason, 'points_match_blocked');
    END IF;
  END IF;

  IF v_blocking_reason IN ('ineligible', 'points_match_blocked') THEN
    RETURN jsonb_build_object(
      'max_selectable_quantity', 0,
      'can_redeem', false,
      'quantity_binding_reason', 'hard_cap',
      'blocking_reason', v_blocking_reason,
      'points_per_unit', COALESCE(v_points_per_unit, 0),
      'qty_hard_cap', v_hard_cap
    );
  END IF;

  SELECT COALESCE(points_balance, 0) INTO v_balance
  FROM public.user_wallet
  WHERE user_id = p_user_id AND merchant_id = p_merchant_id;
  v_balance := COALESCE(v_balance, 0);

  v_tightest_user_remaining := NULL;

  FOR v_limit IN
    SELECT * FROM public.transaction_limits
    WHERE entity_id = p_reward_id
      AND entity_type = 'reward'
      AND merchant_id = p_merchant_id
      AND active_status = true
      AND metric = 'quantity'
      AND scope = 'user'
  LOOP
    v_limit_window := public.fn_transaction_limit_effective_window(v_limit.time_unit::text, v_limit.window_start, v_limit.window_end);
    IF v_limit_window IS NULL AND v_limit.window_start IS NOT NULL AND CURRENT_TIMESTAMP < v_limit.window_start THEN
      CONTINUE;
    END IF;
    IF v_limit.window_end IS NOT NULL AND CURRENT_TIMESTAMP > v_limit.window_end THEN
      CONTINUE;
    END IF;

    SELECT COALESCE(SUM(qty), 0) INTO v_limit_count
    FROM public.reward_redemptions_ledger
    WHERE user_id = p_user_id
      AND reward_id = p_reward_id
      AND redeemed_status = true
      AND (cancelled IS NOT TRUE)
      AND (source_type IS NULL OR source_type NOT IN ('package_assignment', 'persona_entitlement'))
      AND (v_limit_window IS NULL OR created_at >= v_limit_window);

    v_remaining := GREATEST(v_limit.count - v_limit_count, 0);
    IF v_tightest_user_remaining IS NULL OR v_remaining < v_tightest_user_remaining THEN
      v_tightest_user_remaining := v_remaining;
      v_tightest_user_used := v_limit_count;
      v_tightest_user_cap := v_limit.count;
      v_tightest_user_time_unit := v_limit.time_unit::text;
    END IF;
    v_max_selectable := LEAST(v_max_selectable, v_remaining::integer);
    v_quantity_binding := 'reward_quota';
  END LOOP;

  IF v_tightest_user_remaining IS NOT NULL THEN
    v_redeem_limit := jsonb_build_object(
      'used', v_tightest_user_used,
      'cap', v_tightest_user_cap,
      'time_unit', v_tightest_user_time_unit
    );
  END IF;

  v_pool_remaining := NULL;

  FOR v_limit IN
    SELECT * FROM public.transaction_limits
    WHERE entity_id = p_reward_id
      AND entity_type = 'reward'
      AND merchant_id = p_merchant_id
      AND active_status = true
      AND metric = 'quantity'
      AND scope = 'total'
  LOOP
    v_limit_window := public.fn_transaction_limit_effective_window(v_limit.time_unit::text, v_limit.window_start, v_limit.window_end);
    IF v_limit_window IS NULL AND v_limit.window_start IS NOT NULL AND CURRENT_TIMESTAMP < v_limit.window_start THEN
      CONTINUE;
    END IF;
    IF v_limit.window_end IS NOT NULL AND CURRENT_TIMESTAMP > v_limit.window_end THEN
      CONTINUE;
    END IF;

    SELECT COALESCE(SUM(qty), 0) INTO v_limit_count
    FROM public.reward_redemptions_ledger
    WHERE reward_id = p_reward_id
      AND merchant_id = p_merchant_id
      AND redeemed_status = true
      AND (cancelled IS NOT TRUE)
      AND (v_limit_window IS NULL OR created_at >= v_limit_window);

    v_remaining := GREATEST(v_limit.count - v_limit_count, 0);
    v_has_pool := true;
    IF v_pool_remaining IS NULL OR v_remaining < v_pool_remaining THEN
      v_pool_remaining := v_remaining;
      v_pool_time_unit := v_limit.time_unit::text;
    END IF;
    v_max_selectable := LEAST(v_max_selectable, v_remaining::integer);
    IF v_quantity_binding = 'unlimited' THEN
      v_quantity_binding := 'group_quantity';
    END IF;
  END LOOP;

  v_group_ids := public.fn_reward_group_ids_for_reward(p_reward_id);

  IF v_group_ids IS NOT NULL THEN
    FOREACH v_group_id IN ARRAY v_group_ids LOOP
      IF NOT EXISTS (
        SELECT 1 FROM public.reward_group rg
        WHERE rg.id = v_group_id AND rg.merchant_id = p_merchant_id AND rg.is_active = true
      ) THEN
        CONTINUE;
      END IF;

      SELECT ARRAY_AGG(rgm.reward_id) INTO v_sibling_ids
        FROM public.reward_group_member rgm
        WHERE rgm.merchant_id = p_merchant_id
          AND rgm.reward_group_id = v_group_id;

      FOR v_limit IN
        SELECT * FROM public.transaction_limits
        WHERE entity_id = v_group_id
          AND entity_type = 'reward_group'
          AND merchant_id = p_merchant_id
          AND active_status = true
          AND metric = 'quantity'
      LOOP
        v_limit_window := public.fn_transaction_limit_effective_window(v_limit.time_unit::text, v_limit.window_start, v_limit.window_end);
        IF v_limit_window IS NULL AND v_limit.window_start IS NOT NULL AND CURRENT_TIMESTAMP < v_limit.window_start THEN
          CONTINUE;
        END IF;
        IF v_limit.window_end IS NOT NULL AND CURRENT_TIMESTAMP > v_limit.window_end THEN
          CONTINUE;
        END IF;

        IF v_limit.scope = 'user' THEN
          SELECT COALESCE(SUM(qty), 0) INTO v_limit_count
          FROM public.reward_redemptions_ledger
          WHERE user_id = p_user_id
            AND reward_id = ANY(v_sibling_ids)
            AND redeemed_status = true
            AND (cancelled IS NOT TRUE)
            AND (source_type IS NULL OR source_type NOT IN ('package_assignment', 'persona_entitlement'))
            AND (v_limit_window IS NULL OR created_at >= v_limit_window);
        ELSE
          SELECT COALESCE(SUM(qty), 0) INTO v_limit_count
          FROM public.reward_redemptions_ledger
          WHERE reward_id = ANY(v_sibling_ids)
            AND merchant_id = p_merchant_id
            AND redeemed_status = true
            AND (cancelled IS NOT TRUE)
            AND (v_limit_window IS NULL OR created_at >= v_limit_window);
        END IF;

        v_remaining := GREATEST(v_limit.count - v_limit_count, 0);

        IF v_limit.scope = 'user' THEN
          IF v_tightest_user_remaining IS NULL OR v_remaining < v_tightest_user_remaining THEN
            v_tightest_user_remaining := v_remaining;
            v_tightest_user_used := v_limit_count;
            v_tightest_user_cap := v_limit.count;
            v_tightest_user_time_unit := v_limit.time_unit::text;
          END IF;
          v_max_selectable := LEAST(v_max_selectable, v_remaining::integer);
          v_quantity_binding := 'reward_quota';
          IF v_redeem_limit IS NULL OR v_remaining < (v_redeem_limit->>'cap')::numeric - (v_redeem_limit->>'used')::numeric THEN
            v_redeem_limit := jsonb_build_object(
              'used', v_limit_count,
              'cap', v_limit.count,
              'time_unit', v_limit.time_unit::text
            );
          END IF;
        ELSE
          v_has_pool := true;
          IF v_pool_remaining IS NULL OR v_remaining < v_pool_remaining THEN
            v_pool_remaining := v_remaining;
            v_pool_time_unit := v_limit.time_unit::text;
          END IF;
          v_max_selectable := LEAST(v_max_selectable, v_remaining::integer);
          v_quantity_binding := 'group_quantity';
        END IF;
      END LOOP;
    END LOOP;
  END IF;

  IF v_reward.stock_control AND NOT v_reward.assign_promocode AND v_reward.stock_total IS NOT NULL THEN
    SELECT COALESCE(SUM(qty), 0) INTO v_limit_count
    FROM public.reward_redemptions_ledger
    WHERE reward_id = p_reward_id
      AND merchant_id = p_merchant_id
      AND redeemed_status = true
      AND (cancelled IS NOT TRUE);

    v_stock_remaining := GREATEST(v_reward.stock_total - v_limit_count, 0);
    v_has_pool := true;
    IF v_pool_remaining IS NULL OR v_stock_remaining < v_pool_remaining THEN
      v_pool_remaining := v_stock_remaining;
      v_pool_time_unit := NULL;
    END IF;
    v_max_selectable := LEAST(v_max_selectable, v_stock_remaining::integer);
    IF v_stock_remaining <= 0 THEN
      v_quantity_binding := 'sold_out';
    END IF;
  END IF;

  IF v_reward.assign_promocode THEN
    SELECT COUNT(*)::integer INTO v_promo_remaining
    FROM public.reward_promo_code
    WHERE reward_id = p_reward_id
      AND merchant_id = p_merchant_id
      AND redeemed_status = false;

    v_has_pool := true;
    IF v_pool_remaining IS NULL OR v_promo_remaining < v_pool_remaining THEN
      v_pool_remaining := v_promo_remaining;
      v_pool_time_unit := NULL;
    END IF;
    v_max_selectable := LEAST(v_max_selectable, v_promo_remaining);
    v_quantity_binding := CASE WHEN v_promo_remaining <= 0 THEN 'sold_out' ELSE 'promo_codes' END;
  END IF;

  IF v_points_per_unit > 0 THEN
    v_points_cap := FLOOR(v_balance / v_points_per_unit)::integer;
    v_max_selectable := LEAST(v_max_selectable, GREATEST(v_points_cap, 0));
    IF v_points_cap < v_max_selectable AND v_quantity_binding = 'unlimited' THEN
      v_quantity_binding := 'points';
    END IF;
    IF v_balance < v_points_per_unit THEN
      v_can_redeem := false;
      v_blocking_reason := COALESCE(v_blocking_reason, 'insufficient_points');
    END IF;
  END IF;

  v_max_selectable := LEAST(v_max_selectable, v_hard_cap);
  IF v_max_selectable < v_hard_cap AND v_quantity_binding = 'unlimited' THEN
    v_quantity_binding := 'hard_cap';
  END IF;

  IF v_max_selectable < 1 THEN
    v_can_redeem := false;
    v_blocking_reason := COALESCE(v_blocking_reason, 'sold_out');
  END IF;

  v_group_check := public.fn_check_reward_group_limits(p_user_id, p_reward_id, 1, p_merchant_id);
  IF NOT COALESCE((v_group_check->>'allowed')::boolean, true)
     AND COALESCE(v_group_check->>'metric', '') = 'distinct_reward' THEN
    v_can_redeem := false;
    v_blocking_reason := 'group_distinct';
  END IF;

  IF v_has_pool AND v_pool_remaining IS NOT NULL THEN
    v_available := jsonb_build_object(
      'qty', GREATEST(v_pool_remaining, 0),
      'time_unit', v_pool_time_unit
    );
    IF v_pool_remaining <= 0 THEN
      v_can_redeem := false;
      v_blocking_reason := COALESCE(v_blocking_reason, 'sold_out');
    END IF;
  END IF;

  IF v_redeem_limit IS NOT NULL AND v_tightest_user_remaining IS NOT NULL THEN
    v_redeem_limit := jsonb_build_object(
      'used', v_tightest_user_used,
      'cap', v_tightest_user_cap,
      'time_unit', v_tightest_user_time_unit
    );
  END IF;

  RETURN jsonb_build_object(
    'max_selectable_quantity', GREATEST(v_max_selectable, 0),
    'can_redeem', v_can_redeem,
    'quantity_binding_reason', v_quantity_binding,
    'blocking_reason', v_blocking_reason,
    'redeem_limit', v_redeem_limit,
    'available', v_available,
    'points_per_unit', COALESCE(v_points_per_unit, 0),
    'qty_hard_cap', v_hard_cap
  );
END;
$function$;

-- bff_upsert_reward_with_conditions_and_limits
CREATE OR REPLACE FUNCTION public.bff_upsert_reward_with_conditions_and_limits(p_reward_id uuid DEFAULT NULL::uuid, p_name text DEFAULT NULL::text, p_description_headline text DEFAULT NULL::text, p_description_body text DEFAULT NULL::text, p_description_tc text DEFAULT NULL::text, p_description_slip text DEFAULT NULL::text, p_image jsonb DEFAULT NULL::jsonb, p_category_id jsonb DEFAULT NULL::jsonb, p_visibility reward_visibility DEFAULT NULL::reward_visibility, p_redeem_window_start timestamp with time zone DEFAULT NULL::timestamp with time zone, p_redeem_window_end timestamp with time zone DEFAULT NULL::timestamp with time zone, p_stock_control boolean DEFAULT false, p_assign_promocode boolean DEFAULT false, p_use_expire_mode reward_expire_mode DEFAULT NULL::reward_expire_mode, p_use_expire_date timestamp with time zone DEFAULT NULL::timestamp with time zone, p_use_expire_ttl numeric DEFAULT NULL::numeric, p_fulfillment_method reward_fulfillment_method DEFAULT NULL::reward_fulfillment_method, p_allowed_tier jsonb DEFAULT NULL::jsonb, p_allowed_persona jsonb DEFAULT NULL::jsonb, p_allowed_tags jsonb DEFAULT NULL::jsonb, p_allowed_birthmonth jsonb DEFAULT NULL::jsonb, p_fallback_points numeric DEFAULT NULL::numeric, p_require_points_match boolean DEFAULT false, p_points_conditions jsonb DEFAULT NULL::jsonb, p_transaction_limits jsonb DEFAULT NULL::jsonb, p_external_id_shopify text DEFAULT NULL::text, p_online_store jsonb DEFAULT NULL::jsonb, p_reward_group_ids jsonb DEFAULT NULL::jsonb, p_shopify_discount_type text DEFAULT NULL::text, p_shopify_discount_label text DEFAULT NULL::text, p_variant_config jsonb DEFAULT NULL::jsonb, p_physical_draw_name text DEFAULT NULL::text, p_physical_draw_description text DEFAULT NULL::text, p_language text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_lang text;
    v_merchant_id UUID;
    v_reward_id UUID;
    v_reward_name TEXT;
    v_parent_created BOOLEAN := false;
    v_parent_updated BOOLEAN := false;
    v_conditions_created INT := 0;
    v_conditions_updated INT := 0;
    v_conditions_deleted INT := 0;
    v_conditions_skipped INT := 0;
    v_limits_created INT := 0;
    v_limits_updated INT := 0;
    v_limits_deleted INT := 0;
    v_limits_skipped INT := 0;
    v_condition_obj JSONB;
    v_condition_id UUID;
    v_tier_id UUID;
    v_persona_id UUID;
    v_limit_obj JSONB;
    v_limit_id UUID;
    v_limit_id_text TEXT;
    v_conditions_to_keep UUID[] := ARRAY[]::UUID[];
    v_limits_to_keep UUID[] := ARRAY[]::UUID[];
    v_tag_ids UUID[];
    v_user_type user_type;
    v_window_start TIMESTAMPTZ;
    v_window_end TIMESTAMPTZ;
    v_category_id UUID[];
    v_allowed_tier UUID[];
    v_allowed_persona UUID[];
    v_allowed_tags UUID[];
    v_allowed_birthmonth TEXT[];
    v_image TEXT[];
    v_online_store TEXT[];
    v_reward_group_ids UUID[];
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
    v_merchant_id := get_current_merchant_id();
    IF v_merchant_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'NO_MERCHANT_CONTEXT', 'title', fn_admin_envelope_message('error_title', v_lang), 'description', fn_admin_envelope_message('no_merchant_found_title', v_lang));
    END IF;
    
    v_reward_name := COALESCE(p_name, 'Untitled Reward');
    v_category_id := CASE WHEN p_category_id IS NULL OR jsonb_typeof(p_category_id) != 'array' OR jsonb_array_length(p_category_id) = 0 THEN NULL ELSE (SELECT ARRAY_AGG(value::text::uuid) FROM jsonb_array_elements_text(p_category_id)) END;
    v_allowed_tier := CASE WHEN p_allowed_tier IS NULL OR jsonb_typeof(p_allowed_tier) != 'array' OR jsonb_array_length(p_allowed_tier) = 0 THEN NULL ELSE (SELECT ARRAY_AGG(value::text::uuid) FROM jsonb_array_elements_text(p_allowed_tier)) END;
    v_allowed_persona := CASE WHEN p_allowed_persona IS NULL OR jsonb_typeof(p_allowed_persona) != 'array' OR jsonb_array_length(p_allowed_persona) = 0 THEN NULL ELSE (SELECT ARRAY_AGG(value::text::uuid) FROM jsonb_array_elements_text(p_allowed_persona)) END;
    v_allowed_tags := CASE WHEN p_allowed_tags IS NULL OR jsonb_typeof(p_allowed_tags) != 'array' OR jsonb_array_length(p_allowed_tags) = 0 THEN NULL ELSE (SELECT ARRAY_AGG(value::text::uuid) FROM jsonb_array_elements_text(p_allowed_tags)) END;
    v_allowed_birthmonth := CASE WHEN p_allowed_birthmonth IS NULL OR jsonb_typeof(p_allowed_birthmonth) != 'array' OR jsonb_array_length(p_allowed_birthmonth) = 0 THEN NULL ELSE (SELECT ARRAY_AGG(value::text) FROM jsonb_array_elements_text(p_allowed_birthmonth)) END;
    v_image := CASE WHEN p_image IS NULL OR jsonb_typeof(p_image) != 'array' OR jsonb_array_length(p_image) = 0 THEN NULL ELSE (SELECT ARRAY_AGG(value::text) FROM jsonb_array_elements_text(p_image)) END;
    v_online_store := CASE WHEN p_online_store IS NULL OR jsonb_typeof(p_online_store) != 'array' OR jsonb_array_length(p_online_store) = 0 THEN NULL ELSE (SELECT ARRAY_AGG(value::text) FROM jsonb_array_elements_text(p_online_store)) END;
    v_reward_group_ids := CASE WHEN p_reward_group_ids IS NULL OR jsonb_typeof(p_reward_group_ids) != 'array' OR jsonb_array_length(p_reward_group_ids) = 0 THEN NULL ELSE (SELECT ARRAY_AGG(value::text::uuid) FROM jsonb_array_elements_text(p_reward_group_ids)) END;
    
    IF p_reward_id IS NULL THEN
        v_reward_id := gen_random_uuid();
        INSERT INTO reward_master (id, merchant_id, name, description_headline, description_body, description_tc, description_slip, image, category_id, visibility, redeem_window_start, redeem_window_end, stock_control, assign_promocode, use_expire_mode, use_expire_date, use_expire_ttl, fulfillment_method, allowed_tier, allowed_persona, allowed_tags, allowed_birthmonth, fallback_points, require_points_match, external_id_shopify, online_store, shopify_discount_type, shopify_discount_label, variant_config, physical_draw_name, physical_draw_description, created_at)
        VALUES (v_reward_id, v_merchant_id, p_name, p_description_headline, p_description_body, p_description_tc, p_description_slip, v_image, v_category_id, p_visibility, p_redeem_window_start, p_redeem_window_end, p_stock_control, p_assign_promocode, p_use_expire_mode, p_use_expire_date, p_use_expire_ttl, p_fulfillment_method, v_allowed_tier, v_allowed_persona, v_allowed_tags, v_allowed_birthmonth, p_fallback_points, p_require_points_match, p_external_id_shopify, v_online_store, p_shopify_discount_type, p_shopify_discount_label, p_variant_config, p_physical_draw_name, p_physical_draw_description, NOW());
        v_parent_created := true;
    ELSE
        v_reward_id := p_reward_id;
        UPDATE reward_master SET name = p_name, description_headline = p_description_headline, description_body = p_description_body, description_tc = p_description_tc, description_slip = p_description_slip, image = v_image, category_id = v_category_id, visibility = p_visibility, redeem_window_start = p_redeem_window_start, redeem_window_end = p_redeem_window_end, stock_control = p_stock_control, assign_promocode = p_assign_promocode, use_expire_mode = p_use_expire_mode, use_expire_date = p_use_expire_date, use_expire_ttl = p_use_expire_ttl, fulfillment_method = p_fulfillment_method, allowed_tier = v_allowed_tier, allowed_persona = v_allowed_persona, allowed_tags = v_allowed_tags, allowed_birthmonth = v_allowed_birthmonth, fallback_points = p_fallback_points, require_points_match = p_require_points_match, external_id_shopify = p_external_id_shopify, online_store = v_online_store,
          shopify_discount_type = COALESCE(p_shopify_discount_type, shopify_discount_type),
          shopify_discount_label = COALESCE(p_shopify_discount_label, shopify_discount_label),
          variant_config = p_variant_config,
          physical_draw_name = p_physical_draw_name,
          physical_draw_description = p_physical_draw_description
        WHERE id = v_reward_id AND merchant_id = v_merchant_id;
        IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND', 'title', fn_admin_envelope_message('not_found_title', v_lang), 'description', fn_admin_envelope_message('reward_not_found_desc', v_lang)); END IF;
        SELECT rm.name INTO v_reward_name FROM reward_master rm WHERE rm.id = v_reward_id;
        v_parent_updated := true;
    END IF;

    IF p_reward_group_ids IS NOT NULL THEN
        PERFORM public.fn_sync_reward_group_members_for_reward(
            v_merchant_id,
            v_reward_id,
            COALESCE(v_reward_group_ids, ARRAY[]::uuid[])
        );
    END IF;

    IF p_points_conditions IS NOT NULL AND jsonb_typeof(p_points_conditions) = 'array' AND jsonb_array_length(p_points_conditions) > 0 THEN
        FOR v_condition_obj IN SELECT * FROM jsonb_array_elements(p_points_conditions) LOOP
            v_condition_id := CASE WHEN v_condition_obj->>'id' IS NULL OR v_condition_obj->>'id' = '' THEN NULL ELSE (v_condition_obj->>'id')::UUID END;
            v_tier_id := CASE WHEN v_condition_obj->>'tier_id' IS NULL OR v_condition_obj->>'tier_id' = '' THEN NULL ELSE (v_condition_obj->>'tier_id')::UUID END;
            v_persona_id := CASE WHEN v_condition_obj->>'persona_id' IS NULL OR v_condition_obj->>'persona_id' = '' THEN NULL ELSE (v_condition_obj->>'persona_id')::UUID END;
            IF (v_condition_obj->>'points_required') IS NULL THEN v_conditions_skipped := v_conditions_skipped + 1; CONTINUE; END IF;
            v_tag_ids := NULL;
            IF v_condition_obj->'tag_ids' IS NOT NULL AND jsonb_typeof(v_condition_obj->'tag_ids') = 'array' THEN
                v_tag_ids := (SELECT ARRAY_AGG(value::text::uuid) FROM jsonb_array_elements_text(v_condition_obj->'tag_ids'));
            END IF;
            v_user_type := CASE WHEN v_condition_obj->>'user_type' IS NULL OR v_condition_obj->>'user_type' = '' THEN NULL ELSE (v_condition_obj->>'user_type')::user_type END;
            IF v_condition_id IS NOT NULL THEN
                UPDATE reward_points_conditions SET tier_id = v_tier_id, user_type = v_user_type, persona_id = v_persona_id, tag_ids = v_tag_ids, points_required = (v_condition_obj->>'points_required')::NUMERIC, priority = COALESCE((v_condition_obj->>'priority')::INTEGER, 100), condition_name = v_condition_obj->>'condition_name', description = v_condition_obj->>'description', active_status = COALESCE((v_condition_obj->>'active_status')::BOOLEAN, true), updated_at = NOW()
                WHERE id = v_condition_id AND reward_id = v_reward_id AND merchant_id = v_merchant_id;
                IF FOUND THEN v_conditions_updated := v_conditions_updated + 1; v_conditions_to_keep := array_append(v_conditions_to_keep, v_condition_id); ELSE v_conditions_skipped := v_conditions_skipped + 1; END IF;
            ELSE
                v_condition_id := gen_random_uuid();
                INSERT INTO reward_points_conditions (id, reward_id, merchant_id, tier_id, user_type, persona_id, tag_ids, points_required, priority, condition_name, description, active_status, created_at, updated_at)
                VALUES (v_condition_id, v_reward_id, v_merchant_id, v_tier_id, v_user_type, v_persona_id, v_tag_ids, (v_condition_obj->>'points_required')::NUMERIC, COALESCE((v_condition_obj->>'priority')::INTEGER, 100), v_condition_obj->>'condition_name', v_condition_obj->>'description', COALESCE((v_condition_obj->>'active_status')::BOOLEAN, true), NOW(), NOW());
                v_conditions_created := v_conditions_created + 1;
                v_conditions_to_keep := array_append(v_conditions_to_keep, v_condition_id);
            END IF;
        END LOOP;
        DELETE FROM reward_points_conditions WHERE reward_id = v_reward_id AND merchant_id = v_merchant_id AND id != ALL(v_conditions_to_keep);
        GET DIAGNOSTICS v_conditions_deleted = ROW_COUNT;
    ELSE
        DELETE FROM reward_points_conditions WHERE reward_id = v_reward_id AND merchant_id = v_merchant_id;
        GET DIAGNOSTICS v_conditions_deleted = ROW_COUNT;
    END IF;
    
    IF p_transaction_limits IS NOT NULL AND jsonb_typeof(p_transaction_limits) = 'array' AND jsonb_array_length(p_transaction_limits) > 0 THEN
        FOR v_limit_obj IN SELECT * FROM jsonb_array_elements(p_transaction_limits) LOOP
            v_limit_id_text := v_limit_obj->>'id';
            v_limit_id := CASE WHEN v_limit_id_text IS NULL OR v_limit_id_text = '' THEN NULL ELSE v_limit_id_text::UUID END;
            IF (v_limit_obj->>'scope') IS NULL OR v_limit_obj->>'scope' = '' OR (v_limit_obj->>'count') IS NULL THEN v_limits_skipped := v_limits_skipped + 1; CONTINUE; END IF;
            v_window_start := CASE WHEN v_limit_obj->>'window_start' IS NULL OR v_limit_obj->>'window_start' = '' THEN NULL ELSE (v_limit_obj->>'window_start')::TIMESTAMPTZ END;
            v_window_end := CASE WHEN v_limit_obj->>'window_end' IS NULL OR v_limit_obj->>'window_end' = '' THEN NULL ELSE (v_limit_obj->>'window_end')::TIMESTAMPTZ END;
            IF v_limit_id IS NOT NULL THEN
                UPDATE transaction_limits SET scope = (v_limit_obj->>'scope')::reward_condition_scope, count = (v_limit_obj->>'count')::NUMERIC, time_unit = CASE WHEN v_limit_obj->>'time_unit' IS NULL OR v_limit_obj->>'time_unit' = '' THEN NULL ELSE (v_limit_obj->>'time_unit')::reward_condition_time_unit END, window_start = v_window_start, window_end = v_window_end, active_status = COALESCE((v_limit_obj->>'active_status')::BOOLEAN, true)
                WHERE id = v_limit_id AND entity_id = v_reward_id AND merchant_id = v_merchant_id;
                IF FOUND THEN v_limits_updated := v_limits_updated + 1; v_limits_to_keep := array_append(v_limits_to_keep, v_limit_id); ELSE v_limits_skipped := v_limits_skipped + 1; END IF;
            ELSE
                v_limit_id := gen_random_uuid();
                INSERT INTO transaction_limits (id, entity_id, entity_type, merchant_id, scope, count, time_unit, window_start, window_end, active_status, created_at)
                VALUES (v_limit_id, v_reward_id, 'reward', v_merchant_id, (v_limit_obj->>'scope')::reward_condition_scope, (v_limit_obj->>'count')::NUMERIC, CASE WHEN v_limit_obj->>'time_unit' IS NULL OR v_limit_obj->>'time_unit' = '' THEN NULL ELSE (v_limit_obj->>'time_unit')::reward_condition_time_unit END, v_window_start, v_window_end, COALESCE((v_limit_obj->>'active_status')::BOOLEAN, true), NOW());
                v_limits_created := v_limits_created + 1;
                v_limits_to_keep := array_append(v_limits_to_keep, v_limit_id);
            END IF;
        END LOOP;
        DELETE FROM transaction_limits WHERE entity_id = v_reward_id AND entity_type = 'reward' AND merchant_id = v_merchant_id AND id != ALL(v_limits_to_keep);
        GET DIAGNOSTICS v_limits_deleted = ROW_COUNT;
    ELSE
        DELETE FROM transaction_limits WHERE entity_id = v_reward_id AND entity_type = 'reward' AND merchant_id = v_merchant_id;
        GET DIAGNOSTICS v_limits_deleted = ROW_COUNT;
    END IF;
    
    RETURN jsonb_build_object(
        'success', true, 
        'code', CASE WHEN v_parent_created THEN 'CREATED' ELSE 'UPDATED' END,
        'title', CASE WHEN v_parent_created THEN fn_admin_envelope_message('reward_created_title', v_lang) ELSE fn_admin_envelope_message('reward_updated_title', v_lang) END,
        'description', fn_admin_envelope_message('reward_action_desc', v_lang, ARRAY[v_reward_name, CASE WHEN v_parent_created THEN fn_admin_envelope_message('word_created', v_lang) ELSE fn_admin_envelope_message('word_updated', v_lang) END, (v_conditions_created + v_conditions_updated)::text, (v_limits_created + v_limits_updated)::text]),
        'reward_id', v_reward_id, 
        'parent_created', v_parent_created, 
        'parent_updated', v_parent_updated, 
        'conditions_created', v_conditions_created, 
        'conditions_updated', v_conditions_updated, 
        'conditions_deleted', v_conditions_deleted, 
        'limits_created', v_limits_created, 
        'limits_updated', v_limits_updated, 
        'limits_deleted', v_limits_deleted
    );
EXCEPTION WHEN OTHERS THEN 
    RETURN jsonb_build_object('success', false, 'code', 'ERROR', 'title', fn_admin_envelope_message('error_title', v_lang), 'description', SQLERRM, 'detail', SQLSTATE);
END;
$function$;

-- bff_upsert_campaign_reward_atomic
CREATE OR REPLACE FUNCTION public.bff_upsert_campaign_reward_atomic(p_reward jsonb, p_slot jsonb, p_request_id uuid, p_language text DEFAULT 'en'::text)
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

-- bff_upsert_reward_group_with_limits
DROP FUNCTION IF EXISTS public.bff_upsert_reward_group_with_limits(uuid, text, text, text, boolean, boolean, jsonb, text);
DROP FUNCTION IF EXISTS public.bff_upsert_reward_group_with_limits(uuid, text, text, text, boolean, jsonb, text);

CREATE OR REPLACE FUNCTION public.bff_upsert_reward_group_with_limits(p_group_id uuid DEFAULT NULL::uuid, p_group_code text DEFAULT NULL::text, p_name text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_is_active boolean DEFAULT true, p_is_featured boolean DEFAULT false, p_member_reward_ids uuid[] DEFAULT NULL::uuid[], p_transaction_limits jsonb DEFAULT NULL::jsonb, p_language text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_lang text;
    v_merchant_id UUID;
    v_group_id UUID;
    v_group_name TEXT;
    v_parent_created BOOLEAN := false;
    v_parent_updated BOOLEAN := false;
    v_limits_created INT := 0;
    v_limits_updated INT := 0;
    v_limits_deleted INT := 0;
    v_limits_skipped INT := 0;
    v_limit_obj JSONB;
    v_limit_id UUID;
    v_limit_id_text TEXT;
    v_limits_to_keep UUID[] := ARRAY[]::UUID[];
    v_window_start TIMESTAMPTZ;
    v_window_end TIMESTAMPTZ;
    v_metric reward_limit_metric;
    v_scope reward_condition_scope;
    v_time_unit reward_condition_time_unit;
    v_count NUMERIC;
    v_max_distinct NUMERIC := NULL;
    v_group_qty_user NUMERIC := NULL;
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
    v_merchant_id := get_current_merchant_id();
    IF v_merchant_id IS NULL THEN
        RETURN fn_response_error(fn_admin_envelope_message('error_title', v_lang), fn_admin_envelope_message('no_merchant_found_title', v_lang), 'NO_MERCHANT_CONTEXT');
    END IF;

    v_group_name := COALESCE(p_name, 'Untitled Group');

    IF p_transaction_limits IS NOT NULL AND jsonb_typeof(p_transaction_limits) = 'array' THEN
        FOR v_limit_obj IN SELECT * FROM jsonb_array_elements(p_transaction_limits) LOOP
            IF COALESCE((v_limit_obj->>'active_status')::BOOLEAN, true) = false THEN CONTINUE; END IF;

            v_metric := COALESCE(NULLIF(v_limit_obj->>'metric','')::reward_limit_metric, 'quantity');
            v_scope  := NULLIF(v_limit_obj->>'scope','')::reward_condition_scope;
            v_count  := NULLIF(v_limit_obj->>'count','')::NUMERIC;

            IF v_metric = 'distinct_reward' AND v_scope = 'user' THEN
                v_max_distinct := LEAST(COALESCE(v_max_distinct, v_count), v_count);
            ELSIF v_metric = 'quantity' AND v_scope = 'user' THEN
                v_group_qty_user := LEAST(COALESCE(v_group_qty_user, v_count), v_count);
            END IF;
        END LOOP;

        IF v_max_distinct IS NOT NULL AND v_group_qty_user IS NOT NULL
           AND v_max_distinct > v_group_qty_user THEN
            RETURN fn_response_error(
                fn_admin_envelope_message('invalid_configuration_title', v_lang),
                fn_admin_envelope_message('conflicting_group_limits_desc', v_lang, ARRAY[v_max_distinct::text, v_group_qty_user::text]),
                'CONFLICTING_GROUP_LIMITS'
            );
        END IF;
    END IF;

    IF p_group_id IS NULL THEN
        v_group_id := gen_random_uuid();
        INSERT INTO reward_group (id, merchant_id, group_code, name, description, is_active, is_featured, created_at, updated_at)
        VALUES (v_group_id, v_merchant_id, p_group_code, v_group_name, p_description, p_is_active, p_is_featured, NOW(), NOW());
        v_parent_created := true;
    ELSE
        v_group_id := p_group_id;
        UPDATE reward_group
        SET group_code  = p_group_code,
            name        = v_group_name,
            description = p_description,
            is_active   = p_is_active,
            is_featured = p_is_featured,
            updated_at  = NOW()
        WHERE id = v_group_id AND merchant_id = v_merchant_id;
        IF NOT FOUND THEN
            RETURN fn_response_error(fn_admin_envelope_message('not_found_title', v_lang), fn_admin_envelope_message('reward_group_not_found_desc', v_lang), 'NOT_FOUND');
        END IF;
        SELECT rg.name INTO v_group_name FROM reward_group rg WHERE rg.id = v_group_id;
        v_parent_updated := true;
    END IF;

    IF p_transaction_limits IS NOT NULL AND jsonb_typeof(p_transaction_limits) = 'array' AND jsonb_array_length(p_transaction_limits) > 0 THEN
        FOR v_limit_obj IN SELECT * FROM jsonb_array_elements(p_transaction_limits) LOOP
            v_limit_id_text := v_limit_obj->>'id';
            v_limit_id := CASE WHEN v_limit_id_text IS NULL OR v_limit_id_text = '' THEN NULL ELSE v_limit_id_text::UUID END;

            IF (v_limit_obj->>'scope') IS NULL OR v_limit_obj->>'scope' = '' OR (v_limit_obj->>'count') IS NULL THEN
                v_limits_skipped := v_limits_skipped + 1; CONTINUE;
            END IF;

            v_metric := COALESCE(NULLIF(v_limit_obj->>'metric','')::reward_limit_metric, 'quantity');
            v_scope  := (v_limit_obj->>'scope')::reward_condition_scope;
            v_count  := (v_limit_obj->>'count')::NUMERIC;
            v_time_unit := CASE WHEN v_limit_obj->>'time_unit' IS NULL OR v_limit_obj->>'time_unit' = ''
                                THEN NULL ELSE (v_limit_obj->>'time_unit')::reward_condition_time_unit END;
            v_window_start := CASE WHEN v_limit_obj->>'window_start' IS NULL OR v_limit_obj->>'window_start' = ''
                                   THEN NULL ELSE (v_limit_obj->>'window_start')::TIMESTAMPTZ END;
            v_window_end   := CASE WHEN v_limit_obj->>'window_end'   IS NULL OR v_limit_obj->>'window_end'   = ''
                                   THEN NULL ELSE (v_limit_obj->>'window_end')::TIMESTAMPTZ END;

            IF v_metric = 'distinct_reward' AND v_scope <> 'user' THEN
                RETURN fn_response_error(
                    fn_admin_envelope_message('invalid_configuration_title', v_lang),
                    fn_admin_envelope_message('invalid_metric_scope_desc', v_lang),
                    'INVALID_METRIC_SCOPE'
                );
            END IF;

            IF v_limit_id IS NOT NULL THEN
                UPDATE transaction_limits
                SET metric       = v_metric,
                    scope        = v_scope,
                    count        = v_count,
                    time_unit    = v_time_unit,
                    window_start = v_window_start,
                    window_end   = v_window_end,
                    active_status = COALESCE((v_limit_obj->>'active_status')::BOOLEAN, true)
                WHERE id = v_limit_id AND entity_id = v_group_id AND merchant_id = v_merchant_id;
                IF FOUND THEN
                    v_limits_updated := v_limits_updated + 1;
                    v_limits_to_keep := array_append(v_limits_to_keep, v_limit_id);
                ELSE
                    v_limits_skipped := v_limits_skipped + 1;
                END IF;
            ELSE
                v_limit_id := gen_random_uuid();
                INSERT INTO transaction_limits (id, entity_id, entity_type, merchant_id, metric, scope, count, time_unit, window_start, window_end, active_status, created_at)
                VALUES (
                    v_limit_id, v_group_id, 'reward_group', v_merchant_id,
                    v_metric, v_scope, v_count, v_time_unit,
                    v_window_start, v_window_end,
                    COALESCE((v_limit_obj->>'active_status')::BOOLEAN, true),
                    NOW()
                );
                v_limits_created := v_limits_created + 1;
                v_limits_to_keep := array_append(v_limits_to_keep, v_limit_id);
            END IF;
        END LOOP;

        DELETE FROM transaction_limits
        WHERE entity_id = v_group_id AND entity_type = 'reward_group' AND merchant_id = v_merchant_id AND id != ALL(v_limits_to_keep);
        GET DIAGNOSTICS v_limits_deleted = ROW_COUNT;
    ELSE
        DELETE FROM transaction_limits
        WHERE entity_id = v_group_id AND entity_type = 'reward_group' AND merchant_id = v_merchant_id;
        GET DIAGNOSTICS v_limits_deleted = ROW_COUNT;
    END IF;

    IF p_member_reward_ids IS NOT NULL THEN
        PERFORM public.fn_sync_reward_group_members_for_group(v_merchant_id, v_group_id, p_member_reward_ids);
    END IF;


    RETURN jsonb_build_object(
        'success', true,
        'code', CASE WHEN v_parent_created THEN 'CREATED' ELSE 'UPDATED' END,
        'title', CASE WHEN v_parent_created THEN fn_admin_envelope_message('reward_group_created_title', v_lang) ELSE fn_admin_envelope_message('reward_group_updated_title', v_lang) END,
        'description', fn_admin_envelope_message('reward_group_action_desc', v_lang, ARRAY[v_group_name, CASE WHEN v_parent_created THEN fn_admin_envelope_message('word_created', v_lang) ELSE fn_admin_envelope_message('word_updated', v_lang) END, (v_limits_created + v_limits_updated)::text]),
        'group_id', v_group_id,
        'parent_created', v_parent_created,
        'parent_updated', v_parent_updated,
        'limits_created', v_limits_created,
        'limits_updated', v_limits_updated,
        'limits_deleted', v_limits_deleted
    );

EXCEPTION WHEN OTHERS THEN
    RETURN fn_response_error(fn_admin_envelope_message('error_title', v_lang), SQLERRM, 'ERROR');
END;
$function$;

DROP VIEW IF EXISTS public.v_rewards;

CREATE VIEW public.v_rewards AS
 SELECT id,
    merchant_id,
    name AS name_default,
    description_headline AS description_headline_default,
    description_body AS description_body_default,
    description_tc AS description_tc_default,
    description_slip AS description_slip_default,
    fallback_points,
    require_points_match,
    image,
    visibility,
    stock_control,
    assign_promocode,
    fulfillment_method,
    redeem_window_start,
    redeem_window_end,
    use_expire_mode,
    use_expire_date,
    use_expire_ttl,
    allowed_tier,
    allowed_persona,
    allowed_tags,
    allowed_birthmonth,
    created_at,
    ( SELECT jsonb_agg(jsonb_build_object('language_code', sub.language_code, 'name', sub.name, 'description_headline', sub.description_headline, 'description_body', sub.description_body, 'description_tc', sub.description_tc, 'description_slip', sub.description_slip)) AS jsonb_agg
           FROM ( SELECT t.language_code,
                    max(
                        CASE
                            WHEN t.field_name = 'name'::text THEN t.translated_value
                            ELSE NULL::text
                        END) AS name,
                    max(
                        CASE
                            WHEN t.field_name = 'description_headline'::text THEN t.translated_value
                            ELSE NULL::text
                        END) AS description_headline,
                    max(
                        CASE
                            WHEN t.field_name = 'description_body'::text THEN t.translated_value
                            ELSE NULL::text
                        END) AS description_body,
                    max(
                        CASE
                            WHEN t.field_name = 'description_tc'::text THEN t.translated_value
                            ELSE NULL::text
                        END) AS description_tc,
                    max(
                        CASE
                            WHEN t.field_name = 'description_slip'::text THEN t.translated_value
                            ELSE NULL::text
                        END) AS description_slip
                   FROM translations t
                  WHERE t.entity_id = r.id AND t.entity_type = 'reward'::text
                  GROUP BY t.language_code) sub) AS translations,
        CASE
            WHEN stock_control THEN ( SELECT count(*) AS count
               FROM reward_promo_code
              WHERE reward_promo_code.reward_id = r.id AND reward_promo_code.redeemed_status = false)
            ELSE NULL::bigint
        END AS available_stock,
    public.fn_reward_group_ids_for_reward(r.id) AS reward_group_ids
   FROM reward_master r
  WHERE merchant_id = get_current_merchant_id();

ALTER TABLE public.reward_master DROP COLUMN IF EXISTS reward_group_ids;
