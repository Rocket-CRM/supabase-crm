-- Retire pg_cron daily-currency-expiry in favor of Render Cron Job currency-expiry-daily.
-- pg_cron cannot run process_expiry_if_needed() because it COMMITs inside a loop.

SELECT cron.alter_job(
  job_id := (
    SELECT jobid FROM cron.job WHERE jobname = 'daily-currency-expiry' LIMIT 1
  ),
  active := false
);
