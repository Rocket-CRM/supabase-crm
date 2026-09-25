CREATE OR REPLACE FUNCTION public.bff_admin_get_user_asset_groups(
  p_user_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_merchant_id uuid;
  v_groups jsonb;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error('No merchant context', 'Unable to resolve merchant for this request.', 'NO_MERCHANT_CONTEXT');
  END IF;

  IF NOT (
    check_admin_permission('frontline_asset_group', 'read')
    OR check_admin_permission('asset', 'read')
  ) THEN
    RETURN fn_response_error('Forbidden', 'Insufficient permission to view asset groups.', 'FORBIDDEN');
  END IF;

  IF p_user_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM user_accounts ua
    WHERE ua.id = p_user_id AND ua.merchant_id = v_merchant_id AND ua.deleted_at IS NULL
  ) THEN
    RETURN fn_response_error('Customer not found', 'Customer does not belong to this merchant.', 'CUSTOMER_NOT_FOUND');
  END IF;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'asset_type_id', at.id,
      'asset_type_code', at.type_code,
      'asset_type_name', at.type_name,
      'display_name', CASE
        WHEN upper(at.type_code) = 'CAR' THEN 'Exclusive Parking'
        ELSE at.type_name
      END,
      'description', CASE
        WHEN upper(at.type_code) = 'CAR' THEN 'Register vehicles for parking privileges limited by member tier.'
        ELSE COALESCE(at.description, at.type_name)
      END
    )
    ORDER BY at.type_name
  ), '[]'::jsonb)
  INTO v_groups
  FROM asset_type at
  WHERE at.merchant_id = v_merchant_id
    AND EXISTS (
      SELECT 1 FROM asset_tier_config c
      WHERE c.merchant_id = v_merchant_id
        AND c.asset_type_id = at.id
        AND c.is_active
    );

  RETURN fn_response_success(
    'Asset groups',
    'Available asset groups for member.',
    jsonb_build_object('groups', v_groups)
  );
EXCEPTION WHEN OTHERS THEN
  RETURN fn_response_error('Load failed', SQLERRM, 'ASSET_GROUPS_FAILED');
END;
$$;
