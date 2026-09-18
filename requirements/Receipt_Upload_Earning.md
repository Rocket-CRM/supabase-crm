# Receipt Upload Earning

Members submit receipt photos through an earn channel; each submission becomes a reviewable upload. After admin approval (or OCR auto-approval where configured), the platform creates a purchase and awards currency through the standard purchase pipeline—not a direct wallet post.

Owner surfaces: loyalty-admin, loyalty-user

**FuturePark** (OCR preview/confirm, deferred nightly CRM sync, native points engine, batch admin approve, OCR eval tables) → [`FuturePark.md`](./FuturePark.md). This doc is the **platform-generic** multi-merchant contract.

## Concept

Receipt upload earning is a **manual-or-assisted approval loop** on top of purchases: the member proves a transaction with images; staff (or OCR rules) turn that proof into a `purchase_ledger` row so earn rules, tier multipliers, missions, and tickets behave like any other completed purchase.

**Receipt upload** — One logical receipt stored as one row: status, images, optional member-entered store/receipt number/date, optional seller, and links to earn channel and (after approval) purchase.

**Upload session (legacy)** — Before 2026-07-07, multiple rows could share a `batch_id` (one image per row). Current member APIs treat a URL array as **pages of one receipt** (single row, `images[]`).

**Earn channel (receipt method)** — The card on the Earn page whose method opens the upload UI. Channel `config` controls extra member fields (store picker, receipt number, purchase date, seller code)—not admin line-entry mode.

**Merchant upload settings** — Plan or merchant `feature_config` for `upload_receipt`: admin **entry mode** (how line items vs total are entered on approve) and **auto approve** (OCR path only; see Rules).

**Review states** — `pending` → `approved` or `rejected`. Member history may **display** `pending` when approved rows are still waiting on deferred CRM sync (Future Park); quota-style CRM failures can surface as `rejected` with localized copy.

**Purchase linkage** — Approval calls the purchase API with `transaction_source = receipt_upload` and `processing_method = direct`, so currency runs synchronously via existing purchase triggers.

**Activity upload (contrast)** — Activity matrices post wallet currency through the wallet chokepoint. Receipt upload never skips the purchase ledger.

## Rules

- **Authentication** — Member `upload_receipts` requires a resolved `user_accounts` row for the session. External/API inserts use `api_create_receipt_upload` with explicit merchant and user or `external_user_ref`.
- **One row per receipt** — Multi-image member submit creates **one** `purchase_receipt_upload` with all page URLs in `images` (`image` = first page). Each distinct receipt is a separate RPC call. Front Line operator flow may still submit **one image per receipt** in a single action (multiple RPCs)—see Journeys.
- **Channel config gates member fields** — `receipt_selection.mode` (`none` | `channel` | `store_only`) controls whether `store_id` is required. `receipt_number` / `purchase_date` blocks require params when enabled **and** required on the channel. Invalid or inactive store → `STORE_INVALID` / `STORE_REQUIRED`.
- **Seller on upload** — When `earn_channel.config.seller_reference` requires a code, member must pass seller code (seller overloads of `upload_receipts`). Admin may attach or override seller on approve via `p_seller_code` → `fn_resolve_seller_reference`; self-reference blocked when buyer id provided on lookup.
- **Admin entry mode** — `line_item_amount` (SKU lines with amounts), `line_item_derived` (qty × price), or `total_only` (`p_receipt_total` required on preview/approve). Resolved from merchant/plan `feature_config.receipt_entry_mode` via `bff_get_upload_receipt_config`.
- **Transaction number on approve** — `p_transaction_number` mandatory for `approve`; preview may run without it.
- **Deduplication on approve** — Duplicate `purchase_ledger.transaction_number` blocks approve. Scope: same store-channel attribute group when store has a channel attribute; else exact store; else merchant-wide. Preview **warns**; approve **blocks**. Separate helpers (`fn_receipt_upload_duplicate_matches`, OCR receipt-id checks) support admin duplicate panels and OCR—see System.
- **Reject** — Sets `status = rejected`, stores reason in `notes`, records `admin_id`. May route through `chokepoint_post_receipt_event(rejected)` for LINE.
- **Submit notification** — After insert (`upload_receipts` / pending `api_create_receipt_upload`), `chokepoint_post_receipt_event(submitted)` emits member LINE “received receipt” when notification pipeline is enabled (Thai system templates by default).
- **Points on history** — When `purchase_ledger_id` exists and wallet earned rows exist, show actual points; else `estimated_points` only if display status is approved; deferred-sync approved-without-ledger displays as pending/processing.
- **Immutable approved audit** — Approved rows linked to `purchase_ledger_id` are the audit trail; purchase cancel/reverse flows go through purchase admin APIs (Front Line same-day cancel documented in Front Line guide).
- **Auto approve flag** — `feature_config.auto_approve` is read by OCR evaluation (`fn_ocr_evaluate_channel_receipt`) and auto-upload edges—not by the standard admin preview modal alone. Default manual queue remains when false.
- **Deferred CRM** — When `fn_get_upload_receipt_config.deferred_crm_confirm` is true (Future Park), approve may queue CRM sync instead of immediate local purchase; `crm_sync_*` columns drive member copy and display status. Full state machine → `FuturePark.md`.
- **Referral** — Receipt-upload purchases do not drive referral purchase conversion; marketplace/Shopify orders use `referral_claim`. Signup referral still applies at join (`Referral.md`).

## Journeys

### Admin journey

| Page | Owning repo | BFF / RPC |
| --- | --- | --- |
| Receipts Upload (queue + review) | loyalty-admin | `bff_list_receipt_uploads`, `v_receipt_upload_list`, `bff_approve_receipt_upload`, `bff_find_seller_by_code`, `bff_list_stores_for_receipt_upload`, `get_store_channels` |
| Upload Receipt settings | loyalty-admin | `bff_get_upload_receipt_config`, `bff_set_upload_receipt_config` |
| Future Park Receipt Approval | loyalty-admin | Batch OCR approve path (deferred CRM)—`FuturePark.md` |
| Front Line — Upload Receipt tab | loyalty-admin | `upload_receipts` (on behalf of member), storage `receipt-uploads`; optional camera autofill modal |
| Receipt OCR hints/products (when used) | loyalty-admin | `bff_get_receipt_ocr_hints`, `bff_upsert_receipt_ocr_hints`, `bff_get_receipt_ocr_channel_products`, `bff_upsert_receipt_ocr_channel_products`, `bff_get_receipt_ocr_set_rule`, `bff_upsert_receipt_ocr_set_rule` |

| Setting | Effect on behaviour |
| --- | --- |
| Entry mode (`receipt_entry_mode`) | Admin approve UI: line items vs receipt-total-only; drives required `p_receipt_items` / `p_receipt_total` |
| Auto approve | When true, OCR auto path may approve without manual queue; does not change manual Receipts Upload steps by itself |
| Earn channel — receipt upload config | Member-only: store picker mode, receipt number, purchase date, seller reference (`bff_upsert_single_earn_channel`) |
| Upload receipt feature flag | `fn_merchant_feature_resolve(earn_channel, upload_receipt)` — channel visibility on Earn surfaces |

1. Open **Receipts Upload** — pending list from `bff_list_receipt_uploads` / list view; filter by status.
2. Open a row — gallery from `images` (fallback `image`); member store/channel prefills when present.
3. **Preview** — `bff_approve_receipt_upload(action=preview)` with line items or total per entry mode; optional seller lookup via `bff_find_seller_by_code`.
4. **Approve** — same RPC `approve`; creates purchase + links `purchase_ledger_id`; duplicate transaction number blocked.
5. **Reject** — `reject` with reason; member notified via receipt LINE template when pipeline enabled.
6. **Upload Receipt settings** — change entry mode / auto approve; saved via `bff_set_upload_receipt_config`.
7. **Front Line** — staff uploads for identified member (multi-receipt session possible); same-day purchase reverse uses purchase cancel BFF—not receipt row delete.

### Member journey

| Surface | Owning repo | BFF / RPC |
| --- | --- | --- |
| Earn → Upload receipt | loyalty-user | `bff_get_earn_channels` → `upload_receipts` |
| Store / channel pickers | loyalty-user | `get_store_channels`, `bff_list_stores_for_receipt_upload` |
| History (upload receipt filter) | loyalty-user | `bff_get_upload_receipt_history` |

1. Member opens **Earn** and taps the receipt upload channel (`earn_method = receipt_upload`).
2. Optional fields per channel config — store/channel picker, receipt number, purchase date, seller code.
3. Member captures or selects image(s); client uploads to storage, then calls `upload_receipts` once with all page URLs for **one** receipt.
4. Success — pending message; LINE “submitted” when enabled.
5. **History** — filter pending/approved/rejected; processing state when approved but purchase not yet visible (deferred CRM).

## System

### Data model

| Object | Role |
| --- | --- |
| `purchase_receipt_upload` | Canonical upload row: `status`, `images`/`image`, `earning_channel_id`, `store_id`, `seller_id`, member prefill (`receipt_number`, `transaction_date`), `purchase_ledger_id`, `approved_method` (`admin` \| `auto`), CRM sync fields (`crm_sync_status`, `crm_sync_error_code`, `crm_sync_error_params`, …), legacy `batch_id`, `external_user_ref`, `mongo_id`, `upload_at_store_id` |
| `purchase_receipt_upload_review_audit` | Append-only admin review snapshots (`trg_purchase_receipt_upload_admin_review` on status-changing updates) |
| `earn_channel` | Member UX + attribution; receipt-specific keys in `config` (`receipt_selection`, `receipt_number`, `purchase_date`, `seller_reference`) |
| `feature_config` (`feature_key = upload_receipt`) | `receipt_entry_mode`, `auto_approve`; extended keys via `fn_get_upload_receipt_config` (`deferred_crm_confirm`, `points_engine`, sync time/timezone, amount limit action) |
| `receipt_approval_rules`, `receipt_ocr_hints`, `receipt_ocr_channel_product`, `receipt_ocr_set_rule` | OCR/approval configuration per store attribute / set (evaluated in OCR flows; Future Park depth in `FuturePark.md`) |
| `purchase_ledger` / `purchase_items_ledger` | Created on approve; `transaction_source = receipt_upload`, images copied to purchase |
| `v_receipt_upload_list` | Admin list join: user, channel, store, purchase, wallet points/tickets |
| `v_receipt_upload_batch_summary` | Legacy batch aggregation by `batch_id` |

Live `purchase_receipt_upload.status` default `pending`; `crm_sync_status` NOT NULL (default `not_applicable`). `image` nullable in schema (prefer `images`).

### Functions

| Function | Role |
| --- | --- |
| `upload_receipts` | Member insert (single URL or page array; optional seller overload); emits `chokepoint_post_receipt_event(submitted)` |
| `api_create_receipt_upload` | Service/edge insert with full column set |
| `bff_approve_receipt_upload` | Admin `preview` / `approve` / `reject`; approve → `api_create_purchase` + seller currency when applicable |
| `bff_list_receipt_uploads` | Cursor list for admin queue |
| `bff_list_stores_for_receipt_upload` | Keyset store picker (member + admin) |
| `bff_find_seller_by_code` | Admin seller lookup before approve |
| `bff_get_upload_receipt_config` / `bff_set_upload_receipt_config` | Merchant admin entry mode + auto approve |
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

**OCR / auto edges (platform)** — Render edges include `receipt-upload-user`, `upload-receipts-auto-preview`, `upload-receipts-auto-confirm`, `approve-receipts-admin`, `receipt-preview-v2`, `forward-receipt*`, `admin-receipt-batch-*` (`REGISTRY_RENDER.md`). Future Park wires the full OCR pipeline; other merchants may use subsets.

### External services

- **Supabase Storage** — Public image URLs referenced on rows (member apps: `images` bucket paths; Front Line `receipt-uploads`).
- **Render edge functions** — User upload proxy, OCR preview/confirm, admin batch tooling (JWT/public per function).
- **Inngest** — Receipt notification routing; Future Park CRM confirm cron/service separate.

### Known gaps

- **Registry vs config keys** — Admin BFF exposes `entry_mode`; `feature_config` stores `receipt_entry_mode` (live both).
- **Auto approve** — UI setting exists; non-OCR merchants may see no effect until OCR/auto edges are enabled.
- **Daily image limit** — Functions exist; generic `upload_receipts` may not enforce—Future Park enforces in preview edge (see `FuturePark.md`).
- **`get_receipt_upload_history` overloads** — Still batch-centric; primary member app uses `bff_get_upload_receipt_history`.
- **OCR table suite** — Shared schema; productized admin UX may be merchant-specific—document operational detail under Future Park when applicable.

## Related

- **Earn Channel** — Receipt card visibility, member config keys, registry `purchase:receipt_upload` → `Earn_Channel.md`.
- **Purchase Transaction** — Purchase creation, cancel, seller lines → `Purchase_Transaction.md`.
- **Currency** — Earn via purchase triggers → `Currency.md`.
- **FuturePark** — OCR, deferred CRM, batch approve, validation reason codes → `FuturePark.md`.
- **Notification Service** — LINE Flex templates and outbox → `Notification_Service.md` (receipt category).
- **Referral** — Purchase referral attribution excludes receipt upload source → `Referral.md`.
- **Front Line** — Staff upload and same-day purchase reverse → loyalty-admin `ProjectDocs/FE_docs/FrontLine.md`.
