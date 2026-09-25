/**
 * Build EECO e-GP upload PDFs:
 *  - Part 2 personnel (cover + combined Appendix B + education evidence)
 *  - Part 2 comparison matrix (cover + paginated landscape sheets;
 *    whole rows only — never split a row across pages; header on every sheet)
 *
 * Output → egp-upload-ready/upload/ and ~/Downloads/EECO-eGP-upload/
 */
import { createRequire } from 'node:module';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const TOOLS = path.resolve(__dirname, '../../../../.tools-playwright/package.json');
const require = createRequire(TOOLS);
const { chromium } = require('playwright');
const { PDFDocument } = require('pdf-lib');

const COVERS = path.join(__dirname, '_build', 'covers');
const BUILD = path.join(__dirname, '_build');
const OUT = path.join(__dirname, 'upload');
const DOWNLOADS = path.join(os.homedir(), 'Downloads', 'EECO-eGP-upload');
const PERSONNEL_BODY = path.resolve(
  __dirname,
  '../02-part2-technical/06-personnel/combined/personnel-combined-ภาคผนวก-ข-และหลักฐาน.pdf',
);
const MATRIX_MD = path.resolve(
  __dirname,
  '../02-part2-technical/05-comparison-matrix/comparison-matrix.md',
);

const PERSONNEL_NAME = 'EECO_ส่วนที่2_คุณสมบัติบุคลากร_TOR5.12.pdf';
const COMPARISON_NAME = 'EECO_ส่วนที่2_ตารางเปรียบเทียบคุณสมบัติ.pdf';

const FONT_REGULAR = path.join(COVERS, 'fonts', 'SarabunRegular.ttf');
const FONT_BOLD = path.join(COVERS, 'fonts', 'SarabunBold.ttf');
const LOGO = path.join(COVERS, 'rocket-logo-full.svg');

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function mdInline(s) {
  return escapeHtml(s).replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
}

function parseMatrixRows(md) {
  const lines = md.split(/\r?\n/).filter((l) => l.trim().startsWith('|'));
  const data = lines.slice(2);
  return data.map((line) => {
    const cells = line
      .replace(/^\|/, '')
      .replace(/\|$/, '')
      .split('|')
      .map((c) => c.trim());
    return cells;
  });
}

function rowHtml(cells) {
  const [a = '', b = '', c = '', d = ''] = cells;
  const cmpClass = c.includes('ดีกว่า')
    ? 'better'
    : c.includes('เท่ากัน')
      ? 'equal'
      : '';
  return `<tr>
    <td>${mdInline(a)}</td>
    <td>${mdInline(b)}</td>
    <td class="cmp ${cmpClass}">${mdInline(c)}</td>
    <td class="ref">${mdInline(d)}</td>
  </tr>`;
}

function sharedStyles() {
  return `
  @font-face {
    font-family: "Sarabun";
    src: url("file://${FONT_REGULAR}") format("truetype");
    font-weight: 400;
  }
  @font-face {
    font-family: "Sarabun";
    src: url("file://${FONT_BOLD}") format("truetype");
    font-weight: 700;
  }
  * { box-sizing: border-box; }
  body {
    font-family: "Sarabun", "TH SarabunPSK", sans-serif;
    color: #000;
    margin: 0;
    padding: 0;
  }
  .hdr {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    margin-bottom: 4px;
    padding-bottom: 4px;
    border-bottom: 1px solid #000;
  }
  .logo { height: 26px; width: auto; }
  .doc-meta { text-align: right; font-size: 9px; line-height: 1.35; }
  h1 {
    text-align: center;
    font-size: 12.5px;
    font-weight: 700;
    margin: 4px 0 2px;
  }
  .sub {
    text-align: center;
    font-size: 9.5px;
    margin: 0 0 5px;
  }
  .table-wrap {
    border: 1.25px solid #000;
    width: 100%;
  }
  table {
    width: 100%;
    border-collapse: separate;
    border-spacing: 0;
    table-layout: fixed;
    font-size: 8.5px;
    line-height: 1.28;
  }
  th, td {
    border-right: 1px solid #000;
    border-bottom: 1px solid #000;
    padding: 3px 4px;
    vertical-align: top;
    overflow-wrap: anywhere;
    word-break: break-word;
  }
  th:last-child, td:last-child { border-right: none; }
  tr:last-child td { border-bottom: none; }
  th {
    font-weight: 700;
    text-align: center;
    background: #f3f3f3;
  }
  col.c1 { width: 36%; }
  col.c2 { width: 36%; }
  col.c3 { width: 8%; }
  col.c4 { width: 20%; }
  td.cmp { text-align: center; white-space: nowrap; font-weight: 700; }
  td.cmp.better { background: #eef7ee; }
  td.ref { white-space: normal; }
`;
}

function measureHtml(rows) {
  const tbody = rows.map(rowHtml).join('\n');
  return `<!DOCTYPE html>
<html lang="th"><head><meta charset="utf-8" />
<style>
${sharedStyles()}
html, body { width: 297mm; }
.sheet {
  width: 297mm;
  padding: 9mm 12mm 9mm 10mm;
}
#probe-header { }
</style></head>
<body>
  <div class="sheet">
    <div id="probe-header">
      <div class="hdr">
        <img class="logo" src="file://${LOGO}" alt="Rocket" />
        <div class="doc-meta">
          เอกสารประกอบการยื่นข้อเสนอ · เลขที่โครงการ 69079202016<br />
          เอกสารประกวดราคาอิเล็กทรอนิกส์ เลขที่ ๐๑๘/๒๕๖๙ · วันเสนอราคา ๗ สิงหาคม ๒๕๖๙
        </div>
      </div>
      <h1>ตารางเปรียบเทียบคุณลักษณะเฉพาะและข้อกำหนด</h1>
      <div class="sub">ผู้ยื่นข้อเสนอ: บริษัท ร็อคเก็ต อินโนเวชั่น จำกัด · อ้างอิง TOR ข้อ ๑๐.๒ (๖) · หน้า 1/1</div>
    </div>
    <div class="table-wrap">
      <table id="probe-table">
        <colgroup>
          <col class="c1" /><col class="c2" /><col class="c3" /><col class="c4" />
        </colgroup>
        <thead id="probe-thead">
          <tr>
            <th>คุณลักษณะเฉพาะและข้อกำหนดที่หน่วยงานกำหนด</th>
            <th>คุณสมบัติที่ผู้ยื่นข้อเสนอนำเสนอ</th>
            <th>เปรียบเทียบ</th>
            <th>เอกสารอ้างอิง</th>
          </tr>
        </thead>
        <tbody id="probe-tbody">
${tbody}
        </tbody>
      </table>
    </div>
  </div>
</body></html>`;
}

function paginatedHtml(pages) {
  const total = pages.length;
  const sheets = pages
    .map((pageRows, idx) => {
      const n = idx + 1;
      const tbody = pageRows.map(rowHtml).join('\n');
      return `<section class="sheet">
  <div class="hdr">
    <img class="logo" src="file://${LOGO}" alt="Rocket" />
    <div class="doc-meta">
      เอกสารประกอบการยื่นข้อเสนอ · เลขที่โครงการ 69079202016<br />
      เอกสารประกวดราคาอิเล็กทรอนิกส์ เลขที่ ๐๑๘/๒๕๖๙ · วันเสนอราคา ๗ สิงหาคม ๒๕๖๙
    </div>
  </div>
  <h1>ตารางเปรียบเทียบคุณลักษณะเฉพาะและข้อกำหนด</h1>
  <div class="sub">
    ผู้ยื่นข้อเสนอ: บริษัท ร็อคเก็ต อินโนเวชั่น จำกัด · อ้างอิง TOR ข้อ ๑๐.๒ (๖)
    · หน้า ${n}/${total}
  </div>
  <div class="table-wrap">
    <table>
      <colgroup>
        <col class="c1" /><col class="c2" /><col class="c3" /><col class="c4" />
      </colgroup>
      <thead>
        <tr>
          <th>คุณลักษณะเฉพาะและข้อกำหนดที่หน่วยงานกำหนด</th>
          <th>คุณสมบัติที่ผู้ยื่นข้อเสนอนำเสนอ</th>
          <th>เปรียบเทียบ</th>
          <th>เอกสารอ้างอิง</th>
        </tr>
      </thead>
      <tbody>
${tbody}
      </tbody>
    </table>
  </div>
</section>`;
    })
    .join('\n');

  return `<!DOCTYPE html>
<html lang="th">
<head>
<meta charset="utf-8" />
<title>ตารางเปรียบเทียบคุณลักษณะเฉพาะและข้อกำหนด</title>
<style>
${sharedStyles()}
@page { size: A4 landscape; margin: 0; }
html, body { margin: 0; padding: 0; background: #fff; }
.sheet {
  width: 297mm;
  height: 210mm;
  padding: 9mm 12mm 9mm 10mm;
  overflow: hidden;
  page-break-after: always;
  break-after: page;
}
.sheet:last-child {
  page-break-after: auto;
  break-after: auto;
}
</style>
</head>
<body>
${sheets}
</body>
</html>`;
}

async function packRowsIntoPages(rows) {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  const tmp = path.join(BUILD, '_tmp_measure-comparison.html');
  fs.writeFileSync(tmp, measureHtml(rows), 'utf8');
  await page.goto(`file://${tmp}`, { waitUntil: 'networkidle' });

  // A4 landscape content box ≈ 210mm tall; sheet padding 9+9mm; leave small safety.
  const PAGE_H_PX = await page.evaluate(() => {
    const mm = (n) => (n * 96) / 25.4;
    return mm(210);
  });
  const PAD_Y_PX = await page.evaluate(() => {
    const mm = (n) => (n * 96) / 25.4;
    return mm(9) + mm(9);
  });
  const SAFETY = 8; // px

  const { headerH, theadH, rowHeights } = await page.evaluate(() => {
    const header = document.getElementById('probe-header');
    const thead = document.getElementById('probe-thead');
    const trs = [...document.querySelectorAll('#probe-tbody tr')];
    return {
      headerH: header.getBoundingClientRect().height,
      theadH: thead.getBoundingClientRect().height,
      rowHeights: trs.map((tr) => tr.getBoundingClientRect().height),
    };
  });

  const usable = PAGE_H_PX - PAD_Y_PX - headerH - theadH - SAFETY;
  const pages = [];
  let bucket = [];
  let used = 0;

  for (let i = 0; i < rows.length; i++) {
    const h = rowHeights[i] || 28;
    // If a single row is taller than a page, still put it alone (rare).
    if (bucket.length > 0 && used + h > usable) {
      pages.push(bucket);
      bucket = [];
      used = 0;
    }
    bucket.push(rows[i]);
    used += h;
  }
  if (bucket.length) pages.push(bucket);

  await browser.close();
  console.log(
    `Paged ${rows.length} rows → ${pages.length} sheets (usable≈${usable.toFixed(0)}px; header≈${headerH.toFixed(0)}px)`,
  );
  return pages;
}

async function htmlToPdf(htmlPath, pdfPath) {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  await page.goto(`file://${htmlPath}`, { waitUntil: 'networkidle' });
  await page.pdf({
    path: pdfPath,
    printBackground: true,
    preferCSSPageSize: true,
    margin: { top: '0', right: '0', bottom: '0', left: '0' },
  });
  await browser.close();
}

async function mergePdfs(paths, outPath) {
  const out = await PDFDocument.create();
  for (const p of paths) {
    if (!fs.existsSync(p)) throw new Error(`Missing PDF: ${p}`);
    const bytes = fs.readFileSync(p);
    const doc = await PDFDocument.load(bytes, { ignoreEncryption: true });
    const pages = await out.copyPages(doc, doc.getPageIndices());
    for (const pg of pages) out.addPage(pg);
  }
  fs.writeFileSync(outPath, await out.save());
}

function copyTo(src, destDir) {
  fs.mkdirSync(destDir, { recursive: true });
  const dest = path.join(destDir, path.basename(src));
  fs.copyFileSync(src, dest);
  return dest;
}

async function main() {
  fs.mkdirSync(OUT, { recursive: true });
  fs.mkdirSync(BUILD, { recursive: true });
  fs.mkdirSync(DOWNLOADS, { recursive: true });

  if (!fs.existsSync(PERSONNEL_BODY)) {
    throw new Error(`Missing personnel combined PDF: ${PERSONNEL_BODY}`);
  }
  if (!fs.existsSync(MATRIX_MD)) {
    throw new Error(`Missing comparison matrix: ${MATRIX_MD}`);
  }

  const coverPersonnelPdf = path.join(COVERS, 'cover-personnel.pdf');
  const coverComparisonPdf = path.join(COVERS, 'cover-comparison.pdf');
  const bodyComparisonPdf = path.join(BUILD, 'body-comparison-matrix.pdf');

  console.log('Rendering covers…');
  await htmlToPdf(path.join(COVERS, 'cover-personnel.html'), coverPersonnelPdf);
  await htmlToPdf(path.join(COVERS, 'cover-comparison.html'), coverComparisonPdf);

  console.log('Paging + rendering comparison matrix…');
  const md = fs.readFileSync(MATRIX_MD, 'utf8');
  const rows = parseMatrixRows(md);
  if (rows.length < 10) throw new Error(`Matrix parse too short: ${rows.length} rows`);

  const pages = await packRowsIntoPages(rows);
  const bodyHtml = paginatedHtml(pages);
  const bodyHtmlPath = path.join(BUILD, '_tmp_body-comparison-matrix.html');
  fs.writeFileSync(bodyHtmlPath, bodyHtml, 'utf8');
  await htmlToPdf(bodyHtmlPath, bodyComparisonPdf);

  const outPersonnel = path.join(OUT, PERSONNEL_NAME);
  const outComparison = path.join(OUT, COMPARISON_NAME);

  console.log('Merging personnel pack…');
  await mergePdfs([coverPersonnelPdf, PERSONNEL_BODY], outPersonnel);

  console.log('Merging comparison pack…');
  await mergePdfs([coverComparisonPdf, bodyComparisonPdf], outComparison);

  for (const f of [outPersonnel, outComparison]) {
    const dest = copyTo(f, DOWNLOADS);
    const mb = (fs.statSync(f).size / (1024 * 1024)).toFixed(1);
    console.log(`OK ${path.basename(f)} (${mb} MB)`);
    console.log(`   → ${dest}`);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
