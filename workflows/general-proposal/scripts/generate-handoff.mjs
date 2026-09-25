#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { loadRegistry } from "./lib.mjs";

const slug = process.argv[2];
const { runDir, registry } = loadRegistry(slug);

const lines = [];
lines.push(`# Loyalty-admin handoff — ${registry.run}`);
lines.push("");
lines.push("Paste this **entire file** into a single Cursor thread opened on `/Users/rangwan/loyalty-admin` (canonical clone).");
lines.push("");
lines.push("## Task");
lines.push("");
lines.push("Produce **proposal-usable** mockup pages for this bid in **one pass**.");
lines.push("When you finish, CRM preview/capture must be able to show them in the proposal with **no further scaffold or stub pass**.");
lines.push("Do not touch product routes (rewards, CS inbox, etc.).");
lines.push("");
lines.push("### Definition of done (proposal-usable)");
lines.push("");
lines.push("- Every registry path returns 200 with a **realistic product UI** (not wireframe, not TODO, not “scaffold”).");
lines.push("- Screen matches the brief + `mustShow` — credible for a government bid / POC walkthrough at arm’s length.");
lines.push("- Thai UI chrome; static demo data only.");
lines.push("- If files already exist under `/proposal-mockups/" + registry.runKey + "/`, **upgrade or replace** them to this quality — do not leave thin first drafts.");
lines.push("");
lines.push("### UI quality principles (mandatory)");
lines.push("");
lines.push("These are **principles**, not a checklist of specific bugs. Apply across every screen:");
lines.push("");
lines.push("1. **Use the real design system.** Prefer first-class Shopify Polaris components (`DataTable`, `IndexTable`, `Badge`, `Tabs`/`ButtonGroup`, `Banner`, `Page`/`Layout`/`Card`, `FormLayout`, `Filters`, etc.). Do **not** fake tables with stacked divs or plain HTML tables when Polaris has a table pattern.");
lines.push("2. **Enterprise density, not demo wireframe.** Spacing, typography, and hierarchy should look like a shipped admin app an evaluator could believe is production-adjacent.");
lines.push("3. **Alignment and rhythm.** Badges/pills in a row share height, baseline, and gap; headers and actions align on one bar; columns line up. No floating chips with uneven padding.");
lines.push("4. **Status as badges, not raw text** where status is meaningful (active/suspended, SLA, stage, consent).");
lines.push("5. **Print / PDF / document previews must look like documents** — agency header, title block, labeled field grid or definition list with consistent columns, summary section, signature/footer affordances — not a sparse card with five loose lines.");
lines.push("6. **Interactive affordances where the brief implies them** (selection checkboxes if “edit selected” exists; clear primary/secondary actions; filters/tabs that look wired).");
lines.push("7. **Still static data** — polish the chrome and composition; do not call real APIs or invent forbidden fields.");
lines.push("8. **Real government / buyer agency logo** — use the official mark from the registry `branding` block (run asset path and/or URL). Put it in the app chrome (top bar / login) and on print/PDF headers. **Do not** invent a crest, substitute a generic seal, use Rocket’s logo as the agency mark, or omit branding when `branding.logo` is provided. If the logo file/URL is missing, stop and ask — do not fake one.");
lines.push("");
lines.push("### Buyer / agency branding (mandatory for government packs)");
lines.push("");
if (registry.branding) {
  const b = registry.branding;
  lines.push(`- **Agency:** ${b.agencyName || "—"}${b.agencyNameEn ? ` (${b.agencyNameEn})` : ""}`);
  if (b.logo) {
    if (b.logo.runAsset) {
      lines.push(`- **Official logo (run asset):** copy from the CRM run folder \`${registry.run}/${b.logo.runAsset}\` into this admin project (e.g. \`public/proposal-mockups/${registry.runKey}/agency-logo.png\`) and reference that local file in every screen’s chrome / document header.`);
    }
    if (b.logo.url) {
      lines.push(`- **Official logo (URL):** ${b.logo.url} — download once into the mockup public folder; do not hotlink in the final commit if unstable.`);
    }
    if (b.logo.notes) {
      lines.push(`- **Logo notes:** ${b.logo.notes}`);
    }
    if (!b.logo.runAsset && !b.logo.url) {
      lines.push("- **[GAP: official agency logo]** — registry has no `branding.logo.runAsset` or `url`. Obtain the real mark before generating screens; do not invent one.");
    }
  } else {
    lines.push("- **[GAP: branding.logo]** — add the official agency logo to `mockup-registry.json` before generating screens.");
  }
  if (b.mustAvoid) {
    lines.push(`- **Branding must avoid:** ${b.mustAvoid}`);
  }
} else {
  lines.push("- **[GAP: branding]** — for government / agency bids, add a `branding` object to `mockup-registry.json` with `agencyName` and `logo.runAsset` or `logo.url` pointing at the **real** official logo. Do not generate agency chrome with a fake crest.");
}
lines.push("");
lines.push("### Requirements");
lines.push("");
lines.push("1. Routes exactly as in the registry below (Next.js App Router).");
lines.push("2. Shopify Polaris UI at full fidelity (see principles above); Thai chrome; **official agency logo** in chrome per branding block.");
lines.push("3. Static demo data only — invent plausible labels for this bid; **no real investor PII**; **do not invent external-system field names** the pack does not supply; no public self-registration (named internal users only).");
lines.push("4. Keep pages public (no auth) under `/proposal-mockups/` — middleware already allows this prefix.");
lines.push("5. Index at `/proposal-mockups/" + registry.runKey + "` listing all screens.");
lines.push("6. Sync `public/proposal-mockups/" + registry.runKey + "/mockup-manifest.json` with the registry pages.");
lines.push("7. Commit only when the user asks; user may push `main`.");
lines.push("");
lines.push("## Registry (source of truth)");
lines.push("");
lines.push("```json");
lines.push(JSON.stringify(registry, null, 2));
lines.push("```");
lines.push("");
lines.push("## Screens to implement");
lines.push("");

for (const p of registry.pages) {
  lines.push(`### ${p.id} — ${p.title}`);
  lines.push("");
  lines.push(`- **Path:** \`${p.path}\``);
  lines.push(`- **Section:** ${p.section}`);
  lines.push(`- **User:** ${p.user || "—"}`);
  lines.push(`- **TOR / POC:** ${p.tor || "—"}`);
  lines.push(`- **Brief:** ${p.brief}`);
  if (p.mustShow?.length) {
    lines.push(`- **Must show:** ${p.mustShow.join("; ")}`);
  }
  lines.push("");
}

lines.push("## Must avoid (all screens)");
lines.push("");
lines.push(registry.mustAvoid || "Real PII; invented OSS fields; public signup.");
lines.push("- Fake / invented government crest or seal; Rocket logo used as the buyer agency mark; missing agency logo when branding is supplied.");
lines.push("");
lines.push("## Done when");
lines.push("");
lines.push("- Every registry path is **proposal-usable** and meets **UI quality principles** above.");
lines.push("- Local: `npm run dev` on port 3001; CRM `mockups:view` shows live iframes in the proposal viewer.");
lines.push("- No follow-up “make it look less like a mockup” pass required.");
lines.push("");

const out = path.join(runDir, "loyalty-admin-handoff-prompt.md");
fs.writeFileSync(out, lines.join("\n"), "utf8");
console.log(`Wrote ${out}`);
