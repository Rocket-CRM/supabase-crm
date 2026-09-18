# Consent

Merchant-configurable legal documents (privacy, terms, marketing), communication channel toggles, and topic opt-ins — with an append-only consent ledger for PDPA audit.

Owner surfaces: loyalty-admin (Consent settings), loyalty-user (signup/profile PDPA step, Consent Management drawer), Shopify storefront (read-only consent documents via merchant code + display chrome)

## Concept

**Notice vs consent** — A **notice** is display-only (“we showed you this”); no checkbox and no ledger row. A **consent** requires an explicit accept/decline; each decision appends to history. Interaction style is configured per version (`notice`, `required`, `optional`).

**Consent type** — One of three legal buckets: privacy policy, terms of service, or marketing. Each type can have many historical versions; only one version per type may be **active** for members at a time.

**Consent version** — Immutable legal text identified by `version_code`, with title, preview, body, display order, and mandatory flag. Activating a version publishes it (`published_at`); deactivation is soft (row kept for ledger integrity).

**Consent ledger** — Per-user, per-version audit log: accepted, withdrawn, or rejected. Current stance for a version is the **latest** row by time — never update or delete ledger rows.

**Communication channel** — Fixed delivery paths (email, SMS, LINE, push) stored as booleans on the member record — “may we contact you on this channel?”

**Communication topic** — Merchant-defined subscription category (e.g. promotions, newsletter). Per-user opt-in is stored separately from channels. Outbound messaging should require **channel enabled and topic opted in** when both apply.

**Profile PDPA slice** — Signup and profile flows embed consent UI in the `pdpa` section of the profile template (`missing_data` from auth hub). Save is shared with profile fields via one member save RPC.

## Rules

- **One active version per consent type per merchant** — Activating a second version of the same type without deactivating the first fails (partial unique index on active rows).
- **Unique version codes** — `(merchant_id, version_code)` must be unique.
- **`interaction_type = notice`** — Shown in the notices bucket; `requires_action` false; no ledger write on save.
- **`interaction_type = required`** — Checkbox required; member UI blocks submit until accepted; ledger records `accepted` or `withdrawn` on save.
- **`interaction_type = optional`** — Checkbox optional; ledger still records accept/withdraw when the member submits.
- **Ledger actions** — Enum: `accepted`, `withdrawn`, `rejected`. Append-only; status = latest row for `(user_id, consent_version_id)`.
- **Soft deactivation** — Admin “delete” sets `active_status = false` on versions and topics; no hard deletes of config rows that ledger entries reference.
- **Activation** — First time `active_status` becomes true with null `published_at`, server stamps `published_at = now()`.
- **Translations** — Active consent copy resolves `title`, `preview`, `content` from the translation system (`entity_type = consent_version`) with fallback to base columns.
- **Cache** — Changes to `consent_versions` or `communication_topics` invalidate cached profile/consent templates (`fn_trigger_invalidate_user_profile_cache` via triggers).
- **Channels** — Four booleans on `user_accounts` (`channel_email`, `channel_sms`, `channel_line`, `channel_push`); updated on profile save from the PDPA `channels` payload.
- **Topics** — Composite preference per `(user_id, topic_id)`; upsert on save; invalid UUIDs in payload are skipped (no error).
- **Access control** — Consent tables have no RLS; merchant and member context enforced inside `SECURITY DEFINER` BFFs (`get_current_merchant_id()`, `auth.uid()`).
- **Admin permissions** — Consent settings use `global_setting` resource: Owner/Admin read+write; Admin cannot delete/deactivate where delete permission required; other roles read-only.

Example (send gate): email enabled + “Promotions” topic opted in → promotional email allowed; email enabled + topic opted out → blocked for that topic.

## Journeys

### Admin journey

| Knob | Effect |
| --- | --- |
| Consent version (type, interaction, copy) | What members see on signup/profile and in Consent Management |
| `active_status` / replace flow | Which version is live per type; replace warns when another active version exists |
| `order_index` | Display order within the member form |
| Communication topic | Optional categories for marketing opt-in grid |
| Topic `active_status` | Whether topic appears on member form |

| Page | Owning repo | BFF / RPC |
| --- | --- | --- |
| Consent settings | loyalty-admin | `bff_admin_get_consent_config`, `bff_admin_upsert_consent_config` |
| Display settings → Online store → Chrome (Shopify) | loyalty-admin | `privacy_consent_type` in display config (which document type the storefront footer uses) |

1. Open **Consent settings** — list loads all consent versions (with accepted/withdrawn counts) and communication topics (with subscriber counts).
2. **Add consent version** — set type, interaction (`notice` / `required` / `optional`), version code, title, preview, body, order; save inactive or active.
3. **Activate or replace** — turning on a version when another active version shares the same type prompts replace/deactivate first (DB enforces one active per type).
4. **Deactivate version** — soft-delete via upsert mode `delete_consent_version` (sets `active_status = false`).
5. **Topics** — create/edit/deactivate via upsert modes `topic` / `delete_topic`.
6. Members pick up changes on next template load (signup, profile edit, or Consent Management drawer) after cache invalidation.

`bff_admin_get_consent_config` mode `audit` returns aggregated ledger stats per version; no dedicated audit UI in loyalty-admin today (API-only).

### Member journey

| Surface | Owning repo | BFF / RPC |
| --- | --- | --- |
| Auth drawer → profile form → PDPA step | loyalty-user | Template from hub `missing_data`; save `bff_save_user_profile` |
| Profile → Consent Management | loyalty-user | `bff_get_consent_form_template` (`edit`), save `bff_save_user_profile` |
| Public consent read (Shopify chrome) | loyalty-user | `api_get_consent_documents_cached` (merchant code, no session) |

1. After auth, if hub returns `complete_profile_*`, member reaches profile steps; **PDPA** step shows notices (read-only), required/optional checkboxes, channel toggles, and topic toggles from embedded template data (same shape as `bff_get_consent_form_template`).
2. Submit blocked if any **required** consent in the form is unchecked; error copy lists missing titles.
3. On save, channels update on `user_accounts`; consent decisions append ledger rows; topic preferences upsert.
4. Existing members open **Profile → Consent Management** to change marketing/channel/topic choices without repeating full signup.
5. **Errors** — save failures surface generic profile save errors; permission/session loss returns to sign-in.

### Shopify

- Storefront **privacy link** type is configured in admin display chrome (`privacy_consent_type`, default `privacy_policy`); member app loads documents via `api_get_consent_documents_cached` using shop merchant code — not the session BFF `bff_get_consent_config`.
- Widget signup/profile still uses member JWT path (`bff_get_consent_form_template` / `bff_save_user_profile`) when the member completes standalone profile steps inside loyalty-user.

## System

### Data model

| Table / location | Role |
| --- | --- |
| `consent_versions` | Versioned legal documents per merchant (`consent_type`, `interaction_type`, `version_code`, copy, `active_status`, `order_index`, `published_at`) |
| `user_consent_ledger` | Append-only actions (`consent_version_id`, `action`, `ip_address`, `user_agent`, `created_at`) |
| `communication_topics` | Merchant-defined topic catalog |
| `user_communication_preferences` | `(user_id, topic_id)` → `opted_in`, `updated_at` |
| `user_accounts` | `channel_email`, `channel_sms`, `channel_line`, `channel_push` |
| `translations` | Localized `consent_version` fields |
| `stg_mongo_consent` | Legacy import staging (not member runtime) |

**Enums (live):** `consent_type` — `privacy_policy`, `terms_of_service`, `marketing`; `consent_interaction_type` — `notice`, `optional`, `required`; `consent_action` — `accepted`, `withdrawn`, `rejected`.

**Indexes (material):** `unique_version_code` on `(merchant_id, version_code)`; partial unique `unique_active_consent` on `(merchant_id, consent_type) WHERE active_status = true`.

### Functions

| Function | Role |
| --- | --- |
| `bff_get_consent_config(p_language)` | Active versions for merchant with translations (read-only catalog) |
| `bff_get_consent_form_template(p_mode, p_language)` | Member form: `notices`, `consents`, `channels`, `topics`; `new` vs `edit` prefill from ledger and preferences |
| `bff_save_user_profile(p_data)` | Consent slice: channels → `user_accounts`; PDPA items → ledger append; topics → preference upsert (see **Forms.md** / **Signup_Login.md**) |
| `bff_admin_get_consent_config(p_mode, p_language)` | Admin list (`list`) or ledger aggregates (`audit`) |
| `bff_admin_upsert_consent_config(p_data, p_language)` | Modes: `consent_version`, `topic`, `delete_consent_version`, `delete_topic` |
| `api_get_consent_documents_cached(p_merchant_code, p_language, p_consent_type)` | Public/cached active documents for storefront chrome (not in `REGISTRY_SUPABASE.md` grep snapshot — verified live) |

### Flows

**Signup / profile (member JWT)**

```
bff-auth-complete → missing_data includes pdpa shell
Member submits profile
  → bff_save_user_profile
       → channel_* on user_accounts
       → user_consent_ledger append per consent item
       → user_communication_preferences upsert per topic
```

**Admin config**

```
bff_admin_get_consent_config('list')
  → edit → bff_admin_upsert_consent_config
  → trg_cache_inv_* → fn_trigger_invalidate_user_profile_cache
```

**Current consent for a version**

```
Latest user_consent_ledger row for (user_id, consent_version_id) by created_at DESC
```

**Template bucketing (form builder)** — Privacy policy versions map to `notices` when notice interaction; terms + marketing map to `consents` with `requires_action` true; edit mode prefills `accepted` from latest ledger per version.

### Triggers

| Trigger | Table | Role |
| --- | --- | --- |
| `trg_cache_inv_consent_versions` | `consent_versions` | Profile/consent cache invalidation |
| `trg_cache_inv_communication_topics` | `communication_topics` | Same |
| `update_comm_prefs_updated_at` | `user_communication_preferences` | Maintains `updated_at` on change |

### External services

None dedicated — consent is Postgres BFFs only. Notification sending honors channel/topic flags in **Notification_Service.md**.

### Known gaps

- `api_get_consent_documents_cached` not listed in `REGISTRY_SUPABASE.md` (registry lag).
- Admin `audit` mode for `bff_admin_get_consent_config` has no loyalty-admin page.
- `rejected` ledger enum exists; member save path primarily writes `accepted` / `withdrawn` — confirm product use of `rejected` for optional declines if reporting depends on it.

## Related

- **Signup_Login.md** — `next_step`, `missing_data`, PDPA step in profile template; hub does not mint consent ledger itself.
- **Forms.md** — `bff_save_user_profile` owns profile + PDPA persistence.
- **Translation_System.md** — Consent version field translations.
- **Notification_Service.md** — Channel × topic gating for outbound messages.
- **Display_Settings.md** — Shopify chrome `privacy_consent_type` (storefront document link).
