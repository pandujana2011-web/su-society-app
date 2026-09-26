-- =============================================================================
-- SU Society App — Slice 1 Live Verification Suite
-- Runs against local Supabase PostgreSQL (port 54322)
-- =============================================================================
-- Run order:
--   psql $DB_URL -f database/verify_slice1.sql
--
-- Every test prints:  PASS: <description>
--            or:      FAIL: <description> — <detail>
-- A final summary counts pass/fail.
-- =============================================================================

\set ON_ERROR_STOP on
\timing on

BEGIN;

-- Helper: counted result tracking
CREATE TEMP TABLE IF NOT EXISTS _test_results (
    seq        SERIAL,
    result     TEXT NOT NULL,   -- 'PASS' or 'FAIL'
    category   TEXT NOT NULL,
    description TEXT NOT NULL,
    detail     TEXT
);
GRANT ALL ON _test_results TO PUBLIC;
GRANT ALL ON SEQUENCE _test_results_seq_seq TO PUBLIC;

-- Macro to assert a boolean condition
CREATE OR REPLACE FUNCTION pg_temp.assert(
    p_condition BOOLEAN,
    p_category  TEXT,
    p_desc      TEXT,
    p_detail    TEXT DEFAULT NULL
) RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    IF p_condition THEN
        INSERT INTO _test_results(result, category, description)
            VALUES ('PASS', p_category, p_desc);
        RAISE NOTICE 'PASS [%]: %', p_category, p_desc;
    ELSE
        INSERT INTO _test_results(result, category, description, detail)
            VALUES ('FAIL', p_category, p_desc, COALESCE(p_detail, 'condition was FALSE'));
        RAISE WARNING 'FAIL [%]: % — %', p_category, p_desc, COALESCE(p_detail,'');
    END IF;
END;
$$;

-- Macro to assert that a block raises an exception containing the expected text
CREATE OR REPLACE FUNCTION pg_temp.assert_raises(
    p_category  TEXT,
    p_desc      TEXT,
    p_sql       TEXT,
    p_expected_msg TEXT DEFAULT NULL
) RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
    v_err TEXT;
BEGIN
    BEGIN
        EXECUTE p_sql;
        -- If we reach here, no exception was raised — that is the failure
        INSERT INTO _test_results(result, category, description, detail)
            VALUES ('FAIL', p_category, p_desc, 'Expected exception was NOT raised');
        RAISE WARNING 'FAIL [%]: % — expected exception not raised', p_category, p_desc;
        RETURN;
    EXCEPTION WHEN OTHERS THEN
        v_err := SQLERRM;
    END;
    IF p_expected_msg IS NULL OR v_err ILIKE ('%' || p_expected_msg || '%') THEN
        INSERT INTO _test_results(result, category, description)
            VALUES ('PASS', p_category, p_desc);
        RAISE NOTICE 'PASS [%]: % (exception: %)', p_category, p_desc, v_err;
    ELSE
        INSERT INTO _test_results(result, category, description, detail)
            VALUES ('FAIL', p_category, p_desc,
                    'Exception raised but message mismatch. Got: ' || v_err);
        RAISE WARNING 'FAIL [%]: % — message mismatch. Got: %', p_category, p_desc, v_err;
    END IF;
END;
$$;

\echo ''
\echo '================================================================'
\echo 'SECTION 1 — SCHEMA OBJECT EXISTENCE'
\echo '================================================================'

-- 1.1 All 10 tables exist
DO $$ DECLARE
    expected_tables TEXT[] := ARRAY[
        'societies','users','user_roles','audit_logs','properties','units',
        'property_owners','association_memberships','tenancies','occupants'
    ];
    t TEXT;
    exists_flag BOOLEAN;
BEGIN
    FOREACH t IN ARRAY expected_tables LOOP
        SELECT EXISTS (
            SELECT 1 FROM information_schema.tables
            WHERE table_schema = 'public' AND table_name = t
        ) INTO exists_flag;
        PERFORM pg_temp.assert(exists_flag, 'SCHEMA', 'Table exists: public.' || t);
    END LOOP;
END $$;

-- 1.2 All 12 functions exist
DO $$ DECLARE
    expected_fns TEXT[] := ARRAY[
        'set_updated_at',
        'is_admin',
        'has_role',
        'get_user_society_id',
        'is_property_owner',
        'is_property_tenant',
        'prevent_audit_log_mutations',
        'validate_ownership_share_total',
        'validate_single_primary_owner',
        'prevent_role_name_update',
        'validate_tenancy_unit_property_match',
        'validate_role_revocation'
    ];
    fn TEXT;
    exists_flag BOOLEAN;
BEGIN
    FOREACH fn IN ARRAY expected_fns LOOP
        SELECT EXISTS (
            SELECT 1 FROM pg_proc
            WHERE pronamespace = 'public'::regnamespace
              AND proname = fn
        ) INTO exists_flag;
        PERFORM pg_temp.assert(exists_flag, 'SCHEMA', 'Function exists: public.' || fn || '()');
    END LOOP;
END $$;

-- 1.3 All functions are SECURITY DEFINER
DO $$ DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT proname FROM pg_proc
        WHERE pronamespace = 'public'::regnamespace
          AND proname IN (
            'set_updated_at','is_admin','has_role','get_user_society_id',
            'is_property_owner','is_property_tenant',
            'prevent_audit_log_mutations','validate_ownership_share_total',
            'validate_single_primary_owner','prevent_role_name_update',
            'validate_tenancy_unit_property_match','validate_role_revocation'
          )
          AND NOT prosecdef   -- prosecdef = TRUE means SECURITY DEFINER
    LOOP
        PERFORM pg_temp.assert(FALSE, 'SECURITY',
            'Function is SECURITY DEFINER: ' || r.proname,
            r.proname || ' is NOT SECURITY DEFINER');
    END LOOP;
    -- If loop body never executed, all are SECURITY DEFINER — record pass
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc
        WHERE pronamespace = 'public'::regnamespace
          AND proname IN (
            'set_updated_at','is_admin','has_role','get_user_society_id',
            'is_property_owner','is_property_tenant',
            'prevent_audit_log_mutations','validate_ownership_share_total',
            'validate_single_primary_owner','prevent_role_name_update',
            'validate_tenancy_unit_property_match','validate_role_revocation'
          )
          AND NOT prosecdef
    ) THEN
        PERFORM pg_temp.assert(TRUE, 'SECURITY', 'All 12 functions are SECURITY DEFINER');
    END IF;
END $$;

-- 1.4 search_path locked on all functions (proconfig contains 'search_path=public,pg_temp' or similar)
DO $$ DECLARE
    r RECORD;
    bad_count INT := 0;
BEGIN
    FOR r IN
        SELECT proname, proconfig FROM pg_proc
        WHERE pronamespace = 'public'::regnamespace
          AND proname IN (
            'set_updated_at','is_admin','has_role','get_user_society_id',
            'is_property_owner','is_property_tenant',
            'prevent_audit_log_mutations','validate_ownership_share_total',
            'validate_single_primary_owner','prevent_role_name_update',
            'validate_tenancy_unit_property_match','validate_role_revocation'
          )
    LOOP
        IF r.proconfig IS NULL OR NOT EXISTS (
            SELECT 1 FROM unnest(r.proconfig) c WHERE c ILIKE 'search_path=%'
        ) THEN
            bad_count := bad_count + 1;
            PERFORM pg_temp.assert(FALSE, 'SECURITY',
                'Function has locked search_path: ' || r.proname,
                r.proname || ' has no search_path in proconfig');
        END IF;
    END LOOP;
    IF bad_count = 0 THEN
        PERFORM pg_temp.assert(TRUE, 'SECURITY', 'All 12 functions have locked search_path');
    END IF;
END $$;

-- 1.5 RLS enabled AND forced on all 10 tables
DO $$ DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT c.relname AS tablename, c.relrowsecurity AS rowsecurity, c.relforcerowsecurity AS forcerowsecurity
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public'
          AND c.relname IN (
            'societies','users','user_roles','audit_logs','properties','units',
            'property_owners','association_memberships','tenancies','occupants'
          )
    LOOP
        PERFORM pg_temp.assert(r.rowsecurity, 'RLS',
            'RLS enabled: ' || r.tablename, 'rowsecurity=FALSE');
        PERFORM pg_temp.assert(r.forcerowsecurity, 'RLS',
            'RLS forced: ' || r.tablename, 'forcerowsecurity=FALSE');
    END LOOP;
END $$;

-- 1.6 Exclusion constraints on temporal tables
DO $$ DECLARE
    expected_excl TEXT[] := ARRAY[
        'excl_owner_no_overlap',
        'excl_membership_no_overlap',
        'excl_unit_tenancy_no_overlap'
    ];
    c TEXT;
    exists_flag BOOLEAN;
BEGIN
    FOREACH c IN ARRAY expected_excl LOOP
        SELECT EXISTS (
            SELECT 1 FROM pg_constraint WHERE conname = c AND contype = 'x'
        ) INTO exists_flag;
        PERFORM pg_temp.assert(exists_flag, 'SCHEMA', 'Exclusion constraint exists: ' || c);
    END LOOP;
END $$;

-- 1.7 unit_id is nullable in tenancies and occupants
DO $$ DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT table_name, is_nullable FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name IN ('tenancies','occupants')
          AND column_name = 'unit_id'
    LOOP
        PERFORM pg_temp.assert(
            r.is_nullable = 'YES',
            'NULLABLE_UNIT',
            'unit_id is nullable in ' || r.table_name,
            'is_nullable = ' || r.is_nullable
        );
    END LOOP;
END $$;

-- 1.8 audit_logs immutability trigger exists
SELECT pg_temp.assert(
    EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_audit_logs_immutable'
            AND tgrelid = 'public.audit_logs'::regclass),
    'SCHEMA', 'Trigger exists: trg_audit_logs_immutable on audit_logs'
);

-- 1.9 btree_gist extension loaded
SELECT pg_temp.assert(
    EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'btree_gist'),
    'SCHEMA', 'Extension btree_gist is installed'
);

\echo ''
\echo '================================================================'
\echo 'SECTION 2 — SEED DATA SETUP (service-role, bypasses RLS)'
\echo '================================================================'

-- Create one society
INSERT INTO public.societies (id, name, registration_number, city, state, pincode,
                               contact_email, is_active)
VALUES (
    'aaaaaaaa-0000-0000-0000-000000000001',
    'Green Valley Cooperative Housing Society',
    'REG-MH-2019-001',
    'Pune', 'Maharashtra', '411001',
    'admin@greenvalley.example', TRUE
);

-- Create a second society (for cross-society isolation tests)
INSERT INTO public.societies (id, name, is_active)
VALUES (
    'bbbbbbbb-0000-0000-0000-000000000002',
    'Blue Ridge Society (OTHER)',
    TRUE
);

-- NOTE: auth.users rows are needed for users.id FK.
-- In local Supabase, we insert via auth.users directly (service role).
-- UUIDs are fixed for reproducibility.
INSERT INTO auth.users (id, email, created_at, updated_at, confirmation_token,
                        email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                        is_super_admin, role)
VALUES
  ('a1111111-0000-0000-0000-000000000001', 'superadmin@test.local',     NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
  ('a2222222-0000-0000-0000-000000000002', 'secretary@test.local',      NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
  ('a3333333-0000-0000-0000-000000000003', 'treasurer@test.local',      NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
  ('a4444444-0000-0000-0000-000000000004', 'executive@test.local',      NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
  ('a5555555-0000-0000-0000-000000000005', 'owner_kalyan@test.local',   NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
  ('a6666666-0000-0000-0000-000000000006', 'owner_priya@test.local',    NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
  ('a7777777-0000-0000-0000-000000000007', 'tenant_ravi@test.local',    NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
  ('a8888888-0000-0000-0000-000000000008', 'unrelated@test.local',      NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
  ('a9999999-0000-0000-0000-000000000009', 'other_society@test.local',  NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated')
ON CONFLICT (id) DO NOTHING;

-- Public user profiles
INSERT INTO public.users (id, full_name, mobile, status) VALUES
  ('a1111111-0000-0000-0000-000000000001', 'Super Admin',        '+919000000001', 'active'),
  ('a2222222-0000-0000-0000-000000000002', 'Kavita (Secretary)', '+919000000002', 'active'),
  ('a3333333-0000-0000-0000-000000000003', 'Mohan (Treasurer)',  '+919000000003', 'active'),
  ('a4444444-0000-0000-0000-000000000004', 'Deepa (Executive)',  '+919000000004', 'active'),
  ('a5555555-0000-0000-0000-000000000005', 'Kalyan (Owner)',     '+919000000005', 'active'),
  ('a6666666-0000-0000-0000-000000000006', 'Priya (Co-Owner)',   '+919000000006', 'active'),
  ('a7777777-0000-0000-0000-000000000007', 'Ravi (Tenant)',      '+919000000007', 'active'),
  ('a8888888-0000-0000-0000-000000000008', 'Unrelated User',     '+919000000008', 'active'),
  ('a9999999-0000-0000-0000-000000000009', 'Other Society User', '+919000000009', 'active');

-- Role assignments — society 1
INSERT INTO public.user_roles (society_id, user_id, role_name, granted_on, granted_by) VALUES
  ('aaaaaaaa-0000-0000-0000-000000000001', 'a1111111-0000-0000-0000-000000000001', 'super_admin',      '2024-01-01', 'a1111111-0000-0000-0000-000000000001'),
  ('aaaaaaaa-0000-0000-0000-000000000001', 'a2222222-0000-0000-0000-000000000002', 'secretary',        '2024-01-01', 'a1111111-0000-0000-0000-000000000001'),
  ('aaaaaaaa-0000-0000-0000-000000000001', 'a2222222-0000-0000-0000-000000000002', 'member',           '2024-01-01', 'a1111111-0000-0000-0000-000000000001'),
  ('aaaaaaaa-0000-0000-0000-000000000001', 'a3333333-0000-0000-0000-000000000003', 'treasurer',        '2024-01-01', 'a1111111-0000-0000-0000-000000000001'),
  ('aaaaaaaa-0000-0000-0000-000000000001', 'a3333333-0000-0000-0000-000000000003', 'member',           '2024-01-01', 'a1111111-0000-0000-0000-000000000001'),
  ('aaaaaaaa-0000-0000-0000-000000000001', 'a4444444-0000-0000-0000-000000000004', 'executive_member', '2024-01-01', 'a1111111-0000-0000-0000-000000000001'),
  ('aaaaaaaa-0000-0000-0000-000000000001', 'a5555555-0000-0000-0000-000000000005', 'member',           '2024-01-01', 'a1111111-0000-0000-0000-000000000001'),
  ('aaaaaaaa-0000-0000-0000-000000000001', 'a6666666-0000-0000-0000-000000000006', 'member',           '2024-01-01', 'a1111111-0000-0000-0000-000000000001'),
  ('aaaaaaaa-0000-0000-0000-000000000001', 'a7777777-0000-0000-0000-000000000007', 'tenant',           '2024-01-01', 'a1111111-0000-0000-0000-000000000001'),
  ('aaaaaaaa-0000-0000-0000-000000000001', 'a8888888-0000-0000-0000-000000000008', 'member',           '2024-01-01', 'a1111111-0000-0000-0000-000000000001');

-- Role for other society user (in society 2 only)
INSERT INTO public.user_roles (society_id, user_id, role_name, granted_on, granted_by) VALUES
  ('bbbbbbbb-0000-0000-0000-000000000002', 'a9999999-0000-0000-0000-000000000009', 'member', '2024-01-01', 'a9999999-0000-0000-0000-000000000009');

-- Properties in society 1
INSERT INTO public.properties (id, society_id, plot_number, construction_status,
                                property_type, occupancy_status, created_by) VALUES
  ('b1111001-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
   'Plot-45', 'constructed', 'residential', 'owner_occupied',
   'a1111111-0000-0000-0000-000000000001'),
  ('b1111002-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001',
   'Plot-46', 'constructed', 'residential', 'tenant_occupied',
   'a1111111-0000-0000-0000-000000000001'),
  ('b1111003-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000001',
   'Plot-47', 'vacant_plot', 'residential', 'vacant',
   'a1111111-0000-0000-0000-000000000001');

-- A property in society 2 (for cross-society tests)
INSERT INTO public.properties (id, society_id, plot_number, construction_status,
                                property_type, occupancy_status, created_by) VALUES
  ('b1111099-0000-0000-0000-000000000099', 'bbbbbbbb-0000-0000-0000-000000000002',
   'Plot-1', 'constructed', 'residential', 'owner_occupied',
   'a9999999-0000-0000-0000-000000000009');

-- Units (Plot-46 has a unit; Plot-45 has none — property-level)
INSERT INTO public.units (id, property_id, unit_identifier, created_by) VALUES
  ('f1110001-0000-0000-0000-000000000001', 'b1111002-0000-0000-0000-000000000002',
   'Ground Floor', 'a1111111-0000-0000-0000-000000000001');

-- Property ownership (Plot-45 owned by Kalyan+Priya co-owners; Plot-46 by Kalyan)
INSERT INTO public.property_owners (id, property_id, owner_id, ownership_share_pct,
                                     is_primary_owner, start_date, created_by) VALUES
  ('e1111001-0000-0000-0000-000000000001', 'b1111001-0000-0000-0000-000000000001',
   'a5555555-0000-0000-0000-000000000005', 60.00, TRUE,  '2023-01-01',
   'a1111111-0000-0000-0000-000000000001'),
  ('e1111002-0000-0000-0000-000000000002', 'b1111001-0000-0000-0000-000000000001',
   'a6666666-0000-0000-0000-000000000006', 40.00, FALSE, '2023-01-01',
   'a1111111-0000-0000-0000-000000000001'),
  ('e1111003-0000-0000-0000-000000000003', 'b1111002-0000-0000-0000-000000000002',
   'a5555555-0000-0000-0000-000000000005', 100.00, TRUE, '2023-01-01',
   'a1111111-0000-0000-0000-000000000001');

-- Association memberships (one per property — [AD-1])
INSERT INTO public.association_memberships (id, society_id, property_id, user_id,
                                             membership_number, membership_status,
                                             start_date, created_by) VALUES
  ('d1111001-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
   'b1111001-0000-0000-0000-000000000001',
   'a5555555-0000-0000-0000-000000000005',  -- Kalyan holds vote for Plot-45
   'MEM-001', 'active', '2024-01-01', 'a1111111-0000-0000-0000-000000000001'),
  ('d1111002-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001',
   'b1111002-0000-0000-0000-000000000002',
   'a5555555-0000-0000-0000-000000000005',  -- Kalyan holds vote for Plot-46
   'MEM-002', 'active', '2024-01-01', 'a1111111-0000-0000-0000-000000000001');

-- Tenancy on Plot-46 unit (unit_id NOT NULL)
INSERT INTO public.tenancies (id, society_id, property_id, unit_id, tenant_id,
                               monthly_rent, start_date, created_by) VALUES
  ('c1111001-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
   'b1111002-0000-0000-0000-000000000002',
   'f1110001-0000-0000-0000-000000000001',
   'a7777777-0000-0000-0000-000000000007',
   15000.00, '2025-01-01', 'a1111111-0000-0000-0000-000000000001');

-- Seed complete
SELECT pg_temp.assert(TRUE, 'SEED', 'Seed data inserted successfully');

\echo ''
\echo '================================================================'
\echo 'SECTION 3 — TEMPORAL INTEGRITY: OWNERSHIP OVERLAP PREVENTION'
\echo '================================================================'

-- 3.1 Overlapping ownership for same owner+property must be rejected
SELECT pg_temp.assert_raises(
    'TEMPORAL', 'Overlapping ownership period is rejected (same owner, same property)',
    $$INSERT INTO public.property_owners
        (property_id, owner_id, ownership_share_pct, is_primary_owner, start_date, end_date, created_by)
      VALUES (
        'b1111001-0000-0000-0000-000000000001',
        'a5555555-0000-0000-0000-000000000005',
        10.00, FALSE,
        '2022-06-01', '2024-01-01',  -- overlaps the 2023-01-01→open record
        'a1111111-0000-0000-0000-000000000001'
      )$$,
    'overlap'
);

-- 3.2 Non-overlapping historical ownership is accepted
INSERT INTO public.property_owners
    (property_id, owner_id, ownership_share_pct, is_primary_owner, start_date, end_date, created_by)
VALUES (
    'b1111003-0000-0000-0000-000000000003',  -- vacant plot
    'a8888888-0000-0000-0000-000000000008',
    100.00, TRUE,
    '2020-01-01', '2022-12-31',
    'a1111111-0000-0000-0000-000000000001'
);
SELECT pg_temp.assert(TRUE, 'TEMPORAL', 'Historical (non-overlapping) ownership accepted');

-- 3.3 Ownership share > 100% total is rejected
SELECT pg_temp.assert_raises(
    'TEMPORAL', 'Ownership share exceeding 100% is rejected',
    $$INSERT INTO public.property_owners
        (property_id, owner_id, ownership_share_pct, is_primary_owner, start_date, created_by)
      VALUES (
        'b1111001-0000-0000-0000-000000000001',
        'a8888888-0000-0000-0000-000000000008',
        50.00, FALSE,  -- 60+40+50 = 150% — must be rejected
        '2024-01-01',
        'a1111111-0000-0000-0000-000000000001'
      )$$,
    'share'
);

-- 3.4 Two active primary owners for same property rejected
SELECT pg_temp.assert_raises(
    'TEMPORAL', 'Second active primary owner on same property is rejected',
    $$
      UPDATE public.property_owners SET ownership_share_pct = 99.00 WHERE property_id = 'b1111002-0000-0000-0000-000000000002' AND end_date IS NULL;
      INSERT INTO public.property_owners
        (property_id, owner_id, ownership_share_pct, is_primary_owner, start_date, created_by)
      VALUES (
        'b1111002-0000-0000-0000-000000000002',
        'a6666666-0000-0000-0000-000000000006',
        0.01, TRUE,  -- is_primary_owner conflicts
        '2025-01-01',
        'a1111111-0000-0000-0000-000000000001'
      )$$,
    'primary'
);

\echo ''
\echo '================================================================'
\echo 'SECTION 4 — TEMPORAL INTEGRITY: ASSOCIATION MEMBERSHIP'
\echo '================================================================'

-- 4.1 One-vote-per-property: second ACTIVE membership for same property rejected
SELECT pg_temp.assert_raises(
    'VOTING', '[AD-1] Second active membership for same property is rejected',
    $$INSERT INTO public.association_memberships
        (society_id, property_id, user_id, membership_status, start_date, created_by)
      VALUES (
        'aaaaaaaa-0000-0000-0000-000000000001',
        'b1111001-0000-0000-0000-000000000001',  -- already has active membership
        'a6666666-0000-0000-0000-000000000006',  -- Priya tries to also get membership
        'active', '2025-01-01',
        'a1111111-0000-0000-0000-000000000001'
      )$$,
    NULL -- unique index violation
);

-- 4.2 After ending an old membership, a new one is accepted (temporal transfer)
-- First, close the existing membership for Plot-45
UPDATE public.association_memberships
   SET end_date = '2025-12-31', end_recorded_by = 'a1111111-0000-0000-0000-000000000001'
 WHERE id = 'd1111001-0000-0000-0000-000000000001';

-- Now a new membership can be started
INSERT INTO public.association_memberships
    (society_id, property_id, user_id, membership_status, start_date, created_by)
VALUES (
    'aaaaaaaa-0000-0000-0000-000000000001',
    'b1111001-0000-0000-0000-000000000001',
    'a6666666-0000-0000-0000-000000000006',  -- Priya takes over the vote
    'active', '2026-01-01',
    'a1111111-0000-0000-0000-000000000001'
);
SELECT pg_temp.assert(TRUE, 'VOTING',
    '[AD-1] New membership accepted after old one ended (temporal transfer of voting right)');

-- 4.3 Overlapping membership periods for same property are rejected
SELECT pg_temp.assert_raises(
    'VOTING', 'Overlapping membership periods for same property rejected',
    $$INSERT INTO public.association_memberships
        (society_id, property_id, user_id, membership_status, start_date, end_date, created_by)
      VALUES (
        'aaaaaaaa-0000-0000-0000-000000000001',
        'b1111001-0000-0000-0000-000000000001',
        'a8888888-0000-0000-0000-000000000008',
        'active', '2025-06-01', '2026-06-01',  -- overlaps both the ended and new records
        'a1111111-0000-0000-0000-000000000001'
      )$$,
    NULL  -- exclusion constraint violation
);

\echo ''
\echo '================================================================'
\echo 'SECTION 5 — TEMPORAL INTEGRITY: TENANCY OVERLAP'
\echo '================================================================'

-- 5.1 Second active tenancy for same unit rejected
SELECT pg_temp.assert_raises(
    'TEMPORAL', 'Second active tenancy for same unit is rejected',
    $$INSERT INTO public.tenancies
        (society_id, property_id, unit_id, tenant_id, start_date, created_by)
      VALUES (
        'aaaaaaaa-0000-0000-0000-000000000001',
        'b1111002-0000-0000-0000-000000000002',
        'f1110001-0000-0000-0000-000000000001',  -- same unit, already tenanted
        'a8888888-0000-0000-0000-000000000008',
        '2025-06-01',
        'a1111111-0000-0000-0000-000000000001'
      )$$,
    NULL  -- unique or exclusion constraint
);

-- 5.2 unit_id from wrong property is rejected (cross-property FK check)
SELECT pg_temp.assert_raises(
    'NULLABLE_UNIT', 'unit_id from wrong property rejected by trigger',
    $$INSERT INTO public.tenancies
        (society_id, property_id, unit_id, tenant_id, start_date, created_by)
      VALUES (
        'aaaaaaaa-0000-0000-0000-000000000001',
        'b1111001-0000-0000-0000-000000000001',   -- Plot-45 (no units)
        'f1110001-0000-0000-0000-000000000001',   -- unit belongs to Plot-46 ← WRONG
        'a8888888-0000-0000-0000-000000000008',
        '2025-01-01',
        'a1111111-0000-0000-0000-000000000001'
      )$$,
    'does not belong'
);

-- 5.3 Property-level tenancy (unit_id = NULL) is accepted
INSERT INTO public.tenancies
    (id, society_id, property_id, unit_id, tenant_id, start_date, created_by)
VALUES (
    'c1111002-0000-0000-0000-000000000002',
    'aaaaaaaa-0000-0000-0000-000000000001',
    'b1111003-0000-0000-0000-000000000003',  -- vacant plot, no units
    NULL,                                     -- [AD-2] property-level tenancy
    'a8888888-0000-0000-0000-000000000008',
    '2025-01-01',
    'a1111111-0000-0000-0000-000000000001'
);
SELECT pg_temp.assert(TRUE, 'NULLABLE_UNIT',
    '[AD-2] Property-level tenancy (unit_id = NULL) accepted');

-- 5.4 Property-level occupancy (unit_id = NULL) is accepted
INSERT INTO public.occupants
    (id, society_id, property_id, unit_id, tenancy_id, full_name, relationship, start_date, created_by)
VALUES (
    'e2222001-0000-0000-0000-000000000001',
    'aaaaaaaa-0000-0000-0000-000000000001',
    'b1111003-0000-0000-0000-000000000003',
    NULL,                                     -- [AD-2] property-level
    'c1111002-0000-0000-0000-000000000002',
    'Ramesh Kumar', 'self', '2025-01-01',
    'a1111111-0000-0000-0000-000000000001'
);
SELECT pg_temp.assert(TRUE, 'NULLABLE_UNIT',
    '[AD-2] Property-level occupant (unit_id = NULL) accepted');

\echo ''
\echo '================================================================'
\echo 'SECTION 6 — AUDIT LOG IMMUTABILITY'
\echo '================================================================'

-- 6.1 Insert an audit log entry (allowed)
INSERT INTO public.audit_logs (society_id, actor_id, action, entity_type, entity_id)
VALUES (
    'aaaaaaaa-0000-0000-0000-000000000001',
    'a1111111-0000-0000-0000-000000000001',
    'Test audit entry',
    'properties',
    'b1111001-0000-0000-0000-000000000001'
);
SELECT pg_temp.assert(TRUE, 'AUDIT', 'Audit log entry can be inserted');

-- 6.2 Update is blocked
SELECT pg_temp.assert_raises(
    'AUDIT', 'audit_logs UPDATE is rejected (immutable)',
    $$UPDATE public.audit_logs SET action = 'tampered' WHERE action = 'Test audit entry'$$,
    'immutable'
);

-- 6.3 Delete is blocked
SELECT pg_temp.assert_raises(
    'AUDIT', 'audit_logs DELETE is rejected (immutable)',
    $$DELETE FROM public.audit_logs WHERE action = 'Test audit entry'$$,
    'immutable'
);

\echo ''
\echo '================================================================'
\echo 'SECTION 7 — ROLE INTEGRITY: PREVENT ROLE_NAME DIRECT UPDATE'
\echo '================================================================'

-- 7.1 Direct change of role_name is rejected
SELECT pg_temp.assert_raises(
    'ROLE_INTEGRITY', 'Direct role_name UPDATE is rejected (must use new row)',
    $$UPDATE public.user_roles
        SET role_name = 'super_admin'
      WHERE user_id = 'a7777777-0000-0000-0000-000000000007'
        AND role_name = 'tenant'$$,
    'not permitted'
);

-- 7.2 Setting revoked_on is allowed (normal revocation)
UPDATE public.user_roles
   SET revoked_on = '2026-12-31', revocation_reason = 'Test revocation'
 WHERE user_id = 'a8888888-0000-0000-0000-000000000008'
   AND role_name = 'member'
   AND revoked_on IS NULL;
SELECT pg_temp.assert(TRUE, 'ROLE_INTEGRITY', 'Setting revoked_on on user_roles is permitted');

-- 7.3 Un-revoking (setting revoked_on back to NULL) is rejected
SELECT pg_temp.assert_raises(
    'ROLE_INTEGRITY', 'Un-revoking a role (revoked_on → NULL) is rejected',
    $$UPDATE public.user_roles
        SET revoked_on = NULL
      WHERE user_id = 'a8888888-0000-0000-0000-000000000008'
        AND role_name = 'member'$$,
    'un-revoke'
);

-- 7.4 Backdating revoked_on is rejected
SELECT pg_temp.assert_raises(
    'ROLE_INTEGRITY', 'Backdating revoked_on is rejected',
    $$UPDATE public.user_roles
        SET revoked_on = '2020-01-01'  -- earlier than '2026-12-31'
      WHERE user_id = 'a8888888-0000-0000-0000-000000000008'
        AND role_name = 'member'$$,
    'backwards'
);

-- 7.5 Duplicate active role prevented by partial unique index
SELECT pg_temp.assert_raises(
    'ROLE_INTEGRITY', 'Duplicate active role for same user+society rejected',
    $$INSERT INTO public.user_roles (society_id, user_id, role_name, granted_on, granted_by)
      VALUES (
        'aaaaaaaa-0000-0000-0000-000000000001',
        'a5555555-0000-0000-0000-000000000005',
        'member',  -- Kalyan already has member role (active)
        '2025-01-01',
        'a1111111-0000-0000-0000-000000000001'
      )$$,
    NULL  -- unique index violation
);

\echo ''
\echo '================================================================'
\echo 'SECTION 8 — RLS: AUTHENTICATED USER VISIBILITY TESTS'
\echo '(Simulated via SET LOCAL role + set_config for auth.uid())'
\echo '================================================================'

-- Helper: set auth.uid() context for RLS testing
-- In Supabase, RLS policies call auth.uid() which reads from the JWT claim.
-- We simulate via set_config('request.jwt.claims', ...) in local testing.

CREATE OR REPLACE FUNCTION pg_temp.set_auth_uid(p_uid TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', p_uid, 'role', 'authenticated')::text,
        TRUE);  -- local = TRUE: resets after transaction
    -- Also set auth.uid() directly via the supported Supabase mechanism
    PERFORM set_config('request.jwt.claim.sub', p_uid, TRUE);
END;
$$;

-- NOTE: In Supabase local, auth.uid() is implemented as:
--   (current_setting('request.jwt.claims', true)::json->>'sub')::uuid
-- So our set_config approach correctly simulates authenticated user context.

-- 8.1 Super admin sees all properties in society 1
SELECT pg_temp.set_auth_uid('a1111111-0000-0000-0000-000000000001');
SET LOCAL ROLE authenticated;

DO $$
DECLARE
    prop_count INT;
BEGIN
    SELECT COUNT(*) INTO prop_count
    FROM public.properties
    WHERE society_id = 'aaaaaaaa-0000-0000-0000-000000000001';

    PERFORM pg_temp.assert(prop_count = 3, 'RLS',
        'Super admin sees all 3 properties in society 1',
        'Got: ' || prop_count);
END $$;

RESET ROLE;

-- 8.2 Property owner (Kalyan) sees his properties only
SELECT pg_temp.set_auth_uid('a5555555-0000-0000-0000-000000000005');
SET LOCAL ROLE authenticated;

DO $$
DECLARE
    prop_count INT;
    visible_ids TEXT[];
BEGIN
    SELECT ARRAY_AGG(plot_number ORDER BY plot_number) INTO visible_ids
    FROM public.properties;

    -- Kalyan owns Plot-45 and Plot-46; Plot-47 is vacant (unrelated)
    PERFORM pg_temp.assert(
        'Plot-45' = ANY(visible_ids) AND 'Plot-46' = ANY(visible_ids),
        'RLS', 'Owner sees their own properties (Plot-45, Plot-46)');
    PERFORM pg_temp.assert(
        NOT ('Plot-47' = ANY(visible_ids)),
        'RLS', 'Owner does NOT see unrelated Plot-47');
END $$;

RESET ROLE;

-- 8.3 Tenant (Ravi) sees only the property he rents
SELECT pg_temp.set_auth_uid('a7777777-0000-0000-0000-000000000007');
SET LOCAL ROLE authenticated;

DO $$
DECLARE
    visible_ids TEXT[];
BEGIN
    SELECT ARRAY_AGG(plot_number) INTO visible_ids FROM public.properties;
    PERFORM pg_temp.assert(
        'Plot-46' = ANY(visible_ids),
        'RLS', 'Tenant sees their rented property (Plot-46)');
    PERFORM pg_temp.assert(
        NOT ('Plot-45' = ANY(visible_ids)),
        'RLS', 'Tenant does NOT see Plot-45 (not their property)');
END $$;

RESET ROLE;

-- 8.4 Unrelated user sees nothing (after their role was revoked in section 7)
SELECT pg_temp.set_auth_uid('a8888888-0000-0000-0000-000000000008');
SET LOCAL ROLE authenticated;

DO $$
DECLARE
    prop_count INT;
BEGIN
    SELECT COUNT(*) INTO prop_count FROM public.properties;
    -- Unrelated user owns nothing, tenants nothing — should see 0
    PERFORM pg_temp.assert(prop_count = 0, 'RLS',
        'Unrelated user sees 0 properties', 'Got: ' || prop_count);
END $$;

RESET ROLE;

-- 8.5 Other-society user (society 2) cannot see society 1 properties
SELECT pg_temp.set_auth_uid('a9999999-0000-0000-0000-000000000009');
SET LOCAL ROLE authenticated;

DO $$
DECLARE
    prop_count INT;
BEGIN
    SELECT COUNT(*) INTO prop_count
    FROM public.properties
    WHERE society_id = 'aaaaaaaa-0000-0000-0000-000000000001';
    PERFORM pg_temp.assert(prop_count = 0, 'CROSS_SOCIETY',
        'Society-2 user sees 0 society-1 properties (cross-society isolation)');
END $$;

RESET ROLE;

\echo ''
\echo '================================================================'
\echo 'SECTION 9 — RLS: UNAUTHORIZED WRITE ATTEMPTS'
\echo '================================================================'

-- 9.1 Tenant cannot insert a property
SELECT pg_temp.set_auth_uid('a7777777-0000-0000-0000-000000000007');
SET LOCAL ROLE authenticated;

SELECT pg_temp.assert_raises(
    'RLS_WRITE', 'Tenant cannot insert a property (RLS blocks it)',
    $$INSERT INTO public.properties
        (society_id, plot_number, construction_status, property_type, occupancy_status, created_by)
      VALUES (
        'aaaaaaaa-0000-0000-0000-000000000001',
        'Plot-HACK', 'constructed', 'residential', 'vacant',
        'a7777777-0000-0000-0000-000000000007'
      )$$,
    NULL  -- RLS violation: new row violates WITH CHECK or USING clause
);

RESET ROLE;

-- 9.2 Member cannot insert a property
SELECT pg_temp.set_auth_uid('a5555555-0000-0000-0000-000000000005');
SET LOCAL ROLE authenticated;

SELECT pg_temp.assert_raises(
    'RLS_WRITE', 'Non-admin member cannot insert a property (RLS blocks it)',
    $$INSERT INTO public.properties
        (society_id, plot_number, construction_status, property_type, occupancy_status, created_by)
      VALUES (
        'aaaaaaaa-0000-0000-0000-000000000001',
        'Plot-OWNER-HACK', 'constructed', 'residential', 'vacant',
        'a5555555-0000-0000-0000-000000000005'
      )$$,
    NULL
);

RESET ROLE;

-- 9.3 Member cannot grant themselves a role
SELECT pg_temp.set_auth_uid('a5555555-0000-0000-0000-000000000005');
SET LOCAL ROLE authenticated;

SELECT pg_temp.assert_raises(
    'RLS_WRITE', 'Member cannot self-grant super_admin role',
    $$INSERT INTO public.user_roles (society_id, user_id, role_name, granted_on, granted_by)
      VALUES (
        'aaaaaaaa-0000-0000-0000-000000000001',
        'a5555555-0000-0000-0000-000000000005',
        'super_admin', CURRENT_DATE,
        'a5555555-0000-0000-0000-000000000005'
      )$$,
    NULL  -- RLS: only super_admin can INSERT
);

RESET ROLE;

-- 9.4 Tenant cannot update a property they rent
SELECT pg_temp.set_auth_uid('a7777777-0000-0000-0000-000000000007');
SET LOCAL ROLE authenticated;

DO $$
DECLARE v_count INT;
BEGIN
    UPDATE public.properties
        SET occupancy_status = 'vacant'
      WHERE id = 'b1111002-0000-0000-0000-000000000002';
    GET DIAGNOSTICS v_count = ROW_COUNT;
    PERFORM pg_temp.assert(v_count = 0, 'RLS_WRITE', 'Tenant cannot update a property (even one they rent)', 'Got: ' || v_count);
END $$;

RESET ROLE;

-- 9.5 Other-society user cannot see or touch society-1 data
SELECT pg_temp.set_auth_uid('a9999999-0000-0000-0000-000000000009');
SET LOCAL ROLE authenticated;

DO $$
DECLARE v_count INT;
BEGIN
    UPDATE public.properties
        SET remarks = 'hacked'
      WHERE society_id = 'aaaaaaaa-0000-0000-0000-000000000001';
    GET DIAGNOSTICS v_count = ROW_COUNT;
    PERFORM pg_temp.assert(v_count = 0, 'CROSS_SOCIETY', 'Cross-society user cannot update society-1 property', 'Got: ' || v_count);
END $$;

RESET ROLE;

\echo ''
\echo '================================================================'
\echo 'SECTION 10 — DELETE PROTECTION'
\echo '================================================================'

-- 10.1 No DELETE policy on properties — any attempt is blocked
SELECT pg_temp.set_auth_uid('a1111111-0000-0000-0000-000000000001');
SET LOCAL ROLE authenticated;

SELECT pg_temp.assert_raises(
    'DELETE_PROTECT', 'Even super_admin cannot DELETE a property via direct client call',
    $$DELETE FROM public.properties WHERE id = 'b1111001-0000-0000-0000-000000000001'$$,
    NULL
);

-- 10.2 No DELETE on property_owners
SELECT pg_temp.assert_raises(
    'DELETE_PROTECT', 'property_owners cannot be DELETEd (history preserved)',
    $$DELETE FROM public.property_owners WHERE id = 'e1111001-0000-0000-0000-000000000001'$$,
    NULL
);

-- 10.3 No DELETE on tenancies
SELECT pg_temp.assert_raises(
    'DELETE_PROTECT', 'tenancies cannot be DELETEd (history preserved)',
    $$DELETE FROM public.tenancies WHERE id = 'c1111001-0000-0000-0000-000000000001'$$,
    NULL
);

-- 10.4 No DELETE on association_memberships
SELECT pg_temp.assert_raises(
    'DELETE_PROTECT', 'association_memberships cannot be DELETEd',
    $$DELETE FROM public.association_memberships WHERE id = 'd1111001-0000-0000-0000-000000000001'$$,
    NULL
);

-- 10.5 No DELETE on user_roles
SELECT pg_temp.assert_raises(
    'DELETE_PROTECT', 'user_roles cannot be DELETEd (history preserved)',
    $$DELETE FROM public.user_roles WHERE user_id = 'a7777777-0000-0000-0000-000000000007'$$,
    NULL
);

RESET ROLE;

\echo ''
\echo '================================================================'
\echo 'SECTION 11 — SECURITY DEFINER PRIVILEGE ESCALATION TESTS'
\echo '================================================================'

-- 11.1 is_admin() returns FALSE for non-admin calling user
SELECT pg_temp.set_auth_uid('a7777777-0000-0000-0000-000000000007');
SET LOCAL ROLE authenticated;

DO $$
BEGIN
    PERFORM pg_temp.assert(
        NOT public.is_admin(),
        'SECURITY', 'is_admin() returns FALSE for tenant user (uid=u7777777)');
END $$;

RESET ROLE;

-- 11.2 is_admin() returns TRUE for super_admin
SELECT pg_temp.set_auth_uid('a1111111-0000-0000-0000-000000000001');
SET LOCAL ROLE authenticated;

DO $$
BEGIN
    PERFORM pg_temp.assert(
        public.is_admin(),
        'SECURITY', 'is_admin() returns TRUE for super_admin (uid=u1111111)');
END $$;

RESET ROLE;

-- 11.3 has_role() cannot be called to bypass RLS directly
-- (Calling has_role in a USING clause is fine; what we test here is that
--  a non-admin cannot INSERT a role by calling has_role to inflate their permissions)
SELECT pg_temp.set_auth_uid('a5555555-0000-0000-0000-000000000005');
SET LOCAL ROLE authenticated;

DO $$
DECLARE
    result BOOLEAN;
BEGIN
    -- has_role for a role the user doesn't have
    SELECT public.has_role('a5555555-0000-0000-0000-000000000005', 'super_admin')
    INTO result;
    PERFORM pg_temp.assert(NOT result, 'SECURITY',
        'has_role() returns FALSE for role user does not hold');

    -- has_role for a role the user does have
    SELECT public.has_role('a5555555-0000-0000-0000-000000000005', 'member')
    INTO result;
    PERFORM pg_temp.assert(result, 'SECURITY',
        'has_role() returns TRUE for role user does hold (member)');
END $$;

RESET ROLE;

-- 11.4 is_property_owner() returns correct values
SELECT pg_temp.set_auth_uid('a7777777-0000-0000-0000-000000000007');
SET LOCAL ROLE authenticated;

DO $$
BEGIN
    PERFORM pg_temp.assert(
        NOT public.is_property_owner('a7777777-0000-0000-0000-000000000007',
                                      'b1111001-0000-0000-0000-000000000001'),
        'SECURITY', 'is_property_owner() returns FALSE for tenant on Plot-45');
    PERFORM pg_temp.assert(
        public.is_property_owner('a5555555-0000-0000-0000-000000000005',
                                  'b1111001-0000-0000-0000-000000000001'),
        'SECURITY', 'is_property_owner() returns TRUE for Kalyan on Plot-45');
END $$;

RESET ROLE;

\echo ''
\echo '================================================================'
\echo 'SECTION 12 — CONSTRAINT: DATE INTEGRITY'
\echo '================================================================'

-- 12.1 end_date before start_date is rejected on property_owners
SELECT pg_temp.assert_raises(
    'CONSTRAINT', 'end_date < start_date rejected in property_owners',
    $$INSERT INTO public.property_owners
        (property_id, owner_id, ownership_share_pct, is_primary_owner,
         start_date, end_date, created_by)
      VALUES (
        'b1111003-0000-0000-0000-000000000003',
        'a6666666-0000-0000-0000-000000000006',
        100.00, TRUE,
        '2025-01-01', '2024-01-01',  -- end before start
        'a1111111-0000-0000-0000-000000000001'
      )$$,
    'check'
);

-- 12.2 end_date before start_date rejected on tenancies
SELECT pg_temp.assert_raises(
    'CONSTRAINT', 'end_date < start_date rejected in tenancies',
    $$INSERT INTO public.tenancies
        (society_id, property_id, tenant_id, start_date, end_date, created_by)
      VALUES (
        'aaaaaaaa-0000-0000-0000-000000000001',
        'b1111003-0000-0000-0000-000000000003',
        'a4444444-0000-0000-0000-000000000004',
        '2025-06-01', '2025-01-01',  -- end before start
        'a1111111-0000-0000-0000-000000000001'
      )$$,
    'check'
);

-- 12.3 Invalid pincode format rejected
SELECT pg_temp.assert_raises(
    'CONSTRAINT', 'Invalid pincode format rejected (must be 6 digits)',
    $$INSERT INTO public.societies (name, pincode, is_active)
      VALUES ('Bad Society', '1234', TRUE)$$,
    'check'
);

\echo ''
\echo '================================================================'
\echo 'FINAL SUMMARY'
\echo '================================================================'

DO $$
DECLARE
    pass_count INT;
    fail_count INT;
    total      INT;
    r          RECORD;
BEGIN
    SELECT COUNT(*) FILTER (WHERE result = 'PASS'),
           COUNT(*) FILTER (WHERE result = 'FAIL'),
           COUNT(*)
    INTO pass_count, fail_count, total
    FROM _test_results;

    RAISE NOTICE '';
    RAISE NOTICE '================================================';
    RAISE NOTICE 'SLICE 1 LIVE VERIFICATION RESULTS';
    RAISE NOTICE '================================================';
    RAISE NOTICE 'TOTAL : %', total;
    RAISE NOTICE 'PASS  : %', pass_count;
    RAISE NOTICE 'FAIL  : %', fail_count;
    RAISE NOTICE '================================================';

    IF fail_count > 0 THEN
        RAISE NOTICE '';
        RAISE NOTICE 'FAILED TESTS:';
        FOR r IN
            SELECT seq, category, description, detail
            FROM _test_results WHERE result = 'FAIL'
            ORDER BY seq
        LOOP
            RAISE NOTICE '  [%] [%] % — %',
                r.seq, r.category, r.description, COALESCE(r.detail, '');
        END LOOP;
    END IF;
END $$;

-- Return results as a table (for psql \pset output)
SELECT
    result,
    category,
    description,
    COALESCE(detail, '') AS detail
FROM _test_results
ORDER BY seq;

-- Rollback ALL seed data — verification leaves the database clean
ROLLBACK;
\echo 'All test data rolled back. Database is clean.'
