# Thai convert — EECO CRM (`th/`)

**Run:** `eeco-crm-202608`  
**Stage:** 11 — Thai convert (manual)

## English revision converted

| Item | Value |
|---|---|
| Converted from | Run-root English after Exact TOR text pass (warranty TOR 14 quotes + matrix col 1 verbatim) |
| Frozen snapshot | `en/proposal.md`, `en/comparison-matrix.md` (~2026-08-05T07:47Z UTC) |
| English backup | Remains at run root — **do not overwrite with Thai** |
| Structural status | Thai is the approved condensed submission version, not a line-for-line layout copy of the frozen English backup; coverage parity is documented in `translation-review.md` |

## TOR verification

| Surface | Treatment |
|---|---|
| `th/comparison-matrix.md` col 1 | Verbatim from `sources/eastern-seaboard-crm-documents-combined.md`, the available extraction of `Attach_TOR_1.pdf`. Not reverse-translated from English paraphrases. |
| `th/proposal.md` warranty commitments | Proposal-owned Thai states the 1-year warranty, 24×7 intake, 30-minute response, and resolution times; the duplicate OCR blockquote was removed. |
| `อ้างอิง: TOR …` | Clause IDs retained from the English root. |

The original binary `Attach_TOR_1.pdf` is not present in the repository. OCR forms in matrix column 1 (for example `ดาเนิน`, `จานวน`, `สานัก`) are preserved from the available source extraction and must be verified visually against the original PDF before final packing.

## Files in this folder

| File | Status |
|---|---|
| `comparison-matrix.md` | Proposal-owned Thai finalized; protected TOR column awaits PDF visual verification |
| `proposal.md` | Final Thai language and anti-AI pass completed; architecture, database, security, system design, integration, migration, delivery, and operations coverage preserved |
| `translation-review.md` | Final language, structure, cold-reader, visual inventory, and technical coverage review |
| `README.md` | This note |

## Packing

**Packed 2026-08-07** into `submission-pack/`:

| Source | Pack destination |
|---|---|
| `th/proposal.md` | `02-part2-technical/04-technical-proposal/proposal.md` (+ `assets/`, `diagrams/executive-overview/`) |
| `th/comparison-matrix.md` | `02-part2-technical/05-comparison-matrix/comparison-matrix.md` |

See `submission-pack/CHECKLIST.md` for remaining bid-blocking items (PDF export, TOR PDF verify, e-GP price).
