# Review — KCG Rewards proposal (kcg-202609)

Reviewed `proposal.md` (identical to `sections/00`–`15` concatenated) against `dossier.md`, `outline.md`, `research/product.md`, `research/sources.md`, `research/mockups.md`, `slides.json`, `sources/brief.md`, `answers-1/2/3.md`, and the requirement docs a claim leans on. Mode catalog, language en. Technical parts (architecture, security, SLA, limits, plan, pricing) are out of this pass and not flagged.

Read as KCG's evaluator, the draft is persuasive and easy to follow along the journey. It has two structural problems that stop the evaluator finding things, one founder commitment the AI section still contradicts, and four product claims the docs don't support. It also says the same six or seven ideas four or five times. Most of the length problem is that repetition.

---

## Blocking

**B1. The TOR clause labels in the prose aren't the TOR's.** "TOR 5-P1", "TOR 6-P1", "TOR 5.1-P1", "TOR 1-P1b", "TOR 1-P2", "TOR 7-P2", "TOR 10-P1", "4.1-P1", "TOR 4.1.j" and "TOR 4.2.b" come from the indexing scheme in `research/sources.md`. The TOR itself has no "-P1" paragraphs and no lettered bullets. The dossier keeps clause IDs "so evaluators can find answers", and these IDs send the evaluator looking for clauses that don't exist. There are about 20 occurrences, in 00, 01, 03, 05, 07, 08, 09, 10 and 15.
*Correction (all writers):* cite the TOR's own clause number, then the clause's name or a short quote. For example, "(TOR 5, "สร้างและบริหาร Campaign ได้ด้วยตนเอง")" in place of "(TOR 5-P1)". Other forms: "(TOR 6, reward conditions)", "(TOR 5.1, campaign controls)", "(TOR 1, Personalized Marketing)", "(TOR 4.1, Member Communication Preference)", "(TOR 4.2, Point Redemption)" and "(TOR 10, exclusions)". "TOR 4.1-P1" becomes "(TOR 4.1, LINE OA and LINE Current KCG)".

**B2. Cross-references use section numbers, but the compiled headings have no numbers.** The same number also appears in four styles: "Section 03" (most sections), "section 07" (02, 03, 05, 09), "Section 8" and "Section 3" (13), "section 7" (14), and title-only forms such as "see Reward & Privilege" or *Transaction Capturing: earn on every channel* (07, 11, 15). An evaluator told to see "Section 8" can't find it.
*Correction (all writers):* each section file's H2 carries its two-digit number, e.g. "## 07 · Campaign Management (Campaign)". The executive summary stays unnumbered. Every cross-reference uses "Section 07", with a capital S and two digits, which matches 01's journey table. Where a reader needs the name, add it once: "Section 05 (Reward & Privilege)". Section 13 changes "Section 9/8/3" to "Section 09/08/03". Section 14 changes "section 7/8/3/4/5/6/10" to the standard form. Sections 07, 11, 12 and 15 replace title-only references with numbers.

**B3. Section 11 still flags AI-agent coupons as a gap, although the founder has committed them.** answers-3 says: "commit… remove the coupon gap flag and add coupons to the list of actions and the suggested-agents table". Sections 13 and 15 already list coupons as an agent action, so the evaluator currently reads three sections that disagree. Correction under Section 11 below.

**B4. Four product claims contradict the requirement docs.**
- **Section 05:** "finishing a survey" is offered as a mission goal. Mission form conditions "do not advance in production" (`Mission.md#System > Known gaps`).
- **Section 12:** product pages are said to show points "at the member's tier rate". The product-page badge uses the store's earn rate with no member session (`Shopify.md#Journeys > Member journey`: "Anon widget settings + earn rate overlay (no member JWT)").
- **Section 12:** points "when the shopper confirms it or automatically a set number of days after delivery". Shopify's documented threshold is *paid* (`Marketplace.md#Rules > Shopify`). The general award hold is the documented way to wait (`Currency.md`).
- **Section 10:** "LINE's delivery and read figures" after a broadcast. Per-message LINE delivery and read tracking was descoped. LINE gives only channel-level aggregate figures, and engagement is tracked through links (`AMP - Rule Based.md#Message Delivery Funnel`).

Each correction sits under its section below.

**Before sending, but not a writer fix:** the open `[GAP]` markers need answers from KCG or Rocket. They cover LINE Current KCG sync (02), Makro PRO buyers, the POS vendor, the Brand.com platform, LINE OA orders, the capacity statement and the per-channel connection method (03), receipt volume (14), fuel and restaurant partners (14), and Brand.com on Shopify (12). The 03 marker also reads "left for the technical pass by founder decision". That is process talk and must not survive into print.

---

## The twelve known cross-section issues, verified

1. **Earn-rate examples.** *Only partly confirmed.* The rates already agree. Sections 03, 04 and 12 all use 25 THB = 1 point for third-party channels and 20 THB = 1 point for own channels. Section 04's 35 vs 28 is the same pair of rates on a 500 THB basket with ×2 on 200 THB of a new product, and it reproduces the same 25% uplift. The real inconsistency is which channels count as "own":
   - 03 lists Flagship Store, events and Brand.com.
   - 04 lists flagship store and Brand.com, without events.
   - 12 lists only the Shopify store.
   - 09 describes a tier gap in baht ("a few hundred baht below the next tier"), but 06 recommends a points-based tier.

   *Canonical set, applied everywhere:* 25 THB = 1 point on marketplaces, Makro PRO and Modern Trade. 20 THB = 1 point on KCG's own channels: Flagship Store, event booths, Brand.com, and the Shopify store when live. The worked basket stays 500 THB including 200 THB of a new product at ×2, which earns 35 points on an own channel and 28 on Shopee. Corrections: 03 adds "and the Shopify store when live" to the own-channel line. 04's settings line adds event booths, and a clause "the same rates as Section 03" goes under "The figures below are illustrative". 12's worked example reads "20 THB = 1 point on KCG's own channels, including its Shopify store". 09 changes the tier-gap row to "a few dozen points short of the next tier". 06's ladder can stay as it is, because "at the base rate" is correct.
2. **Stack claim in Section 15.** *Not confirmed. The claim is present.* The intro bullet "A platform built for national-scale peaks… costs significantly less to run" and the subsection "A platform built for national-scale peaks, at lower cost" both carry it, including "designed to absorb national-scale peaks… at significantly lower running cost than conventional loyalty platforms". No restore is needed. A tightening is under Section 15.
3. **"Rules from day one, AI later" framing.** *Confirmed in two places.* Section 09 has "KCG can start with rules on day one and let AI decisioning take over the moments where one rule for everyone falls short." Section 13 closes with "Rule-based marketing automation (Section 10) is part of the core scope, so KCG can activate members from day one. Adding the 9.4 offer lets…". Both read as though AI decisioning comes later, which undercuts the headline. Corrections are under 09 and 13.
4. **Shopify listing as "1to1" (Section 12).** *Supported.* `Shopify.md#Concept`: "Rocket therefore ships as a native Shopify app (listed as **1to1**)". This is not a writer finding. Because an evaluator may search the App Store for "Rocket", the founder should confirm that the public listing name is still 1to1 before printing (see founder decisions).
5. **Segment-gated rewards.** *Confirmed clean.* Section 05 uses the supported shape: "A segment KCG builds reaches a reward through tags: an automated journey tags the segment's members". Section 08 is consistent ("Tags, personas and tier also control which rewards and earn rules apply"). One residual issue: 05 says "member group" twice, which an evaluator may read as "segment". See 05.
6. **Receipt-upload diagram in 03 and 14.** *Confirmed.* Section 03 keeps its diagram. Section 14 drops its diagram and the steps it duplicates (see 14).
7. **Win-back coherence (10 ↔ 11).** *Partly coherent.* Section 10's rule is "spent more than 5,000 THB in the last 12 months and hasn't bought in 2 months", and its Member B is 4,900 THB and gone 3 months. Section 11's Khun Nok is 4,900 THB but last bought only 32 days ago. The Section 10 rule would therefore miss her on both counts, yet 11 says only that she "sits just under the threshold of a typical win-back rule". Section 11's 30-day hand-off segment is not a second rule, but the text never says so, so the evaluator sees two different thresholds. Section 13's row (4,900 THB, three months) matches Member B and is fine. Correction under 11.
8. **AI-agent coupons.** *Confirmed.* This is blocking item B3. Correction under 11. Sections 13 and 15 keep coupons as written.
9. **Section-number style.** *Confirmed, and broader than 13.* See B2.
10. **"30+ reports".** *Confirmed absent.* No section says 30+ or "more than 30". Section 08 says "covers all ten it lists, and more". No action.
11. **Birth Month Coupon.** *Confirmed clean.* Section 07 uses the birthday trigger with an offset ("sent seven days before the birthday and valid for 30 days") and never claims a birth-month trigger. The birth-month conditions elsewhere are all supported: 04's earn condition, 05's reward eligibility and 07's spin-wheel eligibility (`research/product.md` flag 10: "Birth-month eligibility does exist on rewards, earn rules and spin wheel"). Section 06 makes no birth-month claim. Section 07 could meet TOR 5.1.3 more plainly; see 07.
12. **AI-agent results screen.** *Confirmed as a doc status. Kept as a note.* `AMP - AI Decisioning.md#Implementation Status` lists "Deliberation dashboard | Pending | … per-customer timeline and aggregate agent performance views". The data exists: decision logs and a performance summary (`#Merchant Visibility`). The screen does not exist yet. Affected passages:
   - 11, "Seeing what the agent did and why" and the 9.4 list item "The decision log and per-agent results"
   - 13, "KCG sees results for each agent…"
   - 13, 9.4 list "Results for each agent"

   No prose change for now. See founder decisions.

---

## Repetition: one owner per idea

The draft makes the same case in many places. Where more than one section tells the same story, the owning section keeps the full telling. Every other section keeps at most one sentence and a cross-reference.

| Idea | Appears in | Owner | Others do |
|---|---|---|---|
| Third-party channels win the customer; "KCG sees what it sold, not who bought it" | 00, 01, 02 intro, 03 intro and axes, 05 intro, 12, 15 intro | **01** (situation). **03** keeps its "win / keep" channel roles | 02, 05, 12, 15: one clause at most |
| Food brand = frequency, small habitual purchases | 00, 01, 04, 06, 07, 09, 10, 12 | **01** | Others use it only where it drives a design choice: 04 earn rules and 07 calendar keep it. Cut from 06, 09 and 12 openers |
| "Basics aren't enough; members try once or twice and drift" | 00, 01, 07 | **07** (why campaigns) | 01: one clause. 00 may keep it |
| One member's whole journey walked through | 01, 09, 12, 15 (plus 08 and 11 cases) | **01** (whole journey, short). **12** (convert path) | 09: one sentence, point to 01. 15: cut the six-step walkthrough |
| Newton, activation as the fabric, the 50% estimate | 00, 09, 15 | **09** | 00 may keep one line. 15 cuts the 50% sentence and points to 09 |
| "Most AI in loyalty answers questions; Rocket's also acts" | 00, 11, 13, 15 | **13** | 11 cuts its "Rocket's AI: it analyses, and it acts" subsection to one line. 15 keeps the two-sentence claim |
| Goal, actions and guardrails described | 00, 09, 11, 13, 15 | **11** | 13 and 15 each drop their bullet restatements |
| AI analysis in the portal or through MCP, within the admin's permitted data | 00, 08, 13, 15 | **08** | 13: two sentences. 15: one sentence |
| Customer 360 staff corrections list | 02, 08 | **02** | 08 cuts its "The same page is where head office corrects a record…" paragraph to the existing cross-reference |
| Front Line defined ("the counter mode of the admin portal") | 03, 04, 05 | **03** | 04 and 05 just name it |
| Receipt reading flow | 03, 13, 14 | **03** | 14 keeps only what Rocket's team does. 13's single line is fine |
| Point Redemption and Privilege campaigns | 05, 07 | **05** | 07: two sentences each and a cross-reference, using 05's example (see 07) |
| Lifecycle automations (welcome, up-tier, birthday) | 07, 10 | **07** | 10 cuts its "Lifecycle automations" subsection to two sentences |
| Order sync vs plugin | 12, 15 | **12** | 15 drops its feature bullet list |
| Dedicated team and free graphics vs TOR 10 | 00, 14, 15 | **14** | 15: two sentences |
| What KCG gets under TOR 9.4 | 11, 13 | **13** | 11 drops its "Under TOR 9.4, KCG receives" list |

Two mockups are embedded twice, so the evaluator sees the same screen twice. `loyalty.core.home.home` appears in 02 and 03: drop it from 03. `loyalty.admin.audience.list` appears in 08 and 10: drop it from 10. Every mockup and fixed-diagram id in the draft exists in `slides.json` and `research/mockups.md`.

**Length against the outline's depth.** Word counts are:
- Supporting-plus: 02 at 2,310 and 05 at 2,793.
- Supporting: 14 at 1,985, 13 at 1,457 and 15 at 1,479.
- Primary: 08 at 2,246, 11 at 2,481 and 12 at 2,145.

Section 05 is longer than three of the primary sections. The cuts named per section below bring the draft down by about 4,000 words without losing any answer to a TOR item. Approximate targets: 02 → 1,700; 05 → 2,000; 13 → 1,000; 14 → 1,500; 15 → 1,000.

---

## 00 — Executive summary

**The situation claim is stated as fact.** "Much of KCG's volume moves through channels KCG doesn't own" is presented as fact, while 01 correctly says "This is our reading of the TOR's channel list (TOR 7), not something the TOR states." An evaluator who knows KCG's channel mix will notice. *Correction:* "Judging by the channels the TOR lists, much of KCG's volume moves through channels KCG doesn't own…"

**Two founder differentiators are missing.** Section 15's stack claim and its pricing position (B-19–B-24) never reach the summary. "Around the platform" covers only service and the end-to-end claim. *Correction:* add one sentence to "Around the platform", with no figures. "The platform is built to absorb national-scale peaks at lower running cost, and we price the same features significantly below market, so that building in-house never makes sense for KCG (Section 15)."

## 01 — Understanding KCG Rewards

**The "basics aren't enough" argument appears here in full.** "Earning, redeeming and tiers are what every programme has. They are necessary but not sufficient: without something new to take part in, most members redeem once or twice and drift away." Section 07 owns this argument. *Correction:* shorten to "Points, rewards and tiers are the base; campaigns keep members coming back (Section 07)."

The rest of the section does its job. It places the journey once, gives the TOR-to-section table, and hedges the channel reading honestly. Its clause labels "(TOR 5-P1)" and "(4.1-P1)" fall under B1.

## 02 — Member Management (Join)

**The section is long for supporting-plus, and mostly because of configuration inventory.** Correction: cut these to one line each, or remove them:
- the four field settings ("Required / Shown to the member / Shown to staff / Editable by the member")
- the OTP specifics ("expires after 10 minutes and allows three attempts")
- the Notice / Required / Optional consent sub-list
- the UI paths "*Profile → Edit profile*" and "*Profile → Consent Management*"

Keep the five-step sign-up, the account-at-step-3 point, the login options table (it asks KCG to decide), the member-status table and the LINE Current KCG plan. Target about 1,700 words.

**An irrelevant claim.** "on its own LINE Official Account, with no SMS length limits" is beside the point and invites a question. *Correction:* end the bullet at "on its own LINE Official Account."

**Cross-references.** "section 01", "section 07", "section 10" and similar follow B2.

## 03 — Transaction Capturing: earn on every channel (Earn)

**"Most" overstates what the TOR tells us.** "most of its sales happen in stores and shops it does not own" and "Marketplaces and modern trade are where most people first buy KCG" are not supported by the TOR. *Correction:* use "much of its sales" and "where many people first buy KCG", matching 01's hedge.

**An unsourced proof point.** "…and another runs the same layout as KCG: two shops on each platform." `research/product.md` supports only the 56-shop merchant (29 Shopee, 16 Lazada, 11 TikTok Shop). *Correction:* cut the clause unless ops confirms it (see founder decisions).

**Own-channel rate list.** Add "and the Shopify store when live" to "Flagship Store, events and Brand.com: 20 THB = 1 point" (known issue 1).

**Duplicate mockup.** Drop the second `loyalty.core.home.home` embed under "Every way to earn in one place". Section 02 already shows it.

**Cross-references.** "section 02", "section 04" and similar follow B2.

## 04 — KCG Rewards Points (Earn)

**Worked example.** The settings line "KCG's own channels (flagship store, Brand.com)" omits events, which 03 includes. *Correction:* "KCG's own channels (flagship store, event booths, Brand.com): 20 THB = 1 point, the same rates as Section 03."

**Refund reversal claims are too exact for every channel.** "A partial refund reverses the matching share, so a 40% refund takes back 40%… the member still loses exactly what that purchase gave them, no more and no less." That holds on the general purchase path (`Currency.md#Reversal and refunds`). It doesn't hold on Shopify, where "any refund event triggers full points reversal… no proportional partial clawback" (`Shopify.md#Rules`), and marketplace refunds are reversed by staff cancelling the purchase (`research/product.md` §7.5–7.7). The dossier's fit decision was to "keep to 'refunds and cancellations reverse the points'". *Correction:* "Refunds and cancellations reverse the points that purchase earned, at the rates and bonuses that applied when they were earned. Where a channel reports a partial refund, the matching share is reversed." Cut "no more and no less".

**How before why.** Cut two passages:
- the condition-grammar paragraph, from "All the conditions in one rule must be true together" to "is written as two rules"
- the Earn Studio paragraph, "exposes the conditions a brand actually uses… so the editor stays uncluttered"

Replace them with one sentence: "KCG combines these conditions in Earn Studio, the admin editor for earn rules; no rule needs development."

**Point Adjustment re-describes other sections.** It repeats the Customer 360 and Front Line surfaces owned by 02 and 03. *Correction:* keep the reason-and-audit sentence and point to Sections 02 and 03 for the screens.

**Bonus stacking arithmetic.** "Combined bonuses add together rather than multiply. ×2 and ×3… 4× in total, not 6×" follows the founder's training (`training/earn-rule-semi-technical.md`: stacking "is additive"). The requirement doc says stacked multipliers "combine (typically multiplicative per product design)" (`Currency.md#Calculation`). Engineering must confirm before print; see founder decisions. If it isn't confirmed, cut the arithmetic and keep "KCG chooses whether overlapping bonuses combine or only the best one applies."

## 05 — Reward & Privilege (Burn)

**Blocking: survey completion is offered as a mission goal.** Under Extra Points from Mission: "When a member completes a mission — reaching a monthly spend goal, buying a featured KCG product three times in a month, finishing a survey — KCG can award points". Survey-condition missions don't advance in production (`Mission.md#System > Known gaps`). *Correction:* drop "finishing a survey" from the list and add: "Surveys carry their own completion reward (Section 07)."

**"Member group" is undefined.** In the 6-P1 table ("tier, member group, tags and birth month") and in pricing ("by tier, member group or tags"), an evaluator may read "member group" as a segment. The supported dimensions are tier, persona, tags and birth month (`Reward.md#Concept`). *Correction:* replace "member group" with "persona (a member type KCG defines, such as KCG employees)" at first use and "persona" after that. This matches 04.

**The section is longer than the primary sections.** It is 2,793 words at supporting-plus depth. *Correction:*
- Compress "Where the code comes from" and "How long a coupon lasts" into three sentences.
- Cut the reward-groups paragraph to its first two sentences.
- Cut the merchandise-options paragraph.
- Keep the e-coupon walkthrough, the 6-P1 table, the Festive Gift Set example and the Privilege Campaign routes.

Target about 2,000 words.

**Point Redemption Campaign example.** Rename "Mid-Year Redemption Fair, 1–30 June" to "Redeem Month, 1–30 September". Section 07's campaign calendar already schedules the redemption campaign in September, so 07 can then point here and both sections tell the same example.

**Front Line and cross-references.** Front Line is re-defined ("the counter mode of the admin portal"); just name it. "section 07" and similar follow B2.

## 06 — Member Tier (Grow)

**A wrong cross-reference.** "The value of a point used as a discount can also be set per tier (Section 05)." Section 05 doesn't cover this. It is the per-tier burn rate at Shopify checkout. *Correction:* "(Section 12)".

The section is tight and well judged. The points-over-12-months recommendation, the upgrade and review distinction and the ladder arithmetic (200 points ≈ 5,000 THB) are consistent with 04.

## 07 — Campaign Management (Campaign)

**Birth Month Coupon (TOR 5.1.3).** The setup is correct and claims no birth-month trigger. An evaluator checking 5.1.3 still has to infer that "seven days before the birthday, valid for 30 days" is a birth-month answer. *Correction:* add after the table: "This is how KCG Rewards delivers the Birth Month Coupon: it arrives ahead of each member's birthday and stays valid for about a month around it. KCG can also add a birth-month reward to the catalogue that only members whose birthday falls this month can redeem." Reward eligibility by birth month is live (`Reward.md#Concept`).

**The redemption and privilege paragraphs repeat 05 with a different example.** 07 uses "Redeem month… for Gold members, open for two weeks", while 05 uses the June fair. *Correction:* cut each paragraph to two sentences. Point Redemption: "a time-boxed push of catalogue rewards at campaign prices, for example Redeem Month in September (Section 05)." Privilege: "benefits KCG gives rather than sells, pushed to a tier or segment or claimed by link or QR (Section 05)."

**Cross-references by title.** "see Reward & Privilege", "see Member Management", "(see Transaction Capturing)", "(see Rule-based marketing automation)" and "see Services & partnership" follow B2.

## 08 — Reporting, Dashboard & Customer Insight (Analyze)

**Customer 360 corrections repeat 02.** "The same page is where head office corrects a record: edit the profile or phone number, adjust points… freeze an account…" *Correction:* delete the list and keep "Section 02 covers the staff actions on this page."

**Duplicate mockup.** `loyalty.admin.audience.list` is embedded here and in 10. Keep it here (see 10).

The section answers every TOR 9.1 and 9.2 item where the evaluator will look. The Active Member treatment is honest, and the AI analysis subsection is the right single owner of that capability. No "30+" claim appears here.

## 09 — Activation: a journey doesn't move itself

**AI framed as a later step (known issue 3).** "KCG can start with rules on day one and let AI decisioning take over the moments where one rule for everyone falls short." *Correction:* "Both are available from go-live and run in the same journeys. Rules take the moments KCG wants handled the same way every time, and a journey hands the judgment moments to the AI."

**A tier gap in baht.** The tier-gap row says "A few hundred baht below the next tier", but 06 recommends points. *Correction:* "A few dozen points short of the next tier as the qualifying period closes."

**The Newton quote appears twice in a row.** The blockquote is followed straight away by `loyalty.ai-journey-force`, which carries the same quote, attribution, stages and pushes. *Correction:* cut the blockquote and its attribution lines. Keep "Programme results are decided in the gaps between stages…", the slide, and "Loyalty follows the same law…".

**Cross-references.** "section 08/10/11/12" follow B2. This section is the owner of the 50% estimate and the activation argument; 15 should point here.

## 10 — Rule-based marketing automation (Activate)

**Blocking: broadcast reporting.** "After sending, the team sees a send log and LINE's delivery and read figures." *Correction:* "After sending, the team sees a send log and how many members clicked each link in the message."

**Lifecycle automations repeat 07.** *Correction:* cut the "Lifecycle automations" subsection to two sentences. "One-step moments (joining, tier up or down, birthday, anniversary) run as lifecycle automations on the same engine; Section 07 covers the automated coupons that use them. When a moment needs follow-up, KCG builds it as a journey like the example above."

**A lettered clause.** "(TOR 4.1.j, Section 02)" becomes "(TOR 4.1, Member Communication Preference; Section 02)", per B1.

**Duplicate mockup.** Drop the second `loyalty.admin.audience.list` embed ("Audience Builder segments that start journeys"). Section 08 shows it.

The example journey is the strongest evidence in the proposal. It shows a wait, a split on loyalty activity after the wait, a split on interaction, and a different send on each branch, all in KCG terms, with no A/B or email claims. Keep it exactly as written.

## 11 — Agentic AI: AI decisioning for every member (TOR 9.4)

**Blocking: coupons as an agent action (known issue 8).** *Correction:*
- Delete the `[GAP: pushing a coupon…]` block.
- Add a first bullet to "The actions" list: "Coupons and other rewards from KCG's catalogue, from a set KCG chooses for the agent."
- Change "KCG sets a range for each action rather than a fixed value" to "KCG sets a range or a set of choices for each action", since a coupon is picked, not sized.
- Add "coupon" to the First repeat purchase and Win back rows of the agents table, and "coupon for the next redemption" to Redeem your points.
- In the sequence placeholder, change "Act sends points, multiplier or LINE message" to "Act sends a coupon, points, a multiplier or a LINE message".

The guardrails already cover baht spent, so no guardrail text changes.

**Win-back coherence (known issue 7).** *Correction:* replace "so she sits just under the threshold of a typical win-back rule" with: "She is Member B's kind of customer from Section 10. At 4,900 THB she is under the rule's 5,000 THB line, and even above it the rule would wait two months, while her own rhythm says she is overdue after four weeks." After "KCG's 'overdue' journey hands members to the agent when they enter the segment 'no purchase in 30 days'", add: "The hand-off is deliberately wide, with no spend floor and only 30 days, because the agent, not the rule, decides who is really lapsing."

**Repeats 13.** *Correction:* keep the `loyalty.perfectcustomerjourney3` diagram, since the outline gives 11 priority. Cut the subsection text to one sentence: "Section 13 shows how this and AI analysis work together." Delete the "Under TOR 9.4, KCG receives:" list, which 13 owns.

**Cross-references by title.** "see Rule-based marketing automation" and "see Reporting, Dashboard & Customer Insight" follow B2.

**Note for engineering (no prose change).** "Seeing what the agent did and why" presents a per-member timeline and a per-agent results view. The requirement doc marks this "Deliberation dashboard" as Pending (known issue 12).

## 12 — Brand.com & Shopify Plugin (Convert)

**Blocking: product-page points.** "'Earn N points' on each product, at the member's tier rate when KCG knows it." *Correction:* "'Earn N points' on each product, at the store's earn rate." Cut the tier clause.

**Blocking: award timing.** "Or KCG can wait until the order is received, either when the shopper confirms it or automatically a set number of days after delivery." *Correction:* "Points arrive when the order is paid, or after a hold KCG sets to wait out the return window (Section 04)."

**Worked example.** Align it with the canonical rates: "20 THB = 1 point on KCG's own channels, including its Shopify store" (known issue 1).

**App Store listing.** "listed on the Shopify App Store as 1to1" is supported by `Shopify.md#Concept`. Keep it, but make the sentence help the evaluator: "listed on the Shopify App Store under the name 1to1." The founder should confirm the listing name is current.

The comparison table follows the dossier's tier-row rewording, and the "Earning is the baseline… See and Burn are the reason" paragraph is the clearest statement of the plugin's value in the document.

## 13 — Rocket AI across KCG Rewards (TOR 9.4)

**AI framed as an add-on (known issue 3).** The close reads "…so KCG can activate members from day one. Adding the 9.4 offer lets the programme…". *Correction:* "Rule-based automation is part of the core scope and AI decisioning is offered under TOR 9.4. Both run from go-live in the same journeys, so every member gets a fixed path where one fits and individual judgment where it doesn't."

**It restates 08 and 11 instead of summarising them.** The two "Two roles" paragraphs retell AI analysis and the goal, actions and guardrails bullets in full. *Correction:* cut each role to two or three sentences with a pointer (Section 08, Section 11). Keep the loop diagram, the stage table, "How Rocket's AI is different" and "What KCG gets under TOR 9.4". Target about 1,000 words.

**An over-specific permissions example.** "so a store team member and a head-office marketer asking the same question get answers scoped to their own access" goes beyond what the founder confirmed ("the data that admin is permitted to see"). *Correction:* cut the example and keep "the AI sees only the data that admin is permitted to see."

**Section numbers.** "Section 9", "Section 8" and "Section 3" become "Section 09", "Section 08" and "Section 03" (B2).

**Note for engineering.** The 9.4 list item "Results for each agent: decisions made, outcomes…, cost, and recent decisions with their reasoning" depends on the pending deliberation dashboard, as in 11.

## 14 — Services & partnership (TOR 10–13)

**Receipt flow duplicated (known issue 6).** Steps 1–4 and the `[DIAGRAM: receipt approval flow…]` placeholder repeat 03. *Correction:* delete the diagram and replace steps 1–4 with one sentence: "AI reads every receipt and approves clean ones automatically (Section 03); our team works the review queue." Keep step 5, the TOR 11.1–11.4 mapping and the two-step switch-on (framed as what our team does).

**A misattributed requirement.** "Prices, including the fee models TOR 11–13 ask for, are submitted separately from platform and implementation, as TOR 12 requires." TOR 12 asks this only for Loyalty Consultation. *Correction:* "Prices and the fee models TOR 11–13 ask for are in our price proposal."

**Cross-references.** Single-digit, lower-case references ("section 7", "section 3 and 4") follow B2.

With the receipt cut, the section fits supporting depth (about 1,500 words). The BPO table is the right shape for evaluators, because each TOR 10 item maps to what our team does.

## 15 — Why Rocket

**Too much repetition for a closing section.** Each of the six reasons retells a body section:
- the six-step end-to-end walkthrough (01, 12)
- the plugin feature bullets (12)
- goal, actions and guardrails, plus the 50% sentence (09, 11, 13)
- the service bullet list and the TOR 10 graphics argument (14)

*Correction:* each reason becomes a claim, what it means for KCG, and one cross-reference. Delete the walkthrough, the plugin bullets, the AI bullets and the 50% sentence. Cut the service list to "Two dedicated customer success staff, a loyalty strategist, committed service levels and regular campaign graphics at no charge, beyond what TOR 10 asks (Section 14)." Target about 1,000 words. If the walkthrough is kept, fix "gone quiet for six weeks, she enters a segment like '…nothing in 45 days'": six weeks is 42 days, so use 45 in both places.

**Stack claim (known issue 2): present, tighten.** Replace the five bullets ("Points can be held… A sale that reaches Rocket twice earns only once") with one sentence: "Multi-step work, such as a return-window hold, a seven-day journey wait or a refund reversal, finishes reliably even when it runs later, and a sale that arrives twice earns once." Add the concurrency the founder named to the peak sentence: "…such as a big marketplace sale day or a launch pushed to every LINE friend, when many members act at the same moment…".

**Cross-references by italic title.** *Transaction Capturing…*, *Brand.com & Shopify plugin* and similar follow B2.

The company proof is accurate against the slides. "Top 3 B2C CRM", 100+ key accounts, 60+ staff and LINE Developer Partner match `company.about`. The MarTech Report figures (Rocket among the top three B2C CRMs used; 6% in 2024 to 13% expected in 2025; Content Shifu × Hummingbirds) match the two `company.martech-report-2025` images.

---

## Founder or engineering decisions (not writer fixes)

- **The AI agent results screen.** The deliberation dashboard is Pending in `AMP - AI Decisioning.md`, but 11 and 13 present per-member decision timelines and per-agent results as part of what KCG receives under 9.4. Either commit it as a build before go-live, as was done for coupons, or have the 11 and 13 writers soften it to "decision records and results, reported to KCG's team".
- **Bonus stacking.** Engineering to confirm whether stacked multipliers add (founder training) or multiply (`Currency.md`) before 04's "4× not 6×" example prints.
- **Marketplace proof point.** Ops to confirm "another [brand] runs the same layout as KCG: two shops on each platform", or 03 cuts it.
- **Shopify listing name.** Confirm the public App Store name is still "1to1" before 12 prints it.

---

## What is strong (keep through the polish)

- **Section 03's structure:** the 2×2, the one rule ("every purchase must name the member"), the channel table, and the honest recommendation to start receipts on the review queue and switch on auto-approval chain by chain.
- **Section 10's example journey and its "Where rules stop working" passage.** Member A and Member B make the case for AI decisioning better than any claim could.
- **Section 11's three-member worked example.** Nok, Dao and Tee show act, wait and skip, and sizing the offer to the person, in KCG's own terms.
- **Section 12's comparison table and the See/Burn argument.** It is the clearest single reason to prefer Rocket.
- **Section 09's "journey in practice" table,** which puts every drop-off in KCG terms with the push that fixes it.
- **The honesty throughout:** 01 labels its channel reading as ours, 08 treats Active Member as KCG's definition, the lucky draw is run by KCG from exported entries, and the gap markers stay visible instead of papering over unknowns.
