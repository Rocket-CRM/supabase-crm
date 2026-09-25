export type Platform = "shopee" | "lazada" | "tiktok";

export interface PlatformCredentials {
  merchant_id: string;
  shop_id: string;
  partner_id?: string;
  access_token: string;
  refresh_token?: string;
  region?: string;
  shop_cipher?: string;
  app_key?: string;
  app_secret?: string;
  open_id?: string;
}

export interface NormalizedOrderItem {
  platform_item_id: string;
  variant_id?: string | null;
  platform_sku?: string | null;
  variant_sku?: string | null;
  item_name: string;
  variant_name?: string | null;
  quantity: number;
  currency: string;
  unit_price: number;
  discount_amount: number;
  line_total: number;
}

export interface NormalizedOrder {
  merchant_id: string;
  platform: Platform;
  shop_id: string;
  order_sn: string;
  external_user_id?: string | null;
  buyer_username?: string | null;
  buyer_phone?: string | null;
  buyer_email?: string | null;
  order_status: string;
  transaction_date: string;
  update_time: string;
  currency: string;
  total_amount: number;
  shipping_fee: number;
  discount_amount: number;
  tax_amount: number;
  final_amount: number;
  payment_method?: string | null;
  payment_status?: string | null;
  items: NormalizedOrderItem[];
}
