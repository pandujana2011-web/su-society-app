-- =============================================================================
-- SU Society App — Robust Client Roles & Seed Provisioning Script
-- Provisions default system users, profiles, and society-scoped roles into Postgres/Supabase
-- =============================================================================

BEGIN;

-- 1. Ensure Extension for password hashing is active
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 2. Provision Default Society Row if missing
INSERT INTO public.societies (id, name, registration_number, address, city, state, pincode, is_active)
VALUES (
    '11111111-1111-1111-1111-111111111111',
    'Green Meadows Residential Welfare Association',
    'RWA/HYD/2026/9876',
    'Green Meadows Road, Gachibowli, Hyderabad, Telangana, 500032',
    'Hyderabad',
    'Telangana',
    '500032',
    TRUE
)
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    registration_number = EXCLUDED.registration_number;

-- 3. Provision Default Roles and Accounts safely with non-null society_id
DO $$
DECLARE
    v_society_id UUID;
    
    -- Fixed UUIDs for default accounts
    v_super_admin_id UUID := 'a0000000-0000-0000-0000-000000000000';
    v_secretary_id   UUID := 'a1111111-1111-1111-1111-111111111111';
    v_treasurer_id   UUID := 'a2222222-2222-2222-2222-222222222222';
    v_owner_id       UUID := 'b1111111-1111-1111-1111-111111111111';
    v_tenant_id      UUID := 'c1111111-1111-1111-1111-111111111111';
    v_security_id    UUID := 'd1111111-1111-1111-1111-111111111111';
    
    v_encrypted_pw TEXT := crypt('password123', gen_salt('bf'));
    v_has_role_name_col BOOLEAN;
BEGIN
    -- Safely retrieve active society_id (guaranteed non-null)
    SELECT COALESCE(
        (SELECT id FROM public.societies WHERE is_active = TRUE LIMIT 1),
        (SELECT id FROM public.societies LIMIT 1),
        '11111111-1111-1111-1111-111111111111'::UUID
    ) INTO v_society_id;

    -- Check user_roles table column structure
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'user_roles' AND column_name = 'role_name'
    ) INTO v_has_role_name_col;

    -- -------------------------------------------------------------------------
    -- 1. SUPER ADMIN: admin@society.com
    -- -------------------------------------------------------------------------
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'auth' AND table_name = 'users') THEN
        INSERT INTO auth.users (
            id, instance_id, email, encrypted_password, email_confirmed_at, 
            raw_app_meta_data, raw_user_meta_data, created_at, updated_at, role, aud
        ) VALUES (
            v_super_admin_id,
            '00000000-0000-0000-0000-000000000000',
            'admin@society.com',
            v_encrypted_pw,
            NOW(),
            '{"provider":"email","providers":["email"]}'::jsonb,
            '{"full_name":"Super Admin","role":"super_admin"}'::jsonb,
            NOW(), NOW(), 'authenticated', 'authenticated'
        ) ON CONFLICT (id) DO UPDATE SET
            email = EXCLUDED.email,
            encrypted_password = EXCLUDED.encrypted_password,
            raw_user_meta_data = EXCLUDED.raw_user_meta_data;
    END IF;

    INSERT INTO public.users (id, full_name, display_name, mobile, status)
    VALUES (v_super_admin_id, 'Super Admin', 'Super Admin', '+919999999901', 'active')
    ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, status = 'active';

    IF v_has_role_name_col THEN
        INSERT INTO public.user_roles (society_id, user_id, role_name, granted_by)
        VALUES 
            (v_society_id, v_super_admin_id, 'super_admin', v_super_admin_id),
            (v_society_id, v_super_admin_id, 'admin', v_super_admin_id)
        ON CONFLICT DO NOTHING;
    ELSE
        INSERT INTO public.user_roles (society_id, user_id, role)
        VALUES 
            (v_society_id, v_super_admin_id, 'super_admin'),
            (v_society_id, v_super_admin_id, 'admin')
        ON CONFLICT DO NOTHING;
    END IF;

    -- -------------------------------------------------------------------------
    -- 2. SECRETARY: secretary@society.com
    -- -------------------------------------------------------------------------
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'auth' AND table_name = 'users') THEN
        INSERT INTO auth.users (
            id, instance_id, email, encrypted_password, email_confirmed_at, 
            raw_app_meta_data, raw_user_meta_data, created_at, updated_at, role, aud
        ) VALUES (
            v_secretary_id,
            '00000000-0000-0000-0000-000000000000',
            'secretary@society.com',
            v_encrypted_pw,
            NOW(),
            '{"provider":"email","providers":["email"]}'::jsonb,
            '{"full_name":"Srinivas Rao (Secretary)","role":"secretary"}'::jsonb,
            NOW(), NOW(), 'authenticated', 'authenticated'
        ) ON CONFLICT (id) DO UPDATE SET
            email = EXCLUDED.email,
            encrypted_password = EXCLUDED.encrypted_password,
            raw_user_meta_data = EXCLUDED.raw_user_meta_data;
    END IF;

    INSERT INTO public.users (id, full_name, display_name, mobile, status)
    VALUES (v_secretary_id, 'Srinivas Rao (Secretary)', 'Secretary', '+919999999902', 'active')
    ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, status = 'active';

    IF v_has_role_name_col THEN
        INSERT INTO public.user_roles (society_id, user_id, role_name, granted_by)
        VALUES 
            (v_society_id, v_secretary_id, 'secretary', v_super_admin_id),
            (v_society_id, v_secretary_id, 'member', v_super_admin_id)
        ON CONFLICT DO NOTHING;
    ELSE
        INSERT INTO public.user_roles (society_id, user_id, role)
        VALUES 
            (v_society_id, v_secretary_id, 'secretary'),
            (v_society_id, v_secretary_id, 'member')
        ON CONFLICT DO NOTHING;
    END IF;

    -- -------------------------------------------------------------------------
    -- 3. TREASURER: treasurer@society.com
    -- -------------------------------------------------------------------------
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'auth' AND table_name = 'users') THEN
        INSERT INTO auth.users (
            id, instance_id, email, encrypted_password, email_confirmed_at, 
            raw_app_meta_data, raw_user_meta_data, created_at, updated_at, role, aud
        ) VALUES (
            v_treasurer_id,
            '00000000-0000-0000-0000-000000000000',
            'treasurer@society.com',
            v_encrypted_pw,
            NOW(),
            '{"provider":"email","providers":["email"]}'::jsonb,
            '{"full_name":"Lakshmi Narayana (Treasurer)","role":"treasurer"}'::jsonb,
            NOW(), NOW(), 'authenticated', 'authenticated'
        ) ON CONFLICT (id) DO UPDATE SET
            email = EXCLUDED.email,
            encrypted_password = EXCLUDED.encrypted_password,
            raw_user_meta_data = EXCLUDED.raw_user_meta_data;
    END IF;

    INSERT INTO public.users (id, full_name, display_name, mobile, status)
    VALUES (v_treasurer_id, 'Lakshmi Narayana (Treasurer)', 'Treasurer', '+919999999903', 'active')
    ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, status = 'active';

    IF v_has_role_name_col THEN
        INSERT INTO public.user_roles (society_id, user_id, role_name, granted_by)
        VALUES 
            (v_society_id, v_treasurer_id, 'treasurer', v_super_admin_id),
            (v_society_id, v_treasurer_id, 'member', v_super_admin_id)
        ON CONFLICT DO NOTHING;
    ELSE
        INSERT INTO public.user_roles (society_id, user_id, role)
        VALUES 
            (v_society_id, v_treasurer_id, 'treasurer'),
            (v_society_id, v_treasurer_id, 'member')
        ON CONFLICT DO NOTHING;
    END IF;

    -- -------------------------------------------------------------------------
    -- 4. OWNER: owner@society.com
    -- -------------------------------------------------------------------------
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'auth' AND table_name = 'users') THEN
        INSERT INTO auth.users (
            id, instance_id, email, encrypted_password, email_confirmed_at, 
            raw_app_meta_data, raw_user_meta_data, created_at, updated_at, role, aud
        ) VALUES (
            v_owner_id,
            '00000000-0000-0000-0000-000000000000',
            'owner@society.com',
            v_encrypted_pw,
            NOW(),
            '{"provider":"email","providers":["email"]}'::jsonb,
            '{"full_name":"Kalyan Reddy (Owner)","role":"member"}'::jsonb,
            NOW(), NOW(), 'authenticated', 'authenticated'
        ) ON CONFLICT (id) DO UPDATE SET
            email = EXCLUDED.email,
            encrypted_password = EXCLUDED.encrypted_password,
            raw_user_meta_data = EXCLUDED.raw_user_meta_data;
    END IF;

    INSERT INTO public.users (id, full_name, display_name, mobile, status)
    VALUES (v_owner_id, 'Kalyan Reddy (Owner)', 'Kalyan Reddy', '+919876543210', 'active')
    ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, status = 'active';

    IF v_has_role_name_col THEN
        INSERT INTO public.user_roles (society_id, user_id, role_name, granted_by)
        VALUES 
            (v_society_id, v_owner_id, 'member', v_super_admin_id)
        ON CONFLICT DO NOTHING;
    ELSE
        INSERT INTO public.user_roles (society_id, user_id, role)
        VALUES 
            (v_society_id, v_owner_id, 'member')
        ON CONFLICT DO NOTHING;
    END IF;

    -- -------------------------------------------------------------------------
    -- 5. TENANT: tenant@society.com
    -- -------------------------------------------------------------------------
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'auth' AND table_name = 'users') THEN
        INSERT INTO auth.users (
            id, instance_id, email, encrypted_password, email_confirmed_at, 
            raw_app_meta_data, raw_user_meta_data, created_at, updated_at, role, aud
        ) VALUES (
            v_tenant_id,
            '00000000-0000-0000-0000-000000000000',
            'tenant@society.com',
            v_encrypted_pw,
            NOW(),
            '{"provider":"email","providers":["email"]}'::jsonb,
            '{"full_name":"Ravi Kumar (Tenant)","role":"tenant"}'::jsonb,
            NOW(), NOW(), 'authenticated', 'authenticated'
        ) ON CONFLICT (id) DO UPDATE SET
            email = EXCLUDED.email,
            encrypted_password = EXCLUDED.encrypted_password,
            raw_user_meta_data = EXCLUDED.raw_user_meta_data;
    END IF;

    INSERT INTO public.users (id, full_name, display_name, mobile, status)
    VALUES (v_tenant_id, 'Ravi Kumar (Tenant)', 'Ravi Kumar', '+918765432100', 'active')
    ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, status = 'active';

    IF v_has_role_name_col THEN
        INSERT INTO public.user_roles (society_id, user_id, role_name, granted_by)
        VALUES 
            (v_society_id, v_tenant_id, 'tenant', v_super_admin_id)
        ON CONFLICT DO NOTHING;
    ELSE
        INSERT INTO public.user_roles (society_id, user_id, role)
        VALUES 
            (v_society_id, v_tenant_id, 'tenant')
        ON CONFLICT DO NOTHING;
    END IF;

    -- -------------------------------------------------------------------------
    -- 6. SECURITY / GATEKEEPER: security@society.com
    -- -------------------------------------------------------------------------
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'auth' AND table_name = 'users') THEN
        INSERT INTO auth.users (
            id, instance_id, email, encrypted_password, email_confirmed_at, 
            raw_app_meta_data, raw_user_meta_data, created_at, updated_at, role, aud
        ) VALUES (
            v_security_id,
            '00000000-0000-0000-0000-000000000000',
            'security@society.com',
            v_encrypted_pw,
            NOW(),
            '{"provider":"email","providers":["email"]}'::jsonb,
            '{"full_name":"Ramaiah (Security)","role":"gatekeeper"}'::jsonb,
            NOW(), NOW(), 'authenticated', 'authenticated'
        ) ON CONFLICT (id) DO UPDATE SET
            email = EXCLUDED.email,
            encrypted_password = EXCLUDED.encrypted_password,
            raw_user_meta_data = EXCLUDED.raw_user_meta_data;
    END IF;

    INSERT INTO public.users (id, full_name, display_name, mobile, status)
    VALUES (v_security_id, 'Ramaiah (Security)', 'Ramaiah', '+919876543213', 'active')
    ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, status = 'active';

    IF v_has_role_name_col THEN
        INSERT INTO public.user_roles (society_id, user_id, role_name, granted_by)
        VALUES 
            (v_society_id, v_security_id, 'gatekeeper', v_super_admin_id)
        ON CONFLICT DO NOTHING;
    ELSE
        INSERT INTO public.user_roles (society_id, user_id, role)
        VALUES 
            (v_society_id, v_security_id, 'gatekeeper')
        ON CONFLICT DO NOTHING;
    END IF;

END $$;

COMMIT;
