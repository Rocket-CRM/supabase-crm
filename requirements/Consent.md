# Consent

Merchant-configurable legal documents (privacy, terms, marketing), communication channel toggles, and topic opt-ins — with an append-only consent ledger for PDPA audit.

Owner surfaces: loyalty-admin (Consent settings), loyalty-user (signup/profile PDPA step, Consent Management drawer), Shopify storefront (read-only consent documents via merchant code + display chrome)

## Concept

Consent is the last step of Join: before signup completes, the member reviews the brand's legal documents and states how, and about what, the brand may contact them. It exists so brands stay compliant with PDPA/GDPR-style rules, and what the member records here is what later gates marketing sends. It has three groups — **documents**, **communication channels**, **communication topics** — shown together on one screen.

**Consent document** — Legal text the brand writes (title, preview, full content, display order), tagged with a **type**: privacy policy, terms of service, or marketing data use. The type is a label; it does not change signup behaviour. The brand may keep any number of documents over time, but only **one version per type is live** at once.

**Interaction type** — What actually enforces behaviour, set per document: **notice** (shown with a pre-ticked, locked checkbox; nothing recorded), **required** (member must tick to submit; declining means not joining), **optional** (tick or not; either way the decision is recorded). Typical setup: privacy policy as notice, terms as required, marketing as optional.

**Consent version** — Documents change with law, company policy, or regulator guidance. The brand deactivates the old version and adds a new one; old versions are kept because decisions point to them. Existing members never re-signup: at next sign-in, an unaccepted **required** version is shown before home, like a banking app's updated-terms prompt.

**Consent ledger** — Append-only record of each member's decision per version (accepted, withdrawn, rejected). The latest row is the member's current stance.

**Communication channel** — Email, SMS, LINE, push: the paths the member allows the brand to use. Fixed list; the merchant configures nothing here.

**Communication topic** — Optional merchant-defined subject (e.g. per sub-brand, promotions, newsletter) with a name and description. No logic beyond recording each member's opt-in so audiences can be filtered (send brand-B content only to members who opted into brand B). Most merchants don't need topics; with none active, the section is hidden.

**Consent step and Consent Management** — The consent step sits inside the signup/profile form and is saved with it; members change their choices later in Profile → Consent Management.

## Rules

- **One active version per consent type per merchant** — Activating a second version of the same type without deactivating the first fails (partial unique index on active rows).
- **Unique version codes** — `(merchant_id, version_code)` must be unique.
- **Interaction type, not consent type, drives the signup/profile form** — `consent_type` only labels the document there.
- **`interaction_type = notice`** — Rendered with a pre-ticked, disabled checkbox; `requires_action` false; no ledger write on save.
- **`interaction_type = required`** — Checkbox required; member UI blocks submit until accepted; ledger records `accepted` or `withdrawn` on save.
- **`interaction_type = optional`** — Checkbox optional; ledger still records accept/withdraw when the member submits.
- **Ledger actions** — Enum: `accepted`, `withdrawn`, `rejected`. Append-only; status = latest row for `(user_id, consent_version_id)`.
- **New version re-prompt** — Decisions are per version, so a new version starts unaccepted for every member. At sign-in the auth hub returns `complete_profile_existing` with only the unaccepted **required** versions; the member can't reach home until they accept. New **optional** versions (e.g. marketing) are not re-prompted — members count as not accepted until they opt in via Consent Management.
- **Topics section** — Omitted from the member form when the merchant has no active topics.
- **Preview** — Template returns the stored preview, else the first 150 characters of content.
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
| Document type | Label only on signup (privacy / terms / marketing); one live version per type |
| Interaction type | Notice (locked tick, not recorded) / required (blocks submit) / optional (recorded either way) |
| Version code | Unique per merchant; identifies which text a member accepted |
| Title, preview, content | Title and content shown on the consent step; see Known gaps for preview |
| Active / replace | Which version is live per type; activating a new version prompts to deactivate the old; a new required version re-prompts existing members at next sign-in |
| Display order | Order of documents on the consent step |
| Communication topic (name, description) | Adds an opt-in option; description is not shown to members |
| Topic active | Inactive topics disappear; no active topics hides the section |

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

1. **Consent step** (last section of signup, after custom fields) — one accordion list: each document with its title and a two-line teaser (expand for full text); notices pre-ticked and locked; required/optional documents with a tick box; **Communication channels** (Email, SMS, LINE, Push) and, if any are active, **Communication topics** as multi-option blocks; an **Accept all** tick at the bottom.
2. Submit blocked if any **required** consent in the form is unchecked; error copy lists missing titles. After an admin publishes a new required version, a returning member sees this step with only that document at sign-in.
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

**Template bucketing** — Signup/profile template (`bff_get_user_profile_template`): item type and mandatory flag derive from `interaction_type`. Consent Management (`bff_get_consent_form_template`): privacy policy → `notices`, terms + marketing → `consents` with `requires_action` true. Both prefill `accepted` from the latest ledger row per version.

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
- **Consent Management buckets by type, not interaction type** — `bff_get_consent_form_template` treats every privacy policy as a notice and every terms/marketing version as a tick box (using the legacy `is_mandatory` column), so a document can behave differently there than on signup (which uses `interaction_type`).
- **Stored preview unused by loyalty-user** — The collapsed teaser is derived from full content; the admin preview field has no visible effect today.
- **Channels are not tied to auth methods** — All four channels always show, even when the merchant signs members up with LINE only.

## Related

- **Signup_Login.md** — `next_step`, `missing_data`, PDPA step in profile template; hub does not mint consent ledger itself.
- **Forms.md** — `bff_save_user_profile` owns profile + PDPA persistence.
- **Translation_System.md** — Consent version field translations.
- **Notification_Service.md** — Channel × topic gating for outbound messages.
- **Display_Settings.md** — Shopify chrome `privacy_consent_type` (storefront document link).
