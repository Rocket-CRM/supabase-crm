import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const CRM_URL = Deno.env.get('CRM_PROJECT_URL') || 'https://wkevmsedchftztoolkmi.supabase.co';
const CRM_SERVICE_KEY = Deno.env.get('CRM_SERVICE_ROLE_KEY');

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-api-key',
  'Access-Control-Allow-Methods': 'POST, GET, PATCH, OPTIONS'
};

// Character limit constants
const LIMITS = {
  STANDARD_TEXT: 255,
  LONG_TEXT: 5000,
};

const LONG_TEXT_FIELDS = ['notes', 'description', 'reason'];

// Validation utilities
function getFieldLimit(fieldName: string): number {
  const lowerName = fieldName.toLowerCase();
  if (LONG_TEXT_FIELDS.some(f => lowerName.includes(f))) {
    return LIMITS.LONG_TEXT;
  }
  return LIMITS.STANDARD_TEXT;
}

function validateObject(obj: any, parentKey = ''): Array<{field: string; error: string; limit: number; actual: number}> {
  const errors: Array<{field: string; error: string; limit: number; actual: number}> = [];
  
  if (!obj || typeof obj !== 'object') return errors;
  
  for (const [key, value] of Object.entries(obj)) {
    const fullKey = parentKey ? `${parentKey}.${key}` : key;
    
    if (typeof value === 'string') {
      const limit = getFieldLimit(key);
      if (value.length > limit) {
        errors.push({
          field: fullKey,
          error: 'Field exceeds maximum length',
          limit: limit,
          actual: value.length,
        });
      }
    } else if (typeof value === 'object' && value !== null && !Array.isArray(value)) {
      const nestedErrors = validateObject(value, fullKey);
      errors.push(...nestedErrors);
    } else if (Array.isArray(value)) {
      value.forEach((item, index) => {
        if (typeof item === 'string') {
          const limit = getFieldLimit(key);
          if (item.length > limit) {
            errors.push({
              field: `${fullKey}[${index}]`,
              error: 'Field exceeds maximum length',
              limit: limit,
              actual: item.length,
            });
          }
        } else if (typeof item === 'object' && item !== null) {
          const nestedErrors = validateObject(item, `${fullKey}[${index}]`);
          errors.push(...nestedErrors);
        }
      });
    }
  }
  
  return errors;
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
        error: 'Missing x-api-key header',
        code: 'MISSING_API_KEY',
        request_id: requestId
      }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    const crmClient = createClient(CRM_URL, CRM_SERVICE_KEY);
    const { data: validation, error: validationError } = await crmClient.rpc('validate_api_key', {
      p_api_key: apiKey
    });

    if (validationError || !validation?.valid) {
      return new Response(JSON.stringify({
        error: 'Invalid API key',
        code: 'INVALID_API_KEY',
        request_id: requestId
      }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    const merchantId = validation.merchant_id;
    const url = new URL(req.url);
    const pathParts = url.pathname.split('/').filter(p => p);

    let idType = null;
    let idVal = null;

    if (pathParts.length === 3 && pathParts[1].startsWith('by-')) {
      idType = pathParts[1].replace('by-', '').replace(/-/g, '_');
      idVal = decodeURIComponent(pathParts[2]);
    } else if (pathParts.length === 2 && pathParts[1] !== 'api-assets') {
      idVal = pathParts[1];
      idType = 'asset_id';
    }

    let result;
    let statusCode = 200;

    if (req.method === 'POST') {
      const body = await req.json();

      // VALIDATE CHARACTER LIMITS
      const validationErrors = validateObject(body);
      if (validationErrors.length > 0) {
        return new Response(JSON.stringify({
          success: false,
          error: 'Validation failed',
          code: 'VALIDATION_FAILED',
          details: validationErrors,
          request_id: requestId
        }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        });
      }

      const { data, error } = await crmClient.rpc('api_create_or_update_asset', {
        p_merchant_id: merchantId,
        p_asset_type_code: body.asset_type_code,
        p_name: body.name,
        p_user_id: body.user_id,
        p_external_user_id: body.external_user_id,
        p_sku_id: body.sku_id,
        p_sku_code: body.sku_code,
        p_purchase_transaction_id: body.purchase_transaction_id,
        p_purchase_transaction_number: body.purchase_transaction_number,
        p_external_id: body.external_id,
        p_asset_code: body.asset_code,
        p_serial_number: body.serial_number,
        p_status: body.status,
        p_purchase_date: body.purchase_date,
        p_install_date: body.install_date,
        p_custom_fields: body.custom_fields,
        p_covered_assets: body.covered_assets,
        p_upsert: body.upsert ?? false
      });

      if (error || !data?.success) {
        statusCode = data?.code === 'ASSET_EXISTS' ? 409 : 400;
        return new Response(JSON.stringify(data || { error: error.message }), {
          status: statusCode,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        });
      }

      statusCode = data.created ? 201 : 200;
      result = data;
    } else if (req.method === 'PATCH') {
      if (!idType || !idVal) {
        return new Response(JSON.stringify({
          error: 'Missing identifier',
          code: 'MISSING_IDENTIFIER',
          request_id: requestId
        }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        });
      }

      const body = await req.json();

      // VALIDATE CHARACTER LIMITS
      const validationErrors = validateObject(body);
      if (validationErrors.length > 0) {
        return new Response(JSON.stringify({
          success: false,
          error: 'Validation failed',
          code: 'VALIDATION_FAILED',
          details: validationErrors,
          request_id: requestId
        }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        });
      }

      const params = { p_merchant_id: merchantId };
      if (idType === 'external_id') params.p_external_id = idVal;
      else if (idType === 'asset_code') params.p_asset_code = idVal;
      else if (idType === 'serial_number') params.p_serial_number = idVal;
      else if (idType === 'asset_id') params.p_asset_id = idVal;

      const { data, error } = await crmClient.rpc('api_update_asset', {
        ...params,
        p_name: body.name,
        p_status: body.status,
        p_purchase_date: body.purchase_date,
        p_install_date: body.install_date,
        p_custom_fields: body.custom_fields,
        p_covered_assets: body.covered_assets
      });

      if (error || !data?.success) {
        statusCode = data?.code === 'ASSET_NOT_FOUND' ? 404 : 400;
        return new Response(JSON.stringify(data || { error: error.message }), {
          status: statusCode,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        });
      }

      result = data;
    } else if (req.method === 'GET') {
      if (!idType || !idVal) {
        return new Response(JSON.stringify({
          error: 'Missing identifier',
          code: 'MISSING_IDENTIFIER',
          request_id: requestId
        }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        });
      }

      const params = { p_merchant_id: merchantId };
      if (idType === 'external_id') params.p_external_id = idVal;
      else if (idType === 'asset_code') params.p_asset_code = idVal;
      else if (idType === 'serial_number') params.p_serial_number = idVal;
      else if (idType === 'asset_id') params.p_asset_id = idVal;

      const { data, error } = await crmClient.rpc('api_get_asset', params);

      if (error || !data?.success) {
        return new Response(JSON.stringify(data || { error: error.message }), {
          status: 404,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        });
      }

      result = data;
    } else {
      return new Response(JSON.stringify({
        error: 'Method not allowed',
        code: 'METHOD_NOT_ALLOWED',
        request_id: requestId
      }), {
        status: 405,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    const responseTime = Date.now() - startTime;
    return new Response(JSON.stringify({
      success: true,
      data: result,
      meta: {
        request_id: requestId,
        response_time_ms: responseTime
      }
    }), {
      status: statusCode,
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json',
        'X-Request-Id': requestId
      }
    });
  } catch (error) {
    return new Response(JSON.stringify({
      error: 'Internal error',
      code: 'INTERNAL_ERROR',
      message: error.message,
      request_id: requestId
    }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }
});
