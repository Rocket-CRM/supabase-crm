# Loyalty-admin handoff — eeco-crm-202608

Paste this **entire file** into a single Cursor thread opened on `~/Documents/rocket/loyalty-admin` (canonical clone).

## Task

Produce **proposal-usable** mockup pages for this bid in **one pass**.
When you finish, CRM preview/capture must be able to show them in the proposal with **no further scaffold or stub pass**.
Do not touch product routes (rewards, CS inbox, etc.).

### Definition of done (proposal-usable)

- Every registry path returns 200 with a **realistic product UI** (not wireframe, not TODO, not “scaffold”).
- Screen matches the brief + `mustShow` — credible for a government bid / POC walkthrough at arm’s length.
- Thai UI chrome; static demo data only.
- If files already exist under `/proposal-mockups/eeco/`, **upgrade or replace** them to this quality — do not leave thin first drafts.

### UI quality principles (mandatory)

These are **principles**, not a checklist of specific bugs. Apply across every screen:

1. **Use the real design system.** Prefer first-class Shopify Polaris components (`DataTable`, `IndexTable`, `Badge`, `Tabs`/`ButtonGroup`, `Banner`, `Page`/`Layout`/`Card`, `FormLayout`, `Filters`, etc.). Do **not** fake tables with stacked divs or plain HTML tables when Polaris has a table pattern.
2. **Enterprise density, not demo wireframe.** Spacing, typography, and hierarchy should look like a shipped admin app an evaluator could believe is production-adjacent.
3. **Alignment and rhythm.** Badges/pills in a row share height, baseline, and gap; headers and actions align on one bar; columns line up. No floating chips with uneven padding.
4. **Status as badges, not raw text** where status is meaningful (active/suspended, SLA, stage, consent).
5. **Print / PDF / document previews must look like documents** — agency header, title block, labeled field grid or definition list with consistent columns, summary section, signature/footer affordances — not a sparse card with five loose lines.
6. **Interactive affordances where the brief implies them** (selection checkboxes if “edit selected” exists; clear primary/secondary actions; filters/tabs that look wired).
7. **Still static data** — polish the chrome and composition; do not call real APIs or invent forbidden fields.
8. **Real government / buyer agency logo** — use the official mark from the registry `branding` block (run asset path and/or URL). Put it in the app chrome (top bar / login) and on print/PDF headers. **Do not** invent a crest, substitute a generic seal, use Rocket’s logo as the agency mark, or omit branding when `branding.logo` is provided. If the logo file/URL is missing, stop and ask — do not fake one.

### Buyer / agency branding (mandatory for government packs)

- **Agency:** สกพอ. (Eastern Economic Corridor Office (EECO))
- **Official logo (run asset):** copy from the CRM run folder `eeco-crm-202608/assets/agency-logo.png` into this admin project (e.g. `public/proposal-mockups/eeco/agency-logo.png`) and reference that local file in every screen’s chrome / document header.
- **Logo notes:** Use only the official สกพอ./EECO mark. Place the real file at runs/eeco-crm-202608/assets/agency-logo.png before FE generation. Do not invent a crest.
- **Branding must avoid:** Invented government crest or seal; Rocket logo as agency mark; generic placeholder emblem

### Requirements

1. Routes exactly as in the registry below (Next.js App Router).
2. Shopify Polaris UI at full fidelity (see principles above); Thai chrome; **official agency logo** in chrome per branding block.
3. Static demo data only — invent plausible labels for this bid; **no real investor PII**; **do not invent external-system field names** the pack does not supply; no public self-registration (named internal users only).
4. Keep pages public (no auth) under `/proposal-mockups/` — middleware already allows this prefix.
5. Index at `/proposal-mockups/eeco` listing all screens.
6. Sync `public/proposal-mockups/eeco/mockup-manifest.json` with the registry pages.
7. Commit only when the user asks; user may push `main`.

## Registry (source of truth)

```json
{
  "version": 1,
  "run": "eeco-crm-202608",
  "runKey": "eeco",
  "origin": "loyalty-admin",
  "defaultOriginUrl": "http://localhost:3001",
  "branding": {
    "agencyName": "สกพอ.",
    "agencyNameEn": "Eastern Economic Corridor Office (EECO)",
    "logo": {
      "runAsset": "assets/agency-logo.png",
      "url": null,
      "notes": "Use only the official สกพอ./EECO mark. Place the real file at runs/eeco-crm-202608/assets/agency-logo.png before FE generation. Do not invent a crest."
    },
    "mustAvoid": "Invented government crest or seal; Rocket logo as agency mark; generic placeholder emblem"
  },
  "mustAvoid": "Inventing real investor PII; inventing EEC OSS field names; implying public self-registration (internal named users only).",
  "pages": [
    {
      "id": "M01",
      "section": "A9",
      "path": "/proposal-mockups/eeco/M01",
      "title": "Login / SSO entry",
      "aliases": [
        "Login / SSO entry"
      ],
      "user": "EECO named user",
      "tor": "5.7.1; POC 2",
      "brief": "SSO entry for named EECO users only. Show agency branding, SSO button, and a clear note that access is for authorized staff (no public self-registration).",
      "mustShow": [
        "SSO CTA",
        "no signup link",
        "Thai labels preferred"
      ]
    },
    {
      "id": "M02",
      "section": "A8",
      "path": "/proposal-mockups/eeco/M02",
      "title": "Executive heat map / dashboard",
      "aliases": [
        "Executive heat map / dashboard (post-login)"
      ],
      "user": "EECO manager / director",
      "tor": "5.6; POC 2",
      "brief": "Post-login executive dashboard: heat-map style workload / SLA visibility, พ.ศ. or fiscal period filter, drill toward units or officers. Fake aggregates only.",
      "mustShow": [
        "heat map or workload grid",
        "period filter",
        "SLA / escalation signals"
      ]
    },
    {
      "id": "M03",
      "section": "A5",
      "path": "/proposal-mockups/eeco/M03",
      "title": "Customer 360",
      "aliases": [
        "Customer 360 (person + juristic)"
      ],
      "user": "EECO staff",
      "tor": "5.5.2",
      "brief": "Single customer 360 for person and juristic profiles: identity summary, related activities, journey stage, consent status. Use fictional company names.",
      "mustShow": [
        "person vs juristic",
        "linked activities",
        "consent badge"
      ]
    },
    {
      "id": "M04",
      "section": "A5",
      "path": "/proposal-mockups/eeco/M04",
      "title": "Bulk CSV / Excel import",
      "aliases": [
        "Bulk CSV / Excel import"
      ],
      "user": "EECO staff / data steward",
      "tor": "5.5.1",
      "brief": "Bulk import wizard: upload CSV/Excel, column mapping, validation errors, commit summary.",
      "mustShow": [
        "upload",
        "validation errors table",
        "commit summary"
      ]
    },
    {
      "id": "M05",
      "section": "A5",
      "path": "/proposal-mockups/eeco/M05",
      "title": "Consent capture and history",
      "aliases": [
        "Consent capture and history"
      ],
      "user": "EECO staff",
      "tor": "5.5.2, 5.8.3",
      "brief": "Consent capture form plus chronological consent history for PDPA-aligned operations.",
      "mustShow": [
        "consent purpose",
        "history timeline"
      ]
    },
    {
      "id": "M06",
      "section": "A5",
      "path": "/proposal-mockups/eeco/M06",
      "title": "Master data admin",
      "aliases": [
        "Master data admin (industry / country)"
      ],
      "user": "EECO admin",
      "tor": "5.5.2",
      "brief": "Admin lists for industry / country (and similar reference data) with active flags.",
      "mustShow": [
        "reference table",
        "add/edit"
      ]
    },
    {
      "id": "M07",
      "section": "A6",
      "path": "/proposal-mockups/eeco/M07",
      "title": "Activity create / edit (desktop)",
      "aliases": [
        "Activity create / edit (desktop)"
      ],
      "user": "EECO staff",
      "tor": "5.5.3; POC 4",
      "brief": "Desktop activity create/edit: customer link, type, datetime, notes, attachments, save.",
      "mustShow": [
        "customer picker",
        "activity fields",
        "attachments"
      ]
    },
    {
      "id": "M08",
      "section": "A6",
      "path": "/proposal-mockups/eeco/M08",
      "title": "Activity capture (mobile/tablet)",
      "aliases": [
        "Activity capture on tablet / phone"
      ],
      "user": "EECO field officer",
      "tor": "5.5.3, 3.2",
      "brief": "Mobile/tablet-friendly activity capture: large tap targets, photo attach, offline-ready cue (demo).",
      "mustShow": [
        "compact form",
        "photo attach"
      ]
    },
    {
      "id": "M09",
      "section": "A6",
      "path": "/proposal-mockups/eeco/M09",
      "title": "Task and team calendar",
      "aliases": [
        "Task and team calendar"
      ],
      "user": "EECO staff / team lead",
      "tor": "5.5.3",
      "brief": "Team calendar / task board with due dates and assignees (fake names).",
      "mustShow": [
        "calendar or agenda",
        "assignee"
      ]
    },
    {
      "id": "M10",
      "section": "A6",
      "path": "/proposal-mockups/eeco/M10",
      "title": "Ticket create / route / SLA",
      "aliases": [
        "Ticket create / route / SLA"
      ],
      "user": "EECO staff",
      "tor": "5.5.3",
      "brief": "Ticket create with routing unit, SLA clock, escalation state.",
      "mustShow": [
        "route / unit",
        "SLA indicator"
      ]
    },
    {
      "id": "M11",
      "section": "A6",
      "path": "/proposal-mockups/eeco/M11",
      "title": "Activity A4/PDF print preview",
      "aliases": [
        "Activity report — A4 / PDF print preview"
      ],
      "user": "EECO staff",
      "tor": "POC 4.2",
      "brief": "Print preview of an activity report laid out for A4 / PDF.",
      "mustShow": [
        "A4-like layout",
        "print/export affordance"
      ]
    },
    {
      "id": "M12",
      "section": "A7",
      "path": "/proposal-mockups/eeco/M12",
      "title": "Investment Journey pipeline board",
      "aliases": [
        "Investment Journey — pipeline board"
      ],
      "user": "EECO promotion officer / manager",
      "tor": "5.5.4",
      "brief": "Kanban / pipeline board for Investment Journey stages with card counts and SLA coloring.",
      "mustShow": [
        "stages as columns",
        "case cards"
      ]
    },
    {
      "id": "M13",
      "section": "A7",
      "path": "/proposal-mockups/eeco/M13",
      "title": "Investment case workspace",
      "aliases": [
        "Investment case workspace"
      ],
      "user": "EECO staff",
      "tor": "5.5.3–5.5.4, 5.7",
      "brief": "Single investment case workspace: summary, timeline, documents, linked activities, OSS panel slot.",
      "mustShow": [
        "case header",
        "tabs or sections for timeline/docs"
      ]
    },
    {
      "id": "M14",
      "section": "A7",
      "path": "/proposal-mockups/eeco/M14",
      "title": "Move stage / readiness checklist",
      "aliases": [
        "Move stage / pre-incentive readiness checklist"
      ],
      "user": "EECO staff / approver",
      "tor": "5.5.4",
      "brief": "Move-stage dialog with pre-incentive readiness checklist (required items checked).",
      "mustShow": [
        "checklist",
        "confirm move"
      ]
    },
    {
      "id": "M15",
      "section": "A7",
      "path": "/proposal-mockups/eeco/M15",
      "title": "EEC OSS status panel",
      "aliases": [
        "EEC OSS status panel on investment case"
      ],
      "user": "EECO staff",
      "tor": "5.7",
      "brief": "Read-only OSS status panel on a case: last sync time, high-level status chips. Do not invent specific OSS API field names — use generic labels (Status, Last synced, Reference).",
      "mustShow": [
        "last synced",
        "generic status"
      ]
    },
    {
      "id": "M16",
      "section": "A10",
      "path": "/proposal-mockups/eeco/M16",
      "title": "RBAC difference (3 roles)",
      "aliases": [
        "RBAC difference — same case, three roles"
      ],
      "user": "Staff / Manager / Director",
      "tor": "5.8; POC 3",
      "brief": "Same investment case shown under three role tabs (Staff / Manager / Director) with visibly different actions or masked fields.",
      "mustShow": [
        "three role switch",
        "different actions or fields"
      ]
    },
    {
      "id": "M17",
      "section": "A10",
      "path": "/proposal-mockups/eeco/M17",
      "title": "Sensitive doc + watermark",
      "aliases": [
        "Sensitive document viewer with dynamic watermark"
      ],
      "user": "Director / project owner",
      "tor": "5.8.2",
      "brief": "Document viewer with dynamic watermark (user + timestamp overlay).",
      "mustShow": [
        "watermark overlay",
        "document canvas"
      ]
    },
    {
      "id": "M18",
      "section": "A10",
      "path": "/proposal-mockups/eeco/M18",
      "title": "Audit / change-history report",
      "aliases": [
        "Audit / data-change history report"
      ],
      "user": "Manager / admin",
      "tor": "5.8.2; POC 5",
      "brief": "Audit / change-history report table: who, when, object, field, old → new (fake rows).",
      "mustShow": [
        "filterable table",
        "before/after"
      ]
    }
  ]
}
```

## Screens to implement

### M01 — Login / SSO entry

- **Path:** `/proposal-mockups/eeco/M01`
- **Section:** A9
- **User:** EECO named user
- **TOR / POC:** 5.7.1; POC 2
- **Brief:** SSO entry for named EECO users only. Show agency branding, SSO button, and a clear note that access is for authorized staff (no public self-registration).
- **Must show:** SSO CTA; no signup link; Thai labels preferred

### M02 — Executive heat map / dashboard

- **Path:** `/proposal-mockups/eeco/M02`
- **Section:** A8
- **User:** EECO manager / director
- **TOR / POC:** 5.6; POC 2
- **Brief:** Post-login executive dashboard: heat-map style workload / SLA visibility, พ.ศ. or fiscal period filter, drill toward units or officers. Fake aggregates only.
- **Must show:** heat map or workload grid; period filter; SLA / escalation signals

### M03 — Customer 360

- **Path:** `/proposal-mockups/eeco/M03`
- **Section:** A5
- **User:** EECO staff
- **TOR / POC:** 5.5.2
- **Brief:** Single customer 360 for person and juristic profiles: identity summary, related activities, journey stage, consent status. Use fictional company names.
- **Must show:** person vs juristic; linked activities; consent badge

### M04 — Bulk CSV / Excel import

- **Path:** `/proposal-mockups/eeco/M04`
- **Section:** A5
- **User:** EECO staff / data steward
- **TOR / POC:** 5.5.1
- **Brief:** Bulk import wizard: upload CSV/Excel, column mapping, validation errors, commit summary.
- **Must show:** upload; validation errors table; commit summary

### M05 — Consent capture and history

- **Path:** `/proposal-mockups/eeco/M05`
- **Section:** A5
- **User:** EECO staff
- **TOR / POC:** 5.5.2, 5.8.3
- **Brief:** Consent capture form plus chronological consent history for PDPA-aligned operations.
- **Must show:** consent purpose; history timeline

### M06 — Master data admin

- **Path:** `/proposal-mockups/eeco/M06`
- **Section:** A5
- **User:** EECO admin
- **TOR / POC:** 5.5.2
- **Brief:** Admin lists for industry / country (and similar reference data) with active flags.
- **Must show:** reference table; add/edit

### M07 — Activity create / edit (desktop)

- **Path:** `/proposal-mockups/eeco/M07`
- **Section:** A6
- **User:** EECO staff
- **TOR / POC:** 5.5.3; POC 4
- **Brief:** Desktop activity create/edit: customer link, type, datetime, notes, attachments, save.
- **Must show:** customer picker; activity fields; attachments

### M08 — Activity capture (mobile/tablet)

- **Path:** `/proposal-mockups/eeco/M08`
- **Section:** A6
- **User:** EECO field officer
- **TOR / POC:** 5.5.3, 3.2
- **Brief:** Mobile/tablet-friendly activity capture: large tap targets, photo attach, offline-ready cue (demo).
- **Must show:** compact form; photo attach

### M09 — Task and team calendar

- **Path:** `/proposal-mockups/eeco/M09`
- **Section:** A6
- **User:** EECO staff / team lead
- **TOR / POC:** 5.5.3
- **Brief:** Team calendar / task board with due dates and assignees (fake names).
- **Must show:** calendar or agenda; assignee

### M10 — Ticket create / route / SLA

- **Path:** `/proposal-mockups/eeco/M10`
- **Section:** A6
- **User:** EECO staff
- **TOR / POC:** 5.5.3
- **Brief:** Ticket create with routing unit, SLA clock, escalation state.
- **Must show:** route / unit; SLA indicator

### M11 — Activity A4/PDF print preview

- **Path:** `/proposal-mockups/eeco/M11`
- **Section:** A6
- **User:** EECO staff
- **TOR / POC:** POC 4.2
- **Brief:** Print preview of an activity report laid out for A4 / PDF.
- **Must show:** A4-like layout; print/export affordance

### M12 — Investment Journey pipeline board

- **Path:** `/proposal-mockups/eeco/M12`
- **Section:** A7
- **User:** EECO promotion officer / manager
- **TOR / POC:** 5.5.4
- **Brief:** Kanban / pipeline board for Investment Journey stages with card counts and SLA coloring.
- **Must show:** stages as columns; case cards

### M13 — Investment case workspace

- **Path:** `/proposal-mockups/eeco/M13`
- **Section:** A7
- **User:** EECO staff
- **TOR / POC:** 5.5.3–5.5.4, 5.7
- **Brief:** Single investment case workspace: summary, timeline, documents, linked activities, OSS panel slot.
- **Must show:** case header; tabs or sections for timeline/docs

### M14 — Move stage / readiness checklist

- **Path:** `/proposal-mockups/eeco/M14`
- **Section:** A7
- **User:** EECO staff / approver
- **TOR / POC:** 5.5.4
- **Brief:** Move-stage dialog with pre-incentive readiness checklist (required items checked).
- **Must show:** checklist; confirm move

### M15 — EEC OSS status panel

- **Path:** `/proposal-mockups/eeco/M15`
- **Section:** A7
- **User:** EECO staff
- **TOR / POC:** 5.7
- **Brief:** Read-only OSS status panel on a case: last sync time, high-level status chips. Do not invent specific OSS API field names — use generic labels (Status, Last synced, Reference).
- **Must show:** last synced; generic status

### M16 — RBAC difference (3 roles)

- **Path:** `/proposal-mockups/eeco/M16`
- **Section:** A10
- **User:** Staff / Manager / Director
- **TOR / POC:** 5.8; POC 3
- **Brief:** Same investment case shown under three role tabs (Staff / Manager / Director) with visibly different actions or masked fields.
- **Must show:** three role switch; different actions or fields

### M17 — Sensitive doc + watermark

- **Path:** `/proposal-mockups/eeco/M17`
- **Section:** A10
- **User:** Director / project owner
- **TOR / POC:** 5.8.2
- **Brief:** Document viewer with dynamic watermark (user + timestamp overlay).
- **Must show:** watermark overlay; document canvas

### M18 — Audit / change-history report

- **Path:** `/proposal-mockups/eeco/M18`
- **Section:** A10
- **User:** Manager / admin
- **TOR / POC:** 5.8.2; POC 5
- **Brief:** Audit / change-history report table: who, when, object, field, old → new (fake rows).
- **Must show:** filterable table; before/after

## Must avoid (all screens)

Inventing real investor PII; inventing EEC OSS field names; implying public self-registration (internal named users only).
- Fake / invented government crest or seal; Rocket logo used as the buyer agency mark; missing agency logo when branding is supplied.

## Done when

- Every registry path is **proposal-usable** and meets **UI quality principles** above.
- Local: `npm run dev` on port 3001; CRM `mockups:view` shows live iframes in the proposal viewer.
- No follow-up “make it look less like a mockup” pass required.
