# Diagram plan — KCG Rewards (kcg-202609), round 2

**Placeholders:** 3. One changed, two dropped, none added.
**Drawn diagrams carried over from round 1:** 7 in sections 03, 04, 06 and 10. Three kept as they are, three kept but switched to top-down so they fit A4 portrait, one dropped.
**Result:** 7 diagrams in the document. Six are already drawn and need no redraw beyond the direction change; only the §11 flowchart needs the diagrammer.

Round 2 put whole KCG slides beside most flows, and several round-1 diagrams are now covered by them:
- The Convert path is the `loyalty.line-shopify-flow` slide in §12.
- The stage map is the `loyalty.high-level-flow` slide in §01.
- The per-member AI decision log is the "AI: not just analyze, but act" slide in §11.

No diagram below repeats a slide, embed or `rocket-graphic` next to it.

A4 rule for the carried-over diagrams: a `flowchart LR` chain deeper than 4 ranks with sentence-length labels overflows a portrait page. §04, §06 and §10's win-back diagram switch to `TD`, with the same nodes and edges.

---

## sections/03-earn-channels.md

- Drawn flowchart "Four kinds of channel, one purchase history" (quadrants → One member purchase history → Points · Tier · Missions · Reports) → **drop**
  Why: the 2×2 table directly above lists the same four quadrants with the same channels. The paragraph after it ("One rule holds on every channel…") gives how each quadrant links a purchase to the member. With the table, this makes two visuals of one idea back to back. The stages are also drawn in §01's `loyalty.high-level-flow` slide.
  Writer: in the table, add "(receipt upload)" after Makro PRO (TOR 7.9). That was the only thing the flowchart's edge labels carried that the table lacks. Makro PRO sits beside the order-claim marketplaces but earns by receipt.

- Drawn sequence "Member / KCG's Shopee shop / KCG Rewards" (claim by order number, three `alt` outcomes) → **keep as drawn**
  Type: sequenceDiagram. 3 participants, 9 messages.
  Takeaway: the order reaches KCG Rewards before the member does, so a claim needs no receipt and no reviewer. The three outcomes are visible at a glance.
  Why it survives: the slide beside it (`loyalty.basic.marketplace-earn`) shows the claim screen, not the order arriving first or the three outcomes.

- Drawn flowchart "receipt → AI reads → checks + auto-approval switch → approved / review queue → reviewer" → **keep as drawn** (TD, 7 nodes)
  Takeaway: clean receipts need no person, and a person sees only the doubtful ones. Auto-approval is a per-chain switch.
  Why it survives: the `loyalty.basic.upload-receipt` slide is the member screen. The 8-row `kv_table` lists the settings but not the routing. §14 Receipt Approval cross-references this drawing, and the reviewer node already names "Rocket team under Receipt Approval (TOR 11)".

## sections/04-points.md

- Drawn flowchart "Life of a point" (purchase → conditions → rate + bonus → optional hold → One KCG Rewards balance → redeemed / reversed / expired) → **change: direction only**
  Type: flowchart **TD** (was LR). Nodes, labels and edges unchanged, 10 nodes.
  Takeaway: every point is a dated batch with a known fate, which makes holds, reversals and expiry predictable for finance.
  Why: in LR it is five ranks wide with long labels plus three exits, too wide for portrait. No slide or graphic in §04 shows this flow.

## sections/06-tier.md

- Drawn flowchart "Purchase → tier progress → upgraded to Gold 24 Mar 2027 → entry reward → review 24 Mar 2028 → stays / moves down" → **change: direction only**
  Type: flowchart **TD** (was LR). Nodes unchanged, 9 nodes. Keep the dotted refund edge into progress.
  Takeaway: purchases only move a member up. A move down happens only at the review.
  Why: a 6-rank chain doesn't fit portrait in LR. The tier slides beside it (tier settings, tier page) and the `tier_stack` show the ladder, not the up-then-review path.

## sections/08-analyze.md

- Placeholder "purchases from every channel → one member profile → segments (live rules, uploaded lists, RFM groups, tags) → three uses…" → **drop**
  Why: it is a linear chain with a fan-out of three list items, not a branch. The prose carries it twice: "Purchases from every channel build one profile per member, profiles form segments, and segments feed campaigns, automation and AI", and "A segment is built once and used anywhere: a one-off LINE broadcast, a rule-based journey (§10) or an AI decisioning agent (§11)". The live Audience builder embed titled "segments defined once, reused everywhere" follows immediately. The channel-to-profile half is also §01's `loyalty.high-level-flow` slide.
  Writer: none. Both sentences must stay.

## sections/10-rule-based.md

- Drawn flowchart "Welcome journey" (trigger → welcome → wait 7 days → condition split → two interaction splits) → **keep as drawn** (TD, 11 nodes)
  Takeaway: a wait, a loyalty-data split and two interaction splits, with a different send on every branch.
  Why it survives: the Journey Builder slide beside it shows the canvas, not KCG's branches. This is the section's key drawing.

- Drawn flowchart "Member A / Member B vs the win-back rule" → **change: direction only**
  Type: flowchart **TD** (was LR). Nodes, labels and edges unchanged, 6 nodes.
  Takeaway: the member who most needs the offer is the one the rule drops. §11 opens on this.
  Why: two entry nodes and two checks in LR with sentence-length labels sit at the edge of portrait width. TD removes the risk.

## sections/11-ai-decisioning.md

- Placeholder "flowchart of one agent step — member handed over → agent reviews… Act / Wait / Skip…" → **change**
  Type: flowchart TD, 10 nodes
  Shows:
    1. "Journey hands the member over (e.g. enters 'no purchase in 30 days')"
    2. "AI agent reviews: history on every channel, eligible actions, guardrail headroom, goal progress"
    3. Decision: "Act, wait or skip?"
    4. Act → "KCG Rewards checks the guardrails and refuses any breach" → "Sent: LINE or SMS message, bonus points, ×2 points or a coupon" → exit A
    5. Wait → "Records what it is watching for and when to look again" → decision "Reviews left within your limit (e.g. 3 in 2 weeks)?"
       - Yes, edge "look again with fresh data" → loops back to node 2
       - No → exit B
    6. Skip → "Records why; nothing sent" → exit B
    7. Exit A: "Back to the journey: tag 're-engaged' → next seasonal campaign"
    8. Exit B: "Back to the journey: monthly LINE broadcast"
  Takeaway: waiting is a real decision with a cap. KCG Rewards, not the agent, has the final say on limits, and the journey always carries on after the agent.
  Changes from the placeholder:
    - The guardrail check is labelled as KCG Rewards, which is the ownership boundary. This absorbs the one point the dropped Nok sequence carried that the prose states briefly ("Guardrails are checked twice… the platform refuses").
    - The two journey exits come from "Inside your journeys", so the drawing also shows the agent as one step inside a journey.
  Why it survives: the `amp.admin.decisioning-agent` slide names Act / Wait / Skip as text only. It draws neither the loop, its cap, nor the exits.
  Constraints:
    - Draw no branch for a refused action, because the section doesn't say what happens next.
    - Coupon sending by the agent is a go-live commitment presented as available (gaps.md C2), so it may appear in the "Sent" node.

- Placeholder "sequence for Khun Nok — participants Journey, AI agent, KCG Rewards, Nok…" → **drop**
  Why: it tells the same story three times over.
    - The numbered Day 0 / Day 4 / Day 7 steps directly above already read as a timeline.
    - The "AI: not just analyze, but act" slide later in this section draws a per-member day-by-day decision log with ACT / WAIT / GOAL rows.
    - The per-member timeline bullet ("Day 0: waited… Day 4: ×2 points and a LINE message. Day 7: purchased.") says it a third time.
  The wait-then-act shape and the guardrail check move into the flowchart above.
  Writer: in step 2 of Khun Nok, and in "Guardrails are checked twice", say **KCG Rewards** instead of "the platform". The prose then uses the same system name as the flowchart's guardrail node. No other change.

## Sections with no placeholders and no additions

00, 01, 02, 05, 07, 09, 12, 13, 14, 15, 16. Each flow in them is already carried by a whole slide, a `rocket-graphic` or a numbered list:
- §01: the stage table and the high-level-flow slide
- §02: the sign-up slide and the journey-stage stepper
- §07: the referral slide and its 3-step list
- §09: the ai-journey-force slide
- §12: the line-shopify-flow slide
- §14: the service stepper, plus the cross-reference to §03's receipt diagram

No flow is being forced through prose without a picture beside it.

---

## Conventions

Every diagram uses these names, in KCG's vocabulary:

- **Member** is the generic member. The worked examples use the prose names: **Member A** and **Member B** in §10, and **Khun Nok**, **Khun Dao** and **Khun Tee** in §11 (prose only this round). Never mix the two sets.
- **KCG Rewards** is the programme and the system. It matches orders, awards points, checks guardrails and records outcomes. Never "Rocket" or "the platform" as a node. The one exception is "Rocket team" as a receipt reviewer under Receipt Approval (TOR 11).
- **Journey** means a rule-based journey. **AI agent** means the AI decisioning agent.
- **KCG LINE OA** is where members join. Message nodes say "LINE message" or "SMS".
- **Channels:**
  - KCG's Shopee shop (also Lazada and TikTok Shop)
  - Makro PRO
  - Modern Trade
  - Flagship Store
  - Event booths
  - Brand.com
  - KCG's Shopify store, marked "future" or "when live"
- **Front Line** is the staff app.
- **KCG team** covers admins, marketers and reviewers.
- **Shared record:** "One KCG Rewards balance" (§04).
- **Money and points:** THB with a thousands comma (5,000 THB), points as "N points", multipliers as "×2 points".
- **Tags and segments** are quoted exactly as in the prose: "first buyer", "LINE-quiet", "bundle interest", "re-engaged", "no purchase in 30 days".
- **Splits** are condition or interaction only, never A/B, percentage or random.
- **Size:** sequences have at most 4 participants and 10 messages. Flowcharts have at most 12 nodes and are drawn `TD` whenever the chain is deeper than 4 ranks.
