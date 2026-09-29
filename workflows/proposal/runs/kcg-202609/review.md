# Review — round 4 (kcg-202609)

Read cold as KCG's evaluator, then checked against `sources/review-2.md`, `dossier.md` (§ Round 4 decisions, brief checklist #1–33), `outline.md`, `gaps.md`, `integration-notes.md`, `Writing Principles/PROPOSAL_WRITING_PRINCIPLES.md` V9–V12, and the requirement docs behind the claims I doubted (targeted broadcast, audience types, earn-channel cards).

Overall: this round fixes the founder's three central complaints. On slogan cadence, every line he quoted is gone ("you own this, you keep this", "the journey KCG designs, and the one members take", "that one wallet is what turns…", "order sync brings Shopify into…"). The prose now says what happens and why, in plain sentences. The one real relapse is the closing of §14. On important information that was missing or thin, each item he named is now in the body and explained: native marketplace connections at no cost, Makro PRO as its own channel, the two ways to approve a receipt and what happens once one is approved, the email sales file as the lead POS route, the third-party to first-party conversion logic, and order sync against the plugin as Earn, See, Burn and Refer. On flow, every section from §01 to §10 opens from the previous one and hands to the next, and the cross-references say what the reader will find. Voice is clean: KCG is never "you" outside quoted member copy. Brief items #2–#33 are present. What remains is one outline regression in the executive summary, an unaccepted set of commitments in §11a, and a handful of repetitions and hand-off slips.

---

## Blocking

**B1 · The executive summary lost its project overview, and its replacement may not render.** The round-3 `flow_columns` overview (Channels › Join › Customer 360 › Loyalty and activation › Analysis) has been replaced by a `"kind": "pillar_cards"` block. The outline said to keep the `flow_columns` overview and change two items. `pillar_cards` is not a kind in SCAFFOLDS § Visuals, so the first graphic in the document may print as raw JSON. Even if it renders, it drops the channel-to-profile-to-activation picture the founder asked for in round 3. It also duplicates the four pillar paragraphs directly below it, label for label.
*Correction (`sections/00-executive-summary.md`):* replace the `pillar_cards` block with the round-3 `flow_columns` block from `archive/round3/00-executive-summary.md`, with these changes:
- Channels column, six items:
  - "Shopee, Lazada, TikTok Shop": "Six shops · native connection · claim by order number"
  - "Makro PRO": "Order claim, or receipt upload"
  - "Modern Trade": "Receipt upload · AI reads, manual or auto approval"
  - "Flagship store, event booths": "Email sales file, POS or Front Line"
  - "Brand.com, Shopify": "Earn with no claim step"
  - "LINE OA orders": "Matched by phone number"
- Loyalty and activation column, six items: keep "Points and rewards", "Member tiers" and "Campaigns" (detail "Missions · referral · lucky draw"). Add "Audiences and LINE broadcasts" (detail "Built once · sent on KCG's date"). Keep "Rule-based journeys" and "AI decisioning".
- Footer: "Members won on third-party channels earn more on KCG's own: a better rate on the flagship, Brand.com and Shopify, into the same balance, and a Shopify store where that balance can be spent (§03, §10)."

The four stats (10 channels, 10,000 orders an hour, 14 dashboards, go-live) are all in the prose already, so nothing is lost.

**Send gate (render, not a writer fix) · §06 now uses `"kind": "flow"`, which is also not in SCAFFOLDS.** In round 3 this tier path (qualify, then upgrade, then review) was a Mermaid flowchart. `diagrams.md` asked for a change of direction only. Confirm the viewer renders `flow`. If it doesn't, restore the round-3 Mermaid block from `archive/round3/06-tier.md` in top-down direction, with square nodes.

**Send gate (founder, not a writer fix) · §11a states five new commitments as available, and the founder hasn't accepted them.** Only C5–C7 are accepted. `integration-notes.md` lists C8–C12, none of them yet in `gaps.md`, and §11a writes each one as live product:
- C8: POS and Brand.com refunds sent through the Open API ("Refunds are sent the same way and reverse the bill's points")
- C9: the scheduled SKU file from SAP
- C10: the scheduled finance file to SAP
- C11: data lake methods 2–4, meaning daily files to KCG's storage, direct load and a BigQuery view
- C12: a deletion record in the lake feed

The founder either accepts them, and they move into `gaps.md` § Commitments, or the §11a thread rewords each one as "agreed with KCG's teams at implementation".

---

## 00 · Executive summary

- B1 applies.
- **The flagship sentence states a recommendation as fact.** "The flagship store's POS emails its routine daily sales file to KCG Rewards, which needs no integration work from KCG or the POS vendor". Whether it can is open (K3), and §03 frames it as our recommendation.
  *Correction:* "For the flagship store we recommend the POS's routine daily sales file, emailed to KCG Rewards, which needs no integration work from KCG or the POS vendor; event booths use the Front Line staff app, and a real-time POS connection is available where the vendor can send each bill."
- **The plugin's See, Burn and Refer are explained twice within the summary**: once in the "Move repeat purchases" paragraph and again in the Why Rocket row "Thailand's only Shopify-native loyalty plugin". The paragraph is where the reader first meets the point (V11), so keep it there.
  *Correction (Why Rocket row value):* "Live today on the Shopify App Store and ready the day KCG's store opens, on the members and balances KCG already runs in LINE (§10)."
- **TOR 1.10 (extensible to future systems and channels) is no longer tagged anywhere.** Round 3 carried it in this summary. *Correction:* change the "Move repeat purchases…" paragraph tag to "(TOR 1.4, 1.10, 7.4, 7.10)".

## 01 · The KCG Rewards journey

No findings. The one-sentence thread and the pointer to §03 do exactly what the outline asked.

## 02 · Member Management (Join)

No findings. The LINE OA as the programme's home now sits where the reader meets it, and the stages-as-audiences pointer goes to §09.

## 03 · Transaction Capturing (Earn)

No findings that need a writer. This is the strongest section in the document (see the end of this review). The `[DIAGRAM: …]` conversion loop is the diagram planner's call.

## 04 · Earn Logic

No findings. "These groups carry the lower third-party rate and the higher own-channel rate that §03 explains" is the right weight: one sentence and a pointer.

## 05 · Reward & Privilege (Burn)

No findings. The lucky-draw pointer to §07 is one sentence, as the outline asked. The reward-controls embed is known build item B1.

## 06 · Member Tier (Grow)

- The `flow` render gate above applies.

## 07 · Campaign Management

No findings. Lucky Draw reads naturally here. The per-channel entry example ties back to the conversion logic without re-explaining it.

## 08 · Reporting, Dashboard & Customer Insight (Analyze)

- **The per-segment dashboard is described twice within a few paragraphs.** The Tier paragraph says "compared side by side in the *Audiences* dashboard, shows each tier's size, purchase rate, average order and points balance". The Segments paragraph repeats it: "Each segment gets its own dashboard in *Audiences* (size, purchase rate, average order, points balance)".
  *Correction (Tier paragraph):* "Tier is a condition in every segment, so distribution and movement come from segments rather than a separate report: one segment per tier, compared side by side in the *Audiences* dashboard (below), and a segment such as "moved up to Gold this quarter" for movement."

## 09 · Activation

No findings. The four-layer ladder, the broadcast-against-journey table with its rule of thumb, and the button that hands a broadcast to a journey answer brief #31 fully. I checked the broadcast claims against `AMP_Workflows.md` § Targeted broadcast and all of them hold: test send to up to five, refresh before send, an audience built from clickers, and a postback button that enrols members in a journey.

## 10 · Brand.com & Shopify Plugin (Convert)

- **The opening re-tells §03's order-sync paragraph almost word for word.** §03 says: "Order sync covers earning only. It is what most loyalty vendors mean… The member still has to open LINE to see their balance, and has nothing from the programme to use while shopping." §10 says: "When loyalty vendors say they 'integrate with Shopify', they usually mean order sync… Order sync covers Earn and nothing else. A member shopping on the store cannot see their points there… to find their balance they have to leave the store and open LINE." The reader meets the same argument twice within a few pages. §03 must keep it (brief #30, V11), so §10 should refer back to it.
  *Correction:* replace that paragraph with: "Order sync, which is what most loyalty vendors mean by a Shopify integration and how Brand.com earns today (§03), covers Earn only. Rocket's Shopify plugin covers all four dimensions."

## 11 · Rocket AI

- **The closing hands to §12, but §11a comes next.** "Choosing those goals and reviewing the agents' results is work the KCG team can do with our loyalty strategist, as part of the services in §12." The reader then turns the page to a technical section. §11a's opening already picks up from §11 ("The AI in §11… works on data that KCG's channels and systems send in"), so §11 only needs to stop pointing past it.
  *Correction:* end the section with: "Choosing those goals and reviewing the agents' results is work the KCG team can do with our loyalty strategist (§12). All of it runs on the data KCG's channels and systems send in, which §11a sets out connection by connection."

## 11a · System integration and data flow (owned by the integration thread; for that thread)

- The C8–C12 send gate above applies.
- **The opening undercounts what needs outside work.** "Two need work from someone outside Rocket: a real-time link from the flagship POS… and the Makro PRO seller connection". The section's own table shows Brand.com's developer sending each order, SAP providing a scheduled SKU export, and the POS pointing its daily export at us. The Makro PRO connection is built by us.
  *Correction:* "Most connections are live product that the KCG team switches on in the admin portal. A few need something from KCG's side: Brand.com's developer sends each order through the Open API, SAP provides a scheduled SKU export, the flagship POS emails its daily sales file (or, optionally, sends bills in real time), and Makro PRO must offer seller access for the connection we build at no charge. The data lake method is chosen with KCG's data team."
- **The timing contradicts §10 on Shopify.** "Marketplace, LINE and Shopify connections are set up during configuration in November". Everywhere else, Shopify is a future channel that switches on when KCG's store opens (TOR 3.4, 7.10).
  *Correction:* "Marketplace and LINE connections are set up during configuration in November; the Shopify plugin is installed whenever KCG's store opens (§10)."
- **See, Burn and Refer are explained a fourth time.** The paragraph "Syncing orders and members is where most Shopify integrations stop. The plugin goes further…" repeats §03, §10 and §13.
  *Correction:* cut it to "Beyond syncing orders, the plugin runs the programme inside the store; §10 compares the two dimension by dimension." Also drop the triad "There is nothing to develop, no build to wait for, and no integration fee" and write "Nothing is developed for it and there is no integration fee" (V9).
- The Front Line route (Route 2) paragraph repeats §03's Front Line paragraph almost verbatim. Keep only what is technical and new here: no connection needed, and each bill is recorded against its booth and staff member.

## 12 · Services & partnership

No findings for writers.

## 13 · Why Rocket

No findings. The opening says it gathers threads already seen and names where each appeared, as V12 asks.

## 14 · Why our price looks low

- **The section ends in exactly the cadence the founder rejected (V9, brief #33).** It closes with an antithesis pair, "KCG isn't paying for software. KCG is paying for our obsession with loyalty.", then an aphorism, "That part will never become cheap.", then a bold slogan: "**Anyone can make it cheap. Making it right takes the few who have both the ability and the will. We are those few.**" These are close translations of the founder's own memo (`sources/review-1.md`). In a proposal, though, they are the last lines the evaluator reads, and they read as taglines. Founder's call; the recommended edit is below.
  *Correction:* replace the body of "What KCG is actually paying for" and delete the bold line: "What KCG pays for, above the software, is the loyalty expertise built into it. Loyalty is the only thing we work on. Since we launched Rocket in 2023, more than 100 key accounts have run their programmes on it, and each lesson from that work has gone into the platform, which improves every week. Unlike the cost of writing software, that accumulated expertise does not fall each year, and it is what the price is for."

---

## Housekeeping (not for writers)

- Merge `integration-notes.md` into `gaps.md`: C8–C12 under Commitments, and K8–K9 under Questions.
- §12 still refers to "our service-level submission" and "our price proposal" for TOR 11-P1, 12-P1 and 13. That submission package is the founder decision already logged in `integration-notes.md`. Make sure the documents exist before sending.
- Every screenshot id resolves in `research/`, and every mockup id exists in `slides.json` and `research/mockups.md`. The one member mockup carries `pitch=kcg-loyalty-crm`. There are no `fixed_diagram` markers and no gap markers. Stale cross-references: none.

## What is strong — keep through the polish

- **§03's "Why the channels earn at different rates."** The four-link chain (thin third-party margin, then a lower rate; full own-channel margin, then a higher rate; one balance makes the difference visible; repeat purchases move), followed by "Rocket supports each link". This is V10 done properly, and §04, §08, §09 and §10 each refer back to it in one sentence instead of re-telling it.
- **§03's receipt order.** AI reads, two ways to approve, what happens once approved, then manual in detail, then auto with the eight settings. It is exactly the order the founder asked for, and it no longer presents AI reading as the approval method.
- **§03's POS table.** Route, what it needs, when points arrive and what it is best for, with the email sales file first. An evaluator can choose from it.
- **§09's broadcast-against-journey table and the one-line rule of thumb**, plus the Songkran button that hands a broadcast to a journey. This is the distinction the founder was unsure about, made concrete.
- **§10's four dimensions and the line "Every row from See down depends on software running inside the store itself, which is what the plugin is."** This is the plainest statement of the differentiator anywhere in the document.
- **§11's opening**, which names the three places AI already appeared and explains why they are one layer, following one receipt through reading, analysis and decisioning.
- **The hand-offs.** §01 to §10 now read as one argument, and the section-closing sentences name what comes next ("§04 sets how much each one earns…", "§10 covers what members can do when they reach KCG's own online store…").
