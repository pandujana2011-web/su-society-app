-- =========================================================================
-- SU SOCIETY APP - SLICE 8 SCHEMA (Move Lifecycle & Parcel Logistics)
-- =========================================================================

-- =========================================================================
-- 1. MOVE REQUESTS
-- =========================================================================

CREATE TABLE IF NOT EXISTS public.move_requests (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id          UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    property_id         UUID NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
    unit_id             UUID REFERENCES public.units(id) ON DELETE RESTRICT,
    request_type        VARCHAR(30) NOT NULL CONSTRAINT chk_move_req_type CHECK (request_type IN ('move_in', 'move_out')),
    primary_user_id     UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    proposed_date       DATE NOT NULL,
    status              VARCHAR(30) NOT NULL DEFAULT 'pending' 
                        CONSTRAINT chk_move_req_status CHECK (status IN ('pending', 'approved', 'rejected', 'completed', 'cancelled')),
    noc_status          VARCHAR(30) NOT NULL DEFAULT 'pending'
                        CONSTRAINT chk_noc_status CHECK (noc_status IN ('not_applicable', 'pending', 'cleared', 'rejected')),
    remarks             TEXT,
    approved_by         UUID REFERENCES public.users(id) ON DELETE RESTRICT,
    created_by          UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Triggers for updated_at
CREATE TRIGGER trg_move_requests_updated_at
    BEFORE UPDATE ON public.move_requests
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

-- Cross-society isolation
CREATE OR REPLACE FUNCTION public.trg_validate_move_request_isolation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_society_id UUID;
BEGIN
    SELECT society_id INTO v_society_id FROM public.properties WHERE id = NEW.property_id;
    IF v_society_id != NEW.society_id THEN
        RAISE EXCEPTION 'Property does not belong to the society';
    END IF;
    IF NEW.unit_id IS NOT NULL THEN
        SELECT society_id INTO v_society_id FROM public.units JOIN public.properties ON properties.id = units.property_id WHERE units.id = NEW.unit_id;
        IF v_society_id != NEW.society_id THEN
            RAISE EXCEPTION 'Unit does not belong to the society';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_move_requests_isolation
    BEFORE INSERT OR UPDATE ON public.move_requests
    FOR EACH ROW EXECUTE FUNCTION public.trg_validate_move_request_isolation();

-- Audit trigger
CREATE TRIGGER trg_audit_move_requests
    AFTER INSERT OR UPDATE OR DELETE ON public.move_requests
    FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger_func();


-- =========================================================================
-- 2. PARCEL LOGS
-- =========================================================================

CREATE TABLE IF NOT EXISTS public.parcel_logs (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id          UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    property_id         UUID NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
    unit_id             UUID REFERENCES public.units(id) ON DELETE RESTRICT,
    recipient_user_id   UUID REFERENCES public.users(id) ON DELETE SET NULL,
    carrier_name        VARCHAR(150) NOT NULL,
    tracking_number     VARCHAR(150),
    status              VARCHAR(30) NOT NULL DEFAULT 'received_at_gate'
                        CONSTRAINT chk_parcel_status CHECK (status IN ('received_at_gate', 'collected', 'returned')),
    collection_code     VARCHAR(10) NOT NULL,
    logged_by           UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    collected_by        UUID REFERENCES public.users(id) ON DELETE RESTRICT,
    collected_at        TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Triggers for updated_at
CREATE TRIGGER trg_parcel_logs_updated_at
    BEFORE UPDATE ON public.parcel_logs
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

-- Cross-society isolation
CREATE OR REPLACE FUNCTION public.trg_validate_parcel_isolation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_society_id UUID;
BEGIN
    SELECT society_id INTO v_society_id FROM public.properties WHERE id = NEW.property_id;
    IF v_society_id != NEW.society_id THEN
        RAISE EXCEPTION 'Property does not belong to the society';
    END IF;
    IF NEW.unit_id IS NOT NULL THEN
        SELECT society_id INTO v_society_id FROM public.units JOIN public.properties ON properties.id = units.property_id WHERE units.id = NEW.unit_id;
        IF v_society_id != NEW.society_id THEN
            RAISE EXCEPTION 'Unit does not belong to the society';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_parcel_logs_isolation
    BEFORE INSERT OR UPDATE ON public.parcel_logs
    FOR EACH ROW EXECUTE FUNCTION public.trg_validate_parcel_isolation();

-- Custom Audit Trigger for Parcel Logs to redact collection_code
CREATE OR REPLACE FUNCTION public.fn_audit_parcel_logs_redacted()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_action VARCHAR;
    v_new_data JSONB := NULL;
    v_old_data JSONB := NULL;
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_action := 'INSERT';
        v_new_data := row_to_json(NEW)::jsonb;
        v_new_data := v_new_data - 'collection_code';
    ELSIF TG_OP = 'UPDATE' THEN
        v_action := 'UPDATE';
        v_new_data := row_to_json(NEW)::jsonb;
        v_new_data := v_new_data - 'collection_code';
        v_old_data := row_to_json(OLD)::jsonb;
        v_old_data := v_old_data - 'collection_code';
    ELSIF TG_OP = 'DELETE' THEN
        v_action := 'DELETE';
        v_old_data := row_to_json(OLD)::jsonb;
        v_old_data := v_old_data - 'collection_code';
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
        COALESCE(NEW.society_id, OLD.society_id),
        auth.uid(),
        v_action,
        TG_TABLE_NAME,
        COALESCE(NEW.id, OLD.id),
        v_old_data,
        v_new_data
    );

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_audit_parcel_logs
    AFTER INSERT OR UPDATE OR DELETE ON public.parcel_logs
    FOR EACH ROW EXECUTE FUNCTION public.fn_audit_parcel_logs_redacted();


-- =========================================================================
-- 3. SECURITY DEFINER STATE MACHINES
-- =========================================================================

-- 3.1 Move Request State Transition
CREATE OR REPLACE FUNCTION public.fn_transition_move_request_state(
    p_request_id UUID,
    p_new_status VARCHAR
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_req RECORD;
    v_caller_society UUID;
    v_balance NUMERIC;
BEGIN
    SELECT * INTO v_req FROM public.move_requests WHERE id = p_request_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Move request not found'; END IF;

    v_caller_society := public.get_user_society_id(auth.uid());
    IF v_req.society_id != v_caller_society THEN RAISE EXCEPTION 'Cross-society access denied'; END IF;

    IF NOT public.is_admin() THEN RAISE EXCEPTION 'Only admins can process move requests'; END IF;

    -- Valid transitions
    IF v_req.status = 'pending' AND p_new_status IN ('approved', 'rejected', 'cancelled') THEN
        -- OK
    ELSIF v_req.status = 'approved' AND p_new_status IN ('completed', 'cancelled') THEN
        -- OK
    ELSE
        RAISE EXCEPTION 'Invalid state transition from % to %', v_req.status, p_new_status;
    END IF;

    -- Establish trusted transition context
    PERFORM set_config('app.move_req_transition', p_request_id::text, true);

    -- NOC Financial Gate for move_out
    IF p_new_status = 'approved' AND v_req.request_type = 'move_out' THEN
        SELECT public.fn_get_property_outstanding_balance(v_req.property_id) INTO v_balance;
        IF COALESCE(v_balance, 0) > 0 THEN
            RAISE EXCEPTION 'Cannot approve move_out: Property has outstanding dues.';
        END IF;
        
        UPDATE public.move_requests 
        SET status = p_new_status, 
            noc_status = 'cleared',
            approved_by = auth.uid()
        WHERE id = p_request_id;
    ELSE
        UPDATE public.move_requests 
        SET status = p_new_status,
            approved_by = CASE WHEN p_new_status IN ('approved', 'rejected') THEN auth.uid() ELSE v_req.approved_by END
        WHERE id = p_request_id;
    END IF;
END;
$$;

-- 3.2 Parcel State Transition
CREATE OR REPLACE FUNCTION public.fn_transition_parcel_state(
    p_parcel_id UUID,
    p_new_status VARCHAR,
    p_collection_code VARCHAR DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_parcel RECORD;
    v_caller_society UUID;
BEGIN
    SELECT * INTO v_parcel FROM public.parcel_logs WHERE id = p_parcel_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Parcel not found'; END IF;

    v_caller_society := public.get_user_society_id(auth.uid());
    IF v_parcel.society_id != v_caller_society THEN RAISE EXCEPTION 'Cross-society access denied'; END IF;

    IF NOT (public.has_role(auth.uid(), 'gatekeeper') OR public.is_admin()) THEN
        RAISE EXCEPTION 'Only gatekeepers or admins can transition parcel states';
    END IF;

    IF v_parcel.status != 'received_at_gate' THEN
        RAISE EXCEPTION 'Invalid state transition from %', v_parcel.status;
    END IF;

    -- Establish trusted transition context
    PERFORM set_config('app.parcel_transition', p_parcel_id::text, true);

    IF p_new_status = 'collected' THEN
        IF p_collection_code IS NULL OR p_collection_code != v_parcel.collection_code THEN
            RAISE EXCEPTION 'Incorrect collection code';
        END IF;

        UPDATE public.parcel_logs
        SET status = p_new_status,
            collected_by = auth.uid(),
            collected_at = NOW()
        WHERE id = p_parcel_id;
    ELSIF p_new_status = 'returned' THEN
        UPDATE public.parcel_logs
        SET status = p_new_status
        WHERE id = p_parcel_id;
    ELSE
        RAISE EXCEPTION 'Invalid state transition to %', p_new_status;
    END IF;
END;
$$;


-- =========================================================================
-- 4. RLS POLICIES & STATUS MUTATION BLOCKERS
-- =========================================================================

ALTER TABLE public.move_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.move_requests FORCE ROW LEVEL SECURITY;

ALTER TABLE public.parcel_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.parcel_logs FORCE ROW LEVEL SECURITY;

-- Block direct status mutation
CREATE OR REPLACE FUNCTION public.trg_prevent_direct_move_status_update()
RETURNS TRIGGER LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.status IS DISTINCT FROM OLD.status OR NEW.noc_status IS DISTINCT FROM OLD.noc_status THEN
        IF current_setting('app.move_req_transition', true) IS DISTINCT FROM NEW.id::text THEN
             RAISE EXCEPTION 'Direct status updates blocked. Use fn_transition_move_request_state';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_move_requests_status_block
    BEFORE UPDATE ON public.move_requests
    FOR EACH ROW 
    EXECUTE FUNCTION public.trg_prevent_direct_move_status_update();

CREATE OR REPLACE FUNCTION public.trg_prevent_direct_parcel_status_update()
RETURNS TRIGGER LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.status IS DISTINCT FROM OLD.status THEN
        IF current_setting('app.parcel_transition', true) IS DISTINCT FROM NEW.id::text THEN
             RAISE EXCEPTION 'Direct status updates blocked. Use fn_transition_parcel_state';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_parcel_logs_status_block
    BEFORE UPDATE ON public.parcel_logs
    FOR EACH ROW 
    EXECUTE FUNCTION public.trg_prevent_direct_parcel_status_update();


-- Policies Move Requests
-- Admin: SELECT all in society
CREATE POLICY pol_move_req_select_admin ON public.move_requests FOR SELECT
    USING (public.is_admin() AND society_id = public.get_user_society_id(auth.uid()));

-- Owner/Tenant: SELECT own property
CREATE POLICY pol_move_req_select_resident ON public.move_requests FOR SELECT
    USING (public.is_property_owner(auth.uid(), property_id) OR public.is_property_tenant(auth.uid(), property_id));

-- Owner/Tenant: INSERT for own property
CREATE POLICY pol_move_req_insert_resident ON public.move_requests FOR INSERT
    WITH CHECK (
        status = 'pending' AND 
        noc_status = 'pending' AND
        society_id = public.get_user_society_id(auth.uid()) AND
        (public.is_property_owner(auth.uid(), property_id) OR public.is_property_tenant(auth.uid(), property_id))
    );

-- Prevent direct updates (state transitions handle modifications safely bypassing RLS via security definer)
CREATE POLICY pol_move_req_update_none ON public.move_requests FOR UPDATE
    USING (false) WITH CHECK (false);

CREATE POLICY pol_move_req_delete_none ON public.move_requests FOR DELETE
    USING (false);


-- Policies Parcel Logs
-- Admin: SELECT all in society
CREATE POLICY pol_parcel_select_admin ON public.parcel_logs FOR SELECT
    USING (public.is_admin() AND society_id = public.get_user_society_id(auth.uid()));

-- Gatekeeper: SELECT all in society
CREATE POLICY pol_parcel_select_gatekeeper ON public.parcel_logs FOR SELECT
    USING (public.has_role(auth.uid(), 'gatekeeper') AND society_id = public.get_user_society_id(auth.uid()));

-- Resident: SELECT own property parcels
CREATE POLICY pol_parcel_select_resident ON public.parcel_logs FOR SELECT
    USING (public.is_property_owner(auth.uid(), property_id) OR public.is_property_tenant(auth.uid(), property_id));

-- Gatekeeper/Admin: INSERT
CREATE POLICY pol_parcel_insert_gatekeeper ON public.parcel_logs FOR INSERT
    WITH CHECK (
        status = 'received_at_gate' AND
        (public.has_role(auth.uid(), 'gatekeeper') OR public.is_admin()) AND 
        society_id = public.get_user_society_id(auth.uid())
    );

-- Prevent direct UPDATE/DELETE
CREATE POLICY pol_parcel_update_none ON public.parcel_logs FOR UPDATE
    USING (false) WITH CHECK (false);
    
CREATE POLICY pol_parcel_delete_none ON public.parcel_logs FOR DELETE
    USING (false);


-- =========================================================================
-- 5. INDEXES
-- =========================================================================
CREATE INDEX IF NOT EXISTS idx_move_requests_property_id ON public.move_requests(property_id);
CREATE INDEX IF NOT EXISTS idx_move_requests_society_id_status ON public.move_requests(society_id, status);
CREATE INDEX IF NOT EXISTS idx_parcel_logs_property_id ON public.parcel_logs(property_id);
CREATE INDEX IF NOT EXISTS idx_parcel_logs_society_id_status ON public.parcel_logs(society_id, status);

-- =========================================================================
-- 6. GRANTS
-- =========================================================================
GRANT SELECT, INSERT, UPDATE, DELETE ON public.move_requests TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.parcel_logs TO authenticated;
