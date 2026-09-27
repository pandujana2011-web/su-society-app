-- ===========================================================================
-- SLICE 9: SECURITY OPERATIONS & COMPLIANCE
-- ===========================================================================

-- 1. STAFF ATTENDANCE LOGS
CREATE TABLE IF NOT EXISTS public.staff_attendance_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    staff_id UUID NOT NULL REFERENCES public.daily_staff(id) ON DELETE RESTRICT,
    gate_pass_id UUID NOT NULL REFERENCES public.gate_passes(id) ON DELETE RESTRICT,
    check_in TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    check_out TIMESTAMPTZ,
    logged_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_attendance_times CHECK (check_out IS NULL OR check_out >= check_in)
);
CREATE TRIGGER trg_staff_attendance_updated_at BEFORE UPDATE ON public.staff_attendance_logs FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Add partial unique index to prevent double check-in
CREATE UNIQUE INDEX idx_unique_active_attendance ON public.staff_attendance_logs(staff_id) WHERE check_out IS NULL;

-- ===========================================================================
-- AMENDMENT: UPDATE LEDGER TRANSACTIONS FOR PENALTIES
-- ===========================================================================
ALTER TABLE public.ledger_transactions ADD COLUMN source_violation_id UUID;

ALTER TABLE public.ledger_transactions DROP CONSTRAINT IF EXISTS chk_ledger_source_exclusive;
ALTER TABLE public.ledger_transactions ADD CONSTRAINT chk_ledger_source_exclusive CHECK (
    (CASE WHEN source_charge_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN source_payment_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN source_expense_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN source_booking_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN source_voucher_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN source_opening_balance_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN reverses_ledger_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN source_violation_id IS NOT NULL THEN 1 ELSE 0 END) = 1
);

ALTER TABLE public.ledger_transactions DROP CONSTRAINT IF EXISTS chk_tx_type;
ALTER TABLE public.ledger_transactions ADD CONSTRAINT chk_tx_type CHECK (transaction_type IN ('charge', 'payment', 'expense', 'reversal', 'adjustment', 'opening_balance', 'booking_charge', 'penalty'));

-- 2. RULE VIOLATIONS
CREATE TABLE IF NOT EXISTS public.rule_violations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    property_id UUID NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
    reported_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    violation_type VARCHAR(50) NOT NULL,
    description TEXT,
    status VARCHAR(50) NOT NULL DEFAULT 'reported'
        CONSTRAINT chk_violation_status CHECK (status IN ('reported', 'under_review', 'penalized', 'dismissed', 'resolved')),
    penalty_amount NUMERIC(10,2) NOT NULL DEFAULT 0
        CONSTRAINT chk_violation_penalty CHECK (penalty_amount >= 0),
    ledger_transaction_id UUID REFERENCES public.ledger_transactions(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TRIGGER trg_rule_violations_updated_at BEFORE UPDATE ON public.rule_violations FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- 3. STATE MACHINES & SECURITY DEFINERS

-- Force logged_by and reported_by on INSERT
CREATE OR REPLACE FUNCTION public.fn_staff_attendance_force_logged_by()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.logged_by := auth.uid();
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_staff_attendance_force_logged_by BEFORE INSERT ON public.staff_attendance_logs
FOR EACH ROW EXECUTE FUNCTION public.fn_staff_attendance_force_logged_by();

CREATE OR REPLACE FUNCTION public.fn_rule_violations_force_reported_by()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.reported_by := auth.uid();
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_rule_violations_force_reported_by BEFORE INSERT ON public.rule_violations
FOR EACH ROW EXECUTE FUNCTION public.fn_rule_violations_force_reported_by();

-- Staff Check In
CREATE OR REPLACE FUNCTION public.fn_staff_check_in(
    p_gate_pass_id UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_pass RECORD;
    v_caller_society UUID;
BEGIN
    v_caller_society := public.get_user_society_id(auth.uid());
    IF NOT (public.is_admin() OR public.has_role(auth.uid(), 'gatekeeper')) THEN
        RAISE EXCEPTION 'Access Denied: Only admins or gatekeepers can log attendance';
    END IF;

    SELECT * INTO v_pass FROM public.gate_passes WHERE id = p_gate_pass_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Gate pass not found'; END IF;
    IF v_pass.society_id != v_caller_society THEN RAISE EXCEPTION 'Cross-society denied'; END IF;

    IF v_pass.status != 'active' THEN RAISE EXCEPTION 'Gate pass is not active'; END IF;
    IF v_pass.valid_until < NOW() THEN RAISE EXCEPTION 'Gate pass expired'; END IF;

    -- The unique index idx_unique_active_attendance handles double check-in inherently.
    INSERT INTO public.staff_attendance_logs (society_id, staff_id, gate_pass_id)
    VALUES (v_caller_society, v_pass.staff_id, p_gate_pass_id);
END;
$$;

-- Staff Check Out
CREATE OR REPLACE FUNCTION public.fn_staff_check_out(
    p_log_id UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_log RECORD;
    v_caller_society UUID;
BEGIN
    v_caller_society := public.get_user_society_id(auth.uid());
    IF NOT (public.is_admin() OR public.has_role(auth.uid(), 'gatekeeper')) THEN
        RAISE EXCEPTION 'Access Denied: Only admins or gatekeepers can log attendance';
    END IF;

    SELECT * INTO v_log FROM public.staff_attendance_logs WHERE id = p_log_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Attendance log not found'; END IF;
    IF v_log.society_id != v_caller_society THEN RAISE EXCEPTION 'Cross-society denied'; END IF;
    IF v_log.check_out IS NOT NULL THEN RAISE EXCEPTION 'Already checked out'; END IF;

    PERFORM set_config('app.attendance_transition', p_log_id::text, true);
    UPDATE public.staff_attendance_logs SET check_out = NOW() WHERE id = p_log_id;
END;
$$;

-- Trigger to protect staff_attendance_logs UPDATE
CREATE OR REPLACE FUNCTION public.fn_prevent_direct_attendance_update()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF current_setting('app.attendance_transition', true) IS DISTINCT FROM NEW.id::text THEN
        RAISE EXCEPTION 'Direct updates blocked. Use fn_staff_check_out';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_prevent_direct_attendance_update BEFORE UPDATE ON public.staff_attendance_logs
FOR EACH ROW EXECUTE FUNCTION public.fn_prevent_direct_attendance_update();


-- Violation State Transition
CREATE OR REPLACE FUNCTION public.fn_transition_violation_state(
    p_violation_id UUID,
    p_new_status VARCHAR,
    p_penalty_amount NUMERIC DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_violation RECORD;
    v_caller_society UUID;
    v_ledger_id UUID := NULL;
BEGIN
    v_caller_society := public.get_user_society_id(auth.uid());
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access Denied: Only admins can transition violations';
    END IF;

    SELECT * INTO v_violation FROM public.rule_violations WHERE id = p_violation_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Violation not found'; END IF;
    IF v_violation.society_id != v_caller_society THEN RAISE EXCEPTION 'Cross-society denied'; END IF;

    IF p_new_status = 'under_review' AND v_violation.status = 'reported' THEN
        -- allowed
    ELSIF p_new_status = 'dismissed' AND v_violation.status = 'under_review' THEN
        -- allowed
    ELSIF p_new_status = 'penalized' AND v_violation.status = 'under_review' THEN
        IF COALESCE(p_penalty_amount, 0) <= 0 THEN
            RAISE EXCEPTION 'Penalty amount must be > 0 for penalized status';
        END IF;
        
        -- Insert into ledger (enforced by Phase 2 invariants)
        INSERT INTO public.ledger_transactions (
            society_id, scope, property_id, transaction_type, direction, amount, source_violation_id, description, created_by
        ) VALUES (
            v_caller_society, 'property', v_violation.property_id, 'penalty', 'debit', p_penalty_amount, p_violation_id, 
            'Penalty for violation: ' || v_violation.violation_type, auth.uid()
        ) RETURNING id INTO v_ledger_id;

    ELSIF p_new_status = 'resolved' AND v_violation.status = 'penalized' THEN
        -- Check if property has outstanding balance? No, they might pay later, or admin just resolves the violation 
        -- independently of the ledger balance. Let's keep it simple: admin resolves it manually.
        -- allowed
    ELSE
        RAISE EXCEPTION 'Invalid transition from % to %', v_violation.status, p_new_status;
    END IF;

    PERFORM set_config('app.violation_transition', p_violation_id::text, true);
    
    IF p_new_status = 'penalized' THEN
        UPDATE public.rule_violations 
        SET status = p_new_status, penalty_amount = p_penalty_amount, ledger_transaction_id = v_ledger_id 
        WHERE id = p_violation_id;
    ELSE
        UPDATE public.rule_violations SET status = p_new_status WHERE id = p_violation_id;
    END IF;
END;
$$;

-- Trigger to protect rule_violations UPDATE
CREATE OR REPLACE FUNCTION public.fn_prevent_direct_violation_update()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF current_setting('app.violation_transition', true) IS DISTINCT FROM NEW.id::text THEN
        RAISE EXCEPTION 'Direct updates blocked. Use fn_transition_violation_state';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_prevent_direct_violation_update BEFORE UPDATE ON public.rule_violations
FOR EACH ROW EXECUTE FUNCTION public.fn_prevent_direct_violation_update();

-- 4. RLS POLICIES
ALTER TABLE public.staff_attendance_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staff_attendance_logs FORCE ROW LEVEL SECURITY;

ALTER TABLE public.rule_violations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rule_violations FORCE ROW LEVEL SECURITY;

-- staff_attendance_logs RLS
CREATE POLICY pol_attendance_admin ON public.staff_attendance_logs FOR ALL USING (public.is_admin());
CREATE POLICY pol_attendance_gatekeeper ON public.staff_attendance_logs FOR ALL USING (public.has_role(auth.uid(), 'gatekeeper'));
CREATE POLICY pol_attendance_select_owner ON public.staff_attendance_logs FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.gate_passes g WHERE g.id = gate_pass_id AND public.is_property_owner(auth.uid(), g.property_id))
);
CREATE POLICY pol_attendance_select_tenant ON public.staff_attendance_logs FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.gate_passes g WHERE g.id = gate_pass_id AND public.is_property_tenant(auth.uid(), g.property_id))
);

-- rule_violations RLS
CREATE POLICY pol_violations_admin ON public.rule_violations FOR ALL USING (public.is_admin());
CREATE POLICY pol_violations_select_owner ON public.rule_violations FOR SELECT USING (
    public.is_property_owner(auth.uid(), property_id) OR reported_by = auth.uid()
);
CREATE POLICY pol_violations_select_tenant ON public.rule_violations FOR SELECT USING (
    public.is_property_tenant(auth.uid(), property_id) OR reported_by = auth.uid()
);
CREATE POLICY pol_violations_insert_resident ON public.rule_violations FOR INSERT WITH CHECK (
    society_id = public.get_user_society_id(auth.uid())
);

-- 5. INDEXES
CREATE INDEX idx_attendance_staff_id ON public.staff_attendance_logs(staff_id);
CREATE INDEX idx_attendance_society_id ON public.staff_attendance_logs(society_id);
CREATE INDEX idx_violations_property_id ON public.rule_violations(property_id);
CREATE INDEX idx_violations_status ON public.rule_violations(status);

-- 6. AUDIT
CREATE TRIGGER trg_audit_staff_attendance_logs AFTER INSERT OR UPDATE OR DELETE ON public.staff_attendance_logs FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger_func();
CREATE TRIGGER trg_audit_rule_violations AFTER INSERT OR UPDATE OR DELETE ON public.rule_violations FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger_func();

-- 7. GRANTS
GRANT SELECT, INSERT, UPDATE, DELETE ON public.staff_attendance_logs TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.rule_violations TO authenticated;
