CREATE OR REPLACE FUNCTION public.bff_admin_list_assets(
  p_asset_type_code text DEFAULT 'CAR',
  p_status_filter text DEFAULT 'all',
  p_search text DEFAULT NULL,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_merchant_id uuid;
  v_type_id uuid;
  v_limit int;
  v_offset int;
  v_status text;
  v_search text;
  v_items jsonb;
  v_total int;
  v_total_asset int;
  v_total_active int;
  v_total_inactive int;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error('No merchant context', 'Unable to resolve merchant for this request.', 'NO_MERCHANT_CONTEXT');
  END IF;

  IF NOT check_admin_permission('asset', 'read') THEN
    RETURN fn_response_error('Forbidden', 'Insufficient permission to list assets.', 'FORBIDDEN');
  END IF;

  SELECT id INTO v_type_id
  FROM asset_type
  WHERE merchant_id = v_merchant_id
    AND upper(type_code) = upper(trim(COALESCE(p_asset_type_code, 'CAR')))
  LIMIT 1;

  v_limit := GREATEST(1, LEAST(COALESCE(p_limit, 50), 200));
  v_offset := GREATEST(0, COALESCE(p_offset, 0));
  v_status := lower(COALESCE(NULLIF(trim(p_status_filter), ''), 'all'));
  v_search := NULLIF(trim(p_search), '');

  SELECT
    count(*)::int,
    count(*) FILTER (WHERE lower(COALESCE(a.status, '')) = 'active')::int,
    count(*) FILTER (WHERE lower(COALESCE(a.status, '')) <> 'active')::int
  INTO v_total_asset, v_total_active, v_total_inactive
  FROM asset a
  WHERE a.merchant_id = v_merchant_id
    AND a.deleted_at IS NULL
    AND (v_type_id IS NULL OR a.asset_type_id = v_type_id);

  WITH filtered AS (
    SELECT
      a.id,
      a.created_at,
      a.updated_at,
      a.status,
      a.custom_fields,
      a.user_id,
      ua.firstname,
      ua.lastname,
      ua.tel,
      tm.tier_name,
      COALESCE(
        (SELECT bool_or(COALESCE(s.is_sync, false))
         FROM custom_crm_asset_sync s
         WHERE s.asset_id = a.id AND s.merchant_id = a.merchant_id),
        false
      ) AS is_sync,
      COALESCE(
        (SELECT max(s.updated_at)
         FROM custom_crm_asset_sync s
         WHERE s.asset_id = a.id AND s.merchant_id = a.merchant_id),
        a.created_at
      ) AS last_sync_at
    FROM asset a
    JOIN user_accounts ua ON ua.id = a.user_id
    LEFT JOIN tier_master tm ON tm.id = ua.tier_id
    WHERE a.merchant_id = v_merchant_id
      AND a.deleted_at IS NULL
      AND (v_type_id IS NULL OR a.asset_type_id = v_type_id)
      AND (
        v_status = 'all'
        OR (v_status = 'active' AND lower(COALESCE(a.status, '')) = 'active')
        OR (v_status = 'inactive' AND lower(COALESCE(a.status, '')) <> 'active')
      )
      AND (
        v_search IS NULL
        OR a.custom_fields->>'car_plate' ILIKE '%' || v_search || '%'
        OR a.custom_fields->>'car_plate_province' ILIKE '%' || v_search || '%'
        OR ua.firstname ILIKE '%' || v_search || '%'
        OR ua.lastname ILIKE '%' || v_search || '%'
        OR ua.tel ILIKE '%' || v_search || '%'
      )
  ),
  counted AS (SELECT count(*)::int AS c FROM filtered)
  SELECT
    (SELECT c FROM counted),
    COALESCE(jsonb_agg(to_jsonb(row_data) ORDER BY row_data.created_at DESC), '[]'::jsonb)
  INTO v_total, v_items
  FROM (
    SELECT
      f.id,
      f.created_at,
      f.updated_at,
      lower(COALESCE(f.status, 'inactive')) AS status_asset,
      f.custom_fields->>'car_plate' AS license_plate,
      f.custom_fields->>'car_plate_province' AS province,
      f.custom_fields->>'brand' AS car_brand,
      f.custom_fields->>'car_model' AS car_model,
      f.custom_fields->>'car_color' AS car_color,
      f.user_id,
      trim(concat_ws(' ', f.firstname, f.lastname)) AS member_name,
      f.tel AS member_tel,
      f.tier_name,
      CASE WHEN f.is_sync THEN 'synced' ELSE 'pending' END AS status_sync,
      f.last_sync_at
    FROM filtered f
    ORDER BY f.created_at DESC
    LIMIT v_limit OFFSET v_offset
  ) row_data;

  RETURN fn_response_success(
    'Asset list',
    'Assets loaded.',
    jsonb_build_object(
      'stats', jsonb_build_object(
        'total_asset', v_total_asset,
        'total_active', v_total_active,
        'total_inactive', v_total_inactive
      ),
      'total', COALESCE(v_total, 0),
      'limit', v_limit,
      'offset', v_offset,
      'items', COALESCE(v_items, '[]'::jsonb)
    )
  );
EXCEPTION WHEN OTHERS THEN
  RETURN fn_response_error('List failed', SQLERRM, 'ASSET_LIST_FAILED');
END;
$$;
