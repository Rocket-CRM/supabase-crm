## 02 · Member Management (Join)

Every stage in the journey map starts with a member KCG knows, and joining is where that happens. At the end of sign-up KCG holds a verified mobile number that links the member's purchases on every channel, a LINE connection the brand can message, and consent that records what KCG may send.

### KCG's LINE Official Account as the programme's home (TOR 3.4, 4.1)

KCG Rewards runs inside KCG's LINE Official Account, the programme's touchpoint at launch (TOR 3.4), so members have nothing to download and no new account to add. Everything a member does in the programme happens from that one chat: they join, check their points and tier, look back over their purchases and points history, keep their coupons, find how to earn on each channel, and redeem.

- **Rich menu entry points.** Each button on KCG's rich menu can open a KCG Rewards page directly, for example *Home*, *Earn points*, *Rewards* and *My Rewards*, so a member reaches the screen they want in one tap. The same page links can sit behind buttons in LINE messages.
- **Home screen.** Home opens on the member's card: points balance, tier and progress to the next tier. Below it the KCG team arranges banners, featured rewards, missions and quick actions. The team changes the layout in the admin portal without development, and can show different blocks to different member groups, such as business buyers and home cooks.
- **Earning and redeeming.** *Earn points* opens the Ways to earn sheet, which §03 introduces together with the channels; *Rewards* opens the reward catalogue (§05). Orders placed through LINE earn as purchases on KCG's own channel (§03).
- **Messages in the same chat.** When a purchase is recorded, points arrive, a reward is redeemed or the tier changes, KCG Rewards tells the member in the LINE chat, and it reminds them before points or rewards expire. The KCG team chooses which of these messages go out and edits their wording. They reach only members who allow LINE messages (consent, below).

[asset:mockup;id=loyalty.core.home.home;pitch=kcg-loyalty-crm;title=KCG+Rewards+home+in+LINE+-+balance%2C+tier+progress%2C+rewards+and+missions]

[asset:mockup;id=loyalty.admin.display-settings.core;title=Home+screen+layout%2C+set+by+the+KCG+team+in+the+admin+portal]

### Member Registration: one tap in LINE to a consented member

Members open KCG Rewards from the LINE OA rich menu, or from a QR code wherever they meet the brand: a card in marketplace parcels, on pack, at the flagship counter, at an event booth. Every entry point leads to the same flow and the same member record:

1. **LINE OA and LINE Login.** One tap opens KCG Rewards inside LINE; the member allows LINE login.
2. **Mobile number and OTP.** A 6-digit code by SMS verifies the number. The account is created here, before any form.
3. **Standard fields, then KCG's own questions**, on separate steps so neither feels long.
4. **Consent.** KCG's documents, plus the channels and topics the member agrees to.

[asset:screenshot;id=7abd9f62-7dd1-4e45-a892-6e5136fa9459;title=Sign-up — from one tap in LINE to a verified, consented member]

Creating the account at step 2 is deliberate. A member who verifies and then leaves at the form is still reachable on LINE and SMS, and sits in the "joined, profile incomplete" stage (below), where an automated nudge such as *"Finish your profile and get a welcome coupon"* can bring them back (§09). Returning members are recognised by LINE and land on the home screen. If KCG adds a required field or consent later, returning members are asked only for that item. Flagship and event staff can also register a member at the counter (§03).

### Member Login: LINE plus mobile number, with more channels available

Members can sign in with **LINE**, **mobile number and OTP** (TOR 4.1, "Member Login ด้วย Mobile Phone Number"), **Facebook** or **email**. KCG chooses which to offer, and can add a channel later without re-registering anyone.

**Our recommendation: whatever else KCG offers, always require LINE, with a verified mobile number.** LINE is the channel marketing automation reaches best. Messages arrive in the chat members already use, as rich cards with buttons, and the button a member taps tells the journey what to do next (§09). The mobile number is the member's identity across channels. It is stored in one format, so *081…* and *+6681…* are the same person, and it matches the member's purchases at the flagship and event POS, at the counter, and on Brand.com. Facebook and email are then additional ways in, mainly for web visitors who arrive outside LINE. If Brand.com moves to Shopify, we recommend also collecting email at sign-up, so a member's LINE account and their Shopify account resolve to the same KCG Rewards member (§10).

### Member Profile: the questions KCG chooses

KCG decides what to ask and can change it later without development (TOR 4.1, "Member Profile").

- **Standard fields**: name, email, birth date, gender, address, ID card. For each one the KCG team switches it on, makes it required or optional, and decides whether the member can change it later. Collecting birth date from day one matters because it drives the Birth Month Coupon (§07).
- **KCG's own questions**: free text, single or multiple choice, with follow-ups that appear only after a given answer. For example, *"What do you mostly use KCG products for?"* (home cooking · home baking · for my business), then only for business buyers, *"What type of business?"*. Answers feed reports, segments and journeys (§08, §09).
- **Later changes**: members edit their profile in KCG Rewards and staff edit it in Customer 360. A new required question is asked of existing members once, at their next visit. Every question, option and member-facing text can be translated, and members switch between Thai and English.

[asset:screenshot;id=1a4aa463-c4d8-418b-a5d6-6b7a2d35e9ca;title=Member profile — points, tier, rewards, history and consent settings in one place]

### Member Status: tier and journey stage

A member's status has two parts: **where they stand in the programme** and **where they are in their journey with KCG** (TOR 4.1, "Member Status").

**Tier** is the programme status members see: current tier and progress to the next, on the home screen and profile (§06).

**Journey stage** is the status the KCG team works with. The team defines the stages as conditions on the member's data. Each member sits at the furthest stage they match, and moves automatically as they act or stop acting, including backwards when a regular buyer lapses. A starting set for KCG Rewards:

```rocket-graphic
{"kind": "horizontal_stepper", "title": "KCG Rewards journey stages (illustrative, defined with KCG at implementation)", "steps": [
  {"label": "Joined", "sublabel": "LINE and phone verified, profile not finished", "accent": "neutral"},
  {"label": "Profiled", "sublabel": "Profile complete, no purchase yet", "accent": "secondary"},
  {"label": "Earner", "sublabel": "Has earned, never redeemed", "accent": "primary"},
  {"label": "Redeemer", "sublabel": "Redeemed, no repeat purchase yet", "accent": "primary"},
  {"label": "Repeat buyer", "sublabel": "Bought again, increasingly on KCG's own channels", "accent": "gold"},
  {"label": "Lapsed", "sublabel": "No purchase in the window KCG sets, e.g. 90 days", "accent": "warm"}
]}
```

Treating stage as status has three practical consequences:

- **Each stage is an audience the KCG team can target.** "Earned but never redeemed" can receive a broadcast, enter a journey or be handed to an AI agent directly (§09), without anyone exporting a list.
- **Moves are recorded**, so the team sees how many members reached each stage in a period and how many went on to the next.
- **Stage is visible wherever staff look**: on the member's Customer 360 and as a filter and column in the Members report.

[asset:mockup;id=loyalty.admin.reports-members.overview;title=Members+report+-+sign-ups%2C+profile+completion+and+retention]

Account status sits underneath. Head office can **freeze** a member suspected of abuse, such as refund-after-redeem on a marketplace order or repeated fake receipts. A frozen member can still open KCG Rewards but sees only a request to contact KCG, and can't redeem, spin or claim until staff lift it.

### What members see about themselves

Members find their own records in KCG Rewards in LINE; staff see the same records, with more detail, in Customer 360 (below).

| TOR 4.1 item | Member sees in KCG Rewards | Staff see in Customer 360 |
|---|---|---|
| **Member Activity** | Mission progress; points history labelled by source | One activity timeline across channels and campaigns, filterable by type |
| **Member Transaction History** | Purchases from every channel in one list | The same list, plus purchase search across members |
| **Point Balance** | Balance and the next points due to expire, e.g. *"800 points expire 31 Dec"* | Balance, earned and burned over time, points by source, expiry by batch |
| **Coupon / Reward History** | *My Rewards*: ready to use, used, expired | Every redemption and its status |

Point rules, expiry and reversal are in §04; reward rules in §05.

### Member Consent and Communication Preference

Consent is the last sign-up step and keeps KCG within PDPA (TOR 4.1, "Member Consent", "Member Communication Preference").

- **Documents.** KCG's privacy policy, terms and marketing consent, each set as a notice, required to join, or optional.
- **Channels.** LINE, SMS, email and push; the member chooses which KCG may use.
- **Topics.** Subjects KCG defines, such as new products, promotions, or recipes and tips. Hidden if not needed.

When KCG publishes a new version of a document, members aren't asked to re-register. At their next visit they see the new required version before the home screen. Every decision is kept against the exact version the member saw and is never overwritten, so KCG can show who agreed to what, and when. Members change their choices any time from their profile, and audiences respect them, so a promotions message goes only to members who opted in to *Promotions* (§09).

### KCG's current LINE members (TOR 4.1, LINE OA and LINE Current KCG)

- **Same LINE OA.** KCG Rewards opens from the existing rich menu (above), so KCG's LINE friends stay in the chat they already follow.
- **Existing members arrive with their points.** Before go-live we import KCG's member records with profile, point balance and tier, matched on mobile number, LINE account, email or the current member code, so no one is duplicated. If the current system stays live for a period, repeat imports keep the two in step. When an imported member first opens KCG Rewards and verifies their number, their balance is already there; they only complete the profile and consent. The exact sync approach is agreed with the KCG team during onboarding.
- **Friends who aren't members yet** can be sent a LINE invitation to join, addressed only to them and optionally timed with a welcome offer (§09 covers these targeted broadcasts).

### Customer 360: everything about one member, on one page

Customer 360 is where the KCG team sees one member across every part of the programme, over the period they choose (30 days to all time):

- **Identity**: profile, persona, tags, how and when they were acquired, RFM segment, and journey stage.
- **Points and currencies**: balance, earned and burned over time, points by source, and each batch with its expiry.
- **Tier**: current tier and progress to the next.
- **Rewards**: coupons ready to use and used, and every redemption.
- **Campaigns**: mission progress and active benefits.
- **Purchases and interactions**: one timeline of purchases from every channel, point movements, redemptions, mission activity and the touchpoints KCG records from LINE, web or store, filterable by type.

[asset:screenshot;id=375eff5e-6191-4f8a-aa8a-592c64017637;title=Customer 360 — one member's full relationship, then the next action]

From the same page, head office acts with that context in view: edit profile fields or the mobile number; unlink a LINE account when a member switches to a new LINE account, so the next login attaches the new one; add tags and staff notes; adjust points or tickets with a reason (§04); set a tier and lock it against downgrade; freeze or unfreeze. Each action is recorded. What each staff member can see and change follows their role.

[asset:mockup;id=loyalty.admin.customer-360.member;title=Customer+360+in+the+live+portal]

Customer 360 is the per-member view; reports across all members are in §08, and the counter version for flagship and event staff is in §03.

Once a member is known by LINE account and mobile number, a purchase on any KCG channel can be credited to them. §03 sets out how each channel, from Shopee to the flagship till, makes that link.
