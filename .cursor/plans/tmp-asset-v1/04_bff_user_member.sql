-- Member-facing Asset BFFs (loyalty app JWT). Mirror admin rules; no p_user_id/p_merchant_id.

CREATE OR REPLACE FUNCTION public.fn_asset_resolve_auth_member()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_auth_uid uuid;
  v_merchant_hint uuid;
  v_user_id uuid;
  v_merchant_id uuid;
BEGIN
  v_auth_uid := get_current_user_id();
  IF v_auth_uid IS NULL THEN
    RETURN jsonb_build_object(
      'ok', false,
      'title', 'Unauthenticated',
      'description', 'No authenticated user context',
      'code', 'UNAUTHENTICATED'
    );
  END IF;

  -- Optional merchant hint from session/header (loyalty app often sends both)
  BEGIN
    v_merchant_hint := get_current_merchant_id();
  EXCEPTION WHEN OTHERS THEN
    v_merchant_hint := NULL;
  END;

  SELECT ua.id, ua.merchant_id
  INTO v_user_id, v_merchant_id
  FROM user_accounts ua
  WHERE ua.deleted_at IS NULL
    AND ua.is_active IS NOT FALSE
    AND (ua.id = v_auth_uid OR ua.auth_user_id = v_auth_uid)
    AND (v_merchant_hint IS NULL OR ua.merchant_id = v_merchant_hint)
  ORDER BY
    CASE WHEN v_merchant_hint IS NOT NULL AND ua.merchant_id = v_merchant_hint THEN 0 ELSE 1 END,
    ua.created_at NULLS LAST
  LIMIT 1;

  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'ok', false,
      'title', 'User not found',
      'description', 'No user account is linked to this authenticated user',
      'code', 'USER_NOT_FOUND'
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'user_id', v_user_id,
    'merchant_id', v_merchant_id
  );
END;
$function$;

COMMENT ON FUNCTION public.fn_asset_resolve_auth_member() IS
  'Resolve loyalty member user_accounts.id + merchant_id from get_current_user_id() (header id or auth_user_id).';

CREATE OR REPLACE FUNCTION public.bff_user_get_assets(
  p_asset_type_code text DEFAULT 'CAR'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_auth jsonb;
  v_user_id uuid;
  v_merchant_id uuid;
  v_type asset_type%ROWTYPE;
  v_sections jsonb;
  v_out jsonb := '[]'::jsonb;
  v_section jsonb;
  v_is_vip boolean;
  v_count int;
  v_active int;
  v_assets jsonb;
  v_has_vip boolean;
BEGIN
  v_auth := fn_asset_resolve_auth_member();
  IF NOT COALESCE((v_auth->>'ok')::boolean, false) THEN
    RETURN fn_response_error(
      COALESCE(v_auth->>'title', 'Auth failed'),
      COALESCE(v_auth->>'description', 'Unable to resolve member.'),
      COALESCE(v_auth->>'code', 'AUTH_FAILED')
    );
  END IF;
  v_user_id := (v_auth->>'user_id')::uuid;
  v_merchant_id := (v_auth->>'merchant_id')::uuid;

  SELECT * INTO v_type
  FROM asset_type
  WHERE merchant_id = v_merchant_id
    AND upper(type_code) = upper(trim(COALESCE(p_asset_type_code, 'CAR')))
  LIMIT 1;

  IF v_type.id IS NULL THEN
    RETURN fn_response_error('Asset type not found', 'Unknown asset type for this merchant.', 'ASSET_TYPE_NOT_FOUND');
  END IF;

  v_has_vip := fn_asset_user_has_vip(v_merchant_id, v_user_id);
  v_sections := fn_asset_resolve_sections(v_merchant_id, v_user_id, v_type.id);

  FOR v_section IN SELECT * FROM jsonb_array_elements(v_sections)
  LOOP
    v_is_vip := COALESCE((v_section->>'is_vip')::boolean, false);

    SELECT count(*)::int,
           count(*) FILTER (WHERE lower(COALESCE(a.status, '')) = 'active')::int
    INTO v_count, v_active
    FROM asset a
    LEFT JOIN asset_tier_config c ON c.id = a.asset_tier_config_id
    WHERE a.merchant_id = v_merchant_id
      AND a.user_id = v_user_id
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
      AND a.user_id = v_user_id
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
      'has_vip', v_has_vip,
      'sections', v_out
    )
  );
EXCEPTION WHEN OTHERS THEN
  RETURN fn_response_error('Load failed', SQLERRM, 'USER_ASSETS_FAILED');
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_user_upsert_asset(
  p_asset_type_code text,
  p_custom_fields jsonb,
  p_asset_id uuid DEFAULT NULL::uuid,
  p_section_key text DEFAULT 'general'::text,
  p_name text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_auth jsonb;
  v_user_id uuid;
  v_merchant_id uuid;
  v_type asset_type%ROWTYPE;
  v_sections jsonb;
  v_section jsonb;
  v_config_id uuid;
  v_limit int;
  v_count int;
  v_plate text;
  v_uniq jsonb;
  v_asset asset%ROWTYPE;
  v_is_vip_section boolean;
  v_name text;
  v_field jsonb;
  v_slug text;
  v_val text;
BEGIN
  v_auth := fn_asset_resolve_auth_member();
  IF NOT COALESCE((v_auth->>'ok')::boolean, false) THEN
    RETURN fn_response_error(
      COALESCE(v_auth->>'title', 'Auth failed'),
      COALESCE(v_auth->>'description', 'Unable to resolve member.'),
      COALESCE(v_auth->>'code', 'AUTH_FAILED')
    );
  END IF;
  v_user_id := (v_auth->>'user_id')::uuid;
  v_merchant_id := (v_auth->>'merchant_id')::uuid;

  SELECT * INTO v_type
  FROM asset_type
  WHERE merchant_id = v_merchant_id
    AND upper(type_code) = upper(trim(p_asset_type_code))
  LIMIT 1;

  IF v_type.id IS NULL THEN
    RETURN fn_response_error('Asset type not found', 'Unknown asset type for this merchant.', 'ASSET_TYPE_NOT_FOUND');
  END IF;

  v_sections := fn_asset_resolve_sections(v_merchant_id, v_user_id, v_type.id);
  SELECT s INTO v_section
  FROM jsonb_array_elements(v_sections) s
  WHERE s->>'section_key' = COALESCE(NULLIF(trim(p_section_key), ''), 'general')
  LIMIT 1;

  IF v_section IS NULL THEN
    RETURN fn_response_error('Section unavailable', 'Requested asset section is not available for this member.', 'SECTION_UNAVAILABLE');
  END IF;

  v_config_id := NULLIF(v_section->>'asset_tier_config_id', '')::uuid;
  v_limit := COALESCE((v_section->>'limit')::int, 0);
  v_is_vip_section := COALESCE((v_section->>'is_vip')::boolean, false);

  IF jsonb_typeof(v_section->'field_schema') = 'array' THEN
    FOR v_field IN SELECT * FROM jsonb_array_elements(v_section->'field_schema')
    LOOP
      v_slug := v_field->>'slug';
      IF v_slug IS NULL THEN CONTINUE; END IF;
      v_val := NULLIF(trim(COALESCE(p_custom_fields->>v_slug, '')), '');
      IF v_val IS NULL THEN
        RETURN fn_response_error(
          'Validation failed',
          format('Field %s is required.', COALESCE(v_field->>'name', v_slug)),
          'FIELD_REQUIRED',
          jsonb_build_object('field', v_slug)
        );
      END IF;
    END LOOP;
  END IF;

  v_plate := p_custom_fields->>'car_plate';
  v_uniq := fn_asset_assert_plate_unique(v_merchant_id, v_plate, p_asset_id);
  IF COALESCE((v_uniq->>'ok')::boolean, false) IS NOT TRUE THEN
    RETURN fn_response_error(
      'Duplicate plate',
      COALESCE(v_uniq->>'message', 'ทะเบียนรถนี้มีการลงทะเบียนแล้ว กรุณาตรวจสอบอีกครั้ง'),
      COALESCE(v_uniq->>'code', 'PLATE_DUPLICATE')
    );
  END IF;

  v_name := COALESCE(
    NULLIF(trim(p_name), ''),
    NULLIF(trim(v_plate), ''),
    v_type.type_name
  );

  IF p_asset_id IS NULL THEN
    SELECT count(*)::int INTO v_count
    FROM asset a
    LEFT JOIN asset_tier_config c ON c.id = a.asset_tier_config_id
    WHERE a.merchant_id = v_merchant_id
      AND a.user_id = v_user_id
      AND a.asset_type_id = v_type.id
      AND a.deleted_at IS NULL
      AND (
        (v_is_vip_section AND fn_asset_config_is_vip(c.tags))
        OR (NOT v_is_vip_section AND (c.id IS NULL OR NOT fn_asset_config_is_vip(c.tags)))
      );

    IF v_count >= v_limit THEN
      RETURN fn_response_error(
        'Quota exceeded',
        'Asset limit reached for this section. Remove or keep existing assets.',
        'QUOTA_EXCEEDED',
        jsonb_build_object('count', v_count, 'limit', v_limit)
      );
    END IF;

    IF v_config_id IS NULL AND v_limit = 0 THEN
      RETURN fn_response_error(
        'Quota exceeded',
        'This member has no asset quota for the selected section.',
        'QUOTA_EXCEEDED',
        jsonb_build_object('count', v_count, 'limit', v_limit)
      );
    END IF;

    INSERT INTO asset (
      merchant_id, asset_type_id, user_id, name, status,
      custom_fields, asset_tier_config_id, created_at, updated_at
    ) VALUES (
      v_merchant_id, v_type.id, v_user_id, v_name, 'active',
      COALESCE(p_custom_fields, '{}'::jsonb), v_config_id, now(), now()
    )
    RETURNING * INTO v_asset;

    PERFORM fn_asset_mark_sync_pending(v_merchant_id, v_asset.id);
  ELSE
    SELECT * INTO v_asset
    FROM asset
    WHERE id = p_asset_id
      AND merchant_id = v_merchant_id
      AND user_id = v_user_id
      AND deleted_at IS NULL;

    IF v_asset.id IS NULL THEN
      RETURN fn_response_error('Asset not found', 'Asset does not exist for this member.', 'ASSET_NOT_FOUND');
    END IF;

    IF lower(COALESCE(v_asset.status, '')) <> 'active' THEN
      RETURN fn_response_error(
        'Inactive asset',
        'Only active assets can be edited.',
        'ASSET_INACTIVE'
      );
    END IF;

    UPDATE asset
    SET name = v_name,
        custom_fields = COALESCE(p_custom_fields, custom_fields),
        asset_tier_config_id = COALESCE(v_config_id, asset_tier_config_id),
        updated_at = now()
    WHERE id = v_asset.id
    RETURNING * INTO v_asset;

    PERFORM fn_asset_mark_sync_pending(v_merchant_id, v_asset.id);
  END IF;

  RETURN fn_response_success(
    'Asset saved',
    CASE WHEN p_asset_id IS NULL THEN 'Asset created.' ELSE 'Asset updated.' END,
    jsonb_build_object(
      'asset', jsonb_build_object(
        'id', v_asset.id,
        'name', v_asset.name,
        'status', v_asset.status,
        'custom_fields', v_asset.custom_fields,
        'asset_tier_config_id', v_asset.asset_tier_config_id,
        'asset_type_code', v_type.type_code,
        'created_at', v_asset.created_at,
        'updated_at', v_asset.updated_at,
        'can_edit', lower(COALESCE(v_asset.status, '')) = 'active'
      )
    )
  );
EXCEPTION WHEN OTHERS THEN
  RETURN fn_response_error('Asset save failed', SQLERRM, 'ASSET_SAVE_FAILED');
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_user_set_asset_status(
  p_asset_id uuid,
  p_status text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_auth jsonb;
  v_user_id uuid;
  v_merchant_id uuid;
  v_asset asset%ROWTYPE;
  v_status text;
  v_is_vip boolean;
  v_sections jsonb;
  v_section jsonb;
  v_limit int;
  v_active_count int;
BEGIN
  v_auth := fn_asset_resolve_auth_member();
  IF NOT COALESCE((v_auth->>'ok')::boolean, false) THEN
    RETURN fn_response_error(
      COALESCE(v_auth->>'title', 'Auth failed'),
      COALESCE(v_auth->>'description', 'Unable to resolve member.'),
      COALESCE(v_auth->>'code', 'AUTH_FAILED')
    );
  END IF;
  v_user_id := (v_auth->>'user_id')::uuid;
  v_merchant_id := (v_auth->>'merchant_id')::uuid;

  v_status := lower(trim(p_status));
  IF v_status NOT IN ('active', 'inactive') THEN
    RETURN fn_response_error('Invalid status', 'Status must be active or inactive.', 'INVALID_STATUS');
  END IF;

  SELECT * INTO v_asset
  FROM asset
  WHERE id = p_asset_id
    AND merchant_id = v_merchant_id
    AND user_id = v_user_id
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
    v_sections := fn_asset_resolve_sections(v_merchant_id, v_user_id, v_asset.asset_type_id);

    SELECT s INTO v_section
    FROM jsonb_array_elements(v_sections) s
    WHERE COALESCE((s->>'is_vip')::boolean, false) = v_is_vip
    LIMIT 1;

    v_limit := COALESCE((v_section->>'limit')::int, 0);

    SELECT count(*)::int INTO v_active_count
    FROM asset a
    LEFT JOIN asset_tier_config c ON c.id = a.asset_tier_config_id
    WHERE a.merchant_id = v_merchant_id
      AND a.user_id = v_user_id
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
$function$;

CREATE OR REPLACE FUNCTION public.bff_user_delete_asset(
  p_asset_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_auth jsonb;
  v_user_id uuid;
  v_merchant_id uuid;
  v_asset asset%ROWTYPE;
BEGIN
  v_auth := fn_asset_resolve_auth_member();
  IF NOT COALESCE((v_auth->>'ok')::boolean, false) THEN
    RETURN fn_response_error(
      COALESCE(v_auth->>'title', 'Auth failed'),
      COALESCE(v_auth->>'description', 'Unable to resolve member.'),
      COALESCE(v_auth->>'code', 'AUTH_FAILED')
    );
  END IF;
  v_user_id := (v_auth->>'user_id')::uuid;
  v_merchant_id := (v_auth->>'merchant_id')::uuid;

  SELECT * INTO v_asset
  FROM asset
  WHERE id = p_asset_id
    AND merchant_id = v_merchant_id
    AND user_id = v_user_id
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
$function$;

CREATE OR REPLACE FUNCTION public.bff_user_get_parking_entrance_qr(
  p_asset_id uuid DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_auth jsonb;
  v_user_id uuid;
  v_merchant_id uuid;
  v_asset asset%ROWTYPE;
  v_expires_at timestamptz;
  v_ttl int := 600;
  v_nonce text;
  v_claims jsonb;
  v_payload text;
BEGIN
  v_auth := fn_asset_resolve_auth_member();
  IF NOT COALESCE((v_auth->>'ok')::boolean, false) THEN
    RETURN fn_response_error(
      COALESCE(v_auth->>'title', 'Auth failed'),
      COALESCE(v_auth->>'description', 'Unable to resolve member.'),
      COALESCE(v_auth->>'code', 'AUTH_FAILED')
    );
  END IF;
  v_user_id := (v_auth->>'user_id')::uuid;
  v_merchant_id := (v_auth->>'merchant_id')::uuid;

  -- Vehicle-bound entrance QR only (CityPark needs plate). Null → require selection.
  IF p_asset_id IS NULL THEN
    RETURN fn_response_error(
      'Vehicle required',
      'Select an active vehicle to show the parking entrance QR.',
      'ASSET_REQUIRED'
    );
  END IF;

  SELECT * INTO v_asset
  FROM asset
  WHERE id = p_asset_id
    AND merchant_id = v_merchant_id
    AND user_id = v_user_id
    AND deleted_at IS NULL;

  IF v_asset.id IS NULL THEN
    RETURN fn_response_error('Asset not found', 'Vehicle not found for this member.', 'ASSET_NOT_FOUND');
  END IF;

  IF lower(COALESCE(v_asset.status, '')) <> 'active' THEN
    RETURN fn_response_error(
      'Inactive vehicle',
      'Only active vehicles can show a parking entrance QR.',
      'ASSET_INACTIVE'
    );
  END IF;

  v_expires_at := now() + make_interval(secs => v_ttl);
  v_nonce := encode(gen_random_bytes(16), 'hex');

  v_claims := jsonb_build_object(
    'v', 1,
    'kind', 'parking_entrance',
    'merchant_id', v_merchant_id,
    'user_id', v_user_id,
    'asset_id', v_asset.id,
    'plate', v_asset.custom_fields->>'car_plate',
    'province', v_asset.custom_fields->>'car_plate_province',
    'exp', floor(extract(epoch FROM v_expires_at))::bigint,
    'nonce', v_nonce
  );

  -- Temporary CRM opaque token until CityPark HTTP sync. Rotated on every call.
  v_payload := 'CRM-PARKING-V1.' || encode(convert_to(v_claims::text, 'utf8'), 'base64');

  RETURN fn_response_success(
    'Entrance QR',
    'Temporary CRM parking entrance token. Valid for 10 minutes. Call again when the countdown reaches zero (token is rotated each call). Not yet exchanged with CityPark.',
    jsonb_build_object(
      'payload', v_payload,
      'expires_at', v_expires_at,
      'ttl_seconds', v_ttl,
      'rotated', true,
      'asset_id', v_asset.id,
      'license_plate', v_asset.custom_fields->>'car_plate',
      'province', v_asset.custom_fields->>'car_plate_province',
      'status_asset', lower(COALESCE(v_asset.status, 'inactive')),
      'format', 'CRM-PARKING-V1.<base64(json claims)>'
    )
  );
EXCEPTION WHEN OTHERS THEN
  RETURN fn_response_error('QR failed', SQLERRM, 'PARKING_QR_FAILED');
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_asset_resolve_auth_member() TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_user_get_assets(text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_user_upsert_asset(text, jsonb, uuid, text, text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_user_set_asset_status(uuid, text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_user_delete_asset(uuid) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_user_get_parking_entrance_qr(uuid) TO anon, authenticated, service_role;
