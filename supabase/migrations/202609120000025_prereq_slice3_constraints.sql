-- =========================================================================
-- REMEDIATION MIGRATION: Prereq Constraints for Slice 3 Execution
-- Target Table: public.ledger_transactions
-- =========================================================================

-- 1. Remove Slice 2 auto-generated inline check constraint if present
ALTER TABLE public.ledger_transactions
DROP CONSTRAINT IF EXISTS ledger_transactions_transaction_type_check;

-- 2. Establish the exact constraint name expected by Slice 3
ALTER TABLE public.ledger_transactions
DROP CONSTRAINT IF EXISTS chk_tx_type;

ALTER TABLE public.ledger_transactions
ADD CONSTRAINT chk_tx_type CHECK (
    transaction_type IN (
        'charge',
        'payment',
        'expense',
        'reversal',
        'adjustment'
    )
);

-- 3. Establish the exact constraint name expected by Slice 3
ALTER TABLE public.ledger_transactions
DROP CONSTRAINT IF EXISTS chk_ledger_source_exclusive;

ALTER TABLE public.ledger_transactions
ADD CONSTRAINT chk_ledger_source_exclusive CHECK (
    (CASE WHEN source_charge_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN source_payment_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN source_expense_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN reverses_ledger_id IS NOT NULL THEN 1 ELSE 0 END) = 1
);
