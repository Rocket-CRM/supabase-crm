-- Tighten EXECUTE: service-role internals; admin BFFs authenticated-only.
-- Default privileges had left anon/authenticated on the fn_* internals.

REVOKE ALL ON FUNCTION public.fn_integration_webhook_url_is_public(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_integration_resolve_member_snapshot(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_integration_lock_credential(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_integration_webhook_url_is_public(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_integration_resolve_member_snapshot(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_integration_lock_credential(uuid) TO service_role;

REVOKE ALL ON FUNCTION public.bff_integration_klaviyo_get_connection(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.bff_integration_klaviyo_disconnect(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.bff_integration_klaviyo_start_sync_all(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.bff_integration_klaviyo_get_connection(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_integration_klaviyo_disconnect(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_integration_klaviyo_start_sync_all(text) TO authenticated, service_role;
