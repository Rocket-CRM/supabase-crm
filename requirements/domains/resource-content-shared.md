# Resource Content (Shared)

> Per-domain reference. Read ONLY when working on this domain. For the keyword → file map, see `_index.md`.

**Keywords:** resource_content, content_resource, quick_reply, canned_response, saved_reply, media_resource, pdf, video, link, rich_content, content_library, resource_category, sendable_content, trigger_patterns, send_resource, search_resources

**Source:** `Resource_Content.md`

**Tables:** `resource_content`, `resource_content_category`

| Function | Type | Purpose |
|---|---|---|
| `bff_upsert_resource_content_category` | BFF | Create/update content category |
| `bff_list_resource_content_categories` | BFF | List categories as tree |
| `bff_upsert_resource_content` | BFF | Create/update a resource |
| `bff_get_resource_content_details` | BFF | Get single resource (new/edit mode) |
| `bff_list_resource_content` | BFF | List resources with filters, search, pagination |
| `bff_delete_resource_content` | BFF | Delete a resource |
| `cs_fn_search_resources` | Backend | Search resources during conversation (AI, service role) |
| `cs_fn_match_resource` | Backend | Pattern-match message against `trigger_patterns` for auto-reply |
| `cs_fn_send_resource` | Backend | Look up resource → validate channel → send as message (AI, service role) |
| `cs_bff_search_conversation_resources` | BFF | Search resources during conversation (human agent, JWT auth) |
| `cs_bff_send_resource` | BFF | Send resource in conversation (human agent, JWT auth) |
| `cs_bff_search_conversation_knowledge` | BFF | Search knowledge articles during conversation (human agent, JWT auth) |

**Key Business Rules (summary):**
- Shared entity (no module prefix) — used by CS agents, CS AI, AMP workflows, AMP AI agents
- Four resource types: `quick_reply`, `media`, `link`, `rich_content`
- Categories support one level of nesting (parent + children)
- `search_tags` array for freeform tagging and search
- `allowed_channels` deprecated — channel comes from conversation; upsert writes NULL
- `trigger_patterns` array for auto-matching customer messages to resources (migrated from custom answers)
- Custom answers migrated from `cs_knowledge_articles` to `resource_content` as quick_replies
- Both AI and human agents use `cs_fn_search_resources` to find content, `cs_fn_send_resource` to deliver it

---
