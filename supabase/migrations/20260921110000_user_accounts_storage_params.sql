-- user_accounts write-path storage tuning (no heap rewrite, no repack).
-- Apply only when no migration_wave_status row has status = 'running'.
-- Index drops: scripts/ops/user_accounts_index_cleanup_steps_2_4.sql (CONCURRENTLY, manual).

ALTER TABLE public.user_accounts SET (
  fillfactor = 85,
  autovacuum_vacuum_scale_factor  = 0.02,
  autovacuum_analyze_scale_factor = 0.01
);
