# Check-in

Attendance campaigns that reward members for returning on a cadence. Merchants configure evaluation shape, eligibility, caps, and outcomes; members record attendance in the app; the system appends an immutable ledger row and dispatches every matched outcome through the central outcome dispatcher.

Owner surfaces: loyalty-admin, loyalty-user

## Concept

Check-in is an **attendance mechanic**: a merchant runs one or more **campaigns** at once (for example a daily habit loop and a month-long sprint). Each campaign defines how **progress** is measured, who may participate, when check-in is allowed, and what **outcomes** fire on which **triggers**. The member-facing loop is unchanged at a high level: open status → tap check-in → see progress and grants.

**Check-in campaign** — Named program with frequency, condition shape, optional time and campaign windows, eligibility filters, participation caps, and a set of outcomes.

**Frequency type** — `daily` or `weekly`. Controls **streak continuity** for consecutive campaigns only (not how calendar “today” is labeled on the ledger).

**Condition type** — How progress is evaluated: `consecutive` (classic streak), `fixed_period_count` (X check-ins between fixed dates), `rolling_period_count` (X check-ins in any trailing window of N days), or `qr_collection` (collect every active QR code of the campaign).

**QR collection** — The treasure-hunt condition type. A campaign owns a set of **QR codes** (generated in bulk, each labelled, each encoding a member-app URL). The member scans a code with their phone camera; the scan is a check-in that records which code it claimed. One code counts once per member. The campaign is **complete** for that member when they have collected every *active* code. There is no join step — progress begins at the first scan.

**Streak** — For `consecutive` campaigns: consecutive check-ins without a gap. Daily: gap longer than one calendar day resets. Weekly: gap longer than seven days resets. Derived from the ledger at read/eval time, not a separate streak store.

**Period count** — For `fixed_period_count` or `rolling_period_count`: tally of check-ins inside the configured period or rolling window, computed from the ledger when processing and when showing status.

**Outcome** — One configured grant row on a campaign (points, tickets, free reward, or earn factor) with a trigger and amount.

**Trigger type** — When an outcome is eligible to fire: `every_checkin` (each valid check-in), `streak_milestone` (streak day within a configured range), `period_milestone` (period count equals target; **fire-once per member** per outcome, enforced via prior ledger matches), or `collection_complete` (the scan that collects the last active QR code; fire-once per member).

**Trigger ↔ condition pairing** — A trigger only fires for compatible condition types, enforced in the admin form and in `bff_upsert_checkin`:

| Condition type | Allowed triggers |
| --- | --- |
| `consecutive` | `every_checkin`, `streak_milestone` |
| `fixed_period_count`, `rolling_period_count` | `every_checkin`, `period_milestone` |
| `qr_collection` | `every_checkin`, `collection_complete` |

**QR token** — A code's scanned token, stored on `checkin_qr_codes`. The printed code encodes `{member host}/?page=checkin&token={token}`, built by `fn_member_app_deep_link` (kind `checkin_qr`). It is a **bearer token**: the table carries no member-facing RLS policy and no `anon`/`authenticated` grants, so a member can never read an uncollected token. Uncollected codes are exposed to members as a count only.

**Outcome type** — What the member receives: points, tickets (needs ticket type), reward (free redemption), or earn factor (temporary multiplier; default 30-day window via dispatcher).

**Eligibility** — Campaign-level filters on tier, persona, tags (member must have any listed tag), and birth month. Empty or unset means unrestricted.

**Participation limit** — Per-campaign cap stored in the shared participation-limits facility with entity type check-in; scope `user` (per member) or `total` (campaign-wide), over day/week/month/year/all_time (optional absolute window overrides).

**Time window** — Optional daily hours when check-in is allowed, evaluated in the campaign timezone (supports overnight windows when end time is before start time).

**Campaign window** — Optional start/end timestamps when the campaign is active; outside the range the campaign behaves as unavailable.

**Attendance ledger** — Immutable row per check-in: user, campaign, date, streak day at write time, and a JSON list of every outcome dispatch attempt (success or failure). All streak, period, milestone, and history math reads this ledger.

**Require condition match** — When enabled, a check-in is rejected if no outcome would match; when disabled, the check-in can succeed with an empty grant list while still advancing progress where rules allow.

**Per-outcome eligibility (planned)** — Today eligibility is campaign-level only; tier-differentiated grants on one campaign require separate campaigns or this future capability.

Progress is **ledger-derived**. Outcomes are **multi-dispatch**: each match is sent independently through the same dispatcher primitive used by missions, AMP, and referral.

## Rules

- If the campaign is inactive, outside its campaign window, or unknown → check-in fails with a not-found/inactive style error; status reads treat it as unavailable.
- If a daily time window is enabled and current time in the campaign timezone is outside the window → check-in fails with an outside-window error (including window bounds in the response). Overnight windows (start time after end time) use union-of-ranges semantics.
- If tier, persona, tag, or birth-month filters are set and the member does not satisfy them → check-in fails with the corresponding requirement error. Empty filters → all members pass.
- If a participation limit applies and the member or campaign has reached the cap in the configured window → check-in fails with a limit error (includes used/remaining where applicable).
- By default, **multiple check-ins on the same calendar day are allowed**; each creates its own ledger row and can fire `every_checkin` outcomes again. Streak does not advance again on the same date; same-day `streak_milestone` does not re-fire. To enforce one check-in per day, set a participation limit (scope user, count 1, time unit day).
- For `consecutive` + daily frequency: if the last ledger date is yesterday → streak increments; otherwise new streak day is 1. For `consecutive` + weekly: if last check-in within seven days → streak increments; else reset to 1.
- For `fixed_period_count`: period count is check-ins with dates in `[period_start, period_end]`. For `rolling_period_count`: period count is check-ins in the trailing `rolling_window_days` ending now.
- `every_checkin` outcomes match on every valid check-in. `streak_milestone` matches when new streak day is between configured start and end (null end = unbounded high). `period_milestone` matches when period count equals target **and** no prior ledger row for that member already recorded that outcome id in matched grants.
- Multiple outcomes may match one check-in; each dispatches through the central dispatcher with a per-outcome dedup key so duplicate currency grants do not collide. One outcome failing does not block others; failures are recorded on the ledger entry with success false.
- If **require condition match** is true and zero outcomes match → check-in is rejected (no ledger row). If false → check-in proceeds; matched list may be empty while streak/period still advance per condition type.
- Time-window **next deadline** in status responses is null when no daily window is configured; when configured, daily campaigns use next day’s window end in campaign timezone, weekly uses last check-in plus seven days at window end (via shared streak helper).
- Outcome dispatch for rewards uses direct redemption (zero points); earn factor uses dispatcher default window unless metadata overrides window days.
- Admin reversal of a ledger row is supported via admin BFF; corrected ledger data is reflected on the next status read without a separate streak cache.
- **QR collection** requires a scanned token; a missing, unknown, cross-campaign, or deactivated token fails with its own error. A token that matches a code the member already collected fails as already-collected (also enforced by a unique index on member + code, so concurrent double scans are rejected).
- **Completion** is evaluated after the ledger row is written, by comparing distinct collected codes with the count of *active* codes. The completing row is stamped `collection_completed_at`; that stamp is both the reporting fact and the fire-once guard for `collection_complete`.
- A member who completed **stays completed** when the merchant adds codes later: a later scan pays `every_checkin` but does not re-stamp or re-fire `collection_complete`.
- Concurrent scans of two different codes by the same member are serialised by a per-member advisory lock, so the pair cannot each read the same pre-completion count and leave the member at N of N with completion unfired.
- Reversing the completing ledger row removes the stamp with it, so the next completion-scoring scan fires `collection_complete` again (once).
- Scanned codes can be **deactivated** but not deleted; unscanned codes can be deleted. Deactivating a code a member is missing leaves them permanently short of completion, because completion is only evaluated on a scan.
- Participation limits apply to QR scans exactly as to other check-ins, so a per-user daily limit of 1 means one code per day.
- Static QR codes can be photographed and shared; the campaign's daily time window is the on-site control. Rotating or anti-sharing codes are not supported.

## Journeys

### Admin journey

| Page | Owning repo | BFF / RPC |
| --- | --- | --- |
| Check-in list | loyalty-admin | `bff_list_checkins` |
| Check-in settings (create/edit) | loyalty-admin | `bff_get_checkin_details` (load), `bff_upsert_checkin` (save) |
| Outcomes (embedded in settings) | loyalty-admin | `outcomes[]` on upsert (full replace) |
| QR codes (qr_collection only) | loyalty-admin | `bff_list_checkin_qr_codes`, `bff_generate_checkin_qr_codes`, `bff_update_checkin_qr_code`, `bff_delete_checkin_qr_code` |
| QR print sheet | loyalty-admin | server-rendered from `bff_list_checkin_qr_codes` (Save as PDF is the download-all path) |
| Front line — member Check-in tab | loyalty-admin | `get_user_checkin_status`, `process_checkin` (staff check-in on behalf of member) |
| Front line — recent check-ins / reverse | loyalty-admin | `bff_admin_get_checkin_history`, `bff_reverse_checkin` |

| Setting | Effect on behaviour |
| --- | --- |
| Name / description | Display labels for admin and member surfaces |
| Frequency type | Daily vs weekly streak continuity rules |
| Condition type | Consecutive vs fixed-period vs rolling-period vs QR collection evaluation |
| Period start / end / target count | Fixed-period count target and window (not used by QR collection) |
| Rolling window days / target count | Rolling-period window and target (not used by QR collection) |
| Campaign image | Shown on the member event page |
| Timezone | Campaign window and daily time-window evaluation |
| Enable time window + start/end times | Restricts check-in to hours; supports overnight span |
| Campaign window start/end | Active range for the campaign |
| Max streak days | Upper bound on streak counter |
| Active status | Master on/off |
| Eligibility arrays | Tier, persona, tags, birth month gates |
| Require condition match | Reject check-in when no outcome would match |
| Outcome rows | Type, amount, entity, trigger, milestone range/target, priority, milestone UI flag |
| Participation limits | Per-user or campaign-wide caps by time unit (optional absolute window) |

1. Open **Check-in list** and start **Add check-in** (or edit an existing row).
2. Set campaign identity, frequency, and condition type; fill period or rolling fields when not consecutive.
3. Set timezone and optional daily time window and campaign date range.
4. Set eligibility filters or leave empty for all members.
5. Add participation limits if caps are needed (including one-per-day if desired).
6. Open **Outcomes**, add rows: pick trigger from the ones valid for the condition type (`every_checkin`, `streak_milestone`, `period_milestone`, `collection_complete`), outcome type, amount, and entity when required; set streak range or period target; set priority and milestone flag; save (upsert replaces all outcomes and limits on each save).
7. For a **QR code collection** campaign, save first, then open **Manage QR codes** on the campaign to generate, label, download, print, deactivate, or delete codes. Generate takes 1–100 at a time; each code gets its own label and a QR image built from the member-app URL.
8. On **Front line**, open the member **Check-in** tab to run check-in or inspect status; use **Recent check-ins** to view history and **Reverse check-in** on a ledger id when correcting attendance. QR campaigns show collected/completed rather than streak, and the staff check-in button is hidden because staff have no code to scan.

Common pitfalls: require condition match with no matching outcomes blocks all check-ins; inactive or ineligible **reward** on a reward outcome dispatches as failed but check-in still records; unintended overnight window when end time is before start time; period milestone target already passed in ledger will not fire again for that member.

### Member journey

| Page / surface | Owning repo | BFF / RPC |
| --- | --- | --- |
| Check-in events list (`/checkin`) | loyalty-user | `bff_user_list_checkin_events` |
| Check-in event detail (`/checkin/[id]`) | loyalty-user | `bff_user_get_checkin_event` |
| Scan collect (camera + `?page=checkin&token=`) | loyalty-user | `bff_user_collect_checkin_qr` |
| Activity history (check-in filter labels) | loyalty-user | Wallet/history read path |
| Check-in status / action (staff) | loyalty-admin — Front line | `get_user_checkin_status`, `process_checkin` |

Entry point: the **earn channel**. A channel configured with `earn_method = 'checkin'` is a passthrough — tapping it leaves the earn sheet and opens `/checkin`, the same mechanism missions use. No new nav item is required.

1. Member opens the check-in surface from the earn channel. The list shows active, in-window, eligible events with a progress bar and collected/total.
2. Member opens an event: image, description, campaign window, the codes they have already collected (labels and times), and the outcomes split into "for each code" and "when all codes are collected".
3. Member taps **Scan collect now**, or scans a printed code with the phone camera (which opens `?page=checkin&token=…`).
4. Logged out, the scanned URL lands on the event preview; the token is kept across login and the collect resumes automatically.
5. On success the app shows the granted outcomes and progress, driven entirely by the collect response. The completing scan shows the completion state with both the per-code and completion grants.
6. Errors (already collected, inactive code, outside hours, limit, not eligible) are shown with the localized title/description returned by the RPC.

| Error (member-visible) | Typical cause |
| --- | --- |
| Check-in campaign not found or inactive | Off, outside campaign window, or missing |
| Outside check-in window | Outside configured daily hours |
| Tier / Persona / Tag / Birthday month requirement not met | Eligibility filter |
| Personal / Campaign participation limit reached | Cap exhausted |
| Forbidden | Admin frontline check-in without create/update permission |
| Invalid QR code | Token does not belong to an active code in this campaign |
| QR code inactive | The code was deactivated after printing |
| QR code already collected | Member already scanned this code |
| QR code required | A `qr_collection` campaign was called without a token |

## System

### Data model

| Artifact | Role |
| --- | --- |
| `checkin` | Campaign header: frequency, condition config, windows, eligibility, require condition match, image, active flag |
| `checkin_outcomes` | One row per configured outcome and trigger; cascades on campaign delete |
| `checkin_qr_codes` | QR codes belonging to a `qr_collection` campaign: token, label, ordering, active flag. No member-facing policy (bearer tokens) |
| `checkin_ledger` | Immutable attendance and matched-outcome audit per check-in; carries `qr_code_id` (which code this scan claimed) and `collection_completed_at` (the scan that finished the set) |
| `transaction_limits` | Participation caps where entity type is check-in and entity id is campaign id |
| `v_checkin_collection_progress` | Reporting view: `joined_at` (first scan), `completed_at` (stamp), `codes_collected` per member and campaign |

Indexes on the ledger favour user+campaign+date/time ordering for streak and period aggregation. QR collection adds a partial unique index on `(user_id, qr_code_id)` so one code counts once per member, plus partial indexes for completion lookups and per-code scan counts.

Members do not write `checkin_ledger` directly: the insert policy was removed and `INSERT`/`UPDATE`/`DELETE` revoked from `anon` and `authenticated`. Both writers (`process_checkin`, `bff_reverse_checkin`) are `SECURITY DEFINER`.

### Functions

| Function | Role |
| --- | --- |
| `process_checkin` | Member write path: validate campaign, window, eligibility, limits; compute streak/period; match outcomes; dispatch; insert ledger. Accepts an optional `p_qr_token` for `qr_collection`; requires the caller to be the member themselves unless they are an admin |
| `get_user_checkin_status` | Member read path: campaign card, progress, milestones preview, today flag, deadlines, and QR collection progress (`joined_at`, `completed_at`, collected/total) |
| `fn_compute_checkin_streak` | Shared streak/longest/total/last-date/deadline math from ledger |
| `fn_checkin_eligibility` | Shared eligibility gate (tier, persona, tags, birth month); used by `process_checkin` and the member event list |
| `bff_upsert_checkin` | Admin create/update campaign with full-replace outcomes and limits (merchant from JWT); enforces the trigger ↔ condition pairing and refuses a condition-type change once ledger rows exist |
| `bff_get_checkin_details` | Admin load template (`new`) or campaign + children (`edit`) |
| `bff_list_checkins` | Admin list with aggregate stats per campaign, including participant and completion counts for QR campaigns |
| `bff_admin_get_checkin_history` | Admin member attendance history, including which QR code each scan collected |
| `bff_reverse_checkin` | Admin reversal of a ledger row (also removes the QR completion stamp) |
| `bff_generate_checkin_qr_codes` | Generates N codes for a QR campaign (12-char tokens from an unambiguous charset, retrying on collision) |
| `bff_list_checkin_qr_codes` | Admin QR list with per-code scan counts, `scan_url`, and campaign participant/completion totals |
| `bff_update_checkin_qr_code` | Renames or activates/deactivates one code |
| `bff_delete_checkin_qr_code` | Deletes an unscanned code; refuses once scanned |
| `bff_user_list_checkin_events` | Member list of active, in-window, eligible QR campaigns with progress |
| `bff_user_get_checkin_event` | Member event detail by id or by scanned token; never returns a token for an uncollected code |
| `bff_user_collect_checkin_qr` | The only member write: resolves the member from the session, delegates to `process_checkin`, returns the granted outcomes and completion state |
| `fn_member_app_deep_link` | Shared member-app URL builder; kind `checkin_qr` returns `?page=checkin&token=…` |
| `fn_dispatch_outcome` | Central grant primitive for every matched outcome |

Triggers: deleting a campaign invalidates earn-channel display cache for check-in sources; outcome rows maintain updated-at.

### Flows

**Check-in (sync):** resolve campaign → optional time-of-day gate → load member and tags → eligibility → participation limits → compute streak and period from ledger → evaluate outcome triggers → for each match call dispatcher with source type check-in and per-outcome dedup key → insert ledger with matched outcome payloads → return streak, counts, grants, next deadline.

**Status (sync):** load campaign → run shared streak helper and period tally → build upcoming milestones for UI → return today-checked derived from ledger date. For `qr_collection`, also return `joined_at` (first scan), `completed_at` (completion stamp), and collected/total counts.

**QR collect (sync):** take a per-member advisory lock → resolve the token to a code in this campaign → reject unknown/inactive/already-collected → run the standard check-in path → count distinct collected codes against active codes → if the set is now complete and no prior row carries a stamp, stamp `collection_completed_at` → evaluate outcomes (including `collection_complete`) → return the granted list and completion state.

**Admin QR generation:** lock the campaign row → read the highest sort order → insert N codes with sequential labels, retrying the token on collision → return generated and active totals.

**Admin save:** validate required fields → upsert header → delete and reinsert all outcomes and check-in limits from payload (no orphan children).

**Outcome dispatch:** points and tickets via wallet chokepoint; reward via direct redemption; earn factor via user earn-factor row; each attempt logs to outcome distribution log.

Display on the Earn page uses earn-channel source availability for check-in channels (see Earn Channel doc).

### External services

No dedicated Render/Inngest service for check-in; grants and wallet updates run inside the database dispatcher path.

### Known gaps

- **Reward-outcome dedup** — `fn_dispatch_outcome` dedups `points` and `tickets` through the wallet ledger's unique dedup key, but the `reward` and `earn_factor` branches carry no dedup. This is platform-wide (missions, spin wheel, AMP dispatch the same way), not check-in-specific; the ledger-level once-per-member guards are what prevent a second grant today.
- **QR completion when codes are removed after launch** — completion is evaluated only on a scan. If a merchant deactivates the last code a member is missing, that member reaches X of X with nothing left to scan and never completes. The admin deactivate confirmation warns about this.
- **Static QR codes can be shared** — a printed code can be photographed and sent to someone who is not on site. Accepted for v1; rotating or per-member codes are not supported.
- **`match_outcomes` guard depends on stable outcome ids** — `bff_upsert_checkin` replaces all outcome rows on save; the once-per-member guards read outcome ids out of past ledger rows, so an outcome whose id changes loses its guard. The admin form echoes ids back for loaded rows, which keeps them stable in practice.
- **Require condition match** under heavy multi-outcome use may need product refinement (today: any match proceeds; zero matches reject when flag is true). It is hidden for `qr_collection`, whose outcomes are always configured.
- **Time-of-day window** applies to all condition types; confirm merchants want hours gating on fixed/rolling count campaigns.
- **`checkin_outcomes` table policy** — its `FOR ALL` policy keys on `get_current_merchant_id()`, which also resolves for member JWTs, so it is member-writable at the table level. Pre-existing and unrelated to QR collection; the QR token table deliberately does **not** follow that pattern.
- Residual **per-outcome eligibility** product design tracked as planned in Concept.

## Related

- **Central Outcome Dispatcher** — All check-in grants use `fn_dispatch_outcome`; see `Central_Outcome_Dispatcher.md`.
- **Currency** — Points and tickets post through wallet chokepoints invoked by the dispatcher; see `Currency.md`.
- **Reward** — Reward outcomes trigger direct redemption; see `Reward.md`.
- **Earn Channel** — Check-in appears as an earn source when configured; see `Earn_Channel.md`.
- **Tier / Tag & Persona** — Campaign eligibility mirrors reward-style filters; see `Tier.md`, `Tag_and_Persona.md`.
- **Mission** — Shares dispatcher primitives; missions may reference check-in as completion criteria; see `Mission.md`.
