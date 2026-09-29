# Product Messaging

How Rocket explains itself: the story, the retention journey that organises every feature, and the lens we use internally to decide emphasis.

**Internal document.** Two layers:

- **Expression** — lines and explanations we can adapt for customers. Always re-express them in the customer's situation and vocabulary; never paste them.
- **Lens** — frameworks for our own understanding (StoryBrand roles, the "villain"). They decide what to emphasise. They never appear in customer-facing writing, not even paraphrased as a framework.

Product facts live in `requirements/` and `docs/PRODUCT_NARRATIVE.md`. This file says how to frame them, not what exists.

---

## The story (expression)

**Tagline:** Stop selling to strangers. *(Marketing surfaces. Rarely right for a proposal's register.)*

**Pain:** You make the sale. Someone else keeps the customer.

Third-party channels — marketplaces, retail chains, offline resellers — keep the customer relationship. The brand knows what it sold, not who bought it. It cannot reach those buyers again, and ends up paying for ads to win back people who already chose it.

**Solution:** Turn every buyer into your own customer — from third-party buyer to direct relationship.

**Impact:** Lower risk, higher margins, and control over the brand's own growth instead of dependence on platforms.

### Four pillars

| Pillar | What it means | Journey stages |
|---|---|---|
| **Connect** | A direct relationship with every buyer, wherever they purchase, through an omnichannel loyalty programme | Join, Earn |
| **Engage** | Keep members coming back with points, rewards, tiers, and campaigns | Burn, Grow, Campaign |
| **Activate** | Personalised offers so the next purchase happens on the brand's own store | Analyze & Activate |
| **Convert** | Repeat purchase on the brand's highest-margin channel | Convert |

Pillars are the one-breath version for executive summaries and introductions. The journey below is how features are organised and explained.

---

## The retention journey (expression)

**Retention, not acquisition.** Acquisition — ads, marketplace campaigns, live selling — gets the first purchase and is not our domain. Rocket starts after it: the brand gets to know that customer, brings them back, and moves repeat purchase to the brand's highest-value channel (for example, first purchase on Shopee, repeat purchase on the brand's own online store).

Every feature sits in one stage. Present the journey before feature detail, then place each feature in its stage — the audience always knows where they are.

Stage names: proposals use **Campaign** for the fifth stage; slides call it **Return**.

| Stage | What happens |
|---|---|
| **Join** | The customer discovers the programme and becomes a member |
| **Earn** | The customer collects points from every channel they buy through |
| **Burn** | The customer redeems points for something they want |
| **Grow** | Members who buy and engage more reach higher tiers with better privileges |
| **Campaign** | Something new to play gives members a reason to come back |
| **Analyze & Activate** | The brand learns from the data (passive) and acts on it per customer (active) |
| **Convert** | Repeat purchase moves to the brand's own store |

Which capabilities sit in each stage, and what they do, is product fact: `docs/PRODUCT_NARRATIVE.md` (start with each capability's Overview and Purpose) and `requirements/`. The proposal skill's `SCAFFOLDS.md` maps stages to narrative anchors.

**Earn is omnichannel** — online or offline, through a third party or the brand's own channel: marketplace orders, retail receipts or product codes, the brand's online store, and its own shops. Every channel counts toward one relationship.

**Necessary but not sufficient.** Join, Earn, Burn, and Grow are the basics every programme has. On their own they are undifferentiated and dull — members buy once or twice, redeem once or twice, and drift away. Campaigns give them a reason to come back.

**What the brand gets:** more repeat purchase, because every stage is a hook to buy again — and data. A buyer who used to be an anonymous third-party sale now has a profile: what they bought, where, how much, their points, redemptions, tier, and campaigns played.

**Analyze vs Activate.** Analysis is passive: dashboards and insight that inform strategy. Activation is active: using data, or a change in it, to send an action to one customer — a personal offer, bonus points, a survey nudge. Most activation drives repeat purchase.

**Where they buy again.** Repeat purchase on a marketplace is good; repeat purchase on the brand's own store is better — no rising platform fees, higher margin. Rocket is **the only loyalty platform in Thailand with a native Shopify plugin**. Points are unified across channels: a member who earned on Shopee can redeem for a discount on the brand's Shopify store, and the brand can set a better earn rate there.

### AI: not just analyse — act

Most AI in the market answers questions about data. Rocket does that too, but its AI also **acts**.

- **Rule-based marketing automation** sends an action when a customer meets set conditions — for example, "spent over 5,000 THB in the last 12 months and hasn't bought in 2 months → send a win-back offer." It is deterministic: a customer who spent 4,900 THB and has been gone for 3 months also deserves that offer, and the rule will never send it. Covering every real behaviour would take endless rules.
- **AI decisioning** works the way an expert marketer would. The brand sets a **goal** (e.g. repeat purchase), the **actions** available (vouchers, point multipliers, messages), and **guardrails** (e.g. at most one message per person per month, discounts capped at 20%, a monthly budget). On every customer event the agent decides whether to act and what to send — usually it waits — working across the whole customer lifecycle with that customer's profile and history. An expert marketer for every customer, at mass-market scale.

**Why acting matters.** Brands design beautiful journeys, and customers don't follow them: they sign up and never earn, earn and never redeem, redeem once and never return, miss the campaign, ignore the new store. People stay at rest unless something pushes them (Newton's first law). Automation and AI decisioning are that push — the fabric connecting every stage, not a feature bolted on top.

### The short version

Join, Earn, Burn, and Grow are the basics, and the basics aren't enough — so Campaigns give members a reason to return. That creates data, which the brand analyses and activates to bring customers back to its own store. The brand goes from knowing what it sold to knowing who bought it — and bringing them back on its highest-margin channel. None of it happens by itself; AI that acts is what moves customers from stage to stage.

---

## The lens (internal only)

StoryBrand framing, for deciding emphasis:

- **Hero:** the brand. **Guide:** Rocket. **Villain:** third-party channels.
- **Problem** — external: thousands of buyers, zero relationships. Internal: built like a brand, treated like a supplier. Philosophical: brands are built on relationships, not receipts.
- **Cost of doing nothing:** staying at the mercy of platforms.

In customer writing, the brand's success is the subject, not Rocket. No framework names, no hero/villain/guide language, no "treated like a supplier."

---

## Adapting to the customer

Start from the customer's channel mix, goals, and pains, then pick what matters. The story bends to their situation; they are never told what their situation should be.

- **Marketplace-heavy, with an own store:** marketplaces are where customers are won; the programme turns those buyers into known members and moves repeat purchase to the own store. Marketplaces are an acquisition channel, not an enemy.
- **No own store yet:** the value is knowing the customer and bringing them back — repeat purchase on marketplaces counts. An own store is a later option, not a precondition.
- **Retail or offline-heavy:** the same relationship logic through receipts, product QR, and POS.
- **The customer depends on a third party** (a retailer is the buyer, or the programme runs inside a partner's channel): drop the channel tension; the story is about members and repeat purchase.
- **Non-commercial or government:** retention and margin may not apply at all. Translate to their objective (participation, service uptake, engagement) or leave the story out.

Use one pillar or the whole arc — whatever the customer's brief makes relevant.
