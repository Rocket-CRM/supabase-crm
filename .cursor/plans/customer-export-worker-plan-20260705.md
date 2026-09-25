# Customer Export Worker — Implementation Plan (2026-07-05)

## Task

Build the missing backend pipeline for the customer CSV export feature. The frontend wizard
(loyalty-admin) and the starter RPC `bff_admin_start_user_export` already exist; nothing consumes
the batch row after creation. One real batch (`8390aa60…`) has been stuck at `pending` since
2026-07-02.

## Verified facts (do not re-discover)

- `bff_admin_start_user_export(p_batch_name, p_field_keys, p_filters)` is live. It permission-checks
  `user.export`, inserts into `bulk_import_batches` with `import_type='users_export'`,
  `status='pending'`, `field_selection.field_keys`, `metadata.filters`, auto `file_name`
  (`users_export_YYYYMMDD_HH24MISS.csv`), returns `{batch_id, file_name}`. It does NOT trigger anything.
- The export worker exists **nowhere**: checked live edge functions, all Rocket-CRM GitHub repos
  (`crm-event-processors`, `crm-batch-upload`, `render-code-import`, `crm-api`, `newcrm-migration`),
  and org-wide code search for `users_export` / `admin-user-export-csv`. Confirmed never built.
- No `process_user_export_chunk` or any export RPC in DB (only the starter BFF).
- FE polls `bff_admin_get_user_import_progress(p_batch_id)` every 3s (export wizard) and stops on
  terminal status (`completed|failed|cancelled|rolled_back`).
- **FE contract the worker must fulfil** (all on the `bulk_import_batches` row):
  - `status`: `pending → processing → completed` (or `failed`)
  - `total_rows`: export denominator (set at start)
  - `processed_count`: incremented per chunk (progress numerator)
  - `metadata.download_url`: set when CSV ready → "Download CSV" button appears
  - `started_at` / `completed_at`
- FE filter payload (`metadata.filters`, AND-combined, keys omitted when empty):
  `user_type ('buyer'|'seller')`, `persona_ids uuid[]`, `tier_ids uuid[]`, `is_active bool`,
  `has_wallet_balance bool`, `created_from 'YYYY-MM-DD'`, `created_to 'YYYY-MM-DD'`.
- FE field keys come from `bff_admin_get_importable_fields` groups:
  - `default`: `user_accounts_<col>` (tel, line_id, email, firstname, lastname, fullname,
    birth_date, gender, user_type, persona_id, external_user_id, member_code, id_card, mongo_id,
    created_at, channel_email, channel_sms, channel_line, channel_push)
  - `address`: `user_address_<col>` (addressline_1/2, subdistrict(+_code), district(+_code),
    state, province_code, city, postcode, country_code)
  - `wallet`: `user_wallet_points_balance`, `user_accounts_tier_id`,
    `user_accounts_tier_lock_downgrade`, `user_accounts_tier_locked_downgrade_until`
  - forms: `user_profile_<field_key>` (USER_PROFILE form) and `form_<FORM_CODE>_<field_key>`
    (published forms with `allow_bulk_import=true`); values in `form_submissions`/`form_responses`
    (latest submission per user per form)
- Import architecture to mirror: `admin-user-import-kickoff` edge fn + Inngest serve edge functions
  (`inngest-bulk-import-*-serve`) + chunked RPC `process_user_import_chunk(p_batch_id, p_chunk_size)`.
  The export wizard does NOT call any kickoff — trigger must come from the backend.
- FE files (loyalty-admin repo): `src/app/(admin)/customers/export/{page,export-wizard,export-filters,actions}.tsx|ts`,
  `src/lib/api/user-imports.ts`, `src/types/user-imports.ts`,
  `src/app/(admin)/customers/_components/field-picker.tsx`.

## Decisions (agreed in planning thread)

1. **No Render service.** Worker = Supabase edge function serving an Inngest function
   (`admin-user-export-csv`), mirroring the `inngest-bulk-import-*-serve` pattern. Inngest steps
   give chunked execution across invocations → no edge-function timeout risk. Render is a later
   escape hatch only if a merchant needs 1M+-row single-file exports.
2. **Trigger**: `bff_admin_start_user_export` emits the Inngest event directly after insert via
   `pg_net` POST to the Inngest Event API (`https://inn.gs/e/<EVENT_KEY>`), event name
   `export/users-csv`, payload `{batch_id, merchant_id}`. No FE change required.
   (Verify at build time how existing functions obtain secrets — Vault vs hardcoded — and where
   `INNGEST_EVENT_KEY` lives; `crm-event-processors/src/clients/inngest.ts` shows the HTTP shape.)
3. **Reuse `bulk_import_batches`** as the batch/progress table (already wired on both ends; it is
   the de-facto generic batch-job table via the `import_type` discriminator). No new table.
4. **Storage**: private bucket `exports` (create if missing); final CSV at
   `<merchant_id>/<batch_id>/<file_name>`; **signed URL, 7-day expiry** → `metadata.download_url`.
5. **v1 field scope**: exactly the field keys the current picker offers (list above).
   Phase 5 (later, separate thread): `bff_admin_get_exportable_fields` superset catalog — account
   & lifecycle cols (`id`, `created_at`, `is_active`, `user_stage`, `acquisition_source`, `store_id`,
   `marketplace_external_ids`…), resolved tier/persona **names**, per-currency + per-ticket
   balances (`user_wallet`, `user_ticket_balances`), tags (`user_tags`), consent
   (`user_consent_ledger`), referral, benefits; aggregates (lifetime spend/earn, last purchase)
   as v2 — needs small FE change to call the new catalog RPC.

---

## Execution status (2026-07-05 — implemented)

### Phase 1 — DB ✅ `customer_export_worker_v1` migration applied

| Object | Status |
|---|---|
| `fn_emit_inngest_event(p_event_name, p_data)` | ✅ Reads vault `inngest_event_key`; pg_net POST to `https://inn.gs/e/...` |
| `fn_user_export_field_labels(p_merchant_id, p_field_keys)` | ✅ Human CSV headers |
| `fn_user_export_filter_sql(p_filters)` | ✅ Shared AND filter builder |
| `fn_user_export_count(p_batch_id)` | ✅ |
| `process_user_export_chunk(p_batch_id, p_offset, p_limit)` | ✅ Dynamic SELECT; address = latest by `created_at`; form = latest completed submission |
| `bff_admin_start_user_export` | ✅ Updated — calls `fn_emit_inngest_event('export/users-csv', …)` after insert; returns `inngest_request_id` |
| Storage bucket `exports` (private) | ✅ Created |

**Build-time resolutions:**
- **pg_net + secrets:** No existing vault Inngest key. Pattern mirrors `net.http_post` elsewhere; new vault name `inngest_event_key` (NOT provisioned yet — see blocker below).
- **user_address:** Latest row by `user_address.created_at DESC` (no `is_primary` column).
- **CSV headers:** Human `field_label` via `fn_user_export_field_labels` (matches import template intent).
- **Chunk size:** 1000 in edge function.

### Phase 2 — Edge function ✅ deployed

| Slug | Version | verify_jwt | Inngest |
|---|---|---|---|
| `admin-user-export-csv` | v2 | `false` | App `crm-user-export`, fn `export-users-csv`, event `export/users-csv` |

Steps: init → chunk-N (RPC + Storage parts) → finalize (BOM + labels + signed URL + metadata merge preserving `filters`).

### Phase 3 — Verify ✅ E2E complete (2026-07-05)

**Ops completed:** vault `inngest_event_key` + `inngest_signing_key` added; Inngest app `crm-user-export` synced to `/functions/v1/admin-user-export-csv`.

**Stuck batch `8390aa60-d8be-4bf7-8570-b774bdfd80c3` — final result:**
- `pending` → `processing` → **`completed`** (~10s, 2026-07-05 11:36 UTC)
- `total_rows` / `processed_count`: **327**
- `metadata.download_url`: set (7-day signed Storage URL under `exports/32790d51-…/`)
- Thai + form field labels confirmed in RPC smoke; full CSV via signed URL

**New exports from FE:** auto-trigger via `bff_admin_start_user_export` → `fn_emit_inngest_event` (no manual SQL).

### Phase 4 — Docs ✅

- `requirements/Customer_Export.md` — new
- `requirements/REGISTRY_RENDER.md` — `admin-user-export-csv` under Bulk Import
- `requirements/REGISTRY_SUPABASE.md` — regenerated (~1924 lines)
- `requirements/CHANGELOG.md` — 2026-07-05 bullet added
- `scripts/regen_registry_supabase.sql` — Customer Import pattern extended for `user_export|export_`

### Phase 5 — Later ⏸ not started

`bff_admin_get_exportable_fields` + FE picker (unchanged from plan).

---

## Blocker for production / E2E test — ✅ RESOLVED

Vault `inngest_event_key` provisioned; Inngest app synced. E2E verified on batch `8390aa60-…`.
