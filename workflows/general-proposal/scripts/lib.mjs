import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
export const WORKFLOW_ROOT = path.resolve(__dirname, "..");
export const RUNS_ROOT = path.join(WORKFLOW_ROOT, "runs");

export function resolveRunDir(slug) {
  if (!slug) throw new Error("Usage: pass run slug, e.g. eeco-crm-202608");
  const dir = path.join(RUNS_ROOT, slug);
  if (!fs.existsSync(dir)) throw new Error(`Run folder not found: ${dir}`);
  return dir;
}

export function loadRegistry(slug) {
  const runDir = resolveRunDir(slug);
  const file = path.join(runDir, "mockup-registry.json");
  if (!fs.existsSync(file)) {
    throw new Error(`Missing ${file} — create mockup-registry.json first`);
  }
  const registry = JSON.parse(fs.readFileSync(file, "utf8"));
  if (registry.version !== 1 || !Array.isArray(registry.pages)) {
    throw new Error("Invalid registry: need version:1 and pages[]");
  }
  return { runDir, registry, file };
}

export function adminOrigin(registry) {
  return (
    process.env.ADMIN_ORIGIN?.replace(/\/$/, "") ||
    registry.defaultOriginUrl?.replace(/\/$/, "") ||
    "http://localhost:3001"
  );
}

export function pageById(registry, id) {
  return registry.pages.find((p) => p.id === id);
}

export function iframeFigure(page, origin, runSlug = null) {
  const url = `${origin}${page.path}`;
  const run = runSlug || "";
  const captureAbs =
    run && path.join(RUNS_ROOT, run, "assets", `${page.id}.png`);
  const captureSrc =
    captureAbs && fs.existsSync(captureAbs)
      ? `/run-assets/${encodeURIComponent(run)}/${page.id}.png`
      : "";
  // Screen = live iframe; print = captured PNG (browsers blank cross-origin iframes).
  // Embed both in HTML + CSS media toggle — do not rely on beforeprint JS.
  const printImg = captureSrc
    ? `  <img class="mockup-print" src="${escapeHtml(captureSrc)}" alt="${escapeHtml(page.title)}" />`
    : `  <p class="mockup-print-missing">Print capture missing for ${escapeHtml(page.id)} — run <code>npm run mockups:capture</code>.</p>`;
  return [
    `<figure class="proposal-mockup${captureSrc ? " has-print-capture" : ""}" data-mockup-id="${page.id}">`,
    `  <figcaption><strong>${page.id}</strong> — ${escapeHtml(page.title)}`,
    `    <a class="mockup-open" href="${url}" target="_blank" rel="noopener">Open ↗</a>`,
    `  </figcaption>`,
    `  <iframe class="mockup-live" src="${url}" title="${escapeHtml(page.title)}" loading="lazy"></iframe>`,
    printImg,
    `</figure>`,
  ].join("\n");
}

/** Title from diagrams/<id>/data.<lang>.json (fallback: other lang, then id). */
export function loadDiagramTitle(run, id, lang = "en") {
  const dir = path.join(RUNS_ROOT, run, "diagrams", id);
  const order =
    lang === "th"
      ? ["data.th.json", "data.en.json"]
      : ["data.en.json", "data.th.json"];
  for (const name of order) {
    const file = path.join(dir, name);
    if (!fs.existsSync(file)) continue;
    try {
      const data = JSON.parse(fs.readFileSync(file, "utf8"));
      if (data && typeof data.title === "string" && data.title.trim()) {
        return data.title.trim();
      }
    } catch {
      /* ignore */
    }
  }
  return id;
}

/** Replace {{mockup:Mxx}} with HTML iframe or markdown image. */
export function resolveShortcodes(markdown, registry, mode, origin) {
  return markdown.replace(/\{\{mockup:([A-Za-z0-9_-]+)\}\}/g, (full, id) => {
    const page = pageById(registry, id);
    if (!page) {
      return `<!-- missing mockup ${id} -->\n\n**[Missing mockup: ${id}]**\n`;
    }
    const url = `${origin}${page.path}`;
    if (mode === "iframe") {
      return iframeFigure(page, origin, registry.run);
    }
    if (mode === "image") {
      const rel = `./assets/${id}.png`;
      const abs = path.join(
        RUNS_ROOT,
        registry.run,
        "assets",
        `${id}.png`,
      );
      if (fs.existsSync(abs)) {
        // HTML <img> — Cursor MD preview often fails on ![](assets/…) relative links
        return (
          `<img src="${rel}" alt="${escapeHtml(page.title)}" ` +
          `style="max-width:100%;border:1px solid #c9cccf;border-radius:8px;" />\n\n` +
          `*${id}: ${page.title}*`
        );
      }
      return `<!-- capture pending ${id} → ${url} -->\n\n> **Mockup ${id}** — ${page.title} *(run mockups:capture)*\n`;
    }
    return full;
  });
}

function diagramFigureHtml(id, title, bodyInner) {
  const safeTitle = escapeHtml(title);
  return [
    `<figure class="proposal-diagram" data-diagram-id="${escapeHtml(id)}">`,
    `  <figcaption>${safeTitle}</figcaption>`,
    `  ${bodyInner}`,
    `</figure>`,
  ].join("\n");
}

/** Embed `{{diagram:executive-overview}}` as a same-origin iframe (viewer) or PNG if captured. */
export function resolveDiagramShortcodes(markdown, registry, lang = "en") {
  const run = registry.run;
  return markdown.replace(/\{\{diagram:([A-Za-z0-9_-]+)\}\}/g, (full, id) => {
    const dir = path.join(RUNS_ROOT, run, "diagrams", id);
    const htmlFile = path.join(dir, "index.html");
    if (!fs.existsSync(htmlFile)) {
      return `<!-- missing diagram ${id} -->\n\n**[Missing diagram: ${id}]**\n`;
    }
    const title = loadDiagramTitle(run, id, lang);
    const pngAbs = path.join(RUNS_ROOT, run, "assets", `diagram-${id}.png`);
    if (fs.existsSync(pngAbs)) {
      return diagramFigureHtml(
        id,
        title,
        `<img src="./assets/diagram-${escapeHtml(id)}.png" alt="${escapeHtml(title)}" />`,
      );
    }
    const src = `/run-diagrams/${encodeURIComponent(run)}/${encodeURIComponent(id)}/index.html?lang=${encodeURIComponent(lang === "th" ? "th" : "en")}`;
    return diagramFigureHtml(
      id,
      title,
      `<iframe src="${src}" title="${escapeHtml(title)}" loading="lazy" class="diagram-frame"></iframe>`,
    );
  });
}

/**
 * Force live iframes for viewer: shortcodes, captured <img>, and ![](assets) all become iframes.
 */
export function toLiveMockups(markdown, registry, origin, lang = "en") {
  let md = resolveDiagramShortcodes(markdown, registry, lang);
  // Drop standalone caption lines left by embed (*M04: …*)
  md = md.replace(/^\*(M\d+):[^*]+\*\s*$/gm, "");
  // Captured HTML images
  md = md.replace(
    /<img\b[^>]*src=["'](?:\.\/)?assets\/(M\d+)\.png["'][^>]*>/gi,
    (_, id) => {
      const page = pageById(registry, id);
      return page
        ? iframeFigure(page, origin, registry.run)
        : `<!-- missing mockup ${id} -->`;
    },
  );
  // Markdown images
  md = md.replace(/!\[[^\]]*\]\((?:\\.\/)?assets\/(M\d+)\.png\)/g, (_, id) => {
    const page = pageById(registry, id);
    return page
      ? iframeFigure(page, origin, registry.run)
      : `<!-- missing mockup ${id} -->`;
  });
  // Shortcodes
  md = resolveShortcodes(md, registry, "iframe", origin);
  return md;
}

export function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/** Rewrite ./assets/… in static <img> tags for the proposal viewer HTTP server. */
export function resolveRunAssetUrls(html, runSlug) {
  return html.replace(
    /(<img\b[^>]*\ssrc=["'])(?:\.\/)?assets\/([^"']+)(["'])/gi,
    (_, pre, file, post) => `${pre}/run-assets/${runSlug}/${file}${post}`,
  );
}

export function resolveRunAssetFile(runDir, assetPath) {
  if (!assetPath || assetPath.includes("..")) return null;
  const assetsRoot = path.join(runDir, "assets");
  const file = path.resolve(assetsRoot, assetPath);
  if (!file.startsWith(assetsRoot + path.sep) || !fs.existsSync(file)) {
    return null;
  }
  return file;
}

/** Lightweight MD → HTML for the proposal viewer. */
export function mdToHtml(md) {
  // Pull fenced blocks first so blank lines inside ```mermaid don't split the diagram.
  const fences = [];
  // \r?\n — proposal.md may be CRLF; a bare \n fence regex misses ```mermaid blocks.
  const masked = md.replace(/```(\w*)\r?\n([\s\S]*?)```/g, (_, lang, code) => {
    const i = fences.length;
    fences.push({ lang: (lang || "").toLowerCase(), code: code.replace(/\r\n/g, "\n") });
    return `\n\n%%FENCE_${i}%%\n\n`;
  });

  const parts = masked.split(/\n{2,}/);
  return parts
    .map((block) => {
      const t = block.trim();
      if (!t) return "";
      const fence = t.match(/^%%FENCE_(\d+)%%$/);
      if (fence) {
        const { lang, code } = fences[Number(fence[1])];
        if (lang === "mermaid") {
          return `<div class="mermaid-wrap"><pre class="mermaid">${escapeHtml(code.trim())}</pre></div>`;
        }
        return `<pre><code class="language-${escapeHtml(lang)}">${escapeHtml(code)}</code></pre>`;
      }
      if (t.startsWith("<figure")) return t;
      if (t.startsWith("<img")) return t;
      if (t.startsWith("# ")) return `<h1>${inlineMd(t.slice(2))}</h1>`;
      if (t.startsWith("## ")) return `<h2>${inlineMd(t.slice(3))}</h2>`;
      if (t.startsWith("### ")) return `<h3>${inlineMd(t.slice(4))}</h3>`;
      if (t.startsWith("| ") && t.includes("\n|")) return tableHtml(t);
      if (t.startsWith("- ") || t.startsWith("* ")) {
        const items = t.split("\n").map((l) => l.replace(/^[-*]\s+/, ""));
        return `<ul>${items.map((i) => `<li>${inlineMd(i)}</li>`).join("")}</ul>`;
      }
      if (t.startsWith("---")) return "<hr />";
      return `<p>${inlineMd(t).replace(/\n/g, "<br>")}</p>`;
    })
    .join("\n");
}

function inlineMd(s) {
  return escapeHtml(s)
    .replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>")
    .replace(/`([^`]+)`/g, "<code>$1</code>");
}

function tableHtml(block) {
  const rows = block.split("\n").filter((r) => r.trim().startsWith("|"));
  const data = rows
    .filter((r) => !/^\|\s*-+/.test(r))
    .map((r) =>
      r
        .split("|")
        .slice(1, -1)
        .map((c) => c.trim()),
    );
  if (!data.length) return `<pre>${escapeHtml(block)}</pre>`;
  const [head, ...bodyRows] = data;
  return [
    "<table>",
    "<thead><tr>" +
      head.map((c) => `<th>${inlineMd(c)}</th>`).join("") +
      "</tr></thead>",
    "<tbody>" +
      bodyRows
        .map(
          (row) =>
            "<tr>" + row.map((c) => `<td>${inlineMd(c)}</td>`).join("") + "</tr>",
        )
        .join("") +
      "</tbody>",
    "</table>",
  ].join("");
}

export function listMarkdownTargets(runDir) {
  const out = [];
  const proposal = path.join(runDir, "proposal.md");
  if (fs.existsSync(proposal)) out.push(proposal);
  const sections = path.join(runDir, "sections");
  if (fs.existsSync(sections)) {
    for (const name of fs.readdirSync(sections)) {
      if (name.endsWith(".md")) out.push(path.join(sections, name));
    }
  }
  return out;
}
