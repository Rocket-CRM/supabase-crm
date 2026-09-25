-- Confirm/abort mint are internal to Edge (service_role). Claim page + claim stay anon.

REVOKE EXECUTE ON FUNCTION public.api_confirm_referral_mint(uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.api_abort_referral_claim(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_confirm_referral_mint(uuid, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.api_abort_referral_claim(uuid) TO service_role;
