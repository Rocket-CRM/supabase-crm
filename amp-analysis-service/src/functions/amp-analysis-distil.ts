/**
 * amp-analysis-distil
 *
 * Invoked by amp-analysis-agent after session timeout.
 * Reads the full thread, runs a single LLM call to extract
 * structured findings, and stores them as context_summary on the thread.
 */
import { inngest } from '../inngest-client';
import { createClient } from '@supabase/supabase-js';
import Anthropic from '@anthropic-ai/sdk';

const SUPABASE_URL = process.env.SUPABASE_URL!;
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;
const ANTHROPIC_API_KEY = process.env.ANTHROPIC_API_KEY!;

function getDb() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
}

export const ampAnalysisDistil = inngest.createFunction(
  { id: 'amp-analysis-distil', name: 'AMP Analysis Distil' },
  { event: 'amp/analysis.distil' }, // also invokable directly
  async ({ event, step }) => {
    const { thread_id, merchant_id } = event.data as { thread_id: string; merchant_id: string };
    const db = getDb();

    // Load full thread history
    const threadContext = await step.run('load-thread', async () => {
      const { data } = await db.rpc('fn_amp_analysis_load_thread_context', {
        p_thread_id: thread_id,
        p_merchant_id: merchant_id,
      });
      return data;
    });

    if (!threadContext?.messages?.length) {
      return { skipped: true, reason: 'no_messages' };
    }

    // Build a transcript for the distillation prompt
    const transcript = (threadContext.messages as Array<{ role: string; content: string }>)
      .filter((m) => m.role !== 'tool')
      .map((m) => `[${m.role.toUpperCase()}]: ${m.content ?? ''}`)
      .join('\n\n');

    // Single LLM call to extract structured findings
    const contextSummary = await step.run('distil-llm', async () => {
      const anthropic = new Anthropic({ apiKey: ANTHROPIC_API_KEY });
      const response = await anthropic.messages.create({
        model: 'claude-3-5-haiku-20241022',
        max_tokens: 1024,
        messages: [
          {
            role: 'user',
            content: `Extract the key analytical findings from this loyalty analysis session transcript.

TRANSCRIPT:
${transcript}

Return a JSON object with these fields (omit fields with no findings):
{
  "member_base": "key facts about the member base",
  "earn_pattern": "how members earn points",
  "burn_pattern": "redemption behaviour",
  "aov_90d": "average order value if mentioned",
  "active_missions": "summary of active missions and their performance",
  "brand_focus": "what the brand admin was focused on",
  "recommendations": [{"title": "...", "status": "pending|applied|dismissed", "mission_id": "uuid if applied"}],
  "open_questions": ["any unresolved questions"]
}

Return ONLY the JSON object, no markdown, no explanation.`,
          },
        ],
      });

      const text = (response.content[0] as { type: string; text: string }).text;
      try {
        return JSON.parse(text);
      } catch {
        return { raw_summary: text };
      }
    });

    // Save to thread
    await step.run('save-distillation', async () => {
      await db.rpc('fn_amp_analysis_save_distillation', {
        p_thread_id: thread_id,
        p_merchant_id: merchant_id,
        p_context_summary: contextSummary,
      });
    });

    return { ok: true, thread_id };
  },
);
