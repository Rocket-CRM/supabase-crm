# Proposal mockups — mini Deck contract

Same idea as Rocket Deck (`mockup-manifest` → pin ids → resolve live), stripped for general proposals.

## Flow (no scaffold stage)

1. **Write** — sections use `{{mockup:Mxx}}` shortcodes (no ASCII boxes).
2. **Registry** — `runs/<slug>/mockup-registry.json` lists every id → path + brief.
3. **Handoff** — `npm run mockups:handoff -- <slug>` writes `loyalty-admin-handoff-prompt.md`.
4. **Generate once** — paste that file into **one** loyalty-admin thread. Output must be **proposal-usable, realistic product UI** (full Polaris components, aligned chrome, document-quality print previews — see handoff “UI quality principles”). Not wireframes, not stubs, not “scaffold then polish later.”
5. **Review / download (primary)** — small local viewer with **live** mockup iframes:
   ```bash
   # terminal A
   cd ~/Documents/rocket/loyalty-admin && npm run dev   # :3001
   # terminal B
   cd workflows/general-proposal
   ADMIN_ORIGIN=http://localhost:3001 npm run mockups:view -- <slug>
   ```
   Opens `http://127.0.0.1:4177/?run=<slug>`. Admin fix → **Reload** in the viewer (no recapture).
   - Viewer renders **Mermaid** and uses **Sarabun**. Mockup iframes need loyalty-admin `frame-ancestors` to include `http://127.0.0.1:4177` (wired in admin `next.config.ts`).
   - **Download HTML** — offline-ish HTML that still points iframes at `ADMIN_ORIGIN` (admin must be reachable to see screens).
   - **Print / PDF** — browser print (Save as PDF). Page breaks: new page at each body `h1` chapter, each mockup, and each `{{diagram:…}}`; Mermaid stays in-flow but unsplit. Screen keeps live iframes; **print always uses `assets/Mxx.png`** (cross-origin iframes blank in print — same reason Rocket Deck screenshots / freezes mockups instead of printing iframes). Diagram shortcodes show an outer figcaption from `diagrams/<id>/data.<lang>.json` `title`.

6. **Optional offline snapshots** (not the review path):
   `npm run mockups:capture` → `npm run mockups:embed` writes PNGs into `proposal.md` for packs that cannot load admin.

If a page already exists at that path, the admin thread **replaces/upgrades** it to proposal quality — there is no separate scaffold step in the workflow.

## Registry shape

```json
{
  "version": 1,
  "run": "eeco-crm-202608",
  "runKey": "eeco",
  "origin": "loyalty-admin",
  "defaultOriginUrl": "http://localhost:3001",
  "branding": {
    "agencyName": "สกพอ.",
    "agencyNameEn": "Eastern Economic Corridor Office",
    "logo": {
      "runAsset": "assets/agency-logo.png",
      "url": null,
      "notes": "Official agency mark only"
    },
    "mustAvoid": "Invented crest; Rocket logo as agency mark"
  },
  "mustAvoid": "…",
  "pages": [
    {
      "id": "M02",
      "path": "/proposal-mockups/eeco/M02",
      "title": "…",
      "brief": "…",
      "mustShow": ["…"]
    }
  ]
}
```

- `runKey` — URL segment under `/proposal-mockups/`.
- **`branding` (required for government / agency bids)** — `agencyName` plus official logo via `logo.runAsset` (path under the run folder, preferred) and/or `logo.url`. Place the real mark in `runs/<slug>/assets/` before handoff. The generated FE prompt **requires** that logo in app chrome and print headers — no invented crest, no Rocket mark as the agency logo. If missing → `[GAP]` and do not fake one.
- `run` — folder name under `runs/`.
- `path` — must match loyalty-admin route; do not invent at compile time.

## Shortcode

In section markdown (and compiled `proposal.md`):

```md
{{mockup:M02}}
```

Optional caption stays in surrounding prose, not inside the shortcode.

## Loyalty-admin rules

- Namespace: `/proposal-mockups/<runKey>/…` only — never product routes.
- Public (no auth) so preview/capture can load without deck-embed tokens.
- Static / fake data only; no real investor PII; no invented OSS field names unless TOR supplies them.
- Prefer Thai UI chrome when POC will show the screens.
- **Use the real buyer / government agency logo** from `branding` on every screen’s chrome and on print/PDF headers. Never invent a crest or substitute Rocket’s logo.
- Optional: publish `public/proposal-mockups/<runKey>/mockup-manifest.json` mirroring the registry pages (Deck-shaped subset).

## Scripts (from `workflows/general-proposal/`)

```bash
npm run mockups:handoff -- eeco-crm-202608
npm run mockups:preview -- eeco-crm-202608
ADMIN_ORIGIN=http://localhost:3001 npm run mockups:capture -- eeco-crm-202608
```

Env: `ADMIN_ORIGIN` overrides `defaultOriginUrl` (default `http://localhost:3001`).

## What this is not

- Not Rocket Deck composer / ThemePack / loyalty-app manifests.
- Not HMAC `/api/deck-embed` (bid sandbox is public).
- Not a new orchestrator git repo — contract lives in this workflow + admin sandbox routes.
