# Admin Audit Log — Final Plan

Status: approved direction (2026-09-23). Execute in a fresh thread, phase by phase, stopping at each checkpoint. Schema, function, and deploy steps need explicit approval.

## Goal

One log of every change an admin makes, **including the payload they sent**: master data (rewards, missions, tiers, campaigns, content), configuration, member management, and Front Line / approval actions (receipt approve/reject, currency adjust, …). Each entry reads as an action — *"Somchai updated reward R-12: price 100 → 120"* — and is visible in the admin app.

Member activity must never appear, even when members and admins go through the same function or write to the same tables.

## Decision and why

**Admin write functions log themselves**, through one shared helper called in the same transaction as the change. Nothing upstream of the function sees the request body. Alternatives considered and rejected:

| Option | Why not |
|---|---|
| Row triggers | Wrong unit: one admin action changes several rows in tables members also write to. No payload. |
| Supabase API request logs (native) | They record the admin token (user ID, issuer, session), endpoint, status, and time, but **no request body**. Retention is short and the admin app can't query them. Used below as a **coverage safety net** instead. |
| `pgaudit` (native, installed) | Sees admins and members as the same database role (`authenticated`), so it can't tell which admin did something. |
| API pre-request hook + change stream | Gets row changes without per-function work, but still no payload, and needs an always-on reader service. |

**Cost of the decision:** every new admin write function must call the logger. This is made routine by the convention changes in Phase 3 and checked by two automated checks in Phase 6.

## Verified facts (2026-09-23)

- **Admin and member tokens are distinguishable.** Admin tokens come from Supabase Auth: issuer `https://wkevmsedchftztoolkmi.supabase.co/auth/v1`, with a session id. In the last 24h that was 85 users and ~32k write-style requests. Member tokens are the custom login: issuer `supabase`, no session. That was ~2,400 users and ~45k requests. Service-key calls (~27k) and API-key-only calls (~500k) carry no person.
- `is_admin()` = active `admin_users` row where `auth_user_id = auth.uid()`. `auth.uid()` still works inside `SECURITY DEFINER` functions.
- 86 `bff_admin_*` functions, all `SECURITY DEFINER`. 145 of 183 read-style BFFs are declared `VOLATILE`, so volatility can't be used to tell reads from writes.
- The standard skeleton (`requirements/BFF_Conventions.md` §5) ends with `EXCEPTION WHEN OTHERS THEN RETURN fn_response_error(...)`. A log insert inside the body is rolled back with the rest of the action on error, which is what we want.
- Existing one-off logs: `purchase_receipt_upload_review_audit`, `codes_deletion_log`, `user_removal_log`, `frontline_mission_claim_log`, plus admin info in `wallet_ledger.metadata` for manual adjustments.
- `pg_cron` is installed. `pg_partman` is not. There's precedent for append-only tables: the trigger `internal_product_catalog_change_log_no_update`.

---

## Phase 0 — Confirm the admin test and the blind spots (read-only)

1. Confirm the helper's admin test:
   - short-circuit: the token issuer must be Supabase Auth (`auth.jwt()->>'iss'`);
   - then look up the active `admin_users` row by `auth_user_id` for the resolved merchant.
   - Confirm `admin_users(auth_user_id)` is indexed.
2. List admin actions that write through the **service key** (Edge functions, Render services, Inngest) and so carry no admin token. For each, record whether it can forward the admin's token, or must pass a verified actor.

## Phase 1 — Inventory of admin write paths (read-only)

Use three sources, because names aren't reliable and some functions are shared.

- **A. Request logs (native evidence).** Over every retained day (the tool queries 24h at a time), list the endpoints called with **admin tokens** using POST, PATCH, PUT, or DELETE on `/rest/v1/rpc/*`, `/rest/v1/<table>`, and `/functions/v1/*`. This finds misnamed and shared functions, and admin direct table writes.
- **B. Admin client code.** In `loyalty-admin`, and any other merchant-admin surface in `System_Map.md` such as `rewarding-shopify`'s admin UI, collect:
  - every `.rpc('<name>')` call;
  - every Edge function invoke;
  - every direct `.from('<table>').insert|update|upsert|delete`.
- **C. The database.** List every public function that writes (INSERT, UPDATE, DELETE, or a call to a writing `fn_*`). For each, record its grants and whether it has an admin check (`check_admin_permission`, `is_admin`, the admin block from §2.1).

**Classify each write path:**
- **admin-only:** instrument.
- **shared:** instrument. The helper ignores members.
- **member / system / `api_*` / cron:** out of scope.
- **read-only:** out of scope.

**Flag, report only:**
- misnamed functions;
- admin write functions with no admin check (a security finding);
- admin direct table writes (they can't be logged until moved behind a function).

**Output:** `docs/ADMIN_WRITE_INVENTORY.md`. It has one row per path: name, kind (rpc / edge / table), callers (surface + file), class, `action` name, entity type, and flags.

**Checkpoint 1:** the user reviews the inventory and flags, and answers the open decisions.

## Phase 2 — Foundation (schema; needs approval)

**Table `admin_audit_log`**, partitioned by month on `created_at`:

| Column | Meaning |
|---|---|
| `id uuid`, `merchant_id uuid not null`, `actor_admin_id uuid not null` | Who, for which merchant |
| `action text` | `<entity>.<verb>`: `reward.create`, `reward.update`, `receipt.approve`, `member.create`, `currency.adjust` |
| `entity_type text`, `entity_id uuid` | The main record acted on |
| `payload jsonb` | What the admin sent, after redaction and size cap |
| `changes jsonb` | For updates: changed fields only, `{field: {from, to}}` |
| `related jsonb` | Side-effect ids (transaction, ledger, batch) |
| `reason text` | Admin-entered reason when the flow has one |
| `source text` | Entry-point function or Edge name |
| `context jsonb` | IP, user agent, request id from request headers |
| `created_at timestamptz` | |

- Indexes: `(merchant_id, created_at desc)` and `(merchant_id, entity_type, entity_id, created_at desc)`.
- RLS: merchant isolation, read-only, gated by the view permission (open decision 2). A trigger blocks UPDATE and DELETE, except the approved personal-data scrub path (see redaction).
- Partition upkeep: a `pg_cron` job creates upcoming partitions and drops partitions past the retention period.

**Helper `fn_log_admin_action(p_action, p_entity_type, p_entity_id, p_payload jsonb, p_before jsonb DEFAULT NULL, p_after jsonb DEFAULT NULL, p_related jsonb DEFAULT '{}', p_reason text DEFAULT NULL, p_source text DEFAULT NULL)`:**
- **Actor:** uses the Phase 0 admin test. If the caller isn't an active admin of the merchant, it **returns without writing**. This is what makes shared functions safe. A service-role caller may pass a verified actor through a separate parameter, which is ignored for every other role.
- **Changes:** diffs `p_before` and `p_after`, ignoring `updated_at` and `created_at`.
- **Redaction:** drops secret keys (password, token, otp, secret, api_key).
- **Size cap:** payloads over the cap (e.g. 64 KB) are stored as a truncated marker plus counts. Bulk imports log one entry per import job, not per row.
- **Failure:** the insert runs in the caller's transaction. If it fails, the action fails and comes back as the standard error envelope.

**Tests (SQL, rolled back):**
- admin token → 1 row with payload and changes;
- member token on the same shared function → 0 rows;
- service key with no actor → 0 rows;
- validation error or exception → 0 rows.

## Phase 3 — Update the conventions *before* rollout

Do this now, so every function written from here on follows it.

**Where the call goes in the skeleton:** right before the success return, after the business logic.

```sql
  -- 4. BUSINESS LOGIC ... (capture v_before as to_jsonb(row) before an update; v_after after)

  -- 5. AUDIT (admin writes only; no-op for non-admin callers)
  PERFORM fn_log_admin_action('reward.update', 'reward', v_reward_id,
                              p_config, v_before, v_after);

  -- 6. RETURN fn_response_success(...)
```

**Files to change:**

| Repo | File | Change |
|---|---|---|
| `supabase-crm` | `requirements/BFF_Conventions.md` | §5 skeleton gets the AUDIT step. New section: action naming (`<entity>.<verb>`), what to pass as payload/before/after, batch and import rules, when a write is exempt. §7 checklist: "Admin write BFFs call `fn_log_admin_action`". |
| `supabase-crm` | `.cursor/rules/10-function-conventions.mdc` | "BFF Standard Structure" and "BFF Upsert Pattern" get the AUDIT step. |
| `supabase-crm` | `.cursor/rules/11-auth-conventions.mdc` | "Admin Identity": the audit helper resolves the actor. Service-key paths must forward the admin token or pass a verified actor. |
| `supabase-crm` | `requirements/REGISTRY_SUPABASE.md` | Register `admin_audit_log`, `fn_log_admin_action`, `fn_jsonb_diff`, and the upcoming read BFF. |
| `supabase-crm` | `requirements/Admin_Audit_Log.md` (new) | Canonical requirement: what is logged, the admin test, redaction, retention, the view permission. |
| `rocket-agent-plugins` | `plugins/rocket-eng/.cursor/rules/21-backend-functions.mdc` | BFF skeleton gets the AUDIT step. Add a line to run the coverage check before deploying admin write functions. |
| `rocket-agent-plugins` | `plugins/rocket-eng/.cursor/rules/30-fe-admin.mdc` | Admin writes go through BFF functions, never direct `.from(...).insert/update/delete`. |
| `loyalty-admin` | its rules entry (`AGENTS.md` / `.cursorrules`) | Same rule as `30-fe-admin`. |

Commit per repo. The pack commit goes only in `rocket-agent-plugins`.

## Phase 4 — Pilot on three flows that prove the hard cases

1. **Reward create/update:** admin-only master data. Check that payload and changes appear.
2. **Receipt approve/reject (Front Line):** admin-only action that creates transactions and ledger rows members also create. Expect one `receipt.approve` entry with those ids in `related`, and nothing for member earns.
3. **Admin create member:** logs `member.create`. Self-signup logs nothing.

**Checkpoint 2:** the user reads the pilot entries through SQL and confirms the wording and granularity of `action`, `payload`, and `changes`.

## Phase 5 — Roll out by domain

Instrument the rest of the inventory in batches: loyalty master data, config, member management, Front Line / approvals, CS admin, AMP admin. Each batch is one migration set plus the Phase 2 tests.

- **Admin direct table writes:** move each behind an existing BFF (reuse first) or a new one, then instrument it. This touches `loyalty-admin`.
- **Service-key Edge paths:** forward the admin token to the database calls. Where that's impossible, pass the verified actor after the Edge function has checked the admin token.

## Phase 6 — Keep it complete (two checks)

1. **Static check** (`supabase-crm/scripts/admin_audit_coverage.sql`): lists admin-facing functions (`bff_%`, `cs_bff_%`, excluding `bff_user_%`, plus anything the inventory marked shared) that write but never call `fn_log_admin_action` and aren't on the exempt list (each exemption has a reason). Run it before each backend deploy batch.
2. **Runtime check from the native request logs:** a weekly query of endpoints hit by admin tokens with write methods, compared against the functions that log. Any admin-called endpoint that doesn't log and isn't exempt is a gap, and so is any admin direct table write. This catches misnamed and new functions the static check misses.

## Phase 7 — Read side (admin app)

- `bff_admin_list_audit_log(p_filters jsonb, p_limit, p_cursor)`, filtered by entity type, entity id, admin, action, and date range, with keyset pagination on `created_at`.
- `loyalty-admin`: an **Activity Log** page, plus a **History** tab on each record's detail page that reuses the same BFF filtered by entity. A front-end map turns `action` into labels and renders `changes` as "field: from → to".

## Phase 8 — Retire the one-off logs and close out

- Move readers of `purchase_receipt_upload_review_audit` and `codes_deletion_log` to `admin_audit_log`, stop writing to the old tables, and drop them in a later, approved migration. Keep `user_removal_log`.
- Remove-user flow: scrub the removed member's personal data from `admin_audit_log` payloads (open decision 5).
- Product-doc closeout once: `requirements/Admin_Audit_Log.md`, the domain docs touched, and `CHANGELOG.md`.

---

## Open decisions (answer at Checkpoint 1)

1. **Retention:** 12 or 24 months (recommended 24), or forever with an archive?
2. **Who can view the log:** every admin, or only a role with a new `audit_log.view` permission (recommended)?
3. **Admin direct table writes:** move them all in v1 (recommended if there are few), or list them as known gaps?
4. **Sensitive reads** (customer export, viewing member personal data): log them too as `*.export` / `*.view`, or keep writes only for v1 (recommended)?
5. **Personal data in payloads:** scrub a member's personal data from audit payloads when that member is removed (recommended), or mask member personal data at write time?
6. **Superadmin actions:** out of scope for v1 (recommended), or included with actor type `superadmin`?

## Out of scope

- Member activity (already covered by ledgers).
- Raw request forensics: a log drain to S3 is an optional, separate ops task.
- Concurrency / locking.

## Kickoff prompt for the new thread

> Execute `supabase-crm/docs/ADMIN_AUDIT_LOG_PLAN.md`. Run Phase 0 and Phase 1, which are read-only. Produce `docs/ADMIN_WRITE_INVENTORY.md` and stop at Checkpoint 1. Don't change schema, functions, or conventions until I approve.
