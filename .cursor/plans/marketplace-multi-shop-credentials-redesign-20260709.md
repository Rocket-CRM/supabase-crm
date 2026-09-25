# Multi-shop marketplace credentials — findings & redesign

**Status:** Implemented 2026-07-09 (awaiting FE admin follow-up for TikTok multi-shop UX if desired)  
**Date:** 2026-07-09  
**Project:** `wkevmsedchftztoolkmi`

### Shipped
- Migration: `merchant_credentials_marketplace_order_uniq` + `_cs_uniq` (env + scope partials); dropped old `merchant_credentials_marketplace_uniq`
- RPCs: `get_shop_credentials`, `get_merchant_marketplace_channels` filter `scope IS NULL`
- Edge: `marketplace-shopee-exchange-token` v113, `marketplace-lazada-exchange-token` v88, `marketplace-tiktok-exchange-token` v86 (post-exchange shop picker via `marketplace_oauth_pending`), `marketplace-token-refresh` v38 (TikTok sibling token propagate)
- Docs: `REGISTRY_RENDER.md`, `CS_Channels.md`, `CHANGELOG.md`

### TikTok picker contract (v86)
1. POST `{ code, merchant_code, use_test? }` → if 1 shop: connect immediately; if 2+: `{ needs_shop_selection: true, pending_id, shops_available_in_grant, pending_expires_at }` (15m TTL, tokens not returned to FE)
2. POST `{ pending_id, shop_ids: string[], merchant_code?, store_name?, claim_from_status? }` → upserts selected shops, consumes pending
3. Optional skip: pass `shop_id` / `shop_ids` with `code` on step 1 to connect without picker

---

## 1. Verdict

Root cause is confirmed in all three order OAuth exchange edge functions: they look up **one** `merchant_credentials` row by `(merchant_id, service_name, environment)` [Lazada also filters `scope`] and **UPDATE `external_id` + tokens** on that row. The DB unique index already allows multi-shop; admin list/delete RPCs already treat channels as per-row. Order sync / earn resolve by **shop id** and are multi-shop-safe. Fix is exchange upsert semantics (+ unique-index hardening for Lazada CS / env), not FE routing.

---

## 2. Current data model

### `merchant_credentials` (marketplace-relevant columns)

| Column | Role |
|---|---|
| `merchant_id` | Owner |
| `service_name` | `shopee` / `lazada` / `tiktok` |
| `external_id` | Platform shop / seller id (Shopee `shop_id`, TikTok `shop.id`, Lazada `account` / seller_id) |
| `environment` | `production` \| `test` |
| `scope` | `NULL` = order/loyalty; `{cs}` = Lazada CS IM |
| `credentials` | jsonb tokens + platform fields (`shop_id`, `shop_name`, `access_token`, …) |
| `is_active` | Soft-live flag; refresh deactivates on permanent platform rejection |
| `expires_at` | Access-token expiry |
| `credential_name`, `health_status`, `webhook_url`, `channel_config` | CS / Integration Hub |

### Unique index (already multi-shop shaped)

```sql
merchant_credentials_marketplace_uniq
  ON (merchant_id, service_name, external_id)
  WHERE service_name IN ('lazada','shopee','tiktok')
```

**Gaps in the index (must fix in redesign):**
- Does **not** include `environment` → test + prod same shop id collide.
- Does **not** discriminate `scope` → Lazada **order** (`scope NULL`) and **CS** (`scope {cs}`) with the same seller `external_id` would collide. No live CS Lazada rows today, but the exchange fn already writes both shapes.

There is **no** unique on `(merchant_id, service_name, environment)` anymore (dropped for Integration Hub multi-row). Exchange still *behaves* as if that constraint existed.

### Claim status (merchant + platform, not per shop)

`merchant_master.marketplace_claim_from_status` jsonb, keys `shopee` / `lazada` / `tiktok` / `shopify`.  
`claim_marketplace_order` reads `marketplace_claim_from_status->>p_platform` with platform defaults. Live values are almost all platform defaults; one merchant (`biowoman`) has Shopee `COMPLETED`.

---

## 3. Root cause — exchange upsert

| Function | Lookup | On hit | On miss |
|---|---|---|---|
| `marketplace-shopee-exchange-token` | `merchant_id + service_name='shopee' + environment` (`.single()`) | UPDATE `external_id`, tokens, `is_active=true` | INSERT |
| `marketplace-tiktok-exchange-token` | same for `tiktok` | same | INSERT |
| `marketplace-lazada-exchange-token` (`app:'order'`) | same + `scope IS NULL` | same | INSERT |
| `marketplace-lazada-exchange-token` (`app:'cs'`) | same + `scope contains {cs}` | same | INSERT with `scope={cs}` |

Shopee already receives `shop_id` in the body. TikTok ignores multi-shop grants and always takes `shops[0]`. Lazada derives `external_id` from token `account` / `country_user_info[0].seller_id`.

**Effect of connecting shop B while shop A exists:** shop A’s row is rewritten to B’s `external_id` + tokens. Shop A disappears from DB (not deactivated). UI then shows one “Active” channel for B; A looks logged out.

### Token refresh (already per-row — OK)

`marketplace-token-refresh` selects **all** `is_active` rows for `shopee|lazada|tiktok`, refreshes by `record.id`, deactivates only that id on permanent failure. **Does not** overwrite sibling shops. Lazada secret resolved via `credentials.app_key` → env map (order / cs / test). No change required for multi-shop isolation beyond ensuring exchange stops sharing one row.

---

## 4. Call graph & one-credential assumptions

```
Admin FE /marketplace-settings
  → get_merchant_marketplace_channels()     [ALL rows for merchant+platform; multi-OK]
  → OAuth → *-exchange-token                [ONE-ROW OVERWRITE — BUG]
  → admin_delete_marketplace_channel(id)    [per-row; multi-OK]

Webhook → Inngest marketplace/order-received
  → inngest-marketplace-serve
      → get_shop_credentials(shop_id, platform)   [by external_id; multi-OK]
      → platform API → upsert_marketplace_order

Legacy Redis path
  → marketplace-batch-checker → marketplace-process-orders
      → merchant_credentials by external_id       [by shop; multi-OK]

marketplace-tiktok-backfill-orders
  → get_shop_credentials                      [by shop; multi-OK]

Earn / claim
  → claim_marketplace_order
      → marketplace_claim_from_status->>platform  [merchant+platform; OK if policy stays]

CS Lazada
  → exchange app:'cs' + scope {cs}
  → cs_bff_get_channels (scope && {cs})
  → webhook-lazada-cs / messaging-service     [scope-aware; must stay isolated]

One-credential helpers (NOT used by order sync; risk if reused for marketplace)
  → get_merchant_credentials(code, service)           LIMIT 1 active prod
  → fn_get_merchant_credentials_cached(mid, service)  LIMIT 1 active
  → superadmin_create_merchant_credentials            rejects if any row for (mid, service, env)
```

| Reader | Key | Multi-shop safe? |
|---|---|---|
| `get_shop_credentials` | `external_id + service_name + is_active` | Yes (order path). Should also prefer `scope IS NULL` once CS Lazada exists. |
| `get_merchant_marketplace_channels` | all marketplace service rows | Yes. Should **exclude** `scope && {cs}` so CS doesn’t appear on Marketplace Connections. |
| `admin_delete_marketplace_channel` | row id + merchant | Yes |
| `bff_get_merchant_credentials` | all credentials | Yes (lists all) |
| `marketplace-token-refresh` | each active row by id | Yes |
| `inngest-marketplace-serve` / process-orders / backfill | shop id | Yes |
| `get_merchant_credentials` / `fn_get_merchant_credentials_cached` | merchant + service LIMIT 1 | **No** — AMP / generic; do not use for marketplace order |
| `superadmin_create_merchant_credentials` | blocks 2nd row same env | **No** for marketplace multi-shop ops inserts |
| Claim threshold | merchant + platform | Intentional; see policy below |

---

## 5. How existing multi-shop rows were created

Live snapshot (2026-07-09):

- **0 merchants** with 2+ **active** shops on the same platform (consistent with overwrite).
- Active: 4 Shopee, 4 Lazada, 6 TikTok merchants — one shop each.
- Inactive multi-row clusters: `drpongskinclub` (19 Shopee, 3 Lazada), `kaosmileclub` (4 Shopee, 3 TikTok), `yuedpao` (2 Shopee). All inactive; `credential_name` like `shopee:<id>`; `updated_at` clustered ~2026-07-08 21:59 (mass deactivate, likely refresh permanent failures).

**Interpretation:** those inactive rows were **inserted per shop** (legacy WeWeb / migration / ops), not produced by the current exchange overwrite. Overwrite **destroys** shop A’s identity on the single row — it does **not** leave an inactive sibling. Therefore “restore shop #1 from inactive orphan” only works when a historical per-shop insert still exists; pure overwrite victims need **re-OAuth**.

No live Lazada CS (`scope={cs}`) rows today.

---

## 6. Target design

### 6.1 Upsert key (preferred)

For order credentials (`scope IS NULL`):

**Match / upsert on:** `(merchant_id, service_name, external_id, environment)` with `scope IS NULL`.

Rules:
1. **Re-auth same shop** → UPDATE that row’s tokens / expiry / `is_active=true` / shop_name. Never change `external_id` to a different shop.
2. **Connect second shop** → INSERT new row (different `external_id`).
3. **Reconnect after delete** → INSERT (or UPDATE inactive row with same key if we soft-delete instead of hard-delete — today delete is hard DELETE; INSERT is fine; unique index allows reuse of same external_id after delete).
4. **Never** `UPDATE … SET external_id = <new shop>` on a row that already has a different `external_id`.

Lookup algorithm (all three exchange fns):

```
1. Require resolved shop/seller id before DB write (Shopee: body shop_id; TikTok: selected shop id; Lazada: account/seller_id from token).
2. SELECT id WHERE merchant_id + service_name + external_id + environment
     [+ scope IS NULL for Lazada order / contains {cs} for Lazada CS]
3. If found → UPDATE tokens only (and optional store_name, is_active, expires_at).
4. If not found → INSERT.
5. Do not fall back to “any row for merchant+service+env”.
```

### 6.2 Unique index hardening

Replace / extend `merchant_credentials_marketplace_uniq` with **two** partial uniques (or one expression index):

```sql
-- Order / loyalty rows (scope null)
UNIQUE (merchant_id, service_name, external_id, environment)
  WHERE service_name IN ('lazada','shopee','tiktok') AND scope IS NULL;

-- CS rows (Lazada IM today)
UNIQUE (merchant_id, service_name, external_id, environment)
  WHERE service_name IN ('lazada','shopee','tiktok') AND scope @> ARRAY['cs']::text[];
```

This allows same Lazada seller id for order + CS, and test vs production.

### 6.3 Lazada order vs CS

- Keep `app: 'order' | 'cs'` on exchange.
- Order: `scope NULL`; CS: `scope = '{cs}'`.
- Upsert filters must remain scope-aware (already true for lookup; must also be true for the new external_id key).
- `get_shop_credentials` (order): add `AND (scope IS NULL)` so CS tokens never feed order API.
- `get_merchant_marketplace_channels`: exclude `scope && ARRAY['cs']`.
- Token refresh: already per-row + app_key map — OK.

### 6.4 TikTok multi-shop policy (recommendation)

**Phase 1 (ship with upsert fix):** Prefer explicit `shop_id` in exchange body (parity with Shopee). If omitted, keep `shops[0]` for backward compatibility but log a warning when `shops.length > 1`.

**Phase 2 (optional FE):** If OAuth grant returns multiple shops, either:
- **A (recommended):** Create **one credential row per shop** in the grant (same tokens / open_id / refresh_token copied onto each row; refresh updates all rows sharing `open_id` or refresh_token), **or**
- **B:** Require separate OAuth per shop (simpler token lifecycle; worse UX).

Recommend **A** only after FE can show a shop picker or “connect all”; until then, require `shop_id` from FE after picker, or document that connecting again with a different seller account is how you add shop 2.

**Important:** TikTok refresh tokens are often grant-scoped. If multiple rows share one refresh_token, refreshing row A may rotate the token and invalidate row B unless refresh updates **all sibling rows** with the same `open_id` / refresh_token. Design refresh accordingly if choosing A.

### 6.5 `marketplace_claim_from_status`

**Keep merchant + platform** for v1.

Rationale: claim eligibility is a merchant policy (“from READY_TO_SHIP onward”), not shop-specific in current product; claim RPC and catalog docs are platform-keyed; no FE per-shop claim UI. Connecting shop B overwriting the platform key is acceptable (same as today). Per-shop claim can be a later additive shape (`channel_config.claim_from_status` or jsonb keyed by `external_id`) without blocking multi-shop connect.

### 6.6 Row lifecycle

| Event | Behavior |
|---|---|
| Connect new shop | INSERT active |
| Re-auth same shop | UPDATE tokens in place |
| Delete channel | Hard DELETE by id (existing) |
| Refresh success | UPDATE tokens on that id only |
| Refresh permanent fail | `is_active=false` on that id only |
| Connect shop that exists inactive | UPDATE that row → active + new tokens (prefer over second insert; unique on external_id forces this) |

---

## 7. API / edge change list

| Change | Compat for loyalty-admin FE |
|---|---|
| **Deploy** `marketplace-shopee-exchange-token` — upsert by `external_id` | Request body unchanged (`shop_id` already required). Response unchanged. |
| **Deploy** `marketplace-tiktok-exchange-token` — upsert by shop id; accept optional `shop_id`; if provided, select that shop from `shops[]` | Additive field. Without it, still `shops[0]`. |
| **Deploy** `marketplace-lazada-exchange-token` — order/cs upsert by `external_id` + scope | Body unchanged. |
| **Migration** unique indexes (env + scope partials) | No FE impact. |
| **Optional RPC** `get_shop_credentials` add `scope IS NULL` | Safer; no FE contract. |
| **Optional RPC** `get_merchant_marketplace_channels` exclude CS scope | Hides CS from Marketplace Connections if CS Lazada appears. |
| `marketplace-token-refresh` | No change for Shopee/Lazada one-row-per-shop. TikTok shared-grant sibling refresh only if policy A ships. |
| `superadmin_create_merchant_credentials` | Optional later: allow marketplace multi-shop by checking external_id; not required for OAuth path. |
| FE | No route change. “Create channel” already lists multiple rows via `get_merchant_marketplace_channels`. Optional: TikTok shop picker + pass `shop_id`. |

**Backward compatibility:** Existing single-shop merchants: re-auth still updates the same row (external_id match). Connecting a second shop starts inserting instead of overwriting.

---

## 8. Migration for merchants who lost shop #1

1. **Detect overwrite victims (heuristic):** merchants with exactly one active row per platform who report a missing shop, **or** ops list of known dual-shop merchants. Inactive siblings with distinct `external_id` are **candidates to reactivate via re-OAuth**, not silent token revive (tokens are dead).
2. **Do not auto-reactivate** inactive rows — refresh already marked them permanently failed; tokens are invalid.
3. **Playbook:** after exchange fix ships, merchant re-connects each shop via Marketplace Connections → each OAuth creates/updates its own row.
4. **Optional ops SQL:** list inactive marketplace rows per merchant for CS to send “please reconnect” with shop ids:

```sql
SELECT mm.merchant_code, mc.service_name, mc.external_id, mc.is_active, mc.updated_at
FROM merchant_credentials mc
JOIN merchant_master mm ON mm.id = mc.merchant_id
WHERE mc.service_name IN ('shopee','lazada','tiktok')
ORDER BY mm.merchant_code, mc.service_name, mc.is_active DESC;
```

No automated backfill of tokens is possible without re-OAuth.

---

## 9. Test plan

1. Merchant with **no** Shopee → connect shop A → one active row, `external_id=A`.
2. Connect shop B (same platform) → **two** active rows, distinct `external_id`; A’s tokens/`external_id` unchanged.
3. `get_merchant_marketplace_channels` returns both Active.
4. Re-auth A → only A’s tokens/`expires_at` change; B untouched.
5. Delete B → B gone; A still active.
6. Trigger token refresh → A refreshed; no B row; A not deactivated by B’s absence.
7. Webhook/Inngest for shop A order → `get_shop_credentials(A)` succeeds; B’s credentials unused.
8. Lazada: connect order seller S1; connect CS for same seller → two rows (NULL vs `{cs}`); order exchange does not touch CS row.
9. TikTok: with `shop_id` in body selecting shops[1] → row for that id, not shops[0].
10. Test env (`use_test`) vs production → separate rows; unique index allows both.

---

## 10. Rollout plan

1. **Ship unique-index migration** (partial uniques with environment + scope) — verify no duplicate `(merchant, service, external_id, env)` among active order rows (today: none).
2. **Deploy three exchange functions** (order of deploy: any; no FE gate required for Shopee/Lazada; TikTok optional `shop_id` additive).
3. **Optional:** patch `get_shop_credentials` + `get_merchant_marketplace_channels` scope filters.
4. **Monitor** (hourly / dashboard):

```sql
SELECT merchant_id, service_name, environment,
       COUNT(*) FILTER (WHERE is_active) AS active_shops
FROM merchant_credentials
WHERE service_name IN ('shopee','lazada','tiktok')
  AND (scope IS NULL)
GROUP BY 1,2,3
HAVING COUNT(*) FILTER (WHERE is_active) > 1;
```

5. CS notifies multi-shop merchants to reconnect lost shops.
6. Docs: `REGISTRY_RENDER.md` exchange notes; `CS_Channels.md` Lazada scope note if index changes.

---

## 11. Success criteria (acceptance)

- Merchant can have N active Shopee / TikTok / Lazada **order** credentials with different `external_id`s.
- Connecting shop B does not change shop A’s tokens or `external_id`.
- `get_merchant_marketplace_channels` shows all active order shops.
- Order sync / earn resolve credentials by shop id (`get_shop_credentials`).
- Lazada CS credentials remain separate (`scope {cs}`) and unaffected by order upsert.

---

## 12. Out of scope (confirmed)

- Changing `/marketplace-settings` route or moving connect UX to Integrations/Stores.
- CS chat multi-shop product redesign (only collision isolation).
- Per-shop claim status (deferred; keep platform-level).
- Auto-restore of overwritten shop tokens without re-OAuth (impossible).

---

## 13. Approval asks

Please confirm before implementation:

1. **Upsert by `(merchant_id, service_name, external_id, environment)` + scope filter** — yes/no?
2. **Unique index split** (order vs CS partials, include `environment`) — yes/no?
3. **Claim status** stays merchant+platform for v1 — yes/no?
4. **TikTok:** Phase 1 optional `shop_id` only, vs also multi-row-per-grant now?
5. **RPC filters** (`get_shop_credentials` / channels list exclude CS) in same change set — yes/no?
