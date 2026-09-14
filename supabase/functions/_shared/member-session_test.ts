import { assertEquals } from 'https://deno.land/std@0.168.0/testing/asserts.ts';
import { verify } from 'https://deno.land/x/djwt@v2.8/mod.ts';
import { issueMemberSession } from './member-session.ts';

Deno.test('issueMemberSession emits CRM member claims', async () => {
  const prior = Deno.env.get('SUPABASE_JWT_SECRET');
  Deno.env.set('SUPABASE_JWT_SECRET', 'test-member-session-secret-at-least-32-chars!!');

  try {
    const userId = '5ce979af-1fce-4d44-8e65-2a0a08219098';
    const merchantId = '09b45463-3812-42fb-9c7f-9d43b6fd3eb9';
    const { access_token, expires_in } = await issueMemberSession({
      userAccount: {
        id: userId,
        tel: '+66966564526',
        line_id: 'U46fa97098b91e50011b8b556c5690e3bb',
        email: 'member@example.com',
      },
      merchantId,
      channel: 'shopify',
    });

    assertEquals(expires_in, 30 * 24 * 60 * 60);

    const key = await crypto.subtle.importKey(
      'raw',
      new TextEncoder().encode('test-member-session-secret-at-least-32-chars!!'),
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['verify'],
    );
    const payload = await verify(access_token, key) as Record<string, unknown>;

    assertEquals(payload.sub, userId);
    assertEquals(payload.user_id, userId);
    assertEquals(payload.merchant_id, merchantId);
    assertEquals(payload.phone, '+66966564526');
    assertEquals(payload.line_id, 'U46fa97098b91e50011b8b556c5690e3bb');
    assertEquals(payload.email, 'member@example.com');
    assertEquals(payload.role, 'authenticated');
    assertEquals(payload.aud, 'authenticated');
    assertEquals(payload.iss, 'supabase');
    assertEquals(payload.channel, 'shopify');
  } finally {
    if (prior === undefined) Deno.env.delete('SUPABASE_JWT_SECRET');
    else Deno.env.set('SUPABASE_JWT_SECRET', prior);
  }
});
