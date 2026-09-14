import { create, getNumericDate } from 'https://deno.land/x/djwt@v2.8/mod.ts';

export const ACCESS_TOKEN_EXPIRY = 30 * 24 * 60 * 60;

export type MemberSessionChannel = 'line' | 'tel' | 'shopify';

export type UserAccountForSession = {
  id: string;
  tel?: string | null;
  line_id?: string | null;
  email?: string | null;
};

export function getMemberJwtSecret(): string | undefined {
  return Deno.env.get('SUPABASE_JWT_SECRET') || Deno.env.get('JWT_SECRET');
}

export async function issueMemberSession(params: {
  userAccount: UserAccountForSession;
  merchantId: string;
  channel: MemberSessionChannel;
}): Promise<{ access_token: string; expires_in: number }> {
  const jwtSecret = getMemberJwtSecret();
  if (!jwtSecret) {
    throw new Error('JWT secret not configured');
  }

  const { userAccount, merchantId, channel } = params;
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(jwtSecret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );

  const access_token = await create(
    { alg: 'HS256', typ: 'JWT' },
    {
      sub: userAccount.id,
      merchant_id: merchantId,
      user_id: userAccount.id,
      phone: userAccount.tel,
      line_id: userAccount.line_id,
      email: userAccount.email,
      role: 'authenticated',
      aud: 'authenticated',
      iss: 'supabase',
      exp: getNumericDate(ACCESS_TOKEN_EXPIRY),
      channel,
    },
    key,
  );

  return { access_token, expires_in: ACCESS_TOKEN_EXPIRY };
}
