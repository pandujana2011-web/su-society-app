-- Debug SQL
\set ON_ERROR_STOP on
DO $$ 
DECLARE
    v_soc1 UUID := gen_random_uuid();
    v_admin1 UUID := gen_random_uuid();
    v_gk1 UUID := gen_random_uuid();
BEGIN
    INSERT INTO auth.users (id, email, created_at, updated_at, confirmation_token, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, is_super_admin, role) VALUES 
        (v_admin1, 'a112@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
        (v_gk1, 'gk112@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated');

    INSERT INTO public.users (id, full_name, mobile) VALUES 
        (v_admin1, 'Admin 1', '1111111112'),
        (v_gk1, 'Gatekeeper 1', '9999999991');

    INSERT INTO public.societies (id, name) VALUES 
        (v_soc1, 'Society 1 SOS');

    INSERT INTO public.user_roles (society_id, user_id, role_name, granted_by) VALUES 
        (v_soc1, v_admin1, 'admin', v_admin1),
        (v_soc1, v_gk1, 'gatekeeper', v_admin1);
        
    RAISE NOTICE 'USER ROLES:';
    DECLARE
        r RECORD;
    BEGIN
        FOR r IN (
            SELECT ur.user_id, ur.role_name, u.status 
            FROM public.user_roles ur 
            JOIN public.users u ON u.id = ur.user_id 
            WHERE ur.society_id = v_soc1
        ) LOOP
            RAISE NOTICE 'User: %, Role: %, Status: %', r.user_id, r.role_name, r.status;
        END LOOP;
    END;
END $$;
