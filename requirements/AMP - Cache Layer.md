# AMP — Cache Layer

## What This Document Covers

The Upstash Redis caching layer for AMP's static and semi-static configuration data. Eliminates unnecessary Postgres reads on the chokepoint/Inngest AMP path, AI agent deliberation, and workflow execution hot paths.

> **Post-Confluent:** Trigger lookups use `fn_get_active_triggers_cached` on the Inngest AMP dispatch path (not a Kafka `AmpConsumer`). Action config uses `action_registry` + `fn_get_action_registry_cached`.

For the AMP workflow engine, see `AMP - Rule Based.md`. For AI decisioning, see `AMP - AI Decisioning.md`.

---

## Problem

Multiple components in the AMP pipeline read small, rarely-changing configuration from Postgres on every event:

- **Every AMP realtime dispatch** → queries `workflow_trigger` + `workflow_master` to find matching workflows
- **Every agent deliberation cycle** → queries `amp_agent`, `action_registry`, `action_registry`, `entity_cost_normalization`, `amp_agent_performance_summary`, `amp_constraint_usage`
- **Every workflow execution** → queries `amp_workflow_node` + `amp_workflow_edge` (full graph)
- **Every message send** → queries `merchant_credentials` for LINE/SMS API keys

Total: 8-12 Postgres queries per workflow trigger, most returning data that changes days or weeks apart.

---

## Solution

**1 new Upstash Redis database** (`amp-cache`, ap-southeast-1) with cache-aside pattern. Same architectural approach as the existing CRM caches (rewards, translations, merchant config, etc.).

**Read path:**
- Render services (`amp-ai-service`, `crm-event-processors`) → Upstash REST via `@upstash/redis` SDK (direct, ~1-3ms)
- Supabase Edge Functions (`dispatch-workflow-trigger`, `inngest-amp-serve`) → Upstash REST via `fetch` or cached Postgres RPC functions (~3-5ms)
- On cache miss → query Postgres → cache result with TTL → return

**Invalidation:**
- BFF save functions call `extensions.amp_cache_del(key)` after successful writes
- DB triggers on `entity_cost_normalization` and `merchant_credentials` tables
- TTL as safety net — even without explicit invalidation, stale data expires

---

## Infrastructure

### Upstash Redis Database

| Property | Value |
|---|---|
| Name | `amp-cache` |
| Region | `ap-southeast-1` (Singapore) |
| Endpoint | `finer-mastiff-56332.upstash.io` |
| Type | Pay as You Go |

### Postgres Functions (extensions schema)

| Function | Purpose |
|---|---|
| `extensions.amp_cache_get(p_key text)` | GET from amp-cache via Upstash REST |
| `extensions.amp_cache_set(p_key text, p_value text, p_ex_mode text, p_ttl_seconds bigint)` | SET with TTL via Upstash pipeline |
| `extensions.amp_cache_del(p_key text)` | DEL from amp-cache via Upstash REST |

### Environment Variables (for Render services and Edge Functions)

| Variable | Value |
|---|---|
| `AMP_CACHE_REDIS_URL` | `https://finer-mastiff-56332.upstash.io` |
| `AMP_CACHE_REDIS_TOKEN` | (stored in Upstash console) |

---

## Cache Key Map

| # | Key Pattern | Source Table(s) | TTL | Invalidated By | Cached Getter Function |
|---|---|---|---|---|---|
| 1 | `action_types` | `action_registry` | 24h | Deploy only | `fn_get_action_registry_cached()` |
| 2 | `outcome_events` | `amp_outcome_event_config` | 24h | Deploy only | `fn_get_outcome_event_config_cached()` |
| 3 | `cost:{merchant_id}` | `entity_cost_normalization` | 30 min | DB trigger `trg_invalidate_amp_cost_cache` | `fn_get_cost_normalization_cached(merchant_id)` |
| 4 | `creds:{merchant_id}:{service}` | `merchant_credentials` | 30 min | DB trigger `trg_invalidate_amp_creds_cache` | `fn_get_merchant_credentials_cached(merchant_id, service)` |
| 5 | `triggers:{merchant_id}` | `workflow_trigger` + `workflow_master` | 10 min | `bff_upsert_amp_workflow_with_graph` | `fn_get_active_triggers_cached(merchant_id, table, op)` |
| 6 | `workflow:{workflow_id}` | `amp_workflow_node` + `amp_workflow_edge` | 10 min | `bff_upsert_amp_workflow_with_graph` | `fn_get_workflow_graph_cached(workflow_id)` |
| 7 | `agent:{agent_id}` | `amp_agent` + `action_registry` | 10 min | `bff_upsert_agent_with_children` | `fn_get_agent_config_cached(agent_id)` |
| 8 | `perf:{agent_id}` | `amp_agent_performance_summary` | 10 min | TTL only (hourly cron writes) | `fn_get_agent_performance_cached(agent_id)` |
| 9 | `constraint:{agent_id}:{user_id}` | `amp_constraint_usage` | 10 min | TTL only (10-min cron refresh) | `fn_get_constraint_usage_cached(agent_id, user_id)` |
| 10 | `constraint:{agent_id}:global` | `amp_constraint_usage` (per_agent scope) | 10 min | TTL only | `fn_get_constraint_usage_cached(agent_id, NULL)` |

---

## Who Reads What

| Component | Service | Keys Read | Before (Postgres) | After (Cache) |
|---|---|---|---|---|
| amp-dispatch / AMP routers | `inngest-event-router-serve` + edge fns | `triggers:{merchant_id}` | 1 Redis GET per dispatch | 1 Redis GET |
| OutcomeAttributionConsumer | `crm-event-processors` (Render) | `outcome_events` | 1 query per attribution | 1 Redis GET |
| Agent deliberation | `amp-ai-service` (Render) | `agent:{id}`, `action_types`, `cost:{mid}`, `perf:{id}`, `constraint:{id}:{uid}` | 5-6 queries per cycle | 5-6 Redis GETs |
| Workflow executor | `inngest-amp-serve` (Edge Function) | `workflow:{id}`, `agent:{id}` | 2-3 queries per execution | 2-3 cache hits |
| Trigger dispatcher | `dispatch-workflow-trigger` (Edge Function) | `triggers:{merchant_id}` | 1-2 queries per dispatch | 1 cache hit |
| LINE messaging | `send-line-message` (Edge Function) | `creds:{mid}:LINE` | 1 query per message | 1 cache hit |

---

## Invalidation Strategy

### Active Invalidation (on write)

| When | Function | Keys Busted |
|---|---|---|
| Workflow saved | `bff_upsert_amp_workflow_with_graph` | `triggers:{merchant_id}`, `workflow:{workflow_id}` |
| Agent saved | `bff_upsert_agent_with_children` | `agent:{agent_id}` |
| Cost config changed | `trg_invalidate_amp_cost_cache` (DB trigger) | `cost:{merchant_id}` |
| Credentials changed | `trg_invalidate_amp_creds_cache` (DB trigger) | `creds:{merchant_id}:{service}` |

### Passive Invalidation (TTL expiry)

All keys have a TTL. Even if active invalidation fails, stale data expires:
- Static seed data: 24 hours
- Semi-static config: 10-30 minutes
- Dynamic summaries: 10 minutes

### Static Seed Data

`action_types` and `outcome_events` are system-wide seed tables (11 and 8 rows). They only change on code deploy. To manually refresh after a deploy:

```sql
SELECT extensions.amp_cache_del('action_types');
SELECT extensions.amp_cache_del('outcome_events');
```

---

## Connection Patterns

### Render Services (Node.js)

Direct Upstash REST via `@upstash/redis` SDK. Sub-millisecond cache hits. No Supabase RPC overhead.

```typescript
import { Redis } from "@upstash/redis";

const ampCache = new Redis({
  url: process.env.AMP_CACHE_REDIS_URL,
  token: process.env.AMP_CACHE_REDIS_TOKEN,
});

async function getAgentConfig(agentId: string) {
  const key = `agent:${agentId}`;
  const cached = await ampCache.get(key);
  if (cached) return cached;

  const data = await supabase.rpc("fn_get_agent_config_cached", { p_agent_id: agentId });
  // The RPC itself also caches, so both paths populate Redis
  return data;
}
```

### Supabase Edge Functions (Deno)

Option A: Direct Upstash REST via `fetch`:
```typescript
async function getCached(key: string): Promise<any | null> {
  const res = await fetch(`${AMP_CACHE_URL}/get/${key}`, {
    headers: { Authorization: `Bearer ${AMP_CACHE_TOKEN}` },
  });
  const { result } = await res.json();
  return result ? JSON.parse(result) : null;
}
```

Option B: Call the cached Postgres RPC (cache-aside happens inside Postgres):
```typescript
const { data } = await supabase.rpc("fn_get_active_triggers_cached", {
  p_merchant_id: merchantId,
  p_trigger_table: triggerTable,
  p_trigger_operation: triggerOp,
});
```

### Postgres (invalidation only)

BFF functions call `extensions.amp_cache_del(key)` after successful writes:
```sql
BEGIN
  PERFORM extensions.amp_cache_del('triggers:' || v_merchant_id::TEXT);
  PERFORM extensions.amp_cache_del('workflow:' || v_workflow_id::TEXT);
EXCEPTION WHEN OTHERS THEN NULL;
END;
```

---

## Database Objects Created

### Functions

| Function | Type | Purpose |
|---|---|---|
| `extensions.amp_cache_get` | SECURITY DEFINER | Redis GET via Upstash REST |
| `extensions.amp_cache_set` | SECURITY DEFINER | Redis SET + EXPIRE via Upstash pipeline |
| `extensions.amp_cache_del` | SECURITY DEFINER | Redis DEL via Upstash REST |
| `fn_get_active_triggers_cached` | SECURITY DEFINER | Cached trigger lookup (10 min TTL) |
| `fn_get_workflow_graph_cached` | SECURITY DEFINER | Cached workflow graph (10 min TTL) |
| `fn_get_agent_config_cached` | SECURITY DEFINER | Cached agent + actions (10 min TTL) |
| `fn_get_action_registry_cached` | SECURITY DEFINER | Cached action type registry (24h TTL) |
| `fn_get_outcome_event_config_cached` | SECURITY DEFINER | Cached outcome event registry (24h TTL) |
| `fn_get_cost_normalization_cached` | SECURITY DEFINER | Cached cost config (30 min TTL) |
| `fn_get_agent_performance_cached` | SECURITY DEFINER | Cached performance summary (10 min TTL) |
| `fn_get_constraint_usage_cached` | SECURITY DEFINER | Cached constraint usage (10 min TTL) |
| `fn_get_merchant_credentials_cached` | SECURITY DEFINER | Cached credentials (30 min TTL) |

### Triggers

| Trigger | Table | Fires On | Busts |
|---|---|---|---|
| `trg_invalidate_amp_cost_cache` | `entity_cost_normalization` | INSERT, UPDATE, DELETE | `cost:{merchant_id}` |
| `trg_invalidate_amp_creds_cache` | `merchant_credentials` | INSERT, UPDATE, DELETE | `creds:{merchant_id}:{service}` |

### Modified Functions (invalidation added)

| Function | Keys Busted |
|---|---|
| `bff_upsert_amp_workflow_with_graph` (5-param) | `triggers:{merchant_id}`, `workflow:{workflow_id}` |
| `bff_upsert_agent_with_children` | `agent:{agent_id}` |

---

## Implementation Status

| Component | Status |
|---|---|
| Upstash Redis DB `amp-cache` | ✅ Created |
| `extensions.amp_cache_get/set/del` | ✅ Applied |
| Cached getter: `fn_get_active_triggers_cached` | ✅ Applied |
| Cached getter: `fn_get_workflow_graph_cached` | ✅ Applied |
| Cached getter: `fn_get_agent_config_cached` | ✅ Applied |
| Cached getter: `fn_get_action_registry_cached` | ✅ Applied + Verified |
| Cached getter: `fn_get_outcome_event_config_cached` | ✅ Applied + Verified |
| Cached getter: `fn_get_cost_normalization_cached` | ✅ Applied |
| Cached getter: `fn_get_agent_performance_cached` | ✅ Applied |
| Cached getter: `fn_get_constraint_usage_cached` | ✅ Applied |
| Cached getter: `fn_get_merchant_credentials_cached` | ✅ Applied |
| Invalidation in `bff_upsert_amp_workflow_with_graph` | ✅ Applied |
| Invalidation in `bff_upsert_agent_with_children` | ✅ Applied |
| Trigger: `trg_invalidate_amp_cost_cache` | ✅ Applied |
| Trigger: `trg_invalidate_amp_creds_cache` | ✅ Applied |
| **Render service integration** | |
| `amp-ai-service`: add `@upstash/redis`, use cached getters | ✅ PR ready (`feat/amp-cache-integration`, v4.2.0). Cache-aside on `fetchAgentGoalPerformance` (`perf:{id}`), `fetchConstraints` (`agent:{id}` + `constraint:{id}:{uid}`). Bug fix: was passing `workflow_id` instead of `agentId`. |
| `crm-event-processors`: add `@upstash/redis`, use cached triggers | ✅ PR ready (`feat/amp-cache-integration`, v1.1.0). `OutcomeAttributionConsumer` caches agent outcomes via `agent:{id}` (Redis + in-memory, 10 min TTL). |
| Edge Functions: switch to cached RPCs | ✅ Deployed. `dispatch-workflow-trigger` v40 → `fn_get_active_triggers_cached`. `inngest-amp-serve` v2 → `fn_get_workflow_graph_cached` + `fn_get_agent_config_cached`. `send-line-message` v38 → `fn_get_merchant_credentials_cached`. |
| Set env vars on Render | ⬜ Pending — `AMP_CACHE_REDIS_URL` + `AMP_CACHE_REDIS_TOKEN` on both Render services. Edge Functions use cached RPCs (no new env vars). |
