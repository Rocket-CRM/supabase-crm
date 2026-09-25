-- Birth date Format-2 repair runbook
-- Affected: migrated users whose Old CRM dateOfBirth was stored as T17:00:00 UTC
-- Fix: birth_date = (dateOfBirth + 7 hours)::date
--
-- FAST PATH (recommended): fn_birth_date_format2_repair_merchant(merchant_id, false)
--   Single set-based UPDATE — seconds per merchant.
-- SLOW PATH: fn_birth_date_format2_apply_batch — row-by-row chokepoint (~50-100ms/user).

-- 0) Preconditions — pause mongo sync for target merchant(s)
SELECT merchant_uuid, sync_active
FROM migration_merchant_status
WHERE sync_active = true;

-- 1) One-shot per merchant (build manifest + bulk apply)
SELECT fn_birth_date_format2_repair_merchant('MERCHANT_UUID'::uuid, false);

-- FuturePark (~348K rows) — BLOCKED until sync paused
-- SELECT fn_birth_date_format2_repair_merchant('10de947e-ff05-4e2b-88ff-c853e5a69cb3'::uuid, false);

-- All sync-inactive merchants (loop)
-- See migration fn_birth_date_format2_repair_merchant

-- 2) Verify merchant
SELECT COUNT(*) AS still_wrong
FROM user_accounts ua
JOIN stg_mongo_users su ON su.mongo_id = ua.mongo_id
JOIN stg_mongo_contacts sc ON sc.mongo_id = su.raw->>'contactId'
WHERE ua.merchant_id = 'MERCHANT_UUID'
  AND sc.raw->>'dateOfBirth' LIKE '%T17:00:00%'
  AND ua.birth_date IS NOT NULL
  AND ua.deleted_at IS NULL
  AND ua.birth_date <> ((sc.raw->>'dateOfBirth')::timestamptz + interval '7 hours')::date;

-- Completed 2026-09-02:
-- Jorakay (12,977), Her Hyness (7,569), Kovet (240) + 67 merchants with 0 rows
