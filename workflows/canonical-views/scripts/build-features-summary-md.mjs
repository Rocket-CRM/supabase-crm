#!/usr/bin/env node
/**
 * Coverage inventory helper — NOT the published features-summary voice.
 *
 * Canonical Views copy is written (see workflows/canonical-views/REFERENCE.md
 * and Writing Principles/CANONICAL_VIEW_COPY_PRINCIPLES.md). Use this script
 * to dump keys/names for a coverage diff. Do not overwrite
 * docs/canonical-views/FEATURES_SUMMARY.md with its output.
 */

import fs from "node:fs";
import path from "node:path";

function die(msg) {
  console.error(msg);
  process.exit(1);
}

function parseArgs(argv) {
  const out = { fromJson: null, output: null, lang: "en" };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    const next = argv[i + 1];
    if (a === "--from-json" && next) {
      out.fromJson = next;
      i++;
    } else if (a === "--output" && next) {
      out.output = next;
      i++;
    } else if (a === "--lang" && next) {
      out.lang = next.toLowerCase();
      i++;
    } else die(`Unknown/missing arg: ${a}`);
  }
  if (out.lang !== "en" && out.lang !== "th") {
    die(`--lang must be en or th (got ${out.lang})`);
  }
  return out;
}

function escapeMd(s) {
  return String(s).replace(/\r\n/g, "\n").trim();
}

function renderFeature(f) {
  const statusNote =
    f.status === "beta" || f.status === "planned" ? ` _(${f.status})_` : "";
  const lines = [
    `- **${escapeMd(f.feature_name)}**${statusNote}`,
    `  ${escapeMd(f.summary)}`,
  ];
  const includes = Array.isArray(f.includes) ? f.includes : [];
  for (const inc of includes) {
    lines.push(`  - ${escapeMd(inc)}`);
  }
  return lines.join("\n");
}

function buildMarkdown(rows, lang = "en") {
  const langLabel = lang === "th" ? "TH" : "EN";
  const intro =
    lang === "th"
      ? `สรุปรายการฟีเจอร์ตามกลุ่มของ Rocket CRM จาก Product Feature Catalog — **ครบทุกฟีเจอร์ที่ใช้งานอยู่** สำหรับ RFP / เทียบคู่แข่ง

**Contract:** \`workflows/canonical-views/REFERENCE.md\`  
**Language:** ${langLabel}  
**Companion:** [Commercial Pricing Sheet](./COMMERCIAL_PRICING_SHEET.md) (billable units; sparse by design)

แต่ละ bullet = หนึ่งฟีเจอร์จาก catalog: **ชื่อ** + สรุปเต็ม (+ \`includes\` เมื่อมี — includes ยังเป็นภาษาอังกฤษตาม catalog). Module / feature group หัวข้อคงเป็นอังกฤษ

`
      : `Canonical feature-group summary for Rocket CRM. Derived from the Product Feature Catalog — **full coverage** for RFP / competitor compare.

**Contract:** \`workflows/canonical-views/REFERENCE.md\`  
**Language:** ${langLabel}  
**Companion:** [Commercial Pricing Sheet](./COMMERCIAL_PRICING_SHEET.md) (billable units; sparse by design)

Each bullet is one catalog feature: **name** + full sales summary (+ \`includes\` clarifiers when present). Do not collapse to name-only lines. Names and summaries must already pass \`Writing Principles/SALES_FEATURE_COPY_PRINCIPLES.md\` \u2014 if a line is config jargon, fix the catalog, then rebuild.

`;
  const header = `# Features Summary

${intro}`;

  // Group by module then feature group
  const modules = new Map();
  for (const r of rows) {
    if (!modules.has(r.module_name)) {
      modules.set(r.module_name, {
        sort: r.module_sort,
        groups: new Map(),
      });
    }
    const mod = modules.get(r.module_name);
    const gk = r.feature_group_key;
    if (!mod.groups.has(gk)) {
      mod.groups.set(gk, {
        name: r.group_name,
        key: gk,
        sort: r.group_sort,
        features: [],
      });
    }
    mod.groups.get(gk).features.push(r);
  }

  const parts = [header];
  const modEntries = [...modules.entries()].sort((a, b) => a[1].sort - b[1].sort);
  for (const [modName, mod] of modEntries) {
    parts.push(`---\n\n## ${modName}\n`);
    const groups = [...mod.groups.values()].sort((a, b) => a.sort - b.sort);
    for (const g of groups) {
      g.features.sort((a, b) => a.sort_order - b.sort_order);
      parts.push(`### ${g.name} (\`${g.key}\`)\n`);
      parts.push(`| Feature group | Capabilities |`);
      parts.push(`| --- | --- |`);
      parts.push(`| ${g.name} | (see bullets) |\n`);
      for (const f of g.features) {
        parts.push(renderFeature(f));
      }
      parts.push("");
    }
  }
  return parts.join("\n").replace(/\n{3,}/g, "\n\n") + "\n";
}

function main() {
  const args = parseArgs(process.argv);
  if (!args.fromJson || !args.output) {
    die("Need --from-json and --output");
  }
  const raw = JSON.parse(fs.readFileSync(path.resolve(args.fromJson), "utf8"));
  const rows = Array.isArray(raw) ? raw : raw.data;
  if (!Array.isArray(rows)) die("JSON must be an array or { data: [] }");
  const md = buildMarkdown(rows, args.lang);
  const out = path.resolve(args.output);
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, md, "utf8");
  console.log(`Wrote ${out} (${rows.length} features)`);
}

main();
