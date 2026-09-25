# Earn Channel Effective View Restructure — Implemented

## Status

Implemented on 2026-06-16.

Durable documentation now lives in `requirements/Earn_Channel.md` and `requirements/Earn_Channel_Canonical.md`. The detailed planning draft was archived to `.cursor/plans/archive/earn-channel-effective-view-plan-20260616-implemented.md`.

## What Changed

- `earn_channel_registry` now stores stable `channel_code`, default method/config/copy, `availability_rule`, capabilities, `is_active`, and `updated_at`.
- `earn_channel` now has override metadata: `override_kind`, `source_type`, and `source_ref`.
- `fn_get_effective_earn_channels(p_merchant_id, p_language, p_include_admin_metadata)` computes channels from registry templates, source-system availability, merchant overrides, and legacy/custom rows.
- `bff_get_earn_channels` keeps the same member-app response shape but reads from the effective resolver.
- `bff_admin_get_earn_channels` returns effective admin channels plus source/capability metadata while preserving `channels`, `registry`, and `options`.
- `bff_upsert_single_earn_channel` creates/updates override rows for computed defaults.
- `bff_upsert_earn_channel` no longer deletes system/registry-backed/dependency-linked rows by omission.
- `bff_delete_earn_channel` hides computed/system channels instead of deleting them.
- `shopify_seed_default_earn_channel` is now idempotent/no-new-row for computed Shopify defaults; existing Shopify rows are preserved.
- Cache invalidation now listens to registry, feature config, merchant plan/referral changes, credentials, workflow tables, missions, check-ins, and forms.
- Default computed channel copy now uses static member UI translations on `ui_translations.page_key = 'ways_to_earn'`; override/custom rows continue to use object translations on `translations.entity_type = 'earn_channel'`.

## Verification

- Registry check: 15 templates, no missing `channel_code`, no missing `default_method_type`, 1 Shopify template.
- Resolver check: sample Shopify merchants return physical Shopify overrides where present, computed Shopify where no row is needed, and plan/config/campaign-derived defaults.
- Shopify seed check: calling `shopify_seed_default_earn_channel` did not create extra display rows.
- Translation check: 180 global default rows seeded, 45 each for `en`, `th`, `ja`, and `zh`, with no duplicate default key/language pairs.
- Registry regenerated: `requirements/REGISTRY_SUPABASE.md` now lists the new helpers/functions/triggers.

## Remaining Product Follow-Ups

- Confirm whether plan-enabled defaults should appear immediately for every existing merchant, or whether rollout should be gated for merchants with existing earn-channel configurations.
- Decide whether message-only lifecycle automations should ever create `info_card` earn channels. Current implementation requires an earning action node.
- Decide whether `product_code_scan` needs a first-class method distinct from `qr_scan`.
