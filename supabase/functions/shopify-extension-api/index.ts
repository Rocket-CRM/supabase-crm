import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";
import {
  corsHeaders,
  customerNumericId,
  getMerchantByShop,
  jsonResponse,
  resolveMemberFromCustomerId,
  shopHostFromDest,
  verifyShopifySessionToken,
} from "./_shared/shopify-member-session.ts";

const CRM_REDEMPTIONS_URL = "https://crm-api-67ej.onrender.com/redemptions";
const MEMBER_CACHE_MS = 60 * 1000;
const REDEEM_WAIT_MS = 8000;

type MemberSession = {
  jwt: string;
  userId: string;
  merchantId: string;
  merchantCode: string | null;
  shop: string;
};

const memberCache = new Map<
  string,
  { expires: number; value: MemberSession }
>();

function envelopeError(code: string, status: number, message?: string) {
  return jsonResponse({ success: false, code, error: message || code }, status);
}

function envelopeOk(data: unknown) {
  return jsonResponse({ success: true, data });
}

function routePath(url: URL) {
  const raw = url.pathname.replace(/\/+$/, "");
  const idx = raw.indexOf("/shopify-extension-api");
  const rest =
    idx >= 0 ? raw.slice(idx + "/shopify-extension-api".length) : raw;
  return rest || "/";
}

function nonNegativeInteger(
  value: string | null,
  fallback: number,
  max?: number,
) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0) return fallback;
  const integer = Math.floor(parsed);
  return max == null ? integer : Math.min(integer, max);
}

function bearerToken(req: Request): string | null {
  const header =
    req.headers.get("authorization") || req.headers.get("Authorization") || "";
  const match = header.match(/^Bearer\s+(.+)$/i);
  return match ? match[1].trim() : null;
}

function memberClient(jwt: string) {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY") ||
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    {
      global: { headers: { Authorization: `Bearer ${jwt}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    },
  );
}

async function authenticate(
  req: Request,
  supabase: any,
  opts: { memberRequired: boolean },
) {
  const token = bearerToken(req);
  if (!token)
    return {
      error: envelopeError("UNAUTHENTICATED", 401, "Missing session token"),
    };

  const parts = token.split(".");
  if (parts.length !== 3)
    return { error: envelopeError("INVALID_TOKEN", 401, "Malformed token") };
  let unverified: Record<string, unknown>;
  try {
    unverified = JSON.parse(
      atob(parts[1].replace(/-/g, "+").replace(/_/g, "/")),
    );
  } catch {
    return { error: envelopeError("INVALID_TOKEN", 401, "Malformed token") };
  }

  const destHost = shopHostFromDest(String(unverified.dest || ""));
  if (!destHost)
    return { error: envelopeError("INVALID_TOKEN", 401, "Missing dest") };

  const merchant = await getMerchantByShop(supabase, destHost);
  if (!merchant)
    return {
      error: envelopeError(
        "MERCHANT_NOT_FOUND",
        404,
        "Merchant not found for shop",
      ),
    };

  const credentials = merchant.credential_record?.credentials || {};
  const apiSecret =
    credentials.api_secret || Deno.env.get("SHOPIFY_API_SECRET");
  const apiKey = credentials.api_key || Deno.env.get("SHOPIFY_API_KEY");
  if (!apiSecret || !apiKey)
    return {
      error: envelopeError(
        "MERCHANT_NOT_FOUND",
        404,
        "Shop credentials incomplete",
      ),
    };

  try {
    await verifyShopifySessionToken(token, apiSecret, apiKey, destHost);
  } catch (err: any) {
    return {
      error: envelopeError(
        err.code || "INVALID_TOKEN",
        401,
        err.message || "Invalid token",
      ),
    };
  }

  const customerId = customerNumericId(String(unverified.sub || ""));
  if (!customerId) {
    if (opts.memberRequired)
      return {
        error: envelopeError(
          "UNAUTHENTICATED",
          401,
          "Customer session required",
        ),
      };
    return { merchant, session: null as MemberSession | null, destHost };
  }

  const cacheKey = `${destHost}:${customerId}`;
  const cached = memberCache.get(cacheKey);
  if (cached && cached.expires > Date.now()) {
    return { merchant, session: cached.value, destHost };
  }

  try {
    const resolved = await resolveMemberFromCustomerId(
      supabase,
      merchant,
      customerId,
    );
    const session: MemberSession = {
      jwt: resolved.jwt,
      userId: String(resolved.dbUser.id),
      merchantId: merchant.merchant_id,
      merchantCode: merchant.merchant_code,
      shop: resolved.shop,
    };
    memberCache.set(cacheKey, {
      expires: Date.now() + MEMBER_CACHE_MS,
      value: session,
    });
    return { merchant, session, destHost };
  } catch (err: any) {
    if (err.code === "MEMBER_UNAVAILABLE") {
      return {
        error: envelopeError(
          "MEMBER_UNAVAILABLE",
          409,
          "We could not open your rewards yet.",
        ),
      };
    }
    console.error("member resolve", err);
    return {
      error: envelopeError(
        "MEMBER_UNAVAILABLE",
        409,
        err.message || "Member unavailable",
      ),
    };
  }
}

async function handleHub(
  req: URL,
  session: MemberSession | null,
  merchant: any,
  supabase: any,
) {
  const language = req.searchParams.get("language");
  if (session) {
    const client = memberClient(session.jwt);
    const { data, error } = await client.rpc("bff_user_get_shopify_hub", {
      p_language: language,
    });
    if (error)
      return jsonResponse(
        { success: false, code: "NOT_FOUND", error: error.message },
        500,
      );
    if (data?.success === false) return jsonResponse(data, 400);
    return envelopeOk(data?.data ?? data);
  }
  const { data, error } = await supabase.rpc("fn_compose_shopify_hub", {
    p_merchant_id: merchant.merchant_id,
    p_user_id: null,
    p_language: language,
  });
  if (error)
    return jsonResponse(
      { success: false, code: "NOT_FOUND", error: error.message },
      500,
    );
  return envelopeOk(data);
}

async function handleBalance(session: MemberSession) {
  const client = memberClient(session.jwt);
  const { data, error } = await client.rpc("bff_user_get_shopify_hub", {
    p_language: null,
  });
  if (error || data?.success === false)
    return envelopeError("NOT_FOUND", 404, error?.message || "Hub unavailable");
  const hub = data?.data ?? data;
  const member = hub?.member;
  if (!member) return envelopeOk(null);
  const rewards = [...(hub?.spend || []), ...(hub?.shop || [])];
  const hasAffordable = rewards.some(
    (row: { affordable?: boolean }) => row.affordable === true,
  );
  return envelopeOk({
    points_balance: member.points_balance,
    points_name: hub?.branding?.points_name || "Points",
    points_symbol: hub?.branding?.points_symbol || null,
    tier: member.tier
      ? { name: member.tier.name, icon: member.tier.icon }
      : null,
    hub_available: true,
    has_affordable_reward: hasAffordable,
  });
}

async function handleOrderPoints(
  url: URL,
  session: MemberSession | null,
  merchant: any,
  supabase: any,
) {
  const orderId = url.searchParams.get("order_id");
  if (!orderId)
    return envelopeError("VALIDATION_ERROR", 400, "order_id required");
  if (!session) {
    const { data: display } = await supabase
      .from("merchant_display_settings")
      .select("points_unit_label")
      .eq("merchant_id", merchant.merchant_id)
      .maybeSingle();
    return envelopeOk({
      status: "guest",
      points: 0,
      points_name: display?.points_unit_label || "Points",
      balance: null,
    });
  }
  const client = memberClient(session.jwt);
  const { data, error } = await client.rpc("bff_user_get_order_points", {
    p_platform: "shopify",
    p_platform_order_id: orderId,
  });
  if (error) return envelopeError("NOT_FOUND", 404, error.message);
  if (data?.success === false) return jsonResponse(data, 400);
  return envelopeOk(data?.data ?? data);
}

async function handleActivity(url: URL, session: MemberSession) {
  const kind = url.searchParams.get("kind") || "points";
  if (!["points", "tier", "referral"].includes(kind)) {
    return envelopeError("VALIDATION_ERROR", 400, "Unsupported activity kind");
  }
  const offset = nonNegativeInteger(url.searchParams.get("offset"), 0);
  const limit = Math.max(
    1,
    nonNegativeInteger(url.searchParams.get("limit"), 20, 50),
  );
  const client = memberClient(session.jwt);
  if (kind === "tier") {
    const { data, error } = await client.rpc("bff_get_tier_history", {
      p_filter: null,
      p_limit: limit + 1,
      p_offset: offset,
    });
    if (error) return envelopeError("NOT_FOUND", 500, error.message);
    const rows = Array.isArray(data) ? data : [];
    return envelopeOk({
      items: rows.slice(0, limit).map((row: any) => ({
        occurred_at: row.dates?.[0]?.value || null,
        title: row.title,
        delta: null,
        unit: "tier",
      })),
      has_more: rows.length > limit,
    });
  }
  if (kind === "referral") {
    const { data, error } = await client.rpc("bff_user_get_referral_status");
    if (error || data?.success === false)
      return envelopeError("NOT_FOUND", 500, error?.message);
    const asInviter = data?.data?.as_inviter || [];
    const sliced = asInviter.slice(offset, offset + limit + 1);
    return envelopeOk({
      items: sliced.slice(0, limit).map((row: any) => ({
        occurred_at: row.signed_up_at,
        title: "Friend joined",
        delta: null,
        unit: "referral",
      })),
      has_more: sliced.length > limit,
    });
  }
  const { data, error } = await client.rpc("bff_get_currency_history", {
    p_filter: "points",
    p_limit: limit + 1,
    p_offset: offset,
  });
  if (error) return envelopeError("NOT_FOUND", 500, error.message);
  const rows = Array.isArray(data) ? data : [];
  return envelopeOk({
    items: rows.slice(0, limit).map((row: any) => ({
      occurred_at: row.dates?.[0]?.value || null,
      title: row.description || row.title,
      delta: row.results?.[0]?.amount ?? null,
      unit: "points",
    })),
    has_more: rows.length > limit,
  });
}

async function handleBirthday(req: Request, session: MemberSession) {
  const body = await req.json().catch(() => ({}));
  const birthDate = body.birth_date;
  if (!birthDate)
    return envelopeError("VALIDATION_ERROR", 400, "birth_date required");
  const client = memberClient(session.jwt);
  const { data, error } = await client.rpc("bff_user_update_birth_date", {
    p_birth_date: birthDate,
    p_language: body.language || "en",
  });
  if (error) return envelopeError("VALIDATION_ERROR", 400, error.message);
  if (data?.success === false) return jsonResponse(data, 400);
  return envelopeOk({ saved: true });
}

type RedemptionStatusPayload = {
  status: "issued" | "pending" | "failed";
  request_id: string;
  code: string | null;
  expires_at: string | null;
  reward_name: string | null;
  title?: string | null;
  description?: string | null;
};

async function getRedemptionStatus(
  client: any,
  requestId: string,
): Promise<RedemptionStatusPayload> {
  const { data, error } = await client.rpc(
    "bff_user_get_redemption_request_status",
    { p_event_id: requestId },
  );
  if (error) throw error;
  if (data?.success === false) {
    throw new Error(data.description || data.title || "Could not check redemption");
  }
  const payload = data?.data || {};
  return {
    status: payload.status || "pending",
    request_id: payload.request_id || requestId,
    code: payload.code ?? null,
    expires_at: payload.expires_at ?? null,
    reward_name: payload.reward_name ?? null,
    title: payload.title ?? null,
    description: payload.description ?? null,
  };
}

async function handleRedeemStatus(url: URL, session: MemberSession) {
  const requestId = url.searchParams.get("request_id")?.trim();
  if (!requestId)
    return envelopeError("VALIDATION_ERROR", 400, "request_id required");
  try {
    return envelopeOk(
      await getRedemptionStatus(memberClient(session.jwt), requestId),
    );
  } catch (error: any) {
    return envelopeError(
      "NOT_FOUND",
      500,
      error.message || "Could not check redemption",
    );
  }
}

async function handleRedeem(req: Request, session: MemberSession) {
  const body = await req.json().catch(() => ({}));
  const rewardId = body.reward_id;
  if (!rewardId)
    return envelopeError("VALIDATION_ERROR", 400, "reward_id required");

  const redeemRes = await fetch(CRM_REDEMPTIONS_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${session.jwt}`,
    },
    body: JSON.stringify({ reward_id: rewardId, quantity: 1 }),
  });
  const redeemJson = await redeemRes.json().catch(() => ({}));
  if (!redeemRes.ok) {
    return envelopeError(
      "REDEMPTION_FAILED",
      redeemRes.status,
      redeemJson.message || redeemJson.error || "Redemption failed",
    );
  }

  const requestId = String(
    redeemJson.event_id || redeemJson.data?.event_id || "",
  ).trim();
  if (!requestId) {
    return envelopeOk({
      status: "pending",
      request_id: null,
      code: null,
      expires_at: null,
      reward_name: null,
    });
  }

  const client = memberClient(session.jwt);
  const started = Date.now();
  while (Date.now() - started < REDEEM_WAIT_MS) {
    const status = await getRedemptionStatus(client, requestId);
    if (status.status === "issued" || status.status === "failed") {
      return envelopeOk(status);
    }
    await new Promise((r) => setTimeout(r, 600));
  }
  return envelopeOk({
    status: "pending",
    request_id: requestId,
    code: null,
    expires_at: null,
    reward_name: null,
  });
}

async function handleWishlistGet(session: MemberSession) {
  const client = memberClient(session.jwt);
  const { data, error } = await client.rpc("bff_user_get_wishlist");
  if (error) {
    return jsonResponse(
      { success: false, code: "NOT_FOUND", error: error.message },
      500,
    );
  }
  if (data?.success === false) return jsonResponse(data, 400);
  return envelopeOk(data?.data ?? data);
}

async function handleWishlistToggle(req: Request, session: MemberSession) {
  const body = await req.json().catch(() => ({}));
  const variantId = body.variant_id || body.variantId;
  const productId = body.product_id || body.productId;
  const snapshot =
    body.snapshot && typeof body.snapshot === "object"
      ? body.snapshot
      : {
          handle: body.handle,
          title: body.title,
          image_url: body.image_url || body.imageUrl,
        };
  if (!variantId) {
    return envelopeError("VALIDATION_ERROR", 400, "variant_id required");
  }
  const client = memberClient(session.jwt);
  const { data, error } = await client.rpc("bff_user_toggle_wishlist_item", {
    p_variant_id: String(variantId),
    p_product_id: productId ? String(productId) : String(variantId),
    p_snapshot: snapshot,
  });
  if (error) {
    return jsonResponse(
      { success: false, code: "NOT_FOUND", error: error.message },
      500,
    );
  }
  if (data?.success === false) return jsonResponse(data, 400);
  return envelopeOk(data?.data ?? data);
}

serve(async (req) => {
  if (req.method === "OPTIONS")
    return new Response(null, { headers: corsHeaders });
  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const url = new URL(req.url);
    const path = routePath(url);

    const memberRequired =
      path === "/balance" ||
      path.startsWith("/hub/") ||
      path === "/wishlist" ||
      path.startsWith("/wishlist/");
    const auth = await authenticate(req, supabase, { memberRequired });
    if ("error" in auth && auth.error) return auth.error;

    const { merchant, session } = auth as {
      merchant: any;
      session: MemberSession | null;
    };

    if (req.method === "GET" && path === "/hub")
      return await handleHub(url, session, merchant, supabase);
    if (req.method === "GET" && path === "/balance") {
      if (!session) return envelopeOk(null);
      return await handleBalance(session);
    }
    if (req.method === "GET" && path === "/order-points")
      return await handleOrderPoints(url, session, merchant, supabase);
    if (req.method === "GET" && path === "/hub/activity") {
      if (!session) return envelopeError("UNAUTHENTICATED", 401);
      return await handleActivity(url, session);
    }
    if (req.method === "GET" && path === "/hub/redeem") {
      if (!session) return envelopeError("UNAUTHENTICATED", 401);
      return await handleRedeemStatus(url, session);
    }
    if (req.method === "POST" && path === "/hub/birthday") {
      if (!session) return envelopeError("UNAUTHENTICATED", 401);
      return await handleBirthday(req, session);
    }
    if (req.method === "POST" && path === "/hub/redeem") {
      if (!session) return envelopeError("UNAUTHENTICATED", 401);
      return await handleRedeem(req, session);
    }
    if (req.method === "GET" && path === "/wishlist") {
      if (!session) return envelopeError("UNAUTHENTICATED", 401);
      return await handleWishlistGet(session);
    }
    if (req.method === "POST" && path === "/wishlist/toggle") {
      if (!session) return envelopeError("UNAUTHENTICATED", 401);
      return await handleWishlistToggle(req, session);
    }

    return envelopeError("NOT_FOUND", 404, "Endpoint not found");
  } catch (error: any) {
    console.error("shopify-extension-api", error);
    return jsonResponse(
      { success: false, code: "NOT_FOUND", error: error.message },
      500,
    );
  }
});
