# Central Outcome Dispatcher

Single chokepoint for granting campaign outcomes — points, tickets, reward, or earn_factor — with one audit log row per attempt.

Owner surfaces: system (Mission, Check-in, AMP, Spin Wheel, Referral, tier entry rewards, … call `fn_dispatch_outcome`)

## Concept

The **Central Outcome Dispatcher** is the one place a campaign feature sends a resolved grant to the member. Before it existed, mission, check-in, AMP, and spin wheel each had their own wallet/reward/earn-factor plumbing; they drifted (async vs sync currency, wrong redeem modes, inconsistent windows). Callers still own eligibility, condition matching, claim limits, and feature ledgers — the dispatcher only materializes the grant and records whether it succeeded.

**Outcome type** — One of four values the engine understands: points, tickets, reward (catalog push), earn_factor (temporary earn multiplier). Tag/persona AMP actions, event-promo discount shapes, and form/audience actions stay on their own paths.

**Source attribution** — Every attempt is labeled with a free-text source type (for example mission, checkin, amp, spin_wheel, referral, tier_entry_reward) plus an optional source id (campaign id, ledger id, workflow id). For points and tickets that label must be castable to the wallet source enum so the wallet chokepoint can classify the earn.

**Distribution log** — One row per attempt in `outcome_distribution_log`, success or failure, with cross-links to wallet ledger, redemption, or earn-factor user rows. New writes use this table; legacy mission-only distribution log is frozen as read-only history.

**Dedup key** — Optional caller-supplied key for idempotent grants. When omitted, the wallet layer may derive a dedup key from source + user + component; repeated grants from the same source to the same user need an explicit unique key per grant (completion id, spin id, etc.).

**Uniform return** — Callers read a single JSON shape: success flag, outcome type, convenience `transaction_id`, type-specific ids, `distribution_id`, optional `redemption_ids` for multi-quantity rewards, and error text on failure.

## Rules

- **Supported types only** — If `outcome_type` is not points, tickets, reward, or earn_factor, the dispatcher records failure and returns `{success:false}` (does not throw to the caller).
- **Never throws outward** — Exceptions inside the grant block are caught, written to the distribution log with `success=false` and `error_message`, and returned as `{success:false, error:…}`. The log insert itself is outside the catch block so every attempt leaves an audit row.
- **Caller owns limits** — The dispatcher does not enforce mission claim caps, check-in participation limits, referral limits, or tier exclusivity. Callers must gate before calling.
- **Caller owns feature ledgers** — Check-in ledger, mission completion flags, spin log, referral settlement, etc. remain the caller’s responsibility; the dispatcher writes only `outcome_distribution_log`.
- **Points** — Requires amount &gt; 0. Posts a synchronous wallet earn through the wallet chokepoint (base component, earn transaction type). Entity id is not used.
- **Tickets** — Requires amount &gt; 0 and a valid active ticket type id on the merchant. Posts through the wallet chokepoint with ticket currency and target entity = ticket type.
- **Reward** — Requires reward id and quantity &gt; 0. Uses direct redemption mode (zero points deducted; redemption row only). If redemption returns Shopify external id metadata, synchronous Shopify code sync runs inside the reward branch (see System › Flows).
- **Earn factor** — Requires earn factor id. Inserts a user earn-factor row with window end = now + (`metadata.window_days` default **30** days). No unique constraint on (user, earn factor) today — each call inserts a new row.
- **Wallet source type** — For points/tickets, `p_source_type` must cast to `wallet_transaction_source_type`. Unknown labels fail at cast time and surface as a failed dispatch.
- **Log source type** — Stored on the distribution log as provided, or `system` when null.
- **AMP non-outcomes** — assign_tag, remove_tag, assign_persona, submit_form, audience add/remove stay in `fn_execute_amp_action`, not here.

| Outcome | Condition | Result |
| --- | --- | --- |
| any | invalid / unknown type | Log row + `{success:false}` |
| points / tickets | amount ≤ 0 | Failure message per type |
| tickets | missing or inactive ticket type | Failure with ticket type id |
| reward | missing reward id or qty ≤ 0 | Failure |
| reward | redeem helper returns success false | Failure with underlying error |
| earn_factor | missing earn factor id | Failure |
| points / tickets | wallet dedup conflict | Failure (duplicate dedup key) |

Example (repeat grants): two milestone payouts for the same mission completion must pass different `p_dedup_key` values (e.g. include `outcome_id` or completion id); otherwise the second wallet post may hit dedup.

## Journeys

There is no admin or member UI for the dispatcher itself. Configuration and visibility live on each calling feature.

| Surface | Repo | Role |
| --- | --- | --- |
| Campaign engines | Supabase (PL/pgSQL) | Call `fn_dispatch_outcome` after local eligibility |
| Admin | loyalty-admin | Configures outcomes on Mission, Check-in, Spin Wheel, Tier entry rewards, Referral, AMP workflows — not on a “dispatcher” page |
| Member | loyalty-user / Front line | Sees wallet, coupons, and campaign results produced by callers after dispatch |

### Feature author journey

1. Implement or extend a campaign engine (mission claim, check-in, spin, referral settlement, tier upgrade hook, AMP action node, …).
2. After condition matching and limit checks, for each configured grant row resolve outcome type, amounts, entity ids, and trace metadata.
3. Call `fn_dispatch_outcome` with `p_source_type` / `p_source_id` matching the feature’s wallet label (must exist in wallet source enum when granting points or tickets).
4. Pass `p_dedup_key` when retries or multiple grants per source/user are possible.
5. On return, map `transaction_id` / `wallet_ledger_id` / `redemption_id` / `redemption_ids` / `earn_factor_user_id` / `distribution_id` into the feature ledger; treat `success=false` per product rules (mission logs warning and still completes claim; referral logs warning on failed outcome row).

### Admin journey

No dispatcher settings. Merchants configure grants on the owning screens (for example **Mission settings**, **Check-in settings**, **Spin wheel** editor, **Tier** entry rewards, **Referral** outcomes, AMP workflow actions). Audit for support uses `outcome_distribution_log` filtered by source type/id or member wallet/redemption history.

### Member journey

Members never invoke the dispatcher. They see points/tickets in wallet, rewards in My rewards, earn-factor badges from downstream UIs after a successful caller path.

## System

### Data model

**`outcome_type_enum`** — `points` | `tickets` | `reward` | `earn_factor`.

**`outcome_distribution_log`** — Central audit; one row per attempt.

| Column | Role |
| --- | --- |
| id | Primary key |
| user_id, merchant_id | Scope |
| source_type, source_id | Caller attribution (source_type free text; wallet cast when needed) |
| outcome_type, entity_id, amount | What was attempted |
| wallet_ledger_id | Set for points/tickets |
| redemption_id | Primary redemption for reward |
| earn_factor_user_id | Set for earn_factor |
| success, error_message | Outcome of attempt |
| distribution_metadata | Caller jsonb (streak_day, completion_id, party, window_days, …) |
| distributed_at | Timestamp |

Indexes: `(user_id, source_type, source_id)`, `(source_type, source_id)`, `(distributed_at)`. RLS off — writes via SECURITY DEFINER; reads via BFF/admin as needed.

**Frozen legacy** — `mission_log_outcome_distribution` is no longer written; historical rows remain queryable.

### Functions

| Function | Role |
| --- | --- |
| `fn_dispatch_outcome` | SECURITY DEFINER entry: validate branch, call primitive, insert log, return uniform jsonb |
| `chokepoint_post_wallet_transaction` | Points/tickets earn (sync) |
| `redeem_reward_with_points` (`p_mode := direct`) | Free reward grant |
| `fn_sync_shopify_codes_for_redeem_result` | Optional sync after direct reward when Shopify external id present |
| `INSERT earn_factor_user` | Earn-factor branch |

Signature (live): `fn_dispatch_outcome(p_user_id, p_merchant_id, p_outcome_type, p_entity_id, p_amount, p_source_type, p_source_id, p_metadata, p_dedup_key) → jsonb`.

Return keys: `success`, `outcome_type`, `transaction_id` (ledger or primary redemption), `wallet_ledger_id`, `redemption_id`, `redemption_ids` (array for multi-qty), `earn_factor_user_id`, `distribution_id`, `error`.

### Flows

**Sync dispatch path:** caller → `fn_dispatch_outcome` → branch (wallet / redeem / earn_factor insert) → optional Shopify code sync on reward → insert `outcome_distribution_log` → jsonb return. No Inngest/Kafka on this path.

**Per-type routing:**

- Points/tickets → wallet chokepoint with source enum from `p_source_type` (default cast uses `campaign` when null for wallet only).
- Reward → direct redeem; loop redemptions array; Shopify sync when redeem payload includes `external_id_shopify`.
- Earn_factor → insert with window from metadata (default 30 days).

### Callers (verified)

| Caller | `source_type` (typical) | Notes |
| --- | --- | --- |
| `fn_execute_amp_action` | `amp` | Five outcome actions delegate; workflow log and cost normalization unchanged; `push_reward` returns dispatcher jsonb |
| `fn_process_mission_outcomes` | `mission` | All outcome types sync; warning on dispatch failure does not block claim (prior async semantics) |
| `process_checkin` | `checkin` | Per-outcome dedup; ledger stores `transaction_id` (legacy rows may show `campaign`) |
| `fn_spin_wheel` | `spin_wheel` | Spend via wallet chokepoint separately; grants per segment outcome row |
| `fn_process_referral_rewards` | `referral` | Inviter/invitee rows; dedup `referral:{ledger_id}:{party}:{outcome_id}` |
| `fn_grant_tier_entry_rewards` | `tier_entry_reward` | On tier upgrade only; once per member per configured line |

**Not routed here:** event promo outcomes (discount/product shapes), AMP tag/persona/form/audience actions.

**New campaign pattern:** resolve eligibility → loop outcome rows → `fn_dispatch_outcome` with wallet-valid `p_source_type` → write feature ledger using return ids.

### External services

None on the dispatcher path. Mission currency no longer uses the orphaned `publish-currency-event` edge function (no DB caller remains).

### Known gaps

- **`publish-currency-event`** — Orphaned after mission sync collapse; deletion pending explicit ops decision.
- **Registry lag** — Tier entry reward tables/functions may be absent from `REGISTRY_SUPABASE.md` until regenerated; live DB has `tier_entry_rewards`, `tier_entry_reward_grants`, `fn_grant_tier_entry_rewards`.
- **Earn-factor re-grant semantics** — Plain insert; product may later need extend-vs-replace and a uniqueness constraint.
- **Event promo** — Separate claim/preview model; not a dispatcher candidate without new outcome types.

### Convergence (historical)

| Area | Before | After |
| --- | --- | --- |
| Mission currency | Async edge publish | Sync wallet chokepoint via dispatcher |
| Check-in reward | Buggy positional redeem (would burn points) | Direct mode via dispatcher |
| Check-in earn_factor | Hardcoded 7-day window + dead ON CONFLICT | 30-day default + configurable metadata |
| AMP / spin / referral / tier entry | Mixed bespoke grants | Delegate to `fn_dispatch_outcome` |

Plan and phase verification: `.cursor/plans/central-outcome-dispatcher-plan-20260628.md`.

## Related

- **Currency.md** — Wallet chokepoint for points/tickets.
- **Reward.md** — Direct redemption and Shopify code sync context.
- **Mission.md**, **Checkin.md**, **Spin_Wheel.md**, **Referral.md**, **Tier.md**, **AMP - Rule Based.md** — Callers, limits, and feature ledgers.
- **architecture/event-chokepoints.md** — Broader event and wallet pipeline.
