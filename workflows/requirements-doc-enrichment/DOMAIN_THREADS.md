# Domain thread prompts (copy-paste)

**How to use:** Start a **new Cursor thread** per domain. Paste **one** block below as the first message. Attach nothing else unless the block says to — paths are repo-relative from `supabase-crm`.

**Spreadsheet:** [`domain-thread-prompts.csv`](./domain-thread-prompts.csv) — one row per domain; copy the `prompt` column (regenerate from this file if prompts change).

**Workflow:** `workflows/requirements-doc-enrichment/REFERENCE.md`

**Shopify reference MD** (referrals, on-site content, integrations): repo copy at `requirements/reference/SHOPIFY_REFERRALS_ONSITE_INTEGRATIONS.md`; master at `/Users/rangwan/Downloads/SHOPIFY_REFERRALS_ONSITE_INTEGRATIONS.md` — if Downloads is newer, copy into repo before the thread.

**Editing:** Follow REFERENCE §5 — fold legacy into spine; avoid bulk deletes on targeted passes unless content is clearly obsolete or the product has materially changed. No line-count approval gates.

---

## Priority 1 — Shopify reference MD cluster

### Referral

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/Referral.md

Shopify reference MD (mandatory): Read requirements/reference/SHOPIFY_REFERRALS_ONSITE_INTEGRATIONS.md — Part 1 (referrals on Shopify). Sync from /Users/rangwan/Downloads/SHOPIFY_REFERRALS_ONSITE_INTEGRATIONS.md if newer. Reference MD wins over stale requirement text unless live code contradicts (then note in Known gaps).

Fold the existing "technical reference" section into spine System/Rules; delete duplicate H1. Verify referral_program, claim, member_code, SMART attribution, campaign reward slots, embedded admin gating against loyalty-admin, rewarding-shopify, Supabase MCP.

Docs only; CHANGELOG when done.
```

### Display_Settings

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/Display_Settings.md

Shopify reference MD (mandatory): Read requirements/reference/SHOPIFY_REFERRALS_ONSITE_INTEGRATIONS.md — Part 2 (on-site content on Shopify). Sync from /Users/rangwan/Downloads/SHOPIFY_REFERRALS_ONSITE_INTEGRATIONS.md if newer.

Merge legacy "System design" / tables blocks into spine; map touchpoints (Hub, product points, landing, wishlist, banners) to Journeys and System. Verify loyalty-admin routes and shopify-extension-api / rewarding-shopify per reference MD.

Docs only; CHANGELOG when done.
```

### Shopify (hub)

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/Shopify.md

Shopify reference MD (mandatory): Read requirements/reference/SHOPIFY_REFERRALS_ONSITE_INTEGRATIONS.md — all parts for routing context; keep platform plumbing here, feature behaviour as hub → feature doc pointers only. Sync from /Users/rangwan/Downloads/SHOPIFY_REFERRALS_ONSITE_INTEGRATIONS.md if newer.

Convert SECTION: headings to ## / ### where feasible; trim feature-level prose moved to Referral, Display_Settings, Third_Party, Outbound. Top routing table: feature → doc › section.

Docs only; CHANGELOG when done.
```

### Third_Party_Integrations

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/Third_Party_Integrations.md

Shopify reference MD (mandatory): Read requirements/reference/SHOPIFY_REFERRALS_ONSITE_INTEGRATIONS.md — Part 3 (integrations). Sync from /Users/rangwan/Downloads/SHOPIFY_REFERRALS_ONSITE_INTEGRATIONS.md if newer.

Cover Judge.me, Gorgias, connect flows, merchant_credentials; fold legacy into spine. Verify edge fns and admin /integrations paths.

Docs only; CHANGELOG when done.
```

### Outbound_Integrations

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/Outbound_Integrations.md

Shopify reference MD (mandatory): Read requirements/reference/SHOPIFY_REFERRALS_ONSITE_INTEGRATIONS.md — Part 3 (Klaviyo outbound, shared outbox). Sync from /Users/rangwan/Downloads/SHOPIFY_REFERRALS_ONSITE_INTEGRATIONS.md if newer.

Align chokepoint_event_outbox / crm-event-processors paths with live registry. Fold legacy into spine.

Docs only; CHANGELOG when done.
```

### Earn_Channel

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/Earn_Channel.md

Shopify reference MD (mandatory): Read requirements/reference/SHOPIFY_REFERRALS_ONSITE_INTEGRATIONS.md — Part 1 (campaign:referral vs program gate) and Part 2 (earn surfaces on storefront). Sync from /Users/rangwan/Downloads/SHOPIFY_REFERRALS_ONSITE_INTEGRATIONS.md if newer.

Consolidate Earn_Channel / Earn_Channel_Canonical / FE guide pointers if split across files — one canonical spine in Earn_Channel.md; cross-ref siblings only.

Docs only; CHANGELOG when done.
```

### Platform_Plan_Feature_Registry

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/Platform_Plan_Feature_Registry.md

Shopify reference MD (mandatory): Read requirements/reference/SHOPIFY_REFERRALS_ONSITE_INTEGRATIONS.md — embedded gating / entitlement keys (e.g. referral sections, tier earn UI). Sync from /Users/rangwan/Downloads/SHOPIFY_REFERRALS_ONSITE_INTEGRATIONS.md if newer.

Keep OpenAPI/registry detail in System; Concept stays plan/entitlement model without dump. Fold technical reference into spine.

Docs only; CHANGELOG when done.
```

---

## Priority 2 — Wave 2 commerce / identity

### Currency

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/Currency.md

No Shopify reference MD unless documenting storefront earn UI — then read Part 2 of requirements/reference/SHOPIFY_REFERRALS_ONSITE_INTEGRATIONS.md for earn display only.

File still has exec summary + TOC — full restructure to spine; remove duplicate structure. Verify chokepoint wallet, expiry, Inngest award path via registry + MCP.

Docs only; CHANGELOG when done.
```

### Tier

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/Tier.md

Shopify reference MD: Part 2 (tier landing, hub, widget, per-tier earn/burn entitlements) — requirements/reference/SHOPIFY_REFERRALS_ONSITE_INTEGRATIONS.md; sync Downloads if newer.

Spine exists but ~2k lines legacy below — fold accurate legacy into spine; drop only duplicate scaffolding (TOC, second Overview) and verified-obsolete prose. Verify tier evaluation, entry rewards, Shopify deltas.

Docs only; CHANGELOG when done.
```

### Signup_Login

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/Signup_Login.md

Shopify reference MD: Part 2 identity/gateway sections — requirements/reference/SHOPIFY_REFERRALS_ONSITE_INTEGRATIONS.md; sync Downloads if newer. Use ### Shopify under Journeys/System where storefront signup differs.

Fold legacy; verify profile steps, OTP, LINE, Shopify member session cross-ref Authentication.md.

Docs only; CHANGELOG when done.
```

### Authentication

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/Authentication.md

Shopify reference MD: Part 2 identity and member session on storefront — requirements/reference/SHOPIFY_REFERRALS_ONSITE_INTEGRATIONS.md; sync Downloads if newer.

Document admin JWT vs member session vs API key; ### Shopify for issueMemberSession / proxy paths. Fold legacy into spine.

Docs only; CHANGELOG when done.
```

### Purchase_Transaction

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/Purchase_Transaction.md

No Shopify reference MD unless referral attribution on orders — then reference MD Part 1 § purchase settle only.

Build spine from current Overview/Technical sections; verify dual ledger, earn triggers, marketplace claim. Docs only; CHANGELOG when done.
```

### Marketplace

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/Marketplace.md

No Shopify reference MD (marketplace is Shopee/Lazada/TikTok). Absorb still-true bits from Ecommerce_Marketplace_Integration.md as Related only.

Verify Inngest ingest, credentials, claim flows. Docs only; CHANGELOG when done.
```

---

## Priority 3 — Exemplars + engagement

### Reward (consolidation pass)

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/Reward.md

Batch 1 merge done — accuracy + strip any remaining legacy tail below Related. Verify campaign reward slots (referral/tier/lifecycle), Shopify discount types. Optional reference MD Part 1 campaign reward pattern only.

Docs only; CHANGELOG when done.
```

### Checkin (accuracy pass)

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/Checkin.md

Exemplar doc — accuracy pass against registry + MCP; fill Known gaps if loyalty-user routes found. No structural rewrite unless drift found.

Docs only; CHANGELOG if material fixes.
```

### Mission

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/Mission.md

No spine today — restructure from Architecture/Overview; verify post-Confluent progress path (not Kafka). Docs only; CHANGELOG when done.
```

### Forms

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/Forms.md

Verify field systems, form_submissions, profile linkage. Docs only; CHANGELOG when done.
```

### Notification_Service

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/Notification_Service.md

Verify NotificationConsumer, flex templates, referral notification keys per reference MD Part 1 if applicable. Docs only; CHANGELOG when done.
```

---

## Priority 4 — CS (one thread per module)

Use the same pattern for each `CS_*.md`: fold `# … technical reference` into spine; verify live `cs_*` tables via MCP.

### CS_Feature_Spec

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/CS_Feature_Spec.md

Umbrella — keep routing to modular CS_*.md; spine summarizes module map; demote spec dump to folded System or delete duplicated module text now in CS_Conversations etc.

Docs only; CHANGELOG when done.
```

### CS_Conversations

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/CS_Conversations.md

Merge technical reference tables into System; expand Rules/Journeys from live schema + loyalty-admin inbox. No Shopify reference MD.

Docs only; CHANGELOG when done.
```

### CS_Knowledge_Base

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/CS_Knowledge_Base.md

Merge technical reference into spine; verify embeddings pipeline. Docs only; CHANGELOG when done.
```

### CS_Procedures

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/CS_Procedures.md

Merge technical reference into spine; AOP modes and procedure_state. Docs only; CHANGELOG when done.
```

### CS_Channels

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/CS_Channels.md

Merge technical reference; credentials, contact resolution. Docs only; CHANGELOG when done.
```

### CS_AI_System

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/CS_AI_System.md

Merge technical reference; distinguish deployed vs planned. Docs only; CHANGELOG when done.
```

### CS_AI_Pipeline

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/CS_AI_Pipeline.md

Fold prepend + reference into single spine. Docs only; CHANGELOG when done.
```

### CS_Unified_Inbox

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/CS_Unified_Inbox.md

Fold prepend + reference into single spine. Docs only; CHANGELOG when done.
```

### CS_Actions

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/CS_Actions.md

Fold prepend + reference into single spine. Docs only; CHANGELOG when done.
```

### CS_Rules_Engine

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/CS_Rules_Engine.md

Fold prepend + reference into single spine. Docs only; CHANGELOG when done.
```

### CS_SLA

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/CS_SLA.md

Fold prepend + reference into single spine. Docs only; CHANGELOG when done.
```

### CS_Live_Assist

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/CS_Live_Assist.md

Fold prepend + reference into single spine. Docs only; CHANGELOG when done.
```

### CS_Analytics

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/CS_Analytics.md

Fold prepend + reference into single spine. Docs only; CHANGELOG when done.
```

### CS_Platform_Features

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/CS_Platform_Features.md

Fold prepend + reference into single spine. Docs only; CHANGELOG when done.
```

### CS_Channel_Connectors

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/CS_Channel_Connectors.md

Fold prepend + reference into single spine. Docs only; CHANGELOG when done.
```

### CS_Phone_Number_Purchasing

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/CS_Phone_Number_Purchasing.md

Fold prepend + reference into single spine. Docs only; CHANGELOG when done.
```

### CS_Voice

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/CS_Voice.md

Fold prepend + reference into single spine. Docs only; CHANGELOG when done.
```

---

## Priority 5 — Imports, ops, loyalty satellites

### Customer_Import_System

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/Customer_Import_System.md

Merge ~1.5k technical reference into System/Flows. Verify Inngest + crm-bulk-import. Docs only; CHANGELOG when done.
```

### Bulk_Import_Currency

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/Bulk_Import_Currency.md

Merge technical reference into spine. Docs only; CHANGELOG when done.
```

### Purchase_Import_System

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/Purchase_Import_System.md

Merge technical reference into spine. Docs only; CHANGELOG when done.
```

### Open_API

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/Open_API.md

Spine exists; fold openapi bodies under System or keep appendix with clear single H1 — prefer folding. Verify gateway project + api_* RPCs. Docs only; CHANGELOG when done.
```

### Analytics

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/Analytics.md

Verify analytics-query edge + BQ serving layer. Fold legacy. Docs only; CHANGELOG when done.
```

---

## Priority 6 — Remaining domains (generic prompt)

For any domain not listed above, paste this block and replace `DOMAIN_FILE`:

```text
Enrich requirements domain to full spine + verified truth.

Attach and follow: workflows/requirements-doc-enrichment/REFERENCE.md

Domain: requirements/DOMAIN_FILE.md

If this domain touches Shopify referrals, on-site loyalty content, or Shopify integrations (Judge.me, Klaviyo, Gorgias), read requirements/reference/SHOPIFY_REFERRALS_ONSITE_INTEGRATIONS.md (sync from /Users/rangwan/Downloads/SHOPIFY_REFERRALS_ONSITE_INTEGRATIONS.md if newer) and apply the matching reference MD part per REFERENCE § Shopify reference MD scope.

Grep requirements/domains/_index.md for keywords. Fold any technical reference into spine. Docs only; CHANGELOG when done.
```

**DOMAIN_FILE quick list:** `Activity_Based_Earning.md`, `Activity_Attribution.md`, `Admin_Panel.md`, `AMP_Workflows.md`, `AMP - Rule Based.md`, `AMP - AI Decisioning.md`, `Asset.md`, `Campaign_Activity_Grouping.md`, `Central_Outcome_Dispatcher.md`, `Consent.md`, `Custom_Webhooks.md`, `Event_Promotion.md`, `Funnel.md`, `FuturePark.md`, `Leaderboard.md`, `Member_Freeze.md`, `Order_Booking.md`, `Package.md`, `Persona_Entitlement.md`, `Receipt_Upload_Earning.md`, `Resource_Content.md`, `RFM_Scoring.md`, `Spin_Wheel.md`, `Store_Attribute_Classification.md`, `Store_Credit.md`, `Stored_Value_Cards.md`, `Syngenta_Events.md`, `Tag_and_Persona.md`, `Translation_System.md`, `Action_Macro.md`, `CRM_Event_Driven_Architecture.md` (architecture note — spine optional if not a product domain).
