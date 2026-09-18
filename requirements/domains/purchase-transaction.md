# Purchase Transaction

> Per-domain reference. Read ONLY when working on this domain. For the keyword → file map, see `_index.md`.

**Keywords:** purchase, transaction, order, payment, refund, credit, debit, line item, SKU, purchase ledger, purchase items, final amount, status, completed, processing method, store, seller, wallet ledger code, POS discount

**Source:** `Purchase_Transaction.md` (Concept → Rules → Journeys → System spine)

**FE-Relevant Sections:**

| Section | What it contains |
|---|---|
| `## Rules` — header status, record type, line pickup | State machine, debit pattern, `quantity_completed` |
| `## Rules` — earn and side effects | Completed gate, `processing_method`, event emission |
| `## Journeys` — Admin / Member maps | Page → BFF/RPC for reports, cancel, seller, claims |
| `## System` — Data model | `purchase_ledger` / `purchase_items_ledger` columns and roles |

**Supabase Functions (FE-callable):**

| Function | Role |
|---|---|
| `api_create_purchase` | Partner/create path (delegates to chokepoint) |
| `api_get_purchase` | Read by id or transaction number |
| `api_create_manual_purchase_order` | Front-line / event manual basket |
| `bff_seller_get_purchase_by_transaction_number` | Seller load |
| `bff_seller_complete_purchase_items` | Line pickup (`item_quantity_completed` via chokepoint) |
| `bff_seller_complete_purchase_by_transaction_number` | Whole-order complete |
| `bff_get_purchase_history` | Member history drawer |
| `claim_marketplace_order` | Member marketplace claim |

**Internal / platform:**

| Function | Purpose |
|---|---|
| `chokepoint_post_purchase_event` | Sole writer for purchase headers and lines |
| `fn_recompute_purchase_status` | Child → parent status rollup |
| `fn_claim_marketplace_order_service` | Claim → `api_create_purchase` + MKP sync |
| `trigger_cascade_purchase_complete_to_items` | Parent completed → children |

**Key business rules (summary):**
- `status = 'completed'` (with `earn_currency`) drives `crm.events.purchase*` emission; currency/tier/mission consume events (no legacy purchase_ledger earn triggers).
- Refunds use debit `record_type` rows; originals stay immutable.
- `processing_method`: `queue` (default), `direct`, `skip`.
- Buyer `user_id` vs seller `seller_id`; POS discount via `wallet_ledger_code`.
- Completion stamping on every transition to `completed`.
- Marketplace: claim promotes `order_ledger_mkp` → purchase pair (`Marketplace.md`).

---
