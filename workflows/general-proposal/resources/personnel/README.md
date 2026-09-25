# Canonical personnel roster

**File:** `roster.csv`  
**Methodology:** `../personnel-role-fit.md`  
**Workflow stage:** Plan proposal writing (personnel plan) → hybrid forms in Produce / Late AI

## How to use

1. Read TOR role floors from run `sources/`.
2. Match candidates from `roster.csv` using `personnel-role-fit.md`.
3. Persist proposed map in run dossier / `outline.md`.
4. Draft appendix/forms as `hybrid`; humans supply degree/experience evidence and wet signatures into the run `submission-pack/`.

## Updating the canon

When CVs change, edit `roster.csv` here (not only inside a run folder). Runs may keep a dated copy under `submission-pack/.../roster/` for audit.

## Columns (CSV)

Nick / keys, full name (EN), bachelor university + years, major, master’s university + years, master’s major, job experience narrative, plus any extra columns present in the sheet.

Row `Example` is a template — do not propose as a real person.

## Thai personal names (customer documents)

`roster.csv` is the **English** name canon for role matching. For **Thai** customer-facing lists (delivery team tables, Appendix B display names), use Thai names from the run’s Appendix B source — for EECO: `runs/<slug>/personnel/generate_appendix_b.py` (`thai_name`) / generated `personnel/appendix-b/*.html`. Do not invent Thai spellings; if a name is missing, add it to that Appendix B source (and prefer adding a clean Thai-name column to `roster.csv` when the sheet is next cleaned).
