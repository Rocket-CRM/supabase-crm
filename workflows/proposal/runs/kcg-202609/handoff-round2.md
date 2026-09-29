# Round 2 — common handoff (all writers)

- **Run folder:** `workflows/proposal/runs/kcg-202609/`
- **Mode:** catalog · **Language:** en · **Pitch:** `kcg-loyalty-crm`
- **Task:** rewrite your section from scratch against round-2 feedback. The current file is a draft to mine for correct facts, not a base to polish.
- **Read first, in order:**
  1. `sources/review-1.md` (founder feedback, verbatim)
  2. `dossier.md` — § Round 2 decisions, § Brief checklist (items owned by your section are mandatory), § Fit decisions
  3. `outline.md` — header block + your entry
  4. `Writing Principles/PROPOSAL_WRITING_PRINCIPLES.md` § Section 5 (V1–V8) and the checklist
  5. `.cursor/skills/proposal/SCAFFOLDS.md` — your kind + § Visuals
  6. `research/assets-slides.md` — whole KCG slides (view PNGs at `/tmp/cap/slides/NN-<slideId>.png` before choosing; read the slide text so your prose doesn't just repeat it)
  7. `research/product.md` your §, `research/sources.md` your TOR clauses, CRM Knowledge MCP (`search_docs`, `get_section`) for anything you state as a capability
- **Siblings (one owner per idea — reference, don't re-explain):** 00 exec summary · 01 journey map · 02 Join (login, status, Customer 360) · 03 Earn channels (incl. receipt approval, Shopify as earn) · 04 Earn Logic (currency, rules, bonus) · 05 Rewards · 06 Tier · 07 Campaigns · 08 Analyze (reports by domain, AI analysis) · 09 Activation (Newton) · 10 Rule-based automation (ends on limits) · 11 AI decisioning (opens on pain points) · 12 Shopify plugin (deep) · 13 Rocket AI summary · 14 Services · 15 Why Rocket · 16 Why our price looks low
- **Angle:** own the customers who buy through channels you don't own, engage them, trigger repurchase — increasingly on your own channels. Never state this as an analysis of KCG; it is the spine, not a paragraph.

## Non-negotiables
- Voice: we → you. No "KCG wants/needs", no "The TOR asks that". TOR tags only as "(TOR 4.2.1)".
- Dense: ~60% of round-1 length for the same scope, more evidence. Every paragraph carries a capability, a decision, or evidence.
- Evidence beside claims: whole slides first (`[asset:screenshot;id=…;title=…]` from `research/assets-slides.md`), then library screenshots named in your handoff, then `rocket-graphic` blocks and `[DIAGRAM: …]` hints (A4-fit). A live member-screen `[asset:mockup;…]` only if nothing else covers it, with `pitch=kcg-loyalty-crm`. **Admin screens are live embeds of the real demo-merchant portal:** `[asset:mockup;id=loyalty.admin.<id>;title=…]` (ids in `research/mockups.md`) — use them wherever an admin screen is the evidence; don't wait for screenshots. **No** `[asset:fixed_diagram;…]`. Remove every such marker from the old draft.
- Screenshot `title=` is the caption the customer sees — write it customer-facing (no "KCG slide —" prefix). Keep the id exact.
- Nothing internal: no `[GAP…]`, no notes to Rocket, no "to be confirmed by Rocket". Use the sendable defaults in `gaps.md`; report open facts in your return.
- Don't name tables, functions, RPCs, queues or internal services.

## Return
Path; word count; brief-checklist items you covered; open facts for `gaps.md`; claims softened/dropped. A few lines.
