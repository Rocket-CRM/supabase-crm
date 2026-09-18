# Feature Guide: CS Channels

## 1. Overview

CS Channels is the multi-channel infrastructure that connects customer conversations from external messaging platforms into a unified inbox. Merchants connect channels — LINE, WhatsApp, Facebook Messenger, Instagram, Shopee, Lazada, TikTok Shop, email, web chat widget, and voice — and the system routes all inbound messages to a single workspace where AI or human agents respond.

The core problem channels solve: customers reach out from whichever platform they prefer, and the merchant needs one place to handle all of them. Beyond message routing, the channel layer handles identity resolution — mapping platform-specific identifiers (a Shopee buyer ID, a LINE user ID, a phone number) to a single contact record. One person messaging from LINE and Shopee is recognized as the same contact, with their conversation history and preferences unified.

Key capabilities: (1) **10 channel types** across marketplace chat, messaging platforms, email, web widget, and voice; (2) **identity resolution** — automatic lookup and creation of unified contact records from platform-specific user IDs; (3) **customer memory** — AI-extracted persistent facts (preferences, allergies, communication style) attached to the contact and injected into future conversations; (4) **credential sharing via scope** — a single credential row (e.g., LINE Official Account) can serve both CS and Earn modules simultaneously.

## 2. Key Concepts

**Channel** — A connected messaging platform configured with credentials and behavior settings. Stored as a row in `merchant_credentials` with `scope` including `cs`. Example: "LINE OA: @mesoestetic_th" with channel access token and session timeout of 30 minutes.

**Channel Type** — One of 10 supported platforms, organized into three categories: *marketplace* (shopee, lazada, tiktok), *messaging* (line, whatsapp, facebook, instagram), and *other* (email, web_widget, voice).

**Connect Method** — How a channel authenticates: `oauth` (marketplace channels — redirect flow), `credentials` (messaging/voice — manual token entry), or `auto` (web widget — no credentials needed).

**Health Status** — Connection state of a channel: `healthy` (working), `degraded` (intermittent issues), `disconnected` (not connected or deactivated), `error` (broken, needs attention).

**Contact** — A unified person record (`cs_contacts`) combining all platform identities for one individual under one merchant. Holds display name, email, phone, language, tags, and custom fields.

**Platform Identity** — A single platform-specific user ID linked to a contact (`cs_platform_identities`). One contact can have multiple: a Shopee buyer ID, a LINE user ID, and a phone number all pointing to the same person. Unique constraint: `(customer_id, platform_type, platform_user_id)`.

**Identity Resolution** — The automatic process of finding or creating a contact when a message arrives. Looks up the platform user ID → if found, routes to the existing contact; if not found, creates a new contact + platform identity row.

**Contact Merge** — Combining two contact records when they are discovered to be the same person. All platform identities, conversations, tickets, and memory from the secondary contact are re-pointed to the primary. The secondary is deleted.

**Customer Memory** — AI-extracted persistent facts about a contact, stored as key-value pairs with categories (health, preference, interest, logistics, issue, feedback, communication). Example: `{category: "health", key: "allergy", value: "Allergic to marine collagen", confidence: 0.95}`.

**Scope** — A `text[]` array on `merchant_credentials` that controls which modules share a credential. Valid values: `earn`, `cs`. A LINE OA credential with `scope = '{earn,cs}'` is used by both the Earn module (for push messages) and CS (for conversations).

**CRM User ID** — Optional link from a CS contact to a loyalty `user_master` record (`cs_contacts.crm_user_id`). Nullable — CS operates independently from loyalty. When linked, agents see loyalty data (tier, points) alongside conversation context.

**Session Timeout** — How long a conversation stays open after the last message before auto-closing. Configurable per channel: 15 minutes to 48 hours.

**Threading Interval** — Time window for grouping messages into the same conversation thread. Configurable: 1 hour to 72 hours. Messages arriving after the interval starts a new conversation.

**Behavior Config** — Per-channel settings stored in `channel_config` jsonb: session timeout, threading interval, auto-reply toggle + message, AI toggle, voice preset override.

## 3. Configuration Reference

### Channel Credentials (per channel type)

| Channel Type | Required Fields | Connect Method |
|---|---|---|
| Shopee | OAuth flow (no manual fields) | `oauth` |
| Lazada | OAuth flow | `oauth` |
| TikTok Shop | OAuth flow | `oauth` |
| LINE Official | Channel Access Token, Channel Secret | `credentials` |
| WhatsApp Business | Phone Number ID, Permanent Access Token, WABA ID | `credentials` |
| Facebook Messenger | Page Access Token, App ID, Page ID | `credentials` |
| Instagram DM | Page Access Token, Instagram Account ID | `credentials` |
| Email | Email Address, IMAP Host/Port, SMTP Host/Port, Password | `credentials` |
| Web Chat Widget | None (auto-generated) | `auto` |
| Voice (SIP) | Twilio Account SID, Auth Token, Phone Number | `credentials` |

### Behavior Settings

| Setting | What it controls | Options | Default |
|---|---|---|---|
| Session timeout | Auto-close idle conversations | 15min, 30min, 1h, 4h, 12h, 24h, 48h | — |
| Threading interval | Group messages into same thread | 1h, 6h, 12h, 24h, 48h, 72h | — |
| Auto-reply enabled | Send automatic response on first message | Toggle | Off |
| Auto-reply message | Text of the automatic response | Free text | — |
| AI enabled | Route to AI agent before human | Toggle | Off |
| Voice preset override | Custom voice profile for voice channels | Select | — |

### Phone Number Management (Voice/SMS)

| Setting | What it controls | Example |
|---|---|---|
| Provider | Telephony provider account | Twilio (BYOT or master subaccount) |
| Phone number | E.164 format number | +66812345678 |
| Capabilities | What the number supports | `{voice, sms}` |
| Friendly name | Merchant label | "Main Support Line" |

## 4. Admin Journey

**Repo:** `Rocket-CRM/loyalty-admin`

**Route map:**

| Page Name | Current Route | BFF / Data Source |
|---|---|---|
| Channel List | `/cs-channels` | `cs_bff_get_channels()` |
| Channel Config (new) | `/cs-channels/new` | Platform selector → credential form |
| Channel Config (edit) | `/cs-channels/{id}` | `merchant_credentials` direct query |
| Contact List | `/cs-customers` | `cs_contacts` direct table read |
| Contact Detail | `/cs-customers/{id}` | `cs_bff_get_contact_details()` |
| Integration Hub | `/integration` | `bff_get_integration_config()` |

### 4a. Connect a New Channel

1. From **Channel List**, click **"Connect channel"** button (or empty state CTA)
2. **Channel Config** opens — **Platform Selector** shows all 10 channel types grouped by category (Marketplace, Messaging, Other) as selectable cards
3. Select a platform → credential form renders dynamically based on the channel type
4. For *oauth* channels (Shopee, Lazada, TikTok): redirect to platform authorization flow
5. For *credentials* channels: fill in platform-specific fields (tokens, IDs, secrets)
6. For *web_widget*: no credentials needed — auto-generated embed code
7. Set channel display name and scope (defaults to `{cs}`)
8. Configure behavior settings: session timeout, threading interval, auto-reply, AI toggle
9. Click **"Save"** → credential saved to `merchant_credentials`, health set to `disconnected`
10. Run **"Test connection"** to verify → health updates to `healthy` on success

### 4b. Manage Channel List

1. **Channel List** displays cards grouped by category (Marketplace, Messaging, Other)
2. Each card shows: platform icon (color-coded), display name, channel type label, health badge, active/inactive status, last checked timestamp, AI badge if enabled
3. **Filters**: search by name/type, filter by channel type (multi-select), filter by health status (multi-select)
4. **Stats banner**: Connected count, Healthy count, Needs Attention count (shown only if > 0)
5. Click any card → navigates to **Channel Config** edit page
6. Card menu (three-dot): Edit settings, Test connection, Disconnect/Activate

### 4c. View Contact Details

1. From **Contact List**, click a contact row → **Contact Detail** opens
2. Shows: contact profile (name, email, phone, language, tags, custom fields), all linked platform identities, customer memory entries, recent 10 conversations
3. Agent can manually link/unlink platform identities, edit contact fields, delete memory entries

### 4d. Common Admin Mistakes

- Entering expired or revoked tokens → health stays `disconnected`, no error detail until test
- Setting scope to `{earn}` only → channel won't appear in CS channel list
- Forgetting to test connection after saving → messages won't route until health is verified
- Leaving AI enabled on a channel without configuring the AI agent → messages go to AI with no instructions

## 5. Customer Experience

**Note:** Customers interact via their native messaging platforms (LINE app, Shopee app, WhatsApp, etc.) — there is no dedicated CX Platform app for CS. The experience below describes what happens on the platform side.

**Route map:**

| Touchpoint | Platform | Identity Used |
|---|---|---|
| Marketplace chat | Shopee / Lazada / TikTok app | Buyer ID |
| Messaging | LINE / WhatsApp / Facebook / Instagram app | Platform user ID / phone |
| Email | Any email client | Email address |
| Web widget | Merchant's website | Session ID → email (via pre-chat form) |
| Voice | Phone call | Phone number |

### 5a. First Contact

1. Customer sends a message or initiates a call on any connected platform
2. Webhook delivers the message to the system with the platform user ID
3. Identity resolution runs: lookup `cs_platform_identities` for this platform + user ID
4. **New customer**: system creates a `cs_contacts` record + `cs_platform_identities` row, marks `is_new = true`
5. **Returning customer**: system retrieves the existing contact, loads customer memory into the AI prompt
6. Message is routed to the unified inbox as a new or continued conversation

### 5b. Cross-Platform Recognition

1. Customer who previously contacted via LINE now messages from Shopee
2. System creates a new platform identity (Shopee buyer ID) under a new contact initially
3. Auto-suggestion triggers if the Shopee buyer has the same phone or email as the LINE user: "This Shopee buyer has same phone as this LINE user — link?"
4. Agent confirms → `cs_fn_merge_contacts` re-points all identities, conversations, and memory to the primary contact
5. Future messages from either platform route to the same unified contact

### 5c. Conversation Continuity

1. Customer's prior memory (preferences, issues, communication style) is injected into the AI context
2. AI applies knowledge naturally — does not explicitly say "I remember you told me..."
3. If the conversation resolves, a separate async process extracts new persistent facts from the transcript and stores them as customer memory

## 6. Perspectives

### 6a. For Customer Success / Support

**Elevator pitch:** "Channels let you connect all your messaging platforms — LINE, WhatsApp, marketplace chats, email, even voice — into one inbox. When a customer messages from Shopee and later from LINE, the system recognizes them as the same person and keeps their history unified."

**Top support questions:**

| Question | Answer |
|---|---|
| "Channel shows disconnected" | Credentials may be expired or revoked. Go to Channel Config, re-enter credentials, run Test connection. |
| "Same customer appears twice" | Identity resolution created separate contacts. Go to Contact Detail, use the merge function to combine them. |
| "Customer memory is wrong" | Go to Contact Detail → memory section, delete the incorrect entry. New extraction will produce updated facts on the next resolved conversation. |
| "Messages not arriving from Shopee" | Check if the Shopee channel health is `healthy`. If `error`, re-authenticate via OAuth. Shopee requires whitelisted partner access. |
| "Can I use the same LINE account for CS and point notifications?" | Yes — set the credential scope to `{earn,cs}`. Both modules share the same LINE OA credential. |

### 6b. For Marketing

**Value proposition:** Channels provide true omnichannel reach — customers are met on the platform they already use (LINE in Thailand, WhatsApp in Southeast Asia, marketplace chat for post-purchase). Identity resolution means a customer who buys on Shopee and messages on LINE is one person in the system, enabling consistent communication across touchpoints.

**Channel coverage by use case:**
- **Post-purchase support** — Shopee, Lazada, TikTok Shop chat (buyer messages about orders)
- **Proactive outreach** — LINE push messages, WhatsApp template messages, email campaigns
- **Real-time support** — Web widget (on merchant site), Facebook Messenger, Instagram DM
- **Voice** — Inbound AI-powered calls with Thai/English speech recognition, outbound campaign calls

**Metrics that matter:** Channel coverage (% of customer platforms connected), first response time per channel, resolution rate per channel, contact merge rate (identity unification effectiveness).

### 6c. For Testers

**Config → expected behavior:**

| Config | Expected Behavior |
|---|---|
| Channel health = `healthy` | Inbound messages from this platform are received and routed |
| Channel health = `disconnected` | Inbound messages silently fail — no conversation created |
| Channel `is_active = false` | Channel appears in list with "Inactive" badge, messages not processed |
| `ai_enabled = true` | Messages route to AI agent before human assignment |
| `auto_reply_enabled = true` | First inbound message triggers auto-reply text |
| `scope = '{earn}'` only | Channel does NOT appear in CS channel list (`cs_bff_get_channels` filters by `cs` scope) |
| `scope = '{earn,cs}'` | Channel appears in both CS channel list and Earn channel configs |
| Session timeout = 30min | Conversation auto-closes 30 minutes after last message |

**Identity resolution assertions:**

- ASSERT: New platform user ID creates exactly 1 `cs_contacts` + 1 `cs_platform_identities` row
- ASSERT: Known platform user ID returns existing contact, does not create duplicate
- ASSERT: Merge re-points all platform identities from secondary to primary contact
- ASSERT: Merge re-points all conversations and memory from secondary to primary
- ASSERT: Merge deletes the secondary contact record
- ASSERT: Platform identity uniqueness enforced: `(customer_id, platform_type, platform_user_id)`

**Customer memory assertions:**

- ASSERT: Memory extraction upserts on `(contact_id, merchant_id, category, key)` — new key inserts, existing key updates
- ASSERT: Contradicting info overwrites old memory value
- ASSERT: Memory with `expires_at` is auto-deleted after expiration
- ASSERT: "Forget me" request deletes all memory for that contact (PDPA compliance)
- ASSERT: Memory is isolated per contact per merchant — no cross-merchant leakage

**Health status model:**

| Status | Meaning | Transition |
|---|---|---|
| `disconnected` | Initial state or manually deactivated | → `healthy` (on successful test) |
| `healthy` | Connection verified, messages flowing | → `degraded` / `error` (on failure detection) |
| `degraded` | Intermittent issues detected | → `healthy` (on recovery) / `error` (on sustained failure) |
| `error` | Broken connection, needs re-authentication | → `healthy` (after credential fix + test) |

**Error states to test:**
- Invalid credentials saved → test connection fails, health stays `disconnected`
- OAuth token expired (marketplace) → messages stop arriving, health degrades to `error`
- Concurrent messages from same platform user → exactly one contact created (no race condition duplicates)
- Merge two contacts where secondary has conversations → all conversations accessible from primary
- WhatsApp 24-hour window expired → outbound template messages required, free-form blocked
- TikTok Shop 12-hour response SLA → alert if approaching deadline

## 7. Business Rules

**Rule:** One unified contact per person per merchant. Multiple platform identities point to the same `cs_contacts` row. Cross-merchant contacts are fully isolated.
**Example:** A person messaging from LINE and Shopee for Merchant A = one contact. The same person messaging Merchant B = a separate contact.

**Rule:** Identity resolution is automatic on every inbound message. The lookup key is `(platform_type, platform_user_id, merchant_id)`.
**Example:** Shopee buyer "abc123" sends a message → system queries `cs_platform_identities` → found → routes to existing contact.

**Rule:** Cross-platform linking requires matching phone, email, or manual agent confirmation. The system auto-suggests but does not auto-merge.
**Example:** Shopee buyer has phone +66812345678, same as existing LINE contact → system suggests link, agent confirms.

**Rule:** `crm_user_id` is nullable. CS operates independently from the loyalty module. When linked, loyalty data (tier, points, history) enriches the agent workspace.
**Example:** Contact without `crm_user_id` → agent sees conversation history and memory only. With `crm_user_id` → agent also sees loyalty tier and point balance.

**Rule:** Customer memory has configurable expiration (default 1 year). Expired memory is auto-deleted. Contradicting facts overwrite previous entries.
**Example:** Memory `{key: "skin_type", value: "oily"}` → customer later says "my skin has become dry" → value updates to "dry".

**Rule:** Memory extraction is async — runs after conversation resolves, not during. Uses a separate LLM call on the transcript.
**Example:** 30-message conversation resolves → LLM extracts 3 memory entries → stored in `cs_customer_memory`.

**Rule:** Credential scope controls module visibility. Only credentials with `scope && ARRAY['cs']` appear in the CS channel list. A credential can serve multiple modules simultaneously.
**Example:** LINE OA with `scope = '{earn,cs}'` → visible in CS Channels and in Earn channel config.

**Rule:** Marketplace channels enforce platform-specific session timeouts. Shopee and TikTok: 7 days inactive. WhatsApp: 24-hour messaging window for outbound.
**Example:** WhatsApp customer last messaged 25 hours ago → merchant cannot send free-form message, must use approved template.

## 8. Related Features

| Feature | Connection to CS Channels |
|---|---|
| CS Conversations | Conversations are created on channels — each conversation has a `credential_id` linking to the channel. See `CS_Conversations.md`. |
| CS Knowledge Base | Knowledge articles are referenced by AI during conversations on any channel. See `CS_Knowledge_Base.md`. |
| CS Procedures | AI follows procedures (AOPs) during channel conversations. See `CS_Procedures.md`. |
| Loyalty (Currency/Tier) | `crm_user_id` bridges CS contacts to loyalty users, enriching agent context with points and tier data. See `Currency.md`, `Tier.md`. |
| Integration Hub | Channel credentials are stored in `merchant_credentials`, the same table used by the Integration Hub for all platform connections. See Integration Hub docs. |
| Activity/Earning | Earn module can share channel credentials (e.g., LINE OA) via the `scope` array for push notifications. See `Activity_Based_Earning.md`. |
