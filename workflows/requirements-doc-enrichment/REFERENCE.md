# Requirements doc enrichment — workflow

**Purpose:** One domain per thread — review the authoritative `requirements/<Domain>.md`, verify against live code and registries, rewrite to the **four-section spine** at full depth, and remove duplicate legacy structure.

**Not in scope:** Batch 0 mechanics (template, chunker, rules) — already complete. See `.cursor/plans/requirements-doc-unification-plan-20260917.md`.

**Writing standard:** `.cursor/rules/13-requirements-writing.mdc`  
**Closeout:** `.cursor/rules/06-update-docs.mdc` + one line in `requirements/CHANGELOG.md`  
**Thread prompts:** `workflows/requirements-doc-enrichment/DOMAIN_THREADS.md` (copy-paste per domain)

---

## Definition of done (one domain)

1. **Header** — H1, one-line scope, `Owner surfaces:` only (no TOC, exec summary, conclusion).
2. **Spine as the home for truth** — `## Concept` → `## Rules` → `## Journeys` → `## System` → `## Related`. Prefer **moving** legacy sections into the right spine block over leaving a parallel doc. See **Editing principles** below — do not wipe large bodies just to “clean up.”
3. **Depth contract** — Each section meets the table in `13-requirements-writing.mdc` (testable rules, admin settings table + steps, System with data model / functions / flows / gaps).
4. **Verified** — Material claims checked against: `REGISTRY_SUPABASE.md` / `REGISTRY_RENDER.md` grep, Supabase MCP signatures, and relevant app repos under `~/Documents/rocket/` (loyalty-admin, loyalty-user, rewarding-shopify).
5. **Surface deltas** — `### Shopify` (or other) only where behaviour differs; delta-only under the spine section it changes.
6. **Drift fixed** — Stale Kafka paths, retired invite-code referral drafts, wrong table names, etc. removed or corrected with evidence.
7. **CHANGELOG** — One bullet under today’s date for this domain.

Optional after large edits: `cd scripts && node doc-knowledge-reconcile.mjs` (hash-skip; only changed chunks re-embed).

---

## Procedure (agent — every domain thread)

### 0. Attachments

Start the thread with:

1. This file (`workflows/requirements-doc-enrichment/REFERENCE.md`)
2. The domain prompt from `DOMAIN_THREADS.md`
3. If the domain is in **Shopify reference MD scope** (below), the thread prompt already instructs reading the reference MD — do it **before** trusting the existing requirement doc.

### 1. Classify the starting file

| Starting shape | Action |
| --- | --- |
| **Exemplar** (`Checkin.md`, `Reward.md`) | Accuracy pass + remove any legacy tail if present |
| **Spine + legacy H1** (most Wave 3–5 CS/import docs) | Merge legacy into spine; delete duplicate block |
| **No spine** (`Currency.md`, `Mission.md`, …) | Build spine from registry + apps + existing body via `rg -n '^#{2,3} '` + scoped `Read` — never full-read files blocked by hook |
| **SECTION: hub** (`Shopify.md`, `FuturePark.md`) | Convert to `##`/`###` when enriching that hub (or trim hub only per `Shopify.md` routing table plan) |

### 2. Discovery (batched)

- Grep `requirements/domains/_index.md` for domain keywords → confirm authoritative path.
- Grep `REGISTRY_SUPABASE.md` / `REGISTRY_RENDER.md` for domain symbols.
- Supabase MCP: table columns + function **signatures** for names you will cite in System (not full bodies unless fixing behaviour).
- CRM Knowledge `search_docs` for prior narrative (do not treat as sole truth).
- **Journeys:** grep loyalty-admin / loyalty-user / rewarding-shopify for page names, BFF calls, visibility flags.

### 3. Shopify reference MD scope (referrals, on-site content, integrations)

For domains that touch Shopify referrals, storefront/on-site loyalty UI, or merchant integrations (Judge.me, Klaviyo, Gorgias), **mandatory read**:

| Copy in repo | User master (sync if newer) |
| --- | --- |
| `requirements/reference/SHOPIFY_REFERRALS_ONSITE_INTEGRATIONS.md` | `/Users/rangwan/Downloads/SHOPIFY_REFERRALS_ONSITE_INTEGRATIONS.md` |

Not CRM Knowledge–indexed (`requirements/reference/` skipped by reconcile) — threads must attach or read this path explicitly.

**The reference MD wins** over stale requirement prose when they disagree, unless live code contradicts it — then document the conflict in `### Known gaps` and note what you verified.

| Domain doc | Reference MD parts to apply |
| --- | --- |
| `Referral.md` | Part 1 (all) |
| `Display_Settings.md` | Part 2 (touchpoints, admin routes, hub/product/landing) |
| `Shopify.md` | Hub plumbing + routing table; Parts 1–3 **deltas** only (feature detail stays in feature docs) |
| `Third_Party_Integrations.md` | Part 3 |
| `Outbound_Integrations.md` | Part 3 (Klaviyo outbound, shared outbox) |
| `Earn_Channel.md` | Part 1 (referral CMS card vs program gate); Part 2 where earn surfaces on storefront |
| `Platform_Plan_Feature_Registry.md` | Shopify entitlement keys referenced in the reference MD (embedded gating, section visibility) |
| `Signup_Login.md`, `Tier.md` | Part 2 storefront identity / landing / tier hub only — `### Shopify` subsections |
| `Authentication.md` | Member session on Shopify (reference MD identity/gateway sections) — `### Shopify` under System/Journeys |

### 4. Rewrite rules

- Move identifiers (tables, RPCs, edge fns) to **System**; keep **Concept** identifier-free.
- At most **one** short example per non-obvious rule in Rules.
- Admin journey: settings table first, then numbered steps by **page name** (not file paths).
- Do not duplicate `Shopify.md` platform plumbing in feature docs — link and use `### Shopify` deltas.

### 5. Editing principles (guide — not a gate)

**Default:** Enrich and correct in place. Fold duplicate headings into the spine (e.g. old “technical reference” → `## System` subsections). Fix drift; add missing journeys and rules; tighten prose.

**Avoid big deletions** when the thread is a **targeted enrichment** pass:

- Do **not** delete long existing sections wholesale to meet the spine shape if they still describe behaviour that is live or useful detail for System.
- **Do** delete or replace chunks that are **wrong** (retired product, Kafka paths, old referral invite-code model, duplicated TOC/exec summary) after you have a verified replacement in the spine.
- When the **product has materially changed** (reference MD + code agree the old doc describes a different system), it is fine to retire large obsolete sections — prefer a short “retired” note in `### Known gaps` or Related pointing to what replaced it, rather than silent removal.

**Judgment, not strict rules:** If unsure whether a paragraph is obsolete or just poorly placed, **keep and relocate** it under the right spine section rather than drop it. Summarize in Concept/Rules; keep tables and flow detail in System.

**Optional (no approval required):** For a messy file, a short bullet **move plan in the thread** (old heading → spine section) before editing helps the user follow the diff — post it if useful, then proceed.

### 6. Closeout

- Update `requirements/<Domain>.md`
- `requirements/CHANGELOG.md` one bullet
- If new cross-links: touch `Related` only in peer docs when necessary (avoid drive-by rewrites)

---

## Suggested thread order

Priority = business surface + audit debt + unfinished Wave 2.

1. **Shopify cluster (reference MD):** Referral → Display_Settings → Shopify → Third_Party_Integrations → Outbound_Integrations → Earn_Channel  
2. **Wave 2 core:** Currency → Tier (consolidate legacy tail) → Signup_Login  
3. **Commerce ledger:** Purchase_Transaction → Marketplace  
4. **Engagement:** Mission → Forms → Notification_Service  
5. **Exemplar refresh:** Reward (strip legacy tail if any) → Checkin (light)  
6. **CS modular:** `CS_Feature_Spec` umbrella, then each `CS_*.md` (merge technical reference into spine)  
7. **Remaining domains:** alphabetical or when touched by product work  

Full copy-paste prompts: `DOMAIN_THREADS.md`.

---

## Related

- Unification plan: `.cursor/plans/requirements-doc-unification-plan-20260917.md`
- Aug audit queue: `.cursor/plans/requirements-audit-checkpoint-20260809.md` (Phase C accuracy — reuse, don’t re-audit from zero)
- System map for writers: `requirements/architecture/System_Map.md`
