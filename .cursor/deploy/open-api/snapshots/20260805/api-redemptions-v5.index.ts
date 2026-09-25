import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const CRM_URL = Deno.env.get('CRM_PROJECT_URL') || 'https://wkevmsedchftztoolkmi.supabase.co';
const CRM_SERVICE_KEY = Deno.env.get('CRM_SERVICE_ROLE_KEY');

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-api-key',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS'
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

function normalizeResponse(data: any): any {
  if (!data) return data;
  if (data.success === false && data.title && !data.error) {
    return {
      success: false,
      error: data.title,
      code: data.data?.error_code || 'UNKNOWN_ERROR',
      details: data.description,
      data: data.data
    };
  }
  if (data.success === true && data.title && !data.error) {
    return {
      success: true,
      message: data.title,
      details: data.description,
      data: data.data
    };
  }
  return data;
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

    let result;
    let statusCode = 200;

    if (req.method === 'POST' && pathParts.length === 3 && pathParts[2] === 'cancel') {
      const redemptionCode = decodeURIComponent(pathParts[1]);
      const body = await req.json().catch(() => ({}));
      const validationErrors = validateObject(body);
      if (validationErrors.length > 0) {
        return new Response(JSON.stringify({
          success: false, error: 'Validation failed', code: 'VALIDATION_FAILED', details: validationErrors, request_id: requestId
        }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      }

      const { data, error } = await crmClient.rpc('api_cancel_redemption', {
        p_merchant_id: merchantId,
        p_redemption_code: redemptionCode,
        p_reason: body.reason
      });

      if (error) {
        return new Response(JSON.stringify({
          error: 'Cancellation failed', code: 'CANCELLATION_FAILED', details: error.message, request_id: requestId
        }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      }

      const normalized = normalizeResponse(data);
      if (!normalized?.success) {
        statusCode = normalized?.code === 'REDEMPTION_NOT_FOUND' || normalized?.code === 'NOT_FOUND' ? 404 : 400;
        return new Response(JSON.stringify({
          error: normalized?.error || 'Cancellation failed',
          code: normalized?.code || 'CANCELLATION_FAILED',
          details: normalized?.details,
          request_id: requestId
        }), { status: statusCode, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      }

      result = normalized;
    } else if (req.method === 'POST' && pathParts.length === 3 && pathParts[2] === 'mark-used') {
      const redemptionCode = decodeURIComponent(pathParts[1]);
      const body = await req.json().catch(() => ({}));
      const validationErrors = validateObject(body);
      if (validationErrors.length > 0) {
        return new Response(JSON.stringify({
          success: false, error: 'Validation failed', code: 'VALIDATION_FAILED', details: validationErrors, request_id: requestId
        }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      }

      const { data, error } = await crmClient.rpc('api_mark_redemption_used', {
        p_merchant_id: merchantId,
        p_redemption_code: redemptionCode,
        p_notes: body.notes
      });

      if (error) {
        return new Response(JSON.stringify({
          error: 'Mark used failed', code: 'MARK_USED_FAILED', details: error.message, request_id: requestId
        }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      }

      const normalized = normalizeResponse(data);
      if (!normalized?.success) {
        statusCode = normalized?.code === 'NOT_FOUND' ? 404 : 400;
        return new Response(JSON.stringify({
          error: normalized?.error || 'Mark used failed',
          code: normalized?.code || 'MARK_USED_FAILED',
          details: normalized?.details,
          request_id: requestId
        }), { status: statusCode, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      }

      result = normalized;
    } else if (req.method === 'POST') {
      const body = await req.json();
      const validationErrors = validateObject(body);
      if (validationErrors.length > 0) {
        return new Response(JSON.stringify({
          success: false, error: 'Validation failed', code: 'VALIDATION_FAILED', details: validationErrors, request_id: requestId
        }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      }

      const { data, error } = await crmClient.rpc('redeem_reward_with_points', {
        p_user_id: body.user_id,
        p_reward_id: body.reward_id,
        p_quantity: body.quantity || 1,
        p_merchant_id: merchantId
      });

      if (error) {
        return new Response(JSON.stringify({
          error: 'Redemption failed', code: 'REDEMPTION_FAILED', details: error.message, request_id: requestId
        }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      }

      const normalized = normalizeResponse(data);
      if (normalized && normalized.success === false) {
        return new Response(JSON.stringify({
          error: normalized.error || 'Redemption failed',
          code: normalized.code || 'REDEMPTION_FAILED',
          details: normalized.details,
          request_id: requestId
        }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      }

      result = normalized || data;
    } else if (req.method === 'GET') {
      const redemptionCode = pathParts.length >= 2 ? decodeURIComponent(pathParts[1]) : url.searchParams.get('redemption_code');
      const redemptionId = url.searchParams.get('redemption_id');

      if (!redemptionCode && !redemptionId) {
        return new Response(JSON.stringify({
          error: 'Missing redemption identifier', code: 'MISSING_IDENTIFIER', request_id: requestId
        }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      }

      const { data, error } = await crmClient.rpc('api_get_redemption', {
        p_merchant_id: merchantId,
        p_redemption_id: redemptionId,
        p_redemption_code: redemptionCode
      });

      if (error) {
        return new Response(JSON.stringify({
          error: 'Redemption not found', code: 'REDEMPTION_NOT_FOUND', details: error.message, request_id: requestId
        }), { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      }

      if (!data?.success) {
        return new Response(JSON.stringify({
          error: data?.error || 'Redemption not found', code: data?.code || 'REDEMPTION_NOT_FOUND', request_id: requestId
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
