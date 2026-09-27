const fs = require('fs');
const path = require('path');

const schema = `
-- =========================================================================
-- SU SOCIETY APP - SLICE 4 SCHEMA
-- =========================================================================

-- =========================================================================
-- 1. CUSTOM BILLING
-- =========================================================================

CREATE TABLE IF NOT EXISTS public.custom_billing_subjects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    name VARCHAR(150) NOT NULL,
    description TEXT,
    billing_cycle VARCHAR(30) NOT NULL DEFAULT 'one_time'
        CONSTRAINT chk_cb_cycle CHECK (billing_cycle IN ('one_time', 'monthly', 'annual')),
    default_amount NUMERIC(15, 2) CONSTRAINT chk_cb_default_amt CHECK (default_amount >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_cb_subject_name UNIQUE (society_id, name)
);

CREATE TABLE IF NOT EXISTS public.custom_billing_responsibilities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    custom_subject_id UUID NOT NULL REFERENCES public.custom_billing_subjects(id) ON DELETE RESTRICT,
    property_id UUID NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    unit_id UUID REFERENCES public.units(id) ON DELETE RESTRICT,
    share_percentage NUMERIC(5, 2) CONSTRAINT chk_cb_share_pct CHECK (share_percentage > 0 AND share_percentage <= 100),
    share_amount NUMERIC(15, 2) CONSTRAINT chk_cb_share_amt CHECK (share_amount >= 0),
    start_date DATE NOT NULL,
    end_date DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_cb_resp_dates CHECK (end_date IS NULL OR start_date <= end_date),
    CONSTRAINT chk_cb_share_exclusive CHECK (
        (share_percentage IS NOT NULL AND share_amount IS NULL) OR
        (share_percentage IS NULL AND share_amount IS NOT NULL)
    )
);

-- =========================================================================
-- 2. OPENING BALANCES
-- =========================================================================

CREATE TABLE IF NOT EXISTS public.opening_balances (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    property_id UUID NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    amount NUMERIC(15, 2) NOT NULL CONSTRAINT chk_ob_amount CHECK (amount >= 0),
    direction VARCHAR(20) NOT NULL CONSTRAINT chk_ob_direction CHECK (direction IN ('debit', 'credit')),
    as_of_date DATE NOT NULL,
    posted_at TIMESTAMPTZ,
    created_by UUID REFERENCES public.users(id) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_property_ob UNIQUE (property_id, user_id, as_of_date)
);

-- =========================================================================
-- 3. EXPENSE VOUCHERS & BUDGETS
-- =========================================================================

CREATE TABLE IF NOT EXISTS public.expense_categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_exp_category_name UNIQUE (society_id, name)
);

CREATE TABLE IF NOT EXISTS public.budgets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE,
    category_id UUID NOT NULL REFERENCES public.expense_categories(id) ON DELETE CASCADE,
    allocated_amount NUMERIC(15, 2) NOT NULL CONSTRAINT chk_budget_amount CHECK (allocated_amount >= 0),
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    created_by UUID REFERENCES public.users(id) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_budget_dates CHECK (start_date <= end_date)
);

-- Exclude overlapping budgets via GiST (requires btree_gist extension which was added in Slice 1)
ALTER TABLE public.budgets ADD CONSTRAINT excl_budget_no_overlap 
    EXCLUDE USING gist (
        society_id WITH =,
        category_id WITH =,
        daterange(start_date, end_date, '[]') WITH &&
    );

CREATE TABLE IF NOT EXISTS public.expense_vouchers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE,
    category_id UUID NOT NULL REFERENCES public.expense_categories(id) ON DELETE RESTRICT,
    amount NUMERIC(15, 2) NOT NULL CONSTRAINT chk_voucher_amount CHECK (amount > 0),
    vendor_name VARCHAR(150) NOT NULL,
    invoice_number VARCHAR(100),
    invoice_date DATE NOT NULL,
    payment_method VARCHAR(30) NOT NULL CONSTRAINT chk_voucher_pay_method CHECK (payment_method IN ('upi', 'bank_transfer', 'cash', 'cheque')),
    reference_number VARCHAR(100),
    status VARCHAR(30) NOT NULL DEFAULT 'pending_approval' 
        CONSTRAINT chk_voucher_status CHECK (status IN ('pending_approval', 'approved', 'posted', 'rejected', 'reversed')),
    description TEXT,
    rejection_reason TEXT,
    reversal_reason TEXT,
    approved_by UUID REFERENCES public.users(id),
    posted_by UUID REFERENCES public.users(id),
    reversed_by UUID REFERENCES public.users(id),
    created_by UUID REFERENCES public.users(id) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =========================================================================
-- 4. PAYMENT ALLOCATIONS & RECEIPTS
-- =========================================================================

CREATE TABLE IF NOT EXISTS public.payment_allocations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_id UUID NOT NULL REFERENCES public.payments(id) ON DELETE CASCADE,
    charge_id UUID NOT NULL REFERENCES public.maintenance_charges(id) ON DELETE RESTRICT,
    amount NUMERIC(15, 2) NOT NULL CONSTRAINT chk_allocation_amount CHECK (amount > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_payment_charge_allocation UNIQUE (payment_id, charge_id)
);

CREATE SEQUENCE IF NOT EXISTS public.receipt_number_seq START 1;

CREATE TABLE IF NOT EXISTS public.receipts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    payment_id UUID NOT NULL UNIQUE REFERENCES public.payments(id) ON DELETE RESTRICT,
    receipt_number VARCHAR(50) NOT NULL UNIQUE,
    amount NUMERIC(15, 2) NOT NULL,
    receipt_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    allocation_snapshot JSONB NOT NULL,
    payer_snapshot JSONB NOT NULL,
    generated_by UUID REFERENCES public.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =========================================================================
-- 5. BANK RECONCILIATIONS
-- =========================================================================

CREATE TABLE IF NOT EXISTS public.bank_reconciliations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE,
    bank_statement_date DATE NOT NULL,
    opening_balance NUMERIC(15, 2) NOT NULL,
    closing_balance NUMERIC(15, 2) NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'draft' 
        CONSTRAINT chk_recon_status CHECK (status IN ('draft', 'completed')),
    reconciled_by UUID REFERENCES public.users(id),
    reconciled_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.bank_reconciliation_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE,
    reconciliation_id UUID NOT NULL REFERENCES public.bank_reconciliations(id) ON DELETE CASCADE,
    ledger_transaction_id UUID NOT NULL UNIQUE REFERENCES public.ledger_transactions(id) ON DELETE RESTRICT,
    bank_reference VARCHAR(100),
    bank_date DATE,
    bank_amount NUMERIC(15, 2),
    matched_by UUID REFERENCES public.users(id),
    matched_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =========================================================================
-- 6. NOTIFICATIONS
-- =========================================================================

CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE,
    recipient_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    type VARCHAR(50) NOT NULL,
    title VARCHAR(150) NOT NULL,
    body TEXT NOT NULL,
    related_entity_type VARCHAR(50),
    related_entity_id UUID,
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    read_at TIMESTAMPTZ
);

-- =========================================================================
-- 7. LEDGER INTEGRATION (ALTERATIONS)
-- =========================================================================

-- Add source_voucher_id to ledger_transactions
ALTER TABLE public.ledger_transactions ADD COLUMN source_voucher_id UUID REFERENCES public.expense_vouchers(id) ON DELETE RESTRICT;

-- Replace exclusive source constraint
ALTER TABLE public.ledger_transactions DROP CONSTRAINT chk_ledger_source_exclusive;
ALTER TABLE public.ledger_transactions ADD CONSTRAINT chk_ledger_source_exclusive CHECK (
    (CASE WHEN source_charge_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN source_payment_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN source_expense_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN source_booking_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN source_voucher_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN reverses_ledger_id IS NOT NULL THEN 1 ELSE 0 END) = 1
);

-- Recreate ledger consistency trigger to include source_voucher_id check
CREATE OR REPLACE FUNCTION public.trg_validate_ledger_consistency()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_source_society_id UUID;
BEGIN
    IF NEW.unit_id IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM public.units WHERE id = NEW.unit_id AND property_id = NEW.property_id) THEN
            RAISE EXCEPTION 'Unit % does not belong to Property %', NEW.unit_id, NEW.property_id;
        END IF;
    END IF;

    IF NEW.property_id IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM public.properties WHERE id = NEW.property_id AND society_id = NEW.society_id) THEN
            RAISE EXCEPTION 'Property % does not belong to Society %', NEW.property_id, NEW.society_id;
        END IF;
    END IF;

    IF NEW.source_charge_id IS NOT NULL THEN
        SELECT society_id INTO v_source_society_id FROM public.maintenance_charges WHERE id = NEW.source_charge_id;
    ELSIF NEW.source_payment_id IS NOT NULL THEN
        SELECT society_id INTO v_source_society_id FROM public.payments WHERE id = NEW.source_payment_id;
    ELSIF NEW.source_expense_id IS NOT NULL THEN
        SELECT society_id INTO v_source_society_id FROM public.expenses WHERE id = NEW.source_expense_id;
    ELSIF NEW.source_booking_id IS NOT NULL THEN
        SELECT a.society_id INTO v_source_society_id FROM public.amenity_bookings ab JOIN public.amenities a ON ab.amenity_id = a.id WHERE ab.id = NEW.source_booking_id;
    ELSIF NEW.source_voucher_id IS NOT NULL THEN
        SELECT society_id INTO v_source_society_id FROM public.expense_vouchers WHERE id = NEW.source_voucher_id;
    ELSIF NEW.reverses_ledger_id IS NOT NULL THEN
        SELECT society_id INTO v_source_society_id FROM public.ledger_transactions WHERE id = NEW.reverses_ledger_id;
    END IF;

    IF v_source_society_id IS NOT NULL AND v_source_society_id != NEW.society_id THEN
        RAISE EXCEPTION 'Source society % does not match ledger society %', v_source_society_id, NEW.society_id;
    END IF;

    RETURN NEW;
END;
$$;
-- (Trigger remains attached via BEFORE INSERT ON public.ledger_transactions)

-- =========================================================================
-- 8. SECURITY DEFINER FUNCTIONS (STATE MACHINES)
-- =========================================================================

-- A. Payment Verification with Allocation
CREATE OR REPLACE FUNCTION public.fn_verify_payment_with_allocation(
    p_payment_id UUID,
    p_allocations JSONB -- Array of { "charge_id": "uuid", "amount": number }
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller_society UUID;
    v_payment RECORD;
    v_alloc_item RECORD;
    v_charge RECORD;
    v_alloc_sum NUMERIC(15, 2) := 0;
    v_already_allocated NUMERIC(15, 2);
    v_outstanding NUMERIC(15, 2);
    v_advance NUMERIC(15, 2);
    v_receipt_num VARCHAR;
    v_receipt_id UUID;
    v_payer_info JSONB;
BEGIN
    v_caller_society := public.get_user_society_id(auth.uid());
    
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access Denied: Only admins can verify payments.';
    END IF;

    -- 1. Lock payment
    SELECT * INTO v_payment FROM public.payments WHERE id = p_payment_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Payment not found.'; END IF;
    
    -- 3. Validate society
    IF v_payment.society_id != v_caller_society THEN
        RAISE EXCEPTION 'Cross-society denied';
    END IF;

    -- 4. Validate state
    IF v_payment.status != 'pending_verification' THEN
        RAISE EXCEPTION 'Invalid transition: Payment must be pending verification.';
    END IF;

    -- 5. Validate allocations
    FOR v_alloc_item IN SELECT * FROM jsonb_to_recordset(p_allocations) AS x(charge_id UUID, amount NUMERIC) LOOP
        IF v_alloc_item.amount <= 0 THEN
            RAISE EXCEPTION 'Allocation amount must be greater than zero.';
        END IF;
        
        v_alloc_sum := v_alloc_sum + v_alloc_item.amount;
        
        SELECT * INTO v_charge FROM public.maintenance_charges WHERE id = v_alloc_item.charge_id FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION 'Charge % not found.', v_alloc_item.charge_id; END IF;
        
        IF v_charge.society_id != v_payment.society_id THEN RAISE EXCEPTION 'Charge belongs to a different society.'; END IF;
        IF v_charge.property_id != v_payment.property_id THEN RAISE EXCEPTION 'Charge belongs to a different property.'; END IF;
        
        -- Calculate outstanding
        SELECT COALESCE(SUM(pa.amount), 0) INTO v_already_allocated
        FROM public.payment_allocations pa
        JOIN public.payments p ON pa.payment_id = p.id
        WHERE pa.charge_id = v_alloc_item.charge_id AND p.status = 'verified';
        
        v_outstanding := v_charge.amount - v_already_allocated;
        IF v_alloc_item.amount > v_outstanding THEN
            RAISE EXCEPTION 'Allocation exceeds outstanding charge balance.';
        END IF;
    END LOOP;
    
    IF v_alloc_sum > v_payment.amount THEN
        RAISE EXCEPTION 'Allocations exceed total payment amount.';
    END IF;
    
    -- Insert Allocations
    FOR v_alloc_item IN SELECT * FROM jsonb_to_recordset(p_allocations) AS x(charge_id UUID, amount NUMERIC) LOOP
        INSERT INTO public.payment_allocations (payment_id, charge_id, amount)
        VALUES (p_payment_id, v_alloc_item.charge_id, v_alloc_item.amount);
    END LOOP;
    
    -- 8. Post to Ledger (exactly one ledger entry for the payment)
    INSERT INTO public.ledger_transactions (
        society_id, scope, property_id, unit_id, amount, direction, transaction_type, source_payment_id, description, created_by
    ) VALUES (
        v_payment.society_id, 'property', v_payment.property_id, v_payment.unit_id, v_payment.amount, 'credit', 'payment', p_payment_id, 'Verified payment', auth.uid()
    );
    
    -- 9. Generate Receipt
    v_receipt_num := 'REC-' || TO_CHAR(CURRENT_DATE, 'YYYYMMDD') || '-' || LPAD(nextval('public.receipt_number_seq')::text, 6, '0');
    v_payer_info := jsonb_build_object('user_id', v_payment.created_by, 'property_id', v_payment.property_id);
    
    INSERT INTO public.receipts (
        society_id, payment_id, receipt_number, amount, allocation_snapshot, payer_snapshot, generated_by
    ) VALUES (
        v_payment.society_id, p_payment_id, v_receipt_num, v_payment.amount, p_allocations, v_payer_info, auth.uid()
    ) RETURNING id INTO v_receipt_id;
    
    -- Update payment state
    UPDATE public.payments SET status = 'verified', posted_at = NOW(), verified_by = auth.uid() WHERE id = p_payment_id;
    
    -- 10. Audit
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_payment.society_id, auth.uid(), 'payment', p_payment_id, 'payment_verified_with_allocation', 
        jsonb_build_object('receipt_number', v_receipt_num, 'allocations', p_allocations));
        
    -- 11. Notification
    INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
    VALUES (v_payment.society_id, v_payment.created_by, 'payment_verified', 'Payment Verified', 
        'Your payment of ' || v_payment.amount || ' has been verified. Receipt: ' || v_receipt_num, 'payments', p_payment_id);
        
    RETURN v_receipt_id;
END;
$$;

-- B. Expense Voucher State Machine
CREATE OR REPLACE FUNCTION public.fn_transition_voucher_state(
    p_voucher_id UUID,
    p_new_state VARCHAR,
    p_reason TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller_society UUID;
    v_voucher RECORD;
BEGIN
    v_caller_society := public.get_user_society_id(auth.uid());
    
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access Denied: Only admins can manage vouchers.';
    END IF;

    SELECT * INTO v_voucher FROM public.expense_vouchers WHERE id = p_voucher_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Voucher not found.'; END IF;
    
    IF v_voucher.society_id != v_caller_society THEN
        RAISE EXCEPTION 'Cross-society denied';
    END IF;

    IF p_new_state = 'approved' THEN
        IF v_voucher.status != 'pending_approval' THEN RAISE EXCEPTION 'Invalid transition'; END IF;
        UPDATE public.expense_vouchers SET status = 'approved', approved_by = auth.uid() WHERE id = p_voucher_id;
        
    ELSIF p_new_state = 'rejected' THEN
        IF v_voucher.status != 'pending_approval' THEN RAISE EXCEPTION 'Invalid transition'; END IF;
        UPDATE public.expense_vouchers SET status = 'rejected', rejection_reason = p_reason WHERE id = p_voucher_id;
        
    ELSIF p_new_state = 'posted' THEN
        IF v_voucher.status != 'approved' THEN RAISE EXCEPTION 'Invalid transition'; END IF;
        
        -- Insert ledger
        INSERT INTO public.ledger_transactions (
            society_id, scope, amount, direction, transaction_type, source_voucher_id, description, created_by
        ) VALUES (
            v_voucher.society_id, 'society', v_voucher.amount, 'debit', 'expense', p_voucher_id, 'Expense voucher posted', auth.uid()
        );
        
        UPDATE public.expense_vouchers SET status = 'posted', posted_by = auth.uid() WHERE id = p_voucher_id;
        
    ELSIF p_new_state = 'reversed' THEN
        IF v_voucher.status != 'posted' THEN RAISE EXCEPTION 'Invalid transition'; END IF;
        
        -- Reverse ledger
        INSERT INTO public.ledger_transactions (
            society_id, scope, amount, direction, transaction_type, reverses_ledger_id, description, created_by
        )
        SELECT society_id, scope, amount, 'credit', 'reversal', id, 'Reversal of voucher: ' || COALESCE(p_reason, ''), auth.uid()
        FROM public.ledger_transactions WHERE source_voucher_id = p_voucher_id;
        
        UPDATE public.expense_vouchers SET status = 'reversed', reversal_reason = p_reason, reversed_by = auth.uid() WHERE id = p_voucher_id;
    ELSE
        RAISE EXCEPTION 'Invalid target state %', p_new_state;
    END IF;
    
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_voucher.society_id, auth.uid(), 'expense_voucher', p_voucher_id, 'voucher_' || p_new_state, 
        jsonb_build_object('status', p_new_state, 'reason', p_reason));
END;
$$;

-- C. Reconcile Transactions
CREATE OR REPLACE FUNCTION public.fn_reconcile_transactions(
    p_reconciliation_id UUID,
    p_ledger_transaction_ids UUID[]
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller_society UUID;
    v_recon RECORD;
    v_tx_id UUID;
    v_tx RECORD;
BEGIN
    v_caller_society := public.get_user_society_id(auth.uid());
    
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access Denied';
    END IF;
    
    SELECT * INTO v_recon FROM public.bank_reconciliations WHERE id = p_reconciliation_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Reconciliation not found.'; END IF;
    IF v_recon.society_id != v_caller_society THEN RAISE EXCEPTION 'Cross-society denied'; END IF;
    IF v_recon.status = 'completed' THEN RAISE EXCEPTION 'Reconciliation is completed and immutable.'; END IF;
    
    FOREACH v_tx_id IN ARRAY p_ledger_transaction_ids LOOP
        SELECT * INTO v_tx FROM public.ledger_transactions WHERE id = v_tx_id;
        IF NOT FOUND THEN RAISE EXCEPTION 'Ledger tx % not found.', v_tx_id; END IF;
        IF v_tx.society_id != v_recon.society_id THEN RAISE EXCEPTION 'Cross-society transaction % denied.', v_tx_id; END IF;
        
        -- Insert into mapping table, this throws if already matched due to UNIQUE constraint
        INSERT INTO public.bank_reconciliation_items (society_id, reconciliation_id, ledger_transaction_id, matched_by)
        VALUES (v_recon.society_id, p_reconciliation_id, v_tx_id, auth.uid());
    END LOOP;
    
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_recon.society_id, auth.uid(), 'bank_reconciliation', p_reconciliation_id, 'transactions_matched', 
        jsonb_build_object('transaction_ids', p_ledger_transaction_ids));
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_complete_reconciliation(
    p_reconciliation_id UUID
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller_society UUID;
    v_recon RECORD;
BEGIN
    v_caller_society := public.get_user_society_id(auth.uid());
    IF NOT public.is_admin() THEN RAISE EXCEPTION 'Access Denied'; END IF;
    
    SELECT * INTO v_recon FROM public.bank_reconciliations WHERE id = p_reconciliation_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Reconciliation not found.'; END IF;
    IF v_recon.society_id != v_caller_society THEN RAISE EXCEPTION 'Cross-society denied'; END IF;
    IF v_recon.status = 'completed' THEN RAISE EXCEPTION 'Already completed.'; END IF;
    
    UPDATE public.bank_reconciliations SET status = 'completed', reconciled_at = NOW(), reconciled_by = auth.uid()
    WHERE id = p_reconciliation_id;
    
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_recon.society_id, auth.uid(), 'bank_reconciliation', p_reconciliation_id, 'reconciliation_completed', '{}'::jsonb);
END;
$$;

-- D. Open Balance Booking
CREATE OR REPLACE FUNCTION public.fn_book_opening_balance(
    p_property_id UUID,
    p_user_id UUID,
    p_amount NUMERIC,
    p_direction VARCHAR,
    p_as_of_date DATE
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller_society UUID;
    v_prop RECORD;
    v_ob_id UUID;
BEGIN
    v_caller_society := public.get_user_society_id(auth.uid());
    IF NOT public.is_admin() THEN RAISE EXCEPTION 'Access Denied'; END IF;
    
    SELECT * INTO v_prop FROM public.properties WHERE id = p_property_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Property not found.'; END IF;
    IF v_prop.society_id != v_caller_society THEN RAISE EXCEPTION 'Cross-society denied'; END IF;
    
    -- Insert opening balance, unique constraint will prevent duplicates
    INSERT INTO public.opening_balances (society_id, property_id, user_id, amount, direction, as_of_date, posted_at, created_by)
    VALUES (v_caller_society, p_property_id, p_user_id, p_amount, p_direction, p_as_of_date, NOW(), auth.uid())
    RETURNING id INTO v_ob_id;
    
    -- No direct connection to ledger source columns existed in Slice 2 for OBs, we will use a generic adjustment entry.
    -- (We can't add source_opening_balance_id without violating the exclusivity rule, unless we extend it, but Slice 2 allows "no source" if it's an adjustment maybe? Wait, in Slice 2, chk_ledger_source_exclusive says exactly ONE source must be populated.
    -- Let's check Slice 2 chk_ledger_source_exclusive: wait, no, it sums them to 1.
    -- So we NEED a source for everything. We didn't add source_opening_balance_id!
    -- I MUST add source_opening_balance_id to ledger_transactions! 
    -- Let's amend the ALTER TABLE above to include source_opening_balance_id.)
    
    -- WAIT, in the script below, I'll update the ALTER TABLE block to include source_opening_balance_id.
    
    INSERT INTO public.ledger_transactions (
        society_id, scope, property_id, amount, direction, transaction_type, source_opening_balance_id, description, created_by
    ) VALUES (
        v_caller_society, 'property', p_property_id, p_amount, p_direction, 'opening_balance', v_ob_id, 'Opening balance', auth.uid()
    );
    
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_caller_society, auth.uid(), 'opening_balance', v_ob_id, 'opening_balance_posted', 
        jsonb_build_object('amount', p_amount, 'direction', p_direction, 'as_of_date', p_as_of_date));
        
    RETURN v_ob_id;
END;
$$;

-- Amend the ledger_transactions ALTER again to include opening balance source
ALTER TABLE public.ledger_transactions ADD COLUMN source_opening_balance_id UUID REFERENCES public.opening_balances(id) ON DELETE RESTRICT;

ALTER TABLE public.ledger_transactions DROP CONSTRAINT chk_ledger_source_exclusive;
ALTER TABLE public.ledger_transactions ADD CONSTRAINT chk_ledger_source_exclusive CHECK (
    (CASE WHEN source_charge_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN source_payment_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN source_expense_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN source_booking_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN source_voucher_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN source_opening_balance_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN reverses_ledger_id IS NOT NULL THEN 1 ELSE 0 END) = 1
);

ALTER TABLE public.ledger_transactions DROP CONSTRAINT chk_tx_type;
ALTER TABLE public.ledger_transactions ADD CONSTRAINT chk_tx_type CHECK (transaction_type IN ('charge', 'payment', 'expense', 'reversal', 'adjustment', 'opening_balance', 'booking_charge'));

-- =========================================================================
-- 9. TRIGGERS
-- =========================================================================

CREATE OR REPLACE FUNCTION public.trg_block_ob_update_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'Immutable record: Updates and Deletes are not allowed.';
END;
$$;

CREATE TRIGGER trg_opening_balances_immutable
BEFORE UPDATE OR DELETE ON public.opening_balances
FOR EACH ROW EXECUTE FUNCTION public.trg_block_ob_update_delete();

CREATE OR REPLACE FUNCTION public.trg_block_completed_reconciliation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.status = 'completed' THEN RAISE EXCEPTION 'Cannot delete completed reconciliation.'; END IF;
    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.status = 'completed' THEN RAISE EXCEPTION 'Cannot modify completed reconciliation.'; END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_reconciliation_immutable
BEFORE UPDATE OR DELETE ON public.bank_reconciliations
FOR EACH ROW EXECUTE FUNCTION public.trg_block_completed_reconciliation();

CREATE OR REPLACE FUNCTION public.trg_block_matched_tx_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_status VARCHAR;
BEGIN
    SELECT status INTO v_status FROM public.bank_reconciliations WHERE id = OLD.reconciliation_id;
    IF v_status = 'completed' THEN
        RAISE EXCEPTION 'Cannot remove items from completed reconciliation.';
    END IF;
    RETURN OLD;
END;
$$;

CREATE TRIGGER trg_recon_items_immutable
BEFORE DELETE ON public.bank_reconciliation_items
FOR EACH ROW EXECUTE FUNCTION public.trg_block_matched_tx_delete();

-- =========================================================================
-- 10. RLS POLICIES
-- =========================================================================

ALTER TABLE public.custom_billing_subjects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.custom_billing_responsibilities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.opening_balances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expense_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expense_vouchers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.budgets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_allocations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bank_reconciliations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bank_reconciliation_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.custom_billing_subjects FORCE ROW LEVEL SECURITY;
ALTER TABLE public.custom_billing_responsibilities FORCE ROW LEVEL SECURITY;
ALTER TABLE public.opening_balances FORCE ROW LEVEL SECURITY;
ALTER TABLE public.expense_categories FORCE ROW LEVEL SECURITY;
ALTER TABLE public.expense_vouchers FORCE ROW LEVEL SECURITY;
ALTER TABLE public.budgets FORCE ROW LEVEL SECURITY;
ALTER TABLE public.payment_allocations FORCE ROW LEVEL SECURITY;
ALTER TABLE public.receipts FORCE ROW LEVEL SECURITY;
ALTER TABLE public.bank_reconciliations FORCE ROW LEVEL SECURITY;
ALTER TABLE public.bank_reconciliation_items FORCE ROW LEVEL SECURITY;
ALTER TABLE public.notifications FORCE ROW LEVEL SECURITY;

-- Admins see all for their society, members see their own where applicable

-- custom_billing
CREATE POLICY p_cb_admin ON public.custom_billing_subjects FOR ALL USING (public.is_admin() AND society_id = public.get_user_society_id(auth.uid()));
CREATE POLICY p_cb_member ON public.custom_billing_subjects FOR SELECT USING (society_id = public.get_user_society_id(auth.uid()));

CREATE POLICY p_cbr_admin ON public.custom_billing_responsibilities FOR ALL USING (public.is_admin() AND society_id = public.get_user_society_id(auth.uid()));
CREATE POLICY p_cbr_member ON public.custom_billing_responsibilities FOR SELECT USING (user_id = auth.uid() OR public.is_property_owner(property_id));

-- opening_balances
CREATE POLICY p_ob_admin ON public.opening_balances FOR ALL USING (public.is_admin() AND society_id = public.get_user_society_id(auth.uid()));
CREATE POLICY p_ob_member ON public.opening_balances FOR SELECT USING (user_id = auth.uid() OR public.is_property_owner(property_id));

-- expense management
CREATE POLICY p_ec_admin ON public.expense_categories FOR ALL USING (public.is_admin() AND society_id = public.get_user_society_id(auth.uid()));
CREATE POLICY p_ec_member ON public.expense_categories FOR SELECT USING (society_id = public.get_user_society_id(auth.uid()));

CREATE POLICY p_ev_admin ON public.expense_vouchers FOR ALL USING (public.is_admin() AND society_id = public.get_user_society_id(auth.uid()));
CREATE POLICY p_ev_member ON public.expense_vouchers FOR SELECT USING (society_id = public.get_user_society_id(auth.uid()) AND status IN ('posted', 'approved'));

CREATE POLICY p_bdg_admin ON public.budgets FOR ALL USING (public.is_admin() AND society_id = public.get_user_society_id(auth.uid()));
CREATE POLICY p_bdg_member ON public.budgets FOR SELECT USING (society_id = public.get_user_society_id(auth.uid()));

-- payment allocations & receipts
CREATE POLICY p_pa_admin ON public.payment_allocations FOR ALL USING (public.is_admin() AND EXISTS (SELECT 1 FROM public.payments p WHERE p.id = payment_id AND p.society_id = public.get_user_society_id(auth.uid())));
CREATE POLICY p_pa_member ON public.payment_allocations FOR SELECT USING (EXISTS (SELECT 1 FROM public.payments p WHERE p.id = payment_id AND (p.user_id = auth.uid() OR public.is_property_owner(p.property_id))));

CREATE POLICY p_rcpt_admin ON public.receipts FOR ALL USING (public.is_admin() AND society_id = public.get_user_society_id(auth.uid()));
CREATE POLICY p_rcpt_member ON public.receipts FOR SELECT USING (EXISTS (SELECT 1 FROM public.payments p WHERE p.id = payment_id AND (p.user_id = auth.uid() OR public.is_property_owner(p.property_id))));

-- bank reconciliations
CREATE POLICY p_recon_admin ON public.bank_reconciliations FOR ALL USING (public.is_admin() AND society_id = public.get_user_society_id(auth.uid()));
CREATE POLICY p_recon_member ON public.bank_reconciliations FOR SELECT USING (society_id = public.get_user_society_id(auth.uid()) AND status = 'completed');

CREATE POLICY p_recon_item_admin ON public.bank_reconciliation_items FOR ALL USING (public.is_admin() AND society_id = public.get_user_society_id(auth.uid()));
CREATE POLICY p_recon_item_member ON public.bank_reconciliation_items FOR SELECT USING (EXISTS (SELECT 1 FROM public.bank_reconciliations r WHERE r.id = reconciliation_id AND r.status = 'completed') AND society_id = public.get_user_society_id(auth.uid()));

-- notifications
CREATE POLICY p_notif_admin ON public.notifications FOR ALL USING (public.is_admin() AND society_id = public.get_user_society_id(auth.uid()));
CREATE POLICY p_notif_self ON public.notifications FOR SELECT USING (recipient_user_id = auth.uid());
CREATE POLICY p_notif_upd ON public.notifications FOR UPDATE USING (recipient_user_id = auth.uid());

-- Fix trg_validate_ledger_consistency since I added source_opening_balance_id
CREATE OR REPLACE FUNCTION public.trg_validate_ledger_consistency()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_source_society_id UUID;
BEGIN
    IF NEW.unit_id IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM public.units WHERE id = NEW.unit_id AND property_id = NEW.property_id) THEN
            RAISE EXCEPTION 'Unit % does not belong to Property %', NEW.unit_id, NEW.property_id;
        END IF;
    END IF;

    IF NEW.property_id IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM public.properties WHERE id = NEW.property_id AND society_id = NEW.society_id) THEN
            RAISE EXCEPTION 'Property % does not belong to Society %', NEW.property_id, NEW.society_id;
        END IF;
    END IF;

    IF NEW.source_charge_id IS NOT NULL THEN
        SELECT society_id INTO v_source_society_id FROM public.maintenance_charges WHERE id = NEW.source_charge_id;
    ELSIF NEW.source_payment_id IS NOT NULL THEN
        SELECT society_id INTO v_source_society_id FROM public.payments WHERE id = NEW.source_payment_id;
    ELSIF NEW.source_expense_id IS NOT NULL THEN
        SELECT society_id INTO v_source_society_id FROM public.expenses WHERE id = NEW.source_expense_id;
    ELSIF NEW.source_booking_id IS NOT NULL THEN
        SELECT a.society_id INTO v_source_society_id FROM public.amenity_bookings ab JOIN public.amenities a ON ab.amenity_id = a.id WHERE ab.id = NEW.source_booking_id;
    ELSIF NEW.source_voucher_id IS NOT NULL THEN
        SELECT society_id INTO v_source_society_id FROM public.expense_vouchers WHERE id = NEW.source_voucher_id;
    ELSIF NEW.source_opening_balance_id IS NOT NULL THEN
        SELECT society_id INTO v_source_society_id FROM public.opening_balances WHERE id = NEW.source_opening_balance_id;
    ELSIF NEW.reverses_ledger_id IS NOT NULL THEN
        SELECT society_id INTO v_source_society_id FROM public.ledger_transactions WHERE id = NEW.reverses_ledger_id;
    END IF;

    IF v_source_society_id IS NOT NULL AND v_source_society_id != NEW.society_id THEN
        RAISE EXCEPTION 'Source society % does not match ledger society %', v_source_society_id, NEW.society_id;
    END IF;

    RETURN NEW;
END;
$$;
`;


-- Grants

schema += `
-- Grants
GRANT ALL ON TABLE public.payment_allocations TO authenticated;
GRANT ALL ON TABLE public.receipts TO authenticated;
GRANT ALL ON TABLE public.expense_categories TO authenticated;
GRANT ALL ON TABLE public.expense_vouchers TO authenticated;
GRANT ALL ON TABLE public.budgets TO authenticated;
GRANT ALL ON TABLE public.custom_billing_subjects TO authenticated;
GRANT ALL ON TABLE public.custom_billing_responsibilities TO authenticated;
GRANT ALL ON TABLE public.opening_balances TO authenticated;
GRANT ALL ON TABLE public.bank_reconciliations TO authenticated;
GRANT ALL ON TABLE public.bank_reconciliation_items TO authenticated;
GRANT ALL ON TABLE public.notifications TO authenticated;
`;
fs.writeFileSync(path.join(__dirname, '..', 'database', 'schema_slice4.sql'), schema);
console.log('schema_slice4.sql generated successfully.');