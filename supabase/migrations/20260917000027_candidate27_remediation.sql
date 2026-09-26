-- =============================================================================
-- SU Society App — System Architecture v1.0
-- Candidate 27-01: Missing is_staff() Authorization Helper Remediation
-- Revision 1.0 — Additive Post-Slice-26 Architecture Implementation
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.is_staff(
    uid UUID DEFAULT auth.uid()
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM   public.user_roles ur
        JOIN   public.users      u  ON u.id = ur.user_id
        WHERE  ur.user_id   = uid
          AND  ur.role_name IN (
              'admin',
              'super_admin',
              'gatekeeper',
              'technician',
              'secretary',
              'treasurer',
              'executive_member'
          )
          AND  ur.revoked_on IS NULL
          AND  u.status = 'active'
    );
$$;

COMMENT ON FUNCTION public.is_staff(UUID) IS
    'Returns TRUE if uid holds an active staff/admin role in public.user_roles. Used in RPC authorization checks. SECURITY DEFINER, search_path locked.';

-- Privilege Boundaries
REVOKE ALL ON FUNCTION public.is_staff(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_staff(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_staff(UUID) TO service_role;

COMMIT;
