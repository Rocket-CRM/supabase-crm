-- Event registration import: unified CSV/JSON payload + header validation

-- ---------------------------------------------------------------------------
-- CSV parsing helpers
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_split_csv_record(p_line text)
RETURNS text[]
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_fields text[] := '{}';
  v_field text := '';
  v_in_quote boolean := false;
  v_pos int := 1;
  v_len int;
  v_ch text;
BEGIN
  IF p_line IS NULL OR btrim(p_line) = '' THEN
    RETURN v_fields;
  END IF;

  v_len := length(p_line);

  WHILE v_pos <= v_len LOOP
    v_ch := substr(p_line, v_pos, 1);

    IF v_in_quote THEN
      IF v_ch = '"' THEN
        IF v_pos < v_len AND substr(p_line, v_pos + 1, 1) = '"' THEN
          v_field := v_field || '"';
          v_pos := v_pos + 1;
        ELSE
          v_in_quote := false;
        END IF;
      ELSE
        v_field := v_field || v_ch;
      END IF;
    ELSIF v_ch = '"' THEN
      v_in_quote := true;
    ELSIF v_ch = ',' THEN
      v_fields := array_append(v_fields, v_field);
      v_field := '';
    ELSE
      v_field := v_field || v_ch;
    END IF;

    v_pos := v_pos + 1;
  END LOOP;

  v_fields := array_append(v_fields, v_field);
  RETURN v_fields;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_normalize_csv_header_key(p_key text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT NULLIF(btrim(replace(coalesce(p_key, ''), E'\ufeff', '')), '');
$$;

CREATE OR REPLACE FUNCTION public.fn_is_event_import_label_header_row(
  p_key_row text[],
  p_candidate_row text[]
)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_key text;
  v_has_machine_key boolean := false;
  v_candidate_is_machine boolean := false;
BEGIN
  IF p_candidate_row IS NULL OR coalesce(array_length(p_candidate_row, 1), 0) = 0 THEN
    RETURN false;
  END IF;

  IF coalesce(array_length(p_key_row, 1), 0) <> coalesce(array_length(p_candidate_row, 1), 0) THEN
    RETURN false;
  END IF;

  FOREACH v_key IN ARRAY p_key_row LOOP
    IF v_key ~ '^(user_|form_)' THEN
      v_has_machine_key := true;
      EXIT;
    END IF;
  END LOOP;

  IF NOT v_has_machine_key THEN
    RETURN false;
  END IF;

  FOREACH v_key IN ARRAY p_candidate_row LOOP
    IF v_key ~ '^(user_|form_)' THEN
      v_candidate_is_machine := true;
      EXIT;
    END IF;
  END LOOP;

  RETURN NOT v_candidate_is_machine;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_validate_event_import_csv_headers(
  p_header_keys text[],
  p_field_selection jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_columns jsonb := coalesce(p_field_selection->'columns', '[]'::jsonb);
  v_legacy jsonb := coalesce(p_field_selection->'legacy_aliases', '{}'::jsonb);
  v_col jsonb;
  v_header text;
  v_canonical text;
  v_expected_keys text[] := '{}';
  v_required_keys text[] := '{}';
  v_seen_keys text[] := '{}';
  v_missing_required text[] := '{}';
  v_unknown_columns text[] := '{}';
  v_legacy_key text;
  v_legacy_val text;
  v_is_known boolean;
BEGIN
  IF coalesce(array_length(p_header_keys, 1), 0) = 0 THEN
    RETURN jsonb_build_object(
      'valid', false,
      'errors', jsonb_build_array(jsonb_build_object('code', 'EMPTY_HEADER', 'message', 'CSV header row is empty')),
      'warnings', '[]'::jsonb,
      'header_keys', '[]'::jsonb
    );
  END IF;

  FOR v_col IN SELECT value FROM jsonb_array_elements(v_columns)
  LOOP
    IF coalesce(v_col->>'kind', '') = 'metadata' THEN
      CONTINUE;
    END IF;
    v_expected_keys := array_append(v_expected_keys, v_col->>'key');
    IF coalesce((v_col->>'required')::boolean, false) THEN
      v_required_keys := array_append(v_required_keys, v_col->>'key');
    END IF;
  END LOOP;

  FOREACH v_header IN ARRAY p_header_keys LOOP
    v_header := fn_normalize_csv_header_key(v_header);
    IF v_header IS NULL THEN
      CONTINUE;
    END IF;

    v_canonical := v_header;
    IF v_legacy ? v_header THEN
      v_canonical := v_legacy->>v_header;
    END IF;

    v_is_known := v_canonical = ANY (v_expected_keys);

    IF NOT v_is_known THEN
      FOR v_legacy_key, v_legacy_val IN SELECT key, value FROM jsonb_each_text(v_legacy)
      LOOP
        IF v_header = v_legacy_key OR v_header = v_legacy_val THEN
          v_canonical := v_legacy_val;
          v_is_known := v_canonical = ANY (v_expected_keys);
          EXIT WHEN v_is_known;
        END IF;
      END LOOP;
    END IF;

    IF NOT v_is_known THEN
      v_unknown_columns := array_append(v_unknown_columns, v_header);
    END IF;

    IF v_canonical IS NOT NULL AND NOT (v_canonical = ANY (v_seen_keys)) THEN
      v_seen_keys := array_append(v_seen_keys, v_canonical);
    END IF;
  END LOOP;

  FOREACH v_header IN ARRAY v_required_keys LOOP
    IF NOT (v_header = ANY (v_seen_keys)) THEN
      v_missing_required := array_append(v_missing_required, v_header);
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'valid', coalesce(array_length(v_missing_required, 1), 0) = 0,
    'errors', CASE
      WHEN coalesce(array_length(v_missing_required, 1), 0) = 0 THEN '[]'::jsonb
      ELSE jsonb_build_array(jsonb_build_object(
        'code', 'MISSING_REQUIRED_COLUMNS',
        'message', 'CSV is missing required columns',
        'columns', to_jsonb(v_missing_required)
      ))
    END,
    'warnings', CASE
      WHEN coalesce(array_length(v_unknown_columns, 1), 0) = 0 THEN '[]'::jsonb
      ELSE jsonb_build_array(jsonb_build_object(
        'code', 'UNKNOWN_COLUMNS',
        'message', 'CSV contains columns that are not part of this event import template; they will be ignored',
        'columns', to_jsonb(v_unknown_columns)
      ))
    END,
    'header_keys', to_jsonb(p_header_keys),
    'mapped_keys', to_jsonb(v_seen_keys)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_parse_event_import_csv(
  p_csv text,
  p_field_selection jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_csv text;
  v_lines text[];
  v_line text;
  v_header_keys text[];
  v_label_keys text[];
  v_header_validation jsonb;
  v_rows jsonb := '[]'::jsonb;
  v_row jsonb;
  v_fields text[];
  v_idx int;
  v_col_idx int;
  v_data_start int := 2;
  v_nonempty int := 0;
BEGIN
  IF coalesce(btrim(p_csv), '') = '' THEN
    RETURN jsonb_build_object(
      'valid', false,
      'errors', jsonb_build_array(jsonb_build_object('code', 'EMPTY_PAYLOAD', 'message', 'CSV payload is empty')),
      'warnings', '[]'::jsonb,
      'rows', '[]'::jsonb
    );
  END IF;

  v_csv := replace(replace(coalesce(p_csv, ''), E'\r\n', E'\n'), E'\r', E'\n');
  v_lines := regexp_split_to_array(v_csv, E'\n');

  WHILE coalesce(array_length(v_lines, 1), 0) > 0 AND btrim(v_lines[1]) = '' LOOP
    v_lines := v_lines[2:array_length(v_lines, 1)];
  END LOOP;

  IF coalesce(array_length(v_lines, 1), 0) = 0 THEN
    RETURN jsonb_build_object(
      'valid', false,
      'errors', jsonb_build_array(jsonb_build_object('code', 'EMPTY_PAYLOAD', 'message', 'CSV payload is empty')),
      'warnings', '[]'::jsonb,
      'rows', '[]'::jsonb
    );
  END IF;

  v_header_keys := ARRAY(
    SELECT fn_normalize_csv_header_key(field)
    FROM unnest(fn_split_csv_record(v_lines[1])) AS field
  );

  IF coalesce(array_length(v_lines, 1), 0) >= 2 THEN
    v_label_keys := ARRAY(
      SELECT fn_normalize_csv_header_key(field)
      FROM unnest(fn_split_csv_record(v_lines[2])) AS field
    );
    IF fn_is_event_import_label_header_row(v_header_keys, v_label_keys) THEN
      v_data_start := 3;
    END IF;
  END IF;

  IF p_field_selection IS NOT NULL THEN
    v_header_validation := fn_validate_event_import_csv_headers(v_header_keys, p_field_selection);
    IF coalesce((v_header_validation->>'valid')::boolean, false) IS NOT TRUE THEN
      RETURN jsonb_build_object(
        'valid', false,
        'errors', v_header_validation->'errors',
        'warnings', coalesce(v_header_validation->'warnings', '[]'::jsonb),
        'header_validation', v_header_validation,
        'rows', '[]'::jsonb
      );
    END IF;
  ELSE
    v_header_validation := jsonb_build_object('valid', true, 'errors', '[]'::jsonb, 'warnings', '[]'::jsonb);
  END IF;

  FOR v_idx IN v_data_start..coalesce(array_length(v_lines, 1), 0)
  LOOP
    v_line := btrim(v_lines[v_idx]);
    IF v_line = '' THEN
      CONTINUE;
    END IF;

    v_fields := fn_split_csv_record(v_line);
    v_row := '{}'::jsonb;

    FOR v_col_idx IN 1..coalesce(array_length(v_header_keys, 1), 0)
    LOOP
      IF v_header_keys[v_col_idx] IS NULL OR v_header_keys[v_col_idx] = '' THEN
        CONTINUE;
      END IF;
      v_row := jsonb_set(
        v_row,
        ARRAY[v_header_keys[v_col_idx]],
        to_jsonb(coalesce(v_fields[v_col_idx], '')),
        true
      );
    END LOOP;

    IF v_row <> '{}'::jsonb THEN
      v_rows := v_rows || jsonb_build_array(v_row);
      v_nonempty := v_nonempty + 1;
    END IF;
  END LOOP;

  IF v_nonempty = 0 THEN
    RETURN jsonb_build_object(
      'valid', false,
      'errors', jsonb_build_array(jsonb_build_object('code', 'NO_DATA_ROWS', 'message', 'CSV contains a header but no data rows')),
      'warnings', coalesce(v_header_validation->'warnings', '[]'::jsonb),
      'header_validation', v_header_validation,
      'rows', '[]'::jsonb
    );
  END IF;

  RETURN jsonb_build_object(
    'valid', true,
    'errors', '[]'::jsonb,
    'warnings', coalesce(v_header_validation->'warnings', '[]'::jsonb),
    'header_validation', v_header_validation,
    'rows', v_rows
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_parse_event_import_payload(
  p_payload text,
  p_field_selection jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_trimmed text;
  v_rows jsonb;
BEGIN
  v_trimmed := btrim(coalesce(p_payload, ''));

  IF v_trimmed = '' THEN
    RETURN jsonb_build_object(
      'valid', false,
      'format', 'empty',
      'errors', jsonb_build_array(jsonb_build_object('code', 'EMPTY_PAYLOAD', 'message', 'Import payload is empty')),
      'warnings', '[]'::jsonb,
      'rows', '[]'::jsonb
    );
  END IF;

  IF left(v_trimmed, 1) = '[' THEN
    BEGIN
      v_rows := v_trimmed::jsonb;
    EXCEPTION
      WHEN OTHERS THEN
        RETURN jsonb_build_object(
          'valid', false,
          'format', 'json',
          'errors', jsonb_build_array(jsonb_build_object('code', 'INVALID_JSON', 'message', 'Payload looks like JSON but could not be parsed')),
          'warnings', '[]'::jsonb,
          'rows', '[]'::jsonb
        );
    END;

    IF jsonb_typeof(v_rows) <> 'array' THEN
      RETURN jsonb_build_object(
        'valid', false,
        'format', 'json',
        'errors', jsonb_build_array(jsonb_build_object('code', 'INVALID_JSON', 'message', 'JSON payload must be an array of row objects')),
        'warnings', '[]'::jsonb,
        'rows', '[]'::jsonb
      );
    END IF;

    RETURN jsonb_build_object(
      'valid', true,
      'format', 'json',
      'errors', '[]'::jsonb,
      'warnings', '[]'::jsonb,
      'rows', v_rows
    );
  END IF;

  RETURN fn_parse_event_import_csv(v_trimmed, p_field_selection) || jsonb_build_object('format', 'csv');
END;
$$;

-- ---------------------------------------------------------------------------
-- Unified API import (CSV or JSON payload)
-- ---------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.api_import_event_registrations(uuid, text, jsonb, text[], boolean);

CREATE OR REPLACE FUNCTION public.api_import_event_registrations(
  p_merchant_id uuid,
  p_event_code text,
  p_payload text,
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
  v_parsed jsonb;
  v_rows jsonb;
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
  IF coalesce(btrim(p_payload), '') = '' THEN
    RETURN fn_response_error('Bad request', 'p_payload is required (CSV text or JSON array)', 'VALIDATION_ERROR');
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
  v_parsed := fn_parse_event_import_payload(p_payload, v_selection);

  IF coalesce((v_parsed->>'valid')::boolean, false) IS NOT TRUE THEN
    RETURN fn_response_error(
      'Validation failed',
      coalesce(v_parsed->'errors'->0->>'message', 'Import payload failed validation'),
      'VALIDATION_ERROR',
      jsonb_build_object(
        'format', v_parsed->>'format',
        'errors', coalesce(v_parsed->'errors', '[]'::jsonb),
        'warnings', coalesce(v_parsed->'warnings', '[]'::jsonb),
        'header_validation', v_parsed->'header_validation'
      )
    );
  END IF;

  v_rows := coalesce(v_parsed->'rows', '[]'::jsonb);

  FOR v_row IN SELECT value FROM jsonb_array_elements(v_rows)
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
      'payload_format', v_parsed->>'format',
      'dry_run', p_dry_run,
      'total_rows', i,
      'imported', v_imported,
      'updated', v_updated,
      'failed', v_failed,
      'warnings', coalesce(v_parsed->'warnings', '[]'::jsonb),
      'header_validation', v_parsed->'header_validation',
      'results', v_results
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    RETURN fn_response_error('Error', SQLERRM, 'INTERNAL_ERROR');
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_split_csv_record(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_normalize_csv_header_key(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_is_event_import_label_header_row(text[], text[]) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_validate_event_import_csv_headers(text[], jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_parse_event_import_csv(text, jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_parse_event_import_payload(text, jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.api_import_event_registrations(uuid, text, text, text[], boolean) TO authenticated, service_role;
