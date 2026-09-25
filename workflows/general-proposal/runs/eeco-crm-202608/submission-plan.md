# Submission plan — EECO CRM & Database Management System

**Run:** `eeco-crm-202608`  
**Buyer:** สำนักงานคณะกรรมการนโยบายเขตพัฒนาพิเศษภาคตะวันออก (สกพอ. / EECO)  
**Project:** การพัฒนาระบบบริหารจัดการความสัมพันธ์นักลงทุนและฐานข้อมูลกลาง (CRM & Database Management System)  
**Bid:** เอกสารประกวดราคาอิเล็กทรอนิกส์ เลขที่ ๐๑๘/๒๕๖๙ · e-bidding  
**Key dates (from pack):** ประกาศ 13 ก.ค. 2569 · เสนอราคา 7 ส.ค. 2569 09:00–12:00 · ยืนราคา ≥120 วัน · แล้วเสร็จ ≤210 วัน  
**Budget / mid-price:** งบ 4,000,000.00 บาท · ราคากลาง 3,965,433.11 บาท (รวม VAT)  
**Award model:** ราคา 20% + เทคนิค 80% · เทคนิคต้อง ≥70% ก่อนเปิดราคา  

**Source pack:** `sources/eastern-seaboard-crm-documents-combined.md`  
**Catalog:** `workflows/general-proposal/resources/document-groups-catalog.md`  
**Status:** Example run aligned to post-2026-08 workflow shape (groups + `library` class). Proposal already compiled; remaining = personnel evidence, e-GP price, face-checks.  
**Bidder:** Rocket Innovation (single company).

Classes: `manual` | `library` | `generate` | `hybrid` | `out_of_band`

---

## Groups in scope

| Group | In? | Notes |
|---|---|---|
| G1 Proposal | Yes | Technical narrative P2.4 |
| G2 Pricing breakdown | **No** | e-GP quote only (G8); no separate pricing narrative required |
| G3 Company standard docs | Yes | From `resources/company-docs/` |
| G4 Comparison matrix | Yes | P2.6 |
| G5 Personnel | Yes | Roster library + hybrid forms |
| G6 Project evidence | Yes | Library proofs + hybrid cover |
| G7 Power of attorney | Optional | If authorizing |
| G8 e-GP price entry | Yes | Manual system entry |
| G9 Live POC | Yes | Out of band post-submit |
| G10 Bonds | Post-award | Track separately |
| G11 Optional company-claim evidence | Optional | MarTech / headcount proof |
| G12 Mockups | Yes | Hybrid catalogue |

---

## Package inventory by group

### G3 — Company standard docs (Part 1)

| # | Item | Class | Source / notes |
|---|---|---|---|
| P1.1a | หนังสือรับรองการจดทะเบียนนิติบุคคล | `library` | `resources/company-docs/company-certificate.pdf` |
| P1.1b | หนังสือบริคณห์สนธิ (+ เพิ่มเติม) | `library` | `articles-of-association*.pdf` |
| P1.1c | ผู้ถือหุ้น / กรรมการ | `library` | `shareholders.pdf` + directors on cert |
| P1.2 | งบการเงิน / มูลค่าสุทธิ | `library` | `financials-2568.pdf` |
| P1.3 | ภพ.20 + ทะเบียนการค้า | `library` | `vat-pp20.pdf`, `commercial-registration.pdf` |
| P1.5 | บัญชีเอกสารส่วนที่ 1 | `manual` | e-GP auto |

### G6 — Project evidence (Part 1 qual + Part 2 scoring)

| # | Item | Class | Source / notes |
|---|---|---|---|
| P1.4 / P2.2 / P2.3 | หนังสือรับรองผลงาน + สัญญา/SOW (≥2M CRM/task ≤5y) | `library` | `resources/project-proofs/` — Syn, Rangsit, POP, Kao, Rermmai, First Class + certificate |
| Cover | ภาคผนวก ง สรุปผลงาน | `hybrid` | Late AI after picks; stretch per `project-proof-stretch.md` |

### G1 — Proposal (Part 2)

| # | Item | Class | Notes |
|---|---|---|---|
| P2.4 | แนวคิด / architecture / tools + embedded project plan | `generate` | TOR §10.2(4) |
| P2.9 | Company / bidder introduction | `hybrid` | `standard-company-profile.md` + approved answers |

### G4 — Comparison matrix

| # | Item | Class | Notes |
|---|---|---|---|
| P2.6 | ตารางเปรียบเทียบคุณสมบัติ | `generate` | TOR §10.2(6) |

### G5 — Personnel

| # | Item | Class | Notes |
|---|---|---|---|
| P2.5a | ภาคผนวก ข forms | `hybrid` | Drafted; wet sign remaining |
| P2.5b | Degree + experience evidence | `manual` | Staff supply |
| Roster | Canonical CVs | `library` | `resources/personnel/roster.csv` |

### G12 — Mockups

| # | Item | Class | Notes |
|---|---|---|---|
| P2.7 | แค็ตตาล็อก / แบบรูป | `hybrid` | M01–M18 in pack |

### G7 / G8 / G9 / G11

| # | Item | Class | Notes |
|---|---|---|---|
| P2.1 | หนังสือมอบอำนาจ | `manual` | If needed |
| Q.1 | ใบเสนอราคา e-GP | `manual` | Incl. VAT; ≥120 days |
| POC | Live POC | `out_of_band` | ภาคผนวก ก §3 |
| Opt | MarTech / headcount proof | `manual` / `library` | Optional claims |
| Opt | Insurance letter | `library` | `company-docs/insurance-letter.pdf` if pack asks |

### Post-award (not bid-day)

| # | Item | Class | Notes |
|---|---|---|---|
| PA.1–4 | Bonds, formal plans | `manual` / `hybrid` | See prior plan |

---

## Staff requests

See `manual-requests.md` (template: `resources/manual-request-template.md`).

## What this workflow generated

1. **`proposal.md`** — technical approach + embedded project plan; exec overview diagram.
2. **`comparison-matrix.md`** — TOR four-column table.
3. **Hybrid:** company intro; personnel summary + Appendix B drafts; mockups; past-work cover.
4. **Library pulls:** company docs + six proofs + certificate into `submission-pack/`.

## Scoring map

| Technical weight | Factor | Bid artifact |
|---|---|---|
| 20% of tech | Past work count | G6 |
| 10% of tech | Highest past value | G6 (Syngenta) |
| 15% of tech | Concept / architecture | G1 P2.4 |
| 15% of tech | Personnel | G5 |
| 40% of tech | Live POC | G9 |
| Price 20% of award | e-GP quote | G8 |

## Review A checkpoint (historical)

Inventory and classes accepted for this run; remaining human work tracked in `submission-pack/CHECKLIST.md`.
