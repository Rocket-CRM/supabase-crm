import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4';

/**
 * amp-analysis-apply
 *
 * POST /functions/v1/amp-analysis-apply
 *
 * Body: { recommendation_id: string, overrides?: Record<string, unknown> }
 *
 * Auth pattern — same as amp-analysis-message:
 *   - verify_jwt: false at Supabase gateway level
 *   - Internal JWT verification via getUser()
 *   - merchant_id derived from admin_users (never trusted from request body)
 *
 * Flow:
 *   1. Verify JWT → get admin_id
 *   2. Derive merchant_id from admin_users
 *   3. Fire Inngest event amp/analysis.apply → return 200 immediately
 *
 * The heavy lifting (calling bff_upsert_mission, marking applied) is done
 * asynchronously by the amp-analysis-recommendation-apply Inngest function.
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
    let body: { recommendation_id?: string; overrides?: Record<string, unknown> };
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: 'invalid_json' }, 400);
    }

    const { recommendation_id, overrides = {} } = body;

    if (!recommendation_id) {
      return jsonResponse({ error: 'recommendation_id is required' }, 400);
    }

    // ── Verify recommendation belongs to this merchant ───────────────────────
    const { data: rec, error: recErr } = await serviceClient
      .from('amp_analysis_recommendations')
      .select('id, status')
      .eq('id', recommendation_id)
      .eq('merchant_id', merchantId)
      .single();

    if (recErr || !rec) {
      return jsonResponse({ error: 'recommendation_not_found' }, 404);
    }

    if (rec.status === 'applied') {
      return jsonResponse({ error: 'recommendation_already_applied' }, 409);
    }

    // ── Mark as applying so the UI can reflect pending state ─────────────────
    await serviceClient
      .from('amp_analysis_recommendations')
      .update({ status: 'applying' })
      .eq('id', recommendation_id);

    // ── Fire Inngest event ───────────────────────────────────────────────────
    const controller = new AbortController();
    const inngestTimeout = setTimeout(() => controller.abort(), INNGEST_SEND_TIMEOUT_MS);

    try {
      const inngestRes = await fetch(`${INNGEST_API_URL}/${INNGEST_EVENT_KEY}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          name: 'amp/analysis.apply',
          data: {
            recommendation_id,
            merchant_id: merchantId,
            admin_id: adminId,
            overrides,
          },
        }),
        signal: controller.signal,
      });

      if (!inngestRes.ok) {
        const errBody = await inngestRes.text().catch(() => '');
        console.error(`[amp-analysis-apply] Inngest send failed (${inngestRes.status}):`, errBody);
        // Roll back the status update so the user can retry
        await serviceClient
          .from('amp_analysis_recommendations')
          .update({ status: 'pending' })
          .eq('id', recommendation_id);
        return jsonResponse({ error: 'Failed to queue apply job' }, 502);
      }
    } catch (inngestErr) {
      if ((inngestErr as Error)?.name === 'AbortError') {
        console.error('[amp-analysis-apply] Inngest send timed out after', INNGEST_SEND_TIMEOUT_MS, 'ms');
      } else {
        console.error('[amp-analysis-apply] Inngest send error:', inngestErr);
      }
      await serviceClient
        .from('amp_analysis_recommendations')
        .update({ status: 'pending' })
        .eq('id', recommendation_id);
      return jsonResponse({ error: 'Failed to queue apply job' }, 502);
    } finally {
      clearTimeout(inngestTimeout);
    }

    return jsonResponse({ ok: true, recommendation_id, status: 'applying' });

  } catch (err) {
    console.error('[amp-analysis-apply] unhandled error:', err);
    return jsonResponse({ error: 'Internal server error' }, 500);
  }
});
