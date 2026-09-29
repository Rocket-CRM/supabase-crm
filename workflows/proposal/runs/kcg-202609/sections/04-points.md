## 04 · Earn Logic: KCG Rewards Points

Once §03 has brought a purchase in from a KCG channel, earn logic decides what it is worth to the member. The KCG team sets that logic in the admin portal: the rate, which channels and products earn more, which members get a bonus, and when points post and expire. Any of it can be changed when the business changes, with no development (TOR 4.2, 4.2-P3).

```rocket-graphic
{
  "kind": "flow",
  "groups": [
    {
      "id": "earn",
      "label": "Earn",
      "step": 1,
      "tone": "red"
    },
    {
      "id": "use",
      "label": "Spend, reverse or expire",
      "step": 2,
      "tone": "violet"
    }
  ],
  "nodes": [
    {
      "id": "p",
      "label": "Purchase from any KCG channel",
      "icon": "shopping-bag",
      "tone": "red",
      "group": "earn"
    },
    {
      "id": "c",
      "label": "Conditions checked",
      "detail": "What, where, who and when (Point Earning)",
      "icon": "filter",
      "tone": "red",
      "group": "earn"
    },
    {
      "id": "r",
      "label": "Best qualifying rate + bonus multipliers",
      "detail": "Bonus Point",
      "icon": "percent",
      "tone": "red",
      "group": "earn"
    },
    {
      "id": "h",
      "label": "Optional hold",
      "detail": "Until a chosen order status, or the hold period ends",
      "icon": "hourglass",
      "tone": "red",
      "group": "earn"
    },
    {
      "id": "x",
      "type": "end",
      "label": "Pending points cancelled",
      "icon": "x",
      "tone": "neutral",
      "group": "earn"
    },
    {
      "id": "e",
      "label": "Extra Point",
      "detail": "Missions, surveys, check-in and journeys",
      "icon": "star",
      "tone": "amber"
    },
    {
      "id": "b",
      "label": "One KCG Rewards balance",
      "detail": "Posted as a dated batch",
      "icon": "wallet",
      "tone": "amber"
    },
    {
      "id": "o1",
      "type": "end",
      "label": "Redeemed",
      "detail": "Soonest-expiring points first (Point Redemption)",
      "icon": "gift",
      "tone": "violet",
      "group": "use"
    },
    {
      "id": "o2",
      "type": "end",
      "label": "Reversed on refund",
      "detail": "At the original rates (Point Reversal)",
      "icon": "undo",
      "tone": "violet",
      "group": "use"
    },
    {
      "id": "o3",
      "type": "end",
      "label": "Expired if unspent",
      "detail": "Point Expiration",
      "icon": "clock",
      "tone": "violet",
      "group": "use"
    }
  ],
  "edges": [
    {
      "from": "p",
      "to": "c"
    },
    {
      "from": "c",
      "to": "r"
    },
    {
      "from": "r",
      "to": "h"
    },
    {
      "from": "h",
      "to": "x",
      "label": "Refund during hold"
    },
    {
      "from": "h",
      "to": "b",
      "label": "Hold ends"
    },
    {
      "from": "e",
      "to": "b"
    },
    {
      "from": "b",
      "to": "o1"
    },
    {
      "from": "b",
      "to": "o2"
    },
    {
      "from": "b",
      "to": "o3"
    }
  ]
}
```

### Currency: points, and optional tickets (TOR 4.2-P1, 4.2-P2)

KCG Rewards runs on one point currency, carrying the programme's brand in LINE, in Thai and English. Points are **fungible**: every point is the same, whether it came from the flagship store, a Shopee order or a mission, and it sits in one balance that can be spent on any reward.

**Tickets** are **non-fungible**: each ticket type is its own balance with one purpose, such as entries for a lucky draw or tokens for a spin wheel. They power campaigns without touching points, so a draw doesn't dilute the balance or add to KCG's points liability. The TOR doesn't require tickets, so they are optional: a ticket type is switched on when a campaign needs one (§07).

| | Points | Tickets (optional) |
|---|---|---|
| Balance | One balance for the whole programme | One balance per ticket type |
| Earned from | Purchases on any channel, campaigns, adjustments | The same earn rules and campaigns, per ticket type |
| Used for | Any reward in the catalogue | The campaign the ticket type belongs to (e.g. a lucky draw) |
| Expiry | One programme policy (below) | Set per ticket type, including a fixed end date for an event |

### Point Earning: conditions, then rates (TOR 4.2.a)

An earn rule is a set of conditions plus what the member gets when a purchase meets them. A flat programme is one rule with no conditions; "×2 on the new product, at the flagship store, for Gold members, on weekdays" is the same rule with conditions filled in. Conditions come in four groups, combined freely:

- **What was bought**: category, brand, product or SKU. Include a product line, exclude low-margin or promotional items, or require a minimum (at least 300 THB on the line).
- **Where**: a channel group, a store group or a single store (channel groups below).
- **Who**: tier, persona (a member type KCG defines, such as KCG employees), birth month.
- **When**: start and end date, days of the week, hours of the day.

The member gets a **rate** (spend per point), a **multiplier** on that rate, or a **fixed amount**. When several rates qualify, the member gets the best one, so the team never has to rank rules against each other. Product conditions work on every channel that reports what was bought (POS, marketplace orders, receipts read line by line), with KCG's product list mapped across channels at implementation.

**Basic Earn** covers most programmes on one page: the base rate or one rate per tier, which order statuses earn (a marketplace order only once delivered, a flagship sale once paid), excluded products, and bonus multipliers.

[asset:screenshot;id=5bfe8e90-e1aa-469f-bb6c-c2bfdabb040a;title=Basic Earn — base rate, rate per tier, earning order statuses and bonus multipliers]

**Earn Studio** is the full editor: rates and multipliers grouped into programmes, each linked to its conditions, so a new promotion is added as a new row in the editor with no development.

[asset:screenshot;id=93613659-d0a0-435c-a618-f7f376d910e2;title=Earn Studio — rates and multipliers linked to the conditions that trigger them]

**The rate is KCG's to set** (TOR 4.2-P3): for example 25 THB = 1 point, changed at any time. A change applies to purchases from that moment; points already earned keep their value, and a later refund reverses at the rate that applied when they were earned.

#### Rates by channel group

Channel rates are set on groups rather than on individual shops. At setup, every store, shop and retail chain is placed in a group, for example **Marketplaces** (the six Shopee, Lazada and TikTok Shop shops), **Modern Trade**, **Makro PRO** and **Own channels** (flagship store, event booths, Brand.com, Shopify, LINE orders). An earn rule targets the group, and a shop added to a group later, such as a new marketplace shop or a new booth, earns at that group's rate from its first order without the rule being edited. The same groups filter the reports in §08.

These groups carry the lower third-party rate and the higher own-channel rate that §03 explains as the programme's conversion logic.

### Bonus Point: public and personalised multipliers (TOR 4.2.d)

We read **Bonus Point** as extra points on a purchase, and **Extra Point** as points for something other than a purchase, consistent with "Extra Points from Mission" (TOR 6.2).

A bonus is a multiplier on the points a purchase earns at its rate: ×2 on a new SKU for its launch month, ×3 on weekdays, ×2 at the event booth during a fair, a higher multiplier for each tier (§06). Bonuses come in two kinds:

- **Public**: every member whose purchase meets the conditions gets it.
- **Personalised earn factor**: a rate or multiplier attached to chosen members, with its own validity window. Members who haven't bought in 60 days get ×2 on purchases in the next 14 days; once the window closes, the offer stops and public rules carry on. Rule-based journeys and the AI decisioning agent (§09) assign these to the members they select, so the cost of the bonus is spent only on the members whose buying it is meant to change.

Public and personalised factors are evaluated together: the best rate wins, and KCG chooses whether qualifying multipliers stack or only the highest applies.

### Extra Point (TOR 4.2.e)

Extra points are a fixed amount for an action: a mission, survey, check-in or referral (§07), a welcome or birthday step in a journey, or an offer from the AI decisioning agent (both §09). Each campaign sets its own amount without touching the purchase rules. Bonus and extra points share one balance and one expiry, labelled by source in the member's history.

### Worked example: one basket, two channels

Illustrative settings: Marketplaces, Modern Trade and Makro PRO earn 25 THB = 1 point; Own channels earn 20 THB = 1 point, which is 25% more per baht; the new product earns ×2 for its launch month. A member buys a 500 THB basket with 200 THB of the new product:

| | Flagship store | Shopee |
|---|---|---|
| Best qualifying rate | 20 THB = 1 point | 25 THB = 1 point |
| Base points on 500 THB | 25 | 20 |
| ×2 on 200 THB of the new product | +10 | +8 |
| **Points earned** | **35** | **28** |

The flagship buyer earns 35 points for the basket that earns 28 on Shopee, and the Shopee buyer is still rewarded for the claim that identifies them (§03). The new-product bonus applies on both channels because it is set on the product rather than on a channel.

### When points post

Points post moments after a purchase is recorded, unless the programme delays them. Two controls: the **order status** that earns (above), and a **programme-wide hold** of a set number of minutes or days, optionally posting at a chosen time of day. A refund during the hold cancels the pending points, so there is nothing to reverse. Purchases imported from a daily sales file post when the file arrives (§03). We recommend no hold on Front Line and real-time POS purchases, where seeing points at the counter is part of the reward, with reversal as the safety net; a hold can be added later if return abuse appears.

### Point Reversal and Point Adjustment (TOR 4.2.g, 4.2.c)

**Reversal.** Refunds and cancellations reverse the points that purchase earned, at the rates and bonuses of the original earn; a partial refund reverses the matching share. Each reversal is its own history line, linked to the original purchase. If the member has already spent the points, KCG chooses whether the balance may go below zero or stops at zero, and head office can freeze a member who repeatedly buys, redeems and returns (§02).

**Adjustment.** Authorised staff add or deduct points (or tickets) for one member to correct a missed purchase, recover a service failure or give a goodwill award. Every adjustment requires a reason and is recorded with the staff member, time and reason; a deduction can't exceed the balance. Head office adjusts from Customer 360 (§02), counter staff from Front Line (§03).

### Point Redemption (TOR 4.2.b)

A redemption deducts immediately, uses the soonest-expiring points first, and appears as a redemption line. The catalogue, pricing by tier and controls are in §05.

### Point Expiration (TOR 4.2.f)

Expiry bounds the points liability and gives members a reason to return. KCG chooses one policy:

| Policy | How it works |
|---|---|
| No expiry | Points last until spent |
| Rolling | Each earn lasts a set number of months from its earn date, e.g. 12 |
| Fixed schedule | Points due in a period expire together — annual, half-yearly, quarterly or monthly, aligned to KCG's financial year — with a minimum period so late earners aren't caught out |

Only unspent points expire, and redemptions always use the soonest-expiring first, so active members rarely lose anything. A policy change applies to new earns; existing points keep their dates. Members see the next amount due ("800 points expire 31 Dec") and get a LINE reminder ahead of the date; §09 shows how that date can start a journey that brings the member back to buy.

For a 1 January launch, we recommend annual expiry at financial year-end with a six-month minimum period: points earned in October roll to the following December, and finance closes the liability once a year. The final policy is agreed with the KCG finance team at implementation.

### Point Transaction History (TOR 4.2.h)

Members see in LINE their balance, every movement labelled by source (purchase, bonus, mission, redemption, reversal, adjustment, expiry) and when their points expire (§02). Customer 360 shows staff the same, plus each earned batch with its expiry and what is left of it, so a member's question about where their points went is answered on one screen. Programme totals are in the points report (§08), and §05 turns to what members spend them on.
