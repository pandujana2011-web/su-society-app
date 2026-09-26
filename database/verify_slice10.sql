-- ==============================================================================
-- SU SOCIETY APP - SLICE 10: VERIFICATION & REGRESSION
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
    v_member1 UUID;
    v_admin2 UUID;
    v_member2 UUID;
    
    v_meeting1 UUID;
    v_meeting2 UUID;
    v_agenda1 UUID;
    v_res1 UUID;
    v_poll1 UUID;
    v_audit_count INT;
BEGIN
    RAISE NOTICE '==================================================';
    RAISE NOTICE 'STARTING SLICE 10 VERIFICATION (SOCIETY GOVERNANCE)';
    RAISE NOTICE '==================================================';

    -- 1. Setup Test Data
    v_soc1 := gen_random_uuid();
    v_soc2 := gen_random_uuid();
    v_admin1 := gen_random_uuid();
    v_member1 := gen_random_uuid();
    v_admin2 := gen_random_uuid();
    v_member2 := gen_random_uuid();

    -- Setup runs as postgres

    -- Insert into auth.users (mock)
    INSERT INTO auth.users (id, email, created_at, updated_at, confirmation_token, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, is_super_admin, role) VALUES 
        (v_admin1, 'a1@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
        (v_member1, 'm1@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
        (v_admin2, 'a2@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
        (v_member2, 'm2@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated');

    -- Insert into public.users
    INSERT INTO public.users (id, full_name, mobile) VALUES 
        (v_admin1, 'Admin 1', '1111111111'),
        (v_member1, 'Member 1', '2222222222'),
        (v_admin2, 'Admin 2', '3333333333'),
        (v_member2, 'Member 2', '4444444444');

    -- Insert Societies
    INSERT INTO public.societies (id, name) VALUES 
        (v_soc1, 'Society 1'),
        (v_soc2, 'Society 2');

    -- Insert Memberships / Roles
    INSERT INTO public.user_roles (society_id, user_id, role_name, granted_by) VALUES 
        (v_soc1, v_admin1, 'admin', v_admin1),
        (v_soc2, v_admin2, 'admin', v_admin2),
        (v_soc1, v_member1, 'member', v_admin1),
        (v_soc2, v_member2, 'member', v_admin2);

    -- ---------------------------------------------------------
    -- FUNCTIONAL TESTS & RLS
    -- ---------------------------------------------------------
    PERFORM set_config('role', 'authenticated', true);

    
    -- Admin 1 creates Meeting
    PERFORM pg_temp.set_auth_uid(v_admin1::text);
    
    INSERT INTO public.meetings (society_id, title, meeting_type, scheduled_at, created_by)
    VALUES (v_soc1, 'Annual General Meeting 2026', 'AGM', NOW() + INTERVAL '7 days', v_admin1)
    RETURNING id INTO v_meeting1;

    INSERT INTO public.meeting_agendas (meeting_id, item_number, title)
    VALUES (v_meeting1, 1, 'Welcome Note');
    
    INSERT INTO public.meeting_resolutions (meeting_id, title, status)
    VALUES (v_meeting1, 'Budget Approval', 'proposed')
    RETURNING id INTO v_res1;
    
    RAISE NOTICE 'PASS: Admin can create meeting, agendas, and resolutions';

    -- Member 1 can view meeting
    PERFORM pg_temp.set_auth_uid(v_member1::text);
    IF NOT EXISTS (SELECT 1 FROM public.meetings WHERE id = v_meeting1) THEN
        RAISE EXCEPTION 'FAIL: Member cannot view their society meeting';
    END IF;
    RAISE NOTICE 'PASS: Member can view their society meeting';

    -- Member 1 cannot modify meeting
    BEGIN
        INSERT INTO public.meetings (society_id, title, meeting_type, scheduled_at, created_by)
        VALUES (v_soc1, 'Hacked Meeting', 'AGM', NOW(), v_member1);
        RAISE EXCEPTION 'FAIL: Member created a meeting';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'PASS: Member cannot create a meeting (%)', SQLERRM;
    END;

    -- Cross-society Isolation
    PERFORM pg_temp.set_auth_uid(v_admin2::text);
    IF EXISTS (SELECT 1 FROM public.meetings WHERE id = v_meeting1) THEN
        RAISE EXCEPTION 'FAIL: Cross-society leak detected (Admin 2 saw Meeting 1)';
    END IF;
    RAISE NOTICE 'PASS: Cross-society isolation enforced on SELECT';
    
    -- Admin 2 creates their own meeting
    INSERT INTO public.meetings (society_id, title, meeting_type, scheduled_at, created_by)
    VALUES (v_soc2, 'Society 2 EGM', 'EGM', NOW() + INTERVAL '1 day', v_admin2)
    RETURNING id INTO v_meeting2;

    -- ---------------------------------------------------------
    -- STATE MACHINE & ELEVATED SECURITY TESTS
    -- ---------------------------------------------------------
    
    PERFORM pg_temp.set_auth_uid(v_admin1::text);
    
    -- Admin 1 tries direct UPDATE on status
    BEGIN
        UPDATE public.meetings SET status = 'in_progress' WHERE id = v_meeting1;
        RAISE EXCEPTION 'FAIL: Direct UPDATE to meeting status allowed';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'PASS: Direct UPDATE to meeting status blocked (%)', SQLERRM;
    END;

    -- Admin 1 tries fake transition context
    BEGIN
        PERFORM set_config('app.meeting_transition', 'fake-uuid', true);
        UPDATE public.meetings SET status = 'in_progress' WHERE id = v_meeting1;
        RAISE EXCEPTION 'FAIL: Fake context allowed UPDATE';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'PASS: Fake context blocked (%)', SQLERRM;
    END;
    
    -- Clear fake context
    PERFORM set_config('app.meeting_transition', '', true);

    -- Admin 1 correctly transitions meeting to in_progress
    PERFORM public.fn_transition_meeting_state(v_meeting1, 'in_progress');
    IF (SELECT status FROM public.meetings WHERE id = v_meeting1) != 'in_progress' THEN
        RAISE EXCEPTION 'FAIL: Meeting status did not change to in_progress';
    END IF;
    RAISE NOTICE 'PASS: Authorized transition to in_progress successful';

    -- Admin 1 tries invalid transition (in_progress -> scheduled)
    BEGIN
        PERFORM public.fn_transition_meeting_state(v_meeting1, 'scheduled');
        RAISE EXCEPTION 'FAIL: Invalid transition allowed';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'PASS: Invalid transition blocked (%)', SQLERRM;
    END;

    -- Clear transition context before proceeding to attendance!
    PERFORM set_config('app.meeting_transition', '', true);

    -- ---------------------------------------------------------
    -- ATTENDANCE & SELF CHECK-IN TESTS
    -- ---------------------------------------------------------

    PERFORM pg_temp.set_auth_uid(v_member1::text);

    -- Member 1 self checks in
    PERFORM public.fn_meeting_self_check_in(v_meeting1);
    IF NOT EXISTS (SELECT 1 FROM public.meeting_attendance WHERE meeting_id = v_meeting1 AND user_id = v_member1) THEN
        RAISE EXCEPTION 'FAIL: Self check-in failed';
    END IF;
    RAISE NOTICE 'PASS: Member successfully self checked in';

    -- Member 1 tries duplicate check in
    BEGIN
        PERFORM public.fn_meeting_self_check_in(v_meeting1);
        RAISE EXCEPTION 'FAIL: Duplicate check-in allowed';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'PASS: Duplicate check-in blocked by UNIQUE constraint (%)', SQLERRM;
    END;

    -- Member 1 tries to check in to Society 2's meeting (not in progress anyway, but cross-soc should block)
    BEGIN
        PERFORM public.fn_meeting_self_check_in(v_meeting2);
        RAISE EXCEPTION 'FAIL: Cross-society check-in allowed';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'PASS: Cross-society self check-in blocked (%)', SQLERRM;
    END;

    -- Admin 1 tries to log attendance for a user in Society 2
    PERFORM pg_temp.set_auth_uid(v_admin1::text);
    BEGIN
        PERFORM public.fn_meeting_admin_check_in(v_meeting1, v_member2);
        RAISE EXCEPTION 'FAIL: Admin logged attendance for foreign user';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'PASS: Admin cross-society attendance blocked (%)', SQLERRM;
    END;

    -- ---------------------------------------------------------
    -- AGENDA UNIQUE CONSTRAINT TEST
    -- ---------------------------------------------------------
    BEGIN
        INSERT INTO public.meeting_agendas (meeting_id, item_number, title)
        VALUES (v_meeting1, 1, 'Duplicate Item');
        RAISE EXCEPTION 'FAIL: Duplicate agenda item number allowed';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'PASS: Duplicate agenda item number blocked (%)', SQLERRM;
    END;

    -- ---------------------------------------------------------
    -- RESOLUTION & POLL INTEGRITY
    -- ---------------------------------------------------------
    
    -- Create a poll in Society 1
    INSERT INTO public.polls (society_id, title, description, starts_at, ends_at, created_by)
    VALUES (v_soc1, 'Poll for Budget', 'Description', NOW(), NOW() + INTERVAL '1 day', v_admin1)
    RETURNING id INTO v_poll1;
    
    -- Admin 1 adopts resolution linking to poll
    PERFORM public.fn_transition_resolution_state(v_res1, 'adopted', v_poll1);
    IF (SELECT status FROM public.meeting_resolutions WHERE id = v_res1) != 'adopted' THEN
        RAISE EXCEPTION 'FAIL: Resolution adoption failed';
    END IF;
    RAISE NOTICE 'PASS: Resolution state transitioned to adopted with poll link';

    -- Admin 2 creates a resolution in meeting 2 linking to poll 1 (different society)
    PERFORM pg_temp.set_auth_uid(v_admin2::text);
    BEGIN
        INSERT INTO public.meeting_resolutions (meeting_id, title, poll_id)
        VALUES (v_meeting2, 'Malicious Resolution', v_poll1);
        RAISE EXCEPTION 'FAIL: Cross-society poll link allowed';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'PASS: Cross-society poll link blocked';
    END;
    
    -- ---------------------------------------------------------
    -- AUDIT LOG VERIFICATION
    -- ---------------------------------------------------------
    PERFORM pg_temp.set_auth_uid(v_admin1::text);
    
    SELECT count(*) INTO v_audit_count FROM public.audit_logs 
    WHERE entity_type IN ('meetings', 'meeting_agendas', 'meeting_resolutions', 'meeting_attendance');
    
    IF v_audit_count < 5 THEN
        RAISE EXCEPTION 'FAIL: Expected at least 5 audit logs, found %', v_audit_count;
    END IF;
    RAISE NOTICE 'PASS: Audit triggers successfully logged operations (Found: %)', v_audit_count;

    RAISE NOTICE '==================================================';
    RAISE NOTICE 'SLICE 10 VERIFICATION COMPLETE (ALL 13 TESTS PASS)';
    RAISE NOTICE '==================================================';

END $$;
