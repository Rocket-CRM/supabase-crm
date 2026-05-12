---
name: registry-regenerate
description: Regenerate requirements/REGISTRY_SUPABASE.md from the live Supabase DB. Use when (a) the user asks to refresh the registry, (b) you've made approved schema/function changes and want an immediate fresh registry instead of waiting for the daily cron, or (c) you suspect the registry is stale.
---

# Skill: Regenerate `REGISTRY_SUPABASE.md`

`requirements/REGISTRY_SUPABASE.md` is a grep target listing every public table, function, and trigger in the Supabase project, grouped by domain.

It is regenerated **daily** by a scheduled cron (GitHub Action). Use this skill when you need a fresh registry sooner than the next daily run.

## How to run

### Option A — From inside Cursor (preferred for ad-hoc agent runs)

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

### Option B — From the shell (preferred for CI / cron)

```bash
# IPv4-compatible session pooler URL (required for GitHub Actions; direct
# `db.<ref>.supabase.co` is IPv6-only and GH Actions runners are IPv4-only).
export SUPABASE_DB_URL='postgresql://postgres.wkevmsedchftztoolkmi:<password>@aws-0-ap-southeast-1.pooler.supabase.com:5432/postgres'
./scripts/regen_registry_supabase.sh
```

Notes:
- Username is `postgres.<project_ref>` (with the dot) when using the pooler.
- For a local laptop run on an IPv6-capable network, the direct URL `postgresql://postgres:<password>@db.wkevmsedchftztoolkmi.supabase.co:5432/postgres` also works.
- The wrapper script invokes `psql` against the SQL file and writes `requirements/REGISTRY_SUPABASE.md`.

## Daily cron setup (one-time)

The intended scheduled path is a GitHub Action. Sketch:

```yaml
name: regen-supabase-registry
on:
  schedule:
    - cron: '0 6 * * *'  # 06:00 UTC daily
  workflow_dispatch:
jobs:
  regen:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: sudo apt-get update && sudo apt-get install -y postgresql-client
      - run: ./scripts/regen_registry_supabase.sh
        env:
          SUPABASE_DB_URL: ${{ secrets.SUPABASE_DB_URL }}
      - name: Commit registry if changed
        run: |
          git config user.name github-actions
          git config user.email github-actions@github.com
          git add requirements/REGISTRY_SUPABASE.md
          git diff --cached --quiet || git commit -m "chore(registry): regenerate REGISTRY_SUPABASE.md"
          git push
```

Owner: add `SUPABASE_DB_URL` as a GitHub repo secret using the IPv4 session pooler URL (see Option B for the exact format). GitHub Actions runners are IPv4-only, so the direct `db.<ref>.supabase.co` host will time out.

## Domain patterns

Domain assignment uses the regex patterns embedded at the top of `scripts/regen_registry_supabase.sql` (CTE `domains(prio, name, pattern)`). To add or refine a domain:

1. Edit the `domains` CTE in `scripts/regen_registry_supabase.sql`.
2. Re-run the regen (Option A or B).
3. Inspect the output for the new section.

Tips:
- `prio` controls which domain wins for an ambiguous name (higher prio wins). Use `20` for narrow rules that must win over broader ones (`Signup Code Validation` overrides `Signup & Login`).
- Patterns are POSIX regex evaluated by the `~` operator against the function/table/trigger name. Use parens + `|` for alternatives.

## When NOT to run this

- Within a few hours of the daily cron run — wait for the scheduled regen instead.
- If you've only viewed the schema (no changes) — the registry hasn't drifted.
- For Render edge functions, queues, or crons — those go in `requirements/REGISTRY_RENDER.md`, which is hand-maintained per `.cursor/rules/06-update-docs.mdc`.

## Sanity checks after regenerating

- `head -20 requirements/REGISTRY_SUPABASE.md` shows the header with a new timestamp.
- `rg '^## Unassigned' -A 0 requirements/REGISTRY_SUPABASE.md` should appear at the bottom.
- File size should not double or halve unexpectedly. If it does, inspect the diff before committing.
