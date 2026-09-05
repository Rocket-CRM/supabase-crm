# Purchase Transaction System - Complete Business Description

## Overview

### Core Purchase Concept
Our purchase transaction system implements a **dual-table architecture** that captures both transaction headers and line-item details, enabling sophisticated loyalty program integration through granular product-level analysis. The system recognizes that purchases are the primary driver of customer engagement, currency earning, and tier progression.

#### Transaction Architecture
- **Purchase Ledger**: Transaction-level metadata tracking totals, payments, and status
- **Purchase Items Ledger**: Line-by-line product details with SKU-level granularity
- **Source**: Integrated with currency calculation, tier evaluation, and mission progress systems

#### Purchase Philosophy
Purchases serve multiple purposes beyond transaction recording. Each completed purchase triggers cascading effects across the loyalty ecosystem through event-driven architecture. The system treats purchases as **immutable audit records** where refunds create new debit records rather than modifying originals.

### Transaction Processing Philosophy
Users create purchases that progress through defined status states, triggering business logic at specific transition points. The system supports:

- **Multi-Channel Sources**: API integrations, admin entry, external systems, e-commerce platforms
- **Flexible Processing**: Immediate or queued currency calculation based on business needs
- **Buyer/Seller Perspectives**: Dual tracking for B2C and B2B transaction scenarios
- **Credit/Debit Pattern**: Refunds as separate records maintaining complete history

## Core Tables and Structure

### 1. purchase_ledger Table
This table defines transaction headers with complete financial and operational metadata. Key fields include:

| Field | Type | Purpose |
|-------|------|---------|
| `id` | uuid | Unique transaction identifier used throughout system |
| `merchant_id` | uuid | Merchant ownership establishing data isolation boundaries |
| `transaction_number` | text | Human-readable unique identifier per merchant for customer reference |
| `transaction_date` | timestamptz | When transaction occurred (business date, may differ from created_at) |
| `user_id` | uuid | Customer who made the purchase (buyer perspective) |
| `seller_id` | uuid | Seller user (FK to `user_accounts.id`, typically `user_type = 'seller'`, nullable). Powers the seller self-service completion flow. FK is `NOT VALID` so 26 historical orphan rows were grandfathered; new and updated rows are enforced. |
| `store_id` | text | Store code from store_master where purchase occurred |
| `total_amount` | numeric | Sum of all line items before discounts/tax |
| `discount_amount` | numeric | Total discounts applied to transaction |
| `tax_amount` | numeric | Total tax charged |
| `final_amount` | numeric | Net amount after discounts and tax (what customer actually paid) |
| `status` | enum | Transaction lifecycle state (see Status Model section below) |
| `payment_status` | text | Payment processing state (pending/authorized/paid/refunded) |
| `record_type` | enum | 'credit' for normal purchases, 'debit' for refunds |
| `processing_method` | text | Currency award routing: 'queue' (async), 'direct' (immediate), 'skip' (none) |
| `earn_currency` | boolean | Whether this transaction qualifies for currency awards (default true) |
| `currency_processed_at` | timestamptz | When currency calculation completed (nullable until processed) |
| `currency_error` | text | Error message if currency processing failed |
| `transaction_source` | text | Channel identifier (online/in-store/mobile/kiosk) |
| `api_source` | text | Source system name (POS/mobile_app/ecommerce/admin) |
| `external_ref` | text | Reference to external system's transaction ID for reconciliation |
| `notes` | text | Additional transaction notes or context |
| `created_at` | timestamptz | Record creation timestamp (system time) |
| `updated_at` | timestamptz | Last modification timestamp |
| `skip_cdc` | boolean | When true, row is excluded from **chokepoint outbox publish** (migration/backfill). Default false. |
| `completed_by_user_id` | uuid | `user_accounts.id` of the actor that flipped the row to `completed` (NULL for system/admin/API). Stamped on every transition by writers and the rollup helper. |
| `completed_by_source` | text | Free-form source tag explaining how the row was completed: `seller_self_service`, `seller_line_item_completion`, `api_external`, `system_bulk_import`, `refund_flow`, `marketplace_claim`, `historical_backfill`, or `parent_cascade`. |
| `completed_at` | timestamptz | Timestamp of the transition to `completed`. **Invariant** (forward-looking): `status = 'completed'` ⇒ `completed_at IS NOT NULL`. Historical pre-2026-05-10 rows may have NULL completed_at. |

**Unique Constraint**: `transaction_number` must be unique per merchant for customer-facing reference (NOT enforced — see "Transaction Number Disambiguation" below).

**Transaction Number Disambiguation**: Historical data contains duplicate `(merchant_id, transaction_number)` pairs. Seller self-service functions disambiguate by also filtering on `seller_id = caller`. If multiple pending rows still match, the BFFs return `AMBIGUOUS_TRANSACTION_NUMBER`.

### 2. purchase_items_ledger Table
This table stores individual line items within each transaction with SKU-level detail. Key fields include:

| Field | Type | Purpose |
|-------|------|---------|
| `id` | uuid | Unique line item identifier |
| `transaction_id` | uuid | References parent transaction in purchase_ledger |
| `merchant_id` | uuid | Merchant context for data isolation |
| `sku_id` | uuid | References product_sku_master for product variant detail |
| `quantity` | numeric | Number of units ordered (supports decimals for weight-based products). Immutable after insert except via `api_update_purchase` items replacement. |
| `quantity_completed` | numeric | How much of `quantity` has been picked up / fulfilled. Defaults to `0`. **CHECK constraint**: `0 ≤ quantity_completed ≤ quantity`. Set to `quantity` at insert time when the parent is born `completed` (api_create_purchase, bulk_insert_purchases_with_items, 
### Marketplace order landing (live)

Shopee/Lazada/TikTok: `webhook-marketplace-*` → Inngest `marketplace/order-received` → `upsert_marketplace_order` → member `claim_marketplace_order` (see [`Marketplace.md`](./Marketplace.md)). Shopify: `shopify-webhooks` may auto-claim via `fn_claim_marketplace_order_service` when the buyer matches. Manual claim RPC remains for the member Order Claims UI.

claim_marketplace_order, refund_purchase). Updated by `bff_seller_complete_purchase_items` (per-line partial pickup) and by `trg_purchase_complete_cascade_items` (when parent is force-completed). Monotonic non-decreasing — the BFF rejects requests that would lower `quantity_completed`. |
| `unit_price` | numeric | Price per unit before discounts |
| `discount_amount` | numeric | Discount applied to this line (nullable, defaults 0) |
| `tax_amount` | numeric | Tax charged on this line (nullable, defaults 0) |
| `line_total` | numeric | Final line amount: (quantity × unit_price) - discount + tax |
| `status` | enum | Per-line lifecycle (same `purchase_status` enum as parent). Default `'pending'`. **Derived from `quantity_completed`** at every write site: `quantity_completed = quantity` ⇒ `'completed'`, anything less ⇒ `'pending'` (no separate "partial" state — items stay pending until fully complete). Cascades to `'completed'` when the parent flips, via `trg_purchase_complete_cascade_items` (which also sets `quantity_completed = quantity`). Sellers update individual lines via `bff_seller_complete_purchase_items`. |
| `completed_by_user_id` | uuid | `user_accounts.id` of the actor that completed this line (NULL for cascade or default writes). |
| `completed_by_source` | text | Source tag, parallel to `purchase_ledger.completed_by_source`. Adds `parent_cascade` for cascaded rows. |
| `completed_at` | timestamptz | Per-line completion timestamp. |
| `created_at` | timestamptz | Line item creation timestamp |
| `updated_at` | timestamptz | Last modification timestamp |

**Relationship**: Multiple items belong to one transaction (one-to-many)

**Status Cascade Rules**:
- Parent → children: parent flipping to `completed` cascades to all children via a **statement-level** trigger (one fire per UPDATE statement, regardless of row count). The cascade also stamps `quantity_completed = quantity` on each child so the line-level invariant `status='completed' ⇔ quantity_completed = quantity` holds.
- Children → parent: rolled up **inline** by the seller line-item BFF (no row-level trigger on this high-volume table). Reusable rollup is exposed as `fn_recompute_purchase_status(p_purchase_id, p_completed_by_user_id, p_completed_by_source)`. Parent flips only when **every** child has `status='completed'` (i.e. `quantity_completed = quantity` for every line).
- Bulk admin scripts can opt out of the cascade by setting `SET LOCAL app.purchase_cascade_skip = 'on';` before their UPDATE.

**Partial Pickup Invariant**:
- `quantity_completed` is the source of truth for line-level fulfillment. `status` is derived from it at every write — no row-level trigger.
- A line can sit at any `0 ≤ quantity_completed < quantity` indefinitely; status remains `'pending'` until the line is fully fulfilled. The parent therefore stays `'pending'` while any line is partial.
- `quantity_completed` is **monotonic non-decreasing** within a line's lifecycle. The seller BFF rejects requests that would lower it (`MONOTONIC_VIOLATION`). To "undo" a pickup, cancel/refund the line via the appropriate flow — never decrement `quantity_completed` directly.
- Earning (currency / tier / mission) is still keyed off `quantity` (the ordered amount), not `quantity_completed`. Partial pickup does not partially award points.

### 3. Integration Tables

#### user_accounts (purchase-relevant fields)
| Field | Type | Purpose |
|-------|------|---------|
| `id` | uuid | User identifier (buyer in most transactions) |
| `merchant_id` | uuid | Merchant context |
| `user_type` | enum | 'buyer' or 'seller' - determines perspective in calculations |
| `tier_id` | uuid | Current tier affecting earn rates and multipliers |
| `persona_id` | uuid | Business profile affecting pricing and eligibility |

#### product_sku_master (line item detail source)
| Field | Type | Purpose |
|-------|------|---------|
| `id` | uuid | SKU identifier referenced by line items |
| `product_id` | uuid | Parent product linking to category/brand hierarchy |
| `sku_code` | text | Human-readable SKU identifier |
| `price` | numeric | Standard retail price for reference |

#### store_master (location context)
| Field | Type | Purpose |
|-------|------|---------|
| `id` | uuid | Store identifier |
| `store_code` | varchar | Human-readable code stored in purchase_ledger.store_id |
| `merchant_id` | uuid | Store ownership |

## Business Logic and Concepts

### Transaction Status Model

The `status` field in `purchase_ledger` tracks transaction lifecycle with five states driving business logic:

#### Status State Machine

**pending** (Initial State):
- Transaction created but not finalized
- Payment not yet confirmed
- Inventory may be reserved
- Can be edited or cancelled
- No currency awarded
- No tier evaluation triggered

**processing** (In-Progress):
- Payment authorized or in progress
- Fulfillment preparation underway
- Transaction locked from editing
- Still no currency awarded
- Awaiting final confirmation

**completed** (Final State - Primary Trigger):
- **CRITICAL**: This status triggers currency award and tier evaluation
- Payment confirmed and captured
- Fulfillment complete or not applicable
- Transaction finalized and immutable
- Currency calculation executes based on `processing_method`
- Tier evaluation queued for user
- Mission progress increments if conditions match

**cancelled** (Termination):
- Transaction aborted before completion
- Payment voided or never captured
- No currency awarded
- No tier impact
- Historical record preserved

**refunded** (Post-Completion Reversal):
- Previously completed transaction reversed
- Payment returned to customer
- **Triggers currency reversal** via separate debit record
- **Triggers tier re-evaluation** due to reduced spend
- Original transaction preserved, new debit record created

#### Status Transition Rules

**Valid Transitions**:
- pending → processing → completed (normal flow)
- pending → cancelled (early termination)
- processing → cancelled (mid-flow termination)
- completed → refunded (post-completion reversal)

**Invalid Transitions**:
- ❌ completed → pending (cannot uncomplete)
- ❌ cancelled → completed (cannot resurrect)
- ❌ refunded → completed (cannot un-refund)

**One-Way Terminal States**: cancelled and refunded are final

### Payment Status Dimension

The `payment_status` field provides **independent financial lifecycle tracking**:

**Purpose**: Separate payment processing state from business workflow state

**Common Values**:
- `'pending'` - Awaiting payment initiation
- `'authorized'` - Payment method approved, funds on hold
- `'paid'` - Money captured successfully
- `'failed'` - Payment processing failed
- `'refunded'` - Money returned to customer
- `'voided'` - Authorization cancelled before capture

**Independence**: Payment status can be 'paid' while transaction status is still 'processing' (payment complete but fulfillment pending), or transaction can be 'completed' while payment is 'authorized' (fulfillment done but payment settlement pending).

**Not Constrained**: Text field allows flexible values from various payment processors

### Design Decision: Quantity-Driven Line Fulfillment

**Current Model**: Header `status` is a coarse lifecycle (pending → completed → cancelled / refunded). Per-line fulfillment is tracked by `purchase_items_ledger.quantity_completed`, and the line's `status` is derived from the ratio at every write.

**Rationale**:
- Supports **instant fulfillment** (fuel, convenience store, digital, services) — items are born `completed` with `quantity_completed = quantity` so the line is final from inception.
- Supports **deferred / partial pickup** (manual orders, the seller pickup flow shown in `bff_seller_complete_purchase_items`) — items are born `pending` with `quantity_completed = 0` and the seller increments `quantity_completed` over one or more pickup events.
- Status is **derived, not orthogonal** — there is no third "fulfillment status" dimension to maintain in sync. `status='completed'` ⇔ `quantity_completed = quantity` at the line level.
- Partial state is represented by data, not by a new enum value: a line with `0 < quantity_completed < quantity` is still `pending`. The header stays `pending` until every line is fully fulfilled. This was a deliberate choice to avoid splintering downstream consumers (currency, tier, mission) that filter on `status = 'completed'`.

**Use Cases Supported**:
- Fuel purchases (instant consumption — born completed)
- Convenience store transactions (customer takes items — born completed)
- Digital product delivery (instant activation — born completed)
- Service consumption (on-site — born completed)
- In-store retail (immediate possession — born completed)
- **Manual orders with deferred pickup** (born pending; seller increments `quantity_completed` per pickup event)
- **Multi-event pickup** (e.g. customer orders 100 units, picks up 80 today and 20 next week — line stays `pending` and parent stays `pending` until the full 100 is collected)

**E-commerce Integration Note**: When integrating with platforms like Shopify that have order/payment/fulfillment status dimensions, map their multi-status to your single `status` + `quantity_completed` based on business rules:
- Shopify "Payment Paid + Fulfillment Fulfilled" → insert items with `quantity_completed = quantity` and `status = 'completed'`
- Shopify "Payment Paid + Fulfillment Partial" → insert items with `quantity_completed = fulfilled_qty` and `status = 'pending'` (header stays pending)
- Shopify "Payment Refunded" → header `status = 'refunded'` (line `quantity_completed` left as-is — the refund is a separate debit record)
- Choose trigger point (payment vs fulfillment) based on merchant's refund risk tolerance

### Record Type - Credit/Debit Pattern

The `record_type` field implements **append-only transaction history**:

#### Credit Records (Normal Purchases)
- `record_type = 'credit'`
- Positive `final_amount` contributing to sales metrics
- Creates currency awards
- Increases tier progression metrics
- Default type for all purchases

#### Debit Records (Refunds)
- `record_type = 'debit'`
- Positive `final_amount` but treated as negative in calculations
- Triggers currency reversal
- Decreases tier progression metrics
- Links to original transaction via `external_ref` or correlation

**Why Not Modify Original**:
- Preserves complete audit trail
- Enables partial refunds (multiple debit records per credit)
- Maintains immutability principle
- Supports time-based analytics (when did refund occur?)

**Calculation Handling**:
```
Sales Metric = SUM(CASE 
  WHEN record_type = 'credit' THEN final_amount
  WHEN record_type = 'debit' THEN -ABS(final_amount)
END)
```

### Buyer vs Seller Perspective

The `user_id` and `seller_id` fields enable **dual-perspective transaction tracking**:

#### Buyer Perspective (B2C Transactions)
- `user_id` identifies the customer making purchase
- Most common scenario for loyalty programs
- Tier evaluation queries: `WHERE user_id = customer_id`
- Mission conditions with `user_perspective = 'customer'`
- Represents consumer spending behavior

#### Seller Perspective (B2B Transactions)
- `seller_id` identifies the merchant/distributor processing sale
- Used in distributor networks, marketplace platforms
- Tier evaluation queries: `WHERE seller_id = distributor_id`
- Mission conditions with `user_perspective = 'seller'`
- Represents seller performance and revenue

**Dual Tracking**: Same transaction can be analyzed from both perspectives:
- Customer A (buyer) earned points for purchasing
- Distributor B (seller) earned points for selling
- Each has their own tier progression based on their role

**Nullable seller_id**: Most B2C transactions have NULL seller_id (direct merchant sales)

### Currency Award Integration

The purchase system seamlessly integrates with the currency calculation engine:

#### Trigger Conditions
When `status` changes to `'completed'`:
1. System checks `earn_currency` flag (default true)
2. Evaluates `processing_method` configuration
3. Routes to currency calculation engine

#### Processing Paths

**Queue Method** (Default - Recommended):
- Purchase completes → Trigger fires → Message queued to PGMQ
- Transaction returns immediately (non-blocking checkout)
- Queue processor runs every 30-60 seconds
- Calls `calc_currency_for_transaction()` → `chokepoint_post_wallet_transaction()`
- Currency appears in wallet within 1 minute
- **Benefit**: High throughput, no checkout delays

**Direct Method** (Immediate):
- Purchase completes → Trigger fires → Synchronous calculation
- Calls currency functions in same transaction
- User sees currency instantly
- **Benefit**: Real-time gratification, immediate balance updates
- **Drawback**: Slower checkout for high-volume scenarios

**Skip Method** (No Currency):
- Purchase completes → No currency processing
- Used for: Test transactions, internal transfers, refunds that shouldn't reverse
- Set `earn_currency = false`

#### Currency Calculation Scope

The calculation engine evaluates:
- **Base Rate**: Converts purchase amount to currency (100 THB = 1 point)
- **Multipliers**: Applies earn factors based on product, category, brand, store, tier
- **Line-Item Analysis**: Can apply different rates to different products in same transaction
- **Store Attribution**: Uses `store_id` to determine location-based bonuses

**Integration Point**: `purchase_ledger.id` stored in `wallet_ledger.source_id` with `source_type = 'purchase'`

### Tier Evaluation Integration

Purchase completions trigger tier evaluation through event-driven architecture:

#### Trigger Logic


**Live tier path:** purchase/wallet chokepoints → outbox → Inngest tier routers → `process_tier_event` (see [`Tier.md`](./Tier.md)). DB triggers `trigger_tier_eval_on_purchase` / `queue_tier_evaluation` were removed.


#### Metric Contribution

Purchases contribute to tier metrics based on `tier_conditions.metric`:

**Sales Metric**:
- Aggregates `SUM(final_amount)` over evaluation window
- Handles credit/debit record_type appropriately
- Used for spend-based tier progression

**Orders Metric**:
- Counts `COUNT(*) WHERE final_amount > 0`
- Excludes refunds (debit records or negative amounts)
- Used for frequency-based tier progression

**Buyer vs Seller Evaluation**:
- Buyer tiers: `WHERE user_id = customer_id`
- Seller tiers: `WHERE seller_id = distributor_id`

### Mission Progress Integration

Purchase events can satisfy mission conditions when properly configured:

#### Condition Matching

Mission conditions with `condition_type = 'purchase'` evaluate against:
- **Product Filters**: product_ids, sku_ids, category_ids, brand_ids arrays
- **Store Filters**: store_attribute_set_id for location targeting
- **Amount Filters**: min_transaction_amount, max_transaction_amount ranges
- **User Perspective**: Inherits from mission.user_perspective (customer/seller)

#### Trigger Mechanisms

**Manual-Activation Missions**:
- Trigger `trigger_mission_evaluation_realtime()` fires immediately
- Evaluates accepted missions only (accepted_at IS NOT NULL)
- Real-time progress updates within milliseconds

**Auto-Activation Missions**:
- Trigger `queue_mission_evaluation_batch()` creates queue message
- Batch processor runs every 30 seconds
- Evaluates all auto missions with matching condition_type

**Progress Calculation**:
- `measurement_type = 'count'`: Each qualifying purchase adds +1
- `measurement_type = 'sum'`: Each qualifying purchase adds final_amount value

### Line Item Analysis Capabilities

The line items enable **SKU-level business logic** across multiple systems:

#### Product Hierarchy Resolution

Each line item links to complete product hierarchy:
- `sku_id` → `product_sku_master`
- `product_id` → `product_master`
- `category_id` + `brand_id` from product

**Enables**:
- Category-specific earn multipliers
- Brand loyalty campaigns  
- SKU-variant targeting
- Product exclusion rules

#### Earn Factor Evaluation

Currency calculation can apply **different rates to different line items**:

**Line-Specific Multipliers**:
- Shoes category: 3x multiplier on shoe line items only
- Beverages: 2x multiplier on beverage line items only
- Amount consumed by product multipliers removed from transaction-wide pool

**Transaction-Wide Multipliers**:
- Apply to total after line-specific deductions
- Birthday bonus, tier multipliers, weekend bonuses
- Apply to remainder amount

**No Double-Counting**: Amount isolation ensures each THB gets exactly one multiplier path

#### Mission Condition Filtering

Missions with product filters evaluate line items:
- `operator = 'OR'`: Purchase qualifies if ANY line item matches filter
- `operator = 'AND'`: Purchase qualifies if ALL filter items found across line items
- Partial transaction qualification possible

### Transaction Amount Calculations

**Calculation Flow**:
```
total_amount (sum of all line_total values)
  - discount_amount (transaction-level discounts)
  + tax_amount (transaction-level tax)
  = final_amount (net payable)
```

**Line Total Calculation**:
```
(quantity × unit_price)
  - line discount_amount
  + line tax_amount  
  = line_total
```

**Aggregation**: `total_amount` should equal sum of all line_total values before transaction-level adjustments

**Used For**:
- Currency calculation: Typically uses `final_amount`
- Tier metrics: Uses `final_amount` 
- Mission progress: Uses `final_amount` unless filtered by products
- Reporting: All amounts available for analysis

### Refund and Reversal Handling

The system implements **non-destructive refund processing**:

#### Full Refund Pattern

**Original Transaction** (credit):
- `transaction_number: "TXN001"`
- `record_type: 'credit'`
- `final_amount: 1500`
- `status: 'completed'`
- Currency awarded: 15 points

**Refund Transaction** (debit):
- `transaction_number: "TXN001-REF"` (new number)
- `record_type: 'debit'`
- `final_amount: 1500` (positive value)
- `status: 'refunded'`
- `external_ref: "TXN001"` (links to original)
- Currency reversal: -15 points

**Calculation Treatment**:
- Credit adds: +1500 to sales metric
- Debit subtracts: -1500 from sales metric
- Net sales: 0 (refund cancels original)

#### Partial Refund Pattern

**Original**: 1,500 THB purchase  
**Refund 1**: 500 THB partial refund (debit record)  
**Refund 2**: 300 THB additional refund (second debit record)  
**Net Sales**: 1,500 - 500 - 300 = 700 THB

**Currency Handling**:
- Original earned: 15 points
- Reversal 1: -5 points (proportional to 500/1500)
- Reversal 2: -3 points (proportional to 300/1500)
- Net currency: 7 points

#### Reversal Triggers

Purchase refunds trigger **automatic currency reversal**:
1. Debit record inserted with `record_type = 'debit'`
2. System identifies as refund scenario
3. Queries original transaction's `wallet_ledger` entries
4. Reads historical calculation from `metadata` JSONB
5. Calculates proportional reversal using original earn rates
6. Creates wallet_ledger entries with `component = 'reversal'`
7. Updates user balances (deducts currency)
8. Triggers tier re-evaluation

**Historical Data Usage**: Reversal uses original transaction's earn factors and multipliers stored in metadata, not current rates. This ensures fairness - if customer earned during 3x promotion, reversal is also 3x.

### Store Attribution and Location-Based Logic

The `store_id` field enables **location-aware business rules**:

#### Store Resolution

**Storage Format**: `purchase_ledger.store_id` is the store UUID; `purchase_ledger.store_code` is the optional human-readable code. Event payloads may send either.  
**Resolution**: Mission evaluate accepts UUID (`store_master.id`) first, then `event.store_code`, then legacy `store_master.store_code = event.store_id` (POS text codes).  
**Rationale**: Front Line / current ledger writes UUIDs; external POS still sends text codes.

#### Store Attribute Integration

Purchase evaluation resolves store classifications:
1. Event `store_id` (UUID or text code) and optional `store_code`
2. → `store_master` by `id` (UUID) or `store_code`
3. → `store_attribute_assignments` for classification
4. → `store_attribute_set_members` for set membership
5. → Returns array of attribute set UUIDs

**Earn Factor Conditions**: Can filter by `store_attribute_set_id`
- "2x points at premium stores"
- "3x points at airport locations"  
- "Bonus currency at flagship stores"

**Mission Conditions**: Can require purchases at specific store sets
- "Spend 2,000 THB at online marketplaces"
- "Make 5 purchases at physical stores"

### External System Integration

The purchase system provides **multiple integration points** for external platforms:

#### API Source Tracking

**transaction_source**: High-level channel classification
- `'online'`, `'in-store'`, `'mobile'`, `'kiosk'`, `'partner'`

**api_source**: Specific system identification
- `'POS'`, `'mobile_app'`, `'ecommerce'`, `'shopify'`, `'lazada'`, `'admin'`

**Purpose**: Attribution analysis, channel-specific reporting, debugging

#### External Reference Linking

**external_ref**: External system's transaction identifier
- Shopify order number
- POS receipt number
- E-commerce order ID
- Payment processor transaction ID

**Purpose**: Reconciliation, customer service lookups, refund correlation

#### Transaction Number Generation

**Format**: Merchant-controlled unique identifier  
**Pattern**: Often `TXN` + date + sequence (e.g., `TXN20241019000123`)  
**Usage**: Customer-facing reference, receipt printing, support tickets

**Generation**: Via sequence or function to ensure uniqueness within merchant

---

## Technical Implementation

### Architectural Overview

#### Event-Driven Purchase Processing Architecture

The purchase system employs a **multi-trigger event-driven architecture** where completed transactions cascade through currency, tier, and mission subsystems via independent trigger mechanisms.

##### Core Architectural Principles

**1. Immutable Transaction Layer**
- Purchases never modified after completion
- Refunds create new debit records
- Complete audit trail preserved
- Credit/debit pattern for reversals

**2. Multi-System Trigger Cascade**
- Single completion triggers multiple subsystems
- Independent trigger functions for each subsystem
- Queue-based decoupling prevents cascading failures
- Each subsystem processes asynchronously

**3. Dual-Table Granularity**
- Header-detail pattern for flexible analysis
- Transaction totals in purchase_ledger
- SKU-level detail in purchase_items_ledger
- Enables both aggregate and granular business logic

**4. Flexible Processing Routing**
- Queue method for high throughput
- Direct method for immediate gratification
- Skip method for special cases
- Configurable per transaction

**5. Single Write Chokepoint (Phase 1 of the event chokepoint migration — initial 2026-05-13, extended for items 2026-05-14)**

Every INSERT, UPDATE, or DELETE on `purchase_ledger` AND `purchase_items_ledger` is routed through one canonical writer: `chokepoint_post_purchase_event(p_event, p_merchant_id, p_payload jsonb)`. Direct table writes from BFFs, APIs, RPCs, edge functions, bulk imports, and admin tools are forbidden on both tables.

The chokepoint dispatches on `p_event`:

| `p_event` | Purpose | Key payload fields |
|---|---|---|
| `created` | Insert 1..N header rows + their items in one set-based pass (powers `api_create_purchase`, `api_create_manual_purchase_order`, `bulk_insert_purchases_with_items`, `claim_marketplace_order`, and the recursive debit insert inside `refunded`). Per-item completion fields (`status`, `quantity_completed`, `completed_at`, `completed_by_user_id`, `completed_by_source`) on each item entry override the row-level fallback when present (added 2026-05-14 for partial-pickup at order creation). | `rows: [{...header_fields, items: [{...sku_fields, quantity_completed?, status?, completed_*?}, ...]}, ...]` |
| `updated` | Generic single-row patch (powers both `api_update_purchase` overloads). Caller is responsible for whatever business gates it enforces on amount/item edits; the chokepoint stamps `completed_at` / `completed_by_source` whenever status transitions to `completed`. | `purchase_id`, `fields: {...}` |
| `completed` | Idempotent `pending → completed` transition for the seller self-service and rollup paths. Guarded to `status = 'pending'`. | `purchase_id`, `seller_user_id`, `completed_by_user_id`, `completed_by_source` |
| `cancelled` | `pending\|processing → cancelled`. | `purchase_id`, `reason` |
| `refunded` | Validate the original, recursively post a `record_type='debit'` row via `event='created'`, flip the parent to `'refunded'` only on a full refund. | `original_transaction_id`, `refund_amount`, `reason` |
| `promo_applied` | Apply the event-promo engine's discount delta + `reward_list` to an in-flight pending purchase. Also used by `fn_apply_manual_staff_discount` after event promos (`additional_discount` = staff baht). | `purchase_id`, `additional_discount`, `reward_list` |
| `items_added` | Append items to an existing parent. Used by `fn_apply_event_promos` to insert engine-granted freebies and tiered pool-pick items. | `purchase_id`, `items: [{sku_code, quantity, unit_price, line_total, item_type, ...}]` |
| `items_replaced` | DELETE all existing items + INSERT new set. Returns `items_deleted`, `items_created`, `new_total_amount`. Powers both `api_update_purchase` overloads; rejected when parent status is terminal. | `purchase_id`, `items: [...]` |
| `item_quantity_completed` | Increment `quantity_completed` on each listed item (caller-supplied delta), stamp `completed_at`/`completed_by_*` when `quantity_completed` reaches `quantity`, stamp parent `seller_id`, and if every item is now terminal recursively re-invoke the chokepoint with `event='completed'`. Powers `bff_seller_complete_purchase_items`. Replaces the deprecated `line_completed` event. Additive deltas only — `CONTINUE`s when item is already `completed`, rejects negative deltas. | `purchase_id`, `items: [{item_id, quantity_completed_delta}]`, `seller_user_id`, `completed_by_user_id`, `completed_by_source` |
| `item_completion_set` | **Absolute target value** with bounded reversal — set each listed item's `quantity_completed` to the supplied value (`0..quantity`). Reaching `quantity` flips item to `completed` and stamps `completed_at`/`completed_by_*`; dropping below `quantity` flips item back to `pending` and **clears** the `completed_*` columns. Rolls parent forward to `completed` only when all items terminal (never reverses parent). Rejects when parent is `completed` (`PARENT_COMPLETED_USE_REFUND`) or terminal (`PARENT_TERMINAL_STATE`). Added 2026-05-14 for admin operator overrides on event orders; powers `bff_admin_set_event_order_item_completion`. | `purchase_id`, `items: [{item_id, quantity_completed}]`, `completed_by_user_id`, `completed_by_source`, `completed_at` |
| `item_cancelled` | Flip listed items to `cancelled` (skips items already `cancelled` or `refunded`); does not roll up to the parent. | `purchase_id`, `items: [{item_id}]`, `cancelled_by_user_id`, `cancelled_by_source` |
| `item_refunded` | Flip listed items from `completed` to `refunded` (status-only mutation; money-side debit row is handled separately by the parent `refunded` event). | `purchase_id`, `items: [{item_id}]`, `refunded_by_source` |

Why one chokepoint instead of N: OutboxPublisher needs exactly one place to emit per logical event, and the dispatcher pattern lets `bulk_insert_purchases_with_items` send a whole chunk through a single chokepoint call (set-based, no per-row plpgsql loop). The data-integrity trigger `trg_purchase_complete_cascade_items` is preserved unchanged (it now coexists with `item_quantity_completed`-driven parent rollup; both paths converge through the chokepoint's recursive `completed` re-invocation). The dead function `trigger_process_purchase_currency` was dropped as part of the 2026-05-14 extension.

Event publish is live via outbox → Inngest; see `requirements/architecture/event-chokepoints.md`.

### Transaction Creation Flow

#### Primary Creation Path

**Step 1: Transaction Header Creation**
- Generate unique transaction_number
- Set merchant_id from context
- Resolve user_id from identifier (phone/email/user_id)
- Resolve store_id from store_code
- Calculate financial amounts
- Set initial status (typically 'pending' or 'completed')
- Set processing_method and earn_currency flags

**Step 2: Line Items Creation** (if provided)
- Insert items referencing transaction_id
- Link SKU_id for product hierarchy
- Set quantity, unit_price, line_total
- Items inherit merchant_id for isolation

**Step 3: Status Transition** (if not already completed)
- Update status to 'completed' when ready
- Triggers fire on status change
- Cascade begins across subsystems

**Step 4: Asynchronous Processing**
- Currency calculation queued or executed
- Tier evaluation queued
- Mission evaluation queued
- Each subsystem processes independently

### Trigger Architecture

#### Currency Award (Async via outbox → Inngest — no DB trigger)

**Trigger**: There is no longer a database trigger on `purchase_ledger` for currency awarding. The legacy `trigger_process_purchase_currency()` function was dropped on 2026-05-14.

**New pipeline (parent scope, `award_scope='purchase'`)**:
**Live currency path:** `chokepoint_post_purchase_event` → outbox → Inngest currency routers → `inngest-currency-serve` (see [`Currency.md`](./Currency.md)).
4. Consumer calls `calc_currency_for_source('purchase_item', item_id, …)` → `calc_currency_for_purchase_item(item_id)`, which filters to `earn_factor.award_scope = 'purchase_item' AND item.status = ANY(ef.allowed_item_statuses)` and uses `purchase_items_ledger.line_total` as the basis (whole-item — no pro-rata).
5. Multi-status dedup is one award per `(item_id, earn_factor_id)` enforced at the wallet writer via Redis.

`processing_method` on `purchase_ledger` is preserved as a hint for the Inngest workflow but is no longer routed by a database trigger.

#### Tier Evaluation Trigger

**Trigger**: After INSERT or UPDATE on `purchase_ledger`  
**Condition**: Status changes to `'completed'`  
### System Flow Diagrams

### Complete Purchase-to-Currency Flow



### Purchase Data Architecture

```mermaid
graph LR
    subgraph "Transaction Header"
        PL[purchase_ledger<br/>Transaction Totals<br/>Status & Payment<br/>User & Store Context]
    end
    
    subgraph "Transaction Details"
        PIL[purchase_items_ledger<br/>Line Items<br/>SKU × Quantity<br/>Prices & Totals]
    end
    
    subgraph "Product Hierarchy"
        SKU[product_sku_master<br/>Variants]
        PROD[product_master<br/>Products]
        CAT[product_category_master<br/>Categories]
        BRAND[product_brand_master<br/>Brands]
        
        SKU --> PROD
        PROD --> CAT
        PROD --> BRAND
    end
    
    subgraph "Store Context"
        SM[store_master<br/>Store Registry]
        SAA[store_attribute_assignments<br/>Classifications]
        SAS[store_attribute_sets<br/>Business Rule Groups]
    end
    
    subgraph "Integration Points"
        WL[wallet_ledger<br/>Currency Awards<br/>source_type = purchase]
        TE[tier_evaluation_queue<br/>Tier Changes]
        ME[mission_evaluation_queue<br/>Mission Progress]
    end
    
    PL --> PIL
    PIL --> SKU
    PL --> SM
    SM --> SAA
    SAA --> SAS
    
    PL -->|status = completed| WL
    PL -->|status = completed| TE
    PL -->|status = completed| ME
    
    style PL fill:#e3f2fd
    style PIL fill:#fff3e0
    style WL fill:#e8f5e9
    style TE fill:#f3e5f5
    style ME fill:#fce4ec
```

---

## Function Categories & Architecture

### 🎯 CORE FUNCTIONS (Business Logic Orchestrators)

#### `create_purchase_via_api(merchant_id, user_identifier, store_code, transaction_data, items)`
**Purpose**: Primary transaction creation function for external API integration  
**Category**: Core Business Logic Orchestrator  
**Returns**: JSONB with transaction details and processing status  
**Security**: SECURITY DEFINER with merchant validation

**Processing Flow**:
1. **User Resolution**: Calls `find_user_by_identifier()` to resolve user_id from phone/email/line_id
2. **Transaction Number Generation**: Creates unique identifier via sequence
3. **Header Creation**: Inserts purchase_ledger with all metadata
4. **Items Creation**: Loops through items array, inserts to purchase_items_ledger
5. **Trigger Cascade**: Database triggers fire automatically on completion
6. **Response**: Returns transaction_id and processing indicators

**Validation**:
- User must exist in merchant
- Store must exist (if provided)
- SKUs must exist for line items
- Amounts must be positive
- Transaction number uniqueness enforced

#### `find_user_by_identifier(merchant_id, identifier, identifier_type)`
**Purpose**: User lookup supporting multiple identifier types  
**Category**: Helper Function  
**Returns**: UUID of user or NULL if not found

**Supported Identifier Types**:
- `'phone'`: Matches phone, tel, or phone_number fields
- `'email'`: Matches email field
- `'line_id'`: Matches line_id field
- `'user_id'`: Direct UUID lookup
- `'cognito_sub'`: Cognito integration

**Used By**: API functions to resolve external identifiers to internal user_id

#### Seller Self-Service Functions (BFF)

End-user functions for sellers (users with `user_accounts.user_type = 'seller'`) to read and complete their assigned purchases without going through the admin panel. All three resolve the seller via `auth.uid()` against the user JWT and validate `user_type = 'seller'` before doing any work.

##### `bff_seller_get_purchase_by_transaction_number(p_transaction_number text) → jsonb`

**Purpose**: Read a purchase header + line items the calling seller is assigned to.
**Auth**: end-user JWT (no admin context needed).
**Lookup**: `(merchant_id, transaction_number, seller_id = auth.uid())`.
**Returns**: `{ purchase: {...}, items: [...] }` where each item includes its own `status`, `completed_*`, **`quantity`**, **`quantity_completed`**, and **`quantity_remaining = GREATEST(quantity - quantity_completed, 0)`**. Returns `AMBIGUOUS_TRANSACTION_NUMBER` if multiple rows match (legacy duplicate `transaction_number`).

##### `bff_seller_complete_purchase_by_transaction_number(p_transaction_number text) → jsonb`

**Purpose**: Flip the whole pending purchase to `completed` in one shot.
**Lookup**: `(merchant_id, transaction_number, seller_id = auth.uid(), status = 'pending')`.
**Effect**: Single UPDATE on the parent stamps `status = 'completed'`, `completed_by_user_id = caller`, `completed_by_source = 'seller_self_service'`, `completed_at = NOW()`. The cascade trigger handles all children atomically — every child is flipped to `'completed'` AND stamped with `quantity_completed = quantity`. No per-row work in this function.
**Errors**: `PURCHASE_NOT_FOUND`, `AMBIGUOUS_TRANSACTION_NUMBER`, `FORBIDDEN_NOT_SELLER`.

##### `bff_seller_complete_purchase_items(p_transaction_number text, p_line_items jsonb) → jsonb`

**Purpose**: Set the picked-up quantity on selected line items. Supports partial pickup — a line can sit at `0 < quantity_completed < quantity` indefinitely; status only flips to `'completed'` when `quantity_completed = quantity`.

**Input shape** (`p_line_items`):
```json
[
  { "line_item_id": "<uuid>", "quantity_completed": 80 },
  { "line_item_id": "<uuid>", "quantity_completed": 12 }
]
```
`quantity_completed` is the **new absolute total** for that line (not a delta). Idempotent on retry — submitting the same value twice is a no-op on the second call.

**Validation** (whole call rolled back on any failure):
- `INVALID_INPUT` — `p_line_items` not a non-empty array, missing fields, non-numeric `quantity_completed`, or a duplicate `line_item_id` in the same call.
- `INVALID_LINE_ITEMS` — any `line_item_id` does not belong to this purchase + merchant.
- `INVALID_QUANTITY` — `quantity_completed < 0`, `< current quantity_completed` (`MONOTONIC_VIOLATION`), `> quantity` (`QUANTITY_EXCEEDS_ORDER`), or the line is `cancelled` / `refunded` (`LINE_ITEM_LOCKED`). Violations returned in `data.violations[]`.
- `INVALID_TRANSITION` — parent status not in `('pending', 'processing')`.

**Effect**:
1. Rows are SELECT'd `FOR UPDATE` to prevent concurrent partial pickups racing on the same line.
2. One UPDATE applies the new `quantity_completed` per line. `status` flips to `'completed'` only when `quantity_completed = quantity`; otherwise the line stays `'pending'`.
3. `completed_by_user_id`, `completed_by_source = 'seller_line_item_completion'`, `completed_at = NOW()` are stamped only on the `pending → completed` transition.
4. `purchase_ledger.seller_id` is claimed (`COALESCE(seller_id, caller)`) when at least one line's `quantity_completed` actually changed.
5. Inline rollup via `fn_recompute_purchase_status` — parent flips to `'completed'` only if **every** child is now `'completed'` (i.e. fully picked up).

**Returns**:
```json
{
  "purchase_id": "<uuid>",
  "transaction_number": "...",
  "items": [
    { "line_item_id": "<uuid>", "ordered_quantity": 100, "quantity_completed": 80, "status": "pending" }
  ],
  "items_changed": 1,
  "items_unchanged": 0,
  "parent_completed": false,
  "parent_status": "pending"
}
```

### ⚙️ PROCESSING FUNCTIONS (Currency & Tier Integration)

#### Receipt approval seller earning (`bff_approve_receipt_upload`, action `approve`)

When the approved upload has a `seller_id`, the BFF creates the purchase via `api_create_purchase`, then loops `calc_currency_for_transaction(transaction_id, 'seller')` and posts each row **synchronously** via `chokepoint_post_wallet_transaction` with dedup key `seller_earn:<transaction_id>:<earn_factor_id>:<currency>:<component>[:<target_entity_id>]` (unique on `wallet_ledger.dedup_key` — retried approvals cannot double-credit).

**History (2026-07-07)**: previously called `enqueue_wallet_transaction` → `pgmq.send('wallet_queue', …)`. The `wallet_queue` PGMQ queue was never created and has no consumer (`process_wallet_queue` does not exist; `process_wallet_queue_batch` / `get_wallet_queue_status` are orphaned wrappers), so approve failed with `relation "pgmq.q_wallet_queue" does not exist`. Per the "C-sync first" decision in `.cursor/plans/purchase-line-item-earning.md`, the call site was switched to the synchronous chokepoint. The async wallet-queue worker remains unbuilt; `enqueue_wallet_transaction` now has no production caller.

#### `trigger_process_purchase_currency()`
**Purpose**: Routes completed purchases to currency calculation  
**Category**: Trigger Function  
**Execution**: AFTER INSERT OR UPDATE ON purchase_ledger

**Activation Condition**:
```
IF (status = 'completed' AND earn_currency = true) THEN
  CASE processing_method
    WHEN 'queue' THEN enqueue_wallet_transaction()
    WHEN 'direct' THEN chokepoint_post_wallet_transaction()
    WHEN 'skip' THEN NULL
  END
END IF
```

#### `trigger_mission_evaluation_realtime()` / `queue_mission_evaluation_batch()`
**Purpose**: Routes purchases to mission evaluation based on activation type  
**Category**: Trigger Functions  
**Execution**: AFTER INSERT OR UPDATE ON purchase_ledger

**Routing Logic**:
- Manual missions → Real-time evaluation
- Auto missions → Queue for batch processing

### 🔧 HELPER FUNCTIONS (Supporting Utilities)

#### `get_purchase_details(transaction_id, merchant_id)`
**Purpose**: Retrieve complete purchase with line items  
**Category**: Query Helper  
**Returns**: JSONB with transaction and items array

**Data Structure**:
```json
{
  "transaction": {
    "id": "uuid",
    "transaction_number": "TXN20241019001",
    "total_amount": 1500,
    "final_amount": 1350,
    "status": "completed"
  },
  "items": [
    {
      "sku_code": "COFFEE-L",
      "quantity": 2,
      "unit_price": 120,
      "line_total": 240
    }
  ],
  "currency_awarded": {
    "points": 13,
    "tickets": []
  }
}
```

#### `calculate_purchase_totals(items_array)`
**Purpose**: Calculate transaction totals from line items  
**Category**: Calculation Helper  
**Returns**: JSONB with total_amount, tax, discount calculations

**Used By**: API functions to validate incoming transaction data

---

## Status State Design & E-commerce Integration

### Simplified Status Model (Current Design)

**Decision**: Use single `status` field without separate fulfillment dimension

**Rationale**:
- Optimized for instant-fulfillment business models
- Reduces complexity of three-dimensional status tracking (order/payment/fulfillment)
- Clear trigger point for loyalty operations
- Suitable for fuel, retail, in-store, digital, and service transactions

**Status Field**: Combines transaction lifecycle and fulfillment into unified state
**Payment Status**: Separate field for financial settlement tracking
**Fulfillment**: Not tracked separately - assumed instant or included in `completed` status

### E-commerce Platform Integration

When integrating with platforms using multi-dimensional status (like Shopify):

**Shopify's Three Status Dimensions**:
- **Order Status**: Open / Archived / Canceled (workflow state)
- **Payment Status**: Pending / Authorized / Paid / Refunded (financial state)
- **Fulfillment Status**: Unfulfilled / Fulfilled (logistics state)

**These statuses are independent** - one changing doesn't automatically trigger others. They're coordinated through Shopify's business workflow logic.

**Mapping Strategy to Your CRM**:

**Trigger Point Decision** (Business Policy):

**Option A - Payment-Based** (Recommended for most):
- Shopify webhook: `payment_status = 'Paid'` → Set your `status = 'completed'`
- Awards currency when payment captured, regardless of shipping
- **Pros**: Immediate customer gratification, higher engagement
- **Cons**: May need reversals if order cancelled after payment
- **Best for**: Digital goods, low return rates, customer experience priority

**Option B - Fulfillment-Based** (Conservative):
- Shopify webhook: `payment_status = 'Paid' AND fulfillment_status = 'Fulfilled'` → Set your `status = 'completed'`
- Awards currency only when customer receives goods
- **Pros**: Fewer reversals, cleaner accounting
- **Cons**: Delayed gratification (days/weeks), lower engagement
- **Best for**: High return rate categories, long shipping times

**Option C - Hybrid**:
- Award partial currency on payment, remainder on fulfillment
- Award on payment but extend reversal grace period to match return policy

**Refund Handling**:
- Shopify webhook: `payment_status = 'Refunded'` → Create debit record with `status = 'refunded'`
- Triggers currency reversal automatically

**Coordination Note**: The integration logic in your webhook handlers coordinates Shopify's multi-status to your single status based on your business rules. Shopify's statuses don't automatically trigger each other - your code interprets their states to determine your status transitions.

### Future Extension: Fulfillment Tracking

If merchants require delivery tracking, consider:

**Option 1**: Add fulfillment columns to purchase_ledger
- Simple extension for basic tracking
- Fields: fulfillment_status, shipped_at, delivered_at, tracking_number

**Option 2**: Create purchase_fulfillment table
- Separate table for complex fulfillment workflows
- One-to-one with purchase_ledger
- Enables multiple shipments per order

**Option 3**: External fulfillment system
- Use `external_ref` to link to shipping platform
- Track delivery state externally
- Keep CRM focused on loyalty, not logistics

**Current Decision**: Not implemented - simplified model for transaction-based loyalty use cases

---

## Integration Patterns

### Currency System Integration

**Award Flow**:
1. Purchase completes → Currency calculation triggered
2. System calls `calc_currency_for_transaction(transaction_id)`
3. Evaluates earn factors against transaction and line items
4. Creates wallet_ledger entries with `source_type = 'purchase'`, `source_id = transaction_id`
5. Updates user balances (points and/or tickets)

**Reversal Flow**:
1. Refund debit record created → Reversal detection
2. System queries original wallet_ledger via source_id
3. Reads calculation metadata (rates, multipliers used)
4. Creates proportional reversal entries
5. Deducts from user balances

**Metadata Preservation**: Original calculation stored in wallet_ledger.metadata for accurate reversals when rates change

### Tier System Integration

**Metric Contribution**:
- Sales metric: `SUM(final_amount)` with credit/debit handling
- Orders metric: `COUNT(*) WHERE final_amount > 0`
- Both respect user_type (buyer uses user_id, seller uses seller_id)

**Evaluation Trigger**:
- Queue-based with 30-second deduplication
- Evaluates within time windows (rolling/fixed/anniversary)
- Can trigger upgrades or affect maintenance calculations

### Mission System Integration

**Progress Tracking**:
- Missions with purchase conditions evaluate on completion
- Product filters match against line items
- Amount filters check transaction final_amount
- Store filters check via store attribute sets

**Dual Processing Paths**:
- Manual missions: Real-time evaluation
- Auto missions: Batch evaluation every 30 seconds

---

## Performance Considerations

### Database Optimization

#### Indexing Strategy
- `idx_purchase_ledger_user_status`: User queries with status filter
- `idx_purchase_ledger_merchant_date`: Merchant reporting queries
- `idx_purchase_ledger_transaction_number`: Customer service lookups
- `idx_purchase_items_transaction`: Line item retrieval
- `idx_purchase_items_sku`: SKU-based analytics

#### Query Performance Targets
- Transaction creation: < 200ms (with line items)
- Status update: < 50ms (triggers cascade)
- Transaction retrieval: < 100ms (with items)
- Line item queries: < 50ms per transaction

### Scalability Patterns

#### Concurrent Transaction Handling
- Row-level locking on user balances
- Optimistic locking for inventory (if implemented)
- Transaction isolation level: Read Committed
- Queue-based processing absorbs spikes

#### High-Volume Scenarios
**Peak Load Handling** (e.g., flash sales, Black Friday):
- Queue processing: 1,000+ transactions/minute
- Batch currency calculation: 100 transactions per cycle
- Deduplication prevents trigger flooding
- Independent subsystem queues prevent cascading delays

**Scale Projections**:
| Transactions/Day | Peak TPS | Currency Queue | Tier Queue | Database Load |
|------------------|----------|----------------|------------|---------------|
| 10K | 50 | Light (30s lag) | Light | 5% CPU |
| 100K | 500 | Moderate (1min lag) | Moderate | 25% CPU |
| 1M | 5,000 | High (5min lag) | High | 60% CPU |

### Transaction Processing Modes

**Queue Method** (Default):
- Non-blocking transaction creation
- Currency appears within 1 minute
- Handles traffic spikes gracefully
- Retry logic for failures
- **Recommended for**: High-volume merchants, e-commerce, peak periods

**Direct Method**:
- Immediate currency calculation
- Real-time balance updates
- Slower transaction response
- No retry on currency failures
- **Recommended for**: VIP customers, low-volume scenarios, immediate gratification needs

**Skip Method**:
- No currency processing
- **Use for**: Test transactions, internal transfers, admin adjustments

---

## Data Integrity and Business Rules

### Core Principles

1. **Immutability**: Completed transactions never modified, only reversed via debit records
2. **Atomicity**: Transaction header and items created in single database transaction
3. **Dual Perspective**: Same transaction can be buyer's purchase and seller's sale
4. **Status-Driven Logic**: Business rules trigger on status transitions, not arbitrary events
5. **Complete Audit**: All amounts preserved, reversal records linked to originals

### Validation Rules

**Transaction Level**:
- `final_amount` must be positive for credit records
- `transaction_number` unique within merchant
- `user_id` must exist in user_accounts
- `merchant_id` must match user's merchant
- Status transitions follow defined state machine

**Line Item Level**:
- `sku_id` must exist in product_sku_master
- `quantity` must be positive
- `line_total` should equal calculated amount
- All line items must share transaction's merchant_id

**Refund Constraints**:
- Debit records must reference original transaction
- Refund amount cannot exceed original final_amount
- Record_type must be 'debit'
- Triggers currency reversal automatically

### Edge Cases and Handling

**Zero-Amount Transactions**:
- Allowed for free samples, promotional giveaways
- `final_amount = 0` earns 0 currency
- Still creates transaction record for tracking
- Can still trigger missions if conditions match

**Negative Amounts**:
- Not allowed in final_amount for credit records
- Refunds use positive amounts with record_type = 'debit'
- Calculation logic handles negation

**Mixed Credit/Debit Queries**:
- Sales metrics use CASE statement to negate debit records
- Orders metrics exclude debit records entirely
- Ensures accurate tier evaluation

**Concurrent User Transactions**:
- Multiple purchases can process simultaneously
- Queue deduplication prevents evaluation spam
- Each transaction independent until completion

**Missing Line Items**:
- Transaction can exist without items (valid for services)
- Currency calculation uses transaction final_amount
- Product-specific earn factors cannot apply

---

## Current Production Status

### System Health
- **Total Transactions**: 0 (system ready, awaiting production use)
- **Total Line Items**: 0 (infrastructure in place)
- **Trigger Status**: All triggers deployed and active
- **Integration**: Connected to currency, tier, and mission systems
- **Queue Status**: Empty (no pending processing)

### Schema Status
- **Tables**: ✅ Both purchase_ledger and purchase_items_ledger exist
- **Relationships**: ✅ Foreign keys properly configured
- **RLS**: ✅ Enabled on both tables
- **Triggers**: ✅ Currency, tier, and mission triggers active
- **Indexes**: ✅ Performance indexes in place

### Integration Validation
- **Currency Integration**: ✅ Trigger connects to wallet system
- **Tier Integration**: ✅ Trigger connects to tier queue
- **Mission Integration**: ✅ Dual triggers for manual/auto missions
- **Store Attribution**: ✅ Store attribute resolution functional

### API Readiness
- **RPC Functions**: Need to create `create_purchase_via_api()` function
- **User Resolution**: Need to create `find_user_by_identifier()` function
- **Validation Logic**: Need to implement amount calculations validation
- **Error Handling**: Need comprehensive error responses

The purchase transaction system demonstrates **production-ready infrastructure** with comprehensive event-driven integration, dual-table granularity for flexible analysis, and scalable processing architecture suitable for high-volume transaction processing across multiple channels and business models.

---

## Future Enhancements

### Planned Features

**Inventory Integration**:
- Real-time stock checking
- Automatic deduction on completion
- Oversell prevention
- Stock reservation during pending

**Payment Gateway Integration**:
- Direct payment processor connections
- Webhook handlers for payment events
- Automatic status updates from payment state
- Payment method tracking and analytics

**Delivery and Fulfillment**:
- Optional fulfillment_status field
- Shipping carrier integration
- Tracking number storage
- Delivery confirmation webhooks

**Advanced Refund Logic**:
- Partial refund by line item
- Restocking fees
- Refund approval workflows
- Customer-initiated returns

**Transaction Bundling**:
- Multi-transaction checkout
- Split payments
- Gift transactions
- Group purchases

### Extension Points

The system's architecture enables future enhancements:

**JSONB Flexibility**: Add metadata fields without schema changes  
**Trigger Framework**: Additional triggers for new subsystems  
**Status Extension**: Add new status states if needed  
**Queue Integration**: Additional processing queues for new features

---

## Admin Member 360 Purchase History RPC
**Status:** Deployed to Production  
**Implementation Date:** May 6, 2026  
**Migration:** `frontline_admin_be_rpcs`

`admin_get_user_purchases(p_user_id uuid, p_limit int default 10, p_offset int default 0, p_search text default null, p_sort text default 'date_desc')` returns the Member 360 purchase/receipt history envelope:

```json
{ "success": true, "data": { "items": [], "total": 0, "totals": { "bill_count": 0, "points": 0, "amount": 0 } } }
```

Rows include purchase id, transaction number/date, store id/name/code/channel label, amount, item count, awarded points/tickets, payment method, status, batch id, and image URLs. Store property labels are joined once per distinct store via `fn_store_property_labels` (not per history row). Auth is admin-only: caller must resolve a merchant via `get_current_merchant_id()` and have an active `admin_users` row for that merchant; `p_user_id` must belong to the same merchant.

`bff_admin_search_members(p_query, p_limit, p_store_id)` identifier path (digits, min 2: phone / 8-digit `member_code` / normalized id card) uses btree equality+prefix. Compact strip is POSIX `[[:space:]+-]` (hyphen last). Phone prefix folds `0` / `+66` / `66`. Name path (min 3) is one `fn_member_search_text(...) ILIKE`. Does not `ILIKE ANY` three patterns. Hits are ranked and limited **before** joining tier/persona/wallet. Does not return the raw `id_card` value. Optional `p_store_id` keeps the purchase/redemption store filter.

`bff_admin_create_member(...)` creates members through a SECURITY DEFINER admin BFF. Overload with `p_profile jsonb`, `p_language`, `p_image` applies extra profile fields and avatar in the same write. It resolves merchant via `get_current_merchant_id()`, requires an active `admin_users` row for the caller, checks duplicate phone/email/external user ID/member code/LINE ID within the merchant, and returns `{ success, data: { user_id } }`. Frontends should use this RPC instead of direct `user_accounts` inserts.

`bff_admin_get_frontline_member(p_user_id, p_language)` is the Front Line booth header (not Customer 360). Returns profile, notes, `points_balance`, `fn_wallet_today_stats`, tier progress plus `tier_pending_upgrades` overlay, and `profile_incomplete`. No store credit.

`bff_admin_create_frontline_receipt_batch(p_user_id, p_batch_id, p_admin_user_id, p_receipts jsonb)` set-based queued Front Line insert (`status=approved`, `approved_method=frontline`, `crm_sync_status=queued`). Duplicate ledger/upload rows are skipped. Duplicate / `fn_preview_purchase_limits` stay as FE pre-checks.

`bff_get_frontline_reward_catalog(p_language, p_user_id)` optional `p_user_id` prices + eligibility-flags in one set-based pass. `admin_redeem_and_use` embeds `lucky_draw_slip` and `fn_wallet_today_stats`.

---

*Document Version: 1.0*  
*Last Updated: October 2024*  
*System: Supabase CRM - Purchase Transaction System*

