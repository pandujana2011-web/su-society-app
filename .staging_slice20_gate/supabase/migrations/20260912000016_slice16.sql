-- ==============================================================================
-- SLICE 16 SCHEMA: GOVERNANCE, RESOLUTIONS, BUDGETS & BLACKOUT WORKFLOWS
-- ==============================================================================

BEGIN;

-- 1. Create Tables IF NOT EXISTS

-- 1.1 Committee Resolutions Table
CREATE TABLE IF NOT EXISTS public.committee_resolutions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE,
    proposed_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    title VARCHAR(200) NOT NULL,
    description TEXT NOT NULL,
    category VARCHAR(50) NOT NULL DEFAULT 'governance',
    status VARCHAR(30) NOT NULL DEFAULT 'draft',
    quorum_required INT NOT NULL DEFAULT 3 CONSTRAINT chk_quorum_positive CHECK (quorum_required > 0),
    votes_for INT NOT NULL DEFAULT 0 CONSTRAINT chk_votes_for_nonnegative CHECK (votes_for >= 0),
    votes_against INT NOT NULL DEFAULT 0 CONSTRAINT chk_votes_against_nonnegative CHECK (votes_against >= 0),
    tabled_at TIMESTAMPTZ,
    voting_closed_at TIMESTAMPTZ,
    passed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_resolution_status CHECK (status IN ('draft', 'tabled', 'voting', 'passed', 'rejected', 'archived'))
);

-- 1.2 Committee Resolution Votes Table
CREATE TABLE IF NOT EXISTS public.committee_resolution_votes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    resolution_id UUID NOT NULL REFERENCES public.committee_resolutions(id) ON DELETE CASCADE,
    voter_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    vote VARCHAR(10) NOT NULL CONSTRAINT chk_vote_value CHECK (vote IN ('for', 'against', 'abstain')),
    comments TEXT,
    voted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_resolution_voter UNIQUE (resolution_id, voter_id)
);

-- 1.3 Society Budgets Table
CREATE TABLE IF NOT EXISTS public.society_budgets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE,
    fiscal_year VARCHAR(20) NOT NULL,
    title VARCHAR(150) NOT NULL,
    total_budget NUMERIC(15, 2) NOT NULL DEFAULT 0.00 CONSTRAINT chk_total_budget_nonnegative CHECK (total_budget >= 0),
    status VARCHAR(30) NOT NULL DEFAULT 'draft',
    prepared_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    approved_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    submitted_at TIMESTAMPTZ,
    approved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_society_fiscal_year UNIQUE (society_id, fiscal_year),
    CONSTRAINT chk_budget_status CHECK (status IN ('draft', 'submitted', 'approved', 'active', 'closed'))
);

-- 1.4 Budget Line Items Table
CREATE TABLE IF NOT EXISTS public.budget_line_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    budget_id UUID NOT NULL REFERENCES public.society_budgets(id) ON DELETE CASCADE,
    category VARCHAR(50) NOT NULL,
    allocated_amount NUMERIC(15, 2) NOT NULL CONSTRAINT chk_allocated_positive CHECK (allocated_amount > 0),
    spent_amount NUMERIC(15, 2) NOT NULL DEFAULT 0.00 CONSTRAINT chk_spent_nonnegative CHECK (spent_amount >= 0),
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 1.5 Expense Vouchers Table
CREATE TABLE IF NOT EXISTS public.expense_vouchers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE,
    budget_line_item_id UUID REFERENCES public.budget_line_items(id) ON DELETE RESTRICT,
    vendor_id UUID REFERENCES public.vendors(id) ON DELETE SET NULL,
    requested_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    approved_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    amount NUMERIC(15, 2) NOT NULL CONSTRAINT chk_voucher_amount_positive CHECK (amount > 0),
    description TEXT NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'draft',
    rejection_reason TEXT,
    disbursed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_voucher_status CHECK (status IN ('draft', 'pending_approval', 'approved', 'disbursed', 'rejected'))
);

ALTER TABLE public.expense_vouchers 
    ADD COLUMN IF NOT EXISTS budget_line_item_id UUID REFERENCES public.budget_line_items(id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS vendor_id UUID REFERENCES public.vendors(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS requested_by UUID REFERENCES public.users(id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS approved_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS rejection_reason TEXT,
    ADD COLUMN IF NOT EXISTS disbursed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW(),
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

ALTER TABLE public.expense_vouchers DROP CONSTRAINT IF EXISTS chk_voucher_status;
ALTER TABLE public.expense_vouchers DROP CONSTRAINT IF EXISTS expense_vouchers_status_check;

UPDATE public.expense_vouchers 
SET status = 'approved' 
WHERE status NOT IN ('draft', 'pending_approval', 'approved', 'disbursed', 'rejected');

ALTER TABLE public.expense_vouchers ADD CONSTRAINT chk_voucher_status CHECK (status IN ('draft', 'pending_approval', 'approved', 'disbursed', 'rejected'));

ALTER TABLE public.ledger_transactions DROP CONSTRAINT IF EXISTS chk_tx_type;

DO $$ 
DECLARE
    col RECORD;
BEGIN 
    FOR col IN 
        SELECT column_name 
        FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'expense_vouchers' 
          AND is_nullable = 'NO'
          AND column_name NOT IN ('id', 'society_id', 'requested_by', 'amount', 'description', 'status', 'created_at', 'updated_at')
    LOOP 
        EXECUTE format('ALTER TABLE public.expense_vouchers ALTER COLUMN %I DROP NOT NULL', col.column_name);
    END LOOP;
END $$;

-- 1.6 Facility Blackouts Table
CREATE TABLE IF NOT EXISTS public.facility_blackouts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE,
    amenity_id UUID NOT NULL REFERENCES public.amenities(id) ON DELETE CASCADE,
    title VARCHAR(150) NOT NULL,
    reason TEXT NOT NULL,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'scheduled',
    created_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_blackout_times CHECK (start_time < end_time),
    CONSTRAINT chk_blackout_status CHECK (status IN ('scheduled', 'active', 'completed', 'cancelled'))
);

-- Table Grants
GRANT SELECT, INSERT, UPDATE, DELETE ON public.committee_resolutions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.committee_resolution_votes TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.society_budgets TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.budget_line_items TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.expense_vouchers TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.facility_blackouts TO authenticated;

-- 2. Permissive & Restrictive RLS Policies

ALTER TABLE public.committee_resolutions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.committee_resolutions FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_resolutions_restrictive_update ON public.committee_resolutions;
CREATE POLICY pol_resolutions_restrictive_update ON public.committee_resolutions
    AS RESTRICTIVE FOR UPDATE TO authenticated USING (false) WITH CHECK (false);

DROP POLICY IF EXISTS pol_resolutions_select_authenticated ON public.committee_resolutions;
CREATE POLICY pol_resolutions_select_authenticated ON public.committee_resolutions
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS pol_resolutions_insert_authenticated ON public.committee_resolutions;
CREATE POLICY pol_resolutions_insert_authenticated ON public.committee_resolutions
    FOR INSERT TO authenticated WITH CHECK (true);

ALTER TABLE public.committee_resolution_votes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.committee_resolution_votes FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_resolution_votes_select ON public.committee_resolution_votes;
CREATE POLICY pol_resolution_votes_select ON public.committee_resolution_votes
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS pol_resolution_votes_insert ON public.committee_resolution_votes;
DROP POLICY IF EXISTS pol_resolution_votes_restrictive_insert ON public.committee_resolution_votes;
CREATE POLICY pol_resolution_votes_restrictive_insert ON public.committee_resolution_votes
    AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (false);

ALTER TABLE public.society_budgets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.society_budgets FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_budgets_restrictive_update ON public.society_budgets;
CREATE POLICY pol_budgets_restrictive_update ON public.society_budgets
    AS RESTRICTIVE FOR UPDATE TO authenticated USING (false) WITH CHECK (false);

DROP POLICY IF EXISTS pol_budgets_select_authenticated ON public.society_budgets;
CREATE POLICY pol_budgets_select_authenticated ON public.society_budgets
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS pol_budgets_insert_authenticated ON public.society_budgets;
CREATE POLICY pol_budgets_insert_authenticated ON public.society_budgets
    FOR INSERT TO authenticated WITH CHECK (true);

ALTER TABLE public.budget_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.budget_line_items FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_budget_items_select ON public.budget_line_items;
CREATE POLICY pol_budget_items_select ON public.budget_line_items
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS pol_budget_items_insert ON public.budget_line_items;
DROP POLICY IF EXISTS pol_budget_items_restrictive_insert ON public.budget_line_items;
CREATE POLICY pol_budget_items_restrictive_insert ON public.budget_line_items
    AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (false);

ALTER TABLE public.expense_vouchers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expense_vouchers FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_vouchers_restrictive_update ON public.expense_vouchers;
CREATE POLICY pol_vouchers_restrictive_update ON public.expense_vouchers
    AS RESTRICTIVE FOR UPDATE TO authenticated USING (false) WITH CHECK (false);

DROP POLICY IF EXISTS pol_vouchers_select_authenticated ON public.expense_vouchers;
CREATE POLICY pol_vouchers_select_authenticated ON public.expense_vouchers
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS pol_vouchers_insert_authenticated ON public.expense_vouchers;
CREATE POLICY pol_vouchers_insert_authenticated ON public.expense_vouchers
    FOR INSERT TO authenticated WITH CHECK (true);

ALTER TABLE public.facility_blackouts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.facility_blackouts FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_blackouts_restrictive_update ON public.facility_blackouts;
CREATE POLICY pol_blackouts_restrictive_update ON public.facility_blackouts
    AS RESTRICTIVE FOR UPDATE TO authenticated USING (false) WITH CHECK (false);

DROP POLICY IF EXISTS pol_blackouts_select_authenticated ON public.facility_blackouts;
CREATE POLICY pol_blackouts_select_authenticated ON public.facility_blackouts
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS pol_blackouts_insert_authenticated ON public.facility_blackouts;
DROP POLICY IF EXISTS pol_blackouts_restrictive_insert ON public.facility_blackouts;
CREATE POLICY pol_blackouts_restrictive_insert ON public.facility_blackouts
    AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (false);


-- 3. BEFORE UPDATE Workflow Context Triggers

CREATE OR REPLACE FUNCTION public.fn_prevent_direct_resolution_update()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        IF current_setting('app.resolution_workflow_context', true) IS DISTINCT FROM NEW.id::text THEN
            RAISE EXCEPTION 'Direct client UPDATE on resolution status is forbidden.' USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_direct_resolution_update ON public.committee_resolutions;
CREATE TRIGGER trg_prevent_direct_resolution_update
    BEFORE UPDATE ON public.committee_resolutions
    FOR EACH ROW EXECUTE FUNCTION public.fn_prevent_direct_resolution_update();

CREATE OR REPLACE FUNCTION public.fn_prevent_direct_budget_update()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        IF current_setting('app.budget_workflow_context', true) IS DISTINCT FROM NEW.id::text THEN
            RAISE EXCEPTION 'Direct client UPDATE on budget status is forbidden.' USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_direct_budget_update ON public.society_budgets;
CREATE TRIGGER trg_prevent_direct_budget_update
    BEFORE UPDATE ON public.society_budgets
    FOR EACH ROW EXECUTE FUNCTION public.fn_prevent_direct_budget_update();

CREATE OR REPLACE FUNCTION public.fn_prevent_direct_voucher_update()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        IF current_setting('app.voucher_workflow_context', true) IS DISTINCT FROM NEW.id::text THEN
            RAISE EXCEPTION 'Direct client UPDATE on expense voucher status is forbidden.' USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_direct_voucher_update ON public.expense_vouchers;
CREATE TRIGGER trg_prevent_direct_voucher_update
    BEFORE UPDATE ON public.expense_vouchers
    FOR EACH ROW EXECUTE FUNCTION public.fn_prevent_direct_voucher_update();

CREATE OR REPLACE FUNCTION public.fn_prevent_direct_blackout_update()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        IF current_setting('app.blackout_workflow_context', true) IS DISTINCT FROM NEW.id::text THEN
            RAISE EXCEPTION 'Direct client UPDATE on blackout status is forbidden.' USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_direct_blackout_update ON public.facility_blackouts;
CREATE TRIGGER trg_prevent_direct_blackout_update
    BEFORE UPDATE ON public.facility_blackouts
    FOR EACH ROW EXECUTE FUNCTION public.fn_prevent_direct_blackout_update();


-- 4. Stored Procedures for Workflow Transitions

-- 4.1 table_resolution
CREATE OR REPLACE FUNCTION public.table_resolution(
    p_resolution_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor_id UUID;
    v_res RECORD;
    v_actor_role TEXT;
    v_payload JSONB;
BEGIN
    v_actor_id := auth.uid();
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_res 
    FROM public.committee_resolutions 
    WHERE id = p_resolution_id 
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Resolution not found.' USING ERRCODE = 'P0002';
    END IF;

    SELECT role_name INTO v_actor_role 
    FROM public.user_roles 
    WHERE user_id = v_actor_id AND society_id = v_res.society_id;

    IF v_actor_role IS NULL OR v_actor_role NOT IN ('admin', 'secretary', 'treasurer', 'executive_member', 'super_admin') THEN
        RAISE EXCEPTION 'Only active committee members can table resolutions.' USING ERRCODE = '42501';
    END IF;

    IF v_res.status != 'draft' THEN
        RAISE EXCEPTION 'Invalid transition: resolution status % cannot be tabled.', v_res.status USING ERRCODE = '22000';
    END IF;

    PERFORM set_config('app.resolution_workflow_context', p_resolution_id::text, true);

    UPDATE public.committee_resolutions
    SET status = 'voting',
        tabled_at = NOW(),
        updated_at = NOW()
    WHERE id = p_resolution_id;

    v_payload := jsonb_build_object('resolution_id', p_resolution_id, 'title', v_res.title, 'old_status', 'draft', 'new_status', 'voting');
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_res.society_id, v_actor_id, 'committee_resolutions', p_resolution_id, 'RESOLUTION_TABLED', v_payload);

    INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
    VALUES (v_res.society_id, v_res.proposed_by, 'governance', 'Resolution Tabled', 'Your resolution has been tabled for voting.', 'committee_resolutions', p_resolution_id);
END;
$$;


-- 4.2 vote_on_resolution
CREATE OR REPLACE FUNCTION public.vote_on_resolution(
    p_resolution_id UUID,
    p_vote TEXT,
    p_comments TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor_id UUID;
    v_res RECORD;
    v_actor_role TEXT;
    v_payload JSONB;
BEGIN
    v_actor_id := auth.uid();
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    IF p_vote IS NULL OR p_vote NOT IN ('for', 'against', 'abstain') THEN
        RAISE EXCEPTION 'Invalid vote choice. Must be for, against, or abstain.' USING ERRCODE = '22000';
    END IF;

    SELECT * INTO v_res 
    FROM public.committee_resolutions 
    WHERE id = p_resolution_id 
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Resolution not found.' USING ERRCODE = 'P0002';
    END IF;

    SELECT role_name INTO v_actor_role 
    FROM public.user_roles 
    WHERE user_id = v_actor_id AND society_id = v_res.society_id;

    IF v_actor_role IS NULL OR v_actor_role NOT IN ('admin', 'secretary', 'treasurer', 'executive_member', 'super_admin') THEN
        RAISE EXCEPTION 'Only active committee members can vote on resolutions.' USING ERRCODE = '42501';
    END IF;

    IF v_res.status != 'voting' THEN
        RAISE EXCEPTION 'Resolution is not open for voting (current status: %).', v_res.status USING ERRCODE = '22000';
    END IF;

    -- Record individual vote (triggers unique constraint uq_resolution_voter if duplicate)
    INSERT INTO public.committee_resolution_votes (resolution_id, voter_id, vote, comments, voted_at)
    VALUES (p_resolution_id, v_actor_id, p_vote, p_comments, NOW());

    PERFORM set_config('app.resolution_workflow_context', p_resolution_id::text, true);

    IF p_vote = 'for' THEN
        UPDATE public.committee_resolutions
        SET votes_for = votes_for + 1, updated_at = NOW()
        WHERE id = p_resolution_id;
    ELSIF p_vote = 'against' THEN
        UPDATE public.committee_resolutions
        SET votes_against = votes_against + 1, updated_at = NOW()
        WHERE id = p_resolution_id;
    END IF;

    v_payload := jsonb_build_object('resolution_id', p_resolution_id, 'vote', p_vote, 'voter_id', v_actor_id);
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_res.society_id, v_actor_id, 'committee_resolutions', p_resolution_id, 'RESOLUTION_VOTE_CAST', v_payload);
END;
$$;


-- 4.3 close_resolution_voting
CREATE OR REPLACE FUNCTION public.close_resolution_voting(
    p_resolution_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor_id UUID;
    v_res RECORD;
    v_actor_role TEXT;
    v_total_votes INT;
    v_new_status TEXT;
    v_payload JSONB;
BEGIN
    v_actor_id := auth.uid();
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_res 
    FROM public.committee_resolutions 
    WHERE id = p_resolution_id 
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Resolution not found.' USING ERRCODE = 'P0002';
    END IF;

    SELECT role_name INTO v_actor_role 
    FROM public.user_roles 
    WHERE user_id = v_actor_id AND society_id = v_res.society_id;

    IF v_actor_role IS NULL OR v_actor_role NOT IN ('admin', 'secretary', 'super_admin') THEN
        RAISE EXCEPTION 'Only society admin or secretary can close voting.' USING ERRCODE = '42501';
    END IF;

    IF v_res.status != 'voting' THEN
        RAISE EXCEPTION 'Invalid transition: resolution status % cannot be closed.', v_res.status USING ERRCODE = '22000';
    END IF;

    SELECT COUNT(*) INTO v_total_votes 
    FROM public.committee_resolution_votes 
    WHERE resolution_id = p_resolution_id;

    IF v_total_votes < v_res.quorum_required THEN
        v_new_status := 'rejected';
    ELSIF v_res.votes_for > v_res.votes_against THEN
        v_new_status := 'passed';
    ELSE
        v_new_status := 'rejected';
    END IF;

    PERFORM set_config('app.resolution_workflow_context', p_resolution_id::text, true);

    UPDATE public.committee_resolutions
    SET status = v_new_status,
        voting_closed_at = NOW(),
        passed_at = CASE WHEN v_new_status = 'passed' THEN NOW() ELSE NULL END,
        updated_at = NOW()
    WHERE id = p_resolution_id;

    v_payload := jsonb_build_object('resolution_id', p_resolution_id, 'final_status', v_new_status, 'votes_for', v_res.votes_for, 'votes_against', v_res.votes_against, 'total_votes', v_total_votes, 'quorum_required', v_res.quorum_required);
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_res.society_id, v_actor_id, 'committee_resolutions', p_resolution_id, 'RESOLUTION_VOTING_CLOSED', v_payload);

    INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
    VALUES (v_res.society_id, v_res.proposed_by, 'governance', 'Resolution Outcome: ' || initcap(v_new_status), 'Voting closed. Final status: ' || v_new_status, 'committee_resolutions', p_resolution_id);
END;
$$;


-- 4.4 submit_society_budget
CREATE OR REPLACE FUNCTION public.submit_society_budget(
    p_budget_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor_id UUID;
    v_budget RECORD;
    v_actor_role TEXT;
    v_calculated_total NUMERIC(15, 2);
    v_payload JSONB;
BEGIN
    v_actor_id := auth.uid();
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_budget 
    FROM public.society_budgets 
    WHERE id = p_budget_id 
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Budget not found.' USING ERRCODE = 'P0002';
    END IF;

    SELECT role_name INTO v_actor_role 
    FROM public.user_roles 
    WHERE user_id = v_actor_id AND society_id = v_budget.society_id;

    IF v_actor_role IS NULL OR v_actor_role NOT IN ('admin', 'treasurer', 'super_admin') THEN
        RAISE EXCEPTION 'Only society treasurer or admin can submit budget.' USING ERRCODE = '42501';
    END IF;

    IF v_budget.status != 'draft' THEN
        RAISE EXCEPTION 'Invalid transition: budget status % cannot be submitted.', v_budget.status USING ERRCODE = '22000';
    END IF;

    SELECT COALESCE(SUM(allocated_amount), 0.00) INTO v_calculated_total 
    FROM public.budget_line_items 
    WHERE budget_id = p_budget_id;

    IF v_calculated_total <= 0 THEN
        RAISE EXCEPTION 'Budget must contain at least one line item with allocated amount > 0.' USING ERRCODE = '22000';
    END IF;

    PERFORM set_config('app.budget_workflow_context', p_budget_id::text, true);

    UPDATE public.society_budgets
    SET status = 'submitted',
        total_budget = v_calculated_total,
        submitted_at = NOW(),
        updated_at = NOW()
    WHERE id = p_budget_id;

    v_payload := jsonb_build_object('budget_id', p_budget_id, 'fiscal_year', v_budget.fiscal_year, 'total_budget', v_calculated_total, 'old_status', 'draft', 'new_status', 'submitted');
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_budget.society_id, v_actor_id, 'society_budgets', p_budget_id, 'BUDGET_SUBMITTED', v_payload);
END;
$$;


-- 4.5 approve_society_budget
CREATE OR REPLACE FUNCTION public.approve_society_budget(
    p_budget_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor_id UUID;
    v_budget RECORD;
    v_actor_role TEXT;
    v_payload JSONB;
BEGIN
    v_actor_id := auth.uid();
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_budget 
    FROM public.society_budgets 
    WHERE id = p_budget_id 
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Budget not found.' USING ERRCODE = 'P0002';
    END IF;

    SELECT role_name INTO v_actor_role 
    FROM public.user_roles 
    WHERE user_id = v_actor_id AND society_id = v_budget.society_id;

    IF v_actor_role IS NULL OR v_actor_role NOT IN ('admin', 'super_admin') THEN
        RAISE EXCEPTION 'Only society admin can approve budget.' USING ERRCODE = '42501';
    END IF;

    IF v_budget.status != 'submitted' THEN
        RAISE EXCEPTION 'Invalid transition: budget status % cannot be approved.', v_budget.status USING ERRCODE = '22000';
    END IF;

    PERFORM set_config('app.budget_workflow_context', p_budget_id::text, true);

    UPDATE public.society_budgets
    SET status = 'approved',
        approved_by = v_actor_id,
        approved_at = NOW(),
        updated_at = NOW()
    WHERE id = p_budget_id;

    v_payload := jsonb_build_object('budget_id', p_budget_id, 'fiscal_year', v_budget.fiscal_year, 'approved_by', v_actor_id);
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_budget.society_id, v_actor_id, 'society_budgets', p_budget_id, 'BUDGET_APPROVED', v_payload);

    INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
    VALUES (v_budget.society_id, v_budget.prepared_by, 'budget', 'Budget Approved', 'The budget for fiscal year ' || v_budget.fiscal_year || ' has been approved.', 'society_budgets', p_budget_id);
END;
$$;


-- 4.6 approve_expense_voucher
CREATE OR REPLACE FUNCTION public.approve_expense_voucher(
    p_voucher_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor_id UUID;
    v_voucher RECORD;
    v_actor_role TEXT;
    v_payload JSONB;
BEGIN
    v_actor_id := auth.uid();
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_voucher 
    FROM public.expense_vouchers 
    WHERE id = p_voucher_id 
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Expense voucher not found.' USING ERRCODE = 'P0002';
    END IF;

    SELECT role_name INTO v_actor_role 
    FROM public.user_roles 
    WHERE user_id = v_actor_id AND society_id = v_voucher.society_id;

    IF v_actor_role IS NULL OR v_actor_role NOT IN ('admin', 'treasurer', 'super_admin') THEN
        RAISE EXCEPTION 'Only society treasurer or admin can approve expense voucher.' USING ERRCODE = '42501';
    END IF;

    IF v_voucher.status NOT IN ('draft', 'pending_approval') THEN
        RAISE EXCEPTION 'Invalid transition: voucher status % cannot be approved.', v_voucher.status USING ERRCODE = '22000';
    END IF;

    PERFORM set_config('app.voucher_workflow_context', p_voucher_id::text, true);

    UPDATE public.expense_vouchers
    SET status = 'approved',
        approved_by = v_actor_id,
        updated_at = NOW()
    WHERE id = p_voucher_id;

    v_payload := jsonb_build_object('voucher_id', p_voucher_id, 'amount', v_voucher.amount, 'approved_by', v_actor_id);
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_voucher.society_id, v_actor_id, 'expense_vouchers', p_voucher_id, 'VOUCHER_APPROVED', v_payload);
END;
$$;


-- 4.7 disburse_expense_voucher
CREATE OR REPLACE FUNCTION public.disburse_expense_voucher(
    p_voucher_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor_id UUID;
    v_voucher RECORD;
    v_line_item RECORD;
    v_actor_role TEXT;
    v_payload JSONB;
BEGIN
    v_actor_id := auth.uid();
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_voucher 
    FROM public.expense_vouchers 
    WHERE id = p_voucher_id 
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Expense voucher not found.' USING ERRCODE = 'P0002';
    END IF;

    SELECT role_name INTO v_actor_role 
    FROM public.user_roles 
    WHERE user_id = v_actor_id AND society_id = v_voucher.society_id;

    IF v_actor_role IS NULL OR v_actor_role NOT IN ('admin', 'treasurer', 'super_admin') THEN
        RAISE EXCEPTION 'Only society treasurer or admin can disburse expense voucher.' USING ERRCODE = '42501';
    END IF;

    IF v_voucher.status != 'approved' THEN
        RAISE EXCEPTION 'Invalid transition: voucher status % cannot be disbursed.', v_voucher.status USING ERRCODE = '22000';
    END IF;

    -- Lock and validate budget line item if linked
    IF v_voucher.budget_line_item_id IS NOT NULL THEN
        SELECT * INTO v_line_item 
        FROM public.budget_line_items 
        WHERE id = v_voucher.budget_line_item_id 
        FOR UPDATE;

        IF FOUND THEN
            IF v_line_item.spent_amount + v_voucher.amount > v_line_item.allocated_amount THEN
                RAISE EXCEPTION 'Disbursement exceeds budget line item allocated limit (Allocated: %, Spent: %, Voucher: %).', v_line_item.allocated_amount, v_line_item.spent_amount, v_voucher.amount USING ERRCODE = '22000';
            END IF;

            UPDATE public.budget_line_items
            SET spent_amount = spent_amount + v_voucher.amount
            WHERE id = v_voucher.budget_line_item_id;
        END IF;
    END IF;

    -- Generate financial ledger credit entry for expense disbursement
    INSERT INTO public.ledger_transactions (
        society_id, scope, transaction_type, amount, description, created_by, direction, source_voucher_id
    )
    VALUES (
        v_voucher.society_id, 'society', 'expense', v_voucher.amount, 'Expense Voucher Disbursement: ' || v_voucher.description, v_actor_id, 'credit', p_voucher_id
    );

    PERFORM set_config('app.voucher_workflow_context', p_voucher_id::text, true);

    UPDATE public.expense_vouchers
    SET status = 'disbursed',
        disbursed_at = NOW(),
        updated_at = NOW()
    WHERE id = p_voucher_id;

    v_payload := jsonb_build_object('voucher_id', p_voucher_id, 'amount', v_voucher.amount, 'disbursed_at', NOW());
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_voucher.society_id, v_actor_id, 'expense_vouchers', p_voucher_id, 'VOUCHER_DISBURSED', v_payload);

    INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
    VALUES (v_voucher.society_id, v_voucher.requested_by, 'expense', 'Expense Voucher Disbursed', 'Your expense voucher of ' || v_voucher.amount || ' has been disbursed.', 'expense_vouchers', p_voucher_id);
END;
$$;


-- 4.8 cancel_facility_blackout
CREATE OR REPLACE FUNCTION public.cancel_facility_blackout(
    p_blackout_id UUID,
    p_reason TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor_id UUID;
    v_blackout RECORD;
    v_actor_role TEXT;
    v_payload JSONB;
BEGIN
    v_actor_id := auth.uid();
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    IF p_reason IS NULL OR trim(p_reason) = '' THEN
        RAISE EXCEPTION 'Cancellation reason is required.' USING ERRCODE = '22000';
    END IF;

    SELECT * INTO v_blackout 
    FROM public.facility_blackouts 
    WHERE id = p_blackout_id 
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Facility blackout not found.' USING ERRCODE = 'P0002';
    END IF;

    SELECT role_name INTO v_actor_role 
    FROM public.user_roles 
    WHERE user_id = v_actor_id AND society_id = v_blackout.society_id;

    IF v_actor_role IS NULL OR v_actor_role NOT IN ('admin', 'super_admin') THEN
        RAISE EXCEPTION 'Only society admin can cancel facility blackout.' USING ERRCODE = '42501';
    END IF;

    IF v_blackout.status NOT IN ('scheduled', 'active') THEN
        RAISE EXCEPTION 'Invalid transition: blackout status % cannot be cancelled.', v_blackout.status USING ERRCODE = '22000';
    END IF;

    PERFORM set_config('app.blackout_workflow_context', p_blackout_id::text, true);

    UPDATE public.facility_blackouts
    SET status = 'cancelled',
        reason = v_blackout.reason || ' [Cancelled: ' || p_reason || ']',
        updated_at = NOW()
    WHERE id = p_blackout_id;

    v_payload := jsonb_build_object('blackout_id', p_blackout_id, 'old_status', v_blackout.status, 'new_status', 'cancelled', 'reason', p_reason);
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_blackout.society_id, v_actor_id, 'facility_blackouts', p_blackout_id, 'BLACKOUT_CANCELLED', v_payload);
END;
$$;


-- 4.9 add_budget_line_item
CREATE OR REPLACE FUNCTION public.add_budget_line_item(
    p_budget_id UUID,
    p_category VARCHAR,
    p_allocated_amount NUMERIC,
    p_description TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor_id UUID;
    v_budget RECORD;
    v_actor_role TEXT;
    v_line_item_id UUID;
BEGIN
    v_actor_id := auth.uid();
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_budget 
    FROM public.society_budgets 
    WHERE id = p_budget_id 
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Budget not found.' USING ERRCODE = 'P0002';
    END IF;

    IF v_budget.status <> 'draft' THEN
        RAISE EXCEPTION 'Line items can only be added to draft budgets.' USING ERRCODE = '22000';
    END IF;

    SELECT role_name INTO v_actor_role 
    FROM public.user_roles 
    WHERE user_id = v_actor_id AND society_id = v_budget.society_id;

    IF v_actor_role IS NULL OR v_actor_role NOT IN ('admin', 'treasurer', 'super_admin') THEN
        RAISE EXCEPTION 'Only society treasurer or admin can add budget line items.' USING ERRCODE = '42501';
    END IF;

    IF p_allocated_amount <= 0 THEN
        RAISE EXCEPTION 'Allocated amount must be greater than zero.' USING ERRCODE = '23514';
    END IF;

    INSERT INTO public.budget_line_items (
        budget_id, category, allocated_amount, spent_amount, description
    ) VALUES (
        p_budget_id, p_category, p_allocated_amount, 0.00, p_description
    ) RETURNING id INTO v_line_item_id;

    RETURN v_line_item_id;
END;
$$;


-- 4.10 create_facility_blackout
CREATE OR REPLACE FUNCTION public.create_facility_blackout(
    p_society_id UUID,
    p_amenity_id UUID,
    p_title VARCHAR,
    p_reason TEXT,
    p_start_time TIMESTAMPTZ,
    p_end_time TIMESTAMPTZ
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor_id UUID;
    v_actor_role TEXT;
    v_amenity RECORD;
    v_blackout_id UUID;
    v_payload JSONB;
BEGIN
    v_actor_id := auth.uid();
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    IF p_start_time >= p_end_time THEN
        RAISE EXCEPTION 'Invalid blackout time range: start_time must be before end_time.' USING ERRCODE = '23514';
    END IF;

    SELECT role_name INTO v_actor_role 
    FROM public.user_roles 
    WHERE user_id = v_actor_id AND society_id = p_society_id;

    IF v_actor_role IS NULL OR v_actor_role NOT IN ('admin', 'super_admin') THEN
        RAISE EXCEPTION 'Only society admin can create facility blackout.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_amenity 
    FROM public.amenities 
    WHERE id = p_amenity_id 
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Amenity not found.' USING ERRCODE = 'P0002';
    END IF;

    IF v_amenity.society_id <> p_society_id THEN
        RAISE EXCEPTION 'Amenity does not belong to target society.' USING ERRCODE = '42501';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.amenity_bookings
        WHERE amenity_id = p_amenity_id
          AND status IN ('pending', 'approved', 'confirmed')
          AND tstzrange(start_time, end_time) && tstzrange(p_start_time, p_end_time)
    ) THEN
        RAISE EXCEPTION 'Facility blackout overlaps with an existing active amenity booking.' USING ERRCODE = '22000';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.facility_blackouts
        WHERE amenity_id = p_amenity_id
          AND status IN ('scheduled', 'active')
          AND tstzrange(start_time, end_time) && tstzrange(p_start_time, p_end_time)
    ) THEN
        RAISE EXCEPTION 'Facility blackout overlaps with an existing active blackout window.' USING ERRCODE = '22000';
    END IF;

    INSERT INTO public.facility_blackouts (
        society_id, amenity_id, title, reason, start_time, end_time, status, created_by
    ) VALUES (
        p_society_id, p_amenity_id, p_title, p_reason, p_start_time, p_end_time, 'scheduled', v_actor_id
    ) RETURNING id INTO v_blackout_id;

    v_payload := jsonb_build_object('blackout_id', v_blackout_id, 'amenity_id', p_amenity_id, 'title', p_title, 'start_time', p_start_time, 'end_time', p_end_time);
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (p_society_id, v_actor_id, 'facility_blackouts', v_blackout_id, 'BLACKOUT_CREATED', v_payload);

    RETURN v_blackout_id;
END;
$$;


-- 5. Revoke PUBLIC execution on workflow functions and grant to authenticated
REVOKE EXECUTE ON FUNCTION public.table_resolution(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.vote_on_resolution(UUID, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.close_resolution_voting(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.submit_society_budget(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.approve_society_budget(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.approve_expense_voucher(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.disburse_expense_voucher(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.cancel_facility_blackout(UUID, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.add_budget_line_item(UUID, VARCHAR, NUMERIC, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_facility_blackout(UUID, UUID, VARCHAR, TEXT, TIMESTAMPTZ, TIMESTAMPTZ) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.table_resolution(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.vote_on_resolution(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.close_resolution_voting(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_society_budget(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_society_budget(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_expense_voucher(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.disburse_expense_voucher(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_facility_blackout(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.add_budget_line_item(UUID, VARCHAR, NUMERIC, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_facility_blackout(UUID, UUID, VARCHAR, TEXT, TIMESTAMPTZ, TIMESTAMPTZ) TO authenticated;

COMMIT;
