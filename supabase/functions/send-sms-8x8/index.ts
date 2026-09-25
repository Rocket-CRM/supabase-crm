import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";
import {
  buildOtpMessage,
  resolveMerchantId,
  resolveSms8x8Config,
  sendSms8x8,
  type Sms8x8Purpose,
} from "../_shared/sms-8x8/resolve.ts";

interface SendSmsPayload {
  merchant_code?: string;
  merchant_id?: string;
  purpose?: Sms8x8Purpose;
  user?: {
    id?: string;
    phone?: string;
    email?: string;
  };
  sms?: {
    otp?: string;
  };
  message?: string;
}

serve(async (req) => {
  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const payload = (await req.json()) as SendSmsPayload;

    const merchantId = await resolveMerchantId(supabase, {
      merchant_id: payload.merchant_id,
      merchant_code: payload.merchant_code,
    });

    let phone = payload.user?.phone;
    if (!phone && payload.user?.id && merchantId) {
      const { data: user } = await supabase
        .from("user_accounts")
        .select("tel")
        .eq("id", payload.user.id)
        .eq("merchant_id", merchantId)
        .limit(1)
        .maybeSingle();
      phone = (user?.tel as string | undefined) ?? undefined;
    }

    const purpose: Sms8x8Purpose = payload.purpose ??
      (payload.sms?.otp ? "otp" : "marketing");

    let messageText = payload.message?.trim() ?? "";
    if (payload.sms?.otp) {
      const config = await resolveSms8x8Config(supabase, merchantId, "otp");
      messageText = buildOtpMessage(payload.sms.otp, config.sender_name);
    }

    if (!phone || !messageText) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Missing phone or message content",
        }),
        {
          status: 400,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    const config = await resolveSms8x8Config(supabase, merchantId, purpose);
    const result = await sendSms8x8(config, phone, messageText);

    if (!result.success) {
      return new Response(
        JSON.stringify({ success: false, error: result.error }),
        {
          status: 500,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    return new Response(
      JSON.stringify({ success: true, umid: result.umid }),
      {
        status: 200,
        headers: { "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    console.error("Error in send-sms-8x8:", error);
    return new Response(
      JSON.stringify({ success: false, error: message }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      },
    );
  }
});
