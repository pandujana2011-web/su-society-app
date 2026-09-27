const fs = require('fs');
const path = require('path');
const file = path.join(__dirname, 'create_verify_slice4.js');
let content = fs.readFileSync(file, 'utf8');

const missingBlock = `    IF v_count != 1 THEN RAISE EXCEPTION 'FAIL: Voucher compensating reversal not found'; END IF;

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
    BEGIN`;

content = content.replace(/    IF v_count != 1 THEN RAISE EXCEPTION 'FAIL: Voucher compensating reversal not found'; END IF;\s+BEGIN/, missingBlock);

fs.writeFileSync(file, content);
console.log('Restored missing block');
