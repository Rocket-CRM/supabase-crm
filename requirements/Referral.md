# Referral

One referral program per merchant with **two independent conversions** (signup and purchase). The referrer shares a stable **member code**; the friend must **apply at join** (signup) or **claim then complete a qualifying order** (purchase) before configured outcomes pay. Commerce discounts on the purchase path are separate from referrer outcome grants.

Owner surfaces: loyalty-admin, loyalty-user, Shopify storefront widget, Open API (claim / share hop), earn-channel CMS card (`campaign:referral`)

## Concept

Rocket runs a single referral program per merchant. Each conversion type can be enabled independently; both share program-level limits and notification hooks but bind relationships differently.

**Referrer / friend** — An existing member advocates; the friend receives the offer. On signup, the friend must become a loyalty member. On purchase, the friend is a commerce buyer and need not join loyalty.

**Member code** — Stable invite identifier assigned on the member account (derived or ensured at account creation). Signup apply and share links use this value, not a separate per-user referral-code table.

**Signup conversion** — Friend registers on a member channel, then explicitly applies the referrer’s code. A landing visit with an invite query parameter alone never pays.

**Purchase conversion** — Friend follows a share hop, submits identity on a claim surface, receives a **unique store discount code** minted from a **mother discount** (Shopify) or marketplace equivalent, then checks out. Referrer rewards fire when a qualifying paid order is **attributed** to the open claim and **settled**.

**Referral program** — Per-merchant configuration: master activity (derived from conversion toggles in admin UI), signup and purchase enable flags, enabled platforms, friend-offer definition, share copy, Shopify wrapper metadata, mother-discount reference.

**Outcomes** — Configured grants per party (referrer vs friend) and conversion (signup vs purchase): points, tickets, or **catalog reward** (campaign visibility). Paid through the **central outcome dispatcher**, not missions or mission conditions.

**Open claim** — Purchase-path attribution session holding friend identity (email, phone, platform customer id) until an order matches or the window expires.

**Minted commerce code** — Short-lived unique discount code tied to the claim; friend benefit is this commerce offer, not a duplicate referrer-style wallet grant unless signup outcomes configure invitee rewards.

**Earn channel card** — CMS surface `campaign:referral` is always listable for marketing copy; it does **not** gate whether invite, apply, claim, or settle run.

**SMART attribution (purchase)** — Order settlement matches an open claim using discount codes on the order, buyer identity, program rules (first-order requirements, fraud gates), and a **30-day attribution window**. Code TTL and attribution window are decoupled: codes may expire while claims remain attributable until the window ends.

## Rules

### Program gate

- If the program is inactive (`fn_is_referral_program_active` false — no active conversion per DB rules) → invite, apply, claim, and settle paths reject with stable error codes (e.g. `REFERRAL_INACTIVE`).
- If `signup_enabled` is false → signup apply fails; purchase paths unaffected.
- If `purchase_enabled` is false → share hop, claim, mint, and purchase attribution do not run; signup paths unaffected.
- Earn-channel “Active” on `campaign:referral` does **not** override the program gate.

### Signup

- Friend must have a member account before apply; `bff_user_apply_referral` / `fn_process_referral_signup` creates or updates the referral relationship on success.
- Self-referral (member code matches invitee) → `SELF_REFERRAL`.
- Invalid or unknown code → `INVALID_INVITE_CODE`.
- One referral relationship per friend per merchant → `ALREADY_REFERRED` when violated.
- Velocity caps via `transaction_limits` (method `referral`) → `LIMIT_EXCEEDED` when exceeded.
- On success → `referral_ledger` row (`kind = signup`), outcomes via `fn_process_referral_rewards` → `fn_dispatch_outcome`.

### Purchase

- Claim creates `referral_claim` (+ metadata for mint); unique `referral_code` row when commerce mint succeeds.
- Friend-facing benefit is the **commerce discount** (mother + unique code or configured friend-offer reward slot on Shopify); referrer payout is ledger outcome on settle, not an automatic duplicate friend wallet grant.
- `fn_attribute_referral` (`kind = purchase`) runs on order upsert/settlement with order key, buyer email/phone/external id, discount codes, and buyer order counts.
- On qualify → `fn_settle_referral` → `fn_process_referral_rewards` for **referrer** purchase outcomes configured for the merchant.
- Receipt-upload / marketplace attribution uses `referral_claim` — not receipt ledger as the purchase referral source (`Receipt_Upload_Earning.md`).
- `fn_reconcile_missed_referral_purchases` backfills edge timing misses.

### Fraud and withholding

**At claim (friend offer):**

- Email canonicalization (Gmail-style rules), disposable-domain denylist.
- Existing-shopper checks (loyalty member, prior orders, Shopify Admin customer where implemented) may reject with `EXISTING_CUSTOMER`; some Admin lookups fail-open by design.
- Member-facing blocked friend offer copy: *This offer isn’t available.*

**At order (referrer payout):**

- Referrer payout withheld when buyer is the referrer or order is not the first qualifying purchase → `referral_ledger.status = blocked` with `block_reason`.

### Ledger and codes (representative)

| Object | Status / lifecycle (representative) |
| --- | --- |
| `referral_ledger` | Tracks signup or purchase conversion; includes `settled_at`, `clawed_back_at`, `block_reason` |
| `referral_claim` | Open → completed when tied to settled ledger |
| `referral_code` | Active → `used` / `expired` (TTL via `fn_expire_stale_referral_codes`) |

### Notifications

- `chokepoint_post_referral_event` publishes `crm.events.referral` with sub-events `applied`, `claimed`, `settled`, `clawed_back`.
- Catalog sends: `referral.completed`, `referral.friend_rewarded`. Copy-link is **not** an outbound send (`referral.shared` catalog only).
- Router: `notification-referral-router` on Inngest (`OUTBOX_PUBLISH_TOPICS` must include `crm.events.referral`).

### Stable error codes (member / API)

Representative RPC `code` values for i18n: `REFERRAL_INACTIVE`, `INVALID_INVITE_CODE`, `SELF_REFERRAL`, `ALREADY_REFERRED`, `LIMIT_EXCEEDED`, `EXISTING_CUSTOMER`, `NO_MOTHER_DISCOUNT`, `MINT_FAILED`, plus attribution failures recorded on ledger. See Shopify reference appendix A for support mapping.

## Journeys

### Admin journey

| Page | Owning repo | BFF / RPC |
| --- | --- | --- |
| Referral settings | loyalty-admin | `bff_get_referral_settings`, `bff_upsert_referral_settings` |
| Referral settings (reward-type outcomes) | loyalty-admin | `bff_attach_campaign_reward`, `bff_detach_campaign_reward`; atomic friend offer: `bff_upsert_referral_reward_atomic` |
| Referral history | loyalty-admin | `bff_list_referral_ledger` |
| Member 360 | loyalty-admin | Invite from `member_code`; ledger slice via admin member APIs |
| Shopify embedded | loyalty-admin | Same BFFs; section gating per `REFERRAL_SECTIONS` (`settings-visibility.ts`) |

| Setting | Effect on behaviour |
| --- | --- |
| Enable signup referral | Turns on signup conversion and signup outcome blocks (standalone) |
| Enable purchase referral | Turns on purchase share, claim, mint, and purchase settlement |
| Signup outcomes | Referrer + friend cards: points, tickets, or reward per row |
| Purchase outcomes | Referrer rewards (friend benefit is commerce offer / friend-offer slot on Shopify) |
| Friend offer | Mother discount definition and JSON friend offer; Shopify atomic save |
| Share copy / wrapper | Purchase messaging (`fn_referral_resolve_share_copy`, hub/landing labels) |
| Platforms (marketplace) | Which non-Shopify purchase platforms are in scope (standalone picker) |
| Invite limits | `transaction_limits` referral method |
| History tab | Ledger list with filters |

1. Open **Referral settings** (`/referral-settings`). Standalone: tabs **Signup** \| **Purchase** \| **History** (`?tab=signup|purchase|history`). Shopify embedded: **Purchase** \| **History** only.
2. Enable the conversion type(s) you need; configure outcomes per tab.
3. For **Reward** outcome types, use **campaign slot** navigation to reward settings (`from=referral`, `referral_kind=signup|purchase`, `referral_party=referrer|friend`), with `sessionStorage` mirror `rocket.campaign-slot` for App Bridge URL changes. Save attaches via `bff_attach_campaign_reward`; changing reward runs `bff_detach_campaign_reward` (unlink only, not catalog delete). Shared machinery with tier entry and lifecycle workflow outcomes (`campaign-slot.ts`).
4. On Shopify purchase, configure **friend offer** and referrer purchase outcomes; atomic save keeps `referral_program` and `shopify_mother_discount_id` aligned (`bff_upsert_referral_reward_atomic`; reward editor may call **`shopify-upsert-reward-discount`** before attach).
5. Monitor **History** for settled, blocked, and clawed-back rows.

**Shopify embedded section gating** — Page is visible on both surfaces; blocks are filtered by `REFERRAL_SECTIONS`:

| Section | Standalone | Shopify embedded |
| --- | --- | --- |
| Earn-channel banner | Yes | No |
| Signup tab / signup outcomes | Yes | No |
| Purchase tab, friend offer, Shopify wrapper, purchase outcomes, invite limits | Yes | Yes |
| Platforms (marketplace) picker, shop cap | Yes | No |

There is no separate “program master switch” section on either surface; program “active” in UI is derived from enabled conversion toggles. Purchase tab without Shopify connected shows empty state → **Integrations → Connect Shopify**.

### Member journey

| Surface | Owning repo | BFF / RPC |
| --- | --- | --- |
| Invite / share | loyalty-user, widget | `bff_user_get_invite` |
| Signup apply | loyalty-user | `bff_user_apply_referral` |
| Referral status (hub modal) | loyalty-user | `bff_user_get_referral_status` |

1. **Share** — `bff_user_get_invite` returns `member_code`, signup URL `/?invite={member_code}`, and nested purchase hop URLs (`/r/{merchant_code}?p=shopify|shopee&r=`).
2. **Signup path** — Register → apply code → success grants configured signup outcomes; errors map to stable codes above.
3. **Purchase path** — Hop → storefront claim UI → checkout with minted code → referrer rewarded after qualifying settlement.

### Shopify

**Share hop** — Public Rocket `/r/{merchant}` serves Open Graph for crawlers and redirects humans to the landing/storefront. Merchant codes containing dots (e.g. `*.myshopify.com`) use first DNS label on host with full code in path.

**Storefront claim (preferred)** — App proxy on `shopify-proxy`:

- `GET …/apps/rewards/referral/page?referrer_code=` → `api_get_referral_claim_page`
- `POST …/apps/rewards/referral/claim` → `api_claim_referral` then mint

**Mint** — After claim RPC succeeds: `shopify-issue-reward-code` with `shopify_mother_discount_id` and generated commerce code; on failure `api_abort_referral_claim`; on success `api_confirm_referral_mint`.

**Settlement** — `shopify-webhooks` order pipeline → `fn_attribute_referral` (`kind=purchase`) → `fn_settle_referral` → `fn_process_referral_rewards`.

**Alternate claim** — `referral-claim` edge function for hosted / marketplace-style claim; Shopify storefront should prefer HMAC app proxy.

**Shopper-visible referral content** — Loyalty hub (`fn_compose_shopify_hub` referral tiles), landing `shopify_landing_referrals` section, widget invite entry; Klaviyo profile **Rocket Referral URL** when integration connected (`Outbound_Integrations.md`).

## System

### Data model

| Table | Role |
| --- | --- |
| `referral_program` | `is_active`, `signup_enabled`, `purchase_enabled`, `platforms[]`, `friend_offer`, `shopify_wrapper`, `shopify_mother_discount_id` |
| `referral_outcomes` | `party` (inviter/invitee), `kind` (signup/purchase), `outcome_type`, `entity_id`, `amount`, `valid_for_days` |
| `referral_ledger` | Conversion row: `kind`, `status`, `platform`, `inviter_user_id`, `invitee_user_id` (signup), `invite_code`, `claim_id`, `code_id`, `order_key`, friend contact fields, `settled_at`, `clawed_back_at`, `block_reason` |
| `referral_claim` | Open purchase session: referrer, platform, friend email/phone/Shopify customer id, `status`, `ledger_id` |
| `referral_code` | Minted code: `code`, `expires_at`, platform voucher/discount ids, `status`, `claim_id` |
| `referral_reward_save_requests` | Idempotent atomic save requests for referral + Shopify discount cohesion |
| `user_accounts.member_code` | Stable invite identifier (`fn_ensure_member_code`, `fn_derive_member_code`) |

**Campaign reward slots (live)** — Reward-type outcomes attach to `referral_outcomes` (signup/purchase × referrer/friend) or `referral_program.friend_offer` for purchase-friend Shopify slot via `fn_campaign_reward_slot_attach` / `bff_attach_campaign_reward`. There is no separate `campaign_reward_relation` table in production (ND naming).

### Functions

| Callable | Role |
| --- | --- |
| `bff_get_referral_settings` / `bff_upsert_referral_settings` | Admin read/write program + outcomes |
| `bff_list_referral_ledger` | Admin history |
| `bff_attach_campaign_reward` / `bff_detach_campaign_reward` | Campaign slot link |
| `bff_upsert_referral_reward_atomic` (+ `_core`) | Friend offer + mother discount atomic save |
| `bff_user_get_invite` | Member share URLs + code |
| `bff_user_apply_referral` | Signup apply |
| `bff_user_get_referral_status` | Member status summary |
| `api_get_referral_claim_page` | Anon claim landing payload |
| `api_claim_referral` | Create claim |
| `api_confirm_referral_mint` / `api_abort_referral_claim` | Mint lifecycle |
| `fn_process_referral_signup` | Signup ledger + rewards |
| `fn_attribute_referral` | Signup or purchase SMART match |
| `fn_settle_referral` | Close purchase loop |
| `fn_process_referral_rewards` | Outcome dispatcher entry |
| `fn_is_referral_program_active` | Gate |
| `fn_referral_share_hop` / `fn_referral_resolve_share_copy` | Hop + share copy |
| `fn_expire_stale_referral_codes` | Code TTL + claim expiry hygiene |
| `fn_reconcile_missed_referral_purchases` | Backfill |
| `fn_clawback_referral` | Reversal path |
| `chokepoint_post_referral_event` | Notifications + outbox |

### Flows

**Signup** — Share `member_code` → register → `bff_user_apply_referral` → `fn_process_referral_signup` → `fn_process_referral_rewards` → `chokepoint_post_referral_event`.

**Purchase** — Hop → claim APIs → mint edge → checkout → webhook order path → `fn_attribute_referral` → `fn_settle_referral` → `fn_process_referral_rewards` → events.

### External services

| Service | Role |
| --- | --- |
| `shopify-proxy` (edge, public) | App proxy: referral page/claim, widget API |
| `referral-claim` (edge, public) | Non-proxy hosted claim |
| `shopify-issue-reward-code` (edge) | Mint unique code on mother discount GID |
| `shopify-webhooks` (edge, public) | Orders → marketplace upsert + referral attribution |
| `notification-referral-router` (Inngest) | `crm.events.referral` → notification templates |

### Shopify (engineering)

loyalty-admin: `referral-settings/*`, `referral-outcome-cards.tsx`, `src/lib/reward/campaign-slot.ts`. rewarding-shopify widget: `widget-builder/src/services/referral.js` (proxy claim), bootstrap pending referral code handling.

### Known gaps

- `requirements/REGISTRY_SUPABASE.md` Referral section lists only a subset of live tables/functions (missing `referral_program`, `referral_claim`, `referral_code`, attribution RPCs) — regenerate registry when convenient.
- Shopify reference MD table name `campaign_reward_relation` does not exist; slots persist via `referral_outcomes` / `friend_offer` attach path above.
- Retired model: per-user `referral_codes` tables, `merchant_master.referral_active`, mission types `referral_signup` / `referral_purchase` for inviter payouts — missions do not drive referral rewards in the current model.

## Related

- **Earn_Channel.md** — CMS card only; program gate is DB program row.
- **Notification_Service.md** — Referral event catalog and router.
- **Purchase_Transaction.md** — Order settlement vs claim attribution.
- **Shopify.md** — Embed auth, proxy shell, feature routing to this doc.
- **Reward.md** — Campaign reward slot layer (`bff_attach_campaign_reward`).
- **Central_Outcome_Dispatcher.md** — Outcome grants.
- **requirements/reference/SHOPIFY_REFERRALS_ONSITE_INTEGRATIONS.md** — Part 1 authoritative Shopify narrative (on-site touchpoints in Part 2 → Display_Settings.md).
