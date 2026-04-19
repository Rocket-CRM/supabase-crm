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
