# Receipt Upload Earning

Members submit receipt photos through an earn channel; each submission becomes a reviewable upload. After admin approval (or OCR auto-approval where configured), the platform creates a purchase and awards currency through the standard purchase pipeline—not a direct wallet post.

Owner surfaces: loyalty-admin, loyalty-user

**FuturePark** (OCR preview/confirm, deferred nightly CRM sync, native points engine, batch admin approve, OCR eval tables) → [`FuturePark.md`](./FuturePark.md). **Channel OCR auto-approve** (non-FuturePark merchants: read receipt → match products → auto-approve or send to admin) → [`Receipt_Channel_OCR_Auto_Approve.md`](./Receipt_Channel_OCR_Auto_Approve.md). This doc is the **platform-generic** multi-merchant contract.

## Concept

Receipt upload is the earn method for **offline third-party retail**—Watsons, 7-Eleven, modern trade, dealers—where the brand does not own the till and the retailer will never send it sales data. The receipt in the member's hand is the only record that ties that purchase to a person, so the member supplies it self-service and the brand gains a direct relationship with a shopper it otherwise could not see. It is a **manual-or-assisted approval loop** on top of purchases: staff (or OCR rules) turn the proof into a purchase so earn rules, tier multipliers, missions, and tickets behave like any other completed purchase. The operator's only recurring work for this method is approval.

**Receipt upload** — One logical receipt stored as one row: status, images, optional member-entered store/receipt number/date, optional seller, and links to earn channel and (after approval) purchase.

**Upload session (legacy)** — Before 2026-07-07, multiple rows could share a `batch_id` (one image per row). Current member APIs treat a URL array as **pages of one receipt** (single row, `images[]`).

**Earn channel (receipt method)** — The card on the Earn page whose method opens the upload UI. Channel `config` controls extra member fields (store picker, receipt number, purchase date, seller code)—not admin line-entry mode.

**Merchant upload settings** — Plan or merchant `feature_config` for `upload_receipt`: admin **entry mode**, **auto approve** (channel OCR path only; see Rules), and **channel OCR** (platform-admin switch that routes member uploads through receipt reading).

**Entry mode** — How much of the receipt the approver keys, set once per merchant to match what its earn rules need. **Receipt total only** — one amount; enough when points depend only on spend. **SKU lines with amount** — product, quantity, and the printed line total; unit price is derived as line total ÷ quantity, because receipts rarely print a per-unit price. **SKU lines, quantity only** — product and quantity; line total = catalog price × quantity, for merchants whose receipts do not show usable line amounts. SKU modes are what make product-based earn rules and missions work on receipts.

**Channel OCR auto-approve** — Optional path for merchants with channel OCR on: the system reads the receipt, matches eligible products for its sales channel, and either approves it (purchase + points immediately) or leaves it `pending` in the same admin queue with **review reasons**. Full contract → `Receipt_Channel_OCR_Auto_Approve.md`.

**Approved by** — An approved receipt is either **system-approved** (auto path) or **admin-approved** (manual review, bulk, or Front Line). The queue can filter on this when channel OCR is on.

**Review states** — `pending` → `approved` or `rejected`; `approved` → `cancelled` when an admin voids an approved receipt (purchase and its points reversed). Member history may **display** `pending` when approved rows are still waiting on deferred CRM sync (Future Park); quota-style CRM failures can surface as `rejected` with localized copy.

**Front Line receipt (contrast)** — Counter staff keying a receipt for a member who is standing in front of them. Staff enter the same fields an approver would, so there is nothing left to approve: the purchase settles on save and never enters the approval queue (deferred-CRM merchants queue it for the nightly sync instead).

**Purchase linkage** — Approval calls the purchase API with `transaction_source = receipt_upload` and `processing_method = direct`, so currency runs synchronously via existing purchase triggers.

**Activity upload (contrast)** — Activity matrices post wallet currency through the wallet chokepoint. Receipt upload never skips the purchase ledger.

## Rules

- **Authentication** — Member `upload_receipts` requires a resolved `user_accounts` row for the session. External/API inserts use `api_create_receipt_upload` with explicit merchant and user or `external_user_ref`.
- **One row per receipt** — Multi-image member submit creates **one** `purchase_receipt_upload` with all page URLs in `images` (`image` = first page). Each distinct receipt is a separate RPC call.
- **Front Line bypasses the queue** — Front Line batch save creates purchases directly (`api_create_purchase`, `p_api_source = frontline_receipt`) with no upload row; deferred-CRM merchants instead insert `approved` / `approved_method = frontline` / `crm_sync_status = queued` rows. Same-day reverse cancels the purchase; a still-queued row is voided to `rejected`.
- **Channel config gates member fields** — `receipt_selection.mode` (`none` | `channel` | `store_only`) controls whether `store_id` is required. `receipt_number` / `purchase_date` blocks require params when enabled **and** required on the channel. Invalid or inactive store → `STORE_INVALID` / `STORE_REQUIRED`.
- **Seller on upload** — When `earn_channel.config.seller_reference` requires a code, member must pass seller code (seller overloads of `upload_receipts`). Admin may attach or override seller on approve via `p_seller_code` → `fn_resolve_seller_reference`; when the code resolves to a seller-type member, that seller also earns sell-out currency on the purchase. Self-reference blocked when buyer id provided on lookup.
- **Admin entry mode** — `line_item_amount` (SKU lines with amounts), `line_item_derived` (qty × catalog price), or `total_only` (`p_receipt_total` required on preview/approve). Resolved from merchant, else plan `feature_config.receipt_entry_mode`, else `line_item_amount`. SKU modes require at least one line; `line_item_derived` blocks when any SKU has no catalog price (`SKU_PRICE_MISSING`, names the SKUs).
- **Purchase date** — The approver enters the date printed on the receipt, not the approval date; time may be any time that day when unknown. It becomes the purchase transaction date, so date-windowed earn rules and missions judge the purchase, not the review.
- **Transaction number on approve** — `p_transaction_number` mandatory for `approve`; preview may run without it.
- **Deduplication on approve** — Duplicate `purchase_ledger.transaction_number` blocks approve. Scope: same store-channel attribute group when store has a channel attribute; else exact store; else merchant-wide. Preview **warns**; approve **blocks**. Separate helpers (`fn_receipt_upload_duplicate_matches`, OCR receipt-id checks) support admin duplicate panels and OCR—see System.
- **Reject** — Sets `status = rejected`, stores reason in `notes`, records `admin_id`. May route through `chokepoint_post_receipt_event(rejected)` for LINE.
- **Submit notification** — After insert (`upload_receipts` / pending `api_create_receipt_upload`), `chokepoint_post_receipt_event(submitted)` emits member LINE “received receipt” when notification pipeline is enabled (Thai system templates by default).
- **Points on history** — When `purchase_ledger_id` exists and wallet earned rows exist, show actual points; else `estimated_points` only if display status is approved; deferred-sync approved-without-ledger displays as pending/processing.
- **Cancel approved** — Only `approved` rows can be cancelled; a reason is required. Linked purchase → `api_cancel_purchase` with currency reversal (best effort); approved-but-queued (deferred CRM) → sync dropped. Row becomes `cancelled`, reason appended to `notes` as `[Cancelled] …`, admin action logged. Repeat cancel is idempotent. Pending rows are rejected, not cancelled.
- **Auto approve flag** — `feature_config.auto_approve` (merchant row, else plan row, else **false**) is read only by channel OCR evaluation (`fn_ocr_evaluate_channel_receipt`). A receipt auto-approves only when merchant auto approve is on **and** its sales channel's policy allows auto-approve **and** no check failed. Otherwise it lands `pending` in this queue. It never changes the manual Preview/Approve steps.
- **Channel OCR switch** — `feature_config.channel_ocr_enabled` (merchant row, else plan row, else false), set only from Super Admin. When off, members use the standard `upload_receipts` path and the admin UI hides reasons, the Approved-by filter, and OCR settings. When on, member uploads go to `channel-product-receipt-upload`.
- **Review reasons** — Pending rows from channel OCR carry reason codes (`ocr_suggestions.failures`); the list returns them as `review_reasons` and the admin sees plain-language labels under the Pending badge and in the review modal. Legacy pending rows with no stored reason show "duplicate receipt number" when another approved/pending row has the same receipt number. Reasons never go into `notes`.
- **Approved by** — `approved_method` `auto` / `auto_ocr` = System; any other value or null = Admin. `bff_list_receipt_uploads(p_approved_by = system | admin)` filters on this.
- **Deferred CRM** — When `fn_get_upload_receipt_config.deferred_crm_confirm` is true (Future Park), approve may queue CRM sync instead of immediate local purchase; `crm_sync_*` columns drive member copy and display status. Full state machine → `FuturePark.md`.
- **Referral** — Receipt-upload purchases do not drive referral purchase conversion; marketplace/Shopify orders use `referral_claim`. Signup referral still applies at join (`Referral.md`).

## Journeys

### Admin journey

| Page | Owning repo | BFF / RPC |
| --- | --- | --- |
| Receipts Upload (queue + review) | loyalty-admin | `bff_list_receipt_uploads`, `bff_approve_receipt_upload` (preview / approve / reject / cancel), `bff_find_seller_by_code`, `get_store_attributes_hierarchy` (channels), `get_stores_by_channel` |
| Upload Receipt settings | loyalty-admin | `bff_get_upload_receipt_config`, `bff_set_upload_receipt_config`, `bff_list_receipt_ocr_config` (OCR sections when channel OCR on) |
| Receipt reading policy / Sales channel editors (channel OCR) | loyalty-admin | `bff_get_receipt_ocr_set_rule`, `bff_upsert_receipt_ocr_set_rule`, `bff_get_receipt_ocr_channel_products`, `bff_upsert_receipt_ocr_channel_products`, `bff_get_receipt_ocr_hints`, `bff_upsert_receipt_ocr_hints` |
| Super Admin → Receipt upload | loyalty-admin | `superadmin_get_receipt_upload_config`, `superadmin_upsert_receipt_upload_config` |
| Future Park Receipt Approval | loyalty-admin | Batch OCR approve path (deferred CRM)—`FuturePark.md` |
| Front Line — Upload Receipt tab | loyalty-admin | `api_create_purchase` per receipt (immediate) or `api_create_receipt_upload` (deferred CRM); `calc_currency_core` estimate; autofill modal deferred-CRM only |

| Setting | Effect on behaviour |
| --- | --- |
| Entry mode (`receipt_entry_mode`) | Review modal fields: Receipt total only → one amount; SKU lines with amount → product + qty + line total; SKU lines, quantity only → product + qty (price from catalog). Default SKU lines with amount |
| Channel OCR (Super Admin only) | Member uploads go through receipt reading; admin queue shows reasons + Approved-by; settings page shows Auto-approve, Policies, Sales channels |
| Auto approve (shown when channel OCR on) | Clean channel OCR receipts approve without admin; off → every channel OCR receipt waits in the queue with reason "Auto-approve is off" |
| Policy: auto-approve clean receipts (per sales-channel set) | Same as above, scoped to one policy set (e.g. 1st-party vs 3rd-party channels) |
| Earn channel — receipt upload config | Member-only: store picker mode, receipt number, purchase date, seller reference (`bff_upsert_single_earn_channel`) |
| Upload receipt feature flag | `fn_merchant_feature_resolve(earn_channel, upload_receipt)` — channel visibility on Earn surfaces |

1. Open **Receipts Upload** — pending list from `bff_list_receipt_uploads` / list view; filter by status. With channel OCR on: pending rows show review reasons under the badge; approved rows say System approved / Approved by admin; All and Approved tabs add an **Approved by** filter (All / System / Admin). The Channel column shows the OCR sales channel when present, else the earn channel.
2. Open a row — gallery from `images` (fallback `image`); member store/channel prefills when present. Channel OCR rows add a "sent for manual review" banner with the reasons (pending) or an auto-approved banner (approved), and prefill channel, store, receipt number, total, and matched line items from the reading result.
3. **Key the receipt** — receipt number, purchase date (from the receipt), **channel then store** (store list filtered to the chosen store-channel attribute), optional seller code (lookup shows the seller before approve), then line items or total per entry mode (Add Item per receipt line).
4. **Preview** — estimated points and tickets; duplicate warnings with matching receipts.
5. **Approve** — creates purchase + links `purchase_ledger_id`; duplicate transaction number blocked; missing catalog price in quantity-only mode names the SKUs.
6. **Reject** — reason required; member notified via receipt LINE template when pipeline enabled.
7. **Cancel** (approved rows) — reason required; purchase and points reversed; row moves to the Cancelled tab.
8. **Upload Receipt settings** — change entry mode; with channel OCR on also auto approve, receipt reading policies, and per-channel product/hint lists (`Receipt_Channel_OCR_Auto_Approve.md` Journeys).
9. **Front Line** — staff key receipts (store, receipt number, date, amount, optional lines and photo) for an identified member into a pending batch, see estimated points per receipt, then save; purchases settle immediately (or queue under deferred CRM). Same-day reverse from the tab's history—not from Receipts Upload.

### Member journey

| Surface | Owning repo | BFF / RPC |
| --- | --- | --- |
| Earn → Upload receipt | loyalty-user | `bff_get_earn_channels` → `upload_receipts` |
| Store / channel pickers | loyalty-user | `get_store_channels`, `bff_list_stores_for_receipt_upload` |
| History (upload receipt filter) | loyalty-user | `bff_get_upload_receipt_history` |

1. Member opens **Earn** and taps the receipt upload channel (`earn_method = receipt_upload`).
2. Optional fields per channel config — store/channel picker, receipt number, purchase date, seller code.
3. Member captures or selects image(s); client uploads to storage, then calls `upload_receipts` once with all page URLs for **one** receipt. With channel OCR on, the client instead calls `channel-product-receipt-upload` (each image = one receipt).
4. Success — pending message; LINE “submitted” when enabled. Channel OCR: all approved → "approved, +N points"; all pending → the standard pending message; mixed → mixed summary; daily image cap → limit message.
5. **History** — filter pending/approved/rejected; processing state when approved but purchase not yet visible (deferred CRM); a cancelled receipt shows `cancelled` with the admin's reason; voided Front Line queued rows are hidden.

## System

### Data model

| Object | Role |
| --- | --- |
| `purchase_receipt_upload` | Canonical upload row: `status`, `images`/`image`, `earning_channel_id`, `store_id`, `seller_id`, member prefill (`receipt_number`, `transaction_date`), `purchase_ledger_id`, `approved_method` (`admin` \| `auto` \| `auto_ocr` \| `frontline` \| null), `ocr_suggestions` (channel OCR reading result, `failures` = review reasons), `estimated_points` (points), CRM sync fields (`crm_sync_status`, `crm_sync_error_code`, `crm_sync_error_params`, …), legacy `batch_id`, `external_user_ref`, `mongo_id`, `upload_at_store_id` |
| `purchase_receipt_upload_review_audit` | Append-only admin review snapshots (`trg_purchase_receipt_upload_admin_review` on status-changing updates) |
| `earn_channel` | Member UX + attribution; receipt-specific keys in `config` (`receipt_selection`, `receipt_number`, `purchase_date`, `seller_reference`) |
| `feature_config` (`feature_key = upload_receipt`) | `receipt_entry_mode`, `auto_approve`, `channel_ocr_enabled`; extended keys via `fn_get_upload_receipt_config` (`deferred_crm_confirm`, `points_engine`, sync time/timezone, amount limit action) |
| `receipt_approval_rules`, `receipt_ocr_hints`, `receipt_ocr_channel_product`, `receipt_ocr_set_rule` | OCR/approval configuration per store attribute / set (evaluated in OCR flows; Future Park depth in `FuturePark.md`) |
| `purchase_ledger` / `purchase_items_ledger` | Created on approve; `transaction_source = receipt_upload`, images copied to purchase |
| `v_receipt_upload_list` | Admin list join: user, channel, store, purchase, wallet points/tickets |
| `v_receipt_upload_batch_summary` | Legacy batch aggregation by `batch_id` |

Live `purchase_receipt_upload.status` ∈ `pending` (default) \| `approved` \| `rejected` \| `cancelled`; `crm_sync_status` ∈ `not_applicable` (default) \| `queued` \| `confirmed` \| `failed`. `image` nullable in schema (prefer `images`).

### Functions

| Function | Role |
| --- | --- |
| `upload_receipts` | Member insert (single URL or page array; optional seller overload); emits `chokepoint_post_receipt_event(submitted)` |
| `api_create_receipt_upload` | Service/edge insert with full column set |
| `bff_approve_receipt_upload` | Admin `preview` / `approve` / `reject` / `cancel`; approve → `api_create_purchase` + seller currency when applicable; cancel → `fn_cancel_approved_receipt_upload` (→ `api_cancel_purchase`, audit log) |
| `bff_admin_cancel_queued_frontline_uploads` | Front Line: void queued (deferred-CRM) counter receipts before sync → `rejected` + `ocr_suggestions.frontline_void` |
| `bff_list_receipt_uploads` | Cursor list for admin queue; `p_approved_by` (`system` \| `admin`); items carry `review_reasons`, `sales_channel_name` |
| `fn_ocr_evaluate_channel_receipt`, `fn_ocr_persist_channel_receipt` | Channel OCR route decision and atomic purchase + upload write → `Receipt_Channel_OCR_Auto_Approve.md` |
| `bff_list_receipt_ocr_config`, `superadmin_get_receipt_upload_config`, `superadmin_upsert_receipt_upload_config` | Channel OCR settings summary; platform-admin channel OCR switch |
| `bff_list_stores_for_receipt_upload` | Keyset store picker (member + admin) |
| `bff_find_seller_by_code` | Admin seller lookup before approve |
| `bff_get_upload_receipt_config` / `bff_set_upload_receipt_config` | Merchant admin entry mode + auto approve; get also returns `channel_ocr_enabled` (resolved per key: merchant, else plan, else false) |
| `fn_get_upload_receipt_config` | Internal merchant OCR/deferred settings |
| `bff_get_upload_receipt_history` | Member formatted history with display-status mapping |
| `get_receipt_upload_history` / `get_receipt_batch_details` | Batch-grouped history (legacy batch UI / external ref lookups) |
| `chokepoint_post_receipt_event` | Receipt LINE notification chokepoint (`submitted`, `rejected`; `approved` stub—no emit) |
| `fn_receipt_upload_duplicate_matches`, `fn_receipt_upload_approved_datetime_amount_dup`, `fn_ocr_duplicate_by_receipt_id` | Duplicate detection dimensions beyond transaction number |
| `fn_check_receipt_upload_daily_image_limit`, `fn_receipt_upload_daily_image_count` | Daily image caps (OCR / merchant policy callers) |
| `calc_currency_core` | Preview estimate and purchase-time earn (via purchase path) |

### Flows

**Member submit (generic)** — Auth + merchant → validate channel config → insert `pending` → optional LINE submitted.

**Admin approve (generic)** — Preview estimate + dup check → approve creates purchase (`processing_method = direct`, `earn_currency = true`) → update upload row → purchase triggers → wallet ledger. Seller branch: `calc_currency_for_transaction(..., seller)` + wallet chokepoint when seller resolved.

**Currency** — No direct wallet write on upload; all earn side effects ride `api_create_purchase` triggers (tiers, missions, earn rules).

**Notifications** — Outbox topic `crm.events.receipt` → `notification-receipt-router` on Inngest router (requires OutboxPublisher allowlist). Templates `receipt` / `submitted` and `receipt` / `rejected`.

**Channel OCR auto-approve** — Member token → `channel-product-receipt-upload` → read (OpenRouter vision) → sales channel → product match → `fn_ocr_evaluate_channel_receipt` → `fn_ocr_persist_channel_receipt` (auto: purchase + approved row in one transaction; manual: pending row with reasons). Detail → `Receipt_Channel_OCR_Auto_Approve.md`.

**OCR / auto edges (platform)** — Render edges include `receipt-upload-user`, `upload-receipts-auto-preview`, `upload-receipts-auto-confirm`, `approve-receipts-admin`, `receipt-preview-v2`, `forward-receipt*`, `admin-receipt-batch-*` (`REGISTRY_RENDER.md`). Future Park wires the full OCR pipeline; other merchants may use subsets.

### External services

- **Supabase Storage** — Public image URLs referenced on rows (member apps: `images` bucket paths; Front Line `receipt-uploads`).
- **Render edge functions** — User upload proxy, OCR preview/confirm, admin batch tooling (JWT/public per function).
- **Inngest** — Receipt notification routing; Future Park CRM confirm cron/service separate.

### Known gaps

- **Registry vs config keys** — Admin BFF exposes `entry_mode`; `feature_config` stores `receipt_entry_mode` (live both).
- **Front Line photos** — Immediate-settlement Front Line saves do not yet forward receipt images to the purchase; the photo is captured but not stored.
- **Auto approve** — Only affects merchants with channel OCR on; the setting is hidden otherwise.
- **Daily image limit** — Functions exist; generic `upload_receipts` may not enforce—Future Park enforces in preview edge (see `FuturePark.md`).
- **`get_receipt_upload_history` overloads** — Still batch-centric; primary member app uses `bff_get_upload_receipt_history`.
- **OCR table suite** — Shared schema; productized admin UX may be merchant-specific—document operational detail under Future Park when applicable.

## Related

- **Earn Channel** — Receipt card visibility, member config keys, registry `purchase:receipt_upload` → `Earn_Channel.md`.
- **Purchase Transaction** — Purchase creation, cancel, seller lines → `Purchase_Transaction.md`.
- **Currency** — Earn via purchase triggers → `Currency.md`.
- **FuturePark** — OCR, deferred CRM, batch approve, validation reason codes → `FuturePark.md`.
- **Channel OCR auto-approve** — Receipt reading, product allow-lists, policy sets, auto vs manual routing for non-FuturePark merchants → `Receipt_Channel_OCR_Auto_Approve.md`.
- **Notification Service** — LINE Flex templates and outbox → `Notification_Service.md` (receipt category).
- **Referral** — Purchase referral attribution excludes receipt upload source → `Referral.md`.
- **Front Line** — Staff upload and same-day purchase reverse → loyalty-admin `ProjectDocs/FE_docs/FrontLine.md`.
