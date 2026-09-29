## 07 · Campaign Management (Campaign)

Tier status (§06) is one of the things a campaign builds on: the Up-Tier coupon fires when a member moves up, and a mission or spin wheel can be shown only to Gold members. KCG's marketing team builds, changes and stops every campaign in the KCG Rewards admin portal, with no development per campaign (TOR 5-P1). Basic campaigns run on their own when a member reaches a moment such as joining, moving up a tier or a birthday. Advanced campaigns give members a goal they can see in LINE and a reward for reaching it: spending missions, Friend Get Friend and surveys (TOR 1.7). The Lucky Draw (TOR 6.3), spin wheel, daily check-in and leaderboard add further mechanics to rotate through the year. Every channel lands in one purchase history (§03), so a campaign counts a Shopee order, a Modern Trade receipt and a flagship-store sale the same way.

### Building blocks: action, condition, result

Every campaign combines the same three blocks, so the KCG team sets up a new campaign idea by choosing an action, a condition and a result, without a development request.

[asset:screenshot;id=3910a7f2-d4d8-4dc2-948c-3c0ace71ea89;title=Every campaign combines an action, a condition and a result]

A condition narrows the action to what KCG is paying for — a new SKU, the brand's own channels only, a minimum bill, a tier or segment. The result can include a points multiplier on that member's own purchases for a set period, alongside points, e-coupons and lucky-draw entries. Each campaign type sets the five controls of TOR 5.1-P1 on its own settings screen:

| Control (TOR 5.1-P1) | What KCG sets |
|---|---|
| Target Audience | Tier, segment or member tags. Missions can also be limited to members who joined within a date range |
| Period | Start and end dates. Missions can appear a set number of days early and keep a claim deadline after they end |
| Conditions | What counts: spend or number of purchases, products, channels or stores, minimum bill |
| Benefit | Points, e-coupon, lucky-draw entries or a time-limited multiplier |
| Number of entitlements | Caps per member and in total, per day, week, month or campaign |

### Basic campaigns: coupons on member moments (TOR 5.1)

The Welcome, Up-Tier and Birth Month coupons are lifecycle automations. The KCG team sets each one once; from then on KCG Rewards detects the moment every day at the chosen time and puts the coupon in the member's wallet in LINE. Each coupon is a standard KCG Rewards e-coupon, so KCG decides its value, validity and where it can be used (§05).

[asset:screenshot;id=2e146ee2-560e-4e2c-af22-c4b44b4257a8;title=Lifecycle automation: pick the moment, then the actions that follow]

| Campaign | Fires when | Example setup |
|---|---|---|
| Automated Welcome Coupon (TOR 5.1.1) | A member completes sign-up | A discount on the next purchase, valid 30 days, to turn a new member into a second purchase. Welcome points can be added as a second action |
| Automated Up-Tier Coupon (TOR 5.1.2) | A member is upgraded, optionally into a specific tier | One automation per tier, so reaching Gold earns a bigger coupon than reaching Silver |
| Automated Birth Month Coupon (TOR 5.1.3) | A set number of days before each member's birthday | Sent seven days ahead, valid 30 days, so it covers the birthday period. For one send per month, a scheduled journey on the 1st reaches every member born that month (§09) |

A missing birth date means no birthday coupon, which gives members a reason to complete the profile (§02). The same screen runs coupons or points on a tier downgrade and on a membership anniversary. To add a LINE message or a follow-up when the coupon goes unused, the KCG team runs the moment as a journey instead (§09).

**Point Redemption and Privilege Campaigns (TOR 5.1.4, 5.1.5)** are a time-boxed push of catalogue rewards at campaign points prices, and a benefit KCG gives rather than sells, pushed to a tier or claimed by QR at an event booth. Both use the reward controls set out in §05.

### Advanced campaigns: missions (TOR 5.2)

A mission turns a behaviour KCG wants into a goal the member can see, with a progress bar in KCG Rewards and a reward when it is complete. Points awarded by a mission are the Extra Points from Mission of TOR 6.2 (§05).

[asset:screenshot;id=adfd3f14-250c-4cbe-8cb5-765f96f52a4f;title=Missions in KCG Rewards: a goal, visible progress and a reward]

#### Mission – Spending (TOR 5.2.1)

A spending mission rewards a spend or purchase-count goal within a window. Purchase count builds the habit ("buy four times this month"); a spend goal lifts basket size. Six groups of settings:

- **Goal.** Total spend or number of purchases, and which purchases count: products, SKUs or categories; channels or store groups (for example, only the flagship store and website); a minimum bill.
- **Shape.** A standard mission tracks one or several goals at once ("spend 1,000 THB and buy the new product once"). A milestone mission is a staircase of levels; spend beyond one level carries into the next, and each level has its own reward.
- **Who sees it.** Only the tiers or segments KCG chooses (TOR 5.2.1), for example Silver and Gold, or members who haven't bought in 60 days. Members outside the audience never see it.
- **Joining and claiming.** Every eligible member is tracked automatically, or members tap Join first. Missions can sit in a group where each member picks one. Rewards arrive automatically or wait for the member to tap Claim.
- **Repeats and limits.** Progress can reset daily or monthly for a standing challenge. Caps on completions per member and in total, and on how many completions one bill can count toward.
- **Schedule.** Start and end dates, a preview period before the start, and a claim deadline that can run past the end.

[asset:screenshot;id=7329af69-5ee5-45aa-ae8f-a65da47df487;title=Mission list in the admin portal: type, status, join and claim mode at a glance]

**Worked example (illustrative): "Snack Streak – March".** A milestone mission shown only to members who bought once or twice in the last 90 days, the occasional buyers for whom a habit is worth most. Any purchase on any channel counts.

| Level | Goal | Result |
|---|---|---|
| 1 | First 2 purchases | 30 bonus points |
| 2 | 2 more purchases | 50 THB e-coupon |
| 3 | 2 more purchases | Double points on all the member's purchases for the next 30 days |

A member claims a Shopee order in LINE, then uploads a Modern Trade receipt: Level 1 is done and 30 points land. An event-booth sale recorded against her phone number and a website order bring the coupon. Two more purchases by month-end and her double points carry into April. Mission reports show joins, completions and claims per mission (§08).

#### Mission – Friend Get Friend (TOR 5.2.2)

Friend Get Friend turns members into an acquisition channel for KCG, and every friend who joins adds to the brand's first-party base (TOR 1.1).

[asset:screenshot;id=f8927a76-8bb7-44cf-b8dc-126dd2f7ee7e;title=Friend Get Friend: each member's permanent invite code and link]

1. A member opens Invite, copies a personal code or link and shares it in a LINE chat.
2. The friend adds KCG's LINE OA, signs up with a phone number and enters the code.
3. Once the code passes the checks — not the member's own code, a friend referred only once, within the invite cap — both sides receive the rewards KCG sets, for example 50 points for the member and a first-purchase coupon for the friend.

Friend Get Friend is one always-on programme whose offer KCG can change at any time: double the member's reward in the 2027 launch months, switch the friend's reward to a new-product coupon during a launch, then return to standard. Each change is a settings edit, so KCG can run as many referral offers as it wants, one after another, over the life of the programme (TOR 5.2.2). The team sets each side's reward (points, lucky-draw entries or a coupon) and the invite cap per day, week or month. The code is entered at sign-up, so existing members can't be claimed as new friends; referral history shows every referral and its status. Once KCG's Shopify store is live, the same programme gets a second route: a friend who follows the member's link receives a first-order discount on the store, and the member earns the reward set for that purchase (§10).

#### Mission – Survey (TOR 5.2.3)

A survey asks what purchases can't show — who members buy for, when they snack, what they think of a new product — and rewards the answer.

[asset:screenshot;id=8a5d953e-e5f4-400c-815a-47645e4d64b6;title=Survey with a completion reward, in KCG members' language]

The KCG team sets the questions (text, number, date, single or multiple choice), follow-ups that appear only after a matching answer, a submission limit (usually once per member), and the completion reward in points or lucky-draw entries. Members open it from the home screen or a LINE link sent to a segment, such as recent buyers of a new product. Answers become member data: "for my children's lunchboxes" can tag a member for the back-to-school offer, and a low rating can start a follow-up journey (§09).

### Lucky Draw (TOR 6.3)

A lucky draw rewards frequency: the more a member buys or takes part during the draw period, the more entries they hold, so a year-end draw gives members a reason to buy again before it closes. Entries are tickets (§04), kept apart from points, so KCG Rewards keeps its single point currency (TOR 4.2) and a draw adds nothing to the points liability.

[asset:screenshot;id=86b6c59a-7156-4ed4-ba0a-7e3cc7f8ea1c;title=A lucky draw in LINE — the prize, the entry period and how to take part]

Members collect entries in four ways, which the KCG team combines per draw:

- **From purchases**, such as one entry per ฿300 spent on a featured product, on any channel that earns. Because entries follow the same earn rules as points, a draw can give more entries per baht on KCG's own channels, in line with their better points rate (§03, §04).
- **From missions, surveys and daily check-in**, as the activity's prize.
- **By redeeming points** for an entry reward in the catalogue (§05).
- **At an event booth**, where staff redeem an entry on Front Line and print a paper slip for a physical draw box.

Entries can expire on the draw date, so each draw starts clean. When the draw closes, the KCG team exports members and their entries and draws the winners its own way: live on LINE, on stage at an event, or with a witness. Winners' prizes are pushed to their My Rewards or credited as points.

**Worked example (illustrative): "Year-end draw", 1 November – 31 December.** One entry per ฿300 on marketplaces, Modern Trade and Makro PRO, two per ฿300 on the flagship store and website; three entries for completing the November spending mission; one entry for 100 points in the catalogue. Entries expire on 31 December, and the KCG team draws the winners live on LINE in the first week of January.

For an instant result inside LINE, the spin wheel (next subsection) is the alternative that KCG Rewards runs itself: a member spends points or a ticket per spin and wins points, tickets or a reward on the spot.

### More campaign mechanics

Three more mechanics, built from the same blocks, give the KCG team further campaigns to rotate through the year:

| Mechanic | What the member does | What KCG controls |
|---|---|---|
| Spin the Wheel | Spins free, or spends points or tickets, for an instant prize | Prize odds by weight, limited stock per prize, eligibility by tier, tags or birth month, spins per day, week or month |
| Daily Check-in | Checks in daily or weekly and builds a streak, or hits a number of check-ins in a period | Rewards on every check-in and bigger ones on milestone days (for example day 7); eligibility; one check-in per day |
| Leaderboard | Competes for a ranked place, for example top spenders on a new product this month | Columns, ranking and top-N shown; we set up the ranking behind each board with the KCG team. Top ranks win prizes KCG delivers, such as a factory visit |

[asset:screenshot;id=6cecdd12-28d2-424b-96ec-cd98c2c4c7b5;title=Spin the Wheel: prize odds, spin cost and outcomes set by the KCG team]

### An example first year (illustrative)

We suggest running the always-on basics all year with one or two campaigns at a time on top, rotated so returning members find something new. The final calendar is planned with KCG's dedicated loyalty strategist (§12).

| When | Campaign | Mechanic | Purpose |
|---|---|---|---|
| All year | Welcome, Up-Tier and Birth Month coupons; Friend Get Friend | Lifecycle automation, referral | Always-on moments, no monthly work |
| Jan–Feb | Launch: double referral rewards; "first three purchases" for new members | Referral; spending mission for recent joiners | Build the base, turn first purchase into habit |
| Mar | Snack Streak | Milestone spending mission | Raise frequency among occasional buyers |
| Apr | Songkran spin | Spin the Wheel, paid in points | Use idle points; seasonal moment |
| May–Jun | Back-to-school check-in and a family snacking survey | Daily Check-in, survey | Visits between purchases; learn who they buy for |
| Jul–Aug | New product push | Spending mission on the new SKU, then a buyer survey | Trial, then feedback |
| Sep | Redeem Month | Point Redemption Campaign by tier | Use points before expiry |
| Oct | Own-channel month | Spending mission counting flagship and website only | Move repeat purchase to KCG's own channels |
| Nov–Dec | Year-end lucky draw | Entries from purchases and missions; top-spender leaderboard | Peak-season spend, big-prize moment |

Every campaign leaves a record of who took part and what they received — mission joins, completions and claims, referrals, survey answers, draw entries — and §08 reads those records back as campaign-participation reports beside the member, points and redemption data. Telling members about a campaign, and following up with those who don't act, is the work of the targeted broadcasts and journeys in §09.
