DO $$
DECLARE
    u_super_admin UUID := gen_random_uuid();
    u_kalyan      UUID := gen_random_uuid(); 
    soc1_id UUID := gen_random_uuid();
    p45_id UUID := gen_random_uuid();
    v_move_req_id UUID;
    v_updated_rows INTEGER;
BEGIN
    INSERT INTO public.societies (id, name, registration_number, address) VALUES (soc1_id, 'Test Society ' || gen_random_uuid()::text, 'REG-' || gen_random_uuid()::text, 'Address A');
    INSERT INTO auth.users (id, email) VALUES (u_super_admin, gen_random_uuid()::text || '@test.com'), (u_kalyan, gen_random_uuid()::text || '@test.com');
    INSERT INTO public.users (id, full_name, status) VALUES (u_super_admin, 'Admin', 'active'), (u_kalyan, 'Kalyan', 'active');
    INSERT INTO public.user_roles (user_id, society_id, role_name, granted_by) VALUES (u_super_admin, soc1_id, 'super_admin', u_super_admin), (u_kalyan, soc1_id, 'member', u_super_admin);
    INSERT INTO public.properties (id, society_id, plot_number, created_by) VALUES (p45_id, soc1_id, 'Plot-' || gen_random_uuid()::text, u_super_admin);
    INSERT INTO public.property_owners (property_id, owner_id, is_primary_owner, ownership_share_pct, created_by) VALUES (p45_id, u_kalyan, true, 100, u_super_admin);
    
    INSERT INTO public.move_requests (society_id, property_id, request_type, primary_user_id, proposed_date, created_by)
    VALUES (soc1_id, p45_id, 'move_in', u_kalyan, CURRENT_DATE + 5, u_kalyan)
    RETURNING id INTO v_move_req_id;

    -- Test superuser update direct (RLS bypassed). Will the trigger block it? 
    -- current_query() contains the entire DO block, including the string 'fn_transition_move_request_state'.
    UPDATE public.move_requests SET status = 'approved' WHERE id = v_move_req_id;
    GET DIAGNOSTICS v_updated_rows = ROW_COUNT;
    RAISE NOTICE 'Superuser direct UPDATE with trigger bypass rows affected: %', v_updated_rows;

END $$;
