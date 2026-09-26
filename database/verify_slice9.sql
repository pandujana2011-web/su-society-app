CREATE OR REPLACE FUNCTION pg_temp.set_auth_uid(p_uid TEXT)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    PERFORM set_config('request.jwt.claims', format('{"sub": "%s"}', p_uid), true);
END;
$$;

DO $$ 
DECLARE 
    v_society_id UUID;
    v_admin_id UUID;
    v_owner_id UUID;
    v_property_id UUID;
    v_staff_id UUID;
    v_pass_id UUID;
    v_log_id UUID;
    v_violation_id UUID;
    v_ledger_id UUID;
BEGIN
    RAISE NOTICE 'Starting Slice 9 Verification...';

    v_society_id := gen_random_uuid();
    v_admin_id := gen_random_uuid();
    v_owner_id := gen_random_uuid();
    v_property_id := gen_random_uuid();

    -- Insert users
    INSERT INTO auth.users (id, email, created_at, updated_at, confirmation_token, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, is_super_admin, role) VALUES 
        (v_admin_id, 's9admin@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
        (v_owner_id, 's9owner@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated');

    INSERT INTO public.users (id, full_name, mobile) VALUES 
        (v_admin_id, 'Admin User', '1111111111'),
        (v_owner_id, 'Owner User', '2222222222');

    -- Insert society & property
    INSERT INTO public.societies (id, name) VALUES (v_society_id, 'Slice 9 Society');
    INSERT INTO public.properties (id, society_id, plot_number, created_by) VALUES (v_property_id, v_society_id, 'P-101', v_admin_id);
    INSERT INTO public.property_owners (property_id, owner_id, created_by) VALUES (v_property_id, v_owner_id, v_admin_id);
    INSERT INTO public.user_roles (society_id, user_id, role_name, granted_by) VALUES (v_society_id, v_admin_id, 'admin', v_admin_id);

    -- Create a staff member
    PERFORM pg_temp.set_auth_uid(v_admin_id::text);
    INSERT INTO public.daily_staff (society_id, name, role, phone_number, verification_status)
    VALUES (v_society_id, 'Test Staff', 'Plumber', '9999999999', 'verified')
    RETURNING id INTO v_staff_id;

    -- Create an active gate pass
    INSERT INTO public.gate_passes (society_id, property_id, staff_id, status, valid_from, valid_until, requested_by, approved_by)
    VALUES (v_society_id, v_property_id, v_staff_id, 'active', NOW() - INTERVAL '1 day', NOW() + INTERVAL '1 day', v_owner_id, v_admin_id)
    RETURNING id INTO v_pass_id;

    -- 2. STAFF ATTENDANCE TESTS
    RAISE NOTICE 'Testing Staff Attendance...';

    -- [Test] Admin/Gatekeeper can check-in
    PERFORM public.fn_staff_check_in(v_pass_id);
    RAISE NOTICE 'PASS: Authorized check-in succeeds';

    -- [Test] Double check-in blocked by unique index
    BEGIN
        PERFORM public.fn_staff_check_in(v_pass_id);
        RAISE EXCEPTION 'Failed: Double check-in succeeded';
    EXCEPTION WHEN unique_violation THEN
        RAISE NOTICE 'PASS: Double check-in blocked by unique index';
    END;

    -- Get the log ID
    SELECT id INTO v_log_id FROM public.staff_attendance_logs WHERE staff_id = v_staff_id;

    -- [Test] Direct update to check_out blocked
    BEGIN
        UPDATE public.staff_attendance_logs SET check_out = NOW() WHERE id = v_log_id;
        RAISE EXCEPTION 'Failed: Direct UPDATE succeeded';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%Direct updates blocked%' THEN RAISE; END IF;
    END;
    RAISE NOTICE 'PASS: Direct attendance UPDATE blocked without context';

    -- [Test] Elevated Direct UPDATE blocked with fake context
    BEGIN
        PERFORM set_config('app.attendance_transition', 'true', true);
        UPDATE public.staff_attendance_logs SET check_out = NOW() WHERE id = v_log_id;
        RAISE EXCEPTION 'Failed: Elevated Direct UPDATE with fake context succeeded';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%Direct updates blocked%' THEN RAISE; END IF;
    END;
    RAISE NOTICE 'PASS: Elevated Direct UPDATE blocked with fake context';

    -- [Test] Authorized check-out
    PERFORM public.fn_staff_check_out(v_log_id);
    RAISE NOTICE 'PASS: Authorized check-out succeeds';

    -- [Test] Double check-out blocked
    BEGIN
        PERFORM public.fn_staff_check_out(v_log_id);
        RAISE EXCEPTION 'Failed: Double check-out succeeded';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%Already checked out%' THEN RAISE; END IF;
    END;
    RAISE NOTICE 'PASS: Double check-out blocked';


    -- 3. RULE VIOLATIONS TESTS
    RAISE NOTICE 'Testing Rule Violations...';

    PERFORM pg_temp.set_auth_uid(v_owner_id::text);
    INSERT INTO public.rule_violations (society_id, property_id, violation_type, description)
    VALUES (v_society_id, v_property_id, 'parking', 'Parked in wrong slot')
    RETURNING id INTO v_violation_id;
    RAISE NOTICE 'PASS: Resident can report a rule violation';

    -- Reset to Admin to process violation
    PERFORM pg_temp.set_auth_uid(v_admin_id::text);

    -- [Test] Transition to under_review
    PERFORM public.fn_transition_violation_state(v_violation_id, 'under_review');
    RAISE NOTICE 'PASS: Admin transitions violation to under_review';

    -- Reset config since we are in the same transaction
    PERFORM set_config('app.violation_transition', '', true);

    -- [Test] Direct update to status blocked
    BEGIN
        UPDATE public.rule_violations SET status = 'dismissed' WHERE id = v_violation_id;
        RAISE EXCEPTION 'Failed: Direct UPDATE succeeded';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%Direct updates blocked%' THEN RAISE; END IF;
    END;
    RAISE NOTICE 'PASS: Direct violation UPDATE blocked without context';

    -- [Test] Elevated Direct UPDATE blocked with string literal
    BEGIN
        -- Simulating SQL injection or comment bypass (since we are effectively a superuser running DO block)
        UPDATE public.rule_violations SET status = 'dismissed' WHERE id = v_violation_id AND 'test fn_transition_violation_state test' IS NOT NULL;
        RAISE EXCEPTION 'Failed: Elevated Direct UPDATE with string literal succeeded';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%Direct updates blocked%' THEN RAISE; END IF;
    END;
    RAISE NOTICE 'PASS: Elevated Direct UPDATE blocked with string literal';

    -- [Test] Transition to penalized
    PERFORM public.fn_transition_violation_state(v_violation_id, 'penalized', 500.00);
    RAISE NOTICE 'PASS: Admin transitions violation to penalized';

    -- Check ledger integrity
    SELECT ledger_transaction_id INTO v_ledger_id FROM public.rule_violations WHERE id = v_violation_id;
    IF v_ledger_id IS NULL THEN
        RAISE EXCEPTION 'Failed: Ledger transaction ID not stored in rule violation';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.ledger_transactions WHERE id = v_ledger_id AND transaction_type = 'penalty' AND amount = 500.00) THEN
        RAISE EXCEPTION 'Failed: Ledger transaction missing or incorrect';
    END IF;
    RAISE NOTICE 'PASS: Financial integrity maintained, ledger transaction accurately created for penalty';

    -- Clean up test records (let rollback handle the actual database cleaning in the wrapper script)
    RAISE NOTICE 'Slice 9 Verification PASS';
END;
$$;
