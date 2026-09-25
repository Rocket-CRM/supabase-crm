CREATE OR REPLACE FUNCTION public.bff_admin_set_user_asset_status(
  p_user_id uuid,
  p_asset_id uuid,
  p_status text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_merchant_id uuid;
  v_asset asset%ROWTYPE;
  v_status text;
  v_is_vip boolean;
  v_sections jsonb;
  v_section jsonb;
  v_limit int;
  v_active_count int;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error('No merchant context', 'Unable to resolve merchant for this request.', 'NO_MERCHANT_CONTEXT');
  END IF;

  IF NOT (
    check_admin_permission('frontline_asset_group', 'update')
    OR check_admin_permission('asset', 'update')
  ) THEN
    RETURN fn_response_error('Forbidden', 'Insufficient permission to update asset status.', 'FORBIDDEN');
  END IF;

  v_status := lower(trim(p_status));
  IF v_status NOT IN ('active', 'inactive') THEN
    RETURN fn_response_error('Invalid status', 'Status must be active or inactive.', 'INVALID_STATUS');
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

  IF lower(COALESCE(v_asset.status, '')) = v_status THEN
    RETURN fn_response_success('No change', 'Asset already in requested status.', jsonb_build_object('asset_id', v_asset.id, 'status', v_status));
  END IF;

  IF v_status = 'active' THEN
    SELECT fn_asset_config_is_vip(c.tags) INTO v_is_vip
    FROM asset_tier_config c
    WHERE c.id = v_asset.asset_tier_config_id;

    v_is_vip := COALESCE(v_is_vip, false);
    v_sections := fn_asset_resolve_sections(v_merchant_id, p_user_id, v_asset.asset_type_id);

    SELECT s INTO v_section
    FROM jsonb_array_elements(v_sections) s
    WHERE COALESCE((s->>'is_vip')::boolean, false) = v_is_vip
    LIMIT 1;

    v_limit := COALESCE((v_section->>'limit')::int, 0);

    SELECT count(*)::int INTO v_active_count
    FROM asset a
    LEFT JOIN asset_tier_config c ON c.id = a.asset_tier_config_id
    WHERE a.merchant_id = v_merchant_id
      AND a.user_id = p_user_id
      AND a.asset_type_id = v_asset.asset_type_id
      AND a.deleted_at IS NULL
      AND lower(COALESCE(a.status, '')) = 'active'
      AND a.id <> v_asset.id
      AND (
        (v_is_vip AND fn_asset_config_is_vip(c.tags))
        OR (NOT v_is_vip AND (c.id IS NULL OR NOT fn_asset_config_is_vip(c.tags)))
      );

    IF v_active_count + 1 > v_limit THEN
      RETURN fn_response_error(
        'Quota exceeded',
        'Cannot activate: active assets would exceed the current quota. Inactivate another asset first.',
        'QUOTA_EXCEEDED',
        jsonb_build_object('active_count', v_active_count, 'limit', v_limit)
      );
    END IF;
  END IF;

  UPDATE asset
  SET status = v_status,
      updated_at = now()
  WHERE id = v_asset.id
  RETURNING * INTO v_asset;

  PERFORM fn_asset_mark_sync_pending(v_merchant_id, v_asset.id);

  RETURN fn_response_success(
    'Status updated',
    'Asset status updated.',
    jsonb_build_object('asset_id', v_asset.id, 'status', v_asset.status)
  );
EXCEPTION WHEN OTHERS THEN
  RETURN fn_response_error('Status update failed', SQLERRM, 'ASSET_STATUS_FAILED');
END;
$$;
