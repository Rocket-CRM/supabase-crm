CREATE OR REPLACE FUNCTION public.bff_admin_get_user_assets(
  p_user_id uuid,
  p_asset_type_code text DEFAULT 'CAR'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_merchant_id uuid;
  v_type asset_type%ROWTYPE;
  v_sections jsonb;
  v_out jsonb := '[]'::jsonb;
  v_section jsonb;
  v_is_vip boolean;
  v_count int;
  v_active int;
  v_assets jsonb;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error('No merchant context', 'Unable to resolve merchant for this request.', 'NO_MERCHANT_CONTEXT');
  END IF;

  IF NOT (
    check_admin_permission('frontline_asset_group', 'read')
    OR check_admin_permission('asset', 'read')
  ) THEN
    RETURN fn_response_error('Forbidden', 'Insufficient permission to view assets.', 'FORBIDDEN');
  END IF;

  IF p_user_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM user_accounts ua
    WHERE ua.id = p_user_id AND ua.merchant_id = v_merchant_id AND ua.deleted_at IS NULL
  ) THEN
    RETURN fn_response_error('Customer not found', 'Customer does not belong to this merchant.', 'CUSTOMER_NOT_FOUND');
  END IF;

  SELECT * INTO v_type
  FROM asset_type
  WHERE merchant_id = v_merchant_id
    AND upper(type_code) = upper(trim(COALESCE(p_asset_type_code, 'CAR')))
  LIMIT 1;

  IF v_type.id IS NULL THEN
    RETURN fn_response_error('Asset type not found', 'Unknown asset type for this merchant.', 'ASSET_TYPE_NOT_FOUND');
  END IF;

  v_sections := fn_asset_resolve_sections(v_merchant_id, p_user_id, v_type.id);

  FOR v_section IN SELECT * FROM jsonb_array_elements(v_sections)
  LOOP
    v_is_vip := COALESCE((v_section->>'is_vip')::boolean, false);

    SELECT count(*)::int,
           count(*) FILTER (WHERE lower(COALESCE(a.status, '')) = 'active')::int
    INTO v_count, v_active
    FROM asset a
    LEFT JOIN asset_tier_config c ON c.id = a.asset_tier_config_id
    WHERE a.merchant_id = v_merchant_id
      AND a.user_id = p_user_id
      AND a.asset_type_id = v_type.id
      AND a.deleted_at IS NULL
      AND (
        (v_is_vip AND fn_asset_config_is_vip(c.tags))
        OR (NOT v_is_vip AND (c.id IS NULL OR NOT fn_asset_config_is_vip(c.tags)))
      );

    SELECT COALESCE(jsonb_agg(
      jsonb_build_object(
        'id', a.id,
        'name', a.name,
        'status', lower(COALESCE(a.status, 'inactive')),
        'custom_fields', COALESCE(a.custom_fields, '{}'::jsonb),
        'asset_tier_config_id', a.asset_tier_config_id,
        'created_at', a.created_at,
        'updated_at', a.updated_at,
        'can_edit', lower(COALESCE(a.status, '')) = 'active'
      )
      ORDER BY a.created_at DESC NULLS LAST
    ), '[]'::jsonb)
    INTO v_assets
    FROM asset a
    LEFT JOIN asset_tier_config c ON c.id = a.asset_tier_config_id
    WHERE a.merchant_id = v_merchant_id
      AND a.user_id = p_user_id
      AND a.asset_type_id = v_type.id
      AND a.deleted_at IS NULL
      AND (
        (v_is_vip AND fn_asset_config_is_vip(c.tags))
        OR (NOT v_is_vip AND (c.id IS NULL OR NOT fn_asset_config_is_vip(c.tags)))
      );

    v_out := v_out || jsonb_build_array(
      v_section || jsonb_build_object(
        'count', v_count,
        'active_count', v_active,
        'can_add', v_count < COALESCE((v_section->>'limit')::int, 0),
        'assets', v_assets
      )
    );
  END LOOP;

  RETURN fn_response_success(
    'User assets',
    'Member assets loaded.',
    jsonb_build_object(
      'asset_type_code', v_type.type_code,
      'asset_type_name', v_type.type_name,
      'display_name', CASE WHEN upper(v_type.type_code) = 'CAR' THEN 'Exclusive Parking' ELSE v_type.type_name END,
      'sections', v_out
    )
  );
EXCEPTION WHEN OTHERS THEN
  RETURN fn_response_error('Load failed', SQLERRM, 'USER_ASSETS_FAILED');
END;
$$;
