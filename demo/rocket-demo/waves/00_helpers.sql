
-- Rocket Demo generator helpers + waves
-- Merchant: rocket-demo / fae172a5-de90-440e-a766-db6a5982cc9b

CREATE OR REPLACE FUNCTION public.custom_internal_demo_rand(p_key text)
RETURNS double precision
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT (('x' || substr(md5(p_key), 1, 8))::bit(32)::bigint % 1000000)::double precision / 1000000.0;
$$;

CREATE OR REPLACE FUNCTION public.custom_internal_demo_settings()
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
  SELECT payload FROM public.custom_internal_demo_config
  WHERE kind = 'settings' AND code = 'default' AND is_active
  LIMIT 1;
$$;
