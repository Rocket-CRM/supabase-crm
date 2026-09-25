# Open API artefacts

| File | Role |
|---|---|
| `Rocket-Loyalty-Open-API.pdf` | Merchant-sendable specification. Attach this to the customer email. |
| `openapi.yaml` | Machine contract (OpenAPI 3.1). |
| `PLATFORM_API_REFERENCE.md` | Compact route inventory for implementers. |
| `generate-merchant-pdf.mjs` | Rebuilds the PDF from `requirements/Open_API.md` (field tables, JSON examples, and curls are copied — not rewritten). |

```bash
node docs/openapi/generate-merchant-pdf.mjs
```

Requires `pandoc` and Google Chrome. Output: `docs/openapi/Rocket-Loyalty-Open-API.pdf`.
