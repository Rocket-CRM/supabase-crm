/** Shared wallet reversal for shopify_points_to_discount burns. */

export async function reversePointsBurn(
  supabase: any,
  userId: string,
  merchantId: string,
  pointsAmount: number,
  originalTransactionId: string,
  description = "Refund: Shopify discount entitlement failed",
): Promise<void> {
  try {
    const { error } = await supabase.rpc("chokepoint_post_wallet_transaction", {
      p_user_id: userId,
      p_currency: "points",
      p_source_type: "redemption_cancellation",
      p_component: "base",
      p_transaction_type: "earn",
      p_amount: pointsAmount,
      p_transaction_id: crypto.randomUUID(),
      p_merchant_id: merchantId,
      p_description: description,
      p_metadata: {
        type: "shopify_points_to_discount_reversal",
        original_transaction_id: originalTransactionId,
      },
    });
    if (error) console.error("[shopify-points-reversal] CRITICAL: Failed to reverse points burn:", error);
  } catch (err: any) {
    console.error("[shopify-points-reversal] CRITICAL: Exception reversing points:", err);
  }
}
