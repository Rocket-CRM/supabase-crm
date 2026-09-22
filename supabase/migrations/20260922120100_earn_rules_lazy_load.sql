-- Earn Rules lazy load (EARNRULE-0030 Phase 0): read-only BFF RPCs + store-matching helpers + trigram indexes.
-- Advanced group tie-break: highest factor count, then most recently created earn_factor_group (max created_at).

-- ---------------------------------------------------------------------------
-- 0d. Trigram indexes (pg_trgm already enabled on project)
-- ---------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_store_master_store_name_trgm
  ON public.store_master USING gin (store_name gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_store_master_store_code_trgm
  ON public.store_master USING gin (store_code gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_product_master_name_trgm
  ON public.product_master USING gin (name gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_product_master_product_code_trgm
  ON public.product_master USING gin (product_code gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_product_sku_master_name_trgm
  ON public.product_sku_master USING gin (name gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_product_sku_master_sku_code_trgm
  ON public.product_sku_master USING gin (sku_code gin_trgm_ops);

-- ---------------------------------------------------------------------------
-- Store matching helpers (mirror loyalty-admin row-helpers.ts)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.earn_rule_store_assignment_matches(
  p_assignment_attribute_id uuid,
  p_assignment_sub_attribute_id uuid,
  p_selection_attribute_id uuid,
  p_selection_sub_attribute_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT CASE
    WHEN p_selection_attribute_id IS NULL AND p_selection_sub_attribute_id IS NULL THEN TRUE
    WHEN p_assignment_attribute_id IS NULL AND p_assignment_sub_attribute_id IS NULL THEN FALSE
    WHEN p_selection_sub_attribute_id IS NOT NULL THEN
      p_assignment_sub_attribute_id IS NOT DISTINCT FROM p_selection_sub_attribute_id
    WHEN p_selection_attribute_id IS NOT NULL THEN
      p_assignment_attribute_id IS NOT DISTINCT FROM p_selection_attribute_id
    ELSE TRUE
  END;
$$;

CREATE OR REPLACE FUNCTION public.earn_rule_row_covers_store(
  p_amount numeric,
  p_row_store_id uuid,
  p_category_ids uuid[],
  p_selections jsonb,
  p_store_id uuid,
  p_merchant_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_cat uuid;
  v_sel jsonb;
  v_attr uuid;
  v_sub uuid;
  v_asg_attr uuid;
  v_asg_sub uuid;
BEGIN
  IF p_amount IS NULL THEN
    RETURN FALSE;
  END IF;

  IF p_row_store_id IS NOT NULL THEN
    RETURN p_row_store_id = p_store_id;
  END IF;

  IF p_category_ids IS NULL OR cardinality(p_category_ids) = 0 THEN
    RETURN TRUE;
  END IF;

  FOREACH v_cat IN ARRAY p_category_ids LOOP
    v_sel := p_selections -> v_cat::text;
    v_attr := NULLIF(v_sel ->> 'attribute_id', '')::uuid;
    v_sub := NULLIF(v_sel ->> 'sub_attribute_id', '')::uuid;

    SELECT saa.attribute_id, saa.sub_attribute_id
    INTO v_asg_attr, v_asg_sub
    FROM public.store_attribute_assignments saa
    WHERE saa.merchant_id = p_merchant_id
      AND saa.store_id = p_store_id
      AND saa.category_id = v_cat
    LIMIT 1;

    IF NOT public.earn_rule_store_assignment_matches(
      v_asg_attr, v_asg_sub, v_attr, v_sub
    ) THEN
      RETURN FALSE;
    END IF;
  END LOOP;

  RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION public.earn_rule_store_assignments_meta(
  p_store_id uuid,
  p_merchant_id uuid
)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'category_id', saa.category_id,
        'attribute_id', saa.attribute_id,
        'sub_attribute_id', saa.sub_attribute_id
      )
      ORDER BY saa.category_id
    ),
    '[]'::jsonb
  )
  FROM public.store_attribute_assignments saa
  WHERE saa.merchant_id = p_merchant_id
    AND saa.store_id = p_store_id;
$$;

CREATE OR REPLACE FUNCTION public.earn_rule_resolve_advanced_store_group_id(p_merchant_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  WITH factors AS (
    SELECT ef.earn_factor_group_id, ef.earn_conditions_group_id
    FROM public.earn_factor ef
    WHERE ef.merchant_id = p_merchant_id
      AND ef.target_currency = 'points'::public.currency
      AND ef.active_status IS TRUE
      AND ef.earn_factor_type IN ('rate', 'multiplier')
  ),
  store_cond_groups AS (
    SELECT DISTINCT f.earn_conditions_group_id
    FROM factors f
    JOIN public.earn_conditions ec
      ON ec.group_id = f.earn_conditions_group_id
     AND ec.merchant_id = p_merchant_id
    WHERE ec.entity IN ('store', 'store_attribute_set')
  ),
  counts AS (
    SELECT f.earn_factor_group_id, COUNT(*)::int AS cnt
    FROM factors f
    WHERE f.earn_conditions_group_id IN (SELECT earn_conditions_group_id FROM store_cond_groups)
    GROUP BY f.earn_factor_group_id
  )
  SELECT c.earn_factor_group_id
  FROM counts c
  JOIN public.earn_factor_group efg ON efg.id = c.earn_factor_group_id
  ORDER BY c.cnt DESC, efg.created_at DESC
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.earn_rule_factor_covers_store(
  p_factor_id uuid,
  p_store_id uuid,
  p_merchant_id uuid,
  p_category_ids uuid[]
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_amount numeric;
  v_row_store_id uuid;
  v_selections jsonb := '{}'::jsonb;
  v_cond record;
  v_member record;
  v_category_id uuid;
  v_attr_id uuid;
BEGIN
  SELECT ef.earn_factor_amount
  INTO v_amount
  FROM public.earn_factor ef
  WHERE ef.id = p_factor_id
    AND ef.merchant_id = p_merchant_id
    AND ef.active_status IS TRUE
    AND ef.earn_factor_type IN ('rate', 'multiplier')
    AND ef.earn_factor_amount IS NOT NULL;

  IF v_amount IS NULL THEN
    RETURN FALSE;
  END IF;

  FOR v_cond IN
    SELECT ec.entity, ec.entity_ids
    FROM public.earn_factor ef
    JOIN public.earn_conditions ec
      ON ec.group_id = ef.earn_conditions_group_id
     AND ec.merchant_id = p_merchant_id
    WHERE ef.id = p_factor_id
      AND ec.exclude IS NOT TRUE
      AND ec.entity IN ('store', 'store_attribute_set')
  LOOP
    IF v_cond.entity = 'store'
       AND v_cond.entity_ids IS NOT NULL
       AND cardinality(v_cond.entity_ids) > 0 THEN
      v_row_store_id := v_cond.entity_ids[1];
    ELSIF v_cond.entity = 'store_attribute_set'
       AND v_cond.entity_ids IS NOT NULL
       AND cardinality(v_cond.entity_ids) > 0 THEN
      SELECT m.attribute_id, m.sub_attribute_id, m.store_id
      INTO v_member
      FROM public.store_attribute_set_members m
      WHERE m.set_id = v_cond.entity_ids[1]
        AND m.is_deleted IS NOT TRUE
      LIMIT 1;

      IF v_member.store_id IS NOT NULL THEN
        v_row_store_id := v_member.store_id;
      ELSIF v_member.sub_attribute_id IS NOT NULL THEN
        SELECT sa.category_id, sa.id
        INTO v_category_id, v_attr_id
        FROM public.store_sub_attributes ssa
        JOIN public.store_attributes sa ON sa.id = ssa.attribute_id
        WHERE ssa.id = v_member.sub_attribute_id
          AND ssa.merchant_id = p_merchant_id
        LIMIT 1;
        IF v_category_id IS NOT NULL THEN
          v_selections := v_selections || jsonb_build_object(
            v_category_id::text,
            jsonb_build_object(
              'attribute_id', v_attr_id,
              'sub_attribute_id', v_member.sub_attribute_id
            )
          );
        END IF;
      ELSIF v_member.attribute_id IS NOT NULL THEN
        SELECT sa.category_id
        INTO v_category_id
        FROM public.store_attributes sa
        WHERE sa.id = v_member.attribute_id
          AND sa.merchant_id = p_merchant_id
        LIMIT 1;
        IF v_category_id IS NOT NULL THEN
          v_selections := v_selections || jsonb_build_object(
            v_category_id::text,
            jsonb_build_object(
              'attribute_id', v_member.attribute_id,
              'sub_attribute_id', NULL
            )
          );
        END IF;
      END IF;
    END IF;
  END LOOP;

  RETURN public.earn_rule_row_covers_store(
    v_amount,
    v_row_store_id,
    p_category_ids,
    v_selections,
    p_store_id,
    p_merchant_id
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.earn_rule_dimensions_from_merchant(p_merchant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_advanced_enabled boolean;
  v_config jsonb;
  v_dims jsonb;
  v_schema_name text;
  v_parsed jsonb;
  v_cat_ids jsonb;
BEGIN
  SELECT mm.advanced_earn_enabled, COALESCE(mm.advanced_earn_config, '{}'::jsonb)
  INTO v_advanced_enabled, v_config
  FROM public.merchant_master mm
  WHERE mm.id = p_merchant_id;

  v_dims := jsonb_build_object(
    'store_attribute_category_ids', '[]'::jsonb,
    'include_store', false,
    'include_tier', false,
    'include_persona', false,
    'include_product_category', false,
    'include_product_brand', false,
    'include_product_sku', false,
    'include_product_product', false
  );

  IF v_advanced_enabled IS TRUE THEN
    SELECT COALESCE(jsonb_agg(DISTINCT (prop ->> 'category_id')::uuid) FILTER (
      WHERE prop ->> 'type' = 'store_attribute_category' AND NULLIF(prop ->> 'category_id', '') IS NOT NULL
    ), '[]'::jsonb)
    INTO v_cat_ids
    FROM jsonb_array_elements(COALESCE(v_config -> 'properties', '[]'::jsonb)) prop;

    v_dims := jsonb_build_object(
      'store_attribute_category_ids', v_cat_ids,
      'include_store', EXISTS (
        SELECT 1 FROM jsonb_array_elements(COALESCE(v_config -> 'properties', '[]'::jsonb)) p
        WHERE p ->> 'type' = 'store'
      ),
      'include_tier', EXISTS (
        SELECT 1 FROM jsonb_array_elements(COALESCE(v_config -> 'properties', '[]'::jsonb)) p
        WHERE p ->> 'type' = 'tier'
      ),
      'include_persona', EXISTS (
        SELECT 1 FROM jsonb_array_elements(COALESCE(v_config -> 'properties', '[]'::jsonb)) p
        WHERE p ->> 'type' = 'persona'
      ),
      'include_product_category', EXISTS (
        SELECT 1 FROM jsonb_array_elements(COALESCE(v_config -> 'properties', '[]'::jsonb)) p
        WHERE p ->> 'type' = 'product_category'
      ),
      'include_product_brand', EXISTS (
        SELECT 1 FROM jsonb_array_elements(COALESCE(v_config -> 'properties', '[]'::jsonb)) p
        WHERE p ->> 'type' = 'product_brand'
      ),
      'include_product_sku', EXISTS (
        SELECT 1 FROM jsonb_array_elements(COALESCE(v_config -> 'properties', '[]'::jsonb)) p
        WHERE p ->> 'type' = 'product_sku'
      ),
      'include_product_product', EXISTS (
        SELECT 1 FROM jsonb_array_elements(COALESCE(v_config -> 'properties', '[]'::jsonb)) p
        WHERE p ->> 'type' = 'product_product'
      )
    );
    RETURN v_dims;
  END IF;

  SELECT ecg.name
  INTO v_schema_name
  FROM public.earn_conditions_group ecg
  WHERE ecg.merchant_id = p_merchant_id
    AND ecg.name LIKE '__earn_rate_dimensions:%'
  ORDER BY ecg.created_at
  LIMIT 1;

  IF v_schema_name IS NOT NULL THEN
    BEGIN
      v_parsed := (substring(v_schema_name from length('__earn_rate_dimensions:') + 1))::jsonb;
      v_dims := jsonb_build_object(
        'store_attribute_category_ids', COALESCE(v_parsed -> 'c', '[]'::jsonb),
        'include_store', jsonb_array_length(COALESCE(v_parsed -> 'c', '[]'::jsonb)) > 0,
        'include_tier', COALESCE((v_parsed ->> 't')::boolean, false),
        'include_persona', false,
        'include_product_category', false,
        'include_product_brand', false,
        'include_product_sku', false,
        'include_product_product', false
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;

  RETURN v_dims;
END;
$$;

CREATE OR REPLACE FUNCTION public.earn_rule_has_store_dimension(p_dimensions jsonb)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE((p_dimensions ->> 'include_store')::boolean, false)
      OR jsonb_array_length(COALESCE(p_dimensions -> 'store_attribute_category_ids', '[]'::jsonb)) > 0;
$$;

-- ---------------------------------------------------------------------------
-- 0b. Entity search
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.bff_search_earn_rule_entities(
  p_kind text,
  p_query text DEFAULT NULL,
  p_ids uuid[] DEFAULT NULL,
  p_attribute_ids uuid[] DEFAULT NULL,
  p_include_inactive boolean DEFAULT false,
  p_limit integer DEFAULT 20
)
RETURNS TABLE (
  id uuid,
  code text,
  label text,
  sublabel text,
  active boolean,
  meta jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_kind text := lower(trim(COALESCE(p_kind, '')));
  v_q text := trim(COALESCE(p_query, ''));
  v_lim int := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 100);
  v_hydrate boolean := p_ids IS NOT NULL AND cardinality(p_ids) > 0;
BEGIN
  v_merchant_id := public.get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN;
  END IF;

  IF NOT v_hydrate AND length(v_q) < 2 THEN
    RETURN;
  END IF;

  IF v_kind = 'store' THEN
    RETURN QUERY
    SELECT
      sm.id,
      sm.store_code::text,
      sm.store_name::text,
      sm.store_code::text,
      sm.active_status,
      jsonb_build_object('assignments', public.earn_rule_store_assignments_meta(sm.id, v_merchant_id))
    FROM public.store_master sm
    WHERE sm.merchant_id = v_merchant_id
      AND (p_include_inactive OR sm.active_status IS TRUE)
      AND (
        v_hydrate AND sm.id = ANY (p_ids)
        OR NOT v_hydrate AND (
          sm.store_name ILIKE '%' || v_q || '%'
          OR sm.store_code ILIKE '%' || v_q || '%'
        )
      )
      AND (
        p_attribute_ids IS NULL
        OR cardinality(p_attribute_ids) = 0
        OR NOT EXISTS (
          SELECT 1
          FROM unnest(p_attribute_ids) req(attr_id)
          WHERE NOT EXISTS (
            SELECT 1
            FROM public.store_attribute_assignments saa
            WHERE saa.merchant_id = v_merchant_id
              AND saa.store_id = sm.id
              AND (saa.attribute_id = req.attr_id OR saa.sub_attribute_id = req.attr_id)
          )
        )
      )
    ORDER BY
      CASE
        WHEN NOT v_hydrate AND sm.store_name ILIKE v_q || '%' THEN 0
        WHEN NOT v_hydrate AND sm.store_code ILIKE v_q || '%' THEN 1
        ELSE 2
      END,
      sm.store_name
    LIMIT v_lim;
    RETURN;
  END IF;

  IF v_kind = 'product' THEN
    RETURN QUERY
    SELECT
      pm.id,
      pm.product_code,
      pm.name,
      pm.product_code,
      TRUE,
      jsonb_build_object(
        'skus',
        COALESCE((
          SELECT jsonb_agg(
            jsonb_build_object('id', sk.id, 'sku_code', sk.sku_code, 'name', sk.name)
            ORDER BY sk.sku_code
          )
          FROM public.product_sku_master sk
          WHERE sk.product_id = pm.id
            AND sk.merchant_id = v_merchant_id
            AND (
              v_hydrate
              OR sk.name ILIKE '%' || v_q || '%'
              OR sk.sku_code ILIKE '%' || v_q || '%'
            )
        ), '[]'::jsonb)
      )
    FROM public.product_master pm
    WHERE pm.merchant_id = v_merchant_id
      AND (
        v_hydrate AND pm.id = ANY (p_ids)
        OR NOT v_hydrate AND (
          pm.name ILIKE '%' || v_q || '%'
          OR pm.product_code ILIKE '%' || v_q || '%'
          OR EXISTS (
            SELECT 1 FROM public.product_sku_master sk
            WHERE sk.product_id = pm.id
              AND sk.merchant_id = v_merchant_id
              AND (sk.name ILIKE '%' || v_q || '%' OR sk.sku_code ILIKE '%' || v_q || '%')
          )
        )
      )
    ORDER BY
      CASE
        WHEN NOT v_hydrate AND pm.name ILIKE v_q || '%' THEN 0
        WHEN NOT v_hydrate AND pm.product_code ILIKE v_q || '%' THEN 1
        ELSE 2
      END,
      pm.name
    LIMIT v_lim;
    RETURN;
  END IF;

  IF v_kind = 'sku' THEN
    RETURN QUERY
    SELECT
      sk.id,
      sk.sku_code,
      sk.name,
      pm.name,
      TRUE,
      jsonb_build_object(
        'product',
        jsonb_build_object('id', pm.id, 'name', pm.name)
      )
    FROM public.product_sku_master sk
    JOIN public.product_master pm ON pm.id = sk.product_id
    WHERE sk.merchant_id = v_merchant_id
      AND (
        v_hydrate AND sk.id = ANY (p_ids)
        OR NOT v_hydrate AND (
          sk.name ILIKE '%' || v_q || '%'
          OR sk.sku_code ILIKE '%' || v_q || '%'
        )
      )
    ORDER BY
      CASE
        WHEN NOT v_hydrate AND sk.name ILIKE v_q || '%' THEN 0
        WHEN NOT v_hydrate AND sk.sku_code ILIKE v_q || '%' THEN 1
        ELSE 2
      END,
      sk.name
    LIMIT v_lim;
    RETURN;
  END IF;

  IF v_kind = 'brand' THEN
    RETURN QUERY
    SELECT b.id, b.name, b.name, NULL::text, TRUE, '{}'::jsonb
    FROM public.product_brand_master b
    WHERE b.merchant_id = v_merchant_id
      AND (v_hydrate AND b.id = ANY (p_ids) OR NOT v_hydrate AND b.name ILIKE '%' || v_q || '%')
    ORDER BY CASE WHEN NOT v_hydrate AND b.name ILIKE v_q || '%' THEN 0 ELSE 1 END, b.name
    LIMIT v_lim;
    RETURN;
  END IF;

  IF v_kind = 'product_category' THEN
    RETURN QUERY
    SELECT c.id, c.name, c.name, NULL::text, TRUE, '{}'::jsonb
    FROM public.product_category_master c
    WHERE c.merchant_id = v_merchant_id
      AND (v_hydrate AND c.id = ANY (p_ids) OR NOT v_hydrate AND c.name ILIKE '%' || v_q || '%')
    ORDER BY CASE WHEN NOT v_hydrate AND c.name ILIKE v_q || '%' THEN 0 ELSE 1 END, c.name
    LIMIT v_lim;
    RETURN;
  END IF;

  IF v_kind = 'tier' THEN
    RETURN QUERY
    SELECT t.id, t.tier_name, t.tier_name, NULL::text, TRUE, '{}'::jsonb
    FROM public.tier_master t
    WHERE t.merchant_id = v_merchant_id
      AND (v_hydrate AND t.id = ANY (p_ids) OR NOT v_hydrate AND t.tier_name ILIKE '%' || v_q || '%')
    ORDER BY CASE WHEN NOT v_hydrate AND t.tier_name ILIKE v_q || '%' THEN 0 ELSE 1 END, t.tier_name
    LIMIT v_lim;
    RETURN;
  END IF;

  IF v_kind = 'persona' THEN
    RETURN QUERY
    SELECT p.id, p.persona_name, p.persona_name, NULL::text, p.active_status, '{}'::jsonb
    FROM public.persona_master p
    WHERE p.merchant_id = v_merchant_id
      AND (p_include_inactive OR p.active_status IS TRUE)
      AND (v_hydrate AND p.id = ANY (p_ids) OR NOT v_hydrate AND p.persona_name ILIKE '%' || v_q || '%')
    ORDER BY CASE WHEN NOT v_hydrate AND p.persona_name ILIKE v_q || '%' THEN 0 ELSE 1 END, p.persona_name
    LIMIT v_lim;
    RETURN;
  END IF;

  RETURN;
END;
$function$;

-- ---------------------------------------------------------------------------
-- 0c. Uncovered stores (paginated)
-- ---------------------------------------------------------------------------

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

  WITH uncovered AS (
    SELECT sm.id, sm.store_code, sm.store_name, sm.active_status
    FROM public.store_master sm
    WHERE sm.merchant_id = v_merchant_id
      AND sm.active_status IS TRUE
      AND (
        v_q = ''
        OR sm.store_name ILIKE '%' || v_q || '%'
        OR sm.store_code ILIKE '%' || v_q || '%'
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.earn_factor ef
        WHERE ef.merchant_id = v_merchant_id
          AND ef.earn_factor_group_id = v_group_id
          AND ef.active_status IS TRUE
          AND ef.earn_factor_type IN ('rate', 'multiplier')
          AND ef.earn_factor_amount IS NOT NULL
          AND public.earn_rule_factor_covers_store(ef.id, sm.id, v_merchant_id, v_cat_ids)
      )
  )
  SELECT COUNT(*)::int INTO v_total FROM uncovered;

  WITH uncovered AS (
    SELECT sm.id, sm.store_code, sm.store_name, sm.active_status
    FROM public.store_master sm
    WHERE sm.merchant_id = v_merchant_id
      AND sm.active_status IS TRUE
      AND (
        v_q = ''
        OR sm.store_name ILIKE '%' || v_q || '%'
        OR sm.store_code ILIKE '%' || v_q || '%'
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.earn_factor ef
        WHERE ef.merchant_id = v_merchant_id
          AND ef.earn_factor_group_id = v_group_id
          AND ef.active_status IS TRUE
          AND ef.earn_factor_type IN ('rate', 'multiplier')
          AND ef.earn_factor_amount IS NOT NULL
          AND public.earn_rule_factor_covers_store(ef.id, sm.id, v_merchant_id, v_cat_ids)
      )
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

-- ---------------------------------------------------------------------------
-- 0a. Rates tab envelope
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.bff_get_earn_rule_rates_details()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_advanced_enabled boolean;
  v_advanced_config jsonb;
  v_dims jsonb;
  v_group_id uuid;
  v_stackable boolean := true;
  v_hierarchy jsonb;
  v_rows jsonb := '[]'::jsonb;
  v_allowed_statuses text[] := ARRAY['completed']::text[];
  v_excluded_root jsonb := '[]'::jsonb;
  v_factor record;
  v_row jsonb;
  v_cat_sel jsonb;
  v_selections jsonb;
  v_cond record;
  v_member record;
  v_category_id uuid;
  v_attr_id uuid;
  v_store jsonb;
  v_tier jsonb;
  v_persona jsonb;
  v_brand jsonb;
  v_pcat jsonb;
  v_products jsonb;
  v_skus jsonb;
  v_excluded_row jsonb;
  v_unsupported int;
  v_timing jsonb;
  v_cat_ids uuid[];
  v_extra_cats uuid[] := ARRAY[]::uuid[];
  v_all_cats uuid[];
  v_basic jsonb;
  v_is_not_basic boolean;
BEGIN
  v_merchant_id := public.get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'No merchant context found');
  END IF;

  SELECT mm.advanced_earn_enabled, COALESCE(mm.advanced_earn_config, '{}'::jsonb)
  INTO v_advanced_enabled, v_advanced_config
  FROM public.merchant_master mm
  WHERE mm.id = v_merchant_id;

  v_dims := public.earn_rule_dimensions_from_merchant(v_merchant_id);
  v_hierarchy := public.get_store_attributes_hierarchy()::jsonb;

  v_basic := public.bff_get_basic_currency_config('points');
  v_is_not_basic := (v_basic ? 'mode' AND v_basic ->> 'mode' = 'not_basic');
  v_group_id := NULLIF(v_basic ->> 'earn_factor_group_id', '')::uuid;

  IF v_group_id IS NULL THEN
    SELECT ef.earn_factor_group_id INTO v_group_id
    FROM public.earn_factor ef
    WHERE ef.merchant_id = v_merchant_id
      AND ef.target_currency = 'points'::public.currency
      AND ef.target_entity_id IS NULL
    LIMIT 1;
  END IF;

  IF v_advanced_enabled IS TRUE THEN
    v_group_id := COALESCE(
      public.earn_rule_resolve_advanced_store_group_id(v_merchant_id),
      v_group_id
    );
  END IF;

  IF v_group_id IS NOT NULL THEN
    SELECT COALESCE(efg.stackable, true) INTO v_stackable
    FROM public.earn_factor_group efg
    WHERE efg.id = v_group_id;
  END IF;

  IF NOT v_advanced_enabled AND v_basic IS NOT NULL AND NOT v_is_not_basic THEN
    v_allowed_statuses := COALESCE(
      ARRAY(SELECT jsonb_array_elements_text(v_basic -> 'earn_rate' -> 'allowed_purchase_statuses')),
      ARRAY['completed']::text[]
    );
    v_excluded_root := COALESCE(v_basic -> 'earn_rate' -> 'excluded_products', '[]'::jsonb);
    v_stackable := COALESCE((v_basic -> 'multipliers' ->> 'stackable')::boolean, v_stackable);
  END IF;

  IF v_group_id IS NOT NULL THEN
    FOR v_factor IN
      SELECT ef.*
      FROM public.earn_factor ef
      WHERE ef.earn_factor_group_id = v_group_id
        AND ef.merchant_id = v_merchant_id
        AND ef.active_status IS TRUE
        AND (
          (v_advanced_enabled AND ef.earn_factor_type IN ('rate', 'multiplier'))
          OR (NOT v_advanced_enabled AND ef.earn_factor_type = 'rate')
        )
      ORDER BY ef.created_at
    LOOP
      v_selections := '{}'::jsonb;
      v_store := NULL;
      v_tier := NULL;
      v_persona := NULL;
      v_brand := NULL;
      v_pcat := NULL;
      v_products := '[]'::jsonb;
      v_skus := '[]'::jsonb;
      v_excluded_row := '[]'::jsonb;
      v_timing := NULL;
      v_unsupported := 0;

      IF v_factor.allowed_purchase_statuses IS NOT NULL
         AND cardinality(v_factor.allowed_purchase_statuses) > 0 THEN
        v_allowed_statuses := v_factor.allowed_purchase_statuses;
      END IF;

      IF v_factor.earn_conditions_group_id IS NOT NULL THEN
        SELECT COUNT(*)::int
        INTO v_unsupported
        FROM public.earn_conditions ec
        WHERE ec.group_id = v_factor.earn_conditions_group_id
          AND ec.merchant_id = v_merchant_id
          AND ec.exclude IS NOT TRUE
          AND ec.entity::text IN (
            'store_type', 'store_prop1', 'store_subprop1', 'store_prop2', 'store_subprop2',
            'store_prop3', 'store_subprop3', 'type', 'subtype'
          );

        FOR v_cond IN
          SELECT ec.*
          FROM public.earn_conditions ec
          WHERE ec.group_id = v_factor.earn_conditions_group_id
            AND ec.merchant_id = v_merchant_id
          ORDER BY ec.id
        LOOP
          IF v_cond.exclude IS TRUE THEN
            IF v_cond.entity::text IN (
              'product_sku', 'product_product', 'product_brand', 'product_category'
            ) THEN
              IF v_advanced_enabled THEN
                IF v_cond.entity::text = 'product_product' THEN
                  v_excluded_row := v_excluded_row || COALESCE((
                    SELECT jsonb_agg(
                      jsonb_build_object('id', pm.id, 'code', pm.product_code, 'name', pm.name)
                      ORDER BY pm.name
                    )
                    FROM public.product_master pm
                    WHERE pm.id = ANY (COALESCE(v_cond.entity_ids, ARRAY[]::uuid[]))
                  ), '[]'::jsonb);
                ELSIF v_cond.entity::text = 'product_sku' THEN
                  v_excluded_row := v_excluded_row || COALESCE((
                    SELECT jsonb_agg(
                      jsonb_build_object('id', sk.id, 'code', sk.sku_code, 'name', sk.name)
                      ORDER BY sk.name
                    )
                    FROM public.product_sku_master sk
                    WHERE sk.id = ANY (COALESCE(v_cond.entity_ids, ARRAY[]::uuid[]))
                  ), '[]'::jsonb);
                ELSIF v_cond.entity::text = 'product_brand' THEN
                  v_excluded_row := v_excluded_row || COALESCE((
                    SELECT jsonb_agg(
                      jsonb_build_object('id', b.id, 'code', b.name, 'name', b.name)
                      ORDER BY b.name
                    )
                    FROM public.product_brand_master b
                    WHERE b.id = ANY (COALESCE(v_cond.entity_ids, ARRAY[]::uuid[]))
                  ), '[]'::jsonb);
                ELSIF v_cond.entity::text = 'product_category' THEN
                  v_excluded_row := v_excluded_row || COALESCE((
                    SELECT jsonb_agg(
                      jsonb_build_object('id', c.id, 'code', c.name, 'name', c.name)
                      ORDER BY c.name
                    )
                    FROM public.product_category_master c
                    WHERE c.id = ANY (COALESCE(v_cond.entity_ids, ARRAY[]::uuid[]))
                  ), '[]'::jsonb);
                END IF;
              ELSE
                v_excluded_root := v_excluded_root || jsonb_build_array(
                  jsonb_build_object(
                    'condition_id', v_cond.id,
                    'entity', v_cond.entity::text,
                    'entity_ids', to_jsonb(COALESCE(v_cond.entity_ids, ARRAY[]::uuid[]))
                  )
                );
              END IF;
            END IF;
            CONTINUE;
          END IF;

          IF v_cond.entity_ids IS NULL OR cardinality(v_cond.entity_ids) = 0 THEN
            CONTINUE;
          END IF;

          IF v_cond.threshold_unit IS NOT NULL AND v_cond.min_threshold IS NOT NULL THEN
            NULL; -- captured on row below
          END IF;

          IF v_cond.entity = 'tier' THEN
            SELECT jsonb_build_object('id', tm.id, 'name', tm.tier_name)
            INTO v_tier
            FROM public.tier_master tm
            WHERE tm.id = v_cond.entity_ids[1];
            IF NOT v_advanced_enabled THEN
              v_dims := jsonb_set(v_dims, '{include_tier}', 'true'::jsonb, true);
            END IF;
          ELSIF v_cond.entity = 'persona' THEN
            SELECT jsonb_build_object('id', pm.id, 'name', pm.persona_name)
            INTO v_persona
            FROM public.persona_master pm
            WHERE pm.id = v_cond.entity_ids[1];
          ELSIF v_cond.entity = 'product_category' THEN
            SELECT jsonb_build_object('id', c.id, 'name', c.name)
            INTO v_pcat
            FROM public.product_category_master c
            WHERE c.id = v_cond.entity_ids[1];
          ELSIF v_cond.entity = 'product_brand' THEN
            SELECT jsonb_build_object('id', b.id, 'name', b.name)
            INTO v_brand
            FROM public.product_brand_master b
            WHERE b.id = v_cond.entity_ids[1];
          ELSIF v_cond.entity = 'product_product' THEN
            SELECT COALESCE(jsonb_agg(
              jsonb_build_object('id', pm.id, 'code', pm.product_code, 'name', pm.name)
              ORDER BY pm.name
            ), '[]'::jsonb)
            INTO v_products
            FROM public.product_master pm
            WHERE pm.id = ANY (v_cond.entity_ids);
          ELSIF v_cond.entity = 'product_sku' THEN
            SELECT COALESCE(jsonb_agg(
              jsonb_build_object('id', sk.id, 'code', sk.sku_code, 'name', sk.name)
              ORDER BY sk.name
            ), '[]'::jsonb)
            INTO v_skus
            FROM public.product_sku_master sk
            WHERE sk.id = ANY (v_cond.entity_ids);
          ELSIF v_cond.entity = 'store' THEN
            SELECT jsonb_build_object(
              'id', sm.id,
              'code', sm.store_code::text,
              'name', sm.store_name::text
            )
            INTO v_store
            FROM public.store_master sm
            WHERE sm.id = v_cond.entity_ids[1];

            FOR v_category_id IN
              SELECT jsonb_array_elements_text(COALESCE(v_dims -> 'store_attribute_category_ids', '[]'::jsonb))::uuid
            LOOP
              SELECT jsonb_build_object(
                'attribute_id', saa.attribute_id,
                'sub_attribute_id', saa.sub_attribute_id
              )
              INTO v_cat_sel
              FROM public.store_attribute_assignments saa
              WHERE saa.merchant_id = v_merchant_id
                AND saa.store_id = v_cond.entity_ids[1]
                AND saa.category_id = v_category_id
              LIMIT 1;
              v_selections := v_selections || jsonb_build_object(
                v_category_id::text,
                COALESCE(v_cat_sel, jsonb_build_object('attribute_id', NULL, 'sub_attribute_id', NULL))
              );
            END LOOP;
          ELSIF v_cond.entity = 'store_attribute_set' THEN
            SELECT m.attribute_id, m.sub_attribute_id, m.store_id
            INTO v_member
            FROM public.store_attribute_set_members m
            WHERE m.set_id = v_cond.entity_ids[1]
              AND m.is_deleted IS NOT TRUE
            LIMIT 1;

            IF v_member.store_id IS NOT NULL THEN
              SELECT jsonb_build_object(
                'id', sm.id,
                'code', sm.store_code::text,
                'name', sm.store_name::text
              )
              INTO v_store
              FROM public.store_master sm
              WHERE sm.id = v_member.store_id;
            ELSIF v_member.sub_attribute_id IS NOT NULL THEN
              SELECT sa.category_id, sa.id
              INTO v_category_id, v_attr_id
              FROM public.store_sub_attributes ssa
              JOIN public.store_attributes sa ON sa.id = ssa.attribute_id
              WHERE ssa.id = v_member.sub_attribute_id
                AND ssa.merchant_id = v_merchant_id
              LIMIT 1;
              IF v_category_id IS NOT NULL THEN
                v_selections := v_selections || jsonb_build_object(
                  v_category_id::text,
                  jsonb_build_object(
                    'attribute_id', v_attr_id,
                    'sub_attribute_id', v_member.sub_attribute_id
                  )
                );
                v_extra_cats := array_append(v_extra_cats, v_category_id);
              END IF;
            ELSIF v_member.attribute_id IS NOT NULL THEN
              SELECT sa.category_id
              INTO v_category_id
              FROM public.store_attributes sa
              WHERE sa.id = v_member.attribute_id
                AND sa.merchant_id = v_merchant_id
              LIMIT 1;
              IF v_category_id IS NOT NULL THEN
                v_selections := v_selections || jsonb_build_object(
                  v_category_id::text,
                  jsonb_build_object(
                    'attribute_id', v_member.attribute_id,
                    'sub_attribute_id', NULL
                  )
                );
                v_extra_cats := array_append(v_extra_cats, v_category_id);
              END IF;
            END IF;
          END IF;
        END LOOP;
      END IF;

      IF v_factor.has_time_conditions IS TRUE THEN
        SELECT jsonb_build_object(
          'day_of_week', tc.day_of_week,
          'hour_start', tc.hour_start,
          'hour_end', tc.hour_end
        )
        INTO v_timing
        FROM public.earn_factor_time_conditions tc
        WHERE tc.earn_factor_id = v_factor.id
        LIMIT 1;
      END IF;

      IF NOT v_advanced_enabled AND cardinality(v_extra_cats) > 0 THEN
        SELECT COALESCE(array_agg(DISTINCT x), ARRAY[]::uuid[])
        INTO v_all_cats
        FROM (
          SELECT unnest(v_extra_cats) AS x
          UNION
          SELECT jsonb_array_elements_text(COALESCE(v_dims -> 'store_attribute_category_ids', '[]'::jsonb))::uuid
        ) s;
        v_dims := jsonb_set(
          v_dims,
          '{store_attribute_category_ids}',
          to_jsonb(v_all_cats),
          true
        );
        v_dims := jsonb_set(
          v_dims,
          '{include_store}',
          to_jsonb(v_all_cats IS NOT NULL AND cardinality(v_all_cats) > 0),
          true
        );
      END IF;

      SELECT COALESCE(array_agg(x::uuid), ARRAY[]::uuid[])
      INTO v_cat_ids
      FROM jsonb_array_elements_text(COALESCE(v_dims -> 'store_attribute_category_ids', '[]'::jsonb)) x;

      FOREACH v_category_id IN ARRAY v_cat_ids LOOP
        IF v_selections ? v_category_id::text THEN
          CONTINUE;
        END IF;
        v_selections := v_selections || jsonb_build_object(
          v_category_id::text,
          jsonb_build_object('attribute_id', NULL, 'sub_attribute_id', NULL)
        );
      END LOOP;

      v_row := jsonb_build_object(
        'factor_id', v_factor.id,
        'factor_type', CASE WHEN v_factor.earn_factor_type = 'multiplier' THEN 'multiplier' ELSE 'rate' END,
        'amount', v_factor.earn_factor_amount,
        'store', v_store,
        'selections', v_selections,
        'tier', v_tier,
        'persona', v_persona,
        'brand', v_brand,
        'product_category', v_pcat,
        'products', v_products,
        'skus', v_skus,
        'excluded_products', v_excluded_row,
        'threshold_unit', (
          SELECT ec.threshold_unit
          FROM public.earn_conditions ec
          WHERE ec.group_id = v_factor.earn_conditions_group_id
            AND ec.merchant_id = v_merchant_id
            AND ec.threshold_unit IS NOT NULL
            AND ec.min_threshold IS NOT NULL
          ORDER BY ec.id DESC
          LIMIT 1
        ),
        'min_threshold', (
          SELECT ec.min_threshold
          FROM public.earn_conditions ec
          WHERE ec.group_id = v_factor.earn_conditions_group_id
            AND ec.merchant_id = v_merchant_id
            AND ec.threshold_unit IS NOT NULL
            AND ec.min_threshold IS NOT NULL
          ORDER BY ec.id DESC
          LIMIT 1
        ),
        'allowed_purchase_statuses', COALESCE(v_factor.allowed_purchase_statuses, v_allowed_statuses),
        'time_conditions', v_timing,
        'unsupported_conditions', v_unsupported
      );

      v_rows := v_rows || jsonb_build_array(v_row);
    END LOOP;
  END IF;

  IF jsonb_array_length(v_rows) = 0 AND v_basic IS NOT NULL AND NOT v_is_not_basic THEN
    IF COALESCE((v_basic -> 'earn_rate' ->> 'different_rate_per_tier')::boolean, false) THEN
      v_dims := jsonb_set(v_dims, '{include_tier}', 'true'::jsonb, true);
      SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
          'factor_id', r ->> 'factor_id',
          'factor_type', 'rate',
          'amount', (r ->> 'earn_factor_amount')::numeric,
          'store', NULL,
          'selections', '{}'::jsonb,
          'tier', jsonb_build_object('id', r ->> 'tier_id', 'name', r ->> 'tier_name'),
          'persona', NULL,
          'brand', NULL,
          'product_category', NULL,
          'products', '[]'::jsonb,
          'skus', '[]'::jsonb,
          'excluded_products', '[]'::jsonb,
          'threshold_unit', NULL,
          'min_threshold', NULL,
          'allowed_purchase_statuses', v_allowed_statuses,
          'time_conditions', NULL,
          'unsupported_conditions', 0
        )
      ), '[]'::jsonb)
      INTO v_rows
      FROM jsonb_array_elements(COALESCE(v_basic -> 'earn_rate' -> 'rates', '[]'::jsonb)) r;
    ELSIF v_basic -> 'earn_rate' -> 'single_rate' IS NOT NULL THEN
      v_rows := jsonb_build_array(jsonb_build_object(
        'factor_id', v_basic -> 'earn_rate' ->> 'single_rate_factor_id',
        'factor_type', 'rate',
        'amount', (v_basic -> 'earn_rate' ->> 'single_rate')::numeric,
        'store', NULL,
        'selections', '{}'::jsonb,
        'tier', NULL,
        'persona', NULL,
        'brand', NULL,
        'product_category', NULL,
        'products', '[]'::jsonb,
        'skus', '[]'::jsonb,
        'excluded_products', '[]'::jsonb,
        'threshold_unit', NULL,
        'min_threshold', NULL,
        'allowed_purchase_statuses', v_allowed_statuses,
        'time_conditions', NULL,
        'unsupported_conditions', 0
      ));
    END IF;
  END IF;

  IF jsonb_array_length(v_rows) = 0 THEN
    SELECT COALESCE(array_agg(x::uuid), ARRAY[]::uuid[])
    INTO v_cat_ids
    FROM jsonb_array_elements_text(COALESCE(v_dims -> 'store_attribute_category_ids', '[]'::jsonb)) x;
    v_selections := '{}'::jsonb;
    FOREACH v_category_id IN ARRAY v_cat_ids LOOP
      v_selections := v_selections || jsonb_build_object(
        v_category_id::text,
        jsonb_build_object('attribute_id', NULL, 'sub_attribute_id', NULL)
      );
    END LOOP;
    v_rows := jsonb_build_array(jsonb_build_object(
      'factor_id', NULL,
      'factor_type', 'rate',
      'amount', NULL,
      'store', NULL,
      'selections', v_selections,
      'tier', NULL,
      'persona', NULL,
      'brand', NULL,
      'product_category', NULL,
      'products', '[]'::jsonb,
      'skus', '[]'::jsonb,
      'excluded_products', '[]'::jsonb,
      'threshold_unit', NULL,
      'min_threshold', NULL,
      'allowed_purchase_statuses', v_allowed_statuses,
      'time_conditions', NULL,
      'unsupported_conditions', 0
    ));
  END IF;

  IF v_advanced_enabled THEN
    v_excluded_root := '[]'::jsonb;
  END IF;

  RETURN jsonb_build_object(
    'group_id', v_group_id,
    'advanced_enabled', COALESCE(v_advanced_enabled, false),
    'advanced_config', CASE WHEN v_advanced_enabled THEN v_advanced_config ELSE '{}'::jsonb END,
    'stackable', COALESCE(v_stackable, true),
    'dimensions', v_dims,
    'hierarchy', v_hierarchy,
    'rows', v_rows,
    'allowed_purchase_statuses', to_jsonb(v_allowed_statuses),
    'excluded_products', v_excluded_root
  );
END;
$function$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

REVOKE ALL ON FUNCTION public.earn_rule_store_assignment_matches(uuid, uuid, uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.earn_rule_row_covers_store(numeric, uuid, uuid[], jsonb, uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.earn_rule_store_assignments_meta(uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.earn_rule_resolve_advanced_store_group_id(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.earn_rule_factor_covers_store(uuid, uuid, uuid, uuid[]) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.earn_rule_dimensions_from_merchant(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.earn_rule_has_store_dimension(jsonb) FROM PUBLIC, anon;

REVOKE ALL ON FUNCTION public.bff_search_earn_rule_entities(text, text, uuid[], uuid[], boolean, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.bff_list_uncovered_stores(text, integer, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.bff_get_earn_rule_rates_details() FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.bff_search_earn_rule_entities(text, text, uuid[], uuid[], boolean, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bff_list_uncovered_stores(text, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bff_get_earn_rule_rates_details() TO authenticated;
