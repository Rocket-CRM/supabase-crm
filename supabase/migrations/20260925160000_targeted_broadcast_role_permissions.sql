-- Grant menu + BFF access for Targeted broadcast (mirror audience-builder roles).

INSERT INTO public.admin_role_permissions (id, role_id, resource, actions)
SELECT gen_random_uuid(), arp.role_id, 'targeted-broadcast', arp.actions
FROM public.admin_role_permissions arp
WHERE arp.resource = 'audience-builder'
ON CONFLICT (role_id, resource) DO UPDATE SET actions = EXCLUDED.actions;
