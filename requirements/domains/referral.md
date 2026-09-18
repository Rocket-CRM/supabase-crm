# Referral

> Per-domain reference. Read ONLY when working on this domain. For the keyword → file map, see `_index.md`.

**Keywords:** referral, invite, invite code, inviter, invitee, referrer, friend, referral code, signup referral, purchase referral, share hop, referral claim, referral limit, referral reward

**Source:** `Referral.md`

**FE-Relevant Sections:**

| Section Heading | What it contains |
|---|---|
| Concept | One program, two conversions (signup + purchase); claim required to pay |
| Rules | Program gate, fraud/limit semantics, earn-channel vs program |
| Journeys › Admin journey | Settings, ledger, Shopify embed |
| Journeys › Member journey | Signup apply; purchase hop → claim → settle |
| Journeys › Shopify | `/r` share hop and storefront attribution |
| System | Tables, BFFs, outbox notifications |
| Fraud gates | Claim + order withhold rules |
| Notifications | `crm.events.referral` catalog rows |

**Supabase Functions (FE-callable):**

| Function | Role |
|---|---|
| `bff_user_get_invite()` | Nested signup + purchase share URLs + `member_code` |
| `bff_user_apply_referral(p_invite_code)` | Signup apply |
| `api_get_referral_claim_page` | Anon hop/landing payload |
| `api_claim_referral` | Anon claim (email or phone) |
| `bff_get_referral_settings` / `bff_upsert_referral_settings` | Admin program config |

**Key Business Rules (summary):**

- Naming: **referrer** / **friend**. Commerce artifact is a **code** minted at claim, not at share.
- Signup: friend must join and apply `member_code`. Visit-only never pays.
- Purchase: friend does not need to be a member. SMART attribution on open `referral_claim`; code on the order is optional.
- Program gate is `referral_program`, not earn-channel Active and not `merchant_master.referral_active`.
- Purchase outcomes reward the referrer only. Friend gets the commerce discount.
- Inviter rewards are **not** via missions. Legacy `referral_signup` / `referral_purchase` mission types are unsupported for this feature.

---
