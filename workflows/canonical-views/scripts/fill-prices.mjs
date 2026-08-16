#!/usr/bin/env node
/**
 * Fill Canonical View pricing-sheet Price cells from list-prices.json.
 *
 * Unit stays the billing period written in the markdown (month, receipt, seat).
 * Scale only selects the amount — it is not a Unit label.
 * {{sms_included}} and other vars[scale] tokens are substituted in the block.
 *
 *   node scripts/fill-prices.mjs \
 *     --input runs/x/pricing-sheet.md --output runs/x/pricing-sheet.md \
 *     --scale 10000 --lang th
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const defaultBook = path.join(here, "..", "list-prices.json");

function die(msg) {
  console.error(msg);
  process.exit(1);
}

function parseArgs(argv) {
  const out = {
    input: null,
    output: null,
    scale: null,
    lang: "en",
    book: defaultBook,
  };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    const next = argv[i + 1];
    const take = () => {
      if (!next) die(`Missing value for ${a}`);
      i += 1;
      return next;
    };
    if (a === "--input") out.input = take();
    else if (a === "--output") out.output = take();
    else if (a === "--scale") out.scale = take();
    else if (a === "--lang") out.lang = take();
    else if (a === "--book") out.book = take();
    else if (a === "--help" || a === "-h") out.help = true;
    else die(`Unknown arg: ${a}`);
  }
  return out;
}

function formatAmount(n) {
  if (Number.isInteger(n)) return n.toLocaleString("en-US");
  return n.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function resolveFill(spec, scale, lang) {
  const billingUnit = lang === "th" ? spec.billing_unit_th : spec.billing_unit_en;
  const enquire = lang === "th" ? "สอบถาม" : "Enquire";
  const free = lang === "th" ? "ฟรี" : "Free";
  const vars = {};
  if (spec.vars) {
    for (const [name, byScale] of Object.entries(spec.vars)) {
      const v = byScale[String(scale)];
      if (v == null) die(`No ${name} for scale ${scale}`);
      vars[name] = formatAmount(v);
    }
  }

  if (spec.charge === "enquire") {
    return { billingUnit, price: enquire, vars };
  }
  if (spec.charge === "free") {
    return { billingUnit, price: free, vars };
  }
  if (spec.by_scale) {
    const amount = spec.by_scale[String(scale)];
    if (amount == null) die(`No list price for scale ${scale}`);
    return { billingUnit, price: formatAmount(amount), vars };
  }
  if (spec.unit_price_min != null && spec.unit_price_max != null) {
    return {
      billingUnit,
      price: `${formatAmount(spec.unit_price_min)}–${formatAmount(spec.unit_price_max)}`,
      vars,
    };
  }
  if (spec.unit_price != null) {
    return { billingUnit, price: formatAmount(spec.unit_price), vars };
  }
  return { billingUnit, price: enquire, vars };
}

function applyVars(text, vars) {
  return text.replace(/\{\{(\w+)\}\}/g, (m, name) =>
    Object.hasOwn(vars, name) ? vars[name] : m,
  );
}

function replacePriceRow(block, billingUnit, price) {
  const lines = block.split("\n");
  let replaced = false;
  const out = lines.map((line) => {
    if (replaced) return line;
    if (!line.startsWith("|")) return line;
    if (/^\|\s*Feature\s*\|/i.test(line)) return line;
    if (/^\|\s*-+/.test(line)) return line;
    const cells = line.split("|").slice(1, -1).map((c) => c.trim());
    if (cells.length < 3) return line;
    replaced = true;
    return `| ${cells[0]} | ${billingUnit} | ${price} |`;
  });
  if (!replaced) die("No Feature/Unit/Price data row found under a billable unit");
  return out.join("\n");
}

function fillMarkdown(md, book, scale, lang) {
  const scales = book.scales.map(String);
  if (!scales.includes(String(scale))) {
    die(`Scale must be one of ${scales.join(", ")}. Got ${scale}`);
  }

  const lines = md.split("\n");
  const out = [];
  let pending = null;
  let buf = [];

  const flush = () => {
    if (!pending) {
      out.push(...buf);
      buf = [];
      return;
    }
    const spec = book.units[pending.key];
    const block = buf.join("\n");
    if (!spec) {
      out.push(pending.heading, block);
    } else {
      const { billingUnit, price, vars } = resolveFill(spec, scale, lang);
      out.push(pending.heading, applyVars(replacePriceRow(block, billingUnit, price), vars));
    }
    pending = null;
    buf = [];
  };

  for (const line of lines) {
    const h3 = line.match(/^### .+ \(`([a-z0-9_]+)`\)$/);
    if (h3) {
      flush();
      pending = { heading: line, key: h3[1] };
      continue;
    }
    if (pending && /^## /.test(line)) {
      flush();
      out.push(line);
      continue;
    }
    if (pending) buf.push(line);
    else out.push(line);
  }
  flush();
  return out.join("\n");
}

function main() {
  const args = parseArgs(process.argv);
  if (args.help) {
    console.log(`Usage: node fill-prices.mjs --input <md> --output <md> --scale <n> [--lang en|th]`);
    process.exit(0);
  }
  if (!args.input || !args.output || !args.scale) {
    die("Required: --input --output --scale");
  }
  if (args.lang !== "en" && args.lang !== "th") die("--lang must be en or th");

  const book = JSON.parse(fs.readFileSync(args.book, "utf8"));
  const input = fs.readFileSync(args.input, "utf8");
  const filled = fillMarkdown(input, book, args.scale, args.lang);
  fs.mkdirSync(path.dirname(args.output), { recursive: true });
  fs.writeFileSync(args.output, filled);
  console.log(`Filled ${args.output} at scale ${args.scale} (${args.lang})`);
}

main();
