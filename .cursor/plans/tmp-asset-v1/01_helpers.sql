-- Asset v1 helpers: plate normalize, VIP checks, section resolve, quota enforce, sync mark

CREATE OR REPLACE FUNCTION public.fn_asset_normalize_plate(p_plate text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT NULLIF(lower(regexp_replace(trim(COALESCE(p_plate, '')), '\s+', '', 'g')), '');
$$;

CREATE OR REPLACE FUNCTION public.fn_asset_config_is_vip(p_tags jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $$
  -- jsonb null / objects / strings are not SQL NULL; only arrays are iterable
  SELECT CASE
    WHEN p_tags IS NULL OR jsonb_typeof(p_tags) <> 'array' THEN false
    ELSE EXISTS (
      SELECT 1
      FROM jsonb_array_elements(p_tags) e
      WHERE COALESCE(e->>'name', '') ILIKE 'VIP'
    )
  END;
$$;

CREATE OR REPLACE FUNCTION public.fn_asset_user_has_vip(
  p_merchant_id uuid,
  p_user_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM user_tags ut
    JOIN tag_master tm ON tm.id = ut.tag_id
    WHERE ut.user_id = p_user_id
      AND ut.merchant_id = p_merchant_id
      AND upper(COALESCE(tm.tag_name, '')) = 'VIP'
      AND COALESCE(tm.active_status, true)
  );
$$;

CREATE OR REPLACE FUNCTION public.fn_asset_assert_plate_unique(
  p_merchant_id uuid,
  p_plate text,
  p_exclude_asset_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'public'
AS $$
DECLARE
  v_norm text;
  v_exists boolean;
BEGIN
  v_norm := fn_asset_normalize_plate(p_plate);
  IF v_norm IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'PLATE_REQUIRED');
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM asset a
    WHERE a.merchant_id = p_merchant_id
      AND a.deleted_at IS NULL
      AND (p_exclude_asset_id IS NULL OR a.id <> p_exclude_asset_id)
      AND fn_asset_normalize_plate(a.custom_fields->>'car_plate') = v_norm
  ) INTO v_exists;

  IF v_exists THEN
    RETURN jsonb_build_object(
      'ok', false,
      'code', 'PLATE_DUPLICATE',
      'message', 'ทะเบียนรถนี้มีการลงทะเบียนแล้ว กรุณาตรวจสอบอีกครั้ง'
    );
  END IF;

  RETURN jsonb_build_object('ok', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_asset_resolve_sections(
  p_merchant_id uuid,
  p_user_id uuid,
  p_asset_type_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'public'
AS $$
DECLARE
  v_tier_id uuid;
  v_has_vip boolean;
  v_type_code text;
  v_sections jsonb := '[]'::jsonb;
  v_base asset_tier_config%ROWTYPE;
  v_vip asset_tier_config%ROWTYPE;
  v_general_label text;
  v_vip_label text;
BEGIN
  SELECT ua.tier_id INTO v_tier_id
  FROM user_accounts ua
  WHERE ua.id = p_user_id AND ua.merchant_id = p_merchant_id;

  SELECT at.type_code INTO v_type_code
  FROM asset_type at
  WHERE at.id = p_asset_type_id AND at.merchant_id = p_merchant_id;

  v_has_vip := fn_asset_user_has_vip(p_merchant_id, p_user_id);

  IF upper(COALESCE(v_type_code, '')) = 'CAR' THEN
    v_general_label := 'General Parking';
    v_vip_label := 'VIP Parking';
  ELSE
    v_general_label := 'General';
    v_vip_label := 'VIP';
  END IF;

  IF v_tier_id IS NOT NULL THEN
    SELECT * INTO v_base
    FROM asset_tier_config c
    WHERE c.merchant_id = p_merchant_id
      AND c.asset_type_id = p_asset_type_id
      AND c.tier_id = v_tier_id
      AND c.is_active
      AND NOT fn_asset_config_is_vip(c.tags)
    ORDER BY c.sort NULLS LAST, c.name
    LIMIT 1;

    IF v_has_vip THEN
      SELECT * INTO v_vip
      FROM asset_tier_config c
      WHERE c.merchant_id = p_merchant_id
        AND c.asset_type_id = p_asset_type_id
        AND c.tier_id = v_tier_id
        AND c.is_active
        AND fn_asset_config_is_vip(c.tags)
      ORDER BY c.sort NULLS LAST, c.name
      LIMIT 1;
    END IF;
  END IF;

  -- Always expose a general section so UI can show 0/0 when no entitlement
  v_sections := v_sections || jsonb_build_array(jsonb_build_object(
    'section_key', 'general',
    'section_label', v_general_label,
    'asset_tier_config_id', v_base.id,
    'config_name', v_base.name,
    'limit', COALESCE(v_base.asset_limit_per_user, 0),
    'field_schema', COALESCE(v_base.field_schema, '[]'::jsonb),
    'is_vip', false
  ));

  IF v_has_vip THEN
    v_sections := v_sections || jsonb_build_array(jsonb_build_object(
      'section_key', 'vip',
      'section_label', v_vip_label,
      'asset_tier_config_id', v_vip.id,
      'config_name', v_vip.name,
      'limit', COALESCE(v_vip.asset_limit_per_user, 0),
      'field_schema', COALESCE(v_vip.field_schema, '[]'::jsonb),
      'is_vip', true
    ));
  END IF;

  RETURN v_sections;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_asset_mark_sync_pending(
  p_merchant_id uuid,
  p_asset_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'public'
AS $$
BEGIN
  UPDATE custom_crm_asset_sync
  SET is_sync = false,
      updated_at = now()
  WHERE merchant_id = p_merchant_id
    AND asset_id = p_asset_id;

  IF NOT FOUND THEN
    INSERT INTO custom_crm_asset_sync (
      id, mongo_id, merchant_id, asset_id, is_sync, created_at, updated_at
    ) VALUES (
      gen_random_uuid(),
      'local:' || p_asset_id::text,
      p_merchant_id,
      p_asset_id,
      false,
      now(),
      now()
    );
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_asset_enforce_quota_after_tier_change(
  p_merchant_id uuid,
  p_user_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_type record;
  v_section jsonb;
  v_sections jsonb;
  v_limit int;
  v_active_count int;
  v_to_inactivate int;
  v_inactivated uuid[] := '{}';
  v_asset_id uuid;
  v_is_vip boolean;
BEGIN
  FOR v_type IN
    SELECT DISTINCT a.asset_type_id
    FROM asset a
    WHERE a.merchant_id = p_merchant_id
      AND a.user_id = p_user_id
      AND a.deleted_at IS NULL
  LOOP
    v_sections := fn_asset_resolve_sections(p_merchant_id, p_user_id, v_type.asset_type_id);

    FOR v_section IN SELECT * FROM jsonb_array_elements(v_sections)
    LOOP
      v_limit := COALESCE((v_section->>'limit')::int, 0);
      v_is_vip := COALESCE((v_section->>'is_vip')::boolean, false);

      SELECT count(*)::int INTO v_active_count
      FROM asset a
      LEFT JOIN asset_tier_config c ON c.id = a.asset_tier_config_id
      WHERE a.merchant_id = p_merchant_id
        AND a.user_id = p_user_id
        AND a.asset_type_id = v_type.asset_type_id
        AND a.deleted_at IS NULL
        AND lower(COALESCE(a.status, '')) = 'active'
        AND (
          (v_is_vip AND fn_asset_config_is_vip(c.tags))
          OR (NOT v_is_vip AND (c.id IS NULL OR NOT fn_asset_config_is_vip(c.tags)))
        );

      v_to_inactivate := GREATEST(v_active_count - v_limit, 0);

      IF v_to_inactivate > 0 THEN
        FOR v_asset_id IN
          SELECT a.id
          FROM asset a
          LEFT JOIN asset_tier_config c ON c.id = a.asset_tier_config_id
          WHERE a.merchant_id = p_merchant_id
            AND a.user_id = p_user_id
            AND a.asset_type_id = v_type.asset_type_id
            AND a.deleted_at IS NULL
            AND lower(COALESCE(a.status, '')) = 'active'
            AND (
              (v_is_vip AND fn_asset_config_is_vip(c.tags))
              OR (NOT v_is_vip AND (c.id IS NULL OR NOT fn_asset_config_is_vip(c.tags)))
            )
          ORDER BY a.created_at ASC NULLS FIRST, a.id ASC
          LIMIT v_to_inactivate
        LOOP
          UPDATE asset
          SET status = 'inactive',
              updated_at = now()
          WHERE id = v_asset_id;

          PERFORM fn_asset_mark_sync_pending(p_merchant_id, v_asset_id);
          v_inactivated := array_append(v_inactivated, v_asset_id);
        END LOOP;
      END IF;
    END LOOP;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'inactivated_asset_ids', to_jsonb(v_inactivated)
  );
END;
$$;

CREATE INDEX IF NOT EXISTS idx_asset_merchant_plate_lookup
ON public.asset (merchant_id, ((custom_fields->>'car_plate')))
WHERE deleted_at IS NULL AND custom_fields ? 'car_plate';
