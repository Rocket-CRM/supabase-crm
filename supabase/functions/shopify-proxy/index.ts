import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4';
import {
  SHOPIFY_API_VERSION,
  corsHeaders,
  ensureValidShopifyCredentials,
  fetchShopifyCustomer,
  findOrCreateMember,
  getMerchantByShop,
  jsonResponse,
  mintShopifyMemberSessionToken,
  refreshShopifyToken,
  resolveMemberFromCustomerId,
} from './_shared/shopify-member-session.ts';
import { LANDING_STOREFRONT_LIQUID } from './_shared/landing-storefront-liquid.ts';

const EXISTING_CUSTOMER_LOOKUP_MS = 2500;

async function verifyShopifyHMAC(params: Record<string, string>, signature: string, secret: string): Promise<boolean> {
  try {
    const { signature: _, hmac, ...queryParams } = params;
    const sortedParams = Object.keys(queryParams).sort().map(key => `${key}=${queryParams[key]}`).join('');
    const encoder = new TextEncoder();
    const key = await crypto.subtle.importKey('raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
    const signatureBuffer = await crypto.subtle.sign('HMAC', key, encoder.encode(sortedParams));
    const expectedSignature = Array.from(new Uint8Array(signatureBuffer)).map(b => b.toString(16).padStart(2, '0')).join('');
    return signature === expectedSignature || (hmac && hmac === expectedSignature);
  } catch (error) {
    console.error('HMAC verification error:', error);
    return false;
  }
}


/** true = existing shopper, false = not found, null = lookup failed (fail-open). */
async function shopifyEmailLooksLikeExistingCustomer(shop: string, accessToken: string, email: string): Promise<boolean | null> {
  const trimmed = email.trim();
  if (!trimmed) return false;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), EXISTING_CUSTOMER_LOOKUP_MS);
  const headers = { 'X-Shopify-Access-Token': accessToken, 'Content-Type': 'application/json' };
  try {
    const customerRes = await fetch(
      `https://${shop}/admin/api/${SHOPIFY_API_VERSION}/customers/search.json?query=${encodeURIComponent(`email:${trimmed}`)}`,
      { headers, signal: controller.signal },
    );
    if (!customerRes.ok) {
      console.error('[shopify-proxy] customer search', customerRes.status);
      return null;
    }
    const customerJson = await customerRes.json().catch(() => ({}));
    if (Array.isArray(customerJson.customers) && customerJson.customers.length > 0) return true;

    const orderRes = await fetch(
      `https://${shop}/admin/api/${SHOPIFY_API_VERSION}/orders.json?email=${encodeURIComponent(trimmed)}&status=any&limit=1`,
      { headers, signal: controller.signal },
    );
    if (!orderRes.ok) {
      console.error('[shopify-proxy] order search', orderRes.status);
      return null;
    }
    const orderJson = await orderRes.json().catch(() => ({}));
    if (Array.isArray(orderJson.orders) && orderJson.orders.length > 0) return true;
    return false;
  } catch (err) {
    console.error('[shopify-proxy] existing customer lookup', err);
    return null;
  } finally {
    clearTimeout(timer);
  }
}

async function handleLanding(
  supabase: any,
  merchantCode: string | null,
  merchantId: string,
  req: Request,
  shop: string,
  loggedInCustomerId: string | undefined,
  credentialRecord: any,
) {
  if (req.method !== 'GET') return jsonResponse({ ok: false, error: 'GET required' }, 405);

  const url = new URL(req.url);
  const locale = url.searchParams.get('locale') || url.searchParams.get('language') || 'en';

  const { data: payload, error } = await supabase.rpc('api_get_shopify_landing_page_cached', {
    p_merchant_code: merchantCode,
    p_language: locale,
  });
  if (error) {
    console.error('[shopify-proxy] landing rpc', error);
    return jsonResponse({ ok: false, error: error.message }, 500);
  }
  if (!payload?.ok) {
    const status = payload?.published === false ? 404 : 400;
    return jsonResponse(payload, status);
  }

  let body = payload;
  const headers: Record<string, string> = {
    ...corsHeaders,
    'Content-Type': 'application/json',
    'Cache-Control': 'public, max-age=60, s-maxage=300',
  };

  if (loggedInCustomerId) {
    try {
      const { dbUser } = await resolveMemberFromCustomerId(supabase, {
        merchant_id: merchantId,
        merchant_code: merchantCode,
        credential_record: credentialRecord,
      }, loggedInCustomerId);
      const userId = dbUser?.id;
      if (userId) {
        const { data: overlaid, error: overlayError } = await supabase.rpc(
          'fn_overlay_shopify_landing_member_state',
          {
            p_payload: payload,
            p_merchant_id: merchantId,
            p_user_id: userId,
            p_language: locale,
          },
        );
        if (overlayError) {
          console.error('[shopify-proxy] landing overlay', overlayError);
        } else if (overlaid) {
          body = overlaid;
        }
      }
    } catch (err) {
      console.error('[shopify-proxy] landing member resolve', err);
    }
    headers['Cache-Control'] = 'private, no-store';
  }

  return new Response(JSON.stringify(body), { status: 200, headers });
}

function isLandingStorefrontPath(normalizedPath: string): boolean {
  if (normalizedPath.endsWith('/api/rewards')) return false;
  return normalizedPath === '/rewards' || normalizedPath.endsWith('/rewards');
}

async function handleLandingStorefront(
  supabase: any,
  merchantCode: string | null,
  merchantId: string,
  req: Request,
  shop: string,
  loggedInCustomerId: string | undefined,
  credentialRecord: any,
) {
  if (req.method !== 'GET') return jsonResponse({ ok: false, error: 'GET required' }, 405);

  const url = new URL(req.url);
  const locale = url.searchParams.get('locale') || url.searchParams.get('language') || 'en';

  const { data: payload, error } = await supabase.rpc('api_get_shopify_landing_page_cached', {
    p_merchant_code: merchantCode,
    p_language: locale,
  });
  if (error) {
    console.error('[shopify-proxy] landing storefront rpc', error);
    return new Response('Rewards page is temporarily unavailable.', {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'text/html; charset=utf-8' },
    });
  }
  if (!payload?.ok) {
    const status = payload?.published === false ? 404 : 400;
    const message =
      payload?.published === false
        ? 'This rewards page is not published yet.'
        : 'Rewards page is unavailable.';
    return new Response(message, {
      status,
      headers: { ...corsHeaders, 'Content-Type': 'text/html; charset=utf-8' },
    });
  }

  // Member overlay is applied client-side via /landing JSON when logged in; storefront liquid bootstraps the shell.
  void loggedInCustomerId;
  void credentialRecord;
  void merchantId;
  void shop;

  return new Response(LANDING_STOREFRONT_LIQUID, {
    status: 200,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/liquid; charset=utf-8',
      'Cache-Control': loggedInCustomerId ? 'private, no-store' : 'public, max-age=60, s-maxage=300',
    },
  });
}

async function handleReferralClaim(
  supabase: any,
  merchantId: string,
  merchantCode: string | null,
  req: Request,
  shop: string,
  accessToken: string,
) {
  if (req.method !== 'POST') return jsonResponse({ success: false, error: 'POST required' }, 405);
  const body = await req.json().catch(() => ({}));
  const email = typeof body.email === 'string' ? body.email : '';
  if (email.trim() && shop && accessToken) {
    const existing = await shopifyEmailLooksLikeExistingCustomer(shop, accessToken, email);
    if (existing === true) {
      return jsonResponse({ success: false, code: 'EXISTING_CUSTOMER', error: 'This offer isn’t available.' }, 400);
    }
  }
  const { data: claimEnvelope, error: claimError } = await supabase.rpc('api_claim_referral', {
    p_merchant_id: merchantId,
    p_merchant_code: merchantCode || null,
    p_referrer_code: body.referrer_code || null,
    p_platform: 'shopify',
    p_email: body.email || null,
    p_phone: null,
    p_friend_name: body.name || null,
  });
  if (claimError) {
    console.error('[shopify-proxy] claim rpc', claimError);
    return jsonResponse({ success: false, error: claimError.message }, 500);
  }
  if (claimEnvelope?.success !== true) {
    return jsonResponse(claimEnvelope, 400);
  }
  const payload = claimEnvelope.data || {};
  const mother = payload.shopify_mother_discount_id;
  const commerceCode = payload.commerce_code;
  const codeId = payload.referral_code_id;
  const claimId = payload.claim_id;
  if (!mother) {
    await supabase.rpc('api_abort_referral_claim', { p_claim_id: claimId });
    return jsonResponse({ success: false, code: 'NO_MOTHER_DISCOUNT', error: 'Save the friend offer in Referral settings first.' }, 400);
  }
  const issueRes = await fetch(`${Deno.env.get('SUPABASE_URL')}/functions/v1/shopify-issue-reward-code`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`,
    },
    body: JSON.stringify({ merchant_id: merchantId, discount_id: mother, code: commerceCode }),
  });
  const issueJson = await issueRes.json().catch(() => ({}));
  const issueVerified =
    issueRes.ok &&
    issueJson.success === true &&
    issueJson.path !== 'graphql_no_gid' &&
    (issueJson.redeem_code_gid || issueJson.external_ref_id || issueJson.code_verified === true);
  if (!issueVerified) {
    await supabase.rpc('api_abort_referral_claim', { p_claim_id: claimId });
    return jsonResponse({ success: false, code: 'MINT_FAILED', error: issueJson.error || 'Shopify issue failed' }, 502);
  }
  await supabase.rpc('api_confirm_referral_mint', {
    p_referral_code_id: codeId,
    p_platform_discount_id: issueJson.redeem_code_gid || issueJson.external_ref_id || null,
  });
  return jsonResponse({
    success: true,
    code: commerceCode,
    expires_at: payload.expires_at,
  });
}

async function handleReferralPage(supabase: any, merchantCode: string | null, req: Request) {
  if (req.method !== 'GET') return jsonResponse({ success: false, error: 'GET required' }, 405);
  const url = new URL(req.url);
  const referrerCode = url.searchParams.get('referrer_code');
  if (!referrerCode?.trim()) {
    return jsonResponse({ success: false, code: 'INVALID_REFERRER', error: 'referrer_code required' }, 400);
  }
  if (!merchantCode) {
    return jsonResponse({ success: false, code: 'NO_MERCHANT', error: 'Merchant code missing' }, 400);
  }
  const { data, error } = await supabase.rpc('api_get_referral_claim_page', {
    p_merchant_code: merchantCode,
    p_platform: 'shopify',
    p_referrer_code: referrerCode.trim(),
  });
  if (error) {
    console.error('[shopify-proxy] referral page rpc', error);
    return jsonResponse({ success: false, error: error.message }, 500);
  }
  const status = data?.success === true ? 200 : 400;
  return jsonResponse(data, status);
}

const WISHLIST_COOKIE = 'rocket_wishlist';
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function memberClient(jwt: string) {
  return createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    {
      global: { headers: { Authorization: `Bearer ${jwt}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    },
  );
}

function readWishlistSessionId(req: Request): string | null {
  const header = req.headers.get('cookie') || '';
  const match = header.match(/(?:^|;\s*)rocket_wishlist=([^;]+)/);
  const value = match?.[1] ? decodeURIComponent(match[1]) : '';
  return UUID_RE.test(value) ? value : null;
}

function wishlistCookieHeader(sessionId: string) {
  return `${WISHLIST_COOKIE}=${sessionId}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=34560000`;
}

function unwrapWishlist(envelope: any) {
  if (envelope?.success === false) return envelope;
  const data = envelope?.data ?? envelope ?? {};
  return {
    success: true,
    items: data.items || [],
    count: data.count ?? (Array.isArray(data.items) ? data.items.length : 0),
    wished: data.wished,
  };
}

async function resolveLoggedInWishlistMember(
  supabase: any,
  merchantConfig: any,
  shop: string,
  customerId: string,
  credentialRecord: any,
) {
  let creds = credentialRecord;
  let customer;
  try {
    customer = await fetchShopifyCustomer(shop, customerId, creds.credentials.access_token);
  } catch (error: any) {
    if (error.status === 401 && creds.credentials?.token_mode === 'offline_expiring' && creds.credentials?.refresh_token) {
      creds = await refreshShopifyToken(supabase, creds);
      customer = await fetchShopifyCustomer(shop, customerId, creds.credentials.access_token);
    } else {
      throw error;
    }
  }
  const dbUser = await findOrCreateMember(supabase, merchantConfig.merchant_id, customer);
  const jwt = await mintShopifyMemberSessionToken(dbUser, merchantConfig.merchant_id, String(customerId));
  return { jwt, userId: String(dbUser.id), credentialRecord: creds };
}

async function handleWishlist(req: Request, ctx: {
  supabase: any;
  merchantConfig: any;
  merchantId: string;
  shop: string;
  loggedInCustomerId?: string;
  credentialRecord: any;
}) {
  const path = new URL(req.url).pathname.replace(/\/+$/, '');
  const isToggle = path.endsWith('/wishlist/toggle');
  if (isToggle && req.method !== 'POST') return jsonResponse({ success: false, error: 'POST required' }, 405);
  if (!isToggle && req.method !== 'GET') return jsonResponse({ success: false, error: 'GET required' }, 405);

  let sessionId = readWishlistSessionId(req);
  let setCookie: string | undefined;
  if (isToggle && !sessionId && !ctx.loggedInCustomerId) {
    sessionId = crypto.randomUUID();
    setCookie = wishlistCookieHeader(sessionId);
  }

  const respond = (body: unknown, status = 200) =>
    jsonResponse(body, status, setCookie ? { 'Set-Cookie': setCookie } : undefined);

  let jwt: string | null = null;
  if (ctx.loggedInCustomerId) {
    try {
      const resolved = await resolveLoggedInWishlistMember(
        ctx.supabase,
        ctx.merchantConfig,
        ctx.shop,
        ctx.loggedInCustomerId,
        ctx.credentialRecord,
      );
      jwt = resolved.jwt;
      if (sessionId) {
        await ctx.supabase.rpc('fn_shopify_wishlist_merge_session', {
          p_merchant_id: ctx.merchantId,
          p_user_id: resolved.userId,
          p_session_id: sessionId,
        });
      }
    } catch (err: any) {
      const status = err.status || 500;
      return respond({ success: false, error: err.message || 'Member unavailable' }, status);
    }
  }

  if (isToggle) {
    const body = await req.json().catch(() => ({}));
    const variantId = body.variant_id || body.variantId;
    const productId = body.product_id || body.productId;
    const snapshot = body.snapshot && typeof body.snapshot === 'object'
      ? body.snapshot
      : { handle: body.handle, title: body.title, image_url: body.image_url || body.imageUrl };
    if (jwt) {
      const { data, error } = await memberClient(jwt).rpc('bff_user_toggle_wishlist_item', {
        p_variant_id: variantId,
        p_product_id: productId,
        p_snapshot: snapshot,
      });
      if (error) return respond({ success: false, error: error.message }, 500);
      if (data?.success === false) return respond(data, 400);
      return respond(unwrapWishlist(data));
    }
    if (!sessionId) return respond({ success: false, error: 'Session required' }, 400);
    const { data, error } = await ctx.supabase.rpc('fn_shopify_wishlist_toggle', {
      p_merchant_id: ctx.merchantId,
      p_user_id: null,
      p_session_id: sessionId,
      p_variant_id: variantId,
      p_product_id: productId,
      p_snapshot: snapshot,
    });
    if (error) return respond({ success: false, error: error.message }, 500);
    if (data?.success === false) return respond(data, 400);
    return respond(unwrapWishlist(data));
  }

  if (jwt) {
    const { data, error } = await memberClient(jwt).rpc('bff_user_get_wishlist');
    if (error) return respond({ success: false, error: error.message }, 500);
    if (data?.success === false) return respond(data, 400);
    return respond(unwrapWishlist(data));
  }
  const { data, error } = await ctx.supabase.rpc('fn_shopify_wishlist_get', {
    p_merchant_id: ctx.merchantId,
    p_user_id: null,
    p_session_id: sessionId,
  });
  if (error) return respond({ success: false, error: error.message }, 500);
  return respond(unwrapWishlist(data));
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders });
  try {
    const supabase = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const url = new URL(req.url);
    const params: Record<string, string> = {};
    for (const [key, value] of url.searchParams.entries()) params[key] = value;

    const { signature, hmac, shop, logged_in_customer_id } = params;
    if (!shop) return jsonResponse({ success: false, error: 'Missing shop parameter' }, 400);

    const merchantConfig = await getMerchantByShop(supabase, shop);
    if (!merchantConfig) return jsonResponse({ success: false, error: 'Merchant not found for shop', shop }, 404);

    const { merchant_id, merchant_code } = merchantConfig;
    let credentialRecord = await ensureValidShopifyCredentials(supabase, merchantConfig.credential_record);
    const credentials = credentialRecord.credentials || {};
    const { api_secret } = credentials;

    const isValidSignature = await verifyShopifyHMAC(params, signature || hmac, api_secret);
    if (!isValidSignature) return jsonResponse({ success: false, error: 'Invalid signature' }, 403);

    if (url.pathname.endsWith('/referral/page')) {
      return await handleReferralPage(supabase, merchant_code, req);
    }

    if (url.pathname.endsWith('/referral/claim')) {
      return await handleReferralClaim(
        supabase,
        merchant_id,
        merchant_code,
        req,
        shop,
        credentials.access_token || '',
      );
    }

    if (url.pathname.endsWith('/auth/signup') || url.pathname.endsWith('/auth/login')) {
      if (!logged_in_customer_id) return jsonResponse({ success: false, error: 'Customer not logged in', message: 'Please login to your Shopify account first' }, 401);

      let customer;
      try {
        customer = await fetchShopifyCustomer(shop, logged_in_customer_id, credentialRecord.credentials.access_token);
      } catch (error: any) {
        if (error.status === 401 && credentialRecord.credentials?.token_mode === 'offline_expiring' && credentialRecord.credentials?.refresh_token) {
          credentialRecord = await refreshShopifyToken(supabase, credentialRecord);
          customer = await fetchShopifyCustomer(shop, logged_in_customer_id, credentialRecord.credentials.access_token);
        } else {
          const status = error.status || 500;
          let details: any = error.message;
          if (error.body) { try { details = JSON.parse(error.body); } catch { details = error.body; } }
          return jsonResponse({ success: false, error: 'Failed to fetch customer data', details }, status);
        }
      }

      let dbUser;
      try {
        dbUser = await findOrCreateMember(supabase, merchant_id, customer);
      } catch (err: any) {
        return jsonResponse({ success: false, error: 'Failed to create user account', details: err.message }, 500);
      }

      let loyaltyToken: string;
      try {
        loyaltyToken = await mintShopifyMemberSessionToken(dbUser, merchant_id, String(customer.id));
      } catch (err: any) {
        const message = err?.message || 'Failed to mint member session';
        return jsonResponse({ success: false, error: message }, 500);
      }

      return jsonResponse({ success: true, token: loyaltyToken, customer: { email: customer.email, shopify_customer_id: customer.id.toString(), first_name: customer.first_name, last_name: customer.last_name } });
    }

    const normalizedPath = url.pathname.replace(/\/+$/, '');
    if (isLandingStorefrontPath(normalizedPath)) {
      return await handleLandingStorefront(
        supabase,
        merchant_code,
        merchant_id,
        req,
        shop,
        logged_in_customer_id,
        credentialRecord,
      );
    }

    if (normalizedPath.endsWith('/landing')) {
      return await handleLanding(
        supabase,
        merchant_code,
        merchant_id,
        req,
        shop,
        logged_in_customer_id,
        credentialRecord,
      );
    }

    const wishlistPath = normalizedPath;
    if (wishlistPath.endsWith('/wishlist/toggle') || wishlistPath.endsWith('/wishlist')) {
      return await handleWishlist(req, {
        supabase,
        merchantConfig,
        merchantId: merchant_id,
        shop,
        loggedInCustomerId: logged_in_customer_id,
        credentialRecord,
      });
    }

    if (url.pathname.endsWith('/api/rewards')) return jsonResponse({ error: 'Use direct RPC for now' }, 501);
    return jsonResponse({ error: 'Endpoint not found', path: url.pathname }, 404);
  } catch (error: any) {
    console.error('Error in shopify-proxy:', error);
    return jsonResponse({ success: false, error: error.message }, 500);
  }
});
