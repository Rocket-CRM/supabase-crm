# Diagram plan — KCG Rewards (kcg-202609), round 4

**In the compiled document:** 1 placeholder and 11 drawn Mermaid blocks (§03 ×2, §04 ×1, §09 ×3, §11a ×5).
**Decisions:**
- Kept as drawn: 8.
- Changed: 3. These are the §03 conversion placeholder (redefined as a mechanism loop), the §03 receipt flowchart (redrawn so manual approval is the default path), and the §09 win-back rule flowchart (one mislabelled node).
- Dropped: 0.
- Added: 0.

**Result:** 12 diagrams. The diagrammer draws two in §03 and makes a label fix in §09 and two participant renames in §11a. No writer fold-ins are needed.

No diagram below repeats a slide, embed or `rocket-graphic` next to it. The one member walking from Shopee to KCG's store is told once, in §10, as the `loyalty.line-shopify-flow` slide plus the 5-step walkthrough. The §03 diagram shows the mechanism behind that walk, not the walk itself.

---

## sections/03-earn-channels.md

- Placeholder "one member's path — first order on a KCG Shopee shop claimed at the lower third-party rate…" → **change**
  Type: flowchart TD, 9 nodes. Stays where it is: after the slide "Marketplace orders earn at the base rate…", before "Rocket supports each link in that chain".
  Shows:
    1. "Member buys on a third-party channel: Shopee, Lazada, TikTok Shop, Makro PRO or Modern Trade"
    2. "Claims the order or uploads the receipt in LINE: KCG learns who bought"
    3. "Earns at the lower third-party rate (channel groups, §04)"
    4. "One KCG Rewards balance" (the hub)
    5. "Ways to earn shows that KCG's own channels earn more"
    6. "Own-channel nudge: a journey or AI agent sends a LINE message and a first-order coupon (§09)"
    7. "Buys on KCG's own channels: Flagship Store, event booths, Brand.com, Shopify, LINE orders"
    8. "Earns at the higher own-channel rate, no claim step (§04)"
    9. "On KCG's Shopify store: sees and spends the balance at checkout (§10)"
  Edges: 1 → 2 → 3 → 4. Node 4 feeds both 5 and 6. Nodes 5 and 6 both lead to 7. Node 7 → 8 → back to 4, labelled "into the same balance". Node 4 → 9, labelled "when the Shopify store is live".
  Takeaway: both kinds of channel feed one balance, and the balance is where the rate difference becomes visible. Each lever acts at a named point: the claim identifies the buyer, channel groups set the rates, activation prompts the switch, and the plugin lets members spend on KCG's store.
  Why changed: the placeholder asked for "one member's path". That is the §10 slide and walkthrough, and drawing it here would tell the customer journey twice. The mechanism loop is what §03's numbered chain forces through prose. Its return edge, where own-channel purchases go back into the same balance, is the loop the argument depends on.
  Constraints:
    - Don't name a member, and don't write "she".
    - Don't give illustrative rates in nodes. The 25 / 20 THB figures stay in prose and §04.
    - Spending at checkout is tied to the Shopify store only. Brand.com earns by order sync (§03), so no node may say members spend on Brand.com.
    - Don't draw a §08 report node. §03 doesn't claim it.

- Drawn sequence "Member / KCG's Shopee shop / KCG Rewards" (the order arrives first, the member claims by order number, three `alt` outcomes) → **keep as drawn**
  Type: sequenceDiagram. 3 participants, 8 messages, one `alt`.
  Takeaway: the order reaches KCG Rewards before the member does, so a claim needs no receipt and no reviewer. The three outcomes are visible at a glance.
  Still matches the prose. "Status reached delivered" is the recommended claim status the prose names. The `loyalty.basic.marketplace-earn` slide shows the claim screen, not the order arriving first.

- Drawn flowchart "receipt → AI reads → checks + auto-approval switch → approved / review queue → reviewer" → **change**
  Type: flowchart TD, 9 nodes.
  Why: the current single diamond ("All checks pass … and auto-approval on for this chain?") makes auto approval look like the main route and the queue look like the exception. The prose now says the opposite. Manual approval is the default and every receipt is reviewed. Auto approval is an optional switch per retailer group, and doubtful receipts still go to the same queue. Either route ends in the same result. The drawing also stopped at "Approved" and missed the "once approved" consequences the prose now spells out.
  Shows:
    1. A: "Member photographs a Modern Trade or Makro PRO receipt in Ways to earn (LINE message: 'received')"
    2. B: "AI reads chain, branch, receipt no., date and lines, and keeps only the KCG lines on that chain's product list"
    3. D1 (decision): "Auto approval switched on for this retailer group?"
       - Edge "No (default)" → Q
       - Edge "Yes (optional)" → D2
    4. D2 (decision): "Passes every check: not a duplicate, total adds up, KCG lines found, AI confidence above the minimum?"
       - Yes → OK
       - No → Q
    5. Q: "Review queue, pre-filled by AI with the reading and the reason"
    6. G: "Reviewer (KCG team, or Rocket team under Receipt Approval, TOR 11) checks the photo and corrects the reading"
       - "approves" → OK
       - "rejects" → X
    7. OK: "Approved: a purchase in the member's history, dated by the receipt; earnable amount = KCG lines after discounts"
    8. E: "Points under KCG's earn rules (§04); product rules, missions and tier progress apply; LINE message 'approved, +N points'"
    9. X: "Rejected: LINE message to the member"
  Edges: A → B → D1, and OK → E, alongside the branches above.
  Takeaway: AI reads every receipt, and a person approves it unless KCG switches auto approval on for that retailer group. Even with auto approval on, anything doubtful reaches the same queue. Both routes end in the same purchase and points.
  Constraints:
    - Order the branches so the "No (default)" edge into the queue is the straight-down path and "Yes (optional)" is the side branch.
    - Draw no reversal branch. Cancellation of an approved receipt is one prose sentence and doesn't need a node.
    - §12 Receipt Approval refers back to this drawing, so the reviewer node must keep "Rocket team under Receipt Approval (TOR 11)".

## sections/04-points.md

- Drawn flowchart "Life of a point" (purchase → conditions → best rate + bonus → optional hold → One KCG Rewards balance → redeemed / reversed / expired) → **keep as drawn**
  Type: flowchart TD, 10 nodes.
  Takeaway: every point is a dated batch with a known fate, which makes holds, reversals and expiry predictable for finance.
  Still matches the prose. Channel groups belong to the rate, which is already the "Best qualifying rate" node, and don't need a node of their own. The diagrammer may tidy the stray spaces in the first edge line while drawing; no other change.

## sections/06-tier.md

- Tier path (qualify → upgrade → review) → **converted**: the `rocket-graphic` `flow` block doesn't render in the viewer, so it is now a Mermaid flowchart TD (9 nodes, three subgraphs), same labels, dates, refund note and both review outcomes.

## sections/09-activation.md

- Drawn flowchart "Welcome journey" (trigger → welcome → wait 7 days → condition split → two interaction splits) → **keep as drawn**
  Type: flowchart TD, 12 nodes, which is the A4 limit.
  Takeaway: a wait, a loyalty-data split and two interaction splits, with a different send on every branch.
  Still matches steps 1–5 of the example. The Journey Builder slide beside it shows the canvas, not KCG's branches.

- Drawn flowchart "Member A / Member B vs the win-back rule" → **change: one label**
  Type: flowchart TD, 6 nodes, same edges.
  Fix: node N reads "Nothing sent (Member B, further gone than A)". But N also receives the `C2 -->|No|` edge, which is any member with a recent purchase, not Member B. Relabel N to "Nothing sent". Move the comparison onto the edge: `C1 -->|"No: Member B, gone longer than A"| N`.
  Takeaway: the member who most needs the offer is the one the rule drops. The AI decisioning subsection opens on this.

- Drawn flowchart "one agent step" (journey hands over → agent reviews → act / wait / skip → guardrail check → two journey exits) → **keep as drawn**
  Type: flowchart TD, 10 nodes.
  Takeaway: waiting is a real decision with a cap. KCG Rewards, not the agent, has the final say on limits, and the journey always carries on after the agent.
  Still matches the prose: "Guardrails are checked twice… KCG Rewards refuses", "up to three reviews over two weeks… it stops and the journey moves on", and the two exits in "Inside KCG's journeys". The labels are already third person ("KCG's limit").

- No additions. The broadcast-versus-journey difference is carried by its comparison table. The broadcast-to-journey hand-off is two sentences with no branch. The four activation layers are the `horizontal_stepper`.

## sections/11a-integration.md

This section is owned by the parallel integration thread. The TOR asks for an integration architecture and data flow (19.4, 19.5), and the prose says "the diagrams in this section are the starting integration architecture and data flow". All five stay. The only changes are participant names, so the POS reads the same across the document.

- Drawn flowchart LR "Integration architecture" (7 sources → KCG Rewards → SAP, data lake) → **keep as drawn**
  Type: flowchart LR, 9 nodes, 3 ranks. The sources stack vertically, so it fits portrait.
  Takeaway: one hub. Every channel feeds it, SAP both supplies it and receives from it, and the data lake receives everything.

- Drawn sequence "Route 1 · Daily sales file by email" → **change: participant name only**
  Rename `KCG POS or back office` to **`Flagship POS or back office`**, matching the architecture node and §03. There are 3 participants and 7 messages; nothing else changes.
  Takeaway: the file arrives at end of day, and duplicates are skipped.

- Drawn sequence "Route 2 · Front Line staff app" → **keep as drawn**
  Type: sequenceDiagram. 3 participants, 6 messages, one `alt`.
  Takeaway: no POS is involved, points are immediate, and a walk-in is registered in the same flow.

- Drawn sequence "Route 3 · Real-time POS connection" → **change: participant name only**
  Rename `KCG POS` to **`Flagship POS`**. There are 3 participants and 8 messages, with one `opt`.
  Takeaway: bills arrive at the till, duplicates are refused, and refunds reverse the points.

- Drawn flowchart LR "Data lake: four methods" → **keep as drawn**
  Type: flowchart LR, 6 nodes, 3 ranks.
  Takeaway: methods 1–3 push into KCG's lake. Method 4 leaves the data in Rocket's warehouse for KCG to query, which is the one ownership boundary the table alone doesn't show.

## Sections with no diagrams, and none added

00, 00a, 01, 02, 05, 07, 08, 10, 11, 12, 13, 14. Every flow in them is carried by a slide, a `rocket-graphic`, a table or a short numbered list:
- §01: the journey table and the "KCG Rewards at a glance" slide.
- §02: the sign-up slide with its 4-step list, and the journey-stage stepper.
- §07: the Friend Get Friend 3-step list, and the lucky-draw entry list.
- §10: the `loyalty.line-shopify-flow` slide and the 5-step one-wallet walkthrough. This is the document's single drawing of one member's path.
- §12: the service stepper, and the cross-reference to §03's receipt flowchart.

Render check for the publisher, outside Mermaid: `pillar_cards` (§00) is not among the `rocket-graphic` kinds listed in SCAFFOLDS § Visuals. Confirm it renders in the viewer.

---

## Conventions

Every diagram uses these names, in KCG's vocabulary and in the third person. Never write "you" or "your" in a label: say "KCG's limit" or "the KCG team".

- **Member** is the generic member in §03, §11a and the §09 journey. The worked examples keep the prose names: **Member A** and **Member B** in the §09 win-back rule. Khun Nok, Khun Dao and Khun Tee are prose only. Never mix the two sets.
- **KCG Rewards** is the programme and the system. It matches orders, reads files, awards points, checks guardrails and records outcomes. Never use "the platform" as a node. The two exceptions name Rocket as an owner:
  - "Rocket team" as a receipt reviewer under Receipt Approval (TOR 11).
  - "Rocket's analytics warehouse" in the §11a data-lake method 4.
- **AI** reads receipts (§03). **AI agent** is the decisioning agent (§09). **Journey** means a rule-based journey.
- **KCG's LINE OA** is where members join and claim. Message nodes say "LINE message" or "SMS".
- **Ways to earn** is the member's claim and upload sheet.
- **Channels:**
  - KCG's Shopee shop (also Lazada, TikTok Shop), or "Shopee, Lazada, TikTok Shop (6 shops)" in §11a.
  - Makro PRO, or "Makro PRO seller account" in §11a.
  - Modern Trade.
  - Flagship Store.
  - Event booths.
  - Brand.com.
  - KCG's Shopify store, marked "when the Shopify store is live" wherever it is a spend point.
  - LINE orders.
- **Channel groups:** "third-party rate" and "own-channel rate". Group names, when used, are Marketplaces, Modern Trade, Makro PRO and Own channels (§04).
- **Systems:**
  - The till system is **Flagship POS**, or **Flagship POS or back office** where the file can come from either.
  - **Front Line** is the staff app, and **Staff on Front Line** is its participant.
  - Also **SAP ERP**, **KCG data lake**, and **Open API**.
- **KCG team** covers admins, marketers and reviewers.
- **Shared record:** "One KCG Rewards balance".
- **Money and points:** THB with a thousands comma (5,000 THB). Points are written as "N points", and multipliers as "×2 points".
- **Tags and segments** are quoted exactly as in the prose: "first buyer", "LINE-quiet", "bundle interest", "re-engaged", "no purchase in 30 days".
- **Splits** are condition or interaction only, never A/B, percentage or random.
- **Shape and size:**
  - Square nodes; diamonds only for decisions.
  - `flowchart TD` whenever the chain is deeper than 4 ranks. `LR` only for §11a's hub-shaped diagrams.
  - Sequences have at most 4 participants and 10 messages. Flowcharts have at most 12 nodes.
