# Product Feature Catalog — Thread Handoff (2026-05-18, Round 3)

## Task

Write a single authoritative MD catalog of every feature across the Rocket CX Platform (Loyalty / Marketing Automation / Customer Service / Campaigns / Platform). Source of truth for **AI proposal writing** — not engineering reference.

Output file: **`docs/PRODUCT_FEATURE_CATALOG.md`** (already exists; ~2151 lines so far).

## Status — what's done

### Completed sections (cumulative)

**Loyalty domain — fully complete:**

- Top matter (intro, structure spec, writing principles)
- Rewards (+ 3 sub: Reward Groups, Promo Code Management, Reward Sourcing & Partner Fulfillment)
- Tiers (+ 3 sub: Tier Upgrade, Tier Maintenance, Tier Progress)
- Currency
- Forms
- PDPA Consent (brief — synthesized; no dedicated blocks)
- Packages
- Persona Entitlements
- Stored Value Cards
- Tags & Personas
- Activity-Based Earning
- Store & Partner Classification
- **Purchase Transactions (+ 3 sub: Marketplace Integration, Receipt Upload Earning, Event Promo Engine)** ← Round 3

**Marketing Automation (AMP) domain — fully complete:**

- Domain header + intro paragraph
- AMP Workflows
- AMP AI Decisioning

### Decisions locked in (do not re-litigate)

1. **File location** — `docs/PRODUCT_FEATURE_CATALOG.md`. Single file (revisit at ~3000 lines).
2. **Hierarchy** — `##` Domain → `###` Feature → `####` Sub-feature.
3. **Per-feature template** — exactly four bold-labeled blocks in this order:
   - **Overview** — what the feature is (one paragraph)
   - **Purpose** — why it exists / the business outcome
   - **User Journey** — `*Admin journey*` + `*Member journey*` + `*Edge cases*` sub-blocks
   - **Configurations & Rules** — *exhaustive*; tables strongly preferred over prose
4. **Knowledge block types pulled** — `overview`, `rules`, `frontend_journey`. **Never** `technical_reference`.
5. **Sub-features without their own blocks** — synthesize from parent block content. Don't skip them. (Receipt Upload Earning was synthesized from Purchase Transactions parent in Round 3.)
6. **Platform domain filter** — keep only `authentication-and-signup` and `translation-system`. **Skip** `admin-panel`, `internal-knowledge`, `action-macro-shared`, `resource-content-shared`, `universal-action-system-shared`, `display-settings`.
7. **Tone** — preserve the source-block tone per feature.

### CRITICAL — Source-of-truth policy

**Lead with the CRM Knowledge MCP. Do NOT grep `requirements/<Domain>.md` by default.** The previous thread used the deep `Currency.md` doc to enumerate field-level enums, and the user pushed back: knowledge blocks are the source for the catalog. Currency section (lines ~604–897) was written with doc-grep; everything written after that (Forms onward, including Purchase Transactions and AMP) used MCP only.

Trade-off accepted: where MCP blocks describe configuration **categorically** (e.g., "field types include type, validation, options"), the catalog reflects that level of fidelity — no invented enum values. If a future feature needs deeper enum-level depth, the user will say so explicitly that turn.

### Workflow per feature

1. **Batch in one turn**:
   - `CallMcpTool` → `user-crm-knowledge` → `get_feature_context` with `feature_slug: "<slug>"`, `knowledge_types: ["overview", "rules", "frontend_journey"]`, `include_children: true`.
   - Optional: `CallMcpTool` → `search_semantic` for 1–2 targeted questions if `get_feature_context` returns empty/thin (use this for sub-features with no curated blocks).
2. **Write** — `StrReplace` to append the section to `docs/PRODUCT_FEATURE_CATALOG.md` using the four-block template.

### Slug-discovery trick

`resolve_feature_term` only matches exact aliases. If it returns `[]`, fall back to grepping the cached feature tree at:

`/Users/rangwan/.cursor/projects/Users-rangwan-Documents-Supabase-CRM/agent-tools/5db0347a-f5d7-4dde-82b4-19dcba2dbc5a.txt`

This dump is from the original thread's `get_feature_tree` call (1047 lines, full hierarchy). Grep for `"name": "X"` and the line above has `"slug": "..."`.

### Batching multiple features

User confirmed: **batch multiple features per round to save time.** Round 2 did 7 features in one turn-pair; Round 3 did 6 (Purchase Transactions + 3 sub + AMP Workflows + AMP AI Decisioning). Continue that rhythm.

## Open — what's left to write (in order)

### Customer Service (largest domain — likely 1–2 thread checkpoints just for CS)

1. **Connectivity** + 3 sub-features (Channel Connectors, Phone Number Management, Unified Customer Identity)
2. **Agent Workspace** + 4 sub-features (Unified Inbox, Voice Console, Live Assist, Routing & Assignment)
3. **Ticket Management** — slug confirmed: `ticket-management`
4. **Rules-Based Automation** + 3 sub-features (Chatbot Flows: `chatbot-flows`, IVR Flows, Rules & Triggers: `rules-and-triggers`)
5. **CS AI** + 3 sub-features (Brand AI Configuration, Agent Operating Procedures, Watchtower: `watchtower`)
6. **Knowledge Base**
7. **Actions & Integrations**
8. **CSAT & Customer Feedback** — slug confirmed: `csat-and-feedback`
9. **Analytics & Logs** + 2 sub-features (Analytics: `analytics`, Logs)

CS source docs are prefixed `CS_` in `requirements/` and `docs/`. Add `## Customer Service (CS)` domain header with intro paragraph before the first feature.

### Campaigns

10. **Spin Wheel**
11. **Mass Lucky Draw**
12. **Missions**
13. **Referral**
14. **Check-in** — slug confirmed: `checkin`

Add `## Campaigns` domain header with intro paragraph before the first feature.

### Platform (filtered)

15. **Authentication & Signup** + 1 sub-feature (Custom Fields) — slug confirmed: `authentication-and-signup`
16. **Translation System** — try `translation-system`

Add `## Platform` domain header with intro paragraph before the first feature.

**Estimated final size**: ~3500–4000 lines. If the user pushes back on size near the end, fallback is splitting per-domain into separate files.

## Next exact step

Open this checkpoint as your first message, then start with the **Customer Service** domain.

**First turn must batch the gather calls for Connectivity + 3 sub-features** (mirroring the Round 3 opener for Purchase Transactions):

```
CallMcpTool: get_feature_context(feature_slug="connectivity", knowledge_types=["overview","rules","frontend_journey"], include_children=true)
CallMcpTool: get_feature_context(feature_slug="channel-connectors", knowledge_types=["overview","rules","frontend_journey"], include_children=true)
CallMcpTool: get_feature_context(feature_slug="phone-number-management", knowledge_types=["overview","rules","frontend_journey"], include_children=true)
CallMcpTool: get_feature_context(feature_slug="unified-customer-identity", knowledge_types=["overview","rules","frontend_journey"], include_children=true)
```

If any slug returns `[]` or fails, fall back to the cached feature-tree grep (path above) to find the right slug, then re-batch.

**Before writing the first feature**, append the CS domain header + intro paragraph.

After Connectivity + sub-features, batch Agent Workspace + 4 sub-features (Unified Inbox, Voice Console, Live Assist, Routing & Assignment) in the next round. Then 3 features per round (Ticket Mgmt + Rules-Based Automation + sub-features), and so on.

**Suggested checkpoint cadence for CS**: aim to checkpoint once mid-CS (after ~5–6 features) to keep cost low — CS is large enough to warrant two threads.

## Critical context the new thread must know

### MCP source

- Server: `user-crm-knowledge`
- Primary tool: `get_feature_context`
- Schema: `/Users/rangwan/.cursor/projects/Users-rangwan-Documents-Supabase-CRM/mcps/user-crm-knowledge/tools/get_feature_context.json`
- Feature tree cache: `/Users/rangwan/.cursor/projects/Users-rangwan-Documents-Supabase-CRM/agent-tools/5db0347a-f5d7-4dde-82b4-19dcba2dbc5a.txt`

### Format reference (look at examples in the catalog)

- **Tiers section** (lines ~341–602): the format the user signed off on. Heavy on tables, exhaustive enum coverage where blocks provide it.
- **Currency section** (lines ~604–897): represents deeper-than-default depth from doc-grep. **Don't aim to match Currency's depth** unless blocks naturally provide it.
- **Purchase Transactions + sub-features (Round 3)**: lines ~1644–1922. Good template for parent-feature + 3 sub-features pattern, including the synthesize-from-parent case (Receipt Upload Earning).
- **AMP Workflows / AMP AI Decisioning (Round 3)**: lines ~1947–2151. Good template for a fresh domain with header + intro + 2 features. Use this as the model for kicking off CS / Campaigns / Platform.

### Existing catalog structure (do not break)

- Top matter ends with `---` separator before `## Loyalty`.
- Each major domain is separated by `---` and starts with `## <Domain>` + intro paragraph.
- Each feature is separated by `---`.
- File currently ends right after AMP AI Decisioning — next append should add `## Customer Service (CS)` domain header with intro, then Connectivity.

### Domain intro paragraph pattern (for CS / Campaigns / Platform)

Look at Round 3's AMP intro for the model:

> The AMP domain is the platform's **marketing automation engine** — the layer that takes CRM events ... It has two complementary capabilities: ...

Each new domain should open with a 2–4 sentence framing paragraph that says **what the domain is, what it spans, and how its features relate** (so the AI proposal writer has context before diving into feature details).

### Tone calibration warning

Preserve per-feature tone. Some blocks are sales-flavored, most are matter-of-fact. Don't normalize. CS blocks tend to be more matter-of-fact / technical than Loyalty blocks.

### Thread cost discipline

- Round 2 did 7 features comfortably; Round 3 did 6 (4 + 2).
- **Checkpoint every 6–8 features** or at every major domain boundary.
- CS is large — 9 features + ~12 sub-features. **Plan to checkpoint mid-CS** (e.g., after Connectivity + Agent Workspace + Ticket Management = 3 features + 7 sub-features). Then resume with Rules-Based Automation onward in a fresh thread.

### Hard-banned operations

- `technical_reference` knowledge_type pulls. User explicitly excluded technical architecture.
- Including engineering-internal Platform sub-features (`admin-panel`, etc.).
- Full `Read` of any `requirements/<Domain>.md` over 30KB. **Avoid `requirements/<Domain>.md` entirely unless the user explicitly asks for that depth on a specific feature.**

### MCP result hygiene

After each `get_feature_context` (returns 4–10 blocks, ~10–30KB each), extract findings to text in the same turn-pair when writing the section. Do not re-reference the raw MCP dumps in later turns.

### Round 3 notes (slug & content discoveries)

- `purchase-transactions` slug works; returned 3 blocks (overview, rules, frontend_journey).
- `marketplace-integration` slug works; returned 3 blocks.
- `event-promo-engine` slug works; returned 3 blocks.
- `receipt-upload-earning` slug exists but returned **0 blocks** (curated_sub_feature with no curated content). Synthesized from Purchase Transactions parent + a `search_semantic` confirmation that no other feature owned the receipt-upload content.
- `amp-workflows` slug works; returned 4 blocks (extra `Scheduled Triggers` rules block).
- `amp-ai-decisioning` slug works; returned 3 blocks.

For CS, **expect some sub-feature slugs to return `[]`** — Channel Connectors, Phone Number Management, Voice Console, Live Assist, Brand AI Configuration, Agent Operating Procedures, IVR Flows, and Logs are all likely to be sub-feature slugs that may not have curated blocks. When that happens, do a single targeted `search_semantic` to confirm no other feature owns the content, then synthesize from the parent feature's blocks.
