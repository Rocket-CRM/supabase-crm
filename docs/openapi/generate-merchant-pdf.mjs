#!/usr/bin/env node
/**
 * Build the merchant Open API PDF from the canonical human spec.
 * Does not rewrite field tables, JSON examples, or curls.
 *
 * Usage (from repo root or this directory):
 *   node docs/openapi/generate-merchant-pdf.mjs
 */
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(HERE, "../..");
const SOURCE_MD = path.join(REPO, "requirements/Open_API.md");
const OPENAPI_YAML = path.join(HERE, "openapi.yaml");
const CSS = path.join(HERE, "merchant-pdf.css");
const OUT_PDF = path.join(HERE, "Rocket-Loyalty-Open-API.pdf");
const CHROME =
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

function die(msg) {
  console.error(msg);
  process.exit(1);
}

function parseOps(yaml) {
  const ops = [];
  let currentPath = null;
  let inPaths = false;
  for (const line of yaml.split("\n")) {
    if (line === "paths:") {
      inPaths = true;
      continue;
    }
    if (inPaths && /^[a-zA-Z]/.test(line)) break;
    const pathMatch = line.match(/^  (\/[^:]+):$/);
    if (pathMatch) {
      currentPath = pathMatch[1];
      continue;
    }
    const methodMatch = line.match(/^    (get|post|put|patch|delete):$/);
    if (methodMatch && currentPath) {
      ops.push({
        method: methodMatch[1].toUpperCase(),
        path: currentPath,
        summary: inferSummary(methodMatch[1].toUpperCase(), currentPath, ""),
      });
      continue;
    }
    const summaryMatch = line.match(/^      summary: (.+)$/);
    if (summaryMatch && ops.length) {
      const last = ops[ops.length - 1];
      last.summary = inferSummary(last.method, last.path, summaryMatch[1].trim());
    }
  }
  return ops;
}

function inferSummary(method, route, yamlSummary) {
  if (yamlSummary) return yamlSummary.replace(/^"|"$/g, "");
  const resource = (route.split("/")[1] || "")
    .replace(/^api-/, "")
    .replace(/s$/, "");
  if (route.endsWith("/cancel")) return "Cancel redemption";
  if (route.endsWith("/mark-used")) return "Mark redemption used";
  const by = route.match(/by-([a-z0-9-]+)\//);
  if (by) {
    const label = by[1].replace(/-/g, " ");
    if (method === "GET") return `Get ${resource} by ${label}`;
    if (method === "PATCH") return `Update ${resource} by ${label}`;
  }
  if (route.includes("{")) {
    if (method === "GET") return `Get ${resource}`;
    if (method === "PATCH") return `Update ${resource}`;
  }
  return "";
}

function extractDate(src) {
  const m = src.match(/Last Updated:\s*([^\n]+)/i);
  return m ? m[1].trim() : "August 20, 2026";
}

function methodClass(method) {
  return `method method-${method.toLowerCase()}`;
}

function buildIndexTable(ops) {
  const rows = ops
    .map((op) => {
      const summary = op.summary ? op.summary.replace(/^"|"$/g, "") : "";
      return `| <span class="${methodClass(op.method)}">${op.method}</span> | \`${op.path}\` | ${summary} |`;
    })
    .join("\n");
  return `## Endpoint index

Lookup aliases (email, phone, LINE, serial, …) are listed as separate paths.

| Method | Path | Summary |
|--------|------|---------|
${rows}
`;
}

function merchantPreamble(date, opCount) {
  return `::: {.cover}
<p class="cover-kicker">Rocket Innovation Co. Ltd</p>
<h1>Open API</h1>
<p class="subtitle">Merchant integration specification — users, assets, purchases, redemptions, wallet</p>

<table class="cover-meta">
<tr><th>Version</th><td>1.0</td></tr>
<tr><th>Date</th><td>${date}</td></tr>
<tr><th>Auth</th><td><code>x-api-key</code> on every request</td></tr>
<tr><th>Operations</th><td>${opCount} HTTP operations</td></tr>
</table>
<p class="cover-url">Base URL<br><code>https://open-api.rocket-loyalty.com/functions/v1</code></p>

<p class="cover-note">Strictly private &amp; confidential. For the merchant named on the covering email or agreement. Do not redistribute. Examples use placeholder identifiers — substitute your own user, reward, SKU, and API key values.</p>
:::

## How to call the API

Mint a key in Rocket Loyalty admin: **Settings → API Keys**. Send JSON on POST/PATCH.

\`\`\`bash
curl 'https://open-api.rocket-loyalty.com/functions/v1/api-users/by-tel/%2B66812345678' \\
  --header 'x-api-key: YOUR_API_KEY'
\`\`\`

Success bodies are \`{ "success": true, "data": { … }, "meta": { "request_id", "response_time_ms" } }\`. Failures use \`success: false\` plus \`code\` / \`error\` (see Error Codes).

**Not in v1:** absolute points or ticket balance SET; store-credit / Shopify credit ticket types; ticket-type catalog create/list; public purchase-cancel.

`;
}

const PURCHASE_GET_PATCH = `
## Retrieve or update a purchase

These routes exist on the gateway. There is no public purchase-cancel in v1. Purchase → points earn may be asynchronous; use wallet POST when you need a synchronous credit.

| Item | Value |
|------|-------|
| Method | \`GET\` |
| URI | \`/api-purchases/{transaction_number}\` |
| Alt | \`/api-purchases?transaction_number=\` or \`?transaction_id=\` |

| Item | Value |
|------|-------|
| Method | \`PATCH\` |
| URI | \`/api-purchases/{transaction_number}\` |
| Content-Type | \`application/json\` |

`;

function prepareBody(src) {
  const start = src.indexOf("## 1. Authentication with API Key");
  if (start < 0) die("requirements/Open_API.md: missing Authentication section");
  let body = src.slice(start);
  body = body.replace(/POSTMAN curl/g, "Example curl");
  const redeemAt = body.indexOf("\n## 11. Redeem Reward");
  if (redeemAt < 0) die("requirements/Open_API.md: missing Redeem Reward section");
  body = body.slice(0, redeemAt) + "\n" + PURCHASE_GET_PATCH + body.slice(redeemAt);
  return body;
}

function run(cmd, args, opts = {}) {
  const r = spawnSync(cmd, args, { encoding: "utf8", ...opts });
  if (r.status !== 0) {
    die(`${cmd} failed (${r.status})\n${r.stderr || r.stdout || ""}`);
  }
  return r;
}

if (!fs.existsSync(SOURCE_MD)) die(`Missing ${SOURCE_MD}`);
if (!fs.existsSync(OPENAPI_YAML)) die(`Missing ${OPENAPI_YAML}`);
if (!fs.existsSync(CSS)) die(`Missing ${CSS}`);
if (!fs.existsSync(CHROME)) die(`Missing Google Chrome at ${CHROME}`);
const pandocCheck = spawnSync("pandoc", ["--version"], { encoding: "utf8" });
if (pandocCheck.status !== 0) die("pandoc is required");

const src = fs.readFileSync(SOURCE_MD, "utf8");
const yaml = fs.readFileSync(OPENAPI_YAML, "utf8");
const ops = parseOps(yaml);
if (ops.length < 20) die(`openapi.yaml parsed too few operations: ${ops.length}`);

const date = extractDate(src);
const md =
  merchantPreamble(date, ops.length) +
  buildIndexTable(ops) +
  "\n---\n\n" +
  prepareBody(src);

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "openapi-merchant-"));
const mdPath = path.join(tmp, "merchant.md");
const htmlPath = path.join(tmp, "merchant.html");
fs.writeFileSync(mdPath, md, "utf8");

run("pandoc", [
  mdPath,
  "--from=markdown+raw_html+fenced_divs",
  "--standalone",
  `--css=${CSS}`,
  "--metadata",
  "pagetitle=Rocket Loyalty Open API",
  "--wrap=none",
  "-o",
  htmlPath,
]);

let html = fs.readFileSync(htmlPath, "utf8");
if (!html.includes("merchant-pdf.css")) {
  html = html.replace(
    "</head>",
    `<link rel="stylesheet" href="${path.basename(CSS)}" />\n</head>`,
  );
}
const htmlOut = path.join(tmp, "print.html");
fs.copyFileSync(CSS, path.join(tmp, "merchant-pdf.css"));
fs.writeFileSync(htmlOut, html, "utf8");

const fileUrl = `file://${htmlOut}`;
run(CHROME, [
  "--headless=new",
  "--disable-gpu",
  "--no-pdf-header-footer",
  `--print-to-pdf=${OUT_PDF}`,
  "--virtual-time-budget=20000",
  fileUrl,
]);

const stat = fs.statSync(OUT_PDF);
console.log(`Wrote ${path.relative(REPO, OUT_PDF)} (${stat.size} bytes, ${ops.length} operations)`);
console.log(`Build dir ${tmp}`);
