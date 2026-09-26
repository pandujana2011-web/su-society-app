-- =========================================================================
-- SU SOCIETY APP - SLICE 18 SCHEMA (OPERATIONAL WORKFLOWS & FINANCIAL INTEGRITY)
-- =========================================================================

\set ON_ERROR_STOP on

BEGIN;

-- =========================================================================
-- 1. LEDGER TRANSACTION TYPE CONSTRAINT WIDENING
-- =========================================================================

ALTER TABLE public.ledger_transactions DROP CONSTRAINT IF EXISTS check_transaction_type;
ALTER TABLE public.ledger_transactions DROP CONSTRAINT IF EXISTS chk_tx_type;
ALTER TABLE public.ledger_transactions ADD CONSTRAINT check_transaction_type CHECK (
    transaction_type IN (
        'charge', 'penalty', 'adjustment', 'waiver', 'payment', 'advance_payment',
        'refund', 'reversal', 'expense', 'income', 'amenity_fee', 'opening_balance',
        'booking_charge', 'utility_bill'
    )
);


-- =========================================================================
-- 2. HELPDESK TICKETS SLA TIMESTAMPS
-- =========================================================================

ALTER TABLE public.helpdesk_tickets
    ADD COLUMN IF NOT EXISTS assigned_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS started_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS closed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS reopened_at TIMESTAMPTZ;


-- =========================================================================
-- 3. WORKFLOW ROUTINES (SECURITY DEFINER FUNCTIONS)
-- =========================================================================

-- 3.1 assign_ticket
DROP FUNCTION IF EXISTS public.assign_ticket(UUID, UUID);
CREATE OR REPLACE FUNCTION public.assign_ticket(
    p_ticket_id UUID,
    p_technician_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_caller_society UUID;
    v_ticket RECORD;
    v_is_admin BOOLEAN := FALSE;
    v_tech_role BOOLEAN := FALSE;
    v_old_tech UUID;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    v_caller_society := public.get_user_society_id(v_caller);

    SELECT * INTO v_ticket FROM public.helpdesk_tickets WHERE id = p_ticket_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Helpdesk ticket not found.' USING ERRCODE = '22000';
    END IF;

    IF v_caller_society IS DISTINCT FROM v_ticket.society_id THEN
        RAISE EXCEPTION 'Cross-society execution denied.' USING ERRCODE = '42501';
    END IF;

    v_is_admin := public.is_admin();
    IF NOT v_is_admin AND NOT EXISTS (
        SELECT 1 FROM public.user_roles 
        WHERE society_id = v_ticket.society_id AND user_id = v_caller AND role_name IN ('secretary', 'treasurer', 'executive_member')
    ) THEN
        RAISE EXCEPTION 'Access Denied: Admin or executive committee role required.' USING ERRCODE = '42501';
    END IF;

    -- Verify technician exists and belongs to same society with technician role
    IF EXISTS (
        SELECT 1 FROM public.user_roles 
        WHERE society_id = v_ticket.society_id AND user_id = p_technician_id AND role_name = 'technician'
    ) THEN
        v_tech_role := TRUE;
    END IF;

    IF NOT v_tech_role THEN
        RAISE EXCEPTION 'Target user is not an active technician in this society.' USING ERRCODE = '42501';
    END IF;

    IF v_ticket.status NOT IN ('open', 'assigned') THEN
        RAISE EXCEPTION 'Cannot assign ticket in status %', v_ticket.status USING ERRCODE = '22000';
    END IF;

    v_old_tech := v_ticket.assigned_to;

    PERFORM set_config('app.ticket_workflow_context', p_ticket_id::text, true);

    UPDATE public.helpdesk_tickets 
    SET status = 'assigned', assigned_to = p_technician_id, assigned_at = NOW(), updated_at = NOW()
    WHERE id = p_ticket_id;

    -- Server Audit
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (
        v_ticket.society_id, v_caller, 'helpdesk_ticket', p_ticket_id, 'ASSIGNED helpdesk ticket',
        jsonb_build_object('old_technician', v_old_tech, 'new_technician', p_technician_id, 'status', 'assigned')
    );

    -- Notifications
    IF v_old_tech IS NOT NULL AND v_old_tech IS DISTINCT FROM p_technician_id THEN
        INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
        VALUES (v_ticket.society_id, v_old_tech, 'helpdesk_reassigned', 'Ticket Reassigned Away', 'Ticket "' || v_ticket.title || '" has been reassigned.', 'helpdesk_tickets', p_ticket_id);
    END IF;

    INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
    VALUES (v_ticket.society_id, p_technician_id, 'helpdesk_assigned', 'Ticket Assigned', 'You have been assigned ticket "' || v_ticket.title || '".', 'helpdesk_tickets', p_ticket_id);
END;
$$;


-- 3.2 start_ticket
DROP FUNCTION IF EXISTS public.start_ticket(UUID);
CREATE OR REPLACE FUNCTION public.start_ticket(
    p_ticket_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_caller_society UUID;
    v_ticket RECORD;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    v_caller_society := public.get_user_society_id(v_caller);

    SELECT * INTO v_ticket FROM public.helpdesk_tickets WHERE id = p_ticket_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Helpdesk ticket not found.' USING ERRCODE = '22000';
    END IF;

    IF v_caller_society IS DISTINCT FROM v_ticket.society_id THEN
        RAISE EXCEPTION 'Cross-society execution denied.' USING ERRCODE = '42501';
    END IF;

    IF v_caller IS DISTINCT FROM v_ticket.assigned_to AND NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access Denied: Only assigned technician or admin can start ticket.' USING ERRCODE = '42501';
    END IF;

    IF v_ticket.status IS DISTINCT FROM 'assigned' THEN
        RAISE EXCEPTION 'Ticket must be in assigned state to start work.' USING ERRCODE = '22000';
    END IF;

    PERFORM set_config('app.ticket_workflow_context', p_ticket_id::text, true);

    UPDATE public.helpdesk_tickets
    SET status = 'in_progress', started_at = COALESCE(started_at, NOW()), updated_at = NOW()
    WHERE id = p_ticket_id;

    -- Audit
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_ticket.society_id, v_caller, 'helpdesk_ticket', p_ticket_id, 'STARTED helpdesk ticket', jsonb_build_object('status', 'in_progress'));

    -- Notification to ticket creator
    INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
    VALUES (v_ticket.society_id, v_ticket.reported_by, 'helpdesk_update', 'Work Started on Your Ticket', 'Technician has started work on ticket "' || v_ticket.title || '".', 'helpdesk_tickets', p_ticket_id);
END;
$$;


-- 3.3 resolve_ticket
DROP FUNCTION IF EXISTS public.resolve_ticket(UUID);
DROP FUNCTION IF EXISTS public.resolve_ticket(UUID, TEXT);
CREATE OR REPLACE FUNCTION public.resolve_ticket(
    p_ticket_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_caller_society UUID;
    v_ticket RECORD;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    v_caller_society := public.get_user_society_id(v_caller);

    SELECT * INTO v_ticket FROM public.helpdesk_tickets WHERE id = p_ticket_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Helpdesk ticket not found.' USING ERRCODE = '22000';
    END IF;

    IF v_caller_society IS DISTINCT FROM v_ticket.society_id THEN
        RAISE EXCEPTION 'Cross-society execution denied.' USING ERRCODE = '42501';
    END IF;

    IF v_caller IS DISTINCT FROM v_ticket.assigned_to AND NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access Denied: Only assigned technician or admin can resolve ticket.' USING ERRCODE = '42501';
    END IF;

    IF v_ticket.status IS DISTINCT FROM 'in_progress' THEN
        RAISE EXCEPTION 'Ticket must be in in_progress state to resolve.' USING ERRCODE = '22000';
    END IF;

    PERFORM set_config('app.ticket_workflow_context', p_ticket_id::text, true);

    UPDATE public.helpdesk_tickets
    SET status = 'resolved', updated_at = NOW()
    WHERE id = p_ticket_id;

    -- Audit
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_ticket.society_id, v_caller, 'helpdesk_ticket', p_ticket_id, 'RESOLVED helpdesk ticket', jsonb_build_object('status', 'resolved'));

    -- Notification to ticket creator
    INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
    VALUES (v_ticket.society_id, v_ticket.reported_by, 'helpdesk_resolved', 'Your Ticket Has Been Resolved', 'Ticket "' || v_ticket.title || '" has been resolved.', 'helpdesk_tickets', p_ticket_id);
END;
$$;


-- 3.4 close_ticket
DROP FUNCTION IF EXISTS public.close_ticket(UUID);
CREATE OR REPLACE FUNCTION public.close_ticket(
    p_ticket_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_caller_society UUID;
    v_ticket RECORD;
    v_is_resident BOOLEAN := FALSE;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    v_caller_society := public.get_user_society_id(v_caller);

    SELECT * INTO v_ticket FROM public.helpdesk_tickets WHERE id = p_ticket_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Helpdesk ticket not found.' USING ERRCODE = '22000';
    END IF;

    IF v_caller_society IS DISTINCT FROM v_ticket.society_id THEN
        RAISE EXCEPTION 'Cross-society execution denied.' USING ERRCODE = '42501';
    END IF;

    IF v_caller = v_ticket.reported_by THEN
        v_is_resident := TRUE;
    END IF;

    IF NOT v_is_resident AND NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access Denied: Ticket creator, active property resident, or admin required.' USING ERRCODE = '42501';
    END IF;

    IF v_ticket.status IS DISTINCT FROM 'resolved' THEN
        RAISE EXCEPTION 'Only resolved tickets can be closed.' USING ERRCODE = '22000';
    END IF;

    PERFORM set_config('app.ticket_workflow_context', p_ticket_id::text, true);

    UPDATE public.helpdesk_tickets
    SET status = 'closed', closed_at = NOW(), updated_at = NOW()
    WHERE id = p_ticket_id;

    -- Audit
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_ticket.society_id, v_caller, 'helpdesk_ticket', p_ticket_id, 'CLOSED helpdesk ticket', jsonb_build_object('status', 'closed'));
END;
$$;


-- 3.5 reopen_ticket
DROP FUNCTION IF EXISTS public.reopen_ticket(UUID);
DROP FUNCTION IF EXISTS public.reopen_ticket(UUID, TEXT);
CREATE OR REPLACE FUNCTION public.reopen_ticket(
    p_ticket_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_caller_society UUID;
    v_ticket RECORD;
    v_is_resident BOOLEAN := FALSE;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    v_caller_society := public.get_user_society_id(v_caller);

    SELECT * INTO v_ticket FROM public.helpdesk_tickets WHERE id = p_ticket_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Helpdesk ticket not found.' USING ERRCODE = '22000';
    END IF;

    IF v_caller_society IS DISTINCT FROM v_ticket.society_id THEN
        RAISE EXCEPTION 'Cross-society execution denied.' USING ERRCODE = '42501';
    END IF;

    IF v_caller = v_ticket.reported_by THEN
        v_is_resident := TRUE;
    END IF;

    IF NOT v_is_resident AND NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access Denied: Ticket creator, active property resident, or admin required.' USING ERRCODE = '42501';
    END IF;

    IF v_ticket.status IS DISTINCT FROM 'closed' THEN
        RAISE EXCEPTION 'Only closed tickets can be reopened.' USING ERRCODE = '22000';
    END IF;

    PERFORM set_config('app.ticket_workflow_context', p_ticket_id::text, true);

    UPDATE public.helpdesk_tickets
    SET status = 'open', assigned_to = NULL, reopened_at = NOW(), updated_at = NOW()
    WHERE id = p_ticket_id;

    -- Audit
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_ticket.society_id, v_caller, 'helpdesk_ticket', p_ticket_id, 'REOPENED helpdesk ticket', jsonb_build_object('status', 'open'));

    -- Notification to admin
    INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
    SELECT v_ticket.society_id, u.id, 'helpdesk_reopened', 'Ticket Reopened', 'Ticket "' || v_ticket.title || '" has been reopened.', 'helpdesk_tickets', p_ticket_id
    FROM public.user_roles ur JOIN public.users u ON ur.user_id = u.id
    WHERE ur.society_id = v_ticket.society_id AND ur.role_name IN ('admin', 'super_admin') LIMIT 1;
END;
$$;


-- 3.6 reject_amenity_booking
DROP FUNCTION IF EXISTS public.reject_amenity_booking(UUID, TEXT);
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
    v_caller UUID := auth.uid();
    v_caller_society UUID;
    v_booking RECORD;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    v_caller_society := public.get_user_society_id(v_caller);

    SELECT b.*, a.society_id INTO v_booking 
    FROM public.amenity_bookings b
    JOIN public.amenities a ON a.id = b.amenity_id
    WHERE b.id = p_booking_id FOR UPDATE OF b;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Amenity booking not found.' USING ERRCODE = '22000';
    END IF;

    IF v_caller_society IS DISTINCT FROM v_booking.society_id THEN
        RAISE EXCEPTION 'Cross-society execution denied.' USING ERRCODE = '42501';
    END IF;

    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access Denied: Admin role required to reject booking.' USING ERRCODE = '42501';
    END IF;

    IF v_booking.status IS DISTINCT FROM 'pending_approval' THEN
        RAISE EXCEPTION 'Only pending_approval bookings can be rejected.' USING ERRCODE = '22000';
    END IF;

    PERFORM set_config('app.booking_workflow_context', p_booking_id::text, true);

    UPDATE public.amenity_bookings
    SET status = 'rejected', updated_at = NOW()
    WHERE id = p_booking_id;

    -- Audit
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_booking.society_id, v_caller, 'amenity_booking', p_booking_id, 'REJECTED amenity booking', jsonb_build_object('status', 'rejected', 'reason', p_reason));

    -- Notification to booked_by
    INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
    VALUES (v_booking.society_id, v_booking.booked_by, 'amenity_status', 'Booking Rejected', 'Your amenity booking request was rejected.', 'amenity_bookings', p_booking_id);
END;
$$;


-- 3.7 complete_amenity_booking
DROP FUNCTION IF EXISTS public.complete_amenity_booking(UUID);
CREATE OR REPLACE FUNCTION public.complete_amenity_booking(
    p_booking_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_caller_society UUID;
    v_booking RECORD;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    v_caller_society := public.get_user_society_id(v_caller);

    SELECT b.*, a.society_id INTO v_booking 
    FROM public.amenity_bookings b
    JOIN public.amenities a ON a.id = b.amenity_id
    WHERE b.id = p_booking_id FOR UPDATE OF b;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Amenity booking not found.' USING ERRCODE = '22000';
    END IF;

    IF v_caller_society IS DISTINCT FROM v_booking.society_id THEN
        RAISE EXCEPTION 'Cross-society execution denied.' USING ERRCODE = '42501';
    END IF;

    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access Denied: Admin role required to complete booking.' USING ERRCODE = '42501';
    END IF;

    IF v_booking.status IS DISTINCT FROM 'approved' THEN
        RAISE EXCEPTION 'Only approved bookings can be marked complete.' USING ERRCODE = '22000';
    END IF;

    PERFORM set_config('app.booking_workflow_context', p_booking_id::text, true);

    UPDATE public.amenity_bookings
    SET status = 'completed', updated_at = NOW()
    WHERE id = p_booking_id;

    -- Audit
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_booking.society_id, v_caller, 'amenity_booking', p_booking_id, 'COMPLETED amenity booking', jsonb_build_object('status', 'completed'));

    -- Notification to booked_by
    INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
    VALUES (v_booking.society_id, v_booking.booked_by, 'amenity_status', 'Booking Completed', 'Your amenity booking has been marked complete.', 'amenity_bookings', p_booking_id);
END;
$$;


-- 3.8 checkout_visitor
DROP FUNCTION IF EXISTS public.checkout_visitor(UUID);
CREATE OR REPLACE FUNCTION public.checkout_visitor(
    p_log_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_caller_society UUID;
    v_visitor RECORD;
    v_is_staff BOOLEAN := FALSE;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    v_caller_society := public.get_user_society_id(v_caller);

    SELECT * INTO v_visitor FROM public.visitor_logs WHERE id = p_log_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Visitor log record not found.' USING ERRCODE = '22000';
    END IF;

    IF v_caller_society IS DISTINCT FROM v_visitor.society_id THEN
        RAISE EXCEPTION 'Cross-society execution denied.' USING ERRCODE = '42501';
    END IF;

    IF public.is_admin() OR EXISTS (
        SELECT 1 FROM public.user_roles WHERE society_id = v_visitor.society_id AND user_id = v_caller AND role_name = 'gatekeeper'
    ) THEN
        v_is_staff := TRUE;
    END IF;

    IF NOT v_is_staff THEN
        RAISE EXCEPTION 'Access Denied: Only gatekeeper or admin can checkout visitor.' USING ERRCODE = '42501';
    END IF;

    IF v_visitor.check_out IS NOT NULL THEN
        RAISE EXCEPTION 'Visitor already checked out.' USING ERRCODE = '22000';
    END IF;

    UPDATE public.visitor_logs
    SET check_out = NOW()
    WHERE id = p_log_id;

    -- Audit
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_visitor.society_id, v_caller, 'visitor_log', p_log_id, 'CHECKED OUT visitor', jsonb_build_object('visitor_name', v_visitor.visitor_name));
END;
$$;


-- 3.9 approve_amenity_booking
DROP FUNCTION IF EXISTS public.approve_amenity_booking(UUID);
CREATE OR REPLACE FUNCTION public.approve_amenity_booking(
    p_booking_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_caller_society UUID;
    v_booking RECORD;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    v_caller_society := public.get_user_society_id(v_caller);

    SELECT b.*, a.society_id INTO v_booking 
    FROM public.amenity_bookings b
    JOIN public.amenities a ON a.id = b.amenity_id
    WHERE b.id = p_booking_id FOR UPDATE OF b;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Amenity booking not found.' USING ERRCODE = '22000';
    END IF;

    IF v_caller_society IS DISTINCT FROM v_booking.society_id THEN
        RAISE EXCEPTION 'Cross-society execution denied.' USING ERRCODE = '42501';
    END IF;

    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access Denied: Admin role required to approve booking.' USING ERRCODE = '42501';
    END IF;

    IF v_booking.status IS DISTINCT FROM 'pending_approval' THEN
        RAISE EXCEPTION 'Only pending_approval bookings can be approved.' USING ERRCODE = '22000';
    END IF;

    PERFORM set_config('app.booking_workflow_context', p_booking_id::text, true);

    UPDATE public.amenity_bookings
    SET status = 'approved', updated_at = NOW()
    WHERE id = p_booking_id;

    IF v_booking.total_charges > 0 THEN
        INSERT INTO public.ledger_transactions (
            society_id, scope, property_id, amount, direction, transaction_type, source_booking_id, description, created_by
        ) VALUES (
            v_booking.society_id, 'property', v_booking.property_id, v_booking.total_charges, 'debit', 'amenity_fee', p_booking_id, 'Amenity Booking Fee', v_caller
        );
    END IF;

    -- Audit
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_booking.society_id, v_caller, 'amenity_booking', p_booking_id, 'APPROVED amenity booking', jsonb_build_object('status', 'approved'));

    -- Notification
    INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
    VALUES (v_booking.society_id, v_booking.booked_by, 'amenity_status', 'Booking Approved', 'Your amenity booking has been approved.', 'amenity_bookings', p_booking_id);
END;
$$;


-- 3.10 cancel_amenity_booking
DROP FUNCTION IF EXISTS public.cancel_amenity_booking(UUID);
CREATE OR REPLACE FUNCTION public.cancel_amenity_booking(
    p_booking_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_caller_society UUID;
    v_booking RECORD;
    v_orig_tx UUID;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    v_caller_society := public.get_user_society_id(v_caller);

    SELECT b.*, a.society_id INTO v_booking 
    FROM public.amenity_bookings b
    JOIN public.amenities a ON a.id = b.amenity_id
    WHERE b.id = p_booking_id FOR UPDATE OF b;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Amenity booking not found.' USING ERRCODE = '22000';
    END IF;

    IF v_caller_society IS DISTINCT FROM v_booking.society_id THEN
        RAISE EXCEPTION 'Cross-society execution denied.' USING ERRCODE = '42501';
    END IF;

    IF v_booking.booked_by IS DISTINCT FROM v_caller AND NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access Denied: Only booking creator or admin can cancel.' USING ERRCODE = '42501';
    END IF;

    IF v_booking.status NOT IN ('pending_approval', 'approved') THEN
        RAISE EXCEPTION 'Booking state % cannot be cancelled.', v_booking.status USING ERRCODE = '22000';
    END IF;

    PERFORM set_config('app.booking_workflow_context', p_booking_id::text, true);

    UPDATE public.amenity_bookings
    SET status = 'cancelled', updated_at = NOW()
    WHERE id = p_booking_id;

    IF v_booking.status = 'approved' AND v_booking.total_charges > 0 THEN
        SELECT id INTO v_orig_tx FROM public.ledger_transactions WHERE source_booking_id = p_booking_id AND transaction_type = 'amenity_fee' LIMIT 1;
        
        IF EXISTS (SELECT 1 FROM public.ledger_transactions WHERE reverses_ledger_id = v_orig_tx) THEN
            RAISE EXCEPTION 'Duplicate reversal blocked.' USING ERRCODE = '22000';
        END IF;

        INSERT INTO public.ledger_transactions (
            society_id, scope, property_id, amount, direction, transaction_type, reverses_ledger_id, description, created_by
        ) VALUES (
            v_booking.society_id, 'property', v_booking.property_id, v_booking.total_charges, 'credit', 'reversal', v_orig_tx, 'Amenity Booking Cancellation Reversal', v_caller
        );
    END IF;

    -- Audit
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_booking.society_id, v_caller, 'amenity_booking', p_booking_id, 'CANCELLED amenity booking', jsonb_build_object('status', 'cancelled'));

    -- Notification
    INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
    VALUES (v_booking.society_id, v_booking.booked_by, 'amenity_status', 'Booking Cancelled', 'Your amenity booking has been cancelled.', 'amenity_bookings', p_booking_id);
END;
$$;


-- =========================================================================
-- 4. ROUTINE EXECUTE PRIVILEGES HARDENING
-- =========================================================================

REVOKE EXECUTE ON FUNCTION public.assign_ticket(UUID, UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.start_ticket(UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.resolve_ticket(UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.close_ticket(UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.reopen_ticket(UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.reject_amenity_booking(UUID, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.complete_amenity_booking(UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.checkout_visitor(UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.approve_amenity_booking(UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.cancel_amenity_booking(UUID) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.assign_ticket(UUID, UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.start_ticket(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.resolve_ticket(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.close_ticket(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reopen_ticket(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reject_amenity_booking(UUID, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.complete_amenity_booking(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.checkout_visitor(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.approve_amenity_booking(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.cancel_amenity_booking(UUID) TO authenticated, service_role;

COMMIT;
