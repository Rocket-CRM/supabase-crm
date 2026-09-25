export class AuthError extends Error {
  status: number
  constructor(message: string, status: number) {
    super(message)
    this.status = status
  }
}

export type AdminAuth = { userId: string; merchantId: string }

export async function resolveAdminMerchant(req: Request): Promise<AdminAuth> {
  const { createClient } = await import("jsr:@supabase/supabase-js@2")
  const authHeader = req.headers.get("Authorization")
  if (!authHeader) throw new AuthError("Unauthorized", 401)

  const supabaseAuth = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  )
  const supabaseAdmin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  )

  const {
    data: { user },
    error,
  } = await supabaseAuth.auth.getUser()
  if (error || !user) throw new AuthError("Unauthorized", 401)

  let merchantId: string | null = null
  const headerMerchantId = req.headers.get("x-merchant-id")
  if (headerMerchantId) {
    const { data } = await supabaseAdmin
      .from("admin_users")
      .select("merchant_id")
      .eq("auth_user_id", user.id)
      .eq("merchant_id", headerMerchantId)
      .eq("active_status", true)
      .maybeSingle()
    if (data) merchantId = data.merchant_id
  }

  const activeMerchantId = user.app_metadata?.active_merchant_id as string | undefined
  if (!merchantId && activeMerchantId) {
    const { data } = await supabaseAdmin
      .from("admin_users")
      .select("merchant_id")
      .eq("auth_user_id", user.id)
      .eq("merchant_id", activeMerchantId)
      .eq("active_status", true)
      .maybeSingle()
    if (data) merchantId = data.merchant_id
  }

  if (!merchantId) {
    const { data } = await supabaseAdmin
      .from("admin_users")
      .select("merchant_id")
      .eq("auth_user_id", user.id)
      .eq("active_status", true)
      .limit(1)
    if (data && data.length > 0) merchantId = data[0].merchant_id
  }

  if (!merchantId) throw new AuthError("No active merchant", 403)
  return { userId: user.id, merchantId }
}
