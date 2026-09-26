
-- =========================================================================
-- SU SOCIETY APP - SLICE 4 VERIFICATION SUITE
-- =========================================================================

\set ON_ERROR_STOP on

DO $$
DECLARE
    -- Actor UUIDs (reusing exact from Slice 1)
    admin_a UUID := 'a1000000-0000-0000-0000-000000000010';
    admin_b UUID := 'b1000000-0000-0000-0000-000000000010';
    owner_a_1 UUID := 'a2000000-0000-0000-0000-000000000021';
    owner_a_2 UUID := 'a2000000-0000-0000-0000-000000000022';
    
    -- Entities
    soc_a UUID := 'a0000000-0000-0000-0000-000000000000';
    soc_b UUID := 'b0000000-0000-0000-0000-000000000000';
    prop_a1 UUID := 'a4000000-0000-0000-0000-000000000041';
    prop_a2 UUID := 'a4000000-0000-0000-0000-000000000042';
    
    -- New test entities
    chg_a1_1 UUID := 'd6000000-0000-0000-0000-000000000001';
    chg_a1_2 UUID := 'd6000000-0000-0000-0000-000000000002';
    pay_a1 UUID := 'd1000000-0000-0000-0000-000000000001';
    pay_cross UUID := 'd1000000-0000-0000-0000-000000000002';
    
    exp_cat UUID := 'd7000000-0000-0000-0000-000000000001';
    exp_cat_b UUID := 'd7000000-0000-0000-0000-000000000002';
    vouch_1 UUID := 'd2000000-0000-0000-0000-000000000001';
    vouch_2 UUID := 'd2000000-0000-0000-0000-000000000002';
    
    recon_1 UUID := 'd3000000-0000-0000-0000-000000000001';
    
    -- Temp vars
    v_receipt_id UUID;
    v_ob_id UUID;
    v_tx_id UUID;
    v_count INT;
    v_sum NUMERIC;
BEGIN
    RAISE NOTICE '--- STARTING SLICE 4 TESTS ---';

    -- Setup: Make sure we have some active charges to allocate against.
    -- (We will insert directly as admin to speed up setup)
    PERFORM set_config('request.jwt.claims', json_build_object('sub', 'a1000000-0000-0000-0000-000000000010')::text, true);
    -- Insert Societies
    INSERT INTO public.societies (id, name, registration_number, address) VALUES 
        (soc_a, 'Soc A', 'REG-A', 'Add A'),
        (soc_b, 'Soc B', 'REG-B', 'Add B');

    -- Insert auth.users
    INSERT INTO auth.users (id, email, created_at, updated_at, confirmation_token, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, is_super_admin, role)
    VALUES 
        (admin_a, 'admina@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
        (admin_b, 'adminb@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
        (owner_a_1, 'ownera1@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
        (owner_a_2, 'ownera2@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated');

    -- Insert public.users
    INSERT INTO public.users (id, full_name, mobile) VALUES 
        (admin_a, 'Admin A', '1111111111'),
        (admin_b, 'Admin B', '2222222222'),
        (owner_a_1, 'Owner A1', '3333333333'),
        (owner_a_2, 'Owner A2', '4444444444');

    -- Roles
    INSERT INTO public.user_roles (user_id, society_id, role_name, granted_by) VALUES 
        (admin_a, soc_a, 'super_admin', admin_a),
        (admin_b, soc_b, 'super_admin', admin_b),
        (owner_a_1, soc_a, 'member', admin_a),
        (owner_a_2, soc_a, 'member', admin_a);

    -- Properties
    INSERT INTO public.properties (id, society_id, plot_number, plot_size_sqft, construction_status, occupancy_status, created_by) VALUES 
        (prop_a1, soc_a, 'Plot 1', 1000, 'constructed', 'owner_occupied', admin_a),
        (prop_a2, soc_a, 'Plot 2', 1000, 'constructed', 'owner_occupied', admin_a);

INSERT INTO public.maintenance_policies (id, society_id, name, billing_cycle, charge_type, rate, created_by)
    VALUES ('d5000000-0000-0000-0000-000000000000', soc_a, 'Slice4 Policy', 'monthly', 'fixed', 1000.00, admin_a);
    
    INSERT INTO public.maintenance_charges (id, society_id, policy_id, property_id, amount, status, billing_period, billing_basis_snapshot, created_by)
    VALUES 
        (chg_a1_1, soc_a, 'd5000000-0000-0000-0000-000000000000', prop_a1, 1000.00, 'posted', '2026-09', '{}', admin_a),
        (chg_a1_2, soc_a, 'd5000000-0000-0000-0000-000000000000', prop_a1, 500.00, 'posted', '2026-10', '{}', admin_a);

    PERFORM set_config('request.jwt.claims', '{}'::text, true);

    -- =========================================================================
    -- TEST 1: PAYMENT SUBMISSION & ALLOCATIONS
    -- =========================================================================
    RAISE NOTICE 'Test 1: Payment Allocations';
    
    -- Member owner_a_1 submits payment
    PERFORM set_config('request.jwt.claims', json_build_object('sub', 'a2000000-0000-0000-0000-000000000021')::text, true);
    INSERT INTO public.payments (id, society_id, property_id, amount, payment_method, reference_number, posted_at, created_by)
    VALUES (pay_a1, soc_a, prop_a1, 1500.00, 'upi', 'TXN-001', CURRENT_TIMESTAMP, owner_a_1);
    
    -- Member attempts verification (unauthorized)
    BEGIN
        PERFORM public.fn_verify_payment_with_allocation(pay_a1, '[{"charge_id": "d6000000-0000-0000-0000-000000000001", "amount": 1000}]'::jsonb);
        RAISE EXCEPTION 'FAIL: Member verified payment';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%Access Denied%' THEN RAISE EXCEPTION 'FAIL: Expected Access Denied, got %', SQLERRM; END IF;
    END;

    PERFORM set_config('request.jwt.claims', '{}'::text, true);
    
    -- Admin B (Cross-society) attempts verification
    PERFORM set_config('request.jwt.claims', json_build_object('sub', 'b1000000-0000-0000-0000-000000000010')::text, true);
    BEGIN
        PERFORM public.fn_verify_payment_with_allocation(pay_a1, '[{"charge_id": "d6000000-0000-0000-0000-000000000001", "amount": 1000}]'::jsonb);
        RAISE EXCEPTION 'FAIL: Cross-society verification succeeded';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%Cross-society denied%' THEN RAISE EXCEPTION 'FAIL: Expected cross-society error, got %', SQLERRM; END IF;
    END;

    PERFORM set_config('request.jwt.claims', '{}'::text, true);
    
    -- Admin A verifies with over-allocation of payment
    PERFORM set_config('request.jwt.claims', json_build_object('sub', 'a1000000-0000-0000-0000-000000000010')::text, true);
    BEGIN
        PERFORM public.fn_verify_payment_with_allocation(pay_a1, '[{"charge_id": "d6000000-0000-0000-0000-000000000001", "amount": 1000}, {"charge_id": "d6000000-0000-0000-0000-000000000002", "amount": 1000}]'::jsonb);
        RAISE EXCEPTION 'FAIL: Allowed allocation > payment amount';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%Allocation exceeds outstanding charge balance%' AND SQLERRM NOT LIKE '%Allocations exceed total payment amount%' THEN RAISE EXCEPTION 'FAIL: Expected alloc error, got %', SQLERRM; END IF;
    END;
    
    -- Admin A verifies with over-allocation of charge balance
    BEGIN
        PERFORM public.fn_verify_payment_with_allocation(pay_a1, '[{"charge_id": "d6000000-0000-0000-0000-000000000001", "amount": 1500}]'::jsonb);
        RAISE EXCEPTION 'FAIL: Allowed allocation > charge balance';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%Allocation exceeds outstanding charge balance%' THEN RAISE EXCEPTION 'FAIL: Expected alloc balance error, got %', SQLERRM; END IF;
    END;
    
    -- Admin A successfully verifies payment and generates receipt
    SELECT public.fn_verify_payment_with_allocation(pay_a1, '[{"charge_id": "d6000000-0000-0000-0000-000000000001", "amount": 1000}, {"charge_id": "d6000000-0000-0000-0000-000000000002", "amount": 500}]'::jsonb) INTO v_receipt_id;
    
    SELECT COUNT(*) INTO v_count FROM public.receipts WHERE payment_id = pay_a1;
    IF v_count != 1 THEN RAISE EXCEPTION 'FAIL: Receipt not created'; END IF;
    
    SELECT COUNT(*) INTO v_count FROM public.ledger_transactions WHERE source_payment_id = pay_a1;
    IF v_count != 1 THEN RAISE EXCEPTION 'FAIL: Ledger posting not exactly 1 for payment'; END IF;
    
    -- Duplicate verification
    BEGIN
        PERFORM public.fn_verify_payment_with_allocation(pay_a1, '[{"charge_id": "d6000000-0000-0000-0000-000000000001", "amount": 1000}]'::jsonb);
        RAISE EXCEPTION 'FAIL: Allowed duplicate verification';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%Invalid transition%' THEN RAISE EXCEPTION 'FAIL: Expected transition error, got %', SQLERRM; END IF;
    END;
    
    -- Payment reversal logic from Slice 2 should still work, but we verify it reverses exactly 1 posting
    PERFORM public.fn_reverse_payment(pay_a1, 'cheque_bounced');
    SELECT COUNT(*) INTO v_count FROM public.payments WHERE id = pay_a1 AND status = 'reversed';
    IF v_count != 1 THEN RAISE EXCEPTION 'FAIL: Payment not reversed'; END IF;
    
    SELECT COUNT(*) INTO v_count FROM public.ledger_transactions WHERE transaction_type = 'reversal' AND reverses_ledger_id = (SELECT id FROM public.ledger_transactions WHERE source_payment_id = pay_a1);
    IF v_count != 1 THEN RAISE EXCEPTION 'FAIL: Compensating ledger reversal not found'; END IF;

    -- =========================================================================
    -- TEST 2: EXPENSES
    -- =========================================================================
    RAISE NOTICE 'Test 2: Expense Vouchers';
    
    INSERT INTO public.expense_categories (id, society_id, name) VALUES (exp_cat, soc_a, 'Repairs');
    INSERT INTO public.expense_categories (id, society_id, name) VALUES (exp_cat_b, soc_b, 'Admin B repairs');
    
    -- Member creates voucher
    PERFORM set_config('request.jwt.claims', json_build_object('sub', 'a2000000-0000-0000-0000-000000000021')::text, true);
    INSERT INTO public.expense_vouchers (id, society_id, category_id, amount, vendor_name, invoice_number, invoice_date, payment_method, created_by)
    VALUES (vouch_1, soc_a, exp_cat, 5000.00, 'Vendor A', 'INV-001', CURRENT_DATE, 'bank_transfer', owner_a_1);
    
    -- Member attempts to approve
    BEGIN
        PERFORM public.fn_transition_voucher_state(vouch_1, 'approved');
        RAISE EXCEPTION 'FAIL: Member approved voucher';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%Access Denied%' THEN RAISE EXCEPTION 'FAIL: Expected Access Denied, got %', SQLERRM; END IF;
    END;
    
    -- Admin B attempts to approve cross-society
    PERFORM set_config('request.jwt.claims', json_build_object('sub', 'b1000000-0000-0000-0000-000000000010')::text, true);
    BEGIN
        PERFORM public.fn_transition_voucher_state(vouch_1, 'approved');
        RAISE EXCEPTION 'FAIL: Cross-society voucher approval succeeded';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%Cross-society denied%' THEN RAISE EXCEPTION 'FAIL: Expected cross-society error, got %', SQLERRM; END IF;
    END;
    
    -- Admin A approves and posts
    PERFORM set_config('request.jwt.claims', json_build_object('sub', 'a1000000-0000-0000-0000-000000000010')::text, true);
    PERFORM public.fn_transition_voucher_state(vouch_1, 'approved');
    PERFORM public.fn_transition_voucher_state(vouch_1, 'posted');
    
    SELECT COUNT(*) INTO v_count FROM public.ledger_transactions WHERE source_voucher_id = vouch_1;
    IF v_count != 1 THEN RAISE EXCEPTION 'FAIL: Ledger debit not exactly 1 for voucher'; END IF;
    
    -- Duplicate posting
    BEGIN
        PERFORM public.fn_transition_voucher_state(vouch_1, 'posted');
        RAISE EXCEPTION 'FAIL: Allowed duplicate voucher posting';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%Invalid transition%' THEN RAISE EXCEPTION 'FAIL: Expected transition error, got %', SQLERRM; END IF;
    END;
    
    -- Reversal
    PERFORM public.fn_transition_voucher_state(vouch_1, 'reversed', 'Wrong amount');
    SELECT COUNT(*) INTO v_count FROM public.ledger_transactions WHERE transaction_type = 'reversal' AND reverses_ledger_id = (SELECT id FROM public.ledger_transactions WHERE source_voucher_id = vouch_1);
    IF v_count != 1 THEN RAISE EXCEPTION 'FAIL: Voucher compensating reversal not found'; END IF;
    
    -- =========================================================================
    -- TEST 3: RECONCILIATION & LEDGER IMMUTABILITY
    -- =========================================================================
    RAISE NOTICE 'Test 3: Reconciliation';
    
    -- Create some arbitrary ledger transactions (we'll just use adjustments to avoid complex setup)
    INSERT INTO public.ledger_transactions (id, society_id, scope, amount, direction, transaction_type, description, created_by, source_payment_id)
    VALUES ('d4000000-0000-0000-0000-000000000001', soc_a, 'society', 1000.00, 'credit', 'payment', 'Test 1', admin_a, pay_a1);
    
    INSERT INTO public.bank_reconciliations (id, society_id, bank_statement_date, opening_balance, closing_balance)
    VALUES (recon_1, soc_a, CURRENT_DATE, 0, 1000.00);
    
    -- Admin B attempts cross-society match
    PERFORM set_config('request.jwt.claims', json_build_object('sub', 'b1000000-0000-0000-0000-000000000010')::text, true);
    BEGIN
        PERFORM public.fn_reconcile_transactions(recon_1, ARRAY['d4000000-0000-0000-0000-000000000001'::uuid]);
        RAISE EXCEPTION 'FAIL: Cross-society reconciliation succeeded';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%Cross-society denied%' THEN RAISE EXCEPTION 'FAIL: Expected cross-society error, got %', SQLERRM; END IF;
    END;
    
    PERFORM set_config('request.jwt.claims', json_build_object('sub', 'a1000000-0000-0000-0000-000000000010')::text, true);
    
    -- Match transaction
    PERFORM public.fn_reconcile_transactions(recon_1, ARRAY['d4000000-0000-0000-0000-000000000001'::uuid]);
    
    -- Duplicate matching
    BEGIN
        PERFORM public.fn_reconcile_transactions(recon_1, ARRAY['d4000000-0000-0000-0000-000000000001'::uuid]);
        RAISE EXCEPTION 'FAIL: Allowed duplicate matching in same recon';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%duplicate key value violates unique constraint%' THEN RAISE EXCEPTION 'FAIL: Expected unique constraint error, got %', SQLERRM; END IF;
    END;
    
    -- Complete recon
    PERFORM public.fn_complete_reconciliation(recon_1);
    
    -- Attempt mutation of completed
    BEGIN
        UPDATE public.bank_reconciliations SET opening_balance = 500 WHERE id = recon_1;
        RAISE EXCEPTION 'FAIL: Allowed mutation of completed reconciliation';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%Cannot modify completed reconciliation%' THEN RAISE EXCEPTION 'FAIL: Expected immutable recon error, got %', SQLERRM; END IF;
    END;
    
    -- Attempt direct ledger DELETE (must remain blocked by Slice 2)
    BEGIN
        DELETE FROM public.ledger_transactions WHERE id = 'd4000000-0000-0000-0000-000000000001';
        RAISE EXCEPTION 'FAIL: Allowed direct ledger DELETE';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%Immutable record%' THEN RAISE EXCEPTION 'FAIL: Expected immutable ledger error on DELETE, got %', SQLERRM; END IF;
    END;

    -- Attempt direct ledger UPDATE (must remain blocked by Slice 2)
    BEGIN
        UPDATE public.ledger_transactions SET amount = 2000 WHERE id = 'd4000000-0000-0000-0000-000000000001';
        RAISE EXCEPTION 'FAIL: Allowed direct ledger UPDATE';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%Immutable record%' THEN RAISE EXCEPTION 'FAIL: Expected immutable ledger error on UPDATE, got %', SQLERRM; END IF;
    END;

    -- =========================================================================
    -- TEST 4: OPENING BALANCES
    -- =========================================================================
    RAISE NOTICE 'Test 4: Opening Balances';
    -- Attempt insert
    BEGIN
        v_ob_id := public.fn_book_opening_balance(prop_a1, owner_a_1, 5000.00, 'debit', CURRENT_DATE);
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'FAIL: Opening balance insert failed: %', SQLERRM;
    END;
    
    -- Duplicate posting
    BEGIN
        PERFORM public.fn_book_opening_balance(prop_a1, owner_a_1, 1000.00, 'debit', CURRENT_DATE);
        RAISE EXCEPTION 'FAIL: Allowed duplicate opening balance';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%duplicate key value violates unique constraint%' THEN RAISE EXCEPTION 'FAIL: Expected unique constraint error, got %', SQLERRM; END IF;
    END;
    
    -- Attempt mutation
    BEGIN
        UPDATE public.opening_balances SET amount = 10000 WHERE id = v_ob_id;
        RAISE EXCEPTION 'FAIL: Allowed OB update';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%Immutable record%' THEN RAISE EXCEPTION 'FAIL: Expected immutable error, got %', SQLERRM; END IF;
    END;

    -- =========================================================================
    -- TEST 5: NOTIFICATIONS & RLS
    -- =========================================================================
    RAISE NOTICE 'Test 5: Notifications & RLS';
    
    PERFORM set_config('role', 'authenticated', true);
    
    -- Admin A can see the notification generated by verification
    SELECT COUNT(*) INTO v_count FROM public.notifications WHERE society_id = soc_a;
    IF v_count < 1 THEN RAISE EXCEPTION 'FAIL: Notification was not created'; END IF;
    
    PERFORM set_config('request.jwt.claims', '{}'::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', 'b1000000-0000-0000-0000-000000000010')::text, true);
    SELECT COUNT(*) INTO v_count FROM public.notifications;
    IF v_count != 0 THEN RAISE EXCEPTION 'FAIL: Admin B saw Admin A notifications'; END IF;
    
    PERFORM set_config('request.jwt.claims', '{}'::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', 'a2000000-0000-0000-0000-000000000021')::text, true);
    SELECT COUNT(*) INTO v_count FROM public.notifications;
    IF v_count < 1 THEN RAISE EXCEPTION 'FAIL: User could not see their own notification'; END IF;

    RAISE NOTICE '--- SLICE 4 TESTS PASSED ---';
END;
$$;
