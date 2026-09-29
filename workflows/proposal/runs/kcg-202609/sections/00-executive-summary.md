## Executive summary

Most of KCG's customers buy through channels KCG doesn't own. KCG Rewards turns each of those buyers into a member KCG knows, and then moves more of their repeat purchases to KCG's own channels: purchases on the marketplaces, Makro PRO and in Modern Trade earn at a lower rate, because those channels leave KCG a thin margin, while KCG's own channels keep the full margin and earn at a better rate, into the same balance (§03). The KCG team runs the programme from one admin portal, inside KCG's LINE Official Account, from go-live on 1 January 2027.

```rocket-graphic
{
  "kind": "pillar_matrix",
  "pillars": [
    {
      "objective": "One member profile across every channel (TOR 1.1, 1.8)",
      "current": [
        "Buyers on the marketplaces, Makro PRO and in Modern Trade are not known to KCG",
        "Each channel's sales sit in its own system"
      ],
      "future": [
        "All ten channels earn into one member profile in KCG's LINE OA",
        "Order claims and receipt uploads identify third-party buyers"
      ],
      "impact": [
        "▲ Share of sales linked to a known member",
        "▲ First-party customer data KCG owns"
      ]
    },
    {
      "objective": "Repeat purchases on KCG's own channels (TOR 1.4, 1.10)",
      "current": [
        "Repeat orders return to the channel of the first purchase",
        "Nothing makes buying direct more rewarding"
      ],
      "future": [
        "Own channels earn more points, into the same balance",
        "The balance is shown and spent at checkout on KCG's store"
      ],
      "impact": [
        "▲ Share of repeat orders on own channels",
        "▼ Commission and retailer margin on repeat orders"
      ]
    },
    {
      "objective": "Points, rewards, tiers and campaigns (TOR 1.3, 1.5, 1.7)",
      "current": [
        "A new campaign mechanic needs development work",
        "No shared currency or tiers across channels"
      ],
      "future": [
        "One point currency, one reward catalogue and tiers",
        "The KCG team builds campaigns in the admin portal"
      ],
      "impact": [
        "▲ Purchase frequency and lifetime value",
        "▼ Time and cost to launch a campaign"
      ]
    },
    {
      "objective": "Reports and activation for each member (TOR 1.6, 1.9, 9)",
      "current": [
        "Customer behaviour is hard to see across channels",
        "Messages go to broad lists, set up by hand"
      ],
      "future": [
        "14 dashboards, segments, RFM and AI analysis",
        "Journeys and AI decisioning on LINE and SMS"
      ],
      "impact": [
        "▲ Campaign conversion",
        "▼ Manual marketing work"
      ]
    }
  ]
}
```

**One member profile across every channel (TOR 1.1, 1.8, 4.1, 7).** Members join in KCG's LINE OA with LINE Login and a verified mobile number, and the LINE OA stays their home for their balance, coupons and every way to earn. Facebook and email sign-in can be added; we recommend always requiring LINE, the channel marketing automation reaches best. KCG's current LINE members are imported before go-live with their points balance (§02). All ten TOR 7 channels then earn into one purchase history (§03). Rocket's Shopee, Lazada and TikTok Shop connections are native and live today, so the six shops connect from the admin portal with no integration cost, and buyers claim with their order number. Makro PRO is its own channel: we build its order connection free of charge where Makro PRO offers one, and otherwise its buyers upload the receipt. Modern Trade receipts are read by AI and approved by a reviewer by default, from the KCG team or Rocket's Receipt Approval service, or on the spot once KCG switches auto approval on. Our POS routes cover any POS: for the flagship store we recommend the routine daily sales file, emailed to KCG Rewards with no integration work from KCG or the POS vendor, and the Front Line staff app for event booths; §11a sets out every route and its cost. Brand.com, Shopify and LINE orders earn with no claim step.

**Move repeat purchases to KCG's own channels (TOR 1.4, 1.10, 7.4, 7.10).** The earn rate is the main lever. KCG sets rates on channel groups, for example an illustrative 25 THB = 1 point on Marketplaces, Modern Trade and Makro PRO and 20 THB = 1 point on Own channels, which is 25% more per baht; a new shop or booth earns at its group's rate from its first order (§04). Because every purchase lands in one balance, a member claiming a Shopee order sees on the Ways to earn sheet that KCG's own store earns more (§03), and the own-channel nudge journey or an AI agent picks the moment to tell them, with a coupon for a first order there (§09). On KCG's online store, order sync, which is how Brand.com earns through our Open API, covers earning only. Rocket's Shopify plugin also shows the member's balance and each product's points inside the store, lets them spend points and rewards at checkout, and rewards them for referring friends, so the balance built on Shopee and at Lotus's can be used on the store where KCG wants the next order placed (§10). The Purchases report shows member spend on third-party channels against KCG's own, month by month, so the KCG team can see the shift as it happens (§08).

**Points, rewards, tiers and campaigns (TOR 1.3, 1.5, 1.7).** One point currency is earned on any channel and spent on any reward, with optional tickets for campaigns such as lucky draws; KCG sets the conditions, the rates, and public or personalised multipliers for chosen members (§04). One catalogue holds e-coupons, merchandise and extra points, each reward with its own audience, dates, limits and tier-based points price (§05). Each tier programme measures one thing KCG chooses. We recommend points over a rolling 12 months, so members who buy on KCG's own channels also climb faster, and each tier earns more, pays fewer points for selected rewards and gets its own campaigns (§06). The KCG team builds Welcome, Up-Tier and Birth Month coupons, spending missions, Friend Get Friend, surveys, lucky draws, spin wheels, daily check-in and leaderboards in the admin portal, with no development per campaign (TOR 5-P1, §07).

**Reports and activation for each member (TOR 1.6, 1.9, 9).** Analyze shows the KCG team who has stopped where: an executive overview and 14 report dashboards grouped by domain, segments and RFM, a live feed to KCG's data lake, and AI analysis in the portal or in Claude or ChatGPT, limited to what each admin may see (§08). Activate moves those members on, in four layers (§09). Audiences are built once from any programme data and reused by every activation tool. A targeted LINE broadcast sends one message to an audience on a date the team picks, including invitations to LINE friends who aren't members yet. A rule-based journey, in the core scope, runs continuously: each member enters when their own trigger happens, and the journey waits, checks what they bought and which button they tapped, and sends the next LINE or SMS message or benefit. AI decisioning, offered under TOR 9.4, gives every member the attention of an expert marketer: within the goal, actions and guardrails KCG sets, it decides for each member whether to act, wait or skip. On our estimates across customers, brands that pair their programme with activation see over 50% higher member engagement and conversion to next purchase than brands that run the programme alone. Receipt reading, AI analysis and AI decisioning work from the same member profile, and §11 shows how they fit together as one AI layer.

### Why Rocket, in brief

```rocket-graphic
{
  "kind": "kv_table",
  "rows": [
    { "label": "Everything on one platform", "value": "One of the only B2C CRMs with loyalty, mini CDP, marketing automation, AI and an e-commerce plugin on one member profile and one balance, so a buyer KCG first meets on Shopee stays one member through to a repeat purchase on KCG's own store (§13)." },
    { "label": "Thailand's only Shopify-native loyalty plugin", "value": "Live today on the Shopify App Store and ready the day KCG's store opens, on the members and balances KCG already runs in LINE (§10)." },
    { "label": "AI decisioning for each member", "value": "One of only a few loyalty and B2C CRM companies in the world running AI decisioning for mass-market marketing: the agent decides for each member whether to act, wait or skip, within KCG's guardrails (§09, §11)." },
    { "label": "Built for national-scale peaks", "value": "A claim, receipt or purchase updates points, tier and missions as it happens. Order processing is designed for 10,000 orders an hour; KCG's 100,000+ orders a month average around 140 an hour, so an 11.11 peak stays well inside it (§03, §13)." },
    { "label": "A team that knows KCG's programme", "value": "Two dedicated customer success staff, a loyalty strategist, committed service levels and regular campaign graphics at no charge, plus four optional services: platform management, receipt approval, loyalty consultation and partner rewards (TOR 10–13, §12)." },
    { "label": "Lower cost, passed on", "value": "AI has made software cheaper to build and run. We pass that saving to KCG in the price instead of keeping it as margin (§14)." }
  ]
}
```
