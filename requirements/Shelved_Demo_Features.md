# Shelved & demo-built loyalty features

Launch-status index only — business rules and system detail stay in each canonical domain doc; do not duplicate them here.

Owner surfaces: loyalty-admin, loyalty-user, Open API (where noted per row)

## Portfolio

| Feature | Canonical doc | Status | What exists in code & DB (brief) | Not launched / launch gaps | Demo notes (merchants, flags) | Related domains |
| --- | --- | --- | --- | --- | --- | --- |
| **Package** | [Package.md](./Package.md) | shelved — demo-built, not launched | Tables `package_master` / `package_items` / `package_assignment`; entitlements on `reward_redemptions_ledger` (`source_type = package_assignment`, `qty` / `used_qty`); admin BFFs; `api_assign_package`, `api_use_entitlement`, `get_user_packages`, `select_elective_items`, `fn_expire_package_entitlements` (no cron) | GA plan/marketing; scheduled expiry; whole-assignment cancel; Open API gateway for entitlement use; POS/FE multi-use vs mark-used | **Admin:** `/package-builder` (Marketing sidebar). **Member:** Wallet → Packages (`get_user_packages`, elective pick). Menu-driven demos — not default Shopify merchant nav | [Reward.md](./Reward.md), [Persona_Entitlement.md](./Persona_Entitlement.md), [Open_API.md](./Open_API.md) |
| **Persona entitlements** | [Persona_Entitlement.md](./Persona_Entitlement.md) | shelved — demo-built, not launched | `persona_entitlement`; `user_benefit`; `fn_auto_assign_on_persona`; contract BFFs (`bff_upsert_contract_with_levels`, `bff_admin_get_contract_*`, benefit assign/cancel); `api_get_eligibility` | Persona-change trigger missing; no auto-revoke of package/reward grants; Contract Builder UI; idempotent auto-assign; direct-reward expiry edge in auto-assign | **Admin:** `/persona-entitlements-advanced` → empty “coming soon”. Demo: SQL/RPC seed + manual `fn_auto_assign_on_persona` after persona assign | [Tag_and_Persona.md](./Tag_and_Persona.md), [Package.md](./Package.md) |
| **Store credit (internal top-up)** | [Store_Credit.md](./Store_Credit.md) | partial — demo-built frontline; not GA | Bootstrap internal credit `ticket_type`; `store_credit_promo`; `bff_store_credit` (get/topup/spend/reverse/event order); `bff_store_credit_promo`; chokepoint earns/burns; spend code helper | Promo settings page; member self top-up; purchase on top-up; SVC integration; broad checkout spend; platform plan keys for GA | **Admin:** Front Line → Store Credit when `frontline_store_credit` permission granted. Promos on tab; upsert via BFF + `store_credit_promo` permission. Not Shopify external credit | [Currency.md](./Currency.md), [Purchase_Transaction.md](./Purchase_Transaction.md), [Stored_Value_Cards.md](./Stored_Value_Cards.md) |
| **Stored value cards (SVC)** | [Stored_Value_Cards.md](./Stored_Value_Cards.md) | shelved — demo-built, not launched | `card_types`, `cards`; `assign_card_*`, `import_cards*`, `get_user_cards`, `expire_cards` (no cron) | Admin card-type/import UI; member My Cards; scheduled `expire_cards`; spend path; signed-off product rules | RPC/SQL demo imports only. Distinct from internal store-credit wallet | [Currency.md](./Currency.md), [Store_Credit.md](./Store_Credit.md) |

Legacy combined spec (pointer only): [Package_Contract_Benefit.md](./Package_Contract_Benefit.md) → use [Package.md](./Package.md) + [Persona_Entitlement.md](./Persona_Entitlement.md).

## Status labels

| Label | Meaning |
| --- | --- |
| **shelved — demo-built, not launched** | End-to-end or backend-complete for demos; not sold or enabled as GA loyalty product. |
| **partial** | Some surfaces live for demo merchants (e.g. Front Line) while config, member UX, or rollout remain incomplete. |

## How to read

- **Detail** — Follow the canonical doc for Concept, Rules, Journeys, and System (including `### Known gaps`).
- **Catalog evidence** — Inline tags such as `(shelved — demo-built, not launched)` or `(partial)` in a domain **Concept** mean the capability is implemented for demo or selective merchants but is **not** general-availability product.
- **Live truth** — Grep [REGISTRY_SUPABASE.md](./REGISTRY_SUPABASE.md) / [REGISTRY_RENDER.md](./REGISTRY_RENDER.md) and Supabase MCP before changing launch claims; docs can lag code.
- **Do not treat shelf rows as roadmap commitments** — They document what was built and what still blocks GA.
- **Enrichment workflow** — When a shelved feature launches, remove or rewrite its shelf row, update Concept tag to `(live)` or delete tag, and fold launch checklist items out of `Known gaps` into shipped journeys.

## Verification snapshot (2026-09-17)

Objects confirmed present in project `wkevmsedchftztoolkmi` via Supabase MCP: tables `package_*`, `persona_entitlement`, `store_credit_promo`, `cards`, `card_types`; functions including `bff_admin_get_package_list`, `fn_auto_assign_on_persona`, `bff_store_credit`, `get_user_cards`, `select_elective_items`. No Render cron entries for `fn_expire_package_entitlements` or `expire_cards` (registry grep).

## Writer routing (grep hints)

| If the thread mentions… | Open first |
| --- | --- |
| package builder, elective picks, multi-use coupon | [Package.md](./Package.md) — then registry `package_`, `fn_create_package_entitlements` |
| contract level, persona auto-grant, standing benefit | [Persona_Entitlement.md](./Persona_Entitlement.md) — then `persona_entitlement`, `fn_auto_assign_on_persona` |
| frontline top-up, SC- spend code, store_credit_promo | [Store_Credit.md](./Store_Credit.md) — then `bff_store_credit`, Front Line docs in loyalty-admin |
| gift card import, card_number, prepaid card type | [Stored_Value_Cards.md](./Stored_Value_Cards.md) — then `card_types`, `import_cards` |

## Related

- [Platform_Plan_Feature_Registry.md](./Platform_Plan_Feature_Registry.md) — Plan gating for shipped surfaces (these four are largely outside default entitlements).
- [domains/_index.md](./domains/_index.md) — Keyword routing to canonical docs.
- [Open_API.md](./Open_API.md) — Package assign vs entitlement-use gateway gap.
