# Product Feature Catalog — Thread Handoff (2026-05-18)

## Task

Write a single authoritative MD catalog of every feature across the Rocket CX Platform (Loyalty / Marketing Automation / Customer Service / Campaigns / Platform). Source of truth for **AI proposal writing** — not engineering reference.

Output file: **`docs/PRODUCT_FEATURE_CATALOG.md`** (already exists; append remaining features to it; ~603 lines so far).

## Status — what's done

### Completed sections

- Top matter (intro, structure spec, writing principles)
- **Loyalty → Rewards** (+ 3 sub-features: Reward Groups, Promo Code Management, Reward Sourcing & Partner Fulfillment)
- **Loyalty → Tiers** (+ 3 sub-features: Tier Upgrade, Tier Maintenance, Tier Progress)

### Decisions locked in (do not re-litigate)

1. **File location** — `docs/PRODUCT_FEATURE_CATALOG.md`. Single file, not split per-domain (yet — revisit at ~3000 lines).
2. **Hierarchy** — `##` Domain → `###` Feature → `####` Sub-feature.
3. **Per-feature template** — exactly four bold-labeled blocks in this order:
   - **Overview** — what the feature is (one paragraph)
   - **Purpose** — why it exists / the business outcome
   - **User Journey** — `*Admin journey*` + `*Member journey*` + `*Edge cases*` sub-blocks
   - **Configurations & Rules** — *exhaustive*; tables strongly preferred over prose
4. **Knowledge block types pulled** — `overview`, `rules`, `frontend_journey`. **Never** `technical_reference` (user explicitly excluded technical architecture).
5. **Sub-features without their own blocks** — synthesize from parent block content (e.g., `tier-upgrade` content came from the parent Tiers block since it has no own blocks). Don't skip them.
6. **Platform domain filter** — keep only `authentication-and-signup` and `translation-system`. **Skip** these (internal/engineering, not proposal-relevant): `admin-panel`, `internal-knowledge`, `action-macro-shared`, `resource-content-shared`, `universal-action-system-shared`, `display-settings`.
7. **Tone** — preserve the source-block tone per feature (some are sales-flavored like `reward-sourcing-services`, others are matter-of-fact like `rewards`). Do NOT force everything to a single tone.

### Critical user feedback on configuration depth

The user pushed back on the first draft: **Configurations were too shallow.** Initial draft just listed categories ("stock control, eligibility filters, ..."). User requirement is to **enumerate every value of every enum, every field of every config object, every legal combination of multi-field rules**.

Example of what's expected for "reward limits":

| Concept | `entity_type` | `metric` | `scope` | What `count` measures | Time units |
|---|---|---|---|---|---|
| Reward Quota | `reward` | `quantity` | `user` or `total` | Units of this single reward | `day` / `week` / `month` / `year` / `all_time` |
| Group Quantity | `reward_group` | `quantity` | `user` or `total` | Total units across the group | `day` / `week` / `month` / `year` / `all_time` |
| Max Distinct | `reward_group` | `distinct_reward` | `user` only | Distinct reward types in the group | `day` / `week` / `month` / `year` / `all_time` |

**This is the bar.** Knowledge blocks alone won't give you this depth — they describe behavior, not field-level config. To hit the bar, **always pull the source `requirements/<Domain>.md` doc** alongside the MCP knowledge blocks and grep for tables / enum lists / config sections.

The writing-principles section of the catalog now codifies this as principle #6:
> **Configurations are exhaustive** — enumerate every option an admin can set. Don't write "stock control"; write "per-reward total stock + per-store allocation + derived used-quantity". Don't write "limits"; write the scope × metric × time-unit matrix.

## Open — what's left to write (in order)

### Loyalty (remaining)

1. **Currency** — source: `requirements/Currency.md` (~139KB — grep first per `12-doc-search.mdc`)
2. **Forms** — source: `requirements/Forms.md`
3. **PDPA Consent** — likely no own doc; pull from MCP + grep `requirements/` for PDPA
4. **Packages** — source: `requirements/Package.md` and `requirements/Package_Contract_Benefit.md`
5. **Persona Entitlements** — source: `requirements/Persona_Entitlement.md`
6. **Purchase Transactions** + 3 sub-features (Marketplace Integration, Receipt Upload Earning, Event Promo Engine) — source: `requirements/Purchase_Transaction.md` + `requirements/Ecommerce_Marketplace_Integration.md`
7. **Store & Partner Classification** — source: likely `requirements/Store_Attribute_Classification.md` (verify with Glob)
8. **Stored Value Cards** — source: feature-docs or grep
9. **Tags & Personas** — source: likely `requirements/Tag_and_Persona.md`
10. **Activity-Based Earning** — source: `requirements/Activity_Based_Earning.md`

### AMP (Marketing Automation)

11. **AMP Workflows** — source: feature-docs + `docs/AMP_*` files
12. **AMP AI Decisioning** — source: feature-docs

### Customer Service

13. **Connectivity** + 3 sub-features (Channel Connectors, Phone Number Management, Unified Customer Identity)
14. **Agent Workspace** + 4 sub-features (Unified Inbox, Voice Console, Live Assist, Routing & Assignment)
15. **Ticket Management**
16. **Rules-Based Automation** + 3 sub-features (Chatbot Flows, IVR Flows, Rules & Triggers)
17. **CS AI** + 3 sub-features (Brand AI Configuration, Agent Operating Procedures, Watchtower)
18. **Knowledge Base**
19. **Actions & Integrations**
20. **CSAT & Customer Feedback**
21. **Analytics & Logs** + 2 sub-features (Analytics, Logs)

CS source docs are prefixed `CS_` in `requirements/` and `docs/` (per `00-core.mdc`).

### Campaigns

22. **Spin Wheel**
23. **Mass Lucky Draw**
24. **Missions** — source: `requirements/feature-docs/missions.md`, `Mission.md`
25. **Referral** — source: `requirements/feature-docs/referral.md`, `Referral.md`
26. **Check-in** — source: `requirements/feature-docs/checkin.md`

### Platform (filtered)

27. **Authentication & Signup** + 1 sub-feature (Custom Fields) — source: `requirements/Authentication.md`
28. **Translation System** — source: likely `Translation_System.md` (verify with Glob)

**Estimated final size**: ~2500–3000 lines. If user pushes back on size, fallback is splitting per-domain into separate files (`PRODUCT_FEATURE_CATALOG_LOYALTY.md`, `_AMP.md`, `_CS.md`, etc.).

## Next exact step

For each feature, run this sequence (batch independent calls per `16-tool-batching.mdc`):

1. **Batch in one turn**:
   - `CallMcpTool` → `user-crm-knowledge` → `get_feature_context` with `feature_slug: "<slug>"`, `knowledge_types: ["overview", "rules", "frontend_journey"]`, `include_children: true`.
   - `Glob` to locate the source requirement doc.
   - `Grep` `^#{1,4} ` on the source doc to get the heading map.
2. **Next turn** — scoped `Read` of the heading sections most likely to contain config tables / enum lists (typically: "Core Tables", "Configuration", "Business Rules", "Concepts & Glossary", "<Feature> Properties", "<Feature> Conditions", anything with "Field | Type | Purpose" tables).
3. **Write** — `StrReplace` to append the feature's section to `docs/PRODUCT_FEATURE_CATALOG.md`. Use the four-block template. Tables wherever possible in Configurations.

### Concrete first action for the new thread

Start with **Currency** (loyalty domain, next in order). First turn must batch:

```
CallMcpTool: get_feature_context(feature_slug="currency", knowledge_types=["overview","rules","frontend_journey"], include_children=true)
Glob: requirements/Currency.md
Grep: ^#{1,4}  on requirements/Currency.md (output_mode=content, -n=true)
```

Then on the next turn, scoped Read of the relevant Currency sections (likely "Wallet", "Earn Factors", "Expiry Management", "Reverse / Refund").

**Do NOT full-read `Currency.md`** — it's ~139KB and on the hook-enforced ban list (`12-doc-search.mdc`). The block-large-doc-read.sh hook will reject it.

## Critical context the new thread must know

### MCP source

- Server: `user-crm-knowledge`
- Primary tool: `get_feature_context` (deterministic; gets every block for a feature + descendants)
- Schema lives at: `/Users/rangwan/.cursor/projects/Users-rangwan-Documents-Supabase-CRM/mcps/user-crm-knowledge/tools/get_feature_context.json`
- `get_feature_tree` returns the full hierarchy — already pulled in this thread, list of all feature slugs is in the "Open" section above
- The MCP feature-tree dump from this thread is cached at: `/Users/rangwan/.cursor/projects/Users-rangwan-Documents-Supabase-CRM/agent-tools/5db0347a-f5d7-4dde-82b4-19dcba2dbc5a.txt` (1047 lines, the full tree)

### Writing principles file

`.cursor/rules/13-feature-guide-writing.mdc` — Pyramid, MECE, same-abstraction-level, concrete-over-fluff, anti-AI-voice, no-redundancy. These are applied in the catalog's top matter and must be followed in every new section.

### Existing catalog structure (do not break)

- Top matter ends with `---` separator before `## Loyalty`.
- Each major domain is separated by `---`.
- Each feature is separated by `---` (visible between Rewards and Tiers; will be between Tiers and Currency).

### Tone calibration warning

The `reward-sourcing-services` overview uses sales-flavored phrasing ("risk-free", "strategic aims") because the source block is tagged `output_uses: proposal_content`. Most other blocks are matter-of-fact. **Preserve per-feature tone** — don't normalize.

### Hard-banned operations

- Full `Read` of any `requirements/<Domain>.md` over 30KB. Grep first, scoped read second. Hook will reject violations.
- `technical_reference` knowledge_type pulls. User explicitly excluded technical architecture.
- Including engineering-internal Platform sub-features (`admin-panel`, etc. — see decision #6).

### MCP result hygiene

After each `get_feature_context` (returns 5–10 blocks, ~30–50KB), the next turn must extract findings to text and not re-reference the raw dump. Per `16-tool-batching.mdc` § MCP Result Hygiene.

### Thread cost discipline

This catalog work will fill threads quickly because each feature pulls a large MCP result + source doc grep + scoped reads + a long StrReplace. Suggested rhythm:

- **1 feature per turn pair** (gather-turn + write-turn). Don't try to batch 3 features in one gather-turn — context blows up.
- **Checkpoint every 5–6 features** (so every ~10–12 turns) into a new thread, even before the 15/80 hard trigger fires. Each domain (Loyalty / AMP / CS / Campaigns / Platform) is a natural checkpoint boundary.

### Reference: the format that passed user review

See `docs/PRODUCT_FEATURE_CATALOG.md` lines for `### Tiers` → `**Configurations & Rules**` (around line 320–500). This is the format the user signed off on. Match this depth for every remaining feature. Key calibration points:

- Field tables include type, values/enum, and behavior columns.
- Enum values are enumerated as table rows, not prose bullets.
- Cross-cutting matrices (e.g., valid combinations, persona × user-type, behavior matrix) are tables.
- Operating rules are bullets after the config tables, not mixed in.
- Limitations are a separate sub-block at the end.

### User clarifications made in this thread

- "TS" = Tiers, not Translation System (confirmed implicitly by user not correcting).
- Sub-features without own blocks: synthesize from parent (user accepted).
- Tone: preserve source-block tone (user did not push back on tonal inconsistency between Rewards and Reward Sourcing).
