# Implementation plan — CR #3 spot-event pack + Content Library multi-key

**Status:** Locked for implementation. Do not re-litigate defaults below.  
**Date:** 2026-08-14  
**Source diagnosis:** `/Users/rangwan/Downloads/Plan(5).md`  
**Merchant:** Syngenta (`syngentagrower` · `8f67aa08-dfce-454d-bfb1-effc4ee45f1f`) + AMP crop cards on maridaz  
**Repos:** `loyalty-admin` (Sales App / Admin UI) · `supabase-crm` (RPCs, schema, AMP edge)

This is a **speed pack for spot-event checkout**, plus an **admin promo folder**, plus a **Content Library / AMP** change that lives in the same client folder but is a different product.

---

## Frame

Spot-event staff need to take an order in one sitting: find any grower, pick SKUs on one screen, take payment (including “Other” and a cashier discount), print a slip the grower can use later (LINE + pickup). The Sales App home must stop showing every other event after click. Marketing needs folders so 42 promos are not one mixed list. Separately, a Content Library postback button must be able to carry more than one AMP action key.

Folders and AMP keys must **not** change how event promos calculate on an order.

## Locked decisions (2026-08-14)

| # | Topic | Decision |
|---|--------|----------|
| 1 | Checkout surface | **Event New Order only** (`CreateOrderModal` on choose-events). Standalone `/order-booking` unchanged. |
| 2 | Staff discount vs ledger | **Yes — cut `purchase_ledger.final_amount` / raise `discount_amount`.** Points, tier, and missions will follow the lower net. Apply **after** `fn_apply_event_promos` bill discounts. Also persist the structured object in `metadata.staff_discount` for receipt reprint. |
| 3 | Receipt LINE QR | Left QR = Grower CRM `https://syngentagrower.rocket-loyalty.app/`. Right QR = existing pickup (transaction number). Swap to a `line.me` / `lin.ee` URL later if Marketing sends one — constant only. |
| 4 | Freebie gate | Shown pool → staff must pick **≥1** unlocked SKU with qty > 0. Filling the baht cap is **not** required. |
| 5 | Promo folders on deploy | **Empty.** All 42 rows stay Uncategorised. No prefix auto-bucket. |
| 6 | CL-001 tap behaviour | **No new Content Library toggle.** Honour the waiting Interaction Router’s existing `selection_mode`. `single` → this tap continues the **first** key only. `multiple` → this tap **fans out all keys in parallel** (record + continue each). Flex / Content Library cards already allow `multiple` (pills+multiple stays blocked). Do **not** rewrite live `corn` cards. |

## Defaults for remaining open questions (do not ask again)

**OB-001.** Merchant-wide search; selected member read-only (no edit pencil); keep Remove. No walk-in registration link. Inline phone + firstname + lastname for unknown phone. `acquisition_source = event_order_spot`. Phone = existing Syngenta `normalizePhone`. No registration badge required. `PHONE_EXISTS` → re-search and select.

**OB-002.** Inline catalogue (lift `ProductPickerModal` grid, drop nested modal). Cart on the right with `QtyStepper`. Totals under the cart. Freebie picker stays at the bottom (full width or left column bottom). Pickup-at-event qty stays on the right row. Multi-variant = in-place left drill-down, not a second modal. Toast if Review tapped with an unfilled pool.

**OB-003.** Other payment → mandatory note in `metadata.payment_method_other`. Discount types Coupon (type only, **no coupon-code field**) or Others (mandatory note). Value ฿ or % of **promoNet** (after event bill discounts). Clamp to promoNet. Outstanding = max(0, promoNet − staff฿ − amountPaid).

**OB-004.** Caption left: `Scan me เพื่อเป็นเพื่อน`. Print slip only — **no** on-screen Step 3 QR, **no** extra “collect points” copy. Dual QR on the shared thermal template (event + reprint + standalone booking print pick it up). If LINE URL empty, still print pickup QR.

**OB-005.** Single-level folders. No drag-and-drop. Assign from form + list. Event-dashboard `PromosTab` unchanged. Thai: โฟลเดอร์ / ไม่มีหมวดหมู่ / โฟลเดอร์ใหม่. Engine RPCs untouched.

**SA-001.** Two home cards only (Pending / Closed-Done). Currently open and reopened = Pending. Never-opened = Pending. Closed-Done = `opened IS NOT TRUE AND closed_at IS NOT NULL`. Farmer figure **per row only** (Pending → `planned_attended` as เกษตรกรเป้าหมาย; Closed → `total_attended` as เกษตรกรเข้าร่วม). No `/` redirect — role `default_path` already lands on `/choose-events`.

**CL-001.** Cap 5 keys or LINE 300 / 64-per-key, whichever hits first. Invalid token blocked on save. Existing single-key `action=corn` must keep working with no content re-save. AMP-003 / AMP-004 second-tap-on-a-different-button are **out of this package**. Same-tap multi-key under `single` does **not** record the extra keys (avoids `duplicate_selection`).

---

## Workstreams (four independent tracks)

Do them in this order if one implementer. Tracks C and D can run in parallel with A/B.

| Order | Slice | Repo | Kind |
|-------|--------|------|------|
| 1 | **SA-001** Sales App home | `loyalty-admin` + `admin_get_my_events` in `supabase-crm` | Route split + list DTO |
| 2 | **OB-001** Customer | `loyalty-admin` | FE only |
| 3 | **OB-002** Products | `loyalty-admin` | FE only |
| 4 | **OB-003** Payment + ledger discount | `loyalty-admin` + `api_create_manual_purchase_order` | FE + BE |
| 5 | **OB-004** Dual QR | `loyalty-admin` | FE print template |
| 6 | **OB-005** Promo folders | `supabase-crm` then `loyalty-admin` | New table + RPCs + list UI |
| 7 | **CL-001** Multi-key Action data | `loyalty-admin` + Edge `inngest-amp-serve` / `webhook-line` + `fn_amp_record_line_postback` | Authoring + AMP protocol |

OB-001–004 stay on the **event page** created in SA-001 (`/choose-events/[eventCode]`). If SA-001 slips, they can still land on today’s modal — but the route split should go first so New Order is not rewired twice.

---

## Slice contracts (implement against these)

### SA-001 — Sales Event summary home

**What happens:** `/choose-events` is list + Pending/Closed counts only. Click navigates to `/choose-events/[eventCode]`. Back returns to the summary. Other events are gone.

**BE:** Add `closed_at` (and `opened_at` if already in the SELECT) to each object from `admin_get_my_events`. No new table. RPC already returns `opened`, `planned_attended`, `total_attended`, `province`, `date_of_event` — FE currently **drops** them in `fetchMyEvents`.

**FE:**
- `EventOption` keeps status + farmer + location + date.
- New app route `src/app/(admin)/choose-events/[eventCode]/` with today’s tabs.
- Home component no longer mounts Overview/Orders on the same page.
- Back control copies `/event-report/[eventCode]`.

**Do not:** rewrite Overview QR / open-close; change generic loyalty `/`; use merchant-wide 6,027 counts (caller’s `admin_get_my_events` set only).

### OB-001 — Fast customer

**What happens:** Search any CRM member by phone/name. Selected row is read-only. Unknown valid phone → inline firstname/lastname → `createMember` → `customerId`. Walk-in registration link gone.

**RPCs (existing):** `bff_admin_search_members`, `bff_admin_create_member` (overload with `p_acquisition_source`). Stop calling `bff_search_event_attendees` from this modal.

**FE files:** `create-order-modal.tsx`, `customer-search-combo.tsx`, `member-api.ts`. Extract `SpotCustomerCapture` if it stays small.

### OB-002 — Inline catalogue + right cart

**What happens:** Step 1 left = customer + product grid. Right = selected lines with − / number / +. Freebies at bottom. Review blocked (disabled + toast) while any shown `freebie_pools[]` has zero picks.

**RPCs:** unchanged (`bff_list_event_products`, `bff_preview_event_promos`).

**FE:** Lift grid from `product-picker-modal.tsx` into Step 1; extract `QtyStepper` + `ProductCatalogueGrid`. `canNextStep1` += no unfilled pools. `handleSubmit` same check.

### OB-003 — Other note + staff discount on the ledger

**What happens:** Other → required text. Optional Discount Coupon | Others. Outstanding after promo **and** staff cut. Ledger net payable includes the cut, so currency/tier see it.

**BE (this is the schema-adjacent exception for checkout):**

Inside `api_create_manual_purchase_order`, **after** `fn_calc_event_promos` → `fn_apply_event_promos` (bill discounts already on `final_amount`):

1. Read optional staff discount from a new optional arg **or** from `p_metadata.staff_discount` (prefer reading metadata so signature stays compatible; if a dedicated `p_staff_discount jsonb` is cleaner at implement time, append it with a default).
2. Compute `amount_baht`: percent of **post-promo** `final_amount`, else baht; clamp `0 … final_amount`.
3. `discount_amount := discount_amount + amount_baht`
4. `final_amount := final_amount - amount_baht`
5. Write `metadata.staff_discount` including `amount_baht`, plus `payment_method_other` when method is `other`.
6. Return the new `final_amount` so Step 3 / print match the ledger.

Do **not** fold staff discount into `event_promo` / `bill_discounts`. Do **not** touch `fn_calc_event_promos`.

**FE:** Step 2 fields as in diagnosis. Confirm gates: Other empty note; Others-discount empty note; type set with value ≤ 0. Receipt shows Other note + discount row.

**Side effect to accept:** lower `final_amount` → fewer points / weaker tier contribution on that order. That is the requested finance behaviour.

### OB-004 — Dual QR footer

**What happens:** Under signatures, two B&W QRs (~24 mm). Left = Grower CRM URL. Right = transaction number. All print paths that use `thermal-receipt.ts` pick this up.

**FE:** `thermal-receipt.ts` section 7; pass optional `lineAddUrl` on `ThermalReceiptData` (Syngenta constant next to `LOGO_URL`). Empty left URL → pickup-only fallback.

### OB-005 — Promo folders (admin metadata only)

**What happens:** Marketing creates folders, assigns promos, filters the list. Sales App checkout does not read `folder_id`.

**Schema:**

```sql
CREATE TABLE event_promo_folder (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES merchant_master(id),
  name        text NOT NULL,
  sort_order  integer NOT NULL DEFAULT 0,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (merchant_id, name)
);
-- RLS merchant_isolation; trigger_set_updated_at

ALTER TABLE event_promo
  ADD COLUMN folder_id uuid REFERENCES event_promo_folder(id) ON DELETE SET NULL;
```

**RPCs:** `bff_list_event_promo_folders`, `bff_upsert_event_promo_folder`, `bff_delete_event_promo_folder`; extend `bff_list_event_promos`, `bff_get_event_promo_details`, `bff_upsert_event_promo_config` (`p_promo.folder_id`). **Do not** change `fn_calc_event_promos` / preview / create.

**FE:** Grouped list + Uncategorised; folder CRUD; form Select. Existing 42 rows remain visible.

This is a new table in the Event Promotion domain — not a parallel `cs_*` / `amp_*` folder system. Do not reuse `reward_category` or `resource_content_category`.

### CL-001 — Comma-separated Action data

**What happens:** Staff type `corn, follow_corn`. Save validates each token. Discovery lists two checkboxes. AMP signs the whole `a=` list (comma allowed in charset). After verify, split.

Then:

- Waiting router `selection_mode = single` → record + continue **first** key only. Extra keys are discovery aliases, not extra continues. Re-tap still dedupes (existing AMP-004 `single` discriminator).
- Waiting router `selection_mode = multiple` → `webhook_event_id` **per key** (`…:${key}`); record + continue each key. A later tap of the same button still dedupes per key.

**Surfaces:** `button-action-editor.tsx`, `postback.ts`, `engagement-nodes.ts`; Edge `extractActionKeyFromPostbackData` / `signAmpPostback` / `parseAndVerifyAmpPostback`; `fn_amp_record_line_postback` only if per-key webhook ids or discriminator need a server change (inspect at implement — prefer Edge fan-out with existing RPC called N times).

**Do not:** change LINE’s 2-button cap; rewrite `Card Message_Main crop` / maridaz BC-0; fold AMP-003 Flex fail into this slice.

---

## Out of scope (still)

- Standalone `/order-booking` behaviour (print template footer is the one exception — shared `thermal-receipt.ts`)
- Wallet coupon burn / coupon catalogue
- LINE OA credential plumbing
- Nested folders, drag-and-drop, auto-seed
- Event Registration two-button landing
- On-screen Step 3 LINE QR
- AMP-003, AMP-004 second-button tap
- Pixel-perfect clone of the SA-001 middle reference dashboard

---

## Docs to update when a slice ships (`06-update-docs`)

| Slice | Authoritative doc |
|-------|-------------------|
| SA-001 | `requirements/Syngenta_Events.md` (`admin_get_my_events` payload) |
| OB-001–002 | `requirements/Order_Booking.md` / `Syngenta_Events.md` attendee-search note (event modal no longer uses it) |
| OB-003 | `requirements/Order_Booking.md` + `Purchase_Transaction.md` (header staff discount after promo apply) |
| OB-004 | FE `EventOrders.md` in loyalty-admin (print footer) — no CRM schema |
| OB-005 | `requirements/Event_Promotion.md` + regenerate `REGISTRY_SUPABASE.md` |
| CL-001 | `requirements/Resource_Content.md` (+ AMP postback notes in `REGISTRY_RENDER.md` if Edge contract changes) |
| Any BE | one-line `requirements/CHANGELOG.md` |

FE companion docs in `loyalty-admin/ProjectDocs/FE_docs/` as listed in the diagnosis.

---

## Next exact step (fresh implementation thread)

1. Open this file as the first message.
2. Start with **SA-001 BE**: inspect `admin_get_my_events` return shape (signature already `p_include_all boolean`; confirm JSON keys via a small SELECT of `pg_get_functiondef` **for that named function only**), add `closed_at` to each event object, keep existing farmer fields.
3. Then **SA-001 FE** in `loyalty-admin`: stop stripping those fields in `fetchMyEvents`, split `/choose-events` vs `/choose-events/[eventCode]`.
4. After that route exists, implement OB-001 → OB-002 → OB-003 (BE apply-after-promo first) → OB-004. Folders and CL-001 whenever a second thread is free.

**Approval required before any MCP `apply_migration` / `deploy_edge_function`:** this file is the approved direction; still ask once per destructive/schema deploy in the implementation thread (workspace hard law).

## Critical IDs

- Merchant `syngentagrower` `8f67aa08-dfce-454d-bfb1-effc4ee45f1f`
- Example event `TEST-EVENT-001`
- Create order RPC `api_create_manual_purchase_order` — already has `p_metadata`, `p_chosen_freebies`; promo apply is sync inside it
- LINE Login channel `1582522625` is **not** an OA add-friend id
- AMP charset today `[a-zA-Z0-9._-]{1,64}` — comma rejected until CL-001
- Related but out of package: AMP-003 Flex fail, AMP-004 second crop tap
