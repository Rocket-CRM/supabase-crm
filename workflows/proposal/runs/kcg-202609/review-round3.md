# Review — round 2 (kcg-202609)

Read cold as KCG's evaluator, then checked against `sources/review-1.md`, `dossier.md` (Round 2 decisions, brief checklist), `outline.md`, `handoff-round2.md`, `gaps.md`, the KCG slide PNGs and the requirement docs.

Overall: round 2 fixes almost everything in the founder's round-1 feedback. The voice is now "we" writing to "you". The executive summary and Section 01 no longer repeat each other. Evidence sits next to the claims. There are no GAP markers or `fixed_diagram` markers. All 24 brief-checklist items are present. What remains is a small set of contradictions an evaluator will notice, three slide images that promise more than the prose, and two places where the same argument is made twice back to back.

---

## Blocking

**B1 · Shopify slides promise an automatic Gold-tier discount we don't have (gaps R6).** Three slide images show "Gold tier free shipping + 5% off all orders" / "free delivery + 5% off every order":
- `01a64ba5…` (the plugin comparison slide) in §03 and again in §12
- `ce0d1afd…` (the Convert flow slide) at the top of §12

The §12 table correctly says "Tier-only rewards, and higher tier earn and burn rates, at checkout". Tier docs state there is no automatic tier discount on Shopify. The evaluator sees the promise in the picture and the narrower claim in the text.
*Correction:* this is a founder decision. The default is to re-capture both slides with the example changed to "Gold tier: free-delivery reward". That is live, because a free-shipping reward can be restricted to a tier. Remove the "+5%". Then remove the second copy of `01a64ba5…` from §12, since the §12 table already reproduces it row for row. If the founder gap-commits instead, change the §12 table row to match.

**B2 · §03 says every connection is included, then prices one as a project (known issue 3; gaps R7).** "Every channel connection above is included in the KCG Rewards licence" (§03, Connections and volume) contradicts the POS bullet in the same section: "Where your POS can't send bills itself, we can collect them from it as an integration project agreed with your POS vendor." The POS slide `e7e10bfb…` beside that bullet makes a third claim. It shows "End-of-day sync … no changes on the POS side" and "Emailed sales report … automatic". The prose describes neither.
*Correction (§03, replace the first sentence of Connections and volume):* "Connecting your marketplace shops, receipt upload, Front Line, a POS that sends its bills, Brand.com and Shopify is included in the KCG Rewards licence. Collecting bills from a POS that can't send them is scoped with your POS vendor as a separate integration." Replace the second sentence with: "Connection methods, and capacity for your order volumes (TOR 3.3), are set out in the technical proposal." For the slide, the founder either re-captures it without the end-of-day and emailed-report rows, or confirms both and §03 describes them.

**B3 · The capacity claims rest on an open fact (known issue 4; gaps R2).** §00 Why Rocket row: "…as it happens, however many members act at once…". §15: "…sees her points while KCG is still on her mind, however many members act at once…". §03: "The platform is built for your peak order volumes across all channels together". There is no capacity statement yet for 100,000+ orders a month, and "however many" is unbounded.
*Correction:*
- §00: "A claim, receipt or purchase updates points, tier and missions as it happens, not in overnight batches, on a platform that costs less to run (§15)."
- §15: delete ", however many members act at once".
- §03: handled by the B2 rewrite.
- Keep the "Built for national-scale peaks" label, which is the founder's claim, until R2 lands.

**B4 · §11 contradicts §10 on the win-back member (known issue 1).** §10 sets up Member B: 4,900 THB, gone **3 months**, missed by the rule "over 5,000 THB, no purchase in 2 months". §13 repeats Member B correctly. §11's Khun Nok is also 4,900 THB, but her last order was **32 days** ago, and §11 says "She is the member Section 10's win-back rule misses." She isn't Member B. At 32 days, no 2-month rule would look at her yet, whatever she spent. Nok's own story also doesn't hold together. "Bought every three weeks or so" doesn't fit "her orders tend to land in the last week of the month, and it is the 20th".
*Correction (§11, Khun Nok):*
- Replace the last sentence of her intro with: "Section 10's win-back rule misses her twice: she is under its 5,000 THB line, and at 32 days it wouldn't look at her for another month."
- Replace step 1's reason with: "Her gaps have run three to five weeks, so 32 days is still within her range. The agent waits four days, watching for an order. Nothing is sent or spent."
- Leave §10 and §13 as they are.

**B5 · A beauty-brand example sits in the AI decisioning section.** `a3f610cd…` (slide `loyalty.perfectcustomerjourney3`), captioned "AI that acts: goal, allowed actions and guardrails, and the decision log for one member", shows a decision log that reads "Left serum in cart … Bought the serum". A food company's evaluator reads that as copy from another client. The caption also leaves out the slide's left half, which is AI analysis.
*Correction (§11, Seeing what the agent did and why):* remove the marker. The outcomes screenshot `855e7504…` directly below it already evidences the paragraph. Re-capture this slide from the KCG deck with a KCG example before using it anywhere else.

**Send gate (not a writer fix; gaps R13).** §02 and §08 embed the live admin portal: `loyalty.admin.customer-360.member`, `loyalty.admin.reports-points.overview` and six others. In round 1 the founder's screenshots showed exactly these screens cropped. Before sending, confirm the viewer renders these embeds at desktop width and scales them to fit. If it doesn't, swap in the whole slides: `375eff5e…` Customer 360 (already in §02), `f33b0c57…` Points, `903cf51a…` Transactions, `4e640897…` RFM, `0ce27a66…` Exec overview, `c335a1e8…` Members.

---

## 00 · Executive summary

- **The current-state column assumes KCG has no programme today, but §02 imports their points and tiers.** Pillar 2's current state reads "Existing LINE members, without a full programme of points, rewards, tiers and campaigns around them". §02 says "we import your member records with profile, point balance and tier". Whether the current LINE system holds balances is still open (K1), so neither claim should be definite, and the matrix shouldn't describe their situation to them.
  *Correction:* pillar 2 current → "LINE OA friends and members, not yet tied to purchases on every channel". In the "Own the customer" paragraph, "Your current LINE members arrive with their points (§02)" → "Your current LINE members arrive with their history and any points balance (§02)."
- **"Brand.com earns from day one" depends on KCG's web team (K4).** Unless Brand.com is on Shopify, its orders reach us only if the site sends them.
  *Correction:* "Brand.com earns from day one once your site sends us each order; on Shopify, the plugin does this for you."
- Capacity row: see B3.

## 01 · The KCG Rewards journey

- **The heading has no number, but §15 cites "Section 01".** *Correction:* "## 01 · The KCG Rewards journey".

## 02 · Member Management (Join)

- **The expiry example contradicts §04's recommendation.** The table shows *"800 points expire 30 Sep"*, while §04 recommends annual expiry at financial year-end and shows "31 Dec". *Correction:* "800 points expire 31 Dec".
- **Two mockup captions aren't encoded.** The `loyalty.admin.reports-members.overview` and `loyalty.admin.customer-360.member` captions use raw spaces and an em-dash, while §08's are `+`-encoded per SCAFFOLDS. *Correction:* encode them the same way.

## 03 · Transaction Capturing (Earn)

- B1, B2, B3 apply here.
- **The Shopify section repeats §12.** After the brand-com slide, the Shopify paragraph repeats "Standard order sync brings Shopify into your loyalty programme; the Rocket plugin brings your loyalty programme into Shopify". §12 and §15 both say this again. It also lists four plugin capabilities that §12 covers in depth and the slide already shows.
  *Correction:* collapse "On Shopify, Rocket goes further…" through "…Section 12 compares order sync and the plugin feature by feature." into one paragraph: "On Shopify, paid orders earn automatically, and Rocket's plugin, Thailand's only Shopify-native loyalty plugin, also lets members see and spend their points inside your store, on the balance they built on Shopee and at Modern Trade. Section 12 compares it with order sync." Keep the plugin slide here (brief item 5), re-captured per B1.
- **Brand.com earning isn't automatic unless the site sends orders (K4).** "Each order on Brand.com arrives in KCG Rewards as it completes…" *Correction:* "Your site sends each Brand.com order to KCG Rewards through our Open API, included in the licence, as it completes; it is matched to the member…"
- **The diagrams still talk about KCG in the third person.** Examples: "KCG's Shopee shop", "Matches it to KCG's order", "points under KCG's earn rules", "Reviewer: KCG team", "KCG LINE OA, KCG's Shopify store (future)". *Correction:* "your Shopee shop", "your order", "your earn rules", "your team", "your LINE OA, your Shopify store (future)".
- **LINE OA (TOR 7.8) is the only channel without evidence under its own heading.** *Correction:* retitle the home-screen slide `9f2eae77…`, which follows directly, to "Your LINE OA home: every way to earn one tap away".

## 04 · Earn Logic

- **The heading has no number, but other sections cite §04 and "Section 04".** *Correction:* "## 04 · Earn Logic: KCG Rewards Points".
- **The worked example points to a false source.** "Illustrative settings, the same as Section 03: 25 THB = 1 point…; 20 THB = 1 point…". §03 never gives these rates; it only says "25% more". *Correction:* "Illustrative settings, with the 25% own-channel uplift from Section 03: …". The arithmetic (35 vs 28 points) is correct.

## 05 · Reward & Privilege (Burn)

- **The privilege example may not fit KCG.** "a free drink at the flagship for every Platinum member" assumes the flagship serves drinks, which we don't know. *Correction:* use a product KCG certainly has, e.g. "a free gift tin at the flagship for every Platinum member on the first of each month".

## 06 · Member Tier (Grow)

- **The up-tier coupon runs two different ways.** §06 says a tier entry reward "is how the Automated Up-Tier Coupon runs (TOR 5.1.2, §07)". §07 runs the same TOR item as a lifecycle automation ("One automation per tier"). One mechanism, explained once, in §07.
  *Correction (§06, Entry reward bullet):* "**Entry reward**: points or a reward granted once, the moment a member reaches the tier. The Automated Up-Tier Coupon (TOR 5.1.2) is set up in §07."

## 07 · Campaign Management

- **The Shopify referral contradicts §12 (known issue 2).** "Once your Shopify store is live, a friend's first order there can also pay the reward (Section 12)." §12 presents the store referral as a separate programme. The docs describe one referral programme with two independent routes. On the sign-up route, the friend joins and enters the code. On the purchase route, the friend claims a unique first-order store discount, and the member's reward pays when that order qualifies. Each route has its own rewards.
  *Correction:* "Once your Shopify store is live, the same programme gets a second route: a friend who follows the member's link receives a first-order discount on your store, and the member earns the reward you set for that purchase (Section 12)."

## 08 · Reporting, Dashboard & Customer Insight (Analyze)

- **Analyze vs Activate is explained three times: §08's opening, §08's close and §09.** Dossier: "08 closes on it, 09 opens on it."
  *Correction:* in the opening paragraph, delete "This is Analyze: it tells you what happened, and to whom. Activate (§09–11) works on the same data and acts on it, for each member, automatically." Keep "From seeing to moving".
- **For the founder, not the writer (R3):** the brief asked for "over 30 dashboards". The section honestly says "14 report dashboards … plus …". If "over 30" is to be used, it needs a count we can defend.

## 09 · Activation

- **This section repeats §08's close.** The subsection "Analyze tells you; Activate acts" makes the same point as §08's closing section.
  *Correction:* delete that heading and its first paragraph. Open the next paragraph with: "Analyze (§08) shows who stopped where; activation moves each of them, automatically, the moment their data changes. That makes activation the fabric between every stage…" Keep the 50% sentence as it is.
- **The "members stop" idea is said three times in a few lines.** The Newton slide, the blockquote, "Members behave the same way. Left alone, a member stays at the last stage they reached." and "In practice, most members stop somewhere. The stage exists; nothing moves them to the next one." *Correction:* keep the blockquote, since the founder asked for Newton explicitly. Delete "Members behave the same way…" and "The stage exists; nothing moves them to the next one."
- **Spelling is inconsistent.** "personalized marketing and personalized campaigns" should be "personalised" to match the rest of the document. Keep the TOR tag as it is.

## 10 · Rule-based marketing automation

- **"Where rules stop" and §11's opening make the same argument back to back.** Three of §10's four bullets (optimise for the average, fixed path, every fix is another rule) are restated in §11's first four bullets. The outline gives §10 one short limits subsection, and §11 the pain points.
  *Correction:*
  - Keep the Member A/B bullet and the diagram.
  - Replace the other three bullets and the lead-in with: "Rules do exactly what they are told. That makes them predictable, and it is also their limit. Take the win-back rule:"
  - Cut the closing paragraph to: "Rules remain the right tool for moments handled the same way every time. Moments that need judgment about one member go to AI decisioning (Section 11), inside these same journeys."
  - §11 then owns the full list of pain points.

## 11 · AI decisioning

- B4 (Khun Nok) and B5 (serum slide) apply here.
- **Khun Tee can't newly enter a 30-day segment four months after his only purchase.** "He signed up at an event booth four months ago and spent 180 THB" doesn't fit "One morning, three members enter 'no purchase in 30 days'". *Correction:* "He signed up at an event booth a month ago, spent 180 THB, and hasn't been back."
- **The opening pain points stay here**, as the sole owner once §10 is cut. Leave them as written.

## 12 · Brand.com & Shopify Plugin (Convert)

- B1 applies (both slide images here, plus the duplicate plugin slide).
- **The referral paragraph contradicts §07 (known issue 2).** "This complements the friend-get-friend programme in LINE (Section 07), which rewards sign-ups; the store referral rewards first purchases…"
  *Correction:* "This is the purchase route of the same Friend Get Friend programme you run in LINE (Section 07): the sign-up route rewards a friend who joins, and this route rewards a first order on your highest-margin channel. You set each route's rewards separately."
- **The earn timing describes marketplace behaviour, not Shopify.** "Points land when the order is paid, or once it is completed: the member confirms receipt, or the order completes automatically a number of days after delivery." Shopify has no buyer "confirm receipt" step. The docs say Shopify earns when the order is paid by default, and the earning status can be set.
  *Correction:* "**You choose when store orders earn.** By default, points land when the order is paid; you can hold them until a later order status instead. A refund reverses the order's points."
- **Brand.com day one depends on the site (K4).** "Brand.com orders earn automatically from day one" needs the same qualifier as in §00 and §03: "…from day one, sent by your site through our Open API…".

## 13 · Rocket AI

Consistent with §10 after the fixes: Member B at 4,900 THB, three months. No change.

## 14 · Services & partnership

No findings.

## 15 · Why Rocket

- B3 applies.
- **"500 brands" appears only in the pricing section (R4, founder).** §16 says "more than 500 brands"; §15's "Rocket at a glance" says only "more than 100 key accounts". If the founder confirms 500+, add "more than 500 brands served since 2023" to §15's at-a-glance. If not, cut it from §16.

## 16 · Why our price looks low

Only the R4 dependency above.

---

## Housekeeping (not for writers)

- `research/assets.md` doesn't exist, but seven library screenshots are used and aren't recorded anywhere in the run. All seven exist in the asset library, so nothing will break:
  - `30d1b622`, `f4a4e258`, `dcaf48d4`, `855e7504`: AI agent actions, configuration, guardrails and outcomes
  - `40939c43`: Front Line redemptions
  - `64884bab`: workflow analytics
  - `afd806ba`: workflows list

  Record them per SCAFFOLDS.
- Slides to re-capture or confirm before sending, all founder decisions: `loyalty.basic.shopify-plugin` and `loyalty.line-shopify-flow` (R6), `loyalty.basic.pos-earn` (R7), `loyalty.perfectcustomerjourney3` (serum).

## What is strong — keep through the polish

- **The executive summary.** The `pillar_matrix` and the six-row Why Rocket table do what the founder asked. Section 01 is now a navigation map, not a second summary.
- **§03 receipt upload.** Manual approval by default, optional auto approval with the eight controls, and a recommended rollout. This is the clearest configuration section in the document.
- **§02 member status as tier plus journey stage.** "Every stage is a segment" is the kind of sentence an evaluator remembers.
- **§04's worked basket and §05's Festive Gift Set example.** Concrete and checkable, and each shows the own-channel and tier logic in one glance.
- **The rule-based example in §10.** Wait, condition split, interaction split and a different send per button, answering the brief exactly, in a diagram that fits A4.
- **§11's three-members, three-decisions example.** With the Nok fix, this is the best argument in the proposal for why AI decisioning is worth a separate line.
- **§12's order-sync vs plugin table**, and **§16**, which carries the founder's memo in customer voice without the internal register.
