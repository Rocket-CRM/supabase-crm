#!/usr/bin/env node
/**
 * Reconcile requirements markdown + docs/PRODUCT_NARRATIVE.md
 * → public.doc_knowledge_chunks (hash-skip).
 * search_docs defaults to requirements/ only; narrative is get_section-only.
 * Intended for daily CI cron + manual runs.
 *
 * Env:
 *   SUPABASE_URL
 *   SUPABASE_SERVICE_ROLE_KEY
 *   REQUIREMENTS_DIR (optional, default: <repo>/requirements)
 */

import { createHash } from "crypto";
import { createClient } from "@supabase/supabase-js";
import { promises as fs } from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "..");
const REQUIREMENTS_DIR = process.env.REQUIREMENTS_DIR
  ? path.resolve(process.env.REQUIREMENTS_DIR)
  : path.join(REPO_ROOT, "requirements");

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

const MAX_CHARS = 4000; // ~1k tokens rough cap per chunk
const EXCLUDE_NAME_RE =
  /^(REGISTRY_|CHANGELOG\.md$|INDEX_FUNCTION\.md$|INDEX_DOMAIN\.md$)/i;

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

function sha256(text) {
  return createHash("sha256").update(text).digest("hex");
}

function slugify(s) {
  return String(s)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "")
    .slice(0, 80) || "section";
}

function estimateTokens(text) {
  return Math.ceil(text.length / 4);
}

function splitOversized(body, baseKey) {
  if (body.length <= MAX_CHARS) {
    return [{ keySuffix: "", body }];
  }
  const parts = [];
  let i = 0;
  let part = 0;
  while (i < body.length) {
    let end = Math.min(i + MAX_CHARS, body.length);
    if (end < body.length) {
      const nl = body.lastIndexOf("\n", end);
      if (nl > i + MAX_CHARS * 0.5) end = nl;
    }
    parts.push({
      keySuffix: `~p${part}`,
      body: body.slice(i, end).trim(),
    });
    i = end;
    part += 1;
  }
  return parts.filter((p) => p.body.length > 0);
}

/** Chunk markdown by SECTION: tags, else by ## / ### headings. */
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
    for (const part of splitOversized(body || title, baseKey)) {
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
        is_active: true,
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
      current = {
        headingPath: heading,
        title: heading,
        lines: [line],
      };
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
        is_active: true,
      });
    }
  }

  return sections;
}

async function walkMarkdownFiles(dir, base = dir) {
  const out = [];
  const entries = await fs.readdir(dir, { withFileTypes: true });
  for (const ent of entries) {
    const full = path.join(dir, ent.name);
    if (ent.isDirectory()) {
      if (ent.name === "archive" || ent.name === "node_modules") continue;
      out.push(...(await walkMarkdownFiles(full, base)));
      continue;
    }
    if (!ent.name.endsWith(".md")) continue;
    if (EXCLUDE_NAME_RE.test(ent.name)) continue;
    // Skip pure pointer stubs under ~30 lines later via content; keep domains/_index
    out.push(full);
  }
  return out;
}

async function fetchExistingHashes() {
  const map = new Map();
  let from = 0;
  const page = 1000;
  for (;;) {
    const { data, error } = await supabase
      .from("doc_knowledge_chunks")
      .select("id, path, chunk_key, content_hash, is_active")
      .range(from, from + page - 1);
    if (error) throw error;
    if (!data?.length) break;
    for (const row of data) {
      map.set(`${row.path}::${row.chunk_key}`, row);
    }
    if (data.length < page) break;
    from += page;
  }
  return map;
}

async function upsertChunk(row) {
  const { error } = await supabase.from("doc_knowledge_chunks").upsert(
    {
      path: row.path,
      heading_path: row.heading_path,
      chunk_key: row.chunk_key,
      title: row.title,
      content: row.content,
      content_hash: row.content_hash,
      token_estimate: row.token_estimate,
      is_active: true,
    },
    { onConflict: "path,chunk_key" }
  );
  if (error) throw error;
}

async function deactivateIds(ids) {
  if (!ids.length) return;
  for (let i = 0; i < ids.length; i += 200) {
    const batch = ids.slice(i, i + 200);
    const { error } = await supabase
      .from("doc_knowledge_chunks")
      .update({ is_active: false })
      .in("id", batch);
    if (error) throw error;
  }
}

async function main() {
  console.log(`Scanning ${REQUIREMENTS_DIR}`);
  const files = await walkMarkdownFiles(REQUIREMENTS_DIR);
  const narrativePath = path.join(REPO_ROOT, "docs", "PRODUCT_NARRATIVE.md");
  try {
    await fs.access(narrativePath);
    files.push(narrativePath);
  } catch {
    console.warn("docs/PRODUCT_NARRATIVE.md not found — skip narrative ingest");
  }
  const desired = [];
  for (const full of files) {
    const rel = path.relative(REPO_ROOT, full).split(path.sep).join("/");
    // requirements/ for search_docs; narrative for get_section only
    if (
      !rel.startsWith("requirements/") &&
      rel !== "docs/PRODUCT_NARRATIVE.md"
    ) {
      continue;
    }
    const raw = await fs.readFile(full, "utf8");
    // Skip tiny pointer stubs
    if (raw.trim().length < 80 && /Moved|pointer|Canonical:/i.test(raw)) {
      continue;
    }
    desired.push(...chunkMarkdown(rel, raw));
  }

  console.log(`Desired chunks: ${desired.length} from ${files.length} files`);
  const existing = await fetchExistingHashes();
  console.log(`Existing rows: ${existing.size}`);

  let insertedOrUpdated = 0;
  let skipped = 0;
  const seenKeys = new Set();

  for (const row of desired) {
    const key = `${row.path}::${row.chunk_key}`;
    seenKeys.add(key);
    const prev = existing.get(key);
    if (prev && prev.content_hash === row.content_hash && prev.is_active) {
      skipped += 1;
      continue;
    }
    await upsertChunk(row);
    insertedOrUpdated += 1;
  }

  const toDeactivate = [];
  for (const [key, row] of existing.entries()) {
    if (!seenKeys.has(key) && row.is_active) {
      toDeactivate.push(row.id);
    }
  }
  await deactivateIds(toDeactivate);

  console.log(
    JSON.stringify(
      {
        files: files.length,
        desired_chunks: desired.length,
        upserted: insertedOrUpdated,
        unchanged: skipped,
        deactivated: toDeactivate.length,
      },
      null,
      2
    )
  );
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
