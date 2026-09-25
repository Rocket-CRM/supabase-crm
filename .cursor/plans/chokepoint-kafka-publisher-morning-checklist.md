# Chokepoint → Kafka — Morning Checklist (all 4 chokepoints)

**Generated:** 2026-05-14 overnight; expanded 2026-05-15 morning to cover all 4 chokepoints
**Architecture:** silver tier (outbox table + KafkaJS worker on Render, no Debezium)
**Reference plan:** `.cursor/plans/chokepoint-kafka-publisher.md`
**Scope:** all 4 existing chokepoints — purchase, wallet, tier_change, user — migrate from Debezium CDC to chokepoint→outbox→Kafka in one cut-over.
**Rationale for silver over gold:** prior 27 GB WAL slot bloat history (transcript `d0b94926-01cb-456f-bc0c-d831110035a1`). Silver removes the logical replication slot from the new pipeline → structurally immune to that failure mode.

---

## Topic & partition map (5 topics total)

| Topic | Partition key | Emitted by | Consumed by |
|---|---|---|---|
| `crm.events.purchase` | `purchase_id` | `chokepoint_post_purchase_event` | Currency, Tier, Mission, AMP, OutcomeAttribution |
| `crm.events.purchase_item` | `purchase_id` (parent + items co-partition) | `chokepoint_post_purchase_event` | Currency, AMP |
| `crm.events.wallet` | `user_id` | `chokepoint_post_wallet_transaction` | Tier, Mission, AMP, OutcomeAttribution |
| `crm.events.tier_change` | `user_id` | `chokepoint_post_tier_change` | AMP |
| `crm.events.user` | `user_id` | `chokepoint_post_user_event` | AMP |

All consumer dedup keys are kept identical to the legacy Debezium-path keys, so a CDC event and a chokepoint event for the same row collapse to one downstream side effect during dual-run.

---

## What's already deployed (overnight, autonomous)

### DB (Supabase, project `wkevmsedchftztoolkmi`)

Four additive migrations applied via `apply_migration`. **No chokepoint behavior change yet** — none of the 4 chokepoints emit to the outbox.

1. **`chokepoint_event_outbox_table_v1`** — new `public.chokepoint_event_outbox` with bigserial PK, `(topic, partition_key, payload jsonb, created_at, published_at, publish_attempts, last_error)`, CHECK enforcing `topic ~ '^crm\.events\.[a-z_]+$'`, two partial indexes (unpublished + cleanup).
2. **`chokepoint_emit_event_helper_v1`** — `fn_chokepoint_emit_event(p_topic, p_partition_key, p_payload) → bigint` SECURITY DEFINER. INSERT + `pg_notify('chokepoint_outbox_new', id::text)`. EXECUTE granted only to `postgres` and `service_role`. **Single helper used by all 4 chokepoints** — no duplication.
3. **`chokepoint_outbox_cleanup_cron_v1`** — `pg_cron` job daily 03:00 UTC, deletes published rows older than 7d.
4. **`chokepoint_outbox_health_view_v1`** — view `v_chokepoint_outbox_health` (per-topic + total).

Phase A smoke verified: 3 synthetic rows inserted via helper across 2 topics, view returned correct stats, bad topic correctly rejected with sqlstate `22023`, cron registered as jobid 51.

### Code drafted in `crm-event-processors/` working tree (NOT pushed)

- `src/workers/outbox-publisher.ts` — chokepoint-agnostic worker; routes by `topic` column
- `src/config.ts` — 5 new topic constants + `outboxPublisher` env block + `flags.chokepointEventsEnabled`
- `src/index.ts` — gated `OutboxPublisher` instantiation + shutdown wiring
- `src/consumers/currency-consumer.ts` — gated dual-read of `crm.events.purchase` + `crm.events.purchase_item`
- `src/consumers/tier-consumer.ts` — gated dual-read of `crm.events.purchase` + `crm.events.wallet`
- `src/consumers/mission-consumer.ts` — gated dual-read of `crm.events.purchase` + `crm.events.wallet` (with `extractChokepointSourceInfo` helper)
- `src/consumers/amp-consumer.ts` — gated dual-read of all 5 chokepoint topics; per-topic dispatch with legacy-matching dedup keys
- `src/consumers/outcome-attribution-consumer.ts` — gated dual-read of `crm.events.purchase` + `crm.events.wallet`
- `package.json` — added `pg` + `@types/pg`
- `README.md` — Consumers table reflects all 5 new topic subscriptions

### Workspace docs

- `requirements/REGISTRY_SUPABASE.md` — regenerated; new "Chokepoint Outbox" section
- `requirements/REGISTRY_RENDER.md` — added `chokepoint_outbox_cleanup` cron + updated worker line
- `requirements/CHANGELOG.md` — entry under 2026-05-14
- `.cursor/plans/chokepoint-kafka-publisher.md` — Status block updated

---

## Morning execution sequence

**Total estimated time:** 50–70 minutes including soak start. Soak runs in background after step 11.

### Step 1 — Confluent Cloud topic provisioning (manual, ~10 min)

Create 5 topics on the cluster (`pkc-ox31np.ap-southeast-7.aws.confluent.cloud`). All use the same settings:

```
Partitions:        6
Retention:         7 days  (retention.ms = 604800000)
Cleanup policy:    delete
Compression:       gzip
```

Topic names:
- `crm.events.purchase`
- `crm.events.purchase_item`
- `crm.events.wallet`
- `crm.events.tier_change`
- `crm.events.user`

> **Why 6 partitions:** matches existing `crm.public.*` topic config so consumer SLO stays the same. Per-aggregate ordering preserved by partition key (purchase_id for purchase + items; user_id for wallet/tier/user).

> **Why same settings for all 5:** simpler ops, all chokepoints have similar throughput characteristics, and the worker handles compression uniformly. Tune per topic later if a real volume mismatch emerges.

### Step 2 — Confluent API key (manual, ~3 min)

Create one Cloud API key:

- **Name:** `chokepoint-publisher`
- **Description:** "Render outbox-publisher worker → crm.events.* topics. Created 2026-05-14."
- **ACLs:** `WRITE` + `DESCRIBE` on `crm.events.*` (prefix). Single ACL covers all 5 topics.

Save the key + secret for step 4.

### Step 3 — Review and merge the `crm-event-processors` PR (manual, ~15 min)

Drafted files are uncommitted in your local worktree. From that repo:

```bash
cd crm-event-processors
git status                     # 7 modified + 1 new file (workers/outbox-publisher.ts)
git diff src/workers/          # spot-check the new worker
git diff src/consumers/        # spot-check all 5 gated consumers
git checkout -b chokepoint-kafka-pipeline
git add -A
git commit -m "chokepoint outbox publisher + dual-read on all 4 chokepoints"
git push -u origin chokepoint-kafka-pipeline
gh pr create --title "Chokepoint → Kafka pipeline (silver tier, all 4 chokepoints)" --body "..."
```

PR review focus:
- `outbox-publisher.ts` — SKIP LOCKED + per-row publish + LISTEN/NOTIFY (chokepoint-agnostic; routes by row's `topic`)
- Each consumer — confirm dedup keys match legacy path so dual-run dedupes
- AMP consumer — confirm new per-chokepoint dispatch shapes (`wallet_ledger`, `tier_change_ledger`, `user_accounts` table names mirror legacy)

Merge, Render auto-deploys.

### Step 4 — Render env vars on `crm-event-processors` (manual, ~3 min)

```
KAFKA_OUTBOX_API_KEY=<from step 2>
KAFKA_OUTBOX_API_SECRET=<from step 2>
SUPABASE_DB_DIRECT_URL=postgresql://postgres:<password>@db.wkevmsedchftztoolkmi.supabase.co:5432/postgres
OUTBOX_PUBLISHER_BATCH_SIZE=500
OUTBOX_PUBLISHER_POLL_INTERVAL_MS=1000
OUTBOX_PUBLISHER_MAX_ATTEMPTS=10
OUTBOX_PUBLISHER_WORK_POOL_MAX=4
OUTBOX_PUBLISHER_ENABLED=false      # leave false initially
CHOKEPOINT_EVENTS_ENABLED=false     # leave false initially
```

> Get `SUPABASE_DB_DIRECT_URL` from: Supabase dashboard → Project Settings → Database → Connection string → "Direct connection" (NOT pooler).

### Step 5 — Verify deploy clean with both flags off (~1 min)

In Render logs, confirm:
- `[OutboxPublisher] OUTBOX_PUBLISHER_ENABLED=false; not starting`
- Each consumer: `Subscribed: <legacy topics> (chokepointEvents=false)` — only legacy CDC subscribed

### Step 6 — Flip `OUTBOX_PUBLISHER_ENABLED=true` and restart (~2 min)

Worker is now armed and will sit idle (outbox empty until A5 migrations land):

```
[OutboxPublisher] Started. batch=500, pollIntervalMs=1000, maxAttempts=10, dedicatedKafkaCreds=true
```

### Step 7 — Apply the 4 queued A5 migrations (DB, ~5 min)

These wire `fn_chokepoint_emit_event(...)` into each chokepoint. **Apply in order; smoke-test after each:**

| # | Migration | Touches |
|---|---|---|
| A5a | `chokepoint_post_purchase_event_emit_v1` | adds emit calls to all 12 event branches of the purchase chokepoint |
| A5b | `chokepoint_post_wallet_transaction_emit_v1` | one emit at the end of the function (single insert per call) |
| A5c | `chokepoint_post_tier_change_emit_v1` | one emit at the end of the function |
| A5d | `chokepoint_post_user_event_emit_v1` | one emit per branch (create / update / soft_delete / hard_delete) |

After each migration, smoke-check via the matching DO block in Appendix B. Skeleton SQL for each migration is in Appendix A.

> **Order matters why:** if anything goes wrong with A5a (the most complex), you can revert just it without affecting wallet/tier/user pipelines. Apply purchase first because it's the highest-risk; apply user last because it's also high-risk (touches login flow).

### Step 8 — Smoke test from UI (~5 min)

Trigger one of each event type:
- Complete one purchase → expect 1× `crm.events.purchase` + N× `crm.events.purchase_item` + 1× `crm.events.wallet` (currency award) + maybe 1× `crm.events.tier_change` (if tier flips)
- Soft-delete one test user → expect 1× `crm.events.user`

Verify outbox drains within seconds:

```sql
SELECT topic, count(*) FILTER (WHERE published_at IS NULL) AS unpublished,
       count(*) AS total,
       max(now() - created_at) FILTER (WHERE published_at IS NULL) AS oldest_age
  FROM public.chokepoint_event_outbox
 WHERE created_at > now() - interval '5 minutes'
 GROUP BY topic;
```

Verify on Confluent: messages appearing on all 5 topics with correct payload shape.

### Step 9 — Flip `CHOKEPOINT_EVENTS_ENABLED=true` (~2 min)

Restart Render. In logs, every consumer's `Subscribed:` line now lists the chokepoint topics it reads:

```
[CurrencyConsumer]         Subscribed: ..., crm.events.purchase, crm.events.purchase_item (chokepointEvents=true)
[TierConsumer]             Subscribed: ..., crm.events.purchase, crm.events.wallet         (chokepointEvents=true)
[MissionConsumer]          Subscribed: ..., crm.events.purchase, crm.events.wallet         (chokepointEvents=true)
[AmpConsumer]              Subscribed: ..., crm.events.purchase, crm.events.purchase_item, crm.events.wallet, crm.events.tier_change, crm.events.user (chokepointEvents=true)
[OutcomeAttribution]       Subscribed: ..., crm.events.purchase, crm.events.wallet         (chokepointEvents=true)
```

Both pipelines now active. Redis dedup catches the duplicates.

### Step 10 — 24h dual-run soak

Health queries:

```sql
-- Outbox health snapshot
SELECT * FROM public.v_chokepoint_outbox_health;

-- Hourly publish rate per topic
SELECT date_trunc('hour', created_at) AS hr,
       topic,
       count(*) AS emitted,
       count(*) FILTER (WHERE published_at IS NOT NULL) AS published,
       count(*) FILTER (WHERE last_error IS NOT NULL) AS errored,
       max(publish_attempts) AS max_attempts
  FROM public.chokepoint_event_outbox
 WHERE created_at > now() - interval '24 hours'
 GROUP BY 1, 2 ORDER BY 1 DESC, 2;

-- Worst stuck rows
SELECT id, topic, partition_key, publish_attempts,
       left(last_error, 200) AS err, created_at
  FROM public.chokepoint_event_outbox
 WHERE published_at IS NULL AND created_at < now() - interval '5 minutes'
 ORDER BY id LIMIT 20;
```

Healthy soak signals (all 5 topics):
- `unpublished_stale = 0` for every topic
- `errored = 0` for every topic
- `oldest_unpublished_age` < 5 seconds typical
- `max_attempts_unpublished` = 0 or 1
- Confluent topic message rate ≈ chokepoint call rate per topic
- Redis dedup hit rate roughly **doubles** for each (source_table, id) pair (proof both pipelines fire)
- No double-awards in `wallet_ledger` (currency dedup absorbed)
- No duplicate AMP dispatches (AMP dedup absorbed)
- No duplicate tier evaluations (tier dedup absorbed)

### Step 11 — Decommission Debezium for all 4 tables (after 24h healthy)

Single migration drops all 4:

```sql
ALTER PUBLICATION crm_cdc_publication
  DROP TABLE purchase_ledger,
             wallet_ledger,
             tier_change_ledger,
             user_accounts;
```

After this:
- Debezium stops emitting to `crm.public.purchase_ledger`, `wallet_ledger`, `tier_change_ledger`, `user_accounts`
- Consumers' fallback subscriptions on these topics stop receiving messages
- `crm.events.*` is now the sole source of truth for these 4 entity types
- WAL retention pressure on the `crm_cdc_slot` drops (these are 4 of the highest-volume tables)

> **`form_submissions` and `amp_workflow_log` stay on Debezium** — they don't have a chokepoint today. Future work: build `chokepoint_post_form_submission_event` and `chokepoint_post_amp_workflow_event`, repeat the same pattern, then decommission their CDC paths.

Optional follow-up PR: remove the legacy `crm.public.*` topics from each consumer's `subscribe()` topic list and remove the legacy switch branches. Not urgent.

---

## Rollback plan (per layer, independent)

| Failure | Action | Blast radius |
|---|---|---|
| Any A5 migration breaks something | Revert that specific A5 (capture body via `pg_get_functiondef` before applying) | Only that chokepoint stops emitting; other 3 chokepoints + worker + consumers unaffected |
| Worker crashes / can't publish | `OUTBOX_PUBLISHER_ENABLED=false`, restart Render | All 4 chokepoints still commit (atomicity at outbox INSERT preserved). Outbox grows; drain after fix. |
| Consumer breaks on chokepoint payload shape | `CHOKEPOINT_EVENTS_ENABLED=false`, restart | All consumers fall back to Debezium path. Old behavior fully restored. |
| Confluent down for one topic | KafkaJS retries; outbox queues for that topic; other 4 keep flowing | Per-topic transient backpressure |

---

## Validation gate before declaring "done"

- [ ] `v_chokepoint_outbox_health.unpublished_stale = 0` for **all 5 topics** over 24h
- [ ] Zero `errored` rows for any topic
- [ ] Confluent shows healthy publish rate matching chokepoint call rate on all 5 topics
- [ ] No double-awards in `wallet_ledger` from dual-run
- [ ] No duplicate AMP dispatches in `amp_workflow_log` (check via dedup hit rate)
- [ ] Drop 4 tables from CDC publication and confirm `crm.public.*` topic message rates go to 0

---

## What stays untouched

- Other 2 CDC paths still on Debezium: `form_submissions`, `amp_workflow_log` (no chokepoint exists for these yet)
- `RewardConsumer`, `MarketplaceConsumer` — they don't read any of the 4 chokepoint surfaces

---

## Appendix A — Queued A5 migration skeletons

> **Apply pattern:** in the morning, fetch each chokepoint body via `pg_get_functiondef`, then add the emit calls per the routing tables below. The diff per chokepoint is small (1–4 emit calls); the bodies themselves don't change otherwise.
>
> **Backfill escape hatch (all 4 chokepoints):** honor `p_metadata->>'_skip_emit' = 'true'` (or equivalent payload key per chokepoint) so backfill scripts and recursive chokepoint-to-chokepoint calls don't double-emit.

### A5a — `chokepoint_post_purchase_event_emit_v1`

Per-event emit summary:

| Event branch | Emits per call |
|---|---|
| `created` | 1× `crm.events.purchase` per inserted purchase + N× `crm.events.purchase_item` per inserted item |
| `updated` | 1× `crm.events.purchase` (only if `status` / `payment_status` / `*_amount` actually changed) |
| `completed` | 1× `crm.events.purchase` (only when row actually flipped) |
| `cancelled` | 1× `crm.events.purchase` (only when row actually flipped) |
| `refunded` | 1× `crm.events.purchase` for the original purchase status flip when fully refunded; the recursive `created` call for the debit row passes `_skip_emit=true` |
| `promo_applied` | 1× `crm.events.purchase` |
| `items_added` | N× `crm.events.purchase_item` per inserted item |
| `items_replaced` | N× `crm.events.purchase_item` per new item (no events for deleted items) |
| `item_quantity_completed` | K× `crm.events.purchase_item` only for items that flipped to `completed` (skip partials); parent rollup emit fires via the recursive `completed` call |
| `item_completion_set` | K× `crm.events.purchase_item` only for items that flipped to `completed` on this call (forward only); parent rollup emit fires via the recursive `completed` call |
| `item_cancelled` | N× `crm.events.purchase_item` per item updated to `cancelled` |
| `item_refunded` | N× `crm.events.purchase_item` per item updated to `refunded` |

Parent emit pattern (re-join `user_id` + `earn_currency` from the affected purchases):

```sql
IF COALESCE(p_payload->>'_skip_emit','false') <> 'true' THEN
  FOR v_emit_purchase IN
    SELECT id, user_id, earn_currency, status::text AS status_text,
           final_amount, total_amount
      FROM public.purchase_ledger
     WHERE id = ANY (v_txn_ids)
  LOOP
    PERFORM public.fn_chokepoint_emit_event(
      'crm.events.purchase',
      v_emit_purchase.id::text,
      jsonb_build_object(
        'event',         p_event,
        'merchant_id',   p_merchant_id,
        'purchase_id',   v_emit_purchase.id,
        'user_id',       v_emit_purchase.user_id,
        'earn_currency', v_emit_purchase.earn_currency,
        'status',        v_emit_purchase.status_text,
        'final_amount',  v_emit_purchase.final_amount,
        'total_amount',  v_emit_purchase.total_amount,
        'occurred_at',   to_jsonb(now()),
        'source',        'chokepoint_post_purchase_event'
      )
    );
  END LOOP;
END IF;
```

Item emit pattern (note `partition_key` is still `purchase_id` so parent + items co-partition):

```sql
PERFORM public.fn_chokepoint_emit_event(
  'crm.events.purchase_item',
  v_purchase_id::text,                       -- still purchase_id, NOT item_id
  jsonb_build_object(
    'event',         p_event,
    'merchant_id',   p_merchant_id,
    'purchase_id',   v_purchase_id,
    'item_id',       v_item_record.id,
    'user_id',       v_emit_user_id,
    'earn_currency', v_emit_earn_currency,
    'item_status',   v_item_record.status::text,
    'occurred_at',   to_jsonb(now()),
    'source',        'chokepoint_post_purchase_event'
  )
);
```

### A5b — `chokepoint_post_wallet_transaction_emit_v1`

The wallet chokepoint inserts exactly one `wallet_ledger` row per call. Add ONE emit at the end (after the `INSERT ... RETURNING id INTO v_wallet_id` that already exists in the body), before `RETURN`:

```sql
IF COALESCE(p_metadata->>'_skip_emit','false') <> 'true' THEN
  PERFORM public.fn_chokepoint_emit_event(
    'crm.events.wallet',
    p_user_id::text,                         -- partition by user for per-user ordering
    jsonb_build_object(
      'event',             'wallet_transaction',
      'merchant_id',       p_merchant_id,
      'user_id',           p_user_id,
      'wallet_ledger_id',  v_wallet_id,
      'currency',          p_currency::text,
      'component',         p_component::text,
      'transaction_type',  p_transaction_type::text,
      'amount',            p_amount,
      'source_type',       p_source_type::text,
      'source_id',         p_transaction_id,
      'description',       p_description,
      'target_entity_id',  p_target_entity_id,
      'occurred_at',       to_jsonb(now()),
      'source',            'chokepoint_post_wallet_transaction'
    )
  );
END IF;
```

> The actual `INSERT ... RETURNING` variable name in the live function may differ from `v_wallet_id` — fetch `pg_get_functiondef` first and adapt.

### A5c — `chokepoint_post_tier_change_emit_v1`

The tier chokepoint inserts exactly one `tier_change_ledger` row per call. One emit at the end:

```sql
IF COALESCE(p_metadata->>'_skip_emit','false') <> 'true' THEN
  PERFORM public.fn_chokepoint_emit_event(
    'crm.events.tier_change',
    p_user_id::text,
    jsonb_build_object(
      'event',                   'tier_change',
      'merchant_id',             p_merchant_id,
      'user_id',                 p_user_id,
      'tier_change_ledger_id',   v_change_id,
      'from_tier_id',            p_from_tier_id,
      'to_tier_id',              p_to_tier_id,
      'change_type',             p_change_type::text,
      'change_reason',           p_change_reason,
      'metadata',                p_metadata,
      'skip_cdc',                COALESCE((p_metadata->>'skip_cdc')::boolean, false),
      'occurred_at',             to_jsonb(now()),
      'source',                  'chokepoint_post_tier_change'
    )
  );
END IF;
```

> AMP consumer reads `skip_cdc` from this payload and skips dispatch when true (mirroring the legacy `WHERE NOT skip_cdc` filter).

### A5d — `chokepoint_post_user_event_emit_v1`

The user chokepoint dispatches on a 4-event taxonomy (`create`, `update`, `soft_delete`, `hard_delete`). Add one emit per branch, after the row mutation succeeds. Pre-snapshot the post-mutation row for AMP's `user_after` read:

```sql
-- After the INSERT/UPDATE/DELETE succeeds, snapshot the row (if still extant):
SELECT to_jsonb(ua) INTO v_user_after
  FROM public.user_accounts ua
 WHERE ua.id = COALESCE(v_user_id_inserted, p_user_id);

IF COALESCE(p_metadata->>'_skip_emit','false') <> 'true' THEN
  PERFORM public.fn_chokepoint_emit_event(
    'crm.events.user',
    COALESCE(v_user_id_inserted, p_user_id)::text,
    jsonb_build_object(
      'event',             p_event_type,            -- 'create' / 'update' / 'soft_delete' / 'hard_delete'
      'user_event_type',   p_event_type,            -- duplicate so consumer can filter
      'merchant_id',       p_merchant_id,
      'user_id',           COALESCE(v_user_id_inserted, p_user_id),
      'changes',           p_changes,
      'actor',             p_actor,
      'skip_cdc',          p_skip_cdc,
      'user_after',        v_user_after,            -- post-mutation row snapshot for AMP
      'occurred_at',       to_jsonb(now()),
      'source',            'chokepoint_post_user_event'
    )
  );
END IF;
```

> AMP fires only on `event='create'` AND `skip_cdc=false` (mirroring legacy `op='c' AND NOT skip_cdc`).
> For `hard_delete`, `v_user_after` will be `NULL` — that's fine; the AMP consumer doesn't fire on hard_delete anyway.

---

## Appendix B — Per-chokepoint smoke harnesses

### B1 — Purchase smoke (after A5a)

```sql
BEGIN;
DO $$
DECLARE
  v_test_merchant uuid := '<your_test_merchant_id>';
  v_test_user     uuid := '<your_test_user_id>';
  v_outbox_before bigint;
  v_outbox_after  bigint;
  v_result        jsonb;
BEGIN
  SELECT count(*) INTO v_outbox_before FROM public.chokepoint_event_outbox;

  v_result := public.chokepoint_post_purchase_event('created', v_test_merchant,
    jsonb_build_object('rows', jsonb_build_array(jsonb_build_object(
      'transaction_number', 'A5A-SMOKE-' || extract(epoch from now())::bigint,
      'user_id',            v_test_user,
      'final_amount',       100,
      'total_amount',       100,
      'status',             'completed',
      'earn_currency',      true,
      'items', jsonb_build_array(
        jsonb_build_object('product_name', 'A5a smoke 1', 'quantity', 1, 'unit_price', 50),
        jsonb_build_object('product_name', 'A5a smoke 2', 'quantity', 1, 'unit_price', 50)
      )
    )))
  );

  SELECT count(*) INTO v_outbox_after FROM public.chokepoint_event_outbox;
  ASSERT v_outbox_after - v_outbox_before = 3,
    'expected 3 emits (1 parent + 2 items) but got ' || (v_outbox_after - v_outbox_before);
  RAISE NOTICE 'A5a OK: % outbox rows added', v_outbox_after - v_outbox_before;
END $$;
ROLLBACK;
```

### B2 — Wallet smoke (after A5b)

```sql
BEGIN;
DO $$
DECLARE
  v_test_merchant uuid := '<your_test_merchant_id>';
  v_test_user     uuid := '<your_test_user_id>';
  v_outbox_before bigint;
  v_outbox_after  bigint;
BEGIN
  SELECT count(*) INTO v_outbox_before FROM public.chokepoint_event_outbox;

  PERFORM public.chokepoint_post_wallet_transaction(
    p_user_id          := v_test_user,
    p_currency         := 'points'::currency,
    p_source_type      := 'adjustment'::wallet_transaction_source_type,
    p_component        := 'adjustment'::currency_component,
    p_transaction_type := 'earn'::currency_transaction_type,
    p_amount           := 1,
    p_transaction_id   := gen_random_uuid(),
    p_merchant_id      := v_test_merchant,
    p_description      := 'A5b smoke',
    p_dedup_key        := 'A5B-SMOKE-' || extract(epoch from now())::bigint
  );

  SELECT count(*) INTO v_outbox_after FROM public.chokepoint_event_outbox;
  ASSERT v_outbox_after - v_outbox_before = 1,
    'expected 1 emit but got ' || (v_outbox_after - v_outbox_before);
  RAISE NOTICE 'A5b OK';

  -- Inspect
  RAISE NOTICE '%', (SELECT to_jsonb(o) FROM public.chokepoint_event_outbox o ORDER BY id DESC LIMIT 1);
END $$;
ROLLBACK;
```

### B3 — Tier smoke (after A5c)

```sql
BEGIN;
DO $$
DECLARE
  v_test_merchant uuid := '<your_test_merchant_id>';
  v_test_user     uuid := '<your_test_user_id>';
  v_test_tier     uuid := '<some_existing_tier_id_in_that_merchant>';
  v_outbox_before bigint;
  v_outbox_after  bigint;
BEGIN
  SELECT count(*) INTO v_outbox_before FROM public.chokepoint_event_outbox;

  PERFORM public.chokepoint_post_tier_change(
    p_user_id        := v_test_user,
    p_merchant_id    := v_test_merchant,
    p_from_tier_id   := NULL,
    p_to_tier_id     := v_test_tier,
    p_change_type    := 'upgrade'::tier_change_type,
    p_change_reason  := 'A5c smoke',
    p_metadata       := jsonb_build_object('skip_cdc', true)  -- avoid AMP dispatch in smoke
  );

  SELECT count(*) INTO v_outbox_after FROM public.chokepoint_event_outbox;
  ASSERT v_outbox_after - v_outbox_before = 1,
    'expected 1 emit but got ' || (v_outbox_after - v_outbox_before);
  RAISE NOTICE 'A5c OK';
END $$;
ROLLBACK;
```

### B4 — User smoke (after A5d)

```sql
BEGIN;
DO $$
DECLARE
  v_test_merchant uuid := '<your_test_merchant_id>';
  v_outbox_before bigint;
  v_outbox_after  bigint;
  v_user          public.user_accounts;
BEGIN
  SELECT count(*) INTO v_outbox_before FROM public.chokepoint_event_outbox;

  v_user := public.chokepoint_post_user_event(
    p_event_type    := 'create',
    p_merchant_id   := v_test_merchant,
    p_changes       := jsonb_build_object(
      'firstname', 'Smoke',
      'lastname',  'A5d',
      'tel',       '+66' || (extract(epoch from now())::bigint % 1000000000)::text
    ),
    p_skip_cdc      := true,
    p_metadata      := jsonb_build_object('source', 'A5d-smoke')
  );

  SELECT count(*) INTO v_outbox_after FROM public.chokepoint_event_outbox;
  ASSERT v_outbox_after - v_outbox_before >= 1,
    'expected at least 1 emit but got ' || (v_outbox_after - v_outbox_before);
  RAISE NOTICE 'A5d OK: created user_id=%', v_user.id;
END $$;
ROLLBACK;
```

> Note B3 and B4 set `skip_cdc=true` in metadata to avoid generating AMP-visible test events. The chokepoint still emits to the outbox (skip_cdc only suppresses AMP dispatch downstream); B3 / B4 verify the emit count.

---

## Appendix C — Useful reference queries

```sql
-- Capture each chokepoint body before applying its A5 (for rollback reference)
SELECT pg_get_functiondef('public.chokepoint_post_purchase_event'::regproc);
SELECT pg_get_functiondef('public.chokepoint_post_wallet_transaction'::regproc);
SELECT pg_get_functiondef('public.chokepoint_post_tier_change'::regproc);
SELECT pg_get_functiondef('public.chokepoint_post_user_event'::regproc);

-- Outbox table size + index sizes
SELECT pg_size_pretty(pg_total_relation_size('public.chokepoint_event_outbox')) AS total,
       pg_size_pretty(pg_relation_size('public.chokepoint_event_outbox')) AS heap,
       pg_size_pretty(pg_indexes_size('public.chokepoint_event_outbox')) AS indexes;

-- Cron job status
SELECT jobid, jobname, schedule, active, last_run_started_at, last_successful_run
  FROM cron.job WHERE jobname = 'chokepoint_outbox_cleanup';

-- Per-topic rate over last 5 minutes
SELECT topic,
       count(*) AS emitted,
       count(*) FILTER (WHERE published_at IS NOT NULL) AS published,
       round(avg(extract(epoch from (published_at - created_at)))::numeric, 3) AS avg_publish_latency_s
  FROM public.chokepoint_event_outbox
 WHERE created_at > now() - interval '5 minutes'
 GROUP BY topic;

-- Confirm CDC publication state before / after step 11
SELECT pubname, schemaname, tablename
  FROM pg_publication_tables
 WHERE pubname = 'crm_cdc_publication'
 ORDER BY tablename;
```
