# Frontline Admin Actions

Admin actions on one member — viewing the unified profile in Customer 360, and acting on the member's behalf from Customer 360 or the Front Line counter page.

Owner surfaces: loyalty-admin (Customer 360, Front Line)

## Concept

The member journey runs basic loyalty → engage → analyze → activate. Analysis has two lenses: aggregate (Analytics dashboards) and individual (**Customer 360**). Customer 360 is the unified-profile piece of Rocket's "mini CDP" (unified profile → segments → activation). It gathers every domain for one member — profile, tier, points, purchases from all channels, redemptions, campaigns — into one page, and shows the member's lifecycle as a single activity timeline. Analysis is passive (read for insight); activation is proactive (send something to the member) and lives in Segments and Marketing Automation, not here. Customer 360 is also where head office corrects a member's record.

**Front Line** is the counter mode of the same admin portal, not a separate app. Store or counter staff use it to transact for a member who is standing in front of them, so the member does not have to use the member app. The reference case is a shopping mall with service counters: shoppers bring the day's receipts, redeem rewards, or claim campaign prizes at the counter.

- **Member profile** — identity (phone, LINE, email), personal and custom fields, persona, tier, tags, and staff remarks.
- **Service point** — the store, branch, or counter the staff member is serving from. Chosen before any member is opened; every Front Line transaction is attributed to it.
- **Transaction on behalf** — an action staff perform for the member. There are five groups: profile (register, edit); earn (enter a receipt, adjust points); burn (redeem a reward, burn points for a discount code); campaign (claim a mission, check in, push a free reward); and asset (e.g. registered car plates for tier parking privileges). Store credit is a separate tab.
- **LINE unlink** — clears the LINE account bound to a member. Login matches both the phone and the LINE account captured at signup, so a member who switches to a new LINE account while keeping the same phone is locked out. Unlinking lets their next phone login bind the new LINE account to the existing member. This is the most common support fix.
- **Manual tier** — head office assigns a tier by hand, optionally with a downgrade lock so the normal maintain check cannot pull the member back down.
- **Freeze** — blocks a member's self-service for fraud (for example, burning marketplace points and then refunding the order, or faking receipts). See Member_Freeze.md.

## Journeys

| Page | Owning repo | BFF / RPC |
|---|---|---|
| Customer 360 search + detail | loyalty-admin | `bff_admin_search_members`, `bff_admin_get_member_360`, actions in the Overview table, `bff_admin_set_member_freeze` |
| Front Line hub (member / reward search) | loyalty-admin | `bff_admin_get_store_options`, `bff_admin_search_members`, `api_get_redemption`, `api_mark_redemption_used` |
| Front Line member page | loyalty-admin | `bff_admin_get_frontline_member`, `bff_admin_get_frontline_hidden_tabs`, per-tab RPCs in the owning domain docs |

### Admin journey — Customer 360

| Knob | Effect |
|---|---|
| Profile field *visible / editable by admin* (profile field config) | Controls which fields show and which are editable in Edit Profile. |
| Role permission `customer-360` read / update | Read opens the page; update shows Edit Profile, Adjust (currency), Adjust tier, Freeze, and Delete. |

1. **Customers** → search → open the member. The page shows the tier card, points and currency (earned / burned, monthly trend, by source), wallet lots, redemptions, purchase spending, check-in / referral / RFM summaries, and the activity timeline (filterable by type and time range).
2. **Edit Profile** → change fields, mobile, or persona; unlink LINE (confirm dialog); add or remove tags; add a staff remark. Each is saved on its own.
3. **Adjust** (points or tickets) → add or deduct with a required reason. The adjustment appears in the timeline.
4. **Adjust tier** → pick a tier on the member's ladder, give a reason, optionally lock downgrade. The tier engine only ever raises a tier on earn or purchase events. Downgrades happen only at the maintain check, and a manual change restarts the maintain clock from today. Without the lock, a raised tier survives until that check; a lowered tier is raised again as soon as the member's next event qualifies them higher (Tier.md).
5. **Freeze member / Unfreeze member** → confirm. A Frozen badge shows in the header.

### Staff journey — Front Line

| Knob | Effect |
|---|---|
| Frontline role (or custom role) tab permissions | Each tab shows only with its `frontline_*` read permission, and its actions need update. Edit Profile needs `frontline_edit_member_profile`. |
| Per-merchant hidden tabs | Hides tabs the merchant does not use (e.g. check-in, asset group), regardless of role. |
| Staff store assignment | Limits which service points the staff member can pick. |

1. **Front Line** → pick the service point. With no stores assigned, staff see *No stores assigned — contact an admin*; with no `front_line` access, a no-access banner.
2. **Member search** → phone, username, member code, ID card, passport, or a QR scan. *No members found* offers **Add new member** (register on the member's behalf).
3. **Reward search** (no member needed) → type or scan a redemption code. The reward card shows status (active / used / expired), the member, where it was redeemed, and a **Use** button to mark it used. A frozen member's reward shows a warning.
4. Open the member → the header shows name, persona, tier and progress, points balance, today's earned and used points, and remarks. The service point is locked for the session.
5. Work the tabs: Upload Receipt, Redemption Reward (mark used from the member's wallet, or redeem, or redeem-and-use), Adjust Points (add or deduct with reason), Claim Mission, Asset Group, Burn Points for Discount, Push Reward, Store Credit, Check-in. **Push to members** on the hub pushes a reward to several members at once. Upload Receipt records the keyed purchase only — the receipt photo is not stored.
6. **Edit Profile** → the same panel as Customer 360, without tier.
7. A frozen member shows a warning banner, and every tab and Edit Profile become read-only.

---

## Overview

Admins act directly on individual members from Customer 360 or Front Line. These are synchronous, audited operations that bypass the standard user-facing flows.

| Action | Function |
|--------|----------|
| Adjust currency (points/tickets) | `bff_admin_adjust_currency` |
| Adjust member tier + downgrade lock | `bff_admin_adjust_member_tier` |
| Assign / remove member tag | `bff_admin_assign_member_tag` |
| Change mobile number | `bff_admin_change_member_mobile` |
| Change persona | `bff_admin_change_member_persona` |
| View editable profile form | `bff_admin_get_member_profile_form` |
| Save profile changes | `bff_admin_update_member_profile` |
| Add staff remark | `bff_admin_create_user_note` |

Each action is a **separate, isolated call** — mobile, persona, profile fields, remarks, **tags**, and **tier** are never mixed in a single mutation, so a failure in one cannot affect the others. The C360 Adjust tier modal may show tags on the same screen; chip add/remove still calls `bff_admin_assign_member_tag` immediately, and Save only calls `bff_admin_adjust_member_tier`.

### Access Control

Common to all: authenticated caller, merchant from `get_current_merchant_id()`, active `admin_users` row, target member in the same merchant. Then per function:

| Function | Gate |
|---|---|
| `bff_admin_adjust_currency` | Role `owner`/`admin`, **or** `frontline_adjust_points` create/update |
| `bff_admin_update_member_profile`, `bff_admin_assign_member_tag`, `bff_admin_create_user_note` | `customer-360.update` or `front_line.update` |
| `bff_admin_change_member_mobile`, `bff_admin_change_member_persona` | `customer-360.update` or `front_line.update`, **and** role `owner`/`admin` |
| `bff_admin_adjust_member_tier`, `bff_admin_set_member_freeze` | `customer-360.update` only |

Known gap: the owner/admin role check on mobile and persona means Frontline-role staff are rejected server-side even when their role grants profile edit.

---

## 1. Adjust Currency

### Purpose

Allow admins (and Front Line staff with Adjust Points) to add or deduct points/tickets for a member — for corrections, goodwill gestures, customer service resolutions, or manual campaign awards.

### Function

```
POST /rest/v1/rpc/bff_admin_adjust_currency

Parameters:
- p_user_id: UUID (target member)
- p_currency: 'points' | 'ticket'
- p_transaction_type: 'earn' | 'burn'
- p_amount: INTEGER (positive, absolute value)
- p_reason: TEXT (required, non-empty)
- p_target_entity_id: UUID (required for tickets, null for points)
- p_metadata: JSONB (optional, additional context)

Headers:
- Authorization: Bearer {admin_jwt}
- x-merchant-id: {uuid}
```

### How It Works

1. Validates admin auth + permission
2. Validates the target user belongs to the same merchant
3. Validates inputs (positive amount, non-empty reason, correct currency/entity pairing)
4. Builds enriched metadata containing audit trail:
   ```json
   {
     "admin_user_id": "uuid",
     "admin_name": "John Admin",
     "reason": "Customer service goodwill - delayed delivery",
     "adjusted_at": "2026-03-31T..."
   }
   ```
5. Calls `chokepoint_post_wallet_transaction()` with:
   - `source_type = 'manual'`
   - `component = 'adjustment'`
   - `description = p_reason`
   - `metadata = enriched metadata with admin trail`
6. Returns new balance after adjustment

### Response

```json
{
  "success": true,
  "title": "Currency adjusted",
  "description": "Added 500 points for Siriporn Thongsuk",
  "data": {
    "ledger_id": "uuid",
    "user_id": "uuid",
    "currency": "points",
    "transaction_type": "earn",
    "amount": 500,
    "new_balance": 12950,
    "reason": "Customer service goodwill",
    "admin_user_id": "uuid"
  }
}
```

### Audit Trail

Every adjustment creates a `wallet_ledger` entry with:

| Field | Value |
|-------|-------|
| `source_type` | `manual` |
| `component` | `adjustment` |
| `description` | The admin's reason text |
| `metadata` | Contains `admin_user_id`, `admin_name`, `reason`, `adjusted_at` |

This is visible in the member's activity stream (`bff_admin_get_member_360 → data.activity_stream`) and in wallet ledger queries.

### Validation Rules

| Rule | Error |
|------|-------|
| Amount ≤ 0 | "Amount must be a positive integer" |
| Empty reason | "A reason is required for all adjustments" |
| Ticket without entity ID | "target_entity_id is required for ticket adjustments" |
| Points with entity ID | "target_entity_id must be null for points adjustments" |
| Insufficient balance (burn) | "Insufficient points/ticket balance" (from `chokepoint_post_wallet_transaction`) |

---

## 2. Change Mobile Number

### Purpose

Admin changes a member's phone number. Isolated from other profile fields — only `tel` is touched.

### Function

```
POST /rest/v1/rpc/bff_admin_change_member_mobile

Parameters:
- p_user_id: UUID (target member)
- p_tel: TEXT (new phone number)

Headers:
- Authorization: Bearer {admin_jwt}
- x-merchant-id: {uuid}
```

### How It Works

1. Validates admin auth + permission
2. Validates target user belongs to merchant
3. Trims and validates new phone is non-empty
4. No-op if new phone equals current phone
5. Duplicate check — ensures no other user in the merchant has this number
6. Updates `user_accounts.tel`

### Response

```json
{
  "success": true,
  "title": "Mobile updated",
  "description": "Phone changed from +66812345001 to +66899999999 for Siriporn by John Admin",
  "data": {
    "user_id": "uuid",
    "old_tel": "+66812345001",
    "new_tel": "+66899999999",
    "admin_user_id": "uuid"
  }
}
```

### Validation Rules

| Rule | Error |
|------|-------|
| Empty phone | "Phone number cannot be empty" |
| Duplicate phone | "This phone number is already registered to another account" |

---

## 3. Change Persona

### Purpose

Admin changes a member's persona assignment. This also updates `user_type` if the new persona group has a different `user_type`.

### Function

```
POST /rest/v1/rpc/bff_admin_change_member_persona

Parameters:
- p_user_id: UUID (target member)
- p_persona_id: UUID (new persona, or null to remove)

Headers:
- Authorization: Bearer {admin_jwt}
- x-merchant-id: {uuid}
```

### How It Works

1. Validates admin auth + permission
2. Validates target user belongs to merchant
3. Delegates to existing `assign_persona()` which handles:
   - Persona existence and active status validation
   - Merchant match between user and persona
   - `user_type` update if the persona group defines one
   - Removing persona if `p_persona_id` is null

### Response

```json
{
  "success": true,
  "title": "Persona updated",
  "description": "Persona changed to Executive for Siriporn by John Admin",
  "data": {
    "user_id": "uuid",
    "persona_id": "uuid",
    "persona_name": "Executive",
    "group_name": "Corporate",
    "old_persona_id": "uuid",
    "user_type_changed": true,
    "new_user_type": "buyer",
    "admin_user_id": "uuid"
  }
}
```

**Remove persona payload** (pass null):

```json
{
  "p_user_id": "member-uuid",
  "p_persona_id": null
}
```

### Validation Rules

| Rule | Error |
|------|-------|
| Persona not found | "Persona not found" |
| Persona inactive | "Persona or group is inactive" |
| Persona wrong merchant | "Persona belongs to different merchant" |

---

## 4. Edit Member Profile

### Architecture

Editing a member profile is a two-step flow:

```
┌──────────────────┐     ┌───────────────────────────────┐     ┌────────────────────────────────┐
│  Admin clicks     │────▶│  bff_admin_get_member_        │────▶│  Render form with field schema │
│  "Edit Profile"   │     │  profile_form(p_user_id)      │     │  + current values              │
└──────────────────┘     └───────────────────────────────┘     └────────────────────────────────┘
                                                                           │
                                                                           ▼
┌──────────────────┐     ┌───────────────────────────────┐     ┌────────────────────────────────┐
│  Refresh 360     │◀────│  bff_admin_update_member_      │◀────│  Admin modifies fields          │
│  dashboard data   │     │  profile(p_user_id, p_data)   │     │  and clicks Save               │
└──────────────────┘     └───────────────────────────────┘     └────────────────────────────────┘
```

### Step 1: Get Editable Form

```
POST /rest/v1/rpc/bff_admin_get_member_profile_form

Parameters:
- p_user_id: UUID (target member)
- p_language: TEXT (default: 'en')

Headers:
- Authorization: Bearer {admin_jwt}
- x-merchant-id: {uuid}
```

#### What It Returns

The same structure as the user-facing `bff_get_user_profile_template(mode='edit')` but:

- Filtered to fields where `visible_to_admin = true`
- Each field includes `editable_by_admin` flag (FE uses this to enable/disable inputs)
- Values are populated from the target `p_user_id` (not from `auth.uid()`)
- No PDPA/consent section (admin edits don't modify consent)
- No persona section (persona changes are a separate workflow)

#### Response Shape

```json
{
  "success": true,
  "data": {
    "user_id": "uuid",
    "user_image": "url",
    "user_fullname": "Siriporn Thongsuk",
    "default_fields_config": [{
      "id": "default-fields-group",
      "group_key": "default_fields",
      "group_name": "Default Fields",
      "order_index": 0,
      "fields": [{
        "id": "uuid",
        "field_key": "email",
        "field_type": "email",
        "label": "Email Address",
        "placeholder": "email@example.com",
        "order_index": 1,
        "is_required": true,
        "editable_by_admin": true,
        "options": [],
        "is_address_field": false,
        "value": "siriporn.t@example.com"
      }, {
        "id": "uuid",
        "field_key": "gender",
        "field_type": "select",
        "label": "Gender",
        "order_index": 5,
        "is_required": false,
        "editable_by_admin": true,
        "options": [
          {"value": "male", "label": "Male"},
          {"value": "female", "label": "Female"},
          {"value": "other", "label": "Other"}
        ],
        "value": "female"
      }]
    }],
    "custom_fields_config": [{
      "id": "uuid",
      "group_key": "preferences",
      "group_name": "Preferences",
      "order_index": 1,
      "fields": [{
        "id": "uuid",
        "field_key": "interests",
        "field_type": "multi-select",
        "label": "Interests",
        "order_index": 0,
        "is_required": false,
        "editable_by_admin": true,
        "options": [
          {"id": "uuid", "option_value": "fashion", "option_label": "Fashion"},
          {"id": "uuid", "option_value": "food", "option_label": "Food & Dining"}
        ],
        "conditions": [],
        "value": ["fashion"]
      }]
    }],
    "language": "en",
    "timestamp": "2026-03-31T..."
  }
}
```

### Step 2: Save Profile Changes

```
POST /rest/v1/rpc/bff_admin_update_member_profile

Parameters:
- p_user_id: UUID (target member)
- p_data: JSONB (same shape as the form from step 1, with modified values)

Headers:
- Authorization: Bearer {admin_jwt}
- x-merchant-id: {uuid}
```

#### How It Works

1. Validates admin auth + permission (`customer-360.update`, `front_line.update`, `event.update`, or `grower_registration.update`)
2. Validates target user exists in merchant
3. Loads the **allowed** field keys from config:
   - Default fields: `user_field_config` where `editable_by_admin = true` AND `visible_to_admin = true` — for all four permissions above (event / grower-registration staff edit from admin forms such as order booking). Callers with none of them never reach this step.
   - Custom fields: `form_fields` where `editable_by_admin = true` AND `visible_to_admin = true` for `customer-360.update` / `front_line.update`; event / grower-registration-only callers use `visible_to_user = true`
4. For each submitted default field:
   - Skips if field_key is not in the allowed list
   - **Exception:** `line_id` with an empty value is always accepted for `customer-360.update` / `front_line.update`, even when `line_id` is inactive in `user_field_config` (identity unlink, not a profile field)
   - Extracts value and maps to `user_accounts` / `user_address` columns
5. Uniqueness checks on email, phone, line_id (same as user self-service)
6. Updates `user_accounts` (only submitted + allowed fields, others untouched)
   - **Clearable fields**: `line_id` can be set to NULL by submitting an empty value (admin can unlink a LINE account). Most other identity fields (`tel`, `email`) use COALESCE to prevent accidental null-out.
7. Upserts `user_address` if address fields present
8. For each submitted custom field:
   - Skips if field_id is not in the allowed list
   - Upserts into `form_responses` via the USER_PROFILE form submission

#### Response

```json
{
  "success": true,
  "title": "Profile updated",
  "description": "Member profile updated by John Admin",
  "data": {
    "user_id": "uuid",
    "admin_user_id": "uuid",
    "fields_updated": ["email", "firstname", "lastname", "fullname"]
  }
}
```

### Field Editability Configuration

#### Default Fields (`user_field_config`)

| Column | Type | Default | Purpose |
|--------|------|---------|---------|
| `visible_to_user` | boolean | true | Show to end user in signup/edit form |
| `editable_by_user` | boolean | true | Write-once for the member: empty → first fill is allowed; after a value exists, member updates are stripped (`fn_strip_locked_profile_payload`). Phone / LINE stay locked after auth because they are already filled. |
| `visible_to_admin` | boolean | true | Show to admin in member 360 |
| `editable_by_admin` | boolean | true | Allow admin to modify |

#### Custom Fields (`form_fields`)

| Column | Type | Default | Purpose |
|--------|------|---------|---------|
| `visible_to_admin` | boolean | true | Show to admin in member 360 |
| `editable_by_admin` | boolean | true | Allow admin to modify |

These columns are configurable per merchant via `bff_admin_upsert_user_profile_config` (existing function).

#### Example Configurations

| Field | User Can See | User Can Edit | Admin Can See | Admin Can Edit |
|-------|:---:|:---:|:---:|:---:|
| Email | ✅ | ✅ | ✅ | ✅ |
| Phone | ✅ | ❌ | ✅ | ✅ |
| Birth Date | ✅ | ✅ | ✅ | ❌ |
| Internal ID | ❌ | ❌ | ✅ | ✅ |
| ID Card | ✅ | ✅ | ✅ | ❌ |

---

## 5. Staff remarks (member notes)

Append-only remarks on a loyalty member. Not a profile field — multiple rows per user, each with `created_at` and author.

**Table:** `user_notes` (`merchant_id`, `user_id`, `body`, `created_at`, `created_by_admin_id`)

**Read:** `bff_admin_get_member_360` returns `data.notes[]` (`id`, `body`, `created_at`, `created_by_admin_id`, `created_by_name`), newest first, cap 50.

**Write:** `bff_admin_create_user_note(p_user_id, p_body, p_language)` — isolated from `bff_admin_update_member_profile`. Permission: `customer-360.update` or `front_line.update`. Body required, max 2000 chars.

**Removal:** `admin_remove_user` deletes the member's notes.

**Surfaces:** Front Line member header + Customer 360 Profile tab (display). Edit Profile panel (add).

---

## Customer 360 Integration

### Page Architecture

The Customer 360 dashboard loads data via **4 parallel RPC calls** when the page opens:

| Call | Function | Data |
|------|----------|------|
| 1 | `bff_admin_get_member_360` | Profile, tier, wallet, charts, activity stream, staff remarks (`data.notes`) |
| 2 | `bff_admin_get_user_packages` | Packages and entitlements |
| 3 | `bff_admin_get_user_benefits` | Active benefits |
| 4 | `bff_get_user_missions` | Mission progress |

On-demand cards (not in the initial parallel load):

| Call | Function | Data |
|------|----------|------|
| Wallet history | `bff_admin_get_member_wallet_history` | Paginated `wallet_ledger` rows (`all` \| `points` \| `ticket`). Processing-receipt deletes are not wallet events and are omitted. |
| Redeemed rewards | `admin_get_user_redemptions` | Tabs: `my_reward` (unused) / `used` (already used) |

None of the initial 4 calls are modified. Frontline admin actions and the cards above are **additional calls** triggered by user interaction.

### Separation of Concerns

Each mutation is a standalone call. The FE should never batch these — call one, wait for success, then refresh.

| Action | Call | Refreshes |
|--------|------|-----------|
| Adjust currency | `bff_admin_adjust_currency` | Wallet + activity stream |
| Adjust tier | `bff_admin_adjust_member_tier` | Tier card + history |
| Add / remove tag | `bff_admin_assign_member_tag` | Tag chips (immediate) |
| Change mobile | `bff_admin_change_member_mobile` | Profile header |
| Change persona | `bff_admin_change_member_persona` | Profile header + benefits |
| Edit profile fields | `bff_admin_update_member_profile` | Profile header |

### Adjust Currency — Integration

**Flow:** Admin triggers adjustment → call `bff_admin_adjust_currency` → on success, re-fetch `bff_admin_get_member_360` to refresh wallet balance and activity stream.

**Payload example (add 500 points):**

```json
{
  "p_user_id": "member-uuid",
  "p_currency": "points",
  "p_transaction_type": "earn",
  "p_amount": 500,
  "p_reason": "Goodwill credit - delayed delivery complaint #CS-4521"
}
```

**Payload example (deduct 3 tickets):**

```json
{
  "p_user_id": "member-uuid",
  "p_currency": "ticket",
  "p_transaction_type": "burn",
  "p_amount": 3,
  "p_reason": "Correction - tickets awarded in error",
  "p_target_entity_id": "ticket-type-uuid"
}
```

### Change Mobile — Integration

**Flow:** Admin triggers mobile change → call `bff_admin_change_member_mobile(p_user_id, p_tel)` → on success, re-fetch `bff_admin_get_member_360` to refresh profile header.

### Change Persona — Integration

**Flow:** Admin triggers persona change → call `bff_admin_change_member_persona(p_user_id, p_persona_id)` → on success, re-fetch `bff_admin_get_member_360` (profile header) and `bff_admin_get_user_benefits` (benefits may change with persona).

### Edit Profile — Integration

**Flow:**
1. Admin triggers edit → call `bff_admin_get_member_profile_form(p_user_id)` to get field schema + current values
2. FE renders form dynamically from the response. Each field has `editable_by_admin` — if `false`, the field should be read-only.
3. Admin modifies fields → call `bff_admin_update_member_profile(p_user_id, p_data)` to save
4. On success → re-fetch `bff_admin_get_member_360` to refresh profile display

**Key response properties for rendering:**
- `field_type` — determines input type: `normal`, `email`, `phone`, `date`, `select`, `multi-select`
- `text_format` — additional format context for `normal` fields
- `options[]` — choices for `select` and `multi-select` fields
- `conditions[]` — conditional show/hide/require logic (same as user-facing form)
- `is_required` — validation flag
- `is_address_field` — groups address-related fields

**Save payload shape** (same structure as the form response, with modified values):

```json
{
  "p_user_id": "member-uuid",
  "p_data": {
    "default_fields_config": [{
      "id": "default-fields-group",
      "fields": [
        { "field_key": "email", "value": "new-email@example.com" },
        { "field_key": "firstname", "value": "Siriporn" },
        { "field_key": "lastname", "value": "Thongsuk-Smith" }
      ]
    }],
    "custom_fields_config": [{
      "id": "group-uuid",
      "fields": [
        { "field_key": "interests", "value": ["fashion", "food", "sports"] }
      ]
    }]
  }
}
```

**Clear LINE ID payload** (send empty string to unlink):

```json
{
  "p_user_id": "member-uuid",
  "p_data": {
    "default_fields_config": [{
      "id": "default-fields-group",
      "fields": [
        { "field_key": "line_id", "value": "" }
      ]
    }]
  }
}
```

---

## Function Index

| Function | Type | Purpose |
|----------|------|---------|
| `bff_admin_adjust_currency` | BFF | Admin: adjust points or tickets for a member |
| `bff_admin_adjust_member_tier` | BFF | Admin HQ: assign tier + downgrade lock (`customer-360.update` only) |
| `bff_admin_get_member_tier_form` | BFF | Admin HQ: assignable ladder + current lock |
| `bff_admin_assign_member_tag` | BFF | C360 or Front Line: add/remove `user_tags` via `assign_tag` |
| `bff_admin_get_member_wallet_history` | BFF | Admin: paginated wallet ledger for a member (Customer 360 / Front Line Adjust Points); omits Front Line Processing deletes (no points moved) |
| `admin_get_user_redemptions` | Admin | Admin: member redemptions (`my_reward` / `used` / `history` / `all`) |
| `bff_admin_change_member_mobile` | BFF | Admin: change member phone number (isolated) |
| `bff_admin_change_member_persona` | BFF | Admin: change member persona assignment (isolated) |
| `bff_admin_get_member_profile_form` | BFF | Admin: get editable profile form schema + values |
| `bff_admin_update_member_profile` | BFF | Admin: save profile field changes for a member |
| `bff_admin_create_user_note` | BFF | Admin: append a staff remark on a member |
| `bff_admin_get_member_360` | BFF | Admin: member 360 payload including `data.notes` |

### Dependencies

| Function | Depends On |
|----------|------------|
| `bff_admin_adjust_currency` | `chokepoint_post_wallet_transaction`, `admin_users`, `admin_roles`, `user_accounts`, `user_wallet`, `user_ticket_balances` |
| `bff_admin_change_member_mobile` | `admin_users`, `admin_roles`, `user_accounts` |
| `bff_admin_change_member_persona` | `admin_users`, `admin_roles`, `user_accounts`, `assign_persona`, `persona_master`, `persona_group_master` |
| `bff_admin_get_member_profile_form` | `user_field_config`, `form_templates`, `form_field_groups`, `form_fields`, `form_field_options`, `form_conditions`, `form_submissions`, `form_responses`, `translations` |
| `bff_admin_update_member_profile` | `user_field_config`, `form_fields`, `user_accounts`, `user_address`, `form_submissions`, `form_responses` |
| `bff_admin_create_user_note` | `user_notes`, `admin_users`, `user_accounts` |
| `bff_admin_get_member_360` | `fn_admin_list_user_notes` (attaches `data.notes`) |

### Schema Additions

| Table | Column | Type | Default | Purpose |
|-------|--------|------|---------|---------|
| `user_notes` | (table) | — | — | Append-only staff remarks per member |
| `user_field_config` | `editable_by_admin` | boolean | true | Controls whether admin can edit this default field |
| `form_fields` | `visible_to_admin` | boolean | true | Controls whether admin sees this custom field |
| `form_fields` | `editable_by_admin` | boolean | true | Controls whether admin can edit this custom field |

---

## Error Handling

All three functions return the standard response envelope:

**Success:**
```json
{
  "success": true,
  "title": "...",
  "description": "...",
  "data": { ... }
}
```

**Error:**
```json
{
  "success": false,
  "title": "Error title",
  "description": "Human-readable explanation",
  "data": { "error_code": "..." }
}
```

### Common Error Codes

| Scenario | Title | When |
|----------|-------|------|
| Not logged in | "Authentication required" | No JWT |
| Not admin | "Access denied" | Caller is not owner/admin role |
| User not found | "User not found" | Target user_id not in merchant |
| Duplicate email | "Email already in use" | Email belongs to another member |
| Duplicate phone | "Phone already in use" | Phone belongs to another member |
| Duplicate LINE | "LINE already in use" | LINE ID belongs to another member |
| Insufficient balance | "Adjustment failed" | Deducting more than available balance |
| Missing reason | "Reason required" | Empty reason on currency adjustment |
