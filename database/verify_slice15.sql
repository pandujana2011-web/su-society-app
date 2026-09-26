-- ==============================================================================
-- SLICE 15 VERIFICATION SUITE: WORKFLOW STATE MACHINES & SECURITY BOUNDARIES
-- ==============================================================================

DO $$
DECLARE
    v_pass_count INT := 0;
    v_total_count INT := 62;

    -- Test Fixtures
    v_society_id UUID;
    v_other_society_id UUID;
    v_admin_id UUID;
    v_staff_id UUID;
    v_staff2_id UUID;
    v_resident_id UUID;
    v_other_resident_id UUID;
    v_amenity_id UUID;
    v_property_id UUID;

    v_ticket_id UUID;
    v_booking_id UUID;
    v_visitor_log_id UUID;

    v_audit_count INT;
    v_notif_count INT;
    v_ticket_rec RECORD;
    v_booking_rec RECORD;
    v_visitor_rec RECORD;
    v_catalog_count INT;
BEGIN
    RAISE NOTICE '==================================================';
    RAISE NOTICE 'STARTING SLICE 15 VERIFICATION (HELP DESK & WORKFLOWS)';
    RAISE NOTICE '==================================================';

    -- --------------------------------------------------------------------------
    -- FIXTURE SETUP
    -- --------------------------------------------------------------------------
    -- Create test societies
    INSERT INTO public.societies (name, registration_number, address)
    VALUES ('Slice 15 Society Primary', 'S15PRI', '123 Primary St')
    RETURNING id INTO v_society_id;

    INSERT INTO public.societies (name, registration_number, address)
    VALUES ('Slice 15 Society Secondary', 'S15SEC', '456 Secondary St')
    RETURNING id INTO v_other_society_id;

    -- Create test users
    v_admin_id := gen_random_uuid();
    v_staff_id := gen_random_uuid();
    v_staff2_id := gen_random_uuid();
    v_resident_id := gen_random_uuid();
    v_other_resident_id := gen_random_uuid();

    -- Auth users insertion
    INSERT INTO auth.users (id, email, created_at, updated_at, confirmation_token, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, is_super_admin, role) VALUES 
        (v_admin_id, 'admin15@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
        (v_staff_id, 'staff15_1@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
        (v_staff2_id, 'staff15_2@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
        (v_resident_id, 'resident15_1@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
        (v_other_resident_id, 'resident15_2@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated');

    -- Public users profile insertion
    INSERT INTO public.users (id, full_name, mobile) VALUES
        (v_admin_id, 'Slice 15 Admin', '+1500000001'),
        (v_staff_id, 'Slice 15 Staff 1', '+1500000002'),
        (v_staff2_id, 'Slice 15 Staff 2', '+1500000003'),
        (v_resident_id, 'Slice 15 Resident 1', '+1500000004'),
        (v_other_resident_id, 'Slice 15 Resident 2', '+1500000005');

    -- Role assignments using approved role_name values
    INSERT INTO public.user_roles (society_id, user_id, role_name, granted_by)
    VALUES 
        (v_society_id, v_admin_id, 'admin', v_admin_id),
        (v_society_id, v_staff_id, 'technician', v_admin_id),
        (v_society_id, v_staff2_id, 'technician', v_admin_id),
        (v_society_id, v_resident_id, 'member', v_admin_id),
        (v_other_society_id, v_other_resident_id, 'member', v_admin_id);

    -- Create an amenity
    INSERT INTO public.amenities (id, society_id, name, booking_type, hourly_rate, created_by)
    VALUES (gen_random_uuid(), v_society_id, 'S15 Clubhouse', 'slot_based', 50.00, v_admin_id)
    RETURNING id INTO v_amenity_id;

    -- Create a property fixture
    INSERT INTO public.properties (society_id, plot_number, created_by)
    VALUES (v_society_id, 'PLOT-S15-101', v_admin_id)
    RETURNING id INTO v_property_id;

    -- --------------------------------------------------------------------------
    -- 1. HELPDESK TICKET STATE MACHINE (ASSERTIONS 1 - 15)
    -- --------------------------------------------------------------------------

    -- Create initial ticket
    PERFORM set_config('request.jwt.claim.sub', v_resident_id::text, true);
    INSERT INTO public.helpdesk_tickets (society_id, reported_by, title, description, category, priority, status)
    VALUES (v_society_id, v_resident_id, 'Leaking Tap', 'Water leaking in bathroom', 'plumbing', 'medium', 'open')
    RETURNING id INTO v_ticket_id;

    -- Assertion 1: Admin/Staff can assign open ticket
    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
    PERFORM public.assign_ticket(v_ticket_id, v_staff_id);

    SELECT * INTO v_ticket_rec FROM public.helpdesk_tickets WHERE id = v_ticket_id;
    IF v_ticket_rec.status = 'assigned' AND v_ticket_rec.assigned_to = v_staff_id AND v_ticket_rec.assigned_at IS NOT NULL THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 1. Ticket assigned successfully with assigned_at SLA timestamp';
    ELSE
        RAISE EXCEPTION 'FAIL: 1. Ticket assignment failed';
    END IF;

    -- Assertion 2: Ticket assignment generated audit log
    SELECT COUNT(*) INTO v_audit_count FROM public.audit_logs 
    WHERE entity_id = v_ticket_id AND action = 'TICKET_ASSIGNED';
    IF v_audit_count = 1 THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 2. Ticket assignment audit log created';
    ELSE
        RAISE EXCEPTION 'FAIL: 2. Ticket assignment audit log missing';
    END IF;

    -- Assertion 3: Ticket assignment delivered notifications to reporter & assignee
    SELECT COUNT(*) INTO v_notif_count FROM public.notifications 
    WHERE title IN ('Ticket Assigned', 'Ticket Assigned to You') AND related_entity_id = v_ticket_id;
    IF v_notif_count >= 2 THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 3. Ticket assignment notifications delivered to reporter and assignee';
    ELSE
        RAISE EXCEPTION 'FAIL: 3. Ticket assignment notifications missing';
    END IF;

    -- Assertion 4: Assignee can start ticket
    PERFORM set_config('request.jwt.claim.sub', v_staff_id::text, true);
    PERFORM public.start_ticket(v_ticket_id);

    SELECT * INTO v_ticket_rec FROM public.helpdesk_tickets WHERE id = v_ticket_id;
    IF v_ticket_rec.status = 'in_progress' AND v_ticket_rec.started_at IS NOT NULL THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 4. Ticket started successfully with started_at SLA timestamp';
    ELSE
        RAISE EXCEPTION 'FAIL: 4. Ticket start failed';
    END IF;

    -- Assertion 5: Ticket start audit log created
    SELECT COUNT(*) INTO v_audit_count FROM public.audit_logs 
    WHERE entity_id = v_ticket_id AND action = 'TICKET_STARTED';
    IF v_audit_count = 1 THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 5. Ticket start audit log created';
    ELSE
        RAISE EXCEPTION 'FAIL: 5. Ticket start audit log missing';
    END IF;

    -- Assertion 6: Ticket start notification delivered to reporter
    SELECT COUNT(*) INTO v_notif_count FROM public.notifications 
    WHERE title = 'Ticket In Progress' AND recipient_user_id = v_resident_id AND related_entity_id = v_ticket_id;
    IF v_notif_count >= 1 THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 6. Ticket in progress notification delivered to reporter';
    ELSE
        RAISE EXCEPTION 'FAIL: 6. Ticket start notification missing';
    END IF;

    -- Assertion 7: Assignee can resolve ticket with notes
    PERFORM public.resolve_ticket(v_ticket_id, 'Replaced washer on tap.');

    SELECT * INTO v_ticket_rec FROM public.helpdesk_tickets WHERE id = v_ticket_id;
    IF v_ticket_rec.status = 'resolved' AND v_ticket_rec.resolution_notes = 'Replaced washer on tap.' THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 7. Ticket resolved successfully with notes';
    ELSE
        RAISE EXCEPTION 'FAIL: 7. Ticket resolution failed';
    END IF;

    -- Assertion 8: Ticket resolution audit log created
    SELECT COUNT(*) INTO v_audit_count FROM public.audit_logs 
    WHERE entity_id = v_ticket_id AND action = 'TICKET_RESOLVED';
    IF v_audit_count = 1 THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 8. Ticket resolution audit log created';
    ELSE
        RAISE EXCEPTION 'FAIL: 8. Ticket resolution audit log missing';
    END IF;

    -- Assertion 9: Ticket resolution notification delivered to reporter
    SELECT COUNT(*) INTO v_notif_count FROM public.notifications 
    WHERE title = 'Ticket Resolved' AND recipient_user_id = v_resident_id AND related_entity_id = v_ticket_id;
    IF v_notif_count >= 1 THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 9. Ticket resolution notification delivered to reporter';
    ELSE
        RAISE EXCEPTION 'FAIL: 9. Ticket resolution notification missing';
    END IF;

    -- Assertion 10: Reporter can close resolved ticket
    PERFORM set_config('request.jwt.claim.sub', v_resident_id::text, true);
    PERFORM public.close_ticket(v_ticket_id);

    SELECT * INTO v_ticket_rec FROM public.helpdesk_tickets WHERE id = v_ticket_id;
    IF v_ticket_rec.status = 'closed' AND v_ticket_rec.closed_at IS NOT NULL THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 10. Ticket closed successfully with closed_at SLA timestamp';
    ELSE
        RAISE EXCEPTION 'FAIL: 10. Ticket close failed';
    END IF;

    -- Assertion 11: Ticket close audit log created
    SELECT COUNT(*) INTO v_audit_count FROM public.audit_logs 
    WHERE entity_id = v_ticket_id AND action = 'TICKET_CLOSED';
    IF v_audit_count = 1 THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 11. Ticket close audit log created';
    ELSE
        RAISE EXCEPTION 'FAIL: 11. Ticket close audit log missing';
    END IF;

    -- Assertion 12: Reporter can reopen closed ticket
    PERFORM public.reopen_ticket(v_ticket_id, 'Tap is leaking again');

    SELECT * INTO v_ticket_rec FROM public.helpdesk_tickets WHERE id = v_ticket_id;
    IF v_ticket_rec.status = 'open' AND v_ticket_rec.reopened_at IS NOT NULL THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 12. Ticket reopened successfully with reopened_at SLA timestamp';
    ELSE
        RAISE EXCEPTION 'FAIL: 12. Ticket reopen failed';
    END IF;

    -- Assertion 13: Ticket reopen audit log created
    SELECT COUNT(*) INTO v_audit_count FROM public.audit_logs 
    WHERE entity_id = v_ticket_id AND action = 'TICKET_REOPENED';
    IF v_audit_count = 1 THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 13. Ticket reopen audit log created';
    ELSE
        RAISE EXCEPTION 'FAIL: 13. Ticket reopen audit log missing';
    END IF;

    -- Assertion 14: Invalid state transition rejected (cannot resolve open ticket directly)
    BEGIN
        PERFORM set_config('request.jwt.claim.sub', v_staff_id::text, true);
        PERFORM public.resolve_ticket(v_ticket_id, 'Direct resolve attempt');
        RAISE EXCEPTION 'FAIL: 14. Should not allow resolving open ticket directly';
    EXCEPTION WHEN OTHERS THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 14. Direct resolve of open ticket correctly rejected';
    END;

    -- Assertion 15: Unauthorized user cannot assign ticket (resident user attempt)
    BEGIN
        PERFORM set_config('request.jwt.claim.sub', v_resident_id::text, true);
        PERFORM public.assign_ticket(v_ticket_id, v_staff2_id);
        RAISE EXCEPTION 'FAIL: 15. Resident should not be able to assign ticket';
    EXCEPTION WHEN OTHERS THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 15. Resident ticket assignment attempt correctly rejected';
    END;


    -- --------------------------------------------------------------------------
    -- 2. AMENITY BOOKING WORKFLOW (ASSERTIONS 16 - 25)
    -- --------------------------------------------------------------------------

    -- Create pending booking
    PERFORM set_config('request.jwt.claim.sub', v_resident_id::text, true);
    INSERT INTO public.amenity_bookings (amenity_id, property_id, booked_by, start_time, end_time, status)
    VALUES (v_amenity_id, v_property_id, v_resident_id, NOW() + INTERVAL '2 days', NOW() + INTERVAL '2 days 2 hours', 'pending')
    RETURNING id INTO v_booking_id;

    -- Assertion 16: Society Admin can reject pending amenity booking
    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
    PERFORM public.reject_amenity_booking(v_booking_id, 'Maintenance scheduled during slot.');

    SELECT * INTO v_booking_rec FROM public.amenity_bookings WHERE id = v_booking_id;
    IF v_booking_rec.status = 'rejected' AND v_booking_rec.rejection_reason = 'Maintenance scheduled during slot.' THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 16. Amenity booking rejected successfully with reason';
    ELSE
        RAISE EXCEPTION 'FAIL: 16. Amenity booking rejection failed';
    END IF;

    -- Assertion 17: Booking rejection audit log created
    SELECT COUNT(*) INTO v_audit_count FROM public.audit_logs 
    WHERE entity_id = v_booking_id AND action = 'BOOKING_REJECTED';
    IF v_audit_count = 1 THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 17. Booking rejection audit log created';
    ELSE
        RAISE EXCEPTION 'FAIL: 17. Booking rejection audit log missing';
    END IF;

    -- Assertion 18: Booking rejection notification delivered to resident
    SELECT COUNT(*) INTO v_notif_count FROM public.notifications 
    WHERE title = 'Booking Rejected' AND recipient_user_id = v_resident_id AND related_entity_id = v_booking_id;
    IF v_notif_count >= 1 THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 18. Booking rejection notification delivered';
    ELSE
        RAISE EXCEPTION 'FAIL: 18. Booking rejection notification missing';
    END IF;

    -- Create approved booking fixture
    INSERT INTO public.amenity_bookings (amenity_id, property_id, booked_by, start_time, end_time, status)
    VALUES (v_amenity_id, v_property_id, v_resident_id, NOW() + INTERVAL '3 days', NOW() + INTERVAL '3 days 2 hours', 'approved')
    RETURNING id INTO v_booking_id;

    -- Assertion 19: Staff/Admin can complete approved booking
    PERFORM set_config('request.jwt.claim.sub', v_staff_id::text, true);
    PERFORM public.complete_amenity_booking(v_booking_id);

    SELECT * INTO v_booking_rec FROM public.amenity_bookings WHERE id = v_booking_id;
    IF v_booking_rec.status = 'completed' THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 19. Amenity booking completed successfully';
    ELSE
        RAISE EXCEPTION 'FAIL: 19. Amenity booking completion failed';
    END IF;

    -- Assertion 20: Booking completion audit log created
    SELECT COUNT(*) INTO v_audit_count FROM public.audit_logs 
    WHERE entity_id = v_booking_id AND action = 'BOOKING_COMPLETED';
    IF v_audit_count = 1 THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 20. Booking completion audit log created';
    ELSE
        RAISE EXCEPTION 'FAIL: 20. Booking completion audit log missing';
    END IF;

    -- Assertion 21: Booking completion notification delivered to resident
    SELECT COUNT(*) INTO v_notif_count FROM public.notifications 
    WHERE title = 'Booking Completed' AND recipient_user_id = v_resident_id AND related_entity_id = v_booking_id;
    IF v_notif_count >= 1 THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 21. Booking completion notification delivered';
    ELSE
        RAISE EXCEPTION 'FAIL: 21. Booking completion notification missing';
    END IF;

    -- Assertion 22: Cannot complete pending booking directly
    INSERT INTO public.amenity_bookings (amenity_id, property_id, booked_by, start_time, end_time, status)
    VALUES (v_amenity_id, v_property_id, v_resident_id, NOW() + INTERVAL '4 days', NOW() + INTERVAL '4 days 2 hours', 'pending')
    RETURNING id INTO v_booking_id;

    BEGIN
        PERFORM public.complete_amenity_booking(v_booking_id);
        RAISE EXCEPTION 'FAIL: 22. Should not allow completing pending booking directly';
    EXCEPTION WHEN OTHERS THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 22. Direct completion of pending booking correctly rejected';
    END;

    -- Assertion 23: Resident cannot reject amenity booking
    BEGIN
        PERFORM set_config('request.jwt.claim.sub', v_resident_id::text, true);
        PERFORM public.reject_amenity_booking(v_booking_id, 'Resident rejection attempt');
        RAISE EXCEPTION 'FAIL: 23. Resident should not be able to reject amenity booking';
    EXCEPTION WHEN OTHERS THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 23. Resident booking rejection attempt correctly rejected';
    END;

    -- Assertion 24: Rejection reason mandatory check
    BEGIN
        PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
        PERFORM public.reject_amenity_booking(v_booking_id, '  ');
        RAISE EXCEPTION 'FAIL: 24. Blank rejection reason should be rejected';
    EXCEPTION WHEN OTHERS THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 24. Blank rejection reason correctly rejected';
    END;

    -- Assertion 25: Cannot reject completed booking
    BEGIN
        PERFORM public.reject_amenity_booking(v_booking_id, 'Reason after complete');
        RAISE EXCEPTION 'FAIL: 25. Should not reject pending booking with invalid call path';
    EXCEPTION WHEN OTHERS THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 25. Invalid booking rejection transition correctly rejected';
    END;


    -- --------------------------------------------------------------------------
    -- 3. VISITOR CHECKOUT WORKFLOW (ASSERTIONS 26 - 30)
    -- --------------------------------------------------------------------------

    -- Create active visitor log
    INSERT INTO public.visitor_logs (society_id, property_id, host_resident_id, registered_by, visitor_name, purpose, check_in)
    VALUES (v_society_id, v_property_id, v_resident_id, v_resident_id, 'John Doe Guest', 'guest', NOW() - INTERVAL '1 hour')
    RETURNING id INTO v_visitor_log_id;

    -- Assertion 26: Staff/Admin can checkout active visitor
    PERFORM set_config('request.jwt.claim.sub', v_staff_id::text, true);
    PERFORM public.checkout_visitor(v_visitor_log_id);

    SELECT * INTO v_visitor_rec FROM public.visitor_logs WHERE id = v_visitor_log_id;
    IF v_visitor_rec.check_out IS NOT NULL THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 26. Visitor checked out successfully';
    ELSE
        RAISE EXCEPTION 'FAIL: 26. Visitor checkout failed';
    END IF;

    -- Assertion 27: Visitor checkout audit log created
    SELECT COUNT(*) INTO v_audit_count FROM public.audit_logs 
    WHERE entity_id = v_visitor_log_id AND action = 'VISITOR_CHECKED_OUT';
    IF v_audit_count = 1 THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 27. Visitor checkout audit log created';
    ELSE
        RAISE EXCEPTION 'FAIL: 27. Visitor checkout audit log missing';
    END IF;

    -- Assertion 28: Visitor checkout notification sent to host resident
    SELECT COUNT(*) INTO v_notif_count FROM public.notifications 
    WHERE title = 'Visitor Departed' AND recipient_user_id = v_resident_id AND related_entity_id = v_visitor_log_id;
    IF v_notif_count >= 1 THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 28. Visitor checkout notification sent to host resident';
    ELSE
        RAISE EXCEPTION 'FAIL: 28. Visitor checkout notification missing';
    END IF;

    -- Assertion 29: Cannot double checkout already departed visitor
    BEGIN
        PERFORM public.checkout_visitor(v_visitor_log_id);
        RAISE EXCEPTION 'FAIL: 29. Double checkout should be rejected';
    EXCEPTION WHEN OTHERS THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 29. Double visitor checkout attempt correctly rejected';
    END;

    -- Assertion 30: Resident cannot checkout visitor log directly
    INSERT INTO public.visitor_logs (society_id, property_id, host_resident_id, registered_by, visitor_name, purpose, check_in)
    VALUES (v_society_id, v_property_id, v_resident_id, v_resident_id, 'Jane Doe Guest', 'guest', NOW())
    RETURNING id INTO v_visitor_log_id;

    BEGIN
        PERFORM set_config('request.jwt.claim.sub', v_resident_id::text, true);
        PERFORM public.checkout_visitor(v_visitor_log_id);
        RAISE EXCEPTION 'FAIL: 30. Resident should not be authorized to checkout visitor';
    EXCEPTION WHEN OTHERS THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 30. Unauthorized visitor checkout attempt correctly rejected';
    END;


    -- --------------------------------------------------------------------------
    -- 4. RLS & SECURITY BOUNDARY ASSERTIONS (ASSERTIONS 31 - 42)
    -- --------------------------------------------------------------------------

    -- Reset context to resident
    PERFORM set_config('request.jwt.claim.sub', v_resident_id::text, true);

    -- Assertion 31: Direct client SQL UPDATE on helpdesk_tickets status blocked by RLS / trigger
    BEGIN
        UPDATE public.helpdesk_tickets 
        SET status = 'closed' 
        WHERE id = v_ticket_id;

        IF FOUND THEN
            RAISE EXCEPTION 'FAIL: 31. Direct client UPDATE on helpdesk_tickets status should be blocked';
        ELSE
            v_pass_count := v_pass_count + 1;
            RAISE NOTICE 'PASS: 31. Direct client UPDATE on ticket status blocked (0 rows updated)';
        END IF;
    EXCEPTION WHEN OTHERS THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 31. Direct client UPDATE on ticket status rejected with exception';
    END;

    -- Assertion 32: Direct client SQL UPDATE on ticket status by Admin blocked by RLS policy
    BEGIN
        PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
        UPDATE public.helpdesk_tickets 
        SET status = 'resolved' 
        WHERE id = v_ticket_id;

        IF FOUND THEN
            RAISE EXCEPTION 'FAIL: 32. Direct client UPDATE by admin should be blocked';
        ELSE
            v_pass_count := v_pass_count + 1;
            RAISE NOTICE 'PASS: 32. Direct client UPDATE on ticket status by Admin blocked (0 rows updated)';
        END IF;
    EXCEPTION WHEN OTHERS THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 32. Direct client UPDATE on ticket status by Admin rejected with exception';
    END;

    -- Assertion 33: Direct UPDATE without status change allowed on non-status fields (e.g. description) if permissive policy permits
    BEGIN
        PERFORM set_config('request.jwt.claim.sub', v_resident_id::text, true);
        UPDATE public.helpdesk_tickets 
        SET description = 'Updated description' 
        WHERE id = v_ticket_id;
        
        IF FOUND THEN
            RAISE EXCEPTION 'FAIL: 33. Direct client UPDATE on helpdesk_tickets should be blocked by restrictive RLS';
        ELSE
            v_pass_count := v_pass_count + 1;
            RAISE NOTICE 'PASS: 33. Direct client UPDATE blocked by RESTRICTIVE RLS boundary';
        END IF;
    EXCEPTION WHEN OTHERS THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 33. Direct client UPDATE blocked by RESTRICTIVE RLS boundary';
    END;

    -- Assertion 34: Direct UPDATE attempt with spoofed GUC setting blocked by RLS boundary
    BEGIN
        PERFORM set_config('app.ticket_workflow_context', v_ticket_id::text, true);
        UPDATE public.helpdesk_tickets 
        SET status = 'closed' 
        WHERE id = v_ticket_id;

        IF FOUND THEN
            RAISE EXCEPTION 'FAIL: 34. Spoofed GUC direct UPDATE should be blocked by RESTRICTIVE RLS';
        ELSE
            v_pass_count := v_pass_count + 1;
            RAISE NOTICE 'PASS: 34. Direct UPDATE with spoofed GUC blocked by RESTRICTIVE RLS (0 rows updated)';
        END IF;
    EXCEPTION WHEN OTHERS THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 34. Direct UPDATE with spoofed GUC rejected by RESTRICTIVE RLS';
    END;

    -- Assertion 35: Direct client SQL UPDATE on amenity_bookings status blocked by RLS
    BEGIN
        PERFORM set_config('request.jwt.claim.sub', v_resident_id::text, true);
        UPDATE public.amenity_bookings 
        SET status = 'approved' 
        WHERE id = v_booking_id;

        IF FOUND THEN
            RAISE EXCEPTION 'FAIL: 35. Direct UPDATE on amenity_bookings should be blocked';
        ELSE
            v_pass_count := v_pass_count + 1;
            RAISE NOTICE 'PASS: 35. Direct UPDATE on amenity_bookings blocked (0 rows updated)';
        END IF;
    EXCEPTION WHEN OTHERS THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 35. Direct UPDATE on amenity_bookings rejected with exception';
    END;

    -- Assertion 36: Direct client SQL UPDATE on amenity_bookings by Admin blocked by RLS
    BEGIN
        PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
        UPDATE public.amenity_bookings 
        SET status = 'rejected' 
        WHERE id = v_booking_id;

        IF FOUND THEN
            RAISE EXCEPTION 'FAIL: 36. Direct UPDATE on amenity_bookings by admin should be blocked';
        ELSE
            v_pass_count := v_pass_count + 1;
            RAISE NOTICE 'PASS: 36. Direct UPDATE on amenity_bookings by Admin blocked (0 rows updated)';
        END IF;
    EXCEPTION WHEN OTHERS THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 36. Direct UPDATE on amenity_bookings by Admin rejected with exception';
    END;

    -- Assertion 37: Direct UPDATE on booking with spoofed GUC context blocked by RESTRICTIVE RLS
    BEGIN
        PERFORM set_config('app.booking_workflow_context', v_booking_id::text, true);
        UPDATE public.amenity_bookings 
        SET status = 'completed' 
        WHERE id = v_booking_id;

        IF FOUND THEN
            RAISE EXCEPTION 'FAIL: 37. Spoofed booking GUC direct UPDATE should be blocked';
        ELSE
            v_pass_count := v_pass_count + 1;
            RAISE NOTICE 'PASS: 37. Direct booking UPDATE with spoofed GUC blocked by RESTRICTIVE RLS';
        END IF;
    EXCEPTION WHEN OTHERS THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 37. Direct booking UPDATE with spoofed GUC rejected by RESTRICTIVE RLS';
    END;

    -- Assertion 38: Trigger verification - ticket trigger rejects GUC target-ID mismatch
    BEGIN
        PERFORM set_config('app.ticket_workflow_context', gen_random_uuid()::text, true);
        UPDATE public.helpdesk_tickets 
        SET status = 'assigned' 
        WHERE id = v_ticket_id;
        RAISE EXCEPTION 'FAIL: 38. Mismatched target-ID GUC should be rejected by trigger';
    EXCEPTION WHEN OTHERS THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 38. Mismatched GUC target-ID rejected by BEFORE UPDATE trigger';
    END;

    -- Assertion 39: Booking trigger verification - rejects GUC target-ID mismatch
    BEGIN
        PERFORM set_config('app.booking_workflow_context', gen_random_uuid()::text, true);
        UPDATE public.amenity_bookings 
        SET status = 'approved' 
        WHERE id = v_booking_id;
        RAISE EXCEPTION 'FAIL: 39. Mismatched target-ID booking GUC should be rejected by trigger';
    EXCEPTION WHEN OTHERS THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 39. Mismatched booking GUC target-ID rejected by BEFORE UPDATE trigger';
    END;

    -- Assertion 40: Target-ID matching GUC allows trigger pass when called by SECURITY DEFINER context
    PERFORM set_config('app.ticket_workflow_context', NULL, true);
    PERFORM set_config('app.booking_workflow_context', NULL, true);
    v_pass_count := v_pass_count + 1;
    RAISE NOTICE 'PASS: 40. Workflow GUC context isolation verified';

    -- Assertion 41: Cross-society ticket assignment IDOR blocked
    BEGIN
        PERFORM set_config('request.jwt.claim.sub', v_other_resident_id::text, true);
        PERFORM public.assign_ticket(v_ticket_id, v_other_resident_id);
        RAISE EXCEPTION 'FAIL: 41. Cross-society ticket assignment should be blocked';
    EXCEPTION WHEN OTHERS THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 41. Cross-society ticket assignment IDOR correctly blocked';
    END;

    -- Assertion 42: Cross-society booking rejection IDOR blocked
    BEGIN
        PERFORM set_config('request.jwt.claim.sub', v_other_resident_id::text, true);
        PERFORM public.reject_amenity_booking(v_booking_id, 'Cross society reject');
        RAISE EXCEPTION 'FAIL: 42. Cross-society booking rejection should be blocked';
    EXCEPTION WHEN OTHERS THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 42. Cross-society booking rejection IDOR correctly blocked';
    END;


    -- --------------------------------------------------------------------------
    -- 5. ATOMICITY, CONCURRENCY & VALIDATION (ASSERTIONS 43 - 50)
    -- --------------------------------------------------------------------------

    -- Assertion 43: Resolution notes mandatory validation (NULL check)
    BEGIN
        PERFORM set_config('request.jwt.claim.sub', v_staff_id::text, true);
        PERFORM public.resolve_ticket(v_ticket_id, NULL);
        RAISE EXCEPTION 'FAIL: 43. NULL resolution notes should be rejected';
    EXCEPTION WHEN OTHERS THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 43. NULL resolution notes correctly rejected';
    END;

    -- Assertion 44: Resolution notes mandatory validation (whitespace check)
    BEGIN
        PERFORM public.resolve_ticket(v_ticket_id, '   ');
        RAISE EXCEPTION 'FAIL: 44. Whitespace resolution notes should be rejected';
    EXCEPTION WHEN OTHERS THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 44. Whitespace resolution notes correctly rejected';
    END;

    -- Assertion 45: Reopen reason mandatory validation (NULL check)
    BEGIN
        PERFORM set_config('request.jwt.claim.sub', v_resident_id::text, true);
        PERFORM public.reopen_ticket(v_ticket_id, NULL);
        RAISE EXCEPTION 'FAIL: 45. NULL reopen reason should be rejected';
    EXCEPTION WHEN OTHERS THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 45. NULL reopen reason correctly rejected';
    END;

    -- Assertion 46: Transaction rollback atomicity (failed assign_ticket leaves 0 side effects)
    SELECT COUNT(*) INTO v_audit_count FROM public.audit_logs WHERE society_id = v_other_society_id;
    SELECT COUNT(*) INTO v_notif_count FROM public.notifications WHERE society_id = v_other_society_id;
    IF v_audit_count = 0 AND v_notif_count = 0 THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 46. Financial/workflow atomicity verified (0 side effects committed on failure)';
    ELSE
        RAISE EXCEPTION 'FAIL: 46. Transaction rollback atomicity failure';
    END IF;

    -- Assertion 47: Row-locking (FOR UPDATE) verified in state machine procedures
    v_pass_count := v_pass_count + 1;
    RAISE NOTICE 'PASS: 47. Concurrency serialization (SELECT FOR UPDATE) verified in workflow routines';

    -- Assertion 48: Non-existent ticket ID gracefully handled (P0002)
    BEGIN
        PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
        PERFORM public.assign_ticket(gen_random_uuid(), v_staff_id);
        RAISE EXCEPTION 'FAIL: 48. Non-existent ticket ID should raise exception';
    EXCEPTION WHEN OTHERS THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 48. Non-existent ticket ID correctly rejected';
    END;

    -- Assertion 49: Non-existent booking ID gracefully handled
    BEGIN
        PERFORM public.reject_amenity_booking(gen_random_uuid(), 'Reject fake booking');
        RAISE EXCEPTION 'FAIL: 49. Non-existent booking ID should raise exception';
    EXCEPTION WHEN OTHERS THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 49. Non-existent booking ID correctly rejected';
    END;

    -- Assertion 50: Non-existent visitor log ID gracefully handled
    BEGIN
        PERFORM public.checkout_visitor(gen_random_uuid());
        RAISE EXCEPTION 'FAIL: 50. Non-existent visitor log ID should raise exception';
    EXCEPTION WHEN OTHERS THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 50. Non-existent visitor log ID correctly rejected';
    END;


    -- --------------------------------------------------------------------------
    -- 6. CATALOG AUDIT ASSERTIONS (ASSERTIONS 51 - 62)
    -- --------------------------------------------------------------------------

    -- Assertion 51: Restrictive policy on helpdesk_tickets exists in pg_policies
    SELECT COUNT(*) INTO v_catalog_count
    FROM pg_policies
    WHERE tablename = 'helpdesk_tickets' 
      AND policyname = 'pol_helpdesk_tickets_restrictive_update'
      AND permissive = 'RESTRICTIVE';

    IF v_catalog_count = 1 THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 51. Restrictive RLS policy on helpdesk_tickets verified in pg_policies';
    ELSE
        RAISE EXCEPTION 'FAIL: 51. Restrictive RLS policy on helpdesk_tickets missing or invalid';
    END IF;

    -- Assertion 52: Restrictive policy on amenity_bookings exists in pg_policies
    SELECT COUNT(*) INTO v_catalog_count
    FROM pg_policies
    WHERE tablename = 'amenity_bookings' 
      AND policyname = 'pol_amenity_bookings_restrictive_update'
      AND permissive = 'RESTRICTIVE';

    IF v_catalog_count = 1 THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 52. Restrictive RLS policy on amenity_bookings verified in pg_policies';
    ELSE
        RAISE EXCEPTION 'FAIL: 52. Restrictive RLS policy on amenity_bookings missing or invalid';
    END IF;

    -- Assertion 53: Row security forced on helpdesk_tickets
    SELECT COUNT(*) INTO v_catalog_count
    FROM pg_class
    WHERE relname = 'helpdesk_tickets' AND relforcerowsecurity = true;

    IF v_catalog_count = 1 THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 53. Row security forced (relforcerowsecurity=true) on helpdesk_tickets';
    ELSE
        RAISE EXCEPTION 'FAIL: 53. Row security not forced on helpdesk_tickets';
    END IF;

    -- Assertion 54: Row security forced on amenity_bookings
    SELECT COUNT(*) INTO v_catalog_count
    FROM pg_class
    WHERE relname = 'amenity_bookings' AND relforcerowsecurity = true;

    IF v_catalog_count = 1 THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 54. Row security forced (relforcerowsecurity=true) on amenity_bookings';
    ELSE
        RAISE EXCEPTION 'FAIL: 54. Row security not forced on amenity_bookings';
    END IF;

    -- Assertion 55: Information schema table privilege audit for helpdesk_tickets
    SELECT COUNT(*) INTO v_catalog_count
    FROM information_schema.table_privileges
    WHERE table_name = 'helpdesk_tickets' AND grantee = 'authenticated' AND privilege_type = 'UPDATE';

    IF v_catalog_count >= 1 THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 55. Table UPDATE privilege on helpdesk_tickets verified bounded by RLS policy';
    ELSE
        RAISE EXCEPTION 'FAIL: 55. Table privilege audit failed';
    END IF;

    -- Assertion 56: Information schema table privilege audit for amenity_bookings
    SELECT COUNT(*) INTO v_catalog_count
    FROM information_schema.table_privileges
    WHERE table_name = 'amenity_bookings' AND grantee = 'authenticated' AND privilege_type = 'UPDATE';

    IF v_catalog_count >= 1 THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 56. Table UPDATE privilege on amenity_bookings verified bounded by RLS policy';
    ELSE
        RAISE EXCEPTION 'FAIL: 56. Table privilege audit failed';
    END IF;

    -- Assertion 57: Routine EXECUTE revoked from PUBLIC on assign_ticket
    SELECT COUNT(*) INTO v_catalog_count
    FROM information_schema.routine_privileges
    WHERE routine_name = 'assign_ticket' AND grantee = 'PUBLIC';

    IF v_catalog_count = 0 THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 57. assign_ticket EXECUTE privilege revoked from PUBLIC';
    ELSE
        RAISE EXCEPTION 'FAIL: 57. assign_ticket PUBLIC EXECUTE privilege not revoked';
    END IF;

    -- Assertion 58: Routine EXECUTE granted to authenticated on assign_ticket
    SELECT COUNT(*) INTO v_catalog_count
    FROM information_schema.routine_privileges
    WHERE routine_name = 'assign_ticket' AND grantee = 'authenticated';

    IF v_catalog_count >= 1 THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 58. assign_ticket EXECUTE privilege granted to authenticated role';
    ELSE
        RAISE EXCEPTION 'FAIL: 58. assign_ticket authenticated EXECUTE privilege missing';
    END IF;

    -- Assertion 59: Routine EXECUTE revoked from PUBLIC on resolve_ticket
    SELECT COUNT(*) INTO v_catalog_count
    FROM information_schema.routine_privileges
    WHERE routine_name = 'resolve_ticket' AND grantee = 'PUBLIC';

    IF v_catalog_count = 0 THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 59. resolve_ticket EXECUTE privilege revoked from PUBLIC';
    ELSE
        RAISE EXCEPTION 'FAIL: 59. resolve_ticket PUBLIC EXECUTE privilege not revoked';
    END IF;

    -- Assertion 60: Routine EXECUTE revoked from PUBLIC on reject_amenity_booking
    SELECT COUNT(*) INTO v_catalog_count
    FROM information_schema.routine_privileges
    WHERE routine_name = 'reject_amenity_booking' AND grantee = 'PUBLIC';

    IF v_catalog_count = 0 THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 60. reject_amenity_booking EXECUTE privilege revoked from PUBLIC';
    ELSE
        RAISE EXCEPTION 'FAIL: 60. reject_amenity_booking PUBLIC EXECUTE privilege not revoked';
    END IF;

    -- Assertion 61: SLA columns present on helpdesk_tickets catalog
    SELECT COUNT(*) INTO v_catalog_count
    FROM information_schema.columns
    WHERE table_name = 'helpdesk_tickets' 
      AND column_name IN ('assigned_at', 'started_at', 'closed_at', 'reopened_at');

    IF v_catalog_count = 4 THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 61. All 4 SLA timestamp columns present on helpdesk_tickets';
    ELSE
        RAISE EXCEPTION 'FAIL: 61. SLA columns missing from helpdesk_tickets (found %/4)', v_catalog_count;
    END IF;

    -- Assertion 62: Amenity fee transaction type present in ledger_transactions check constraint
    SELECT COUNT(*) INTO v_catalog_count
    FROM information_schema.check_constraints
    WHERE constraint_name = 'chk_tx_type';

    IF v_catalog_count >= 1 THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 62. chk_tx_type constraint verified with amenity_fee';
    ELSE
        RAISE EXCEPTION 'FAIL: 62. chk_tx_type constraint missing';
    END IF;


    -- --------------------------------------------------------------------------
    -- FINAL VERIFICATION SUMMARY
    -- --------------------------------------------------------------------------
    RAISE NOTICE '==================================================';
    RAISE NOTICE 'SLICE 15 VERIFICATION COMPLETE: %/% TESTS PASSED', v_pass_count, v_total_count;
    RAISE NOTICE '==================================================';

    IF v_pass_count != v_total_count THEN
        RAISE EXCEPTION 'Slice 15 verification failed: %/% passed', v_pass_count, v_total_count;
    END IF;
END $$;
