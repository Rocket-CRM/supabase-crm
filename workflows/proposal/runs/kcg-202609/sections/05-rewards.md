## 05 · Reward & Privilege (Burn)

The balance members build on every channel (§04) is worth collecting because of what it buys, and rewards give members a reason to come back to KCG's own touchpoints to spend it. Every reward type in TOR 6 runs from one catalogue in the LINE OA, and each reward carries its own audience, dates, limits and tier-based points price, set by the KCG team in the admin portal (TOR 1.5, 6).

[asset:screenshot;id=7ce449a8-b347-4f80-8dd7-d072de8cea09;title=Rewards in LINE — each member sees only the rewards open to them, at their own points price]

### One catalogue, three ways in

A reward is defined once (name, picture, terms, fulfilment, rules) and reaches members by any of three routes:

- **Redeemed with points**, by the member from Rewards in LINE, or by KCG staff at the counter on Front Line, the staff app. Once KCG's Shopify store is live, members can also spend points and rewards at its checkout (§10).
- **Won** as the prize of a mission, referral, spin wheel, lucky draw or tier upgrade (§06, §07).
- **Given** free: pushed by an automated journey (§09) or by staff, or claimed from a link or QR code.

The second and third routes can use campaign-only rewards that never appear in the catalogue, so a privilege reaches only the members it is meant for.

### Reward types (TOR 6.1–6.4)

#### E-Coupon (TOR 6.1)

A coupon has two moments: **redeemed** (points deducted, coupon waiting in the member's My Rewards) and **used** (benefit consumed). At the counter, a booth or online checkout, the member opens it and the slip shows a code, barcode and QR code with the brand's instructions for staff. My Rewards keeps unused, used and expired coupons apart.

At the flagship: a member redeems 100 points for "฿100 off at the KCG Flagship Store". Two weeks later they tap Use at the till; the cashier checks the slip and applies the discount; the coupon moves to Used and counts in the redemption report (§08).

For each coupon, KCG decides:

- **Who marks it used.** The member, which suits partner and online codes; or staff only, on Front Line or a connected POS, so a counter coupon can't be spent by accident at home.
- **Where the code comes from.** Generated per redemption; one fixed code for everyone, such as a website promotion code; or an uploaded code list, such as partner vouchers, tracked by partner for reconciliation. On Shopify, the discount code is created automatically (§10).
- **How long it lasts.** Until a fixed date, to match a partner batch, or a set time from redemption: 30 days for a standard coupon, down to minutes for a flash offer at an event.

[asset:screenshot;id=35716bf9-8114-499c-b817-0c5c0b90cbff;title=From catalogue to slip — the member redeems, then shows the code, barcode or QR at the KCG counter]

#### Merchandise (TOR 6.4)

Gift sets, totes, aprons and seasonal hampers are each either **shipped** or **picked up**. For shipped items, the member confirms a delivery address at redemption, prefilled from their profile; the KCG team exports redemptions for the warehouse, and each shipment moves through pending, shipped, delivered or cancelled. For pickup, the member collects at the flagship and staff mark the handover on Front Line. Stock can be capped per item, and redemption stops when it runs out. A wider partner catalogue, sourced and fulfilled by Rocket, is an optional service (§12).

[asset:screenshot;id=40939c43-a616-4fa9-a718-8bba4848d971;title=Front Line — KCG staff redeem, hand over and mark rewards used at the counter or event booth]

#### Extra Points from Mission (TOR 6.2)

A mission can award points as its prize, for example for reaching a monthly spend goal or buying a featured product three times in a month. The points land in the member's one balance, follow the programme's usual expiry, and show in their history as a mission reward. A mission can award a coupon or merchandise instead, or as well. Missions are built in §07; how extra points differ from purchase bonuses is in §04.

#### Lucky Draw entry (TOR 6.3)

A lucky-draw entry can sit in the catalogue as a reward members redeem with points; how members collect entries and how KCG draws the winners is a campaign, set out in §07 under Lucky Draw.

### Controls on every reward (TOR 6-P1)

Each reward's rules fall into five groups of settings:

```rocket-graphic
{
  "kind": "kv_table",
  "rows": [
    { "label": "Who may redeem (Target Audience, เงื่อนไขการได้รับสิทธิ์)", "value": "Tier, persona (a member type KCG defines, such as KCG employees), tags and birth month. Left empty, it means everyone. A segment the KCG team builds reaches a reward through a tag a journey applies (§09)." },
    { "label": "When (วันเริ่มต้น, วันสิ้นสุด)", "value": "A redemption period: the reward can show ahead of it as a teaser and leaves the catalogue when it closes. Separately, a use period after redemption." },
    { "label": "How many (จำนวนสิทธิ์)", "value": "Limits per member and across all members, per day, week, month, year or all time, several at once, counted across every past redemption. Reward groups cap a set of rewards together: total units, and how many different rewards a member may pick." },
    { "label": "At what points price (TOR 4.2)", "value": "A base price, plus lower prices for chosen tiers, personas or tags. The most specific match wins; a tie goes to the lower price. A reward can also be restricted to members who match one of its prices." },
    { "label": "Where it appears", "value": "The LINE catalogue, the counter only (Front Line), both, or campaign-only." }
  ]
}
```

A worked example, with illustrative tiers (KCG's tier design is agreed at implementation, §06):

> **KCG Festive Gift Set**, 1–31 December. 400 points; 350 for Gold; 300 for Platinum. One per member, 500 in total. Shipped, with a choice of two flavours.
>
> A Gold member with 380 points sees it at 350 and redeems. A Silver member with 380 points sees it at 400, and the button says they need 20 more. After the 500th set, the button reads "limit reached".

The member always sees their own price, the dates and whether they can redeem; if not, the button says why (not enough points, limit reached, not yet open, not eligible).

### Point Redemption Campaign (TOR 5.1.4)

A Point Redemption Campaign offers a set of rewards for a limited time, with its own period, audience, prices and limits: a reward group featured at the top of Rewards for the campaign period. For example, **Redeem Month**, 1–30 September: five gift sets at reduced points, lower still for Gold and Platinum, one per member, 300 in total, announced by a LINE broadcast to members whose balance already covers a set (§09). Run just before a points-expiry date, it lets members spend points that would otherwise lapse.

### Privilege Campaign (TOR 5.1.5)

A privilege is a benefit selected members receive without spending points. It is built from campaign-only rewards, so it never shows in the public catalogue, and carries the same audience, period, conditions and entitlement controls as any reward (TOR 5.1). It reaches members in four ways: pushed to a tier or segment by a journey, once or on a schedule, such as a free drink at the flagship for every Platinum member on the first of each month (§09); pushed by staff on Front Line, to one member or a list; granted on reaching a tier (§06); or claimed from a link or QR code on a poster, a booth or a LINE message, which KCG can switch off at any time. Partner privileges (dining, beverages, fuel, lifestyle, TOR 13) come through the optional Privilege Acquisition service (§12), on the same catalogue and controls.

Tier-only rewards, lower tier prices and rewards granted on reaching a tier are the other form of privilege. All three depend on the tier ladder, which §06 sets out: what members qualify on, when they move up and how they keep a tier.
