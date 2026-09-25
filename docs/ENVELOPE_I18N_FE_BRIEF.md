# Envelope i18n — FE / crm-api brief

**Status:** Backend redeem path live (2026-08-09). Broader BFF/`api_*` rollout in progress.

## Contract

- Member/admin apps paint backend `title` / `description` as-is.
- Send **one** language per request: `language` or RPC `p_language` = `th` | `en`.
- Omit → **English** (backward compatible).
- Do **not** expect a multi-language map in the response.

## Redeem (fixes personal-limit toast)

1. Member app: include UI language on `POST /redemptions` body, e.g. `{ ..., "language": "th" }`.
2. **crm-api** (Render): forward that field onto Inngest event `reward/redemption.requested` as `language` (same as `selected_variants`).
3. `inngest-reward-serve` already maps `language` → `redeem_reward_with_points.p_language`.
4. Realtime `redemption_failed` continues to pass RPC `title`/`description` through unchanged.

Without step 1–2, Thai UI merchants still see English toasts (default `en`).

## Other envelopes (in progress)

Any `bff_*` / `api_*` / member write RPC that returns `title`/`description` is being updated to accept `p_language text DEFAULT 'en'`. Inventory: `.cursor/plans/envelope-i18n-inventory-20260809.md`.

**Already live with `p_language`:** `bff_save_user_profile`, `bff_validate_signup_code`, `bff_user_update_birth_date`, `bff_get_user_missions` (plus redeem path above).
