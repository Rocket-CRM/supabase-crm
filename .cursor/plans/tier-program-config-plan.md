# Tier Program Config Simplification — Backend Plan (v3)

**Status:** Ready for implementation. Decisions locked 2026-07-26. Phase 1 SQL is in §14 (approve + apply — do not re-draft).
**Project:** `wkevmsedchftztoolkmi`
**Authoritative sources:** live schema via Supabase MCP; this plan overrides stale `requirements/Tier.md` / CRM Knowledge where they conflict (see §11).

**New-thread handoff:** attach this file as the first message. Start at §12.

**Approval gate:** no schema or function deploys until the user explicitly approves Phase 1 migration SQL in-thread. Phases 2–5 proceed after Phase 1 verify, unless the user pauses.

---

## 0. Locked decisions (do not re-litigate)

| # | Decision | Lock |
|---|---|---|
| D1 | Downgrade target on maintain fail | **Highest lower tier the member still qualifies for** (not adjacent-by-rank). Entry tier if none qualify. |
| D2 | Dulux anniversary upgrade rows | Convert program clock to **`rolling_months = 12`**. |
| D3 | Munasoul upgrade `rolling 1` | **Config mistake.** Backfill **`rolling_months = 12`** (match maintain). |
| D4 | API response after rank dies | **Stop emitting `ranking` / `entry_tier`.** FE changes in the same release. No transitional `ladder_position` in public/admin JSON unless an internal engine helper needs it. |
| D5 | Tiers exist but no `tier_program_config` | **Fail evaluation** (clear error / no-op recommend). Phase 1 backfills every group that has active conditions. **FE follow-up (out of Phase 1–5 critical path):** block creating/editing tier amounts until program config exists. |
| D6 | Delete list | See §5. Includes folding `calculate_upgrade_effective_date` into evaluate/apply. |

---

## 1. What this is

Today a tier row carries both *how much* a member needs and *how that amount is measured, checked, and applied*. `tier_conditions` has nine policy columns; seven describe a clock.

**Target model:** the program owns the clock; each tier owns its threshold. Ladder order and entry tier are derived, never stored.

Why this is safe:

- One active row per `(tier_id, condition_type)` already holds everywhere (49 groups). Multi-path OR is dead.
- `frequency` is inert (selected, never branched). Batch keys off `tier_evaluation_tracking.maintain_deadline`.
- All ten real merchants use exactly one metric per ladder.

---

## 2. Product contract

### Program (one row per `merchant_id` + `user_type`)

| Field | Values | Notes |
|---|---|---|
| `program_start_date` | date, nullable | Activity before this does not count. NULL = no floor. |
| `metric` | `points` \| `sales` \| `orders` \| `ticket` | One metric for the whole ladder. |
| `period_type` | `calendar_year` \| `rolling` | |
| `period_start_month` | 1–12 | Required when `calendar_year`. `4` = Apr 1 → Mar 31. |
| `rolling_months` | 1–36 | Required when `rolling`. |
| `upgrade_timing` | `immediate` \| `end_of_month` | Default `immediate`. |

**One clock** for upgrade and maintain. Kovet / Biowoman / BMW “rolling climb + calendar maintain” was a UI default artifact (§9) — ignore maintain window when backfilling.

**`maintain_enabled` is derived:** ladder has ≥1 active maintain amount.

### Each tier

- Thresholds: `upgrade_amount`, optional `maintain_amount`
- Display: name, icon, color, benefits, burn rate, personas
- **Not on tier:** metric, window fields, frequency, timing, ranking, entry-tier flag

### Derived

| Property | Rule |
|---|---|
| Ladder order | `upgrade_amount` ASC NULLS FIRST, then `tier_id`, within the persona’s effective ladder |
| Entry tier | `ladder_position = 1` on that persona’s effective ladder |
| `maintain_enabled` | Any maintain amount on the ladder |

### Persona effective ladder

Same as `fn_tier_matches_persona`: unassigned tiers belong to every persona; assigned tiers only to listed personas. **Every evaluate / next-tier / downgrade / entry-assign path must scope to the member’s effective ladder** — never `max(ladder_position)` over the whole merchant.

### Out of product surface

Anniversary windows; per-tier metric/window/frequency/timing; `calendar_month` / `calendar_quarter`; `fixed_date` / `rolling_days` timing; free frequency picker; `end_of_period` upgrade timing (enum may stay extensible later).

---

## 3. Target schema

### 3.1 `tier_program_config`

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `merchant_id` | uuid NOT NULL | |
| `user_type` | `user_type` NOT NULL | |
| `program_start_date` | date NULL | |
| `metric` | `metric` NOT NULL | |
| `period_type` | text NOT NULL | CHECK (`calendar_year`,`rolling`) |
| `period_start_month` | smallint NULL | CHECK 1–12 |
| `rolling_months` | smallint NULL | CHECK 1–36 |
| `upgrade_timing` | text NOT NULL DEFAULT `'immediate'` | CHECK (`immediate`,`end_of_month`) |
| `created_at` / `updated_at` | timestamptz | |

Unique `(merchant_id, user_type)`.

CHECK: `calendar_year` ⇒ `period_start_month` NOT NULL and `rolling_months` IS NULL; `rolling` ⇒ opposite.

### 3.2 View `v_tier_ladder`

Single owner of ordering / entry derivation. Exposes per `(tier_id, persona_id)`:

`merchant_id`, `user_type`, `persona_id` (NULL = unsegmented base row for joins), `tier_id`, `upgrade_amount`, `ladder_position`, `is_entry`.

Ordering: `row_number() OVER (PARTITION BY merchant_id, user_type, persona_id ORDER BY upgrade_amount ASC NULLS FIRST, tier_id)`.

**Engine helper (new):** `fn_tier_ladder_for_user(p_user_id, p_merchant_id)` → setof ladder rows for that user’s persona (or unsegmented). All evaluate/downgrade/entry/next-tier logic uses this — not raw `v_tier_ladder` without persona.

### 3.3 Constraints on amounts

- Partial unique: active upgrade rows, **non-null** `amount` unique per `(merchant_id, user_type)` (reject duplicate thresholds).
- At most **one** active upgrade row with **NULL** `amount` per `(merchant_id, user_type)`.

**Phase 1 note:** live duplicates exist today on **New CRM** and **qa-next** only (not on the ten real merchants). Phase 1A ships without these indexes; Phase 1B (same migration file, gated) cleans those test duplicates then applies indexes. SQL in §14.

### 3.4 Column / table changes

**`tier_conditions` — keep:** `id`, `merchant_id`, `tier_id`, `condition_type`, `amount`, `active_status`, `created_at`.

**Drop Phase 1 (unread by engine):** `frequency`, `window_start_field`, `upgrade_evaluation_value`.

**Drop Phase 5 (after resolver live):** `metric`, `window_type`, `window_months`, `window_start`, `upgrade_evaluation_timing`.

**`tier_master`:** drop `ranking`, `entry_tier` in Phase 3 (same release as FE + reader migration).

**`tier_pending_upgrades`:** drop `to_tier_ranking`; `tier_upsert_pending_upgrade` loses that parameter.

**`tier_evaluation_tracking`:** `maintain_condition_ids` → scalar `maintain_condition_id` or drop (Phase 5). `maintain_window_type` mirrors program `period_type` after rewrite.

**`amp_analysis_member_attrs.tier_ranking`:** stop writing; drop column in Phase 3 or leave nullable unused — prefer **drop** after refresh writers migrate (no API emission of ranking per D4).

---

## 4. Function changes

### 4.1 Core engine

| Function | Action |
|---|---|
| `calculate_tier_window_dates` | **DELETE** |
| **NEW** `fn_tier_window(merchant_id, user_type, evaluation_date)` → `(window_start, window_end)` | Sole clock. Apply `GREATEST(window_start, program_start_date)` here. Missing config → raise/return sentinel that evaluate treats as fail (D5). |
| **NEW** `fn_tier_ladder_for_user(user_id, merchant_id)` | Persona-scoped ladder. |
| `calculate_maintain_deadline` | Rewrite; key `(merchant_id, user_type)` (+ achieved date). Absorbs period-end math. |
| `calculate_next_period_end` | **DELETE** |
| `calculate_upgrade_effective_date` | **DELETE** — inline `immediate` / `end_of_month` into evaluate / pending path. |
| `evaluate_user_tier_status` | Rewrite (§4.2). Output **must not** include `to_tier_ranking` / `ranking`. |
| `ensure_tier_progress` | Same rewrite; drop `maintain_condition_ids` array usage. |
| `apply_tier_upgrade` | Rename → `apply_tier_change`; add explicit change-type (`upgrade` \| `downgrade` \| `assign_entry` \| …). Fix bug: downgrades must not stamp as upgrade / must not reset maintain clock as fresh earn. |
| `evaluate_and_apply_chunk` | Advance `maintain_deadline` on maintain success (bug 1). Downgrade via D1. Call `apply_tier_change`. |
| `process_tier_event` | Update for new evaluate JSON (no `to_tier_ranking`); call `apply_tier_change` / slim `tier_upsert_pending_upgrade`. |
| `tier_upsert_pending_upgrade` | Drop `p_to_tier_ranking`. |
| `tier_apply_due_pending_upgrades` | Verify vs new evaluate; call `apply_tier_change`. |
| `calculate_tier_metric_value` | Signature unchanged; caller supplies floored window. |
| `get_tier_evaluation_chunks` | Verify selection still correct. |

### 4.2 Evaluation rewrite (shape)

1. Resolve `user_type` + persona.
2. Load `tier_program_config` — **if missing, fail eval (D5)**.
3. `fn_tier_window` once.
4. `calculate_tier_metric_value` once.
5. From `fn_tier_ladder_for_user`, pick highest `ladder_position` with `upgrade_amount IS NULL OR upgrade_amount <= metric` (NULL amount = entry rung).
6. Compare to current tier position on same ladder → recommend upgrade / maintain / downgrade / assign_entry.
7. Downgrade (D1): highest lower rung that still qualifies; else entry.
8. Upgrade timing: inline immediate vs end-of-month → `effective_at` / pending row.

No per-tier window loop. No `to_tier_ranking` in JSON.

### 4.3 Admin API

| Function | Action |
|---|---|
| **NEW** `bff_get_tier_program_config` / `bff_upsert_tier_program_config` | Program settings. |
| `bff_upsert_tier_with_conditions` | Accept name, display, personas, amounts only. **Reject** metric, window fields, `ranking`, `entry_tier`. Fix maintain-window default at source (§9). |
| `get_tier_conditions_by_type` | Slim; join program config for edit context. **No** `ranking` / `entry_tier`. |
| `get_merchant_tiers` | Breaking: drop rank/entry/window/timing from conditions JSON; order by amount. |
| `get_tier_display_config` | Drop rank/entry; order by amount / derived entry. |
| `reorder_tiers` | **DELETE** |
| `set_entry_tier` | **DELETE** |
| `admin_delete_tier` | Verify behavior when last tier removed; program config row may remain (FE cleans later). |

### 4.4 Ranking / entry / window readers — full migrate list

**Must migrate off `tier_master.ranking` / `entry_tier` (Phase 3, with FE):**

| Function | Notes |
|---|---|
| `evaluate_user_tier_status` | Engine rewrite |
| `ensure_tier_progress` | Engine rewrite |
| `process_tier_event` | Drop `to_tier_ranking` plumbing |
| `get_merchant_tiers` | Response shape |
| `get_tier_display_config` | Response shape |
| `get_tier_conditions_by_type` | Response shape |
| `bff_upsert_tier_with_conditions` | Stop writing rank/entry |
| `chokepoint_post_user_event` | Entry assign via `fn_tier_ladder_for_user` / `is_entry` |
| `get_user_summary` | Rank + metric from program config |
| `get_user_burn_rate` | Drop stored/returned tier ranking if present |
| `bff_admin_get_member_360` | Drop `tier_ranking` from payload |
| `cs_bff_get_loyalty_snapshot_for_contact` | Same |
| `fn_amp_analysis_get_member_snapshot` | Same |
| `fn_amp_analysis_refresh_member_attrs` | Stop writing `tier_ranking` |
| `api_bigcommerce_get_user_profile` | Drop `ranking` from tier objects; keep `amount` thresholds |
| `fn_resolve_widget_merchant_display` | Order by amount |
| `get_translation_entities` | Order by amount |
| `get_translation_form_data` | Drop `ranking` from reference JSON |
| `get_entity_options_by_type` | `ORDER BY` amount (join upgrade condition) or `tier_name` — **not** ranking |
| `custom_internal_demo_bootstrap_merchant` | Stop inserting ranking/entry_tier; insert program config + amounts |
| `tier_upsert_pending_upgrade` | Signature |

**Seed / demo (same Phase 3):**

- `demo/rocket-demo/waves/01_bootstrap.sql` — remove ranking/entry_tier inserts; add `tier_program_config` + condition amounts only.

**Confirm then dismiss if false positive:**

- `bff_get_basic_currency_config` — joins `tier_master` for earn-factor entity; re-eyeball; do not assume ranking migrate.

**Unaffected by ranking drop:**

- Reward APIs (`reward_master.ranking` is unrelated).
- `get_user_tier_progress` — reads `tier_progress` + display columns only; depends on `ensure_tier_progress` rewrite for correct progress, not on rank columns.
- `get_tier_system_summary` — counts only.
- `.cursor/deploy/inngest-event-router-serve` tier routers — call `process_tier_event` only; notification enrich selects `tier_name, icon` only.

**`tier_conditions` policy readers outside tier module:**

- `get_user_summary` — **must** read metric/window from program config (breaks if Phase 5 drops columns without this).
- `api_bigcommerce_get_user_profile` — amount only for threshold; survives column drops if it does not read window/metric from conditions.

### 4.5 Outside SQL (same releases as noted)

| Surface | When | Work |
|---|---|---|
| Admin FE | Phase 3–4 | Program settings page; per-tier amounts only; remove drag-reorder / entry-tier controls; stop binding `ranking` / `entry_tier`. Block tier amount save if no program config (D5 follow-up — can ship with program settings). |
| `crm-event-processors` / `tier-daily-batch` | Phase 2 | Verify due-user selection; no direct rank/column deps expected. |
| Edge functions (§4.7) | Before Phase 3 drop | Scan; fix any direct `tier_master.ranking` / `entry_tier` reads. |
| CRM Knowledge + docs | Phase 5 | §11 |

### 4.7 Gate before Phase 3 column drop

1. Grep / scan deployed edge function bodies for `ranking`, `entry_tier`, `to_tier_ranking` on tier objects.
2. Confirm Render `tier-daily-batch` (and any leftover TierConsumer reference) does not read those columns.
3. FE build that does not require `ranking` / `entry_tier` ready to deploy **same release** as the DROP.

Likely edge candidates: `auth-user-crm-v1`, `bigcommerce-get-user-profile`, `bigcommerce-get-user-rewards`, `amp-export-node-users`, `admin-user-export-csv`, `admin-batch-create-users`.

---

## 5. Delete / fold inventory

### DELETE (Postgres functions)

| Function | Why |
|---|---|
| `calculate_tier_window_dates` | Replaced by `fn_tier_window` |
| `calculate_next_period_end` | Absorbed into `calculate_maintain_deadline` |
| `calculate_upgrade_effective_date` | Only `immediate` / `end_of_month`; inline |
| `reorder_tiers` | Order derived from amounts |
| `set_entry_tier` | Entry derived |

### DROP (parameters / columns) — not whole functions

- `tier_upsert_pending_upgrade.p_to_tier_ranking` + `tier_pending_upgrades.to_tier_ranking`
- `tier_master.ranking`, `tier_master.entry_tier`
- `amp_analysis_member_attrs.tier_ranking` (prefer drop)
- Dead `tier_conditions` policy columns (Phased)
- Evaluate JSON keys: `to_tier_ranking`, any emitted `ranking` / `entry_tier`

### KEEP (distinct jobs — slim/rewrite only)

`evaluate_user_tier_status`, `ensure_tier_progress`, `get_user_tier_progress`, `process_tier_event`, `evaluate_and_apply_chunk`, `get_tier_evaluation_chunks`, `tier_apply_due_pending_upgrades`, `apply_tier_change` (renamed), `calculate_tier_metric_value`, `calculate_maintain_deadline`, `admin_delete_tier`, `tier_cancel_pending_upgrade`, `bff_upsert_tier_with_conditions`, `bff_upsert_tier_display`, `get_merchant_tiers`, `get_tier_conditions_by_type`, `get_tier_display_config`, `get_tier_system_summary`.

Optional later (not this project): merge admin reads into one `bff_get_tier_program`.

---

## 6. Data migration

### 6.1 Ten real merchants — backfill targets

| Merchant | Metric | Program period | Notes |
|---|---|---|---|
| Syngenta | points | rolling 12 | Fix NULL months; **delete `test` tier** (do not migrate) |
| Kao Smile Club | points | rolling 12 | Gold has no upgrade condition — deactivate or set amount with merchant; unreachable today |
| Dulux | points | **rolling 12** (D2) | Was anniversary; ladder repair in audit |
| Biowoman | points | rolling 12 | Ignore maintain fixed_period default |
| Kovet | points | rolling 12 | Same |
| Ajinomoto | points | rolling 12 | Ladder inverted by ranking — amount order fixes |
| Munasoul | points | **rolling 12** (D3) | Upgrade was wrongly 1 |
| BANGKOK HOSPITAL | points | rolling 6 | Clean |
| BMW | ticket | rolling 12 | Ignore maintain default + months=11 typo |
| Samitivej | sales | rolling 12 | Clean |

Test / qa merchants: mode from upgrade rows; force-migrate.

### 6.2 Backfill rules

1. Metric — distinct upgrade-row value (all real merchants single-valued).
2. Period — from **upgrade** rows only. `fixed_period` + `01-01`/12 → `calendar_year` `period_start_month=1`. Other `fixed_period` starts → calendar year with that start month. `rolling` → `rolling_months=N` (Munasoul forced to 12).
3. Ignore maintain window config when building the clock.
4. Anniversary upgrade → rolling 12 (Dulux).
5. Amounts stay on `tier_conditions`.
6. `program_start_date` = NULL for all existing.
7. `upgrade_timing` — `end_of_month` where set (3 rows / 2 merchants), else `immediate`.
8. Insert a config row for **every** `(merchant_id, user_type)` that has ≥1 active condition. Groups with tiers but zero conditions: **no config row** (D5 fail-eval until FE/program setup).

### 6.3 No blanket deadline rewrite

Merchants whose logic maps 1:1 need no `tier_evaluation_tracking` rewrite. Per-merchant diff only for Kovet, Biowoman, BMW, Syngenta NULL, Munasoul 1→12. Zero rows past due today (earliest deadline 2027-01-13).

### 6.4 Ladder repairs (sign-off diffs in Phase 1)

Amount order auto-corrects Ajinomoto, Dulux, Syngenta (+ delete `test`), Kao. Produce before/after member-impact diff; get sign-off before Phase 2 evaluates against new order. Derivation also closes 3 groups with no entry tier today.

---

## 7. Bugs fixed in the same pass (Phase 2)

1. **`maintain_deadline` never advances on maintain success** — highest priority; first cohort 2027.
2. **Downgrades logged as upgrades** — `apply_tier_change` + correct ledger / `tier_achieved_at` behavior.
3. **Downgrade target** — D1 (highest qualifying lower tier).
4. **Off-by-one** period end — fixed by deleting `calculate_next_period_end` and owning math in one place.
5. **`fixed_period` months &lt; 12` frozen windows** — repaired by calendar_year / rolling migration; list in audit.
6. **NULL `window_months`** — prevented by program CHECK.
7. Dead `OR tm.user_type IS NULL` branches — remove.
8. Maintain UI default — fix at FE or `bff_upsert_tier_with_conditions` source (§9) in Phase 4.

---

## 8. Phasing (implementation order)

### Phase 1 — schema + backfill (no engine behavior change)

**SQL is complete in §14** — next thread approves and applies via `apply_migration`; does not re-draft.

- 1A: `tier_program_config` + CHECKs, `v_tier_ladder`, drop three dead columns, backfill (Dulux/Munasoul → rolling 12).
- 1B (gated): clear duplicate upgrade amounts on New CRM / qa-next, then unique indexes.
- Run §14 audit queries; paste ten-merchant before/after into the thread.
- **Do not** switch `evaluate_user_tier_status` yet.

### Phase 2 — evaluation path

- Add `fn_tier_window`, `fn_tier_ladder_for_user`.
- Delete `calculate_tier_window_dates`, `calculate_next_period_end`, `calculate_upgrade_effective_date`.
- Rewrite `evaluate_user_tier_status`, `ensure_tier_progress`, `calculate_maintain_deadline`.
- Rename/fix `apply_tier_change`; update `process_tier_event`, `evaluate_and_apply_chunk`, `tier_apply_due_pending_upgrades`, `tier_upsert_pending_upgrade` (may keep `to_tier_ranking` param until Phase 3 if easier — prefer drop param here if pending column still unused).
- Fix bugs 1–4, 7.
- Missing config → fail eval (D5).
- Legacy policy columns may still be written for rollback until Phase 5.

### Phase 3 — drop ranking / entry_tier (FE same release)

**Hard gate §4.7 first.**

- Migrate all §4.4 readers; demo bootstrap + rocket-demo SQL.
- Stop AMP `tier_ranking` writes; drop column.
- Drop `tier_master.ranking`, `tier_master.entry_tier`, `tier_pending_upgrades.to_tier_ranking`.
- Delete `reorder_tiers`, `set_entry_tier`.
- Admin/member JSON: **no** `ranking` / `entry_tier` (D4).
- Deploy FE that matches.

### Phase 4 — admin program API + default fix

- `bff_get/upsert_tier_program_config`.
- Slim `bff_upsert_tier_with_conditions`, `get_tier_conditions_by_type`, `get_merchant_tiers`, `get_tier_display_config` (if any leftovers after Phase 3).
- Fix maintain-window default at source.
- FE: program settings; **do not allow tier threshold admin without program config** (D5).

*Note: Phase 3 and 4 may ship as one release if FE is ready — preferred.*

### Phase 5 — enforce + docs

- Drop remaining `tier_conditions` policy columns.
- Scalarize/drop `maintain_condition_ids`.
- Docs + registry + CRM Knowledge + CHANGELOG (§11).
- Confirm edge/Render clean.

---

## 9. Maintain clock default (must fix Phase 4)

Kovet, Biowoman, BMW: upgrade rolling 12 + maintain fixed_period 01-01/12 written in the **same transaction to the same microsecond** across all tiers — UI/BFF default, not intent.

**Before rewriting upsert:** locate default in FE form vs `bff_upsert_tier_with_conditions`. Remove it so new program config cannot be polluted.

---

## 10. Bugs / audits to ship with Phase 1 output

Per-merchant mapping table +:

- Four inverted/broken ladders
- `fixed_period` with `window_months < 12`
- Syngenta `test` tier delete recommendation
- Kao Gold missing upgrade amount
- Three entry-tier-less groups (fixed by derivation)
- Munasoul 1 → 12
- Dulux anniversary → rolling 12
- Top Charoen orphaned tracking (118k rows, no conditions) — **out of scope**

---

## 11. Docs to correct (Phase 5)

Stale and must not guide implementation:

- `Tier.md`: multi-path OR; calendar_month/quarter; fixed_date/rolling_days; downgrade adjacent; deadline auto-advance claim
- `requirements/feature-docs/tiers.md`
- CRM Knowledge `tiers` blocks (still mention ranking, multi-window, Render TierConsumer / “no Inngest” — live path is Inngest `process_tier_event`)
- `docs/PRODUCT_FEATURE_CATALOG.md` if it repeats the above
- `REGISTRY_SUPABASE.md` regenerate after function churn
- `requirements/CHANGELOG.md` one line

---

## 12. Next exact step (implementation thread)

1. Attach this file.
2. Run §14 **preflight / audit** SELECTs; paste ten-merchant mapping into the thread.
3. Get explicit approval → `apply_migration` with §14 Phase 1A (then 1B if precheck clean or after test-merchant cleanup).
4. Verify config row counts + view sample.
5. Phase 2 onward per §8 (engine rewrite — SQL for later phases is outlined in §8/§4; draft function bodies in-thread from those contracts, not from stale Tier.md).
6. Before Phase 3 → §4.7 scan + FE ready → rank/entry drop with §4.4 migrate; prefer same release as Phase 4.

**Do not** touch `evaluate_user_tier_status` until Phase 1 is applied and verified.

---

## 13. Verified reference snapshot (2026-07-26)

- 47 merchants with active `tier_conditions`; 49 `(merchant, user_type)` groups; 3 groups no maintain rows; 0 groups no upgrade rows
- 60 merchants with `tier_master`; 63 groups; 207 tiers; **0 NULL `user_type`**; 60 entry tiers (3 groups none); 18 tiers with persona assignments
- `tier_evaluation_tracking`: 118,742 rows; 118,535 with deadline; **0 past due**; earliest 2027-01-13; 0 rows with &gt;1 condition id
- Top Charoen: 118,200 tracking rows, 0 conditions — out of scope
- `calendar_month` / `calendar_quarter`: 0 active. `fixed_date` / `rolling_days`: 0. `end_of_month` timing: 3 rows, 2 merchants
- `fixed_period`: 140/144 use `window_start='01-01'`
- No views/MVs depend on `tier_conditions`
- Only two triggers on tier tables: widget cache invalidate; persona assignment validate — neither reads policy/ranking
- Munasoul live: upgrade rolling 1 ×3, maintain rolling 12 ×3 → program **rolling 12**
- `end_of_month` timing live on: New CRM (1), สี่มุมเมืองออนไลน์ (2)

---

## 14. Phase 1 migration SQL (apply as written)

**Migration name suggestion:** `tier_program_config_phase1`

**Order:** run preflight SELECTs → approve → apply **14.1 Phase 1A** → run verify → apply **14.2 Phase 1B** (after duplicate cleanup) → run audit SELECTs for the thread record.

Engine behavior is unchanged after this migration (no function rewrites).

### 14.0 Preflight (SELECT only — do not skip)

```sql
-- A) Ten real merchants: proposed program config from upgrade rows (with D2/D3 overrides)
WITH upgrade_rows AS (
  SELECT
    m.id AS merchant_id,
    m.name AS merchant_name,
    tm.user_type,
    tc.metric,
    tc.window_type::text AS window_type,
    tc.window_months,
    tc.window_start,
    tc.upgrade_evaluation_timing
  FROM tier_conditions tc
  JOIN tier_master tm ON tm.id = tc.tier_id
  JOIN merchant_master m ON m.id = tc.merchant_id
  WHERE tc.active_status IS TRUE
    AND tc.condition_type = 'upgrade'
    AND m.name IN (
      'Syngenta','Kao Smile Club','Dulux','Biowoman','Kovet',
      'Ajinomoto','Munasoul','BANGKOK HOSPITAL','BMW','Samitivej'
    )
),
agg AS (
  SELECT
    merchant_id,
    merchant_name,
    user_type,
    MODE() WITHIN GROUP (ORDER BY metric) AS metric,
    MODE() WITHIN GROUP (ORDER BY window_type) AS window_type,
    MODE() WITHIN GROUP (ORDER BY window_months) AS window_months,
    MODE() WITHIN GROUP (ORDER BY window_start) AS window_start,
    BOOL_OR(upgrade_evaluation_timing = 'end_of_month') AS any_eom
  FROM upgrade_rows
  GROUP BY 1,2,3
)
SELECT
  merchant_name,
  user_type::text,
  metric::text,
  CASE
    WHEN merchant_name IN ('Dulux','Munasoul') THEN 'rolling'
    WHEN window_type = 'anniversary' THEN 'rolling'
    WHEN window_type = 'fixed_period' THEN 'calendar_year'
    WHEN window_type = 'rolling' THEN 'rolling'
    ELSE 'rolling'
  END AS period_type,
  CASE
    WHEN merchant_name IN ('Dulux','Munasoul') THEN NULL
    WHEN window_type = 'anniversary' THEN NULL
    WHEN window_type = 'fixed_period' THEN
      COALESCE(NULLIF(split_part(window_start, '-', 1), '')::smallint, 1)
    ELSE NULL
  END AS period_start_month,
  CASE
    WHEN merchant_name IN ('Dulux','Munasoul') THEN 12::smallint
    WHEN window_type = 'anniversary' THEN 12::smallint
    WHEN window_type = 'rolling' THEN COALESCE(window_months, 12)::smallint
    ELSE NULL
  END AS rolling_months,
  CASE WHEN any_eom THEN 'end_of_month' ELSE 'immediate' END AS upgrade_timing
FROM agg
ORDER BY merchant_name;

-- B) Duplicate non-null upgrade amounts (must be empty before 1B indexes; expect New CRM / qa-next only)
SELECT m.name, tm.user_type::text, tc.amount, COUNT(*), array_agg(tc.id) AS condition_ids
FROM tier_conditions tc
JOIN tier_master tm ON tm.id = tc.tier_id
JOIN merchant_master m ON m.id = tc.merchant_id
WHERE tc.active_status IS TRUE
  AND tc.condition_type = 'upgrade'
  AND tc.amount IS NOT NULL
GROUP BY 1,2,3
HAVING COUNT(*) > 1
ORDER BY 1,3;

-- C) Ladder repair preview (ranking vs amount order)
SELECT m.name, tm.tier_name, tm.ranking, tm.entry_tier, tc.amount AS upgrade_amount
FROM tier_master tm
JOIN merchant_master m ON m.id = tm.merchant_id
LEFT JOIN tier_conditions tc
  ON tc.tier_id = tm.id AND tc.condition_type = 'upgrade' AND tc.active_status IS TRUE
WHERE m.name IN ('Ajinomoto','Dulux','Syngenta','Kao Smile Club')
ORDER BY m.name, tm.ranking NULLS LAST, tm.tier_name;
```

### 14.1 Phase 1A — DDL, view, backfill, drop dead columns

```sql
-- ========== tier_program_config ==========
CREATE TABLE public.tier_program_config (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES public.merchant_master(id),
  user_type public.user_type NOT NULL,
  program_start_date date NULL,
  metric public.metric NOT NULL,
  period_type text NOT NULL,
  period_start_month smallint NULL,
  rolling_months smallint NULL,
  upgrade_timing text NOT NULL DEFAULT 'immediate',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT tier_program_config_merchant_user_type_uidx UNIQUE (merchant_id, user_type),
  CONSTRAINT tier_program_config_period_type_chk
    CHECK (period_type IN ('calendar_year', 'rolling')),
  CONSTRAINT tier_program_config_upgrade_timing_chk
    CHECK (upgrade_timing IN ('immediate', 'end_of_month')),
  CONSTRAINT tier_program_config_period_start_month_chk
    CHECK (period_start_month IS NULL OR period_start_month BETWEEN 1 AND 12),
  CONSTRAINT tier_program_config_rolling_months_chk
    CHECK (rolling_months IS NULL OR rolling_months BETWEEN 1 AND 36),
  CONSTRAINT tier_program_config_period_shape_chk CHECK (
    (period_type = 'calendar_year'
      AND period_start_month IS NOT NULL
      AND rolling_months IS NULL)
    OR
    (period_type = 'rolling'
      AND rolling_months IS NOT NULL
      AND period_start_month IS NULL)
  )
);

COMMENT ON TABLE public.tier_program_config IS
  'One clock per merchant+user_type ladder. Tiers own thresholds only (tier_conditions.amount).';
COMMENT ON COLUMN public.tier_program_config.program_start_date IS
  'Activity before this date does not count. NULL = no floor.';
COMMENT ON COLUMN public.tier_program_config.period_start_month IS
  'For calendar_year: 1 = Jan1–Dec31, 4 = Apr1–Mar31.';

CREATE INDEX tier_program_config_merchant_id_idx
  ON public.tier_program_config (merchant_id);

-- ========== v_tier_ladder ==========
-- persona_id NULL = unsegmented ladder (tiers with no persona assignments).
-- persona_id set = unassigned tiers + tiers assigned to that persona.
CREATE OR REPLACE VIEW public.v_tier_ladder AS
WITH upgrade AS (
  SELECT
    tm.merchant_id,
    tm.user_type,
    tm.id AS tier_id,
    tc.amount AS upgrade_amount
  FROM public.tier_master tm
  LEFT JOIN public.tier_conditions tc
    ON tc.tier_id = tm.id
   AND tc.condition_type = 'upgrade'
   AND tc.active_status IS TRUE
),
persona_keys AS (
  SELECT DISTINCT
    tm.merchant_id,
    tm.user_type,
    tpa.persona_id
  FROM public.tier_persona_assignments tpa
  JOIN public.tier_master tm ON tm.id = tpa.tier_id
),
unsegmented AS (
  SELECT
    u.merchant_id,
    u.user_type,
    NULL::uuid AS persona_id,
    u.tier_id,
    u.upgrade_amount
  FROM upgrade u
  WHERE NOT EXISTS (
    SELECT 1 FROM public.tier_persona_assignments tpa WHERE tpa.tier_id = u.tier_id
  )
),
per_persona AS (
  SELECT
    pk.merchant_id,
    pk.user_type,
    pk.persona_id,
    u.tier_id,
    u.upgrade_amount
  FROM persona_keys pk
  JOIN upgrade u
    ON u.merchant_id = pk.merchant_id
   AND u.user_type = pk.user_type
  WHERE NOT EXISTS (
          SELECT 1 FROM public.tier_persona_assignments tpa WHERE tpa.tier_id = u.tier_id
        )
     OR EXISTS (
          SELECT 1 FROM public.tier_persona_assignments tpa
          WHERE tpa.tier_id = u.tier_id AND tpa.persona_id = pk.persona_id
        )
),
combined AS (
  SELECT * FROM unsegmented
  UNION ALL
  SELECT * FROM per_persona
)
SELECT
  c.merchant_id,
  c.user_type,
  c.persona_id,
  c.tier_id,
  c.upgrade_amount,
  row_number() OVER (
    PARTITION BY c.merchant_id, c.user_type, c.persona_id
    ORDER BY c.upgrade_amount ASC NULLS FIRST, c.tier_id
  )::integer AS ladder_position,
  (
    row_number() OVER (
      PARTITION BY c.merchant_id, c.user_type, c.persona_id
      ORDER BY c.upgrade_amount ASC NULLS FIRST, c.tier_id
    ) = 1
  ) AS is_entry
FROM combined c;

COMMENT ON VIEW public.v_tier_ladder IS
  'Derived ladder order and entry flag from upgrade amounts + persona assignments. Do not store ranking/entry_tier.';

-- ========== Backfill from active upgrade conditions ==========
-- Overrides: Dulux + any anniversary → rolling 12; Munasoul → rolling 12 (upgrade=1 was mistake).
-- Ignore maintain rows entirely. program_start_date left NULL.
INSERT INTO public.tier_program_config (
  merchant_id,
  user_type,
  program_start_date,
  metric,
  period_type,
  period_start_month,
  rolling_months,
  upgrade_timing
)
WITH upgrade_rows AS (
  SELECT
    tm.merchant_id,
    tm.user_type,
    m.name AS merchant_name,
    tc.metric,
    tc.window_type::text AS window_type,
    tc.window_months,
    tc.window_start,
    tc.upgrade_evaluation_timing
  FROM public.tier_conditions tc
  JOIN public.tier_master tm ON tm.id = tc.tier_id
  JOIN public.merchant_master m ON m.id = tm.merchant_id
  WHERE tc.active_status IS TRUE
    AND tc.condition_type = 'upgrade'
),
agg AS (
  SELECT
    merchant_id,
    user_type,
    MIN(merchant_name) AS merchant_name,
    MODE() WITHIN GROUP (ORDER BY metric) AS metric,
    MODE() WITHIN GROUP (ORDER BY window_type) AS window_type,
    MODE() WITHIN GROUP (ORDER BY window_months) AS window_months,
    MODE() WITHIN GROUP (ORDER BY window_start) AS window_start,
    BOOL_OR(upgrade_evaluation_timing = 'end_of_month') AS any_eom
  FROM upgrade_rows
  GROUP BY merchant_id, user_type
)
SELECT
  a.merchant_id,
  a.user_type,
  NULL::date AS program_start_date,
  a.metric,
  CASE
    WHEN a.merchant_name IN ('Dulux', 'Munasoul') THEN 'rolling'
    WHEN a.window_type = 'anniversary' THEN 'rolling'
    WHEN a.window_type = 'fixed_period' THEN 'calendar_year'
    WHEN a.window_type = 'rolling' THEN 'rolling'
    ELSE 'rolling'
  END AS period_type,
  CASE
    WHEN a.merchant_name IN ('Dulux', 'Munasoul') THEN NULL
    WHEN a.window_type = 'anniversary' THEN NULL
    WHEN a.window_type = 'fixed_period' THEN
      COALESCE(
        NULLIF(split_part(COALESCE(a.window_start, '01-01'), '-', 1), '')::smallint,
        1
      )
    ELSE NULL
  END AS period_start_month,
  CASE
    WHEN a.merchant_name IN ('Dulux', 'Munasoul') THEN 12::smallint
    WHEN a.window_type = 'anniversary' THEN 12::smallint
    WHEN a.window_type = 'rolling' THEN COALESCE(a.window_months, 12)::smallint
    ELSE NULL
  END AS rolling_months,
  CASE WHEN a.any_eom THEN 'end_of_month' ELSE 'immediate' END AS upgrade_timing
FROM agg a
ON CONFLICT (merchant_id, user_type) DO NOTHING;

-- ========== Drop inert columns (engine does not branch on these) ==========
ALTER TABLE public.tier_conditions
  DROP COLUMN IF EXISTS frequency,
  DROP COLUMN IF EXISTS window_start_field,
  DROP COLUMN IF EXISTS upgrade_evaluation_value;
```

### 14.2 Phase 1B — amount uniqueness (after duplicates cleared)

Run only when preflight B returns **zero** rows, or run the cleanup first then the trigger.

`user_type` lives on `tier_master`, so a plain unique index on `tier_conditions` cannot express the rule — enforce with a trigger.

```sql
-- Cleanup known test-merchant duplicate upgrade amounts (keep oldest per amount).
WITH dups AS (
  SELECT
    tc.id,
    row_number() OVER (
      PARTITION BY tm.merchant_id, tm.user_type, tc.amount
      ORDER BY tc.created_at NULLS LAST, tc.id
    ) AS rn
  FROM public.tier_conditions tc
  JOIN public.tier_master tm ON tm.id = tc.tier_id
  JOIN public.merchant_master m ON m.id = tm.merchant_id
  WHERE tc.active_status IS TRUE
    AND tc.condition_type = 'upgrade'
    AND tc.amount IS NOT NULL
    AND m.name IN ('New CRM', 'qa-next')
)
UPDATE public.tier_conditions tc
SET active_status = false
FROM dups d
WHERE tc.id = d.id
  AND d.rn > 1;

CREATE OR REPLACE FUNCTION public.fn_tier_conditions_enforce_unique_upgrade_amount()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_user_type public.user_type;
  v_cnt integer;
BEGIN
  IF NEW.active_status IS TRUE AND NEW.condition_type = 'upgrade' THEN
    SELECT tm.user_type INTO v_user_type
    FROM public.tier_master tm
    WHERE tm.id = NEW.tier_id;

    SELECT COUNT(*) INTO v_cnt
    FROM public.tier_conditions tc
    JOIN public.tier_master tm ON tm.id = tc.tier_id
    WHERE tc.active_status IS TRUE
      AND tc.condition_type = 'upgrade'
      AND tc.amount IS NOT DISTINCT FROM NEW.amount
      AND tm.merchant_id = NEW.merchant_id
      AND tm.user_type = v_user_type
      AND tc.id IS DISTINCT FROM NEW.id;

    IF v_cnt > 0 THEN
      RAISE EXCEPTION
        'duplicate active upgrade amount % for merchant % user_type %',
        NEW.amount, NEW.merchant_id, v_user_type;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_tier_conditions_unique_upgrade_amount ON public.tier_conditions;
CREATE TRIGGER trg_tier_conditions_unique_upgrade_amount
  BEFORE INSERT OR UPDATE ON public.tier_conditions
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_tier_conditions_enforce_unique_upgrade_amount();
```

### 14.3 Post-apply verify

```sql
-- Expect 49 rows (one per group with active conditions)
SELECT COUNT(*) AS config_rows FROM public.tier_program_config;

SELECT m.name, c.user_type::text, c.metric::text, c.period_type,
       c.period_start_month, c.rolling_months, c.upgrade_timing
FROM public.tier_program_config c
JOIN public.merchant_master m ON m.id = c.merchant_id
WHERE m.name IN (
  'Syngenta','Kao Smile Club','Dulux','Biowoman','Kovet',
  'Ajinomoto','Munasoul','BANGKOK HOSPITAL','BMW','Samitivej'
)
ORDER BY m.name;

-- Munasoul + Dulux must be rolling / 12
SELECT m.name, c.period_type, c.rolling_months
FROM public.tier_program_config c
JOIN public.merchant_master m ON m.id = c.merchant_id
WHERE m.name IN ('Munasoul','Dulux');

-- Dead columns gone
SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'tier_conditions'
  AND column_name IN ('frequency','window_start_field','upgrade_evaluation_value');
-- expect 0 rows

-- Ladder sample
SELECT m.name, v.persona_id IS NULL AS unsegmented, tm.tier_name,
       v.upgrade_amount, v.ladder_position, v.is_entry
FROM public.v_tier_ladder v
JOIN public.tier_master tm ON tm.id = v.tier_id
JOIN public.merchant_master m ON m.id = v.merchant_id
WHERE m.name = 'Ajinomoto' AND v.persona_id IS NULL
ORDER BY v.ladder_position;
```

### 14.4 Audit queries (paste results into implementation thread)

```sql
-- Syngenta test tier
SELECT tm.id, tm.tier_name, tm.ranking, tc.amount
FROM tier_master tm
JOIN merchant_master m ON m.id = tm.merchant_id
LEFT JOIN tier_conditions tc
  ON tc.tier_id = tm.id AND tc.condition_type = 'upgrade' AND tc.active_status
WHERE m.name = 'Syngenta'
ORDER BY tm.ranking;

-- Kao Gold missing upgrade
SELECT tm.tier_name, tm.ranking, tc.amount, tc.id AS upgrade_condition_id
FROM tier_master tm
JOIN merchant_master m ON m.id = tm.merchant_id
LEFT JOIN tier_conditions tc
  ON tc.tier_id = tm.id AND tc.condition_type = 'upgrade' AND tc.active_status
WHERE m.name = 'Kao Smile Club'
ORDER BY tm.ranking;

-- Groups with no entry_tier today (derivation will close)
SELECT m.name, tm.user_type::text, COUNT(*) AS tiers,
       COUNT(*) FILTER (WHERE tm.entry_tier) AS entry_flags
FROM tier_master tm
JOIN merchant_master m ON m.id = tm.merchant_id
GROUP BY 1,2
HAVING COUNT(*) FILTER (WHERE tm.entry_tier) = 0
ORDER BY 1;

-- fixed_period months < 12 still on conditions (legacy cols until Phase 5)
SELECT m.name, tc.condition_type::text, tc.window_months, COUNT(*)
FROM tier_conditions tc
JOIN merchant_master m ON m.id = tc.merchant_id
WHERE tc.active_status
  AND tc.window_type::text = 'fixed_period'
  AND tc.window_months IS NOT NULL
  AND tc.window_months < 12
GROUP BY 1,2,3
ORDER BY 1;
```
)
