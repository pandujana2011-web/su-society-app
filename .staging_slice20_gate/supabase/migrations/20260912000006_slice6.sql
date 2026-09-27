-- ===========================================================================
-- SLICE 6: AUDIT, OPTIMIZATION, AND GATE PASS MANAGEMENT
-- ===========================================================================

-- 1. INDEXES
CREATE INDEX IF NOT EXISTS idx_charges_property_id ON public.maintenance_charges(property_id);
CREATE INDEX IF NOT EXISTS idx_payments_society_id ON public.payments(society_id);
CREATE INDEX IF NOT EXISTS idx_payments_property_id ON public.payments(property_id);
CREATE INDEX IF NOT EXISTS idx_ledger_property_id ON public.ledger_transactions(property_id);
CREATE INDEX IF NOT EXISTS idx_bookings_property_id ON public.amenity_bookings(property_id);
CREATE INDEX IF NOT EXISTS idx_tickets_property_id ON public.technician_tickets(property_id);
CREATE INDEX IF NOT EXISTS idx_vouchers_society_status ON public.expense_vouchers(society_id, status);

-- 2. DAILY STAFF
CREATE TABLE IF NOT EXISTS public.daily_staff (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    name VARCHAR(200) NOT NULL,
    role VARCHAR(100) NOT NULL,
    phone_number VARCHAR(50) NOT NULL,
    id_proof_url VARCHAR(1000),
    verification_status VARCHAR(50) NOT NULL DEFAULT 'pending'
        CONSTRAINT chk_staff_status CHECK (verification_status IN ('pending', 'verified', 'rejected', 'suspended')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_daily_staff_phone UNIQUE(society_id, phone_number)
);
CREATE TRIGGER trg_daily_staff_updated_at BEFORE UPDATE ON public.daily_staff FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- 3. GATE PASSES
CREATE TABLE IF NOT EXISTS public.gate_passes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    property_id UUID NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
    staff_id UUID NOT NULL REFERENCES public.daily_staff(id) ON DELETE RESTRICT,
    status VARCHAR(50) NOT NULL DEFAULT 'pending'
        CONSTRAINT chk_gate_pass_status CHECK (status IN ('pending', 'active', 'suspended')),
    valid_from TIMESTAMPTZ NOT NULL,
    valid_until TIMESTAMPTZ NOT NULL,
    requested_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    approved_by UUID REFERENCES auth.users(id) ON DELETE RESTRICT,
    approved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_gate_pass_validity CHECK (valid_from < valid_until)
);
CREATE TRIGGER trg_gate_passes_updated_at BEFORE UPDATE ON public.gate_passes FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE UNIQUE INDEX idx_unique_active_pass ON public.gate_passes(property_id, staff_id) WHERE status IN ('pending', 'active');

-- Force requested_by on INSERT via trigger to prevent spoofing
CREATE OR REPLACE FUNCTION public.fn_gate_passes_force_requested_by()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.requested_by := auth.uid();
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_gate_passes_force_requested_by BEFORE INSERT ON public.gate_passes
FOR EACH ROW EXECUTE FUNCTION public.fn_gate_passes_force_requested_by();

-- 4. DAILY STAFF STATE TRANSITION FUNCTION
CREATE OR REPLACE FUNCTION public.fn_transition_daily_staff_verification(
    p_staff_id UUID,
    p_new_status VARCHAR
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_staff RECORD;
    v_caller_society UUID;
BEGIN
    v_caller_society := public.get_user_society_id(auth.uid());
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access Denied: Only admins can manage staff verification';
    END IF;

    SELECT * INTO v_staff FROM public.daily_staff WHERE id = p_staff_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Staff not found'; END IF;
    IF v_staff.society_id != v_caller_society THEN RAISE EXCEPTION 'Cross-society denied'; END IF;

    IF p_new_status = 'verified' AND v_staff.verification_status = 'pending' THEN
        -- allowed
    ELSIF p_new_status = 'rejected' AND v_staff.verification_status = 'pending' THEN
        -- allowed
    ELSIF p_new_status = 'suspended' AND v_staff.verification_status = 'verified' THEN
        -- allowed
    ELSE
        RAISE EXCEPTION 'Invalid transition from % to %', v_staff.verification_status, p_new_status;
    END IF;

    -- Establish transaction-local scoped transition token before UPDATE
    PERFORM set_config(
        'app.authorized_daily_staff_transition',
        p_staff_id::text || ':' || p_new_status,
        true
    );

    UPDATE public.daily_staff SET verification_status = p_new_status WHERE id = p_staff_id;
END;
$$;

-- 5. GATE PASS STATE TRANSITION FUNCTION
CREATE OR REPLACE FUNCTION public.fn_transition_gate_pass_state(
    p_pass_id UUID,
    p_new_status VARCHAR
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_pass RECORD;
    v_staff RECORD;
    v_caller_society UUID;
    v_authorized BOOLEAN := FALSE;
BEGIN
    v_caller_society := public.get_user_society_id(auth.uid());

    SELECT * INTO v_pass FROM public.gate_passes WHERE id = p_pass_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Gate pass not found'; END IF;
    IF v_pass.society_id != v_caller_society THEN RAISE EXCEPTION 'Cross-society denied'; END IF;

    SELECT * INTO v_staff FROM public.daily_staff WHERE id = v_pass.staff_id;

    IF public.is_admin() THEN
        v_authorized := TRUE;
    ELSIF public.is_property_owner(auth.uid(), v_pass.property_id) OR public.is_property_tenant(auth.uid(), v_pass.property_id) THEN
        v_authorized := TRUE;
    END IF;

    IF NOT v_authorized THEN RAISE EXCEPTION 'Access Denied: Not authorized for this property'; END IF;

    IF p_new_status = 'active' AND v_pass.status = 'pending' THEN
        IF v_staff.verification_status != 'verified' THEN
            RAISE EXCEPTION 'Staff must be verified to activate gate pass';
        END IF;

        -- Establish transaction-local scoped transition token before UPDATE
        PERFORM set_config(
            'app.authorized_gate_pass_transition',
            p_pass_id::text || ':' || p_new_status,
            true
        );

        UPDATE public.gate_passes 
        SET status = 'active', approved_by = auth.uid(), approved_at = NOW() 
        WHERE id = p_pass_id;
    ELSIF p_new_status = 'suspended' AND v_pass.status = 'active' THEN
        -- Establish transaction-local scoped transition token before UPDATE
        PERFORM set_config(
            'app.authorized_gate_pass_transition',
            p_pass_id::text || ':' || p_new_status,
            true
        );

        UPDATE public.gate_passes SET status = 'suspended' WHERE id = p_pass_id;
    ELSE
        RAISE EXCEPTION 'Invalid transition from % to %', v_pass.status, p_new_status;
    END IF;
END;
$$;

-- 6. AUDIT TRIGGER FUNCTION
CREATE OR REPLACE FUNCTION public.fn_audit_trigger_func()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_society_id UUID;
    v_actor_id UUID;
    v_old_data JSONB;
    v_new_data JSONB;
BEGIN
    v_actor_id := auth.uid();
    
    IF TG_OP = 'INSERT' THEN
        v_old_data := NULL;
        v_new_data := to_jsonb(NEW);
    ELSIF TG_OP = 'UPDATE' THEN
        v_old_data := to_jsonb(OLD);
        v_new_data := to_jsonb(NEW);
    ELSIF TG_OP = 'DELETE' THEN
        v_old_data := to_jsonb(OLD);
        v_new_data := NULL;
    END IF;

    -- Extract society_id safely
    v_society_id := public.get_user_society_id(auth.uid());
    IF v_society_id IS NULL THEN
        -- Fallback for system actions
        IF TG_OP = 'DELETE' THEN
            v_society_id := (v_old_data->>'society_id')::UUID;
        ELSE
            v_society_id := (v_new_data->>'society_id')::UUID;
        END IF;
    END IF;

    -- Redaction for daily_staff
    IF TG_TABLE_NAME = 'daily_staff' THEN
        IF v_old_data IS NOT NULL THEN v_old_data := v_old_data - 'id_proof_url'; END IF;
        IF v_new_data IS NOT NULL THEN v_new_data := v_new_data - 'id_proof_url'; END IF;
    END IF;

    INSERT INTO public.audit_logs (
        society_id, actor_id, action, entity_type, entity_id, old_data, new_data
    ) VALUES (
        v_society_id, v_actor_id, TG_OP, TG_TABLE_NAME, 
        COALESCE(NEW.id, OLD.id), v_old_data, v_new_data
    );

    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$;

CREATE TRIGGER trg_audit_amenity_bookings AFTER INSERT OR UPDATE OR DELETE ON public.amenity_bookings FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger_func();
CREATE TRIGGER trg_audit_budgets AFTER INSERT OR UPDATE OR DELETE ON public.budgets FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger_func();
CREATE TRIGGER trg_audit_expense_vouchers AFTER INSERT OR UPDATE OR DELETE ON public.expense_vouchers FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger_func();
CREATE TRIGGER trg_audit_polls AFTER INSERT OR UPDATE OR DELETE ON public.polls FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger_func();
CREATE TRIGGER trg_audit_daily_staff AFTER INSERT OR UPDATE OR DELETE ON public.daily_staff FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger_func();
CREATE TRIGGER trg_audit_gate_passes AFTER INSERT OR UPDATE OR DELETE ON public.gate_passes FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger_func();
CREATE TRIGGER trg_audit_technician_tickets AFTER INSERT OR UPDATE OR DELETE ON public.technician_tickets FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger_func();


-- 7. TECHNICIAN TICKET REJECTION
ALTER TABLE public.technician_tickets DROP CONSTRAINT chk_ticket_status;
ALTER TABLE public.technician_tickets ADD CONSTRAINT chk_ticket_status CHECK (status IN ('open', 'assigned', 'in_progress', 'resolved', 'closed', 'rejected'));

CREATE OR REPLACE FUNCTION public.fn_transition_ticket_state(
    p_ticket_id UUID,
    p_new_state VARCHAR
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_ticket RECORD;
    v_caller_society UUID;
    v_is_authorized BOOLEAN;
BEGIN
    v_caller_society := public.get_user_society_id(auth.uid());
    
    SELECT * INTO v_ticket FROM public.technician_tickets WHERE id = p_ticket_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Ticket not found'; END IF;
    IF v_ticket.society_id != v_caller_society THEN RAISE EXCEPTION 'Cross-society denied'; END IF;

    v_is_authorized := public.is_admin() OR public.has_role(auth.uid(), 'technician');
    
    IF NOT v_is_authorized AND v_ticket.created_by = auth.uid() AND p_new_state IN ('resolved', 'closed') THEN
        v_is_authorized := TRUE;
    END IF;

    IF NOT v_is_authorized THEN RAISE EXCEPTION 'Access Denied'; END IF;

    IF p_new_state = 'assigned' AND v_ticket.status = 'open' THEN
        UPDATE public.technician_tickets SET status = 'assigned' WHERE id = p_ticket_id;
    ELSIF p_new_state = 'in_progress' AND v_ticket.status = 'assigned' THEN
        UPDATE public.technician_tickets SET status = 'in_progress' WHERE id = p_ticket_id;
    ELSIF p_new_state = 'resolved' AND v_ticket.status IN ('assigned', 'in_progress') THEN
        UPDATE public.technician_tickets SET status = 'resolved', resolved_at = NOW() WHERE id = p_ticket_id;
    ELSIF p_new_state = 'closed' AND v_ticket.status = 'resolved' THEN
        UPDATE public.technician_tickets SET status = 'closed' WHERE id = p_ticket_id;
    ELSIF p_new_state = 'rejected' AND v_ticket.status IN ('open', 'assigned', 'in_progress') THEN
        IF NOT public.is_admin() THEN
            RAISE EXCEPTION 'Only admins can reject tickets';
        END IF;
        UPDATE public.technician_tickets SET status = 'rejected' WHERE id = p_ticket_id;
    ELSE
        RAISE EXCEPTION 'Invalid transition from % to %', v_ticket.status, p_new_state;
    END IF;

    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_caller_society, auth.uid(), 'technician_ticket', p_ticket_id, 'ticket_status_changed', 
jsonb_build_object('old_status', v_ticket.status, 'new_status', p_new_state));
END;
$$;


-- 8. ROW LEVEL SECURITY (RLS) & IMMUTABILITY PROTECTION TRIGGERS
ALTER TABLE public.daily_staff ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gate_passes ENABLE ROW LEVEL SECURITY;

-- State Column Immutability Protection Triggers (Hardened Option 1)
CREATE OR REPLACE FUNCTION public.fn_protect_gate_pass_status_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_expected_token TEXT;
    v_actual_token TEXT;
BEGIN
    IF NEW.status IS DISTINCT FROM OLD.status THEN
        v_expected_token := NEW.id::text || ':' || NEW.status;
        v_actual_token := current_setting('app.authorized_gate_pass_transition', true);
        
        IF v_actual_token IS DISTINCT FROM v_expected_token THEN
            RAISE EXCEPTION 'Direct update of gate_passes.status prohibited. Use RPC fn_transition_gate_pass_state.';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_protect_gate_pass_status BEFORE UPDATE ON public.gate_passes
FOR EACH ROW EXECUTE FUNCTION public.fn_protect_gate_pass_status_mutation();

CREATE OR REPLACE FUNCTION public.fn_protect_daily_staff_status_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_expected_token TEXT;
    v_actual_token TEXT;
BEGIN
    IF NEW.verification_status IS DISTINCT FROM OLD.verification_status THEN
        v_expected_token := NEW.id::text || ':' || NEW.verification_status;
        v_actual_token := current_setting('app.authorized_daily_staff_transition', true);
        
        IF v_actual_token IS DISTINCT FROM v_expected_token THEN
            RAISE EXCEPTION 'Direct update of daily_staff.verification_status prohibited. Use RPC fn_transition_daily_staff_verification.';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_protect_daily_staff_status BEFORE UPDATE ON public.daily_staff
FOR EACH ROW EXECUTE FUNCTION public.fn_protect_daily_staff_status_mutation();

-- RLS Row-Level Isolation Policies
CREATE POLICY pol_daily_staff_admin_select ON public.daily_staff FOR SELECT USING (public.is_admin() AND society_id = public.get_user_society_id(auth.uid()));
CREATE POLICY pol_daily_staff_admin_insert ON public.daily_staff FOR INSERT WITH CHECK(public.is_admin() AND society_id = public.get_user_society_id(auth.uid()));
CREATE POLICY pol_daily_staff_admin_delete ON public.daily_staff FOR DELETE USING (public.is_admin() AND society_id = public.get_user_society_id(auth.uid()));

CREATE POLICY pol_daily_staff_gatekeeper_select ON public.daily_staff FOR SELECT
USING (public.has_role(auth.uid(), 'gatekeeper') AND society_id = public.get_user_society_id(auth.uid()) AND verification_status = 'verified');

CREATE POLICY pol_daily_staff_owner_select ON public.daily_staff FOR SELECT
USING (
    society_id = public.get_user_society_id(auth.uid()) AND
    EXISTS (
        SELECT 1 FROM public.gate_passes gp 
        WHERE gp.staff_id = daily_staff.id 
        AND gp.status = 'active'
        AND gp.valid_until >= NOW()
        AND (public.is_property_owner(auth.uid(), gp.property_id) OR public.is_property_tenant(auth.uid(), gp.property_id))
    )
);

CREATE POLICY pol_gate_passes_admin_select ON public.gate_passes FOR SELECT USING (public.is_admin() AND society_id = public.get_user_society_id(auth.uid()));
CREATE POLICY pol_gate_passes_admin_insert ON public.gate_passes FOR INSERT WITH CHECK(public.is_admin() AND society_id = public.get_user_society_id(auth.uid()));
CREATE POLICY pol_gate_passes_admin_delete ON public.gate_passes FOR DELETE USING (public.is_admin() AND society_id = public.get_user_society_id(auth.uid()));

CREATE POLICY pol_gate_passes_gatekeeper_select ON public.gate_passes FOR SELECT
USING (public.has_role(auth.uid(), 'gatekeeper') AND society_id = public.get_user_society_id(auth.uid()) AND status = 'active' AND valid_until >= current_timestamp);

CREATE POLICY pol_gate_passes_owner_insert ON public.gate_passes FOR INSERT
WITH CHECK (society_id = public.get_user_society_id(auth.uid()) AND (public.is_property_owner(auth.uid(), property_id) OR public.is_property_tenant(auth.uid(), property_id)));

CREATE POLICY pol_gate_passes_owner_select ON public.gate_passes FOR SELECT
USING (society_id = public.get_user_society_id(auth.uid()) AND (public.is_property_owner(auth.uid(), property_id) OR public.is_property_tenant(auth.uid(), property_id)));

CREATE POLICY pol_gate_passes_owner_delete ON public.gate_passes FOR DELETE
USING (society_id = public.get_user_society_id(auth.uid()) AND (public.is_property_owner(auth.uid(), property_id) OR public.is_property_tenant(auth.uid(), property_id)));

CREATE POLICY pol_gate_passes_admin_update ON public.gate_passes FOR UPDATE
USING (public.is_admin() AND society_id = public.get_user_society_id(auth.uid()))
WITH CHECK (society_id = public.get_user_society_id(auth.uid()));

CREATE POLICY pol_gate_passes_owner_update ON public.gate_passes FOR UPDATE
USING (society_id = public.get_user_society_id(auth.uid()) AND (public.is_property_owner(auth.uid(), property_id) OR public.is_property_tenant(auth.uid(), property_id)))
WITH CHECK (society_id = public.get_user_society_id(auth.uid()));

CREATE POLICY pol_daily_staff_admin_update ON public.daily_staff FOR UPDATE
USING (public.is_admin() AND society_id = public.get_user_society_id(auth.uid()))
WITH CHECK (society_id = public.get_user_society_id(auth.uid()));

GRANT ALL ON TABLE public.daily_staff TO authenticated;
GRANT ALL ON TABLE public.gate_passes TO authenticated;
