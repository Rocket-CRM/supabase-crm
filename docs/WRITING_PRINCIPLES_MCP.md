# Writing Principles (local craft — not CRM Knowledge MCP)

Craft playbooks live as markdown under [`Writing Principles/`](../Writing%20Principles/).

As of CRM Knowledge **v2**, Writing Principles are **not** served from the hosted Knowledge MCP and are **not** stored in `internal_knowledge_*` (those tables were removed).

## How agents should use them

1. Read `Writing Principles/INDEX.md` for routing.
2. Load `CORE_WRITING_PRINCIPLES.md` first for structure/voice.
3. Load genre files as needed (`PROPOSAL_WRITING_PRINCIPLES.md`, slide/web/translation/feature-guide files, `SALES_FEATURE_COPY_PRINCIPLES.md` for catalog copy). Pricing sheet / features summary craft lives in the sales pack (`rocket-sales/commercial/COPY_PRINCIPLES.md`).
4. For **product facts**, use CRM Knowledge MCP (`search_docs` / `get_section`) over `requirements/`.

**Truth boundary:** Writing Principles = craft. CRM Knowledge MCP = product facts from requirements.

## Retired

- Hosted tools: `writing_get_*`, `writing_search_guidance`, etc.
- Seed pipeline into `internal_knowledge_*` (`scripts/generate_writing_principles_seed.py` is obsolete for production load).
