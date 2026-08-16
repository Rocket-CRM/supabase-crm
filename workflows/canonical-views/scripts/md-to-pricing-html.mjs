#!/usr/bin/env node
/**
 * Deterministic Canonical View MD → Rocket Deck Merz-style pricing HTML.
 *
 * Visual + structure contract from:
 *   /Users/rangwan/rocket-deck/src/slides/merz-pricing.tsx
 *   /Users/rangwan/rocket-deck/src/slides/verasu-pricing.tsx
 *   /Users/rangwan/rocket-deck/src/components/ui/slide-cn/slide.tsx (A4, rails, meta)
 *   /Users/rangwan/rocket-deck/src/app/globals.css (--slide-*, typ-*)
 *
 * Pricing mode: one ModuleBlock per H2 module; Feature/Unit/Price/Qty/Total table
 * has one row per H3 billable unit (plan grouping and/or fee model).
 * Checklist mode: one ModuleBlock per H2 module; Feature group/Capabilities table
 * has one row per H3 feature group.
 *
 * Usage:
 *   node workflows/canonical-views/scripts/md-to-pricing-html.mjs \
 *     --input docs/canonical-views/COMMERCIAL_PRICING_SHEET.md \
 *     --output docs/canonical-views/export/commercial-pricing-sheet.html
 */

import fs from "node:fs";
import path from "node:path";

/** A4 portrait at Merz deck density (SLIDE_A4_W × SLIDE_A4_H). */
const SLIDE_A4_W = 1080;
const SLIDE_A4_H = Math.round((1080 * 297) / 210); // 1527

function die(msg) {
  console.error(msg);
  process.exit(1);
}

/** Contract length applied to every pricing line item (qty × unit price). */
const CONTRACT_MONTHS = 12;

function parseArgs(argv) {
  const out = {
    input: null,
    output: null,
    title: null,
    meta: null,
    mode: "auto",
    footnotes: [],
    date: null,
    product: "ROCKET CRM",
    /** Meta-bar RHS label (doc type), e.g. "PRICING SHEET" / "FEATURES SUMMARY" */
    docLabel: null,
    /** en | th — footnotes, headers, defaults */
    lang: null,
  };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    const next = argv[i + 1];
    const take = () => {
      if (!next) die(`Missing value for ${a}`);
      i++;
      return next;
    };
    if (a === "--input") out.input = take();
    else if (a === "--output") out.output = take();
    else if (a === "--title") out.title = take();
    else if (a === "--meta") out.meta = take();
    else if (a === "--mode") out.mode = take();
    else if (a === "--date") out.date = take();
    else if (a === "--product") out.product = take();
    else if (a === "--doc-label" || a === "--company") out.docLabel = take();
    else if (a === "--lang") {
      const v = take().toLowerCase();
      if (v !== "en" && v !== "th") die(`--lang must be en or th (got ${v})`);
      out.lang = v;
    } else if (a === "--footnotes") {
      out.footnotes = take()
        .split("|")
        .map((s) => s.trim())
        .filter(Boolean);
    } else if (a === "--help" || a === "-h") out.help = true;
    else die(`Unknown arg: ${a}`);
  }
  return out;
}

function detectLang({ lang, md, title, inputPath }) {
  if (lang === "en" || lang === "th") return lang;
  if (/^\*\*Language:\*\*\s*TH\b/m.test(md) || /\*\*Language:\*\*\s*TH\b/m.test(md))
    return "th";
  if (/Language:\s*TH\b/i.test(md)) return "th";
  if (/[\u0E00-\u0E7F]/.test(title || "")) return "th";
  if (/\/th\/|[-_]th\b/i.test(inputPath || "")) return "th";
  return "en";
}

function uiCopy(lang) {
  if (lang === "th") {
    return {
      feature: "รายการ",
      group: "กลุ่มฟีเจอร์",
      unit: "หน่วย",
      price: "ราคา",
      qty: "จำนวน",
      total: "รวม",
      caps: "ความสามารถ",
      metaPricing: "บาท · ไม่รวม VAT",
      free: "ฟรี",
      enquire: "สอบถาม",
      docLabelPricing: "ใบสรุปราคา",
      docLabelFeatures: "สรุปฟีเจอร์",
      titlePricing: "ใบสรุปราคา",
      titleFeatures: "สรุปฟีเจอร์",
    };
  }
  return {
    feature: "Feature",
    group: "Feature group",
    unit: "Unit",
    price: "Price",
    qty: "Qty",
    total: "Total",
    caps: "Capabilities",
    metaPricing: "THB · excl. VAT",
    free: "Free",
    enquire: "Enquire",
    docLabelPricing: "PRICING SHEET",
    docLabelFeatures: "FEATURES SUMMARY",
    titlePricing: "Pricing sheet",
    titleFeatures: "Features summary",
  };
}

function parseMoney(price) {
  const p = String(price ?? "").trim();
  if (!p || p === "—") return { kind: "blank" };
  if (/^(free|ฟรี)$/i.test(p)) return { kind: "free" };
  if (/^(enquire|สอบถาม)/i.test(p)) return { kind: "enquire" };
  const n = Number(p.replace(/,/g, ""));
  if (Number.isFinite(n)) return { kind: "number", value: n };
  return { kind: "raw", value: p };
}

function formatMoney(n) {
  return n.toLocaleString("en-US");
}

function lineQtyTotal(price, lang) {
  const ui = uiCopy(lang);
  const qty = String(CONTRACT_MONTHS);
  const parsed = parseMoney(price);
  if (parsed.kind === "number") {
    return { qty, total: formatMoney(parsed.value * CONTRACT_MONTHS) };
  }
  if (parsed.kind === "free") return { qty, total: ui.free };
  if (parsed.kind === "enquire") return { qty, total: ui.enquire };
  if (parsed.kind === "blank") return { qty, total: "" };
  return { qty, total: parsed.value };
}

function defaultFootnotes(mode, lang) {
  if (lang === "th") {
    return mode === "pricing"
      ? [
          "ไม่ใช่รายการฟีเจอร์ครบทุกตัว — ดูสรุปฟีเจอร์สำหรับรายละเอียด coverage",
          "สัญญาขั้นต่ำ 12 เดือน และชำระล่วงหน้า",
          "เอกสารลับและเป็นความลับ",
        ]
      : [
          "สรุปฟีเจอร์จาก Product Feature Catalog — ยืนยันรายการ planned/beta ก่อน commit",
          "เอกสารลับและเป็นความลับ",
        ];
  }
  return mode === "pricing"
    ? [
        "Not an exhaustive feature list; see Features Summary for coverage detail.",
        "12-month minimum contract period with upfront payment.",
        "Private & confidential.",
      ]
    : [
        "Features Summary derived from the Product Feature Catalog; confirm planned/beta items before committing.",
        "Private & confidential.",
      ];
}

function escapeHtml(s) {
  return String(s)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function cellText(raw) {
  return raw
    .trim()
    .replace(/^\*\*(.+)\*\*$/, "$1")
    .replace(/`([^`]+)`/g, "$1")
    .trim();
}

function defaultDateLabel() {
  return new Date()
    .toLocaleString("en-US", { month: "long", year: "numeric" })
    .toUpperCase();
}

/**
 * Merz module caption: "Loyalty — Core" from module H2 + feature name.
 */
function blockLabel(moduleName, featureName) {
  const m = moduleName.trim();
  let f = featureName.trim();
  if (!m) return f;
  if (!f) return m;
  // Already "Marketing Automation — Workflows"
  if (/[—–-]/.test(f) && f.toLowerCase().startsWith(m.toLowerCase())) return f;
  const prefix = m.toLowerCase() + " ";
  if (f.toLowerCase().startsWith(prefix)) {
    f = f.slice(m.length).trim();
  }
  return `${m} — ${f}`;
}

function parseCanonicalMd(md) {
  const lines = md.replace(/\r\n/g, "\n").split("\n");
  let title = "";
  const modules = [];
  let module = null;
  let row = null;
  let inTable = false;
  let tableHeaders = null;
  let sawSeparator = false;

  function finishRow() {
    if (row && module) {
      if (row._rich) {
        row.bullets.push(row._rich);
        row._rich = null;
      }
      delete row._rich;
      module.rows.push(row);
      row = null;
    }
  }

  function finishModule() {
    finishRow();
    if (module) {
      modules.push(module);
      module = null;
    }
  }

  for (const line of lines) {
    const h1 = line.match(/^#\s+(.+)$/);
    const h2 = line.match(/^##\s+(.+)$/);
    const h3 = line.match(/^###\s+(.+)$/);

    if (h1) {
      if (!title) title = h1[1].trim();
      continue;
    }
    if (h2) {
      finishModule();
      module = { label: h2[1].trim(), rows: [] };
      inTable = false;
      tableHeaders = null;
      sawSeparator = false;
      continue;
    }
    if (h3) {
      if (!module) module = { label: "General", rows: [] };
      finishRow();
      const heading = h3[1].trim();
      const keyMatch = heading.match(/^(.*?)\s*\(`([^`]+)`\)\s*$/);
      row = {
        key: keyMatch ? keyMatch[2] : null,
        feature: keyMatch ? keyMatch[1].trim() : heading,
        unit: "",
        price: "",
        bullets: [], // pricing: string[]; checklist: {name, summary, includes[]}[]
        notes: [], // italic PS / unit-definition lines — not feature bullets
        _rich: null, // in-progress checklist feature
      };
      inTable = false;
      tableHeaders = null;
      sawSeparator = false;
      continue;
    }

    if (!module || !row) continue;

    if (line.trim().startsWith("|")) {
      const cells = line
        .trim()
        .replace(/^\|/, "")
        .replace(/\|$/, "")
        .split("|")
        .map((c) => c.trim());

      if (cells.every((c) => /^:?-{3,}:?$/.test(c))) {
        sawSeparator = true;
        inTable = true;
        continue;
      }

      if (!sawSeparator && !inTable) {
        tableHeaders = cells.map((c) => cellText(c).toLowerCase());
        continue;
      }

      const featureIdx = tableHeaders
        ? tableHeaders.findIndex((h) => h.includes("feature"))
        : 0;
      const unitIdx = tableHeaders
        ? tableHeaders.findIndex((h) => h === "unit" || h.includes("unit"))
        : 1;
      const priceIdx = tableHeaders
        ? tableHeaders.findIndex((h) => h.includes("price"))
        : 2;

      const f = featureIdx >= 0 ? cellText(cells[featureIdx] ?? "") : "";
      if (f && f.toLowerCase() !== "(see bullets)") row.feature = f;
      if (unitIdx >= 0 && cells[unitIdx] != null) {
        const u = cellText(cells[unitIdx]);
        if (u && u.toLowerCase() !== "(see bullets)") row.unit = u;
      }
      if (priceIdx >= 0 && cells[priceIdx] != null) {
        row.price = cellText(cells[priceIdx]);
      }
      inTable = true;
      continue;
    }

    // Italic note / PS (whole line *…*) — not a feature bullet
    const note = line.match(/^\*(?!\*)(.+?)\*\s*$/);
    if (note) {
      row.notes.push(note[1].trim());
      continue;
    }

    // Nested include under a rich checklist feature: "  - clarifier"
    const nested = line.match(/^(\s{2,})[-*]\s+(.+)$/);
    if (nested && row._rich) {
      row._rich.includes.push(nested[2].trim());
      continue;
    }

    // Top-level bullet
    const bullet = line.match(/^[-*]\s+(.+)$/);
    if (bullet) {
      const raw = bullet[1].trim();
      const bold = raw.match(/^\*\*(.+?)\*\*(.*)$/);
      if (bold) {
        if (row._rich) row.bullets.push(row._rich);
        row._rich = {
          name: bold[1].trim(),
          summary: bold[2].replace(/^[:\s—–-]+/, "").trim(),
          includes: [],
        };
      } else if (row._rich) {
        // Plain bullet after rich mode — treat as new simple/rich name-only
        row.bullets.push(row._rich);
        row._rich = { name: raw.replace(/\*\*/g, ""), summary: "", includes: [] };
      } else {
        row.bullets.push(raw);
      }
      continue;
    }

    // Continuation summary line (indented, not a bullet) under rich feature
    const cont = line.match(/^\s{2,}(\S.*)$/);
    if (cont && row._rich) {
      const t = cont[1].trim();
      row._rich.summary = row._rich.summary
        ? `${row._rich.summary} ${t}`
        : t;
      continue;
    }
  }

  finishModule();
  return { title, modules };
}

function detectMode(md, forced) {
  if (forced === "pricing" || forced === "checklist") return forced;
  if (/\|\s*Feature group\s*\|/i.test(md)) return "checklist";
  if (/\|\s*Feature\s*\|\s*Unit\s*\|\s*Price\s*\|/i.test(md)) return "pricing";
  return "pricing";
}

function stripMdBold(s) {
  return String(s).replace(/\*\*/g, "").trim();
}

/** Pricing: short · lines. Checklist: name + summary + nested includes. */
function includeList(bullets, { rich = false } = {}) {
  if (!bullets.length) return "";
  if (!rich) {
    return `<ul class="includes">${bullets
      .map((b) => {
        if (typeof b === "string") {
          const m = b.match(/^\*\*(.+?)\*\*\s*(.*)$/);
          if (m) {
            const rest = m[2].trim();
            return `<li><span class="include-line">· <strong class="include-keyword">${escapeHtml(m[1].trim())}</strong>${rest ? " " + escapeHtml(rest) : ""}</span></li>`;
          }
          return `<li><span class="include-line">· ${escapeHtml(stripMdBold(b))}</span></li>`;
        }
        const rest = (b.summary || "").trim();
        return `<li><span class="include-line">· <strong class="include-keyword">${escapeHtml(b.name)}</strong>${rest ? " " + escapeHtml(rest) : ""}</span></li>`;
      })
      .join("")}</ul>`;
  }
  return `<ul class="feature-list">${bullets
    .map((b) => {
      if (typeof b === "string") {
        return `<li class="feature-item"><div class="feature-item-name">${escapeHtml(stripMdBold(b))}</div></li>`;
      }
      const includes =
        b.includes?.length > 0
          ? `<ul class="feature-includes">${b.includes
              .map(
                (i) =>
                  `<li><span class="include-line">· ${escapeHtml(i)}</span></li>`,
              )
              .join("")}</ul>`
          : "";
      const summary = b.summary
        ? `<div class="feature-item-summary">${escapeHtml(b.summary)}</div>`
        : "";
      return `<li class="feature-item">
        <div class="feature-item-name">${escapeHtml(b.name)}</div>
        ${summary}
        ${includes}
      </li>`;
    })
    .join("")}</ul>`;
}

function noteList(notes) {
  if (!notes?.length) return "";
  return notes
    .map((n) => `<p class="row-note"><em>${escapeHtml(n)}</em></p>`)
    .join("");
}

function pricingRow({ feature, unit, price, bullets, notes, detail, qty, total }) {
  const priceHtml =
    price && price !== "—"
      ? `<div class="price-val">${escapeHtml(price)}</div>`
      : ""; // Merz leaves price empty when blank / banded

  const qtyHtml = qty
    ? `<div class="qty-val">${escapeHtml(qty)}</div>`
    : "";
  const totalHtml =
    total && total !== "—"
      ? `<div class="total-val">${escapeHtml(total)}</div>`
      : "";

  const detailHtml = detail
    ? `<div class="feature-detail">${escapeHtml(detail)}</div>`
    : "";

  return `<tr>
      <th scope="row" class="cell feature">
        <div class="feature-stack">
          <div class="feature-name">${escapeHtml(feature)}</div>
          ${detailHtml}
          ${includeList(bullets)}
          ${noteList(notes)}
        </div>
      </th>
      <td class="cell unit">
        <div class="unit-stack">
          <div class="unit-name">${escapeHtml(unit || "")}</div>
        </div>
      </td>
      <td class="cell price">${priceHtml}</td>
      <td class="cell qty">${qtyHtml}</td>
      <td class="cell total">${totalHtml}</td>
    </tr>`;
}

function pricingTable({ rows, headers }) {
  return `<table class="pricing-table">
  <thead>
    <tr>
      <th class="col-feature"><span class="col-header">${escapeHtml(headers.feature)}</span></th>
      <th class="col-unit"><span class="col-header">${escapeHtml(headers.unit)}</span></th>
      <th class="col-price"><span class="col-header">${escapeHtml(headers.price)}</span></th>
      <th class="col-qty"><span class="col-header">${escapeHtml(headers.qty)}</span></th>
      <th class="col-total"><span class="col-header">${escapeHtml(headers.total)}</span></th>
    </tr>
  </thead>
  <tbody>
    ${rows.map((r) => pricingRow(r)).join("\n    ")}
  </tbody>
</table>`;
}

function checklistRow({ feature, bullets }) {
  return `<tr>
      <th scope="row" class="cell feature">
        <div class="feature-name">${escapeHtml(feature)}</div>
      </th>
      <td class="cell caps">${includeList(bullets, { rich: true })}</td>
    </tr>`;
}

function checklistTable({ rows, headers }) {
  return `<table class="pricing-table checklist">
  <thead>
    <tr>
      <th class="col-feature"><span class="col-header">${escapeHtml(headers.group)}</span></th>
      <th class="col-caps"><span class="col-header">${escapeHtml(headers.caps)}</span></th>
    </tr>
  </thead>
  <tbody>
    ${rows.map((r) => checklistRow(r)).join("\n    ")}
  </tbody>
</table>`;
}

/** Keep small modules on one page; allow tall modules to split (thead repeats). */
function moduleBlockClass(mod, mode) {
  const bulletCount = mod.rows.reduce(
    (n, r) => n + (Array.isArray(r.bullets) ? r.bullets.length : 0),
    0,
  );
  const maySplit = mod.rows.length >= 4 || bulletCount >= 20;
  if (mode === "pricing" || mode === "checklist") {
    return maySplit
      ? "module-block module-block--may-split"
      : "module-block module-block--keep";
  }
  return "module-block module-block--keep";
}

function renderHtml({
  title,
  meta,
  mode,
  modules,
  footnotes,
  date,
  product,
  docLabel,
  lang,
}) {
  const showPrice = mode === "pricing";
  const ui = uiCopy(lang);
  const tableHeaders = {
    feature: ui.feature,
    group: ui.group,
    unit: ui.unit,
    price: ui.price,
    qty: ui.qty,
    total: ui.total,
    caps: ui.caps,
  };

  // Pricing + features summary: one labeled ModuleBlock per H2 module.
  // Pricing rows = billable units; checklist rows = feature groups.
  const blocks = [];
  for (const mod of modules) {
    if (showPrice) {
      const rows = mod.rows.map((r) => {
        const { qty, total } = lineQtyTotal(r.price, lang);
        return { ...r, qty, total };
      });
      blocks.push(`<section class="${moduleBlockClass(mod, mode)}">
  <div class="module-label">${escapeHtml(mod.label)}</div>
  ${pricingTable({ rows, headers: tableHeaders })}
</section>`);
      continue;
    }
    blocks.push(`<section class="${moduleBlockClass(mod, mode)}">
  <div class="module-label">${escapeHtml(mod.label)}</div>
  ${checklistTable({ rows: mod.rows, headers: tableHeaders })}
</section>`);
  }

  const footnotesHtml =
    footnotes.length > 0
      ? `<footer class="footnotes">${footnotes
          .map((n) => `<p class="footnote">* ${escapeHtml(n)}</p>`)
          .join("")}</footer>`
      : "";

  const metaRight = meta ? escapeHtml(meta) : "";
  const htmlLang = lang === "th" ? "th" : "en";
  const fontStack =
    lang === "th"
      ? '"Sarabun", "Plus Jakarta Sans", system-ui, sans-serif'
      : '"Plus Jakarta Sans", system-ui, sans-serif';
  const fontLinks =
    lang === "th"
      ? `  <link href="https://fonts.googleapis.com/css2?family=Sarabun:wght@300;400;500;600;700&family=Plus+Jakarta+Sans:wght@300;400;500;600;700&display=swap" rel="stylesheet" />`
      : `  <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@300;400;500;600;700&display=swap" rel="stylesheet" />`;

  return `<!DOCTYPE html>
<html lang="${htmlLang}">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${escapeHtml(title)}</title>
  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
${fontLinks}
  <style>
    /* Tokens from rocket-deck globals.css + merz-pricing.tsx */
    :root {
      --slide-surface: #f7f5f2;
      --slide-frame: #f7f5f2;
      --slide-border: #1d2124;
      --slide-text: #1d2124;
      --foreground: #1d2124;
      --background: #f7f5f2;
      --slide-rail: 56px;
      --slide-w: ${SLIDE_A4_W}px;
    }

    * { box-sizing: border-box; }

    html, body {
      margin: 0;
      padding: 0;
      background: #e5e2dc;
      color: var(--foreground);
      font-family: ${fontStack};
      -webkit-print-color-adjust: exact;
      print-color-adjust: exact;
    }

    /* One Merz A4 canvas; content may grow → multi-page print */
    .slide {
      position: relative;
      width: var(--slide-w);
      min-height: ${SLIDE_A4_H}px;
      margin: 24px auto;
      background: var(--slide-frame);
      container-type: inline-size;
      container-name: slide;
    }

    .slide-surface {
      position: relative;
      min-height: ${SLIDE_A4_H}px;
      background: var(--slide-surface);
      border: 0.8px solid var(--slide-border);
    }

    /* Grid rails (slide.tsx frameVariant=grid) */
    .rail-h {
      position: absolute;
      left: 0; right: 0;
      top: var(--slide-rail);
      border-top: 0.8px solid color-mix(in srgb, var(--slide-border) 45%, transparent);
      pointer-events: none;
      z-index: 30;
    }
    .rail-v {
      position: absolute;
      top: 0; bottom: 0;
      left: var(--slide-rail);
      border-left: 0.8px solid color-mix(in srgb, var(--slide-border) 45%, transparent);
      pointer-events: none;
      z-index: 30;
    }

    .meta-bar {
      position: absolute;
      left: var(--slide-rail);
      right: 24px;
      top: 0;
      z-index: 40;
      height: var(--slide-rail);
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding-left: 24px;
    }
    .meta-bar .meta-left {
      display: flex;
      align-items: baseline;
      gap: 32px;
    }
    .typ-caption {
      font-size: clamp(0.75rem, 1.17cqw, 1.375rem);
      font-weight: 600;
      line-height: 1.1;
      letter-spacing: 0.07em;
      text-transform: uppercase;
      color: var(--slide-text);
    }

    .slide-body {
      position: relative;
      z-index: 10;
      padding-left: var(--slide-rail);
      padding-top: var(--slide-rail);
      min-height: ${SLIDE_A4_H}px;
    }

    /* HeaderWithContent: p-6 md:p-10 + gap-3.5 from merz */
    .hwc {
      display: flex;
      flex-direction: column;
      width: 100%;
      min-height: calc(${SLIDE_A4_H}px - var(--slide-rail));
      background: var(--background);
      padding: 40px;
      gap: 14px;
    }

    .hwc-header {
      display: flex;
      align-items: flex-end;
      justify-content: space-between;
      gap: 24px;
      padding-bottom: 12px;
      border-bottom: 1px solid var(--foreground);
    }

    .typ-heading {
      margin: 0;
      font-size: clamp(2rem, 3.7cqw, 4.375rem);
      font-weight: 400;
      line-height: 1.1;
      letter-spacing: -0.022em;
      color: var(--foreground);
    }

    .header-meta {
      flex-shrink: 0;
      font-size: clamp(0.875rem, 1.17cqw, 1.375rem);
      font-weight: 400;
      line-height: 1.5;
      letter-spacing: -0.022em;
      color: color-mix(in srgb, var(--foreground) 55%, transparent);
      text-align: right;
    }

    .hwc-content {
      display: flex;
      flex-direction: column;
      justify-content: space-between;
      gap: 14px;
      flex: 1;
      min-height: 0;
    }

    .modules {
      display: flex;
      flex-direction: column;
      gap: 14px;
      min-height: 0;
    }

    /* ModuleBlock */
    .module-block {
      display: flex;
      flex-direction: column;
      gap: 10px;
    }

    /* Small modules: keep label+table together; push to next page if they won't fit. */
    .module-block--keep {
      break-inside: avoid;
      page-break-inside: avoid;
    }

    /* Tall pricing modules (e.g. Loyalty): may split across pages; thead repeats. */
    .module-block--may-split {
      break-inside: auto;
      page-break-inside: auto;
    }

    .module-label {
      font-size: clamp(0.75rem, 1.17cqw, 1.375rem);
      font-weight: 600;
      line-height: 1.1;
      letter-spacing: 0.07em;
      text-transform: uppercase;
      color: var(--foreground);
      break-after: avoid;
      page-break-after: avoid;
    }

    /* PricingTable — merz-pricing.tsx */
    .pricing-table {
      width: 100%;
      border-collapse: collapse;
      border: 1px solid color-mix(in srgb, var(--foreground) 25%, transparent);
    }

    /* Repeat FEATURE/UNIT/PRICE when a table continues on the next page */
    .pricing-table thead {
      display: table-header-group;
    }
    .pricing-table tbody {
      display: table-row-group;
    }

    .pricing-table thead tr {
      border-bottom: 1px solid color-mix(in srgb, var(--foreground) 25%, transparent);
      background: color-mix(in srgb, var(--foreground) 3%, transparent);
      break-inside: avoid;
      page-break-inside: avoid;
    }

    /* CRITICAL: th defaults to center — Merz is left-aligned */
    .pricing-table th,
    .pricing-table td {
      text-align: left;
      font-weight: 400;
      vertical-align: top;
    }

    .col-header {
      font-size: clamp(0.75rem, 1.17cqw, 1.375rem);
      font-weight: 600;
      line-height: 1.1;
      letter-spacing: 0.07em;
      text-transform: uppercase;
      color: color-mix(in srgb, var(--foreground) 45%, transparent);
    }

    .pricing-table th.col-feature,
    .pricing-table th.col-unit,
    .pricing-table th.col-price,
    .pricing-table th.col-qty,
    .pricing-table th.col-total,
    .pricing-table th.col-caps {
      padding: 10px 16px;
      border-right: 1px solid color-mix(in srgb, var(--foreground) 15%, transparent);
    }

    .pricing-table th.col-unit { width: 18%; }
    .pricing-table th.col-price {
      width: 14%;
      text-align: right;
    }
    .pricing-table th.col-price .col-header,
    .pricing-table th.col-qty .col-header,
    .pricing-table th.col-total .col-header {
      display: block;
      text-align: right;
    }
    .pricing-table th.col-qty {
      width: 10%;
      text-align: right;
    }
    .pricing-table th.col-total {
      width: 14%;
      text-align: right;
      border-right: none;
    }
    .pricing-table th.col-caps { border-right: none; width: 62%; }

    .pricing-table tbody tr {
      border-bottom: 1px solid color-mix(in srgb, var(--foreground) 15%, transparent);
      page-break-inside: avoid;
    }
    .pricing-table tbody tr:last-child { border-bottom: none; }

    .cell {
      padding: 14px 16px;
      border-right: 1px solid color-mix(in srgb, var(--foreground) 15%, transparent);
      font-size: clamp(0.875rem, 1.17cqw, 1.375rem);
      line-height: 1.5;
      letter-spacing: -0.022em;
    }

    .cell.feature { font-weight: 400; }
    .cell.price,
    .cell.qty,
    .cell.total {
      text-align: right;
      white-space: nowrap;
    }
    .cell.price { width: 14%; }
    .cell.qty { width: 10%; }
    .cell.total {
      border-right: none;
      width: 14%;
    }
    .cell.unit { width: 18%; }
    .cell.caps { border-right: none; }

    .feature-stack,
    .unit-stack {
      display: flex;
      flex-direction: column;
      gap: 4px;
      align-items: flex-start;
      text-align: left;
    }

    .feature-name {
      font-weight: 600;
      color: var(--foreground);
      text-align: left;
    }

    .feature-detail {
      color: color-mix(in srgb, var(--foreground) 55%, transparent);
      text-align: left;
    }

    .unit-name {
      font-weight: 500;
      color: color-mix(in srgb, var(--foreground) 80%, transparent);
      text-align: left;
    }

    .price-val,
    .qty-val,
    .total-val {
      font-weight: 600;
      font-variant-numeric: tabular-nums;
      color: var(--foreground);
      text-align: right;
    }

    ul.includes,
    ul.feature-list,
    ul.feature-includes {
      list-style: none;
      margin: 6px 0 0;
      padding: 0;
      display: flex;
      flex-direction: column;
      gap: 2px;
      align-items: flex-start;
      width: 100%;
    }

    ul.feature-list {
      gap: 12px;
      margin: 0;
    }

    .feature-item {
      display: flex;
      flex-direction: column;
      gap: 2px;
      align-items: flex-start;
      width: 100%;
      text-align: left;
    }

    .feature-item-name {
      font-weight: 600;
      color: var(--foreground);
      text-align: left;
    }

    .feature-item-summary {
      color: color-mix(in srgb, var(--foreground) 55%, transparent);
      text-align: left;
      font-weight: 400;
    }

    ul.feature-includes {
      margin-top: 4px;
      gap: 2px;
      padding-left: 2px;
    }

    .include-line {
      color: color-mix(in srgb, var(--foreground) 55%, transparent);
      text-align: left;
      display: block;
    }

    .include-keyword {
      font-weight: 650;
      color: var(--foreground);
    }

    .row-note {
      margin: 8px 0 0;
      padding: 0;
      font-style: italic;
      font-weight: 400;
      color: color-mix(in srgb, var(--foreground) 50%, transparent);
      text-align: left;
    }

    .checklist .cell.caps {
      width: 72%;
    }
    .checklist .col-feature,
    .checklist .cell.feature {
      width: 28%;
    }

    .footnotes {
      display: flex;
      flex-direction: column;
      gap: 4px;
      margin-top: auto;
      padding-top: 10px;
      border-top: 1px solid color-mix(in srgb, var(--foreground) 20%, transparent);
    }

    .footnote {
      margin: 0;
      font-size: clamp(0.875rem, 1.17cqw, 1.375rem);
      line-height: 1.5;
      letter-spacing: -0.022em;
      color: color-mix(in srgb, var(--foreground) 45%, transparent);
    }

    /* Top/bottom margin on every printed page (avoids flush table starts on page 2+) */
    @page {
      size: A4 portrait;
      margin: 12mm 8mm;
    }

    @media print {
      html, body {
        background: var(--slide-frame);
        width: auto;
      }
      .slide {
        margin: 0;
        width: auto;
        min-height: auto;
      }
      .slide-surface,
      .slide-body,
      .hwc {
        min-height: auto;
      }
      .slide-surface {
        border: none;
      }
      /* Absolute rails only decorate the first fragment; hide so they don't clip mid-doc */
      .rail-h,
      .rail-v {
        display: none;
      }
      .slide-body {
        padding-left: 0;
        padding-top: 0;
      }
      .meta-bar {
        position: static;
        height: auto;
        padding: 0 0 12px;
        margin-bottom: 8px;
      }
      .hwc {
        padding: 0;
      }
    }
  </style>
</head>
<body>
  <div class="slide">
    <div class="slide-surface">
      <span class="rail-h" aria-hidden="true"></span>
      <span class="rail-v" aria-hidden="true"></span>
      <div class="meta-bar">
        <div class="meta-left">
          <span class="typ-caption">${escapeHtml(date)}</span>
          <span class="typ-caption">${escapeHtml(product)}</span>
        </div>
        <span class="typ-caption">${escapeHtml(docLabel)}</span>
      </div>
      <div class="slide-body">
        <div class="hwc">
          <header class="hwc-header">
            <h1 class="typ-heading">${escapeHtml(title)}</h1>
            ${metaRight ? `<div class="header-meta">${metaRight}</div>` : ""}
          </header>
          <div class="hwc-content">
            <div class="modules">
${blocks.join("\n")}
            </div>
            ${footnotesHtml}
          </div>
        </div>
      </div>
    </div>
  </div>
</body>
</html>
`;
}

function main() {
  const args = parseArgs(process.argv);
  if (args.help || !args.input || !args.output) {
    console.log(`Usage:
  node commercial/scripts/md-to-pricing-html.mjs \\
    --input <md> --output <html> [--mode pricing|checklist|auto] \\
    [--lang en|th] [--title "..."] [--meta "..."] [--date "AUGUST 2026"] \\
    [--product "ROCKET CRM"] [--doc-label "PRICING SHEET"] \\
    [--footnotes "note1|note2"]

  Pricing exports always use qty=${CONTRACT_MONTHS} months per line and Total = Price × ${CONTRACT_MONTHS}.
  Default footnotes match --lang (no blank-baseline note on customer exports).`);
    process.exit(args.help ? 0 : 1);
  }

  const inputPath = path.resolve(args.input);
  const outputPath = path.resolve(args.output);
  if (!fs.existsSync(inputPath)) die(`Input not found: ${inputPath}`);

  const md = fs.readFileSync(inputPath, "utf8");
  const mode = detectMode(md, args.mode);
  const parsed = parseCanonicalMd(md);

  const lang = detectLang({
    lang: args.lang,
    md,
    title: args.title || parsed.title,
    inputPath,
  });
  const ui = uiCopy(lang);

  const title =
    args.title ||
    (mode === "pricing" ? ui.titlePricing : ui.titleFeatures) ||
    parsed.title ||
    path.basename(inputPath, path.extname(inputPath));

  let meta = args.meta;
  if (meta === null) {
    meta = mode === "pricing" ? ui.metaPricing : "";
  }

  const defaultDocLabel =
    mode === "pricing" ? ui.docLabelPricing : ui.docLabelFeatures;
  const rawDocLabel = args.docLabel || defaultDocLabel;
  const docLabel =
    lang === "th" ? rawDocLabel : rawDocLabel.toUpperCase();

  const html = renderHtml({
    title,
    meta,
    mode,
    modules: parsed.modules,
    footnotes:
      args.footnotes.length > 0
        ? args.footnotes
        : defaultFootnotes(mode, lang),
    date: args.date || defaultDateLabel(),
    product: args.product,
    docLabel,
    lang,
  });

  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, html, "utf8");

  const rowCount = parsed.modules.reduce((n, m) => n + m.rows.length, 0);
  console.log(
    `Wrote ${outputPath} (${mode}, lang=${lang}, ${parsed.modules.length} module sections, ${rowCount} rows)`,
  );
}

main();
