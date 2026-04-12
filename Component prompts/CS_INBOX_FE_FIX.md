# CS Inbox — Realtime Fix (Revert to SSR Client)

> **Root cause**: The separate vanilla `@supabase/supabase-js` client (`realtime-client.ts`) 
> was unnecessary and introduced differences vs the working loyalty-user pattern.
> The assumption that `@supabase/ssr` corrupts WebSocket was never proven.
>
> **Fix**: Delete the vanilla client. Use the SSR client for Realtime directly.

---

## Why the separate client was wrong

| | loyalty-user (works) | loyalty-admin (broken) |
|---|---|---|
| Clients | 1 (vanilla) | 2 (SSR + vanilla) |
| `_getAccessToken()` callback | Returns anon key | SSR: admin JWT / Vanilla: anon key |
| `vsn` | Default `2.0.0` | Forced `1.0.0` |
| GoTrueClient instances | 1 | 2 (triggers warning) |
| `@supabase/supabase-js` | `^2.99.3` (standalone WebSocket) | `^2.101.1` (Phoenix adapter) |

The SSR client has a valid admin session from cookies. Its internal `_getAccessToken()` 
returns the admin JWT — exactly what Realtime needs. No manual `setAuth()` race conditions.

---

## Step 1 — Delete `src/lib/supabase/realtime-client.ts`

Remove the entire file.

## Step 2 — Update `src/lib/supabase/client.ts`

Remove the warning comment about not using SSR for Realtime:

```typescript
"use client"

import { createBrowserClient } from "@supabase/ssr"

export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  )
}
```

## Step 3 — Update `use-inbox.ts` Realtime sections

Replace both Realtime `useEffect` blocks to use the SSR client directly.

### Conversation channel (replace the existing Realtime useEffect):

```typescript
// ── Supabase Realtime: conversation subscription ──────
useEffect(() => {
  let conversationChannel: ReturnType<typeof supabase.channel> | null = null
  let cancelled = false

  async function setupRealtime() {
    const { data: { session } } = await supabase.auth.getSession()
    if (cancelled) return

    if (session?.access_token) {
      supabase.realtime.setAuth(session.access_token)
    }

    conversationChannel = supabase
      .channel("cs-conversation-updates")
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "cs_conversations",
        },
        (payload) => {
          console.log("[Realtime] cs_conversations event:", payload.eventType, payload.new)
          if (payload.eventType === "INSERT") {
            fetchConversations()
          } else if (payload.eventType === "UPDATE") {
            const updated = payload.new as Partial<Conversation> & { id: string }
            if (updated.id) {
              setAllConversations((prev) =>
                prev.map((c) =>
                  c.id === updated.id
                    ? { ...c, ...updated } as Conversation
                    : c,
                ),
              )
            }
          }
        },
      )
      .subscribe((status, err) => {
        console.log("[Realtime] cs_conversations subscription:", status, err ?? "")
      })
  }

  setupRealtime()

  return () => {
    cancelled = true
    if (conversationChannel) {
      supabase.removeChannel(conversationChannel)
    }
  }
}, [supabase, fetchConversations])
```

### Message channel (replace the existing message Realtime useEffect):

```typescript
// ── Supabase Realtime: message subscription for selected conversation ──
useEffect(() => {
  if (!selectedId) return

  let messageChannel: ReturnType<typeof supabase.channel> | null = null
  let cancelled = false

  async function setupMessageRealtime() {
    const { data: { session } } = await supabase.auth.getSession()
    if (cancelled) return

    if (session?.access_token) {
      supabase.realtime.setAuth(session.access_token)
    }

    messageChannel = supabase
      .channel(`cs-messages-${selectedId}`)
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "cs_messages",
          filter: `conversation_id=eq.${selectedId}`,
        },
        (payload) => {
          const newMsg = payload.new as {
            id: string
            conversation_id: string
            sender_type: string
            sender_id: string | null
            content: string
            message_type: string
            metadata: Record<string, unknown>
            created_at: string
          }
          setMessages((prev) => {
            if (prev.some((m) => m.id === newMsg.id)) return prev
            return [...prev, newMsg as ConversationMessage]
          })

          setAllConversations((prev) =>
            prev.map((c) =>
              c.id === selectedId
                ? {
                    ...c,
                    last_message: {
                      content: newMsg.content,
                      sender_type: newMsg.sender_type as ConversationMessage["sender_type"],
                      message_type: newMsg.message_type as ConversationMessage["message_type"],
                    },
                    last_message_at: newMsg.created_at,
                    unread_count: 0,
                  }
                : c,
            ),
          )
        },
      )
      .subscribe((status, err) => {
        console.log(`[Realtime] cs_messages-${selectedId} subscription:`, status, err ?? "")
      })
  }

  setupMessageRealtime()

  return () => {
    cancelled = true
    if (messageChannel) {
      supabase.removeChannel(messageChannel)
    }
  }
}, [supabase, selectedId])
```

## Step 4 — Remove the import

In `use-inbox.ts`, remove:

```typescript
import { getRealtimeClient } from "@/lib/supabase/realtime-client"
```

---

## What this changes

1. **One client** instead of two — eliminates "Multiple GoTrueClient instances" warning
2. **Default `vsn=2.0.0`** — matches loyalty-user exactly
3. **SSR client's `_getAccessToken()` returns admin JWT** from cookies — no anon key mismatch
4. **Same package path** as REST calls — no second SupabaseClient with different auth state

## If this still fails

Pin `@supabase/supabase-js` to the exact version loyalty-user uses:

```json
"@supabase/supabase-js": "2.99.3"
```

(not `^2.99.3` — exact version)

This downgrades from the new Phoenix Socket adapter back to direct WebSocket management, 
which is the one internal difference between the two packages.
