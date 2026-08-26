import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

/**
 * FuturePark E-Directory → store_master directory sync.
 *
 * NEVER writes: purchase_receipt_upload, OCR prompts/hints/eval/GT,
 * hint_receipt_storename, benchmark_receipts, substore_hints, mongo_id,
 * store_code (existing), manual_approve, is_reward_stock,
 * earn rates, or CRM-only utility stores (booth / pop-up / lounge / QA).
 *
 * active_status: set false only when max(LeaseEndDate) + 1 month has passed
 * (Bangkok calendar). Never auto-reactivates.
 *
 * Taxonomy: Oracle Merc/SubMerc → Merchandise attribute/sub-attribute;
 * Building/Floor → Location attribute/sub-attribute. Missing master rows
 * are created. Categories are never created.
 *
 * Duplicate external_ref: ignore inactive CRM rows. Skip write only when
 * more than one *active* store shares the number. Location/Merchandise
 * assignments are updated when Oracle Building/Floor or Merc/SubMerc change.
 * After each live run, email an HTML report (tables) to REPORT_EMAILS.
 */

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const FUNCTION_VERSION = 8;
const REPORT_EMAILS = [
  "kankamon.k@futurepark.co.th",
  "prakan@rocket.in.th",
  "rangwan@rocket.in.th",
];
const DEFAULT_MERCHANT_CODE = "futurepark";
const SNAPSHOT_RETENTION_DAYS = 14;
const STORE_SELECT =
  "id, merchant_id, store_code, store_name, active_status, external_ref, mongo_id, metadata, hint_receipt_storename, benchmark_receipts, substore_hints, manual_approve, is_reward_stock, address, province, postcode, coordinates, location_url, created_at, updated_at";

const MERC_TO_ATTR: Record<string, string> = {
  food: "FOOD",
  fashion: "FASHION",
  other: "OTHER",
  mobile: "MOBILE",
  beauty: "BEAUTY",
  service: "SERVICE",
  it: "IT",
  school: "SCHOOL",
  furniture: "FURNITURE",
  "gold&jewelry": "GOLD_JEWELRY",
  "gold & jewelry": "GOLD_JEWELRY",
  "gold jewelry": "GOLD_JEWELRY",
  cosmetic: "BEAUTY",
  superstores: "BIGC",
};

const SUBMERC_ALIASES: Record<string, string> = {
  "bakery&dessert": "Bakery&Dessert",
  "bakery & dessert": "Bakery&Dessert",
  japanese: "Japanese Food",
  "japanese food": "Japanese Food",
  "ice cream": "Ice Creme",
  icecream: "Ice Creme",
  thai: "Thai Food",
  "thai food": "Thai Food",
  korean: "Korean Food",
  "korean food": "Korean Food",
  chinese: "Chinese Food",
  "chinese / taiwanese": "Chinese Food",
  "coffee & tea": "COFFEE & TEA",
  "coffee and tea": "COFFEE & TEA",
  "local grab & go": "Local Grab & Go",
  fastfood: "Fastfood",
  "fast food": "Fastfood",
  casual: "Casual",
  accessories: "Accessories",
  "shoes & bag": "Shoes & Bag",
  sportswear: "Sportswear",
  eyeglasses: "Eyeglasses",
  watch: "Watch",
  jeans: "Jeans",
  "skin clinic": "Skin Clinic",
  nail: "Nail",
  "beauty salon": "Beauty Salon",
  spa: "Spa",
  slimming: "Slimming",
  clinic: "Clinic",
  repair: "Repair",
  studio: "Studio",
  printing: "Printing",
  massage: "Massage",
  flower: "Flower",
  gadget: "Gadget",
  hardware: "Hardware",
  camera: "Camera",
  drone: "Drone",
  game: "Game",
  distributor: "Distributor",
  "mobile phone network": "Mobile Phone Network",
  skills: "Skills",
  language: "Language",
  tutor: "Tutor",
  furniture: "Furniture",
  "home decorate": "Home Decorate",
  entertainment: "Entertainment",
  "gift shop": "Gift Shop",
  "electronic appliances": "Electronic Appliances",
  "convenience store": "Convenience Store",
  "sport activities": "Sport Activities",
  toy: "Toy",
  "drug store": "Drug Store",
  "multi brand": "Cosmetic",
  "single brand": "Cosmetic",
};

type JsonRecord = Record<string, unknown>;
type OracleRow = Record<string, string | null>;

type Tenant = {
  customerNumber: string;
  customerId: string | null;
  tenaNameEN: string;
  tenaNameTH: string | null;
  customer2Dsc: string | null;
  building: string;
  floors: string[];
  locs: string[];
  merc: string | null;
  subMerc: string | null;
  lastUpdateDate: string | null;
  leaseEndDate: string | null;
};

type AttrRow = {
  id: string;
  attribute_code: string;
  attribute_name: string;
  category_id: string;
};

type SubRow = {
  id: string;
  attribute_id: string;
  sub_attribute_code: string;
  sub_attribute_name: string;
};

type TaxCache = {
  merchantId: string;
  locCatId?: string;
  merchCatId?: string;
  locAttrs: AttrRow[];
  merchAttrs: AttrRow[];
  subsByAttr: Map<string, SubRow[]>;
  createdAttributes: number;
  createdSubAttributes: number;
};

function log(msg: string) {
  console.log(`[${new Date().toISOString()}] ${msg}`);
}

function jsonResponse(body: JsonRecord, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function pageMerchantRows(
  sb: any,
  table: string,
  select: string,
  merchantId: string,
  orderCol: string,
): Promise<any[]> {
  const pageSize = 1000;
  const rows: any[] = [];
  for (let from = 0; ; from += pageSize) {
    const { data, error } = await sb
      .from(table)
      .select(select)
      .eq("merchant_id", merchantId)
      .order(orderCol)
      .range(from, from + pageSize - 1);
    if (error) throw new Error(`${table} load: ${error.message}`);
    rows.push(...(data || []));
    if (!data || data.length < pageSize) break;
  }
  return rows;
}

function norm(s: string | null | undefined): string {
  return (s || "").trim().toLowerCase().replace(/\s+/g, " ");
}

function matchKey(s: string | null | undefined): string {
  return (s || "")
    .trim()
    .toLowerCase()
    .replace(/[&/_-]+/g, " ")
    .replace(/[^a-z0-9\u0e00-\u0e7f ]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function slugCode(raw: string): string {
  const code = raw
    .trim()
    .toUpperCase()
    .replace(/[^A-Z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .slice(0, 50);
  return code || "UNKNOWN";
}

function brandPart(storeName: string | null | undefined): string {
  return (storeName || "").split("/")[0].trim();
}

function parseOracleDate(s: string | null | undefined): Date | null {
  const m = String(s || "").match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (!m) return null;
  return new Date(Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3])));
}

function addOneMonth(d: Date): Date {
  const y = d.getUTCFullYear();
  const m = d.getUTCMonth() + 1;
  const day = d.getUTCDate();
  const last = new Date(Date.UTC(y, m + 1, 0)).getUTCDate();
  return new Date(Date.UTC(y, m, Math.min(day, last)));
}

function bangkokTodayUtcDate(): Date {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Bangkok",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date());
  const y = Number(parts.find((p) => p.type === "year")?.value);
  const mo = Number(parts.find((p) => p.type === "month")?.value);
  const d = Number(parts.find((p) => p.type === "day")?.value);
  return new Date(Date.UTC(y, mo - 1, d));
}

function leaseInactive(leaseEndDate: string | null | undefined): boolean {
  const end = parseOracleDate(leaseEndDate);
  if (!end) return false;
  return bangkokTodayUtcDate().getTime() >= addOneMonth(end).getTime();
}

type FieldChange = { field: string; before: string; after: string };
type AssignRow = {
  id: string;
  store_id: string;
  category_id: string;
  attribute_id: string | null;
  sub_attribute_id: string | null;
};
type DesiredTax = { categoryId: string; attr: AttrRow; sub: SubRow | null; field: "Location" | "Merchandise" };
type SkipBlock = {
  tenant: Tenant;
  stores: any[];
  oracleLocation: string;
  oracleMerchandise: string;
  crmLocation: string[];
  crmMerchandise: string[];
};
type ChangeBlock = { store_code: string; store_name: string; external_ref: string; changes: FieldChange[] };
type InsertBlock = { store_code: string; store_name: string; external_ref: string; locs: string; active: boolean };

function escapeHtml(s: string | null | undefined): string {
  return String(s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function locKey(locs: string[]): string {
  return [...locs].map((x) => String(x).trim()).filter(Boolean).sort().join(", ");
}

function leaseKey(s: string | null | undefined): string {
  const m = String(s || "").match(/^(\d{4}-\d{2}-\d{2})/);
  return m ? m[1] : "";
}

function statusLabel(v: unknown): string {
  return v === false ? "ปิด" : "เปิด";
}

function crmLocs(store: any): string[] {
  const meta = store?.metadata && typeof store.metadata === "object" ? store.metadata : {};
  const raw = meta.edirectory_location_codes;
  if (Array.isArray(raw) && raw.length) return raw.map((x: unknown) => String(x));
  const name = String(store?.store_name || "");
  const i = name.indexOf(" / ");
  if (i >= 0) return name.slice(i + 3).split(",").map((x: string) => x.trim()).filter(Boolean);
  return [];
}

function crmLease(store: any): string {
  const meta = store?.metadata && typeof store.metadata === "object" ? store.metadata : {};
  return leaseKey(meta.edirectory_lease_end_date);
}

function collectFieldChanges(store: any, tenant: Tenant, nextName: string | null, nextActive: boolean | null): FieldChange[] {
  const changes: FieldChange[] = [];
  if (nextName && nextName !== store.store_name) {
    changes.push({ field: "ชื่อร้าน", before: String(store.store_name || ""), after: nextName });
  }
  const oldLocs = locKey(crmLocs(store));
  const newLocs = locKey(tenant.locs);
  if (newLocs && oldLocs !== newLocs) {
    changes.push({ field: "รหัสพื้นที่", before: oldLocs || "(ยังไม่มีในแถวนี้)", after: newLocs });
  }
  if (nextActive === false && store.active_status !== false) {
    changes.push({ field: "สถานะเปิดร้าน", before: statusLabel(store.active_status), after: "ปิด" });
  }
  const oldLease = crmLease(store);
  const newLease = leaseKey(tenant.leaseEndDate);
  if (oldLease && newLease && oldLease !== newLease) {
    changes.push({ field: "วันสิ้นสุดสัญญา", before: oldLease, after: newLease });
  }
  return changes;
}

function isActiveStore(store: { active_status?: boolean | null }): boolean {
  return store.active_status !== false;
}

function formatTax(attr: AttrRow | null, sub: SubRow | null): string {
  if (!attr) return "(ยังไม่มี)";
  return sub ? `${attr.attribute_name} / ${sub.sub_attribute_name}` : attr.attribute_name;
}

function attrById(cache: TaxCache, id: string | null | undefined): AttrRow | null {
  if (!id) return null;
  return cache.locAttrs.find((a) => a.id === id) || cache.merchAttrs.find((a) => a.id === id) || null;
}

function subById(cache: TaxCache, attrId: string | null | undefined, subId: string | null | undefined): SubRow | null {
  if (!attrId || !subId) return null;
  return (cache.subsByAttr.get(attrId) || []).find((s) => s.id === subId) || null;
}

function currentTaxLabel(storeId: string, categoryId: string | undefined, cache: TaxCache, assignByStoreCat: Map<string, AssignRow>): string {
  if (!categoryId) return "(ยังไม่มี)";
  const existing = assignByStoreCat.get(`${storeId}:${categoryId}`);
  if (!existing) return "(ยังไม่มี)";
  const attr = attrById(cache, existing.attribute_id);
  return formatTax(attr, subById(cache, existing.attribute_id, existing.sub_attribute_id));
}

function desiredAssignments(tenant: Tenant, cache: TaxCache): DesiredTax[] {
  const out: DesiredTax[] = [];
  if (cache.locCatId && tenant.building) {
    const attr = findAttr(cache.locAttrs, tenant.building);
    if (attr) {
      let sub: SubRow | null = null;
      if (tenant.floors.length === 1) {
        sub = findSub(cache.subsByAttr.get(attr.id) || [], tenant.floors[0], SUBMERC_ALIASES);
      }
      out.push({ categoryId: cache.locCatId, attr, sub, field: "Location" });
    }
  }
  if (cache.merchCatId && tenant.merc) {
    const attr = findAttr(cache.merchAttrs, tenant.merc, MERC_TO_ATTR);
    if (attr) {
      let sub: SubRow | null = null;
      if (tenant.subMerc) {
        sub = findSub(cache.subsByAttr.get(attr.id) || [], tenant.subMerc, SUBMERC_ALIASES);
      }
      out.push({ categoryId: cache.merchCatId, attr, sub, field: "Merchandise" });
    }
  }
  return out;
}

function collectAttrChanges(
  store: any,
  tenant: Tenant,
  cache: TaxCache,
  assignByStoreCat: Map<string, AssignRow>,
): FieldChange[] {
  const changes: FieldChange[] = [];
  for (const d of desiredAssignments(tenant, cache)) {
    const existing = assignByStoreCat.get(`${store.id}:${d.categoryId}`);
    const same = existing
      && existing.attribute_id === d.attr.id
      && (existing.sub_attribute_id || null) === (d.sub?.id || null);
    if (same) continue;
    changes.push({
      field: d.field,
      before: currentTaxLabel(store.id, d.categoryId, cache, assignByStoreCat),
      after: formatTax(d.attr, d.sub),
    });
  }
  return changes;
}

function plannedNameAndActive(store: any, tenant: Tenant, expired: boolean): { nextName: string | null; nextActive: boolean | null } {
  const nextName = brandsMatch(store.store_name, tenant) && tenant.locs.length
    ? `${brandPart(store.store_name)} / ${tenant.locs.join(",")}`
    : null;
  const nextActive = expired && store.active_status !== false ? false : null;
  return { nextName, nextActive };
}

function storeHasOracleDiff(
  store: any,
  tenant: Tenant,
  expired: boolean,
  cache: TaxCache,
  assignByStoreCat: Map<string, AssignRow>,
): boolean {
  const { nextName, nextActive } = plannedNameAndActive(store, tenant, expired);
  return collectFieldChanges(store, tenant, nextName, nextActive).length > 0
    || collectAttrChanges(store, tenant, cache, assignByStoreCat).length > 0;
}

function htmlTable(headers: string[], rows: string[][]): string {
  const th = headers.map((h) =>
    `<th style="border:1px solid #ccc;padding:8px 10px;background:#f3f3f3;text-align:left;font-size:13px;">${escapeHtml(h)}</th>`
  ).join("");
  const trs = rows.map((r) =>
    `<tr>${r.map((c) => `<td style="border:1px solid #ccc;padding:8px 10px;font-size:13px;vertical-align:top;">${c}</td>`).join("")}</tr>`
  ).join("");
  return `<table cellpadding="0" cellspacing="0" border="0" width="100%" style="border-collapse:collapse;margin:12px 0 20px 0;">` +
    `<thead><tr>${th}</tr></thead><tbody>${trs || `<tr><td colspan="${headers.length}" style="border:1px solid #ccc;padding:8px 10px;">—</td></tr>`}</tbody></table>`;
}

function bangkokStamp(): string {
  return new Intl.DateTimeFormat("th-TH", {
    timeZone: "Asia/Bangkok",
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  }).format(new Date());
}

function buildReportHtml(args: {
  runId: string;
  dryRun: boolean;
  counts: Record<string, number>;
  skips: SkipBlock[];
  changes: ChangeBlock[];
  inserts: InsertBlock[];
  unchanged: number;
  fieldCounts: Record<string, number>;
}): string {
  const stamp = bangkokStamp();
  const skipCrmRows = args.skips.reduce((n, s) => n + s.stores.length, 0);
  const skippedDup = args.counts.skipped_duplicate || 0;
  const fieldRows = Object.entries(args.fieldCounts).map(([k, v]) => [escapeHtml(k), String(v)]);
  const fieldTotal = Object.values(args.fieldCounts).reduce((a, b) => a + b, 0);

  let skipHtml = "<p>ไม่มีรายการที่ต้องแจ้งในรอบนี้ — แสดงเฉพาะรหัสที่ร้าน active ซ้ำ และ Oracle ไม่ตรงกับ CRM</p>";
  if (args.skips.length) {
    skipHtml = args.skips.map((block) => {
      const headers = ["", "Oracle", ...block.stores.map((_: any, i: number) => `CRM แถวที่ ${i + 1}`)];
      const col = (oracle: string, crm: (s: any, i: number) => string) =>
        [escapeHtml(oracle), ...block.stores.map((s, i) => escapeHtml(crm(s, i)))];
      const rows = [
        ["รหัสร้าน", ...col("—", (s) => s.store_code || "")],
        ["ชื่อร้าน", ...col(block.tenant.tenaNameEN, (s) => s.store_name || "")],
        ["รหัสอ้างอิงภายนอก", ...col(block.tenant.customerNumber, (s) => s.external_ref || "")],
        ["รหัสพื้นที่", ...col(locKey(block.tenant.locs), (s) => locKey(crmLocs(s)) || "(ยังไม่มีในแถวนี้)")],
        ["Location", ...col(block.oracleLocation, (_s, i) => block.crmLocation[i] || "(ยังไม่มี)")],
        ["Merchandise", ...col(block.oracleMerchandise, (_s, i) => block.crmMerchandise[i] || "(ยังไม่มี)")],
        ["สถานะเปิดร้าน", ...col("—", (s) => statusLabel(s.active_status))],
        ["วันสิ้นสุดสัญญา", ...col(leaseKey(block.tenant.leaseEndDate) || "—", (s) => crmLease(s) || "(ยังไม่มีในแถวนี้)")],
      ];
      const names = [...new Set(block.stores.map((s: any) => brandPart(s.store_name)))].join(" / ");
      return `<h3 style="margin:20px 0 8px;">Customer Number <code>${escapeHtml(block.tenant.customerNumber)}</code> — ใน CRM มี ${block.stores.length} แถว active</h3>` +
        htmlTable(headers, rows) +
        `<p style="font-size:13px;">ข้อต่าง: Oracle เป็นร้านเดียว ชื่อ ${escapeHtml(block.tenant.tenaNameEN)} พื้นที่ ${escapeHtml(locKey(block.tenant.locs))} — CRM มี ${escapeHtml(names)} ใช้รหัสเดียวกัน ระบบไม่เขียน</p>`;
    }).join("");
  }

  const changeHtml = args.changes.length
    ? args.changes.map((c) => {
      const lis = c.changes.map((ch) =>
        `<li><b>${escapeHtml(ch.field)}:</b> ${escapeHtml(ch.before)} → ${escapeHtml(ch.after)}</li>`
      ).join("");
      return `<p style="margin:16px 0 4px;"><b>${escapeHtml(c.store_code)}</b> — ${escapeHtml(c.store_name)} — รหัสอ้างอิงภายนอก <code>${escapeHtml(c.external_ref)}</code></p><ul>${lis}</ul>`;
    }).join("")
    : "<p>ไม่มีร้านที่เปลี่ยนข้อมูลในรอบนี้</p>";

  const insertHtml = args.inserts.length
    ? htmlTable(
      ["รหัสร้าน", "ชื่อร้าน", "รหัสอ้างอิงภายนอก", "รหัสพื้นที่", "สถานะเปิดร้าน"],
      args.inserts.map((r) => [
        escapeHtml(r.store_code),
        escapeHtml(r.store_name),
        escapeHtml(r.external_ref),
        escapeHtml(r.locs),
        r.active ? "เปิด" : "ปิด",
      ]),
    )
    : "<p>ไม่มีร้านที่สร้างใหม่ในรอบนี้</p>";

  const dryNote = args.dryRun ? "<p><b>นี่คือรอบทดสอบ (dry-run) ไม่ได้เขียนลง CRM</b></p>" : "";

  return `<div style="font-family:Tahoma,Arial,sans-serif;font-size:14px;color:#222;line-height:1.45;">
<p>สวัสดีค่ะ</p>
<p>ซิงก์ร้านจาก Oracle E-Directory รอบเที่ยงคืนเสร็จแล้ว<br/>
รอบ: ${escapeHtml(stamp)} (เวลาไทย)<br/>
รหัสรอบ: <code>${escapeHtml(args.runId)}</code></p>
${dryNote}
<hr/>
<h2>1. สรุปตัวเลข</h2>
${htmlTable(["รายการ", "จำนวน"], [
    ["ยูนิตจาก Oracle", String(args.counts.oracle_units || 0)],
    ["ร้านตาม Customer Number", String(args.counts.oracle_tenants || 0)],
    ["จับคู่ได้และไม่เปลี่ยนข้อมูล", String(args.unchanged)],
    ["จับคู่ได้และมีการเปลี่ยน", String(args.changes.length)],
    ["สร้างร้านใหม่", String(args.inserts.length)],
    ["ปิดร้านเพราะสัญญาสิ้นสุด + 1 เดือน", String(args.counts.inactivated || 0)],
    ["ข้ามเพราะ Customer Number ซ้ำใน CRM (ร้าน active มากกว่า 1 แถว)", String(skippedDup)],
    ["ข้ามเพราะเป็นร้านยูทิลิตี้ OCR", String(args.counts.skipped_utility || 0)],
    ["ชื่อแบรนด์ไม่ตรง (อัปเดตอย่างอื่นได้ แค่ไม่แก้ชื่อ)", String(args.counts.skipped_brand_mismatch || 0)],
  ])}
<p>รวมข้ามเพราะรหัสซ้ำ (ร้าน active): <b>${skippedDup}</b> รหัส Oracle — แสดงรายละเอียดในข้อ 2 เฉพาะที่ข้อมูลไม่ตรง: <b>${args.skips.length}</b> รหัส / <b>${skipCrmRows}</b> แถว</p>
<hr/>
<h2>2. ข้าม ไม่ได้อัปเดต — Customer Number ซ้ำใน CRM</h2>
<p>นับเฉพาะร้านที่ <b>active</b> (ตัดร้านปิดออก) และแสดงรายละเอียดเฉพาะเมื่อข้อมูลจาก Oracle ไม่ตรงกับ CRM</p>
${skipHtml}
<hr/>
<h2>3. ร้านที่เปลี่ยน</h2>
${changeHtml}
<p>รวมร้านที่เปลี่ยน: <b>${args.changes.length}</b> ร้าน</p>
<hr/>
<h2>4. นับการเปลี่ยนรายฟิลด์</h2>
${htmlTable(["ฟิลด์", "จำนวน"], fieldRows.length ? fieldRows : [["—", "0"]])}
<p>รวมครั้งที่ฟิลด์เปลี่ยน: <b>${fieldTotal}</b></p>
<hr/>
<h2>5. ร้านที่สร้างใหม่</h2>
${insertHtml}
<p>รวมสร้างใหม่: <b>${args.inserts.length}</b> ร้าน</p>
<p>จบรายงานค่ะ</p>
</div>`;
}

async function sendReportEmail(subject: string, html: string): Promise<string | null> {
  const key = Deno.env.get("SENDGRID_API_KEY");
  if (!key) return "SENDGRID_API_KEY not configured";
  const res = await fetch("https://api.sendgrid.com/v3/mail/send", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      personalizations: [{ to: REPORT_EMAILS.map((email) => ({ email })) }],
      from: { email: "no-reply@rocket.in.th", name: "Rocket CRM" },
      subject,
      content: [{ type: "text/html", value: html }],
    }),
  });
  if (res.status === 202 || res.status === 200) return null;
  return `SendGrid error (${res.status}): ${await res.text()}`;
}

function isUtilityStore(store: { store_code?: string | null; store_name?: string | null }): boolean {
  const code = (store.store_code || "").trim();
  const name = store.store_name || "";
  if (/^FP-RW/i.test(code)) return true;
  if (["1234", "2001", "STK1", "PU3C", "BP122", "BP221", "CMVB", "CMVF"].includes(code)) return true;
  if (/PLZ\.|PL2\.|ACH\.|CRD\.|PKT\./i.test(name)) return false;
  return /booth\s*promotion|pop\s*up|exclusive lounge|member point|stock location|workshop|alive park|cascata|commonview|f-zpace|frontline location|^qa\s*$/i.test(
    name,
  );
}

function pickCanonical(rows: any[]): any {
  return [...rows].sort((a, b) => {
    const aAct = a.active_status === true ? 1 : 0;
    const bAct = b.active_status === true ? 1 : 0;
    if (bAct !== aAct) return bAct - aAct;
    return String(b.updated_at || "").localeCompare(String(a.updated_at || ""));
  })[0];
}

function groupTenants(rows: OracleRow[]): Tenant[] {
  const map = new Map<string, Tenant>();
  for (const r of rows) {
    const cn = String(r.CustomerNumber || "").trim();
    if (!cn) continue;
    const loc = String(r.LocationCode || "").trim();
    const floor = String(r.Floor || "").trim();
    const lease = r.LeaseEndDate ? String(r.LeaseEndDate) : null;
    const existing = map.get(cn);
    if (!existing) {
      map.set(cn, {
        customerNumber: cn,
        customerId: r.CustomerId ? String(r.CustomerId) : null,
        tenaNameEN: String(r.TenaNameEN || r.Customer2Dsc || r.CustomerName || cn).trim(),
        tenaNameTH: r.TenaNameTH ? String(r.TenaNameTH) : null,
        customer2Dsc: r.Customer2Dsc ? String(r.Customer2Dsc) : null,
        building: String(r.Building || "").trim(),
        floors: floor ? [floor] : [],
        locs: loc ? [loc] : [],
        merc: r.Merc ? String(r.Merc) : null,
        subMerc: r.SubMerc ? String(r.SubMerc) : null,
        lastUpdateDate: r.LastUpdateDate ? String(r.LastUpdateDate) : null,
        leaseEndDate: lease,
      });
      continue;
    }
    if (loc && !existing.locs.includes(loc)) existing.locs.push(loc);
    if (floor && !existing.floors.includes(floor)) existing.floors.push(floor);
    if (!existing.tenaNameEN && r.TenaNameEN) existing.tenaNameEN = String(r.TenaNameEN);
    if (r.LastUpdateDate && (!existing.lastUpdateDate || String(r.LastUpdateDate) > existing.lastUpdateDate)) {
      existing.lastUpdateDate = String(r.LastUpdateDate);
    }
    if (lease && (!existing.leaseEndDate || lease > existing.leaseEndDate)) {
      existing.leaseEndDate = lease;
    }
  }
  return [...map.values()];
}

function mergeMetadata(existing: unknown, patch: JsonRecord): JsonRecord {
  const base = existing && typeof existing === "object" && !Array.isArray(existing)
    ? { ...(existing as JsonRecord) }
    : {};
  return { ...base, ...patch };
}

function brandsMatch(storeName: string, tenant: Tenant): boolean {
  const current = norm(brandPart(storeName));
  const candidates = [tenant.tenaNameEN, tenant.customer2Dsc, tenant.tenaNameTH].map(norm).filter(Boolean);
  return candidates.some((c) => c === current || current.includes(c) || c.includes(current));
}

function directoryMetadata(tenant: Tenant): JsonRecord {
  return {
    edirectory_location_codes: tenant.locs,
    edirectory_customer_id: tenant.customerId,
    edirectory_last_update_date: tenant.lastUpdateDate,
    edirectory_building: tenant.building,
    edirectory_lease_end_date: tenant.leaseEndDate,
    edirectory_synced_at: new Date().toISOString(),
  };
}

async function loginOracle(baseUrl: string, username: string, password: string): Promise<string> {
  const res = await fetch(`${baseUrl.replace(/\/$/, "")}/api/Auth/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ username, password }),
  });
  if (!res.ok) throw new Error(`Oracle login HTTP ${res.status}`);
  const body = await res.json();
  if (!body?.token) throw new Error("Oracle login missing token");
  return body.token as string;
}

async function fetchOracleSync(baseUrl: string, token: string): Promise<OracleRow[]> {
  const res = await fetch(`${baseUrl.replace(/\/$/, "")}/api/EDirectory/sync`, {
    method: "GET",
    headers: { Authorization: `Bearer ${token}`, Accept: "application/json" },
  });
  if (!res.ok) throw new Error(`Oracle sync HTTP ${res.status}`);
  const body = await res.json();
  if (!body?.success || !Array.isArray(body.data)) throw new Error("Oracle sync payload unexpected");
  return body.data as OracleRow[];
}

function findAttr(list: AttrRow[], raw: string, aliases?: Record<string, string>): AttrRow | null {
  const key = matchKey(raw);
  if (!key) return null;
  const aliasCode = aliases?.[norm(raw)];
  for (const a of list) {
    if (matchKey(a.attribute_code) === key || matchKey(a.attribute_name) === key) return a;
    if (aliasCode && String(a.attribute_code).toUpperCase() === aliasCode.toUpperCase()) return a;
  }
  return null;
}

function findSub(list: SubRow[], raw: string, aliases?: Record<string, string>): SubRow | null {
  const wanted = aliases?.[norm(raw)] || raw;
  const key = matchKey(wanted);
  if (!key) return null;
  return list.find((s) => matchKey(s.sub_attribute_code) === key || matchKey(s.sub_attribute_name) === key) || null;
}

function uniqueCode(base: string, used: Set<string>): string {
  let code = base.slice(0, 50);
  if (!used.has(code)) return code;
  for (let i = 2; i < 100; i++) {
    const suffix = `_${i}`;
    code = `${base.slice(0, 50 - suffix.length)}${suffix}`;
    if (!used.has(code)) return code;
  }
  return `${base.slice(0, 42)}_${Date.now().toString().slice(-7)}`;
}

async function findOrCreateAttribute(
  sb: any,
  cache: TaxCache,
  kind: "LOCATION" | "MERCHANDISE",
  rawName: string,
): Promise<AttrRow | null> {
  const name = rawName.trim();
  if (!name) return null;
  const categoryId = kind === "LOCATION" ? cache.locCatId : cache.merchCatId;
  if (!categoryId) return null;
  const list = kind === "LOCATION" ? cache.locAttrs : cache.merchAttrs;
  const aliases = kind === "MERCHANDISE" ? MERC_TO_ATTR : undefined;
  const existing = findAttr(list, name, aliases);
  if (existing) return existing;

  const used = new Set(list.map((a) => a.attribute_code.toUpperCase()));
  const code = uniqueCode(slugCode(name), used);
  const insert = {
    merchant_id: cache.merchantId,
    category_id: categoryId,
    attribute_code: code,
    attribute_name: name.slice(0, 255),
    is_deleted: false,
  };
  const { data, error } = await sb.from("store_attributes").insert(insert).select("id, attribute_code, attribute_name, category_id").single();
  let row: AttrRow | null = data as AttrRow | null;
  if (error || !row) {
    const { data: found } = await sb
      .from("store_attributes")
      .select("id, attribute_code, attribute_name, category_id, is_deleted")
      .eq("merchant_id", cache.merchantId)
      .eq("category_id", categoryId)
      .eq("attribute_code", code)
      .maybeSingle();
    if (!found) {
      log(`create attribute ${kind} ${name}: ${error?.message || "missing after insert"}`);
      return null;
    }
    if (found.is_deleted) {
      await sb.from("store_attributes").update({ is_deleted: false, updated_at: new Date().toISOString() }).eq("id", found.id);
    }
    row = { id: found.id, attribute_code: found.attribute_code, attribute_name: found.attribute_name, category_id: found.category_id };
  } else {
    cache.createdAttributes += 1;
    log(`created ${kind} attribute ${row.attribute_code} (${name})`);
  }
  list.push(row);
  return row;
}

async function findOrCreateSubAttribute(
  sb: any,
  cache: TaxCache,
  attr: AttrRow,
  rawName: string,
): Promise<SubRow | null> {
  const name = rawName.trim();
  if (!name) return null;
  const list = cache.subsByAttr.get(attr.id) || [];
  const existing = findSub(list, name, SUBMERC_ALIASES);
  if (existing) return existing;

  const used = new Set(list.map((s) => s.sub_attribute_code.toUpperCase()));
  const code = uniqueCode(slugCode(name), used);
  const insert = {
    merchant_id: cache.merchantId,
    attribute_id: attr.id,
    sub_attribute_code: code,
    sub_attribute_name: name.slice(0, 255),
    is_deleted: false,
  };
  const { data, error } = await sb.from("store_sub_attributes").insert(insert).select("id, attribute_id, sub_attribute_code, sub_attribute_name").single();
  let row: SubRow | null = data as SubRow | null;
  if (error || !row) {
    const { data: found } = await sb
      .from("store_sub_attributes")
      .select("id, attribute_id, sub_attribute_code, sub_attribute_name, is_deleted")
      .eq("merchant_id", cache.merchantId)
      .eq("attribute_id", attr.id)
      .eq("sub_attribute_code", code)
      .maybeSingle();
    if (!found) {
      log(`create sub-attribute ${attr.attribute_code}/${name}: ${error?.message || "missing after insert"}`);
      return null;
    }
    if (found.is_deleted) {
      await sb.from("store_sub_attributes").update({ is_deleted: false, updated_at: new Date().toISOString() }).eq("id", found.id);
    }
    row = {
      id: found.id,
      attribute_id: found.attribute_id,
      sub_attribute_code: found.sub_attribute_code,
      sub_attribute_name: found.sub_attribute_name,
    };
  } else {
    cache.createdSubAttributes += 1;
    log(`created sub-attribute ${attr.attribute_code}/${row.sub_attribute_code} (${name})`);
  }
  list.push(row);
  cache.subsByAttr.set(attr.id, list);
  return row;
}

async function ensureTaxonomy(sb: any, cache: TaxCache, tenants: Tenant[]) {
  for (const tenant of tenants) {
    if (tenant.merc) {
      const attr = await findOrCreateAttribute(sb, cache, "MERCHANDISE", tenant.merc);
      if (attr && tenant.subMerc) await findOrCreateSubAttribute(sb, cache, attr, tenant.subMerc);
    }
    if (tenant.building) {
      const attr = await findOrCreateAttribute(sb, cache, "LOCATION", tenant.building);
      if (attr) {
        for (const floor of tenant.floors) {
          await findOrCreateSubAttribute(sb, cache, attr, floor);
        }
      }
    }
  }
}

Deno.serve(async (req) => {
  log(`=== CUSTOM-FUTUREPARK-EDIRECTORY-SYNC START (v${FUNCTION_VERSION}) ===`);
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  let merchantCode = DEFAULT_MERCHANT_CODE;
  let dryRun = false;
  let forceEmail = false;
  if (req.method === "POST") {
    try {
      const body = await req.json();
      if (body?.merchant_code) merchantCode = String(body.merchant_code);
      if (body?.dry_run === true) dryRun = true;
      if (body?.send_email === true) forceEmail = true;
    } catch (_) { /* cron body may be empty */ }
  }

  const { data: merchant, error: merchErr } = await sb
    .from("merchant_master")
    .select("id, merchant_code")
    .ilike("merchant_code", merchantCode)
    .maybeSingle();
  if (merchErr || !merchant) {
    return jsonResponse({ success: false, error: `merchant not found: ${merchantCode}` }, 400);
  }
  const merchantId = merchant.id as string;

  const { data: runRow, error: runErr } = await sb
    .from("custom_futurepark_edirectory_sync_runs")
    .insert({
      merchant_id: merchantId,
      status: "running",
      dry_run: dryRun,
    })
    .select("id")
    .single();
  if (runErr || !runRow) {
    return jsonResponse({ success: false, error: `failed to open run: ${runErr?.message}` }, 500);
  }
  const runId = runRow.id as string;

  const counts = {
    oracle_units: 0,
    oracle_tenants: 0,
    matched: 0,
    inserted: 0,
    updated: 0,
    inactivated: 0,
    skipped_utility: 0,
    skipped_brand_mismatch: 0,
    skipped_other: 0,
    skipped_duplicate: 0,
    unchanged: 0,
    created_attributes: 0,
    created_sub_attributes: 0,
  };
  const errors: string[] = [];

  try {
    const { data: credRow, error: credErr } = await sb
      .from("merchant_credentials")
      .select("credentials")
      .eq("merchant_id", merchantId)
      .eq("service_name", "edirectory")
      .eq("is_active", true)
      .maybeSingle();
    if (credErr || !credRow?.credentials) throw new Error("missing merchant_credentials.edirectory");
    const creds = credRow.credentials as { base_url?: string; username?: string; password?: string };
    const baseUrl = creds.base_url || Deno.env.get("CUSTOM_FUTUREPARK_EDIRECTORY_BASE_URL") || "";
    const username = creds.username || Deno.env.get("CUSTOM_FUTUREPARK_EDIRECTORY_USERNAME") || "";
    const password = creds.password || Deno.env.get("CUSTOM_FUTUREPARK_EDIRECTORY_PASSWORD") || "";
    if (!baseUrl || !username || !password) throw new Error("E-Directory credentials incomplete");

    const token = await loginOracle(baseUrl, username, password);
    const oracleRows = await fetchOracleSync(baseUrl, token);
    const tenants = groupTenants(oracleRows);
    counts.oracle_units = oracleRows.length;
    counts.oracle_tenants = tenants.length;
    log(`oracle units=${counts.oracle_units} tenants=${counts.oracle_tenants} dry_run=${dryRun}`);

    const allStores: any[] = await pageMerchantRows(sb, "store_master", STORE_SELECT, merchantId, "id");

    const byExternal = new Map<string, any[]>();
    const storeCodes = new Set<string>();
    for (const s of allStores) {
      storeCodes.add(String(s.store_code));
      const ext = String(s.external_ref || "").trim();
      if (!ext) continue;
      const list = byExternal.get(ext) || [];
      list.push(s);
      byExternal.set(ext, list);
    }

    const { data: locCat } = await sb
      .from("store_attribute_categories")
      .select("id")
      .eq("merchant_id", merchantId)
      .eq("attribute_category_code", "LOCATION")
      .maybeSingle();
    const { data: merchCat } = await sb
      .from("store_attribute_categories")
      .select("id")
      .eq("merchant_id", merchantId)
      .eq("attribute_category_code", "MERCHANDISE")
      .maybeSingle();
    const { data: locAttrs } = await sb
      .from("store_attributes")
      .select("id, attribute_code, attribute_name, category_id")
      .eq("merchant_id", merchantId)
      .eq("category_id", locCat?.id || "00000000-0000-0000-0000-000000000000")
      .eq("is_deleted", false);
    const { data: merchAttrs } = await sb
      .from("store_attributes")
      .select("id, attribute_code, attribute_name, category_id")
      .eq("merchant_id", merchantId)
      .eq("category_id", merchCat?.id || "00000000-0000-0000-0000-000000000000")
      .eq("is_deleted", false);
    const { data: allSubs } = await sb
      .from("store_sub_attributes")
      .select("id, attribute_id, sub_attribute_code, sub_attribute_name")
      .eq("merchant_id", merchantId)
      .eq("is_deleted", false);

    const cache: TaxCache = {
      merchantId,
      locCatId: locCat?.id,
      merchCatId: merchCat?.id,
      locAttrs: (locAttrs || []) as AttrRow[],
      merchAttrs: (merchAttrs || []) as AttrRow[],
      subsByAttr: new Map<string, SubRow[]>(),
      createdAttributes: 0,
      createdSubAttributes: 0,
    };
    for (const sub of (allSubs || []) as SubRow[]) {
      const list = cache.subsByAttr.get(sub.attribute_id) || [];
      list.push(sub);
      cache.subsByAttr.set(sub.attribute_id, list);
    }

    if (!dryRun) {
      await ensureTaxonomy(sb, cache, tenants);
      counts.created_attributes = cache.createdAttributes;
      counts.created_sub_attributes = cache.createdSubAttributes;
      log(`taxonomy created attributes=${counts.created_attributes} sub_attributes=${counts.created_sub_attributes}`);
    }

    const { count: assignCount, error: assignCountErr } = await sb
      .from("store_attribute_assignments")
      .select("id", { count: "exact", head: true })
      .eq("merchant_id", merchantId);
    if (assignCountErr) throw new Error(`assignments count: ${assignCountErr.message}`);
    const existingAssign = await pageMerchantRows(
      sb,
      "store_attribute_assignments",
      "id, store_id, category_id, attribute_id, sub_attribute_id",
      merchantId,
      "id",
    ) as AssignRow[];
    if (assignCount != null && existingAssign.length !== assignCount) {
      throw new Error(`assignments load incomplete: ${existingAssign.length} vs ${assignCount}`);
    }
    const assignByStoreCat = new Map<string, AssignRow>();
    for (const a of existingAssign) {
      assignByStoreCat.set(`${a.store_id}:${a.category_id}`, a);
    }
    if (assignByStoreCat.size !== existingAssign.length) {
      throw new Error(`assignments map collision: ${assignByStoreCat.size} vs ${existingAssign.length}`);
    }
    log(`assignments loaded=${existingAssign.length}`);

    const snapshots: JsonRecord[] = [];
    const inserts: JsonRecord[] = [];
    const insertTenants: Tenant[] = [];
    const skipBlocks: SkipBlock[] = [];
    const changeBlocks: ChangeBlock[] = [];
    const insertBlocks: InsertBlock[] = [];
    const fieldCounts: Record<string, number> = {
      "ชื่อร้าน": 0,
      "รหัสพื้นที่": 0,
      "สถานะเปิดร้าน": 0,
      "วันสิ้นสุดสัญญา": 0,
      Location: 0,
      Merchandise: 0,
    };

    for (const tenant of tenants) {
      const expired = leaseInactive(tenant.leaseEndDate);
      const matches = byExternal.get(tenant.customerNumber) || [];
      const activeMatches = matches.filter(isActiveStore);
      if (activeMatches.length > 1) {
        counts.skipped_duplicate += 1;
        if (activeMatches.some((store) => storeHasOracleDiff(store, tenant, expired, cache, assignByStoreCat))) {
          const desired = desiredAssignments(tenant, cache);
          const locD = desired.find((d) => d.field === "Location");
          const merchD = desired.find((d) => d.field === "Merchandise");
          skipBlocks.push({
            tenant,
            stores: activeMatches,
            oracleLocation: locD ? formatTax(locD.attr, locD.sub) : "—",
            oracleMerchandise: merchD ? formatTax(merchD.attr, merchD.sub) : "—",
            crmLocation: activeMatches.map((s) => currentTaxLabel(s.id, cache.locCatId, cache, assignByStoreCat)),
            crmMerchandise: activeMatches.map((s) => currentTaxLabel(s.id, cache.merchCatId, cache, assignByStoreCat)),
          });
        }
        continue;
      }
      if (activeMatches.length === 0 && matches.length > 0) {
        continue;
      }
      if (activeMatches.length === 0) {
        let code = `ed${tenant.customerNumber}`;
        if (storeCodes.has(code)) code = `ed${tenant.customerNumber}x`;
        const storeName = `${tenant.tenaNameEN} / ${tenant.locs.join(",")}`;
        inserts.push({
          merchant_id: merchantId,
          store_code: code,
          store_name: storeName,
          active_status: !expired,
          external_ref: tenant.customerNumber,
          mongo_id: null,
          manual_approve: false,
          is_reward_stock: false,
          metadata: {
            migration_source: "custom-futurepark-edirectory-sync",
            ...directoryMetadata(tenant),
          },
        });
        if (expired) counts.inactivated += 1;
        insertTenants.push(tenant);
        insertBlocks.push({
          store_code: code,
          store_name: storeName,
          external_ref: tenant.customerNumber,
          locs: locKey(tenant.locs),
          active: !expired,
        });
        storeCodes.add(code);
        continue;
      }

      const store = activeMatches[0];
      if (isUtilityStore(store)) {
        counts.skipped_utility += 1;
        continue;
      }

      counts.matched += 1;
      const patch: JsonRecord = {
        metadata: mergeMetadata(store.metadata, directoryMetadata(tenant)),
      };
      const { nextName, nextActive } = plannedNameAndActive(store, tenant, expired);
      if (nextName) {
        patch.store_name = nextName;
      } else if (!brandsMatch(store.store_name, tenant)) {
        counts.skipped_brand_mismatch += 1;
      }
      if (nextActive === false) {
        patch.active_status = false;
        counts.inactivated += 1;
      }

      const fieldChanges = [
        ...collectFieldChanges(store, tenant, nextName, nextActive),
        ...collectAttrChanges(store, tenant, cache, assignByStoreCat),
      ];
      if (fieldChanges.length) {
        changeBlocks.push({
          store_code: String(store.store_code),
          store_name: String(nextName || store.store_name || ""),
          external_ref: tenant.customerNumber,
          changes: fieldChanges,
        });
        for (const ch of fieldChanges) fieldCounts[ch.field] = (fieldCounts[ch.field] || 0) + 1;
      } else {
        counts.unchanged += 1;
      }

      if (!dryRun) {
        snapshots.push({
          merchant_id: merchantId,
          run_id: runId,
          store_id: store.id,
          external_ref: tenant.customerNumber,
          store_code: store.store_code,
          operation: "update",
          row_before: store,
        });
        const { error: updErr } = await sb
          .from("store_master")
          .update(patch)
          .eq("id", store.id)
          .eq("merchant_id", merchantId);
        if (updErr) {
          errors.push(`update ${store.store_code}: ${updErr.message}`);
          continue;
        }
        await syncStoreAttributes(sb, {
          merchantId,
          storeId: store.id,
          tenant,
          cache,
          assignByStoreCat,
        });
      }
      counts.updated += 1;
    }

    if (!dryRun && snapshots.length) {
      for (let i = 0; i < snapshots.length; i += 100) {
        const chunk = snapshots.slice(i, i + 100);
        const { error: snapErr } = await sb.from("custom_futurepark_edirectory_store_snapshots").insert(chunk);
        if (snapErr) errors.push(`snapshot chunk: ${snapErr.message}`);
      }
    }

    if (!dryRun && inserts.length) {
      for (let i = 0; i < inserts.length; i += 50) {
        const chunk = inserts.slice(i, i + 50);
        const tenantsChunk = insertTenants.slice(i, i + 50);
        const { data: created, error: insErr } = await sb
          .from("store_master")
          .insert(chunk)
          .select("id, store_code, external_ref");
        if (insErr) {
          errors.push(`insert chunk: ${insErr.message}`);
          continue;
        }
        counts.inserted += created?.length || 0;
        for (const row of created || []) {
          snapshots.push({
            merchant_id: merchantId,
            run_id: runId,
            store_id: row.id,
            external_ref: row.external_ref,
            store_code: row.store_code,
            operation: "insert",
            row_before: null,
          });
          const tenant = tenantsChunk.find((t) => t.customerNumber === row.external_ref);
          if (!tenant) continue;
          await syncStoreAttributes(sb, {
            merchantId,
            storeId: row.id,
            tenant,
            cache,
            assignByStoreCat,
          });
        }
      }
      const insertSnaps = snapshots.filter((s) => s.operation === "insert");
      if (insertSnaps.length) {
        for (let i = 0; i < insertSnaps.length; i += 100) {
          await sb.from("custom_futurepark_edirectory_store_snapshots").insert(insertSnaps.slice(i, i + 100));
        }
      }
    } else if (dryRun) {
      counts.inserted = inserts.length;
    }

    const cutoff = new Date(Date.now() - SNAPSHOT_RETENTION_DAYS * 86400000).toISOString();
    await sb.from("custom_futurepark_edirectory_store_snapshots").delete().lt("created_at", cutoff);

    const status = errors.length ? "completed_with_errors" : "completed";
    await sb.from("custom_futurepark_edirectory_sync_runs").update({
      status,
      oracle_units: counts.oracle_units,
      oracle_tenants: counts.oracle_tenants,
      matched: counts.matched,
      inserted: counts.inserted,
      updated: dryRun ? 0 : counts.updated,
      inactivated: dryRun ? 0 : counts.inactivated,
      skipped_utility: counts.skipped_utility,
      skipped_brand_mismatch: counts.skipped_brand_mismatch,
      skipped_other: counts.skipped_other,
      skipped_duplicate: counts.skipped_duplicate,
      error_summary: errors,
      finished_at: new Date().toISOString(),
    }).eq("id", runId);

    const syncOk = errors.length === 0;
    const shouldEmail = !dryRun || forceEmail;
    let emailError: string | null = null;
    if (shouldEmail) {
      const html = buildReportHtml({
        runId,
        dryRun,
        counts,
        skips: skipBlocks,
        changes: changeBlocks,
        inserts: insertBlocks,
        unchanged: counts.unchanged,
        fieldCounts,
      });
      const day = new Intl.DateTimeFormat("th-TH", { timeZone: "Asia/Bangkok", day: "numeric", month: "short", year: "numeric" }).format(new Date());
      const subject = `FuturePark E-Directory — สรุปซิงก์ร้าน ${day} 00:00`;
      emailError = await sendReportEmail(subject, html);
      if (emailError) {
        errors.push(`email: ${emailError}`);
        log(`email failed: ${emailError}`);
        await sb.from("custom_futurepark_edirectory_sync_runs").update({
          error_summary: errors,
        }).eq("id", runId);
      } else {
        log(`email sent to ${REPORT_EMAILS.join(",")}`);
      }
    }

    return jsonResponse({
      success: syncOk,
      version: FUNCTION_VERSION,
      dry_run: dryRun,
      run_id: runId,
      ...counts,
      skipped_duplicate: counts.skipped_duplicate,
      changed: changeBlocks.length,
      email_sent: shouldEmail && !emailError,
      email_error: emailError,
      errors,
    });
  } catch (error: any) {
    log(`FATAL: ${error.message}`);
    await sb.from("custom_futurepark_edirectory_sync_runs").update({
      status: "failed",
      error_summary: [error.message],
      finished_at: new Date().toISOString(),
      ...{
        oracle_units: counts.oracle_units,
        oracle_tenants: counts.oracle_tenants,
        matched: counts.matched,
        inserted: counts.inserted,
        updated: counts.updated,
        inactivated: counts.inactivated,
        skipped_utility: counts.skipped_utility,
        skipped_brand_mismatch: counts.skipped_brand_mismatch,
        skipped_other: counts.skipped_other,
        skipped_duplicate: counts.skipped_duplicate,
      },
    }).eq("id", runId);
    return jsonResponse({ success: false, run_id: runId, error: error.message, ...counts }, 500);
  }
});

async function syncStoreAttributes(
  sb: any,
  args: {
    merchantId: string;
    storeId: string;
    tenant: Tenant;
    cache: TaxCache;
    assignByStoreCat: Map<string, AssignRow>;
  },
) {
  for (const d of desiredAssignments(args.tenant, args.cache)) {
    const key = `${args.storeId}:${d.categoryId}`;
    const existing = args.assignByStoreCat.get(key);
    const next = {
      attribute_id: d.attr.id,
      sub_attribute_id: d.sub?.id || null,
    };
    if (!existing) {
      const { data, error } = await sb
        .from("store_attribute_assignments")
        .insert({
          merchant_id: args.merchantId,
          store_id: args.storeId,
          category_id: d.categoryId,
          attribute_id: next.attribute_id,
          sub_attribute_id: next.sub_attribute_id,
        })
        .select("id, store_id, category_id, attribute_id, sub_attribute_id")
        .single();
      if (!error && data) {
        args.assignByStoreCat.set(key, data as AssignRow);
        continue;
      }
      const dup = /duplicate key|store_attribute_assignments_merchant_id_store_id_category/i.test(
        error?.message || "",
      );
      if (!dup) {
        log(`insert attribute ${args.storeId} ${d.field}: ${error?.message}`);
        continue;
      }
      const { data: found } = await sb
        .from("store_attribute_assignments")
        .select("id, store_id, category_id, attribute_id, sub_attribute_id")
        .eq("merchant_id", args.merchantId)
        .eq("store_id", args.storeId)
        .eq("category_id", d.categoryId)
        .maybeSingle();
      if (!found) {
        log(`insert attribute ${args.storeId} ${d.field}: duplicate but row missing`);
        continue;
      }
      args.assignByStoreCat.set(key, found as AssignRow);
      if (
        found.attribute_id === next.attribute_id
        && (found.sub_attribute_id || null) === next.sub_attribute_id
      ) {
        continue;
      }
    }
    const row = args.assignByStoreCat.get(key);
    if (!row) continue;
    if (
      row.attribute_id === next.attribute_id
      && (row.sub_attribute_id || null) === next.sub_attribute_id
    ) {
      continue;
    }
    const { error } = await sb
      .from("store_attribute_assignments")
      .update({
        attribute_id: next.attribute_id,
        sub_attribute_id: next.sub_attribute_id,
      })
      .eq("id", row.id)
      .eq("merchant_id", args.merchantId);
    if (error) {
      log(`update attribute ${args.storeId} ${d.field}: ${error.message}`);
      continue;
    }
    args.assignByStoreCat.set(key, { ...row, ...next });
  }
}
