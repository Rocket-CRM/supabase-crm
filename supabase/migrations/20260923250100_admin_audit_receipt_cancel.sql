-- Phase 8: receipt cancel writes admin_audit_log instead of purchase_receipt_upload_review_audit.

CREATE OR REPLACE FUNCTION public.fn_cancel_approved_receipt_upload(
  p_receipt_upload_id uuid,
  p_reason text,
  p_admin_id uuid,
  p_merchant_id uuid,
  p_lang text DEFAULT 'en'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_receipt public.purchase_receipt_upload%ROWTYPE;
  v_cancel_result jsonb;
  v_before jsonb;
  v_after jsonb;
BEGIN
  IF NULLIF(TRIM(p_reason), '') IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'title', fn_member_envelope_message('invalid_request_title', p_lang),
      'description', 'Cancellation reason is required',
      'data', null
    );
  END IF;

  SELECT * INTO v_receipt
  FROM public.purchase_receipt_upload pru
  WHERE pru.id = p_receipt_upload_id
    AND pru.merchant_id = p_merchant_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'title', fn_member_envelope_message('not_found_title', p_lang), 'description', null, 'data', null);
  END IF;

  IF v_receipt.status = 'cancelled' THEN
    RETURN jsonb_build_object('success', true, 'title', null, 'description', null, 'data', jsonb_build_object('idempotent', true));
  END IF;

  IF v_receipt.status IS DISTINCT FROM 'approved' THEN
    RETURN jsonb_build_object('success', false, 'title', fn_member_envelope_message('invalid_request_title', p_lang), 'description', 'Only approved receipts can be cancelled', 'data', null);
  END IF;

  v_before := to_jsonb(v_receipt);

  IF v_receipt.purchase_ledger_id IS NOT NULL THEN
    v_cancel_result := public.api_cancel_purchase(
      p_merchant_id,
      ARRAY[v_receipt.purchase_ledger_id],
      TRIM(p_reason),
      true,
      'best_effort'
    );
    IF COALESCE((v_cancel_result->>'success')::boolean, false) IS NOT TRUE THEN
      RETURN v_cancel_result;
    END IF;
  ELSIF v_receipt.crm_sync_status = 'queued' THEN
    UPDATE public.purchase_receipt_upload
    SET crm_sync_status = 'not_applicable',
        updated_at = now()
    WHERE id = p_receipt_upload_id;
  END IF;

  UPDATE public.purchase_receipt_upload
  SET status = 'cancelled',
      notes = COALESCE(notes, '') || CASE WHEN COALESCE(notes, '') = '' THEN '' ELSE E'\n' END || '[Cancelled] ' || TRIM(p_reason),
      updated_at = now()
  WHERE id = p_receipt_upload_id
  RETURNING * INTO v_receipt;

  v_after := to_jsonb(v_receipt) || jsonb_build_object('cancel_reason', TRIM(p_reason));

  PERFORM fn_log_admin_action(
    'receipt.cancel',
    'receipt',
    p_receipt_upload_id,
    jsonb_build_object('cancel_reason', TRIM(p_reason)),
    v_before,
    v_after,
    jsonb_build_object('receipt_upload_id', p_receipt_upload_id),
    TRIM(p_reason),
    'fn_cancel_approved_receipt_upload',
    p_admin_id
  );

  RETURN jsonb_build_object('success', true, 'title', 'Receipt cancelled', 'description', null, 'data', jsonb_build_object('receipt_upload_id', p_receipt_upload_id));
END;
$function$;
