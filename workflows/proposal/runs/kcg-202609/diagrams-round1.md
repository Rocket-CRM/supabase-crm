# Diagram plan — KCG Rewards (kcg-202609)

22 placeholders → **11 diagrams** (8 kept, 3 changed, 11 dropped, 0 added). All Mermaid, `flowchart` or `sequenceDiagram` only. Budget: 3 in Earn (the primary section), 4 in Activate (the pivot), 1 each in Points, Tier, Convert and Rocket AI. There's no standalone customer-journey diagram: the stage map is already carried by the table in 01 and the fixed slides in 00 and 09, and 12's Convert flowchart is the only drawn member path across channels.

Sections 00, 09 and 15 have no placeholders and need no additions. 09's fixed slide `loyalty.ai-journey-force` already shows the stages and the pushes between them.

---

## sections/01-understanding.md

- Placeholder "flowchart, left to right, of the seven stages Join → Earn…" → **drop**
  Why: the stage table directly below carries every stage, TOR area and section number. The stages are also drawn in the fixed slides in 00 (`loyalty.high-level-flow`) and 09 (`loyalty.ai-journey-force`). A third picture would repeat both.
  Writer: fold in the loop, the one meaning the table lacks. After the table, add one sentence: every purchase, including a converted one on KCG's own store, earns into the same balance and starts the next round, so the journey repeats with each purchase.

## sections/02-join.md

- Placeholder "sequence with three actors (Member, KCG LINE OA, KCG Rewards)…" → **drop**
  Why: the fixed slide `loyalty.basic.signup` sits directly above and shows the same six-step path. The numbered list and the paragraph after it already say that the account is created at the OTP step, that drop-outs stay reachable by LINE and phone, and that returning members skip OTP.
  Writer: none.

## sections/03-earn-channels.md

- Placeholder "the 2×2 with KCG's channels in each quadrant…" → **change**
  Type: flowchart (left to right)
  Shows: four quadrant nodes, each listing its channels:
    - Online · third-party: Shopee ×2, Lazada ×2, TikTok Shop ×2, Makro PRO
    - Offline · third-party: Modern Trade
    - Offline · first-party: Flagship Store, Event booths
    - Online · first-party: Brand.com, KCG LINE OA, KCG's Shopify store (future)

  Each quadrant has one edge, labelled with how the member earns, into **One member purchase history**, which feeds **Points · Tier · Missions · Reports**. Edge labels:
    - Online · third-party: "claim order number (marketplaces) · upload receipt (Makro PRO)". This is the fix: Makro PRO earns by receipt upload, not order claim.
    - Offline · third-party: "upload receipt"
    - Offline · first-party: "phone number at the till or on Front Line"
    - Online · first-party: "automatic, no claim step"

  Six nodes in total.
  Takeaway: ten channels, four ways in, one record. Rules set once apply everywhere.

- Placeholder "sequence: Member buys on KCG's Shopee shop → Shopee shop passes the order…" → **keep**
  Type: sequenceDiagram
  Shows: participants Member, KCG's Shopee shop, KCG Rewards.
    1. Member buys on KCG's Shopee shop.
    2. The shop passes the order to KCG Rewards, held unclaimed.
    3. Note: parcel delivered, time passes.
    4. Member scans the parcel-insert QR and joins in KCG LINE OA.
    5. Member enters the order number in Ways to earn.
    6. KCG Rewards matches it to KCG's order and checks its status.
    7. `alt` status reached "delivered" → points added to the balance and a LINE confirmation.
    8. `else` not yet delivered → "not yet claimable, try again after delivery".
    9. `else` wrong number or already claimed → clear reason shown.
  Takeaway: the order reaches KCG Rewards before the member does, so claiming needs no receipt and no reviewer.

- Placeholder "flowchart: Member uploads receipt photo → AI reads chain, branch…" → **keep** (this is the one receipt diagram; 14 cross-references it)
  Type: flowchart (top down)
  Shows:
    1. Member photographs a Modern Trade or Makro PRO receipt in Ways to earn (LINE: "received").
    2. AI reads chain, branch, receipt no., date and lines.
    3. It keeps the KCG lines on that chain's product list; the earnable amount is after discounts.
    4. Decision: "All checks pass (not a duplicate, totals add up, KCG items found, readable) **and** auto-approval on for this chain?"
       - Yes → approved, points under KCG's earn rules, LINE "approved +N".
       - No → review queue, pre-filled with the reason → reviewer corrects it and approves or rejects → LINE notice either way.
  Label the reviewer node "Reviewer: KCG team, or Rocket team under Receipt Approval (TOR 11)" so the same drawing serves section 14.
  Takeaway: clean receipts need no person, and a person sees only the doubtful ones. Auto-approval is a per-chain switch KCG turns on when it trusts the reading.

## sections/04-points.md

- Placeholder "Life of a point. A purchase arrives from any KCG channel…" → **change** (map the nodes to the TOR 4.2 items so evaluators can score from it)
  Type: flowchart (left to right, three exits at the end)
  Shows:
    1. Purchase from any KCG channel.
    2. Conditions checked: what, where, who, when *(Point Earning)*.
    3. Best qualifying rate + bonus multipliers *(Bonus Point)*.
    4. Optional hold until the chosen order status or the hold period ends *(award timing)*. Side edge: refund during hold → pending points cancelled.
    5. Dated batch joins **One KCG Rewards balance**.
       - Side entry into the balance: "Extra Point: missions, surveys, check-in, journeys" *(Extra Point)*.
    6. Three exits from the balance:
       - Redeemed, soonest-expiring first *(Point Redemption)*
       - Reversed on refund, at the original rates *(Point Reversal)*
       - Expired if unspent *(Point Expiration)*

  About nine nodes.
  Takeaway: every point is a dated batch with a known fate. Holds, reversals and expiry are predictable for finance.

## sections/05-rewards.md

- Placeholder "e-coupon life — member redeems with points in LINE…" → **drop**
  Why: the flagship walkthrough (three steps), the counter-confirm mockup and the "who may mark a coupon used" paragraph already carry both branches and the staff hand-off.
  Writer: none.
- Placeholder "lucky draw flow — entries come in from purchases…" → **drop**
  Why: the flow is linear. The four-source bullet list and the paragraph after it ("When the draw closes, KCG exports… makes the draw") already carry the hand-off from KCG Rewards to KCG. The lucky-draw mockup follows.
  Writer: none.

## sections/06-tier.md

- Placeholder "One member's path through a tier year…" → **keep**
  Type: flowchart (left to right)
  Shows:
    1. Purchase on any KCG channel → points → tier progress (rolling 12 months). Side note: a refund reduces progress but never downgrades the member.
    2. Threshold crossed? → upgrade, immediately or at month end, per KCG's setting.
    3. Entry reward, with optional LINE congratulations via a journey.
    4. Review date: use the prose example, reached Gold 24 Mar 2027 → review 24 Mar 2028.
    5. Decision: "Reached the Gold threshold again in the 12 months?"
       - Yes → stays Gold.
       - No → moves to the highest tier still qualified for.
  Seven or eight nodes.
  Takeaway: purchases only move a member up. A move down happens only at the review.

## sections/07-campaigns.md

- Placeholder "Milestone mission progression for 'Snack Streak – March'…" → **drop**
  Why: the level table carries the staircase. The paragraph after it walks one member through four channels, and the "Shape" bullet states carry-forward. That the channels converge into one progress bar is already drawn in 03.
  Writer: none.
- Placeholder "Friend Get Friend sequence: member → shares code in LINE…" → **drop**
  Why: three linear steps with a mockup. The abuse checks are listed in the paragraph that follows.
  Writer: in step 3, say that the checks run before any reward. Example wording: "Once the friend is a member and the code passes KCG Rewards' checks (not their own code, not referred before, within the invite cap), both receive the rewards KCG set."

## sections/08-analyze.md

- Placeholder "KCG's channels (marketplaces, modern trade, Makro PRO…) → one member profile → segments…" → **drop**
  Why: the channel-to-profile half is 03's 2×2 diagram, and the profile-to-AI half is 13's loop. The sentence "purchases from every channel build one profile per member, profiles form segments, and segments feed campaigns, automation and AI" carries the chain. The audience-builder mockup shows the segments.
  Writer: none. That sentence must stay.
- Placeholder "KCG admin asks a question → in the portal, or in Claude/ChatGPT…" → **drop**
  Why: the two doors, the permission scoping and the draft-then-apply step are each stated in the prose. The AI-analysis mockup follows, and the same governance points are drawn once in 13's loop, which 08 already cross-references ("Section 13 shows how the two fit together").
  Writer: none.

## sections/10-rule-based.md

- Placeholder "Flowchart of the example journey. Trigger 'Joins KCG Rewards'…" → **keep** (the section's key diagram)
  Type: flowchart (top down)
  Shows:
    1. Trigger "Joins KCG Rewards".
    2. LINE welcome message + welcome coupon.
    3. Wait 7 days.
    4. **Condition split** "Used the coupon or bought on any channel?"
       - Yes → tag "first buyer" + LINE thank-you + ×2 points on the next purchase within 30 days.
       - No → go to step 5.
    5. **Interaction split** "Clicked the link in the welcome message?"
       - Not clicked → SMS reminder + tag "LINE-quiet".
       - Clicked → LINE carousel, three cards → go to step 6.
    6. **Interaction split** "Which button was tapped?"
       - New launch → new-product coupon pushed.
       - Best-seller → ×2 points on that product for 14 days.
       - Family bundle → LINE where-to-buy + tag "bundle interest".

  Combine the action and tag on each branch into one node. That gives about 11 nodes.
  Takeaway: a wait, a loyalty-activity split and two interaction splits, with a different send on every branch.
  Constraint: splits are condition or interaction only. No A/B test, no percentage or random split, no email.

- Placeholder "Flowchart of the win-back rule as a hard check…" → **keep** (with the exact figures from the prose)
  Type: flowchart (left to right)
  Shows:
    - Two entry nodes: **Member A** (5,200 THB in 12 months, gone 2 months) and **Member B** (4,900 THB in 12 months, gone 3 months).
    - Check 1: "Spent > 5,000 THB in the last 12 months?"
    - Check 2: "No purchase in 2 months?"
    - Both yes → "Send win-back offer (LINE)". Any no → "Nothing sent".
    - Draw Member A passing both checks to "Send". Draw Member B failing check 1 and falling to "Nothing sent", annotated "further gone than A".
  Draw only the entry rule. The rest of the win-back journey in the table (wait 7 days, multiplier by SMS) stays out.
  Takeaway: the member who most needs the offer is the one the rule drops.

## sections/11-ai-decisioning.md

- Placeholder "sequence — member event (purchase, entering a segment) reaches the agent…" → **change** (make KCG Rewards' guardrail check its own participant, since it is the ownership boundary)
  Type: sequenceDiagram
  Shows: participants Journey, AI agent, KCG Rewards, Member.
    1. Journey hands the member to the AI agent at the chosen moment (purchase, enters a segment, tier change or points change).
    2. AI agent reviews the profile and history across every channel, the eligible actions, the guardrail headroom and its goal progress.
    3. `alt` **Wait** → the agent records what it is watching for. `loop` re-review with fresh data at the set time, within KCG's limit (e.g. up to 3 reviews over 2 weeks).
    4. `else` **Skip** → the reason is recorded and nothing is sent.
    5. `else` **Act** → the agent requests an action from KCG Rewards → KCG Rewards checks the guardrails → allowed → Member gets points or ×2 points plus a LINE message. A note says a breach is refused.
    6. Member purchases within the window → KCG Rewards records the outcome against the agent.
    7. Agent returns the member to the journey.
  Takeaway: waiting is a real decision, and KCG Rewards, not the agent, has the final say on limits.

- Placeholder "flowchart — journey trigger (member enters 'no purchase in 30 days') → AI agent step…" → **change** (fold in the worked example so it answers 10's win-back diagram)
  Type: flowchart (left to right)
  Shows:
    1. Overdue journey: member enters "no purchase in 30 days".
    2. AI agent step.
    3. Three member paths:
       - **Khun Nok** (4,900 THB in 12 months, 32 days since last order) → wait 4 days → act: LINE message + ×2 points for 14 days → orders on Shopee on day 7 (counted as a conversion).
       - **Khun Dao** (12,000+ THB, buys about every 2 months) → skip, reason recorded.
       - **Khun Tee** (180 THB once, 4 months ago) → act small: 50 bonus points + LINE message.
    4. Two exits back into the journey:
       - "Agent acted" (Nok, Tee) → tag re-engaged → next seasonal campaign.
       - "Agent didn't act" (Dao) → monthly LINE broadcast.
  About 11 nodes.
  Takeaway: one trigger, three decisions, no extra rules, and the journey carries on after the agent. Nok is the kind of member 10's 5,000 THB rule misses.
  Constraint: use the names and figures from the prose. Don't relabel Nok as "Member B". Both sit at 4,900 THB, but Member B has been gone 3 months and Nok 32 days.

## sections/12-shopify.md

- Placeholder "flowchart left to right — first order on a KCG Shopee shop → QR in parcel…" → **keep** (the document's one drawn member journey across channels)
  Type: flowchart (left to right, with one loop)
  Shows:
    1. First order on KCG's Shopee shop, with a QR in the parcel.
    2. Joins in KCG LINE OA and claims the order at the marketplace rate.
    3. Modern Trade receipt and Flagship Store purchases.
    4. **One KCG Rewards balance**.
    5. LINE invitation from a rule-based journey or AI decisioning.
    6. Signs in on KCG's Shopify store (when live) and sees balance and tier.
    7. Spends points or a reward at checkout.
    8. The order earns at the higher store rate, looping back to **One KCG Rewards balance**.
  About 8 nodes.
  Takeaway: value earned on third-party channels is spent and re-earned on KCG's own store, all in one balance.

## sections/13-rocket-ai.md

- Placeholder "A loop. Member activity from every channel builds one member profile…" → **change** (mark the three control points; this is now the only AI-analysis drawing in the document)
  Type: flowchart (loop)
  Shows:
    1. Member activity on every KCG channel.
    2. One member profile.
    3. AI analysis, in the portal or Claude/ChatGPT, within the admin's own access. *(Control point 1.)*
    4. Draft recommendation.
    5. KCG team reviews and applies. *(Control point 2.)*
    6. Journeys, campaigns and AI agent settings.
    7. AI decisioning acts per member; KCG Rewards enforces the guardrails. *(Control point 3.)*
    8. Outcomes (purchases, redemptions) loop back to One member profile.
  Eight nodes. Show the three control points as short edge labels or badges.
  Takeaway: one role answers and the other acts, each feeds the other, and KCG holds a control point at every hand-off.

## sections/14-services.md

- Placeholder "three levels of support side by side…" → **drop**
  Why: the three bullets above it carry the levels. Content that sits side by side isn't a flow, and a flowchart would only restate the list.
  Writer: add one sentence to the level bullets or the "two roles" paragraph: the optional services add to the dedicated team and don't replace it, and KCG can move between levels over time.
- Placeholder "receipt approval flow — member uploads receipt photo in LINE…" → **drop** (duplicate of 03's receipt flowchart)
  Writer: after the numbered steps, cross-reference the drawing, e.g. "The same flow is drawn in Transaction Capturing (section 3); under this service, the reviewer is Rocket's team." No other change: 03's diagram labels the reviewer "KCG team, or Rocket team under Receipt Approval".
- Placeholder "consultation cycle — programme data (reports, RFM, segments, AI analysis)…" → **drop**
  Why: it has the same shape as 13's loop (data → insight → action → outcomes → data). A second loop would tell the same story with a different actor.
  Writer: fold in the cycle, which the prose currently lists but never closes. After the 12.2 groups, add one sentence: the results of each campaign feed the next monthly scorecard, and the quarterly strategy refresh resets tiers, earn rules and the calendar from them.

---

## Conventions

Every diagram uses these names, in KCG's vocabulary:

- **Member** is the generic member. Worked examples use the names from the prose: **Member A** and **Member B** in 10, and **Khun Nok**, **Khun Dao** and **Khun Tee** in 11. Never mix the two sets.
- **KCG Rewards** is the programme and system: it matches orders, awards points, checks guardrails and records outcomes. Don't use "Rocket" or "the platform" as a node, except "Rocket team" as a reviewer under Receipt Approval.
- **KCG LINE OA** is where members join and receive messages. Message nodes say "LINE message" or "SMS".
- **Channels**:
  - KCG's Shopee shop, Lazada, TikTok Shop
  - Makro PRO
  - Modern Trade
  - Flagship Store
  - Event booths
  - Brand.com
  - KCG's Shopify store, marked "future" or "when live"
- **Front Line** is the staff counter mode.
- **KCG team** covers admins, marketers and reviewers.
- **Journey** is a rule-based journey. **AI agent** is the AI decisioning agent. **AI analysis** is the question-answering AI.
- **Shared records**: "One member purchase history" (03) and "One KCG Rewards balance" (04, 12). "One member profile" appears in 13 only.
- **Money and points**: THB with a thousands comma (5,000 THB), points as "N points", multipliers as "×2 points".
- **Tags and segments**: quoted exactly as in the prose ("first buyer", "LINE-quiet", "bundle interest", "no purchase in 30 days").
- **Agent actions** in diagrams are limited to what 11 supports: bonus points, ×2 multiplier, lucky-draw entries, LINE or SMS message, and tags. **No coupon push by the agent**; 11 has an open GAP on it.
- **Splits**: condition or interaction only. Never A/B, percentage or random.
- **Detail**: about 11 nodes at most; one idea per node; short edge labels.

## Consistency flag for writers (not a diagram change)

- **Coupon push by the agent**:
  - 11 has a GAP saying the agent can't push a coupon today.
  - 13 lists "coupons" among the agent's actions, and its table rows for Join and Convert have the agent sending a coupon.
  - 15 lists coupons among the allowed actions.

  Either align 13 and 15 with 11 (points, multipliers, entries, messages, tags) or resolve the GAP. The diagrams follow 11.
