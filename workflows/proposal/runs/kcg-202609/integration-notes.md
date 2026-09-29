# Integration section — internal notes (kcg-202609)

Written alongside `sections/11a-integration.md`. **Merged into `gaps.md` and the section files at round-4 close (C8–C12, K8–K9, R20–R21, §11a review fixes, flow diagrams live via rocket-deck PR #8).** Kept for history; nothing here is customer prose.

## For the round-4 editor pass

- New section `sections/11a-integration.md` sorts between §11 Rocket AI and §12 Services. Renumber in the editor pass (Integration → 12, Services → 13, Why Rocket → 14, Pricing → 15) or keep "11a"; update §01's journey map if it lists sections.
- §03 "Connections included in the licence…" ends "Connection methods for each channel are set out in the technical proposal." → point to the integration section instead.
- §08 "Data lake (TOR 9.3)" → keep the one paragraph, add a pointer to the integration section for the four methods.
- The architecture map and the data lake diagram are `"kind": "flow"` rocket-graphics. The live viewer renders them only after `rocket-deck-flow` branch `proposal-flow-diagrams` is merged and deployed; before that they show an error box. Merge the branch before publishing, or temporarily swap them back to Mermaid flowcharts.
- §12 says "Committed service levels … set out in our service-level submission." TOR 14, 15, 16, 17, 18, 20, 25.9, 25.15, 25.16 (security, SLA with RTO/RPO, project plan, timeline, system limits, warranty, support model) have no section in the proposal. Founder decision whether they live in the proposal or a separate submission document.

## Commitments made in the integration section (add to gaps.md § Commitments)

| # | Capability | Status in docs | Sendable wording used |
|---|---|---|---|
| C8 | Refunds / purchase cancel through the Open API (POS route 3, Brand.com) | `Open_API.md` Known gaps: no public purchase-cancel route in v1; reversals are ops/admin paths. §03 already claims Brand.com refunds reverse | "Refunds are sent the same way and reverse the bill's points" |
| C9 | Scheduled SKU file import from SAP | No product/SKU import or Open API product route in docs; purchase import requires SKUs to already exist | "A scheduled SKU export … keeps KCG Rewards current" |
| C10 | Scheduled finance file (points earned / redeemed / expired / outstanding, rewards issued) | Points reports and on-demand email CSV exports live (`Analytics.md`); scheduled delivery not documented | "KCG's finance team receives a scheduled file …" |
| C11 | Data lake methods 2–4: scheduled incremental files to customer storage; direct load into customer warehouse; customer-only BigQuery view | Analytics serving layer is BigQuery (`Analytics.md`); only email CSV export is live. Method 1 (signed outbound webhook) is live (`Outbound_Integrations.md`) | Four-method table; method 1 marked "Live today" |
| C12 | Deletion record in the data lake feed (PDPA erasure propagation) | Webhook event vocabulary has `member.updated` / `member.created`, no deletion event | "the feed carries a deletion record" |
| C7 (existing) | Email sales-file ingestion | Engineering to confirm the email ingress is live | Route 1 |
| C6 (existing) | Makro PRO seller connection | No connector in docs | Makro PRO subsection |

Data lake cost is deferred to the Data Lake line of the commercial proposal (TOR 21 item 8). Pricing sheet must carry that line.

## Questions for KCG (add to gaps.md § Questions)

| # | Open fact | Sendable default |
|---|---|---|
| K8 | KCG's data platform (cloud, lake storage, warehouse) and who runs the ingestion | Event stream + daily files to KCG's storage |
| K9 | What SAP can export on a schedule (SKU master fields; whether flagship bills reach SAP) | Scheduled SKU export; sales file from POS |
| K3 (existing) | Flagship POS vendor and whether it can email a daily export with the member phone | Email sales file first |

## Engineering checks before submission

- Webhook v1 limits (one URL per merchant, 3 attempts, no replay after failure) are why the section pairs the stream with daily files. Don't claim replay on the stream itself.
- "Each bill number earns only once" rests on purchase `transaction_number` uniqueness per merchant (`Purchase_Import_System.md`, `Open_API.md` Rules). Confirm the email-file path uses the same dedupe.
