import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4';

/**
 * amp-analysis-message
 *
 * POST /functions/v1/amp-analysis-message
 *
 * Auth pattern — matches amp-analysis-apply:
 *   - verify_jwt: false at Supabase gateway level
 *   - Internal JWT verification via getUser()
 *   - merchant_id derived from admin_users (never trusted from request body)
 *
 * Flow:
 *   1. Verify JWT → get admin_id
 *   2. Derive merchant_id from admin_users
 *   3. Create thread if needed
 *   4. Write user message to DB immediately
 *   5. Fire Inngest event → return 200
 */

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
const INNGEST_EVENT_KEY = Deno.env.get('INNGEST_EVENT_KEY')!;
const INNGEST_API_URL = Deno.env.get('INNGEST_API_URL') ?? 'https://inn.gs/e';

const INNGEST_SEND_TIMEOUT_MS = 8_000;

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  try {
    // ── Auth: verify JWT, extract admin_id ───────────────────────────────────
    // createClient with global.headers only sets PostgREST/storage headers; the
    // auth.getUser() call uses the client's in-memory session (empty on a fresh
    // serverless client). Must pass the token explicitly to hit /auth/v1/user.
    const authHeader = req.headers.get('authorization') ?? req.headers.get('Authorization');
    if (!authHeader) {
      return jsonResponse({ error: 'unauthorized' }, 401);
    }

    const token = authHeader.replace(/^[Bb]earer\s+/, '');
    const anonClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
    const { data: { user }, error: authError } = await anonClient.auth.getUser(token);
    if (authError || !user) {
      return jsonResponse({ error: 'unauthorized' }, 401);
    }
    const adminId = user.id;

    // ── Derive merchant_id from admin_users ──────────────────────────────────
    // Multi-merchant admins have multiple rows — use active_merchant_id from
    // app_metadata (set by the portal's merchant-select flow) to pick the right
    // one. Fall back to any active row if app_metadata isn't populated yet.
    const serviceClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

    const activeMerchantId: string | undefined =
      (user.app_metadata as Record<string, unknown>)?.active_merchant_id as string | undefined;

    let adminQuery = serviceClient
      .from('admin_users')
      .select('merchant_id')
      .eq('auth_user_id', adminId)
      .eq('active_status', true);

    if (activeMerchantId) {
      adminQuery = adminQuery.eq('merchant_id', activeMerchantId);
    }

    const { data: adminRow, error: adminErr } = await adminQuery.limit(1).maybeSingle();

    if (adminErr || !adminRow) {
      return jsonResponse({ error: 'admin_not_found' }, 403);
    }
    const merchantId: string = adminRow.merchant_id;

    // ── Parse body ───────────────────────────────────────────────────────────
    let body: { thread_id?: string; content?: string };
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: 'invalid_json' }, 400);
    }

    const { thread_id, content } = body;

    if (!content?.trim()) {
      return jsonResponse({ error: 'content is required' }, 400);
    }

    // ── Step 1: Resolve or create thread ────────────────────────────────────
    let threadId = thread_id;
    const isNewThread = !threadId;

    if (!threadId) {
      const { data: thread, error: threadError } = await serviceClient
        .from('amp_analysis_threads')
        .insert({
          merchant_id: merchantId,
          created_by: adminId,
          title: content.slice(0, 120),
        })
        .select('id')
        .single();

      if (threadError || !thread) {
        console.error('[amp-analysis-message] thread create error:', threadError);
        return jsonResponse({ error: 'Failed to create thread' }, 500);
      }
      threadId = thread.id as string;
    } else {
      // Verify thread belongs to this merchant before accepting it
      const { data: existingThread, error: threadLookupErr } = await serviceClient
        .from('amp_analysis_threads')
        .select('id')
        .eq('id', threadId)
        .eq('merchant_id', merchantId)
        .single();

      if (threadLookupErr || !existingThread) {
        return jsonResponse({ error: 'thread_not_found' }, 404);
      }
    }

    // ── Step 2: Write user message to DB IMMEDIATELY ─────────────────────────
    // Must happen before firing the Inngest event. If the function dies after
    // this point the message is still persisted.
    const { data: messageRow, error: msgError } = await serviceClient
      .from('amp_analysis_messages')
      .insert({
        thread_id: threadId,
        merchant_id: merchantId,
        role: 'user',
        content: content.trim(),
        status: 'complete',
      })
      .select('id')
      .single();

    if (msgError || !messageRow) {
      console.error('[amp-analysis-message] message insert error:', msgError);
      return jsonResponse({ error: 'Failed to persist message' }, 500);
    }

    const messageId = messageRow.id as string;

    // Update thread timestamp (best-effort)
    serviceClient
      .from('amp_analysis_threads')
      .update({ last_message_at: new Date().toISOString() })
      .eq('id', threadId)
      .then(({ error }) => {
        if (error) console.warn('[amp-analysis-message] last_message_at update failed:', error);
      });

    // ── Step 3: Fire Inngest event ───────────────────────────────────────────
    // New threads:  amp/analysis.thread.started  → starts the agent
    // Follow-ups:   amp/analysis.message         → waitForEvent in running agent
    const eventName = isNewThread ? 'amp/analysis.thread.started' : 'amp/analysis.message';

    const controller = new AbortController();
    const inngestTimeout = setTimeout(() => controller.abort(), INNGEST_SEND_TIMEOUT_MS);

    try {
      const inngestRes = await fetch(`${INNGEST_API_URL}/${INNGEST_EVENT_KEY}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          name: eventName,
          data: {
            thread_id: threadId,
            merchant_id: merchantId,
            admin_id: adminId,
            message_id: messageId,
            content: content.trim(),
          },
        }),
        signal: controller.signal,
      });

      if (!inngestRes.ok) {
        const errBody = await inngestRes.text().catch(() => '');
        console.error(`[amp-analysis-message] Inngest send failed (${inngestRes.status}):`, errBody);
      }
    } catch (inngestErr) {
      if ((inngestErr as Error)?.name === 'AbortError') {
        console.error('[amp-analysis-message] Inngest send timed out after', INNGEST_SEND_TIMEOUT_MS, 'ms');
      } else {
        console.error('[amp-analysis-message] Inngest send error:', inngestErr);
      }
      // Non-fatal — message is already in DB
    } finally {
      clearTimeout(inngestTimeout);
    }

    // ── Step 4: Return immediately ───────────────────────────────────────────
    return jsonResponse({
      ok: true,
      thread_id: threadId,
      message_id: messageId,
      is_new_thread: isNewThread,
    });

  } catch (err) {
    console.error('[amp-analysis-message] unhandled error:', err);
    return jsonResponse({ error: 'Internal server error' }, 500);
  }
});
