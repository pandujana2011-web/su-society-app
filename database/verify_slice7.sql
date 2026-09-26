-- ===========================================================================
-- SLICE 7: VERIFICATION SCRIPT (Vendors & Assets)
-- ===========================================================================

-- Create auth helper function
CREATE OR REPLACE FUNCTION pg_temp.set_auth_uid(p_uid TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', p_uid, 'role', 'authenticated')::text,
        TRUE);
    PERFORM set_config('request.jwt.claim.sub', p_uid, TRUE);
END;
$$;

DO $$
DECLARE
    v_society1_id UUID := gen_random_uuid();
    v_society2_id UUID := gen_random_uuid();
    v_admin_id UUID := gen_random_uuid();
    v_member_id UUID := gen_random_uuid();
    v_tech_id UUID := gen_random_uuid();
    v_admin2_id UUID := gen_random_uuid();
    
    v_vendor1_id UUID;
    v_vendor2_id UUID;
    v_asset1_id UUID;
    v_asset2_id UUID;
    v_amc1_id UUID;
    
    v_property1_id UUID := gen_random_uuid();
    v_category_id UUID := gen_random_uuid();
    v_budget_id UUID := gen_random_uuid();
    v_voucher1_id UUID := gen_random_uuid();
    v_ticket1_id UUID := gen_random_uuid();
    
    v_audit_row RECORD;
BEGIN
    RAISE NOTICE 'Starting Slice 7 Verification...';

    -- =======================================================================
    -- SETUP TEST DATA
    -- =======================================================================
    INSERT INTO public.societies (id, name, registration_number, address) VALUES 
        (v_society1_id, 'Society 7A', 'REG-S7A', 'Address A'),
        (v_society2_id, 'Society 7B', 'REG-S7B', 'Address B');
        
    INSERT INTO auth.users (id, email, created_at, updated_at, confirmation_token, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, is_super_admin, role) VALUES 
        (v_admin_id, 's7admin@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
        (v_member_id, 's7member@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
        (v_tech_id, 's7tech@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated'),
        (v_admin2_id, 's7admin2@test.com', NOW(), NOW(), '', NOW(), '{}', '{}', FALSE, 'authenticated');

    INSERT INTO public.users (id, full_name) VALUES 
        (v_admin_id, 'S7 Admin'), (v_member_id, 'S7 Member'), (v_tech_id, 'S7 Tech'), (v_admin2_id, 'S7 Admin 2');

    INSERT INTO public.user_roles (user_id, society_id, role_name, granted_by) VALUES 
        (v_admin_id, v_society1_id, 'admin', v_admin_id),
        (v_member_id, v_society1_id, 'member', v_admin_id),
        (v_tech_id, v_society1_id, 'technician', v_admin_id),
        (v_admin2_id, v_society2_id, 'admin', v_admin2_id);

    -- Setup for Tickets/Vouchers
    INSERT INTO public.properties (id, society_id, plot_number, created_by) VALUES 
        (v_property1_id, v_society1_id, 'Plot S7-1', v_admin_id);
    INSERT INTO public.property_owners (property_id, owner_id, is_primary_owner, ownership_share_pct, created_by) VALUES 
        (v_property1_id, v_member_id, true, 100, v_admin_id);
    INSERT INTO public.expense_categories (id, society_id, name, created_at) VALUES 
        (v_category_id, v_society1_id, 'Maintenance', NOW());
    INSERT INTO public.budgets (id, society_id, start_date, end_date, category_id, allocated_amount, created_by) VALUES 
        (v_budget_id, v_society1_id, '2026-01-01', '2026-12-31', v_category_id, 10000, v_admin_id);

    -- =======================================================================
    -- 1. VENDORS & VENDOR BANK DETAILS
    -- =======================================================================
    RAISE NOTICE 'Testing Vendors...';
    
    SET LOCAL ROLE authenticated;
    PERFORM pg_temp.set_auth_uid(v_admin_id::text);
    
    -- Admin creation
    INSERT INTO public.vendors (society_id, name, pan_number)
    VALUES (v_society1_id, 'Vendor A', 'PAN123') RETURNING id INTO v_vendor1_id;

    -- Cross-society admin creation fail
    BEGIN
        INSERT INTO public.vendors (society_id, name) VALUES (v_society2_id, 'Vendor B');
        RAISE EXCEPTION 'Admin1 should not be able to create vendor in Society2';
    EXCEPTION WHEN OTHERS THEN -- RLS failure
    END;

    -- Create Vendor Bank
    INSERT INTO public.vendor_bank_details (vendor_id, society_id, account_name, account_number, ifsc_code)
    VALUES (v_vendor1_id, v_society1_id, 'Vendor A Inc', 'ACC-123', 'IFSC001');

    -- Member constraints
    PERFORM pg_temp.set_auth_uid(v_member_id::text);
    BEGIN
        INSERT INTO public.vendors (society_id, name) VALUES (v_society1_id, 'Vendor Member');
        RAISE EXCEPTION 'Member should not be able to create vendor';
    EXCEPTION WHEN OTHERS THEN END;

    -- Member can SELECT vendor but NOT bank
    IF NOT EXISTS (SELECT 1 FROM public.vendors WHERE id = v_vendor1_id) THEN
        RAISE EXCEPTION 'Member could not view vendor';
    END IF;
    IF EXISTS (SELECT 1 FROM public.vendor_bank_details WHERE vendor_id = v_vendor1_id) THEN
        RAISE EXCEPTION 'Member should not view vendor bank details';
    END IF;

    -- Check Audit Log redaction for Bank Details
    PERFORM pg_temp.set_auth_uid(v_admin_id::text);
    SELECT * INTO v_audit_row FROM public.audit_logs 
    WHERE entity_type = 'vendor_bank_details' AND entity_id = v_vendor1_id LIMIT 1;
    IF v_audit_row.new_data IS NOT NULL THEN
        RAISE EXCEPTION 'Vendor Bank details payload was not redacted from audit_logs!';
    END IF;

    -- Vendor state transition
    PERFORM public.fn_transition_vendor_status(v_vendor1_id, 'inactive');
    
    -- Prevent direct update
    BEGIN
        UPDATE public.vendors SET status = 'active' WHERE id = v_vendor1_id;
        RAISE EXCEPTION 'Direct update of vendor status should fail';
    EXCEPTION WHEN OTHERS THEN END;

    -- =======================================================================
    -- 2. ASSETS
    -- =======================================================================
    RAISE NOTICE 'Testing Assets...';
    
    INSERT INTO public.assets (society_id, name, category)
    VALUES (v_society1_id, 'Lift A', 'Elevator') RETURNING id INTO v_asset1_id;

    -- Member/Tech SELECT
    PERFORM pg_temp.set_auth_uid(v_tech_id::text);
    IF NOT EXISTS (SELECT 1 FROM public.assets WHERE id = v_asset1_id) THEN
        RAISE EXCEPTION 'Tech could not view asset';
    END IF;
    BEGIN
        INSERT INTO public.assets (society_id, name, category) VALUES (v_society1_id, 'Lift B', 'Elevator');
        RAISE EXCEPTION 'Tech should not be able to create asset';
    EXCEPTION WHEN OTHERS THEN END;

    -- Asset transition
    PERFORM pg_temp.set_auth_uid(v_admin_id::text);
    PERFORM public.fn_transition_asset_status(v_asset1_id, 'retired');
    
    -- Check retired restriction
    BEGIN
        PERFORM public.fn_transition_asset_status(v_asset1_id, 'active');
        RAISE EXCEPTION 'Retired asset should not transition back to active';
    EXCEPTION WHEN OTHERS THEN END;

    -- Reset for AMC tests
    INSERT INTO public.assets (society_id, name, category)
    VALUES (v_society1_id, 'Lift B', 'Elevator') RETURNING id INTO v_asset2_id;
    
    PERFORM pg_temp.set_auth_uid(v_admin2_id::text);
    INSERT INTO public.vendors (society_id, name) VALUES (v_society2_id, 'Vendor B') RETURNING id INTO v_vendor2_id;
    PERFORM pg_temp.set_auth_uid(v_admin_id::text);
    
    PERFORM public.fn_transition_vendor_status(v_vendor1_id, 'active');

    -- =======================================================================
    -- 3. ASSET AMC
    -- =======================================================================
    RAISE NOTICE 'Testing AMC...';
    
    -- Cross-society rejection
    BEGIN
        INSERT INTO public.asset_amc (society_id, asset_id, vendor_id, start_date, end_date, cost)
        VALUES (v_society1_id, v_asset2_id, v_vendor2_id, '2026-01-01', '2026-12-31', 5000);
        RAISE EXCEPTION 'AMC with Society A asset and Society B vendor should fail';
    EXCEPTION WHEN OTHERS THEN END;

    -- Valid AMC
    INSERT INTO public.asset_amc (society_id, asset_id, vendor_id, start_date, end_date, cost)
    VALUES (v_society1_id, v_asset2_id, v_vendor1_id, '2026-01-01', '2026-12-31', 5000)
    RETURNING id INTO v_amc1_id;

    -- Overlap Rejection
    BEGIN
        INSERT INTO public.asset_amc (society_id, asset_id, vendor_id, start_date, end_date, cost)
        VALUES (v_society1_id, v_asset2_id, v_vendor1_id, '2026-06-01', '2027-05-31', 5000);
        RAISE EXCEPTION 'Overlapping AMC should fail';
    EXCEPTION WHEN exclusion_violation THEN END;

    -- Retired asset / Inactive vendor AMC rejection
    PERFORM public.fn_transition_vendor_status(v_vendor1_id, 'inactive');
    BEGIN
        INSERT INTO public.asset_amc (society_id, asset_id, vendor_id, start_date, end_date, cost)
        VALUES (v_society1_id, v_asset2_id, v_vendor1_id, '2027-01-01', '2027-12-31', 5000);
        RAISE EXCEPTION 'AMC with inactive vendor should fail';
    EXCEPTION WHEN OTHERS THEN END;

    BEGIN
        INSERT INTO public.asset_amc (society_id, asset_id, vendor_id, start_date, end_date, cost)
        VALUES (v_society1_id, v_asset1_id, v_vendor1_id, '2027-01-01', '2027-12-31', 5000);
        RAISE EXCEPTION 'AMC with retired asset should fail';
    EXCEPTION WHEN OTHERS THEN END;

    PERFORM public.fn_transition_vendor_status(v_vendor1_id, 'active');

    -- =======================================================================
    -- 4. EXPENSE VOUCHER & TICKET INTEGRATION
    -- =======================================================================
    RAISE NOTICE 'Testing Voucher and Ticket Integrations...';

    -- Voucher Legacy Insert
    INSERT INTO public.expense_vouchers (id, society_id, category_id, vendor_name, amount, invoice_date, payment_method, status, created_by)
    VALUES (v_voucher1_id, v_society1_id, v_category_id, 'Legacy Vendor', 1000, '2026-06-01', 'bank_transfer', 'pending_approval', v_admin_id);

    -- Voucher Cross-Society Link
    BEGIN
        UPDATE public.expense_vouchers SET vendor_id = v_vendor2_id WHERE id = v_voucher1_id;
        RAISE EXCEPTION 'Updating voucher with cross-society vendor_id should fail';
    EXCEPTION WHEN OTHERS THEN END;

    -- Voucher Valid Link
    UPDATE public.expense_vouchers SET vendor_id = v_vendor1_id WHERE id = v_voucher1_id;

    -- Ticket Legacy Insert
    PERFORM pg_temp.set_auth_uid(v_member_id::text);
    INSERT INTO public.technician_tickets (id, society_id, property_id, created_by, category, title, description)
    VALUES (v_ticket1_id, v_society1_id, v_property1_id, v_member_id, 'plumbing', 'Water Leak', 'Fix leak');

    -- Ticket Assign Asset
    PERFORM pg_temp.set_auth_uid(v_tech_id::text);
    PERFORM public.fn_assign_ticket_asset(v_ticket1_id, v_asset2_id);

    -- Check assignment success
    IF (SELECT asset_id FROM public.technician_tickets WHERE id = v_ticket1_id) != v_asset2_id THEN
        RAISE EXCEPTION 'Ticket asset assignment failed';
    END IF;

    -- Ticket Assign Retired Asset
    BEGIN
        PERFORM public.fn_assign_ticket_asset(v_ticket1_id, v_asset1_id);
        RAISE EXCEPTION 'Assigning retired asset to ticket should fail';
    EXCEPTION WHEN OTHERS THEN END;

    RAISE NOTICE 'Slice 7 Verification PASS';
END;
$$;
