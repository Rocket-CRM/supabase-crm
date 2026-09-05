# Referral

One referral program. Two conversions: **signup** and **purchase**. People are **referrer** (the member who shares) and **friend** (the other person). Signup identity is `member_code`. The commerce artifact is a **code**.

The friend does **not** need to join loyalty to use a purchase offer. Visit or cookie without a **claim** never pays.

## Concept

Referral is member-led acquisition. A logged-in member shares a personal link. What happens next depends on which conversion is on:

| Conversion | Friend must join? | When the referrer is paid | Friend’s benefit |
|---|---|---|---|
| **Signup** | Yes — apply `member_code` after they become a member | On successful apply | Configured signup outcomes (both parties) |
| **Purchase** | No | First qualifying **paid** order after claim | Commerce discount minted at claim |

Sharing a link does **not** mint a discount. Mint happens at claim. Attribution for purchase is SMART: an open `referral_claim` matching the buyer (email / phone / Shopify customer id) first; a code on the order is optional confirmation.

`source_type` stays `'referral'`. There is no `purchase_referral` source. Do not subscribe to `crm/purchase.event`.

## Notifications (outbox)

`chokepoint_post_referral_event` emits `crm.events.referral` after the existing writers succeed (emit-only; not the sole ledger writer). Copy-link share is not an event. There is no `referral.shared`.

| Domain `event` | When | Notification map |
|---|---|---|
| `applied` | Signup apply; purchase attributed | Dropped at notification router |
| `claimed` | Purchase claim/mint (`api_claim_referral`) | `referral.friend_rewarded` (friend; often no `user_id`) |
| `settled` | Rewards paid (`fn_settle_referral`; signup apply now goes through settle) | `referral.completed` (referrer); `referral.friend_rewarded` (signup friend) |
| `clawed_back` | Purchase clawback | Dropped at notification router |

Requires `OUTBOX_PUBLISH_TOPICS` on Render `crm-event-processors` to include `crm.events.referral`, and `notification-referral-router` on `inngest-event-router-serve`. See `requirements/Notification_Service.md`.

## People and terms

| Term | Meaning |
|---|---|
| **Referrer** | Existing loyalty member who shares. Not “advocate.” |
| **Friend** | The other person. Signup: new member. Purchase: shopper, membership optional. |
| **`member_code`** | Permanent per user/merchant. Signup share identity. Also the `r=` on purchase hops. |
| **Code** | Commerce voucher minted **at claim** (`referral_code`). Not the thing the member copies. |
| **Hop URL** | Rocket `/r/{merchant_code}` page members actually copy for purchase. Crawlers get OG; humans 302. |
| **Claim** | Friend identifies themselves (email or phone) so we can mint and later match the order. |

Do not say “token.” Signup invitee/inviter still appear in older signup copy; prefer referrer/friend in new UI.

## Surfaces

| Surface | What it does |
|---|---|
| **Referral settings** `/referral-settings` | Program on/off, conversions, platforms, outcomes, friend offer, Shopify wrapper, limits, ledger |
| **Standalone admin** | Full page (signup + purchase + Shopee + shop-cap) |
| **Shopify embedded admin** | Same page, **section-gated**: hide signup, Shopee, shop-cap 800, tickets on purchase outcomes. App Bridge nav shows **Referral**. Saves `platform_shopify` instead of replacing `platforms`. |
| **Earn Channels** | Signup CMS card only (`method_type='referral'`). Active does **not** turn the engine on. |
| **Member app** | Signup share (`/?invite=`). Purchase hop `/r/{merchant_code}` (OG + Shopify 302 or Shopee claim landing). |
| **Shopify widget / storefront** | Member: copy/share `purchase.shopify.share_url`. Friend: claim popup on `?r=` (works if launcher is hidden). Storefront job: `rewarding-shopify/widget-builder/REFERRAL_SHOPIFY_FE.md`. |

Customer 360 / analytics **signup** KPIs stay standalone-only.

## Signup journey

1. Referrer opens the member-app referral earn card → `bff_user_get_invite` → copy `{member-app}/?invite={member_code}`.
2. Friend joins, then `bff_user_apply_referral` → `fn_attribute_referral(kind=signup)` → ledger `applied` → settle + `fn_process_referral_rewards`.
3. Limits and self-refer still apply. Friend must become a member.

## Purchase journey (Shopify)

```text
Referrer (widget)                         Friend (store)
─────────────────                         ──────────────
Copy/share hop URL                        Opens hop (OG preview in LINE/FB/WA)
                                          Human 302 → landing URL or shop + ?r=
                                          Claim popup (email) → mint redeem code
                                          Shops. Code at checkout is optional.
                                                    ↓
                              First paid / partially_paid / authorized order
                                                    ↓
                              Referrer outcomes settle. Refund/cancel → clawback.
```

Hop URL (members copy this — **not** the raw store URL):

```text
{first-label}.rocket-loyalty.app/r/{merchant_code}?p=shopify&r={member_code}
```

Dotted Shopify codes stay in the **path**, not the hostname (`fn_referral_share_hop`). Admin **landing URL** is the human destination after 302. No merchant custom CNAME.

### Shopify share copy (three objects)

Share message is **casual** (friend → friend). Link preview and friend-claim popup are **official** (store → friend). Blank wrapper fields use the system default. Custom text replaces that field only. `Use default` stores `null`.

| Field | Voice | Default template |
|---|---|---|
| `share_message` | Casual | `Thought you'd like this — {{friend_offer}} at {{store_name}}` |
| Email subject (member form only, not admin) | Casual | `A gift from a friend` |
| `og_title` | Official | `Get {{friend_offer}} at {{store_name}}` |
| `og_description` | Official | `Claim {{friend_offer}} on your first order.` |
| `popup_title` | Official | `Get your {{friend_offer}}` |
| `popup_button` | Official | `Claim your gift` |

Variables: share message may use `{{store_name}}`, `{{friend_offer}}`, `{{referral_url}}`. Preview + popup use the first two. The runtime **always attaches the invite link** next to the share message — do not put `{{referral_url}}` in the default. Facebook cannot prefill a caption; the OG card is what Facebook friends see.

Widget buttons: Facebook, Email, native Share. Email is the in-widget form (To + subject + body). Subject defaults to `A gift from a friend`; body defaults to the resolved share message; we append the link. Send is the member’s own mail app (`mailto:`), not a branded notification template.

**Do not** use `referral.shared` / Invite a friend in Notification settings. Keep `referral.completed` and `referral.friend_rewarded` (those are store emails after conversion).

`og_title` / `og_description` / `og_image_url` drive LINE / Facebook / WhatsApp cards. `popup_title` / `popup_button` / `popup_icon_url` drive the storefront friend claim popup. Resolver: `fn_referral_resolve_share_copy` — invite and claim APIs return **resolved** strings.

## Fraud gates (purchase)

Claim-time typed email is a lookup, not OTP. Friend-facing copy for self / throwaway / existing is the generic line **This offer isn’t available.** Do not say the friend is the referrer.

| When | Rule | Result |
|---|---|---|
| Claim | Canonicalize email (lowercase; strip `+tag` on all domains; Gmail also strips dots and treats `googlemail` as `gmail`) and compare to the referrer | `SELF_REFERRAL` |
| Claim | Local disposable-domain denylist (`disposable_email_domains`) | `DISPOSABLE_EMAIL` |
| Claim | Already a loyalty member, or a prior marketplace order, or Shopify Admin customer/order for that email (2.5s, **fail-open** if Admin is down) | `EXISTING_CUSTOMER` |
| Claim | One open/completed claim per email (canonical) | `ALREADY_CLAIMED` |
| Order | Buyer is the referrer (canonical email / phone / Shopify customer id) | Ledger `status=blocked`, `block_reason=BLOCKED_SELF`. Friend may keep the coupon. Referrer is not paid. |
| Order | Not first order (`customer.orders_count >= 2`, or another local marketplace order for that email/id) | `BLOCKED_EXISTING`. Same withhold. |

Do **not** hard-block same IP, same name, or shipping address. Do **not** call a third-party mailbox API at claim. Clawback on a blocked row is a no-op.

## Purchase journey (Shopee)

Same hop host/path with `p=shopee`. Friend stays on the Rocket landing and claims with **phone**. Mint is a hidden `add_voucher` (`display_channel_list: []`, 5-char code). Do not mix Shopee into the Shopify widget. Lazada is not v1.

## Program on / off

Active when `referral_program.is_active` AND (`signup_enabled` OR `purchase_enabled`). Helper: `fn_is_referral_program_active(merchant_id)`.

Earn channel Active does **not** turn the engine on. Existing merchants with an active referral earn channel were seeded `is_active=true, signup_enabled=true` so signup did not go dark at cutover.

## Ownership split (admin)

| Concern | Owner | Notes |
|---|---|---|
| Program on / off | **Referral settings** (`referral_program.is_active`) | Not the earn-channel Active toggle |
| Signup / purchase conversions | **Referral settings** | `signup_enabled`, `purchase_enabled`, `platforms` |
| Ways-to-earn card copy / assets | **Earn Channels** | Signup CMS card only (`method_type='referral'`) |
| Signup outcomes | **Referral settings** | `referral_outcomes.kind='signup'` |
| Purchase referrer outcomes | **Referral settings** | `kind='purchase'`, party always `inviter` |
| Friend offer / Shopify wrapper | **Referral settings** | `friend_offer`, `shopify_wrapper`, mother discount on save |
| Invite caps | **Referral settings** | `transaction_limits` `entity_type='referral'` |
| Ledger | **Referral settings** | `bff_list_referral_ledger` with kind/platform filters |
| Global Settings | **None** | Do not put enable here |

One admin page: `/referral-settings`. Shopify embedded **section-gates**; it does not hide the page.

## Conversions (engine)

### Signup

Friend must become a member and apply `member_code`. `bff_user_apply_referral` → `fn_attribute_referral(kind=signup)` → ledger `applied` then settle + `fn_process_referral_rewards`.

Share URL: `{member-app}/?invite={member_code}`.

### Purchase

Platforms in v1: **Shopify** and **Shopee**.

| Surface | Friend identity | Mint | Share URL |
|---|---|---|---|
| Shopify | Email (existing shopper blocked — member, prior order, or Shopify customer) | Redeem code under one mother discount | Hop above |
| Shopee | Phone | Hidden `add_voucher` at claim | Same hop, `p=shopee` |

Claim creates `referral_claim` + `referral_code` (`pending_mint` → `minted`). Caps: shop live unused (default 800, hidden on Shopify admin), per-referrer live unused (default 5). TTL ~24h at create.

**SMART attribution** (`fn_attribute_referral` kind=purchase): open `referral_claim` matching canonical buyer email/phone/Shopify customer id first; minted code on the order is optional confirmation. First order per claim. If the buyer is the referrer or not a first order, insert ledger `blocked` and **do not** settle referrer rewards. Otherwise settle Shopify `paid`/`partially_paid`/`authorized`, Shopee `COMPLETED`. Cancel/refund → clawback (`fn_clawback_referral`); blocked rows skip clawback. Ingest: `upsert_marketplace_order` / `update_marketplace_order_status` / Shopify webhooks `discount_codes` + `buyer_orders_count`.

Purchase outcomes reward the **referrer only**. Friend gets the commerce discount. Receipt-upload `purchase_ledger` is not a purchase-referral trigger.

## Tables

- `referral_program` — master flags, platforms, friend_offer, shopify wrapper, mother discount id
- `referral_outcomes` — `kind` `signup` \| `purchase`
- `referral_ledger` — `kind`, `status` (`applied`/`attributed`/`settled`/`clawed_back`/`blocked`), `block_reason`, `platform`, `claim_id`, `code_id`, `order_key`, friend email/phone
- `disposable_email_domains` — local throwaway inbox list used at claim
- `referral_claim` — `open`/`completed`/`expired`/`aborted`
- `referral_code` — commerce `code`, `pending_mint`/`minted`/`used`/`expired`/`aborted`
- `transaction_limits` — signup invite caps (`entity_type='referral'`)
- `order_ledger_mkp.discount_codes` — codes observed on ingest

## Public / Edge

| Entry | Role |
|---|---|
| `api_get_referral_claim_page` | Anon landing payload (offer + Shopify OG/landing fields) |
| `api_claim_referral` | Anon claim (email or phone by platform) |
| `api_confirm_referral_mint` / `api_abort_referral_claim` | **service_role only** |
| Edge `referral-claim` (`verify_jwt: false`) | Shopee mint via `add_voucher` |
| Edge `shopify-proxy` `POST /referral/claim` | HMAC storefront claim + `shopify-issue-reward-code` |
| `fn_referral_share_hop` | DNS-safe hop host + `/r/{merchant_code}` |

## Admin / member BFFs

| Function | Role |
|---|---|
| `bff_get_referral_settings()` | Program, conversions, platforms, outcomes by kind, friend_offer, shopify, limits |
| `bff_upsert_referral_settings(p_config)` | Merge; Shopify embedded sends `platform_shopify` not a full `platforms` replace |
| `bff_list_referral_ledger(...)` | Optional `p_kind`, `p_platform` |
| `bff_user_get_invite()` | Nested `signup` / `purchase.shopify` / `purchase.shopee` share URLs plus resolved `share.message` / `share.email_subject` / `share.url`. Shopify share URL is the Rocket `/r` hop. |
| `bff_user_apply_referral` | Signup apply (unchanged contract) |

## Apply / claim error codes

| `code` | When |
|---|---|
| `REFERRAL_INACTIVE` | Program off or conversion/platform disabled |
| `EMAIL_REQUIRED` / `PHONE_REQUIRED` | Claim identity missing |
| `SELF_REFERRAL` | Friend is the referrer (canonical email / exact phone). Friend copy: *This offer isn’t available.* |
| `EXISTING_CUSTOMER` | Already a member, prior order, or Shopify customer/order for that email. Friend copy: *This offer isn’t available.* |
| `DISPOSABLE_EMAIL` | Throwaway inbox domain. Friend copy: *This offer isn’t available.* |
| `ALREADY_CLAIMED` | Repeat claim (canonical email) |
| `SHOP_CAP` / `REFERRER_CAP` | Live unused code caps |
| `INVALID_REFERRER` / `INVALID_PLATFORM` / `NO_MERCHANT` | Claim input |
| `MINT_FAILED` / `NO_MOTHER_DISCOUNT` | Commerce mint |
| `INVALID_INVITE_CODE` / `ALREADY_REFERRED` / `LIMIT_EXCEEDED` | Signup apply |
| `OK` | Success |

## Related

- Earn channels: `requirements/Earn_Channel.md` — referral card is CMS only
- Outcome dispatcher: `fn_dispatch_outcome`, `outcome_distribution_log` (`source_type='referral'`)
- Shared limits: `transaction_limits`
- Shopify widget FE: `rewarding-shopify/widget-builder/REFERRAL_SHOPIFY_FE.md`
- Admin FE: `loyalty-admin/ProjectDocs/FE_docs/ReferralSettings.md`
