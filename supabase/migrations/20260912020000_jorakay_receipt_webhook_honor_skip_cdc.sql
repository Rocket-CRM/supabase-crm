-- Historical / backfill purchases set skip_cdc = true.
-- Honor that flag so Jorakay's HubSpot receipt webhook does not fire.

CREATE OR REPLACE FUNCTION public.jorakay_notify_receipt_webhook()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  webhook_url text := 'https://wkevmsedchftztoolkmi.supabase.co/functions/v1/custom_webhook_jorakay_receipts';
BEGIN
  IF NEW.merchant_id <> '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid THEN
    RETURN NEW;
  END IF;
  IF COALESCE(NEW.skip_cdc, false) THEN
    RETURN NEW;
  END IF;
  IF NEW.status IS DISTINCT FROM 'completed' THEN
    RETURN NEW;
  END IF;

  PERFORM net.http_post(
    url := webhook_url,
    headers := jsonb_build_object('Content-Type', 'application/json'),
    body := jsonb_build_object('purchase_id', NEW.id::text)
  );

  RETURN NEW;
END;
$function$;
