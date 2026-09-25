## 5.7 Bring Excel history into one structured database

Go-live only counts if bureau spreadsheets become a clean CRM, including one person linked to many companies. Rocket separates this one-time historical cutover from the day-to-day list import officers use after launch. Migration preparation runs before Phase 2 acceptance; the reconciled production load occurs in Phase 3.

## Migration methodology

| Phase | What Rocket runs | Includes (sub-capabilities) |
|---|---|---|
| Discover | Inventory bureau Excel/exports and stewards. | Source list per bureau; checksum; owner contact; quarantine until mapping starts. |
| Map | Align each file to the target CRM model. | Mapping sheet; unmapped-column report; sign-off before cleanse/load. |
| Cleanse | Normalize formats so dedupe and reports work. | Date and Tax ID formats; trim/encoding; reject or quarantine bad rows with a report. |
| Dedupe organizations | Merge preferring **Tax ID**, then legal name. | Collision report; steward keep/merge log; no silent overwrite of conflicts. |
| Dedupe / link persons | One person row; 1:N org links. | Merge candidates; org–contact links; no clone persons across companies. |
| Reconcile & load | Production commit only after counts signed off. | Count reconciliation; rollback plan; cutover window with สกพอ. |
| Preserve controls | Same audit/RBAC/watermark as new data. | Access logs ≥180 days; backup/DR docs; Section 5.6 controls on migrated sensitive files. |

```mermaid
flowchart LR
  X[Excel drops] --> ST[Staging]
  ST --> CL[Cleanse and map]
  CL --> DD[Dedupe]
  DD --> REL[1:N relationships]
  REL --> RC[Reconcile]
  RC --> LIVE[(PostgreSQL)]
```

**Validation:** row counts and key totals (organizations, persons, cases) must match the signed reconcile sheet before go-live use. Failed rows remain in quarantine with a report — they are not silently dropped.

Migration **preparation** reports are Phase 2 deliverables; the **structured clean database** is a Phase 3 deliverable (Section 6).

Reference: TOR 5.9.
