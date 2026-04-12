# Integration Hub — List + Config

## What This Is

**This replaces both the old integration config page AND the CS Channels page (`CS_05_CHANNELS_LIST_CONFIG.md`) with a single unified Integration Hub.** All external connections — commerce platforms, messaging channels, auth providers, marketplace APIs — are managed from one place.

- **List page** — All integrations for this merchant, grouped by category, with status and health
- **Config modal** — Large modal (or drawer) to configure a platform. Platforms with multiple app types (e.g. LINE has Login + Messaging) show **tabs** inside the modal — one tab per app type. Each tab is backed by its own `integration_key` and credential row, loaded and saved independently.

The old `cs-channels/` routes should redirect here. Channel-specific config (CS session timeout, threading, AI toggle) stays as a section within the config modal for integrations that have CS scope.

---

## FE Project Context

| Layer | Tech |
|---|---|
| Framework | Next.js 16 (App Router, React 19) |
| UI | Shopify Polaris v13 (the only component library) |
| Backend | Complex operations via `supabase.rpc()`. Simple reads/writes via `supabase.from()` (RLS handles merchant scoping). |
| Auth | Supabase Auth, JWT carries merchant context |
| Forms | `react-hook-form` + `zod` |

### Routes

```
src/app/(admin)/integrations/              → Integration hub list
```

The config is a **modal** (not a separate route). Opening an integration opens the config modal in-place. No `[id]` route needed unless you prefer URL-driven modals.

---

## Backend Connection — Tables & RPCs

### Core Tables

**`merchant_credentials`** — One row per integration connection per merchant.

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `merchant_id` | uuid FK | |
| `service_name` | text | Integration key: `line_login`, `line_messaging`, `bigcommerce`, `shopify_app`, `shopee_marketplace`, `shopee_chat`, `lazada_marketplace`, `lazada_chat`, `tiktok_marketplace`, `tiktok_chat`, etc. |
| `credentials` | jsonb | All secrets + config values. Shape varies per integration type. |
| `environment` | text | `production` (default), `staging`, `development`, `test` |
| `is_active` | boolean | default true |
| `expires_at` | timestamptz | Optional credential expiry |
| `external_id` | text | Optional external reference |
| `credential_name` | text | Display name (e.g. "LINE OA: @brand_th") |
| `scope` | text[] | Which modules use this: `'{earn}'`, `'{cs}'`, `'{earn,cs}'` |
| `channel_config` | jsonb | CS-specific behavioral config (session_timeout, threading_interval, ai_enabled, auto_reply, voice_override) |
| `webhook_url` | text | Auto-generated webhook URL for messaging channels |
| `health_status` | text | `healthy`, `degraded`, `disconnected`, `error` |
| `last_health_check` | timestamptz | |
| `updated_at` | timestamptz | |

**No unique constraint** — the `(merchant_id, service_name, environment)` constraint has been dropped to allow multiple credential rows per platform. A non-unique index exists for query performance.

**`integration_type_master`** — Registry of known integration types.

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `integration_key` | text | `line_login`, `line_messaging`, `bigcommerce`, `shopify_app`, `shopee_marketplace`, `shopee_chat`, `lazada_marketplace`, `lazada_chat`, `tiktok_marketplace`, `tiktok_chat` (matches `service_name` in credentials) |
| `display_name` | text | Human label: "LINE Login", "LINE Messaging", "BigCommerce Integration", "Shopify" |
| `description` | text | One-liner description |
| `platform_key` | text | UI grouping key: `line`, `bigcommerce`, `shopify`, `shopee`, `lazada`, `tiktok` |
| `platform_name` | text | UI group label: "LINE", "BigCommerce", "Shopify", "Shopee", "Lazada", "TikTok" |
| `platform_order` | integer | Sort order for platform groups in the list |
| `public_fields` | text[] | Field names safe to expose in public API |
| `sensitive_fields` | text[] | Field names that must be masked |

**`integration_field_definitions`** — Per-type field schema. Drives the entire config form dynamically.

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `integration_type_id` | uuid FK → integration_type_master | |
| `field_path` | text | Storage path: `channel_id` (flat) or `bigcommerce.footerInfo.facebook` (nested) |
| `field_name` | text | Flat key used in FE form state and upsert payload |
| `data_type` | text | `string`, `boolean`, `array` |
| `is_required` | boolean | |
| `expose_in_public_api` | boolean | false = sensitive, show as `***` |
| `display_title` | text | Label shown in UI |
| `input_type` | text | `normal`, `password`, `email`, `tel`, `select`, `multi-select` |
| `select_options` | jsonb | For select/multi-select: `[{"label": "Yes", "value": "true"}]` |
| `group_key` | text | Section identifier within the config form |
| `group_name` | text | Section heading: "General Settings", "API Credentials" |
| `group_order` | integer | Section sort order |
| `field_order` | integer | Field sort order within the group |

### RPCs

#### Admin UI RPCs (used by this page)

| RPC | Purpose | Params | Notes |
|---|---|---|---|
| `bff_get_integration_config` | Get config for one integration | `p_integration_key text` | Returns `{structure, fields, current_values, platform_key, platform_name}`. Structure is **group → fields** hierarchy (no module layer). Sensitive values masked as `***`. |
| `bff_upsert_integration_config` | Save config | `p_integration_key text, p_config jsonb` | Accepts flat `{field_name: value}`. Skips `***` values (unchanged secrets). Maps to nested storage via `field_path`. |
| `cs_bff_get_channels` | List CS channels | (none) | Returns credentials where scope includes `cs`, with health_status, conversation counts, last activity. |
| `cs_bff_upsert_channel` | Save CS channel config | `p_credential_id, p_credential_type, p_credential_name, p_credentials, p_channel_config, p_scope` | For CS-specific fields (channel_config, scope, webhook). |
| `cs_bff_get_channel_stats` | Channel usage stats | `p_credential_id, p_days` | Conversation count, message count, avg response time. |

#### Runtime RPCs (DO NOT CHANGE — external systems depend on these)

| RPC | Purpose |
|---|---|
| `get_merchant_credentials` | Returns raw credential row by merchant_code + service_name. Alias: `'LINE'` → `'line_login'`. |
| `fn_get_merchant_credentials_cached` | Same but with Redis cache (30min TTL). Alias: `'LINE'` → `'line_login'`. Used by messaging-service. |
| `get_shop_credentials` | Marketplace variant (by external_id + platform) |

---

## Data Flow

### GET (loading config modal)

```
1. FE calls bff_get_integration_config("line_login")
2. Response shape:
   {
     success: true,
     data: {
       integration_key: "line_login",
       display_name: "LINE Login",
       platform_key: "line",
       platform_name: "LINE",
       fields: [                          // flat array of all fields with current values
         { field_name, data_type, is_required, is_sensitive, group_key, value }
       ],
       structure: [                       // group → fields hierarchy for rendering
         {
           group_key: "general",
           group_name: "General",
           group_order: 0,
           fields: [
             { title: "Channel Id", init_value: "channel_id", type: "normal", data_type: "string", is_required: true, is_sensitive: false },
             { title: "Channel Secret", init_value: "channel_secret", type: "normal", data_type: "string", is_required: true, is_sensitive: false }
           ]
         }
       ],
       current_values: {                   // flat field_name → value map (secrets masked)
         credential_id: "uuid",
         environment: "production",
         is_active: true,
         updated_at: "...",
         values: {
           channel_id: "1234567890",
           channel_secret: "***"
         }
       }
     }
   }
```

### SAVE (submitting config modal)

```
1. FE collects all field values into one flat object:
   { channel_id: "1234567890", channel_secret: "***" }

2. Call bff_upsert_integration_config("line_login", flat_config)

3. Backend:
   - Skips any field where value = "***" (unchanged secret)
   - Maps each field_name → field_path → nested position in credentials jsonb
   - Deep-merges into existing credentials blob
   - Upserts merchant_credentials row (matched by merchant_id + service_name)

4. Response: { success: true, data: { credential_id, was_created, field_count } }
```

### CS Channel Config (additional save for messaging channels)

For integrations that also serve as CS channels (LINE, WhatsApp, etc.), the modal has an **additional section or tab** for CS-specific config:

```
1. After saving credentials via bff_upsert_integration_config...
2. Call cs_bff_upsert_channel with channel_config (session_timeout, threading_interval, ai_enabled, etc.)
3. This updates the same merchant_credentials row (channel_config column, scope column)
```

---

## UI Structure

### List Page

**Layout:** Card grid or table, grouped by category.

**Grouping:** Use `platform_key` and `platform_order` from `integration_type_master` to group integration types by platform. Each platform can have multiple app types (e.g. LINE has `line_login` + `line_messaging`).

| Platform (`platform_key`) | Integration Keys | `platform_order` |
|---|---|---|
| `line` (LINE) | `line_login`, `line_messaging` | 0 |
| `bigcommerce` (BigCommerce) | `bigcommerce` | 1 |
| `shopify` (Shopify) | `shopify_app` | 2 |
| `shopee` (Shopee) | `shopee_marketplace`, `shopee_chat` | 3 |
| `lazada` (Lazada) | `lazada_marketplace`, `lazada_chat` | 4 |
| `tiktok` (TikTok) | `tiktok_marketplace`, `tiktok_chat` | 5 |

**Each integration card/row shows:**
- Integration icon + display name
- Status badge: Connected (green) / Disconnected (gray) / Error (red)
- Health status (for messaging channels): healthy / degraded / disconnected / error
- Scope badges: "Loyalty", "CS", "Both"
- Last updated timestamp
- For CS channels: conversation count, last activity

**Actions:**
- Click card → opens config modal
- "Add Integration" button → opens picker (select integration type first, then config modal)

**Data loading:**
1. Load all `merchant_credentials` for this merchant (direct table read with RLS, or a list BFF)
2. Load all `integration_type_master` rows — group by `platform_key`, sort by `platform_order`
3. Cross-reference credentials with types for display_name, platform grouping, etc.
4. For CS channels, supplement with `cs_bff_get_channels` data (conversation counts, health)

### Add Integration Flow

1. Click "Add Integration"
2. **Picker modal / step 1:** Grid of available integration types from `integration_type_master`. Show icon + display_name + description. Gray out already-connected ones (unless multiple instances allowed).
3. On select → **transition to config modal** (same shell, content swaps from picker to config form)
4. Config modal opens in "new" mode (no current_values)

### Config Modal (Add + Edit share same shell)

**Modal shell:**
- Header: Platform icon + platform name + status badge
- **App type tabs** (if platform has >1 app type): rendered from the integration types that share the same `platform_key`. E.g. LINE shows tabs: "Login" | "Messaging". BigCommerce has only one type, so no tab bar.
- Footer: Cancel + Save button (saves the **active tab** only)

**Each tab loads independently:**
- On tab switch, call `bff_get_integration_config(integration_key)` for that tab's type (e.g. `"line_login"` or `"line_messaging"`)
- Each tab has its own form state, its own credential row, its own save action

**Inside each tab:**
- Render groups from `structure[]`, ordered by `group_order`
- Each group = a titled section (use Polaris `LegacyCard` or `Box` with heading)
- Inside each group: render fields from `group.fields[]`, ordered as returned
- Field rendering by `type`:
  - `normal` → `TextField`
  - `password` → `TextField` with `type="password"` + reveal toggle. Show `***` for existing secrets.
  - `email` → `TextField` with `type="email"`
  - `tel` → `TextField` with `type="tel"`
  - `select` → `Select` with options from `field.options`
  - `multi-select` → `ChoiceList` with `allowMultiple`
- Mark required fields (from `is_required`)
- Sensitive fields show masked value; user must clear and re-enter to change

**For integrations with CS scope — additional "Channel Settings" section:**
- Session timeout (number input, minutes)
- Threading interval (number input, hours)
- AI enabled (toggle)
- Auto-reply enabled (toggle)
- Auto-reply message (text area)
- Voice/tone override (select: default / casual / formal)
- Webhook URL (read-only, with copy button)
- Health status (read-only badge)
- "Test Connection" button (calls `cs_bff_upsert_channel` test or a future test RPC)

**Example: LINE platform modal (2 tabs)**
- Tab bar: **"Login"** | **"Messaging"**
- Login tab (loads `line_login`): one group with channel_id, channel_secret
- Messaging tab (loads `line_messaging`): one group with messaging_channel_id, messaging_channel_secret, messaging_channel_access_token. If it has CS scope: "Channel Settings" section appears below the credential form.
- Switching tabs triggers a new `bff_get_integration_config` call. Save only affects the active tab.

**Example: Shopee platform modal (2 tabs)**
- Tab bar: **"Marketplace"** | **"Chat"**
- Marketplace tab (loads `shopee_marketplace`): marketplace credential fields
- Chat tab (loads `shopee_chat`): chat/CS credential fields

**Example: BigCommerce platform modal (no tabs — single app type)**
- No tab bar (only one type: `bigcommerce`)
- 12 groups render as collapsible sections or stacked cards

**Example: Shopify platform modal (no tabs — single app type)**
- No tab bar (only one type: `shopify_app`)
- One group: shop_domain, api_key, api_secret, access_token

### Edit Mode

Same modal as Add, but:
- `current_values.values` pre-fills the form
- Sensitive fields show `***` — user must explicitly clear to change
- Save sends all fields (including unchanged `***` ones — backend skips them)

---

## Form State Management

```typescript
// One form state PER TAB (per integration_key)
// The modal tracks which tab is active and maintains separate state per tab
interface TabFormState {
  [integration_key: string]: {
    [field_name: string]: string | boolean | string[]
  }
}

// On tab switch: load that tab's data via bff_get_integration_config(integration_key)
// On save: serialize the ACTIVE tab's state to flat { field_name: value }
//          and call bff_upsert_integration_config(active_integration_key, flat_config)
```

Each tab has its own flat form state. Switching tabs doesn't lose state (keep loaded tabs in memory). Save only affects the active tab.

---

## Key UX Requirements

1. **Single page for all integrations** — no separate "channels" page. Category grouping provides organization.

2. **Registry-driven forms** — the config modal renders entirely from `bff_get_integration_config` response. FE should NOT hard-code field lists per integration type. New integration types or fields added to the registry should render automatically.

3. **Platform grouping with app type tabs** — the list page groups by `platform_key`/`platform_name`. Clicking a platform opens one modal with tabs for each app type. Each tab is a separate `integration_key` with its own form and credential row.

4. **Credential security** — sensitive fields masked, never sent back in plain text, re-entry required to change.

5. **Scope awareness** — show which modules (Loyalty, CS) use each integration. CS-specific config (channel_config) only appears for integrations with CS scope.

6. **Non-breaking** — the config modal saves via `bff_upsert_integration_config` which writes to the same `credentials` JSONB blob. Runtime RPCs (`get_merchant_credentials`, `fn_get_merchant_credentials_cached`) are untouched and return the same data shape as before.

---

## What This Replaces

| Old | New |
|---|---|
| `src/app/(admin)/cs-channels/` (channel list) | Merged into Integration Hub list page (filtered by CS scope) |
| `src/app/(admin)/cs-channels/[id]/` (channel config) | Merged into Integration Hub config modal (CS tab/section) |
| Old integration config page (if any) | Merged into Integration Hub config modal |

The old `cs-channels` routes should **redirect** to the integrations page, or be removed entirely.

---

## Decisions

### 1. Unregistered integrations (credential rows with no registry entry)

Some merchants have credential rows with `service_name` values that don't match any `integration_key` in `integration_type_master` — e.g. `shopee`, `lazada`, `tiktok` (legacy names before the marketplace/chat split), `cognito_auth`, `CRM_v1`, `8x8`.

**Decision:** Show them on the list with a **"Legacy / No configurable fields"** fallback. They are active credentials that matter — hiding them makes them invisible to admins.

- Display them using `service_name` as the label (e.g. "shopee", "CRM_v1")
- Show "Connected" status badge if `is_active = true`
- Clicking opens a read-only detail view (no editable form since there are no field definitions)
- The detail shows: service_name, environment, is_active, scope, updated_at, and a raw JSON viewer for credentials (masked sensitive values)
- Do NOT show "Add Integration" for unregistered types — they only appear if a credential row already exists

### 2. Null scope

All existing credentials have `scope = null`.

**Decision:** Treat `null` scope as **"Loyalty"** (the original module — these credentials predate the scope column). Display rules:

| `scope` value | Badge | Meaning |
|---|---|---|
| `null` | "Loyalty" (gray) | Legacy — predates scope column |
| `'{earn}'` | "Loyalty" | Explicitly loyalty-only |
| `'{cs}'` | "CS" | CS-only |
| `'{earn,cs}'` | "Loyalty + CS" | Shared credential |

### 3. Add Integration picker

**Decision:** Show **only** types from `integration_type_master` (currently 10 types across 6 platforms). The picker is fully registry-driven — when new types are added to the master table, they appear automatically. No manual/hardcoded channel types.

Picker groups types by `platform_key`, sorted by `platform_order`. Within each platform, show each integration type as a selectable card.

Gray out types that are already connected for this merchant (check `merchant_credentials` for a matching `service_name`). Multiple instances of the same type are allowed (the unique constraint has been dropped), so "already connected" means show a count badge, not disable.

### 4. Navigation

**Decision:** Place under a **"Settings"** section in the sidebar nav.

```
Settings
  └── Integrations        ← /integrations/
```

This is an admin configuration page, not a day-to-day operational page. It sits alongside other settings (general config, display settings, etc.).

---

## What NOT to Build (Backend Handles These)

- Webhook registration with platforms — backend registers webhooks when channel is connected
- OAuth flows with platforms — backend handles OAuth redirect/callback
- Message routing — backend routes messages based on channel type
- Platform-specific message formatting — backend adapts messages for each platform
- Credential encryption — stored encrypted in DB, FE never sees raw secrets after initial save
- Cache invalidation — DB trigger auto-invalidates Redis cache when credentials change
