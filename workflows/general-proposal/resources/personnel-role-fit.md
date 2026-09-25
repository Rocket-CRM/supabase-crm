# Personnel role-fit methodology

How to map `resources/personnel/roster.csv` to bid-required roles without inventing qualifications.

## Purpose

Propose a delivery team that:

1. Meets TOR **compliance floors** (degree field, years, role-specific experience) where the pack makes them mandatory.
2. **Stretches** titles and emphasis toward the TOR role when the CV honestly supports it.
3. Does **not** invent degrees, employers, dates, or years.
4. Balances “best narrative fit for the TOR” against “not a blatant stretch from their real work.”

## Inputs

- TOR / personnel clauses (verbatim in `sources/`) — floors and scored tiers.
- Canonical roster: `resources/personnel/roster.csv`
- Optional bid-specific answers in `sources/`

## Procedure

1. **Extract role slots** — name, degree minimum, years, domain keywords (e.g. “web/graphic design” vs “systems analysis”).
2. **Score each candidate per slot** (dossier-only):
   - Degree: meets / related-argue / miss
   - Years in required domain: meets / close / miss
   - Title stretch: natural / moderate / forced
3. **Assign** — prefer meets on floors first; use moderate stretch for scoring upside only when floors clear.
4. **Flag gaps in dossier** — never claim “Equal” in the comparison matrix if floors are unmet.
5. **Produce hybrid artifacts** — named summary in proposal; appendix/forms shells; humans supply certificates + wet signatures.
6. **Late AI** — regenerate forms only after role map is locked (Review 2 / Clarify).

## Stretch rules

| Allowed | Not allowed |
|---|---|
| Emphasize TOR-relevant duties already on the CV | Adding degrees or employers |
| Map a design-tech master’s as “related” only when TOR wording allows related fields — mark risk in dossier | Treating a clear miss as compliant in customer prose |
| Use supporting specialists outside scored slots | Substituting a non-qualifying person into a mandatory scored slot silently |

## Outputs

- Personnel plan bullets in `outline.md` / dossier
- Proposal named-team summary (customer-facing)
- Appendix / form drafts (`hybrid`)
- Matrix status honest to floors

## Cross-links

- Roster: `personnel/roster.csv` + `personnel/README.md`
- Company signatory on forms: `standard-company-profile.md`
