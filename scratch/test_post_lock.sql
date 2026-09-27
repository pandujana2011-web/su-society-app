-- Test 1: committee_resolution_votes UPDATE
DO $$
BEGIN
    SET LOCAL ROLE authenticated;
    SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000001';
    UPDATE committee_resolution_votes SET vote = 'against';
    RAISE NOTICE 'UPDATE votes succeeded (rows updated)';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'UPDATE votes blocked: %', SQLERRM;
END $$;

-- Test 2: committee_resolution_votes DELETE
DO $$
BEGIN
    SET LOCAL ROLE authenticated;
    SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000001';
    DELETE FROM committee_resolution_votes;
    RAISE NOTICE 'DELETE votes succeeded';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'DELETE votes blocked: %', SQLERRM;
END $$;

-- Test 3: committee_resolution_votes INSERT impersonating another voter
DO $$
DECLARE
    v_res_id UUID;
    v_count INT;
BEGIN
    SET LOCAL ROLE authenticated;
    SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000001';
    
    SELECT id INTO v_res_id FROM committee_resolutions LIMIT 1;
    
    IF v_res_id IS NOT NULL THEN
        INSERT INTO committee_resolution_votes (resolution_id, voter_id, vote, comments)
        VALUES (v_res_id, '00000000-0000-0000-0000-000000000099', 'against', 'impersonated vote');
        
        GET DIAGNOSTICS v_count = ROW_COUNT;
        RAISE NOTICE 'INSERT vote impersonation count: %', v_count;
    ELSE
        RAISE NOTICE 'No resolution found to test vote impersonation';
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'INSERT vote impersonation blocked: %', SQLERRM;
END $$;

-- Test 4: budget_line_items UPDATE
DO $$
BEGIN
    SET LOCAL ROLE authenticated;
    SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000001';
    UPDATE budget_line_items SET allocated_amount = 999999.00;
    RAISE NOTICE 'UPDATE budget_line_items succeeded';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'UPDATE budget_line_items blocked: %', SQLERRM;
END $$;

-- Test 5: budget_line_items DELETE
DO $$
BEGIN
    SET LOCAL ROLE authenticated;
    SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000001';
    DELETE FROM budget_line_items;
    RAISE NOTICE 'DELETE budget_line_items succeeded';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'DELETE budget_line_items blocked: %', SQLERRM;
END $$;

-- Test 6: budget_line_items INSERT
DO $$
DECLARE
    v_budget_id UUID;
    v_count INT;
BEGIN
    SET LOCAL ROLE authenticated;
    SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000001';
    
    SELECT id INTO v_budget_id FROM society_budgets LIMIT 1;
    
    IF v_budget_id IS NOT NULL THEN
        INSERT INTO budget_line_items (budget_id, category, allocated_amount, description)
        VALUES (v_budget_id, 'Hacked Category', 50000.00, 'Direct SQL insert');
        
        GET DIAGNOSTICS v_count = ROW_COUNT;
        RAISE NOTICE 'INSERT budget_line_items count: %', v_count;
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'INSERT budget_line_items blocked: %', SQLERRM;
END $$;

-- Test 7: Audit log direct INSERT
DO $$
BEGIN
    SET LOCAL ROLE authenticated;
    SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000001';
    INSERT INTO audit_logs (action, entity_name, entity_id, actor_id, details)
    VALUES ('FORGED_ACTION', 'committee_resolutions', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', '{"forged": true}');
    RAISE NOTICE 'INSERT audit_logs succeeded';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'INSERT audit_logs blocked: %', SQLERRM;
END $$;

-- Test 8: Audit log direct UPDATE
DO $$
BEGIN
    SET LOCAL ROLE authenticated;
    SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000001';
    UPDATE audit_logs SET action = 'ALTERED';
    RAISE NOTICE 'UPDATE audit_logs succeeded';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'UPDATE audit_logs blocked: %', SQLERRM;
END $$;

-- Test 9: Audit log direct DELETE
DO $$
BEGIN
    SET LOCAL ROLE authenticated;
    SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000001';
    DELETE FROM audit_logs;
    RAISE NOTICE 'DELETE audit_logs succeeded';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'DELETE audit_logs blocked: %', SQLERRM;
END $$;
