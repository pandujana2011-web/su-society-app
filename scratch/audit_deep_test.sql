DO $$
DECLARE
    v_user1 UUID;
    v_count INT;
BEGIN
    SELECT id INTO v_user1 FROM public.users LIMIT 1;
    
    SET LOCAL ROLE authenticated;
    EXECUTE format('SET LOCAL "request.jwt.claim.sub" = %L', v_user1::text);
    
    -- Attempt direct INSERT into audit_logs
    BEGIN
        INSERT INTO audit_logs (action, entity_type, entity_id, actor_id)
        VALUES ('FORGED_ACTION', 'committee_resolutions', v_user1, v_user1);
        GET DIAGNOSTICS v_count = ROW_COUNT;
        RAISE NOTICE 'Audit Log INSERT rows affected: %', v_count;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Audit Log INSERT BLOCKED: %', SQLERRM;
    END;
    
    -- Attempt direct UPDATE on audit_logs
    UPDATE audit_logs SET action = 'ALTERED';
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'Audit Log UPDATE rows affected: %', v_count;

    -- Attempt direct DELETE on audit_logs
    DELETE FROM audit_logs;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'Audit Log DELETE rows affected: %', v_count;
END $$;
