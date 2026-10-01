# BFF Function Conventions — Admin & User

Conventions and best practices for writing `bff_*` (admin panel) and `bff_user_*` (end-user app) Postgres functions. Distilled from the live conventions in `.cursor/rules/10-function-conventions.mdc`, `.cursor/rules/11-auth-conventions.mdc`, and ~400 deployed functions.

**Core principle: identity comes from the token, never from the payload.**
- Admin BFFs derive **merchant** from the JWT / headers via `get_current_merchant_id()`.
- User BFFs derive **user** (and their merchant) from the token via `get_current_user_id()` → `user_accounts`.
- A BFF function **never** accepts `p_merchant_id` or `p_user_id` as a way to choose whose data to act on. Anything the client could lie about must come from auth context.

---

## 1. Naming

| Prefix | Caller | Identity source |
|---|---|---|
| `bff_*` | Admin panel (loyalty) | `get_current_merchant_id()` |
| `bff_admin_*` | Admin panel, admin-management ops | Same as `bff_*` |
| `cs_bff_*` | CS admin panel | `get_current_merchant_id()` |
| `bff_user_*` | End-user app (LINE / web / WeWeb) | `get_current_user_id()` → `user_accounts` |

Verb patterns:

| Pattern | Purpose | Example |
|---|---|---|
| `bff_list_<entities>` | Admin list/table page | `bff_list_spin_wheels`, `bff_list_campaigns` |
| `bff_get_<entity>_details` | Load one object + children for a config/edit page | `bff_get_spin_wheel_details` |
| `bff_upsert_<entity>` | Create-or-update submit from a config page | `bff_upsert_spin_wheel` |
| `bff_upsert_<entity>_with_<children>` | Submit with nested children | `bff_upsert_reward_with_conditions_and_limits` |
| `bff_approve_*` / `bff_reject_*` / `bff_delete_*` | Single-action admin operations | `bff_approve_receipt_upload` |
| `bff_user_get_*` | User-facing read | `bff_user_get_spin_wheel_status`, `bff_user_get_surveys` |
| `bff_user_<verb>_*` | User-facing action/submit | `bff_user_submit_survey`, `bff_user_spin_wheel` |

All BFFs: `RETURNS jsonb`, `LANGUAGE plpgsql`, `SECURITY DEFINER`, `SET search_path TO 'public'`.

---

## 2. Auth — the two contexts

### 2.1 Admin auth (`bff_*`, `bff_admin_*`, `cs_bff_*`)

**Who:** merchants, operators, CS agents on the admin panel, logged in via Supabase Auth JWT.

Two checks, in order, at the top of every function:

1. **Admin identity** — the caller must be an active row in `admin_users`:

```sql
IF NOT EXISTS (
  SELECT 1 FROM public.admin_users
  WHERE auth_user_id = auth.uid() AND active_status = true
) THEN
  RETURN fn_response_error('Forbidden', 'Admin access required', 'FORBIDDEN');
END IF;
```

2. **Merchant context** — resolved from the request, never from a parameter:

```sql
v_merchant_id := public.get_current_merchant_id();
IF v_merchant_id IS NULL THEN
  RETURN fn_response_error('No merchant context', 'Unable to determine merchant from authentication', 'NO_MERCHANT_CONTEXT');
END IF;
```

`get_current_merchant_id()` resolution priority (highest first):

| # | Source |
|---|---|
| 1 | `x-merchant-id` header |
| 2 | `x-merchant-code` header → `merchant_master` lookup |
| 3 | JWT claim `merchant_id` (set by `custom_access_token_hook`) |
| 4 | JWT `user_metadata.merchant_id` |
| 5 | JWT `app_metadata.active_merchant_id` (multi-merchant admins) |
| 6 | `admin_users` lookup by `auth.uid()` |
| 7 | `user_accounts` lookup by `auth.uid()` |

For sensitive operations, add a permission check after the merchant check:

```sql
IF NOT check_admin_permission('manage_rewards') THEN
  RETURN fn_response_error('Forbidden', 'Insufficient permissions', 'FORBIDDEN');
END IF;
```

### 2.2 End-user auth (`bff_user_*`)

**Who:** loyalty members / customers on the user app. Identity arrives either as a Supabase Auth JWT (`auth.uid()`) or as an `x-user-id` header from the custom session layer (WeWeb).

`get_current_user_id()` = `COALESCE(get_header_user_id(), auth.uid())` — header first, then JWT.

The standard resolution block derives **both** the user account and their merchant from the token. The merchant is a property of the user, not a parameter:

```sql
v_auth_uid := public.get_current_user_id();
IF v_auth_uid IS NULL THEN
  RETURN fn_response_error('Unauthenticated', 'No authenticated user context', 'UNAUTHENTICATED');
END IF;

SELECT ua.id, ua.merchant_id
INTO v_user_id, v_merchant_id
FROM public.user_accounts ua
WHERE ua.auth_user_id = v_auth_uid
  AND ua.deleted_at IS NULL
  AND ua.is_active IS NOT FALSE;

IF v_user_id IS NULL THEN
  RETURN fn_response_error('User not found', 'No user account is linked to this authenticated user', 'USER_NOT_FOUND');
END IF;
```

Note: the identity value may be either `user_accounts.id` (header path) or `auth_user_id` (JWT path). When both paths must work, match either column, scoped to the merchant (pattern from `bff_user_submit_survey`):

```sql
SELECT ua.id INTO v_user_id
FROM public.user_accounts ua
WHERE ua.merchant_id = v_merchant_id
  AND ua.deleted_at IS NULL
  AND ua.is_active IS NOT FALSE
  AND (ua.id = v_current_identity_id OR ua.auth_user_id = v_current_identity_id)
LIMIT 1;
```

**Semi-public user BFFs** (e.g. anonymous survey submission): resolve the merchant via `get_current_merchant_id()` (headers work for anon), then *try* to resolve the user and continue with `v_user_id = NULL` if unidentified. Gate any user-bound side effects (rewards, wallet writes) on `v_user_id IS NOT NULL`.

### 2.3 What BFFs must never do

- Never accept `p_merchant_id` — that's the `api_*` pattern (API-key callers only).
- Never accept `p_user_id` on `bff_user_*` to select whose data to act on.
- Never skip the merchant filter in a query "because RLS will catch it" — RLS is the safety net, the explicit `merchant_id = v_merchant_id` filter is the contract.

---

## 3. Payload (parameter) conventions

- Parameters are `p_` prefixed; local variables are `v_` prefixed.
- **Simple reads**: scalar params with defaults — `p_mode text DEFAULT 'edit'`, `p_spin_wheel_id uuid DEFAULT NULL`.
- **List functions**: usually **zero params** (everything derives from merchant context). Optional filter params are scalars with `DEFAULT NULL` (e.g. `cs_bff_list_conversations(p_status, p_priority, ...)`).
- **Complex submits**: a single `p_config jsonb` (or `p_data jsonb`) carrying the whole object graph — parent fields at the top level, children as arrays:

```json
{
  "id": null,
  "name": "Birthday Wheel",
  "active_status": true,
  "window_start": "2026-07-01T00:00:00+07:00",
  "segments": [
    { "id": null, "label": "10 points", "weight": 30, "outcomes": [ ... ] },
    { "id": "existing-uuid", "label": "No win", "weight": 70, "outcomes": [] }
  ],
  "limits": [ { "id": null, "scope": "per_user", "count": 1, "time_unit": "day" } ]
}
```

  Alternatively, flat entities use named scalar params + `jsonb` params for children (`bff_upsert_macro_with_contexts(p_macro_id, p_name, ..., p_contexts jsonb)`). Prefer `p_config jsonb` when the object has 8+ fields or nested children.
- Parse jsonb defensively at the boundary: `NULLIF(p_config->>'x', '')::uuid`, `COALESCE((p_config->>'active_status')::boolean, true)`, and check `jsonb_typeof(... ) = 'array'` before looping.
- `id: null` (or absent) in a payload means INSERT; a present `id` means UPDATE. The same rule applies per child row.

---

## 4. Response structure

Every BFF returns jsonb with a `success` boolean. Use the shared helpers — do not hand-build response envelopes in new functions:

```sql
-- success → {"success": true, "title": ..., "description": ..., "data": {...}}
RETURN fn_response_success('Spin wheel saved', NULL, jsonb_build_object('spin_wheel_id', v_id));

-- error → {"success": false, "title": ..., "description": ..., "data": {"error_code": ...}}
RETURN fn_response_error('Not found', 'Spin wheel not found or access denied', 'NOT_FOUND');
```

- `fn_response_success(p_title, p_description, p_data jsonb DEFAULT '{}')`
- `fn_response_error(p_title, p_description, p_code DEFAULT NULL, p_data jsonb DEFAULT '{}')` — the code lands in `data.error_code`.

Conventions inside `data`:

- **List**: a named array key — `{"spin_wheels": [...]}` — never a bare array, so the shape can grow (counts, pagination) without breaking the FE.
- **Get details**: named sections — `{"campaign": {...}, "segments": [...], "limits": [...]}`.
- **Upsert**: the entity id + mutation counters — `{"spin_wheel_id": ..., "segments_created": 2, "segments_updated": 1, "segments_deleted": 0, ...}`.
- Arrays are never NULL: wrap with `COALESCE(jsonb_agg(...), '[]'::jsonb)`.

Common error codes: `FORBIDDEN`, `NO_MERCHANT_CONTEXT`, `UNAUTHENTICATED`, `USER_NOT_FOUND`, `NOT_FOUND`, `VALIDATION_ERROR`, plus `SQLSTATE` in the catch-all handler.

(You will see older functions returning raw `jsonb_build_object('success', false, 'error', ...)` — that is legacy. New functions use the helpers.)

---

## 5. Standard function skeleton

Every BFF follows the same spine:

```sql
CREATE OR REPLACE FUNCTION public.bff_<verb>_<entity>(...)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_merchant_id uuid;
  -- v_user_id uuid;  (user BFFs)
BEGIN
  -- 1. AUTH: resolve identity from token (admin block §2.1 or user block §2.2)

  -- 2. VALIDATE: cheap payload checks, early-return fn_response_error(...)

  -- 3. OWNERSHIP: any id passed in must belong to this merchant/user
  --    "not found or access denied" — never reveal existence across merchants

  -- 4. BUSINESS LOGIC: every query filtered by v_merchant_id (and v_user_id)

  -- 5. RETURN fn_response_success(...)

EXCEPTION WHEN OTHERS THEN
  RETURN fn_response_error('Error <doing thing>', SQLERRM, SQLSTATE);
END;
$$;
```

---

## 6. The BFF categories

### 6.1 Admin — List page (`bff_list_<entities>`)

Feeds an admin table/grid. Zero or filter-only params. One aggregated query, denormalized enough that the FE never has to join.

```sql
CREATE OR REPLACE FUNCTION public.bff_list_spin_wheels()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_merchant_id uuid;
  v_rows jsonb;
BEGIN
  -- [admin auth block §2.1]

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', sw.id,
    'name', sw.name,
    'active_status', sw.active_status,
    'segment_count', COALESCE(sc.cnt, 0),   -- child counts via LATERAL
    'created_at', sw.created_at
  ) ORDER BY sw.created_at DESC), '[]'::jsonb)
  INTO v_rows
  FROM public.spin_wheel sw
  LEFT JOIN LATERAL (
    SELECT COUNT(*)::int AS cnt FROM public.spin_wheel_segment
    WHERE spin_wheel_id = sw.id AND active_status
  ) sc ON true
  WHERE sw.merchant_id = v_merchant_id;          -- the one non-negotiable line

  RETURN fn_response_success(NULL, NULL, jsonb_build_object('spin_wheels', v_rows));
EXCEPTION WHEN OTHERS THEN
  RETURN fn_response_error('Error listing spin wheels', SQLERRM, SQLSTATE);
END;
$$;
```

Rules:
- Return list-view fields only (name, status, dates, counts) — not full child payloads.
- Deterministic `ORDER BY` inside `jsonb_agg`.
- Counts/rollups via `LEFT JOIN LATERAL`, not N follow-up calls from the FE.

### 6.2 Admin — Object config page (`bff_get_<entity>_details`)

Feeds a create/edit form. Dual mode via `p_mode`:

- `p_mode = 'new'` → return an **empty template**: every field present with NULL/default values, children as `'[]'::jsonb`. The FE renders one shape for both modes.
- `p_mode = 'edit'` → require the id, verify ownership, load parent + all children.

```sql
CREATE OR REPLACE FUNCTION public.bff_get_spin_wheel_details(
  p_mode text DEFAULT 'edit', p_spin_wheel_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  -- [admin auth block §2.1]

  IF p_mode = 'new' THEN
    RETURN fn_response_success(NULL, NULL, jsonb_build_object(
      'campaign', jsonb_build_object('id', NULL, 'name', NULL, 'active_status', true, ...),
      'segments', '[]'::jsonb,
      'limits',   '[]'::jsonb));
  END IF;

  IF p_spin_wheel_id IS NULL THEN
    RETURN fn_response_error('Missing id', 'spin_wheel_id is required for edit mode', 'VALIDATION_ERROR');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.spin_wheel
                 WHERE id = p_spin_wheel_id AND merchant_id = v_merchant_id) THEN
    RETURN fn_response_error('Not found', 'Spin wheel not found or access denied', 'NOT_FOUND');
  END IF;

  -- load parent into v_campaign, children via jsonb_agg + COALESCE('[]')
  RETURN fn_response_success(NULL, NULL, jsonb_build_object(
    'campaign', v_campaign, 'segments', v_segments, 'limits', v_limits));
END;
$$;
```

Rules:
- The `data` shape of get-details must be **round-trippable**: the FE edits it and posts it back as the upsert payload. Keep field names identical between the two functions.
- Children always `COALESCE(..., '[]'::jsonb)`; include child `id`s so the upsert can diff.

### 6.3 Admin — Submit function (`bff_upsert_<entity>`)

One function handles both create and update; the payload's `id` decides.

```sql
-- 1. [admin auth block §2.1]
-- 2. VALIDATE payload (required fields, cross-field rules, FK ownership):
IF NULLIF(p_config->>'name', '') IS NULL THEN
  RETURN fn_response_error('Validation failed', 'name required', 'VALIDATION_ERROR');
END IF;
-- referenced entities must belong to the same merchant:
IF NOT EXISTS (SELECT 1 FROM ticket_type
               WHERE id = (p_config->>'cost_ticket_type_id')::uuid
                 AND merchant_id = v_merchant_id) THEN ... END IF;

-- 3. PARENT: id NULL → INSERT (gen_random_uuid()), else verify ownership → UPDATE
-- 4. CHILDREN (per array in payload):
--      child id NULL → INSERT, else UPDATE ... AND merchant_id = v_merchant_id
--      (IF NOT FOUND → error), track v_kept_<child>_ids,
--      count v_<child>_created / _updated
-- 5. DELETE ORPHANS:
DELETE FROM public.spin_wheel_segment
WHERE spin_wheel_id = v_spin_wheel_id
  AND merchant_id = v_merchant_id
  AND (cardinality(v_kept_segment_ids) = 0 OR id != ALL(v_kept_segment_ids));
GET DIAGNOSTICS v_segments_deleted = ROW_COUNT;

-- 6. RETURN entity id + counters
RETURN fn_response_success('Saved', NULL, jsonb_build_object(
  'spin_wheel_id', v_spin_wheel_id,
  'segments_created', v_segments_created,
  'segments_updated', v_segments_updated,
  'segments_deleted', v_segments_deleted));
```

Rules:
- Validate **before** writing anything; the whole function is one transaction, so any early error return leaves the DB untouched only if nothing was written yet — order validation first.
- Every child UPDATE/DELETE carries the `merchant_id = v_merchant_id` guard so a forged child id from another merchant hits `IF NOT FOUND`.
- Single-action submits (`bff_approve_*`, `bff_delete_*`) are the degenerate case: auth → ownership check → one write → success with the affected id.

### 6.4 User — Read (`bff_user_get_*`)

Feeds the end-user app (my status, my rewards, available surveys). Merchant scoping comes from the user's own account.

```sql
CREATE OR REPLACE FUNCTION public.bff_user_get_spin_wheel_status(p_spin_wheel_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_auth_uid uuid; v_user_id uuid; v_merchant_id uuid;
BEGIN
  -- [user auth block §2.2] → v_user_id, v_merchant_id

  -- Delegate to an internal helper with resolved, trusted identifiers:
  RETURN public.get_user_spin_wheel_status(v_user_id, v_merchant_id, p_spin_wheel_id);
EXCEPTION WHEN OTHERS THEN
  RETURN fn_response_error('Error', SQLERRM, SQLSTATE);
END;
$$;
```

Rules:
- Params identify **which object**, never **which user**.
- Return only what this user may see — strip admin fields (weights, stock internals, other users' data).
- A thin BFF wrapper that resolves identity and delegates to a `fn_*` engine (which is service-role-only) is the preferred layering: auth at the edge, logic inside.

### 6.5 User — Submit / action (`bff_user_submit_*`, `bff_user_<verb>_*`)

User-initiated writes: submit a survey, spin the wheel, update a profile field.

```sql
-- 1. Resolve merchant (get_current_merchant_id() — works for anon via headers)
-- 2. Validate the payload shape and that the target object is live:
--    published/active AND merchant_id = v_merchant_id AND within window
-- 3. Resolve the user (§2.2). Strict actions error on NULL user;
--    semi-public actions (anonymous survey) continue with v_user_id = NULL
--    and gate user-bound side effects on v_user_id IS NOT NULL
-- 4. Enforce user-level limits (per-user counts, cost deduction) BEFORE the write
-- 5. Perform the write / delegate to fn_* engine
-- 6. Return an outcome the app can render directly, e.g.:
RETURN fn_response_success('Survey submitted', NULL,
  v_submit_data || jsonb_build_object('reward_outcome', v_reward_outcome));
```

Rules:
- Never trust client-supplied cost, reward, or eligibility fields — recompute server-side.
- Idempotency/limits (once-per-user, stock, cooldowns) are enforced in the function or its `fn_*` engine, never in the FE alone.
- Return rich status objects (`eligible`, `status`, `description`) so the app doesn't have to infer outcomes.

---

## 7. Checklist for any new BFF

1. Correct prefix (`bff_` / `bff_user_` / `cs_bff_`) and verb pattern from §1.
2. `SECURITY DEFINER`, `SET search_path TO 'public'`, `RETURNS jsonb`.
3. Auth block first — admin (§2.1) or user (§2.2). No `p_merchant_id`, no `p_user_id`-as-identity.
4. `check_admin_permission(...)` on sensitive admin ops.
5. Every table access filtered by `v_merchant_id` (and `v_user_id` where applicable).
6. Ownership checks say "not found or access denied" — don't leak cross-merchant existence.
7. jsonb parsed defensively (`NULLIF`, `COALESCE`, `jsonb_typeof` before looping).
8. Responses via `fn_response_success` / `fn_response_error`; arrays never NULL; `data` keys named.
9. `EXCEPTION WHEN OTHERS` → `fn_response_error(<context>, SQLERRM, SQLSTATE)`.
10. Get-details and upsert payload shapes round-trip.
11. Deploy via Supabase MCP; update `requirements/REGISTRY_SUPABASE.md`, the domain doc, and `requirements/CHANGELOG.md` (per `06-update-docs.mdc`).
