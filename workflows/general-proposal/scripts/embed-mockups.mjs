#!/usr/bin/env node
/**
 * Replace {{mockup:Mxx}} in proposal.md (and optionally sections) with
 * markdown images pointing at assets/<id>.png so the MD is viewable in Cursor.
 *
 * Source of truth for ids remains the shortcodes until this runs.
 * Re-run after mockups:capture when screens change.
 */
import fs from "node:fs";
import path from "node:path";
import {
  adminOrigin,
  listMarkdownTargets,
  loadRegistry,
  resolveShortcodes,
} from "./lib.mjs";

const slug = process.argv[2];
const all = process.argv.includes("--all");
const { runDir, registry } = loadRegistry(slug);
const origin = adminOrigin(registry);
const assetsDir = path.join(runDir, "assets");

const missing = registry.pages.filter(
  (p) => !fs.existsSync(path.join(assetsDir, `${p.id}.png`)),
);
if (missing.length) {
  console.error(
    `Missing ${missing.length} capture(s). Run with loyalty-admin up:\n` +
      `  ADMIN_ORIGIN=${origin} npm run mockups:capture -- ${slug}\n` +
      `Missing: ${missing.map((p) => p.id).join(", ")}`,
  );
  process.exit(1);
}

const targets = all
  ? listMarkdownTargets(runDir)
  : [path.join(runDir, "proposal.md")].filter((f) => fs.existsSync(f));

for (const file of targets) {
  const raw = fs.readFileSync(file, "utf8");
  const next = resolveShortcodes(raw, registry, "image", origin);
  fs.writeFileSync(file, next, "utf8");
  console.log(`Embedded images → ${file}`);
}

console.log(
  "Open proposal.md in the editor — mockups render as local PNGs under assets/.",
);
