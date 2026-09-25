import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

export type Sms8x8Purpose = "otp" | "marketing";

export interface Sms8x8Config {
  sender_name: string;
  api_url: string;
  bearer_token: string;
}

function stripBearer(token: string): string {
  return token.replace(/^Bearer\s+/i, "").trim();
}

function parseCredentials(raw: Record<string, unknown>): Sms8x8Config | null {
  const apiUrl = raw.api_url as string | undefined;
  const bearerToken = (raw.bearer_token ?? raw.api_key) as string | undefined;
  const senderName = (raw.sender_name ?? raw.source_name) as string | undefined;

  if (!apiUrl || !bearerToken || !senderName) return null;

  return {
    sender_name: senderName,
    api_url: apiUrl,
    bearer_token: stripBearer(bearerToken),
  };
}

function envDefault(): Sms8x8Config {
  return {
    sender_name:
      Deno.env.get("8X8_SOURCE_NAME") ??
      Deno.env.get("EIGHT_X_EIGHT_SOURCE_NAME") ??
      "Rocket CRM",
    api_url:
      Deno.env.get("8X8_API_URL") ??
      Deno.env.get("EIGHT_X_EIGHT_API_URL") ??
      "https://sms.8x8.com/api/v1/subaccounts/RocketCRM_Notif/messages",
    bearer_token: stripBearer(
      Deno.env.get("8X8_BEARER_TOKEN") ??
        Deno.env.get("EIGHT_X_EIGHT_BEARER_TOKEN") ??
        "",
    ),
  };
}

async function fetchCredentialRow(
  supabase: SupabaseClient,
  merchantId: string,
  serviceName: string,
): Promise<Sms8x8Config | null> {
  const { data, error } = await supabase
    .from("merchant_credentials")
    .select("credentials")
    .eq("merchant_id", merchantId)
    .eq("service_name", serviceName)
    .eq("is_active", true)
    .eq("environment", "production")
    .limit(1)
    .maybeSingle();

  if (error || !data?.credentials) return null;
  return parseCredentials(data.credentials as Record<string, unknown>);
}

export async function resolveSms8x8Config(
  supabase: SupabaseClient,
  merchantId: string | null | undefined,
  purpose: Sms8x8Purpose,
): Promise<Sms8x8Config> {
  if (merchantId) {
    const primaryService = purpose === "otp" ? "sms_8x8_otp" : "sms_8x8_marketing";
    const primaryConfig = await fetchCredentialRow(supabase, merchantId, primaryService);
    if (primaryConfig) return primaryConfig;

    const sharedConfig = await fetchCredentialRow(supabase, merchantId, "sms_8x8");
    if (sharedConfig) return sharedConfig;
  }

  return envDefault();
}

export async function resolveMerchantId(
  supabase: SupabaseClient,
  opts: { merchant_id?: string; merchant_code?: string },
): Promise<string | null> {
  if (opts.merchant_id) return opts.merchant_id;
  if (!opts.merchant_code) return null;

  const { data } = await supabase
    .from("merchant_master")
    .select("id")
    .eq("merchant_code", opts.merchant_code)
    .limit(1)
    .maybeSingle();

  return (data?.id as string | undefined) ?? null;
}

export function buildOtpMessage(
  otp: string,
  senderName: string,
  expiryMinutes = 10,
): string {
  return `Your OTP: ${otp} (Valid ${expiryMinutes} min)\nรหัส OTP: ${otp} (ใช้ได้ ${expiryMinutes} นาที)\n\n${senderName}`;
}

export async function sendSms8x8(
  config: Sms8x8Config,
  destination: string,
  text: string,
): Promise<{ success: boolean; error?: string; umid?: string }> {
  if (!config.bearer_token) {
    return { success: false, error: "SMS provider not configured" };
  }

  const res = await fetch(config.api_url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${config.bearer_token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      source: config.sender_name,
      destination,
      text,
      encoding: "AUTO",
    }),
  });

  if (!res.ok) {
    const errorText = await res.text();
    return { success: false, error: `8x8 API error (${res.status}): ${errorText}` };
  }

  const data = await res.json().catch(() => ({}));
  return {
    success: true,
    umid: (data as Record<string, unknown>).umid as string | undefined,
  };
}
