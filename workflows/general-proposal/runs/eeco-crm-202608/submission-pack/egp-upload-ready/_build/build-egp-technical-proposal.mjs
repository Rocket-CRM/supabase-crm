/**
 * Build EECO Part 2 technical-proposal upload PDF:
 *   Thai title cover + Thai proposal body (from packed th/ copy).
 *
 * Fixes vs first export:
 * - Real Sarabun TTFs (stubs caused spaced Thai glyphs)
 * - Executive diagram via local HTTP (file:// fetch failed)
 * - Mockups: full captures as-is (no crop) — scale to page width
 * - Mermaid rasterized to PNG to avoid empty page-break ghosts
 * - Smaller body type + forced Sarabun on all elements
 * - Playwright header/footer on body pages
 */
import { createRequire } from 'node:module';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';

const require = createRequire(
  path.resolve(
    path.dirname(fileURLToPath(import.meta.url)),
    '../../../../../.tools-playwright/package.json',
  ),
);
const { chromium } = require('playwright');
const { PDFDocument } = require('pdf-lib');

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const OUT = __dirname;
const UPLOAD = path.resolve(__dirname, '../upload');
const COVERS = path.join(__dirname, 'covers');
const PROP_DIR = path.resolve(__dirname, '../../02-part2-technical/04-technical-proposal');
const RUN_ASSETS = path.resolve(__dirname, '../../../assets');
const LIB = path.resolve(__dirname, '../../../../../scripts/lib.mjs');

const OUT_NAME =
  'ส่วนที่2_ข้อเสนอทางเทคนิค_แนวคิดสถาปัตยกรรมและเครื่องมือพัฒนา.pdf';
const UPLOAD_NAME = 'EECO_ส่วนที่2_ข้อเสนอทางเทคนิค.pdf';
const COVER_STANDALONE = '00_ปก_ส่วนที่2_ข้อเสนอทางเทคนิค.pdf';

function fileUrl(p) {
  return pathToFileURL(path.resolve(p)).href;
}

function startStaticServer(rootDir) {
  return new Promise((resolve) => {
    const server = http.createServer((req, res) => {
      const urlPath = decodeURIComponent((req.url || '/').split('?')[0]);
      const rel = urlPath === '/' ? '/index.html' : urlPath;
      const file = path.join(rootDir, rel.replace(/^\//, ''));
      if (!file.startsWith(rootDir) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
        res.writeHead(404);
        res.end('not found');
        return;
      }
      const ext = path.extname(file).toLowerCase();
      const type =
        ext === '.html'
          ? 'text/html; charset=utf-8'
          : ext === '.json'
            ? 'application/json; charset=utf-8'
            : ext === '.js'
              ? 'text/javascript; charset=utf-8'
              : ext === '.css'
                ? 'text/css; charset=utf-8'
                : ext === '.png'
                  ? 'image/png'
                  : ext === '.svg'
                    ? 'image/svg+xml'
                    : 'application/octet-stream';
      res.writeHead(200, { 'Content-Type': type, 'Cache-Control': 'no-store' });
      res.end(fs.readFileSync(file));
    });
    server.listen(0, '127.0.0.1', () => {
      const { port } = server.address();
      resolve({ server, port });
    });
  });
}

async function htmlToPdf(htmlPath, pdfPath) {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  await page.goto(fileUrl(htmlPath), { waitUntil: 'networkidle' });
  await page.pdf({
    path: pdfPath,
    format: 'A4',
    printBackground: true,
    margin: { top: '12mm', right: '12mm', bottom: '12mm', left: '12mm' },
  });
  await browser.close();
}

async function captureExecutiveDiagram(browser, outPng) {
  const diagramDir = path.join(PROP_DIR, 'diagrams/executive-overview');
  if (!fs.existsSync(path.join(diagramDir, 'index.html'))) {
    console.warn('No executive-overview diagram; skipping capture');
    return null;
  }
  const { server, port } = await startStaticServer(diagramDir);
  // Match proposal content width so the pillar grid fills the card (no right void)
  const page = await browser.newPage({
    viewport: { width: 1100, height: 900 },
    deviceScaleFactor: 2,
  });
  try {
    await page.goto(`http://127.0.0.1:${port}/index.html?lang=th`, {
      waitUntil: 'networkidle',
    });
    await page.waitForFunction(
      () => {
        const root = document.getElementById('root');
        return root && !root.querySelector('.err') && !!root.querySelector('.pillar-grid');
      },
      null,
      { timeout: 20000 },
    );
    await page.waitForTimeout(400);
    await page.evaluate(() => {
      document.documentElement.style.width = '100%';
      document.body.style.width = '100%';
      const wrap = document.querySelector('.wrap');
      if (wrap) wrap.style.width = '100%';
      const grid = document.querySelector('.pillar-grid');
      if (grid) grid.style.width = '100%';
    });
    const el = (await page.$('.wrap')) || (await page.$('#root'));
    await el.screenshot({ path: outPng, type: 'png' });
    return outPng;
  } finally {
    await page.close();
    server.close();
  }
}

/** Use the capture as-is — do not crop mockups (cropping mangled headers/UI). */
function copyMockupPng(src, dest) {
  fs.copyFileSync(src, dest);
  console.log('asset', path.basename(src));
}

async function mergePdfs(paths, outPath) {
  const out = await PDFDocument.create();
  for (const p of paths) {
    if (!fs.existsSync(p)) throw new Error(`Missing PDF: ${p}`);
    const bytes = fs.readFileSync(p);
    const doc = await PDFDocument.load(bytes, { ignoreEncryption: true });
    const pages = await out.copyPages(doc, doc.getPageIndices());
    for (const page of pages) out.addPage(page);
  }
  fs.writeFileSync(outPath, await out.save());
}

function rewriteAssetUrls(html, assetsDir) {
  return html.replace(
    /<img\b([^>]*)\ssrc=["'](?:\.\/)?assets\/([^"']+)["']([^>]*)>/gi,
    (_, pre, file, post) => {
      const abs = path.join(assetsDir, file);
      const src = fs.existsSync(abs) ? fileUrl(abs) : file;
      if (!fs.existsSync(abs)) console.warn(`Missing asset: ${abs}`);
      const attrs = `${pre} ${post}`;
      const isShot = /^(M\d{2}|company-)/i.test(file);
      const hasClass = /\bclass\s*=/.test(attrs);
      const classAttr = isShot
        ? hasClass
          ? ''
          : ' class="shot"'
        : '';
      // Re-inject class into existing class attr when present
      let open = `<img${classAttr} ${pre.trim()} src="${src}" ${post.trim()}>`;
      if (isShot && hasClass) {
        open = open.replace(
          /\bclass=["']([^"']*)["']/,
          (_m, c) => `class="${c} shot"`.replace(/\s+/g, ' '),
        );
      }
      return open.replace(/\s+/g, ' ').replace(' >', '>');
    },
  );
}

function normalizeMarkdown(md) {
  // Drop markdown italic caption lines under images (*…*)
  md = md.replace(/^\*[^*\n]+\*\s*$/gm, '');
  // Prefer ASCII hyphen ranges in TOR refs for cleaner PDF shaping
  md = md.replace(/(\d)\u2013(\d)/g, '$1-$2');
  md = md.replace(/\u2014/g, ' — ');
  // Keep LR layouts (viewer-like). Scale-to-fit in mermaid post-process handles A4.
  // Strip inline width styles so CSS can constrain to page
  md = md.replace(/<img\b([^>]*?)\sstyle="[^"]*"([^>]*)>/gi, '<img$1$2>');
  md = md.replace(
    /<figure\b[^>]*style="[^"]*"[^>]*>/gi,
    '<figure class="photo-grid">',
  );
  // Tag mockup / photo assets for print layout
  md = md.replace(
    /<img\b([^>]*\ssrc=["'][^"']*\/(?:M\d{2}|company-[^"']+)\.png["'][^>]*)>/gi,
    '<img class="shot"$1>',
  );
  return md;
}

async function buildBodyHtml({ diagramPng, croppedAssetsDir }) {
  const { mdToHtml } = await import(pathToFileURL(LIB).href);
  let md = fs.readFileSync(path.join(PROP_DIR, 'proposal.md'), 'utf8');
  md = normalizeMarkdown(md);

  if (diagramPng && fs.existsSync(diagramPng)) {
    const src = fileUrl(diagramPng);
    md = md.replace(
      /\{\{diagram:executive-overview\}\}/g,
      `<figure class="exec-diagram"><img src="${src}" alt="สรุปผู้บริหาร — จากสถานะปัจจุบันสู่ระบบที่เสนอ" /></figure>`,
    );
  } else {
    md = md.replace(/\{\{diagram:executive-overview\}\}/g, '');
  }

  let html = mdToHtml(md);
  html = html.replace(/<table>/g, '<div class="table-wrap"><table>').replace(/<\/table>/g, '</table></div>');
  html = rewriteAssetUrls(html, croppedAssetsDir);
  // Keep each mockup/photo in an unbreakable frame (prevents gray page-2 ghosts)
  html = html.replace(
    /<img\b([^>]*\bclass=["'][^"']*\bshot\b[^"']*["'][^>]*)>/gi,
    '<div class="shot-frame">$&</div>',
  );

  const fontRegular = fileUrl(path.join(COVERS, 'fonts/SarabunRegular.ttf'));
  const fontBold = fileUrl(path.join(COVERS, 'fonts/SarabunBold.ttf'));
  const fontSemi = fileUrl(path.join(COVERS, 'fonts/SarabunSemiBold.ttf'));
  const fontItalic = fileUrl(path.join(COVERS, 'fonts/SarabunItalic.ttf'));

  return `<!DOCTYPE html>
<html lang="th">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>ข้อเสนอทางเทคนิค — บริษัท ร็อคเก็ต อินโนเวชั่น จำกัด</title>
<style>
  @font-face {
    font-family: "Sarabun";
    src: url("${fontRegular}") format("truetype");
    font-weight: 400;
    font-style: normal;
  }
  @font-face {
    font-family: "Sarabun";
    src: url("${fontItalic}") format("truetype");
    font-weight: 400;
    font-style: italic;
  }
  @font-face {
    font-family: "Sarabun";
    src: url("${fontSemi}") format("truetype");
    font-weight: 600;
    font-style: normal;
  }
  @font-face {
    font-family: "Sarabun";
    src: url("${fontBold}") format("truetype");
    font-weight: 700;
    font-style: normal;
  }

  *, *::before, *::after { box-sizing: border-box; }
  html, body {
    margin: 0;
    padding: 0;
    width: 100%;
    max-width: 100%;
    /* Do NOT use overflow-x:hidden — Chromium PDF clips table right borders */
    overflow-x: visible;
    background: #fff;
    color: #111;
    font-family: "Sarabun", "TH SarabunPSK", sans-serif !important;
    font-size: 10pt;
    line-height: 1.4;
    letter-spacing: 0 !important;
  }
  body, body * {
    font-family: "Sarabun", "TH SarabunPSK", sans-serif !important;
    letter-spacing: 0 !important;
  }
  main.doc {
    width: 100%;
    max-width: 100%;
    margin: 0;
    padding: 0 1px 0 0; /* keep 1px border of tables inside the page box */
    overflow-x: visible;
  }
  h1 { font-size: 14pt; font-weight: 700; margin: 0.75rem 0 0.35rem; line-height: 1.25; }
  h2 { font-size: 12pt; font-weight: 700; margin: 0.7rem 0 0.3rem; line-height: 1.25; }
  h3 { font-size: 10.5pt; font-weight: 700; margin: 0.55rem 0 0.25rem; line-height: 1.25; }
  h4 { font-size: 10pt; font-weight: 700; margin: 0.45rem 0 0.2rem; }
  p, li { font-size: 10pt; margin: 0.22rem 0; }
  ul, ol { margin: 0.3rem 0 0.3rem 1.05rem; padding: 0; }
  strong, b { font-weight: 700; }

  .table-wrap {
    width: calc(100% - 2px);
    max-width: calc(100% - 2px);
    margin: 0.45rem 1px 0.65rem 0;
    overflow: visible;
  }
  table {
    width: 100% !important;
    max-width: 100% !important;
    table-layout: fixed;
    border-collapse: separate;
    border-spacing: 0;
    font-size: 8.5pt;
    border: none;
  }
  /* Every cell paints its own edges — keep last-column right border
     (dropping it looked like “cut off at right” when outer stroke clipped). */
  th, td {
    border-right: 1px solid #333;
    border-bottom: 1px solid #333;
    border-top: 0;
    border-left: 0;
    padding: 0.22rem 0.4rem;
    vertical-align: top;
    word-break: break-word;
    overflow-wrap: anywhere;
  }
  tr:first-child > th,
  tr:first-child > td { border-top: 1px solid #333; }
  th:first-child, td:first-child { border-left: 1px solid #333; }
  th { font-weight: 700; background: #f3f3f3; }

  img {
    display: block;
    max-width: 100% !important;
    height: auto !important;
    margin: 0.45rem auto 0.65rem;
    border: 0;
    background: #fff;
  }
  .shot-frame {
    display: block;
    width: 100%;
    max-width: 100%;
    margin: 0.5rem 0 0.75rem;
    text-align: center;
    overflow: visible;
    break-inside: avoid;
    page-break-inside: avoid;
  }
  /* Full capture, scaled to page — never clip with overflow */
  img.shot {
    display: block;
    width: 100% !important;
    max-width: 100% !important;
    height: auto !important;
    max-height: 200mm;
    object-fit: contain;
    object-position: top center;
    margin: 0 auto;
    border: 1px solid #e6e7e8;
    border-radius: 4px;
    background: #fafbfb;
    break-inside: avoid;
    page-break-inside: avoid;
  }
  figure {
    margin: 0.45rem 0 0.65rem;
    padding: 0;
    width: 100%;
    max-width: 100%;
    border: 0;
  }
  figure.photo-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 0.5rem;
  }
  figure.photo-grid img { margin: 0; width: 100% !important; }
  figure.exec-diagram {
    border: 0 !important;
    background: transparent;
    box-shadow: none;
  }
  figure.exec-diagram img {
    margin: 0.35rem 0 0.55rem;
    width: 100% !important;
    border: 0 !important;
    border-radius: 0;
    background: transparent;
  }

  .mermaid-wrap {
    margin: 0.55rem 0;
    padding: 0.25rem 0;
    width: 100%;
    max-width: 100%;
    overflow: visible;
    background: transparent;
    border: 0;
    border-radius: 0;
    text-align: center;
    break-inside: avoid;
    page-break-inside: avoid;
  }
  .mermaid-wrap .mermaid {
    display: inline-block;
    max-width: 100%;
  }
  .mermaid-wrap svg {
    display: block;
    margin: 0 auto;
    max-width: 100% !important;
    max-height: 200mm !important;
    width: auto !important;
    height: auto !important;
  }

  pre { font-size: 8.5pt; max-width: 100%; overflow: visible; white-space: pre-wrap; }
  hr { border: 0; border-top: 1px solid #ddd; margin: 0.7rem 0; }

  @page { size: A4 portrait; }
  @media print {
    h1 { break-before: page; break-after: avoid; }
    main.doc > h1:first-child { break-before: auto; }
    h2, h3, h4 { break-after: avoid; }
    figure, .mermaid-wrap, .shot-frame, img.shot { break-inside: avoid; page-break-inside: avoid; }
  }
</style>
<script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"><\/script>
</head>
<body>
<main class="doc">${html}</main>
<script>
  (async () => {
    if (!window.mermaid) { document.body.dataset.ready = "1"; return; }
    const pageW = Math.max(320, document.documentElement.clientWidth || 700);
    // Match viewer: theme "neutral" (softer than flat white "base")
    mermaid.initialize({
      startOnLoad: false,
      theme: "neutral",
      securityLevel: "loose",
      fontFamily: "Sarabun, TH SarabunPSK, sans-serif",
      themeVariables: {
        fontFamily: "Sarabun, TH SarabunPSK, sans-serif",
        fontSize: "13px",
        primaryTextColor: "#111111",
        lineColor: "#444444",
        edgeLabelBackground: "#fafbfb",
      },
      flowchart: {
        htmlLabels: true,
        curve: "basis",
        padding: 12,
        nodeSpacing: 28,
        rankSpacing: 36,
        useMaxWidth: true,
      },
      state: { htmlLabels: true, useMaxWidth: true },
    });
    // Fit within pageW × maxH — do not stretch tall charts to full width.
    const maxH = 720;
    for (const node of document.querySelectorAll("pre.mermaid")) {
      try {
        const id = "m-" + Math.random().toString(36).slice(2);
        const { svg } = await mermaid.render(id, node.textContent.trim());
        // mdToHtml already wraps <pre.mermaid> in .mermaid-wrap — replace pre only
        const div = document.createElement("div");
        div.className = "mermaid";
        div.innerHTML = svg;
        const el = div.querySelector("svg");
        if (el) {
          let vb = el.getAttribute("viewBox");
          if (!vb) {
            const w = parseFloat(el.getAttribute("width")) || pageW;
            const h = parseFloat(el.getAttribute("height")) || 200;
            vb = "0 0 " + w + " " + h;
            el.setAttribute("viewBox", vb);
          }
          const parts = vb.trim().split(/[\\s,]+/).map(Number);
          const vbW = parts[2] || pageW;
          const vbH = parts[3] || 200;
          const scale = Math.min(1, (pageW - 28) / vbW, maxH / vbH);
          const outW = Math.max(120, Math.round(vbW * scale));
          const outH = Math.max(80, Math.round(vbH * scale));
          el.setAttribute("width", String(outW));
          el.setAttribute("height", String(outH));
          el.style.width = outW + "px";
          el.style.height = outH + "px";
          el.style.maxWidth = "100%";
          el.style.maxHeight = maxH + "px";
          el.setAttribute("preserveAspectRatio", "xMidYMid meet");
        }
        node.replaceWith(div);
      } catch (e) { console.error(e); }
    }
    document.body.dataset.ready = "1";
  })();
<\/script>
</body>
</html>`;
}

async function main() {
  const coverHtml = path.join(COVERS, 'cover-technical-proposal.html');
  const coverPdf = path.join(COVERS, 'cover-technical-proposal.pdf');
  const bodyHtmlPath = path.join(COVERS, 'body-technical-proposal.html');
  const bodyPdf = path.join(COVERS, 'body-technical-proposal.pdf');
  const diagramPng = path.join(COVERS, 'diagram-executive-overview-th.png');
  const croppedDir = path.join(COVERS, 'cropped-assets');
  const outPdf = path.join(OUT, OUT_NAME);
  const packCopy = path.join(PROP_DIR, OUT_NAME);

  fs.mkdirSync(croppedDir, { recursive: true });

  // Crop every image referenced by the packed proposal
  const propMd = fs.readFileSync(path.join(PROP_DIR, 'proposal.md'), 'utf8');
  const assetNames = new Set();
  for (const m of propMd.matchAll(/(?:\.\/)?assets\/([A-Za-z0-9._-]+\.png)/g)) {
    assetNames.add(m[1]);
  }
  console.log(`Copying ${assetNames.size} assets (no crop)…`);
  for (const name of assetNames) {
    const srcPack = path.join(PROP_DIR, 'assets', name);
    const srcRun = path.join(RUN_ASSETS, name);
    const src = fs.existsSync(srcPack) ? srcPack : srcRun;
    if (!fs.existsSync(src)) {
      console.warn('missing asset', name);
      continue;
    }
    copyMockupPng(src, path.join(croppedDir, name));
  }

  console.log('Rendering Thai title cover…');
  await htmlToPdf(coverHtml, coverPdf);

  const browser = await chromium.launch();
  console.log('Capturing executive-overview diagram (Thai, via HTTP)…');
  await captureExecutiveDiagram(browser, diagramPng);
  const diagStat = fs.statSync(diagramPng);
  console.log(`diagram png: ${(diagStat.size / 1024).toFixed(0)} KB`);

  console.log('Building proposal body HTML…');
  const bodyHtml = await buildBodyHtml({ diagramPng, croppedAssetsDir: croppedDir });
  fs.writeFileSync(bodyHtmlPath, bodyHtml, 'utf8');

  console.log('Rendering proposal body PDF…');
  // Layout width ≈ A4 content box. Slightly under-size vs 210−margins so table
  // borders are never clipped by Chromium's PDF compositor.
  const page = await browser.newPage({
    viewport: { width: 680, height: 990 },
    deviceScaleFactor: 1,
  });
  await page.goto(fileUrl(bodyHtmlPath), { waitUntil: 'networkidle' });
  await page.waitForFunction(() => document.body.dataset.ready === '1', null, {
    timeout: 90000,
  });
  await page.waitForTimeout(800);

  // Rasterize Mermaid SVGs → PNG. Chromium PDF splits tall SVGs and leaves
  // empty gray/white continuation pages; bitmaps honor max-height + avoid-break.
  const mermaidDir = path.join(COVERS, 'mermaid-rasters');
  fs.mkdirSync(mermaidDir, { recursive: true });
  const wraps = await page.$$('.mermaid-wrap');
  console.log(`Rasterizing ${wraps.length} mermaid diagrams…`);
  for (let i = 0; i < wraps.length; i++) {
    const wrap = wraps[i];
    const pngPath = path.join(mermaidDir, `m${String(i).padStart(2, '0')}.png`);
    await wrap.screenshot({ path: pngPath, type: 'png' });
    const dataUrl = `data:image/png;base64,${fs.readFileSync(pngPath).toString('base64')}`;
    await wrap.evaluate((el, src) => {
      el.innerHTML = '';
      el.style.border = '0';
      el.style.background = 'transparent';
      el.style.padding = '0';
      const img = document.createElement('img');
      img.src = src;
      img.alt = 'diagram';
      img.style.display = 'block';
      img.style.width = 'auto';
      img.style.maxWidth = '100%';
      img.style.maxHeight = '180mm';
      img.style.height = 'auto';
      img.style.margin = '0 auto';
      img.style.border = '0';
      el.appendChild(img);
    }, dataUrl);
  }

  // Keep content safely inside the PDF content box (border strokes + mermaid).
  await page.evaluate(() => {
    const doc = document.documentElement;
    const main = document.querySelector('main.doc') || document.body;
    const overflow = Math.max(0, main.scrollWidth - doc.clientWidth);
    const z = overflow > 1
      ? Math.max(0.9, (doc.clientWidth - 4) / main.scrollWidth)
      : 0.985;
    main.style.zoom = String(z);
  });
  await page.pdf({
    path: bodyPdf,
    format: 'A4',
    printBackground: true,
    displayHeaderFooter: true,
    headerTemplate: `
      <div style="width:100%;font-family:Sarabun,sans-serif;font-size:8px;color:#444;padding:0 14mm;display:flex;justify-content:space-between;box-sizing:border-box;">
        <span>บริษัท ร็อคเก็ต อินโนเวชั่น จำกัด</span>
        <span>ข้อเสนอทางเทคนิค · โครงการ 69079202016</span>
      </div>`,
    footerTemplate: `
      <div style="width:100%;font-family:Sarabun,sans-serif;font-size:8px;color:#444;padding:0 14mm;display:flex;justify-content:space-between;box-sizing:border-box;">
        <span>เอกสารประกวดราคาอิเล็กทรอนิกส์ เลขที่ ๐๑๘/๒๕๖๙ · ส่วนที่ ๒ ข้อ (๔)</span>
        <span>หน้า <span class="pageNumber"></span> / <span class="totalPages"></span></span>
      </div>`,
    margin: { top: '16mm', right: '14mm', bottom: '16mm', left: '14mm' },
  });
  await browser.close();

  console.log('Merging cover + body…');
  await mergePdfs([coverPdf, bodyPdf], outPdf);
  fs.copyFileSync(coverPdf, path.join(OUT, COVER_STANDALONE));
  fs.copyFileSync(outPdf, packCopy);
  fs.mkdirSync(UPLOAD, { recursive: true });
  const uploadCopy = path.join(UPLOAD, UPLOAD_NAME);
  fs.copyFileSync(outPdf, uploadCopy);
  const downloads = path.join(process.env.HOME || '', 'Downloads', UPLOAD_NAME);
  fs.copyFileSync(outPdf, downloads);

  const mb = (fs.statSync(outPdf).size / (1024 * 1024)).toFixed(1);
  console.log(`OK ${OUT_NAME} (${mb} MB)`);
  console.log(`OK ${COVER_STANDALONE}`);
  console.log(`Upload: ${uploadCopy}`);
  console.log(`Downloads: ${downloads}`);
  console.log(`Pack: ${packCopy}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
