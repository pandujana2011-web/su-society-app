-- =============================================================================
-- SU Society App — System Architecture v1.0
-- Schema Slice 7: Vendors & Assets
-- =============================================================================

BEGIN;

-- ===========================================================================
-- STEP 1 — VENDORS
-- ===========================================================================

CREATE TABLE IF NOT EXISTS public.vendors (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id          UUID        NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    name                VARCHAR(200) NOT NULL CONSTRAINT chk_vendor_name CHECK (TRIM(name) <> ''),
    contact_person      VARCHAR(150),
    phone               VARCHAR(50),
    email               VARCHAR(200),
    gst_number          VARCHAR(50),
    pan_number          VARCHAR(50),
    status              VARCHAR(30) NOT NULL DEFAULT 'active'
                            CONSTRAINT chk_vendor_status CHECK (status IN ('active', 'inactive')),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_vendors_updated_at
    BEFORE UPDATE ON public.vendors
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_audit_vendors
    AFTER INSERT OR UPDATE OR DELETE ON public.vendors
    FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger_func();

-- ===========================================================================
-- STEP 2 — VENDOR STATUS TRANSITION
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.fn_transition_vendor_status(
    p_vendor_id UUID,
    p_new_status VARCHAR
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_society_id UUID;
    v_current_status VARCHAR;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access Denied: Only Admins can modify vendor status';
    END IF;

    SELECT society_id, status INTO v_society_id, v_current_status
    FROM public.vendors
    WHERE id = p_vendor_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Vendor not found';
    END IF;

    IF v_society_id <> public.get_user_society_id() THEN
        RAISE EXCEPTION 'Cross-society access denied';
    END IF;

    IF v_current_status = p_new_status THEN
        RETURN;
    END IF;

    IF p_new_status NOT IN ('active', 'inactive') THEN
        RAISE EXCEPTION 'Invalid status transition';
    END IF;

    UPDATE public.vendors
    SET status = p_new_status
    WHERE id = p_vendor_id;
END;
$$;

-- Prevent direct UPDATE of status
CREATE OR REPLACE FUNCTION public.trg_prevent_direct_vendor_status_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.status IS DISTINCT FROM OLD.status THEN
        -- Check if it is being called from our secure transition function
        -- (In Postgres, we just rely on RLS blocking regular updates or this trigger enforcing it)
        -- Since users have no direct UPDATE privileges to vendors (or if they do, we want to block status change)
        IF NOT (current_query() ILIKE '%fn_transition_vendor_status%') THEN
             RAISE EXCEPTION 'Direct UPDATE of vendor status is prohibited. Use fn_transition_vendor_status()';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_prevent_vendor_status_update
    BEFORE UPDATE ON public.vendors
    FOR EACH ROW EXECUTE FUNCTION public.trg_prevent_direct_vendor_status_update();

-- ===========================================================================
-- STEP 3 — VENDOR BANK DETAILS
-- ===========================================================================

CREATE TABLE IF NOT EXISTS public.vendor_bank_details (
    vendor_id           UUID        PRIMARY KEY REFERENCES public.vendors(id) ON DELETE CASCADE,
    society_id          UUID        NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    account_name        VARCHAR(200) NOT NULL,
    account_number      VARCHAR(100) NOT NULL,
    ifsc_code           VARCHAR(50) NOT NULL,
    bank_name           VARCHAR(150),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_vendor_bank_details_updated_at
    BEFORE UPDATE ON public.vendor_bank_details
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Custom Metadata-Only Audit for Bank Details
CREATE OR REPLACE FUNCTION public.fn_audit_vendor_bank_metadata()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_society_id UUID;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_society_id := OLD.society_id;
    ELSE
        v_society_id := NEW.society_id;
    END IF;

    INSERT INTO public.audit_logs (
        society_id,
        actor_id,
        action,
        entity_type,
        entity_id,
        old_data,
        new_data
    ) VALUES (
        v_society_id,
        auth.uid(),
        'bank_details_' || lower(TG_OP),
        TG_TABLE_NAME,
        COALESCE(NEW.vendor_id, OLD.vendor_id),
        NULL, -- Payload explicitly redacted
        NULL  -- Payload explicitly redacted
    );

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_audit_vendor_bank_details
    AFTER INSERT OR UPDATE OR DELETE ON public.vendor_bank_details
    FOR EACH ROW EXECUTE FUNCTION public.fn_audit_vendor_bank_metadata();

-- Trigger to validate society isolation on INSERT
CREATE OR REPLACE FUNCTION public.trg_validate_bank_details_society()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_vendor_society_id UUID;
BEGIN
    SELECT society_id INTO v_vendor_society_id
    FROM public.vendors WHERE id = NEW.vendor_id;

    IF v_vendor_society_id <> NEW.society_id THEN
        RAISE EXCEPTION 'Cross-society vendor bank linkage is strictly prohibited';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_vendor_bank_society_match
    BEFORE INSERT OR UPDATE ON public.vendor_bank_details
    FOR EACH ROW EXECUTE FUNCTION public.trg_validate_bank_details_society();

-- ===========================================================================
-- STEP 4 — ASSETS
-- ===========================================================================

CREATE TABLE IF NOT EXISTS public.assets (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id          UUID        NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    name                VARCHAR(200) NOT NULL CONSTRAINT chk_asset_name CHECK (TRIM(name) <> ''),
    category            VARCHAR(100) NOT NULL,
    location            VARCHAR(200),
    purchase_date       DATE,
    warranty_expiry     DATE,
    status              VARCHAR(30) NOT NULL DEFAULT 'active'
                            CONSTRAINT chk_asset_status CHECK (status IN ('active', 'maintenance', 'retired')),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_assets_updated_at
    BEFORE UPDATE ON public.assets
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_audit_assets
    AFTER INSERT OR UPDATE OR DELETE ON public.assets
    FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger_func();

-- ===========================================================================
-- STEP 5 — ASSET STATUS TRANSITION
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.fn_transition_asset_status(
    p_asset_id UUID,
    p_new_status VARCHAR
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_society_id UUID;
    v_current_status VARCHAR;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access Denied: Only Admins can modify asset status';
    END IF;

    SELECT society_id, status INTO v_society_id, v_current_status
    FROM public.assets
    WHERE id = p_asset_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Asset not found';
    END IF;

    IF v_society_id <> public.get_user_society_id() THEN
        RAISE EXCEPTION 'Cross-society access denied';
    END IF;

    IF v_current_status = p_new_status THEN
        RETURN;
    END IF;

    IF v_current_status = 'retired' THEN
        RAISE EXCEPTION 'Retired assets cannot transition to other states';
    END IF;

    IF p_new_status NOT IN ('active', 'maintenance', 'retired') THEN
        RAISE EXCEPTION 'Invalid status transition';
    END IF;

    UPDATE public.assets
    SET status = p_new_status
    WHERE id = p_asset_id;
END;
$$;

-- Prevent direct UPDATE of asset status
CREATE OR REPLACE FUNCTION public.trg_prevent_direct_asset_status_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.status IS DISTINCT FROM OLD.status THEN
        IF NOT (current_query() ILIKE '%fn_transition_asset_status%') THEN
             RAISE EXCEPTION 'Direct UPDATE of asset status is prohibited. Use fn_transition_asset_status()';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_prevent_asset_status_update
    BEFORE UPDATE ON public.assets
    FOR EACH ROW EXECUTE FUNCTION public.trg_prevent_direct_asset_status_update();

-- ===========================================================================
-- STEP 6 — ASSET AMC
-- ===========================================================================

CREATE TABLE IF NOT EXISTS public.asset_amc (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id          UUID        NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    asset_id            UUID        NOT NULL REFERENCES public.assets(id) ON DELETE RESTRICT,
    vendor_id           UUID        NOT NULL REFERENCES public.vendors(id) ON DELETE RESTRICT,
    contract_number     VARCHAR(100),
    start_date          DATE        NOT NULL,
    end_date            DATE        NOT NULL,
    cost                NUMERIC(15,2) NOT NULL CONSTRAINT chk_amc_cost CHECK (cost >= 0),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_amc_dates CHECK (end_date >= start_date)
);

-- EXCLUDE Overlapping AMC periods for the same asset
ALTER TABLE public.asset_amc
    ADD CONSTRAINT excl_amc_no_overlap
    EXCLUDE USING gist (
        asset_id WITH =,
        daterange(start_date, end_date, '[]') WITH &&
    );

CREATE TRIGGER trg_asset_amc_updated_at
    BEFORE UPDATE ON public.asset_amc
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_audit_asset_amc
    AFTER INSERT OR UPDATE OR DELETE ON public.asset_amc
    FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger_func();

-- Cross-Society and Status Isolation Trigger
CREATE OR REPLACE FUNCTION public.trg_validate_amc_isolation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_asset_society_id UUID;
    v_vendor_society_id UUID;
    v_vendor_status VARCHAR;
    v_asset_status VARCHAR;
BEGIN
    SELECT society_id, status INTO v_asset_society_id, v_asset_status
    FROM public.assets WHERE id = NEW.asset_id;

    SELECT society_id, status INTO v_vendor_society_id, v_vendor_status
    FROM public.vendors WHERE id = NEW.vendor_id;

    IF v_asset_society_id <> NEW.society_id THEN
        RAISE EXCEPTION 'Asset does not belong to the AMC society';
    END IF;

    IF v_vendor_society_id <> NEW.society_id THEN
        RAISE EXCEPTION 'Vendor does not belong to the AMC society';
    END IF;

    IF v_asset_status = 'retired' THEN
        RAISE EXCEPTION 'Cannot create AMC for retired asset';
    END IF;

    IF v_vendor_status = 'inactive' THEN
        RAISE EXCEPTION 'Cannot create AMC with inactive vendor';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_amc_isolation
    BEFORE INSERT OR UPDATE ON public.asset_amc
    FOR EACH ROW EXECUTE FUNCTION public.trg_validate_amc_isolation();

-- ===========================================================================
-- STEP 7 — EXPENSE VOUCHER INTEGRATION
-- ===========================================================================

-- Allow vendor_id to be NULL to maintain slice 4 backward compatibility
ALTER TABLE public.expense_vouchers 
    ADD COLUMN vendor_id UUID REFERENCES public.vendors(id) ON DELETE RESTRICT;

CREATE OR REPLACE FUNCTION public.trg_validate_voucher_vendor_isolation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_vendor_society_id UUID;
    v_vendor_status VARCHAR;
BEGIN
    IF NEW.vendor_id IS NOT NULL THEN
        SELECT society_id, status INTO v_vendor_society_id, v_vendor_status
        FROM public.vendors WHERE id = NEW.vendor_id;

        IF v_vendor_society_id <> NEW.society_id THEN
            RAISE EXCEPTION 'Vendor society_id must match voucher society_id';
        END IF;

        IF TG_OP = 'INSERT' AND v_vendor_status = 'inactive' THEN
            RAISE EXCEPTION 'Cannot link voucher to an inactive vendor';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_voucher_vendor_isolation
    BEFORE INSERT OR UPDATE ON public.expense_vouchers
    FOR EACH ROW EXECUTE FUNCTION public.trg_validate_voucher_vendor_isolation();


-- ===========================================================================
-- STEP 8 — TECHNICIAN TICKET INTEGRATION
-- ===========================================================================

-- Allow asset_id to be NULL to maintain slice 3/6 backward compatibility
ALTER TABLE public.technician_tickets 
    ADD COLUMN asset_id UUID REFERENCES public.assets(id) ON DELETE RESTRICT;

CREATE OR REPLACE FUNCTION public.trg_validate_ticket_asset_isolation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_asset_society_id UUID;
    v_asset_status VARCHAR;
BEGIN
    IF NEW.asset_id IS NOT NULL THEN
        SELECT society_id, status INTO v_asset_society_id, v_asset_status
        FROM public.assets WHERE id = NEW.asset_id;

        IF v_asset_society_id <> NEW.society_id THEN
            RAISE EXCEPTION 'Asset society_id must match ticket society_id';
        END IF;

        IF TG_OP = 'INSERT' AND v_asset_status = 'retired' THEN
            RAISE EXCEPTION 'Cannot link new ticket to a retired asset';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_ticket_asset_isolation
    BEFORE INSERT OR UPDATE ON public.technician_tickets
    FOR EACH ROW EXECUTE FUNCTION public.trg_validate_ticket_asset_isolation();

-- Secure function to link asset to ticket
CREATE OR REPLACE FUNCTION public.fn_assign_ticket_asset(
    p_ticket_id UUID,
    p_asset_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_society_id UUID;
    v_ticket_society_id UUID;
    v_asset_society_id UUID;
    v_asset_status VARCHAR;
BEGIN
    -- Authorization: Admin or Technician
    IF NOT (public.is_admin() OR public.has_role(auth.uid(), 'technician')) THEN
        RAISE EXCEPTION 'Access Denied: Must be Admin or Technician to assign assets';
    END IF;

    SELECT society_id INTO v_ticket_society_id FROM public.technician_tickets WHERE id = p_ticket_id;
    SELECT society_id, status INTO v_asset_society_id, v_asset_status FROM public.assets WHERE id = p_asset_id;

    IF v_ticket_society_id IS NULL THEN RAISE EXCEPTION 'Ticket not found'; END IF;
    IF v_asset_society_id IS NULL THEN RAISE EXCEPTION 'Asset not found'; END IF;

    v_society_id := public.get_user_society_id();

    IF v_ticket_society_id <> v_society_id OR v_asset_society_id <> v_society_id THEN
        RAISE EXCEPTION 'Cross-society access denied';
    END IF;

    IF v_asset_status = 'retired' THEN
        RAISE EXCEPTION 'Cannot assign retired asset to ticket';
    END IF;

    UPDATE public.technician_tickets
    SET asset_id = p_asset_id
    WHERE id = p_ticket_id;
END;
$$;

-- ===========================================================================
-- STEP 9 — INDEXES
-- ===========================================================================

CREATE INDEX idx_vendors_society_id ON public.vendors(society_id);
CREATE INDEX idx_assets_society_id ON public.assets(society_id);
CREATE INDEX idx_asset_amc_asset_id ON public.asset_amc(asset_id);
CREATE INDEX idx_vouchers_vendor_id ON public.expense_vouchers(vendor_id);
CREATE INDEX idx_tickets_asset_id ON public.technician_tickets(asset_id);

-- ===========================================================================
-- STEP 10 — RLS POLICIES & GRANTS
-- ===========================================================================

GRANT ALL ON public.vendors TO authenticated;
GRANT ALL ON public.vendor_bank_details TO authenticated;
GRANT ALL ON public.assets TO authenticated;
GRANT ALL ON public.asset_amc TO authenticated;

ALTER TABLE public.vendors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vendor_bank_details ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.asset_amc ENABLE ROW LEVEL SECURITY;

-- vendors
CREATE POLICY "Admins have full access to vendors"
    ON public.vendors
    FOR ALL
    USING (public.is_admin() AND society_id = public.get_user_society_id());

CREATE POLICY "Members can view vendors"
    ON public.vendors
    FOR SELECT
    USING (society_id = public.get_user_society_id());

-- vendor_bank_details
CREATE POLICY "Admins have full access to vendor bank details"
    ON public.vendor_bank_details
    FOR ALL
    USING (public.is_admin() AND society_id = public.get_user_society_id());

-- assets
CREATE POLICY "Admins have full access to assets"
    ON public.assets
    FOR ALL
    USING (public.is_admin() AND society_id = public.get_user_society_id());

CREATE POLICY "Members and techs can view assets"
    ON public.assets
    FOR SELECT
    USING (society_id = public.get_user_society_id());

-- asset_amc
CREATE POLICY "Admins have full access to AMCs"
    ON public.asset_amc
    FOR ALL
    USING (public.is_admin() AND society_id = public.get_user_society_id());

COMMIT;
