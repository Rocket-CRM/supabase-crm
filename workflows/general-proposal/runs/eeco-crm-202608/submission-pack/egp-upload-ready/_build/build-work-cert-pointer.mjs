/**
 * One-page Thai pointer PDF for Part 2 「หนังสือรับรองผลงาน」 / 「อื่นๆ」 slots.
 */
import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(
  path.resolve(
    path.dirname(fileURLToPath(import.meta.url)),
    '../../../../../.tools-playwright/package.json',
  ),
);
const { chromium } = require('playwright');

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const COVERS = path.join(__dirname, 'covers');
const OUT = path.resolve(__dirname, '../upload');
const HTML = path.join(COVERS, 'cover-work-cert-pointer.html');
const PDF_NAME = 'EECO_ส่วนที่2_คำชี้แจงชี้แหล่ง_หนังสือรับรองผลงาน.pdf';

async function main() {
  fs.mkdirSync(OUT, { recursive: true });
  const outPdf = path.join(OUT, PDF_NAME);
  const browser = await chromium.launch();
  const page = await browser.newPage();
  await page.goto(`file://${HTML}`, { waitUntil: 'networkidle' });
  await page.pdf({
    path: outPdf,
    format: 'A4',
    printBackground: true,
    margin: { top: '0', right: '0', bottom: '0', left: '0' },
  });
  await browser.close();
  console.log('Wrote', outPdf);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
