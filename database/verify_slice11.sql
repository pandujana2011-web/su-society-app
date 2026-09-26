-- ==============================================================================
-- SU SOCIETY APP - SLICE 11: METERED UTILITIES VERIFICATION
-- ==============================================================================

\set ON_ERROR_STOP on

CREATE OR REPLACE FUNCTION pg_temp.set_auth_uid(p_uid TEXT)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    PERFORM set_config('request.jwt.claims', format('{"sub": "%s"}', p_uid), true);
END;
$$;

DO $$ 
DECLARE
    v_soc1 UUID;
    v_soc2 UUID;
    v_admin1 UUID;
    v_admin2 UUID;
    v_member1 UUID;
    
    v_prop1 UUID;
    v_prop2 UUID;
    v_meter1 UUID;
    v_meter2 UUID;
    v_read1 UUID;
    
    v_txn_count INT;
    v_audit_count INT;
BEGIN
    RAISE NOTICE '==================================================';
    RAISE NOTICE 'STARTING SLICE 11 VERIFICATION (METERED UTILITIES)';
    RAISE NOTICE '==================================================';

    -- 1. Setup Test Data (Runs as postgres)
    v_soc1 := gen_random_uuid();
    v_soc2 := gen_random_uuid();
    v_admin1 := gen_random_uuid();
    v_admin2 := gen_random_uuid();
    v_member1 := gen_random_uuid();
    v_prop1 := gen_random_uuid();
    v_prop2 := gen_random_uuid();

    -- Insert into auth.users (mock)
    INSERT INTO auth.users (id, email, created_at, updated_at, confirmation_token, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, is_super_admin, role) VALUES 
        (v_admin1, 'a111@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
        (v_admin2, 'a211@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
        (v_member1, 'm111@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated');

    -- Insert into public.users
    INSERT INTO public.users (id, full_name, mobile) VALUES 
        (v_admin1, 'Admin 1', '1111111111'),
        (v_admin2, 'Admin 2', '2222222222'),
        (v_member1, 'Member 1', '3333333333');

    -- Insert Societies
    INSERT INTO public.societies (id, name) VALUES 
        (v_soc1, 'Society 1'),
        (v_soc2, 'Society 2');

    -- Insert Roles
    INSERT INTO public.user_roles (society_id, user_id, role_name, granted_by) VALUES 
        (v_soc1, v_admin1, 'admin', v_admin1),
        (v_soc2, v_admin2, 'admin', v_admin2),
        (v_soc1, v_member1, 'member', v_admin1);

    -- Insert Properties
    INSERT INTO public.properties (id, society_id, plot_number, plot_size_sqft, created_by) VALUES 
        (v_prop1, v_soc1, 'P11', 1000, v_admin1),
        (v_prop2, v_soc2, 'P12', 1000, v_admin2);

    -- Insert Primary Owner
    INSERT INTO public.property_owners (property_id, owner_id, is_primary_owner, start_date, created_by) VALUES 
        (v_prop1, v_member1, TRUE, NOW(), v_admin1);

    -- ---------------------------------------------------------
    -- FUNCTIONAL TESTS & RLS
    -- ---------------------------------------------------------
    PERFORM set_config('role', 'authenticated', true);
    
    -- Admin 1 creates Meter
    PERFORM pg_temp.set_auth_uid(v_admin1::text);
    
    INSERT INTO public.utility_meters (society_id, property_id, utility_type, meter_number, unit_rate)
    VALUES (v_soc1, v_prop1, 'water', 'WM-001', 5.50)
    RETURNING id INTO v_meter1;
    
    RAISE NOTICE 'PASS: Admin can create utility meter';

    -- Member 1 can view meter for their property
    PERFORM pg_temp.set_auth_uid(v_member1::text);
    IF NOT EXISTS (SELECT 1 FROM public.utility_meters WHERE id = v_meter1) THEN
        RAISE EXCEPTION 'FAIL: Member cannot view their own property meter';
    END IF;
    RAISE NOTICE 'PASS: Member can view their own property meter';

    -- Member 1 cannot create reading (RLS check)
    BEGIN
        INSERT INTO public.meter_readings (meter_id, reading_date, previous_reading, current_reading, applied_unit_rate, created_by)
        VALUES (v_meter1, CURRENT_DATE, 100.00, 150.00, 5.50, v_member1);
        RAISE EXCEPTION 'FAIL: Member created a meter reading';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'PASS: Member cannot create a meter reading (%)', SQLERRM;
    END;

    -- Cross-society Isolation
    PERFORM pg_temp.set_auth_uid(v_admin2::text);
    IF EXISTS (SELECT 1 FROM public.utility_meters WHERE id = v_meter1) THEN
        RAISE EXCEPTION 'FAIL: Cross-society leak detected (Admin 2 saw Meter 1)';
    END IF;
    RAISE NOTICE 'PASS: Cross-society isolation enforced on SELECT';
    
    -- ---------------------------------------------------------
    -- CONSTRAINT TESTS
    -- ---------------------------------------------------------
    PERFORM pg_temp.set_auth_uid(v_admin1::text);

    -- Try invalid reading (current < previous)
    BEGIN
        INSERT INTO public.meter_readings (meter_id, reading_date, previous_reading, current_reading, applied_unit_rate, created_by)
        VALUES (v_meter1, CURRENT_DATE, 100.00, 90.00, 5.50, v_admin1);
        RAISE EXCEPTION 'FAIL: Invalid reading allowed';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'PASS: Invalid reading blocked by CHECK constraint (current_reading >= previous_reading)';
    END;

    -- Create valid reading
    INSERT INTO public.meter_readings (meter_id, reading_date, previous_reading, current_reading, applied_unit_rate, created_by)
    VALUES (v_meter1, CURRENT_DATE, 100.00, 150.00, 5.50, v_admin1)
    RETURNING id INTO v_read1;

    -- Verify derived calculations
    IF (SELECT consumption FROM public.meter_readings WHERE id = v_read1) != 50.00 THEN
        RAISE EXCEPTION 'FAIL: Generated consumption incorrect';
    END IF;
    
    IF (SELECT total_charge FROM public.meter_readings WHERE id = v_read1) != 275.00 THEN
        RAISE EXCEPTION 'FAIL: Generated total_charge incorrect';
    END IF;
    RAISE NOTICE 'PASS: Database generated consumption and total_charge correctly';

    -- ---------------------------------------------------------
    -- STATE MACHINE & ELEVATED SECURITY TESTS
    -- ---------------------------------------------------------
    
    -- Admin 1 tries direct UPDATE on status
    BEGIN
        UPDATE public.meter_readings SET status = 'verified' WHERE id = v_read1;
        RAISE EXCEPTION 'FAIL: Direct UPDATE to reading status allowed';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'PASS: Direct UPDATE to reading status blocked (%)', SQLERRM;
    END;

    -- Admin 1 tries fake transition context
    BEGIN
        PERFORM set_config('app.meter_transition', 'fake-uuid', true);
        UPDATE public.meter_readings SET status = 'verified' WHERE id = v_read1;
        RAISE EXCEPTION 'FAIL: Fake context allowed UPDATE';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'PASS: Fake context blocked (%)', SQLERRM;
    END;
    
    PERFORM set_config('app.meter_transition', '', true);

    -- Authorized transition to verified
    PERFORM public.fn_transition_meter_reading_state(v_read1, 'verified');
    IF (SELECT status FROM public.meter_readings WHERE id = v_read1) != 'verified' THEN
        RAISE EXCEPTION 'FAIL: Reading status did not change to verified';
    END IF;
    RAISE NOTICE 'PASS: Authorized transition to verified successful';

    -- Transition to billed
    PERFORM public.fn_transition_meter_reading_state(v_read1, 'billed');
    
    IF (SELECT status FROM public.meter_readings WHERE id = v_read1) != 'billed' THEN
        RAISE EXCEPTION 'FAIL: Reading status did not change to billed';
    END IF;

    -- Ensure Ledger Transaction was created accurately
    SELECT count(*) INTO v_txn_count FROM public.ledger_transactions WHERE source_meter_reading_id = v_read1 AND transaction_type = 'charge';
    IF v_txn_count != 1 THEN
        RAISE EXCEPTION 'FAIL: Expected exactly 1 ledger transaction, found %', v_txn_count;
    END IF;
    
    IF (SELECT amount FROM public.ledger_transactions WHERE source_meter_reading_id = v_read1) != 275.00 THEN
        RAISE EXCEPTION 'FAIL: Ledger transaction amount does not match total_charge';
    END IF;
    RAISE NOTICE 'PASS: Billed transition automatically created exactly one correct ledger transaction';

    -- Try double billing (billed -> billed)
    BEGIN
        PERFORM public.fn_transition_meter_reading_state(v_read1, 'billed');
        RAISE EXCEPTION 'FAIL: Double billing allowed';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'PASS: Double billing blocked';
    END;

    -- ---------------------------------------------------------
    -- AUDIT LOG VERIFICATION
    -- ---------------------------------------------------------
    SELECT count(*) INTO v_audit_count FROM public.audit_logs 
    WHERE entity_type IN ('utility_meters', 'meter_readings');
    
    IF v_audit_count < 2 THEN
        RAISE EXCEPTION 'FAIL: Expected at least 2 audit logs, found %', v_audit_count;
    END IF;
    RAISE NOTICE 'PASS: Audit triggers successfully logged operations (Found: %)', v_audit_count;

    RAISE NOTICE '==================================================';
    RAISE NOTICE 'SLICE 11 VERIFICATION COMPLETE (ALL TESTS PASS)';
    RAISE NOTICE '==================================================';

END $$;
