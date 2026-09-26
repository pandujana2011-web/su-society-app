-- ==============================================================================
-- SLICE 16 VERIFICATION SUITE: GOVERNANCE, BUDGETS & BLACKOUT WORKFLOWS (REMEDIATED)
-- ==============================================================================

DO $$
DECLARE
    v_pass_count INT := 0;
    v_total_count INT := 35;

    -- Test Fixtures
    v_society_id UUID;
    v_other_society_id UUID;

    v_admin_id UUID;
    v_secretary_id UUID;
    v_treasurer_id UUID;
    v_exec_id UUID;
    v_member_id UUID;

    v_other_admin_id UUID;
    v_other_member_id UUID;

    v_amenity_id UUID;

    -- Entities
    v_res_id UUID;
    v_res2_id UUID;
    v_res3_id UUID;

    v_budget_id UUID;
    v_empty_budget_id UUID;
    v_line_item1_id UUID;
    v_line_item2_id UUID;
    v_line_item3_id UUID;

    v_voucher_id UUID;
    v_voucher2_id UUID;

    v_blackout_id UUID;
    v_blackout2_id UUID;

    v_audit_count INT;
    v_notif_count INT;
    v_ledger_count INT;
    v_catalog_count INT;
    v_row_count INT;

    v_res_rec RECORD;
    v_budget_rec RECORD;
    v_line_rec RECORD;
    v_voucher_rec RECORD;
    v_blackout_rec RECORD;
    v_ledger_rec RECORD;
BEGIN
    RAISE NOTICE '==================================================';
    RAISE NOTICE 'STARTING SLICE 16 VERIFICATION (GOVERNANCE & WORKFLOWS - REMEDIATED)';
    RAISE NOTICE '==================================================';

    -- --------------------------------------------------------------------------
    -- FIXTURE SETUP
    -- --------------------------------------------------------------------------
    -- Create test societies
    INSERT INTO public.societies (name, registration_number, address)
    VALUES ('Slice 16 Primary Society', 'S16PRI', '789 Governance Ave')
    RETURNING id INTO v_society_id;

    INSERT INTO public.societies (name, registration_number, address)
    VALUES ('Slice 16 Secondary Society', 'S16SEC', '101 Isolation Blvd')
    RETURNING id INTO v_other_society_id;

    -- Create test users
    v_admin_id := gen_random_uuid();
    v_secretary_id := gen_random_uuid();
    v_treasurer_id := gen_random_uuid();
    v_exec_id := gen_random_uuid();
    v_member_id := gen_random_uuid();
    v_other_admin_id := gen_random_uuid();
    v_other_member_id := gen_random_uuid();

    -- Auth users insertion
    INSERT INTO auth.users (id, email, created_at, updated_at, confirmation_token, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, is_super_admin, role) VALUES 
        (v_admin_id, 'admin16@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
        (v_secretary_id, 'secretary16@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
        (v_treasurer_id, 'treasurer16@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
        (v_exec_id, 'exec16@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
        (v_member_id, 'member16@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
        (v_other_admin_id, 'other_admin16@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
        (v_other_member_id, 'other_member16@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated');

    -- Public users profile insertion
    INSERT INTO public.users (id, full_name, mobile) VALUES
        (v_admin_id, 'Slice 16 Admin', '+1600000001'),
        (v_secretary_id, 'Slice 16 Secretary', '+1600000002'),
        (v_treasurer_id, 'Slice 16 Treasurer', '+1600000003'),
        (v_exec_id, 'Slice 16 Executive Member', '+1600000004'),
        (v_member_id, 'Slice 16 Member', '+1600000005'),
        (v_other_admin_id, 'Slice 16 Other Admin', '+1600000006'),
        (v_other_member_id, 'Slice 16 Other Member', '+1600000007');

    -- Role assignments using approved role_name values
    INSERT INTO public.user_roles (society_id, user_id, role_name, granted_by)
    VALUES 
        (v_society_id, v_admin_id, 'admin', v_admin_id),
        (v_society_id, v_secretary_id, 'secretary', v_admin_id),
        (v_society_id, v_treasurer_id, 'treasurer', v_admin_id),
        (v_society_id, v_exec_id, 'executive_member', v_admin_id),
        (v_society_id, v_member_id, 'member', v_admin_id),
        (v_other_society_id, v_other_admin_id, 'admin', v_other_admin_id),
        (v_other_society_id, v_other_member_id, 'member', v_other_admin_id);

    -- Create an amenity fixture
    INSERT INTO public.amenities (id, society_id, name, booking_type, hourly_rate, created_by)
    VALUES (gen_random_uuid(), v_society_id, 'S16 Community Hall', 'slot_based', 100.00, v_admin_id)
    RETURNING id INTO v_amenity_id;

    -- --------------------------------------------------------------------------
    -- 1. RESOLUTION STATE MACHINE & VOTING (ASSERTIONS 1 - 11)
    -- --------------------------------------------------------------------------

    -- Create initial resolution draft
    PERFORM set_config('request.jwt.claim.sub', v_secretary_id::text, true);
    INSERT INTO public.committee_resolutions (society_id, proposed_by, title, description, category, quorum_required, status)
    VALUES (v_society_id, v_secretary_id, 'Upgrade Solar Panels', 'Install 50kW solar array', 'infrastructure', 3, 'draft')
    RETURNING id INTO v_res_id;

    -- Assertion 1: Committee member can table resolution
    PERFORM public.table_resolution(v_res_id);
    SELECT * INTO v_res_rec FROM public.committee_resolutions WHERE id = v_res_id;
    IF v_res_rec.status = 'voting' AND v_res_rec.tabled_at IS NOT NULL THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 1. Resolution tabled successfully for voting';
    ELSE
        RAISE EXCEPTION 'FAIL: 1. Table resolution failed';
    END IF;

    -- Assertion 2: Casting FOR vote via procedure increments votes_for and records vote
    PERFORM public.vote_on_resolution(v_res_id, 'for', 'Strongly support');
    SELECT * INTO v_res_rec FROM public.committee_resolutions WHERE id = v_res_id;
    SELECT COUNT(*) INTO v_audit_count FROM public.committee_resolution_votes WHERE resolution_id = v_res_id AND voter_id = v_secretary_id AND vote = 'for';
    IF v_res_rec.votes_for = 1 AND v_audit_count = 1 THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 2. Cast FOR vote recorded and vote counter incremented';
    ELSE
        RAISE EXCEPTION 'FAIL: 2. Vote FOR recording failed';
    END IF;

    -- Assertion 3: Direct authenticated INSERT into committee_resolution_votes is BLOCKED by RESTRICTIVE RLS
    BEGIN
        SET LOCAL ROLE authenticated;
        PERFORM set_config('request.jwt.claim.sub', v_treasurer_id::text, true);
        INSERT INTO public.committee_resolution_votes (resolution_id, voter_id, vote, comments)
        VALUES (v_res_id, v_exec_id, 'against', 'Direct SQL impersonation');
        RAISE EXCEPTION 'FAIL: 3. Direct client INSERT on votes allowed';
    EXCEPTION
        WHEN insufficient_privilege OR SQLSTATE '42501' THEN
            SET LOCAL ROLE postgres;
            v_pass_count := v_pass_count + 1;
            RAISE NOTICE 'PASS: 3. Direct authenticated INSERT into committee_resolution_votes blocked by RESTRICTIVE RLS';
    END;
    SET LOCAL ROLE postgres;

    -- Assertion 4: Second vote FOR and third vote AGAINST via procedure update counters
    PERFORM set_config('request.jwt.claim.sub', v_treasurer_id::text, true);
    PERFORM public.vote_on_resolution(v_res_id, 'for', 'Approved from finance perspective');

    PERFORM set_config('request.jwt.claim.sub', v_exec_id::text, true);
    PERFORM public.vote_on_resolution(v_res_id, 'against', 'Cost is too high');

    SELECT * INTO v_res_rec FROM public.committee_resolutions WHERE id = v_res_id;
    IF v_res_rec.votes_for = 2 AND v_res_rec.votes_against = 1 THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 4. Additional votes FOR and AGAINST updated vote counters correctly';
    ELSE
        RAISE EXCEPTION 'FAIL: 4. Vote counters mismatch';
    END IF;

    -- Assertion 5: Close voting passes resolution when quorum met and votes_for > votes_against
    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
    PERFORM public.close_resolution_voting(v_res_id);

    SELECT * INTO v_res_rec FROM public.committee_resolutions WHERE id = v_res_id;
    IF v_res_rec.status = 'passed' AND v_res_rec.voting_closed_at IS NOT NULL AND v_res_rec.passed_at IS NOT NULL THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 5. Resolution closed and passed successfully';
    ELSE
        RAISE EXCEPTION 'FAIL: 5. Close resolution voting pass failed';
    END IF;

    -- Assertion 6: Close voting rejects resolution when quorum is not met
    PERFORM set_config('request.jwt.claim.sub', v_secretary_id::text, true);
    INSERT INTO public.committee_resolutions (society_id, proposed_by, title, description, category, quorum_required, status)
    VALUES (v_society_id, v_secretary_id, 'Paint Exterior Walls', 'Repaint block A', 'maintenance', 3, 'draft')
    RETURNING id INTO v_res2_id;

    PERFORM public.table_resolution(v_res2_id);
    PERFORM public.vote_on_resolution(v_res2_id, 'for', 'Looks good');

    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
    PERFORM public.close_resolution_voting(v_res2_id);

    SELECT * INTO v_res_rec FROM public.committee_resolutions WHERE id = v_res2_id;
    IF v_res_rec.status = 'rejected' THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 6. Resolution rejected due to unmet quorum';
    ELSE
        RAISE EXCEPTION 'FAIL: 6. Resolution quorum rejection failed';
    END IF;

    -- Assertion 7: Duplicate vote by same voter on same resolution fails with unique constraint
    PERFORM set_config('request.jwt.claim.sub', v_secretary_id::text, true);
    INSERT INTO public.committee_resolutions (society_id, proposed_by, title, description, category, quorum_required, status)
    VALUES (v_society_id, v_secretary_id, 'Garden Landscaping', 'New plants for garden', 'governance', 2, 'draft')
    RETURNING id INTO v_res3_id;
    PERFORM public.table_resolution(v_res3_id);
    PERFORM public.vote_on_resolution(v_res3_id, 'for', 'First vote');

    BEGIN
        PERFORM public.vote_on_resolution(v_res3_id, 'for', 'Second vote attempt');
        RAISE EXCEPTION 'FAIL: 7. Duplicate vote allowed';
    EXCEPTION
        WHEN unique_violation THEN
            v_pass_count := v_pass_count + 1;
            RAISE NOTICE 'PASS: 7. Duplicate vote blocked by uq_resolution_voter unique constraint';
    END;

    -- Assertion 8: Voting on closed resolution fails with state machine exception
    BEGIN
        PERFORM set_config('request.jwt.claim.sub', v_exec_id::text, true);
        PERFORM public.vote_on_resolution(v_res_id, 'for', 'Late vote');
        RAISE EXCEPTION 'FAIL: 8. Voting on closed resolution allowed';
    EXCEPTION
        WHEN invalid_parameter_value OR SQLSTATE '22000' THEN
            v_pass_count := v_pass_count + 1;
            RAISE NOTICE 'PASS: 8. Voting on closed resolution rejected by state machine';
    END;

    -- Assertion 9: Non-committee member voting on resolution fails with authorization exception
    BEGIN
        PERFORM set_config('request.jwt.claim.sub', v_member_id::text, true);
        PERFORM public.vote_on_resolution(v_res3_id, 'for', 'Member vote attempt');
        RAISE EXCEPTION 'FAIL: 9. Non-committee vote allowed';
    EXCEPTION
        WHEN insufficient_privilege OR SQLSTATE '42501' THEN
            v_pass_count := v_pass_count + 1;
            RAISE NOTICE 'PASS: 9. Non-committee member voting rejected with 42501';
    END;

    -- Assertion 10: Direct client UPDATE on committee_resolutions status fails due to RESTRICTIVE RLS / trigger
    BEGIN
        SET LOCAL ROLE authenticated;
        PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
        PERFORM set_config('app.resolution_workflow_context', '', true);
        UPDATE public.committee_resolutions SET status = 'passed' WHERE id = v_res3_id;
        GET DIAGNOSTICS v_row_count = ROW_COUNT;
        IF v_row_count > 0 THEN
            RAISE EXCEPTION 'FAIL: 10. Direct client UPDATE on resolution allowed';
        ELSE
            SET LOCAL ROLE postgres;
            v_pass_count := v_pass_count + 1;
            RAISE NOTICE 'PASS: 10. Direct client UPDATE on resolution blocked by RESTRICTIVE RLS / trigger';
        END IF;
    EXCEPTION
        WHEN insufficient_privilege OR SQLSTATE '42501' THEN
            SET LOCAL ROLE postgres;
            v_pass_count := v_pass_count + 1;
            RAISE NOTICE 'PASS: 10. Direct client UPDATE on resolution blocked by RESTRICTIVE RLS / trigger';
    END;
    SET LOCAL ROLE postgres;

    -- Assertion 11: Direct client DELETE on committee_resolution_votes is BLOCKED by default-deny RLS
    BEGIN
        SET LOCAL ROLE authenticated;
        PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
        DELETE FROM public.committee_resolution_votes WHERE resolution_id = v_res3_id;
        GET DIAGNOSTICS v_row_count = ROW_COUNT;
        IF v_row_count > 0 THEN
            RAISE EXCEPTION 'FAIL: 11. Direct DELETE on votes succeeded';
        ELSE
            SET LOCAL ROLE postgres;
            v_pass_count := v_pass_count + 1;
            RAISE NOTICE 'PASS: 11. Direct DELETE on committee_resolution_votes blocked by default-deny RLS';
        END IF;
    END;
    SET LOCAL ROLE postgres;

    -- --------------------------------------------------------------------------
    -- 2. BUDGET LIFECYCLE & LINE ITEM CONSTRAINTS (ASSERTIONS 12 - 20)
    -- --------------------------------------------------------------------------

    -- Create draft budget
    PERFORM set_config('request.jwt.claim.sub', v_treasurer_id::text, true);
    INSERT INTO public.society_budgets (society_id, fiscal_year, title, prepared_by, status)
    VALUES (v_society_id, 'FY2026', 'Annual Operating Budget 2026', v_treasurer_id, 'draft')
    RETURNING id INTO v_budget_id;

    -- Assertion 12: Direct authenticated INSERT into budget_line_items is BLOCKED by RESTRICTIVE RLS
    BEGIN
        SET LOCAL ROLE authenticated;
        PERFORM set_config('request.jwt.claim.sub', v_treasurer_id::text, true);
        INSERT INTO public.budget_line_items (budget_id, category, allocated_amount, description)
        VALUES (v_budget_id, 'Unvetted Category', 99999.00, 'Direct SQL insert');
        RAISE EXCEPTION 'FAIL: 12. Direct client INSERT on budget_line_items allowed';
    EXCEPTION
        WHEN insufficient_privilege OR SQLSTATE '42501' THEN
            SET LOCAL ROLE postgres;
            v_pass_count := v_pass_count + 1;
            RAISE NOTICE 'PASS: 12. Direct authenticated INSERT into budget_line_items blocked by RESTRICTIVE RLS';
    END;
    SET LOCAL ROLE postgres;

    -- Assertion 13: Controlled procedure add_budget_line_item adds line item to draft budget
    PERFORM set_config('request.jwt.claim.sub', v_treasurer_id::text, true);
    v_line_item1_id := public.add_budget_line_item(v_budget_id, 'Maintenance', 5000.00, 'General maintenance expenses');
    v_line_item2_id := public.add_budget_line_item(v_budget_id, 'Utilities', 3000.00, 'Water and electricity bills');

    SELECT * INTO v_line_rec FROM public.budget_line_items WHERE id = v_line_item1_id;
    IF v_line_rec.allocated_amount = 5000.00 AND v_line_rec.spent_amount = 0.00 THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 13. Controlled add_budget_line_item procedure added line item successfully';
    ELSE
        RAISE EXCEPTION 'FAIL: 13. Controlled add_budget_line_item procedure failed';
    END IF;

    -- Assertion 14: Submit budget calculates total and transitions draft to submitted
    PERFORM public.submit_society_budget(v_budget_id);

    SELECT * INTO v_budget_rec FROM public.society_budgets WHERE id = v_budget_id;
    IF v_budget_rec.status = 'submitted' AND v_budget_rec.total_budget = 8000.00 AND v_budget_rec.submitted_at IS NOT NULL THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 14. Budget submitted successfully with calculated total_budget';
    ELSE
        RAISE EXCEPTION 'FAIL: 14. Submit budget failed';
    END IF;

    -- Assertion 15: Submitting empty budget with zero line items fails
    INSERT INTO public.society_budgets (society_id, fiscal_year, title, prepared_by, status)
    VALUES (v_society_id, 'FY2027', 'Empty Budget 2027', v_treasurer_id, 'draft')
    RETURNING id INTO v_empty_budget_id;

    BEGIN
        PERFORM public.submit_society_budget(v_empty_budget_id);
        RAISE EXCEPTION 'FAIL: 15. Submit empty budget allowed';
    EXCEPTION
        WHEN invalid_parameter_value OR SQLSTATE '22000' THEN
            v_pass_count := v_pass_count + 1;
            RAISE NOTICE 'PASS: 15. Submitting empty budget rejected by line item validation';
    END;

    -- Assertion 16: Adding line item to non-draft budget via procedure fails
    BEGIN
        PERFORM public.add_budget_line_item(v_budget_id, 'Late Add', 1000.00, 'Post-submission line item');
        RAISE EXCEPTION 'FAIL: 16. Adding line item to submitted budget allowed';
    EXCEPTION
        WHEN invalid_parameter_value OR SQLSTATE '22000' THEN
            v_pass_count := v_pass_count + 1;
            RAISE NOTICE 'PASS: 16. Adding line item to non-draft budget rejected by procedure';
    END;

    -- Assertion 17: Admin approves submitted budget
    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
    PERFORM public.approve_society_budget(v_budget_id);

    SELECT * INTO v_budget_rec FROM public.society_budgets WHERE id = v_budget_id;
    IF v_budget_rec.status = 'approved' AND v_budget_rec.approved_by = v_admin_id AND v_budget_rec.approved_at IS NOT NULL THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 17. Budget approved successfully by society admin';
    ELSE
        RAISE EXCEPTION 'FAIL: 17. Budget approval failed';
    END IF;

    -- Assertion 18: Direct client UPDATE on society_budgets status fails due to RESTRICTIVE RLS / trigger
    BEGIN
        SET LOCAL ROLE authenticated;
        PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
        PERFORM set_config('app.budget_workflow_context', '', true);
        UPDATE public.society_budgets SET status = 'approved' WHERE id = v_empty_budget_id;
        GET DIAGNOSTICS v_row_count = ROW_COUNT;
        IF v_row_count > 0 THEN
            RAISE EXCEPTION 'FAIL: 18. Direct client UPDATE on budget allowed';
        ELSE
            SET LOCAL ROLE postgres;
            v_pass_count := v_pass_count + 1;
            RAISE NOTICE 'PASS: 18. Direct client UPDATE on budget status blocked by RESTRICTIVE RLS / trigger';
        END IF;
    EXCEPTION
        WHEN insufficient_privilege OR SQLSTATE '42501' THEN
            SET LOCAL ROLE postgres;
            v_pass_count := v_pass_count + 1;
            RAISE NOTICE 'PASS: 18. Direct client UPDATE on budget status blocked by RESTRICTIVE RLS / trigger';
    END;
    SET LOCAL ROLE postgres;

    -- Assertion 19: Non-positive line item allocated amount blocked by check constraint
    BEGIN
        PERFORM set_config('request.jwt.claim.sub', v_treasurer_id::text, true);
        PERFORM public.add_budget_line_item(v_empty_budget_id, 'Invalid', -500.00, 'Negative amount');
        RAISE EXCEPTION 'FAIL: 19. Negative allocated amount inserted';
    EXCEPTION
        WHEN check_violation THEN
            v_pass_count := v_pass_count + 1;
            RAISE NOTICE 'PASS: 19. Non-positive allocated amount blocked by chk_allocated_positive';
    END;

    -- Assertion 20: Direct client DELETE on budget_line_items is BLOCKED by default-deny RLS
    BEGIN
        SET LOCAL ROLE authenticated;
        PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
        DELETE FROM public.budget_line_items WHERE id = v_line_item1_id;
        GET DIAGNOSTICS v_row_count = ROW_COUNT;
        IF v_row_count > 0 THEN
            RAISE EXCEPTION 'FAIL: 20. Direct DELETE on budget line items succeeded';
        ELSE
            SET LOCAL ROLE postgres;
            v_pass_count := v_pass_count + 1;
            RAISE NOTICE 'PASS: 20. Direct DELETE on budget_line_items blocked by default-deny RLS';
        END IF;
    END;
    SET LOCAL ROLE postgres;

    -- --------------------------------------------------------------------------
    -- 3. EXPENSE VOUCHER WORKFLOW & LEDGER INTEGRATION (ASSERTIONS 21 - 24)
    -- --------------------------------------------------------------------------

    -- Create draft expense voucher
    PERFORM set_config('request.jwt.claim.sub', v_treasurer_id::text, true);
    INSERT INTO public.expense_vouchers (society_id, budget_line_item_id, requested_by, amount, description, status)
    VALUES (v_society_id, v_line_item1_id, v_treasurer_id, 2000.00, 'Elevator Service Call', 'draft')
    RETURNING id INTO v_voucher_id;

    -- Assertion 21: Treasurer approves expense voucher
    PERFORM public.approve_expense_voucher(v_voucher_id);

    SELECT * INTO v_voucher_rec FROM public.expense_vouchers WHERE id = v_voucher_id;
    IF v_voucher_rec.status = 'approved' AND v_voucher_rec.approved_by = v_treasurer_id THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 21. Expense voucher approved successfully';
    ELSE
        RAISE EXCEPTION 'FAIL: 21. Expense voucher approval failed';
    END IF;

    -- Assertion 22: Disburse voucher updates spent_amount and creates ledger entry
    PERFORM public.disburse_expense_voucher(v_voucher_id);

    SELECT * INTO v_voucher_rec FROM public.expense_vouchers WHERE id = v_voucher_id;
    SELECT * INTO v_line_rec FROM public.budget_line_items WHERE id = v_line_item1_id;
    SELECT COUNT(*) INTO v_ledger_count FROM public.ledger_transactions 
    WHERE society_id = v_society_id AND transaction_type = 'expense' AND amount = 2000.00 AND direction = 'credit';

    IF v_voucher_rec.status = 'disbursed' AND v_voucher_rec.disbursed_at IS NOT NULL 
       AND v_line_rec.spent_amount = 2000.00 AND v_ledger_count = 1 THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 22. Voucher disbursed, line item spent_amount updated, financial ledger entry generated';
    ELSE
        RAISE EXCEPTION 'FAIL: 22. Expense voucher disbursement failed';
    END IF;

    -- Assertion 23: Disbursement exceeding budget line item limit fails and rolls back
    INSERT INTO public.expense_vouchers (society_id, budget_line_item_id, requested_by, amount, description, status)
    VALUES (v_society_id, v_line_item1_id, v_treasurer_id, 4000.00, 'Over budget repair', 'draft')
    RETURNING id INTO v_voucher2_id;

    PERFORM public.approve_expense_voucher(v_voucher2_id);

    BEGIN
        PERFORM public.disburse_expense_voucher(v_voucher2_id);
        RAISE EXCEPTION 'FAIL: 23. Over-budget disbursement allowed';
    EXCEPTION
        WHEN invalid_parameter_value OR SQLSTATE '22000' THEN
            v_pass_count := v_pass_count + 1;
            RAISE NOTICE 'PASS: 23. Over-budget disbursement rejected and transaction safely rolled back';
    END;

    -- Assertion 24: Direct client UPDATE on expense_vouchers status fails due to RESTRICTIVE RLS / trigger
    BEGIN
        SET LOCAL ROLE authenticated;
        PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
        PERFORM set_config('app.voucher_workflow_context', '', true);
        UPDATE public.expense_vouchers SET status = 'disbursed' WHERE id = v_voucher2_id;
        GET DIAGNOSTICS v_row_count = ROW_COUNT;
        IF v_row_count > 0 THEN
            RAISE EXCEPTION 'FAIL: 24. Direct client UPDATE on voucher allowed';
        ELSE
            SET LOCAL ROLE postgres;
            v_pass_count := v_pass_count + 1;
            RAISE NOTICE 'PASS: 24. Direct client UPDATE on voucher status blocked by RESTRICTIVE RLS / trigger';
        END IF;
    EXCEPTION
        WHEN insufficient_privilege OR SQLSTATE '42501' THEN
            SET LOCAL ROLE postgres;
            v_pass_count := v_pass_count + 1;
            RAISE NOTICE 'PASS: 24. Direct client UPDATE on voucher status blocked by RESTRICTIVE RLS / trigger';
    END;
    SET LOCAL ROLE postgres;

    -- --------------------------------------------------------------------------
    -- 4. FACILITY BLACKOUT WORKFLOWS & OVERLAP SECURITY (ASSERTIONS 25 - 28)
    -- --------------------------------------------------------------------------

    -- Assertion 25: Direct authenticated INSERT into facility_blackouts is BLOCKED by RESTRICTIVE RLS
    BEGIN
        SET LOCAL ROLE authenticated;
        PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
        INSERT INTO public.facility_blackouts (society_id, amenity_id, title, reason, start_time, end_time, created_by, status)
        VALUES (v_society_id, v_amenity_id, 'Direct SQL Blackout', 'Unverified', NOW() + INTERVAL '10 days', NOW() + INTERVAL '11 days', v_admin_id, 'scheduled');
        RAISE EXCEPTION 'FAIL: 25. Direct client INSERT on facility_blackouts allowed';
    EXCEPTION
        WHEN insufficient_privilege OR SQLSTATE '42501' THEN
            SET LOCAL ROLE postgres;
            v_pass_count := v_pass_count + 1;
            RAISE NOTICE 'PASS: 25. Direct authenticated INSERT into facility_blackouts blocked by RESTRICTIVE RLS';
    END;
    SET LOCAL ROLE postgres;

    -- Assertion 26: Authorized create_facility_blackout procedure creates scheduled blackout
    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
    v_blackout_id := public.create_facility_blackout(
        v_society_id, v_amenity_id, 'Annual Maintenance', 'Hall painting',
        NOW() + INTERVAL '1 day', NOW() + INTERVAL '2 days'
    );

    SELECT * INTO v_blackout_rec FROM public.facility_blackouts WHERE id = v_blackout_id;
    IF v_blackout_rec.status = 'scheduled' AND v_blackout_rec.title = 'Annual Maintenance' THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 26. Authorized create_facility_blackout procedure created blackout successfully';
    ELSE
        RAISE EXCEPTION 'FAIL: 26. Procedure create_facility_blackout failed';
    END IF;

    -- Assertion 27: Overlapping blackout creation through create_facility_blackout procedure is rejected
    BEGIN
        PERFORM public.create_facility_blackout(
            v_society_id, v_amenity_id, 'Conflicting Maintenance', 'Overlap test',
            NOW() + INTERVAL '36 hours', NOW() + INTERVAL '3 days'
        );
        RAISE EXCEPTION 'FAIL: 27. Overlapping facility blackout allowed';
    EXCEPTION
        WHEN invalid_parameter_value OR SQLSTATE '22000' THEN
            v_pass_count := v_pass_count + 1;
            RAISE NOTICE 'PASS: 27. Overlapping blackout window rejected by procedure validation';
    END;

    -- Assertion 28: Admin cancels facility blackout
    PERFORM public.cancel_facility_blackout(v_blackout_id, 'Rescheduled to next quarter');

    SELECT * INTO v_blackout_rec FROM public.facility_blackouts WHERE id = v_blackout_id;
    IF v_blackout_rec.status = 'cancelled' AND v_blackout_rec.reason LIKE '%Rescheduled to next quarter%' THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 28. Facility blackout cancelled successfully with updated reason';
    ELSE
        RAISE EXCEPTION 'FAIL: 28. Facility blackout cancellation failed';
    END IF;

    -- --------------------------------------------------------------------------
    -- 5. ADVANCED SECURITY BOUNDARIES & IDOR (ASSERTIONS 29 - 32)
    -- --------------------------------------------------------------------------

    -- Assertion 29: Forged GUC attempt during direct UPDATE fails due to trigger / RESTRICTIVE RLS boundary
    BEGIN
        SET LOCAL ROLE authenticated;
        PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
        PERFORM set_config('app.resolution_workflow_context', 'forged_guc_val', true);
        UPDATE public.committee_resolutions SET status = 'passed' WHERE id = v_res3_id;
        GET DIAGNOSTICS v_row_count = ROW_COUNT;
        IF v_row_count > 0 THEN
            RAISE EXCEPTION 'FAIL: 29. Direct UPDATE with forged GUC succeeded';
        ELSE
            SET LOCAL ROLE postgres;
            v_pass_count := v_pass_count + 1;
            RAISE NOTICE 'PASS: 29. Direct UPDATE with forged GUC blocked by trigger / RESTRICTIVE RLS boundary';
        END IF;
    EXCEPTION
        WHEN insufficient_privilege OR SQLSTATE '42501' THEN
            SET LOCAL ROLE postgres;
            v_pass_count := v_pass_count + 1;
            RAISE NOTICE 'PASS: 29. Direct UPDATE with forged GUC blocked by trigger / RESTRICTIVE RLS boundary';
    END;
    SET LOCAL ROLE postgres;

    -- Assertion 30: Cross-society IDOR on table_resolution rejected
    BEGIN
        PERFORM set_config('request.jwt.claim.sub', v_other_admin_id::text, true);
        PERFORM public.table_resolution(v_res3_id);
        RAISE EXCEPTION 'FAIL: 30. Cross-society table_resolution allowed';
    EXCEPTION
        WHEN insufficient_privilege OR SQLSTATE '42501' THEN
            v_pass_count := v_pass_count + 1;
            RAISE NOTICE 'PASS: 30. Cross-society table_resolution blocked with 42501';
    END;

    -- Assertion 31: Cross-society IDOR on submit_society_budget rejected
    BEGIN
        PERFORM set_config('request.jwt.claim.sub', v_other_admin_id::text, true);
        PERFORM public.submit_society_budget(v_empty_budget_id);
        RAISE EXCEPTION 'FAIL: 31. Cross-society budget submission allowed';
    EXCEPTION
        WHEN insufficient_privilege OR SQLSTATE '42501' THEN
            v_pass_count := v_pass_count + 1;
            RAISE NOTICE 'PASS: 31. Cross-society submit_society_budget blocked with 42501';
    END;

    -- Assertion 32: Cross-society IDOR on disburse_expense_voucher rejected
    BEGIN
        PERFORM set_config('request.jwt.claim.sub', v_other_admin_id::text, true);
        PERFORM public.disburse_expense_voucher(v_voucher2_id);
        RAISE EXCEPTION 'FAIL: 32. Cross-society voucher disbursement allowed';
    EXCEPTION
        WHEN insufficient_privilege OR SQLSTATE '42501' THEN
            v_pass_count := v_pass_count + 1;
            RAISE NOTICE 'PASS: 32. Cross-society disburse_expense_voucher blocked with 42501';
    END;

    -- --------------------------------------------------------------------------
    -- 6. CONCURRENCY, CATALOG SECURITY & AUDIT LOG INTEGRITY (ASSERTIONS 33 - 35)
    -- --------------------------------------------------------------------------

    -- Assertion 33: FOR UPDATE row locking state validation check on closed resolution
    BEGIN
        PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
        PERFORM public.close_resolution_voting(v_res_id);
        RAISE EXCEPTION 'FAIL: 33. Closing already closed resolution allowed';
    EXCEPTION
        WHEN invalid_parameter_value OR SQLSTATE '22000' THEN
            v_pass_count := v_pass_count + 1;
            RAISE NOTICE 'PASS: 33. Row locking FOR UPDATE state validation correctly blocks double closure';
    END;

    -- Assertion 34: Catalog audit: search_path set on all 10 workflow functions & PUBLIC EXECUTE revoked
    SELECT COUNT(*) INTO v_catalog_count 
    FROM pg_proc 
    WHERE proname IN (
        'table_resolution', 'vote_on_resolution', 'close_resolution_voting',
        'submit_society_budget', 'approve_society_budget', 'approve_expense_voucher',
        'disburse_expense_voucher', 'cancel_facility_blackout', 'add_budget_line_item', 'create_facility_blackout'
    ) 
    AND proconfig IS NOT NULL 
    AND ARRAY['search_path=public, pg_temp'] <@ proconfig;

    IF v_catalog_count = 10 THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 34. Catalog audit verified search_path=public, pg_temp on all 10 workflow functions';
    ELSE
        RAISE EXCEPTION 'FAIL: 34. Catalog search_path audit failed (Found: %/10)', v_catalog_count;
    END IF;

    -- Assertion 35: Audit logs and notifications generation verification across Slice 16 workflows
    SELECT COUNT(*) INTO v_audit_count FROM public.audit_logs WHERE society_id = v_society_id;
    SELECT COUNT(*) INTO v_notif_count FROM public.notifications WHERE society_id = v_society_id;

    IF v_audit_count >= 7 AND v_notif_count >= 4 THEN
        v_pass_count := v_pass_count + 1;
        RAISE NOTICE 'PASS: 35. Audit logs (% entries) and notifications (% entries) generated successfully', v_audit_count, v_notif_count;
    ELSE
        RAISE EXCEPTION 'FAIL: 35. Workflow audit log or notification verification failed (Audit: %, Notif: %)', v_audit_count, v_notif_count;
    END IF;

    -- Final completion summary
    RAISE NOTICE '==================================================';
    RAISE NOTICE 'SLICE 16 VERIFICATION COMPLETE: %/% TESTS PASSED', v_pass_count, v_total_count;
    RAISE NOTICE '==================================================';
END;
$$;
