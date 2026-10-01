# BigCommerce Storefront API

> Per-domain reference. Read ONLY when working on this domain. For the keyword → file map, see `_index.md`.

**Keywords:** bigcommerce, storefront, api_bigcommerce_*, mongoId, mongo_id, migrated user, member profile (storefront), member tier (storefront), storefront rewards, merchant config (storefront)

**Source:** none (function-defined surface; this doc is the source of truth)

## Purpose

Public-facing RPC surface consumed directly by BigCommerce storefront themes/widgets. Each function returns a single `jsonb` payload shaped to match the storefront's expected contract (camelCase keys, `_id` aliases for legacy Mongo compatibility). All three live under `public.api_bigcommerce_*` and are called via PostgREST RPC.

## Function Inventory

| Function | Args | Auth | Returns |
|---|---|---|---|
| `api_bigcommerce_get_merchant_config(p_merchant_code text)` | merchant code | none (public) | merchant + tier + theme config keyed for storefront |
| `api_bigcommerce_get_user_profile()` | — | `auth.uid()` + `get_current_merchant_id()` | profile + tier + wallet + `mongoId` |
| `api_bigcommerce_get_user_rewards(p_limit int=100, p_page int=1)` | pagination | `auth.uid()` + `get_current_merchant_id()` | redeemed rewards filtered for the BigCommerce store channel |

All three are `SECURITY DEFINER`. The two authenticated functions resolve merchant via `get_current_merchant_id()` (see `11-auth-conventions.mdc`).

## Response Contract — `api_bigcommerce_get_user_profile`

Top-level keys (camelCase):

| Key | Source | Notes |
|---|---|---|
| `_id` | `user_accounts.id` | UUID |
| `mongoId` | `user_accounts.mongo_id` | Legacy Mongo ObjectId (text) **or `null`**. `null` = user signed up after migration. Use `mongoId != null` to detect a migrated user. |
| `merchantId` | `user_accounts.merchant_id` | UUID |
| `phoneNumber`, `email`, `fullName`, `lineUserId`, `avatar` | `user_accounts.tel/email/fullname/line_id/image` | empty string when null |
| `memberCode` | derived: `to_char(created_at,'YYMMDDHH24MI') || last 3 hex of id` | display code |
| `userType` | hardcoded | always `'CLIENT'` |
| `signupMethod` | derived | `'LINE'` if `line_id` set, else `'TEL'` |
| `status` | hardcoded | always `'ACTIVE'` |
| `memberTier` | `tier_master` + `tier_conditions` + `earn_factor` | nested object: `tierName, pointThreshold, color, icon, benefits, card_design, bahtSpent, points, discountInBaht, discountUsePoints, burnRate, burnRateEnabled, maxDiscountInBaht, status, isDefault, _id` |
| `contact` | `user_accounts` + `user_wallet` | flat user record incl. `pointBalance`, `memberTierId/Name` |
| `totalPoints` | `user_wallet.points_balance` | |
| `totalCoupons` | hardcoded `0` | not yet wired |
| `merchant` | `merchant_master` + all tiers | `_id, name, membershipTiers[], themeMode='light'` |
| `typeTier` | hardcoded | `'sale_earn'` |
| `registerAt` | `user_accounts.created_at` | timestamptz |

**Error shapes:** `{ "error": "Authentication required" }` if `auth.uid()` is null, `{ "error": "Merchant context not found" }` if merchant resolution fails.

## Underlying Tables (already documented elsewhere)

- `user_accounts`, `user_wallet` → see `currency.md`, `signup-login.md`
- `tier_master`, `tier_conditions`, `earn_factor` → see `tier.md`, `currency.md`
- `merchant_master` → core
- Reward tables for `get_user_rewards` → see `reward.md`

This doc only covers the storefront-facing wrapper layer; business logic lives in the source domains.

## Migration Detection

Storefront pattern for "is this a migrated user from the old Mongo CRM?":

```js
const profile = await supabase.rpc('api_bigcommerce_get_user_profile').then(r => r.data)
const isMigratedUser = profile?.mongoId != null
```

`mongo_id` is populated for ~96% of current `user_accounts` rows (those imported from the legacy Mongo CRM). New signups created after migration have `mongo_id = NULL`.

---
