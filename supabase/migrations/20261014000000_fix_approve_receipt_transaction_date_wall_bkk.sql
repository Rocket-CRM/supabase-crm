-- bff_approve_receipt_upload passed `p_transaction_date::text` to api_create_purchase.
-- The instant is rendered in the session timezone (UTC), e.g. '2026-09-24 18:02:00+00', and since
-- 20260803112239 (parse_receipt_tz_always_wall_bkk) fn_parse_receipt_timestamptz ignores the offset
-- and reads the printed clock face as Asia/Bangkok. Result: every admin-approved receipt landed
-- 7 hours early in purchase_ledger (01:02 Bangkok on 25 Sep -> stored as 18:02 Bangkok on 24 Sep).
-- Fix: hand api_create_purchase the Bangkok wall-clock key the RPC already computes
-- (v_receipt_dt_key = fn_receipt_datetime_key(p_transaction_date)) — the parser's documented input.
-- Patches the live definition in place so nothing else in the 24 KB body can drift.
DO $migration$
DECLARE
  v_sig  regprocedure := 'public.bff_approve_receipt_upload(text,uuid,uuid,uuid,uuid,timestamp with time zone,text,jsonb,text,text,numeric,text,text)'::regprocedure;
  v_def  text := pg_get_functiondef(v_sig);
  v_old  constant text := 'CASE WHEN p_transaction_date IS NULL THEN NULL ELSE p_transaction_date::text END';
  v_new  constant text := 'v_receipt_dt_key';
BEGIN
  IF (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 THEN
    RAISE EXCEPTION 'bff_approve_receipt_upload: expected exactly one occurrence of the old p_transaction_date expression';
  END IF;
  EXECUTE replace(v_def, v_old, v_new);
END
$migration$;
