-- =========================================================================
-- SU SOCIETY APP - SLICE 17 SCHEMA (OPERATIONAL LOGISTICS & COMMUNITY WORKFLOWS)
-- =========================================================================

-- \set ON_ERROR_STOP on

BEGIN;

-- =========================================================================
-- 1. LIVE-CATALOG LEGACY ROUTINE HARDENING (SLICES 5, 6, 8, 11, 12)
-- =========================================================================

REVOKE EXECUTE ON FUNCTION public.fn_cast_poll_vote(UUID, UUID, VARCHAR) FROM PUBLIC, authenticated, anon;
GRANT  EXECUTE ON FUNCTION public.fn_cast_poll_vote(UUID, UUID, VARCHAR) TO service_role;

REVOKE EXECUTE ON FUNCTION public.fn_assign_parking_slot(UUID, UUID) FROM PUBLIC, authenticated, anon;
GRANT  EXECUTE ON FUNCTION public.fn_assign_parking_slot(UUID, UUID) TO service_role;

REVOKE EXECUTE ON FUNCTION public.fn_transition_gate_pass_state(UUID, VARCHAR) FROM PUBLIC, authenticated, anon;
GRANT  EXECUTE ON FUNCTION public.fn_transition_gate_pass_state(UUID, VARCHAR) TO service_role;

REVOKE EXECUTE ON FUNCTION public.fn_transition_parcel_state(UUID, VARCHAR, VARCHAR) FROM PUBLIC, authenticated, anon;
GRANT  EXECUTE ON FUNCTION public.fn_transition_parcel_state(UUID, VARCHAR, VARCHAR) TO service_role;

REVOKE EXECUTE ON FUNCTION public.fn_transition_meter_reading_state(UUID, VARCHAR) FROM PUBLIC, authenticated, anon;
GRANT  EXECUTE ON FUNCTION public.fn_transition_meter_reading_state(UUID, VARCHAR) TO service_role;

REVOKE EXECUTE ON FUNCTION public.fn_transition_sos_alert(UUID, VARCHAR, TEXT) FROM PUBLIC, authenticated, anon;
GRANT  EXECUTE ON FUNCTION public.fn_transition_sos_alert(UUID, VARCHAR, TEXT) TO service_role;


-- =========================================================================
-- 2. HELPER FUNCTIONS
-- =========================================================================

-- Poll Option Validator Helper (IMMUTABLE)
CREATE OR REPLACE FUNCTION public.fn_validate_poll_options(p_options JSONB)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
DECLARE
    v_len INT;
    v_i INT;
    v_elem JSONB;
    v_text TEXT;
    v_norm TEXT;
    v_seen TEXT[] := '{}';
BEGIN
    IF p_options IS NULL OR jsonb_typeof(p_options) != 'array' THEN
        RETURN FALSE;
    END IF;

    v_len := jsonb_array_length(p_options);
    IF v_len < 2 THEN
        RETURN FALSE;
    END IF;

    FOR v_i IN 0 .. (v_len - 1) LOOP
        v_elem := p_options -> v_i;
        IF jsonb_typeof(v_elem) != 'string' THEN
            RETURN FALSE;
        END IF;

        v_text := TRIM(v_elem #>> '{}');
        IF v_text IS NULL OR LENGTH(v_text) = 0 THEN
            RETURN FALSE;
        END IF;

        v_norm := LOWER(v_text);
        IF v_norm = ANY(v_seen) THEN
            RETURN FALSE; -- Duplicate option detected (case/whitespace invariant)
        END IF;

        v_seen := array_append(v_seen, v_norm);
    END LOOP;

    RETURN TRUE;
END;
$$;


-- =========================================================================
-- 3. TABLES DDL
-- =========================================================================

-- 3.1 Gate Passes Table
CREATE TABLE IF NOT EXISTS public.gate_passes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    property_id UUID NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
    created_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    staff_id UUID REFERENCES public.users(id) ON DELETE RESTRICT,
    valid_from TIMESTAMPTZ NOT NULL,
    valid_until TIMESTAMPTZ NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'pending'
        CONSTRAINT chk_gate_pass_status CHECK (status IN ('pending', 'active', 'suspended', 'expired')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_gate_pass_validity CHECK (valid_from < valid_until)
);

ALTER TABLE public.gate_passes
    ADD COLUMN IF NOT EXISTS society_id UUID REFERENCES public.societies(id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS property_id UUID REFERENCES public.properties(id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES public.users(id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS staff_id UUID,
    ADD COLUMN IF NOT EXISTS valid_from TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS valid_until TIMESTAMPTZ;

ALTER TABLE public.gate_passes
    DROP CONSTRAINT IF EXISTS gate_passes_staff_id_fkey;

ALTER TABLE public.gate_passes ALTER COLUMN staff_id DROP NOT NULL;
ALTER TABLE public.gate_passes ALTER COLUMN requested_by DROP NOT NULL;

UPDATE public.gate_passes 
SET staff_id = NULL 
WHERE staff_id IS NOT NULL AND staff_id NOT IN (SELECT id FROM public.users);

ALTER TABLE public.gate_passes
    ADD CONSTRAINT gate_passes_staff_id_fkey
    FOREIGN KEY (staff_id) REFERENCES public.users(id) ON DELETE RESTRICT;

ALTER TABLE public.gate_passes DROP CONSTRAINT IF EXISTS chk_gate_pass_status;
ALTER TABLE public.gate_passes ADD CONSTRAINT chk_gate_pass_status CHECK (status IN ('pending', 'active', 'suspended', 'expired'));

-- 3.2 Parcel Logs Table
CREATE TABLE IF NOT EXISTS public.parcel_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    property_id UUID NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
    carrier_name VARCHAR(100) NOT NULL,
    tracking_number VARCHAR(100),
    recipient_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    logged_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    collection_code VARCHAR(10) CONSTRAINT chk_parcel_code_null CHECK (collection_code IS NULL),
    collection_code_hash VARCHAR(64) NOT NULL,
    failed_collection_attempts INT NOT NULL DEFAULT 0 CONSTRAINT chk_failed_attempts_nonneg CHECK (failed_collection_attempts >= 0),
    status VARCHAR(50) NOT NULL DEFAULT 'received_at_gate'
        CONSTRAINT chk_parcel_status CHECK (status IN ('received_at_gate', 'collected', 'locked_failed_attempts')),
    collected_at TIMESTAMPTZ,
    collected_by UUID REFERENCES public.users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.parcel_logs
    ADD COLUMN IF NOT EXISTS society_id UUID REFERENCES public.societies(id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS property_id UUID REFERENCES public.properties(id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS recipient_user_id UUID REFERENCES public.users(id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS logged_by UUID REFERENCES public.users(id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS collection_code_hash VARCHAR(64),
    ADD COLUMN IF NOT EXISTS failed_collection_attempts INT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS collected_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS collected_by UUID REFERENCES public.users(id) ON DELETE RESTRICT;

ALTER TABLE public.parcel_logs ALTER COLUMN collection_code DROP NOT NULL;
ALTER TABLE public.parcel_logs DROP CONSTRAINT IF EXISTS chk_parcel_status;
ALTER TABLE public.parcel_logs ADD CONSTRAINT chk_parcel_status CHECK (status IN ('received_at_gate', 'collected', 'locked_failed_attempts', 'returned'));

-- 3.3 SOS Alerts Table
CREATE TABLE IF NOT EXISTS public.sos_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    property_id UUID NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
    triggered_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    alert_type VARCHAR(50) NOT NULL DEFAULT 'general',
    status VARCHAR(50) NOT NULL DEFAULT 'triggered'
        CONSTRAINT chk_sos_status CHECK (status IN ('triggered', 'acknowledged', 'resolved', 'false_alarm')),
    acknowledged_by UUID REFERENCES public.users(id) ON DELETE RESTRICT,
    acknowledged_at TIMESTAMPTZ,
    resolved_by UUID REFERENCES public.users(id) ON DELETE RESTRICT,
    resolved_at TIMESTAMPTZ,
    resolution_notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.sos_alerts
    ADD COLUMN IF NOT EXISTS society_id UUID REFERENCES public.societies(id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS property_id UUID REFERENCES public.properties(id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS triggered_by UUID REFERENCES public.users(id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS alert_type VARCHAR(50) DEFAULT 'general',
    ADD COLUMN IF NOT EXISTS acknowledged_by UUID REFERENCES public.users(id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS acknowledged_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS resolved_by UUID REFERENCES public.users(id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS resolved_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS resolution_notes TEXT;

ALTER TABLE public.sos_alerts ALTER COLUMN raised_by DROP NOT NULL;
ALTER TABLE public.sos_alerts DROP CONSTRAINT IF EXISTS sos_alerts_alert_type_check;

CREATE UNIQUE INDEX IF NOT EXISTS uq_active_sos_alert_property 
ON public.sos_alerts(property_id) 
WHERE status IN ('triggered', 'acknowledged');

-- 3.4 Utility Meters Table
CREATE TABLE IF NOT EXISTS public.utility_meters (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    property_id UUID NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
    meter_number VARCHAR(50) NOT NULL,
    meter_type VARCHAR(50) NOT NULL DEFAULT 'electricity',
    unit_rate NUMERIC(15, 2) NOT NULL CONSTRAINT chk_unit_rate_pos CHECK (unit_rate > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_meter_number UNIQUE (society_id, meter_number)
);

ALTER TABLE public.utility_meters
    ADD COLUMN IF NOT EXISTS society_id UUID REFERENCES public.societies(id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS property_id UUID REFERENCES public.properties(id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS meter_number VARCHAR(50),
    ADD COLUMN IF NOT EXISTS meter_type VARCHAR(50) DEFAULT 'electricity',
    ADD COLUMN IF NOT EXISTS unit_rate NUMERIC(15, 2);

ALTER TABLE public.utility_meters ALTER COLUMN utility_type DROP NOT NULL;

-- 3.5 Meter Readings Table
CREATE TABLE IF NOT EXISTS public.meter_readings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    meter_id UUID NOT NULL REFERENCES public.utility_meters(id) ON DELETE RESTRICT,
    property_id UUID NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
    reading_date DATE NOT NULL,
    previous_reading NUMERIC(15, 2) NOT NULL CONSTRAINT chk_prev_reading_nonneg CHECK (previous_reading >= 0),
    current_reading NUMERIC(15, 2) NOT NULL CONSTRAINT chk_curr_reading_nonneg CHECK (current_reading >= 0),
    consumption NUMERIC(15, 2) NOT NULL CONSTRAINT chk_consumption_nonneg CHECK (consumption >= 0),
    applied_unit_rate NUMERIC(15, 2) NOT NULL CONSTRAINT chk_applied_rate_pos CHECK (applied_unit_rate > 0),
    total_amount NUMERIC(15, 2) NOT NULL CONSTRAINT chk_reading_total_nonneg CHECK (total_amount >= 0),
    submitted_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    status VARCHAR(50) NOT NULL DEFAULT 'draft'
        CONSTRAINT chk_reading_status CHECK (status IN ('draft', 'submitted', 'verified', 'billed')),
    verified_at TIMESTAMPTZ,
    verified_by UUID REFERENCES public.users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_monotonic_reading CHECK (current_reading >= previous_reading)
);

ALTER TABLE public.meter_readings
    ADD COLUMN IF NOT EXISTS meter_id UUID REFERENCES public.utility_meters(id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS property_id UUID REFERENCES public.properties(id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS reading_date DATE,
    ADD COLUMN IF NOT EXISTS previous_reading NUMERIC(15, 2) DEFAULT 0,
    ADD COLUMN IF NOT EXISTS current_reading NUMERIC(15, 2) DEFAULT 0,
    ADD COLUMN IF NOT EXISTS consumption NUMERIC(15, 2) DEFAULT 0,
    ADD COLUMN IF NOT EXISTS applied_unit_rate NUMERIC(15, 2),
    ADD COLUMN IF NOT EXISTS total_amount NUMERIC(15, 2),
    ADD COLUMN IF NOT EXISTS submitted_by UUID REFERENCES public.users(id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS verified_by UUID REFERENCES public.users(id) ON DELETE RESTRICT;

ALTER TABLE public.meter_readings ALTER COLUMN consumption DROP EXPRESSION IF EXISTS;
ALTER TABLE public.meter_readings ALTER COLUMN total_charge DROP EXPRESSION IF EXISTS;
ALTER TABLE public.meter_readings ALTER COLUMN created_by DROP NOT NULL;
ALTER TABLE public.meter_readings DROP CONSTRAINT IF EXISTS chk_reading_status;
ALTER TABLE public.meter_readings ADD CONSTRAINT chk_reading_status CHECK (status IN ('draft', 'submitted', 'verified', 'billed', 'rejected'));

-- 3.6 Parking Slots Table (Deeded Permanent Association)
CREATE TABLE IF NOT EXISTS public.parking_slots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    property_id UUID NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT, -- Permanent deeded slot ownership
    slot_number VARCHAR(50) NOT NULL,
    assigned_vehicle_id UUID, -- Dynamic assigned vehicle
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_parking_slot_number UNIQUE (society_id, slot_number)
);

ALTER TABLE public.parking_slots
    ADD COLUMN IF NOT EXISTS society_id UUID REFERENCES public.societies(id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS property_id UUID REFERENCES public.properties(id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS assigned_vehicle_id UUID;

-- 3.7 Vehicles Table
CREATE TABLE IF NOT EXISTS public.vehicles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    property_id UUID NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
    owner_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    registration_number VARCHAR(50) NOT NULL,
    vehicle_type VARCHAR(50) NOT NULL DEFAULT 'four_wheeler',
    parking_slot_id UUID REFERENCES public.parking_slots(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_vehicle_registration UNIQUE (society_id, registration_number)
);

ALTER TABLE public.vehicles
    ADD COLUMN IF NOT EXISTS society_id UUID REFERENCES public.societies(id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS property_id UUID REFERENCES public.properties(id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS owner_user_id UUID REFERENCES public.users(id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS parking_slot_id UUID REFERENCES public.parking_slots(id) ON DELETE SET NULL;

ALTER TABLE public.vehicles DROP CONSTRAINT IF EXISTS chk_vehicle_type;
ALTER TABLE public.vehicles ADD CONSTRAINT chk_vehicle_type CHECK (vehicle_type IN ('four_wheeler', 'two_wheeler', '2-wheeler', '4-wheeler'));

-- Add foreign key constraint back to vehicles from parking_slots
ALTER TABLE public.parking_slots 
    DROP CONSTRAINT IF EXISTS fk_parking_slots_assigned_vehicle,
    ADD CONSTRAINT fk_parking_slots_assigned_vehicle 
    FOREIGN KEY (assigned_vehicle_id) REFERENCES public.vehicles(id) ON DELETE SET NULL;

-- 3.8 Polls Table
CREATE TABLE IF NOT EXISTS public.polls (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    options JSONB NOT NULL CONSTRAINT chk_poll_options CHECK (public.fn_validate_poll_options(options)),
    starts_at TIMESTAMPTZ NOT NULL,
    ends_at TIMESTAMPTZ NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'draft'
        CONSTRAINT chk_poll_status CHECK (status IN ('draft', 'active', 'closed')),
    created_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_poll_schedule CHECK (starts_at < ends_at)
);

ALTER TABLE public.polls
    ADD COLUMN IF NOT EXISTS society_id UUID REFERENCES public.societies(id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES public.users(id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS options JSONB;

ALTER TABLE public.polls ALTER COLUMN description DROP NOT NULL;

-- 3.9 Poll Votes Table
CREATE TABLE IF NOT EXISTS public.poll_votes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    poll_id UUID NOT NULL REFERENCES public.polls(id) ON DELETE CASCADE,
    property_id UUID NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
    voter_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    vote_choice VARCHAR(255) NOT NULL,
    voted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_poll_property_vote UNIQUE (poll_id, property_id)
);

ALTER TABLE public.poll_votes
    ADD COLUMN IF NOT EXISTS poll_id UUID REFERENCES public.polls(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS property_id UUID REFERENCES public.properties(id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS voter_id UUID REFERENCES public.users(id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS vote_choice VARCHAR(255);


-- =========================================================================
-- 4. MUTATION PROTECTION TRIGGERS
-- =========================================================================

-- Gate Passes Direct Update Guard
CREATE OR REPLACE FUNCTION public.trg_prevent_direct_gate_pass_update_func()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF current_setting('app.workflow_context', true) IS DISTINCT FROM 'gate_pass_transition' AND auth.role() IS DISTINCT FROM 'service_role' THEN
        RAISE EXCEPTION 'Direct update on gate_passes status blocked. Use workflow procedures.' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_direct_gate_pass_update ON public.gate_passes;
CREATE TRIGGER trg_prevent_direct_gate_pass_update
    BEFORE UPDATE ON public.gate_passes
    FOR EACH ROW EXECUTE FUNCTION public.trg_prevent_direct_gate_pass_update_func();


-- Parcel Logs Direct Update Guard
CREATE OR REPLACE FUNCTION public.trg_prevent_direct_parcel_update_func()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF current_setting('app.workflow_context', true) IS DISTINCT FROM 'parcel_transition' 
       AND current_setting('app.parcel_transition', true) IS DISTINCT FROM NEW.id::text 
       AND auth.role() IS DISTINCT FROM 'service_role' THEN
        RAISE EXCEPTION 'Direct update on parcel_logs status blocked. Use workflow procedures.' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_parcel_logs_status_block ON public.parcel_logs;
DROP TRIGGER IF EXISTS trg_prevent_direct_parcel_update ON public.parcel_logs;
CREATE TRIGGER trg_prevent_direct_parcel_update
    BEFORE UPDATE ON public.parcel_logs
    FOR EACH ROW EXECUTE FUNCTION public.trg_prevent_direct_parcel_update_func();


-- SOS Alert Direct Update Guard
CREATE OR REPLACE FUNCTION public.trg_protect_sos_status_update_func()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF current_setting('app.workflow_context', true) IS DISTINCT FROM 'sos_transition' AND auth.role() IS DISTINCT FROM 'service_role' THEN
        RAISE EXCEPTION 'Direct update on sos_alerts blocked. Use workflow procedures.' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_sos_status_update ON public.sos_alerts;
CREATE TRIGGER trg_protect_sos_status_update
    BEFORE UPDATE ON public.sos_alerts
    FOR EACH ROW EXECUTE FUNCTION public.trg_protect_sos_status_update_func();


-- Meter Readings Direct Update Guard
CREATE OR REPLACE FUNCTION public.trg_prevent_direct_meter_reading_update_func()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF current_setting('app.workflow_context', true) IS DISTINCT FROM 'meter_reading_transition' AND auth.role() IS DISTINCT FROM 'service_role' THEN
        RAISE EXCEPTION 'Direct update on meter_readings status blocked. Use workflow procedures.' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_direct_meter_reading_update ON public.meter_readings;
CREATE TRIGGER trg_prevent_direct_meter_reading_update
    BEFORE UPDATE ON public.meter_readings
    FOR EACH ROW EXECUTE FUNCTION public.trg_prevent_direct_meter_reading_update_func();


-- Vehicle Deletion Auto-Release Trigger
CREATE OR REPLACE FUNCTION public.trg_vehicles_auto_release_parking_func()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    -- Unlink assigned_vehicle_id from parking_slots while preserving permanent property_id
    UPDATE public.parking_slots 
    SET assigned_vehicle_id = NULL
    WHERE assigned_vehicle_id = OLD.id;

    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_vehicles_auto_release_parking ON public.vehicles;
CREATE TRIGGER trg_vehicles_auto_release_parking
    BEFORE DELETE ON public.vehicles
    FOR EACH ROW EXECUTE FUNCTION public.trg_vehicles_auto_release_parking_func();


-- Poll Votes Mutation Defense-in-Depth Trigger
CREATE OR REPLACE FUNCTION public.trg_prevent_vote_mutations_func()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    RAISE EXCEPTION 'Direct mutation of poll_votes is prohibited.' USING ERRCODE = '42501';
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_vote_mutations ON public.poll_votes;
CREATE TRIGGER trg_prevent_vote_mutations
    BEFORE UPDATE OR DELETE ON public.poll_votes
    FOR EACH ROW EXECUTE FUNCTION public.trg_prevent_vote_mutations_func();


-- =========================================================================
-- 5. WORKFLOW ROUTINES (16 SECURITY DEFINER FUNCTIONS)
-- =========================================================================

-- 1. issue_gate_pass
CREATE OR REPLACE FUNCTION public.issue_gate_pass(
    p_society_id UUID,
    p_property_id UUID,
    p_staff_id UUID,
    p_valid_from TIMESTAMPTZ,
    p_valid_until TIMESTAMPTZ
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_caller_society UUID;
    v_is_resident BOOLEAN := FALSE;
    v_is_admin BOOLEAN := FALSE;
    v_staff_status VARCHAR;
    v_initial_status VARCHAR := 'pending';
    v_pass_id UUID;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    v_caller_society := public.get_user_society_id(v_caller);
    IF v_caller_society IS DISTINCT FROM p_society_id THEN
        RAISE EXCEPTION 'Cross-society execution denied.' USING ERRCODE = '42501';
    END IF;

    IF p_valid_from >= p_valid_until THEN
        RAISE EXCEPTION 'valid_from must be before valid_until.' USING ERRCODE = '22000';
    END IF;

    -- Verify caller active ownership/tenancy or admin
    IF EXISTS (
        SELECT 1 FROM public.property_owners WHERE property_id = p_property_id AND owner_id = v_caller AND (end_date IS NULL OR end_date >= CURRENT_DATE)
    ) OR EXISTS (
        SELECT 1 FROM public.tenancies t JOIN public.units u ON t.unit_id = u.id WHERE u.property_id = p_property_id AND t.tenant_id = v_caller AND (end_date IS NULL OR end_date >= CURRENT_DATE)
    ) THEN
        v_is_resident := TRUE;
    END IF;

    v_is_admin := public.is_admin();

    IF NOT v_is_resident AND NOT v_is_admin THEN
        RAISE EXCEPTION 'Access Denied: Caller is not an active resident or admin for target property.' USING ERRCODE = '42501';
    END IF;

    -- If staff_id is provided, verify status
    IF p_staff_id IS NOT NULL THEN
        SELECT raw_app_meta_data->>'verification_status' INTO v_staff_status
        FROM auth.users WHERE id = p_staff_id;

        IF v_staff_status = 'verified' THEN
            v_initial_status := 'active';
        END IF;
    END IF;

    PERFORM set_config('app.workflow_context', 'gate_pass_transition', true);

    INSERT INTO public.gate_passes (
        society_id, property_id, created_by, staff_id, valid_from, valid_until, status
    ) VALUES (
        p_society_id, p_property_id, v_caller, p_staff_id, p_valid_from, p_valid_until, v_initial_status
    ) RETURNING id INTO v_pass_id;

    -- Audit
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (p_society_id, v_caller, 'gate_pass', v_pass_id, 'pass_issued', jsonb_build_object('status', v_initial_status, 'property_id', p_property_id));

    -- Notification
    INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
    VALUES (p_society_id, v_caller, 'gate_pass', 'Gate Pass Issued', 'Gate pass issued with status ' || v_initial_status, 'gate_passes', v_pass_id);

    RETURN v_pass_id;
END;
$$;


-- 2. transition_gate_pass_status
CREATE OR REPLACE FUNCTION public.transition_gate_pass_status(
    p_pass_id UUID,
    p_new_status VARCHAR
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_pass RECORD;
    v_is_admin BOOLEAN := FALSE;
    v_is_gatekeeper BOOLEAN := FALSE;
    v_is_resident BOOLEAN := FALSE;
    v_staff_status VARCHAR;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_pass FROM public.gate_passes WHERE id = p_pass_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Gate pass not found.' USING ERRCODE = '22000';
    END IF;

    IF public.get_user_society_id(v_caller) IS DISTINCT FROM v_pass.society_id THEN
        RAISE EXCEPTION 'Cross-society execution denied.' USING ERRCODE = '42501';
    END IF;

    v_is_admin := public.is_admin();
    IF EXISTS (
        SELECT 1 FROM public.user_roles WHERE society_id = v_pass.society_id AND user_id = v_caller AND role_name = 'gatekeeper'
    ) THEN
        v_is_gatekeeper := TRUE;
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.property_owners WHERE property_id = v_pass.property_id AND owner_id = v_caller AND (end_date IS NULL OR end_date >= CURRENT_DATE)
    ) OR EXISTS (
        SELECT 1 FROM public.tenancies t JOIN public.units u ON t.unit_id = u.id WHERE u.property_id = v_pass.property_id AND t.tenant_id = v_caller AND (end_date IS NULL OR end_date >= CURRENT_DATE)
    ) THEN
        v_is_resident := TRUE;
    END IF;

    -- State machine check
    IF p_new_status = 'suspended' THEN
        IF NOT v_is_admin AND NOT v_is_gatekeeper AND NOT v_is_resident THEN
            RAISE EXCEPTION 'Access Denied: Cannot suspend pass.' USING ERRCODE = '42501';
        END IF;
    ELSIF p_new_status = 'active' THEN
        -- Resident reactivation BLOCKED by security rule
        IF NOT v_is_admin AND NOT v_is_gatekeeper THEN
            RAISE EXCEPTION 'Access Denied: Residents cannot reactivate suspended passes.' USING ERRCODE = '42501';
        END IF;

        IF v_pass.staff_id IS NOT NULL THEN
            SELECT raw_app_meta_data->>'verification_status' INTO v_staff_status FROM auth.users WHERE id = v_pass.staff_id;
            IF v_staff_status IS DISTINCT FROM 'verified' THEN
                RAISE EXCEPTION 'Pass cannot be activated for unverified staff.' USING ERRCODE = '22000';
            END IF;
        END IF;
    ELSE
        RAISE EXCEPTION 'Invalid target status %', p_new_status USING ERRCODE = '22000';
    END IF;

    PERFORM set_config('app.workflow_context', 'gate_pass_transition', true);

    UPDATE public.gate_passes 
    SET status = p_new_status, updated_at = NOW()
    WHERE id = p_pass_id;

    -- Audit
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_pass.society_id, v_caller, 'gate_pass', p_pass_id, 'status_transition', jsonb_build_object('old_status', v_pass.status, 'new_status', p_new_status));
END;
$$;


-- 3. log_parcel_delivery
CREATE OR REPLACE FUNCTION public.log_parcel_delivery(
    p_society_id UUID,
    p_property_id UUID,
    p_carrier_name VARCHAR,
    p_tracking_number VARCHAR,
    p_recipient_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_is_staff BOOLEAN := FALSE;
    v_rand_val BIGINT;
    v_code_int INT;
    v_code_str VARCHAR(6);
    v_code_hash VARCHAR(64);
    v_parcel_id UUID;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    IF public.get_user_society_id(v_caller) IS DISTINCT FROM p_society_id THEN
        RAISE EXCEPTION 'Cross-society execution denied.' USING ERRCODE = '42501';
    END IF;

    IF public.is_admin() OR EXISTS (
        SELECT 1 FROM public.user_roles WHERE society_id = p_society_id AND user_id = v_caller AND role_name = 'gatekeeper'
    ) THEN
        v_is_staff := TRUE;
    END IF;

    IF NOT v_is_staff THEN
        RAISE EXCEPTION 'Access Denied: Only gatekeepers and admins can log parcels.' USING ERRCODE = '42501';
    END IF;

    -- 4-Byte CSPRNG Rejection Sampling for 6-Digit Code
    LOOP
        v_rand_val := ('x' || encode(extensions.gen_random_bytes(4), 'hex'))::bit(32)::bigint;
        IF v_rand_val < 4294000000 THEN
            v_code_int := (v_rand_val % 1000000)::INT;
            EXIT;
        END IF;
    END LOOP;

    v_code_str := LPAD(v_code_int::TEXT, 6, '0');
    v_code_hash := encode(extensions.digest(v_code_str, 'sha256'), 'hex');

    INSERT INTO public.parcel_logs (
        society_id, property_id, carrier_name, tracking_number, recipient_user_id, logged_by, collection_code, collection_code_hash
    ) VALUES (
        p_society_id, p_property_id, p_carrier_name, p_tracking_number, p_recipient_user_id, v_caller, NULL, v_code_hash
    ) RETURNING id INTO v_parcel_id;

    -- Audit (Plaintext code strictly excluded)
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (p_society_id, v_caller, 'parcel', v_parcel_id, 'delivery_logged', jsonb_build_object('carrier', p_carrier_name, 'recipient_id', p_recipient_user_id));

    -- Notification (Plaintext code strictly excluded)
    INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
    VALUES (p_society_id, p_recipient_user_id, 'parcel', 'Parcel Delivered', 'A parcel from ' || p_carrier_name || ' has arrived at the gate.', 'parcel_logs', v_parcel_id);

    RETURN jsonb_build_object('parcel_id', v_parcel_id, 'collection_code', v_code_str);
END;
$$;


-- 4. collect_parcel
CREATE OR REPLACE FUNCTION public.collect_parcel(
    p_parcel_id UUID,
    p_collection_code VARCHAR
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_parcel RECORD;
    v_hash_input VARCHAR(64);
    v_is_staff BOOLEAN := FALSE;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_parcel FROM public.parcel_logs WHERE id = p_parcel_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Parcel record not found.' USING ERRCODE = '22000';
    END IF;

    IF public.get_user_society_id(v_caller) IS DISTINCT FROM v_parcel.society_id THEN
        RAISE EXCEPTION 'Cross-society execution denied.' USING ERRCODE = '42501';
    END IF;

    IF public.is_admin() OR EXISTS (
        SELECT 1 FROM public.user_roles WHERE society_id = v_parcel.society_id AND user_id = v_caller AND role_name = 'gatekeeper'
    ) THEN
        v_is_staff := TRUE;
    END IF;

    IF v_caller IS DISTINCT FROM v_parcel.recipient_user_id AND NOT v_is_staff THEN
        RAISE EXCEPTION 'Access Denied: Only recipient or staff can collect parcel.' USING ERRCODE = '42501';
    END IF;

    IF v_parcel.status = 'locked_failed_attempts' THEN
        RAISE EXCEPTION 'Parcel is locked due to 5 failed collection attempts.' USING ERRCODE = '22000';
    END IF;

    IF v_parcel.status = 'collected' THEN
        RAISE EXCEPTION 'Parcel has already been collected.' USING ERRCODE = '22000';
    END IF;

    v_hash_input := encode(extensions.digest(p_collection_code, 'sha256'), 'hex');

    PERFORM set_config('app.workflow_context', 'parcel_transition', true);
    PERFORM set_config('app.parcel_transition', p_parcel_id::text, true);

    IF v_hash_input = v_parcel.collection_code_hash THEN
        -- Success
        UPDATE public.parcel_logs 
        SET status = 'collected', collected_at = NOW(), collected_by = v_caller
        WHERE id = p_parcel_id;

        INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
        VALUES (v_parcel.society_id, v_caller, 'parcel', p_parcel_id, 'parcel_collected', jsonb_build_object('status', 'collected'));

        RETURN jsonb_build_object('success', true, 'status', 'collected');
    ELSE
        -- Failure - increment attempt counter
        IF v_parcel.failed_collection_attempts + 1 >= 5 THEN
            UPDATE public.parcel_logs 
            SET failed_collection_attempts = v_parcel.failed_collection_attempts + 1, status = 'locked_failed_attempts'
            WHERE id = p_parcel_id;

            RETURN jsonb_build_object('success', false, 'status', 'locked_failed_attempts', 'failed_attempts', 5);
        ELSE
            UPDATE public.parcel_logs 
            SET failed_collection_attempts = v_parcel.failed_collection_attempts + 1
            WHERE id = p_parcel_id;

            RETURN jsonb_build_object('success', false, 'status', 'received_at_gate', 'failed_attempts', v_parcel.failed_collection_attempts + 1);
        END IF;
    END IF;
END;
$$;


-- 5. trigger_sos_alert
CREATE OR REPLACE FUNCTION public.trigger_sos_alert(
    p_society_id UUID,
    p_property_id UUID,
    p_alert_type VARCHAR
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_sos_id UUID;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    IF public.get_user_society_id(v_caller) IS DISTINCT FROM p_society_id THEN
        RAISE EXCEPTION 'Cross-society execution denied.' USING ERRCODE = '42501';
    END IF;

    -- Verify active resident
    IF NOT EXISTS (
        SELECT 1 FROM public.property_owners WHERE property_id = p_property_id AND owner_id = v_caller AND (end_date IS NULL OR end_date >= CURRENT_DATE)
    ) AND NOT EXISTS (
        SELECT 1 FROM public.tenancies t JOIN public.units u ON t.unit_id = u.id WHERE u.property_id = p_property_id AND t.tenant_id = v_caller AND (end_date IS NULL OR end_date >= CURRENT_DATE)
    ) THEN
        RAISE EXCEPTION 'Access Denied: Caller is not an active resident of target property.' USING ERRCODE = '42501';
    END IF;

    -- Trigger alert
    INSERT INTO public.sos_alerts (
        society_id, property_id, triggered_by, alert_type, status
    ) VALUES (
        p_society_id, p_property_id, v_caller, COALESCE(p_alert_type, 'general'), 'triggered'
    ) RETURNING id INTO v_sos_id;

    -- Audit
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (p_society_id, v_caller, 'sos_alert', v_sos_id, 'sos_triggered', jsonb_build_object('alert_type', p_alert_type, 'property_id', p_property_id));

    RETURN v_sos_id;
END;
$$;


-- 6. acknowledge_sos_alert
CREATE OR REPLACE FUNCTION public.acknowledge_sos_alert(
    p_alert_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_alert RECORD;
    v_is_staff BOOLEAN := FALSE;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_alert FROM public.sos_alerts WHERE id = p_alert_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'SOS alert record not found.' USING ERRCODE = '22000';
    END IF;

    IF public.get_user_society_id(v_caller) IS DISTINCT FROM v_alert.society_id THEN
        RAISE EXCEPTION 'Cross-society execution denied.' USING ERRCODE = '42501';
    END IF;

    IF public.is_admin() OR EXISTS (
        SELECT 1 FROM public.user_roles WHERE society_id = v_alert.society_id AND user_id = v_caller AND role_name = 'gatekeeper'
    ) THEN
        v_is_staff := TRUE;
    END IF;

    IF NOT v_is_staff THEN
        RAISE EXCEPTION 'Access Denied: Only gatekeepers or admins can acknowledge SOS alerts.' USING ERRCODE = '42501';
    END IF;

    IF v_alert.status IS DISTINCT FROM 'triggered' THEN
        RAISE EXCEPTION 'SOS alert is not in triggered status.' USING ERRCODE = '22000';
    END IF;

    PERFORM set_config('app.workflow_context', 'sos_transition', true);

    UPDATE public.sos_alerts 
    SET status = 'acknowledged', acknowledged_by = v_caller, acknowledged_at = NOW()
    WHERE id = p_alert_id;

    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_alert.society_id, v_caller, 'sos_alert', p_alert_id, 'sos_acknowledged', jsonb_build_object('status', 'acknowledged'));
END;
$$;


-- 7. resolve_sos_alert
CREATE OR REPLACE FUNCTION public.resolve_sos_alert(
    p_alert_id UUID,
    p_resolution_status VARCHAR,
    p_resolution_notes TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_alert RECORD;
    v_is_staff BOOLEAN := FALSE;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    IF p_resolution_notes IS NULL OR LENGTH(TRIM(p_resolution_notes)) = 0 THEN
        RAISE EXCEPTION 'Resolution notes are mandatory.' USING ERRCODE = '22000';
    END IF;

    IF p_resolution_status NOT IN ('resolved', 'false_alarm') THEN
        RAISE EXCEPTION 'Target resolution status must be resolved or false_alarm.' USING ERRCODE = '22000';
    END IF;

    SELECT * INTO v_alert FROM public.sos_alerts WHERE id = p_alert_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'SOS alert record not found.' USING ERRCODE = '22000';
    END IF;

    IF public.get_user_society_id(v_caller) IS DISTINCT FROM v_alert.society_id THEN
        RAISE EXCEPTION 'Cross-society execution denied.' USING ERRCODE = '42501';
    END IF;

    IF public.is_admin() OR EXISTS (
        SELECT 1 FROM public.user_roles WHERE society_id = v_alert.society_id AND user_id = v_caller AND role_name = 'gatekeeper'
    ) THEN
        v_is_staff := TRUE;
    END IF;

    IF NOT v_is_staff THEN
        RAISE EXCEPTION 'Access Denied: Only gatekeepers or admins can resolve SOS alerts.' USING ERRCODE = '42501';
    END IF;

    IF v_alert.status IN ('resolved', 'false_alarm') THEN
        RAISE EXCEPTION 'SOS alert is already resolved.' USING ERRCODE = '22000';
    END IF;

    PERFORM set_config('app.workflow_context', 'sos_transition', true);

    UPDATE public.sos_alerts 
    SET status = p_resolution_status, resolved_by = v_caller, resolved_at = NOW(), resolution_notes = p_resolution_notes
    WHERE id = p_alert_id;

    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_alert.society_id, v_caller, 'sos_alert', p_alert_id, 'sos_resolved', jsonb_build_object('status', p_resolution_status, 'notes', p_resolution_notes));
END;
$$;


-- 8. submit_meter_reading
CREATE OR REPLACE FUNCTION public.submit_meter_reading(
    p_meter_id UUID,
    p_reading_date DATE,
    p_current_reading NUMERIC
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_meter RECORD;
    v_last_reading RECORD;
    v_prev_val NUMERIC := 0;
    v_consumption NUMERIC;
    v_total_amt NUMERIC;
    v_reading_id UUID;
    v_is_resident BOOLEAN := FALSE;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_meter FROM public.utility_meters WHERE id = p_meter_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Utility meter not found.' USING ERRCODE = '22000';
    END IF;

    IF public.get_user_society_id(v_caller) IS DISTINCT FROM v_meter.society_id THEN
        RAISE EXCEPTION 'Cross-society execution denied.' USING ERRCODE = '42501';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.property_owners WHERE property_id = v_meter.property_id AND owner_id = v_caller AND (end_date IS NULL OR end_date >= CURRENT_DATE)
    ) OR EXISTS (
        SELECT 1 FROM public.tenancies t JOIN public.units u ON t.unit_id = u.id WHERE u.property_id = v_meter.property_id AND t.tenant_id = v_caller AND (end_date IS NULL OR end_date >= CURRENT_DATE)
    ) THEN
        v_is_resident := TRUE;
    END IF;

    IF NOT v_is_resident AND NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access Denied: Resident of property or admin required.' USING ERRCODE = '42501';
    END IF;

    -- Fetch latest reading
    SELECT * INTO v_last_reading FROM public.meter_readings WHERE meter_id = p_meter_id ORDER BY reading_date DESC LIMIT 1;
    IF FOUND THEN
        IF p_reading_date <= v_last_reading.reading_date THEN
            RAISE EXCEPTION 'reading_date must be after last reading date.' USING ERRCODE = '22000';
        END IF;
        IF p_current_reading < v_last_reading.current_reading THEN
            RAISE EXCEPTION 'current_reading cannot be less than previous reading.' USING ERRCODE = '22000';
        END IF;
        v_prev_val := v_last_reading.current_reading;
    END IF;

    v_consumption := p_current_reading - v_prev_val;
    v_total_amt := v_consumption * v_meter.unit_rate;

    PERFORM set_config('app.workflow_context', 'meter_reading_transition', true);

    INSERT INTO public.meter_readings (
        meter_id, property_id, reading_date, previous_reading, current_reading, consumption, applied_unit_rate, total_amount, submitted_by, status
    ) VALUES (
        p_meter_id, v_meter.property_id, p_reading_date, v_prev_val, p_current_reading, v_consumption, v_meter.unit_rate, v_total_amt, v_caller, 'submitted'
    ) RETURNING id INTO v_reading_id;

    RETURN v_reading_id;
END;
$$;


-- 9. verify_and_bill_meter_reading
CREATE OR REPLACE FUNCTION public.verify_and_bill_meter_reading(
    p_reading_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_reading RECORD;
    v_meter RECORD;
    v_target_user UUID;
    v_ledger_id UUID;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access Denied: Only admin can verify and bill meter readings.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_reading FROM public.meter_readings WHERE id = p_reading_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Meter reading record not found.' USING ERRCODE = '22000';
    END IF;

    SELECT * INTO v_meter FROM public.utility_meters WHERE id = v_reading.meter_id;

    IF public.get_user_society_id(v_caller) IS DISTINCT FROM v_meter.society_id THEN
        RAISE EXCEPTION 'Cross-society execution denied.' USING ERRCODE = '42501';
    END IF;

    IF v_reading.status = 'billed' THEN
        RAISE EXCEPTION 'Meter reading is already billed.' USING ERRCODE = '22000';
    END IF;

    -- Derive target debit user (primary owner or tenant)
    SELECT owner_id INTO v_target_user 
    FROM public.property_owners 
    WHERE property_id = v_reading.property_id AND (end_date IS NULL OR end_date >= CURRENT_DATE) 
    LIMIT 1;

    IF v_target_user IS NULL THEN
        SELECT t.tenant_id INTO v_target_user 
        FROM public.tenancies t JOIN public.units u ON t.unit_id = u.id 
        WHERE u.property_id = v_reading.property_id AND (end_date IS NULL OR end_date >= CURRENT_DATE) 
        LIMIT 1;
    END IF;

    IF v_target_user IS NULL THEN
        v_target_user := v_reading.submitted_by;
    END IF;

    -- Post to Ledger
    INSERT INTO public.ledger_transactions (
        society_id, scope, property_id, amount, direction, transaction_type, source_meter_reading_id, description, created_by
    ) VALUES (
        v_meter.society_id, 'property', v_reading.property_id, v_reading.total_amount, 'debit', 'utility_bill',
        p_reading_id, 'Utility bill reading for meter ' || v_meter.meter_number, v_target_user
    ) RETURNING id INTO v_ledger_id;

    PERFORM set_config('app.workflow_context', 'meter_reading_transition', true);

    UPDATE public.meter_readings 
    SET status = 'billed', verified_at = NOW(), verified_by = v_caller
    WHERE id = p_reading_id;

    -- Audit
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_meter.society_id, v_caller, 'meter_reading', p_reading_id, 'reading_billed', jsonb_build_object('amount', v_reading.total_amount, 'ledger_id', v_ledger_id));

    RETURN v_ledger_id;
END;
$$;


-- 10. register_vehicle
CREATE OR REPLACE FUNCTION public.register_vehicle(
    p_society_id UUID,
    p_property_id UUID,
    p_registration_number VARCHAR,
    p_vehicle_type VARCHAR
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_vehicle_id UUID;
    v_is_resident BOOLEAN := FALSE;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    IF public.get_user_society_id(v_caller) IS DISTINCT FROM p_society_id THEN
        RAISE EXCEPTION 'Cross-society execution denied.' USING ERRCODE = '42501';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.property_owners WHERE property_id = p_property_id AND owner_id = v_caller AND (end_date IS NULL OR end_date >= CURRENT_DATE)
    ) OR EXISTS (
        SELECT 1 FROM public.tenancies t JOIN public.units u ON t.unit_id = u.id WHERE u.property_id = p_property_id AND t.tenant_id = v_caller AND (end_date IS NULL OR end_date >= CURRENT_DATE)
    ) THEN
        v_is_resident := TRUE;
    END IF;

    IF NOT v_is_resident AND NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access Denied: Resident of property or admin required.' USING ERRCODE = '42501';
    END IF;

    INSERT INTO public.vehicles (
        society_id, property_id, owner_user_id, registration_number, vehicle_type
    ) VALUES (
        p_society_id, p_property_id, v_caller, UPPER(TRIM(p_registration_number)), COALESCE(p_vehicle_type, 'four_wheeler')
    ) RETURNING id INTO v_vehicle_id;

    RETURN v_vehicle_id;
END;
$$;


-- 11. assign_parking_slot (Canonical Lock Order)
CREATE OR REPLACE FUNCTION public.assign_parking_slot(
    p_society_id UUID,
    p_parking_slot_id UUID,
    p_vehicle_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_slot RECORD;
    v_vehicle RECORD;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access Denied: Only admin can assign parking slots.' USING ERRCODE = '42501';
    END IF;

    IF public.get_user_society_id(v_caller) IS DISTINCT FROM p_society_id THEN
        RAISE EXCEPTION 'Cross-society execution denied.' USING ERRCODE = '42501';
    END IF;

    -- Canonical Lock Order: Lock parking_slots first FOR UPDATE ORDER BY id, then vehicles
    SELECT * INTO v_slot FROM public.parking_slots WHERE id = p_parking_slot_id AND society_id = p_society_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Parking slot not found.' USING ERRCODE = '22000';
    END IF;

    SELECT * INTO v_vehicle FROM public.vehicles WHERE id = p_vehicle_id AND society_id = p_society_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Vehicle not found.' USING ERRCODE = '22000';
    END IF;

    IF v_slot.assigned_vehicle_id IS NOT NULL AND v_slot.assigned_vehicle_id IS DISTINCT FROM p_vehicle_id THEN
        RAISE EXCEPTION 'Parking slot is already occupied.' USING ERRCODE = '22000';
    END IF;

    IF v_vehicle.parking_slot_id IS NOT NULL AND v_vehicle.parking_slot_id IS DISTINCT FROM p_parking_slot_id THEN
        RAISE EXCEPTION 'Vehicle is already assigned to another slot.' USING ERRCODE = '22000';
    END IF;

    -- Update reciprocal pointers
    UPDATE public.parking_slots SET assigned_vehicle_id = p_vehicle_id WHERE id = p_parking_slot_id;
    UPDATE public.vehicles SET parking_slot_id = p_parking_slot_id WHERE id = p_vehicle_id;
END;
$$;


-- 12. release_parking_slot (Canonical Lock Order)
CREATE OR REPLACE FUNCTION public.release_parking_slot(
    p_society_id UUID,
    p_parking_slot_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_slot RECORD;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access Denied: Only admin can release parking slots.' USING ERRCODE = '42501';
    END IF;

    IF public.get_user_society_id(v_caller) IS DISTINCT FROM p_society_id THEN
        RAISE EXCEPTION 'Cross-society execution denied.' USING ERRCODE = '42501';
    END IF;

    -- Canonical Lock Order
    SELECT * INTO v_slot FROM public.parking_slots WHERE id = p_parking_slot_id AND society_id = p_society_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Parking slot not found.' USING ERRCODE = '22000';
    END IF;

    IF v_slot.assigned_vehicle_id IS NOT NULL THEN
        UPDATE public.vehicles SET parking_slot_id = NULL WHERE id = v_slot.assigned_vehicle_id;
    END IF;

    -- Clear vehicle pointer; permanent deeded property_id is NEVER modified
    UPDATE public.parking_slots SET assigned_vehicle_id = NULL WHERE id = p_parking_slot_id;
END;
$$;


-- 13. create_community_poll
CREATE OR REPLACE FUNCTION public.create_community_poll(
    p_society_id UUID,
    p_title VARCHAR,
    p_description TEXT,
    p_options JSONB,
    p_starts_at TIMESTAMPTZ,
    p_ends_at TIMESTAMPTZ
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_poll_id UUID;
    v_status VARCHAR := 'draft';
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    IF public.get_user_society_id(v_caller) IS DISTINCT FROM p_society_id THEN
        RAISE EXCEPTION 'Cross-society execution denied.' USING ERRCODE = '42501';
    END IF;

    IF NOT public.is_admin() AND NOT EXISTS (
        SELECT 1 FROM public.user_roles WHERE society_id = p_society_id AND user_id = v_caller AND role_name IN ('committee_member', 'secretary', 'treasurer')
    ) THEN
        RAISE EXCEPTION 'Access Denied: Only admin or committee member can create polls.' USING ERRCODE = '42501';
    END IF;

    IF NOT public.fn_validate_poll_options(p_options) THEN
        RAISE EXCEPTION 'Invalid poll options format or duplicates.' USING ERRCODE = '23514';
    END IF;

    IF p_starts_at >= p_ends_at THEN
        RAISE EXCEPTION 'starts_at must be before ends_at.' USING ERRCODE = '22000';
    END IF;

    IF NOW() >= p_starts_at THEN
        v_status := 'active';
    END IF;

    INSERT INTO public.polls (
        society_id, title, description, options, starts_at, ends_at, status, created_by
    ) VALUES (
        p_society_id, p_title, p_description, p_options, p_starts_at, p_ends_at, v_status, v_caller
    ) RETURNING id INTO v_poll_id;

    RETURN v_poll_id;
END;
$$;


-- 14. cast_poll_vote
CREATE OR REPLACE FUNCTION public.cast_poll_vote(
    p_poll_id UUID,
    p_property_id UUID,
    p_vote_choice VARCHAR
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_poll RECORD;
    v_norm_choice VARCHAR;
    v_valid_choice BOOLEAN := FALSE;
    v_opt JSONB;
    v_vote_id UUID;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_poll FROM public.polls WHERE id = p_poll_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Poll not found.' USING ERRCODE = '22000';
    END IF;

    IF public.get_user_society_id(v_caller) IS DISTINCT FROM v_poll.society_id THEN
        RAISE EXCEPTION 'Cross-society execution denied.' USING ERRCODE = '42501';
    END IF;

    IF v_poll.status IS DISTINCT FROM 'active' OR NOW() < v_poll.starts_at OR NOW() > v_poll.ends_at THEN
        RAISE EXCEPTION 'Poll is not currently active for voting.' USING ERRCODE = '22000';
    END IF;

    -- Verify active resident
    IF NOT EXISTS (
        SELECT 1 FROM public.property_owners WHERE property_id = p_property_id AND owner_id = v_caller AND (end_date IS NULL OR end_date >= CURRENT_DATE)
    ) AND NOT EXISTS (
        SELECT 1 FROM public.tenancies t JOIN public.units u ON t.unit_id = u.id WHERE u.property_id = p_property_id AND t.tenant_id = v_caller AND (end_date IS NULL OR end_date >= CURRENT_DATE)
    ) THEN
        RAISE EXCEPTION 'Access Denied: Caller is not an active resident of property.' USING ERRCODE = '42501';
    END IF;

    -- Validate choice against poll options
    v_norm_choice := LOWER(TRIM(p_vote_choice));
    FOR v_opt IN SELECT * FROM jsonb_array_elements(v_poll.options) LOOP
        IF LOWER(TRIM(v_opt #>> '{}')) = v_norm_choice THEN
            v_valid_choice := TRUE;
            EXIT;
        END IF;
    END LOOP;

    IF NOT v_valid_choice THEN
        RAISE EXCEPTION 'Invalid vote choice for this poll.' USING ERRCODE = '22000';
    END IF;

    -- Insert vote (Runs as SECURITY DEFINER postgres owner, BYPASSRLS)
    INSERT INTO public.poll_votes (
        poll_id, property_id, voter_id, vote_choice
    ) VALUES (
        p_poll_id, p_property_id, v_caller, TRIM(p_vote_choice)
    ) RETURNING id INTO v_vote_id;

    RETURN v_vote_id;
END;
$$;


-- 15. close_community_poll
CREATE OR REPLACE FUNCTION public.close_community_poll(
    p_poll_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_poll RECORD;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access Denied: Only admin can close polls.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_poll FROM public.polls WHERE id = p_poll_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Poll not found.' USING ERRCODE = '22000';
    END IF;

    IF public.get_user_society_id(v_caller) IS DISTINCT FROM v_poll.society_id THEN
        RAISE EXCEPTION 'Cross-society execution denied.' USING ERRCODE = '42501';
    END IF;

    IF NOW() < v_poll.ends_at THEN
        RAISE EXCEPTION 'Cannot close poll before ends_at time.' USING ERRCODE = '22000';
    END IF;

    UPDATE public.polls SET status = 'closed' WHERE id = p_poll_id;
END;
$$;


-- 16. get_poll_results
CREATE OR REPLACE FUNCTION public.get_poll_results(
    p_poll_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_poll RECORD;
    v_is_admin BOOLEAN := FALSE;
    v_total_votes INT := 0;
    v_results JSONB := '[]'::jsonb;
    v_opt JSONB;
    v_opt_text TEXT;
    v_count INT;
    v_pct NUMERIC(5,2);
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_poll FROM public.polls WHERE id = p_poll_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Poll not found.' USING ERRCODE = '22000';
    END IF;

    IF public.get_user_society_id(v_caller) IS DISTINCT FROM v_poll.society_id THEN
        RAISE EXCEPTION 'Cross-society execution denied.' USING ERRCODE = '42501';
    END IF;

    v_is_admin := public.is_admin();

    -- Active poll confidentiality rule: non-admin member queries rejected
    IF v_poll.status IS DISTINCT FROM 'closed' AND NOW() < v_poll.ends_at AND NOT v_is_admin THEN
        RAISE EXCEPTION 'Access Denied: Results for active polls are confidential.' USING ERRCODE = '22000';
    END IF;

    SELECT COUNT(*) INTO v_total_votes FROM public.poll_votes WHERE poll_id = p_poll_id;

    FOR v_opt IN SELECT * FROM jsonb_array_elements(v_poll.options) LOOP
        v_opt_text := TRIM(v_opt #>> '{}');
        
        SELECT COUNT(*) INTO v_count 
        FROM public.poll_votes 
        WHERE poll_id = p_poll_id AND LOWER(TRIM(vote_choice)) = LOWER(v_opt_text);

        IF v_total_votes > 0 THEN
            v_pct := ROUND((v_count::NUMERIC / v_total_votes::NUMERIC) * 100.0, 2);
        ELSE
            v_pct := 0.00;
        END IF;

        v_results := v_results || jsonb_build_object(
            'option', v_opt_text,
            'votes', v_count,
            'percentage', v_pct
        );
    END LOOP;

    RETURN jsonb_build_object(
        'poll_id', p_poll_id,
        'title', v_poll.title,
        'status', v_poll.status,
        'total_votes', v_total_votes,
        'results', v_results
    );
END;
$$;


-- =========================================================================
-- 6. ROUTINE EXECUTE PRIVILEGES HARDENING
-- =========================================================================

-- Revoke EXECUTE on all 16 new routines from PUBLIC, anon, authenticated
REVOKE EXECUTE ON FUNCTION public.issue_gate_pass(UUID, UUID, UUID, TIMESTAMPTZ, TIMESTAMPTZ) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.transition_gate_pass_status(UUID, VARCHAR) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.log_parcel_delivery(UUID, UUID, VARCHAR, VARCHAR, UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.collect_parcel(UUID, VARCHAR) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.trigger_sos_alert(UUID, UUID, VARCHAR) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.acknowledge_sos_alert(UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.resolve_sos_alert(UUID, VARCHAR, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.submit_meter_reading(UUID, DATE, NUMERIC) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.verify_and_bill_meter_reading(UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.register_vehicle(UUID, UUID, VARCHAR, VARCHAR) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.assign_parking_slot(UUID, UUID, UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.release_parking_slot(UUID, UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.create_community_poll(UUID, VARCHAR, TEXT, JSONB, TIMESTAMPTZ, TIMESTAMPTZ) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.cast_poll_vote(UUID, UUID, VARCHAR) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.close_community_poll(UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_poll_results(UUID) FROM PUBLIC, anon, authenticated;

-- Grant EXECUTE to authenticated and service_role
GRANT EXECUTE ON FUNCTION public.issue_gate_pass(UUID, UUID, UUID, TIMESTAMPTZ, TIMESTAMPTZ) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.transition_gate_pass_status(UUID, VARCHAR) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.log_parcel_delivery(UUID, UUID, VARCHAR, VARCHAR, UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.collect_parcel(UUID, VARCHAR) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.trigger_sos_alert(UUID, UUID, VARCHAR) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.acknowledge_sos_alert(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.resolve_sos_alert(UUID, VARCHAR, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.submit_meter_reading(UUID, DATE, NUMERIC) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.verify_and_bill_meter_reading(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.register_vehicle(UUID, UUID, VARCHAR, VARCHAR) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.assign_parking_slot(UUID, UUID, UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.release_parking_slot(UUID, UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.create_community_poll(UUID, VARCHAR, TEXT, JSONB, TIMESTAMPTZ, TIMESTAMPTZ) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.cast_poll_vote(UUID, UUID, VARCHAR) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.close_community_poll(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_poll_results(UUID) TO authenticated, service_role;


-- =========================================================================
-- 7. ROW LEVEL SECURITY POLICIES (ALL 9 TABLES)
-- =========================================================================

-- 7.1 gate_passes RLS
ALTER TABLE public.gate_passes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gate_passes FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_gate_passes_restrictive_insert ON public.gate_passes;
CREATE POLICY pol_gate_passes_restrictive_insert ON public.gate_passes AS RESTRICTIVE FOR INSERT WITH CHECK (false);

DROP POLICY IF EXISTS pol_gate_passes_restrictive_update ON public.gate_passes;
CREATE POLICY pol_gate_passes_restrictive_update ON public.gate_passes AS RESTRICTIVE FOR UPDATE USING (false);

DROP POLICY IF EXISTS pol_gate_passes_restrictive_delete ON public.gate_passes;
CREATE POLICY pol_gate_passes_restrictive_delete ON public.gate_passes AS RESTRICTIVE FOR DELETE USING (false);

DROP POLICY IF EXISTS pol_gate_passes_select ON public.gate_passes;
CREATE POLICY pol_gate_passes_select ON public.gate_passes FOR SELECT USING (
    public.is_admin() OR
    created_by = auth.uid() OR
    property_id IN (SELECT property_id FROM public.property_owners WHERE owner_id = auth.uid()) OR
    property_id IN (SELECT u.property_id FROM public.tenancies t JOIN public.units u ON t.unit_id = u.id WHERE t.tenant_id = auth.uid())
);

-- 7.2 parcel_logs RLS
ALTER TABLE public.parcel_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.parcel_logs FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_parcel_restrictive_insert ON public.parcel_logs;
CREATE POLICY pol_parcel_restrictive_insert ON public.parcel_logs AS RESTRICTIVE FOR INSERT WITH CHECK (false);

DROP POLICY IF EXISTS pol_parcel_update_none ON public.parcel_logs;
CREATE POLICY pol_parcel_update_none ON public.parcel_logs AS RESTRICTIVE FOR UPDATE USING (false);

DROP POLICY IF EXISTS pol_parcel_delete_none ON public.parcel_logs;
CREATE POLICY pol_parcel_delete_none ON public.parcel_logs AS RESTRICTIVE FOR DELETE USING (false);

DROP POLICY IF EXISTS pol_parcel_select ON public.parcel_logs;
CREATE POLICY pol_parcel_select ON public.parcel_logs FOR SELECT USING (
    public.is_admin() OR
    recipient_user_id = auth.uid() OR
    EXISTS (SELECT 1 FROM public.user_roles WHERE society_id = parcel_logs.society_id AND user_id = auth.uid() AND role_name = 'gatekeeper')
);

-- 7.3 sos_alerts RLS
ALTER TABLE public.sos_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sos_alerts FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_sos_restrictive_insert ON public.sos_alerts;
CREATE POLICY pol_sos_restrictive_insert ON public.sos_alerts AS RESTRICTIVE FOR INSERT WITH CHECK (false);

DROP POLICY IF EXISTS pol_sos_restrictive_update ON public.sos_alerts;
CREATE POLICY pol_sos_restrictive_update ON public.sos_alerts AS RESTRICTIVE FOR UPDATE USING (false);

DROP POLICY IF EXISTS policy_sos_delete ON public.sos_alerts;
CREATE POLICY policy_sos_delete ON public.sos_alerts AS RESTRICTIVE FOR DELETE USING (false);

DROP POLICY IF EXISTS pol_sos_select ON public.sos_alerts;
CREATE POLICY pol_sos_select ON public.sos_alerts FOR SELECT USING (
    public.is_admin() OR
    triggered_by = auth.uid() OR
    EXISTS (SELECT 1 FROM public.user_roles WHERE society_id = sos_alerts.society_id AND user_id = auth.uid() AND role_name = 'gatekeeper')
);

-- 7.4 utility_meters RLS
ALTER TABLE public.utility_meters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.utility_meters FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_utility_meters_restrictive_delete ON public.utility_meters;
CREATE POLICY pol_utility_meters_restrictive_delete ON public.utility_meters AS RESTRICTIVE FOR DELETE USING (false);

DROP POLICY IF EXISTS pol_utility_meters_admin_all ON public.utility_meters;
CREATE POLICY pol_utility_meters_admin_all ON public.utility_meters FOR ALL USING (public.is_admin());

DROP POLICY IF EXISTS pol_utility_meters_select_member ON public.utility_meters;
CREATE POLICY pol_utility_meters_select_member ON public.utility_meters FOR SELECT USING (
    society_id = public.get_user_society_id(auth.uid())
);

-- 7.5 meter_readings RLS
ALTER TABLE public.meter_readings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meter_readings FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_meter_readings_restrictive_insert ON public.meter_readings;
CREATE POLICY pol_meter_readings_restrictive_insert ON public.meter_readings AS RESTRICTIVE FOR INSERT WITH CHECK (false);

DROP POLICY IF EXISTS pol_meter_readings_restrictive_update ON public.meter_readings;
CREATE POLICY pol_meter_readings_restrictive_update ON public.meter_readings AS RESTRICTIVE FOR UPDATE USING (false);

DROP POLICY IF EXISTS pol_meter_readings_restrictive_delete ON public.meter_readings;
CREATE POLICY pol_meter_readings_restrictive_delete ON public.meter_readings AS RESTRICTIVE FOR DELETE USING (false);

DROP POLICY IF EXISTS pol_meter_readings_select ON public.meter_readings;
CREATE POLICY pol_meter_readings_select ON public.meter_readings FOR SELECT USING (
    public.is_admin() OR
    submitted_by = auth.uid() OR
    property_id IN (SELECT property_id FROM public.property_owners WHERE owner_id = auth.uid()) OR
    property_id IN (SELECT u.property_id FROM public.tenancies t JOIN public.units u ON t.unit_id = u.id WHERE t.tenant_id = auth.uid())
);

-- 7.6 parking_slots RLS
ALTER TABLE public.parking_slots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.parking_slots FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_slots_restrictive_update ON public.parking_slots;
CREATE POLICY pol_slots_restrictive_update ON public.parking_slots AS RESTRICTIVE FOR UPDATE USING (false);

DROP POLICY IF EXISTS pol_slots_restrictive_delete ON public.parking_slots;
CREATE POLICY pol_slots_restrictive_delete ON public.parking_slots AS RESTRICTIVE FOR DELETE USING (false);

DROP POLICY IF EXISTS pol_slots_admin_all ON public.parking_slots;
CREATE POLICY pol_slots_admin_all ON public.parking_slots FOR ALL USING (public.is_admin());

DROP POLICY IF EXISTS pol_slots_select_member ON public.parking_slots;
CREATE POLICY pol_slots_select_member ON public.parking_slots FOR SELECT USING (
    society_id = public.get_user_society_id(auth.uid())
);

-- 7.7 vehicles RLS
ALTER TABLE public.vehicles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vehicles FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_vehicles_restrictive_insert ON public.vehicles;
CREATE POLICY pol_vehicles_restrictive_insert ON public.vehicles AS RESTRICTIVE FOR INSERT WITH CHECK (false);

DROP POLICY IF EXISTS pol_vehicles_restrictive_update ON public.vehicles;
CREATE POLICY pol_vehicles_restrictive_update ON public.vehicles AS RESTRICTIVE FOR UPDATE USING (false);

DROP POLICY IF EXISTS pol_vehicles_delete_resident ON public.vehicles;
CREATE POLICY pol_vehicles_delete_resident ON public.vehicles FOR DELETE USING (
    owner_user_id = auth.uid() OR public.is_admin()
);

DROP POLICY IF EXISTS pol_vehicles_select ON public.vehicles;
CREATE POLICY pol_vehicles_select ON public.vehicles FOR SELECT USING (
    society_id = public.get_user_society_id(auth.uid())
);

-- 7.8 polls RLS
ALTER TABLE public.polls ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.polls FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_polls_restrictive_insert ON public.polls;
CREATE POLICY pol_polls_restrictive_insert ON public.polls AS RESTRICTIVE FOR INSERT WITH CHECK (false);

DROP POLICY IF EXISTS pol_polls_restrictive_update ON public.polls;
CREATE POLICY pol_polls_restrictive_update ON public.polls AS RESTRICTIVE FOR UPDATE USING (false);

DROP POLICY IF EXISTS pol_polls_restrictive_delete ON public.polls;
CREATE POLICY pol_polls_restrictive_delete ON public.polls AS RESTRICTIVE FOR DELETE USING (false);

DROP POLICY IF EXISTS pol_polls_select ON public.polls;
CREATE POLICY pol_polls_select ON public.polls FOR SELECT USING (
    society_id = public.get_user_society_id(auth.uid())
);

-- 7.9 poll_votes RLS
ALTER TABLE public.poll_votes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.poll_votes FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_poll_votes_restrictive_insert ON public.poll_votes;
CREATE POLICY pol_poll_votes_restrictive_insert ON public.poll_votes AS RESTRICTIVE FOR INSERT WITH CHECK (false);

DROP POLICY IF EXISTS pol_poll_votes_restrictive_update ON public.poll_votes;
CREATE POLICY pol_poll_votes_restrictive_update ON public.poll_votes AS RESTRICTIVE FOR UPDATE USING (false);

DROP POLICY IF EXISTS pol_poll_votes_restrictive_delete ON public.poll_votes;
CREATE POLICY pol_poll_votes_restrictive_delete ON public.poll_votes AS RESTRICTIVE FOR DELETE USING (false);

DROP POLICY IF EXISTS pol_poll_votes_select ON public.poll_votes;
CREATE POLICY pol_poll_votes_select ON public.poll_votes FOR SELECT USING (
    voter_id = auth.uid() OR public.is_admin()
);


-- =========================================================================
-- 8. TABLE GRANTS
-- =========================================================================

GRANT SELECT ON public.gate_passes TO authenticated;
GRANT SELECT ON public.parcel_logs TO authenticated;
GRANT SELECT ON public.sos_alerts TO authenticated;
GRANT SELECT ON public.utility_meters TO authenticated;
GRANT SELECT ON public.meter_readings TO authenticated;
GRANT SELECT ON public.parking_slots TO authenticated;
GRANT SELECT, DELETE ON public.vehicles TO authenticated;
GRANT SELECT ON public.polls TO authenticated;
GRANT SELECT ON public.poll_votes TO authenticated;

-- Service Role Grants
GRANT ALL ON TABLE public.gate_passes TO service_role;
GRANT ALL ON TABLE public.parcel_logs TO service_role;
GRANT ALL ON TABLE public.sos_alerts TO service_role;
GRANT ALL ON TABLE public.utility_meters TO service_role;
GRANT ALL ON TABLE public.meter_readings TO service_role;
GRANT ALL ON TABLE public.parking_slots TO service_role;
GRANT ALL ON TABLE public.vehicles TO service_role;
GRANT ALL ON TABLE public.polls TO service_role;
GRANT ALL ON TABLE public.poll_votes TO service_role;

COMMIT;
