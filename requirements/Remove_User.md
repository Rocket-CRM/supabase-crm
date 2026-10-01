# Remove User (Admin)

**Version:** 1.0
**Last Updated:** April 2026
**Project:** Supabase CRM

## Overview

Admin-initiated soft deletion of an end-user (member) account. The function scrubs all personally identifiable information (PII), forfeits remaining balances, kills active sessions, and logs the action for audit. The user row is preserved (with `deleted_at` set) so that foreign key references from transaction history remain intact.

End-users do not use Supabase native auth — they authenticate via custom JWTs (LINE + Phone OTP through `bff-auth-complete`). No `auth.users` changes are involved.

---

## Database Changes

### New Column

| Table | Column | Type | Default | Purpose |
|---|---|---|---|---|
| `user_accounts` | `deleted_at` | `timestamptz` | `NULL` | Soft-delete marker |

**Index:** `idx_user_accounts_deleted_at` — partial index `WHERE deleted_at IS NOT NULL`

### New Enum Value

| Enum | Value | Purpose |
|---|---|---|
| `wallet_transaction_source_type` | `account_removal` | Source type for wallet forfeiture ledger entries |

### New Table: `user_removal_log`

| Column | Type | Nullable | Description |
|---|---|---|---|
| `id` | uuid PK | NO | Log entry ID |
| `merchant_id` | uuid FK → `merchant_master` | NO | Merchant context |
| `user_id` | uuid FK → `user_accounts` | NO | The removed user |
| `removed_by` | uuid FK → `admin_users` | NO | Admin who initiated |
| `reason` | text | NO | Reason for removal (default: 'Admin request') |
| `snapshot` | jsonb | NO | Pre-scrub PII snapshot (name, tel, email, balances) |
| `affected_summary` | jsonb | NO | Row counts of what was cleaned up per table |
| `created_at` | timestamptz | NO | When the removal happened |

RLS enabled, filtered by `merchant_id = get_current_merchant_id()`.

---

## Function: `admin_remove_user`

**Signature:** `admin_remove_user(p_user_id uuid, p_reason text DEFAULT 'Admin request') → jsonb`
**Security:** `SECURITY DEFINER`
**Caller:** Admin (validated via `is_admin()` + `get_current_merchant_id()`)

### Execution Steps

| Step | Action | Detail |
|---|---|---|
| 1 | **Authorize** | Verify caller is active admin, get `merchant_id` |
| 2 | **Validate** | User exists, belongs to merchant, `deleted_at IS NULL` |
| 3 | **Snapshot** | Capture pre-scrub PII + wallet balance for audit log |
| 4 | **Kill sessions** | DELETE from `refresh_tokens` and `user_sessions` |
| 5 | **Forfeit wallet** | If `points_balance > 0`: insert `wallet_ledger` burn entry (`source_type = 'account_removal'`, `component = 'adjustment'`), then set `points_balance = 0` |
| 6 | **Zero tickets** | Set `user_ticket_balances.balance = 0` where balance > 0 |
| 7 | **Revoke benefits** | Set `user_benefit.status = 'revoked'` where active |
| 8 | **Remove from audiences** | DELETE from `amp_audience_member` |
| 9 | **Scrub PII** | NULL out: `firstname`, `lastname`, `fullname`, `email`, `tel`, `line_id`, `birth_date`, `id_card`, `gender`, `image`, `external_user_id`. Clear `marketplace_external_ids → '{}'`. Set `deleted_at = now()` |
| 10 | **Scrub address** | DELETE from `user_address` |
| 11 | **Delete comm prefs** | DELETE from `user_communication_preferences` |
| 12 | **Log** | INSERT into `user_removal_log` (snapshot + affected summary) |
| 13 | **Return** | JSON with success, affected summary |

### Response Format

**Success:**
```json
{
  "success": true,
  "data": {
    "user_id": "uuid",
    "removed_at": "2026-04-02T10:00:00Z",
    "removed_by": "admin-uuid",
    "reason": "Customer requested account deletion",
    "affected": {
      "refresh_tokens_deleted": 2,
      "sessions_deleted": 1,
      "points_forfeited": 500,
      "ticket_balances_zeroed": 1,
      "benefits_revoked": 3,
      "audience_memberships_removed": 2,
      "addresses_deleted": 1,
      "comm_prefs_deleted": 1
    }
  }
}
```

**Error cases:**
- Merchant context missing → `Unauthorized`
- Caller not admin → `Forbidden`
- User not found → `Not Found`
- User already removed → `Conflict`

---

## Unique Constraint Handling

### Problem

Soft-deleting (keeping the row) would normally cause conflicts when a new user signs up with the same phone or email.

### Solution: PII Scrub Resolves It Naturally

| Constraint | What Happens After Removal |
|---|---|
| `UNIQUE (merchant_id, tel)` | `tel` is set to NULL. PostgreSQL allows multiple NULLs in unique constraints — no conflict. |
| `UNIQUE INDEX ON (merchant_id, lower(email)) WHERE email IS NOT NULL` | `email` is set to NULL. The partial index only covers `WHERE email IS NOT NULL`, so the nulled row is invisible to it. |

No constraint modifications are needed.

### Auth Flow Impact

`bff-auth-complete` looks up users by `tel` and/or `line_id`. After PII scrub:
- `tel` is NULL → no match on phone lookup
- `line_id` is NULL → no match on LINE lookup
- A new sign-up with the same phone/LINE creates a fresh `user_accounts` row without conflict

---

## Updated Edge Function: `bff-auth-complete`

**Problem found during testing:** After a user was removed (PII scrubbed), the user's app still had a valid JWT (up to 30 days). When the app called `bff-auth-complete` with the old JWT, the edge function found the user by ID, saw `tel`/`line_id` were null, and **wrote them back** from the request payload — undoing the PII scrub.

**Fix applied (v77):** All user lookups in `bff-auth-complete` now include `.is('deleted_at', null)`:

1. **JWT-based lookup** (access_token flow) — `eq('id', userId).is('deleted_at', null)`. Deleted user's JWT resolves to no match → falls through to tel/line_id lookup → creates new account.
2. **Tel lookup** — `eq('tel', tel).is('deleted_at', null)`. Deleted user's tel is null anyway, but this is defense-in-depth.
3. **LINE lookup** — `eq('line_id', line_user_id).is('deleted_at', null)`. Same.
4. **Shopify lookup** — `eq('id', user_id).is('deleted_at', null)`.
5. **All UPDATE queries** — `eq('id', ...).is('deleted_at', null)` on the WHERE clause, preventing writes to deleted rows.

**Net effect:** A deleted user's old JWT is now harmless. It can't find the deleted account, can't write PII back, and the flow naturally creates a new account when the user re-authenticates.

---

## Updated Functions

### `resolve_target_user`

**Change:** Added `deleted_at IS NOT NULL` check after user lookup. If the user account is marked as removed, raises exception: `'This account has been removed'`.

**Also:** When resolving **self** (`p_user_id IS NULL`) and `user_accounts.is_freeze`, raises `'Please contact admin'` (`DETAIL = ACCOUNT_RESTRICTED`). See `requirements/Member_Freeze.md`.

**Impact:** This function gates all end-user self-service calls (`get_user_wallet_summary`, `get_user_missions`, `bff_get_user_profile_template`, etc.). A single check here blocks all downstream functions from serving a removed user.

### `bff_admin_get_member_360`

**Changes:**
1. Added `deleted_at` to the profile object
2. Added `removal_info` to the response — when `deleted_at` is present, queries `user_removal_log` for the most recent removal entry and returns:

```json
{
  "removal_info": {
    "removed_by_admin_id": "uuid",
    "removed_by_name": "Admin Name",
    "reason": "Customer requested account deletion",
    "removed_at": "2026-04-02T10:00:00Z",
    "snapshot": { "fullname": "...", "tel": "...", "points_balance": 500 },
    "affected_summary": { "points_forfeited": 500, "..." }
  }
}
```

When the user is not removed, `removal_info` is `null`.

### `bff_admin_search_members`

**No change needed.** Searches by `fullname`, `email`, `tel`, `firstname`, `lastname`, `external_user_id`, `member_code`, and `id_card` — identity fields are nulled after removal (and `deleted_at` excludes the row), so deleted users naturally don't appear in results.

---

## What Is Preserved (Not Deleted)

Transaction history remains intact for accounting and audit. The FK still points to the `user_accounts` row, but the row contains no PII — only a UUID and `deleted_at`.

| Table | Purpose |
|---|---|
| `wallet_ledger` | Points transaction history (including the forfeiture entry) |
| `purchase_ledger` / `purchase_items_ledger` | Purchase history |
| `reward_redemptions_ledger` | Redemption history |
| `tier_change_ledger` | Tier change history |
| `mission_log_completion` | Mission completion history |
| `checkin_ledger` | Check-in history |
| `referral_ledger` | Referral records |
| `user_consent_ledger` | Consent audit trail |
| `form_submissions` | Form data |

---

## What Is Not In Scope

| Item | Reason |
|---|---|
| Restore/undo | Not required yet |
| `auth.users` deletion | End-users don't use Supabase native auth |
| Backup table cleanup | `user_wallet_backup_*` and `wallet_ledger_backup_*` are not touched |
| Bulk removal | Single-user only; bulk can be added later |

---

## End-User Experience After Removal

| Scenario | Behavior |
|---|---|
| App is open, JWT still valid (up to 24h) | All API calls fail via `resolve_target_user` → "This account has been removed" |
| JWT expires, tries to refresh | Refresh token deleted → refresh fails → forced logout |
| Tries to log in with same phone/LINE | `bff-auth-complete` creates a **new** account — fresh start |

No end-user frontend changes required.

---

## Admin Frontend Requirements

### 1. Remove Member Action
- Location: Member 360 page
- Destructive-style button ("Remove Member")
- Confirmation dialog with required **reason** text input
- Calls `admin_remove_user(p_user_id, p_reason)` via RPC
- Shows success summary (affected counts)

### 2. Removed User State
- When `profile.deleted_at` is present in Member 360 response:
  - Show "This member has been removed" banner
  - Display removal info (who, when, why) from `removal_info`
  - Disable all action buttons (adjust points, change tier, etc.)

### 3. Removal Log Viewer (Optional)
- List view of `user_removal_log` for the merchant
- Shows: who was removed (from snapshot), by whom, when, reason
- Useful for audit and compliance review

---

## API Reference

### RPC: `admin_remove_user`

```
POST /rest/v1/rpc/admin_remove_user
Authorization: Bearer <admin-jwt>
Content-Type: application/json

{
  "p_user_id": "uuid-of-user-to-remove",
  "p_reason": "Customer requested account deletion"
}
```

### Member 360 Response Changes

New fields in `bff_admin_get_member_360` response:

```
data.profile.deleted_at    → timestamptz | null
data.removal_info          → object | null
data.removal_info.removed_by_admin_id → uuid
data.removal_info.removed_by_name     → text
data.removal_info.reason              → text
data.removal_info.removed_at          → timestamptz
data.removal_info.snapshot            → jsonb
data.removal_info.affected_summary    → jsonb
```
