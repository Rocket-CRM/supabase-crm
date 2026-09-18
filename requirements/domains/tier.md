# Tier

> Per-domain reference. Read ONLY when working on this domain. For the keyword → file map, see `_index.md`.

**Keywords:** tier, level, upgrade, downgrade, maintain, tier progress, tier conditions, ranking, entry tier, burn rate, point-to-discount, tier lock, window type, calendar month, calendar quarter, rolling, fixed period, anniversary, persona tier

**Source:** `Tier.md`

**FE-Relevant Sections:**

| Section Heading | Lines | What it contains |
|---|---|---|
| Core Tables and Structure | 39–174 | `tier_master`, `tier_persona_assignments`, `tier_conditions`, `tier_progress`, `user_accounts` field definitions — use for TypeScript types |
| Burn Rate - Direct Point-to-Discount Conversion | 595–674 | How burn rate works at checkout, configuration per tier, `get_user_burn_rate()` response shape |
| Business Logic and Concepts | 175–598 | Window types (5 kinds), frequency options, upgrade/downgrade rules, persona-based segmentation, progress tracking |
| Key Concepts Glossary | 1016–1045 | Quick definitions: earn, burn, reversal, window types, frequencies, record types |
| Ranking System | 498–504 | How tier conflicts resolve (highest wins, non-adjacent skip allowed) |
| Tier Locking | 582–589 | `tier_lock_downgrade` and `tier_locked_downgrade_until` behaviour |

**Supabase Functions (FE-callable):**

| Function | Parameters | Returns | Lines |
|---|---|---|---|
| `get_user_burn_rate()` | None (merchant + user from JWT) | JSON: `effective_rate`, `base_rate`, `multiplier`, `is_enabled`, `tier_name`, `available_points`, `max_discount`, `factors[]` | 621–674 |
| `bff_upsert_tier_with_conditions(tier_data jsonb)` | `tier_data` with `id`/`tier_id`, `tier_name`, `user_type`, `persona_ids[]`, `ranking`, `entry_tier`, `icon`, `color`, `burn_rate`, `upgrade[]`, `maintain[]` | Standard envelope `{success, code, title, description, data:{tier_id, operation, persona_ids, personas, burn_rate, stats}}` | — |
| `get_tier_conditions_by_type(p_mode text, p_tier_id uuid)` | `p_mode='new'\|'edit'`, `p_tier_id` required for edit | JSON: `mode`, `tier_id`, `tier_name`, `user_type`, `persona_id`, `persona_ids[]`, `personas`, `ranking`, `entry_tier`, `created_at`, `upgrade[]`, `maintain[]` (returns ALL rows incl. `active_status: false`) | — |
| `get_merchant_tiers(p_merchant_id uuid)` | `p_merchant_id` (must match caller's merchant) | TABLE per tier with `conditions` jsonb_agg of active conditions only | — |
| `reorder_tiers(p_merchant_id uuid, p_tier_ids jsonb)` | `p_merchant_id` (must match caller's merchant), `p_tier_ids` ordered uuid array | JSON `{success, updated_count, message, invalid_tier_ids?}` | — |
| `set_entry_tier(p_tier_id uuid)` | tier id | JSON `{success, tier_id, tier_name, user_type, persona_id, persona_ids, personas, message}` | — |
| `admin_delete_tier(p_tier_id uuid)` | tier id | Standard envelope; rejects with friendly message when users still on tier | — |
| `bff_upsert_tier_display(p_tier_id uuid, p_display jsonb)` | display fields: `icon`, `color`, `benefits`, `card_design` | Standard envelope | — |

### Tier Conditions Round-Trip Contract

The `tier_conditions` table has no soft-delete — row existence is the source of truth.

- `get_tier_conditions_by_type` returns ALL conditions for the tier including `active_status = false`. The FE must round-trip every row (with its `id` and `active_status`) in the next `bff_upsert_tier_with_conditions` call. Any row whose `id` is missing from `tier_data.upgrade[]` or `tier_data.maintain[]` is **hard-deleted** by the upsert. The FE may visually hide inactive rows but must keep them in the form's data model.
- `upgrade_evaluation_timing` and `upgrade_evaluation_value` (both `text`) are **upgrade-branch only**. They live on `tier_conditions` (column names start with `upgrade_`), are written only by the upgrade INSERT/UPDATE in `bff_upsert_tier_with_conditions`, returned only on upgrade rows by `get_tier_conditions_by_type` and `get_merchant_tiers`, and read only by `evaluate_user_tier_status` in the upgrade evaluation path. Do not send them on maintain rows.
- The upsert uses "key present" semantics on UPDATE for `frequency`, `window_start_field`, `upgrade_evaluation_timing`, `upgrade_evaluation_value`: omit the key to preserve the existing value, send the key with `null` or empty string to clear it. Other fields (`metric`, `amount`, `window_type`, `window_months`, `window_start`, `active_status`) use COALESCE — empty/null preserves existing.
- Empty array `tier_data.upgrade: []` (or `maintain: []`) is treated as "delete all conditions of that type". To leave conditions untouched, omit the key entirely from `tier_data`.
- `reorder_tiers` and `get_merchant_tiers` accept a `p_merchant_id` parameter for backwards compat but enforce that it matches `get_current_merchant_id()` when a caller merchant is present. Service-role/cron callers (where `get_current_merchant_id()` returns NULL) are still allowed to pass any merchant.

### Tier Ranking Contract (2026-05-28)

- **Distinct rankings required** per merchant. Duplicate values break upgrade evaluation.
- **`get_tier_conditions_by_type('new')`** returns `ranking = COALESCE(MAX(ranking), -1) + 1` as the suggested next slot.
- **`bff_upsert_tier_with_conditions` create**: omit `ranking` → auto-append; explicit `ranking` → insert-at-slot (`UPDATE … SET ranking = ranking + 1 WHERE ranking >= target`, then insert at target).
- **`bff_upsert_tier_with_conditions` update**: `ranking` key present and changed → shift peers then save (moving to lower number bumps `[new, old)`; moving to higher number decrements `(old, new]`).
- **Response** includes `data.ranking` after save.
- **`reorder_tiers`** remains the bulk list-reorder path (assigns `1..N` in UUID array order); upsert slot logic is separate.
- FE may expose a ranking input **or** omit `ranking` and let the backend auto-append; if FE sends an explicit slot, backend handles peer shifts on save.

**Key Business Rules (summary):**
- Users can skip tiers (non-adjacent progression) if they qualify for higher ones
- Multiple upgrade paths per tier (points OR sales OR orders)
- Progress tracking shows the best path automatically (highest `progress_percent`)
- `burn_rate` on `tier_master` converts points to monetary discount (NULL = disabled)
- Tier evaluation considers `user_type` (buyer/seller) and optional `tier_persona_assignments`; no assignment rows means all personas
- Downgrade happens when maintain conditions fail; user drops to highest qualifying lower tier or entry tier
- `tier_change_ledger` rows publish through CDC unless `skip_cdc = true`; AMP lifecycle automations can trigger on `change_type = upgrade` or `change_type = downgrade`; RLS allows admins to modify ledger rows and members to read their own rows
- `tier_master` delete paths require leading indexes on all referencing FK columns, including global `user_accounts.tier_id` and chained ledger references such as `tier_change_ledger.triggered_by_condition_id`, to avoid statement timeouts during restrict/cascade checks

---
