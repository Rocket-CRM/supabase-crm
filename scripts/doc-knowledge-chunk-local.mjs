#!/usr/bin/env node
/**
 * Local-only: walk requirements markdown files → write chunks JSON for MCP/SQL ingest.
 * Usage: node scripts/doc-knowledge-chunk-local.mjs [out.json]
 */

import { createHash } from "crypto";
import { promises as fs } from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "..");
const REQUIREMENTS_DIR = path.join(REPO_ROOT, "requirements");
const OUT =
  process.argv[2] ||
  path.join(REPO_ROOT, "scripts/.cache/doc-knowledge-chunks.json");

const MAX_CHARS = 4000;
const EXCLUDE_NAME_RE =
  /^(REGISTRY_|CHANGELOG\.md$|INDEX_FUNCTION\.md$|INDEX_DOMAIN\.md$)/i;

function sha256(text) {
  return createHash("sha256").update(text).digest("hex");
}

function slugify(s) {
  return (
    String(s)
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-|-$/g, "")
      .slice(0, 80) || "section"
  );
}

function estimateTokens(text) {
  return Math.ceil(text.length / 4);
}

function splitOversized(body) {
  if (body.length <= MAX_CHARS) return [{ keySuffix: "", body }];
  const parts = [];
  let i = 0;
  let part = 0;
  while (i < body.length) {
    let end = Math.min(i + MAX_CHARS, body.length);
    if (end < body.length) {
      const nl = body.lastIndexOf("\n", end);
      if (nl > i + MAX_CHARS * 0.5) end = nl;
    }
    parts.push({ keySuffix: `~p${part}`, body: body.slice(i, end).trim() });
    i = end;
    part += 1;
  }
  return parts.filter((p) => p.body.length > 0);
}

function chunkMarkdown(relPath, raw) {
  const lines = raw.replace(/\r\n/g, "\n").split("\n");
  const hasSection = lines.some((l) => /^#{1,6}\s+SECTION:\s*\S+/i.test(l));
  const sections = [];
  let current = {
    headingPath: "",
    title: path.basename(relPath, ".md"),
    lines: [],
  };

  const flush = () => {
    const body = current.lines.join("\n").trim();
    if (!body && !current.headingPath) return;
    const title = current.title || current.headingPath || path.basename(relPath);
    const headingPath = current.headingPath || title;
    const baseKey = slugify(headingPath || title);
    for (const part of splitOversized(body || title)) {
      const chunkKey = `${baseKey}${part.keySuffix}`;
      const content = part.body || title;
      const displayTitle =
        headingPath && headingPath !== title
          ? `${path.basename(relPath)} > ${headingPath}`
          : title;
      const stored = `${displayTitle}\n\n${content}`.trim();
      sections.push({
        path: relPath,
        heading_path: headingPath,
        chunk_key: chunkKey,
        title: displayTitle,
        content: stored,
        content_hash: sha256(stored),
        token_estimate: estimateTokens(stored),
      });
    }
  };

  for (const line of lines) {
    let heading = null;
    if (hasSection) {
      const m = line.match(/^#{1,6}\s+(SECTION:\s*.+)$/i);
      if (m) heading = m[1].replace(/^SECTION:\s*/i, "SECTION: ").trim();
    } else {
      const m = line.match(/^(#{2,3})\s+(.+)$/);
      if (m) heading = m[2].trim();
    }
    if (heading) {
      flush();
      current = { headingPath: heading, title: heading, lines: [line] };
    } else {
      current.lines.push(line);
    }
  }
  flush();

  if (sections.length === 0) {
    const stored = raw.trim();
    if (stored) {
      sections.push({
        path: relPath,
        heading_path: "",
        chunk_key: "root",
        title: path.basename(relPath),
        content: stored,
        content_hash: sha256(stored),
        token_estimate: estimateTokens(stored),
      });
    }
  }
  return sections;
}

async function walk(dir) {
  const out = [];
  for (const ent of await fs.readdir(dir, { withFileTypes: true })) {
    const full = path.join(dir, ent.name);
    if (ent.isDirectory()) {
      if (ent.name === "archive" || ent.name === "node_modules") continue;
      out.push(...(await walk(full)));
      continue;
    }
    if (!ent.name.endsWith(".md")) continue;
    if (EXCLUDE_NAME_RE.test(ent.name)) continue;
    out.push(full);
  }
  return out;
}

const files = await walk(REQUIREMENTS_DIR);
const chunks = [];
for (const full of files) {
  const rel = path.relative(REPO_ROOT, full).split(path.sep).join("/");
  const raw = await fs.readFile(full, "utf8");
  if (raw.trim().length < 80 && /Moved|pointer|Canonical:/i.test(raw)) continue;
  chunks.push(...chunkMarkdown(rel, raw));
}

await fs.mkdir(path.dirname(OUT), { recursive: true });
await fs.writeFile(OUT, JSON.stringify(chunks));
console.log(
  JSON.stringify({ out: OUT, files: files.length, chunks: chunks.length }, null, 2)
);
