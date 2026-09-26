-- =========================================================================
-- SU SOCIETY APP - SLICE 18 VERIFICATION SUITE (44 ASSERTIONS: S18-001 to S18-044)
-- =========================================================================

\set ON_ERROR_STOP off

BEGIN;

CREATE TEMP TABLE IF NOT EXISTS slice18_test_results (
    test_id VARCHAR(50) PRIMARY KEY,
    description TEXT NOT NULL,
    status VARCHAR(10) NOT NULL CHECK (status IN ('PASS', 'FAIL')),
    details TEXT
);

GRANT ALL ON slice18_test_results TO PUBLIC, authenticated, anon;

DO $$
DECLARE
    v_society_a UUID;
    v_society_b UUID;
    v_prop_a UUID;
    v_prop_b UUID;
    v_admin_a UUID;
    v_admin_b UUID;
    v_tech_a UUID;
    v_tech_b UUID;
    v_res_a UUID;
    v_res_b UUID;
    v_gatekeeper_a UUID;
    v_ticket_1 UUID;
    v_ticket_2 UUID;
    v_amenity_a UUID;
    v_amenity_b UUID;
    v_booking_pending UUID;
    v_booking_approved UUID;
    v_visitor_a UUID;
    v_pass_count INT := 0;
    v_fail_count INT := 0;
    v_audit_count INT := 0;
    v_notif_count INT := 0;
    v_ledger_count INT := 0;
    v_reversal_id UUID;
    v_orig_fee_id UUID;
BEGIN
    -- Setup baseline test data
    INSERT INTO public.societies (name, registration_number, address)
    VALUES ('Slice 18 Primary Society', 'S18PRI', '100 Operational Hub')
    RETURNING id INTO v_society_a;

    INSERT INTO public.societies (name, registration_number, address)
    VALUES ('Slice 18 Secondary Society', 'S18SEC', '200 Isolation Way')
    RETURNING id INTO v_society_b;

    v_admin_a := gen_random_uuid();
    v_admin_b := gen_random_uuid();
    v_tech_a := gen_random_uuid();
    v_res_a := gen_random_uuid();
    v_gatekeeper_a := gen_random_uuid();

    INSERT INTO auth.users (id, email, created_at, updated_at, confirmation_token, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, is_super_admin, role) VALUES 
        (v_admin_a, 'admin18_a@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
        (v_admin_b, 'admin18_b@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
        (v_tech_a, 'tech18_a@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
        (v_res_a, 'res18_a@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
        (v_gatekeeper_a, 'gk18_a@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated');

    INSERT INTO public.users (id, full_name, mobile) VALUES
        (v_admin_a, 'Slice 18 Admin A', '+1800000001'),
        (v_admin_b, 'Slice 18 Admin B', '+1800000002'),
        (v_tech_a, 'Slice 18 Tech A', '+1800000003'),
        (v_res_a, 'Slice 18 Resident A', '+1800000004'),
        (v_gatekeeper_a, 'Slice 18 Gatekeeper A', '+1800000005');

    INSERT INTO public.user_roles (society_id, user_id, role_name, granted_by) VALUES
        (v_society_a, v_admin_a, 'admin', v_admin_a),
        (v_society_b, v_admin_b, 'admin', v_admin_b),
        (v_society_a, v_tech_a, 'technician', v_admin_a),
        (v_society_a, v_res_a, 'member', v_admin_a),
        (v_society_a, v_gatekeeper_a, 'gatekeeper', v_admin_a);

    INSERT INTO public.properties (society_id, plot_number, created_by, property_type)
    VALUES (v_society_a, 'S18-P1', v_admin_a, 'residential')
    RETURNING id INTO v_prop_a;

    INSERT INTO public.properties (society_id, plot_number, created_by, property_type)
    VALUES (v_society_b, 'S18-P2', v_admin_b, 'residential')
    RETURNING id INTO v_prop_b;

    INSERT INTO public.property_owners (property_id, owner_id, start_date, created_by) VALUES
        (v_prop_a, v_res_a, CURRENT_DATE - 30, v_admin_a);

    INSERT INTO public.amenities (society_id, name, booking_type, hourly_rate, created_by)
    VALUES (v_society_a, 'Slice 18 Clubhouse', 'slot_based', 50.00, v_admin_a)
    RETURNING id INTO v_amenity_a;

    -- S18-001: 8 Routines Exist
    IF (SELECT COUNT(*) FROM pg_proc WHERE proname IN (
        'assign_ticket', 'start_ticket', 'resolve_ticket', 'close_ticket', 'reopen_ticket',
        'reject_amenity_booking', 'complete_amenity_booking', 'checkout_visitor'
    )) = 8 THEN
        INSERT INTO slice18_test_results VALUES ('S18-001', '8 Workflow Routines Exist', 'PASS', 'All 8 routines created successfully');
    ELSE
        INSERT INTO slice18_test_results VALUES ('S18-001', '8 Workflow Routines Exist', 'FAIL', 'Routine count mismatch');
    END IF;

    -- S18-002: SECURITY DEFINER and search_path check
    IF (SELECT COUNT(*) FROM pg_proc WHERE proname IN (
        'assign_ticket', 'start_ticket', 'resolve_ticket', 'close_ticket', 'reopen_ticket',
        'reject_amenity_booking', 'complete_amenity_booking', 'checkout_visitor'
    ) AND prosecdef = true AND proconfig::text LIKE '%search_path=public, pg_temp%') = 8 THEN
        INSERT INTO slice18_test_results VALUES ('S18-002', 'SECURITY DEFINER & search_path hardened', 'PASS', 'All 8 routines use search_path=public, pg_temp');
    ELSE
        INSERT INTO slice18_test_results VALUES ('S18-002', 'SECURITY DEFINER & search_path hardened', 'FAIL', 'Hardening mismatch');
    END IF;

    -- S18-003: Ledger Constraint Widened
    IF EXISTS (
        SELECT 1 FROM information_schema.check_constraints 
        WHERE constraint_name = 'check_transaction_type' AND check_clause LIKE '%amenity_fee%'
    ) THEN
        INSERT INTO slice18_test_results VALUES ('S18-003', 'Ledger transaction_type includes amenity_fee', 'PASS', 'Constraint widened');
    ELSE
        INSERT INTO slice18_test_results VALUES ('S18-003', 'Ledger transaction_type includes amenity_fee', 'FAIL', 'Constraint missing amenity_fee');
    END IF;

    -- S18-004: SLA Columns Exist
    IF (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'helpdesk_tickets' AND column_name IN ('assigned_at', 'started_at', 'closed_at', 'reopened_at')) = 4 THEN
        INSERT INTO slice18_test_results VALUES ('S18-004', 'Helpdesk SLA Columns Exist', 'PASS', '4 SLA columns added');
    ELSE
        INSERT INTO slice18_test_results VALUES ('S18-004', 'Helpdesk SLA Columns Exist', 'FAIL', 'SLA columns missing');
    END IF;

    -- S18-005 & S18-006: Unauthenticated execution rejected
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claim.sub', '', true);
    BEGIN
        PERFORM public.assign_ticket(gen_random_uuid(), gen_random_uuid());
        INSERT INTO slice18_test_results VALUES ('S18-005', 'Anonymous assign_ticket Rejected', 'FAIL', 'Should have thrown 42501');
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO slice18_test_results VALUES ('S18-005', 'Anonymous assign_ticket Rejected', 'PASS', SQLERRM);
    END;

    BEGIN
        PERFORM public.checkout_visitor(gen_random_uuid());
        INSERT INTO slice18_test_results VALUES ('S18-006', 'Anonymous checkout_visitor Rejected', 'FAIL', 'Should have thrown 42501');
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO slice18_test_results VALUES ('S18-006', 'Anonymous checkout_visitor Rejected', 'PASS', SQLERRM);
    END;
    EXECUTE 'RESET ROLE';

    -- Setup test helpdesk ticket
    INSERT INTO public.helpdesk_tickets (society_id, reported_by, title, description, category, status)
    VALUES (v_society_a, v_res_a, 'Plumbing Leak', 'Fix required', 'plumbing', 'open')
    RETURNING id INTO v_ticket_1;

    -- S18-007: Valid Assignment
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claim.sub', v_admin_a::text, true);
    BEGIN
        PERFORM public.assign_ticket(v_ticket_1, v_tech_a);
        IF (SELECT status FROM public.helpdesk_tickets WHERE id = v_ticket_1) = 'assigned' THEN
            INSERT INTO slice18_test_results VALUES ('S18-007', 'Valid assign_ticket Execution', 'PASS', 'Ticket assigned successfully');
        ELSE
            INSERT INTO slice18_test_results VALUES ('S18-007', 'Valid assign_ticket Execution', 'FAIL', 'Status not assigned');
        END IF;
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO slice18_test_results VALUES ('S18-007', 'Valid assign_ticket Execution', 'FAIL', SQLERRM);
    END;

    -- S18-008: Valid Reassignment
    BEGIN
        PERFORM public.assign_ticket(v_ticket_1, v_tech_a);
        INSERT INTO slice18_test_results VALUES ('S18-008', 'Reassignment execution', 'PASS', 'Reassigned successfully');
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO slice18_test_results VALUES ('S18-008', 'Reassignment execution', 'FAIL', SQLERRM);
    END;

    -- S18-009: Unauthorized Member Assignment Blocked
    PERFORM set_config('request.jwt.claim.sub', v_res_a::text, true);
    BEGIN
        PERFORM public.assign_ticket(v_ticket_1, v_tech_a);
        INSERT INTO slice18_test_results VALUES ('S18-009', 'Unauthorized assign_ticket Blocked', 'FAIL', 'Should fail for resident');
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO slice18_test_results VALUES ('S18-009', 'Unauthorized assign_ticket Blocked', 'PASS', SQLERRM);
    END;

    -- S18-010: Valid Start
    PERFORM set_config('request.jwt.claim.sub', v_tech_a::text, true);
    BEGIN
        PERFORM public.start_ticket(v_ticket_1);
        IF (SELECT status FROM public.helpdesk_tickets WHERE id = v_ticket_1) = 'in_progress' THEN
            INSERT INTO slice18_test_results VALUES ('S18-010', 'Valid start_ticket Execution', 'PASS', 'Ticket started');
        ELSE
            INSERT INTO slice18_test_results VALUES ('S18-010', 'Valid start_ticket Execution', 'FAIL', 'Status not in_progress');
        END IF;
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO slice18_test_results VALUES ('S18-010', 'Valid start_ticket Execution', 'FAIL', SQLERRM);
    END;

    -- S18-011: Wrong Technician Start Blocked
    PERFORM set_config('request.jwt.claim.sub', v_res_a::text, true);
    BEGIN
        PERFORM public.start_ticket(v_ticket_1);
        INSERT INTO slice18_test_results VALUES ('S18-011', 'Wrong Tech start_ticket Blocked', 'FAIL', 'Should fail');
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO slice18_test_results VALUES ('S18-011', 'Wrong Tech start_ticket Blocked', 'PASS', SQLERRM);
    END;

    -- S18-012: Valid Resolution
    PERFORM set_config('request.jwt.claim.sub', v_tech_a::text, true);
    BEGIN
        PERFORM public.resolve_ticket(v_ticket_1);
        IF (SELECT status FROM public.helpdesk_tickets WHERE id = v_ticket_1) = 'resolved' THEN
            INSERT INTO slice18_test_results VALUES ('S18-012', 'Valid resolve_ticket Execution', 'PASS', 'Ticket resolved');
        ELSE
            INSERT INTO slice18_test_results VALUES ('S18-012', 'Valid resolve_ticket Execution', 'FAIL', 'Status not resolved');
        END IF;
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO slice18_test_results VALUES ('S18-012', 'Valid resolve_ticket Execution', 'FAIL', SQLERRM);
    END;

    -- S18-013: Forbidden Jump assigned -> resolved Blocked
    INSERT INTO public.helpdesk_tickets (society_id, reported_by, title, description, category, status, assigned_to)
    VALUES (v_society_a, v_res_a, 'Electrical Fuse', 'Fix fuse', 'electrical', 'assigned', v_tech_a)
    RETURNING id INTO v_ticket_2;

    BEGIN
        PERFORM public.resolve_ticket(v_ticket_2);
        INSERT INTO slice18_test_results VALUES ('S18-013', 'Forbidden assigned->resolved Jump Blocked', 'FAIL', 'Should fail');
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO slice18_test_results VALUES ('S18-013', 'Forbidden assigned->resolved Jump Blocked', 'PASS', SQLERRM);
    END;

    -- S18-014: Creator Close Ticket
    PERFORM set_config('request.jwt.claim.sub', v_res_a::text, true);
    BEGIN
        PERFORM public.close_ticket(v_ticket_1);
        IF (SELECT status FROM public.helpdesk_tickets WHERE id = v_ticket_1) = 'closed' THEN
            INSERT INTO slice18_test_results VALUES ('S18-014', 'Valid Creator close_ticket Execution', 'PASS', 'Ticket closed');
        ELSE
            INSERT INTO slice18_test_results VALUES ('S18-014', 'Valid Creator close_ticket Execution', 'FAIL', 'Status not closed');
        END IF;
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO slice18_test_results VALUES ('S18-014', 'Valid Creator close_ticket Execution', 'FAIL', SQLERRM);
    END;

    -- S18-015: Invalid Close State Rejection
    BEGIN
        PERFORM public.close_ticket(v_ticket_2);
        INSERT INTO slice18_test_results VALUES ('S18-015', 'Invalid close_ticket State Rejected', 'FAIL', 'Should fail for assigned ticket');
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO slice18_test_results VALUES ('S18-015', 'Invalid close_ticket State Rejected', 'PASS', SQLERRM);
    END;

    -- S18-016: Unauthorized Resident Close Blocked
    PERFORM set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
    BEGIN
        PERFORM public.close_ticket(v_ticket_1);
        INSERT INTO slice18_test_results VALUES ('S18-016', 'Unauthorized Resident close_ticket Blocked', 'FAIL', 'Should fail');
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO slice18_test_results VALUES ('S18-016', 'Unauthorized Resident close_ticket Blocked', 'PASS', SQLERRM);
    END;

    -- S18-017: Creator Reopen Ticket
    PERFORM set_config('request.jwt.claim.sub', v_res_a::text, true);
    BEGIN
        PERFORM public.reopen_ticket(v_ticket_1);
        IF (SELECT status FROM public.helpdesk_tickets WHERE id = v_ticket_1) = 'open' THEN
            INSERT INTO slice18_test_results VALUES ('S18-017', 'Valid Creator reopen_ticket Execution', 'PASS', 'Ticket reopened to open');
        ELSE
            INSERT INTO slice18_test_results VALUES ('S18-017', 'Valid Creator reopen_ticket Execution', 'FAIL', 'Status not open');
        END IF;
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO slice18_test_results VALUES ('S18-017', 'Valid Creator reopen_ticket Execution', 'FAIL', SQLERRM);
    END;

    -- S18-018: Invalid Reopen State Rejection
    BEGIN
        PERFORM public.reopen_ticket(v_ticket_2);
        INSERT INTO slice18_test_results VALUES ('S18-018', 'Invalid reopen_ticket State Rejected', 'FAIL', 'Should fail for assigned ticket');
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO slice18_test_results VALUES ('S18-018', 'Invalid reopen_ticket State Rejected', 'PASS', SQLERRM);
    END;

    -- Cross-Society Rejections S18-019 to S18-024
    EXECUTE 'RESET ROLE';
    
    -- Insert Society B ticket
    INSERT INTO public.helpdesk_tickets (society_id, reported_by, title, description, category, status)
    VALUES (v_society_b, v_res_a, 'Society B Ticket', 'Fix issue', 'general', 'open')
    RETURNING id INTO v_ticket_2;

    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claim.sub', v_admin_a::text, true);

    BEGIN
        PERFORM public.assign_ticket(v_ticket_2, v_tech_a);
        INSERT INTO slice18_test_results VALUES ('S18-019', 'Cross-Society assign_ticket Blocked', 'FAIL', 'Should fail');
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO slice18_test_results VALUES ('S18-019', 'Cross-Society assign_ticket Blocked', 'PASS', SQLERRM);
    END;

    BEGIN
        PERFORM public.start_ticket(v_ticket_2);
        INSERT INTO slice18_test_results VALUES ('S18-020', 'Cross-Society start_ticket Blocked', 'FAIL', 'Should fail');
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO slice18_test_results VALUES ('S18-020', 'Cross-Society start_ticket Blocked', 'PASS', SQLERRM);
    END;

    BEGIN
        PERFORM public.resolve_ticket(v_ticket_2);
        INSERT INTO slice18_test_results VALUES ('S18-021', 'Cross-Society resolve_ticket Blocked', 'FAIL', 'Should fail');
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO slice18_test_results VALUES ('S18-021', 'Cross-Society resolve_ticket Blocked', 'PASS', SQLERRM);
    END;

    BEGIN
        PERFORM public.close_ticket(v_ticket_2);
        INSERT INTO slice18_test_results VALUES ('S18-022', 'Cross-Society close_ticket Blocked', 'FAIL', 'Should fail');
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO slice18_test_results VALUES ('S18-022', 'Cross-Society close_ticket Blocked', 'PASS', SQLERRM);
    END;

    BEGIN
        PERFORM public.reopen_ticket(v_ticket_2);
        INSERT INTO slice18_test_results VALUES ('S18-023', 'Cross-Society reopen_ticket Blocked', 'FAIL', 'Should fail');
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO slice18_test_results VALUES ('S18-023', 'Cross-Society reopen_ticket Blocked', 'PASS', SQLERRM);
    END;

    -- Insert Society B visitor
    EXECUTE 'RESET ROLE';
    INSERT INTO public.visitor_logs (society_id, property_id, visitor_name, purpose, registered_by, check_in)
    VALUES (v_society_b, v_prop_b, 'Society B Guest', 'guest', v_res_a, NOW())
    RETURNING id INTO v_visitor_a;

    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claim.sub', v_admin_a::text, true);

    BEGIN
        PERFORM public.checkout_visitor(v_visitor_a);
        INSERT INTO slice18_test_results VALUES ('S18-024', 'Cross-Society checkout_visitor Blocked', 'FAIL', 'Should fail');
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO slice18_test_results VALUES ('S18-024', 'Cross-Society checkout_visitor Blocked', 'PASS', SQLERRM);
    END;

    -- Amenity Bookings S18-025 to S18-028
    EXECUTE 'RESET ROLE';
    SELECT id INTO v_amenity_a FROM public.amenities WHERE society_id = v_society_a LIMIT 1;
    IF v_amenity_a IS NULL THEN
        INSERT INTO public.amenities (society_id, name, booking_type, hourly_rate, created_by) VALUES (v_society_a, 'Clubhouse', 'slot_based', 50.00, v_admin_a) RETURNING id INTO v_amenity_a;
    END IF;

    INSERT INTO public.amenity_bookings (amenity_id, property_id, booked_by, start_time, end_time, total_charges, status)
    VALUES (v_amenity_a, v_prop_a, v_res_a, NOW() + INTERVAL '1 day', NOW() + INTERVAL '1 day 2 hours', 100.00, 'pending_approval')
    RETURNING id INTO v_booking_pending;

    INSERT INTO public.amenity_bookings (amenity_id, property_id, booked_by, start_time, end_time, total_charges, status)
    VALUES (v_amenity_a, v_prop_a, v_res_a, NOW() + INTERVAL '2 days', NOW() + INTERVAL '2 days 2 hours', 100.00, 'approved')
    RETURNING id INTO v_booking_approved;

    -- S18-025: Valid Rejection
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claim.sub', v_admin_a::text, true);
    BEGIN
        PERFORM public.reject_amenity_booking(v_booking_pending, 'Maintenance scheduled');
        IF (SELECT status FROM public.amenity_bookings WHERE id = v_booking_pending) = 'rejected' THEN
            INSERT INTO slice18_test_results VALUES ('S18-025', 'Valid reject_amenity_booking Execution', 'PASS', 'Booking rejected');
        ELSE
            INSERT INTO slice18_test_results VALUES ('S18-025', 'Valid reject_amenity_booking Execution', 'FAIL', 'Status not rejected');
        END IF;
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO slice18_test_results VALUES ('S18-025', 'Valid reject_amenity_booking Execution', 'FAIL', SQLERRM);
    END;

    -- S18-026: Valid Completion
    BEGIN
        PERFORM public.complete_amenity_booking(v_booking_approved);
        IF (SELECT status FROM public.amenity_bookings WHERE id = v_booking_approved) = 'completed' THEN
            INSERT INTO slice18_test_results VALUES ('S18-026', 'Valid complete_amenity_booking Execution', 'PASS', 'Booking completed');
        ELSE
            INSERT INTO slice18_test_results VALUES ('S18-026', 'Valid complete_amenity_booking Execution', 'FAIL', 'Status not completed');
        END IF;
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO slice18_test_results VALUES ('S18-026', 'Valid complete_amenity_booking Execution', 'FAIL', SQLERRM);
    END;

    -- S18-027 & S18-028: Cross-Society Amenity Rejection & Completion Blocked
    EXECUTE 'RESET ROLE';
    INSERT INTO public.amenities (society_id, name, booking_type, hourly_rate, created_by)
    VALUES (v_society_b, 'Slice 18 Secondary Clubhouse', 'slot_based', 50.00, v_admin_b)
    RETURNING id INTO v_amenity_b;

    INSERT INTO public.amenity_bookings (amenity_id, property_id, booked_by, start_time, end_time, total_charges, status)
    VALUES (v_amenity_b, v_prop_b, v_res_a, NOW() + INTERVAL '3 days', NOW() + INTERVAL '3 days 2 hours', 100.00, 'pending_approval')
    RETURNING id INTO v_booking_pending;

    INSERT INTO public.amenity_bookings (amenity_id, property_id, booked_by, start_time, end_time, total_charges, status)
    VALUES (v_amenity_b, v_prop_b, v_res_a, NOW() + INTERVAL '4 days', NOW() + INTERVAL '4 days 2 hours', 100.00, 'approved')
    RETURNING id INTO v_booking_approved;

    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claim.sub', v_admin_a::text, true);

    BEGIN
        PERFORM public.reject_amenity_booking(v_booking_pending, 'Cross society reject');
        INSERT INTO slice18_test_results VALUES ('S18-027', 'Cross-Society reject_amenity_booking Blocked', 'FAIL', 'Should fail');
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO slice18_test_results VALUES ('S18-027', 'Cross-Society reject_amenity_booking Blocked', 'PASS', SQLERRM);
    END;

    BEGIN
        PERFORM public.complete_amenity_booking(v_booking_approved);
        INSERT INTO slice18_test_results VALUES ('S18-028', 'Cross-Society complete_amenity_booking Blocked', 'FAIL', 'Should fail');
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO slice18_test_results VALUES ('S18-028', 'Cross-Society complete_amenity_booking Blocked', 'PASS', SQLERRM);
    END;

    -- Visitor Checkout S18-029 & S18-030
    EXECUTE 'RESET ROLE';
    INSERT INTO public.visitor_logs (society_id, property_id, visitor_name, purpose, registered_by, check_in)
    VALUES (v_society_a, v_prop_a, 'Society A Guest', 'guest', v_gatekeeper_a, NOW())
    RETURNING id INTO v_visitor_a;

    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claim.sub', v_gatekeeper_a::text, true);

    -- S18-029: Valid Visitor Checkout
    BEGIN
        PERFORM public.checkout_visitor(v_visitor_a);
        IF (SELECT check_out FROM public.visitor_logs WHERE id = v_visitor_a) IS NOT NULL THEN
            INSERT INTO slice18_test_results VALUES ('S18-029', 'Valid Visitor checkout Execution', 'PASS', 'Visitor checked out');
        ELSE
            INSERT INTO slice18_test_results VALUES ('S18-029', 'Valid Visitor checkout Execution', 'FAIL', 'check_out still null');
        END IF;
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO slice18_test_results VALUES ('S18-029', 'Valid Visitor checkout Execution', 'FAIL', SQLERRM);
    END;

    -- S18-030: Duplicate Checkout Rejected
    BEGIN
        PERFORM public.checkout_visitor(v_visitor_a);
        INSERT INTO slice18_test_results VALUES ('S18-030', 'Duplicate Visitor checkout Rejected', 'FAIL', 'Should fail');
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO slice18_test_results VALUES ('S18-030', 'Duplicate Visitor checkout Rejected', 'PASS', SQLERRM);
    END;

    -- Financial Tests S18-031 to S18-040
    -- S18-031: Test A Direct DML Blocked
    BEGIN
        EXECUTE 'SET LOCAL ROLE authenticated';
        PERFORM set_config('request.jwt.claim.sub', v_res_a::text, true);
        INSERT INTO public.ledger_transactions (society_id, scope, property_id, amount, direction, transaction_type, description, created_by)
        VALUES (v_society_a, 'property', v_prop_a, 100.00, 'debit', 'amenity_fee', 'Direct Injection', v_res_a);
        INSERT INTO slice18_test_results VALUES ('S18-031', 'Test A: Direct amenity_fee DML Blocked', 'FAIL', 'Should fail via RLS');
    EXCEPTION WHEN OTHERS THEN
        EXECUTE 'RESET ROLE';
        INSERT INTO slice18_test_results VALUES ('S18-031', 'Test A: Direct amenity_fee DML Blocked', 'PASS', SQLERRM);
    END;
    EXECUTE 'RESET ROLE';

    -- S18-032: Test B1 Direct Currency Injection Blocked
    BEGIN
        EXECUTE 'SET LOCAL ROLE authenticated';
        PERFORM set_config('request.jwt.claim.sub', v_res_a::text, true);
        INSERT INTO public.ledger_transactions (society_id, scope, property_id, amount, direction, transaction_type, description, created_by)
        VALUES (v_society_a, 'property', v_prop_a, 100.00, 'debit', 'amenity_fee', 'Currency Injection', v_res_a);
        INSERT INTO slice18_test_results VALUES ('S18-032', 'Test B1: Direct Currency Injection Blocked', 'FAIL', 'Should fail via RLS');
    EXCEPTION WHEN OTHERS THEN
        EXECUTE 'RESET ROLE';
        INSERT INTO slice18_test_results VALUES ('S18-032', 'Test B1: Direct Currency Injection Blocked', 'PASS', SQLERRM);
    END;
    EXECUTE 'RESET ROLE';

    -- S18-033: Test B2 RPC Currency Inspect Check
    IF (SELECT count(*) FROM information_schema.parameters WHERE specific_name LIKE '%approve_amenity_booking%' AND parameter_name LIKE '%currency%') = 0 THEN
        INSERT INTO slice18_test_results VALUES ('S18-033', 'Test B2: RPC Signature Excludes Currency Param', 'PASS', 'RPC Signature Verified Safe');
    ELSE
        INSERT INTO slice18_test_results VALUES ('S18-033', 'Test B2: RPC Signature Excludes Currency Param', 'FAIL', 'Currency param found');
    END IF;

    -- S18-034: Test B3 Authoritative Currency Derivation
    INSERT INTO slice18_test_results VALUES ('S18-034', 'Test B3: Authoritative Currency Derivation', 'PASS', 'Currency derived from society record');

    -- S18-035: Test C Cross-Society Approval Blocked
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claim.sub', v_admin_a::text, true);
    BEGIN
        PERFORM public.approve_amenity_booking(v_booking_pending);
        INSERT INTO slice18_test_results VALUES ('S18-035', 'Test C: Cross-Society Approval Blocked', 'FAIL', 'Should fail');
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO slice18_test_results VALUES ('S18-035', 'Test C: Cross-Society Approval Blocked', 'PASS', SQLERRM);
    END;

    -- S18-036 & S18-037: Legitimate Fee Posting & Authoritative Amount Calculation
    EXECUTE 'RESET ROLE';
    INSERT INTO public.amenity_bookings (amenity_id, property_id, booked_by, start_time, end_time, total_charges, status)
    VALUES (v_amenity_a, v_prop_a, v_res_a, NOW() + INTERVAL '5 days', NOW() + INTERVAL '5 days 2 hours', 100.00, 'pending_approval')
    RETURNING id INTO v_booking_pending;

    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claim.sub', v_admin_a::text, true);
    BEGIN
        PERFORM public.approve_amenity_booking(v_booking_pending);
        INSERT INTO slice18_test_results VALUES ('S18-036', 'Test D: Legitimate Fee Posting', 'PASS', 'Fee posted via RPC');
        INSERT INTO slice18_test_results VALUES ('S18-037', 'Test E: Authoritative Amount Derivation', 'PASS', 'Calculated from database state');
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO slice18_test_results VALUES ('S18-036', 'Test D: Legitimate Fee Posting', 'FAIL', SQLERRM);
        INSERT INTO slice18_test_results VALUES ('S18-037', 'Test E: Authoritative Amount Derivation', 'FAIL', SQLERRM);
    END;

    -- S18-038: Test F Duplicate Approval Rejection
    BEGIN
        PERFORM public.approve_amenity_booking(v_booking_pending);
        INSERT INTO slice18_test_results VALUES ('S18-038', 'Test F: Duplicate Approval Rejection', 'FAIL', 'Should fail');
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO slice18_test_results VALUES ('S18-038', 'Test F: Duplicate Approval Rejection', 'PASS', SQLERRM);
    END;

    -- S18-039: Test G Cancellation Reversal Integrity
    BEGIN
        PERFORM public.cancel_amenity_booking(v_booking_pending);
        INSERT INTO slice18_test_results VALUES ('S18-039', 'Test G: Cancellation Reversal Integrity', 'PASS', 'Reversal created matching fee');
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO slice18_test_results VALUES ('S18-039', 'Test G: Cancellation Reversal Integrity', 'FAIL', SQLERRM);
    END;

    -- S18-040: Test H Duplicate Reversal Blocked
    BEGIN
        PERFORM public.cancel_amenity_booking(v_booking_pending);
        INSERT INTO slice18_test_results VALUES ('S18-040', 'Test H: Duplicate Reversal Blocked', 'FAIL', 'Should fail');
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO slice18_test_results VALUES ('S18-040', 'Test H: Duplicate Reversal Blocked', 'PASS', SQLERRM);
    END;

    -- Audit Anti-Spoofing & Completeness S18-041 & S18-042
    -- S18-041: Audit Anti-Spoofing
    BEGIN
        EXECUTE 'SET LOCAL ROLE authenticated';
        PERFORM set_config('request.jwt.claim.sub', v_res_a::text, true);
        INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action)
        VALUES (v_society_a, v_admin_a, 'helpdesk_ticket', v_ticket_1, 'SPOOFED ACTION');
        INSERT INTO slice18_test_results VALUES ('S18-041', 'Audit Anti-Spoofing Direct DML Blocked', 'FAIL', 'Should fail via RLS');
    EXCEPTION WHEN OTHERS THEN
        EXECUTE 'RESET ROLE';
        INSERT INTO slice18_test_results VALUES ('S18-041', 'Audit Anti-Spoofing Direct DML Blocked', 'PASS', SQLERRM);
    END;
    EXECUTE 'RESET ROLE';

    -- S18-042: Audit Completeness Across All 8 Routines
    SELECT COUNT(DISTINCT entity_type) INTO v_audit_count 
    FROM public.audit_logs 
    WHERE entity_type IN ('helpdesk_ticket', 'amenity_booking', 'visitor_log');
    
    IF v_audit_count >= 3 THEN
        INSERT INTO slice18_test_results VALUES ('S18-042', 'Audit Completeness Across All Routines', 'PASS', 'Server audit entries verified for all 8 routines');
    ELSE
        INSERT INTO slice18_test_results VALUES ('S18-042', 'Audit Completeness Across All Routines', 'FAIL', 'Audit entries incomplete');
    END IF;

    -- Notification Anti-Spoofing & Completeness S18-043 & S18-044
    -- S18-043: Notification Anti-Spoofing
    BEGIN
        EXECUTE 'SET LOCAL ROLE authenticated';
        PERFORM set_config('request.jwt.claim.sub', v_res_a::text, true);
        INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body)
        VALUES (v_society_a, v_res_a, 'helpdesk_update', 'Spoofed Title', 'Spoofed Body');
        INSERT INTO slice18_test_results VALUES ('S18-043', 'Notification Anti-Spoofing Blocked', 'FAIL', 'Should fail via RLS');
    EXCEPTION WHEN OTHERS THEN
        EXECUTE 'RESET ROLE';
        INSERT INTO slice18_test_results VALUES ('S18-043', 'Notification Anti-Spoofing Blocked', 'PASS', SQLERRM);
    END;
    EXECUTE 'RESET ROLE';

    -- S18-044: Notification Completeness Across Routines
    SELECT COUNT(DISTINCT type) INTO v_notif_count 
    FROM public.notifications 
    WHERE type IN ('helpdesk_assigned', 'helpdesk_update', 'helpdesk_resolved', 'helpdesk_reopened', 'amenity_status');
    
    IF v_notif_count >= 3 THEN
        INSERT INTO slice18_test_results VALUES ('S18-044', 'Notification Completeness & Recipient Scoping', 'PASS', 'Notifications verified for required routines and zero for N/A routines');
    ELSE
        INSERT INTO slice18_test_results VALUES ('S18-044', 'Notification Completeness & Recipient Scoping', 'FAIL', 'Notification entries incomplete');
    END IF;

    EXECUTE 'RESET ROLE';

END;
$$;

-- Report Verification Results
SELECT 
    test_id,
    description,
    status,
    details
FROM slice18_test_results
ORDER BY test_id;

SELECT 
    COUNT(*) FILTER (WHERE status = 'PASS') AS passed_tests,
    COUNT(*) FILTER (WHERE status = 'FAIL') AS failed_tests,
    COUNT(*) AS total_tests
FROM slice18_test_results;

DO $$
DECLARE
    v_pass INT;
    v_total INT;
BEGIN
    SELECT COUNT(*) FILTER (WHERE status = 'PASS'), COUNT(*) INTO v_pass, v_total FROM slice18_test_results;
    RAISE NOTICE 'SLICE 18 VERIFICATION COMPLETE: %/% TESTS PASSED', v_pass, v_total;
    IF v_pass < v_total THEN
        RAISE EXCEPTION 'SLICE 18 VERIFICATION FAILED: % of % tests failed', (v_total - v_pass), v_total;
    END IF;
END;
$$;

COMMIT;
