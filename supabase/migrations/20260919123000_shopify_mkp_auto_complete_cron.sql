-- Hourly Shopify mkp auto-complete (delivered → completed + claim). Edge: shopify-mkp-auto-complete.

SELECT cron.unschedule(jobid)
FROM cron.job
WHERE jobname = 'shopify-mkp-auto-complete';

SELECT cron.schedule(
  'shopify-mkp-auto-complete',
  '0 * * * *',
  $$
  SELECT net.http_post(
    url := (
      SELECT decrypted_secret
      FROM vault.decrypted_secrets
      WHERE name = 'supabase_url'
    ) || '/functions/v1/shopify-mkp-auto-complete',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (
        SELECT decrypted_secret
        FROM vault.decrypted_secrets
        WHERE name = 'service_role_key'
      )
    ),
    body := '{"limit": 100}'::jsonb
  );
  $$
);
