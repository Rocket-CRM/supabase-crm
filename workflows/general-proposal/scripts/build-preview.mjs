#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import {
  adminOrigin,
  loadRegistry,
  resolveShortcodes,
} from "./lib.mjs";

const slug = process.argv[2];
const { runDir, registry } = loadRegistry(slug);
const origin = adminOrigin(registry);

const proposalPath = path.join(runDir, "proposal.md");
if (!fs.existsSync(proposalPath)) {
  throw new Error(`Missing ${proposalPath}`);
}

const raw = fs.readFileSync(proposalPath, "utf8");
const body = resolveShortcodes(raw, registry, "iframe", origin);

// Minimal markdown → HTML (headings, paragraphs, pre, figures already HTML)
function mdToHtml(md) {
  const parts = md.split(/\n{2,}/);
  return parts
    .map((block) => {
      const t = block.trim();
      if (!t) return "";
      if (t.startsWith("<figure")) return t;
      if (t.startsWith("```")) {
        const inner = t.replace(/^```\w*\n?/, "").replace(/\n?```$/, "");
        return `<pre><code>${escape(inner)}</code></pre>`;
      }
      if (t.startsWith("# ")) return `<h1>${inline(t.slice(2))}</h1>`;
      if (t.startsWith("## ")) return `<h2>${inline(t.slice(3))}</h2>`;
      if (t.startsWith("### ")) return `<h3>${inline(t.slice(4))}</h3>`;
      if (t.startsWith("| ") && t.includes("\n|")) {
        return tableHtml(t);
      }
      if (t.startsWith("- ") || t.startsWith("* ")) {
        const items = t.split("\n").map((l) => l.replace(/^[-*]\s+/, ""));
        return `<ul>${items.map((i) => `<li>${inline(i)}</li>`).join("")}</ul>`;
      }
      return `<p>${inline(t).replace(/\n/g, "<br>")}</p>`;
    })
    .join("\n");
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
  if (!data.length) return `<pre>${escape(block)}</pre>`;
  const [head, ...bodyRows] = data;
  return [
    "<table>",
    "<thead><tr>" + head.map((c) => `<th>${inline(c)}</th>`).join("") + "</tr></thead>",
    "<tbody>" +
      bodyRows
        .map(
          (row) =>
            "<tr>" + row.map((c) => `<td>${inline(c)}</td>`).join("") + "</tr>",
        )
        .join("") +
      "</tbody>",
    "</table>",
  ].join("");
}

function inline(s) {
  return escape(s)
    .replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>")
    .replace(/`([^`]+)`/g, "<code>$1</code>");
}

function escape(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Proposal preview — ${registry.run}</title>
  <style>
    :root { color-scheme: light; }
    body { font-family: "Sarabun", "Noto Sans Thai", system-ui, sans-serif; margin: 0; background: #f6f6f7; color: #202223; line-height: 1.55; }
    main { max-width: 920px; margin: 0 auto; padding: 2rem 1.25rem 4rem; background: #fff; box-shadow: 0 0 0 1px #e1e3e5; }
    h1,h2,h3 { line-height: 1.25; }
    h1 { font-size: 1.75rem; }
    h2 { font-size: 1.35rem; margin-top: 2.5rem; border-top: 1px solid #e1e3e5; padding-top: 1.5rem; }
    table { border-collapse: collapse; width: 100%; font-size: 0.9rem; margin: 1rem 0; }
    th, td { border: 1px solid #c9cccf; padding: 0.4rem 0.55rem; vertical-align: top; }
    th { background: #f1f2f3; }
    pre { background: #f1f2f3; padding: 0.75rem; overflow: auto; font-size: 0.85rem; }
    .banner { background: #000; color: #fff; padding: 0.65rem 1.25rem; font-size: 0.85rem; }
    .banner code { background: #333; padding: 0.1rem 0.35rem; border-radius: 3px; }
    figure.proposal-mockup { margin: 1.5rem 0; border: 1px solid #c9cccf; border-radius: 8px; overflow: hidden; background: #fafbfb; }
    figure.proposal-mockup figcaption { padding: 0.5rem 0.75rem; font-size: 0.85rem; background: #f1f2f3; border-bottom: 1px solid #c9cccf; }
    figure.proposal-mockup iframe { display: block; width: 100%; height: 720px; border: 0; background: #fff; }
    .toc { font-size: 0.9rem; margin: 1rem 0 2rem; padding: 1rem; background: #f6f6f7; border-radius: 8px; }
    .toc a { color: #2c6ecb; }
  </style>
</head>
<body>
  <div class="banner">
    Live preview · admin origin <code>${origin}</code> · run <code>${registry.run}</code>
    · start loyalty-admin (<code>npm run dev</code> :3001) then refresh
  </div>
  <main>
    <div class="toc">
      <strong>Mockups</strong>
      <ol>
        ${registry.pages
          .map(
            (p) =>
              `<li><a href="${origin}${p.path}" target="_blank" rel="noopener">${p.id}</a> — ${escape(p.title)}</li>`,
          )
          .join("\n")}
      </ol>
    </div>
    ${mdToHtml(body)}
  </main>
</body>
</html>
`;

const outDir = path.join(runDir, "preview");
fs.mkdirSync(outDir, { recursive: true });
const outFile = path.join(outDir, "index.html");
fs.writeFileSync(outFile, html, "utf8");
console.log(`Wrote ${outFile}`);
console.log(`Open in browser (loyalty-admin must be running at ${origin})`);
