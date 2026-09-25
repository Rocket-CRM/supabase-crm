#!/usr/bin/env node
/**
 * Small proposal viewer — live loyalty-admin mockup iframes + download/print.
 *
 *   npm run mockups:view -- eeco-crm-202608
 *   ADMIN_ORIGIN=http://localhost:3001 npm run mockups:view -- eeco-crm-202608
 */
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";
import {
  adminOrigin,
  loadRegistry,
  mdToHtml,
  resolveRunAssetFile,
  resolveRunAssetUrls,
  toLiveMockups,
} from "../scripts/lib.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PUBLIC = path.join(__dirname, "public");
const slug = process.argv[2];
const port = Number(process.env.VIEWER_PORT || 4177);

if (!slug) {
  console.error("Usage: npm run mockups:view -- <run-slug>");
  process.exit(1);
}

// Validate run exists up front
loadRegistry(slug);

const mime = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".png": "image/png",
  ".pdf": "application/pdf",
};

function send(res, status, body, type = "text/plain; charset=utf-8") {
  res.writeHead(status, {
    "Content-Type": type,
    "Cache-Control": "no-store",
  });
  res.end(body);
}

function readIfExists(file) {
  return fs.existsSync(file) ? fs.readFileSync(file, "utf8") : null;
}

function sectionDivider(id, title) {
  // Owner-facing titles only. No "Combined pack" kickers, no writer notes,
  // no process blurbs ("Full narrative with mockups", "pending", etc.).
  return [
    `<section class="pack-part" id="${id}">`,
    `  <header class="pack-part-header">`,
    `    <h1 class="pack-part-title">${title}</h1>`,
    `  </header>`,
  ].join("\n");
}

function listPdfsUnder(runDir, runSlug, packRelRoot, emptyMessage) {
  const root = path.join(runDir, "submission-pack", packRelRoot);
  if (!fs.existsSync(root)) {
    return `<p>${emptyMessage}</p>`;
  }
  const rows = [];
  function walk(dir, rel = "") {
    for (const name of fs.readdirSync(dir).sort()) {
      const full = path.join(dir, name);
      const nextRel = rel ? `${rel}/${name}` : name;
      const st = fs.statSync(full);
      if (st.isDirectory()) walk(full, nextRel);
      else if (name.toLowerCase().endsWith(".pdf")) {
        const href = `/pack-files/${encodeURIComponent(runSlug)}/${packRelRoot}/${nextRel
          .split("/")
          .map(encodeURIComponent)
          .join("/")}`;
        rows.push(
          `<li><a href="${href}" target="_blank" rel="noopener">${nextRel}</a>` +
            ` · <a href="${href}#view=FitH" target="pack-pdf-frame">Open</a></li>`,
        );
      }
    }
  }
  walk(root);
  if (!rows.length) {
    return `<p>${emptyMessage}</p>`;
  }
  return ["<ul class=\"pack-file-list\">", ...rows, "</ul>"].join("\n");
}

function listPackPdfs(runDir, runSlug) {
  const company = listPdfsUnder(
    runDir,
    runSlug,
    "01-part1-qualification",
    "No Part 1 PDF files are attached yet.",
  );
  return [
    company,
    `<iframe class="pack-pdf-frame" name="pack-pdf-frame" title="Pack PDF preview"></iframe>`,
  ].join("\n");
}

function listPastWorkPdfs(runDir, runSlug, lang = "en") {
  const h2 =
    lang === "th"
      ? {
          count: "ผลงานเพิ่มเติมสำหรับคะแนนจำนวนสัญญา",
          highest: "ผลงานมูลค่าสูงสุด",
          upload: "ไฟล์ยื่น (ภาคผนวก ง + หลักฐาน — รวมเล่ม)",
        }
      : {
          count: "Additional past works for count scoring",
          highest: "Highest-value past work",
          upload: "Upload file (Appendix ง + evidence — one PDF)",
        };

  function listCombinedOrAll(packRelRoot, emptyMessage) {
    const root = path.join(runDir, "submission-pack", packRelRoot);
    if (!fs.existsSync(root)) {
      return `<p>${emptyMessage}</p>`;
    }
    const combinedName = "past-work-combined-ภาคผนวก-ง-และหลักฐาน.pdf";
    const combinedPath = path.join(root, combinedName);
    if (fs.existsSync(combinedPath)) {
      const href = `/pack-files/${encodeURIComponent(runSlug)}/${packRelRoot
        .split("/")
        .map(encodeURIComponent)
        .join("/")}/${encodeURIComponent(combinedName)}`;
      return [
        `<p><strong>${h2.upload}</strong></p>`,
        "<ul class=\"pack-file-list\">",
        `<li><a href="${href}" target="_blank" rel="noopener">${combinedName}</a>` +
          ` · <a href="${href}#view=FitH" target="pack-pdf-frame">Open</a></li>`,
        "</ul>",
      ].join("\n");
    }
    return listPdfsUnder(runDir, runSlug, packRelRoot, emptyMessage);
  }

  const count = listCombinedOrAll(
    "02-part2-technical/02-past-work-scoring-count",
    lang === "th"
      ? "ยังไม่มีไฟล์ผลงานสำหรับคะแนนจำนวนสัญญา"
      : "No past-work scoring-count PDFs attached yet.",
  );
  const highest = listCombinedOrAll(
    "02-part2-technical/03-past-work-scoring-highest-value",
    lang === "th"
      ? "ยังไม่มีไฟล์ผลงานมูลค่าสูงสุด"
      : "No highest-value past-work PDFs attached yet.",
  );
  return [
    `<h2>${h2.count}</h2>`,
    count,
    `<h2>${h2.highest}</h2>`,
    highest,
    `<iframe class="pack-pdf-frame" name="pack-pdf-frame" title="Past work PDF preview"></iframe>`,
  ].join("\n");
}

function listAppendixForms(runDir, runSlug, lang = "en") {
  // Prefer signed+evidence interleaved PDFs under combined/ (submission upload).
  // Old nickname HTML drafts in appendix-b-forms/ are writer drafts only — hide
  // them from the customer-facing combined view when combined PDFs exist.
  const combinedDir = path.join(
    runDir,
    "submission-pack",
    "02-part2-technical",
    "06-personnel",
    "combined",
  );
  const combinedMaster = "personnel-combined-ภาคผนวก-ข-และหลักฐาน.pdf";
  const combinedMasterPath = path.join(combinedDir, combinedMaster);

  if (fs.existsSync(combinedMasterPath)) {
    const base = `/pack-files/${encodeURIComponent(runSlug)}/02-part2-technical/06-personnel/combined`;
    const masterHref = `${base}/${encodeURIComponent(combinedMaster)}`;
    const h2 =
      lang === "th"
        ? {
            upload: "ไฟล์ยื่น (แบบฟอร์มภาคผนวก ข + หลักฐานวุฒิ — รวมเล่ม)",
            perPerson: "รายบุคคล (แบบฟอร์ม + หลักฐานต่อคน)",
          }
        : {
            upload: "Upload file (Appendix B form + education evidence — one PDF)",
            perPerson: "Per person (form + evidence)",
          };
    const perPerson = fs
      .readdirSync(combinedDir)
      .filter((n) => n.endsWith(".pdf") && n !== combinedMaster)
      .sort();
    const rows = [
      `<h2>${h2.upload}</h2>`,
      "<ul class=\"pack-file-list\">",
      `<li><a href="${masterHref}" target="_blank" rel="noopener">${combinedMaster}</a>` +
        ` · <a href="${masterHref}#view=FitH" target="pack-pdf-frame">Open</a></li>`,
      "</ul>",
      `<iframe class="pack-pdf-frame" name="pack-pdf-frame" title="Personnel PDF preview"></iframe>`,
    ];
    if (perPerson.length) {
      rows.push(
        `<h2>${h2.perPerson}</h2>`,
        "<ul class=\"pack-file-list\">",
        ...perPerson.map((name) => {
          const href = `${base}/${encodeURIComponent(name)}`;
          return (
            `<li><a href="${href}" target="_blank" rel="noopener">${name}</a>` +
            ` · <a href="${href}#view=FitH" target="pack-pdf-frame">Open</a></li>`
          );
        }),
        "</ul>",
      );
    }
    return rows.join("\n");
  }

  const dir = path.join(
    runDir,
    "submission-pack",
    "02-part2-technical",
    "06-personnel",
    "appendix-b-forms",
  );
  if (!fs.existsSync(dir)) {
    return "<p>Appendix B personnel forms will appear here when added.</p>";
  }
  const forms = fs
    .readdirSync(dir)
    .filter((n) => n.endsWith(".html"))
    .sort();
  if (!forms.length) {
    return "<p>No Appendix B forms are attached yet.</p>";
  }
  return [
    "<ul class=\"pack-file-list\">",
    ...forms.map((name) => {
      const href = `/pack-files/${encodeURIComponent(runSlug)}/02-part2-technical/06-personnel/appendix-b-forms/${encodeURIComponent(name)}`;
      const label = name.replace(/\.html$/i, "");
      return `<li><a href="${href}" target="_blank" rel="noopener">${label}</a></li>`;
    }),
    "</ul>",
  ].join("\n");
}

function docRoot(runDir, lang) {
  if (lang === "th") {
    const thDir = path.join(runDir, "th");
    if (!fs.existsSync(path.join(thDir, "proposal.md"))) {
      throw new Error(`Missing Thai proposal at ${path.join(thDir, "proposal.md")}`);
    }
    return thDir;
  }
  return runDir;
}

function renderPayload(runSlug, view = "proposal", lang = "en") {
  const { runDir, registry } = loadRegistry(runSlug);
  const origin = adminOrigin(registry);
  const root = docRoot(runDir, lang);
  const proposalPath = path.join(root, "proposal.md");
  if (!fs.existsSync(proposalPath)) {
    throw new Error(`Missing ${proposalPath}`);
  }

  const proposalRaw = fs.readFileSync(proposalPath, "utf8");
  const proposalLive = toLiveMockups(proposalRaw, registry, origin, lang);
  const proposalHtml = resolveRunAssetUrls(mdToHtml(proposalLive), registry.run);

  const titles =
    lang === "th"
      ? {
          proposal: "ข้อเสนอทางเทคนิค",
          part1: "ส่วนที่ 1 — เอกสารบริษัทและผลงานคุณสมบัติ",
          part2PastWork: "ผลงานสำหรับให้คะแนน",
          part2Proposal: "ข้อเสนอทางเทคนิค",
          part2Matrix: "ตารางเปรียบเทียบข้อกำหนด",
          part2Personnel: "บุคลากร (ภาคผนวก ข)",
        }
      : {
          proposal: "Technical proposal",
          part1: "Part 1 — company documents and qualifying past work",
          part2PastWork: "Past work for scoring",
          part2Proposal: "Technical proposal",
          part2Matrix: "Requirement comparison table",
          part2Personnel: "Personnel (Appendix B)",
        };

  let html = proposalHtml;
  let parts = [{ id: "doc-proposal", title: titles.proposal }];

  if (view === "combined") {
    // Customer-facing continuous pack only. Internal trackers (CHECKLIST,
    // writer ROSTER notes) stay out of this view.
    const matrixPath = path.join(root, "comparison-matrix.md");
    const matrixMd =
      readIfExists(matrixPath) ||
      (lang === "th"
        ? "ยังไม่มีตารางเปรียบเทียบข้อกำหนด"
        : "Requirement comparison table is not yet available.");

    parts = [
      { id: "doc-part1", title: titles.part1 },
      { id: "doc-past-work", title: titles.part2PastWork },
      { id: "doc-proposal", title: titles.part2Proposal },
      { id: "doc-matrix", title: titles.part2Matrix },
      { id: "doc-personnel", title: titles.part2Personnel },
    ];

    html = [
      sectionDivider("doc-part1", titles.part1),
      listPackPdfs(runDir, registry.run),
      "</section>",
      sectionDivider("doc-past-work", titles.part2PastWork),
      listPastWorkPdfs(runDir, registry.run, lang),
      "</section>",
      sectionDivider("doc-proposal", titles.part2Proposal),
      proposalHtml,
      "</section>",
      sectionDivider("doc-matrix", titles.part2Matrix),
      mdToHtml(matrixMd),
      "</section>",
      sectionDivider("doc-personnel", titles.part2Personnel),
      listAppendixForms(runDir, registry.run, lang),
      "</section>",
    ].join("\n");
  }

  const css = fs.readFileSync(path.join(PUBLIC, "styles.css"), "utf8");
  return {
    run: registry.run,
    view,
    lang,
    origin,
    html,
    css,
    parts,
    pages: registry.pages.map((p) => ({
      id: p.id,
      title: p.title,
      path: p.path,
    })),
  };
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url || "/", `http://127.0.0.1:${port}`);

  if (url.pathname === "/api/render") {
    try {
      const run = url.searchParams.get("run") || slug;
      const view = url.searchParams.get("view") === "combined" ? "combined" : "proposal";
      const lang = url.searchParams.get("lang") === "th" ? "th" : "en";
      const payload = renderPayload(run, view, lang);
      send(res, 200, JSON.stringify(payload), "application/json; charset=utf-8");
    } catch (e) {
      send(
        res,
        400,
        JSON.stringify({ error: e.message || String(e) }),
        "application/json; charset=utf-8",
      );
    }
    return;
  }

  const assetMatch = url.pathname.match(/^\/run-assets\/([^/]+)\/(.+)$/);
  if (assetMatch) {
    try {
      const [, runName, assetPath] = assetMatch;
      const { runDir } = loadRegistry(runName);
      const file = resolveRunAssetFile(runDir, assetPath);
      if (!file) {
        send(res, 404, "not found");
        return;
      }
      send(
        res,
        200,
        fs.readFileSync(file),
        mime[path.extname(file)] || "application/octet-stream",
      );
    } catch (e) {
      send(res, 404, e.message || "not found");
    }
    return;
  }

  const diagramMatch = url.pathname.match(
    /^\/run-diagrams\/([^/]+)\/([^/]+)\/(.+)$/,
  );
  if (diagramMatch) {
    try {
      const [, runName, diagramId, relRaw] = diagramMatch;
      const { runDir } = loadRegistry(runName);
      const base = path.resolve(runDir, "diagrams", diagramId);
      const file = path.resolve(base, decodeURIComponent(relRaw));
      if (!file.startsWith(base + path.sep) && file !== base) {
        send(res, 400, "bad path");
        return;
      }
      if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) {
        send(res, 404, "not found");
        return;
      }
      send(
        res,
        200,
        fs.readFileSync(file),
        mime[path.extname(file)] || "application/octet-stream",
      );
    } catch (e) {
      send(res, 404, e.message || "not found");
    }
    return;
  }

  const packMatch = url.pathname.match(/^\/pack-files\/([^/]+)\/(.+)$/);
  if (packMatch) {
    try {
      const [, runName, relRaw] = packMatch;
      const { runDir } = loadRegistry(runName);
      const packRoot = path.join(runDir, "submission-pack");
      const decoded = decodeURIComponent(relRaw);
      if (decoded.includes("..")) {
        send(res, 400, "bad path");
        return;
      }
      const file = path.resolve(packRoot, decoded);
      if (!file.startsWith(packRoot + path.sep) || !fs.existsSync(file)) {
        send(res, 404, "not found");
        return;
      }
      const ext = path.extname(file).toLowerCase();
      const type =
        mime[ext] ||
        (ext === ".pdf" ? "application/pdf" : "application/octet-stream");
      send(res, 200, fs.readFileSync(file), type);
    } catch (e) {
      send(res, 404, e.message || "not found");
    }
    return;
  }

  let rel = url.pathname === "/" ? "/index.html" : url.pathname;
  if (rel.includes("..")) {
    send(res, 400, "bad path");
    return;
  }
  const file = path.join(PUBLIC, rel);
  if (!file.startsWith(PUBLIC) || !fs.existsSync(file)) {
    send(res, 404, "not found");
    return;
  }
  const ext = path.extname(file);
  let body = fs.readFileSync(file);
  if (rel === "/index.html") {
    let html = body.toString("utf8");
    html = html.replace(
      "</head>",
      `<script>window.__DEFAULT_RUN__=${JSON.stringify(slug)}</script></head>`,
    );
    // Auto-append ?run= for first load convenience when opened as /
    body = Buffer.from(html, "utf8");
  }
  send(res, 200, body, mime[ext] || "application/octet-stream");
});

server.listen(port, "127.0.0.1", () => {
  const origin = adminOrigin(loadRegistry(slug).registry);
  const href = `http://127.0.0.1:${port}/?run=${encodeURIComponent(slug)}`;
  const combined = `${href}&view=combined`;
  console.log(`Proposal viewer: ${href}`);
  console.log(`Combined pack:   ${combined}`);
  console.log(`Language: use the Language selector (English / ไทย) — keeps run root EN + th/ as first-class.`);
  console.log(`Live mockups from: ${origin}`);
  console.log("Keep loyalty-admin running (npm run dev :3001). Ctrl+C to stop.");
  const open =
    process.platform === "darwin"
      ? "open"
      : process.platform === "win32"
        ? "start"
        : "xdg-open";
  spawn(open, [combined], { detached: true, stdio: "ignore" }).unref();
});
