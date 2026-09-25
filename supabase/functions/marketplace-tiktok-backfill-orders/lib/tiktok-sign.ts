/** TikTok Shop Open API HMAC-SHA256 (matches inngest-marketplace-serve TikTokAdapter). */

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes).map((b) => b.toString(16).padStart(2, "0")).join("");
}

export async function tiktokHmacSha256Hex(message: string, secret: string): Promise<string> {
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

/** GET: secret + path + sortedQuery + secret. POST: secret + path + sortedQuery + body + secret. */
export async function signTiktokRequest(
  path: string,
  queryParams: Record<string, string>,
  appSecret: string,
  body?: string,
): Promise<string> {
  const sortedKeys = Object.keys(queryParams).sort();
  const paramString = sortedKeys.map((k) => `${k}${queryParams[k]}`).join("");
  const signString = body ? `${path}${paramString}${body}` : `${path}${paramString}`;
  const wrapped = `${appSecret}${signString}${appSecret}`;
  return tiktokHmacSha256Hex(wrapped, appSecret);
}
