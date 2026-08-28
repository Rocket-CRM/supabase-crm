import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4';
import { create, getNumericDate, verify } from 'https://deno.land/x/djwt@v2.8/mod.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type'
};

const JWT_SECRET = Deno.env.get('SUPABASE_JWT_SECRET') || Deno.env.get('JWT_SECRET');
const ACCESS_TOKEN_EXPIRY = 30 * 24 * 60 * 60;
const REFRESH_TOKEN_EXPIRY = 30 * 24 * 60 * 60;

interface AuthInput {
  merchant_code: string;
  line_user_id?: string;
  tel?: string;
  otp_code?: string;
  session_id?: string;
  access_token?: string;
  user_id?: string;
  source?: string;
  acquisition_source?: string;
  email?: string;
  bot_secret?: string;
  selected_persona_id?: string;
  language?: string;
}

interface MissingResult {
  missingData: any;
  hasMissingConsent: boolean;
  hasMissingProfile: boolean;
  hasMissingAddress: boolean;
}

function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return result === 0;
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function normalizeTel(tel: string | undefined | null): string | null {
  if (!tel) return null;
  let normalized = tel.trim();
  normalized = normalized.replace(/[\s-]/g, '');
  if (normalized.startsWith('+660')) {
    normalized = '+66' + normalized.substring(4);
  } else if (normalized.startsWith('0')) {
    normalized = '+66' + normalized.substring(1);
  } else if (normalized.startsWith('66') && !normalized.startsWith('+')) {
    normalized = '+' + normalized;
  }
  return normalized;
}

function normalizeLineId(value: string | undefined | null): string | null {
  if (!value) return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  if (trimmed === 'undefined' || trimmed === 'null') return null;
  return trimmed;
}

function normalizeAcquisitionSource(value: string | undefined | null): string | null {
  if (!value) return null;
  const trimmed = value.trim();
  return trimmed || null;
}

function normalizeLanguage(value: string | undefined | null): string {
  if (!value) return 'th';
  const normalized = value.trim().toLowerCase().slice(0, 2);
  if (normalized === 'en' || normalized === 'th') return normalized;
  return 'th';
}

function applyAcquisitionSourceUpdate(
  updates: Record<string, unknown>,
  userAccount: { acquisition_source?: string | null },
  acquisitionSource: string | null
) {
  if (acquisitionSource && !userAccount.acquisition_source) {
    updates.acquisition_source = acquisitionSource;
  }
}

function filterFieldsByPersona(fields: any[], userPersonaId: string | null): any[] {
  return fields.filter(field => {
    if (!field.persona_ids || field.persona_ids.length === 0) {
      return true;
    }
    if (!userPersonaId) {
      return false;
    }
    return field.persona_ids.includes(userPersonaId);
  });
}

function filterToMissingOnly(template: any, userPersonaId: string | null): MissingResult {
  const missingData: any = {
    persona: template.persona ? {
      selected_persona_id: template.persona.selected_persona_id || null,
      merchant_config: template.persona.merchant_config || null,
      persona_groups: (!template.persona.selected_persona_id) ? template.persona.persona_groups : []
    } : null,
    pdpa: [],
    default_fields_config: [],
    custom_fields_config: []
  };
  let hasMissingAddress = false;

  if (template.pdpa && Array.isArray(template.pdpa)) {
    missingData.pdpa = template.pdpa.filter((item: any) => item.is_mandatory === true && item.isAccepted === false);
  }

  if (template.default_fields_config && Array.isArray(template.default_fields_config)) {
    for (const group of template.default_fields_config) {
      const personaRelevantFields = filterFieldsByPersona(group.fields || [], userPersonaId);
      const missingFields = personaRelevantFields.filter((field: any) => {
        const isMissing = field.is_required === true && (field.value === null || field.value === '' || field.value === undefined);
        if (isMissing && field.is_address_field === true) {
          hasMissingAddress = true;
        }
        return isMissing;
      });
      if (missingFields.length > 0) {
        missingData.default_fields_config.push({ ...group, fields: missingFields });
      }
    }
  }

  if (template.custom_fields_config && Array.isArray(template.custom_fields_config)) {
    for (const group of template.custom_fields_config) {
      const personaRelevantFields = filterFieldsByPersona(group.fields || [], userPersonaId);
      const missingFields = personaRelevantFields.filter(
        (field: any) => field.is_required === true && (field.value === null || field.value === '' || field.value === undefined)
      );
      if (missingFields.length > 0) {
        missingData.custom_fields_config.push({ ...group, fields: missingFields });
      }
    }
  }

  const hasMissingConsent = missingData.pdpa.length > 0;
  const hasMissingProfile = missingData.default_fields_config.length > 0 || missingData.custom_fields_config.length > 0;
  return { missingData, hasMissingConsent, hasMissingProfile, hasMissingAddress };
}

function extractFullFormData(template: any, userPersonaId: string | null): any {
  const filteredDefaultConfig = template.default_fields_config?.map((group: any) => ({
    ...group,
    fields: filterFieldsByPersona(group.fields || [], userPersonaId)
  })) || [];

  const filteredCustomConfig = template.custom_fields_config?.map((group: any) => ({
    ...group,
    fields: filterFieldsByPersona(group.fields || [], userPersonaId)
  })) || [];

  return {
    persona: template.persona || null,
    pdpa: template.pdpa || [],
    default_fields_config: filteredDefaultConfig,
    custom_fields_config: filteredCustomConfig,
    selected_section: template.selected_section || null
  };
}

async function getMerchantId(supabase: any, merchantCode: string): Promise<string | null> {
  const { data, error } = await supabase.from('merchant_master').select('id').eq('merchant_code', merchantCode).single();
  if (error || !data) return null;
  return data.id;
}

async function backfillAuthUserIdIfMissing(supabase: any, userAccount: any): Promise<any> {
  if (!userAccount || userAccount.auth_user_id) return userAccount;
  const { data: backfilled, error: bkErr } = await supabase.rpc('chokepoint_post_user_event', {
    p_event_type: 'update',
    p_user_id: userAccount.id,
    p_changes: { auth_user_id: userAccount.id },
    p_actor: { actor_type: 'edge_fn', edge_fn: 'bff-auth-complete', reason: 'auth_user_id backfill on login' }
  });
  if (bkErr) {
    console.error('[AUTH_USER_ID_BACKFILL] chokepoint error', bkErr);
    return userAccount;
  }
  return backfilled || { ...userAccount, auth_user_id: userAccount.id };
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }
  try {
    if (!JWT_SECRET) {
      return new Response(JSON.stringify({ success: false, error: 'JWT secret not configured' }), {
        status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }
    const supabase = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const input: AuthInput = await req.json();
    const { merchant_code, otp_code, session_id, access_token, user_id, source, email, bot_secret } = input;
    const tel = normalizeTel(input.tel);
    const lineUserId = normalizeLineId(input.line_user_id);
    const acquisitionSource = normalizeAcquisitionSource(input.acquisition_source);
    const language = normalizeLanguage(input.language);
    const requestedSelectedPersonaId = typeof input.selected_persona_id === 'string' && input.selected_persona_id.trim()
      ? input.selected_persona_id.trim()
      : null;
    if (!merchant_code) {
      return new Response(JSON.stringify({ success: false, error: 'merchant_code is required' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }
    const merchant_id = await getMerchantId(supabase, merchant_code);
    if (!merchant_id) {
      return new Response(JSON.stringify({ success: false, error: 'Invalid merchant_code' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    let selectedPersonaId: string | null = null;
    if (requestedSelectedPersonaId) {
      if (!isUuid(requestedSelectedPersonaId)) {
        return new Response(JSON.stringify({ success: false, error: 'Invalid selected_persona_id' }), {
          status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        });
      }
      const { data: selectedPersona } = await supabase
        .from('persona_master')
        .select('id')
        .eq('id', requestedSelectedPersonaId)
        .eq('merchant_id', merchant_id)
        .eq('active_status', true)
        .single();
      if (!selectedPersona) {
        return new Response(JSON.stringify({ success: false, error: 'selected_persona_id is not valid for this merchant' }), {
          status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        });
      }
      selectedPersonaId = selectedPersona.id;
    }

    const { data: merchantData } = await supabase.from('merchant_master').select('auth_methods').eq('id', merchant_id).single();
    const authMethods: string[] = merchantData?.auth_methods || ['line'];
    const hasLine = !!lineUserId;
    let hasTel = false;
    let hasShopifyEmail = false;

    let isBotAuth = false;
    if (bot_secret) {
      const BOT_SECRET = Deno.env.get('BOT_SECRET');
      if (!BOT_SECRET) {
        return new Response(JSON.stringify({ success: false, error: 'Bot authentication is not configured on this project' }), {
          status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        });
      }
      if (!constantTimeEqual(bot_secret, BOT_SECRET)) {
        return new Response(JSON.stringify({ success: false, error: 'Invalid bot_secret' }), {
          status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        });
      }
      isBotAuth = true;
      if (tel) hasTel = true;
      console.log(`[BOT_AUTH] Bot authentication bypass for merchant=${merchant_code} tel=${tel || 'none'} line=${lineUserId || 'none'}`);
    }

    if (!isBotAuth) {
      const hasTelParam = !!tel;
      const hasOtpParam = !!otp_code;
      const hasSessionParam = !!session_id;
      const anyTelParamsProvided = hasTelParam || hasOtpParam || hasSessionParam;
      const allTelParamsProvided = hasTelParam && hasOtpParam && hasSessionParam;
      if (anyTelParamsProvided && !allTelParamsProvided) {
        const missingParams: string[] = [];
        if (!hasTelParam) missingParams.push('tel');
        if (!hasOtpParam) missingParams.push('otp_code');
        if (!hasSessionParam) missingParams.push('session_id');
        return new Response(JSON.stringify({
          success: false, error: 'Incomplete phone verification parameters',
          details: `Missing required parameters: ${missingParams.join(', ')}.`
        }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      }
      if (allTelParamsProvided) {
        const { data: recentlyVerified } = await supabase.from('otp_requests').select('*').eq('session_id', session_id).eq('otp_code', otp_code).eq('verified', true).gt('expires_at', new Date(Date.now() - 5 * 60 * 1000).toISOString()).single();
        if (recentlyVerified && normalizeTel(recentlyVerified.phone) === tel) {
          hasTel = true;
        } else {
          const { data: sessionOtp } = await supabase.from('otp_requests').select('*').eq('session_id', session_id).eq('verified', false).gt('expires_at', new Date().toISOString()).single();
          if (!sessionOtp || sessionOtp.attempts >= 3) {
            return new Response(JSON.stringify({ success: false, error: !sessionOtp ? 'Invalid or expired OTP' : 'Maximum OTP attempts exceeded' }), {
              status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
            });
          }
          if (sessionOtp.otp_code === otp_code && normalizeTel(sessionOtp.phone) === tel) {
            await supabase.from('otp_requests').update({ verified: true }).eq('id', sessionOtp.id);
            hasTel = true;
          } else {
            await supabase.from('otp_requests').update({ attempts: sessionOtp.attempts + 1 }).eq('id', sessionOtp.id);
            const remaining = Math.max(0, 3 - (sessionOtp.attempts + 1));
            return new Response(JSON.stringify({ success: false, error: 'Invalid or expired OTP', attempts_remaining: remaining }), {
              status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
            });
          }
        }
      }
    }

    if (source === 'shopify' && user_id) {
      hasShopifyEmail = true;
    }
    let userAccount: any = null;
    let isNewUser = false;
    if (access_token) {
      try {
        const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(JWT_SECRET), { name: 'HMAC', hash: 'SHA-256' }, false, ['verify']);
        const payload = await verify(access_token, key);
        const userId = payload.sub as string;
        const { data: existingUser } = await supabase.from('user_accounts').select('*').eq('id', userId).is('deleted_at', null).single();
        if (existingUser) {
          userAccount = existingUser;
          const updates: Record<string, unknown> = {};
          if (hasTel && !existingUser.tel) updates.tel = tel;
          if (hasLine && !existingUser.line_id) updates.line_id = lineUserId;
          applyAcquisitionSourceUpdate(updates, existingUser, acquisitionSource);
          if (Object.keys(updates).length > 0) {
            const { data: updated, error: updErr } = await supabase.rpc('chokepoint_post_user_event', {
              p_event_type: 'update',
              p_user_id: userId,
              p_changes: updates,
              p_actor: { actor_type: 'edge_fn', edge_fn: 'bff-auth-complete' }
            });
            if (updErr) console.error('[CHOKEPOINT_UPDATE_AUTH_LINK] error', updErr);
            userAccount = updated || userAccount;
          }
        }
      } catch (e) {
        console.error('Invalid access_token:', e);
      }
    }
    if (!userAccount && hasShopifyEmail && user_id) {
      const { data: shopifyUser } = await supabase.from('user_accounts').select('*').eq('id', user_id).eq('merchant_id', merchant_id).is('deleted_at', null).single();
      if (shopifyUser) {
        userAccount = shopifyUser;
      }
    }
    if (!userAccount) {
      let userByLine: any = null;
      let userByTel: any = null;
      if (hasLine) {
        const { data, error } = await supabase
          .from('user_accounts')
          .select('*')
          .eq('merchant_id', merchant_id)
          .eq('line_id', lineUserId)
          .is('deleted_at', null)
          .order('is_signup_form_complete', { ascending: false, nullsFirst: false })
          .order('persona_id', { ascending: false, nullsFirst: false })
          .order('updated_at', { ascending: false, nullsFirst: false })
          .order('created_at', { ascending: true })
          .order('id', { ascending: true })
          .limit(1)
          .maybeSingle();
        if (error) {
          console.error('[LINE_LOOKUP] error', { merchant_id, line_id: lineUserId, error });
        }
        userByLine = data;
      }
      if (hasTel) {
        const { data, error } = await supabase
          .from('user_accounts')
          .select('*')
          .eq('merchant_id', merchant_id)
          .eq('tel', tel)
          .is('deleted_at', null)
          .order('is_signup_form_complete', { ascending: false, nullsFirst: false })
          .order('persona_id', { ascending: false, nullsFirst: false })
          .order('updated_at', { ascending: false, nullsFirst: false })
          .order('created_at', { ascending: true })
          .order('id', { ascending: true })
          .limit(1)
          .maybeSingle();
        if (error) {
          console.error('[TEL_LOOKUP] error', { merchant_id, tel, error });
        }
        userByTel = data;
      }
      if (userByLine && userByTel && userByLine.id !== userByTel.id) {
        return new Response(JSON.stringify({ success: false, error: 'Credentials belong to different accounts' }), { status: 409, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      }
      userAccount = userByLine || userByTel;
    }
    if (!userAccount) {
      const needsLine = authMethods.includes('line');
      const needsTel = authMethods.includes('tel');
      const needsShopifyEmail = authMethods.includes('shopify_email');
      const hasBoth = needsLine && needsTel;
      if (hasBoth) {
        if (!hasLine) {
          return new Response(JSON.stringify({ success: true, next_step: 'verify_line', message: 'LINE login required' }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
        }
        if (!hasTel) {
          return new Response(JSON.stringify({ success: true, next_step: 'verify_tel', message: 'Phone verification required' }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
        }
      } else if (needsLine && !hasLine) {
        return new Response(JSON.stringify({ success: true, next_step: 'verify_line', message: 'LINE login required' }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      } else if (needsTel && !hasTel) {
        return new Response(JSON.stringify({ success: true, next_step: 'verify_tel', message: 'Phone verification required' }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      } else if (needsShopifyEmail && !hasShopifyEmail) {
        return new Response(JSON.stringify({ success: true, next_step: 'verify_shopify', message: 'Shopify login required' }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      }
      const newUserId = crypto.randomUUID();
      const { data: newUser, error: createError } = await supabase.rpc('chokepoint_post_user_event', {
        p_event_type: 'create',
        p_merchant_id: merchant_id,
        p_changes: {
          id: newUserId,
          auth_user_id: newUserId,
          line_id: hasLine ? lineUserId : null,
          tel: hasTel ? tel : null,
          email: hasShopifyEmail ? email : null,
          is_signup_form_complete: false,
          ...(acquisitionSource ? { acquisition_source: acquisitionSource } : {})
        },
        p_actor: { actor_type: 'edge_fn', edge_fn: 'bff-auth-complete' }
      });
      if (createError || !newUser) {
        return new Response(JSON.stringify({ success: false, error: 'Failed to create account', details: createError?.message }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      }
      userAccount = newUser;
      isNewUser = true;
    } else {
      const needsTel = authMethods.includes('tel');
      const needsShopifyEmail = authMethods.includes('shopify_email');
      if (needsTel && !userAccount.tel && !hasTel) {
        return new Response(JSON.stringify({ success: true, next_step: 'verify_tel', message: 'Phone verification required' }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      }
      if (needsShopifyEmail && !userAccount.external_user_id?.startsWith('shopify:') && !hasShopifyEmail) {
        return new Response(JSON.stringify({ success: true, next_step: 'verify_shopify', message: 'Shopify login required' }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      }
      const updates: Record<string, unknown> = {};
      if (hasTel && !userAccount.tel) updates.tel = tel;
      if (hasLine && !userAccount.line_id) updates.line_id = lineUserId;
      applyAcquisitionSourceUpdate(updates, userAccount, acquisitionSource);
      if (Object.keys(updates).length > 0) {
        const { data: updated, error: updErr } = await supabase.rpc('chokepoint_post_user_event', {
          p_event_type: 'update',
          p_user_id: userAccount.id,
          p_changes: updates,
          p_actor: { actor_type: 'edge_fn', edge_fn: 'bff-auth-complete' }
        });
        if (updErr) console.error('[CHOKEPOINT_UPDATE_BACKFILL] error', updErr);
        userAccount = updated || userAccount;
      }
    }

    userAccount = await backfillAuthUserIdIfMissing(supabase, userAccount);

    const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(JWT_SECRET), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
    const accessTokenJwt = await create(
      { alg: 'HS256', typ: 'JWT' },
      { sub: userAccount.id, merchant_id, user_id: userAccount.id, phone: userAccount.tel, line_id: userAccount.line_id, email: userAccount.email, role: 'authenticated', aud: 'authenticated', iss: 'supabase', exp: getNumericDate(ACCESS_TOKEN_EXPIRY) },
      key
    );
    const userSupabase = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: { headers: { Authorization: `Bearer ${accessTokenJwt}` } }
    });
    const missingTel = authMethods.includes('tel') && !userAccount.tel;
    const missingLine = authMethods.includes('line') && !userAccount.line_id;
    const missingShopifyEmail = authMethods.includes('shopify_email') && !userAccount.external_user_id?.startsWith('shopify:');
    const baseUserAccountPayload: any = { id: userAccount.id, tel: userAccount.tel, line_id: userAccount.line_id, email: userAccount.email, fullname: userAccount.fullname, persona_id: userAccount.persona_id, profile_complete: false };
    if (missingLine || missingTel || missingShopifyEmail) {
      let nextStep = 'verify_line';
      let message = 'LINE login required';
      if (missingTel) { nextStep = 'verify_tel'; message = 'Phone verification required'; }
      else if (missingShopifyEmail) { nextStep = 'verify_shopify'; message = 'Shopify login required'; }
      const refreshToken = crypto.randomUUID() + '-' + crypto.randomUUID();
      await supabase.from('refresh_tokens').insert({ user_id: userAccount.id, token: refreshToken, expires_at: new Date(Date.now() + REFRESH_TOKEN_EXPIRY * 1000).toISOString() });
      return new Response(JSON.stringify({ success: true, next_step: nextStep, message, user_account: baseUserAccountPayload, access_token: accessTokenJwt, refresh_token: refreshToken, expires_in: ACCESS_TOKEN_EXPIRY, is_new_user: isNewUser, is_signup_form_complete: userAccount.is_signup_form_complete ?? false, missing: { tel: missingTel, line: missingLine, shopify_email: missingShopifyEmail, consent: false, profile: false, address: false }, missing_data: null, profile_check_skipped: true }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const userPersonaId = userAccount.persona_id || null;
    const effectivePersonaId = selectedPersonaId || userPersonaId;
    const isSignupFormComplete = userAccount.is_signup_form_complete ?? false;
    console.log(`[PERSONA_FILTER] User persona: ${userPersonaId || 'none'}, selected persona: ${selectedPersonaId || 'none'}, effective persona: ${effectivePersonaId || 'none'}, is_signup_form_complete: ${isSignupFormComplete}`);

    const { data: profileTemplate, error: profileTemplateError } = await userSupabase.rpc('bff_get_user_profile_template', {
      p_language: language,
      p_mode: 'edit',
      p_merchant_code: merchant_code,
      p_selected_persona_id: effectivePersonaId
    });

    if (profileTemplateError) {
      console.error(`[PROFILE_TEMPLATE] RPC error:`, profileTemplateError);
    }
    const templateFieldCount = profileTemplate?.default_fields_config?.[0]?.fields?.length ?? 0;
    console.log(`[PROFILE_TEMPLATE] Template loaded: language=${language}, hasData=${!!profileTemplate}, defaultFieldCount=${templateFieldCount}, customGroupCount=${profileTemplate?.custom_fields_config?.length ?? 0}, pdpaCount=${profileTemplate?.pdpa?.length ?? 0}`);

    if (profileTemplate && effectivePersonaId && profileTemplate.persona) {
      profileTemplate.persona.selected_persona_id = effectivePersonaId;
    }

    const { missingData, hasMissingConsent, hasMissingProfile, hasMissingAddress } = filterToMissingOnly(profileTemplate || {}, effectivePersonaId);

    const missing = { tel: false, line: false, shopify_email: false, consent: hasMissingConsent, profile: hasMissingProfile, address: hasMissingAddress };
    const profileActuallyComplete = !isNewUser && isSignupFormComplete && !hasMissingConsent && !hasMissingProfile;

    if (profileActuallyComplete) {
      console.log(`[FINAL] Returning complete - required profile and consent are filled`);
      const refreshToken = crypto.randomUUID() + '-' + crypto.randomUUID();
      await supabase.from('refresh_tokens').insert({ user_id: userAccount.id, token: refreshToken, expires_at: new Date(Date.now() + REFRESH_TOKEN_EXPIRY * 1000).toISOString() });
      let userAccountPayload: any = { id: userAccount.id, tel: userAccount.tel, line_id: userAccount.line_id, email: userAccount.email, fullname: userAccount.fullname, persona_id: userAccount.persona_id, profile_complete: true };
      const { data: summaryData } = await userSupabase.rpc('get_user_summary');
      if (summaryData && typeof summaryData === 'object' && !('error' in summaryData)) {
        userAccountPayload = { ...summaryData, id: userAccount.id, line_id: userAccount.line_id, email: userAccount.email, profile_complete: true };
      }
      return new Response(JSON.stringify({ success: true, next_step: 'complete', user_account: userAccountPayload, access_token: accessTokenJwt, refresh_token: refreshToken, expires_in: ACCESS_TOKEN_EXPIRY, is_new_user: false, is_signup_form_complete: true, missing: { tel: false, line: false, shopify_email: false, consent: false, profile: false, address: false }, missing_data: null }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const nextStep = isNewUser ? 'complete_profile_new' : 'complete_profile_existing';

    let missingDataResult: any = null;
    if (isNewUser || !isSignupFormComplete) {
      missingDataResult = extractFullFormData(profileTemplate || {}, effectivePersonaId);
      console.log(`[FORM_DATA] Full form: defaultGroups=${missingDataResult.default_fields_config?.length ?? 0}, defaultFields=${missingDataResult.default_fields_config?.[0]?.fields?.length ?? 0}, pdpa=${missingDataResult.pdpa?.length ?? 0}`);
    } else {
      missingDataResult = missingData;
      console.log(`[FORM_DATA] Missing-only form: defaultGroups=${missingDataResult.default_fields_config?.length ?? 0}, defaultFields=${missingDataResult.default_fields_config?.[0]?.fields?.length ?? 0}, pdpa=${missingDataResult.pdpa?.length ?? 0}`);
    }

    const refreshToken = crypto.randomUUID() + '-' + crypto.randomUUID();
    await supabase.from('refresh_tokens').insert({ user_id: userAccount.id, token: refreshToken, expires_at: new Date(Date.now() + REFRESH_TOKEN_EXPIRY * 1000).toISOString() });

    console.log(`[FINAL] next_step=${nextStep}, is_signup_form_complete=${isSignupFormComplete}`);

    return new Response(JSON.stringify({ success: true, next_step: nextStep, user_account: baseUserAccountPayload, access_token: accessTokenJwt, refresh_token: refreshToken, expires_in: ACCESS_TOKEN_EXPIRY, is_new_user: isNewUser, is_signup_form_complete: isSignupFormComplete, missing, missing_data: missingDataResult }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  } catch (error) {
    console.error('Error in bff-auth-complete:', error);
    return new Response(JSON.stringify({ success: false, error: error.message }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
});
