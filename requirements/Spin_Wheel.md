# Spin Wheel

Weighted-random gamification campaigns: members pay spin cost (points, tickets, or free), land on one prize slice, and receive every grant configured on that slice through the central outcome dispatcher.

Owner surfaces: loyalty-admin, loyalty-user

## Concept

Spin wheel is a **gamified lottery mechanic** merchants configure as one or more **campaigns** (wheels). Each campaign defines who may spin, when, at what **cost**, how often (participation caps), and a set of **segments** (wheel slices). One spin always selects exactly one segment by **relative weight**, then delivers zero or more **outcomes** (points, tickets, reward pushes, earn-factor assignments) for that slice.

**Campaign / wheel** — Named program with active window, spin cost, eligibility filters, presentation JSON, and participation limits.

**Segment / prize slice** — One wheel slice with a **weight** (relative probability, not a fixed percentage), display order, optional inventory cap, optional no-win flag, and marketing label. Product language treats the slice as “the prize”; dispatcher language treats each grant row as an **outcome**.

**Outcome (grant row)** — One configured grant on a winning segment: points quantity, ticket type + quantity, reward push, or earn-factor assignment. A segment may have many outcome rows or none when marked no-win.

**Spin (event)** — One immutable ledger row: cost charged (if any), winning segment, RNG audit snapshot, link to wallet burn. Participation limits count spin rows, including no-win spins.

**Relative weights** — At draw time, eligible segments contribute weight; probability of segment S = weight(S) / sum(weights). Weights need not sum to 100. Inactive segments and sold-out segments (stock remaining zero) drop out before normalization. Admin UI may show percentages derived from weights.

**Cost** — Points burn, ticket burn, or free (`cost_amount = 0`). Outcome grants are independent of cost (e.g. pay points, win tickets).

**Segment stock** — Optional cap on how many times a **slice** can be won worldwide; distinct from reward redemption limits and from campaign-wide spin caps.

**No-win segment** — Slice that participates in the draw but dispatches no grants (“try again”). Still charges cost unless free; still counts toward limits.

**Presentation config** — Opaque JSON on campaign and segments for banners, colors, icons, and copy. Backend stores pass-through JSON; the spin engine never reads it.

**Participation limit** — Per-campaign cap in the shared limits facility with entity type spin wheel; scope per member or campaign-wide, over day/week/month/year/all_time.

Progress and fairness are **log-derived**: limits and disputes use `spin_wheel_log`; per-grant audit lives in outcome distribution log with source type spin wheel. All grants route through the same dispatcher primitive as check-in, missions, and AMP. Sync path only — no Kafka, Inngest, or edge function on the spin path.

## Rules

- If campaign is inactive, outside `window_start` / `window_end`, or unknown → spin and status treat as unavailable (`Spin wheel campaign not found or inactive`).
- If tier, persona, tag (member must overlap at least one listed tag), or birth-month filters are set and the member fails → spin fails with the matching eligibility error. Empty or null filter arrays → no restriction on that dimension. Buyer/seller type filters are not supported (use persona/tier/tags).
- If a participation limit applies and the member or campaign has reached the cap in the configured window → spin fails with personal or campaign limit reached (status exposes `spins_remaining` and `next_reset_at` where applicable).
- Before any charge, the engine must find a **winnable set**: at least one active segment with stock (or unlimited stock) **or** an active no-win segment. If none → `no_prize_available` with **no** wallet burn.
- If `cost_amount > 0` and balance (points or ticket type) is below cost → `insufficient_balance` before charge.
- One spin → one segment → N dispatcher calls (one per outcome row on that segment). Never multiple segments per spin.
- **Atomic transaction** — spend, weighted selection, stock decrement, outcome dispatch, and log insert succeed or fail together. Any dispatch failure rolls back burn and stock.
- Sold-out segments (`stock_remaining = 0`) are excluded from the draw; remaining weights renormalize. Concurrent last-unit wins use atomic decrement; loser re-draws (up to 50 attempts) or falls back per no-win rules.
- If all weighted segments have weight zero → fallback to first active no-win segment if configured; else `no_prize_available`.
- No-win winning segment skips dispatch; still inserts log and applies cost unless free.
- Free spins skip wallet burn; cost fields on log may be null.
- Limit counting includes every spin log row, including no-win spins.
- Reward-type outcomes still enforce reward and reward-group limits at grant time via the dispatcher.
- Admin upsert requires at least one segment with `weight > 0`. Ticket cost requires valid active ticket type. Weights not summing to 100 → advisory `weight_note` only, not rejected.
- Admin delete: if any spin log exists → soft delete (`active_status = false`); else hard delete campaign tree and limit rows.
- User BFFs resolve member identity from session only — never accept client-supplied user or merchant ids. Internal engine functions are not granted to browser roles.

**Example (non-obvious weight normalization):** Segments A=50, B=30, C=20 → 50% / 30% / 20%. If C sells out, A and B renormalize to 62.5% / 37.5% among eligible slices.

## Journeys

### Admin journey

| Page | Owning repo | BFF / RPC |
| --- | --- | --- |
| Spin wheel list | loyalty-admin | `bff_list_spin_wheels` |
| Spin wheel settings (create / edit) | loyalty-admin | `bff_get_spin_wheel_details` (load), `bff_upsert_spin_wheel` (save) |
| Segments, outcomes, limits (embedded in settings) | loyalty-admin | Nested arrays on upsert (full replace / orphan delete) |
| Delete campaign | loyalty-admin | `bff_delete_spin_wheel` |

| Setting | Effect on behaviour |
| --- | --- |
| Name / description | List labels and member page headings |
| Active status / window start / end | Campaign availability |
| Cost currency / ticket type / amount | Points burn, ticket burn, or free spin |
| Eligibility arrays | Tier, persona, tags, birth month gates |
| Segment label, weight, order, active | Wheel layout and draw weights |
| Segment stock total / remaining | Limited prize inventory (admin-visible only) |
| Segment no-win flag | Slice with zero outcome rows |
| Outcome rows per segment | Grant types, amounts, entity refs, metadata |
| Campaign / segment `display_config` | Presentation JSON (pass-through; engine ignores) |
| Participation limits | Per-user and/or campaign-wide spin caps |

1. Open **Spin wheel list** and start **Create spin wheel** (or edit an existing row).
2. Set campaign name, description, active flag, and optional date window.
3. Set spin cost: points, ticket type + amount, or zero for free.
4. Set eligibility filters or leave empty for all members.
5. Add **segments**: label, weight, display order, optional stock cap, no-win flag, segment presentation JSON.
6. For each winning segment, add **outcome** rows (points, tickets, reward, earn factor) with entity refs and amounts.
7. Configure **participation limits** on the limits editor (stored with entity type spin wheel).
8. Set campaign presentation (banner, theme, copy keys) in presentation fields; save via upsert (single transactional payload for campaign, segments, outcomes, limits).
9. Copy member deep link from settings when needed (`…/spin-wheel/{campaign_id}` on the loyalty-user host).
10. Delete from list when retiring: soft-deletes if spins exist, else removes config tree.

Common pitfalls: ticket cost without ticket type fails upsert; all segments sold out with no no-win slice blocks spins; reward outcome out of stock rolls back entire spin; weights are relative — changing one slice changes displayed odds for all.

### Member journey

| Page / surface | Owning repo | BFF / RPC |
| --- | --- | --- |
| Spin wheel (per campaign) | loyalty-user | `bff_user_get_spin_wheel_status`, `bff_user_spin_wheel` |

1. Member opens spin wheel (deep link or in-app navigation). App loads **status**: campaign name, description, presentation config, segment list with `weight_pct` and labels, cost, balance, eligibility, `can_spin`, spins remaining.
2. If not eligible, inactive, over limit, or insufficient balance → UI disables spin and shows error copy from status (`is_eligible`, `can_spin`, `eligibility_error`).
3. Member taps spin; app calls **spin** RPC (debounce double-taps). Backend selects winning segment and grants before animation completes; UI animates wheel to returned `segment.id`.
4. On success: show win/lose modal using spin response outcomes for grants; resolve slice styling via `segment.id` against cached status segments (spin response does not echo `display_config`).
5. App refreshes status for balance, `can_spin`, and remaining spins.
6. On failure: show returned error string (unauthenticated, user not linked, inactive campaign, eligibility, limits, insufficient balance, no prize available, dispatch failure).

| Error (member-visible) | Typical cause |
| --- | --- |
| `UNAUTHENTICATED` / `USER_NOT_FOUND` | Session missing or no `user_accounts` row |
| Spin wheel campaign not found or inactive | Off or outside window |
| Tier / Persona / Tag / Birthday month requirement not met | Eligibility |
| Personal / Campaign participation limit reached | Cap exhausted |
| `insufficient_balance` | Points or tickets below cost |
| `no_prize_available` | No eligible segments and no no-win fallback |

## System

### Data model

| Artifact | Role |
| --- | --- |
| `spin_wheel` | Campaign header: window, cost, eligibility arrays, campaign `display_config`, active flag |
| `spin_wheel_segment` | Slice: weight, order, stock, no-win, segment `display_config`, active flag |
| `spin_wheel_segment_outcome` | Grant rows per segment; cascades on segment delete |
| `spin_wheel_log` | Immutable spin events; limit counting; `draw_metadata` RNG snapshot; optional `cost_ledger_id` |
| `transaction_limits` | Participation caps where `entity_type` is spin wheel and `entity_id` is campaign id |

Enum extensions: `wallet_transaction_source_type.spin_wheel`, `entity_type.spin_wheel`. Reuses `outcome_type_enum`, currency burn/earn, and shared limit time units (no `time_value` column — cap is `count` per `time_unit`).

**Stock semantics:** `stock_remaining` null = unlimited; zero excludes segment from draw. Upsert may default `stock_remaining` from `stock_total` on create. `stock_total` is informational after create.

**Upsert orphan handling:** Present child ids update; missing ids insert; ids not in payload delete for segments, outcomes, and limits.

### Functions

| Function | Role |
| --- | --- |
| `fn_spin_wheel` | Atomic engine: validate campaign, eligibility, limits, balance; weighted pick + stock decrement; chokepoint burn when cost > 0; dispatch outcomes; insert log. **Not** callable from browser roles. |
| `get_user_spin_wheel_status` | Internal read helper for status shape (explicit user/merchant ids). **Not** browser-callable. |
| `bff_user_get_spin_wheel_status` | Member status: resolves auth context → internal read. Primary source for presentation config pre-spin. |
| `bff_user_spin_wheel` | Member spin: resolves auth → `fn_spin_wheel`. |
| `bff_list_spin_wheels` | Admin list (no presentation JSON; summary counts and cost). |
| `bff_get_spin_wheel_details` | Admin load (`new` template or `edit` with segments, outcomes, limits, `weight_pct`, stock). |
| `bff_upsert_spin_wheel` | Admin save single jsonb tree. |
| `bff_delete_spin_wheel` | Soft or hard delete per spin history. |
| `fn_dispatch_outcome` | Central grants for every winning outcome row |
| `chokepoint_post_wallet_transaction` | Spin cost burn and dispatcher earns |

Triggers: `set_updated_at_spin_wheel`, `set_updated_at_spin_wheel_segment` on update.

### Flows

**Status (sync):** Load campaign and active segments → compute display weights → read wallet/ticket balance → evaluate eligibility → evaluate participation limits → return `can_spin`, `spins_remaining`, `next_reset_at`.

**Spin (sync):** Same validations → ensure winnable set → pre-generate spin log id → cumulative weighted random over eligible segments (re-draw on stock race) → burn cost with dedup key including spin log id → for each outcome on winner call dispatcher with source type spin wheel and per-outcome dedup key → insert log with `draw_metadata` (`random_value`, weight snapshot, selected segment) → return segment summary, outcome results, cost, `new_balance`. Segment in spin response: `id`, `label`, `is_no_win` only — no `display_config`.

**Admin save:** Validate segments and entities → upsert header → replace children with orphan cleanup.

**Grant audit:** Dispatcher writes outcome distribution log; spin cost links to wallet ledger via `cost_ledger_id`.

### Presentation (`display_config`)

| Surface | Column | Engine reads? |
| --- | --- | --- |
| Campaign chrome | `spin_wheel.display_config` | No |
| Segment chrome | `spin_wheel_segment.display_config` | No |

Pass-through JSON on upsert; no server defaults, validation, or `fn_enrich_display_config`. Structured columns (`name`, `description`, `label`, `weight`, outcomes table) hold configured truth; JSON holds rendering hints only.

| Endpoint | Campaign config | Segment config |
| --- | --- | --- |
| `bff_list_spin_wheels` | No | No |
| `bff_get_spin_wheel_details` | Yes (all segments) | Yes |
| `bff_user_get_spin_wheel_status` | Yes | Yes (active segments only) |
| `bff_user_spin_wheel` | No | No (lookup by `segment.id` from prior status) |

Suggested convention keys (not enforced): campaign groups `banner`, `wheel`, `theme`, `labels`, `icons`; segment `color`, `text_color`, `icon` / `icon_url`, `subtitle`, `badge`. Reward/ticket artwork for win modals comes from reward/ticket masters, not slice JSON.

### Security

RLS merchant isolation on config tables; spin log readable/insertable for own user where applicable. User BFFs bind `user_accounts` from `get_current_user_id()`. Admin BFFs require active `admin_users` row and merchant from JWT.

### External services

None on the spin path — Postgres only.

### Known gaps

- **Frontline spin on behalf of member** — Not shipped (no admin RPC like `process_checkin`; permission seeding deferred).
- **Spin history on member profile** — No dedicated BFF; support uses spin log and outcome distribution log.
- **Earn Channel surfacing** — Spin wheel is not modeled as an earn-channel card (deep link / CMS only).
- **Pity / guaranteed-win, personalized odds, bonus-spin wallet** — Out of scope for current engine.
- **Scheduled free-spin credits** — Use `cost_amount = 0` or future product; not a separate wallet type today.

## Related

- **Central Outcome Dispatcher** — All spin grants use `fn_dispatch_outcome`; see `Central_Outcome_Dispatcher.md`.
- **Currency** — Spin cost burn and point/ticket grants via wallet chokepoints; see `Currency.md`.
- **Reward** — Reward outcomes use direct redemption; eligibility and limits mirror reward rules; see `Reward.md`.
- **Check-in** — Sibling pattern for admin BFFs, eligibility arrays, and `transaction_limits`; see `Checkin.md`.
- **Tier / Tag & Persona** — Eligibility filters; see `Tier.md`, `Tag_and_Persona.md`.
- **CS config (TH)** — Merchant-facing setup narrative; see `Spin_Wheel_CS_Config_TH.md`.
