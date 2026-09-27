-- ============================================================================
-- SU SOCIETY APP — SLICE 21 SCHEMA DEFINITION
-- Security Gate Emergency Blacklist, Gate Access Denial & Asset/Vendor AMC System
-- Revision 10.1 Authoritative Specification
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. CANONICALIZATION & VALIDATION FUNCTIONS (IMMUTABLE / STABLE)
-- ----------------------------------------------------------------------------

-- Canonicalize Identity Number (CNIC / Passport / License / VIN)
CREATE OR REPLACE FUNCTION public.fn_canonicalize_cnic_passport(p_input TEXT)
RETURNS VARCHAR
LANGUAGE plpgsql
IMMUTABLE
SET search_path = pg_catalog, public
AS $$
BEGIN
    IF p_input IS NULL THEN
        RETURN NULL;
    END IF;
    -- Remove non-alphanumeric characters and convert to uppercase
    RETURN upper(regexp_replace(p_input, '[^a-zA-Z0-9]', '', 'g'));
END;
$$;

-- Canonicalize Phone Number (E.164 format digits)
CREATE OR REPLACE FUNCTION public.fn_canonicalize_phone(p_input TEXT)
RETURNS VARCHAR
LANGUAGE plpgsql
IMMUTABLE
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_cleaned TEXT;
BEGIN
    IF p_input IS NULL THEN
        RETURN NULL;
    END IF;
    -- Retain numeric digits
    v_cleaned := regexp_replace(p_input, '[^0-9]', '', 'g');
    IF length(v_cleaned) = 0 THEN
        RETURN NULL;
    END IF;
    IF length(v_cleaned) = 10 THEN
        RETURN '92' || v_cleaned; -- Standardize 10-digit to Pakistan E.164 country code if applicable or keep digits
    END IF;
    RETURN v_cleaned;
END;
$$;

-- Validate Structured JSONB Denial Details
CREATE OR REPLACE FUNCTION public.fn_is_valid_denial_details(p_details JSONB)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_key TEXT;
    v_allowed_keys TEXT[] := ARRAY['attempted_entry_type', 'decision_source', 'normalized_subject_type', 'gate_identifier', 'correlation_id'];
BEGIN
    IF p_details IS NULL OR jsonb_typeof(p_details) <> 'object' THEN
        RETURN FALSE;
    END IF;
    IF pg_column_size(p_details) > 1024 THEN
        RETURN FALSE;
    END IF;
    FOR v_key IN SELECT jsonb_object_keys(p_details) LOOP
        IF NOT (v_key = ANY(v_allowed_keys)) THEN
            RETURN FALSE;
        END IF;
        IF jsonb_typeof(p_details -> v_key) IN ('object', 'array') THEN
            RETURN FALSE;
        END IF;
    END LOOP;
    RETURN TRUE;
END;
$$;

-- ----------------------------------------------------------------------------
-- 2. TABLES & STRUCTURES
-- ----------------------------------------------------------------------------

-- 1. Security Blacklist Records Table
CREATE TABLE IF NOT EXISTS public.security_blacklist_records (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    society_id UUID NOT NULL REFERENCES public.societies(id),
    identity_number_raw VARCHAR(100),
    identity_number_canonical VARCHAR(100),
    phone_raw VARCHAR(50),
    phone_canonical VARCHAR(50),
    reason TEXT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'deactivated')),
    created_by UUID NOT NULL REFERENCES auth.users(id),
    deactivated_by UUID REFERENCES auth.users(id),
    deactivated_at TIMESTAMPTZ,
    deactivation_reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (identity_number_canonical IS NOT NULL OR phone_canonical IS NOT NULL)
);

-- 2. Vendor Rate Limits Table (Model B: Composite Primary Key)
CREATE TABLE IF NOT EXISTS public.vendor_rate_limits (
    society_id UUID NOT NULL REFERENCES public.societies(id),
    gatekeeper_id UUID NOT NULL REFERENCES auth.users(id),
    failure_count INT NOT NULL DEFAULT 0 CHECK (failure_count >= 0),
    first_failure_at TIMESTAMPTZ,
    lockout_until TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (society_id, gatekeeper_id)
);

-- 3. Security Denial Logs Table
CREATE TABLE IF NOT EXISTS public.security_denial_logs (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    society_id UUID NOT NULL REFERENCES public.societies(id),
    gatekeeper_id UUID NOT NULL REFERENCES auth.users(id),
    entry_type VARCHAR(50) NOT NULL CHECK (entry_type IN ('visitor', 'vendor_technician', 'delivery', 'cab', 'resident_vehicle', 'other')),
    denial_reason VARCHAR(100) NOT NULL,
    denial_details JSONB NOT NULL DEFAULT '{}'::jsonb,
    attempted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (public.fn_is_valid_denial_details(denial_details))
);

-- 4. Society Assets Table
CREATE TABLE IF NOT EXISTS public.society_assets (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    society_id UUID NOT NULL REFERENCES public.societies(id),
    asset_name VARCHAR(150) NOT NULL,
    asset_code VARCHAR(50) NOT NULL,
    category VARCHAR(50) NOT NULL CHECK (category IN ('lift', 'generator', 'transformer', 'water_pump', 'cctv_system', 'fire_system', 'intercom', 'solar_plant', 'gym_equipment', 'pool_filter', 'other')),
    location_description TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_by UUID NOT NULL REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (society_id, asset_code)
);

-- 5. AMC Vendor Contracts Table
CREATE TABLE IF NOT EXISTS public.amc_vendor_contracts (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    society_id UUID NOT NULL REFERENCES public.societies(id),
    asset_id UUID NOT NULL REFERENCES public.society_assets(id),
    vendor_name VARCHAR(150) NOT NULL,
    vendor_code VARCHAR(50) NOT NULL,
    contract_number VARCHAR(100) NOT NULL,
    contact_email VARCHAR(150),
    contact_phone VARCHAR(50),
    contract_start DATE NOT NULL,
    contract_end DATE NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'expired', 'terminated')),
    terminated_at TIMESTAMPTZ,
    terminated_by UUID REFERENCES auth.users(id),
    termination_reason TEXT,
    created_by UUID NOT NULL REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (contract_start <= contract_end)
);

-- 6. Vendor Access Passes Table
CREATE TABLE IF NOT EXISTS public.vendor_access_passes (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    society_id UUID NOT NULL REFERENCES public.societies(id),
    amc_contract_id UUID NOT NULL REFERENCES public.amc_vendor_contracts(id),
    pass_token_digest VARCHAR(64) NOT NULL UNIQUE,
    technician_name VARCHAR(150) NOT NULL,
    technician_identity_raw VARCHAR(100),
    technician_identity_canonical VARCHAR(100),
    technician_phone_raw VARCHAR(50),
    technician_phone_canonical VARCHAR(50),
    status VARCHAR(20) NOT NULL DEFAULT 'issued' CHECK (status IN ('issued', 'used', 'revoked', 'expired', 'cancelled')),
    valid_from TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    valid_until TIMESTAMPTZ NOT NULL,
    redeemed_at TIMESTAMPTZ,
    redeemed_by_gatekeeper_id UUID REFERENCES auth.users(id),
    revoked_at TIMESTAMPTZ,
    revoked_by UUID REFERENCES auth.users(id),
    revocation_reason TEXT,
    issued_by UUID NOT NULL REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (valid_from < valid_until)
);

-- ----------------------------------------------------------------------------
-- 3. INDEXES & VIEWS
-- ----------------------------------------------------------------------------

-- Partial Unique Indexes for Blacklist Active Entries
CREATE UNIQUE INDEX IF NOT EXISTS uq_active_blacklist_identity
ON public.security_blacklist_records(society_id, identity_number_canonical)
WHERE status = 'active' AND identity_number_canonical IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_active_blacklist_phone
ON public.security_blacklist_records(society_id, phone_canonical)
WHERE status = 'active' AND phone_canonical IS NOT NULL;

-- General Query Indexes
CREATE INDEX IF NOT EXISTS idx_blacklist_society ON public.security_blacklist_records(society_id);
CREATE INDEX IF NOT EXISTS idx_blacklist_status ON public.security_blacklist_records(status);
CREATE INDEX IF NOT EXISTS idx_denial_logs_society ON public.security_denial_logs(society_id);
CREATE INDEX IF NOT EXISTS idx_denial_logs_gatekeeper ON public.security_denial_logs(gatekeeper_id);
CREATE INDEX IF NOT EXISTS idx_society_assets_society ON public.society_assets(society_id);
CREATE INDEX IF NOT EXISTS idx_amc_contracts_society ON public.amc_vendor_contracts(society_id);
CREATE INDEX IF NOT EXISTS idx_amc_contracts_asset ON public.amc_vendor_contracts(asset_id);
CREATE INDEX IF NOT EXISTS idx_vendor_passes_society ON public.vendor_access_passes(society_id);
CREATE INDEX IF NOT EXISTS idx_vendor_passes_amc ON public.vendor_access_passes(amc_contract_id);
CREATE INDEX IF NOT EXISTS idx_vendor_passes_digest ON public.vendor_access_passes(pass_token_digest);

-- View for Resident Data Minimization (Masking Email & Phone)
CREATE OR REPLACE VIEW public.v_resident_amc_contracts AS
SELECT 
    c.id,
    c.society_id,
    c.asset_id,
    a.asset_name,
    a.asset_code,
    c.vendor_name,
    c.vendor_code,
    c.contract_number,
    c.contract_start,
    c.contract_end,
    c.status,
    c.created_at
FROM public.amc_vendor_contracts c
JOIN public.society_assets a ON a.id = c.asset_id;

-- ----------------------------------------------------------------------------
-- 4. ROW LEVEL SECURITY (RLS) & PRIVILEGES
-- ----------------------------------------------------------------------------

ALTER TABLE public.security_blacklist_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.security_blacklist_records FORCE ROW LEVEL SECURITY;

ALTER TABLE public.vendor_rate_limits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vendor_rate_limits FORCE ROW LEVEL SECURITY;

ALTER TABLE public.security_denial_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.security_denial_logs FORCE ROW LEVEL SECURITY;

ALTER TABLE public.society_assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.society_assets FORCE ROW LEVEL SECURITY;

ALTER TABLE public.amc_vendor_contracts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.amc_vendor_contracts FORCE ROW LEVEL SECURITY;

ALTER TABLE public.vendor_access_passes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vendor_access_passes FORCE ROW LEVEL SECURITY;

-- Revoke direct DML from authenticated, anon, gatekeeper
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.security_blacklist_records FROM authenticated, anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.vendor_rate_limits FROM authenticated, anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.security_denial_logs FROM authenticated, anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.society_assets FROM authenticated, anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.amc_vendor_contracts FROM authenticated, anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.vendor_access_passes FROM authenticated, anon;

-- Grant SELECT to authenticated
GRANT SELECT ON public.security_blacklist_records TO authenticated;
GRANT SELECT ON public.vendor_rate_limits TO authenticated;
GRANT SELECT ON public.security_denial_logs TO authenticated;
GRANT SELECT ON public.society_assets TO authenticated;
GRANT SELECT ON public.amc_vendor_contracts TO authenticated;
GRANT SELECT ON public.vendor_access_passes TO authenticated;
GRANT SELECT ON public.v_resident_amc_contracts TO authenticated;

-- RLS Policies
CREATE POLICY blacklist_select_policy ON public.security_blacklist_records
    FOR SELECT TO authenticated
    USING (public.is_admin() OR public.has_role(auth.uid(), 'gatekeeper'));

CREATE POLICY rate_limits_select_policy ON public.vendor_rate_limits
    FOR SELECT TO authenticated
    USING (gatekeeper_id = auth.uid() OR public.is_admin());

CREATE POLICY denial_logs_select_policy ON public.security_denial_logs
    FOR SELECT TO authenticated
    USING (public.is_admin());

CREATE POLICY assets_select_policy ON public.society_assets
    FOR SELECT TO authenticated
    USING (TRUE);

CREATE POLICY amc_contracts_select_policy ON public.amc_vendor_contracts
    FOR SELECT TO authenticated
    USING (public.is_admin() OR public.has_role(auth.uid(), 'gatekeeper'));

CREATE POLICY vendor_passes_select_policy ON public.vendor_access_passes
    FOR SELECT TO authenticated
    USING (public.is_admin() OR public.has_role(auth.uid(), 'gatekeeper') OR issued_by = auth.uid());

-- ----------------------------------------------------------------------------
-- 5. AUTOMATIC TRIGGER FOR AMC CONTRACT SHORTENING / TERMINATION
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_trg_amc_shorten_update_passes()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_new_end_boundary TIMESTAMPTZ;
BEGIN
    IF (OLD.status = 'active' AND NEW.status IN ('expired', 'terminated')) OR (OLD.contract_end <> NEW.contract_end) THEN
        IF NEW.status = 'terminated' THEN
            v_new_end_boundary := COALESCE(NEW.terminated_at, NOW());
        ELSE
            v_new_end_boundary := (NEW.contract_end + INTERVAL '1 day' - INTERVAL '1 microsecond')::TIMESTAMPTZ;
        END IF;

        -- Safe Pass Shortening:
        -- 1. Cancel passes whose valid_from is >= new boundary
        UPDATE public.vendor_access_passes
        SET status = 'cancelled', updated_at = NOW()
        WHERE amc_contract_id = NEW.id AND status = 'issued' AND valid_from >= v_new_end_boundary;

        -- 2. Shorten valid_until for passes whose valid_from < new boundary
        UPDATE public.vendor_access_passes
        SET valid_until = v_new_end_boundary, updated_at = NOW()
        WHERE amc_contract_id = NEW.id AND status = 'issued' AND valid_from < v_new_end_boundary AND valid_until > v_new_end_boundary;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_amc_shorten_update_passes ON public.amc_vendor_contracts;
CREATE TRIGGER trg_amc_shorten_update_passes
AFTER UPDATE ON public.amc_vendor_contracts
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_amc_shorten_update_passes();

-- ----------------------------------------------------------------------------
-- 6. HARDENED SECURITY DEFINER RPC ROUTINES (SET search_path = pg_catalog, public;)
-- ----------------------------------------------------------------------------

-- RPC 1: fn_create_blacklist_entry
CREATE OR REPLACE FUNCTION public.fn_create_blacklist_entry(
    p_identity_number VARCHAR DEFAULT NULL,
    p_phone VARCHAR DEFAULT NULL,
    p_reason TEXT DEFAULT 'Security concern'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_caller_id UUID;
    v_society_id UUID;
    v_ident_canon VARCHAR;
    v_phone_canon VARCHAR;
    v_id UUID;
    v_res JSONB;
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Admin authorization required.' USING ERRCODE = '42501';
    END IF;

    v_ident_canon := public.fn_canonicalize_cnic_passport(p_identity_number);
    v_phone_canon := public.fn_canonicalize_phone(p_phone);

    IF v_ident_canon IS NULL AND v_phone_canon IS NULL THEN
        RAISE EXCEPTION 'At least one valid identity number or phone number is required.' USING ERRCODE = '22000';
    END IF;

    SELECT society_id INTO v_society_id
    FROM public.user_roles
    WHERE user_id = v_caller_id AND role_name = 'admin' LIMIT 1;

    IF v_society_id IS NULL THEN
        SELECT id INTO v_society_id FROM public.societies WHERE is_active = true LIMIT 1;
    END IF;

    -- Lock Society Scope [Rank 1 Lock]
    PERFORM 1 FROM public.societies WHERE id = v_society_id FOR SHARE;

    INSERT INTO public.security_blacklist_records (
        society_id, identity_number_raw, identity_number_canonical,
        phone_raw, phone_canonical, reason, status, created_by
    ) VALUES (
        v_society_id, p_identity_number, v_ident_canon,
        p_phone, v_phone_canon, p_reason, 'active', v_caller_id
    ) RETURNING id INTO v_id;

    SELECT jsonb_build_object(
        'success', true,
        'id', id,
        'society_id', society_id,
        'identity_canonical', identity_number_canonical,
        'phone_canonical', phone_canonical,
        'status', status
    ) INTO v_res FROM public.security_blacklist_records WHERE id = v_id;

    RETURN v_res;
END;
$$;

-- RPC 2: fn_deactivate_blacklist_entry
CREATE OR REPLACE FUNCTION public.fn_deactivate_blacklist_entry(
    p_blacklist_id UUID,
    p_reason TEXT DEFAULT 'Deactivated by admin'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_caller_id UUID;
    v_rec RECORD;
    v_res JSONB;
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL OR NOT public.is_admin() THEN
        RAISE EXCEPTION 'Admin authorization required.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_rec FROM public.security_blacklist_records WHERE id = p_blacklist_id FOR UPDATE;

    IF v_rec.id IS NULL THEN
        RAISE EXCEPTION 'Blacklist record not found.' USING ERRCODE = 'P0002';
    END IF;

    IF v_rec.status = 'deactivated' THEN
        RAISE EXCEPTION 'Blacklist record already deactivated.' USING ERRCODE = '22000';
    END IF;

    UPDATE public.security_blacklist_records
    SET status = 'deactivated', deactivated_by = v_caller_id, deactivated_at = NOW(), deactivation_reason = p_reason, updated_at = NOW()
    WHERE id = p_blacklist_id;

    SELECT jsonb_build_object(
        'success', true,
        'id', id,
        'status', status,
        'deactivated_at', NOW()
    ) INTO v_res FROM public.security_blacklist_records WHERE id = p_blacklist_id;

    RETURN v_res;
END;
$$;

-- RPC 3: fn_evaluate_access_denial
CREATE OR REPLACE FUNCTION public.fn_evaluate_access_denial(
    p_entry_type VARCHAR,
    p_identity_number VARCHAR DEFAULT NULL,
    p_phone VARCHAR DEFAULT NULL,
    p_details JSONB DEFAULT '{}'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_caller_id UUID;
    v_society_id UUID;
    v_ident_canon VARCHAR;
    v_phone_canon VARCHAR;
    v_blacklist_match RECORD;
    v_rate_limit RECORD;
    v_denial_id UUID;
    v_is_denied BOOLEAN := FALSE;
    v_reason VARCHAR := 'none';
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    SELECT society_id INTO v_society_id
    FROM public.user_roles
    WHERE user_id = v_caller_id AND role_name IN ('gatekeeper', 'admin') LIMIT 1;

    IF v_society_id IS NULL THEN
        SELECT id INTO v_society_id FROM public.societies WHERE is_active = true LIMIT 1;
    END IF;

    -- Lock Society Scope [Rank 1 Lock]
    PERFORM 1 FROM public.societies WHERE id = v_society_id FOR SHARE;

    -- Atomic Rate Limit Lockout Check [Rank 2 Lock]
    INSERT INTO public.vendor_rate_limits (society_id, gatekeeper_id, failure_count)
    VALUES (v_society_id, v_caller_id, 0)
    ON CONFLICT (society_id, gatekeeper_id) DO NOTHING;

    SELECT * INTO v_rate_limit
    FROM public.vendor_rate_limits
    WHERE society_id = v_society_id AND gatekeeper_id = v_caller_id FOR UPDATE;

    IF v_rate_limit.lockout_until IS NOT NULL AND v_rate_limit.lockout_until > NOW() THEN
        INSERT INTO public.security_denial_logs (society_id, gatekeeper_id, entry_type, denial_reason, denial_details)
        VALUES (v_society_id, v_caller_id, p_entry_type, 'rate_limit_lockout', jsonb_build_object('attempted_entry_type', p_entry_type, 'decision_source', 'gatekeeper_rate_limit'));
        RETURN jsonb_build_object('success', false, 'access_granted', false, 'denial_reason', 'rate_limit_lockout', 'lockout_until', v_rate_limit.lockout_until);
    END IF;

    v_ident_canon := public.fn_canonicalize_cnic_passport(p_identity_number);
    v_phone_canon := public.fn_canonicalize_phone(p_phone);

    -- Ordinary Non-Locking SELECT on Blacklist Records [Rank 3 Read]
    SELECT * INTO v_blacklist_match
    FROM public.security_blacklist_records
    WHERE society_id = v_society_id AND status = 'active'
      AND ((v_ident_canon IS NOT NULL AND identity_number_canonical = v_ident_canon)
        OR (v_phone_canon IS NOT NULL AND phone_canonical = v_phone_canon))
    LIMIT 1;

    IF v_blacklist_match.id IS NOT NULL THEN
        v_is_denied := TRUE;
        v_reason := 'blacklist_match';
    END IF;

    IF v_is_denied THEN
        INSERT INTO public.security_denial_logs (society_id, gatekeeper_id, entry_type, denial_reason, denial_details)
        VALUES (v_society_id, v_caller_id, p_entry_type, v_reason, jsonb_build_object('attempted_entry_type', p_entry_type, 'decision_source', 'security_blacklist'))
        RETURNING id INTO v_denial_id;

        RETURN jsonb_build_object('success', false, 'access_granted', false, 'denial_reason', v_reason, 'denial_id', v_denial_id);
    END IF;

    RETURN jsonb_build_object('success', true, 'access_granted', true);
END;
$$;

-- RPC 4: fn_register_society_asset
CREATE OR REPLACE FUNCTION public.fn_register_society_asset(
    p_asset_name VARCHAR,
    p_asset_code VARCHAR,
    p_category VARCHAR,
    p_location_description TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_caller_id UUID;
    v_society_id UUID;
    v_id UUID;
    v_res JSONB;
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL OR NOT public.is_admin() THEN
        RAISE EXCEPTION 'Admin authorization required.' USING ERRCODE = '42501';
    END IF;

    SELECT society_id INTO v_society_id
    FROM public.user_roles
    WHERE user_id = v_caller_id AND role_name = 'admin' LIMIT 1;

    IF v_society_id IS NULL THEN
        SELECT id INTO v_society_id FROM public.societies WHERE is_active = true LIMIT 1;
    END IF;

    -- Lock Society Scope [Rank 1 Lock]
    PERFORM 1 FROM public.societies WHERE id = v_society_id FOR SHARE;

    INSERT INTO public.society_assets (society_id, asset_name, asset_code, category, location_description, created_by)
    VALUES (v_society_id, p_asset_name, p_asset_code, p_category, p_location_description, v_caller_id)
    RETURNING id INTO v_id;

    SELECT jsonb_build_object('success', true, 'id', id, 'asset_code', asset_code, 'asset_name', asset_name)
    INTO v_res FROM public.society_assets WHERE id = v_id;

    RETURN v_res;
END;
$$;

-- RPC 5: fn_create_amc_contract
CREATE OR REPLACE FUNCTION public.fn_create_amc_contract(
    p_asset_id UUID,
    p_vendor_name VARCHAR,
    p_vendor_code VARCHAR,
    p_contract_number VARCHAR,
    p_contract_start DATE,
    p_contract_end DATE,
    p_contact_email VARCHAR DEFAULT NULL,
    p_contact_phone VARCHAR DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_caller_id UUID;
    v_society_id UUID;
    v_id UUID;
    v_res JSONB;
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL OR NOT public.is_admin() THEN
        RAISE EXCEPTION 'Admin authorization required.' USING ERRCODE = '42501';
    END IF;

    SELECT society_id INTO v_society_id FROM public.society_assets WHERE id = p_asset_id;
    IF v_society_id IS NULL THEN
        RAISE EXCEPTION 'Society asset not found.' USING ERRCODE = 'P0002';
    END IF;

    -- Lock Society Scope [Rank 1 Lock]
    PERFORM 1 FROM public.societies WHERE id = v_society_id FOR SHARE;
    -- Lock Asset Scope [Rank 4 Lock]
    PERFORM 1 FROM public.society_assets WHERE id = p_asset_id FOR SHARE;

    INSERT INTO public.amc_vendor_contracts (
        society_id, asset_id, vendor_name, vendor_code, contract_number,
        contract_start, contract_end, contact_email, contact_phone, created_by
    ) VALUES (
        v_society_id, p_asset_id, p_vendor_name, p_vendor_code, p_contract_number,
        p_contract_start, p_contract_end, p_contact_email, p_contact_phone, v_caller_id
    ) RETURNING id INTO v_id;

    SELECT jsonb_build_object('success', true, 'id', id, 'contract_number', contract_number, 'status', status)
    INTO v_res FROM public.amc_vendor_contracts WHERE id = v_id;

    RETURN v_res;
END;
$$;

-- RPC 6: fn_terminate_amc_contract
CREATE OR REPLACE FUNCTION public.fn_terminate_amc_contract(
    p_contract_id UUID,
    p_reason TEXT DEFAULT 'Terminated by admin'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_caller_id UUID;
    v_rec RECORD;
    v_res JSONB;
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL OR NOT public.is_admin() THEN
        RAISE EXCEPTION 'Admin authorization required.' USING ERRCODE = '42501';
    END IF;

    -- Lock AMC Contract [Rank 5 Lock]
    SELECT * INTO v_rec FROM public.amc_vendor_contracts WHERE id = p_contract_id FOR UPDATE;
    IF v_rec.id IS NULL THEN
        RAISE EXCEPTION 'AMC contract not found.' USING ERRCODE = 'P0002';
    END IF;

    IF v_rec.status <> 'active' THEN
        RAISE EXCEPTION 'Cannot terminate contract in status: %', v_rec.status USING ERRCODE = '22000';
    END IF;

    -- Lock Society Scope [Rank 1 Lock]
    PERFORM 1 FROM public.societies WHERE id = v_rec.society_id FOR SHARE;

    UPDATE public.amc_vendor_contracts
    SET status = 'terminated', terminated_at = NOW(), terminated_by = v_caller_id, termination_reason = p_reason, updated_at = NOW()
    WHERE id = p_contract_id;

    -- Trigger trg_amc_shorten_update_passes automatically executes here to update vendor_access_passes [Rank 6 Lock]

    SELECT jsonb_build_object('success', true, 'id', id, 'status', status, 'terminated_at', NOW())
    INTO v_res FROM public.amc_vendor_contracts WHERE id = p_contract_id;

    RETURN v_res;
END;
$$;

-- RPC 7: fn_issue_vendor_pass
CREATE OR REPLACE FUNCTION public.fn_issue_vendor_pass(
    p_amc_contract_id UUID,
    p_technician_name VARCHAR,
    p_identity_number VARCHAR,
    p_phone VARCHAR,
    p_valid_from TIMESTAMPTZ,
    p_valid_until TIMESTAMPTZ
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_caller_id UUID;
    v_amc RECORD;
    v_raw_token VARCHAR;
    v_digest VARCHAR;
    v_ident_canon VARCHAR;
    v_phone_canon VARCHAR;
    v_id UUID;
    v_res JSONB;
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL OR NOT public.is_admin() THEN
        RAISE EXCEPTION 'Admin authorization required.' USING ERRCODE = '42501';
    END IF;

    IF p_valid_from >= p_valid_until THEN
        RAISE EXCEPTION 'valid_from must be before valid_until.' USING ERRCODE = '22000';
    END IF;

    -- Lock AMC Contract [Rank 5 Lock]
    SELECT * INTO v_amc FROM public.amc_vendor_contracts WHERE id = p_amc_contract_id FOR SHARE;
    IF v_amc.id IS NULL THEN
        RAISE EXCEPTION 'AMC contract not found.' USING ERRCODE = 'P0002';
    END IF;

    IF v_amc.status <> 'active' THEN
        RAISE EXCEPTION 'Cannot issue pass for non-active AMC contract.' USING ERRCODE = '22000';
    END IF;

    -- Validate pass dates are within contract bounds
    IF p_valid_from::date < v_amc.contract_start OR p_valid_until::date > v_amc.contract_end THEN
        RAISE EXCEPTION 'Pass validity dates outside AMC contract duration.' USING ERRCODE = '22000';
    END IF;

    v_ident_canon := public.fn_canonicalize_cnic_passport(p_identity_number);
    v_phone_canon := public.fn_canonicalize_phone(p_phone);

    -- Generate raw token (41-char: VND-PASS- + 32 HEX)
    v_raw_token := 'VND-PASS-' || upper(encode(extensions.gen_random_bytes(16), 'hex'));
    v_digest := encode(extensions.digest(v_raw_token, 'sha256'), 'hex');

    INSERT INTO public.vendor_access_passes (
        society_id, amc_contract_id, pass_token_digest, technician_name,
        technician_identity_raw, technician_identity_canonical,
        technician_phone_raw, technician_phone_canonical, status,
        valid_from, valid_until, issued_by
    ) VALUES (
        v_amc.society_id, p_amc_contract_id, v_digest, p_technician_name,
        p_identity_number, v_ident_canon,
        p_phone, v_phone_canon, 'issued',
        p_valid_from, p_valid_until, v_caller_id
    ) RETURNING id INTO v_id;

    RETURN jsonb_build_object(
        'success', true,
        'pass_id', v_id,
        'raw_pass_token', v_raw_token,
        'valid_from', p_valid_from,
        'valid_until', p_valid_until
    );
END;
$$;

-- RPC 8: fn_revoke_vendor_pass
CREATE OR REPLACE FUNCTION public.fn_revoke_vendor_pass(
    p_pass_id UUID,
    p_reason TEXT DEFAULT 'Revoked by admin'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_caller_id UUID;
    v_pass RECORD;
    v_res JSONB;
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL OR NOT public.is_admin() THEN
        RAISE EXCEPTION 'Admin authorization required.' USING ERRCODE = '42501';
    END IF;

    -- Lock Pass Row [Rank 6 Lock]
    SELECT * INTO v_pass FROM public.vendor_access_passes WHERE id = p_pass_id FOR UPDATE;
    IF v_pass.id IS NULL THEN
        RAISE EXCEPTION 'Vendor access pass not found.' USING ERRCODE = 'P0002';
    END IF;

    IF v_pass.status <> 'issued' THEN
        RAISE EXCEPTION 'Cannot revoke pass in status: %', v_pass.status USING ERRCODE = '22000';
    END IF;

    UPDATE public.vendor_access_passes
    SET status = 'revoked', revoked_at = NOW(), revoked_by = v_caller_id, revocation_reason = p_reason, updated_at = NOW()
    WHERE id = p_pass_id;

    RETURN jsonb_build_object('success', true, 'id', p_pass_id, 'status', 'revoked');
END;
$$;

-- RPC 9: fn_verify_vendor_pass (Reconciled Step 1..15 Sequence)
CREATE OR REPLACE FUNCTION public.fn_verify_vendor_pass(
    p_raw_token VARCHAR
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_caller_id UUID;
    v_society_id UUID;
    v_digest VARCHAR;
    v_rate_limit RECORD;
    v_prelim RECORD;
    v_blacklist_match RECORD;
    v_amc RECORD;
    v_pass RECORD;
    v_denial_id UUID;
BEGIN
    -- Step 1: Authenticate Caller
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    -- Step 2: Resolve Gatekeeper Society Context
    SELECT society_id INTO v_society_id
    FROM public.user_roles
    WHERE user_id = v_caller_id AND role_name IN ('gatekeeper', 'admin') LIMIT 1;

    IF v_society_id IS NULL THEN
        SELECT id INTO v_society_id FROM public.societies WHERE is_active = true LIMIT 1;
    END IF;

    -- Step 3: Lock Society Scope [Rank 1 Lock]
    PERFORM 1 FROM public.societies WHERE id = v_society_id FOR SHARE;

    -- Step 4: Atomic Rate Limit Row Lock [Rank 2 Lock]
    INSERT INTO public.vendor_rate_limits (society_id, gatekeeper_id, failure_count)
    VALUES (v_society_id, v_caller_id, 0)
    ON CONFLICT (society_id, gatekeeper_id) DO NOTHING;

    SELECT * INTO v_rate_limit
    FROM public.vendor_rate_limits
    WHERE society_id = v_society_id AND gatekeeper_id = v_caller_id FOR UPDATE;

    -- Step 5: Evaluate Rate Limit Lockout
    IF v_rate_limit.lockout_until IS NOT NULL AND v_rate_limit.lockout_until > NOW() THEN
        INSERT INTO public.security_denial_logs (society_id, gatekeeper_id, entry_type, denial_reason, denial_details)
        VALUES (v_society_id, v_caller_id, 'vendor_technician', 'rate_limit_lockout', jsonb_build_object('attempted_entry_type', 'vendor_technician', 'decision_source', 'gatekeeper_rate_limit'));
        RETURN jsonb_build_object('success', false, 'access_granted', false, 'denial_reason', 'rate_limit_lockout');
    END IF;

    -- Step 6: Validate Token Input Format (VND-PASS- + 32 HEX)
    IF p_raw_token IS NULL OR NOT (p_raw_token ~ '^VND-PASS-[A-FA-f0-9]{32}$') THEN
        UPDATE public.vendor_rate_limits
        SET failure_count = failure_count + 1,
            lockout_until = CASE WHEN failure_count + 1 >= 5 THEN NOW() + INTERVAL '15 minutes' ELSE lockout_until END,
            updated_at = NOW()
        WHERE society_id = v_society_id AND gatekeeper_id = v_caller_id;

        INSERT INTO public.security_denial_logs (society_id, gatekeeper_id, entry_type, denial_reason, denial_details)
        VALUES (v_society_id, v_caller_id, 'vendor_technician', 'invalid_token_format', jsonb_build_object('attempted_entry_type', 'vendor_technician', 'decision_source', 'token_format_check'));
        RETURN jsonb_build_object('success', false, 'access_granted', false, 'denial_reason', 'invalid_token_format');
    END IF;

    -- Step 7: Compute Token Digest
    v_digest := encode(extensions.digest(p_raw_token, 'sha256'), 'hex');

    -- Step 8: Preliminary Pass Lookup (Non-Locking Information Read)
    SELECT * INTO v_prelim FROM public.vendor_access_passes WHERE pass_token_digest = v_digest;
    IF v_prelim.id IS NULL THEN
        UPDATE public.vendor_rate_limits
        SET failure_count = failure_count + 1,
            lockout_until = CASE WHEN failure_count + 1 >= 5 THEN NOW() + INTERVAL '15 minutes' ELSE lockout_until END,
            updated_at = NOW()
        WHERE society_id = v_society_id AND gatekeeper_id = v_caller_id;

        INSERT INTO public.security_denial_logs (society_id, gatekeeper_id, entry_type, denial_reason, denial_details)
        VALUES (v_society_id, v_caller_id, 'vendor_technician', 'token_not_found', jsonb_build_object('attempted_entry_type', 'vendor_technician', 'decision_source', 'token_lookup'));
        RETURN jsonb_build_object('success', false, 'access_granted', false, 'denial_reason', 'token_not_found');
    END IF;

    -- Step 9: Preliminary Blacklist Read (Rank 3 Non-Locking Read)
    SELECT * INTO v_blacklist_match
    FROM public.security_blacklist_records
    WHERE society_id = v_society_id AND status = 'active'
      AND ((v_prelim.technician_identity_canonical IS NOT NULL AND identity_number_canonical = v_prelim.technician_identity_canonical)
        OR (v_prelim.technician_phone_canonical IS NOT NULL AND phone_canonical = v_prelim.technician_phone_canonical))
    LIMIT 1;

    IF v_blacklist_match.id IS NOT NULL THEN
        INSERT INTO public.security_denial_logs (society_id, gatekeeper_id, entry_type, denial_reason, denial_details)
        VALUES (v_society_id, v_caller_id, 'vendor_technician', 'blacklist_match', jsonb_build_object('attempted_entry_type', 'vendor_technician', 'decision_source', 'security_blacklist'));
        RETURN jsonb_build_object('success', false, 'access_granted', false, 'denial_reason', 'blacklist_match');
    END IF;

    -- Step 10: Asset Operational Read (Rank 4 Non-Locking Read)
    -- Step 11: Lock AMC Contract Row [Rank 5 Lock FOR SHARE]
    SELECT * INTO v_amc FROM public.amc_vendor_contracts WHERE id = v_prelim.amc_contract_id FOR SHARE;
    IF v_amc.id IS NULL OR v_amc.status <> 'active' OR CURRENT_DATE < v_amc.contract_start OR CURRENT_DATE > v_amc.contract_end THEN
        INSERT INTO public.security_denial_logs (society_id, gatekeeper_id, entry_type, denial_reason, denial_details)
        VALUES (v_society_id, v_caller_id, 'vendor_technician', 'amc_contract_inactive', jsonb_build_object('attempted_entry_type', 'vendor_technician', 'decision_source', 'amc_contract_check'));
        RETURN jsonb_build_object('success', false, 'access_granted', false, 'denial_reason', 'amc_contract_inactive');
    END IF;

    -- Step 12: Authoritative Pass Row Lock [Rank 6 Lock FOR UPDATE]
    SELECT * INTO v_pass FROM public.vendor_access_passes WHERE pass_token_digest = v_digest FOR UPDATE;

    -- Step 13a: Pass Attribute Revalidation Under Lock
    IF v_pass.status <> 'issued' OR NOW() < v_pass.valid_from OR NOW() > v_pass.valid_until THEN
        INSERT INTO public.security_denial_logs (society_id, gatekeeper_id, entry_type, denial_reason, denial_details)
        VALUES (v_society_id, v_caller_id, 'vendor_technician', 'pass_invalid_or_expired', jsonb_build_object('attempted_entry_type', 'vendor_technician', 'decision_source', 'pass_revalidation'));
        RETURN jsonb_build_object('success', false, 'access_granted', false, 'denial_reason', 'pass_invalid_or_expired');
    END IF;

    -- Step 13b: FINAL BLACKLIST AUTHORIZATION CHECK (INV-BL-01) - Fresh READ COMMITTED Snapshot Read
    SELECT * INTO v_blacklist_match
    FROM public.security_blacklist_records
    WHERE society_id = v_society_id AND status = 'active'
      AND ((v_pass.technician_identity_canonical IS NOT NULL AND identity_number_canonical = v_pass.technician_identity_canonical)
        OR (v_pass.technician_phone_canonical IS NOT NULL AND phone_canonical = v_pass.technician_phone_canonical))
    LIMIT 1;

    IF v_blacklist_match.id IS NOT NULL THEN
        INSERT INTO public.security_denial_logs (society_id, gatekeeper_id, entry_type, denial_reason, denial_details)
        VALUES (v_society_id, v_caller_id, 'vendor_technician', 'blacklist_match', jsonb_build_object('attempted_entry_type', 'vendor_technician', 'decision_source', 'security_blacklist_final'));
        RETURN jsonb_build_object('success', false, 'access_granted', false, 'denial_reason', 'blacklist_match');
    END IF;

    -- Step 13c: FINAL_AUTHORIZATION_POINT (All predicates passed)

    -- Reset rate limit failure count on successful authorization
    UPDATE public.vendor_rate_limits
    SET failure_count = 0, first_failure_at = NULL, lockout_until = NULL, updated_at = NOW()
    WHERE society_id = v_society_id AND gatekeeper_id = v_caller_id;

    -- Step 14: Execute Atomic Redemption Update (T_mutation)
    UPDATE public.vendor_access_passes
    SET status = 'used', redeemed_at = NOW(), redeemed_by_gatekeeper_id = v_caller_id, updated_at = NOW()
    WHERE id = v_pass.id;

    -- Step 15: Persist Log & Complete RPC (T_commit)
    INSERT INTO public.security_denial_logs (society_id, gatekeeper_id, entry_type, denial_reason, denial_details)
    VALUES (v_society_id, v_caller_id, 'vendor_technician', 'access_granted', jsonb_build_object('attempted_entry_type', 'vendor_technician', 'decision_source', 'redemption_success'));

    RETURN jsonb_build_object(
        'success', true,
        'access_granted', true,
        'pass_id', v_pass.id,
        'technician_name', v_pass.technician_name,
        'redeemed_at', NOW()
    );
END;
$$;

-- RPC 10: process_expired_amc_contracts
CREATE OR REPLACE FUNCTION public.process_expired_amc_contracts()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_count INT := 0;
BEGIN
    -- Update expired AMC contracts
    UPDATE public.amc_vendor_contracts
    SET status = 'expired', updated_at = NOW()
    WHERE status = 'active' AND contract_end < CURRENT_DATE;

    GET DIAGNOSTICS v_count = ROW_COUNT;

    -- Update expired vendor passes
    UPDATE public.vendor_access_passes
    SET status = 'expired', updated_at = NOW()
    WHERE status = 'issued' AND valid_until < NOW();

    RETURN v_count;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.process_expired_amc_contracts() FROM PUBLIC, authenticated, anon;

