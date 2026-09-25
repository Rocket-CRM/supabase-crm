CREATE OR REPLACE FUNCTION public.bff_list_signup_codes(p_field_config_id uuid, p_status text DEFAULT 'all'::text, p_search text DEFAULT NULL::text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_language text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_lang text;
  v_merchant_id uuid;
  v_field_owner uuid;
  v_store_binding text;
  v_total int;
  v_items jsonb;
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'title', fn_admin_envelope_message('no_merchant_title', v_lang), 'description', null, 'data', null);
  END IF;

  IF NOT check_admin_permission('form', 'read') THEN
    RETURN jsonb_build_object('success', false, 'title', fn_admin_envelope_message('forbidden_title', v_lang), 'description', fn_admin_envelope_message('insufficient_permissions_desc', v_lang), 'data', jsonb_build_object('error_code', 'FORBIDDEN'));
  END IF;

  SELECT
    merchant_id,
    COALESCE(NULLIF(trim(config #>> '{external_code,store_binding}'), ''), 'off')
  INTO v_field_owner, v_store_binding
  FROM user_field_config WHERE id = p_field_config_id;

  IF v_field_owner IS NULL OR v_field_owner != v_merchant_id THEN
    RETURN jsonb_build_object('success', false, 'title', fn_admin_envelope_message('field_not_found_title', v_lang), 'description', null, 'data', jsonb_build_object('error_code', 'FIELD_NOT_FOUND'));
  END IF;

  WITH filtered AS (
    SELECT s.*
    FROM signup_codes s
    WHERE s.field_config_id = p_field_config_id
      AND s.merchant_id = v_merchant_id
      AND (
        p_search IS NULL
        OR s.code ILIKE '%' || p_search || '%'
        OR EXISTS (
          SELECT 1 FROM store_master sm
          WHERE sm.id = s.store_id
            AND (sm.store_code ILIKE '%' || p_search || '%' OR sm.store_name ILIKE '%' || p_search || '%')
        )
      )
      AND (
        p_status = 'all'
        OR (p_status = 'available' AND s.is_active = true AND s.consumed_count < s.max_consumers)
        OR (p_status = 'consumed' AND s.consumed_count >= s.max_consumers)
        OR (p_status = 'inactive' AND s.is_active = false)
      )
  )
  SELECT count(*) INTO v_total FROM filtered;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', s.id,
      'code', s.code,
      'metadata', s.metadata,
      'max_consumers', s.max_consumers,
      'consumed_count', s.consumed_count,
      'remaining_seats', s.max_consumers - s.consumed_count,
      'is_active', s.is_active,
      'created_at', s.created_at,
      'last_claimed_at', (SELECT max(claimed_at) FROM signup_code_claims WHERE code_id = s.id),
      'store_id', s.store_id,
      'store_code', sm.store_code,
      'store_name', sm.store_name
    )
    ORDER BY s.created_at DESC
  ), '[]'::jsonb)
  INTO v_items
  FROM (
    SELECT s.* FROM signup_codes s
    WHERE s.field_config_id = p_field_config_id
      AND s.merchant_id = v_merchant_id
      AND (
        p_search IS NULL
        OR s.code ILIKE '%' || p_search || '%'
        OR EXISTS (
          SELECT 1 FROM store_master sm2
          WHERE sm2.id = s.store_id
            AND (sm2.store_code ILIKE '%' || p_search || '%' OR sm2.store_name ILIKE '%' || p_search || '%')
        )
      )
      AND (
        p_status = 'all'
        OR (p_status = 'available' AND s.is_active = true AND s.consumed_count < s.max_consumers)
        OR (p_status = 'consumed' AND s.consumed_count >= s.max_consumers)
        OR (p_status = 'inactive' AND s.is_active = false)
      )
    ORDER BY s.created_at DESC
    LIMIT p_limit OFFSET p_offset
  ) s
  LEFT JOIN store_master sm ON sm.id = s.store_id;

  RETURN jsonb_build_object(
    'success', true,
    'title', null,
    'description', null,
    'data', jsonb_build_object(
      'total', v_total,
      'limit', p_limit,
      'offset', p_offset,
      'store_binding', v_store_binding,
      'items', v_items
    )
  );
END;
$function$;

DROP FUNCTION IF EXISTS public.bff_list_signup_codes(uuid, text, text, integer, integer);
