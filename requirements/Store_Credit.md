# Store Credit (Internal Top-up)

Per-member internal prepaid balance for frontline top-up, promo bonus, spend at checkout, expiry, and reversal — implemented as a credit **ticket** wallet (`credit_platform = internal`), not purchase-linked top-ups.

Owner surfaces: loyalty-admin Front Line, loyalty-user checkout spend (where wired), event order flows (optional spend)

## Concept

**Internal store credit (partial — demo-built frontline path; not GA)** — When launched, staff would top up a member’s internal credit wallet (THB 1:1), apply tiered promo bonuses, generate spend codes for POS, and optionally burn credit on event/manual orders. Wallet chokepoint, promos table, and Front Line tab are implemented; promo admin UI, member self top-up, and broad plan rollout are not. Portfolio: [Shelved_Demo_Features.md](./Shelved_Demo_Features.md).

**Internal credit ticket type** — One bootstrap row per merchant (`STORE_CREDIT_INTERNAL`); 1 credit = 1 THB integer.

**Top-up session** — Base earn + optional promo bonus grouped by `metadata.topup_session_id` on `wallet_ledger`.

**Promo tier** — `store_credit_promo` rows; best matching `min_topup_amount` wins; hard cap `max_bonus_per_topup`.

**Spend / reversal** — Burns through chokepoint like other ticket currencies; Shopify external credit is a separate ticket type.

## Rules

- All writes go through `chokepoint_post_wallet_transaction` only.
- Top-ups do not create `purchase_ledger` rows.
- Promo selection: active, in-window, scope-matching rows where `min_topup_amount <= amount` → `ORDER BY min_topup_amount DESC LIMIT 1`.
- Expiry follows `ticket_type` config via existing `process_currency_expiry`.
- `credit_platform = shopify` store credit is unchanged and documented under Shopify/Currency — not this doc.
- **Launch gate:** Front Line Store Credit tab requires `frontline_store_credit` permission; promo CRUD uses `bff_store_credit_promo` — no standalone promo settings page in loyalty-admin today.

## Journeys

### Admin / frontline journey

| Knob | Effect |
| --- | --- |
| Top-up amount | Base earn + eligible promo bonus |
| Event-scoped promo | `event_id` on promo row |
| Promo windows | `window_start` / `window_end` |

1. Staff opens member → store credit top-up.
2. System posts base earn + computed bonus under one session id.
3. Member spends at checkout or staff reverses per frontline tools.

### Member journey

1. View internal credit balance (ticket wallet UI).
2. Apply credit at checkout when merchant enables spend path.
3. Expiry notifications follow Currency expiry rules.

3. Expiry notifications follow Currency expiry rules.

Member checkout spend and self top-up remain optional / out of v1 scope — enable only where product wires loyalty-user to `bff_store_credit` spend modes.

## System

`ticket_type` (internal credit), `store_credit_promo`, `wallet_ledger` / `user_ticket_balances`, chokepoint helpers — detail in technical reference.

### Known gaps (launch checklist)

| Area | Gap |
| --- | --- |
| Admin | Dedicated promo configuration page (today: BFF-only + Front Line promo list) |
| Product | GA entitlements, member self top-up, purchase ledger on top-up — v1 out of scope in doc |
| Integration | Stored value cards not linked — [Stored_Value_Cards.md](./Stored_Value_Cards.md) |
| Member app | Checkout spend path merchant-specific |
| Ops | Expiry uses shared `process_currency_expiry` — ensure cron covers internal credit ticket type per merchant |
| External | Shopify store credit issue queue unchanged (`trg_enqueue_shopify_store_credit_issue`) — separate product surface |

## Related

- **[Shelved_Demo_Features.md](./Shelved_Demo_Features.md)** — Launch status index.
- **Currency.md** — Ticket wallets, expiry, chokepoint.
- **Purchase_Transaction.md** — Optional spend linkage on orders only.
- **Shopify.md** — External Shopify store credit ticket type.
- **Stored_Value_Cards.md** — Prepaid cards; not this wallet.

---

# Store Credit — technical reference

## Overview

| Concept | Implementation |
|---|---|
| Wallet | `user_ticket_balances` + `wallet_ledger` for one `ticket_type` row (`is_credit = true`, `credit_platform = 'internal'`) |
| Unit | 1 credit = 1 THB (integer) |
| Top-up audit | `wallet_ledger` only — rows grouped by `metadata.topup_session_id` |
| Promos | Single table `store_credit_promo` — each row is one bonus condition |
| Bonus cap | `max_bonus_per_topup` on each promo row |
| Expiry | Per `ticket_type` config; processed by existing `process_currency_expiry` |
| Writes | `chokepoint_post_wallet_transaction` only |

Shopify / external store credit (`credit_platform = 'shopify'`) is unchanged — separate ticket type per merchant.

---

## Schema

### `ticket_type` (existing — bootstrap)

One internal credit row per merchant (via `fn_resolve_internal_store_credit_ticket_type(..., p_bootstrap := true)`):

| Field | Value |
|---|---|
| `ticket_code` | `STORE_CREDIT_INTERNAL` |
| `is_credit` | `true` |
| `credit_platform` | `internal` |
| `metadata` | `{ "credit_currency": "THB", "ticket_to_credit_rate": 1 }` |

### `store_credit_promo` (new)

Each row = one bonus condition (tier). Multiple rows may share the same `name` for admin grouping.

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | Bonus earn uses `wallet_ledger.source_id = id` |
| `merchant_id` | uuid | |
| `name` | text | Display / admin label |
| `is_active` | boolean | Default true |
| `window_start` / `window_end` | timestamptz | NULL = open |
| `event_id` | uuid | NULL = merchant-wide; set = event-scoped |
| `min_topup_amount` | integer | Threshold (THB) |
| `bonus_type` | text | `fixed` \| `percent` |
| `bonus_amount` | integer | When fixed |
| `bonus_percent` | numeric(5,2) | When percent |
| `max_bonus_amount` | integer | Sub-cap for percent calc |
| `max_bonus_per_topup` | integer | **Hard cap on bonus for one top-up** |
| `created_at` / `updated_at` | timestamptz | |

**Runtime selection:** among active, in-window, scope-matching rows where `min_topup_amount <= topup_amount`, pick **`ORDER BY min_topup_amount DESC LIMIT 1`** (best tier wins).

---

## Wallet ledger conventions

### Top-up base earn

| Field | Value |
|---|---|
| `currency` | `ticket` |
| `transaction_type` | `earn` |
| `component` | `base` |
| `source_type` | `manual` |
| `metadata` | `operation`, `topup_session_id`, optional `paid_amount`, `event_id`, `admin_user_id` |

### Promo bonus earn

| Field | Value |
|---|---|
| `component` | `bonus` |
| `source_type` | `campaign` |
| `source_id` | `store_credit_promo.id` |
| `metadata` | `operation = store_credit_topup_bonus`, same `topup_session_id` |

### Spend burn

| Field | Value |
|---|---|
| `transaction_type` | `burn` |
| `component` | `base` |
| `source_type` | `purchase` (when linked to order) or `manual` |
| `metadata` | `operation = store_credit_spend`, `spend_session_id`, optional `purchase_id`, `event_id` |

### Dedup keys

- `store_credit_topup:{session_id}:base` / `:bonus`
- `store_credit_spend:{session_id}`

---

## Functions

### Helpers (internal)

| Function | Purpose |
|---|---|
| `fn_resolve_internal_store_credit_ticket_type(p_merchant_id, p_bootstrap default false)` | Resolve or bootstrap internal credit ticket type |
| `fn_calc_store_credit_promo_bonus(p_merchant_id, p_topup_amount, p_event_id default null)` | Match promo + apply `max_bonus_per_topup` |

### BFF — promos (admin config + frontline display)

**`bff_store_credit_promo(p_mode, p_id default null, p_data default '{}')`**

| Mode | Permission | Action |
|---|---|---|
| `list` | `store_credit_promo` view **or** `frontline_store_credit` view | Active promos for display; optional `p_data.event_id` |
| `get` | `store_credit_promo` view | One row or empty template |
| `upsert` | `store_credit_promo` update | Insert/update row from `p_data` |
| `delete` | `store_credit_promo` update | Delete by `p_id` |

### BFF — wallet (frontline + admin operations)

**`bff_store_credit(p_mode, p_data default '{}')`**

| Mode | Permission | Action |
|---|---|---|
| `get` | `frontline_store_credit` view | Balance + ledger (grouped by `topup_session_id`) |
| `list_promos` | `frontline_store_credit` view | Alias of promo list for single-FE-entry |
| `preview_topup` | `frontline_store_credit` view | Calc bonus; no write |
| `topup` | `frontline_store_credit` create | Post base + optional bonus earns |
| `preview_spend` | `frontline_store_credit` view | Balance check |
| `spend` | `frontline_store_credit` create | Burn store credit |
| `submit_event_order` | `frontline_store_credit` create | Atomic spend + `api_create_manual_purchase_order` |
| `reverse_topup` | `frontline_store_credit` create or `currency` update | Claw back session by `topup_session_id` |
| `reverse_spend` | `frontline_store_credit` create or `currency` update | Re-credit by `spend_session_id` |
| `expiry` | `frontline_store_credit` view | Upcoming expiry on earn rows |
| `reverse_expiry` | `currency` update | CS restore expired credit |

**Bonus evaluation:** only in `preview_topup` and `topup` via `fn_calc_store_credit_promo_bonus`. Promo BFF is config/display only.

---

## Flows

### Frontline top-up

1. (Optional) `bff_store_credit_promo('list', …)` or `bff_store_credit('list_promos', …)` — show tiers.
2. `bff_store_credit('preview_topup', { user_id, amount, event_id })` — live bonus preview.
3. `bff_store_credit('topup', { user_id, amount, paid_amount?, event_id?, reason? })` — wallet write.

`paid_amount` is informational metadata only (nullable for comp top-ups). No purchase row.

### Event checkout with store credit

`bff_store_credit('submit_event_order', { user_id, store_credit_amount, items, event_id, … })` — burn then create order in one transaction.

### Reversal

| Scenario | Mode |
|---|---|
| Wrong top-up | `reverse_topup` + `topup_session_id` |
| Cancel spend / order | `reverse_spend` + `spend_session_id` |
| Mistaken expiry | `reverse_expiry` + earn `wallet_ledger_id` |

---

## Permissions (admin catalog)

| Category | Resource |
|---|---|
| `frontline` | `frontline_store_credit` |
| `loyalty` | `store_credit_promo` |

---

## Compatibility

| Existing | Impact |
|---|---|
| Shopify credit ticket type | Unchanged — separate `credit_platform` |
| `bff_admin_adjust_currency` | Unchanged — raw manual adjust without promo |
| Point discount burn BFFs | Unchanged |
| `process_currency_expiry` | Unchanged — applies to internal credit ticket type |
| Ticket per-unit ledger rows | Large top-ups create one ledger row per credit unit (existing ticket chokepoint behaviour) |

---

## Out of scope (v1)

- Max claims / per-user promo limits
- Purchase ledger on top-up
- Member self-service top-up payment
- Stored Value Cards integration

## Additional helpers (registry)

- `fn_store_credit_wallet_history` — wallet history for store-credit ticket wallets
- `fn_generate_store_credit_spend_code` — spend code generation
- `trg_enqueue_shopify_store_credit_issue` on `wallet_ledger` — Shopify store-credit issue path (`shopify-issue-store-credit` edge)
