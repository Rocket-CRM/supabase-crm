# Jorakay drift — master list + 5-user deep dive

**As of:** 2026-09-12  
**Drift users:** **153** (83 wallet > lots, 70 lots > wallet) of 24,602 wallets  
**Full list query:** `drift-list.sql` (run in Supabase SQL editor → export CSV)

## Five users selected

| # | mongo_id | Pattern | Δ (wallet − lots) | Native CRM rows |
|---|----------|---------|-------------------|-----------------|
| 1 | `65413f78d6b1732a1ec616f1` | Lots massively high | −82,112 | 7 |
| 2 | `6811e84c6fc1032760808710` | Wallet high, lots under Mongo | +8,227 | 1 |
| 3 | `65e992956fdff6649db70844` | Wallet high, lots zero | +3,415 | 0 |
| 4 | `65413f89d6b1732a1ec6255d` | Wallet = Mongo headline, lots high | −1,151 | 0 |
| 5 | `67cd2a13865b399021ce9895` | Wallet high, partial expiry | +3,441 | 1 |

---

## User 1 — `65413f78d6b1732a1ec616f1` (`465dae9a-01fa-49ca-b3f1-957deb899d5d`)

### Current (New CRM)

| | Value |
|---|------|
| Wallet | 43,361 |
| Σ open lots | 125,473 |
| Δ | −82,112 |

### Mongo (live)

| | Value |
|---|------|
| `contacts.pointBalance` | 35,313 |
| Σ open `GIVEN.balance` (20 rows) | 40,783 |
| Last GIVEN/REDEEMED | 2026-07-07 |

### New CRM activity (native)

Seven purchase earns after last Mongo activity, Σ **8,048** pts (Aug–Sep 2026). **Wallet already matches:** 35,313 + 8,048 = **43,361** → **no wallet change**.

### Root cause (lots)

| Bucket | Earn rows | Current Σ deductible | Should be |
|--------|-----------|----------------------|-----------|
| Mongo `GIVEN.balance = 0` (consumed in old CRM) | 135 | **35,313** | **0** — consumed lots must not stay open |
| Mongo open GIVEN (20 ids) | 20 | **82,112** | **40,783** — each row = live Mongo `balance` on that `_id` |
| Native purchase earns | 7 | 8,048 | 8,048 (keep) |

After correction, Σ lots = **40,783 + 8,048 = 48,831** (not 43,361).

### Residual gap (not forced)

Mongo headline **35,313** is **5,470** below Σ open GIVEN **40,783** (old CRM quirk). New CRM needs a **named** treatment for that 5,470 (e.g. triggered expiry on specific earns with `expiry_date` ≤ last Mongo activity day **without** wallet movement — wallet already reflects headline). **Do not** blindly shrink lots to wallet.

### Proposed edits (proposal only)

1. **UPDATE** 135 earns: `deductible_balance = 0` where live Mongo `GIVEN.balance = 0` (reason: consumed in old CRM).
2. **UPDATE** 20 earns: set `deductible_balance` = live Mongo `balance` per `mongo_id` (reason: mirror open lots).
3. **Leave** `user_wallet` at 43,361.
4. **Then** apply expiry rules on the 20 open rows + native replay for any New CRM burns that should FIFO (none listed beyond earns).
5. **Re-run check**; if wallet ≠ lots, resolve 5,470 with per-lot expiry reasons (step 1 triggered vs step 3 inactive).

---

## User 2 — `6811e84c6fc1032760808710` (`6cce9025-1504-49f5-a51a-02c0aefd576b`)

### Current

| Wallet | Lots | Δ |
|--------|------|---|
| 9,859 | 1,632 | +8,227 |

### Mongo

| `pointBalance` | Σ open GIVEN | Last activity |
|----------------|--------------|---------------|
| 9,259 | 9,259 (5 GIVEN, 6 ledger rows) | 2025-11-03 |

### Native

One purchase earn **600** (2026-07-22). **Wallet matches:** 9,259 + 600 = **9,859** → **no wallet change**.

### Root cause

Migrated earns sum **1,032** deductible vs **9,259** on live Mongo open GIVEN. Closed Mongo earns already at 0 deductible. Lots under-state open Mongo balance.

### Target

| Wallet | Σ lots |
|--------|--------|
| 9,859 | 9,259 + 600 = **9,859** |

### Proposed edits

1. **UPDATE** each migrated earn: `deductible_balance` = live Mongo `GIVEN.balance` for that `mongo_id` (0 if consumed).
2. **No change** to native earn (600).
3. **No change** to wallet.

---

## User 3 — `65e992956fdff6649db70844` (`2e9794f1-5f7b-4e41-ab8d-43e6b2c03779`)

### Current

| Wallet | Lots | Δ |
|--------|------|---|
| 3,415 | 0 | +3,415 |

### Mongo

| `pointBalance` | Σ open GIVEN | Open rows |
|----------------|--------------|-----------|
| 3,733 | 318 (62 + 256) | 2 GIVEN, expiredDate Jul 2025 |

Last Mongo activity 2024-08-14.

### New CRM

- 144 migrated earns, all **deductible 0** (TTL step-1 style zeroing).
- One native row: **expiry burn 318** (`TTL historical repair expiry for 2025-07-22`).
- Wallet **3,415** = 3,733 − 318 (burn posted; lots already 0).

### Target

| Wallet | Lots |
|--------|------|
| **3,415** (headline after inactive expiry burn) | **318** on the two open Mongo GIVEN earns (`669e24c5…` → 62, `669e3934…` → 256) |

After restoring lots, wallet ≠ lots by **3,097** unless those 318 are **inactive-expired** (expiry passed, no Mongo activity after) → then **zero both lots** and **additional wallet burn 318** → wallet **3,097**? That contradicts current wallet.

**Interpretation:** Current wallet **3,415** is consistent with **pointBalance minus one expiry burn** while **open Mongo lots 318** still exist in Mongo. New CRM must either:

- **A)** Restore **318** lot balance and treat **3,097** as wallet-only legacy (hold / Track B), or  
- **B)** Zero the two earns (inactive expiry) and **reduce wallet by 318** to **3,097** (if product accepts lower spendable than today).

### Proposed edits (need product pick on A vs B)

1. **UPDATE** two earns: set `deductible_balance` to Mongo `balance` (62, 256) — **if** spendable stays 3,415 (option A, still imbalanced until 3,097 resolved).
2. **OR** inactive expiry on those two earns + **wallet −318** (option B, wallet = 3,097, lots = 0, balanced).

No native earns to replay.

---

## User 4 — `65413f89d6b1732a1ec6255d` (`d093dcaf-0507-4d3f-a899-4ab57adf5444`)

### Current

| Wallet | Lots | Δ |
|--------|------|---|
| 12,544 | 13,695 | −1,151 |

### Mongo

| `pointBalance` | Σ open GIVEN (live) |
|----------------|---------------------|
| **12,544** | **12,544** |

Wallet **already equals Mongo headline**. No native activity.

### Root cause

Σ CRM deductible **13,695** on migrated earns is **1,151** above live Mongo open lot sum. Per-id CRM deductible exceeds live Mongo `balance` on at least one earn (e.g. +237 vs staging); total gap vs live Mongo = **1,151**.

### Target

| Wallet | Lots |
|--------|------|
| 12,544 | 12,544 |

### Proposed edits

1. **UPDATE** earns where `deductible_balance` > live Mongo `GIVEN.balance`: set to Mongo `balance` (reason: redemption/expiry already reflected in Mongo).
2. **UPDATE** earns where Mongo `balance = 0`: set `deductible_balance = 0`.
3. **No wallet change.**

---

## User 5 — `67cd2a13865b399021ce9895` (`6d60ddf9-c4b2-4186-9714-6cfe86aca1d4`)

### Current

| Wallet | Lots | Δ |
|--------|------|---|
| 7,469 | 4,028 | +3,441 |

### Mongo

| `pointBalance` | Σ open GIVEN |
|----------------|--------------|
| 7,226 | 7,226 |

### Native / expiry (New CRM)

| Event | Pts |
|-------|-----|
| Purchase earn | +659 |
| Expiry burns | −228, −188 (= **416**) |

**Wallet check:** 7,226 + 659 − 416 = **7,469** ✓ — wallet trail is coherent.

### Root cause

Lots **4,028** vs wallet **7,469**: migrated deductibles not aligned to Mongo open balances after **New CRM expiry burns** (FIFO on lots likely incomplete — burns hit wallet but not fully allocated on earns).

### Target (method)

1. Set migrated earn deductibles from **live Mongo `GIVEN.balance`** per `mongo_id`.
2. **Replay** native earn (+659) and two expiry burns (−416) in order: expiry should zero specific earns; purchase earn adds lot.
3. End state: **wallet = Σ lots = 7,469**.

### Proposed edits (after row-level replay)

1. **UPDATE** migrated earns to Mongo balances (same pattern as user 2).
2. **UPDATE** FIFO allocation on open earns for the two expiry ledger rows (reduce `deductible_balance` on affected earns by 228 and 188 with `expiry_processed_at` as appropriate).
3. **No wallet change** if replay matches existing burns and earn.

---

## Patterns across the five

| Pattern | Users | Fix class |
|---------|-------|-----------|
| Consumed Mongo GIVEN still have deductible | 1 (major) | Zero + refresh open from Mongo |
| Open Mongo GIVEN under-reported in CRM | 2 | UPDATE deductible from Mongo |
| Wallet OK, lots over Mongo | 4 | UPDATE down to Mongo per id |
| TTL zero all lots; wallet vs open Mongo | 3 | Product call + expiry option A/B |
| Wallet OK after native/expiry; lots not FIFO’d | 5 | Mongo sync + replay native expiry |

**None of the five** need staging orphan scripts. Most fixes are **per-earn `deductible_balance` updates** from **live Mongo `GIVEN.balance`**, then **native event replay** where post-cutover burns/earns exist.

## Next step

Approve fix option for user 3 (A vs B). For users 1, 2, 4, 5, generate row-level UPDATE list (ledger_id, current, target, reason) before any apply.
