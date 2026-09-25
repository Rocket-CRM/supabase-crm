# rocket-eng Plugin v2 — Cross-Repo Execution Plan (2026-08-10)

**Status:** Ready for a fresh thread. Attach this file as the first message.  
**Task:** Enhance `Rocket-CRM/rocket-agent-plugins` / plugin `rocket-eng` so one Cursor window can **plan + diagnose + edit + commit** across standard local clones — without project-hopping handoff prompts.  
**Prior art:** v1 shipped in [Rocket engine plugin execution](e7e27778-5007-44ef-90f5-04fbc9eac70f); handoff was `.cursor/plans/rocket-eng-plugin-execute-20260810.md`.

---

## Verdict

v1 is strong for **Knowledge-first think / diagnose** (GitHub remotes, no product wiki in plugin). v2 adds **local execution** under a **team path convention**, plus **L4a routers for CS and AMP** (same shape as FuturePark). Optional `.code-workspace` files are **not** required — skip them.

**Meta already partially done:** L1 now includes **Convention over portable abstraction (small team)** + eng path example in `01-design-judgment.mdc` (local edit; may need commit/push if not pushed yet).

---

## Why (problem this solves)

Today: plan backend in Supabase CRM → paste prompt → run in loyalty-admin / loyalty-user / hub. Cross-repo features feel ununified.

Target: install `rocket-eng` → open a multi-root (or add folders) Cursor window → one thread routes surfaces, edits the right clone, commits per remote, pushes only when asked.

---

## Design constraints (do not violate)

1. **Convention over portable abstraction** (L1) — small team agrees on one layout; do **not** build path-detection / N-layout resolution.
2. **Canonical path:** `~/Documents/rocket/<folder>` (home-relative `~/`, never `/Users/<one-person>/...`).
3. **One clone per remote** — ban duplicates (`Documents/rocket/loyalty-admin` vs `~/Documents/rocket/loyalty-admin`, `loyalty-app` vs `loyalty-user`, `cs-ai-service-tmp`, etc.).
4. **Diagnose without clones still OK** — Knowledge + MCP + GitHub. Build requires the relevant folders present (or print exact `git clone` into `~/Documents/rocket/`).
5. **No product wiki bodies** in plugin — Knowledge / live MCP / thin hub docs on demand.
6. **Soft pack routing** — load L4a for the product in play; do not alwaysApply every orch pack.
7. **Push only on explicit user ask**; commit per owning repo; backend still Supabase MCP.
8. **Shopify L4** — still out of this plan unless user expands scope (same port pattern later).

---

## Team path convention (document in plugin README + L0/L2 execution)

| Folder under `~/Documents/rocket/` | GitHub remote | Notes |
|------------------------------------|---------------|--------|
| `supabase-crm` | CRM requirements workspace (current `Supabase CRM`) | registries + domain docs; MCP for live DB |
| `loyalty-admin` | `Rocket-CRM/loyalty-admin` | admin FE |
| `loyalty-user` | `Rocket-CRM/loyalty-user` | member FE (rename from `loyalty-app` if needed) |
| `futurepark-upload-receipt` | `Rocket-CRM/futurepark-upload-receipt` | FP hub + Render OCR eval |
| `messaging-service` | `Rocket-CRM/messaging-service` | shared CS/AMP/CRM send |
| `cs-ai-service` | `Rocket-CRM/cs-ai-service` | CS AI Render |
| `cs-orchestration` | `Rocket-CRM/cs-orchestration` | today’s `CS Module` hub |
| `amp-ai-service` | `Rocket-CRM/amp-ai-service` | AMP AI Render |
| `amp-orchestration` | optional `Rocket-CRM/amp-orchestration` | today’s `amp-marketing-orchestrator` |
| `shopify-loyalty` | Shopify hub | L4 later |
| `rocket-agent-plugins` | `Rocket-CRM/rocket-agent-plugins` | this plugin |

**Operator move (outside plugin code, call out in README):** Rangwan (and teammates) relocate/rename clones into this tree once; delete duplicates. Not blocking for authoring rules that *describe* the convention.

**Do not** add team `.code-workspace` files in this plan — optional later; File → Add Folder is enough.

---

## Architecture delta (v1 → v2)

```text
L0  always-on     eng protocol (+ point at local execution + path convention)
L1  requestable   design judgment (ALREADY: convention-over-abstraction)
L2  requestable   surfaces unchanged + NEW local-execution pack/skill
L3  on demand     Knowledge + Supabase (+ GitHub when needed)
L4a requestable   FuturePark | CRM BE | NEW CS | NEW AMP
L4b requestable   FP prompt / OCR eval only (no new L4b for CS/AMP in this plan)
```

---

## Deliverables (files to add/change)

### A. Commit pending L1 (if unpushed)

- `plugins/rocket-eng/rules/01-design-judgment.mdc` — already contains **Convention over portable abstraction**; include in v2 commit.

### B. New — local execution

| Path | Role |
|------|------|
| `plugins/rocket-eng/rules/05-local-execution.mdc` | Requestable (or alwaysApply: false, load on build/fix/ship). Path table, clone-if-missing, sync before edit, edit owning root only, commit-per-repo, push policy, Supabase MCP vs git. |
| Optional: `plugins/rocket-eng/skills/cross-repo-ship/SKILL.md` | Only if the rule is too long — prefer **one rule first**; skill only if ship checklist is heavy. |

**Must include in `05-local-execution`:**

- Resolve paths as `~/Documents/rocket/<folder>` only.
- If folder missing: print `git clone git@github.com:Rocket-CRM/<repo>.git ~/Documents/rocket/<folder>` (exact).
- Before sibling edits: `cd … && git fetch origin && git status` (+ pull if behind/clean).
- Never edit known-ban duplicates (list: old `Documents/rocket/loyalty-admin`, `cs-ai-service-tmp`, hub `render-service/` for AMP, etc.).
- Commit message / push: only when user asks; push remote = table above; usually `main`.
- Multi-root: agent may edit any open folder that matches the convention; if folder not in workspace but exists on disk under convention, still edit there (same as today’s hubs) — **do not** invent alternate path search.

### C. Enhance L0

`plugins/rocket-eng/rules/00-eng-protocol.mdc`:

- Replace/soften “No absolute home paths / remotes only” with: **team local root `~/Documents/rocket/`** + GitHub remotes for identity; diagnose can skip clones.
- Classify table: Build/fix → load L1 + L2 surfaces + **`05-local-execution`** + L4a if multi-surface product.
- Remotes table → expand to include CS/AMP/messaging folders (pointer to L4a + `05`).
- Architecture table: add CS/AMP L4a; add `05-local-execution`.

### D. New L4a — CS

`plugins/rocket-eng/rules/44-orch-cs.mdc` — port from (do not copy wiki bodies):

- `/Users/rangwan/CS Module/AGENTS.md`
- `/Users/rangwan/CS Module/MONOREPO.md`
- `/Users/rangwan/CS Module/.cursor/rules/05-cross-repo.mdc`
- Pointers only: Edge JWT / MCP Edge workflow → L2 `21-backend-functions` (already has FP JWT family; keep CS verify_jwt notes thin or point at shared L2)
- Surfaces: admin `cs-*`, Supabase `cs_*` / `cs_bff_*` / `cs_fn_*`, `cs-ai-service`, `messaging-service`, hub docs
- Paths rewritten to `~/Documents/rocket/...`
- Product truth → Knowledge (`CS_*` / requirements), not hub doc dumps
- Conflict: live Supabase > Knowledge > hub pointers

### E. New L4a — AMP

`plugins/rocket-eng/rules/45-orch-amp.mdc` — same port pattern from:

- `/Users/rangwan/amp-marketing-orchestrator/AGENTS.md`
- `MONOREPO.md`
- `.cursor/rules/05-cross-repo.mdc`
- Surfaces: admin AMP routes, `amp_*` / BFFs, `amp-ai-service`, messaging; ban hub `render-service/`
- Paths → `~/Documents/rocket/...`

### F. Refresh existing L4a

- `40-orch-futurepark.mdc` — replace remote-only language with `~/Documents/rocket/<folder>` for member/admin/hub where execution applies; keep Knowledge/MCP conflict order.
- `42-orch-crm.mdc` — mention local `supabase-crm` for registries/docs; MCP still for live DB.

### G. README

`rocket-agent-plugins/README.md`:

- v2 purpose: single-window cross-repo build under `~/Documents/rocket/`
- Clone map table
- Deduplicate instructions (one-time operator)
- When L4a CS/AMP load
- Marketplace reinstall / Auto Refresh
- Explicit: `.code-workspace` not required

### H. Hub stubs (thin pointers — optional but recommended in same PR or follow-up)

Update AGENTS.md first lines (like FuturePark already):

- `~/Documents/rocket/cs-orchestration` (after move) or current CS Module until moved
- `amp-marketing-orchestrator` / amp-orchestration
- Prefer plugin packs; keep hubs as doc shells

**Do not** delete hub rules in this plan — stub + “prefer rocket-eng”; full hub rule retirement is a later cleanup once multi-root alwaysApply collision is felt.

### I. Marketplace metadata

- Bump plugin version in `.cursor-plugin/plugin.json` / marketplace.json (e.g. `1.1.0`)
- Description mentions cross-repo local execution + CS/AMP orch

---

## Out of scope (this plan)

- Shopify L4 (`41-orch-shopify`)
- New CS/AMP L4b skills (voice eval, Inngest debug) unless trivial pointers
- Physically moving Rangwan’s clones (document checklist only; operator does move)
- Team `.code-workspace` files
- Writing Principles / proposals plugins
- Regenerating CRM registries

---

## Execute order (fresh thread)

1. Confirm local plugin repo at `~/Documents/rocket/rocket-agent-plugins` or move note; `git status` / pull `main`.
2. Ensure L1 convention principle is present; commit with rest if needed.
3. Author `05-local-execution.mdc`.
4. Patch `00-eng-protocol.mdc` (path convention + route to `05` + CS/AMP in architecture).
5. Author `44-orch-cs.mdc` from CS hub sources (paths normalized).
6. Author `45-orch-amp.mdc` from AMP hub sources.
7. Patch `40-orch-futurepark.mdc` + `42-orch-crm.mdc` for `~/Documents/rocket/` execution paths.
8. Update README + marketplace version/description.
9. Optional: stub CS/AMP hub `AGENTS.md` pointers.
10. Commit + push `Rocket-CRM/rocket-agent-plugins`.
11. User: Team Marketplace Auto Refresh → reinstall/reload `rocket-eng`.
12. Smoke (same window, folders under convention if available):
    - Product Q&A → Knowledge only (no local-execution noise)
    - “Build FP upload change across admin + member” → L4a FP + `05` + L2 FE
    - “CS inbox BFF + admin page” → L4a CS + `05` + L2
    - “AMP workflow + amp-ai-service” → L4a AMP + `05`
    - Missing folder → exact clone command printed
13. Operator checklist (separate): relocate clones to `~/Documents/rocket/`, delete duplicates.

---

## Acceptance criteria

- [ ] Plugin documents one path convention: `~/Documents/rocket/<folder>` + one clone per remote
- [ ] Build/fix threads load local-execution: sync → edit correct root → commit per repo → push only on ask
- [ ] Diagnose/plan still works without all clones open
- [ ] L4a CS and AMP exist and route surfaces without embedding CS_*/AMP product wiki bodies
- [ ] L1 retains convention-over-abstraction with eng path example
- [ ] No `.code-workspace` requirement
- [ ] README clone map + dedupe guidance for teammates
- [ ] Pushed; marketplace bump ready for Default On / Auto Refresh

---

## Critical context for next thread

- Plugin repo: `Rocket-CRM/rocket-agent-plugins` (local often `Documents/rocket/rocket-agent-plugins` until moved under `~/Documents/rocket/`)
- Supabase project: `wkevmsedchftztoolkmi`
- CS source hubs: `/Users/rangwan/CS Module` (rules + MONOREPO)
- AMP source hubs: `/Users/rangwan/amp-marketing-orchestrator`
- FP already stubbed toward plugin; mirror for CS/AMP
- Discussion thread that defined this: Project structure / plugin path convention (this plan’s parent chat)

---

## Next exact step

Open a fresh Cursor thread, attach **this file**, then: pull `rocket-agent-plugins` `main`, author `05-local-execution.mdc` first, then L0 patch, then `44`/`45` L4a ports.
