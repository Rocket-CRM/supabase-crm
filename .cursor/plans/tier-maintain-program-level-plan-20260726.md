# Tier maintain → program-level — design pin 2026-07-26

Predecessor: `.cursor/plans/tier-program-config-checkpoint-20260726.md` (Tier Program Config v6, live).
Project `wkevmsedchftztoolkmi`. All DB work via Supabase MCP.

**Status: implemented 2026-07-26** on `wkevmsedchftztoolkmi` (migrations `tier_maintain_program_level_phase1` +
`tier_maintain_program_level_phase2`). Docs + FE brief updated in the same session.

## The decision

Whether members can be downgraded becomes a program setting. The separate maintain threshold is
removed entirely — maintain is evaluated against the member's current rung's own upgrade amount.

Pinned with the user on 2026-07-26:

| Question | Answer |
|---|---|
| Where does the maintain threshold live? | Nowhere. Maintain = that tier's upgrade amount. Drop the separate amount. |
| Does the floor tier get a maintain amount? | Always exempt (falls out for free — its upgrade amount is null). |
| Mixed-coverage programs | Moot once there is no separate maintain amount. |
| FE contract | `maintain_mode` replaces `maintain_enabled` outright. No transitional alias. |
| Rollout for merchants whose bar rises | Apply to everyone now. |
| Existing maintain rows | Delete outright. |

## Resulting model

A member's tier is the highest rung their window metric qualifies for. Upgrades apply on crossing
(or end of month, per `upgrade_timing`). `maintain_mode` controls only whether the system ever
looks downward:

- `lifetime` — tier is never re-evaluated downward. No deadline is ever stamped.
- `period` — at each period boundary the member is re-checked against their current rung's
  upgrade amount, using the clock already on `tier_program_config` (`rolling` / `calendar_year`).

This is the Smile.io mental model ("lifetime forever" vs "calendar year").

## Live findings this pin rests on

Extracted from `wkevmsedchftztoolkmi` on 2026-07-26; re-verify before applying.

### The gate is centralized

`calculate_maintain_deadline` derives `v_has_maintain` from `EXISTS (active maintain condition on
this merchant + user_type ladder)` and returns a **null deadline** when false. A null deadline means
`evaluate_and_apply_chunk` never selects the member (it filters
`tet.maintain_deadline <= p_evaluation_date`) and `evaluate_user_tier_status` never enters the
maintain branch. Swapping that one `EXISTS` for a config read moves the whole feature.

### The downgrade target is already ladder-derived

`evaluate_user_tier_status` lines 107–129 compute the downgrade target as the highest rung below
the current position with `upgrade_amount <= v_metric_value`, falling back to the entry rung. With
maintain equal to the current rung's upgrade amount, `v_maintain_qualified` reduces to
`v_metric_value >= <current rung>.upgrade_amount` — readable from the
`fn_tier_ladder_for_user` select already in the function. The separate `tier_conditions` lookup at
lines 94–101 can be deleted rather than re-pointed.

### Data shape

- 49 program tracks. 44 have maintain on every tier, 3 have none
  (`duluxreward`, `outdoorshield`, `8mqr0k-qs.myshopify.com`), 2 are mixed
  (`newcrm` 11/6 — test merchant; `syngentagrower` 2/1 — real).
- 129 tiers with conditions: 76 maintain below upgrade, 40 equal, 9 above, 13 no maintain row,
  4 entry tiers carrying a maintain row (all test merchants: `newcrm` golden / Ultimate / Platinum,
  `qa-next` Tier E).
- `tier_conditions.condition_type` is enum `tier_conditions_type` with labels `upgrade,maintain`.
- Member table is `user_accounts` (`merchant_id`, `tier_id`). Merchant name column is
  `merchant_master.merchant_code` — there is no `merchant` table and no `merchant_name` column.

### Member impact — bar rises

| Merchant | Tier | maintain → new bar | Members |
|---|---|---|---|
| ajinomoto | Silver | 1,500 → 2,000 | 163 |
| kovet | Platinum Member | 120 → 150 | 155 |
| merge | Silver / Gold / Platinum | 2,500→3,000 / 3,500→4,000 / 4,500→5,000 | 36 |
| quickstart-ef112207 | Bronze / Silver / Gold | 0→100 / 300→500 / 1,000→1,500 | 12 |
| yuanta-demo | Silver / Gold / Platinum / Premier | ~30–40% higher | 6 |
| samitivej | Gold | 30,000 → 50,000 | 4 |
| cloudfriends, bmwperformance | various | small | 6 |

### Member impact — bar falls (current config was inverted)

| Merchant | Tier | maintain → new bar | Members |
|---|---|---|---|
| bangkokhospitalpartnerprogram | Prefer Partner | 10 → 5 | 71 |
| kaosmileclub | Silver | 24,999 → 15,000 | 60 |
| syngentagrower | test | 12 → 10 | 27 |

Zero-member tiers also affected: ajinomoto Gold/Diamond, doubleareward Gold, eurocreations
Gold/Platinum, munasoul, occ Silver, samitivej Platinum, smm Gold, tanktinkerclub Gold/Black,
wangwela Gold/Platinum, withat Rose Gold/Silver/Platinum, quickstart Starter/Diamond/Builder/Performer.

Change bites at each member's next period boundary, not on deploy.

## Change list

### 1. Schema migration

```sql
ALTER TABLE public.tier_program_config
  ADD COLUMN maintain_mode text NOT NULL DEFAULT 'lifetime'
    CHECK (maintain_mode IN ('lifetime','period'));

COMMENT ON COLUMN public.tier_program_config.maintain_mode IS
  'lifetime = tier never re-evaluated downward; period = re-checked each period boundary against the member''s current rung upgrade amount.';

UPDATE public.tier_program_config c
SET maintain_mode = 'period'
WHERE EXISTS (
  SELECT 1 FROM public.tier_conditions tc
  JOIN public.tier_master tm ON tm.id = tc.tier_id
  WHERE tc.merchant_id = c.merchant_id
    AND tm.user_type = c.user_type
    AND tc.condition_type = 'maintain'
    AND tc.active_status
);

DELETE FROM public.tier_conditions WHERE condition_type = 'maintain';
```

Expected: 46 rows to `period`, 3 remain `lifetime`. Delete removes ~129 rows (116 active + inactive).

Leave the `maintain` label on `tier_conditions_type`. Dropping an enum value in Postgres requires
recreating the type and every dependent column; the unused label is harmless once nothing reads it.
Confirm `trg_tier_conditions_unique_upgrade_amount` is unaffected (it scopes to `upgrade`).

### 2. `calculate_maintain_deadline` — the gate

Replace the `v_has_maintain` `EXISTS` block (lines ~21–32) with a read of
`tier_program_config.maintain_mode = 'period'` for `(p_merchant_id, p_user_type)`. Return null
deadline for `lifetime` and for a missing config row. Signature and return shape unchanged.

### 3. `evaluate_user_tier_status`

Delete the `tier_conditions` maintain lookup (lines ~94–101). Compute `v_maintain_qualified` from
the ladder: true when the current rung's `upgrade_amount IS NULL`, else
`v_metric_value >= <current rung>.upgrade_amount`. Keep the deadline guard at line ~93 so the check
still only fires when the deadline is due. Output keys unchanged (`maintain_qualified` stays).

### 4. `ensure_tier_progress`

Lines ~81–91 read the current tier's maintain amount into `v_maintain_threshold`. Re-point to the
current tier's upgrade amount. Under `lifetime`, leave `maintain_metric_needed` and
`maintain_progress` null rather than computing a target the member can never fail.

### 5. `bff_get_tier_program_config`

Drop the derived `maintain_enabled` `EXISTS` (lines ~27–32). Return stored `maintain_mode`.
Breaking read change — FE must ship together.

### 6. `bff_upsert_tier_program_config`

Read the live body before editing. Accept and validate `maintain_mode`; new stable error code
`INVALID_MAINTAIN_MODE`.

**Transition side-effects — the only genuinely new logic:**

- `period → lifetime`: null `tier_evaluation_tracking.maintain_deadline` and
  `maintain_window_type` for that `(merchant_id, user_type)`. Without this the daily batch keeps
  downgrading members of a program that is now lifetime.
- `lifetime → period`: seed `maintain_deadline` for existing members of that track from their
  `tier_achieved_at` via `calculate_maintain_deadline`. Without this nobody is ever evaluated until
  they happen to change tier.

### 7. `bff_upsert_tier_with_conditions`

Read the live body before editing (24 maintain references, ~11KB). Reject a `maintain` array with
the existing `UNSUPPORTED_FIELDS` code; stop writing maintain rows.

### 8. `get_tier_conditions_by_type`

Drop `v_maintain_conditions` and the `'maintain'` key from the returned object (lines ~12, 25,
71–74, 87). Form seed returns upgrade only.

### 9. No change expected, verify only

`evaluate_and_apply_chunk`, `apply_tier_change`, `process_tier_event`, `tier_upsert_pending_upgrade`
all inherit the null deadline and need no edit.

Read-side surfaces see null `maintain_deadline` under lifetime — confirm each renders it as
"lifetime" rather than erroring or showing a blank date: `get_user_summary`,
`get_user_tier_progress`, `bff_admin_get_member_360`, `get_tier_system_summary`,
`fn_amp_analysis_get_member_snapshot`, `fn_amp_analysis_refresh_member_attrs`,
`cs_bff_get_loyalty_snapshot_for_contact`. `chokepoint_post_user_event` has only a comment
mention — no gate.

`bff_admin_get_member_360` and `chokepoint_post_user_event` were previously edited by anchored
`replace()` on `pg_get_functiondef` inside a guarded `DO` block. If either needs editing, read the
live definition first.

## Smoke tests

1. `bff_get_tier_program_config('buyer')` for a `period` merchant returns `maintain_mode: 'period'`
   and no `maintain_enabled` key.
2. `calculate_maintain_deadline` on a `lifetime` track (`duluxreward`) returns a null deadline;
   on `kovet` returns a real date.
3. `evaluate_user_tier_status` on the Kovet member used in the v6 smoke test still returns
   `recommended_action: maintain`, now with the threshold at 150 not 120.
4. A member below their current rung's upgrade amount with a due deadline returns
   `recommended_action: downgrade` and a `recommended_tier_id` equal to the highest rung they
   still clear.
5. Save a program config flipping `period → lifetime`; confirm every
   `tier_evaluation_tracking.maintain_deadline` for that track is null.
6. Flip it back to `period`; confirm deadlines are re-seeded.
7. `bff_upsert_tier_with_conditions` with a `maintain` array returns `UNSUPPORTED_FIELDS`.
8. `get_tier_conditions_by_type` returns no `maintain` key.
9. Entry-rung member (null upgrade amount) on a `period` track is never downgraded.

## Docs to update after behavior lands

`requirements/Tier.md` (bump past v6.0), `docs/TIER_PROGRAM_CONFIG_FE_BRIEF.md` (§3 program config
table, the `maintain_enabled` note at line 77, the tier-definition layer at line 44, and the
`bff_upsert_tier_with_conditions` accepted-fields note at line 95), `requirements/feature-docs/tiers.md`,
`requirements/REGISTRY_SUPABASE.md` regen, `requirements/CHANGELOG.md` one-liner, CRM Knowledge
`tiers` blocks (MCP `update_knowledge_block` hits an hstore bug — write via SQL).

## Next exact step

FE alignment against `docs/TIER_PROGRAM_CONFIG_FE_BRIEF.md` (remove maintain amounts / `maintain_enabled`;
wire `maintain_mode`). Optional: Ajinomoto free-entry product decision (separate).
