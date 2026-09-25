# Tier Program Config — Frontend Alignment Brief

**Status:** Backend live on `wkevmsedchftztoolkmi` (2026-07-26), including program-level `maintain_mode` (v6.1). Admin/member UIs still need to catch up.  
**Audience:** Frontend / product.  
**Tone:** Contract + journey impact. Exact screens, copy, and interaction patterns are a project decision — this doc does not prescribe UX.

Related: `.cursor/plans/tier-program-config-plan.md`, `.cursor/plans/tier-maintain-program-level-plan-20260726.md`, `requirements/Tier.md` (v6.1), `requirements/REGISTRY_SUPABASE.md` §Tier.

---

## 1. What changed (plain language)

Previously each tier carried its own clock and a separate maintain amount, plus stored ladder flags (`ranking`, `entry_tier`).

Now:

1. **The program owns the clock** — one config row per merchant + user type: metric, period, upgrade timing, and **`maintain_mode`**. Optional `program_start_date` is only a history cutover override (see below).
2. **Each tier owns only an upgrade threshold** (plus display / personas / optional burn **override**). Merchant-default points→discount burn lives on currency settings — see [`docs/BURN_RATE_FE_BRIEF.md`](BURN_RATE_FE_BRIEF.md). There is **no separate maintain amount**.
3. **Ladder order and free entry are derived** from upgrade amounts (null first, then ascending).
4. **Maintain is Smile-shaped at program level:**
   - `lifetime` — once achieved, never auto-downgraded; no maintain deadline.
   - `period` — at each period boundary, member must still meet **their current rung’s upgrade amount** (floor / null-amount rung is always exempt).

Until the admin UI stops sending retired fields, saves that still include `ranking`, `entry_tier`, a top-level `maintain` array, or per-condition window/metric fields will fail with `UNSUPPORTED_FIELDS`.

---

## 2. Surfaces this touches

| Surface | Why it matters |
|---|---|
| Admin — tier program / “clock” settings | Read/write API including `maintain_mode` (lifetime vs period). Required before tier thresholds can be saved. |
| Admin — tier list | Order by upgrade amount. No entry-tier badge boolean. No per-tier maintain column. |
| Admin — create / edit tier | Upgrade amount (+ display/personas/burn rate) only. Do not collect maintain amounts. |
| Admin — reorder / set entry tier | RPCs gone. Order = amounts; free entry = no upgrade amount. |
| Member — tier card / progress | No ranking keys. Under `lifetime`, maintain progress/deadline are null. Under `period`, maintain bar = current upgrade amount. |
| Member 360 / CS snapshot | No `tier_ranking`. Tolerate null maintain deadline as lifetime. |
| Onboarding / empty merchant | Block threshold save until program config exists. |

---

## 3. Concept model (for product + FE)

Three layers:

1. **Program config (primary)** — metric, period (`calendar_year` / `rolling`), upgrade timing, **`maintain_mode`** (`lifetime` / `period`).
2. **Program override (optional)** — `program_start_date`: ignore activity before this date. Does **not** replace the period; it only floors `window_start`.
3. **Tier definition** — name, personas, burn rate, display, **upgrade amount only**.
4. **Member instance** — current tier (nullable), upgrade progress, maintain deadline only when mode is `period`.

Derived:

- **Ladder position** — upgrade amount ASC NULLS FIRST on the persona-effective ladder.
- **Free entry** — rung with no upgrade amount. If none, member starts with no tier until they earn in.
- **Maintain bar** (period only) — current rung’s upgrade amount, not a second field.

### `program_start_date` — optional override (not a primary default)

Backend: `fn_tier_window` builds the normal window from `period_type`, then if start date is set:  
`window_start = GREATEST(normal_window_start, program_start_date)`.

| Value | Meaning |
|---|---|
| **`null` (default)** | No override. Count purely by calendar year / rolling config. |
| **A date** | Cutover: activity before that date does not count, even if the period window would include it. |

**FE guidance (product already pinned):**

- Do **not** default the field to “today” on first save — that would collapse a rolling window to “from today,” which is not the same as “use period config.”
- Prefer omitting it from the primary program settings surface, or place it under **advanced** (e.g. “Ignore activity before…”).
- Omit the key or send `null` on upsert unless the merchant explicitly sets a cutover.
- Existing merchants were backfilled with `null`; leave them alone unless they opt into a cutover.

---

## 4. Backend functions and how they relate to the journey

### Admin journey — set the program clock

| Function | Role |
|---|---|
| `bff_get_tier_program_config(p_user_type)` | Load config for JWT merchant. `p_user_type` optional. |
| `bff_upsert_tier_program_config(p_config jsonb)` | Create/update one `(merchant, user_type)` row. |

**`p_config` fields (write):**

| Field | Notes |
|---|---|
| `user_type` | `buyer` (default) or `seller` |
| `metric` | Required |
| `period_type` | `calendar_year` or `rolling` |
| `period_start_month` | Required for calendar year (1–12) |
| `rolling_months` | Required for rolling (1–36) |
| `upgrade_timing` | `immediate` or `end_of_month` |
| `maintain_mode` | `lifetime` or `period` (default `lifetime` if omitted) |
| `program_start_date` | Optional. Default **`null`** = no history cutover. Advanced override only — see §3. |

**Primary fields for a first-time / empty-state form:** `metric`, `period_type` (+ month or rolling months), `upgrade_timing`, `maintain_mode`.  
**Not primary:** `program_start_date` (advanced / omit unless set).

**Get `data[]` includes stored `maintain_mode` and `program_start_date`.** There is **no** `maintain_enabled` key (removed).

Stable error codes: `NO_MERCHANT_CONTEXT`, `INVALID_METRIC`, `INVALID_PERIOD_TYPE`, `INVALID_PERIOD_START_MONTH`, `INVALID_ROLLING_MONTHS`, `INVALID_UPGRADE_TIMING`, `INVALID_MAINTAIN_MODE`.

**Mode flip side-effects (backend, not FE):**

- `period → lifetime` — clears maintain deadlines for that track.
- `lifetime → period` — reseeds deadlines for members with a tier.

### Admin journey — define tiers

| Function | Role |
|---|---|
| `get_merchant_tiers(p_merchant_id)` | List tiers ordered by upgrade amount. |
| `get_tier_conditions_by_type(p_mode, p_tier_id)` | Form seed: **upgrade only** (no `maintain` key). `program_config` includes `maintain_mode`. |
| `get_tier_display_config()` | Display read. |
| `bff_upsert_tier_with_conditions(tier_data)` | Create/update tier + **upgrade** amounts. |
| `bff_upsert_tier_display(...)` | Icon/color/benefits/card. |
| `admin_delete_tier` | Delete path. |

**`get_merchant_tiers` conditions shape:** `{ id, amount, active_status, condition_type }` — expect `upgrade` only in practice.

**`bff_upsert_tier_with_conditions` accepts** name, user type, personas, burn rate, and `upgrade` array with amounts/ids.

**Rejected if present** (`UNSUPPORTED_FIELDS`):

- Top-level: `ranking`, `entry_tier`, **`maintain`**
- On upgrade conditions: `metric`, `window_type`, `window_months`, `window_start`, `frequency`, `window_start_field`, `upgrade_evaluation_timing`, `upgrade_evaluation_value`

Program config must exist before threshold upsert (`NO_PROGRAM_CONFIG`).

**Removed RPCs:** `reorder_tiers`, `set_entry_tier`.

### Member journey

| Function | Role |
|---|---|
| `get_user_tier_progress` / `get_user_summary` | Progress; maintain fields null under lifetime. |
| `evaluate_user_tier_status` / `process_tier_event` | Engine / event path — not typical FE calls. |

Tolerate `tier_id = null` on earn-in ladders. Under period, treat null maintain deadline as “not due / not applicable” carefully; under lifetime, null deadline is expected.

### CS / admin member views

| Function | Role |
|---|---|
| `bff_admin_get_member_360` | No `tier_ranking`. |
| `cs_bff_get_loyalty_snapshot_for_contact` | Same. |

---

## 5. Contract breakages to grep in FE

- `ranking`, `entry_tier`, `tier_ranking`, `maintain_enabled`
- `reorder_tiers`, `set_entry_tier`
- Per-tier `maintain` form arrays / maintain amount fields
- Condition fields: `window_type`, `window_months`, `frequency`, `calendar_month`, `anniversary`, etc.
- Assumptions every member always has a tier on signup

---

## 6. Open product decisions (not UX specs)

1. Where program config (including lifetime vs period) lives in IA.
2. How to express free entry (empty upgrade amount vs labeled control that only clears amount).
3. How to show ladder order (amount-sorted list is enough for the contract).
4. Empty state when `tier_id` is null.
5. Copy for lifetime vs period (Smile-style “keep forever” vs “re-qualify each period”).
6. Whether `program_start_date` is hidden entirely vs an advanced “Ignore activity before…” control (backend supports both; default remains null).

---

## 7. Smoke checks for FE after wiring

1. Load/save program config with `maintain_mode: 'lifetime'` and `'period'` → reload matches; no `maintain_enabled`.
2. First save without `program_start_date` (or with `null`) → stored null; window follows period only.
3. Optional: set `program_start_date` → activity before that date excluded from the window.
4. Create/edit tier with upgrade amount only → succeeds.
5. Send `maintain: [...]` or `ranking` → `UNSUPPORTED_FIELDS`.
6. `get_tier_conditions_by_type` has no `maintain` key.
7. Member UI: lifetime → no maintain countdown; period → maintain against current upgrade amount.
8. Tier list order = ascending upgrade amounts (null first).

---

## 8. Out of scope for FE

- SQL ladder views / daily maintain batch internals
- Merchant data cleanup / Ajinomoto free-entry product decision

Authority: live RPCs + `requirements/Tier.md` v6.1. This brief is a handoff, not a second schema source of truth.
