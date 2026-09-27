-- =========================================================================
-- SU SOCIETY APP - SLICE 3 SCHEMA (Operations: Bookings, technician, Visitors)
-- =========================================================================

-- =========================================================================
-- 1. TABLES
-- =========================================================================

-- 1.1 Amenities
CREATE TABLE IF NOT EXISTS public.amenities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    booking_type VARCHAR(30) NOT NULL CONSTRAINT chk_amenity_booking_type CHECK (booking_type IN ('slot_based', 'day_based')),
    hourly_rate NUMERIC(15, 2) NOT NULL DEFAULT 0.00 CONSTRAINT chk_amenity_rate CHECK (hourly_rate >= 0),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID NOT NULL REFERENCES public.users(id),
    CONSTRAINT uq_society_amenity_name UNIQUE (society_id, name)
);

-- 1.2 Amenity Bookings
CREATE TABLE IF NOT EXISTS public.amenity_bookings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    amenity_id UUID NOT NULL REFERENCES public.amenities(id) ON DELETE RESTRICT,
    property_id UUID NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
    unit_id UUID REFERENCES public.units(id) ON DELETE RESTRICT,
    booked_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    total_charges NUMERIC(15, 2) NOT NULL DEFAULT 0.00 CONSTRAINT chk_booking_charges CHECK (total_charges >= 0),
    status VARCHAR(30) NOT NULL DEFAULT 'pending_approval' 
        CONSTRAINT chk_booking_status CHECK (status IN ('pending_approval', 'approved', 'rejected', 'cancelled', 'completed')),
    payment_status VARCHAR(30) NOT NULL DEFAULT 'unpaid' 
        CONSTRAINT chk_booking_payment_status CHECK (payment_status IN ('unpaid', 'paid', 'refunded')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_booking_times CHECK (start_time < end_time)
);

-- EXCLUSION CONSTRAINT FOR CONCURRENCY: Overlapping bookings blocked natively
ALTER TABLE public.amenity_bookings ADD CONSTRAINT excl_booking_no_overlap 
    EXCLUDE USING gist (
        amenity_id WITH =,
        tstzrange(start_time, end_time, '[)') WITH &&
    ) WHERE (status IN ('approved', 'completed'));


-- 1.3 technician Tickets
CREATE TABLE IF NOT EXISTS public.technician_tickets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    property_id UUID NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
    unit_id UUID REFERENCES public.units(id) ON DELETE RESTRICT,
    created_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    category VARCHAR(50) NOT NULL CONSTRAINT chk_ticket_category CHECK (category IN ('plumbing', 'electrical', 'carpentry', 'security', 'billing', 'other')),
    title VARCHAR(150) NOT NULL,
    description TEXT NOT NULL,
    priority VARCHAR(20) NOT NULL DEFAULT 'medium' CONSTRAINT chk_ticket_priority CHECK (priority IN ('low', 'medium', 'high', 'emergency')),
    status VARCHAR(30) NOT NULL DEFAULT 'open' CONSTRAINT chk_ticket_status CHECK (status IN ('open', 'assigned', 'in_progress', 'resolved', 'closed')),
    assigned_to UUID REFERENCES public.users(id) ON DELETE RESTRICT,
    resolved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 1.4 Ticket Comments
CREATE TABLE IF NOT EXISTS public.ticket_comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id UUID NOT NULL REFERENCES public.technician_tickets(id) ON DELETE CASCADE,
    author_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    comment_text TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 1.5 Visitor Logs
CREATE TABLE IF NOT EXISTS public.visitor_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    property_id UUID NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
    unit_id UUID REFERENCES public.units(id) ON DELETE RESTRICT,
    visitor_name VARCHAR(100) NOT NULL,
    visitor_mobile VARCHAR(20),
    purpose VARCHAR(100) NOT NULL CONSTRAINT chk_visitor_purpose CHECK (purpose IN ('guest', 'delivery', 'service', 'other')),
    valid_until TIMESTAMPTZ,
    check_in TIMESTAMPTZ,
    check_out TIMESTAMPTZ,
    pre_auth_code VARCHAR(6) CONSTRAINT chk_pre_auth_format CHECK (pre_auth_code IS NULL OR pre_auth_code ~ '^[0-9]{6}$'),
    vehicle_number VARCHAR(30),
    registered_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_visitor_times CHECK (check_out IS NULL OR check_out >= check_in)
);

CREATE UNIQUE INDEX uq_visitor_active_pre_auth
    ON public.visitor_logs (society_id, pre_auth_code)
    WHERE pre_auth_code IS NOT NULL AND check_out IS NULL;


-- =========================================================================
-- 2. INTEGRATION WITH SLICE 2 LEDGER
-- =========================================================================

-- Add source_booking_id to Ledger
ALTER TABLE public.ledger_transactions ADD COLUMN source_booking_id UUID REFERENCES public.amenity_bookings(id) ON DELETE RESTRICT;

ALTER TABLE public.ledger_transactions DROP CONSTRAINT chk_tx_type;
ALTER TABLE public.ledger_transactions ADD CONSTRAINT chk_tx_type CHECK (transaction_type IN ('charge', 'payment', 'expense', 'reversal', 'booking_charge'));

-- Replace constraint to include booking source
ALTER TABLE public.ledger_transactions DROP CONSTRAINT chk_ledger_source_exclusive;
ALTER TABLE public.ledger_transactions ADD CONSTRAINT chk_ledger_source_exclusive CHECK (
    (CASE WHEN source_charge_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN source_payment_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN source_expense_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN reverses_ledger_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN source_booking_id IS NOT NULL THEN 1 ELSE 0 END) = 1
);

-- Update Trigger to validate cross-society for booking
CREATE OR REPLACE FUNCTION public.trg_validate_ledger_consistency()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_source_society_id UUID;
    v_booking_amenity UUID;
BEGIN
    IF NEW.unit_id IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM public.units WHERE id = NEW.unit_id AND property_id = NEW.property_id) THEN
            RAISE EXCEPTION 'Unit % does not belong to Property %', NEW.unit_id, NEW.property_id;
        END IF;
    END IF;

    IF NEW.property_id IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM public.properties WHERE id = NEW.property_id AND society_id = NEW.society_id) THEN
            RAISE EXCEPTION 'Property % does not belong to Society %', NEW.property_id, NEW.society_id;
        END IF;
    END IF;

    IF NEW.source_charge_id IS NOT NULL THEN
        SELECT society_id INTO v_source_society_id FROM public.maintenance_charges WHERE id = NEW.source_charge_id;
    ELSIF NEW.source_payment_id IS NOT NULL THEN
        SELECT society_id INTO v_source_society_id FROM public.payments WHERE id = NEW.source_payment_id;
    ELSIF NEW.source_expense_id IS NOT NULL THEN
        SELECT society_id INTO v_source_society_id FROM public.expenses WHERE id = NEW.source_expense_id;
    ELSIF NEW.reverses_ledger_id IS NOT NULL THEN
        SELECT society_id INTO v_source_society_id FROM public.ledger_transactions WHERE id = NEW.reverses_ledger_id;
    ELSIF NEW.source_booking_id IS NOT NULL THEN
        SELECT amenity_id INTO v_booking_amenity FROM public.amenity_bookings WHERE id = NEW.source_booking_id;
        SELECT society_id INTO v_source_society_id FROM public.amenities WHERE id = v_booking_amenity;
    END IF;

    IF v_source_society_id IS NOT NULL AND v_source_society_id != NEW.society_id THEN
        RAISE EXCEPTION 'Source society % does not match ledger society %', v_source_society_id, NEW.society_id;
    END IF;

    RETURN NEW;
END;
$$;


-- =========================================================================
-- 3. ROW LEVEL SECURITY (Default Deny)
-- =========================================================================
ALTER TABLE public.amenities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.amenities FORCE ROW LEVEL SECURITY;
ALTER TABLE public.amenity_bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.amenity_bookings FORCE ROW LEVEL SECURITY;
ALTER TABLE public.technician_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.technician_tickets FORCE ROW LEVEL SECURITY;
ALTER TABLE public.ticket_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ticket_comments FORCE ROW LEVEL SECURITY;
ALTER TABLE public.visitor_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.visitor_logs FORCE ROW LEVEL SECURITY;

-- 3.1 Amenities
CREATE POLICY pol_amenities_select ON public.amenities FOR SELECT USING (society_id = public.get_user_society_id(auth.uid()));
CREATE POLICY pol_amenities_insert_admin ON public.amenities FOR INSERT WITH CHECK (public.is_admin() AND society_id = public.get_user_society_id(auth.uid()));
CREATE POLICY pol_amenities_update_admin ON public.amenities FOR UPDATE USING (public.is_admin()) WITH CHECK (public.is_admin());

-- 3.2 Bookings
CREATE POLICY pol_bookings_select_admin ON public.amenity_bookings FOR SELECT USING (
    (public.is_admin() OR public.has_role(auth.uid(), 'gatekeeper') OR public.has_role(auth.uid(), 'technician')) 
    AND property_id IN (SELECT id FROM public.properties WHERE society_id = public.get_user_society_id(auth.uid()))
);
CREATE POLICY pol_bookings_select_owner ON public.amenity_bookings FOR SELECT USING (public.is_property_owner(auth.uid(), property_id));
CREATE POLICY pol_bookings_select_tenant ON public.amenity_bookings FOR SELECT USING (public.is_property_tenant(auth.uid(), property_id));

-- 3.3 technician Tickets
CREATE POLICY pol_tickets_select_admin ON public.technician_tickets FOR SELECT USING (
    (public.is_admin() OR public.has_role(auth.uid(), 'technician')) AND society_id = public.get_user_society_id(auth.uid())
);
CREATE POLICY pol_tickets_select_owner ON public.technician_tickets FOR SELECT USING (public.is_property_owner(auth.uid(), property_id));
CREATE POLICY pol_tickets_select_tenant ON public.technician_tickets FOR SELECT USING (public.is_property_tenant(auth.uid(), property_id));

CREATE POLICY pol_tickets_insert_member ON public.technician_tickets FOR INSERT WITH CHECK (
    society_id = public.get_user_society_id(auth.uid()) AND
    (public.is_property_owner(auth.uid(), property_id) OR public.is_property_tenant(auth.uid(), property_id)) AND
    status = 'open'
);

-- 3.4 Ticket Comments
CREATE POLICY pol_comments_select_admin ON public.ticket_comments FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.technician_tickets t WHERE t.id = ticket_id AND t.society_id = public.get_user_society_id(auth.uid()))
    AND (public.is_admin() OR public.has_role(auth.uid(), 'technician'))
);
CREATE POLICY pol_comments_select_member ON public.ticket_comments FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.technician_tickets t WHERE t.id = ticket_id AND (public.is_property_owner(auth.uid(), t.property_id) OR public.is_property_tenant(auth.uid(), t.property_id)))
);
CREATE POLICY pol_comments_insert_admin ON public.ticket_comments FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM public.technician_tickets t WHERE t.id = ticket_id AND t.society_id = public.get_user_society_id(auth.uid()))
    AND (public.is_admin() OR public.has_role(auth.uid(), 'technician'))
);
CREATE POLICY pol_comments_insert_member ON public.ticket_comments FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM public.technician_tickets t WHERE t.id = ticket_id AND (public.is_property_owner(auth.uid(), t.property_id) OR public.is_property_tenant(auth.uid(), t.property_id)))
);

-- 3.5 Visitor Logs
CREATE POLICY pol_visitors_select_admin ON public.visitor_logs FOR SELECT USING (
    (public.is_admin() OR public.has_role(auth.uid(), 'gatekeeper')) AND society_id = public.get_user_society_id(auth.uid())
);
CREATE POLICY pol_visitors_select_owner ON public.visitor_logs FOR SELECT USING (public.is_property_owner(auth.uid(), property_id));
CREATE POLICY pol_visitors_select_tenant ON public.visitor_logs FOR SELECT USING (public.is_property_tenant(auth.uid(), property_id));

CREATE POLICY pol_visitors_insert_member ON public.visitor_logs FOR INSERT WITH CHECK (
    society_id = public.get_user_society_id(auth.uid()) AND
    (public.is_property_owner(auth.uid(), property_id) OR public.is_property_tenant(auth.uid(), property_id)) AND
    check_in IS NULL AND check_out IS NULL AND pre_auth_code IS NOT NULL AND valid_until IS NOT NULL
);


-- =========================================================================
-- 4. SECURITY DEFINER FUNCTIONS (State Machines)
-- =========================================================================

-- 4.1 Amenity Bookings
CREATE OR REPLACE FUNCTION public.fn_create_amenity_booking(
    p_amenity_id UUID,
    p_property_id UUID,
    p_unit_id UUID,
    p_start_time TIMESTAMPTZ,
    p_end_time TIMESTAMPTZ
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller_society UUID;
    v_amenity RECORD;
    v_prop RECORD;
    v_booking_id UUID;
    v_duration_hours NUMERIC;
    v_charges NUMERIC(15, 2);
BEGIN
    v_caller_society := public.get_user_society_id(auth.uid());
    
    -- Validate caller has property access
    IF NOT (public.is_property_owner(auth.uid(), p_property_id) OR public.is_property_tenant(auth.uid(), p_property_id) OR public.is_admin()) THEN
        RAISE EXCEPTION 'Access Denied: Not authorized for property';
    END IF;

    -- Validate Amenity
    SELECT * INTO v_amenity FROM public.amenities WHERE id = p_amenity_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Amenity not found'; END IF;
    IF v_amenity.society_id != v_caller_society THEN RAISE EXCEPTION 'Cross-society denied'; END IF;
    IF NOT v_amenity.is_active THEN RAISE EXCEPTION 'Amenity inactive'; END IF;

    -- Validate Property
    SELECT * INTO v_prop FROM public.properties WHERE id = p_property_id;
    IF v_prop.society_id != v_caller_society THEN RAISE EXCEPTION 'Property mismatch'; END IF;
    
    -- Calculate Charges
    v_duration_hours := EXTRACT(EPOCH FROM (p_end_time - p_start_time)) / 3600.0;
    IF v_duration_hours <= 0 THEN RAISE EXCEPTION 'Invalid duration'; END IF;
    
    IF v_amenity.booking_type = 'day_based' THEN
        v_duration_hours := CEIL(v_duration_hours / 24.0);
    END IF;
    v_charges := ROUND(v_amenity.hourly_rate * v_duration_hours, 2);

    -- Insert Booking (will be blocked if overlap by UI/admin approval later, but let's allow pending_approval to overlap for queueing, EXCLUDE is for approved/completed)
    INSERT INTO public.amenity_bookings (amenity_id, property_id, unit_id, booked_by, start_time, end_time, total_charges, status, payment_status)
    VALUES (p_amenity_id, p_property_id, p_unit_id, auth.uid(), p_start_time, p_end_time, v_charges, 'pending_approval', 'unpaid')
    RETURNING id INTO v_booking_id;

    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_caller_society, auth.uid(), 'amenity_booking', v_booking_id, 'booking_created', jsonb_build_object('start_time', p_start_time, 'end_time', p_end_time));

    RETURN v_booking_id;
END;
$$;


CREATE OR REPLACE FUNCTION public.fn_process_booking_action(
    p_booking_id UUID,
    p_action VARCHAR -- 'approve', 'reject', 'cancel', 'complete'
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_booking RECORD;
    v_amenity RECORD;
    v_ledger_id UUID;
    v_reversal_id UUID;
    v_caller_society UUID;
BEGIN
    v_caller_society := public.get_user_society_id(auth.uid());

    -- Lock row
    SELECT * INTO v_booking FROM public.amenity_bookings WHERE id = p_booking_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Booking not found'; END IF;
    
    SELECT * INTO v_amenity FROM public.amenities WHERE id = v_booking.amenity_id;
    IF v_amenity.society_id != v_caller_society THEN RAISE EXCEPTION 'Cross-society denied'; END IF;

    -- State Machine
    IF p_action = 'approve' THEN
        IF NOT public.is_admin() THEN RAISE EXCEPTION 'Only admin can approve'; END IF;
        IF v_booking.status != 'pending_approval' THEN RAISE EXCEPTION 'Invalid transition'; END IF;
        
        -- Update state (this triggers the EXCLUDE constraint if overlapping)
        UPDATE public.amenity_bookings SET status = 'approved' WHERE id = p_booking_id;
        
        -- Financial Integration
        IF v_booking.total_charges > 0 THEN
            INSERT INTO public.ledger_transactions (society_id, scope, property_id, unit_id, amount, direction, transaction_type, source_booking_id, description, created_by)
            VALUES (v_caller_society, 'property', v_booking.property_id, v_booking.unit_id, v_booking.total_charges, 'debit', 'booking_charge', p_booking_id, 'Amenity Booking', auth.uid())
            RETURNING id INTO v_ledger_id;
            
            INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
            VALUES (v_caller_society, auth.uid(), 'amenity_booking', p_booking_id, 'financial_booking_charge_created', jsonb_build_object('ledger_id', v_ledger_id));
        END IF;

        INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
        VALUES (v_caller_society, auth.uid(), 'amenity_booking', p_booking_id, 'booking_approved', '{}');

    ELSIF p_action = 'reject' THEN
        IF NOT public.is_admin() THEN RAISE EXCEPTION 'Only admin can reject'; END IF;
        IF v_booking.status != 'pending_approval' THEN RAISE EXCEPTION 'Invalid transition'; END IF;
        UPDATE public.amenity_bookings SET status = 'rejected' WHERE id = p_booking_id;
        INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
        VALUES (v_caller_society, auth.uid(), 'amenity_booking', p_booking_id, 'booking_rejected', '{}');

    ELSIF p_action = 'cancel' THEN
        -- Admin or creator can cancel
        IF NOT (public.is_admin() OR v_booking.booked_by = auth.uid()) THEN RAISE EXCEPTION 'Access Denied'; END IF;
        IF v_booking.status NOT IN ('pending_approval', 'approved') THEN RAISE EXCEPTION 'Invalid transition'; END IF;
        
        UPDATE public.amenity_bookings SET status = 'cancelled' WHERE id = p_booking_id;
        
        IF v_booking.status = 'approved' AND v_booking.total_charges > 0 THEN
            -- Reverse financial
            SELECT id INTO v_ledger_id FROM public.ledger_transactions WHERE source_booking_id = p_booking_id AND direction = 'debit';
            
            INSERT INTO public.ledger_transactions (society_id, scope, property_id, unit_id, amount, direction, transaction_type, reverses_ledger_id, description, created_by)
            VALUES (v_caller_society, 'property', v_booking.property_id, v_booking.unit_id, v_booking.total_charges, 'credit', 'reversal', v_ledger_id, 'Booking Cancellation', auth.uid())
            RETURNING id INTO v_reversal_id;
            
            INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
            VALUES (v_caller_society, auth.uid(), 'amenity_booking', p_booking_id, 'financial_booking_reversal_created', jsonb_build_object('ledger_id', v_reversal_id));
        END IF;

        INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
        VALUES (v_caller_society, auth.uid(), 'amenity_booking', p_booking_id, 'booking_cancelled', '{}');

    ELSIF p_action = 'complete' THEN
        IF NOT public.is_admin() THEN RAISE EXCEPTION 'Only admin can complete'; END IF;
        IF v_booking.status != 'approved' THEN RAISE EXCEPTION 'Invalid transition'; END IF;
        UPDATE public.amenity_bookings SET status = 'completed' WHERE id = p_booking_id;
        INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
        VALUES (v_caller_society, auth.uid(), 'amenity_booking', p_booking_id, 'booking_completed', '{}');

    ELSE
        RAISE EXCEPTION 'Unknown action';
    END IF;
END;
$$;


-- 4.2 technician
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

    -- Auth check
    v_is_authorized := public.is_admin() OR public.has_role(auth.uid(), 'technician');
    
    -- Users can resolve/close their own tickets
    IF NOT v_is_authorized AND v_ticket.created_by = auth.uid() AND p_new_state IN ('resolved', 'closed') THEN
        v_is_authorized := TRUE;
    END IF;

    IF NOT v_is_authorized THEN RAISE EXCEPTION 'Access Denied'; END IF;

    -- State Machine Rules
    IF p_new_state = 'assigned' AND v_ticket.status = 'open' THEN
        UPDATE public.technician_tickets SET status = 'assigned' WHERE id = p_ticket_id;
    ELSIF p_new_state = 'in_progress' AND v_ticket.status = 'assigned' THEN
        UPDATE public.technician_tickets SET status = 'in_progress' WHERE id = p_ticket_id;
    ELSIF p_new_state = 'resolved' AND v_ticket.status IN ('assigned', 'in_progress') THEN
        UPDATE public.technician_tickets SET status = 'resolved', resolved_at = NOW() WHERE id = p_ticket_id;
    ELSIF p_new_state = 'closed' AND v_ticket.status = 'resolved' THEN
        UPDATE public.technician_tickets SET status = 'closed' WHERE id = p_ticket_id;
    ELSE
        RAISE EXCEPTION 'Invalid transition from % to %', v_ticket.status, p_new_state;
    END IF;

    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_caller_society, auth.uid(), 'technician_ticket', p_ticket_id, 'ticket_status_changed', jsonb_build_object('old_status', v_ticket.status, 'new_status', p_new_state));
END;
$$;


-- 4.3 Gatekeeper
CREATE OR REPLACE FUNCTION public.fn_visitor_check_in(
    p_society_id UUID,
    p_pre_auth_code VARCHAR DEFAULT NULL,
    p_property_id UUID DEFAULT NULL,
    p_visitor_name VARCHAR DEFAULT NULL,
    p_purpose VARCHAR DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_visitor RECORD;
    v_caller_society UUID;
    v_visitor_id UUID;
BEGIN
    v_caller_society := public.get_user_society_id(auth.uid());
    IF p_society_id != v_caller_society THEN RAISE EXCEPTION 'Cross-society denied'; END IF;
    IF NOT (public.is_admin() OR public.has_role(auth.uid(), 'gatekeeper')) THEN RAISE EXCEPTION 'Access Denied: Must be gatekeeper'; END IF;

    IF p_pre_auth_code IS NOT NULL THEN
        SELECT * INTO v_visitor FROM public.visitor_logs WHERE pre_auth_code = p_pre_auth_code AND society_id = v_caller_society FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION 'Invalid pre-auth code'; END IF;
        IF v_visitor.valid_until <= NOW() THEN RAISE EXCEPTION 'Pre-auth code expired'; END IF;
        IF v_visitor.check_in IS NOT NULL THEN RAISE EXCEPTION 'Already checked in'; END IF;
        
        UPDATE public.visitor_logs SET check_in = NOW() WHERE id = v_visitor.id;
        v_visitor_id := v_visitor.id;
    ELSE
        INSERT INTO public.visitor_logs (society_id, property_id, visitor_name, purpose, check_in, registered_by)
        VALUES (v_caller_society, p_property_id, p_visitor_name, p_purpose, NOW(), auth.uid())
        RETURNING id INTO v_visitor_id;
    END IF;

    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_caller_society, auth.uid(), 'visitor_log', v_visitor_id, 'visitor_checked_in', '{}');

    RETURN v_visitor_id;
END;
$$;


CREATE OR REPLACE FUNCTION public.fn_visitor_check_out(
    p_visitor_id UUID
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_visitor RECORD;
    v_caller_society UUID;
BEGIN
    v_caller_society := public.get_user_society_id(auth.uid());
    IF NOT (public.is_admin() OR public.has_role(auth.uid(), 'gatekeeper')) THEN RAISE EXCEPTION 'Access Denied: Must be gatekeeper'; END IF;

    SELECT * INTO v_visitor FROM public.visitor_logs WHERE id = p_visitor_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Visitor not found'; END IF;
    IF v_visitor.society_id != v_caller_society THEN RAISE EXCEPTION 'Cross-society denied'; END IF;
    IF v_visitor.check_in IS NULL THEN RAISE EXCEPTION 'Cannot check out visitor who has not checked in'; END IF;
    IF v_visitor.check_out IS NOT NULL THEN RAISE EXCEPTION 'Already checked out'; END IF;

    UPDATE public.visitor_logs SET check_out = NOW() WHERE id = p_visitor_id;

    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_caller_society, auth.uid(), 'visitor_log', p_visitor_id, 'visitor_checked_out', '{}');
END;
$$;


-- =========================================================================
-- 5. GRANTS
-- =========================================================================
GRANT SELECT, INSERT, UPDATE, DELETE ON public.amenities TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.amenity_bookings TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.technician_tickets TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.ticket_comments TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.visitor_logs TO authenticated;
