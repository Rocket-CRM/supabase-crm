# Catalog weekly run — 2026-09-07 — `f2a9c4e1-6b83-4d17-9e50-20260907c001`

## Environment / evidence constraints

- CRM Knowledge MCP (`search_docs` / `get_section`) was **not** available on this Automation (only Cursor Automation Tools + cursor-cloud + subscriptions).
- Supabase MCP (`execute_sql`) was **not** available. Live inventory used anon REST on `v_internal_product_feature_catalog` (95 rows) + readable `internal_product_catalog_change_log` (241 rows; latest live mutation 2026-08-20).
- Projection view lacks `last_verified_at` / `source_refs`. Overdue detection used change-log reconstruction + requirement-path churn since verify.
- Catalog write policy: **reviewable SQL only** (`catalog-updates.sql`). Do not apply without human approval.
- Prior reviewable runs `2026-08-31-c001` and `2026-08-17-c002` remain **unapplied** in live change_log — this run re-carries their evidence-backed verify/repair set under the new `run_id`, plus Sep Reward/Referral path churn.

## Inspect

- `requirements/CHANGELOG.md`: not present in repo.
- Requirement path churn since last weekly automation (~2026-08-31):
  - `requirements/Forms.md` (2026-08-25) — optional survey header `banner_url` — **still material** (surveys SQL never applied).
  - `requirements/Reward.md` (2026-09-05) — Campaign reward relation layer + campaign visibility clarification — **eng attach layer**; no new sellable row.
  - `requirements/Referral.md` (2026-09-04) — Notifications (outbox) — **eng**; sellable referral claim unchanged.
  - `requirements/REGISTRY_*` — registry/orchestration only (loyalty cache, LINE webhook, analytics CSV, receipt params, CS Web Push) — **no new sellable rows**.
  - Tier perk master shipped as migration `20260905143000_tier_perk_master.sql` **without** `requirements/Tier.md` update — **conflict / do not add**.
- Active public modules in live catalog: `loyalty`, `shopify`, `marketing_automation`, `customer_service` (4 — matches REFERENCE §5; automation prompt “three modules” is stale vs REFERENCE).
- Freshness: projection has no `last_verified_at`; change-log reconstruction shows many null LVs; Forms/Reward/Referral path churn since last logged verify.

## Classify

| feature_key | change | notes |
|---|---|---|
| `loyalty.forms.surveys` | update (+ localize_th) | Banner + completion rewards; refresh Thai; source_refs + `last_verified_at` |
| `loyalty.forms.profile_fields` | update (verify) | Forms.md re-checked; copy unchanged |
| `loyalty.forms.custom_fields` | update (verify) | Forms.md re-checked; copy unchanged |
| `loyalty.forms.signup_form` | update (verify) | Forms.md + Signup_Login; copy unchanged |
| `loyalty.campaign.referral` | update (verify) | Referral.md Core + Notifications outbox; copy unchanged |
| `loyalty.reward.catalog` (+ eligibility, dynamic_pricing, promo_codes, groups_limits, flash, admin_push_claim) | update (verify) | Reward.md path churn; copy unchanged |
| 11 currency/tier/mission/signup/persona/store/purchase/openapi/voice features | update (verify / repair) | Re-issue evidence-backed provenance from unapplied prior runs |
| `platform.governance.admin_shell` | update (repair only) | Point source_refs at REGISTRY Admin Panel; **do not** bump `last_verified_at` |
| `loyalty.campaign.leaderboard` | conflict / stop | See Conflicts |
| Broken-`source_refs` / missing-doc features | conflict / stop | See Conflicts |
| Tier perk master (no feature_key) | conflict / stop | Eng shipped without Tier.md — do not invent catalog row |
| Registry-only churn | no_change | Eng registry / cron / webhook surface only |

## Conflicts (stopped — no SQL mutation)

| feature_key | reason | action |
|---|---|---|
| `loyalty.campaign.leaderboard` | `source_refs` still cite non-existent `requirements/Leaderboard.md`; sales claims not evidenced by REGISTRY Campaign listing alone | left unchanged; no narrative section |
| `loyalty.analytics.reports` | cites missing `docs/LOYALTY_REPORTS_MARKETING_BRIEF.md` + `requirements/Analytics.md` | left unchanged |
| `loyalty.frontline.customer_360` | cites missing Frontline / Activity_Attribution docs | left unchanged |
| `loyalty.frontline.assisted_actions` | cites missing Frontline docs | left unchanged |
| `loyalty.lifecycle.anniversary` | cites missing `docs/AMP_LIFECYCLE_AUTOMATION.md` | left unchanged |
| `loyalty.lifecycle.tier_change` | cites missing `docs/AMP_LIFECYCLE_AUTOMATION.md` | left unchanged |
| `loyalty.persona.targeted_broadcast` | cites missing `requirements/AMP - Rule Based.md` | left unchanged |
| `marketing_automation.workflows.line_flex` | cites missing `requirements/AMP - Rule Based.md` | left unchanged |
| `loyalty.campaign.checkin` | no `requirements/Checkin.md`; REGISTRY Checkin alone too thin for daily/weekly rhythm claim | deferred |
| *(no key)* tier perk master | migration landed without `requirements/Tier.md` evidence | do not add feature; wait for doc closeout |

## Narrative

- Sections updated: **Survey forms** (five-block section + `<!-- feature_key: loyalty.forms.surveys -->`); light Forms umbrella pointer to Survey forms / banner.
- Referral / Rewards narrative left untouched (eng-only churn; catalog copy unchanged for those rows).
- Known gaps (reported, not rewritten): no `## Shopify` module section; sparse `<!-- feature_key -->` anchors elsewhere; leaderboard still blocked.

## Canonical Views handoff

- Catalog SQL changes **sales copy** for `loyalty.forms.surveys` (summary/includes/Thai) but **not** `commercial_nature`, package membership, or active-set. Optional Canonical Views refresh in `rocket-agent-plugins/plugins/rocket-sales/commercial/` if the features-summary sheet still uses the thin prior survey line — **not written in this repo**.

## Validation (pre-apply)

- Hierarchy / four modules: pass (live view)
- Thai completeness on active ga/beta (view): pass; surveys Thai refreshed in SQL
- `commercial_nature` present; consumption units set: pass (view)
- Broken `source_refs` paths: **fail** until SQL applied for repaired rows + human resolves remaining conflicts
- Narrative surveys anchor: pass (added this run)
