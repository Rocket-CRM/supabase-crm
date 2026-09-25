/** Lazada Push: Authorization = HEX(HMAC-SHA256(AppKey + rawBody, AppSecret)) */

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

async function hmacSha256Hex(message: string, secret: string): Promise<string> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, encoder.encode(message));
  return bytesToHex(new Uint8Array(sig));
}

export async function verifyLazadaPushSignature(
  rawBody: string,
  authorization: string | null,
): Promise<{ ok: boolean; reason?: string }> {
  const appKey = Deno.env.get("LAZADA_APP_KEY");
  const appSecret = Deno.env.get("LAZADA_APP_SECRET");

  if (!appKey || !appSecret) {
    console.warn("[lazada] LAZADA_APP_KEY / LAZADA_APP_SECRET not set — signature check skipped");
    return { ok: true, reason: "signature_check_skipped" };
  }

  if (!authorization) {
    return { ok: false, reason: "missing_authorization_header" };
  }

  const base = appKey + rawBody;
  const expected = await hmacSha256Hex(base, appSecret);
  const ok = timingSafeEqual(authorization.trim().toLowerCase(), expected.toLowerCase());

  return ok ? { ok: true } : { ok: false, reason: "signature_mismatch" };
}
