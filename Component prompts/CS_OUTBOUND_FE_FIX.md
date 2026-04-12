# CS Inbox — Outbound Message Delivery

## Architecture

Agent messages from the inbox are delivered via the `cs-send-message` **edge function** (not the DB trigger).

| Path | How it works | Status |
|---|---|---|
| **AI agent** | cs-ai-service (Render) → `cs_fn_insert_message` → messaging-service (Render) | Working |
| **Human agent** | Frontend → `cs-send-message` edge function → `cs_fn_insert_message` → messaging-service (Render) | Working |
| **~~DB trigger~~** | ~~`trg_cs_messages_deliver_outbound` → `net.http_post`~~ | **Disabled — do not re-enable** |

The DB trigger `trg_cs_messages_deliver_outbound` on `cs_messages` is intentionally **DISABLED**. All outbound delivery goes through the messaging service on Render, called by the edge function (human agent) or cs-ai-service (AI agent). Do not re-enable the trigger.

## Edge Function: `cs-send-message`

- **verify_jwt:** `false` (auth handled internally)
- **Auth:** validates Supabase Auth JWT via `auth.getUser(token)`, then checks `admin_users` for merchant authorization
- **Messaging auth:** uses `get_messaging_auth_key()` DB function (reads from vault) — NOT the `SUPABASE_SERVICE_ROLE_KEY` env var
- **URL:** hardcoded `https://messaging-service-li40.onrender.com/send`

The function:
1. Validates admin JWT + verifies admin belongs to the conversation's merchant
2. Saves the message to DB via `cs_fn_insert_message`
3. Delivers to the platform (LINE, Shopee, etc.) via the messaging service
4. Skips delivery for internal notes (`message_type: 'note'`)

---

## FE Change: Replace RPC with Edge Function Call

### Before (broken — saves only, no delivery)

```typescript
const { data } = await supabase.rpc('cs_bff_send_message', {
  p_conversation_id: conversationId,
  p_content: content,
  p_message_type: messageType,
  p_metadata: metadata,
})
const messageId = data?.data?.message_id
```

### After (saves + delivers)

```typescript
const { data: { session } } = await supabase.auth.getSession()

const response = await fetch(
  `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/cs-send-message`,
  {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${session?.access_token}`,
      'apikey': process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    },
    body: JSON.stringify({
      conversation_id: conversationId,
      content: content,
      message_type: messageType,   // 'text' | 'image' | 'file' | 'note'
      metadata: metadata,          // optional
    }),
  }
)

const result = await response.json()
const messageId = result?.data?.message_id
const delivery = result?.data?.delivery
```

### Response Shape

```typescript
// Success
{
  success: true,
  data: {
    message_id: "uuid",
    delivery: {
      success: true,
      // ... messaging service response
    }
  }
}

// For internal notes (message_type: 'note')
{
  success: true,
  data: {
    message_id: "uuid",
    delivery: {
      success: true,
      skipped: true,
      reason: "internal_note"
    }
  }
}

// Error
{
  error: "conversation_not_found" | "no_merchant_context" | "insert_failed" | "missing_fields",
  message?: "details"
}
```

---

## Where to Change

Find ALL places that call `cs_bff_send_message` — typically in:
- `use-inbox.ts` or similar hook (sendMessage, sendNote functions)
- Any component that sends agent replies
- Any component that sends internal notes

Replace the `supabase.rpc('cs_bff_send_message', ...)` call with the `fetch` call above.

### Internal Notes

For internal notes, use the same endpoint with `message_type: 'note'`:

```typescript
// Agent reply — saves to DB + delivers to customer via LINE/Shopee/etc.
await sendToEdgeFunction({ conversation_id, content, message_type: 'text' })

// Internal note — saves to DB only, no delivery
await sendToEdgeFunction({ conversation_id, content, message_type: 'note' })
```

### Helper Function (recommended)

Create a reusable helper:

```typescript
// src/lib/api/cs/send-message.ts
export async function csSendMessage(
  supabase: SupabaseClient,
  params: {
    conversation_id: string
    content: string
    message_type?: 'text' | 'image' | 'file' | 'note'
    metadata?: Record<string, any>
  }
): Promise<{ message_id: string; delivery: any }> {
  const { data: { session } } = await supabase.auth.getSession()

  const res = await fetch(
    `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/cs-send-message`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${session?.access_token}`,
        'apikey': process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
      },
      body: JSON.stringify({
        conversation_id: params.conversation_id,
        content: params.content,
        message_type: params.message_type ?? 'text',
        metadata: params.metadata ?? {},
      }),
    }
  )

  if (!res.ok) {
    const err = await res.json()
    throw new Error(err.error || 'Failed to send message')
  }

  const result = await res.json()
  return result.data
}
```

Then use it everywhere:

```typescript
// Send reply
const { message_id } = await csSendMessage(supabase, {
  conversation_id: convId,
  content: 'Hello, how can I help?',
})

// Send internal note
const { message_id } = await csSendMessage(supabase, {
  conversation_id: convId,
  content: 'Customer is VIP, handle with care',
  message_type: 'note',
})
```

---

## What NOT to Change

- `cs_bff_list_conversations` — still uses `supabase.rpc()` (read-only, no delivery needed)
- `cs_bff_get_conversation_details` — still uses `supabase.rpc()` (read-only)
- `cs_bff_update_conversation` — still uses `supabase.rpc()` (status/priority changes, no delivery)
- Supabase Realtime subscriptions — no change needed
