# Graph Executor — Implementation Spec

> **Deploy to:** Render `cs-ai-service` (`Rocket-CRM/cs-ai-service`)
> **Endpoint:** `POST /api/cs-voice-turn`
> **Also used by:** `voice-custom-llm` Edge Function, optionally chat pipeline (Phase 4.2)

---

## Endpoint Contract

```typescript
// POST /api/cs-voice-turn
interface VoiceTurnRequest {
  conversation_id: string;
  message_text: string;
  procedure_state?: ProcedureState | null;  // null on first turn
  context?: ConversationContext;              // pre-loaded by caller if available
}

interface VoiceTurnResponse {
  response_text: string;          // customer-facing message
  action_tools: ActionTool[];     // write operations to execute post-response
  updated_state: ProcedureState;  // save to cs_conversations.procedure_state
  next_step: 'wait_for_customer' | 'resolve' | 'escalate';
  metadata: {
    current_step_index: number;
    current_step_name: string;
    tier: 1 | 2 | 3;             // which prefetch tier was used
    prefetch_ms: number;          // prefetch duration
    llm_ms: number;               // LLM call duration
    total_ms: number;
  };
}

interface ActionTool {
  tool: string;                   // e.g. 'process_refund'
  args: Record<string, any>;
}

interface ProcedureState {
  procedure_id: string;
  procedure_name: string;
  current_step: number;
  intent: string;
  data_collected: Record<string, any>;
  actions_taken: string[];
  started_at: string;
}
```

Supports SSE streaming for voice (ElevenLabs Custom LLM expects OpenAI Chat Completions SSE format).

---

## File Structure

```
src/
  routes/
    cs-voice-turn.ts          ← Express route handler
  cs-voice/
    graph-executor.ts          ← Main 5-phase orchestrator
    entity-extractor.ts        ← Regex/keyword entity extraction
    prefetcher.ts              ← Step-aware data fetching
    aop-walker.ts              ← Code condition evaluation + step routing
    prompt-builder.ts          ← Step-focused LLM prompt construction
    action-executor.ts         ← Post-response action tool execution
    types.ts                   ← TypeScript interfaces
```

---

## graph-executor.ts — Main Orchestrator

```typescript
import { extractEntities } from './entity-extractor';
import { prefetchStepData } from './prefetcher';
import { walkAOP } from './aop-walker';
import { buildPrompt } from './prompt-builder';
import { executeActions } from './action-executor';
import { callLLM } from '../llm/openai';        // existing LLM client
import { supabase } from '../lib/supabase';       // existing Supabase client

export async function executeVoiceTurn(req: VoiceTurnRequest): Promise<VoiceTurnResponse> {
  const t0 = Date.now();

  // ═══ PHASE 1: Route + Extract (~10-20ms) ═══
  const { procedure_state, message_text, conversation_id } = req;

  // Load procedure if not in state yet
  let compiledSteps: CompiledSteps;
  let currentStep: number;
  let dataCollected: Record<string, any>;
  let intent: string;

  if (procedure_state) {
    // Follow-up turn: load procedure from state
    const proc = await supabase.rpc('cs_fn_get_active_procedure', {
      p_merchant_id: req.context.merchant_id,
      p_intent: procedure_state.intent
    });
    compiledSteps = proc.compiled_steps;
    currentStep = procedure_state.current_step;
    dataCollected = procedure_state.data_collected;
    intent = procedure_state.intent;
  } else {
    // First turn: detect intent via entity extraction + keyword matching
    // (fast LLM call for intent if needed — gpt-4o-mini, ~200ms)
    // Then load matching procedure
  }

  // Extract entities from message using compiled_steps.entity_extractors
  const entities = extractEntities(message_text, compiledSteps.entity_extractors);
  Object.assign(dataCollected, entities);

  // ═══ PHASE 2: Prefetch — step-aware (~0-300ms) ═══
  const step = compiledSteps.steps[currentStep - 1]; // 1-based index
  const tPrefetch = Date.now();

  // Always load context
  const contextPromise = req.context
    ? Promise.resolve(req.context)
    : supabase.rpc('cs_fn_load_conversation_context', { p_conversation_id: conversation_id });

  // Prefetch step's data_needs (only what's declared)
  const prefetchPromise = prefetchStepData(step, dataCollected, compiledSteps, req.context?.merchant_id);

  const [context, prefetchedData] = await Promise.all([contextPromise, prefetchPromise]);
  const prefetchMs = Date.now() - tPrefetch;

  // Determine tier
  const tier = step.data_needs.length > 0
    ? (step.data_needs.some(d => d.source !== 'knowledge') ? 1 : 2)
    : (compiledSteps ? 2 : 3);

  // ═══ PHASE 3: Walk AOP graph (~5-10ms) ═══
  const walkResult = walkAOP(compiledSteps, currentStep, dataCollected, prefetchedData);
  // walkResult: { targetStep, skippedSteps[], resolvedConditions[] }

  const targetStep = compiledSteps.steps[walkResult.targetStep - 1];

  // ═══ PHASE 4: ONE LLM call (~500ms-1s) ═══
  const tLLM = Date.now();

  const prompt = buildPrompt({
    step: targetStep,
    context,
    prefetchedData,
    dataCollected,
    procedure: { name: procedure_state?.procedure_name, flexibility: 'guided' },
    config: context.config
  });

  const llmResponse = await callLLM({
    model: 'gpt-4o',
    messages: [
      { role: 'system', content: prompt.system },
      ...prompt.history,
      { role: 'user', content: message_text }
    ],
    response_format: { type: 'json_object' }
  });

  const parsed = JSON.parse(llmResponse.content);
  const llmMs = Date.now() - tLLM;

  // ═══ PHASE 5: Return response, execute actions async ═══
  const updatedState: ProcedureState = {
    procedure_id: procedure_state?.procedure_id || compiledSteps.procedure_id,
    procedure_name: procedure_state?.procedure_name || compiledSteps.procedure_name,
    current_step: walkResult.targetStep,
    intent,
    data_collected: { ...dataCollected, ...parsed.data_collected },
    actions_taken: [...(procedure_state?.actions_taken || []), ...(parsed.actions?.map(a => a.tool) || [])],
    started_at: procedure_state?.started_at || new Date().toISOString()
  };

  // Execute action tools async (don't await — response goes first)
  if (parsed.actions?.length > 0) {
    executeActions(parsed.actions, context).catch(err =>
      console.error('Action execution error:', err)
    );
  }

  return {
    response_text: parsed.message || parsed.customer_message,
    action_tools: parsed.actions || [],
    updated_state: updatedState,
    next_step: parsed.next_step || 'wait_for_customer',
    metadata: {
      current_step_index: walkResult.targetStep,
      current_step_name: targetStep.name,
      tier,
      prefetch_ms: prefetchMs,
      llm_ms: llmMs,
      total_ms: Date.now() - t0
    }
  };
}
```

---

## entity-extractor.ts

```typescript
interface EntityExtractor {
  variable: string;
  type: 'regex' | 'keyword';
  pattern?: string;     // for regex
  keywords?: string[];  // for keyword
}

export function extractEntities(
  message: string,
  extractors: EntityExtractor[]
): Record<string, string> {
  const result: Record<string, string> = {};

  for (const ext of extractors) {
    if (ext.type === 'regex' && ext.pattern) {
      const match = message.match(new RegExp(ext.pattern, 'i'));
      if (match) {
        result[ext.variable] = match[1] || match[0];
      }
    } else if (ext.type === 'keyword' && ext.keywords) {
      const lower = message.toLowerCase();
      const found = ext.keywords.find(kw => lower.includes(kw.toLowerCase()));
      if (found) {
        result[ext.variable] = found;
      }
    }
  }

  return result;
}
```

---

## prefetcher.ts — Step-Aware Data Fetching

```typescript
import { lookupOrder } from '../tools/cs-actions/lookup-order';
import { searchKnowledge } from '../tools/cs-actions/search-knowledge';
import { getRecentOrders } from '../tools/cs-actions/recent-orders';

// Same tool functions that MCP server exposes — imported directly
// No MCP protocol overhead since we're in the same process

interface DataNeed {
  source: string;
  args_from?: Record<string, string>;
  query_hints?: string[];
  when: string;
  limit?: number;
}

export async function prefetchStepData(
  step: Step,
  dataCollected: Record<string, any>,
  compiledSteps: CompiledSteps,
  merchantId: string
): Promise<Record<string, any>> {
  const prefetched: Record<string, any> = {};
  const promises: Promise<void>[] = [];

  // Step's declared data_needs
  for (const need of step.data_needs || []) {
    if (!evaluateWhen(need.when, dataCollected)) continue;

    const args = resolveArgs(need.args_from || {}, dataCollected);

    if (need.source === 'knowledge') {
      promises.push(
        searchKnowledge({
          merchant_id: merchantId,
          query: need.query_hints?.[0] || step.step_topic,
          top_k: 5
        }).then(chunks => { prefetched.knowledge = chunks; })
      );
    } else if (need.source === 'lookup_order') {
      promises.push(
        lookupOrder(args).then(order => { prefetched.order = order; })
      );
    } else if (need.source === 'recent_orders') {
      promises.push(
        getRecentOrders({ merchant_id: merchantId, limit: need.limit || 3 })
          .then(orders => { prefetched.recent_orders = orders; })
      );
    }
    // Extend for: check_stock, get_customer_profile, etc.
  }

  // Default fallback: if no entities and no data_needs, check default_data_needs
  if (promises.length === 0 && Object.keys(dataCollected).length === 0) {
    const defaults = compiledSteps.default_data_needs?.no_entities || [];
    for (const def of defaults) {
      if (def.source === 'recent_orders') {
        promises.push(
          getRecentOrders({ merchant_id: merchantId, limit: def.limit || 3 })
            .then(orders => { prefetched.recent_orders = orders; })
        );
      }
    }
  }

  await Promise.all(promises);
  return prefetched;
}

function evaluateWhen(when: string, data: Record<string, any>): boolean {
  if (when === 'always') return true;
  // Parse "variable IS NOT NULL" patterns
  const match = when.match(/^(\w+)\s+IS\s+NOT\s+NULL$/i);
  if (match) return data[match[1]] != null;
  return true; // default: fetch
}

function resolveArgs(
  argsFrom: Record<string, string>,
  data: Record<string, any>
): Record<string, any> {
  const resolved: Record<string, any> = {};
  for (const [argName, varName] of Object.entries(argsFrom)) {
    resolved[argName] = data[varName];
  }
  return resolved;
}
```

---

## aop-walker.ts — Deterministic Graph Navigation

Walk loop iterates through steps using three advancement mechanisms:
1. **skip_condition** — explicit skip rule on the step
2. **variables_out completion** — all declared output variables are collected (auto-advance for data-collection steps that lack code_conditions)
3. **code_conditions** — deterministic branching based on required_variables

```typescript
interface WalkResult {
  targetStep: number;
  targetStepObj: Step;
  skippedSteps: number[];
  resolvedConditions: string[];
}

export function walkAOP(
  compiledSteps: CompiledSteps,
  currentStepIndex: number,
  dataCollected: Record<string, any>,
  prefetchedData: Record<string, any>
): WalkResult {
  const allData = { ...dataCollected, ...flattenPrefetched(prefetchedData) };
  const skipped: number[] = [];
  const conditions: string[] = [];

  let step = compiledSteps.steps.find(s => s.index === currentStepIndex);
  if (!step) step = compiledSteps.steps[0];

  let iterations = 0;
  while (iterations < 10) {
    iterations++;

    // 1) Explicit skip_condition
    if (step.skip_condition && canSkip(step, allData)) {
      skipped.push(step.index);
      const nextIdx = step.next || step.index + 1;
      const nextStep = compiledSteps.steps.find(s => s.index === nextIdx);
      if (nextStep) { step = nextStep; continue; }
    }

    // 2) Auto-advance: variables_out all collected, no code_conditions
    if (!step.code_conditions?.length && step.variables_out?.length) {
      const allCollected = step.variables_out.every(v => allData[v] != null);
      if (allCollected) {
        skipped.push(step.index);
        const nextIdx = step.next || step.index + 1;
        const nextStep = compiledSteps.steps.find(s => s.index === nextIdx);
        if (nextStep) {
          conditions.push(`step ${step.index} variables_out complete → advance to ${nextIdx}`);
          step = nextStep; continue;
        }
      }
    }

    // 3) Evaluate code_conditions — if a condition matches, jump and return
    if (step.code_conditions?.length > 0) {
      const hasAll = (step.required_variables || []).every(v => allData[v] != null);
      if (hasAll) {
        for (const cond of step.code_conditions) {
          if (evaluateCondition(cond.condition, allData)) {
            conditions.push(`${cond.condition} → goto ${cond.goto}`);
            const target = compiledSteps.steps.find(s => s.index === cond.goto);
            return { targetStep: cond.goto, targetStepObj: target || step, skippedSteps: skipped, resolvedConditions: conditions };
          }
        }
      }
    }

    break; // No deterministic advancement possible
  }

  return { targetStep: step.index, targetStepObj: step, skippedSteps: skipped, resolvedConditions: conditions };
}

function evaluateCondition(condition: string, data: Record<string, any>): boolean {
  // Safe evaluation of simple boolean expressions
  // Supports: ==, !=, <=, >=, <, >, AND, OR, NOT, true, false
  try {
    let expr = condition;
    // Replace variable references with actual values
    for (const [key, val] of Object.entries(data)) {
      const regex = new RegExp(`\\b${key}\\b`, 'g');
      if (typeof val === 'string') expr = expr.replace(regex, `'${val}'`);
      else if (typeof val === 'boolean') expr = expr.replace(regex, String(val));
      else if (typeof val === 'number') expr = expr.replace(regex, String(val));
      else if (val == null) expr = expr.replace(regex, 'null');
    }
    // Simple safe eval (no Function constructor in production — use a parser)
    // In production: use a proper expression parser like jsep + custom evaluator
    return Boolean(safeEval(expr));
  } catch {
    return false;
  }
}

function flattenPrefetched(data: Record<string, any>): Record<string, any> {
  const flat: Record<string, any> = {};
  if (data.order) {
    flat.order_status = data.order.status;
    flat.order_total = data.order.total;
    flat.delivered_at = data.order.delivered_at;
    if (data.order.delivered_at) {
      const days = Math.floor((Date.now() - new Date(data.order.delivered_at).getTime()) / 86400000);
      flat.days_since_purchase = days;
      flat.days_since_delivery = days;
    }
  }
  return flat;
}
```

---

## prompt-builder.ts — Context Compression

```typescript
export function buildPrompt(params: {
  step: Step;
  context: ConversationContext;
  prefetchedData: Record<string, any>;
  dataCollected: Record<string, any>;
  procedure: { name: string; flexibility: string };
  config: BrandConfig;
}): { system: string; history: Message[] } {
  const { step, context, prefetchedData, dataCollected, procedure, config } = params;

  // Context compression: only current step topic + data, not full AOP
  let system = `You are a customer service agent for ${config.brand_name || 'the brand'}.`;

  // Tone
  if (step.tone_override || config.voice_preset) {
    system += `\nTone: ${step.tone_override || config.voice_preset}`;
  }

  // Current step instruction
  system += `\n\nYou are on step "${step.name}" of the "${procedure.name}" procedure.`;
  system += `\nStep purpose: ${step.step_topic}`;

  // Inject prefetched data as facts
  if (prefetchedData.order) {
    system += `\n\n[ORDER DATA — pre-loaded, do not call lookup_order]`;
    system += `\n${JSON.stringify(prefetchedData.order, null, 2)}`;
  }
  if (prefetchedData.knowledge?.length > 0) {
    system += `\n\n[KNOWLEDGE — pre-loaded, do not call search_knowledge]`;
    for (const chunk of prefetchedData.knowledge) {
      system += `\n- ${chunk.content} (score: ${chunk.score})`;
    }
  }
  if (prefetchedData.recent_orders?.length > 0) {
    system += `\n\n[RECENT ORDERS — pre-loaded]`;
    system += `\n${JSON.stringify(prefetchedData.recent_orders, null, 2)}`;
  }

  // Collected data so far
  if (Object.keys(dataCollected).length > 0) {
    system += `\n\n[DATA COLLECTED SO FAR]`;
    system += `\n${JSON.stringify(dataCollected, null, 2)}`;
  }

  // Customer profile
  system += `\n\n[CUSTOMER] ${context.contact?.name || 'Unknown'}`;
  if (context.contact?.tier) system += `, ${context.contact.tier} tier`;

  // Available action tools (LLM can request these)
  if (step.action_tools?.length > 0) {
    system += `\n\n[AVAILABLE ACTIONS — return in "actions" array if needed]`;
    for (const at of step.action_tools) {
      system += `\n- ${at.tool}${at.requires_confirmation ? ' (requires customer confirmation first)' : ''}`;
    }
  }

  // Response format
  system += `\n\nRespond in JSON: { "message": "customer-facing text", "actions": [{ "tool": "name", "args": {} }], "next_step": "wait_for_customer|resolve|escalate", "data_collected": {} }`;

  // Conversation history (last N messages for context)
  const history = (context.messages || []).slice(-10).map(m => ({
    role: m.sender_type === 'customer' ? 'user' as const : 'assistant' as const,
    content: m.content
  }));

  return { system, history };
}
```

---

## action-executor.ts — Post-Response Actions

```typescript
import { processRefund } from '../tools/cs-actions/process-refund';
import { awardPoints } from '../tools/crm-loyalty/award-points';
import { createTicket } from '../tools/cs-actions/create-ticket';
import { escalateToHuman } from '../tools/cs-actions/escalate';

const TOOL_MAP: Record<string, (args: any) => Promise<any>> = {
  process_refund: processRefund,
  award_points: awardPoints,
  create_ticket: createTicket,
  escalate_to_human: escalateToHuman,
};

export async function executeActions(
  actions: ActionTool[],
  context: ConversationContext
): Promise<void> {
  const results = await Promise.allSettled(
    actions.map(async (action) => {
      const fn = TOOL_MAP[action.tool];
      if (!fn) {
        console.warn(`Unknown action tool: ${action.tool}`);
        return;
      }
      return fn({ ...action.args, merchant_id: context.merchant_id });
    })
  );

  for (let i = 0; i < results.length; i++) {
    const r = results[i];
    if (r.status === 'rejected') {
      console.error(`Action ${actions[i].tool} failed:`, r.reason);
    }
  }
}
```

---

## Express Route

```typescript
// src/routes/cs-voice-turn.ts
import { Router } from 'express';
import { executeVoiceTurn } from '../cs-voice/graph-executor';

const router = Router();

router.post('/api/cs-voice-turn', async (req, res) => {
  try {
    const result = await executeVoiceTurn(req.body);

    // For voice: stream as SSE (OpenAI Chat Completions format)
    if (req.headers['accept'] === 'text/event-stream') {
      res.setHeader('Content-Type', 'text/event-stream');
      res.setHeader('Cache-Control', 'no-cache');

      // Stream response text in chunks
      const words = result.response_text.split(' ');
      for (const word of words) {
        const chunk = {
          choices: [{ delta: { content: word + ' ' } }]
        };
        res.write(`data: ${JSON.stringify(chunk)}\n\n`);
      }
      res.write('data: [DONE]\n\n');
      res.end();
    } else {
      // For chat/API: return full JSON
      res.json(result);
    }
  } catch (err) {
    console.error('Voice turn error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

export default router;
```

---

## Testing

```bash
# Test Tier 2 (conversation only — no data tools)
curl -X POST http://localhost:3000/api/cs-voice-turn \
  -H 'Content-Type: application/json' \
  -d '{
    "conversation_id": "conv_001",
    "message_text": "สวัสดีค่ะ อยากถามเรื่องกล่องสุ่ม",
    "procedure_state": null
  }'

# Test Tier 1 (with order data prefetch)
curl -X POST http://localhost:3000/api/cs-voice-turn \
  -H 'Content-Type: application/json' \
  -d '{
    "conversation_id": "conv_001",
    "message_text": "order PM-12345 ของเสียหาย อยากขอคืนเงิน",
    "procedure_state": null
  }'
```
