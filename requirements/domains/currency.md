# Currency

> Per-domain reference. Read ONLY when working on this domain. For the keyword → file map, see `_index.md`.

**Keywords:** points, tickets, balance, earn, burn, wallet, earn factor, multiplier, rate, expiry, TTL, fixed frequency, reversal, refund, wallet ledger, source type, ticket type, credit ticket, deductible balance, wallet code, POS discount

**Source:** `Currency.md`

**FE-Relevant Sections:**

| Section Heading | Lines | What it contains |
|---|---|---|
| Glossary of Terms | 38–143 | Core concepts: currency types, earn factors, components, transaction types, signed amount, ticket types, source types, expiry modes |
| Public Earning Rules vs Personalized Offers | 181–211 | How public vs private earn factors work for the user |
| Tier Integration and Benefits | 212–288 | Tier is one of many attributes — not the primary earn rate driver |
| Currency Expiry Management | 289–420 | TTL, fixed frequency, absolute date modes; minimum period protection; customer communication data |
| Ticket Type Architecture | 1207–1293 | Non-fungible ticket types, credit tickets for external platform credits, `target_entity_id` usage |
| API — Calculate Currency (Preview) | 2085–2153 | Response shape for currency preview (base, final, breakdown, tickets) |
| API — Award Currency | 2155–2192 | Response shape after award (balance_after, tickets, queue status) |
| API — Check Currency Status | 2194–2211 | Poll transaction processing status |
| API — Get Upcoming Expiries | 2230–2265 | Upcoming expiry data for customer notifications |
| Business Rules Summary | 1728–1800 | Core principles, earn/burn rules, reversal logic, edge cases |
| Implementation Examples | 1806–2080 | 12 worked examples covering standard, tiered, multi-product, refund, expiry, UOM scenarios |

**Supabase Functions (FE-callable):**

| Function | Parameters | Returns | Lines |
|---|---|---|---|
| `chokepoint_post_wallet_transaction(...)` | `p_user_id`, `p_merchant_id`, `p_currency`, `p_transaction_type`, `p_component`, `p_amount`, `p_source_type`, `p_source_id`, etc. | Wallet ledger entry with balance_before/after | 594 |
| `bff_preview_point_discount_burn(...)` | `p_user_id`, `p_points_amount` | Calculates available points, tier burn rate, and discount amount without deducting points |
| `bff_create_point_discount_burn(...)` | `p_user_id`, `p_points_amount`, optional `p_store_id`, `p_description`, `p_metadata` | Burns points, stores `wallet_ledger.code` + `discount_amount`, returns POS code |
| `bff_reverse_point_discount_burn(...)` | `p_wallet_ledger_id` or `p_code`, optional `p_reason`, `p_metadata` | Returns points through an earn/reversal row unless code is attached to an active purchase |
| `bff_admin_get_point_discount_burn_history(...)` | `p_user_id`, optional `p_store_id`, `p_minutes` | Returns recent POS point-discount burn rows and reversal/use status |
| `bff_admin_get_member_wallet_history(...)` | `p_user_id`, `p_filter` (`all`\|`points`\|`ticket`), `p_limit`, `p_offset` | Customer 360 paginated `wallet_ledger` TABLE (+ `total_count`); requires `customer-360.read` |

**Key Business Rules (summary):**
- Points are fungible; tickets are non-fungible (each type has independent balance via `target_entity_id`)
- Earn factors: rate (conversion) and multiplier (bonus); can be public or personalized per user
- `signed_amount`: positive for earn, negative for burn/reversal; `amount` always positive
- Reversals use original calculation metadata (historical rates, not current) for fairness
- Expiry processes daily at 2 AM; creates `burn` entries with `component='expiry'`
- Components: `base`, `bonus`, `adjustment`, `reversal`
- Source types: `purchase`, `referral`, `mission`, `campaign`, `manual`, `activity`, `reward_redemption`
- Staff POS point-discount burns store a human-facing `wallet_ledger.code` and the calculated cash `discount_amount` on the burn row. POS orders copy that code into `purchase_ledger.wallet_ledger_code` for reconciliation.
- Wrong staff point-discount burns are reversed by creating a new wallet earn row with `component='reversal'` and `reference_id` pointing to the original burn; the original burn is not deleted.
- Point-discount BFFs allow broad currency admins via `currency` permissions and frontline admins via scoped `frontline_burn_points_discount` permissions. History accepts `read` or `update`; preview, create, and reverse require `update`.

---
