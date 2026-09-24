-- Allow browsing earn-rule entity pickers without typing (first page on empty query).

DROP FUNCTION IF EXISTS public.bff_search_earn_rule_entities(text, text, uuid[], uuid[], boolean, integer);

CREATE OR REPLACE FUNCTION public.bff_search_earn_rule_entities(
  p_kind text,
  p_query text DEFAULT NULL,
  p_ids uuid[] DEFAULT NULL,
  p_attribute_ids uuid[] DEFAULT NULL,
  p_include_inactive boolean DEFAULT false,
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0
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
  v_off int := GREATEST(COALESCE(p_offset, 0), 0);
  v_hydrate boolean := p_ids IS NOT NULL AND cardinality(p_ids) > 0;
BEGIN
  v_merchant_id := public.get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN;
  END IF;

  IF NOT v_hydrate AND length(v_q) < 2 AND length(v_q) > 0 THEN
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
          length(v_q) = 0
          OR sm.store_name ILIKE '%' || v_q || '%'
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
        WHEN NOT v_hydrate AND length(v_q) > 0 AND sm.store_name ILIKE v_q || '%' THEN 0
        WHEN NOT v_hydrate AND length(v_q) > 0 AND sm.store_code ILIKE v_q || '%' THEN 1
        ELSE 2
      END,
      sm.store_name
    LIMIT v_lim
    OFFSET v_off;
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
              OR length(v_q) = 0
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
          length(v_q) = 0
          OR pm.name ILIKE '%' || v_q || '%'
          OR pm.product_code ILIKE '%' || v_q || '%'
          OR EXISTS (
            SELECT 1 FROM public.product_sku_master sk
            WHERE sk.product_id = pm.id
              AND sk.merchant_id = v_merchant_id
              AND (length(v_q) = 0 OR sk.name ILIKE '%' || v_q || '%' OR sk.sku_code ILIKE '%' || v_q || '%')
          )
        )
      )
    ORDER BY
      CASE
        WHEN NOT v_hydrate AND length(v_q) > 0 AND pm.name ILIKE v_q || '%' THEN 0
        WHEN NOT v_hydrate AND length(v_q) > 0 AND pm.product_code ILIKE v_q || '%' THEN 1
        ELSE 2
      END,
      pm.name
    LIMIT v_lim
    OFFSET v_off;
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
          length(v_q) = 0
          OR sk.name ILIKE '%' || v_q || '%'
          OR sk.sku_code ILIKE '%' || v_q || '%'
        )
      )
    ORDER BY
      CASE
        WHEN NOT v_hydrate AND length(v_q) > 0 AND sk.name ILIKE v_q || '%' THEN 0
        WHEN NOT v_hydrate AND length(v_q) > 0 AND sk.sku_code ILIKE v_q || '%' THEN 1
        ELSE 2
      END,
      sk.name
    LIMIT v_lim
    OFFSET v_off;
    RETURN;
  END IF;

  IF v_kind = 'brand' THEN
    RETURN QUERY
    SELECT b.id, b.name, b.name, NULL::text, TRUE, '{}'::jsonb
    FROM public.product_brand_master b
    WHERE b.merchant_id = v_merchant_id
      AND (
        v_hydrate AND b.id = ANY (p_ids)
        OR NOT v_hydrate AND (length(v_q) = 0 OR b.name ILIKE '%' || v_q || '%')
      )
    ORDER BY CASE WHEN NOT v_hydrate AND length(v_q) > 0 AND b.name ILIKE v_q || '%' THEN 0 ELSE 1 END, b.name
    LIMIT v_lim
    OFFSET v_off;
    RETURN;
  END IF;

  IF v_kind = 'product_category' THEN
    RETURN QUERY
    SELECT c.id, c.name, c.name, NULL::text, TRUE, '{}'::jsonb
    FROM public.product_category_master c
    WHERE c.merchant_id = v_merchant_id
      AND (
        v_hydrate AND c.id = ANY (p_ids)
        OR NOT v_hydrate AND (length(v_q) = 0 OR c.name ILIKE '%' || v_q || '%')
      )
    ORDER BY CASE WHEN NOT v_hydrate AND length(v_q) > 0 AND c.name ILIKE v_q || '%' THEN 0 ELSE 1 END, c.name
    LIMIT v_lim
    OFFSET v_off;
    RETURN;
  END IF;

  IF v_kind = 'tier' THEN
    RETURN QUERY
    SELECT t.id, t.tier_name, t.tier_name, NULL::text, TRUE, '{}'::jsonb
    FROM public.tier_master t
    WHERE t.merchant_id = v_merchant_id
      AND (
        v_hydrate AND t.id = ANY (p_ids)
        OR NOT v_hydrate AND (length(v_q) = 0 OR t.tier_name ILIKE '%' || v_q || '%')
      )
    ORDER BY CASE WHEN NOT v_hydrate AND length(v_q) > 0 AND t.tier_name ILIKE v_q || '%' THEN 0 ELSE 1 END, t.tier_name
    LIMIT v_lim
    OFFSET v_off;
    RETURN;
  END IF;

  IF v_kind = 'persona' THEN
    RETURN QUERY
    SELECT p.id, p.persona_name, p.persona_name, NULL::text, p.active_status, '{}'::jsonb
    FROM public.persona_master p
    WHERE p.merchant_id = v_merchant_id
      AND (p_include_inactive OR p.active_status IS TRUE)
      AND (
        v_hydrate AND p.id = ANY (p_ids)
        OR NOT v_hydrate AND (length(v_q) = 0 OR p.persona_name ILIKE '%' || v_q || '%')
      )
    ORDER BY CASE WHEN NOT v_hydrate AND length(v_q) > 0 AND p.persona_name ILIKE v_q || '%' THEN 0 ELSE 1 END, p.persona_name
    LIMIT v_lim
    OFFSET v_off;
    RETURN;
  END IF;

  RETURN;
END;
$function$;

REVOKE ALL ON FUNCTION public.bff_search_earn_rule_entities(text, text, uuid[], uuid[], boolean, integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.bff_search_earn_rule_entities(text, text, uuid[], uuid[], boolean, integer, integer) TO authenticated;
