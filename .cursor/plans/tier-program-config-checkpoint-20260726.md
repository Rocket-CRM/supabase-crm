# Tier Program Config — checkpoint 2026-07-26

Source plan: `.cursor/plans/tier-program-config-plan.md`

## Task

Migrate tier configuration from "every tier defines its own clock" to "the program owns the
clock, each tier owns only a threshold." Phases 1–5 of the plan.

## Status — code and schema complete and smoke-tested

Phases 1 through 5 are applied to `wkevmsedchftztoolkmi`. Only the §11 documentation sweep
is left.

### Schema

- `tier_program_config` created and backfilled: **49 rows**, one per `(merchant_id, user_type)`
  group that has active tier conditions. Zero groups missing config. Split is 30 `rolling`,
  19 `calendar_year`. Dulux and Munasoul were forced to `rolling 12` per the plan;
  TANGPORADO's `window_months = 0` is clamped into the legal 1–36 range.
- `v_tier_ladder` created (266 rows). Ladder order and entry flag are derived from the active
  upgrade amount, ordered `NULLS FIRST`, partitioned by persona.
- Dropped from `tier_conditions`: `frequency`, `window_start_field`, `upgrade_evaluation_value`,
  `metric`, `window_type`, `window_months`, `window_start`, `upgrade_evaluation_timing`.
  Surviving columns: `id`, `merchant_id`, `tier_id`, `condition_type`, `amount`,
  `active_status`, `created_at`.
- Dropped: `tier_master.ranking`, `tier_master.entry_tier`,
  `tier_pending_upgrades.to_tier_ranking`, `amp_analysis_member_attrs.tier_ranking`,
  `tier_evaluation_tracking.maintain_condition_ids`.
- Trigger `trg_tier_conditions_unique_upgrade_amount` enforces one active upgrade amount per
  `(merchant_id, user_type)`. Duplicates on `New CRM` and `qa-next` were deactivated first.
  Current duplicate count is 0.
- `mv_amp_analysis_member_segments` rebuilt without `tier_ranking`. **`tier_name` moved from
  the `GROUP BY` into `max(tier_name)`** — it is a denormalized copy that can lag a rename,
  and grouping on it split one tier into duplicate rows and broke the unique index.
  `uq_mv_member_segments` was not recreated: it is strictly redundant with the
  `COALESCE(tier_id, ...)` unique index, which also handles null `tier_id`.

### Functions

Added: `fn_tier_window`, `fn_tier_ladder_for_user`, `bff_get_tier_program_config(p_user_type)`,
`bff_upsert_tier_program_config(p_config jsonb)`.

Deleted: `calculate_tier_window_dates`, `calculate_next_period_end`,
`calculate_upgrade_effective_date`, `reorder_tiers`, `set_entry_tier`, and the old
`apply_tier_upgrade`.

Rewritten: `evaluate_user_tier_status`, `apply_tier_change` (replaces `apply_tier_upgrade`,
now takes `p_change_type`), `ensure_tier_progress`, `evaluate_and_apply_chunk`,
`process_tier_event`, `tier_upsert_pending_upgrade`, `calculate_maintain_deadline`
(re-keyed to `(merchant_id, user_type, achieved_date)`), `bff_upsert_tier_with_conditions`,
`get_merchant_tiers`, `get_tier_display_config`, `get_tier_conditions_by_type`,
`get_user_summary`, `get_entity_options_by_type`, `get_translation_entities`,
`get_translation_form_data`, `fn_resolve_widget_merchant_display`,
`cs_bff_get_loyalty_snapshot_for_contact`, `get_user_burn_rate`,
`fn_amp_analysis_get_member_snapshot`, `api_bigcommerce_get_user_profile`,
`fn_amp_analysis_refresh_member_attrs`, `custom_internal_demo_bootstrap_merchant`,
`bff_admin_get_member_360`, `bff_get_basic_currency_config`, `chokepoint_post_user_event`.

### Bugs fixed along the way

1. Maintain success now advances `maintain_deadline` (plan Bug 1).
2. Downgrades log as `downgrade`, not `upgrade` (`apply_tier_change` takes the change type).
3. `calculate_next_period_end` off-by-one removed with the function (plan Bug 4).
4. **Entry-tier regression:** the first Phase 2 rewrite granted the lowest rung of a
   persona-filtered ladder even when it carried a real threshold, which handed Ajinomoto
   members a free Diamond. Both `evaluate_user_tier_status` and `chokepoint_post_user_event`
   now grant an entry tier only when its `upgrade_amount IS NULL`. A member on a ladder with
   no free rung starts with no tier and earns in.

### Verified

- `evaluate_user_tier_status` on a live Kovet member returns a clean rolling-12 window
  (2025-07-26 → 2026-07-26), `recommended_action: maintain`, no ranking keys.
- `fn_tier_ladder_for_user` derives Member (null) → Sliver 50 → Gold 80 → Platinum 150 →
  VIP 300.
- `calculate_maintain_deadline` returns `2027-07-26 / rolling`.
- `get_merchant_tiers` emits no `ranking` or `entry_tier`; conditions slimmed to
  `id / amount / active_status / condition_type`.
- Full scan of every `public` function and view: no surviving reference to `ranking`,
  `entry_tier`, `tier_ranking`, `to_tier_ranking`, or any dropped policy column. The only
  hits are the deliberate rejection list inside `bff_upsert_tier_with_conditions`.
- §4.7 gate: grep of `.cursor/deploy/**` (edge function mirror) found no matches.
- `requirements/CHANGELOG.md` has the 2026-07-26 entry.

## Open — §11 documentation sweep

**Done (2026-07-26 follow-up thread):**

1. Regenerated `requirements/REGISTRY_SUPABASE.md` (2098 lines; timestamp 2026-07-26T01:54:20Z).
   Note: regen SQL lists BASE TABLEs only — `v_tier_ladder` does not appear (functions +
   `tier_program_config` do).
2. `requirements/Tier.md` bumped to v6.0 (program config model).
3. `requirements/feature-docs/tiers.md` rewritten (still Archived in INDEX).
4. CRM Knowledge `tiers` blocks updated via SQL (MCP `update_knowledge_block` hit hstore bug).
5. `docs/PRODUCT_FEATURE_CATALOG.md` §Tiers + Admin Portal tiers row corrected.
6. FE handoff: `docs/TIER_PROGRAM_CONFIG_FE_BRIEF.md`.

**Still open for product:** Ajinomoto persona free-entry decision (see Data findings).

## Next exact step

Product decision on Ajinomoto ladders (keep earn-in for retailer / unsegmented vs make Bronze
universal or add a free retailer rung). Then FE alignment against
`docs/TIER_PROGRAM_CONFIG_FE_BRIEF.md`.

## Context the next thread needs

- Project `wkevmsedchftztoolkmi`. All DB work through Supabase MCP.
- Migrations applied, in order: `tier_program_config_phase1a`,
  `tier_program_config_phase1b_unique_upgrade_amount`, `tier_program_config_phase2_engine`,
  `tier_program_config_phase34_admin_api`, `tier_phase3_readers_batch1`,
  `tier_phase3_readers_batch2`, `tier_phase3_readers_batch3`,
  `tier_phase3_amp_and_demo_bootstrap`, `tier_phase3_readers_batch4_anchored`,
  `tier_phase3_drop_ranking_entry_tier`, `tier_phase5_drop_policy_columns`.
- Three large functions (`chokepoint_post_user_event`, `bff_admin_get_member_360`,
  `bff_get_basic_currency_config`) were edited by anchored `replace()` on
  `pg_get_functiondef` inside a `DO` block, each guarded by a `RAISE EXCEPTION` if its anchor
  was missing. This avoided retyping ~55KB of unrelated body. If those functions are edited
  again, read the live definition first.
- `bff_get_tier_program_config` takes `p_user_type` only; merchant comes from the JWT.
- **Frontend is not yet aligned.** The user chose `drop_anyway` on the Phase 3 gate, so any
  admin UI still reading `ranking` or `entry_tier`, or writing tier policy fields, is broken
  until it ships against the new contract (D4/D5 in the plan).

## Data findings worth surfacing to the business

- 25 `(merchant, user_type, persona)` ladders have no free entry rung, so new members there
  hold no tier until they cross the first threshold. Mostly `qa-*` Shopify test stores, but
  **ajinomoto** is real: its Bronze has no upgrade condition at the group level, yet some
  persona-scoped ladders exclude it. Worth a product decision.
- 38 tiers have no active upgrade condition. Most are legitimate entry rungs under the new
  model. `newcrm` has 9, which means several tiers tie at position 1 — test-merchant noise,
  but it will look odd in admin.
- Top Charoen's 118k orphaned `tier_evaluation_tracking` rows with no conditions remain
  untouched; the plan marks this out of scope.
