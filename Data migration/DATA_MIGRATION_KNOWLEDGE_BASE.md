# Data Migration Knowledge Base: MongoDB → Supabase

## Overview

Migration from legacy CRM (MongoDB, multi-database architecture) to new CRM (Supabase/PostgreSQL, single-schema).

**MongoDB cluster:** `crm-prod.it7rm.mongodb.net` (13 databases)
**Supabase project:** `wkevmsedchftztoolkmi` (189 tables in `public` schema)

### Key Architectural Differences

| Aspect | MongoDB (Old) | Supabase (New) |
|---|---|---|
| Schema | Document-oriented, nested objects/arrays | Relational, normalized tables |
| IDs | ObjectId (24-char hex) | UUID |
| Naming | Mixed: `camelCase` (loyaltydb) / `snake_case` (crm_*_db) | `snake_case` only |
| Money | Number or Decimal128 | `numeric` |
| Timestamps | Date or epoch Number | `timestamptz` |
| Multi-tenancy | `merchantId` (ObjectId) or `merchant_id` (String) | `merchant_id` (UUID FK → merchant_master) |
| User reference | `userId` (ObjectId) or `user_id` (String) | `user_id` (UUID FK → user_accounts) |
| Nested data | Embedded documents & arrays | Normalized to child tables or JSONB |

---

## Migration Priority

Items with **Migrate=1** are first-wave. Others are deferred or may not migrate (rebuild from scratch in Supabase).

---

## Table Mapping by Area

### PRIORITY 1 (Migrate=1)

#### 1. Accounts (state)

| MongoDB Source | Supabase Target | Notes |
|---|---|---|
| `loyaltydb.users` (49 fields) | `user_accounts` (29 cols) | Core user identity, flags, referral fields |
| `loyaltydb.contacts` (77 fields) | `user_accounts` + `user_address` + `form_submissions`/`form_responses` | Massive document: profile, address, stats, tier cache, custom fields, surveys all embedded |
| `crm_user_db.users` (13 fields) | `user_accounts` | Microservice copy — lighter, newer schema |
| `loyaltydb.contacts.address` | `user_address` (16 cols) | Embedded doc → separate table |
| `loyaltydb.contacts.customFields[]` | `form_responses` via USER_PROFILE form | Array of embedded docs → normalized form system |
| `loyaltydb.contacts.surveyQuestions[]` | `survey_answers` or `form_responses` | Embedded array → normalized |
| `loyaltydb.users.memberTier` | `user_accounts.tier_id` + `tier_progress` | Embedded tier doc → FK + separate progress table |
| `loyaltydb.users.notifSetting` | `user_communication_preferences` | Embedded doc → separate table |

**Complexity: HIGH** — Three source collections with overlapping data, massive contacts doc needs decomposition.

**ID Mapping Strategy:** Must create a crosswalk table `migration_id_map(mongo_id, supabase_uuid, entity_type)` since ObjectId→UUID is not deterministic.

#### 2. Points History (ledger)

| MongoDB Source | Supabase Target | Notes |
|---|---|---|
| `loyaltydb.points` (20 fields) | `wallet_ledger` (23 cols) | Legacy point transactions (camelCase, ObjectId refs, epoch expiry) |
| `crm_point_db.point_transactions` (17 fields) | `wallet_ledger` | Newer point transactions (snake_case, String refs) |
| `crm_point_db.point_delay_transactions` (14 fields) | `wallet_ledger` + `currency_transactions_schedule` | Delayed/pending points — extra `delayed_to` field |

**Key transforms:**
- `earned_item.tier.earn_rate` (nested doc) → flattened into `wallet_ledger` JSONB metadata or separate columns
- `earned_item.store_property` → resolved to `store_id` FK
- `redemption_item` → only present on burn transactions
- `loyaltydb.points.expiredDate` is epoch Number → `timestamptz`
- Two different ID systems: ObjectId (legacy) vs String (new) for user/merchant refs

#### 3. Points Balance (state)

| MongoDB Source | Supabase Target | Notes |
|---|---|---|
| `loyaltydb.contacts.pointBalance` | `user_wallet.balance` | Embedded field in contacts doc |
| `crm_wallet_db.wallets` (7 fields) | `user_wallet` (6 cols) | Direct mapping, clean schema |

**Strategy:** Migrate `crm_wallet_db.wallets` as source of truth. Validate against `loyaltydb.contacts.pointBalance`. Reconcile discrepancies before migration.

#### 4. Tier Movement History (ledger)

| MongoDB Source | Supabase Target | Notes |
|---|---|---|
| `crm_tier_db.user_tier_transactions` (9 fields) | `tier_change_ledger` (11 cols) | Clean 1:1 mapping |

**Key transforms:**
- `type` (e.g. "ASSIGN") → `change_type`
- `current_tier_id` / `previous_tier_id` (String) → UUID FK → `tier_master`
- `user_display_name` → denormalized, can derive from `user_accounts`

#### 5. Reward Master (master)

| MongoDB Source | Supabase Target | Notes |
|---|---|---|
| `loyaltydb.rewards` (45 fields) | `reward_master` (32 cols) + `reward_points_conditions` + `reward_promo_code` | Complex: nested arrays for tier pricing, promo codes, quota limits |
| `loyaltydb.qrtables` (48 fields) | `reward_master` (type=COUPON) + `reward_promo_code` (alien codes) | QR-based coupons — similar structure to rewards but with QR/URL fields |
| `loyaltydb.rewardgroups` (10 fields) | Custom grouping table or `reward_master.group_id` | Reward groupings with images |
| `loyaltydb.rewardcategories` (8 fields) | `reward_category` (6 cols) | Clean mapping |

**Key nested structures to normalize:**
- `rewards.tierPointList[]` → `reward_points_conditions` rows
- `rewards.alienCodePartnerList[].alienList[]` → `reward_promo_code` rows
- `rewards.quotaLimitList[]` → `transaction_limits` rows
- `rewards.memberType[]` → `reward_master.allowed_type` / `allowed_persona` arrays
- `qrtables.alienCoupons[]` → `reward_promo_code` rows

#### 6. Redemptions History (ledger)

| MongoDB Source | Supabase Target | Notes |
|---|---|---|
| `loyaltydb.histories` (37 fields) | `reward_redemptions_ledger` (28 cols) | Redemption records with status tracking |

**Key transforms:**
- `objectId` → `reward_id` (FK to reward_master)
- `ticketCode` → `code`
- `exchangedType` → categorize into `fulfillment_method`
- `redeemedStoreId` / `usedStoreId` → `store_id` FK
- `alienCode` → link to `reward_promo_code`
- `points` / `pointBefore` → `points_deducted` + derive from wallet_ledger

#### 7. Marketplace Orders (ledger)

| MongoDB Source | Supabase Target | Notes |
|---|---|---|
| `third_party_ecommerce.lazada_order_transactions` (10 fields) | `order_ledger_mkp` (24 cols) | Platform-specific → unified schema |
| `third_party_ecommerce.shopee_order_transactions` (13 fields) | `order_ledger_mkp` | More fields (shipping, COD) |
| `third_party_ecommerce.tiktok_order_transactions` (15 fields) | `order_ledger_mkp` | Most discount breakdown fields |
| All `items[]` arrays | `order_items_ledger_mkp` (16 cols) | Nested arrays → child table rows |

**Key transforms:**
- Three separate platform collections → one unified `order_ledger_mkp` with `platform` discriminator
- `items[]` (embedded array) → normalize to `order_items_ledger_mkp` rows
- `shopee.items[].recipient_address` → may go to order-level address or discard
- All Decimal128 → `numeric`
- `shop_id` → resolve to `merchant_id` via `merchant_credentials`

#### 8. Marketplace Claimed Orders (ledger)

| MongoDB Source | Supabase Target | Notes |
|---|---|---|
| `third_party_ecommerce.lazada_order_claimed_transactions` (5 fields) | `order_ledger_mkp` (claim status columns) | Claimed = order linked to user for point earning |
| `third_party_ecommerce.shopee_order_claimed_transactions` | `order_ledger_mkp` | Same pattern |
| `third_party_ecommerce.tiktok_order_claimed_transactions` | `order_ledger_mkp` | Same pattern |

**Strategy:** These track which orders were claimed by users. In Supabase, this is likely a status/flag on `order_ledger_mkp` rather than separate tables.

#### 9. PDPA Consent History (ledger)

| MongoDB Source | Supabase Target | Notes |
|---|---|---|
| `loyaltydb.clientpdpas` (12 fields) | `user_consent_ledger` (8 cols) | Consent records |

**Key transforms:**
- `pdpaId` → `consent_version_id` FK → `consent_versions`
- `isAccept` → `action` (accept/reject)
- `nameForm` / `titleForm` / `detail` → **discard at extract** — denormalized copies of the PDPA policy HTML; canonical text lives in `loyaltydb.pdpas` and will migrate to `consent_versions`.

**Extract projection (see `src/migration/collections.ts`):** `{ detail: 0, titleForm: 0, nameForm: 0 }`.
- **Why:** each `clientpdpas` doc embeds the full Thai privacy-policy HTML in `detail` (~35 KB/doc). Without projection, a 100K-row merchant slice is ~3.7 GB over the wire and hangs the extractor on small Render instances. Projection drops per-doc size from ~36 KB → ~0.3 KB (100× reduction).

#### 10. Storefront: Receipts, Products, Stores (sf cluster)

| MongoDB Source | Supabase Target | Notes |
|---|---|---|
| `storefrontdb.product_orders` | `purchase_ledger` + `purchase_items_ledger` | Keyed by `organization_id` (ObjectId) = merchant mongo id |
| `storefrontdb.products` | `product_master` + `product_sku_master` | Keyed by `organization_id` |
| `storefrontdb.stores` | `store_master` | Keyed by `organization_id` |

**Status (2026-04-19):** storefrontdb has real data per-merchant (e.g. HER HYNESS: 516 stores, 396 products, 44,320 product_orders). The earlier "0 collections" note was stale.

**Extract caveat:** `organization_id` is stored as a Mongo `ObjectId`, not a string — the extractor in `src/migration/extract-collection.ts` coerces the input hex string via the `OBJECT_ID_MERCHANT_FIELDS` set (`{merchantId, organization_id}`). A previous version only coerced `merchantId`, which caused all `stg_sf_*` tables to extract 0 rows in single-merchant mode. Fixed 2026-04-19.

---

### PRIORITY 0 (Deferred / Rebuild)

| Area | Type | MongoDB Source | Likely Supabase Target | Notes |
|---|---|---|---|---|
| receipts (upload) | ledger | `loyaltydb.receipts`, `crm_receipt_db.receipt_*` | `purchase_receipt_upload` | Receipt image uploads |
| receipt rules | master | `crm_receipt_db.receipt_upload_rules/print_settings` | `earn_factor` / `earn_conditions` | Rules rebuilt in new earn system |
| wallet history | ledger | `crm_wallet_db.wallet_transactions` | `wallet_ledger` | If not covered by points history |
| points rules | master | `crm_point_db.point_rules`, `loyaltydb.pointspromotions` | `earn_factor`, `earn_conditions`, `earn_factor_group` | Earning rules — likely rebuild |
| custom form | state | `loyaltydb.contacts.customFields` | `form_fields` + `form_responses` | Embedded → form system |
| survey | state | `loyaltydb.contacts.surveyQuestions` | `survey_answers` / `form_responses` | Embedded → normalized |
| tier master | master | `crm_tier_db.tiers`, `crm_tier_db.tier_rules` | `tier_master`, `tier_conditions` | Tier definitions — likely rebuild |
| assets master | master | `crm_asset_db.asset_groups` | `asset_type`, `asset_field_definition` | Asset type definitions |
| asset | state | `crm_asset_db.assets` | `asset` | Registered assets |
| 3P integration master | master | `crm_third_party_db.webhook_settings` | `merchant_integration` | Webhook configs |
| 3P integration logs | ledger | `crm_third_party_db.sync_log/bsr_*` | Custom or discard | Historical logs |
| marketplace tokens | state | `third_party_ecommerce.*_access_tokens` | `merchant_credentials` | API tokens — re-auth likely needed |
| marketplace failed | ledger | `third_party_ecommerce.*_failed_transactions` | Discard or archive | Failed syncs |
| marketplace claim points | ledger | `loyaltydb.*cliampoints` | `wallet_ledger` (source_type=marketplace) | Post-claim point awards |
| pdpa master | master | `loyaltydb.pdpas` | `consent_versions` | PDPA form definitions |
| merchant master | master | `loyaltydb.merchants` | `merchant_master` | Merchant/brand defs |
| content/CMS | master | `loyaltydb.news/posters/navigationboxes/notifications` | `display_settings` or custom CMS | Content — likely rebuild |
| events & leaderboards | master | `loyaltydb.eventactivities/leaderboards` | `campaign_master`, `campaign_leaderboard` | Events |
| loyalty groups | state | `loyaltydb.loyaltygroups` | `persona_group_master`, `persona_master` | Customer classification |
| channels | master | `loyaltydb.channels` | `earn_channel` | Channel list |
| messaging | master | `loyaltydb.message_conditions/external_data_sources` | AMP tables or custom | Message targeting |
| roles & permissions | master | `loyaltydb.roles/permissions` | `admin_roles`, `admin_role_permissions` | RBAC — likely rebuild |
| auth & invites | state | `loyaltydb.invitelinks/refreshtokens` | `admin_invitations`, `refresh_tokens` | Auth — rebuild with new auth |
| plans | master | `loyaltydb.plans` | `merchant_plan` | Subscription plans |
| geo reference | master | `loyaltydb.provinces/amphurs/districts` | `address_th_province/district/subdistrict` | Thai geography — likely reload |
| member type history | ledger | `loyaltydb.membertypehistories` | `tier_change_ledger` or custom | Type change requests |
| member cards master | master | `loyaltydb.membercards` | `card_types` | Card definitions |
| member cards state | state | `loyaltydb.membercardusers` | `card_assignments`, `cards` | Cards assigned to users |
| member cards history | ledger | `loyaltydb.membercardhistories` | `card_transactions_ledger` | Card activity |
| campaigns master | master | `loyaltydb.campaigns` | `campaign_master` | Campaign definitions |
| campaigns state | state | `loyaltydb.campaign_users` | `campaign_participation` | Participants |
| campaigns history | ledger | `loyaltydb.campaign_user_transactions` | Custom ledger | Activity submissions |
| segments master | master | `loyaltydb.segments/segmentconditions` | `amp_audience_master` | Segment definitions |
| accounts audit | ledger | `loyaltydb.client_user_edit_revisions/userslogs` | Custom audit log | User edit history |
| suspicious points | ledger | `loyaltydb.suspiciouspoints` | Custom or flag on wallet_ledger | Flagged activities |
| variants | master | `loyaltydb.variants` | `product_sku_master` or custom | Product variants |
| variants sales | ledger | `loyaltydb.variantsales` | `purchase_items_ledger` or custom | Sales data |

---

## MongoDB Schema Reference (Priority Collections)

### Naming Convention Differences

| Database | Convention | ID Format | Example |
|---|---|---|---|
| `loyaltydb` | camelCase | ObjectId | `userId`, `merchantId`, `createdAt` |
| `crm_point_db` | snake_case | String (UUID-like) | `user_id`, `merchant_id`, `created_at` |
| `crm_wallet_db` | snake_case | String | Same as crm_point_db |
| `crm_user_db` | snake_case | String | Same |
| `crm_tier_db` | snake_case | String | Same |
| `third_party_ecommerce` | snake_case | String | `shop_id`, `order_id` |

### Common Type Transforms

| MongoDB Type | PostgreSQL Type | Transform Rule |
|---|---|---|
| ObjectId | uuid | Lookup via `migration_id_map` |
| String (UUID-like) | uuid | Direct cast |
| Decimal128 | numeric | Direct cast |
| Number (money) | numeric | Direct cast |
| Number (epoch ms) | timestamptz | `to_timestamp(value / 1000)` |
| Date | timestamptz | Direct |
| Boolean | boolean | Direct |
| String | text | Direct |
| Null | NULL | Direct |
| Embedded Document | JSONB or normalize to child table | Case-by-case |
| Array[Document] | Normalize to child table rows | One row per array element |
| Array[String] | text[] | Direct |
| `__v` | — | Discard (Mongoose version key) |
| `_id` | — | Discard (replaced by UUID) |

---

## Field Mapping CSV Format

### Recommended Structure

```
area,priority,mongo_source,mongo_field,mongo_type,supabase_table,supabase_column,supabase_type,transform,notes
```

### Nested Field Notation

| Pattern | Meaning | Example |
|---|---|---|
| `field` | Top-level field | `merchant_id` |
| `parent.child` | Nested document field | `earned_item.tier.id` |
| `parent.child.grandchild` | Deep nesting | `earned_item.tier.earn_rate.amount` |
| `array[]` | Array (simple values) | `imageUrl[]` |
| `array[].field` | Array of documents, specific field | `items[].sku` |
| `array[].nested.field` | Array of docs with nested doc | `alienCodePartnerList[].alienList[].alienCode` |

### Transform Codes

| Code | Meaning |
|---|---|
| `direct` | Copy as-is (type-compatible) |
| `cast::type` | Type conversion (e.g. `cast::numeric`) |
| `ObjectId→UUID` | Lookup crosswalk table |
| `epoch→timestamptz` | Convert epoch ms to timestamp |
| `flatten` | Embedded doc fields → columns on same table |
| `normalize→table_name` | Array/doc → rows in child table |
| `derive` | Computed from other data, don't migrate directly |
| `discard` | Not needed in new schema |
| `jsonb` | Store as JSONB column |
| `resolve→table.col` | Lookup FK (e.g. store name → store_id) |

---

## Migration Dependencies

```
1. merchant_master        ← Must exist first (all data references merchant)
2. tier_master            ← Needed for user tier FK
3. store_master           ← Needed for store FK resolution
4. user_accounts          ← Core entity, most things FK to this
5. user_wallet            ← Depends on user_accounts
6. wallet_ledger          ← Depends on user_wallet, user_accounts
7. reward_master          ← Independent of users
8. reward_redemptions     ← Depends on user_accounts, reward_master
9. tier_change_ledger     ← Depends on user_accounts, tier_master
10. order_ledger_mkp      ← Depends on merchant_credentials, user_accounts
11. user_consent_ledger   ← Depends on user_accounts, consent_versions
```

---

## Crosswalk / ID Mapping Requirements

A `migration_id_map` table is essential:

```sql
CREATE TABLE migration_id_map (
  mongo_id       text NOT NULL,
  supabase_id    uuid NOT NULL DEFAULT gen_random_uuid(),
  entity_type    text NOT NULL,  -- 'user', 'merchant', 'reward', 'tier', 'store', etc.
  mongo_database text,
  mongo_collection text,
  created_at     timestamptz DEFAULT now(),
  PRIMARY KEY (mongo_id, entity_type)
);
```

This allows:
- Deterministic UUID assignment for each MongoDB ObjectId
- Cross-reference during migration of related entities
- Validation and rollback capability

---

## Data Volume Estimates

| Database | Size | Primary Collections |
|---|---|---|
| `loyaltydb` | ~30 GB | contacts, users, points, rewards, histories (heaviest) |
| `third_party_ecommerce` | ~22 GB | Order transactions across 3 platforms |
| `crm_point_db` | ~1.1 GB | Point transactions |
| `crm_receipt_db` | ~949 MB | Receipt uploads |
| `crm_wallet_db` | ~599 MB | Wallets and wallet transactions |
| `crm_user_db` | ~178 MB | User microservice data |
| `crm_tier_db` | ~102 MB | Tier transactions |

---

## Storefront Cluster (sf)

`storefrontdb` has real data per merchant, keyed on `organization_id` (ObjectId = merchant mongo id). Priority collections:

| Collection | Per-merchant volume (HER HYNESS) | Target |
|---|---|---|
| `stores` | 516 | `store_master` |
| `products` | 396 | `product_master` / `product_sku_master` |
| `product_orders` | 44,320 | `purchase_ledger` / `purchase_items_ledger` |

**Extract ObjectId-coercion set** (see `extract-collection.ts`):

```ts
const OBJECT_ID_MERCHANT_FIELDS = new Set<string>([
  'merchantId',      // loyaltydb.*
  'organization_id', // storefrontdb.*
]);
```

Other merchant-id fields (`merchant_id` in `crm_*_db.*`, `shop_id` in `third_party_ecommerce.*`) are stored as plain strings and must **not** be coerced.

---

## Known Extraction Issues / Deferred Fixes

| Area | Issue | Status |
|---|---|---|
| `stg_mongo_consent` | `clientpdpas` docs embed full policy HTML in `detail`/`titleForm`/`nameForm` (~36 KB/doc, hangs extractor) | **Fixed 2026-04-19** — projection drops those fields at extract time |
| `stg_sf_*` | `organization_id` is ObjectId but extractor only coerced `merchantId` → 0 rows extracted for storefront in single-merchant mode | **Fixed 2026-04-19** — `OBJECT_ID_MERCHANT_FIELDS` now includes `organization_id` |
| `stg_mongo_orders_{lazada,shopee,tiktok}` | `shop_id` is a platform-specific ID (e.g. Lazada seller id `100184574113`), not merchant mongo id. Extract filter used merchant mongo id → 0 rows. Wave 5 also JOINs `stg.merchant_ref` against `merchant_master.mongo_id` but `merchant_ref` stored `shop_id` → mismatch | **Fixed 2026-04-20** — `CollectionConfig.marketplacePlatform` flag + `seedMarketplaceCredentials` step. See **Marketplace shop_id resolution** below. |
| `stg_mongo_orders_tiktok` (and other large cursors) | `MongoServerError: Executor error during getMore :: caused by :: operation exceeded time limit`. Streaming cursor held open while PG COPY flushed 10K-doc batches of fat marketplace docs (~5–15 s per flush) — Atlas tripped its per-op limit on the next `getMore`. Failed repeatedly on HER HYNESS's tiktok extract; retries restarted from zero since cursor position was lost. | **Fixed 2026-04-20** — extract now paginates by `_id > lastSeen` with `sort: {_id: 1}, limit: MONGO_BATCH`. Each page is a fresh indexed find (no `getMore`), so cursor timeouts are structurally impossible. Resumable on retry. See **Resumable `_id` pagination** below. |
| Wave 5 (`transform-5a/5b/5c-orders-*`) | `invalid input syntax for type numeric: "{"$numberDecimal":"0"}"` — marketplace money fields (`total_amount`, `shipping_fee`, `tax`, etc.) are stored as Mongo `Decimal128`. The extractor's `serializeDoc` only handled `ObjectId` and `bigint`; Decimal128 fell through to the driver's `toJSON()` which emits the EJSON envelope `{$numberDecimal: "..."}`. Downstream `(stg.raw->>'total_amount')::numeric` then failed. | **Fixed 2026-04-20** — `serializeDoc` now flattens `Decimal128` and `Long` via `.toString()` before JSON.stringify; existing `->>`/`::numeric` SQL works unchanged. |
| Wave 6b (`transform-6b-link`) | `error: invalid reference to FROM-clause entry for table "pru"` — the UPDATE target `purchase_receipt_upload pru` was referenced inside a JOIN's ON clause (`JOIN purchase_ledger pl ON ... AND pl.merchant_id = pru.merchant_id`). Postgres evaluates FROM-clause joins before the target is joined, so target-table references are illegal there. | **Fixed 2026-04-20** — rewrote to implicit cross-join (`FROM stg_mongo_receipts stg, purchase_ledger pl`) with all predicates moved into the `WHERE` clause where target-table references are legal. |
| Extract pipeline serialisation | Each extract-one did `fetchPage → process → flushBatch → fetchPage …` with Mongo and PG never busy at the same time. On flush-bound extracts (marketplace, `sf_bills`) that roughly doubled wall time vs the overlap-ideal: a 5–15 s PG flush per 10K docs was paired with a 0.5–2 s Atlas page fetch, both serial. Observed HER HYNESS run: ~9 min each for `orders_{lazada,shopee,tiktok}` and `sf_bills`. | **Fixed 2026-04-20** — `MONGO_BATCH` raised from 1K → 10K (matches `COPY_BATCH`), and the loop now kicks off the NEXT page's `find()` before processing+flushing the current page. Overlap is a simple one-deep prefetch on the shared PG client — memory bounded at one in-flight page + one in-flight flush buffer. See **Pipelined page fetch** below. |
| Single-slot flush on flush-bound extracts | With pipelining in place, `max(fetch, flush)` per iteration meant marketplace + sf_bills extracts were still flush-bound: ~8 s per 10K-row PG COPY+INSERT dominated the 1.5 s Atlas fetch. Extract wall time scaled linearly with flush time. | **Fixed 2026-04-20** — added `FLUSH_PARALLELISM = 2` and reshaped the loop to a 2-slot round-robin on fresh pooled connections. Two concurrent COPY+INSERTs commit independently against the same staging table; `ON CONFLICT (mongo_id) DO UPDATE` is commutative (a single Mongo page has no duplicate `_id`s, so no in-flight row conflict is possible). Expected ~2× on flush-bound extracts. See **Parallel flush** below. |
| Late-start on `concurrency: 5` fan-out | HER HYNESS run (2026-04-19 23:26 UTC): `lazada`/`tiktok` started at `t+3 s`, `sf_bills` at `t+6 min`, `shopee` at `t+10 min`. The Inngest concurrency cap left the two largest extracts queued for ~10 min behind smaller fast-finishing collections — pure wall-time tax with no database pressure. | **Fixed 2026-04-20** — raised `concurrency: { limit: 5 }` → `8` in `migration-extract-one` and bumped `getPgPool().max` from 10 → 20 (required for 8 × 2 peak connections with `FLUSH_PARALLELISM=2`). Memory envelope on Render Pro 4 GB verified below 50 %. |
| Storefront extract missing compound index `{organization_id, _id}` | `storefrontdb.{product_orders,products,stores}` have only a single-field `organization_id_1` index. The `_id`-paginated extract query `find({organization_id:X, _id:{$gt:last}}).sort({_id:1}).limit(10000)` falls back to an in-memory SORT of every merchant doc per page (verified via `.explain(executionStats)`: 44,331 keysExamined, 44,331 docsExamined, SORT stage with 54 MB in memory, 699 ms per page on HER HYNESS). For HER HYNESS this is ~3.5 s total (0.35 % of extract wall time — PG TOAST writes dominate). For 500K-order merchants ≈ 6 min Mongo time per extract; 2M+ merchants ≈ 45+ min. | **TODO before bulk backfill of large-storefront merchants** — not needed for HER HYNESS validation run (Mongo cost negligible relative to PG). Create via `mongosh` against storefront cluster: `use storefrontdb; db.product_orders.createIndex({organization_id:1, _id:1}, {name:'organization_id_1__id_1', background:true})` — repeat for `products` and `stores`. Build takes ~2-5 min on 5.2M-row `product_orders`; do between runs so it doesn't compete for Mongo I/O. Atlas UI cannot create this — the Create Index dropdown filters `_id` out; use mongosh or Compass. |
| Wave 5 cross-merchant scope leak | `wave-5{a,b,c}-orders-*.sql` and `wave-5d-order-items.sql` filtered by `stg.merchant_ref IN (SELECT mongo_id FROM migration_id_map WHERE entity_type='merchant')` — every migrated merchant. Effects: (1) single-merchant runs re-processed every other migrated merchant's marketplace staging (wasteful, idempotent); (2) when two per-merchant runs overlapped (e.g. HER HYNESS + Future Park concurrent bulk test), whichever wave 5 finished first would sweep up the other's partial/incomplete extract, creating half-finished `order_ledger_mkp` rows until the owning run caught up. | **Fixed 2026-04-20** — all four wave 5 SQL files now guard on `current_setting('migration.scope_merchant', true)`, matching the pattern already used by wave-4a/4b/6a. `WAVE_STEPS[5]` in `transform-wave.ts` marks each as `perMerchant: true` so `runSqlPerMerchant` sets the GUC per iteration. Empty GUC = no scope → stand-alone debug runs still work. |
| Wave 5 platform steps ran sequentially | 5a/5b/5c write disjoint rows into `order_ledger_mkp` (different `platform` discriminators, unique `mongo_id` per Mongo page) but executed one after another even though there's no read-after-write dependency between them. On a marketplace-heavy merchant each step takes minutes; total wave 5 wall time was the sum. | **Fixed 2026-04-20** — added `parallelGroup` marker on `SubStep`; the wave loop collects adjacent same-group entries and awaits them via `Promise.all`. 5a/5b/5c now share `parallelGroup: 'orders-ingest'`. Each step is still its own `step.run()` for Inngest observability. 5d stays outside the group because it JOINs `order_ledger_mkp` (written by 5a/b/c) and must wait. Wave 5 wall time drops from `sum(5a,5b,5c) + 5d + 5e` to `max(5a,5b,5c) + 5d + 5e`. |
| No bulk orchestrator for 79-merchant rollout | Fleet-wide migration required N individual `curl POST /migration/start` calls with no built-in way to cap concurrent merchants. Single-merchant endpoints existed and are isolated (per-merchant staging / target scoping, ON CONFLICT idempotency throughout) but there was no batched entry point. | **Fixed 2026-04-20** — `migration-run-full` now has `concurrency: { limit: BULK_MERCHANT_CONCURRENCY }` (env-configurable, default 3 for Render Pro 4 GB). New endpoint `POST /migration/bulk-start` enqueues one `migration/start` per target merchant; Inngest dispatches them N at a time, rest queue. Skips `SKIP_MERCHANT_IDS`, skips completed/live merchants by default. See **Bulk migration orchestration** below. |
| `getMore` cursor timeouts under concurrent-extract GC pressure | With HER HYNESS (2.88M shopee) + Future Park (1.8M points, 430K bills, 414K users — ~10× HER HYNESS's scale) running concurrently, 8 parallel extract-ones on Render Pro 4 GB hit GC-pause storms. Node event loop stalls for 5–30 s during major GCs, Mongo driver can't drain getMore response buffers fast enough, Atlas trips its per-op timeout (`MongoServerError: Executor error during getMore :: operation exceeded time limit`). Inngest's function-level `retries: 2` did eventually recover (data progressed), but each retry restarted from `lastId=null` — wasteful. Simultaneously observed: intermittent `Error performing request to SDK URL: Your server reset the connection` — Node event loop too busy to answer Inngest's step-request webhook → TCP RST. Root cause is client-side resource pressure, NOT an Atlas capacity issue (M60 is nowhere near saturation). | **Fixed 2026-04-20** — two defences: (a) per-page retry with exponential backoff inside `extractCollection` for transient patterns (`getMore`, `exceeded time limit`, network/socket errors) — 3 attempts with 500/1500/4000 ms backoff, keeps progress (no restart from `lastId=null`); (b) per-collection `mongoBatchSize` override on `CollectionConfig` — marketplace and `stg_sf_bills` reduced from 10K → 5K to halve in-flight page memory (fat docs), small-doc collections stay at 10K. Throughput-neutral (flush-bound extracts scale linearly either way) but roughly halves GC pressure per extract. Render Pro Plus (8 GB / 4 CPU) would further reduce recurrence risk if bulk concurrency grows beyond 3–5 merchants. See **Page-fetch retry + per-collection batch size** below. |
| Stuck orchestrator on lost fan-in events | Extract-all used 21 parallel `step.waitForEvent('migration/extract-one-done')` calls for fan-in. When Inngest's SDK connection to Render dropped mid-run (observed during the GC-pressure incident above), one or more `extract-one-done` events went undelivered even though the extract-one function itself reported "Completed" in the Inngest dashboard (its own step.run calls succeeded). Extract-all's corresponding `waitForEvent` never fired. Orchestrator hung for 44+ min on HER HYNESS, 26+ min on Future Park, with staging data fully populated but `migration_merchant_status.status` still stuck at `'extracting'` and zero transform waves triggered. Design is fundamentally fragile: single lost event = whole run wedged until 6h timeout. | **Fixed 2026-04-20** — replaced event-based fan-in with DB polling against a new `wave=0` sentinel in `migration_wave_status`. Extract-one now writes `status='running'` at start, `'completed'`/`'failed'` at end via durable `step.run` calls. Extract-all polls `SELECT ... WHERE run_id=$1 AND wave=0` every 15s (step.sleep + step.run) until all collections are no longer `'running'`. Source of truth is PG rows, not Inngest event delivery — resilient to any number of dropped events. The `step.sendEvent('extract-done')` signal is kept for observability but extract-all no longer depends on it. See **Extract fan-in via DB polling** below. |
| Stuck orchestrator on lost wave-done events (run-full layer) | The extract-all fan-in fix only covered the child-level hand-off (21× `extract-one-done` → extract-all). The parent `migration-run-full` still used 6 × `step.waitForEvent('migration/extract-done' \| 'migration/wave-done')` for its own child coordination (extract-all → run-full, transform-wave → run-full for each of waves 1,2,3,5,6,4). Same class of failure hit a second time on the 2026-04-20 merchant `66e2aa...4230b8` run: extract-all completed cleanly (all 21 staging tables populated, fan-in poll exited green, Inngest showed `migration-extract-all` as Completed at 28m 57s), but run-full's `wait-extract` waiter never fired. The `migration/extract-done` event was dropped in the same SDK-webhook window as the original incident. Run-full sat on `wait-extract` for 31m+ until cancelled. `migration_merchant_status.status` stuck at `'extracting'`, no transform waves triggered despite the 21 extract sub-steps all being `'completed'` in the DB. Identical failure mode, one layer up, still fragile for the same reason. | **Fixed 2026-04-20** — applied the DB-polling pattern at the run-full layer too. `transform-wave.ts` and `extract-all.ts` now each write a per-wave sentinel row (`sub_step='__wave__'`, `status='running'` at start → `'completed'`/`'failed'` at end, `error_detail` populated on failure). `run-migration.ts` replaces every `step.waitForEvent` with a `waitForWaveCompletion` helper that polls `migration_wave_status WHERE run_id=$1 AND wave=$2 AND sub_step='__wave__'` on the same 15s interval. Source of truth is the sentinel row, not event delivery — same resilience guarantee the extract-level fix gave, now uniform across all 7 phases (wave 0 extract + waves 1–6 transforms). `sendEvent('extract-done')` and `sendEvent('wave-done')` are retained purely for observability / external listeners. Also adds a `mark-merchant-failed` cleanup step so a crashed run-full flips `migration_merchant_status.status='failed'` instead of leaving it stuck at `'extracting'` or `'transforming'`. See **Run-full fan-in via DB polling** below. |

### Marketplace shop_id resolution (fix landed 2026-04-20)

**Source of truth:** `loyaltydb.merchants` — NOT `third_party_ecommerce.*_access_tokens`. The access-token collections only carry `{shop_id, access_token, refresh_token, expired_at}` and do **not** contain any `merchant_id` field (verified via MCP `collection-schema`). The authoritative `shop_id ↔ merchant` mapping lives on the merchant doc itself, embedded as three parallel arrays:

| Platform | Field path on `loyaltydb.merchants` | Example value |
|---|---|---|
| Lazada | `lazadaIntegrations[].country_user_info[].seller_id` (primary) or `.account_detail.seller_id` | `"100184574113"` (HER HYNESS) |
| Shopee | `shopeeIntegrations[].shop_id` | `"224882570"` (HER HYNESS) |
| TikTok | `tikTokIntegrations[].shop_list.id` | `"7495709562522995045"` |

**Resolution path:**

1. `seedMarketplaceCredentials` (new programmatic step, `src/migration/steps/seed-marketplace-credentials.ts`) reads each merchant's three integration arrays and UPSERTs rows into `merchant_credentials (merchant_id, service_name, external_id, credentials)` keyed by `service_name ∈ {lazada,shopee,tiktok}` with `external_id = shop_id`. The full integration payload (tokens, expiry, account metadata) goes into the `credentials` JSONB column for downstream API use.
2. `extract-collection.ts` detects marketplace collections via `config.marketplacePlatform`. Before opening the Mongo cursor it `SELECT external_id FROM merchant_credentials JOIN merchant_master ON mongo_id = …` and filters the cursor by `{shop_id: {$in: resolvedShopIds}}`. The `merchant_ref` column written to staging holds the owning merchant's mongo hex (not the shop_id), so Wave 5 SQL's existing JOIN `merchant_master.mongo_id = stg.merchant_ref` resolves without change.
3. `extract-all.ts` (initial load) and `daily-sync.ts` (cron) both run `seedMarketplaceCredentials` BEFORE the fan-out. Single-merchant mode scopes the seed to that merchant; bulk mode refreshes every integration on the roster.
4. `transform-claimed-orders.ts` uses the same `merchant_credentials` lookup to scope `*_order_claimed_transactions` — prior bug where it filtered by `{shop_id: merchantMongoId}` is now fixed.

**New supporting index:** `merchant_credentials_marketplace_uniq` (partial unique index on `(merchant_id, service_name, external_id)` WHERE `service_name IN ('lazada','shopee','tiktok')`) — enables the `ON CONFLICT … DO UPDATE` path. Scoped to marketplace services so it doesn't collide with the existing email-as-external_id rows used by native-CRM merchants.

---

### Resumable `_id` pagination (fix landed 2026-04-20)

**Problem:** the previous extract used a single streaming cursor:

```ts
const cursor = coll.find(filter, { batchSize: MONGO_BATCH });
for await (const doc of cursor) { /* push to PG COPY buffer, flush at 10K */ }
```

On the three `third_party_ecommerce.*_order_transactions` collections (23.75 GB, 75M docs across all 12 collections in the cluster) this repeatedly tripped:

```text
MongoServerError: Executor error during getMore :: caused by :: operation exceeded time limit
```

Mechanism: each `flushBatch` (COPY + temp-table upsert of 10K rows of fat marketplace docs) takes 5–15 s. Mongo holds the cursor server-side across that gap. When we resume iteration the next `getMore` can't complete fast enough and Atlas kills it. Cursor death means the Inngest retry (`retries: 2`) restarts the extract from zero — the reason the tiktok staging count was an exact round 580,000 on failure (always died near the same spot).

**Fix:** replaced the streaming loop with `_id > lastSeen` pagination:

```ts
let lastId: ObjectId | null = null;
while (true) {
  const pageFilter = lastId ? { ...filter, _id: { $gt: lastId } } : filter;
  const page = await coll.find(pageFilter, {
    sort: { _id: 1 },
    limit: MONGO_BATCH,
    projection: config.projection,
  }).toArray();
  if (page.length === 0) break;
  for (const doc of page) { /* … */ }
  lastId = page[page.length - 1]._id as ObjectId;
  if (page.length < MONGO_BATCH) break;
}
```

Properties:

1. **No `getMore` round-trips** — each page is a one-shot `find`. Atlas cursor-timeout window structurally cannot apply.
2. **Uses the default `_id_` B-tree index** — `{_id: {$gt: X}}` + `sort({_id:1})` is an index range scan; no new index required.
3. **Resumable.** Staging uses `INSERT … ON CONFLICT (mongo_id) DO UPDATE`, so a retry that restarts from `lastId=0` is idempotent even without explicit checkpointing; in practice every retry picks up where the previous page finished.
4. **Negligible overhead.** One B-tree seek per page (~1 ms) × N/MONGO_BATCH pages — e.g. ~1.2 s total across the 1.2M-row shopee extract.

Applies to every collection uniformly (loyaltydb, crm_*, storefrontdb, third_party_ecommerce) — the same code path is strictly more resilient than streaming cursors for every size class, so no need for a per-collection flag. This is a prerequisite for bulk migration across all 79 merchants, where the naive streaming cursor against 75M third_party_ecommerce docs would fail repeatedly.

---

### Pipelined page fetch (fix landed 2026-04-20)

**Problem:** the `_id` pagination loop was structurally serial. Each iteration looked like:

```text
await fetchPage(lastId)   ←  0.5 – 2 s (Atlas RTT + serve)
process page
await flushBatch(buffer)  ←  5 – 15 s (CREATE TEMP + COPY + INSERT…ON CONFLICT + COMMIT)
```

Mongo was idle during the flush; PG was idle during the fetch. On the four flush-bound extracts (`stg_sf_bills`, `stg_mongo_orders_{lazada,shopee,tiktok}`) wall time was approximately `(fetch + flush) × pages` — HER HYNESS observed ~9 min per collection in parallel.

**Fix:** two small changes in `src/migration/extract-collection.ts`:

1. `MONGO_BATCH` raised from 1 000 → 10 000, matching `COPY_BATCH`. Every page now triggers exactly one flush, cutting Atlas round-trips by 10×.
2. The loop kicks off the next page's `find()` *before* processing and flushing the current one:

```ts
let pagePromise: Promise<any[]> = fetchPage(null);
while (true) {
  const page = await pagePromise;
  if (page.length === 0) break;
  const nextLastId = page[page.length - 1]._id as ObjectId;
  const shortPage = page.length < MONGO_BATCH;
  pagePromise = shortPage ? Promise.resolve([]) : fetchPage(nextLastId);

  for (const doc of page) { /* format → buffer → flush at COPY_BATCH */ }

  if (shortPage) break;
}
```

Effective wall time becomes `max(fetch, flush) × pages` — when flush dominates (always true on marketplace / sf_bills), Atlas latency disappears from the critical path.

**Invariants preserved:**

- Filter, page ordering (`sort: {_id:1}`), and upsert key (`ON CONFLICT (mongo_id)`) are unchanged — no migration or schema impact.
- At most one flush in flight: the same pooled PG client serialises writes, so memory stays bounded at roughly two pages + one buffer (~100 MB worst case on fat marketplace docs).
- Resumable-on-crash: if the process dies mid-flush, Inngest's retry restarts this collection from `lastId = null` and `ON CONFLICT DO UPDATE` rewrites any previously-committed rows. A prefetched-but-unused next page is discarded without side effect.

Not worth chasing further without measurement: parallel flushes on two PG connections would roughly halve time on marketplace extracts specifically (since flush is ≥10× longer than fetch), but adds a second transaction to reason about. Defer until we've measured the simple overlap win.

**Follow-up (2026-04-20):** live stats from the HER HYNESS run validated that marketplace and sf_bills extracts were still flush-bound even with pipelining (~8 s flush per 10K vs ~1.5 s fetch). Parallel flush landed — see **Parallel flush** below.

---

### Parallel flush (fix landed 2026-04-20)

**Stats that justified the change** (HER HYNESS run, merchant `66e2aa1173943473744230b8`, measured from `MIN(loaded_at)` → `MAX(loaded_at)` on each staging table):

| Collection | Rows | Span (s) | Rows/sec | Mongo cluster |
|---|---|---|---|---|
| `stg_sf_bills` | 44,331 | 1002 | 44 | sf M50 |
| `stg_mongo_orders_lazada` | 683,276 | 547 | 1,249 | crm M60 |
| `stg_mongo_orders_tiktok` | 771,229 | 655 | 1,177 | crm M60 |
| `stg_mongo_orders_shopee` (still running) | 1,230,000 / 2,877,520 | 903 so far | 1,361 | crm M60 |

`stg_sf_bills`'s 30× slower per-row rate traces to a 96 % TOAST ratio (`pg_total_relation_size`: 5 MB table / 140 MB TOAST+idx) — the docs exceed PG's ~2 KB TOAST threshold and every row pays the out-of-line storage cost. Marketplace docs inline (7 % TOAST on shopee). Parallel flush halves the commit cycle for both classes; the TOAST cost itself is not eliminated, but now runs on two connections at once.

**Design:**

```ts
const FLUSH_PARALLELISM = 2;
const flushSlots: Promise<void>[] = Array.from(
  { length: FLUSH_PARALLELISM },
  () => Promise.resolve()
);
let flushSlotIdx = 0;

const flushBatchOnPool = async (rows: string[]) => {
  const client = await getPgPool().connect();
  try { await flushBatch(client, stagingTable, rows); }
  finally { client.release(); }
};

// inside the page loop, when buffer is full:
const toFlush = buffer; buffer = [];
await flushSlots[flushSlotIdx];                           // wait only for THIS slot
flushSlots[flushSlotIdx] = flushBatchOnPool(toFlush);     // new fresh-connection flush
flushSlotIdx = (flushSlotIdx + 1) % FLUSH_PARALLELISM;

// at end:
await Promise.all(flushSlots);                            // drain remaining in-flight
if (buffer.length > 0) await flushBatchOnPool(buffer);    // remainder
```

**Correctness invariants:**

- Two simultaneous COPY+INSERT flushes target the same staging table but disjoint sets of `mongo_id`s (a Mongo page sorted by `_id` has no duplicates and we clear `buffer` before handing it off), so `ON CONFLICT (mongo_id) DO UPDATE` has no two-row contention between slots.
- `INSERT … ON CONFLICT` takes per-row locks, not table locks, so the two transactions commit in any order without blocking each other.
- On error in any slot, `Promise.allSettled(flushSlots)` in the outer catch lets other in-flight flushes drain before the function throws. Any partially-committed rows are idempotent on retry (same `mongo_id` conflict path).

**Connection-pool sizing:** raised `getPgPool().max` from 10 → 20 in `src/lib/pg.ts`. Peak usage: `concurrency(extract-one) × FLUSH_PARALLELISM = 8 × 2 = 16` for flushes, plus ~2 for API routes and status endpoints ≈ 18. Supabase allows ~200 direct connections so we're well under the server ceiling.

**Not tried:** `FLUSH_PARALLELISM > 2`. Once `flush/N < fetch` the pipeline becomes fetch-bound and further slots just waste memory. For the observed HER HYNESS shape, N=2 hits `max(1.5 s fetch, 4 s flush) ≈ 4 s` per iteration — already close enough to fetch-bound that N=3 would buy single-digit percent. Revisit if marketplace doc sizes grow or if we move the worker to a plan with faster CPU.

---

### Inngest concurrency bump to 8 (landed 2026-04-20)

**Why:** HER HYNESS timeline showed the 5-slot cap costing ~10 min of pure wall-time. Fan-out kicked at `23:26:06`, but:

- `stg_sf_bills`  first write at `23:32:02`  (t + 6 min)
- `stg_mongo_orders_shopee` first write at `23:36:47`  (t + 10 min)

Both large collections had to wait for smaller collections to release a slot — there was no database pressure preventing them from running. The cap was sized for safety during the initial rollout.

**New setting:** `concurrency: { limit: 8 }` in `extractOneFn` (`src/migration/inngest/extract-one.ts`).

**Memory envelope on Render Pro (4 GB)** with parallel flush active:

```text
8 concurrent extracts × max(50 MB fat, 5 MB small) × (page + prefetch + 2 flush buffers)
  worst-case (all 8 are fat, which never happens — only 4 fat collections exist):
  8 × 4 × 50 MB = 1.6 GB peak
  typical: 4 fat + 4 small = 4×200 + 4×20 ≈ 880 MB peak
+ Node + driver baseline ≈ 400 MB
= <2 GB of 4 GB total, comfortable
```

**Do NOT raise further without re-measuring.** The next bump (→ 16) would push worst-case toward the 4 GB Render Pro ceiling and would need either Pro Plus (8 GB) or a measurement-driven reduction in `FLUSH_PARALLELISM`. Bulk-merchant backfill across all 79 merchants will need this decision re-examined against the per-merchant memory cost multiplied by the cross-merchant Inngest concurrency.

---

### Wave 5 per-merchant scope + platform parallelisation (fix landed 2026-04-20)

**Problem — scope leak:** `wave-5{a,b,c}-orders-*.sql` and `wave-5d-order-items.sql` filtered on `stg.merchant_ref IN (SELECT mongo_id FROM migration_id_map WHERE entity_type='merchant')` — i.e. every migrated merchant. This matters under two conditions:

1. **Single-merchant re-runs** wasted work re-processing every previously-migrated merchant's marketplace staging on every trigger. Idempotent via `ON CONFLICT` but unnecessary.
2. **Concurrent per-merchant runs** (e.g. HER HYNESS + Future Park bulk test) caused whichever run reached wave 5 first to sweep up the other's partial, still-extracting staging data. `order_ledger_mkp` ended up temporarily inconsistent until the owning run completed.

**Problem — sequential execution:** 5a/5b/5c inside a single wave run serially even though they write disjoint `platform` discriminators into the same `order_ledger_mkp` with unique `mongo_id`s — no row-level contention, but wave 5 wall time was the sum of all three platforms.

**Fix — scope guard (matches wave-6a-bills / wave-4a-points-old pattern):**

```sql
AND (
  COALESCE(current_setting('migration.scope_merchant', true), '') = ''
  OR stg.merchant_ref = current_setting('migration.scope_merchant', true)
)
```

Added to all four wave 5 SQL files. `WAVE_STEPS[5]` now marks every sub-step as `perMerchant: true` so `runSqlPerMerchant` sets the GUC for each iteration. Empty GUC (stand-alone debug execution without a scope) short-circuits the predicate — SQL files remain runnable as-is.

**Fix — parallel group for 5a/b/c:**

New `parallelGroup` marker on `SubStep` in `transform-wave.ts`. The wave executor collects *contiguous adjacent* steps sharing the same group name and awaits them via `Promise.all(group.map(step.run))`:

```ts
5: [
  { file: 'wave-5a-…', label: '5a-orders-lazada', perMerchant: true, parallelGroup: 'orders-ingest' },
  { file: 'wave-5b-…', label: '5b-orders-shopee', perMerchant: true, parallelGroup: 'orders-ingest' },
  { file: 'wave-5c-…', label: '5c-orders-tiktok', perMerchant: true, parallelGroup: 'orders-ingest' },
  { file: 'wave-5d-…', label: '5d-order-items',  perMerchant: true },   // waits for 5a/b/c
  { fn: …,             label: '5e-claimed-orders' },
],
```

**Invariants preserved:**

- Each sub-step remains its own `step.run(...)` — Inngest still records individual retry/timeout state. We're only parallelising at the JS promise layer, not merging Inngest step boundaries.
- 5a/5b/5c are row-level disjoint (unique mongo_id per Mongo page, disjoint `platform` column). `ON CONFLICT (mongo_id) DO UPDATE` has no inter-slot contention.
- 5d joins `order_ledger_mkp` (written by 5a/b/c) so it has a read-after-write dependency — it stays outside the group and runs after. Same for 5e (`transformClaimedOrders`).
- `parallelGroup` only collapses CONTIGUOUS peers. Non-adjacent same-group entries are treated as separate groups by design, keeps the parallel surface visually obvious in `WAVE_STEPS`.

**Wall-time impact:** wave 5 drops from `sum(5a, 5b, 5c) + 5d + 5e` to `max(5a, 5b, 5c) + 5d + 5e`. On a marketplace-heavy merchant (HER HYNESS shape) that's a ~3× speedup on the 5a–c segment specifically, ~50 % speedup on wave 5 overall (since 5d can't parallelise).

---

### Bulk migration orchestration (landed 2026-04-20)

**Goal:** migrate 79 merchants end-to-end without bespoke orchestration code, with controlled concurrency bounded by Render's resource envelope.

**Design:** use Inngest's built-in per-function concurrency ceiling rather than write a step-based scheduler. `migration-run-full` now declares:

```ts
concurrency: { limit: BULK_MERCHANT_CONCURRENCY }
```

where `BULK_MERCHANT_CONCURRENCY` is read from env (default `3`). Firing N `migration/start` events enqueues N pipeline runs; Inngest dispatches `BULK_MERCHANT_CONCURRENCY` at a time and queues the rest. No custom orchestrator, no new DB table, no coupling between merchants.

**New endpoint — `POST /migration/bulk-start`** (in `src/routes/migration.ts`):

```json
{
  "merchantMongoIds": ["…", "…"],     // optional — default = all merchants
  "skipCompleted":    true,             // optional — default true
  "includeFailed":    true              // optional — default true (retry failed)
}
```

Resolution rules:

1. Start from the requested list, or every merchant in `merchant_master` with `mongo_id IS NOT NULL`.
2. Always drop `SKIP_MERCHANT_IDS` entries (`collections.ts` blocklist: Suntory Wellness, Rocket Retail, Dulux, BEARHOUSE, QA Rocket Test, Syngenta).
3. When `skipCompleted=true` (default): drop merchants with `migration_merchant_status.status ∈ {completed, live}`.
4. When `includeFailed=false`: also drop `failed` / `rolled_back`. Default `true` so failures retry automatically.
5. Issue a single batched `inngest.send([...])` — one event per surviving target.

Returns `{ triggered: [...], skipped: [...] }` so the caller can audit the decision.

**Resource envelope rationale for the default of 3 on Render Pro 4 GB:**

```text
Per-merchant extract peak:  ~250 MB (8 extract-one × ~50 MB fat pages × 1 in-flight flush buffer/extract)
                            but capped by extract-one's own concurrency:{limit:8} across the fleet

3 merchants concurrent:     ≤ 8 extract-one slots total (global cap), so memory ≈ 800 MB
                            + 3 transform-wave processes each holding 1 PG connection
                            + Node + driver baseline ≈ 400 MB
Total peak:                 ~1.3 GB of 4 GB → comfortable
PG connections:             ≤ 16 for extracts + ~3 for transforms + ~2 for API = ~21 peak
                            pool max=20 is tight — see "Tuning" below
```

**Tuning ladder:**

| Render plan | Recommended `BULK_MERCHANT_CONCURRENCY` | PG pool `max` change needed |
|---|---|---|
| Pro (4 GB)        | 3 (default) | — (pool=20 is sufficient) |
| Pro Plus (8 GB)   | 5           | bump `getPgPool().max` → 30 |
| Pro Max (16 GB)   | 8+          | bump `getPgPool().max` → 40+ |

**When NOT to use bulk-start:**

- Mid-migration (e.g. HER HYNESS currently extracting): fine for OTHER merchants (isolation is clean since wave 5 scope fix), but don't re-trigger a merchant whose previous run hasn't finished — Inngest allows parallel same-merchant invocations and they'd race on `migration_merchant_status` writes.
- When reconciling a specific failed merchant: use single `POST /start` with `merchantMongoId`, not bulk.

**Operational flow for full-fleet rollout:**

1. Ensure storefront compound index exists (see KB "Known Extraction Issues" — storefrontdb `{organization_id, _id}`).
2. Confirm `BULK_MERCHANT_CONCURRENCY` env matches plan (or accept default 3).
3. `POST /migration/bulk-start {}` — triggers everyone not yet done.
4. Poll `GET /migration/progress/detailed` for per-merchant status.
5. Re-run `POST /migration/bulk-start {"includeFailed": true}` after any individual failures to retry them.
6. Post-verification, call `POST /migration/live/:merchantMongoId` per merchant to stop daily sync.

---

### Page-fetch retry + per-collection batch size (fix landed 2026-04-20)

**The trigger:** running HER HYNESS (2.88M shopee rows) and Future Park (1.8M points, 430K bills, 414K users — ~10× HER HYNESS's scale across the board) concurrently exposed a GC-pressure failure mode that wasn't visible in any single-merchant run:

```text
MongoServerError: Executor error during getMore ::
  caused by :: operation exceeded time limit
  at FindCursor.fetchBatch (mongodb/lib/cursor/abstract_cursor.js:614:16)
  at async FindCursor.next       (mongodb/lib/cursor/abstract_cursor.js:542:17)
  at async extract-stg_mongo_consent
```

Plus intermittently:

```text
Error performing request to SDK URL: Your server reset the connection while we were sending the request.
```

**Why `getMore` even though we use `_id > lastId` pagination:** the 2026-04-19 streaming-cursor fix eliminated cross-page `getMore`s, but `coll.find(filter, {limit: 10000}).toArray()` still uses `getMore` internally WITHIN a single page because results stream back in 16 MB chunks. On fat docs (marketplace ~2–5 KB/doc, sf_bills ~3 KB with 96 % TOAST), a 10K-doc page requires 3–10 intra-page `getMore` round trips.

**Why it fails now and not before:** these `getMore` calls all complete during one `.toArray()` await with no delays of our own. But when 8 concurrent extracts run on Render Pro (2 CPU cores, 4 GB RAM) with fat in-memory pages from a larger merchant like Future Park, Node's event loop enters 5–30 s GC pause windows. Mongo's driver can't drain `getMore` response buffers during those pauses → Atlas sees the cursor as idle past its per-op threshold (~30 s) → server terminates cursor → client gets the `executor error`. Side effect: Node also can't respond to Inngest's webhook POSTs → connection resets.

**Confirmation that it's client-side:** measured throughput during the incident was still healthy (~2,915 rows/sec for Future Park points, ~1,369 rows/sec for HER HYNESS shopee). Atlas M60 had plenty of headroom — the bottleneck was Node's event loop and GC, not Mongo.

**Fix (a) — per-page retry with exponential backoff** in `src/migration/extract-collection.ts`:

```ts
const PAGE_FETCH_MAX_ATTEMPTS = 3;
const PAGE_FETCH_BACKOFF_MS = [500, 1500, 4000];
const TRANSIENT_MONGO_ERROR_PATTERN =
  /getMore|operation exceeded time limit|ECONNRESET|ETIMEDOUT|socket|network|topology|not primary|ServerSelectionTimeout/i;

for (let attempt = 0; attempt < PAGE_FETCH_MAX_ATTEMPTS; attempt++) {
  try {
    return await coll.find(pageFilter, findOpts).toArray();
  } catch (err) {
    const isLastAttempt = attempt === PAGE_FETCH_MAX_ATTEMPTS - 1;
    const transient = TRANSIENT_MONGO_ERROR_PATTERN.test(err.message) || TRANSIENT_MONGO_ERROR_PATTERN.test(err.name);
    if (isLastAttempt || !transient) throw err;
    await sleep(PAGE_FETCH_BACKOFF_MS[attempt]);
  }
}
```

Page-level recovery — no impact on `lastId`, no restart-from-zero behaviour. The 500/1500/4000 ms backoff gives the event loop time to finish whatever GC storm triggered the failure, then retries. Non-transient errors (auth, bad filter, missing collection) still throw immediately to surface real bugs.

**Fix (b) — per-collection `mongoBatchSize` override** in `src/migration/collections.ts`:

```ts
{ stagingTable: 'stg_mongo_orders_lazada', …, mongoBatchSize: 5_000 },
{ stagingTable: 'stg_mongo_orders_shopee', …, mongoBatchSize: 5_000 },
{ stagingTable: 'stg_mongo_orders_tiktok', …, mongoBatchSize: 5_000 },
{ stagingTable: 'stg_sf_bills',             …, mongoBatchSize: 5_000 },
// All others use the default MONGO_BATCH = 10_000
```

Halves in-flight page memory on the four known-fat collections:

| Per in-flight page (fat docs, 5 KB/doc) | Before | After |
|---|---|---|
| 1 in-memory BSON page | 50 MB | 25 MB |
| 1 prefetched BSON page | 50 MB | 25 MB |
| 2 COPY buffers (FLUSH_PARALLELISM) | 100 MB | 50 MB |
| **Per fat extract** | **200 MB** | **100 MB** |
| **8 concurrent (global cap)** | **1.6 GB** | **800 MB** |

Throughput is unchanged for these collections because they're flush-bound, not fetch-bound — `max(fetch, flush / FLUSH_PARALLELISM)` scales linearly either way. Small-doc collections keep 10K because they benefit from amortising Atlas RTT over more rows.

**Combined effect:**

| Failure mode | Before fixes | After fixes |
|---|---|---|
| Single `getMore` timeout | Whole Inngest step fails → retry restarts extract from `lastId=null` (idempotent via ON CONFLICT but wastes 5–30 min of progress) | Page-level retry recovers within 500–4000 ms, keeps progress |
| Node OOM / GC storm on fat pages | 8 × 200 MB = 1.6 GB peak on Render Pro 4 GB — tight enough to cause GC pauses that cascade | 8 × 100 MB = 800 MB peak — comfortable on Pro (4 GB), trivial on Pro Plus (8 GB) |
| SDK connection reset | Event loop busy enough to miss Inngest webhook responses | Less memory pressure → less GC → event loop stays responsive |

**Next layer of protection** if future workloads still stress the system: upgrade Render Pro → Pro Plus (2× CPU, 2× RAM). Doesn't remove the code fix — they're complementary. Code fix is cheap and permanent; Render upgrade is tunable and reversible.

---

### Extract fan-in via DB polling (fix landed 2026-04-20)

**Problem observed on HER HYNESS + Future Park concurrent run:**

All 21 `migration-extract-one` functions reported **Completed** in the Inngest dashboard (confirmed from screenshots: every row green). Staging tables had every expected row (`stg_mongo_orders_shopee = 2,877,596` matching Mongo total for HER HYNESS, etc). But `migration-extract-all` and `migration-run-full` remained **Running** for 44+ minutes post-extract-completion. `migration_merchant_status.status` stayed stuck at `'extracting'`. Zero rows in `migration_wave_status` — no transform wave ever started.

Diagnosis via Supabase: `migration_id_map` contained HER HYNESS's merchant row (from a prior run's `populate-merchant-id-map` step, which runs AFTER extract completion). No wave-status rows for the current run. So the orchestrator was stuck strictly between `step.waitForEvent` on fan-in and `populate-merchant-id-map`.

**Root cause:** the previous fan-in used 21 parallel `step.waitForEvent('migration/extract-one-done')` calls, one per collection. Under the GC-pressure incident (see "Page-fetch retry + per-collection batch size" above), Inngest's connection to Render was resetting intermittently. One or more `extract-one-done` events never reached extract-all's waiter even though extract-one's own step.run calls succeeded and reported "Completed" to Inngest. With 21 parallel waiters on independent matches, a single dropped event → the whole run wedges until the 6h `timeout` fires.

**Why it's fragile by design:** event delivery is effectively fire-and-forget from extract-one's perspective. `step.sendEvent` is a step, so Inngest *retries* delivery if the function is retried — but if the function completed successfully on its first attempt, no retry is triggered. The send either made it to the event bus or didn't. There's no confirmation loop.

**Fix:** DB polling against a new sentinel in the existing `migration_wave_status` table.

**`wave=0` convention:** `migration_wave_status` already tracks transform waves as `wave ∈ {1..6}`. We now use `wave=0` for extract phase, one row per `sub_step = 'extract-${stagingTable}'`. No schema change — same columns (`run_id, wave, sub_step, status, started_at, completed_at, rows_written, error_detail`), just a reserved wave value.

**Extract-one writes the tracker** via durable `step.run` calls:

```ts
// On start
await step.run(`track-start-${stagingTable}`, () =>
  pgQuery(`INSERT INTO migration_wave_status … VALUES ($1::uuid, 0, $2, 'running', …)
           ON CONFLICT (run_id, wave, sub_step) DO UPDATE SET status='running', …`,
          [batchId, `extract-${stagingTable}`]));

// On success
await step.run(`track-complete-${stagingTable}`, () =>
  pgQuery(`UPDATE migration_wave_status SET status='completed', completed_at=now(), rows_written=$3
           WHERE run_id=$1::uuid AND wave=0 AND sub_step=$2`,
          [batchId, `extract-${stagingTable}`, rowCount]));

// On failure (inside catch, before rethrow)
await step.run(`track-failed-${stagingTable}`, () => …);
```

Each is its own `step.run` so Inngest retries replay deterministically.

**Extract-all polls** the tracker instead of waiting on 21 events:

```ts
const POLL_INTERVAL_SEC = 15;
const POLL_MAX_ITERATIONS = 960; // 4h cap

for (let i = 0; i < POLL_MAX_ITERATIONS; i++) {
  const progress = await step.run(`fan-in-check-${i}`, async () => {
    const res = await pgQuery(
      `SELECT status, sub_step FROM migration_wave_status WHERE run_id=$1::uuid AND wave=0`,
      [batchId]
    );
    return {
      total: res.rowCount,
      completed: res.rows.filter(r => r.status === 'completed').length,
      failed:    res.rows.filter(r => r.status === 'failed').length,
      running:   res.rows.filter(r => r.status === 'running').length,
      failedTables: res.rows.filter(r => r.status === 'failed').map(r => r.sub_step),
    };
  });
  if (progress.total >= expectedTotal && progress.running === 0) {
    if (progress.failed > 0) throw new Error(`Extract failed for ${progress.failed}/${expectedTotal}: …`);
    break;
  }
  await step.sleep(`fan-in-wait-${i}`, `${POLL_INTERVAL_SEC}s`);
}
```

**Invariants preserved:**

- Same `batchId` correlation as before — polling is strictly scoped to the caller's run.
- `migration/extract-one-done` events are still emitted for observability and backward compatibility with daily-sync callers. `extract-all` just doesn't depend on them anymore.
- Source of truth for "did extract X complete" is now the PG row, which is written via durable `step.run`. Inngest's retry-and-replay semantics ensure the row is present as long as the extract itself ran (which we can independently verify — staging row counts).

**Cost:** 1 SELECT every 15s (~4 reads/min × 30 min extract ≈ 120 reads per merchant). Each read is a single-condition index scan on `migration_wave_status (run_id, wave)` — sub-millisecond. Total PG load is trivial.

**Step budget:** typical single-merchant extract finishes in 15–40 min = 60–160 poll iterations = 120–320 Inngest steps for the fan-in. 4h worst-case cap = 960 iterations = 1920 steps; exceeds Inngest's ~1000 soft limit but only triggers for genuinely broken extracts. If we see this in practice, bump the step plan or reduce the cap.

**Unblocks stuck orchestrators going forward.** For runs that hung on the old fan-in (like the HER HYNESS/Future Park incident), the only recovery is to cancel + re-trigger — no backwards compatibility for in-flight runs. Post-deploy, any new run uses the polling path.

---

### Run-full fan-in via DB polling (fix landed 2026-04-20)

**Problem observed on 2026-04-20 single-merchant run (`66e2aa...4230b8`):**

`migration-extract-all` ran for 28m 57s and completed **green** in the Inngest dashboard — internal 21-collection fan-in polled `migration_wave_status wave=0` to completion exactly as designed. All 21 `extract-*` sub_steps showed `status='completed'`, all 4.8M staging rows landed, `summary.percentComplete=100`. But the parent `migration-run-full` sat stuck on its `wait-extract` step for 31m+ before being cancelled. `migration_merchant_status.status` remained `'extracting'`, no transform waves triggered.

**Root cause:** the extract-level fix closed the child-fan-in hole but left the parent-level hand-off using the same lost-event pattern. `run-migration.ts` had six `step.waitForEvent` calls:

| Step | Waits on event | Sent by |
|---|---|---|
| `wait-extract` | `migration/extract-done` | `extract-all.ts` |
| `wait-wave-{1,2,3,4,5,6}` | `migration/wave-done` (match `wave == N`) | `transform-wave.ts` |

Every one of these is one-shot. A single dropped event wedges the whole run for the full 60m / 120m / 180m / 6h `timeout`. That's what happened here: extract-all's final `sendEvent('migration/extract-done')` never reached run-full's waiter, the same way the 21× `extract-one-done` events used to drop under load.

**Fix:** same DB-polling pattern, extended to the run-full layer. Uses a single sentinel row per wave (not per sub_step — transform-wave has fn-based sub_steps like `seedPersonas`, `transformClaimedOrders` that don't write `migration_wave_status`, so we can't infer wave completion from per-sub_step rows).

**Sentinel convention:** `sub_step = '__wave__'`, one row per `(run_id, wave)` where `wave ∈ {0..6}` (0 = extract phase, 1–6 = transform waves). Double-underscore prefix distinguishes it from real sub_steps in progress endpoints.

**`transform-wave.ts`** writes the sentinel at start, flips to completed/failed at end:

```ts
await step.run(`mark-wave-${wave}-running`, () =>
  pgQuery(`INSERT INTO migration_wave_status (run_id, wave, sub_step, status, started_at)
           VALUES ($1,$2,'__wave__','running',now())
           ON CONFLICT (run_id, wave, sub_step) DO UPDATE SET
             status='running', started_at=now(), completed_at=NULL, error_detail=NULL`,
          [runId, wave]));

try {
  // ... run all sub-steps (parallelGroup-aware loop unchanged) ...
} catch (err) {
  await step.run(`mark-wave-${wave}-failed`, () => pgQuery(
    `UPDATE migration_wave_status SET status='failed', completed_at=now(), error_detail=$4
       WHERE run_id=$1 AND wave=$2 AND sub_step=$3`,
    [runId, wave, '__wave__', (err as Error).message.slice(0, 2000)]));
  throw err;
}

await step.run(`mark-wave-${wave}-complete`, () => pgQuery(
  `UPDATE migration_wave_status SET status='completed', completed_at=now()
     WHERE run_id=$1 AND wave=$2 AND sub_step='__wave__'`, [runId, wave]));
```

**`extract-all.ts`** does the same for `wave=0`, bracketing the existing per-collection fan-in. On timeout or `failed > 0` it writes the sentinel `'failed'` before throwing, so run-full's poll breaks fast instead of waiting out the 4h fan-in cap.

**`run-migration.ts`** replaces all 6 `waitForEvent` calls with a shared helper:

```ts
async function waitForWaveCompletion(step, { label, runId, wave, timeoutMinutes }) {
  const maxIterations = Math.ceil((timeoutMinutes * 60) / 15);
  for (let i = 0; i < maxIterations; i++) {
    const sentinel = await step.run(`${label}-check-${i}`, () => pgQuery(
      `SELECT status, error_detail FROM migration_wave_status
        WHERE run_id=$1 AND wave=$2 AND sub_step='__wave__'`, [runId, wave]));
    if (sentinel?.status === 'failed') throw new Error(`Wave ${wave} failed: ${sentinel.error_detail}`);
    if (sentinel?.status === 'completed') return;
    await step.sleep(`${label}-wait-${i}`, '15s');
  }
  throw new Error(`Wave ${wave} did not complete within ${timeoutMinutes}m`);
}
```

**Failure-path cleanup:** run-full now wraps its main body in try/catch and flips `migration_merchant_status.status='failed'` on any thrown error, so a crashed run is visible on `/progress/detailed` without digging through Inngest. Scoped to `current_run_id=$runId` so a concurrent re-trigger (new runId) isn't clobbered.

**Invariants preserved:**

- `step.sendEvent('extract-done')` and `step.sendEvent('wave-done')` still fire — kept for observability and any external listener. Run-full just doesn't depend on them.
- Per-sub_step rows for transforms (`1a-tiers`, `5b-orders-shopee`, etc.) keep their existing semantics from `runSql` / `runSqlPerMerchant`. Adding the `__wave__` sentinel adds exactly 1 row per wave, increasing `subStepsTotal` in `/progress` responses by a small constant (good — the sentinel reflects real aggregate progress).
- Extract phase retains its 21-row per-collection tracker. The `wave=0 __wave__` sentinel is layered on top; extract-all's internal fan-in still polls per-collection rows as the source of truth for "have all 21 finished", then updates the sentinel to `completed` for the parent.

**Cost:** 1 SELECT per poll × 7 polls (extract + 6 waves). Single-condition index scan on `(run_id, wave, sub_step)` — sub-millisecond. A full merchant run (typical ~90 min total across all phases) = ~90 × 60 / 15 = 360 polls = 720 steps; well inside Inngest's soft limit.

**Unblocks stuck runs going forward.** For the `66e2aa...4230b8` run that hung on the old hand-off: cancel in Inngest, reset `migration_merchant_status.status='pending'` + `current_run_id=null` (staging is already populated and idempotent — no need to re-extract), retrigger `POST /migration/start`. Post-deploy, run-full uses DB polling for all 7 phases.

---

### Decimal128 serialization (fix landed 2026-04-20)

**Problem:** marketplace money fields (`total_amount`, `shipping_fee`, `tax`, item-level `original_price`/`net_price`, etc.) are Mongo `Decimal128`. `JSON.stringify(doc)` invokes each type's `toJSON()` — for `Decimal128` that's the EJSON envelope:

```json
{ "total_amount": { "$numberDecimal": "630" } }
```

Downstream Wave 5 SQL (`wave-5{a,b,c}-orders-*.sql`, `wave-5d-order-items.sql`) does `(stg.raw->>'total_amount')::numeric`, which extracts the **string** `{"$numberDecimal":"630"}` and fails to cast.

**Fix:** `serializeDoc` now flattens `Decimal128` and `Long` to plain string scalars via `.toString()` before `JSON.stringify`:

```ts
function serializeDoc(doc: Record<string, any>): string {
  return JSON.stringify(doc, (_k, v) => {
    if (v instanceof ObjectId)   return v.toHexString();
    if (v instanceof Decimal128) return v.toString();
    if (v instanceof Long)       return v.toString();
    if (typeof v === 'bigint')   return v.toString();
    return v;
  });
}
```

`->>` returns text either way, so the existing `(stg.raw->>'…')::numeric` casts work unchanged. Emitting as a string (rather than a JSON number) preserves full Decimal128 precision — important for merchants with large totals where `Number` would round.

---

### Wave 6b-link target-table reference (fix landed 2026-04-20)

**Problem:** `wave-6b-link.sql` referenced the UPDATE target `pru` from inside a `JOIN … ON` clause:

```sql
UPDATE purchase_receipt_upload pru SET purchase_ledger_id = pl.id
FROM stg_mongo_receipts stg
JOIN purchase_ledger pl ON pl.transaction_number = (stg.raw->>'receiptId')
  AND pl.merchant_id = pru.merchant_id   -- ← pru not in FROM list
WHERE stg.mongo_id = pru.mongo_id AND …;
```

Postgres evaluates the FROM-list joins before the target is joined in, so target-table columns can only appear in the top-level `WHERE`, not in join `ON` conditions. Error: `invalid reference to FROM-clause entry for table "pru"`.

**Fix:** replaced the `JOIN` with an implicit cross-join and moved every predicate (including `pl.merchant_id = pru.merchant_id`) into the `WHERE` clause. Behaviour is identical, Postgres now plans it as a hash/merge join on the legal predicates.

---

### Per-merchant rollback hardening (fixes landed 2026-04-20)

Two orthogonal bugs blocked `POST /migration/rollback/:merchantMongoId` on HER HYNESS; both now fixed.

#### 1. `column "mongo_id" does not exist` (code bug in `rollbackMerchant`)

`rollback-merchant.ts` applied `mongo_id IS NOT NULL` as a delete predicate against every target table, but 9 of the 32 target tables don't carry a `mongo_id` column (they're normalised children scoped through a parent FK). The endpoint 500'd on dry-run at the first such table.

Tables without `mongo_id` (scoping is via parent subquery in `extra`, which itself filters parent's `mongo_id IS NOT NULL`):

```text
tier_progress          form_responses            form_submissions
user_address           reward_promo_code         reward_points_conditions
store_attribute_assignments   store_attributes   store_attribute_categories
```

**Fix:** added `noMongoId?: boolean` flag to `TARGET_TABLES` entries, marked those 9, and made the `mongo_id IS NOT NULL` predicate conditional:

```ts
const predicates: string[] = [];
if (!t.noMongoId) predicates.push('mongo_id IS NOT NULL');
if (t.extra) predicates.push(t.extra);
else predicates.push('merchant_id = $1::uuid');
if (t.requireSkipCdc) predicates.push('skip_cdc = true');
```

For the 8 child tables with `extra`, the parent subquery already filters to migrated rows, so dropping the child-side predicate is safe. `store_attribute_categories` is the one exception — no mongo_id *and* no `extra`, so its rollback scope is every row for the merchant. Acceptable because rollback is explicitly a clean-slate operation; documented in code.

When adding a new target table: run the `information_schema.columns` check in the code comment and set the flag accordingly.

#### 2. `Column used in the publication WHERE expression is not part of the replica identity` (schema bug)

The `crm_cdc_publication` has a row filter `(skip_cdc IS NOT TRUE)` on three tables:

| Table | Replica identity before | After |
|---|---|---|
| `wallet_ledger` | `full` | `full` (was already correct) |
| `purchase_ledger` | `default (pkey)` | **`full`** |
| `tier_change_ledger` | `default (pkey)` | **`full`** |

A DELETE against a CDC-filtered table fails if Postgres can't evaluate the publication's row filter on the tombstone, and it can't unless the filter-referenced columns are present in the replica identity. `default` replica identity only covers the primary key, so `skip_cdc` isn't publishable → DELETE blocked.

**Fix:** `ALTER TABLE purchase_ledger REPLICA IDENTITY FULL; ALTER TABLE tier_change_ledger REPLICA IDENTITY FULL;` — matches the existing pattern on `wallet_ledger`. Applied directly against Supabase (no migrations folder in this repo).

Trade-off: `REPLICA IDENTITY FULL` slightly increases WAL volume for UPDATE/DELETE (publishes all old-row columns instead of just PK). Negligible for these three low-QPS ledger tables and already accepted for `wallet_ledger`.

**Audit query** for adding future CDC-filtered tables:

```sql
SELECT pt.tablename, pt.rowfilter,
       CASE c.relreplident WHEN 'f' THEN 'full' ELSE 'default (pkey)' END AS replica_identity
  FROM pg_publication_tables pt
  JOIN pg_class c ON c.relname=pt.tablename
 WHERE pt.pubname='crm_cdc_publication' AND pt.rowfilter IS NOT NULL;
```

Any table with a non-null `rowfilter` must have `replica_identity = full` or the rollback path (and any other DELETE/UPDATE touching the filtered rows) will trip.
