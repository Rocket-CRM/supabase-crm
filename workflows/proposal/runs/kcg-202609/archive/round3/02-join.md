## 02 · Member Management (Join)

Joining turns a buyer into someone KCG knows: a verified mobile number that links their purchases on every channel, a LINE connection the brand can message, and consent that says what KCG may send. KCG Rewards runs inside KCG's LINE Official Account, so members have nothing to download (TOR 4.1).

### Member Registration: one tap in LINE to a consented member

Members open KCG Rewards from the LINE OA rich menu, or from a QR code wherever they meet the brand: a card in marketplace parcels, on pack, at the flagship counter, at an event booth. Every entry point leads to the same flow and the same member record:

1. **LINE OA and LINE Login.** One tap opens KCG Rewards inside LINE; the member allows LINE login.
2. **Mobile number and OTP.** A 6-digit code by SMS verifies the number. The account is created here, before any form.
3. **Standard fields, then KCG's own questions**, on separate steps so neither feels long.
4. **Consent.** KCG's documents, plus the channels and topics the member agrees to.

[asset:screenshot;id=7abd9f62-7dd1-4e45-a892-6e5136fa9459;title=Sign-up — from one tap in LINE to a verified, consented member]

Creating the account at step 2 is deliberate. A member who verifies and then leaves at the form is still reachable on LINE and SMS, and sits in the "joined, profile incomplete" stage (below), where an automated nudge such as *"Finish your profile and get a welcome coupon"* can bring them back (§10). Returning members are recognised by LINE and land on the home screen. If KCG adds a required field or consent later, returning members are asked only for that item. Flagship and event staff can also register a member at the counter (§03).

### Member Login: LINE plus mobile number, with more channels available

Members can sign in with **LINE**, **mobile number and OTP** (TOR 4.1, "Member Login ด้วย Mobile Phone Number"), **Facebook** or **email**. KCG chooses which to offer, and can add a channel later without re-registering anyone.

**Our recommendation: whatever else KCG offers, always require LINE, with a verified mobile number.** LINE is the channel marketing automation reaches best. Messages arrive where members already are, as rich cards with buttons, and a tap on a button tells the journey what to do next (§10). The mobile number is the member's identity across channels. It is stored in one format, so *081…* and *+6681…* are the same person, and it matches the member's purchases at the flagship and event POS, at the counter, and on Brand.com. Facebook and email then widen the door, mainly for web visitors who arrive outside LINE. If Brand.com moves to Shopify, collect email at sign-up too, so a member's LINE account and their Shopify account resolve to the same KCG Rewards member (§12).

### Member Profile: the questions KCG chooses

KCG decides what to ask and can change it later without development (TOR 4.1, "Member Profile").

- **Standard fields**: name, email, birth date, gender, address, ID card. For each one the KCG team switches it on, makes it required or optional, and decides whether the member can change it later. Collect birth date from day one; it drives the Birth Month Coupon (§07).
- **KCG's own questions**: free text, single or multiple choice, with follow-ups that appear only after a given answer. For example, *"What do you mostly use KCG products for?"* (home cooking · home baking · for my business), then only for business buyers, *"What type of business?"*. Answers feed segments, reports and journeys (§08, §10).
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

Three things follow from treating stage as status:

- **Every stage is a segment.** "Earned but never redeemed" is an audience journeys target directly (§10), not a list someone exports.
- **Moves are recorded**, so the team sees how many members reached each stage in a period and how many converted to the next.
- **Stage is visible everywhere staff look**: on the member's Customer 360 and as a filter and column in the Members report.

[asset:mockup;id=loyalty.admin.reports-members.overview;title=Members+report+-+sign-ups%2C+profile+completion+and+retention]

Account status sits underneath. Head office can **freeze** a member suspected of abuse, such as refund-after-redeem on a marketplace order or repeated fake receipts. A frozen member can still open KCG Rewards but sees only a request to contact KCG, and can't redeem, spin or claim until staff lift it.

### What members see about themselves

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

When KCG publishes a new version of a document, members aren't asked to re-register. At their next visit they see the new required version before the home screen. Every decision is kept against the exact version the member saw and is never overwritten, so KCG can show who agreed to what, and when. Members change their choices any time from their profile, and audiences can use them, so a promotions message goes only to members who opted in to *Promotions* (§10).

### KCG's current LINE members (TOR 4.1, LINE OA and LINE Current KCG)

- **Same LINE OA.** KCG Rewards opens from the existing rich menu, so KCG's LINE friends don't add a new account.
- **Existing members arrive with their points.** Before go-live we import KCG's member records with profile, point balance and tier, matched on mobile number, LINE account, email or the current member code, so no one is duplicated. If the current system stays live for a period, repeat imports keep the two in step. When an imported member first opens KCG Rewards and verifies their number, their balance is already there; they only complete the profile and consent. The exact sync approach is agreed with the KCG team during onboarding.
- **Friends who aren't members yet** get a LINE invitation to join, sent only to them and optionally timed with a welcome offer (§10).

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
