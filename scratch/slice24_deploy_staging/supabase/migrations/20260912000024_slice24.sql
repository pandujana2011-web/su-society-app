-- ============================================================================
-- SLICE 24 MIGRATION: OPERATIONS LIFECYCLE COMPLETION & MULTI-ROLE OPERATIONS
-- Target Repository: SU Society App
-- Target Supabase Project: fsegpxqoozxmicxcxjun (ap-south-1)
-- Execution Mode: LOCAL MIGRATION (M-02 ISOLATED WORKSPACE)
-- Authoritative Specs: SLICE24_FORMAL_FORENSIC_SECURITY_PLAN.md (SHA-256: D38AAA5AE63B26CF82897AB279331B2E57D82A92CA7EA3EA5BE744BEF355D254)
--                      SLICE24_ADVERSARIAL_PRE_IMPLEMENTATION_SECURITY_REVIEW.md (SHA-256: 5FEB7779EF3D517C0F6901C2EDB457CF3A6F6A30D9A3061B74F4A41220DF75A8)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. SCHEMA ALIGNMENT & CONSTRAINTS
-- ----------------------------------------------------------------------------

-- S24-055: Add reopen_count to helpdesk_tickets if not present
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'helpdesk_tickets' 
          AND column_name = 'reopen_count'
    ) THEN
        ALTER TABLE public.helpdesk_tickets 
        ADD COLUMN reopen_count INTEGER NOT NULL DEFAULT 0;
    END IF;
END $$;

-- S24-004: Update ledger_transactions check_transaction_type constraint to include 'amenity_fee'
ALTER TABLE public.ledger_transactions 
DROP CONSTRAINT IF EXISTS check_transaction_type;

ALTER TABLE public.ledger_transactions 
ADD CONSTRAINT check_transaction_type 
CHECK (transaction_type IN ('maintenance_fee', 'fine', 'penalty', 'utility_charge', 'payment', 'amenity_fee'));

-- ----------------------------------------------------------------------------
-- 2. HELPDESK TICKET LIFECYCLE PROCEDURES
-- ----------------------------------------------------------------------------

-- S24-005, S24-006, S24-007, S24-008, S24-009, S24-010: Assign Ticket
CREATE OR REPLACE FUNCTION public.fn_assign_helpdesk_ticket(
    p_ticket_id UUID,
    p_technician_id UUID,
    p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_actor_id UUID;
    v_actor_role TEXT;
    v_actor_society_id UUID;
    v_ticket_society_id UUID;
    v_current_status TEXT;
    v_tech_role TEXT;
    v_tech_society_id UUID;
    v_result JSONB;
BEGIN
    v_actor_id := auth.uid();
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Authentication required';
    END IF;

    SELECT society_id, role INTO v_actor_society_id, v_actor_role 
    FROM public.profiles 
    WHERE id = v_actor_id;

    IF v_actor_role IS NULL OR v_actor_role != 'admin' THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Only admins can assign helpdesk tickets';
    END IF;

    -- Lock ticket row for concurrency check
    SELECT society_id, status INTO v_ticket_society_id, v_current_status
    FROM public.helpdesk_tickets
    WHERE id = p_ticket_id
    FOR UPDATE;

    IF v_ticket_society_id IS NULL OR v_ticket_society_id != v_actor_society_id THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Ticket not found or cross-society access denied';
    END IF;

    IF v_current_status != 'open' THEN
        RAISE EXCEPTION USING ERRCODE = '45000', MESSAGE = 'ERR_INVALID_STATE_TRANSITION: Ticket must be in open status to be assigned';
    END IF;

    -- Verify technician
    SELECT society_id, role INTO v_tech_society_id, v_tech_role
    FROM public.profiles
    WHERE id = p_technician_id;

    IF v_tech_role IS NULL OR v_tech_role != 'technician' OR v_tech_society_id != v_actor_society_id THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Target user is not an active technician in caller society';
    END IF;

    -- Update Ticket State
    UPDATE public.helpdesk_tickets
    SET status = 'assigned',
        assigned_to = p_technician_id,
        updated_at = NOW()
    WHERE id = p_ticket_id;

    -- Transactional Audit Entry
    INSERT INTO public.audit_logs (
        actor_id, actor_role, society_id, entity_type, entity_id, action, previous_state, new_state, payload
    ) VALUES (
        v_actor_id, v_actor_role, v_actor_society_id, 'helpdesk_ticket', p_ticket_id, 'ASSIGN',
        jsonb_build_object('status', v_current_status),
        jsonb_build_object('status', 'assigned', 'assigned_to', p_technician_id),
        jsonb_build_object('notes', p_notes)
    );

    -- Transactional Notification to Technician
    INSERT INTO public.notifications (
        user_id, society_id, title, message, type, is_read, created_at
    ) VALUES (
        p_technician_id, v_actor_society_id, 'Ticket Assigned',
        'Helpdesk ticket ' || p_ticket_id || ' has been assigned to you.',
        'helpdesk', FALSE, NOW()
    );

    v_result := jsonb_build_object(
        'success', TRUE,
        'ticket_id', p_ticket_id,
        'status', 'assigned',
        'assigned_to', p_technician_id
    );

    RETURN v_result;
END;
$$;

-- S24-011, S24-012, S24-013, S24-014, S24-054: Start Ticket
CREATE OR REPLACE FUNCTION public.fn_start_helpdesk_ticket(
    p_ticket_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_actor_id UUID;
    v_actor_role TEXT;
    v_actor_society_id UUID;
    v_ticket_society_id UUID;
    v_assigned_to UUID;
    v_current_status TEXT;
    v_result JSONB;
BEGIN
    v_actor_id := auth.uid();
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Authentication required';
    END IF;

    SELECT society_id, role INTO v_actor_society_id, v_actor_role 
    FROM public.profiles 
    WHERE id = v_actor_id;

    -- Lock ticket row for update
    SELECT society_id, status, assigned_to INTO v_ticket_society_id, v_current_status, v_assigned_to
    FROM public.helpdesk_tickets
    WHERE id = p_ticket_id
    FOR UPDATE;

    IF v_ticket_society_id IS NULL OR v_ticket_society_id != v_actor_society_id THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Ticket not found or cross-society access denied';
    END IF;

    IF v_actor_role != 'admin' AND (v_actor_role != 'technician' OR v_assigned_to != v_actor_id) THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Only the assigned technician or an admin can start this ticket';
    END IF;

    IF v_current_status != 'assigned' THEN
        RAISE EXCEPTION USING ERRCODE = '45000', MESSAGE = 'ERR_INVALID_STATE_TRANSITION: Ticket must be in assigned status to be started';
    END IF;

    -- Update Ticket State
    UPDATE public.helpdesk_tickets
    SET status = 'in_progress',
        updated_at = NOW()
    WHERE id = p_ticket_id;

    -- Transactional Audit Entry
    INSERT INTO public.audit_logs (
        actor_id, actor_role, society_id, entity_type, entity_id, action, previous_state, new_state
    ) VALUES (
        v_actor_id, v_actor_role, v_actor_society_id, 'helpdesk_ticket', p_ticket_id, 'START',
        jsonb_build_object('status', v_current_status),
        jsonb_build_object('status', 'in_progress')
    );

    v_result := jsonb_build_object(
        'success', TRUE,
        'ticket_id', p_ticket_id,
        'status', 'in_progress'
    );

    RETURN v_result;
END;
$$;

-- S24-015, S24-016, S24-017, S24-018: Resolve Ticket
CREATE OR REPLACE FUNCTION public.fn_resolve_helpdesk_ticket(
    p_ticket_id UUID,
    p_resolution_notes TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_actor_id UUID;
    v_actor_role TEXT;
    v_actor_society_id UUID;
    v_ticket_society_id UUID;
    v_assigned_to UUID;
    v_created_by UUID;
    v_current_status TEXT;
    v_result JSONB;
BEGIN
    v_actor_id := auth.uid();
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Authentication required';
    END IF;

    IF p_resolution_notes IS NULL OR trim(p_resolution_notes) = '' THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Resolution notes are mandatory when resolving a ticket';
    END IF;

    SELECT society_id, role INTO v_actor_society_id, v_actor_role 
    FROM public.profiles 
    WHERE id = v_actor_id;

    -- Lock ticket row for update
    SELECT society_id, status, assigned_to, created_by 
    INTO v_ticket_society_id, v_current_status, v_assigned_to, v_created_by
    FROM public.helpdesk_tickets
    WHERE id = p_ticket_id
    FOR UPDATE;

    IF v_ticket_society_id IS NULL OR v_ticket_society_id != v_actor_society_id THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Ticket not found or cross-society access denied';
    END IF;

    IF v_actor_role != 'admin' AND (v_actor_role != 'technician' OR v_assigned_to != v_actor_id) THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Only the assigned technician or an admin can resolve this ticket';
    END IF;

    IF v_current_status != 'in_progress' THEN
        RAISE EXCEPTION USING ERRCODE = '45000', MESSAGE = 'ERR_INVALID_STATE_TRANSITION: Ticket must be in in_progress status to be resolved';
    END IF;

    -- Update Ticket State
    UPDATE public.helpdesk_tickets
    SET status = 'resolved',
        resolution_notes = p_resolution_notes,
        resolved_at = NOW(),
        updated_at = NOW()
    WHERE id = p_ticket_id;

    -- Transactional Audit Entry
    INSERT INTO public.audit_logs (
        actor_id, actor_role, society_id, entity_type, entity_id, action, previous_state, new_state, payload
    ) VALUES (
        v_actor_id, v_actor_role, v_actor_society_id, 'helpdesk_ticket', p_ticket_id, 'RESOLVE',
        jsonb_build_object('status', v_current_status),
        jsonb_build_object('status', 'resolved'),
        jsonb_build_object('resolution_notes', p_resolution_notes)
    );

    -- Transactional Notification to Ticket Creator
    IF v_created_by IS NOT NULL THEN
        INSERT INTO public.notifications (
            user_id, society_id, title, message, type, is_read, created_at
        ) VALUES (
            v_created_by, v_actor_society_id, 'Ticket Resolved',
            'Your helpdesk ticket ' || p_ticket_id || ' has been resolved.',
            'helpdesk', FALSE, NOW()
        );
    END IF;

    v_result := jsonb_build_object(
        'success', TRUE,
        'ticket_id', p_ticket_id,
        'status', 'resolved'
    );

    RETURN v_result;
END;
$$;

-- S24-019, S24-020, S24-021: Close Ticket
CREATE OR REPLACE FUNCTION public.fn_close_helpdesk_ticket(
    p_ticket_id UUID,
    p_feedback_rating INT DEFAULT NULL,
    p_feedback_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_actor_id UUID;
    v_actor_role TEXT;
    v_actor_society_id UUID;
    v_ticket_society_id UUID;
    v_created_by UUID;
    v_current_status TEXT;
    v_result JSONB;
BEGIN
    v_actor_id := auth.uid();
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Authentication required';
    END IF;

    IF p_feedback_rating IS NOT NULL AND (p_feedback_rating < 1 OR p_feedback_rating > 5) THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Feedback rating must be between 1 and 5';
    END IF;

    SELECT society_id, role INTO v_actor_society_id, v_actor_role 
    FROM public.profiles 
    WHERE id = v_actor_id;

    -- Lock ticket row for update
    SELECT society_id, status, created_by 
    INTO v_ticket_society_id, v_current_status, v_created_by
    FROM public.helpdesk_tickets
    WHERE id = p_ticket_id
    FOR UPDATE;

    IF v_ticket_society_id IS NULL OR v_ticket_society_id != v_actor_society_id THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Ticket not found or cross-society access denied';
    END IF;

    IF v_actor_role != 'admin' AND v_created_by != v_actor_id THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Only the ticket creator or an admin can close this ticket';
    END IF;

    IF v_current_status != 'resolved' THEN
        RAISE EXCEPTION USING ERRCODE = '45000', MESSAGE = 'ERR_INVALID_STATE_TRANSITION: Ticket must be in resolved status to be closed';
    END IF;

    -- Update Ticket State
    UPDATE public.helpdesk_tickets
    SET status = 'closed',
        closed_at = NOW(),
        updated_at = NOW()
    WHERE id = p_ticket_id;

    -- Transactional Audit Entry
    INSERT INTO public.audit_logs (
        actor_id, actor_role, society_id, entity_type, entity_id, action, previous_state, new_state, payload
    ) VALUES (
        v_actor_id, v_actor_role, v_actor_society_id, 'helpdesk_ticket', p_ticket_id, 'CLOSE',
        jsonb_build_object('status', v_current_status),
        jsonb_build_object('status', 'closed'),
        jsonb_build_object('rating', p_feedback_rating, 'notes', p_feedback_notes)
    );

    v_result := jsonb_build_object(
        'success', TRUE,
        'ticket_id', p_ticket_id,
        'status', 'closed'
    );

    RETURN v_result;
END;
$$;

-- S24-022, S24-023, S24-024, S24-025, TV24-20: Reopen Ticket
CREATE OR REPLACE FUNCTION public.fn_reopen_helpdesk_ticket(
    p_ticket_id UUID,
    p_reopen_reason TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_actor_id UUID;
    v_actor_role TEXT;
    v_actor_society_id UUID;
    v_ticket_society_id UUID;
    v_created_by UUID;
    v_current_status TEXT;
    v_reopen_count INT;
    v_result JSONB;
BEGIN
    v_actor_id := auth.uid();
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Authentication required';
    END IF;

    IF p_reopen_reason IS NULL OR trim(p_reopen_reason) = '' THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Reopen reason is mandatory';
    END IF;

    SELECT society_id, role INTO v_actor_society_id, v_actor_role 
    FROM public.profiles 
    WHERE id = v_actor_id;

    -- Lock ticket row for update
    SELECT society_id, status, created_by, COALESCE(reopen_count, 0)
    INTO v_ticket_society_id, v_current_status, v_created_by, v_reopen_count
    FROM public.helpdesk_tickets
    WHERE id = p_ticket_id
    FOR UPDATE;

    IF v_ticket_society_id IS NULL OR v_ticket_society_id != v_actor_society_id THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Ticket not found or cross-society access denied';
    END IF;

    IF v_actor_role != 'admin' AND v_created_by != v_actor_id THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Only the ticket creator or an admin can reopen this ticket';
    END IF;

    IF v_current_status NOT IN ('resolved', 'closed') THEN
        RAISE EXCEPTION USING ERRCODE = '45000', MESSAGE = 'ERR_INVALID_STATE_TRANSITION: Ticket must be resolved or closed to be reopened';
    END IF;

    IF v_reopen_count >= 3 THEN
        RAISE EXCEPTION USING ERRCODE = '45000', MESSAGE = 'ERR_REOPEN_LIMIT_EXCEEDED: Maximum reopen limit (3) reached for ticket';
    END IF;

    -- Update Ticket State to open, clear assignment, increment reopen_count
    UPDATE public.helpdesk_tickets
    SET status = 'open',
        assigned_to = NULL,
        reopen_count = v_reopen_count + 1,
        updated_at = NOW()
    WHERE id = p_ticket_id;

    -- Transactional Audit Entry
    INSERT INTO public.audit_logs (
        actor_id, actor_role, society_id, entity_type, entity_id, action, previous_state, new_state, payload
    ) VALUES (
        v_actor_id, v_actor_role, v_actor_society_id, 'helpdesk_ticket', p_ticket_id, 'REOPEN',
        jsonb_build_object('status', v_current_status, 'reopen_count', v_reopen_count),
        jsonb_build_object('status', 'open', 'reopen_count', v_reopen_count + 1),
        jsonb_build_object('reopen_reason', p_reopen_reason)
    );

    v_result := jsonb_build_object(
        'success', TRUE,
        'ticket_id', p_ticket_id,
        'status', 'open',
        'reopen_count', v_reopen_count + 1
    );

    RETURN v_result;
END;
$$;

-- ----------------------------------------------------------------------------
-- 3. VISITOR LIFECYCLE COMPLETION PROCEDURES
-- ----------------------------------------------------------------------------

-- S24-026, S24-027, S24-028, S24-029, S24-030, S24-031, S24-032: Checkout Visitor
CREATE OR REPLACE FUNCTION public.fn_checkout_visitor(
    p_visitor_id UUID,
    p_exit_gate TEXT DEFAULT 'main_gate'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_actor_id UUID;
    v_actor_role TEXT;
    v_actor_society_id UUID;
    v_visitor_society_id UUID;
    v_host_resident_id UUID;
    v_visitor_name TEXT;
    v_current_status TEXT;
    v_result JSONB;
BEGIN
    v_actor_id := auth.uid();
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Authentication required';
    END IF;

    SELECT society_id, role INTO v_actor_society_id, v_actor_role 
    FROM public.profiles 
    WHERE id = v_actor_id;

    IF v_actor_role IS NULL OR v_actor_role NOT IN ('gatekeeper', 'admin') THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Only gatekeepers or admins can check out visitors';
    END IF;

    -- Pessimistic Lock for Concurrency Protection (S24-029, S24-031)
    SELECT society_id, status, host_resident_id, visitor_name
    INTO v_visitor_society_id, v_current_status, v_host_resident_id, v_visitor_name
    FROM public.visitors
    WHERE id = p_visitor_id
    FOR UPDATE;

    IF v_visitor_society_id IS NULL OR v_visitor_society_id != v_actor_society_id THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Visitor not found or cross-society access denied';
    END IF;

    IF v_current_status = 'checked_out' THEN
        RAISE EXCEPTION USING ERRCODE = '45000', MESSAGE = 'VISITOR_ALREADY_CHECKED_OUT: Visitor has already been checked out';
    END IF;

    IF v_current_status != 'checked_in' THEN
        RAISE EXCEPTION USING ERRCODE = '45000', MESSAGE = 'ERR_INVALID_STATE_TRANSITION: Visitor must be in checked_in status to checkout';
    END IF;

    -- Update Visitor State
    UPDATE public.visitors
    SET status = 'checked_out',
        check_out_time = NOW(),
        exit_gate = p_exit_gate,
        updated_at = NOW()
    WHERE id = p_visitor_id;

    -- Transactional Audit Entry
    INSERT INTO public.audit_logs (
        actor_id, actor_role, society_id, entity_type, entity_id, action, previous_state, new_state, payload
    ) VALUES (
        v_actor_id, v_actor_role, v_actor_society_id, 'visitor', p_visitor_id, 'CHECKOUT',
        jsonb_build_object('status', v_current_status),
        jsonb_build_object('status', 'checked_out', 'exit_gate', p_exit_gate),
        jsonb_build_object('visitor_name', v_visitor_name)
    );

    -- Transactional Notification to Host Resident
    IF v_host_resident_id IS NOT NULL THEN
        INSERT INTO public.notifications (
            user_id, society_id, title, message, type, is_read, created_at
        ) VALUES (
            v_host_resident_id, v_actor_society_id, 'Visitor Checked Out',
            'Visitor ' || COALESCE(v_visitor_name, 'Guest') || ' has departed via ' || p_exit_gate || '.',
            'visitor', FALSE, NOW()
        );
    END IF;

    v_result := jsonb_build_object(
        'success', TRUE,
        'visitor_id', p_visitor_id,
        'status', 'checked_out',
        'exit_gate', p_exit_gate
    );

    RETURN v_result;
END;
$$;

-- ----------------------------------------------------------------------------
-- 4. AMENITY BOOKING TERMINAL LIFECYCLE PROCEDURES
-- ----------------------------------------------------------------------------

-- S24-033, S24-034, S24-035: Reject Amenity Booking
CREATE OR REPLACE FUNCTION public.fn_reject_amenity_booking(
    p_booking_id UUID,
    p_rejection_reason TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_actor_id UUID;
    v_actor_role TEXT;
    v_actor_society_id UUID;
    v_booking_society_id UUID;
    v_applicant_id UUID;
    v_current_status TEXT;
    v_result JSONB;
BEGIN
    v_actor_id := auth.uid();
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Authentication required';
    END IF;

    IF p_rejection_reason IS NULL OR trim(p_rejection_reason) = '' THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Rejection reason is mandatory';
    END IF;

    SELECT society_id, role INTO v_actor_society_id, v_actor_role 
    FROM public.profiles 
    WHERE id = v_actor_id;

    IF v_actor_role IS NULL OR v_actor_role != 'admin' THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Only admins can reject amenity bookings';
    END IF;

    -- Lock booking row for update
    SELECT society_id, status, resident_id
    INTO v_booking_society_id, v_current_status, v_applicant_id
    FROM public.amenity_bookings
    WHERE id = p_booking_id
    FOR UPDATE;

    IF v_booking_society_id IS NULL OR v_booking_society_id != v_actor_society_id THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Booking not found or cross-society access denied';
    END IF;

    IF v_current_status != 'pending' THEN
        RAISE EXCEPTION USING ERRCODE = '45000', MESSAGE = 'ERR_INVALID_STATE_TRANSITION: Booking must be in pending status to be rejected';
    END IF;

    -- Update Booking State to rejected
    UPDATE public.amenity_bookings
    SET status = 'rejected',
        rejection_reason = p_rejection_reason,
        updated_at = NOW()
    WHERE id = p_booking_id;

    -- Transactional Audit Entry
    INSERT INTO public.audit_logs (
        actor_id, actor_role, society_id, entity_type, entity_id, action, previous_state, new_state, payload
    ) VALUES (
        v_actor_id, v_actor_role, v_actor_society_id, 'amenity_booking', p_booking_id, 'REJECT',
        jsonb_build_object('status', v_current_status),
        jsonb_build_object('status', 'rejected'),
        jsonb_build_object('rejection_reason', p_rejection_reason)
    );

    -- Transactional Notification to Applicant
    IF v_applicant_id IS NOT NULL THEN
        INSERT INTO public.notifications (
            user_id, society_id, title, message, type, is_read, created_at
        ) VALUES (
            v_applicant_id, v_actor_society_id, 'Amenity Booking Rejected',
            'Your amenity booking ' || p_booking_id || ' was rejected: ' || p_rejection_reason,
            'amenity', FALSE, NOW()
        );
    END IF;

    v_result := jsonb_build_object(
        'success', TRUE,
        'booking_id', p_booking_id,
        'status', 'rejected'
    );

    RETURN v_result;
END;
$$;

-- S24-036, S24-037, S24-038, S24-039, TV24-22: Complete Amenity Booking
CREATE OR REPLACE FUNCTION public.fn_complete_amenity_booking(
    p_booking_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_actor_id UUID;
    v_actor_role TEXT;
    v_actor_society_id UUID;
    v_booking_society_id UUID;
    v_current_status TEXT;
    v_booking_end TIMESTAMPTZ;
    v_result JSONB;
BEGIN
    v_actor_id := auth.uid();
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Authentication required';
    END IF;

    SELECT society_id, role INTO v_actor_society_id, v_actor_role 
    FROM public.profiles 
    WHERE id = v_actor_id;

    IF v_actor_role IS NULL OR v_actor_role NOT IN ('admin', 'gatekeeper') THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Only admins or gatekeepers can complete amenity bookings';
    END IF;

    -- Lock booking row for update
    SELECT society_id, status, booking_end
    INTO v_booking_society_id, v_current_status, v_booking_end
    FROM public.amenity_bookings
    WHERE id = p_booking_id
    FOR UPDATE;

    IF v_booking_society_id IS NULL OR v_booking_society_id != v_actor_society_id THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Booking not found or cross-society access denied';
    END IF;

    IF v_current_status != 'approved' THEN
        RAISE EXCEPTION USING ERRCODE = '45000', MESSAGE = 'ERR_INVALID_STATE_TRANSITION: Booking must be in approved status to be completed';
    END IF;

    -- Server-time authority check (TV24-22)
    IF v_booking_end IS NOT NULL AND v_booking_end > NOW() THEN
        RAISE EXCEPTION USING ERRCODE = '45000', MESSAGE = 'ERR_BOOKING_NOT_FINISHED: Booking end time has not yet passed';
    END IF;

    -- Update Booking State to completed (terminal state)
    UPDATE public.amenity_bookings
    SET status = 'completed',
        updated_at = NOW()
    WHERE id = p_booking_id;

    -- Transactional Audit Entry
    INSERT INTO public.audit_logs (
        actor_id, actor_role, society_id, entity_type, entity_id, action, previous_state, new_state
    ) VALUES (
        v_actor_id, v_actor_role, v_actor_society_id, 'amenity_booking', p_booking_id, 'COMPLETE',
        jsonb_build_object('status', v_current_status),
        jsonb_build_object('status', 'completed')
    );

    v_result := jsonb_build_object(
        'success', TRUE,
        'booking_id', p_booking_id,
        'status', 'completed'
    );

    RETURN v_result;
END;
$$;

-- ----------------------------------------------------------------------------
-- 5. OPERATIONAL REPORTING DASHBOARD METRICS
-- ----------------------------------------------------------------------------

-- S24-051, S24-052: Operations Dashboard Metrics
CREATE OR REPLACE FUNCTION public.fn_get_operations_dashboard_metrics()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_actor_id UUID;
    v_actor_role TEXT;
    v_society_id UUID;
    v_open_tickets INT := 0;
    v_assigned_tickets INT := 0;
    v_in_progress_tickets INT := 0;
    v_avg_resolution_hours NUMERIC := 0.0;
    v_active_visitors INT := 0;
    v_active_bookings INT := 0;
    v_total_amenity_fee_debits NUMERIC := 0.0;
    v_result JSONB;
BEGIN
    v_actor_id := auth.uid();
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Authentication required';
    END IF;

    SELECT society_id, role INTO v_society_id, v_actor_role 
    FROM public.profiles 
    WHERE id = v_actor_id;

    IF v_actor_role IS NULL OR v_actor_role NOT IN ('admin', 'gatekeeper', 'technician') THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Operational reporting restricted to staff roles';
    END IF;

    -- Helpdesk counts
    SELECT 
        COUNT(*) FILTER (WHERE status = 'open'),
        COUNT(*) FILTER (WHERE status = 'assigned'),
        COUNT(*) FILTER (WHERE status = 'in_progress')
    INTO v_open_tickets, v_assigned_tickets, v_in_progress_tickets
    FROM public.helpdesk_tickets
    WHERE society_id = v_society_id;

    -- Mean resolution time in hours
    SELECT COALESCE(ROUND(AVG(EXTRACT(EPOCH FROM (resolved_at - created_at))/3600.0)::numeric, 2), 0.0)
    INTO v_avg_resolution_hours
    FROM public.helpdesk_tickets
    WHERE society_id = v_society_id AND resolved_at IS NOT NULL;

    -- Active checked_in visitors
    SELECT COUNT(*) INTO v_active_visitors
    FROM public.visitors
    WHERE society_id = v_society_id AND status = 'checked_in';

    -- Active approved amenity bookings
    SELECT COUNT(*) INTO v_active_bookings
    FROM public.amenity_bookings
    WHERE society_id = v_society_id AND status = 'approved' AND booking_end >= NOW();

    -- Total amenity fee debits
    SELECT COALESCE(SUM(amount), 0.0) INTO v_total_amenity_fee_debits
    FROM public.ledger_transactions
    WHERE society_id = v_society_id AND transaction_type = 'amenity_fee';

    v_result := jsonb_build_object(
        'society_id', v_society_id,
        'open_tickets', v_open_tickets,
        'assigned_tickets', v_assigned_tickets,
        'in_progress_tickets', v_in_progress_tickets,
        'avg_resolution_hours', v_avg_resolution_hours,
        'active_visitors_in_compound', v_active_visitors,
        'active_amenity_bookings', v_active_bookings,
        'total_amenity_fee_debits', v_total_amenity_fee_debits,
        'generated_at', NOW()
    );

    RETURN v_result;
END;
$$;

-- ----------------------------------------------------------------------------
-- 6. GRANT HARDENING & SECURITY ACCESS CONTROL
-- ----------------------------------------------------------------------------

-- S24-046, S24-047: Revoke from public/anon, Grant to authenticated
REVOKE EXECUTE ON FUNCTION public.fn_assign_helpdesk_ticket(UUID, UUID, TEXT) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.fn_start_helpdesk_ticket(UUID) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.fn_resolve_helpdesk_ticket(UUID, TEXT) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.fn_close_helpdesk_ticket(UUID, INT, TEXT) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.fn_reopen_helpdesk_ticket(UUID, TEXT) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.fn_checkout_visitor(UUID, TEXT) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.fn_reject_amenity_booking(UUID, TEXT) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.fn_complete_amenity_booking(UUID) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.fn_get_operations_dashboard_metrics() FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.fn_assign_helpdesk_ticket(UUID, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_start_helpdesk_ticket(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_resolve_helpdesk_ticket(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_close_helpdesk_ticket(UUID, INT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_reopen_helpdesk_ticket(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_checkout_visitor(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_reject_amenity_booking(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_complete_amenity_booking(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_get_operations_dashboard_metrics() TO authenticated;

-- ============================================================================
-- END OF MIGRATION 20260912000024_SLICE24.SQL
-- ============================================================================
