# Project Brief — Shared Input Contract

The single shared input contract between the proposal generator and the deck composer. One row per engagement (one client, one fiscal pursuit). A single brief drives N decks plus M proposals.

This doc is the canonical schema reference. The TypeScript truth is `src/lib/project-brief/types.ts`; this doc explains intent, ownership, and the per-surface derivation rules.

> **Status (May 13, 2026):** Code shipped (Phase 0 of the deck-generation work). Migrations **applied** to both Corp Web (`0001_project_brief_pointer.sql`) and CRM (`0008_project_briefs.sql`) — verified via `user-supabase` SQL. Form-layer integration: shared `<BriefForm>` (full field catalog) lives in `src/components/internal/BriefForm.tsx` and is hosted by `/project-briefs` (canonical editor) and `/composer` `ContextPanel` (embed alongside `BriefPicker`). The proposal form `/internal-proposal` still uses its own hand-rolled field layout — refactor to `<BriefForm>` is tracked but not blocking.

---

## 1. Why a shared brief

Before Phase 0 the deck and the proposal had separate, semi-overlapping input shapes:

- The proposal asked for `customer_name`, `customer_industry`, `selected_features[]`, `business_context.*`, `system_context[]`, `module_contexts[]`, `language`, `tone_locale`, plus run-only knobs (`audiences[]`, `detail`, `clarification_mode`, `source_bundle[]`, `attributes`, `integration_scope`, `operations_nuances`).
- The deck asked for `brand.{primary, accent, logoUrl, companyName}`, `client.{name, industry, size, markets}`, `persona.{demographics, behaviors, goals}`, `modules[]` (three string ids), `pointCollection`, `exampleRewards[]`, `campaigns[]`, `showcaseIdeas`, `tone` (free string), `meta.{date, product, company}`.

Two real problems:

1. **Duplicate data entry.** SE writes Yuanta's industry, parent group, branch count, currency word three times (once per proposal, once per deck, once for the next deck).
2. **Drift.** The proposal says "Yuanta Coins"; the deck says "points." Cross-deliverable consistency is impossible to enforce when the inputs aren't shared.

The brief solves both by being the single source of truth at the form layer. Per-surface workers / inject routes consume derived shapes, not the brief directly — see §5.

---

## 2. The shape

```ts
export interface ProjectBrief {
  id: string;

  client: {
    name: string;                    // "Yuanta Securities"
    industry: string;                // "Retail brokerage"
    size?: string;                   // "12M members, 220 branches"
    markets?: string[];              // ["TH", "VN"]
    logoSquareUrl?: string;          // 1:1, validated at upload
  };

  brand: {
    primary?: string;                // "#00B8D4"
    secondary?: string;              // "#FF6B35"
  };

  businessContext: {
    parent_group?: string;
    scale?: string;
    business_model_summary?: string;
    geographic_footprint?: string;
    hosting_preference?: "cloud" | "on_prem" | "no_preference";
    compliance_regime?: string[];
    go_live_target?: string;
  };

  persona?: {
    demographics?: string;
    behaviors?: string;
    goals?: string;
  };

  selectedFeatures: SelectedFeature[];   // commercial scope — internal_pricing_blocks (CRM)
  selectedCapabilities: SelectedCapability[];  // narrative scope — feature-scope-catalog (CRM Knowledge slugs)
  systemContext: KnownSystem[];           // [{ name, role?, touchpoint? }]
  moduleContexts: ModuleContextEntry[];   // per-feature sales notes

  toneLocale: "professional" | "consultative";
  language: "en" | "th" | "bilingual";

  notes?: string;

  createdAt: string;
  updatedAt: string;
}
```

Fragment types:

```ts
export interface SelectedFeature {
  block_key: string;            // FK into internal_pricing_blocks
  parent_block_key: string | null;
  module_key: string;           // "loyalty" | "marketing_automation" | ...
  name: string;                 // human label
  crm_feature_slugs: string[];  // link to CRM Knowledge (metadata on pricing rows)
}

export interface SelectedCapability {
  slug: string;                 // CRM Knowledge feature slug (e.g. display-settings, forms)
  module_key: string;
  label: string;                // human label from feature-scope-catalog
}

export interface KnownSystem {
  name: string;
  role?: string;        // "Branch transactions"
  touchpoint?: string;  // "QR earn"
}

export interface ModuleContextEntry {
  parent_block_key: string;
  module_key: string;
  feature_slugs: string[];
  context_text: string;          // verbatim sales note
}
```

---

## 3. Discipline — what stays out of the brief

Three rules keep the brief clean:

1. **Both surfaces must consume the field, or could plausibly consume it next quarter.** No proposal-only or deck-only fields creep in.
2. **Per-engagement, per-deliverable knobs live on the deliverable row, not the brief.** The brief is reusable — one Yuanta brief drives three decks plus a proposal; per-run audience tilt lives on `internal_proposal_run`, per-deck slide order lives on `presentations`.
3. **Free-form notes go in `notes` or `moduleContexts[].context_text`.** Don't add half-structured fields like the deck's old `pointCollection.{methods, rules}` — those were proxies for what `moduleContexts[]` does properly.

### 3.1 Fields that are explicitly NOT on the brief

| Field | Lives on | Why |
|---|---|---|
| `audiences[]` | `internal_proposal_run` | Same client may want an exec deck and a technical deck this quarter |
| `detail` | `internal_proposal_run` | Per-pursuit depth choice |
| `clarification_mode` | `internal_proposal_run` | Per-pursuit |
| `source_bundle[]` | `internal_proposal_run` (via storage) | Per-pursuit artifacts |
| `attributes` (`has_tor`, `requires_phasing`, `requires_clause_coverage_matrix`) | `internal_proposal_run` | Per-pursuit |
| `integration_scope` | `internal_proposal_run` | Per-pursuit (which integrations are in this engagement's scope) |
| `operations_nuances` | `internal_proposal_run` | Per-pursuit |
| `linked_deck_slug` | `internal_proposal_run` | Per-pursuit |
| `model_writer`, `model_mechanical` | `internal_proposal_run` | Per-pursuit |
| `slug`, `title`, `slides[]`, `meta.{date, product, company}` | `presentations` | Per-deck |
| `tone_override` | (future) `presentations` | Per-deck override of brief tone |

---

## 4. Storage

| Concern | Project | Table / column |
|---|---|---|
| Brief row | CRM Supabase | `public.project_briefs` (jsonb `payload` + denormalized `client_name`, `client_industry`) |
| Logo file | CRM Supabase Storage | `project-briefs` bucket, path `{briefId}/logo-square.{ext}`. Public-read |
| Proposal pointer | CRM Supabase | `internal_proposal_run.project_brief_id uuid → project_briefs.id` (FK, `on delete set null`) |
| Deck pointer | Corp Web Supabase | `presentations.project_brief_id uuid` (no FK — cross-project) |

### 4.1 Why CRM, not Corp Web

`SelectedFeature.block_key` is a foreign reference into `internal_pricing_blocks` (CRM). Putting the brief next to the catalog it references is the correct ownership boundary. The proposal worker in `Rocket-CRM/rocket-internal` already has a CRM connection and reads the catalog directly. The deck reads the brief via `getCrmSupabase()` — already wired in `src/lib/supabase/crm-server.ts`.

### 4.2 Logo upload contract

- **Format**: PNG, WEBP, JPEG, or SVG.
- **Size limit**: 2 MB.
- **Aspect ratio**: 1:1 with 5% tolerance (0.95 ≤ width/height ≤ 1.05). Validated **client-side** at file selection time. SVG is exempt (vector, square at any render size).
- **Path**: `project-briefs/{briefId}/logo-square.{ext}`.
- **Bucket**: `project-briefs`, public-read (both surfaces render without auth).

The form-layer enforcement is intentional — server `sharp` integration would add a heavyweight dependency for a mostly-cosmetic check. If the SE bypasses the client-side validation, the worst case is a non-square logo that displays compressed or letter-boxed; the brief data itself stays clean.

---

## 5. Derivation — brief → per-surface input shapes

Both surfaces consume *derived* shapes from `src/lib/project-brief/derive.ts`. Neither surface's worker / writer / inject route knows the brief exists.

### 5.1 Proposal payload

`briefToProposalRunPayload(brief)` produces a shape that matches `internal-proposal/lib/types.ts:RunCreateInput` minus the per-run knobs:

```ts
{
  customer_name, customer_industry,
  selected_features[], business_context, system_context[], module_contexts[],
  language, tone_locale
}
```

The proxy at `/api/internal-proposal/runs` accepts `{ project_brief_id, ...runOptions }`, resolves the brief, merges the derived payload with run-only fields, and forwards to the worker. The worker (`Rocket-CRM/rocket-internal`) is unchanged — it still receives flat `RunCreateInput`.

### 5.2 Deck `ClientContext`-like

`briefToDeckContext(brief, meta?)` produces a shape compatible with the legacy `ClientContext`, plus the new fields the inject route reads:

```ts
{
  brand: { primary, accent /* = secondary */, logoUrl /* = logoSquareUrl */, companyName, productName?, date? },
  client: { name, industry, size?, markets? },
  persona?,
  modules: string[],     // derived from selectedFeatures[].module_key (deduped)
  // Phase-1 extras (the new inject route reads directly):
  selectedFeatures, systemContext, moduleContexts, businessContext,
  toneLocale, language, notes,
  tone: brief.toneLocale,           // legacy free-string alias
  showcaseIdeas: brief.notes,       // legacy alias
}
```

Two backwards aliases exist for the deck's legacy field names: `brand.accent` ← `brand.secondary`, `brand.logoUrl` ← `client.logoSquareUrl`. Slides written before Phase 0 keep working; new code reads the canonical names.

### 5.3 Reverse — legacy `ClientContext` → transient brief

`legacyContextToTransientBrief(ctx)` synthesizes a `ProjectBrief`-shaped object in memory from a pre-Phase-0 deck's `presentations.context` jsonb. Used by the inject route when `presentations.project_brief_id` is null. Not persisted; the SE can press "Save as brief" in the composer to materialize it.

This is the migration window's safety net. Plan to drop this helper once existing decks have been re-pointed at briefs.

---

## 6. Form layer

### 6.1 Standalone manager

`/project-briefs` (`src/app/project-briefs/page.tsx`) renders a list + an editor. Same field catalog the proposal and the deck render. Owns the canonical UX for create / edit / delete / logo upload.

### 6.2 Embed in the proposal form

`/internal-proposal` carries `BriefPicker` (`src/components/internal/BriefPicker.tsx`) at the top of the run-create form. Loading a brief prefills client identity, business context, selected features, module contexts, system context, language, tone. Run-only knobs (audiences, detail, clarification mode, attributes, sources, integration scope, operations nuances) stay where the SE left them. Saving harvests current form state into a `ProjectBriefInput` and writes back to CRM.

### 6.3 Embed in the composer

`/composer` `ContextPanel` carries `BriefPicker` + the same `<BriefForm>` rendered by `/project-briefs`. `DraftState.brief: ProjectBriefInput` is the source of truth; the legacy `DraftState.context` is a derived snapshot (computed via `syncContextFromBrief`) that the renderer + persist path consume unchanged.

Brief-load behaviour:

- Resolves the linked brief into `draft.brief` (full field catalog, including business context, selected features, module contexts, system context).
- Auto-ticks any `selectedFeatures[].module_key` into the Default deck panel's `products`. The user can still toggle modules independently; brief edits only *add* matching modules.
- Mirrors `client.name` into the slide-meta `company` string so the title bar tracks the brief.

Save behaviour:

- "Save changes" from `BriefPicker` round-trips the entire `draft.brief` (no data loss — the pre-Phase-0 composer harvest used to write empty `selectedFeatures`/`moduleContexts`/`systemContext`/`businessContext`, which destroyed proposal-side fields).
- Publishing (`POST /api/presentations`) sends `project_brief_id` so `presentations.project_brief_id` points back at CRM.

Publish-with-AI gating: `Publish + AI content` is blocked unless `draft.brief.client.name` is set AND `draft.brief.selectedFeatures.length > 0`. Without selected features the worker's MCP grounding can't fire and the resulting slides are generic; the gate forces the SE to fill the engagement scope first.

The composer's slide selection (default-deck panel) and per-slide editing remain on the composer; they do not move onto the brief.

### 6.4 What both forms render the same

| Section | Fields |
|---|---|
| Client identity | `name`, `industry`, `size`, `markets[]`, `logoSquareUrl` |
| Brand | `primary`, `secondary` |
| Business context | `parent_group`, `scale`, `business_model_summary`, `geographic_footprint`, `hosting_preference`, `compliance_regime[]`, `go_live_target` |
| Persona | `demographics`, `behaviors`, `goals` |
| Engagement scope | `selectedFeatures[]` (pricing blocks), `selectedCapabilities[]` (CRM capability slugs — drives v2 gap Q&A + dossier), `moduleContexts[]`, `systemContext[]` |
| Voice | `toneLocale`, `language`, `notes` |

### 6.5 What's specific to each form

- **Proposal-only:** `audiences[]`, `detail`, `clarification_mode`, `attributes.{has_tor, requires_phasing, requires_clause_coverage_matrix}`, source bundle uploader, `integration_scope.*`, `operations_nuances`, `linked_deck_slug`, model selectors.
- **Deck-only:** `title`, `slug`, `meta.date`, default-deck panel + per-slide reorder.

---

## 7. Migrations

Both migrations are **applied** in production. They remain in the repo as the source-of-truth schema for fresh clones / staging environments.

### 7.1 CRM — `internal-proposal/db/migrations/0008_project_briefs.sql`

Creates `public.project_briefs`, adds `internal_proposal_run.project_brief_id`, creates the `project-briefs` storage bucket. Project ref: `wkevmsedchftztoolkmi`. Applied.

### 7.2 Corp Web — `db/migrations-corp-web/0001_project_brief_pointer.sql`

Adds `presentations.{project_brief_id, dossier, evidence}` and `presentation_slides.{feedback, lint_violations}`. Project ref: `uzebtdlhoptnuqwgdnor`. Applied.

Both are append-only with `if not exists` guards — re-running is a no-op.

### 7.3 Backfill (deferred)

Existing `internal_proposal_run` rows have brief fields denormalized on the row. A one-shot script can read each row, build a brief from its denormalized fields, insert into `project_briefs`, and set `project_brief_id`. Same pattern for existing `presentations.context` rows.

The API tolerates `project_brief_id = null` indefinitely (transient-brief fallback in `legacyContextToTransientBrief`). The backfill is correctness-improving, not safety-critical.

---

## 8. API

| Method | Path | Notes |
|---|---|---|
| `GET` | `/api/project-briefs` | List (id, clientName, clientIndustry, selectedFeatureCount, hasLogo, updatedAt) |
| `POST` | `/api/project-briefs` | Create. Body = `ProjectBriefInput` |
| `POST` | `/api/project-briefs/[id]/duplicate` | Clone payload + logo into a new row. Optional body `{ name }`; defaults to `<source client name> (copy)`. V2 lifecycle fields reset to defaults |
| `PATCH` | `/api/project-briefs/[id]/rename` | Update `client.name` only. Body `{ name }`. Does **not** reset v2 lifecycle |
| `GET` | `/api/project-briefs/[id]` | Read full brief |
| `PATCH` | `/api/project-briefs/[id]` | Replace payload (the body is a full `ProjectBriefInput`). Resets v2 lifecycle (`gap_qa`, `dossier_*`, `proposal_status→draft`); keeps `source_artifacts` |
| `DELETE` | `/api/project-briefs/[id]` | Hard delete. Pointers in `internal_proposal_run` go to null via the FK's `on delete set null`; `presentations.project_brief_id` does not (cross-project, no FK) — those need an app-side cleanup if you care about referential cleanliness |
| `POST` | `/api/project-briefs/[id]/logo` | Multipart upload. Returns `{ url }` |

All routes require the internal-proposal cookie or header (`INTERNAL_PROPOSAL_AUTH_*`). Same auth as the proposal form.

---

## 9. Decisions log

| Decision | Why |
|---|---|
| Brief lives in CRM | `selectedFeatures[]` references `internal_pricing_blocks` (CRM) |
| Square logo only (1:1) | Deterministic shape for `<ClientLogo>` / `<BrandLogo>` / abstracted-ui brand-theme; render at any size with object-fit: contain |
| Aspect-ratio enforcement client-side | No server-side `sharp` dependency for a cosmetic check |
| Brand `secondary` (not `accent`) | Matches the primary/secondary design vocab; backwards alias for the deck's existing `accent` |
| `notes` is free-form, not structured | Anything genuinely structured belongs in a typed field. `notes` is the catch-all for things not yet structured |
| `pointCollection`, `exampleRewards[]`, `campaigns[]` dropped | Free-form `moduleContexts[].context_text` is more honest than half-structured proxies. The writer + illustration prompts already grep prose for entity names |
| Per-run knobs not on brief | Same client may want different proposal types (executive vs technical) in the same quarter |
| Tone is a brief-level enum, not run-level | The default voice is a per-client constant; per-run overrides live on the run row |
| Deck pointer has no FK to CRM brief | Cross-project FKs aren't supported in Supabase. The app handles dangling pointers (transient-brief fallback) |
| Form schema NOT reified into a runtime data structure | Both forms render the same field catalog through hand-written components instead of a generic schema-driven renderer. Cheaper than building a form-renderer library; the catalog is small enough to hand-maintain |

---

## 10. References

- `src/lib/project-brief/types.ts` — TypeScript truth (canonical).
- `src/lib/project-brief/derive.ts` — per-surface derivation functions.
- `src/lib/project-brief/store.ts` — CRM CRUD + logo upload.
- `src/components/internal/BriefPicker.tsx` — shared form widget.
- `internal-proposal/REQUIREMENTS.md` §3 — proposal-side input contract that the brief subsumes.
- `docs/DECK_GENERATION_REQUIREMENTS.md` §3 — deck-side input contract derived from the brief.
