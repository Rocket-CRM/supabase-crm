const encoder = new TextEncoder()

function toBase64Url(bytes: Uint8Array): string {
  let bin = ""
  for (const b of bytes) bin += String.fromCharCode(b)
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
}

function fromBase64Url(s: string): Uint8Array {
  const padded = s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4)
  const bin = atob(padded)
  const out = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i)
  return out
}

export function randomUrlSafe(byteLen = 32): string {
  return toBase64Url(crypto.getRandomValues(new Uint8Array(byteLen)))
}

async function hmacHex(secret: string, data: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  )
  const sig = await crypto.subtle.sign("HMAC", key, encoder.encode(data))
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("")
}

async function sha256Base64Url(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(value))
  return toBase64Url(new Uint8Array(digest))
}

export async function generatePkce(): Promise<{ verifier: string; challenge: string }> {
  const verifier = randomUrlSafe(32)
  const challenge = await sha256Base64Url(verifier)
  return { verifier, challenge }
}

export interface OAuthStatePayload {
  merchant_id: string
  integration_key: string
  exp: number
  nonce: string
}

function stateSecret(): string {
  const secret = Deno.env.get("INTEGRATION_OAUTH_STATE_SECRET") || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
  if (!secret) throw new Error("INTEGRATION_OAUTH_STATE_SECRET is not set")
  return secret
}

export async function signOAuthState(payload: OAuthStatePayload): Promise<string> {
  const body = JSON.stringify(payload)
  const bodyB64 = toBase64Url(encoder.encode(body))
  const sig = await hmacHex(stateSecret(), bodyB64)
  return `${bodyB64}.${sig}`
}

export async function verifyOAuthState(state: string): Promise<OAuthStatePayload> {
  const [bodyB64, sig] = state.split(".")
  if (!bodyB64 || !sig) throw new Error("invalid_state")
  const expected = await hmacHex(stateSecret(), bodyB64)
  if (expected !== sig) throw new Error("invalid_state")
  const json = new TextDecoder().decode(fromBase64Url(bodyB64))
  const payload = JSON.parse(json) as OAuthStatePayload
  if (payload.exp < Date.now()) throw new Error("expired_state")
  return payload
}

export { toBase64Url, fromBase64Url }
