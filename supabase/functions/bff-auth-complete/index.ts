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
  email?: string;
}

interface MissingResult {
  missingData: any;
  hasMissingConsent: boolean;
  hasMissingProfile: boolean;
  hasMissingAddress: boolean;
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

/**
 * NEW: Filters fields to only those relevant to the user's persona
 * - If field has no persona restriction (persona_ids = null or []) → include for everyone
 * - If user has no persona → only include unrestricted fields
 * - If user has persona → include unrestricted fields + fields matching their persona
 */
function filterFieldsByPersona(fields: any[], userPersonaId: string | null): any[] {
  return fields.filter(field => {
    // Universal fields (no persona restriction) → always visible
    if (!field.persona_ids || field.persona_ids.length === 0) {
      return true;
    }
    
    // User has no persona → skip persona-restricted fields
    if (!userPersonaId) {
      return false;
    }
    
    // User has persona → check if it matches
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
  
  // PDPA consents (not persona-filtered)
  if (template.pdpa && Array.isArray(template.pdpa)) {
    missingData.pdpa = template.pdpa.filter((item: any) => item.is_mandatory === true && item.isAccepted === false);
  }
  
  // Default fields with persona filtering
  if (template.default_fields_config && Array.isArray(template.default_fields_config)) {
    for (const group of template.default_fields_config) {
      // First filter by persona, then check for missing values
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
  
  // Custom fields with persona filtering
  if (template.custom_fields_config && Array.isArray(template.custom_fields_config)) {
    for (const group of template.custom_fields_config) {
      // First filter by persona, then check for missing values
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
  // Apply persona filtering to full form data as well
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
    const { merchant_code, line_user_id, otp_code, session_id, access_token, user_id, source, email } = input;
    const tel = normalizeTel(input.tel);
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
    const { data: merchantData } = await supabase.from('merchant_master').select('auth_methods').eq('id', merchant_id).single();
    const authMethods: string[] = merchantData?.auth_methods || ['line'];
    const hasLine = !!line_user_id;
    let hasTel = false;
    let hasShopifyEmail = false;
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
        details: `Missing required parameters: ${missingParams.join(', ')}. For phone verification, you must provide tel, otp_code, and session_id together.`
      }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }
    if (allTelParamsProvided) {
      const { data: recentlyVerified } = await supabase.from('otp_requests').select('*').eq('session_id', session_id).eq('otp_code', otp_code).eq('verified', true).gt('expires_at', new Date(Date.now() - 5 * 60 * 1000).toISOString()).single();
      if (recentlyVerified && normalizeTel(recentlyVerified.phone) === tel) {
        hasTel = true;
      } else {
        const { data: otpData } = await supabase.from('otp_requests').select('*').eq('session_id', session_id).eq('otp_code', otp_code).eq('verified', false).gt('expires_at', new Date().toISOString()).single();
        if (otpData && otpData.attempts < 3 && normalizeTel(otpData.phone) === tel) {
          await supabase.from('otp_requests').update({ verified: true }).eq('id', otpData.id);
          hasTel = true;
        } else {
          return new Response(JSON.stringify({ success: false, error: 'Invalid or expired OTP' }), {
            status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          });
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
        const { data: existingUser } = await supabase.from('user_accounts').select('*').eq('id', userId).single();
        if (existingUser) {
          userAccount = existingUser;
          const updates: any = {};
          if (hasTel && !existingUser.tel) updates.tel = tel;
          if (hasLine && !existingUser.line_id) updates.line_id = line_user_id;
          if (Object.keys(updates).length > 0) {
            const { data: updated } = await supabase.from('user_accounts').update(updates).eq('id', userId).select().single();
            userAccount = updated || userAccount;
          }
        }
      } catch (e) {
        console.error('Invalid access_token:', e);
      }
    }
    if (!userAccount && hasShopifyEmail && user_id) {
      const { data: shopifyUser } = await supabase.from('user_accounts').select('*').eq('id', user_id).eq('merchant_id', merchant_id).single();
      if (shopifyUser) {
        userAccount = shopifyUser;
        console.log('✅ Shopify user found:', userAccount.id);
      }
    }
    if (!userAccount) {
      let userByLine: any = null;
      let userByTel: any = null;
      if (hasLine) {
        const { data } = await supabase.from('user_accounts').select('*').eq('merchant_id', merchant_id).eq('line_id', line_user_id).single();
        userByLine = data;
      }
      if (hasTel) {
        const { data } = await supabase.from('user_accounts').select('*').eq('merchant_id', merchant_id).eq('tel', tel).single();
        userByTel = data;
      }
      if (userByLine && userByTel && userByLine.id !== userByTel.id) {
        return new Response(JSON.stringify({ success: false, error: 'Credentials belong to different accounts', details: 'LINE and phone are registered to different users' }), { status: 409, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
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
      const { data: newUser, error: createError } = await supabase.from('user_accounts').insert({ merchant_id, line_id: hasLine ? line_user_id : null, tel: hasTel ? tel : null, email: hasShopifyEmail ? email : null, is_signup_form_complete: false }).select().single();
      if (createError) {
        return new Response(JSON.stringify({ success: false, error: 'Failed to create account', details: createError.message }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      }
      await supabase.from('user_accounts').update({ auth_user_id: newUser.id }).eq('id', newUser.id);
      userAccount = { ...newUser, auth_user_id: newUser.id };
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
      const updates: any = {};
      if (hasTel && !userAccount.tel) updates.tel = tel;
      if (hasLine && !userAccount.line_id) updates.line_id = line_user_id;
      if (Object.keys(updates).length > 0) {
        const { data: updated } = await supabase.from('user_accounts').update(updates).eq('id', userAccount.id).select().single();
        userAccount = updated || userAccount;
      }
    }
    const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(JWT_SECRET), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
    const accessTokenJwt = await create(
      { alg: 'HS256', typ: 'JWT' },
      { sub: userAccount.id, merchant_id: merchant_id, user_id: userAccount.id, phone: userAccount.tel, line_id: userAccount.line_id, email: userAccount.email, role: 'authenticated', aud: 'authenticated', iss: 'supabase', exp: getNumericDate(ACCESS_TOKEN_EXPIRY) },
      key
    );
    const missingTel = authMethods.includes('tel') && !userAccount.tel;
    const missingLine = authMethods.includes('line') && !userAccount.line_id;
    const missingShopifyEmail = authMethods.includes('shopify_email') && !userAccount.external_user_id?.startsWith('shopify:');
    const baseUserAccountPayload: any = { id: userAccount.id, tel: userAccount.tel, line_id: userAccount.line_id, email: userAccount.email, fullname: userAccount.fullname, persona_id: userAccount.persona_id, profile_complete: false };
    if (missingLine || missingTel || missingShopifyEmail) {
      let nextStep = 'verify_line';
      let message = 'LINE login required';
      if (missingTel) {
        nextStep = 'verify_tel';
        message = 'Phone verification required';
      } else if (missingShopifyEmail) {
        nextStep = 'verify_shopify';
        message = 'Shopify login required';
      }
      const refreshToken = crypto.randomUUID() + '-' + crypto.randomUUID();
      await supabase.from('refresh_tokens').insert({ user_id: userAccount.id, token: refreshToken, expires_at: new Date(Date.now() + REFRESH_TOKEN_EXPIRY * 1000).toISOString() });
      return new Response(JSON.stringify({ success: true, next_step: nextStep, message, user_account: baseUserAccountPayload, access_token: accessTokenJwt, refresh_token: refreshToken, expires_in: ACCESS_TOKEN_EXPIRY, is_new_user: isNewUser, is_signup_form_complete: userAccount.is_signup_form_complete ?? false, missing: { tel: missingTel, line: missingLine, shopify_email: missingShopifyEmail, consent: false, profile: false, address: false }, missing_data: null, profile_check_skipped: true }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }
    
    // Get user's persona_id for filtering
    const userPersonaId = userAccount.persona_id || null;
    console.log(`[PERSONA_FILTER] User persona: ${userPersonaId || 'none'}`);
    
    const userSupabase = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: `Bearer ${accessTokenJwt}`, 'x-merchant-id': merchant_id } } });
    const { data: profileTemplate } = await userSupabase.rpc('bff_get_user_profile_template', { p_language: 'th', p_mode: 'edit' });
    
    // ✅ FIX: Inject user's persona_id into template if they have one
    if (profileTemplate && userPersonaId && profileTemplate.persona) {
      console.log(`[PERSONA_INJECT] Before: selected_persona_id = ${profileTemplate.persona.selected_persona_id}`);
      profileTemplate.persona.selected_persona_id = userPersonaId;
      console.log(`[PERSONA_INJECT] After: selected_persona_id = ${profileTemplate.persona.selected_persona_id}`);
    }
    
    // Apply persona-aware filtering
    const { missingData, hasMissingConsent, hasMissingProfile, hasMissingAddress } = filterToMissingOnly(profileTemplate || {}, userPersonaId);
    console.log(`[PERSONA_FILTER] Missing persona_groups count: ${missingData?.persona?.persona_groups?.length || 0}`);
    
    const missing = { tel: false, line: false, shopify_email: false, consent: hasMissingConsent, profile: hasMissingProfile, address: hasMissingAddress };
    const isSignupFormComplete = userAccount.is_signup_form_complete ?? false;
    
    // Calculate profile_complete: true if no missing persona-relevant required fields
    const profileComplete = !hasMissingConsent && !hasMissingProfile;
    
    let nextStep = 'complete';
    if (isNewUser) {
      nextStep = 'complete_profile_new';
    } else if (!isSignupFormComplete || hasMissingConsent || hasMissingProfile) {
      nextStep = 'complete_profile_existing';
    }
    let missingDataResult: any = null;
    if (nextStep === 'complete_profile_new') {
      missingDataResult = extractFullFormData(profileTemplate || {}, userPersonaId);
    } else if (nextStep === 'complete_profile_existing') {
      if (!isSignupFormComplete) {
        missingDataResult = extractFullFormData(profileTemplate || {}, userPersonaId);
      } else {
        missingDataResult = missingData;
      }
    }
    const refreshToken = crypto.randomUUID() + '-' + crypto.randomUUID();
    await supabase.from('refresh_tokens').insert({ user_id: userAccount.id, token: refreshToken, expires_at: new Date(Date.now() + REFRESH_TOKEN_EXPIRY * 1000).toISOString() });
    let userAccountPayload: any = { ...baseUserAccountPayload, profile_complete: profileComplete };
    if (nextStep === 'complete') {
      const { data } = await userSupabase.rpc('get_user_summary');
      if (data && typeof data === 'object' && !('error' in data)) {
        userAccountPayload = { ...data, id: userAccount.id, line_id: userAccount.line_id, email: userAccount.email, profile_complete: profileComplete };
      }
    }
    
    console.log(`[PERSONA_FILTER] Final next_step: ${nextStep}, profile_complete: ${profileComplete}`);
    
    return new Response(JSON.stringify({ success: true, next_step: nextStep, user_account: userAccountPayload, access_token: accessTokenJwt, refresh_token: refreshToken, expires_in: ACCESS_TOKEN_EXPIRY, is_new_user: isNewUser, is_signup_form_complete: isSignupFormComplete, missing, missing_data: missingDataResult }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  } catch (error) {
    console.error('Error in bff-auth-complete:', error);
    return new Response(JSON.stringify({ success: false, error: error.message }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
});
