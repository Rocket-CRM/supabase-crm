-- Activity log stays in admin_audit_log; no sidebar entry (direct URL / embedded history only).
UPDATE public.admin_menu_config
SET active_status = false
WHERE id = 'activity-log';
