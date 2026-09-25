/**
 * amp-analysis-agent
 *
 * Fires once per thread on `amp/analysis.thread.started`.
 * Handles turn 1, then loops via waitForEvent for subsequent turns.
 * On 8h timeout (session end), invokes amp-analysis-distil.
 */
import { inngest } from '../inngest-client.js';
import { ampAnalysisDistil } from './amp-analysis-distil.js';
import { createClient } from '@supabase/supabase-js';
import Anthropic from '@anthropic-ai/sdk';

const SUPABASE_URL = process.env.SUPABASE_URL!;
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;
const TOOLS_BASE_URL = process.env.AMP_ANALYSIS_TOOLS_URL!; // Supabase Edge Function base URL
const ANTHROPIC_API_KEY = process.env.ANTHROPIC_API_KEY!;

const MODEL = 'claude-3-5-sonnet-20241022';
const SESSION_TIMEOUT = '8h';
const MAX_HISTORY_MESSAGES = 20;

function getDb() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
}

// Include service-role credentials so amp-analysis-tools edge function
// (JWT-verified) accepts calls from this internal Render service.
function toolHeaders(merchantId: string) {
  return {
    'Content-Type': 'application/json',
    'x-merchant-id': merchantId,
    'Authorization': `Bearer ${SUPABASE_SERVICE_KEY}`,
    'apikey': SUPABASE_SERVICE_KEY,
  };
}

// ─── Tool definitions (MCP-style) ───────────────────────────────────────────

const TOOLS: Anthropic.Messages.Tool[] = [
  {
    name: 'query_member_overview',
    description: 'Returns cohort breakdown across all segment dimensions (activity, spend, engagement, tier) for this merchant. Call this first for any member-base question.',
    input_schema: { type: 'object', properties: {}, required: [] },
  },
  {
    name: 'query_acquisition',
    description: 'Returns monthly signup trends, activation rate, and referral % for the last 12 months.',
    input_schema: { type: 'object', properties: {}, required: [] },
  },
  {
    name: 'query_earn_activity',
    description: 'Returns earn event breakdown by source type across all configured analysis periods. Shows what drives point earning.',
    input_schema: { type: 'object', properties: {}, required: [] },
  },
  {
    name: 'query_burn_activity',
    description: 'Returns redemption stats: count, cancellations, points burned, top rewards across configured periods.',
    input_schema: { type: 'object', properties: {}, required: [] },
  },
  {
    name: 'query_purchase_trends',
    description: 'Returns revenue, AOV, transaction count, unique buyers across configured periods. Use for sizing mission targets.',
    input_schema: { type: 'object', properties: {}, required: [] },
  },
  {
    name: 'query_mission_catalog',
    description: 'Returns all missions with their full config (conditions, outcomes) plus engagement stats (completion rate, enrolled count).',
    input_schema: { type: 'object', properties: {}, required: [] },
  },
  {
    name: 'get_member_snapshot',
    description: 'Returns a detailed profile for a single member: wallet, activity, tier progress, earn/redemption history, missions. Use for specific member questions.',
    input_schema: {
      type: 'object',
      properties: {
        user_id: { type: 'string', description: 'UUID of the member to look up' },
      },
      required: ['user_id'],
    },
  },
  {
    name: 'get_mission_field_guide',
    description: 'Returns technical field reference and business context for creating valid mission configs. ALWAYS call this before produce_recommendation.',
    input_schema: { type: 'object', properties: {}, required: [] },
  },
  {
    name: 'get_form_field_guide',
    description: 'Returns routing guide for form/survey/profile data tools. Call before answering crop, farm size, survey, or event attendance questions.',
    input_schema: { type: 'object', properties: {}, required: [] },
  },
  {
    name: 'query_form_catalog',
    description: 'Returns all published forms with fields, ai_context, aggregation_mode (member_latest vs submission), and submission counts. Also injected in thread context as form_catalog.',
    input_schema: { type: 'object', properties: {}, required: [] },
  },
  {
    name: 'query_form_field_breakdown',
    description: 'Survey form field value distribution (submission-level). Do NOT use for USER_PROFILE — use query_profile_field instead.',
    input_schema: {
      type: 'object',
      properties: {
        form_id: { type: 'string', description: 'UUID from form_catalog' },
        field_keys: { type: 'array', items: { type: 'string' }, description: 'Optional filter to specific field_keys' },
        start_date: { type: 'string', description: 'Optional ISO8601 filter' },
        end_date: { type: 'string', description: 'Optional ISO8601 filter' },
      },
      required: ['form_id'],
    },
  },
  {
    name: 'query_profile_field',
    description: 'USER_PROFILE field distribution using latest value per member. Use for crop, area (farm size in rai), and other profile attributes.',
    input_schema: {
      type: 'object',
      properties: {
        field_key: { type: 'string', description: 'e.g. crop, area' },
        bucket_rules: { type: 'array', description: 'Optional numeric bucket rules [{label,min,max}]' },
      },
      required: ['field_key'],
    },
  },
  {
    name: 'query_cross_tab_profile',
    description: 'Cross-tab USER_PROFILE field vs outcome (event attendance). Use for "which crop/farm size attends events most".',
    input_schema: {
      type: 'object',
      properties: {
        field_key: { type: 'string', description: 'e.g. crop or area' },
        outcome_type: { type: 'string', enum: ['event_attended', 'event_registered'], description: 'Default event_attended' },
        bucket_rules: { type: 'array', description: 'Optional numeric bucket rules for area field' },
      },
      required: ['field_key'],
    },
  },
  {
    name: 'query_event_attendance',
    description: 'Event registration and attendance summary from syngenta_event_registration_ledger. Authoritative source for who attended events.',
    input_schema: {
      type: 'object',
      properties: {
        event_code: { type: 'string', description: 'Optional filter to one event' },
      },
      required: [],
    },
  },
  {
    name: 'produce_recommendation',
    description: `Emits a typed recommendation card that the brand can click to create a mission draft.
Call get_mission_field_guide FIRST. Then call this with a COMPLETE config including conditions and outcomes arrays.
REQUIRED: config.conditions (array with at least 1 item) and config.outcomes (array with at least 1 item).
A recommendation with missing conditions or outcomes cannot be applied and is useless to the brand.`,
    input_schema: {
      type: 'object',
      properties: {
        type: { type: 'string', enum: ['mission'], description: 'Recommendation type. mission is the only type currently supported.' },
        title: { type: 'string', description: 'Short descriptive name for this recommendation.' },
        rationale: { type: 'string', description: 'Why this recommendation, grounded in the specific data found (member counts, AOV, segments). Include estimated cost in points.' },
        impact_estimate: { type: 'string', description: 'Expected impact: member count affected, rough point cost, expected revenue lift.' },
        target_segment: {
          type: 'object',
          properties: {
            activity_bucket: { type: 'string' },
            tier_ids: { type: 'array', items: { type: 'string' } },
            spend_bucket: { type: 'string' },
            engagement_type: { type: 'string' },
          },
        },
        config: {
          type: 'object',
          description: 'Complete mission config. is_active is enforced false server-side.',
          required: ['type', 'activation_type', 'claim_type', 'start_date', 'end_date', 'conditions', 'outcomes'],
          properties: {
            type: { type: 'string', enum: ['standard', 'milestone', 'recurring'], description: 'standard=AND logic, milestone=sequential levels, recurring=resets on schedule' },
            activation_type: { type: 'string', enum: ['auto', 'manual'], description: 'auto=system tracks all members automatically, manual=member must opt in' },
            claim_type: { type: 'string', enum: ['auto', 'manual'], description: 'auto=reward issued instantly, manual=member taps to claim' },
            reset_frequency: { type: 'string', enum: ['realtime', 'daily', 'monthly', 'period_end'], nullable: true, description: 'null for standard and milestone. Required for recurring.' },
            start_date: { type: 'string', description: 'ISO8601 date string (e.g. 2026-04-25)' },
            end_date: { type: 'string', description: 'ISO8601 date string. 30–60 days for re-engagement; 1 year for recurring.' },
            is_active: { type: 'boolean', description: 'ALWAYS false. Enforced server-side.' },
            conditions: {
              type: 'array',
              minItems: 1,
              description: 'REQUIRED. At least one condition defining what the member must do.',
              items: {
                type: 'object',
                required: ['condition_type', 'measurement_type', 'target_value'],
                properties: {
                  condition_type: { type: 'string', enum: ['purchase', 'points_earned', 'tickets_earned', 'form_submission', 'referral_signup', 'referral_purchase'] },
                  measurement_type: { type: 'string', enum: ['count', 'sum'], description: 'count=number of transactions, sum=total spend amount' },
                  target_value: { type: 'number', description: 'For count: number of events. For sum: total spend in local currency.' },
                  min_transaction_amount: { type: 'number', nullable: true, description: 'Per-transaction minimum. Use AOV from query_purchase_trends as baseline. null if not applicable.' },
                  tier_ids: { type: 'array', items: { type: 'string' }, nullable: true, description: 'Restrict to specific tiers. null = all tiers.' },
                  milestone_level: { type: 'integer', nullable: true, description: 'For milestone missions: 1-indexed level this condition belongs to.' },
                },
              },
            },
            outcomes: {
              type: 'array',
              minItems: 1,
              description: 'REQUIRED. At least one outcome defining what the member receives.',
              items: {
                type: 'object',
                required: ['outcome_type'],
                properties: {
                  outcome_type: { type: 'string', enum: ['points', 'tickets', 'reward'], description: 'reward type requires entity_id.' },
                  amount: { type: 'integer', description: 'Points or tickets amount. Not used when outcome_type=reward.' },
                  entity_id: { type: 'string', nullable: true, description: 'reward_master.id when outcome_type=reward.' },
                  milestone_level: { type: 'integer', nullable: true, description: 'For milestone missions: which level this outcome rewards.' },
                },
              },
            },
          },
        },
      },
      required: ['type', 'title', 'rationale', 'impact_estimate', 'config'],
    },
  },
];

// ─── Tool executor ───────────────────────────────────────────────────────────

async function executeTool(
  toolName: string,
  input: Record<string, unknown>,
  merchantId: string,
  threadId: string,
  messageId: string | null,
): Promise<unknown> {
  const baseUrl = `${TOOLS_BASE_URL}/amp-analysis-tools`;
  const headers = toolHeaders(merchantId);

  switch (toolName) {
    case 'query_member_overview':
    case 'query_acquisition':
    case 'query_earn_activity':
    case 'query_burn_activity':
    case 'query_purchase_trends':
    case 'query_mission_catalog':
    case 'get_mission_field_guide':
    case 'get_form_field_guide':
    case 'query_form_catalog': {
      const res = await fetch(`${baseUrl}/${toolName}`, { headers });
      const json = await res.json();
      return json.data;
    }
    case 'query_form_field_breakdown':
    case 'query_profile_field':
    case 'query_cross_tab_profile':
    case 'query_event_attendance': {
      const res = await fetch(`${baseUrl}/${toolName}`, {
        method: 'POST',
        headers,
        body: JSON.stringify(input),
      });
      const json = await res.json();
      return json.data;
    }
    case 'get_member_snapshot': {
      const res = await fetch(`${baseUrl}/get_member_snapshot`, {
        method: 'POST',
        headers,
        body: JSON.stringify({ user_id: input.user_id }),
      });
      const json = await res.json();
      return json.data;
    }
    case 'produce_recommendation': {
      const res = await fetch(`${baseUrl}/produce_recommendation`, {
        method: 'POST',
        headers,
        body: JSON.stringify({ ...input, thread_id: threadId, message_id: messageId }),
      });
      const json = await res.json();
      return json.data;
    }
    default:
      throw new Error(`Unknown tool: ${toolName}`);
  }
}

// Zero-cost keyword classifier — no LLM call needed.
// Only purpose is to short-circuit explicit apply commands.
function classifyIntent(content: string): 'apply_action' | 'other' {
  const lower = content.toLowerCase().trim();
  const applyPhrases = ['apply this', 'create draft', 'apply recommendation', 'apply the recommendation'];
  return applyPhrases.some((p) => lower.includes(p)) ? 'apply_action' : 'other';
}

// How long a single reasoning turn may run before we give up and mark the
// assistant message as errored. Inngest step timeout sits above this, but
// having our own guard means we write a clean error row instead of letting
// the step die silently.
const TURN_TIMEOUT_MS = 120_000;

function sleep(ms: number) {
  return new Promise<never>((_, reject) =>
    setTimeout(() => reject(new Error('TURN_TIMEOUT')), ms),
  );
}

// ─── Main reasoning turn ─────────────────────────────────────────────────────

async function runReasoningTurn(params: {
  threadId: string;
  merchantId: string;
  adminId: string;
  messages: Anthropic.Messages.MessageParam[];
  contextSummary: Record<string, unknown> | null;
  formCatalog: unknown;
  mvFreshness: Record<string, unknown>;
  merchantConfig: Record<string, unknown>;
  userContent: string;
  userMessageId?: string;
}) {
  const { threadId, merchantId, messages, contextSummary, formCatalog, mvFreshness, merchantConfig, userContent, userMessageId } = params;
  const db = getDb();
  const anthropic = new Anthropic({ apiKey: ANTHROPIC_API_KEY });

  // ── Guard: ensure the user message exists in DB ──────────────────────────
  //
  // The Edge Function writes it first, but if Inngest retries or the Edge
  // Function crashed after firing the event, the row may be missing. Insert
  // idempotently so the thread is never silently empty.
  if (userMessageId) {
    const { count } = await db
      .from('amp_analysis_messages')
      .select('id', { count: 'exact', head: true })
      .eq('id', userMessageId);

    if (!count) {
      await db.from('amp_analysis_messages').insert({
        id: userMessageId,
        thread_id: threadId,
        merchant_id: merchantId,
        role: 'user',
        content: userContent,
        status: 'complete',
      });
    }
  }

  // ── Build system prompt ───────────────────────────────────────────────────
  const availablePeriods: string = ((mvFreshness.available_periods as number[]) ?? [30, 90, 180])
    .map((d: number) => `${d}d`)
    .join(', ');

  const freshnessSummary = Object.entries(mvFreshness)
    .filter(([k]) => k !== 'available_periods')
    .map(([k, v]) => `${k}: ${v ? new Date(v as string).toISOString() : 'never'}`)
    .join('\n');

  const systemPrompt = `You are the AMP Analysis Agent for a loyalty platform.
You help brand administrators understand their member base and create data-driven mission recommendations.

MERCHANT CONTEXT:
${JSON.stringify(merchantConfig, null, 2)}

DATA FRESHNESS:
${freshnessSummary}

AVAILABLE ANALYSIS PERIODS: ${availablePeriods}
When citing data, always qualify it with the data freshness. e.g. "Based on data as of X minutes ago..."

${contextSummary ? `PREVIOUS SESSION FINDINGS:\n${JSON.stringify(contextSummary, null, 2)}\n` : ''}

FORM CATALOG (published forms + field ai_context — use for crop/farm/survey/event questions):
${JSON.stringify(formCatalog, null, 2)}

FORM DATA RULES:
- Questions about crop type, farm size, grower profile → query_profile_field or query_cross_tab_profile (USER_PROFILE, member_latest).
- Questions about survey responses → query_form_field_breakdown (submission-level, pick form_id from catalog).
- Questions about event attendance → query_event_attendance + query_cross_tab_profile with outcome_type=event_attended.
- Call get_form_field_guide if unsure which tool to use.
- Never say crop/farm/event data is unavailable without calling form tools first.

RULES:
- Never make up data. Only cite numbers from tool results.
- Always call get_mission_field_guide before produce_recommendation.
- Always call query_purchase_trends before produce_recommendation to get real AOV for condition sizing.
- Recommendations must have is_active: false (enforced server-side).
- Be specific about segment sizes, not vague about "some members".
- If you produce a recommendation, explain the estimated cost in points.

RECOMMENDATION RULES (CRITICAL):
- Every produce_recommendation call MUST include config.conditions (array, at least 1 item) AND config.outcomes (array, at least 1 item).
- A recommendation with missing conditions or outcomes is invalid and cannot be applied. Do not emit incomplete configs.
- Use real numbers from tool results for target_value and amount — do not use placeholder values.
- Set start_date to today and end_date based on mission duration from the field guide.

DATA INTERPRETATION GUIDANCE:
- If query_member_overview shows all members as "never_bought" but query_purchase_trends shows revenue, this means purchases exist but are not linked to member accounts (user_id = null in purchase_ledger). Tell the admin this is a data quality issue — purchases were not attributed to member profiles — and recommend fixing at the data integration layer.
- If unique_buyers = 0 but transaction_count > 0, the same null user_id issue applies to purchase_trends.
- In this case, do NOT fabricate "lapsed member" analysis. Instead: (a) explain the data gap, (b) recommend missions based on the engagement data you DO have (engagement_type, earn/burn activity), OR (c) use form/event tools if this is an event-driven merchant (common for agricultural/event programs).
- engagement_type = "earn_only" for all members means they earn points but never redeem. This IS actionable: recommend an earn-only → burn nudge mission.
- If all members show never_bought but form_catalog and query_event_attendance return rich data, this merchant is event-driven — answer crop/farm/attendance questions from form and event tools, not purchase cohorts.`;

  const turnMessages: Anthropic.Messages.MessageParam[] = [
    ...messages,
    { role: 'user', content: userContent },
  ];

  // ── Create assistant message placeholder ─────────────────────────────────
  const { data: assistantRow, error: insertErr } = await db
    .from('amp_analysis_messages')
    .insert({
      thread_id: threadId,
      merchant_id: merchantId,
      role: 'assistant',
      content: '',
      status: 'streaming',
    })
    .select('id')
    .single();

  if (insertErr) {
    // Surface Supabase errors explicitly — usually a misconfigured SUPABASE_URL
    // or SUPABASE_SERVICE_ROLE_KEY on the Render service, which previously made
    // this fail silently leaving the debug panel with nothing to show.
    throw new Error(`DB insert failed: ${insertErr.message} (${insertErr.code}). Check SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY on Render.`);
  }

  const assistantMessageId: string | null = assistantRow?.id ?? null;

  // ── Run the agentic loop with a wall-clock timeout guard ─────────────────
  //
  // Promise.race: if the agent loop doesn't finish within TURN_TIMEOUT_MS,
  // the timeout leg wins, we catch it, and write a clean error row instead
  // of letting Inngest's step timeout kill us silently with no DB update.
  try {
    await Promise.race([
      executeAgentLoop({ anthropic, db, assistantMessageId, threadId, merchantId, systemPrompt, turnMessages }),
      sleep(TURN_TIMEOUT_MS),
    ]);
  } catch (err) {
    const isTimeout = err instanceof Error && err.message === 'TURN_TIMEOUT';

    if (assistantMessageId) {
      const errorContent = isTimeout
        ? 'The analysis took too long to complete. Please try again — if your question requires many data lookups, try breaking it into smaller steps.'
        : 'An error occurred during analysis. Please try again.';

      await db
        .from('amp_analysis_messages')
        .update({ content: errorContent, status: 'error' })
        .eq('id', assistantMessageId);
    }

    if (!isTimeout) throw err; // re-throw unexpected errors so Inngest can retry
  }
}

// Extracted so Promise.race can race it cleanly against the timeout.
async function executeAgentLoop(params: {
  anthropic: Anthropic;
  db: ReturnType<typeof getDb>;
  assistantMessageId: string | null;
  threadId: string;
  merchantId: string;
  systemPrompt: string;
  turnMessages: Anthropic.Messages.MessageParam[];
}) {
  const { anthropic, db, assistantMessageId, threadId, merchantId, systemPrompt } = params;
  let currentMessages = params.turnMessages;
  let iterationCount = 0;
  const MAX_ITERATIONS = 10;

  while (iterationCount < MAX_ITERATIONS) {
    iterationCount++;

    const response = await anthropic.messages.create({
      model: MODEL,
      max_tokens: 4096,
      system: systemPrompt,
      tools: TOOLS,
      messages: currentMessages,
    });

    if (response.stop_reason === 'end_turn') {
      const textContent = response.content
        .filter((b) => b.type === 'text')
        .map((b) => (b as { type: string; text: string }).text)
        .join('');

      if (assistantMessageId) {
        await db
          .from('amp_analysis_messages')
          .update({ content: textContent, status: 'complete' })
          .eq('id', assistantMessageId);
      }
      break;
    }

    if (response.stop_reason === 'tool_use') {
      const toolUseBlocks = response.content.filter((b) => b.type === 'tool_use');
      const toolCallsJson = toolUseBlocks.map((b) => {
        const tb = b as { type: string; id: string; name: string; input: Record<string, unknown> };
        return { id: tb.id, name: tb.name, input: tb.input };
      });

      if (assistantMessageId) {
        await db
          .from('amp_analysis_messages')
          .update({ tool_calls: toolCallsJson })
          .eq('id', assistantMessageId);
      }

      const toolResults = await Promise.all(
        toolCallsJson.map(async (tc) => {
          try {
            const result = await executeTool(tc.name, tc.input, merchantId, threadId, assistantMessageId);
            return { tool_use_id: tc.id, content: JSON.stringify(result) };
          } catch (err) {
            return { tool_use_id: tc.id, content: JSON.stringify({ error: String(err) }) };
          }
        }),
      );

      if (assistantMessageId) {
        await db
          .from('amp_analysis_messages')
          .update({ tool_results: toolResults })
          .eq('id', assistantMessageId);
      }

      currentMessages = [
        ...currentMessages,
        { role: 'assistant', content: response.content },
        { role: 'user', content: toolResults.map((r) => ({ type: 'tool_result' as const, ...r })) },
      ];
    }
  }
}

// ─── Inngest function ────────────────────────────────────────────────────────

export const ampAnalysisAgent = inngest.createFunction(
  { id: 'amp-analysis-agent', name: 'AMP Analysis Agent' },
  { event: 'amp/analysis.thread.started' },
  async ({ event, step }) => {
    const { thread_id, merchant_id, admin_id, message_id, content } = event.data as {
      thread_id: string;
      merchant_id: string;
      admin_id: string;
      message_id: string;
      content: string;
    };

    const db = getDb();

    // Short-circuit apply commands before loading any context
    if (classifyIntent(content) === 'apply_action') {
      return { action: 'short_circuit', intent: 'apply_action' };
    }

    // Writes a visible error assistant message so the debug panel always has
    // something to show when a pre-turn step fails (before runReasoningTurn
    // creates its own streaming placeholder).
    async function writeErrorMessage(errMsg: string) {
      const { error } = await db.from('amp_analysis_messages').insert({
        thread_id,
        merchant_id,
        role: 'assistant',
        content: errMsg,
        status: 'error',
      });
      if (error) console.error('[amp-analysis-agent] writeErrorMessage failed:', error.message);
    }

    // INIT — parallelised context load with explicit error surfacing
    let threadContext: unknown = null;
    let mvFreshness: Record<string, unknown> = {};

    try {
      [threadContext, mvFreshness] = await step.run('init-context', async () => {
        // Connectivity pre-check: exposes the true OS-level cause (ECONNREFUSED,
        // ENOTFOUND, TLS errors, etc.) that the Supabase client otherwise swallows.
        const pingUrl = `${SUPABASE_URL}/rest/v1/?select=1`;
        try {
          await fetch(pingUrl, {
            headers: {
              'apikey': SUPABASE_SERVICE_KEY,
              'Authorization': `Bearer ${SUPABASE_SERVICE_KEY}`,
            },
          });
        } catch (pingErr: unknown) {
          const e = pingErr as { message?: string; cause?: { message?: string; code?: string; errno?: number } };
          console.error('[amp-analysis] SUPABASE_CONNECTIVITY_FAIL', {
            pingUrl,
            urlLength: SUPABASE_URL?.length,
            keyDefined: !!SUPABASE_SERVICE_KEY,
            keyLength: SUPABASE_SERVICE_KEY?.length,
            error: e?.message,
            causeMessage: e?.cause?.message,
            causeCode: e?.cause?.code,
            causeErrno: e?.cause?.errno,
          });
          throw new Error(`Supabase unreachable from Render: ${e?.message} | cause: ${e?.cause?.message} (${e?.cause?.code})`);
        }

        const [ctx, freshness] = await Promise.all([
          db.rpc('fn_amp_analysis_load_thread_context', {
            p_thread_id: thread_id,
            p_merchant_id: merchant_id,
          }).then((r) => {
            if (r.error) throw new Error(`load_thread_context: ${r.error.message} (${r.error.code})`);
            return r.data;
          }),
          db.rpc('fn_amp_analysis_get_mv_freshness', {
            p_merchant_id: merchant_id,
          }).then((r) => {
            if (r.error) throw new Error(`get_mv_freshness: ${r.error.message} (${r.error.code})`);
            return r.data as Record<string, unknown>;
          }),
        ]);
        return [ctx, freshness] as [unknown, Record<string, unknown>];
      });
    } catch (err) {
      await writeErrorMessage(`Failed to load analysis context.\n\nDebug: ${err instanceof Error ? err.message : String(err)}`);
      throw err;
    }

    // Build message history helper — converts DB rows to Anthropic format,
    // excluding the current user message (already appended in runReasoningTurn).
    function buildHistory(
      ctx: unknown,
      excludeContent: string,
    ): Anthropic.Messages.MessageParam[] {
      return (
        (ctx as { messages?: Array<{ role: string; content: string }> } | null)?.messages ?? []
      )
        .slice(-MAX_HISTORY_MESSAGES)
        .filter((m) => !(m.role === 'user' && m.content === excludeContent))
        .map((m) => ({ role: m.role as 'user' | 'assistant', content: m.content ?? '' }));
    }

    const turn1History = buildHistory(threadContext, content);

    await step.run('turn-1', () =>
      runReasoningTurn({
        threadId: thread_id,
        merchantId: merchant_id,
        adminId: admin_id,
        messages: turn1History,
        contextSummary: (threadContext as { thread?: { context_summary?: Record<string, unknown> } } | null)?.thread?.context_summary ?? null,
        formCatalog: (threadContext as { form_catalog?: unknown } | null)?.form_catalog ?? [],
        mvFreshness: mvFreshness ?? {},
        merchantConfig: {},
        userContent: content,
        userMessageId: message_id,
      }),
    );

    let turnIndex = 2;
    while (true) {
      const nextMsg = await step.waitForEvent('wait-for-next-message', {
        event: 'amp/analysis.message',
        match: 'data.thread_id',
        timeout: SESSION_TIMEOUT,
      });

      if (!nextMsg) break;

      const nextData = nextMsg.data as {
        content: string;
        thread_id: string;
        merchant_id: string;
        admin_id: string;
        message_id: string;
      };

      // Reload thread context so this turn sees all prior Q&A, including
      // tool results and assistant answers from previous turns.
      const freshCtx = await step.run(`reload-context-turn-${turnIndex}`, async () => {
        const { data, error } = await getDb().rpc('fn_amp_analysis_load_thread_context', {
          p_thread_id: thread_id,
          p_merchant_id: merchant_id,
        });
        if (error) throw new Error(`reload_thread_context: ${error.message}`);
        return data;
      });

      const freshHistory = buildHistory(freshCtx, nextData.content);

      await step.run(`turn-${turnIndex}-${nextData.content.slice(0, 20)}`, () =>
        runReasoningTurn({
          threadId: thread_id,
          merchantId: merchant_id,
          adminId: admin_id,
          messages: freshHistory,
          contextSummary: (freshCtx as { thread?: { context_summary?: Record<string, unknown> } } | null)?.thread?.context_summary ?? null,
          formCatalog: (freshCtx as { form_catalog?: unknown } | null)?.form_catalog ?? [],
          mvFreshness: mvFreshness ?? {},
          merchantConfig: {},
          userContent: nextData.content,
          userMessageId: nextData.message_id,
        }),
      );

      turnIndex++;
    }

    await step.invoke('distil', {
      function: ampAnalysisDistil,
      data: { thread_id, merchant_id },
    });

    return { completed: true };
  },
);
