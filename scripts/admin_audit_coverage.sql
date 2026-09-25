-- Static coverage check (Phase 6): admin-facing writers without fn_log_admin_action.
-- Run before backend deploy batches. Add exemptions to admin_audit_log_exempt with a reason.

CREATE TABLE IF NOT EXISTS public.admin_audit_log_exempt (
  function_name text PRIMARY KEY,
  reason text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

WITH writers AS (
  SELECT
    p.oid,
    n.nspname || '.' || p.proname AS function_name,
    pg_get_functiondef(p.oid) AS def
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND (
      (p.proname LIKE 'bff\_%' AND p.proname NOT LIKE 'bff\_user\_%')
      OR p.proname LIKE 'cs\_bff\_%'
    )
    AND pg_get_functiondef(p.oid) ~* '(INSERT INTO|UPDATE |DELETE FROM|EXECUTE )'
),
missing AS (
  SELECT w.function_name
  FROM writers w
  WHERE w.def NOT LIKE '%fn_log_admin_action%'
    AND w.def NOT LIKE '%fn_log_admin_bff_write%'
    AND NOT EXISTS (
      SELECT 1 FROM admin_audit_log_exempt e
      WHERE e.function_name = split_part(w.function_name, '.', 2)
         OR e.function_name = w.function_name
    )
)
SELECT function_name AS missing_audit_logger
FROM missing
ORDER BY 1;
