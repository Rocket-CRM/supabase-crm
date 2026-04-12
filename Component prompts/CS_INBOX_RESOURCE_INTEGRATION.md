# CS Inbox — Resource Content Integration

> **What:** Add resource browsing and sending to the CS Inbox composer. Agents can browse the content library and send rich content (cards, carousels, lists, etc.) to customers. Rich content renders as platform-native format at delivery time.

---

## FE Project Context

Same stack as `CS_01_INBOX_INTEGRATED_CHAT.md`:

| Layer | Tech |
|---|---|
| Framework | Next.js 16 (App Router, React 19) |
| UI | Shopify Polaris v13 |
| Chat UI | **assistant-ui** (`ExternalStoreRuntime`) |
| Backend | `supabase.rpc()` for reads, `cs-send-message` edge function for sends |

---

## What Changes in the Inbox

### 1. Composer — Add "Resource" Action Button

The assistant-ui Composer already has action buttons (attach image, send note). Add a new **"Resource"** button that opens a resource browser popover/modal.

**Resource Browser UX:**
- Opens as a slide-over panel or modal from the composer
- Tabs or filter for resource types: Quick Reply | Media | Link | Rich Content
- Category filter dropdown (from `resource_content_category`)
- Search by name and `search_tags`
- Each resource shows: name, type badge, preview thumbnail, description snippet
- Click to preview full content → click "Send" to insert

**Data source:**

```typescript
// Fetch resources for the browser
const { data } = await supabase.rpc('bff_list_resource_content', {
  p_resource_type: 'rich_content',  // or null for all types
  p_category_id: selectedCategory,   // optional filter
  p_search: searchQuery,             // optional
  p_is_active: true,
  p_limit: 20,
  p_offset: 0,
})
```

**Auto-suggest (optional enhancement):**
Resources have `trigger_patterns[]`. When the agent types in the composer, match against trigger patterns of active resources and show a subtle suggestion bar: "📎 Suggested: Return & Exchange Guide". Agent clicks to preview/send.

### 2. Composer — Sending a Resource

When the agent selects a resource, send it via the dedicated `cs_bff_send_resource` RPC. This function handles everything — resolving the resource, checking channel restrictions, determining delivery mode (native catalog card vs rich content vs text fallback), inserting the message, and triggering platform delivery.

```typescript
const { data } = await supabase.rpc('cs_bff_send_resource', {
  p_conversation_id: conversationId,
  p_resource_id: resource.id,
})

if (data?.data?.message_id) {
  // Message sent + delivery triggered. Realtime subscription picks up the new message.
  // data.data includes: message_id, resource_type, delivery_mode, message_type
}
```

**The FE does NOT render platform-specific content. It sends `resource_id` and the backend handles:**
1. `fn_resolve_resource_for_delivery` — checks allowed channels, decides delivery_mode (platform_native / rich_content / text / media / link)
2. `cs_fn_send_resource` — inserts into `cs_messages` with full delivery context in metadata
3. `cs_trigger_deliver_outbound_message` — fires on INSERT, calls messaging service with resource-aware payload (native items, rich content blocks, or text fallback)
4. Messaging service renders per-platform format and delivers

### 3. Chat Thread — Rendering Resource Messages

When `cs_messages` has `message_type = 'resource'`, the chat thread needs a custom message renderer. This renders the **web preview** of the resource (since the agent is viewing in a browser).

**What to show in the chat thread:**

The chat thread shows a **web-rendered preview** of the rich content blocks. This is the same rendering the customer sees on web chat. For messages sent to LINE/Shopee/etc., add a subtle platform badge: "Sent as LINE Flex Message" or "Sent as Shopee product card".

**Message renderer logic:**

```typescript
// In the assistant-ui message renderer
if (message.message_type === 'resource' && message.metadata?.resource_id) {
  return <ResourceMessageBubble
    resourceId={message.metadata.resource_id}
    resourceType={message.metadata.resource_type}
    platform={conversation.platform}  // for the "Sent as..." badge
  />
}
```

**`ResourceMessageBubble` component** renders blocks from the resource's `rich_content`:

| Block type | Web chat render |
|---|---|
| `card` | Image + title + subtitle + fields as key-value pairs + CTA button |
| `carousel` | Horizontal scroll of cards |
| `hero` | Full-width image with text overlay |
| `buttons` | Row of styled buttons (primary = filled, secondary = outline) |
| `text` | Formatted text (heading = bold large, caption = small gray) |
| `image` | Image with optional caption |
| `video` | Video player with thumbnail |
| `list` | Styled list (key_value = label:value pairs, numbered = 1. 2. 3., bullet = dots) |
| `callout` | Colored box (promo = orange, info = blue, warning = yellow, success = green) |
| `separator` | Horizontal rule |

**Important:** The FE needs to fetch the full resource data to render blocks:

```typescript
const { data: resource } = await supabase.rpc('bff_get_resource_content_details', {
  p_resource_content_id: message.metadata.resource_id,
})
// Then render resource.rich_content.blocks
```

Cache aggressively — the same resource may appear in many messages.

### 4. Chat Thread — Platform Delivery Indicator

After a resource message, show a small indicator of how it was delivered:

- "✅ Delivered as LINE Flex Message" (rich platform)
- "✅ Delivered as Shopee product card" (marketplace with `platform_content`)
- "⚠️ Delivered as text + image on Shopee" (marketplace, no catalog ref)
- "✅ Delivered as web card" (web chat)

The delivery mode comes from `cs_messages.metadata.delivery_mode` — values: `platform_native`, `rich_content`, `text`, `media`, `link`.

### 5. Quick Reply Resources — Inline Insert

For `resource_type = 'quick_reply'`, instead of sending as a `resource` message type, insert the text directly into the composer as editable text. The agent can modify before sending as a normal `text` message.

This matches existing "canned response" behavior — quick replies are text shortcuts, not visual cards.

---

## Backend Status (all deployed)

| Component | Status | What it does |
|---|---|---|
| `cs_bff_send_resource` RPC | Deployed | BFF wrapper — validates merchant + conversation, calls cs_fn_send_resource |
| `cs_fn_send_resource` | Deployed | Calls `fn_resolve_resource_for_delivery`, maps delivery_mode to message_type, inserts into cs_messages with full metadata |
| `fn_resolve_resource_for_delivery` | Deployed | Universal resolver — reads resource, checks allowed_channels, decides platform_native vs rich_content vs text/media/link |
| `fn_render_blocks_as_text` | Deployed | Text fallback renderer — converts blocks to plain text (used for SMS, marketplace fallback) |
| `cs_trigger_deliver_outbound_message` | Deployed | Trigger — fires on cs_messages INSERT, sends resource-aware payload to messaging service (native_items, blocks, or text) |

---

## What NOT to Change

- Conversation list (left panel) — no changes
- Context sidebar (right panel) — no changes
- Conversation actions (assign, status, tags) — no changes
- Realtime subscriptions — the existing `cs_messages` subscription will pick up resource messages automatically
- AI suggested reply — no changes (AI may suggest resources in the future, but not in this phase)

---

## Dependencies (all deployed)

| Dependency | Type | Purpose |
|---|---|---|
| `cs_bff_send_resource` | RPC | Send resource in conversation — handles everything |
| `bff_list_resource_content` | RPC | Resource browser data (filter, search, paginate) |
| `bff_get_resource_content_details` | RPC | Full resource data for message rendering |
| `bff_list_resource_content_categories` | RPC | Category filter in resource browser |
| Block renderer components | FE | Shared with the content builder page — build once, reuse in both |
