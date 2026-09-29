# Dossier — KCG Corporation · KCG Rewards (kcg-202609)

## Deal
- **Customer:** KCG Corporation PCL — food, B2C/D2C. One brand (KCG), one programme ("KCG Rewards"), one point currency.
- **Ask:** TOR "CRM & Loyalty Program" (Thai). Submission 30 Sep 2026 (hard copy, signed); award 31 Oct 2026; go-live 1 Jan 2027.
- **Mode:** Catalog. **Pitch:** `kcg-loyalty-crm` (KCG-customised deck with uploaded KCG mockups — every live mockup marker carries `pitch=kcg-loyalty-crm`). **Language:** English first.
- **Round 2 (2026-09-29):** founder review in `sources/review-1.md` — voice, density, evidence, structure. Evidence indexes: `research/assets-slides.md` (whole KCG slides), `research/assets.md` (live admin screens from the demo merchant). Open facts and commitments: `gaps.md` (internal — never in prose).
- **Scope offered (B-01):** Loyalty (join, earn, burn, grow), core loyalty campaigns, marketing automation (rule-based + AI decisioning), AI analysis, Shopify plugin. Customer Service module out of scope.

## Scope decisions (from answers-1)
- **In:** all functional TOR clauses 1, 3.4, 4, 5, 6, 7, 9.1–9.4; optional services 10–13 at concept level (no prices).
- **Rule-based marketing automation = core scope.** AI decisioning + AI analysis answer TOR 9.4 "Agentic AI – Optional" but get headline narrative treatment (their own Activate sections + an AI summary section). Where priced, it's the 9.4 line — prose never says "optional" apologetically; it says "offered under TOR 9.4".
- **Shopify:** a future extension per TOR 3.4/7.10/8.6, but the plugin is live and ready the day KCG needs it — IMPORTANT, full section with the comparison table.
- **Left out for now (founder B-04):** integration architecture & data flow (8-P1), security/PDPA controls (14), SLA/RTO/RPO (15), system limits (18), deliverables (19), project plan & timeline (16–17), pricing (21), submission docs (25). No clause coverage matrix. No per-channel technical connection method (API/webhook/file) — Earn explains each channel in member/brand terms only. Keep clause IDs visible in prose, e.g. "(TOR 5.1.1)", so evaluators can find answers.
- **Why Rocket** includes the stack claim (B-22) at business level only — no architecture names.

## Angle
KCG sells mostly through channels it doesn't own — modern trade, Makro PRO, six marketplace shops — alongside its flagship store, events and website, with LINE OA as the member home. The TOR's first objective is first-party customer data (1.1); its business objective is purchase frequency and lifetime value (1.4). For a food brand, value is in frequency: small, habitual purchases repeated.

Story, adapted ("marketplace/retail-heavy with an own store"):
1. **Connect** — turn every KCG buyer, wherever they bought, into a known KCG Rewards member. Marketplaces and modern trade are where KCG customers are won — not an enemy.
2. **Engage** — points, rewards, tiers and campaigns give members reasons to come back.
3. **Activate** — the journey doesn't move itself (Newton, B-14). Rule-based automation and AI decisioning are the fabric between stages; this is where results go from average to exceptional (B-15, B-16).
4. **Convert** — over time, more repeat purchase on KCG's own channels (flagship, Brand.com, Shopify when ready), with better earn on those channels.

Journey frame for the features part: **Join → Earn → Burn → Grow → Campaign → Analyze & Activate → Convert.** Founder's "perfect journey" wording (Join, Earn, Burn, Grow, Engage & return, Convert to second purchase on first-party) is used in the activation section.

## Emphasis directives (founder brief, see research/sources.md §9)
- Earn: omnichannel; the 2×2 abstraction (online/offline × first/third-party); every requested channel named (B-06).
- Activate: role of activation first, why it matters (Newton quote from slide `loyalty.ai-journey-force`), then two types. Rule-based example with delay, condition split after delay, split in sending; conditions on loyalty activity AND interaction (B-07–B-09). Limits of rules: optimise for the mean, assume fixed journeys (B-10). AI decisioning = an expert marketer / relationship manager for every member at mass-market scale.
- AI appears twice (analysis in Analyze; decisioning in Activate) plus one AI summary section (B-17). AI analysis: ask in portal or via Rocket's MCP in Claude/ChatGPT; AI sees only the data that admin is permitted to see — founder confirmed live (answers-1 #4). Analysis = convenience; action = outcomes (B-12).
- **50% claim (B-16):** attribute as Rocket's estimate: "brands that pair their programme with activation see over 50% higher member engagement and conversion to next purchase than programme-only, on our estimates across customers." Never as a guarantee.
- Shopify: comparison table order sync vs plugin; "Thailand's only Shopify-native loyalty plugin" (B-18, B-20).
- Why Rocket: end-to-end B2C CRM (loyalty, mini CDP, automation, AI, e-commerce plugin; third-party acquisition → first-party conversion); only Shopify plugin; AI that acts (connecting layer); stack of the future (event-driven, orchestrated, resilient, national-scale peaks at lower cost); service (2 dedicated CS, 1 loyalty strategist, SLAs, regular free campaign graphics — answers-1 #5); consumer-surplus pricing (B-19–B-24).

## Fit decisions writers must respect (from research/product.md §0)
- **"Split in sending" (B-09):** there is no A/B or percentage split. Frame split as (a) condition split on loyalty data, (b) interaction split — which LINE button the member tapped, whether they clicked the link. Never say A/B test or random split.
- **Message channels in workflows:** LINE and SMS. No email in workflows.
- **Birth Month Coupon (5.1.3):** a monthly scheduled send to members whose birth month is this month (audience condition), coupon valid for the month; or a birthday trigger with an offset. Do not claim a "birth month trigger" by name.
- **Mission visible to selected tiers/segments (5.2.1):** today visibility is by persona. **Gap-commit** (small, general, add-on): write as supported for KCG — "show a mission only to chosen tiers or segments" — and flag at Gate 2 for founder confirmation.
- **Friend Get Friend (5.2.2):** one always-on referral programme whose rewards and periods KCG changes whenever it likes; referral progress can also feed missions only where docs support — don't claim "referral-count missions". Don't claim "N separate referral campaigns".
- **Survey (5.2.3):** deliver as a survey with completion reward; workflows can react to answers.
- **Lucky Draw (6.3):** members collect entries (tickets from purchases, missions, check-in, or redeem points for an entry); KCG draws offline from the exported entry list. Spin wheel as the platform-run instant alternative. No "draw engine" claim.
- **Tier (4.3):** each tier programme measures one thing — spend, order count, points or tickets. Campaign participation/behaviour counts via tickets or points awarded for it. Criteria co-designed at implementation (4.3-P3). Per-tier benefits via earn rate, burn rate, tier-only rewards, entry rewards, tier-targeted campaigns.
- **Receipt reading (Modern Trade; Makro PRO fallback):** superseded by § Round 4 — Earn. Don't say "proven at scale"; the review queue is the backstop.
- **Marketplaces:** native, ready-made connections to Shopee, Lazada and TikTok Shop — connect each shop from the admin portal and it works; no custom integration and no integration cost. Two shops per platform = two connections; member claims with order number; points after the status KCG chooses (e.g. delivered).
- **POS (flagship, event):** superseded by § Round 4 — Earn (email sales file is the lead route).
- **Point reversal:** refunds reverse the points awarded for that purchase; route differs by channel — keep to "refunds and cancellations reverse the points".
- **Shopify table:** reword the tier row to "Tier-only rewards and higher tier earn/burn at checkout" (no automatic tier % discount). Don't sell checkout points estimate.
- **Active Member KPI:** KCG defines "active" at implementation (e.g. purchased in the last 90 days); tracked as a live segment/dashboard.
- **Data lake (9.3):** "we deliver to KCG's data lake as a live event stream and scheduled extracts, per KCG's data architecture" — one or two lines, no mechanism.
- **AI analysis & MCP:** founder confirmed live incl. per-admin data scope (answers-1 #4) and Claude/ChatGPT.

## Gaps
All open facts live in `gaps.md` with the sendable default each section uses. Prose never carries a gap marker. Technical sections (architecture, security, SLA, limits, plan, pricing) are required submission items (25.5–25.16) — added in a later pass; channel connection method and capacity (TOR 7, 3.3) belong there.

## Round 2 decisions (founder, `sources/review-1.md`)
- **Voice (superseded round 3, founder):** Rocket is "we"; KCG is named in the third person — "KCG's members", "the KCG team", "most of KCG's customers" — never "you" / "your" (V1). Still never "KCG wants…", "The TOR asks that…". Cite a clause as a tag "(TOR 5.1.1)", not as a sentence subject.
- **Understanding in one line:** KCG knows its own business. The essence: *own the customers who buy through channels you don't own, engage them, and trigger the repurchase — ideally on your own channels.* Say it once (exec summary); never re-tell it.
- **Exec summary** opens with a `pillar_matrix` (objective · current state · future state · business impact) and carries the Why Rocket summary. Section 01 no longer repeats it — it is the journey map only.
- **Join:** LINE, phone OTP; Facebook and email sign-in also offered (gap-commit C4). Recommend LINE is always required, whatever else is added — it is the channel marketing automation reaches best.
- **Member status = tier + journey stage** (signed up with LINE but form incomplete · profile done, no first purchase · earned, never redeemed · redeemed, no repeat · lapsed). Freeze is a footnote.
- **Customer 360** is first a data view across every domain — points, tiers, rewards, campaigns, interactions — with time series and insights; actions second. Slide `loyalty.reports.customer-360` + admin screenshot.
- **Earn:** per-channel slides (`loyalty.basic.brand-com-earn`, `loyalty.basic.pos-earn`, `loyalty.basic.marketplace-earn`, `loyalty.basic.upload-receipt`). Shopify is a headline earn channel in 03 (competitive advantage), with the plugin slide, not a one-liner. Receipt upload: **manual approval** (staff read the photo, key the amount/lines, approve) is the default; **auto approval is optional** (`requirements/Receipt_Channel_OCR_Auto_Approve.md` Concept, Rules, Merchant admin journey — setup). AI reads every receipt either way, so manual reviewers get a pre-filled form with the reason it stopped. Auto-approve configuration KCG controls: (1) master switch; (2) reading policy per group of retailers (e.g. one for your own shops, one for Modern Trade / Makro PRO) with its own auto-approve switch; (3) minimum confidence (default 70%); (4) receipt total must add up — strict or skip; (5) bill discounts spread proportionally or ignored; (6) duplicate receipt-number check; (7) product allow-list per retailer — only KCG product lines earn, the rest of the basket doesn't; (8) reading hints per retailer's receipt layout. Auto = every switch on and zero failed checks; anything doubtful → same review queue. Recommend: run on manual first, switch auto on once policies are trialled. Daily upload cap per member (default 15 images). Admin filter "Approved by: System / Admin".
- **Earn Logic** (section 04 title): currency first — points are fungible (one balance, any source, any spend); tickets are non-fungible (each ticket type its own balance, used for campaigns such as lucky draw entries) and optional since not in the TOR. Bonus points include personalised earn factors / multipliers attached to chosen members.
- **Reports:** grouped by domain — members, points & currencies, tier, redemption, transactions, campaign participation, marketing interaction, AI analysis. Use the true count of report views from `research/assets.md` (never inflate).
- **Analyze vs Activate** is introduced explicitly (08 closes on it, 09 opens on it). Newton slide `loyalty.ai-journey-force` is shown in 09.
- **AI decisioning** opens with what goes wrong in rule-based journeys (optimise for the mean, fixed paths, rule explosion, send-when-triggered). Claim (founder): *we are one of only a few loyalty / B2C CRM companies in the world that can run AI decisioning for mass-market marketing.* Diagrams fit A4.
- **New section 16 "Why our price looks so low"** adapted from the founder memo (§ in `sources/review-1.md`); 15 Why Rocket summarises and references it.

## Round 4 decisions (founder, `sources/review-2.md`)

**The spine of the argument — first-party conversion.** One of the programme's main jobs is moving customers from third-party channels to first-party ones. The mechanism, stated in full once (§03 opening) and referenced everywhere else: KCG acquires members where they already buy — marketplaces, Modern Trade, Makro PRO — at a lower earn rate, because those channels leave KCG a thin margin; KCG's own channels (flagship, events, Brand.com, Shopify, LINE orders) keep the full margin, so they can afford a better earn rate and tier/burn benefits; because it is one wallet, the member sees the difference every time they earn, and over time more of their repeat purchases move to KCG's own channels. Rocket supports each link of that chain: identifying the third-party buyer (claim, receipt), per-channel earn rates (§04), spending anywhere including on KCG's own store (§10 Convert), and activation that nudges the switch (§09). Exec summary, §01, §03, §04, §09 and §10 each carry their part and point to one another.

**Structure (outline round 4).** 02 Join takes LINE OA as the programme's home (moved out of Earn). 03 Earn opens with the channel map, the conversion logic and **Ways to earn** (the member's one place to earn) before the channel subsections. Lucky draw moves from Rewards (05) to Campaigns (07). Activation, audiences, targeted LINE broadcasts, rule-based journeys and AI decisioning become **one section, 09 Activate**, in that order; Shopify becomes 10, Rocket AI 11, Services 12, Why Rocket 13, Pricing 14.

**Audience Builder and targeted broadcasts — placement (parent's recommendation, proceeding unless the founder overrides).** Both sit inside 09 Activate, as its first two rungs, because both exist to reach members: audiences answer *who*, and broadcasts, journeys and AI agents answer *how and when*. Not in 02 Members (that is the member record and sign-up; an audience is a targeting object used by every activation tool). 08 Analyze shows segment and RFM performance and points to 09 for using them. The ladder in 09: audience → targeted broadcast → rule-based journey → AI decisioning. The broadcast/journey distinction must be explicit: a **broadcast** is one message the KCG team sends once, to everyone in an audience, at a moment the team chooses; a **journey** runs continuously — each member enters on their own when their trigger happens (signed up, earned, went quiet), and moves through waits, conditions and branches, so the moment is set by the member's behaviour, not by the calendar. AI decisioning then decides per member whether and what to send.

**Earn — per channel.**
- **Marketplaces:** native connections to Shopee, Lazada, TikTok Shop, live today; connect the shop and go — no custom integration, no integration cost.
- **Makro PRO:** its own online third-party channel, integrated like a marketplace (members claim with their order number) — we build the connection **free of charge**, subject to Makro PRO offering a seller API connection; where it doesn't, Makro PRO buyers upload their receipt or tax invoice (gap-commit C6).
- **Modern Trade receipts — order of explanation:** (1) the member photographs the receipt; AI reads every receipt (chain, branch, receipt number, date, lines) and keeps only KCG lines; (2) **there are two ways to approve it — manual (the default) and auto (optional)**; (3) **once approved**, what happens: earnable amount = KCG lines after discounts, points under KCG's earn rules, product rules and missions apply, member notified on LINE. Then manual in detail (pre-filled queue, reviewer, Rocket's Receipt Approval service), then auto in detail (the 8 settings, recommendation to start manual). Don't present AI reading as if it were the approval method.
- **Flagship & events — POS, three routes, lead with the easiest:** (1) **Email sales file** — the POS or back office emails its routine daily sales export (with the member's phone on each bill) to a dedicated KCG Rewards address; it is imported automatically and points go out. Same result as an integration, with no integration work on KCG's side or the POS vendor's; the trade-off is timing — points arrive when the file does (typically end of day), not at the till. Recommended default for the flagship (C7). (2) **Front Line** staff app for booths and pop-ups with no POS — points immediately. (3) **POS real-time connection** where the vendor can send each bill — points at the till. All included in the licence.
- **Brand.com & Shopify in §03:** state the order-sync vs plugin difference here, not only in §10: order sync (how Brand.com earns via Open API) covers **earn** only; the plugin also lets the member **see** their balance and what each product earns inside KCG's store, **burn** points and rewards at checkout, and **refer** friends to the store — which is what makes the one-wallet conversion work. 2–3 sentences + slide `loyalty.basic.shopify-plugin`, then "§10 goes through each".
- **LINE OA orders (TOR 7.8):** one short paragraph in 03 as an earn channel only; the LINE OA as the programme's home lives in 02.

**Shopify (§10) — lead with the four dimensions.** Open on what the plugin does that order sync can't, organised as **Earn · See · Burn · Refer** (+ Operations): order sync gives you Earn; the plugin gives all four. Then the one-wallet conversion walkthrough. Drop the "Order sync brings Shopify into… The plugin brings…" antithesis.

**Rewards (§05):** "Controls on every reward" — the live admin reward settings embed, scrolled to the controls, once build item B1 ships; until then keep the rewards slide.

**Rocket AI (§11):** open by saying AI has appeared throughout (receipt reading §03, AI analysis §08, AI decisioning §09 …); this section is the summary of the AI layer — a common layer under every stage that keeps members moving, not a bolt-on feature.

**Flow.** Each section opens from where the previous one left off and closes by handing to the next; cross-references name what the reader will find ("§04 sets the per-channel rates"). After the writers, one editor pass over the whole document for transitions, references and voice.

**Voice:** third person throughout (V1) — the founder's quotes in `sources/review-2.md` say "you/your" because they came from the earlier page; don't copy that.

**Prose (founder, round 4).** No slogan cadence: no parallel triads ("You own this, you keep this. Every order earns this."), no chiasmus headings ("The journey you design, and the one members take"), no aphoristic closing lines ("That one wallet is what turns…"), no antithesis pairs. Explain the mechanism and its consequence in plain sentences. Headings are descriptive. See `Writing Principles/PROPOSAL_WRITING_PRINCIPLES.md` V9–V12.

## Brief checklist (every pass must carry these — reviewer blocks on a miss)
| # | Point | Owner section |
|---|---|---|
| 1 | Objective / current / future / impact matrix | 00 |
| 2 | Why Rocket summary in the exec summary | 00 |
| 3 | Omnichannel earn 2×2 (online/offline × first/third-party) | 03 |
| 4 | Every TOR channel named, each with its slide or screen | 03 |
| 5 | Shopify as a headline earn channel + plugin slide | 03, 10 |
| 6 | Receipt: manual + optional auto approval with configs | 03 |
| 7 | Currency: fungible points vs non-fungible tickets (optional) | 04 |
| 8 | Personalised earn factor / multiplier | 04 |
| 9 | Login: other channels (Facebook, email) + LINE required | 02 |
| 10 | Member status = tier + journey stage | 02 |
| 11 | Customer 360 as data view across domains, with screen | 02 or 08 |
| 12 | Reports grouped by domain, true count, examples with screens | 08 |
| 13 | Analyze vs Activate distinction | 08, 09 |
| 14 | Newton quote + slide; activation as the fabric | 09 |
| 15 | 50%+ uplift as Rocket's estimate | 09 |
| 16 | Rule-based example: delay → condition split → interaction split → different sends | 09 |
| 17 | Limits of rules (mean, fixed path) → pain points open the AI decisioning subsection | 09 |
| 18 | AI decisioning = expert marketer per member at mass scale; "one of few in the world" | 09 |
| 19 | AI analysis in portal + MCP in Claude/ChatGPT, scoped to admin permissions; AI that acts | 08, 11 |
| 20 | Perfect journey: Join, Earn, Burn, Grow, Engage & return, Convert on first-party | 09 |
| 21 | Shopify comparison table; Thailand's only Shopify-native loyalty plugin | 10 |
| 22 | Why Rocket six points | 13 |
| 23 | Pricing rationale from the commoditisation memo | 14 |
| 24 | No internal notes, no GAP markers, no bad `fixed_diagram` | all |
| 25 | Third-party → first-party conversion via lower 3P / higher 1P earn rates, explained in full once and threaded | 03 (home), 00, 01, 04, 09, 10 |
| 26 | Marketplaces: native Shopee/Lazada/TikTok connections, no integration cost | 03 |
| 27 | Makro PRO as its own claim channel, integration built free (API permitting), receipt fallback | 03 |
| 28 | Receipt: two ways to approve (manual default, auto optional) and what happens once approved | 03 |
| 29 | POS email sales file as the lead route, no integration on either side | 03 |
| 30 | Order sync vs plugin difference stated in 03 and organised as Earn/See/Burn/Refer in 10 | 03, 10 |
| 31 | One Activate section: audiences → broadcast → rule-based → AI; broadcast vs journey distinction | 09 |
| 32 | Rocket AI as the summary of an AI layer that runs under every stage | 11 |
| 33 | No slogan cadence (V9) | all |

## Open questions (not blocking)
- Two accounts per marketplace: same brand or sub-brands? (affects nothing in prose.)
- Bonus vs Extra point: our reading — Bonus = multipliers on purchases; Extra = points awarded for missions/campaigns (supported by 6.2).
