# Widget Settings — Front-End Spec

Concise reference for consuming `api_get_widget_settings_cached`. Covers the response envelope, every field, valid values, and how the FE should use each one.

## Endpoint

`POST /rest/v1/rpc/api_get_widget_settings_cached`

Body:

```json
{ "p_widget_type": "shopify", "p_merchant_code": "<merchant_code>" }
```

- Public / anon-callable.
- Server caches the response for 5 minutes per merchant + widget type.
- Always merges the saved config on top of the template defaults — every documented field is guaranteed to be present in `config`.

## Response envelope

Success:

```json
{
  "ok": true,
  "widget_type": "shopify",
  "schema_version": "1.0.0",
  "config":   { /* widget theming — see below */ },
  "resolved": { /* merchant-level display values — see below */ }
}
```

Error (note: simpler than the admin BFF envelope):

```json
{ "ok": false, "error": "merchant not found" }
```

| `error` value | Meaning | FE action |
|---|---|---|
| `merchant_code and widget_type required` | One of the two args was empty. | Fix the call. |
| `merchant not found` | `p_merchant_code` does not match any merchant. | Permanent — show fallback, don't retry. |
| `unknown widget_type` | No template exists for that `widget_type`. | Permanent — show fallback, don't retry. |

Rule: render only when `ok === true`. Otherwise show fallback UI.

## Top-level fields

| Field | Type | Use |
|---|---|---|
| `ok` | bool | Gate rendering. |
| `widget_type` | string | Echo of input, e.g. `shopify`. Branch widget-specific code on this. |
| `schema_version` | string (semver) | Currently `1.0.0`. If it changes, re-check this spec before rendering. |
| `config` | object | Per-merchant theming for the widget shell. Always fully populated. |
| `resolved` | object | Merchant-wide display values (brand color + points unit and symbol). Source of truth for points UI. |

## `config` — widget theming

### `config.theme`

| Field | Values | Use |
|---|---|---|
| `theme.mode` | `light` \| `dark` | Top-level color scheme for widget surfaces. |

### `config.header.background`

| Field | Values | Use |
|---|---|---|
| `background.type` | `solid` \| `gradient` \| `image` | Picks which sub-block below to render. Ignore the others. |
| `background.solid.color` | `#RRGGBB` (6-digit hex) | Background color when `type=solid`. |
| `background.gradient.from` | `#RRGGBB` | Gradient start color when `type=gradient`. |
| `background.gradient.to` | `#RRGGBB` | Gradient end color. |
| `background.gradient.angle` | number (degrees, e.g. `135`) | CSS `linear-gradient` angle. |
| `background.image.items` | array, 1–10 items when `type=image` | Carousel slides. Each item: `{ id, url, alt, order, size_kb? }`. Sort by `order` ascending before rendering. |
| `background.image.carousel.autoplay` | bool | Auto-advance the carousel. |
| `background.image.carousel.transition` | `fade` \| `slide` | Slide animation style. |
| `background.image.carousel.interval_ms` | int, 1000–30000 | Time per slide. Default 4000. |

If `type=image` and `items` is empty (defensive), fall back to the gradient block.

### `config.header.brand_mark`

| Field | Values | Use |
|---|---|---|
| `brand_mark.type` | `none` \| `text` \| `image` | `none` = render nothing. |
| `brand_mark.text` | string, 1–40 chars (when `type=text`) | Wordmark text. |
| `brand_mark.image_url` | URL (when `type=image`) | Logo image src. |
| `brand_mark.position` | `left` \| `center` \| `right` | Horizontal alignment in the header. |

### `config.header.coins_layout`

| Value | Meaning |
|---|---|
| `default` | Coins shown in the standard slot inside the header. |
| `overlay` | Coins float over the header background. |
| `below` | Coins rendered as a band directly under the header. |

### `config._schema_version`

Mirrors the top-level `schema_version`. Prefer the top-level one; this is just a tag inside the stored JSON.

## `resolved` — merchant display

These come from `merchant_display_settings` and are shared across all widgets. Use them for points UI and brand color — do **not** read points/symbol from anywhere inside `config`. The deprecated `point` block inside `config` is rejected by the saver and will not appear here.

| Field | Type | Use |
|---|---|---|
| `primary_color` | `#RRGGBB` or null | Primary accent color (launcher, header default, links, icon tints, button fallback). Mirrors `brand_scheme.tokens.primary` (scheme v2.1; v2.0 rows used `tokens.brand` — read `primary ?? brand`). Fall back to a neutral if null. |
| `points.unit_label` | string, e.g. `"Points"`, `"Coins"` | Label shown next to a points amount. |
| `points.symbol_type` | `icon` \| `image` (may be null) | Picks which symbol field to render. |
| `points.symbol_icon` | string (icon name) | Render when `symbol_type=icon`. Treat unknown names as missing. |
| `points.symbol_image_url` | URL | Render when `symbol_type=image`. |

If both `symbol_icon` and `symbol_image_url` are empty, render the unit label alone.

## Rendering checklist

1. Call the RPC with `p_widget_type` and `p_merchant_code`. Bail out if `ok !== true`.
2. Render the header background by switching on `config.header.background.type`.
3. Render the brand mark only if `config.header.brand_mark.type !== 'none'`.
4. Place coins per `config.header.coins_layout`.
5. For any points display anywhere in the widget, use `resolved.points.*` and `resolved.primary_color` — never read points fields from `config`.
6. Include the merchant code in your client cache key. The server already caches for up to 5 minutes, so a hard refresh may show stale data for that long.
