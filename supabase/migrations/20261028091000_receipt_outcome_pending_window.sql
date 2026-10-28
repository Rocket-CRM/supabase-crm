-- =============================================================================
-- OUTCOMECHOICE-0276: the receipt-outcome "mission" card never came back after
-- midnight once a member had a receipt waiting for review.
--
-- Why: `fn_receipt_outcome_options` decides `unavailable_reason` from two
-- independent blockers.
--
--   limit_reached   -> `fn_check_progress_limits`, which windows completions
--                      with `fn_mission_calendar_boundary_start(..., merchant_tz)`.
--                      This half already resets at merchant-local midnight.
--   pending_review  -> a COUNT of `purchase_receipt_upload` rows with
--                      status='pending' and **no date filter at all**.
--
-- That count is all-time, so the daily quota coming back to 1 at midnight
-- changed nothing: a single stale pending receipt kept `1 >= 1` true forever
-- and the card stayed disabled ("รอการตรวจสอบ") until an admin cleared it.
-- Confirmed live on the จระเข้ campaign (mission 5521bcc1…, limit 1/person/day,
-- Asia/Bangkok): 10 pending receipts, none from the current day, every one of
-- those members still blocked.
--
-- Fix: give the pending count the same window the quota uses. A pending receipt
-- only reserves a slot inside the mission's own limit window, so it stops
-- blocking when that window rolls over. The CR is explicit that the reset must
-- not wait for approval ("ถึงแม้ว่า receipt นั้นจะยังไม่ approve").
--
-- Scope of change: this function body only. `upload_receipts` and
-- `fn_ocr_persist_channel_receipt` both re-validate by calling this same helper
-- and surface `OUTCOME_UNAVAILABLE`, so both write paths inherit the fix with
-- no Edge redeploy and no second copy of the rule.
--
-- Window selection mirrors `fn_check_progress_limits`: MAX() over the mission's
-- progress limits picks the shortest configured window. `all_time` limits
-- resolve to '-infinity', so a once-per-lifetime mission keeps today's
-- behaviour (a pending receipt still holds its only slot).
--
-- Note this function had no source of record in this repo before this file; the
-- definition below is the live one plus the windowed pending count.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_receipt_outcome_options(
  p_merchant_id uuid,
  p_user_id uuid,
  p_earning_channel_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_choice jsonb;
  v_opt jsonb;
  v_result jsonb := '[]'::jsonb;
  v_mission_id uuid;
  v_mission_name text;
  v_reason text;
  v_remaining integer;
  v_pending integer;
  v_mission_blocked boolean;
  v_tz text;
  v_window_start timestamptz;
BEGIN
  IF p_earning_channel_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT ec.config->'outcome_choice' INTO v_choice
  FROM earn_channel ec
  WHERE ec.id = p_earning_channel_id AND ec.merchant_id = p_merchant_id;

  IF v_choice IS NULL
     OR COALESCE((v_choice->>'enabled')::boolean, false) IS NOT TRUE
     OR jsonb_typeof(v_choice->'options') IS DISTINCT FROM 'array' THEN
    RETURN NULL;
  END IF;

  -- Mission picks need earn_currency=false. Channel OCR can do that on auto-approve.
  -- Deferred CRM confirm still cannot grant a mission from a receipt.
  v_mission_blocked := fn_merchant_deferred_crm_confirm(p_merchant_id);

  v_tz := fn_mission_merchant_tz(p_merchant_id);

  FOR v_opt IN SELECT * FROM jsonb_array_elements(v_choice->'options')
  LOOP
    IF v_opt->>'type' = 'points' THEN
      v_result := v_result || jsonb_build_array(jsonb_build_object(
        'type', 'points',
        'mission_id', NULL,
        'label', NULLIF(btrim(COALESCE(v_opt->>'label', '')), ''),
        'available', true,
        'unavailable_reason', NULL
      ));
    ELSIF v_opt->>'type' = 'mission' THEN
      v_mission_id := NULL;
      v_mission_name := NULL;
      BEGIN
        v_mission_id := NULLIF(v_opt->>'mission_id', '')::uuid;
      EXCEPTION WHEN invalid_text_representation THEN
        v_mission_id := NULL;
      END;
      SELECT m.mission_name INTO v_mission_name
      FROM mission m
      WHERE m.id = v_mission_id AND m.merchant_id = p_merchant_id;
      IF NOT FOUND THEN
        CONTINUE;
      END IF;

      v_reason := NULL;
      IF v_mission_blocked THEN
        v_reason := 'not_supported';
      ELSIF p_user_id IS NOT NULL THEN
        IF COALESCE((fn_mission_access_state(v_mission_id, p_user_id, p_merchant_id, now())->>'can_progress')::boolean, false) IS NOT TRUE THEN
          v_reason := 'not_available';
        ELSE
          v_remaining := fn_check_progress_limits(p_user_id, v_mission_id, 1000000);
          IF v_remaining < 1 THEN
            v_reason := 'limit_reached';
          ELSE
            -- Same window the progress quota uses, so a pending receipt stops
            -- reserving a slot when the window rolls over at merchant-local 00:00.
            SELECT MAX(fn_mission_calendar_boundary_start(
                     l.time_unit::text,
                     now(),
                     v_tz,
                     COALESCE(l.time_value, 1)
                   ))
              INTO v_window_start
            FROM mission_limit_progress l
            WHERE l.mission_id = v_mission_id
              AND l.scope::text IN ('user', 'total');

            SELECT COUNT(*)::integer INTO v_pending
            FROM purchase_receipt_upload pru
            WHERE pru.user_id = p_user_id
              AND pru.chosen_outcome_mission_id = v_mission_id
              AND pru.status = 'pending'
              AND (
                v_window_start IS NULL
                OR v_window_start = '-infinity'::timestamptz
                OR pru.created_at >= v_window_start
              );
            IF v_pending >= v_remaining THEN
              v_reason := 'pending_review';
            END IF;
          END IF;
        END IF;
      END IF;

      v_result := v_result || jsonb_build_array(jsonb_build_object(
        'type', 'mission',
        'mission_id', v_mission_id,
        'label', COALESCE(NULLIF(btrim(COALESCE(v_opt->>'label', '')), ''), v_mission_name),
        'available', v_reason IS NULL,
        'unavailable_reason', v_reason
      ));
    END IF;
  END LOOP;

  RETURN v_result;
END;
$function$;
