# Internal Knowledge

> Per-domain reference. Read ONLY when working on this domain. For the keyword -> file map, see `_index.md`.

**Keywords:** internal_knowledge, feature knowledge, feature_items, knowledge_blocks, knowledge_type, perspectives, output_uses, downstream agent context, slide_generation, frontend_context, implementation_brief

**Source:** `docs/FEATURE_KNOWLEDGE_DATABASE_PLAN.md`

**Tables:** `internal_knowledge_feature_items`, `internal_knowledge_blocks`, `internal_knowledge_type_templates`

| Function | Type | Purpose |
|---|---|---|
| `internal_knowledge_get_feature_tree` | Read RPC | Return active feature hierarchy, optionally rooted by slug |
| `internal_knowledge_get_feature_context` | Read RPC | Return typed blocks for one feature, optionally including children and metadata filters |
| `internal_knowledge_search_feature_knowledge` | Read RPC | Full-text search knowledge blocks with feature/type/perspective/use/scope filters |
| `internal_knowledge_get_related_features` | Read RPC | Return parent/child relationships and related-feature blocks |
| `internal_knowledge_list_knowledge_type_templates` | Read RPC | Return authoring templates by knowledge type |
| `internal_knowledge_create_feature_item` | Edit RPC | Create a domain/feature/sub-feature item |
| `internal_knowledge_update_feature_item` | Edit RPC | Update or deactivate a feature item |
| `internal_knowledge_create_knowledge_block` | Edit RPC | Create a typed reusable knowledge block |
| `internal_knowledge_update_knowledge_block` | Edit RPC | Update or deactivate a knowledge block |
| `internal_knowledge_suggest_block_metadata` | Authoring RPC | Return recommended scopes and quality rules for a knowledge type |
| `internal_knowledge_validate_knowledge_block` | Authoring RPC | Validate title/content/type/perspective/use/scope inputs before writing |

**Key Business Rules (summary):**
- Product hierarchy lives in `internal_knowledge_feature_items`; block content lives in `internal_knowledge_blocks`.
- All schema objects and functions use the `internal_knowledge` prefix.
- Content is stored as small Markdown/plain-text blocks, not one flat feature document.
- Retrieval should filter by feature, `knowledge_type`, `perspectives`, `output_uses`, and `scope` before generating downstream outputs.
- `internal_knowledge_blocks.search_vector` supports full-text search over title and content.
- `internal_knowledge_type_templates` stores authoring guidance for each allowed `knowledge_type`.
- Read functions are granted to `authenticated` and `service_role`; edit functions are granted to `service_role`.
- Exact implementation object names in generated outputs should still be verified from live schema/code before implementation.
