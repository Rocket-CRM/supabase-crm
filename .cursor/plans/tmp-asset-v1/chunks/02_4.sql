CREATE OR REPLACE FUNCTION public.bff_admin_delete_user_asset(
  p_user_id uuid,
  p_asset_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_merchant_id uuid;
  v_asset asset%ROWTYPE;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error('No merchant context', 'Unable to resolve merchant for this request.', 'NO_MERCHANT_CONTEXT');
  END IF;

  IF NOT (
    check_admin_permission('frontline_asset_group', 'delete')
    OR check_admin_permission('asset', 'delete')
    OR check_admin_permission('frontline_asset_group', 'update')
    OR check_admin_permission('asset', 'update')
  ) THEN
    RETURN fn_response_error('Forbidden', 'Insufficient permission to delete assets.', 'FORBIDDEN');
  END IF;

  SELECT * INTO v_asset
  FROM asset
  WHERE id = p_asset_id
    AND merchant_id = v_merchant_id
    AND user_id = p_user_id
    AND deleted_at IS NULL;

  IF v_asset.id IS NULL THEN
    RETURN fn_response_error('Asset not found', 'Asset does not exist for this member.', 'ASSET_NOT_FOUND');
  END IF;

  UPDATE asset
  SET deleted_at = now(),
      updated_at = now(),
      status = CASE WHEN lower(COALESCE(status, '')) = 'active' THEN 'inactive' ELSE status END
  WHERE id = v_asset.id;

  PERFORM fn_asset_mark_sync_pending(v_merchant_id, v_asset.id);

  RETURN fn_response_success(
    'Asset deleted',
    'Asset soft-deleted.',
    jsonb_build_object('asset_id', v_asset.id)
  );
EXCEPTION WHEN OTHERS THEN
  RETURN fn_response_error('Delete failed', SQLERRM, 'ASSET_DELETE_FAILED');
END;
$$;
