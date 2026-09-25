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
  variant_id?: string;
  platform_sku?: string;
  item_name: string;
  variant_name?: string;
  quantity: number;
  currency: string;
  unit_price: number;
  discount_amount: number;
  line_total: number;
  earnable_amount: number;
  financial_details: Record<string, unknown>;
}

export interface NormalizedOrder {
  merchant_id: string;
  platform: string;
  shop_id: string;
  order_sn: string;
  external_user_id?: string;
  buyer_username?: string;
  buyer_phone?: string;
  buyer_email?: string;
  order_status: string;
  transaction_date: string;
  update_time: string;
  currency: string;
  total_amount: number;
  shipping_fee: number;
  discount_amount: number;
  tax_amount: number;
  final_amount: number;
  earnable_amount: number;
  financial_details: Record<string, unknown>;
  payment_method?: string;
  payment_status?: string;
  items: NormalizedOrderItem[];
}

export interface MarketplaceAdapter {
  readonly supportsBatch: boolean;
  getNewOrderStatuses(): string[];
  buildGetOrderDetailsRequest(
    credentials: PlatformCredentials,
    orderSns: string[],
  ): Promise<{ url: string; options: RequestInit }>;
  parseOrdersResponse(response: unknown): unknown[];
  normalizeOrder(platformOrder: unknown, credentials: PlatformCredentials): NormalizedOrder;
}
