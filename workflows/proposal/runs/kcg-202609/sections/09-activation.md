## 09 · Activation: marketing automation and AI decisioning (Activate)

§08 shows the KCG team who has stopped where in the programme. This section covers how KCG Rewards moves each of those members on, automatically and one member at a time. It is the part of the programme that turns sign-ups and balances into purchase frequency and lifetime value (TOR 1.3, 1.4).

### What activation does in KCG Rewards

The features in §02–07 give a member somewhere to go next: a first claim, a reward, a higher tier, a mission. None of them prompts a member who has stopped. Activation sends that prompt — a LINE or SMS message, an offer, bonus points — to a particular member when their data shows they have stalled.

[asset:screenshot;id=2b9dad9d-dfe8-4af7-94f0-785043cf740f;title=Newton's first law applied to the member journey: activation is what moves members between stages]

> "Every body persists in its state of rest unless it is compelled to change by forces impressed upon it."
> — Isaac Newton, First Law of Motion · Principia, 1687

#### The full member journey and where members leave it

In the programme's design, a member walks the whole path: **Join** in KCG's LINE OA (§02), **Earn** on every channel they buy through (§03), **Burn** points on a reward (§05), **Grow** into a higher tier (§06), **Engage and return** through campaigns (§07), and **Convert**: make the next purchase on KCG's own channels — the Flagship Store, event booths, Brand.com and, when it opens, KCG's Shopify store (§10).

Most members stop somewhere along that path. The table pairs the common stopping points with the prompt that moves each one on.

| Where members stop | The prompt that moves them on |
|---|---|
| Joined at an event booth for the welcome gift, never claimed a receipt or order | Bonus points on the first claim, sent on LINE a few days after sign-up |
| Earns from Shopee and Lazada, never redeems | A reminder before points expire, showing a reward already within reach |
| Redeemed once, then quiet for two months | A win-back offer timed to that member — triple points on a purchase in the next 30 days |
| A few points short of the next tier as the period closes | Extra points on the purchases that close the gap |
| Never heard about this month's mission | A LINE message sent only to the members the mission suits |
| Buys only on marketplaces and in Modern Trade | A LINE message showing the higher earn rate on KCG's own channels (§04), with a coupon for a first order there |

The last row is the programme's conversion strategy at work. Members won on third-party channels earn at a lower rate there, KCG's own channels pay more, and activation puts that difference in front of the member when they are deciding where to buy next (§03 sets out the full logic).

Each row describes a member whose data has changed, or has stopped changing: a sign-up with no claim, a balance with no redemption, a longer gap than usual since the last order. Activation watches for those changes and responds to each member, which is why it connects every stage of the programme to the next. It is also where personalised marketing and personalised campaigns actually reach individual members (TOR 1-P1b, 1.6). Without it, the programme mostly serves members who would have come back anyway. On our estimates across customers, brands that pair their programme with activation see over 50% higher member engagement and conversion to next purchase than brands that run the programme alone.

#### Four layers of activation

KCG Rewards activates members in four layers, each using the one before it.

```rocket-graphic
{"kind": "horizontal_stepper", "steps": [
  {"label": "Audiences", "sublabel": "Who to reach: groups of members, built once and reused", "accent": "neutral"},
  {"label": "Targeted LINE broadcasts", "sublabel": "One message, sent once, on a date the KCG team picks", "accent": "neutral"},
  {"label": "Rule-based journeys", "sublabel": "Always on: each member's behaviour selects the next step", "accent": "secondary"},
  {"label": "AI decisioning", "sublabel": "Judges, member by member, whether to act and what to send", "accent": "primary"}
]}
```

Audiences, broadcasts and rule-based journeys are part of the core scope; AI decisioning is offered under TOR 9.4. Broadcasts go out on LINE; journeys and AI agents send on LINE and SMS.

### Audiences: who to reach

An audience (segment) is a named group of members defined by conditions on any data in KCG Rewards (TOR 1-P1b, 5.1-P1). The KCG team builds it once and picks it wherever a group is needed: as the recipients of a broadcast, the entry rule of a journey, or the members an AI agent works on. Nobody exports a list or re-enters the conditions.

Conditions can use profile fields; tier and recent tier changes; purchases by channel, store and product, with spend and order counts over a period; points balance; rewards redeemed and coupons used; missions completed, check-ins and survey answers; tags and personas; and RFM group (§08). The journey stages defined in §02, such as "profile done, no first purchase" or "earned, never redeemed", are built as audiences, so the team can target any stage directly. Tier and persona are classifications that the programme's own rules read (earn rates, reward eligibility); an audience is a grouping for marketing and can use tier or persona as one of its conditions.

Each audience is one of three types, chosen by how its membership should change:

```rocket-graphic
{"kind": "kv_table", "rows": [
  {"label": "Live", "value": "Members enter the moment their data matches and leave when it no longer does. Built once, it keeps itself current, which suits journeys and AI agents."},
  {"label": "Fixed", "value": "A snapshot, refreshed when the team asks or daily at a set time, and automatically just before a broadcast goes out. Suits a one-off send or a list that should not change mid-campaign."},
  {"label": "Uploaded list", "value": "A file of existing members matched by phone, email or member code, for lists from outside the programme such as event attendees."}
]}
```

Before switching an audience on, the team previews how many members match today. In KCG's terms, audiences might be "joined at an event booth, no purchase in 14 days", "earned on Shopee, Lazada or TikTok Shop, never redeemed" or "Gold members who bought at the Flagship Store this year". Every audience also gets its own report — size, purchase rate, average order, points balance — covered in §08.

[asset:screenshot;id=13a18464-2e16-4669-905b-6755f52d1464;title=Audience Builder: conditions on any programme data, built once and used by broadcasts, journeys and AI agents]

### Targeted LINE broadcasts

A targeted broadcast is one LINE message, identical for every recipient, sent once at a moment the KCG team chooses. It suits news that belongs to KCG's marketing calendar: a Songkran promotion, a new product launch, a double-points weekend on Brand.com.

A broadcast goes to one of three groups:

- **An audience** — the members in it whose KCG Rewards account is linked to LINE.
- **All of KCG's LINE OA friends.**
- **LINE friends who are not yet members.** This is the route for turning KCG's existing LINE audience into KCG Rewards members, alongside importing current members before go-live (§02, TOR 4.1-P1).

The message is a card or carousel from the Content Library (the same content journeys use), a custom LINE Flex message, or text with quick-reply buttons. The team picks the recipients and sees how many can be reached on LINE, chooses the content, sends a test to up to five staff accounts, then sends now or schedules it. A fixed audience is refreshed just before sending, so members who qualified since the last refresh are included. The send log shows each batch as it goes out; afterwards, the broadcast page shows LINE's delivery and click statistics, and the team can turn the members who clicked into a new audience.

#### How a broadcast differs from a journey

A broadcast and a journey can both send a LINE message to an audience, so the difference is worth stating plainly. A broadcast follows KCG's calendar: the team sets the date, and everyone in the audience receives the same message at the same time, once. A journey runs continuously: each member enters on their own when their trigger happens — they sign up, earn, redeem, change tier or go quiet — and then moves through waits, conditions and branches, so what they receive next depends on what they did. The timing comes from the member's behaviour rather than from a date.

| | Targeted broadcast | Rule-based journey |
|---|---|---|
| What starts it | The KCG team, on a date it chooses | Each member's own trigger (sign-up, purchase, tier change, going quiet), or a recurring schedule |
| Who receives what | Everyone in the audience, the same message | Each member, on the path their own behaviour selects |
| Steps | One message | Waits, condition and interaction splits, several messages and loyalty actions (points, coupons, multipliers, tags) |
| How long it runs | Once | Until the team switches it off |
| Channels | LINE | LINE and SMS |
| Typical use | Songkran promotion, product launch, invitation to non-member LINE friends | Welcome series, points-expiry follow-through, win-back, own-channel nudge |

As a rule of thumb, when the date comes from KCG's marketing calendar, the team sends a broadcast; when the moment depends on something a member did or stopped doing, the team builds a journey.

The two also work together. A button in a broadcast can enrol whoever taps it in a journey: a Songkran broadcast to all members can carry a "Show me the deals" button that starts a three-step offer journey for only the members who tapped. The audience built from a broadcast's clickers can also be a journey's entry rule.

### Rule-based journeys (TOR 1.6)

A rule-based journey is designed once in the admin portal and then runs for every member without anyone pulling a list. When something happens to a member, the journey waits, checks what they did, and sends the next LINE or SMS message or loyalty benefit. Every path is decided in advance, so members who meet the same conditions get the same treatment. This is how segmentation becomes personalised campaigns (TOR 1-P1b, 1.6). Journeys need no development per campaign (TOR 5), and the automated welcome, up-tier and birth-month coupons in §07 run on the same engine (TOR 5.1).

#### Example: from first order to second purchase

The second purchase is where one sale becomes a habit, so this welcome journey is built to get it. A shopper claims a Shopee order in KCG Rewards through LINE and becomes a member (§03). Joining starts the journey:

1. **Welcome.** A LINE message with the welcome coupon (TOR 5.1.1) and a "Ways to earn" link.
2. **Wait 7 days** — time to use the coupon before anything is decided.
3. **Condition split on loyalty data.** Used the coupon or bought on any channel since joining — flagship, Modern Trade receipt or marketplace order?
   - **Yes:** tag "first buyer" and send a LINE thank-you with ×2 points on the next purchase within 30 days. The journey now works on purchase two.
   - **No:** move to the interaction check.
4. **Interaction split on the link.** Did the member click "Ways to earn"?
   - **Didn't click:** switch channel — an SMS says the welcome coupon is waiting, and a "LINE-quiet" tag lets later campaigns reach them differently.
   - **Clicked:** they showed interest but didn't buy. Send a LINE carousel of three ranges KCG wants to push this month: a new launch, a best-seller and a family bundle, each card with its own button.
5. **Interaction split on the button tapped.** Each card leads to a different send: a coupon for the new launch; ×2 points on the best-seller for 14 days; or a where-to-buy message for the bundle plus a "bundle interest" tag that feeds the next family-pack campaign.

```rocket-graphic
{
  "kind": "flow",
  "nodes": [
    {
      "id": "t",
      "label": "Joins KCG Rewards",
      "detail": "Starts the journey",
      "icon": "user-plus",
      "tone": "red"
    },
    {
      "id": "w1",
      "label": "LINE welcome message + welcome coupon",
      "icon": "message",
      "tone": "green"
    },
    {
      "id": "w2",
      "label": "Wait 7 days",
      "icon": "hourglass",
      "tone": "neutral"
    },
    {
      "id": "c1",
      "type": "decision",
      "label": "Used the coupon or bought on any channel?",
      "tone": "blue"
    },
    {
      "id": "y1",
      "type": "end",
      "label": "Tag \"first buyer\" + LINE thank-you",
      "detail": "×2 points on the next purchase within 30 days",
      "icon": "tag",
      "tone": "green"
    },
    {
      "id": "c2",
      "type": "decision",
      "label": "Clicked the link in the welcome message?",
      "tone": "blue"
    },
    {
      "id": "n1",
      "type": "end",
      "label": "SMS reminder + tag \"LINE-quiet\"",
      "icon": "smartphone",
      "tone": "amber"
    },
    {
      "id": "k1",
      "label": "LINE carousel, three cards",
      "icon": "message",
      "tone": "green"
    },
    {
      "id": "c3",
      "type": "decision",
      "label": "Which button was tapped?",
      "tone": "blue"
    },
    {
      "id": "b1",
      "type": "end",
      "label": "New-product coupon",
      "icon": "ticket",
      "tone": "violet"
    },
    {
      "id": "b2",
      "type": "end",
      "label": "×2 points on that product for 14 days",
      "icon": "coins",
      "tone": "violet"
    },
    {
      "id": "b3",
      "type": "end",
      "label": "Where-to-buy + tag \"bundle interest\"",
      "icon": "map-pin",
      "tone": "violet"
    }
  ],
  "edges": [
    {
      "from": "t",
      "to": "w1"
    },
    {
      "from": "w1",
      "to": "w2"
    },
    {
      "from": "w2",
      "to": "c1"
    },
    {
      "from": "c1",
      "to": "y1",
      "label": "Yes"
    },
    {
      "from": "c1",
      "to": "c2",
      "label": "No"
    },
    {
      "from": "c2",
      "to": "n1",
      "label": "Didn't click"
    },
    {
      "from": "c2",
      "to": "k1",
      "label": "Clicked"
    },
    {
      "from": "k1",
      "to": "c3"
    },
    {
      "from": "c3",
      "to": "b1",
      "label": "New launch"
    },
    {
      "from": "c3",
      "to": "b2",
      "label": "Best-seller"
    },
    {
      "from": "c3",
      "to": "b3",
      "label": "Family bundle"
    }
  ]
}
```

Once switched on, the journey runs without staff involvement. Each member follows the path their own behaviour selects, and every step is logged against that member.

[asset:screenshot;id=40d97325-60b9-4e3a-b7d1-56aab4eeedd2;title=Journey Builder — triggers, waits, splits, messages and loyalty actions on one canvas]

#### Journey building blocks

A journey takes its audience from the Audience Builder and its messages from the Content Library, so neither is rebuilt for each journey. The journey itself is assembled from five kinds of block:

| Block | What it does | Examples for KCG Rewards |
|---|---|---|
| **Starting point** | When a member enters | Joins; tier up or down; birthday (on the day or with an offset); membership anniversary; purchase on any channel; points earned or used; reward redeemed; survey answered; enters an audience; a schedule (daily, weekly, monthly, once); a tap on a LINE message button; a manual "run now" for everyone who matches today |
| **Wait** | Pauses for minutes, days or months | 7 days to use a coupon before checking |
| **Condition split** | Yes/no branch on anything the programme knows about the member | Bought a product, or at a channel or store; spend or order count in a period; points balance; tier or recent tier change; tag, persona or audience; used a reward; completed a mission; checked in; a survey answer |
| **Interaction split** | Branches on how the member responded | Which button they tapped in a LINE card or carousel (one branch per button); whether they clicked a link in a LINE or SMS message, optionally which link |
| **Action** | What the member receives or what changes on their profile | LINE message (text, image, video, cards, carousels); SMS; award points; push a coupon or reward; a personal points multiplier for a set window (e.g. ×2 for 30 days); add or remove a tag; assign a persona; add to or remove from an audience |

Conditions work the same way in audiences, entry rules and splits, so anyone who can build an audience can build a split. Before switching a journey on, the KCG team previews how many members match its entry rule today. A member goes through a journey once unless the journey allows repeat entry — for example, a monthly points-balance nudge.

In the Content Library, each button in a LINE card or carousel does one of four things: open a link, give a reward, open a survey, or continue the journey down a branch. That last option is what powers the button split in step 5.

#### Journeys to run from launch

Each is built from the blocks above; final designs are agreed with the KCG team during implementation.

| Journey | Starts when | What it does |
|---|---|---|
| **Welcome series** | A buyer joins, from any channel | The example above |
| **First-purchase nudge** | Joined at an event or through LINE, no purchase in 14 days | LINE coupon for a best-seller; after 7 more days with no purchase, an SMS reminder |
| **Points-expiry follow-through** | Monthly: members with a large balance | Adds to the built-in expiry reminder (§04) a LINE carousel of rewards they can afford now |
| **Own-channel nudge** | A purchase through a marketplace, Modern Trade or Makro PRO, from a member with at least two such purchases and none on KCG's own channels | LINE message showing the higher earn rate on KCG's own channels (§04) and a coupon for a first order there; after 14 days with no own-channel purchase, an SMS reminder that the coupon is waiting |
| **Win-back** | Spent over 5,000 THB in 12 months, no purchase in 2 months | LINE win-back offer; after 7 days with no purchase, a time-limited multiplier announced by SMS |
| **Post-redemption** | A member redeems a reward | After 3 days: coupon used → thank-you and a short survey with points (§07); not used → reminder |
| **LINE friends to members** | Weekly schedule: LINE friends who aren't members yet, each invited once | Join-now invitation; friends who join enter the welcome series |

[asset:screenshot;id=afd806ba-9274-4f7f-97f0-f63221b11007;title=Marketing automation — every journey, its status and entry rules in one list]

#### Measuring each journey

Each journey reports step by step, so the team sees where members drop off: how many reached and completed each step and any that failed; clicks and click-through rate per link in every message; and each member's timeline of what they received and clicked. The tags and audiences journeys create ("first buyer", "LINE-quiet", "bundle interest") flow into audience reports (§08), so one journey's results become the next journey's audience.

[asset:screenshot;id=64884bab-319b-439c-9311-94598e830bbf;title=Journey analytics — sends, clicks and conversions per step]

#### Where rules stop

A rule treats every member who meets its condition the same way and ignores everyone who doesn't. That makes journeys predictable, and it also causes four problems as the programme grows:

- **Rules are set for the average member.** Every threshold is drawn around a typical member, so whoever sits just outside it gets nothing.
- **They assume a fixed path.** A journey expects members to move in the order it was drawn. A loyal buyer who never opens LINE looks disengaged.
- **Every new behaviour needs a new rule.** Each exception is another branch, and across 200,000 members (TOR 3.2) the rules never catch up.
- **They send when triggered, whether or not it helps.** A rule fires the day its condition is met, including for the member who was about to buy anyway.

The first problem is easiest to see in the win-back journey above. Apply it to two members. Member A spent 5,200 THB and has been gone 2 months: the offer goes out. Member B spent 4,900 THB and has been gone 3 months — further along the way to being lost — and the rule never fires.

```rocket-graphic
{
  "kind": "flow",
  "nodes": [
    {
      "id": "a",
      "label": "Member A",
      "detail": "5,200 THB in 12 months, gone 2 months",
      "icon": "user",
      "tone": "blue"
    },
    {
      "id": "b",
      "label": "Member B",
      "detail": "4,900 THB in 12 months, gone 3 months",
      "icon": "user",
      "tone": "violet"
    },
    {
      "id": "c1",
      "type": "decision",
      "label": "Spent over 5,000 THB in the last 12 months?",
      "tone": "neutral"
    },
    {
      "id": "c2",
      "type": "decision",
      "label": "No purchase in 2 months?",
      "tone": "neutral"
    },
    {
      "id": "s",
      "type": "end",
      "label": "Win-back offer sent on LINE",
      "detail": "Member A",
      "icon": "send",
      "tone": "green"
    },
    {
      "id": "n",
      "type": "end",
      "label": "Nothing sent",
      "detail": "Member B is missed",
      "icon": "x",
      "tone": "red"
    }
  ],
  "edges": [
    {
      "from": "a",
      "to": "c1"
    },
    {
      "from": "b",
      "to": "c1",
      "label": "No: Member B, gone longer than A"
    },
    {
      "from": "c1",
      "to": "c2",
      "label": "Yes: Member A"
    },
    {
      "from": "c1",
      "to": "n",
      "label": "No: Member B"
    },
    {
      "from": "c2",
      "to": "s",
      "label": "Yes"
    },
    {
      "from": "c2",
      "to": "n",
      "label": "No"
    }
  ]
}
```

Rules remain the right tool for moments handled the same way every time: the welcome, the birthday coupon, the expiry reminder. Moments that need a judgment about one member go to AI decisioning, which works inside these same journeys.

### AI decisioning: an expert marketer for every member (TOR 9.4)

AI decisioning addresses the four problems just described: the member just outside a threshold, the member who doesn't follow the path the journey drew, the exceptions that would each need another branch, and the offer sent to a member who was about to buy anyway.

A good relationship manager doesn't work from thresholds. They look at one customer: what that person buys, where, how often, what is left in their account. Then they ask whether now is the moment, and what would bring this person back. Mass-market loyalty has always run on averages because that kind of attention needs one person per customer. AI decisioning gives every KCG Rewards member that attention, without a team to provide it. This is how first-party data becomes more frequent purchases and higher lifetime value, member by member (TOR 1.4, 1.6).

Rocket is one of only a few loyalty and B2C CRM companies in the world that can run AI decisioning for mass-market marketing. We offer it under Agentic AI, priced as its own line (TOR 9.4).

[asset:screenshot;id=0680aa25-d43e-46e4-b446-f97a581f4e27;title=AI decisioning agents: a goal and guardrails, then act, wait or skip for each member]

#### What KCG sets: goal, actions, guardrails

The KCG team builds each agent in the admin portal. The agent can only work inside these settings.

**The goal.** The team chooses what the agent works towards: a purchase (such as a second or repeat purchase), win-back, re-engagement, redeeming points, moving up a tier or upsell. Success is defined as a main result, such as a purchase within 7 days of the agent's action, with a target rate for it. Other results can be counted too, including ones the brand wants to avoid. The team also sets the tone of the agent's messages (friendly, urgent, exclusive or celebratory). A short note gives it context in plain language: "a new product launches this month", or "our members buy small baskets often; don't over-reward".

[asset:screenshot;id=f4a4e258-772e-4495-966c-e46b068df00c;title=AI agent: goal and configuration]

**The actions.** The agent uses KCG Rewards' own tools: coupons and rewards from a set KCG chooses, bonus points, time-limited point multipliers (×2 on everything for 14 days), lucky-draw entries, LINE and SMS messages, and tags or audience changes that hand the member to other journeys. Each action gets a range or a set of choices rather than a fixed value, such as 50–200 bonus points or three coupons to choose between, and a note of which members it suits. The agent picks within those limits. It never sees an action KCG hasn't enabled or one the member isn't eligible for.

[asset:screenshot;id=30d1b622-4bd0-4e81-81f0-40511c321b09;title=AI agent: the actions it may use]

**The guardrails.** Guardrails cap what the agent does per member and in total, per day, week or month: actions, messages, points, lucky-draw entries or baht spent. Timing controls sit alongside them: a minimum gap between actions for the same member, quiet hours and blackout dates. A win-back agent for KCG Rewards might run with:

```rocket-graphic
{"kind":"kv_table","rows":[
{"label":"Messages","value":"At most one per member per week"},
{"label":"Bonus points","value":"No more than 300 per member per month"},
{"label":"Budget","value":"50,000 THB a month for the agent"},
{"label":"Quiet hours","value":"No messages between 21:00 and 08:00"},
{"label":"Blackout dates","value":"No actions on KCG's marketplace mega-sale days, so offers don't stack"}
]}
```

Guardrails are checked twice. The agent plans within the headroom it has left, and KCG Rewards refuses any action that would break a limit. Where an agent-wide limit and a limit on one action both apply, the stricter wins.

[asset:screenshot;id=dcaf48d4-e760-4e1a-8b69-492ed0823dda;title=AI agent: guardrails]

#### How the agent decides: act, wait or skip

KCG's journeys choose the moments that hand a member to the agent: a purchase on any channel, entering an audience such as "no purchase in 30 days", a tier change, a points change. At that moment the agent reviews the member's full history across Shopee, Lazada, TikTok Shop, Modern Trade receipts, the Flagship Store and events. It also checks the actions this member is eligible for, the guardrail headroom left, and how it is doing against its goal, including which actions have converted best so far. Then it decides:

- **Act:** send one or more allowed actions now, in the tone KCG set.
- **Wait:** not yet. It records what it is watching for ("an order in the next few days") and when it will look again, then reviews with fresh data.
- **Skip:** this member isn't a fit now. It records why and sends nothing.

Most decisions are "not yet", by design. A good marketer watches before stepping in, and an offer to a member who was about to buy anyway costs KCG margin without changing what the member does. The team sets how often the agent may look again and for how long, for example up to three reviews over two weeks. If it hasn't acted by then, it stops and the journey moves on.

```rocket-graphic
{
  "kind": "flow",
  "groups": [
    {
      "id": "agent",
      "label": "AI agent",
      "tone": "violet"
    }
  ],
  "nodes": [
    {
      "id": "a",
      "label": "Journey hands the member over",
      "detail": "e.g. enters \"no purchase in 30 days\"",
      "icon": "users",
      "tone": "neutral"
    },
    {
      "id": "b",
      "label": "Reviews the member",
      "detail": "History on every channel, eligible actions, guardrail headroom, goal progress",
      "icon": "sparkles",
      "tone": "violet",
      "group": "agent"
    },
    {
      "id": "c",
      "type": "decision",
      "label": "Act, wait or skip?",
      "tone": "violet",
      "group": "agent"
    },
    {
      "id": "f",
      "label": "Records what to watch for and when to look again",
      "icon": "eye",
      "tone": "violet",
      "group": "agent"
    },
    {
      "id": "g",
      "type": "decision",
      "label": "Reviews left within KCG's limit?",
      "detail": "e.g. 3 in 2 weeks",
      "tone": "violet",
      "group": "agent"
    },
    {
      "id": "h",
      "label": "Records why; nothing sent",
      "icon": "clipboard",
      "tone": "violet",
      "group": "agent"
    },
    {
      "id": "d",
      "label": "Guardrails checked",
      "detail": "KCG Rewards refuses any action that breaks a limit",
      "icon": "shield",
      "tone": "blue"
    },
    {
      "id": "e",
      "label": "Sent",
      "detail": "LINE or SMS message, bonus points, ×2 points or a coupon",
      "icon": "send",
      "tone": "green"
    },
    {
      "id": "x1",
      "type": "end",
      "label": "Back to the journey",
      "detail": "Tag \"re-engaged\", then the next seasonal campaign",
      "icon": "repeat",
      "tone": "green"
    },
    {
      "id": "x2",
      "type": "end",
      "label": "Back to the journey",
      "detail": "Monthly LINE broadcast",
      "icon": "repeat",
      "tone": "neutral"
    }
  ],
  "edges": [
    {
      "from": "a",
      "to": "b"
    },
    {
      "from": "b",
      "to": "c"
    },
    {
      "from": "c",
      "to": "d",
      "label": "Act"
    },
    {
      "from": "d",
      "to": "e"
    },
    {
      "from": "e",
      "to": "x1"
    },
    {
      "from": "c",
      "to": "f",
      "label": "Wait"
    },
    {
      "from": "f",
      "to": "g"
    },
    {
      "from": "g",
      "to": "b",
      "label": "Yes: look again",
      "dashed": true
    },
    {
      "from": "g",
      "to": "x2",
      "label": "No"
    },
    {
      "from": "c",
      "to": "h",
      "label": "Skip"
    },
    {
      "from": "h",
      "to": "x2"
    }
  ]
}
```

#### Worked example: three members enter the same win-back journey

Say KCG runs a win-back agent. Its goal is a purchase within 7 days of any action. It can use bonus points (50–200), a ×2 multiplier for 14 days and a LINE message, within the guardrails above. An "overdue" journey hands over every member who enters "no purchase in 30 days", with no spend floor, because the agent, not the rule, decides who is really lapsing. One morning, three members enter.

**Khun Nok, a regular running late.** She joined by claiming a Shopee order in LINE and has bought every three to five weeks since, on Shopee and twice at a Modern Trade store by receipt upload. That comes to 4,900 THB in 12 months, 1,150 points unspent, last order 32 days ago. The rule-based win-back journey misses her twice: she is under its 5,000 THB line, and at 32 days it wouldn't look at her for another month.

1. **Day 0, wait.** Her gaps have run three to five weeks, so 32 days is still within her range. The agent waits four days, watching for an order. Nothing is sent or spent.
2. **Day 4, act.** No order has arrived. The agent sends a friendly LINE message saying her 1,150 points already cover a reward and anything she orders in the next 14 days earns double. It switches the ×2 on for her. This is her first message this week, within budget, so KCG Rewards lets it through.
3. **Day 7, result.** She orders on Shopee, claims in LINE and earns double. The order counts as a conversion for the agent, with its value.

**Khun Dao, not lapsed, just different.** She has spent over 12,000 THB this year, mostly at the Flagship Store, in large baskets every two months or so. Thirty days without a purchase is normal for her. The agent skips her and records why. A rule would have sent her an offer she didn't need.

**Khun Tee, joined once, never returned.** He signed up at an event booth a month ago, spent 180 THB, and hasn't been back. The agent acts small: 50 bonus points and a short LINE invitation to earn on his next order, wherever he buys.

The KCG team wrote no extra rule for any of the three; each treatment came from the member's own history.

#### Inside KCG's journeys

The agent runs as one step inside a rule-based journey. The journey decides who is handed over and when; the agent decides whether to act and what to send. Afterwards the journey carries on down one of two paths: the agent acted (tag the member "re-engaged" for the next seasonal campaign), or it didn't (return them to the monthly LINE broadcast). KCG can keep rules for predictable moments and hand only the moments that need judgment to the agent, in the same journey.

One agent can serve several journeys, with its results pooled so it learns from a larger base. We would expect a small set of agents along the KCG Rewards journey, shaped with the KCG team at implementation and changeable at any time:

| Agent | Goal | Typical actions | Example guardrail |
|---|---|---|---|
| First repeat purchase | A second purchase after the first earn (marketplace claim, receipt or event booth) | LINE message, coupon, small bonus points, ×2 for 14 days | One message per member per week |
| Points redemption | A first redemption from members with enough points | LINE message pointing to rewards within reach, coupon, lucky-draw entry | Two actions per member per month |
| Tier gap | An upgrade for members close to the next tier | Time-limited multiplier, bonus points | 300 bonus points per member per month |
| Win back | A purchase from members overdue against their own rhythm | LINE or SMS, coupon, bonus points, ×2 multiplier | Monthly budget; quiet hours |

#### Seeing what the agent did and why

Every decision is recorded with its reasoning, including waits and skips. The AI results screen in the admin portal shows it at two levels:

- **Per member:** a timeline, such as "Day 0: waited, watching for an order. Day 4: ×2 points and a LINE message. Day 7: purchased."
- **Per agent:** members being watched, acted on and skipped; results against the target rate; which actions converted best; spend against budget; guardrail headroom left.

A result counts only when it happens within the window KCG sets after the agent's action. The KCG team judges the agent on what it changed, and adjusts its goal, actions or guardrails with evidence. The agent sees the same results and leans towards what has worked.

[asset:screenshot;id=855e7504-7d50-4de8-9cf9-13ff1437d740;title=AI agent: outcomes]

#### Rules and AI decisioning side by side

| | Rule-based journeys | AI decisioning |
|---|---|---|
| What KCG defines | The exact trigger, conditions, waits and sends | The goal, allowed actions with ranges, guardrails |
| Who it decides for | Everyone matching a condition, the same way | Each member, from their own history |
| Timing | Fixed delays set in advance | Acts now, waits and looks again, or skips |
| The offer | One offer per branch | Chooses the action and its size within KCG's ranges |
| How it improves | The team edits the rules | It leans towards what converts; the team tunes goal and guardrails |
| Best for | Welcome, birthday, tier-up coupon, expiry reminder | First repeat purchase, win-back, redemption, tier gap |

Both run from go-live in the same journey builder: rule-based journeys in the core scope, AI decisioning under TOR 9.4. §11 gathers the AI that runs across the programme, including how AI analysis (§08) and AI decisioning work together.

Many of the prompts in this section — the own-channel nudge, the ×2 offers, the Songkran button — send members to KCG's own channels. §10 covers what members can do when they reach KCG's own online store: see their balance and what each product earns, spend points and rewards at checkout, and refer friends.
