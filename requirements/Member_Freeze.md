# Member Freeze

Admin can freeze or unfreeze a loyalty member. Frozen members may still sign in, but the member app shows a restricted state and self-service mutating RPCs are blocked in Postgres.

Owner surfaces: loyalty-admin (Customer 360 freeze toggle, Front Line read-only state), loyalty-user (account-restricted gate)

## Concept

Freeze is the fraud brake on one member. Typical cases: a member earns marketplace points, burns them all, then refunds the order so the points can no longer be clawed back; or a member uploads fake receipts. Freezing stops the member from spending or playing on their own, while head office keeps full control of the record. It is reversible, unlike removal.

- **Frozen flag** — on/off per member. It is separate from removal (soft delete) and from inactive.
- **Restricted session** — a frozen member can still sign in. The app detects the freeze and shows only a contact-admin screen, never the normal loyalty app.
- **Self-service guard** — every member-initiated mutation (redeem, spin, referral, mission claim, …) is refused server-side with a generic *Please contact admin*.
- **Admin override** — admins and integrations can still post to a frozen member. Front Line deliberately makes the counter read-only for frozen members.

## Rules

- Only admins with Customer 360 **update** may toggle freeze (`bff_admin_set_member_freeze`).
- Toggle is merchant-scoped and skips deleted users; idempotent when state unchanged (`changed: false`).
- Integrations (purchase ingest, wallet chokepoints, admin currency adjust) are **not** blocked by freeze — restriction targets member-initiated mutations.
- Member messaging must not say “frozen”; use vague contact-admin copy.
- `resolve_target_user(NULL)` raises `ACCOUNT_RESTRICTED` for frozen callers (covers redeem and shared self-service entry). Admin calls that pass an explicit target user are not blocked.
- Customer 360 keeps all admin actions available on a frozen member (adjust, tier, edit, unfreeze).
- Front Line shows a frozen warning and disables every tab action and Edit Profile for a frozen member; reward-code lookup still shows the reward with a frozen warning. This is a UI rule only — the Front Line RPCs do not check freeze.
- Open API and integration member lookups report a frozen member as status `suspended` (frozen wins over inactive).
- No reason is captured on freeze or unfreeze.

## Journeys

### Admin journey

| Knob | Effect |
| --- | --- |
| Freeze / unfreeze | Sets `is_freeze` on member |

| Page | Owning repo | BFF / RPC |
| --- | --- | --- |
| Customer 360 | loyalty-admin | `bff_admin_get_member_360` (read `profile.is_freeze`), `bff_admin_set_member_freeze` |
| Front Line member page | loyalty-admin | `bff_admin_get_frontline_member` (read `profile.is_freeze`) |

1. Open **Customer 360** for the member. A *Frozen* badge in the header shows the current state.
2. **Freeze member** (or **Unfreeze member**) → confirm dialog (*will be frozen; you can unfreeze them later*) → toast, and the badge updates. The success payload includes `previous_is_freeze`, `changed`, `admin_user_id`.
3. At the counter, **Front Line** shows the frozen banner and badge; the tabs stay visible but read-only.

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
| `resolve_target_user` | Self-service entry; raises `ACCOUNT_RESTRICTED` when caller is frozen |
| `fn_open_api_member_status` | Maps frozen → `suspended` for Open API / integration snapshots |

### Known gaps

- Freeze does not revoke JWT immediately; relies on summary + RPC guards until token refresh.
- The Front Line read-only state for frozen members is enforced only in the UI.

## Related

- **Remove_User.md** — Soft delete vs freeze.
- **Frontline_Admin_Actions.md** — Customer 360 and Front Line pages that surface and respect freeze.
- **Tier.md** — Other `get_user_summary` fields alongside `is_freeze`.
