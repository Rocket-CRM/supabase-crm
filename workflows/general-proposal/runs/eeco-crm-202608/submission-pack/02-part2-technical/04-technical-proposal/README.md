# Technical proposal (Part 2)

**Language:** Thai (submission)  
**Source:** `runs/eeco-crm-202608/th/proposal.md`  
**Packed:** 2026-08-07

| Path | Role |
|---|---|
| `proposal.md` | Thai technical proposal (source) |
| `ส่วนที่2_ข้อเสนอทางเทคนิค_แนวคิดสถาปัตยกรรมและเครื่องมือพัฒนา.pdf` | Upload PDF = Thai title cover + body |
| `assets/` | Images referenced by `./assets/…` in the markdown |
| `diagrams/executive-overview/` | Executive pillar matrix (`{{diagram:executive-overview}}`; use Thai data via `data.th.json` / `?lang=th`) |

Rebuild PDF (from `workflows/general-proposal/.tools-playwright/`):

```bash
node ../runs/eeco-crm-202608/submission-pack/egp-upload-ready/build-egp-technical-proposal.mjs
```

English backup remains at the run root and under `en/` — do not overwrite those with Thai.
