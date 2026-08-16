#!/usr/bin/env node
/**
 * Assemble FEATURES_SUMMARY.md from SQL group rows:
 * [{ module_name, module_sort, feature_group_key, group_name, group_sort, body }]
 */
import fs from "node:fs";
import path from "node:path";

const args = process.argv.slice(2);
let fromJson = null;
let output = null;
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--from-json") fromJson = args[++i];
  else if (args[i] === "--output") output = args[++i];
}
if (!fromJson || !output) {
  console.error("Need --from-json and --output");
  process.exit(1);
}

const rows = JSON.parse(fs.readFileSync(path.resolve(fromJson), "utf8"));
rows.sort((a, b) => a.module_sort - b.module_sort || a.group_sort - b.group_sort);

const parts = [
  `# Features Summary`,
  ``,
  `Canonical feature-group summary for Rocket CRM. Derived from the Product Feature Catalog — **full coverage** for RFP / competitor compare.`,
  ``,
  `**Contract:** \`workflows/canonical-views/REFERENCE.md\`  `,
  `**Language:** EN  `,
  `**Companion:** [Commercial Pricing Sheet](./COMMERCIAL_PRICING_SHEET.md) (billable units; sparse by design)`,
  ``,
  `Each bullet is one catalog feature: **name** + full sales summary (+ \`includes\` clarifiers when present). Do not collapse to name-only lines.`,
  ``,
];

let lastModule = null;
for (const g of rows) {
  if (g.module_name !== lastModule) {
    parts.push(`---`, ``, `## ${g.module_name}`, ``);
    lastModule = g.module_name;
  }
  parts.push(
    `### ${g.group_name} (\`${g.feature_group_key}\`)`,
    ``,
    `| Feature group | Capabilities |`,
    `| --- | --- |`,
    `| ${g.group_name} | (see bullets) |`,
    ``,
    g.body.replace(/\\n/g, "\n"),
    ``,
  );
}

const out = path.resolve(output);
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, parts.join("\n").replace(/\n{3,}/g, "\n\n") + "\n", "utf8");
console.log(`Wrote ${out} (${rows.length} groups)`);
