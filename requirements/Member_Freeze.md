# Member Freeze

Admin can freeze or unfreeze a loyalty member. Frozen members may still sign in, but the member app shows a restricted state and self-service mutating RPCs are blocked in Postgres.

Owner surfaces: loyalty-admin (Customer 360 freeze toggle), loyalty-user (account-restricted gate)

## Concept

**Frozen flag** — `user_accounts.is_freeze` (boolean, default false). Distinct from soft delete (`deleted_at`) and `is_active`.

**Restricted session** — Summary/bootstrap still returns so the app can detect freeze; UI must not expose normal loyalty chrome.

**Self-service guard** — Redeem, spin wheel, referral apply, self mission claim, and similar paths return a generic **Please contact admin** message (`ACCOUNT_RESTRICTED`).

## Rules

- Only admins with Customer 360 **update** may toggle freeze (`bff_admin_set_member_freeze`).
- Toggle is merchant-scoped and skips deleted users; idempotent when state unchanged (`changed: false`).
- Integrations (purchase ingest, wallet chokepoints, admin currency adjust) are **not** blocked by freeze — restriction targets member-initiated mutations.
- Member messaging must not say “frozen”; use vague contact-admin copy.
- `resolve_target_user(NULL)` raises `ACCOUNT_RESTRICTED` for frozen callers (covers redeem and shared self-service entry).

## Journeys

### Admin journey

| Knob | Effect |
| --- | --- |
| Freeze / unfreeze | Sets `is_freeze` on member |

| Page | Owning repo | BFF / RPC |
| --- | --- | --- |
| Customer 360 | loyalty-admin | `bff_admin_get_member_360` (read `profile.is_freeze`), `bff_admin_set_member_freeze` |

1. Open **Customer 360** for the member — confirm current freeze state.
2. Freeze or unfreeze — success payload includes `previous_is_freeze`, `changed`, `admin_user_id`.

### Member journey

| Signal | Member sees |
| --- | --- |
| `get_user_summary().is_freeze === true` | Account-restricted gate (no normal app) |
| RPC `ACCOUNT_RESTRICTED` / PostgREST detail | Same gate via `loyalty:account-restricted` event |

1. App loads summary on bootstrap.
2. If frozen, **AccountRestrictedGate** blocks navigation with contact-admin messaging.
3. Any self-service mutation during session triggers the same restricted handling if freeze was applied mid-session.

## System

### Data model

| Column | Table | Role |
| --- | --- | --- |
| `is_freeze` | `user_accounts` | Frozen when `true` |

### Functions

| Function | Role |
| --- | --- |
| `bff_admin_get_member_360` | Exposes `data.profile.is_freeze` |
| `bff_admin_set_member_freeze(p_user_id, p_is_freeze)` | Admin write; permission `customer-360` / `update` |
| `get_user_summary()` | Top-level `is_freeze` for member app |
| `fn_is_user_frozen` / `fn_assert_user_not_frozen` | Server-side checks |
| `fn_account_restricted_error()` | Standard JSON error envelope |
| `bff_user_spin_wheel`, `bff_user_apply_referral`, `bff_claim_mission` (self) | Return restricted error when frozen |

### Known gaps

- Freeze does not revoke JWT immediately; relies on summary + RPC guards until token refresh.

## Related

- **Remove_User.md** — Soft delete vs freeze.
- **Tier.md** — Other `get_user_summary` fields alongside `is_freeze`.
