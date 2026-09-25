# Chokepoint → Kafka — Redemption (next phase)

**Status (2026-05-16):** **Phase R-1 (DB layer) is live.** Originally shipped via `chokepoint_redemption_emit_trigger_v1` with a separate `fn_build_redemption_event_payload` helper + `trigger_emit_redemption_event` classifier; cleaned up via `chokepoint_redemption_inline_payload_v1` which **inlined the payload builder into the trigger and dropped the helper** to match the precedent set by the other 4 chokepoints (`chokepoint_post_*_event` all build their payload inline before `fn_chokepoint_emit_event`). The two AFTER triggers on `reward_redemptions_ledger` are deployed. Backfill skip is GUC-only — callers must `PERFORM set_config('redemption.skip_emit','true',true);` before invoking; the planned `p_skip_emit` arg on the two `bulk_import_redemptions_chunk` overloads was **not** added (live signatures unchanged). Smoke verified all 9 event branches in transaction; live trigger re-verified post-inline with `used`/`unmarked_used` synthetic ROLLBACK round-trip. **Phase R-2 (Confluent topic + consumer wiring) is the next blocker** — outbox rows for `crm.events.redemption` will start accumulating with `last_error="Topic 'crm.events.redemption' not found"` from the worker until the Confluent topic is provisioned. Quiet redemption window right now (0 writes / 5 min) buys time, but provisioning should land before peak-hour traffic resumes.
**Reference:** `.cursor/plans/chokepoint-kafka-publisher.md` (the 4-chokepoint pipeline this builds on top of).
**Project ref:** `wkevmsedchftztoolkmi`. All DB work via Supabase MCP.

---

## TL;DR

We have 4 chokepoints today (purchase, wallet, tier_change, user) all flowing through the new outbox → Kafka pipeline. **Redemption is the obvious next domain with no chokepoint and no downstream signal.**

This plan adds a 6th topic `crm.events.redemption` driven by a **single AFTER trigger on `reward_redemptions_ledger`** (not a chokepoint function — see "Architecture choice" below). Unlike the previous 4 (which were CDC cut-overs), redemption is **net-new signal** — `reward_redemptions_ledger` was never in `crm_cdc_publication`, so there's no legacy pipeline to dual-run against and no Step 11 decommission. That removes the entire 24h soak gate.

Volume to expect: ~150k redemption rows / 30 days across 18 merchants today (~5k/day, sub-1 emit/sec average; bursts much higher during campaigns). Same pipeline that absorbs purchase + wallet + user volume will absorb this trivially.

---

## Architecture choice — why a trigger, not a chokepoint function

The existing 4 chokepoints are all function-level (caller invokes `chokepoint_post_<domain>_event(...)`) because:

1. **Their write surface fans out to multiple tables.** Purchase writes hit `purchase_ledger` + `purchase_items_ledger` + (for refunds) recursive purchase rows. The chokepoint function's job is to consolidate those multi-table writes behind one entry point.
2. **Their event-intent isn't derivable from column diffs alone.** A `purchase_ledger` UPDATE could mean "completed", "cancelled", or "promo_applied" — same column flips, different intent. Only the calling function knows.

**Neither condition holds for redemptions:**

1. **Single write surface.** Every redemption operation writes to exactly one row of `reward_redemptions_ledger` (plus an audit row in `redemption_usage_log`, which is internal-only). No fan-out.
2. **Intent IS column-diff-able.** Each lifecycle verb has a unique column-change signature (see "Event classification" table below).

**Plus there's strong precedent on this exact table:** `reward_redemptions_ledger` already has `validate_reward_store_stock_on_use` — an `AFTER INSERT OR UPDATE OF used_status, used_store_id, redeemed_store_id, qty, cancelled` trigger that runs reactive logic on the same column set we'd want to emit on.

So the chokepoint here is **the table itself**, expressed as a trigger. Zero refactor of the 12 redemption-touching functions. Any future code that writes to the table (intentionally or not) will emit. One classifier, one place to maintain.

---

## Why now (gap analysis)

Today, when a customer **uses** a reward (frontline scan, app QR, package entitlement consumed), there is **no downstream signal at all** outside the redemption tables themselves:

| Lifecycle event | DB write | Wallet event fires? | Downstream visibility |
|---|---|---|---|
| `redeem` (issuance) | INSERT `reward_redemptions_ledger` + burn | YES (burn) | AMP/Currency/Tier see `wallet.burn`. **Reward context** (`reward_id`, `qty`, `redemption_id`, `store_id`) is **not** carried natively in the burn payload — it's only in `metadata`. |
| `mark_used` (single-use) | UPDATE `used_status=true` | NO | **Blackhole.** AMP cannot fire on "user used a reward". |
| `use_entitlement` (multi-use consume) | UPDATE `used_qty++` | NO | **Blackhole.** |
| `cancel` | UPDATE `cancelled=true` (+ optional refund) | If refund: YES (earn) | AMP sees `wallet.earn` for the refund only. The cancellation itself isn't a first-class signal. |
| `unmark_used` | UPDATE `used_status=false` | NO | **Blackhole.** |
| `reverse_entitlement_use` | UPDATE `used_qty--` | NO | **Blackhole.** |
| `adjust_entitlement_total` | UPDATE `qty±` | NO | **Blackhole.** |
| `expire_entitlement` (cron) | UPDATE `used_status=true` (forced) | NO | **Blackhole.** |
| `package_entitlement_created` | INSERT (mass) | NO | **Blackhole.** |

**Concrete product gap:** a customer is in-store, scans their reward QR, the cashier marks it used → we cannot fire any AMP workflow on that ("send a thank-you survey", "schedule a re-engagement message", "tag them as `redeemed_in_store`"). We also cannot attribute revenue uplift to a redemption because there's no event for OutcomeAttribution to consume.

Adding `chokepoint_post_redemption_event` closes all of these blackholes and gives reward usage parity with how purchases/wallet/tiers are currently observable.

---

## Today's redemption write surface (no consolidation needed)

Verified live via MCP `pg_proc` 2026-05-16. **All 12 paths write to one row of `reward_redemptions_ledger` (plus an audit row in `redemption_usage_log`).** Because we're putting the chokepoint at the table layer, none of these functions need to be refactored. Listed here just to confirm they all flow through the trigger:

| Function | Scope | What it writes |
|---|---|---|
| `redeem_reward_with_points(p_reward_id, p_quantity, p_user_id, p_merchant_id, p_mode, p_source_type, p_source_id, p_event_id, p_store_id)` | Issuance (user + admin + service_role) | INSERT `reward_redemptions_ledger` (1 or N rows for promo-code rewards) + INSERT `redemption_usage_log` (`action='redeem'`, only when `p_store_id` set or admin frontline) + calls `chokepoint_post_wallet_transaction` for the burn |
| `admin_redeem_and_use(p_user_id, p_reward_id, p_quantity, p_merchant_id, p_notes, p_store_id)` | Admin "issue + immediately consume" | Calls `redeem_reward_with_points` then UPDATEs `used_status=true` + INSERTs `redemption_usage_log` (`action='use'`) |
| `bulk_import_redemptions_chunk(...)` | Backfill (historical import) | INSERT `reward_redemptions_ledger` rows in chunks. Should `_skip_emit=true`. |
| `fn_create_package_entitlements(p_assignment_id)` | Package assignment fan-out | INSERTs N `reward_redemptions_ledger` rows (one per mandatory package item) |
| `api_mark_redemption_used(p_redemption_id, p_redemption_code, p_user_id, p_notes, p_language, p_merchant_id, p_store_id)` | User self-mark + admin mark single-use | UPDATE `used_status=true, used_at, used_store_id, fulfillment_status='completed'` + INSERT `redemption_usage_log` (`action='use'`) |
| `admin_mark_redemptions_used(p_redemption_ids[], p_user_id, p_merchant_id, p_notes, p_store_id, p_language)` | Bulk admin mark | Per redemption: UPDATE used_status + INSERT redemption_usage_log |
| `api_use_entitlement(p_redemption_id, p_user_id, p_store_id, p_external_ref, p_merchant_id)` → `fn_use_entitlement(...)` | Multi-use entitlement consume | UPDATE `used_qty++`, conditionally `used_status=true` when fully consumed + INSERT `redemption_usage_log` (`action='use'`) |
| `bff_admin_adjust_entitlement(p_redemption_id, p_qty_change, p_reason)` → `fn_adjust_entitlement_total(...)` | Admin adjust total qty | UPDATE `qty` + recompute `used_status` + INSERT `redemption_usage_log` (`action='adjust'`) |
| `fn_reverse_entitlement_use(p_redemption_id, p_qty, p_performed_by, p_reason)` | Entitlement reverse | UPDATE `used_qty--`, optionally clear `used_status` + INSERT `redemption_usage_log` (`action='reverse'`) |
| `api_cancel_redemption(p_merchant_id, p_redemption_id, p_redemption_code, p_reason, p_cancelled_by, p_force_used)` | Cancel (with optional force-used reversal + refund) | UPDATE `cancelled=true, cancelled_at, cancelled_reason, cancelled_by` + (if `force_used`) UPDATE `used_status=false` + INSERT `redemption_usage_log` (`action='reverse_use'`) + (if points were deducted) calls `chokepoint_post_wallet_transaction` (refund) + UPDATE `reward_promo_code.redeemed_status=false` |
| `admin_unmark_redemption_used(p_merchant_id, p_redemption_id, p_redemption_code, p_reason, p_store_id)` | Reverse a stale "used" mark | UPDATE `used_status=false, used_at=NULL, used_store_id=NULL, fulfillment_status='pending'` + INSERT `redemption_usage_log` (`action='reverse_use'`) |
| `fn_expire_package_entitlements()` | Daily cron auto-expire | Per stale row: UPDATE `used_status=true, used_at=now()` + INSERT `redemption_usage_log` (`action='expire'`) |

**Out of scope (separate redemption surface, not consolidated here):**
- `create_parking_privilege_redemption(p_merchant_code, p_ticketid, p_rewardid)` — writes to a different table (`futurepark_parking_privilege_redemptions`), merchant-specific, no downstream consumer reading it. If futurepark needs a downstream signal later, build a separate chokepoint for it.

---

## Architecture (silver tier, identical to existing pipeline)

```
┌──────────────────────────────────────────────────────────────────┐
│  12 existing redemption functions  ← UNCHANGED                   │
│  (auth, validation, business rules, return shapes — all intact)  │
│  Each writes to reward_redemptions_ledger as it does today.      │
└──────────┬───────────────────────────────────────────────────────┘
           │ INSERT or UPDATE OF used_status, used_qty, qty, cancelled
           ▼
┌──────────────────────────────────────────────────────────────────┐
│  AFTER trigger: emit_redemption_event_after_{insert,update}      │
│  on public.reward_redemptions_ledger                             │
│                                                                   │
│  trigger_emit_redemption_event() classifies via TG_OP +          │
│  column-diff:                                                    │
│    INSERT non-entitlement     → 'issued'                         │
│    INSERT entitlement         → 'package_entitlement_created'    │
│    UPDATE cancelled false→true → 'cancelled'                     │
│    UPDATE qty changed (entitlement) → 'entitlement_total_adjusted'│
│    UPDATE used_qty++ (entitlement)  → 'entitlement_used'         │
│              (or 'entitlement_expired' if used_status=true       │
│              with used_qty<qty — fn_expire_* path)               │
│    UPDATE used_qty-- (entitlement)  → 'entitlement_use_reversed' │
│    UPDATE used_status false→true   → 'used'                      │
│    UPDATE used_status true→false   → 'unmarked_used'             │
│                                                                   │
│  Honors current_setting('redemption.skip_emit', true)='true' as  │
│  a per-transaction backfill hatch.                               │
│                                                                   │
│  Wraps fn_chokepoint_emit_event call in EXCEPTION WHEN OTHERS    │
│  → never blocks a redemption write because of an emit hiccup.    │
└──────────┬───────────────────────────────────────────────────────┘
           ▼
   fn_chokepoint_emit_event('crm.events.redemption', user_id, payload)
   public.chokepoint_event_outbox  (existing, unchanged)
           │ pg_notify('chokepoint_outbox_new', id::text)
           ▼
   OutboxPublisher worker (existing, unchanged — topic-agnostic)
           ▼
   Confluent: crm.events.redemption (NEW topic)
           ▼
   AMP, OutcomeAttribution, (optional) Mission consumers
```

**Reuses without change:** `chokepoint_event_outbox` table, `fn_chokepoint_emit_event` helper, `chokepoint_outbox_cleanup` cron, `v_chokepoint_outbox_health` view, OutboxPublisher worker. The outbox infra is already chokepoint-agnostic — only the topic CHECK regex matters, and the new topic `crm.events.redemption` already passes `'^crm\.events\.[a-z_]+$'`.

### Event classification table (the only logic in the trigger)

| TG_OP | Column condition | Emitted event |
|---|---|---|
| INSERT | `source_type IN ('package_assignment','persona_entitlement')` | `package_entitlement_created` |
| INSERT | otherwise | `issued` |
| UPDATE | `OLD.cancelled IS DISTINCT FROM NEW.cancelled AND NEW.cancelled = true` | `cancelled` |
| UPDATE | entitlement source_type AND `NEW.qty IS DISTINCT FROM OLD.qty` | `entitlement_total_adjusted` |
| UPDATE | entitlement AND `NEW.used_qty > OLD.used_qty` AND `used_status` flips true with `used_qty < qty` | `entitlement_expired` |
| UPDATE | entitlement AND `NEW.used_qty > OLD.used_qty` (other case) | `entitlement_used` |
| UPDATE | entitlement AND `NEW.used_qty < OLD.used_qty` | `entitlement_use_reversed` |
| UPDATE | `OLD.used_status IS DISTINCT FROM NEW.used_status AND NEW.used_status = true` AND non-entitlement | `used` |
| UPDATE | entitlement AND `used_status` flips true with `used_qty < qty` (no `used_qty` change in same call) | `entitlement_expired` |
| UPDATE | `OLD.used_status IS DISTINCT FROM NEW.used_status AND NEW.used_status = false` | `unmarked_used` |
| UPDATE | none of the above (e.g., `points_calculation` jsonb-only edit) | no emit |

**Force-cancel branch of `api_cancel_redemption`** (calls `UPDATE used_status=false` then `UPDATE cancelled=true` in two separate statements) emits **two** events: first `unmarked_used`, then `cancelled`. Both correct — consumers can correlate by `redemption_id`.

**Cancellation refund** still emits its own `crm.events.wallet` via `chokepoint_post_wallet_transaction` as it does today. The new redemption `cancelled` emit is additive context, not a replacement.

---

## Topic + partition map (1 new topic)

| Topic | Partition key | Emitted by | Consumed by |
|---|---|---|---|
| `crm.events.redemption` | `user_id` (NULL-tolerant; falls back to `redemption_id` for parking-style anonymous rows) | `chokepoint_post_redemption_event` | AMP (new redemption-based source events), OutcomeAttribution (for redemption-driven attribution windows), optionally Mission |

Topic config matches the other 5: 6 partitions, 7-day retention, gzip, delete cleanup.

**Why partition by `user_id`:** preserves per-user ordering — issuance → use → cancel events for the same user land on the same partition and are processed in order by AMP. Using `redemption_id` would scatter the lifecycle of one redemption across partitions.

---

## Skip-emit hatch (backfill)

The trigger reads a transaction-local GUC at the top:

```plpgsql
v_skip_emit := COALESCE(current_setting('redemption.skip_emit', true), 'false') = 'true';
IF v_skip_emit THEN RETURN NULL; END IF;
```

**GUC-only mechanism — no function-side wrapper.** `bulk_import_redemptions_chunk` (both overloads) was **not** modified. Backfill callers are responsible for setting the GUC themselves at the start of the transaction:

```plpgsql
BEGIN;
  PERFORM set_config('redemption.skip_emit', 'true', true);  -- true = txn-local
  -- ...call bulk_import_redemptions_chunk(...) or run direct INSERTs into reward_redemptions_ledger...
COMMIT;
```

This means:
- **Default behavior:** any write to `reward_redemptions_ledger` emits — including bulk imports if the caller forgot to set the GUC. Be explicit in backfill scripts.
- **Caller opt-out:** set `redemption.skip_emit='true'` for the duration of the transaction. Universal — works for `bulk_import_redemptions_chunk`, direct SQL backfills, ad-hoc admin scripts. No function-specific wrapper needed.
- **Per-row override** is not supported by design — backfills are all-or-nothing on emit.

Real-time write paths (`redeem_reward_with_points`, `api_mark_redemption_used`, etc.) never set the GUC and always emit.

---

## Payload contract

All payloads share the standard outer envelope:

```jsonc
{
  "event":         "<verb>",                  // 'issued', 'used', etc.
  "merchant_id":   "uuid",
  "occurred_at":   "2026-05-16T10:12:00Z",
  "source":        "chokepoint_post_redemption_event",
  "source_function": "redeem_reward_with_points",  // which caller triggered this event
  // ...domain-specific fields below
}
```

### `crm.events.redemption` (all branches)

Full superset; each branch populates the relevant subset:

```jsonc
{
  "event":              "issued|used|entitlement_used|entitlement_use_reversed|entitlement_total_adjusted|entitlement_expired|cancelled|unmarked_used|package_entitlement_created",
  "merchant_id":        "uuid",
  "user_id":            "uuid|null",          // partition key when present
  "redemption_id":      "uuid",
  "redemption_code":    "string|null",        // human-readable code from set_redemption_code_before_insert trigger
  "reward_id":          "uuid",
  "qty":                1,                    // total entitlement qty (for issuance & adjusts)
  "used_qty":           0,                    // running consumed count (for entitlement_used / reversed)
  "qty_change":         1,                    // delta this call applied (for adjust / use / reverse / expire)
  "used_qty_after":     1,                    // post-mutation consumed count
  "remaining":          0,                    // qty - used_qty (entitlement events only)
  "fully_consumed":     true,                 // (entitlement_used / used) — flipped to fully-used this call
  "used_at":            "...|null",
  "used_store_id":      "uuid|null",
  "redeemed_store_id":  "uuid|null",
  "fulfillment_status": "pending|completed",
  "use_expire_date":    "...|null",
  "redeemed_at":        "...|null",
  "cancelled":          false,
  "cancelled_at":       "...|null",
  "cancelled_reason":   "...|null",
  "cancelled_by":       "uuid|null",
  "source_type":        "wallet_transaction_source_type|null",
  "source_id":          "uuid|null",
  "package_assignment_id": "uuid|null",
  "promo_code":         "string|null",
  "promo_code_id":      "uuid|null",
  "external_ref_id":    "string|null",        // shopify discount code id, if any
  "points_deducted":    0,
  "wallet_ledger_id":   "uuid|null",          // present on issued (burn) + cancelled-with-refund (earn)
  "performed_by":       "string|null",        // 'auth.uid()' | 'service_role' | 'system' | 'admin'
  "actor_admin_user_id": "uuid|null",
  "store_id":           "uuid|null",
  "notes":              "string|null",
  "occurred_at":        "2026-05-16T10:12:00Z",
  "source":             "chokepoint_post_redemption_event",
  "source_function":    "string"
}
```

**Why one schema for all branches:** matches how `crm.events.purchase` carries 12 different `event` values in one schema. Consumers filter on `event` first then read the fields they need. Avoids 9 separate topics for one domain.

**Why include `wallet_ledger_id` on issuance/cancel:** lets AMP & OutcomeAttribution correlate the redemption event with its wallet emit on `crm.events.wallet` and dedupe across them when needed. Same pattern the wallet payload uses for its `transaction_id` field.

---

## Phased execution

The whole thing collapses to **2 DB-touching phases** (was 13 sub-migrations and 4 phases under the old chokepoint-function design):

### Phase R-1 — Trigger + helper + bulk-import GUC (single migration)

Migration name: `chokepoint_redemption_emit_trigger_v1`

DDL bundle (as deployed, after the inline cleanup):

1. `CREATE FUNCTION trigger_emit_redemption_event() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER` — the classifier described above, with the payload `jsonb_strip_nulls(jsonb_build_object(...)) || COALESCE(v_extras, '{}'::jsonb)` constructed inline before the `PERFORM fn_chokepoint_emit_event(...)` call (matches the other 4 chokepoints' pattern). Outer `EXCEPTION WHEN OTHERS` downgrades any emit failure to `RAISE NOTICE` so a misbehaving outbox can never block a redemption write.
2. `CREATE TRIGGER emit_redemption_event_after_insert AFTER INSERT ON reward_redemptions_ledger FOR EACH ROW EXECUTE FUNCTION trigger_emit_redemption_event()`.
3. `CREATE TRIGGER emit_redemption_event_after_update AFTER UPDATE OF used_status, used_qty, qty, cancelled ON reward_redemptions_ledger FOR EACH ROW EXECUTE FUNCTION trigger_emit_redemption_event()`.

**No changes** to `bulk_import_redemptions_chunk` overloads. Callers that need to suppress emits during a backfill must set the session GUC themselves before invoking:

```plpgsql
PERFORM set_config('redemption.skip_emit', 'true', true);  -- true = txn-local
-- ...then call bulk_import_redemptions_chunk(...)
```

The trigger reads `current_setting('redemption.skip_emit', true)` at the top of every fire and bails out when it's `'true'`. Universal: any caller that sets the GUC suppresses emits for the duration of that transaction; the trigger doesn't care which function set it.

Smoke test before applying (run in `BEGIN; ... ROLLBACK;`):

- INSERT a synthetic non-entitlement row → assert outbox got 1 row with `event='issued'` and matching `partition_key`.
- INSERT a synthetic entitlement row → assert outbox got 1 row with `event='package_entitlement_created'`.
- UPDATE `used_status=true` on the non-entitlement row → assert `event='used'`.
- UPDATE `used_status=false` → assert `event='unmarked_used'`.
- UPDATE `used_qty=used_qty+1` on the entitlement → assert `event='entitlement_used'`.
- UPDATE `cancelled=true` → assert `event='cancelled'`.
- `set_config('redemption.skip_emit','true',true)` then INSERT → assert no new outbox row.

After applying for real, eyeball `v_chokepoint_outbox_health` for 5 min: `crm.events.redemption` should be accumulating at ~5k/day rate (≈1 emit per 17 seconds).

**At this point the worker will start trying to publish to a topic that doesn't yet exist on Confluent.** The worker's per-row retry will surface as `last_error` in the outbox table. Two mitigations available:

- (a) **Sequence so Confluent topic provisioning happens before R-1 deploys** — preferred, simpler.
- (b) Add a runtime topic-allowlist env var on the worker so it skips publishing rows for unprovisioned topics. More code, less coupling.

We'll go with (a).

### Phase R-2 — Consumer wiring (code) + Confluent topic provisioning

**Note on terminology:** earlier drafts called this "dual-read." It's not — `reward_redemptions_ledger` was never in `crm_cdc_publication`, so there's no legacy CDC pipeline to dual-run against. R-2 is simply "add a new topic to existing consumers" + "provision the topic on Confluent." Redis dedup is still used, but for KafkaJS rebalance-retry absorption, not for legacy-vs-chokepoint overlap.

**Code changes (landed 2026-05-16):**

1. **`crm-event-processors/src/config.ts`:** added `redemptionEvents: 'crm.events.redemption'` alongside the existing 5 chokepoint topics; comment block notes redemption's `COALESCE(user_id, redemption_id)` partition-key fallback.
2. **`AmpConsumer` (`src/consumers/amp-consumer.ts`):**
   - `ChokepointEvent` interface extended with `redemption_id`/`redemption_code`/`reward_id`/`qty`/`used_qty`/`used_status`/`cancelled`/`fulfillment_status`/`package_assignment_id`/`qty_change`. Existing `source_id?: string` widened to `string | null` (the redemption payload's `source_id` comes from a nullable column).
   - `isChokepointEventTopic()` now matches `redemptionEvents`.
   - `subscribe()` topic list (gated by `config.flags.chokepointEventsEnabled`) includes the redemption topic.
   - New dispatch branch in `handleChokepointEventMessage()` — fires for **all 9 event verbs**, with `trigger_table='reward_redemptions_ledger'` + `trigger_operation='INSERT'` + `record_data` carrying the verb + lifecycle shape. AMP workflow rules filter on `record_data.event` to select the verb they care about.
   - Dedup key: **`amp:reward_redemptions_ledger:${event}:${redemption_id}`** (the verb is part of the key, so each lifecycle step dispatches as a distinct AMP trigger; only KafkaJS rebalance-retry duplicates within 300s are absorbed).
3. **`OutcomeAttributionConsumer` (`src/consumers/outcome-attribution-consumer.ts`):**
   - `ChokepointEvent` interface extended with `redemption_id`/`reward_id`/`qty`/`used_qty`/`qty_change`.
   - `isChokepointEventTopic()` + `subscribe()` updated like AMP.
   - `handleChokepointEventMessage()` classifies **4 of 9 verbs** as attributable outcomes (the rest are operational): `issued` → `reward_redeemed`, `used`+`entitlement_used` → `reward_used`, `cancelled` → `reward_cancelled`. Customers opt into redemption attribution by adding rows with `event_type IN ('reward_redeemed','reward_used','reward_cancelled')` to `amp_agent_outcome`; until configured, events are received + dedup-checked but produce no attribution rows.
   - Dedup key: **`oattr:${eventType}:${redemption_id}:${event}:${used_qty ?? 0}`** (deviates from the standard `oattr:<eventType>:<sourceId>` because multi-use entitlement consumption fires multiple `entitlement_used` events on the same `redemption_id` with monotonically increasing `used_qty` — the qty disambiguates them within the 600s window).
4. **`MissionConsumer`:** unchanged. Opt-in for the future — wire when/if a mission rule is defined that fires on "user used a reward."
5. **`RewardConsumer`:** unchanged. It's the **producer**-side path (Kafka → call `redeem_reward_with_points` RPC), not a chokepoint consumer. The new emits fire automatically when its RPC writes.

**Infra step still to do (you):**

6. **Confluent topic provisioning:** create `crm.events.redemption` on `pkc-ox31np.ap-southeast-7.aws.confluent.cloud`: **6 partitions, 7d retention, gzip, delete cleanup**. The existing `crm.events.*` ACL prefix already grants WRITE+DESCRIBE to the `chokepoint-publisher` API key — no new credentials needed.
7. **Render redeploy** of `crm-event-processors` to pick up the new consumer code.

Until 6 + 7 land, outbox rows for `crm.events.redemption` continue to accumulate with `last_error='This server does not host this topic-partition'` (2 rows already as of the code-side commit). Once the topic exists, the worker drains the backlog and AMP starts dispatching on lifecycle events.

### Phase R-3 — Doc cleanup

There is **nothing to decommission in CDC** (`reward_redemptions_ledger` was never in the publication). Only:

- Update `requirements/REGISTRY_SUPABASE.md` "Chokepoint Outbox" section: add the new trigger + helper functions + topic.
- Update `requirements/REGISTRY_RENDER.md` worker line: include `crm.events.redemption` in the topic list.
- Append `requirements/CHANGELOG.md` entries.
- Add a "Redemption (trigger-based)" subsection to `.cursor/plans/chokepoint-kafka-publisher.md`'s "Per-chokepoint emit specification" so future maintainers know it exists.

---

## SLO gate (per-phase, no 24h soak)

Because there's no legacy CDC pipeline to compare against, the gate is **internal correctness**, not parity:

After **R-1**:
- [ ] All 7 in-transaction smoke assertions pass (issued, package_entitlement_created, used, unmarked_used, entitlement_used, cancelled, skip_emit honored).
- [ ] Pre-existing redemption flows in admin UI still function — function bodies were untouched, but verify redemption issuance and mark-used end-to-end on a live merchant.
- [ ] `v_chokepoint_outbox_health` shows `crm.events.redemption` accumulating at ≈ organic rate (~5k/day, ~1 row per 17s).
- [ ] `errored = 0` for `crm.events.redemption` after R-2's Confluent topic exists (during the gap between R-1 and R-2, `errored` will rise — that's the topic-doesn't-exist-yet error and is recoverable).

After **R-2**:
- [ ] Confluent topic shows ≈ trigger emit rate.
- [ ] `OutboxPublisher` `errored = 0` and `unpublished_stale = 0` for the new topic.
- [ ] AMP receives `crm.events.redemption` events and dispatches at least one realtime event per `event` value — verify per-event with a cherry-picked synthetic redemption.
- [ ] No exceptions in `crm-event-processors` Render logs.

---

## Rollback (per layer, independent)

| Failure | Action | Blast radius |
|---|---|---|
| Trigger misclassifies an event (wrong `event` field on certain edge cases) | `CREATE OR REPLACE FUNCTION trigger_emit_redemption_event()` with corrected logic. Outbox already in dual-state — incorrect events get dedup-absorbed by AMP because the dedup key includes `event`. | Local: only future emits use new logic. Pre-fix events stay in outbox/Kafka with original (incorrect) classification. Re-emission after fix would be a one-off backfill if needed. |
| Trigger raises an unexpected exception | Outer `EXCEPTION WHEN OTHERS` block in the trigger function catches it and converts to `RAISE NOTICE`. **Redemption write itself succeeds.** Outbox just doesn't get a row for that one transaction. | Single-transaction emit miss. Re-publishable manually if material. |
| Trigger overhead degrades redemption write latency | `DROP TRIGGER emit_redemption_event_after_insert, emit_redemption_event_after_update ON reward_redemptions_ledger` — instant. Helper + trigger function stay (harmless). | Emits stop. Redemption writes return to pre-trigger latency. Re-attach triggers after fix. |
| Worker can't publish `crm.events.redemption` (Confluent down, ACL drift) | Confluent issue → KafkaJS retries; outbox queues for that topic only; other 5 keep flowing. ACL drift → fix ACL, no redeploy. | Per-topic transient backpressure on redemption only. |
| AMP consumer breaks on the redemption payload shape | Set `CHOKEPOINT_EVENTS_ENABLED=false`, restart Render. All 6 chokepoint topics fall back to legacy CDC paths — but redemption has **no** legacy CDC fallback, so AMP simply won't fire on redemption events until the consumer is fixed. | Tolerable: redemption was a downstream blackhole pre-this-plan anyway. |

---

## Knobs (no new Render env vars)

The existing `OUTBOX_PUBLISHER_*` and `CHOKEPOINT_EVENTS_ENABLED` flags govern this entire pipeline. **Nothing new to add.**

---

## Out of scope (deferred)

- **Futurepark parking privilege redemptions** (`futurepark_parking_privilege_redemptions`) — separate table, separate function `create_parking_privilege_redemption`, no downstream consumer. If Futurepark needs a downstream signal, build a parallel chokepoint then.
- **Card redemptions** (`redeem_card`) — gift-card-style; different domain, different ledger. Out of scope for the loyalty redemption pipeline.
- **`crm.events.reward`** topic for reward-master changes (someone updates a reward's points cost) — not requested, can be added later if AMP needs it.
- **Schema Registry for `crm.events.redemption`** — same JSON-only stance as the other 5 topics.
- **Mission consumer wiring** — defer until a concrete mission rule needs `redemption.used` as a trigger.

---

## Reference: live counts (verified 2026-05-16)

- `reward_redemptions_ledger` total rows: **1,451,249** across 18 merchants.
- 30-day rate: **~150,164 rows / 30d ≈ 5k/day ≈ 0.06 emits/sec average**.
- Last 30d `redemption_usage_log` actions: 163 `use`, 10 `lookup`, 2 `redeem`. (The low `redeem` count is because `redemption_usage_log` only records redemptions that hit the store-aware path — the chokepoint will record all of them.)
- Outbox health right now: 271 published rows lifetime, 0 unpublished, 0 errored. Pipeline is idle and healthy — adding a 6th topic at ~0.06 emits/sec is well within the worker's drained throughput.

---

## What this plan does NOT change

- `chokepoint_event_outbox` schema, indexes, CHECK regex, retention.
- `fn_chokepoint_emit_event` signature.
- `chokepoint_outbox_cleanup` cron.
- `OutboxPublisher` worker code (the worker is topic-agnostic by design).
- The 5 existing chokepoint functions and their payloads.
- **The 12 redemption-touching function bodies** — the entire point of the trigger-based architecture is they stay untouched.
- The CDC publication membership (still `cdc_heartbeat`, `form_submissions`, `purchase_ledger`, `tier_change_ledger`, `user_accounts`, `wallet_ledger`).
- Reward consumer behavior — it stays a producer-of-redemption-RPCs, not a consumer of `crm.events.redemption`.
