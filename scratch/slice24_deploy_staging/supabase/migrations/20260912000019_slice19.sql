-- =========================================================================
-- SU SOCIETY APP - SLICE 19 SCHEMA (DOMESTIC STAFF ACCESS MANAGEMENT)
-- =========================================================================

-- \set ON_ERROR_STOP on

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- =========================================================================
-- 1. TABLE DEFINITIONS
-- =========================================================================

-- 1.1 Domestic Staff Helper Registry
CREATE TABLE IF NOT EXISTS public.staff_helpers (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id              UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    full_name               VARCHAR(150) NOT NULL,
    mobile                  VARCHAR(20) NOT NULL,
    service_type            VARCHAR(50) NOT NULL CONSTRAINT chk_helper_service_type CHECK (
                                service_type IN ('maid', 'driver', 'cook', 'nanny', 'car_washer', 'tutor', 'gardener', 'other')
                            ),
    id_type                 VARCHAR(30) CONSTRAINT chk_helper_id_type CHECK (
                                id_type IS NULL OR id_type IN ('aadhaar', 'pan', 'passport', 'voter_id', 'driving_license', 'other')
                            ),
    photo_url               TEXT,
    passcode_hash           TEXT NOT NULL,
    status                  VARCHAR(20) NOT NULL DEFAULT 'active' CONSTRAINT chk_helper_status CHECK (status IN ('active', 'inactive')),
    failed_passcode_attempts INT NOT NULL DEFAULT 0,
    lockout_until           TIMESTAMPTZ,
    registered_by           UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_staff_helpers_society_status ON public.staff_helpers(society_id, status);
CREATE INDEX IF NOT EXISTS idx_staff_helpers_mobile ON public.staff_helpers(mobile);


-- 1.2 Helper Flat Authorization Mappings
CREATE TABLE IF NOT EXISTS public.helper_flat_mappings (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id          UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    helper_id           UUID NOT NULL REFERENCES public.staff_helpers(id) ON DELETE CASCADE,
    property_id         UUID NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
    employer_user_id    UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    status              VARCHAR(20) NOT NULL DEFAULT 'active' CONSTRAINT chk_mapping_status CHECK (status IN ('active', 'revoked')),
    start_date          DATE NOT NULL DEFAULT CURRENT_DATE,
    end_date            DATE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Partial Unique Index: At most ONE active mapping per helper/property pair
CREATE UNIQUE INDEX IF NOT EXISTS uq_helper_property_active_mapping ON public.helper_flat_mappings(helper_id, property_id) WHERE status = 'active';

CREATE INDEX IF NOT EXISTS idx_helper_flat_mappings_helper ON public.helper_flat_mappings(helper_id);
CREATE INDEX IF NOT EXISTS idx_helper_flat_mappings_property ON public.helper_flat_mappings(property_id);


-- 1.3 Security Gate Attendance Logs
CREATE TABLE IF NOT EXISTS public.helper_attendance_logs (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id          UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    helper_id           UUID NOT NULL REFERENCES public.staff_helpers(id) ON DELETE RESTRICT,
    property_id         UUID NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
    check_in            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    check_out           TIMESTAMPTZ,
    entry_gatekeeper_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    exit_gatekeeper_id  UUID REFERENCES public.users(id) ON DELETE RESTRICT,
    status              VARCHAR(20) NOT NULL DEFAULT 'checked_in' CONSTRAINT chk_attendance_status CHECK (status IN ('checked_in', 'checked_out', 'overstayed')),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Partial Unique Index: At most ONE active (checked_in) attendance record per helper across database
CREATE UNIQUE INDEX IF NOT EXISTS uq_helper_active_attendance ON public.helper_attendance_logs(helper_id) WHERE status = 'checked_in';

CREATE INDEX IF NOT EXISTS idx_helper_attendance_helper_status ON public.helper_attendance_logs(helper_id, status);
CREATE INDEX IF NOT EXISTS idx_helper_attendance_society_checkin ON public.helper_attendance_logs(society_id, check_in);


-- =========================================================================
-- 2. ROW LEVEL SECURITY (RLS) POLICIES
-- =========================================================================

ALTER TABLE public.staff_helpers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staff_helpers FORCE ROW LEVEL SECURITY;

ALTER TABLE public.helper_flat_mappings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.helper_flat_mappings FORCE ROW LEVEL SECURITY;

ALTER TABLE public.helper_attendance_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.helper_attendance_logs FORCE ROW LEVEL SECURITY;

-- Select policies
DROP POLICY IF EXISTS pol_staff_helpers_select ON public.staff_helpers;
CREATE POLICY pol_staff_helpers_select ON public.staff_helpers FOR SELECT
    USING (
        society_id = public.get_user_society_id(auth.uid()) AND (
            public.is_admin() OR public.has_role(auth.uid(), 'gatekeeper') OR registered_by = auth.uid() OR
            EXISTS (SELECT 1 FROM public.helper_flat_mappings m WHERE m.helper_id = staff_helpers.id AND m.status = 'active' AND (m.employer_user_id = auth.uid() OR public.is_property_owner(auth.uid(), m.property_id) OR public.is_property_tenant(auth.uid(), m.property_id)))
        )
    );

DROP POLICY IF EXISTS pol_helper_flat_mappings_select ON public.helper_flat_mappings;
CREATE POLICY pol_helper_flat_mappings_select ON public.helper_flat_mappings FOR SELECT
    USING (
        society_id = public.get_user_society_id(auth.uid()) AND (
            public.is_admin() OR employer_user_id = auth.uid() OR public.is_property_owner(auth.uid(), property_id) OR public.is_property_tenant(auth.uid(), property_id)
        )
    );

DROP POLICY IF EXISTS pol_helper_attendance_logs_select ON public.helper_attendance_logs;
CREATE POLICY pol_helper_attendance_logs_select ON public.helper_attendance_logs FOR SELECT
    USING (
        society_id = public.get_user_society_id(auth.uid()) AND (
            public.is_admin() OR public.has_role(auth.uid(), 'gatekeeper') OR
            EXISTS (SELECT 1 FROM public.helper_flat_mappings m WHERE m.helper_id = helper_attendance_logs.helper_id AND m.property_id = helper_attendance_logs.property_id AND (m.employer_user_id = auth.uid() OR public.is_property_owner(auth.uid(), m.property_id) OR public.is_property_tenant(auth.uid(), m.property_id)))
        )
    );

-- Restrictive mutation policies (block direct client DML, forcing RPC execution)
DROP POLICY IF EXISTS pol_staff_helpers_restrictive_insert ON public.staff_helpers;
CREATE POLICY pol_staff_helpers_restrictive_insert ON public.staff_helpers FOR INSERT WITH CHECK (false);

DROP POLICY IF EXISTS pol_staff_helpers_restrictive_update ON public.staff_helpers;
CREATE POLICY pol_staff_helpers_restrictive_update ON public.staff_helpers FOR UPDATE USING (false) WITH CHECK (false);

DROP POLICY IF EXISTS pol_staff_helpers_restrictive_delete ON public.staff_helpers;
CREATE POLICY pol_staff_helpers_restrictive_delete ON public.staff_helpers FOR DELETE USING (false);

DROP POLICY IF EXISTS pol_helper_flat_mappings_restrictive_insert ON public.helper_flat_mappings;
CREATE POLICY pol_helper_flat_mappings_restrictive_insert ON public.helper_flat_mappings FOR INSERT WITH CHECK (false);

DROP POLICY IF EXISTS pol_helper_flat_mappings_restrictive_update ON public.helper_flat_mappings;
CREATE POLICY pol_helper_flat_mappings_restrictive_update ON public.helper_flat_mappings FOR UPDATE USING (false) WITH CHECK (false);

DROP POLICY IF EXISTS pol_helper_flat_mappings_restrictive_delete ON public.helper_flat_mappings;
CREATE POLICY pol_helper_flat_mappings_restrictive_delete ON public.helper_flat_mappings FOR DELETE USING (false);

DROP POLICY IF EXISTS pol_helper_attendance_logs_restrictive_insert ON public.helper_attendance_logs;
CREATE POLICY pol_helper_attendance_logs_restrictive_insert ON public.helper_attendance_logs FOR INSERT WITH CHECK (false);

DROP POLICY IF EXISTS pol_helper_attendance_logs_restrictive_update ON public.helper_attendance_logs;
CREATE POLICY pol_helper_attendance_logs_restrictive_update ON public.helper_attendance_logs FOR UPDATE USING (false) WITH CHECK (false);

DROP POLICY IF EXISTS pol_helper_attendance_logs_restrictive_delete ON public.helper_attendance_logs;
CREATE POLICY pol_helper_attendance_logs_restrictive_delete ON public.helper_attendance_logs FOR DELETE USING (false);


-- =========================================================================
-- 3. WORKFLOW ROUTINES (SECURITY DEFINER FUNCTIONS)
-- =========================================================================

-- 3.1 register_domestic_helper
DROP FUNCTION IF EXISTS public.register_domestic_helper(TEXT, TEXT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION public.register_domestic_helper(
    p_name TEXT,
    p_mobile TEXT,
    p_service_type TEXT,
    p_passcode TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_caller_society UUID;
    v_new_id UUID;
    v_hash TEXT;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    v_caller_society := public.get_user_society_id(v_caller);
    IF v_caller_society IS NULL THEN
        RAISE EXCEPTION 'User does not belong to a society.' USING ERRCODE = '42501';
    END IF;

    IF p_service_type NOT IN ('maid', 'driver', 'cook', 'nanny', 'car_washer', 'tutor', 'gardener', 'other') THEN
        RAISE EXCEPTION 'Invalid service type.' USING ERRCODE = '22000';
    END IF;

    IF p_passcode !~ '^[0-9]{6}$' THEN
        RAISE EXCEPTION 'Passcode must be a 6-digit number.' USING ERRCODE = '22000';
    END IF;

    v_hash := extensions.crypt(p_passcode, extensions.gen_salt('bf', 8));

    INSERT INTO public.staff_helpers (
        society_id, full_name, mobile, service_type, passcode_hash, status, registered_by
    ) VALUES (
        v_caller_society, p_name, p_mobile, p_service_type, v_hash, 'active', v_caller
    ) RETURNING id INTO v_new_id;

    -- Audit
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_caller_society, v_caller, 'staff_helper', v_new_id, 'REGISTERED helper', jsonb_build_object('full_name', p_name, 'mobile', p_mobile, 'service_type', p_service_type));

    RETURN v_new_id;
END;
$$;


-- 3.2 update_domestic_helper
DROP FUNCTION IF EXISTS public.update_domestic_helper(UUID, TEXT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION public.update_domestic_helper(
    p_helper_id UUID,
    p_name TEXT,
    p_mobile TEXT,
    p_service_type TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_caller_society UUID;
    v_helper RECORD;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    v_caller_society := public.get_user_society_id(v_caller);

    SELECT * INTO v_helper FROM public.staff_helpers WHERE id = p_helper_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Helper record not found.' USING ERRCODE = '22000';
    END IF;

    IF v_caller_society IS DISTINCT FROM v_helper.society_id THEN
        RAISE EXCEPTION 'Cross-society execution denied.' USING ERRCODE = '42501';
    END IF;

    IF NOT public.is_admin() AND v_helper.registered_by IS DISTINCT FROM v_caller THEN
        RAISE EXCEPTION 'Access Denied: Only registering user or admin can update helper.' USING ERRCODE = '42501';
    END IF;

    IF p_service_type NOT IN ('maid', 'driver', 'cook', 'nanny', 'car_washer', 'tutor', 'gardener', 'other') THEN
        RAISE EXCEPTION 'Invalid service type.' USING ERRCODE = '22000';
    END IF;

    UPDATE public.staff_helpers
    SET full_name = p_name, mobile = p_mobile, service_type = p_service_type, updated_at = NOW()
    WHERE id = p_helper_id;

    -- Audit
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_helper.society_id, v_caller, 'staff_helper', p_helper_id, 'UPDATED helper', jsonb_build_object('full_name', p_name, 'mobile', p_mobile, 'service_type', p_service_type));
END;
$$;


-- 3.3 set_helper_status
DROP FUNCTION IF EXISTS public.set_helper_status(UUID, TEXT);
CREATE OR REPLACE FUNCTION public.set_helper_status(
    p_helper_id UUID,
    p_status TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_caller_society UUID;
    v_helper RECORD;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    v_caller_society := public.get_user_society_id(v_caller);

    SELECT * INTO v_helper FROM public.staff_helpers WHERE id = p_helper_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Helper record not found.' USING ERRCODE = '22000';
    END IF;

    IF v_caller_society IS DISTINCT FROM v_helper.society_id THEN
        RAISE EXCEPTION 'Cross-society execution denied.' USING ERRCODE = '42501';
    END IF;

    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access Denied: Admin role required to set helper status.' USING ERRCODE = '42501';
    END IF;

    IF p_status NOT IN ('active', 'inactive') THEN
        RAISE EXCEPTION 'Invalid status value.' USING ERRCODE = '22000';
    END IF;

    UPDATE public.staff_helpers
    SET status = p_status, updated_at = NOW()
    WHERE id = p_helper_id;

    -- Audit
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_helper.society_id, v_caller, 'staff_helper', p_helper_id, 'UPDATED helper status', jsonb_build_object('old_status', v_helper.status, 'new_status', p_status));
END;
$$;


-- 3.4 authorize_helper_for_flat
DROP FUNCTION IF EXISTS public.authorize_helper_for_flat(UUID, UUID);
CREATE OR REPLACE FUNCTION public.authorize_helper_for_flat(
    p_helper_id UUID,
    p_property_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_caller_society UUID;
    v_helper RECORD;
    v_prop_society UUID;
    v_mapping_id UUID;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    v_caller_society := public.get_user_society_id(v_caller);

    SELECT society_id INTO v_prop_society FROM public.properties WHERE id = p_property_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Property record not found.' USING ERRCODE = '22000';
    END IF;

    IF v_caller_society IS DISTINCT FROM v_prop_society THEN
        RAISE EXCEPTION 'Cross-society execution denied.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_helper FROM public.staff_helpers WHERE id = p_helper_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Helper record not found.' USING ERRCODE = '22000';
    END IF;

    IF v_helper.society_id IS DISTINCT FROM v_prop_society THEN
        RAISE EXCEPTION 'Cross-society execution denied.' USING ERRCODE = '42501';
    END IF;

    IF v_helper.status != 'active' THEN
        RAISE EXCEPTION 'Helper is currently inactive.' USING ERRCODE = '22000';
    END IF;

    IF NOT public.is_admin() AND NOT public.is_property_owner(v_caller, p_property_id) AND NOT public.is_property_tenant(v_caller, p_property_id) THEN
        RAISE EXCEPTION 'Access Denied: Only flat owner, tenant, or admin can authorize helper.' USING ERRCODE = '42501';
    END IF;

    INSERT INTO public.helper_flat_mappings (
        society_id, helper_id, property_id, employer_user_id, status, start_date
    ) VALUES (
        v_prop_society, p_helper_id, p_property_id, v_caller, 'active', CURRENT_DATE
    ) RETURNING id INTO v_mapping_id;

    -- Audit
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_prop_society, v_caller, 'helper_flat_mapping', v_mapping_id, 'AUTHORIZED helper for flat', jsonb_build_object('helper_id', p_helper_id, 'property_id', p_property_id));

    RETURN v_mapping_id;
END;
$$;


-- 3.5 revoke_helper_authorization
DROP FUNCTION IF EXISTS public.revoke_helper_authorization(UUID);
CREATE OR REPLACE FUNCTION public.revoke_helper_authorization(
    p_mapping_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_caller_society UUID;
    v_mapping RECORD;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    v_caller_society := public.get_user_society_id(v_caller);

    SELECT * INTO v_mapping FROM public.helper_flat_mappings WHERE id = p_mapping_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Flat authorization mapping not found.' USING ERRCODE = '22000';
    END IF;

    IF v_caller_society IS DISTINCT FROM v_mapping.society_id THEN
        RAISE EXCEPTION 'Cross-society execution denied.' USING ERRCODE = '42501';
    END IF;

    IF NOT public.is_admin() AND v_mapping.employer_user_id IS DISTINCT FROM v_caller AND NOT public.is_property_owner(v_caller, v_mapping.property_id) AND NOT public.is_property_tenant(v_caller, v_mapping.property_id) THEN
        RAISE EXCEPTION 'Access Denied: Only employer resident or admin can revoke authorization.' USING ERRCODE = '42501';
    END IF;

    UPDATE public.helper_flat_mappings
    SET status = 'revoked', end_date = CURRENT_DATE, updated_at = NOW()
    WHERE id = p_mapping_id;

    -- Audit
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_mapping.society_id, v_caller, 'helper_flat_mapping', p_mapping_id, 'REVOKED helper authorization', jsonb_build_object('helper_id', v_mapping.helper_id, 'property_id', v_mapping.property_id));
END;
$$;


-- 3.6 checkin_domestic_helper
DROP FUNCTION IF EXISTS public.checkin_domestic_helper(UUID, UUID, TEXT);
CREATE OR REPLACE FUNCTION public.checkin_domestic_helper(
    p_helper_id UUID,
    p_property_id UUID,
    p_passcode TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_caller_society UUID;
    v_helper RECORD;
    v_mapping RECORD;
    v_att_id UUID;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    v_caller_society := public.get_user_society_id(v_caller);

    IF NOT public.is_admin() AND NOT public.has_role(v_caller, 'gatekeeper') THEN
        RAISE EXCEPTION 'Access Denied: Gatekeeper or admin role required for check-in.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_helper FROM public.staff_helpers WHERE id = p_helper_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Helper record not found.' USING ERRCODE = '22000';
    END IF;

    IF v_helper.society_id IS DISTINCT FROM v_caller_society THEN
        RAISE EXCEPTION 'Cross-society execution denied.' USING ERRCODE = '42501';
    END IF;

    IF v_helper.status != 'active' THEN
        RAISE EXCEPTION 'Helper is currently inactive.' USING ERRCODE = '22000';
    END IF;

    IF v_helper.lockout_until IS NOT NULL AND v_helper.lockout_until > NOW() THEN
        RAISE EXCEPTION 'Account temporarily locked due to excessive failed attempts. Try again later.' USING ERRCODE = '22000';
    END IF;

    -- Verify flat authorization mapping
    SELECT * INTO v_mapping FROM public.helper_flat_mappings 
    WHERE helper_id = p_helper_id AND property_id = p_property_id AND status = 'active';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Helper is not authorized for target property.' USING ERRCODE = '42501';
    END IF;

    -- Atomic Passcode Verification
    IF extensions.crypt(p_passcode, v_helper.passcode_hash) IS DISTINCT FROM v_helper.passcode_hash THEN
        UPDATE public.staff_helpers
        SET failed_passcode_attempts = failed_passcode_attempts + 1,
            lockout_until = CASE WHEN failed_passcode_attempts + 1 >= 5 THEN NOW() + INTERVAL '15 minutes' ELSE lockout_until END
        WHERE id = p_helper_id;

        RAISE EXCEPTION 'Invalid helper passcode.' USING ERRCODE = '22000';
    END IF;

    -- Active attendance check
    IF EXISTS (SELECT 1 FROM public.helper_attendance_logs WHERE helper_id = p_helper_id AND status = 'checked_in') THEN
        RAISE EXCEPTION 'Helper is already checked in.' USING ERRCODE = '22000';
    END IF;

    -- Reset failed attempts on success
    UPDATE public.staff_helpers
    SET failed_passcode_attempts = 0, lockout_until = NULL
    WHERE id = p_helper_id;

    INSERT INTO public.helper_attendance_logs (
        society_id, helper_id, property_id, check_in, entry_gatekeeper_id, status
    ) VALUES (
        v_caller_society, p_helper_id, p_property_id, NOW(), v_caller, 'checked_in'
    ) RETURNING id INTO v_att_id;

    -- Audit
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_caller_society, v_caller, 'helper_attendance_log', v_att_id, 'CHECKED IN domestic helper', jsonb_build_object('helper_id', p_helper_id, 'property_id', p_property_id));

    -- Notification to mapped employer
    INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
    VALUES (v_caller_society, v_mapping.employer_user_id, 'helper_attendance', 'Helper Checked In', v_helper.full_name || ' has checked in at the gate.', 'helper_attendance_logs', v_att_id);

    RETURN v_att_id;
END;
$$;


-- 3.7 checkout_domestic_helper
DROP FUNCTION IF EXISTS public.checkout_domestic_helper(UUID);
CREATE OR REPLACE FUNCTION public.checkout_domestic_helper(
    p_attendance_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_caller_society UUID;
    v_att RECORD;
    v_helper RECORD;
    v_mapping RECORD;
    v_exit_status VARCHAR(20);
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    v_caller_society := public.get_user_society_id(v_caller);

    IF NOT public.is_admin() AND NOT public.has_role(v_caller, 'gatekeeper') THEN
        RAISE EXCEPTION 'Access Denied: Gatekeeper or admin role required for checkout.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_att FROM public.helper_attendance_logs WHERE id = p_attendance_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Attendance log record not found.' USING ERRCODE = '22000';
    END IF;

    IF v_att.society_id IS DISTINCT FROM v_caller_society THEN
        RAISE EXCEPTION 'Cross-society execution denied.' USING ERRCODE = '42501';
    END IF;

    IF v_att.check_out IS NOT NULL OR v_att.status != 'checked_in' THEN
        RAISE EXCEPTION 'Helper is already checked out.' USING ERRCODE = '22000';
    END IF;

    IF (NOW() - v_att.check_in) > INTERVAL '12 hours' THEN
        v_exit_status := 'overstayed';
    ELSE
        v_exit_status := 'checked_out';
    END IF;

    UPDATE public.helper_attendance_logs
    SET check_out = NOW(), status = v_exit_status, exit_gatekeeper_id = v_caller, updated_at = NOW()
    WHERE id = p_attendance_id;

    SELECT * INTO v_helper FROM public.staff_helpers WHERE id = v_att.helper_id;
    SELECT * INTO v_mapping FROM public.helper_flat_mappings WHERE helper_id = v_att.helper_id AND property_id = v_att.property_id AND status = 'active' LIMIT 1;

    -- Audit
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_att.society_id, v_caller, 'helper_attendance_log', p_attendance_id, 'CHECKED OUT domestic helper', jsonb_build_object('helper_id', v_att.helper_id, 'exit_status', v_exit_status));

    -- Notification
    IF v_mapping IS NOT NULL THEN
        INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
        VALUES (v_att.society_id, v_mapping.employer_user_id, 'helper_attendance', 'Helper Checked Out', v_helper.full_name || ' has checked out at the gate.', 'helper_attendance_logs', p_attendance_id);
    END IF;
END;
$$;


-- 3.8 generate_helper_passcode
DROP FUNCTION IF EXISTS public.generate_helper_passcode(UUID, TEXT);
CREATE OR REPLACE FUNCTION public.generate_helper_passcode(
    p_helper_id UUID,
    p_new_passcode TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_caller_society UUID;
    v_helper RECORD;
    v_hash TEXT;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    v_caller_society := public.get_user_society_id(v_caller);

    SELECT * INTO v_helper FROM public.staff_helpers WHERE id = p_helper_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Helper record not found.' USING ERRCODE = '22000';
    END IF;

    IF v_helper.society_id IS DISTINCT FROM v_caller_society THEN
        RAISE EXCEPTION 'Cross-society execution denied.' USING ERRCODE = '42501';
    END IF;

    IF NOT public.is_admin() AND NOT EXISTS (
        SELECT 1 FROM public.helper_flat_mappings 
        WHERE helper_id = p_helper_id AND status = 'active' AND (employer_user_id = v_caller OR public.is_property_owner(v_caller, property_id) OR public.is_property_tenant(v_caller, property_id))
    ) THEN
        RAISE EXCEPTION 'Access Denied: Only employer resident or admin can rotate passcode.' USING ERRCODE = '42501';
    END IF;

    IF p_new_passcode !~ '^[0-9]{6}$' THEN
        RAISE EXCEPTION 'Passcode must be a 6-digit number.' USING ERRCODE = '22000';
    END IF;

    v_hash := extensions.crypt(p_new_passcode, extensions.gen_salt('bf', 8));

    UPDATE public.staff_helpers
    SET passcode_hash = v_hash, failed_passcode_attempts = 0, lockout_until = NULL, updated_at = NOW()
    WHERE id = p_helper_id;

    -- Audit (redact passcode)
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_helper.society_id, v_caller, 'staff_helper', p_helper_id, 'ROTATED helper passcode', jsonb_build_object('helper_id', p_helper_id));

    RETURN p_new_passcode;
END;
$$;


-- =========================================================================
-- 4. ROUTINE EXECUTE PRIVILEGES HARDENING
-- =========================================================================

REVOKE EXECUTE ON FUNCTION public.register_domestic_helper(TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.update_domestic_helper(UUID, TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.set_helper_status(UUID, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.authorize_helper_for_flat(UUID, UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.revoke_helper_authorization(UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.checkin_domestic_helper(UUID, UUID, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.checkout_domestic_helper(UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.generate_helper_passcode(UUID, TEXT) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.register_domestic_helper(TEXT, TEXT, TEXT, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.update_domestic_helper(UUID, TEXT, TEXT, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.set_helper_status(UUID, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.authorize_helper_for_flat(UUID, UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.revoke_helper_authorization(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.checkin_domestic_helper(UUID, UUID, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.checkout_domestic_helper(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.generate_helper_passcode(UUID, TEXT) TO authenticated, service_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.staff_helpers TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.helper_flat_mappings TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.helper_attendance_logs TO authenticated;

COMMIT;
