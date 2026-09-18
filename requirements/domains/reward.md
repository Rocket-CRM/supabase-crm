# Reward Domain

## Tables

### `reward_master`
- Primary reward configuration.
- Existing stock fields: `stock_control`, `stock_total`.
- `stock_control = true` enables stock validation.
- Existing global stock behavior remains unchanged for rewards without store stock rows.

### `reward_stock_store`
- Store-level reward stock allocation.
- Columns: `id`, `merchant_id`, `reward_id`, `store_id`, `stock_total`, `created_at`, `updated_at`.
- Unique key: `(merchant_id, reward_id, store_id)`.
- `stock_total` must be `>= 0`.
- No `active_status`, `used`, `reserved`, or `redeemed` counters. Used quantity is derived from `reward_redemptions_ledger`.
- RLS: `merchant_id = get_current_merchant_id()`.

### `reward_redemptions_ledger`
- Source of truth for reward redemption and claim/use events.
- `delivery_address` (jsonb, 2026-07-12): immutable member-address snapshot stamped by `redeem_reward_with_points` when `fulfillment_method='shipping'` (with `fulfillment_status='pending'`). See `requirements/Reward.md` §Shipping Fulfillment & Delivery Address.
- Store stock consumption is derived from rows where:
  - `used_status = true`
  - `cancelled IS NOT TRUE`
  - `reward_id` matches
  - `COALESCE(used_store_id, redeemed_store_id)` matches `reward_stock_store.store_id`
- Availability formula:
  - `available_stock = reward_stock_store.stock_total - SUM(COALESCE(reward_redemptions_ledger.qty, 1))`

## Functions

### `fn_invalidate_merchant_rewards_cache(p_merchant_id uuid)`
- Invalidates reward catalog cache keys through one best-effort Upstash pipeline request.
- Reward cache invalidation is de-duplicated per merchant per transaction by `trigger_invalidate_rewards_cache_on_reward_change`.
- Cache invalidation must not block admin writes; HTTP cache failures/timeouts are swallowed and catalog cache expires by TTL.

### `fn_get_reward_store_stock(p_reward_id uuid, p_merchant_id uuid default null)`
- Returns store stock rows with `store_code`, `store_name`, `stock_total`, `used_qty`, and `available_stock`.
- Uses `get_current_merchant_id()` when `p_merchant_id` is not provided.

### `fn_check_reward_store_stock_on_use(p_redemption_id uuid, p_store_id uuid default null)`
- Validates whether a redemption can be marked used for a store.
- Allows the operation when:
  - no store context exists,
  - reward stock control is off,
  - no store stock rows are configured for the reward.
- Blocks the operation when store stock rows exist and the selected store is unallocated or does not have enough available stock.

### `bff_get_reward_store_stock(p_reward_id uuid)`
- Admin helper for loading store stock allocations for a reward.

### `bff_upsert_reward_store_stock(p_reward_id uuid, p_store_stock jsonb default '[]'::jsonb)`
- Admin helper for replacing store stock allocations for a reward.
- Payload rows require `store_id` and `stock_total`.
- Deletes omitted store rows for the reward.

## Business Rules

- Store stock is consumed at use/claim time, not at redeem time.
- Stock is not deducted by updating counters; successful claim/use rows in `reward_redemptions_ledger` determine consumption.
- Existing reward redemption flows remain backward compatible:
  - rewards without `reward_stock_store` rows use existing behavior,
  - existing function signatures are unchanged,
  - `redeem_reward_with_points` continues to write `redeemed_store_id` when `p_store_id` is provided.
- Claim/use enforcement runs through the `validate_reward_store_stock_on_use` trigger on `reward_redemptions_ledger`.
- Reward catalog cache invalidation is best-effort and batched; reward writes must not depend on synchronous per-key Redis deletes.
# Reward

> Per-domain reference. Read ONLY when working on this domain. For the keyword → file map, see `_index.md`.

**Keywords:** reward, redeem, redemption, voucher, coupon, promo code, points required, fulfillment, eligibility, stock, reward catalog, dynamic points, multi-quantity, used status, redeemed status, online store, Shopify discount, reward_group, group limit, shared limit, cross-reward limit, is_featured, groups map, group usage, redeemed_reward_ids, frontline, redemption_usage_log, admin_user_id

**Source:** `Reward.md`

**FE-Relevant Sections:**

| Section Heading | Lines | What it contains |
|---|---|---|
| Core Concepts & Glossary | 30–113 | Visibility types, fulfillment methods, expiration modes, redemption states, points matching concepts |
| Database Schema — reward_master | 464–518 | Full column list for reward definition — use for TypeScript types |
| Database Schema — reward_points_conditions | 520–549 | Dynamic pricing condition structure |
| Database Schema — reward_redemptions_ledger | 551–584 | Redemption record shape |
| Dynamic Points Calculation | 882–1014 | Multi-dimensional matching algorithm (tier × type × persona × tags), specificity scoring |
| Redemption Process Flow | 1018–1114 | Complete sequence diagram of a redemption |
| Multi-Quantity Redemption | 1116–1260 | Patterns A/B/C for qty handling, promo code reservation, API format |
| Cached Rewards API | 774–879 | `api_get_rewards_full_cached()` response shape with translations, stock, promo codes, groups map |
| API Integration — REST | 1583–1710 | Redeem, preview points, get history, Realtime subscription for async results |
| Shopify Discount Product Lookup | 2356–2446 | `shopify_discount_detail` response shape for rewards linked to Shopify price rules |
| Error Codes | 2058–2079 | RWD001–RWD017 error code table |
| Persona-Aware Field Filtering | 1373–1415 | How eligibility filters fields by user persona |

**Supabase Functions (FE-callable):**

| Function | Parameters | Returns |
|---|---|---|
| `api_get_rewards_full_cached(p_language?, p_persona_id?)` | optional language + persona filter | `{ data[], categories[], groups{}, cache_hit, ... }` |
| `api_get_my_reward_group_usage()` | none (user from JWT) | `[{ group_id, group_name, is_featured, limits[], redeemed_reward_ids[] }]` |
| `calculate_redemption_points(user_id, reward_id)` | `user_id uuid`, `reward_id uuid` | Points required, matched condition, calculation details |
| `check_reward_eligibility_enhanced(user_id, reward_id)` | `user_id uuid`, `reward_id uuid` | Eligibility status, rejection reasons, available quantity |
| `redeem_reward_with_points(user_id, reward_id, qty)` | `user_id uuid`, `reward_id uuid`, `qty numeric` | Redemption IDs, promo codes, points deducted, expiry |
| `admin_get_user_redemptions(p_user_id, p_merchant_id, p_filter?, p_limit?, p_offset?, p_search?, p_date_from?, p_date_to?)` | Admin JWT + merchant match | User redemption rows; filters: `my_reward` (unused redeemed), `used` (used_status=true, not cancelled), `history`, `all` (non-cancelled); optional search/date filters, store/channel/by metadata |
| `admin_mark_redemptions_used(p_redemption_ids, p_user_id, p_merchant_id, p_notes?, p_store_id?, p_language?)` | Bulk admin mark-used | `{ used_at, succeeded[], failed[] }`; partial success allowed |
| `admin_unmark_redemption_used(p_merchant_id, p_redemption_id?, p_redemption_code?, p_reason?, p_store_id?)` | Admin-only revive (Mode A reversal) | `{ redemption_id, status:'redeemed', reverted_at, previous_used_at, previous_used_store_id }`; flips a used redemption back to redeemed-but-not-used; points stay deducted, promo code stays issued; rejects `cancelled` / `not_used` / multi-use entitlements; logs `redemption_usage_log.action='reverse_use'` with `source_type='admin_unmark_used'` |
| `bff_admin_get_reward_redemption_history(p_user_id, p_store_id?, p_minutes?)` | Front Line redemption history (read or update on `frontline_redemption_reward`) | `{ items[], minutes, store_id, generated_at }`. Returns up to 50 successful, non-cancelled redemptions for the customer, ordered by `COALESCE(used_at, redeemed_at, created_at) DESC`, anchored within `p_minutes` (clamped 1..1440, default 60). Each item includes reward name/image, store ids+names, points/promo, status (`used`/`redeemed`), and `can_unmark_used`. Used by FE Redemption Reward flow to power reverse/unmark actions. |
| `api_cancel_redemption(p_merchant_id, p_redemption_id?, p_redemption_code?, p_reason?, p_cancelled_by?, p_force_used?)` | Cancel/reverse redemption | Refunds points (writes `wallet_transaction_source_type='redemption_cancellation'`), returns promo code to pool, sets `cancelled=true`. Default `p_force_used=false` returns `REWARD_ALREADY_USED` for used redemptions; pass `p_force_used=true` to reverse a used redemption (Mode B): unmarks used first then cancels, logs `reverse_use` with `source_type='cancel_force_used'`. Idempotent on already-cancelled. Multi-use entitlements not in scope. |
| `api_get_redemption(p_merchant_id, p_redemption_id?, p_redemption_code?, p_store_id?)` | API redemption lookup | Redemption JSON includes store names and redeemed/used-by display names |
| `bff-mark-redemption-used` | Edge Function: `redemption_id` | Marks used + optional Shopify product enrichment |
| `bff-get-redemption-detail` | Edge Function: `redemption_id` | Redemption detail + optional Shopify product enrichment |

**`api_get_rewards_full_cached` — top-level `groups` map (added Apr 2026):**
Each reward row already carries `reward_group_ids: uuid[]`. The `groups` map lets the FE resolve name, featured flag, and limits without a second round-trip. Only active groups with at least one visible member reward are included.
```json
"groups": {
  "<group_uuid>": {
    "id": "<group_uuid>",
    "name": "Cinema Tickets",
    "is_featured": true,
    "limits": [
      { "metric": "distinct_reward", "count": 1, "scope": "user", "time_unit": "all_time" }
    ]
  }
}
```

**`api_get_my_reward_group_usage` — response shape (restructured Apr 2026):**
One element per group that has an active `distinct_reward` limit. `redeemed_reward_ids` lists which reward IDs the user already holds in-window — FE uses this to distinguish "Chosen ✓" (re-redeem allowed) from "Locked" (group full, new type blocked). Uses same window logic as `fn_check_reward_group_limits`.
```json
[
  {
    "group_id": "uuid",
    "group_name": "Cinema Tickets",
    "is_featured": true,
    "limits": [
      { "metric": "distinct_reward", "count": 2, "time_unit": "all_time", "current_usage": 1, "remaining": 1 }
    ],
    "redeemed_reward_ids": ["uuid-zone-a"]
  }
]
```

**Key Business Rules (summary):**
- Two-layer architecture: eligibility (WHO) then points pricing (HOW MANY)
- Dynamic points via 4-dimension matching: tier, user_type, persona, tags — most specific match wins
- Redemption is async: FE gets `event_id` immediately, listens to Realtime for result
- Multi-quantity with promo codes creates N separate ledger records; without promo codes creates 1 record with qty=N
- All-or-nothing: if insufficient promo codes, entire transaction fails
- Frontline/admin actions carry store and actor audit fields. Redeem with `p_store_id` or `p_source_type='admin_frontline'` writes `redemption_usage_log.action='redeem'`; mark-used writes `action='use'`; lookup with `p_store_id` writes `action='lookup'`; reversal (either Mode A unmark or Mode B force-cancel) writes `action='reverse_use'` with `qty_change` set negative. Store IDs are validated against the merchant. Staff actors are stored in `redemption_usage_log.admin_user_id` and `performed_by=auth.uid()::text`; enrichment prefers the redeem actor over lookup-only history and resolves names from `admin_users` first, then `user_accounts`.
- **Reversal modes**: Mode A (`admin_unmark_redemption_used`) returns a used redemption to the redeemed state without refunding points or returning the promo code — for "scanner glitch / wrong scan" recovery. Mode B (`api_cancel_redemption` with `p_force_used=true`) does Mode A first then refunds points and returns the promo code — for "admin redeemed wrong reward, give the customer their points back". Stock and group-limit usage restore automatically because availability is derived from `used_status=true AND cancelled IS NOT TRUE`.
- `online_store[]` is a free-text array for marketplace distribution (e.g., `shopify`, `lazada`)
- **Reward Groups**: `reward_group` table groups rewards for shared limits. Limits in `transaction_limits` with `entity_type='reward_group'`. A reward can belong to multiple groups via `reward_master.reward_group_ids UUID[]`. Group limits enforced at redemption time via `fn_check_reward_group_limits`.
- **`reward_group.is_featured`** (added Apr 2026): boolean, default false. Controls whether the group gets carousel/featured treatment in the FE gallery. Exposed via all three BFF admin functions and both user-facing APIs.
- **`reward_master.is_featured`**: boolean, default false. Admin Reward List pin writes this via `bff_set_reward_featured`. Member catalog (`api_get_rewards_full_cached`) returns it; featured public rewards appear first as Special Reward. `bff_list_rewards` returns the flag and sorts pinned first.

## Curated knowledge (internal MCP)

- **Reward sourcing & partner fulfillment** (positioning + operating model, not schema): `requirements/feature-docs/reward-sourcing-services.md` — feeds `internal_knowledge` blocks for slug `reward-sourcing-services` when `scripts/generate_internal_knowledge_seed.py` is run and `generated/internal-knowledge/load.sql` is applied.

---
