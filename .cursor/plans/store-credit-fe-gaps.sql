-- Helpers + bff_store_credit FE gap fixes (reference copy)

CREATE OR REPLACE FUNCTION public.fn_generate_store_credit_spend_code(p_merchant_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $function$
DECLARE
  v_code text;
  v_attempt integer := 0;
BEGIN
  LOOP
    v_attempt := v_attempt + 1;
    v_code := 'SC-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM wallet_ledger wl
      WHERE wl.merchant_id = p_merchant_id AND wl.code = v_code
    );
    IF v_attempt >= 10 THEN
      RAISE EXCEPTION 'Could not generate unique store credit spend code';
    END IF;
  END LOOP;
  RETURN v_code;
END;
$function$;
