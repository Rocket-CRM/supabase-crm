# Feature Guide: Activity-Based Earning

## 1. Overview

Activity-Based Earning is an image-upload-based earning mechanism where members submit proof photos of completed activities (exercise, POSM checks, volunteer work) and earn currency upon admin approval. Unlike purchase-based earning which processes transactions automatically, this feature requires human review — a member uploads an image, an admin classifies the submission by selecting field values, and the system calculates the currency award from a pre-configured pricing matrix.

The pricing matrix is the core concept: merchants define a two-dimensional grid where one axis (the primary dimension) crosses with one or more secondary fields to produce specific currency amounts. For example, an exercise activity might award different points for "yoga in the morning" (50 pts) versus "running in the evening" (45 pts). This lets merchants incentivize specific combinations of activity attributes without building custom logic for each one.

Key characteristics: (1) **matrix-based pricing** — a 2D grid of primary × secondary values determines exact currency amounts per combination; (2) **dual-validated frequency limits** — checked at both upload time and approval time to prevent race conditions; (3) **synchronous currency award** — admin approval immediately deposits currency into the member's wallet (no async queue); (4) **dynamic field definitions** — each activity defines its own set of fields that admins fill during review, including auto-populated fields pulled from the member's profile.

## 2. Key Concepts

**Activity** — A merchant-defined activity type that members can submit uploads for. Identified by a unique code (e.g., `exercise`, `posm_check`). Each activity defines its own field definitions, primary dimension, and currency matrix. Example: "Exercise Activity" with fields for exercise type, time of day, and location.

**Field Definition** — A configurable field attached to an activity. Two types exist:
- `manual` — Admin selects a value from predefined options during review. Example: exercise_type with options [yoga, running, swimming].
- `auto_populate` — Value pulled automatically from the member's USER_PROFILE form data at upload time. Example: user_tier pulled from the member's membership_tier field.

**Primary Dimension** — The field whose values become columns in the currency matrix. Only one field per activity serves as the primary dimension. Example: if `time_of_day` is primary, columns are "morning", "afternoon", "evening".

**Secondary Field** — Any non-primary field that creates rows in the matrix. Multiple secondary fields produce multiple matrix tables for the same activity. Example: `exercise_type` as secondary creates one matrix; `location` as secondary creates another.

**Currency Matrix** — A 2D pricing grid: primary dimension values × secondary field values → currency amounts. Each cell defines points and/or tickets to award. Example: morning × yoga = 50 points; evening × running = 55 points + 2 raffle tickets.

**Upload Ledger** — The record of a member's activity submission, tracking the uploaded image, status, field values (filled by admin), and currency awarded. One record per upload.

**Status** — The lifecycle state of an upload: `pending` (submitted, awaiting review), `approved` (admin approved, currency awarded), `rejected` (admin rejected, no currency), `cancelled` (member cancelled before review).

**Frequency Limit** — A cap on how many uploads a member (or all members globally) can submit within a time window. Reuses the platform's `transaction_limits` table with `entity_type='activity'`. Multiple limits can stack (e.g., 1/day AND 7/week AND 30/month).

## 3. Configuration Reference

### Activity Setup

| Setting | What it controls | Example | Default |
|---|---|---|---|
| Activity code | Unique identifier | `exercise` | Required |
| Activity name | Display name | "Exercise Activity" | Required |
| Description | Activity description | "Upload your workout photo" | Empty |
| Icon URL | Activity icon | PNG/SVG URL | None |
| Banner URLs | Banner images (array) | Multiple image URLs | Empty |
| Active status | Whether activity accepts uploads | true | true |

### Field Definitions

| Setting | What it controls | Example | Default |
|---|---|---|---|
| Field key | Identifier used in matrix matching | `exercise_type` | Required |
| Type | `manual` or `auto_populate` | `manual` | Required |
| Label | Display name in admin form | "Type of Exercise" | Required |
| Options | Allowed values (manual fields only) | ["yoga", "running", "swimming"] | Required for manual |
| Field key source | USER_PROFILE form field (auto_populate only) | `membership_tier` | Required for auto_populate |
| Required | Must be filled to approve | true | false |
| Order | Display order in admin form | 1 | — |

### Currency Matrix

| Setting | What it controls | Example | Default |
|---|---|---|---|
| Primary dimension | Which field creates matrix columns | `time_of_day` | Required |
| Primary value | Column value | "morning" | Per cell |
| Secondary field | Which field creates matrix rows | `exercise_type` | Per matrix |
| Secondary value | Row value | "yoga" | Per cell |
| Points amount | Points to award for this combination | 50 | 0 |
| Ticket type ID | Optional ticket type reference | UUID | null |
| Ticket amount | Tickets to award | 2 | 0 |

### Frequency Limits

| Setting | What it controls | Example | Default |
|---|---|---|---|
| Scope | Who the limit applies to | `user` or `total` | — |
| Time unit | Period of the limit | `day`, `week`, `month`, `year` | — |
| Count | Maximum uploads in period | 1 | — |
| Active status | Enable/disable this limit | true | true |

## 4. Admin Journey

### 4a. Activity Configuration (WeWeb Admin)

**Platform:** WeWeb admin dashboard

**Route map:**

| Page name | Current route | BFF / data source |
|---|---|---|
| Activity Settings | WeWeb activity page | `api_get_activity_full(p_activity_id, p_mode)` |
| Matrix Editor | Within Activity Settings | `bff_upsert_activity_currency_matrix(p_activity_id, p_matrix_configs)` |

1. Open **Activity Settings** — in create mode (empty) or edit mode (pre-populated)
2. Fill activity info: code, name, description, icon, banners
3. Define fields: add manual fields with option lists, add auto_populate fields with profile field key mappings, set one field as primary dimension
4. Configure currency matrix: a Data Grid renders one table per secondary field, with primary dimension values as columns — enter points and ticket amounts per cell
5. Save via `bff_upsert_activity_master` (activity + fields) and `bff_upsert_activity_currency_matrix` (matrix cells)

### 4b. Review Uploads (Next.js Admin)

**Repo:** `Rocket-CRM/loyalty-admin`

**Route map:**

| Page name | Current route | BFF / data source |
|---|---|---|
| Activity Uploads | `/approve-activities-upload` | `bff_get_activity_uploads(p_status_filter, p_activity_id, p_limit, p_offset)` |
| Review Modal | Modal on Activity Uploads | `bff_approve_activity_upload(p_upload_id, p_field_values)` |
| Reject Modal | Modal on Activity Uploads | `bff_reject_activity_upload(p_upload_id, p_rejection_reason)` |

1. Open **Activity Uploads** — IndexTable with tabs: All, Pending, Approved, Rejected (each with count)
2. Search bar filters by member name, phone, email, or activity name
3. Columns: thumbnail, Member, Activity, Status (badge), Points, Tickets, Date
4. Click any row → **Review Modal** opens (two-column layout)
5. Left panel: uploaded image, member name/phone/email, awarded points (if approved), rejection reason (if rejected)
6. Right panel: activity details + **dynamic field editor** — renders Select dropdowns for manual fields, TextFields for other types
7. Fill in field values from the image evidence, then click **Approve** → `bff_approve_activity_upload` validates fields, checks limits, calculates currency from matrix, awards directly to wallet
8. Or click **Reject** → opens **Reject Modal** with reason text field → `bff_reject_activity_upload`
9. Already-processed uploads open in read-only mode (no action buttons)

### 4c. Common Admin Mistakes

- Forgetting to set the primary dimension → matrix cannot render correctly
- Setting required fields but leaving options empty → admin cannot select values during review
- No matrix cells configured for a field combination → zero currency awarded on approval (not an error — just no matching price)
- Approving without filling required fields → validation error returned
- Configuring auto_populate fields with a `field_key` that doesn't exist in the USER_PROFILE form → null values at upload time
- No frequency limits configured → members can upload unlimited times

## 5. Member Experience

**Repo:** `Rocket-CRM/loyalty-user`

**Route map:**

| Page / Component | Current route | Data source |
|---|---|---|
| Earn Drawer | Bottom-sheet from Homepage | `bff_get_earn_channels()` |
| Activity Upload | Within Earn Drawer | `upload_activity_image(p_activity_id, p_image_url)` |
| History Drawer | Bottom-sheet from Homepage/Profile | `bff_get_campaign_history(p_filter='activity')` |

### 5a. Upload an Activity Image

1. Member opens the **Earn Drawer** and selects the activity earn channel
2. Member takes or selects a photo and uploads to Supabase Storage
3. App calls `upload_activity_image` with the activity ID and image URL
4. Backend checks frequency limits — if exceeded, returns error with `next_available_at` timestamp
5. On success: upload ledger record created with `status='pending'`, member sees confirmation message ("Your submission is pending admin approval")

### 5b. View Upload History

1. Member opens **History Drawer** → selects **Campaigns** tab → **Activity** sub-filter chip
2. Each row shows: activity name, submission date, status, points/tickets awarded (if approved)
3. Statuses displayed: Pending, Approved, Rejected

## 6. Perspectives

### 6a. For Customer Success / Support

**Elevator pitch:** "Activity uploads let your members earn points by proving they did something — exercise, store visits, POSM compliance checks. They upload a photo, your team reviews it, and points are awarded automatically based on what they did."

**Top support questions:**

| Question | Answer |
|---|---|
| "Member says upload was rejected" | Check the rejection reason in the review modal — admin provides a reason when rejecting. Member should re-upload with correct proof. |
| "Member can't upload — says limit reached" | Frequency limits are active. Check `transaction_limits` for this activity — shows max uploads per period and when the next window opens. |
| "Upload approved but no points received" | Check `currency_error` on the upload ledger record. If the matrix has no matching cell for the field values selected, zero points are awarded — not an error, but a configuration gap. |
| "How long until my upload is reviewed?" | No SLA — depends on admin review queue. Check pending count in the Activity Uploads page. |

### 6b. For Marketing

**Value proposition:** Activity-Based Earning turns real-world actions into loyalty engagement. Instead of only earning from purchases, members earn by doing things the brand wants to encourage — exercising, visiting stores, verifying product displays. The matrix-based pricing lets merchants fine-tune incentives per combination (morning yoga earns more than evening yoga) without custom development.

**Use-case stories:**

1. **Fitness brand** — Creates an "Exercise" activity with time × exercise type matrix. Morning workouts earn more points than evening ones, incentivizing early activity. Members upload gym selfies or fitness tracker screenshots. Multiple limits (1/day, 7/week) encourage daily habits without bulk gaming.

2. **CPG distributor (POSM)** — Creates a "POSM Check" activity where field reps upload photos of in-store displays. Matrix prices by display size (S/M/L) × check type (planogram compliance vs. POSM presence). Larger displays and correct planograms earn more. Monthly upload limit matches the visit cadence.

3. **Wellness campaign** — Combines activity earning with missions. Mission tracks "3 approved exercise uploads this week" as a completion condition. Activity points stack on top of mission completion rewards, creating a double-incentive loop.

**Metrics merchants care about:** uploads per day, approval rate, average time-to-review, total currency awarded by activity type, top uploading members, matrix cell utilization (which combinations are most common).

### 6c. For Testers

**Config → expected behavior:**

| Config | Expected behavior |
|---|---|
| Limit: 1/user/day, member already uploaded today | Upload blocked with "limit reached" + next_available_at |
| Limit: 1/user/day, upload pending, member tries again | Upload blocked — pending uploads count toward limits |
| No matrix cell for selected field combination | Approval succeeds with 0 points awarded |
| Required field left empty by admin | Approval fails with validation error listing missing fields |
| Invalid option value for manual field | Approval fails with validation error listing invalid values + allowed options |
| Activity `active_status = false` | Uploads blocked |
| Auto_populate field with no profile data | Field value is null — handled based on required flag |

**Business rules as assertions:**

- ASSERT: Upload creates ledger record with `status='pending'`, `field_values=null`
- ASSERT: Frequency limit counts both `pending` and `approved` uploads in the time window
- ASSERT: Frequency limit is re-checked at approval time (not just upload time)
- ASSERT: On approval, `chokepoint_post_wallet_transaction` creates wallet_ledger entries with `source_type='activity'` and `source_id=upload_id`
- ASSERT: Points + tickets can both be awarded from a single matrix cell
- ASSERT: Multiple matrix tables (one per secondary field) can each award currency from the same upload
- ASSERT: Rejected upload records `rejected_by` and `rejection_reason`
- ASSERT: Approved upload records `approved_by`, `approved_at`, `points_awarded`, `tickets_awarded`
- ASSERT: Currency award is atomic with approval — if wallet transaction fails, approval rolls back

**Status model (single track):**

| Field | Values | Transition | Meaning |
|---|---|---|---|
| `status` | `pending` | → `approved` | Admin approved, currency awarded |
| `status` | `pending` | → `rejected` | Admin rejected, no currency |
| `status` | `pending` | → `cancelled` | Member cancelled before review |

- No transitions from `approved`, `rejected`, or `cancelled` — these are terminal states
- Currency is only awarded on the `pending → approved` transition

## 7. Business Rules

**Rule:** Frequency limits are dual-validated — checked at upload time (member-facing) and re-checked at approval time (admin-facing, prevents race conditions where a second upload squeaks in before the first is approved).
**Example:** Limit = 1/day. Member uploads at 9:00. Second upload at 9:01 is blocked. If admin somehow has two pending from a race condition, second approval fails.

**Rule:** Frequency limit counting includes both `pending` and `approved` uploads in the window. Rejected and cancelled uploads do not count.
**Example:** Limit = 3/week. Member has 2 approved + 1 pending this week = 3 total. Next upload is blocked.

**Rule:** Currency is calculated by matching field values against `activity_currency_config`. The primary dimension value must match `primary_value`, and the secondary field/value must match exactly.
**Example:** Field values: {time_of_day: "morning", exercise_type: "yoga"}. Primary dimension = time_of_day. Matches cell: primary_value="morning", secondary_field="exercise_type", secondary_value="yoga" → 50 points.

**Rule:** Multiple matrix tables (one per secondary field) can each contribute currency from a single upload. Awards are additive.
**Example:** Exercise activity has two matrices: time × exercise_type (50 pts) and time × location (25 pts). Member's upload matches both → 75 total points.

**Rule:** Currency award uses `chokepoint_post_wallet_transaction()` directly — synchronous, atomic with the approval. If the wallet transaction fails, the entire approval rolls back.
**Example:** Admin clicks Approve → field validation passes → matrix match found → wallet transaction attempted → if wallet error, upload stays `pending`.

**Rule:** Field validation at approval time requires all `required` fields to have values, and manual field values must be in the defined options list.
**Example:** exercise_type is required with options [yoga, running]. Admin submits "dancing" → validation error: "invalid value, allowed: yoga, running."

**Rule:** Auto-populated fields are fetched from the member's USER_PROFILE form responses at upload time and stored in the ledger record. They are not re-fetched at approval time.
**Example:** Member's tier at upload time was "Gold". Even if they upgrade to "Platinum" before approval, the stored value remains "Gold".

## 8. Related Features

| Feature | Connection to Activity-Based Earning |
|---|---|
| Currency | Points/tickets awarded via `chokepoint_post_wallet_transaction()` with `source_type='activity'`. See `Currency.md`. |
| Mission | Missions can track "activity upload approved" as a progress event. See `Mission.md`. |
| Transaction Limits | Reuses `transaction_limits` table with `entity_type='activity'` for frequency caps. See `Purchase_Transaction.md`. |
| Forms | Auto-populate fields pull values from USER_PROFILE form responses. See `Forms.md`. |
| Earn Channels | Activity upload appears as an earn channel in the member app. See earn channel configuration. |
