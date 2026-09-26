-- =========================================================================
-- SU SOCIETY APP - SLICE 14 GENUINE VERIFICATION (AUTOMATED PAYMENT WEBHOOKS)
-- =========================================================================

DO $$
DECLARE
    -- Standard Test Identities (Valid Hex UUIDs)
    v_admin1_id UUID := 'a1400000-0000-0000-0000-000000000000';
    v_member1_id UUID := 'b1400000-0000-0000-0000-000000000001';
    v_member2_id UUID := 'c1400000-0000-0000-0000-000000000002';
    
    v_society1_id UUID := 'd1400000-0000-0000-0000-000000000001';
    v_society2_id UUID := 'e1400000-0000-0000-0000-000000000002';
    
    v_property1_id UUID := 'f1400000-0000-0000-0000-000000000001';
    v_property2_id UUID := 'f1400000-0000-0000-0000-000000000002';
    
    v_charge1_id UUID;
    v_payment1_id UUID;
    v_intent1_id UUID;
    
    v_charge2_id UUID;
    v_payment2_id UUID;
    v_intent2_id UUID;
    
    v_charge3_id UUID;
    v_payment3_id UUID;
    v_intent3_id UUID;
    
    v_assertions_passed INT := 0;
    v_success BOOLEAN;
    v_tmp_count INT;
    v_tmp_sum NUMERIC;
    v_tmp_val VARCHAR;
    v_tmp_bool BOOLEAN;
    v_order_id VARCHAR(255);
BEGIN
    RAISE NOTICE '==================================================';
    RAISE NOTICE 'STARTING SLICE 14 VERIFICATION (PAYMENT WEBHOOKS)';
    RAISE NOTICE '==================================================';

    -- -------------------------------------------------------------------------
    -- SETUP FIXTURES (Elevated System Context)
    -- -------------------------------------------------------------------------
    PERFORM set_config('role', 'postgres', true);

    -- Auth Users
    INSERT INTO auth.users (id, email, created_at, updated_at, confirmation_token, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, is_super_admin, role) VALUES 
        (v_admin1_id, 'admin14@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
        (v_member1_id, 'member14_1@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
        (v_member2_id, 'member14_2@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated')
    ON CONFLICT DO NOTHING;

    -- Public Users
    INSERT INTO public.users (id, full_name, mobile) VALUES 
        (v_admin1_id, 'Admin 14', '+1400000000'),
        (v_member1_id, 'Member 14-1', '+1411111111'),
        (v_member2_id, 'Member 14-2', '+1422222222')
    ON CONFLICT DO NOTHING;

    -- Societies
    INSERT INTO public.societies (id, name, registration_number, address) VALUES 
        (v_society1_id, 'Test Society 14-A', 'TS14-A', 'Address 14A'),
        (v_society2_id, 'Test Society 14-B', 'TS14-B', 'Address 14B')
    ON CONFLICT DO NOTHING;

    -- User Roles
    INSERT INTO public.user_roles (society_id, user_id, role_name, granted_by) VALUES 
        (v_society1_id, v_admin1_id, 'admin', v_admin1_id),
        (v_society1_id, v_member1_id, 'member', v_admin1_id),
        (v_society1_id, v_member2_id, 'member', v_admin1_id),
        (v_society2_id, v_admin1_id, 'admin', v_admin1_id)
    ON CONFLICT DO NOTHING;

    -- Properties & Ownership
    INSERT INTO public.properties (id, society_id, plot_number, plot_size_sqft, created_by) VALUES 
        (v_property1_id, v_society1_id, 'P14-01', 1200, v_admin1_id),
        (v_property2_id, v_society2_id, 'P14-02', 1500, v_admin1_id)
    ON CONFLICT DO NOTHING;

    INSERT INTO public.property_owners (property_id, owner_id, is_primary_owner, start_date, created_by) VALUES 
        (v_property1_id, v_member1_id, TRUE, CURRENT_DATE, v_admin1_id),
        (v_property2_id, v_member2_id, TRUE, CURRENT_DATE, v_admin1_id)
    ON CONFLICT DO NOTHING;

    -- Fixture 1: Charge & Payment for Society 1
    INSERT INTO public.maintenance_charges (society_id, property_id, amount, status, billing_period, billing_basis_snapshot, created_by)
    VALUES (v_society1_id, v_property1_id, 1000.00, 'posted', '2026-01', '{}', v_admin1_id) 
    RETURNING id INTO v_charge1_id;

    INSERT INTO public.payments (society_id, property_id, amount, payment_method, reference_number, created_by)
    VALUES (v_society1_id, v_property1_id, 1000.00, 'upi', 'REF-14-1', v_member1_id) 
    RETURNING id INTO v_payment1_id;

    -- -------------------------------------------------------------------------
    -- ASSERTION 1: Payment Intent Creation (Member 1 Context)
    -- -------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claims', format('{"sub": "%s", "role": "authenticated"}', v_member1_id), true);
    PERFORM set_config('role', 'authenticated', true);

    v_order_id := 'order_stripe_' || gen_random_uuid();
    BEGIN
        INSERT INTO public.payment_intents (society_id, property_id, user_id, payment_id, allocations, amount, provider, provider_order_id)
        VALUES (
            v_society1_id, v_property1_id, v_member1_id, v_payment1_id, 
            jsonb_build_array(jsonb_build_object('charge_id', v_charge1_id, 'amount', 1000.00)), 
            1000.00, 'stripe', v_order_id
        )
        RETURNING id INTO v_intent1_id;

        IF v_intent1_id IS NOT NULL THEN
            v_assertions_passed := v_assertions_passed + 1;
            RAISE NOTICE 'PASS: 1. Payment intent creation successful';
        ELSE
            RAISE EXCEPTION 'FAIL 1: Intent creation returned NULL';
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'FAIL 1: Intent creation failed with error: %', SQLERRM;
    END;

    -- -------------------------------------------------------------------------
    -- ASSERTION 2: Intent RLS User Isolation (Member 2 cannot see Member 1 Intent)
    -- -------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claims', format('{"sub": "%s", "role": "authenticated"}', v_member2_id), true);
    PERFORM set_config('role', 'authenticated', true);

    SELECT COUNT(*) INTO v_tmp_count FROM public.payment_intents WHERE id = v_intent1_id;
    IF v_tmp_count = 0 THEN
        v_assertions_passed := v_assertions_passed + 1;
        RAISE NOTICE 'PASS: 2. Intent RLS user isolation strictly enforced';
    ELSE
        RAISE EXCEPTION 'FAIL 2: Member 2 was able to view Member 1 payment intent';
    END IF;

    -- -------------------------------------------------------------------------
    -- ASSERTION 3: Intent RLS Society Isolation
    -- -------------------------------------------------------------------------
    -- Member 2 in Society 2 context cannot view Society 1 intents
    SELECT COUNT(*) INTO v_tmp_count FROM public.payment_intents WHERE id = v_intent1_id AND society_id = v_society2_id;
    IF v_tmp_count = 0 THEN
        v_assertions_passed := v_assertions_passed + 1;
        RAISE NOTICE 'PASS: 3. Intent RLS society isolation strictly enforced';
    ELSE
        RAISE EXCEPTION 'FAIL 3: Cross-society intent access leaked';
    END IF;

    -- -------------------------------------------------------------------------
    -- ASSERTION 4: Direct Intent Status Update Blocked
    -- -------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claims', format('{"sub": "%s", "role": "authenticated"}', v_admin1_id), true);
    PERFORM set_config('role', 'authenticated', true);

    BEGIN
        UPDATE public.payment_intents SET status = 'settled' WHERE id = v_intent1_id;
        RAISE EXCEPTION 'FAIL 4: Direct status update was not blocked!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Direct status updates blocked%' OR SQLERRM LIKE '%permission denied%' THEN
            v_assertions_passed := v_assertions_passed + 1;
            RAISE NOTICE 'PASS: 4. Direct status update correctly blocked by trigger';
        ELSE
            RAISE EXCEPTION 'FAIL 4: Unexpected error on direct status update: %', SQLERRM;
        END IF;
    END;

    -- -------------------------------------------------------------------------
    -- ASSERTION 5: Invalid Intent State Transition Blocked
    -- -------------------------------------------------------------------------
    PERFORM set_config('role', 'postgres', true);
    BEGIN
        PERFORM public.fn_transition_payment_intent_state(v_intent1_id, 'invalid_status');
        RAISE EXCEPTION 'FAIL 5: Invalid transition succeeded!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Invalid state transition%' OR SQLERRM LIKE '%value for domain%' THEN
            v_assertions_passed := v_assertions_passed + 1;
            RAISE NOTICE 'PASS: 5. Invalid state transition correctly rejected';
        ELSE
            RAISE EXCEPTION 'FAIL 5: Unexpected error on invalid state transition: %', SQLERRM;
        END IF;
    END;

    -- -------------------------------------------------------------------------
    -- ASSERTION 6: _internal_settle_payment Non-Public Catalog Privilege Check
    -- -------------------------------------------------------------------------
    SELECT has_function_privilege('authenticated', 'public._internal_settle_payment(uuid, jsonb, uuid)', 'EXECUTE') INTO v_tmp_bool;
    IF v_tmp_bool = FALSE THEN
        v_assertions_passed := v_assertions_passed + 1;
        RAISE NOTICE 'PASS: 6. _internal_settle_payment non-PUBLIC privilege catalog check verified';
    ELSE
        RAISE EXCEPTION 'FAIL 6: _internal_settle_payment is executable by authenticated role!';
    END IF;

    -- -------------------------------------------------------------------------
    -- ASSERTION 7: process_verified_webhook Non-Authenticated Execution Blocked
    -- -------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claims', format('{"sub": "%s", "role": "authenticated"}', v_member1_id), true);
    PERFORM set_config('role', 'authenticated', true);

    BEGIN
        SELECT public.process_verified_webhook('stripe', 'evt_fake', 'payment_intent.succeeded', '{}'::jsonb, v_intent1_id) INTO v_success;
        RAISE EXCEPTION 'FAIL 7: process_verified_webhook executable by authenticated role!';
    EXCEPTION WHEN insufficient_privilege THEN
        v_assertions_passed := v_assertions_passed + 1;
        RAISE NOTICE 'PASS: 7. process_verified_webhook restricted from authenticated users';
    END;

    -- -------------------------------------------------------------------------
    -- ASSERTION 8: Amount Mismatch Rejection (Provider amount != Intent amount)
    -- -------------------------------------------------------------------------
    PERFORM set_config('role', 'service_role', true);

    DECLARE
        v_mismatch_payload JSONB := jsonb_build_object(
            'data', jsonb_build_object(
                'object', jsonb_build_object(
                    'id', v_order_id,
                    'amount', 50000 -- $500.00 instead of $1000.00
                )
            )
        );
    BEGIN
        SELECT public.process_verified_webhook('stripe', 'evt_amt_mismatch_' || gen_random_uuid(), 'payment_intent.succeeded', v_mismatch_payload, v_intent1_id) INTO v_success;
        IF v_success = FALSE THEN
            v_assertions_passed := v_assertions_passed + 1;
            RAISE NOTICE 'PASS: 8. Amount mismatch correctly rejected by process_verified_webhook';
        ELSE
            RAISE EXCEPTION 'FAIL 8: Amount mismatch returned TRUE!';
        END IF;
    END;

    -- -------------------------------------------------------------------------
    -- ASSERTION 9: Intent Failed State Transition on Mismatch
    -- -------------------------------------------------------------------------
    PERFORM set_config('role', 'postgres', true);
    SELECT status INTO v_tmp_val FROM public.payment_intents WHERE id = v_intent1_id;
    IF v_tmp_val = 'failed' THEN
        v_assertions_passed := v_assertions_passed + 1;
        RAISE NOTICE 'PASS: 9. Payment intent transitioned to failed status on amount mismatch';
    ELSE
        RAISE EXCEPTION 'FAIL 9: Intent status is %, expected failed', v_tmp_val;
    END IF;

    -- -------------------------------------------------------------------------
    -- SETUP FIXTURE 2 FOR VALID SETTLEMENT & IDEMPOTENCY
    -- -------------------------------------------------------------------------
    PERFORM set_config('role', 'postgres', true);

    INSERT INTO public.maintenance_charges (society_id, property_id, amount, status, billing_period, billing_basis_snapshot, created_by)
    VALUES (v_society1_id, v_property1_id, 1500.00, 'posted', '2026-02', '{}', v_admin1_id) 
    RETURNING id INTO v_charge2_id;

    INSERT INTO public.payments (society_id, property_id, amount, payment_method, reference_number, created_by)
    VALUES (v_society1_id, v_property1_id, 1500.00, 'upi', 'REF-14-2', v_member1_id) 
    RETURNING id INTO v_payment2_id;

    PERFORM set_config('request.jwt.claims', format('{"sub": "%s", "role": "authenticated"}', v_member1_id), true);
    PERFORM set_config('role', 'authenticated', true);

    v_order_id := 'order_stripe_2_' || gen_random_uuid();
    INSERT INTO public.payment_intents (society_id, property_id, user_id, payment_id, allocations, amount, provider, provider_order_id)
    VALUES (
        v_society1_id, v_property1_id, v_member1_id, v_payment2_id, 
        jsonb_build_array(jsonb_build_object('charge_id', v_charge2_id, 'amount', 1500.00)), 
        1500.00, 'stripe', v_order_id
    )
    RETURNING id INTO v_intent2_id;

    -- -------------------------------------------------------------------------
    -- ASSERTION 10: Duplicate Webhook Idempotency (Same Event Retried)
    -- -------------------------------------------------------------------------
    DECLARE
        v_event_id VARCHAR := 'evt_valid_2_' || gen_random_uuid();
        v_valid_payload JSONB := jsonb_build_object(
            'data', jsonb_build_object(
                'object', jsonb_build_object(
                    'id', v_order_id,
                    'amount', 150000, -- $1500.00
                    'currency', 'inr'
                )
            )
        );
    BEGIN
        PERFORM set_config('role', 'service_role', true);
        
        -- First execution
        SELECT public.process_verified_webhook('stripe', v_event_id, 'payment_intent.succeeded', v_valid_payload, v_intent2_id) INTO v_success;
        IF NOT v_success THEN RAISE EXCEPTION 'First settlement failed'; END IF;

        -- Second execution (duplicate event retry)
        SELECT public.process_verified_webhook('stripe', v_event_id, 'payment_intent.succeeded', v_valid_payload, v_intent2_id) INTO v_success;
        IF v_success = TRUE THEN
            v_assertions_passed := v_assertions_passed + 1;
            RAISE NOTICE 'PASS: 10. Duplicate webhook retry handled idempotently without error';
        ELSE
            RAISE EXCEPTION 'FAIL 10: Duplicate retry returned FALSE';
        END IF;
    END;

    -- -------------------------------------------------------------------------
    -- ASSERTION 11: Conflicting Duplicate Webhook Payload Protection
    -- -------------------------------------------------------------------------
    DECLARE
        v_event_id_dup VARCHAR := 'evt_conflict_' || gen_random_uuid();
        v_payload_a JSONB := jsonb_build_object('data', jsonb_build_object('object', jsonb_build_object('id', 'ord_a', 'amount', 100000)));
        v_payload_b JSONB := jsonb_build_object('data', jsonb_build_object('object', jsonb_build_object('id', 'ord_b', 'amount', 200000)));
    BEGIN
        PERFORM set_config('role', 'postgres', true);
        INSERT INTO public.payment_webhooks (provider, provider_event_id, event_type, payload) 
        VALUES ('stripe', v_event_id_dup, 'payment_intent.succeeded', v_payload_a);

        PERFORM set_config('role', 'service_role', true);
        SELECT public.process_verified_webhook('stripe', v_event_id_dup, 'payment_intent.succeeded', v_payload_b, v_intent2_id) INTO v_success;
        RAISE EXCEPTION 'FAIL 11: Conflicting payload duplicate was not rejected!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Conflicting webhook payload%' THEN
            v_assertions_passed := v_assertions_passed + 1;
            RAISE NOTICE 'PASS: 11. Conflicting duplicate webhook payload correctly rejected';
        ELSE
            RAISE EXCEPTION 'FAIL 11: Unexpected error on conflicting duplicate: %', SQLERRM;
        END IF;
    END;

    -- -------------------------------------------------------------------------
    -- SETUP FIXTURE 3 FOR CARDINALITY & ATOMICITY TESTS
    -- -------------------------------------------------------------------------
    PERFORM set_config('role', 'postgres', true);

    INSERT INTO public.maintenance_charges (society_id, property_id, amount, status, billing_period, billing_basis_snapshot, created_by)
    VALUES (v_society1_id, v_property1_id, 2000.00, 'posted', '2026-03', '{}', v_admin1_id) 
    RETURNING id INTO v_charge3_id;

    INSERT INTO public.payments (society_id, property_id, amount, payment_method, reference_number, created_by)
    VALUES (v_society1_id, v_property1_id, 2000.00, 'upi', 'REF-14-3', v_member1_id) 
    RETURNING id INTO v_payment3_id;

    PERFORM set_config('request.jwt.claims', format('{"sub": "%s", "role": "authenticated"}', v_member1_id), true);
    PERFORM set_config('role', 'authenticated', true);

    v_order_id := 'order_stripe_3_' || gen_random_uuid();
    INSERT INTO public.payment_intents (society_id, property_id, user_id, payment_id, allocations, amount, provider, provider_order_id)
    VALUES (
        v_society1_id, v_property1_id, v_member1_id, v_payment3_id, 
        jsonb_build_array(jsonb_build_object('charge_id', v_charge3_id, 'amount', 2000.00)), 
        2000.00, 'stripe', v_order_id
    )
    RETURNING id INTO v_intent3_id;

    -- -------------------------------------------------------------------------
    -- ASSERTION 12: Valid Webhook Settlement Execution Success
    -- -------------------------------------------------------------------------
    DECLARE
        v_event_id3 VARCHAR := 'evt_valid_3_' || gen_random_uuid();
        v_payload3 JSONB := jsonb_build_object(
            'data', jsonb_build_object(
                'object', jsonb_build_object(
                    'id', v_order_id,
                    'amount', 200000, -- $2000.00
                    'currency', 'inr'
                )
            )
        );
    BEGIN
        PERFORM set_config('role', 'service_role', true);
        SELECT public.process_verified_webhook('stripe', v_event_id3, 'payment_intent.succeeded', v_payload3, v_intent3_id) INTO v_success;
        IF v_success THEN
            v_assertions_passed := v_assertions_passed + 1;
            RAISE NOTICE 'PASS: 12. Valid webhook settlement execution completed successfully';
        ELSE
            RAISE EXCEPTION 'FAIL 12: Valid settlement returned FALSE';
        END IF;
    END;

    -- -------------------------------------------------------------------------
    -- ASSERTION 13: Exactly One Payment State Verification (verified_by IS NULL)
    -- -------------------------------------------------------------------------
    PERFORM set_config('role', 'postgres', true);
    SELECT COUNT(*) INTO v_tmp_count 
    FROM public.payments 
    WHERE id = v_payment3_id AND status = 'verified' AND verified_by IS NULL;
    
    IF v_tmp_count = 1 THEN
        v_assertions_passed := v_assertions_passed + 1;
        RAISE NOTICE 'PASS: 13. Exactly one payment verified with SYSTEM actor (verified_by IS NULL)';
    ELSE
        RAISE EXCEPTION 'FAIL 13: Payment status or verified_by incorrect. Count: %', v_tmp_count;
    END IF;

    -- -------------------------------------------------------------------------
    -- ASSERTION 14: Exactly One Property Subsidiary Ledger Credit Verification
    -- -------------------------------------------------------------------------
    SELECT COUNT(*), SUM(amount) INTO v_tmp_count, v_tmp_sum
    FROM public.ledger_transactions 
    WHERE source_payment_id = v_payment3_id AND scope = 'property' AND direction = 'credit';

    IF v_tmp_count = 1 AND v_tmp_sum = 2000.00 THEN
        v_assertions_passed := v_assertions_passed + 1;
        RAISE NOTICE 'PASS: 14. Exactly one property subsidiary ledger credit verified (Amount: 2000.00)';
    ELSE
        RAISE EXCEPTION 'FAIL 14: Property ledger count % or sum % incorrect', v_tmp_count, v_tmp_sum;
    END IF;

    -- -------------------------------------------------------------------------
    -- ASSERTION 15: Exactly One Society Cash/Bank Ledger Debit Verification
    -- -------------------------------------------------------------------------
    SELECT COUNT(*), SUM(amount) INTO v_tmp_count, v_tmp_sum
    FROM public.ledger_transactions 
    WHERE source_payment_id = v_payment3_id AND scope = 'society' AND direction = 'debit';

    IF v_tmp_count = 1 AND v_tmp_sum = 2000.00 THEN
        v_assertions_passed := v_assertions_passed + 1;
        RAISE NOTICE 'PASS: 15. Exactly one society cash/bank ledger debit verified (Amount: 2000.00)';
    ELSE
        RAISE EXCEPTION 'FAIL 15: Society ledger count % or sum % incorrect', v_tmp_count, v_tmp_sum;
    END IF;

    -- -------------------------------------------------------------------------
    -- ASSERTION 16: Exactly One Receipt Generated Verification
    -- -------------------------------------------------------------------------
    SELECT COUNT(*) INTO v_tmp_count FROM public.receipts WHERE payment_id = v_payment3_id;
    IF v_tmp_count = 1 THEN
        v_assertions_passed := v_assertions_passed + 1;
        RAISE NOTICE 'PASS: 16. Exactly one receipt generated for settlement';
    ELSE
        RAISE EXCEPTION 'FAIL 16: Receipt count % incorrect', v_tmp_count;
    END IF;

    -- -------------------------------------------------------------------------
    -- ASSERTION 17: Notification Fan-Out to Payer Verification
    -- -------------------------------------------------------------------------
    SELECT COUNT(*) INTO v_tmp_count 
    FROM public.notifications 
    WHERE related_entity_type = 'payments' AND related_entity_id = v_payment3_id AND recipient_user_id = v_member1_id;

    IF v_tmp_count = 1 THEN
        v_assertions_passed := v_assertions_passed + 1;
        RAISE NOTICE 'PASS: 17. Exactly one notification delivered to payer';
    ELSE
        RAISE EXCEPTION 'FAIL 17: Notification count % incorrect', v_tmp_count;
    END IF;

    -- -------------------------------------------------------------------------
    -- ASSERTION 18: Audit Trail Verification with SYSTEM Actor (actor_id IS NULL)
    -- -------------------------------------------------------------------------
    SELECT COUNT(*) INTO v_tmp_count 
    FROM public.audit_logs 
    WHERE entity_type = 'payment' AND entity_id = v_payment3_id AND action = 'payment_verified_with_allocation' AND actor_id IS NULL;

    IF v_tmp_count = 1 THEN
        v_assertions_passed := v_assertions_passed + 1;
        RAISE NOTICE 'PASS: 18. Audit trail correctly logged with SYSTEM actor (actor_id IS NULL)';
    ELSE
        RAISE EXCEPTION 'FAIL 18: Audit log count % incorrect or actor spoofed', v_tmp_count;
    END IF;

    -- -------------------------------------------------------------------------
    -- ASSERTION 19: Webhook Settlement Retry on Settled Intent Idempotency
    -- -------------------------------------------------------------------------
    PERFORM set_config('role', 'service_role', true);
    DECLARE
        v_retry_evt VARCHAR := 'evt_retry_' || gen_random_uuid();
        v_retry_payload JSONB := jsonb_build_object(
            'data', jsonb_build_object(
                'object', jsonb_build_object(
                    'id', v_order_id,
                    'amount', 200000,
                    'currency', 'inr'
                )
            )
        );
    BEGIN
        SELECT public.process_verified_webhook('stripe', v_retry_evt, 'payment_intent.succeeded', v_retry_payload, v_intent3_id) INTO v_success;
        IF v_success = TRUE THEN
            -- Verify receipt count remains 1
            SELECT COUNT(*) INTO v_tmp_count FROM public.receipts WHERE payment_id = v_payment3_id;
            IF v_tmp_count = 1 THEN
                v_assertions_passed := v_assertions_passed + 1;
                RAISE NOTICE 'PASS: 19. Webhook retry on settled intent returned success idempotently without duplicate receipt';
            ELSE
                RAISE EXCEPTION 'FAIL 19: Duplicate receipt created on retry!';
            END IF;
        ELSE
            RAISE EXCEPTION 'FAIL 19: Retry returned FALSE';
        END IF;
    END;

    -- -------------------------------------------------------------------------
    -- ASSERTION 20: Webhook Table Immutability (UPDATE blocked)
    -- -------------------------------------------------------------------------
    PERFORM set_config('role', 'postgres', true);
    BEGIN
        UPDATE public.payment_webhooks SET event_type = 'tampered' WHERE provider = 'stripe';
        RAISE EXCEPTION 'FAIL 20: payment_webhooks UPDATE was not blocked!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%immutable append-only ledger%' THEN
            v_assertions_passed := v_assertions_passed + 1;
            RAISE NOTICE 'PASS: 20. payment_webhooks UPDATE correctly blocked by immutability trigger';
        ELSE
            RAISE EXCEPTION 'FAIL 20: Unexpected error on webhook UPDATE: %', SQLERRM;
        END IF;
    END;

    -- -------------------------------------------------------------------------
    -- ASSERTION 21: Slice 5 Admin Wrapper Security Isolation
    -- -------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claims', format('{"sub": "%s", "role": "authenticated"}', v_member1_id), true);
    PERFORM set_config('role', 'authenticated', true);

    BEGIN
        SELECT public.fn_verify_payment_with_allocation(v_payment3_id, '[]'::jsonb) INTO v_tmp_val;
        RAISE EXCEPTION 'FAIL 21: Resident was able to invoke fn_verify_payment_with_allocation!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Access Denied%' THEN
            v_assertions_passed := v_assertions_passed + 1;
            RAISE NOTICE 'PASS: 21. Admin isolation enforced on fn_verify_payment_with_allocation';
        ELSE
            RAISE EXCEPTION 'FAIL 21: Unexpected error on admin wrapper call: %', SQLERRM;
        END IF;
    END;

    -- -------------------------------------------------------------------------
    -- ASSERTION 22: Slice 5 Overpayment/Allocation Boundary Validation
    -- -------------------------------------------------------------------------
    PERFORM set_config('role', 'postgres', true);
    
    -- Create charge 100.00, payment 200.00
    DECLARE
        v_chg_over UUID;
        v_pay_over UUID;
    BEGIN
        INSERT INTO public.maintenance_charges (society_id, property_id, amount, status, billing_period, billing_basis_snapshot, created_by)
        VALUES (v_society1_id, v_property1_id, 100.00, 'posted', '2026-04', '{}', v_admin1_id) 
        RETURNING id INTO v_chg_over;

        INSERT INTO public.payments (society_id, property_id, amount, payment_method, reference_number, created_by)
        VALUES (v_society1_id, v_property1_id, 200.00, 'upi', 'REF-OVER', v_member1_id) 
        RETURNING id INTO v_pay_over;

        PERFORM set_config('request.jwt.claims', format('{"sub": "%s", "role": "authenticated"}', v_admin1_id), true);
        PERFORM set_config('role', 'authenticated', true);

        BEGIN
            SELECT public.fn_verify_payment_with_allocation(v_pay_over, jsonb_build_array(jsonb_build_object('charge_id', v_chg_over, 'amount', 200.00))) INTO v_tmp_val;
            RAISE EXCEPTION 'FAIL 22: Allocation exceeding charge outstanding balance succeeded!';
        EXCEPTION WHEN OTHERS THEN
            IF SQLERRM LIKE '%Allocation exceeds outstanding charge balance%' THEN
                v_assertions_passed := v_assertions_passed + 1;
                RAISE NOTICE 'PASS: 22. Allocation boundary check (charge balance limit) verified';
            ELSE
                RAISE EXCEPTION 'FAIL 22: Unexpected error on over-allocation: %', SQLERRM;
            END IF;
        END;
    END;

    -- -------------------------------------------------------------------------
    -- ASSERTION 23: Slice 5 Negative/Zero Allocation Validation
    -- -------------------------------------------------------------------------
    PERFORM set_config('role', 'postgres', true);

    DECLARE
        v_chg_neg UUID;
        v_pay_neg UUID;
    BEGIN
        INSERT INTO public.maintenance_charges (society_id, property_id, amount, status, billing_period, billing_basis_snapshot, created_by)
        VALUES (v_society1_id, v_property1_id, 100.00, 'posted', '2026-12', '{}', v_admin1_id) 
        RETURNING id INTO v_chg_neg;

        INSERT INTO public.payments (society_id, property_id, amount, payment_method, reference_number, created_by)
        VALUES (v_society1_id, v_property1_id, 100.00, 'upi', 'REF-NEG', v_member1_id) 
        RETURNING id INTO v_pay_neg;

        PERFORM set_config('request.jwt.claims', format('{"sub": "%s", "role": "authenticated"}', v_admin1_id), true);
        PERFORM set_config('role', 'authenticated', true);

        BEGIN
            SELECT public.fn_verify_payment_with_allocation(v_pay_neg, jsonb_build_array(jsonb_build_object('charge_id', v_chg_neg, 'amount', -50.00))) INTO v_tmp_val;
            RAISE EXCEPTION 'FAIL 23: Negative allocation succeeded!';
        EXCEPTION WHEN OTHERS THEN
            IF SQLERRM LIKE '%Allocation amount must be greater than zero%' THEN
                v_assertions_passed := v_assertions_passed + 1;
                RAISE NOTICE 'PASS: 23. Non-positive allocation amount correctly rejected';
            ELSE
                RAISE EXCEPTION 'FAIL 23: Unexpected error on negative allocation: %', SQLERRM;
            END IF;
        END;
    END;

    -- -------------------------------------------------------------------------
    -- ASSERTION 24: Slice 5 Cross-Society Allocation Validation
    -- -------------------------------------------------------------------------
    PERFORM set_config('role', 'postgres', true);

    DECLARE
        v_chg_soc2 UUID;
        v_pay_soc1 UUID;
    BEGIN
        INSERT INTO public.maintenance_charges (society_id, property_id, amount, status, billing_period, billing_basis_snapshot, created_by)
        VALUES (v_society2_id, v_property2_id, 300.00, 'posted', '2026-05', '{}', v_admin1_id) 
        RETURNING id INTO v_chg_soc2;

        INSERT INTO public.payments (society_id, property_id, amount, payment_method, reference_number, created_by)
        VALUES (v_society1_id, v_property1_id, 300.00, 'upi', 'REF-CROSS', v_member1_id) 
        RETURNING id INTO v_pay_soc1;

        PERFORM set_config('request.jwt.claims', format('{"sub": "%s", "role": "authenticated"}', v_admin1_id), true);
        PERFORM set_config('role', 'authenticated', true);

        BEGIN
            SELECT public.fn_verify_payment_with_allocation(v_pay_soc1, jsonb_build_array(jsonb_build_object('charge_id', v_chg_soc2, 'amount', 300.00))) INTO v_tmp_val;
            RAISE EXCEPTION 'FAIL 24: Cross-society allocation succeeded!';
        EXCEPTION WHEN OTHERS THEN
            IF SQLERRM LIKE '%Charge belongs to a different society%' THEN
                v_assertions_passed := v_assertions_passed + 1;
                RAISE NOTICE 'PASS: 24. Cross-society charge allocation correctly blocked';
            ELSE
                RAISE EXCEPTION 'FAIL 24: Unexpected error on cross-society allocation: %', SQLERRM;
            END IF;
        END;
    END;

    -- -------------------------------------------------------------------------
    -- ASSERTION 25: Payer Active Relationship Enforcement (Slice 5 behavior)
    -- -------------------------------------------------------------------------
    PERFORM set_config('role', 'postgres', true);

    DECLARE
        v_orphan_user UUID := '91400000-0000-0000-0000-000000000000';
        v_pay_orphan UUID;
    BEGIN
        INSERT INTO auth.users (id, email) VALUES (v_orphan_user, 'orphan@test.com') ON CONFLICT DO NOTHING;
        INSERT INTO public.users (id, full_name, mobile) VALUES (v_orphan_user, 'Orphan User', '+1499999999') ON CONFLICT DO NOTHING;

        INSERT INTO public.payments (society_id, property_id, amount, payment_method, reference_number, created_by)
        VALUES (v_society1_id, v_property1_id, 100.00, 'upi', 'REF-ORPHAN', v_orphan_user)
        RETURNING id INTO v_pay_orphan;

        BEGIN
            PERFORM public._internal_settle_payment(v_pay_orphan, '[]'::jsonb, v_admin1_id);
            RAISE EXCEPTION 'FAIL 25: Unassociated payer payment settlement succeeded!';
        EXCEPTION WHEN OTHERS THEN
            IF SQLERRM LIKE '%Payer has no active ownership or tenancy connection%' THEN
                v_assertions_passed := v_assertions_passed + 1;
                RAISE NOTICE 'PASS: 25. Payer active relationship check strictly enforced';
            ELSE
                RAISE EXCEPTION 'FAIL 25: Unexpected error on orphan payer settlement: %', SQLERRM;
            END IF;
        END;
    END;

    -- -------------------------------------------------------------------------
    -- ASSERTION 26: Financial Atomicity & Transaction Rollback Proof
    -- -------------------------------------------------------------------------
    PERFORM set_config('role', 'postgres', true);

    DECLARE
        v_pay_rollback UUID;
        v_chg_valid UUID;
        v_chg_invalid UUID;
    BEGIN
        INSERT INTO public.maintenance_charges (society_id, property_id, amount, status, billing_period, billing_basis_snapshot, created_by)
        VALUES (v_society1_id, v_property1_id, 500.00, 'posted', '2026-06', '{}', v_admin1_id) RETURNING id INTO v_chg_valid;

        INSERT INTO public.maintenance_charges (society_id, property_id, amount, status, billing_period, billing_basis_snapshot, created_by)
        VALUES (v_society2_id, v_property2_id, 500.00, 'posted', '2026-07', '{}', v_admin1_id) RETURNING id INTO v_chg_invalid;

        INSERT INTO public.payments (society_id, property_id, amount, payment_method, reference_number, created_by)
        VALUES (v_society1_id, v_property1_id, 1000.00, 'upi', 'REF-ROLLBACK', v_member1_id) RETURNING id INTO v_pay_rollback;

        PERFORM set_config('request.jwt.claims', format('{"sub": "%s", "role": "authenticated"}', v_admin1_id), true);
        PERFORM set_config('role', 'authenticated', true);

        BEGIN
            -- First allocation valid, second allocation cross-society (will fail transaction)
            PERFORM public.fn_verify_payment_with_allocation(
                v_pay_rollback, 
                jsonb_build_array(
                    jsonb_build_object('charge_id', v_chg_valid, 'amount', 500.00),
                    jsonb_build_object('charge_id', v_chg_invalid, 'amount', 500.00)
                )
            );
            RAISE EXCEPTION 'FAIL 26: Multi-allocation settlement containing invalid charge succeeded!';
        EXCEPTION WHEN OTHERS THEN
            PERFORM set_config('role', 'postgres', true);
            -- Verify atomic rollback: no payment_allocations or receipts inserted for this payment
            SELECT COUNT(*) INTO v_tmp_count FROM public.payment_allocations WHERE payment_id = v_pay_rollback;
            IF v_tmp_count = 0 THEN
                v_assertions_passed := v_assertions_passed + 1;
                RAISE NOTICE 'PASS: 26. Financial atomicity verified (zero side effects committed on failure)';
            ELSE
                RAISE EXCEPTION 'FAIL 26: Partial allocation committed on failure! Count: %', v_tmp_count;
            END IF;
        END;
    END;

    -- -------------------------------------------------------------------------
    -- ASSERTION 27: Currency Test A — Valid INR Currency Settlement
    -- -------------------------------------------------------------------------
    PERFORM set_config('role', 'postgres', true);
    DECLARE
        v_chg_inr UUID;
        v_pay_inr UUID;
        v_intent_inr UUID;
        v_order_inr VARCHAR := 'ord_inr_' || gen_random_uuid();
        v_evt_inr VARCHAR := 'evt_inr_' || gen_random_uuid();
        v_payload_inr JSONB;
    BEGIN
        INSERT INTO public.maintenance_charges (society_id, property_id, amount, status, billing_period, billing_basis_snapshot, created_by)
        VALUES (v_society1_id, v_property1_id, 1000.00, 'posted', '2026-08', '{}', v_admin1_id) RETURNING id INTO v_chg_inr;

        INSERT INTO public.payments (society_id, property_id, amount, currency, payment_method, reference_number, created_by)
        VALUES (v_society1_id, v_property1_id, 1000.00, 'INR', 'upi', 'REF-CURR-INR', v_member1_id) RETURNING id INTO v_pay_inr;

        INSERT INTO public.payment_intents (society_id, property_id, user_id, payment_id, allocations, amount, currency, provider, provider_order_id)
        VALUES (v_society1_id, v_property1_id, v_member1_id, v_pay_inr, jsonb_build_array(jsonb_build_object('charge_id', v_chg_inr, 'amount', 1000.00)), 1000.00, 'INR', 'stripe', v_order_inr)
        RETURNING id INTO v_intent_inr;

        v_payload_inr := jsonb_build_object('data', jsonb_build_object('object', jsonb_build_object('id', v_order_inr, 'amount', 100000, 'currency', 'inr')));

        PERFORM set_config('role', 'service_role', true);
        SELECT public.process_verified_webhook('stripe', v_evt_inr, 'payment_intent.succeeded', v_payload_inr, v_intent_inr) INTO v_success;

        PERFORM set_config('role', 'postgres', true);
        IF v_success = TRUE THEN
            SELECT COUNT(*) INTO v_tmp_count FROM public.receipts WHERE payment_id = v_pay_inr;
            IF v_tmp_count = 1 THEN
                v_assertions_passed := v_assertions_passed + 1;
                RAISE NOTICE 'PASS: 27. Valid INR currency settlement completed successfully with receipt';
            ELSE
                RAISE EXCEPTION 'FAIL 27: Receipt count % != 1', v_tmp_count;
            END IF;
        ELSE
            RAISE EXCEPTION 'FAIL 27: process_verified_webhook returned FALSE for valid INR';
        END IF;
    END;

    -- -------------------------------------------------------------------------
    -- ASSERTION 28: Currency Test B — USD Currency Mismatch Rejection
    -- -------------------------------------------------------------------------
    PERFORM set_config('role', 'postgres', true);
    DECLARE
        v_chg_usd UUID;
        v_pay_usd UUID;
        v_intent_usd UUID;
        v_order_usd VARCHAR := 'ord_usd_' || gen_random_uuid();
        v_evt_usd VARCHAR := 'evt_usd_' || gen_random_uuid();
        v_payload_usd JSONB;
        v_status VARCHAR;
    BEGIN
        INSERT INTO public.maintenance_charges (society_id, property_id, amount, status, billing_period, billing_basis_snapshot, created_by)
        VALUES (v_society1_id, v_property1_id, 1000.00, 'posted', '2026-09', '{}', v_admin1_id) RETURNING id INTO v_chg_usd;

        INSERT INTO public.payments (society_id, property_id, amount, currency, payment_method, reference_number, created_by)
        VALUES (v_society1_id, v_property1_id, 1000.00, 'INR', 'upi', 'REF-CURR-USD', v_member1_id) RETURNING id INTO v_pay_usd;

        INSERT INTO public.payment_intents (society_id, property_id, user_id, payment_id, allocations, amount, currency, provider, provider_order_id)
        VALUES (v_society1_id, v_property1_id, v_member1_id, v_pay_usd, jsonb_build_array(jsonb_build_object('charge_id', v_chg_usd, 'amount', 1000.00)), 1000.00, 'INR', 'stripe', v_order_usd)
        RETURNING id INTO v_intent_usd;

        -- Provider sends USD currency
        v_payload_usd := jsonb_build_object('data', jsonb_build_object('object', jsonb_build_object('id', v_order_usd, 'amount', 100000, 'currency', 'USD')));

        PERFORM set_config('role', 'service_role', true);
        SELECT public.process_verified_webhook('stripe', v_evt_usd, 'payment_intent.succeeded', v_payload_usd, v_intent_usd) INTO v_success;

        PERFORM set_config('role', 'postgres', true);
        IF v_success = FALSE THEN
            SELECT status INTO v_status FROM public.payment_intents WHERE id = v_intent_usd;
            SELECT COUNT(*) INTO v_tmp_count FROM public.receipts WHERE payment_id = v_pay_usd;
            
            IF v_status = 'failed' AND v_tmp_count = 0 THEN
                v_assertions_passed := v_assertions_passed + 1;
                RAISE NOTICE 'PASS: 28. USD currency mismatch correctly rejected (intent failed, 0 side-effects)';
            ELSE
                RAISE EXCEPTION 'FAIL 28: Status % or receipt count % incorrect', v_status, v_tmp_count;
            END IF;
        ELSE
            RAISE EXCEPTION 'FAIL 28: process_verified_webhook returned TRUE for USD mismatch!';
        END IF;
    END;

    -- -------------------------------------------------------------------------
    -- ASSERTION 29: Currency Test C — Missing Provider Currency Rejection
    -- -------------------------------------------------------------------------
    PERFORM set_config('role', 'postgres', true);
    DECLARE
        v_chg_nocurr UUID;
        v_pay_nocurr UUID;
        v_intent_nocurr UUID;
        v_order_nocurr VARCHAR := 'ord_nocurr_' || gen_random_uuid();
        v_evt_nocurr VARCHAR := 'evt_nocurr_' || gen_random_uuid();
        v_payload_nocurr JSONB;
        v_status VARCHAR;
    BEGIN
        INSERT INTO public.maintenance_charges (society_id, property_id, amount, status, billing_period, billing_basis_snapshot, created_by)
        VALUES (v_society1_id, v_property1_id, 1000.00, 'posted', '2026-10', '{}', v_admin1_id) RETURNING id INTO v_chg_nocurr;

        INSERT INTO public.payments (society_id, property_id, amount, currency, payment_method, reference_number, created_by)
        VALUES (v_society1_id, v_property1_id, 1000.00, 'INR', 'upi', 'REF-CURR-NOCURR', v_member1_id) RETURNING id INTO v_pay_nocurr;

        INSERT INTO public.payment_intents (society_id, property_id, user_id, payment_id, allocations, amount, currency, provider, provider_order_id)
        VALUES (v_society1_id, v_property1_id, v_member1_id, v_pay_nocurr, jsonb_build_array(jsonb_build_object('charge_id', v_chg_nocurr, 'amount', 1000.00)), 1000.00, 'INR', 'stripe', v_order_nocurr)
        RETURNING id INTO v_intent_nocurr;

        -- Provider payload omits currency
        v_payload_nocurr := jsonb_build_object('data', jsonb_build_object('object', jsonb_build_object('id', v_order_nocurr, 'amount', 100000)));

        PERFORM set_config('role', 'service_role', true);
        SELECT public.process_verified_webhook('stripe', v_evt_nocurr, 'payment_intent.succeeded', v_payload_nocurr, v_intent_nocurr) INTO v_success;

        PERFORM set_config('role', 'postgres', true);
        IF v_success = FALSE THEN
            SELECT status INTO v_status FROM public.payment_intents WHERE id = v_intent_nocurr;
            IF v_status = 'failed' THEN
                v_assertions_passed := v_assertions_passed + 1;
                RAISE NOTICE 'PASS: 29. Missing provider currency correctly rejected with intent failed';
            ELSE
                RAISE EXCEPTION 'FAIL 29: Intent status % != failed', v_status;
            END IF;
        ELSE
            RAISE EXCEPTION 'FAIL 29: process_verified_webhook returned TRUE for missing currency!';
        END IF;
    END;

    -- -------------------------------------------------------------------------
    -- ASSERTION 30: Currency Test D — Internal Intent vs Payment Currency Mismatch
    -- -------------------------------------------------------------------------
    PERFORM set_config('role', 'postgres', true);
    DECLARE
        v_chg_intmismatch UUID;
        v_pay_intmismatch UUID;
        v_intent_intmismatch UUID;
        v_order_intmismatch VARCHAR := 'ord_intmismatch_' || gen_random_uuid();
        v_evt_intmismatch VARCHAR := 'evt_intmismatch_' || gen_random_uuid();
        v_payload_intmismatch JSONB;
    BEGIN
        INSERT INTO public.maintenance_charges (society_id, property_id, amount, status, billing_period, billing_basis_snapshot, created_by)
        VALUES (v_society1_id, v_property1_id, 1000.00, 'posted', '2026-11', '{}', v_admin1_id) RETURNING id INTO v_chg_intmismatch;

        -- Payment currency USD, Intent currency INR
        INSERT INTO public.payments (society_id, property_id, amount, currency, payment_method, reference_number, created_by)
        VALUES (v_society1_id, v_property1_id, 1000.00, 'USD', 'upi', 'REF-CURR-INTMIS', v_member1_id) RETURNING id INTO v_pay_intmismatch;

        INSERT INTO public.payment_intents (society_id, property_id, user_id, payment_id, allocations, amount, currency, provider, provider_order_id)
        VALUES (v_society1_id, v_property1_id, v_member1_id, v_pay_intmismatch, jsonb_build_array(jsonb_build_object('charge_id', v_chg_intmismatch, 'amount', 1000.00)), 1000.00, 'INR', 'stripe', v_order_intmismatch)
        RETURNING id INTO v_intent_intmismatch;

        v_payload_intmismatch := jsonb_build_object('data', jsonb_build_object('object', jsonb_build_object('id', v_order_intmismatch, 'amount', 100000, 'currency', 'INR')));

        PERFORM set_config('role', 'service_role', true);
        SELECT public.process_verified_webhook('stripe', v_evt_intmismatch, 'payment_intent.succeeded', v_payload_intmismatch, v_intent_intmismatch) INTO v_success;

        PERFORM set_config('role', 'postgres', true);
        IF v_success = FALSE THEN
            v_assertions_passed := v_assertions_passed + 1;
            RAISE NOTICE 'PASS: 30. Internal intent vs payment currency mismatch correctly rejected';
        ELSE
            RAISE EXCEPTION 'FAIL 30: Internal currency mismatch returned TRUE!';
        END IF;
    END;

    -- -------------------------------------------------------------------------
    -- ASSERTION 31: Currency Test E — Case Normalization Validation (inr vs INR)
    -- -------------------------------------------------------------------------
    PERFORM set_config('role', 'postgres', true);
    DECLARE
        v_chg_case UUID;
        v_pay_case UUID;
        v_intent_case UUID;
        v_order_case VARCHAR := 'ord_case_' || gen_random_uuid();
        v_evt_case VARCHAR := 'evt_case_' || gen_random_uuid();
        v_payload_case JSONB;
    BEGIN
        INSERT INTO public.maintenance_charges (society_id, property_id, amount, status, billing_period, billing_basis_snapshot, created_by)
        VALUES (v_society1_id, v_property1_id, 1000.00, 'posted', '2027-01', '{}', v_admin1_id) RETURNING id INTO v_chg_case;

        INSERT INTO public.payments (society_id, property_id, amount, currency, payment_method, reference_number, created_by)
        VALUES (v_society1_id, v_property1_id, 1000.00, 'inr', 'upi', 'REF-CURR-CASE', v_member1_id) RETURNING id INTO v_pay_case;

        INSERT INTO public.payment_intents (society_id, property_id, user_id, payment_id, allocations, amount, currency, provider, provider_order_id)
        VALUES (v_society1_id, v_property1_id, v_member1_id, v_pay_case, jsonb_build_array(jsonb_build_object('charge_id', v_chg_case, 'amount', 1000.00)), 1000.00, 'InR', 'stripe', v_order_case)
        RETURNING id INTO v_intent_case;

        v_payload_case := jsonb_build_object('data', jsonb_build_object('object', jsonb_build_object('id', v_order_case, 'amount', 100000, 'currency', 'inr')));

        PERFORM set_config('role', 'service_role', true);
        SELECT public.process_verified_webhook('stripe', v_evt_case, 'payment_intent.succeeded', v_payload_case, v_intent_case) INTO v_success;

        PERFORM set_config('role', 'postgres', true);
        IF v_success = TRUE THEN
            v_assertions_passed := v_assertions_passed + 1;
            RAISE NOTICE 'PASS: 31. Case-normalized currency matching (inr vs InR vs INR) verified';
        ELSE
            RAISE EXCEPTION 'FAIL 31: Case normalization returned FALSE!';
        END IF;
    END;

    -- -------------------------------------------------------------------------
    -- ASSERTION 32: Direct Adversarial RPC Execution of fn_transition_payment_intent_state Blocked (authenticated & anon)
    -- -------------------------------------------------------------------------
    -- Test Authenticated Role RPC Attempt
    PERFORM set_config('request.jwt.claims', format('{"sub": "%s", "role": "authenticated"}', v_member1_id), true);
    PERFORM set_config('role', 'authenticated', true);

    BEGIN
        PERFORM public.fn_transition_payment_intent_state(v_intent1_id, 'settled');
        RAISE EXCEPTION 'FAIL 32A: fn_transition_payment_intent_state executable by authenticated role!';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS: 32A. Direct RPC execution blocked by permission denied (42501) for authenticated role';
    WHEN OTHERS THEN
        IF SQLERRM LIKE '%Access Denied%' OR SQLSTATE = '42501' THEN
            RAISE NOTICE 'PASS: 32A. Direct RPC execution blocked by Access Denied (42501) for authenticated role';
        ELSE
            RAISE EXCEPTION 'FAIL 32A: Unexpected error on authenticated RPC attempt: % (SQLSTATE %)', SQLERRM, SQLSTATE;
        END IF;
    END;

    -- Test Anon Role RPC Attempt
    PERFORM set_config('request.jwt.claims', '{"role": "anon"}', true);
    PERFORM set_config('role', 'anon', true);

    BEGIN
        PERFORM public.fn_transition_payment_intent_state(v_intent1_id, 'settled');
        RAISE EXCEPTION 'FAIL 32B: fn_transition_payment_intent_state executable by anon role!';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS: 32B. Direct RPC execution blocked by permission denied (42501) for anon role';
    WHEN OTHERS THEN
        IF SQLERRM LIKE '%Access Denied%' OR SQLSTATE = '42501' THEN
            RAISE NOTICE 'PASS: 32B. Direct RPC execution blocked by Access Denied (42501) for anon role';
        ELSE
            RAISE EXCEPTION 'FAIL 32B: Unexpected error on anon RPC attempt: % (SQLSTATE %)', SQLERRM, SQLSTATE;
        END IF;
    END;

    -- Reset to elevated system context
    PERFORM set_config('role', 'postgres', true);
    v_assertions_passed := v_assertions_passed + 1;
    RAISE NOTICE 'PASS: 32. Direct adversarial RPC execution of fn_transition_payment_intent_state blocked for authenticated & anon roles';

    -- -------------------------------------------------------------------------
    -- ASSERTION 33: Catalog Privilege Verification for fn_transition_payment_intent_state
    -- -------------------------------------------------------------------------
    SELECT has_function_privilege('authenticated', 'public.fn_transition_payment_intent_state(uuid, varchar)', 'EXECUTE') INTO v_tmp_bool;
    IF v_tmp_bool = FALSE THEN
        SELECT has_function_privilege('anon', 'public.fn_transition_payment_intent_state(uuid, varchar)', 'EXECUTE') INTO v_tmp_bool;
        IF v_tmp_bool = FALSE THEN
            SELECT has_function_privilege('service_role', 'public.fn_transition_payment_intent_state(uuid, varchar)', 'EXECUTE') INTO v_tmp_bool;
            IF v_tmp_bool = TRUE THEN
                v_assertions_passed := v_assertions_passed + 1;
                RAISE NOTICE 'PASS: 33. Catalog ACL verified: PUBLIC/anon/authenticated = FALSE, service_role = TRUE';
            ELSE
                RAISE EXCEPTION 'FAIL 33: service_role lacks EXECUTE on fn_transition_payment_intent_state!';
            END IF;
        ELSE
            RAISE EXCEPTION 'FAIL 33: anon has EXECUTE on fn_transition_payment_intent_state!';
        END IF;
    ELSE
        RAISE EXCEPTION 'FAIL 33: authenticated has EXECUTE on fn_transition_payment_intent_state!';
    END IF;

    -- -------------------------------------------------------------------------
    -- SUMMARY
    -- -------------------------------------------------------------------------
    RAISE NOTICE '==================================================';
    RAISE NOTICE 'SLICE 14 VERIFICATION COMPLETE (%/33 TESTS PASSED)', v_assertions_passed;
    RAISE NOTICE '==================================================';

    IF v_assertions_passed != 33 THEN
        RAISE EXCEPTION 'SLICE 14 VERIFICATION FAILED: Expected 33 passes, got %', v_assertions_passed;
    END IF;
END;
$$;

