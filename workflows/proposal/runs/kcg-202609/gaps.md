# Gaps — internal only (kcg-202609)

Open facts and commitments. None of this appears in customer prose; each section carries the sendable version noted here.

## Questions for KCG (sendable default in brackets)

| # | Open fact | Why it matters | Sendable default in the proposal |
|---|---|---|---|
| K1 | What "Sync ข้อมูลสมาชิกกับ LINE Current KCG" means — one-time migration of existing members and balances, or ongoing sync with a live system | Scope of migration vs integration | We import existing members with balances before go-live and broadcast to LINE friends who aren't members yet; the exact sync approach is agreed in onboarding |
| K2 | Makro PRO buyers are mostly businesses — include them in KCG Rewards, and as individuals? | Earn rules and segment design | Makro PRO purchases earn by receipt / tax-invoice upload like modern trade |
| K3 | Flagship and event POS vendor; can it send the member's phone with each sale? | POS earn path | POS sends the sale with the member's phone; where it can't, staff record the sale in Front Line |
| K4 | Which platform Brand.com runs on today (Shopify or other) | Convert story | Brand.com earns automatically; on Shopify the plugin applies directly |
| K5 | How KCG sells through LINE OA today (chat orders, LINE MyShop, other) | LINE as a sales channel | LINE orders are recorded by staff or sent from KCG's order tool |
| K6 | Expected monthly receipt volume (Modern Trade, Makro PRO) | Sizing the optional review service | Review service sized to volume during onboarding |
| K7 | Fuel and named restaurant partners for partner rewards | Partner reward coverage | Partner categories named without specific brands |
| K8 | KCG's data platform (cloud, lake storage, warehouse) and who runs the ingestion | Data lake method (§11a) | Event stream + daily files to KCG's storage |
| K9 | Which SAP interfaces KCG's SAP team can open (APIs or file exchange), product master fields, and the posting structure finance wants (summary or line level) | SAP connector (§11a) | Rocket's connector pulls product master and posts transactions, points and redemptions; mapping agreed in onboarding |

## Rocket to confirm before submission

| # | Item | Sendable version in the proposal | Owner |
|---|---|---|---|
| R1 | Connection method, limits and any extra cost per channel (TOR 7 asks "ระบุวิธีการเชื่อมต่อของแต่ละ Channel") | Answered in §11a (round 4): method, data, what KCG does and extra cost per channel | Resolved |
| R3 | Number of reports and dashboards (brief asks for "over 30") | Admin source has 14 report dashboards (+ Home KPI strip, per-audience / per-RFM drill-downs, Customer 360, marketing analytics, AI analysis). §08 says "14 report dashboards … plus …"; "over 30" not used anywhere | Founder |
| R10 | No tier report in the requirement docs (narrative lists "Tier distribution") | §08 shows tier distribution / movement as one segment per tier, compared in the audiences dashboard | Engineering |
| R11 | Active Member and campaign KPI dashboard page | §08: "a dashboard page set up for you at implementation" (custom-dashboard capability) — implementation commitment | Founder |
| R12 | Collect email at LINE sign-up so LINE and Shopify accounts resolve to one member | §02 states it, resting on the Shopify email linkage in sign-up docs; §12 should agree | Engineering |
| R17 | Who configures the LINE OA rich menu (KCG in LINE OA Manager, or Rocket during onboarding); §02's buttons are examples | §02 names example buttons linking into KCG Rewards pages | Onboarding |
| R18 | No screen for the targeted LINE broadcast page; §09 uses a comparison table and the Songkran example | Capture or embed the broadcast page when available | Product |
| R19 | Weekly "LINE friends to members" journey needs a verified or premium LINE OA | §09 states it as a journey; confirm KCG's OA tier in onboarding | Onboarding |
| R14 | Some Shopify stores hide customers' phone numbers from apps, so phone matching may fail | Shopper ↔ member matching is email first, then phone; §02 collects email at LINE sign-up | Engineering |
| R20 | TOR 14–18, 20, 25.9, 25.15, 25.16 (security, SLA with RTO/RPO, project plan, system limits, warranty, support model) have no section; §12 points to "our service-level submission" | Founder decides: an Operations & Support section in the proposal (Yuanta structure + P1–P4 table) or a separate submission. Needs uptime, RTO/RPO and response-time numbers | Founder |
| R21 | Webhook v1 limits (one URL per merchant, 3 attempts, no replay); "each bill number earns once" on the email-file path | §11a pairs the stream with daily files and claims no replay on the stream; confirm email-file dedupe uses `transaction_number` | Engineering |
| R5 | §14 says categories not stocked today (e.g. fuel) are sourced for KCG's programme | Keep unless reward ops objects; fallback: name categories only | Reward ops |
| R8 | Stacked multipliers add or multiply? (slide shows 2× + 1.5× = 3.5×; Currency.md says typically multiplicative) | §04 says only "stack, or only the highest applies" | Engineering |
| R9 | "One of only a few loyalty / B2C CRM companies in the world that can run AI decisioning for mass-market marketing" — founder claim, no external source | Used in §11/§15 as stated | Founder |

## Commitments — build before go-live (presented as available)

| # | Capability | Status in docs | Decided |
|---|---|---|---|
| C1 | Missions visible only to chosen tiers or segments | Persona visibility today | answers-2 |
| C2 | AI agent can send coupons | Rule-based journeys only today | answers-3 |
| C3 | Screen showing AI agent decisions and results | Listed as pending in AI Decisioning doc | answers-3 |
| C4 | Facebook and email sign-in, alongside LINE and phone OTP | Docs list LINE, phone OTP, Shopify email linkage | Founder brief, round 2 (2026-09-29) |

| C5 | Automatic tier checkout benefit on Shopify (e.g. Gold free shipping + 5% off), as on slides `loyalty.basic.shopify-plugin` / `loyalty.line-shopify-flow` | Tier-only rewards and tier earn/burn live; no automatic checkout discount | Founder, round 3 (2026-09-29) |
| C6 | Makro PRO order connection built by Rocket at no charge, as a claimable channel like the marketplaces — where Makro PRO offers a seller API; receipt / tax-invoice upload otherwise | No Makro PRO connector in docs; marketplace claim pattern is live | Founder, `sources/review-2.md` |
| C7 | POS daily sales file emailed to a KCG Rewards address and imported automatically (no POS or KCG-side integration) | Not in requirement docs (Purchase_Import_System.md covers CSV import by API, no email ingress); founder states it is the standard method | Founder, `sources/review-2.md` — engineering to confirm the email ingress is live |
| C8 | Refunds / purchase cancel through the Open API (POS route 3, Brand.com) | `Open_API.md` known gap: no public purchase-cancel route in v1 | Round 4 merge — general, add-on, thin endpoint (gap-commit ladder); founder may reverse |
| C9 | SAP connector (Rocket-built middleware): pulls product master into KCG Rewards; posts transactions, points movements and redemptions to SAP | No product import route or SAP connector in docs | Founder, round 5 — **custom integration, charged** (Custom Integration line: upfront ≤ 50k THB, maintenance within the ≤ 5k THB/month cap for all custom paths) |
| C10 | (merged into C9 — SAP posting replaces the scheduled finance file) | — | Round 5 |
| C11 | Data lake methods 2–4 (daily files to KCG storage, direct load, KCG-only BigQuery view); method 1 (signed webhook) is live | Only webhook + email CSV live | Round 4 merge — priced on the Data Lake line of the commercial proposal (TOR 21 item 8) |
| C12 | Deletion record in the data lake feed (PDPA erasure, TOR 14.9) | No deletion event in webhook vocabulary | Round 4 merge — gap-commit ladder; founder may reverse |
| C13 | Purchase file upload in the admin portal (POS route 2) | Bulk purchase import worker is live; no admin upload screen (`Purchase_Import_System.md`) | Founder, round 5 — no charge |
| C14 | End-of-day POS connector built by Rocket (POS route 4) — pulls closed bills from the POS's API | Custom per POS | Founder, round 5 — **custom integration, charged** (Custom Integration line, upfront ≤ 50k THB) |

## Founder to confirm — §11b architecture and security (round 5)

| # | Item | What §11b says now |
|---|---|---|
| S1 | Does Rocket hold ISO 27001 (or ISO 29110)? TOR 2.6 and 14 ask for the certificate and its scope | Hosting (AWS, Google Cloud) is ISO 27001 / SOC 2 certified; Rocket's own certificate "provided with the submission documents" — must be true before sending |
| S2 | 99.9% monthly uptime target (reused from the Samitivej proposal) | Stated as the target; commitments in the service-level submission |
| S3 | Admin MFA, WAF / DDoS protection, PII hashing for analytics (Samitivej claims) | Not claimed anywhere — add a line to §11b's TOR 14 table only if true |
| S4 | Backup frequency, point-in-time restore, RTO / RPO numbers (TOR 14.6, 14.7, 15) | Daily automatic backups; RTO / RPO deferred to the service-level submission |
| S5 | Render region (workers process but don't store member data) | §11b says member data is stored in Singapore (database on AWS ap-southeast-1, analytics on Google Cloud asia-southeast1) |
| S6 | Open API rate limits per key — enforced today? default numbers? (TOR 18) | Limits table doesn't give a number |
| S7 | Concurrent-user figure we can declare; any cap on admin accounts (TOR 18) | "Not capped by the licence; peak load planned against 10,000 orders an hour" |
| S8 | Retention per data type — configurable in product, or an onboarding commitment? Defaults beyond the 24-month audit log (TOR 14.8) | Retention agreed with KCG; audit log 24 months |
| S9 | **PDPA risk:** member removal keeps a snapshot (name, phone, email, balances) in the removal record, and form submissions survive removal. Purge after a set period? (TOR 14.9) | Worded narrowly: "erased from the member profile, audiences and the audit log" — does not claim all personal data is erased |
| S10 | Rocket superadmin actions are outside audit-log scope, but §12 platform-management implies every change is visible | §11b doesn't claim superadmin actions are logged; check §12 wording |
| S11 | Where AI steps run (receipt reading, AI analysis) — cross-border transfer under PDPA | §11b says data is *stored* in Singapore, not *processed* only there |
| S12 | Rocket as data processor; 72-hour breach-support wording | Stated in §11b TOR 14 table — confirm |

## Resolved (round 3, 2026-09-29)

- R2 capacity: §00/§15 state order processing is designed for 10,000 orders an hour and scales out (Ecommerce_Marketplace_Integration.md); KCG's 100,000+/month ≈ 140/hour.
- R4: "100+ key accounts" only; 500+ removed.
- R6: committed → C5; prose and slides state it as live.
- R7: recurring POS sales-file import is included in the licence (§03). Round 4: delivered by email ingestion (C7).
- R16 (round 4): viewer showed each screenshot's library description as a caption — the slide capture had written internal notes there ("Whole slide from the KCG pitch deck… slide id…"). Cleared on the 55 KCG slide assets; originals in `research/asset-descriptions-backup.jsonl`.

## Build items outside the proposal (round 4)

| # | Item | Why | Status |
|---|---|---|---|
| B1 | Admin embed opened scrolled to a section — e.g. reward settings at the controls (who, when, how many, tier price). Needs a demo reward's settings page in the portal's mockup manifest and a scroll-to-section parameter the admin honours on load | Founder asked for the reward-controls embed (`sources/review-2.md`) | Awaiting founder approval; §05 uses the rewards slide until built |
- R13: deck viewer renders admin embeds at 1600px and scales to fit (rocket-deck PR #5).
- Round 5: AI analysis embed opens at the top of the thread in deck-embed mode (loyalty-admin PR #20). Data lake method 1 (event stream) confirmed live — custom HTTPS webhook in `Outbound_Integrations.md` v1; kept.
