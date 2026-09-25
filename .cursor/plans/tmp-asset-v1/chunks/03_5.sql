CREATE OR REPLACE FUNCTION public.bff_admin_get_asset(
  p_asset_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_merchant_id uuid;
  v_row jsonb;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error('No merchant context', 'Unable to resolve merchant for this request.', 'NO_MERCHANT_CONTEXT');
  END IF;

  IF NOT (
    check_admin_permission('asset', 'read')
    OR check_admin_permission('frontline_asset_group', 'read')
  ) THEN
    RETURN fn_response_error('Forbidden', 'Insufficient permission to view asset detail.', 'FORBIDDEN');
  END IF;

  SELECT jsonb_build_object(
    'id', a.id,
    'status_asset', lower(COALESCE(a.status, 'inactive')),
    'license_plate', a.custom_fields->>'car_plate',
    'province', a.custom_fields->>'car_plate_province',
    'car_brand', a.custom_fields->>'brand',
    'car_model', a.custom_fields->>'car_model',
    'car_color', a.custom_fields->>'car_color',
    'custom_fields', a.custom_fields,
    'created_at', a.created_at,
    'updated_at', a.updated_at,
    'member', jsonb_build_object(
      'user_id', ua.id,
      'member_name', trim(concat_ws(' ', ua.firstname, ua.lastname)),
      'tel', ua.tel,
      'tier_name', tm.tier_name
    ),
    'status_sync', CASE
      WHEN EXISTS (
        SELECT 1 FROM custom_crm_asset_sync s
        WHERE s.asset_id = a.id AND s.merchant_id = a.merchant_id AND COALESCE(s.is_sync, false)
      ) THEN 'synced' ELSE 'pending'
    END,
    'last_sync_at', COALESCE(
      (SELECT max(s.updated_at) FROM custom_crm_asset_sync s
       WHERE s.asset_id = a.id AND s.merchant_id = a.merchant_id),
      a.created_at
    )
  )
  INTO v_row
  FROM asset a
  JOIN user_accounts ua ON ua.id = a.user_id
  LEFT JOIN tier_master tm ON tm.id = ua.tier_id
  WHERE a.id = p_asset_id
    AND a.merchant_id = v_merchant_id
    AND a.deleted_at IS NULL;

  IF v_row IS NULL THEN
    RETURN fn_response_error('Asset not found', 'Asset not found.', 'ASSET_NOT_FOUND');
  END IF;

  RETURN fn_response_success('Asset detail', 'Asset loaded.', jsonb_build_object('asset', v_row));
EXCEPTION WHEN OTHERS THEN
  RETURN fn_response_error('Load failed', SQLERRM, 'ASSET_DETAIL_FAILED');
END;
$$;
