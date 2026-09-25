-- Phase 6 runtime gap check (manual / weekly).
-- Compare admin-token RPC traffic (from Supabase log explorer or API logs export)
-- against functions that call fn_log_admin_action / fn_log_admin_bff_write.
--
-- This script lists writer BFFs still missing hooks (same as static check).
-- Export last-7d admin POST /rpc/* paths from logs and diff against:
--   SELECT proname FROM pg_proc WHERE proname LIKE 'bff_%' ...

\i admin_audit_coverage.sql
