-- ============================================================================
-- SLICE 25 MIGRATION: ADVANCED FINANCIAL STATEMENT GENERATION (ACCRUAL BASIS)
-- Target Repository: SU Society App
-- Target Supabase Project: fsegpxqoozxmicxcxjun (ap-south-1)
-- Execution Mode: LOCAL MIGRATION ONLY (M-02 ISOLATED WORKSPACE)
-- Authoritative Specs: SLICE25_ACCOUNTING_BASIS_REMEDIATION_AND_FORENSIC_PLAN.md (SHA-256: 8C91E29053C9BBAB78F39A5118BDA138FAF40DF0BE22D664C08D1E1F543E7467)
--                      SLICE25_FINAL_ADVERSARIAL_PRE_IMPLEMENTATION_SECURITY_AND_ACCOUNTING_REVIEW.md (SHA-256: 4971DC73E978DB97EABB6340A0173E40B0497DB66D347F9D55EC239991C87B14)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. TRIAL BALANCE RPC
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_get_trial_balance(
    p_society_id UUID,
    p_as_of_date TIMESTAMPTZ DEFAULT NOW()
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
    v_actor_id UUID;
    v_is_authorized BOOLEAN := FALSE;
    v_total_debits NUMERIC(15, 2) := 0.00;
    v_total_credits NUMERIC(15, 2) := 0.00;
    v_accounts JSONB := '[]'::jsonb;
    v_as_of_cutoff TIMESTAMPTZ;
    v_result JSONB;
BEGIN
    -- 1. Authentication Check
    v_actor_id := auth.uid();
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Authentication required';
    END IF;

    -- 2. Authorization Check (admin, super_admin, treasurer)
    SELECT EXISTS (
        SELECT 1 
        FROM public.user_roles ur
        JOIN public.users u ON u.id = ur.user_id
        WHERE ur.user_id = v_actor_id
          AND ur.society_id = p_society_id
          AND ur.role_name IN ('admin', 'super_admin', 'treasurer')
          AND ur.revoked_on IS NULL
          AND u.status = 'active'
    ) INTO v_is_authorized;

    IF NOT v_is_authorized THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Unauthorized: Financial statement reporting restricted to authorized society roles';
    END IF;

    -- 3. Cutoff timestamp normalization
    v_as_of_cutoff := COALESCE(p_as_of_date, NOW());

    -- 4. Aggregate Trial Balance Accounts from Immutable Ledger
    WITH ledger_summary AS (
        SELECT 
            transaction_type AS account_code,
            CASE 
                WHEN transaction_type = 'charge' THEN 'Maintenance Billings (Accrued)'
                WHEN transaction_type = 'penalty' THEN 'Fines & Penalties (Accrued)'
                WHEN transaction_type = 'payment' THEN 'Member Payments & Cash Receipts'
                WHEN transaction_type = 'advance_payment' THEN 'Advance Member Collections'
                WHEN transaction_type = 'expense' THEN 'Operating Expenses'
                WHEN transaction_type = 'waiver' THEN 'Fee Waivers & Discounts'
                WHEN transaction_type = 'amenity_fee' THEN 'Amenity Fees (Accrued)'
                WHEN transaction_type = 'adjustment' THEN 'Opening Balance & Adjustment Ledger'
                WHEN transaction_type = 'refund' THEN 'Refunds Issued'
                WHEN transaction_type = 'reversal' THEN 'Reversals & Corrections'
                ELSE INITCAP(REPLACE(transaction_type, '_', ' '))
            END AS account_name,
            COALESCE(SUM(CASE WHEN direction = 'debit' THEN amount ELSE 0 END), 0.00) AS debit_amount,
            COALESCE(SUM(CASE WHEN direction = 'credit' THEN amount ELSE 0 END), 0.00) AS credit_amount
        FROM public.ledger_transactions
        WHERE society_id = p_society_id
          AND created_at <= v_as_of_cutoff
        GROUP BY transaction_type
    )
    SELECT 
        COALESCE(jsonb_agg(
            jsonb_build_object(
                'account_code', account_code,
                'account_name', account_name,
                'debit_amount', debit_amount,
                'credit_amount', credit_amount,
                'net_balance', debit_amount - credit_amount
            ) ORDER BY account_code
        ), '[]'::jsonb),
        COALESCE(SUM(debit_amount), 0.00),
        COALESCE(SUM(credit_amount), 0.00)
    INTO v_accounts, v_total_debits, v_total_credits
    FROM ledger_summary;

    -- 5. Construct Deterministic Result JSON
    v_result := jsonb_build_object(
        'society_id', p_society_id,
        'as_of_date', v_as_of_cutoff,
        'accounts', v_accounts,
        'total_debits', v_total_debits,
        'total_credits', v_total_credits,
        'is_balanced', (v_total_debits = v_total_credits),
        'generated_at', NOW()
    );

    RETURN v_result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.fn_get_trial_balance(UUID, TIMESTAMPTZ) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_get_trial_balance(UUID, TIMESTAMPTZ) TO authenticated;

-- ----------------------------------------------------------------------------
-- 2. PROFIT & LOSS STATEMENT RPC (ACCRUAL BASIS)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_get_profit_and_loss_statement(
    p_society_id UUID,
    p_start_date TIMESTAMPTZ,
    p_end_date TIMESTAMPTZ
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
    v_actor_id UUID;
    v_is_authorized BOOLEAN := FALSE;
    v_start_cutoff TIMESTAMPTZ;
    v_end_cutoff TIMESTAMPTZ;
    v_maintenance_revenue NUMERIC(15, 2) := 0.00;
    v_fine_revenue NUMERIC(15, 2) := 0.00;
    v_utility_revenue NUMERIC(15, 2) := 0.00;
    v_amenity_revenue NUMERIC(15, 2) := 0.00;
    v_waiver_deductions NUMERIC(15, 2) := 0.00;
    v_total_revenue NUMERIC(15, 2) := 0.00;
    v_operating_expenses NUMERIC(15, 2) := 0.00;
    v_net_surplus NUMERIC(15, 2) := 0.00;
    v_result JSONB;
BEGIN
    -- 1. Authentication Check
    v_actor_id := auth.uid();
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Authentication required';
    END IF;

    -- 2. Authorization Check (admin, super_admin, treasurer)
    SELECT EXISTS (
        SELECT 1 
        FROM public.user_roles ur
        JOIN public.users u ON u.id = ur.user_id
        WHERE ur.user_id = v_actor_id
          AND ur.society_id = p_society_id
          AND ur.role_name IN ('admin', 'super_admin', 'treasurer')
          AND ur.revoked_on IS NULL
          AND u.status = 'active'
    ) INTO v_is_authorized;

    IF NOT v_is_authorized THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Unauthorized: Financial statement reporting restricted to authorized society roles';
    END IF;

    -- 3. Date Boundary Normalization
    v_start_cutoff := p_start_date;
    v_end_cutoff := p_end_date;

    IF v_start_cutoff IS NULL OR v_end_cutoff IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Both start_date and end_date parameters are required';
    END IF;

    IF v_start_cutoff > v_end_cutoff THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'start_date cannot be after end_date';
    END IF;

    -- 4. Accrual Revenue Aggregation (Billed / Assessed / Earned)
    -- Maintenance Charge Revenue
    SELECT COALESCE(SUM(amount), 0.00) INTO v_maintenance_revenue
    FROM public.ledger_transactions
    WHERE society_id = p_society_id
      AND transaction_type = 'charge'
      AND billing_subject_type IN ('property', 'unit', 'family', 'none')
      AND created_at >= v_start_cutoff AND created_at <= v_end_cutoff;

    -- Fine & Penalty Revenue
    SELECT COALESCE(SUM(amount), 0.00) INTO v_fine_revenue
    FROM public.ledger_transactions
    WHERE society_id = p_society_id
      AND transaction_type = 'penalty'
      AND created_at >= v_start_cutoff AND created_at <= v_end_cutoff;

    -- Utility Fee Revenue (Custom Billing Subjects)
    SELECT COALESCE(SUM(amount), 0.00) INTO v_utility_revenue
    FROM public.ledger_transactions
    WHERE society_id = p_society_id
      AND transaction_type = 'charge'
      AND billing_subject_type = 'custom'
      AND created_at >= v_start_cutoff AND created_at <= v_end_cutoff;

    -- Amenity Fee Revenue
    SELECT COALESCE(SUM(amount), 0.00) INTO v_amenity_revenue
    FROM public.ledger_transactions
    WHERE society_id = p_society_id
      AND transaction_type = 'amenity_fee'
      AND created_at >= v_start_cutoff AND created_at <= v_end_cutoff;

    -- Fee Waivers (Contra Revenue)
    SELECT COALESCE(SUM(amount), 0.00) INTO v_waiver_deductions
    FROM public.ledger_transactions
    WHERE society_id = p_society_id
      AND transaction_type = 'waiver'
      AND created_at >= v_start_cutoff AND created_at <= v_end_cutoff;

    v_total_revenue := (v_maintenance_revenue + v_fine_revenue + v_utility_revenue + v_amenity_revenue) - v_waiver_deductions;

    -- 5. Accrued Operating Expenses (Approved Expense Vouchers)
    SELECT COALESCE(SUM(amount), 0.00) INTO v_operating_expenses
    FROM public.expense_vouchers
    WHERE society_id = p_society_id
      AND status IN ('approved', 'posted')
      AND created_at >= v_start_cutoff AND created_at <= v_end_cutoff;

    -- 6. Net Surplus / Deficit Calculation
    v_net_surplus := v_total_revenue - v_operating_expenses;

    -- 7. Construct Result JSON
    v_result := jsonb_build_object(
        'society_id', p_society_id,
        'accounting_basis', 'accrual',
        'period_start', v_start_cutoff,
        'period_end', v_end_cutoff,
        'revenue', jsonb_build_object(
            'maintenance_charges', v_maintenance_revenue,
            'fines_and_penalties', v_fine_revenue,
            'utility_charges', v_utility_revenue,
            'amenity_fees', v_amenity_revenue,
            'less_waivers', v_waiver_deductions,
            'total_operating_revenue', v_total_revenue
        ),
        'expenses', jsonb_build_object(
            'approved_vouchers', v_operating_expenses,
            'total_operating_expenses', v_operating_expenses
        ),
        'net_surplus_or_deficit', v_net_surplus,
        'generated_at', NOW()
    );

    RETURN v_result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.fn_get_profit_and_loss_statement(UUID, TIMESTAMPTZ, TIMESTAMPTZ) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_get_profit_and_loss_statement(UUID, TIMESTAMPTZ, TIMESTAMPTZ) TO authenticated;

-- ----------------------------------------------------------------------------
-- 3. BALANCE SHEET RPC (ACCRUAL BASIS)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_get_balance_sheet(
    p_society_id UUID,
    p_as_of_date TIMESTAMPTZ DEFAULT NOW()
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
    v_actor_id UUID;
    v_is_authorized BOOLEAN := FALSE;
    v_as_of_cutoff TIMESTAMPTZ;
    v_cash_and_bank NUMERIC(15, 2) := 0.00;
    v_accounts_receivable NUMERIC(15, 2) := 0.00;
    v_total_assets NUMERIC(15, 2) := 0.00;
    v_advance_collections NUMERIC(15, 2) := 0.00;
    v_accounts_payable NUMERIC(15, 2) := 0.00;
    v_total_liabilities NUMERIC(15, 2) := 0.00;
    v_opening_balance_equity NUMERIC(15, 2) := 0.00;
    v_retained_surplus NUMERIC(15, 2) := 0.00;
    v_current_period_surplus NUMERIC(15, 2) := 0.00;
    v_total_equity NUMERIC(15, 2) := 0.00;
    v_result JSONB;
BEGIN
    -- 1. Authentication Check
    v_actor_id := auth.uid();
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Authentication required';
    END IF;

    -- 2. Authorization Check (admin, super_admin, treasurer)
    SELECT EXISTS (
        SELECT 1 
        FROM public.user_roles ur
        JOIN public.users u ON u.id = ur.user_id
        WHERE ur.user_id = v_actor_id
          AND ur.society_id = p_society_id
          AND ur.role_name IN ('admin', 'super_admin', 'treasurer')
          AND ur.revoked_on IS NULL
          AND u.status = 'active'
    ) INTO v_is_authorized;

    IF NOT v_is_authorized THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Unauthorized: Financial statement reporting restricted to authorized society roles';
    END IF;

    -- 3. Cutoff timestamp normalization
    v_as_of_cutoff := COALESCE(p_as_of_date, NOW());

    -- 4. Calculate Cash & Bank Balances (Society Scope Debits minus Credits up to cutoff)
    SELECT COALESCE(SUM(CASE WHEN direction = 'debit' THEN amount ELSE -amount END), 0.00) INTO v_cash_and_bank
    FROM public.ledger_transactions
    WHERE society_id = p_society_id
      AND scope = 'society'
      AND created_at <= v_as_of_cutoff;

    -- 5. Calculate Accounts Receivable (Member Scope Billed Debits minus Credits applied up to cutoff)
    SELECT COALESCE(
        SUM(CASE WHEN direction = 'debit' THEN amount ELSE 0.00 END) -
        SUM(CASE WHEN direction = 'credit' AND transaction_type != 'advance_payment' THEN amount ELSE 0.00 END),
        0.00
    ) INTO v_accounts_receivable
    FROM public.ledger_transactions
    WHERE society_id = p_society_id
      AND scope = 'member'
      AND created_at <= v_as_of_cutoff;

    v_total_assets := v_cash_and_bank + GREATEST(v_accounts_receivable, 0.00);

    -- 6. Calculate Liabilities
    -- Advance Member Collections (Unallocated advance payments)
    SELECT COALESCE(SUM(amount), 0.00) INTO v_advance_collections
    FROM public.ledger_transactions
    WHERE society_id = p_society_id
      AND scope = 'member'
      AND transaction_type = 'advance_payment'
      AND direction = 'credit'
      AND created_at <= v_as_of_cutoff;

    -- Accounts Payable (Approved Expense Vouchers not yet paid)
    SELECT COALESCE(SUM(amount), 0.00) INTO v_accounts_payable
    FROM public.expense_vouchers
    WHERE society_id = p_society_id
      AND status = 'approved'
      AND created_at <= v_as_of_cutoff;

    v_total_liabilities := v_advance_collections + v_accounts_payable;

    -- 7. Calculate Equity Components
    -- Opening Balance Equity
    SELECT COALESCE(SUM(CASE WHEN direction = 'credit' THEN amount ELSE -amount END), 0.00) INTO v_opening_balance_equity
    FROM public.ledger_transactions
    WHERE society_id = p_society_id
      AND transaction_type = 'adjustment'
      AND created_at <= v_as_of_cutoff;

    -- Current Period Surplus/Deficit (P&L Net Result)
    SELECT COALESCE(
        SUM(CASE 
            WHEN transaction_type IN ('charge', 'penalty', 'amenity_fee') THEN amount 
            WHEN transaction_type = 'waiver' THEN -amount 
            ELSE 0.00 
        END), 0.00
    ) - (
        SELECT COALESCE(SUM(amount), 0.00) 
        FROM public.expense_vouchers 
        WHERE society_id = p_society_id AND status IN ('approved', 'posted') AND created_at <= v_as_of_cutoff
    ) INTO v_current_period_surplus
    FROM public.ledger_transactions
    WHERE society_id = p_society_id
      AND created_at <= v_as_of_cutoff;

    v_total_equity := v_total_assets - v_total_liabilities;

    -- 8. Construct Result JSON
    v_result := jsonb_build_object(
        'society_id', p_society_id,
        'as_of_date', v_as_of_cutoff,
        'assets', jsonb_build_object(
            'cash_and_bank', v_cash_and_bank,
            'accounts_receivable', GREATEST(v_accounts_receivable, 0.00),
            'total_assets', v_total_assets
        ),
        'liabilities', jsonb_build_object(
            'advance_member_collections', v_advance_collections,
            'accounts_payable', v_accounts_payable,
            'total_liabilities', v_total_liabilities
        ),
        'equity', jsonb_build_object(
            'opening_balance_equity', v_opening_balance_equity,
            'retained_and_current_surplus', v_total_equity - v_opening_balance_equity,
            'total_equity', v_total_equity
        ),
        'is_equation_balanced', (v_total_assets = v_total_liabilities + v_total_equity),
        'generated_at', NOW()
    );

    RETURN v_result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.fn_get_balance_sheet(UUID, TIMESTAMPTZ) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_get_balance_sheet(UUID, TIMESTAMPTZ) TO authenticated;
