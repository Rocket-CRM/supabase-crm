---
name: registry-regenerate
description: Regenerate requirements/REGISTRY_SUPABASE.md from the live Supabase DB. Use when (a) the user asks to refresh the registry, (b) you've made approved schema/function changes and need the registry to reflect them before grepping, or (c) you suspect the registry is stale (e.g. you grepped and a recently-added function name isn't there).
---

# Skill: Regenerate `REGISTRY_SUPABASE.md`

`requirements/REGISTRY_SUPABASE.md` is the grep target listing every public table, function, and trigger in the Supabase project, grouped by domain.

It is **regenerated on demand by this skill** — there is no scheduled cron. The agent refreshes it when needed: at the start of a DB task if it looks stale, and at the close of any task that changed the schema or a function signature.

## How to run (in Cursor)

1. Read `scripts/regen_registry_supabase.sql` from this repo.
2. Execute its contents via the Supabase MCP (`execute_sql` with project_id `wkevmsedchftztoolkmi`).
3. The query returns a single row, single column containing the entire markdown text.
4. Write that text to `requirements/REGISTRY_SUPABASE.md`, replacing the existing file. Keep a trailing newline.
5. Run `wc -l requirements/REGISTRY_SUPABASE.md` and confirm the size is in the expected ballpark (currently ~1600 lines, ~109KB).

A reference one-shot extractor for the JSON-wrapped MCP response:

```bash
python3 - <<'PY'
import json, re, pathlib, sys
src = pathlib.Path(sys.argv[1]).read_text()
outer = json.loads(src)
m = re.search(r"<untrusted-data-[a-f0-9-]+>\s*(\[.*?\])\s*</untrusted-data-[a-f0-9-]+>", outer["result"], re.S)
arr = json.loads(m.group(1))
pathlib.Path("requirements/REGISTRY_SUPABASE.md").write_text(arr[0]["registry"] + "\n")
PY
```

## Domain patterns

Domain assignment uses the regex patterns embedded at the top of `scripts/regen_registry_supabase.sql` (CTE `domains(prio, name, pattern)`). To add or refine a domain:

1. Edit the `domains` CTE in `scripts/regen_registry_supabase.sql`.
2. Re-run the regen via this skill.
3. Inspect the output for the new section.

Tips:
- `prio` controls which domain wins for an ambiguous name (higher prio wins). Use `20` for narrow rules that must win over broader ones (`Signup Code Validation` overrides `Signup & Login`).
- Patterns are POSIX regex evaluated by the `~` operator against the function/table/trigger name. Use parens + `|` for alternatives.

## When NOT to run this

- If you've only viewed the schema (no changes) and the registry already lists the names you care about — it hasn't drifted.
- For Render edge functions, queues, or crons — those go in `requirements/REGISTRY_RENDER.md`, which is hand-maintained per `.cursor/rules/06-update-docs.mdc`.

## Sanity checks after regenerating

- `head -20 requirements/REGISTRY_SUPABASE.md` shows the header with a new timestamp.
- `rg '^## Unassigned' -A 0 requirements/REGISTRY_SUPABASE.md` should appear at the bottom.
- File size should not double or halve unexpectedly. If it does, inspect the diff before committing.
