# Jorakay drift — 10 more users (data-fix manifests)

**Method:** Derive target **wallet** from live Mongo `contacts.pointBalance` ± **New CRM-only** `wallet_ledger` rows (`mongo_id` IS NULL): earns add, burns/expiry subtract. Derive target **lots** as Σ `deductible_balance` on open earns so **target lots = target wallet**. Compare to current; list **INSERT/UPDATE** only — **no RPCs, no migration scripts, no expiry batch functions.**

**Purchases:** No `purchase_ledger` / receipt changes in these 10 unless a later row-level pass ties a missing earn to a purchase (none identified here).

---

## 6 — `67510f45a33a4dc033969a91` (`ff511b13-f049-40fd-925f-0ef12ee595cb`)

| | Current | Target |
|---|---------|--------|
| Wallet | 118,172 | **128,882** |
| Σ lots | 128,882 | **128,882** |

**Wallet target:** Mongo **87,572** + native earns **41,310** − native burns **0** = **128,882**.  
**Lots:** Migrated open Mongo **87,572** already on deductibles; native earns **41,310** on deductibles — **correct total**.

**Gap:** Wallet **10,710** below ledger net (native earns posted on `wallet_ledger` but `user_wallet` not fully credited).

| Table | Action |
|-------|--------|
| `user_wallet` | **UPDATE** `points_balance` **118,172 → 128,882** (+10,710). |
| `wallet_ledger` | **None** (earns/lots already consistent with target). |
| `purchase_ledger` | **None** |

---

## 7 — `699efc2f2ec2d76e1eae0dd6` (`75b78f9f-5219-4021-9364-c24009c8264a`)

| | Current | Target |
|---|---------|--------|
| Wallet | 13,694 | **13,694** |
| Σ lots | 23,222 | **13,694** |

**Wallet target:** Mongo **36,104** + native earns **145,990** − native burns **168,400** = **13,694** (unchanged).  
**Lots target:** **13,694** — migrated deductibles must match **live Mongo `GIVEN.balance` per `mongo_id`** (Σ open Mongo **36,104** today, not staging **53,894**), then native earns reduced by **FIFO 168,400** against open earns (Mongo redemptions already reflected in migrated balances; burns apply to New CRM earns first, then migrated FIFO).

| Table | Action |
|-------|--------|
| `user_wallet` | **None** |
| `wallet_ledger` (earn) | **UPDATE** each migrated earn: `deductible_balance` = live Mongo `balance` for that `mongo_id` (0 if consumed). **UPDATE** native earn rows: reduce `deductible_balance` by **168,400** total in FIFO `created_at` order (reason: New CRM redemption). Net lot reduction **9,528** (23,222 → 13,694). |
| `wallet_ledger` (burn) | **None** (burn rows exist). |
| `purchase_ledger` | **None** |

*Row-level UPDATE list: generate from `SELECT id, mongo_id, deductible_balance … ORDER BY created_at` before apply.*

---

## 8 — `65e54b99d3d42fdf0cf61c93` (`509d2ec8-bc6f-4e8b-b69b-a130363090d8`)

| | Current | Target |
|---|---------|--------|
| Wallet | 9,428 | **9,428** |
| Σ lots | 17,735 | **9,428** |

**Wallet target:** Mongo **3,775** + native **8,653** − native burn **3,000** = **9,428**.  
**Lots target:** **9,428** (migrated **3,775** live Mongo open + native **8,653** − **FIFO 3,000** on native/migrated as per burn row).

| Table | Action |
|-------|--------|
| `user_wallet` | **None** |
| `wallet_ledger` (earn) | **UPDATE** migrated earns to live Mongo `balance` (Σ **3,775**). **UPDATE** FIFO **3,000** off open earns tied to native redemption. Reduce lots **8,307**. |
| `wallet_ledger` (burn) | **None** |
| `purchase_ledger` | **None** |

---

## 9 — `681421cab1e202f9103ec1a0` (`41ffe054-bc16-4d3a-9120-bc551b76991c`)

| | Current | Target |
|---|---------|--------|
| Wallet | 157 | **157** |
| Σ lots | 8,453 | **157** |

**Wallet target:** Mongo **31,653** + native earns **62,804** − native burns **94,300** = **157**.  
**Lots target:** **157** (native net + migrated open Mongo after FIFO on **94,300** burn).

| Table | Action |
|-------|--------|
| `user_wallet` | **None** |
| `wallet_ledger` (earn) | **UPDATE** migrated earns to live Mongo `balance` (Σ **31,653**). **UPDATE** FIFO **94,300** across open earns (native + migrated). Reduce lots **8,296**. |
| `wallet_ledger` (burn) | **None** |
| `purchase_ledger` | **None** |

---

## 10 — `669f3ec760ab0274d8e31ed4` (`a8b16c7b-9930-4e67-8ae3-f8a219ca51c6`)

| | Current | Target |
|---|---------|--------|
| Wallet | 13,063 | **13,063** |
| Σ lots | 4,916 | **13,063** |

**Wallet target:** Mongo **15,647** + native **7,916** − **10,500** = **13,063**.  
**Lots target:** **13,063** — migrated earns currently **0** deductible vs live Mongo open **15,647**; native earns **4,916** deductible need to rise after migrated restoration and **FIFO 10,500** redemption.

| Table | Action |
|-------|--------|
| `user_wallet` | **None** |
| `wallet_ledger` (earn) | **UPDATE** migrated earns: `deductible_balance` = live Mongo `balance` (Σ **15,647**). **UPDATE** FIFO **10,500** on open earns. Adjust native earn deductibles so Σ lots = **13,063** (+**8,147** net). |
| `wallet_ledger` (burn) | **None** |
| `purchase_ledger` | **None** |

---

## 11 — `67c917a2c336839338cc12a8` (`6ac3a95a-0f78-4603-800d-3354c9a2b345`)

| | Current | Target |
|---|---------|--------|
| Wallet | 2,436 | **2,436** |
| Σ lots | 8,330 | **2,436** |

**Wallet target:** Mongo **6,010** + native **12,926** − **16,500** = **2,436**.  
**Lots target:** **2,436**.

| Table | Action |
|-------|--------|
| `user_wallet` | **None** |
| `wallet_ledger` (earn) | **UPDATE** migrated to live Mongo Σ **6,010**. **UPDATE** FIFO **16,500** for native burns. Reduce lots **5,894**. |
| `wallet_ledger` (burn) | **None** |
| `purchase_ledger` | **None** |

---

## 12 — `6a4869e18a5ea7b763b65992` (`07313983-05d3-46a1-8549-75fc6d087ec5`)

| | Current | Target |
|---|---------|--------|
| Wallet | 510 | **510** |
| Σ lots | 6,110 | **510** |

**Wallet target:** Mongo **6,110** − native redemption burn **5,600** = **510**.  
**Lots target:** **510** — single migrated earn still shows **6,110** `deductible_balance`; burn `5fd6c5ad-8660-413c-a1a8-b7bac8836614` (**5,600**, reward redemption) did not reduce lots.

| Table | Action |
|-------|--------|
| `user_wallet` | **None** |
| `wallet_ledger` (earn) | **UPDATE** migrated earn(s) for the open Mongo GIVEN (**6,110** `deductible_balance` → **510**), FIFO **5,600** against that earn (reason: New CRM redemption). |
| `wallet_ledger` (burn) | **None** (burn row correct). |
| `purchase_ledger` | **None** |

---

## 13 — `66aa305cddfe1420692eff91` (`e5961962-0b82-404b-8aee-e7e793d4ec3a`)

| | Current | Target |
|---|---------|--------|
| Wallet | 105,230 | **105,230** |
| Σ lots | 110,093 | **105,230** |

**Wallet target:** Mongo **66,533** + native **65,197** − **26,500** = **105,230**.  
**Lots target:** **105,230** (refresh migrated from live Mongo **66,533**, then FIFO **26,500** native burns).

| Table | Action |
|-------|--------|
| `user_wallet` | **None** |
| `wallet_ledger` (earn) | **UPDATE** migrated to live Mongo balances; **UPDATE** FIFO **26,500**; trim **4,863** lots. |
| `wallet_ledger` (burn) | **None** |
| `purchase_ledger` | **None** |

---

## 14 — `65413f4fd6b1732a1ec5f415` (`7e16a591-c38f-4c79-904a-bc99e2b1eab1`)

| | Current | Target |
|---|---------|--------|
| Wallet | 57,280 | **57,280** |
| Σ lots | 54,008 | **57,280** |

**Wallet target:** Mongo **41,365** + native **78,877** − native burns **62,962** = **57,280** (expiry burns **8,962** already in ledger).  
**Lots target:** **57,280** — all **54,008** current lots sit on **native** earns; migrated Mongo open **47,902** (live) not reflected in deductibles. Restore migrated from Mongo, apply native burns + expiry **FIFO** on earns.

| Table | Action |
|-------|--------|
| `user_wallet` | **None** |
| `wallet_ledger` (earn) | **UPDATE** migrated earns to live Mongo `balance`. **UPDATE** FIFO for native burns **62,962** and allocate **8,962** expiry across earns (burn rows already exist — only earn `deductible_balance` / `expiry_processed_at`). Increase lots **3,272**. |
| `wallet_ledger` (burn) | **None** |
| `purchase_ledger` | **None** |

---

## 15 — `6787827bb0d6038e49a36ed6` (`8e9f72fb-b005-492d-8f90-dc9b81aca7bf`)

| | Current | Target |
|---|---------|--------|
| Wallet | 16,514 | **16,514** |
| Σ lots | 14,098 | **16,514** |

**Wallet target:** Mongo **20,234** + native earn **362** − native/expiry burns **4,082** = **16,514**.  
**Lots target:** **16,514** — multiple **Currency expiry** burn rows (Σ **4,082**) posted; earn rows still **~2,416** short on FIFO allocation. Migrated deductibles use stale staging vs live Mongo open **63,311** / headline **20,234** — use **live Mongo per `mongo_id`**, then apply each existing expiry burn amount to specific earns (no new expiry run).

| Table | Action |
|-------|--------|
| `user_wallet` | **None** |
| `wallet_ledger` (earn) | **UPDATE** migrated `deductible_balance` from live Mongo `GIVEN.balance`. **UPDATE** earn rows so Σ expiry burn amounts (**4,082**, ids e.g. `a1b9510a-…`, `33acdf29-…`, …) match reductions on named earns (+**2,416** net lots). |
| `wallet_ledger` (burn) | **None** (keep existing expiry rows). |
| `purchase_ledger` | **None** |

---

## Pattern summary (these 10)

| Pattern | Users | Primary fix |
|---------|-------|-------------|
| Wallet low vs ledger / lots | **67510f45** | **UPDATE `user_wallet` only** |
| Wallet OK; lots high — migrated not synced to live Mongo + missing FIFO on New CRM burns | **699efc2f, 65e54b99, 681421ca, 67c917a2, 66aa305c** | **UPDATE earn `deductible_balance`** |
| Wallet OK; lots high — single redemption, no FIFO | **6a4869e18** | **UPDATE one (or few) earns** |
| Wallet OK; lots low — migrated zeroed / expiry not allocated on earns | **669f3ec7, 65413f4fd, 6787827b** | **UPDATE earns** (+ migrate balances from Mongo) |

---

## Before apply (all users)

1. Export **row-level** CSV: `ledger_id`, `mongo_id`, current `deductible_balance`, target `deductible_balance`, reason.  
2. Confirm live Mongo `balance` per `_id` (not staging-only).  
3. One transaction per user: earns first, then `user_wallet` only if still wrong.  
4. Re-run `drift-list.sql` — expect these 10 to drop off when targets met.

See also: `Five-users-deep-dive.md` (users 1–5), `Plan.md` (method).
