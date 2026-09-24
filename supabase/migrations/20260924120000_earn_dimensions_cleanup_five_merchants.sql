-- Earn rules simplification: remove __earn_rate_dimensions markers and collapse empty groups.
-- Rollback: restore rows from audit snapshot (Sep 24 2026) if needed.

CREATE OR REPLACE FUNCTION pg_temp.delete_earn_schema_marker(p_group_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.earn_conditions_group
    WHERE id = p_group_id AND name LIKE '__earn_rate_dimensions:%'
  ) THEN
    RAISE EXCEPTION 'Not a schema marker group: %', p_group_id;
  END IF;

  IF EXISTS (SELECT 1 FROM public.earn_conditions WHERE group_id = p_group_id) THEN
    RAISE EXCEPTION 'Schema marker % still has earn_conditions', p_group_id;
  END IF;

  IF EXISTS (SELECT 1 FROM public.earn_factor WHERE earn_conditions_group_id = p_group_id) THEN
    RAISE EXCEPTION 'Schema marker % referenced by earn_factor', p_group_id;
  END IF;

  DELETE FROM public.earn_conditions_group WHERE id = p_group_id;
END;
$$;

-- Phase A: five live merchants — delete markers only (Pisenthailand / Pornmaya / sereichaibeauty: no other earn changes)
SELECT pg_temp.delete_earn_schema_marker('841885de-0381-4ee3-9aa9-877345dc2ab6'); -- Kao Smile Club
SELECT pg_temp.delete_earn_schema_marker('5d39f7cc-413c-4b26-ad78-44ee38c35eaa'); -- Mypaws
SELECT pg_temp.delete_earn_schema_marker('12abfe8d-47b7-4a44-ab5d-fb4d75e85445'); -- Pisenthailand
SELECT pg_temp.delete_earn_schema_marker('9c4987a2-d4b5-4655-8902-15d1d9172967'); -- Pornmaya
SELECT pg_temp.delete_earn_schema_marker('0aec5dcc-da50-4abb-9653-56e7448942e5'); -- sereichaibeauty

-- Kao Smile Club: orphan studio condition groups (no factor refs)
DELETE FROM public.earn_conditions
WHERE group_id IN (
  '705af6dd-8888-4109-8628-a3077bb060bb',
  '709a37a3-1f15-409d-b845-284a4a4d219d'
);
DELETE FROM public.earn_conditions_group
WHERE id IN (
  '705af6dd-8888-4109-8628-a3077bb060bb',
  '709a37a3-1f15-409d-b845-284a4a4d219d'
);

-- Kao: collapse empty earn_factor_groups to one Basic points config (keep oldest by created_at)
DELETE FROM public.earn_factor_group
WHERE merchant_id = '3365ee7e-7de7-4b94-b2ea-6f78314817b7'
  AND id IN (
    '81525852-b37e-4a1f-a8e0-c1247a97d076',
    '0bd86c5d-0172-4537-9aaf-61baefaa43aa'
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.earn_factor ef WHERE ef.earn_factor_group_id = earn_factor_group.id
  );

-- Mypaws: collapse empty groups (keep c9235c3b-7d70-43a6-bfaa-949cafa59049)
DELETE FROM public.earn_factor_group
WHERE merchant_id = 'ac5971b7-f006-48b9-bbd6-c9cf0545413f'
  AND id IN (
    'bb5d1579-9622-49f1-a6bf-0e25f68850d3',
    'e8ab1203-922c-4036-9de8-6276058e9955'
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.earn_factor ef WHERE ef.earn_factor_group_id = earn_factor_group.id
  );

-- Phase B1: additional merchants verified safe to drop marker only
SELECT pg_temp.delete_earn_schema_marker('e2271c3c-2e8d-4aac-9fe4-f6fc8119ac6a'); -- Rocket Demo
SELECT pg_temp.delete_earn_schema_marker('2c936de4-1948-41a4-82de-72eba66d3715'); -- Dr.PONG
SELECT pg_temp.delete_earn_schema_marker('b417d65e-e7b9-4be6-9480-c7bb3b97855d'); -- Prakaivanich
