# Feature Guide: Purchase Transactions

## 1. Overview

Purchase transactions are the primary earning trigger in the loyalty ecosystem — every completed purchase can award currency (points/tickets), advance tier progression, and increment mission progress. The system captures both transaction headers and line-item details in a dual-table architecture, enabling granular product-level earn rules (e.g., 3x points on shoes, 2x on beverages) alongside transaction-wide multipliers.

Transactions flow in from external systems — POS terminals, e-commerce platforms (Shopify, Lazada), mobile apps, admin-approved receipt uploads — not from a dedicated admin form. The system treats purchases as immutable audit records: once completed, a transaction is never modified. Refunds create separate debit records that reverse currency awards proportionally, preserving the full history for reconciliation and analytics.

Key characteristics: (1) **append-only ledger** — credit records for purchases, debit records for refunds, originals never mutated; (2) **flexible processing** — queue (async, high-throughput), direct (immediate gratification), or skip (no currency); (3) **multi-system trigger cascade** — a single completion event independently fires currency calculation, tier evaluation, and mission progress; (4) **dual perspective** — same transaction can track both buyer (B2C) and seller (B2B) for distributor networks.

## 2. Key Concepts

**Purchase Ledger** — The transaction header table (`purchase_ledger`). Stores totals, status, payment info, user/store context, and processing flags. Each row is one transaction with a unique `transaction_number` per merchant. Example: `TXN20241019000123` for a 1,500 THB purchase at Store A.

**Purchase Items Ledger** — The line-item detail table (`purchase_items_ledger`). Each row is one product line within a transaction, linked by `transaction_id`. Stores SKU, quantity, unit price, and line total. Example: 2× Coffee (120 THB each) = 240 THB line total.

**Record Type** — Distinguishes purchases from refunds. `credit` = normal purchase (adds to sales metrics, awards currency). `debit` = refund (subtracts from metrics, reverses currency). Both store positive `final_amount` values — the system negates debits in calculations.

**Transaction Status** — Five-state lifecycle controlling when business logic fires:
- `pending` — created, not finalized, editable
- `processing` — payment authorized, locked from editing
- `completed` — finalized, triggers currency + tier + mission cascade
- `cancelled` — aborted before completion, no loyalty impact
- `refunded` — reversed after completion, triggers currency reversal + tier re-evaluation

**Payment Status** — Independent financial tracking (text field, not enum): `pending`, `authorized`, `paid`, `failed`, `refunded`, `voided`. A transaction can be `status=completed` while `payment_status=authorized` (fulfillment done, settlement pending), or `payment_status=paid` while `status=processing` (payment captured, fulfillment in progress).

**Processing Method** — Controls how currency calculation is routed on completion:
- `queue` — async via PGMQ, non-blocking, currency appears within ~1 minute
- `direct` — synchronous, immediate balance update, slower checkout
- `skip` — no currency processing (test transactions, internal transfers)

**Final Amount** — The net amount the customer actually paid: `total_amount - discount_amount + tax_amount`. This is the value used for currency calculation, tier metrics, and mission progress.

**Buyer / Seller Perspective** — `user_id` tracks the buyer (customer); `seller_id` tracks the seller (distributor/merchant staff). B2C transactions typically have `seller_id = NULL`. Both perspectives can independently earn currency and progress tiers.

**External Reference** — The `external_ref` field links to the source system's transaction ID (Shopify order number, POS receipt number) for reconciliation and refund correlation.

**Transaction Source / API Source** — Two-level channel tracking. `transaction_source` = high-level channel (`online`, `in-store`, `mobile`, `kiosk`). `api_source` = specific system (`POS`, `shopify`, `lazada`, `admin`).

## 3. Configuration Reference

### Transaction Processing

| Setting | What it controls | Values | Default |
|---|---|---|---|
| `processing_method` | Currency award routing on completion | `queue`, `direct`, `skip` | `queue` |
| `earn_currency` | Whether this transaction qualifies for currency awards | `true` / `false` | `true` |

### Status Mapping (E-commerce Integration)

| E-commerce event | Maps to `status` | Maps to `payment_status` |
|---|---|---|
| Payment captured | `completed` (Option A: payment-based trigger) | `paid` |
| Payment captured + fulfilled | `completed` (Option B: fulfillment-based trigger) | `paid` |
| Payment refunded | `refunded` (creates debit record) | `refunded` |
| Order cancelled | `cancelled` | `voided` |

### Amount Calculation

| Level | Formula |
|---|---|
| Line item | `(quantity × unit_price) - line_discount + line_tax = line_total` |
| Transaction | `SUM(line_totals) - discount_amount + tax_amount = final_amount` |

## 4. Admin Journey

**Repo:** `Rocket-CRM/loyalty-admin`

**Route map:**

| Page name | Current route | BFF / data source |
|---|---|---|
| Receipt Uploads | `/receipts-upload` | `v_receipt_upload_list`, `bff_approve_receipt_upload()` |
| Customer 360 | `/customer-360/{userId}` | Customer profile with purchase history tab |

There is no dedicated "Purchase List" admin page. Transactions are created by external systems (POS, e-commerce webhooks, API calls) or through the Receipt Uploads approval flow. Admins interact with purchases in two contexts:

### 4a. Approve a Receipt Upload (Creates Purchase Record)

1. From **Receipt Uploads**, admin sees an IndexTable of member-submitted receipt images with status tabs (All / Pending / Approved / Rejected)
2. Click a receipt row — **Review Modal** opens with receipt image on the left, form on the right
3. Fill in transaction number (required), transaction date, and notes
4. Add line items: click **"Pick SKU"** to open SKU picker, set quantity and price per line — `line_total` auto-computes
5. Click **"Preview Points"** — calls `bff_approve_receipt_upload(action='preview')`, shows estimated points and duplicate warning if transaction number already exists
6. Click **"Approve"** — calls `bff_approve_receipt_upload(action='approve')`, creates a purchase record in `purchase_ledger` + `purchase_items_ledger`, triggers the currency/tier/mission cascade
7. Click **"Reject"** — opens rejection reason modal, marks receipt as rejected

### 4b. View Customer Purchase History

1. From **Customer 360**, search for a member by name/phone/email
2. Navigate to the customer's purchase history tab
3. View transaction list with amounts, dates, status, and currency awarded

### 4c. Common Admin Mistakes

- Approving a receipt without line items — currency calculation may use `final_amount` only, missing product-specific multipliers
- Duplicate transaction number — preview step warns, but approve step blocks with error
- Wrong transaction date — affects tier evaluation window calculations

## 5. Member Experience

**Repo:** `Rocket-CRM/loyalty-user`

**Route map:**

| Page / Component | Current route | Data source |
|---|---|---|
| History Drawer | Bottom-sheet from Homepage/Profile | `bff_get_purchase_history(p_filter, p_limit, p_offset)` |

Members do not create purchases directly in the app. Purchases are recorded by external systems (POS, e-commerce) or via receipt upload approval. Members see their purchase history in the History Drawer.

### 5a. View Purchase History

1. Member opens **History Drawer** (from Homepage or Profile) → selects the **Purchases** tab
2. Sub-filter chips: **"Ordered"** / **"Reviewed"**
3. Each row shows: order number as title, item count, transaction amount, date, and currency earned (points/tickets badges with +/- signs)
4. Infinite scroll pagination for long histories

### 5b. Purchase-Triggered Notifications

1. When a purchase completes and currency is awarded, the member sees the updated points balance on the Homepage **Profile Card**
2. Currency history (viewable in the **Currency** tab of History Drawer) shows the earn entry linked to the purchase with `source_type = 'purchase'`

## 6. Perspectives

### 6a. For Customer Success / Support

**Elevator pitch:** "Every time a customer makes a purchase, the system can automatically award points, progress their tier, and advance their missions. Transactions come in from POS, online stores, or receipt uploads — they're all tracked in one ledger with full refund history."

**Top support questions:**

| Question | Answer |
|---|---|
| "Customer didn't receive points after purchase" | Check: (1) `status` must be `completed`, (2) `earn_currency` must be `true`, (3) `processing_method` — if `queue`, currency may take up to 1 minute; if `skip`, no currency by design. Check `currency_processed_at` and `currency_error` fields. |
| "Customer wants a refund reversal" | Refunds create a new debit record — original transaction stays intact. Currency reversal is automatic and proportional using the original earn rates. |
| "Points from receipt upload are wrong" | Check the line items added during approval — product-specific earn multipliers depend on correct SKU assignment. Preview Points shows the estimate before approval. |
| "Duplicate transaction detected" | The system enforces unique `transaction_number` per merchant. If a duplicate is submitted, approval is blocked. Check if the same receipt was uploaded twice. |
| "Tier didn't upgrade after big purchase" | Tier evaluation is queued with 30-second dedup. Check if `final_amount` meets tier threshold, and whether the evaluation window (rolling/fixed/anniversary) includes this transaction. |

### 6b. For Marketing

**Value proposition:** Purchase transactions close the loyalty loop — customers buy, earn points automatically, see their tier progress, and are motivated to buy again. The system supports any sales channel (in-store POS, e-commerce, mobile) and awards currency in near-real-time, giving customers instant gratification that reinforces the purchase-earn-redeem cycle.

**Use-case stories:**

1. **Fuel station chain** — Every pump transaction sends purchase data via POS API. Currency awarded within 1 minute (queue method). Members see points on the app before leaving the station. Tier upgrades based on monthly spend happen automatically.

2. **Fashion retailer with Shopify** — Online orders trigger purchase creation on payment capture. Product-level earn rates mean premium categories earn 3x points. Refunds auto-reverse the exact proportional currency — no manual adjustment needed.

3. **Distributor network** — B2B transactions track both buyer and seller. The buyer earns points for purchasing; the distributor earns separate points for selling. Both progress through independent tier ladders.

4. **FMCG brand with receipt uploads** — Members photograph store receipts and submit via the app. Admin reviews, adds line items with correct SKUs, and approves. Product-specific earn rates apply to each verified line item. The preview step shows estimated points before committing.

**Metrics merchants care about:** Transaction volume by channel, average transaction value, currency award rate (points per THB), refund rate, time-to-currency (purchase → points in wallet).

**Differentiators to highlight:**
- **Any-channel ingestion** — POS, Shopify, Lazada, receipt uploads, and custom API all feed into one ledger
- **Near-real-time earning** — queue method delivers currency within ~1 minute; direct method is instant
- **Product-level granularity** — different earn rates for different SKUs, categories, and brands in the same transaction
- **Automatic refund reversal** — proportional currency clawback using original earn rates, no manual intervention

### 6c. For Testers

**Config → expected behavior:**

| Config | Expected behavior |
|---|---|
| `status = 'completed'`, `earn_currency = true`, `processing_method = 'queue'` | Currency awarded within ~1 minute via queue |
| `status = 'completed'`, `earn_currency = true`, `processing_method = 'direct'` | Currency awarded immediately in same transaction |
| `status = 'completed'`, `processing_method = 'skip'` | No currency awarded regardless of `earn_currency` |
| `status = 'completed'`, `earn_currency = false` | No currency awarded regardless of `processing_method` |
| `status = 'pending'` or `'processing'` | No currency, no tier eval, no mission progress |
| `status = 'cancelled'` | No loyalty impact; record preserved for audit |
| `record_type = 'debit'` (refund) | Currency reversed proportionally using original earn rates |
| `seller_id` populated | Both buyer and seller evaluated for tier/currency independently |

**Status transition assertions:**

- ASSERT: `pending` → `processing` → `completed` is the normal flow
- ASSERT: `completed` → `refunded` creates a new debit record, does not modify original
- ASSERT: `completed` → `pending` is invalid (cannot uncomplete)
- ASSERT: `cancelled` → `completed` is invalid (cannot resurrect)
- ASSERT: `cancelled` and `refunded` are terminal states

**Business rules as assertions:**

- ASSERT: On `status = 'completed'`, three independent triggers fire: currency, tier, mission
- ASSERT: Currency reversal uses the original transaction's earn rates stored in `wallet_ledger.metadata`, not current rates
- ASSERT: Partial refund creates a debit record with proportional `final_amount`; currency reversal is proportional
- ASSERT: `transaction_number` is unique per merchant — duplicate INSERT fails
- ASSERT: `final_amount = total_amount - discount_amount + tax_amount`
- ASSERT: Line item `line_total = (quantity × unit_price) - discount_amount + tax_amount`
- ASSERT: Tier evaluation has 30-second dedup — rapid consecutive purchases don't flood the queue
- ASSERT: Mission progress evaluates product filters against `purchase_items_ledger` line items

**Status model (two independent tracks):**

| Track | Field | Values | Meaning |
|---|---|---|---|
| Transaction | `status` | `pending` → `processing` → `completed` | Business lifecycle |
| Transaction (terminal) | `status` | `cancelled`, `refunded` | Final states, no further transitions |
| Payment | `payment_status` | `pending`, `authorized`, `paid`, `failed`, `refunded`, `voided` | Financial settlement (independent of transaction status) |

**Error states to test:**

- Purchase with non-existent `user_id` → creation fails
- Purchase with non-existent `store_id` → creation fails or store context missing
- Line items referencing non-existent `sku_id` → creation fails
- Currency processing failure → `currency_error` populated, `currency_processed_at` remains null
- Concurrent purchases by same user → each processed independently, queue dedup prevents tier evaluation flooding
- Refund amount exceeding original `final_amount` → should be blocked
- Receipt upload with duplicate `transaction_number` → preview warns, approve blocks

## 7. Business Rules

**Rule:** `status = 'completed'` is the single trigger point for all loyalty operations — currency award, tier evaluation, and mission progress all fire on this transition.
**Example:** Transaction inserted with `status = 'pending'` → no loyalty impact. Status updated to `'completed'` → triggers fire.

**Rule:** Refunds create new debit records; originals are never modified (append-only ledger).
**Example:** Original TXN001 (credit, 1,500 THB, 15 points awarded). Refund creates TXN001-REF (debit, 1,500 THB). Net sales = 0, net currency = 0.

**Rule:** Partial refunds create proportional debit records. Currency reversal uses the original earn rates stored in metadata.
**Example:** 1,500 THB purchase earned 15 points during a 3x promotion. 500 THB partial refund → reverses 5 points (using original 3x rate), not the current 1x rate.

**Rule:** Processing method determines currency routing. Queue is non-blocking (~1 min delay), direct is synchronous (immediate), skip bypasses currency entirely.
**Example:** High-volume merchant uses `queue` for POS transactions. VIP lounge uses `direct` for instant gratification.

**Rule:** Transaction status and payment status are independent. Either can advance without the other.
**Example:** E-commerce order: `payment_status = 'paid'` but `status = 'processing'` (payment captured, awaiting fulfillment). Loyalty operations don't fire until `status = 'completed'`.

**Rule:** Empty `seller_id` means B2C transaction. Populated `seller_id` enables dual-perspective evaluation — buyer and seller each get independent currency and tier processing.
**Example:** Distributor sells to retailer → distributor earns seller-tier points, retailer earns buyer-tier points.

**Rule:** `transaction_number` must be unique per merchant. Duplicates are rejected.
**Example:** POS sends TXN001 twice → second insert fails, preventing double-counting.

**Rule:** Line-item product hierarchy enables granular earn multipliers. Category, brand, and SKU-level rates apply to individual lines before transaction-wide multipliers apply to the remainder.
**Example:** Transaction has shoes (3x category) and socks (1x). Shoes earn 3x on their line total, socks earn base rate. Birthday bonus (2x) applies to the remainder.

## 8. Related Features

| Feature | Connection to Purchase Transactions |
|---|---|
| Currency | Completed purchases trigger currency award via `calc_currency_for_transaction()`. Refunds trigger proportional reversal. See `Currency.md`. |
| Tier | Completed purchases contribute to tier metrics (sales = `SUM(final_amount)`, orders = `COUNT(*)`). Triggers `queue_tier_evaluation()`. See `Tier.md`. |
| Mission | Purchase conditions evaluate against transaction amount and line-item product filters. See `Mission.md`. |
| Store Classification | `store_id` resolves to store attribute sets for location-based earn multipliers and mission conditions. See `Store_Attribute_Classification.md`. |
| Activity/Earning | Earn factors (multipliers by product, category, brand, store, tier) are evaluated against purchase line items. See `Activity_Based_Earning.md`. |
| Receipt Upload | Admin-approved receipt uploads create purchase records via `bff_approve_receipt_upload()`. |
