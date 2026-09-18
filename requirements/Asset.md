# Asset

Member asset registry: tier-scoped limits and typed fields per asset category. First shipped skin is FuturePark **Exclusive Parking** (vehicles). Admin lists, Front Line per-member management, and member self-service share the same quota and validation rules.

Owner surfaces: loyalty-admin, loyalty-user (member app), Front Line

## Concept

**Asset type** — Merchant catalog entry (e.g. vehicles / `CAR`); drives labels and which tier configs apply.

**Tier config** — Per tier + type: max assets per member, dynamic field schema (`field_schema`), optional VIP tag metadata for a second quota section.

**Asset instance** — A member-owned row with custom fields, `active` / `inactive` status, and soft delete.

**Quota section** — General (default tier config) plus optional VIP section when the member carries the VIP tag; each section has its own X/Y limit (X = non-deleted instances in section; Y = `asset_limit_per_user` on that config).

**Sync flag** — Local `custom_crm_asset_sync` pending state; external CityPark HTTP sync is not wired in v1 (UI may still show verification copy).

Open API / warranty-style assets use overlapping `asset` rows but `api_*` validation and SKU columns — not Exclusive Parking BFFs.

## Rules

**Status**

| Value | Member-facing | Valid transitions |
| --- | --- | --- |
| `active` | Active / can use entrance QR | → `inactive` (toggle); soft-delete |
| `inactive` | Inactive | → `active` only if section active count would stay below Y; soft-delete |

**Quota**

- Add allowed only when active count in the target section is strictly below `asset_limit_per_user` (Y).
- Reactivate (`inactive` → `active`) blocked if it would exceed section quota.
- Edit custom fields allowed only while instance is `active`.
- Soft delete sets `deleted_at`; deleted rows do not count toward quota or plate uniqueness.
- Tier downgrade (via `apply_tier_change` → `apply_tier_change_core`) may FIFO-inactivate oldest **active** assets per type/section until within the **new** tier limits.

**CAR plates**

- Merchant-scoped uniqueness on normalized plate among non-deleted rows (BFF-enforced via `fn_asset_assert_plate_unique`; no DB unique index yet — historical duplicates block adding an index).

**Auth**

- Member BFFs resolve identity from JWT only (`fn_asset_resolve_auth_member`) — never trust client-supplied `user_id` / `merchant_id`.
- Admin / Front Line BFFs use `get_current_merchant_id()` and permission checks (`asset`, `frontline_asset_group`).

**VIP sections**

- VIP tier config is detected when `asset_tier_config.tags` is a JSON array containing an object with `name` ILIKE `VIP` (`fn_asset_config_is_vip`). General configs often store jsonb `null` for `tags` — not SQL NULL; bare `jsonb_array_elements` on jsonb null errors.

**Sync (v1)**

- Writes call `fn_asset_mark_sync_pending` → `custom_crm_asset_sync.is_sync = false`. Admin “Sync” sets `is_sync = true` locally only — no CityPark HTTP or scheduled job.

## Journeys

### Admin journey

| Knob | Effect |
| --- | --- |
| `asset_type` + `asset_tier_config` (DB-seeded today) | Per-tier limits, `field_schema`, VIP section eligibility |
| Vehicle lists | Search, filter, bulk local sync flag, CSV export of loaded rows |
| Permissions `asset.view` / `asset.edit` | Gates merchant-wide asset pages |
| Permission `frontline_asset_group` | Front Line Asset Group tab |

| Page | Owning repo | BFF / RPC |
| --- | --- | --- |
| Assets summary | loyalty-admin | `bff_admin_list_assets` |
| Vehicle lists | loyalty-admin | `bff_admin_list_assets`, `bff_admin_get_asset`, `bff_admin_sync_assets` |
| Front Line → Asset Group | loyalty-admin | `bff_admin_get_user_asset_groups`, `bff_admin_get_user_assets`, `bff_admin_upsert_user_asset`, `bff_admin_set_user_asset_status`, `bff_admin_delete_user_asset` |

1. **Assets summary** — Review fleet totals; open vehicle lists or jump to Front Line for a member.
2. **Vehicle lists** — Search/filter/paginate; open detail modal; run bulk **Sync** (local `is_sync` only); export CSV client-side from loaded rows.
3. **Front Line → Asset Group** — Landing shows one card per asset type with at least one active tier config (e.g. Exclusive Parking). Empty landing (“No asset groups…”) means no active type+config for the merchant — not a missing tab.
4. **Open group** — Sections + member vehicles driven by `field_schema`; labels “General Parking” / “VIP Parking” for CAR.
5. **Add / edit** — Modal with section key `general` \| `vip`; save via upsert BFF; add disabled when `can_add` false at limit; edit disabled when inactive.
6. **Toggle active/inactive** — Confirm; reactivate fails if section quota would be exceeded.
7. **Delete** — Soft-delete with confirm.

No admin UI yet to create asset types, edit `field_schema`, or tier limits — masters are DB-seeded.

### Member journey

| Page | Owning repo | BFF / RPC |
| --- | --- | --- |
| Exclusive Parking | loyalty-user | `bff_user_get_assets`, `bff_user_upsert_asset`, `bff_user_set_asset_status`, `bff_user_delete_asset`, `bff_user_get_parking_entrance_qr` |

Do **not** use legacy `bff_get_user_assets` — SKU/warranty catalog shape, not parking vehicles.

1. Load Exclusive Parking — sections, X/Y counters, vehicles, `field_schema`, `has_vip` for `CAR` (default type code).
2. Add vehicle — pick section; fill required fields; blocked at quota (`can_add` false).
3. Edit vehicle — only while active; duplicate plate surfaces BFF error.
4. Toggle inactive / reactivate — reactivate blocked at quota.
5. Delete — soft-delete.
6. **Entrance QR** — Requires active owned vehicle; 10-minute TTL; each refresh issues new token (`rotated: true`). Countdown at zero → call QR BFF again. Errors: `ASSET_REQUIRED` (no id), `ASSET_INACTIVE`.

Member get response omits durable `quota_notice` after downtier FIFO until a signal exists.

## System

Registry: `REGISTRY_SUPABASE.md` § Asset.

### Data model

| Table | Role |
| --- | --- |
| `asset_type` | Merchant catalog: `type_code`, `type_name`, `description` |
| `asset_tier_config` | Per `tier_id` + type: `asset_limit_per_user`, `field_schema` (jsonb array), `tags` (jsonb), `is_active`, `sort`, `name` |
| `asset` | Instance: `user_id`, `status`, `custom_fields`, `asset_tier_config_id`, `deleted_at`; plus Open API / legacy columns (`sku_*`, `external_id`, `asset_code`, …) unused by parking CRUD |
| `custom_crm_asset_sync` | One row per asset: `is_sync`, timestamps |
| `asset_field_definition` | Coarse field-key registry for Open API `validate_asset_custom_fields` — not Front Line form source of truth |
| `asset_relation` | Asset-to-asset links (Open API / warranty); not Front Line parking |

**Parking-relevant `asset` columns:** `status` (`active` / `inactive` in BFF payloads), `custom_fields` (slug → value), `asset_tier_config_id` (section at write time), `deleted_at` (soft-delete).

**FuturePark CAR `field_schema` slugs (seeded):**

| Slug | UI label | Type |
| --- | --- | --- |
| `car_plate` | License plate | STRING (unique) |
| `car_plate_province` | Province | SELECT_STRING |
| `brand` | Car brand | SELECT_STRING |
| `car_model` | Model | STRING |
| `car_color` | Color | STRING |

Plate normalize: trim, collapse whitespace, lower (`fn_asset_normalize_plate`).

### Functions

**Helpers**

| Function | Role |
| --- | --- |
| `fn_asset_normalize_plate` | Normalize plate text |
| `fn_asset_config_is_vip` | VIP config detector (array-safe) |
| `fn_asset_user_has_vip` | Member has `tag_master.tag_name = 'VIP'` |
| `fn_asset_assert_plate_unique` | Merchant + normalized plate among non-deleted |
| `fn_asset_resolve_sections` | General (+ VIP if eligible) section jsonb for UI |
| `fn_asset_resolve_auth_member` | Member JWT → `{ok, user_id, merchant_id}` (`user_accounts.id` or `auth_user_id`) |
| `fn_asset_mark_sync_pending` | Set / upsert sync row with `is_sync = false` |
| `fn_asset_enforce_quota_after_tier_change` | FIFO `inactive` on downtier |
| `validate_asset_custom_fields` | Open API field validation |

**Admin / Front Line BFFs** — `fn_response_*` envelopes; merchant from `get_current_merchant_id()`.

| Function | Role |
| --- | --- |
| `bff_admin_get_user_asset_groups` | Front Line landing cards |
| `bff_admin_get_user_assets` | Sections, limits, assets, `field_schema` |
| `bff_admin_upsert_user_asset` | Create/update (`p_section_key`, optional `p_asset_id`) |
| `bff_admin_set_user_asset_status` | Toggle active/inactive |
| `bff_admin_delete_user_asset` | Soft-delete |
| `bff_admin_list_assets` | Merchant list + stats |
| `bff_admin_get_asset` | Detail modal |
| `bff_admin_sync_assets` | Local stub: `is_sync = true` |

**Member BFFs** — auth via `fn_asset_resolve_auth_member()`; own assets only.

| Function | Role |
| --- | --- |
| `bff_user_get_assets` | Sections, counters, assets, `field_schema`, `has_vip` |
| `bff_user_upsert_asset` | Create/update; returns `{ asset }` |
| `bff_user_set_asset_status` | `active` / `inactive` |
| `bff_user_delete_asset` | Soft-delete |
| `bff_user_get_parking_entrance_qr` | Entrance QR payload + 10-minute TTL |

**Open API (other surface):** `api_create_or_update_asset`, `api_get_asset`, `api_update_asset`, `api_find_asset` — warranty/SKU flows; not `bff_user_*`.

**Display names (CAR):** group “Exclusive Parking”; sections “General Parking” / “VIP Parking”.

### Flows

**Upsert (admin, Front Line, member)**

1. Resolve merchant and permissions (admin) or member id (JWT).
2. Resolve asset type by `type_code`; sections via `fn_asset_resolve_sections`.
3. Target section by `p_section_key` (`general` \| `vip`); on create enforce quota.
4. Validate required fields from section `field_schema`; normalize + assert plate unique for CAR.
5. Insert or update `asset` (`status` default `active` on create; update only when active); set `asset_tier_config_id`.
6. `fn_asset_mark_sync_pending`.

**Downtier quota**

On `apply_tier_change_core` after downgrade / manual / assign_entry paths, `fn_asset_enforce_quota_after_tier_change`: for each type/section under new tier limits, set oldest active assets to `inactive` until `active_count ≤ Y`.

**Parking entrance QR**

- Requires `p_asset_id` of active, non-deleted, caller-owned vehicle.
- `ttl_seconds = 600`; `expires_at = now() + 10 minutes`; new `nonce` each call.
- Payload (until CityPark validates): `CRM-PARKING-V1.<base64(utf8 json)>` with claims `v`, `kind=parking_entrance`, `merchant_id`, `user_id`, `asset_id`, `plate`, `province`, `exp`, `nonce`.

### External services

- **CityPark** — Not integrated in v1 (no HTTP sync, no gate validation of QR payload).

### Known gaps

| Gap | Notes |
| --- | --- |
| Admin masters UI | No UI for `asset_type`, `field_schema`, tier limits, VIP tags |
| Real sync | No CityPark HTTP; no 02:00 cron; admin Sync is local flag only |
| `quota_notice` | Member get omits post-downtier notice until durable signal exists |
| DB unique on plate | Blocked until historical duplicate plates cleaned |
| Thai admin copy | Some Front Line / member keys may lack `ui_translation_admin` rows |
| Open API vs parking | Same `asset` table; different entrypoints and validation |

**Error / support matrix**

| Symptom | Typical cause |
| --- | --- |
| Front Line “No asset groups configured…” | No active `asset_type` + `asset_tier_config` for merchant |
| `cannot extract elements from a scalar` | VIP detection on non-array `tags` (fixed in `fn_asset_config_is_vip`) |
| Add disabled | `can_add` false when count ≥ limit |
| Edit disabled | Asset inactive |
| Reactivate fails | Would exceed section active quota |
| Duplicate plate | `fn_asset_assert_plate_unique` / BFF error |

## Related

- **Tier.md** — `apply_tier_change` / core hook to `fn_asset_enforce_quota_after_tier_change`.
- **Open_API.md** — `api-assets` warranty/SKU; `asset_field_definition`.
- **Stored_Value_Card.md** / FuturePark rewards — Parking privilege redemption, not asset CRUD.
- **FuturePark.md** — Merchant context for Exclusive Parking skin.
