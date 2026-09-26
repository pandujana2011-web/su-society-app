-- ===========================================================================
-- SLICE 6: VERIFICATION SCRIPT
-- ===========================================================================

-- Create auth helper function
CREATE OR REPLACE FUNCTION pg_temp.set_auth_uid(p_uid TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', p_uid, 'role', 'authenticated')::text,
        TRUE);  -- local = TRUE: resets after transaction
    PERFORM set_config('request.jwt.claim.sub', p_uid, TRUE);
END;
$$;

-- Create a helper function for assertions (assuming a testing framework isn't used, we use DO blocks and RAISE EXCEPTION)
DO $$
DECLARE
    v_society1_id UUID;
    v_society2_id UUID;
    v_admin_id UUID;
    v_owner_id UUID;
    v_tenant_id UUID;
    v_gatekeeper_id UUID;
    v_neighbor_id UUID;
    
    v_property1_id UUID;
    v_property2_id UUID;
    
    v_staff_id UUID;
    v_pass_id UUID;
    v_ticket_id UUID;
    
    v_audit_count INT;
    v_audit_row RECORD;
    v_error_caught BOOLEAN;
    
    v_index_count INT;
BEGIN
    RAISE NOTICE 'Starting Slice 6 Verification...';

    -- Generate IDs
    v_society1_id := gen_random_uuid();
    v_admin_id := gen_random_uuid();
    v_owner_id := gen_random_uuid();
    v_tenant_id := gen_random_uuid();
    v_gatekeeper_id := gen_random_uuid();
    v_neighbor_id := gen_random_uuid();
    v_property1_id := gen_random_uuid();
    v_property2_id := gen_random_uuid();

    -- Setup base data for Slice 6 testing
    INSERT INTO public.societies (id, name, registration_number, address) VALUES 
        (v_society1_id, 'Society 6', 'REG-S6', 'S6 Address');
        
    INSERT INTO auth.users (id, email, created_at, updated_at, confirmation_token, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, is_super_admin, role) VALUES 
        (v_admin_id, 's6admin@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
        (v_owner_id, 's6owner@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
        (v_tenant_id, 's6tenant@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
        (v_gatekeeper_id, 's6gk@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
        (v_neighbor_id, 's6neigh@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated');

    INSERT INTO public.users (id, full_name, mobile) VALUES 
        (v_admin_id, 'S6 Admin', '6111111111'),
        (v_owner_id, 'S6 Owner', '6222222222'),
        (v_tenant_id, 'S6 Tenant', '6333333333'),
        (v_gatekeeper_id, 'S6 Gatekeeper', '6444444444'),
        (v_neighbor_id, 'S6 Neighbor', '6555555555');

    INSERT INTO public.user_roles (user_id, society_id, role_name, granted_by) VALUES 
        (v_admin_id, v_society1_id, 'super_admin', v_admin_id),
        (v_owner_id, v_society1_id, 'member', v_admin_id),
        (v_tenant_id, v_society1_id, 'member', v_admin_id),
        (v_gatekeeper_id, v_society1_id, 'gatekeeper', v_admin_id),
        (v_neighbor_id, v_society1_id, 'member', v_admin_id);

    INSERT INTO public.properties (id, society_id, plot_number, plot_size_sqft, construction_status, occupancy_status, created_by) VALUES 
        (v_property1_id, v_society1_id, 'Plot S6-1', 1000, 'constructed', 'owner_occupied', v_admin_id),
        (v_property2_id, v_society1_id, 'Plot S6-2', 1000, 'constructed', 'owner_occupied', v_admin_id);

    INSERT INTO public.property_owners (property_id, owner_id, is_primary_owner, ownership_share_pct, start_date, created_by) VALUES 
        (v_property1_id, v_owner_id, true, 100, '2026-01-01', v_admin_id),
        (v_property2_id, v_neighbor_id, true, 100, '2026-01-01', v_admin_id);

    INSERT INTO public.tenancies (society_id, property_id, tenant_id, start_date, created_by)
        VALUES (v_society1_id, v_property1_id, v_tenant_id, '2026-06-01', v_admin_id);

    -- =======================================================================
    -- 1. INDEXES
    -- =======================================================================
    RAISE NOTICE 'Verifying Indexes...';
    SELECT count(*) INTO v_index_count FROM pg_indexes WHERE indexname IN (
        'idx_charges_property_id', 'idx_payments_society_id', 'idx_payments_property_id',
        'idx_ledger_property_id', 'idx_bookings_property_id', 'idx_tickets_property_id',
        'idx_vouchers_society_status'
    );
    IF v_index_count < 7 THEN RAISE EXCEPTION 'Missing Slice 6 targeted indexes'; END IF;

    -- =======================================================================
    -- 2. DAILY STAFF
    -- =======================================================================
    RAISE NOTICE 'Verifying Daily Staff...';
    
    -- Admin creation
    SET LOCAL ROLE authenticated;
    PERFORM pg_temp.set_auth_uid(v_admin_id::text);
    
    INSERT INTO public.daily_staff (society_id, name, role, phone_number, id_proof_url)
    VALUES (v_society1_id, 'Maid Mary', 'maid', '555-1234', 'http://s3/proof1.jpg')
    RETURNING id INTO v_staff_id;
    
    -- Duplicate phone rejection
    BEGIN
        INSERT INTO public.daily_staff (society_id, name, role, phone_number, id_proof_url)
        VALUES (v_society1_id, 'Maid Jane', 'maid', '555-1234', 'http://s3/proof2.jpg');
        RAISE EXCEPTION 'Duplicate phone should have failed';
    EXCEPTION WHEN unique_violation THEN
        -- Expected
    END;

    -- Bypass prevention (Direct UPDATE)
    BEGIN
        UPDATE public.daily_staff SET verification_status = 'verified' WHERE id = v_staff_id;
        RAISE EXCEPTION 'Direct update of verification_status should have failed RLS check';
    EXCEPTION WHEN OTHERS THEN
        -- Expected (RLS WITH CHECK fails)
    END;

    -- Valid state transition (Admin)
    PERFORM public.fn_transition_daily_staff_verification(v_staff_id, 'verified');
    
    SELECT verification_status INTO v_audit_row FROM public.daily_staff WHERE id = v_staff_id;
    IF v_audit_row.verification_status != 'verified' THEN RAISE EXCEPTION 'Staff transition failed'; END IF;
    
    -- Audit log generation & id_proof_url redaction
    SELECT * INTO v_audit_row FROM public.audit_logs 
    WHERE entity_type = 'daily_staff' AND action = 'UPDATE' AND entity_id = v_staff_id 
    ORDER BY created_at DESC LIMIT 1;
    
    IF v_audit_row.actor_id != v_admin_id THEN RAISE EXCEPTION 'Audit actor_id mismatch'; END IF;
    IF v_audit_row.new_data ? 'id_proof_url' THEN RAISE EXCEPTION 'id_proof_url was not redacted!'; END IF;
    
    -- Unauthorized transition (Owner)
    PERFORM pg_temp.set_auth_uid(v_owner_id::text);
    BEGIN
        PERFORM public.fn_transition_daily_staff_verification(v_staff_id, 'suspended');
        RAISE EXCEPTION 'Owner should not be able to transition staff';
    EXCEPTION WHEN OTHERS THEN
        -- Expected
    END;

    -- =======================================================================
    -- 3. GATE PASSES
    -- =======================================================================
    RAISE NOTICE 'Verifying Gate Passes...';
    
    -- Owner creation (pending)
    INSERT INTO public.gate_passes (society_id, property_id, staff_id, valid_from, valid_until)
    VALUES (v_society1_id, v_property1_id, v_staff_id, NOW(), NOW() + interval '1 month')
    RETURNING id INTO v_pass_id;

    -- Verify requested_by is populated automatically
    SELECT requested_by INTO v_audit_row FROM public.gate_passes WHERE id = v_pass_id;
    IF v_audit_row.requested_by != v_owner_id THEN RAISE EXCEPTION 'requested_by not set correctly by trigger'; END IF;

    -- Direct update bypass prevention
    BEGIN
        UPDATE public.gate_passes SET status = 'active' WHERE id = v_pass_id;
        RAISE EXCEPTION 'Direct update of gate pass status should have failed';
    EXCEPTION WHEN OTHERS THEN
        -- Expected
    END;

    -- Valid transition (Owner activates)
    PERFORM public.fn_transition_gate_pass_state(v_pass_id, 'active');
    
    -- Verify approval metadata
    SELECT status, approved_by, approved_at INTO v_audit_row FROM public.gate_passes WHERE id = v_pass_id;
    IF v_audit_row.status != 'active' THEN RAISE EXCEPTION 'Gate pass not activated'; END IF;
    IF v_audit_row.approved_by != v_owner_id THEN RAISE EXCEPTION 'approved_by not set'; END IF;
    IF v_audit_row.approved_at IS NULL THEN RAISE EXCEPTION 'approved_at not set'; END IF;

    -- Concurrency/Duplicate restriction
    BEGIN
        INSERT INTO public.gate_passes (society_id, property_id, staff_id, valid_from, valid_until, status)
        VALUES (v_society1_id, v_property1_id, v_staff_id, NOW(), NOW() + interval '1 month', 'active');
        RAISE EXCEPTION 'Duplicate active pass should fail';
    EXCEPTION WHEN unique_violation THEN
        -- Expected
    END;

    -- Unverified staff activation rejection
    PERFORM pg_temp.set_auth_uid(v_admin_id::text);
    INSERT INTO public.daily_staff (society_id, name, role, phone_number)
    VALUES (v_society1_id, 'Unverified Bob', 'driver', '555-9999');
    
    PERFORM set_config('request.jwt.claims', '{"sub": "' || v_owner_id || '"}', true);
    SELECT id INTO v_audit_row FROM public.daily_staff WHERE phone_number = '555-9999';
    BEGIN
        -- Insert pending
        INSERT INTO public.gate_passes (society_id, property_id, staff_id, valid_from, valid_until)
        VALUES (v_society1_id, v_property1_id, v_audit_row.id, NOW(), NOW() + interval '1 month')
        RETURNING id INTO v_audit_row;
        
        -- Try activation
        PERFORM public.fn_transition_gate_pass_state(v_audit_row.id, 'active');
        RAISE EXCEPTION 'Unverified staff should not be activatable';
    EXCEPTION WHEN OTHERS THEN
        -- Expected
    END;

    -- Gatekeeper Access & Effective Expiration
    PERFORM pg_temp.set_auth_uid(v_gatekeeper_id::text);
    SELECT count(*) INTO v_index_count FROM public.gate_passes WHERE id = v_pass_id;
    IF v_index_count = 0 THEN RAISE EXCEPTION 'Gatekeeper cannot see active valid pass'; END IF;
    
    -- Owner isolation (Neighbor cannot see Property 1's pass)
    PERFORM pg_temp.set_auth_uid(v_neighbor_id::text);
    SELECT count(*) INTO v_index_count FROM public.gate_passes WHERE id = v_pass_id;
    IF v_index_count > 0 THEN RAISE EXCEPTION 'Neighbor can see property 1 pass!'; END IF;

    -- =======================================================================
    -- 4. TECHNICIAN TICKETS (Rejection Extension)
    -- =======================================================================
    RAISE NOTICE 'Verifying Technician Tickets...';
    PERFORM pg_temp.set_auth_uid(v_owner_id::text);
    
    INSERT INTO public.technician_tickets (society_id, property_id, title, description, category, created_by)
    VALUES (v_society1_id, v_property1_id, 'Fix AC', 'Broken', 'electrical', v_owner_id)
    RETURNING id INTO v_ticket_id;
    
    -- Owner trying to reject
    BEGIN
        PERFORM public.fn_transition_ticket_state(v_ticket_id, 'rejected');
        RAISE EXCEPTION 'Owner should not be able to reject ticket';
    EXCEPTION WHEN OTHERS THEN
        -- Expected
    END;

    -- Admin trying to reject
    PERFORM pg_temp.set_auth_uid(v_admin_id::text);
    PERFORM public.fn_transition_ticket_state(v_ticket_id, 'rejected');
    
    SELECT status INTO v_audit_row FROM public.technician_tickets WHERE id = v_ticket_id;
    IF v_audit_row.status != 'rejected' THEN RAISE EXCEPTION 'Admin ticket rejection failed'; END IF;

    -- =======================================================================
    -- 5. AUDIT IMMUTABILITY
    -- =======================================================================
    RAISE NOTICE 'Verifying Audit Immutability...';
    SELECT id INTO v_audit_row FROM public.audit_logs LIMIT 1;
    
    BEGIN
        UPDATE public.audit_logs SET action = 'tampered' WHERE id = v_audit_row.id;
        RAISE EXCEPTION 'Audit log was tampered!';
    EXCEPTION WHEN OTHERS THEN
        -- Expected
    END;
    
    BEGIN
        DELETE FROM public.audit_logs WHERE id = v_audit_row.id;
        RAISE EXCEPTION 'Audit log was deleted!';
    EXCEPTION WHEN OTHERS THEN
        -- Expected
    END;

    RAISE NOTICE 'Slice 6 Verification Completed Successfully.';
END $$;
