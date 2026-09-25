# Product Feature Catalog — Thread Handoff (2026-05-18, Round 2)

## Task

Write a single authoritative MD catalog of every feature across the Rocket CX Platform (Loyalty / Marketing Automation / Customer Service / Campaigns / Platform). Source of truth for **AI proposal writing** — not engineering reference.

Output file: **`docs/PRODUCT_FEATURE_CATALOG.md`** (already exists; append remaining features to it; ~1642 lines so far).

## Status — what's done

### Completed sections

- Top matter (intro, structure spec, writing principles)
- **Loyalty → Rewards** (+ 3 sub: Reward Groups, Promo Code Management, Reward Sourcing & Partner Fulfillment)
- **Loyalty → Tiers** (+ 3 sub: Tier Upgrade, Tier Maintenance, Tier Progress)
- **Loyalty → Currency**
- **Loyalty → Forms**
- **Loyalty → PDPA Consent** (brief — knowledge blocks were empty; synthesized from Forms-block PDPA fields)
- **Loyalty → Packages**
- **Loyalty → Persona Entitlements**
- **Loyalty → Stored Value Cards**
- **Loyalty → Tags & Personas**
- **Loyalty → Activity-Based Earning**
- **Loyalty → Store & Partner Classification**

### Decisions locked in (do not re-litigate)

1. **File location** — `docs/PRODUCT_FEATURE_CATALOG.md`. Single file (revisit at ~3000 lines).
2. **Hierarchy** — `##` Domain → `###` Feature → `####` Sub-feature.
3. **Per-feature template** — exactly four bold-labeled blocks in this order:
   - **Overview** — what the feature is (one paragraph)
   - **Purpose** — why it exists / the business outcome
   - **User Journey** — `*Admin journey*` + `*Member journey*` + `*Edge cases*` sub-blocks
   - **Configurations & Rules** — *exhaustive*; tables strongly preferred over prose
4. **Knowledge block types pulled** — `overview`, `rules`, `frontend_journey`. **Never** `technical_reference`.
5. **Sub-features without their own blocks** — synthesize from parent block content. Don't skip them.
6. **Platform domain filter** — keep only `authentication-and-signup` and `translation-system`. **Skip** `admin-panel`, `internal-knowledge`, `action-macro-shared`, `resource-content-shared`, `universal-action-system-shared`, `display-settings`.
7. **Tone** — preserve the source-block tone per feature.

### CRITICAL — Source-of-truth policy (user-clarified this round)

**Lead with the CRM Knowledge MCP. Do NOT grep `requirements/<Domain>.md` by default.** The previous thread used the deep `Currency.md` doc to enumerate field-level enums, and the user pushed back: knowledge blocks are the source for the catalog. The Currency section (lines ~604–897) was written with doc-grep support; everything written after that (Forms onward) used MCP only.

Trade-off accepted: where the MCP blocks describe configuration **categorically** (e.g., "field types include type, validation, options"), the catalog reflects that level of fidelity — no invented enum values. If a future feature needs deeper enum-level depth, the user will say so explicitly that turn.

### Workflow per feature

1. **Batch in one turn**:
   - `CallMcpTool` → `user-crm-knowledge` → `get_feature_context` with `feature_slug: "<slug>"`, `knowledge_types: ["overview", "rules", "frontend_journey"]`, `include_children: true`.
   - Optional: `CallMcpTool` → `search_semantic` for 1–2 targeted questions if `get_feature_context` looks thin.
2. **Write** — `StrReplace` to append the section to `docs/PRODUCT_FEATURE_CATALOG.md` using the four-block template.

### Slug-discovery trick

`resolve_feature_term` only matches exact aliases. If it returns `[]`, fall back to grepping the cached feature tree at:

`/Users/rangwan/.cursor/projects/Users-rangwan-Documents-Supabase-CRM/agent-tools/5db0347a-f5d7-4dde-82b4-19dcba2dbc5a.txt`

This dump is from the original thread's `get_feature_tree` call (1047 lines, full hierarchy). Grep for `"name": "X"` and the line above has `"slug": "..."`.

### Batching multiple features

User confirmed: **batch multiple features per round to save time.** Round 2 did 7 features in one turn-pair (gather all contexts → single big StrReplace). Continue that rhythm.

## Open — what's left to write (in order)

### Loyalty (remaining)

1. **Purchase Transactions** + 3 sub-features
   - Marketplace Integration
   - Receipt Upload Earning
   - Event Promo Engine (the `event-promo-engine` slug appeared in a search result this round — has its own blocks)
   - Likely slugs to try: `purchase-transactions`, `marketplace-integration`, `receipt-upload-earning`, `event-promo-engine`

### AMP (Marketing Automation)

2. **AMP Workflows** — slug confirmed: `amp-workflows`
3. **AMP AI Decisioning** — try `amp-ai-decisioning`

### Customer Service

4. **Connectivity** + 3 sub-features (Channel Connectors, Phone Number Management, Unified Customer Identity)
5. **Agent Workspace** + 4 sub-features (Unified Inbox, Voice Console, Live Assist, Routing & Assignment)
6. **Ticket Management** — slug confirmed: `ticket-management`
7. **Rules-Based Automation** + 3 sub-features (Chatbot Flows: `chatbot-flows`, IVR Flows, Rules & Triggers: `rules-and-triggers`)
8. **CS AI** + 3 sub-features (Brand AI Configuration, Agent Operating Procedures, Watchtower: `watchtower`)
9. **Knowledge Base**
10. **Actions & Integrations**
11. **CSAT & Customer Feedback** — slug confirmed: `csat-and-feedback`
12. **Analytics & Logs** + 2 sub-features (Analytics: `analytics`, Logs)

CS source docs are prefixed `CS_` in `requirements/` and `docs/`.

### Campaigns

13. **Spin Wheel**
14. **Mass Lucky Draw**
15. **Missions**
16. **Referral**
17. **Check-in** — slug confirmed: `checkin`

### Platform (filtered)

18. **Authentication & Signup** + 1 sub-feature (Custom Fields) — slug confirmed: `authentication-and-signup`
19. **Translation System** — try `translation-system`

**Estimated final size**: ~3000–3500 lines. If the user pushes back on size near the end, fallback is splitting per-domain into separate files.

## Next exact step

Open this checkpoint as your first message, then start with **Purchase Transactions**. First turn must batch:

```
CallMcpTool: get_feature_context(feature_slug="purchase-transactions", knowledge_types=["overview","rules","frontend_journey"], include_children=true)
CallMcpTool: get_feature_context(feature_slug="marketplace-integration", knowledge_types=["overview","rules","frontend_journey"], include_children=true)
CallMcpTool: get_feature_context(feature_slug="receipt-upload-earning", knowledge_types=["overview","rules","frontend_journey"], include_children=true)
CallMcpTool: get_feature_context(feature_slug="event-promo-engine", knowledge_types=["overview","rules","frontend_journey"], include_children=true)
```

If any slug returns `[]` or fails, fall back to grepping the cached feature-tree file (path above) to find the right slug, then re-batch.

After Purchase Transactions and its 3 sub-features are written, continue with **AMP** (2 features), then **CS** (largest domain — likely 1–2 thread checkpoints just for CS).

## Critical context the new thread must know

### MCP source

- Server: `user-crm-knowledge`
- Primary tool: `get_feature_context`
- Schema: `/Users/rangwan/.cursor/projects/Users-rangwan-Documents-Supabase-CRM/mcps/user-crm-knowledge/tools/get_feature_context.json`
- Feature tree cache: `/Users/rangwan/.cursor/projects/Users-rangwan-Documents-Supabase-CRM/agent-tools/5db0347a-f5d7-4dde-82b4-19dcba2dbc5a.txt`

### Format reference

- **Tiers section** (lines ~341–602): the format the user signed off on. Heavy on tables, exhaustive enum coverage where blocks provide it.
- **Currency section** (lines ~604–897): also user-approved, but represents the deeper-than-default depth that came from doc-grep. **Don't aim to match Currency's depth on every feature** — match it only when the knowledge blocks naturally provide that level of detail (Packages, Persona Entitlements, and Stored Value Cards got close because their blocks are dense).

### Existing catalog structure (do not break)

- Top matter ends with `---` separator before `## Loyalty`.
- Each major domain is separated by `---`.
- Each feature is separated by `---`.
- File currently ends right after Store & Partner Classification — next append should add Purchase Transactions and its 3 sub-features.

### Tone calibration warning

Preserve per-feature tone. Some blocks are sales-flavored (e.g., reward sourcing), most are matter-of-fact. Don't normalize.

### Thread cost discipline

- Did 7 features in this round comfortably.
- **Checkpoint every 6–8 features** or at every major domain boundary (Loyalty / AMP / CS / Campaigns / Platform).
- Next natural boundary: after Purchase Transactions + AMP, hand off again before starting CS (CS is large — 9 features + ~12 sub-features).

### Hard-banned operations

- `technical_reference` knowledge_type pulls. User explicitly excluded technical architecture.
- Including engineering-internal Platform sub-features (`admin-panel`, etc.).
- Full `Read` of any `requirements/<Domain>.md` over 30KB. Per the user's clarification this round, **avoid `requirements/<Domain>.md` entirely unless the user explicitly asks for that depth on a specific feature.**

### MCP result hygiene

After each `get_feature_context` (returns 4–10 blocks, ~10–30KB each), extract findings to text in the same turn-pair when writing the section. Do not re-reference the raw MCP dumps in later turns.
