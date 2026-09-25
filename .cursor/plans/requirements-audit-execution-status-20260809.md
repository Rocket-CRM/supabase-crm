# Requirements corpus audit — post-execution status

**Date:** 2026-08-09

## Cleanup pass (same day)

Confirmed legacy **removed** (not kept in archive):
- `MARKETPLACE_SETUP`, full `Ecommerce_Marketplace_Integration`, `INDEX_FUNCTION` dump, `Tier_Simplification`, `amp_analysis`, duplicate `agent-context-architecture` draft, FuturePark OCR pre-merge body, feature-docs `marketplace-integration` Kafka draft
- Kafka/CDC/CurrencyConsumer mermaid + teaching sections stripped from `Tier.md`, `Reward.md`, `Currency.md`, `Purchase_Transaction.md` (live path only: outbox → Inngest)

**Restored (not legacy):** `AMP - Cache Layer.md` — still referenced as live Upstash `amp-cache` by AMP Rule Based / AI Decisioning.

**Kept:** `archive/feature-docs-draft/*` audience drafts (except marketplace Kafka draft) — unused but product-narrative, not infra-legacy. Delete in a later pass only if Knowledge include-list excludes them.

## Wave 13+ (same day — next-wave domains)

Pipeline / registry accuracy fixes (no core Tier/Reward/Currency/Purchase redo):

| Area | Action |
|---|---|
| Activity | `ACTIVITY_WALLET_INTEGRATION.md`, `Activity_Based_Earning.md` — CDC/Kafka → outbox/Inngest; remove fake `trigger_tier_eval_on_wallet`; refresh function list |
| Referral / Attribution / Campaign grouping | Verified OK — no edit |
| Notifications | `Notification_Service.md` — `NotificationConsumer`/Kafka → `notification-*-router` on `inngest-event-router-serve` |
| Import | Customer/Purchase/Redemption system docs — per-type `inngest-bulk-import-*-serve` + kickoff; CDC downstream → outbox; `Bulk_Import_Currency.md` mission-trigger fix |
| Tag / Store attr / Translation | Slim aspirational RPCs; `assign_tag` 5-arg; trigger-based UI cache invalidation |
| Order booking | Pending-earn column myth removed; outbox/Inngest flow |
| Package | `Package_Contract_Benefit.md` → stub pointing to `Package.md` + `Persona_Entitlement.md` |
| Store credit / SVC / Asset / Central Outcome / Platform Plan | Light fixes; Platform Plan legacy-resolver contradiction reconciled |
| AMP | Rule Based / Cache / AI / Condition — Post-Confluent banners; `workflow_*` names; status rows; v4 collections note. Large Rule Based diagrams still historical under banner |
| CS | Conversations/Channels FK rename; plan-doc vision banners; Feature_Spec live rename map; **deleted** sales-only `CS_Competitor_Matrix.md` |

## Earlier batches 0–7

See prior section in git history / conversation; Open_API, Analytics, Checkin, Marketplace expand, domain map, structure/workflow updates remain.
