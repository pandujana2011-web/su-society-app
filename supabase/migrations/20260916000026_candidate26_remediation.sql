-- =============================================================================
-- SU Society App — System Architecture v1.0
-- Candidate 26-01: Vendor Registry, Asset Inventory & AMC Management System
-- Revision 2.0 — Slice-7 Additive Architecture Implementation
-- =============================================================================

BEGIN;

-- ===========================================================================
-- STEP 1 — ADDITIVE COLUMNS ON SLICE-7 TABLES
-- ===========================================================================

-- 1.1 Extend public.vendors with service_category
ALTER TABLE public.vendors
    ADD COLUMN IF NOT EXISTS service_category VARCHAR(100) DEFAULT 'General Maintenance';

-- 1.2 Extend public.assets with asset_code, purchase_cost, serial_number
ALTER TABLE public.assets
    ADD COLUMN IF NOT EXISTS asset_code TEXT,
    ADD COLUMN IF NOT EXISTS purchase_cost NUMERIC(12,2) DEFAULT 0.00 CONSTRAINT chk_asset_purchase_cost CHECK (purchase_cost >= 0),
    ADD COLUMN IF NOT EXISTS serial_number VARCHAR(150);

-- ===========================================================================
-- STEP 2 — DETERMINISTIC LEGACY DATA BACKFILL FOR ASSET_CODE
-- ===========================================================================

UPDATE public.assets
SET asset_code = 'AST-' || UPPER(SUBSTRING(id::text FROM 1 FOR 8))
WHERE asset_code IS NULL;

-- ===========================================================================
-- STEP 3 — CONSTRAINT HARDENING & ASSET CODE NORMALIZATION
-- ===========================================================================

ALTER TABLE public.assets
    ALTER COLUMN asset_code SET NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'uq_assets_society_asset_code'
    ) THEN
        ALTER TABLE public.assets
            ADD CONSTRAINT uq_assets_society_asset_code UNIQUE (society_id, asset_code);
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.fn_normalize_asset_code()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.asset_code IS NOT NULL THEN
        NEW.asset_code := UPPER(TRIM(NEW.asset_code));
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_normalize_asset_code ON public.assets;
CREATE TRIGGER trg_normalize_asset_code
    BEFORE INSERT OR UPDATE ON public.assets
    FOR EACH ROW EXECUTE FUNCTION public.fn_normalize_asset_code();

-- ===========================================================================
-- STEP 4 — ASSET MAINTENANCE LOGS TABLE & APPEND-ONLY TRIGGER
-- ===========================================================================

CREATE TABLE IF NOT EXISTS public.asset_maintenance_logs (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id          UUID        NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    asset_id            UUID        NOT NULL REFERENCES public.assets(id) ON DELETE RESTRICT,
    vendor_id           UUID        REFERENCES public.vendors(id) ON DELETE RESTRICT,
    service_date        DATE        NOT NULL DEFAULT CURRENT_DATE,
    description         TEXT        NOT NULL CONSTRAINT chk_maintenance_log_desc CHECK (TRIM(description) <> ''),
    cost                NUMERIC(12,2) NOT NULL DEFAULT 0.00 CONSTRAINT chk_maintenance_log_cost CHECK (cost >= 0),
    performed_by        VARCHAR(150),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Append-Only Mutation Prevention Trigger
CREATE OR REPLACE FUNCTION public.fn_prevent_maintenance_log_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    RAISE EXCEPTION 'Asset maintenance logs are append-only. UPDATE and DELETE operations are prohibited.';
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_maintenance_log_mutation ON public.asset_maintenance_logs;
CREATE TRIGGER trg_prevent_maintenance_log_mutation
    BEFORE UPDATE OR DELETE ON public.asset_maintenance_logs
    FOR EACH ROW EXECUTE FUNCTION public.fn_prevent_maintenance_log_mutation();

-- ===========================================================================
-- STEP 5 — MULTI-TENANT RLS POLICIES FOR MAINTENANCE LOGS
-- ===========================================================================

ALTER TABLE public.asset_maintenance_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS p_asset_maintenance_logs_society_isolation ON public.asset_maintenance_logs;
CREATE POLICY p_asset_maintenance_logs_society_isolation ON public.asset_maintenance_logs
    FOR ALL TO authenticated
    USING (society_id = public.get_user_society_id())
    WITH CHECK (society_id = public.get_user_society_id());

-- ===========================================================================
-- STEP 6 — RPC HARDENING & AUDIT ATOMICITY
-- ===========================================================================

-- 6.1 RPC: Concurrency-Hardened AMC Renewal (Row Locking on Slice-7 asset_amc)
CREATE OR REPLACE FUNCTION public.renew_amc(
    p_amc_id UUID,
    p_new_end_date DATE,
    p_new_cost NUMERIC
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_amc RECORD;
    v_vendor_status VARCHAR;
BEGIN
    IF NOT (public.is_admin() OR public.is_staff()) THEN
        RAISE EXCEPTION 'Access Denied: Only Admins or Staff can renew AMC contracts';
    END IF;

    -- Concurrency Row Locking
    SELECT * INTO v_amc
    FROM public.asset_amc
    WHERE id = p_amc_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'AMC contract not found';
    END IF;

    IF v_amc.society_id <> public.get_user_society_id() THEN
        RAISE EXCEPTION 'Cross-society access denied';
    END IF;

    SELECT status INTO v_vendor_status
    FROM public.vendors
    WHERE id = v_amc.vendor_id;

    IF v_vendor_status <> 'active' THEN
        RAISE EXCEPTION 'Cannot renew AMC with inactive vendor';
    END IF;

    IF p_new_end_date <= v_amc.start_date THEN
        RAISE EXCEPTION 'New end date must be after AMC start date';
    END IF;

    IF p_new_cost < 0 THEN
        RAISE EXCEPTION 'AMC cost cannot be negative';
    END IF;

    UPDATE public.asset_amc
    SET end_date = p_new_end_date,
        cost = p_new_cost,
        updated_at = NOW()
    WHERE id = p_amc_id;
END;
$$;

-- 6.2 RPC: Atomic Service Logging with Dual-Write Audit
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
    v_vendor_status VARCHAR;
    v_log_id UUID;
BEGIN
    IF NOT (public.is_admin() OR public.is_staff()) THEN
        RAISE EXCEPTION 'Access Denied: Only Admins or Staff can log asset services';
    END IF;

    SELECT society_id, status INTO v_society_id, v_asset_status
    FROM public.assets
    WHERE id = p_asset_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Asset not found';
    END IF;

    IF v_society_id <> public.get_user_society_id() THEN
        RAISE EXCEPTION 'Cross-society access denied';
    END IF;

    IF p_vendor_id IS NOT NULL THEN
        SELECT status INTO v_vendor_status
        FROM public.vendors
        WHERE id = p_vendor_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Vendor not found';
        END IF;

        IF v_vendor_status <> 'active' THEN
            RAISE EXCEPTION 'Cannot log service with inactive vendor';
        END IF;
    END IF;

    -- Target 1: Insert Into Asset Maintenance Logs
    INSERT INTO public.asset_maintenance_logs (
        society_id,
        asset_id,
        vendor_id,
        service_date,
        description,
        cost,
        performed_by
    ) VALUES (
        v_society_id,
        p_asset_id,
        p_vendor_id,
        p_service_date,
        p_description,
        p_cost,
        p_performed_by
    ) RETURNING id INTO v_log_id;

    -- Target 2: Atomic Dual-Write to Central Audit Logs
    INSERT INTO public.audit_logs (
        society_id,
        actor_id,
        action,
        entity_type,
        entity_id,
        new_data
    ) VALUES (
        v_society_id,
        auth.uid(),
        'asset_service_logged',
        'asset_maintenance_logs',
        v_log_id,
        jsonb_build_object(
            'asset_id', p_asset_id,
            'vendor_id', p_vendor_id,
            'service_date', p_service_date,
            'cost', p_cost,
            'performed_by', p_performed_by
        )
    );

    RETURN v_log_id;
END;
$$;

-- ===========================================================================
-- STEP 7 — PRIVILEGE HARDENING
-- ===========================================================================

REVOKE ALL ON FUNCTION public.renew_amc(UUID, DATE, NUMERIC) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.renew_amc(UUID, DATE, NUMERIC) TO authenticated;

REVOKE ALL ON FUNCTION public.log_asset_service(UUID, UUID, DATE, TEXT, NUMERIC, VARCHAR) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.log_asset_service(UUID, UUID, DATE, TEXT, NUMERIC, VARCHAR) TO authenticated;

COMMIT;
