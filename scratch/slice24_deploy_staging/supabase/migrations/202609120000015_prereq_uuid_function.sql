CREATE OR REPLACE FUNCTION public.uuid_generate_v4()
RETURNS uuid
LANGUAGE sql
VOLATILE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT pg_catalog.gen_random_uuid();
$$;
