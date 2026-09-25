-- Earn channels: Display settings sub-item only (loyalty-admin menu-transforms).
-- Marketplace order ops under Operations.

UPDATE public.admin_menu_config
SET active_status = false
WHERE id IN ('earn-methods', 'earn-channels');

UPDATE public.admin_menu_config
SET parent_id = 'operations',
    label = 'Marketplace orders',
    display_order = 4
WHERE id = 'marketplace';
