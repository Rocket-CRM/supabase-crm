# Resource Content Library — Builder & Management

## What This Is

A content management page where admins create, edit, and organize reusable sendable content. This content is used by CS agents (browse & send in chat), CS AI (proactive resource sending), and AMP workflows (automated messages).

Four content types: **Quick Replies** (canned text), **Media** (files, PDFs, videos), **Links** (external URLs), and **Rich Content** (structured visual blocks — cards, carousels, lists, banners, etc.).

The Rich Content builder is the most complex component — a block-based visual editor with live platform preview.

---

## FE Project Context

| Layer | Tech |
|---|---|
| Framework | Next.js 16 (App Router, React 19) |
| UI | Shopify Polaris v13 (the only component library) |
| Rich text | TipTap (for text block editing within rich content) |
| Backend | Complex operations via `supabase.rpc()`. Simple reads/writes via `supabase.from()`. |
| Auth | Supabase Auth, JWT carries merchant context |
| Forms | `react-hook-form` + `zod` |

### Routes

```
src/app/(admin)/content-library/                    → Resource list page
src/app/(admin)/content-library/[id]/               → Create/edit resource
src/app/(admin)/content-library/categories/          → Category management
```

---

## Backend Connection — Tables & RPCs

### Core Tables

**`resource_content`** — Every piece of sendable content

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `merchant_id` | uuid FK | |
| `resource_type` | text | `quick_reply`, `media`, `link`, `rich_content` |
| `resource_code` | text | Human-readable identifier (unique per merchant, optional) |
| `name` | text | Admin display name |
| `content` | text | Text body (primary for quick_reply, description for others) |
| `media_url` | text | Supabase Storage URL (media type) |
| `media_mime_type` | text | e.g. `application/pdf`, `video/mp4` |
| `link_url` | text | Default URL (link type) |
| `thumbnail_url` | text | Preview image |
| `file_size_bytes` | integer | Media type |
| `rich_content` | jsonb | Structured blocks (rich_content type) — see Block Types section |
| `category_id` | uuid FK | → resource_content_category |
| `language` | text | ISO language code |
| `search_tags` | text[] | Freeform tags for search/filter |
| `trigger_patterns` | text[] | Conversation patterns for auto-suggest |
| `allowed_channels` | text[] | Channel restrictions. NULL = all. |
| `is_active` | boolean | |
| `sort_order` | integer | |
| `metadata` | jsonb | Extensible |
| `created_by` | uuid | |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |

**`resource_content_category`** — Content organization

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `merchant_id` | uuid FK | |
| `category_name` | text | Display name |
| `parent_id` | uuid FK → self | One level nesting |
| `sort_order` | integer | |
| `is_active` | boolean | |

### RPCs

| RPC | Purpose | Params |
|---|---|---|
| `bff_list_resource_content` | List with filters + pagination | `p_resource_type`, `p_category_id`, `p_search`, `p_is_active`, `p_limit`, `p_offset` |
| `bff_get_resource_content_details` | Single resource (new/edit) | `p_resource_content_id` (NULL for new — returns defaults) |
| `bff_upsert_resource_content` | Create or update | All resource fields as params |
| `bff_delete_resource_content` | Soft delete | `p_resource_content_id` |
| `bff_upsert_resource_content_category` | Create/update category | Category fields |
| `bff_list_resource_content_categories` | Category tree | (none — returns merchant's categories as parent/child tree) |

### Supporting Queries

```typescript
// Get merchant's active platforms (for link map editor + platform preview)
const { data: credentials } = await supabase
  .from('merchant_credentials')
  .select('service_name, credential_name, is_active')
  .eq('is_active', true)
```

This determines which platform tabs to show in the link editor and platform preview.

---

## Page 1: Resource List

### Layout

Standard Polaris resource list page:
- Page header: "Content Library" with "Create resource" primary action
- Filter bar: resource type tabs (All | Quick Replies | Media | Links | Rich Content), category dropdown, search, active/inactive toggle
- Resource list table/cards showing: thumbnail, name, type badge, category, search tags, last updated, status toggle

### Behavior

- Click resource → navigate to edit page
- Bulk actions: activate/deactivate, change category, delete
- Empty state per type with helpful copy explaining what each type is for

---

## Page 2: Resource Create/Edit

### Layout

Two-column layout:
- **Left (wide):** Content editor — varies by resource type
- **Right (narrow):** Metadata sidebar — name, code, category, tags, trigger patterns, allowed channels, active toggle

### Common Fields (all types)

| Field | Component | Notes |
|---|---|---|
| Name | `TextField` | Required. Admin/agent display name |
| Resource Code | `TextField` | Optional. Auto-generated suggestion from name |
| Category | `Select` | From `bff_list_resource_content_categories` |
| Search Tags | Tag input (Polaris `Tag` + `TextField`) | Freeform tags |
| Trigger Patterns | Tag input | Conversation patterns for auto-suggest |
| Language | `Select` | ISO code dropdown |
| Allowed Channels | Multi-select checkboxes | From merchant's active `merchant_credentials`. NULL = all |
| Active | `Toggle` | |

### Type-Specific Editors

#### Quick Reply Editor
- Single `TextField` (multiline) or TipTap for formatted text
- Character count indicator
- Preview of how the text appears in chat

#### Media Editor
- Supabase Storage file uploader (drag-and-drop)
- Auto-detect MIME type, file size
- Thumbnail preview for images/PDFs
- Description text field

#### Link Editor
- Default URL field (`link_url`)
- **Platform URL overrides** — expandable section showing platform-specific URLs
- Uses the Platform Link Editor component (see below)
- Description text field, thumbnail URL

#### Rich Content Editor (see dedicated section below)

---

## Rich Content Block Editor — The Core Builder

This is the most important component. A visual block-based editor where admins compose structured content from generic blocks.

### Top-Level Tabs

The rich content editor has **two tabs** at the top:

```
[Custom Content]  [Platform Cards]
```

- **Custom Content** — Block editor for designing visual layouts (the core builder described below)
- **Platform Cards** — Browse marketplace catalogs and select products for native card delivery (see Platform Catalog Browser section)

Both tabs are optional. A resource can have just custom content, just platform cards, or both. When both exist, the system sends platform cards on marketplaces and custom content everywhere else.

### Custom Content Tab — Editor Layout

```
┌──────────────────────────────────────────────────────────┐
│  Block Canvas (left ~60%)        │  Preview Panel (~40%) │
│                                  │                       │
│  [+ Add Block]                   │  Platform tabs:       │
│                                  │  [Web] [LINE]         │
│  ┌─────────────────────────┐     │  [WhatsApp] [SMS]     │
│  │ 📦 card                 │←drag│                       │
│  │ Title: [Glow Serum    ] │     │  ┌─────────────────┐  │
│  │ Subtitle: [Brightening] │     │  │  Live preview    │  │
│  │ Fields: + Add field     │     │  │  of selected     │  │
│  │ Link: [Platform links]  │     │  │  platform        │  │
│  └─────────────────────────┘     │  │  rendering       │  │
│                                  │  └─────────────────┘  │
│  ┌─────────────────────────┐     │                       │
│  │ 🔘 buttons              │     │  Compatibility:       │
│  │ [Shop Now] [Learn More] │     │  Web      ✅          │
│  └─────────────────────────┘     │  LINE     ✅          │
│                                  │  WhatsApp ⚠️ degraded │
│  [+ Add Block ▼]                 │  SMS      ⚠️ text     │
│                                  │  Shopee   → Platform  │
│                                  │            Cards tab  │
└──────────────────────────────────────────────────────────┘
```

For marketplace platforms (Shopee/Lazada/TikTok), the preview panel shows: "Custom content degrades to text+image on this platform. Use the **Platform Cards** tab to send native product cards instead."

### Block Palette

"Add Block" button opens a dropdown/popover with available block types:

| Block | Icon | Description shown to admin |
|---|---|---|
| `card` | 🃏 | Content card — image, title, details, action button. Use for products, people, events, anything. |
| `carousel` | 🎠 | Horizontal scroll of multiple cards |
| `hero` | 🖼️ | Full-width banner image with text overlay |
| `buttons` | 🔘 | Action buttons — links to pages, products, forms |
| `text` | 📝 | Text block — heading, paragraph, or caption |
| `image` | 🏞️ | Standalone image with optional caption |
| `video` | 🎬 | Video with thumbnail |
| `list` | 📋 | Vertical list — key-value pairs, numbered steps, or bullet points |
| `callout` | 💡 | Highlighted box — info, warning, promo code, tip |
| `separator` | ➖ | Visual divider between sections |

### Block Editor Forms

Each block type has its own inline editor form. Blocks are draggable for reordering.

#### `card` Block Form

| Field | Component | Notes |
|---|---|---|
| Image | Image uploader (Supabase Storage) | Drag-drop or URL input |
| Title | `TextField` | Required |
| Subtitle | `TextField` | Optional |
| Description | `TextField` multiline | Optional |
| Badge | `TextField` | Optional (e.g., "Bestseller", "New", "Available") |
| Fields | Dynamic key-value list | + Add Field → label input + value input + optional style select |
| Link | **Platform Link Editor** | Per-platform URL map |

#### `carousel` Block Form
- Contains nested `card` blocks (reuses card form)
- + Add Card button
- Drag to reorder cards
- Show warning: "Carousel not supported on Shopee, Lazada, TikTok, WhatsApp — cards will be sent individually"

#### `hero` Block Form

| Field | Component |
|---|---|
| Image | Image uploader |
| Title | `TextField` |
| Subtitle | `TextField` |
| Description | `TextField` multiline |
| Background Color | Color picker |
| Text Color | Color picker |

#### `buttons` Block Form
- Dynamic list of buttons
- Each button: Label (`TextField`) + Style (primary/secondary `Select`) + Link (**Platform Link Editor**)
- Show warning if > 3 buttons: "WhatsApp supports max 3 buttons"

#### `text` Block Form

| Field | Component |
|---|---|
| Content | TipTap editor (basic formatting) |
| Style | `Select`: heading / normal / caption |

#### `image` Block Form

| Field | Component |
|---|---|
| Image | Image uploader |
| Alt Text | `TextField` |
| Caption | `TextField` |
| Link | **Platform Link Editor** (optional — makes image clickable) |

#### `video` Block Form

| Field | Component |
|---|---|
| Video URL | `TextField` (Supabase Storage URL or external) |
| Thumbnail | Image uploader |
| Caption | `TextField` |
| Duration | `TextField` (display only, e.g. "2:30") |

Show warning: "Video not supported on Shopee, Lazada, SMS — will send as link"

#### `list` Block Form

| Field | Component |
|---|---|
| Title | `TextField` (optional list header) |
| Style | `Select`: key_value / bullet / numbered |
| Items | Dynamic list — each item has: |
| → Title | `TextField` (for numbered/bullet) |
| → Label | `TextField` (for key_value) |
| → Value | `TextField` (for key_value) |
| → Description | `TextField` (optional) |
| → Image | Image uploader (optional) |
| → Link | **Platform Link Editor** (optional) |
| → Icon Color | Color picker (optional) |

#### `callout` Block Form

| Field | Component |
|---|---|
| Style | `Select`: info (blue) / warning (yellow) / success (green) / promo (orange) |
| Title | `TextField` |
| Content | `TextField` multiline |
| Promo Code | `TextField` (optional — shown with copy button in preview) |
| Valid Until | Date picker (optional) |
| Image | Image uploader (optional) |

#### `separator` Block Form
- Style: `Select` — line / space
- No other fields

---

## Reusable Sub-Components

### Platform Link Editor

Used by `card`, `buttons`, `image`, `list` items — anywhere a `link` field appears.

```
┌─────────────────────────────────────────────┐
│ Default URL *   [https://brand.com/product] │
│                                             │
│ ▸ Platform-specific URLs (3 configured)     │
│   ┌─────────────────────────────────────┐   │
│   │ Shopee    [https://shopee.co.th/..] │   │
│   │ Lazada    [https://lazada.co.th/..] │   │
│   │ LINE      [https://liff.line.me/..] │   │
│   │ + Add platform URL ▼                │   │
│   └─────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

- Default URL is always required
- "Platform-specific URLs" section is collapsed by default with count badge
- Only shows platforms the merchant has active credentials for (from `merchant_credentials`)
- "Add platform URL" dropdown lists remaining unconfigured platforms

### Platform Catalog Browser (Platform Cards Tab)

This is the second top-level tab in the rich content editor. It lets admins browse their connected marketplace catalogs and select products to send as **native platform cards**.

**Only shown when the merchant has active Shopee, Lazada, or TikTok credentials.**

```
┌─────────────────────────────────────────────────────────────┐
│  Platform Cards                                             │
│                                                             │
│  [Shopee]  [Lazada]  [TikTok]   ← tabs per connected mktpl │
│                                                             │
│  Search: [_______________] [🔍]                              │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  ☐ Glow Vitamin C Serum 15%          ฿890   In Stock │   │
│  │     [img]  SKU: RB-GLOW-001                          │   │
│  ├──────────────────────────────────────────────────────┤   │
│  │  ☐ Shield Daily Sunscreen SPF50+     ฿590   In Stock │   │
│  │     [img]  SKU: RB-SHIELD-001                        │   │
│  ├──────────────────────────────────────────────────────┤   │
│  │  ☐ Hydra Centella Cream              ฿690   In Stock │   │
│  │     [img]  SKU: RB-HYDRA-001                         │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                             │
│  Selected (3):                                              │
│  [Glow Serum ✕] [Shield Sunscreen ✕] [Hydra Cream ✕]       │
│                                                             │
│  ℹ️ Selected products will be sent as native [Shopee]       │
│     product cards when this resource is used in a           │
│     Shopee conversation.                                    │
└─────────────────────────────────────────────────────────────┘
```

**How it works:**

1. Admin clicks a platform tab (Shopee / Lazada / TikTok)
2. FE calls an edge function to browse the merchant's catalog on that platform:

```typescript
const response = await fetch(
  `${SUPABASE_URL}/functions/v1/browse-platform-catalog`,
  {
    method: 'POST',
    headers: { Authorization: `Bearer ${jwt}`, apikey: ANON_KEY },
    body: JSON.stringify({
      platform: 'shopee',        // or 'lazada' or 'tiktok'
      search: 'glow serum',      // optional search query
      page: 1,
      page_size: 20,
    }),
  }
)
// Returns: { items: [{ item_id, name, image_url, price, currency, url, status }], total }
```

3. Admin browses/searches, selects products (checkbox per item)
4. Selected items are stored in `resource_content.platform_content.{platform}.items`
5. Repeat per platform tab if merchant sells on multiple marketplaces

**Edge function `browse-platform-catalog`** (deployed):
- Reads `merchant_credentials` for the specified platform
- Calls platform API to list/search products (Shopee, Lazada, TikTok)
- Returns normalized product list: `{ items: [{item_id, name, image_url, price, currency, url, status}], total, platform }`

**Per-platform selected items view:**
Each platform tab shows which items are currently selected with:
- Product image thumbnail, name, price, stock status
- Remove button (✕) per item
- "Last synced: 2 hours ago" indicator + "Refresh" button to re-fetch latest data from platform
- Warning if item is out of stock or delisted on the platform

**What gets saved:**

```json
// resource_content.platform_content
{
  "shopee": {
    "items": [
      {
        "item_id": "890123456",
        "name": "Glow Vitamin C Serum 15%",
        "image_url": "https://cf.shopee.co.th/file/...",
        "price": 890,
        "currency": "THB",
        "url": "https://shopee.co.th/product/i.890123.456",
        "synced_at": "2026-04-07T10:00:00Z"
      }
    ]
  }
}
```

**Platform Cards tab is independent from Custom Content tab.** The admin can:
- Set up only custom content (no platform cards) → marketplaces get text+image fallback
- Set up only platform cards (no custom content) → LINE/web get no content (show warning)
- Set up both (recommended) → best experience on all platforms

### Platform Preview Panel

Side panel showing live preview of how content renders on each platform. Tabs for each platform the merchant has configured.

| Platform Tab | What to show |
|---|---|
| **Web** | Full HTML rendering of all blocks (the "ideal" view) |
| **LINE** | Mock LINE chat bubble showing approximate Flex Message layout |
| **Shopee** | Mock Shopee chat showing: native product card if `platform_content.shopee.items` present, otherwise text+image fallback |
| **Lazada** | Same pattern as Shopee |
| **TikTok** | Same pattern as Shopee |
| **WhatsApp** | Mock WhatsApp chat showing interactive buttons (if ≤3), text fallback otherwise |
| **SMS** | Plain text rendering |

Each platform tab also shows a **compatibility summary** for all blocks in the current resource:

```
Block compatibility:
  carousel (3 cards)   ✅ Native    → ⚠️ Cards sent individually
  buttons (2)          ✅ Native    → ❌ Text with URLs
```

The preview panel is the primary tool for admins to understand cross-platform behavior. It should update live as blocks are edited.

---

## Validation Rules

| Rule | When | Message |
|---|---|---|
| Name required | Save | "Resource name is required" |
| At least one content source | Save rich_content | "Add custom content blocks and/or select platform catalog items" |
| Default link required | Any link field with platform overrides | "Default URL is required as fallback" |
| Carousel max 12 | LINE platform | "LINE supports max 12 cards in a carousel" |
| Buttons max 3 | WhatsApp platform | "WhatsApp supports max 3 buttons — additional buttons will be sent as text links" |
| WhatsApp list max 10 | WhatsApp platform | "WhatsApp list messages support max 10 items" |
| File size limit | Media upload | Check Supabase Storage limits |
| No custom content + no platform cards | Save | Warning: "This resource has no content for non-marketplace channels (LINE, Web, WhatsApp)" |
| Platform item out of stock | Platform Cards tab, on sync | Warning: "This item may be unavailable on {platform}" (non-blocking) |

---

## What NOT to Build

- Platform-specific message rendering (that's the messaging service's job — backend)
- Resource usage analytics (future phase)
- Version history / undo (future phase)
- AI-generated content suggestions (future phase)
- Resource approval workflow (future phase)
- Translation management (use existing translation system)

## New Backend Dependencies

| Dependency | Type | Purpose |
|---|---|---|
| `browse-platform-catalog` | Edge function (deployed) | POST `{ platform, search, page, page_size }`. Calls Shopee/Lazada/TikTok APIs. Returns `{ items: [{item_id, name, image_url, price, currency, url, status}], total }` |
| `bff_list_resource_content` | RPC (deployed) | List with filters + pagination |
| `bff_get_resource_content_details` | RPC (deployed) | Single resource for edit page |
| `bff_upsert_resource_content` | RPC (deployed) | Create/update — accepts `p_platform_content` jsonb + `p_trigger_patterns` text[] |
| `bff_delete_resource_content` | RPC (deployed) | Delete resource |
| `bff_upsert_resource_content_category` | RPC (deployed) | Category management |
| `bff_list_resource_content_categories` | RPC (deployed) | Category tree |
| `merchant_credentials` table | Direct query | Get merchant's active platform connections |
