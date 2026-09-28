-- Reward list server pagination + per-reward redemption stats.
--
-- Why: bff_list_rewards returns every reward for the merchant and LEFT JOINs a
-- GROUP BY over the merchant's whole reward_redemptions_ledger (1.5–1.8M rows on
-- large merchants) to attach redeemed/used counts — ~2.5s mean, 10s max — while
-- the admin UI shows 25 rows. Admin callers move to bff_list_rewards_paged
-- (filters + pagination in SQL, no ledger join); the counts move to the reward
-- detail header via bff_get_reward_redemption_stats (one reward, indexed).
-- bff_list_rewards is left in place for any remaining caller.

-- ---------------------------------------------------------------------------
-- Search index (pg_trgm already enabled on project)
-- ---------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_reward_master_name_trgm
  ON public.reward_master USING gin (name gin_trgm_ops);

-- ---------------------------------------------------------------------------
-- Shared filter (inlined SQL) so count + page share one predicate set
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_reward_admin_list_base(
  p_merchant_id uuid,
  p_query text,
  p_kind text,
  p_status text,
  p_category_ids uuid[],
  p_visibility text[],
  p_ids uuid[]
)
RETURNS SETOF public.reward_master
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $$
  SELECT r.*
  FROM public.reward_master r
  WHERE r.merchant_id = p_merchant_id
    AND (p_ids IS NULL OR cardinality(p_ids) = 0 OR r.id = ANY (p_ids))
    AND (
      p_kind = 'all'
      OR (p_kind = 'catalog' AND COALESCE(r.visibility::text, '') <> 'campaign')
      OR (p_kind = 'campaign' AND r.visibility::text = 'campaign')
    )
    AND (
      p_status = 'all'
      OR (p_status = 'active' AND r.active_status IS TRUE)
      OR (p_status = 'inactive' AND r.active_status IS NOT TRUE)
    )
    AND (
      p_category_ids IS NULL
      OR cardinality(p_category_ids) = 0
      OR r.category_id && p_category_ids
    )
    AND (
      p_visibility IS NULL
      OR cardinality(p_visibility) = 0
      OR r.visibility::text = ANY (p_visibility)
    )
    AND (
      p_query IS NULL
      OR r.name ILIKE '%' || p_query || '%'
      OR r.reward_code ILIKE '%' || p_query || '%'
      OR similarity(r.name, p_query) > 0.3
    );
$$;

-- ---------------------------------------------------------------------------
-- Paged reward list (admin list page + every reward picker / preview / count)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.bff_list_rewards_paged(
  p_query text DEFAULT NULL,
  p_kind text DEFAULT 'all',            -- all | catalog | campaign
  p_status text DEFAULT 'all',          -- all | active | inactive
  p_category_ids uuid[] DEFAULT NULL,
  p_visibility text[] DEFAULT NULL,     -- optional explicit visibility whitelist (Shopify surface)
  p_ids uuid[] DEFAULT NULL,            -- hydrate already-selected rows in pickers
  p_page integer DEFAULT 1,
  p_page_size integer DEFAULT 25,
  p_with_summary boolean DEFAULT false  -- tab / banner / quota counts (reward_master only)
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_q text := NULLIF(trim(COALESCE(p_query, '')), '');
  v_kind text := lower(COALESCE(NULLIF(trim(p_kind), ''), 'all'));
  v_status text := lower(COALESCE(NULLIF(trim(p_status), ''), 'all'));
  v_page int := GREATEST(COALESCE(p_page, 1), 1);
  v_page_size int := LEAST(GREATEST(COALESCE(p_page_size, 25), 1), 100);
  v_offset int;
  v_total bigint := 0;
  v_items jsonb := '[]'::jsonb;
  v_summary jsonb := NULL;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'No merchant context');
  END IF;

  IF v_kind NOT IN ('all', 'catalog', 'campaign') THEN v_kind := 'all'; END IF;
  IF v_status NOT IN ('all', 'active', 'inactive') THEN v_status := 'all'; END IF;
  v_offset := (v_page - 1) * v_page_size;

  SELECT COUNT(*) INTO v_total
  FROM fn_reward_admin_list_base(
    v_merchant_id, v_q, v_kind, v_status, p_category_ids, p_visibility, p_ids
  );

  SELECT COALESCE(jsonb_agg(row_json ORDER BY ord), '[]'::jsonb)
  INTO v_items
  FROM (
    SELECT
      jsonb_build_object(
        'id', b.id,
        'name', b.name,
        'reward_code', b.reward_code,
        'category_id', b.category_id,
        'visibility', b.visibility,
        'redeem_window_start', b.redeem_window_start,
        'redeem_window_end', b.redeem_window_end,
        'require_points_match', b.require_points_match,
        'points', jsonb_build_object('fallback', COALESCE(b.fallback_points, 0)),
        'stock_control', b.stock_control,
        'active_status', b.active_status,
        'shopify_discount_type', b.shopify_discount_type,
        'assign_promocode', COALESCE(b.assign_promocode, false),
        'is_featured', COALESCE(b.is_featured, false),
        'image_url', b.image[1],
        'created_at', b.created_at
      ) AS row_json,
      row_number() OVER (
        ORDER BY
          CASE
            WHEN v_q IS NULL THEN 0
            WHEN b.name ILIKE v_q || '%' THEN 0
            WHEN b.name ILIKE '%' || v_q || '%' THEN 1
            ELSE 2
          END,
          CASE WHEN v_q IS NULL THEN 0 ELSE -similarity(b.name, v_q) END,
          COALESCE(b.is_featured, false) DESC,
          b.created_at DESC,
          b.id DESC
      ) AS ord
    FROM fn_reward_admin_list_base(
      v_merchant_id, v_q, v_kind, v_status, p_category_ids, p_visibility, p_ids
    ) b
    ORDER BY ord
    LIMIT v_page_size OFFSET v_offset
  ) q;

  IF COALESCE(p_with_summary, false) THEN
    SELECT jsonb_build_object(
      'total', COUNT(*),
      'catalog_total', COUNT(*) FILTER (WHERE COALESCE(r.visibility::text, '') <> 'campaign'),
      'campaign_total', COUNT(*) FILTER (WHERE r.visibility::text = 'campaign'),
      'active_catalog_total', COUNT(*) FILTER (
        WHERE r.active_status IS TRUE AND COALESCE(r.visibility::text, '') <> 'campaign'
      ),
      'active_total', COUNT(*) FILTER (WHERE r.active_status IS TRUE),
      'by_visibility', jsonb_build_object(
        'user', COUNT(*) FILTER (WHERE r.visibility::text = 'user'),
        'user_only', COUNT(*) FILTER (WHERE r.visibility::text = 'user_only'),
        'admin', COUNT(*) FILTER (WHERE r.visibility::text = 'admin'),
        'campaign', COUNT(*) FILTER (WHERE r.visibility::text = 'campaign')
      )
    )
    INTO v_summary
    FROM reward_master r
    WHERE r.merchant_id = v_merchant_id
      AND (
        p_visibility IS NULL
        OR cardinality(p_visibility) = 0
        OR r.visibility::text = ANY (p_visibility)
      );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'data', jsonb_build_object(
      'items', v_items,
      'total', v_total,
      'page', v_page,
      'page_size', v_page_size,
      'summary', v_summary
    )
  );
END;
$function$;

-- ---------------------------------------------------------------------------
-- Per-reward redemption stats (reward detail header pills)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.bff_get_reward_redemption_stats(p_reward_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_redeemed_qty bigint := 0;
  v_used_qty bigint := 0;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error('No merchant context', NULL, 'NO_MERCHANT', NULL);
  END IF;

  IF p_reward_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM reward_master rm
    WHERE rm.id = p_reward_id AND rm.merchant_id = v_merchant_id
  ) THEN
    RETURN fn_response_error('Reward not found', NULL, 'NOT_FOUND', NULL);
  END IF;

  SELECT
    COALESCE(SUM(COALESCE(rrl.qty, 1)), 0)::bigint,
    COALESCE(SUM(
      CASE WHEN COALESCE(rrl.used_status, false) THEN COALESCE(rrl.qty, 1) ELSE 0 END
    ), 0)::bigint
  INTO v_redeemed_qty, v_used_qty
  FROM reward_redemptions_ledger rrl
  WHERE rrl.merchant_id = v_merchant_id
    AND rrl.reward_id = p_reward_id
    AND fn_reward_admin_ledger_reportable(
      rrl.success,
      rrl.cancelled,
      rrl.redeemed_status,
      rrl.package_assignment_id,
      rrl.source_type
    );

  RETURN fn_response_success(
    'Reward redemption stats',
    NULL,
    jsonb_build_object(
      'redeemed_qty', v_redeemed_qty,
      'used_qty', v_used_qty,
      'not_used_qty', GREATEST(v_redeemed_qty - v_used_qty, 0)
    )
  );
END;
$function$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

REVOKE ALL ON FUNCTION public.fn_reward_admin_list_base(uuid, text, text, text, uuid[], text[], uuid[]) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.bff_list_rewards_paged(text, text, text, uuid[], text[], uuid[], integer, integer, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.bff_get_reward_redemption_stats(uuid) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.bff_list_rewards_paged(text, text, text, uuid[], text[], uuid[], integer, integer, boolean) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_get_reward_redemption_stats(uuid) TO authenticated, service_role;
