# Multi-Channel Product Reference — Implementation Plan (FINAL)

**Task:** Shopify (and future channels) can reference loyalty product rules **without full catalog sync**, while **sharing one Product/SKU master** with POS and other channels.

**Approach:** One **platform bridge table** at SKU grain (`product_sku_external_ref`) — not Shopify IDs in `sku_code`, and **not** a second product-grain table.

**Status:** Plan for review — implement in a fresh thread.

---

## Confirmed live flow (verified against deployed source)

Shopify order webhook ingest is **not** a dedicated path — it shares the marketplace claim service with Shopee/Lazada/TikTok:

```text
shopify-webhooks (edge fn, verify_jwt=false, v24)
  → upsert_marketplace_order        # stores order + line items in marketplace ledger
  → fn_match_marketplace_user        # match buyer → loyalty member (id / email / phone)
  → fn_claim_marketplace_order_service(p_platform='shopify', p_earn_currency=true)
        → api_create_purchase        # WRAPPER: resolves user/store/items, builds row payload
              → chokepoint_post_purchase_event   # THE chokepoint: inserts purchase + purchase_items_ledger, runs side effects
                    → evaluate_earn_conditions → evaluate_earn_conditions_core   # points
              (purchase CDC) → fn_evaluate_mission_conditions                    # missions
```

**`api_create_purchase` is NOT the chokepoint** — it's a thin wrapper that calls `chokepoint_post_purchase_event('created', ...)`. The five chokepoints (`post_purchase_event`, `post_tier_change`, `post_user_event`, `post_wallet_transaction`, `fn_chokepoint_emit_event`) are **not modified** by this plan.

**How `api_create_purchase` resolves items today (verified, body lines 69–103):** it joins each item to `product_sku_master` **solely on `sku_code` + `merchant_id`**, emits the matched `sku_id`, and **drops any item with no/unmatched `sku_code`**. It ignores any incoming `sku_id`. → The resolver must be added *inside this block*; resolving upstream and passing `sku_id` down would be discarded.

**Points are awarded only if:** buyer matched to a member **and** order status ≥ claimable threshold (Shopify default = `paid`) **and** not already claimed (`synced_to_transaction` guard). The "loyalty consume" metafield path in the same webhook is **spending**, not earning — out of scope here.

**Implication:** the resolver runs inside `api_create_purchase` (where line items become ledger rows); the item-payload shape change runs inside `fn_claim_marketplace_order_service` (and benefits all four marketplaces at once).

---

## Glossary

| Term | Meaning |
|---|---|
| **Product master** | CRM row for a product (`product_master`) — one logical product |
| **SKU master** | CRM row for a sellable variant (`product_sku_master`) — size/color/etc. |
| **Stub** | Minimal master row created only because admin picked it for a rule — not a full catalog import |
| **Merchant SKU** | Optional code the shop owner typed into Shopify (or POS). Often blank on Shopify. **Not used as primary match key.** |
| **Bridge / external ref** | Row linking a platform ID (Shopify `variant_id`) → CRM `product_sku_master.id` |
| **Platform ID** | Stable ID from Shopify/Shopee/etc. (`variant_id`, `product_id`) |

---

## Goal

1. Admin browses **Shopify live catalog** in the UI (no catalog sync).
2. On save, backend creates **stub SKU master row(s)** and/or **links** to existing CRM rows via the bridge table.
3. Earn / multiplier / mission rules still store **CRM UUIDs only** (no rule-schema change).
4. Shopify webhook orders **resolve to the same SKU master** as POS when linked.
5. Earn engine (`evaluate_earn_conditions_core`) **unchanged** — it already walks `sku → product_sku_master → product_master`.

---

## Why ONE bridge table (and why not columns)

A platform reference is **one CRM SKU → many platform IDs** (Shopify *and* Shopee *and* … for the same shared SKU). That's a one-to-many relation, so it belongs in a child table, not columns:

- Columns-per-platform (`shopify_variant_id`, `shopee_item_id`, …) = a schema migration per new marketplace, mostly-NULL columns, resolver hard-codes every column name.
- A single generic `(platform, external_id)` column pair can't hold two platforms for one shared SKU — breaks the multi-channel case that motivates this.
- (If it were ever truly Shopify-only-forever, a single nullable `shopify_variant_id` column would be fine — like the existing `product_sku_master.mongo_id`. It isn't, so the bridge wins.)

**Only SKU grain is needed.** Every Shopify order line carries `variant_id`, so ingest always resolves at SKU grain; `product_sku_master.product_id` then gives the parent product for free. A **product-level earn rule still matches** because the resolved SKU's parent `product_id` is what the engine compares against. So a separate `product_external_ref` table is redundant for v1 — **dropped.**

**Why not one polymorphic table with a `ref_type` (product/sku) discriminator?** Two reasons: (1) a polymorphic `target_id` pointing at either `product_master` or `product_sku_master` can't carry a foreign key (FK targets one table), so you lose `ON DELETE CASCADE` + integrity — the "fix" (two nullable FKs + CHECK) is just two tables in disguise; (2) we don't need product-grain rows at all (see above). So the type column would always be `'sku'` — dead weight. **Single SKU-grain table, no discriminator.**

**Products without variants/SKUs:** on Shopify this case doesn't exist at the order layer — a product with no defined variants still has one auto-created "Default Title" variant with a stable `variant_id`, and order lines always reference it. So we stub one `product_sku_master` (sku_code NULL) for that default variant and bridge it; product-level rules match via its parent `product_id`. The only truly variant-less lines are **custom/manual line items** and **deleted variants** (`variant_id` null in the normalizer) — those fall back to `sku_code`, else resolve to `sku_id NULL` (line kept, earn skips). No table-shape change helps those; there's nothing in the catalog to match.

**Product-rule journey (single table):** Admin picks Shopify product → picker loads its variants → `bff_link_product_external_ref` creates one `product_master` stub + N `product_sku_master` stubs (same parent) + N variant bridge rows → rule saves `entity_ids=[product_id]`. Order for any variant → resolver hits bridge → `sku_id` → earn core walks `sku_id → product_sku_master.product_id` → matches the rule's `product_id`. The parent product comes from the SKU's FK; no product bridge row needed.

```text
One CRM SKU row (S-uuid, parent P-uuid)
    ├── bridge: shopify → variant 456789
    ├── bridge: shopee  → item 999
    └── sku_code: TEE-BLK-M   ← POS / API still works (or NULL for Shopify-only)
```

---

## Schema (new) — single table

```sql
CREATE TABLE product_sku_external_ref (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id     uuid NOT NULL REFERENCES merchant_master(id),
  platform        text NOT NULL,          -- 'shopify','shopee','lazada','tiktok',...  (text + CHECK, not enum)
  external_id     text NOT NULL,          -- Shopify variant_id
  product_sku_id  uuid NOT NULL REFERENCES product_sku_master(id) ON DELETE CASCADE,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (merchant_id, platform, external_id)
);

CREATE INDEX idx_product_sku_ext_ref_sku ON product_sku_external_ref (product_sku_id);

-- platform allow-list (cheap to extend, no ALTER TYPE)
ALTER TABLE product_sku_external_ref
  ADD CONSTRAINT product_sku_external_ref_platform_chk
  CHECK (platform IN ('shopify','shopee','lazada','tiktok','bigcommerce'));
```

- `updated_at`: attach the project's standard moddatetime trigger, **or** drop the column. Don't ship a column that never updates.
- **RLS:** mirror `product_sku_master` merchant isolation.
- **Do not** store Shopify IDs in `sku_code` / `product_code`.

### Existing master tables — no new columns

| Table | Role |
|---|---|
| `product_master` | Canonical product; `product_code` = merchant/POS code when present (optional for Shopify-only stubs) |
| `product_sku_master` | Canonical variant; `sku_code` = merchant/POS SKU when present. **Leave NULL for Shopify-only stubs** (the `(sku_code, merchant_id)` unique index permits multiple NULLs). Do **not** synthesize `SHOPIFY-{variant_id}` — it pollutes the POS namespace and risks accidental resolver matches. |

---

## Shared resolver (new) — SKU grain only

```sql
fn_resolve_product_sku_id(
  p_merchant_id uuid,
  p_platform    text,      -- 'shopify', NULL for native/POS
  p_external_id text,      -- variant_id from marketplace line
  p_sku_code    text       -- optional merchant/POS code
) RETURNS uuid             -- product_sku_master.id or NULL
```

**Resolution order:**

1. If `p_platform` + `p_external_id` → lookup `product_sku_external_ref` (unique per merchant/platform).
2. Else if `p_sku_code` not null → lookup `product_sku_master.sku_code` (deterministic: `(sku_code, merchant_id)` is unique).
3. Else NULL.

Returns SKU id only; parent product is derived downstream via `product_sku_master.product_id`. **Backward-compatible:** POS lines (no platform) still resolve via step 2, so each consumer can adopt the resolver independently.

---

## Functions & services to change

### Must change

| Object | Type | What to do |
|---|---|---|
| **`product_sku_external_ref`** | table | Create (migration) + RLS + platform CHECK |
| **`fn_resolve_product_sku_id`** | function | **NEW** — shared resolver (returns sku_id) |
| **`bff_link_product_external_ref`** | function | **NEW** — admin stub/link (see below) |
| **`api_create_purchase`** | function | **Surgical change to the item-resolution block only (body lines 69–103).** Today it `LEFT JOIN product_sku_master ON sku_code = item->>'sku_code' AND merchant_id`. Replace that join with `fn_resolve_product_sku_id(p_merchant_id, item->>'platform', item->>'external_variant_id', item->>'sku_code')` per item. Everything downstream (row payload → `chokepoint_post_purchase_event`) unchanged. The resolver's `sku_code` branch must exactly mirror the current join so POS/receipt callers are byte-identical. |
| **`fn_claim_marketplace_order_service`** | function | Build items with `platform`, `external_variant_id` (= `variant_id`), optional `sku_code` (= merchant sku); pass through to `api_create_purchase`. Shared across all 4 marketplaces — fixes them together. |
| **`shopify-webhooks`** | edge fn | Normalizer fix: `platform_item_id` = `product_id` (currently `li.id ?? li.product_id` — line-item id is unstable). `variant_id` + `platform_sku` already emitted — no change there. |

> Note: `claim_marketplace_order` (the older public RPC) shares item-build logic with `fn_claim_marketplace_order_service`. Extract the item-payload builder **once** (shared helper) instead of patching two functions in parallel, or they will drift.

### Should NOT change (v1)

| Object | Why |
|---|---|
| `evaluate_earn_conditions_core` | Already matches `sku → product_sku_master → product_master` once lines carry `sku_id` |
| `evaluate_earn_conditions` | Reads ledger; no change if `sku_id`/`sku_code` populated at insert |
| `bff_upsert_earn_conditions_group` / `bff_get_earn_conditions_group` | Still store/read CRM UUIDs in `entity_ids` |
| Multiplier CRUD BFFs | `entity_id` stays CRM UUID |
| `bff_upsert_mission` / mission condition BFFs | `sku_ids` / `product_ids` stay CRM UUIDs |
| `chokepoint_post_purchase_event` | Passes through resolved items from `api_create_purchase` |

### Verify in implementation thread (possible small follow-up)

| Object | Check |
|---|---|
| `fn_evaluate_mission_conditions` | Purchase CDC payload must carry CRM `sku_id` / `product_id` — confirm publisher reads `purchase_items_ledger.sku_id` after resolver runs |
| `api_update_purchase` / `api_create_manual_purchase_order` | Apply same resolver if those paths touch marketplace lines |
| `get_entity_options_by_type` / `get_all_entity_options` / `get_products_with_skus` | Admin earn picker — include stub/linked products; optional platform badges from bridge |
| Shopee / Lazada / TikTok claim paths | Already share the claim service — they inherit the payload change; bridge rows added per platform as needed |

### Out of scope (v1)

Brand/category from collections; full catalog sync; storing platform IDs in rule tables; auto-stub on first order without admin action; `evaluate_earn_conditions_core` matching on `sku_id` directly (v2 optional).

---

## New BFF: `bff_link_product_external_ref`

Admin JWT + `get_current_merchant_id()`.

### Input (example)

```json
{
  "platform": "shopify",
  "mode": "create_stub" | "link_existing",
  "product_sku_id": "uuid-if-link_existing",
  "selections": [
    { "shopify_product_id": "8234567890123", "shopify_variant_id": "45678901234567",
      "merchant_sku": "TEE-BLK-M", "product_title": "Classic Tee",
      "variant_title": "Black / M", "image_url": "https://..." }
  ],
  "grain": "variant" | "product"
}
```

### Behavior

**`create_stub`** (Shopify-only / new item):
1. Upsert `product_master` (minimal name/image) → `product_id`.
2. For each variant in scope: upsert `product_sku_master` (parent = `product_id`; set `sku_code = merchant_sku` **only if provided**, else NULL) → `sku_id`.
3. Upsert `product_sku_external_ref(merchant, platform, variant_id, sku_id)` with `ON CONFLICT (merchant_id, platform, external_id) DO UPDATE SET product_sku_id = EXCLUDED.product_sku_id, updated_at = now()` (idempotent + re-link safe).
4. Return `{ product_id, sku_ids[] }`.

**`link_existing`** (multi-channel): validate `product_sku_id` belongs to merchant; upsert bridge row only — no duplicate master.

**`grain: product`**: frontend supplies all variants for the product; bridge every variant so any purchased variant resolves and product-level rules match.

---

## Admin UI flows

- **A — Variant rule (Shopify-only):** pick variant → `create_stub` → save rule `entity=product_sku`, `entity_ids=[sku_id]`.
- **B — Product rule (all variants):** pick product + load variants → `create_stub`, `grain=product` → save rule `entity=product_product`, `entity_ids=[product_id]`.
- **C — Multi-channel link:** find existing CRM SKU → pick Shopify variant → `link_existing` → POS (`sku_code`) and Shopify (`variant_id`) resolve to the **same** `product_sku_master.id`.
- **D — Exclude:** same link/stub, then earn condition with `exclude=true` (existing behavior).

---

## Item payload contract (claim service → `api_create_purchase`)

```json
{
  "platform": "shopify",
  "external_variant_id": "45678901234567",
  "sku_code": "TEE-BLK-M",
  "quantity": 1, "unit_price": 990, "line_total": 990,
  "item_type": "product", "product_name": "Classic Tee", "variant_name": "Black / M"
}
```

- `external_variant_id` — required for marketplace resolution.
- `sku_code` — optional fallback.
- Resolver output → `purchase_items_ledger.sku_id` + `sku_code` copied from matched master.

**Unresolved lines (decision):** insert with `sku_id = NULL` (keep the line for revenue/support visibility; earn simply skips it) rather than dropping silently. Confirm current behavior and align.

---

## Blast radius & safety — `api_create_purchase`

`api_create_purchase` is a high-traffic shared wrapper. In-DB callers (verified via `pg_proc.prosrc`):

| Caller | Path | Sends `platform` / `external_variant_id`? | Effect of change |
|---|---|---|---|
| `bff_approve_receipt_upload` | receipt OCR approval | No | None — `sku_code` branch identical to today |
| `claim_marketplace_order` | older marketplace RPC | Only after we update it | New bridge branch |
| `fn_claim_marketplace_order_service` | Shopify + Shopee/Lazada/TikTok | Only after we update it | New bridge branch |

(Possible direct RPC callers via `p_api_source` external ingestion — same guarantee.)

**Safety contract:** the change is additive. `fn_resolve_product_sku_id`'s step-2 (`sku_code` + `merchant_id`, backed by the `(sku_code, merchant_id)` unique index) reproduces the current join exactly, so any caller not passing `platform`/`external_variant_id` gets a byte-identical `sku_id`. We do **not** modify `chokepoint_post_purchase_event`, the earn engine, or the chokepoint's item contract (still `items[]` with `sku_id`). Verify with a regression smoke on a POS purchase (test row 2) before/after.

## Implementation order

1. Migration — `product_sku_external_ref` + RLS + platform CHECK (+ `updated_at` trigger or drop column).
2. `fn_resolve_product_sku_id` + tests.
3. `api_create_purchase` — integrate resolver (backward-compatible; POS unaffected).
4. Shared item-builder helper → patch `fn_claim_marketplace_order_service` (+ `claim_marketplace_order`).
5. `shopify-webhooks` — normalizer fix `platform_item_id = product_id`. (CLI deploy if jwt rules apply.)
6. `bff_link_product_external_ref`.
7. Smoke: webhook fixture → claim → purchase → earn.
8. Verify mission CDC payload includes `sku_id` / `product_id`.
9. Admin FE (separate thread) — picker → link BFF → existing earn save.

---

## Test matrix

| # | Setup | Order | Expected |
|---|---|---|---|
| 1 | Bridge: shopify variant → stub SKU (sku_code NULL) | Shopify paid order, matched buyer | Resolves, earn matches |
| 2 | Bridge + `sku_code=TEE-BLK-M` | POS order with `TEE-BLK-M` | Same CRM SKU, earn matches |
| 3 | `link_existing` POS + Shopify bridge | Either channel | Same rules |
| 4 | Product rule + all variant bridges | Buy any variant | Product rule matches via parent product_id |
| 5 | No bridge | Shopify order | Line `sku_id NULL`, earn skips line |
| 6 | Re-link same variant to different SKU | — | Bridge re-points (ON CONFLICT DO UPDATE), idempotent |
| 7 | Buyer not matched / order not yet paid | Shopify order | Stored, no purchase, no points until matched + paid |

---

## Open questions — resolved

1. **RLS** → mirror `product_sku_master`.
2. **Unresolved lines** → insert `sku_id NULL` (keep line).
3. **Generated `sku_code`** → leave NULL for Shopify-only stubs.
4. **`platform` type** → `text` + CHECK constraint (not pg enum).

---

## Next thread — first actions

1. Read this plan.
2. `apply_migration` for `product_sku_external_ref` + RLS + CHECK.
3. Implement `fn_resolve_product_sku_id`.
4. Patch `api_create_purchase` (resolver, backward-compatible).
5. Shared item-builder → patch `fn_claim_marketplace_order_service` (+ `claim_marketplace_order`); deploy `shopify-webhooks` normalizer fix.
6. Implement `bff_link_product_external_ref`.
7. Run test matrix rows 1, 4, 5, 7 on staging.
