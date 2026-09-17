# Weekly catalog + Product Narrative — Cursor Automation entrypoint

Read **first**, in order:

1. `workflows/product-feature-catalog/REFERENCE.md` (full file — especially §6–10)
2. This file

Supabase project: `wkevmsedchftztoolkmi` only. Working repo: `Rocket-CRM/supabase-crm`.

## Mission

Reconcile the **product feature catalog** (`internal_product_*`) and **patch-only** updates to `docs/PRODUCT_NARRATIVE.md` from requirements evidence (CRM Knowledge MCP + scoped requirement reads). Do **not** edit commercial Canonical Views in this repo or in `rocket-agent-plugins`.

## Run order (REFERENCE §9)

1. Inspect requirement churn and catalog rows overdue for verification (30-day `last_verified_at`, null verify, or touching requirements path changed since verify). Include null/stale Thai when Thai is in scope.
2. Gather evidence via CRM Knowledge (`search_docs`, then `get_section` on hits). Scoped `requirements/**` reads only when Knowledge is thin.
3. Classify each candidate: `add` | `update` | `move` | `deprecate` | `no_change` | `localize_th`.
4. Apply catalog mutations in **one SQL transaction** with `run_id` (uuid) and append `internal_product_catalog_change_log` rows. Never hard-delete valid features.
5. Sync **only** affected Product Narrative sections (five-block template per §7). Map via `<!-- feature_key: … -->`.
6. Validate hierarchy, status, packages, `source_refs`, anchors, `commercial_nature` / `consumption_unit`, Thai completeness when in scope.
7. Produce the run summary (format below). If commercial identity changed (`commercial_nature`, groups, active set, names/summaries views use), add a **Canonical Views handoff** block — do not write view files.

## Conflict stop (per row)

Stop and leave prior state for that row when narrative contradicts catalog, requirements contradict GA without deprecate decision, duplicate `feature_key`, or package reassignment lacks evidence. Report in summary.

## Canonical Views handoff (when triggered)

List `feature_key`s and what changed (nature, group, active, name/summary). Point maintainers to `rocket-agent-plugins/plugins/rocket-sales/commercial/` per `commercial/REFERENCE.md` §7. Prices stay blank; do not touch `sales-run/`.

## Git

Commit narrative (and only catalog-related doc fixes if required) on a branch; open a PR or leave changes for human review per automation settings. Do not commit secrets.

## Run summary (required)

Use the markdown template in REFERENCE §10 (counts, feature changes table, conflicts, narrative sections touched, validation pass/fail).
