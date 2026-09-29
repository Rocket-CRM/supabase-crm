## 08 · Reporting, Dashboard & Customer Insight (Analyze)

Every purchase, point, redemption and LINE tap, from every channel, lands on one member profile. KCG's team reads it back in 14 report dashboards grouped by domain, plus the Home KPI strip, drill-downs by segment, Customer 360, marketing analytics and AI analysis (TOR 1.9, 9.1–9.4).

### KCG's programme on one page (TOR 9.2)

The **Executive overview** puts members, purchases, points and redemptions for any date range on one page, with acquisition, campaign, journey-stage and RFM highlights beneath. Every figure opens the report behind it. The **Home** page opens on the last 30 days: members added, total members, points earned, members who redeemed, and revenue from members.

[asset:mockup;id=loyalty.admin.reports-exec.overview;title=Executive+overview+-+members%2C+purchases%2C+points+and+redemptions+on+one+page]

```rocket-graphic
{"kind": "kv_table", "title": "Where each TOR 9.2 KPI appears", "rows": [
  {"label": "Member Growth", "value": "Home (members added, total members) and the sign-up trend on the Executive overview"},
  {"label": "Active Member", "value": "KCG's definition of active, run as a live segment; count and trend on a dashboard page set up for KCG at implementation"},
  {"label": "Sales · Transaction · Average Spending", "value": "Executive overview and Purchases: net sales, orders and average order value, by channel, store and product"},
  {"label": "Point Earn / Burn", "value": "Executive overview and Points: earned, burned, expired and outstanding"},
  {"label": "Campaign Performance", "value": "Marketing campaigns (return per campaign), mission, survey and journey reports; headline figures on KCG's dashboard page"},
  {"label": "Redemption Rate", "value": "Home (members who redeemed against total members) and per reward in Redemptions"}
]}
```

**Active member is KCG's to define.** A food brand's buying cycle is short, so KCG sets the rule (for example, a purchase in the last 90 days) and we build it as a live segment. A member counts the moment they buy and drops out when they go quiet, so the figure is always current. The same segment is the audience for a win-back journey (§10).

### Report dashboards by domain (TOR 9.1)

Every report TOR 9.1 lists is a standard dashboard, and all 14 work the same way. Pick any period and view it by day, week, month or quarter. Filter before it counts: by channel, store, product or points source. Open any figure to the rows behind it, down to the single purchase and the member who made it. Export with the current filters; large extracts of up to 200,000 rows arrive by email as a download link.

**Members** (TOR 9.1 Member Report, New Member, Active Member). *Members* shows the sign-up trend, age and gender, profile completion, and cohort retention: how each month's new members keep coming back. *Acquisition* shows new members by lead source (an event booth, a marketplace campaign, a LINE link), how many became active, and the revenue each joining cohort produced. *Activity* shows engagement volume by activity type. *Funnels* shows how many members sit at each journey stage KCG defines (§02) and how they move between stages. One member in full, across every domain, is Customer 360 (§02).

**Points and currencies** (Point Earn, Point Burn, Point Balance). *Points* shows points earned, burned and expired over time and by source (purchase, bonus, mission, adjustment), and each month's movement from opening to closing balance, for points and for each ticket type. *Points snapshot* gives the balance and outstanding liability on any chosen date, such as 31 December for year-end. *Wallet and discount reconciliation* serves KCG's finance team.

[asset:mockup;id=loyalty.admin.reports-points.overview;title=Points+-+earned%2C+burned%2C+expired+and+outstanding+liability]

**Tier.** Tier is a condition in every segment, so distribution and movement come from segments rather than a separate report. One segment per tier, compared side by side in the *Audiences* dashboard, shows each tier's size, purchase rate, average order and points balance. A segment such as "moved up to Gold this quarter" tracks movement.

**Redemption** (Reward / Coupon Redemption). *Redemptions* shows redemptions and points burned per reward, success rate and pending fulfilment, and for coupons, redeemed against actually used.

**Transactions** (Transaction, Sales). *Purchases* shows orders, net sales, average order value and buyers by channel, store and product. The channel split is where KCG follows the programme's longer arc: member spend through Shopee, Lazada, TikTok Shop, Modern Trade and Makro PRO against the brand's Flagship Store, event booths and Brand.com, month by month.

[asset:mockup;id=loyalty.admin.reports-transactions.overview;title=Purchases+-+sales%2C+orders+and+average+spend+by+channel%2C+store+and+product]

**Campaign participation** (Campaign Performance). Each mission reports joins, completions and claims; each survey, including event registrations, reports its answers question by question.

**Marketing interaction** (Campaign Performance). Register each marketing campaign (a marketplace mega-sale push, an event, a LINE ad) with its budget and identifiers: voucher code, LINE link, tracked link or UTM. Purchases are attributed to it daily, and *Marketing campaigns* shows the return on each campaign and across all of them. Journey analytics show, step by step, how many members each message reached, what they clicked and where they dropped off (§10).

### Segments and RFM: who to act on (TOR 1.6, 1-P1b)

Reports count members; segments name them. Purchases from every channel build one profile per member, profiles form segments, and segments feed campaigns, automation and AI. A segment is built in four ways:

- **Live rules** on any programme data: profile, purchases (amount, channel, store, SKU), points, tier and tier changes, missions, redemptions, survey answers, check-ins, tags. The segment keeps itself current as members qualify or drop out, or runs as a fixed snapshot when a set list is needed.
- **Uploaded lists**, matched to members by phone, email or member code, for lists from outside the programme.
- **RFM groups.** Every member is scored daily on how recently, how often and how much they buy, and placed in a group such as Champions, At risk or Lost.
- **Tags and personas** that the KCG team or an automation assigns, such as "Frequent buyer" or "Event sign-up".

Each segment gets its own dashboard in *Audiences* (size, purchase rate, average order, points balance), compared side by side with others and drilling into its members. The *RFM* dashboard does the same per RFM group. For a brand that grows on repeat purchase, RFM is the early warning: it shows who is buying less often before they stop.

[asset:mockup;id=loyalty.admin.reports-rfm.overview;title=RFM+-+who+is+buying+often%2C+cooling+off+or+lost]

In KCG's terms:

- Bought on a marketplace twice in six months, never on KCG's own channels: the audience for an own-channel offer.
- Gold, no purchase in 60 days: a win-back audience.
- More than 500 points expiring next month: an expiry reminder.

A segment is built once and used anywhere: a one-off LINE broadcast, a rule-based journey (§10) or an AI decisioning agent (§11), with no list to re-export.

[asset:mockup;id=loyalty.admin.audience.list;title=Audience+builder+-+segments+defined+once%2C+reused+everywhere]

### Data lake (TOR 9.3)

We deliver KCG Rewards data to KCG's data lake as a live stream of member and loyalty events plus scheduled extracts, following the data architecture KCG sets. Format and schedule are agreed with the KCG data team at implementation.

### AI analysis: ask instead of searching (TOR 9.4)

Reports answer the questions someone planned; AI analysis answers today's. The KCG team asks in plain language in the KCG Rewards portal, or connects Rocket's MCP connector (the open standard AI assistants use to reach business systems) to Claude or ChatGPT and asks there, alongside the rest of their work. Either way the AI works under that admin's access: it sees only the data that admin is permitted to see, so the role permissions KCG sets apply to the AI too.

- "Of members who joined in January, how many bought a second time, and through which channel?"
- "How many points expire next month, and which tier holds most of them?"
- "Which rewards do members who first bought on a marketplace redeem most?"

Answers come with a recommendation where one fits. For example (illustrative figures): *"412 Gold members have points expiring in 30 days and haven't bought in 45; send a reminder with a limited-time multiplier."* The recommendation becomes a draft the KCG team reviews and applies. The AI analyses and suggests; it doesn't act on members. Acting on each member is AI decisioning (§11), and §13 shows the two together. AI analysis is offered under TOR 9.4.

[asset:mockup;id=loyalty.admin.ai-analysis.list;title=AI+analysis+-+ask+a+question%2C+get+an+answer+and+a+draft+to+apply]

### From seeing to moving

Everything in this section makes KCG's team faster at seeing who is growing, who is slipping and which channels work. None of it brings a slipping member back. Moving each member, at the moment it counts, is activation (§09).
