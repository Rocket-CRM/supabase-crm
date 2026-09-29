# Proposal scaffolds

A vocabulary for planning and writing sections — what good sections of each kind usually carry, and the lessons earlier runs paid for. **Guidance, not a form.** Nothing here is a quota: no required count of journey references, diagrams, mockups, examples, or words per section. Use a pattern when it helps this customer understand; skip it when it doesn't, and say why at Gate 2 if the skip is surprising.

## Structure of the features part

### Default: the retention journey

Organise member-facing features by the journey in `docs/PRODUCT_MESSAGING.md`: **Join → Earn → Burn → Grow → Campaign → Analyze & Activate → Convert.** Stages are the grouping level; each in-scope capability is its own section (or subsection) inside its stage. Skip stages the deal doesn't touch.

Why: a reader who knows which stage they are in can place every feature, and complex capabilities (automation, AI decisioning) land in context instead of floating. Place the journey once where the features begin, then let the structure carry it — a heading hierarchy that says "Earn" doesn't need every paragraph to repeat it.

Placement lessons (Proposal V12): the member's home (LINE OA) belongs to Join; the "ways to earn" hub opens Earn; lucky draw, spin, check-in are Campaign mechanics, not Rewards; **Activate is one section** — why activation, then audiences (who), targeted broadcasts (one send, a moment you choose), rule-based journeys (always on, the member's behaviour sets the moment), AI decisioning (per-member choice) — not three sibling sections.

Outside the journey, after it: customer service (its own group when in scope), admin portal and reports infrastructure, data ownership, integration, operations and support, delivery.

The journey fits loyalty and CRM scope. For a custom build that isn't a loyalty programme, derive the structure from the tender and Core principles instead.

### When the tender has its own structure

Evaluators score against their own structure, so respect it — but a proposal is also our chance to show clearer thinking. Decide once at Plan and explain the choice at Gate 2:

- **Their structure is clear and well grouped** → follow it. Inside their sections, order content along the journey where it reads naturally.
- **Same shape, different words** → use their term, ours in brackets, in headings and at first mention: "Member registration (Join)". After that, their term alone — brackets on every mention are noise.
- **A flat list, or items mixed across levels** → group their items into journey stages (Core §6–8). Keep each item findable: their wording as a subsection or table row, with its clause ID.
- **Their structure groups on a different axis** (by department, by system) → keep their top level; use the journey within each part where it helps.

Whenever we regroup their items, include a clause coverage matrix (clause → where it's answered) so an evaluator can find anything in seconds.

## Depth

Depth comes from three things: every in-scope capability getting its own treatment, writers opening their reading list before writing, and the dossier pointing at sources instead of summarising them. It does not come from word targets.

The failure this protects against: an earlier run wrote the whole proposal in one pass from a 633-word dossier summary of a 4,519-word brief, and produced a 3.2k-word coverage memo where ~10k was warranted. Collapsing "earn, tiers, redemption" into one section is the same failure at section level.

Primary-deliverable sections go deeper than siblings; the rest is calibrated against them. A thin section is flagged to the parent in the writer's return and logged in `gaps.md` — never with a marker in customer prose (Proposal V6).

Depth is not length. The opposite failure, from a later run: 30k words that walked the TOR clause by clause, re-explained the customer's own business, and repeated the executive summary in the first section — long, but thin on evidence. Depth = distinct facts and visible evidence per page (Proposal V2–V5).

The overcorrection, from the same run's next round: a "~60% of the previous word count" target and "dense, not long" produced slogan cadence and dropped the explanations that carried the argument — the third-party → first-party logic, the order-sync vs plugin difference, whole earn routes. Never set a word-count target on a rewrite. Cut repetition; keep and explain every mechanism (Proposal V9–V11).

**Fit decisions constrain claims, not coverage.** A dossier rule like "no file-import claims" or "keep to what the slide shows" silently deletes a capability from every writer. Write such rules as "claim X only in form Y", and check them against the brief before handing off.

## Section kinds

### Feature section

What a strong one usually does:

- **Why first** — what this capability is for, in the customer's terms (Core §13).
- **The journey or scenario** when sequence is the evidence (Proposal W2): a realistic member, staff, or agent walkthrough in the customer's vocabulary. A diagram placeholder when a flow has branches or actors prose can't carry.
- **What it is** — the configuration model as groups of settings (display, price, eligibility…), not click steps.
- **The Rocket features involved**, by their real names.
- **A mockup** where seeing the screen answers a question faster than prose — member (phone) or admin (tablet).
- **Fit** against their requirements when the tender enumerates them (Proposal S6).

Lessons that still hold:

- **Earn** — conditions (rule types, dimensions, grouping) before rate examples. If the customer calculates earn outside Rocket today, give both paths equal weight: customer-posted pre-calculated points, and Rocket's native earn rules.
- **Rewards** — per-reward limits and reward groups belong in the rewards section, not a sibling.
- **Tiers** — qualification, upgrade/downgrade, and review before any UI.
- **One owner per story** — one earn section owns the member earn narrative; purchase ledger and marketplace ingestion are subsections or cross-references.
- **Customer service** — the walkthrough is a realistic contact scenario for this customer; AI sections show concrete procedures with tool steps and escalation.
- **Join** — name every sign-in channel we support (LINE, phone OTP, Facebook, email…) and state the recommendation: whatever else is offered, require LINE, because it is the channel marketing automation reaches best. Member status means tier plus journey stage first (Proposal V7).
- **Customer 360** — it is first the place to *see* a member: every domain (profile, points, tier, rewards, campaigns, purchases by channel, interactions) with insight and time-series views; the actions an admin can take come second. Show the screen.
- **Earn** — introduce currency before rules: points are fungible (one balance, spent in any amount); tickets are non-fungible entries used for campaigns such as lucky draws. Name personalised earn factors (multipliers by tier, persona, product, channel, time) when describing bonus points. Receipt upload covers manual approval and optional auto-approval with its configurations. When the deal includes Shopify or an own web store, it is a headline earn channel with its own slides, not a line in a list.
- **Reports** — group by domain (members, points and currencies, tier, redemption, transactions, campaign participation, marketing-campaign interaction), with named examples and screens for each; state the true count of reports and views.
- **Analyze vs Activate** — two different jobs: Analyze tells you what is happening and to whom; Activate changes what happens next. Say so explicitly where the two meet, and carry the "customers don't move along the journey on their own" argument (the Newton slide) in the activation section.
- **AI decisioning** — open with the limits of rule-based journeys (they optimise for the average member and assume a fixed path), then why per-member decisioning answers them. The rule-based section ends on the same limits so the hand-off is explicit.

### Other kinds

- **Vocabulary alignment** (early; Proposal S1, U1–U2): their term → what we configure. Call out when one of their words hides two platform patterns.
- **Data ownership**: one place — each data domain, its master system, consumers, sync direction — with the customer's real system names. Referenced elsewhere, not repeated (Proposal S4).
- **Reward sourcing** (when rewards are in scope): the reward strategy for this customer's members first; then inventory model vs fulfilment channel (never conflated), coverage and timelines as commercial targets, and exception handling.
- **Admin portal and reports**: a catalogue of configuration areas and named reports in scope — not walkthroughs. A domain without its named reports says nothing.
- **Additional features**: licensed but not configured for go-live — breadth, so nothing in scope is silently dropped.
- **Integration**: the only home for wire-level detail — systems, direction, data, mechanism — with a subsection per real external contract. **Cost follows who moves the data:** the customer's system pushes to us (Open API, emailed files, a file uploaded in the admin portal) — no charge; we build and run a connector that pulls from their system or posts into it (an ERP such as SAP, a POS we read at end of day) — custom integration, one-time build plus monthly maintenance, on the commercial proposal's Custom Integration line. Never write "None" for a connector we build. For an ERP, assume we pull product master and post the programme's major activity (transactions, points movements, redemptions). For POS, say integration differs by the customer's needs and the POS's readiness, list every route (email file, upload, Open API, our connector, the staff app), and show that together they cover any POS.
- **Architecture and security** (when the tender asks for system architecture or security — TOR items like "System Architecture", "Data Security / PDPA", ISO certificates): the layers at evaluator level (channels, API, loyalty core, event processing, analytics, outbound), where data lives, declared limits, and one row per security topic the tender lists. Never reuse an older proposal's stack names without checking them against `requirements/architecture/System_Map.md` and `CRM_Event_Driven_Architecture.md`; never claim a certificate the founder hasn't confirmed.
- **Operations and support**: SLA, severity, and governance, with this customer's operational specifics woven in, not appended.
- **Delivery and timeline**: phases, dependencies, and milestones. Tender delivery dates are sovereign.
- **Executive summary** (written last, compiled first): opens with a `pillar_matrix` objectives grid — 3–4 rows, each an objective (with its TOR tag) and 1–3 short bullets for current state, future state and business impact, impact bullets led by ▲ or ▼ (the Samitivej objectives slide; § Visuals). Current-state bullets stay neutral and come from what the TOR says, not from our guesses about the customer's operations — then one paragraph per objective in the same order, led by the pillar's name, then the Why Rocket summary (the differentiators in a few lines each, pointing to the full sections). A reader who stops here knows what they get and why us. It summarises; it introduces nothing new. It does not narrate the customer's situation back to them beyond the matrix's current-state column (Proposal V2).
- **Understanding / overview** (optional): only when it carries something the executive summary doesn't — typically the journey map (stage → what the member does → TOR areas → section) and, for regrouped tenders, the coverage map. Never a longer re-telling of the summary or of the customer's objectives (Proposal V3).
- **Pricing rationale** (when price will look low next to competitors): why the price is what it is — the commercial philosophy, not the price list. One home; Why Rocket summarises and points to it.
- **Clause coverage matrix**: when a tender or numbered requirement list exists — every clause, verbatim, with where it is answered.

## Reading map

Writers open these **before** drafting. The outline's `reads` narrows them to exact headings.

**Requirement docs.** Grep `requirements/domains/_index.md` for the customer's terms to find the authoritative `requirements/<Domain>.md` (if the index is absent, list `requirements/*.md`). Read **Concept** and **Journeys** closely, **Rules** for the constraints a claim depends on, **System** only when the section needs it (integration, data, security). Requirement docs name tables and functions; use them to confirm behaviour, never repeat them to the customer.

**Narrative** (`docs/PRODUCT_NARRATIVE.md`) for customer-facing framing. Two layers:

- **Summary layer** — each `##` module's intro and each capability's **Overview** and **Purpose** (newer sections: **What it enables**). `bash .cursor/skills/proposal/narrative-overview.sh` prints all of it (~6k words). The parent reads it whole before planning; writers read the module intro and their own capabilities' summaries first, since that's where a section's opening idea usually comes from.
- **Full sections** — journeys, configuration, edge cases. Locate with `rg -n "^### <Anchor>"`, read to the next `###`. Configuration tables carry field and enum names; use them to understand, never repeat them to the customer.

Anchors by stage:

| Stage / area | Narrative anchors |
|---|---|
| Join | `Authentication & Signup` · `Forms` · `PDPA Consent` · `Tags & Personas` |
| Earn | `Currency` · `Purchase Transactions` · `Activity-Based Earning` · `Store & Partner Classification` |
| Burn | `Rewards` · `Packages` · `Stored Value Cards` |
| Grow | `Tiers` · `Persona Entitlements` |
| Campaign | `Missions` · `Spin Wheel` · `Mass Lucky Draw` · `Referral` · `Check-in` |
| Analyze & Activate | `Reports — What the Brand Sees Back` · `AMP Workflows` · `AMP AI Decisioning` · `AMP AI Analysis & Recommendations` |
| Customer service | `Connectivity` · `Agent Workspace` · `Ticket Management` · `Rules-Based Automation` · `CS AI` · `Knowledge Base` · `Actions & Integrations` · `CSAT & Customer Feedback` · `Analytics & Logs` |
| Admin, localisation | `Admin Portal — Configuration Surfaces` · `Translation System` |

Convert (Shopify, unified points) is framed in `PRODUCT_MESSAGING.md`; facts in the Shopify requirement doc.

## Visuals

- **Diagrams: two types only.** Node diagrams (stages, branches, decisions, hub maps) are `flow` rocket-graphics in the Rocket Slide brand style; actors exchanging messages over time are Mermaid `sequenceDiagram`. No Mermaid `flowchart`. Worth one when a journey, a logic branch, or a process across actors is clearer drawn than written. Keep node counts low; label in the customer's vocabulary. A diagram that carries unique meaning (a branch, an ownership boundary) is content — never cut it without moving that meaning into prose.

  Diagrams are decided and drawn after the prose, by agents that see the whole document. Writers mark where one would help, on its own line:

  `[DIAGRAM: <what it must show — actors, steps, branches> | <why a drawing beats prose here>]`

  The diagram planner then keeps, changes, or drops each placeholder and adds any that are missing; the diagrammer draws the survivors. Writers never draw diagrams themselves, and prose around a placeholder should read fine whether or not a diagram ends up there.
- **Diagrams fit an A4 portrait page.** The viewer exports to PDF. A `sequenceDiagram` stays at ≤ 4 participants and ≤ ~10 messages with short labels; loops and alt blocks nest at most once. A `flow` stays at ≤ ~12 nodes (hard cap 14). Bigger than that is two diagrams, or a `flow` instead of a sequence.
- **Visual evidence, in order of preference** (Proposal V5). Every scored capability should have one.
  1. **The customer's pitch deck.** Most deals have a customised pitch in rocket-deck with the customer's own images. Find it at intake (`dossier.md` records the slug); never default to the library when a pitch exists.
  2. **Whole slides as screenshots.** A single phone mockup wastes the page width; a whole landscape slide fills it at the same height and carries the slide's framing. Capture the pitch's slides (deck page `https://workspace.rocketcrm.io/pitch/<slug>`, arrow-key navigation, 1600×900 @2x), upload them (below), and embed as screenshots.
  3. **Real admin screens** from the demo merchant in the loyalty admin portal (Customer 360, reports, earn rules, workflow canvas, AI agent builder…), as live embeds: `[asset:mockup;id=loyalty.admin.<id>;title=<caption>]`. The embed is the real portal, so it never goes stale and needs no capture step. Writers never wait on screenshots for admin evidence. If a page renders cropped, that is a viewer fix (render at desktop width, scale to fit) — log it, don't route around it with captures.
  4. **Library mockups** — last resort.
- **Uploading screenshots.** `POST https://workspace.rocketcrm.io/api/internal-proposal/assets` (multipart: `file`, `title`, `description`; header `x-internal-proposal-token`). The returned id embeds as `[asset:screenshot;id=<uuid>;title=<caption>]`. The viewer prints the stored `description` as the italic caption under the image (unless the marker sets `desc=`), so upload with an empty or customer-ready description — never notes to ourselves (slide ids, pitch slugs, "sell X as…"); those belong in `research/assets*.md`. `GET …/assets` lists the library; check it before capturing something that may already exist. Record every asset used by a run in `research/assets.md`.
- **Live mockups** (when a live, animated member screen is wanted): `[asset:mockup;id=<mockupId>;pitch=<pitchSlug>;title=<caption>]` from `slides.json`. `pitch=` shows the pitch's uploaded customer images; without it you get library defaults. Admin mockup ids (`loyalty.admin.*`) embed the live demo-merchant portal (item 3 above). URL-encode caption spaces as `+`. Take the slide's copy as input and re-express it — don't paste slide text.
- **Diagram slides**: `[asset:fixed_diagram;slide=<slideId>]` works **only** for slides whose library entry has a `diagram` field; anything else renders an error box. Screenshot the slide instead.
- **Rocket graphics**: fenced ` ```rocket-graphic ` JSON blocks the viewer renders natively and flat (square corners, no background panel behind any diagram; colour fills only in `pillar_matrix` and flow zones), e.g. `{"kind": "kv_table", "title": "…", "rows": [{"label": "…", "value": "…"}]}` — the key is `kind` (not `type`); `title` optional. Kinds: `flow` (brand-style node diagram: `nodes` of `id` / `label` ≤ 80 chars / optional `detail` ≤ 110, `type` step·decision·end·note, `icon`, `tone` red·amber·violet·blue·green·neutral, `group`; `edges` of `from` / `to` / optional `label`, `dashed`; optional `groups` (≤ 4) of `id` / `label` / `step` / `tone` drawn as tinted numbered zones; optional `direction` down·right, right falling back to down when too wide; with `direction: "right"` add `zone_direction: "down"` when a long chain runs through zones — zones then sit left to right with their steps stacked, which fits the page where a plain left-to-right chain of more than ~4 steps would not; ≤ 14 nodes, ≤ 20 edges; icons from `FLOW_ICONS` in rocket-deck `internal-proposal/lib/rocket-graphic-kinds.ts`) — every node diagram; `pillar_cards` (2–4 `pillars` of `label` / `summary` / optional `tag`; optional `stats` of `value` / `label`, ≤ 5; optional `subtitle`) — the executive-summary pillars; `flow_columns` (2–5 `columns` of `label` / `items[]` of `title` + optional `detail` (≤ 6) / optional `emphasis: true` on one column; optional `subtitle`, `footer`) — a channels-to-analysis overview; `pillar_matrix` (2–4 pillars, each `objective` plus `current` / `future` / `impact` string arrays of 1–3 bullets; an impact bullet may start with ▲ or ▼) — the executive-summary objectives grid; `kv_table` (`rows` of `label` / `value`), `numbered_steps` (`steps` of `title` / `description`), `horizontal_stepper` (`steps` of `label` / `sublabel` / `accent`), `milestone_timeline` (`milestones` of `label` / `description`), `tier_stack` (`tiers` of `level` / `label` / `threshold` / `benefits[]` / `accent`; `level` is a string, e.g. `"1"`). Accents: primary, secondary, neutral, warm, bronze, silver, gold, platinum. Use `flow` for diagrams and the rest for structured content that isn't a flow — the executive summary's pillars above all. Write item text as plain phrases, not `·`-joined fragments.
- **Check the render.** After publishing, open the viewer page and look at every visual: broken markers, error boxes, cropped or zoomed mockups, and diagrams too wide for A4 are findings for the next round.

## Sources-only mode (custom and government bids)

Facts come only from `sources/` and human answers — no product catalogue claims beyond what the bid needs. In addition to the above:

- Depth follows the tender's spine — uneven on purpose (Proposal W13b). Official voice for government packs (W13c): propose to the buyer; no echoing the TOR back, no document choreography.
- Tender text appears verbatim in matrices and in-body requirement quotes.
- Hosting, environment, operations ownership, and delivery dates come from the pack. Don't impose Rocket's SaaS architecture on a buyer-installed system without a reason recorded in the dossier.
- Architecture, system design, and data models are fine — required, even — when the tender asks for them.
- Payment percentages stay out of technical prose.
- Submission documents the workflow doesn't write (bank letters, signed forms, certificates) are listed with an owner in the dossier, not drafted.
