# Multi-Channel Product Reference (Shopify + future marketplaces)

**Status:** Implemented (DB layer live on project `wkevmsedchftztoolkmi`). One edge-function cleanup deferred to CLI deploy — see [Deferred](#deferred-cli-deploy).

**Problem solved:** Shopify (and later Shopee/Lazada/TikTok) order lines often have **no merchant SKU**, and previously the marketplace claim path jammed the Shopify **line-item id** (a throwaway value, different on every order) into `sku_code`. It never matched the CRM catalog, so the line was dropped and **no loyalty points were earned**. We now translate the stable Shopify **`variant_id`** into a CRM SKU via a small bridge table, without syncing the whole catalog and while sharing one Product/SKU master with POS.

---

## Mental model

Think of one **translation dictionary** that maps a marketplace **variant id** → a CRM **SKU**. Every entry is variant-grain; there is no product-grain entry because **a product is just the parent of its variants** — the link already lives on the SKU (`product_sku_master.product_id`).

- A **variant-level** earn rule matches because we resolve the order line straight to that SKU.
- A **product-level** earn rule matches because the resolved SKU carries its parent `product_id`, which the earn engine compares against.

A Shopify product with **no variants** still has one auto-created "Default Title" variant with a stable `variant_id`, so it collapses to "one SKU" and needs no special handling. The only unresolvable lines are **custom/manual line items** and **deleted variants** (no `variant_id`); those fall back to `sku_code`, else are kept with `sku_id = NULL` and earn nothing (nothing in the catalog to match).

---

## Implemented structure

### Table — `product_sku_external_ref` (the bridge / dictionary)

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `merchant_id` | uuid NOT NULL → `merchant_master(id)` | |
| `platform` | text NOT NULL | CHECK in (`shopify`,`shopee`,`lazada`,`tiktok`,`bigcommerce`) |
| `external_id` | text NOT NULL | the platform variant id (e.g. Shopify `variant_id`) |
| `product_sku_id` | uuid NOT NULL → `product_sku_master(id)` ON DELETE CASCADE | |
| `created_at` / `updated_at` | timestamptz | `updated_at` maintained by trigger |

- **Unique:** `(merchant_id, platform, external_id)` — one platform variant maps to exactly one CRM SKU; gives free idempotency + re-link via `ON CONFLICT`.
- **Index:** `idx_product_sku_ext_ref_sku (product_sku_id)`.
- **RLS:** enabled; read policy `(merchant_id = get_current_merchant_id())`, mirroring `product_sku_master`. Writes go through SECURITY DEFINER functions.
- **SKU grain only** — no product-grain table; product linkage is derived from `product_sku_master.product_id`.

### Function — `fn_resolve_product_sku_id(p_merchant_id, p_platform, p_external_id, p_sku_code) → uuid`

Shared resolver. Order:
1. If `p_platform` + `p_external_id` present → look up the bridge.
2. Else if `p_sku_code` present → merchant-scoped `product_sku_master.sku_code` lookup (backed by the unique `(sku_code, merchant_id)` index — reproduces the legacy match exactly).
3. Else → `NULL`.

`STABLE`, `SECURITY DEFINER`. Returns the CRM SKU id or `NULL`. Backward-compatible: POS/receipt callers (no platform) always take step 2.

### Function — `fn_marketplace_order_items_payload(p_order_id, p_merchant_id) → jsonb`

Builds the `api_create_purchase` `items[]` from `order_items_ledger_mkp`. Now carries `platform` + `external_variant_id` (= `oi.variant_id`) for bridge resolution. `sku_code` still `COALESCE(platform_sku, variant_sku, platform_item_id)` for backward-compatible fallback. Shared by both claim functions (removes prior duplication / drift risk).

### Function — `bff_link_product_external_ref(p_platform, p_selections, p_mode, p_product_sku_id, p_grain) → jsonb`

Admin BFF (JWT → `get_current_merchant_id()`). For each selection (carries `shopify_product_id`, `shopify_variant_id`, `product_title`, `variant_title`, `image_url`, optional `price`):

- **`create_stub`** (default): find-or-create `product_master` (by `product_code = UPPER(platform)-<product_id>`) + `product_sku_master` (by `sku_code = UPPER(platform)-<variant_id>`) + upsert the bridge row. Idempotent (all keys deterministic).
- **`link_existing`**: validate `p_product_sku_id` belongs to merchant, then point every selected variant's bridge row at that existing CRM SKU (multi-channel link to a POS SKU).

Returns `{ links_created, product_ids[], sku_ids[] }`. The returned ids are what the earn rule saves in `entity_ids`.

> **Synthetic codes:** `product_code`/`sku_code` are `NOT NULL` in the master tables, so Shopify-only stubs get a synthetic code (`SHOPIFY-<id>`). This is safe — the resolver only matches an incoming order's `sku_code`, which is never of that synthetic form (Shopify orders resolve via the bridge on `variant_id`).

### Changed — `api_create_purchase`

Only the **item-resolution block** changed: the old `sku_code`-only join was replaced by a `JOIN LATERAL` on `fn_resolve_product_sku_id(merchant, item.platform, item.external_variant_id, item.sku_code)`, taking the matched master's `id` + `sku_code`. Unresolved items are dropped (unchanged behavior). The duplicate-check, user/store resolution, `unknown_skus` reporting, row payload, and the `chokepoint_post_purchase_event` call are all unchanged.

### Unchanged (by design)

`chokepoint_post_purchase_event` and the other chokepoints, `evaluate_earn_conditions(_core)`, mission evaluation, and all earn/mission/multiplier rule BFFs — once a line carries a CRM `sku_id`, a Shopify order is identical to a POS order, so nothing downstream changes.

---

## Order flow (live wiring)

```text
shopify-webhooks (edge)
  → upsert_marketplace_order            store raw order + line items (order_ledger_mkp / order_items_ledger_mkp)
  → fn_match_marketplace_user           match buyer → loyalty member
  → fn_claim_marketplace_order_service  (only if matched; threshold = paid; once)
        → fn_marketplace_order_items_payload   build items[] with platform + external_variant_id
        → api_create_purchase                  resolve each item via fn_resolve_product_sku_id → sku_id
              → chokepoint_post_purchase_event  insert purchase + purchase_items_ledger, run side effects
                    → evaluate_earn_conditions(_core)   points
              (purchase CDC) → fn_evaluate_mission_conditions   missions
```

`claim_marketplace_order` (the older user/admin-facing RPC) shares the same item helper.

---

## User journey

### A. Admin binds an earn rule to a Shopify product (setup)

1. Admin browses the **live Shopify catalog** in the rule builder (fetched on demand; no catalog sync).
2. Picks a product (or specific variant) and chooses the reward (e.g. 2× points).
3. FE calls `bff_link_product_external_ref` (`create_stub`) with the product + its variants.
4. Backend creates one `product_master` stub + a `product_sku_master` stub per variant + a bridge row per variant; returns CRM ids.
5. FE saves the earn rule pointing at the returned CRM id(s) — `entity = product_product` (use `product_id`) or `product_sku` (use `sku_id`). **The rule stores only CRM UUIDs; it never references Shopify.**

### B. Multi-channel: link Shopify to an existing POS SKU

1. Admin finds the existing CRM SKU.
2. Picks the Shopify variant(s); FE calls `bff_link_product_external_ref` (`link_existing`, `p_product_sku_id`).
3. POS purchases (via `sku_code`) and Shopify purchases (via `variant_id`) now resolve to the **same** SKU → same earn rules.

### C. Customer places a Shopify order (runtime)

1. Shopify fires the order webhook; the order is stored raw.
2. Buyer is matched to a member (else the order waits, unclaimed, no points).
3. Once **paid**, the claim step builds items carrying `platform='shopify'` + `external_variant_id`, and calls `api_create_purchase`.
4. The resolver translates the variant → CRM SKU; a normal purchase line is written with that `sku_id`.
5. From there it is an ordinary CRM purchase: the earn engine matches the SKU (and, for product rules, its parent product) and awards points; missions react via the purchase CDC event.

**Points land only when:** buyer matched **and** order paid **and** not already claimed (`synced_to_transaction`). These are pre-existing marketplace-claim conditions, unrelated to the bridge.

---

## Backward-compatibility & blast radius

`api_create_purchase` callers: `bff_approve_receipt_upload`, `claim_marketplace_order`, `fn_claim_marketplace_order_service`. The change is additive — any caller not passing `platform`/`external_variant_id` resolves through the `sku_code` branch, which reproduces the legacy join exactly. Verified live: resolving an existing SKU by `sku_code` returns the same id; a non-existent bridge lookup returns `NULL`.

The claim helper keeps `platform_item_id` as the final `sku_code` fallback, so Shopee/Lazada/TikTok claims are unchanged (they gain bridge resolution only once bridge rows exist for them).

---

## Deferred (CLI deploy)

`shopify-webhooks` normalizer currently sets `platform_item_id: String(li.id ?? li.product_id ?? "")` (line-item id first). Change to product-id-first:

```ts
platform_item_id: String(li.product_id ?? li.id ?? ""),
```

This is a **cleanup only** — resolution runs off `variant_id` (already normalized correctly), so the feature works without it. Deploy from the edge-source repo via CLI, preserving `--no-verify-jwt` semantics (the function is HMAC-verified and must keep `verify_jwt=false`).

---

## Out of scope (v1)

Catalog sync; brand/category from Shopify collections; storing platform ids in rule tables; auto-stub on first order without admin action; matching `evaluate_earn_conditions_core` directly on `sku_id`; re-syncing variants added on Shopify after a product was linked (those orders won't resolve until re-linked).

## Test checklist

1. Shopify variant bridged to stub SKU, paid order, matched buyer → resolves, earn matches.
2. POS order with real `sku_code` → same CRM SKU, earn matches (regression).
3. `link_existing` POS+Shopify → either channel hits the same rules.
4. Product-level rule + all variants bridged → buying any variant matches via parent product.
5. No bridge → line kept with `sku_id NULL`, earn skips.
6. Re-link a variant to a different SKU → bridge re-points (`ON CONFLICT DO UPDATE`), idempotent.
7. Buyer not matched / not yet paid → stored, no purchase, no points until satisfied.
