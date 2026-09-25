# Requirements doc unification — execution plan

**Date:** 2026-09-17
**Status:** Batch 0 (mechanics & structure) **complete** 2026-09-17 (`System_Map.md`, rules, chunker, indexes). Batches 1–5 (domain enrichment) tracked in `requirements/CHANGELOG.md` — separate execution program.
**Repo:** `Rocket-CRM/supabase-crm` only. No DB schema changes. One script change. One MCP-adjacent behaviour is verified unchanged (§6.1).

---

## 0. Task

Collapse the two document types under `requirements/` (engineering-dense `<Domain>.md` + human-facing `feature-docs/*.md`) into **one canonical document per feature domain** with a fixed four-section spine, define how Shopify-specific behaviour is written, replace the feature-guide rule + checklist with a short requirements-writing rule, and make the one chunker change that lets the CRM Knowledge reader address subsections precisely. Then run an enrichment program domain by domain.

Nothing here changes the derived pipeline's inputs: CRM Knowledge chunks, the product feature catalog (`internal_product_*`), and `docs/PRODUCT_NARRATIVE.md` all continue to read `requirements/**/*.md`.

---

## 1. Decisions locked (do not reopen)

| # | Decision |
|---|---|
| D1 | Section order: **Concept → Rules → Journeys → System**, tail **Related**. |
| D2 | Shopify: platform plumbing stays in `Shopify.md`; **feature-level Shopify behaviour lives in the feature's doc** as a `### Shopify` subsection under the spine section it changes, written as **delta only**. Cross-refs run hub → feature doc only. |
| D3 | `requirements/feature-docs/` is **retired** after the Reward and Check-in merges; contents move to `requirements/archive/feature-docs/`. |
| D4 | Chunker: `heading_path` becomes a path (`Journeys > Shopify`), not the leaf heading. |
| D5 | New docs use plain `##` / `###` headings. **No `SECTION:` tags** in the new template (they force whole-section mechanical splitting — see §6.1). |
| D6 | Frontend content is limited to intended journey + human-visible states + page → repo → BFF/RPC map. No component/route/validation specs. |
| D7 | No coverage checklist, no scenario matrix, no per-audience sections, no per-feature Shopify files, no status registry. The template's per-section depth contract is the standard. |

---

## 2. The document standard (what every `requirements/<Domain>.md` converges to)

### 2.1 Spine

| `##` heading | Question it alone answers | Depth contract |
|---|---|---|
| **Concept** | What is this, and what are its objects? | A new PM understands it in two minutes: purpose (2–4 sentences), the 5–10 nouns with one-line definitions and how they relate, shipped-status inline as `(beta)` / `(planned)` on the capability it qualifies. No identifiers (no table/function names). |
| **Rules** | What does the system guarantee? | Every rule is testable: condition → outcome. State models fully enumerated: all values, valid transitions, dependence between tracks, member-facing label per state. Limits, precedence, edge cases. One example only where the rule is non-obvious. |
| **Journeys** | What does the admin do, what does the member see, in order? | `### Admin journey` opens with a **settings table** (knob → effect on behaviour) then numbered steps by **page name**; `### Member journey` numbered steps with every human-visible state incl. errors. Each journey heads with a small map: page → owning repo → BFF/RPC (route optional). Steps never restate a rule — they reference its effect. |
| **System** | How is it built? | Every table, function, trigger, queue, edge fn, Render/Inngest service a change would touch — **named with its role** and the flow between them (sync path, async path, external calls, caches). Roles and flows, not signatures or bodies (registry + live Supabase own those). Subsections typically: `### Data model`, `### Functions`, `### Flows`, `### External services`, `### Known gaps`. |
| **Related** (tail) | Where does it hand off? | 3–6 lines: domain → one-sentence coupling. Routing only. |

Document header (above Concept): H1 title, one-line scope statement, `Owner surfaces:` line (e.g. `loyalty-admin, loyalty-user, Shopify storefront`). Nothing else — no TOC, exec summary, conclusion, quick reference.

### 2.2 Surface deltas (Shopify today; LINE / WooCommerce later)

- Under any spine section whose default behaviour differs on a surface, add `### Shopify` (or `### LINE`, …) as the **last** subsection of that section.
- Write **only the delta**: what differs, what is absent, what is added. Never restate the default. If nothing differs in a section, no subsection.
- Typical placement: `Journeys > Shopify` (checkout / storefront / embedded-admin steps), `System > Shopify` (webhook path, `rewarding-shopify` calls, credential lookup), occasionally `Rules > Shopify`.
- `Shopify.md` keeps: OAuth, embedded auth, webhooks receiver, billing, entitlements, widget shell, `rewarding-shopify` service, landing page, UI hiding — i.e. things with no non-Shopify counterpart — plus one routing table at the top: *feature → doc › section where its Shopify variant lives*.

### 2.3 Writing craft (cite, don't copy)

`Writing Principles/CORE_WRITING_PRINCIPLES.md` governs prose: lead with the core concept, vertical/horizontal logic, MECE, peers at the same abstraction level, layered depth, cross-reference instead of duplicating, specificity, no filler. The rule file (§3.2) cites it; it does not restate it.

---

## 3. Deliverables — Batch 0 (system in place; no doc rewrites yet)

Execute in this order. Each item is small. Commit as one change set after user review of the diff.

### 3.1 `requirements/_TEMPLATE.md` (new)

Skeleton of §2.1 with each section's depth contract as an HTML comment directly under its heading, plus a commented `### Shopify` example under Journeys and System. ≤ 80 lines. Excluded from indexing (§3.4).

### 3.2 `.cursor/rules/13-requirements-writing.mdc` (replaces `13-feature-guide-writing.mdc`)

Frontmatter: `globs: ["requirements/*.md", "requirements/architecture/*.md"]`, `alwaysApply: false`, description "How to write and update canonical requirement docs. Triggers on any edit under requirements/."

Body, ≤ 80 lines, in this order:
1. The spine table from §2.1 (heading, question, depth contract).
2. The surface-delta rule from §2.2 (5 bullets).
3. **Where to look before writing** — one table: what you're writing → truth source → tool.
   - Concept / Rules → product decision in thread + existing doc + CRM Knowledge `search_docs`
   - Journeys → `Rocket-CRM/loyalty-admin`, `Rocket-CRM/loyalty-user` (GitHub MCP or local clone under `~/Documents/rocket/`), `Shopify` surface → `rewarding-shopify`, storefront extension in loyalty-user
   - System → `REGISTRY_SUPABASE.md` / `REGISTRY_RENDER.md` grep, then Supabase MCP `information_schema` / `pg_proc` signatures
   - "Where does X run / live" → `requirements/architecture/System_Map.md` (§3.5)
4. Frontend boundary (D6) — 3 bullets.
5. Header format and the "no TOC / summary / conclusion" line.
6. Pointer: prose craft = `Writing Principles/CORE_WRITING_PRINCIPLES.md`; closeout routing = `06-update-docs.mdc`.

Delete `13-feature-guide-writing.mdc`. Reduce `Writing Principles/FEATURE_GUIDE_WRITING_PRINCIPLES.md` to a 3-line pointer to the new rule + CORE (keep the file so `Writing Principles/INDEX.md` links don't break; update its INDEX row).

### 3.3 `.cursor/rules/06-update-docs.mdc` (edit two rows, add one table)

- Replace the row *"Feature behavior change with an active Feature Guide → update `requirements/feature-docs/<feature>.md` …"* with:

  | You changed… | Touch in `requirements/<Domain>.md` |
  |---|---|
  | a noun, concept, rename, or shipped-status | Concept |
  | a rule, limit, state, edge case | Rules |
  | what admin/member does or sees, or a setting | Journeys |
  | a table, function, flow, service, cache | System (+ registries as today) |
  | any of the above only on Shopify (or another surface) | `### <Surface>` under that section |
  | a domain with no doc | copy `requirements/_TEMPLATE.md` + `_index.md` row |

- Delete the "Feature Guide Updates" subsection. Replace "Domain docs: schema + business rules + function signatures" in *Writing Conciseness* with "Domain docs: follow the spine in `13-requirements-writing.mdc`; no narrative filler."

### 3.4 `scripts/doc-knowledge-reconcile.mjs` (D4 + exclusions)

In `chunkMarkdown`, non-`SECTION:` mode only:
- Track the current `##` heading. When a `###` heading starts a chunk, set `headingPath = "<H2> > <H3>"`; a `##` heading sets `headingPath = "<H2>"`.
- `chunk_key` is already `slugify(headingPath)` → becomes `journeys-shopify`, `system-shopify`. **This also fixes a latent bug:** today two `### Shopify` headings in one file produce the same `chunk_key` and the second upsert overwrites the first (`onConflict: "path,chunk_key"`).
- `title` (display) already renders `file.md > headingPath`; no change.
- `SECTION:` mode: unchanged (legacy hubs keep working).

`EXCLUDE_NAME_RE`: add `_TEMPLATE\.md$`. Confirm `archive/` is skipped by the directory walk (it is excluded today per `docs/CRM_KNOWLEDGE_MCP_ARCHITECTURE.md`; verify in `walk()` and add if not).

After the change, run reconcile once (`cd scripts && node doc-knowledge-reconcile.mjs`, needs `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY`). Expect: every `###` chunk in non-SECTION files gets a new `chunk_key` → old rows flip `is_active=false`, new rows insert and queue embeddings. This is a one-time re-embed of most of the corpus; check the embedding cron is active and OpenAI credits are available first (`docs/CRM_KNOWLEDGE_MCP_ARCHITECTURE.md` § Embeddings).

Update `docs/CRM_KNOWLEDGE_MCP_ARCHITECTURE.md` § Corpus → Chunking: "`heading_path` = `H2 > H3` path in heading mode; `SECTION: X` in section mode."

### 3.5 `requirements/architecture/System_Map.md` (new, ~150 lines, indexed)

The one new content document. Answers "where does X live / run" for writers and agents. Sections (`##`):
1. **Repos and what each owns** — `supabase-crm` (DB, RPCs, edge fns, canonical docs), `loyalty-admin` (merchant admin FE), `loyalty-user` (member app FE incl. Shopify storefront extension), `rewarding-shopify` (Shopify app backend), `crm-event-processors`, `messaging-service`, `amp-ai-service`, `cs-ai-service`, `futurepark-upload-receipt`, `crm-knowledge` (Knowledge MCP), `rocket-agent-plugins` (eng/sales plugins, commercial views). One line each. Verify the list against `~/Documents/rocket/` and `REGISTRY_RENDER.md` before writing.
2. **Runtime tiers** — Postgres RPC (`bff_*` admin/member, `api_*` external, `fn_*` internal, `trigger_*`), Supabase Edge Functions (Deno; webhooks, external API calls, embeddings), Render services (long-running Node; Inngest workers, consumers), pg_cron, PGMQ, Inngest. One line each: what it is, when to use it, where it's registered (`REGISTRY_SUPABASE.md` / `REGISTRY_RENDER.md`).
3. **Surfaces** — loyalty-user web app, LINE (LIFF/messaging), Shopify storefront widget + checkout + embedded admin, Open API, Front Line / store staff. One line each + which repo renders it.
4. **Auth contexts** — merchant admin JWT, member session, API key / service role, superadmin. Pointer to `11-auth-conventions.mdc`.
5. **Read order for writers** — registry → CRM Knowledge → live Supabase → app repo code.

Add an `_index.md` row: `System Map | architecture/System_Map.md | repo, where does, runs on, edge function vs rpc, render, inngest, surface, frontend lives`.

### 3.6 Registry / index hygiene

- `requirements/domains/_index.md`: add the System Map row. No other changes in Batch 0.
- `docs/PROJECT_CONTEXT_STRUCTURE.md` § Layer 3: one sentence — "Domain docs follow the four-section spine (`13-requirements-writing.mdc`); address subsections as `H2 > H3` via `get_section`."
- `requirements/CHANGELOG.md`: one line under today's date: **Docs** — requirements writing standard adopted (spine, surface deltas), feature-guide rule retired, chunker heading paths. See `.cursor/plans/requirements-doc-unification-plan-20260917.md`.

**Approval checkpoint:** show the diff summary of 3.1–3.6 before commit. Reconcile run (3.4) requires explicit go because it re-embeds the corpus.

---

## 4. Batch 1 — Pattern-setting merges (one thread each)

These two define the house style everything else copies. Do Check-in first (small, nearly done), then Reward (large, sets the pattern for big docs).

### 4.1 Check-in

- Sources: `requirements/Checkin.md` (already Concept → journey → system), `requirements/feature-docs/checkin.md` (§1–8 guide + §9 backend).
- Target: `requirements/Checkin.md` on the spine. Guide §2 → Concept nouns; §3 config → Journeys › Admin settings table; §4/§5 → Journeys; §7 → Rules; §9.1–9.3 → System; §9.4/9.5 → System › Known gaps (with inline `(planned)` tags moved to Concept where the capability is named). Drop §6 Perspectives.
- Move `feature-docs/checkin.md` → `archive/feature-docs/checkin.md`.
- Verify: grep the new file for any term used before it's defined in Concept; every rule in Rules has condition → outcome; no route paths inside steps.

### 4.2 Reward

- Sources: `requirements/Reward.md` (85 KB, 2200 lines, violates pyramid: opens on schema, has Exec Summary, TOC, two Conclusions, two "API Integration" H2s), `feature-docs/rewards.md`, `feature-docs/reward-groups.md`, `feature-docs/reward-sourcing-services.md`.
- Target: `requirements/Reward.md` on the spine. Reward groups and sourcing become `###` subsections (Concept nouns + Rules + System) — not separate docs. Shopify discount-product lookup (current § "Shopify Discount Product Lookup") becomes `System > Shopify`; `online_store[]` storefront display becomes `Journeys > Shopify` delta.
- Method: build the new skeleton in a fresh file, move content section by section using `rg -n '^#{2,3} '` + scoped reads (never full-read; hook enforces), then replace. Consolidate the seven "Implementation Examples" into at most three, placed under the rule they illustrate.
- Move the three guides → `archive/feature-docs/`. Update `feature-docs/INDEX.md` → replace with a 5-line stub: "Retired 2026-09; content merged into `requirements/<Domain>.md`; archive at `requirements/archive/feature-docs/`." Then move the stub too and delete the folder once nothing links to it (`rg -n 'feature-docs' .cursor requirements docs workflows`).
- Re-run reconcile; confirm `get_section("requirements/Reward.md", "Journeys > Shopify")` returns the delta chunk.

**Approval checkpoint:** each merge is presented as a section-by-section move plan before the file is rewritten.

---

## 5. Batch 2 onward — Enrichment program (one domain per thread)

Order by consumer value. For each doc: walk the four sections in order, verify each against its truth source (§3.2 table), fix drift, `_index.md` row present, CHANGELOG line. A doc is done when it has all four spine sections at the depth contract, even if System is short.

| Wave | Domains | Work type |
|---|---|---|
| 2 | Currency, Tier, Signup_Login | Move feature-level Shopify content out of `Shopify.md` into `### Shopify` deltas; add Concept/Journeys where tables-first. Then trim `Shopify.md` to platform + routing table (§2.2). |
| 3 | Display_Settings, CS_Feature_Spec / CS_AI_System, Asset, RFM_Scoring, Syngenta_Events, Marketplace | Tables-first docs: add Concept + Journeys; leave System mostly as is (Phase E list from `requirements-audit-checkpoint-20260809.md`). |
| 4 | Domains flagged missing/thin in the Aug audit coverage matrix (Phase B) | New files from `_TEMPLATE.md`. |
| 5 | Everything else, alphabetically, only when touched by real work | Apply the spine opportunistically via `06-update-docs` routing. |

The periodic **review mode** (read whole doc vs live code) uses the same procedure with no extra criteria. If a recurring review is wanted later, it is a Cursor Automation whose prompt is: "pick the domain with the oldest CHANGELOG touch, run the review procedure in §5, present drift as a diff." Do not build this in Batch 0–2.

---

## 6. Reader / pipeline verification (what must keep working)

### 6.1 CRM Knowledge

- `doc_knowledge_get_section(p_path, p_heading)` matches `heading_path ILIKE '%' || p_heading || '%'` (exact > prefix > substring, shortest first). Verified 2026-09-17 from the live function body. Therefore `get_section(path, "Journeys > Shopify")` and `get_section(path, "Shopify")` both resolve after D4; **no RPC change needed**. Known limitation (pre-existing, leave alone): neighbour ordering is alphabetical by `heading_path`, not document order.
- `search_docs` unaffected: FTS + semantic over `content`; `title` gains the H2 context, which helps ranking.
- `SECTION:`-mode files (`Shopify.md`, `FuturePark.md`, hubs) are unchanged until rewritten. When `Shopify.md` is trimmed in wave 2, convert it to `##`/`###` headings at the same time.

### 6.2 Product feature catalog (weekly Automation, `workflows/product-feature-catalog/REFERENCE.md`)

- No change to procedure. It diffs `requirements/**` and cites `source_refs: {path, heading}`. After D4, new `source_refs` should use the path form (`"heading": "Rules"` or `"Journeys > Shopify"`). Existing refs with leaf headings still resolve via substring match.
- Add one sentence to REFERENCE §8 Evidence: "Prefer `heading` in `H2 > H3` form; Shopify-module features cite the feature doc's `### Shopify` subsection, not `Shopify.md`, unless the capability is platform plumbing."
- Status signal: inline `(beta)` / `(planned)` tags in Concept are the evidence for `status`.

### 6.3 Product narrative

Untouched. Derived from catalog + requirements; sections keyed by `feature_key`. Not indexed.

### 6.4 Rocket-eng plugin (`rocket-agent-plugins/plugins/rocket-eng/`, README only today)

Out of this repo. When its protocol is written, one line suffices: "Behaviour-affecting change → close out in `supabase-crm` per `.cursor/rules/06-update-docs.mdc` and `13-requirements-writing.mdc`; edit the CRM clone in the multi-root workspace." Content never moves into the orchestrator.

---

## 7. Critical context for the executing thread

- Repo: `/Users/rangwan/Documents/rocket/supabase-crm`. Sibling repos under `/Users/rangwan/Documents/rocket/` (loyalty-admin, loyalty-user, rewarding-shopify, crm-knowledge, rocket-agent-plugins, …).
- Supabase project `wkevmsedchftztoolkmi`. Chunk table `public.doc_knowledge_chunks` (`path`, `heading_path`, `chunk_key`, `title`, `content`, `content_hash`, `is_active`; unique on `path,chunk_key`).
- Reconcile: `scripts/doc-knowledge-reconcile.mjs`; `MAX_CHARS = 4000`; `EXCLUDE_NAME_RE` at line ~30; `chunkMarkdown` at line ~82. Embedding worker cron `process-internal-knowledge-embeddings`; edge fn `embed-jobs`.
- Knowledge MCP server code: `~/Documents/rocket/crm-knowledge/src/index.ts` (`get_section` passes `p_heading` straight through; citation renders `path#heading_path`). No change required.
- Hook `.cursor/hooks/block-large-doc-read.sh` blocks full reads of large `requirements/*.md` — the Reward merge must work via `rg -n '^#{2,3} '` + `Read` with `offset`/`limit`.
- Prior analysis threads: `8d983b2a-3bfa-4f71-b338-f1fad6085267` (pipeline mapping) and the thread that produced this plan (design rationale). Aug audit: `.cursor/plans/requirements-audit-checkpoint-20260809.md` (Phase B coverage matrix, Phase E structure queue — reuse, don't redo).
- Existing exemplars closest to the spine: `Checkin.md`, `Package.md`, `Mission.md`, `Consent.md`, `Persona_Entitlement.md`.

---

## 8. Next exact step (start of new thread)

1. Read this file.
2. Read `scripts/doc-knowledge-reconcile.mjs` lines 25–160 and `.cursor/rules/06-update-docs.mdc`, `.cursor/rules/13-feature-guide-writing.mdc` (to be replaced).
3. Write `requirements/_TEMPLATE.md` (§3.1) and `.cursor/rules/13-requirements-writing.mdc` (§3.2); show both for approval.
4. On approval, do §3.3–3.6, present the diff, commit. Run reconcile only after explicit go.
5. Open a new thread for §4.1 (Check-in merge).
