import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4';
import { verify, create, getNumericDate } from 'https://deno.land/x/djwt@v2.8/mod.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type'
};

interface ShopifyAdminTokenPayload {
  email: string;
  shopify_user_id?: string;
  first_name?: string;
  last_name?: string;
  merchant_code: string;
  shop: string;
  nonce?: string;
  exp: number;
}

async function getShopifyCredentials(supabase: any, merchantCode: string) {
  const { data: merchant } = await supabase
    .from('merchant_master')
    .select('id')
    .eq('merchant_code', merchantCode)
    .single();
  
  if (!merchant) {
    throw new Error('Merchant not found');
  }
  
  const { data: credData } = await supabase
    .from('merchant_credentials')
    .select('credentials')
    .eq('merchant_id', merchant.id)
    .eq('service_name', 'shopify_app')
    .eq('is_active', true)
    .single();
  
  if (!credData) {
    throw new Error('Shopify credentials not found');
  }
  
  return {
    merchant_id: merchant.id,
    api_secret: credData.credentials.api_secret
  };
}

async function findAdminByEmail(
  supabase: any,
  email: string,
  merchantId: string
) {
  const { data } = await supabase
    .from('admin_users')
    .select('*')
    .eq('merchant_id', merchantId)
    .ilike('email', email)
    .single();
  
  return data;
}

async function createAdminUser(
  supabase: any,
  merchantId: string,
  email: string,
  firstName?: string,
  lastName?: string
) {
  const userId = crypto.randomUUID();
  const fullname = [firstName, lastName].filter(Boolean).join(' ') || null;
  
  // Get default admin role
  const { data: roleData } = await supabase
    .from('admin_roles')
    .select('id')
    .eq('code', 'admin')
    .eq('is_system_role', true)
    .single();
  
  if (!roleData) {
    throw new Error('Admin role not found');
  }
  
  const { data: newAdmin, error } = await supabase
    .from('admin_users')
    .insert({
      id: userId,
      auth_user_id: userId,
      merchant_id: merchantId,
      email: email.toLowerCase(),
      name: fullname,
      role_id: roleData.id,
      active_status: true
    })
    .select()
    .single();
  
  if (error) {
    throw new Error(`Failed to create admin: ${error.message}`);
  }
  
  return newAdmin;
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    );

    const { shopify_admin_token, merchant_code } = await req.json();

    if (!shopify_admin_token || !merchant_code) {
      return new Response(JSON.stringify({
        success: false,
        error: 'shopify_admin_token and merchant_code are required'
      }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    // Get merchant credentials
    let merchantId: string;
    let apiSecret: string;
    
    try {
      const creds = await getShopifyCredentials(supabase, merchant_code);
      merchantId = creds.merchant_id;
      apiSecret = creds.api_secret;
    } catch (error) {
      return new Response(JSON.stringify({
        success: false,
        error: error.message
      }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    // Verify and decode Shopify admin token
    let payload: ShopifyAdminTokenPayload;
    
    try {
      const key = await crypto.subtle.importKey(
        'raw',
        new TextEncoder().encode(apiSecret),
        { name: 'HMAC', hash: 'SHA-256' },
        false,
        ['verify']
      );
      
      payload = await verify(shopify_admin_token, key) as unknown as ShopifyAdminTokenPayload;
    } catch (error) {
      console.error('Token verification failed:', error);
      return new Response(JSON.stringify({
        success: false,
        error: 'Invalid token signature'
      }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    // Check token expiration
    if (payload.exp < Math.floor(Date.now() / 1000)) {
      return new Response(JSON.stringify({
        success: false,
        error: 'Token expired'
      }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    // Verify merchant code matches
    if (payload.merchant_code !== merchant_code) {
      return new Response(JSON.stringify({
        success: false,
        error: 'Merchant mismatch'
      }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    // Check nonce if present (optional - prevents replay attacks)
    if (payload.nonce) {
      const { data: nonceResult } = await supabase.rpc('check_and_use_shopify_nonce', {
        p_nonce: payload.nonce,
        p_merchant_id: merchantId
      });

      if (!nonceResult) {
        return new Response(JSON.stringify({
          success: false,
          error: 'Token already used'
        }), {
          status: 401,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        });
      }
    }

    console.log('✅ Token verified for admin:', payload.email);

    // Find or create admin user
    let adminUser = await findAdminByEmail(supabase, payload.email, merchantId);
    let isNewAdmin = false;

    if (!adminUser) {
      console.log('Creating new admin user:', payload.email);
      
      adminUser = await createAdminUser(
        supabase,
        merchantId,
        payload.email,
        payload.first_name,
        payload.last_name
      );
      
      isNewAdmin = true;
    }

    console.log('✅ Admin user ready:', {
      id: adminUser.id,
      email: adminUser.email,
      is_new: isNewAdmin
    });

    // Generate CRM JWT token
    const supabaseJwtSecret = Deno.env.get('JWT_SECRET');
    if (!supabaseJwtSecret) {
      throw new Error('Missing JWT_SECRET in environment variables');
    }

    const key = await crypto.subtle.importKey(
      'raw',
      new TextEncoder().encode(supabaseJwtSecret),
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['sign']
    );
    
    const crmToken = await create(
      { alg: 'HS256', typ: 'JWT' },
      {
        aud: 'authenticated',
        role: 'authenticated',
        exp: getNumericDate(24 * 60 * 60), // 24 hours
        sub: adminUser.auth_user_id,
        email: adminUser.email,
        merchant_id: merchantId,
        merchant_code: merchant_code,
        user_metadata: {
          role: 'admin',
          source: 'shopify_admin'
        }
      },
      key
    );

    console.log('✅ CRM token generated');

    return new Response(JSON.stringify({
      success: true,
      admin_user: {
        id: adminUser.id,
        email: adminUser.email,
        name: adminUser.name,
        merchant_code: merchant_code
      },
      crm_token: crmToken,
      is_new_admin: isNewAdmin
    }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });

  } catch (error) {
    console.error('Error in auth-shopify-admin:', error);
    return new Response(JSON.stringify({
      success: false,
      error: error.message
    }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }
});
