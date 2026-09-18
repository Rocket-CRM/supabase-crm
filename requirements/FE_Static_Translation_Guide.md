# Frontend Static Translation Guide

## Overview

All static UI text (page titles, buttons, labels, popups, error messages) is served from a single API. Dynamic data like reward names, user names, tier names, and point balances come from their own feature APIs — this guide only covers the **static text layer**.

**API Function:** `get_ui_translations`
**Auth:** Public — no token required (needed for pre-login pages like signup)

---

## 1. Loading Translations

### On App Load

Call once when the app initializes. Pass `p_page_key: null` to fetch **all pages** in a single request.

```javascript
const language = getUserLanguage(); // 'en' | 'th' | 'ja' | 'zh'

const { data } = await supabase.rpc('get_ui_translations', {
  p_page_key: null,
  p_language: language
});

// Save to local variable
const APP_TRANSLATIONS = data.pages;
```

### On Language Change

When user switches language, re-fetch and replace the local variable.

```javascript
async function switchLanguage(newLang) {
  const { data } = await supabase.rpc('get_ui_translations', {
    p_page_key: null,
    p_language: newLang
  });

  APP_TRANSLATIONS = data.pages;

  // Trigger UI re-render
}
```

### Response Shape

```json
{
  "cache_hit": true,
  "language": "th",
  "pages": {
    "home": {
      "header_greeting_prefix": "สวัสดี,",
      "header_label_your_coins": "เหรียญของคุณ",
      ...
    },
    "rewards": {
      "header_page_title": "รายการของรางวัล",
      "popup_button_confirm": "ยืนยัน",
      ...
    }
  }
}
```

---

## 2. Global Translation Function

Create a single helper function used everywhere in the app. Every static text element calls this instead of hardcoding strings.

```javascript
/**
 * Get static translated text by page and field key.
 * @param {string} page  - page_key (e.g. 'home', 'rewards')
 * @param {string} field - field_key (e.g. 'header_page_title')
 * @param {string} [fallback] - optional fallback if key not found
 * @returns {string}
 */
function t(page, field, fallback = '') {
  return APP_TRANSLATIONS?.[page]?.[field] || fallback;
}
```

### Usage in Components

```html
<!-- Instead of hardcoding -->
<h1>Ways to redeem</h1>

<!-- Use the function -->
<h1>{{ t('rewards', 'header_page_title') }}</h1>
<button>{{ t('rewards', 'popup_button_confirm') }}</button>
```

### For Mixed Static + Dynamic Text

When a label is static but the value is dynamic (e.g. "Expires on: 30/12/2025"):

```html
<span>{{ t('rewards', 'wallet_label_expires_on') }} {{ item.expiry_date }}</span>
```

When a number sits alongside a static suffix (e.g. "3 days left"):

```html
<span>{{ item.days_remaining }} {{ t('rewards', 'wallet_label_days_left') }}</span>
```

---

## 3. Page-by-Page Field Reference

Below is every page and which `page_key` + `field_key` to use for each UI element. Elements marked **DYNAMIC** come from feature APIs, not from this translation system.

---

### 3.1 Home / Dashboard — `page_key: "home"`

| UI Element | field_key | Example (EN) |
|---|---|---|
| Greeting before user name | `header_greeting_prefix` | HI, |
| Coins label | `header_label_your_coins` | Your Coins |
| Coin balance | DYNAMIC | 75 |
| Expiry label | `header_label_expiration` | Expiration date: |
| Expiry date value | DYNAMIC | May 20, 2025 |
| My Reward button (top-right) | `header_button_my_reward` | My Reward |
| Way to earn menu | `menu_way_to_earn` | Way to earn |
| Ways to redeem menu | `menu_ways_to_redeem` | Ways to redeem |
| Campaign section header | `section_campaign` | Campaign |
| Mission name inside Campaign | DYNAMIC | — (from mission API) |
| Tier Progress section header | `section_tier_progress` | Your Tier Progress |
| Tier name + progress text | DYNAMIC | Diamonds / Spend $500... |
| Referral section header | `section_referral` | Refer your friends |
| Referral count suffix | `referral_label_completed` | referrals completed |
| Referral share instruction | `referral_share_text` | Share this URL to give your friends the reward |
| Share Facebook label | `share_facebook` | Facebook |
| Share X label | `share_x` | X |
| Share Email label | `share_email` | Email |
| History menu | `menu_my_history` | My History |

---

### 3.2 Ways to Earn — `page_key: "ways_to_earn"`

| UI Element | field_key | Example (EN) |
|---|---|---|
| Page title | `header_page_title` | Ways to earn |
| Earn channel names | DYNAMIC | Place an order, Take a photo... |
| Earn rules (points, conditions) | DYNAMIC | Get ★ 100 points · For every $1 spent |
| Claim Order button | `button_claim_order` | Claim Order |
| Scan Now button | `button_scan_now` | Scan Now |
| Upload button | `button_upload` | Upload |
| Invite Now button | `button_invite_now` | Invite Now |
| Footer branding | `footer_powered_by` | Powered by ROCKET CRM |

---

### 3.3 Rewards List (Ways to Redeem) — `page_key: "rewards"`

| UI Element | field_key | Example (EN) |
|---|---|---|
| Page title | `header_page_title` | Rewards list |
| Points label (top-right) | `header_points` | points |
| My Reward link (top-right) | `header_my_reward` | My reward |
| **Slider section** | | |
| Slider header | `slider_header` | Convert your points |
| Discount amount label | `slider_label_discount` | Discount Amount |
| Points to use label | `slider_label_points` | Points to Use |
| Discount/points values | DYNAMIC | 2,000 / 80 |
| Redeem button (slider) | `details_button_redeem` | Redeem |
| **Filters** | | |
| "All" tab | `filter_all` | All |
| Category tabs | DYNAMIC | Discounts, Free Product (from reward_category) |
| Highlight sort | `sort_highlight` | Highlight |
| **Reward cards** | | |
| Reward name, image, points | DYNAMIC | Grab Voucher – ฿100 / 12 points |
| Redeem button on card | `details_button_redeem` | Redeem |
| Collect points label | `list_collect_points` | Collect points |

---

### 3.4 Reward Detail — `page_key: "rewards"`

| UI Element | field_key | Example (EN) |
|---|---|---|
| Reward name, image, dates | DYNAMIC | Grab Voucher – ฿100 / April 1, 2025 – June 30, 2026 |
| Description body | DYNAMIC | From reward description fields |
| Description tab | `details_tab_description` | Description |
| Terms & conditions tab | `details_tab_terms` | Terms & conditions |
| Redeem limit label | `details_redeem_limit` | Redeem limit |
| Eligible tiers label | `details_eligible_tiers` | Eligible tiers |
| Redeem button | `details_button_redeem` | Redeem |

---

### 3.5 Redeem Confirmation Popup — `page_key: "rewards"`

| UI Element | field_key | Example (EN) |
|---|---|---|
| Popup title | `popup_redeem_confirm_title` | Redeem now? |
| Popup message | `popup_redeem_confirm_message` | Please confirm to redeem |
| Cancel button | `popup_button_cancel` | Cancel |
| Confirm button | `popup_button_confirm` | Confirm |

---

### 3.6 Post-Redeem Success — `page_key: "rewards"`

| UI Element | field_key | Example (EN) |
|---|---|---|
| Success toast title | `popup_success_title` | Redeem success |
| Success toast message | `popup_success_message` | What do you want to do next? |
| See wallet button | `popup_button_see_wallet` | See wallet |
| Use now button | `popup_button_use_now` | Use now |

---

### 3.7 Use Confirmation Popup — `page_key: "rewards"`

| UI Element | field_key | Example (EN) |
|---|---|---|
| Popup title | `popup_use_confirm_title` | Ready to use your reward? |
| Popup message | `popup_use_confirm_message` | Confirm to use it right away. |
| Cancel button | `popup_button_cancel` | Cancel |
| Confirm button | `popup_button_confirm` | Confirm |

---

### 3.8 My Rewards Wallet — `page_key: "rewards"`

| UI Element | field_key | Example (EN) |
|---|---|---|
| Page title | `header_my_reward` | My reward |
| Redeemed tab | `filter_redeemed` | Redeemed |
| Used tab | `filter_used` | Used |
| Expired tab | `filter_expired` | Expired |
| Reward name, image | DYNAMIC | Grab Voucher – ฿100 |
| Expires on label | `wallet_label_expires_on` | Expires on: |
| Expiry date value | DYNAMIC | 30/12/2025 |
| Days left suffix | `wallet_label_days_left` | days left |
| Days left number | DYNAMIC | 7 |
| Use button | `details_button_use` | Use |

---

### 3.9 Reward QR / Barcode / Code View — `page_key: "rewards"`

| UI Element | field_key | Example (EN) |
|---|---|---|
| Reward name | DYNAMIC | Grab Voucher – ฿100 |
| Points label | `details_label_points` | Points |
| Points value | DYNAMIC | 12 ★ |
| Type label | `details_label_type` | Type |
| Type value | DYNAMIC | Discount |
| Redeemed on label | `details_label_redeemed_on` | Redeemed on |
| Redeemed date value | DYNAMIC | 10.02.25 |
| Status label | `details_label_status` | Status |
| Status value | `redemption_status.*` | Ready to Use / Used / Expired |
| QR Code tab | `details_tab_qr_code` | QR code |
| Barcode tab | `details_tab_bar_code` | Bar code |
| Code tab | `details_tab_code` | Code |
| Instruction text | `details_instruction_code` | Show this barcode to staff to redeem your reward. |
| Code value | DYNAMIC | Fcc916Oaab1d |

**Redemption status values** — `page_key: "redemption_status"`

| Status | field_key |
|---|---|
| Redeemed | `status_redeemed` |
| Used | `status_used` |
| Expired | `status_expired` |
| Cancelled | `status_cancelled` |
| Pending | `status_pending` |

---

### 3.10 Ranking Tier — `page_key: "tier"`

| UI Element | field_key | Example (EN) |
|---|---|---|
| VIP Status header | `header_vip_status` | VIP Status |
| Current tier name | DYNAMIC | Diamonds |
| Tier progress text | DYNAMIC | Spend $500 by December 31, 2024 to reach Glow |
| Points / threshold | DYNAMIC | 75 ★ / 3,750 |
| VIP Tier section header | `section_vip_tier` | VIP Tier |
| Tier description | DYNAMIC | From tier config |
| Tier list (names, thresholds) | DYNAMIC | Gold / Spend $0 |

---

### 3.11 My History — `page_key: "history"`

| UI Element | field_key | Example (EN) |
|---|---|---|
| **Top-level tabs** | | |
| Points tab | `menu_currency` | Points |
| Rewards tab | `menu_rewards` | Rewards |
| Campaigns tab | `menu_campaigns` | Campaigns |
| Purchases tab | `menu_purchases` | Purchases |
| Tier tab | `menu_tier` | Tier |
| Receipts tab | `menu_upload_receipt` | Receipts |
| **Sub-filters (Points tab)** | | |
| Points filter | `filter_points` | Points |
| Tickets filter | `filter_tickets` | Tickets |
| **Sub-filters (Campaigns)** | | |
| Activities filter | `filter_activities` | Activities |
| Check-ins filter | `filter_checkins` | Check-ins |
| Missions filter | `filter_missions` | Missions |
| Referrals filter | `filter_referrals` | Referrals |
| **Sub-filters (Rewards)** | | |
| My Rewards filter | `filter_my_rewards` | My Rewards |
| Used filter | `filter_used` | Used |
| Expired filter | `filter_expired` | Expired |
| **Detail labels** | | |
| Date | `date_label_date` | Date |
| Transaction Date | `date_label_transaction_date` | Transaction Date |
| Redeemed | `date_label_redeemed_at` | Redeemed |
| Used | `date_label_used_at` | Used |
| Submitted | `date_label_submitted` | Submitted |
| Approved | `date_label_approved_at` | Approved |
| Rejected | `date_label_rejected_at` | Rejected |
| Expires | `date_label_expires` | Expires |
| Amount | `detail_label_amount` | Amount |
| Source | `detail_label_source` | Source |
| Store | `detail_label_store` | Store |
| Type | `detail_label_type` | Type |
| Code | `detail_label_code` | Code |
| Promo Code | `detail_label_promo_code` | Promo Code |
| Quantity | `detail_label_quantity` | Quantity |
| Balance | `detail_label_balance` | Balance |
| Reason | `detail_label_reason` | Reason |
| Progress | `detail_label_progress` | Progress |
| Payment | `detail_label_payment` | Payment |
| Tax | `detail_label_tax` | Tax |
| Discount | `detail_label_discount` | Discount |
| Fulfillment | `detail_label_fulfillment` | Fulfillment |
| Component | `detail_label_component` | Component |
| **Tier movement prefixes** | | |
| Upgraded to | `tier_prefix_upgrade` | Upgraded to |
| Downgraded to | `tier_prefix_downgrade` | Downgraded to |
| Joined | `tier_prefix_initial` | Joined |
| Moved to (manual) | `tier_prefix_manual` | Moved to |
| Moved to (scheduled) | `tier_prefix_scheduled` | Moved to |
| Tier change to | `tier_prefix_change` | Tier change to |
| **Currency labels** | | |
| Points unit | `currency_points` | points |
| Ticket unit | `currency_ticket` | ticket |
| Use button | `action_use` | Use |
| **Transaction names, dates, amounts** | DYNAMIC | From transaction/history API |

---

### 3.12 Missions — `page_key: "missions"`

| UI Element | field_key | Example (EN) |
|---|---|---|
| Page title | `header_missions` | Missions |
| Claim button | `button_claim` | Claim |
| View button | `button_view` | View |
| Mission goal tab | `detail_tab_mission_goal` | Mission goal |
| Terms & conditions tab | `detail_tab_tc` | Terms & conditions |
| Goal conditions label | `detail_conditions` | Goal conditions |
| Mission progress label | `detail_mission_completion` | Mission progress |
| Outcomes label | `detail_outcomes` | Outcomes |
| Mission names, progress, rewards | DYNAMIC | From mission API |

---

### 3.13 Profile — `page_key: "profile"`

| UI Element | field_key | Example (EN) |
|---|---|---|
| Hello greeting | `text_hello` | Hello |
| Your account section | `text_your_account` | Your account |
| Settings section | `text_settings` | Settings |
| Member benefits label | `text_member_benefits` | Member benefits |
| Change language label | `text_change_language` | Change language |
| Edit profile button | `edit_profile_settings` | Edit profile settings |
| Manage consent button | `button_consent` | Manage consent |
| Language button | `button_language` | Language |
| Notification settings button | `button_notification_settings` | Notification settings |
| User name, tier, points | DYNAMIC | From user profile API |

---

### 3.14 Navigation Bar — `page_key: "navigation"`

| UI Element | field_key | Example (EN) |
|---|---|---|
| Home | `menu_home` | Home |
| Rewards | `menu_rewards` | Rewards |
| Missions | `menu_missions` | Missions |
| Packages | `menu_packages` | Packages |
| Benefits | `menu_benefits` | Benefits |
| History | `menu_history` | History |
| Profile | `menu_profile` | Profile |

---

### 3.15 Packages — `page_key: "packages"`

| UI Element | field_key | Example (EN) |
|---|---|---|
| Page title | `header_my_packages` | My Packages |
| Active filter | `filter_active` | Active |
| Expired filter | `filter_expired` | Expired |
| Use button | `button_use` | Use |
| Included items label | `details_entitlements` | Included Items |
| Remaining label | `details_remaining` | Remaining |
| Used label | `details_used` | Used |
| Source label | `details_source` | Source |
| Valid until label | `details_validity` | Valid until |
| Use confirm popup | `popup_use_confirm_title` | Use this entitlement? |
| Use success message | `popup_use_success` | Entitlement used successfully |
| Package names, counts | DYNAMIC | From packages API |

---

### 3.16 Shared Utility — `page_key: "utility"`

Reusable across any page:

| UI Element | field_key | Example (EN) |
|---|---|---|
| Cancel | `button_cancel` | Cancel |
| Edit | `button_edit` | Edit |
| Save | `button_save` | Save |

---

## 4. Available Pages Summary

| page_key | Fields | Languages | Purpose |
|---|---|---|---|
| `home` | 15 | en, th, ja, zh | Dashboard / landing page |
| `ways_to_earn` | 6 | en, th, ja, zh | Earn channels list |
| `rewards` | 40 | en, th, ja, zh | Reward list, detail, popups, wallet, QR view |
| `redemption_status` | 5 | en, th, ja, zh | Status labels for redemptions |
| `tier` | 2 | en, th, ja, zh | Tier / VIP page |
| `history` | 68 | en, th | Transaction history (ja/zh pending) |
| `missions` | 8 | en, th, ja, zh | Mission list and detail |
| `navigation` | 7 | en, th, ja, zh | Bottom navigation bar |
| `profile` | 9 | en, th, ja, zh | User profile & settings |
| `packages` | 11 | en, th, ja, zh | Package entitlements |
| `benefits` | 8 | en, th, ja, zh | Member benefits |
| `signup_form` | 43 | en, th, ja, zh | Registration / login flow |
| `upload_activities` | 9 | en, th, ja, zh | Activity upload |
| `asset` | 2 | en, th, ja, zh | Asset wallet |
| `utility` | 3 | en, th, ja, zh | Shared buttons |

**Total: 236 unique fields across 15 pages**

---

## 5. Known Gap

| Issue | Detail |
|---|---|
| `history` missing ja + zh | 68 fields exist in en/th only. Japanese and Chinese translations need to be added (136 rows). |

---

*Document Version: 1.0*
*Last Updated: March 27, 2026*
