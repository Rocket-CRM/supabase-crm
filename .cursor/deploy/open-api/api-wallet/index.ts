import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const CRM_URL = Deno.env.get("CRM_PROJECT_URL") || "https://wkevmsedchftztoolkmi.supabase.co";
const CRM_SERVICE_KEY = Deno.env.get("CRM_SERVICE_ROLE_KEY");

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-api-key",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

const LIMITS = { STANDARD_TEXT: 255, LONG_TEXT: 5000 };
const LONG_TEXT_FIELDS = ["notes", "description", "reason"];

function getFieldLimit(fieldName: string): number {
  return LONG_TEXT_FIELDS.some((f) => fieldName.toLowerCase().includes(f))
    ? LIMITS.LONG_TEXT
    : LIMITS.STANDARD_TEXT;
}

function validateObject(
  obj: any,
  parentKey = "",
): Array<{ field: string; error: string; limit: number; actual: number }> {
  const errors: Array<{ field: string; error: string; limit: number; actual: number }> = [];
  if (!obj || typeof obj !== "object") return errors;
  for (const [key, value] of Object.entries(obj)) {
    const fullKey = parentKey ? `${parentKey}.${key}` : key;
    if (typeof value === "string") {
      const limit = getFieldLimit(key);
      if (value.length > limit) {
        errors.push({
          field: fullKey,
          error: "Field exceeds maximum length",
          limit,
          actual: value.length,
        });
      }
    } else if (typeof value === "object" && value !== null && !Array.isArray(value)) {
      errors.push(...validateObject(value, fullKey));
    } else if (Array.isArray(value)) {
      value.forEach((item, index) => {
        if (typeof item === "string") {
          const limit = getFieldLimit(key);
          if (item.length > limit) {
            errors.push({
              field: `${fullKey}[${index}]`,
              error: "Field exceeds maximum length",
              limit,
              actual: item.length,
            });
          }
        } else if (typeof item === "object" && item !== null) {
          errors.push(...validateObject(item, `${fullKey}[${index}]`));
        }
      });
    }
  }
  return errors;
}

function httpStatusForCode(code: string | undefined, fallback: number): number {
  switch (code) {
    case "USER_NOT_FOUND":
      return 404;
    case "IDEMPOTENCY_CONFLICT":
      return 409;
    case "INSUFFICIENT_BALANCE":
    case "INSUFFICIENT_TICKET_POOL":
    case "VALIDATION_FAILED":
    case "MISSING_IDENTIFIER":
    case "MULTIPLE_IDENTIFIERS":
    case "INVALID_AMOUNT":
    case "INVALID_TRANSACTION_TYPE":
    case "INVALID_CURRENCY":
    case "INVALID_DEDUP_KEY":
    case "RESERVED_METADATA_KEY":
    case "TICKET_TYPE_REQUIRED":
    case "TICKET_TYPE_NOT_FOUND":
    case "TICKET_TYPE_NOT_AVAILABLE":
    case "TICKET_TYPE_CREDIT_FORBIDDEN":
    case "MULTIPLE_TICKET_IDENTIFIERS":
      return 400;
    default:
      return fallback;
  }
}

function pickUserIds(source: Record<string, any>) {
  return {
    p_user_id: source.user_id ?? null,
    p_external_user_id: source.external_user_id ?? null,
    p_tel: source.tel ?? null,
    p_email: source.email ?? null,
    p_line_id: source.line_id ?? null,
  };
}

Deno.serve(async (req) => {
  const startTime = Date.now();
  const requestId = crypto.randomUUID();

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const apiKey = req.headers.get("x-api-key");
    if (!apiKey) {
      return new Response(
        JSON.stringify({
          error: "Missing x-api-key header",
          code: "MISSING_API_KEY",
          request_id: requestId,
        }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    if (!CRM_SERVICE_KEY) {
      return new Response(
        JSON.stringify({
          error: "API gateway not configured",
          code: "GATEWAY_CONFIG_ERROR",
          request_id: requestId,
        }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const crmClient = createClient(CRM_URL, CRM_SERVICE_KEY);
    const { data: validation, error: validationError } = await crmClient.rpc("validate_api_key", {
      p_api_key: apiKey,
    });

    if (validationError || !validation?.valid) {
      return new Response(
        JSON.stringify({
          error: "Invalid or expired API key",
          code: "INVALID_API_KEY",
          request_id: requestId,
        }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const merchantId = validation.merchant_id;
    const url = new URL(req.url);
    const pathParts = url.pathname.split("/").filter((p) => p);
    // Expect .../api-wallet/transactions
    const isTransactions =
      pathParts.length >= 2 &&
      pathParts[pathParts.length - 1] === "transactions" &&
      pathParts[pathParts.length - 2] === "api-wallet";

    if (!isTransactions) {
      return new Response(
        JSON.stringify({
          error: "Not found",
          code: "NOT_FOUND",
          request_id: requestId,
        }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    let result: any;
    let statusCode = 200;

    if (req.method === "POST") {
      const body = await req.json();
      const validationErrors = validateObject(body);
      if (validationErrors.length > 0) {
        return new Response(
          JSON.stringify({
            success: false,
            error: "Validation failed",
            code: "VALIDATION_FAILED",
            details: validationErrors,
            request_id: requestId,
          }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      const { data, error } = await crmClient.rpc("api_post_wallet_transaction", {
        p_merchant_id: merchantId,
        ...pickUserIds(body),
        p_transaction_type: body.transaction_type,
        p_amount: body.amount,
        p_dedup_key: body.dedup_key,
        p_description: body.description ?? null,
        p_metadata: body.metadata ?? null,
        p_currency: body.currency ?? "points",
        p_ticket_type_id: body.ticket_type_id ?? null,
        p_ticket_code: body.ticket_code ?? null,
      });

      if (error) {
        return new Response(
          JSON.stringify({
            success: false,
            error: error.message,
            code: "RPC_ERROR",
            request_id: requestId,
          }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      if (!data?.success) {
        statusCode = httpStatusForCode(data?.code, 400);
        return new Response(JSON.stringify({ ...data, request_id: requestId }), {
          status: statusCode,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      statusCode = data.already_processed ? 200 : 201;
      result = data;
    } else if (req.method === "GET") {
      const q = Object.fromEntries(url.searchParams.entries());
      const limit = q.limit !== undefined ? Number(q.limit) : 50;
      const offset = q.offset !== undefined ? Number(q.offset) : 0;

      const { data, error } = await crmClient.rpc("api_get_wallet_transactions", {
        p_merchant_id: merchantId,
        ...pickUserIds(q),
        p_from: q.from || null,
        p_to: q.to || null,
        p_transaction_type: q.transaction_type || null,
        p_limit: Number.isFinite(limit) ? limit : 50,
        p_offset: Number.isFinite(offset) ? offset : 0,
        p_currency: q.currency || "points",
        p_ticket_type_id: q.ticket_type_id || null,
        p_ticket_code: q.ticket_code || null,
      });

      if (error) {
        return new Response(
          JSON.stringify({
            success: false,
            error: error.message,
            code: "RPC_ERROR",
            request_id: requestId,
          }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      if (!data?.success) {
        statusCode = httpStatusForCode(data?.code, 400);
        return new Response(JSON.stringify({ ...data, request_id: requestId }), {
          status: statusCode,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      result = data;
    } else {
      return new Response(
        JSON.stringify({
          error: "Method not allowed",
          code: "METHOD_NOT_ALLOWED",
          request_id: requestId,
        }),
        { status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const responseTime = Date.now() - startTime;
    return new Response(
      JSON.stringify({
        success: true,
        data: result,
        meta: {
          request_id: requestId,
          response_time_ms: responseTime,
        },
      }),
      {
        status: statusCode,
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json",
          "X-Request-Id": requestId,
        },
      },
    );
  } catch (error) {
    return new Response(
      JSON.stringify({
        error: "Internal error",
        code: "INTERNAL_ERROR",
        message: error.message,
        request_id: requestId,
      }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
