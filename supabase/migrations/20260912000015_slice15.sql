-- ==============================================================================
-- SLICE 15 SCHEMA: HELP DESK WORKFLOW & STATE MACHINES
-- ==============================================================================

BEGIN;

-- 1. Create helpdesk_tickets Table IF NOT EXISTS
CREATE TABLE IF NOT EXISTS public.helpdesk_tickets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE,
    reported_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    assigned_to UUID REFERENCES public.users(id) ON DELETE SET NULL,
    title VARCHAR(200) NOT NULL,
    description TEXT NOT NULL,
    category VARCHAR(50) NOT NULL DEFAULT 'general',
    priority VARCHAR(20) NOT NULL DEFAULT 'medium',
    status VARCHAR(30) NOT NULL DEFAULT 'open',
    resolution_notes TEXT,
    assigned_at TIMESTAMPTZ,
    started_at TIMESTAMPTZ,
    closed_at TIMESTAMPTZ,
    reopened_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.helpdesk_tickets TO authenticated;

-- Permissive SELECT/INSERT RLS policy for helpdesk_tickets if not already defined
DROP POLICY IF EXISTS pol_helpdesk_tickets_select_authenticated ON public.helpdesk_tickets;
CREATE POLICY pol_helpdesk_tickets_select_authenticated ON public.helpdesk_tickets
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS pol_helpdesk_tickets_insert_authenticated ON public.helpdesk_tickets;
CREATE POLICY pol_helpdesk_tickets_insert_authenticated ON public.helpdesk_tickets
    FOR INSERT TO authenticated WITH CHECK (true);

-- 2. DDL Updates & SLA Column Additions
ALTER TABLE public.ledger_transactions 
    DROP CONSTRAINT IF EXISTS check_transaction_type;
ALTER TABLE public.ledger_transactions 
    DROP CONSTRAINT IF EXISTS chk_tx_type;

ALTER TABLE public.ledger_transactions 
    ADD CONSTRAINT chk_tx_type 
    CHECK (transaction_type IN (
        'charge', 'penalty', 'adjustment', 'waiver', 'payment', 
        'advance_payment', 'refund', 'reversal', 'expense', 'income', 'booking_charge',
        'opening_balance', 'maintenance_fee', 'utility_bill', 'facility_booking', 
        'amenity_fee', 'other'
    ));

ALTER TABLE public.helpdesk_tickets
    ADD COLUMN IF NOT EXISTS assigned_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS started_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS closed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS reopened_at TIMESTAMPTZ;

ALTER TABLE public.amenity_bookings
    ADD COLUMN IF NOT EXISTS rejection_reason TEXT,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

ALTER TABLE public.visitor_logs
    ADD COLUMN IF NOT EXISTS host_resident_id UUID REFERENCES public.users(id) ON DELETE SET NULL;

ALTER TABLE public.amenity_bookings 
    DROP CONSTRAINT IF EXISTS chk_booking_status;
ALTER TABLE public.amenity_bookings 
    DROP CONSTRAINT IF EXISTS check_booking_status;

ALTER TABLE public.amenity_bookings 
    ADD CONSTRAINT chk_booking_status 
    CHECK (status IN ('pending', 'pending_approval', 'approved', 'rejected', 'cancelled', 'completed'));

-- 3. Restrictive RLS Policies
ALTER TABLE public.helpdesk_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.helpdesk_tickets FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_helpdesk_tickets_restrictive_update ON public.helpdesk_tickets;
CREATE POLICY pol_helpdesk_tickets_restrictive_update ON public.helpdesk_tickets
    AS RESTRICTIVE
    FOR UPDATE
    TO authenticated
    USING (false)
    WITH CHECK (false);

ALTER TABLE public.amenity_bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.amenity_bookings FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_amenity_bookings_restrictive_update ON public.amenity_bookings;
CREATE POLICY pol_amenity_bookings_restrictive_update ON public.amenity_bookings
    AS RESTRICTIVE
    FOR UPDATE
    TO authenticated
    USING (false)
    WITH CHECK (false);

-- 4. Workflow Context Enforcement Triggers
CREATE OR REPLACE FUNCTION public.fn_prevent_direct_ticket_status_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        IF current_setting('app.ticket_workflow_context', true) IS DISTINCT FROM NEW.id::text THEN
            RAISE EXCEPTION 'Direct client update of ticket status is forbidden. Use workflow stored procedures.'
                USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_direct_ticket_status_update ON public.helpdesk_tickets;
CREATE TRIGGER trg_prevent_direct_ticket_status_update
    BEFORE UPDATE ON public.helpdesk_tickets
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_prevent_direct_ticket_status_update();

CREATE OR REPLACE FUNCTION public.fn_prevent_direct_booking_status_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        IF current_setting('app.booking_workflow_context', true) IS DISTINCT FROM NEW.id::text THEN
            RAISE EXCEPTION 'Direct client update of amenity booking status is forbidden. Use workflow stored procedures.'
                USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_direct_booking_status_update ON public.amenity_bookings;
CREATE TRIGGER trg_prevent_direct_booking_status_update
    BEFORE UPDATE ON public.amenity_bookings
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_prevent_direct_booking_status_update();

-- 5. Stored Procedures for State Machine Transitions

-- 5.1 assign_ticket
CREATE OR REPLACE FUNCTION public.assign_ticket(
    p_ticket_id UUID,
    p_assignee_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor_id UUID;
    v_ticket RECORD;
    v_actor_role TEXT;
    v_assignee_role TEXT;
    v_payload JSONB;
BEGIN
    v_actor_id := auth.uid();
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_ticket 
    FROM public.helpdesk_tickets 
    WHERE id = p_ticket_id 
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Ticket not found.' USING ERRCODE = 'P0002';
    END IF;

    -- Actor permission check
    SELECT role_name INTO v_actor_role 
    FROM public.user_roles 
    WHERE user_id = v_actor_id AND society_id = v_ticket.society_id;

    IF v_actor_role IS NULL OR v_actor_role NOT IN ('admin', 'technician', 'gatekeeper', 'secretary', 'treasurer', 'executive_member', 'super_admin') THEN
        RAISE EXCEPTION 'Unauthorized to assign ticket.' USING ERRCODE = '42501';
    END IF;

    -- State transition validation
    IF v_ticket.status NOT IN ('open', 'assigned') THEN
        RAISE EXCEPTION 'Invalid transition: ticket status % cannot be assigned.', v_ticket.status USING ERRCODE = '22000';
    END IF;

    -- Target assignee validation
    SELECT role_name INTO v_assignee_role 
    FROM public.user_roles 
    WHERE user_id = p_assignee_id AND society_id = v_ticket.society_id;

    IF v_assignee_role IS NULL OR v_assignee_role NOT IN ('admin', 'technician', 'gatekeeper', 'secretary', 'treasurer', 'executive_member', 'super_admin') THEN
        RAISE EXCEPTION 'Assignee must be active staff or admin in the society.' USING ERRCODE = '22000';
    END IF;

    -- Set workflow context GUC
    PERFORM set_config('app.ticket_workflow_context', p_ticket_id::text, true);

    -- Execute status and assignment update
    UPDATE public.helpdesk_tickets
    SET status = 'assigned',
        assigned_to = p_assignee_id,
        assigned_at = COALESCE(assigned_at, NOW()),
        updated_at = NOW()
    WHERE id = p_ticket_id;

    -- Audit log
    v_payload := jsonb_build_object(
        'ticket_id', p_ticket_id,
        'old_assignee', v_ticket.assigned_to,
        'new_assignee', p_assignee_id,
        'old_status', v_ticket.status,
        'new_status', 'assigned'
    );
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_ticket.society_id, v_actor_id, 'helpdesk_tickets', p_ticket_id, 'TICKET_ASSIGNED', v_payload);

    -- Notification dispatch to reporter & assignee
    INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
    VALUES 
        (v_ticket.society_id, v_ticket.reported_by, 'helpdesk', 'Ticket Assigned', 'Your ticket has been assigned.', 'helpdesk_tickets', p_ticket_id),
        (v_ticket.society_id, p_assignee_id, 'helpdesk', 'Ticket Assigned to You', 'You have been assigned a helpdesk ticket.', 'helpdesk_tickets', p_ticket_id);
END;
$$;

-- 5.2 start_ticket
CREATE OR REPLACE FUNCTION public.start_ticket(
    p_ticket_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor_id UUID;
    v_ticket RECORD;
    v_actor_role TEXT;
    v_payload JSONB;
BEGIN
    v_actor_id := auth.uid();
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_ticket 
    FROM public.helpdesk_tickets 
    WHERE id = p_ticket_id 
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Ticket not found.' USING ERRCODE = 'P0002';
    END IF;

    -- Authorization check: assigned user OR society admin
    SELECT role_name INTO v_actor_role 
    FROM public.user_roles 
    WHERE user_id = v_actor_id AND society_id = v_ticket.society_id;

    IF v_actor_id IS DISTINCT FROM v_ticket.assigned_to AND (v_actor_role IS NULL OR v_actor_role NOT IN ('admin', 'super_admin')) THEN
        RAISE EXCEPTION 'Only the assigned staff or society admin can start the ticket.' USING ERRCODE = '42501';
    END IF;

    -- Transition check
    IF v_ticket.status != 'assigned' THEN
        RAISE EXCEPTION 'Invalid transition: ticket status % cannot be started.', v_ticket.status USING ERRCODE = '22000';
    END IF;

    -- Set workflow GUC
    PERFORM set_config('app.ticket_workflow_context', p_ticket_id::text, true);

    UPDATE public.helpdesk_tickets
    SET status = 'in_progress',
        started_at = COALESCE(started_at, NOW()),
        updated_at = NOW()
    WHERE id = p_ticket_id;

    -- Audit log
    v_payload := jsonb_build_object(
        'ticket_id', p_ticket_id,
        'old_status', 'assigned',
        'new_status', 'in_progress'
    );
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_ticket.society_id, v_actor_id, 'helpdesk_tickets', p_ticket_id, 'TICKET_STARTED', v_payload);

    -- Notification dispatch to reporter
    INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
    VALUES (v_ticket.society_id, v_ticket.reported_by, 'helpdesk', 'Ticket In Progress', 'Work has started on your ticket.', 'helpdesk_tickets', p_ticket_id);
END;
$$;

-- 5.3 resolve_ticket
CREATE OR REPLACE FUNCTION public.resolve_ticket(
    p_ticket_id UUID,
    p_resolution_notes TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor_id UUID;
    v_ticket RECORD;
    v_actor_role TEXT;
    v_payload JSONB;
BEGIN
    v_actor_id := auth.uid();
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    IF p_resolution_notes IS NULL OR trim(p_resolution_notes) = '' THEN
        RAISE EXCEPTION 'Resolution notes are required.' USING ERRCODE = '22000';
    END IF;

    SELECT * INTO v_ticket 
    FROM public.helpdesk_tickets 
    WHERE id = p_ticket_id 
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Ticket not found.' USING ERRCODE = 'P0002';
    END IF;

    -- Authorization check: assigned user OR society admin
    SELECT role_name INTO v_actor_role 
    FROM public.user_roles 
    WHERE user_id = v_actor_id AND society_id = v_ticket.society_id;

    IF v_actor_id IS DISTINCT FROM v_ticket.assigned_to AND (v_actor_role IS NULL OR v_actor_role NOT IN ('admin', 'super_admin')) THEN
        RAISE EXCEPTION 'Only the assigned staff or society admin can resolve the ticket.' USING ERRCODE = '42501';
    END IF;

    -- Transition check
    IF v_ticket.status != 'in_progress' THEN
        RAISE EXCEPTION 'Invalid transition: ticket status % cannot be resolved.', v_ticket.status USING ERRCODE = '22000';
    END IF;

    -- Set workflow GUC
    PERFORM set_config('app.ticket_workflow_context', p_ticket_id::text, true);

    UPDATE public.helpdesk_tickets
    SET status = 'resolved',
        resolution_notes = p_resolution_notes,
        updated_at = NOW()
    WHERE id = p_ticket_id;

    -- Audit log
    v_payload := jsonb_build_object(
        'ticket_id', p_ticket_id,
        'old_status', 'in_progress',
        'new_status', 'resolved',
        'resolution_notes', p_resolution_notes
    );
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_ticket.society_id, v_actor_id, 'helpdesk_tickets', p_ticket_id, 'TICKET_RESOLVED', v_payload);

    -- Notification dispatch to reporter
    INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
    VALUES (v_ticket.society_id, v_ticket.reported_by, 'helpdesk', 'Ticket Resolved', 'Your helpdesk ticket has been resolved.', 'helpdesk_tickets', p_ticket_id);
END;
$$;

-- 5.4 close_ticket
CREATE OR REPLACE FUNCTION public.close_ticket(
    p_ticket_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor_id UUID;
    v_ticket RECORD;
    v_actor_role TEXT;
    v_payload JSONB;
BEGIN
    v_actor_id := auth.uid();
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_ticket 
    FROM public.helpdesk_tickets 
    WHERE id = p_ticket_id 
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Ticket not found.' USING ERRCODE = 'P0002';
    END IF;

    -- Authorization check: reporter OR admin
    SELECT role_name INTO v_actor_role 
    FROM public.user_roles 
    WHERE user_id = v_actor_id AND society_id = v_ticket.society_id;

    IF v_actor_id IS DISTINCT FROM v_ticket.reported_by AND (v_actor_role IS NULL OR v_actor_role NOT IN ('admin', 'super_admin')) THEN
        RAISE EXCEPTION 'Only the ticket reporter or society admin can close the ticket.' USING ERRCODE = '42501';
    END IF;

    -- Transition check
    IF v_ticket.status != 'resolved' THEN
        RAISE EXCEPTION 'Invalid transition: ticket status % cannot be closed.', v_ticket.status USING ERRCODE = '22000';
    END IF;

    -- Set workflow GUC
    PERFORM set_config('app.ticket_workflow_context', p_ticket_id::text, true);

    UPDATE public.helpdesk_tickets
    SET status = 'closed',
        closed_at = NOW(),
        updated_at = NOW()
    WHERE id = p_ticket_id;

    -- Audit log
    v_payload := jsonb_build_object(
        'ticket_id', p_ticket_id,
        'old_status', 'resolved',
        'new_status', 'closed'
    );
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_ticket.society_id, v_actor_id, 'helpdesk_tickets', p_ticket_id, 'TICKET_CLOSED', v_payload);

    -- Notification dispatch to reporter & assignee (if assigned)
    INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
    VALUES (v_ticket.society_id, v_ticket.reported_by, 'helpdesk', 'Ticket Closed', 'Your ticket has been closed.', 'helpdesk_tickets', p_ticket_id);

    IF v_ticket.assigned_to IS NOT NULL AND v_ticket.assigned_to IS DISTINCT FROM v_ticket.reported_by THEN
        INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
        VALUES (v_ticket.society_id, v_ticket.assigned_to, 'helpdesk', 'Ticket Closed', 'A ticket assigned to you was closed.', 'helpdesk_tickets', p_ticket_id);
    END IF;
END;
$$;

-- 5.5 reopen_ticket
CREATE OR REPLACE FUNCTION public.reopen_ticket(
    p_ticket_id UUID,
    p_reason TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor_id UUID;
    v_ticket RECORD;
    v_actor_role TEXT;
    v_payload JSONB;
BEGIN
    v_actor_id := auth.uid();
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    IF p_reason IS NULL OR trim(p_reason) = '' THEN
        RAISE EXCEPTION 'Reopen reason is required.' USING ERRCODE = '22000';
    END IF;

    SELECT * INTO v_ticket 
    FROM public.helpdesk_tickets 
    WHERE id = p_ticket_id 
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Ticket not found.' USING ERRCODE = 'P0002';
    END IF;

    -- Authorization check: reporter OR admin
    SELECT role_name INTO v_actor_role 
    FROM public.user_roles 
    WHERE user_id = v_actor_id AND society_id = v_ticket.society_id;

    IF v_actor_id IS DISTINCT FROM v_ticket.reported_by AND (v_actor_role IS NULL OR v_actor_role NOT IN ('admin', 'super_admin')) THEN
        RAISE EXCEPTION 'Only the ticket reporter or society admin can reopen the ticket.' USING ERRCODE = '42501';
    END IF;

    -- Transition check
    IF v_ticket.status NOT IN ('resolved', 'closed') THEN
        RAISE EXCEPTION 'Invalid transition: ticket status % cannot be reopened.', v_ticket.status USING ERRCODE = '22000';
    END IF;

    -- Set workflow GUC
    PERFORM set_config('app.ticket_workflow_context', p_ticket_id::text, true);

    UPDATE public.helpdesk_tickets
    SET status = 'open',
        reopened_at = NOW(),
        updated_at = NOW()
    WHERE id = p_ticket_id;

    -- Audit log
    v_payload := jsonb_build_object(
        'ticket_id', p_ticket_id,
        'old_status', v_ticket.status,
        'new_status', 'open',
        'reason', p_reason
    );
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_ticket.society_id, v_actor_id, 'helpdesk_tickets', p_ticket_id, 'TICKET_REOPENED', v_payload);

    -- Notification dispatch to reporter & assignee (if assigned)
    INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
    VALUES (v_ticket.society_id, v_ticket.reported_by, 'helpdesk', 'Ticket Reopened', 'Your ticket has been reopened.', 'helpdesk_tickets', p_ticket_id);

    IF v_ticket.assigned_to IS NOT NULL AND v_ticket.assigned_to IS DISTINCT FROM v_ticket.reported_by THEN
        INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
        VALUES (v_ticket.society_id, v_ticket.assigned_to, 'helpdesk', 'Ticket Reopened', 'A resolved/closed ticket assigned to you was reopened.', 'helpdesk_tickets', p_ticket_id);
    END IF;
END;
$$;

-- 5.6 reject_amenity_booking
CREATE OR REPLACE FUNCTION public.reject_amenity_booking(
    p_booking_id UUID,
    p_reason TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor_id UUID;
    v_booking RECORD;
    v_actor_role TEXT;
    v_payload JSONB;
BEGIN
    v_actor_id := auth.uid();
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    IF p_reason IS NULL OR trim(p_reason) = '' THEN
        RAISE EXCEPTION 'Rejection reason is required.' USING ERRCODE = '22000';
    END IF;

    SELECT ab.*, a.society_id 
    INTO v_booking 
    FROM public.amenity_bookings ab 
    JOIN public.amenities a ON ab.amenity_id = a.id 
    WHERE ab.id = p_booking_id 
    FOR UPDATE OF ab;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Booking not found.' USING ERRCODE = 'P0002';
    END IF;

    -- Authorization check: admin only
    SELECT role_name INTO v_actor_role 
    FROM public.user_roles 
    WHERE user_id = v_actor_id AND society_id = v_booking.society_id;

    IF v_actor_role IS NULL OR v_actor_role NOT IN ('admin', 'super_admin') THEN
        RAISE EXCEPTION 'Only society admin can reject amenity booking.' USING ERRCODE = '42501';
    END IF;

    -- Transition check
    IF v_booking.status NOT IN ('pending', 'pending_approval') THEN
        RAISE EXCEPTION 'Invalid transition: booking status % cannot be rejected.', v_booking.status USING ERRCODE = '22000';
    END IF;

    -- Set workflow GUC
    PERFORM set_config('app.booking_workflow_context', p_booking_id::text, true);

    UPDATE public.amenity_bookings
    SET status = 'rejected',
        rejection_reason = p_reason,
        updated_at = NOW()
    WHERE id = p_booking_id;

    -- Audit log
    v_payload := jsonb_build_object(
        'booking_id', p_booking_id,
        'old_status', v_booking.status,
        'new_status', 'rejected',
        'reason', p_reason
    );
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_booking.society_id, v_actor_id, 'amenity_bookings', p_booking_id, 'BOOKING_REJECTED', v_payload);

    -- Notification dispatch to resident who booked
    INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
    VALUES (v_booking.society_id, v_booking.booked_by, 'amenity', 'Booking Rejected', 'Your amenity booking request was rejected.', 'amenity_bookings', p_booking_id);
END;
$$;

-- 5.7 complete_amenity_booking
CREATE OR REPLACE FUNCTION public.complete_amenity_booking(
    p_booking_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor_id UUID;
    v_booking RECORD;
    v_actor_role TEXT;
    v_payload JSONB;
BEGIN
    v_actor_id := auth.uid();
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    SELECT ab.*, a.society_id 
    INTO v_booking 
    FROM public.amenity_bookings ab 
    JOIN public.amenities a ON ab.amenity_id = a.id 
    WHERE ab.id = p_booking_id 
    FOR UPDATE OF ab;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Booking not found.' USING ERRCODE = 'P0002';
    END IF;

    -- Authorization check: admin or staff
    SELECT role_name INTO v_actor_role 
    FROM public.user_roles 
    WHERE user_id = v_actor_id AND society_id = v_booking.society_id;

    IF v_actor_role IS NULL OR v_actor_role NOT IN ('admin', 'technician', 'gatekeeper', 'secretary', 'treasurer', 'executive_member', 'super_admin') THEN
        RAISE EXCEPTION 'Only staff or admin can mark amenity booking complete.' USING ERRCODE = '42501';
    END IF;

    -- Transition check
    IF v_booking.status != 'approved' THEN
        RAISE EXCEPTION 'Invalid transition: booking status % cannot be completed.', v_booking.status USING ERRCODE = '22000';
    END IF;

    -- Set workflow GUC
    PERFORM set_config('app.booking_workflow_context', p_booking_id::text, true);

    UPDATE public.amenity_bookings
    SET status = 'completed',
        updated_at = NOW()
    WHERE id = p_booking_id;

    -- Audit log
    v_payload := jsonb_build_object(
        'booking_id', p_booking_id,
        'old_status', 'approved',
        'new_status', 'completed'
    );
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_booking.society_id, v_actor_id, 'amenity_bookings', p_booking_id, 'BOOKING_COMPLETED', v_payload);

    -- Notification dispatch to resident who booked
    INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
    VALUES (v_booking.society_id, v_booking.booked_by, 'amenity', 'Booking Completed', 'Your amenity booking is marked as completed.', 'amenity_bookings', p_booking_id);
END;
$$;

-- 5.8 checkout_visitor
CREATE OR REPLACE FUNCTION public.checkout_visitor(
    p_visitor_log_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor_id UUID;
    v_log RECORD;
    v_actor_role TEXT;
    v_payload JSONB;
BEGIN
    v_actor_id := auth.uid();
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_log 
    FROM public.visitor_logs 
    WHERE id = p_visitor_log_id 
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Visitor log not found.' USING ERRCODE = 'P0002';
    END IF;

    -- Authorization check: staff or admin
    SELECT role_name INTO v_actor_role 
    FROM public.user_roles 
    WHERE user_id = v_actor_id AND society_id = v_log.society_id;

    IF v_actor_role IS NULL OR v_actor_role NOT IN ('admin', 'technician', 'gatekeeper', 'secretary', 'treasurer', 'executive_member', 'super_admin') THEN
        RAISE EXCEPTION 'Only staff or admin can checkout visitor.' USING ERRCODE = '42501';
    END IF;

    -- State check
    IF v_log.check_out IS NOT NULL THEN
        RAISE EXCEPTION 'Visitor already checked out.' USING ERRCODE = '22000';
    END IF;

    UPDATE public.visitor_logs
    SET check_out = NOW()
    WHERE id = p_visitor_log_id;

    -- Audit log
    v_payload := jsonb_build_object(
        'visitor_log_id', p_visitor_log_id,
        'visitor_name', v_log.visitor_name,
        'check_out', NOW()
    );
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_log.society_id, v_actor_id, 'visitor_logs', p_visitor_log_id, 'VISITOR_CHECKED_OUT', v_payload);

    -- Notification dispatch to resident host
    IF v_log.host_resident_id IS NOT NULL THEN
        INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
        VALUES (v_log.society_id, v_log.host_resident_id, 'visitor', 'Visitor Departed', 'Your visitor has checked out.', 'visitor_logs', p_visitor_log_id);
    END IF;
END;
$$;

-- 6. Revoke PUBLIC execution on workflow functions and grant to authenticated
REVOKE EXECUTE ON FUNCTION public.assign_ticket(UUID, UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.start_ticket(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.resolve_ticket(UUID, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.close_ticket(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.reopen_ticket(UUID, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.reject_amenity_booking(UUID, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.complete_amenity_booking(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.checkout_visitor(UUID) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.assign_ticket(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.start_ticket(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_ticket(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.close_ticket(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reopen_ticket(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_amenity_booking(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_amenity_booking(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.checkout_visitor(UUID) TO authenticated;

COMMIT;
