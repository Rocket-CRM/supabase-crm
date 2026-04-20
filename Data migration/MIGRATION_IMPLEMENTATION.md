# Migration Implementation Status

> **Created:** 2026-04-15 | **Updated:** 2026-04-19 (v6 — large-scale hardening: UNLOGGED staging, COPY extract, per-merchant transform loop)  
> **Service:** `newcrm-migration` on Render (`https://newcrm-migration.onrender.com`)  
> **GitHub:** `Rocket-CRM/newcrm-migration` — PR #1 `feat/migration-gaps-round2` **merged 2026-04-19 (commit `4a6e0fc5`)**  
> **Supabase Project:** `wkevmsedchftztoolkmi`  
> **Render Dashboard:** https://dashboard.render.com/web/srv-d7g2qmv7f7vs73bncpsg  
> **Previous v1 (deprecated):** `crm-batch-upload` repo — do not use for MongoDB migration

---

## Architecture

```
MongoDB (CRM-PROD + StorefrontPROD)
    │
    ▼  [Extract: Node.js MongoDB driver, cursor streaming]
Staging Tables (21 stg_* tables on Supabase PG)
    │
    ▼  [Transform: 42 SQL files executed via PG pool]
Target Tables (Supabase production schema)
    │
    ▼  [Orchestrate: Inngest functions]
Wave Status Tracking (migration_wave_status)
```

**Where things live:**
- **SQL transform files** → Render service source code (`src/migration/sql/*.sql`), read from disk at runtime and executed against Supabase PG
- **Programmatic steps** → TypeScript in `src/migration/steps/*.ts`, connect to MongoDB directly for seeding operations
- **Staging + infra tables** → Supabase PostgreSQL (created via `apply_migration` MCP)
- **Node.js service** → Render web service `newcrm-migration`, auto-deploys from GitHub main branch
- **Orchestration** → Inngest functions served at `/api/inngest`

---

## What Was Built

### Supabase (via MCP `apply_migration`)

Migration: `create_migration_infrastructure_and_staging_tables`

| Table Type | Count | Tables |
|---|---|---|
| Infrastructure | 3 | `migration_id_map`, `migration_wave_status`, `sync_watermarks` |
| CRM staging | 15 | `stg_mongo_users`, `stg_mongo_contacts`, `stg_mongo_crm_users`, `stg_mongo_points`, `stg_mongo_point_txns`, `stg_mongo_wallets`, `stg_mongo_tiers`, `stg_mongo_tier_txns`, `stg_mongo_rewards`, `stg_mongo_qrtables`, `stg_mongo_reward_cats`, `stg_mongo_redemptions`, `stg_mongo_orders_lazada`, `stg_mongo_orders_shopee`, `stg_mongo_orders_tiktok` |
| Storefront staging | 3 | `stg_sf_products`, `stg_sf_stores`, `stg_sf_bills` |
| Additional staging | 3 | `stg_mongo_consent`, `stg_mongo_receipts`, `stg_mongo_channels` |

### Render Service (GitHub `Rocket-CRM/newcrm-migration`)

```
src/
├── lib/
│   ├── pg.ts                    # PG pool → Supabase direct pooler
│   ├── mongo-crm.ts             # MongoDB driver → CRM-PROD cluster
│   ├── mongo-sf.ts              # MongoDB driver → StorefrontPROD cluster
│   └── inngest.ts               # Inngest client
├── migration/
│   ├── collections.ts           # 21 collection configs + SKIP_MERCHANT_IDS
│   ├── extract-collection.ts    # Generic cursor → batch INSERT (filters merchants at extract)
│   ├── transform-runner.ts      # Read .sql file, execute against PG, track status
│   ├── inngest/
│   │   ├── index.ts             # Exports all 5 functions
│   │   ├── extract-all.ts       # Fan-out 21 extract jobs
│   │   ├── extract-one.ts       # Extract single collection → staging
│   │   ├── transform-wave.ts    # Execute sub-steps (SQL + programmatic)
│   │   ├── run-migration.ts     # Master orchestrator (DB-polling fan-in on `__wave__` sentinel)
│   │   └── daily-sync.ts        # Nightly cron (0 3 * * *)
│   ├── steps/                   # Programmatic transforms (direct MongoDB reads)
│   │   ├── seed-consent-versions.ts    # 1b: pdpas → consent_versions
│   │   ├── seed-personas.ts            # 1i-pre: MemberTypeConfig → persona tables
│   │   ├── seed-surveys.ts             # 1i-pre: surVeySettings → form_templates/fields
│   │   ├── seed-custom-fields.ts       # 1i: customFields → USER_PROFILE forms
│   │   ├── transform-custom-field-answers.ts  # 3b: customFields[] → form_responses
│   │   ├── transform-survey-answers.ts        # 3c/3d: surveyQuestions[] → form_responses
│   │   └── transform-claimed-orders.ts        # 5e: claimed → UPDATE order_ledger_mkp
│   ├── validate/
│   │   └── count-checks.ts      # Row counts + FK orphan checks
│   └── sql/                     # 35 transform SQL files
├── routes/
│   └── migration.ts             # API endpoints
└── server.ts                    # Express + Inngest serve
```

### API Endpoints

| Method | Path | Purpose |
|---|---|---|
| POST | `/api/migration/start` | Trigger full migration via Inngest |
| POST | `/api/migration/extract` | Trigger extract phase only |
| POST | `/api/migration/transform/:wave` | Trigger single wave transform |
| GET | `/api/migration/status` | View migration_wave_status |
| GET | `/api/migration/validate` | Run count + FK orphan checks |
| GET | `/api/migration/watermarks` | View sync_watermarks |
| POST | `/api/inngest` | Inngest serve endpoint |

All endpoints require `x-migration-secret` header.

### Transform Files (35 SQL + 7 programmatic = 42 total)

| Wave | SQL Files | Programmatic Steps | Target Tables |
|---|---|---|---|
| 1 (19 steps) | 15 SQL | `seed-consent-versions`, `seed-personas`, `seed-surveys`, `seed-custom-fields` | tier_master, consent_versions, store_master, store_attributes, reward_category, reward_master, reward_points_conditions, reward_promo_code, persona_group/master, form_templates/fields, product_category/brand/master, product_sku_master |
| 2 (3 steps) | 3 SQL | — | user_accounts (3-pass merge with phone normalization) |
| 3 (5 steps) | 3 SQL | `transform-custom-field-answers`, `transform-survey-answers` | user_address, form_submissions/responses, user_wallet, tier_progress |
| 4 (5 steps) | 5 SQL | — | wallet_ledger (with source_id/target_entity_id), tier_change_ledger, reward_redemptions_ledger, user_consent_ledger |
| 5 (5 steps) | 4 SQL | `transform-claimed-orders` | order_ledger_mkp, order_items_ledger_mkp |
| 6 (5 steps) | 5 SQL | — | purchase_ledger, purchase_items_ledger, purchase_receipt_upload |

---

## Gap Analysis: v1 → v2 Fixes Applied

All P0 and P1 gaps from the v1 audit have been resolved in the v2 codebase (`newcrm-migration`):

| # | Gap | Status | Fix |
|---|---|---|---|
| G1 | 6 placeholder SQL files | **FIXED** | Implemented as TypeScript programmatic steps in `src/migration/steps/` |
| G2 | Boonsiri placeholder ObjectId | **TODO** | Marked with `TODO` comment — user must fill in actual ObjectId |
| G3 | SKIP_MERCHANTS placeholder IDs | **TODO** | Marked with `TODO` comment — user must fill in actual ObjectIds |
| G4 | Fixed sleep() in orchestrator | **FIXED** | Uses `step.waitForEvent('migration/wave-done')` with wave matching |
| G5 | No phone normalization | **FIXED** | Wave 2a strips `+66` prefix → `0` prefix before dedup |
| G6 | wallet_ledger.source_id unmapped (old) | **FIXED** | Resolves `productOrderId` → `purchase_ledger.id` |
| G7 | wallet_ledger.source_id unmapped (new) | **FIXED** | Resolves `earned_item.receipt_id` → `purchase_ledger.id` |
| G8 | wallet_ledger.target_entity_id unmapped | **FIXED** | Resolves `earned_item.store_property.id` → `store_master.id` |
| G9 | reward_master.allowed_persona unmapped | **FIXED** | Resolves `memberType[]` → `persona_master` UUIDs |
| G10 | CRM channel store code collision | **FIXED** | Uses `ROW_NUMBER() OVER (PARTITION BY merchant_ref)` for unique ch_idx |
| G11 | Extract loads all merchants | **FIXED** | `SKIP_MERCHANT_IDS` filter applied during extract |
| G12 | Missing channel_sms/channel_push defaults | **FIXED** | Added `false`/`true` to Wave 2a INSERT |
| G14 | Insufficient validation checks | **FIXED** | Added product_sku_master, user_address, consent_versions, purchase_receipt_upload + FK orphan checks |
| G16 | No FK orphan checks | **FIXED** | Added 3 orphan queries (wallet→users, purchase→stores, redemption→rewards) |
| G17 | Daily sync watermark mapping wrong | **FIXED** | Corrected area-to-staging-table mapping |

### Remaining TODOs (user action required)

| Item | Where |
|---|---|
| **G15** financial reconciliation query | **IMPLEMENTED** in v4 — run via `POST /api/migration/recon` |
| **G18** user_field_config.persona_ids from staticQuestion | Not implemented — minor, do post-migration if needed |
| **G19** Wave 1 sub-step parallelization | Sequential is safe; parallel is optimization only |

_G2/G3 (merchant ObjectIds) resolved in v3; remaining G14/G17 expanded in v4._

### v7 Extract correctness fixes (2026-04-19)

Discovered while unsticking the first production migration (HER HYNESS, merchant `66e2aa1173943473744230b8`).

| # | Gap | Fix |
|---|---|---|
| G36 | `stg_mongo_consent` extract hung for >1 h with no output. `loyaltydb.clientpdpas` embeds the full PDPA policy HTML in each doc's `detail`/`titleForm`/`nameForm` fields (~36 KB/doc). A 100K-row merchant slice transferred ~3.7 GB over the wire and hit Atlas query-time limits before the COPY flush could complete. The extractor had no projection and no `maxTimeMS`. | **FIXED** — `CollectionConfig.projection` added in `src/migration/collections.ts`. `stg_mongo_consent` now extracts with `{ detail: 0, titleForm: 0, nameForm: 0 }` → per-doc payload drops ~36 KB → ~0.3 KB (100× reduction). Canonical policy text will migrate from `loyaltydb.pdpas` → `consent_versions` separately (joined by `pdpaId`). Verified via Mongo MCP: the `merchantId_1` index exists and `EXPRESS_IXSCAN` returns in 0ms — this was never an indexing problem. |
| G37 | All `stg_sf_*` tables extracted 0 rows in single-merchant mode, despite merchants having real data (HER HYNESS: 516 stores, 396 products, 44,320 product_orders in `storefrontdb`). The extract filter coerced the merchant id to `ObjectId` only when `merchantIdField === 'merchantId'`. Storefront collections use `organization_id` (also an ObjectId on disk) — filter sent a plain string, matched zero docs. | **FIXED** — `src/migration/extract-collection.ts` now uses an `OBJECT_ID_MERCHANT_FIELDS` set that includes both `merchantId` and `organization_id`. Other merchant fields (`merchant_id` for `crm_*_db.*`, `shop_id` for `third_party_ecommerce.*`) are correctly kept as strings. |
| G38 | Marketplace orders (`stg_mongo_orders_{lazada,shopee,tiktok}`) show 0 rows for every merchant. Root cause is **two-layered**: (1) extractor filters by `shop_id == merchantMongoId`, but `shop_id` is a platform-specific seller id (e.g. Lazada `"100184574113"`), not a Mongo ObjectId. (2) Even when data makes it in via bulk mode, `extract-collection.ts` stores `shop_id` into `stg.merchant_ref`, but Wave 5 SQL joins `merchant_ref` against `merchant_master.mongo_id` — ids never match, so all marketplace rows are silently dropped by the transform. | **FIXED 2026-04-20** — see below. |

**Impact:** `stg_mongo_consent` and `stg_sf_{stores,products,bills}` now extract correctly for all merchants. Marketplace fix landed 2026-04-20.

### v7.1 Marketplace shop_id resolution (2026-04-20)

Fix for G38. **Important schema correction** vs. the original design note: the `third_party_ecommerce.*_access_tokens` collections do **not** contain a `merchant_id` field — verified via MCP `collection-schema`, they only carry `{shop_id, access_token, refresh_token, expired_at, created_at}`. The authoritative `shop_id ↔ merchant` mapping lives on `loyaltydb.merchants` itself, embedded as three parallel arrays:

- `lazadaIntegrations[].country_user_info[].seller_id` (preferred) or `.account_detail.seller_id` — Lazada shop_id
- `shopeeIntegrations[].shop_id` — Shopee shop_id
- `tikTokIntegrations[].shop_list.id` — TikTok shop_id (capital **T** in field name)

Sampled HER HYNESS (`66e2aa1173943473744230b8`) as ground truth:

| Platform | Field path | shop_id | Mongo rows |
|---|---|---|---|
| Lazada | `lazadaIntegrations[0].country_user_info[0].seller_id` | `100184574113` | 683 276 |
| Shopee | `shopeeIntegrations[0].shop_id` | `224882570` | 2 877 458 |
| TikTok | `tikTokIntegrations[0].shop_list.id` | `7495127669839399750` | 771 170 |

Total ≈ 4.33M marketplace orders for HER HYNESS alone. Expected seed output: 3 rows in `merchant_credentials` keyed by `(merchant_id=HER HYNESS UUID, service_name, external_id)`.

Dr.PONG (`673af7bb8cc3e50c0e8a355b`) as multi-shop stress case:

| Platform | Integration count | Distinct shop_ids | Notes |
|---|---|---|---|
| Lazada | 3 | 3 (`100875232344`, `23396`, `1000180612`) | Three separate Lazada accounts — status mix (INACTIVE + 2 ACTIVE) |
| Shopee | 21 | 21 | One per physical store (Central Ladprao, Lotus บางกะปิ, ICONSIAM, etc.) |
| TikTok | 1 | 1 (`7494587102891248593`) | Shop "drpongshop" |

Dr.PONG produces **25** seed rows.

**Changes shipped:**

| File | Change |
|---|---|
| `src/migration/steps/seed-marketplace-credentials.ts` (NEW) | Reads `loyaltydb.merchants.{lazada,shopee,tikTok}Integrations`, upserts into `merchant_credentials (merchant_id, service_name, external_id, credentials)`. Full integration payload (tokens/expiry/account_detail/shop_info) goes into the `credentials` jsonb column. Honours `SKIP_MERCHANT_IDS`. Accepts single-merchant or bulk scope. |
| `src/migration/collections.ts` | New `CollectionConfig.marketplacePlatform: 'lazada'\|'shopee'\|'tiktok'` flag on the three marketplace staging configs. |
| `src/migration/extract-collection.ts` | When `marketplacePlatform` is set: (1) resolve shop_ids via `SELECT external_id FROM merchant_credentials JOIN merchant_master` before opening the Mongo cursor, (2) filter cursor by `{shop_id: {$in: resolvedShopIds}}` instead of the broken `{shop_id: merchantMongoId}`, (3) translate each doc's shop_id back to the owning merchant's mongo hex and write THAT into `stg.merchant_ref` so Wave 5 JOINs work unchanged. If no shop_ids resolve, logs and returns 0 cleanly. |
| `src/migration/inngest/extract-all.ts` | Seeds `merchant_credentials` via `seedMarketplaceCredentials` BEFORE fanning out extract-one. Dependency ordering is hard — without the seed, marketplace extracts short-circuit to 0. |
| `src/migration/inngest/daily-sync.ts` | Same seed step, per-active-merchant, before the SYNC_AREAS loop. Idempotent — runs every night to refresh tokens/expiry alongside shop_id mappings. |
| `src/migration/steps/transform-claimed-orders.ts` | Fixed the same bug (filtered `*_order_claimed_transactions` by `{shop_id: merchantMongoId}` → 0 rows). Now resolves shop_ids from `merchant_credentials` the same way. |

**New Supabase index (via apply_migration):** `merchant_credentials_marketplace_uniq` — partial unique index on `(merchant_id, service_name, external_id)` WHERE `service_name IN ('lazada','shopee','tiktok')`. Enables the seed step's `ON CONFLICT` upsert without colliding with existing native-CRM rows that use email addresses as `external_id`.

**Verification plan (HER HYNESS first):**
1. Rerun single-merchant migration with `merchantMongoId = 66e2aa1173943473744230b8`.
2. Confirm `merchant_credentials` has **3** rows for HER HYNESS (Lazada `100184574113`, Shopee `224882570`, TikTok `7495127669839399750`).
3. Confirm staging counts match Mongo: `stg_mongo_orders_lazada ≈ 683K`, `stg_mongo_orders_shopee ≈ 2.87M`, `stg_mongo_orders_tiktok ≈ 771K`.
4. Confirm Wave 5 writes ~4.33M rows into `order_ledger_mkp` for HER HYNESS alone, keyed by `(platform, order_sn)`.

**Preserved invariants:** SKIP_MERCHANT_IDS still honoured; ON CONFLICT staging upsert unchanged; `merchant_id` (crm_*_db) and `merchantId` (loyaltydb) / `organization_id` (storefrontdb) coercion logic untouched; daily-sync watermark contract unchanged.

### v7.2 Run-full fan-in via DB polling (2026-04-20)

| # | Gap | Fix |
|---|---|---|
| G39 | `migration-run-full` hung 31m+ on `step.waitForEvent('migration/extract-done')` even though `migration-extract-all` completed green and wrote all 21 staging tables. Same lost-event failure mode as G-row "Stuck orchestrator on lost fan-in events" but one layer up: the extract-level fix (2026-04-20) closed the 21× child fan-in, but run-full still had 6 × `step.waitForEvent` calls for its own child coordination (extract-all → run-full plus each of waves 1,2,3,4,5,6 → run-full). Any one dropped event wedges the whole run for its 60m–6h `timeout`. Hit in practice on merchant `66e2aa...4230b8`: `migration_merchant_status.status` stuck at `'extracting'`, no transform waves triggered, only recovery was cancel + retrigger. | **FIXED** — `transform-wave.ts` and `extract-all.ts` now each write a `sub_step='__wave__'` sentinel row in `migration_wave_status` (`running` at start → `completed`/`failed` at end, with `error_detail` populated on failure). `run-migration.ts` replaces every `step.waitForEvent` with a shared `waitForWaveCompletion(step, { label, runId, wave, timeoutMinutes })` helper that polls the sentinel on the same 15s interval as extract-all's internal fan-in. Source of truth is the PG sentinel, not Inngest event delivery — uniform resilience across all 7 phases (wave 0 extract + waves 1–6 transforms). `sendEvent('extract-done')` / `sendEvent('wave-done')` retained for observability only. Also adds a `mark-merchant-failed` cleanup path: run-full's main body is wrapped in try/catch and flips `migration_merchant_status.status='failed'` (scoped to `current_run_id`) on any thrown error, so crashed runs are visible in `/progress/detailed` without digging through Inngest. See `DATA_MIGRATION_KNOWLEDGE_BASE.md` **Run-full fan-in via DB polling** for the full write-up. |

**Preserved invariants:** transform wave DAG unchanged (3/5/6 parallel, 4 after 6, 5d after 5a/b/c `parallelGroup`); per-sub_step `migration_wave_status` rows keep the exact same `runSql`/`runSqlPerMerchant` semantics; `step.sendEvent` calls still fire so any external listener or daily-sync subscriber is unaffected; `retries: 0` on `migration-run-full` unchanged (we want the parent to fail fast on a real sub-step failure rather than loop through a 2nd expensive retry).

**Recovery for runs stuck on the old hand-off:** cancel the parent `migration-run-full` in Inngest (extract-all children will already show Completed; they exited cleanly), reset `migration_merchant_status` → `status='pending'`, `current_run_id=null`, `initial_load_started_at=null` for the affected merchant(s), then retrigger `POST /migration/start`. Staging data is idempotent (`ON CONFLICT (mongo_id) DO UPDATE`) — no need to manually clear it; the new run will re-land any rows it touches at the same row counts.

### v6 Large-scale hardening (2026-04-19 — in PR #4 `feat/large-scale-hardening`)

Scaled the pipeline to comfortably handle the full ~65–70 GB / tens-of-millions-of-rows load without per-step timeouts, WAL bursts, or memory spikes. None of these are semantic behaviour changes — the transforms, upsert keys, and idempotency guarantees are identical to v5.

| # | Gap | Fix |
|---|---|---|
| G33 | Staging tables were LOGGED — bulk extract of 70 GB doubled WAL volume and added checkpoint pressure | **FIXED** — Supabase migration `staging_tables_set_unlogged` applied. All 21 `stg_mongo_*` / `stg_sf_*` tables are now UNLOGGED. Staging is re-extractable so the post-crash truncate semantics are acceptable; re-running extract is idempotent via `ON CONFLICT (mongo_id) DO UPDATE`. |
| G34 | Extract used parameterised multi-row `INSERT` — bottleneck on >1M-row collections (`point_transactions` 6M, `product_orders` 5.1M, `points` 4M, `histories` 3.16M) | **FIXED** — `src/migration/extract-collection.ts` now uses `pg-copy-streams` `COPY` into a per-batch `CREATE TEMP TABLE … ON COMMIT DROP` scratch table, merged into staging via `INSERT … SELECT … ON CONFLICT`. 5–10× throughput improvement; single code path still handles both initial load and daily-sync upsert semantics. Batch size = 10 000 docs (~10–50 MB per flush). |
| G35 | Waves 4a / 4b / 6a ran as single transactions over the whole roster — multi-GB WAL burst, long-held row locks, `work_mem` spills, statement-timeout risk | **FIXED** — `pgQueryMigrationScoped()` publishes a `migration.scope_merchant` GUC; the three SQL files read it via `current_setting(…, true)` and filter staging rows accordingly. `transform-runner.ts::runSqlPerMerchant` iterates one merchant per transaction (roster pulled from `migration_id_map(entity_type='merchant')`). Single-merchant runs loop once; full-bulk runs iterate over all ~79 merchants. SQL files remain runnable stand-alone (empty GUC = no scope). |

**New files / helpers:**
- `src/lib/pg.ts::pgQueryMigrationScoped(sql, merchantMongoId, params?)`
- `src/migration/transform-runner.ts::runSqlPerMerchant(filename, runId, wave, subStep, onlyMerchant?)`
- `package.json` adds `pg-copy-streams@^7.0.0` + `@types/pg-copy-streams@^1.2.5`.

**Expected runtime at cutover (full-bulk, all 79 merchants):**

| Phase | Before (est.) | After (est.) | Notes |
|---|---|---|---|
| Extract (21 collections, 5 giants) | 6–10 h | 45–90 min | UNLOGGED + COPY — now bounded by Atlas read throughput |
| Waves 3/5/6 parallel | 1–3 h | 45–90 min | Wave 6a now per-merchant |
| Wave 4 (serialised after 3/5/6) | 2–4 h | 60–120 min | Waves 4a/4b per-merchant |
| **Total initial load** | **~12 h** | **~4 h** | Plus validation + recon (~15 min) |

Rough planning numbers — real runtime depends on Atlas read IOPS, Supabase disk IOPS, and how many merchants hit the Future Park / Kao Smile Club scale of ledger history.

### v4 Gap Fixes (2026-04-17 — in PR #1)

| # | Gap | Fix |
|---|---|---|
| G20 | Wave 4 ran in parallel with Wave 6 | **FIXED** — `run-migration.ts` now serializes Wave 4 after Waves 3/5/6. `wallet_ledger.source_id` lookups to `purchase_ledger` now resolve correctly. |
| G21 | `reward_promo_code` had no unique constraint; `ON CONFLICT DO NOTHING` was a no-op | **FIXED** — Applied `reward_promo_code_merchant_code_uniq` partial unique index. Pre-migration dedup removed 916 duplicate rows (all from "New CRM" test merchant). Wave-1g/1h-promo now use `ON CONFLICT (merchant_id, promo_code) DO UPDATE SET redeemed_status = OLD OR NEW`. |
| G22 | `reward_redemptions_ledger.promo_code` was text, no FK | **FIXED** — Added `promo_code_id uuid REFERENCES reward_promo_code(id)`. Wave-4d LEFT JOINs on `(merchant_id, alienCode)` to resolve. Post-step propagates `redeemed_status=true` back to promo codes for any used historical redemption. |
| G23 | Store dedup used `mongo_id`; storefront + CRM channel stores for same code collided | **FIXED** — Wave-1c-stores and wave-1c-crm-channel-stores use `ON CONFLICT (merchant_id, store_code)` with COALESCE backfill. |
| G24 | `SKIP_MERCHANT_IDS` missing BEARHOUSE, QA Rocket Test, Syngenta | **FIXED** — Added `64ec8ac50d8af3b191d60f9e`, `66695264c2fcc59a44c58ba8`, `67ee607230daa03a19ca8b4f`. |
| G25 | `seedConsentVersions` migrated all pdpas including unreferenced experimentals | **FIXED** — Filter keeps pdpas that are active OR referenced by `clientpdpas`. |
| G26 | `wave-6a-bills.sql` NULL `is_external_bill` silently bucketed to 'pos' | **FIXED** — explicit NULL branch + audit count added to `count-checks.ts`. |
| G27 | `transformClaimedOrders` read all merchants + one UPDATE per row | **FIXED** — `shop_id` MongoDB filter when `merchantMongoId` scoped; batched UPDATEs (500 per round-trip). |
| G28 | No rollback procedure | **FIXED** — `rollback-merchant.ts` + `migration_rollback_log` table + `POST /rollback/:merchantMongoId` endpoint. Unlinks users (not delete); enforces no-live-activity precondition. |
| G29 | No financial reconciliation (G15) | **FIXED** — `recon_mongo_expected`, `recon_report`, 4 `recon_v_supabase_*` views. `POST /recon` computes per-merchant user/merchant deltas with status (match/warn/fail). |
| G30 | Count checks missing `reward_promo_code`, line-item tables, forms | **FIXED** — expanded `count-checks.ts` + orphan checks for missing source_id on purchase wallet rows, orphan promo_code_id, and NULL is_external_bill. |
| G31 | Pre-flight verification of `receipts.receiptId == product_orders.order_code` assumption | **ADDED** — `verify-receipt-linkage.ts` + `POST /verify-receipt-linkage` endpoint. Decision rule: ≥95% match → proceed; 80-95% → proceed with gap; <80% → investigate. |
| G32 | File-storage URL reachability question | **RESOLVED** — stakeholders confirm old S3 buckets remain read-only accessible after cutover. No image migration needed. |

### New Supabase migration (v4)

`migration_promo_code_fk_and_rollback_recon_infra` — applied to `wkevmsedchftztoolkmi`:
- Partial unique index `reward_promo_code_merchant_code_uniq`
- `reward_redemptions_ledger.promo_code_id uuid REFERENCES reward_promo_code(id)` + index
- `migration_rollback_log`
- `recon_mongo_expected`, `recon_report`
- `recon_v_supabase_user_points`, `recon_v_supabase_user_wallet`, `recon_v_supabase_purchases`, `recon_v_supabase_redemptions`

### v4 New API endpoints

| Method | Path | Purpose |
|---|---|---|
| POST | `/api/migration/verify-receipt-linkage?limit=500` | Sample receipt↔order_code match rate (pre-flight) |
| POST | `/api/migration/rollback/:merchantMongoId` | Per-merchant rollback (refuses if live activity present) |
| GET | `/api/migration/rollback-log?merchantMongoId=...` | Audit trail |
| POST | `/api/migration/recon { merchantMongoId?, mode: 'async' }` | MongoDB aggregate extraction + report build |
| GET | `/api/migration/recon/report/:runId?status=fail` | Fetch per-run deltas |

### What's Correct (Verified Against Specs)

The following were verified as correctly implementing the spec:

- ✅ Wave 1a tier_master: ranking derivation, entry_tier logic, burn_rate calculation, card_design jsonb, user_type='buyer' default
- ✅ Wave 1e rewards: visibility compound transform, fulfillment_method derivation, autoUseTime TTL with h→mins×60
- ✅ Wave 1h QR coupons: visibility='campaign', fulfillment='digital', stock_total from quantity, COUPON filter
- ✅ Wave 1h-promo: alienCoupons[] → reward_promo_code (distinct from alienCodePartnerList pattern)
- ✅ Wave 2a users: dual upsert strategy (phone-matched + mongo_id fallback), COALESCE for backfill
- ✅ Wave 2b contacts: COALESCE merge, marketplace_external_ids jsonb merge (shopee + lazada + tiktok)
- ✅ Wave 4a points (old): ABS() for amount, signed_amount derivation, FIFO balance→deductible_balance, epoch→timestamptz, giveFrom→source_type comprehensive mapping, skip_cdc=true
- ✅ Wave 4b points (new): type-level overrides before channel mapping, REPLACED record handling with paired EARNED exclusion
- ✅ Wave 4c tier changes: ASSIGN split (initial when no previous_tier_id, manual when populated), fallback to 'manual' for unknown types
- ✅ Wave 4d redemptions: status→(redeemed_status, used_status, cancelled, fulfillment_status) quad derivation, FREE_POINT→0 points_deducted, use_expire_date computation from reward TTL, MERCHANT_UPDATE_POINT filter
- ✅ Wave 6a bills: CDC protection (skip_cdc=true, processing_method='skip', earn_currency=false), refund/delete filters, transaction_type derivation with 'pos' fallback
- ✅ Wave 6b-link: receiptId-based linkage from staging data
- ✅ Wave 6b-fix-date: transaction_date correction for receipt-based purchases
- ✅ Infrastructure: migration_id_map PK (mongo_id, entity_type), wave_status tracking, sync_watermarks
- ✅ Extract: cursor streaming with batch INSERT, ObjectId→hex serialization in JSONB

---

## Environment Variables

All set on Render dashboard (verified 2026-04-19 after v6 deploy): https://dashboard.render.com/web/srv-d7g2qmv7f7vs73bncpsg

| Variable | Purpose | Status |
|---|---|---|
| `MONGO_CRM_URI` | CRM-PROD cluster read-only | ✅ Set |
| `MONGO_SF_URI` | StorefrontPROD cluster read-only | ✅ Set |
| `SUPABASE_PG_URL` | Transaction pooler (port 6543) — used by the normal request pool | ✅ Set |
| `MIGRATION_PG_URL` | **Direct** Postgres connection (port 5432) — used by migration pool only; bypasses pooler for long-lived `COPY` + per-merchant transforms. Falls back to `SUPABASE_PG_URL` if unset. | ✅ Set (v6) |
| `INNGEST_EVENT_KEY` | Inngest event publishing | ✅ Set |
| `INNGEST_SIGNING_KEY` | Inngest signature verification | ✅ Set |
| `MIGRATION_SECRET` | `x-migration-secret` header on API | ✅ Set |

---

## Completed Steps

### Merchant Seeding (2026-04-16)

Source: `Data migration/Merchants_migrate_newcrm.csv` (80 merchants from MongoDB)

**Part 0 — Futurepark test data cleanup**

Cleared native new-CRM test data before migration. Required temporary `REPLICA IDENTITY FULL` on `purchase_ledger` and `tier_change_ledger` to work around CDC publication WHERE filters (restored to DEFAULT after).

| Table | Rows deleted |
|-------|-------------|
| `purchase_receipt_upload` | 548 |
| `purchase_ledger` | 366 |
| `tier_master` | 1 |
| `store_master` | 72 |

**Part A — Updated 5 existing merchants**

| Merchant | UUID | Changes |
|----------|------|---------|
| Kao Smile Club | `3365ee7e-7de7-4b94-b2ea-6f78314817b7` | Set `merchant_code` = `kaosmileclub`, `mongo_id` = `67975aae5f248acf5c11dfc1` |
| Her Hyness Reward | `ffe8519e-49a2-467b-a0ec-57d28ba8be49` | Set `mongo_id` = `66e2aa1173943473744230b8`. Existing campaign data preserved (2 campaigns, 1,596 participations — non-conflicting). |
| VISTRA Family | `7faab812-e179-48c2-9707-0d8a9b2f84ea` | Set `mongo_id` = `68be529cc1983430236d7116`, renamed from "NBD" to "VISTRA Family". Was empty. |
| Futurepark | `10de947e-ff05-4e2b-88ff-c853e5a69cb3` | Set `mongo_id` = `66dfd75723e3824514531d08`. Test data cleaned (Part 0). |
| Dulux | `71a1b38e-ae10-42e1-ba12-63cbb4c0c4ba` | Set `mongo_id` = `681ae0005053979597d1bbf0`. Has 8,562 native users + 1,743 stores (no mongo_id). User migration uses `ON CONFLICT (merchant_id, tel)` upsert to deduplicate. |

**Part B — Inserted 74 new merchants**

All with `name`, `merchant_code`, `mongo_id`, `created_at` from CSV. Other columns use DB defaults. Idempotent via `ON CONFLICT (mongo_id) WHERE mongo_id IS NOT NULL DO NOTHING`.

**Excluded from migration**

| Merchant | Reason |
|----------|--------|
| Syngenta | Already exists as `syngentagrower` (different product line). Kept as-is, no `mongo_id` set. |

**Final state:** 99 total merchants, 79 with `mongo_id` (migration-linked), 20 without (native new-CRM / test).

**Dulux dedup strategy:** User migration will upsert by `(merchant_id, tel)` — unique constraint `demo_mock_users_phone_merchant_key` enforces one phone per merchant. Matching users get `mongo_id` backfilled + COALESCE for empty fields. Store migration needs similar code-based matching.

---

## Infrastructure Readiness

All infrastructure in place before first test-merchant run:

| Item | Status | Notes |
|---|---|---|
| Render env vars (7, incl. `MIGRATION_PG_URL`) | ✅ Done | See table above |
| Inngest endpoint registered | ✅ Done | `https://newcrm-migration.onrender.com/api/inngest` |
| MongoDB index `loyaltydb.receipts.{createdAt:1}` | ✅ Done | Verified READY in Atlas (3.1 MB, 2026-04-15). Required for daily-sync watermark. |
| Supabase infra tables + staging | ✅ Done | 3 infra + 21 staging tables (v1) |
| Supabase v4 schema (unique index, promo_code_id FK, rollback, recon) | ✅ Done | Migration `migration_promo_code_fk_and_rollback_recon_infra` applied |
| Merchant seeding (79 with mongo_id) | ✅ Done | v3, 2026-04-16 |
| TODO placeholder ObjectIds filled | ✅ Done | v4 |
| SKIP_MERCHANT_IDS complete (6 merchants) | ✅ Done | v4 |

## Remaining Steps

1. **P0 — Apply trigger suppression** (see §P0 below). Blocker for first test merchant. Required before any run touches `wallet_ledger`, `user_accounts`, or `reward_redemptions_ledger`.
2. **Run `POST /api/migration/verify-receipt-linkage?limit=500`** — confirm receipt→order_code match rate ≥95% (one-time pre-flight)
3. **Test with single merchant** (recommended: VISTRA Family `68be529cc1983430236d7116` or Her Hyness Reward `66e2aa1173943473744230b8` for low blast radius) — then run `/recon` and review fails
4. **P1 — Extend daily-sync scope** (see §P1 below) before production cutover window
5. **Post-migration admin config** (per merchant, before cutover): tier colors, tier_conditions, earn_factor, re-invite admins

> **Note on `VISTRA Family`:** `merchant_code` remains `nbdreward` (renamed from NBD only at the display-name level; merchant_code is immutable after migration ID map is seeded).

## P0 — Trigger suppression (pending implementation)

### Why this is a blocker

`skip_cdc` only blocks logical-replication events; it does **not** stop Postgres triggers. Live triggers on migration target tables would corrupt migrated data:

| Trigger | Table | Event | Problem for migration |
|---|---|---|---|
| `fn_apply_fifo_burn` | `wallet_ledger` | AFTER INSERT | For every migrated `transaction_type='burn'` row, loops over earn rows and subtracts `deductible_balance` again. Wave 4a/4b already writes MongoDB's post-burn `balance` into `deductible_balance` → **double deduction, catastrophic**. |
| `assign_entry_tier_on_signup` | `user_accounts` | BEFORE INSERT | Unconditionally sets `NEW.tier_id := entry_tier_of(merchant, user_type, persona_id)` and overwrites the MongoDB-derived `tier_id` passed by Wave 2a/2b. |
| `after_user_signup_tier_setup` | `user_accounts` | AFTER INSERT | Creates a synthetic `tier_change_ledger` row (`change_type='initial'`, `change_reason='New user signup'`) **without `skip_cdc=true`** — floods CDC/Kafka with ~3.6M duplicate initial events. Also creates `tier_progress` rows that Wave 3f would upsert onto. |
| `trg_mission_eval_queue_wallet` / `trg_mission_eval_realtime_wallet` | `wallet_ledger` | AFTER INSERT | No-op for fresh merchants (no missions yet), but fires on `INSERT` regardless — would be a problem if migrating a merchant that already has missions native. |
| `trigger_auto_assign_on_persona_change` | `user_accounts` | AFTER UPDATE | Wave 2b `ON CONFLICT DO UPDATE` changing `persona_id` fires `fn_auto_assign_on_persona` → writes unwanted `user_benefit` rows. |
| `trigger_generate_redemption_code` | `reward_redemptions_ledger` | BEFORE INSERT | Low-severity: generates a Supabase code when `NEW.code` is NULL (~3% of `histories` rows with null `ticketCode`). Acceptable. |

### Chosen approach — session-level `session_replication_role = replica`

Verified on Supabase `postgres` role (2026-04-19): `SET LOCAL session_replication_role = replica` succeeds despite `rolsuper=false`. Zero schema change, zero trigger change, automatic cleanup on COMMIT.

**Alternatives considered and rejected:**
- *Per-row `disable_trigger` boolean*: adds a column to 10+ production tables plus rewrites of ~20 trigger functions. Larger blast radius on normal Supabase usage (every live trigger gets a new branch).
- *Custom GUC `app.migration_mode`*: targeted but still requires rewriting 6 trigger bodies. Offers no advantage over `session_replication_role` unless we need selective suppression.

### Implementation patches (scoped)

1. `src/migration/transform-runner.ts` — wrap SQL execution in `BEGIN; SET LOCAL session_replication_role = replica; <sql>; COMMIT;`.
2. Programmatic steps (`seed-*.ts`, `transform-*.ts`, `rollback-merchant.ts`) — same wrap via a new `withMigrationMode()` helper in `src/lib/pg.ts`. Exempt pure metadata writes (`migration_wave_status`, `migration_id_map`, `sync_watermarks`, `recon_report`, `migration_rollback_log`).

### Known side-effects (accepted)

- **FK enforcement is also paused in the migration session.** FKs in Postgres are implemented as system triggers, which the `replica` role bypasses alongside user triggers. This is acceptable because:
  - Every wave SQL resolves FKs via explicit JOIN/LEFT JOIN on `mongo_id` (so only already-resolvable rows insert).
  - `GET /api/migration/validate` runs 6 FK-orphan checks post-run (`wallet_ledger → user_accounts`, `purchase_ledger → store_master`, `redemption → reward_master`, `redemption → promo_code_id`, etc.).
- **Synthetic "initial" `tier_change_ledger` rows not created.** Historical tier changes come from Wave 4c (`user_tier_transactions` → real ledger rows). Users keep their real tier history; no synthetic "New user signup" row is needed. _Accepted gap._
- **No other trigger-created side-data to backfill.** `tier_progress` is inserted explicitly by Wave 3f; no other trigger on the target list creates derived rows the migration doesn't already populate.

### Rollout

- Land the `transform-runner.ts` + helper patches in `newcrm-migration` repo.
- Re-run a dry migration of the smallest test merchant (recommended: **Her Hyness Reward** `66e2aa1173943473744230b8` — has 1,596 existing participations + clean data).
- Verify via `/validate` + `/recon` that `wallet_ledger.deductible_balance` sums match MongoDB `SUM(balance)` per user.
- Roll back if off by more than `Δ < 1 pt` on user_points scope.

---

## P1 — Daily sync scope

`src/migration/inngest/daily-sync.ts::SYNC_AREAS` currently re-extracts 14 staging tables and skips all programmatic steps via `if (!s.file) continue`. The sections below define the post-cutover sync contract.

### Tier 1 — MUST sync (mutable, user-facing)

| Area | Source | Currently synced | Action |
|---|---|---|---|
| users | `loyaltydb.users` | ✅ | keep |
| contacts | `loyaltydb.contacts` | ✅ | keep |
| points_old | `loyaltydb.points` | ✅ | keep |
| points_new | `crm_point_db.point_transactions` | ✅ | keep |
| wallets | `crm_wallet_db.wallets` | ✅ | keep |
| redemptions | `loyaltydb.histories` | ✅ | keep (mutable state — use `updatedAt > watermark OR createdAt > watermark`) |
| orders_{lazada,shopee,tiktok} | `third_party_ecommerce.*_order_transactions` | ✅ | keep |
| bills | `storefrontdb.product_orders` | ✅ | keep |
| consent | `loyaltydb.clientpdpas` | ✅ | keep |
| receipts | `loyaltydb.receipts` | ✅ | keep |
| **tier_txns** | `crm_tier_db.user_tier_transactions` | ❌ | **add** — tier changes during cutover |
| **consent_versions** | `loyaltydb.pdpas` (programmatic) | ❌ | **add** — invoke `seedConsentVersions()` nightly |
| **claimed_orders** | `*_order_claimed_transactions` (programmatic) | ❌ | **add** — invoke `transformClaimedOrders()` nightly per active merchant; users claim daily |
| **custom_field_answers** | `loyaltydb.contacts.customFields[]` (programmatic) | partial | **add** — invoke `transformCustomFieldAnswers()` after contacts extract |
| **survey_answers** | `loyaltydb.contacts.surveyQuestions[]` + `memberTypeQuestion[]` (programmatic) | partial | **add** — invoke `transformSurveyAnswers()` after contacts extract |

### Tier 2 — SHOULD sync (admin-mutable, low-churn)

| Area | Source | Currently synced | Action |
|---|---|---|---|
| rewards | `loyaltydb.rewards` | ✅ | keep |
| stores | `storefrontdb.stores` | ✅ | keep |
| **qrtables** | `loyaltydb.qrtables` | ❌ | **add** — HER HYNESS, Urai Point, Kao Smile Club add codes weekly |

### Tier 3 — SKIP sync (accepted as frozen at initial load)

| Source | Rationale |
|---|---|
| `crm_tier_db.tiers` | Tier definitions are admin-config; migrated once, re-edited in new CRM only (tier colors, earn rates, conditions). |
| `loyaltydb.merchants.MemberTypeConfig` (personas) | New personas added in new CRM after cutover. Frozen on old side. |
| `loyaltydb.merchants.surVeySettings` (survey defs) | Surveys are rebuilt in new CRM. Frozen. |
| `loyaltydb.merchants.signUpSettings.fields` (custom field defs) | Same — frozen. |
| `loyaltydb.rewardcategories` | Rarely edited. |
| `loyaltydb.channels` | Static per merchant. |
| `storefrontdb.products` | New CRM uses a fresh product catalog — stakeholder-confirmed. |

### Implementation patches

1. Add `tier_txns`, `qrtables` to `SYNC_AREAS` (staging-backed — reuse the existing extract loop).
2. After the `update-watermarks` step, add a new `step.run('programmatic-sync-<merchantId>', …)` for each active merchant that sequentially calls: `seedConsentVersions`, `transformCustomFieldAnswers`, `transformSurveyAnswers`, `transformClaimedOrders({ merchantMongoId })`.
3. Keep the `if (!s.file) continue` guard in the transform-replay loop — programmatic steps were already run in step 2 with correct per-merchant scoping, so skipping in replay avoids double-processing.
4. Add count-checks for `stg_mongo_tier_txns` and `stg_mongo_qrtables` to `count-checks.ts`.

---

### How to trigger

```bash
SECRET="your-migration-secret"
BASE="https://newcrm-migration.onrender.com/api/migration"
MERCHANT_ID="67975aae5f248acf5c11dfc1"   # Kao Smile Club — recommended test merchant

# Pre-flight: verify receipt linkage assumption
curl -X POST "$BASE/verify-receipt-linkage?limit=500" -H "x-migration-secret: $SECRET"

# Migrate a single test merchant
curl -X POST "$BASE/start" -H "x-migration-secret: $SECRET" \
  -H "Content-Type: application/json" \
  -d "{\"merchantMongoId\":\"$MERCHANT_ID\"}"

# Monitor progress
curl "$BASE/status" -H "x-migration-secret: $SECRET"
curl "$BASE/merchants" -H "x-migration-secret: $SECRET"

# Post-load validation
curl "$BASE/validate" -H "x-migration-secret: $SECRET"

# Financial reconciliation (can take minutes for larger merchants)
curl -X POST "$BASE/recon" -H "x-migration-secret: $SECRET" \
  -H "Content-Type: application/json" \
  -d "{\"merchantMongoId\":\"$MERCHANT_ID\"}"

# If reconciliation fails, inspect
RUN_ID="<from-response>"
curl "$BASE/recon/report/$RUN_ID?status=fail" -H "x-migration-secret: $SECRET"

# Rollback if needed
curl -X POST "$BASE/rollback/$MERCHANT_ID" \
  -H "x-migration-secret: $SECRET" -H "x-initiated-by: test-reset"

# Audit rollback
curl "$BASE/rollback-log?merchantMongoId=$MERCHANT_ID" -H "x-migration-secret: $SECRET"
```
