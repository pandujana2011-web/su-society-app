-- =========================================================================
-- SU SOCIETY APP — SLICE 2 FINANCIAL SERIALIZATION SCHEMA (CORRECTED)
-- =========================================================================
-- Execution Mode: Controlled Security Execution (Slice 2 Only)
-- Architectural Anchor: public.properties FOR UPDATE (Mandatory Step 1)
-- Privilege Hardening: REVOKE direct write privileges; SECURITY DEFINER RPCs only
-- =========================================================================

-- 1. EXTENSIONS & DOMAINS
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. TABLES & INDEXES

-- 2.1 Maintenance Policies (Fee Structures)
CREATE TABLE IF NOT EXISTS public.maintenance_policies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE,
    title VARCHAR(100) NOT NULL,
    charge_type VARCHAR(20) NOT NULL CHECK (charge_type IN ('fixed', 'per_sqft')),
    rate NUMERIC(12,2) NOT NULL CHECK (rate >= 0),
    frequency VARCHAR(20) NOT NULL CHECK (frequency IN ('monthly', 'quarterly', 'annually')),
    due_day INT NOT NULL DEFAULT 5 CHECK (due_day BETWEEN 1 AND 28),
    grace_period_days INT NOT NULL DEFAULT 10 CHECK (grace_period_days >= 0),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES auth.users(id)
);

CREATE INDEX IF NOT EXISTS idx_policies_society ON public.maintenance_policies(society_id);

-- 2.2 Maintenance Charges (Assessed Debits)
CREATE TABLE IF NOT EXISTS public.maintenance_charges (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE,
    policy_id UUID REFERENCES public.maintenance_policies(id),
    property_id UUID NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
    unit_id UUID REFERENCES public.units(id),
    billing_period VARCHAR(7) NOT NULL, -- Format: 'YYYY-MM'
    amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    status VARCHAR(20) NOT NULL DEFAULT 'posted' CHECK (status IN ('posted', 'reversed', 'cancelled')),
    billing_basis_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES auth.users(id)
);

CREATE INDEX IF NOT EXISTS idx_charges_property ON public.maintenance_charges(property_id);
CREATE INDEX IF NOT EXISTS idx_charges_period ON public.maintenance_charges(society_id, billing_period);

-- 2.3 Payments (Remittances & Collections)
CREATE TABLE IF NOT EXISTS public.payments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE,
    property_id UUID NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
    unit_id UUID REFERENCES public.units(id),
    amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    payment_method VARCHAR(30) NOT NULL CHECK (payment_method IN ('bank_transfer', 'upi', 'cheque', 'cash', 'gateway')),
    reference_number VARCHAR(100) NOT NULL,
    proof_attachment_url TEXT,
    status VARCHAR(20) NOT NULL DEFAULT 'pending_verification' CHECK (status IN ('pending_verification', 'verified', 'rejected', 'reversed')),
    verification_reason TEXT,
    posted_at TIMESTAMPTZ,
    verified_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES auth.users(id)
);

CREATE INDEX IF NOT EXISTS idx_payments_property ON public.payments(property_id);
CREATE INDEX IF NOT EXISTS idx_payments_status ON public.payments(society_id, status);

-- 2.4 Expenses (Society Operating Disbursements)
CREATE TABLE IF NOT EXISTS public.expenses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE,
    amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    category VARCHAR(50) NOT NULL,
    description TEXT NOT NULL,
    voucher_attachment_url TEXT,
    status VARCHAR(20) NOT NULL DEFAULT 'posted' CHECK (status IN ('posted', 'reversed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES auth.users(id)
);

CREATE INDEX IF NOT EXISTS idx_expenses_society ON public.expenses(society_id);

-- 2.5 Ledger Transactions (Authoritative Immutable Financial Ledger)
CREATE TABLE IF NOT EXISTS public.ledger_transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE,
    scope VARCHAR(20) NOT NULL CHECK (scope IN ('property', 'society')),
    property_id UUID REFERENCES public.properties(id) ON DELETE CASCADE,
    unit_id UUID REFERENCES public.units(id),
    amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    direction VARCHAR(10) NOT NULL CHECK (direction IN ('debit', 'credit')),
    transaction_type VARCHAR(30) NOT NULL CHECK (transaction_type IN ('charge', 'payment', 'expense', 'reversal', 'adjustment')),
    source_charge_id UUID REFERENCES public.maintenance_charges(id),
    source_payment_id UUID REFERENCES public.payments(id),
    source_expense_id UUID REFERENCES public.expenses(id),
    reverses_ledger_id UUID REFERENCES public.ledger_transactions(id),
    description TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES auth.users(id),
    CONSTRAINT chk_ledger_scope_target CHECK (
        (scope = 'property' AND property_id IS NOT NULL) OR
        (scope = 'society' AND property_id IS NULL)
    )
);

CREATE INDEX IF NOT EXISTS idx_ledger_property ON public.ledger_transactions(property_id);
CREATE INDEX IF NOT EXISTS idx_ledger_society ON public.ledger_transactions(society_id);

-- 3. APPEND-ONLY LEDGER IMMUTABILITY TRIGGER
CREATE OR REPLACE FUNCTION public.trg_block_update_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'Ledger transactions are immutable append-only records. UPDATE and DELETE are prohibited.';
END;
$$;

DROP TRIGGER IF EXISTS trg_ledger_protect ON public.ledger_transactions;
CREATE TRIGGER trg_ledger_protect
BEFORE UPDATE OR DELETE ON public.ledger_transactions
FOR EACH ROW EXECUTE FUNCTION public.trg_block_update_delete();

-- 4. ROW LEVEL SECURITY (RLS)
ALTER TABLE public.maintenance_policies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.maintenance_charges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ledger_transactions ENABLE ROW LEVEL SECURITY;

-- 4.1 Policies Select Policies
CREATE POLICY pol_policies_select ON public.maintenance_policies FOR SELECT 
    USING (society_id = public.get_user_society_id(auth.uid()));

-- 4.2 Charges Select Policies
CREATE POLICY pol_charges_select ON public.maintenance_charges FOR SELECT 
    USING (society_id = public.get_user_society_id(auth.uid()) AND (
        public.is_admin() OR 
        public.is_property_owner(auth.uid(), property_id) OR 
        public.is_property_tenant(auth.uid(), property_id)
    ));

-- 4.3 Payments Select Policies
CREATE POLICY pol_payments_select ON public.payments FOR SELECT 
    USING (society_id = public.get_user_society_id(auth.uid()) AND (
        public.is_admin() OR 
        public.is_property_owner(auth.uid(), property_id) OR 
        public.is_property_tenant(auth.uid(), property_id)
    ));

-- 4.4 Expenses Select Policies
CREATE POLICY pol_expenses_select ON public.expenses FOR SELECT 
    USING (public.is_admin() AND society_id = public.get_user_society_id(auth.uid()));

-- 4.5 Ledger Select Policies
CREATE POLICY pol_ledger_select_admin ON public.ledger_transactions FOR SELECT 
    USING (public.is_admin() AND society_id = public.get_user_society_id(auth.uid()));
CREATE POLICY pol_ledger_select_owner ON public.ledger_transactions FOR SELECT 
    USING (scope = 'property' AND public.is_property_owner(auth.uid(), property_id));
CREATE POLICY pol_ledger_select_tenant ON public.ledger_transactions FOR SELECT 
    USING (scope = 'property' AND public.is_property_tenant(auth.uid(), property_id));


-- =========================================================================
-- 5. HARDENED FINANCIAL SERIALIZATION RPCs (SECURITY DEFINER)
-- =========================================================================

-- 5.1 Helper: Outstanding Property Balance
CREATE OR REPLACE FUNCTION public.fn_get_property_outstanding_balance(p_property_id UUID)
RETURNS NUMERIC
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public, pg_temp
AS $$
    SELECT COALESCE(SUM(CASE WHEN direction = 'debit' THEN amount ELSE 0 END), 0) -
           COALESCE(SUM(CASE WHEN direction = 'credit' THEN amount ELSE 0 END), 0)
    FROM public.ledger_transactions
    WHERE property_id = p_property_id;
$$;

-- 5.2 Generate Charge
CREATE OR REPLACE FUNCTION public.fn_generate_charge(
    p_property_id UUID,
    p_unit_id UUID,
    p_policy_id UUID,
    p_billing_period VARCHAR
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_society_id UUID;
    v_policy_rate NUMERIC;
    v_charge_type VARCHAR;
    v_amount NUMERIC;
    v_charge_id UUID;
    v_ledger_id UUID;
    v_caller_society UUID;
BEGIN
    -- Validate Admin Caller
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access Denied: Must be an admin';
    END IF;

    v_caller_society := public.get_user_society_id(auth.uid());

    -- MANDATORY STEP 1: Acquire Property Row Lock (Serialization Anchor)
    PERFORM 1 FROM public.properties WHERE id = p_property_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invalid property ID';
    END IF;

    -- Validate Property Society Scope
    SELECT society_id INTO v_society_id FROM public.properties WHERE id = p_property_id;
    IF v_society_id IS NULL OR v_society_id != v_caller_society THEN
        RAISE EXCEPTION 'Invalid property or society mismatch';
    END IF;

    -- Fetch Policy
    SELECT charge_type, rate INTO v_charge_type, v_policy_rate FROM public.maintenance_policies 
    WHERE id = p_policy_id AND society_id = v_society_id AND is_active = TRUE;
    
    IF v_policy_rate IS NULL THEN
        RAISE EXCEPTION 'Invalid or inactive policy';
    END IF;

    -- Calculate Amount
    IF v_charge_type = 'fixed' THEN
        v_amount := v_policy_rate;
    ELSE
        v_amount := v_policy_rate * 1000; 
    END IF;

    IF v_amount <= 0 THEN
        RAISE EXCEPTION 'Amount must be positive';
    END IF;

    -- Generate Charge
    INSERT INTO public.maintenance_charges (
        society_id, policy_id, property_id, unit_id, billing_period, amount, status, billing_basis_snapshot, created_by
    ) VALUES (
        v_society_id, p_policy_id, p_property_id, p_unit_id, p_billing_period, v_amount, 'posted', 
        jsonb_build_object('charge_type', v_charge_type, 'rate', v_policy_rate, 'calculated_amount', v_amount), 
        auth.uid()
    ) RETURNING id INTO v_charge_id;

    -- Ledger Debit
    INSERT INTO public.ledger_transactions (
        society_id, scope, property_id, unit_id, amount, direction, transaction_type, source_charge_id, description, created_by
    ) VALUES (
        v_society_id, 'property', p_property_id, p_unit_id, v_amount, 'debit', 'charge', v_charge_id, 'Maintenance Charge for ' || p_billing_period, auth.uid()
    ) RETURNING id INTO v_ledger_id;

    -- Audit Log
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_society_id, auth.uid(), 'maintenance_charge', v_charge_id, 'charge_generated', jsonb_build_object('amount', v_amount, 'ledger_id', v_ledger_id));

    RETURN v_charge_id;
END;
$$;

-- 5.3 Process Payment
CREATE OR REPLACE FUNCTION public.fn_process_payment(
    p_payment_id UUID,
    p_action VARCHAR, -- 'verified', 'rejected'
    p_reason TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_payment RECORD;
    v_property_id UUID;
    v_ledger_id UUID;
    v_caller_society UUID;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access Denied: Must be an admin';
    END IF;

    v_caller_society := public.get_user_society_id(auth.uid());

    -- Resolve Property ID
    SELECT property_id INTO v_property_id FROM public.payments WHERE id = p_payment_id;
    IF v_property_id IS NULL THEN
        RAISE EXCEPTION 'Payment not found';
    END IF;

    -- MANDATORY STEP 1: Acquire Property Row Lock (Serialization Anchor)
    PERFORM 1 FROM public.properties WHERE id = v_property_id FOR UPDATE;

    -- MANDATORY STEP 2: Lock Secondary Payment Record
    SELECT * INTO v_payment FROM public.payments WHERE id = p_payment_id FOR UPDATE;

    IF v_payment.society_id != v_caller_society THEN
        RAISE EXCEPTION 'Cross-society payment processing denied';
    END IF;

    IF v_payment.status != 'pending_verification' THEN
        RAISE EXCEPTION 'Invalid state transition: Payment is %', v_payment.status;
    END IF;

    IF p_action = 'verified' THEN
        UPDATE public.payments 
        SET status = 'verified', posted_at = NOW(), verified_by = auth.uid()
        WHERE id = p_payment_id;

        -- Create Credit Ledger Entry
        INSERT INTO public.ledger_transactions (
            society_id, scope, property_id, unit_id, amount, direction, transaction_type, source_payment_id, description, created_by
        ) VALUES (
            v_payment.society_id, 'property', v_payment.property_id, v_payment.unit_id, v_payment.amount, 'credit', 'payment', p_payment_id, 'Payment ' || v_payment.reference_number, auth.uid()
        ) RETURNING id INTO v_ledger_id;

        INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
        VALUES (v_payment.society_id, auth.uid(), 'payment', p_payment_id, 'payment_verified', jsonb_build_object('ledger_id', v_ledger_id));

    ELSIF p_action = 'rejected' THEN
        UPDATE public.payments 
        SET status = 'rejected', verification_reason = p_reason, verified_by = auth.uid()
        WHERE id = p_payment_id;

        INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
        VALUES (v_payment.society_id, auth.uid(), 'payment', p_payment_id, 'payment_rejected', jsonb_build_object('reason', p_reason));
    ELSE
        RAISE EXCEPTION 'Invalid action. Must be verified or rejected.';
    END IF;
END;
$$;

-- 5.4 Reverse Charge
CREATE OR REPLACE FUNCTION public.fn_reverse_charge(
    p_charge_id UUID,
    p_reason TEXT
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_charge RECORD;
    v_property_id UUID;
    v_ledger RECORD;
    v_new_ledger_id UUID;
    v_caller_society UUID;
BEGIN
    IF NOT public.is_admin() THEN RAISE EXCEPTION 'Access Denied'; END IF;
    v_caller_society := public.get_user_society_id(auth.uid());

    SELECT property_id INTO v_property_id FROM public.maintenance_charges WHERE id = p_charge_id;
    IF v_property_id IS NULL THEN RAISE EXCEPTION 'Charge not found'; END IF;

    -- MANDATORY STEP 1: Acquire Property Row Lock
    PERFORM 1 FROM public.properties WHERE id = v_property_id FOR UPDATE;

    -- MANDATORY STEP 2: Lock Secondary Charge Record
    SELECT * INTO v_charge FROM public.maintenance_charges WHERE id = p_charge_id FOR UPDATE;
    IF v_charge.society_id != v_caller_society THEN RAISE EXCEPTION 'Cross-society denied'; END IF;
    IF v_charge.status = 'reversed' THEN RAISE EXCEPTION 'Already reversed'; END IF;

    SELECT * INTO v_ledger FROM public.ledger_transactions WHERE source_charge_id = p_charge_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Ledger transaction not found'; END IF;

    UPDATE public.maintenance_charges SET status = 'reversed' WHERE id = p_charge_id;

    -- Compensating Credit
    INSERT INTO public.ledger_transactions (
        society_id, scope, property_id, unit_id, amount, direction, transaction_type, reverses_ledger_id, description, created_by
    ) VALUES (
        v_charge.society_id, 'property', v_charge.property_id, v_charge.unit_id, v_ledger.amount, 'credit', 'reversal', v_ledger.id, 'Reversal: ' || p_reason, auth.uid()
    ) RETURNING id INTO v_new_ledger_id;

    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_charge.society_id, auth.uid(), 'maintenance_charge', p_charge_id, 'charge_reversed', jsonb_build_object('reason', p_reason, 'reversal_ledger_id', v_new_ledger_id));
END;
$$;

-- 5.5 Reverse Payment
CREATE OR REPLACE FUNCTION public.fn_reverse_payment(
    p_payment_id UUID,
    p_reversal_reason VARCHAR
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_payment RECORD;
    v_property_id UUID;
    v_ledger RECORD;
    v_new_ledger_id UUID;
    v_caller_society UUID;
BEGIN
    IF NOT public.is_admin() THEN RAISE EXCEPTION 'Access Denied'; END IF;
    v_caller_society := public.get_user_society_id(auth.uid());

    SELECT property_id INTO v_property_id FROM public.payments WHERE id = p_payment_id;
    IF v_property_id IS NULL THEN RAISE EXCEPTION 'Payment not found'; END IF;

    -- MANDATORY STEP 1: Acquire Property Row Lock
    PERFORM 1 FROM public.properties WHERE id = v_property_id FOR UPDATE;

    -- MANDATORY STEP 2: Lock Secondary Payment Record
    SELECT * INTO v_payment FROM public.payments WHERE id = p_payment_id FOR UPDATE;
    IF v_payment.society_id != v_caller_society THEN RAISE EXCEPTION 'Cross-society denied'; END IF;
    IF v_payment.status != 'verified' THEN RAISE EXCEPTION 'Only verified payments can be reversed'; END IF;

    SELECT * INTO v_ledger FROM public.ledger_transactions WHERE source_payment_id = p_payment_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Ledger transaction not found'; END IF;

    UPDATE public.payments SET status = 'reversed', reversal_reason = p_reversal_reason WHERE id = p_payment_id;

    -- Compensating Debit
    INSERT INTO public.ledger_transactions (
        society_id, scope, property_id, unit_id, amount, direction, transaction_type, reverses_ledger_id, description, created_by
    ) VALUES (
        v_payment.society_id, 'property', v_payment.property_id, v_payment.unit_id, v_ledger.amount, 'debit', 'reversal', v_ledger.id, 'Payment Reversal: ' || p_reversal_reason, auth.uid()
    ) RETURNING id INTO v_new_ledger_id;

    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_payment.society_id, auth.uid(), 'payment', p_payment_id, 'payment_reversed', jsonb_build_object('reason', p_reversal_reason, 'reversal_ledger_id', v_new_ledger_id));
END;
$$;

-- 5.6 Post Expense (Society Scope)
CREATE OR REPLACE FUNCTION public.fn_post_expense(
    p_society_id UUID,
    p_amount NUMERIC,
    p_category VARCHAR,
    p_description TEXT
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_expense_id UUID;
    v_ledger_id UUID;
BEGIN
    IF NOT public.is_admin() THEN RAISE EXCEPTION 'Access Denied'; END IF;
    IF p_society_id != public.get_user_society_id(auth.uid()) THEN RAISE EXCEPTION 'Cross-society denied'; END IF;
    IF p_amount <= 0 THEN RAISE EXCEPTION 'Amount must be positive'; END IF;

    INSERT INTO public.expenses (society_id, amount, category, description, status, created_by)
    VALUES (p_society_id, p_amount, p_category, p_description, 'posted', auth.uid())
    RETURNING id INTO v_expense_id;

    INSERT INTO public.ledger_transactions (
        society_id, scope, amount, direction, transaction_type, source_expense_id, description, created_by
    ) VALUES (
        p_society_id, 'society', p_amount, 'debit', 'expense', v_expense_id, p_description, auth.uid()
    ) RETURNING id INTO v_ledger_id;

    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (p_society_id, auth.uid(), 'expense', v_expense_id, 'expense_posted', jsonb_build_object('ledger_id', v_ledger_id));

    RETURN v_expense_id;
END;
$$;

-- 5.7 Reverse Expense (Society Scope)
CREATE OR REPLACE FUNCTION public.fn_reverse_expense(
    p_expense_id UUID,
    p_reason TEXT
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_expense RECORD;
    v_ledger RECORD;
    v_new_ledger_id UUID;
    v_caller_society UUID;
BEGIN
    IF NOT public.is_admin() THEN RAISE EXCEPTION 'Access Denied'; END IF;
    v_caller_society := public.get_user_society_id(auth.uid());

    SELECT * INTO v_expense FROM public.expenses WHERE id = p_expense_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Expense not found'; END IF;
    IF v_expense.society_id != v_caller_society THEN RAISE EXCEPTION 'Cross-society denied'; END IF;
    IF v_expense.status = 'reversed' THEN RAISE EXCEPTION 'Already reversed'; END IF;

    SELECT * INTO v_ledger FROM public.ledger_transactions WHERE source_expense_id = p_expense_id;

    UPDATE public.expenses SET status = 'reversed' WHERE id = p_expense_id;

    INSERT INTO public.ledger_transactions (
        society_id, scope, amount, direction, transaction_type, reverses_ledger_id, description, created_by
    ) VALUES (
        v_expense.society_id, 'society', v_ledger.amount, 'credit', 'reversal', v_ledger.id, 'Expense Reversal: ' || p_reason, auth.uid()
    ) RETURNING id INTO v_new_ledger_id;

    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_expense.society_id, auth.uid(), 'expense', p_expense_id, 'expense_reversed', jsonb_build_object('reason', p_reason, 'reversal_ledger_id', v_new_ledger_id));
END;
$$;

-- =========================================================================
-- 6. PRIVILEGE HARDENING & DIRECT-WRITE LOCKDOWN
-- =========================================================================

-- REVOKE DIRECT WRITE PRIVILEGES FROM PUBLIC CLIENT ROLES
REVOKE INSERT, UPDATE, DELETE ON public.maintenance_policies FROM authenticated, anon, PUBLIC;
REVOKE INSERT, UPDATE, DELETE ON public.maintenance_charges FROM authenticated, anon, PUBLIC;
REVOKE INSERT, UPDATE, DELETE ON public.payments FROM authenticated, anon, PUBLIC;
REVOKE INSERT, UPDATE, DELETE ON public.expenses FROM authenticated, anon, PUBLIC;
REVOKE INSERT, UPDATE, DELETE ON public.ledger_transactions FROM authenticated, anon, PUBLIC;

-- GRANT READ-ONLY SELECT PRIVILEGES FOR RLS ENFORCEMENT
GRANT SELECT ON public.maintenance_policies TO authenticated;
GRANT SELECT ON public.maintenance_charges TO authenticated;
GRANT SELECT ON public.payments TO authenticated;
GRANT SELECT ON public.expenses TO authenticated;
GRANT SELECT ON public.ledger_transactions TO authenticated;

-- GRANT EXECUTE PRIVILEGES FOR SECURITY DEFINER RPCs
GRANT EXECUTE ON FUNCTION public.fn_get_property_outstanding_balance(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_generate_charge(UUID, UUID, UUID, VARCHAR) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_process_payment(UUID, VARCHAR, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_reverse_charge(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_reverse_payment(UUID, VARCHAR) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_post_expense(UUID, NUMERIC, VARCHAR, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_reverse_expense(UUID, TEXT) TO authenticated;
