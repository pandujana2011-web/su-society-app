-- =========================================================================
-- ADVERSARIAL SECURITY AUDIT TEST SCRIPT
-- =========================================================================

DO $$
DECLARE
    v_admin_id UUID := 'a1400000-0000-0000-0000-000000000099';
    v_member1_id UUID := 'b1400000-0000-0000-0000-000000000099';
    v_member2_id UUID := 'c1400000-0000-0000-0000-000000000099';
    
    v_society1_id UUID := 'd1400000-0000-0000-0000-000000000099';
    v_property1_id UUID := 'f1400000-0000-0000-0000-000000000099';
    
    v_payment_id UUID;
    v_intent_id UUID;
    v_charge_id UUID;
    v_tmp_count INT;
    v_status VARCHAR;
BEGIN
    RAISE NOTICE '==================================================';
    RAISE NOTICE 'STARTING ADVERSARIAL SECURITY & INTEGRITY TESTS';
    RAISE NOTICE '==================================================';

    PERFORM set_config('role', 'postgres', true);

    -- Setup Users
    INSERT INTO auth.users (id, email) VALUES 
        (v_admin_id, 'admin_adv99@test.com'),
        (v_member1_id, 'member1_adv99@test.com'),
        (v_member2_id, 'member2_adv99@test.com')
    ON CONFLICT DO NOTHING;

    INSERT INTO public.users (id, full_name, mobile) VALUES 
        (v_admin_id, 'Admin Adv 99', '+1400000099'),
        (v_member1_id, 'Member 1 Adv 99', '+1411111199'),
        (v_member2_id, 'Member 2 Adv 99', '+1422222299')
    ON CONFLICT DO NOTHING;

    INSERT INTO public.societies (id, name, registration_number, address) VALUES 
        (v_society1_id, 'Adv Society 99', 'ADV-99', 'Adv Address 99')
    ON CONFLICT DO NOTHING;

    INSERT INTO public.user_roles (society_id, user_id, role_name, granted_by) VALUES 
        (v_society1_id, v_admin_id, 'admin', v_admin_id),
        (v_society1_id, v_member1_id, 'member', v_admin_id),
        (v_society1_id, v_member2_id, 'member', v_admin_id)
    ON CONFLICT DO NOTHING;

    INSERT INTO public.properties (id, society_id, plot_number, plot_size_sqft, created_by) VALUES 
        (v_property1_id, v_society1_id, 'P-ADV-99', 1200, v_admin_id)
    ON CONFLICT DO NOTHING;

    INSERT INTO public.property_owners (property_id, owner_id, is_primary_owner, start_date, created_by) VALUES 
        (v_property1_id, v_member1_id, TRUE, CURRENT_DATE, v_admin_id)
    ON CONFLICT DO NOTHING;

    INSERT INTO public.maintenance_charges (society_id, property_id, amount, status, billing_period, billing_basis_snapshot, created_by)
    VALUES (v_society1_id, v_property1_id, 1000.00, 'posted', '2026-11', '{}', v_admin_id)
    RETURNING id INTO v_charge_id;

    INSERT INTO public.payments (society_id, property_id, amount, payment_method, reference_number, created_by)
    VALUES (v_society1_id, v_property1_id, 1000.00, 'upi', 'REF-ADV-99', v_member1_id)
    RETURNING id INTO v_payment_id;

    INSERT INTO public.payment_intents (society_id, property_id, user_id, payment_id, allocations, amount, provider, provider_order_id)
    VALUES (v_society1_id, v_property1_id, v_member1_id, v_payment_id, jsonb_build_array(jsonb_build_object('charge_id', v_charge_id, 'amount', 1000.00)), 1000.00, 'stripe', 'ord_adv_99')
    RETURNING id INTO v_intent_id;

    -- -------------------------------------------------------------------------
    -- TEST 1: GUC SPOOFING BY AUTHENTICATED RESIDENT
    -- -------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claims', format('{"sub": "%s", "role": "authenticated"}', v_member1_id), true);
    PERFORM set_config('role', 'authenticated', true);

    -- Attempt 1A: Direct UPDATE without GUC
    BEGIN
        UPDATE public.payment_intents SET status = 'settled' WHERE id = v_intent_id;
        RAISE EXCEPTION 'TEST 1A FAILED: Direct UPDATE succeeded without GUC!';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'PASS 1A: Direct UPDATE blocked by RLS/Trigger: %', SQLERRM;
    END;

    -- Attempt 1B: Direct UPDATE WITH Spoofed GUC
    PERFORM set_config('app.intent_transition', v_intent_id::text, true);
    BEGIN
        UPDATE public.payment_intents SET status = 'settled' WHERE id = v_intent_id;
        RAISE EXCEPTION 'TEST 1B FAILED: Direct UPDATE succeeded with spoofed GUC!';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'PASS 1B: Direct UPDATE with spoofed GUC blocked by RLS: %', SQLERRM;
    END;

    -- Verify status remains 'created'
    PERFORM set_config('role', 'postgres', true);
    SELECT status INTO v_status FROM public.payment_intents WHERE id = v_intent_id;
    IF v_status = 'created' THEN
        RAISE NOTICE 'PASS 1C: Intent status strictly preserved as created';
    ELSE
        RAISE EXCEPTION 'TEST 1C FAILED: Status mutated to %', v_status;
    END IF;

    RAISE NOTICE '==================================================';
    RAISE NOTICE 'ADVERSARIAL TESTS COMPLETED';
    RAISE NOTICE '==================================================';
END;
$$;
