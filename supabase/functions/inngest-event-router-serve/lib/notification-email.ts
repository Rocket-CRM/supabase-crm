import { getSupabase } from "./supabase.ts";

export const NOTIFICATION_FROM_EMAIL = "no-reply@rocket.in.th";

const PLACEHOLDER_RE = /\$\{([a-zA-Z0-9_]+)\}/g;
const DEFAULT_MESSAGING_URL = "https://messaging-service-li40.onrender.com";

export interface EmailTemplateJson {
  subject?: string;
  title?: string;
  description?: string;
  button?: string;
  banner_url?: string | null;
}

export interface NotificationAppearance {
  fromName: string;
  logoUrl: string | null;
  primaryColor: string;
}

export interface RenderedEmail {
  subject: string;
  html: string;
  text: string;
}

export interface EmailSendResult {
  status: "sent" | "failed";
  httpStatus: number;
  responseBody: Record<string, unknown> | null;
  error?: string;
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function substitute(input: string, lookup: Record<string, unknown>, html: boolean): string {
  return input.replace(PLACEHOLDER_RE, (_match, name: string) => {
    const value = lookup[name];
    if (value === null || value === undefined || value === "") return "";
    const text = String(value);
    return html ? escapeHtml(text) : text;
  });
}

function firstHttps(value: unknown): string | null {
  return typeof value === "string" && /^https?:\/\//i.test(value) ? value : null;
}

export function renderNotificationEmail(input: {
  template: EmailTemplateJson;
  lookup: Record<string, unknown>;
  appearance: NotificationAppearance;
}): RenderedEmail | null {
  const subject = substitute(input.template.subject ?? "", input.lookup, false).trim();
  if (!subject) return null;

  const title = substitute(input.template.title ?? "", input.lookup, true).trim();
  const description = substitute(input.template.description ?? "", input.lookup, true).trim();
  const button = substitute(input.template.button ?? "", input.lookup, true).trim();
  const banner = firstHttps(input.template.banner_url) ?? firstHttps(input.lookup.hero_image_url);
  const detailUrl = firstHttps(input.lookup.detail_url);
  const color = input.appearance.primaryColor || "#111111";
  const logo = input.appearance.logoUrl;

  const textParts = [title, description, button && detailUrl ? `${button}: ${detailUrl}` : button]
    .filter(Boolean)
    .join("\n\n");

  const html = `<!doctype html>
<html><body style="margin:0;padding:24px;background:#f5f5f5;font-family:Arial,Helvetica,sans-serif;color:#111;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;margin:0 auto;background:#ffffff;border-radius:8px;">
    <tr><td style="padding:24px 24px 8px;">
      ${logo ? `<img src="${escapeHtml(logo)}" alt="" style="max-height:40px;max-width:160px;display:block;margin-bottom:16px;" />` : ""}
      ${banner ? `<img src="${escapeHtml(banner)}" alt="" style="width:100%;max-height:180px;object-fit:cover;border-radius:6px;margin-bottom:16px;" />` : ""}
      ${title ? `<h1 style="margin:0 0 12px;font-size:22px;line-height:1.3;color:${escapeHtml(color)};">${title}</h1>` : ""}
      ${description ? `<p style="margin:0 0 20px;font-size:15px;line-height:1.5;color:#333;">${description.replace(/\n/g, "<br/>")}</p>` : ""}
      ${
        button
          ? `<a href="${escapeHtml(detailUrl || "#")}" style="display:inline-block;padding:12px 20px;background:${escapeHtml(color)};color:#fff;text-decoration:none;border-radius:6px;font-size:14px;font-weight:600;">${button}</a>`
          : ""
      }
    </td></tr>
    <tr><td style="padding:16px 24px 24px;font-size:12px;color:#888;">Sent by ${escapeHtml(input.appearance.fromName)}</td></tr>
  </table>
</body></html>`;

  return { subject, html, text: textParts || subject };
}

export async function fetchNotificationAppearance(
  merchantId: string,
): Promise<NotificationAppearance> {
  const fallback: NotificationAppearance = {
    fromName: "Rocket Loyalty",
    logoUrl: null,
    primaryColor: "#111111",
  };
  try {
    const supabase = getSupabase();
    const [{ data: appearance }, { data: merchant }, { data: display }] = await Promise.all([
      supabase
        .from("merchant_notification_appearance")
        .select("from_name, logo_url, primary_color")
        .eq("merchant_id", merchantId)
        .maybeSingle(),
      supabase.from("merchant_master").select("name").eq("id", merchantId).maybeSingle(),
      supabase
        .from("merchant_display_settings")
        .select("logo, primary_color")
        .eq("merchant_id", merchantId)
        .maybeSingle(),
    ]);

    return {
      fromName:
        (typeof appearance?.from_name === "string" && appearance.from_name.trim()) ||
        (typeof merchant?.name === "string" && merchant.name.trim()) ||
        fallback.fromName,
      logoUrl: firstHttps(appearance?.logo_url) ?? firstHttps(display?.logo),
      primaryColor:
        (typeof appearance?.primary_color === "string" && appearance.primary_color.trim()) ||
        (typeof display?.primary_color === "string" && display.primary_color.trim()) ||
        fallback.primaryColor,
    };
  } catch (e) {
    console.warn(`[notification] appearance fetch failed merchant=${merchantId}:`, e);
    return fallback;
  }
}

async function messagingAuthKey(): Promise<string> {
  const supabase = getSupabase();
  const { data, error } = await supabase.rpc("get_messaging_auth_key");
  if (!error && typeof data === "string" && data.length > 0) return data;
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
  if (serviceRole) return serviceRole;
  throw new Error(`get_messaging_auth_key failed: ${error?.message || "no data"}`);
}

export async function sendNotificationEmail(input: {
  merchantId: string;
  userId: string | null;
  toEmail: string;
  rendered: RenderedEmail;
  appearance: NotificationAppearance;
  sourceEventId: string;
}): Promise<EmailSendResult> {
  const baseUrl = (
    Deno.env.get("MESSAGING_SERVICE_URL") ||
    DEFAULT_MESSAGING_URL
  ).replace(/\/$/, "");
  const url = `${baseUrl}/send`;
  const authKey = await messagingAuthKey();

  let response: Response;
  try {
    response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${authKey}`,
      },
      body: JSON.stringify({
        merchant_id: input.merchantId,
        channel: "EMAIL",
        recipient: { direct: { email: input.toEmail } },
        message: {
          type: "html",
          content: input.rendered.html,
          subject: input.rendered.subject,
          metadata: {
            from: NOTIFICATION_FROM_EMAIL,
            from_name: input.appearance.fromName,
          },
        },
        source: "notification",
        reference_id: input.sourceEventId,
        user_id: input.userId,
      }),
    });
  } catch (e) {
    throw new Error(`[email] send request failed: ${(e as Error).message}`);
  }

  const text = await response.text();
  let parsed: Record<string, unknown> | null = null;
  if (text) {
    try {
      parsed = JSON.parse(text) as Record<string, unknown>;
    } catch {
      parsed = { raw: text };
    }
  }

  if (response.status >= 500) {
    throw new Error(`[email] send 5xx status=${response.status} body=${text.slice(0, 200)}`);
  }

  if (response.ok && parsed?.success !== false) {
    return { status: "sent", httpStatus: response.status, responseBody: parsed };
  }

  const error =
    (typeof parsed?.error === "string" && parsed.error) || text.slice(0, 200) || "EMAIL_SEND_FAILED";
  return { status: "failed", httpStatus: response.status, responseBody: parsed, error };
}
