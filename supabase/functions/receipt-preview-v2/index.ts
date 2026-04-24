import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type'
};

const ROBOFLOW_API_URL = 'https://serverless.roboflow.com/rocket-crm/workflows/detect-and-classify-new-use-this-2';
const ROBOFLOW_API_KEY = 'QfgZMd7Ls56DCmQhY0JY';
const CLAUDE_API_URL = 'https://api.anthropic.com/v1/messages';
const CLAUDE_MODEL = 'claude-haiku-4-5';
const MIN_CONFIDENCE = 0.40;
const MAX_OCR_TEXT_LENGTH = 6000;
const CRM_API_BASE = Deno.env.get('CRM_INTERNAL_API_RECEIPT_URL_UAT') || 'https://crm-api.rocket-tech.app/receipt/api/v1';
const SAME_DAY_MERCHANTS = ['futurepark'];
const BANGKOK_OFFSET_MS = 7 * 60 * 60 * 1000;
const MAX_EVAL_BATCH_SIZE = 35;

const EVAL_FIELDS = [
  'store_name',
  'belongs_to_futurepark',
  'receipt_number',
  'receipt_datetime',
  'net_amount_after_discount',
  'payment_method'
];

// ─── Utilities ────────────────────────────────────────────────────────────────

function log(msg: string) { console.log(`[${new Date().toISOString()}] ${msg}`); }

function bffResponse(success: boolean, title: string, description: string | null, extra: Record<string, any>, status: number) {
  return new Response(JSON.stringify({ success, title, description, ...extra }), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
}

function stripBase64Prefix(base64: string): string { return base64.replace(/^data:image\/\w+;base64,/, ''); }
function isUrl(s: string): boolean { return s.startsWith('http://') || s.startsWith('https://'); }

function normalizeImageInput(image: string | { id?: string; base64?: string; url?: string }, index: number, batchId: string): { id: string; base64: string | null; url: string | null } {
  const genId = () => `file-${Date.now()}-${Math.random().toString(36).substring(2, 15)}`;
  if (typeof image === 'string') {
    if (isUrl(image)) return { id: genId(), base64: null, url: image };
    return { id: genId(), base64: image, url: null };
  }
  if (image.url) return { id: image.id || genId(), base64: null, url: image.url };
  return { id: image.id || genId(), base64: image.base64 || '', url: null };
}

function parseClarityCheck(a: any): { is_clear: boolean; clarity_reason: string | null } {
  try {
    if (!a?.output) return { is_clear: true, clarity_reason: null };
    let s = a.output;
    const m = s.match(/```json\n?([\s\S]*?)\n?```/) || s.match(/```\n?([\s\S]*?)\n?```/);
    if (m) s = m[1];
    const si = s.indexOf('{'); const ei = s.lastIndexOf('}');
    if (si !== -1 && ei !== -1) s = s.substring(si, ei + 1);
    const p = JSON.parse(s.trim());
    return { is_clear: p.is_clear === true, clarity_reason: p.is_clear ? null : (p.reason || 'Image quality insufficient') };
  } catch (e) { return { is_clear: true, clarity_reason: null }; }
}

function extractStringArray(field: any): string {
  if (Array.isArray(field)) return field.map((i: any) => typeof i === 'string' ? i : (i?.text || '')).filter(Boolean).join('\n---\n');
  if (typeof field === 'string') return field;
  if (field?.text) return field.text;
  return '';
}

function extractArrayValue(field: any): string | null {
  if (Array.isArray(field) && field.length > 0) return String(field[0]);
  if (typeof field === 'string') return field;
  return null;
}

function shuffleArray<T>(arr: T[]): T[] {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

// ─── Eval: field comparison ───────────────────────────────────────────────────

function compareField(field: string, expected: any, actual: any): boolean {
  if (expected === null || expected === undefined) return actual === null || actual === undefined;
  if (actual === null || actual === undefined) return false;
  if (field === 'net_amount_after_discount') {
    const expNum = parseFloat(String(expected));
    const actNum = parseFloat(String(actual));
    if (isNaN(expNum) || isNaN(actNum)) return String(expected) === String(actual);
    return Math.abs(expNum - actNum) <= 1;
  }
  if (field === 'receipt_datetime') {
    return String(expected).split('T')[0] === String(actual).split('T')[0];
  }
  if (field === 'receipt_number') {
    // OCR commonly reads dashes as spaces (and vice versa). Normalize both before comparing.
    const norm = (s: string) => s.replace(/[\s\-]/g, '').toUpperCase();
    return norm(String(expected)) === norm(String(actual));
  }
  if (field === 'store_name' || field === 'payment_method') {
    return String(expected).toLowerCase().trim() === String(actual).toLowerCase().trim();
  }
  return String(expected) === String(actual);
}

// ─── DB helpers ───────────────────────────────────────────────────────────────

async function getPrompts(supabase: any) {
  const [fp, amt] = await Promise.all([
    supabase.rpc('assemble_ocr_prompt', { p_key: 'is_futurepark' }),
    supabase.rpc('assemble_ocr_prompt', { p_key: 'net_amount_extraction' }),
  ]);
  return {
    futurepark_prompt: fp.data || 'Return JSON: store_name, branch_name, receipt_number, receipt_datetime, payment_method, belongs_to_futurepark. {{store_header_ocr}}',
    amount_prompt: amt.data || 'Return JSON: net_amount_after_discount, vat_amount, payment_method, items_count. {{sale_section_ocr}}'
  };
}

async function getMerchantIdByCode(sb: any, c: string) {
  const { data, error } = await sb.from('merchant_master').select('id').ilike('merchant_code', c.trim()).single();
  return error || !data ? null : data.id;
}

async function getStoreByCode(sb: any, mid: string, sc: string) {
  const { data, error } = await sb.from('store_master').select('id, store_code, store_name, external_ref').eq('merchant_id', mid).eq('store_code', sc).single();
  if (error || !data) return null;
  return { id: data.id, storeCode: data.store_code, storeName: data.store_name, externalRef: data.external_ref };
}

interface StoreOcrHint {
  receipt_number_example: string | null;
  receipt_date_raw_example: string | null;
  receipt_date_standardized_example: string | null;
  net_amount_label: string | null;
}

async function getStoreOcrHint(sb: any, mid: string, storeCode: string): Promise<StoreOcrHint | null> {
  if (!storeCode) return null;
  const { data } = await sb
    .from('custom_futurepark_store_ocr_hints')
    .select('receipt_number_example, receipt_date_raw_example, receipt_date_standardized_example, net_amount_label')
    .eq('merchant_id', mid)
    .eq('store_code', storeCode)
    .single();
  return data || null;
}

function buildStoreFutureparkHintText(hint: StoreOcrHint): string {
  const parts: string[] = [];
  if (hint.receipt_number_example) parts.push(`Receipt number format example: ${hint.receipt_number_example}`);
  if (hint.receipt_date_raw_example && hint.receipt_date_standardized_example) {
    // The note about "format only" prevents Claude from anchoring to the example year
    // when the actual receipt is from a different year (e.g. hint shows 2026, receipt is 2025).
    parts.push(`Date format example (year shown is a sample only — extract the ACTUAL year from the receipt): "${hint.receipt_date_raw_example}" → interpreted as "${hint.receipt_date_standardized_example}"`);
  }
  if (parts.length === 0) return '';
  return `\n\n--- Store-specific OCR hints ---\n${parts.join('\n')}`;
}

function buildStoreAmountHintText(hint: StoreOcrHint): string {
  if (!hint.net_amount_label) return '';
  return `\n\n--- Store-specific OCR hints ---\nNet amount label for this store: "${hint.net_amount_label}"`;
}

async function getCrmCredentials(sb: any, mid: string) {
  const { data, error } = await sb.from('merchant_credentials').select('credentials').eq('merchant_id', mid).eq('service_name', 'CRM_v1').single();
  if (error || !data?.credentials) return null;
  return { apiKey: data.credentials['rocket-access-token'] || data.credentials['x-api-key'], merchantId: data.credentials['rocket-merchant-id'], userId: data.credentials['rocket-user-id'] };
}

async function uploadToStorage(sb: any, base64: string, mid: string, bid: string, fid: string) {
  try {
    const d = stripBase64Prefix(base64);
    const b = atob(d);
    const u = new Uint8Array(b.length);
    for (let i = 0; i < b.length; i++) u[i] = b.charCodeAt(i);
    const safe = fid.replace(/[^a-zA-Z0-9-_]/g, '_');
    const path = `receipts/${mid}/${bid}/${safe}.jpg`;
    const { error } = await sb.storage.from('images').upload(path, u, { contentType: 'image/jpeg', upsert: true });
    if (error) return { url: null, error: error.message };
    const { data: urlData } = sb.storage.from('images').getPublicUrl(path);
    return { url: urlData.publicUrl, error: null };
  } catch (e: any) { return { url: null, error: String(e) }; }
}

// ─── Same-day helpers ─────────────────────────────────────────────────────────

function getTodayBangkok(): string {
  const now = new Date(Date.now() + BANGKOK_OFFSET_MS);
  return now.toISOString().split('T')[0];
}

function getReceiptDateBangkok(datetime: string): string | null {
  try {
    const d = new Date(datetime);
    if (isNaN(d.getTime())) return null;
    return new Date(d.getTime() + BANGKOK_OFFSET_MS).toISOString().split('T')[0];
  } catch { return null; }
}

// ─── OCR pipeline ─────────────────────────────────────────────────────────────

async function callRoboflow(imageInput: { base64?: string | null; url?: string | null }, fileId: string): Promise<{ result: any; error: string | null; rawKeys: string[] | null }> {
  try {
    const imagePayload = imageInput.url
      ? { type: 'url', value: imageInput.url }
      : { type: 'base64', value: stripBase64Prefix(imageInput.base64!) };
    log(`Roboflow ${fileId}: sending as ${imagePayload.type}`);
    const ROBOFLOW_MAX_RETRIES = 3;
    const ROBOFLOW_RETRY_DELAY_MS = [1000, 2500, 5000];
    const ROBOFLOW_ATTEMPT_TIMEOUT_MS = 25_000; // 25s per attempt — handles silent hangs
    let response: Response | null = null;
    let lastError = '';
    for (let attempt = 0; attempt < ROBOFLOW_MAX_RETRIES; attempt++) {
      if (attempt > 0) {
        await new Promise(r => setTimeout(r, ROBOFLOW_RETRY_DELAY_MS[attempt - 1]));
        log(`Roboflow ${fileId}: retry ${attempt}/${ROBOFLOW_MAX_RETRIES - 1}`);
      }
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), ROBOFLOW_ATTEMPT_TIMEOUT_MS);
      try {
        response = await fetch(ROBOFLOW_API_URL, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ api_key: ROBOFLOW_API_KEY, inputs: { image: imagePayload } }), signal: controller.signal });
      } catch (fetchErr: any) {
        clearTimeout(timeoutId);
        lastError = fetchErr.name === 'AbortError' ? `Roboflow timeout after ${ROBOFLOW_ATTEMPT_TIMEOUT_MS / 1000}s` : String(fetchErr);
        log(`Roboflow ${fileId} attempt ${attempt}: ${lastError}`);
        continue;
      }
      clearTimeout(timeoutId);
      if (response.ok) {
        const ct = response.headers.get('content-type') || '';
        if (!ct.includes('application/json') && !ct.includes('text/json')) {
          lastError = `Non-JSON response (content-type: ${ct}) — likely CDN error page`;
          log(`Roboflow ${fileId}: got 200 but content-type="${ct}", retrying`);
          continue;
        }
        break;
      }
      lastError = `API error: ${response.status}`;
      if (response.status !== 500 && response.status !== 503) break;
    }
    if (!response || !response.ok) return { result: null, error: lastError || `API error: ${response?.status}`, rawKeys: null };
    if (lastError.startsWith('Non-JSON response')) return { result: null, error: lastError, rawKeys: null };
    const result = await response.json();
    const output = Array.isArray(result) ? result[0] : result?.outputs?.[0];
    const rawKeys = output ? Object.keys(output) : [];
    log(`Roboflow ${fileId} raw keys: ${rawKeys.join(', ')}`);
    const { is_clear, clarity_reason } = parseClarityCheck(output?.anthropic_claude);
    const storeHeaderOcr = extractStringArray(output?.store_header_ocr).substring(0, MAX_OCR_TEXT_LENGTH);
    const saleSectionOcr = extractStringArray(output?.sale_section_ocr || output?.sale_amount_ocr).substring(0, MAX_OCR_TEXT_LENGTH);
    const amountRaw = extractArrayValue(output?.net_amount_after_discount);
    const roboflowAmount = amountRaw ? parseFloat(amountRaw.replace(/,/g, '')) : null;
    let pc: string | null = null; let pconf: number | null = null;
    const cls = output?.receipt_classification;
    if (Array.isArray(cls)) { for (const c of cls) { const p = c?.predictions; if (p?.top && p?.confidence > (pconf || 0)) { pc = p.top; pconf = p.confidence; } } }
    log(`Roboflow ${fileId}: clear=${is_clear}, class=${pc}, conf=${pconf}, store_ocr=${storeHeaderOcr.length}ch, sale_ocr=${saleSectionOcr.length}ch`);
    return { result: { fileId, store_header_ocr: storeHeaderOcr, sale_section_ocr: saleSectionOcr, roboflow_amount: isNaN(roboflowAmount as number) ? null : roboflowAmount, is_clear, clarity_reason, prediction_class: pc, prediction_confidence: pconf, store_header: output?.store_header ?? null, sale_amount_predictions: output?.sale_amount_predictions ?? null }, error: null, rawKeys };
  } catch (e: any) { return { result: null, error: String(e), rawKeys: null }; }
}

async function callClaude(prompt: string, key: string, imageUrl?: string | null): Promise<{ result: any; error: string | null; raw: string | null }> {
  try {
    const CLAUDE_TIMEOUT_MS = 45_000; // 45s — Claude Haiku is fast, hangs should time out well before Supabase's 150s wall clock
    const textContent = prompt.replace('{{receipt_image}}', imageUrl ? '[See attached receipt image]' : '[No image available]');
    const msgContent: any = imageUrl
      ? [{ type: 'image', source: { type: 'url', url: imageUrl } }, { type: 'text', text: textContent }]
      : textContent;
    const claudeController = new AbortController();
    const claudeTimeoutId = setTimeout(() => claudeController.abort(), CLAUDE_TIMEOUT_MS);
    let response: Response;
    try {
      response = await fetch(CLAUDE_API_URL, { method: 'POST', headers: { 'Content-Type': 'application/json', 'anthropic-version': '2023-06-01', 'x-api-key': key }, body: JSON.stringify({ model: CLAUDE_MODEL, max_tokens: 1024, messages: [{ role: 'user', content: msgContent }] }), signal: claudeController.signal });
    } catch (fetchErr: any) {
      clearTimeout(claudeTimeoutId);
      const msg = fetchErr.name === 'AbortError' ? `Claude timeout after ${CLAUDE_TIMEOUT_MS / 1000}s` : String(fetchErr);
      return { result: null, error: msg, raw: null };
    }
    clearTimeout(claudeTimeoutId);
    const rt = await response.text();
    if (response.status !== 200) {
      let msg = `Claude HTTP ${response.status}`;
      try { const e = JSON.parse(rt); msg = `Claude ${response.status} ${e?.error?.type || ''}: ${e?.error?.message || rt.substring(0, 300)}`; } catch (_) {}
      return { result: null, error: msg, raw: rt.substring(0, 500) };
    }
    const parsed = JSON.parse(rt);
    const content = parsed?.content?.[0]?.text || '';
    const s = content.indexOf('{'); const e = content.lastIndexOf('}');
    if (s === -1 || e === -1) return { result: null, error: 'No JSON in response', raw: content.substring(0, 500) };
    let extracted = JSON.parse(content.substring(s, e + 1));
    if (Array.isArray(extracted)) extracted = extracted[0];
    return { result: extracted, error: null, raw: content.substring(0, 500) };
  } catch (e: any) { return { result: null, error: `${e?.name || 'Error'}: ${e?.message || String(e)}`, raw: null }; }
}

function buildItem(robo: any, fp: any, amt: any) {
  const net = amt?.net_amount_after_discount ?? robo.roboflow_amount;
  return { fileId: robo.fileId, store_name: fp?.store_name || null, branch_name: fp?.branch_name || null, belongs_to_futurepark: fp?.belongs_to_futurepark || 'uncertain', receipt_number: fp?.receipt_number || null, receipt_datetime: fp?.receipt_datetime || null, net_amount_after_discount: typeof net === 'number' ? net : (net ? parseFloat(String(net).replace(/,/g, '')) : null), vat_amount: amt?.vat_amount ?? null, payment_method: amt?.payment_method || fp?.payment_method || null, items_count: amt?.items_count ?? null, is_clear: robo.is_clear, clarity_reason: robo.clarity_reason, prediction_class: robo.prediction_class, prediction_confidence: robo.prediction_confidence, store_header_ocr: robo.store_header_ocr, sale_section_ocr: robo.sale_section_ocr, store_header: robo.store_header, sale_amount_predictions: robo.sale_amount_predictions,
    _reasoning: { ...(fp?._reasoning || {}), ...(amt?._reasoning || {}) },
    _confidence: { ...(fp?._confidence || {}), ...(amt?._confidence || {}) },
    _date_debug: { raw: fp?._raw_date_from_ocr || null, month_token: fp?._month_token_from_middle || null, month_name: fp?._month_name || null },
  };
}

const IMAGE_CHECK_PROMPT = `You are inspecting a receipt image. Assess only whether you can see and read it.

Return ONLY this JSON, no other text:
{
  "can_see_image": <true if you can see any image content at all, false if missing or inaccessible>,
  "can_read_text": <true if receipt text is legible, false if unreadable>,
  "image_quality": <"clear" if fully readable, "partial" if some text is readable, "unreadable" if no text can be read>,
  "reason": <null if clear, otherwise brief reason e.g. "image too blurry", "image not accessible", "image is blank">
}`;

async function callClaudeImageCheck(imageUrl: string, key: string): Promise<{ can_see_image: boolean; can_read_text: boolean; image_quality: 'clear' | 'partial' | 'unreadable' | null; reason: string | null; error: string | null }> {
  const fallback = { can_see_image: false, can_read_text: false, image_quality: null as any, reason: null, error: null };
  try {
    const imgCheckController = new AbortController();
    const imgCheckTimeoutId = setTimeout(() => imgCheckController.abort(), 30_000);
    let response: Response;
    try {
      response = await fetch(CLAUDE_API_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'anthropic-version': '2023-06-01', 'x-api-key': key },
        body: JSON.stringify({ model: CLAUDE_MODEL, max_tokens: 256, messages: [{ role: 'user', content: [{ type: 'image', source: { type: 'url', url: imageUrl } }, { type: 'text', text: IMAGE_CHECK_PROMPT }] }] }),
        signal: imgCheckController.signal,
      });
    } catch (fetchErr: any) {
      clearTimeout(imgCheckTimeoutId);
      return { ...fallback, error: fetchErr.name === 'AbortError' ? 'Claude image-check timeout after 30s' : String(fetchErr) };
    }
    clearTimeout(imgCheckTimeoutId);
    const rt = await response.text();
    if (response.status !== 200) return { ...fallback, error: `Claude image check HTTP ${response.status}` };
    const parsed = JSON.parse(rt);
    const content = parsed?.content?.[0]?.text || '';
    const s = content.indexOf('{'); const e = content.lastIndexOf('}');
    if (s === -1 || e === -1) return { ...fallback, can_see_image: true, can_read_text: true, image_quality: 'clear' };
    const r = JSON.parse(content.substring(s, e + 1));
    return {
      can_see_image: r.can_see_image === true,
      can_read_text: r.can_read_text === true,
      image_quality: r.image_quality || null,
      reason: r.reason || null,
      error: null
    };
  } catch (e: any) { return { ...fallback, error: String(e) }; }
}

// Runs Roboflow + Claude on a single image URL — the shared OCR engine core.
async function runOcrOnImage(imageUrl: string, fileId: string, claudeKey: string, futureparkPrompt: string, amountPrompt: string, delayMs = 0, sb?: any, mid?: string): Promise<{ item: any; error: string | null; debug: any }> {
  const d: any = { fileId };
  const rf = await callRoboflow({ url: imageUrl }, fileId);
  if (!rf.result) return { item: null, error: rf.error, debug: d };
  d.roboflow_raw_keys = rf.rawKeys;
  d.sale_ocr_length = rf.result.sale_section_ocr.length;
  d.store_ocr_length = rf.result.store_header_ocr.length;
  d.roboflow_amount = rf.result.roboflow_amount;
  if (delayMs > 0) await new Promise(r => setTimeout(r, delayMs));

  // Fetch store-specific OCR hints using prediction_class from Roboflow
  let hint: StoreOcrHint | null = null;
  if (sb && mid && rf.result.prediction_class) {
    hint = await getStoreOcrHint(sb, mid, rf.result.prediction_class);
    if (hint) log(`Hint for ${rf.result.prediction_class}: receipt_no_ex=${hint.receipt_number_example}, net_label=${hint.net_amount_label}`);
  }

  const saleOcr = rf.result.sale_section_ocr;
  const storeHintText = hint ? buildStoreFutureparkHintText(hint) : '';
  const amountHintText = hint ? buildStoreAmountHintText(hint) : '';
  const fpp = futureparkPrompt.replace('{{store_header_ocr}}', rf.result.store_header_ocr + storeHintText);
  const saleOcrOrFallback = saleOcr.length > 0 ? saleOcr : '[Sale section OCR unavailable — extract net amount from image directly]';
  const ap = amountPrompt.replace('{{sale_section_ocr}}', saleOcrOrFallback + amountHintText);
  const [fpR, amtR, imgCheck] = await Promise.all([
    callClaude(fpp, claudeKey, imageUrl),
    ap ? callClaude(ap, claudeKey, imageUrl) : Promise.resolve(null),
    imageUrl ? callClaudeImageCheck(imageUrl, claudeKey) : Promise.resolve(null)
  ]);
  d.claude_fp_error = fpR.error; d.claude_fp_result = fpR.result;
  if (amtR) { d.claude_amt_error = amtR.error; d.claude_amt_result = amtR.result; d.claude_amt_raw = amtR.raw; }
  else { d.claude_amt_skipped = true; }
  d.image_check = imgCheck;
  const item = buildItem(rf.result, fpR.result, amtR?.result);
  item.image_readable = imgCheck?.can_see_image === true && imgCheck?.can_read_text === true;
  item.image_quality = imgCheck?.image_quality || null;
  item.image_readable_note = imgCheck?.reason || null;
  d.final_amount = item.net_amount_after_discount;

  // Roboflow-confidence fallback for belongs_to_futurepark.
  // Roboflow was trained exclusively on FuturePark receipts, so a confident
  // prediction_class is strong evidence the receipt is from FuturePark even
  // when the receipt itself prints no mall name (common for chain stores).
  const conf = item.prediction_confidence ?? 0;
  if (item.belongs_to_futurepark === 'uncertain' && item.prediction_class && conf >= MIN_CONFIDENCE) {
    item.belongs_to_futurepark = 'yes';
    log(`${fileId}: belongs_to_futurepark upgraded uncertain→yes (Roboflow class=${item.prediction_class}, conf=${conf.toFixed(2)})`);
  } else if (item.belongs_to_futurepark === 'no' && item.prediction_class && conf >= 0.70) {
    // High-confidence Roboflow hit on a store that Claude says is "no":
    // downgrade to "uncertain" rather than hard-rejecting, so it goes to admin review
    // instead of being permanently blocked as not_futurepark_receipt.
    item.belongs_to_futurepark = 'uncertain';
    log(`${fileId}: belongs_to_futurepark downgraded no→uncertain (Roboflow class=${item.prediction_class}, conf=${conf.toFixed(2)})`);
  }

  return { item, error: null, debug: d };
}

// ─── Approval rules ───────────────────────────────────────────────────────────

async function applyApprovalRules(sb: any, mid: string, items: any[], lang: string = 'en'): Promise<void> {
  const { data: rules } = await sb.from('receipt_approval_rules').select('id, rule_name, scope, attribute_code, min_amount').eq('merchant_id', mid).eq('active', true);
  if (!rules || rules.length === 0) return;
  const storeCodes = [...new Set(items.filter((i: any) => !i.error && !i.approval_required).map((i: any) => i.prediction_class).filter(Boolean))];
  if (storeCodes.length === 0) return;
  const { data: stores } = await sb.from('store_master').select('id, store_code').eq('merchant_id', mid).in('store_code', storeCodes);
  if (!stores || stores.length === 0) return;
  const storeIdByCode = new Map<string, string>();
  stores.forEach((s: any) => storeIdByCode.set(s.store_code, s.id));
  const storeIds = stores.map((s: any) => s.id);
  const { data: assignments } = await sb.from('store_attribute_assignments').select('store_id, attribute_id, category_id').in('store_id', storeIds);
  const attrsByStoreId = new Map<string, any[]>();
  if (assignments) { for (const a of assignments) { if (!attrsByStoreId.has(a.store_id)) attrsByStoreId.set(a.store_id, []); attrsByStoreId.get(a.store_id)!.push({ attribute_id: a.attribute_id, category_id: a.category_id }); } }
  const catCodeToId = new Map<string, string>(); const attrCodeToId = new Map<string, string>();
  const catCodes = rules.filter((r: any) => r.scope === 'category' && r.attribute_code).map((r: any) => r.attribute_code);
  const attrCodes = rules.filter((r: any) => r.scope === 'attribute' && r.attribute_code).map((r: any) => r.attribute_code);
  if (catCodes.length > 0) { const { data: cats } = await sb.from('store_attribute_categories').select('id, attribute_category_code').eq('merchant_id', mid).in('attribute_category_code', catCodes); if (cats) cats.forEach((c: any) => catCodeToId.set(c.attribute_category_code, c.id)); }
  if (attrCodes.length > 0) { const { data: attrs } = await sb.from('store_attributes').select('id, attribute_code').eq('merchant_id', mid).in('attribute_code', attrCodes); if (attrs) attrs.forEach((a: any) => attrCodeToId.set(a.attribute_code, a.id)); }
  const setCodes = rules.filter((r: any) => r.scope === 'set' && r.attribute_code).map((r: any) => r.attribute_code);
  const setCodeToId = new Map<string, string>();
  if (setCodes.length > 0) { const { data: sets } = await sb.from('store_attribute_sets').select('id, set_code').eq('merchant_id', mid).in('set_code', setCodes); if (sets) sets.forEach((s: any) => setCodeToId.set(s.set_code, s.id)); }
  const storeToSets = new Map<string, string[]>();
  if (setCodes.length > 0) { for (const storeId of storeIds) { const { data: storeSets } = await sb.rpc('get_store_attribute_sets', { store_id: storeId }); storeToSets.set(storeId, Array.isArray(storeSets) ? storeSets : []); } }
  const reviewTr: Record<string, string> = { en: 'Receipt is being reviewed', th: '\u0e43\u0e1a\u0e40\u0e2a\u0e23\u0e47\u0e08\u0e2d\u0e22\u0e39\u0e48\u0e23\u0e30\u0e2b\u0e27\u0e48\u0e32\u0e07\u0e15\u0e23\u0e27\u0e08\u0e2a\u0e2d\u0e1a', zh: '\u6536\u636e\u6b63\u5728\u5ba1\u6838\u4e2d', jp: '\u30ec\u30b7\u30fc\u30c8\u306f\u78ba\u8a8d\u4e2d\u3067\u3059' };
  const reason = reviewTr[lang] || reviewTr['en'];
  let reviewCount = 0;
  for (const item of items) {
    if (item.error || item.approval_required) continue;
    const storeCode = item.prediction_class;
    const amount = item.net_amount_after_discount || 0;
    const storeId = storeCode ? storeIdByCode.get(storeCode) : null;
    const attrs = storeId ? (attrsByStoreId.get(storeId) || []) : [];
    for (const rule of rules) {
      if (amount < rule.min_amount) continue;
      let matched = false;
      if (rule.scope === 'attribute' && rule.attribute_code) { const resolvedId = attrCodeToId.get(rule.attribute_code); matched = !!resolvedId && attrs.some((a: any) => a.attribute_id === resolvedId); }
      else if (rule.scope === 'category' && rule.attribute_code) { const resolvedId = catCodeToId.get(rule.attribute_code); matched = !!resolvedId && attrs.some((a: any) => a.category_id === resolvedId); }
      else if (rule.scope === 'global') { matched = true; }
      else if (rule.scope === 'set' && rule.attribute_code) { const rid = setCodeToId.get(rule.attribute_code); const storeSets = storeId ? (storeToSets.get(storeId) || []) : []; matched = !!rid && storeSets.includes(rid); }
      if (matched) { item.approval_required = true; item.approval_rule_name = rule.rule_name; item.failures = [...(item.failures || []), 'approval_required']; item.failures_translated = [...(item.failures_translated || []), reason]; if (!item.error_reason) { item.error_reason = 'approval_required'; item.error_reason_translated = reason; } reviewCount++; break; }
    }
  }
  if (reviewCount > 0) log(`Approval rules: ${reviewCount} items flagged for review`);
}

// ─── CRM helpers ──────────────────────────────────────────────────────────────

async function crmUpload(sb: any, creds: any, mid: string, data: any, url: string, uid: string) {
  try {
    const store = data.prediction_class ? await getStoreByCode(sb, mid, data.prediction_class) : null;
    const payload = { receipt_uid: crypto.randomUUID(), store_id: store?.externalRef || '', store_name: store?.storeName || data.store_name || '', estimated_point: 0, reference_receipt_id: data.receipt_number || '', remark: 'Auto-uploaded v3', receipt_image_urls: [url], user_id: uid, receipt_date: data.receipt_datetime?.split('T')[0] || new Date().toISOString().split('T')[0], total_amount: (data.net_amount_after_discount || 0).toString(), products: [], receipt_properties: [] };
    const r = await fetch(`${CRM_API_BASE}/receipt-upload-templates`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'rocket-access-token': creds.apiKey, 'rocket-merchant-id': creds.merchantId, 'rocket-user-id': creds.userId }, body: JSON.stringify(payload) });
    return { success: r.ok, data: await r.json() };
  } catch (e: any) { return { success: false, error: String(e) }; }
}

async function crmPreview(creds: any, uid: string) {
  try {
    const r = await fetch(`${CRM_API_BASE}/receipt-upload-templates?limit=100&page=1&user_id=${uid}`, { headers: { 'rocket-merchant-id': creds.merchantId, 'rocket-user-id': creds.userId } });
    return { success: r.ok, data: await r.json() };
  } catch (e: any) { return { success: false, error: String(e) }; }
}

// ─── Handler ──────────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  const t0 = Date.now();
  log('=== RECEIPT PREVIEW V2 START (v56) ===');
  if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders });

  try {
    const sbUrl = Deno.env.get('SUPABASE_URL')!;
    const sbKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const claudeKey = Deno.env.get('ANTHROPIC_X_API_KEY');
    if (!claudeKey) return bffResponse(false, 'Configuration error', 'Anthropic API key not configured', {}, 500);

    const sb = createClient(sbUrl, sbKey);
    const body = await req.json();
    const { merchant_code, external_user_ref, images, language = 'en', mode = 'quick', check_date = true } = body;

    if (!merchant_code) return bffResponse(false, 'Missing required fields', 'Required: merchant_code', {}, 400);

    const mid = await getMerchantIdByCode(sb, merchant_code);
    if (!mid) return bffResponse(false, 'Merchant not found', `Invalid merchant_code: ${merchant_code}`, {}, 400);

    const { futurepark_prompt, amount_prompt } = await getPrompts(sb);

    // ── EVAL MODE ─────────────────────────────────────────────────────────────
    if (mode === 'eval') {
      const { store_code, random: randomMode = false, limit: qLimit, tags_filter } = body;
      const effectiveLimit = Math.min(qLimit || MAX_EVAL_BATCH_SIZE, MAX_EVAL_BATCH_SIZE);
      let selectionDesc = '';
      let groundTruth: any[] = [];

      if (store_code) {
        const storeCodes = Array.isArray(store_code) ? store_code : [store_code];
        selectionDesc = `store_code=${storeCodes.join(',')}`;
        const { data: allRows, error: gtError } = await sb.from('custom_futurepark_receipt_groundtruth').select('id, image_url, correct_result, tags').eq('merchant_id', mid).eq('is_active', true);
        if (gtError) return bffResponse(false, 'Failed to load ground truth', gtError.message, {}, 500);
        if (!allRows || allRows.length === 0) return bffResponse(false, 'No ground truth data', 'No active test cases found', {}, 404);
        let filtered = allRows.filter((r: any) => storeCodes.includes(r.correct_result?.prediction_class));
        if (filtered.length === 0) return bffResponse(false, 'No matching test cases', `No ground truth rows with store_code in [${storeCodes.join(', ')}]`, {}, 404);
        if (randomMode) { filtered = shuffleArray(filtered); selectionDesc += ', random'; }
        groundTruth = filtered.slice(0, effectiveLimit);
        selectionDesc += `, ${groundTruth.length}/${filtered.length} available`;

      } else if (randomMode) {
        selectionDesc = 'random';
        let query = sb.from('custom_futurepark_receipt_groundtruth').select('id, image_url, correct_result, tags').eq('merchant_id', mid).eq('is_active', true);
        if (tags_filter && Array.isArray(tags_filter)) { query = query.overlaps('tags', tags_filter); selectionDesc += `, tags=${tags_filter.join(',')}`; }
        const { data: allRows, error: gtError } = await query;
        if (gtError) return bffResponse(false, 'Failed to load ground truth', gtError.message, {}, 500);
        if (!allRows || allRows.length === 0) return bffResponse(false, 'No ground truth data', 'No active test cases found', {}, 404);
        groundTruth = shuffleArray(allRows).slice(0, effectiveLimit);
        selectionDesc += `, ${groundTruth.length}/${allRows.length} available`;

      } else {
        selectionDesc = 'sequential';
        let query = sb.from('custom_futurepark_receipt_groundtruth').select('id, image_url, correct_result, tags').eq('merchant_id', mid).eq('is_active', true).order('created_at', { ascending: true }).limit(effectiveLimit);
        if (tags_filter && Array.isArray(tags_filter)) { query = query.overlaps('tags', tags_filter); selectionDesc += `, tags=${tags_filter.join(',')}`; }
        const { data: rows, error: gtError } = await query;
        if (gtError) return bffResponse(false, 'Failed to load ground truth', gtError.message, {}, 500);
        if (!rows || rows.length === 0) return bffResponse(false, 'No ground truth data', 'No active test cases found', {}, 404);
        groundTruth = rows;
        selectionDesc += `, ${groundTruth.length} cases`;
      }

      log(`Eval: ${groundTruth.length} test cases (${selectionDesc})`);

      const byField: Record<string, { pass: number; fail: number }> = {};
      for (const f of EVAL_FIELDS) byField[f] = { pass: 0, fail: 0 };
      const failures: any[] = [];
      const perCase: any[] = [];
      let totalPassed = 0; let totalFailed = 0;

      for (let i = 0; i < groundTruth.length; i++) {
        const tc = groundTruth[i];
        const storeName = tc.correct_result?.store_name || 'unknown';
        log(`[${i + 1}/${groundTruth.length}] ${storeName}`);

        const { item, error } = await runOcrOnImage(tc.image_url, `eval-${i}`, claudeKey, futurepark_prompt, amount_prompt, i > 0 ? 300 : 0, sb, mid);

        if (error || !item) {
          log(`  ERROR: ${error}`);
          totalFailed++;
          perCase.push({ image_url: tc.image_url, store_name: storeName, store_code: tc.correct_result?.prediction_class || null, error, passed: false, fields: {} });
          for (const f of EVAL_FIELDS) byField[f].fail++;
          continue;
        }

        let casePassed = true;
        const caseFields: Record<string, any> = {};
        for (const field of EVAL_FIELDS) {
          const expected = tc.correct_result[field];
          const actual = item[field];
          const pass = compareField(field, expected, actual);
          byField[field][pass ? 'pass' : 'fail']++;
          caseFields[field] = { expected: expected ?? null, actual: actual ?? null, pass };
          if (!pass) { casePassed = false; failures.push({ image_url: tc.image_url, store_name: storeName, store_code: tc.correct_result?.prediction_class || null, field, expected: expected ?? null, actual: actual ?? null }); }
        }

        if (casePassed) totalPassed++; else totalFailed++;
        perCase.push({
          image_url: tc.image_url, store_name: storeName, store_code: tc.correct_result?.prediction_class || null,
          passed: casePassed, fields: caseFields,
          image_check: { readable: item.image_readable, quality: item.image_quality, note: item.image_readable_note }
        });
      }

      const totalCases = groundTruth.length;
      const overallAccuracy = totalCases > 0 ? Math.round((totalPassed / totalCases) * 10000) / 10000 : 0;
      const resultSummary: Record<string, any> = {};
      for (const [field, counts] of Object.entries(byField)) {
        const total = counts.pass + counts.fail;
        resultSummary[field] = { pass: counts.pass, fail: counts.fail, accuracy: total > 0 ? Math.round((counts.pass / total) * 10000) / 10000 : 0 };
      }

      const durationMs = Date.now() - t0;
      const { data: runData } = await sb.from('custom_futurepark_ocr_eval_runs').insert({
        merchant_id: mid,
        total_cases: totalCases,
        passed_cases: totalPassed,
        failed_cases: totalFailed,
        overall_accuracy: overallAccuracy,
        result_summary: resultSummary,
        failures,
        prompt_snapshot: {
          is_futurepark: futurepark_prompt.substring(0, 500) + '...',
          net_amount_extraction: amount_prompt.substring(0, 500) + '...'
        },
        run_duration_ms: durationMs,
        notes: selectionDesc
      }).select('id').single();

      log(`=== EVAL DONE in ${durationMs}ms — ${totalPassed}/${totalCases} passed (${Math.round(overallAccuracy * 100)}%) ===`);

      return bffResponse(true, 'Evaluation complete', `${totalPassed}/${totalCases} cases passed (${Math.round(overallAccuracy * 100)}%)`, {
        mode: 'eval',
        selection: selectionDesc,
        run_id: runData?.id || null,
        summary: { total_cases: totalCases, passed: totalPassed, failed: totalFailed, overall_accuracy: overallAccuracy, by_field: resultSummary },
        failures,
        per_case: perCase,
        duration_ms: durationMs
      }, 200);
    }

    // ── QUICK / FULL MODE ─────────────────────────────────────────────────────

    if (!images || !Array.isArray(images)) return bffResponse(false, 'Missing required fields', 'Required: images[]', {}, 400);
    if (images.length === 0) return bffResponse(false, 'No images provided', null, {}, 400);
    if (mode === 'full' && !external_user_ref) return bffResponse(false, 'Missing required field', 'external_user_ref required for full mode', {}, 400);

    let creds = null;
    if (mode === 'full') { creds = await getCrmCredentials(sb, mid); if (!creds?.apiKey) return bffResponse(false, 'Configuration error', 'CRM credentials not configured', {}, 400); }

    const bid = crypto.randomUUID();
    const results: any[] = []; const urlMap = new Map<string, string>(); const errs: any[] = []; const dbg: any[] = [];
    const imgs = images.map((img: any, idx: number) => normalizeImageInput(img, idx, bid));
    log(`Processing ${imgs.length} images, mode=${mode}, check_date=${check_date}`);

    if (mode === 'full') {
      for (const { id, base64, url } of imgs) {
        if (url) { urlMap.set(id, url); log(`Image ${id}: using provided URL`); }
        else { const r = await uploadToStorage(sb, base64!, mid, bid, id); if (r.url) urlMap.set(id, r.url); else errs.push({ fileId: id, error: 'storage_upload_failed', error_details: r.error }); }
      }
    }

    for (let i = 0; i < imgs.length; i++) {
      const img = imgs[i];
      if (errs.some(e => e.fileId === img.id)) continue;
      const imageUrl = urlMap.get(img.id) || img.url || null;
      const { item, error: ocrErr, debug } = await runOcrOnImage(
        imageUrl || img.url || '',
        img.id,
        claudeKey,
        futurepark_prompt,
        amount_prompt,
        i > 0 ? 300 : 0,
        sb,
        mid
      );
      if (ocrErr || !item) {
        errs.push({ fileId: img.id, error: 'roboflow_failed', error_details: ocrErr, image_url: imageUrl });
        dbg.push(debug);
        continue;
      }
      // Override fileId in case runOcrOnImage set it differently
      item.fileId = img.id;
      results.push(item);
      dbg.push({ ...debug, amount_ocr_used: item.sale_section_ocr?.length > 0 ? 'sale_section_ocr' : 'NONE' });
      log(`Done ${img.id}: fp=${item.belongs_to_futurepark}, amt=${item.net_amount_after_discount}`);
    }

    const checkSameDay = check_date && SAME_DAY_MERCHANTS.some(m => merchant_code.toLowerCase().includes(m));
    const todayBkk = checkSameDay ? getTodayBangkok() : null;
    if (!check_date) log('Same-day check DISABLED via check_date=false');

    const tr: Record<string, Record<string, string>> = {
      'duplicate_receipt': { 'en': 'Duplicate receipt', 'th': '\u0e43\u0e1a\u0e40\u0e2a\u0e23\u0e47\u0e08\u0e0b\u0e49\u0e33' },
      'not_futurepark_receipt': { 'en': 'Not a Future Park receipt', 'th': '\u0e44\u0e21\u0e48\u0e43\u0e0a\u0e48\u0e43\u0e1a\u0e40\u0e2a\u0e23\u0e47\u0e08\u0e1f\u0e34\u0e27\u0e40\u0e08\u0e2d\u0e23\u0e4c\u0e1e\u0e32\u0e23\u0e4c\u0e04' },
      'uncertain_futurepark': { 'en': 'Cannot verify Future Park receipt', 'th': '\u0e44\u0e21\u0e48\u0e2a\u0e32\u0e21\u0e32\u0e23\u0e16\u0e22\u0e37\u0e19\u0e22\u0e31\u0e19\u0e43\u0e1a\u0e40\u0e2a\u0e23\u0e47\u0e08' },
      'low_confidence': { 'en': 'Could not identify store', 'th': '\u0e44\u0e21\u0e48\u0e2a\u0e32\u0e21\u0e32\u0e23\u0e16\u0e23\u0e30\u0e1a\u0e38\u0e23\u0e49\u0e32\u0e19\u0e04\u0e49\u0e32' },
      'unclear_image': { 'en': 'Unclear image', 'th': '\u0e20\u0e32\u0e1e\u0e44\u0e21\u0e48\u0e0a\u0e31\u0e14\u0e40\u0e08\u0e19' },
      'extraction_failed': { 'en': 'Could not extract receipt data', 'th': '\u0e44\u0e21\u0e48\u0e2a\u0e32\u0e21\u0e32\u0e23\u0e16\u0e2d\u0e48\u0e32\u0e19\u0e02\u0e49\u0e2d\u0e21\u0e39\u0e25\u0e43\u0e1a\u0e40\u0e2a\u0e23\u0e47\u0e08' },
      'receipt_not_same_day': { 'en': 'Receipt date does not match today', 'th': '\u0e27\u0e31\u0e19\u0e17\u0e35\u0e48\u0e43\u0e19\u0e43\u0e1a\u0e40\u0e2a\u0e23\u0e47\u0e08\u0e44\u0e21\u0e48\u0e15\u0e23\u0e07\u0e01\u0e31\u0e1a\u0e27\u0e31\u0e19\u0e19\u0e35\u0e49' }
    };
    const tl = (c: string, l: string) => tr[c]?.[l] || tr[c]?.['en'] || c;

    const fin = results.map(item => {
      const f: string[] = [];
      if (item.is_clear === false) f.push('unclear_image');
      if (item.receipt_datetime && item.net_amount_after_discount && results.some(o => o.fileId !== item.fileId && o.receipt_datetime === item.receipt_datetime && o.net_amount_after_discount === item.net_amount_after_discount)) f.push('duplicate_receipt');
      if (item.belongs_to_futurepark === 'no') f.push('not_futurepark_receipt');
      if (item.belongs_to_futurepark === 'uncertain') f.push('uncertain_futurepark');
      if (item.prediction_confidence !== null && item.prediction_confidence < MIN_CONFIDENCE) f.push('low_confidence');
      if (checkSameDay && todayBkk && item.receipt_datetime) { const rd = getReceiptDateBangkok(item.receipt_datetime); if (rd && rd !== todayBkk) { f.push('receipt_not_same_day'); log(`Same-day check failed: receipt=${rd}, today=${todayBkk}`); } }
      const url = urlMap.get(item.fileId) || null;
      const he = f.length > 0;
      return { ...item, id: item.fileId, image_url: url, error: he, failures: f, failures_translated: f.map(c => tl(c, language)), error_reason: he ? f[0] : null, error_reason_translated: he ? tl(f[0], language) : null };
    });

    errs.forEach(err => { fin.push({ fileId: err.fileId, id: err.fileId, image_url: err.image_url || null, is_clear: true, error: true, failures: [err.error], failures_translated: [err.error_details || err.error], error_reason: err.error, error_reason_translated: err.error_details || err.error }); });

    await applyApprovalRules(sb, mid, fin, language);

    const pc = fin.filter(r => !r.error && !r.approval_required).length;
    const fc = fin.filter(r => r.error).length;
    const rc = fin.filter(r => r.approval_required).length;

    let crm = null;
    if (mode === 'full' && creds && external_user_ref) {
      const pi = fin.filter(r => !r.error && !r.approval_required);
      for (const item of pi) { item.crm_upload_result = await crmUpload(sb, creds, mid, item, item.image_url, external_user_ref); }
      if (pi.length > 0) {
        const pv = await crmPreview(creds, external_user_ref);
        if (pv.success) { crm = pv.data; const tpls = crm?.data?.receipt_templates || []; pi.forEach((r: any) => { const t = tpls.find((t: any) => t.receipt_image_urls?.some((u: string) => u === r.image_url)); r.crm_estimated_points = t?.estimated_point || 0; if (t) r.crm_template_id = t.template_id; }); }
      }
    }

    log(`=== DONE in ${Date.now() - t0}ms ===`);
    return bffResponse(true, 'Receipt preview complete', null, {
      mode,
      batch_id: bid,
      summary: { total: images.length, passed: pc, failed: fc, approval_required: rc },
      results: fin,
      _debug: { version: 56, items: dbg },
      crm_batch_preview: mode === 'full' ? crm : null
    }, 200);

  } catch (error: any) {
    log(`FATAL: ${error?.name}: ${error?.message}`);
    return bffResponse(false, 'System error', `${error?.name || 'Error'}: ${error?.message || String(error)}`, { _debug: { fatal: true, version: 56 } }, 500);
  }
});
