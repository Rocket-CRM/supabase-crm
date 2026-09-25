# Daily merchant ops reconciliation

Operator runbook for `fn_ops_daily_recon` — compact daily health check for live loyalty merchants.

## Run

```sql
-- Yesterday (Bangkok)
SELECT public.fn_ops_daily_recon();

-- Specific day
SELECT public.fn_ops_daily_recon('2026-09-01'::date);
```

Used by the Cursor Automation **CRM daily merchant recon** (Supabase MCP → one query → Lark webhook summary).

**Performance (2026-09-17):** Activity-silence metrics pre-aggregate each fact table once over the 28-day Bangkok window (sargable `created_at` bounds), then cross-join only the small merchant×day calendar. Wallet ledger sums are split native vs migrated. The function sets a 5-minute local `statement_timeout` for the run. Call it **once** per automation (`WITH r AS (SELECT fn_ops_daily_recon() j) SELECT … FROM r`) — do not invoke the RPC multiple times in one statement.

## Merchant scope

| Rule | Merchants |
|------|-----------|
| Migrated (`mongo_id` set) | **Only** `herhynessreward`, `jorakay`, `kovet` |
| CRM-native | All except exclusions below |
| Always excluded | `futurepark`, `kaosmileclub` (Ka-Oh!), `rocket-demo`, `ausiris`, `newcrm`, `samitivej`, `qatest`, any `qa-*` / `*.myshopify.com` test shop |

## Output shape (area-first)

Top level: `status`, `day`, `scope`, `areas`.

Each area has `status` (`ok` / `warn`) and `merchants` (only when something is wrong):

| Area | What it checks |
|------|----------------|
| `wallet_integrity` | **Migrated TTL** (`herhynessreward`, `jorakay`, `kovet`): `points_balance` = Σ `deductible_balance` on earn lots (`balance_vs_lots`). **Native**: `points_balance` = Σ `signed_amount` (`balance_vs_ledger`). Open `wallet_reconciliation_issue`; stale unprocessed expired lots. Migrated merchants may include `ledger_audit_gap` (info only — expected post-repair, does not alert). |
| `daily_crons` | `expiry_processing_log`; stale `tier_pending_upgrades`; `system_cron` cache jobs; chokepoint outbox backlog |
| `activity_silence` | Zero activity on day D when 28-day median ≥ 1 (earn, burn, purchases, mkp orders, redemptions, receipt uploads) |
| `marketplace_channel_connection` | Marketplace shops with `disconnected` or `reauth_required` **and** zero orders from that platform on day D. Token expiry is ignored (Shopee hourly refresh is normal). Orders flowing = pass. |
| `pipeline_health` | Marketplace connect errors; stuck earn purchases (post-migration only); failed redemptions. Pre-2026-08-24 earn gaps appear as `earn_migration_backlog` (info only). |

`daily_crons.global` holds platform-wide signals (expiry log, outbox, total stale tier pending). Merchant rows appear only under the area they belong to.

### Wallet integrity — merchant classes

| Class | Detection | Primary check | Escalates? |
|-------|-----------|---------------|------------|
| Migrated TTL | `merchant_code` in `herhynessreward`, `jorakay`, `kovet` | `balance_vs_lots` | Yes, if users > 0 |
| Native / CRM-born | everyone else in scope | `balance_vs_ledger` | Yes, if users > 0 |
| Migrated audit | same three | `ledger_audit_gap` | **No** — informational only |

After [wallet↔lot historical repair](./POINTS_WALLET_LOT_RECONCILIATION.md), migrated merchants intentionally have `wallet = lots ≠ ledger sum` (legacy expiry stamped on earn rows without matching burn rows). Do not backfill synthetic expiry burns.

Pre-cutover stale lots (`expiry_date < 2026-08-31`) may persist until manual backfill — still reported under `stale_expired_lots` as low-severity migration tail.

### Marketplace channel connection

Marketplace ingest is webhook-driven; CRM only needs a valid token at API-fetch time. Shopee tokens refresh hourly, so `expires_at` within hours is **not** an alert.

| Signal | Escalates? |
|--------|------------|
| `disconnected` or `reauth_required` on Shopee/Lazada/TikTok/Shopify **and** `orders_on_day = 0` for that platform | Yes |
| Same status but orders still arriving on that platform | **No** — downstream proof channel works |
| Token expiry alone | **No** — normal refresh cycle |

Example merchant row:

```json
{
  "merchant_code": "example",
  "name": "Example Shop",
  "channels": [
    { "platform": "lazada", "health_status": "disconnected", "shops": 1, "orders_on_day": 0 }
  ]
}
```

### Earn migration backlog (`pipeline_health`)

During the Aug 2026 earn-pipeline cutover (Kafka CDC off, chokepoint outbox not fully live for all receipt/marketplace paths), ~45 purchases from before late August never emitted `crm.events.purchase` and received no wallet credit. Earn has worked since **2026-09-01**; the fix is a one-time backfill for those purchase IDs.

| Signal | Escalates? |
|--------|------------|
| `stuck_earn_purchases` on purchases **on or after** `2026-09-01` (BKK) | Yes |
| `earn_migration_backlog` on purchases **before** `2026-09-01` with no outbox event and no wallet earn | **No** — informational; pending one-time replay |

```json
{
  "earn_migration_backlog": {
    "purchases": 19,
    "note": "known earn-pipeline migration gap (pre-2026-09-01 BKK); crm.events.purchase never fired — one-time backfill pending, not ongoing drift"
  }
}
```

### Example `wallet_integrity` issues JSON

Migrated (operational):

```json
{
  "balance_vs_lots": { "users": 0, "total_delta": 0 },
  "open_recon_issues": { "expiry_lots_exceed_wallet": { "open": 1, "seen_on_day": 1 } },
  "stale_expired_lots": { "lots": 4, "points": 1178 }
}
```

Native:

```json
{
  "balance_vs_ledger": { "users": 2, "total_delta": 162800 },
  "open_recon_issues": { ... },
  "stale_expired_lots": { ... }
}
```

Migrated info-only (when merchant appears for other reasons):

```json
{
  "ledger_audit_gap": {
    "users": 6216,
    "total_delta": 435717,
    "note": "expected post-migration; not operational drift"
  }
}
```

## Automation prompt (summary)

1. Call `select fn_ops_daily_recon();` on project `wkevmsedchftztoolkmi` — **no other SQL** unless a red flag needs one follow-up.
2. Write a short report **by area**, then merchants within each area.
3. **Wallet integrity:** for Her Hyness / Jorakay / Kovet report **wallet vs lots** (`balance_vs_lots`), not ledger sum. If `ledger_audit_gap` is present, one line: “ledger audit gap N pts (expected, ignore)” — do not escalate.
4. Escalate: `balance_vs_lots` > 0 (migrated), `balance_vs_ledger` > 0 (native), `open_recon_issues`, `stale_expired_lots`.
5. **Marketplace channel connection:** escalate only when a platform shows `disconnected`/`reauth_required` **and** `orders_on_day = 0`. Do not mention token expiry or Shopee refresh. Merchants with orders flowing pass regardless of credential status.
6. **Pipeline / stuck earn:** escalate `stuck_earn_purchases` only for purchases on or after 2026-09-01. If `earn_migration_backlog` is present, one line “N purchases pending earn backfill (pre-migration, expected)” — do not escalate.
7. Post full text to Lark webhook.

## Verification (post-deploy)

```sql
-- Should show 0 drift users for HH and Jorakay (wallet vs lots)
SELECT merchant_code, COUNT(*) FILTER (WHERE wallet <> lots) AS drift_users
FROM (
  SELECT m.merchant_code, uw.points_balance AS wallet,
    COALESCE(SUM(wl.deductible_balance) FILTER (
      WHERE wl.transaction_type = 'earn'
    ), 0) AS lots
  FROM merchant_master m
  JOIN user_wallet uw ON uw.merchant_id = m.id
  LEFT JOIN wallet_ledger wl
    ON wl.user_id = uw.user_id
   AND wl.merchant_id = m.id
   AND wl.currency = 'points'
  WHERE m.merchant_code IN ('herhynessreward', 'jorakay')
  GROUP BY m.merchant_code, uw.user_id, uw.points_balance
) t
GROUP BY merchant_code;

SELECT fn_ops_daily_recon();
-- Expect: HH/Jorakay NOT flagged for balance_vs_ledger;
-- only stale lots / open issues if still present
```

## Related

- Wallet/lot repair (migrated TTL): [`POINTS_WALLET_LOT_RECONCILIATION.md`](./POINTS_WALLET_LOT_RECONCILIATION.md)
- Cron registry: [`requirements/REGISTRY_RENDER.md`](../requirements/REGISTRY_RENDER.md)
