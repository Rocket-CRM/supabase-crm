-- Add set-based bulk apply for birth date Format-2 repair.
-- Row-by-row chokepoint is correct but ~50-100ms/user; bulk UPDATE is seconds per merchant.

CREATE OR REPLACE FUNCTION public.fn_birth_date_format2_apply_bulk(
  p_run_id uuid,
  p_dry_run boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  v_applied bigint;
BEGIN
  IF p_dry_run THEN
    SELECT COUNT(*) INTO v_applied
    FROM birth_date_format2_repair_user r
    JOIN user_accounts ua ON ua.id = r.user_id
    WHERE r.run_id = p_run_id
      AND r.applied_at IS NULL
      AND ua.birth_date IS DISTINCT FROM r.new_birth_date;

    RETURN jsonb_build_object('run_id', p_run_id, 'dry_run', true, 'rows', v_applied);
  END IF;

  WITH updated AS (
    UPDATE user_accounts ua
    SET birth_date = r.new_birth_date,
        skip_cdc = true,
        updated_at = now()
    FROM birth_date_format2_repair_user r
    WHERE r.run_id = p_run_id
      AND r.applied_at IS NULL
      AND ua.id = r.user_id
      AND ua.birth_date IS DISTINCT FROM r.new_birth_date
    RETURNING ua.id
  )
  UPDATE birth_date_format2_repair_user r
  SET applied_at = now()
  FROM updated u
  WHERE r.run_id = p_run_id
    AND r.user_id = u.id;

  GET DIAGNOSTICS v_applied = ROW_COUNT;

  RETURN jsonb_build_object('run_id', p_run_id, 'dry_run', false, 'rows', v_applied);
END;
$function$;

-- One-shot per merchant: build manifest + bulk apply (for sync-inactive merchants).
CREATE OR REPLACE FUNCTION public.fn_birth_date_format2_repair_merchant(
  p_merchant_id uuid,
  p_dry_run boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  v_manifest jsonb;
  v_run_id uuid;
  v_apply jsonb;
BEGIN
  v_manifest := fn_birth_date_format2_build_manifest(p_merchant_id);
  v_run_id := (v_manifest->>'run_id')::uuid;

  IF (v_manifest->>'rows')::bigint = 0 THEN
    RETURN v_manifest || jsonb_build_object('applied', 0, 'dry_run', p_dry_run);
  END IF;

  v_apply := fn_birth_date_format2_apply_bulk(v_run_id, p_dry_run);

  RETURN v_manifest || jsonb_build_object('apply', v_apply, 'dry_run', p_dry_run);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_birth_date_format2_apply_bulk(uuid, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_birth_date_format2_repair_merchant(uuid, boolean) FROM PUBLIC, anon, authenticated;
