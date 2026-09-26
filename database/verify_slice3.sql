-- =========================================================================
-- SU SOCIETY APP - SLICE 3 VERIFICATION
-- =========================================================================

-- Test Result Table (same as Slice 1)
CREATE TABLE IF NOT EXISTS public._test_results (
    id SERIAL PRIMARY KEY,
    result VARCHAR(10),
    category VARCHAR(50),
    description TEXT,
    detail TEXT
);

TRUNCATE TABLE public._test_results;
GRANT SELECT, INSERT ON public._test_results TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE public._test_results_id_seq TO authenticated;

CREATE OR REPLACE FUNCTION pg_temp.assert(
    p_condition BOOLEAN,
    p_category  TEXT,
    p_desc      TEXT,
    p_detail    TEXT DEFAULT ''
) RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    IF p_condition THEN
        INSERT INTO _test_results(result, category, description, detail)
        VALUES ('PASS', p_category, p_desc, p_detail);
    ELSE
        INSERT INTO _test_results(result, category, description, detail)
        VALUES ('FAIL', p_category, p_desc, p_detail);
        RAISE WARNING 'FAIL [%]: % - %', p_category, p_desc, p_detail;
    END IF;
END;
$$;

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
        INSERT INTO _test_results(result, category, description, detail)
            VALUES ('FAIL', p_category, p_desc, 'Expected exception was NOT raised');
        RAISE WARNING 'FAIL [%]: % - expected exception not raised', p_category, p_desc;
        RETURN;
    EXCEPTION WHEN OTHERS THEN
        v_err := SQLERRM;
    END;
    IF p_expected_msg IS NULL OR v_err ILIKE ('%' || p_expected_msg || '%') THEN
        INSERT INTO _test_results(result, category, description)
            VALUES ('PASS', p_category, p_desc);
    ELSE
        INSERT INTO _test_results(result, category, description, detail)
            VALUES ('FAIL', p_category, p_desc, 'Expected msg containing "' || p_expected_msg || '", got: ' || v_err);
    END IF;
END;
$$;

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

BEGIN;

-- SEED DATA FROM SLICE 1
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


-- 1. SEED ROLES & AMENITIES FOR SLICE 3
INSERT INTO auth.users (id, email, created_at, updated_at, confirmation_token, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, is_super_admin, role) VALUES
('a5000000-0000-0000-0000-000000000050', 'gatekeeper@test.local', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
('a6000000-0000-0000-0000-000000000060', 'technician@test.local', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.users (id, full_name, mobile, status) VALUES 
('a5000000-0000-0000-0000-000000000050', 'S3 Gatekeeper', '+919999999950', 'active'),
('a6000000-0000-0000-0000-000000000060', 'S3 Technician', '+919999999960', 'active')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.user_roles (society_id, user_id, role_name, granted_by) VALUES
('aaaaaaaa-0000-0000-0000-000000000001', 'a5000000-0000-0000-0000-000000000050', 'gatekeeper', 'a1111111-0000-0000-0000-000000000001'),
('aaaaaaaa-0000-0000-0000-000000000001', 'a6000000-0000-0000-0000-000000000060', 'technician', 'a1111111-0000-0000-0000-000000000001');

SELECT pg_temp.set_auth_uid('a1111111-0000-0000-0000-000000000001'); -- Admin

INSERT INTO public.amenities (id, society_id, name, booking_type, hourly_rate, created_by) VALUES
('e1111001-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'Clubhouse', 'slot_based', 1000.00, 'a1111111-0000-0000-0000-000000000001'),
('e1111002-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001', 'Free Gym', 'slot_based', 0.00, 'a1111111-0000-0000-0000-000000000001');

-- =========================================================================
SET LOCAL ROLE authenticated;
SELECT pg_temp.set_auth_uid('a5555555-0000-0000-0000-000000000005'); -- Owner Plot-45
DO $test$
DECLARE 
    v_booking1 UUID;
    v_booking2 UUID;
    v_row_count INT;
BEGIN
    v_booking1 := public.fn_create_amenity_booking('e1111001-0000-0000-0000-000000000001', 'b1111001-0000-0000-0000-000000000001', NULL, '2026-10-01 10:00:00+00', '2026-10-01 12:00:00+00');
    PERFORM pg_temp.assert(v_booking1 IS NOT NULL, 'BOOKING', 'Owner can create pending booking for own property');

    v_booking2 := public.fn_create_amenity_booking('e1111001-0000-0000-0000-000000000001', 'b1111001-0000-0000-0000-000000000001', NULL, '2026-10-01 11:00:00+00', '2026-10-01 13:00:00+00');
    
    PERFORM pg_temp.assert_raises('SECURITY', 'Owner cannot approve booking',
        $$SELECT public.fn_process_booking_action('$$ || v_booking1 || $$', 'approve')$$, 'Only admin can approve');

    UPDATE public.amenity_bookings SET status = 'approved' WHERE id = v_booking1;
    GET DIAGNOSTICS v_row_count = ROW_COUNT;
    PERFORM pg_temp.assert(v_row_count = 0, 'SECURITY', 'Direct UPDATE of booking status is blocked by RLS');
        
    PERFORM pg_temp.set_auth_uid('a1111111-0000-0000-0000-000000000001'); -- Admin
    
    PERFORM public.fn_process_booking_action(v_booking1, 'approve');
    PERFORM pg_temp.assert(TRUE, 'BOOKING', 'Admin successfully approved booking 1');
    
    PERFORM pg_temp.assert_raises('CONCURRENCY', 'Overlapping approved booking natively blocked by EXCLUDE USING gist',
        $$SELECT public.fn_process_booking_action('$$ || v_booking2 || $$', 'approve')$$, 'conflicting key value violates exclusion constraint');

    PERFORM pg_temp.assert_raises('CONCURRENCY', 'Cannot approve already approved booking',
        $$SELECT public.fn_process_booking_action('$$ || v_booking1 || $$', 'approve')$$, 'Invalid transition');
END $test$;

-- =========================================================================
-- CATEGORY: BOOKING FINANCIAL INTEGRATION
-- =========================================================================
DO $test$
DECLARE
    v_booking_id UUID;
    v_ledger_count INT;
    v_ledger_id UUID;
BEGIN
    SELECT id INTO v_booking_id FROM public.amenity_bookings WHERE status = 'approved';
    
    SELECT COUNT(*) INTO v_ledger_count FROM public.ledger_transactions 
    WHERE source_booking_id = v_booking_id AND transaction_type = 'booking_charge' AND amount = 2000.00;
    PERFORM pg_temp.assert(v_ledger_count = 1, 'FINANCIAL', 'Approved booking strictly generated exactly one 2000.00 ledger debit');

    PERFORM public.fn_process_booking_action(v_booking_id, 'cancel');
    
    SELECT id INTO v_ledger_id FROM public.ledger_transactions 
    WHERE source_booking_id = v_booking_id AND transaction_type = 'booking_charge';
    
    SELECT COUNT(*) INTO v_ledger_count FROM public.ledger_transactions 
    WHERE reverses_ledger_id = v_ledger_id AND transaction_type = 'reversal' AND direction = 'credit' AND amount = 2000.00;
    PERFORM pg_temp.assert(v_ledger_count = 1, 'FINANCIAL', 'Cancelled approved booking strictly generated exactly one 2000.00 compensating credit');
    
    PERFORM pg_temp.set_auth_uid('a5555555-0000-0000-0000-000000000005');
    v_booking_id := public.fn_create_amenity_booking('e1111002-0000-0000-0000-000000000002', 'b1111001-0000-0000-0000-000000000001', NULL, '2026-10-01 10:00:00+00', '2026-10-01 12:00:00+00');
    
    PERFORM pg_temp.set_auth_uid('a1111111-0000-0000-0000-000000000001');
    PERFORM public.fn_process_booking_action(v_booking_id, 'approve');
    
    SELECT COUNT(*) INTO v_ledger_count FROM public.ledger_transactions WHERE source_booking_id = v_booking_id;
    PERFORM pg_temp.assert(v_ledger_count = 0, 'FINANCIAL', 'Zero-charge booking successfully bypassed ledger insertion');
END $test$;

-- =========================================================================
-- CATEGORY: VISITORS & PRE-AUTH
-- =========================================================================
SELECT pg_temp.set_auth_uid('a5555555-0000-0000-0000-000000000005'); -- Owner
DO $test$
DECLARE
    v_visitor UUID;
BEGIN
    INSERT INTO public.visitor_logs (society_id, property_id, visitor_name, purpose, valid_until, pre_auth_code, registered_by)
    VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'b1111001-0000-0000-0000-000000000001', 'John Guest', 'guest', NOW() + INTERVAL '1 day', '123456', auth.uid())
    RETURNING id INTO v_visitor;
    
    PERFORM pg_temp.assert(v_visitor IS NOT NULL, 'VISITOR', 'Owner can generate pre-auth code for their property');

    PERFORM pg_temp.assert_raises('SECURITY', 'Owner cannot check-in visitor',
        $$SELECT public.fn_visitor_check_in('aaaaaaaa-0000-0000-0000-000000000001', '123456')$$, 'Access Denied: Must be gatekeeper');
        
    INSERT INTO public.visitor_logs (society_id, property_id, visitor_name, purpose, valid_until, pre_auth_code, registered_by)
    VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'b1111001-0000-0000-0000-000000000001', 'Expired Guest', 'guest', NOW() - INTERVAL '1 day', '999999', auth.uid());
    
    PERFORM pg_temp.set_auth_uid('a5000000-0000-0000-0000-000000000050'); -- Gatekeeper
    
    PERFORM pg_temp.assert_raises('VISITOR', 'Gatekeeper check-in strictly rejects expired pre-auth code',
        $$SELECT public.fn_visitor_check_in('aaaaaaaa-0000-0000-0000-000000000001', '999999')$$, 'Pre-auth code expired');
        
    PERFORM public.fn_visitor_check_in('aaaaaaaa-0000-0000-0000-000000000001', '123456');
    PERFORM pg_temp.assert(TRUE, 'VISITOR', 'Gatekeeper successfully checked in valid pre-auth visitor');
    
    PERFORM pg_temp.assert_raises('CONCURRENCY', 'Gatekeeper cannot double check-in same pre-auth code',
        $$SELECT public.fn_visitor_check_in('aaaaaaaa-0000-0000-0000-000000000001', '123456')$$, 'Already checked in');
        
    PERFORM public.fn_visitor_check_out(v_visitor);
    PERFORM pg_temp.assert(TRUE, 'VISITOR', 'Gatekeeper successfully checked out visitor');
    
    PERFORM pg_temp.assert_raises('CONCURRENCY', 'Gatekeeper cannot double check-out same visitor',
        $$SELECT public.fn_visitor_check_out('$$ || v_visitor || $$')$$, 'Already checked out');
END $test$;

-- =========================================================================
-- CATEGORY: HELPDESK & RLS
-- =========================================================================
SELECT pg_temp.set_auth_uid('a7777777-0000-0000-0000-000000000007'); -- Tenant Plot-46
DO $test$
DECLARE
    v_ticket UUID;
    v_row_count INT;
BEGIN
    INSERT INTO public.technician_tickets (society_id, property_id, category, title, description, created_by)
    VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'b1111002-0000-0000-0000-000000000002', 'plumbing', 'Leak', 'Pipe leak', auth.uid())
    RETURNING id INTO v_ticket;
    
    PERFORM pg_temp.assert(v_ticket IS NOT NULL, 'HELPDESK', 'Tenant can create a ticket for their property');

    PERFORM pg_temp.assert_raises('SECURITY', 'Tenant cannot transition ticket to assigned',
        $$SELECT public.fn_transition_ticket_state('$$ || v_ticket || $$', 'assigned')$$, 'Access Denied');
        
    UPDATE public.technician_tickets SET status = 'closed' WHERE id = v_ticket;
    GET DIAGNOSTICS v_row_count = ROW_COUNT;
    PERFORM pg_temp.assert(v_row_count = 0, 'SECURITY', 'Direct UPDATE of ticket status blocked by RLS');
    
    PERFORM pg_temp.assert_raises('SECURITY', 'Tenant cannot create ticket for another property',
        $$INSERT INTO public.technician_tickets (society_id, property_id, category, title, description, created_by)
          VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'b1111001-0000-0000-0000-000000000001', 'plumbing', 'Leak', 'Leak', auth.uid())$$, NULL);

    PERFORM pg_temp.set_auth_uid('a6000000-0000-0000-0000-000000000060'); -- Technician
    
    PERFORM public.fn_transition_ticket_state(v_ticket, 'assigned');
    PERFORM pg_temp.assert(TRUE, 'HELPDESK', 'Technician successfully transitioned ticket to assigned');
    
    INSERT INTO public.ticket_comments (ticket_id, author_id, comment_text) VALUES (v_ticket, auth.uid(), 'Will check today');
    PERFORM pg_temp.assert(TRUE, 'HELPDESK', 'Technician successfully commented on ticket');
    
    PERFORM public.fn_transition_ticket_state(v_ticket, 'resolved');
    PERFORM pg_temp.assert(TRUE, 'HELPDESK', 'Technician successfully resolved ticket');
    
    PERFORM pg_temp.set_auth_uid('a7777777-0000-0000-0000-000000000007');
    PERFORM public.fn_transition_ticket_state(v_ticket, 'closed');
    PERFORM pg_temp.assert(TRUE, 'HELPDESK', 'Ticket creator successfully closed their resolved ticket');
    
    PERFORM pg_temp.set_auth_uid('a1111111-0000-0000-0000-000000000001');
    PERFORM pg_temp.assert_raises('HELPDESK', 'Invalid transition from closed rejected',
        $$SELECT public.fn_transition_ticket_state('$$ || v_ticket || $$', 'open')$$, 'Invalid transition');
END $test$;

-- =========================================================================
-- CATEGORY: CROSS-SOCIETY ATTACKS
-- =========================================================================
SELECT pg_temp.set_auth_uid('a1111111-0000-0000-0000-000000000001'); -- Admin to fetch ticket
DO $test$
DECLARE
    v_ticket UUID;
BEGIN
    SELECT id INTO v_ticket FROM public.technician_tickets LIMIT 1;
    
    PERFORM pg_temp.set_auth_uid('a9999999-0000-0000-0000-000000000009'); -- Other Society User
    
    PERFORM pg_temp.assert_raises('SECURITY', 'Cross-society admin cannot transition ticket',
        $$SELECT public.fn_transition_ticket_state('$$ || v_ticket || $$', 'open')$$, 'Cross-society denied');
        
    PERFORM pg_temp.assert_raises('SECURITY', 'Cross-society gatekeeper cannot check-in visitor',
        $$SELECT public.fn_visitor_check_in('aaaaaaaa-0000-0000-0000-000000000001', '123456')$$, 'Cross-society denied');
END $test$;

-- Print Results
SELECT 
    COUNT(*) AS total_assertions,
    COUNT(*) FILTER (WHERE result = 'PASS') AS passed,
    COUNT(*) FILTER (WHERE result = 'FAIL') AS failed
FROM _test_results
WHERE category IN ('BOOKING', 'FINANCIAL', 'VISITOR', 'HELPDESK', 'CONCURRENCY');

SELECT result, category, description FROM _test_results WHERE result = 'FAIL';

ROLLBACK;
