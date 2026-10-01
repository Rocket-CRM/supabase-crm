import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";
import { verify } from "https://deno.land/x/djwt@v2.8/mod.ts";
import { getMemberJwtSecret } from "../_shared/member-session.ts";
import { getFreshShopifyCredentialForMerchant } from "../_shared/shopify-admin-client.ts";
import {
  addAmountToLoyaltyBalance,
  balanceGetSummary,
  customerGidFromId,
  deleteDiscountCodeNode,
  findShopifyCustomerGidByIdentity,
  formatLoyaltyReservationDiscountTitle,
  linkShopifyCustomerToMember,
  mutateLoyaltyPointsBalance,
  numericCustomerId,
  prepareBalanceForReservation,
  readLoyaltyPointsBalance,
} from "../_shared/shopify-points-balance.ts";
import { reversePointsBurn } from "../_shared/shopify-points-reversal.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const REFRESH_WINDOW_MS = 5 * 60 * 1000;
const LOYALTY_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

type DeliveryMode = "balance" | "discount_code";
type PointsAction = "redeem" | "get" | "reserve";

interface JWTPayload {
  sub: string;
  user_id: string;
  merchant_id: string;
  shopify_customer_id?: string;
  shop: string;
  [key: string]: unknown;
}

interface RequestBody {
  action?: PointsAction;
  points_amount?: number;
  discount_amount?: number;
  currency_code?: string;
  delivery?: DeliveryMode | "metafield";
  cart_subtotal?: number;
}

function jsonResponse(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
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

function bahtFromPoints(points: number, rate: number): number {
  return Math.round(points * rate * 100) / 100;
}

function generateLoyaltyDiscountCode(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  let suffix = "";
  for (let i = 0; i < 16; i++) suffix += LOYALTY_CODE_ALPHABET[bytes[i]! % LOYALTY_CODE_ALPHABET.length];
  return `LOYALTY${suffix}`;
}

async function resolveEffectiveBurnRate(
  supabase: any,
  userId: string,
  merchantId: string,
): Promise<{ effective_rate: number; is_enabled: boolean }> {
  const { data: ua } = await supabase
    .from("user_accounts")
    .select("tier_id")
    .eq("id", userId)
    .eq("merchant_id", merchantId)
    .maybeSingle();
  const { data: resolved, error } = await supabase.rpc("fn_resolve_burn_rate", {
    p_merchant_id: merchantId,
    p_tier_id: ua?.tier_id ?? null,
  });
  if (error) {
    console.error("[shopify-points-to-discount] fn_resolve_burn_rate error:", error);
    return { effective_rate: 0, is_enabled: false };
  }
  const effective = Number(resolved?.effective_rate ?? 0);
  const is_enabled = Boolean(resolved?.is_enabled);
  return { effective_rate: Number.isFinite(effective) ? effective : 0, is_enabled };
}

async function resolveShopifyCustomerId(
  supabase: any,
  userId: string,
  merchantId: string,
  fromJwt?: string,
): Promise<{ customerId: string | null; error?: string }> {
  if (fromJwt?.trim()) return { customerId: numericCustomerId(fromJwt.trim()) };

  const { data, error } = await supabase
    .from("user_accounts")
    .select("marketplace_external_ids, external_user_id, email, tel, firstname, lastname")
    .eq("id", userId)
    .eq("merchant_id", merchantId)
    .maybeSingle();
  if (error || !data) return { customerId: null };

  const marketplace = data.marketplace_external_ids as Record<string, unknown> | null;
  const fromMarketplace = marketplace?.shopify;
  if (fromMarketplace != null && String(fromMarketplace).trim()) {
    return { customerId: numericCustomerId(String(fromMarketplace)) };
  }
  const external = data.external_user_id;
  if (external != null && String(external).trim()) {
    return { customerId: numericCustomerId(String(external)) };
  }

  let credRecord;
  try {
    credRecord = await getFreshShopifyCredentialForMerchant(supabase, merchantId);
  } catch {
    return { customerId: null };
  }

  const found = await findShopifyCustomerGidByIdentity(supabase, credRecord, {
    email: data.email,
    phone: data.tel,
  });
  if (!found.gid) return { customerId: null };

  const numericId = numericCustomerId(found.gid);
  const link = await linkShopifyCustomerToMember(supabase, merchantId, userId, numericId);
  if (!link.ok) return { customerId: null, error: link.error };

  return { customerId: numericId };
}

async function refreshShopifyToken(supabase: any, record: any) {
  const credentials = record.credentials || {};
  const shopDomain = credentials.shop_domain;
  const apiKey = credentials.api_key || Deno.env.get("SHOPIFY_API_KEY");
  const apiSecret = credentials.api_secret || Deno.env.get("SHOPIFY_API_SECRET");
  if (!shopDomain || !apiKey || !apiSecret || !credentials.refresh_token) {
    throw new Error("Shopify credential requires admin reauth");
  }

  const body = new URLSearchParams();
  body.set("client_id", apiKey);
  body.set("client_secret", apiSecret);
  body.set("grant_type", "refresh_token");
  body.set("refresh_token", credentials.refresh_token);
  const response = await fetch(`https://${shopDomain}/admin/oauth/access_token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded", Accept: "application/json" },
    body,
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok || !data.access_token || !data.refresh_token) {
    const status = response.status === 400 || response.status === 401 ? "reauth_required" : "refresh_failed";
    await supabase.from("merchant_credentials").update({
      credentials: { ...credentials, health_status: status, last_health_check: new Date().toISOString() },
      health_status: status,
      last_health_check: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    }).eq("id", record.id);
    throw new Error(data.error_description || data.error || `Shopify token refresh failed (${response.status})`);
  }
  const expiresAt = toIsoFromSeconds(data.expires_in);
  const refreshTokenExpiresAt = toIsoFromSeconds(data.refresh_token_expires_in);
  const nextCredentials = {
    ...credentials,
    access_token: data.access_token,
    refresh_token: data.refresh_token,
    token_mode: "offline_expiring",
    scope: data.scope || credentials.scope || null,
    expires_at: expiresAt,
    refresh_token_expires_at: refreshTokenExpiresAt,
    health_status: "healthy",
    last_health_check: new Date().toISOString(),
    token_updated_at: new Date().toISOString(),
  };
  await supabase.from("merchant_credentials").update({
    credentials: nextCredentials,
    expires_at: expiresAt,
    health_status: "healthy",
    last_health_check: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  }).eq("id", record.id);
  return { ...record, credentials: nextCredentials };
}

async function getShopifyCredential(supabase: any, merchantId: string) {
  const { data, error } = await supabase.from("merchant_credentials").select("id, merchant_id, credentials")
    .eq("merchant_id", merchantId).eq("service_name", "shopify_app").eq("is_active", true).single();
  if (error || !data) throw new Error("No active Shopify credentials found for this merchant");
  const record = { id: data.id, merchant_id: data.merchant_id, credentials: data.credentials || {} };
  if (isNearExpiry(record.credentials || {})) return await refreshShopifyToken(supabase, record);
  return record;
}

async function shopifyGraphqlWithRefresh(supabase: any, record: any, query: string, variables: any) {
  let current = record;
  const call = () =>
    fetch(`https://${current.credentials.shop_domain}/admin/api/2024-04/graphql.json`, {
      method: "POST",
      headers: {
        "X-Shopify-Access-Token": current.credentials.access_token,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ query, variables }),
    });
  let response = await call();
  if (response.status === 401 && current.credentials?.token_mode === "offline_expiring" && current.credentials?.refresh_token) {
    current = await refreshShopifyToken(supabase, current);
    response = await call();
  }
  return { response, credential: current };
}

const DISCOUNT_CODE_BASIC_CREATE = `
mutation discountCodeBasicCreate($basicCodeDiscount: DiscountCodeBasicInput!) {
  discountCodeBasicCreate(basicCodeDiscount: $basicCodeDiscount) {
    codeDiscountNode {
      id
      codeDiscount {
        ... on DiscountCodeBasic {
          codes(first: 1) { nodes { code } }
        }
      }
    }
    userErrors { field message code }
  }
}`;

async function mergeBurnMetadata(supabase: any, transactionId: string, patch: Record<string, unknown>) {
  const { data: row } = await supabase.from("wallet_ledger").select("metadata").eq("source_id", transactionId).maybeSingle();
  const merged = { ...(row?.metadata || {}), ...patch };
  await supabase.from("wallet_ledger").update({ metadata: merged }).eq("source_id", transactionId);
}

async function mintSingleUseDiscount(
  supabase: any,
  credRecord: any,
  amount: number,
  currencyCode: string,
  _customerGid: string,
  title: string,
): Promise<{ code: string; discountNodeId: string | null; credential: any }> {
  const discountCode = generateLoyaltyDiscountCode();
  const basicCodeDiscount = {
    title,
    code: discountCode,
    startsAt: new Date().toISOString(),
    customerSelection: { all: true },
    appliesOncePerCustomer: true,
    usageLimit: 1,
    combinesWith: { orderDiscounts: true, productDiscounts: true, shippingDiscounts: true },
    customerGets: {
      value: { discountAmount: { amount: String(amount), appliesOnEachItem: false } },
      items: { all: true },
    },
  };

  const { response, credential } = await shopifyGraphqlWithRefresh(
    supabase,
    credRecord,
    DISCOUNT_CODE_BASIC_CREATE,
    { basicCodeDiscount },
  );
  const shopifyBody = await response.json().catch(() => ({}));
  const createResult = shopifyBody?.data?.discountCodeBasicCreate;
  const userErrors = createResult?.userErrors;
  if (!response.ok || shopifyBody.errors || (userErrors && userErrors.length > 0)) {
    throw new Error("discount_code_create_failed");
  }
  const discountNodeId = createResult?.codeDiscountNode?.id || null;
  const mintedCode = createResult?.codeDiscountNode?.codeDiscount?.codes?.nodes?.[0]?.code || discountCode;
  return { code: mintedCode, discountNodeId, credential };
}

async function handleGet(
  supabase: any,
  merchantId: string,
  shopifyCustomerId: string,
) {
  const credRecord = await getShopifyCredential(supabase, merchantId);
  const customerGid = customerGidFromId(shopifyCustomerId);
  const read = await readLoyaltyPointsBalance(supabase, credRecord, customerGid);
  const summary = balanceGetSummary(read.balance);
  return jsonResponse({ success: true, ...summary });
}

async function handleReserve(
  supabase: any,
  merchantId: string,
  shopifyCustomerId: string,
  cartSubtotal: number,
  userLabel: string,
) {
  const credRecord = await getShopifyCredential(supabase, merchantId);
  const customerGid = customerGidFromId(shopifyCustomerId);
  const prep = await prepareBalanceForReservation(supabase, credRecord, customerGid);
  if (prep.reuse) {
    return jsonResponse({ success: true, code: prep.reuse.code, amount: prep.reuse.amount });
  }

  let cred = prep.record;
  const read = await readLoyaltyPointsBalance(supabase, cred, customerGid);
  cred = read.record;
  const available = read.balance?.status === "active" ? Math.max(0, Number(read.balance.amount) || 0) : 0;
  const reserveAmount = Math.min(available, Math.max(0, cartSubtotal));
  if (reserveAmount <= 0) return jsonResponse({ success: true, code: null, amount: 0 });

  const discountTitle = formatLoyaltyReservationDiscountTitle(userLabel, shopifyCustomerId);

  let minted: { code: string; discountNodeId: string | null; credential: any };
  try {
    minted = await mintSingleUseDiscount(
      supabase,
      cred,
      reserveAmount,
      read.balance?.currency || "THB",
      customerGid,
      discountTitle,
    );
  } catch {
    return jsonResponse({ success: false, error: "Failed to create checkout discount code" }, 502);
  }
  cred = minted.credential;

  try {
    await mutateLoyaltyPointsBalance(supabase, cred, customerGid, (current) => {
      const next = { ...current };
      if (next.status !== "active") throw new Error("balance_inactive");
      next.amount = Math.max(0, Number(next.amount) - reserveAmount);
      next.reserved = {
        code: minted.code,
        discount_node_id: minted.discountNodeId || "",
        amount: reserveAmount,
        reserved_at: new Date().toISOString(),
      };
      if (next.amount <= 0 && !next.reserved) next.status = "consumed";
      return next;
    });
  } catch (_err) {
    if (minted.discountNodeId) {
      await deleteDiscountCodeNode(supabase, cred, minted.discountNodeId);
    }
    return jsonResponse({ success: false, error: "Failed to reserve balance for checkout" }, 502);
  }

  return jsonResponse({ success: true, code: minted.code, amount: reserveAmount });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) return jsonResponse({ success: false, error: "Missing authorization" }, 401);

    const token = authHeader.replace("Bearer ", "");
    const secret = getMemberJwtSecret();
    if (!secret) return jsonResponse({ success: false, error: "JWT secret not configured" }, 500);
    const key = await crypto.subtle.importKey(
      "raw",
      new TextEncoder().encode(secret),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["verify"],
    );
    let payload: JWTPayload;
    try {
      payload = (await verify(token, key)) as unknown as JWTPayload;
    } catch {
      return jsonResponse({ success: false, error: "Invalid or expired token" }, 401);
    }

    const userId = payload.user_id || payload.sub;
    const merchantId = payload.merchant_id;
    if (!userId || !merchantId) {
      return jsonResponse({ success: false, error: "Token missing required claims (user_id, merchant_id)" }, 401);
    }

    const body: RequestBody = await req.json().catch(() => ({}));
    const action: PointsAction = body.action === "get" || body.action === "reserve" ? body.action : "redeem";

    if (action === "get") {
      const resolved = await resolveShopifyCustomerId(supabase, userId, merchantId, payload.shopify_customer_id);
      if (resolved.error === "shopify_customer_conflict") {
        return jsonResponse({ success: false, error: "shopify_customer_conflict" }, 409);
      }
      if (!resolved.customerId) {
        return jsonResponse({ success: true, available: 0, reserved_amount: 0, currency: "THB" });
      }
      return await handleGet(supabase, merchantId, resolved.customerId);
    }

    if (action === "reserve") {
      const cartSubtotal = Number(body.cart_subtotal);
      if (!Number.isFinite(cartSubtotal) || cartSubtotal < 0) {
        return jsonResponse({ success: false, error: "cart_subtotal must be a non-negative number" }, 400);
      }
      const resolved = await resolveShopifyCustomerId(supabase, userId, merchantId, payload.shopify_customer_id);
      if (resolved.error === "shopify_customer_conflict") {
        return jsonResponse({ success: false, error: "shopify_customer_conflict" }, 409);
      }
      if (!resolved.customerId) {
        return jsonResponse({ success: false, error: "Shopify customer not linked" }, 400);
      }
      const { data: profile } = await supabase.from("user_accounts").select("email, firstname, lastname")
        .eq("id", userId).eq("merchant_id", merchantId).maybeSingle();
      const userLabel = profile?.email ||
        [profile?.firstname, profile?.lastname].filter(Boolean).join(" ") ||
        "member";
      return await handleReserve(supabase, merchantId, resolved.customerId, cartSubtotal, userLabel);
    }

    const delivery: DeliveryMode = body.delivery === "discount_code" ? "discount_code" : "balance";
    const { points_amount, currency_code } = body;
    if (!points_amount || points_amount <= 0) {
      return jsonResponse({ success: false, error: "points_amount must be a positive number" }, 400);
    }
    if (!currency_code) return jsonResponse({ success: false, error: "currency_code is required" }, 400);

    const burn = await resolveEffectiveBurnRate(supabase, userId, merchantId);
    if (!burn.is_enabled || burn.effective_rate <= 0) {
      return jsonResponse({ success: false, error: "Point discount is not enabled" }, 400);
    }
    const discount_amount = bahtFromPoints(points_amount, burn.effective_rate);
    if (discount_amount <= 0) {
      return jsonResponse({ success: false, error: "Points amount is too low for a discount" }, 400);
    }

    const resolved = await resolveShopifyCustomerId(supabase, userId, merchantId, payload.shopify_customer_id);
    if (resolved.error === "shopify_customer_conflict") {
      return jsonResponse({ success: false, error: "shopify_customer_conflict" }, 409);
    }
    const shopifyCustomerId = resolved.customerId;
    if (delivery === "balance" && !shopifyCustomerId) {
      return jsonResponse({
        success: false,
        error: "Token missing required claims (user_id, merchant_id, shopify_customer_id)",
      }, 401);
    }

    const { data: wallet, error: walletError } = await supabase.from("user_wallet").select("points_balance")
      .eq("user_id", userId).eq("merchant_id", merchantId).maybeSingle();
    if (walletError) return jsonResponse({ success: false, error: "Failed to check points balance" }, 500);
    const balanceBefore = wallet?.points_balance || 0;
    const max_discount = bahtFromPoints(balanceBefore, burn.effective_rate);
    if (discount_amount > max_discount + 0.001) {
      return jsonResponse({ success: false, error: "exceeds_max_discount" }, 400);
    }
    if (balanceBefore < points_amount) {
      return jsonResponse({
        success: false,
        error: "Insufficient points",
        points_burn: {
          success: false,
          balance_before: balanceBefore,
          points_requested: points_amount,
          shortage: points_amount - balanceBefore,
        },
        shopify_metafield: { success: false, error: "Not attempted - insufficient points" },
      }, 400);
    }

    const transactionId = crypto.randomUUID();
    const burnMetadata: Record<string, unknown> = {
      type: "shopify_points_to_discount",
      discount_amount,
      currency_code,
      delivery: delivery === "discount_code" ? "discount_code" : "balance",
    };
    if (shopifyCustomerId) burnMetadata.shopify_customer_id = shopifyCustomerId;

    const { data: burnResult, error: burnError } = await supabase.rpc("chokepoint_post_wallet_transaction", {
      p_user_id: userId,
      p_currency: "points",
      p_source_type: "reward_redemption",
      p_component: "base",
      p_transaction_type: "burn",
      p_amount: points_amount,
      p_transaction_id: transactionId,
      p_merchant_id: merchantId,
      p_description: `Points to Shopify discount: ${discount_amount} ${currency_code}`,
      p_metadata: burnMetadata,
    });
    if (burnError) {
      return jsonResponse({
        success: false,
        error: "Failed to deduct points",
        points_burn: { success: false, error: burnError.message, balance_before: balanceBefore },
        shopify_metafield: { success: false, error: "Not attempted - points burn failed" },
      }, 500);
    }

    let credRecord;
    try {
      credRecord = await getShopifyCredential(supabase, merchantId);
    } catch (err: any) {
      await reversePointsBurn(supabase, userId, merchantId, points_amount, transactionId);
      return jsonResponse({
        success: false,
        error: "Shopify credentials not found, points refunded",
        points_burn: {
          success: true,
          reversed: true,
          reason: err.message,
          transaction_id: transactionId,
          ledger_id: burnResult,
          points_burned: points_amount,
          balance_before: balanceBefore,
          balance_after: balanceBefore,
        },
        shopify_metafield: { success: false, error: err.message },
      }, 500);
    }

    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
    const startsAt = new Date().toISOString();

    if (delivery === "discount_code") {
      const discountCode = generateLoyaltyDiscountCode();
      const basicCodeDiscount = {
        title: transactionId,
        code: discountCode,
        startsAt,
        endsAt: expiresAt,
        customerSelection: { all: true },
        appliesOncePerCustomer: true,
        usageLimit: 1,
        combinesWith: { orderDiscounts: true, productDiscounts: true, shippingDiscounts: true },
        customerGets: {
          value: { discountAmount: { amount: String(discount_amount), appliesOnEachItem: false } },
          items: { all: true },
        },
      };

      const { response: shopifyResponse, credential } = await shopifyGraphqlWithRefresh(
        supabase,
        credRecord,
        DISCOUNT_CODE_BASIC_CREATE,
        { basicCodeDiscount },
      );
      const shopifyBody = await shopifyResponse.json().catch(() => ({}));
      const createResult = shopifyBody?.data?.discountCodeBasicCreate;
      const userErrors = createResult?.userErrors;

      if (!shopifyResponse.ok || shopifyBody.errors || (userErrors && userErrors.length > 0)) {
        const errorDetail = shopifyBody.errors || userErrors || shopifyBody;
        await reversePointsBurn(
          supabase,
          userId,
          merchantId,
          points_amount,
          transactionId,
          "Refund: Shopify discount code creation failed",
        );
        return jsonResponse({
          success: false,
          error: "Failed to create Shopify discount code, points refunded",
          points_burn: {
            success: true,
            reversed: true,
            reason: "Shopify discount code create failed",
            transaction_id: transactionId,
            ledger_id: burnResult,
            points_burned: points_amount,
            balance_before: balanceBefore,
            balance_after: balanceBefore,
          },
          shopify_discount_code: {
            success: false,
            error: errorDetail,
            shop_domain: credential.credentials.shop_domain,
          },
        }, 502);
      }

      const discountNodeId = createResult?.codeDiscountNode?.id || null;
      const mintedCode = createResult?.codeDiscountNode?.codeDiscount?.codes?.nodes?.[0]?.code || discountCode;
      await mergeBurnMetadata(supabase, transactionId, {
        discount_code: mintedCode,
        discount_node_id: discountNodeId,
      });

      return jsonResponse({
        success: true,
        message: `${discount_amount} ${currency_code} discount code ready.`,
        points_burn: {
          success: true,
          reversed: false,
          transaction_id: transactionId,
          ledger_id: burnResult,
          points_burned: points_amount,
          balance_before: balanceBefore,
          balance_after: balanceBefore - points_amount,
        },
        shopify_discount_code: {
          success: true,
          code: mintedCode,
          discount_amount,
          currency_code,
          discount_node_id: discountNodeId,
          expires_at: expiresAt,
          shop_domain: credential.credentials.shop_domain,
        },
      });
    }

    const customerGid = customerGidFromId(shopifyCustomerId!);
    try {
      const balanceResult = await addAmountToLoyaltyBalance(
        supabase,
        credRecord,
        customerGid,
        discount_amount,
        currency_code,
      );
      const entitlement = balanceResult.balance;
      return jsonResponse({
        success: true,
        message: `${discount_amount} ${currency_code} discount saved to your account.`,
        points_burn: {
          success: true,
          reversed: false,
          transaction_id: transactionId,
          ledger_id: burnResult,
          points_burned: points_amount,
          balance_before: balanceBefore,
          balance_after: balanceBefore - points_amount,
        },
        shopify_metafield: {
          success: true,
          shopify_customer_id: shopifyCustomerId,
          shop_domain: credRecord.credentials.shop_domain,
          entitlement,
        },
      });
    } catch (err: any) {
      await reversePointsBurn(supabase, userId, merchantId, points_amount, transactionId);
      return jsonResponse({
        success: false,
        error: "Failed to add Shopify discount balance, points refunded",
        points_burn: {
          success: true,
          reversed: true,
          reason: "Shopify balance write failed",
          transaction_id: transactionId,
          ledger_id: burnResult,
          points_burned: points_amount,
          balance_before: balanceBefore,
          balance_after: balanceBefore,
        },
        shopify_metafield: { success: false, error: err?.message || "write_failed", shopify_customer_id: shopifyCustomerId },
      }, 502);
    }
  } catch (error: any) {
    console.error("[shopify-points-to-discount] Unexpected error:", error);
    return jsonResponse({ success: false, error: error.message || "Unexpected error" }, 500);
  }
});
