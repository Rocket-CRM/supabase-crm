# Catalog weekly run — 2026-08-31 — `a7c3e9f1-2b84-4d56-9e10-20260831c001`

## Environment / evidence constraints

- CRM Knowledge MCP (`search_docs` / `get_section`) was **not** available on this Automation (only Cursor Automation Tools + cursor-cloud).
- Supabase MCP (`execute_sql`) was **not** available. Live inventory used anon REST on `v_internal_product_feature_catalog` (95 rows) + readable `internal_product_catalog_change_log`.
- `last_verified_at` / `source_refs` are **not** on the projection view; overdue detection used change-log reconstruction + requirement-path churn since verify.
- Catalog write policy: **reviewable SQL only** (`catalog-updates.sql`). Do not apply without human approval.
- Prior reviewable run `d1f5a8c3-6e2b-4d91-9d44-20260817c002` (PR draft on `cursor/product-feature-catalog-narrative-a858`) was **never applied** to live change_log — this run re-carries its evidence-backed verify/repair set under the new `run_id`.

## Inspect

- `requirements/CHANGELOG.md`: not present in repo.
- Requirement path churn since last weekly automation (~14d):
  - `requirements/Forms.md` (2026-08-25) — **optional survey header `banner_url`** (material).
  - `requirements/REGISTRY_SUPABASE.md` / `REGISTRY_RENDER.md` — registry only (receipt upload params, analytics CSV, CS Web Push, LINE webhook) — **no new sellable rows**.
- Active public modules in live catalog: `loyalty`, `shopify`, `marketing_automation`, `customer_service` (4 — matches REFERENCE §5; automation hard-law text saying “three” is stale vs REFERENCE).
- Freshness: many rows still lack logged `last_verified_at` (c002 never applied). Forms-group overdue because Forms.md changed after surveys’ last logged verify (2026-08-13).

## Classify

| feature_key | change | notes |
|---|---|---|
| `loyalty.forms.surveys` | update (+ localize_th) | Enrich summary/includes for banner + completion rewards; refresh Thai; source_refs + `last_verified_at` |
| `loyalty.forms.profile_fields` | update (verify) | Forms.md re-checked; copy unchanged |
| `loyalty.forms.custom_fields` | update (verify) | Forms.md re-checked; copy unchanged |
| `loyalty.forms.signup_form` | update (verify) | Forms.md + Signup_Login; copy unchanged |
| 15 currency/tier/mission/referral/reward/signup/persona/store/purchase/openapi/voice features | update (verify / repair) | Re-issue evidence-backed provenance from unapplied c002 |
| `platform.governance.admin_shell` | update (repair only) | Point source_refs at REGISTRY Admin Panel; **do not** bump `last_verified_at` |
| `loyalty.campaign.leaderboard` | conflict / stop | See Conflicts |
| Broken-`source_refs` / missing-doc features | conflict / stop | See Conflicts |
| Receipt upload / analytics / CS push / Asset registry churn | no_change | Eng registry / param surface only; sellable copy unchanged |
| Remaining never-verified rows without local evidence | skipped | No CRM Knowledge; deferred |

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

## Narrative

- Sections updated: **Survey forms** (new five-block section + `<!-- feature_key: loyalty.forms.surveys -->`); light Forms umbrella pointer to Survey forms / banner.
- Unrelated sections left untouched.
- Known gaps (reported, not rewritten): no `## Shopify` module section; sparse `<!-- feature_key -->` anchors elsewhere; leaderboard still blocked.

## Canonical Views handoff

- Catalog SQL changes **sales copy** for `loyalty.forms.surveys` (summary/includes/Thai) but **not** `commercial_nature`, package membership, or active-set. Optional Canonical Views refresh in `rocket-agent-plugins/plugins/rocket-sales/commercial/` if the features-summary sheet still uses the thin prior survey line — **not written in this repo**.

## Validation (pre-apply)

- Hierarchy / four modules: pass (live view)
- Thai completeness on active ga/beta (view): pass; surveys Thai refreshed in SQL
- `commercial_nature` present; consumption units set: pass (view)
- Broken `source_refs` paths: **fail** until SQL applied for repaired rows + human resolves remaining conflicts
- Narrative surveys anchor: pass (added this run)
