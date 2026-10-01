# DEPRECATED — Split into per-domain files

This 79KB monolithic index has been split into small per-domain files to save input tokens.

**Use instead:**

- `requirements/domains/_index.md` — keyword → file pointer map (read first when you don't know which domain applies)
- `requirements/domains/<slug>.md` — the per-domain reference (read only the one you need)

If you see a rule or doc still referencing `INDEX_DOMAIN.md`, treat it as a reference to `requirements/domains/_index.md` and fix the rule on the way through.

The original monolithic content is preserved in git history — check `git log requirements/INDEX_DOMAIN.md` if you need it.
