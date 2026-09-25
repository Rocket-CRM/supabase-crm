-- Admin menu entry for the Audience report (visibility follows audience-builder read access).

INSERT INTO public.admin_menu_config (id, label, href, category, resource, display_order, active_status, feature_group)
VALUES ('report-audiences', 'Audience report', '/reports/audiences', 'loyalty', 'audience-builder', 130, true, 'marketing_automation')
ON CONFLICT (id) DO UPDATE
SET label = EXCLUDED.label,
    href = EXCLUDED.href,
    category = EXCLUDED.category,
    resource = EXCLUDED.resource,
    active_status = EXCLUDED.active_status,
    feature_group = EXCLUDED.feature_group;
