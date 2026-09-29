# Round 3 — founder fixes (all writers)

- **Run folder:** `workflows/proposal/runs/kcg-202609/` (repo root `/Users/rangwan/rocket/supabase-crm`).
- **Task:** an edit, not a rewrite. Keep structure, claims, numbers, asset markers and diagrams unless a rule below changes them.

## 1. Voice: KCG in the third person (every section)

The founder does not want the customer addressed as "you" / "your". Rewrite every "you", "your", "yours", "yourself" that means KCG.

- "Most of your customers buy KCG through channels you don't own" → "Most of KCG's customers buy through channels KCG doesn't own".
- "your team" → "KCG's team" / "the KCG team"; "your LINE OA" → "KCG's LINE OA"; "your own channels" → "KCG's own channels"; "you set" → "KCG sets" / "KCG's team sets"; "for you" → "for KCG".
- Don't hammer "KCG's" into every clause. Vary with "the KCG team", "the brand", "KCG Rewards", or restructure the sentence so no possessive is needed ("Members join in the LINE OA…").
- "We" / "our" stay: that is Rocket.
- "You" addressed to a member inside a quoted member-facing message (e.g. a LINE message text) is fine; leave it.
- Apply the same rule to Mermaid labels, `rocket-graphic` JSON strings, table cells and asset `title=` captions.
- Headings too: "Your programme on one page" → "KCG's programme on one page"; "Brand.com today, Shopify when you're ready" → "Brand.com today, Shopify when KCG is ready".

## 2. Decisions that change prose

- **Shopify tier checkout benefit is available.** Slides show "Gold tier free shipping + 5% off every order". State it as a live plugin capability: tiers can carry automatic checkout benefits on the Shopify store, e.g. Gold members get free shipping and 5% off every order. Keep tier-only rewards and tier earn/burn rates alongside it. Don't hedge it.
- **POS sales-file import is included in the licence.** A POS that can only export reports hands over its sales file and our team imports it, included in the licence. Pulling bills from a POS that can't send them stays a separate integration scoped with the POS vendor.
- **Capacity (TOR 3.3).** Sendable line: "Order processing is designed for 10,000 orders an hour and scales out beyond that. KCG's 100,000+ orders a month average around 140 an hour, so even an 11.11 peak many times a normal day stays well inside it." Use it where capacity / order volume / peaks are discussed (§03 "Connections and volume" at minimum) instead of deferring capacity to "the technical proposal".
- **Customer count:** "100+ key accounts". Never "500+ brands".
- **Rocket intro:** the About Rocket, MarTech Report 2025 and events slides now live in a new intro section `00a-about-rocket.md` (written by the parent). Don't reference "§15 Rocket at a glance".

## 3. Diagrams

- Mermaid: no rounded nodes. Use `A[label]` rectangles and `{…}` for decisions only; no `(…)`, `([…])`, `((…))`. Keep node ids, edges and wording (apart from the voice rule).
- Don't add new diagrams.

## 4. Return

One line per file: what changed beyond the voice pass, and any sentence you couldn't make read naturally in the third person.
