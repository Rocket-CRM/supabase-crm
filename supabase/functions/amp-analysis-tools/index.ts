import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

function getClient() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
}

async function queryMemberOverview(merchantId: string) {
  const { data, error } = await getClient()
    .from('mv_amp_analysis_member_segments')
    .select('*')
    .eq('merchant_id', merchantId);
  if (error) throw error;
  return data;
}

async function queryAcquisition(merchantId: string) {
  const { data, error } = await getClient()
    .from('mv_amp_analysis_acquisition')
    .select('*')
    .eq('merchant_id', merchantId)
    .order('year_month', { ascending: false });
  if (error) throw error;
  return data;
}

async function queryEarnActivity(merchantId: string) {
  const { data, error } = await getClient()
    .from('mv_amp_analysis_earn_activity')
    .select('*')
    .eq('merchant_id', merchantId);
  if (error) throw error;
  return data;
}

async function queryBurnActivity(merchantId: string) {
  const { data, error } = await getClient()
    .from('mv_amp_analysis_burn_activity')
    .select('*')
    .eq('merchant_id', merchantId)
    .order('period');
  if (error) throw error;
  return data;
}

async function queryPurchaseTrends(merchantId: string) {
  const { data, error } = await getClient()
    .from('mv_amp_analysis_purchase_trends')
    .select('*')
    .eq('merchant_id', merchantId)
    .order('period');
  if (error) throw error;
  return data;
}

async function queryMissionCatalog(merchantId: string) {
  const client = getClient();
  const [perfResult, catalogResult] = await Promise.all([
    client.from('mv_amp_analysis_mission_performance').select('*').eq('merchant_id', merchantId).order('enrolled_count', { ascending: false }),
    client.from('mv_mission_conditions_expanded').select('*').eq('merchant_id', merchantId),
  ]);
  if (perfResult.error) throw perfResult.error;
  if (catalogResult.error) throw catalogResult.error;
  const perfMap = new Map((perfResult.data ?? []).map((r: Record<string, unknown>) => [r.mission_id, r]));
  return (catalogResult.data ?? []).map((m: Record<string, unknown>) => ({ ...m, performance: perfMap.get(m.id) ?? null }));
}

async function getMemberSnapshot(merchantId: string, userId: string) {
  const { data, error } = await getClient().rpc('fn_amp_analysis_get_member_snapshot', {
    p_merchant_id: merchantId,
    p_user_id: userId,
  });
  if (error) throw error;
  return data;
}

async function getMissionFieldGuide() {
  const { data, error } = await getClient()
    .from('ai_knowledge_registry')
    .select('content, content_type, version, updated_at')
    .eq('feature_key', 'amp_analysis.mission_field_guide')
    .eq('is_active', true)
    .single();
  if (error) throw error;
  return data;
}

async function getFormFieldGuide() {
  const { data, error } = await getClient()
    .from('ai_knowledge_registry')
    .select('content, content_type, version, updated_at')
    .eq('feature_key', 'amp_analysis.form_field_guide')
    .eq('is_active', true)
    .single();
  if (error) throw error;
  return data;
}

async function queryFormCatalog(merchantId: string) {
  const { data, error } = await getClient().rpc('fn_amp_analysis_list_forms', {
    p_merchant_id: merchantId,
  });
  if (error) throw error;
  return data;
}

function formatError(err: unknown): string {
  if (err instanceof Error) return err.message;
  if (typeof err === 'object' && err !== null) {
    const e = err as Record<string, unknown>;
    if (typeof e.message === 'string') return e.message;
    if (typeof e.error === 'string') return e.error;
    return JSON.stringify(err);
  }
  return String(err);
}

async function queryFormFieldBreakdown(
  merchantId: string,
  body: Record<string, unknown>,
) {
  if (!body.form_id || typeof body.form_id !== 'string') {
    throw new Error('form_id is required');
  }
  const { data, error } = await getClient().rpc('fn_amp_analysis_query_form_summary', {
    p_merchant_id: merchantId,
    p_form_id: body.form_id,
    p_field_keys: body.field_keys ?? null,
    p_start_date: body.start_date ?? null,
    p_end_date: body.end_date ?? null,
  });
  if (error) throw error;
  return data;
}

async function queryProfileField(
  merchantId: string,
  body: Record<string, unknown>,
) {
  const { data, error } = await getClient().rpc('fn_amp_analysis_query_profile_field', {
    p_merchant_id: merchantId,
    p_field_key: body.field_key,
    p_bucket_rules: body.bucket_rules ?? null,
  });
  if (error) throw error;
  return data;
}

async function queryCrossTabProfile(
  merchantId: string,
  body: Record<string, unknown>,
) {
  const { data, error } = await getClient().rpc('fn_amp_analysis_cross_tab_profile', {
    p_merchant_id: merchantId,
    p_field_key: body.field_key,
    p_outcome_type: body.outcome_type ?? 'event_attended',
    p_bucket_rules: body.bucket_rules ?? null,
  });
  if (error) throw error;
  return data;
}

async function queryEventAttendance(
  merchantId: string,
  body: Record<string, unknown>,
) {
  const { data, error } = await getClient().rpc('fn_amp_analysis_query_event_attendance', {
    p_merchant_id: merchantId,
    p_event_code: body.event_code ?? null,
  });
  if (error) throw error;
  return data;
}

async function produceRecommendation(merchantId: string, body: Record<string, unknown>) {
  const { thread_id, message_id, type, title, rationale, impact_estimate, target_segment, config } = body;

  if (!config || typeof config !== 'object') {
    throw new Error('produce_recommendation: config is required');
  }
  const cfg = config as Record<string, unknown>;
  if (!Array.isArray(cfg.conditions) || cfg.conditions.length === 0) {
    throw new Error(
      'produce_recommendation: config.conditions is required and must have at least 1 item.',
    );
  }
  if (!Array.isArray(cfg.outcomes) || cfg.outcomes.length === 0) {
    throw new Error(
      'produce_recommendation: config.outcomes is required and must have at least 1 item.',
    );
  }

  cfg.is_active = false;

  const { data, error } = await getClient().rpc('fn_amp_analysis_save_recommendation', {
    p_thread_id: thread_id,
    p_message_id: message_id ?? null,
    p_merchant_id: merchantId,
    p_type: type ?? 'mission',
    p_title: title,
    p_rationale: rationale ?? null,
    p_impact_estimate: impact_estimate ?? null,
    p_target_segment: target_segment ?? null,
    p_config: cfg,
  });
  if (error) throw error;
  return data;
}

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, x-merchant-id',
};

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS_HEADERS });

  const url = new URL(req.url);
  const path = url.pathname.replace(/^\/amp-analysis-tools/, '');
  const merchantId = req.headers.get('x-merchant-id');
  if (!merchantId) {
    return new Response(JSON.stringify({ error: 'x-merchant-id header required' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  let body: Record<string, unknown> = {};
  if (req.method === 'POST') {
    try {
      body = await req.json();
    } catch {
      /* empty body */
    }
  }

  try {
    let result: unknown;
    if (path === '/query_member_overview') result = await queryMemberOverview(merchantId);
    else if (path === '/query_acquisition') result = await queryAcquisition(merchantId);
    else if (path === '/query_earn_activity') result = await queryEarnActivity(merchantId);
    else if (path === '/query_burn_activity') result = await queryBurnActivity(merchantId);
    else if (path === '/query_purchase_trends') result = await queryPurchaseTrends(merchantId);
    else if (path === '/query_mission_catalog') result = await queryMissionCatalog(merchantId);
    else if (path === '/query_form_catalog') result = await queryFormCatalog(merchantId);
    else if (path === '/query_form_field_breakdown') result = await queryFormFieldBreakdown(merchantId, body);
    else if (path === '/query_profile_field') result = await queryProfileField(merchantId, body);
    else if (path === '/query_cross_tab_profile') result = await queryCrossTabProfile(merchantId, body);
    else if (path === '/query_event_attendance') result = await queryEventAttendance(merchantId, body);
    else if (path === '/get_member_snapshot') {
      const userId = (body.user_id ?? url.searchParams.get('user_id')) as string;
      if (!userId) {
        return new Response(JSON.stringify({ error: 'user_id required' }), { status: 400 });
      }
      result = await getMemberSnapshot(merchantId, userId);
    } else if (path === '/get_mission_field_guide') result = await getMissionFieldGuide();
    else if (path === '/get_form_field_guide') result = await getFormFieldGuide();
    else if (path === '/produce_recommendation') result = await produceRecommendation(merchantId, body);
    else {
      return new Response(JSON.stringify({ error: `unknown tool: ${path}` }), { status: 404 });
    }

    return new Response(JSON.stringify({ ok: true, data: result }), {
      headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
    });
  } catch (err: unknown) {
    const message = formatError(err);
    console.error(`[amp-analysis-tools] ${path} error:`, message);
    return new Response(JSON.stringify({ ok: false, error: message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
    });
  }
});
