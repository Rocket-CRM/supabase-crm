#!/usr/bin/env node
/**
 * Replace ASCII UI MOCKUP PLACEHOLDER blocks with {{mockup:ID}} using Screen: line.
 */
import fs from "node:fs";
import { listMarkdownTargets, loadRegistry, resolveRunDir } from "./lib.mjs";

const slug = process.argv[2];
const { registry } = loadRegistry(slug);
const runDir = resolveRunDir(slug);

const byScreen = new Map();
for (const p of registry.pages) {
  byScreen.set(normalize(p.title), p.id);
  for (const a of p.aliases || []) byScreen.set(normalize(a), p.id);
}

const blockRe =
  /```\n┌─+[^\n]*\n│\s*\[UI MOCKUP PLACEHOLDER\][^\n]*\n([\s\S]*?)└─+[^\n]*\n```/g;

let filesChanged = 0;
for (const file of listMarkdownTargets(runDir)) {
  let text = fs.readFileSync(file, "utf8");
  let hits = 0;
  const next = text.replace(blockRe, (full, body) => {
    const m = body.match(/Screen:\s*(.+)/);
    if (!m) return full;
    const id = byScreen.get(normalize(m[1]));
    if (!id) {
      console.warn(`No registry match for screen: ${m[1].trim()} in ${file}`);
      return full;
    }
    hits++;
    return `{{mockup:${id}}}`;
  });
  if (hits) {
    fs.writeFileSync(file, next, "utf8");
    filesChanged++;
    console.log(`${file}: ${hits} shortcode(s)`);
  }
}
console.log(`Updated ${filesChanged} file(s)`);

function normalize(s) {
  return String(s)
    .replace(/[│┃┆┊]/g, "")
    .replace(/[─━┄┅]+/g, "")
    .toLowerCase()
    .replace(/\s+/g, " ")
    .replace(/[—–]/g, "-")
    .trim();
}
