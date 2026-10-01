import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";
import { reversePointsBurn } from "../_shared/shopify-points-reversal.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-shopify-points-sweep-secret",
};
const REFRESH_WINDOW_MS = 5 * 60 * 1000;
const ENTITLEMENT_WINDOW_MS = 24 * 60 * 60 * 1000;
/**
 * Burns before this date used metafield delivery, whose single per-customer
 * entitlement slot is overwritten by each later redemption — usage can no longer
 * be established for them, so they are out of scope permanently.
 */
const SWEEP_MIN_CREATED_AT = Deno.env.get("SHOPIFY_POINTS_SWEEP_SINCE") ?? "2026-10-01T00:00:00Z";

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

function authorize(req: Request): boolean {
  const expected = Deno.env.get("SHOPIFY_POINTS_SWEEP_SECRET");
  if (!expected) return true;
  const header = req.headers.get("x-shopify-points-sweep-secret") ?? "";
  return header === expected;
}

function toIsoFromSeconds(seconds?: number): string | null {
  return !seconds || Number.isNaN(seconds) ? null : new Date(Date.now() + seconds * 1000).toISOString();
}

function isNearExpiry(credentials: Record<string, any>): boolean {
  if (credentials.token_mode !== "offline_expiring" || !credentials.refresh_token) return false;
  if (!credentials.expires_at) return true;
  const expiresAt = new Date(credentials.expires_at).getTime();
  return Number.isNaN(expiresAt) || expiresAt <= Date.now() + REFRESH_WINDOW_MS;
}

async function refreshShopifyToken(supabase: any, record: any) {
  const credentials = record.credentials || {};
  const shopDomain = credentials.shop_domain;
  const apiKey = credentials.api_key || Deno.env.get("SHOPIFY_API_KEY");
  const apiSecret = credentials.api_secret || Deno.env.get("SHOPIFY_API_SECRET");
  if (!shopDomain || !apiKey || !apiSecret || !credentials.refresh_token) throw new Error("Shopify credential requires admin reauth");
  const body = new URLSearchParams();
  body.set("client_id", apiKey);
  body.set("grant_type", "refresh_token");
  body.set("client_secret", apiSecret);
  body.set("refresh_token", credentials.refresh_token);
  const response = await fetch(`https://${shopDomain}/admin/oauth/access_token`, { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded", Accept: "application/json" }, body });
  const data = await response.json().catch(() => ({}));
  if (!response.ok || !data.access_token || !data.refresh_token) throw new Error(data.error_description || data.error || "refresh failed");
  const expiresAt = toIsoFromSeconds(data.expires_in);
  const nextCredentials = { ...credentials, access_token: data.access_token, refresh_token: data.refresh_token, token_mode: "offline_expiring", expires_at: expiresAt, health_status: "healthy", last_health_check: new Date().toISOString(), token_updated_at: new Date().toISOString() };
  await supabase.from("merchant_credentials").update({ credentials: nextCredentials, expires_at: expiresAt, health_status: "healthy", last_health_check: new Date().toISOString(), updated_at: new Date().toISOString() }).eq("id", record.id);
  return { ...record, credentials: nextCredentials };
}

async function getShopifyCredential(supabase: any, merchantId: string) {
  const { data, error } = await supabase.from("merchant_credentials").select("id, credentials").eq("merchant_id", merchantId).eq("service_name", "shopify_app").eq("is_active", true).single();
  if (error || !data) throw new Error("No active Shopify credentials");
  if (isNearExpiry(data.credentials || {})) return await refreshShopifyToken(supabase, data);
  return data;
}

async function shopifyGraphql(supabase: any, record: any, query: string, variables: Record<string, unknown>) {
  let current = record;
  const call = () => fetch(`https://${current.credentials.shop_domain}/admin/api/2024-04/graphql.json`, { method: "POST", headers: { "X-Shopify-Access-Token": current.credentials.access_token, "Content-Type": "application/json" }, body: JSON.stringify({ query, variables }) });
  let response = await call();
  if (response.status === 401 && current.credentials?.refresh_token) {
    current = await refreshShopifyToken(supabase, current);
    response = await call();
  }
  const body = await response.json().catch(() => ({}));
  return { response, body, credential: current };
}

const CODE_USAGE_QUERY = `
query PointsDiscountUsage($id: ID!) {
  codeDiscountNode(id: $id) {
    id
    codeDiscount {
      ... on DiscountCodeBasic {
        asyncUsageCount
      }
    }
  }
}`;

type BurnRow = {
  id: string;
  user_id: string;
  merchant_id: string;
  amount: number;
  source_id: string | null;
  created_at: string;
  metadata: Record<string, unknown> | null;
};

function windowEnd(row: BurnRow): number {
  const metaExpires = row.metadata?.expires_at;
  if (typeof metaExpires === "string") {
    const t = new Date(metaExpires).getTime();
    if (!Number.isNaN(t)) return t;
  }
  return new Date(row.created_at).getTime() + ENTITLEMENT_WINDOW_MS;
}

/**
 * One scan for every reversal, not one per candidate — wallet_ledger has no index
 * for this predicate, so a per-row lookup costs a full seq scan each time.
 */
async function loadReversedTransactionIds(supabase: any): Promise<Set<string>> {
  const { data, error } = await supabase
    .from("wallet_ledger")
    .select("metadata")
    .eq("metadata->>type", "shopify_points_to_discount_reversal")
    .gte("created_at", SWEEP_MIN_CREATED_AT);
  if (error) throw error;
  const ids = new Set<string>();
  for (const row of data ?? []) {
    const original = row?.metadata?.original_transaction_id;
    if (typeof original === "string") ids.add(original);
  }
  return ids;
}

async function discountCodeWasUsed(supabase: any, cred: any, nodeId: string): Promise<boolean> {
  const { body } = await shopifyGraphql(supabase, cred, CODE_USAGE_QUERY, { id: nodeId });
  const usage = body?.data?.codeDiscountNode?.codeDiscount?.asyncUsageCount;
  return typeof usage === "number" && usage > 0;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") return json({ success: false, error: "POST only" }, 405);
  if (!authorize(req)) return json({ success: false, error: "Unauthorized" }, 401);

  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const now = Date.now();
  const summary = { reversed: [] as string[], skipped: [] as string[], errors: [] as string[] };

  try {
    const { data: burns, error } = await supabase
      .from("wallet_ledger")
      .select("id, user_id, merchant_id, amount, source_id, created_at, metadata")
      .eq("transaction_type", "burn")
      .eq("metadata->>type", "shopify_points_to_discount")
      .eq("metadata->>delivery", "discount_code")
      .gte("created_at", SWEEP_MIN_CREATED_AT)
      .order("created_at", { ascending: true })
      .limit(500);

    if (error) throw error;

    const reversed = await loadReversedTransactionIds(supabase);
    const credByMerchant = new Map<string, any>();

    for (const row of (burns ?? []) as BurnRow[]) {
      const transactionId = row.source_id;
      if (!transactionId) {
        summary.skipped.push(`${row.id}:missing_source_id`);
        continue;
      }
      if (windowEnd(row) > now) {
        summary.skipped.push(`${transactionId}:window_open`);
        continue;
      }
      if (reversed.has(transactionId)) {
        summary.skipped.push(`${transactionId}:already_reversed`);
        continue;
      }

      const nodeId = row.metadata?.discount_node_id;
      if (typeof nodeId !== "string" || !nodeId.startsWith("gid://")) {
        summary.skipped.push(`${transactionId}:missing_discount_node_id`);
        continue;
      }

      let used = false;

      try {
        let cred = credByMerchant.get(row.merchant_id);
        if (!cred) {
          cred = await getShopifyCredential(supabase, row.merchant_id);
          credByMerchant.set(row.merchant_id, cred);
        }
        used = await discountCodeWasUsed(supabase, cred, nodeId);
      } catch (err: any) {
        summary.errors.push(`${transactionId}:${err.message || "shopify_check_failed"}`);
        continue;
      }

      if (used) {
        summary.skipped.push(`${transactionId}:used`);
        continue;
      }

      await reversePointsBurn(
        supabase,
        row.user_id,
        row.merchant_id,
        row.amount,
        transactionId,
        "Refund: unused Shopify points discount expired",
      );
      summary.reversed.push(transactionId);
    }

    console.log("[shopify-sweep-points-discount]", JSON.stringify(summary));
    return json({ success: true, ...summary });
  } catch (err: any) {
    console.error("[shopify-sweep-points-discount] fatal", err);
    return json({ success: false, error: err.message || "Unexpected error", ...summary }, 500);
  }
});
