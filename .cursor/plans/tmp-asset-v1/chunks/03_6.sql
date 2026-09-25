CREATE OR REPLACE FUNCTION public.bff_admin_sync_assets(
  p_asset_ids uuid[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_merchant_id uuid;
  v_id uuid;
  v_ok uuid[] := '{}';
  v_failed jsonb := '[]'::jsonb;
  v_exists boolean;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error('No merchant context', 'Unable to resolve merchant for this request.', 'NO_MERCHANT_CONTEXT');
  END IF;

  IF NOT (
    check_admin_permission('asset', 'update')
    OR check_admin_permission('asset', 'create')
  ) THEN
    RETURN fn_response_error('Forbidden', 'Insufficient permission to sync assets.', 'FORBIDDEN');
  END IF;

  IF p_asset_ids IS NULL OR coalesce(array_length(p_asset_ids, 1), 0) = 0 THEN
    RETURN fn_response_error('No assets selected', 'Select at least one asset to sync.', 'NO_SELECTION');
  END IF;

  FOREACH v_id IN ARRAY p_asset_ids
  LOOP
    SELECT EXISTS (
      SELECT 1 FROM asset a
      WHERE a.id = v_id AND a.merchant_id = v_merchant_id AND a.deleted_at IS NULL
    ) INTO v_exists;

    IF NOT v_exists THEN
      v_failed := v_failed || jsonb_build_array(jsonb_build_object('asset_id', v_id, 'code', 'NOT_FOUND'));
      CONTINUE;
    END IF;

    UPDATE custom_crm_asset_sync
    SET is_sync = true,
        updated_at = now()
    WHERE merchant_id = v_merchant_id
      AND asset_id = v_id;

    IF NOT FOUND THEN
      INSERT INTO custom_crm_asset_sync (
        id, mongo_id, merchant_id, asset_id, is_sync, created_at, updated_at
      ) VALUES (
        gen_random_uuid(),
        'local:' || v_id::text,
        v_merchant_id,
        v_id,
        true,
        now(),
        now()
      );
    END IF;

    v_ok := array_append(v_ok, v_id);
  END LOOP;

  RETURN fn_response_success(
    'Sync complete',
    'Local sync status updated. External parking sync is not enabled yet.',
    jsonb_build_object(
      'synced_asset_ids', to_jsonb(v_ok),
      'failed', v_failed,
      'mode', 'local_stub'
    )
  );
EXCEPTION WHEN OTHERS THEN
  RETURN fn_response_error('Sync failed', SQLERRM, 'ASSET_SYNC_FAILED');
END;
$$;

-- Downtier hook: enforce asset quotas after tier change
