-- CANDIDATE-28-01 REMEDIATION MIGRATION
-- Remediates FIND-DB-TEST-01: Vendor Society Scope Validation in public.log_asset_service()
-- Slice 28 Additive Remediation

CREATE OR REPLACE FUNCTION public.log_asset_service(
    p_asset_id UUID,
    p_vendor_id UUID,
    p_service_date DATE,
    p_description TEXT,
    p_cost NUMERIC,
    p_performed_by VARCHAR
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_society_id UUID;
    v_asset_status VARCHAR;
    v_vendor_society_id UUID;
    v_vendor_status VARCHAR;
    v_log_id UUID;
BEGIN
    -- 1. Authorization Check: Require Admin or Staff role
    IF NOT (public.is_admin() OR public.is_staff()) THEN
        RAISE EXCEPTION 'Access Denied: Only Admins or Staff can log asset services';
    END IF;

    -- 2. Asset Lookup & Active Society Validation
    SELECT society_id, status INTO v_society_id, v_asset_status
    FROM public.assets
    WHERE id = p_asset_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Asset not found';
    END IF;

    IF v_society_id <> public.get_user_society_id() THEN
        RAISE EXCEPTION 'Cross-society access denied';
    END IF;

    -- 3. Vendor Lookup & Society Match Validation (Remediates FIND-DB-TEST-01)
    IF p_vendor_id IS NOT NULL THEN
        SELECT society_id, status INTO v_vendor_society_id, v_vendor_status
        FROM public.vendors
        WHERE id = p_vendor_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Vendor not found';
        END IF;

        IF v_vendor_status <> 'active' THEN
            RAISE EXCEPTION 'Cannot log service with inactive vendor';
        END IF;

        IF v_vendor_society_id IS NULL OR v_vendor_society_id <> v_society_id THEN
            RAISE EXCEPTION 'Vendor does not belong to the asset society';
        END IF;
    END IF;

    -- 4. Atomic Maintenance Log Insertion
    INSERT INTO public.asset_maintenance_logs (
        society_id,
        asset_id,
        vendor_id,
        service_date,
        description,
        cost,
        performed_by,
        created_by
    ) VALUES (
        v_society_id,
        p_asset_id,
        p_vendor_id,
        p_service_date,
        p_description,
        p_cost,
        p_performed_by,
        auth.uid()
    )
    RETURNING id INTO v_log_id;

    -- 5. Dual Write to Audit Logs
    INSERT INTO public.audit_logs (
        society_id,
        actor_id,
        action,
        entity_type,
        entity_id,
        details
    ) VALUES (
        v_society_id,
        auth.uid(),
        'asset_service_logged',
        'asset_maintenance_logs',
        v_log_id,
        jsonb_build_object(
            'asset_id', p_asset_id,
            'vendor_id', p_vendor_id,
            'cost', p_cost,
            'service_date', p_service_date
        )
    );

    RETURN v_log_id;
END;
$$;

-- 6. Privilege Boundary Hardening
REVOKE EXECUTE ON FUNCTION public.log_asset_service(UUID, UUID, DATE, TEXT, NUMERIC, VARCHAR) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.log_asset_service(UUID, UUID, DATE, TEXT, NUMERIC, VARCHAR) TO authenticated;
GRANT EXECUTE ON FUNCTION public.log_asset_service(UUID, UUID, DATE, TEXT, NUMERIC, VARCHAR) TO service_role;
