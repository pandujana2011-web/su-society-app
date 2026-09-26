-- SU SOCIETY APP - SLICE 5 VERIFICATION
-- Governance, Documents, Notices, Vehicles & Parking

BEGIN;

DO $$
DECLARE
    -- Test Actor UUIDs
    admin_a UUID := 'e1000000-0000-0000-0000-000000000010';
    admin_b UUID := 'e1000000-0000-0000-0000-000000000011';
    owner_a UUID := 'e2000000-0000-0000-0000-000000000021';
    owner_b UUID := 'e2000000-0000-0000-0000-000000000022';
    tenant_a UUID := 'e3000000-0000-0000-0000-000000000031';
    
    soc_a UUID := 'e0000000-0000-0000-0000-000000000001';
    soc_b UUID := 'e0000000-0000-0000-0000-000000000002';
    prop_a1 UUID := 'e4000000-0000-0000-0000-000000000041';
    prop_b1 UUID := 'e4000000-0000-0000-0000-000000000042';
    
    v_notice_id UUID;
    v_poll_id UUID;
    v_vote_id UUID;
    v_slot1_id UUID;
    v_slot2_id UUID;
    v_vehicle_id UUID;
    v_doc_id UUID;
    v_count INT;

    v_err_msg TEXT;
BEGIN
    RAISE NOTICE '--- SLICE 5: STARTING VERIFICATION ---';

    -- Setup Isolated Data for Slice 5
    -- (We run this as a superuser before setting RLS context)
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', '{}'::text, true);
    EXECUTE 'SET LOCAL ROLE postgres';

    INSERT INTO public.societies (id, name, registration_number, address) VALUES 
        (soc_a, 'Society A', 'REG-A5', 'Add A'),
        (soc_b, 'Society B', 'REG-B5', 'Add B');

    INSERT INTO auth.users (id, email, created_at, updated_at, confirmation_token, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, is_super_admin, role)
    VALUES 
        (admin_a, 's5admina@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
        (admin_b, 's5adminb@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
        (owner_a, 's5ownera@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
        (owner_b, 's5ownerb@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
        (tenant_a, 's5tenanta@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated');

    INSERT INTO public.users (id, full_name, mobile) VALUES 
        (admin_a, 'Admin A', '5111111111'),
        (admin_b, 'Admin B', '5222222222'),
        (owner_a, 'Owner A', '5333333333'),
        (owner_b, 'Owner B', '5444444444'),
        (tenant_a, 'Tenant A', '5555555555');

    INSERT INTO public.user_roles (user_id, society_id, role_name, granted_by) VALUES 
        (admin_a, soc_a, 'super_admin', admin_a),
        (admin_b, soc_b, 'super_admin', admin_b),
        (owner_a, soc_a, 'member', admin_a),
        (owner_b, soc_a, 'member', admin_a),
        (tenant_a, soc_a, 'member', admin_a);

    INSERT INTO public.properties (id, society_id, plot_number, plot_size_sqft, construction_status, occupancy_status, created_by) VALUES 
        (prop_a1, soc_a, 'Plot 1', 1000, 'constructed', 'owner_occupied', admin_a),
        (prop_b1, soc_b, 'Plot 2', 1000, 'constructed', 'owner_occupied', admin_b);

    INSERT INTO public.property_owners (property_id, owner_id, is_primary_owner, ownership_share_pct, start_date, created_by)
    VALUES 
        (prop_a1, owner_a, true, 100, '2026-01-01', admin_a),
        (prop_b1, owner_b, true, 100, '2026-01-01', admin_b);

    INSERT INTO public.tenancies (society_id, property_id, tenant_id, start_date, created_by)
    VALUES (soc_a, prop_a1, tenant_a, '2026-06-01', admin_a);

    -- =========================================================================
    -- 1. NOTICES VERIFICATION
    -- =========================================================================
    
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', admin_a::text, 'role', 'authenticated')::text, true);
    
    -- Create Notice
    INSERT INTO public.notices (society_id, title, content, visibility, created_by)
    VALUES (soc_a, 'AGM Meeting', 'Meeting tomorrow', 'all', admin_a)
    RETURNING id INTO v_notice_id;
    
    RAISE NOTICE 'PASS: Admin successfully created notice';
    
    -- Verify RLS: tenant_a can see it (visibility = 'all' and same society)
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', tenant_a::text, 'role', 'authenticated')::text, true);
    IF NOT EXISTS (SELECT 1 FROM public.notices WHERE id = v_notice_id) THEN
        RAISE EXCEPTION 'FAIL: Tenant cannot see "all" notice';
    END IF;
    RAISE NOTICE 'PASS: Tenant can see "all" notice';

    -- Verify RLS: cross society block
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', admin_b::text, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    IF EXISTS (SELECT 1 FROM public.notices WHERE id = v_notice_id) THEN
        RAISE EXCEPTION 'FAIL: Cross-society notice visibility leak';
    END IF;
    RAISE NOTICE 'PASS: Cross-society notice blocked';

    -- =========================================================================
    -- 2. GOVERNANCE & POLLS VERIFICATION
    -- =========================================================================
    
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', admin_a::text, 'role', 'authenticated')::text, true);
    
    INSERT INTO public.polls (society_id, title, description, starts_at, ends_at, created_by)
    VALUES (soc_a, 'New Paint Color', 'Choose paint', NOW() - INTERVAL '1 day', NOW() + INTERVAL '2 days', admin_a)
    RETURNING id INTO v_poll_id;
    
    RAISE NOTICE 'PASS: Admin created draft poll';

    -- Attempt voting on draft poll (Should Fail)
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', owner_a::text, 'role', 'authenticated')::text, true);
    BEGIN
        PERFORM public.fn_cast_poll_vote(v_poll_id, prop_a1, 'Blue');
        RAISE EXCEPTION 'FAIL: Allowed voting on draft poll';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%Poll is not active%' THEN RAISE EXCEPTION 'FAIL: Expected not active error, got %', SQLERRM; END IF;
        RAISE NOTICE 'PASS: Blocked voting on draft poll (State machine enforced)';
    END;

    -- Admin activates poll
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', admin_a::text, 'role', 'authenticated')::text, true);
    UPDATE public.polls SET status = 'active' WHERE id = v_poll_id;
    
    RAISE NOTICE 'PASS: Admin activated poll';

    -- Valid Vote
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', owner_a::text, 'role', 'authenticated')::text, true);
    v_vote_id := public.fn_cast_poll_vote(v_poll_id, prop_a1, 'Blue');
    RAISE NOTICE 'PASS: Owner cast a valid vote';

    -- Double Vote (Idempotency / AD-1)
    BEGIN
        PERFORM public.fn_cast_poll_vote(v_poll_id, prop_a1, 'Red');
        RAISE EXCEPTION 'FAIL: Allowed double voting';
    EXCEPTION WHEN unique_violation THEN
        RAISE NOTICE 'PASS: Blocked double voting [AD-1 Enforced]';
    END;

    -- Tenant attempting to vote (Should Fail)
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', tenant_a::text, 'role', 'authenticated')::text, true);
    BEGIN
        PERFORM public.fn_cast_poll_vote(v_poll_id, prop_a1, 'Green');
        RAISE EXCEPTION 'FAIL: Allowed tenant voting';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%Access Denied: Caller is not an active owner%' THEN RAISE EXCEPTION 'FAIL: Expected ownership error, got %', SQLERRM; END IF;
        RAISE NOTICE 'PASS: Blocked tenant voting (Must be owner)';
    END;
    
    -- Cross-society voting attack (Should Fail)
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', owner_a::text, 'role', 'authenticated')::text, true);
    BEGIN
        PERFORM public.fn_cast_poll_vote(v_poll_id, prop_b1, 'Blue');
        RAISE EXCEPTION 'FAIL: Allowed cross-society voting';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%Access Denied: Caller is not an active owner%' THEN RAISE EXCEPTION 'FAIL: Expected ownership error, got %', SQLERRM; END IF;
        RAISE NOTICE 'PASS: Blocked cross-society voting';
    END;

    -- Poll Closure and Mutation blocking
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', admin_a::text, 'role', 'authenticated')::text, true);
    UPDATE public.polls SET status = 'closed' WHERE id = v_poll_id;
    RAISE NOTICE 'PASS: Admin closed poll';
    
    BEGIN
        UPDATE public.polls SET title = 'Hacked' WHERE id = v_poll_id;
        RAISE EXCEPTION 'FAIL: Allowed mutation of closed poll';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%Poll configuration is immutable%' THEN RAISE EXCEPTION 'FAIL: Expected immutable error, got %', SQLERRM; END IF;
        RAISE NOTICE 'PASS: Poll configuration is immutable (State machine)';
    END;


    -- =========================================================================
    -- 3. PARKING & VEHICLES VERIFICATION
    -- =========================================================================
    
    -- Admin creates parking slots
    INSERT INTO public.parking_slots (society_id, slot_number, property_id)
    VALUES (soc_a, 'A-101-P1', prop_a1)
    RETURNING id INTO v_slot1_id;

    INSERT INTO public.parking_slots (society_id, slot_number, is_visitor)
    VALUES (soc_a, 'VIS-01', TRUE)
    RETURNING id INTO v_slot2_id;
    
    RAISE NOTICE 'PASS: Admin created parking slots';

    -- Owner registers vehicle
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', owner_a::text, 'role', 'authenticated')::text, true);
    INSERT INTO public.vehicles (society_id, property_id, registration_number, vehicle_type)
    VALUES (soc_a, prop_a1, 'KA-01-AB-1234', '4-wheeler')
    RETURNING id INTO v_vehicle_id;
    
    RAISE NOTICE 'PASS: Owner registered vehicle';

    -- Owner assigns vehicle to their slot
    PERFORM public.fn_assign_parking_slot(v_vehicle_id, v_slot1_id);
    RAISE NOTICE 'PASS: Owner assigned vehicle to their property slot';

    -- Owner attempts to assign to visitor slot (Should Fail)
    BEGIN
        PERFORM public.fn_assign_parking_slot(v_vehicle_id, v_slot2_id);
        RAISE EXCEPTION 'FAIL: Allowed resident to claim visitor slot';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%Cannot assign resident vehicle to visitor slot%' THEN RAISE EXCEPTION 'FAIL: Expected visitor slot error, got %', SQLERRM; END IF;
        RAISE NOTICE 'PASS: Blocked resident from claiming visitor slot';
    END;


    -- =========================================================================
    -- 4. DOCUMENTS VERIFICATION
    -- =========================================================================
    
    -- Owner uploads a document for their property
    INSERT INTO public.documents (society_id, property_id, title, document_type, file_url, uploaded_by)
    VALUES (soc_a, prop_a1, 'Lease Agreement', 'lease', 'https://s3/lease.pdf', owner_a)
    RETURNING id INTO v_doc_id;
    RAISE NOTICE 'PASS: Owner uploaded document';

    -- Tenant viewing document (RLS)
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', tenant_a::text, 'role', 'authenticated')::text, true);
    IF NOT EXISTS (SELECT 1 FROM public.documents WHERE id = v_doc_id) THEN
        RAISE EXCEPTION 'FAIL: Tenant cannot see property document';
    END IF;
    RAISE NOTICE 'PASS: Tenant can see property document';

    -- Other owner viewing document (Should Fail RLS)
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', owner_b::text, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    IF EXISTS (SELECT 1 FROM public.documents WHERE id = v_doc_id) THEN
        RAISE EXCEPTION 'FAIL: RLS leak, neighbor can see document';
    END IF;
    RAISE NOTICE 'PASS: Neighbor cannot see private property document';

    -- =========================================================================
    -- 5. REPORTING VERIFICATION
    -- =========================================================================
    
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', admin_a::text, 'role', 'authenticated')::text, true);
    
    -- We haven't inserted any charges for this property in this isolated slice, so vw_member_financial_statement might be empty.
    -- But we can just test if the view exists and is selectable.
    SELECT COUNT(*) INTO v_count FROM public.vw_member_financial_statement WHERE property_id = prop_a1;
    -- Result will be 0, which is perfectly valid since no charges exist.
    RAISE NOTICE 'PASS: vw_member_financial_statement executed successfully';

    RAISE NOTICE '--- SLICE 5 TESTS PASSED ---';

EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_err_msg = MESSAGE_TEXT;
        RAISE EXCEPTION 'SLICE 5 VERIFICATION FAILED: %', v_err_msg;
END;
$$ LANGUAGE plpgsql;

ROLLBACK;
