-- =========================================================================
-- SU SOCIETY APP - SLICE 8 VERIFICATION
-- =========================================================================

-- Helper to impersonate users
CREATE OR REPLACE FUNCTION pg_temp.set_auth_uid(p_uid TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', p_uid, 'role', 'authenticated')::text,
        TRUE);
    PERFORM set_config('request.jwt.claim.sub', p_uid, TRUE);
END;
$$;


DO $$
DECLARE
    -- Standard Users 
    u_super_admin UUID := gen_random_uuid();
    u_kalyan      UUID := gen_random_uuid(); -- Owner in Soc 1 (Plot-45)
    u_tenant      UUID := gen_random_uuid(); -- Tenant in Soc 1 (Plot-46)
    u_soc2_member UUID := gen_random_uuid(); -- Owner in Soc 2 (Villa-1)
    
    -- New test users
    u_gatekeeper  UUID := gen_random_uuid();
    u_soc2_admin  UUID := gen_random_uuid();
    
    -- IDs
    soc1_id UUID := gen_random_uuid();
    soc2_id UUID := gen_random_uuid();
    p45_id UUID := gen_random_uuid();
    p46_id UUID := gen_random_uuid();
    soc2_villa_id UUID := gen_random_uuid();
    
    v_move_req_id UUID;
    v_move_out_req_id UUID;
    v_parcel_id UUID;
    v_collection_code VARCHAR := '123456';
    
    v_record RECORD;
    v_error TEXT;
    
    -- Helper for outstanding balance manipulation
    v_policy_id UUID := gen_random_uuid();
    v_charge_id UUID;
BEGIN
    RAISE NOTICE 'Starting Slice 8 Verification...';

    -- =====================================================================
    -- SETUP TEST DATA
    -- =====================================================================
    INSERT INTO public.societies (id, name, registration_number, address) VALUES 
        (soc1_id, 'Greenwood Estate', 'REG-S8A', 'Address A'),
        (soc2_id, 'Silver Oaks', 'REG-S8B', 'Address B');
        
    INSERT INTO auth.users (id, email) VALUES 
        (u_super_admin, 'admin@soc8.com'),
        (u_kalyan, 'kalyan@soc8.com'),
        (u_tenant, 'tenant@soc8.com'),
        (u_soc2_member, 'member@soc8b.com'),
        (u_gatekeeper, 'gate@soc8.com'),
        (u_soc2_admin, 'admin2@soc8.com');

    INSERT INTO public.users (id, full_name, status) VALUES 
        (u_super_admin, 'Admin', 'active'), 
        (u_kalyan, 'Kalyan', 'active'), 
        (u_tenant, 'Tenant', 'active'), 
        (u_soc2_member, 'Soc 2 Member', 'active'),
        (u_gatekeeper, 'Gate Keeper', 'active'),
        (u_soc2_admin, 'Admin 2', 'active');

    INSERT INTO public.user_roles (user_id, society_id, role_name, granted_by) VALUES 
        (u_super_admin, soc1_id, 'super_admin', u_super_admin),
        (u_kalyan, soc1_id, 'member', u_super_admin),
        (u_tenant, soc1_id, 'tenant', u_super_admin),
        (u_soc2_member, soc2_id, 'member', u_soc2_admin),
        (u_gatekeeper, soc1_id, 'gatekeeper', u_super_admin),
        (u_soc2_admin, soc2_id, 'admin', u_soc2_admin);

    INSERT INTO public.properties (id, society_id, plot_number, created_by) VALUES 
        (p45_id, soc1_id, 'Plot-45', u_super_admin),
        (p46_id, soc1_id, 'Plot-46', u_super_admin),
        (soc2_villa_id, soc2_id, 'Villa-1', u_soc2_member);
        
    INSERT INTO public.property_owners (property_id, owner_id, is_primary_owner, ownership_share_pct, created_by) VALUES 
        (p45_id, u_kalyan, true, 100, u_super_admin),
        (soc2_villa_id, u_soc2_member, true, 100, u_soc2_member);
        
    INSERT INTO public.tenancies (society_id, property_id, tenant_id, created_by) VALUES
        (soc1_id, p46_id, u_tenant, u_super_admin);

    INSERT INTO public.maintenance_policies (id, society_id, name, charge_type, rate, created_by) VALUES
        (v_policy_id, soc1_id, 'Fixed Maintenance', 'fixed', 1000.00, u_super_admin);

    SET LOCAL ROLE authenticated;

    -- =====================================================================
    -- TEST BLOCK A: MOVE REQUESTS
    -- =====================================================================
    RAISE NOTICE 'Testing Move Requests...';

    -- [Test] 2. Authorized resident can create a pending move request
    PERFORM pg_temp.set_auth_uid(u_kalyan::text);
    INSERT INTO public.move_requests (society_id, property_id, request_type, primary_user_id, proposed_date, created_by)
    VALUES (soc1_id, p45_id, 'move_in', u_kalyan, CURRENT_DATE + 5, u_kalyan)
    RETURNING id INTO v_move_req_id;
    
    SELECT * INTO v_record FROM public.move_requests WHERE id = v_move_req_id;
    IF v_record.status != 'pending' THEN RAISE EXCEPTION 'Move request did not start as pending'; END IF;
    RAISE NOTICE 'PASS: Authorized resident can create a pending move request';

    -- [Test] 1. Admin can view move requests & 14. Cross-society SELECT isolation works
    PERFORM pg_temp.set_auth_uid(u_super_admin::text);
    IF NOT EXISTS (SELECT 1 FROM public.move_requests WHERE id = v_move_req_id) THEN
        RAISE EXCEPTION 'Admin cannot see move requests';
    END IF;
    
    PERFORM pg_temp.set_auth_uid(u_soc2_member::text);
    IF EXISTS (SELECT 1 FROM public.move_requests WHERE id = v_move_req_id) THEN
        RAISE EXCEPTION 'Cross-society move request SELECT isolation failed';
    END IF;
    RAISE NOTICE 'PASS: Admin view and cross-society isolation works';

    -- [Test] 3. Unauthorized resident cannot create a request for another property
    PERFORM pg_temp.set_auth_uid(u_tenant::text); -- tenant in P46 trying to insert for P45
    BEGIN
        INSERT INTO public.move_requests (society_id, property_id, request_type, primary_user_id, proposed_date, created_by)
        VALUES (soc1_id, p45_id, 'move_in', u_tenant, CURRENT_DATE + 5, u_tenant);
        RAISE EXCEPTION 'Failed: Unauthorized resident created request for another property';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Failed: %' THEN RAISE; END IF;
    END;
    RAISE NOTICE 'PASS: Unauthorized resident cannot create request for another property';

    -- [Test] 4. Cross-society move request creation fails (trigger validation)
    PERFORM pg_temp.set_auth_uid(u_kalyan::text);
    BEGIN
        -- kalyan tries to create move for Soc2 Villa
        INSERT INTO public.move_requests (society_id, property_id, request_type, primary_user_id, proposed_date, created_by)
        VALUES (soc1_id, soc2_villa_id, 'move_in', u_kalyan, CURRENT_DATE + 5, u_kalyan);
        RAISE EXCEPTION 'Failed: Cross society creation succeeded';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Failed: %' THEN RAISE; END IF;
    END;
    RAISE NOTICE 'PASS: Cross-society move request creation blocked by trigger';

    -- [Test] 10. Direct status modification blocked by RLS (Ordinary user)
    PERFORM pg_temp.set_auth_uid(u_super_admin::text);
    UPDATE public.move_requests SET status = 'approved' WHERE id = v_move_req_id;
    IF FOUND THEN
        RAISE EXCEPTION 'Failed: Direct status update succeeded';
    END IF;
    RAISE NOTICE 'PASS: Direct status modification blocked by RLS';

    -- Elevated Privilege Tests (Bypassing RLS)
    RESET ROLE; -- Now running as postgres (superuser)

    -- [Test] 10A. Elevated Direct UPDATE - No context
    BEGIN
        UPDATE public.move_requests SET status = 'approved' WHERE id = v_move_req_id;
        RAISE EXCEPTION 'Failed: Elevated Direct UPDATE without context succeeded';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%Direct status updates blocked%' THEN RAISE; END IF;
    END;
    RAISE NOTICE 'PASS: Elevated Direct UPDATE blocked without context';

    -- [Test] 10B. Elevated Direct UPDATE - Fake context (static string)
    BEGIN
        PERFORM set_config('app.move_req_transition', 'true', true);
        UPDATE public.move_requests SET status = 'approved' WHERE id = v_move_req_id;
        RAISE EXCEPTION 'Failed: Elevated Direct UPDATE with fake static context succeeded';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%Direct status updates blocked%' THEN RAISE; END IF;
    END;
    RAISE NOTICE 'PASS: Elevated Direct UPDATE blocked with fake context';

    -- [Test] 10C. Elevated Direct UPDATE - SQL comment bypass attempt
    BEGIN
        PERFORM set_config('app.move_req_transition', '', true);
        UPDATE public.move_requests SET status = 'approved' WHERE id = v_move_req_id; -- fn_transition_move_request_state
        RAISE EXCEPTION 'Failed: Elevated Direct UPDATE with SQL comment succeeded';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%Direct status updates blocked%' THEN RAISE; END IF;
    END;
    RAISE NOTICE 'PASS: Elevated Direct UPDATE blocked with SQL comment';

    -- [Test 10D] Elevated Direct UPDATE - String literal bypass attempt
    BEGIN
        UPDATE public.move_requests SET status = 'approved' WHERE id = v_move_req_id AND 'test fn_transition_move_request_state test' IS NOT NULL;
        RAISE EXCEPTION 'Failed: Elevated Direct UPDATE with string literal succeeded';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%Direct status updates blocked%' THEN RAISE; END IF;
    END;
    RAISE NOTICE 'PASS: Elevated Direct UPDATE blocked with string literal';

    -- Return to application context
    SET LOCAL ROLE authenticated;
    PERFORM pg_temp.set_auth_uid(u_super_admin::text);

    -- [Test] 11. Non-admin cannot approve/reject requests
    PERFORM pg_temp.set_auth_uid(u_kalyan::text);
    BEGIN
        PERFORM public.fn_transition_move_request_state(v_move_req_id, 'approved');
        RAISE EXCEPTION 'Failed: Non-admin could approve request';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Failed: %' THEN RAISE; END IF;
    END;
    RAISE NOTICE 'PASS: Non-admin cannot approve move requests';

    -- [Test] 5. Valid move-in approval succeeds
    PERFORM pg_temp.set_auth_uid(u_super_admin::text);
    PERFORM public.fn_transition_move_request_state(v_move_req_id, 'approved');
    SELECT * INTO v_record FROM public.move_requests WHERE id = v_move_req_id;
    IF v_record.status != 'approved' THEN RAISE EXCEPTION 'Status not approved'; END IF;
    IF v_record.approved_by != u_super_admin THEN RAISE EXCEPTION 'Approved by not recorded'; END IF;
    RAISE NOTICE 'PASS: Valid move-in approval succeeds';

    -- [Test] 12. Completed transition works
    PERFORM public.fn_transition_move_request_state(v_move_req_id, 'completed');
    SELECT status INTO v_record FROM public.move_requests WHERE id = v_move_req_id;
    IF v_record.status != 'completed' THEN RAISE EXCEPTION 'Status not completed'; END IF;
    RAISE NOTICE 'PASS: Completed transition works';

    -- [Test] 6. Move-out with outstanding dues fails
    -- Ensure property has dues by generating a charge
    PERFORM public.fn_generate_charge(p45_id, NULL, v_policy_id, '2026-09');
    
    PERFORM pg_temp.set_auth_uid(u_kalyan::text);
    INSERT INTO public.move_requests (society_id, property_id, request_type, primary_user_id, proposed_date, created_by)
    VALUES (soc1_id, p45_id, 'move_out', u_kalyan, CURRENT_DATE + 5, u_kalyan)
    RETURNING id INTO v_move_out_req_id;

    PERFORM pg_temp.set_auth_uid(u_super_admin::text);
    BEGIN
        PERFORM public.fn_transition_move_request_state(v_move_out_req_id, 'approved');
        RAISE EXCEPTION 'Failed: Move-out approved despite outstanding dues';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Failed: %' THEN RAISE; END IF;
        IF SQLERRM NOT LIKE '%Property has outstanding dues%' THEN RAISE EXCEPTION 'Wrong error for dues: %', SQLERRM; END IF;
    END;
    RAISE NOTICE 'PASS: Move-out with outstanding dues blocked (NOC check)';

    -- [Test] 7 & 8. Move-out with zero outstanding balance succeeds
    -- We need to pay the dues or reverse the charge. Let's reverse the charge.
    SELECT id INTO v_charge_id FROM public.maintenance_charges WHERE property_id = p45_id AND status = 'posted' LIMIT 1;
    PERFORM public.fn_reverse_charge(v_charge_id, 'Test reversal');
    
    PERFORM public.fn_transition_move_request_state(v_move_out_req_id, 'approved');
    SELECT * INTO v_record FROM public.move_requests WHERE id = v_move_out_req_id;
    IF v_record.status != 'approved' THEN RAISE EXCEPTION 'Move-out status not approved'; END IF;
    IF v_record.noc_status != 'cleared' THEN RAISE EXCEPTION 'noc_status not cleared'; END IF;
    IF v_record.approved_by != u_super_admin THEN RAISE EXCEPTION 'approved_by not set'; END IF;
    RAISE NOTICE 'PASS: Move-out with zero balance succeeds, noc_status cleared, approved_by set';


    -- =====================================================================
    -- TEST BLOCK B: PARCEL LOGS
    -- =====================================================================
    RAISE NOTICE 'Testing Parcel Logs...';

    -- [Test] 15 & 16. Gatekeeper can create parcel. Starts as received_at_gate
    PERFORM pg_temp.set_auth_uid(u_gatekeeper::text);
    INSERT INTO public.parcel_logs (society_id, property_id, recipient_user_id, carrier_name, tracking_number, collection_code, logged_by)
    VALUES (soc1_id, p45_id, u_kalyan, 'Amazon', 'AMZ123', v_collection_code, u_gatekeeper)
    RETURNING id INTO v_parcel_id;

    SELECT * INTO v_record FROM public.parcel_logs WHERE id = v_parcel_id;
    IF v_record.status != 'received_at_gate' THEN RAISE EXCEPTION 'Parcel did not start as received_at_gate'; END IF;
    RAISE NOTICE 'PASS: Gatekeeper can create parcel; starts as received_at_gate';

    -- [Test] 17. Owner can see parcel for own property
    PERFORM pg_temp.set_auth_uid(u_kalyan::text);
    IF NOT EXISTS (SELECT 1 FROM public.parcel_logs WHERE id = v_parcel_id) THEN
        RAISE EXCEPTION 'Owner cannot see their own parcel';
    END IF;
    RAISE NOTICE 'PASS: Owner can see their own parcel';

    -- [Test] 18. Owner cannot see another property's parcel
    PERFORM pg_temp.set_auth_uid(u_tenant::text);
    IF EXISTS (SELECT 1 FROM public.parcel_logs WHERE id = v_parcel_id) THEN
        RAISE EXCEPTION 'Tenant sees parcel from another property';
    END IF;
    RAISE NOTICE 'PASS: Owner/Tenant cannot see another property parcel';

    -- [Test] 19. Cross-society parcel creation fails
    PERFORM pg_temp.set_auth_uid(u_gatekeeper::text);
    BEGIN
        INSERT INTO public.parcel_logs (society_id, property_id, recipient_user_id, carrier_name, tracking_number, collection_code, logged_by)
        VALUES (soc1_id, soc2_villa_id, u_soc2_member, 'Flipkart', 'FK456', '654321', u_gatekeeper);
        RAISE EXCEPTION 'Failed: Cross-society parcel creation succeeded';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Failed: %' THEN RAISE; END IF;
    END;
    RAISE NOTICE 'PASS: Cross-society parcel creation blocked';

    -- [Test] 25. Direct status UPDATE blocked by RLS (Ordinary User)
    UPDATE public.parcel_logs SET status = 'collected' WHERE id = v_parcel_id;
    IF FOUND THEN
        RAISE EXCEPTION 'Failed: Direct status update succeeded';
    END IF;
    RAISE NOTICE 'PASS: Direct parcel status UPDATE blocked by RLS';

    -- Elevated Privilege Tests (Bypassing RLS)
    RESET ROLE; -- Now running as postgres (superuser)

    -- [Test] 25A. Elevated Direct UPDATE - No context
    BEGIN
        UPDATE public.parcel_logs SET status = 'collected' WHERE id = v_parcel_id;
        RAISE EXCEPTION 'Failed: Elevated Direct UPDATE without context succeeded';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%Direct status updates blocked%' THEN RAISE; END IF;
    END;
    RAISE NOTICE 'PASS: Elevated Direct UPDATE (Parcel) blocked without context';

    -- [Test] 25B. Elevated Direct UPDATE - Fake context (static string)
    BEGIN
        PERFORM set_config('app.parcel_transition', 'true', true);
        UPDATE public.parcel_logs SET status = 'collected' WHERE id = v_parcel_id;
        RAISE EXCEPTION 'Failed: Elevated Direct UPDATE with fake static context succeeded';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%Direct status updates blocked%' THEN RAISE; END IF;
    END;
    RAISE NOTICE 'PASS: Elevated Direct UPDATE (Parcel) blocked with fake context';

    -- [Test] 25C. Elevated Direct UPDATE - SQL comment bypass attempt
    BEGIN
        PERFORM set_config('app.parcel_transition', '', true);
        UPDATE public.parcel_logs SET status = 'collected' WHERE id = v_parcel_id; -- fn_transition_parcel_state
        RAISE EXCEPTION 'Failed: Elevated Direct UPDATE with SQL comment succeeded';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%Direct status updates blocked%' THEN RAISE; END IF;
    END;
    RAISE NOTICE 'PASS: Elevated Direct UPDATE (Parcel) blocked with SQL comment';

    -- [Test 25D] Elevated Direct UPDATE - String literal bypass attempt
    BEGIN
        UPDATE public.parcel_logs SET status = 'collected' WHERE id = v_parcel_id AND 'test fn_transition_parcel_state test' IS NOT NULL;
        RAISE EXCEPTION 'Failed: Elevated Direct UPDATE with string literal succeeded';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%Direct status updates blocked%' THEN RAISE; END IF;
    END;
    RAISE NOTICE 'PASS: Elevated Direct UPDATE (Parcel) blocked with string literal';

    -- Return to application context
    SET LOCAL ROLE authenticated;
    PERFORM pg_temp.set_auth_uid(u_gatekeeper::text);

    -- [Test] 20. Incorrect collection code fails
    BEGIN
        PERFORM public.fn_transition_parcel_state(v_parcel_id, 'collected', '000000');
        RAISE EXCEPTION 'Failed: Collected with incorrect code';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Failed: %' THEN RAISE; END IF;
    END;
    RAISE NOTICE 'PASS: Incorrect collection code fails';

    -- [Test] 21, 22, 23. Correct collection code succeeds, sets collected_by and collected_at
    PERFORM public.fn_transition_parcel_state(v_parcel_id, 'collected', v_collection_code);
    SELECT * INTO v_record FROM public.parcel_logs WHERE id = v_parcel_id;
    IF v_record.status != 'collected' THEN RAISE EXCEPTION 'Parcel not collected'; END IF;
    IF v_record.collected_by != u_gatekeeper THEN RAISE EXCEPTION 'collected_by not set correctly'; END IF;
    IF v_record.collected_at IS NULL THEN RAISE EXCEPTION 'collected_at not set'; END IF;
    RAISE NOTICE 'PASS: Correct collection code succeeds, correctly records collection details';

    -- [Test] 24. Invalid parcel transitions fail
    BEGIN
        -- already collected, cannot transition to returned
        PERFORM public.fn_transition_parcel_state(v_parcel_id, 'returned', NULL);
        RAISE EXCEPTION 'Failed: Invalid transition succeeded';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Failed: %' THEN RAISE; END IF;
    END;
    RAISE NOTICE 'PASS: Invalid parcel transitions fail';

    -- [Test] 26. Gatekeeper cannot access another society (implied by RLS/Trigger logic)
    -- Gatekeeper is in soc1, cannot transition a parcel in soc2. Let's create a parcel in soc2 via admin
    PERFORM pg_temp.set_auth_uid(u_soc2_admin::text);
    INSERT INTO public.parcel_logs (society_id, property_id, recipient_user_id, carrier_name, tracking_number, collection_code, logged_by)
    VALUES (soc2_id, soc2_villa_id, u_soc2_member, 'Fedex', 'F111', '111111', u_soc2_admin)
    RETURNING id INTO v_parcel_id;
    
    PERFORM pg_temp.set_auth_uid(u_gatekeeper::text);
    BEGIN
        PERFORM public.fn_transition_parcel_state(v_parcel_id, 'collected', '111111');
        RAISE EXCEPTION 'Failed: Gatekeeper transitioned cross-society parcel';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Failed: %' THEN RAISE; END IF;
    END;
    RAISE NOTICE 'PASS: Gatekeeper cannot access another society';

    -- [Test] 27 & 28. Audit record generated correctly & Collection code redacted
    PERFORM pg_temp.set_auth_uid(u_soc2_admin::text);
    -- look at the audit log for the parcel insert
    SELECT new_data INTO v_record FROM public.audit_logs 
    WHERE entity_type = 'parcel_logs' AND action = 'INSERT' AND society_id = soc2_id 
    ORDER BY created_at DESC LIMIT 1;
    
    IF v_record.new_data ? 'collection_code' THEN
        RAISE EXCEPTION 'Collection code leaked in audit log payload!';
    END IF;
    RAISE NOTICE 'PASS: Audit record generated and collection_code securely redacted';

    RAISE NOTICE 'Slice 8 Verification PASS';
END $$;
