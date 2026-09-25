# MCA: Birth-month operators (RULEBASEDWORKFLO-0033) + "All LINE Friends (exclude members)" entry (RULEBASEDWORKFLO-0032)

Execution plan. Written 2026-09-23 from a diagnosis thread; every file path, function name, and code excerpt below was verified against the live Supabase project and local clones on that date. Follow it literally. Where a step says **STOP AND ASK**, end your turn and ask the user; do not guess.

---

## 0. Context the executor must hold

**What we are building**

1. **0033 (small):** Three new condition operators, offered on Member Profile → Birth Date in the workflow builder and the audience builder:
   - `month_in`: label **"month is any of"**. Multi-select of January–December.
   - `month_not_in`: label **"month is none of"**. Multi-select of January–December.
   - `month_current`: label **"month is the current month"**. No value input. Lets one monthly scheduled workflow cover every birthday month.
   
   The same task also fixes a real existing bug: condition checks inside Conditional Split nodes run through a JavaScript filter in the executor that ignores `birthday_today`, and would ignore the new operators too. After this plan, splits use the same SQL evaluator as entry, preview, batch, and schedule.
2. **0032 (feature):** A new workflow Entry type, **"All LINE Friends (exclude members)"** (`entry_type = "all_line_friends_exclude_members"`). On activate:
   - The workflow executor pages through LINE's follower-ID API (through messaging-service).
   - It removes LINE IDs that belong to members.
   - It starts one workflow run per remaining LINE user ID. Each run pushes individually, not by broadcast.
   
   This reuses the existing per-LINE-user run path that `past_line_interaction` already uses (`run_scope = "line"`). The merchant's LINE Official Account is assumed verified/premium, which the follower-ID API requires.

**Fixed decisions (do not re-open)**

- Operator names are generic (`month_*`), not `birth_month_*`. They work on any date field, but metadata exposes them only on `birth_date` for now.
- Month values are stored as **strings `"1"`…`"12"`** in a JSON array: `{"field":"birth_date","operator":"month_in","value":["1","12"]}`.
- A member with **NULL `birth_date` never matches** any of the three operators, `month_not_in` included.
- `month_current` uses the same timezone resolution as `birthday_today`: the condition's `timezone` key, then the group's `timezone`, then `'UTC'`. Do not add merchant-timezone lookup.
- 0032 is **manual activate / batch run only**. There is no scheduled support. With empty groups the scheduler already resolves 0 users and skips, and that is fine.
- 0032 has **no follower table and no follow/unfollow webhook**. The list is fetched live at send time.
- Members who never linked LINE (no `user_accounts.line_id`) cannot be excluded. That is expected and stated in the UI copy.

**Repos (team convention: `~/Documents/rocket/<folder>`)**

| Repo | Role | Deploy |
|---|---|---|
| `~/Documents/rocket/supabase-crm` | Migration files, Edge function sources, product docs | Backend is applied with **Supabase MCP** on project `wkevmsedchftztoolkmi` (never `list_projects`) |
| `~/Documents/rocket/loyalty-admin` | Admin FE (Next.js + **Shopify Polaris only**) | Push `main` (only when the user says push) |
| `~/Documents/rocket/messaging-service` | LINE adapter (Express 5) | Push `main` → Render deploy (only when the user says push) |

**Live objects touched**

- SQL: `bff_get_workflow_collections_v2()`, `fn_amp_build_condition_clause(text, jsonb, text, text)`, `bff_amp_batch_run(...)`, new `fn_amp_filter_non_member_line_ids(uuid, text[])`.
- Edge: `inngest-amp-serve` (live v83, `verify_jwt: false`; the local file is byte-identical to live), `amp-dispatch-workflow-batch` (live v57, `verify_jwt: false`; **it is not in the local clone**, so this plan adds it).
- Do **not** touch: `fn_amp_lifecycle_date_matches`, `fn_amp_run_due_scheduled_workflows`, `inngest-event-router-serve`, `amp-dispatch-realtime-event`, reward birth-month logic, `amp-ai-service`.

---

## Phase 0: Preflight (STOP AND ASK where marked)

1. Sync gate, once per repo:
   ```bash
   export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"
   for r in supabase-crm loyalty-admin messaging-service; do
     echo "== $r"; cd ~/Documents/rocket/$r && git status -sb && git fetch --quiet origin && git status -sb
   done
   ```
2. Known state on 2026-09-23. Re-check it, and **STOP AND ASK** if still true:
   - `supabase-crm` is on `feat/expiry-reminder-render-cron`, dirty, ahead 14 / behind 2. Ask: *"Which supabase-crm branch should the migration files, Edge sources, and docs for this work be committed on?"* Do not commit onto the unrelated feature branch without an answer.
   - `messaging-service` `main` has uncommitted changes in `src/adapters/sms.ts` and `src/resolution/resolve-recipient.ts` (someone's in-progress SMS credential work). This plan must edit `resolve-recipient.ts`. Ask: *"messaging-service has uncommitted SMS changes in resolve-recipient.ts and sms.ts. Should I wait for them to be committed, or build on top of them?"* Never stash, discard, or commit someone else's changes.
   - `loyalty-admin` `main` clean → if behind, `git pull --ff-only origin main`.
3. Ask once: *"OK to apply the two migrations and deploy the two Edge functions to production (wkevmsedchftztoolkmi) as part of this plan?"* Do not run `apply_migration` or `deploy_edge_function` without a yes. Git pushes need a separate explicit "push".
4. **Rollback snapshot** before any backend change. Run with `execute_sql` and save each result to `/tmp/mca-rollback/<name>.sql`:
   ```sql
   SELECT pg_get_functiondef('public.bff_get_workflow_collections_v2()'::regprocedure);
   SELECT pg_get_functiondef(p.oid) FROM pg_proc p WHERE p.proname = 'fn_amp_build_condition_clause';
   SELECT pg_get_functiondef(p.oid) FROM pg_proc p WHERE p.proname = 'bff_amp_batch_run';
   ```
   Also save the live Edge sources with `get_edge_function` for `inngest-amp-serve` and `amp-dispatch-workflow-batch`.
5. Migration filenames use the `YYYYMMDDHHMMSS_snake_case.sql` convention. List `supabase-crm/supabase/migrations/` and pick timestamps **later than the newest file** (the newest on 2026-09-23 was `20260923142000_brand_scheme_unification_c.sql`). This plan uses `20260923160000` and `20260923161000`; bump them if needed.

---

## Phase 1: 0033 backend (migration A)

File: `supabase-crm/supabase/migrations/20260923160000_amp_month_operators.sql`.

The migration contains **two full `CREATE OR REPLACE FUNCTION` statements**, each copied from the live definitions saved in Phase 0 step 4 with only the edits below. Do not hand-retype the functions. Copy the live definition, then apply the exact edits.

### 1a. `bff_get_workflow_collections_v2()`: metadata

The metadata is a single `$json$[...]$json$::jsonb` literal. Replace exactly this object:

```json
{"name": "birth_date", "label": "Birth Date", "type": "date", "input": "date", "operators": ["birthday_today", "greater_or_equal", "less_or_equal", "greater_than", "less_than"]}
```

with:

```json
{"name": "birth_date", "label": "Birth Date", "type": "date", "input": "date", "operators": ["birthday_today", "month_current", "month_in", "month_not_in", "greater_or_equal", "less_or_equal", "greater_than", "less_than"]}
```

Do **not** add `options` to this field: `options` means a closed value set for `input: "select"`. The FE supplies the month list for these operators (Phase 3).

### 1b. `fn_amp_build_condition_clause`: compiler

Signature (unchanged): `fn_amp_build_condition_clause(p_collection text, p_cond jsonb, p_alias text DEFAULT ''::text, p_default_timezone text DEFAULT 'UTC'::text) RETURNS text`. The locals `v_operator`, `v_field`, `v_value`, `v_values text[]`, `v_list text`, and `v_timezone` already exist.

Edit 1: value collection. Change

```sql
  IF v_operator IN ('in', 'not_in') THEN
```

to

```sql
  IF v_operator IN ('in', 'not_in', 'month_in', 'month_not_in') THEN
```

Edit 2: add these branches to the `CASE v_operator` immediately **after** the existing `WHEN 'birthday_today', 'anniversary_today', 'date_anniversary_today' THEN ... ;` branch, before the final `ELSE RAISE EXCEPTION 'Unknown AMP condition operator: %'`:

```sql
    WHEN 'month_in', 'month_not_in' THEN
      SELECT string_agg(DISTINCT x::int::text, ',') INTO v_list
      FROM unnest(v_values) x
      WHERE CASE WHEN x ~ '^[0-9]{1,2}$' THEN x::int BETWEEN 1 AND 12 ELSE false END;
      IF v_list IS NULL THEN
        RETURN 'FALSE';
      END IF;
      RETURN format(
        'COALESCE(EXTRACT(MONTH FROM %s%I::date)::int %s (%s), false)',
        p_alias, v_field,
        CASE WHEN v_operator = 'month_in' THEN 'IN' ELSE 'NOT IN' END,
        v_list
      );
    WHEN 'month_current' THEN
      RETURN format(
        'COALESCE(EXTRACT(MONTH FROM %s%I::date)::int = EXTRACT(MONTH FROM timezone(%L, now()))::int, false)',
        p_alias, v_field, COALESCE(NULLIF(v_timezone, ''), 'UTC')
      );
```

Edit 3: a consistency sweep inside the same function body.
- Search for any other `IN (...)` list that contains `'birthday_today'`, for example a "valueless operators" or "requires value" check. Add `'month_current'` to each such list.
- Search for any other list containing both `'in'` and `'not_in'`, for example array-value handling. Add `'month_in', 'month_not_in'` to each.
- If there are none, change nothing else.

### 1c. Apply and verify

1. `apply_migration` with name `amp_month_operators` and the file contents.
2. Verify with `execute_sql`. Every row must match its expectation:
   ```sql
   SELECT fn_amp_build_condition_clause('user_accounts','{"field":"birth_date","operator":"month_in","value":["12","1","1","13","x"]}'::jsonb,'ua.');
   -- expect: COALESCE(EXTRACT(MONTH FROM ua.birth_date::date)::int IN (1,12), false)   (1,12 order may vary)
   SELECT fn_amp_build_condition_clause('user_accounts','{"field":"birth_date","operator":"month_not_in","value":["3"]}'::jsonb,'ua.');
   -- expect: COALESCE(EXTRACT(MONTH FROM ua.birth_date::date)::int NOT IN (3), false)
   SELECT fn_amp_build_condition_clause('user_accounts','{"field":"birth_date","operator":"month_in","value":[]}'::jsonb,'ua.');
   -- expect: FALSE
   SELECT fn_amp_build_condition_clause('user_accounts','{"field":"birth_date","operator":"month_current","timezone":"Asia/Bangkok"}'::jsonb,'ua.');
   -- expect: ... timezone('Asia/Bangkok', now()) ...
   SELECT fn_amp_build_condition_clause('user_accounts','{"field":"birth_date","operator":"birthday_today"}'::jsonb,'ua.');
   -- expect: unchanged fn_amp_lifecycle_date_matches(...) string (regression)
   ```
   Then run the evaluator against a real member:
   ```sql
   WITH u AS (
     SELECT id, merchant_id, EXTRACT(MONTH FROM birth_date)::int AS m
     FROM user_accounts WHERE birth_date IS NOT NULL LIMIT 1
   ), g AS (
     SELECT u.*, (u.m % 12) + 1 AS other FROM u
   )
   SELECT
     fn_evaluate_amp_condition_group(id, merchant_id, jsonb_build_object('type','simple','collection','user_accounts','match','all',
       'conditions', jsonb_build_array(jsonb_build_object('field','birth_date','operator','month_in','value', jsonb_build_array(m::text))))) AS own_in,        -- true
     fn_evaluate_amp_condition_group(id, merchant_id, jsonb_build_object('type','simple','collection','user_accounts','match','all',
       'conditions', jsonb_build_array(jsonb_build_object('field','birth_date','operator','month_in','value', jsonb_build_array(other::text))))) AS other_in,  -- false
     fn_evaluate_amp_condition_group(id, merchant_id, jsonb_build_object('type','simple','collection','user_accounts','match','all',
       'conditions', jsonb_build_array(jsonb_build_object('field','birth_date','operator','month_not_in','value', jsonb_build_array(m::text))))) AS own_not_in, -- false
     fn_evaluate_amp_condition_group(id, merchant_id, jsonb_build_object('type','simple','collection','user_accounts','match','all',
       'conditions', jsonb_build_array(jsonb_build_object('field','birth_date','operator','month_not_in','value', jsonb_build_array(other::text))))) AS other_not_in -- true
   FROM g;
   ```
   If any result is wrong, fix the migration before continuing. To roll back, re-run the saved definitions.
3. Confirm metadata: `SELECT bff_get_workflow_collections_v2()::text ILIKE '%"month_current", "month_in", "month_not_in"%';` → `true`.
4. Save the final migration file in `supabase-crm/supabase/migrations/`.

---

## Phase 2: 0033 executor fix (splits use the SQL evaluator)

File: `~/Documents/rocket/supabase-crm/supabase/functions/inngest-amp-serve/index.ts` (the only file in that function dir).

Replace the whole `evaluateConditionGroup` function (currently lines ~562–627, from `async function evaluateConditionGroup(` to its closing `}`) with:

```ts
async function evaluateConditionGroup(supabase, group, user_id, merchant_id, userContext, runtimeCtx) {
  const groupType = group.type || "simple";
  // All groups go to the SQL evaluator so split nodes share semantics with entry, preview,
  // batch and schedule. fn_evaluate_amp_condition_group ignores value_type, so dynamic
  // values are substituted here before the call.
  let payload = group;
  if (groupType === "content_engagement" && runtimeCtx) {
    payload = {
      ...group,
      _workflow_id: runtimeCtx.workflow_id,
      _inngest_run_id: runtimeCtx.runId
    };
  } else if (groupType === "simple" && Array.isArray(group.conditions)) {
    payload = {
      ...group,
      conditions: group.conditions.map((cond)=>cond.value_type === "dynamic" ? {
          ...cond,
          value: substituteVariables(cond.value, userContext)
        } : cond)
    };
  }
  const { data, error } = await supabase.rpc("fn_evaluate_amp_condition_group", {
    p_user_id: user_id,
    p_merchant_id: merchant_id,
    p_group: payload
  });
  if (error) {
    console.error("Condition group RPC error:", error);
    return false;
  }
  return data === true;
}
```

Do not change any caller. `substituteVariables` already exists in the file.

Deploy (only with the Phase 0 yes):
- `deploy_edge_function` with name `inngest-amp-serve`, files `[{ name: "index.ts", content: <full local file> }]`, and **`verify_jwt: false`**.
- Confirm with `list_edge_functions` that the version incremented and `verify_jwt` is still `false`.
- Check `query_logs` (service `edge-function`) for boot errors over the next few minutes.

---

## Phase 3: 0033 admin FE (loyalty-admin)

Polaris only. No new components, Tailwind, raw hex, or emoji.

### 3a. `src/lib/types/amp.ts`

1. In the operator label map (the object containing `birthday_today: "is today (birthday)"`), add directly after the `birthday_today` entry:
   ```ts
   month_current: "month is the current month",
   month_in: "month is any of",
   month_not_in: "month is none of",
   ```
2. In `isValuelessOperator`, add `"month_current",` after `"date_anniversary_today",`.
3. Change `isMultiValueOperator` to:
   ```ts
   export function isMultiValueOperator(op: string): boolean {
     return ["in", "not_in", "month_in", "month_not_in"].includes(op)
   }
   ```
4. Add, right after `isMultiValueOperator`:
   ```ts
   export const MONTH_OPTIONS: AmpOption[] = [
     { value: "1", label: "January" },
     { value: "2", label: "February" },
     { value: "3", label: "March" },
     { value: "4", label: "April" },
     { value: "5", label: "May" },
     { value: "6", label: "June" },
     { value: "7", label: "July" },
     { value: "8", label: "August" },
     { value: "9", label: "September" },
     { value: "10", label: "October" },
     { value: "11", label: "November" },
     { value: "12", label: "December" },
   ]

   export function isMonthListOperator(op: string): boolean {
     return op === "month_in" || op === "month_not_in"
   }
   ```

### 3b. `src/components/patterns/amp-condition-builder/condition-row.tsx`

Current lines 49–51:
```ts
  const input = meta ? fieldInput(meta) : "text"
  const valueOptions = meta?.ref ? (entityOptions[meta.ref] ?? []) : (meta?.options ?? [])
  const showValue = !isValuelessOperator(condition.operator)
```
Change to:
```ts
  const monthList = isMonthListOperator(condition.operator)
  const input = monthList ? "select" : meta ? fieldInput(meta) : "text"
  const valueOptions = monthList
    ? MONTH_OPTIONS
    : meta?.ref ? (entityOptions[meta.ref] ?? []) : (meta?.options ?? [])
  const showValue = !isValuelessOperator(condition.operator)
```
Import `isMonthListOperator` and `MONTH_OPTIONS` from the same module that `isValuelessOperator` is imported from.

**Value reset on operator change:** read the operator-change handler in this file.
- When the new operator is `month_in` / `month_not_in` and the current value is not an array, set `value: []`.
- When the new operator is valueless (`isValuelessOperator`), clear the value the same way the handler already does for `birthday_today`.
- When switching **from** a month-list operator to a date operator (`greater_or_equal` etc.), set `value: ""`.
- If the handler already resets values on every operator change, only confirm this behaviour and do not duplicate it.

**Calendar order of tags:** wherever the multi-value `onChange` for this row is handled (in `condition-row.tsx` if it wraps the value input's onChange, otherwise in `value-input.tsx`), when `isMonthListOperator(condition.operator)`, sort the selected array numerically before saving: `[...next].sort((a, b) => Number(a) - Number(b))`. Keep it scoped to month operators so Gender/Tier order is unchanged.

### 3c. `src/components/patterns/amp-condition-builder/value-input.tsx`

This file (175 lines) renders multi-select with Polaris `Combobox` + `Listbox` + `Tag`, single select with `Select`, and date/number/text with `TextField`.
- Read it and confirm that the multi-select branch is taken for `isMultiValueOperator(operator) && input === "select"` with options.
- If the branch condition is different, adjust the **props passed from condition-row** so the existing multi-select branch is taken. Do not add a new branch or component.
- Placeholder: if the multi-select placeholder is generic (for example "Select values"), leave it. Do not special-case copy.

### 3d. Visual verification (required; the user asked that the UI look clean)

1. `cd ~/Documents/rocket/loyalty-admin && npm run dev` (port 3001). Log in via `http://localhost:3001/api/agent-login?redirect=/workflow-list`.
2. Use the Playwright MCP. Open any Draft workflow (or create one; do not activate it). Open the entry node → Entry type "Custom condition" → Collection "Member Profile" → field "Birth Date".
3. Screenshot and check each item:
   - The operator dropdown lists, in order: is today (birthday), month is the current month, month is any of, month is none of, is at least, is at most, is greater than, is less than.
   - "month is any of" shows the same multi-select control as Gender → "is any of". Open both and compare screenshots: same component, same spacing.
   - The listbox shows January…December with check state. Selecting March, then January, shows tags **January, March** in calendar order. Tags wrap inside the config panel with no horizontal scroll or overflow past the panel edge, and each tag has a working remove (x).
   - "month is the current month" shows **no** value input, and the row height matches the "is today (birthday)" row.
   - Switching operator from "month is any of" to "is at least" clears the tags and shows an empty date field, with no console error.
   - Click **Preview matching users** with "month is any of" = your current month. It returns a count with no error.
   - Save draft, reload, reopen the node: the operator and tags persist.
4. Repeat the "month is any of" check once in the **audience builder** (`/audience-builder` or wherever `AmpConditionBuilder` is used for audiences; grep for `AmpConditionBuilder` usages). It shares the metadata and must render the same way.
5. Attach the screenshots in the final chat summary.

### 3e. Checks

- `ReadLints` on the touched files.
- Tests: existing vitest files live in `src/app/(admin)/workflow-list/lib/*.test.ts`, but vitest is not in `package.json`. Try `npx vitest run "src/app/(admin)/workflow-list/lib"` **once**. If it cannot resolve vitest, do not install anything: note it and move on.
- Commit in loyalty-admin: `feat(amp): birth date month operators (any of / none of / current month)`. No push unless asked.

---

## Phase 4: 0032 messaging-service: follower-ID endpoint

Only after the Phase 0 answer about the dirty files.

### 4a. `src/adapters/line.ts`: add an exported function (keep existing code untouched)

```ts
export type LineFollowerPage =
  | { ok: true; userIds: string[]; next: string | null }
  | { ok: false; status: number; error: string }

export async function listLineFollowerIds(
  accessToken: string,
  start?: string | null,
  limit = 1000,
): Promise<LineFollowerPage> {
  const url = new URL("https://api.line.me/v2/bot/followers/ids")
  url.searchParams.set("limit", String(Math.min(Math.max(limit, 1), 1000)))
  if (start) url.searchParams.set("start", start)
  const res = await fetch(url, { headers: { Authorization: `Bearer ${accessToken}` } })
  if (!res.ok) {
    const text = await res.text()
    return { ok: false, status: res.status, error: text.slice(0, 500) }
  }
  const body = (await res.json()) as { userIds?: string[]; next?: string }
  return { ok: true, userIds: body.userIds ?? [], next: body.next ?? null }
}
```
Match the file's existing semicolon/quote style when pasting.

### 4b. `src/resolution/resolve-recipient.ts`

`getCredentials(merchantId, channel, smsPurpose)` (lines ~198–238) is module-private. Add `export` to it. Change nothing else in this file.

### 4c. `src/index.ts`: new route

Register after `POST /send`, behind the same global `requireAuth` (Bearer = `SUPABASE_SERVICE_ROLE_KEY`). Follow the file's existing handler style for try/catch and JSON responses:

```ts
app.post("/line/followers", async (req, res) => {
  try {
    const { merchant_id, start } = req.body ?? {}
    if (typeof merchant_id !== "string" || !merchant_id) {
      return res.status(400).json({ success: false, error: "merchant_id is required" })
    }
    const { credentials } = await getCredentials(merchant_id, "LINE")
    const token = credentials?.messaging_channel_access_token
    if (typeof token !== "string" || !token) {
      return res.status(404).json({ success: false, error: "line_credentials_not_found" })
    }
    const page = await listLineFollowerIds(token, typeof start === "string" ? start : null)
    if (!page.ok) {
      const forbidden = page.status === 403
      return res.status(forbidden ? 403 : 502).json({
        success: false,
        error: forbidden ? "followers_api_forbidden" : "line_api_error",
        detail: page.error,
      })
    }
    return res.json({ success: true, user_ids: page.userIds, next: page.next })
  } catch (e) {
    return res.status(500).json({ success: false, error: (e as Error).message })
  }
})
```
- Confirm that `"LINE"` is the channel key `getCredentials` maps to `service_name = 'line_messaging'`: check `channelToServiceName`. It must be the same string `inngest-amp-serve` sends as `channel` to `/send` (`"LINE"`).
- If `getCredentials` throws when no row exists (`.single()`), the catch returns 500. That is acceptable.

### 4d. Test + build

- Add a test case to `src/adapters/line.test.ts` following its existing mocking pattern. Cover: (1) a 200 response with `userIds` + `next` maps to `{ok:true,...}`; (2) a 403 maps to `{ok:false,status:403}`; (3) `limit` is clamped to 1000 and `start` is passed only when given.
- `npm test` and `npm run build` (tsc).
- Commit: `feat(line): follower ID listing endpoint for AMP non-member entry`. **STOP AND ASK** before pushing; pushing `main` deploys Render. Phase 7 depends on this being live.
- After the deploy, run a read-only smoke test: POST `/line/followers` with `{ "merchant_id": "<a merchant id the user names>" }` using the service-role bearer. Expect `success: true` and `user_ids` as an array. Do not invent a merchant id; ask the user which merchant to test on.

---

## Phase 5: 0032 backend (migration B)

File: `supabase-crm/supabase/migrations/20260923161000_amp_line_friends_exclude_members.sql`.

### 5a. New RPC `fn_amp_filter_non_member_line_ids`

`user_accounts` has about 3.7M rows. The index `idx_user_accounts_merchant_line_id ON user_accounts (merchant_id, line_id) WHERE line_id IS NOT NULL` already exists, so **do not create an index**.

```sql
CREATE OR REPLACE FUNCTION public.fn_amp_filter_non_member_line_ids(
  p_merchant_id uuid,
  p_line_user_ids text[]
)
RETURNS text[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT COALESCE(array_agg(x), ARRAY[]::text[])
  FROM unnest(COALESCE(p_line_user_ids, ARRAY[]::text[])) AS x
  WHERE x IS NOT NULL
    AND x <> ''
    AND NOT EXISTS (
      SELECT 1 FROM user_accounts ua
      WHERE ua.merchant_id = p_merchant_id
        AND ua.line_id = x
    );
$function$;

REVOKE ALL ON FUNCTION public.fn_amp_filter_non_member_line_ids(uuid, text[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_amp_filter_non_member_line_ids(uuid, text[]) TO service_role;
```

### 5b. `bff_amp_batch_run`: new branch

- Copy the full live definition saved in Phase 0.
- Insert this block **immediately after the `END IF;` that closes the `IF v_entry_type = 'all_line_friends' THEN` branch**.
- The variables `v_merchant_id`, `v_dispatch_url`, `v_service_role_key`, and `v_request_id` already exist in the function.

```sql
  IF v_entry_type = 'all_line_friends_exclude_members' THEN
    INSERT INTO workflow_log (
      merchant_id, workflow_id, user_id, inngest_run_id,
      event_type, event_data, run_scope
    ) VALUES (
      v_merchant_id, p_workflow_id, NULL,
      'batch_run_' || gen_random_uuid()::text,
      'batch_run_requested',
      jsonb_build_object(
        'entry_type', 'all_line_friends_exclude_members',
        'run_scope', 'line',
        'requested_at', now()
      ),
      'line'
    );

    v_request_id := net.http_post(
      url := v_dispatch_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_service_role_key
      ),
      body := jsonb_build_object(
        'workflow_id', p_workflow_id,
        'merchant_id', v_merchant_id,
        'entry_type', 'all_line_friends_exclude_members',
        'run_scope', 'line',
        'trigger_data', jsonb_build_object(
          'source', 'batch_run',
          'entry_type', 'all_line_friends_exclude_members'
        )
      )
    );

    RETURN jsonb_build_object(
      'success', true,
      'workflow_id', p_workflow_id,
      'entry_type', 'all_line_friends_exclude_members',
      'run_scope', 'line',
      'matching_users', 0,
      'dispatched', 0,
      'batch_count', 1,
      'pg_net_request_ids', jsonb_build_array(v_request_id),
      'message', 'Started sending to LINE friends who are not members. Friends are enrolled as the follower list is scanned.'
    );
  END IF;
```
Do not put `fanout` in this `trigger_data`. The executor treats a missing `fanout` as "this is the seed run".

### 5c. Apply and verify

1. `apply_migration` with name `amp_line_friends_exclude_members`.
2. Verify:
   ```sql
   WITH m AS (SELECT merchant_id, line_id FROM user_accounts WHERE line_id IS NOT NULL LIMIT 1)
   SELECT fn_amp_filter_non_member_line_ids(m.merchant_id, ARRAY[m.line_id, 'U00000000000000000000000000000000', '', NULL]) FROM m;
   -- expect: {U00000000000000000000000000000000}
   SELECT has_function_privilege('authenticated', 'public.fn_amp_filter_non_member_line_ids(uuid, text[])', 'EXECUTE'); -- false
   SELECT has_function_privilege('service_role', 'public.fn_amp_filter_non_member_line_ids(uuid, text[])', 'EXECUTE');  -- true
   SELECT pg_get_functiondef(p.oid) ILIKE '%all_line_friends_exclude_members%' FROM pg_proc p WHERE p.proname = 'bff_amp_batch_run'; -- true
   ```
3. Save the migration file.

---

## Phase 6: 0032 Edge `amp-dispatch-workflow-batch`

1. **Mirror first.** Create `supabase-crm/supabase/functions/amp-dispatch-workflow-batch/index.ts` with the **exact live v57 source** from `get_edge_function`. Commit it alone: `chore(edge): mirror live amp-dispatch-workflow-batch v57`.
2. Edit that file:
   - After
     ```ts
     const isBroadcast = entry_type === 'all_line_friends' || run_scope === 'broadcast';
     const isLineSubjects = line_subjects.length > 0;
     ```
     add
     ```ts
     const isFollowerScan = entry_type === 'all_line_friends_exclude_members';
     ```
   - Change the required-input guard to:
     ```ts
     if (!isBroadcast && !isLineSubjects && !isFollowerScan && user_ids.length === 0) {
     ```
   - Insert this block **after** the `workflow_master` active check and `let dispatched = 0; let failed = 0;`, and **before** `if (isBroadcast) {`:
     ```ts
     if (isFollowerScan) {
       try {
         await postInngestEvents([{
           name: 'amp/workflow.trigger',
           data: {
             workflow_id,
             merchant_id,
             run_scope: 'line',
             trigger_data: {
               ...trigger_data,
               entry_type: 'all_line_friends_exclude_members',
               source: trigger_data.source || 'batch_run',
             },
           },
         }]);
         dispatched = 1;
         console.log(`[amp-dispatch-workflow-batch] Dispatched follower-scan seed run for ${workflow_id}`);
       } catch (e: any) {
         failed = 1;
         console.error(`[amp-dispatch-workflow-batch] Follower-scan seed error: ${e.message}`);
       }

       await supabase.from('workflow_log').insert({
         merchant_id,
         workflow_id,
         user_id: null,
         run_scope: 'line',
         inngest_run_id: `batch_run_follower_scan_${Date.now()}`,
         event_type: 'batch_run_completed',
         event_data: { entry_type: 'all_line_friends_exclude_members', run_scope: 'line', seed_dispatched: dispatched, failed },
       });

       return new Response(JSON.stringify({
         success: failed === 0,
         workflow_id,
         entry_type: 'all_line_friends_exclude_members',
         run_scope: 'line',
         dispatched,
         failed,
       }), { headers: { 'Content-Type': 'application/json' } });
     }
     ```
3. Deploy with `deploy_edge_function`: name `amp-dispatch-workflow-batch`, files `[{name:"index.ts", content}]`, **`verify_jwt: false`**. Confirm the version incremented (to 58 or higher) and `verify_jwt` is still `false`.

---

## Phase 7: 0032 executor fan-out (`inngest-amp-serve`)

Same file as Phase 2. This work starts from the Phase 2 local file, which is already deployed.

### 7a. Helpers: add right after `callMessagingService` (around line 297)

```ts
async function callMessagingServiceFollowers(supabase, merchant_id: string, start: string | null) {
  try {
    const authKey = await getMessagingAuthKey(supabase);
    const response = await fetch(`${MESSAGING_SERVICE_URL}/line/followers`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${authKey}`
      },
      body: JSON.stringify({ merchant_id, start })
    });
    return await response.json();
  } catch (e) {
    return { success: false, error: e.message };
  }
}
```

And right after `emitInngestEvent` (around line 169):

```ts
async function emitInngestEvents(events: Array<{ name: string; data: any }>): Promise<void> {
  if (!INNGEST_EVENT_URL) throw new Error("INNGEST_EVENT_KEY missing");
  const resp = await fetch(INNGEST_EVENT_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(events)
  });
  if (!resp.ok) throw new Error(`Inngest post failed: ${resp.status} ${await resp.text()}`);
}
```

### 7b. Seed-run fan-out

In the `workflow-executor` handler, insert this block **immediately before** the existing line
`if ((ed.dispatch_line_subjects || trigger_data.entry_type === "past_line_interaction") && !trigger_data.fanout) {`:

```ts
  if (trigger_data.entry_type === "all_line_friends_exclude_members" && !trigger_data.fanout) {
    // Inngest caps steps per run; one step per 1000-follower page keeps well under it.
    const MAX_PAGES = 900;
    let start: string | null = null;
    let page = 0;
    let followers = 0;
    let dispatched = 0;
    let failure: string | null = null;
    do {
      const cursor = start;
      const res = await step.run(`follower-page-${page}`, async ()=>{
        const f = await callMessagingServiceFollowers(supabase, merchant_id, cursor);
        if (!f?.success) return { ok: false, error: f?.error || "followers_fetch_failed", next: null, followers: 0, dispatched: 0 };
        const ids: string[] = Array.isArray(f.user_ids) ? f.user_ids : [];
        let targets: string[] = [];
        if (ids.length > 0) {
          const { data, error } = await supabase.rpc("fn_amp_filter_non_member_line_ids", {
            p_merchant_id: merchant_id,
            p_line_user_ids: ids
          });
          if (error) return { ok: false, error: error.message, next: null, followers: ids.length, dispatched: 0 };
          targets = data || [];
        }
        const events = targets.map((line_user_id)=>({
          name: "amp/workflow.trigger",
          data: {
            workflow_id,
            merchant_id,
            run_scope: "line",
            line_user_id,
            user_id: null,
            trigger_data: { ...trigger_data, entry_type: "all_line_friends_exclude_members", fanout: true }
          }
        }));
        for (let i = 0; i < events.length; i += 500) await emitInngestEvents(events.slice(i, i + 500));
        return { ok: true, error: null, next: f.next || null, followers: ids.length, dispatched: targets.length };
      });
      if (!res.ok) { failure = res.error; break; }
      followers += res.followers;
      dispatched += res.dispatched;
      start = res.next;
      page++;
    } while (start && page < MAX_PAGES);
    const truncated = !failure && !!start;
    await step.run("follower-scan-log", async ()=>{
      await supabase.from("workflow_log").insert({
        merchant_id,
        workflow_id,
        user_id: null,
        line_user_id: null,
        run_scope: "line",
        inngest_run_id: runId,
        event_type: failure ? "follower_scan_failed" : "follower_scan_completed",
        event_data: {
          entry_type: "all_line_friends_exclude_members",
          pages: page,
          followers,
          excluded_members: followers - dispatched,
          dispatched,
          truncated,
          error: failure
        }
      });
    });
    return { success: !failure, fanout: { pages: page, followers, dispatched, truncated, error: failure } };
  }
```

Notes for the executor. Do not change these behaviours:
- Child runs carry `run_scope: "line"`, `line_user_id`, `user_id: null`, and `fanout: true`. Existing code then resolves `user_id` via `fn_amp_resolve_user_by_line_id` in `log-start`, which stays null for non-members. Sends push to `line_user_id` via `resolveLineRecipient`, and tracked links are skipped when there is no `user_id`. This is already how `past_line_interaction` children behave.
- A retried page step can re-emit that page's events. Re-enrollment dedupe on `workflow_log.line_user_id` covers workflows with re-enrollment off, which is the same exposure `past_line_interaction` has today.

### 7c. Entry node always takes True for this entry type

In the condition-node handler (around line 1099), change

```ts
        if (config?.entry_type === "all_line_friends" || run_scope === "broadcast") {
```

to

```ts
        if (config?.entry_type === "all_line_friends" || config?.entry_type === "all_line_friends_exclude_members" || run_scope === "broadcast") {
```

Leave the body of that block unchanged; it already logs `config?.entry_type`.

### 7d. Deploy

Deploy exactly as in Phase 2 (`verify_jwt: false`), then confirm the version. **Order:** deploy only after the messaging-service `/line/followers` is live on Render (Phase 4) and migration B is applied (Phase 5).

---

## Phase 8: 0032 admin FE (loyalty-admin)

Directory: `src/app/(admin)/workflow-list/`.

1. **`lib/types.ts`**: add `| "all_line_friends_exclude_members"` to `ConditionEntryType`, directly after `| "all_line_friends"`.
2. **`lib/node-config-contract.ts`**:
   - Add `"all_line_friends_exclude_members",` to `ENTRY_TYPES`, after `"all_line_friends",`.
   - Then read lines ~240–241, where `all_line_friends` / `past_line_interaction` are special-cased during serialization. Wherever `all_line_friends` gets special handling there (for example, groups forced empty), give the new type the **same** handling.
3. **`lib/workflow-validation.ts`**:
   - Add, next to `BROADCAST_COPY`:
     ```ts
     const EXCLUDE_MEMBERS_COPY =
       "Sends an individual LINE message to every friend of your LINE Official Account who isn't a member. Friends are matched to members by linked LINE account, so members who never linked LINE will still receive it. Runs each time the workflow is activated; scheduled runs don't apply. Requires a verified or premium LINE Official Account."
     ```
     and next to `allLineFriendsBroadcastCopy()`:
     ```ts
     export function lineFriendsExcludeMembersCopy(): string {
       return EXCLUDE_MEMBERS_COPY
     }
     ```
   - After the existing `if (entry && ... === "all_line_friends") { ... }` advisory block, add a sibling block for `"all_line_friends_exclude_members"` that pushes two soft advisories. Use the same `issues.push({ code, message, node_id })` shape:
     - For each LINE send node (the same `isLine` test as the broadcast block) where `data.recipient_mode === "broadcast"`: code `exclude_members_recipient_mode_mismatch`, message `"This workflow sends individually to each non-member friend. Set this LINE message to individual (push) recipient mode."`.
     - For each **non-entry** `condition` node whose groups (read them the same way the canvas stores them, `data.groups` / `data.condition_groups`) contain a group with `(group.type ?? "simple")` equal to `"simple"` or `"aggregate"`: code `exclude_members_member_condition`, message `"LINE friends who aren't members have no member data, so this condition will always take the False path."`.
   - `formatBatchRunToast`: no change needed, because the RPC returns `message` and the first line of that function uses it.
4. **`components/config-panels/condition-config.tsx`**:
   - `ENTRY_OPTIONS`: insert `{ label: "All LINE Friends (exclude members)", value: "all_line_friends_exclude_members" },` directly after the `All LINE Friends` option.
   - `handleEntryTypeChange`: change `if (value === "all_line_friends") {` to `if (value === "all_line_friends" || value === "all_line_friends_exclude_members") {`. The body (clear audience, `groups: []`, `match: "all"`) is correct for both.
   - Panel render (around line 246): add a branch before the `line_option_selected` branch:
     ```tsx
     ) : entryType === "all_line_friends_exclude_members" ? (
       <Banner tone="info">{lineFriendsExcludeMembersCopy()}</Banner>
     ```
     Import `lineFriendsExcludeMembersCopy` next to `allLineFriendsBroadcastCopy`.
5. **`components/nodes/workflow-nodes.tsx`**: after the `all_line_friends` summary line, add
   `else if (entryType === "all_line_friends_exclude_members") summary = "All LINE Friends (exclude members)"`.
6. **Tests:**
   - `lib/node-config-contract.test.ts`: add a round-trip case proving `entry_type: "all_line_friends_exclude_members"` survives serialize/deserialize with empty groups.
   - `lib/workflow-validation.test.ts`: add cases for both new advisory codes, plus one negative case (a push-mode send node with no member conditions yields no issues).
   - Run them as in Phase 3e.
7. **Visual verification** (Playwright MCP, localhost:3001, agent login). Use a **Draft** workflow and **do not activate it**. Screenshot each check:
   - The Entry type dropdown shows "All LINE Friends (exclude members)" directly under "All LINE Friends". The label fits in the select with no truncation at the panel's default width.
   - Selecting it shows only the info Banner below Entry type: no condition builder and no Preview button. The banner text wraps cleanly inside the panel with consistent padding, matching how the "All LINE Friends" banner looks. Compare the two screenshots.
   - The canvas entry card reads "All LINE Friends (exclude members)". It must fit inside the card like "All LINE Friends (broadcast)" does. If it truncates, check how the existing summary is truncated (ellipsis) and make sure it is not clipped mid-glyph. Do not change the card component.
   - Switching back to "Custom condition" restores the normal builder with no console errors.
   - Add a Conditional Split with a Member Profile condition: the `exclude_members_member_condition` advisory surfaces wherever the existing broadcast advisory surfaces.
8. `ReadLints`, then commit in loyalty-admin: `feat(amp): All LINE Friends (exclude members) entry type`. No push unless asked.

**Release order:** push loyalty-admin for 0032 **only after** Phases 4–7 are live. Otherwise merchants could pick an entry type the backend can't run.

---

## Phase 9: End-to-end check for 0032 (sends real LINE messages; STOP AND ASK)

Ask: *"Which merchant and LINE OA should I use for a live test of 'All LINE Friends (exclude members)'? It will send a real LINE message to every non-member friend of that OA."* Proceed only with a named test merchant (ideally a test OA with a few friends, at least one of whom is a member with a linked `line_id`).

1. Create a Draft workflow on that merchant with the entry "All LINE Friends (exclude members)" → one Send LINE node (push mode, short test text). Save & activate.
2. The toast reads "Workflow activated — Started sending to LINE friends who are not members…".
3. Check `workflow_log` for that `workflow_id`:
   - `batch_run_requested` (run_scope `line`) → `batch_run_completed` with `seed_dispatched: 1` → `follower_scan_completed` with `followers`, `excluded_members`, `dispatched` → one child run per dispatched `line_user_id`.
   - The member friend is **not** among the child `line_user_id`s.
4. The member test device receives nothing, and the non-member test device receives the message.
5. Deactivate the test workflow.

---

## Phase 10: Product-doc closeout (once)

Follow `~/Documents/rocket/supabase-crm/.cursor/rules/06-update-docs.mdc` and `13-requirements-writing.mdc`. Edit by absolute path. The domain is AMP workflows.

- `requirements/AMP_Condition_Contract.md` → `## 2. Operator vocabulary`: add rows in the same table format as the existing `birthday_today` row:
  - `| \`month_in\`, \`month_not_in\` | \`EXTRACT(MONTH FROM field)\` IN / NOT IN listed months | \`value\`: array of month numbers as strings "1"–"12"; invalid entries ignored; NULL date never matches (including \`month_not_in\`). |`
  - `| \`month_current\` | month of field = current month in \`timezone\` | Optional \`timezone\` (condition, then group, else UTC). NULL date never matches. |`
  - Also add a §4.1-style example: `{"field": "birth_date", "operator": "month_in", "value": ["1", "12"]}`.
- `requirements/AMP_Workflows.md`:
  - Under `## Rules`, add `### Entry types` listing all six entry types and their dispatch mode: `audience`, `condition`, `all_line_friends` (one LINE broadcast), `line_option_selected` (realtime postback), `past_line_interaction` (one push run per LINE user who tapped matching options), and `all_line_friends_exclude_members`. For the last one: follower IDs are fetched from LINE at activation, members are removed by `user_accounts.line_id`, it runs one push per remaining friend, it is manual activate only, it requires a verified/premium OA, and unlinked members are not excluded.
  - Under `### Condition evaluation`, note that split nodes now evaluate all groups via `fn_evaluate_amp_condition_group` (the same semantics as entry/preview/batch).
  - Under `## System`: Functions → `fn_amp_filter_non_member_line_ids`; External services → messaging-service `POST /line/followers`; Flows → the seed run → `follower-page-N` steps → per-friend runs.
- Registries: update the `requirements/REGISTRY_*` entries per `06-update-docs.mdc` for the new RPC, the edited RPCs, the two Edge functions, and the new messaging-service route.
- `requirements/CHANGELOG.md`: one entry covering both changes, in the file's existing format.

Commit these docs in supabase-crm, together with the migration files and Edge sources, on the branch from Phase 0.

---

## Phase 11: Deck write-back and summary

Only after the relevant phases are live:

`eng_bugs_patch` (CRM Knowledge MCP):
```json
{ "bugs": [
  { "code": "RULEBASEDWORKFLO-0033", "status": "done",
    "implementation_notes_text": "Added Birth Date operators: 'month is any of' / 'month is none of' (Jan–Dec multi-select) and 'month is the current month' (for one monthly scheduled workflow). Works in entry, Conditional Split, preview, batch and schedule. Members without a birth date never match. Also fixed Conditional Split so birthday conditions (incl. 'is today (birthday)') evaluate correctly — splits now use the same evaluator as entry/preview." },
  { "code": "RULEBASEDWORKFLO-0032", "status": "done",
    "implementation_notes_text": "New Entry type 'All LINE Friends (exclude members)'. On activate it fetches the LINE OA follower list, removes friends linked to a member account, and sends each remaining friend an individual LINE push. Manual activate only (no schedule). Requires a verified or premium LINE OA. Members who never linked LINE cannot be excluded." }
] }
```
Check `results[].ok`. If 0032 isn't live (for example, the pushes weren't approved), patch only 0033 and say so.

Final chat summary to the user:
- What shipped, per bug.
- What is still unpushed or undeployed.
- The screenshots from Phases 3d and 8.7.
- Any STOP AND ASK answers that are still open.
