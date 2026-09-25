# Agent-System Maintenance Scripts

## `audit_agent_tokens.py`

Measures what past agent threads read, wrote, and burned in input tokens. Use to verify that rule/doc changes actually reduced token waste.

### Baseline (run once, right after the 2026-04-19 cleanup)

```bash
python3 scripts/audit_agent_tokens.py --save-baseline
```

This records the current per-thread averages into `scripts/.agent_token_baseline.json`.

### Measure delta after changes

```bash
python3 scripts/audit_agent_tokens.py --last 50 --compare
```

Compares the most recent 50 threads against the baseline. Expect:

- `tokens_burned_reads` per-thread **down** (the big win)
- `index_domain_monolith` category reads → 0
- `index_function` category reads → near 0 (only on explicit request)
- `scratchpad_migration` / `scratchpad_plan` reads → 0 (covered by `.cursorignore`)
- `archived_draft` reads → 0
- `domain_index_split` reads → appears as new category replacing the monolith

### All threads report (no comparison)

```bash
python3 scripts/audit_agent_tokens.py
```

### Notes on token estimates

The script approximates tokens as `bytes / 4` of the file's **current** workspace copy. If a file was deleted or moved, its token contribution is 0 (under-counts historical cost). Ratios and categories are the reliable signal — absolute numbers are directional.
