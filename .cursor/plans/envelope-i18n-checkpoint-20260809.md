# Envelope i18n checkpoint — 2026-08-09 (complete)

## Task
Scope C: optional `p_language text DEFAULT 'en'` on FE-facing jsonb RPCs with envelope `title`/`description` (th+en).

## Status
- **Inventory complete: 96/96 done** (`.cursor/plans/envelope-i18n-inventory-20260809.md`).
- Helpers: `fn_normalize_ui_language`; `fn_admin_envelope_message` (wrapper) → `fn_admin_envelope_message_core`.
- This session closed remaining upserts/getters (earn/currency/integration/leaderboard/activity/reward/form/amp/tier/signup/agent/etc.).
- `bff_get_agent_full` consolidated to one overload: `(p_agent_id uuid, p_mode text DEFAULT 'edit', p_language text DEFAULT 'en')` — use named args for `p_mode` vs language.
- Docs: CHANGELOG Scope C complete; REGISTRY lines patched for touched signatures.

## Open
None for inventory Scope C. Out of inventory (if desired later): other `api_*` / `cs_bff_*` envelope RPCs not listed in the inventory file.

## Next exact step
Smoke FE admin calls with omit lang (EN) and `p_language:='th'` on a few upserts (earn channel, currency config, reward). No further inventory migrations unless new RPCs are added.

## Critical context
- Project: `wkevmsedchftztoolkmi`
- After adding `p_language`, DROP old overload.
- Temp SQL: `.cursor/plans/tmp-envelope-i18n/`
