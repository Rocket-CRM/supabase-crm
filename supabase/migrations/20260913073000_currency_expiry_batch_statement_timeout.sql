-- PostgREST callers hit ~8s statement_timeout; Render expiry job uses direct
-- Postgres with a session timeout, but keep a function-level ceiling for safety.
ALTER FUNCTION public.process_currency_expiry_batch(date, date, integer, text)
  SET statement_timeout TO '10min';
