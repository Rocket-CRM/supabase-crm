# Ecom Subscription — Cancellation & Refund Plan

> **Purpose:** Handoff for CS/engineering to stop unwanted billing, refund undelivered charges, and reconcile Supabase.
> **Companion:** `docs/ECOM_SUBSCRIPTION_ARCHITECTURE.md`
> **Supabase project:** `ttamegbuapjfklogbviq`
> **Refund tool:** `stripe-refund` v1 (service_role only) — Jul 2026
> **Status:** **EXECUTED** — Pim Charusrini case completed **3 Jul 2026**

---

## 1. Problem statement

Customers can accumulate **multiple active Stripe subscriptions** for the same account. When CS cancels one subscription in Supabase or Stripe, **other subs keep charging**. Stripe charge exports show `ch_…` IDs without subscription IDs unless joined via invoice.

Additionally:

- Recurring payments may succeed in Stripe while **`installments.order_status` stays `pending`** (webhook gap on `invoice.payment_succeeded`).
- **`cancel-subscription`** cancels Stripe but DB update may fail (`canceled_at` column missing).
- **`stripe-refund`** v1 deployed Jul 2026; first production CS case completed with this plan (Pim Charusrini, 3 Jul 2026).

---

## 2. Reference case — Pim Charusrini

| Field | Value |
|---|---|
| Name | Pim Charusrini (พิมพ์นารา นันทพานิชย์) |
| Email | `pimnara.ny@gmail.com` |
| Phone | +66838814455 |
| User ID | `d8ae8718-03b8-4044-a9b9-cb9cc329c6a8` |
| Stripe customer (on active subs) | `cus_SzXtyjS59jifwt` |
| `user_data.stripe_customer_id` | `cus_UVZ2ZHG9i4iSYB` (**drift** — use sub-level customer) |

### 2.1 CS request

Cancel **two unwanted subscriptions** where payment succeeded but **goods not shipped**, and **refund** May + June charges:

| CS description | Amount | Charge dates | Notes |
|---|---|---|---|
| XL 32 single (CS label) | ฿2,100 | 14/05/2026, 14/06/2026 | **Actually P17 (L 36×4)** — not XL |
| XL 32 × 3 | ฿7,327 | 22/05/2026, 22/06/2026 | P18 × qty 3 |

**CS ticket error (corrected at execution):** June charge IDs were listed with **amounts swapped**. Actual Stripe amounts:

| Charge ID | CS label | **Actual amount** | Date (UTC) |
|---|---|---|---|
| `ch_3Ti7Y82MlAnf1K1x0cvnRVwT` | ฿7,327 | **฿2,100** | 14 Jun 2026 |
| `ch_3TlC292MlAnf1K1x1gqk2wCU` | ฿2,100 | **฿7,327** | 22 Jun 2026 |

Refunds were issued by **actual charge amount**, not CS labels.

### 2.2 Mapped subscriptions (post-execution, 3 Jul 2026)

| Action | Package | Qty | Supabase ID | Stripe sub | Stripe status | DB status |
|---|---|---|---|---|---|---|
| **Canceled + refunded** | P17 L 36×4 | 1 | `4fbde7af-8ff9-4a67-a29e-d18b1db323af` | `sub_1Sntx92MlAnf1K1xBHvmQ8RJ` | **canceled** | **cancel** |
| **Canceled + refunded** | P18 XL 32×4 | 3 | `47f49e94-5bf1-4b85-b308-e34eab48640b` | `sub_1TDpEI2MlAnf1K1xbybTrdrm` | **canceled** | **cancel** |
| **Kept** | P18 XL 32×4 | 1 | `7bb8c02c-d46a-4409-af55-c62696708573` | `sub_1TV0aC2MlAnf1K1x6Bpy6wM8` | **active** | **ongoing** |
| DB sync | P18 ×1 | 1 | `48add691-09ee-48b7-8a96-294a9c5f7709` | `sub_1SwZZz2MlAnf1K1xQtpt86cX` | canceled | **cancel** |
| DB sync | P09 | 1 | `ee80b4dd-ad8e-472a-a668-8053a6f2824d` | `sub_1S3Yuv2MlAnf1K1xuZYZUxWd` | canceled | **cancel** |
| DB close | P18 ×3 | 3 | `622ad04d-3ced-4a26-bc00-dabc4081de18` | — | never paid | **cancel** |
| DB close | P04 | 1 | `3464395b-f223-4337-ba9c-9f1f14bf4a16`, `cd11a38a-5be6-4510-9dc5-90921b53fc11` | — | abandoned | **cancel** |

**Decision (approved):** Keep **`sub_1TV0aC…`** (single P18 ฿2,215/mo). Cancel + refund only the two subs above.

### 2.3 Installment state (post-execution)

**P17 + P18×3:** 10 undelivered installments (`shipment_status = pending`) set to `order_status = cancelled`.

**Not refunded (out of scope for this case):** older P17/P18×3 charges Mar–Apr 2026 — see §11.4.

---

## 3. Target end state

For each **cancel + refund** subscription:

1. **Stripe subscription** → `canceled` (no future charges). ✅
2. **Affected charges** → fully **refunded** in Stripe. ✅ (4 charges, ฿18,854)
3. **Supabase subscription** → `cancel`. ✅
4. **Paid, undelivered installments** → `order_status = cancelled`. ✅ (10 rows)
5. **Warehouse** — installment UPDATEs may have fired Pipedream; ops should confirm picks canceled.

For **keep** subscription: remains **active** in Stripe and `ongoing` in DB. ✅

---

## 4. Tools available

### 4.1 `stripe-refund` (v1 — preferred for future cases)

**URL:** `POST https://ttamegbuapjfklogbviq.supabase.co/functions/v1/stripe-refund`
**Auth:** `Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>` only

Use for future CS refunds when service role key is available. Request body supports `charge_id`, `sync_supabase`, `cancel_subscription`, `cs_reference`, and `Idempotency-Key` header.

### 4.2 `cancel-subscription` (existing)

Public endpoint — use only from secure backend. DB update may fail on missing `canceled_at` column.

### 4.3 `get-stripe-subscription` (existing)

Post-op verification of sub status.

### 4.4 One-shot executors (Pim case only — **delete after use**)

Deployed 3 Jul 2026 for execution without local service role key. **Remove from project when no longer needed:**

| Function | Purpose |
|---|---|
| `cs-pim-cancel-refund-executor` | Batch cancel + refund + Supabase sync |
| `cs-pim-refund-remainder` | Missed May ฿7,327 charge (timezone discovery gap) |
| `cs-pim-charge-audit` | List all charges for customer audit |

---

## 5. Execution plan (Pim case)

### Phase 0 — Preconditions

- [x] CS confirms subscription to **keep** — P18 single kept.
- [x] Written CS approval for refunds — approved 3 Jul 2026.
- [ ] Warehouse notified — **ops follow-up**.
- [x] Execution path available — one-shot edge executors (no local SRK).

### Phase 1 — Discover May charge IDs in Stripe

- [x] Customer `cus_SzXtyjS59jifwt` — 20 paid charges listed.
- [x] May ฿2,100 → `ch_3TWsmA2MlAnf1K1x02zgUWXt` (14 May 2026)
- [x] May ฿7,327 → `ch_3TZxFR2MlAnf1K1x0lHzszHF` (22 May 2026; UTC 17:52 — missed on first pass due to timezone window)

### Phase 2 — Cancel Stripe subs, then refund four charges

**Order used:** Cancel subs first, then refund (stop billing before money back).

| # | Amount | Charge ID | Refund ID | Idempotency key | Status |
|---|---|---|---|---|---|
| 1 | ฿2,100 | `ch_3TWsmA2MlAnf1K1x02zgUWXt` | `re_3TWsmA2MlAnf1K1x0KA5RFYx` | `pim-refund-20260514-2100` | ✅ |
| 2 | ฿7,327 | `ch_3TZxFR2MlAnf1K1x0lHzszHF` | `re_3TZxFR2MlAnf1K1x0t5KGiIO` | `pim-refund-20260522-7327` | ✅ (2nd pass) |
| 3 | ฿2,100 | `ch_3Ti7Y82MlAnf1K1x0cvnRVwT` | `re_3Ti7Y82MlAnf1K1x0wmbsqr0` | — | ✅ |
| 4 | ฿7,327 | `ch_3TlC292MlAnf1K1x1gqk2wCU` | `re_3TlC292MlAnf1K1x1KLenkyu` | — | ✅ |

**Total refunded: ฿18,854**

Stripe subs canceled before refunds:

- `sub_1Sntx92MlAnf1K1xBHvmQ8RJ` → canceled
- `sub_1TDpEI2MlAnf1K1xbybTrdrm` → canceled

### Phase 3 — Supabase reconciliation

- [x] Target subs → `cancel`
- [x] Stale subs (Stripe already canceled) → `cancel`
- [x] Abandoned checkout rows → `cancel`
- [x] 10 undelivered installments on P17 + P18×3 → `cancelled`

### Phase 4 — Verification

- [x] Stripe: 2 subs canceled, 4 charges fully refunded
- [x] Kept sub `sub_1TV0aC…` still **active**
- [x] Supabase: all non-kept subs `cancel`; kept sub `ongoing`

---

## 6. `stripe-refund` implementation summary

| Item | Detail |
|---|---|
| Deployed | v1, `ttamegbuapjfklogbviq`, Jul 2026 |
| Auth | Service role only (anon → 403 verified) |
| Stripe API | `refunds.create` with idempotency |
| Pre-check | Charge retrieve; reject if fully refunded |
| Sync | installment → `cancelled`, subscription → `cancel`, optional Stripe sub cancel |
| First CS use | Pim case used one-shot executors (same Stripe API); use `stripe-refund` for future cases |

---

## 7. Recommended follow-up engineering

1. Add `canceled_at` column to `subscriptions`.
2. Handle `invoice.payment_succeeded` in `stripe-webhook` to complete installments.
3. Enable RLS on `subscription_packages`.
4. Prevent duplicate active subs per user in `dynamic-subscription`.
5. Lock down `cancel-subscription` (service role + fix DB write).
6. Refund audit log table (optional).
7. **Delete** temporary Pim executor functions (§4.4).
8. Document charge lookup: use Stripe charge list by customer; CS export amounts may not match charge IDs.

---

## 8. Resolved / remaining questions

| Question | Resolution |
|---|---|
| Keep `sub_1TV0aC…` (P18 single)? | **Yes — kept active** |
| Refund P17 installment #1 (Jan, ฿2,215)? | **No — out of scope** |
| Refund Mar/Apr P17/P18×3 charges? | **No — out of scope** (see §11.4) |
| Warehouse picks? | **Ops follow-up** — installment rows updated |

---

## 9. Quick reference — Pim IDs

```
User:            d8ae8718-03b8-4044-a9b9-cb9cc329c6a8
Stripe customer: cus_SzXtyjS59jifwt

CANCELED + REFUNDED:
  sub_1Sntx92MlAnf1K1xBHvmQ8RJ  / 4fbde7af-8ff9-4a67-a29e-d18b1db323af  (P17)
  sub_1TDpEI2MlAnf1K1xbybTrdrm  / 47f49e94-5bf1-4b85-b308-e34eab48640b  (P18×3)

Refunded charges (all 4):
  ch_3TWsmA2MlAnf1K1x02zgUWXt  ฿2,100  May 14
  ch_3TZxFR2MlAnf1K1x0lHzszHF  ฿7,327  May 22
  ch_3Ti7Y82MlAnf1K1x0cvnRVwT  ฿2,100  Jun 14
  ch_3TlC292MlAnf1K1x1gqk2wCU  ฿7,327  Jun 22

KEPT:
  sub_1TV0aC2MlAnf1K1x6Bpy6wM8  / 7bb8c02c-d46a-4409-af55-c62696708573
```

---

## 10. CS customer message (sent-ready)

> เรียนคุณพิมพ์  
> ดำเนินการยกเลิก Subscription 2 รายการเรียบร้อยแล้ว (P17 + P18×3) และคืนเงิน 4 รายการ รวม **฿18,854**  
> - 14/05/2026 ฿2,100  
> - 22/05/2026 ฿7,327  
> - 14/06/2026 ฿2,100  
> - 22/06/2026 ฿7,327  
> เงินจะกลับเข้บัตรภายใน 5–10 วันทำการ  
> Subscription P18 รายการเดียว (฿2,215/เดือน) ยังคงใช้งานอยู่ตามปกติ

---

## 11. Execution record (3 Jul 2026)

### 11.1 What was done

1. Canceled Stripe subs `sub_1Sntx92…` and `sub_1TDpEI…`.
2. Full refund on 4 charges totaling **฿18,854** (see §5 Phase 2).
3. Supabase: 2 target subs + 5 stale/abandoned subs → `cancel`; 10 installments → `cancelled`.
4. Verified kept sub `sub_1TV0aC…` remains **active** in Stripe and **ongoing** in DB.

### 11.2 Lessons learned

- **CS charge exports:** Amount labels may not match charge IDs — always verify via Stripe `charges.retrieve` or list-by-customer.
- **Timezone:** May 22 ฿7,327 charge created `2026-05-22T17:52:39Z` (23 May ICT) — date-window discovery must use wider UTC range or list-all + filter by amount.
- **Cancel before refund:** Prevents new cycle charges while refunds process.
- **Multiple subs:** Root cause of continued June billing after partial cancel — always enumerate all active `sub_…` on customer.

### 11.3 Pending cleanup

- [ ] Delete `cs-pim-cancel-refund-executor`, `cs-pim-refund-remainder`, `cs-pim-charge-audit` from Supabase project.
- [ ] Warehouse: confirm no picks shipped for canceled installment codes.

### 11.4 Charges not refunded (out of scope)

Older charges on canceled subs — refund only if CS requests separately (+฿19,054):

| Charge ID | Date | Amount | Sub |
|---|---|---|---|
| `ch_3TAliL2MlAnf1K1x1Efvlc3t` | 14 Mar 2026 | ฿2,100 | P17 |
| `ch_3TM0Uq2MlAnf1K1x1TqiJUA9` | 14 Apr 2026 | ฿2,100 | P17 |
| `ch_3TDpEG2MlAnf1K1x1aO8tTCO` | 22 Mar 2026 | ฿7,327 | P18×3 |
| `ch_3TP4wr2MlAnf1K1x1nt5kyxq` | 22 Apr 2026 | ฿7,327 | P18×3 |

Also not refunded: P17 Jan ฿2,215 (`ch_3Sntx72MlAnf1K1x1wtO0lmh`) and other subs/charges on kept P18 single sub.
