# General proposal runs

Each deal or bid lives in `runs/<project>-<yyyymm>/`. That folder is the only state for the run.

## Start a run

1. New Cursor thread.
2. `@.cursor/rules/23-general-proposal-workflow.mdc` (or say “run general proposal” / “EECO proposal”).
3. Create `runs/<slug>/sources/` and drop TOR extracts, notes, or a combined pack.
4. Agent starts at **submission inventory** → classify → understand → **clarify** before outlining or writing.
5. After compile (or a large rewrite): **principles review** → `principles-review.md` → deepen/cut only where judgment adds value (see SCAFFOLDS “Depth and examples”). For every cut/merge, preserve unique commitments and technical meaning; record visual before/after inventory. Examples and operating detail are not mandatory in every chapter.

## Project context

There is no hidden project-context MCP. Context flows through:

`sources/` (authoritative TOR and answers) → `dossier.md` (index with exact source locations) → `outline.md` `reads` (what each section must reopen).

If the dossier or `reads` pointers are missing, build them from `sources/` before drafting. Do not substitute a previous proposal, a product knowledge base, or remembered TOR wording.

## Mockups (loyalty-admin sandbox)

See `../MOCKUPS.md`. Per run: `mockup-registry.json` → shortcodes `{{mockup:Mxx}}` → `loyalty-admin-handoff-prompt.md` → pages under `/proposal-mockups/<runKey>/` → `npm run mockups:preview` / `mockups:capture`.

Optional workspace: repo-root `proposal-studio.code-workspace` (CRM + `~/Documents/rocket/loyalty-admin`).

## First-run source pattern (EECO)

A combined extract of the Eastern Seaboard / EECO CRM bid pack already exists at:

`.cursor/plans/eastern-seaboard-crm-documents-combined.md`

For an EECO run, copy or link that file into:

`workflows/general-proposal/runs/eeco-crm-<yyyymm>/sources/`

Do not draft the proposal until Review A (submission plan) and Clarify are done.
