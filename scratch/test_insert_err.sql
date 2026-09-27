DO $$
DECLARE
    v_user1 UUID;
    v_res_id UUID;
BEGIN
    SELECT id INTO v_user1 FROM public.users LIMIT 1;
    SELECT id INTO v_res_id FROM public.committee_resolutions LIMIT 1;
    
    SET LOCAL ROLE authenticated;
    EXECUTE format('SET LOCAL "request.jwt.claim.sub" = %L', v_user1::text);
    
    INSERT INTO public.committee_resolution_votes (resolution_id, voter_id, vote, comments)
    VALUES (v_res_id, gen_random_uuid(), 'against', 'Direct SQL impersonation');
    
    RAISE NOTICE 'INSERT succeeded!';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'INSERT exception caught: SQLSTATE %, SQLERRM %', SQLSTATE, SQLERRM;
END $$;
