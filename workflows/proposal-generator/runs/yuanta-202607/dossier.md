# Dossier — Yuanta Securities (yuanta-202607)

**Stage:** Understand complete — drafting under implicit Review 1 pass (user supplied finished dossier brief and asked for proposal)  
**Inputs read:** `sources/dossier-brief.md` (injected dossier)  
**Resources:** vendored proposal/core writing principles; CRM Knowledge product catalog + feature overviews (`currency`, `tiers`, `rewards` / `reward-sourcing-services`, `amp-workflows`, `amp-ai-decisioning`, `customer-service` tree, `campaigns` tree, `pdpa-consent`, `translation-system`)

## Authoritative parameters

Thailand market · PDPA · Thai + English · go-live **2Q 2026**. Taiwan / PIPA / zh-tw / Q4 2026 from the test requirements doc are **not adopted**.

## Problem in one line

Three disconnected stacks (app-embedded loyalty without engine, unreliable Cisco voice routing, HubSpot weak on Thai channels) → one Rocket CRM / Loyalty / CS platform beside Yuanta’s trading app.

## Mapped needs → Rocket surface

| Need | Rocket surface | Fit |
|---|---|---|
| Commission-based points + multi-currency | Currency (points + tickets) + Purchase Transactions API ingest | Supported pattern; commission field contract open |
| Silver / Gold / Platinum, rolling 12m | Tiers (upgrade / maintain / progress; rolling windows) | Supported; thresholds TBD |
| Web-view redeem in Yuanta app | Rewards marketplace (in-app / webview / LINE) + secure session handoff | Supported; token type TBD |
| Buzzebees-only supply | Reward Sourcing & Partner Fulfillment (partner-network path); Buzzebees as mandated partner | Supported as workstream; commercial/API open |
| Missions, referral, check-in, spin, lucky draw | Campaigns domain | Supported |
| “Top-trader” recognition | Missions / tags / campaign thresholds | Partial — no dedicated leaderboard product claim |
| Replace HubSpot for LINE + local SMS + segments | AMP Workflows + channel connectors | Supported |
| AI marketing personalisation | AMP AI Decisioning | Supported |
| Omnichannel CS (6 digital channels) | Channel connectors + Unified Inbox + routing | Supported |
| Voice modernisation | Voice Console + IVR + Twilio SIP / ElevenLabs stack | Supported cloud path; Cisco hybrid TBD |
| AI CS agent + KB + Watchtower + live assist | CS AI + Knowledge Base + AOPs + Watchtower + Live Assist | Supported |
| PDPA consent | PDPA Consent on profile | Supported |
| Thai / English | Translation System (`th`, `en`) | Supported |
| Loyalty data migration | Confirmed phase-1 workstream | Effort unscoped |

## Decisions carried into proposal

1. Greenfield Rocket deploy; Yuanta app remains member shell; Rocket owns points/rewards/CS/AMP.
2. Recommend **cloud voice replacement** for reliability; document Cisco-retain hybrid as alternative.
3. Recommend **signed short-lived token** for web-view handoff (not plain member ID).
4. HubSpot decommission workstream included; parallel-run details in solution-design.
5. Buzzebees is mandated supply partner — no Rocket direct voucher issuance.
6. Admin panel English by default unless Yuanta requires Thai admin UI.

## Open gaps (carry into proposal as `[GAP: …]`)

- `[GAP: Web-view token type + IdP ownership — Yuanta app + Rocket solution-design]`
- `[GAP: Trading REST field schema, frequency, auth — Yuanta trading IT]`
- `[GAP: Buzzebees API contract + account ownership — Yuanta commercial / Rocket sourcing]`
- `[GAP: Tier metric + thresholds + downgrade grace — Yuanta programme owners]`
- `[GAP: Point expiry model — Yuanta programme owners]`
- `[GAP: Cisco model / SIP config if hybrid chosen — Yuanta contact centre]`
- `[GAP: KB content volume/format — Yuanta CS]`
- `[GAP: SMS gateway provider — Yuanta or Rocket default]`
- `[GAP: HubSpot cutover + historical retention — Yuanta marketing]`
- `[GAP: Data residency (TH-only vs PDPA-compliant region) — Yuanta legal]`
- `[GAP: Loyalty migration volume/quality — assessed in solution-design]`
- `[GAP: Named “top-trader leaderboard” UX — confirm mission/tag pattern vs custom UI]`

## Sufficiency

Enough to draft a sendable structure with visible gaps. No blocking questions — prior gap Q&A already deferred commercial/technical specifics to solution-design.
