# Loyalty cache redesign — Redis at Render, plain SQL, one purge event

Status: approved design, ready to execute in one thread.
Author thread: 2026-09-22. Supabase project: `wkevmsedchftztoolkmi` (never any other; never `list_projects`).

This document is written for an execution agent. Follow it literally. Where it says VERIFY, run the check and stop if the result differs from what is written here. Where it says ASK, stop and ask the user before continuing. Do not improvise alternative designs; if something in here cannot be done as written, report the exact blocker and ask.

---

## 0. Vocabulary (use these words exactly)

| Word | Means | Does NOT mean |
|---|---|---|
| **Redis** | The one Upstash database `loyalty-cache` that holds cached JSON payloads. The only cache we manage. | Any of the 7 legacy Upstash databases called from SQL |
| **Render API** | The Node/Express service `loyalty-cache-api` on Render. It reads/writes Redis and, on a miss, calls Postgres. It is a program, not a cache. | A cache store |
| **Vercel Data Cache** | Next.js built-in: stores Render API HTTP responses inside `loyalty-user` on Vercel for 300 s, per URL, all users. | Per-user or per-request storage |
| **React.cache** | Dedupes identical loader calls within one server render. Out of scope. Do not touch. | A cache tier |
| **Postgres** | Truth. After this plan, its functions contain no Redis logic. | A cache |
| **Scope** | A named group of cache keys that one kind of admin change invalidates. Fixed list in §3.3. | A route or a table |
| **Purge** | Delete Redis keys + drop Vercel Data Cache tags for one merchant and one or more scopes. Never a write. | Rebuild / warm |

Target read path (stop at first hit):

```
member app / Shopify storefront
  → Vercel Data Cache (tags: lc:all, m:{merchant_code}, m:{merchant_code}:{scope})
  → Render API  GET /v1/...
  → Redis       GET lc:{merchant_code}:{scope}:{variant}
  → Postgres    plain function → Render writes result to Redis (TTL 600 s) → returns
admin → Postgres directly, uncached
```

Target invalidation path:

```
admin write → row trigger (deferred to commit) → fn_cache_purge_emit(merchant_id, scopes)
  → pg_net POST {RENDER}/v1/purge { merchant_code, scopes }
  → Render deletes lc:{merchant_code}:{scope}:*  and POSTs {LOYALTY_USER}/api/revalidate { tags }
  → Next.js revalidateTag(...)
  → next member request misses both caches, Postgres recomputes, Redis refills
```

---

## 1. Verified current state (2026-09-22, live DB + local clones)

Do not re-derive these; VERIFY only the ones marked.

1. `~/Documents/rocket/loyalty-cache-api` has **no Redis client**. Cross-request cache = `src/cache/memory-cache.ts` (`Map` `store`, `Map` `inFlight`; exports `cacheKey`, `getCached`, `getStale`, `setCached`, `singleFlight`). `src/cache/serve-cached.ts` exports `serveCached(req, res, key, loader, send)` and uses `singleFlight` on miss.
2. Routes in `src/routes/`: `bootstrap.ts`, `rewards.ts`, `earn-channels.ts`, `display-blocks.ts`, `language-pack.ts`, `tier.ts`, `consent.ts`. Mounted in `src/server.ts` under `/v1` with `optionalApiKey` (header `x-cache-api-key` vs env `CACHE_API_KEY`) and `rateLimitUnlessKeyed` (600/min unkeyed). Health `/health`. `render.yaml`: Standard ×2, env `DATABASE_URL`, `CACHE_API_KEY`, `DB_POOL_MAX=8`, `CACHE_TTL_SECONDS=300`. Scripts: `dev`, `build`, `start`, `typecheck`. No test framework.
3. **VERIFY (Phase 0):** `src/routes/earn-channels.ts` is untracked and `src/server.ts`, `src/db/rpc.ts` are modified in the local clone; `origin/main` does not have `/v1/earn-channels`.
4. `src/db/rpc.ts:45-48` sets merchant context per transaction: `BEGIN; SELECT set_config('request.headers', '{"x-merchant-code": "<code>"}', true)`. SQL functions that use `get_current_merchant_id()` read this header and look up `merchant_master.id` by `merchant_code`.
5. `~/Documents/rocket/loyalty-user`: all Render fetches go through `src/lib/api/cache-api-server.ts` → `fetch(base+path, { headers: cacheApiHeaders(), next: { revalidate: 300 } })`. **No `tags`.** No `/api/revalidate` route. `revalidateTag` exists only in `src/lib/shopify/admin.ts:41` for an unrelated Shopify catalog tag — leave it. Next.js `16.2.1`, App Router. Flag `LOYALTY_CACHE_READS_VIA` read in `src/lib/api/cache-api.ts:29-31`; env `LOYALTY_CACHE_API_URL`, `LOYALTY_CACHE_API_KEY`.
6. Live SQL functions Render calls today, with signatures and merchant resolution:

| Function | Signature | Merchant | Uses legacy Redis inside SQL |
|---|---|---|---|
| `api_get_rewards_full_cached` | `(p_language text DEFAULT NULL, p_persona_id uuid DEFAULT NULL)` | header | yes — `extensions.rewards_cache_get/set` |
| `bff_get_earn_channels` | `(p_language text DEFAULT NULL, p_surface text DEFAULT NULL)` | header | yes — `extensions.earn_channels_cache_get/set` |
| `api_get_display_blocks_cached` | `(p_page text DEFAULT NULL, p_language text DEFAULT NULL, p_merchant_code text DEFAULT NULL)` | param or header; persona from `auth.uid()` else `'guest'` | yes — `extensions.display_blocks_cache_get/set` |
| `get_ui_translations` | `(p_page_key text DEFAULT NULL, p_language text DEFAULT 'en', p_merchant_code text DEFAULT NULL)` | param or header | yes — `extensions.ui_cache_get/set` |
| `api_get_consent_documents_cached` | `(p_merchant_code text, p_language text DEFAULT 'en', p_consent_type text DEFAULT NULL)` | param | yes — `extensions.ui_cache_get/set` |
| `get_tier_display_config` | `()` | header | no |
| `get_display_settings_fast` | `(p_merchant_code text)` | param | no |
| `api_get_merchant_languages` | `(p_merchant_code text)` | param | no |
| `bff_get_auth_config` | `(p_merchant_code text)` | param | no |
| `get_liff_config` | `(p_merchant_code text)` | param | no |

   Not yet on Render (Phase 4 adds them):

| Function | Signature | Current caller |
|---|---|---|
| `api_get_widget_settings_cached` | `(p_widget_type text, p_merchant_code text)` | `rewarding-shopify/widget-builder/src/services/widgetSettings.js` (PostgREST POST), `rewarding-shopify/extensions/loyalty-widget/assets/points-on-product.js` (PostgREST POST, `p_widget_type:'shopify', p_merchant_code: shop`) |
| `api_get_shopify_landing_page_cached` | `(p_merchant_code text, p_language text DEFAULT 'en')` | `supabase-crm/supabase/functions/shopify-proxy/index.ts` ~L87 and ~L159 |
| `api_get_store_home_config_cached` | `(p_merchant_code text)` | `loyalty-user/src/lib/shopify/store-cms.ts:47` |

7. Legacy Redis: 7 Upstash databases, URL + bearer token **hardcoded inside `extensions.*_cache_get/set/del` function bodies** (Postgres `http` extension). Loyalty families in scope of this plan: `rewards_cache_*` (host `mutual-stud-37574`), `earn_channels_cache_*` (`keen-koala-67759`), `display_blocks_cache_*` (`special-sparrow-18357`), `ui_cache_*` (`free-hound-25865`). **Out of scope — do not touch:** `user_profile_cache_*` (`crisp-bison-32725`), `merchant_config_cache_*` (`sweet-cardinal-5243`), `amp_cache_*` (`finer-mastiff-56332`), `extensions.redis_get/set/del` (`usable-ray-20184`, marketplace).
8. Legacy invalidation is **broken by key mismatch** (confirmed from live bodies): earn deletes without `:surface:{default|shopify}`; display blocks deletes without `:persona:{guest|uuid}`; widget deletes `merchant:{id}:widget:{type}` but reads `…:widget:v2:{type}`; landing deletes without `v2`; `trigger_invalidate_cache_on_language_change` deletes `rewards:all_languages` but reads are per-language. This plan removes all of it (Phase 5) rather than patching.
9. `pg_net` 0.19.5 installed: `net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer)`. `supabase_vault` installed; pattern in use: `SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = '...'` (e.g. `public.get_messaging_auth_key()`).
10. `translations` has `merchant_id uuid NOT NULL`, `entity_type`, `entity_id`. Entity types used by legacy invalidators: `'reward'`, `'display_block_item'`, `'earn_channel'`. **VERIFY (Phase 3):** `SELECT DISTINCT entity_type FROM translations`.
11. Only admin call to a `*_cached` function: `loyalty-admin/src/app/(admin)/display-settings/actions.ts:98` → `supabase.rpc("api_get_rewards_full_cached")`. No plain `api_get_rewards_full` exists live.
12. AMP Redis client pattern to copy: `amp-ai-service/src/connections.ts:31-39` — lazy singleton `new Redis({ url: process.env.AMP_CACHE_REDIS_URL!, token: process.env.AMP_CACHE_REDIS_TOKEN! })` from `@upstash/redis`.
13. Docs that describe the old model and must be updated in Phase 6: `supabase-crm/requirements/Member_App_Cached_Reads.md`, `supabase-crm/requirements/Reward_Cache_Implementation.md`, `supabase-crm/requirements/Display_Settings.md` (invalidation section), `supabase-crm/requirements/REGISTRY_RENDER.md`, `supabase-crm/requirements/REGISTRY_SUPABASE.md`, `loyalty-user/docs/ai/loyalty-cache-api-plan.md`.

---

## 2. Rules for the execution thread

- Repos and where to edit: `~/Documents/rocket/loyalty-cache-api`, `~/Documents/rocket/loyalty-user`, `~/Documents/rocket/loyalty-admin`, `~/Documents/rocket/rewarding-shopify`, `~/Documents/rocket/supabase-crm` (Edge function source + docs). Backend SQL via Supabase MCP `apply_migration` on `wkevmsedchftztoolkmi` only. `git pull --ff-only` each repo before editing. Commit per repo with the messages given. **Do not `git push` and do not deploy** until the user says so at the gates in §9.
- Do not touch: AMP, marketplace, user-profile-template, merchant-config Redis families; `React.cache`; the tier-progress/expiry cron cache (`loyalty-cache-dirty-5m`, `LOYALTY_PROGRESS_EXPIRY_CACHE.md`); `src/lib/shopify/admin.ts` in loyalty-user.
- Keep every SQL function's output shape identical. The plain twins are "same body minus the Redis get/set lines", nothing else.
- When a step says VERIFY and the live result differs, stop and report; do not adapt silently.
- Approval gates are listed in §9. Everything else in this document is pre-approved by the user.

User must provide before start (ASK if missing):

| Input | Used for |
|---|---|
| Upstash REST URL + token of a **new** database named `loyalty-cache` (create in Upstash console; region close to Render) | Render env `LOYALTY_CACHE_REDIS_URL`, `LOYALTY_CACHE_REDIS_TOKEN` |
| Public base URL of the Render service (e.g. `https://loyalty-cache-api.onrender.com`) | Vault secret `loyalty_cache_purge_url`, Edge env |
| Production URL of loyalty-user (e.g. `https://app.example.com`) | Render env `LOYALTY_USER_REVALIDATE_URL` |

Generate two secrets yourself with `openssl rand -hex 32`: `CACHE_PURGE_SECRET` (Postgres → Render) and `REVALIDATE_SECRET` (Render → Vercel). Print them once for the user to store.

---

## 3. Design decisions (fixed)

### 3.1 Redis key format

```
lc:{merchant_code}:{scope}:{variant}
```

`variant` = sorted `k=v` pairs joined by `&`, e.g. `language=th&personaId=` . Keyed by `merchant_code` (what Render receives on every request) — no id lookup on the hot path. Composed only in `src/cache/keys.ts`. TTL 600 s (`CACHE_TTL_SECONDS=600`).

### 3.2 Vercel tags

Every `loyalty-user` fetch to Render carries three tags: `lc:all`, `m:{merchant_code}`, `m:{merchant_code}:{scope}`. Purge revalidates the narrowest tag that matches.

### 3.3 Scopes (closed list)

| Scope | Render route(s) | Postgres function(s) on miss |
|---|---|---|
| `bootstrap` | `/v1/bootstrap` | `get_display_settings_fast`, `api_get_merchant_languages`, `get_ui_translations`, `bff_get_auth_config`, `get_liff_config`, `api_get_display_blocks*` ×3 |
| `rewards` | `/v1/rewards/catalog` | `api_get_rewards_full*` |
| `earn_channels` | `/v1/earn-channels` | `bff_get_earn_channels` |
| `display_blocks` | `/v1/display-blocks` | `api_get_display_blocks*` |
| `language_pack` | `/v1/language-pack` | `get_ui_translations`, `api_get_display_blocks*` ×3 |
| `tier_display` | `/v1/tier-display` | `get_tier_display_config` |
| `consent` | `/v1/consent/documents` | `api_get_consent_documents*` |
| `widget` | `/v1/widget-settings` (new) | `api_get_widget_settings*` |
| `shopify_landing` | `/v1/shopify-landing` (new) | `api_get_shopify_landing_page*` |
| `store_home` | `/v1/store-home` (new) | `api_get_store_home_config*` |
| `all` | purge-only | — |

(`*` = `_cached` name until Phase 5, plain name after.)

### 3.4 Purge contract

`POST {RENDER}/v1/purge`, header `x-purge-secret: <CACHE_PURGE_SECRET>`, body:

```json
{ "merchant_code": "acme" | null, "scopes": ["rewards", "shopify_landing"] }
```

- `merchant_code` null → global: `FLUSHDB` on Redis, revalidate tag `lc:all`.
- scopes contains `all` → delete prefix `lc:{merchant_code}:`, revalidate `m:{merchant_code}`.
- otherwise for each scope → delete prefix `lc:{merchant_code}:{scope}:`, revalidate `m:{merchant_code}:{scope}`.
- Response `200 { deleted: number, tags: string[], revalidated: boolean }`. Unknown scope → `400`. Bad secret → `401`.
- Purge is idempotent; duplicates are harmless.

### 3.5 Trigger design (Postgres)

One emitter, three thin trigger functions, no queue table:

- `fn_cache_purge_emit(p_merchant_id uuid, p_scopes text[])` — dedups within the transaction via a transaction-local GUC (`set_config('cache_purge.sent', ..., true)`), resolves `merchant_code`, reads URL + secret from Vault, calls `net.http_post` (async). Swallows errors with `RAISE WARNING`; TTL is the backstop.
- `trigger_cache_purge()` — generic row trigger; `TG_ARGV[0]` = comma-separated scopes; `TG_ARGV[1]` = merchant column name (default `merchant_id`).
- `trigger_cache_purge_translations()` — maps `translations.entity_type` → scopes.
- `trigger_cache_purge_global()` — for template tables without merchant; emits `(NULL, scopes)`.

All are created as `CONSTRAINT TRIGGER ... DEFERRABLE INITIALLY DEFERRED FOR EACH ROW` so they run at commit, after the data is visible, and the dedup collapses a 20-row admin save into one POST per (merchant, scope-set).

### 3.6 SQL functions

Plain twins with the same signature and same body minus Redis: `api_get_rewards_full`, `api_get_display_blocks`, `api_get_consent_documents`, `api_get_widget_settings`, `api_get_shopify_landing_page`, `api_get_store_home_config`. `bff_get_earn_channels` and `get_ui_translations` keep their names and are `CREATE OR REPLACE`d minus Redis. The `_cached` functions are dropped at the end of Phase 5.

Accepted deviation from `api_*` convention: `api_get_rewards_full` keeps header-based merchant resolution because the `_cached` version does; do not change resolution in this plan.

---

## 4. Phase 0 — Ground truth and prerequisites

1. `cd ~/Documents/rocket/loyalty-cache-api && git status -sb && git diff` — VERIFY §1.3. Read the diff of `src/server.ts` and `src/db/rpc.ts` and the new `src/routes/earn-channels.ts`. If it is only the earn-channels route + its rpc + mount, commit: `feat: add /v1/earn-channels route`. If it contains anything else, ASK.
2. Snapshot every function this plan will change or drop, to `~/Documents/rocket/supabase-crm/docs/cache-redesign/legacy-functions-snapshot.sql` (create folder). For each name in §7.3 and §1.6 run `SELECT pg_get_functiondef(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('public','extensions') AND p.proname = '<name>'` and append. Also snapshot trigger DDL: `SELECT pg_get_triggerdef(oid) FROM pg_trigger WHERE tgname IN (...)` for §7.2. Commit in supabase-crm: `docs: snapshot legacy cache functions before redesign`.
3. Vault secrets (Supabase MCP `execute_sql`):
   ```sql
   SELECT vault.create_secret('<RENDER_BASE_URL>/v1/purge', 'loyalty_cache_purge_url');
   SELECT vault.create_secret('<CACHE_PURGE_SECRET>', 'loyalty_cache_purge_secret');
   ```
   VERIFY: `SELECT name FROM vault.decrypted_secrets WHERE name LIKE 'loyalty_cache_purge_%'` returns 2 rows.
4. Render env (Render MCP `update_environment_variables` on service `loyalty-cache-api`, or ASK user to set): `LOYALTY_CACHE_REDIS_URL`, `LOYALTY_CACHE_REDIS_TOKEN`, `CACHE_PURGE_SECRET`, `LOYALTY_USER_REVALIDATE_URL=<LOYALTY_USER_URL>/api/revalidate`, `REVALIDATE_SECRET`, `CACHE_TTL_SECONDS=600`. Do not trigger a deploy yet.
5. Vercel env for loyalty-user (ASK user to set in Vercel dashboard): `REVALIDATE_SECRET` (same value).

---

## 5. Phase 1 — Redis at Render, memory cache removed (`loyalty-cache-api`)

### 5.1 Dependency

`npm i @upstash/redis` (match the package manager in the repo — check for `package-lock.json` / `pnpm-lock.yaml`).

### 5.2 New `src/cache/keys.ts`

```ts
export const SCOPES = [
  "bootstrap", "rewards", "earn_channels", "display_blocks", "language_pack",
  "tier_display", "consent", "widget", "shopify_landing", "store_home",
] as const
export type Scope = (typeof SCOPES)[number]

export function isScope(s: string): s is Scope {
  return (SCOPES as readonly string[]).includes(s)
}

/** lc:{merchant_code}:{scope}:{k=v&k=v} — the ONLY place keys are composed. */
export function redisKey(
  merchantCode: string,
  scope: Scope,
  variant: Record<string, string | undefined | null> = {},
): string {
  const v = Object.keys(variant)
    .sort()
    .map((k) => `${k}=${variant[k] ?? ""}`)
    .join("&")
  return `lc:${merchantCode}:${scope}:${v}`
}

export function scopePrefix(merchantCode: string, scope: Scope): string {
  return `lc:${merchantCode}:${scope}:`
}
export function merchantPrefix(merchantCode: string): string {
  return `lc:${merchantCode}:`
}
```

### 5.3 New `src/cache/redis-cache.ts`

```ts
import { Redis } from "@upstash/redis"

let client: Redis | undefined
export function getRedis(): Redis {
  if (!client) {
    const url = process.env.LOYALTY_CACHE_REDIS_URL
    const token = process.env.LOYALTY_CACHE_REDIS_TOKEN
    if (!url || !token) throw new Error("LOYALTY_CACHE_REDIS_URL/TOKEN not set")
    client = new Redis({ url, token })
  }
  return client
}

export const CACHE_TTL_SECONDS = Number(process.env.CACHE_TTL_SECONDS ?? 600)

// single-flight per key, per process (kept from memory-cache.ts)
const inFlight = new Map<string, Promise<unknown>>()
function singleFlight<T>(key: string, loader: () => Promise<T>): Promise<T> {
  const existing = inFlight.get(key) as Promise<T> | undefined
  if (existing) return existing
  const p = loader().finally(() => inFlight.delete(key))
  inFlight.set(key, p)
  return p
}

export type CacheResult<T> = { value: T; hit: boolean }

export async function getOrCompute<T>(
  key: string,
  loader: () => Promise<T>,
  ttlSeconds: number = CACHE_TTL_SECONDS,
): Promise<CacheResult<T>> {
  const cached = await getRedis().get<T>(key)
  if (cached !== null && cached !== undefined) return { value: cached, hit: true }
  const value = await singleFlight(key, loader)
  // fire-and-forget write; a failed write only costs one more miss
  void getRedis().set(key, value, { ex: ttlSeconds }).catch((e) =>
    console.error("redis set failed", key, e),
  )
  return { value, hit: false }
}

export async function deleteByPrefix(prefix: string): Promise<number> {
  const redis = getRedis()
  let cursor = "0"
  let deleted = 0
  do {
    const [next, keys] = await redis.scan(cursor, { match: `${prefix}*`, count: 200 })
    cursor = String(next)
    if (keys.length) deleted += await redis.del(...keys)
  } while (cursor !== "0")
  return deleted
}

export async function flushAll(): Promise<void> {
  await getRedis().flushdb()
}
```

`@upstash/redis` JSON-serialises objects on `set` and parses on `get`; the payloads are plain JSON already, so no extra (de)serialisation.

### 5.4 Rewrite `src/cache/serve-cached.ts`

Keep the exported signature `serveCached(req, res, key, loader, send)` so routes change minimally. Body: call `getOrCompute(key, loader)`; on success call `send(res, value, meta)` with `meta.cache = hit ? "HIT" : "MISS"` (preserve whatever `CacheMeta` fields/headers exist today, e.g. `X-Cache`). On loader error: respond `502` with the existing error shape (there is no stale copy any more; remove any `getStale` usage). Remove all imports from `memory-cache.ts`.

### 5.5 Routes: key construction

In each `src/routes/*.ts`, replace `cacheKey({ route: ..., merchantCode, ... })` with `redisKey(merchantCode, "<scope>", { ...variant })`:

| Route file | scope | variant fields (use the exact variable names already parsed in the route) |
|---|---|---|
| `bootstrap.ts` | `bootstrap` | `language`, plus anything else in today's key (e.g. `personaId`) |
| `rewards.ts` | `rewards` | `language`, `personaId` |
| `earn-channels.ts` | `earn_channels` | `language`, `surface` |
| `display-blocks.ts` | `display_blocks` | `page`, `language` |
| `language-pack.ts` | `language_pack` | `language` |
| `tier.ts` | `tier_display` | (none, or `language` if present today) |
| `consent.ts` | `consent` | `language`, `consentType` |

Rule: the variant must contain every request parameter that changes the SQL result, and nothing else. Copy the field list from today's `cacheKey({...})` call in each file.

### 5.6 Delete `src/cache/memory-cache.ts`

`grep -rn "memory-cache" src` must return nothing. `npm run typecheck` must pass.

### 5.7 `render.yaml`

Set `CACHE_TTL_SECONDS: 600`. Add env entries (sync: false) for `LOYALTY_CACHE_REDIS_URL`, `LOYALTY_CACHE_REDIS_TOKEN`, `CACHE_PURGE_SECRET`, `LOYALTY_USER_REVALIDATE_URL`, `REVALIDATE_SECRET`.

### 5.8 Local verification

`DATABASE_URL=... LOYALTY_CACHE_REDIS_URL=... LOYALTY_CACHE_REDIS_TOKEN=... npm run dev`, then twice: `curl -s -D - "http://localhost:<port>/v1/rewards/catalog?merchant_code=<code>&language=th" -o /dev/null`. First response header `X-Cache: MISS` (or the existing miss marker), second `HIT`. In Upstash console (or `redis.keys('lc:*')` via a one-off script) a key `lc:<code>:rewards:language=th&personaId=` exists.

Commit: `feat(cache): store payloads in Upstash Redis; remove in-process memory cache`.

---

## 6. Phase 2 — Purge endpoint and Vercel tags

### 6.1 Render: `src/routes/purge.ts`

```ts
import type { Request, Response } from "express"
import { isScope, merchantPrefix, scopePrefix } from "../cache/keys"
import { deleteByPrefix, flushAll } from "../cache/redis-cache"

export async function handlePurge(req: Request, res: Response): Promise<void> {
  const secret = process.env.CACHE_PURGE_SECRET
  if (!secret || req.header("x-purge-secret") !== secret) {
    res.status(401).json({ error: "unauthorized" }); return
  }
  const body = req.body as { merchant_code?: string | null; scopes?: string[] }
  const scopes = Array.isArray(body.scopes) ? body.scopes : []
  const merchantCode = body.merchant_code ?? null
  if (!scopes.length) { res.status(400).json({ error: "scopes required" }); return }
  for (const s of scopes) if (s !== "all" && !isScope(s)) { res.status(400).json({ error: `unknown scope ${s}` }); return }

  let deleted = 0
  const tags: string[] = []
  if (merchantCode === null) {
    await flushAll(); tags.push("lc:all")
  } else if (scopes.includes("all")) {
    deleted += await deleteByPrefix(merchantPrefix(merchantCode)); tags.push(`m:${merchantCode}`)
  } else {
    for (const s of scopes) {
      if (!isScope(s)) continue
      deleted += await deleteByPrefix(scopePrefix(merchantCode, s))
      tags.push(`m:${merchantCode}:${s}`)
    }
  }

  let revalidated = false
  const url = process.env.LOYALTY_USER_REVALIDATE_URL
  const revalidateSecret = process.env.REVALIDATE_SECRET
  if (url && revalidateSecret) {
    try {
      const r = await fetch(url, {
        method: "POST",
        headers: { "content-type": "application/json", "x-revalidate-secret": revalidateSecret },
        body: JSON.stringify({ tags }),
        signal: AbortSignal.timeout(5000),
      })
      revalidated = r.ok
      if (!r.ok) console.error("revalidate failed", r.status, await r.text())
    } catch (e) { console.error("revalidate error", e) }
  }
  res.json({ deleted, tags, revalidated })
}
```

Mount in `src/server.ts` **before** the `/v1` api-key + rate-limit middleware: `app.post("/v1/purge", express.json(), handlePurge)`. Purge has its own secret; it must not be rate-limited or require `x-cache-api-key`.

### 6.2 loyalty-user: tags on every Render fetch

In `src/lib/api/cache-api-server.ts`, the shared fetch helper (`fetchCacheJson` or equivalent) gains a `scope` argument and sets:

```ts
next: {
  revalidate: 300,
  tags: ["lc:all", `m:${merchantCode}`, `m:${merchantCode}:${scope}`],
},
```

Pass the scope from each caller in that file: bootstrap → `"bootstrap"`, rewards catalog → `"rewards"`, earn channels → `"earn_channels"`, display blocks → `"display_blocks"`, language pack → `"language_pack"`, tier display → `"tier_display"`, consent → `"consent"`. `merchantCode` is already a parameter of every helper (it is in the query string).

### 6.3 loyalty-user: `src/app/api/revalidate/route.ts`

VERIFY the available API first: `grep -n "export" node_modules/next/dist/server/web/spec-extension/revalidate.d.ts` (or `node_modules/next/cache.d.ts`). Prefer an API that expires tags immediately and is allowed in Route Handlers. If only `revalidateTag(tag, profile)` exists (Next 16 signature), use `revalidateTag(tag, "max")` and note in the commit message that the first request after a purge may serve stale once (stale-while-revalidate). Do not use `updateTag` unless the type definitions say it is allowed outside Server Actions.

```ts
import { NextRequest, NextResponse } from "next/server"
import { revalidateTag } from "next/cache"

export const runtime = "nodejs"

export async function POST(req: NextRequest) {
  const secret = process.env.REVALIDATE_SECRET
  if (!secret || req.headers.get("x-revalidate-secret") !== secret) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 })
  }
  const { tags } = (await req.json()) as { tags?: string[] }
  if (!Array.isArray(tags) || !tags.length) {
    return NextResponse.json({ error: "tags required" }, { status: 400 })
  }
  for (const t of tags) revalidateTag(t /*, "max" if required by Next 16 types */)
  return NextResponse.json({ revalidated: tags })
}
```

### 6.4 Verification (local Render + local loyalty-user or after deploy)

1. Load a member page for merchant `<code>` twice → second load makes no Render request (Render logs show none).
2. `curl -X POST <RENDER>/v1/purge -H "x-purge-secret: $S" -H "content-type: application/json" -d '{"merchant_code":"<code>","scopes":["rewards"]}'` → `{ deleted: >=1, tags: ["m:<code>:rewards"], revalidated: true }`.
3. Next page load → Render logs one `/v1/rewards/catalog` MISS then HIT; another merchant's keys still present.

Commits: loyalty-cache-api `feat(cache): POST /v1/purge (Redis prefix delete + Vercel revalidate)`; loyalty-user `feat(cache): tag Render fetches per merchant/scope; add /api/revalidate`.

---

## 7. Phase 3 — One trigger path (Supabase migration)

Apply as one migration named `cache_purge_triggers_v1` via Supabase MCP `apply_migration`. Also save the same SQL to `~/Documents/rocket/supabase-crm/docs/cache-redesign/01_cache_purge_triggers.sql` and commit.

### 7.1 Functions

```sql
CREATE OR REPLACE FUNCTION public.fn_cache_purge_emit(p_merchant_id uuid, p_scopes text[])
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions, net, vault
AS $$
DECLARE
  v_sent   text := COALESCE(current_setting('cache_purge.sent', true), '');
  v_scope  text;
  v_tag    text;
  v_new    text[] := '{}';
  v_code   text;
  v_url    text;
  v_secret text;
BEGIN
  IF p_scopes IS NULL OR array_length(p_scopes, 1) IS NULL THEN RETURN; END IF;

  FOREACH v_scope IN ARRAY p_scopes LOOP
    v_tag := COALESCE(p_merchant_id::text, 'global') || ':' || v_scope;
    IF position(',' || v_tag || ',' IN ',' || v_sent || ',') = 0 THEN
      v_new  := v_new || v_scope;
      v_sent := CASE WHEN v_sent = '' THEN v_tag ELSE v_sent || ',' || v_tag END;
    END IF;
  END LOOP;
  IF array_length(v_new, 1) IS NULL THEN RETURN; END IF;           -- all already sent in this tx
  PERFORM set_config('cache_purge.sent', v_sent, true);             -- transaction-local

  IF p_merchant_id IS NOT NULL THEN
    SELECT merchant_code INTO v_code FROM public.merchant_master WHERE id = p_merchant_id;
    IF v_code IS NULL THEN RETURN; END IF;
  END IF;

  SELECT decrypted_secret INTO v_url    FROM vault.decrypted_secrets WHERE name = 'loyalty_cache_purge_url'    LIMIT 1;
  SELECT decrypted_secret INTO v_secret FROM vault.decrypted_secrets WHERE name = 'loyalty_cache_purge_secret' LIMIT 1;
  IF v_url IS NULL OR v_secret IS NULL THEN
    RAISE WARNING 'fn_cache_purge_emit: vault secrets missing'; RETURN;
  END IF;

  PERFORM net.http_post(
    url                  := v_url,
    body                 := jsonb_build_object('merchant_code', v_code, 'scopes', to_jsonb(v_new)),
    params               := '{}'::jsonb,
    headers              := jsonb_build_object('Content-Type', 'application/json', 'x-purge-secret', v_secret),
    timeout_milliseconds := 5000
  );
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'fn_cache_purge_emit failed: %', SQLERRM;
END;
$$;

-- Generic: TG_ARGV[0] = 'scope1,scope2'; TG_ARGV[1] = merchant column (default merchant_id)
CREATE OR REPLACE FUNCTION public.trigger_cache_purge()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_scopes text[] := string_to_array(TG_ARGV[0], ',');
  v_col    text   := COALESCE(TG_ARGV[1], 'merchant_id');
  v_new_id uuid;
  v_old_id uuid;
BEGIN
  IF TG_OP IN ('INSERT', 'UPDATE') THEN v_new_id := (to_jsonb(NEW) ->> v_col)::uuid; END IF;
  IF TG_OP IN ('UPDATE', 'DELETE') THEN v_old_id := (to_jsonb(OLD) ->> v_col)::uuid; END IF;
  IF v_new_id IS NOT NULL THEN PERFORM public.fn_cache_purge_emit(v_new_id, v_scopes); END IF;
  IF v_old_id IS NOT NULL AND v_old_id IS DISTINCT FROM v_new_id THEN
    PERFORM public.fn_cache_purge_emit(v_old_id, v_scopes);
  END IF;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.trigger_cache_purge_translations()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_type text;
  v_mid  uuid;
  v_scopes text[];
BEGIN
  IF TG_OP = 'DELETE' THEN v_type := OLD.entity_type; v_mid := OLD.merchant_id;
  ELSE                     v_type := NEW.entity_type; v_mid := NEW.merchant_id; END IF;

  v_scopes := CASE v_type
    WHEN 'reward'             THEN ARRAY['rewards', 'shopify_landing']
    WHEN 'reward_category'    THEN ARRAY['rewards']
    WHEN 'display_block_item' THEN ARRAY['display_blocks', 'bootstrap', 'language_pack', 'shopify_landing']
    WHEN 'earn_channel'       THEN ARRAY['earn_channels']
    -- add consent entity type here after the VERIFY in 7.2
    ELSE NULL END;
  IF v_scopes IS NULL OR v_mid IS NULL THEN RETURN NULL; END IF;
  PERFORM public.fn_cache_purge_emit(v_mid, v_scopes);
  RETURN NULL;
END;
$$;

-- Global template tables (no merchant): flush everything
CREATE OR REPLACE FUNCTION public.trigger_cache_purge_global()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.fn_cache_purge_emit(NULL, string_to_array(TG_ARGV[0], ','));
  RETURN NULL;
END;
$$;
```

### 7.2 Triggers — table → scopes

VERIFY before creating, per table: (a) it exists; (b) the merchant column named exists; (c) it is a **configuration/master** table, not a per-user event/ledger table (check column names and `SELECT count(*)`; a table growing with member activity must be excluded — report it). Specifically confirm `checkin`, `feature_config`, `merchant_credentials`, `mission`, `workflow_master`, `workflow_node`, `workflow_trigger` are config tables; the legacy earn-channels invalidator already fires on them, so they are expected to be.

VERIFY `SELECT DISTINCT entity_type FROM translations` and, if consent documents use `translations`, add that entity type → `ARRAY['consent','store_home']` in `trigger_cache_purge_translations`.

DDL pattern:

```sql
CREATE CONSTRAINT TRIGGER trg_cache_purge
  AFTER INSERT OR UPDATE OR DELETE ON public.<table>
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.trigger_cache_purge('<scopes>'[, '<merchant_col>']);
```

| Table | Function + args |
|---|---|
| `reward_master` | `trigger_cache_purge('rewards,shopify_landing')` |
| `reward_category` | `trigger_cache_purge('rewards')` |
| `reward_group` | `trigger_cache_purge('rewards')` |
| `reward_group_member` | `trigger_cache_purge('rewards')` |
| `transaction_limits` | `trigger_cache_purge('rewards')` |
| `translations` | `trigger_cache_purge_translations()` |
| `earn_channel` | `trigger_cache_purge('earn_channels')` |
| `checkin` | `trigger_cache_purge('earn_channels')` |
| `feature_config` | `trigger_cache_purge('earn_channels')` |
| `form_templates` | `trigger_cache_purge('earn_channels')` |
| `merchant_credentials` | `trigger_cache_purge('earn_channels')` |
| `mission` | `trigger_cache_purge('earn_channels')` |
| `workflow_master` | `trigger_cache_purge('earn_channels')` |
| `workflow_node` | `trigger_cache_purge('earn_channels')` |
| `workflow_trigger` | `trigger_cache_purge('earn_channels')` |
| `display_settings` | `trigger_cache_purge('display_blocks,bootstrap,language_pack,shopify_landing')` |
| `merchant_display_settings` | `trigger_cache_purge('bootstrap,earn_channels,widget,shopify_landing')` |
| `ui_translations` | `trigger_cache_purge('bootstrap,language_pack')` — VERIFY `merchant_id` nullable: if a row has NULL merchant_id it is a global default → use `trigger_cache_purge_global('bootstrap,language_pack')` semantics. Simplest: attach `trigger_cache_purge('bootstrap,language_pack')` AND accept that NULL-merchant rows do not purge (they are seed data). Note this in the commit. |
| `merchant_languages` | `trigger_cache_purge('all')` |
| `merchant_master` | `trigger_cache_purge('all', 'id')` |
| `tier_master` | `trigger_cache_purge('tier_display,widget')` |
| `earn_factor` | `trigger_cache_purge('widget')` |
| `consent_versions` | `trigger_cache_purge('consent,store_home')` |
| `merchant_widget_settings` | `trigger_cache_purge('widget')` |
| `merchant_shopify_landing_page_settings` | `trigger_cache_purge('shopify_landing')` |
| `referral_program` | `trigger_cache_purge('shopify_landing')` |
| `merchant_store_settings` | `trigger_cache_purge('store_home')` |
| `merchant_store_overlays` | `trigger_cache_purge('store_home')` |
| `earn_channel_registry` (global) | `trigger_cache_purge_global('earn_channels')` |
| `display_block_template` (global) | `trigger_cache_purge_global('display_blocks,bootstrap,language_pack,shopify_landing')` |
| `widget_config_template` (global) | `trigger_cache_purge_global('widget')` |
| `store_config_template` (global) | `trigger_cache_purge_global('store_home')` |

Legacy invalidation triggers stay in place during this phase (they still serve the SQL-side Redis until Phase 5). Both fire; that is fine.

### 7.3 Verification

1. `UPDATE reward_master SET updated_at = now() WHERE id = '<one reward of merchant X>'` (via MCP `execute_sql`).
2. Within ~2 s: `SELECT id, status_code, content FROM net._http_response ORDER BY created DESC LIMIT 3` shows a `200` from Render with `{"deleted":…,"tags":["m:<X>:rewards","m:<X>:shopify_landing"],"revalidated":true}`.
3. Redis has no `lc:<X>:rewards:*` keys; other merchants' keys remain.
4. Repeat for an `earn_channel` row and a `display_settings` row — these are the three scopes that legacy invalidation was failing on.

Commit (supabase-crm): `feat(cache): unified purge triggers → Render /v1/purge`.

---

## 8. Phase 4 — Shopify and store-home reads through Render

### 8.1 Render routes (`loyalty-cache-api`)

Add to `src/db/rpc.ts` three functions following the existing pattern (param-based, no header needed but harmless):

- `getWidgetSettings(merchantCode, widgetType)` → `SELECT api_get_widget_settings_cached($1, $2)` with `(p_widget_type, p_merchant_code)` order as in §1.6.
- `getShopifyLandingPage(merchantCode, language)` → `api_get_shopify_landing_page_cached(p_merchant_code, p_language)`.
- `getStoreHomeConfig(merchantCode)` → `api_get_store_home_config_cached(p_merchant_code)`.

Routes:

| Route | Query | Scope | Variant |
|---|---|---|---|
| `GET /v1/widget-settings` | `merchant_code`, `widget_type` (default `shopify`) | `widget` | `{ widgetType }` |
| `GET /v1/shopify-landing` | `merchant_code`, `language` (default `en`) | `shopify_landing` | `{ language }` |
| `GET /v1/store-home` | `merchant_code` | `store_home` | `{}` |

Mount under `/v1` like the others. VERIFY CORS in `src/server.ts` allows the Shopify storefront origins that will call `/v1/widget-settings` from the browser (today they call PostgREST directly, which allows `*`). If CORS is restricted, extend it to `*.myshopify.com` and the merchant custom domains pattern used today, or ASK.

### 8.2 Callers

- `rewarding-shopify/widget-builder/src/services/widgetSettings.js`: replace the PostgREST POST with `GET {LOYALTY_CACHE_API_URL}/v1/widget-settings?merchant_code=…&widget_type=…`. Read the base URL from the same config mechanism the file uses for the Supabase URL today (env/constant); add `LOYALTY_CACHE_API_URL`.
- `rewarding-shopify/extensions/loyalty-widget/assets/points-on-product.js`: same replacement (it is a theme asset; the Render URL becomes a constant next to the existing hardcoded Supabase URL).
- `supabase-crm/supabase/functions/shopify-proxy/index.ts` (~L87 and ~L159): replace both `supabase.rpc('api_get_shopify_landing_page_cached', {...})` with `fetch(`${Deno.env.get('LOYALTY_CACHE_API_URL')}/v1/shopify-landing?merchant_code=${merchantCode}&language=${locale}`)` and unwrap the JSON to the same shape the code expects (check the route's `send` envelope). Add Edge secret `LOYALTY_CACHE_API_URL`. Deploy per `21-backend-functions` (fetch live bundle with `get_edge_function`, deploy full file set, keep `verify_jwt` as it is today).
- `loyalty-user/src/lib/shopify/store-cms.ts:47`: replace the RPC with a call through `cache-api-server.ts` (new helper `fetchStoreHomeConfig(merchantCode)` with scope `store_home`).

### 8.3 Verification

Storefront widget renders with data from Render (Render logs show `/v1/widget-settings`); landing page via app proxy renders; `POST /v1/purge {"merchant_code":X,"scopes":["widget"]}` then reload shows a MISS then HIT.

Commits: loyalty-cache-api `feat(cache): widget-settings, shopify-landing, store-home routes`; rewarding-shopify `feat: read widget settings via loyalty-cache-api`; supabase-crm `feat(shopify-proxy): landing page via loyalty-cache-api`; loyalty-user `feat: store home via loyalty-cache-api`.

---

## 9. Approval gates

| Gate | Before | Needs |
|---|---|---|
| G1 | Deploying Render (Phase 1+2), pushing loyalty-user (Phase 2) | User says "deploy" |
| G2 | Applying Phase 3 migration | User says "approved" (it creates triggers on ~30 production tables) |
| G3 | Phase 4 Edge deploy + rewarding-shopify push | User says "deploy" |
| G4 | Phase 5 DROP statements and Upstash DB deletion | User says "approved" — irreversible |

Between gates, do all code edits and commits without asking.

---

## 10. Phase 5 — Postgres becomes plain; legacy removed

### 10.1 Plain twins (migration `cache_plain_functions_v1`)

For each row, obtain the live body with `SELECT pg_get_functiondef('public.<name>'::regproc)` (or by OID if overloaded), then:

1. Change the function name where indicated.
2. Delete the early-return block that calls `extensions.<family>_cache_get(...)` (typically: `v_cached := extensions.X_cache_get(v_key); IF v_cached IS NOT NULL THEN RETURN v_cached; END IF;`) and the `v_key` construction if it is only used for caching.
3. Delete the `PERFORM extensions.<family>_cache_set(...)` call near the end.
4. Keep everything else byte-identical: params, defaults, `SECURITY DEFINER`, `SET search_path`, return type, language, the `RETURN` of the computed JSON.
5. Re-grant: run `SELECT grantee, privilege_type FROM information_schema.routine_privileges WHERE routine_name = '<old_name>'` and `GRANT EXECUTE` the same to the new name.

| Old | New | Action |
|---|---|---|
| `api_get_rewards_full_cached` | `api_get_rewards_full` | new function |
| `api_get_display_blocks_cached` | `api_get_display_blocks` | new function |
| `api_get_consent_documents_cached` | `api_get_consent_documents` | new function |
| `api_get_widget_settings_cached` | `api_get_widget_settings` | new function |
| `api_get_shopify_landing_page_cached` | `api_get_shopify_landing_page` | new function |
| `api_get_store_home_config_cached` | `api_get_store_home_config` | new function |
| `bff_get_earn_channels` | same name | `CREATE OR REPLACE` minus Redis |
| `get_ui_translations` | same name | `CREATE OR REPLACE` minus Redis |

VERIFY equivalence for 3 merchants and 2 languages each: after a `POST /v1/purge` for that merchant with `["all"]` (so the legacy Redis is not consulted — note the legacy Redis inside `_cached` may still return a stale copy; if the two outputs differ, run `SELECT extensions.rewards_cache_del(...)` etc. for that key or simply compare `jsonb_typeof`/top-level keys and one known field), run e.g.

```sql
SELECT api_get_rewards_full('th') = api_get_rewards_full_cached('th');  -- with request.headers set for merchant
```

Use `SELECT set_config('request.headers', '{"x-merchant-code":"<code>"}', true)` in the same `execute_sql` call for header-resolved functions.

### 10.2 Switch callers to plain names

- `loyalty-cache-api/src/db/rpc.ts`: every `_cached` name → plain name. Commit `refactor: call plain SQL functions`.
- `loyalty-admin/src/app/(admin)/display-settings/actions.ts:98`: `api_get_rewards_full_cached` → `api_get_rewards_full`. Regenerate/adjust `database.ts` types if the repo's convention requires. Commit `refactor(display-settings): read rewards from plain function`.
- VERIFY no remaining references: `grep -rn "_cached" ~/Documents/rocket/loyalty-cache-api/src ~/Documents/rocket/loyalty-user/src ~/Documents/rocket/loyalty-admin/src ~/Documents/rocket/rewarding-shopify ~/Documents/rocket/supabase-crm/supabase/functions --include=*.ts --include=*.tsx --include=*.js` shows only comments/generated types. And in DB: `SELECT proname FROM pg_proc WHERE prosrc ILIKE '%api_get_rewards_full_cached%' OR prosrc ILIKE '%api_get_display_blocks_cached%' ...` for each old name — must return none other than the function itself.

### 10.3 loyalty-user: remove the rollback flag and PostgREST fallbacks

Delete the `LOYALTY_CACHE_READS_VIA` branches and PostgREST fallbacks so the Render path is the only path. Exact targets (line numbers as of 2026-09-22; re-locate by content):

| File | What to remove |
|---|---|
| `src/lib/api/cache-api.ts` L29–31 | `loyaltyCacheReadsViaRender()` and every caller of it |
| `src/lib/api/member-bootstrap.ts` L77–78, L117–139 | early `return null` when flag off; `get_line_channel_id` PostgREST fallback |
| `src/lib/api/rewards.ts` L54–85 | flag branch + `api_get_rewards_full_cached` RPC fallback |
| `src/lib/api/tier-server.ts` L20–28 | flag branch + `get_tier_display_config` RPC fallback |
| `src/lib/api/store-consent.ts` L20–36 | flag branch + `api_get_consent_documents_cached` RPC fallback |
| `src/lib/api/merchant.ts` L19–30, L36–82, L88–102 | bootstrap short-circuit + PostgREST fallbacks |
| `src/lib/api/blocks.ts` L15–28 | `api_get_display_blocks_cached` RPC fallback |
| `src/lib/api/earn.ts` L23–34 | `bff_get_earn_channels` RPC fallback |
| `src/lib/api/cache-api-client.ts` L13, L25, L38 | `404 → null` fallback pattern (make 404 an error) |
| `src/app/api/cache/earn-channels/route.ts` L31–33, `display-blocks/route.ts` L8–10, `language-pack/route.ts` L9–11 | `return 404 when flag off` |
| `src/app/layout.tsx` L48–50 | `bootstrap?.settings ?? getMerchantSettings(...)` fallback → bootstrap is required |

After removal: `npm run typecheck && npm run lint` pass; a Render outage now surfaces as an error page rather than a silent slow path — this is intended. Remove `LOYALTY_CACHE_READS_VIA` from `.env.example` and docs. Commit `refactor(cache): Render is the only read path; drop LOYALTY_CACHE_READS_VIA and PostgREST fallbacks`.

### 10.4 Drop legacy (migration `cache_legacy_drop_v1`) — Gate G4

Order matters: triggers → trigger functions → invalidator functions → `_cached` functions → `extensions.*` families.

Before running, VERIFY the trigger→function mapping live and that every function below is only referenced by the triggers being dropped:

```sql
SELECT t.tgname, c.relname, p.proname
FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_proc p ON p.oid = t.tgfoid
WHERE NOT t.tgisinternal AND p.proname IN (<trigger function names from list B>)
ORDER BY c.relname;
```

**Exclude from this plan (different families, leave alone):** `trg_cache_inv_communication_topics`, `trg_cache_inv_consent_versions`, `trg_cache_inv_form_conditions`, `trg_cache_inv_form_field_groups`, `trg_cache_inv_form_field_options`, `trg_cache_inv_form_fields`, `trg_cache_inv_form_templates`, `trg_cache_inv_user_field_config` (user-profile family, `fn_trigger_invalidate_user_profile_cache`), `merchant_languages_config_cache_invalidation`, `merchant_master_config_cache_invalidation` (merchant-config family), `trg_invalidate_amp_*`, `tr_mission_*`, `trg_loyalty_persona_cache_refresh`. If the VERIFY query shows one of these attached to a function in list B, stop and ASK.

List A — `DROP TRIGGER`:

```sql
DROP TRIGGER IF EXISTS trg_invalidate_earn_channels_cache_on_checkin_source ON public.checkin;
DROP TRIGGER IF EXISTS display_settings_invalidate_shopify_landing_cache ON public.display_settings;
DROP TRIGGER IF EXISTS trg_invalidate_display_blocks_cache_on_settings ON public.display_settings;
DROP TRIGGER IF EXISTS trg_invalidate_earn_channels_cache ON public.earn_channel;
DROP TRIGGER IF EXISTS trg_invalidate_earn_channels_cache_on_registry_source ON public.earn_channel_registry;
DROP TRIGGER IF EXISTS earn_factor_invalidate_widget_cache ON public.earn_factor;
DROP TRIGGER IF EXISTS trg_invalidate_earn_channels_cache_on_feature_config_source ON public.feature_config;
DROP TRIGGER IF EXISTS trg_invalidate_earn_channels_cache_on_form_templates_source ON public.form_templates;
DROP TRIGGER IF EXISTS trg_invalidate_earn_channels_cache_on_credentials_source ON public.merchant_credentials;
DROP TRIGGER IF EXISTS merchant_display_settings_invalidate_shopify_landing_cache ON public.merchant_display_settings;
DROP TRIGGER IF EXISTS merchant_display_settings_invalidate_widget_cache ON public.merchant_display_settings;
DROP TRIGGER IF EXISTS merchant_languages_cache_invalidation ON public.merchant_languages;
DROP TRIGGER IF EXISTS trg_invalidate_earn_channels_cache_on_merchant_master_source ON public.merchant_master;
DROP TRIGGER IF EXISTS merchant_shopify_landing_page_settings_invalidate_cache ON public.merchant_shopify_landing_page_settings;
DROP TRIGGER IF EXISTS merchant_store_overlays_invalidate_cache ON public.merchant_store_overlays;
DROP TRIGGER IF EXISTS merchant_store_settings_invalidate_cache ON public.merchant_store_settings;
DROP TRIGGER IF EXISTS merchant_widget_settings_invalidate_cache ON public.merchant_widget_settings;
DROP TRIGGER IF EXISTS trg_invalidate_earn_channels_cache_on_mission_source ON public.mission;
DROP TRIGGER IF EXISTS referral_program_invalidate_shopify_landing_cache ON public.referral_program;
DROP TRIGGER IF EXISTS reward_group_cache_invalidation ON public.reward_group;
DROP TRIGGER IF EXISTS reward_master_cache_invalidation ON public.reward_master;
DROP TRIGGER IF EXISTS reward_master_invalidate_shopify_landing_cache ON public.reward_master;
DROP TRIGGER IF EXISTS tier_master_invalidate_widget_cache ON public.tier_master;
DROP TRIGGER IF EXISTS transaction_limits_group_cache_invalidation ON public.transaction_limits;
DROP TRIGGER IF EXISTS translations_cache_invalidation ON public.translations;
DROP TRIGGER IF EXISTS trg_invalidate_display_blocks_cache_on_translation ON public.translations;
DROP TRIGGER IF EXISTS trg_invalidate_earn_channels_cache_on_translation ON public.translations;
DROP TRIGGER IF EXISTS ui_translations_cache_invalidation ON public.ui_translations;
DROP TRIGGER IF EXISTS trg_invalidate_earn_channels_cache_on_workflow_master_source ON public.workflow_master;
DROP TRIGGER IF EXISTS trg_invalidate_earn_channels_cache_on_workflow_node_source ON public.workflow_node;
DROP TRIGGER IF EXISTS trg_invalidate_earn_channels_cache_on_workflow_trigger_source ON public.workflow_trigger;
```

List B — `DROP FUNCTION` (trigger wrappers then invalidators). Use `DROP FUNCTION IF EXISTS public.<name>(<args>)` with the exact argument lists from `pg_get_function_identity_arguments`:

```
trigger_invalidate_rewards_cache_on_reward_change()
trigger_invalidate_rewards_cache_on_group_change()
trigger_invalidate_rewards_cache_on_group_limit_change()
trigger_invalidate_rewards_cache_on_translation_change()
trigger_invalidate_rewards_cache_on_promo_change()        -- no trigger attached; drop
trigger_invalidate_rewards_cache_on_redemption()          -- no trigger attached; drop
trigger_invalidate_display_blocks_cache_on_settings_change()
trigger_invalidate_display_blocks_cache_on_translation_change()
trigger_invalidate_earn_channels_cache_on_channel_change()
trigger_invalidate_earn_channels_cache_on_source_change()
trigger_invalidate_earn_channels_cache_on_translation_change()
trigger_invalidate_widget_settings_cache_on_change()
trigger_invalidate_widget_cache_on_merchant_display_change()
trigger_invalidate_widget_cache_on_earn_factor_change()
trigger_invalidate_widget_cache_on_tier_change()
trigger_invalidate_shopify_landing_page_cache()
trigger_invalidate_shopify_landing_program_cache()
trigger_invalidate_store_home_cache_on_settings()
trigger_invalidate_store_home_cache_on_overlays()
trigger_invalidate_ui_cache()
trigger_invalidate_cache_on_language_change()
fn_invalidate_merchant_rewards_cache(uuid)
fn_invalidate_earn_channels_cache(uuid)
fn_invalidate_display_blocks_cache(uuid)
fn_invalidate_widget_settings_cache(uuid, text)
fn_invalidate_shopify_landing_page_cache(uuid)
fn_invalidate_store_home_cache(uuid)
```

**Do not drop** `fn_invalidate_user_profile_template_cache`, `fn_trigger_invalidate_user_profile_cache`, `trigger_invalidate_merchant_config_cache` (other families).

List C — `DROP FUNCTION` the `_cached` functions (six from §10.1, exact identity args).

List D — `extensions` families. VERIFY first that nothing else references them:

```sql
SELECT n.nspname, p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE p.prosrc ILIKE '%rewards_cache_%' OR p.prosrc ILIKE '%earn_channels_cache_%'
   OR p.prosrc ILIKE '%display_blocks_cache_%' OR p.prosrc ILIKE '%ui_cache_%';
```

Expected: only the `extensions.*` functions themselves. If any `public.*` function still references `ui_cache_*` (possible — it was shared), leave the whole `ui_cache_*` family in place and report. Otherwise:

```sql
DROP FUNCTION IF EXISTS extensions.rewards_cache_get(text), extensions.rewards_cache_set(...), extensions.rewards_cache_del(text);
-- same for earn_channels_cache_*, display_blocks_cache_*, ui_cache_*  (exact identity args from pg_get_function_identity_arguments)
```

Save all four lists as executed to `supabase-crm/docs/cache-redesign/02_cache_legacy_drop.sql`. Commit `chore(cache): drop legacy SQL-side Redis and invalidators`.

### 10.5 Upstash cleanup (user action)

After G4 and 24 h of clean operation, the user deletes these Upstash databases in the console: `mutual-stud-37574`, `keen-koala-67759`, `special-sparrow-18357`, `free-hound-25865` (only if `ui_cache_*` was dropped in 10.4). Keep `crisp-bison-32725`, `sweet-cardinal-5243`, `finer-mastiff-56332`, `usable-ray-20184`.

---

## 11. Phase 6 — Docs closeout (supabase-crm + loyalty-user)

Once per thread, after Phase 5:

- `requirements/Member_App_Cached_Reads.md` — rewrite the tier section to the §0 diagram; list all ten scopes and routes (including earn-channels, widget-settings, shopify-landing, store-home); document the purge contract (§3.4) and tag scheme (§3.2); remove references to in-memory Render cache and to SQL-side Redis.
- `requirements/Reward_Cache_Implementation.md` — replace the body with a short pointer: "Rewards catalog is cached by loyalty-cache-api in Redis under scope `rewards`; see Member_App_Cached_Reads.md." Delete the Upstash-in-SQL and key-pattern sections.
- `requirements/Display_Settings.md` — invalidation section: "any write to `display_settings`, `merchant_display_settings`, or `translations(entity_type=display_block_item)` purges scopes display_blocks/bootstrap/language_pack/shopify_landing via the cache purge trigger".
- `requirements/REGISTRY_RENDER.md` — loyalty-cache-api: routes, env vars, Redis, `/v1/purge`.
- `requirements/REGISTRY_SUPABASE.md` — add `fn_cache_purge_emit`, `trigger_cache_purge*`, plain function names; remove dropped names.
- `loyalty-user/docs/ai/loyalty-cache-api-plan.md` — mark superseded by this document; keep as history.
- Changelog entry per the repo's convention.

Commit `docs: cache architecture — Redis at Render, plain SQL, purge triggers`.

---

## 12. Rollback

| Phase | Rollback |
|---|---|
| 1–2 | Redeploy previous Render commit; revert loyalty-user commit. Legacy SQL Redis is still intact so behaviour returns to today's. |
| 3 | `DROP TRIGGER trg_cache_purge ON <each table>`; drop the four functions. |
| 4 | Revert the four commits; redeploy Edge from snapshot. |
| 5 | Functions: recreate from `legacy-functions-snapshot.sql`. Triggers: from the snapshot DDL. The `_cached` functions can be recreated from the snapshot. This is why Phase 0.2 is mandatory. |

---

## 13. Out of scope (do not do in this thread)

- Warming after purge (optional later: Render self-GETs bootstrap + rewards for the purged merchant).
- Changing how persona is resolved in `api_get_display_blocks` (today: `auth.uid()` → `'guest'` under Render).
- Moving `api_get_rewards_full` to explicit `p_merchant_code`.
- User-profile-template, merchant-config, AMP, marketplace Redis families.
- Tier-progress / expiry cron cache.
- Rate-limit rework on Render.
- Vault-rotating any secret other than the two created here.

---

## 14. Done checklist

- [ ] Phase 0: earn-channels committed; snapshot saved; Vault secrets; Render + Vercel env
- [ ] Phase 1: Redis in Render; memory-cache deleted; typecheck passes; HIT/MISS verified
- [ ] Phase 2: `/v1/purge`; tags; `/api/revalidate`; curl purge verified
- [ ] G1 deploy
- [ ] Phase 3 migration applied (G2); reward/earn/display edits purge within ~2 s
- [ ] Phase 4 routes + callers; Edge deployed (G3)
- [ ] Phase 5.1–5.3 plain functions, callers switched, fallbacks removed
- [ ] Phase 5.4 drops (G4); lists saved
- [ ] Phase 6 docs
- [ ] User deletes 4 legacy Upstash DBs after 24 h
