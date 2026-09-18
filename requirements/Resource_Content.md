# Resource Content

Merchant-owned library of reusable sendable content (canned text, files, links, and structured rich messages) for CS agents, CS AI, and AMP workflows.

Owner surfaces: loyalty-admin (Content Library, CS conversations, workflow message nodes), CS outbound messaging, AMP / Inngest

## Concept

The **content library** is the single place merchants define things they send repeatedly to customers. Each row is a **resource**: a typed payload plus optional organization, search hints, and marketplace catalog picks. Resources are **shared** across modules (not CS-only) — the same tables and delivery resolver power human agents, AI tools, and workflow message nodes.

**Category** — Optional folder label for admin browsing; at most one level of nesting (parent + children).

**Resource type** — One of four shapes: quick reply (text), media (stored file), link (external URL), or rich content (block-based layout).

**Quick reply** — Plain text body used as a canned agent/AI response.

**Media** — File in storage (PDF, image, video, etc.) with MIME type and optional description.

**Link** — External URL with optional description and thumbnail.

**Rich content** — Platform-agnostic **blocks** (cards, carousels, buttons, text, images, etc.) authored once; a renderer converts blocks to channel-native formats at send time.

**Platform content** — Separate from custom blocks: product (or catalog) items selected from connected marketplace shops (Shopee, Lazada, TikTok). On a marketplace conversation, native catalog cards are preferred when items exist.

**Trigger patterns** — Phrases on a resource used to suggest or auto-match content when an inbound customer message resembles the pattern (CS assist / AI).

**Delivery resolution** — At send time the system picks delivery mode (native catalog card vs rendered rich layout vs plain text/media/link), resolves per-channel URLs in blocks, and rewrites certain button actions (reward/survey picks) into member-app deep links before flex/HTML rendering.

**Consumers** — CS reply composer and AI `send_resource` tools; AMP workflow message nodes and AMP AI actions; optional references from knowledge articles. Sent messages record which resource id was used in message metadata.

## Rules

- Every resource belongs to exactly one merchant and has a **resource type**; fields required by type must be present on save (text for quick reply; `media_url` + MIME for media; `link_url` for link; `rich_content` JSON for rich content).
- **`resource_code`**, when set, is unique per merchant; omit for auto-only identity.
- **Categories**: `parent_id` may point to a root category only (one nesting level); inactive categories do not remove resources but affect admin tree display per list filters.
- **`allowed_channels`** is **deprecated**: channel is determined by the destination conversation’s credential, not the resource. Upsert accepts the parameter for FE compatibility but persists NULL; search/load paths do not filter on it. The column may be dropped after BFFs stop selecting it.
- **Active flag**: inactive resources are excluded from default agent/search listings (`is_active = true` default on list BFFs) but remain editable in admin.
- **Search**: `search_tags`, name, and list filters drive admin list and CS search; `trigger_patterns` drive `cs_fn_match_resource` suggestions against inbound message text.
- **Rich content blocks are structural, not semantic** — use generic `card` + `fields[]` for products, staff, events, etc.; no domain-specific block type names in storage.
- **URLs in blocks** use either a plain string (all channels) or a **link map** with required `default` and optional keys matching `merchant_credentials.service_name` (e.g. `shopee`, `lazada`, `line`, `tiktok`, `bigcommerce`, `shopify_app`). Renderer picks platform-specific URL from the conversation channel, else `default`.
- **Buttons** (in `buttons` blocks or up to two per card) support `action.type`: `uri`, `postback`, `reward`, `survey`. Legacy buttons with only `link` are treated as `uri`. Postback `data` ≤ 300 chars (LINE). Reward/survey actions are stored as authored; at delivery, `fn_resolve_rich_content_actions` rewrites them to member-app `uri` deep links; stored JSON is unchanged.
- **Postback data convention** (admin validates on save): `src=resource&resource_id=<uuid>&action=<keys>` where `action` / AMP `a=` is one or more keys `[a-zA-Z0-9._-]{1,64}`, comma-separated, max 5. AMP signs the list; Interaction Router `selection_mode` `single` continues on first key only, `multiple` fans out per key with suffixed `webhook_event_id`.
- **Marketplace send precedence** on Shopee/Lazada/TikTok conversations: if `platform_content.{platform}.items` is non-empty → send **native catalog cards**; else render `rich_content` with text+image (or weaker) fallbacks per block compatibility matrix.
- **Non-marketplace channels** (LINE, web chat, Messenger, WhatsApp, SMS): render `rich_content` natively where supported; degrade per matrix (e.g. carousel → separate messages on WhatsApp; buttons → numbered URLs on SMS).
- **LINE preview**: admin save path validates rich content for LINE constraints before persist where the editor enforces it.
- **Engagement**: `bff_get_resource_content_engagement` aggregates send/interaction stats for a resource in admin (date range optional).

Example (link map): a card CTA uses `{ "default": "https://brand.com/p", "shopee": "https://shopee.co.th/..." }` — a Shopee chat receives the Shopee URL; other channels receive `default`.

## Journeys

### Admin journey

| Page | Owning repo | BFF / RPC |
| --- | --- | --- |
| Content Library (list) | loyalty-admin | `bff_list_resource_content`, `bff_list_resource_content_categories` |
| Content Library (create/edit) | loyalty-admin | `bff_get_resource_content_details`, `bff_upsert_resource_content`, `bff_delete_resource_content` |
| Content Library — Categories | loyalty-admin | `bff_upsert_resource_content_category`, `bff_list_resource_content_categories` |
| CS conversation — resource search/send | loyalty-admin | `cs_bff_search_conversation_resources`, `cs_bff_send_resource` |
| Workflow / LINE message node — pick resource | loyalty-admin | `bff_list_resource_content`, `bff_get_resource_content_details` (picker); node stores `content_resource_id` |
| LINE flex preview (admin) | loyalty-admin | `bff_preview_resource_line_flex` |

| Setting | Effect on behaviour |
| --- | --- |
| Resource type | Which editor fields and delivery mode apply |
| Name / resource code | Admin display and optional stable code |
| Category | List filtering and organization |
| Language | Metadata for search/filter |
| Search tags | Admin and CS search |
| Trigger patterns | Inbound message pattern match / suggestions |
| Rich content blocks | Cross-channel layout; LINE validation on save |
| Platform content tab | Native marketplace cards when credentials exist |
| Active / sort order | Visibility in pickers and default lists |
| Button actions (reward/survey) | Resolved to member-app links at send time |

1. Open **Content Library**, filter by type/category/search, or open **Categories** to manage the tree (create/edit category, optional parent).
2. **Create** resource: choose type — quick reply, media (upload to storage), link, or rich content.
3. For **rich content**, use the block editor (Custom Content tab); optional **Platform Cards** tab when marketplace credentials exist — browse catalog via edge `browse-platform-catalog`, select items into `platform_content`.
4. Set metadata sidebar: category, tags, trigger patterns, active, sort; configure button actions and postback keys per validation rules.
5. Save — upsert persists `platform_content` and `trigger_patterns`; reward/survey picks reference live rewards/forms.
6. Optional: view **engagement** card on edit screen via `bff_get_resource_content_engagement`.
7. In **CS conversations**, search resources in the composer and send — BFF wraps backend send + outbound message insert.
8. In **Workflow List** / AMP message nodes, attach a resource by id (`content_resource_id` in node config).

### Member journey

| Surface | Owning repo | BFF / RPC |
| --- | --- | --- |
| Omnichannel chat (LINE, marketplaces, web, etc.) | CS messaging + channel adapters | `cs_fn_send_resource` → `fn_resolve_resource_for_delivery` → outbound deliver |
| Member app (reward/survey deep links from buttons) | loyalty-user | Opened via URLs from `fn_member_app_deep_link` after delivery resolution |

1. Customer receives a message on the active channel — plain text, file, link, rendered rich layout, or native marketplace product card depending on delivery resolution.
2. Taps a **URI button** or link → opens URL (platform-specific link map or resolved member-app page for reward/survey actions).
3. Taps a **postback button** → LINE posts back to `webhook-line`; AMP-signed postbacks route to AMP recorder; unsigned resource postbacks ingest as synthetic inbound text with postback metadata for agent/AI continuation.
4. If channel only supports degraded format (e.g. SMS), customer sees text + URLs instead of full carousel/button UI.

## System

### Data model

**`resource_content_category`** — Merchant-scoped category tree (one child level): `category_name`, `parent_id`, `sort_order`, `is_active`, timestamps. FK to `merchant_master`.

**`resource_content`** — Core sendable entity:

| Column | Role |
| --- | --- |
| `resource_type` | `quick_reply` \| `media` \| `link` \| `rich_content` |
| `resource_code`, `name` | Identity and display |
| `content` | Text body or description |
| `media_url`, `media_mime_type`, `file_size_bytes`, `thumbnail_url` | Media type |
| `link_url` | Link type |
| `rich_content` | jsonb `{ "blocks": [ ... ] }` |
| `platform_content` | jsonb per marketplace `{ shopee\|lazada\|tiktok: { items: [...] } }` with cached catalog fields + `synced_at` |
| `category_id` | Optional FK to category |
| `language`, `search_tags`, `trigger_patterns` | Discovery and auto-suggest |
| `allowed_channels` | Deprecated; always NULL on write |
| `is_active`, `sort_order`, `metadata`, `created_by` | Lifecycle and extension |
| `created_at`, `updated_at` | Audit; `set_updated_at` trigger |

Indexes (live): unique `(merchant_id, resource_code)` where code not null; `(merchant_id, resource_type, is_active)`; GIN on `search_tags`; `(merchant_id, category_id)` where category set.

### Functions

| Function | Role |
| --- | --- |
| `bff_upsert_resource_content_category` | Category CRUD |
| `bff_list_resource_content_categories` | Category tree for admin |
| `bff_upsert_resource_content` | Resource CRUD (overload with `p_platform_content`, `p_trigger_patterns`; ignores `p_allowed_channels`) |
| `bff_get_resource_content_details` | New/edit load |
| `bff_list_resource_content` | Filtered list (type, category, search, active, pagination) |
| `bff_delete_resource_content` | Delete resource |
| `bff_get_resource_content_engagement` | Engagement stats for admin card |
| `bff_preview_resource_line_flex` | LINE flex preview payload for admin |
| `fn_resolve_resource_for_delivery` | Universal resolver: delivery_mode, native items vs blocks, action resolution; no `CHANNEL_NOT_ALLOWED` |
| `fn_resolve_rich_content_actions` | Rewrites reward/survey button actions to `uri` deep links |
| `fn_member_app_deep_link` | Member-app URL shapes from `merchant_code` |
| `fn_render_blocks_as_text` | Plain-text fallback (SMS, marketplace degrade, previews) |
| `fn_render_blocks_as_line_flex` | LINE flex generation from blocks (post-resolution) |
| `cs_fn_search_resources` | Service-role search for AI/automation |
| `cs_fn_load_available_resources` | Load catalog for channel context |
| `cs_fn_match_resource` | `trigger_patterns` match on inbound text |
| `cs_fn_send_resource` | Resolve + insert `cs_messages` with delivery metadata |
| `cs_bff_search_conversation_resources` | JWT search in agent UI |
| `cs_bff_send_resource` | JWT send wrapper |
| `cs_trigger_deliver_outbound_message` | On `cs_messages` insert → messaging service with resource-aware payload |

### Flows

**Admin save** — loyalty-admin → `bff_upsert_resource_content` → row in `resource_content` (storage upload for media happens via admin/storage pattern before URL is saved).

**Agent/AI send** — Pick `resource_id` → `cs_fn_send_resource` (or AMP equivalent) → `fn_resolve_resource_for_delivery` (channel from conversation credential) → optional native marketplace API payload from `platform_content` → else render `rich_content` / text / media / link → `cs_messages` row with `content_resource_id` in metadata → `cs_trigger_deliver_outbound_message` → channel messaging service.

**Delivery decision (marketplace vs rich)** — Resolve `service_name` from conversation → if marketplace and `platform_content.{platform}.items` present → native catalog cards; else block renderer with per-platform link resolution and compatibility fallbacks (carousel split, buttons as URLs, video as link-only on weak channels).

**Button postback (LINE)** — `webhook-line` receives postback → AMP-signed `src=amp` via verify + `fn_amp_record_line_postback` (multi-key when configured); resource unsigned → `cs_api_receive_message` as text with postback metadata → Inngest `cs/message.received` includes `line_event_type: postback`.

**AMP workflow** — Message node `node_config.content_resource_id` references library row; send path uses same resolver as CS.

**Knowledge** — `cs_knowledge_articles.metadata` may reference attached resources; historical migration moved some custom answers into quick_reply resources.

### Rich content schema (reference)

Blocks array under `rich_content.blocks`. Types: `card`, `carousel`, `hero`, `buttons`, `text`, `image`, `video`, `list`, `callout`, `separator` — fields per legacy matrix in admin types; `card` uses flexible `fields[]`; carousels cap per channel (e.g. LINE 12, Messenger 10).

**Platform compatibility (summary)** — Rich: LINE, web, Messenger full; WhatsApp interactive limits; Shopee/Lazada/TikTok/SMS degrade custom blocks to text/image/URL; use `platform_content` for native product cards on marketplaces.

**`platform_content` item shape** — Platform id field (`item_id` / `product_id`), name, image, price, currency, url, `synced_at`.

### External services

| Service | Role |
| --- | --- |
| Edge `browse-platform-catalog` | Admin catalog browser; proxies marketplace product APIs via `merchant_credentials` |
| CS messaging / `webhook-line` | Outbound delivery and LINE postback ingress |
| Inngest (`cs/message.received`) | Downstream CS automation on inbound/postback |
| Supabase Storage | Media URLs for `media` type |

### Known gaps

- `allowed_channels` column still present until BFF selects are cleaned up; behaviour is fully deprecated.
- Domain index stub `requirements/domains/resource-content-shared.md` may still mention channel restriction — authoritative rule is this doc.
- Catalog browser depends on active marketplace credentials per platform tab.
- `fn_render_blocks_as_line_flex` lives in DB; admin preview also uses `bff_preview_resource_line_flex` — keep URL/deep-link contracts aligned with loyalty-user routing.

## Related

- **CS Conversations** — Composer search/send, message metadata, outbound trigger.
- **CS Knowledge Base** — Articles may reference resources; overlap with quick replies historically.
- **AMP (Rule Based / AI)** — Message nodes and `send_resource` actions consume `content_resource_id`.
- **Reward** / **Forms** — Button action targets for rich content (`reward_id`, `survey_id`).
- **Third-party channels** — Credential `service_name` drives link maps and marketplace native send (`merchant_credentials`).
