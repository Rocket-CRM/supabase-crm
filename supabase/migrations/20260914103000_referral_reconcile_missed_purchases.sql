-- Safety net: re-run purchase attribution for paid Shopify orders that match an open claim
-- but missed realtime ingest (e.g. legacy claim-expired-on-code-TTL window).

CREATE OR REPLACE FUNCTION public.fn_reconcile_missed_referral_purchases(p_merchant_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  r record;
  v_attr jsonb;
  v_attempted int := 0;
  v_attributed int := 0;
BEGIN
  FOR r IN
    SELECT
      o.merchant_id,
      o.platform,
      o.order_sn,
      o.order_status,
      o.payment_status,
      o.buyer_email,
      o.buyer_phone,
      o.external_user_id,
      o.discount_codes
    FROM public.order_ledger_mkp o
    WHERE o.platform = 'shopify'
      AND (p_merchant_id IS NULL OR o.merchant_id = p_merchant_id)
      AND lower(COALESCE(o.payment_status, o.order_status, '')) IN ('paid', 'partially_paid', 'authorized')
      AND NOT EXISTS (
        SELECT 1
        FROM public.referral_ledger rl
        WHERE rl.merchant_id = o.merchant_id
          AND rl.platform = o.platform
          AND rl.order_key = o.order_sn
          AND rl.kind = 'purchase'
      )
      AND EXISTS (
        SELECT 1
        FROM public.referral_claim c
        WHERE c.merchant_id = o.merchant_id
          AND c.platform = o.platform
          AND c.completed_at IS NULL
          AND c.status IN ('open', 'expired')
          AND c.created_at > now() - interval '30 days'
          AND (
            (o.buyer_email IS NOT NULL AND public.fn_canonicalize_email(c.friend_email) = public.fn_canonicalize_email(o.buyer_email))
            OR (
              o.discount_codes IS NOT NULL
              AND EXISTS (
                SELECT 1
                FROM public.referral_code rc
                WHERE rc.claim_id = c.id AND rc.code = ANY (o.discount_codes)
              )
            )
          )
      )
    ORDER BY o.transaction_date ASC
    LIMIT 200
  LOOP
    v_attempted := v_attempted + 1;
    v_attr := public.fn_attribute_referral(
      p_kind := 'purchase',
      p_merchant_id := r.merchant_id,
      p_platform := r.platform,
      p_order_key := r.order_sn,
      p_order_status := r.order_status,
      p_payment_status := r.payment_status,
      p_buyer_email := r.buyer_email,
      p_buyer_phone := r.buyer_phone,
      p_buyer_external_id := r.external_user_id,
      p_codes := COALESCE(r.discount_codes, '{}'::text[])
    );
    IF COALESCE(v_attr->>'success', 'false')::boolean
       AND (
         COALESCE(v_attr->>'code', '') IN ('OK', 'ATTRIBUTED', 'IDEMPOTENT')
         OR COALESCE(v_attr->>'code', '') LIKE 'BLOCKED_%'
       ) THEN
      v_attributed := v_attributed + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'attempted', v_attempted,
    'attributed', v_attributed
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_reconcile_missed_referral_purchases(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_reconcile_missed_referral_purchases(uuid) TO service_role;

-- Run reconciliation after referral code expiry sweep (same 5-minute cadence).
SELECT cron.unschedule(jobid)
FROM cron.job
WHERE jobname = 'referral-expire-stale-codes';

SELECT cron.schedule(
  'referral-expire-stale-codes',
  '*/5 * * * *',
  $$
  DO $referral_maint$
  DECLARE v_merchant_id uuid;
  BEGIN
    FOR v_merchant_id IN
      SELECT DISTINCT merchant_id
      FROM public.referral_code
      WHERE status IN ('pending_mint', 'minted')
        AND expires_at <= now()
    LOOP
      PERFORM public.fn_expire_stale_referral_codes(v_merchant_id);
    END LOOP;
    PERFORM public.fn_reconcile_missed_referral_purchases(NULL);
  END
  $referral_maint$;
  $$
);
