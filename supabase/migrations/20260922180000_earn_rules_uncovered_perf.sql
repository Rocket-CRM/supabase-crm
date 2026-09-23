-- Uncovered stores: avoid O(stores × factors) NOT EXISTS; bulk direct store IDs + attribute-set pass only.

CREATE OR REPLACE FUNCTION public.earn_rule_covered_store_ids(
  p_merchant_id uuid,
  p_group_id uuid,
  p_category_ids uuid[]
)
RETURNS SETOF uuid
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
  v_factor_id uuid;
BEGIN
  IF p_group_id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT DISTINCT uid::uuid
  FROM public.earn_factor ef
  JOIN public.earn_conditions ec
    ON ec.group_id = ef.earn_conditions_group_id
   AND ec.merchant_id = p_merchant_id
  CROSS JOIN LATERAL unnest(ec.entity_ids) AS uid
  WHERE ef.merchant_id = p_merchant_id
    AND ef.earn_factor_group_id = p_group_id
    AND ef.active_status IS TRUE
    AND ef.earn_factor_type IN ('rate', 'multiplier')
    AND ef.earn_factor_amount IS NOT NULL
    AND ec.entity = 'store'
    AND ec.exclude IS NOT TRUE
    AND uid IS NOT NULL;

  FOR v_factor_id IN
    SELECT ef.id
    FROM public.earn_factor ef
    WHERE ef.merchant_id = p_merchant_id
      AND ef.earn_factor_group_id = p_group_id
      AND ef.active_status IS TRUE
      AND ef.earn_factor_type IN ('rate', 'multiplier')
      AND ef.earn_factor_amount IS NOT NULL
      AND EXISTS (
        SELECT 1
        FROM public.earn_conditions ec
        WHERE ec.group_id = ef.earn_conditions_group_id
          AND ec.merchant_id = p_merchant_id
          AND ec.exclude IS NOT TRUE
          AND ec.entity = 'store_attribute_set'
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.earn_conditions ec
        WHERE ec.group_id = ef.earn_conditions_group_id
          AND ec.merchant_id = p_merchant_id
          AND ec.exclude IS NOT TRUE
          AND ec.entity = 'store'
          AND ec.entity_ids IS NOT NULL
          AND cardinality(ec.entity_ids) > 0
      )
  LOOP
    RETURN QUERY
    SELECT sm.id
    FROM public.store_master sm
    WHERE sm.merchant_id = p_merchant_id
      AND sm.active_status IS TRUE
      AND public.earn_rule_factor_covers_store(
        v_factor_id, sm.id, p_merchant_id, p_category_ids
      );
  END LOOP;

  RETURN;
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_list_uncovered_stores(
  p_query text DEFAULT NULL,
  p_limit integer DEFAULT 10,
  p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_dims jsonb;
  v_group_id uuid;
  v_cat_ids uuid[];
  v_advanced boolean;
  v_q text := trim(COALESCE(p_query, ''));
  v_lim int := LEAST(GREATEST(COALESCE(p_limit, 10), 1), 100);
  v_off int := GREATEST(COALESCE(p_offset, 0), 0);
  v_total int;
  v_items jsonb;
BEGIN
  v_merchant_id := public.get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'No merchant context found');
  END IF;

  SELECT mm.advanced_earn_enabled INTO v_advanced
  FROM public.merchant_master mm WHERE mm.id = v_merchant_id;

  v_dims := public.earn_rule_dimensions_from_merchant(v_merchant_id);
  IF NOT public.earn_rule_has_store_dimension(v_dims) THEN
    RETURN jsonb_build_object('total', 0, 'items', '[]'::jsonb);
  END IF;

  SELECT COALESCE(array_agg(x::uuid), ARRAY[]::uuid[])
  INTO v_cat_ids
  FROM jsonb_array_elements_text(COALESCE(v_dims -> 'store_attribute_category_ids', '[]'::jsonb)) x;

  IF v_advanced IS TRUE THEN
    v_group_id := public.earn_rule_resolve_advanced_store_group_id(v_merchant_id);
  ELSE
    SELECT (public.bff_get_basic_currency_config('points') ->> 'earn_factor_group_id')::uuid
    INTO v_group_id;
    IF v_group_id IS NULL THEN
      SELECT ef.earn_factor_group_id INTO v_group_id
      FROM public.earn_factor ef
      WHERE ef.merchant_id = v_merchant_id
        AND ef.target_currency = 'points'::public.currency
        AND ef.target_entity_id IS NULL
      LIMIT 1;
    END IF;
  END IF;

  WITH covered AS (
    SELECT DISTINCT c.store_id
    FROM public.earn_rule_covered_store_ids(v_merchant_id, v_group_id, v_cat_ids) AS c(store_id)
  ),
  uncovered AS (
    SELECT sm.id, sm.store_code, sm.store_name, sm.active_status
    FROM public.store_master sm
    WHERE sm.merchant_id = v_merchant_id
      AND sm.active_status IS TRUE
      AND (
        v_q = ''
        OR sm.store_name ILIKE '%' || v_q || '%'
        OR sm.store_code ILIKE '%' || v_q || '%'
      )
      AND NOT EXISTS (SELECT 1 FROM covered c WHERE c.store_id = sm.id)
  )
  SELECT COUNT(*)::int INTO v_total FROM uncovered;

  WITH covered AS (
    SELECT DISTINCT c.store_id
    FROM public.earn_rule_covered_store_ids(v_merchant_id, v_group_id, v_cat_ids) AS c(store_id)
  ),
  uncovered AS (
    SELECT sm.id, sm.store_code, sm.store_name, sm.active_status
    FROM public.store_master sm
    WHERE sm.merchant_id = v_merchant_id
      AND sm.active_status IS TRUE
      AND (
        v_q = ''
        OR sm.store_name ILIKE '%' || v_q || '%'
        OR sm.store_code ILIKE '%' || v_q || '%'
      )
      AND NOT EXISTS (SELECT 1 FROM covered c WHERE c.store_id = sm.id)
  )
  SELECT COALESCE(jsonb_agg(row_to_json(r)::jsonb), '[]'::jsonb)
  INTO v_items
  FROM (
    SELECT
      u.id,
      u.store_code::text AS code,
      u.store_name::text AS label,
      u.store_code::text AS sublabel,
      u.active_status AS active,
      jsonb_build_object(
        'assignments',
        public.earn_rule_store_assignments_meta(u.id, v_merchant_id)
      ) AS meta
    FROM uncovered u
    ORDER BY u.store_name
    LIMIT v_lim OFFSET v_off
  ) r;

  RETURN jsonb_build_object('total', COALESCE(v_total, 0), 'items', COALESCE(v_items, '[]'::jsonb));
END;
$function$;
