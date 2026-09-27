const fs = require('fs');
const path = require('path');
const file = path.join(__dirname, 'create_verify_slice4.js');
let content = fs.readFileSync(file, 'utf8');

const missingBlock = `        PERFORM public.fn_verify_payment_with_allocation(pay_a1, '[{"charge_id": "d6000000-0000-0000-0000-000000000001", "amount": 1000}]'::jsonb);
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

    -- =========================================================================`;

content = content.replace(/    BEGIN\s+-- =========================================================================/, "    BEGIN\n" + missingBlock);

fs.writeFileSync(file, content);
console.log('Restored missing block');
