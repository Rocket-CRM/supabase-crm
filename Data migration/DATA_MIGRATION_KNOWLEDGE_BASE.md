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
- `nameForm` / `titleForm` / `detail` → denormalized, derive from `consent_versions`

#### 10. Storefront: Receipts, Products, Stores (sf cluster)

| MongoDB Source | Supabase Target | Notes |
|---|---|---|
| `storefrontdb.product_orders` | `purchase_ledger` + `purchase_items_ledger` | **DB is empty** — no data to migrate |
| `storefrontdb.products` | `product_master` + `product_sku_master` | **DB is empty** |
| `storefrontdb.stores` | `store_master` | **DB is empty** |

**Status:** storefrontdb exists but has 0 collections. These are likely set up fresh in Supabase.

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

`storefrontdb` exists but has **0 collections**. All sf-marked items (receipts, products, stores, missions, inventory) will be fresh in Supabase — no data migration needed, only schema setup.
