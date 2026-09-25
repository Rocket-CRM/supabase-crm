-- Event registration import: async CSV-only public surface
-- Upload: api_upload_event_registration_import_csv
-- Progress: api_get_event_registration_import_progress

-- ---------------------------------------------------------------------------
-- Internal: stage parsed rows
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_stage_event_registration_import_rows(
  p_batch_id uuid,
  p_merchant_id uuid,
  p_rows jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_batch bulk_import_batches%ROWTYPE;
  v_row jsonb;
  v_csv_row int;
  v_errors jsonb;
  v_status text;
  v_inserted int := 0;
  v_valid int := 0;
  v_invalid int := 0;
  v_value text;
  v_offset int;
  v_match_on_pretty text;
BEGIN
  SELECT * INTO v_batch
  FROM bulk_import_batches
  WHERE id = p_batch_id
    AND merchant_id = p_merchant_id;

  IF NOT FOUND THEN
    RETURN fn_response_error('Batch not found', NULL, 'NOT_FOUND');
  END IF;

  IF v_batch.import_type <> 'event_registrations' THEN
    RETURN fn_response_error('Bad request', 'Batch is not an event registration import', 'VALIDATION_ERROR');
  END IF;

  IF v_batch.status NOT IN ('validating', 'pending') THEN
    RETURN fn_response_error('Batch not stageable', 'Status is ' || v_batch.status, 'BAD_STATE');
  END IF;

  v_match_on_pretty := array_to_string(v_batch.match_on, ', ');
  v_offset := coalesce((SELECT max(csv_row_num) FROM user_import_staging WHERE batch_id = p_batch_id), 0);

  FOR v_row IN SELECT value FROM jsonb_array_elements(coalesce(p_rows, '[]'::jsonb))
  LOOP
    v_offset := v_offset + 1;
    v_csv_row := coalesce((v_row->>'__csv_row')::int, v_offset);
    v_errors := '[]'::jsonb;

    IF NOT EXISTS (
      SELECT 1
      FROM unnest(v_batch.match_on) k
      WHERE nullif(btrim(coalesce(v_row->>('user_accounts_' || k), v_row->>k)), '') IS NOT NULL
    ) THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'error_code', 'NO_MATCH_KEY',
        'message', format('At least one match key must be supplied: [%s]', v_match_on_pretty)
      ));
    END IF;

    v_value := nullif(btrim(coalesce(v_row->>'user_accounts_tel', v_row->>'tel')), '');
    IF v_value IS NOT NULL AND v_value !~ '^\+' THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'error_code', 'INVALID_TEL',
        'field_key', 'user_accounts_tel',
        'message', 'tel must start with + and country code'
      ));
    END IF;

    v_status := CASE WHEN jsonb_array_length(v_errors) = 0 THEN 'valid' ELSE 'invalid' END;
    IF v_status = 'valid' THEN
      v_valid := v_valid + 1;
    ELSE
      v_invalid := v_invalid + 1;
    END IF;

    INSERT INTO user_import_staging (
      batch_id, merchant_id, csv_row_num, row_data, row_status, row_errors
    ) VALUES (
      p_batch_id,
      p_merchant_id,
      v_csv_row,
      v_row,
      v_status,
      CASE WHEN jsonb_array_length(v_errors) = 0 THEN NULL ELSE v_errors END
    );

    v_inserted := v_inserted + 1;
  END LOOP;

  UPDATE bulk_import_batches
  SET total_rows = (SELECT count(*) FROM user_import_staging WHERE batch_id = p_batch_id)
  WHERE id = p_batch_id;

  RETURN fn_response_success('Rows staged', NULL, jsonb_build_object(
    'inserted', v_inserted,
    'valid', v_valid,
    'invalid', v_invalid
  ));
EXCEPTION
  WHEN OTHERS THEN
    RETURN fn_response_error('Failed to stage rows', SQLERRM, 'INTERNAL_ERROR');
END;
$$;

-- ---------------------------------------------------------------------------
-- Internal: queue batch (validating -> pending)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_queue_event_registration_import_batch(p_batch_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_batch bulk_import_batches%ROWTYPE;
  v_valid int;
  v_invalid int;
BEGIN
  SELECT * INTO v_batch FROM bulk_import_batches WHERE id = p_batch_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN fn_response_error('Batch not found', NULL, 'NOT_FOUND');
  END IF;

  IF v_batch.import_type <> 'event_registrations' THEN
    RETURN fn_response_error('Bad request', 'Batch is not an event registration import', 'VALIDATION_ERROR');
  END IF;

  IF v_batch.status <> 'validating' THEN
    RETURN fn_response_error('Batch not in validating state', 'Status is ' || v_batch.status, 'BAD_STATE');
  END IF;

  SELECT count(*) FILTER (WHERE row_status = 'valid'),
         count(*) FILTER (WHERE row_status = 'invalid')
  INTO v_valid, v_invalid
  FROM user_import_staging
  WHERE batch_id = p_batch_id;

  IF v_valid = 0 THEN
    UPDATE bulk_import_batches
    SET status = 'failed',
        completed_at = now(),
        validation_errors = jsonb_build_array(jsonb_build_object(
          'code', 'NO_VALID_ROWS',
          'message', 'No valid rows to import',
          'invalid', v_invalid
        ))
    WHERE id = p_batch_id;

    RETURN fn_response_error('No valid rows to import', NULL, 'NO_VALID_ROWS', jsonb_build_object(
      'invalid', v_invalid
    ));
  END IF;

  UPDATE bulk_import_batches
  SET status = 'pending',
      total_rows = v_valid + v_invalid
  WHERE id = p_batch_id;

  RETURN fn_response_success('Import queued', NULL, jsonb_build_object(
    'valid', v_valid,
    'invalid', v_invalid
  ));
END;
$$;

-- ---------------------------------------------------------------------------
-- Internal: async worker (pg_net chain)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_run_event_registration_import_worker(p_batch_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_batch bulk_import_batches%ROWTYPE;
  v_result jsonb;
  v_supabase_url text;
  v_service_key text;
  v_request_id bigint;
BEGIN
  IF p_batch_id IS NULL THEN
    RETURN fn_response_error('Bad request', 'p_batch_id is required', 'VALIDATION_ERROR');
  END IF;

  v_result := process_event_registration_import_chunk(p_batch_id, NULL);

  SELECT * INTO v_batch FROM bulk_import_batches WHERE id = p_batch_id;
  IF NOT FOUND THEN
    RETURN fn_response_error('Batch not found', NULL, 'NOT_FOUND');
  END IF;

  IF v_batch.status IN ('pending', 'processing')
     AND EXISTS (
       SELECT 1
       FROM user_import_staging
       WHERE batch_id = p_batch_id
         AND row_status = 'valid'
     ) THEN
    SELECT decrypted_secret INTO v_supabase_url FROM vault.decrypted_secrets WHERE name = 'supabase_url';
    SELECT decrypted_secret INTO v_service_key FROM vault.decrypted_secrets WHERE name = 'service_role_key';

    v_request_id := net.http_post(
      url := v_supabase_url || '/rest/v1/rpc/fn_run_event_registration_import_worker',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_service_key,
        'apikey', v_service_key
      ),
      body := jsonb_build_object('p_batch_id', p_batch_id)
    );
  END IF;

  RETURN fn_response_success('Worker tick', NULL, jsonb_build_object(
    'batch_id', p_batch_id,
    'batch_status', v_batch.status,
    'chunk', v_result->'data',
    'next_request_id', v_request_id
  ));
EXCEPTION
  WHEN OTHERS THEN
    RETURN fn_response_error('Worker failed', SQLERRM, 'INTERNAL_ERROR');
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_kickoff_event_registration_import(p_batch_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_supabase_url text;
  v_service_key text;
  v_request_id bigint;
BEGIN
  SELECT decrypted_secret INTO v_supabase_url FROM vault.decrypted_secrets WHERE name = 'supabase_url';
  SELECT decrypted_secret INTO v_service_key FROM vault.decrypted_secrets WHERE name = 'service_role_key';

  v_request_id := net.http_post(
    url := v_supabase_url || '/rest/v1/rpc/fn_run_event_registration_import_worker',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_service_key,
      'apikey', v_service_key
    ),
    body := jsonb_build_object('p_batch_id', p_batch_id)
  );

  RETURN fn_response_success('Import kickoff queued', NULL, jsonb_build_object(
    'batch_id', p_batch_id,
    'request_id', v_request_id
  ));
EXCEPTION
  WHEN OTHERS THEN
    RETURN fn_response_error('Kickoff failed', SQLERRM, 'INTERNAL_ERROR');
END;
$$;

-- ---------------------------------------------------------------------------
-- Public API: upload CSV (async)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.api_upload_event_registration_import_csv(
  p_merchant_id uuid,
  p_event_code text,
  p_csv text,
  p_batch_name text DEFAULT NULL,
  p_file_name text DEFAULT NULL,
  p_import_mode text DEFAULT 'ongoing',
  p_match_on text[] DEFAULT ARRAY['tel']
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
  v_batch_id uuid;
  v_stage jsonb;
  v_queue jsonb;
BEGIN
  IF p_merchant_id IS NULL THEN
    RETURN fn_response_error('Bad request', 'p_merchant_id is required', 'VALIDATION_ERROR');
  END IF;
  IF coalesce(btrim(p_event_code), '') = '' THEN
    RETURN fn_response_error('Bad request', 'p_event_code is required', 'VALIDATION_ERROR');
  END IF;
  IF coalesce(btrim(p_csv), '') = '' THEN
    RETURN fn_response_error('Bad request', 'p_csv is required', 'VALIDATION_ERROR');
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
  v_parsed := fn_parse_event_import_csv(p_csv, v_selection);

  IF coalesce((v_parsed->>'valid')::boolean, false) IS NOT TRUE THEN
    RETURN fn_response_error(
      'Validation failed',
      coalesce(v_parsed->'errors'->0->>'message', 'CSV failed validation'),
      'VALIDATION_ERROR',
      jsonb_build_object(
        'errors', coalesce(v_parsed->'errors', '[]'::jsonb),
        'warnings', coalesce(v_parsed->'warnings', '[]'::jsonb),
        'header_validation', v_parsed->'header_validation'
      )
    );
  END IF;

  INSERT INTO bulk_import_batches (
    merchant_id, batch_name, file_name, status, import_type, import_mode,
    match_on, field_selection, metadata
  ) VALUES (
    p_merchant_id,
    coalesce(nullif(btrim(p_batch_name), ''), format('Event import %s', p_event_code)),
    coalesce(nullif(btrim(p_file_name), ''), 'upload.csv'),
    'validating',
    'event_registrations',
    coalesce(p_import_mode, 'ongoing'),
    coalesce(p_match_on, ARRAY['tel']),
    v_selection,
    jsonb_build_object('event_id', v_event_id, 'event_code', p_event_code)
  )
  RETURNING id INTO v_batch_id;

  v_stage := fn_stage_event_registration_import_rows(
    p_batch_id := v_batch_id,
    p_merchant_id := p_merchant_id,
    p_rows := v_parsed->'rows'
  );

  IF coalesce((v_stage->>'success')::boolean, false) IS NOT TRUE THEN
    UPDATE bulk_import_batches SET status = 'failed', completed_at = now() WHERE id = v_batch_id;
    RETURN v_stage;
  END IF;

  v_queue := fn_queue_event_registration_import_batch(v_batch_id);
  IF coalesce((v_queue->>'success')::boolean, false) IS NOT TRUE THEN
    RETURN v_queue || jsonb_build_object('data', coalesce(v_queue->'data', '{}'::jsonb) || jsonb_build_object('batch_id', v_batch_id));
  END IF;

  PERFORM fn_kickoff_event_registration_import(v_batch_id);

  RETURN fn_response_success(
    'Import queued',
    'Processing asynchronously. Poll progress with api_get_event_registration_import_progress.',
    jsonb_build_object(
      'batch_id', v_batch_id,
      'event_id', v_event_id,
      'event_code', p_event_code,
      'status', 'pending',
      'staged', v_stage->'data',
      'warnings', coalesce(v_parsed->'warnings', '[]'::jsonb),
      'header_validation', v_parsed->'header_validation'
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    RETURN fn_response_error('Error', SQLERRM, 'INTERNAL_ERROR');
END;
$$;

-- ---------------------------------------------------------------------------
-- Public API: progress
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.api_get_event_registration_import_progress(
  p_merchant_id uuid,
  p_batch_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_batch bulk_import_batches%ROWTYPE;
  v_counts jsonb;
BEGIN
  IF p_merchant_id IS NULL OR p_batch_id IS NULL THEN
    RETURN fn_response_error('Bad request', 'p_merchant_id and p_batch_id are required', 'VALIDATION_ERROR');
  END IF;

  SELECT * INTO v_batch
  FROM bulk_import_batches
  WHERE id = p_batch_id
    AND merchant_id = p_merchant_id;

  IF NOT FOUND THEN
    RETURN fn_response_error('Not found', 'Batch not found', 'NOT_FOUND');
  END IF;

  IF v_batch.import_type <> 'event_registrations' THEN
    RETURN fn_response_error('Bad request', 'Batch is not an event registration import', 'VALIDATION_ERROR');
  END IF;

  SELECT jsonb_object_agg(row_status, c)
  INTO v_counts
  FROM (
    SELECT row_status, count(*) AS c
    FROM user_import_staging
    WHERE batch_id = p_batch_id
    GROUP BY row_status
  ) s;

  RETURN fn_response_success('Progress', NULL, jsonb_build_object(
    'batch_id', v_batch.id,
    'event_id', v_batch.metadata->>'event_id',
    'event_code', v_batch.metadata->>'event_code',
    'status', v_batch.status,
    'import_mode', v_batch.import_mode,
    'match_on', v_batch.match_on,
    'total_rows', v_batch.total_rows,
    'processed_count', v_batch.processed_count,
    'imported_users', v_batch.imported_users,
    'failed_count', v_batch.failed_count,
    'started_at', v_batch.started_at,
    'completed_at', v_batch.completed_at,
    'metadata', v_batch.metadata,
    'error_sample', coalesce(v_batch.validation_errors, '[]'::jsonb),
    'row_status_counts', coalesce(v_counts, '{}'::jsonb)
  ));
EXCEPTION
  WHEN OTHERS THEN
    RETURN fn_response_error('Error', SQLERRM, 'INTERNAL_ERROR');
END;
$$;

-- ---------------------------------------------------------------------------
-- Remove sync / redundant public entry points
-- ---------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.api_import_event_registrations(uuid, text, jsonb, text[], boolean);
DROP FUNCTION IF EXISTS public.api_import_event_registrations(uuid, text, text, text[], boolean);
DROP FUNCTION IF EXISTS public.bff_admin_start_event_registration_import(uuid, text, text, text, text[], text);

GRANT EXECUTE ON FUNCTION public.fn_stage_event_registration_import_rows(uuid, uuid, jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_queue_event_registration_import_batch(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_run_event_registration_import_worker(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_kickoff_event_registration_import(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.api_upload_event_registration_import_csv(uuid, text, text, text, text, text, text[]) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.api_get_event_registration_import_progress(uuid, uuid) TO authenticated, service_role;
