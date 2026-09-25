# rocket-eng Plugin — FINAL Execute Handoff (2026-08-10)

**Status:** Ready for a fresh thread. Attach this file as the first message.  
**Task:** Create `Rocket-CRM/rocket-agent-plugins`, author Cursor Plugin `rocket-eng`, publish via Team Marketplace, dogfood the marketplace install path.

---

## Verdict

One **Cursor Plugin** (`rocket-eng`) for eng + QA: understand, plan, debug, build, test-plan — **without requiring local clones** for orchestration thinking (code write still needs clone or Cloud Agent).

**Format:** Cursor Plugin (`.cursor-plugin/plugin.json` + rules). Not Agent-Plugins-only (that can’t ship `.mdc` rules).

**Meta:** principles > rigid rule forests; complexity budget; soft pack routing (miss = worse answer, not broken).

**v1 L4 products only:** FuturePark + CRM backend orchestration. **Shopify L4 out of v1.**

---

## Architecture (5 levels)

```text
L0  always-on     eng protocol (classify, Knowledge, hygiene, route)
L1  requestable   design judgment (plan/design/build only — not QA-understand)
L2  requestable   surface packs: CRM Core | Backend | FE Admin | FE Member | FE Shared | QA skill
L3  on demand     Knowledge MCP + Supabase MCP (facts — not plugin bodies)
L4  requestable   orchestration + domain ops for: FuturePark | CRM BE
                  (FE admin/user conventions are L2, not L4 product packs)
```

| Level | What it is | What it is NOT |
|-------|------------|----------------|
| L0 | How to run every eng thread | Product wiki |
| L1 | Simple/elegant design principles | Feature-specific engines by name |
| L2 | How to work on a *surface* (Polaris vs shadcn vs DB/BFF) | FuturePark product chapters |
| L3 | Product + live truth | Copied into plugin |
| L4a | Multi-surface router (remotes, read order) | Duplicate of FuturePark.md |
| L4b | Domain agent procedures (prompt edit, eval run_id) | Canonical feature narrative |

---

## Install / author loop (team-real path)

1. Local clone: e.g. `~/Documents/rocket/rocket-agent-plugins` → remote `Rocket-CRM/rocket-agent-plugins`.
2. Edit under `plugins/rocket-eng/` → commit → push.
3. Dashboard → Plugins → Team Marketplace → import repo → **Default On** for eng → Auto Refresh.
4. You + teammates: Customize → Install → **user** scope → auth Knowledge (+ Supabase/GitHub as needed).
5. Symlink to `~/.cursor/plugins/local` is optional only; prefer marketplace dogfood.

---

## Repo layout (create this)

```text
rocket-agent-plugins/
  README.md                          # teammate: install, MCP auth, clone vs not
  .cursor-plugin/marketplace.json
  plugins/
    rocket-eng/
      .cursor-plugin/plugin.json
      rules/
        00-eng-protocol.mdc          # L0 alwaysApply: true
        01-design-judgment.mdc       # L1
        10-crm-core.mdc              # L2
        20-backend-db.mdc            # L2
        21-backend-functions.mdc     # L2 (incl. Edge MCP deploy + JWT)
        30-fe-admin.mdc              # L2
        31-fe-member.mdc             # L2
        32-fe-shared.mdc             # L2 (study/visual/playwright)
        40-orch-futurepark.mdc       # L4a
        42-orch-crm.mdc              # L4a (Supabase + Render pointers)
        43-fp-prompt-editing.mdc     # L4b
      skills/
        test-planning/SKILL.md
        fp-ocr-eval-run/SKILL.md     # L4b
      mcp.json                       # Knowledge MCP; GitHub optional
```

**Out of v1:** `41-orch-shopify.mdc`, proposals, CS/Sales, mockup/deck pipelines, Syngenta one-offs.

---

## Document merge map (pull from existing → enhance/consolidate)

### L0 — `00-eng-protocol.mdc`

| Pull from | Action |
|-----------|--------|
| CRM `.cursor/rules/00-core.mdc` | Split: always-on protocol + hard laws summary; long routing → L4a CRM |
| CRM `12`, `15`, `16`, `17`, `18`, `20`, `14` | Port/condense into one short always-on file |
| admin `response-style`, hub `02-communication`, app `20-output-quality` | **Dedupe** into one answer-shape section |
| app `10-knowledge-mcp-retrieval` | Merge Knowledge protocol (eng depth includes technical_reference) |

**Enhance:** classify → route L1/L2/L4; Knowledge first for understand; no requirements full-read always-on; GitHub remotes not `/Users/...`.

---

### L1 — `01-design-judgment.mdc`

| Pull from | Action |
|-----------|--------|
| CRM `07-abstraction-principles.mdc` | Merge |
| `loyalty-admin/ProjectDocs/supabase_backend_project_principles.md` | Merge |
| Chat principles (simple/elegant, complexity budget, principles>rules, ceremony≠risk, FE gate security, generative scaffolds) | **Author** into this file |

**Enhance:** unify+discriminator; no speculative tables; shared capability before new path — **no named Currency/two-point law**.

---

### L2 — Surface packs

#### `10-crm-core.mdc`

| Pull from | Action |
|-----------|--------|
| CRM `docs/PROJECT_CONTEXT_STRUCTURE.md` | Condense cross-surface context |
| CRM `08-context-lookup.mdc` | Condense (implement path) |
| app `verify-data-before-coding`, `docs/ai/project-boundaries.md` | Merge FE↔BE contract boundary |

#### `20-backend-db.mdc`

| Pull from | Action |
|-----------|--------|
| CRM `09-db-conventions.mdc` | Port |
| CRM `05` schema-relevant bits | Merge if needed |

**Enhance:** section “Schema design principles” — unify + type column; no good-to-have tables.

#### `21-backend-functions.mdc`

| Pull from | Action |
|-----------|--------|
| CRM `10`, `11`, `02`, `06` | Port/consolidate |
| FP hub `04-edge-function-jwt`, `06-edge-function-mcp-workflow` | Merge (Supabase Edge + Render-related deploy discipline) |

**Enhance:** “Shared capability first” as discovery principle (not function allowlist); keep envelope `p_language` i18n.

#### `30-fe-admin.mdc` (loyalty-admin)

| Pull from | Action |
|-----------|--------|
| `~/Documents/rocket/loyalty-admin/.cursorrules` | Port identity + workflow triggers (trim absolute paths) |
| Rules: `nextjs-supabase`, `polaris-patterns`, `server-actions-patterns`, `config-api-patterns`, `new-page-workflow`, `requirement-docs` (retarget Knowledge MCP), `figma-workflow`, `weweb-reference`, `feedback-impact-check`, `pre-deployment` | Consolidate into one or few `.mdc` sections / files under 30 |
| `ProjectDocs/WEWEB_ADMIN_INDEX.md` | Pointer only (GitHub path) |

**Skip:** Syngenta, Shopify ProjectDocs, solar-icons (keep repo-local), FE_docs product chapters (Knowledge).

#### `31-fe-member.mdc` (loyalty-app / loyalty-user)

| Pull from | Action |
|-----------|--------|
| `AGENTS.md` | Trim — drop mockup/deck bulk |
| `00-project-identity`, `project-context`, component/patterns/`nextjs-supabase`, hydration, Knowledge retrieval | Port |
| `docs/ai/feature-map.md`, `project-boundaries.md` | Port pointers |

**Skip:** `docs/ai/deck-*`, `home-pack-*`, figma mockup pipelines (v1).

#### `32-fe-shared.mdc`

| Pull from | Action |
|-----------|--------|
| Both repos: `study-before-building`, `verify-visual-changes`, `playwright-testing` | Port once |
| app `fix-then-abstract` | Port |

#### `skills/test-planning/SKILL.md`

| Pull from | Action |
|-----------|--------|
| — | **New:** scenarios / exists-vs-gap from Knowledge MCP |

---

### L4a — Orchestration (v1 products only)

#### `40-orch-futurepark.mdc`

| Pull from | **Consolidate into one router** |
|-----------|----------------------------------|
| hub `AGENTS.md`, `MONOREPO.md`, `FEATURES.md`, `docs/SOURCE_OF_TRUTH.md` | Merge; replace `/Users/rangwan/...` with GitHub remotes |
| hub `00-core.mdc`, `05-cross-repo.mdc` | Merge routing tables |

**Must include:**
- Surfaces: member (`loyalty-user`), admin approve (`loyalty-admin`), Edge/RPC (Supabase), Render OCR eval (`futurepark-upload-receipt`), product → Knowledge `FuturePark`
- Remotes: `Rocket-CRM/loyalty-user`, `loyalty-admin`, `futurepark-upload-receipt`
- Conflict: live Supabase > GitHub `docs/CURRENT_STATE.md` > Knowledge > pointers
- Pointers to L4b: prompt edit → `43-…`; eval run_id → `fp-ocr-eval-run`
- **Do not** paste FuturePark.md body; **do not** ingest CURRENT_STATE body (reference GitHub path only)

**Enhance:** hub local `AGENTS.md` → thin stub pointing at this pack (after plugin ships).

#### `42-orch-crm.mdc` (Supabase BE + Render)

| Pull from | Action |
|-----------|--------|
| CRM `00-core` project ID + MCP-only deploy hard laws | Port |
| Pointers: `REGISTRY_SUPABASE.md`, `REGISTRY_RENDER.md`, `domains/_index.md` | Grep protocol — never ship registry bodies |
| `PROJECT_CONTEXT_STRUCTURE.md` | Condense |

**Must include:** project `wkevmsedchftztoolkmi`; Edge via MCP; Render services discovered via REGISTRY_RENDER grep / Render MCP when needed; product docs → Knowledge not full-read Domain.md.

---

### L4b — FuturePark domain ops

| Plugin file | Pull from | Notes |
|-------------|-----------|-------|
| `43-fp-prompt-editing.mdc` | hub `01-prompt-editing.mdc` | Live principles from DB `__editing_principles__`; product SECTION → Knowledge |
| Optional datetime ops | hub `03-receipt-datetime-policy.mdc` | Merge short ops into 43 or separate `44-fp-datetime.mdc` if needed |
| `skills/fp-ocr-eval-run/SKILL.md` | hub `ocr-eval-run-summary/SKILL.md` | run_id → diagnose / group; rewrite hub-relative rule refs to plugin rule names |

**v1.1 (not blocking):** `07-store-matching-llm`, `manual-approve-reason-audit` skill.

---

## Explicit: do not put in plugin

| Content | Why |
|---------|-----|
| `requirements/FuturePark.md` / domain MD bodies | Knowledge MCP |
| Hub `CURRENT_STATE.md` body | Volatile; read from GitHub when needed |
| Shopify orchestration | Out of v1 |
| Proposal / writing / demo generator rules | Deferred |
| loyalty-app mockup/deck AI docs | Specialized, not eng core |

---

## Execute sequence (next thread — do in order)

1. Create GitHub private repo `Rocket-CRM/rocket-agent-plugins` + local clone.
2. Scaffold `plugins/rocket-eng` + root `marketplace.json` + README (this architecture).
3. Write **L0** `00-eng-protocol.mdc` (keep short).
4. Write **L1** `01-design-judgment.mdc`.
5. Port **L2** Backend (`20`, `21` with enrichments) + `10-crm-core`.
6. Port **L2** FE Admin + FE Member + FE Shared (consolidate; no absolute home paths).
7. Port **L4a** `40-orch-futurepark` + `42-orch-crm`.
8. Port **L4b** prompt-editing + `fp-ocr-eval-run`; wire L4a references.
9. Add `test-planning` skill.
10. Push → Team Marketplace import → Default On → install yourself (user scope).
11. Smoke **without** hub/admin/app clones open:
    - Feature understand → Knowledge only
    - “FuturePark upload — which surfaces?” → L4a
    - Paste OCR `run_id` → L4b skill
    - Prompt fragment edit → L4b rule
    - Admin Polaris page / member component → L2 FE packs
    - New BFF/table → L1 + L2 Backend
12. Thin hub `AGENTS.md` (+ optional admin/app stubs) to point at plugin packs.
13. Teammate README: MCP auth, when to clone for ship.

---

## Success criteria

- [ ] One marketplace install → eng workflow across CRM / admin / user / FuturePark without those repos locally (plan/diagnose).
- [ ] Product facts from Knowledge; orchestration from L4a; FP ops from L4b; conventions from L2.
- [ ] QA understand does not load design/L4b spam.
- [ ] No `/Users/rangwan/` paths in plugin rules.
- [ ] Shopify not in v1.
- [ ] Hub CURRENT_STATE / FuturePark.md not duplicated into plugin bodies.

---

## Next exact step

```bash
# In next thread: create repo + scaffold
mkdir -p ~/Documents/rocket/rocket-agent-plugins/plugins/rocket-eng/.cursor-plugin
mkdir -p ~/Documents/rocket/rocket-agent-plugins/plugins/rocket-eng/{rules,skills}
# Write plugin.json + marketplace.json + README
# Then author 00-eng-protocol.mdc and 01-design-judgment.mdc first
```

Sources to keep open while porting (read scoped, don’t dump):

- CRM: `.cursor/rules/00-core.mdc`, `09`, `10`, `15`, `20`
- Hub: `AGENTS.md`, `docs/SOURCE_OF_TRUTH.md`, `MONOREPO.md`, `01-prompt-editing.mdc`, `skills/ocr-eval-run-summary/SKILL.md`
- Admin: `.cursorrules` + polaris/server-actions/config-api rules
- App: `AGENTS.md` (trim), `project-context.mdc`, `component-standards.mdc`, `docs/ai/feature-map.md`
