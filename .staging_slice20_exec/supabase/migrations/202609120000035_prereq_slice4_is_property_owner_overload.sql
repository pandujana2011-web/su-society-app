CREATE OR REPLACE FUNCTION public.is_property_owner(p_property_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
SELECT public.is_property_owner(auth.uid(), p_property_id);
$$;

COMMENT ON FUNCTION public.is_property_owner(UUID) IS
'Convenience overload evaluating ownership for the currently authenticated user (auth.uid()).';

REVOKE EXECUTE ON FUNCTION public.is_property_owner(UUID) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.is_property_owner(UUID) TO authenticated, service_role;
