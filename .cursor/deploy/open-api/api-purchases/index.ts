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

    if (!CRM_SERVICE_KEY) {
      return new Response(JSON.stringify({
        error: 'API gateway not configured',
        code: 'GATEWAY_CONFIG_ERROR',
        request_id: requestId
      }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    const crmClient = createClient(CRM_URL, CRM_SERVICE_KEY);
    const { data: validation, error: validationError } = await crmClient.rpc('validate_api_key', {
      p_api_key: apiKey
    });

    if (validationError || !validation?.valid) {
      return new Response(JSON.stringify({
        error: 'Invalid or expired API key',
        code: 'INVALID_API_KEY',
        details: validation?.error,
        request_id: requestId
      }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    const merchantId = validation.merchant_id;
    const url = new URL(req.url);
    const pathParts = url.pathname.split('/').filter(p => p);

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

      const { data, error } = await crmClient.rpc('api_create_purchase', {
        p_merchant_id: merchantId,
        p_final_amount: body.final_amount,
        p_user_id: body.user_id,
        p_external_user_id: body.external_user_id,
        p_seller_user_id: body.seller_user_id,
        p_seller_external_user_id: body.seller_external_user_id,
        p_store_code: body.store_code,
        p_total_amount: body.total_amount,
        p_discount_amount: body.discount_amount,
        p_tax_amount: body.tax_amount,
        p_status: body.status,
        p_payment_status: body.payment_status,
        p_processing_method: body.processing_method,
        p_earn_currency: body.earn_currency,
        p_transaction_number: body.transaction_number,
        p_transaction_date: body.transaction_date ?? null,
        p_external_ref: body.external_ref,
        p_api_source: body.api_source,
        p_notes: body.notes,
        p_items: body.items,
        p_images: body.images ?? null,
        p_external_user_ref: body.external_user_ref ?? null,
        p_transaction_source: body.transaction_source ?? null,
        p_transaction_type: body.transaction_type ?? null,
        p_store_id: body.store_id ?? null,
        p_earning_channel_id: body.earning_channel_id ?? null,
        p_transaction_source_id: body.transaction_source_id ?? null,
        p_payment_method: body.payment_method ?? null,
        p_metadata: body.metadata ?? null
      });

      if (error) {
        statusCode = 400;
        return new Response(JSON.stringify({
          error: 'Purchase creation failed',
          code: 'PURCHASE_CREATION_FAILED',
          details: error.message,
          request_id: requestId
        }), {
          status: statusCode,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        });
      }

      if (!data?.success) {
        statusCode = 400;
        return new Response(JSON.stringify({
          error: data?.error || 'Purchase creation failed',
          code: data?.code || 'PURCHASE_FAILED',
          details: data?.details,
          request_id: requestId
        }), {
          status: statusCode,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        });
      }

      result = data;
    } else if (req.method === 'PATCH') {
      const transactionNumber = pathParts[pathParts.length - 1];
      if (!transactionNumber || transactionNumber === 'api-purchases') {
        return new Response(JSON.stringify({
          error: 'Missing transaction_number in path',
          code: 'MISSING_TRANSACTION_NUMBER',
          details: 'Use PATCH /api-purchases/{transaction_number}',
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

      const { data, error } = await crmClient.rpc('api_update_purchase', {
        p_merchant_id: merchantId,
        p_transaction_number: transactionNumber,
        p_status: body.status,
        p_payment_status: body.payment_status,
        p_discount_amount: body.discount_amount,
        p_tax_amount: body.tax_amount,
        p_final_amount: body.final_amount,
        p_total_amount: body.total_amount,
        p_notes: body.notes,
        p_external_ref: body.external_ref,
        p_items: body.items,
        p_payment_method: body.payment_method ?? null,
        p_metadata: body.metadata ?? null,
        p_transaction_source: body.transaction_source ?? null,
        p_transaction_source_id: body.transaction_source_id ?? null
      });

      if (error) {
        statusCode = 400;
        return new Response(JSON.stringify({
          error: 'Purchase update failed',
          code: 'UPDATE_FAILED',
          details: error.message,
          request_id: requestId
        }), {
          status: statusCode,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        });
      }

      if (!data?.success) {
        statusCode = 400;
        return new Response(JSON.stringify({
          error: data?.error || 'Purchase update failed',
          code: data?.code || 'UPDATE_FAILED',
          details: data?.details,
          request_id: requestId
        }), {
          status: statusCode,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        });
      }

      result = data;
    } else if (req.method === 'GET') {
      const transactionNumber = pathParts[pathParts.length - 1];
      const queryTxnNumber = url.searchParams.get('transaction_number');
      const transactionId = url.searchParams.get('transaction_id');
      const txnNumber = transactionNumber && transactionNumber !== 'api-purchases' ? transactionNumber : queryTxnNumber;

      const { data, error } = await crmClient.rpc('api_get_purchase', {
        p_merchant_id: merchantId,
        p_transaction_id: transactionId,
        p_transaction_number: txnNumber
      });

      if (error) {
        statusCode = 404;
        return new Response(JSON.stringify({
          error: 'Purchase not found',
          code: 'PURCHASE_NOT_FOUND',
          details: error.message,
          request_id: requestId
        }), {
          status: statusCode,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        });
      }

      result = data;
    } else {
      return new Response(JSON.stringify({
        error: 'Method not allowed',
        code: 'METHOD_NOT_ALLOWED',
        allowed: ['GET', 'POST', 'PATCH'],
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
        'X-Request-Id': requestId,
        'X-Response-Time': `${responseTime}ms`
      }
    });
  } catch (error) {
    const responseTime = Date.now() - startTime;
    return new Response(JSON.stringify({
      error: 'Internal server error',
      code: 'INTERNAL_ERROR',
      message: error.message,
      request_id: requestId
    }), {
      status: 500,
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json',
        'X-Request-Id': requestId,
        'X-Response-Time': `${responseTime}ms`
      }
    });
  }
});
