-- The refresh-schedule versions (20260925180100) default every new param, so the
-- 5-arg versions made named-arg calls ambiguous (42725 / PGRST203).
DROP FUNCTION IF EXISTS public.bff_create_audience(text, text, jsonb, text, text);
DROP FUNCTION IF EXISTS public.bff_update_audience(uuid, text, text, jsonb, text);
