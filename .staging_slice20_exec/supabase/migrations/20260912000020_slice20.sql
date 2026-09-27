-- ============================================================================
-- SU SOCIETY APP — SLICE 20 SCHEMA DEFINITION
-- NOC & Move-Out Management System (Rev 4.53 Authoritative Specification)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. TABLES & STRUCTURES
-- ----------------------------------------------------------------------------

-- NOC Requests Table
CREATE TABLE IF NOT EXISTS public.noc_requests (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    society_id UUID NOT NULL REFERENCES public.societies(id),
    property_id UUID NOT NULL REFERENCES public.properties(id),
    applicant_id UUID NOT NULL REFERENCES auth.users(id),
    noc_type VARCHAR(50) NOT NULL CHECK (noc_type IN ('tenant_move_out', 'owner_transfer')),
    status VARCHAR(50) NOT NULL DEFAULT 'draft' CHECK (status IN (
        'draft', 'submitted', 'under_review', 'approved', 'rejected',
        'move_pass_generated', 'transfer_pending', 'completed', 'revoked', 'cancelled', 'expired'
    )),
    target_user_id UUID REFERENCES auth.users(id),
    rejection_reason TEXT,
    revocation_reason TEXT,
    cancellation_reason TEXT,
    fee_amount NUMERIC(12,2) NOT NULL DEFAULT 0.00 CHECK (fee_amount >= 0),
    approved_at TIMESTAMPTZ,
    approved_by UUID REFERENCES auth.users(id),
    completed_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- NOC Move Passes Table
CREATE TABLE IF NOT EXISTS public.noc_move_passes (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    noc_id UUID NOT NULL REFERENCES public.noc_requests(id) ON DELETE CASCADE,
    society_id UUID NOT NULL REFERENCES public.societies(id),
    property_id UUID NOT NULL REFERENCES public.properties(id),
    pass_token_digest VARCHAR(64) NOT NULL UNIQUE,
    pin_digest VARCHAR(64) NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'approved' CHECK (status IN (
        'approved', 'completed', 'revoked', 'cancelled', 'expired'
    )),
    one_time_revealed BOOLEAN NOT NULL DEFAULT FALSE,
    verified_at TIMESTAMPTZ,
    verified_by UUID REFERENCES auth.users(id),
    completed_at TIMESTAMPTZ,
    completed_by UUID REFERENCES auth.users(id),
    valid_from TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    valid_until TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Gatekeeper Rate Limits Table
CREATE TABLE IF NOT EXISTS public.noc_gatekeeper_rate_limits (
    gatekeeper_id UUID PRIMARY KEY REFERENCES auth.users(id),
    failure_count INT NOT NULL DEFAULT 0,
    first_failure_at TIMESTAMPTZ,
    lockout_until TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- NOC Audit Logs Table
CREATE TABLE IF NOT EXISTS public.noc_audit_logs (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    noc_id UUID REFERENCES public.noc_requests(id) ON DELETE CASCADE,
    pass_id UUID REFERENCES public.noc_move_passes(id) ON DELETE CASCADE,
    actor_id UUID REFERENCES auth.users(id),
    action VARCHAR(100) NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_noc_requests_society ON public.noc_requests(society_id);
CREATE INDEX IF NOT EXISTS idx_noc_requests_property ON public.noc_requests(property_id);
CREATE INDEX IF NOT EXISTS idx_noc_requests_applicant ON public.noc_requests(applicant_id);
CREATE INDEX IF NOT EXISTS idx_noc_requests_status ON public.noc_requests(status);

CREATE INDEX IF NOT EXISTS idx_noc_passes_noc ON public.noc_move_passes(noc_id);
CREATE INDEX IF NOT EXISTS idx_noc_passes_property ON public.noc_move_passes(property_id);
CREATE INDEX IF NOT EXISTS idx_noc_passes_token ON public.noc_move_passes(pass_token_digest);
CREATE INDEX IF NOT EXISTS idx_noc_passes_status ON public.noc_move_passes(status);

-- ----------------------------------------------------------------------------
-- 2. ROW LEVEL SECURITY (RLS) & PRIVILEGES
-- ----------------------------------------------------------------------------

ALTER TABLE public.noc_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.noc_requests FORCE ROW LEVEL SECURITY;

ALTER TABLE public.noc_move_passes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.noc_move_passes FORCE ROW LEVEL SECURITY;

ALTER TABLE public.noc_gatekeeper_rate_limits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.noc_gatekeeper_rate_limits FORCE ROW LEVEL SECURITY;

ALTER TABLE public.noc_audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.noc_audit_logs FORCE ROW LEVEL SECURITY;

-- Revoke direct writes for untrusted roles
REVOKE INSERT, UPDATE, DELETE ON public.noc_requests FROM authenticated, anon;
REVOKE INSERT, UPDATE, DELETE ON public.noc_move_passes FROM authenticated, anon;
REVOKE INSERT, UPDATE, DELETE ON public.noc_gatekeeper_rate_limits FROM authenticated, anon;
REVOKE INSERT, UPDATE, DELETE ON public.noc_audit_logs FROM authenticated, anon;

GRANT SELECT ON public.noc_requests TO authenticated;
GRANT SELECT ON public.noc_move_passes TO authenticated;
GRANT SELECT ON public.noc_gatekeeper_rate_limits TO authenticated;
GRANT SELECT ON public.noc_audit_logs TO authenticated;

-- RLS Policies
CREATE POLICY noc_requests_select_policy ON public.noc_requests
    FOR SELECT TO authenticated
    USING (
        applicant_id = auth.uid() OR
        public.is_admin() OR
        EXISTS (
            SELECT 1 FROM public.association_memberships am
            WHERE am.property_id = noc_requests.property_id
            AND am.user_id = auth.uid()
            AND am.membership_status = 'active'
            AND am.end_date IS NULL
        )
    );

CREATE POLICY noc_move_passes_select_policy ON public.noc_move_passes
    FOR SELECT TO authenticated
    USING (
        public.is_admin() OR
        public.has_role(auth.uid(), 'gatekeeper') OR
        EXISTS (
            SELECT 1 FROM public.noc_requests nr
            WHERE nr.id = noc_move_passes.noc_id
            AND nr.applicant_id = auth.uid()
        )
    );

CREATE POLICY noc_gatekeeper_rate_limits_policy ON public.noc_gatekeeper_rate_limits
    FOR SELECT TO authenticated
    USING (gatekeeper_id = auth.uid() OR public.is_admin());

CREATE POLICY noc_audit_logs_select_policy ON public.noc_audit_logs
    FOR SELECT TO authenticated
    USING (public.is_admin());

-- ----------------------------------------------------------------------------
-- 3. HARDENED SECURITY DEFINER RPC ROUTINES (SET search_path = pg_catalog, public;)
-- ----------------------------------------------------------------------------

-- Helper function to generate CSPRNG hex string
CREATE OR REPLACE FUNCTION public.fn_generate_csprng_hex(p_bytes INT)
RETURNS VARCHAR
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
    RETURN encode(extensions.gen_random_bytes(p_bytes), 'hex');
END;
$$;

-- Helper function to generate 6-digit PIN using CSPRNG rejection sampling
CREATE OR REPLACE FUNCTION public.fn_generate_csprng_pin6()
RETURNS VARCHAR
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_val INT;
    v_bytes BYTEA;
BEGIN
    LOOP
        v_bytes := extensions.gen_random_bytes(4);
        v_val := (get_byte(v_bytes, 0) << 24) | (get_byte(v_bytes, 1) << 16) | (get_byte(v_bytes, 2) << 8) | get_byte(v_bytes, 3);
        v_val := v_val & 2147483647; -- Keep non-negative
        IF v_val < 2147000000 THEN -- Uniform rejection cutoff for 1,000,000 range
            RETURN lpad((v_val % 1000000)::text, 6, '0');
        END IF;
    END LOOP;
END;
$$;

-- 1. fn_request_noc
CREATE OR REPLACE FUNCTION public.fn_request_noc(
    p_property_id UUID,
    p_noc_type VARCHAR,
    p_target_user_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_caller_id UUID;
    v_society_id UUID;
    v_noc_id UUID;
    v_res JSONB;
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    IF p_noc_type NOT IN ('tenant_move_out', 'owner_transfer') THEN
        RAISE EXCEPTION 'Invalid NOC type: %', p_noc_type USING ERRCODE = '22000';
    END IF;

    SELECT society_id INTO v_society_id
    FROM public.properties
    WHERE id = p_property_id;

    IF v_society_id IS NULL THEN
        RAISE EXCEPTION 'Property not found.' USING ERRCODE = 'P0002';
    END IF;

    -- Validate applicant eligibility (owner or active resident)
    IF NOT (public.is_admin() OR EXISTS (
        SELECT 1 FROM public.association_memberships am
        WHERE am.property_id = p_property_id
        AND am.user_id = v_caller_id
        AND am.membership_status = 'active'
        AND am.end_date IS NULL
    )) THEN
        RAISE EXCEPTION 'Applicant is not authorized for this property.' USING ERRCODE = '42501';
    END IF;

    INSERT INTO public.noc_requests (
        society_id, property_id, applicant_id, noc_type, status, target_user_id
    ) VALUES (
        v_society_id, p_property_id, v_caller_id, p_noc_type, 'submitted', p_target_user_id
    ) RETURNING id INTO v_noc_id;

    INSERT INTO public.noc_audit_logs (noc_id, actor_id, action, payload)
    VALUES (v_noc_id, v_caller_id, 'REQUEST_NOC', jsonb_build_object('noc_type', p_noc_type, 'property_id', p_property_id));

    SELECT jsonb_build_object(
        'id', id, 'society_id', society_id, 'property_id', property_id,
        'applicant_id', applicant_id, 'noc_type', noc_type, 'status', status,
        'created_at', created_at
    ) INTO v_res FROM public.noc_requests WHERE id = v_noc_id;

    RETURN v_res;
END;
$$;

-- 2. fn_review_noc
CREATE OR REPLACE FUNCTION public.fn_review_noc(
    p_noc_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_caller_id UUID;
    v_status VARCHAR;
    v_res JSONB;
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL OR NOT public.is_admin() THEN
        RAISE EXCEPTION 'Admin authorization required.' USING ERRCODE = '42501';
    END IF;

    SELECT status INTO v_status FROM public.noc_requests WHERE id = p_noc_id FOR UPDATE;
    IF v_status IS NULL THEN
        RAISE EXCEPTION 'NOC request not found.' USING ERRCODE = 'P0002';
    END IF;

    IF v_status <> 'submitted' THEN
        RAISE EXCEPTION 'Cannot review NOC in state: %', v_status USING ERRCODE = '22000';
    END IF;

    UPDATE public.noc_requests
    SET status = 'under_review', updated_at = NOW()
    WHERE id = p_noc_id;

    INSERT INTO public.noc_audit_logs (noc_id, actor_id, action, payload)
    VALUES (p_noc_id, v_caller_id, 'REVIEW_NOC', jsonb_build_object('status', 'under_review'));

    SELECT jsonb_build_object(
        'id', id, 'status', status, 'updated_at', updated_at
    ) INTO v_res FROM public.noc_requests WHERE id = p_noc_id;

    RETURN v_res;
END;
$$;

-- 3. fn_approve_noc (WITH FINANCIAL SERIALIZATION STEP 1)
CREATE OR REPLACE FUNCTION public.fn_approve_noc(
    p_noc_id UUID,
    p_fee_amount NUMERIC DEFAULT 0.00,
    p_validity_days INT DEFAULT 30
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_caller_id UUID;
    v_society_id UUID;
    v_property_id UUID;
    v_status VARCHAR;
    v_balance NUMERIC;
    v_raw_token VARCHAR;
    v_raw_pin VARCHAR;
    v_token_digest VARCHAR;
    v_pin_digest VARCHAR;
    v_pass_id UUID;
    v_valid_until TIMESTAMPTZ;
    v_res JSONB;
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL OR NOT public.is_admin() THEN
        RAISE EXCEPTION 'Admin authorization required.' USING ERRCODE = '42501';
    END IF;

    -- Look up NOC request
    SELECT society_id, property_id, status INTO v_society_id, v_property_id, v_status
    FROM public.noc_requests
    WHERE id = p_noc_id FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'NOC request not found.' USING ERRCODE = 'P0002';
    END IF;

    IF v_status NOT IN ('submitted', 'under_review') THEN
        RAISE EXCEPTION 'Cannot approve NOC in state: %', v_status USING ERRCODE = '22000';
    END IF;

    -- MANDATORY FINANCIAL SERIALIZATION STEP 1: Property Row Lock
    PERFORM 1 FROM public.properties WHERE id = v_property_id FOR UPDATE;

    -- Check financial outstanding balance under property lock
    v_balance := public.fn_get_property_outstanding_balance(v_property_id);
    IF v_balance > 0 THEN
        RAISE EXCEPTION 'Cannot approve NOC: property has outstanding financial balance of %', v_balance USING ERRCODE = '42501';
    END IF;

    v_valid_until := NOW() + (p_validity_days || ' days')::INTERVAL;

    -- Generate CSPRNG Pass Token (NOC-PASS- + 12 hex chars = 21 chars total length, 48-bit entropy)
    v_raw_token := 'NOC-PASS-' || upper(public.fn_generate_csprng_hex(6));
    -- Generate CSPRNG 6-digit PIN using rejection sampling
    v_raw_pin := public.fn_generate_csprng_pin6();

    -- Compute SHA-256 digests
    v_token_digest := encode(extensions.digest(v_raw_token, 'sha256'), 'hex');
    v_pin_digest := encode(extensions.digest(v_raw_pin, 'sha256'), 'hex');

    -- Update NOC Request
    UPDATE public.noc_requests
    SET status = 'approved',
        fee_amount = p_fee_amount,
        approved_at = NOW(),
        approved_by = v_caller_id,
        expires_at = v_valid_until,
        updated_at = NOW()
    WHERE id = p_noc_id;

    -- Insert Move Pass
    INSERT INTO public.noc_move_passes (
        noc_id, society_id, property_id, pass_token_digest, pin_digest,
        status, one_time_revealed, valid_from, valid_until
    ) VALUES (
        p_noc_id, v_society_id, v_property_id, v_token_digest, v_pin_digest,
        'approved', TRUE, NOW(), v_valid_until
    ) RETURNING id INTO v_pass_id;

    -- Assess NOC fee if applicable
    IF p_fee_amount > 0 THEN
        PERFORM public.fn_generate_charge(v_society_id, v_property_id, NULL, 'NOC Fee', p_fee_amount);
    END IF;

    -- Audit log with REDACTED raw token/PIN
    INSERT INTO public.noc_audit_logs (noc_id, pass_id, actor_id, action, payload)
    VALUES (p_noc_id, v_pass_id, v_caller_id, 'APPROVE_NOC', jsonb_build_object('fee_amount', p_fee_amount, 'valid_until', v_valid_until));

    -- Return ONE-TIME raw secret payload
    v_res := jsonb_build_object(
        'noc_id', p_noc_id,
        'pass_id', v_pass_id,
        'status', 'approved',
        'raw_pass_token', v_raw_token,
        'raw_pin', v_raw_pin,
        'valid_until', v_valid_until
    );

    RETURN v_res;
END;
$$;

-- 4. fn_reject_noc
CREATE OR REPLACE FUNCTION public.fn_reject_noc(
    p_noc_id UUID,
    p_reason TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_caller_id UUID;
    v_property_id UUID;
    v_status VARCHAR;
    v_res JSONB;
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL OR NOT public.is_admin() THEN
        RAISE EXCEPTION 'Admin authorization required.' USING ERRCODE = '42501';
    END IF;

    SELECT property_id, status INTO v_property_id, v_status
    FROM public.noc_requests WHERE id = p_noc_id FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'NOC request not found.' USING ERRCODE = 'P0002';
    END IF;

    IF v_status NOT IN ('submitted', 'under_review') THEN
        RAISE EXCEPTION 'Cannot reject NOC in state: %', v_status USING ERRCODE = '22000';
    END IF;

    PERFORM 1 FROM public.properties WHERE id = v_property_id FOR UPDATE;

    UPDATE public.noc_requests
    SET status = 'rejected', rejection_reason = p_reason, updated_at = NOW()
    WHERE id = p_noc_id;

    INSERT INTO public.noc_audit_logs (noc_id, actor_id, action, payload)
    VALUES (p_noc_id, v_caller_id, 'REJECT_NOC', jsonb_build_object('reason', p_reason));

    SELECT jsonb_build_object('id', id, 'status', status, 'rejection_reason', rejection_reason)
    INTO v_res FROM public.noc_requests WHERE id = p_noc_id;

    RETURN v_res;
END;
$$;

-- 5. fn_revoke_noc
CREATE OR REPLACE FUNCTION public.fn_revoke_noc(
    p_noc_id UUID,
    p_reason TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_caller_id UUID;
    v_property_id UUID;
    v_status VARCHAR;
    v_res JSONB;
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL OR NOT public.is_admin() THEN
        RAISE EXCEPTION 'Admin authorization required.' USING ERRCODE = '42501';
    END IF;

    SELECT property_id, status INTO v_property_id, v_status
    FROM public.noc_requests WHERE id = p_noc_id FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'NOC request not found.' USING ERRCODE = 'P0002';
    END IF;

    IF v_status NOT IN ('approved', 'move_pass_generated') THEN
        RAISE EXCEPTION 'Cannot revoke NOC in state: %', v_status USING ERRCODE = '22000';
    END IF;

    PERFORM 1 FROM public.properties WHERE id = v_property_id FOR UPDATE;

    UPDATE public.noc_requests
    SET status = 'revoked', revocation_reason = p_reason, updated_at = NOW()
    WHERE id = p_noc_id;

    UPDATE public.noc_move_passes
    SET status = 'revoked', updated_at = NOW()
    WHERE noc_id = p_noc_id AND status = 'approved';

    INSERT INTO public.noc_audit_logs (noc_id, actor_id, action, payload)
    VALUES (p_noc_id, v_caller_id, 'REVOKE_NOC', jsonb_build_object('reason', p_reason));

    SELECT jsonb_build_object('id', id, 'status', status, 'revocation_reason', revocation_reason)
    INTO v_res FROM public.noc_requests WHERE id = p_noc_id;

    RETURN v_res;
END;
$$;

-- 6. fn_cancel_noc
CREATE OR REPLACE FUNCTION public.fn_cancel_noc(
    p_noc_id UUID,
    p_reason TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_caller_id UUID;
    v_applicant_id UUID;
    v_property_id UUID;
    v_status VARCHAR;
    v_res JSONB;
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    SELECT applicant_id, property_id, status INTO v_applicant_id, v_property_id, v_status
    FROM public.noc_requests WHERE id = p_noc_id FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'NOC request not found.' USING ERRCODE = 'P0002';
    END IF;

    IF NOT (v_caller_id = v_applicant_id OR public.is_admin()) THEN
        RAISE EXCEPTION 'Not authorized to cancel NOC.' USING ERRCODE = '42501';
    END IF;

    IF v_status NOT IN ('draft', 'submitted', 'under_review', 'approved') THEN
        RAISE EXCEPTION 'Cannot cancel NOC in state: %', v_status USING ERRCODE = '22000';
    END IF;

    PERFORM 1 FROM public.properties WHERE id = v_property_id FOR UPDATE;

    UPDATE public.noc_requests
    SET status = 'cancelled', cancellation_reason = p_reason, updated_at = NOW()
    WHERE id = p_noc_id;

    UPDATE public.noc_move_passes
    SET status = 'cancelled', updated_at = NOW()
    WHERE noc_id = p_noc_id AND status = 'approved';

    INSERT INTO public.noc_audit_logs (noc_id, actor_id, action, payload)
    VALUES (p_noc_id, v_caller_id, 'CANCEL_NOC', jsonb_build_object('reason', p_reason));

    SELECT jsonb_build_object('id', id, 'status', status, 'cancellation_reason', cancellation_reason)
    INTO v_res FROM public.noc_requests WHERE id = p_noc_id;

    RETURN v_res;
END;
$$;

-- 7. verify_pass (Rev 4.53 Model A)
CREATE OR REPLACE FUNCTION public.verify_pass(
    p_pass_token VARCHAR,
    p_pin VARCHAR
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_caller_id UUID;
    v_token_digest VARCHAR;
    v_pin_digest VARCHAR;
    v_rate_limit RECORD;
    v_pass RECORD;
    v_res JSONB;
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    IF NOT (public.has_role(v_caller_id, 'gatekeeper') OR public.is_admin()) THEN
        RAISE EXCEPTION 'Gatekeeper or Admin authorization required.' USING ERRCODE = '42501';
    END IF;

    -- Gatekeeper Rate Limit Lookup (FOR UPDATE)
    SELECT * INTO v_rate_limit
    FROM public.noc_gatekeeper_rate_limits
    WHERE gatekeeper_id = v_caller_id FOR UPDATE;

    IF v_rate_limit.gatekeeper_id IS NULL THEN
        RAISE EXCEPTION 'Gatekeeper rate limit context missing.' USING ERRCODE = '42501';
    END IF;

    IF v_rate_limit.lockout_until IS NOT NULL AND v_rate_limit.lockout_until > NOW() THEN
        RAISE EXCEPTION 'Gatekeeper locked out until %', v_rate_limit.lockout_until USING ERRCODE = '42501';
    END IF;

    -- Reset rolling 10-minute window if expired
    IF v_rate_limit.first_failure_at IS NOT NULL AND v_rate_limit.first_failure_at < NOW() - INTERVAL '10 minutes' THEN
        UPDATE public.noc_gatekeeper_rate_limits
        SET failure_count = 0, first_failure_at = NULL, lockout_until = NULL, updated_at = NOW()
        WHERE gatekeeper_id = v_caller_id;
        v_rate_limit.failure_count := 0;
    END IF;

    -- Compute SHA-256 digests
    v_token_digest := encode(extensions.digest(p_pass_token, 'sha256'), 'hex');
    v_pin_digest := encode(extensions.digest(p_pin, 'sha256'), 'hex');

    -- Lookup move pass
    SELECT * INTO v_pass
    FROM public.noc_move_passes
    WHERE pass_token_digest = v_token_digest;

    -- Validate pass match & PIN
    IF v_pass.id IS NULL OR v_pass.pin_digest <> v_pin_digest THEN
        -- Handle failure counter
        IF v_rate_limit.failure_count = 0 THEN
            UPDATE public.noc_gatekeeper_rate_limits
            SET failure_count = 1, first_failure_at = NOW(), updated_at = NOW()
            WHERE gatekeeper_id = v_caller_id;
        ELSE
            UPDATE public.noc_gatekeeper_rate_limits
            SET failure_count = failure_count + 1,
                lockout_until = CASE WHEN failure_count + 1 >= 10 THEN NOW() + INTERVAL '15 minutes' ELSE lockout_until END,
                updated_at = NOW()
            WHERE gatekeeper_id = v_caller_id;
        END IF;

        RAISE EXCEPTION 'Invalid NOC pass token or PIN.' USING ERRCODE = '22000';
    END IF;

    -- Reset failure count on success
    UPDATE public.noc_gatekeeper_rate_limits
    SET failure_count = 0, first_failure_at = NULL, lockout_until = NULL, updated_at = NOW()
    WHERE gatekeeper_id = v_caller_id;

    -- Validate pass status & validity
    IF v_pass.status <> 'approved' THEN
        RAISE EXCEPTION 'Pass is not valid for use (status: %).', v_pass.status USING ERRCODE = '22000';
    END IF;

    IF v_pass.valid_until < NOW() THEN
        RAISE EXCEPTION 'Pass has expired.' USING ERRCODE = '22000';
    END IF;

    -- Update verification timestamp
    UPDATE public.noc_move_passes
    SET verified_at = NOW(), verified_by = v_caller_id, updated_at = NOW()
    WHERE id = v_pass.id;

    INSERT INTO public.noc_audit_logs (noc_id, pass_id, actor_id, action, payload)
    VALUES (v_pass.noc_id, v_pass.id, v_caller_id, 'VERIFY_PASS', jsonb_build_object('status', 'verified'));

    SELECT jsonb_build_object(
        'pass_id', v_pass.id,
        'noc_id', v_pass.noc_id,
        'property_id', v_pass.property_id,
        'status', 'verified',
        'valid_until', v_pass.valid_until
    ) INTO v_res;

    RETURN v_res;
END;
$$;

-- 8. fn_complete_noc_transfer
CREATE OR REPLACE FUNCTION public.fn_complete_noc_transfer(
    p_pass_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_caller_id UUID;
    v_pass RECORD;
    v_noc RECORD;
    v_res JSONB;
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    IF NOT (public.has_role(v_caller_id, 'gatekeeper') OR public.is_admin()) THEN
        RAISE EXCEPTION 'Gatekeeper or Admin authorization required.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_pass
    FROM public.noc_move_passes
    WHERE id = p_pass_id FOR UPDATE;

    IF v_pass.id IS NULL THEN
        RAISE EXCEPTION 'NOC move pass not found.' USING ERRCODE = 'P0002';
    END IF;

    IF v_pass.status = 'completed' THEN
        RAISE EXCEPTION 'Pass already completed.' USING ERRCODE = '22000';
    END IF;

    IF v_pass.status <> 'approved' OR v_pass.verified_at IS NULL THEN
        RAISE EXCEPTION 'Pass must be verified before completing transfer.' USING ERRCODE = '22000';
    END IF;

    SELECT * INTO v_noc
    FROM public.noc_requests
    WHERE id = v_pass.noc_id FOR UPDATE;

    -- MANDATORY FINANCIAL SERIALIZATION STEP 1: Property Row Lock
    PERFORM 1 FROM public.properties WHERE id = v_pass.property_id FOR UPDATE;

    -- Complete pass & NOC request
    UPDATE public.noc_move_passes
    SET status = 'completed', completed_at = NOW(), completed_by = v_caller_id, updated_at = NOW()
    WHERE id = p_pass_id;

    UPDATE public.noc_requests
    SET status = 'completed', completed_at = NOW(), updated_at = NOW()
    WHERE id = v_pass.noc_id;

    -- Perform property occupancy/membership status updates if applicable
    IF v_noc.noc_type = 'tenant_move_out' THEN
        UPDATE public.occupants
        SET end_date = CURRENT_DATE,
            end_recorded_by = v_caller_id,
            departure_reason = 'NOC Tenant Move-Out Completed',
            updated_at = NOW()
        WHERE property_id = v_pass.property_id
          AND user_id = v_noc.applicant_id
          AND end_date IS NULL;
    ELSIF v_noc.noc_type = 'owner_transfer' AND v_noc.target_user_id IS NOT NULL THEN
        -- 1. Close outgoing owner's active membership
        UPDATE public.association_memberships
        SET end_date = CURRENT_DATE,
            membership_status = 'resigned',
            end_recorded_by = v_caller_id,
            transition_notes = 'NOC Ownership Transfer Completed',
            updated_at = NOW()
        WHERE property_id = v_pass.property_id
          AND user_id = v_noc.applicant_id
          AND end_date IS NULL;

        -- 2. Insert incoming owner's new active membership
        INSERT INTO public.association_memberships (
            society_id,
            property_id,
            user_id,
            membership_status,
            start_date,
            created_by,
            transition_notes
        ) VALUES (
            v_noc.society_id,
            v_pass.property_id,
            v_noc.target_user_id,
            'active',
            CURRENT_DATE,
            v_caller_id,
            'NOC Ownership Transfer Admission'
        );
    END IF;

    INSERT INTO public.noc_audit_logs (noc_id, pass_id, actor_id, action, payload)
    VALUES (v_pass.noc_id, p_pass_id, v_caller_id, 'COMPLETE_NOC_TRANSFER', jsonb_build_object('noc_type', v_noc.noc_type));

    SELECT jsonb_build_object(
        'pass_id', p_pass_id,
        'noc_id', v_pass.noc_id,
        'status', 'completed',
        'completed_at', NOW()
    ) INTO v_res;

    RETURN v_res;
END;
$$;

-- 9. process_expired_noc_passes
CREATE OR REPLACE FUNCTION public.process_expired_noc_passes()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_count INT := 0;
BEGIN
    UPDATE public.noc_move_passes
    SET status = 'expired', updated_at = NOW()
    WHERE status = 'approved' AND valid_until < NOW();

    GET DIAGNOSTICS v_count = ROW_COUNT;

    UPDATE public.noc_requests
    SET status = 'expired', updated_at = NOW()
    WHERE status IN ('approved', 'move_pass_generated') AND expires_at < NOW();

    RETURN v_count;
END;
$$;
