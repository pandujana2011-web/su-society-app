-- SU Society App — Database Schema Setup (Phase 2 - Unified Financial Framework)
-- Target: PostgreSQL / Supabase Postgres

-- =========================================================================
-- 1. BASE STRUCTURES & SEQUENCES
-- =========================================================================

-- Safe receipt sequence number generator
CREATE SEQUENCE IF NOT EXISTS public.receipt_number_seq START 1;

CREATE OR REPLACE FUNCTION public.generate_receipt_number()
RETURNS VARCHAR AS $$
DECLARE
    seq_val INT;
    rec_num VARCHAR;
BEGIN
    seq_val := nextval('public.receipt_number_seq');
    rec_num := 'REC-' || TO_CHAR(CURRENT_DATE, 'YYYYMMDD') || '-' || LPAD(seq_val::text, 6, '0');
    RETURN rec_num;
END;
$$ LANGUAGE plpgsql;

-- =========================================================================
-- 2. PHASE 2A TABLES
-- =========================================================================

-- Maintenance Policies Table
CREATE TABLE IF NOT EXISTS public.maintenance_policies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    formula_type VARCHAR(30) NOT NULL
        CONSTRAINT check_policy_formula CHECK (formula_type IN ('per_plot', 'per_sqft', 'per_unit', 'per_family', 'fixed', 'custom')),
    rate NUMERIC(15, 2) NOT NULL CONSTRAINT check_policy_rate CHECK (rate >= 0),
    description TEXT,
    effective_from DATE NOT NULL,
    effective_to DATE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    version INTEGER NOT NULL DEFAULT 1,
    created_by UUID REFERENCES public.users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    CONSTRAINT check_policy_dates CHECK (effective_to IS NULL OR effective_from <= effective_to)
);

-- Custom Billing Subjects Table
CREATE TABLE IF NOT EXISTS public.custom_billing_subjects (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(150) NOT NULL UNIQUE,
    description TEXT,
    billing_cycle VARCHAR(30) NOT NULL DEFAULT 'one_time'
        CONSTRAINT check_billing_cycle CHECK (billing_cycle IN ('one_time', 'monthly', 'annual')),
    default_amount NUMERIC(15, 2) CONSTRAINT check_default_amount CHECK (default_amount >= 0),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

-- Custom Billing Responsibilities Table
CREATE TABLE IF NOT EXISTS public.custom_billing_responsibilities (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    custom_subject_id UUID NOT NULL REFERENCES public.custom_billing_subjects(id) ON DELETE CASCADE,
    property_id UUID NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    share_percentage NUMERIC(5, 2) CONSTRAINT check_share_percentage CHECK (share_percentage > 0 AND share_percentage <= 100),
    share_amount NUMERIC(15, 2) CONSTRAINT check_share_amount CHECK (share_amount >= 0),
    start_date DATE NOT NULL,
    end_date DATE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    CONSTRAINT check_responsibility_dates CHECK (end_date IS NULL OR start_date <= end_date),
    CONSTRAINT check_share_exclusivity CHECK (
        (share_percentage IS NOT NULL AND share_amount IS NULL) OR
        (share_percentage IS NULL AND share_amount IS NOT NULL)
    )
);

-- Maintenance Charges Table (Generated Dues)
CREATE TABLE IF NOT EXISTS public.maintenance_charges (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    billing_subject_type VARCHAR(30) NOT NULL
        CONSTRAINT check_charge_subject_type CHECK (billing_subject_type IN ('property', 'unit', 'family', 'custom')),
    property_id UUID REFERENCES public.properties(id) ON DELETE RESTRICT,
    unit_id UUID REFERENCES public.units(id) ON DELETE RESTRICT,
    family_id UUID REFERENCES public.family_groups(id) ON DELETE RESTRICT,
    custom_subject_id UUID REFERENCES public.custom_billing_subjects(id) ON DELETE RESTRICT,
    amount NUMERIC(15, 2) NOT NULL CONSTRAINT check_charge_amount CHECK (amount > 0),
    billing_period VARCHAR(7) NOT NULL, -- e.g., '2026-08'
    due_date DATE NOT NULL,
    billing_basis_snapshot JSONB NOT NULL, -- Snapshot of calculation variables (size, formula, rate)
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    CONSTRAINT check_charge_fk_discriminator CHECK (
        (billing_subject_type = 'property' AND property_id IS NOT NULL AND unit_id IS NULL AND family_id IS NULL AND custom_subject_id IS NULL) OR
        (billing_subject_type = 'unit' AND property_id IS NULL AND unit_id IS NOT NULL AND family_id IS NULL AND custom_subject_id IS NULL) OR
        (billing_subject_type = 'family' AND property_id IS NULL AND unit_id IS NULL AND family_id IS NOT NULL AND custom_subject_id IS NULL) OR
        (billing_subject_type = 'custom' AND property_id IS NULL AND unit_id IS NULL AND family_id IS NULL AND custom_subject_id IS NOT NULL)
    )
);

-- Idempotency constraints on charge generation:
-- 1. Enforce max one property maintenance charge per period
CREATE UNIQUE INDEX IF NOT EXISTS unique_property_maintenance_charge 
    ON public.maintenance_charges (property_id, billing_period) 
    WHERE (billing_subject_type = 'property');

-- 2. Enforce max one custom subject charge per property per period
CREATE UNIQUE INDEX IF NOT EXISTS unique_custom_maintenance_charge 
    ON public.maintenance_charges (property_id, custom_subject_id, billing_period) 
    WHERE (billing_subject_type = 'custom');


-- Ledger Transactions Table (Financial Ledger - Two Append-Only Sub-ledgers)
CREATE TABLE IF NOT EXISTS public.ledger_transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    property_id UUID REFERENCES public.properties(id) ON DELETE RESTRICT,
    user_id UUID REFERENCES public.users(id) ON DELETE RESTRICT,
    billing_subject_type VARCHAR(30) NOT NULL DEFAULT 'none'
        CONSTRAINT check_ledger_subject_type CHECK (billing_subject_type IN ('none', 'property', 'unit', 'family', 'custom')),
    billing_property_id UUID REFERENCES public.properties(id) ON DELETE RESTRICT,
    billing_unit_id UUID REFERENCES public.units(id) ON DELETE RESTRICT,
    billing_family_id UUID REFERENCES public.family_groups(id) ON DELETE RESTRICT,
    billing_custom_subject_id UUID REFERENCES public.custom_billing_subjects(id) ON DELETE RESTRICT,
    scope VARCHAR(20) NOT NULL
        CONSTRAINT check_ledger_scope CHECK (scope IN ('member', 'society')),
    direction VARCHAR(20) NOT NULL
        CONSTRAINT check_ledger_direction CHECK (direction IN ('debit', 'credit')),
    amount NUMERIC(15, 2) NOT NULL CONSTRAINT check_ledger_amount CHECK (amount > 0), -- Positive amount only
    transaction_type VARCHAR(50) NOT NULL
        CONSTRAINT check_transaction_type CHECK (transaction_type IN ('charge', 'penalty', 'adjustment', 'waiver', 'payment', 'advance_payment', 'refund', 'reversal', 'expense', 'income')),
    transaction_date DATE NOT NULL DEFAULT CURRENT_DATE,
    description TEXT,
    reference_id UUID, -- References table that triggered transaction (like opening_balances or maintenance_charges or payments)
    created_by UUID REFERENCES public.users(id) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    
    CONSTRAINT check_ledger_fk_discriminator CHECK (
        (billing_subject_type = 'none' AND billing_property_id IS NULL AND billing_unit_id IS NULL AND billing_family_id IS NULL AND billing_custom_subject_id IS NULL) OR
        (billing_subject_type = 'property' AND billing_property_id IS NOT NULL AND billing_unit_id IS NULL AND billing_family_id IS NULL AND billing_custom_subject_id IS NULL) OR
        (billing_subject_type = 'unit' AND billing_property_id IS NULL AND billing_unit_id IS NOT NULL AND billing_family_id IS NULL AND billing_custom_subject_id IS NULL) OR
        (billing_subject_type = 'family' AND billing_property_id IS NULL AND billing_unit_id IS NULL AND billing_family_id IS NOT NULL AND billing_custom_subject_id IS NULL) OR
        (billing_subject_type = 'custom' AND billing_property_id IS NULL AND billing_unit_id IS NULL AND billing_family_id IS NULL AND billing_custom_subject_id IS NOT NULL)
    ),
    
    CONSTRAINT check_ledger_scope_requirements CHECK (
        (scope = 'member' AND property_id IS NOT NULL AND user_id IS NOT NULL) OR
        (scope = 'society')
    )
);

-- Opening Balances Table
CREATE TABLE IF NOT EXISTS public.opening_balances (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    property_id UUID NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    amount NUMERIC(15, 2) NOT NULL CONSTRAINT check_opening_amount CHECK (amount >= 0),
    direction VARCHAR(20) NOT NULL CONSTRAINT check_opening_direction CHECK (direction IN ('debit', 'credit')),
    as_of_date DATE NOT NULL,
    created_by UUID REFERENCES public.users(id) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    CONSTRAINT unique_property_opening UNIQUE (property_id, user_id, as_of_date)
);

-- =========================================================================
-- 3. PHASE 2B TABLES (PAYMENT ARCHITECTURE)
-- =========================================================================

-- Payments Table (Submitted by members, verified by admins, supports all v2.1 billing subject types)
CREATE TABLE IF NOT EXISTS public.payments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    property_id UUID NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT, -- Payer
    amount NUMERIC(15, 2) NOT NULL CONSTRAINT check_payment_amount CHECK (amount > 0),
    payment_method VARCHAR(30) NOT NULL
        CONSTRAINT check_payment_method CHECK (payment_method IN ('upi', 'bank_transfer', 'cash', 'cheque', 'other')),
    reference_number VARCHAR(100) NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'pending_verification'
        CONSTRAINT check_payment_status CHECK (status IN ('pending_verification', 'verified', 'rejected', 'reversed')),
    billing_subject_type VARCHAR(30) NOT NULL DEFAULT 'property'
        CONSTRAINT check_payment_subject_type CHECK (billing_subject_type IN ('property', 'unit', 'family', 'custom')),
    billing_property_id UUID REFERENCES public.properties(id) ON DELETE RESTRICT,
    billing_unit_id UUID REFERENCES public.units(id) ON DELETE RESTRICT,
    billing_family_id UUID REFERENCES public.family_groups(id) ON DELETE RESTRICT,
    billing_custom_subject_id UUID REFERENCES public.custom_billing_subjects(id) ON DELETE RESTRICT,
    verification_reason TEXT,
    posted_at TIMESTAMP WITH TIME ZONE,
    verified_by UUID REFERENCES public.users(id),
    created_by UUID REFERENCES public.users(id) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    CONSTRAINT check_payment_fk_discriminator CHECK (
        (billing_subject_type = 'property' AND billing_property_id IS NOT NULL AND billing_unit_id IS NULL AND billing_family_id IS NULL AND billing_custom_subject_id IS NULL) OR
        (billing_subject_type = 'unit' AND billing_property_id IS NULL AND billing_unit_id IS NOT NULL AND billing_family_id IS NULL AND billing_custom_subject_id IS NULL) OR
        (billing_subject_type = 'family' AND billing_property_id IS NULL AND billing_unit_id IS NULL AND billing_family_id IS NOT NULL AND billing_custom_subject_id IS NULL) OR
        (billing_subject_type = 'custom' AND billing_property_id IS NULL AND billing_unit_id IS NULL AND billing_family_id IS NULL AND billing_custom_subject_id IS NOT NULL)
    )
);

-- Active reference uniqueness index per society
CREATE UNIQUE INDEX IF NOT EXISTS uq_payment_reference_active
    ON public.payments (society_id, payment_method, reference_number)
    WHERE status IN ('pending_verification', 'verified');


-- Payment Allocations Table
CREATE TABLE IF NOT EXISTS public.payment_allocations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    payment_id UUID NOT NULL REFERENCES public.payments(id) ON DELETE CASCADE,
    charge_id UUID NOT NULL REFERENCES public.maintenance_charges(id) ON DELETE RESTRICT,
    amount NUMERIC(15, 2) NOT NULL CONSTRAINT check_allocation_amount CHECK (amount > 0),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    CONSTRAINT unique_payment_charge_allocation UNIQUE (payment_id, charge_id)
);

-- Receipts Table
CREATE TABLE IF NOT EXISTS public.receipts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    payment_id UUID NOT NULL UNIQUE REFERENCES public.payments(id) ON DELETE RESTRICT,
    receipt_number VARCHAR(50) NOT NULL UNIQUE,
    generated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    details JSONB NOT NULL
);

-- Notifications Table (v2.1 Schema Compliance)
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE,
    recipient_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    type VARCHAR(50) NOT NULL, -- e.g., 'payment_status', 'billing_run'
    title VARCHAR(150) NOT NULL,
    body TEXT NOT NULL,
    related_entity_type VARCHAR(50),
    related_entity_id UUID,
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    read_at TIMESTAMP WITH TIME ZONE
);

-- =========================================================================
-- 4. TRIGGERS & INTEGRITY CHECKS (PHASE 2A & 2B)
-- =========================================================================

-- Trigger function: validate_ledger_direction_invariants
CREATE OR REPLACE FUNCTION public.validate_ledger_direction_invariants()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.scope = 'member' THEN
        IF NEW.transaction_type = 'charge' AND NEW.direction <> 'debit' THEN
            RAISE EXCEPTION 'MEMBER Charge must be a debit (dues-increasing).';
        ELSIF NEW.transaction_type = 'penalty' AND NEW.direction <> 'debit' THEN
            RAISE EXCEPTION 'MEMBER Penalty must be a debit (dues-increasing).';
        ELSIF NEW.transaction_type = 'waiver' AND NEW.direction <> 'credit' THEN
            RAISE EXCEPTION 'MEMBER Waiver must be a credit (dues-decreasing).';
        ELSIF NEW.transaction_type = 'payment' AND NEW.direction <> 'credit' THEN
            RAISE EXCEPTION 'MEMBER Payment must be a credit (dues-decreasing).';
        ELSIF NEW.transaction_type = 'advance_payment' AND NEW.direction <> 'credit' THEN
            RAISE EXCEPTION 'MEMBER Advance payment must be a credit (dues-decreasing).';
        ELSIF NEW.transaction_type = 'refund' AND NEW.direction <> 'debit' THEN
            RAISE EXCEPTION 'MEMBER Refund must be a debit (dues-increasing).';
        END IF;
    ELSIF NEW.scope = 'society' THEN
        IF NEW.transaction_type = 'payment' AND NEW.direction <> 'debit' THEN
            RAISE EXCEPTION 'SOCIETY Member receipt must be a debit (cash-increasing).';
        ELSIF NEW.transaction_type = 'income' AND NEW.direction <> 'debit' THEN
            RAISE EXCEPTION 'SOCIETY Income must be a debit (cash-increasing).';
        ELSIF NEW.transaction_type = 'expense' AND NEW.direction <> 'credit' THEN
            RAISE EXCEPTION 'SOCIETY Expense must be a credit (cash-decreasing).';
        ELSIF NEW.transaction_type = 'refund' AND NEW.direction <> 'credit' THEN
            RAISE EXCEPTION 'SOCIETY Refund paid must be a credit (cash-decreasing).';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trigger_validate_ledger_direction_invariants
BEFORE INSERT ON public.ledger_transactions
FOR EACH ROW EXECUTE FUNCTION public.validate_ledger_direction_invariants();


-- Trigger function: prevent_ledger_mutations (Immutable Ledger)
CREATE OR REPLACE FUNCTION public.prevent_ledger_mutations()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF (OLD.id IS DISTINCT FROM NEW.id OR
            OLD.society_id IS DISTINCT FROM NEW.society_id OR
            OLD.property_id IS DISTINCT FROM NEW.property_id OR
            OLD.user_id IS DISTINCT FROM NEW.user_id OR
            OLD.billing_subject_type IS DISTINCT FROM NEW.billing_subject_type OR
            OLD.billing_property_id IS DISTINCT FROM NEW.billing_property_id OR
            OLD.billing_unit_id IS DISTINCT FROM NEW.billing_unit_id OR
            OLD.billing_family_id IS DISTINCT FROM NEW.billing_family_id OR
            OLD.billing_custom_subject_id IS DISTINCT FROM NEW.billing_custom_subject_id OR
            OLD.scope IS DISTINCT FROM NEW.scope OR
            OLD.direction IS DISTINCT FROM NEW.direction OR
            OLD.amount IS DISTINCT FROM NEW.amount OR
            OLD.transaction_type IS DISTINCT FROM NEW.transaction_type OR
            OLD.transaction_date IS DISTINCT FROM NEW.transaction_date OR
            OLD.reference_id IS DISTINCT FROM NEW.reference_id OR
            OLD.created_by IS DISTINCT FROM NEW.created_by OR
            OLD.created_at IS DISTINCT FROM NEW.created_at) THEN
            RAISE EXCEPTION 'Financial ledger transactions are immutable. Core accounting fields (amount, direction, scope, transaction_type, reference_id, etc.) cannot be modified.';
        END IF;
        RETURN NEW;
    END IF;
    RAISE EXCEPTION 'Financial ledger transactions are immutable. Modifications (UPDATE/DELETE) are blocked.';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trigger_prevent_ledger_mutations
BEFORE UPDATE OR DELETE ON public.ledger_transactions
FOR EACH ROW EXECUTE FUNCTION public.prevent_ledger_mutations();


-- Trigger function: prevent_opening_balance_mutations (Immutable Balance Setup)
CREATE OR REPLACE FUNCTION public.prevent_opening_balance_mutations()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'Opening balances are immutable. Corrections must be booked as compensating ledger adjustments.';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trigger_prevent_opening_balance_mutations
BEFORE UPDATE OR DELETE ON public.opening_balances
FOR EACH ROW EXECUTE FUNCTION public.prevent_opening_balance_mutations();


-- Trigger function: book_opening_balance_in_ledger
CREATE OR REPLACE FUNCTION public.book_opening_balance_in_ledger()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.amount > 0 THEN
        INSERT INTO public.ledger_transactions (
            society_id,
            property_id,
            user_id,
            billing_subject_type,
            scope,
            direction,
            amount,
            transaction_type,
            transaction_date,
            description,
            reference_id,
            created_by
        ) VALUES (
            '11111111-1111-1111-1111-111111111111'::uuid, -- MVP Society ID
            NEW.property_id,
            NEW.user_id,
            'none',
            'member',
            NEW.direction,
            NEW.amount,
            'adjustment',
            NEW.as_of_date,
            'Opening balance adjustment booked as of ' || NEW.as_of_date,
            NEW.id,
            NEW.created_by
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trigger_book_opening_balance_in_ledger
AFTER INSERT ON public.opening_balances
FOR EACH ROW EXECUTE FUNCTION public.book_opening_balance_in_ledger();


-- Trigger function: validate_payment_state_transitions
CREATE OR REPLACE FUNCTION public.validate_payment_state_transitions()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'Payments are immutable database records. Deletion is blocked.';
    END IF;

    IF OLD.status <> 'pending_verification' THEN
        IF NEW.amount <> OLD.amount OR 
           NEW.payment_method <> OLD.payment_method OR 
           NEW.reference_number <> OLD.reference_number OR
           NEW.user_id <> OLD.user_id OR
           NEW.property_id <> OLD.property_id OR
           NEW.society_id <> OLD.society_id 
        THEN
            RAISE EXCEPTION 'Cannot edit core payment attributes once payment is processed.';
        END IF;
    END IF;

    IF OLD.status = 'pending_verification' AND NEW.status NOT IN ('verified', 'rejected', 'pending_verification') THEN
        RAISE EXCEPTION 'Invalid transition: pending payment can only transition to verified or rejected.';
    END IF;

    IF OLD.status = 'verified' AND NEW.status <> 'reversed' AND NEW.status <> 'verified' THEN
        RAISE EXCEPTION 'Invalid transition: verified payment can only transition to reversed.';
    END IF;

    IF OLD.status = 'rejected' AND NEW.status <> 'rejected' THEN
        RAISE EXCEPTION 'Invalid transition: rejected payments are terminal and cannot be changed.';
    END IF;

    IF OLD.status = 'reversed' AND NEW.status <> 'reversed' THEN
        RAISE EXCEPTION 'Invalid transition: reversed payments are terminal.';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trigger_validate_payment_state_transitions
BEFORE UPDATE ON public.payments
FOR EACH ROW EXECUTE FUNCTION public.validate_payment_state_transitions();

CREATE OR REPLACE TRIGGER trigger_prevent_payment_deletes
BEFORE DELETE ON public.payments
FOR EACH ROW EXECUTE FUNCTION public.validate_payment_state_transitions();


-- Trigger function: prevent_receipt_mutations
CREATE OR REPLACE FUNCTION public.prevent_receipt_mutations()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'Receipts are immutable financial documents. Modifications (UPDATE/DELETE) are blocked.';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trigger_prevent_receipt_mutations
BEFORE UPDATE OR DELETE ON public.receipts
FOR EACH ROW EXECUTE FUNCTION public.prevent_receipt_mutations();


-- Trigger function: prevent_verified_allocation_mutations
CREATE OR REPLACE FUNCTION public.prevent_verified_allocation_mutations()
RETURNS TRIGGER AS $$
DECLARE
    pay_status VARCHAR(30);
BEGIN
    SELECT status INTO pay_status 
    FROM public.payments 
    WHERE id = COALESCE(NEW.payment_id, OLD.payment_id);
    
    IF pay_status <> 'pending_verification' THEN
        RAISE EXCEPTION 'Cannot modify or delete payment allocations once the payment is processed.';
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trigger_prevent_verified_allocation_mutations
BEFORE UPDATE OR DELETE ON public.payment_allocations
FOR EACH ROW EXECUTE FUNCTION public.prevent_verified_allocation_mutations();


-- =========================================================================
-- 5. SECURITY DEFINER FUNCTIONS (VERIFY, REJECT, REVERSE)
-- =========================================================================

-- _internal_settle_payment (Shared financial core for Admin and Webhook payment verification)
CREATE OR REPLACE FUNCTION public._internal_settle_payment(
    payment_uuid UUID,
    allocations JSONB,
    authorized_caller_uuid UUID
)
RETURNS UUID AS $
DECLARE
    pay_row RECORD;
    alloc_sum NUMERIC(15, 2) := 0;
    charge_row RECORD;
    outstanding NUMERIC(15, 2);
    already_allocated NUMERIC(15, 2);
    advance_amt NUMERIC(15, 2);
    new_receipt_id UUID;
    rec_num VARCHAR(50);
    alloc_item RECORD;
BEGIN
    -- 1. Lock payment row to prevent concurrent postings
    SELECT * INTO pay_row
    FROM public.payments
    WHERE id = payment_uuid
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Payment record not found.';
    END IF;

    -- 2. Confirm pending_verification
    IF pay_row.status <> 'pending_verification' THEN
        RAISE EXCEPTION 'Payment status must be pending_verification.';
    END IF;

    -- 3. Validate payment has authorized relationship (belongs to plot/payer)
    IF NOT EXISTS (
        SELECT 1 FROM public.property_owners po
        WHERE po.property_id = pay_row.property_id 
          AND po.owner_id = pay_row.user_id 
          AND po.end_date IS NULL
    ) AND NOT EXISTS (
        SELECT 1 FROM public.tenancies t
        JOIN public.units u ON t.unit_id = u.id
        WHERE u.property_id = pay_row.property_id 
          AND t.tenant_id = pay_row.user_id 
          AND t.is_active = TRUE
    ) THEN
        RAISE EXCEPTION 'Invalid relationship: Payer has no active ownership or tenancy connection on this property.';
    END IF;

    -- 4. Loop to validate allocation boundaries
    FOR alloc_item IN SELECT * FROM jsonb_to_recordset(allocations) AS x(charge_id UUID, amount NUMERIC) LOOP
        IF alloc_item.amount <= 0 THEN
            RAISE EXCEPTION 'Allocation amount must be greater than zero.';
        END IF;
        alloc_sum := alloc_sum + alloc_item.amount;

        -- Fetch charge details
        SELECT * INTO charge_row FROM public.maintenance_charges WHERE id = alloc_item.charge_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Charge record not found.';
        END IF;

        -- Confirm target shares the same society ID
        IF charge_row.society_id <> pay_row.society_id THEN
            RAISE EXCEPTION 'Society mismatch: Payment and charge must share the same society.';
        END IF;

        -- Confirm charge belongs to target property
        IF charge_row.property_id <> pay_row.property_id THEN
            RAISE EXCEPTION 'Property mismatch: Charge belongs to a different property.';
        END IF;

        -- Check allocations boundaries
        SELECT COALESCE(SUM(pa.amount), 0) INTO already_allocated
        FROM public.payment_allocations pa
        JOIN public.payments p ON pa.payment_id = p.id
        WHERE pa.charge_id = alloc_item.charge_id AND p.status = 'verified';

        outstanding := charge_row.amount - already_allocated;
        IF alloc_item.amount > outstanding THEN
            RAISE EXCEPTION 'Allocation exceeds outstanding charge balance. Outstanding: %', outstanding;
        END IF;
    END LOOP;

    -- Verify allocation total limit
    IF alloc_sum > pay_row.amount THEN
        RAISE EXCEPTION 'Sum of allocations (%) exceeds payment amount (%).', alloc_sum, pay_row.amount;
    END IF;

    -- 5. Insert allocations & post credits in member subsidiary ledger
    FOR alloc_item IN SELECT * FROM jsonb_to_recordset(allocations) AS x(charge_id UUID, amount NUMERIC) LOOP
        INSERT INTO public.payment_allocations (
            payment_id,
            charge_id,
            amount
        ) VALUES (
            payment_uuid,
            alloc_item.charge_id,
            alloc_item.amount
        );

        INSERT INTO public.ledger_transactions (
            society_id,
            property_id,
            user_id,
            billing_subject_type,
            billing_property_id,
            scope,
            direction,
            amount,
            transaction_type,
            description,
            reference_id,
            created_by
        ) VALUES (
            pay_row.society_id,
            pay_row.property_id,
            pay_row.user_id,
            'property',
            pay_row.property_id,
            'member',
            'credit',
            alloc_item.amount,
            'payment',
            'Verified payment allocation against charge ' || alloc_item.charge_id,
            payment_uuid, -- Deterministic reference
            authorized_caller_uuid
        );
    END LOOP;

    -- 6. Advance payment handling
    advance_amt := pay_row.amount - alloc_sum;
    IF advance_amt > 0 THEN
        INSERT INTO public.ledger_transactions (
            society_id,
            property_id,
            user_id,
            billing_subject_type,
            billing_property_id,
            scope,
            direction,
            amount,
            transaction_type,
            description,
            reference_id,
            created_by
        ) VALUES (
            pay_row.society_id,
            pay_row.property_id,
            pay_row.user_id,
            'property',
            pay_row.property_id,
            'member',
            'credit',
            advance_amt,
            'advance_payment',
            'Unallocated payment portion credited as advance',
            payment_uuid, -- Deterministic reference
            authorized_caller_uuid
        );
    END IF;

    -- 7. Book society cash/bank ledger receipt
    INSERT INTO public.ledger_transactions (
        society_id,
        property_id,
        user_id,
        billing_subject_type,
        scope,
        direction,
        amount,
        transaction_type,
        description,
        reference_id,
        created_by
    ) VALUES (
        pay_row.society_id,
        NULL,
        NULL,
        'none',
        'society',
        'debit',
        pay_row.amount,
        'payment',
        'Member payment receipt ref: ' || pay_row.reference_number,
        payment_uuid, -- Deterministic reference
        authorized_caller_uuid
    );

    -- 8. Generate receipt document
    rec_num := public.generate_receipt_number();
    
    INSERT INTO public.receipts (
        society_id,
        payment_id,
        receipt_number,
        details
    ) VALUES (
        pay_row.society_id,
        payment_uuid,
        rec_num,
        jsonb_build_object(
            'payment_id', pay_row.id,
            'amount', pay_row.amount,
            'reference_number', pay_row.reference_number,
            'payment_date', pay_row.payment_date,
            'allocations', allocations,
            'advance_credited', advance_amt
        )
    ) RETURNING id INTO new_receipt_id;

    -- 9. Transition status & timestamps on payments row
    UPDATE public.payments
    SET status = 'verified',
        posted_at = NOW(),
        verified_by = authorized_caller_uuid
    WHERE id = payment_uuid;

    -- 10. Dispatch notifications (recipient-scoped)
    INSERT INTO public.notifications (
        society_id,
        recipient_user_id,
        type,
        title,
        body,
        related_entity_type,
        related_entity_id
    ) VALUES (
        pay_row.society_id,
        pay_row.user_id,
        'payment_status',
        'Payment Verified successfully',
        'Your payment of ₹' || pay_row.amount || ' (ref: ' || pay_row.reference_number || ') has been verified. Receipt number is ' || rec_num,
        'payments',
        payment_uuid
    );

    -- 11. Write audit log
    INSERT INTO public.audit_logs (
        user_id,
        action,
        table_name,
        record_id,
        old_value,
        new_value
    ) VALUES (
        authorized_caller_uuid,
        'VERIFIED payment',
        'payments',
        payment_uuid,
        jsonb_build_object('status', 'pending_verification'),
        jsonb_build_object('status', 'verified', 'receipt_number', rec_num)
    );

    RETURN new_receipt_id;
END;
$ LANGUAGE plpgsql;

-- Prevent public access to internal helper
REVOKE EXECUTE ON FUNCTION public._internal_settle_payment(UUID, JSONB, UUID) FROM PUBLIC;

-- verify_payment (Exactly-Once verification with sequence control and locks)
CREATE OR REPLACE FUNCTION public.verify_payment(
    payment_uuid UUID,
    allocations JSONB
)
RETURNS UUID AS $
DECLARE
    caller_uuid UUID := COALESCE(auth.uid(), 'a0000000-0000-0000-0000-000000000000');
    receipt_id UUID;
BEGIN
    -- 1. Validate caller authorization inside PostgreSQL
    IF NOT (public.is_admin(caller_uuid) AND EXISTS (
        SELECT 1 FROM public.users WHERE id = caller_uuid AND status = 'active'
    )) THEN
        RAISE EXCEPTION 'Unauthorized: Caller must be an active administrator.';
    END IF;

    -- 2. Call internal settlement helper
    receipt_id := public._internal_settle_payment(payment_uuid, allocations, caller_uuid);

    RETURN receipt_id;
END;
$ LANGUAGE plpgsql;


-- reject_payment (Converts pending to rejected state, books no transactions/receipts)
CREATE OR REPLACE FUNCTION public.reject_payment(
    payment_uuid UUID,
    reason TEXT
)
RETURNS BOOLEAN AS $$
DECLARE
    caller_uuid UUID := COALESCE(auth.uid(), 'a0000000-0000-0000-0000-000000000000');
    pay_row RECORD;
BEGIN
    SELECT * INTO pay_row
    FROM public.payments
    WHERE id = payment_uuid
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Payment record not found.';
    END IF;

    IF pay_row.status <> 'pending_verification' THEN
        RAISE EXCEPTION 'Payment must be pending_verification to reject.';
    END IF;

    IF NOT (public.is_admin(caller_uuid) AND EXISTS (
        SELECT 1 FROM public.users WHERE id = caller_uuid AND status = 'active'
    )) THEN
        RAISE EXCEPTION 'Unauthorized: Caller must be an active administrator.';
    END IF;

    UPDATE public.payments
    SET status = 'rejected',
        verification_reason = reason
    WHERE id = payment_uuid;

    INSERT INTO public.notifications (
        society_id,
        recipient_user_id,
        type,
        title,
        body,
        related_entity_type,
        related_entity_id
    ) VALUES (
        pay_row.society_id,
        pay_row.user_id,
        'payment_status',
        'Payment Slip Rejected',
        'Your payment of ₹' || pay_row.amount || ' (ref: ' || pay_row.reference_number || ') has been rejected. Reason: ' || reason,
        'payments',
        payment_uuid
    );

    INSERT INTO public.audit_logs (
        user_id,
        action,
        table_name,
        record_id,
        old_value,
        new_value
    ) VALUES (
        caller_uuid,
        'REJECTED payment',
        'payments',
        payment_uuid,
        jsonb_build_object('status', 'pending_verification'),
        jsonb_build_object('status', 'rejected', 'reason', reason)
    );

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;


-- reverse_payment (Reverses verified payment and triggers matching ledger corrections)
CREATE OR REPLACE FUNCTION public.reverse_payment(
    payment_uuid UUID,
    reason TEXT
)
RETURNS BOOLEAN AS $$
DECLARE
    caller_uuid UUID := COALESCE(auth.uid(), 'a0000000-0000-0000-0000-000000000000');
    pay_row RECORD;
    tx RECORD;
BEGIN
    SELECT * INTO pay_row
    FROM public.payments
    WHERE id = payment_uuid
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Payment record not found.';
    END IF;

    IF pay_row.status <> 'verified' THEN
        RAISE EXCEPTION 'Only verified payments can be reversed.';
    END IF;

    IF NOT (public.is_admin(caller_uuid) AND EXISTS (
        SELECT 1 FROM public.users WHERE id = caller_uuid AND status = 'active'
    )) THEN
        RAISE EXCEPTION 'Unauthorized: Caller must be an active administrator.';
    END IF;

    UPDATE public.payments
    SET status = 'reversed',
        verification_reason = reason
    WHERE id = payment_uuid;

    -- Reverse ledger transactions sharing reference_id = payment_uuid
    FOR tx IN 
        SELECT id FROM public.ledger_transactions 
        WHERE reference_id = payment_uuid
    LOOP
        PERFORM public.reverse_ledger_transaction(tx.id, 'Payment reversal: ' || reason, caller_uuid);
    END LOOP;

    INSERT INTO public.notifications (
        society_id,
        recipient_user_id,
        type,
        title,
        body,
        related_entity_type,
        related_entity_id
    ) VALUES (
        pay_row.society_id,
        pay_row.user_id,
        'payment_status',
        'Payment Reversal Posted',
        'Your verified payment of ₹' || pay_row.amount || ' (ref: ' || pay_row.reference_number || ') has been reversed by administration. Reason: ' || reason,
        'payments',
        payment_uuid
    );

    INSERT INTO public.audit_logs (
        user_id,
        action,
        table_name,
        record_id,
        old_value,
        new_value
    ) VALUES (
        caller_uuid,
        'REVERSED payment',
        'payments',
        payment_uuid,
        jsonb_build_object('status', 'verified'),
        jsonb_build_object('status', 'reversed', 'reason', reason)
    );

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- =========================================================================
-- 6. ROW LEVEL SECURITY (RLS) POLICIES
-- =========================================================================

-- Enable RLS
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_allocations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- payments policies (Privacy Class B: Individual private financial)
CREATE POLICY "View payments" ON public.payments FOR SELECT 
    USING (
        public.is_admin(auth.uid()) OR 
        user_id = auth.uid() OR
        EXISTS (
            SELECT 1 FROM public.property_owners po
            WHERE po.property_id = payments.property_id 
              AND po.owner_id = auth.uid() 
              AND po.start_date <= payments.payment_date
              AND (po.end_date IS NULL OR po.end_date >= payments.payment_date)
        )
    );

CREATE POLICY "Insert payments" ON public.payments FOR INSERT 
    WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "Admin manage payments" ON public.payments FOR ALL 
    USING (public.is_admin(auth.uid()));


-- payment_allocations policies (Privacy Class B)
CREATE POLICY "View allocations" ON public.payment_allocations FOR SELECT 
    USING (
        public.is_admin(auth.uid()) OR 
        EXISTS (
            SELECT 1 FROM public.payments p
            WHERE p.id = payment_allocations.payment_id 
              AND (p.user_id = auth.uid() OR EXISTS (
                  SELECT 1 FROM public.property_owners po
                  WHERE po.property_id = p.property_id 
                    AND po.owner_id = auth.uid()
                    AND po.end_date IS NULL
              ))
        )
    );

CREATE POLICY "Admin manage allocations" ON public.payment_allocations FOR ALL 
    USING (public.is_admin(auth.uid()));


-- receipts policies (Privacy Class B)
CREATE POLICY "View receipts" ON public.receipts FOR SELECT 
    USING (
        public.is_admin(auth.uid()) OR 
        EXISTS (
            SELECT 1 FROM public.payments p
            WHERE p.id = receipts.payment_id 
              AND (p.user_id = auth.uid() OR EXISTS (
                  SELECT 1 FROM public.property_owners po
                  WHERE po.property_id = p.property_id 
                    AND po.owner_id = auth.uid()
                    AND po.end_date IS NULL
              ))
        )
    );

CREATE POLICY "Admin manage receipts" ON public.receipts FOR ALL 
    USING (public.is_admin(auth.uid()));


-- notifications policies (Privacy Class C: Private personal information)
CREATE POLICY "View own notifications" ON public.notifications FOR SELECT 
    USING (recipient_user_id = auth.uid());

CREATE POLICY "Update own notifications" ON public.notifications FOR UPDATE 
    USING (recipient_user_id = auth.uid());

CREATE POLICY "Admin manage notifications" ON public.notifications FOR ALL 
    USING (public.is_admin(auth.uid()));


-- =========================================================================
-- 7. PHASE 2C TABLES & STRUCTURES
-- =========================================================================

-- Expense Categories Table
CREATE TABLE IF NOT EXISTS public.expense_categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    CONSTRAINT unique_society_category_name UNIQUE (society_id, name)
);

-- Expense Vouchers Table
CREATE TABLE IF NOT EXISTS public.expense_vouchers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE,
    category_id UUID NOT NULL REFERENCES public.expense_categories(id) ON DELETE RESTRICT,
    amount NUMERIC(15, 2) NOT NULL CONSTRAINT check_expense_amount CHECK (amount > 0),
    vendor_name VARCHAR(150) NOT NULL,
    invoice_number VARCHAR(100),
    invoice_date DATE NOT NULL,
    payment_method VARCHAR(30) NOT NULL CONSTRAINT check_expense_payment_method CHECK (payment_method IN ('upi', 'bank_transfer', 'cash', 'cheque')),
    reference_number VARCHAR(100),
    status VARCHAR(30) NOT NULL DEFAULT 'pending_approval' CONSTRAINT check_voucher_status CHECK (status IN ('pending_approval', 'approved', 'posted', 'rejected', 'reversed')),
    description TEXT,
    attachment_url TEXT,
    approved_by UUID REFERENCES public.users(id),
    approved_at TIMESTAMP WITH TIME ZONE,
    created_by UUID REFERENCES public.users(id) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

-- Budgets Table
CREATE TABLE IF NOT EXISTS public.budgets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE,
    category_id UUID NOT NULL REFERENCES public.expense_categories(id) ON DELETE CASCADE,
    allocated_amount NUMERIC(15, 2) NOT NULL CONSTRAINT check_budget_amount CHECK (allocated_amount >= 0),
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    created_by UUID REFERENCES public.users(id) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    CONSTRAINT check_budget_dates CHECK (start_date <= end_date)
);

-- Bank Reconciliations Table
CREATE TABLE IF NOT EXISTS public.bank_reconciliations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE,
    bank_statement_date DATE NOT NULL,
    opening_balance NUMERIC(15, 2) NOT NULL,
    closing_balance NUMERIC(15, 2) NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'draft' CONSTRAINT check_reconciliation_status CHECK (status IN ('draft', 'completed')),
    reconciled_by UUID REFERENCES public.users(id),
    reconciled_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

-- Extend ledger_transactions to support reconciliation
ALTER TABLE public.ledger_transactions 
ADD COLUMN IF NOT EXISTS bank_reconciliation_id UUID REFERENCES public.bank_reconciliations(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS reconciled_at TIMESTAMP WITH TIME ZONE DEFAULT NULL;

-- Safe indices for isolation and quick joins
CREATE INDEX IF NOT EXISTS idx_expense_vouchers_society ON public.expense_vouchers (society_id);
CREATE INDEX IF NOT EXISTS idx_budgets_society_category ON public.budgets (society_id, category_id);
CREATE INDEX IF NOT EXISTS idx_reconciliations_society ON public.bank_reconciliations (society_id);


-- =========================================================================
-- 8. PHASE 2C TRIGGERS & MUTATION CHECKS
-- =========================================================================

-- Budget period overlap check trigger
CREATE OR REPLACE FUNCTION public.validate_budget_overlap()
RETURNS TRIGGER AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM public.budgets 
        WHERE society_id = NEW.society_id
          AND category_id = NEW.category_id
          AND id <> COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
          AND NEW.start_date <= end_date
          AND NEW.end_date >= start_date
    ) THEN
        RAISE EXCEPTION 'Overlapping budget period detected for this category.';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_validate_budget_overlap
    BEFORE INSERT OR UPDATE ON public.budgets
    FOR EACH ROW EXECUTE FUNCTION public.validate_budget_overlap();


-- Expense Voucher state mutation logic
CREATE OR REPLACE FUNCTION public.validate_expense_voucher_mutations()
RETURNS TRIGGER AS $$
BEGIN
    -- Block Delete
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'Expense vouchers cannot be deleted.';
    END IF;

    -- Block update on financial fields if not pending_approval
    IF OLD.status <> 'pending_approval' THEN
        IF OLD.amount <> NEW.amount OR
           OLD.category_id <> NEW.category_id OR
           OLD.vendor_name <> NEW.vendor_name OR
           OLD.invoice_number <> NEW.invoice_number OR
           OLD.invoice_date <> NEW.invoice_date OR
           OLD.payment_method <> NEW.payment_method OR
           OLD.reference_number <> NEW.reference_number OR
           OLD.society_id <> NEW.society_id THEN
            RAISE EXCEPTION 'Approved, posted, or rejected expense vouchers are immutable.';
        END IF;
    END IF;

    -- State machine checks
    IF OLD.status = 'pending_approval' AND NEW.status NOT IN ('pending_approval', 'approved', 'rejected') THEN
        RAISE EXCEPTION 'Invalid voucher state transition from pending_approval to %', NEW.status;
    END IF;

    IF OLD.status = 'approved' AND NEW.status NOT IN ('approved', 'posted', 'rejected') THEN
        RAISE EXCEPTION 'Invalid voucher state transition from approved to %', NEW.status;
    END IF;

    IF OLD.status = 'posted' AND NEW.status NOT IN ('posted', 'reversed') THEN
        RAISE EXCEPTION 'Invalid voucher state transition from posted to %', NEW.status;
    END IF;

    IF OLD.status = 'rejected' AND NEW.status <> 'rejected' THEN
        RAISE EXCEPTION 'Rejected vouchers are final and cannot be transitioned.';
    END IF;

    IF OLD.status = 'reversed' AND NEW.status <> 'reversed' THEN
        RAISE EXCEPTION 'Reversed vouchers are final and cannot be transitioned.';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_validate_expense_voucher_mutations
    BEFORE UPDATE OR DELETE ON public.expense_vouchers
    FOR EACH ROW EXECUTE FUNCTION public.validate_expense_voucher_mutations();


-- Bank reconciliation lock trigger
CREATE OR REPLACE FUNCTION public.prevent_completed_reconciliation_changes()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.status = 'completed' THEN
            RAISE EXCEPTION 'Completed bank reconciliations cannot be deleted.';
        END IF;
    END IF;

    IF OLD.status = 'completed' THEN
        IF NEW.opening_balance <> OLD.opening_balance OR
           NEW.closing_balance <> OLD.closing_balance OR
           NEW.bank_statement_date <> OLD.bank_statement_date OR
           NEW.society_id <> OLD.society_id OR
           NEW.status <> OLD.status OR
           NEW.reconciled_by <> OLD.reconciled_by OR
           NEW.reconciled_at <> OLD.reconciled_at THEN
            RAISE EXCEPTION 'Completed bank reconciliations are immutable.';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_prevent_completed_reconciliation_changes
    BEFORE UPDATE OR DELETE ON public.bank_reconciliations
    FOR EACH ROW EXECUTE FUNCTION public.prevent_completed_reconciliation_changes();


-- Reconciled transaction lock trigger
CREATE OR REPLACE FUNCTION public.prevent_reconciled_ledger_transaction_changes()
RETURNS TRIGGER AS $$
DECLARE
    recon_status VARCHAR;
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.bank_reconciliation_id IS NOT NULL THEN
            SELECT status INTO recon_status FROM public.bank_reconciliations WHERE id = OLD.bank_reconciliation_id;
            IF recon_status = 'completed' THEN
                RAISE EXCEPTION 'Reconciled ledger transactions cannot be deleted.';
            END IF;
        END IF;
    END IF;

    IF TG_OP = 'UPDATE' THEN
        IF OLD.bank_reconciliation_id IS NOT NULL THEN
            SELECT status INTO recon_status FROM public.bank_reconciliations WHERE id = OLD.bank_reconciliation_id;
            IF recon_status = 'completed' THEN
                IF NEW.bank_reconciliation_id IS DISTINCT FROM OLD.bank_reconciliation_id OR
                   NEW.reconciled_at IS DISTINCT FROM OLD.reconciled_at THEN
                    RAISE EXCEPTION 'Reconciliation assignment on completed statement is immutable.';
                END IF;
            END IF;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_prevent_reconciled_ledger_transaction_changes
    BEFORE UPDATE OR DELETE ON public.ledger_transactions
    FOR EACH ROW EXECUTE FUNCTION public.prevent_reconciled_ledger_transaction_changes();


-- =========================================================================
-- 9. PHASE 2C STORED PROCEDURES (SECURITY DEFINER)
-- =========================================================================

-- approve_expense_voucher
CREATE OR REPLACE FUNCTION public.approve_expense_voucher(
    voucher_uuid UUID
)
RETURNS BOOLEAN AS $$
DECLARE
    caller_uuid UUID := COALESCE(auth.uid(), 'a0000000-0000-0000-0000-000000000000');
    v_row RECORD;
BEGIN
    SELECT * INTO v_row FROM public.expense_vouchers WHERE id = voucher_uuid FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Voucher not found.';
    END IF;

    IF v_row.status <> 'pending_approval' THEN
        RAISE EXCEPTION 'Only pending vouchers can be approved.';
    END IF;

    IF NOT (public.is_admin(caller_uuid) AND EXISTS (
        SELECT 1 FROM public.users WHERE id = caller_uuid AND status = 'active'
    )) THEN
        RAISE EXCEPTION 'Unauthorized: Caller must be an active administrator.';
    END IF;

    UPDATE public.expense_vouchers
    SET status = 'approved',
        approved_by = caller_uuid,
        approved_at = NOW()
    WHERE id = voucher_uuid;

    INSERT INTO public.audit_logs (user_id, action, table_name, record_id, new_value)
    VALUES (caller_uuid, 'APPROVED expense voucher', 'expense_vouchers', voucher_uuid, jsonb_build_object('status', 'approved'));

    INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
    VALUES (v_row.society_id, v_row.created_by, 'expense_status', 'Expense Approved', 'Expense voucher for ₹' || v_row.amount || ' approved.', 'expense_vouchers', voucher_uuid);

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;


-- reject_expense_voucher
CREATE OR REPLACE FUNCTION public.reject_expense_voucher(
    voucher_uuid UUID,
    reason TEXT
)
RETURNS BOOLEAN AS $$
DECLARE
    caller_uuid UUID := COALESCE(auth.uid(), 'a0000000-0000-0000-0000-000000000000');
    v_row RECORD;
BEGIN
    SELECT * INTO v_row FROM public.expense_vouchers WHERE id = voucher_uuid FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Voucher not found.';
    END IF;

    IF v_row.status NOT IN ('pending_approval', 'approved') THEN
        RAISE EXCEPTION 'Only pending or approved vouchers can be rejected.';
    END IF;

    IF NOT (public.is_admin(caller_uuid) AND EXISTS (
        SELECT 1 FROM public.users WHERE id = caller_uuid AND status = 'active'
    )) THEN
        RAISE EXCEPTION 'Unauthorized: Caller must be an active administrator.';
    END IF;

    UPDATE public.expense_vouchers
    SET status = 'rejected',
        description = COALESCE(description, '') || E'\nRejection Reason: ' || reason
    WHERE id = voucher_uuid;

    INSERT INTO public.audit_logs (user_id, action, table_name, record_id, new_value)
    VALUES (caller_uuid, 'REJECTED expense voucher', 'expense_vouchers', voucher_uuid, jsonb_build_object('status', 'rejected', 'reason', reason));

    INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
    VALUES (v_row.society_id, v_row.created_by, 'expense_status', 'Expense Rejected', 'Expense voucher for ₹' || v_row.amount || ' rejected.', 'expense_vouchers', voucher_uuid);

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;


-- post_expense_voucher
CREATE OR REPLACE FUNCTION public.post_expense_voucher(
    voucher_uuid UUID
)
RETURNS BOOLEAN AS $$
DECLARE
    caller_uuid UUID := COALESCE(auth.uid(), 'a0000000-0000-0000-0000-000000000000');
    v_row RECORD;
BEGIN
    SELECT * INTO v_row FROM public.expense_vouchers WHERE id = voucher_uuid FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Voucher not found.';
    END IF;

    IF v_row.status <> 'approved' THEN
        RAISE EXCEPTION 'Only approved vouchers can be posted.';
    END IF;

    IF NOT (public.is_admin(caller_uuid) AND EXISTS (
        SELECT 1 FROM public.users WHERE id = caller_uuid AND status = 'active'
    )) THEN
        RAISE EXCEPTION 'Unauthorized: Caller must be an active administrator.';
    END IF;

    -- Append Society Cash/Bank sub-ledger credit
    INSERT INTO public.ledger_transactions (
        society_id,
        property_id,
        user_id,
        billing_subject_type,
        billing_property_id,
        scope,
        direction,
        amount,
        transaction_type,
        transaction_date,
        reference_id,
        created_by
    ) VALUES (
        v_row.society_id,
        NULL,
        NULL,
        'none',
        NULL,
        'society',
        'credit',
        v_row.amount,
        'expense',
        CURRENT_DATE,
        voucher_uuid,
        caller_uuid
    );

    UPDATE public.expense_vouchers
    SET status = 'posted'
    WHERE id = voucher_uuid;

    INSERT INTO public.audit_logs (user_id, action, table_name, record_id, new_value)
    VALUES (caller_uuid, 'POSTED expense voucher', 'expense_vouchers', voucher_uuid, jsonb_build_object('status', 'posted'));

    INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
    VALUES (v_row.society_id, v_row.created_by, 'expense_status', 'Expense Disbursed', 'Expense voucher for ₹' || v_row.amount || ' posted as disbursed.', 'expense_vouchers', voucher_uuid);

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;


-- reverse_expense_voucher
CREATE OR REPLACE FUNCTION public.reverse_expense_voucher(
    voucher_uuid UUID,
    reason TEXT
)
RETURNS BOOLEAN AS $$
DECLARE
    caller_uuid UUID := COALESCE(auth.uid(), 'a0000000-0000-0000-0000-000000000000');
    v_row RECORD;
    tx RECORD;
BEGIN
    SELECT * INTO v_row FROM public.expense_vouchers WHERE id = voucher_uuid FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Voucher not found.';
    END IF;

    IF v_row.status <> 'posted' THEN
        RAISE EXCEPTION 'Only posted vouchers can be reversed.';
    END IF;

    IF NOT (public.is_admin(caller_uuid) AND EXISTS (
        SELECT 1 FROM public.users WHERE id = caller_uuid AND status = 'active'
    )) THEN
        RAISE EXCEPTION 'Unauthorized: Caller must be an active administrator.';
    END IF;

    -- Reverse ledger transactions
    FOR tx IN 
        SELECT * FROM public.ledger_transactions 
        WHERE reference_id = voucher_uuid
    LOOP
        INSERT INTO public.ledger_transactions (
            society_id,
            property_id,
            user_id,
            billing_subject_type,
            billing_property_id,
            scope,
            direction,
            amount,
            transaction_type,
            transaction_date,
            reference_id,
            created_by
        ) VALUES (
            tx.society_id,
            tx.property_id,
            tx.user_id,
            tx.billing_subject_type,
            tx.billing_property_id,
            tx.scope,
            CASE WHEN tx.direction = 'debit' THEN 'credit'::VARCHAR ELSE 'debit'::VARCHAR END,
            tx.amount,
            'reversal',
            CURRENT_DATE,
            tx.id,
            caller_uuid
        );
    END LOOP;

    UPDATE public.expense_vouchers
    SET status = 'reversed',
        description = COALESCE(description, '') || E'\nReversal Reason: ' || reason
    WHERE id = voucher_uuid;

    INSERT INTO public.audit_logs (user_id, action, table_name, record_id, new_value)
    VALUES (caller_uuid, 'REVERSED expense voucher', 'expense_vouchers', voucher_uuid, jsonb_build_object('status', 'reversed', 'reason', reason));

    INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
    VALUES (v_row.society_id, v_row.created_by, 'expense_status', 'Expense Reversed', 'Expense voucher for ₹' || v_row.amount || ' reversed: ' || reason, 'expense_vouchers', voucher_uuid);

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;


-- reconcile_transactions
CREATE OR REPLACE FUNCTION public.reconcile_transactions(
    reconciliation_uuid UUID,
    transaction_uuids UUID[]
)
RETURNS BOOLEAN AS $$
DECLARE
    caller_uuid UUID := COALESCE(auth.uid(), 'a0000000-0000-0000-0000-000000000000');
    recon_row RECORD;
    tx_id UUID;
    tx_row RECORD;
BEGIN
    SELECT * INTO recon_row FROM public.bank_reconciliations WHERE id = reconciliation_uuid FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Reconciliation record not found.';
    END IF;

    IF recon_row.status = 'completed' THEN
        RAISE EXCEPTION 'Cannot match transactions on a completed bank reconciliation.';
    END IF;

    IF NOT (public.is_admin(caller_uuid) AND EXISTS (
        SELECT 1 FROM public.users WHERE id = caller_uuid AND status = 'active'
    )) THEN
        RAISE EXCEPTION 'Unauthorized: Caller must be an active administrator.';
    END IF;

    FOREACH tx_id IN ARRAY transaction_uuids LOOP
        SELECT * INTO tx_row FROM public.ledger_transactions WHERE id = tx_id FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Ledger transaction % not found.', tx_id;
        END IF;

        IF tx_row.society_id <> recon_row.society_id THEN
            RAISE EXCEPTION 'Cross-society reconciliation blocked for transaction %.', tx_id;
        END IF;

        IF tx_row.scope <> 'society' THEN
            RAISE EXCEPTION 'Member-scoped transactions cannot be reconciled. ID: %', tx_id;
        END IF;

        IF tx_row.bank_reconciliation_id IS NOT NULL THEN
            RAISE EXCEPTION 'Transaction % is already matched to a reconciliation.', tx_id;
        END IF;

        UPDATE public.ledger_transactions
        SET bank_reconciliation_id = reconciliation_uuid,
            reconciled_at = NOW()
        WHERE id = tx_id;
    END LOOP;

    INSERT INTO public.audit_logs (user_id, action, table_name, record_id, new_value)
    VALUES (caller_uuid, 'RECONCILED ledger transactions', 'bank_reconciliations', reconciliation_uuid, jsonb_build_object('transaction_count', array_length(transaction_uuids, 1)));

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;


-- =========================================================================
-- 10. ROW LEVEL SECURITY (RLS) FOR PHASE 2C
-- =========================================================================

ALTER TABLE public.expense_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expense_vouchers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.budgets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bank_reconciliations ENABLE ROW LEVEL SECURITY;

-- expense_categories RLS
CREATE POLICY "View expense categories" ON public.expense_categories FOR SELECT 
    USING (
        EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid() 
              AND u.status = 'active'
              AND (
                  u.roles ? 'admin' OR 
                  u.roles ? 'secretary' OR 
                  u.roles ? 'treasurer' OR 
                  u.roles ? 'executive_member' OR 
                  u.roles ? 'member'
              )
        )
    );

CREATE POLICY "Admin manage expense categories" ON public.expense_categories FOR ALL 
    USING (public.is_admin(auth.uid()));

-- expense_vouchers RLS
CREATE POLICY "View expense vouchers" ON public.expense_vouchers FOR SELECT 
    USING (
        public.is_admin(auth.uid()) OR (
            status IN ('approved', 'posted') AND 
            EXISTS (
                SELECT 1 FROM public.users u
                WHERE u.id = auth.uid() 
                  AND u.status = 'active'
                  AND (u.roles ? 'member')
            )
        )
    );

CREATE POLICY "Admin manage expense vouchers" ON public.expense_vouchers FOR ALL 
    USING (public.is_admin(auth.uid()));

-- budgets RLS
CREATE POLICY "View budgets" ON public.budgets FOR SELECT 
    USING (
        EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid() 
              AND u.status = 'active'
              AND (
                  u.roles ? 'admin' OR 
                  u.roles ? 'secretary' OR 
                  u.roles ? 'treasurer' OR 
                  u.roles ? 'executive_member' OR 
                  u.roles ? 'member'
              )
        )
    );

CREATE POLICY "Admin manage budgets" ON public.budgets FOR ALL 
    USING (public.is_admin(auth.uid()));

-- bank_reconciliations RLS
CREATE POLICY "View bank reconciliations" ON public.bank_reconciliations FOR SELECT 
    USING (
        public.is_admin(auth.uid()) OR (
            status = 'completed' AND 
            EXISTS (
                SELECT 1 FROM public.users u
                WHERE u.id = auth.uid() 
                  AND u.status = 'active'
                  AND (u.roles ? 'member')
            )
        )
    );

CREATE POLICY "Admin manage bank reconciliations" ON public.bank_reconciliations FOR ALL 
    USING (public.is_admin(auth.uid()));


-- =========================================================================
-- 11. PHASE 3A TABLES & STRUCTURES
-- =========================================================================

-- Amenities Table
CREATE TABLE IF NOT EXISTS public.amenities (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    booking_type VARCHAR(30) NOT NULL CONSTRAINT check_amenity_booking_type CHECK (booking_type IN ('slot_based', 'day_based')),
    hourly_rate NUMERIC(10, 2) NOT NULL DEFAULT 0.00 CONSTRAINT check_amenity_rate CHECK (hourly_rate >= 0),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    CONSTRAINT unique_society_amenity_name UNIQUE (society_id, name)
);

-- Amenity Bookings Table
CREATE TABLE IF NOT EXISTS public.amenity_bookings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    amenity_id UUID NOT NULL REFERENCES public.amenities(id) ON DELETE CASCADE,
    property_id UUID NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
    booked_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    start_time TIMESTAMP WITH TIME ZONE NOT NULL,
    end_time TIMESTAMP WITH TIME ZONE NOT NULL,
    total_charges NUMERIC(15, 2) NOT NULL DEFAULT 0.00 CONSTRAINT check_booking_charges CHECK (total_charges >= 0),
    status VARCHAR(30) NOT NULL DEFAULT 'pending_approval' CONSTRAINT check_booking_status CHECK (status IN ('pending_approval', 'approved', 'rejected', 'cancelled', 'completed')),
    payment_status VARCHAR(30) NOT NULL DEFAULT 'unpaid' CONSTRAINT check_booking_payment_status CHECK (payment_status IN ('unpaid', 'paid', 'refunded')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    CONSTRAINT check_booking_times CHECK (start_time < end_time)
);

-- Helpdesk Tickets Table
CREATE TABLE IF NOT EXISTS public.helpdesk_tickets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE,
    unit_id UUID NOT NULL REFERENCES public.units(id) ON DELETE RESTRICT,
    created_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    category VARCHAR(50) NOT NULL CONSTRAINT check_ticket_category CHECK (category IN ('plumbing', 'electrical', 'carpentry', 'security', 'billing', 'other')),
    title VARCHAR(150) NOT NULL,
    description TEXT NOT NULL,
    priority VARCHAR(20) NOT NULL DEFAULT 'medium' CONSTRAINT check_ticket_priority CHECK (priority IN ('low', 'medium', 'high', 'emergency')),
    status VARCHAR(30) NOT NULL DEFAULT 'open' CONSTRAINT check_ticket_status CHECK (status IN ('open', 'assigned', 'in_progress', 'resolved', 'closed')),
    assigned_to UUID REFERENCES public.users(id) ON DELETE SET NULL,
    resolved_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

-- Ticket Comments Table
CREATE TABLE IF NOT EXISTS public.ticket_comments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    ticket_id UUID NOT NULL REFERENCES public.helpdesk_tickets(id) ON DELETE CASCADE,
    author_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    comment_text TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

-- Visitor Logs Table
CREATE TABLE IF NOT EXISTS public.visitor_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE,
    unit_id UUID NOT NULL REFERENCES public.units(id) ON DELETE RESTRICT,
    visitor_name VARCHAR(100) NOT NULL,
    visitor_mobile VARCHAR(20),
    purpose VARCHAR(100) NOT NULL CONSTRAINT check_visitor_purpose CHECK (purpose IN ('guest', 'delivery', 'service', 'other')),
    check_in TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    check_out TIMESTAMP WITH TIME ZONE,
    pre_auth_code VARCHAR(6) CONSTRAINT check_pre_auth_format CHECK (pre_auth_code IS NULL OR pre_auth_code ~ '^[0-9]{6}$'),
    vehicle_number VARCHAR(30),
    registered_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    CONSTRAINT check_visitor_times CHECK (check_out IS NULL OR check_out >= check_in)
);

-- Safe Indices
CREATE INDEX IF NOT EXISTS idx_amenities_society ON public.amenities (society_id, is_active);
CREATE INDEX IF NOT EXISTS idx_bookings_amenity_dates ON public.amenity_bookings (amenity_id, start_time, end_time);
CREATE INDEX IF NOT EXISTS idx_tickets_society_status ON public.helpdesk_tickets (society_id, status);
CREATE INDEX IF NOT EXISTS idx_visitor_logs_active ON public.visitor_logs (society_id, check_out) WHERE check_out IS NULL;

-- FIX 3: Partial unique index to prevent duplicate active pre-auth codes within the same society
-- Allows: NULL codes, reuse after check-out, codes in different societies
-- Blocks: two simultaneous active (not-checked-out) visitor records sharing the same pre_auth_code+society_id
CREATE UNIQUE INDEX IF NOT EXISTS uq_visitor_active_pre_auth
    ON public.visitor_logs (society_id, pre_auth_code)
    WHERE pre_auth_code IS NOT NULL
      AND check_out IS NULL;

-- Trigger logic for preventing overlapping bookings
CREATE OR REPLACE FUNCTION public.validate_amenity_booking_overlap()
RETURNS TRIGGER AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM public.amenity_bookings
        WHERE amenity_id = NEW.amenity_id
          AND id <> COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
          AND status IN ('pending_approval', 'approved')
          AND NEW.start_time < end_time
          AND NEW.end_time > start_time
    ) THEN
        RAISE EXCEPTION 'Overlapping booking slot detected for this amenity.';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_validate_amenity_booking_overlap
    BEFORE INSERT OR UPDATE ON public.amenity_bookings
    FOR EACH ROW EXECUTE FUNCTION public.validate_amenity_booking_overlap();


-- create_amenity_booking
CREATE OR REPLACE FUNCTION public.create_amenity_booking(
    amenity_uuid UUID,
    property_uuid UUID,
    start_t TIMESTAMP WITH TIME ZONE,
    end_t TIMESTAMP WITH TIME ZONE
)
RETURNS UUID AS $$
DECLARE
    caller_uuid UUID := COALESCE(auth.uid(), 'a0000000-0000-0000-0000-000000000000');
    amenity_row RECORD;
    prop_row RECORD;
    is_authorized BOOLEAN := FALSE;
    charges NUMERIC(15, 2) := 0.00;
    booking_id UUID;
    duration_hours DOUBLE PRECISION;
BEGIN
    SELECT * INTO amenity_row FROM public.amenities WHERE id = amenity_uuid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Amenity not found.';
    END IF;
    IF NOT amenity_row.is_active THEN
        RAISE EXCEPTION 'Amenity is currently inactive.';
    END IF;

    SELECT * INTO prop_row FROM public.properties WHERE id = property_uuid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Property not found.';
    END IF;

    IF amenity_row.society_id <> prop_row.society_id THEN
        RAISE EXCEPTION 'Amenity and Property must belong to the same society.';
    END IF;

    -- Authorize caller
    IF EXISTS (
        SELECT 1 FROM public.users u
        WHERE u.id = caller_uuid AND u.status = 'active'
          AND (u.roles ? 'admin' OR u.roles ? 'secretary' OR u.roles ? 'treasurer' OR u.roles ? 'executive_member')
    ) THEN
        is_authorized := TRUE;
    ELSIF EXISTS (
        SELECT 1 FROM public.property_owners po
        WHERE po.property_id = property_uuid
          AND po.owner_id = caller_uuid
          AND po.end_date IS NULL
    ) THEN
        is_authorized := TRUE;
    ELSIF EXISTS (
        SELECT 1 FROM public.tenancies t
        JOIN public.units u ON u.id = t.unit_id
        WHERE u.property_id = property_uuid
          AND t.tenant_id = caller_uuid
          AND t.is_active = TRUE
          AND t.start_date <= CURRENT_DATE
          AND (t.end_date IS NULL OR t.end_date >= CURRENT_DATE)
    ) THEN
        is_authorized := TRUE;
    END IF;

    IF NOT is_authorized THEN
        RAISE EXCEPTION 'Unauthorized: Caller is not associated with this property.';
    END IF;

    -- FIX 4: Upgrade lock from FOR SHARE to FOR UPDATE to serialize concurrent booking
    -- creation for the same amenity, preventing overlap-check race conditions.
    PERFORM 1 FROM public.amenities WHERE id = amenity_uuid FOR UPDATE;

    -- Calculate charges
    IF amenity_row.booking_type = 'slot_based' THEN
        duration_hours := EXTRACT(EPOCH FROM (end_t - start_t)) / 3600.0;
        IF duration_hours <= 0 THEN
            RAISE EXCEPTION 'Invalid booking duration.';
        END IF;
        charges := ROUND((duration_hours * amenity_row.hourly_rate)::numeric, 2);
    ELSE
        duration_hours := EXTRACT(EPOCH FROM (end_t - start_t)) / 86400.0;
        IF duration_hours <= 0 THEN
            RAISE EXCEPTION 'Invalid booking duration.';
        END IF;
        charges := ROUND((CEIL(duration_hours) * amenity_row.hourly_rate)::numeric, 2);
    END IF;

    INSERT INTO public.amenity_bookings (
        amenity_id,
        property_id,
        booked_by,
        start_time,
        end_time,
        total_charges,
        status,
        payment_status
    ) VALUES (
        amenity_uuid,
        property_uuid,
        caller_uuid,
        start_t,
        end_t,
        charges,
        'pending_approval',
        'unpaid'
    ) RETURNING id INTO booking_id;

    RETURN booking_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;


-- approve_amenity_booking
CREATE OR REPLACE FUNCTION public.approve_amenity_booking(
    booking_uuid UUID
)
RETURNS BOOLEAN AS $$
DECLARE
    caller_uuid UUID := COALESCE(auth.uid(), 'a0000000-0000-0000-0000-000000000000');
    booking_row RECORD;
    amenity_row RECORD;
    owner_uuid UUID;
BEGIN
    SELECT * INTO booking_row FROM public.amenity_bookings WHERE id = booking_uuid FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Booking not found.';
    END IF;

    IF booking_row.status <> 'pending_approval' THEN
        RAISE EXCEPTION 'Only pending bookings can be approved.';
    END IF;

    IF NOT (
        EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = caller_uuid AND u.status = 'active'
              AND (u.roles ? 'admin' OR u.roles ? 'secretary' OR u.roles ? 'treasurer')
        )
    ) THEN
        RAISE EXCEPTION 'Unauthorized: Caller must be an active administrator or secretary.';
    END IF;

    SELECT * INTO amenity_row FROM public.amenities WHERE id = booking_row.amenity_id;

    SELECT owner_id INTO owner_uuid FROM public.property_owners
    WHERE property_id = booking_row.property_id
      AND end_date IS NULL
      AND is_primary = TRUE
    LIMIT 1;

    IF owner_uuid IS NULL THEN
        SELECT owner_id INTO owner_uuid FROM public.property_owners
        WHERE property_id = booking_row.property_id
          AND end_date IS NULL
        LIMIT 1;
    END IF;

    IF owner_uuid IS NULL THEN
        RAISE EXCEPTION 'No active owner found for the property associated with this booking.';
    END IF;

    UPDATE public.amenity_bookings
    SET status = 'approved'
    WHERE id = booking_uuid;

    IF booking_row.total_charges > 0 THEN
        INSERT INTO public.ledger_transactions (
            society_id,
            property_id,
            user_id,
            billing_subject_type,
            billing_property_id,
            scope,
            direction,
            amount,
            transaction_type,
            transaction_date,
            reference_id,
            created_by
        ) VALUES (
            amenity_row.society_id,
            booking_row.property_id,
            owner_uuid,
            'property',
            booking_row.property_id,
            'member',
            'debit',
            booking_row.total_charges,
            'amenity_fee',
            CURRENT_DATE,
            booking_uuid,
            caller_uuid
        );
    END IF;

    INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
    VALUES (amenity_row.society_id, booking_row.booked_by, 'amenity_status', 'Booking Approved', 'Your booking request for ' || amenity_row.name || ' is approved.', 'amenity_bookings', booking_uuid);

    INSERT INTO public.audit_logs (user_id, action, table_name, record_id, new_value)
    VALUES (caller_uuid, 'APPROVED amenity booking', 'amenity_bookings', booking_uuid, jsonb_build_object('status', 'approved', 'ledger_posted', booking_row.total_charges > 0));

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;


-- cancel_amenity_booking
CREATE OR REPLACE FUNCTION public.cancel_amenity_booking(
    booking_uuid UUID
)
RETURNS BOOLEAN AS $$
DECLARE
    caller_uuid UUID := COALESCE(auth.uid(), 'a0000000-0000-0000-0000-000000000000');
    booking_row RECORD;
    amenity_row RECORD;
    is_admin BOOLEAN := FALSE;
    owner_uuid UUID;
BEGIN
    SELECT * INTO booking_row FROM public.amenity_bookings WHERE id = booking_uuid FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Booking not found.';
    END IF;

    IF booking_row.status IN ('cancelled', 'completed', 'rejected') THEN
        RAISE EXCEPTION 'Voucher / Booking in ' || booking_row.status || ' state cannot be cancelled.';
    END IF;

    SELECT * INTO amenity_row FROM public.amenities WHERE id = booking_row.amenity_id;

    SELECT EXISTS (
        SELECT 1 FROM public.users u
        WHERE u.id = caller_uuid AND u.status = 'active'
          AND (u.roles ? 'admin' OR u.roles ? 'secretary' OR u.roles ? 'treasurer')
    ) INTO is_admin;

    IF NOT (is_admin OR booking_row.booked_by = caller_uuid) THEN
        RAISE EXCEPTION 'Unauthorized: Only the booking resident or administrators can cancel this booking.';
    END IF;

    IF booking_row.status = 'approved' AND booking_row.total_charges > 0 THEN
        IF EXISTS (
            SELECT 1 FROM public.ledger_transactions
            WHERE reference_id = booking_uuid
              AND transaction_type = 'reversal'
        ) THEN
            RAISE EXCEPTION 'Duplicate reversal blocked: Booking charges already reversed.';
        END IF;

        SELECT owner_id INTO owner_uuid FROM public.property_owners
        WHERE property_id = booking_row.property_id
          AND end_date IS NULL
          AND is_primary = TRUE
        LIMIT 1;

        IF owner_uuid IS NULL THEN
            SELECT owner_id INTO owner_uuid FROM public.property_owners
            WHERE property_id = booking_row.property_id
              AND end_date IS NULL
            LIMIT 1;
        END IF;

        IF owner_uuid IS NULL THEN
            RAISE EXCEPTION 'No active owner found for property to credit reversal.';
        END IF;

        INSERT INTO public.ledger_transactions (
            society_id,
            property_id,
            user_id,
            billing_subject_type,
            billing_property_id,
            scope,
            direction,
            amount,
            transaction_type,
            transaction_date,
            reference_id,
            created_by
        ) VALUES (
            amenity_row.society_id,
            booking_row.property_id,
            owner_uuid,
            'property',
            booking_row.property_id,
            'member',
            'credit',
            booking_row.total_charges,
            'reversal',
            CURRENT_DATE,
            booking_uuid,
            caller_uuid
        );
    END IF;

    UPDATE public.amenity_bookings
    SET status = 'cancelled'
    WHERE id = booking_uuid;

    INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
    VALUES (amenity_row.society_id, booking_row.booked_by, 'amenity_status', 'Booking Cancelled', 'Your booking request for ' || amenity_row.name || ' was cancelled.', 'amenity_bookings', booking_uuid);

    INSERT INTO public.audit_logs (user_id, action, table_name, record_id, new_value)
    VALUES (caller_uuid, 'CANCELLED amenity booking', 'amenity_bookings', booking_uuid, jsonb_build_object('status', 'cancelled'));

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;


-- =========================================================================
-- 12. ROW LEVEL SECURITY (RLS) FOR PHASE 3A
-- =========================================================================

ALTER TABLE public.amenities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.amenity_bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.helpdesk_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ticket_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.visitor_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "View active amenities" ON public.amenities FOR SELECT
    USING (is_active = TRUE OR public.is_admin(auth.uid()));

CREATE POLICY "Admin manage amenities" ON public.amenities FOR ALL
    USING (public.is_admin(auth.uid()));

CREATE POLICY "View bookings" ON public.amenity_bookings FOR SELECT
    USING (
        public.is_admin(auth.uid()) OR
        booked_by = auth.uid() OR
        EXISTS (
            SELECT 1 FROM public.property_owners po
            WHERE po.property_id = amenity_bookings.property_id
              AND po.owner_id = auth.uid()
              AND po.end_date IS NULL
        ) OR
        EXISTS (
            SELECT 1 FROM public.tenancies t
            JOIN public.units u ON u.id = t.unit_id
            WHERE u.property_id = amenity_bookings.property_id
              AND t.tenant_id = auth.uid()
              AND t.is_active = TRUE
        )
    );

CREATE POLICY "Manage own bookings" ON public.amenity_bookings FOR ALL
    USING (
        booked_by = auth.uid() OR
        EXISTS (
            SELECT 1 FROM public.property_owners po
            WHERE po.property_id = amenity_bookings.property_id
              AND po.owner_id = auth.uid()
              AND po.end_date IS NULL
        )
    );

CREATE POLICY "View tickets" ON public.helpdesk_tickets FOR SELECT
    USING (
        public.is_admin(auth.uid()) OR
        created_by = auth.uid() OR
        assigned_to = auth.uid() OR
        EXISTS (
            SELECT 1 FROM public.property_owners po
            JOIN public.units u ON u.property_id = po.property_id
            WHERE u.id = helpdesk_tickets.unit_id
              AND po.owner_id = auth.uid()
              AND po.end_date IS NULL
        ) OR
        EXISTS (
            SELECT 1 FROM public.tenancies t
            WHERE t.unit_id = helpdesk_tickets.unit_id
              AND t.tenant_id = auth.uid()
              AND t.is_active = TRUE
        )
    );

-- FIX 2: Allow assigned technicians to update tickets assigned to them.
-- Society isolation is preserved because: technicians can only access tickets
-- that are already visible to them via the "View tickets" SELECT policy,
-- and the assigned_to column is only set by admins via the assign workflow.
CREATE POLICY "Manage tickets" ON public.helpdesk_tickets FOR ALL
    USING (
        public.is_admin(auth.uid()) OR
        created_by = auth.uid() OR
        assigned_to = auth.uid()
    );

CREATE POLICY "View ticket comments" ON public.ticket_comments FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.helpdesk_tickets t
            WHERE t.id = ticket_comments.ticket_id
              AND (
                  public.is_admin(auth.uid()) OR
                  t.created_by = auth.uid() OR
                  t.assigned_to = auth.uid() OR
                  EXISTS (
                      SELECT 1 FROM public.property_owners po
                      JOIN public.units u ON u.property_id = po.property_id
                      WHERE u.id = t.unit_id
                        AND po.owner_id = auth.uid()
                        AND po.end_date IS NULL
                  ) OR
                  EXISTS (
                      SELECT 1 FROM public.tenancies ten
                      WHERE ten.unit_id = t.unit_id
                        AND ten.tenant_id = auth.uid()
                        AND ten.is_active = TRUE
                  )
              )
        )
    );

CREATE POLICY "Manage ticket comments" ON public.ticket_comments FOR ALL
    USING (
        author_id = auth.uid() OR
        public.is_admin(auth.uid())
    );

CREATE POLICY "Gatekeeper view all visitor logs" ON public.visitor_logs FOR SELECT
    USING (
        public.is_admin(auth.uid()) OR
        EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid() AND u.status = 'active' AND u.roles ? 'gatekeeper'
        ) OR
        EXISTS (
            SELECT 1 FROM public.property_owners po
            JOIN public.units u ON u.property_id = po.property_id
            WHERE u.id = visitor_logs.unit_id
              AND po.owner_id = auth.uid()
              AND po.end_date IS NULL
        ) OR
        EXISTS (
            SELECT 1 FROM public.tenancies t
            WHERE t.unit_id = visitor_logs.unit_id
              AND t.tenant_id = auth.uid()
              AND t.is_active = TRUE
        )
    );

CREATE POLICY "Gatekeeper modify visitor logs" ON public.visitor_logs FOR ALL
    USING (
        public.is_admin(auth.uid()) OR
        EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid() AND u.status = 'active' AND u.roles ? 'gatekeeper'
        )
    );
