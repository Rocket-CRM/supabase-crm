# Canonical Code Roots + Legacy Path Retarget (2026-08-10)

**Status:** Executed 2026-08-10 (Phase 0–3). Duplicates left for user delete approval.  
**Task:** (1) Move pure code/service clones under `~/Documents/rocket/`, (2) keep legacy Cursor hubs/projects on their **existing local workflows**, (3) retarget those workflows so sibling **code** edits hit the new paths only, (4) use the agent plugin only in a **new** Cursor window — do **not** migrate legacy hubs onto `rocket-eng`.

**Related:** Plugin already at v1.1 with `05-local-execution` + CS/AMP L4a (`Rocket-CRM/rocket-agent-plugins`). Prior plans assumed stubbing hubs onto the plugin — **superseded by this coexistence model.**

---

## Verdict / policy (do not violate)

| Surface | Workflows | Code edits |
|---------|-----------|------------|
| **New** Cursor project (multi-root or empty + add folders) | Team Marketplace **`rocket-eng`** | `~/Documents/rocket/<folder>` |
| **Legacy** hubs & FE projects (CS Module, AMP orch, Shopify, FP hub, Supabase CRM window, loyalty-admin window, …) | **Keep** local `AGENTS` / `.cursor/rules` / MONOREPO / SETUP docs | **Retarget** sibling code paths → `~/Documents/rocket/…` |

- Do **not** delete or gut legacy workflow forests for this task.  
- Do **not** require legacy windows to install/use the plugin.  
- Do **not** maintain two clones of the same remote — one under `~/Documents/rocket/` only.  
- Hub **docs that are not workflows** (CURRENT_STATE, FEATURES product pointers) stay in the hub; optional later cleanup out of scope.  
- Prefer home-relative form in **new** text: `~/Documents/rocket/...`. When replacing old absolute paths, either `~/Documents/rocket/...` or `/Users/rangwan/Documents/rocket/...` is fine for Rangwan’s Mac; prefer `~/Documents/rocket/` for teammate-safe docs.

---

## Phase 0 — Operator: create tree + move code (no plugin rewrite)

```bash
mkdir -p ~/Documents/rocket
```

### Move / rename (keep = canonical)

| From (current) | To |
|----------------|-----|
| `~/Documents/rocket/supabase-crm` | `~/Documents/rocket/supabase-crm` |
| `~/Documents/rocket/loyalty-admin` | `~/Documents/rocket/loyalty-admin` |
| `~/Documents/rocket/loyalty-user` | `~/Documents/rocket/loyalty-user` |
| `~/Documents/rocket/futurepark-upload-receipt` | `~/Documents/rocket/futurepark-upload-receipt` |
| `~/Documents/rocket/messaging-service` | `~/Documents/rocket/messaging-service` |
| `~/Documents/rocket/cs-ai-service` | `~/Documents/rocket/cs-ai-service` |
| `~/Documents/rocket/amp-ai-service` | `~/Documents/rocket/amp-ai-service` |
| `~/Documents/rocket/rocket-agent-plugins` | `~/Documents/rocket/rocket-agent-plugins` |

Optional (same tree, not required for CS/AMP day-one):

| From | To |
|------|-----|
| `~/Documents/rocket/crm-event-processors` | `~/Documents/rocket/crm-event-processors` |
| `~/Documents/rocket/crm-knowledge` | `~/Documents/rocket/crm-knowledge` |
| `~/Documents/rocket/rewarding-shopify` (if present) | `~/Documents/rocket/rewarding-shopify` |

### Do **not** move as “code” into rocket (legacy hubs stay put)

Leave these Cursor projects where they are; only **path pointers inside them** change:

- `~/CS Module` (CS hub workflows + docs)
- `~/amp-marketing-orchestrator`
- `~/shopify-loyalty`
- (After move, FP **code** lives under rocket; if you still open a “hub” experience, open `~/Documents/rocket/futurepark-upload-receipt` — same repo, new path. No second FP clone.)

### Delete / stop using (duplicates)

| Path | Action |
|------|--------|
| `~/Documents/rocket/loyalty-admin` | Delete or archive after confirming rocket clone is good |
| `~/Documents/cs-ai-service-tmp` | Delete or archive |
| `~/Documents/futurepark-receipt-upload` | **Do not** rename to FP — remote is `crm-batch-upload`; leave or move separately as `crm-batch-upload` if needed |

**Before each `mv`:** `git status` clean (or stash); close Cursor windows on that folder; after move, reopen from new path.

**Supabase CRM note:** Moving renames the Cursor project root. Re-open `~/Documents/rocket/supabase-crm`. Legacy rules elsewhere that pointed at `Documents/rocket/supabase-crm` must be retargeted in Phase 2.

---

## Phase 1 — New Cursor project (plugin path)

1. Create/open a **new** Cursor window (e.g. open `~/Documents/rocket` or add the code folders you need).  
2. Install / confirm **rocket-eng** v1.1+ from Team Marketplace (user scope).  
3. Do **not** change this in Phase 2 — plugin already documents `~/Documents/rocket/`.  
4. Smoke: build task mentions loyalty-admin → agent uses `~/Documents/rocket/loyalty-admin`.

Out of scope here: writing a `.code-workspace` file (optional).

---

## Phase 2 — Legacy path retarget only (workflows stay)

For each legacy project below: **replace sibling code/docs paths** with the map. Keep rule *behavior* (cross-repo edit permissions, JWT, Edge MCP, etc.).

### Canonical substitution map

| Old (ban after retarget) | New |
|--------------------------|-----|
| `~/Documents/rocket/loyalty-admin` | `~/Documents/rocket/loyalty-admin` |
| `~/Documents/rocket/loyalty-admin` | *(still banned)* → same new path |
| `~/Documents/rocket/loyalty-user` | `~/Documents/rocket/loyalty-user` |
| `~/Documents/rocket/cs-ai-service` | `~/Documents/rocket/cs-ai-service` |
| `~/Documents/rocket/cs-ai-service` | still banned |
| `~/Documents/rocket/amp-ai-service` | `~/Documents/rocket/amp-ai-service` |
| `~/Documents/rocket/messaging-service` | `~/Documents/rocket/messaging-service` |
| `~/Documents/rocket/futurepark-upload-receipt` | `~/Documents/rocket/futurepark-upload-receipt` |
| `~/Documents/rocket/supabase-crm` | `~/Documents/rocket/supabase-crm` |
| `~/Documents/rocket/rewarding-shopify` (if used) | `~/Documents/rocket/rewarding-shopify` |

**Hub self-paths** (leave unless you later move hubs):

- `/Users/rangwan/CS Module` — unchanged  
- `/Users/rangwan/amp-marketing-orchestrator` — unchanged  
- `/Users/rangwan/shopify-loyalty` — unchanged  

Update ban text: “do not use Documents/rocket/loyalty-admin” → “do not use any clone outside `~/Documents/rocket/loyalty-admin`.”

---

### 2A — CS Module (`~/CS Module`)

**Priority files (path tables + always-on rules):**

- `AGENTS.md`
- `MONOREPO.md`
- `FEATURES.md`
- `README.md`
- `RULES.md` (admin path mentions)
- `.cursor/rules/05-cross-repo.mdc`
- `.cursor/rules/00-core.mdc` (if paths)
- `.cursor/rules/08-frontend-conventions.mdc`
- `docs/INDEX.md`
- `docs/conventions/INDEX.md`
- `SETUP_CS_CONVENTIONS.md` (CRM + LA variables)

**Keep:** all workflow rules content; only path strings.

Optional low priority: deep `docs/backend/*` narrative paths — retarget if they hardcode sibling clones; skip pure product prose.

---

### 2B — AMP marketing orchestrator (`~/amp-marketing-orchestrator`)

Same pattern:

- `AGENTS.md`, `MONOREPO.md`, `FEATURES.md`, `README.md`, `RULES.md`
- `.cursor/rules/00-core.mdc`, `05-cross-repo.mdc`, `08-frontend-conventions.mdc`
- `docs/INDEX.md`, `docs/conventions/INDEX.md`, `docs/conventions/SOURCE.md`
- `docs/architecture/AMP_AI_SERVICE.md` (canonical path line)

Still ban hub `render-service/` → point at `~/Documents/rocket/amp-ai-service`.

---

### 2C — FuturePark (`~/Documents/rocket/futurepark-upload-receipt` after move)

**Keep** local FP workflows (`.cursor/rules`, AGENTS, MONOREPO). Retarget siblings:

- admin → `~/Documents/rocket/loyalty-admin`
- member → `~/Documents/rocket/loyalty-user` (not `loyalty-app`)
- CRM requirements → `~/Documents/rocket/supabase-crm/requirements/...`
- “this hub” path → `~/Documents/rocket/futurepark-upload-receipt`

Files: `AGENTS.md`, `MONOREPO.md`, `README.md`, `.cursor/rules/00-core.mdc`, `05-cross-repo.mdc`, `docs/SOURCE_OF_TRUTH.md`, plus doc stubs that only point at CRM paths.

Do **not** strip hub docs into the plugin in this plan.

---

### 2D — Shopify (`~/shopify-loyalty`)

- `.cursor/rules/00-core.mdc`, `02-shopify-audit.mdc`
- `FEATURES.md`, `docs/SOURCE_OF_TRUTH.md`, `docs/SHOPIFY_APP_AUDIT_WORKFLOW.md`, `docs/INDEX.md`
- Other docs that only say “FE at `~/Documents/rocket/loyalty-admin`” — batch replace
- CRM product paths → `~/Documents/rocket/supabase-crm/requirements/...`
- `rewarding-shopify` if present in map

---

### 2E — Supabase CRM (`~/Documents/rocket/supabase-crm` after move)

- Grep `.cursor/` + `requirements/` for `~/Documents/rocket/loyalty-admin`, `loyalty-app`, `futurepark-upload-receipt`, old Documents paths
- Update **agent-facing** path pointers only; do not rewrite product wiki substance
- Plans under `.cursor/plans/` that are historical SETUP scripts: update if still used as paste-prompts (`SETUP_CS_ORCHESTRATION.md` etc.), else leave archive

---

### 2F — FE projects if opened as their own Cursor windows

After move they **are** the rocket folders. Still fix internal absolute refs:

**`loyalty-admin`** (now under rocket):

- `.cursorrules`, `ProjectDocs/*` stubs pointing at shopify hub / CRM / loyalty-app
- `requirements/Shopify.md` / `FuturePark.md` path headers if present (often mirrors — prefer pointing to `supabase-crm` canonical)

**`loyalty-user`** (was `loyalty-app`):

- `.cursor/rules/dev-server.mdc` (`cd …/loyalty-app` → `…/loyalty-user`)
- any other `~/Documents/rocket/loyalty-user` strings

---

## Phase 3 — Verify

```bash
# Exactly one loyalty-admin clone
find ~/Documents/rocket ~/Documents ~/Documents/rocket/loyalty-admin -maxdepth 2 -type d -name 'loyalty-admin' 2>/dev/null

# Remotes match
for d in loyalty-admin loyalty-user cs-ai-service amp-ai-service messaging-service futurepark-upload-receipt supabase-crm; do
  echo "== $d =="; git -C ~/Documents/rocket/$d remote get-url origin 2>/dev/null || echo MISSING
done
```

Grep legacy hubs for **banned** old code paths (should be empty or only in historical changelogs):

```bash
rg -n '~/Documents/rocket/loyalty-admin|~/Documents/rocket/loyalty-user|~/Documents/rocket/cs-ai-service|~/Documents/rocket/messaging-service|~/Documents/rocket/supabase-crm|~/Documents/rocket/loyalty-admin' \
  ~/CS\ Module ~/amp-marketing-orchestrator ~/shopify-loyalty ~/Documents/rocket/futurepark-upload-receipt \
  --glob '*.md' --glob '*.mdc' --glob '.cursorrules'
```

Manual smoke (legacy window): open CS Module → ask to edit CS inbox UI → agent `cd`s / edits `~/Documents/rocket/loyalty-admin`.  
Manual smoke (new window): same with plugin, no hub rules required.

---

## Out of scope

- Migrating legacy hubs onto `rocket-eng` / deleting hub `.cursor/rules`
- Splitting FP hub docs out of `futurepark-upload-receipt` into plugin-only
- Shopify L4 in plugin
- Moving CS Module / AMP / Shopify hub folders themselves under `rocket/`
- Committing/pushing every hub (do push when user asks; group by repo)

---

## Execute order (fresh thread)

1. Confirm policy with user if anything unclear — then **Phase 0** moves (shell), status check each repo.  
2. Phase 1 note only (user opens new window + marketplace).  
3. Phase 2A → 2B → 2C → 2D → 2E → 2F: batched search-replace on path tables; preserve workflow text.  
4. Phase 3 verify greps + one legacy smoke instruction.  
5. Summarize remaining old-path hits (if any) and ask before deleting duplicate folders.

---

## Acceptance criteria

- [x] Code remotes live only under `~/Documents/rocket/<name>` (canonical clones moved; duplicates still on disk pending delete approval)
- [x] Legacy hubs still have full local workflow files
- [x] Legacy path tables / `05-cross-repo` / AGENTS / MONOREPO point siblings at `~/Documents/rocket/…`
- [x] `loyalty-app` string retired in favor of `loyalty-user` folder name (priority path tables; product prose may still say “member app”)
- [x] CRM requirements path updated to `~/Documents/rocket/supabase-crm` where hubs referenced old Documents path
- [x] New plugin-based project is separate; legacy not forced onto plugin
- [x] User asked before any `git push` / destructive delete of old duplicate dirs

---

## Critical context

- Plugin SoT for **new** work: `~/Documents/rocket/rocket-agent-plugins` (after move), marketplace v1.1+  
- Coexistence: plugin window ≠ legacy hub window  
- This plan **supersedes** “stub all hubs to rocket-eng” guidance from the v2 plugin plan  
- User preference (2026-08-10): legacy keeps old workflows; only code path retarget

---

## Next exact step

Fresh thread + this file → run Phase 0: `mkdir ~/Documents/rocket` and move the keep-list clones (start with `loyalty-admin` + `loyalty-user` + `supabase-crm` after clean `git status`).
