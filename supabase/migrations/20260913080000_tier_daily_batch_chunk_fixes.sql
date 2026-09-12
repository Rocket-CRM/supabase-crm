-- tier-daily-batch: use allowed processing_status 'error' (not 'failed');
-- skip maintain-batch rows when merchant has no tier_program_config for user_type.

CREATE OR REPLACE FUNCTION public.evaluate_and_apply_chunk_standard(
  p_merchant_id uuid,
  p_offset integer,
  p_limit integer,
  p_evaluation_date date DEFAULT CURRENT_DATE
)
RETURNS TABLE(
  out_user_id uuid,
  out_old_tier_id uuid,
  out_new_tier_id uuid,
  out_action text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET statement_timeout TO '60s'
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_record RECORD;
  v_eval jsonb;
  v_new_tier uuid;
  v_action text;
  v_deadline date;
  v_window_type public.tier_evaluation_window_type;
  v_locked boolean;
BEGIN
  FOR v_user_record IN
    SELECT ua.id, ua.tier_id AS current_tier_id, ua.user_type
    FROM public.tier_evaluation_tracking tet
    JOIN public.user_accounts ua
      ON ua.id = tet.user_id AND ua.merchant_id = tet.merchant_id
    WHERE tet.merchant_id = p_merchant_id
      AND tet.maintain_deadline IS NOT NULL
      AND tet.maintain_deadline <= p_evaluation_date
      AND EXISTS (
        SELECT 1
        FROM public.tier_program_config tpc
        WHERE tpc.merchant_id = tet.merchant_id
          AND tpc.user_type = ua.user_type
      )
    ORDER BY ua.id
    OFFSET p_offset
    LIMIT p_limit
  LOOP
    v_eval := public.evaluate_user_tier_status(v_user_record.id, p_merchant_id, p_evaluation_date);
    v_new_tier := NULLIF(v_eval->>'recommended_tier_id', '')::uuid;
    v_action := v_eval->>'recommended_action';
    v_locked := public.fn_user_tier_downgrade_is_locked(v_user_record.id, p_merchant_id);

    out_user_id := v_user_record.id;
    out_old_tier_id := v_user_record.current_tier_id;
    out_new_tier_id := v_new_tier;
    out_action := v_action;

    IF v_action = 'downgrade' AND v_locked THEN
      out_action := 'downgrade_locked';
      out_new_tier_id := v_user_record.current_tier_id;
      PERFORM public.ensure_tier_progress(v_user_record.id, p_merchant_id);
      SELECT cmd.deadline, cmd.window_type
      INTO v_deadline, v_window_type
      FROM public.calculate_maintain_deadline(p_merchant_id, v_user_record.user_type, p_evaluation_date) cmd;
      UPDATE public.tier_evaluation_tracking tet
      SET last_processed_at = NOW(),
          processing_status = 'completed',
          error_message = NULL,
          maintain_deadline = COALESCE(v_deadline, tet.maintain_deadline),
          maintain_window_type = COALESCE(v_window_type, tet.maintain_window_type),
          updated_at = NOW()
      WHERE tet.user_id = v_user_record.id AND tet.merchant_id = p_merchant_id;
      UPDATE public.tier_progress
      SET maintain_deadline = COALESCE(v_deadline, maintain_deadline)
      WHERE user_id = v_user_record.id AND merchant_id = p_merchant_id;

    ELSIF v_action IN ('upgrade', 'downgrade', 'assign_entry')
       AND v_new_tier IS NOT NULL
       AND v_user_record.current_tier_id IS DISTINCT FROM v_new_tier THEN
      PERFORM public.apply_tier_change(v_user_record.id, p_merchant_id, v_new_tier, v_action);

    ELSIF v_action = 'error' THEN
      UPDATE public.tier_evaluation_tracking
      SET last_processed_at = NOW(),
          processing_status = 'error',
          error_message = v_eval->>'error',
          updated_at = NOW()
      WHERE user_id = v_user_record.id AND merchant_id = p_merchant_id;

    ELSE
      PERFORM public.ensure_tier_progress(v_user_record.id, p_merchant_id);
      SELECT cmd.deadline, cmd.window_type
      INTO v_deadline, v_window_type
      FROM public.calculate_maintain_deadline(p_merchant_id, v_user_record.user_type, p_evaluation_date) cmd;
      UPDATE public.tier_evaluation_tracking tet
      SET last_processed_at = NOW(),
          processing_status = 'completed',
          error_message = NULL,
          maintain_deadline = COALESCE(v_deadline, tet.maintain_deadline),
          maintain_window_type = COALESCE(v_window_type, tet.maintain_window_type),
          updated_at = NOW()
      WHERE tet.user_id = v_user_record.id AND tet.merchant_id = p_merchant_id;
      UPDATE public.tier_progress
      SET maintain_deadline = COALESCE(v_deadline, maintain_deadline)
      WHERE user_id = v_user_record.id AND merchant_id = p_merchant_id;
    END IF;

    RETURN NEXT;
  END LOOP;
END;
$function$;
