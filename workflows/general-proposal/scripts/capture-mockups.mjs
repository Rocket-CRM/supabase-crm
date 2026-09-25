#!/usr/bin/env node
/**
 * Capture registry pages from loyalty-admin into runs/<slug>/assets/<id>.png
 */
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { adminOrigin, loadRegistry, WORKFLOW_ROOT } from "./lib.mjs";

const slug = process.argv[2];
const { runDir, registry } = loadRegistry(slug);
const origin = adminOrigin(registry);
const assetsDir = path.join(runDir, "assets");
fs.mkdirSync(assetsDir, { recursive: true });

const pwDir = path.join(WORKFLOW_ROOT, ".tools-playwright");
fs.mkdirSync(pwDir, { recursive: true });
const pkg = path.join(pwDir, "package.json");
if (!fs.existsSync(pkg)) {
  fs.writeFileSync(
    pkg,
    JSON.stringify({ name: "gp-playwright", private: true }, null, 2),
  );
}
if (!fs.existsSync(path.join(pwDir, "node_modules", "playwright"))) {
  console.log("Installing playwright into workflows/general-proposal/.tools-playwright …");
  const inst = spawnSync("npm", ["install", "playwright@1.49.1", "--no-save"], {
    cwd: pwDir,
    stdio: "inherit",
  });
  if (inst.status !== 0) process.exit(inst.status ?? 1);
  spawnSync("npx", ["playwright", "install", "chromium"], {
    cwd: pwDir,
    stdio: "inherit",
  });
}

const runner = path.join(pwDir, "capture-once.mjs");
fs.writeFileSync(
  runner,
  `
import { chromium } from 'playwright';
import path from 'node:path';
import fs from 'node:fs';

const pages = ${JSON.stringify(registry.pages)};
const origin = ${JSON.stringify(origin)};
const assetsDir = ${JSON.stringify(assetsDir)};

const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({
  viewport: { width: 1440, height: 900 },
  deviceScaleFactor: 2,
});
const page = await context.newPage();
let failed = 0;
for (const p of pages) {
  const url = origin + p.path;
  const out = path.join(assetsDir, p.id + '.png');
  console.log('GET', url);
  try {
    const res = await page.goto(url, { waitUntil: 'networkidle', timeout: 60000 });
    if (!res || !res.ok()) {
      console.error('FAIL', p.id, res && res.status());
      failed++;
      continue;
    }
    await page.waitForTimeout(600);
    await page.screenshot({ path: out, fullPage: true });
    console.log('WROTE', out);
  } catch (e) {
    console.error('FAIL', p.id, e.message);
    failed++;
  }
}
await browser.close();
process.exit(failed ? 1 : 0);
`,
  "utf8",
);

console.log(`Capturing ${registry.pages.length} pages from ${origin}`);
const run = spawnSync("node", [runner], { cwd: pwDir, stdio: "inherit" });
process.exit(run.status ?? 1);
