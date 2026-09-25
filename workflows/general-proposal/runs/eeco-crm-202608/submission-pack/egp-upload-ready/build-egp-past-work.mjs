/**
 * Build EECO past-work upload PDFs from existing evidence.
 * Both packs: full 6-project cover + same full evidence.
 * Labels differ: Part 1 qualifying vs Part 2 scoring.
 */
import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(
  path.resolve(
    path.dirname(fileURLToPath(import.meta.url)),
    '../../../../.tools-playwright/package.json',
  ),
);
const { chromium } = require('playwright');
const { PDFDocument } = require('pdf-lib');

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '../..');
const OUT = path.join(__dirname, 'upload'); // combined upload PDFs only
const COVERS = path.join(__dirname, '_build', 'covers');
const BUILD = path.join(ROOT, 'sources/past-work-build');

const QUALIFYING_NAME = 'EECO_ส่วนที่1_ผลงานคุณสมบัติ_TOR4.13.pdf';
const SCORING_NAME = 'EECO_ส่วนที่2_ผลงานคะแนน_TOR4.13.pdf';

async function htmlToPdf(htmlPath, pdfPath) {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  await page.goto(`file://${htmlPath}`, { waitUntil: 'networkidle' });
  await page.pdf({
    path: pdfPath,
    format: 'A4',
    printBackground: true,
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
    for (const page of pages) out.addPage(page);
  }
  fs.writeFileSync(outPath, await out.save());
}

async function main() {
  fs.mkdirSync(OUT, { recursive: true });
  const coverQ = path.join(COVERS, 'cover-qualifying.pdf');
  const coverS = path.join(COVERS, 'cover-scoring.pdf');

  console.log('Rendering Thai covers + certificate…');
  await htmlToPdf(path.join(COVERS, 'cover-qualifying.html'), coverQ);
  await htmlToPdf(path.join(COVERS, 'cover-scoring.html'), coverS);
  const certNew = path.join(COVERS, 'certificate-of-work.pdf');
  await htmlToPdf(path.join(COVERS, 'certificate-of-work.html'), certNew);

  const evidence = [
    certNew,
    path.join(BUILD, '02-syngenta-สัญญา.pdf'),
    path.join(BUILD, '03-rangsit-futurepark-สัญญา.pdf'),
    path.join(BUILD, '04-popmart-หลักฐาน.pdf'),
    path.join(BUILD, '05-kao-หลักฐาน.pdf'),
    path.join(BUILD, '06-firstclass-หลักฐาน.pdf'),
    path.join(BUILD, '07-rermmai-หลักฐาน.pdf'),
  ];

  const outQ = path.join(OUT, QUALIFYING_NAME);
  const outS = path.join(OUT, SCORING_NAME);

  console.log('Merging Part 1 pack…');
  await mergePdfs([coverQ, ...evidence], outQ);

  console.log('Merging Part 2 pack…');
  await mergePdfs([coverS, ...evidence], outS);

  for (const f of [outQ, outS]) {
    const mb = (fs.statSync(f).size / (1024 * 1024)).toFixed(1);
    console.log(`OK ${path.basename(f)} (${mb} MB)`);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
