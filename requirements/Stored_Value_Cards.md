# Stored Value Cards

Physical or imported prepaid card inventory (card number + balance per row) distinct from internal store-credit ticket wallets.

Owner surfaces: none shipped in loyalty-admin / loyalty-user (RPC-only demo path)

## Concept

**Stored value cards (shelved — demo-built, not launched)** — When launched, merchants would define card types (face value, expiry rules, sales window), import or assign numbered cards to members, and let members view balances and spend through the loyalty wallet stack. Postgres tables and assign/import RPCs exist; there is no GA admin catalog, member “My Cards” UI, or expiry cron. Portfolio: [Shelved_Demo_Features.md](./Shelved_Demo_Features.md).

**Card type** — Merchant template: value, expiry mode (TTL months or fixed date), optional price and active window.

**Card instance** — One numbered row with `current_balance`, status, optional security code; linked to a user when assigned.

**Not the same as** internal store credit — see [Store_Credit.md](./Store_Credit.md) (ticket wallet top-up/spend).

## Rules

- Assignment and import mutate `cards` through registry RPCs (`assign_card_*`, `import_cards`, `import_cards_bulk`) — verify permissions and merchant scope in live `prosrc` before demo use.
- Expiry processing relies on `expire_cards()` — **no Render/cron registration** today (same pattern as package entitlement expiry).
- Card types respect `window_start` / `window_end` and `is_active` on the type row; instance `status` governs spend eligibility (detail in archived draft — do not treat as GA until product signs journey).

## Journeys

### Admin journey

| Knob | Effect |
| --- | --- |
| Card type | Value, expiry mode, sales window |
| Import batch | Bulk load pre-generated numbers |
| Manual assign | Link card to member with or without security code |

No shipped admin pages — demo operators use RPC/SQL or future tooling. Archived UX draft: [archive/feature-docs-draft/stored-value-cards.md](./archive/feature-docs-draft/stored-value-cards.md).

### Member journey

1. _Not built_ — planned: list cards via `get_user_cards`, spend through wallet/chargepoint integration.
2. Until launch, members do not see SVC in loyalty-user (wallet tabs cover packages/benefits/rewards only).

## System

### Data model

| Table | Role |
| --- | --- |
| `card_types` | Catalog: name, `card_value`, expiry mode, windows, `is_active` |
| `cards` | Instances: `card_number`, balances, `status`, import metadata, optional `security_code` |

Verified live via Supabase MCP (`information_schema`).

### Functions

| Function | Role |
| --- | --- |
| `assign_card_automatic` | Program-driven assign to user |
| `assign_card_manual_with_code` / `assign_card_manual_without_code` | Staff/demo assign paths |
| `import_cards` / `import_cards_bulk` | Batch load for a `card_type_id` |
| `get_user_cards` | Member list (no FE consumer shipped) |
| `expire_cards` | Batch expiry job — **not scheduled** |
| `calculate_card_expiry` | Expiry helper for type rules |

Grep `card` in [REGISTRY_SUPABASE.md](./REGISTRY_SUPABASE.md) for full list.

### Known gaps (launch checklist)

| Area | Gap |
| --- | --- |
| Product | Canonical member + admin journeys unsigned — expand from archive draft only after PM approval |
| Admin UI | Card type editor, import wizard, assignment console |
| Member UI | “My Cards” in loyalty-user |
| Ops | Schedule `expire_cards` |
| Commerce | Spend/redemption integration with ticket chokepoint or orders |
| Plan | Platform entitlements and permissions catalog |

## Related

- **[Shelved_Demo_Features.md](./Shelved_Demo_Features.md)** — Launch status index.
- **[Store_Credit.md](./Store_Credit.md)** — Internal credit wallet (explicitly excludes SVC in v1).
- **[Currency.md](./Currency.md)** — Wallet ledger patterns when spend is wired.
- **Archive draft** — [archive/feature-docs-draft/stored-value-cards.md](./archive/feature-docs-draft/stored-value-cards.md) (non-canonical until merged).
