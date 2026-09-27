DO $$
DECLARE
    u_super_admin UUID := gen_random_uuid();
    u_soc2_member UUID := gen_random_uuid();
    soc1_id UUID := gen_random_uuid();
    soc2_id UUID := gen_random_uuid();
    p45_id UUID := gen_random_uuid();
    soc2_villa_id UUID := gen_random_uuid();
    v_move_req_id UUID;
    v_is_owner BOOLEAN;
    v_is_tenant BOOLEAN;
    v_is_admin BOOLEAN;
    v_soc UUID;
BEGIN
    INSERT INTO public.societies (id, name, registration_number, address) VALUES 
        (soc1_id, 'Greenwood Estate', 'REG-S8A', 'Address A'),
        (soc2_id, 'Silver Oaks', 'REG-S8B', 'Address B');
        
    INSERT INTO auth.users (id, email) VALUES 
        (u_super_admin, 'admin@soc8.com'),
        (u_soc2_member, 'member@soc8b.com');

    INSERT INTO public.users (id, full_name, status) VALUES 
        (u_super_admin, 'Admin', 'active'), 
        (u_soc2_member, 'Soc 2 Member', 'active');

    INSERT INTO public.user_roles (user_id, society_id, role_name, granted_by) VALUES 
        (u_super_admin, soc1_id, 'super_admin', u_super_admin),
        (u_soc2_member, soc2_id, 'member', u_soc2_member);

    INSERT INTO public.properties (id, society_id, plot_number, created_by) VALUES 
        (p45_id, soc1_id, 'Plot-45', u_super_admin),
        (soc2_villa_id, soc2_id, 'Villa-1', u_soc2_member);
        
    INSERT INTO public.property_owners (property_id, owner_id, is_primary_owner, ownership_share_pct, created_by) VALUES 
        (soc2_villa_id, u_soc2_member, true, 100, u_soc2_member);

    PERFORM set_config('request.jwt.claims', json_build_object('sub', u_super_admin::text, 'role', 'authenticated')::text, TRUE);
    PERFORM set_config('request.jwt.claim.sub', u_super_admin::text, TRUE);

    INSERT INTO public.move_requests (society_id, property_id, request_type, primary_user_id, proposed_date, created_by)
    VALUES (soc1_id, p45_id, 'move_in', u_super_admin, CURRENT_DATE + 5, u_super_admin)
    RETURNING id INTO v_move_req_id;

    PERFORM set_config('request.jwt.claims', json_build_object('sub', u_soc2_member::text, 'role', 'authenticated')::text, TRUE);
    PERFORM set_config('request.jwt.claim.sub', u_soc2_member::text, TRUE);

    v_is_owner := public.is_property_owner(u_soc2_member, p45_id);
    v_is_tenant := public.is_property_tenant(u_soc2_member, p45_id);
    v_is_admin := public.is_admin();
    v_soc := public.get_user_society_id(u_soc2_member);
    
    RAISE NOTICE 'is_owner: %', v_is_owner;
    RAISE NOTICE 'is_tenant: %', v_is_tenant;
    RAISE NOTICE 'is_admin: %', v_is_admin;
    RAISE NOTICE 'auth.uid: %', auth.uid();
    RAISE NOTICE 'u_soc2_member: %', u_soc2_member;
    RAISE NOTICE 'v_soc: %', v_soc;
    
    IF EXISTS (SELECT 1 FROM public.move_requests WHERE id = v_move_req_id) THEN
        RAISE EXCEPTION 'Cross-society move request SELECT isolation failed';
    END IF;
END $$;
