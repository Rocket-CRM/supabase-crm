-- user_accounts index cleanup — Steps 2–4 (manual)
-- Project: wkevmsedchftztoolkmi
--
-- HARD RULES:
--   • Do NOT run while migration_wave_status has status = 'running' (especially sub_step = '__wave__').
--   • Run each DROP INDEX CONCURRENTLY as a single statement, outside any transaction (psql or SQL editor).
--   • Never drop, reindex, or repack idx_user_accounts_mongo_id.
--   • Deploy 20260921103000_user_accounts_bff_admin_search_members.sql first; confirm EXPLAIN plans.
--
-- Step 0 — pre-checks (read-only)
/*
SELECT sub_step, status, started_at
FROM public.migration_wave_status
WHERE status = 'running';

SELECT pid, now() - query_start AS age, state, left(query, 120)
FROM pg_stat_activity
WHERE state <> 'idle'
  AND query ILIKE '%user_accounts%'
  AND pid <> pg_backend_pid()
ORDER BY age DESC;

SELECT pg_size_pretty(pg_total_relation_size('public.user_accounts')) AS total,
       pg_size_pretty(pg_table_size('public.user_accounts')) AS heap,
       pg_size_pretty(pg_indexes_size('public.user_accounts')) AS indexes;

SELECT indexrelname, idx_scan, pg_size_pretty(pg_relation_size(indexrelid))
FROM pg_stat_user_indexes
WHERE relname = 'user_accounts'
ORDER BY indexrelname;

SELECT indexrelid::regclass, pg_get_indexdef(indexrelid)
FROM pg_index
WHERE indrelid = 'public.user_accounts'::regclass
ORDER BY 1;
*/

-- Pre-drop: merchant-scoped count should use user_accounts_merchant_created_idx (not idx_user_accounts_merchant)
/*
EXPLAIN SELECT count(*) FROM user_accounts ua
WHERE ua.merchant_id = 'fa71c192-d5bf-4957-bd0f-a89dc6b72ea5';
*/

-- Step 2 — one statement per execution (CONCURRENTLY, no transaction block)
-- DROP INDEX CONCURRENTLY IF EXISTS public.user_accounts_id_key;
-- DROP INDEX CONCURRENTLY IF EXISTS public.idx_user_accounts_id_card_norm_trgm;
-- DROP INDEX CONCURRENTLY IF EXISTS public.idx_user_accounts_user_stage;
-- DROP INDEX CONCURRENTLY IF EXISTS public.idx_user_accounts_merchant_external_user_id;
-- DROP INDEX CONCURRENTLY IF EXISTS public.idx_user_accounts_merchant;

-- Step 3 — storage parameters (no heap rewrite; safe in one ALTER, still avoid migration wave)
/*
ALTER TABLE public.user_accounts SET (
  fillfactor = 85,
  autovacuum_vacuum_scale_factor  = 0.02,
  autovacuum_analyze_scale_factor = 0.01
);
*/

-- Step 4 — post-change verification
/*
SELECT count(*) AS index_count
FROM pg_index i
JOIN pg_class c ON c.oid = i.indexrelid
JOIN pg_class t ON t.oid = i.indrelid
WHERE t.relname = 'user_accounts'
  AND t.relnamespace = 'public'::regnamespace;

EXPLAIN SELECT * FROM user_accounts WHERE id = '00000000-0000-0000-0000-000000000000';
EXPLAIN SELECT id FROM user_accounts
WHERE external_user_id = 'x' AND merchant_id = 'fa71c192-d5bf-4957-bd0f-a89dc6b72ea5';
EXPLAIN SELECT mongo_id, id FROM user_accounts WHERE mongo_id = ANY(ARRAY['x']::text[]);
-- Last plan must use idx_user_accounts_mongo_id

SELECT pg_size_pretty(pg_indexes_size('public.user_accounts')) AS indexes;
*/
