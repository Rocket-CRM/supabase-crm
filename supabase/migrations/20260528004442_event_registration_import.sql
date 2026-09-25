-- Event registration bulk import (Syngenta)
-- Reuses bulk_import_batches, user_import_staging, bulk_upsert_customers_from_import

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_normalize_th_geo_name(p_text text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT NULLIF(
    trim(
      regexp_replace(
        regexp_replace(
          regexp_replace(
            regexp_replace(
              regexp_replace(
                regexp_replace(lower(trim(coalesce(p_text, ''))), '^จ\.?\s*', '', 'g'),
                '^จังหวัด\s*', '', 'g'
              ),
              '^อ\.?\s*', '', 'g'
            ),
            '^อำเภอ\s*', '', 'g'
          ),
          '^ต\.?\s*', '', 'g'
        ),
        '^ตำบล\s*', '', 'g'
      )
    ),
    ''
  );
$$;

CREATE OR REPLACE FUNCTION public.fn_import_truthy(p_value text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT coalesce(p_value, '') ~* '^(1|true|yes|y|t)$';
$$;

CREATE OR REPLACE FUNCTION public.fn_normalize_import_tel(p_tel text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_digits text;
BEGIN
  IF p_tel IS NULL OR trim(p_tel) = '' THEN
    RETURN NULL;
  END IF;

  v_digits := regexp_replace(p_tel, '[^0-9+]', '', 'g');

  IF v_digits ~ '^\+' THEN
    RETURN v_digits;
  END IF;

  IF v_digits ~ '^66' THEN
    RETURN '+' || v_digits;
  END IF;

  IF v_digits ~ '^0' THEN
    RETURN '+66' || substr(v_digits, 2);
  END IF;

  RETURN '+66' || v_digits;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_resolve_th_address_codes(
  p_province text,
  p_district text,
  p_subdistrict text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_province_id text;
  v_district_id text;
  v_subdistrict_id text;
  v_province_norm text := fn_normalize_th_geo_name(p_province);
  v_district_norm text := fn_normalize_th_geo_name(p_district);
  v_subdistrict_norm text := fn_normalize_th_geo_name(p_subdistrict);
BEGIN
  IF v_province_norm IS NOT NULL THEN
    SELECT p.id
    INTO v_province_id
    FROM address_th_province p
    WHERE fn_normalize_th_geo_name(p.province_name_th) = v_province_norm
       OR fn_normalize_th_geo_name(p.province_name_en) = v_province_norm
    ORDER BY p.sort_order NULLS LAST, p.id
    LIMIT 1;
  END IF;

  IF v_province_id IS NOT NULL AND v_district_norm IS NOT NULL THEN
    SELECT d.id
    INTO v_district_id
    FROM address_th_district d
    WHERE d.province_id::text = v_province_id
      AND (
        fn_normalize_th_geo_name(d.district_name_th) = v_district_norm
        OR fn_normalize_th_geo_name(d.district_name_en) = v_district_norm
      )
    ORDER BY d.sort_order NULLS LAST, d.id
    LIMIT 1;
  END IF;

  IF v_district_id IS NOT NULL AND v_subdistrict_norm IS NOT NULL THEN
    SELECT s.id
    INTO v_subdistrict_id
    FROM address_th_subdistrict s
    WHERE s.district_id::text = v_district_id
      AND (
        fn_normalize_th_geo_name(s.subdistrict_name_th) = v_subdistrict_norm
        OR fn_normalize_th_geo_name(s.subdistrict_name_en) = v_subdistrict_norm
      )
    ORDER BY s.id
    LIMIT 1;
  END IF;

  RETURN jsonb_build_object(
    'province_code', v_province_id,
    'district_code', v_district_id,
    'subdistrict_code', v_subdistrict_id
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_build_event_import_field_selection(p_event_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event record;
  v_form record;
  v_profile_form_id uuid;
  v_columns jsonb := '[]'::jsonb;
  v_legacy jsonb := '{}'::jsonb;
  v_field record;
  v_option record;
  v_col_key text;
BEGIN
  SELECT e.id, e.merchant_id, e.event_code, e.form_id
  INTO v_event
  FROM syngenta_events_master e
  WHERE e.id = p_event_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Event not found: %', p_event_id;
  END IF;

  IF v_event.form_id IS NULL THEN
    RAISE EXCEPTION 'Event % has no linked survey form', v_event.event_code;
  END IF;

  SELECT ft.id, ft.code, ft.name
  INTO v_form
  FROM form_templates ft
  WHERE ft.id = v_event.form_id
    AND ft.merchant_id = v_event.merchant_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Linked form not found for event %', v_event.event_code;
  END IF;

  SELECT ft.id
  INTO v_profile_form_id
  FROM form_templates ft
  WHERE ft.merchant_id = v_event.merchant_id
    AND ft.code = 'USER_PROFILE'
  LIMIT 1;

  -- Default profile + address columns
  v_columns := v_columns || jsonb_build_array(
    jsonb_build_object('key', 'user_accounts_tel', 'label', 'Phone', 'kind', 'default', 'required', true),
    jsonb_build_object('key', 'user_accounts_fullname', 'label', 'Full Name', 'kind', 'default', 'required', false),
    jsonb_build_object('key', 'user_accounts_id_card', 'label', 'ID Card', 'kind', 'default', 'required', false),
    jsonb_build_object('key', 'user_address_addressline_1', 'label', 'Address Line 1', 'kind', 'address', 'required', false),
    jsonb_build_object('key', 'user_address_subdistrict', 'label', 'Sub-district', 'kind', 'address', 'required', false),
    jsonb_build_object('key', 'user_address_district', 'label', 'District', 'kind', 'address', 'required', false),
    jsonb_build_object('key', 'user_address_state', 'label', 'Province', 'kind', 'address', 'required', false),
    jsonb_build_object('key', 'import_source', 'label', 'Source', 'kind', 'metadata', 'required', false),
    jsonb_build_object('key', 'import_registered_at', 'label', 'Registration Date', 'kind', 'metadata', 'required', false)
  );

  v_legacy := v_legacy || jsonb_build_object(
    'tel', 'user_accounts_tel',
    'fullname', 'user_accounts_fullname',
    'id_card', 'user_accounts_id_card',
    'address', 'user_address_addressline_1',
    'address1', 'user_address_addressline_1',
    'sub_district', 'user_address_subdistrict',
    'district', 'user_address_district',
    'province', 'user_address_state',
    'source', 'import_source',
    'Date', 'import_registered_at',
    'date', 'import_registered_at',
    'event_code', '_event_code'
  );

  -- USER_PROFILE custom fields used on Syngenta events
  IF v_profile_form_id IS NOT NULL THEN
    FOR v_field IN
      SELECT ff.field_key, ff.field_type, ff.label
      FROM form_fields ff
      WHERE ff.form_id = v_profile_form_id
        AND ff.field_key IN ('crop', 'area')
      ORDER BY ff.order_index
    LOOP
      v_col_key := 'user_profile_' || v_field.field_key;
      v_columns := v_columns || jsonb_build_array(
        jsonb_build_object(
          'key', v_col_key,
          'label', v_field.label,
          'kind', 'profile_form',
          'field_key', v_field.field_key,
          'field_type', v_field.field_type,
          'required', false
        )
      );
      v_legacy := v_legacy || jsonb_build_object(v_field.field_key, v_col_key);
    END LOOP;
  END IF;

  -- Event survey form fields
  FOR v_field IN
    SELECT ff.id, ff.field_key, ff.field_type, ff.label, ff.is_required
    FROM form_fields ff
    WHERE ff.form_id = v_form.id
    ORDER BY ff.order_index
  LOOP
    IF v_field.field_type IN ('multi-select', 'multi_select') THEN
      FOR v_option IN
        SELECT fo.option_value, fo.option_label
        FROM form_field_options fo
        WHERE fo.field_id = v_field.id
        ORDER BY fo.order_index NULLS LAST, fo.option_value
      LOOP
        v_col_key := format('form_%s_%s__%s', v_form.code, v_field.field_key, v_option.option_value);
        v_columns := v_columns || jsonb_build_array(
          jsonb_build_object(
            'key', v_col_key,
            'label', coalesce(v_option.option_label, v_option.option_value),
            'kind', 'form_option',
            'form_code', v_form.code,
            'field_key', v_field.field_key,
            'option_value', v_option.option_value,
            'field_type', v_field.field_type,
            'required', false
          )
        );
        v_legacy := v_legacy || jsonb_build_object(v_option.option_value, v_col_key);
      END LOOP;
      v_legacy := v_legacy || jsonb_build_object(v_field.field_key, format('form_%s_%s', v_form.code, v_field.field_key));
    ELSE
      v_col_key := format('form_%s_%s', v_form.code, v_field.field_key);
      v_columns := v_columns || jsonb_build_array(
        jsonb_build_object(
          'key', v_col_key,
          'label', v_field.label,
          'kind', 'form_scalar',
          'form_code', v_form.code,
          'field_key', v_field.field_key,
          'field_type', v_field.field_type,
          'required', coalesce(v_field.is_required, false)
        )
      );
      v_legacy := v_legacy || jsonb_build_object(v_field.field_key, v_col_key);
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'event_id', v_event.id,
    'event_code', v_event.event_code,
    'merchant_id', v_event.merchant_id,
    'form_id', v_form.id,
    'form_code', v_form.code,
    'columns', v_columns,
    'legacy_aliases', v_legacy
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_resolve_form_field_input(
  p_form_id uuid,
  p_field_key text,
  p_input text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_field record;
  v_option_value text;
  v_values text[];
  v_part text;
  v_resolved text[];
BEGIN
  IF coalesce(trim(p_input), '') = '' THEN
    RETURN NULL;
  END IF;

  SELECT ff.id, ff.field_type
  INTO v_field
  FROM form_fields ff
  WHERE ff.form_id = p_form_id
    AND ff.field_key = p_field_key
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN to_jsonb(trim(p_input));
  END IF;

  IF v_field.field_type IN ('multi-select', 'multi_select') THEN
    v_values := regexp_split_to_array(p_input, '\|');
    FOREACH v_part IN ARRAY v_values
    LOOP
      v_part := trim(v_part);
      IF v_part = '' THEN CONTINUE; END IF;
      SELECT fo.option_value
      INTO v_option_value
      FROM form_field_options fo
      WHERE fo.field_id = v_field.id
        AND (fo.option_value = v_part OR fo.option_label = v_part)
      LIMIT 1;
      IF v_option_value IS NOT NULL THEN
        v_resolved := array_append(v_resolved, v_option_value);
      ELSE
        v_resolved := array_append(v_resolved, v_part);
      END IF;
    END LOOP;
    RETURN to_jsonb(v_resolved);
  END IF;

  IF v_field.field_type IN ('select', 'single_select') THEN
    SELECT fo.option_value
    INTO v_option_value
    FROM form_field_options fo
    WHERE fo.field_id = v_field.id
      AND (fo.option_value = trim(p_input) OR fo.option_label = trim(p_input))
    LIMIT 1;
    RETURN to_jsonb(coalesce(v_option_value, trim(p_input)));
  END IF;

  RETURN to_jsonb(trim(p_input));
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_normalize_event_import_row(
  p_row jsonb,
  p_field_selection jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_normalized jsonb := '{}'::jsonb;
  v_legacy jsonb;
  v_columns jsonb;
  v_src_key text;
  v_src_val text;
  v_target_key text;
  v_col jsonb;
  v_form_values jsonb := '{}'::jsonb;
  v_field_key text;
  v_codes jsonb;
  v_event_code text;
  v_form_id uuid := (p_field_selection->>'form_id')::uuid;
  v_handled boolean;
  v_scalar_val jsonb;
BEGIN
  v_legacy := coalesce(p_field_selection->'legacy_aliases', '{}'::jsonb);
  v_columns := coalesce(p_field_selection->'columns', '[]'::jsonb);
  v_event_code := p_field_selection->>'event_code';

  IF coalesce(p_row->>'event_code', p_row->>'_event_code') IS NOT NULL
     AND coalesce(p_row->>'event_code', p_row->>'_event_code') <> v_event_code THEN
    RAISE EXCEPTION 'event_code mismatch: expected %, got %', v_event_code, coalesce(p_row->>'event_code', p_row->>'_event_code');
  END IF;

  FOR v_src_key, v_src_val IN SELECT key, value FROM jsonb_each_text(p_row)
  LOOP
    IF v_src_key IN ('event_code', '_event_code') THEN
      CONTINUE;
    END IF;

    v_handled := false;

    FOR v_col IN SELECT value FROM jsonb_array_elements(v_columns)
    LOOP
      IF v_col->>'kind' = 'form_option'
         AND (v_src_key = v_col->>'key' OR v_src_key = v_col->>'option_value' OR v_legacy->>v_src_key = v_col->>'key') THEN
        IF fn_import_truthy(v_src_val) THEN
          v_field_key := v_col->>'field_key';
          v_form_values := jsonb_set(
            v_form_values,
            ARRAY[v_field_key],
            coalesce(v_form_values->v_field_key, '[]'::jsonb) || to_jsonb(v_col->>'option_value'),
            true
          );
        END IF;
        v_handled := true;
        EXIT;
      END IF;
    END LOOP;

    IF v_handled THEN
      CONTINUE;
    END IF;

    v_target_key := CASE WHEN v_legacy ? v_src_key THEN v_legacy->>v_src_key ELSE v_src_key END;
    IF v_target_key = '_event_code' THEN
      CONTINUE;
    END IF;

    v_normalized := jsonb_set(v_normalized, ARRAY[v_target_key], to_jsonb(v_src_val), true);
  END LOOP;

  FOR v_col IN SELECT value FROM jsonb_array_elements(v_columns)
  LOOP
    IF v_col->>'kind' = 'form_scalar' AND v_normalized ? (v_col->>'key') THEN
      v_scalar_val := fn_resolve_form_field_input(v_form_id, v_col->>'field_key', v_normalized->>(v_col->>'key'));
      IF v_scalar_val IS NOT NULL THEN
        v_form_values := jsonb_set(v_form_values, ARRAY[v_col->>'field_key'], v_scalar_val, true);
      END IF;
    END IF;
  END LOOP;

  IF v_normalized ? 'user_accounts_tel' THEN
    v_normalized := jsonb_set(
      v_normalized,
      ARRAY['user_accounts_tel'],
      to_jsonb(fn_normalize_import_tel(v_normalized->>'user_accounts_tel')),
      true
    );
  END IF;

  v_codes := fn_resolve_th_address_codes(
    v_normalized->>'user_address_state',
    v_normalized->>'user_address_district',
    v_normalized->>'user_address_subdistrict'
  );

  IF v_codes->>'province_code' IS NOT NULL THEN
    v_normalized := jsonb_set(v_normalized, ARRAY['user_address_province_code'], to_jsonb(v_codes->>'province_code'), true);
  END IF;
  IF v_codes->>'district_code' IS NOT NULL THEN
    v_normalized := jsonb_set(v_normalized, ARRAY['user_address_district_code'], to_jsonb(v_codes->>'district_code'), true);
  END IF;
  IF v_codes->>'subdistrict_code' IS NOT NULL THEN
    v_normalized := jsonb_set(v_normalized, ARRAY['user_address_subdistrict_code'], to_jsonb(v_codes->>'subdistrict_code'), true);
  END IF;

  v_normalized := jsonb_set(v_normalized, ARRAY['_survey_submission'], v_form_values, true);
  v_normalized := jsonb_set(v_normalized, ARRAY['_import_metadata'], jsonb_build_object(
    'source', v_normalized->>'import_source',
    'registered_at', v_normalized->>'import_registered_at'
  ), true);

  RETURN v_normalized;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_upsert_event_registration(
  p_merchant_id uuid,
  p_event_id uuid,
  p_event_code text,
  p_user_id uuid,
  p_member_name text,
  p_member_tel text,
  p_form_submission_id uuid,
  p_source text DEFAULT 'event_import',
  p_custom_data jsonb DEFAULT '{}'::jsonb,
  p_registered boolean DEFAULT true,
  p_attended boolean DEFAULT false,
  p_registered_at timestamptz DEFAULT now()
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing_id bigint;
  v_row syngenta_event_registration_ledger%ROWTYPE;
BEGIN
  SELECT id
  INTO v_existing_id
  FROM syngenta_event_registration_ledger
  WHERE merchant_id = p_merchant_id
    AND event_id = p_event_id
    AND member_id = p_user_id::text
  ORDER BY id DESC
  LIMIT 1;

  IF v_existing_id IS NOT NULL THEN
    UPDATE syngenta_event_registration_ledger
    SET member_name = coalesce(p_member_name, member_name),
        member_tel = coalesce(p_member_tel, member_tel),
        registered = p_registered,
        attended = coalesce(p_attended, attended),
        source = coalesce(p_source, source),
        form_submission_id = coalesce(p_form_submission_id, form_submission_id),
        custom_data = coalesce(p_custom_data, custom_data),
        time_registered = coalesce(p_registered_at, time_registered)
    WHERE id = v_existing_id
    RETURNING * INTO v_row;
  ELSE
    INSERT INTO syngenta_event_registration_ledger (
      merchant_id, event_id, event_code, member_id, member_name, member_tel,
      registered, attended, source, form_submission_id, custom_data, time_registered
    ) VALUES (
      p_merchant_id, p_event_id, p_event_code, p_user_id::text, p_member_name, p_member_tel,
      p_registered, p_attended, p_source, p_form_submission_id, p_custom_data, p_registered_at
    )
    RETURNING * INTO v_row;
  END IF;

  RETURN jsonb_build_object(
    'registration_id', v_row.id,
    'created', v_existing_id IS NULL,
    'updated', v_existing_id IS NOT NULL
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_process_event_registration_import_row(
  p_merchant_id uuid,
  p_field_selection jsonb,
  p_row jsonb,
  p_match_on text[] DEFAULT ARRAY['tel']
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_normalized jsonb;
  v_upsert_row jsonb;
  v_user_row jsonb;
  v_upsert_result record;
  v_user_id uuid;
  v_submission jsonb;
  v_submission_id uuid;
  v_registration jsonb;
  v_event_id uuid := (p_field_selection->>'event_id')::uuid;
  v_event_code text := p_field_selection->>'event_code';
  v_form_id uuid := (p_field_selection->>'form_id')::uuid;
  v_key text;
BEGIN
  v_normalized := fn_normalize_event_import_row(p_row, p_field_selection);

  IF coalesce(v_normalized->>'user_accounts_tel', '') = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Missing required field: user_accounts_tel');
  END IF;

  -- Strip internal/metadata keys before user upsert
  v_upsert_row := v_normalized;
  v_upsert_row := v_upsert_row - '_survey_submission' - '_import_metadata' - 'import_source' - 'import_registered_at';
  FOR v_key IN SELECT jsonb_object_keys(v_upsert_row)
  LOOP
    IF v_key LIKE 'form_%' THEN
      v_upsert_row := v_upsert_row - v_key;
    END IF;
  END LOOP;

  SELECT *
  INTO v_upsert_result
  FROM bulk_upsert_customers_from_import(
    p_rows := jsonb_build_array(v_upsert_row),
    p_merchant_id := p_merchant_id,
    p_create_wallet_ledger_entry := false
  )
  LIMIT 1;

  IF coalesce(v_upsert_result.success, false) IS NOT TRUE OR coalesce(v_upsert_result.valid, false) IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', coalesce(v_upsert_result.error_message, 'User upsert failed'),
      'errors', v_upsert_result.errors
    );
  END IF;

  v_user_id := (v_upsert_result.matched_user_ids)[1];

  v_submission := coalesce(v_normalized->'_survey_submission', '{}'::jsonb);
  v_submission_id := NULL;

  IF v_submission <> '{}'::jsonb THEN
    SELECT (submit_form_response(
      p_form_id := v_form_id,
      p_submission_data := v_submission,
      p_user_id := v_user_id,
      p_source := 'event_import',
      p_source_id := v_event_code
    )->>'submission_id')::uuid
    INTO v_submission_id;
  END IF;

  v_registration := fn_upsert_event_registration(
    p_merchant_id := p_merchant_id,
    p_event_id := v_event_id,
    p_event_code := v_event_code,
    p_user_id := v_user_id,
    p_member_name := v_normalized->>'user_accounts_fullname',
    p_member_tel := v_normalized->>'user_accounts_tel',
    p_form_submission_id := v_submission_id,
    p_source := coalesce(v_normalized->'_import_metadata'->>'source', 'event_import'),
    p_custom_data := coalesce(v_normalized->'_import_metadata', '{}'::jsonb)
  );

  RETURN jsonb_build_object(
    'success', true,
    'user_id', v_user_id,
    'submission_id', v_submission_id,
    'registration', v_registration,
    'imported', coalesce(v_upsert_result.imported_count, 0) > 0,
    'updated', coalesce(v_upsert_result.updated_count, 0) > 0
  );
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

-- ---------------------------------------------------------------------------
-- Admin BFFs
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.bff_admin_get_event_import_fields(p_event_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_merchant_id uuid;
  v_event_merchant uuid;
  v_role text;
  v_selection jsonb;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error('Unauthorized', 'Merchant context required', 'UNAUTHORIZED');
  END IF;

  SELECT merchant_id INTO v_event_merchant FROM syngenta_events_master WHERE id = p_event_id;
  IF v_event_merchant IS NULL OR v_event_merchant <> v_merchant_id THEN
    RETURN fn_response_error('Not found', 'Event not found', 'NOT_FOUND');
  END IF;

  v_role := fn_event_caller_role(p_event_id);
  IF auth.uid() IS NOT NULL
     AND v_role NOT IN ('owner', 'coordinator', 'superadmin')
     AND NOT check_admin_permission('user', 'create') THEN
    RETURN fn_response_error('Forbidden', 'Insufficient permissions', 'FORBIDDEN');
  END IF;

  v_selection := fn_build_event_import_field_selection(p_event_id);
  RETURN fn_response_success('Event import fields', NULL, v_selection);
EXCEPTION
  WHEN OTHERS THEN
    RETURN fn_response_error('Error', SQLERRM, 'INTERNAL_ERROR');
END;
$$;

CREATE OR REPLACE FUNCTION public.bff_admin_get_event_import_template_csv(p_event_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_merchant_id uuid;
  v_event_merchant uuid;
  v_role text;
  v_selection jsonb;
  v_columns jsonb;
  v_col jsonb;
  v_header_keys text := '';
  v_header_labels text := '';
  v_csv text;
  v_key text;
  v_label text;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error('Unauthorized', 'Merchant context required', 'UNAUTHORIZED');
  END IF;

  SELECT merchant_id INTO v_event_merchant FROM syngenta_events_master WHERE id = p_event_id;
  IF v_event_merchant IS NULL OR v_event_merchant <> v_merchant_id THEN
    RETURN fn_response_error('Not found', 'Event not found', 'NOT_FOUND');
  END IF;

  v_role := fn_event_caller_role(p_event_id);
  IF auth.uid() IS NOT NULL
     AND v_role NOT IN ('owner', 'coordinator', 'superadmin')
     AND NOT check_admin_permission('user', 'create') THEN
    RETURN fn_response_error('Forbidden', 'Insufficient permissions', 'FORBIDDEN');
  END IF;

  v_selection := fn_build_event_import_field_selection(p_event_id);
  v_columns := v_selection->'columns';

  FOR v_col IN SELECT value FROM jsonb_array_elements(v_columns)
  LOOP
    IF v_col->>'kind' = 'metadata' THEN
      CONTINUE;
    END IF;
    IF v_header_keys <> '' THEN
      v_header_keys := v_header_keys || ',';
      v_header_labels := v_header_labels || ',';
    END IF;
    v_key := replace(v_col->>'key', '"', '""');
    v_label := replace(coalesce(v_col->>'label', v_col->>'key'), '"', '""');
    v_header_keys := v_header_keys || format('"%s"', v_key);
    v_header_labels := v_header_labels || format('"%s"', v_label);
  END LOOP;

  v_csv := v_header_keys || E'\n' || v_header_labels || E'\n';
  RETURN fn_response_success('Template generated', NULL, jsonb_build_object('csv', v_csv, 'mime', 'text/csv', 'field_selection', v_selection));
EXCEPTION
  WHEN OTHERS THEN
    RETURN fn_response_error('Error', SQLERRM, 'INTERNAL_ERROR');
END;
$$;

-- ---------------------------------------------------------------------------
-- API import (synchronous)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.api_import_event_registrations(
  p_merchant_id uuid,
  p_event_code text,
  p_rows jsonb,
  p_match_on text[] DEFAULT ARRAY['tel'],
  p_dry_run boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event_id uuid;
  v_selection jsonb;
  v_row jsonb;
  v_result jsonb;
  v_results jsonb := '[]'::jsonb;
  v_imported int := 0;
  v_updated int := 0;
  v_failed int := 0;
  i int := 0;
BEGIN
  IF p_merchant_id IS NULL THEN
    RETURN fn_response_error('Bad request', 'p_merchant_id is required', 'VALIDATION_ERROR');
  END IF;
  IF coalesce(p_event_code, '') = '' THEN
    RETURN fn_response_error('Bad request', 'p_event_code is required', 'VALIDATION_ERROR');
  END IF;
  IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN
    RETURN fn_response_error('Bad request', 'p_rows must be a JSON array', 'VALIDATION_ERROR');
  END IF;

  SELECT id
  INTO v_event_id
  FROM syngenta_events_master
  WHERE merchant_id = p_merchant_id
    AND event_code = p_event_code
  LIMIT 1;

  IF v_event_id IS NULL THEN
    RETURN fn_response_error('Not found', format('Event not found: %s', p_event_code), 'NOT_FOUND');
  END IF;

  v_selection := fn_build_event_import_field_selection(v_event_id);

  FOR v_row IN SELECT value FROM jsonb_array_elements(p_rows)
  LOOP
    i := i + 1;
    IF p_dry_run THEN
      BEGIN
        v_result := jsonb_build_object(
          'row', i,
          'success', true,
          'normalized', fn_normalize_event_import_row(v_row, v_selection)
        );
      EXCEPTION WHEN OTHERS THEN
        v_result := jsonb_build_object('row', i, 'success', false, 'error', SQLERRM);
        v_failed := v_failed + 1;
      END;
    ELSE
      v_result := fn_process_event_registration_import_row(p_merchant_id, v_selection, v_row, p_match_on);
      v_result := v_result || jsonb_build_object('row', i);
      IF coalesce((v_result->>'success')::boolean, false) THEN
        IF coalesce((v_result->>'imported')::boolean, false) THEN
          v_imported := v_imported + 1;
        ELSIF coalesce((v_result->>'updated')::boolean, false) THEN
          v_updated := v_updated + 1;
        END IF;
      ELSE
        v_failed := v_failed + 1;
      END IF;
    END IF;
    v_results := v_results || jsonb_build_array(v_result);
  END LOOP;

  RETURN fn_response_success(
    'Import complete',
    format('%s imported, %s updated, %s failed', v_imported, v_updated, v_failed),
    jsonb_build_object(
      'event_id', v_event_id,
      'event_code', p_event_code,
      'dry_run', p_dry_run,
      'total_rows', i,
      'imported', v_imported,
      'updated', v_updated,
      'failed', v_failed,
      'results', v_results
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    RETURN fn_response_error('Error', SQLERRM, 'INTERNAL_ERROR');
END;
$$;

-- ---------------------------------------------------------------------------
-- Batch import (reuses customer import staging)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.bff_admin_start_event_registration_import(
  p_event_id uuid,
  p_batch_name text,
  p_file_name text DEFAULT NULL,
  p_import_mode text DEFAULT 'ongoing',
  p_match_on text[] DEFAULT ARRAY['tel'],
  p_file_url text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_merchant_id uuid;
  v_selection jsonb;
  v_batch_id uuid;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error('Unauthorized', 'Merchant context required', 'UNAUTHORIZED');
  END IF;

  IF NOT check_admin_permission('user', 'create') THEN
    RETURN fn_response_error('Forbidden', 'Insufficient permissions', 'FORBIDDEN');
  END IF;

  v_selection := fn_build_event_import_field_selection(p_event_id);

  IF (v_selection->>'merchant_id')::uuid <> v_merchant_id THEN
    RETURN fn_response_error('Not found', 'Event not found', 'NOT_FOUND');
  END IF;

  INSERT INTO bulk_import_batches (
    merchant_id, batch_name, file_name, status, import_type, import_mode,
    match_on, field_selection, file_url, metadata
  ) VALUES (
    v_merchant_id,
    p_batch_name,
    p_file_name,
    'validating',
    'event_registrations',
    coalesce(p_import_mode, 'ongoing'),
    coalesce(p_match_on, ARRAY['tel']),
    v_selection,
    p_file_url,
    jsonb_build_object('event_id', p_event_id, 'event_code', v_selection->>'event_code')
  )
  RETURNING id INTO v_batch_id;

  RETURN fn_response_success('Import batch created', NULL, jsonb_build_object('batch_id', v_batch_id));
EXCEPTION
  WHEN OTHERS THEN
    RETURN fn_response_error('Error', SQLERRM, 'INTERNAL_ERROR');
END;
$$;

CREATE OR REPLACE FUNCTION public.process_event_registration_import_chunk(
  p_batch_id uuid,
  p_chunk_size integer DEFAULT 250
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_batch bulk_import_batches%ROWTYPE;
  v_selection jsonb;
  v_row record;
  v_result jsonb;
  v_processed int := 0;
  v_imported int := 0;
  v_updated int := 0;
  v_failed int := 0;
BEGIN
  SELECT * INTO v_batch FROM bulk_import_batches WHERE id = p_batch_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN fn_response_error('Not found', 'Batch not found', 'NOT_FOUND');
  END IF;

  IF v_batch.import_type <> 'event_registrations' THEN
    RETURN fn_response_error('Bad request', 'Batch is not an event registration import', 'VALIDATION_ERROR');
  END IF;

  v_selection := v_batch.field_selection;

  IF v_batch.status IN ('pending', 'validating') THEN
    UPDATE bulk_import_batches SET status = 'processing', started_at = coalesce(started_at, now()) WHERE id = p_batch_id;
  END IF;

  FOR v_row IN
    SELECT *
    FROM user_import_staging
    WHERE batch_id = p_batch_id
      AND row_status = 'valid'
    ORDER BY row_num
    LIMIT coalesce(p_chunk_size, v_batch.chunk_size, 250)
  LOOP
    v_result := fn_process_event_registration_import_row(v_batch.merchant_id, v_selection, v_row.row_data, v_batch.match_on);

    IF coalesce((v_result->>'success')::boolean, false) THEN
      UPDATE user_import_staging
      SET row_status = CASE WHEN coalesce((v_result->>'imported')::boolean, false) THEN 'imported' ELSE 'updated' END,
          matched_user_id = (v_result->>'user_id')::uuid,
          processed_at = now(),
          row_errors = NULL
      WHERE row_num = v_row.row_num;

      IF coalesce((v_result->>'imported')::boolean, false) THEN v_imported := v_imported + 1; ELSE v_updated := v_updated + 1; END IF;
    ELSE
      UPDATE user_import_staging
      SET row_status = 'failed', row_errors = jsonb_build_array(jsonb_build_object('message', v_result->>'error')), processed_at = now()
      WHERE row_num = v_row.row_num;
      v_failed := v_failed + 1;
    END IF;

    v_processed := v_processed + 1;
    UPDATE bulk_import_batches
    SET processed_count = coalesce(processed_count, 0) + 1,
        last_processed_row_num = v_row.row_num,
        imported_users = coalesce(imported_users, 0) + CASE WHEN coalesce((v_result->>'imported')::boolean, false) THEN 1 ELSE 0 END,
        failed_count = coalesce(failed_count, 0) + CASE WHEN coalesce((v_result->>'success')::boolean, false) THEN 0 ELSE 1 END
    WHERE id = p_batch_id;
  END LOOP;

  IF NOT EXISTS (SELECT 1 FROM user_import_staging WHERE batch_id = p_batch_id AND row_status = 'valid') THEN
    UPDATE bulk_import_batches SET status = 'completed', completed_at = now() WHERE id = p_batch_id;
  END IF;

  RETURN fn_response_success('Chunk processed', NULL, jsonb_build_object(
    'batch_id', p_batch_id,
    'processed', v_processed,
    'imported', v_imported,
    'updated', v_updated,
    'failed', v_failed
  ));
EXCEPTION
  WHEN OTHERS THEN
    RETURN fn_response_error('Error', SQLERRM, 'INTERNAL_ERROR');
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_normalize_th_geo_name(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_import_truthy(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_normalize_import_tel(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_resolve_th_address_codes(text, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_resolve_form_field_input(uuid, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_build_event_import_field_selection(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_normalize_event_import_row(jsonb, jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_upsert_event_registration(uuid, uuid, text, uuid, text, text, uuid, text, jsonb, boolean, boolean, timestamptz) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_process_event_registration_import_row(uuid, jsonb, jsonb, text[]) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_admin_get_event_import_fields(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_admin_get_event_import_template_csv(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.api_import_event_registrations(uuid, text, jsonb, text[], boolean) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_admin_start_event_registration_import(uuid, text, text, text, text[], text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.process_event_registration_import_chunk(uuid, integer) TO authenticated, service_role;
