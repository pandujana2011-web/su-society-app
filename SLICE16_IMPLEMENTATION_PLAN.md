# SLICE 16 — COMPLETE IMPLEMENTATION PLAN

## MISSION STATEMENT

Slice 16 implements **Society Governance, Board Resolutions, Budget Approval Engine & Facility Blackout Workflows** with non-bypassable RESTRICTIVE RLS policies, BEFORE UPDATE GUC-binding triggers, transaction-local authorization context validation, `SELECT FOR UPDATE` row locking, and 8 state machine stored procedures.

Existing baseline **434 / 434 PASS** (Slices 1–15) remains **IMMUTABLE** and fully preserved.

---

## 1. PROPOSED DATABASE SCHEMA DESIGN (`database/schema_slice16.sql`)

### 1.1 New Tables & Structure

#### A. Committee Resolutions (`public.committee_resolutions`)
```sql
CREATE TABLE IF NOT EXISTS public.committee_resolutions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE,
    proposed_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    title VARCHAR(200) NOT NULL,
    description TEXT NOT NULL,
    category VARCHAR(50) NOT NULL DEFAULT 'governance',
    status VARCHAR(30) NOT NULL DEFAULT 'draft', -- draft, tabled, voting, passed, rejected, archived
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
```

#### B. Committee Resolution Votes (`public.committee_resolution_votes`)
```sql
CREATE TABLE IF NOT EXISTS public.committee_resolution_votes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    resolution_id UUID NOT NULL REFERENCES public.committee_resolutions(id) ON DELETE CASCADE,
    voter_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    vote VARCHAR(10) NOT NULL CONSTRAINT chk_vote_value CHECK (vote IN ('for', 'against', 'abstain')),
    comments TEXT,
    voted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_resolution_voter UNIQUE (resolution_id, voter_id)
);
```

#### C. Society Budgets (`public.society_budgets`)
```sql
CREATE TABLE IF NOT EXISTS public.society_budgets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE,
    fiscal_year VARCHAR(20) NOT NULL,
    title VARCHAR(150) NOT NULL,
    total_budget NUMERIC(15, 2) NOT NULL DEFAULT 0.00 CONSTRAINT chk_total_budget_nonnegative CHECK (total_budget >= 0),
    status VARCHAR(30) NOT NULL DEFAULT 'draft', -- draft, submitted, approved, active, closed
    prepared_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    approved_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    submitted_at TIMESTAMPTZ,
    approved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_society_fiscal_year UNIQUE (society_id, fiscal_year),
    CONSTRAINT chk_budget_status CHECK (status IN ('draft', 'submitted', 'approved', 'active', 'closed'))
);
```

#### D. Budget Line Items (`public.budget_line_items`)
```sql
CREATE TABLE IF NOT EXISTS public.budget_line_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    budget_id UUID NOT NULL REFERENCES public.society_budgets(id) ON DELETE CASCADE,
    category VARCHAR(50) NOT NULL,
    allocated_amount NUMERIC(15, 2) NOT NULL CONSTRAINT chk_allocated_positive CHECK (allocated_amount > 0),
    spent_amount NUMERIC(15, 2) NOT NULL DEFAULT 0.00 CONSTRAINT chk_spent_nonnegative CHECK (spent_amount >= 0),
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

#### E. Expense Vouchers (`public.expense_vouchers`)
```sql
CREATE TABLE IF NOT EXISTS public.expense_vouchers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE,
    budget_line_item_id UUID REFERENCES public.budget_line_items(id) ON DELETE RESTRICT,
    vendor_id UUID REFERENCES public.vendors(id) ON DELETE SET NULL,
    requested_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    approved_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    amount NUMERIC(15, 2) NOT NULL CONSTRAINT chk_voucher_amount_positive CHECK (amount > 0),
    description TEXT NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'draft', -- draft, pending_approval, approved, disbursed, rejected
    rejection_reason TEXT,
    disbursed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_voucher_status CHECK (status IN ('draft', 'pending_approval', 'approved', 'disbursed', 'rejected'))
);
```

#### F. Facility Blackouts (`public.facility_blackouts`)
```sql
CREATE TABLE IF NOT EXISTS public.facility_blackouts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE,
    amenity_id UUID NOT NULL REFERENCES public.amenities(id) ON DELETE CASCADE,
    title VARCHAR(150) NOT NULL,
    reason TEXT NOT NULL,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'scheduled', -- scheduled, active, completed, cancelled
    created_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_blackout_times CHECK (start_time < end_time),
    CONSTRAINT chk_blackout_status CHECK (status IN ('scheduled', 'active', 'completed', 'cancelled'))
);
```

---

## 2. RLS ARCHITECTURE & DIRECT SQL BYPASS PREVENTION

### Restrictive RLS Policies
```sql
ALTER TABLE public.committee_resolutions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.committee_resolutions FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_resolutions_restrictive_update ON public.committee_resolutions;
CREATE POLICY pol_resolutions_restrictive_update ON public.committee_resolutions
    AS RESTRICTIVE FOR UPDATE TO authenticated USING (false) WITH CHECK (false);

ALTER TABLE public.society_budgets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.society_budgets FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_budgets_restrictive_update ON public.society_budgets;
CREATE POLICY pol_budgets_restrictive_update ON public.society_budgets
    AS RESTRICTIVE FOR UPDATE TO authenticated USING (false) WITH CHECK (false);

ALTER TABLE public.expense_vouchers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expense_vouchers FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_vouchers_restrictive_update ON public.expense_vouchers;
CREATE POLICY pol_vouchers_restrictive_update ON public.expense_vouchers
    AS RESTRICTIVE FOR UPDATE TO authenticated USING (false) WITH CHECK (false);

ALTER TABLE public.facility_blackouts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.facility_blackouts FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_blackouts_restrictive_update ON public.facility_blackouts;
CREATE POLICY pol_blackouts_restrictive_update ON public.facility_blackouts
    AS RESTRICTIVE FOR UPDATE TO authenticated USING (false) WITH CHECK (false);
```

### Permissive RLS Policies for SELECT & INSERT
```sql
CREATE POLICY pol_resolutions_select ON public.committee_resolutions FOR SELECT TO authenticated USING (true);
CREATE POLICY pol_resolutions_insert ON public.committee_resolutions FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY pol_budgets_select ON public.society_budgets FOR SELECT TO authenticated USING (true);
CREATE POLICY pol_budgets_insert ON public.society_budgets FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY pol_vouchers_select ON public.expense_vouchers FOR SELECT TO authenticated USING (true);
CREATE POLICY pol_vouchers_insert ON public.expense_vouchers FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY pol_blackouts_select ON public.facility_blackouts FOR SELECT TO authenticated USING (true);
CREATE POLICY pol_blackouts_insert ON public.facility_blackouts FOR INSERT TO authenticated WITH CHECK (true);
```

### GUC-Binding Triggers

```sql
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
```

---

## 3. STORED PROCEDURES FOR WORKFLOW STATE MACHINES

1. `public.table_resolution(p_resolution_id UUID)`
2. `public.vote_on_resolution(p_resolution_id UUID, p_vote TEXT, p_comments TEXT)`
3. `public.close_resolution_voting(p_resolution_id UUID)`
4. `public.submit_society_budget(p_budget_id UUID)`
5. `public.approve_society_budget(p_budget_id UUID)`
6. `public.approve_expense_voucher(p_voucher_id UUID)`
7. `public.disburse_expense_voucher(p_voucher_id UUID)`
8. `public.cancel_facility_blackout(p_blackout_id UUID, p_reason TEXT)`

All procedures will be defined with:
* `SECURITY DEFINER`
* `SET search_path = public, pg_temp`
* Privileges `REVOKED FROM PUBLIC`
* Privileges `GRANTED TO authenticated`

---

## 4. VERIFICATION SUITE DESIGN (`database/verify_slice16.sql`)

* 29 Genuine SQL Test Assertions (Assertions 1–29) covering:
  - Resolution voting lifecycle, committee role enforcement, quorum validation.
  - Budget submission, line item validation, approval workflows.
  - Expense voucher authorization, line item budget balance checks, disbursement & ledger entry generation.
  - Facility blackout scheduling & amenity booking overlap prevention.
  - RESTRICTIVE RLS bypass blocking & spoofed GUC rejection.
  - Row-locking (`FOR UPDATE`), atomicity rollback, and catalog audits.

---

## 5. REGRESSION & MASTER RUNNER (`scratch/run_all16.ps1`)

* Phase A: Execute `scratch/run_all15.ps1` (Baseline: **434/434 PASS**)
* Phase B: Execute `database/schema_slice16.sql`
* Phase C: Execute `database/verify_slice16.sql` (Assertions: **29/29 PASS**)
* Phase D: Cumulative Final Report: **463 / 463 PASS (100%)**

---

## 6. FILE CHANGE PLAN

| File | Status | Action |
| :--- | :--- | :--- |
| `database/schema_slice16.sql` | Proposed | Create DDL, RESTRICTIVE RLS, triggers & 8 stored procedures |
| `database/verify_slice16.sql` | Proposed | Create 29 test assertions |
| `scratch/run_all16.ps1` | Proposed | Create master cumulative runner |
| `SLICE16_PRE_IMPLEMENTATION_AUDIT.md` | Created | Pre-implementation security audit |
| `SLICE16_IMPLEMENTATION_PLAN.md` | Created | Implementation plan document |
| Slices 1–15 files | Locked | UNTOUCHED |

---

## 7. ABSOLUTE APPROVAL GATE

```text
SLICE 16 IMPLEMENTATION STATUS: NOT AUTHORIZED

Implementation: NOT STARTED

Database modification: NOT STARTED

Application modification: NOT STARTED

Slices 1–15: LOCKED / UNTOUCHED

Current baseline: 434/434 PASS

Awaiting explicit user approval after plan review.
```
