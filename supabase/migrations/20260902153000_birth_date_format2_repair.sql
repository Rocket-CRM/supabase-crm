-- Birth date Format-2 repair (Old CRM migrated users).
-- Old CRM stored migrated birthdays as (calendar date - 7h) at 17:00 UTC.
-- New CRM date-only column kept the truncated UTC date (off by 1 day).
-- Correct value: ((dateOfBirth)::timestamptz + interval '7 hours')::date
-- Source: stg_mongo_contacts.raw->>'dateOfBirth' LIKE '%T17:00:00%'
-- Apply via chokepoint_post_user_event (skip side effects + CDC).

CREATE TABLE IF NOT EXISTS public.birth_date_format2_repair_run (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid REFERENCES public.merchant_master(id),
  status text NOT NULL DEFAULT 'manifest',
  summary jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.birth_date_format2_repair_user (
  run_id uuid NOT NULL REFERENCES public.birth_date_format2_repair_run(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  merchant_id uuid NOT NULL,
  old_birth_date date NOT NULL,
  new_birth_date date NOT NULL,
  source_dob text NOT NULL,
  applied_at timestamptz,
  PRIMARY KEY (run_id, user_id)
);

CREATE INDEX IF NOT EXISTS birth_date_format2_repair_user_pending_idx
  ON public.birth_date_format2_repair_user (run_id)
  WHERE applied_at IS NULL;

REVOKE ALL ON public.birth_date_format2_repair_run FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.birth_date_format2_repair_user FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_birth_date_format2_build_manifest(
  p_merchant_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  v_run_id uuid;
  v_inserted bigint;
  v_sync_active boolean;
BEGIN
  IF p_merchant_id IS NOT NULL THEN
    SELECT COALESCE(s.sync_active, false)
      INTO v_sync_active
    FROM migration_merchant_status s
    WHERE s.merchant_uuid = p_merchant_id;

    IF v_sync_active THEN
      RAISE EXCEPTION 'migration sync_active is true for merchant % — pause sync first', p_merchant_id;
    END IF;
  END IF;

  INSERT INTO birth_date_format2_repair_run (merchant_id, status)
  VALUES (p_merchant_id, 'manifest')
  RETURNING id INTO v_run_id;

  INSERT INTO birth_date_format2_repair_user (
    run_id, user_id, merchant_id, old_birth_date, new_birth_date, source_dob
  )
  SELECT
    v_run_id,
    ua.id,
    ua.merchant_id,
    ua.birth_date,
    ((sc.raw->>'dateOfBirth')::timestamptz + interval '7 hours')::date,
    sc.raw->>'dateOfBirth'
  FROM user_accounts ua
  JOIN stg_mongo_users su ON su.mongo_id = ua.mongo_id
  JOIN stg_mongo_contacts sc ON sc.mongo_id = su.raw->>'contactId'
  WHERE sc.raw->>'dateOfBirth' LIKE '%T17:00:00%'
    AND ua.birth_date IS NOT NULL
    AND ua.deleted_at IS NULL
    AND ua.birth_date <> ((sc.raw->>'dateOfBirth')::timestamptz + interval '7 hours')::date
    AND (p_merchant_id IS NULL OR ua.merchant_id = p_merchant_id);

  GET DIAGNOSTICS v_inserted = ROW_COUNT;

  UPDATE birth_date_format2_repair_run
  SET status = 'ready',
      summary = jsonb_build_object(
        'merchant_id', p_merchant_id,
        'rows', v_inserted
      )
  WHERE id = v_run_id;

  RETURN jsonb_build_object(
    'run_id', v_run_id,
    'merchant_id', p_merchant_id,
    'rows', v_inserted
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_birth_date_format2_apply_batch(
  p_run_id uuid,
  p_limit integer DEFAULT 500,
  p_dry_run boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  v_row record;
  v_applied integer := 0;
BEGIN
  IF p_limit IS NULL OR p_limit < 1 THEN
    RAISE EXCEPTION 'fn_birth_date_format2_apply_batch: p_limit must be >= 1';
  END IF;

  FOR v_row IN
    SELECT user_id, merchant_id, new_birth_date
    FROM birth_date_format2_repair_user
    WHERE run_id = p_run_id
      AND applied_at IS NULL
    ORDER BY user_id
    LIMIT p_limit
  LOOP
    IF p_dry_run THEN
      v_applied := v_applied + 1;
      CONTINUE;
    END IF;

    PERFORM public.chokepoint_post_user_event(
      'update',
      v_row.merchant_id,
      v_row.user_id,
      jsonb_build_object('birth_date', v_row.new_birth_date::text),
      true,
      true,
      jsonb_build_object('actor_type', 'system', 'reason', 'birth_date_format2_repair'),
      format('birth_date_format2_repair:%s:%s', p_run_id, v_row.user_id),
      jsonb_build_object('_skip_emit', true)
    );

    UPDATE birth_date_format2_repair_user
    SET applied_at = now()
    WHERE run_id = p_run_id
      AND user_id = v_row.user_id;

    v_applied := v_applied + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'run_id', p_run_id,
    'dry_run', p_dry_run,
    'batch_applied', v_applied
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_birth_date_format2_build_manifest(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_birth_date_format2_apply_batch(uuid, integer, boolean) FROM PUBLIC, anon, authenticated;
