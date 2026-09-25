# Document groups catalog

Standard groups for general / government / custom proposal packs. **Include, omit, or add** groups per run. List concrete documents under each group in `submission-plan.md` and classify each row (`manual` | `library` | `generate` | `hybrid` | `out_of_band`).

This file is a catalog — not a validator. EECO used most of these; thinner bids may use a subset.

## Standard groups

| Group ID | Name | Typical contents | Default modes |
|---|---|---|---|
| `G1` | **Proposal** | Company intro; features / capabilities; architecture; timeline / delivery; ops & tech support (inc. SLA) | mostly `generate`; company intro `hybrid` |
| `G2` | **Pricing breakdown / summary** | Commercial structure, line items, assumptions, validity — customer-facing narrative or table | `hybrid` (facts human) |
| `G3` | **Company standard docs** | Juristic certificate, articles, shareholders/directors, financials, VAT/commercial reg, insurance | `library` (else `manual`) |
| `G4` | **Summary table / comparison matrix** | TOR vs response matrix | `generate` |
| `G5` | **Personnel** | Named summary in proposal; appendix/forms; degree + experience evidence | `hybrid` + roster `library` |
| `G6` | **Project evidence** | Cover summary (AI) + contracts / certificates from library | `hybrid` cover + `library` PDFs |

## Optional / bid-specific groups (add when pack requires)

| Group ID | Name | Typical contents | Default modes |
|---|---|---|---|
| `G7` | Power of attorney / authorization | POA, stamp duty | `manual` |
| `G8` | e-GP / portal price entry | System quote (often not a PDF) | `manual` |
| `G9` | Live POC / demo | Scenarios, prep notes | `out_of_band` |
| `G10` | Bonds / guarantees | Bid, performance, advance, retention | `manual` |
| `G11` | Optional company-claim evidence | Rankings, headcount, office photos | `library` / `manual` |
| `G12` | Mockups / catalogue | UI samples for technical pack | `hybrid` |

## Per-run procedure

1. Start from this catalog.
2. Mark each group **in** / **out** / **added (custom)**.
3. Under each in-scope group, list the actual documents the buyer or scoring needs.
4. Classify each document.
5. Emit staff-facing pulls via `manual-requests.md` (`manual-request-template.md`).

## Cross-links

- Classes + stages: `REFERENCE.md`
- Company profile craft: `standard-company-profile.md`
- Personnel fit: `personnel-role-fit.md` + `personnel/roster.csv`
- Project proofs: `project-proof-stretch.md` + `project-proofs/INDEX.md`
- Pricing scaffold: `pricing-breakdown.md`
- Company doc index: `company-docs/INDEX.md`
