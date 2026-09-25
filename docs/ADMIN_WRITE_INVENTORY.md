# Admin write inventory

Status: **Checkpoint 1 complete** (2026-09-23). Rollout instrumented on live Supabase; re-run `scripts/admin_audit_coverage.sql` before backend deploys.

## Phase 0 — Admin test & blind spots

| Check | Result |
|-------|--------|
| Admin JWT | Issuer `…/auth/v1`, session present; member JWT issuer `supabase` |
| Actor resolution | `fn_resolve_admin_audit_actor` + `fn_log_admin_action` |
| Service role | No actor unless `p_verified_actor_admin_id` is set after admin check |
| Index | `admin_users(auth_user_id)` (verify in migrations) |

**Service-key / Edge blind spots (document, not auto-fixed):** receipt OCR pipelines, Inngest/Render jobs, and any path that mutates without forwarding the admin JWT must pass `p_verified_actor_admin_id` or be moved behind an admin BFF.

## Phase 1 — Classification summary

| Source | Finding |
|--------|---------|
| A. Request logs | Admin writes concentrate on `/rest/v1/rpc/bff_*` and `/rest/v1/rpc/bff_admin_*`; use weekly log export vs `scripts/admin_audit_runtime_gap.sql` |
| B. `loyalty-admin` | Hundreds of `.rpc('bff_*')` call sites under `src/`; no production member-table writes expected |
| C. Database | 189 writer overloads on `bff_%` / `cs_bff_%` (excluding `bff_user_%`); **0 missing** audit hooks after bulk patch v4–v6 |

### Pilot rows (explicit payload / diff)

| Path | Kind | Class | Action | Entity |
|------|------|-------|--------|--------|
| `bff_upsert_reward_with_conditions_and_limits` | rpc | admin | `reward.create` / `reward.update` | reward |
| `bff_approve_receipt_upload` | rpc | admin | `receipt.approve` / `receipt.reject` | receipt |
| `bff_admin_create_member` (canonical) | rpc | admin | `member.create` | member |

### Bulk rollout

- Most writers use `fn_log_admin_bff_write` + `fn_admin_audit_infer_action` (payload `{}` until enriched per domain).
- Exempt list: `admin_audit_log_exempt` (`fn_log_admin_action`, `fn_log_admin_bff_write`, `bff_admin_list_audit_log`).

## Decisions (locked)

1. Retention: **24 months** (partition cron).
2. View: **`audit_log.read`** → FE resource `audit_log` / menu Activity log.
3. Direct table writes: **move behind BFF** when found; flag in inventory.
4. Sensitive reads: **writes only** v1.
5. PII: **`fn_scrub_admin_audit_log_for_member`** on `admin_remove_user`.
6. Superadmin: **out of scope** v1.

## Phase 8 — Legacy logs

| Table | Status |
|-------|--------|
| `purchase_receipt_upload_review_audit` | Cancel path migrated to `admin_audit_log`; approve/reject via pilot; table retained until readers moved |
| `codes_deletion_log` | Readers not migrated in this pass — switch when promo-code UI needs history |
| `user_removal_log` | **Keep** (compliance snapshot) |

## Maintenance

- Static: `scripts/admin_audit_coverage.sql`
- Runtime: `scripts/admin_audit_runtime_gap.sql` + admin-token RPC log diff
