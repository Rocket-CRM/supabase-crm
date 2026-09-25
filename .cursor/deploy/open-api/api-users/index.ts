import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.8';

const CRM_URL = Deno.env.get('CRM_PROJECT_URL') || 'https://wkevmsedchftztoolkmi.supabase.co';
const CRM_SERVICE_KEY = Deno.env.get('CRM_SERVICE_ROLE_KEY');

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-api-key',
  'Access-Control-Allow-Methods': 'POST, GET, PATCH, OPTIONS'
};

const LIMITS = { STANDARD_TEXT: 255, LONG_TEXT: 5000 };
const LONG_TEXT_FIELDS = ['notes', 'description', 'reason'];

function getFieldLimit(fieldName: string): number {
  return LONG_TEXT_FIELDS.some(f => fieldName.toLowerCase().includes(f)) ? LIMITS.LONG_TEXT : LIMITS.STANDARD_TEXT;
}

function validateObject(obj: any, parentKey = ''): Array<{field: string; error: string; limit: number; actual: number}> {
  const errors: Array<{field: string; error: string; limit: number; actual: number}> = [];
  if (!obj || typeof obj !== 'object') return errors;
  for (const [key, value] of Object.entries(obj)) {
    const fullKey = parentKey ? `${parentKey}.${key}` : key;
    if (typeof value === 'string') {
      const limit = getFieldLimit(key);
      if (value.length > limit) errors.push({ field: fullKey, error: 'Field exceeds maximum length', limit, actual: value.length });
    } else if (typeof value === 'object' && value !== null && !Array.isArray(value)) {
      errors.push(...validateObject(value, fullKey));
    } else if (Array.isArray(value)) {
      value.forEach((item, index) => {
        if (typeof item === 'string') {
          const limit = getFieldLimit(key);
          if (item.length > limit) errors.push({ field: `${fullKey}[${index}]`, error: 'Field exceeds maximum length', limit, actual: item.length });
        } else if (typeof item === 'object' && item !== null) {
          errors.push(...validateObject(item, `${fullKey}[${index}]`));
        }
      });
    }
  }
  return errors;
}

function definedOnly(obj: Record<string, any>): Record<string, any> {
  const result: Record<string, any> = {};
  for (const [k, v] of Object.entries(obj)) {
    if (v !== undefined) result[k] = v;
  }
  return result;
}

/** Default true. Legacy callers: `include_tier=false` or `include` without `tier`. */
function parseIncludeTier(url: URL): boolean {
  const includeTier = url.searchParams.get('include_tier');
  if (includeTier === 'false') return false;
  if (includeTier === 'true') return true;

  const include = url.searchParams.get('include');
  if (include === null) return true;

  return include
    .split(',')
    .map((part) => part.trim())
    .filter(Boolean)
    .includes('tier');
}

Deno.serve(async (req) => {
  const startTime = Date.now();
  const requestId = crypto.randomUUID();

  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const apiKey = req.headers.get('x-api-key');
    if (!apiKey) {
      return new Response(JSON.stringify({
        error: 'Missing x-api-key header', code: 'MISSING_API_KEY', request_id: requestId
      }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    if (!CRM_SERVICE_KEY) {
      return new Response(JSON.stringify({
        error: 'API gateway not configured', code: 'GATEWAY_CONFIG_ERROR', request_id: requestId
      }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const crmClient = createClient(CRM_URL, CRM_SERVICE_KEY);
    const { data: validation, error: validationError } = await crmClient.rpc('validate_api_key', { p_api_key: apiKey });

    if (validationError || !validation?.valid) {
      return new Response(JSON.stringify({
        error: 'Invalid or expired API key', code: 'INVALID_API_KEY', request_id: requestId
      }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const merchantId = validation.merchant_id;
    const url = new URL(req.url);
    const pathParts = url.pathname.split('/').filter(p => p);

    let identifierType = null;
    let identifierValue = null;

    if (pathParts.length === 3 && pathParts[1].startsWith('by-')) {
      identifierType = pathParts[1].replace('by-', '').replace(/-/g, '_');
      identifierValue = decodeURIComponent(pathParts[2]);
    } else if (pathParts.length === 2 && pathParts[1] !== 'api-users') {
      identifierValue = pathParts[1];
      identifierType = 'user_id';
    }

    let result;
    let statusCode = 200;

    if (req.method === 'POST') {
      const body = await req.json();
      const validationErrors = validateObject(body);
      if (validationErrors.length > 0) {
        return new Response(JSON.stringify({
          success: false, error: 'Validation failed', code: 'VALIDATION_FAILED', details: validationErrors, request_id: requestId
        }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      }

      const { data, error } = await crmClient.rpc('api_create_or_update_user', {
        p_merchant_id: merchantId,
        p_tel: body.tel,
        p_external_user_id: body.external_user_id ?? null,
        p_firstname: body.firstname ?? null,
        p_lastname: body.lastname ?? null,
        p_email: body.email ?? null,
        p_line_id: body.line_id ?? null,
        p_id_card: body.id_card ?? null,
        p_birth_date: body.birth_date ?? null,
        p_user_type: body.user_type ?? 'buyer',
        p_user_stage: body.user_stage ?? null,
        p_channel_email: body.channel_email ?? true,
        p_channel_sms: body.channel_sms ?? false,
        p_channel_line: body.channel_line ?? true,
        p_channel_push: body.channel_push ?? true,
        p_upsert: body.upsert ?? false,
        p_addresses: body.addresses ?? null,
        p_address_mode: body.address_mode ?? 'replace',
        p_form_submissions: body.form_submissions ?? null,
        p_acquisition_source: body.acquisition_source ?? null
      });

      if (error) {
        return new Response(JSON.stringify({
          error: 'User operation failed', code: 'USER_OPERATION_FAILED', details: error.message, request_id: requestId
        }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      }

      if (!data?.success) {
        statusCode = data?.code === 'USER_EXISTS' ? 409 : 400;
        return new Response(JSON.stringify({
          error: data?.error, code: data?.code, details: data?.details, request_id: requestId
        }), { status: statusCode, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      }

      statusCode = data.created ? 201 : 200;
      result = data;
    } else if (req.method === 'PATCH') {
      if (!identifierType || !identifierValue) {
        return new Response(JSON.stringify({
          error: 'Missing identifier in path', code: 'MISSING_IDENTIFIER',
          details: 'Use /api-users/by-{type}/{value}', request_id: requestId
        }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      }

      const body = await req.json();
      const validationErrors = validateObject(body);
      if (validationErrors.length > 0) {
        return new Response(JSON.stringify({
          success: false, error: 'Validation failed', code: 'VALIDATION_FAILED', details: validationErrors, request_id: requestId
        }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      }

      // Build body params (only include defined values)
      const bodyParams = definedOnly({
        p_fullname: body.fullname,
        p_firstname: body.firstname,
        p_lastname: body.lastname,
        p_email: body.email,
        p_tel: body.tel,
        p_line_id: body.line_id,
        p_id_card: body.id_card,
        p_birth_date: body.birth_date,
        p_user_stage: body.user_stage,
        p_channel_email: body.channel_email,
        p_channel_sms: body.channel_sms,
        p_channel_line: body.channel_line,
        p_channel_push: body.channel_push,
        p_addresses: body.addresses,
        p_address_mode: body.address_mode,
        p_form_submissions: body.form_submissions
      });

      // Build identifier params (these override body params to ensure correct lookup)
      const identifierParams: Record<string, any> = { p_merchant_id: merchantId };
      if (identifierType === 'external_id') identifierParams.p_external_user_id = identifierValue;
      else if (identifierType === 'email') identifierParams.p_email = identifierValue;
      else if (identifierType === 'tel') identifierParams.p_tel = identifierValue;
      else if (identifierType === 'line_id') identifierParams.p_line_id = identifierValue;
      else if (identifierType === 'user_id') identifierParams.p_user_id = identifierValue;

      const { data, error } = await crmClient.rpc('api_update_user', {
        ...bodyParams,
        ...identifierParams  // identifier always wins over body
      });

      if (error) {
        return new Response(JSON.stringify({
          error: 'Update failed', code: 'UPDATE_FAILED', details: error.message, request_id: requestId
        }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      }

      if (!data?.success) {
        statusCode = data?.code === 'USER_NOT_FOUND' ? 404 : 400;
        return new Response(JSON.stringify({
          error: data?.error, code: data?.code, request_id: requestId
        }), { status: statusCode, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      }

      result = data;
    } else if (req.method === 'GET') {
      if (!identifierType || !identifierValue) {
        return new Response(JSON.stringify({
          error: 'Missing identifier in path', code: 'MISSING_IDENTIFIER',
          details: 'Use /api-users/by-{type}/{value}', request_id: requestId
        }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      }

      const identifierParams: Record<string, any> = {
        p_merchant_id: merchantId,
        p_include_tier: parseIncludeTier(url),
      };
      if (identifierType === 'external_id') identifierParams.p_external_user_id = identifierValue;
      else if (identifierType === 'email') identifierParams.p_email = identifierValue;
      else if (identifierType === 'tel') identifierParams.p_tel = identifierValue;
      else if (identifierType === 'line_id') identifierParams.p_line_id = identifierValue;
      else if (identifierType === 'user_id') identifierParams.p_user_id = identifierValue;

      const { data, error } = await crmClient.rpc('api_get_user', identifierParams);

      if (error) {
        return new Response(JSON.stringify({
          error: 'User not found', code: 'USER_NOT_FOUND', details: error.message, request_id: requestId
        }), { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      }

      if (!data?.success) {
        return new Response(JSON.stringify({
          error: data?.error, code: data?.code, request_id: requestId
        }), { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      }

      result = data;
    } else {
      return new Response(JSON.stringify({
        error: 'Method not allowed', code: 'METHOD_NOT_ALLOWED', request_id: requestId
      }), { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const responseTime = Date.now() - startTime;
    return new Response(JSON.stringify({
      success: true, data: result, meta: { request_id: requestId, response_time_ms: responseTime }
    }), {
      status: statusCode,
      headers: { ...corsHeaders, 'Content-Type': 'application/json', 'X-Request-Id': requestId, 'X-Response-Time': `${responseTime}ms` }
    });
  } catch (error) {
    const responseTime = Date.now() - startTime;
    return new Response(JSON.stringify({
      error: 'Internal server error', code: 'INTERNAL_ERROR', message: error.message, request_id: requestId
    }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json', 'X-Request-Id': requestId, 'X-Response-Time': `${responseTime}ms` }
    });
  }
});
