const ASSET_V = "20260805f";
const params = new URLSearchParams(location.search);
const slug = params.get("run") || window.__DEFAULT_RUN__ || "";
let view = params.get("view") === "combined" ? "combined" : "proposal";
let lang = params.get("lang") === "th" ? "th" : "en";
if (slug && !params.get("run")) {
  params.set("run", slug);
  history.replaceState(null, "", `${location.pathname}?${params}`);
}

const el = {
  doc: document.getElementById("doc"),
  toc: document.getElementById("mockup-toc"),
  docToc: document.getElementById("doc-toc"),
  tocHeading: document.getElementById("toc-heading"),
  run: document.getElementById("run-label"),
  origin: document.getElementById("origin-label"),
  mode: document.getElementById("mode-label"),
  viewSelect: document.getElementById("view-select"),
  langSelect: document.getElementById("lang-select"),
};

if (el.viewSelect) el.viewSelect.value = view;
if (el.langSelect) el.langSelect.value = lang;

let tocObserver = null;

function waitForMermaid(timeoutMs = 8000) {
  if (window.__mermaid) return Promise.resolve(window.__mermaid);
  return new Promise((resolve, reject) => {
    const t = setTimeout(
      () => reject(new Error("Mermaid CDN did not load (check network / jsdelivr)")),
      timeoutMs,
    );
    window.addEventListener(
      "mermaid-ready",
      () => {
        clearTimeout(t);
        if (window.__mermaid) resolve(window.__mermaid);
        else reject(new Error("Mermaid loaded but window.__mermaid missing"));
      },
      { once: true },
    );
  });
}

async function renderMermaid(root) {
  const nodes = [...root.querySelectorAll("pre.mermaid")];
  if (!nodes.length) return;

  let mermaid;
  try {
    mermaid = await waitForMermaid();
  } catch (e) {
    root.insertAdjacentHTML(
      "afterbegin",
      `<div class="error">${escapeText(e.message)}. Diagrams stay as source text.</div>`,
    );
    return;
  }

  let ok = 0;
  let fail = 0;
  for (const node of nodes) {
    const src = node.textContent.trim();
    const id = `mmd-${ok + fail}-${Math.random().toString(36).slice(2, 8)}`;
    try {
      const { svg } = await mermaid.render(id, src);
      const wrap = document.createElement("div");
      wrap.className = "mermaid";
      wrap.innerHTML = svg;
      node.replaceWith(wrap);
      ok++;
    } catch (e) {
      fail++;
      console.error("mermaid render failed", e, src.slice(0, 80));
      const err = document.createElement("div");
      err.className = "error";
      err.textContent = `Diagram failed to render: ${e.message || e}`;
      node.insertAdjacentElement("afterend", err);
    }
  }
  if (fail) console.warn(`Mermaid: ${ok} ok, ${fail} failed`);
}

function wireIframeErrors(root) {
  root.querySelectorAll("figure.proposal-mockup iframe").forEach((iframe) => {
    iframe.addEventListener("error", () => {
      const msg = document.createElement("div");
      msg.className = "iframe-error";
      msg.style.display = "block";
      msg.textContent =
        "Mockup iframe blocked or failed to load. Ensure loyalty-admin is on :3001.";
      iframe.insertAdjacentElement("afterend", msg);
    });
  });
}

window.addEventListener("message", (ev) => {
  const data = ev.data;
  if (!data || data.type !== "proposal-diagram-height") return;
  const fig = document.querySelector(
    `figure.proposal-diagram[data-diagram-id="${data.id}"] iframe`,
  );
  if (fig && data.height) {
    fig.style.height = `${Math.max(240, Number(data.height) + 16)}px`;
  }
});

function escapeText(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

function slugify(text) {
  const base = String(text)
    .trim()
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 72);
  return base || "section";
}

function uniqueId(preferred, used) {
  let id = preferred;
  let n = 2;
  while (used.has(id) || document.getElementById(id)) {
    id = `${preferred}-${n++}`;
  }
  used.add(id);
  return id;
}

function isDocumentTitle(text) {
  return /^(technical proposal|requirement comparison table|ข้อเสนอทางเทคนิค|ตารางเปรียบเทียบคุณลักษณะเฉพาะและข้อกำหนด|ตารางเปรียบเทียบข้อกำหนด)$/i.test(
    text.trim(),
  );
}

/**
 * Document-order TOC: pack parts as L1; headings inside a pack part nest under it.
 * Avoids dumping all chapters after every Part 2 label.
 */
function collectHeadings(root) {
  const used = new Set();
  const entries = [];
  const hasPackParts = root.querySelectorAll("section.pack-part[id]").length > 0;

  if (!hasPackParts) {
    root.querySelectorAll("h1, h2").forEach((heading) => {
      const text = heading.textContent.trim();
      if (text.length < 2 || isDocumentTitle(text)) {
        if (!heading.id) heading.id = uniqueId(slugify(text || "section"), used);
        else used.add(heading.id);
        return;
      }
      const isH1 = heading.tagName === "H1";
      const numberedSub =
        /^\d+\.\d+\s+\S/.test(text) && !/^\d+\.\d+\.\d+/.test(text);
      if (!isH1 && !numberedSub) return;
      const id = uniqueId(heading.id || slugify(text), used);
      heading.id = id;
      entries.push({ id, text, level: isH1 ? 1 : 2, el: heading, parentId: null });
    });
    return entries;
  }

  root.querySelectorAll("section.pack-part[id]").forEach((sec) => {
    used.add(sec.id);
    const title =
      sec.querySelector(".pack-part-title")?.textContent?.trim() || sec.id;
    entries.push({
      id: sec.id,
      text: title,
      level: 1,
      el: sec,
      parentId: null,
      collapsible: true,
    });

    sec.querySelectorAll("h1, h2").forEach((heading) => {
      if (heading.classList.contains("pack-part-title")) return;
      // Only direct descendants of this section for nesting (skip nested pack-parts)
      if (heading.closest("section.pack-part") !== sec) return;

      const text = heading.textContent.trim();
      if (text.length < 2) return;
      if (isDocumentTitle(text)) {
        if (!heading.id) heading.id = uniqueId(slugify(text), used);
        else used.add(heading.id);
        return;
      }

      const isH1 = heading.tagName === "H1";
      const numberedSub =
        /^\d+\.\d+\s+\S/.test(text) && !/^\d+\.\d+\.\d+/.test(text);
      if (!isH1 && !numberedSub) return;

      const id = uniqueId(heading.id || slugify(text), used);
      heading.id = id;
      entries.push({
        id,
        text,
        level: isH1 ? 2 : 3,
        el: heading,
        parentId: sec.id,
      });
    });
  });

  return entries;
}

function buildDocumentToc(entries) {
  if (!el.docToc) return;
  if (!entries.length) {
    el.docToc.innerHTML = "<li><em>No sections found</em></li>";
    return;
  }

  const byParent = new Map();
  const roots = [];
  for (const e of entries) {
    if (!e.parentId) roots.push(e);
    else {
      if (!byParent.has(e.parentId)) byParent.set(e.parentId, []);
      byParent.get(e.parentId).push(e);
    }
  }

  const parts = [];
  for (const rootEntry of roots) {
    const kids = byParent.get(rootEntry.id) || [];
    const childHtml = kids
      .map(
        (c) =>
          `<li class="toc-item toc-level-${c.level}"><a href="#${c.id}" data-toc-id="${c.id}">${escapeText(c.text)}</a></li>`,
      )
      .join("");

    if (kids.length) {
      parts.push(`
        <li class="toc-item toc-level-1 toc-group" data-toc-group="${rootEntry.id}">
          <div class="toc-group-head">
            <button type="button" class="toc-toggle" aria-expanded="true" aria-controls="toc-kids-${rootEntry.id}" data-toc-toggle="${rootEntry.id}" title="Expand / collapse">▾</button>
            <a href="#${rootEntry.id}" data-toc-id="${rootEntry.id}">${escapeText(rootEntry.text)}</a>
          </div>
          <ol class="toc-children" id="toc-kids-${rootEntry.id}">${childHtml}</ol>
        </li>`);
    } else {
      parts.push(
        `<li class="toc-item toc-level-1"><a href="#${rootEntry.id}" data-toc-id="${rootEntry.id}">${escapeText(rootEntry.text)}</a></li>`,
      );
    }
  }
  el.docToc.innerHTML = parts.join("");
}

function wireTocToggle(container) {
  container?.addEventListener("click", (e) => {
    const btn = e.target.closest("[data-toc-toggle]");
    if (!btn) return;
    e.preventDefault();
    e.stopPropagation();
    const id = btn.getAttribute("data-toc-toggle");
    const kids = document.getElementById(`toc-kids-${id}`);
    const group = btn.closest(".toc-group");
    if (!kids) return;
    const open = btn.getAttribute("aria-expanded") !== "false";
    btn.setAttribute("aria-expanded", open ? "false" : "true");
    btn.textContent = open ? "▸" : "▾";
    kids.hidden = open;
    group?.classList.toggle("is-collapsed", open);
  });
}

function buildMockupToc(pages, origin) {
  el.toc.innerHTML = pages
    .map(
      (p) =>
        `<li class="toc-item"><a href="#mockup-${p.id}" data-toc-id="mockup-${p.id}">${p.id}</a> · <a href="${origin}${p.path}" target="_blank" rel="noopener">open</a> — ${escapeText(p.title)}</li>`,
    )
    .join("");
}

function scrollToId(id) {
  const target = document.getElementById(id);
  if (!target) return false;
  target.scrollIntoView({ behavior: "smooth", block: "start" });
  history.replaceState(null, "", `#${id}`);
  setActiveToc(id);
  return true;
}

function setActiveToc(id) {
  document.querySelectorAll(".sidebar a[data-toc-id]").forEach((a) => {
    a.classList.toggle("is-active", a.getAttribute("data-toc-id") === id);
  });
}

function wireTocClicks(container) {
  container?.addEventListener("click", (e) => {
    const a = e.target.closest("a[data-toc-id]");
    if (!a) return;
    e.preventDefault();
    scrollToId(a.getAttribute("data-toc-id"));
  });
}

function wireScrollSpy(entries) {
  if (tocObserver) {
    tocObserver.disconnect();
    tocObserver = null;
  }
  if (!entries.length || !("IntersectionObserver" in window)) return;

  const byId = new Map(entries.map((e) => [e.id, e.el]));
  tocObserver = new IntersectionObserver(
    (obs) => {
      const visible = obs
        .filter((x) => x.isIntersecting)
        .sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top);
      if (!visible.length) return;
      const id = visible[0].target.id;
      if (id) setActiveToc(id);
    },
    {
      root: null,
      rootMargin: "-80px 0px -60% 0px",
      threshold: [0, 0.1, 1],
    },
  );

  for (const e of entries) {
    if (e.el) tocObserver.observe(e.el);
  }
  // Also observe mockup figures
  el.doc.querySelectorAll("figure.proposal-mockup[id]").forEach((fig) => {
    tocObserver.observe(fig);
  });
}

async function load() {
  if (!slug) {
    el.doc.innerHTML =
      '<div class="error">Missing <code>?run=</code> (e.g. <code>?run=eeco-crm-202608</code>).</div>';
    return;
  }
  el.run.textContent = slug;
  const qs = new URLSearchParams({ run: slug, view, lang });
  const res = await fetch(`/api/render?${qs}`, { cache: "no-store" });
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    el.doc.innerHTML = `<div class="error">${err.error || res.statusText}</div>`;
    return;
  }
  const data = await res.json();
  el.origin.textContent = data.origin;
  const modeBase =
    data.view === "combined" ? "all documents" : "proposal only";
  el.mode.textContent =
    data.lang === "th" ? `${modeBase} · Thai` : modeBase;
  el.doc.innerHTML = data.html;

  if (el.tocHeading) {
    el.tocHeading.textContent =
      data.view === "combined" ? "Contents" : "Contents";
  }

  el.doc.querySelectorAll("figure.proposal-mockup[data-mockup-id]").forEach((fig) => {
    fig.id = `mockup-${fig.getAttribute("data-mockup-id")}`;
  });

  wireIframeErrors(el.doc);
  await renderMermaid(el.doc);

  const headings = collectHeadings(el.doc);
  buildDocumentToc(headings);
  // Default: expand technical proposal; collapse other pack groups
  el.docToc?.querySelectorAll("[data-toc-toggle]").forEach((btn) => {
    const id = btn.getAttribute("data-toc-toggle");
    if (id === "doc-proposal") return;
    btn.click();
  });
  buildMockupToc(data.pages || [], data.origin);
  wireScrollSpy(headings);

  const langTag = data.lang === "th" ? " · TH" : "";
  document.title =
    data.view === "combined"
      ? `Documents — ${slug}${langTag}`
      : `Proposal — ${slug}${langTag}`;
  window.__lastRender = data;

  // Honor hash on load / after reload
  const hash = location.hash.replace(/^#/, "");
  if (hash) {
    requestAnimationFrame(() => scrollToId(hash));
  }
}

function downloadHtml() {
  const data = window.__lastRender;
  if (!data) return;
  const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>${data.view === "combined" ? "Documents" : "Proposal"} — ${data.run}</title>
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
<link href="https://fonts.googleapis.com/css2?family=Sarabun:ital,wght@0,300;0,400;0,500;0,600;0,700;1,400&display=swap" rel="stylesheet" />
<style>${data.css}</style>
<script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"><\/script>
<script>
  mermaid.initialize({ startOnLoad: false, theme: "neutral", securityLevel: "loose", fontFamily: "Sarabun, sans-serif" });
  document.addEventListener("DOMContentLoaded", async () => {
    for (const node of document.querySelectorAll("pre.mermaid")) {
      try {
        const id = "m-" + Math.random().toString(36).slice(2);
        const { svg } = await mermaid.render(id, node.textContent.trim());
        const div = document.createElement("div");
        div.className = "mermaid";
        div.innerHTML = svg;
        node.replaceWith(div);
      } catch (e) { console.error(e); }
    }
  });
<\/script>
</head>
<body>
<header class="topbar"><div class="meta"><strong>${data.run}</strong> · ${data.view} · <code>${data.origin}</code></div></header>
<div class="layout"><main class="doc" style="max-width:920px;margin:0 auto;">${data.html}</main></div>
</body>
</html>`;
  const blob = new Blob([html], { type: "text/html;charset=utf-8" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = `${data.run}-${data.view || "proposal"}-${data.lang || "en"}.html`;
  a.click();
  URL.revokeObjectURL(a.href);
}

function syncUrlAndReload() {
  params.set("run", slug);
  params.set("view", view);
  if (lang === "th") params.set("lang", "th");
  else params.delete("lang");
  const hash = location.hash || "";
  history.replaceState(null, "", `${location.pathname}?${params}${hash}`);
  load().catch((e) => {
    el.doc.innerHTML = `<div class="error">${escapeText(e.message)}</div>`;
  });
}

wireTocClicks(el.docToc);
wireTocClicks(el.toc);
wireTocToggle(el.docToc);

document.getElementById("btn-reload").addEventListener("click", () => load());
document.getElementById("btn-download-html").addEventListener("click", downloadHtml);
document.getElementById("btn-print").addEventListener("click", () => window.print());
el.viewSelect?.addEventListener("change", () => {
  view = el.viewSelect.value === "combined" ? "combined" : "proposal";
  syncUrlAndReload();
});
el.langSelect?.addEventListener("change", () => {
  lang = el.langSelect.value === "th" ? "th" : "en";
  syncUrlAndReload();
});

load().catch((e) => {
  el.doc.innerHTML = `<div class="error">${escapeText(e.message)}</div>`;
});

// Silence unused lint for cache bust constant if tree-shaken — referenced for debugging
void ASSET_V;
