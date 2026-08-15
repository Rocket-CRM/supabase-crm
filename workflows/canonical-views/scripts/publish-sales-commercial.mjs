#!/usr/bin/env node
/**
 * Copy canonical-view baselines + list-prices + export scripts into
 * rocket-sales/commercial/ (published snapshot, not SoT).
 *
 * Default dest: <repo>/../rocket-agent-plugins/plugins/rocket-sales/commercial
 * Override: SALES_PLUGIN_COMMERCIAL=/absolute/path
 */

import { promises as fs } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, "../../..");
const destRoot =
  process.env.SALES_PLUGIN_COMMERCIAL ||
  path.resolve(
    repoRoot,
    "../rocket-agent-plugins/plugins/rocket-sales/commercial"
  );

const copies = [
  ["docs/canonical-views/COMMERCIAL_PRICING_SHEET.md", "COMMERCIAL_PRICING_SHEET.md"],
  ["docs/canonical-views/FEATURES_SUMMARY.md", "FEATURES_SUMMARY.md"],
  ["docs/canonical-views/th/COMMERCIAL_PRICING_SHEET.md", "th/COMMERCIAL_PRICING_SHEET.md"],
  ["docs/canonical-views/th/FEATURES_SUMMARY.md", "th/FEATURES_SUMMARY.md"],
  ["workflows/canonical-views/list-prices.json", "list-prices.json"],
  ["workflows/canonical-views/scripts/fill-prices.mjs", "scripts/fill-prices.mjs"],
  ["workflows/canonical-views/scripts/md-to-pricing-html.mjs", "scripts/md-to-pricing-html.mjs"],
  ["workflows/canonical-views/package.json", "package.json"],
];

async function copyOne(fromRel, toRel) {
  const from = path.join(repoRoot, fromRel);
  const to = path.join(destRoot, toRel);
  try {
    await fs.access(from);
  } catch {
    console.warn(`skip missing ${fromRel}`);
    return;
  }
  await fs.mkdir(path.dirname(to), { recursive: true });
  await fs.copyFile(from, to);
  console.log(`${fromRel} → ${toRel}`);
}

const readme = `Published copy from supabase-crm. Do not edit.
SoT: docs/canonical-views/ and workflows/canonical-views/
Refresh: from supabase-crm run
  node workflows/canonical-views/scripts/publish-sales-commercial.mjs
then push rocket-agent-plugins; sales replace their plugin folder.
`;

await fs.mkdir(destRoot, { recursive: true });
for (const [fromRel, toRel] of copies) {
  await copyOne(fromRel, toRel);
}
await fs.writeFile(path.join(destRoot, "README.md"), readme);
console.log(`Wrote ${destRoot}`);
