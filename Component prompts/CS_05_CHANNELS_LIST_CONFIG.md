# CS Channels — List + Config

## What This Is

Channel management for connecting the brand's messaging platforms to the CS system. Each channel is a configured connection to an external messaging platform (Shopee, Lazada, TikTok Shop, LINE, WhatsApp, Facebook Messenger, Instagram DM, email, web chat widget, voice).

- **List page** — Overview of all connected channels, their status, and health
- **Config page** — Connect a new channel or edit an existing connection's settings

The AI in this project should use its own judgment for what UI layout and interaction patterns produce the best UX for **managing omnichannel messaging integrations**. Study how Respond.io, Zaapi, or Freshdesk's channel management works — then decide the best structure.

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
src/app/(admin)/cs-channels/           → Channel list
src/app/(admin)/cs-channels/[id]/      → Channel config (connect/edit)
```

---

## Backend Connection — Tables & RPCs

### Core Table

Channels use the existing **`merchant_credentials`** table (shared with loyalty integrations) with CS-specific columns added:

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `merchant_id` | uuid FK | |
| `credential_type` | text | `shopee`, `lazada`, `tiktok`, `line`, `whatsapp`, `facebook`, `instagram`, `email`, `web_widget`, `voice` |
| `credential_name` | text | Display name: "Shopee Store: Rocket Innovation" |
| `credentials` | jsonb (encrypted) | Platform-specific: app_key, app_secret, access_token, shop_id, etc. |
| `scope` | text | `loyalty`, `cs`, `both` — which module uses this connection |
| `channel_config` | jsonb | CS-specific: `{session_timeout, threading_interval, auto_reply_enabled, ai_enabled, voice_preset_override, message_format_rules}` |
| `webhook_url` | text | Auto-generated webhook URL for receiving messages |
| `is_active` | boolean | |
| `last_health_check` | timestamptz | |
| `health_status` | text | `healthy`, `degraded`, `disconnected`, `error` |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |

### RPCs

| RPC | Purpose | Notes |
|---|---|---|
| `cs_bff_get_channels` | List all CS channels | Returns channels where scope='cs' or scope='both'. Includes health_status, message counts, last activity. |
| `cs_bff_get_channel` | Get channel detail | Params: credential_id. Returns full config for edit (credentials redacted for display). |
| `cs_bff_upsert_channel` | Connect/update channel | Params: credential_type, credentials, channel_config. Backend validates credentials (test API call), sets up webhook. |
| `cs_bff_test_channel` | Test connection health | Params: credential_id. Backend pings the platform API and returns status. |
| `cs_bff_disconnect_channel` | Deactivate channel | Params: credential_id. Sets is_active=false. Does NOT delete — conversations remain. |
| `cs_bff_get_channel_stats` | Channel usage stats | Params: credential_id, date_range. Returns: conversation count, message count, avg response time per channel. |

**Direct CRUD (use `supabase.from()`):**
- Disconnect channel: `supabase.from('merchant_credentials').update({ is_active: false }).eq('id', credentialId)`
- Get single channel: `supabase.from('merchant_credentials').select('*').eq('id', credentialId).single()`

**RPCs (use `supabase.rpc()`):**
- `cs_bff_get_channels` — channels with conversation counts + last activity (joins)
- `cs_bff_upsert_channel` — connect/update with webhook URL generation
- `cs_bff_get_channel_stats` — aggregate conversation/message counts per channel

---

## Key Domain Concepts the UI Must Support

### 1. Channel Types and Their Setup

Each channel type has different credential requirements and configuration options:

| Channel Type | Credentials Needed | Specific Config |
|---|---|---|
| **Shopee** | App key, app secret, shop_id, partner_id | Session: follows platform threading. Rate limits apply. |
| **Lazada** | App key, app secret, seller center access | Similar to Shopee |
| **TikTok Shop** | App key, app secret, shop_id | 12-hour response SLA enforced by platform |
| **LINE OA** | Channel access token, channel secret | Session timeout (default 24h), threading interval (48h), rich menu support, flex message support |
| **WhatsApp** | Business API credentials via Twilio/Meta | 24-hour messaging window, template messages for outbound |
| **Facebook Messenger** | Page access token, app ID | Persistent menu, handover protocol |
| **Instagram DM** | Connected via Facebook, page access token | Story replies, quick replies, ice breakers |
| **Email** | IMAP/SMTP or Gmail/Outlook API | Threading interval (72h), signature management, HTML rendering |
| **Web Chat Widget** | Auto-generated (embed code) | Widget customization: colors, position, avatar, greeting, pre-chat form, proactive triggers |
| **Voice (SIP)** | Twilio SIP credentials | IVR config, hold music, transfer settings |

### 2. Channel Health Monitoring

Each channel shows:
- Connection status (healthy / degraded / disconnected / error)
- Last successful message sent/received
- Error details if unhealthy
- Quick "Test Connection" action

### 3. Per-Channel Configuration

Beyond credentials, each channel has behavioral config:
- **Session timeout** — How long before an idle conversation auto-closes
- **Threading interval** — After resolution, how long before a new message creates a new conversation vs reopening
- **AI enabled** — Whether AI agent handles messages on this channel
- **Auto-reply** — Default auto-reply when outside business hours
- **Voice/tone override** — Channel-specific voice (e.g., LINE = casual, email = formal)

### 4. Web Widget Customization

The web chat widget has its own config UI:
- Brand colors, position (bottom-right, bottom-left)
- Avatar image, greeting message
- Pre-chat form fields (name, email, topic)
- Proactive triggers (show widget after X seconds, on specific URLs, on exit intent)
- Embed code snippet for the brand to copy

---

## Key UX Requirements

1. The channel list should feel like a dashboard — at a glance, see which channels are connected, healthy, and active.

2. Connecting a new channel should be a guided flow — select platform, enter credentials, test, configure, activate.

3. Credential fields should be masked/secure. Show only last 4 characters of secrets.

4. Web widget configuration should include a live preview of the widget.

---

## What NOT to Build (Backend Handles These)

- Webhook registration with platforms — backend registers webhooks when channel is connected
- OAuth flows with platforms — backend handles OAuth redirect/callback
- Message routing — backend routes messages based on channel type
- Platform-specific message formatting — backend adapts messages for each platform
