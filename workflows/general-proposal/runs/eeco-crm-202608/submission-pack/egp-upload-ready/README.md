# EECO e-GP upload

**Upload folder:** `upload/`

| e-GP slot | File |
|---|---|
| Arrow 1 — ผลงานคุณสมบัติ | `upload/EECO_ส่วนที่1_ผลงานคุณสมบัติ_TOR4.13.pdf` |
| Arrow 2 — ผลงานคะแนน | `upload/EECO_ส่วนที่2_ผลงานคะแนน_TOR4.13.pdf` |
| Part 2 — ข้อเสนอทางเทคนิค | `upload/EECO_ส่วนที่2_ข้อเสนอทางเทคนิค.pdf` |
| Part 2 — คุณสมบัติบุคลากร (ข้อ ๔ / TOR 5.12) | `upload/EECO_ส่วนที่2_คุณสมบัติบุคลากร_TOR5.12.pdf` |
| Part 2 — ตารางเปรียบเทียบคุณสมบัติ (ข้อ ๕) | `upload/EECO_ส่วนที่2_ตารางเปรียบเทียบคุณสมบัติ.pdf` |

Also copied to `~/Downloads/EECO-eGP-upload/` for upload.

Past-work files = Thai cover + certificate + evidence.  
Technical proposal = Thai title cover + full Thai body (Sarabun, headers/footers, cropped mockups).  
Personnel = Thai cover + interleaved Appendix B + education evidence.  
Comparison = Thai cover + landscape comparison matrix.

Build artifacts: `_build/`  
Rebuild from `workflows/general-proposal/.tools-playwright/`:

```bash
node ../runs/eeco-crm-202608/submission-pack/egp-upload-ready/_build/build-egp-technical-proposal.mjs
node ../runs/eeco-crm-202608/submission-pack/egp-upload-ready/build-egp-past-work.mjs
node ../runs/eeco-crm-202608/submission-pack/egp-upload-ready/build-egp-personnel-comparison.mjs
```
