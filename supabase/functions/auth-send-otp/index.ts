import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const OTP_LENGTH = 6;
const OTP_EXPIRY_MINUTES = 10;

function normalizeTel(tel: string | undefined | null): string | null {
  if (!tel) return null;

  let normalized = tel.trim().replace(/[\s-]/g, "");

  if (normalized.startsWith("+660")) {
    normalized = "+66" + normalized.substring(4);
  } else if (normalized.startsWith("0")) {
    normalized = "+66" + normalized.substring(1);
  } else if (normalized.startsWith("66") && !normalized.startsWith("+")) {
    normalized = "+" + normalized;
  }

  return normalized;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const { phone, merchant_code } = await req.json();

    if (!phone || !merchant_code) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "phone and merchant_code are required",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const normalizedPhone = normalizeTel(phone);

    if (!normalizedPhone || normalizedPhone.length < 10) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Invalid phone number format",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const otpCode = Math.floor(100000 + Math.random() * 900000).toString();
    const sessionId = crypto.randomUUID();
    const expiresAt = new Date(
      Date.now() + OTP_EXPIRY_MINUTES * 60 * 1000,
    ).toISOString();

    const { error: insertError } = await supabase.from("otp_requests").insert({
      phone: normalizedPhone,
      otp_code: otpCode,
      session_id: sessionId,
      attempts: 0,
      verified: false,
      expires_at: expiresAt,
    });

    if (insertError) {
      console.error("Error storing OTP:", insertError);
      return new Response(
        JSON.stringify({
          success: false,
          error: "Failed to generate OTP",
          details: insertError.message,
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const smsResponse = await fetch(`${supabaseUrl}/functions/v1/send-sms-8x8`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${supabaseServiceKey}`,
      },
      body: JSON.stringify({
        merchant_code,
        purpose: "otp",
        user: { phone: normalizedPhone },
        sms: { otp: otpCode },
      }),
    });

    const smsResult = await smsResponse.json();

    if (!smsResult.success) {
      console.error("Failed to send SMS:", smsResult.error);
      return new Response(
        JSON.stringify({
          success: true,
          session_id: sessionId,
          expires_in: OTP_EXPIRY_MINUTES * 60,
          message: `OTP generated for ${normalizedPhone}`,
          sms_sent: false,
          sms_error: smsResult.error,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    return new Response(
      JSON.stringify({
        success: true,
        session_id: sessionId,
        expires_in: OTP_EXPIRY_MINUTES * 60,
        message: `OTP sent to ${normalizedPhone}`,
        sms_sent: true,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    console.error("Error in auth-send-otp:", error);
    return new Response(
      JSON.stringify({ success: false, error: message }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
