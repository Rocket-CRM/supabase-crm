CREATE OR REPLACE FUNCTION public.bff_admin_upsert_user_asset(
  p_user_id uuid,
  p_asset_type_code text,
  p_custom_fields jsonb,
  p_asset_id uuid DEFAULT NULL,
  p_section_key text DEFAULT 'general',
  p_name text DEFAULT NULL
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
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error('No merchant context', 'Unable to resolve merchant for this request.', 'NO_MERCHANT_CONTEXT');
  END IF;

  IF NOT (
    check_admin_permission('frontline_asset_group', 'create')
    OR check_admin_permission('frontline_asset_group', 'update')
    OR check_admin_permission('asset', 'create')
    OR check_admin_permission('asset', 'update')
  ) THEN
    RETURN fn_response_error('Forbidden', 'Insufficient permission to manage assets.', 'FORBIDDEN');
  END IF;

  IF p_user_id IS NULL THEN
    RETURN fn_response_error('Customer required', 'Select a customer before managing assets.', 'CUSTOMER_REQUIRED');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM user_accounts ua
    WHERE ua.id = p_user_id AND ua.merchant_id = v_merchant_id AND ua.deleted_at IS NULL
  ) THEN
    RETURN fn_response_error('Customer not found', 'Customer does not belong to this merchant.', 'CUSTOMER_NOT_FOUND');
  END IF;

  SELECT * INTO v_type
  FROM asset_type
  WHERE merchant_id = v_merchant_id
    AND upper(type_code) = upper(trim(p_asset_type_code))
  LIMIT 1;

  IF v_type.id IS NULL THEN
    RETURN fn_response_error('Asset type not found', 'Unknown asset type for this merchant.', 'ASSET_TYPE_NOT_FOUND');
  END IF;

  v_sections := fn_asset_resolve_sections(v_merchant_id, p_user_id, v_type.id);
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

  -- Mandatory fields from field_schema when present
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
    -- Create: quota on total non-deleted in section
    SELECT count(*)::int INTO v_count
    FROM asset a
    LEFT JOIN asset_tier_config c ON c.id = a.asset_tier_config_id
    WHERE a.merchant_id = v_merchant_id
      AND a.user_id = p_user_id
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
      v_merchant_id, v_type.id, p_user_id, v_name, 'active',
      COALESCE(p_custom_fields, '{}'::jsonb), v_config_id, now(), now()
    )
    RETURNING * INTO v_asset;

    PERFORM fn_asset_mark_sync_pending(v_merchant_id, v_asset.id);
  ELSE
    SELECT * INTO v_asset
    FROM asset
    WHERE id = p_asset_id
      AND merchant_id = v_merchant_id
      AND user_id = p_user_id
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
        'updated_at', v_asset.updated_at
      )
    )
  );
EXCEPTION WHEN OTHERS THEN
  RETURN fn_response_error('Asset save failed', SQLERRM, 'ASSET_SAVE_FAILED');
END;
$$;
