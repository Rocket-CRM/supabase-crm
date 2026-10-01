# Agent Context Architecture

> **Generalizable reference for organizing AI agent context across rules, skills, requirement docs, registries, and MCPs — and how requests route between them.**
>
> Companion to `CURSOR_RULES_PRINCIPLES.md` (which covers rule-writing and token economy). This doc focuses on the **asset architecture** (what kinds of files exist, what role each plays) and the **request flow** (how the agent moves between them).
>
> The Supabase CRM project is the reference implementation; the model is intentionally portable to any project where an agent works against multiple sources of truth.

---

## Why This Architecture Exists

A single AI agent thread can easily incur:
- A large per-turn system prompt (rules, tool descriptors, MCP instructions).
- Repeated tool outputs that pin to context for the rest of the thread.
- Sequential discovery turns that each replay full prior context.
- Full reads of large requirement docs when a 50-line section would do.

Without an explicit architecture, every project re-invents an ad-hoc mix of `rules/`, `docs/`, indexes, and prompts — which then drifts. This doc defines layered roles for each asset type and a deterministic routing pattern between them so the agent always knows where to look.

---

## Universal Asset Model (7 layers)

| Layer | Role | Discovery mechanism | Loaded per turn? |
|---|---|---|---|
| **0. Always-applied rules** | Hard project laws + minimal routing map | Forced into context | Yes |
| **1. Routers** | Map keyword → domain → asset locations | Grepped on demand; never full-read | No (grep only) |
| **2. Live truth** (MCP / API) | Authoritative live state (schema, signatures, data) | Tool descriptors visible; queries on demand | No (calls only) |
| **3. Authoritative narrative docs** | Business rules, edge cases, examples | Scoped grep + offset/limit read | No (scoped read) |
| **4. Product/concept context** (semantic MCP) | Pre-chunked semantic knowledge (feature overview, FE journey, technical reference) | Tool descriptors visible | No (calls only) |
| **5. Requestable rules** | Conventions for discovery, build, close phases | Path + description surfaced to the model | On demand |
| **6. Skills** | Multi-file workflows that benefit from scripts/reference files | Name + description surfaced to the model | On demand |

### What each layer is FOR

- **Layer 0** answers "what must never be violated and where do I look next?" Keep it tiny.
- **Layer 1** answers "given this keyword, which domain and which file?" It is a router, not knowledge. Never full-read it.
- **Layer 2** is the only authoritative source for live state (DB schema, deployed function signatures, current data). Docs drift; live truth doesn't.
- **Layer 3** is the source of business intent — the WHY behind the code. It is large and must be accessed by scoped grep + offset/limit.
- **Layer 4** (when available) is the cheapest path to product/feature-level framing because it returns pre-chunked semantic blocks.
- **Layer 5** is the convention library — naming, patterns, guardrails per work phase. Loaded only when relevant.
- **Layer 6** is for workflows that justify a directory of supporting files. Most "workflows" should be requestable rules; only graduate to a skill when scripts or progressive disclosure across multiple files actually help.

---

## Skills vs Requestable Rules — When To Use Which

Both expose `name` + `description` to the agent and are loaded on demand. Use a skill instead of a requestable rule only when:

- The workflow ships with executable scripts.
- Progressive disclosure across multiple files genuinely helps (lean `SKILL.md` linking to `examples.md`, `reference.md`).
- A glob auto-attach rule wouldn't fit (skills are pure description-discovery).

If you don't need scripts or multi-file structure, a requestable `.mdc` rule is simpler and lives in the same directory as your other conventions.

---

## Request Flow Pattern

```
User request
   │
   ▼
Layer 0 — Always-applied rules
   Hard laws + routing map + universal MCP usage notes
   │
   ▼
Identify request type
   (build / fix / analyze / plan / meta / migration / one-off)
   │
   ▼
Load discovery-phase rules
   (doc-search, tool-batching, context-lookup, image-handling if applicable)
   │
   ▼ (parallel turn 1 — batched)
Grep Layer 1 routers for user keywords          → domain
Grep registry routers for the domain            → candidate functions/tables/edge fns
Layer 4 semantic MCP search (if concept-level)  → product context
   │
   ▼ (parallel turn 2 — batched)
Layer 2 MCP introspection on candidates         → live signatures/columns
Grep Layer 3 doc headings around the symbol     → section map
Scoped read of Layer 3 sections                 → exact business rules
   │
   ▼ (parallel turn 3 — batched, when needed)
Layer 2 MCP read body of the likely candidate   → live logic
   │
   ▼
Load build-phase rules
   (conventions relevant to the work: DB, function, auth, abstraction, etc.)
   │
   ▼
Present plan + impact analysis  →  WAIT for user approval
   │
   ▼
Execute via Layer 2 MCP / git / deploy
   │
   ▼
Load close-phase rule
   Update authoritative narrative doc + changelog
   Regenerate registries if schema/functions changed
   │
   ▼
Thread checkpoint behavior fires if context is large
   Emit compact state summary
   Recommend continuing in a new thread
```

### The discovery batching invariant

Each parallel turn collapses what would otherwise be many sequential calls. **A 3-turn batched discovery is roughly 3× cheaper than a 9-turn sequential discovery for the same information** because every additional turn replays the entire prior context.

Independent calls always go in one turn; only sequentialize when call B's inputs come from call A's output.

---

## Cross-Cutting Behavioral Rules

These are not phase-specific — they apply to how the agent acts in any turn.

| Rule | Trigger | Purpose | Placement |
|---|---|---|---|
| **Tool batching** | Any turn with multiple tool calls | Parallelize independent calls; sequentialize only on real data dependency. | **Always-applied imperative** (deep examples in requestable rule) |
| **Doc grep-first** | Before reading any large reference doc | Heading grep → keyword grep → scoped read with offset/limit. Never full-read large docs. | **Always-applied imperative** (patterns in requestable rule) |
| **Registry-first** | Any DB / function discovery | Grep the registry before MCP `LIKE` discovery. | **Always-applied imperative** |
| **Identifier hygiene** | Before any tool call needing an ID | Don't pass UUIDs/names from memory — must come from user message, prior tool result, or confirmation query. | Requestable (tool-batching rule) |
| **Image handling** | Image attached to the turn | Extract facts to text early; recommend a fresh thread for downstream work so the image doesn't ride along forever. | Requestable (auto-trigger via "image attached" cue) |
| **Discovery loop checkpoint** | After 3 discovery turns or no-new-info turn | Stop and present hypothesis + evidence + next step. Premature consolidation is cheaper than perfect certainty. | Requestable (context-lookup rule) |
| **Bug diagnosis shortcut** | Bug looks like a documented contract | Grep authoritative doc for the contract BEFORE reading function bodies. | Requestable (context-lookup rule) |

### Architectural lesson: when behaviors must be always-applied

The first three behavioral rules above are imperatives that must apply on **every** turn touching the database or large docs — they're not optional. We initially placed them all as requestable `.mdc` files, but observed in a 50-thread audit that:

- Requestable rules describing behaviors (vs. specific work phases like "writing a function") loaded in only ~6–10% of threads, even with strong trigger terms in their descriptions.
- The agent's discovery model triggers reliably on **noun-shaped signals** ("writing a `bff_*` function", "image attached", "closing a task") but unreliably on **verb-shaped signals** ("grepping a doc", "making multiple tool calls").
- The cost was concrete: sequential single-tool turn runs hit 17 calls in one thread, and full-reads of 100KB+ docs continued to appear in 24% of threads.

The fix is to **promote the imperative itself into Layer 0** as a short, sticky directive ("Grep the registry first. Never full-read large docs. Batch independent tool calls."), while leaving the longer worked examples in a requestable rule. The always-applied cost of the directive is far smaller than the cost of one misbehaving turn it prevents.

**Heuristic:** if a behavior should fire on every turn of a common task type, promote it to Layer 0. If it should fire only when a specific noun is in scope (a function name, a file type, a phase name), leave it requestable.

---

## Routing Matrix (asset → asset)

| From | To | Trigger |
|---|---|---|
| User request | Layer 0 (auto) | Always |
| Layer 0 | Discovery rules | Discovery phase begins |
| Discovery rules | Layer 1 router (grep) | Always at start of domain task |
| Layer 1 router | Registry routers (grep) | After domain identified |
| Registries | Layer 2 MCP | Got candidate function/table names |
| Layer 1 router (parallel) | Layer 4 semantic MCP | Product/feature/concept question |
| Layer 1 router (parallel) | Layer 3 narrative doc via grep | Need exact business rule wording |
| Discovery complete | Build-phase rules (Layer 5) | About to write/change |
| Build rules | Plan → approval | Always before execute |
| Approval | Layer 2 MCP / git / deploy | Execute change |
| Execute complete | Close-phase rule | Always at close |
| Close-phase rule | Registry regenerate (skill or script) | DB function/schema changed |
| Close-phase rule | Layer 3 narrative doc + CHANGELOG | Always at close |
| Any phase | Behavioral rules | Per trigger |

---

## Adoption Guide — Applying This To A New Project

### Step 1 — Define hard laws (Layer 0)

Identify the non-negotiables. Examples: read-only by default, no schema changes without approval, no destructive renames, deployment quirks. Put them in one always-applied rule file (`00-core.mdc` or `AGENTS.md`). Target ~300–500 tokens.

Include a routing map: "Discovery → these rules. Build → these. Close → these."

### Step 2 — Identify your domains

A domain is anything with its own conventions, tables, or business rules. Create a tiny keyword router (`_index.md`) mapping keywords → domain file paths. This is your Layer 1.

### Step 3 — Identify your live source of truth

Wire an MCP for it (Supabase, REST endpoint, GraphQL, GitHub, database client). This is Layer 2. Live truth wins over docs whenever they conflict.

### Step 4 — Identify your large reference docs

Anything >50KB needs the grep-first protocol applied. Create a `doc-search.mdc` requestable rule with heading-grep patterns and the ban on full-reads.

### Step 5 — Build a registry (if applicable)

If you have many functions/tables/endpoints, build a per-domain registry mapping domain → list of resources. Auto-generate from live truth where possible (e.g. `pg_proc` for Postgres functions, OpenAPI spec for REST). Keep it under 30KB so grep stays cheap.

### Step 6 — Capture phase conventions as requestable rules

For each work phase (discovery, build, close), create a single rule. Use strong trigger terms in the description. Skip skills unless you actually need scripts or multi-file disclosure.

### Step 7 — Add cross-cutting behavioral rules

Tool batching, image handling, identifier hygiene, discovery checkpoint, thread checkpoint. Each is short. They are individually small but compound large savings.

### Step 8 — Trim MCPs per project

Every enabled MCP server adds tool descriptors + server-use instructions to every turn. Disable MCPs that aren't relevant to this repo. Re-enable per task elsewhere.

### Step 9 — Audit and trim

- Is `00-core` under ~500 tokens?
- Do all requestable rule descriptions have trigger terms?
- Are there any "small" docs that have grown >50KB and now need grep-first protocol?
- Are large tool results staying in long threads? Add a thread-checkpoint trigger if so.

---

## Common Pitfalls

| Pitfall | Cost | Fix |
|---|---|---|
| All conventions in always-applied rules | Token tax on every turn | Move procedural detail to requestable rules; keep Layer 0 small |
| Treating per-domain summaries as authoritative | Drift between summary and source | Make summary explicitly non-authoritative; use it only for navigation/line ranges |
| Reading large docs without grep | 25K+ tokens for 2K of useful content | Enforce grep-first protocol via `doc-search.mdc` |
| Long threads (>150 turns) | Quadratic context replay cost | Thread-checkpoint behavior: summarize + new thread |
| Images riding along forever | 1.5K tokens × every turn | Image-handling rule: extract facts early; new thread for downstream work |
| Skipping registry updates after changes | Stale registry; agent guesses or rediscovers | Close-phase rule mandates registry regen |
| Sequential tool calls when independent | 3× tokens for the same information | Tool-batching rule with concrete batchable examples |
| Skills for everything | Maintenance overhead; redundant with requestable rules | Use requestable rules unless multi-file/scripts actually justify a skill |
| Index files that grew into content | Loaded as content, not router | Split: pointer index + per-domain detail files |
| Bug diagnosis via function bodies first | 200 lines of SQL when 10 lines of doc would answer | Bug-diagnosis-shortcut rule: grep contract docs first |

---

## Success Criteria

A project running this architecture should observe:

- Average tokens per turn for routine tasks reduced 30–50% vs an unstructured baseline.
- No full-reads of authoritative `<Domain>.md` files in normal task flows.
- Long threads (>150 turns) become rare.
- Independent tool calls observably collapse into single turns.
- Registries stay in sync after schema/function changes.
- New contributors (human or AI) can orient themselves on a new domain in <5 minutes by following the routing map.

---

## Reference Implementation: Supabase CRM (this repo)

Concrete mapping of the universal model onto this codebase.

| Universal layer | This project |
|---|---|
| Layer 0 — always-applied rules | `.cursor/rules/00-core.mdc` (laws + four discovery imperatives + routing map), `14-no-canvas.mdc`, `15-crm-knowledge-mcp.mdc` (retrieval order only) |
| Layer 1 — routers | `requirements/domains/_index.md` (Domain Map → authoritative paths), `requirements/REGISTRY_SUPABASE.md`, `requirements/REGISTRY_RENDER.md` |
| Layer 2 — live truth | Supabase MCP (`supabase`), GitHub MCP (`github`) for Render code |
| Layer 3 — authoritative docs | `requirements/<Domain>.md` (Currency.md, Tier.md, Reward.md, CS_*.md, etc.) |
| Layer 4 — product/concept | CRM Knowledge MCP (`crm-knowledge`) |
| Layer 5 — requestable rules | `08-context-lookup`, `09-db-conventions`, `10-function-conventions`, `11-auth-conventions`, `07-abstraction-principles`, `02-functions-queues-triggers`, `05-function-database-implementation`, `06-update-docs`, `12-doc-search`, `13-requirements-writing`, `16-tool-batching`, `18-image-handling`, `19-writing-principles-mcp` |
| Layer 6 — skills | `.cursor/skills/registry-regenerate/` (bundles `scripts/regen_registry_supabase.sh` for refreshing `REGISTRY_SUPABASE.md` from live DB) |

### Routing in this repo

- **Discovery** is largely handled by the always-applied imperatives in `00-core.mdc` (grep registry, grep-not-full-read, batch independent calls). `08-context-lookup.mdc` is loaded for the SQL templates and worked examples; `12-doc-search.mdc` and `16-tool-batching.mdc` are reference deep-dives loaded only when patterns get complex. `18-image-handling.mdc` triggers on image attach.
- **Build** loads `09`, `10`, `11`, `07` depending on what's being changed.
- **Close** loads `06-update-docs.mdc`, which mandates domain doc + CHANGELOG + registry regen.

### MCP profile

Pinned in `.cursor/mcp.json` for this repo: `supabase`, `crm-knowledge`, `github`. Other servers from the global profile (`mongodb`, `n8n`, `playwright`, `render`, `web-to-mcp`, etc.) are not enabled here and can be re-enabled per task elsewhere. The Cursor built-in `cursor-ide-browser` MCP carries ~6,193 tokens of tool descriptors per turn and is **manually disabled in Cursor Settings → MCP** for this workspace (it's a frontend-testing MCP, irrelevant to a backend repo).

### Always-applied per-turn budget (this repo)

| File | Approx tokens |
|---|---|
| `00-core.mdc` | ~935 |
| `14-no-canvas.mdc` | ~158 |
| `15-crm-knowledge-mcp.mdc` (retrieval-only) | ~514 |
| **Total** | **~1,607 tokens/turn replay** |

The split of `15-crm-knowledge-mcp.mdc` (audit-driven, 2026-05-13) moved smoke-check SQL and write workflows into the requestable `15a-crm-knowledge-writes.mdc`, saving ~535 tokens per turn that were previously paid by every thread regardless of whether it wrote knowledge.

### Outcomes observed

- Per-thread Read-burned tokens dropped 41% vs. April baseline (52.1k → 30.7k) once the registry layer + grep-first protocol were in place.
- Zero full-reads of the deprecated `INDEX_FUNCTION.md` (~100KB) in normal task flows.
- Bug-diagnosis tasks reliably grep `REGISTRY_SUPABASE.md` + Supabase MCP instead of full-reading function indices.
- Registry-regenerate skill keeps function/table inventory in sync; agents find the right name without MCP `LIKE` discovery.

### Known follow-ups (status: 2026-05-13)

- **Phase 6 physical slug consolidation.** `requirements/domains/_index.md` Domain Map now routes to authoritative `requirements/<Domain>.md` paths, but the per-domain slug files at `requirements/domains/<slug>.md` still exist. At least one (`purchase-transaction.md`) carries unique business-rule summaries not yet present in the authoritative doc; bulk deletion would lose context. Each slug needs a careful per-domain merge.
- **`cursor-ide-browser` Settings toggle.** Workspace-level disable is a Cursor Settings UI action — the largest remaining always-applied tax.
- **Backward-looking audit metric** (`scripts/audit_agent_tokens.py --compare`) is calibrated against pre-change file sizes; forward delta will materialize as new threads land against the trimmed always-applied layer and the always-applied imperatives.

---

## Related Reading

- `requirements/CURSOR_RULES_PRINCIPLES.md` — rule-writing principles, layer model, token economy (the "why" behind the layer model).
- `.cursor/rules/00-core.mdc` — this project's Layer 0 implementation.
- `.cursor/rules/08-context-lookup.mdc` — discovery phase orchestration.
- `.cursor/rules/12-doc-search.mdc` — grep-first protocol for large docs.
- `.cursor/rules/16-tool-batching.mdc` — parallel-when-independent rule + identifier hygiene.
