# Outline — KCG Rewards proposal (kcg-202609) · round 4

**Structure.** Features follow the retention journey — Join → Earn → Burn → Grow → Campaign → Analyze → Activate → Convert — with the TOR's own terms in headings and clause tags inline, e.g. "(TOR 5.1.1)". Round 4 applies `sources/review-2.md` (founder, 2026-09-29) on top of round 3 (third-person voice, flow_columns overview, square diagrams). Activate is now **one section (09)** with subsections; numbering after it shifts: 10 Shopify, 11 Rocket AI, 12 Services, 13 Why Rocket, 14 Pricing rationale.

**The thread through the document.** One of the programme's main jobs is moving KCG's customers from third-party channels to KCG's own. Mechanism (full home: §03 opening): acquire members on marketplaces, Modern Trade and Makro PRO at a lower earn rate because those channels leave KCG a thin margin → KCG's own channels keep the full margin, so they earn more and carry better benefits → one wallet makes the difference visible each time a member earns → repeat purchases shift to KCG's channels. §04 sets the rates, §09 nudges the switch, §10 lets members spend on KCG's store. Other sections reference it; they don't re-explain it.

**Every writer reads:** `dossier.md` (all — especially § Round 4 decisions, § Round 2 decisions, § Brief checklist, § Fit decisions); `sources/review-2.md`; `sources/review-1.md`; `Writing Principles/PROPOSAL_WRITING_PRINCIPLES.md` § Section 5 (V1–V12 — **V1 is third person**, V9–V12 are new); `.cursor/skills/proposal/SCAFFOLDS.md` (your kind + Visuals + Depth); the current draft of your section and any draft you absorb (keep what is right, rewrite the rest); `research/product.md` (your §); `research/sources.md` (your TOR clauses).

**Evidence (use, in this order):**
1. `research/assets-slides.md` — whole KCG slides as `[asset:screenshot;id=…;title=…]`. Write a customer-facing `title=`. Local PNGs at `/tmp/cap/slides/` if present.
2. Live admin embeds from the demo merchant: `[asset:mockup;id=loyalty.admin.<feature>.<page>;title=…]` (ids in `research/mockups.md`; they render the full desktop portal now). Admin library screenshots already used in the draft stay valid.
3. Member mockups with `pitch=kcg-loyalty-crm` when neither covers it. Never `[asset:fixed_diagram;…]` on a slide without a diagram.
4. `rocket-graphic` blocks (`flow_columns`, `pillar_matrix`, `tier_stack`, `horizontal_stepper`, `kv_table`, `numbered_steps`, `milestone_timeline`) and `[DIAGRAM: …]` placeholders (A4-fit: sequence ≤4 participants, ≤10 messages; flowchart ≤12 nodes; square nodes).

**Voice:** Rocket is "we"; KCG in the third person — "KCG's members", "the KCG team", "most of KCG's customers" — never "you"/"your" outside quoted member copy (V1). No "KCG wants…", "The TOR asks…". No re-telling KCG's business to KCG. No gap markers. Say each idea once; elsewhere one clause + what the reader finds there ("§04 sets the per-channel rates").

**Prose:** explain, don't sloganise (V9) — no triads, chiasmus headings, aphoristic closers, antithesis pairs. **No word-count target.** Cut repetition; keep and explain every mechanism.

Heading levels: each file starts with `## <nn> · <Title>`; subsections `###`, sub-subsections `####`.

---

## 00 — Executive summary
- **File:** `sections/00-executive-summary.md` · **Kind:** Executive summary. Written after the body and before the editor pass.
- **Keep** the round-3 form: one-line understanding, the `flow_columns` overview, pillar paragraphs, Why Rocket in brief. **Change:** make the third-party → first-party conversion explicit in the opening lines and in its pillar (lower earn on third-party channels, better on KCG's own, one wallet — pointing to §03, §04, §10); section numbers to the new scheme (Activate §09 covers audiences, broadcasts, journeys, AI decisioning); the flow_columns item for flagship/booths reads "Email sales file, POS or Front Line"; Makro PRO reads as its own channel ("Order claim, or receipt upload").
- **Hands to:** 00a/01.

## 00a — About Rocket
- **File:** `sections/00a-about-rocket.md` — unchanged except cross-references (editor pass).

## 01 — The KCG Rewards journey
- **File:** `sections/01-understanding.md` · **Kind:** Overview.
- **Scope:** the journey map table (stage · what the member does · TOR clauses · section), renumbered: Activate → §09 (audiences, broadcasts, rule-based journeys, AI decisioning); Convert → §10; AI summary §11; services, why Rocket, pricing §12–14. Add one sentence naming the thread: members are won on third-party channels and, stage by stage, given reasons to buy again on KCG's own (§03 explains how). No restatement of the exec summary.
- **Opens from:** the overview. **Hands to:** Join — every stage starts with a known member.

## 02 — Member Management (Join)
- **File:** `sections/02-join.md` · **Kind:** Feature.
- **Scope:** as round 3 (sign-up in LINE, login channels + LINE always required, profile & custom fields, consent/PDPA, member status = tier + journey stage, Customer 360, existing members brought in) **plus the LINE OA as the programme's home (TOR 3.4, 7.8 member side)** — moved here from §03: members join, check balance, see history and coupons, find every way to earn and redeem, all inside KCG's LINE OA; rich menu entry points. The "Ways to earn" hub itself is introduced in §03 — here one clause pointing to it. Journey stages are segments the KCG team can target in §09 (Audiences) — say that, not §10.
- **Evidence:** slides `loyalty.basic.signup`, `loyalty.basic.profile`, `loyalty.reports.customer-360`, `loyalty.basic.home` if §03 doesn't use it; admin embeds already in the draft.
- **Reads:** product.md §3; `Signup_Login.md`, `Consent.md`, `Forms.md`, `Customer_Import_System.md`; `LINE_OA` / narrative Join anchors; old §03 "LINE Official Account" subsection.
- **Opens from:** the journey map. **Hands to:** Earn — once a member is known, every purchase can count.

## 03 — Transaction Capturing: earn on every channel (Earn)
- **File:** `sections/03-earn-channels.md` · **Kind:** Feature — primary.
- **Order:**
  1. **Opening — one purchase history, four kinds of channel.** Every channel lands in one member purchase history under one set of rules (TOR 1.8, 1-P2). The 2×2 (online/offline × third-party/first-party) with Makro PRO in online third-party beside the marketplaces.
  2. **Why the channels earn differently — the conversion logic, in full (brief #25).** Third-party channels are where KCG's customers are won, and where the brand never learns who bought; the claim or receipt is the moment they identify themselves. Those channels leave a thin margin, so they earn at a lower rate; KCG's own channels keep the full margin and can pay more (with an illustrative example from §04, e.g. 25 THB = 1 point vs 20 THB = 1 point) — slide `loyalty.basic.brand-com-earn`. One balance makes the difference visible every time; that is how repeat purchases move to KCG's channels. §04 sets the rates; §09 nudges the switch; §10 lets members spend on KCG's store.
  3. **Ways to earn — the member's one place to earn** (moved from the end): one sheet in LINE with a tab per channel; claim and upload forms inside; info cards for automatic channels; editable banners; tabs hidden when unused; slide `loyalty.basic.home`. A member claiming a Shopee order sees on the same sheet that KCG's own store earns more.
  4. **One rule on every channel:** a purchase earns only when it names the member (phone from sign-up); how each channel makes the link.
  5. **Marketplaces — Shopee, Lazada, TikTok Shop, six shops (TOR 7.5–7.7):** native connections, live today; the KCG team connects each shop once from the admin portal and it works — no custom integration and no integration cost. Member claims with order number; status KCG chooses; support lookup; clean start. Slide `loyalty.basic.marketplace-earn`; keep the existing sequence diagram.
  6. **Makro PRO — its own channel (TOR 7.9):** integrated like a marketplace, members claim with the order number; we build the connection free of charge where Makro PRO offers a seller API connection; where it doesn't, Makro PRO buyers upload the receipt or tax invoice exactly as in Modern Trade (next subsection). Its own sales channel and product list either way.
  7. **Modern Trade — receipt upload (TOR 7.2):** order per dossier: member photographs the receipt → AI reads every receipt → **two ways to approve: manual (default) and auto (optional)** → **once approved**: earnable amount = KCG lines after discounts, points under KCG's earn rules (§04), product rules and missions apply, LINE notices → manual in detail (pre-filled queue, reviewer, Receipt Approval service §12) → auto in detail (8-setting `kv_table`, recommendation to start manual, audit filter) → purchase date, daily cap, pack codes as a later option. Slide `loyalty.basic.upload-receipt`; keep the flowchart.
  8. **Flagship Store and event booths — POS (TOR 7.1, 7.3):** three routes, **email sales file first**: (a) the POS or back office emails its routine daily sales export (member phone on each bill) to a dedicated KCG Rewards address, imported automatically — same result as an integration with no integration work on KCG's or the POS vendor's side; points arrive when the file does (typically end of day); recommended for the flagship; (b) Front Line staff app for booths/pop-ups — points at once; (c) real-time POS connection where the vendor can send each bill — points at the till. Recommendation paragraph. Events as acquisition (existing paragraph). Slide `loyalty.basic.pos-earn`.
  9. **Brand.com and Shopify — KCG's own online store (TOR 7.4, 7.10):** Brand.com sends orders by Open API (order sync) — earns with no claim, matched by phone or email, refunds reverse. **State the difference plainly (brief #30, V11):** order sync covers earning only; Rocket's Shopify plugin, Thailand's only Shopify-native loyalty plugin, also lets members **see** their balance and what each product earns inside the store, **burn** points and rewards at checkout, and **refer** friends to the store — which is what turns the balance built on Shopee and at Lotus's into a reason to buy on KCG's store. Slide `loyalty.basic.shopify-plugin`; "§10 goes through each dimension".
  10. **LINE OA orders (TOR 7.8):** one short paragraph — orders taken through LINE earn as first-party purchases (Front Line or KCG's order tool), no claim. The LINE OA as home is §02.
  11. **Connections and volume (TOR 7, 3.3):** marketplace connections (native), Makro PRO connection (built by us at no charge), receipt upload, email sales-file import, Front Line, POS connection where the POS can send, Brand.com Open API, Shopify plugin — all in the licence. Capacity sentence as round 3. Connection methods in the technical proposal.
- **Reads:** product.md §2; `Marketplace.md` Concept; `Receipt_Channel_OCR_Auto_Approve.md` Concept, Rules, Merchant admin journey; `Receipt_Upload_Earning.md` Concept; `Purchase_Import_System.md` Concept; `Frontline_Admin_Actions.md`; `Shopify.md` Concept; the current §03 and the old §03 LINE OA subsection.
- **Opens from:** Join (members are known). **Hands to:** Earn Logic — how much each purchase earns.

## 04 — Earn Logic: KCG Rewards Points
- **File:** `sections/04-points.md` · **Kind:** Feature.
- **Scope:** as round 3. **Change:** where channel rates appear, tie them to the conversion logic in one sentence + pointer to §03 (don't re-explain); make channel groups the mechanism ("Marketplaces", "Modern Trade", "Makro PRO", "Own channels"; a new shop joins its group's rate). Renumber references (Activate §09, Shopify §10).
- **Opens from:** Earn channels (every purchase arrives). **Hands to:** Rewards — what points are for.

## 05 — Reward & Privilege (Burn)
- **File:** `sections/05-rewards.md` · **Kind:** Feature.
- **Scope:** as round 3 **minus Lucky Draw as a mechanic** (moves to §07): the reward catalogue can include a lucky-draw entry as a reward type in one line pointing to §07, nothing more. **Controls on every reward** (who, when, how many, tier price): keep the current evidence; the live admin reward-settings embed will replace it when the viewer supports scroll-to-section (gaps B1) — don't add a placeholder marker. Point Redemption Campaign, Privilege Campaign. Renumber references (broadcast → §09).
- **Opens from:** Earn Logic (a balance). **Hands to:** Tier — members who spend more get more.

## 06 — Member Tier (Grow)
- **File:** `sections/06-tier.md` — unchanged except cross-references and prose sweep (editor pass).

## 07 — Campaign Management (Campaign)
- **File:** `sections/07-campaigns.md` · **Kind:** Feature — primary.
- **Scope:** as round 3 **plus Lucky Draw (TOR 6.3)** moved from §05 with its mechanics: members collect entries (tickets from purchases, missions, check-in, or points redeemed for an entry), KCG draws from the exported entry list; spin wheel as the platform-run instant alternative (dossier § Fit decisions). Slide `loyalty.campaigns.luckydraw`. Keep TOR 6.3 findable (tag in heading). Renumber references (journeys → §09).
- **Opens from:** Tier. **Hands to:** Analyze — every campaign produces data on who took part.

## 08 — Reporting, Dashboard & Customer Insight (Analyze)
- **File:** `sections/08-analyze.md` · **Kind:** Admin/reports.
- **Scope:** as round 3. **Change:** Audience Builder moves to §09 — here, segments and RFM are shown as analysis (who is where, how segments perform) with one line: "the same segments become audiences for broadcasts, journeys and AI agents (§09)". Close by handing to §09: knowing who stopped where is half the job; §09 moves them. Renumber.
- **Opens from:** Campaigns. **Hands to:** Activate.

## 09 — Activation: marketing automation and AI decisioning (Activate)
- **File:** `sections/09-activation.md` · **Kind:** Feature — primary. Absorbs the round-3 drafts `archive/round3/10-rule-based.md` and `archive/round3/11-ai-decisioning.md`; keep their Mermaid blocks and screenshots where they still fit.
- **Subsections, in order:**
  1. **Why activation (brief #13–15, #20).** Newton slide + quote; the perfect journey (Join, Earn, Burn, Grow, Engage & return, Convert on KCG's own channels) vs where members stop (the table); activation as the fabric; 50%+ as Rocket's estimate; the ladder this section walks: audiences → broadcasts → rule-based journeys → AI decisioning. Heading descriptive — not "The journey KCG designs, and the one members take".
  2. **Audiences: who to reach (TOR 9.x as applicable).** Built from any loyalty data (tier, journey stage from §02, channel, points, campaign activity, interactions); live (members enter and leave as data changes) or fixed; built once and used by broadcasts, journeys and AI agents. Admin embed `loyalty.admin.audience.list` or the audience slide.
  3. **Targeted LINE broadcasts.** One message, sent once, to an audience, at a moment the KCG team chooses (or to all LINE friends / friends not yet members — the route to convert KCG's existing LINE audience, alongside the import in §02); test send, schedule, send log and clicks. **Distinguish explicitly from journeys:** a broadcast is calendar-led and one-shot; a journey is always on — each member enters on their own when their trigger happens, waits, branches on what they did, and gets a different next step. Rule of thumb in one line. A broadcast can hand off to a journey (button tap enrols).
  4. **Rule-based journeys (TOR 1.6).** As round-3 §10: example first (delay → condition split on loyalty data → interaction split → different sends) with its flowchart; building blocks; typical journeys table; then **the limits of rules** (optimise for the mean, fixed paths, rule explosion, the 4,900-THB member) as the bridge.
  5. **AI decisioning (TOR 9.4).** As round-3 §11: opens on the limits just named (one line each, no re-telling), an expert marketer for every member at mass-market scale, "one of only a few … in the world", goal/actions/guardrails, act/wait/skip, worked KCG example, measurement, works inside journeys, rules vs AI table. Keep both diagrams.
- **Evidence:** slides `loyalty.ai-journey-force`, `amp.admin.audience-builder`, `amp.admin.rules-builder`, `amp.admin.decisioning-agent`, `loyalty.perfectcustomerjourney3`; library screenshots already in the round-3 drafts (workflow analytics, MCA AI screens).
- **Reads:** round-3 §09, §10, §11; `AMP_Workflows.md` Concept (audience, workflow, triggers); `AMP - Rule Based.md`; `AMP - AI Decisioning.md` Concept.
- **Opens from:** Analyze. **Hands to:** Convert — the most valuable push is the one that brings a member to KCG's own store.

## 10 — Brand.com & Shopify Plugin (Convert)
- **File:** `sections/10-shopify.md` (was `12-shopify.md`) · **Kind:** Feature — important.
- **Order:** (1) Opening, plain: §03 introduced Brand.com and Shopify as earn channels; this section is about what members can do on KCG's own store beyond earning. Order sync — what most loyalty vendors mean by "integrates with Shopify" — sends store orders to the loyalty system so they earn points; that is one dimension. The plugin works in four: **Earn, See, Burn, Refer** (+ Operations), each defined in one line, and says why the other three are the ones that make a member choose KCG's store (their balance from Shopee and Lotus's is visible and spendable there). Thailand's only Shopify-native loyalty plugin; live; nothing rebuilt. (2) The comparison table grouped by those dimensions (existing). (3) The one-wallet walkthrough (existing, tightened; it closes the conversion loop from §03). (4) See / Burn / Refer / Operations subsections (existing). (5) Brand.com today, Shopify when ready (existing). Drop the antithesis line and the aphorism.
- **Evidence:** slides `loyalty.basic.shopify-plugin`, `loyalty.line-shopify-flow`, `loyalty.basic.shopify-loyalty-widget` (already in the draft).
- **Opens from:** Activate (the push toward KCG's store). **Hands to:** Rocket AI.

## 11 — Rocket AI across KCG Rewards (TOR 9.4)
- **File:** `sections/11-rocket-ai.md` (was `13-rocket-ai.md`) · **Kind:** Summary.
- **Change:** open by saying AI has already appeared throughout — reading receipts (§03), answering the team's questions (§08), deciding per member (§09) — and that this section gathers it: Rocket's AI is one layer that runs under every stage from the same member profile, keeping members moving, not a bolt-on. Keep the stage × role table and the "analysis vs action" paragraph (rewrite any slogan lines). Renumber.
- **Opens from:** Convert. **Hands to:** Services.

## 11a — System integration and data flow
- **File:** `sections/11a-integration.md` — added by a parallel thread (technical pass; notes in `integration-notes.md`). Owned there; round-4 editor only adjusted its opening and one pointer. §01, §03 and §08 point to it.

## 11b — Platform architecture and security (TOR 2.5, 2.6, 14, 18, 19.4, 25.5, 25.10)
- **File:** `sections/11b-architecture-security.md` — added round 5 (founder: "we need a section on high-level architecture and security; pull from Samitivej"). Kind: architecture and security. Owns layers, where data lives, declared limits, TOR 14.1–14.10 row by row. Leaves connections to §11a, AI to §11, SLA numbers to §12 / service-level submission. Samitivej's shape reused; its Kafka / Temporal / ECS stack is not (retired / not ours).
- **Opens from:** §11a. **Hands to:** §12.

## 12 — Services & partnership (TOR 10–13)
- **File:** `sections/12-services.md` (was `14-services.md`) — cross-references and prose sweep (editor pass).

## 13 — Why Rocket
- **File:** `sections/13-why-rocket.md` (was `15-why-rocket.md`) — keep round-3 content; cross-references and prose sweep (editor pass).

## 14 — Why our price looks low
- **File:** `sections/14-pricing-rationale.md` (was `16-pricing-rationale.md`) — keep; cross-references (editor pass).

---

## Editor pass (after 00 is rewritten)
One `proposal-writer` in `Mode: edit` across all section files: openings and hand-offs per the entries above; every cross-reference uses the new numbering and says what it points to; ideas explained twice cut to reminders; slogan cadence rewritten (V9); third person throughout (V1). No fact, scope, marker, graphic or diagram changes.
