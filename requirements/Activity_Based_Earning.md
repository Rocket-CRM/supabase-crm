# Activity-Based Earning

Members submit photo proof of a merchant-defined activity; operators review submissions, enter structured dimension values, and approval credits points and/or tickets from a **currency matrix** (primary dimension × secondary fields). Awards post synchronously to the wallet on approval — the same direct-post pattern as reward redemption, not an async earn pipeline.

Owner surfaces: loyalty-admin (approval queue), loyalty-user (upload + history), Open API (`upload_activity_image`, activity display/history RPCs)

## Concept

Activity-based earning is a **proof-and-approve** earn path beside purchase, check-in, missions, and receipts. A merchant runs one or more **activity programs** (for example exercise check-ins or POSM audits). Each program defines what evidence members submit (typically one image), which **dimensions** operators use when scoring a submission, and how each dimension combination maps to currency.

**Activity program** — Named earn mechanic with display copy, field schema, optional how-to content, primary pivot field, and active flag.

**Upload** — A member’s submission row: image URL, optional auto-captured profile fields, workflow status, and operator-entered dimension values after review.

**Dimension field** — Configured input used for matrix lookup. **Manual** fields are chosen by the operator from a fixed option list at approval time. **Auto-populate** fields copy from the member’s USER_PROFILE form at upload time and are read-only in the approval UI.

**Primary dimension** — The field whose values become matrix columns (for example time of day or display size).

**Secondary dimension** — Each other manual field can own a separate matrix “grid”: rows are that field’s values, columns are primary values, cells are currency amounts.

**Matrix cell** — One primary value + secondary field + secondary value → points and/or ticket grants.

**Frequency limit** — Reuses the shared participation-limit store with entity type activity and entity id = program id; enforced at upload and again at approval (pending rows count toward caps).

**Post-approval edit** — Operators may correct field values on already-approved or rejected uploads with a mandatory reason; the system recalculates currency and applies wallet **deltas** (including partial reversal when reducing awards).

Do not confuse this domain with **marketing activity logging** (`activity_type_master`, UTM attribution) — see Activity_Attribution.md.

## Rules

- If the activity program is inactive or unknown → member display/upload APIs return not-found style errors.
- **Upload limits:** If any configured limit for the program is exceeded (including pending + approved rows in the window) → `upload_activity_image` fails with limit metadata (current count, max, next available time when applicable).
- **Approval limits:** If limits would be exceeded when approving (race with other pending rows) → approve fails with limit metadata; upload row stays pending.
- **Field validation** runs at approval (and on edit), not at upload: required manual fields must be present; each value must match configured options. Auto-populate fields are not re-validated as manual picks.
- **Matrix match:** For each secondary field on the program, the system matches operator `field_values` to matrix rows: `primary_value` equals the primary dimension’s value; `secondary_field` and `secondary_value` must match exactly. Unmatched combinations award zero for that secondary matrix; multiple secondaries can each contribute currency in one approval.
- **Currency:** Points and tickets may both post in one approval. Snapshot columns on the upload row store totals; wallet rows use `source_type = activity` and `source_id = upload id` with matrix metadata (detail in ACTIVITY_WALLET_INTEGRATION.md).
- **Approval atomicity:** Status moves to approved only if wallet posting succeeds; otherwise the transaction rolls back.
- **Reject:** Pending → rejected with reason; no wallet movement.
- **Cancel:** Status `cancelled` is valid in the ledger model; member cancel RPC is not exposed in loyalty-user (see Known gaps).
- **Edit (approved or rejected only):** Operator supplies new field values and non-empty reason → `bff_edit_activity_upload` recalculates awards, appends `edit_history`, bumps `edit_version`, and applies wallet adjustments (earn or burn components) including FIFO partial reversal when reducing below already-consumed balance. Pending and cancelled uploads are not editable via this path.
- **Re-approve from rejected:** Edit flow may set status back to approved and clear rejection fields when matrix validation passes.
- **i18n:** User-facing titles/descriptions for upload, list, and status use activity translation helpers with `p_language`.

**Status model**

| Status | Member-visible meaning | Wallet |
| --- | --- | --- |
| `pending` | Submitted; awaiting review | None |
| `approved` | Accepted; currency granted (or adjusted via edit) | Earn rows linked to upload |
| `rejected` | Declined; reason shown | None |
| `cancelled` | Withdrawn / voided before completion | None |

Valid transitions: `pending` → `approved` | `rejected` | `cancelled`; `approved` | `rejected` → `approved` via edit (with deltas); no member-facing transition from `approved` back to `pending`.

## Journeys

### Admin journey

| Page | Owning repo | BFF / RPC |
| --- | --- | --- |
| Activity Uploads (queue) | loyalty-admin | `bff_get_activity_uploads`, `bff_approve_activity_upload`, `bff_reject_activity_upload`, `bff_edit_activity_upload` |
| Activity program + matrix (configuration) | — (RPC-only in repo) | `bff_upsert_activity_master`, `bff_upsert_activity_currency_matrix`, `api_get_activity_full`, `bff_get_activity_matrix` |

| Setting | Effect on behaviour |
| --- | --- |
| Activity code / name / active | Identity and whether members can load or upload |
| Field definitions + primary dimension | Approval form fields and matrix shape |
| How-to / banner / label / header | Member upload page presentation (`api_get_activity_display`) |
| Currency matrix rows | Points and ticket amounts per primary × secondary combo |
| `transaction_limits` (entity activity) | Per-user or global caps by day/week/month/year/lifetime |
| Edit reason (on correction) | Required audit string stored in edit history and wallet metadata |

1. Configure the program and matrix via admin tooling that calls the upsert/matrix RPCs (no dedicated Next.js settings route in loyalty-admin today — operators may use legacy WeWeb or direct RPC).
2. Open **Activity Uploads**; filter tabs (All / Pending / Approved / Rejected) and search the queue.
3. Open a row → review image, member context, and field editor (auto-populate fields read-only).
4. **Pending:** enter manual dimension values → **Approve** (wallet credit) or **Reject** with reason.
5. **Approved or rejected:** **Edit** → change values, enter reason → **Save**; UI shows currency deltas and edit history; list row patches from response.

Common pitfalls: limits count pending rows — approving two pendings in parallel can fail the second; matrix must include a cell for every combination operators intend to pay; reducing awards after members spent points may leave `unreversed_amount` on edit deltas.

### Member journey

| Page / surface | Owning repo | BFF / RPC |
| --- | --- | --- |
| Upload Activities | loyalty-user | `api_get_activity_display`, `upload_activity_image` |
| Upload history drawer | loyalty-user | `api_get_my_activity_uploads` |
| Earn drawer / deep link | loyalty-user | Routes into Upload Activities when earn method routes to activity code |

1. Member opens **Upload Activities** (from earn entry or deep link with activity code/id); app loads display config (banner, header, how-to).
2. Member attaches photo → **Submit** → `upload_activity_image` with image URL (storage upload is client-side).
3. On success → toast that submission is pending review; member may open **history** for status list.
4. On limit error → toast/banner with limit copy from RPC envelope.
5. When operator approves → history shows approved status and awarded amounts; wallet history may show activity earn lines (`source_type` activity).
6. When operator rejects → history shows reason; no balance change.

| Error (member-visible) | Typical cause |
| --- | --- |
| Upload limit reached | Frequency cap including pending |
| Activity not found | Inactive or wrong code/id |
| Could not upload photo | Storage or RPC failure |

## System

### Data model

| Artifact | Role |
| --- | --- |
| `activity_master` | Program header: code, name, description, `field_definitions` JSON, `primary_dimension`, media/how-to copy (`howto_banner`, `howto_description`, `label`, `header`, `icon_url`, `banner_urls`), `active_status` |
| `activity_currency_config` | Matrix cells: `activity_id`, `primary_value`, `secondary_field`, `secondary_value`, `points_amount`, optional `ticket_type_id` + `ticket_amount`, `active_status`; unique per combo |
| `activity_upload_ledger` | Submissions: `user_id`, `activity_id`, `image_url`, `field_values`, `status`, timestamps, approver/rejector ids, `rejection_reason`, award snapshots, `currency_processed_at` / `currency_error`, `edit_version`, `edit_history` JSON |
| `transaction_limits` | Caps where `entity_type = 'activity'` and `entity_id` = program id (shared limit machinery with check-in and other entities) |
| `wallet_ledger` | Earn/burn lines from approval and edits (`source_type = activity`) |

`field_definitions` entries support `type: manual` (with `options`, `required`, `order`) or `type: auto_populate` (with `field_key` into USER_PROFILE `form_responses`). Values are stored on the upload row at submit time for auto fields.

### Functions

| Function | Role |
| --- | --- |
| `upload_activity_image` | Member create pending row; upload-time limit check; optional auto-populate |
| `api_get_activity_display` | Member read presentation config by id or code |
| `api_get_my_activity_uploads` | Member history with optional status filter and pagination |
| `api_get_activity_full` | Admin load program + pivot-friendly matrix (`columns`, `config.matrices[]`) for grid UIs |
| `bff_get_activity_matrix` | Admin matrix read (alternate shape) |
| `bff_upsert_activity_master` | Admin create/update program header and fields |
| `bff_upsert_activity_currency_matrix` | Admin replace matrix configs for a program |
| `bff_get_activity_uploads` | Admin queue with enriched member + field definitions |
| `bff_approve_activity_upload` | Validate fields → approval limits → `fn_calculate_activity_currency` → `post_wallet_transaction` → approve |
| `bff_reject_activity_upload` | Pending → rejected |
| `bff_edit_activity_upload` | Recalculate matrix, wallet deltas, append edit history |
| `fn_validate_activity_field_values` | Required/options check |
| `fn_check_activity_upload_limits` | Upload gate |
| `fn_check_activity_approval_limits` | Approval gate (excludes or accounts for current upload id) |
| `fn_calculate_activity_currency` | Matrix resolution for given field values |
| `translate_activity_message` / `translate_activity_status` | Localized envelopes |

Open API and member RPCs accept `p_activity_id` or `p_activity_code` where noted in signatures.

### Flows

**Upload (sync):** Resolve program → `fn_check_activity_upload_limits` → insert `activity_upload_ledger` (`pending`) with image URL and auto field values → return success envelope.

**Approve (sync):** Load pending row → `fn_validate_activity_field_values` → `fn_check_activity_approval_limits` → `fn_calculate_activity_currency` → for each currency line call `post_wallet_transaction` (`source_type` activity, `source_id` upload, component `base`, rich metadata) → set approved timestamps and award snapshots.

**Reject (sync):** Validate pending → set rejected + reason; no wallet calls.

**Edit (sync):** Row lock → validate fields and limits → recompute matrix → compute deltas vs prior awards → post adjustment/reversal wallet rows (FIFO consumption rules per wallet integration) → update field values, totals, `edit_history`, status approved.

**Matrix admin read:** `api_get_activity_full` returns shared column defs plus one pivoted `data` array per secondary field for data-grid binding (legacy WeWeb pattern; same RPC used by any future loyalty-admin matrix UI).

### External services

Image hosting uses merchant/client storage (URL passed into RPC). No dedicated Render/Inngest worker for activity earn — approval and edit are database-synchronous.

### Known gaps

- **Activity program / matrix UI in loyalty-admin** — Approval queue is shipped (`/approve-activities-upload`); master and matrix upsert RPCs exist but no Next.js configuration page in loyalty-admin (types/i18n only). Operators rely on external admin or RPC until a settings route ships.
- **Member cancel** — `cancelled` status exists on ledger; no loyalty-user cancel action wired.
- **Auto-populate detail doc** — Legacy link `Activity_Auto_Populate_Fields.md` was never added; behaviour is summarized above (USER_PROFILE `field_key` → upload `field_values`).
- **activity-types admin page** — Configures CDP **activity types** for attribution (`bff_upsert_activity_type`), not upload earning programs.

## Related

- **Currency.md** — Wallet posting, limits entity types, expiry on earn.
- **ACTIVITY_WALLET_INTEGRATION.md** — Audit shape and `source_type = activity` metadata.
- **Activity_Attribution.md** — `activity_ledger` / UTM logging (orthogonal to upload earning).
- **Forms.md** — USER_PROFILE form and `form_responses` for auto-populate fields.
- **Earn_Channel.md** — Routing members into upload surfaces from earn methods.
- **Event_Promotion.md** — “Activity group” on events is promo mapping vocabulary, not this upload matrix.
