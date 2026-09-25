# Points → Discount Burn Rate — Frontend Brief

**Audience:** Admin / member / POS frontend.  
**Scope:** Backend contract and semantics only. Screen layout, copy, and config UX are owned by the FE project.

---

## Before vs after

| | Before | After |
|---|---|---|
| Where the rate lives | Only on each tier (`tier_master.burn_rate`) | **Merchant default** on `merchant_master.default_burn_rate`, optional **tier override** on `tier_master.burn_rate` |
| Same rate for all tiers | Copy the same value onto every tier | Set merchant default once; leave tier overrides empty |
| New tier with no burn field | Point discount **off** for members on that tier | Inherits merchant default (if set) |
| Member with no tier | Discount off | Uses merchant default (if set) |

Unit is unchanged: **baht (THB) per 1 point**. Example: `0.01` ⇒ 100 points = 1 THB.

---

## Resolution (backend)

All runtime paths call `fn_resolve_burn_rate(merchant_id, tier_id)`:

1. If the member has a tier and `tier_master.burn_rate IS NOT NULL` → use that value (`source = tier_override`). **`0` force-disables** discount for that tier even if a merchant default exists.
2. Else → use `merchant_master.default_burn_rate` (`source = merchant_default`).
3. Else → disabled (`source = none`, `is_enabled = false`).

```
effective = tier override if set, else merchant default
is_enabled = effective > 0
```

---

## Functions FE should know

### Admin — merchant default (currency settings)

| RPC | Role |
|---|---|
| `bff_get_currency_config()` | Returns existing expiry/timing fields **plus** `default_burn_rate` |
| `bff_upsert_currency_config(p_data)` | Write `default_burn_rate` when the key is present; `null` / `""` clears it. Requires `currency` / `update` |

Do **not** confuse with Basic Currency Config earn rates (`bff_get_basic_currency_config` / “different rate per tier”) — that is **earn** (THB → points), not burn (points → discount).

### Admin — tier override (tier form)

| RPC | Role |
|---|---|
| `bff_upsert_tier_with_conditions(tier_data)` | Optional `burn_rate`: omit/null = inherit; `0` = force off; `>0` = override. Omitting the key on update leaves the stored override unchanged |
| `get_merchant_tiers(p_merchant_id)` | Returns raw `burn_rate` = **override only** (`NULL` means inherit, not “disabled”) |

Plan flag `tier/per_tier_burn_rate` can gate whether the override control is shown; the merchant default remains on currency settings.

### Member checkout

| RPC | Role |
|---|---|
| `get_user_burn_rate()` | JWT merchant + `auth.uid()`. Use `effective_rate`, `is_enabled`, `max_discount`. New fields: `source`, `merchant_default_rate`, `tier_override_rate` |

### Frontline / POS burn

| RPC | Role |
|---|---|
| `bff_preview_point_discount_burn(p_user_id, p_points_amount)` | Preview; uses resolver. Error `BURN_RATE_DISABLED` when nothing enables burn |
| `bff_create_point_discount_burn(...)` | Same resolution; burns points and returns wallet code |

### Integrations

| RPC | Role |
|---|---|
| `api_bigcommerce_get_user_profile()` | `burnRate` / `burnRateEnabled` / `discountInBaht` / `maxDiscountInBaht` are **resolved** effective values (not raw override-only) |

---

## Suggested mental model for FE (not a mandated journey)

- **Currency settings:** “Default points → baht rate for this merchant.”
- **Tier form:** “Optional better/worse/off rate for this tier only.”
- **Checkout / POS:** Always trust `effective_rate` / `is_enabled` from the RPCs above; do not re-implement inheritance in the client.

Exact pages, toggles, and copy are for the FE project to decide.
