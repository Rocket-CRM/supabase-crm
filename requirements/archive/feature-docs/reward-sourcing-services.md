# Feature Guide: Reward Sourcing & Partner Fulfillment

Curated product knowledge for **reward sourcing** and **reward-as-a-service** positioning: partner catalog, pay-on-redeem economics, fulfillment paths, the Reward Strategy team, and admin operations. This file feeds internal CRM knowledge blocks under the `reward-sourcing-services` sub-feature (not auto-merged into the main `rewards` feature guide).

It is intentionally **not** a full 8-section feature guide. Many sections (key concepts, configuration reference, member experience) live entirely under the platform `rewards` feature; this guide only covers what is *additional* when the operational service is layered on top.

## 1. Overview

**Reward sourcing** is an operational service Rocket layers on top of the platform `rewards` feature. It gives merchants a curated partner catalog (digital vouchers, physical goods, lifestyle and wellness brands) while charging **only when a member actually redeems** — no prepaid inventory sitting on the merchant's balance sheet.

**Two reward pools**

- **Partner-network rewards (pay-per-use).** Large SKU breadth from integrated partners. **Digital e-vouchers** are issued in near real time at redemption. **Physical rewards** ship via a fulfillment partner with tracking surfaced in-app where the product supports it.
- **Merchant-owned privileges.** Discounts, service vouchers, and on-site benefits configured directly in the loyalty program. These typically have **no third-party procurement cost** — value is funded by the merchant's own services or margin.

**Reward Strategy team**

Rocket's Reward Strategy team designs the reward mix per merchant, not just plumbs the catalog. The team integrates the reward catalog with two things:

- The **lifestyle** of the merchant's user base — the everyday brands they actually use (coffee, transport, marketplace gift cards, beauty, wellness).
- The **design utility** of those rewards inside the loyalty program — which categories drive return visits, which support cross-sell, which keep the brand present between touchpoints.

Three strategic aims drive every reward mix:

1. **Bring members back** — privileges that motivate a return interaction (follow-up offers, repeat-visit credits, category-specific vouchers tied to past purchases).
2. **Cross-sell adjacent services** — surface departments or product lines a member has not engaged with yet via segment-specific bundles.
3. **Stay present between touchpoints** — everyday lifestyle rewards (dining, coffee, marketplaces, wellness retail) so the brand stays relevant outside of direct merchant interactions.

---

## 4. Admin journey

The native reward create / edit / list forms are unchanged from the `rewards` feature. This journey covers only what is added when the partner catalog is layered on top.

**Catalog and program setup**

- From the **Partner Reward Catalog** view, browse SKUs by category, source, and band.
- Select SKUs to expose in the merchant's program. Each selected SKU becomes a reward record; ownership and procurement metadata are carried in.
- Map each reward to **campaigns**, **catalog placements**, or both, and set **coin pricing**. Tier-, persona-, and tag-specific pricing follow the standard `rewards` pricing matrix.
- For inventory-bound rewards (physical, pre-loaded codes), configure **stock** and **reorder / alert thresholds**.

**Monitoring and reporting**

- Monitor **stock levels** and redemption velocity per reward and per category.
- Run **redemption reports** (by reward, tier, channel, period).
- Trigger reorder or partner replenishment when stock crosses the configured threshold. Whether that step is fully automated or manual depends on the partner connector.

**Member-facing outcome**

- After redemption, members receive **wallet entries, codes, or delivery status** consistent with the reward type — instant for digital and merchant-owned, tracked for physical.

**Not in this journey**

- The native reward create / edit / list forms — those are documented in the `rewards` feature guide.
- Partner contracting, code-pool ingestion, and partner billing — operating-model concerns handled by Rocket's Reward Strategy team and integration partners, not by the merchant admin.

---

## 7. Business rules

**Economics**

- **Pay-per-use (partner rewards).** The merchant is charged **only for rewards that members actually redeem** — no upfront inventory purchase for partner-sourced catalog items unless explicitly negotiated otherwise.
- **Merchant-owned privileges.** Funded as discounts or internal services. **No third-party SKU procurement** for those items.

**Fulfillment SLAs (commercial / contracted defaults — not platform-enforced guarantees)**

| Type | Process | Typical SLA |
| --- | --- | --- |
| **Digital e-voucher** | Real-time or near-real-time procurement from partner / API; code or link delivered into wallet on redeem | **Instant** (target) |
| **Physical reward** | Order to fulfillment partner → pick, pack, ship; tracking surfaced in app where supported | **2–5 business days** standard; **up to ~14 days** for edge cases |
| **Merchant-owned** | Configured in admin; issued as privilege / voucher at redeem | **Instant** |
| **Flash / limited** | Pre-loaded finite stock; high-concurrency redemption with first-come-first-served and fairness rules | **Instant** for digital; physical follows physical row |

**Partner network and onboarding**

- Onboarding a new partner typically takes **~5 business days** end-to-end (contracting + technical integration via API or file-based codes + catalog configuration). Actual timelines vary by partner.
- Seasonal / campaign partners are supported via scheduled start / end on catalog visibility.
- The exact partner roster and SKU count are **deal-specific**; use marketing-approved numbers when quoting externally.

**Reconciliation**

- Monthly per-partner reports list **codes issued, redeemed, and expired**.
- Billing is based on **redeemed (and billable) volume** per partner agreement.

**Illustrative category bands (relative ordering, not platform defaults)**

Coin ranges are program-specific and depend on the merchant's earn velocity. The bands below show the relative ordering Rocket's strategy team uses when proposing a reward mix.

| Category | Typical examples | Source | Relative band |
| --- | --- | --- | --- |
| **Core service privileges** | Service discounts, internal credits, ancillary department offers | Merchant-owned | Wide (program-specific) |
| **On-site amenities** | Parking, on-site F&B, lounges | Merchant-owned | Lower |
| **Wellness** | Spa, fitness, supplements, massage | Merchant + partner | Mid |
| **Dining** | National QSR, café and restaurant chains | Partner network | Mid |
| **Lifestyle** | Marketplace gift cards, transport, entertainment, beauty | Partner network | Mid–upper |
| **Health product** | Supplements, skincare, devices | Partner network | Upper |
| **Premium / flash** | High-ticket electronics, luxury wellness | Partner network | High |

---

## 9. Platform mapping and boundaries

**Where the platform ends and the service begins**

In-platform behavior (covered by the `rewards` feature):

- `reward_master`, `reward_redemptions_ledger`, `reward_promo_code`, `reward_stock_store`, `reward_group`, and `transaction_limits`.
- Coin pricing across tier / persona / tag dimensions, fallback points, redeem windows, eligibility filters, and the redemption ledger.

Service / integration layer (covered by Reward Sourcing):

- Partner catalog browse and SKU import.
- Redeem-time API procurement of partner codes, where supported.
- Fulfillment partner shipping (pick, pack, ship, tracking).
- Partner billing reconciliation and monthly per-partner reporting.

Not all merchants ship with the same partner connector set. Partner integrations are delivered as **professional services**, **partner integrations**, or **roadmapped product** — not as a single uniform connector.

**When describing capabilities externally**

Distinguish two layers:

1. **Native admin and ledger behavior** — what the platform `rewards` feature does on its own.
2. **Sourced catalog and commercial SLAs** — what Rocket's Reward Strategy team and partner integrations deliver on top.

Mixing the two without distinction is the most common source of misleading proposals.

**Truth boundary**

- Numeric claims in proposals (SKU counts, partner counts, onboarding durations, fulfillment SLAs) are **deal-specific** and **partner-mix-specific**. Treat them as targets, not platform guarantees, unless marketing has approved a **canonical** figure for the CRM knowledge base.
