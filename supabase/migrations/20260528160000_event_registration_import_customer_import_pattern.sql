-- Event registration import: align with customer import (multi-step JSON RPCs)
-- CSV is parsed client-side; DB receives JSON rows via bff_admin_stage_user_import_rows

-- ---------------------------------------------------------------------------
-- Restore batch starter (removed by async_csv migration)
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
    coalesce(nullif(btrim(p_file_name), ''), 'upload.csv'),
    'validating',
    'event_registrations',
    coalesce(p_import_mode, 'ongoing'),
    coalesce(p_match_on, ARRAY['tel']),
    v_selection,
    p_file_url,
    jsonb_build_object('event_id', p_event_id, 'event_code', v_selection->>'event_code')
  )
  RETURNING id INTO v_batch_id;

  RETURN fn_response_success('Import batch created', NULL, jsonb_build_object(
    'batch_id', v_batch_id,
    'event_id', p_event_id,
    'event_code', v_selection->>'event_code',
    'field_selection', v_selection
  ));
EXCEPTION
  WHEN OTHERS THEN
    RETURN fn_response_error('Error', SQLERRM, 'INTERNAL_ERROR');
END;
$$;

-- ---------------------------------------------------------------------------
-- Optional: validate CSV headers before staging (client still parses rows)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.bff_admin_validate_event_import_csv(
  p_event_id uuid,
  p_csv text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_merchant_id uuid;
  v_selection jsonb;
  v_parsed jsonb;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error('Unauthorized', 'Merchant context required', 'UNAUTHORIZED');
  END IF;

  IF NOT check_admin_permission('user', 'create') THEN
    RETURN fn_response_error('Forbidden', 'Insufficient permissions', 'FORBIDDEN');
  END IF;

  IF coalesce(btrim(p_csv), '') = '' THEN
    RETURN fn_response_error('Bad request', 'p_csv is required', 'VALIDATION_ERROR');
  END IF;

  v_selection := fn_build_event_import_field_selection(p_event_id);

  IF (v_selection->>'merchant_id')::uuid <> v_merchant_id THEN
    RETURN fn_response_error('Not found', 'Event not found', 'NOT_FOUND');
  END IF;

  v_parsed := fn_parse_event_import_csv(p_csv, v_selection);

  RETURN fn_response_success(
    CASE WHEN coalesce((v_parsed->>'valid')::boolean, false) THEN 'CSV valid' ELSE 'CSV invalid' END,
    NULL,
    jsonb_build_object(
      'valid', coalesce((v_parsed->>'valid')::boolean, false),
      'errors', coalesce(v_parsed->'errors', '[]'::jsonb),
      'warnings', coalesce(v_parsed->'warnings', '[]'::jsonb),
      'header_validation', v_parsed->'header_validation',
      'row_count', jsonb_array_length(coalesce(v_parsed->'rows', '[]'::jsonb)),
      'field_selection', v_selection
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    RETURN fn_response_error('Error', SQLERRM, 'INTERNAL_ERROR');
END;
$$;

-- ---------------------------------------------------------------------------
-- Kickoff async processing (parity with admin-user-import-kickoff edge fn)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.bff_admin_kickoff_event_registration_import(p_batch_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_merchant_id uuid;
  v_batch bulk_import_batches%ROWTYPE;
  v_kickoff jsonb;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error('Unauthorized', 'Merchant context required', 'UNAUTHORIZED');
  END IF;

  IF NOT check_admin_permission('user', 'create') THEN
    RETURN fn_response_error('Forbidden', 'Insufficient permissions', 'FORBIDDEN');
  END IF;

  SELECT * INTO v_batch
  FROM bulk_import_batches
  WHERE id = p_batch_id
    AND merchant_id = v_merchant_id;

  IF NOT FOUND THEN
    RETURN fn_response_error('Not found', 'Batch not found', 'NOT_FOUND');
  END IF;

  IF v_batch.import_type <> 'event_registrations' THEN
    RETURN fn_response_error('Bad request', 'Batch is not an event registration import', 'VALIDATION_ERROR');
  END IF;

  IF v_batch.status <> 'pending' THEN
    RETURN fn_response_error(
      'Batch not ready',
      format('Expected status pending, got %s. Call bff_admin_run_user_import first.', v_batch.status),
      'BAD_STATE'
    );
  END IF;

  v_kickoff := fn_kickoff_event_registration_import(p_batch_id);

  IF coalesce((v_kickoff->>'success')::boolean, false) IS NOT TRUE THEN
    RETURN v_kickoff;
  END IF;

  RETURN fn_response_success(
    'Import kickoff queued',
    'Poll bff_admin_get_user_import_progress for status.',
    jsonb_build_object(
      'batch_id', p_batch_id,
      'kickoff', v_kickoff->'data'
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    RETURN fn_response_error('Error', SQLERRM, 'INTERNAL_ERROR');
END;
$$;

-- ---------------------------------------------------------------------------
-- Remove monolithic CSV upload path
-- ---------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.api_upload_event_registration_import_csv(uuid, text, text, text, text, text, text[]);
DROP FUNCTION IF EXISTS public.fn_stage_event_registration_import_rows(uuid, uuid, jsonb);
DROP FUNCTION IF EXISTS public.fn_queue_event_registration_import_batch(uuid);

GRANT EXECUTE ON FUNCTION public.bff_admin_start_event_registration_import(uuid, text, text, text, text[], text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_admin_validate_event_import_csv(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_admin_kickoff_event_registration_import(uuid) TO authenticated, service_role;
