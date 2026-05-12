# Agent Context Architecture — Optimization Plan

> Handoff document. Read in full at the start of the follow-up thread.
> Lives outside the `.plan.md` ignore pattern so it remains @-referenceable.

## Goal

Reduce per-turn token cost and improve agent reliability without downgrading models or weakening workflows. Restructure the layers of context (rules, skills, requirement docs, registries, MCPs) so each is loaded only when the agent actually needs it, and routing between them is deterministic.

---

## Asset Layers (target state)

| Layer | Role | Discovery mechanism | Loaded per turn? |
|---|---|---|---|
| **0. Always-applied rules** | Hard laws + minimal routing | Forced into context | Yes |
| **1. Routers** (`_index.md`, `REGISTRY_SUPABASE.md`, `REGISTRY_RENDER.md`) | Map keyword → domain → function/table/edge fn | Grepped on demand; never full-read | No (grep only) |
| **2. Live truth** (Supabase MCP) | Authoritative schema + function signatures + bodies | Tool descriptors visible; queries on demand | No |
| **3. Authoritative narrative** (`requirements/<Domain>.md`) | Business rules, edge cases, examples | Scoped grep + offset/limit read | No |
| **4. Product/feature context** (CRM Knowledge MCP) | Pre-chunked semantic blocks (overview/rules/frontend_journey/technical_reference) | Tool descriptors visible | No |
| **5. Requestable rules** (`.cursor/rules/*.mdc`, `alwaysApply: false`) | Conventions for lookup, build, close phases | Path + description surfaced | On demand |
| **6. Skills** (`.cursor/skills/<name>/SKILL.md`) | Multi-file workflows with optional scripts | Name + description surfaced | On demand |

---

## Current State (May 2026)

### Existing files

- Always-applied: `00-core.mdc` (large), `14-no-canvas.mdc`, `15-crm-knowledge-mcp.mdc`.
- Requestable: `02`, `05`, `06`, `07`, `08`, `09`, `10`, `11`, `13`.
- Requirement docs: large authoritative `<Domain>.md` files in `/requirements/` (Currency.md ~139KB, Tier.md ~119KB, Reward.md ~102KB, INDEX_FUNCTION.md ~100KB).
- Per-domain summaries: `requirements/domains/<slug>.md` (small, mixed registry + line-range map).
- Domain index: `requirements/domains/_index.md` (~22KB — currently used as router but oversized for full-read).
- No skills exist yet (`.cursor/skills/` does not exist).
- `INDEX_FUNCTION.md` is deprecated artifact (regenerated, ~100KB, not to be read).
- CRM Knowledge MCP (`user-crm-knowledge`) is available with `resolve_feature_term`, `search_semantic`, `get_feature_context`.

### Known problems

1. `00-core.mdc` carries procedural detail (5-step Context Lookup walkthrough) that should be in a requestable rule.
2. Requirement docs are large and often full-read; no grep-first protocol enforced.
3. Per-domain summary docs mix registry-style function/table lists with narrative — agent gets lost.
4. No function/table registry → agent either guesses, reads per-domain file (token cost), or does `LIKE` discovery on MCP (turn cost).
5. No tool-batching rule → independent reads happen sequentially over many turns.
6. No thread-checkpoint behavior → long threads compound context replay cost.
7. No explicit image-handling rule → images ride along on every turn.
8. MCP servers enabled per-machine, not per-project → unused servers add per-turn descriptor tax.

---

## New / Changed Documents

### A. Always-applied rules — TRIM

**`00-core.mdc`** — keep only:
- Project ID + 2-line module overview.
- Hard guardrails (read-only default, approval gating, root-cause rule, abstraction check, when-in-doubt).
- Edge function deploy notes (especially `receipt-preview-v2 --no-verify-jwt`).
- Routing map (table form):
  - Discovery → `12-doc-search`, `08-context-lookup`, `16-tool-batching`
  - DB function edit → `10-function-conventions`
  - Schema change → `09-db-conventions`
  - Auth involved → `11-auth-conventions`
  - Cross-module → `07-abstraction-principles`
  - Close-out → `06-update-docs`
  - Image attached → `18-image-handling`
  - Registry regen → `registry-regenerate` skill

Move OUT of `00-core.mdc`:
- 5-step Context Lookup walkthrough → `08-context-lookup.mdc`.
- Scratchpad/Plan files exclusion list → `08-context-lookup.mdc` or a new `19-scratchpad-exclusion.mdc`.

Target size: ~300–500 tokens (vs current ~3,000).

**`14-no-canvas.mdc`** — keep as is.
**`15-crm-knowledge-mcp.mdc`** — keep as is.

### B. Requestable rules — ADD or UPDATE

| File | Status | Purpose |
|---|---|---|
| `08-context-lookup.mdc` | Update | Absorb 5-step procedure from `00-core.mdc`; add SQL templates; add grep-first pointer to `12-doc-search`. |
| `12-doc-search.mdc` | NEW | Grep-first protocol for large requirement docs (`rg` heading search → offset/limit read). |
| `16-tool-batching.mdc` | NEW | Behavioral rule: emit independent tool calls in a single turn; sequentialize only when B depends on A. |
| `18-image-handling.mdc` | NEW | On image attach, immediately extract facts to text; recommend fresh thread for downstream work. |
| `06-update-docs.mdc` | Update | Add registry update obligations: changes to edge fns/queues/crons/Render services must update `REGISTRY_RENDER.md` in the same task; `REGISTRY_SUPABASE.md` is regenerated daily by cron (per-change regen optional via `registry-regenerate` skill). |
| `09`/`10`/`11`/`07` | Keep | Conventions for write/change phase. Confirm descriptions include strong trigger terms. |
| `02-functions-queues-triggers.mdc` | Keep | Analysis guide. |
| `13-feature-guide-writing.mdc` | Keep | Doc style. |

**Rule description hygiene:** every requestable rule description must contain WHAT + WHEN with trigger terms. Example for `10-function-conventions.mdc`: "Function conventions for writing DB functions. Read when creating, modifying, or reviewing any `bff_*`, `api_*`, `fn_*`, or `trigger_*` function."

### C. New routers (registries)

**`requirements/REGISTRY_SUPABASE.md`** — NEW
- Auto-generated artifact (script: `scripts/regen_registry_supabase.sh`).
- Regenerated **on demand** via the `registry-regenerate` skill. No scheduled cron — the agent refreshes the file at the start of a DB task if it looks stale, and at the close of any task that changed the schema or a function signature. (Earlier plan called for a daily GitHub Actions cron; that was rolled back on 2026-05-12 in favor of on-demand because pg_cron can't commit to git and a GH Actions cron added infra with no extra value over agent-driven refresh.)
- Sections per domain. Each section lists:
  - Tables (one line each)
  - Functions (name + truncated arg list + return type)
  - Triggers (table → trigger name)
- Generation source: query `pg_proc`, `information_schema.tables`, `information_schema.triggers` filtered by domain keyword/prefix patterns from `_index.md`.
- Replaces `INDEX_FUNCTION.md`. Mark `INDEX_FUNCTION.md` deprecated and ignore.
- File size target: ~100KB given ~1000 public functions × ~316 tables. Designed for grep, not full read. Hard ban on full-reading it (in `12-doc-search.mdc`).

**`requirements/REGISTRY_RENDER.md`** — NEW
- Hand-maintained. No generator — `06-update-docs.mdc` mandates an update in the same task whenever an edge function, queue, cron, or Render service changes.
- Sections per domain. Each section lists:
  - Edge functions (Supabase edge fns + Render services)
  - Queues (consumer/producer mapping)
  - Crons (schedule + purpose)
- File size target: <15KB.

### D. Requirement docs — UNCHANGED structure, NEW access protocol

- `requirements/<Domain>.md` remains the authoritative source.
- `requirements/domains/_index.md` remains the keyword router (used via grep only).
- `requirements/domains/<slug>.md` is being **merged into the authoritative `<Domain>.md`** and deleted. Until Phase 6 completes for a given domain, the slug file remains a temporary navigation aid; new content goes directly into the authoritative doc.

### E. Skills — ADD only where multi-file/scripts justify it

| Skill | Reason |
|---|---|
| `.cursor/skills/registry-regenerate/SKILL.md` + `scripts/regen_registry_supabase.sh` | Has a script. Run on schema/function change. Triggered manually or via `06-update-docs.mdc`. |
| `.cursor/skills/requirement-doc-search/SKILL.md` + `examples.md` + `scripts/find_section.sh` | Optional. Wraps the grep-first protocol with a helper script. May be deferred if `12-doc-search.mdc` rule is sufficient. |

Other workflows (bug diagnosis, feature build) stay as rule-level text rather than skills.

### F. MCP profile — TRIM per-project

For Supabase CRM repo, keep enabled:
- `user-supabase`
- `user-crm-knowledge`
- `user-github`

Disable in this repo (re-enable per-task elsewhere):
- `cursor-ide-browser` (frontend testing only)
- `user-mongodb`, `user-mongodb-storefront` (storefront repo)
- `user-n8n`
- `user-web-to-mcp`

`cursor-app-control` is system-level and can stay.

---

## Request Flow (target)

```text
User request
   │
   ▼
Layer 0 — Always-applied rules
   Hard laws + routing map + CRM Knowledge MCP usage
   │
   ▼
Identify request type (build / fix / analyze / plan / meta / migration)
   │
   ▼
Load lookup-phase rules (12-doc-search, 16-tool-batching, 08-context-lookup)
   │
   ▼ (parallel turn 1)
Grep `requirements/domains/_index.md` for user keywords        → domain
+ CRM Knowledge MCP semantic search (concept-level)            → product context
   │
   ▼ (parallel turn 2)
Grep `REGISTRY_SUPABASE.md` for the domain                     → function/table names
Grep `REGISTRY_RENDER.md` for the domain                       → edge fns/queues/crons
Grep heading structure of authoritative `<Domain>.md`          → section map
Supabase MCP introspection on candidate functions/tables       → live signatures
   │
   ▼ (parallel turn 3)
Read scoped sections of authoritative `<Domain>.md`            → exact business rules
Supabase MCP read body of likely-culprit function              → live logic
   │
   ▼
Load build-phase rules (09/10/11/07 as relevant)
Present plan + impact analysis → wait for approval
   │
   ▼
Execute via Supabase MCP / GitHub (Render)
   │
   ▼
Load close-phase rule (06-update-docs)
Update authoritative `<Domain>.md` + CHANGELOG
If function/schema changed → regen `REGISTRY_SUPABASE.md` (registry-regenerate skill)
If Render changed → update `REGISTRY_RENDER.md`
   │
   ▼
Daily cron regenerates `REGISTRY_SUPABASE.md` independently (out-of-band)
```

### Batching policy

Per-turn decision by the agent, governed by `16-tool-batching.mdc`:

- Group all tool calls whose inputs do not depend on another call's output into a single turn.
- Break into a new turn only when call B genuinely needs call A's result.

Examples of batchable:
- Multiple `Grep` patterns on `_index.md` for several terms.
- `Grep` across multiple requirement docs at once.
- Multiple `execute_sql` introspection queries on different tables/functions.
- `resolve_feature_term` + `search_semantic` + `get_feature_context` for CRM Knowledge MCP.
- Reading multiple small files (per-domain summary + relevant requestable rule).

Examples of necessarily sequential:
- Grep returns line numbers → read at offset/limit.
- Identify domain from `_index.md` → grep `REGISTRY_SUPABASE.md` for that domain.
- Get function signature → read function body (only if body needed unconditionally).
- Read business rule → propose fix.
- User approval → execute change.

---

## Routing Matrix (asset → asset)

| From | To (next step) | Trigger |
|---|---|---|
| User request | `00-core.mdc` (auto) | Always |
| `00-core.mdc` | Lookup-phase rules (`12`, `16`, `08`) | Discovery phase begins |
| Lookup-phase rules | `_index.md` (grep) | Always at start of domain task |
| `_index.md` | `REGISTRY_SUPABASE.md` + `REGISTRY_RENDER.md` | After domain identified |
| Registries | Supabase MCP | Got candidate function/table names |
| `_index.md` (in parallel) | CRM Knowledge MCP | Product/feature/concept question |
| `_index.md` (in parallel) | `requirements/<Domain>.md` via grep | Need exact business rule wording |
| Discovery complete | Build-phase rules (`09`, `10`, `11`, `07`) | About to write/change |
| Build-phase rules | Plan → approval | Always before execute |
| Approval | Supabase MCP / GitHub | Execute change |
| Execute complete | `06-update-docs.mdc` | Always at close |
| `06-update-docs.mdc` | `registry-regenerate` skill | DB function/schema changed |
| `06-update-docs.mdc` | `<Domain>.md` + `CHANGELOG.md` | Always at close |
| Image attached | `18-image-handling.mdc` | At attach time |

---

## Implementation Tasks (ordered)

### Phase 1 — Foundations (do first)

1. [ ] Trim `00-core.mdc` to laws + routing only. Target ~400 tokens.
2. [ ] Update `08-context-lookup.mdc` to absorb the 5-step procedure + SQL templates.
3. [ ] Create `12-doc-search.mdc` with grep-first protocol for large requirement docs.
4. [ ] Create `16-tool-batching.mdc` with parallel-when-independent rule.
5. [ ] Confirm every requestable rule description contains strong trigger terms.

### Phase 2 — Registry layer

6. [ ] Design `REGISTRY_SUPABASE.md` format (per-domain sections, line-format spec).
7. [ ] Write `scripts/regen_registry_supabase.sh` that queries `pg_proc` + `information_schema` via Supabase MCP and emits the registry.
8. [ ] Create `.cursor/skills/registry-regenerate/SKILL.md` referencing the script.
9. [ ] Generate first `REGISTRY_SUPABASE.md` from live DB.
10. [ ] Hand-create initial `REGISTRY_RENDER.md` from current Render services + Supabase edge functions.
11. [ ] Update `06-update-docs.mdc` to require registry update on relevant changes.
12. [ ] Mark `INDEX_FUNCTION.md` deprecated; add note in `06-update-docs.mdc` and `08-context-lookup.mdc`.

### Phase 3 — Behavioral rules

13. [ ] Create `18-image-handling.mdc` (extract-to-text early; recommend fresh thread).

### Phase 4 — Optional skill polish

14. [ ] Decide whether to add `.cursor/skills/requirement-doc-search/` (only if `12-doc-search.mdc` rule alone is insufficient in practice).

### Phase 5 — MCP profile

15. [ ] Verify per-project MCP enablement: keep `user-supabase`, `user-crm-knowledge`, `user-github`. Disable others for this repo.

**Status:** `.cursor/mcp.json` exists with empty `mcpServers` (this project inherits the global MCP profile). To trim per-project, the user must either (a) populate `.cursor/mcp.json` with only the desired servers, or (b) toggle servers off in Cursor Settings → MCP for this workspace. Recommended set for the Supabase CRM workspace:

- ✅ `user-supabase` (always needed)
- ✅ `user-crm-knowledge` (product knowledge)
- ✅ `user-github` (PR / CI work)
- ⚪ `cursor-app-control` (system-level; harmless to keep)
- ❌ `cursor-ide-browser` (frontend testing only)
- ❌ `user-mongodb`, `user-mongodb-storefront` (other repos)
- ❌ `user-n8n` (other workflows)
- ❌ `user-web-to-mcp` (occasional)

Action for owner: open Cursor Settings → MCP and disable the four `❌` servers for this workspace. No code change required.

### Phase 6 — Content consolidation sweep (multi-pass)

Merge each `requirements/domains/<slug>.md` into its authoritative `<Domain>.md` and delete the slug file. Do this in batches; not part of the architecture refactor pass.

For each domain:
- [ ] Find the authoritative source (read `Source:` line at the top of the slug file)
- [ ] Move the **Section TOC** (FE-Relevant Sections table) into the authoritative doc near the top
- [ ] Drop the Functions/Tables list — that role belongs to `REGISTRY_SUPABASE.md`
- [ ] Move any business-rule summary that adds context beyond the source doc into the source doc, otherwise drop
- [ ] Update `requirements/domains/_index.md` to point at `requirements/<Domain>.md` instead of the slug file
- [ ] Delete `requirements/domains/<slug>.md`
- [ ] CHANGELOG entry

Domains pending merge (one per row):
- [ ] action-macro-shared → ?
- [ ] activity-earning → `Activity_Earning.md`
- [ ] admin-panel → `Admin_Panel.md` (if exists, else create)
- [ ] authentication → `Authentication.md`
- [ ] bigcommerce-storefront-api → ?
- [ ] cs-* (15+ files) → `CS_*.md` (one-to-one mapping)
- [ ] currency → `Currency.md`
- [ ] customer-import → `Customer_Import.md` (if exists)
- [ ] display-settings → ?
- [ ] event-promotion → `Event_Promotion.md` (if exists)
- [ ] forms-user-profile → `Forms.md`
- [ ] internal-knowledge → ?
- [ ] mission → `Mission.md`
- [ ] purchase-transaction → `Purchase_Transaction.md`
- [ ] referral → `Referral.md`
- [ ] resource-content-shared → ?
- [ ] reward → `Reward.md`
- [ ] signup-code-validation → `Signup_Login.md` (likely)
- [ ] signup-login → `Signup_Login.md`
- [ ] store-classification → ?
- [ ] tag-persona → ?
- [ ] tier → `Tier.md`
- [ ] translation → ?
- [ ] universal-action-system-shared → ?

---

## Resolved Decisions

1. **Registry regen cadence:** On-demand via the `registry-regenerate` skill, not a scheduled cron. The agent regenerates at the start of a DB task if the registry looks stale, and at the close of any task that changed the schema or a function signature. (Original plan called for a daily GitHub Actions cron; that was implemented and then rolled back on 2026-05-12 — pg_cron can't commit to a git repo, and GH Actions cron added infra/secret management with no advantage over agent-driven refresh, which only runs when work is actually happening.)
2. **Per-domain slug docs (`requirements/domains/<slug>.md`):** Merge into authoritative `<Domain>.md`. The merge target is a Section TOC + Functions/Tables links inside the authoritative doc. The per-domain slug file is deleted once content is merged. Because there are ~40 slug files, this is tracked as **Phase 6 — Content Consolidation Sweep** and executed in batches, not in the architecture pass.
3. **Thread checkpoint rule:** Not adopted. Long-thread management is left to operator judgement; no `17-thread-checkpoint.mdc` is created.
4. **Render registry generator:** Not built. `REGISTRY_RENDER.md` is hand-maintained. `06-update-docs.mdc` is updated so any change to an edge function, queue, cron, or Render service triggers a `REGISTRY_RENDER.md` update in the same task.
5. **`00-core.mdc` routing map:** Mentions both requestable rules and skills, in a single table with a Trigger column.

---

## Success Criteria

- Average tokens per turn in routine tasks reduced by 30–50% vs current baseline.
- `INDEX_FUNCTION.md` and full `<Domain>.md` reads disappear from normal task flows.
- Independent tool calls observably batch into single turns in agent traces.
- Registry stays in sync (no stale function/table names) — verified by agents finding the right names without falling back to MCP `LIKE` discovery.
- Per-domain slug files removed once Phase 6 sweep completes; `_index.md` and authoritative docs are the only narrative-tier docs.

---

## Handoff Notes for Next Thread

- Start by reading this file in full.
- Then read `00-core.mdc`, `08-context-lookup.mdc`, `06-update-docs.mdc` (the three files that change most).
- Confirm Phase 1 tasks before starting Phase 2.
- Registry script (Task 7) needs example output before approval — draft a small section first.
- Coordinate any rule description changes against the `agent_requestable_workspace_rules` block exposed to the agent (descriptions are the discovery surface).
