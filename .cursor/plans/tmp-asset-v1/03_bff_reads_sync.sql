-- Asset v1 read BFFs + sync stub + downtier hook on apply_tier_change

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
CREATE OR REPLACE FUNCTION public.apply_tier_change(
  p_user_id uuid,
  p_merchant_id uuid,
  p_to_tier_id uuid,
  p_change_type text DEFAULT 'upgrade'::text,
  p_pending_id uuid DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_current_tier_id uuid;
  v_user_type public.user_type;
  v_maintain_deadline date;
  v_maintain_window_type public.tier_evaluation_window_type;
  v_asset_result jsonb;
BEGIN
  IF p_change_type NOT IN ('upgrade', 'downgrade', 'assign_entry', 'manual') THEN
    RAISE EXCEPTION 'invalid tier change type: %', p_change_type;
  END IF;

  SELECT ua.tier_id, ua.user_type
  INTO v_current_tier_id, v_user_type
  FROM public.user_accounts ua
  WHERE ua.id = p_user_id AND ua.merchant_id = p_merchant_id;

  SELECT cmd.deadline, cmd.window_type
  INTO v_maintain_deadline, v_maintain_window_type
  FROM public.calculate_maintain_deadline(p_merchant_id, v_user_type, CURRENT_DATE) cmd;

  PERFORM public.chokepoint_post_user_event(
    p_event_type := 'update',
    p_merchant_id := p_merchant_id,
    p_user_id := p_user_id,
    p_changes := jsonb_build_object('tier_id', p_to_tier_id),
    p_metadata := jsonb_build_object(
      'tier_change_type', p_change_type,
      'tier_change_reason', format('Tier %s applied', p_change_type)
    )
  );

  INSERT INTO public.tier_evaluation_tracking (
    user_id, merchant_id, tier_achieved_at, maintain_deadline,
    maintain_window_type, updated_at
  ) VALUES (
    p_user_id, p_merchant_id, NOW(), v_maintain_deadline,
    v_maintain_window_type, NOW()
  )
  ON CONFLICT (user_id, merchant_id) DO UPDATE SET
    tier_achieved_at = NOW(),
    maintain_deadline = EXCLUDED.maintain_deadline,
    maintain_window_type = EXCLUDED.maintain_window_type,
    updated_at = NOW();

  PERFORM public.ensure_tier_progress(p_user_id, p_merchant_id);

  DELETE FROM public.tier_pending_upgrades
  WHERE user_id = p_user_id AND merchant_id = p_merchant_id;

  -- After tier is applied, shrink active assets to new quotas (FIFO)
  IF p_change_type IN ('downgrade', 'manual', 'assign_entry') THEN
    v_asset_result := public.fn_asset_enforce_quota_after_tier_change(p_merchant_id, p_user_id);
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'user_id', p_user_id,
    'change_type', p_change_type,
    'from_tier_id', v_current_tier_id,
    'to_tier_id', p_to_tier_id,
    'maintain_deadline', v_maintain_deadline,
    'asset_quota_enforcement', v_asset_result
  );
END;
$function$;
