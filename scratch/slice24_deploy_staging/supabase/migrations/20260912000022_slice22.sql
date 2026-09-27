-- ============================================================================
-- SU SOCIETY APP — SLICE 22 SCHEMA DEFINITION
-- Society Rule Violation, Fine Ledger Posting & Dispute Management System
-- Revision 2.0 Hardened Specification (Plan V2 Micro-Remediated)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. HELPER & VALIDATION FUNCTIONS (IMMUTABLE / STABLE)
-- ----------------------------------------------------------------------------

-- Validate Evidence URLs JSONB Array with Strict Scheme & Type Enforcement
CREATE OR REPLACE FUNCTION public.fn_is_valid_evidence_urls(p_urls JSONB)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_elem JSONB;
    v_str TEXT;
BEGIN
    IF p_urls IS NULL THEN
        RETURN TRUE;
    END IF;
    
    -- Must be a JSON array
    IF jsonb_typeof(p_urls) != 'array' THEN
        RETURN FALSE;
    END IF;
    
    -- Maximum 10 evidence items
    IF jsonb_array_length(p_urls) > 10 THEN
        RETURN FALSE;
    END IF;

    -- Validate each element is a string beginning with http:// or https://
    FOR v_elem IN SELECT * FROM jsonb_array_elements(p_urls)
    LOOP
        IF jsonb_typeof(v_elem) != 'string' THEN
            RETURN FALSE;
        END IF;
        v_str := jsonb_extract_path_text(v_elem);
        IF v_str IS NULL OR (v_str NOT LIKE 'http://%' AND v_str NOT LIKE 'https://%') THEN
            RETURN FALSE;
        END IF;
    END LOOP;
    
    RETURN TRUE;
END;
$$;

-- ----------------------------------------------------------------------------
-- 1.5 LEGACY SCHEMA RECONCILIATION & CLEANUP (SLICE 9 / SLICE 13 RECONCILIATION)
-- ----------------------------------------------------------------------------

-- Drop legacy Slice 9 / Slice 13 triggers on public.rule_violations
DROP TRIGGER IF EXISTS trg_rule_violations_updated_at ON public.rule_violations;
DROP TRIGGER IF EXISTS trg_rule_violations_force_reported_by ON public.rule_violations;
DROP TRIGGER IF EXISTS trg_prevent_direct_violation_update ON public.rule_violations;
DROP TRIGGER IF EXISTS trg_audit_rule_violations ON public.rule_violations;
DROP TRIGGER IF EXISTS trg_notify_violation_insert ON public.rule_violations;
DROP TRIGGER IF EXISTS trg_notify_violation_update ON public.rule_violations;

-- Drop legacy Slice 9 functions
DROP FUNCTION IF EXISTS public.fn_rule_violations_force_reported_by();
DROP FUNCTION IF EXISTS public.fn_prevent_direct_violation_update();
DROP FUNCTION IF EXISTS public.fn_transition_violation_state(UUID, VARCHAR, NUMERIC);

-- Drop legacy Slice 9 RLS policies
DROP POLICY IF EXISTS pol_violations_admin ON public.rule_violations;
DROP POLICY IF EXISTS pol_violations_select_owner ON public.rule_violations;
DROP POLICY IF EXISTS pol_violations_select_tenant ON public.rule_violations;
DROP POLICY IF EXISTS pol_violations_insert_resident ON public.rule_violations;

-- Reconcile legacy public.rule_violations table if it pre-exists from Slice 9
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'rule_violations') THEN
        -- 1. Add/rename missing columns conditionally
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'rule_violations' AND column_name = 'reporter_id') THEN
            IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'rule_violations' AND column_name = 'reported_by') THEN
                ALTER TABLE public.rule_violations RENAME COLUMN reported_by TO reporter_id;
            ELSE
                ALTER TABLE public.rule_violations ADD COLUMN reporter_id UUID REFERENCES public.users(id) ON DELETE RESTRICT;
            END IF;
        END IF;

        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'rule_violations' AND column_name = 'subject_user_id') THEN
            ALTER TABLE public.rule_violations ADD COLUMN subject_user_id UUID REFERENCES public.users(id) ON DELETE RESTRICT;
        END IF;

        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'rule_violations' AND column_name = 'violation_category') THEN
            IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'rule_violations' AND column_name = 'violation_type') THEN
                ALTER TABLE public.rule_violations RENAME COLUMN violation_type TO violation_category;
            ELSE
                ALTER TABLE public.rule_violations ADD COLUMN violation_category VARCHAR(64);
            END IF;
        END IF;

        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'rule_violations' AND column_name = 'evidence_urls') THEN
            ALTER TABLE public.rule_violations ADD COLUMN evidence_urls JSONB DEFAULT '[]'::jsonb;
        END IF;

        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'rule_violations' AND column_name = 'reported_at') THEN
            ALTER TABLE public.rule_violations ADD COLUMN reported_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP;
        END IF;

        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'rule_violations' AND column_name = 'reviewed_at') THEN
            ALTER TABLE public.rule_violations ADD COLUMN reviewed_at TIMESTAMPTZ;
        END IF;

        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'rule_violations' AND column_name = 'reviewed_by') THEN
            ALTER TABLE public.rule_violations ADD COLUMN reviewed_by UUID REFERENCES public.users(id);
        END IF;

        -- 2. Data backfill for legacy rows
        UPDATE public.rule_violations
        SET reporter_id = COALESCE(reporter_id, (SELECT id FROM public.users LIMIT 1))
        WHERE reporter_id IS NULL;

        UPDATE public.rule_violations
        SET subject_user_id = COALESCE(subject_user_id, reporter_id)
        WHERE subject_user_id IS NULL;

        UPDATE public.rule_violations
        SET violation_category = CASE
            WHEN violation_category IN ('noise', 'parking_unauthorized', 'trash_disposal', 'unauthorized_alteration', 'common_area_damage', 'pet_policy') THEN violation_category
            ELSE 'other'
        END
        WHERE violation_category IS NOT NULL;

        UPDATE public.rule_violations
        SET violation_category = 'other'
        WHERE violation_category IS NULL;

        UPDATE public.rule_violations
        SET status = CASE
            WHEN status = 'penalized' THEN 'penalty_assessed'
            WHEN status = 'resolved' THEN 'financially_posted'
            WHEN status IN ('reported', 'under_review', 'dismissed', 'penalty_assessed', 'disputed', 'dispute_upheld', 'dispute_reversed', 'financially_posted') THEN status
            ELSE 'reported'
        END;

        UPDATE public.rule_violations
        SET reported_at = COALESCE(created_at, CURRENT_TIMESTAMP)
        WHERE reported_at IS NULL;

        -- 3. Drop legacy constraints if present
        ALTER TABLE public.rule_violations DROP CONSTRAINT IF EXISTS chk_violation_status;
        ALTER TABLE public.rule_violations DROP CONSTRAINT IF EXISTS chk_violation_penalty;

        -- 4. Apply NOT NULL constraints
        ALTER TABLE public.rule_violations ALTER COLUMN reporter_id SET NOT NULL;
        ALTER TABLE public.rule_violations ALTER COLUMN subject_user_id SET NOT NULL;
        ALTER TABLE public.rule_violations ALTER COLUMN violation_category SET NOT NULL;
        ALTER TABLE public.rule_violations ALTER COLUMN reported_at SET NOT NULL;

        -- 5. Drop legacy columns if present
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'rule_violations' AND column_name = 'penalty_amount') THEN
            ALTER TABLE public.rule_violations DROP COLUMN penalty_amount;
        END IF;
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'rule_violations' AND column_name = 'ledger_transaction_id') THEN
            ALTER TABLE public.rule_violations DROP COLUMN ledger_transaction_id;
        END IF;

        -- 6. Ensure chk_different_reporter_subject constraint exists
        IF NOT EXISTS (SELECT 1 FROM information_schema.table_constraints WHERE table_schema = 'public' AND table_name = 'rule_violations' AND constraint_name = 'chk_different_reporter_subject') THEN
            ALTER TABLE public.rule_violations ADD CONSTRAINT chk_different_reporter_subject CHECK (reporter_id != subject_user_id);
        END IF;
    END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 2. TABLE DEFINITIONS
-- ----------------------------------------------------------------------------

-- 1. Rule Violations Master Table
CREATE TABLE IF NOT EXISTS public.rule_violations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    property_id UUID NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
    reporter_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    subject_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    violation_category VARCHAR(64) NOT NULL CHECK (violation_category IN ('noise', 'parking_unauthorized', 'trash_disposal', 'unauthorized_alteration', 'common_area_damage', 'pet_policy', 'other')),
    description TEXT NOT NULL CHECK (length(trim(description)) >= 10 AND length(description) <= 2000),
    evidence_urls JSONB DEFAULT '[]'::jsonb CHECK (public.fn_is_valid_evidence_urls(evidence_urls)),
    status VARCHAR(32) NOT NULL DEFAULT 'reported' CHECK (status IN ('reported', 'under_review', 'dismissed', 'penalty_assessed', 'disputed', 'dispute_upheld', 'dispute_reversed', 'financially_posted')),
    reported_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    reviewed_at TIMESTAMPTZ,
    reviewed_by UUID REFERENCES public.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_different_reporter_subject CHECK (reporter_id != subject_user_id)
);

-- 2. Violation Penalties Table
CREATE TABLE IF NOT EXISTS public.violation_penalties (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    violation_id UUID NOT NULL UNIQUE REFERENCES public.rule_violations(id) ON DELETE RESTRICT,
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    penalty_amount NUMERIC(12, 2) NOT NULL CHECK (penalty_amount > 0 AND penalty_amount <= 50000.00),
    assessed_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    assessed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    appeal_deadline TIMESTAMPTZ NOT NULL,
    is_posted BOOLEAN NOT NULL DEFAULT FALSE,
    posted_at TIMESTAMPTZ,
    charge_id UUID REFERENCES public.maintenance_charges(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 3. Violation Disputes Table
CREATE TABLE IF NOT EXISTS public.violation_disputes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    violation_id UUID NOT NULL UNIQUE REFERENCES public.rule_violations(id) ON DELETE RESTRICT,
    penalty_id UUID NOT NULL UNIQUE REFERENCES public.violation_penalties(id) ON DELETE RESTRICT,
    disputed_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    dispute_reason TEXT NOT NULL CHECK (length(trim(dispute_reason)) >= 10 AND length(dispute_reason) <= 2000),
    disputed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    resolution_status VARCHAR(32) NOT NULL DEFAULT 'pending' CHECK (resolution_status IN ('pending', 'upheld', 'reversed')),
    resolved_by UUID REFERENCES public.users(id),
    resolved_at TIMESTAMPTZ,
    resolution_notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 4. Violation Rate Limits Table
CREATE TABLE IF NOT EXISTS public.violation_rate_limits (
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    reporter_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    reports_count INT NOT NULL DEFAULT 1,
    window_start TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (society_id, reporter_id)
);

-- 5. Violation Audit Logs Table (Append-Only)
-- Note: actor_id is UUID NOT NULL without FK constraint to support background worker sentinel UUID 00000000-0000-0000-0000-000000000000
CREATE TABLE IF NOT EXISTS public.violation_audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    violation_id UUID NOT NULL REFERENCES public.rule_violations(id) ON DELETE RESTRICT,
    actor_id UUID NOT NULL,
    event_type VARCHAR(64) NOT NULL,
    old_status VARCHAR(32),
    new_status VARCHAR(32),
    details JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for Query & Concurrency Performance
CREATE INDEX IF NOT EXISTS idx_rule_violations_society_status ON public.rule_violations(society_id, status);
CREATE INDEX IF NOT EXISTS idx_rule_violations_property ON public.rule_violations(property_id);
CREATE INDEX IF NOT EXISTS idx_rule_violations_subject ON public.rule_violations(subject_user_id);
CREATE INDEX IF NOT EXISTS idx_violation_penalties_deadline ON public.violation_penalties(appeal_deadline, is_posted);
CREATE INDEX IF NOT EXISTS idx_violation_audit_logs_violation ON public.violation_audit_logs(violation_id);

-- ----------------------------------------------------------------------------
-- 3. HARDENED RPC ROUTINES
-- ----------------------------------------------------------------------------

-- RPC 1: Report Rule Violation
CREATE OR REPLACE FUNCTION public.fn_report_rule_violation(
    p_property_id UUID,
    p_subject_user_id UUID,
    p_category VARCHAR,
    p_description TEXT,
    p_evidence_urls JSONB DEFAULT '[]'::jsonb
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_caller_id UUID;
    v_caller_society UUID;
    v_prop_society UUID;
    v_violation_id UUID;
    v_window_start TIMESTAMPTZ;
    v_count INT;
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Authentication Required';
    END IF;

    -- Reporter cannot be subject
    IF v_caller_id = p_subject_user_id THEN
        RAISE EXCEPTION 'Invalid Operation: Cannot report self for rule violation';
    END IF;

    -- Validate Property & Society Scope
    SELECT society_id INTO v_prop_society FROM public.properties WHERE id = p_property_id;
    IF v_prop_society IS NULL THEN
        RAISE EXCEPTION 'Property Not Found';
    END IF;

    v_caller_society := public.get_user_society_id(v_caller_id);
    IF v_caller_society IS NULL OR v_caller_society != v_prop_society THEN
        RAISE EXCEPTION 'Access Denied: Cross-society violation reporting blocked';
    END IF;

    -- Atomic Anti-Spam Rate Limit (First-Row Creation Race Fix)
    INSERT INTO public.violation_rate_limits (society_id, reporter_id, reports_count, window_start)
    VALUES (v_caller_society, v_caller_id, 0, CURRENT_TIMESTAMP)
    ON CONFLICT (society_id, reporter_id) DO NOTHING;

    PERFORM 1 FROM public.violation_rate_limits 
    WHERE society_id = v_caller_society AND reporter_id = v_caller_id 
    FOR UPDATE;

    SELECT window_start, reports_count INTO v_window_start, v_count
    FROM public.violation_rate_limits
    WHERE society_id = v_caller_society AND reporter_id = v_caller_id;

    IF v_window_start IS NULL OR (CURRENT_TIMESTAMP - v_window_start) > INTERVAL '1 hour' THEN
        UPDATE public.violation_rate_limits 
        SET reports_count = 1, window_start = CURRENT_TIMESTAMP
        WHERE society_id = v_caller_society AND reporter_id = v_caller_id;
    ELSE
        IF v_count >= 3 THEN
            RAISE EXCEPTION 'Rate Limit Exceeded: Maximum 3 rule violation reports permitted per hour';
        END IF;
        UPDATE public.violation_rate_limits 
        SET reports_count = reports_count + 1 
        WHERE society_id = v_caller_society AND reporter_id = v_caller_id;
    END IF;

    -- Create Violation Record
    INSERT INTO public.rule_violations (
        society_id, property_id, reporter_id, subject_user_id, violation_category, description, evidence_urls, status
    ) VALUES (
        v_caller_society, p_property_id, v_caller_id, p_subject_user_id, p_category, p_description, p_evidence_urls, 'reported'
    ) RETURNING id INTO v_violation_id;

    -- Log Audit Event
    INSERT INTO public.violation_audit_logs (
        society_id, violation_id, actor_id, event_type, old_status, new_status, details
    ) VALUES (
        v_caller_society, v_violation_id, v_caller_id, 'VIOLATION_REPORTED', NULL, 'reported', 
        jsonb_build_object('category', p_category, 'property_id', p_property_id, 'subject_id', p_subject_user_id)
    );

    RETURN v_violation_id;
END;
$$;

-- RPC 2: Review Rule Violation (Dismiss or Assess Penalty)
CREATE OR REPLACE FUNCTION public.fn_review_rule_violation(
    p_violation_id UUID,
    p_action VARCHAR,
    p_penalty_amount NUMERIC DEFAULT NULL,
    p_notes TEXT DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_caller_id UUID;
    v_caller_society UUID;
    v_violation public.rule_violations%ROWTYPE;
    v_penalty_id UUID;
    v_deadline TIMESTAMPTZ;
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Authentication Required';
    END IF;

    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access Denied: Administrative authority required';
    END IF;

    v_caller_society := public.get_user_society_id(v_caller_id);

    -- Lock Violation Row (Rank 3)
    SELECT * INTO v_violation FROM public.rule_violations WHERE id = p_violation_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Violation Record Not Found';
    END IF;

    IF v_violation.society_id != v_caller_society THEN
        RAISE EXCEPTION 'Access Denied: Cross-society violation review blocked';
    END IF;

    IF v_violation.status NOT IN ('reported', 'under_review') THEN
        RAISE EXCEPTION 'Invalid State Transition: Violation is not in reviewable status';
    END IF;

    IF p_action = 'dismiss' THEN
        UPDATE public.rule_violations
        SET status = 'dismissed', reviewed_at = CURRENT_TIMESTAMP, reviewed_by = v_caller_id, updated_at = CURRENT_TIMESTAMP
        WHERE id = p_violation_id;

        INSERT INTO public.violation_audit_logs (
            society_id, violation_id, actor_id, event_type, old_status, new_status, details
        ) VALUES (
            v_caller_society, p_violation_id, v_caller_id, 'VIOLATION_DISMISSED', v_violation.status, 'dismissed',
            jsonb_build_object('notes', p_notes)
        );

        RETURN 'dismissed';

    ELSIF p_action = 'assess_penalty' THEN
        IF p_penalty_amount IS NULL OR p_penalty_amount <= 0 OR p_penalty_amount > 50000.00 THEN
            RAISE EXCEPTION 'Invalid Penalty Amount: Amount must be positive and <= 50000.00';
        END IF;

        -- Mandatory 7-calendar-day (168-hour) appeal window
        v_deadline := CURRENT_TIMESTAMP + INTERVAL '7 days';

        UPDATE public.rule_violations
        SET status = 'penalty_assessed', reviewed_at = CURRENT_TIMESTAMP, reviewed_by = v_caller_id, updated_at = CURRENT_TIMESTAMP
        WHERE id = p_violation_id;

        -- Insert Penalty Record (Rank 4)
        INSERT INTO public.violation_penalties (
            violation_id, society_id, penalty_amount, assessed_by, assessed_at, appeal_deadline, is_posted
        ) VALUES (
            p_violation_id, v_caller_society, p_penalty_amount, v_caller_id, CURRENT_TIMESTAMP, v_deadline, FALSE
        ) RETURNING id INTO v_penalty_id;

        INSERT INTO public.violation_audit_logs (
            society_id, violation_id, actor_id, event_type, old_status, new_status, details
        ) VALUES (
            v_caller_society, p_violation_id, v_caller_id, 'PENALTY_ASSESSED', v_violation.status, 'penalty_assessed',
            jsonb_build_object('penalty_id', v_penalty_id, 'amount', p_penalty_amount, 'appeal_deadline', v_deadline)
        );

        RETURN 'penalty_assessed';
    ELSE
        RAISE EXCEPTION 'Invalid Review Action: Must be dismiss or assess_penalty';
    END IF;
END;
$$;

-- RPC 3: Dispute Rule Violation (Resident Appeal)
CREATE OR REPLACE FUNCTION public.fn_dispute_rule_violation(
    p_violation_id UUID,
    p_dispute_reason TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_caller_id UUID;
    v_violation public.rule_violations%ROWTYPE;
    v_penalty public.violation_penalties%ROWTYPE;
    v_dispute_id UUID;
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Authentication Required';
    END IF;

    -- Lock Violation Row (Rank 3)
    SELECT * INTO v_violation FROM public.rule_violations WHERE id = p_violation_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Violation Record Not Found';
    END IF;

    -- Verifies caller is subject resident
    IF v_violation.subject_user_id != v_caller_id THEN
        RAISE EXCEPTION 'Access Denied: Only the subject resident may dispute a violation penalty';
    END IF;

    IF v_violation.status != 'penalty_assessed' THEN
        RAISE EXCEPTION 'Invalid State Transition: Violation is not in penalty_assessed status';
    END IF;

    -- Lock Penalty Row (Rank 4)
    SELECT * INTO v_penalty FROM public.violation_penalties WHERE violation_id = p_violation_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Penalty Record Not Found';
    END IF;

    -- Validate Appeal Window (Must be <= appeal_deadline)
    IF CURRENT_TIMESTAMP > v_penalty.appeal_deadline THEN
        RAISE EXCEPTION 'Appeal Deadline Expired: Dispute submission window has closed';
    END IF;

    IF v_penalty.is_posted THEN
        RAISE EXCEPTION 'Invalid Operation: Cannot dispute penalty that has already been financially posted';
    END IF;

    -- Update Violation Status to disputed
    UPDATE public.rule_violations
    SET status = 'disputed', updated_at = CURRENT_TIMESTAMP
    WHERE id = p_violation_id;

    -- Insert Dispute Record (Rank 5)
    INSERT INTO public.violation_disputes (
        violation_id, penalty_id, disputed_by, dispute_reason, disputed_at, resolution_status
    ) VALUES (
        p_violation_id, v_penalty.id, v_caller_id, p_dispute_reason, CURRENT_TIMESTAMP, 'pending'
    ) RETURNING id INTO v_dispute_id;

    INSERT INTO public.violation_audit_logs (
        society_id, violation_id, actor_id, event_type, old_status, new_status, details
    ) VALUES (
        v_violation.society_id, p_violation_id, v_caller_id, 'VIOLATION_DISPUTED', 'penalty_assessed', 'disputed',
        jsonb_build_object('dispute_id', v_dispute_id, 'reason', p_dispute_reason)
    );

    RETURN v_dispute_id;
END;
$$;

-- RPC 4: Resolve Violation Dispute (Committee Decision — Corrected Lock Order: Rank 3 -> Rank 5)
CREATE OR REPLACE FUNCTION public.fn_resolve_violation_dispute(
    p_dispute_id UUID,
    p_resolution VARCHAR,
    p_notes TEXT DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_caller_id UUID;
    v_caller_society UUID;
    v_dispute public.violation_disputes%ROWTYPE;
    v_violation public.rule_violations%ROWTYPE;
    v_new_status VARCHAR;
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Authentication Required';
    END IF;

    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access Denied: Administrative authority required';
    END IF;

    v_caller_society := public.get_user_society_id(v_caller_id);

    -- Lock Violation Row FIRST (Rank 3)
    SELECT * INTO v_violation FROM public.rule_violations WHERE id = (
        SELECT violation_id FROM public.violation_disputes WHERE id = p_dispute_id
    ) FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Violation Record Not Found';
    END IF;

    IF v_violation.society_id != v_caller_society THEN
        RAISE EXCEPTION 'Access Denied: Cross-society dispute resolution blocked';
    END IF;

    -- Lock Dispute Row SECOND (Rank 5)
    SELECT * INTO v_dispute FROM public.violation_disputes WHERE id = p_dispute_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Dispute Record Not Found';
    END IF;

    IF v_dispute.resolution_status != 'pending' THEN
        RAISE EXCEPTION 'Invalid State Transition: Dispute is already resolved';
    END IF;

    IF p_resolution = 'upheld' THEN
        v_new_status := 'dispute_upheld';
        UPDATE public.violation_disputes
        SET resolution_status = 'upheld', resolved_by = v_caller_id, resolved_at = CURRENT_TIMESTAMP, resolution_notes = p_notes
        WHERE id = p_dispute_id;
    ELSIF p_resolution = 'reversed' THEN
        v_new_status := 'dispute_reversed';
        UPDATE public.violation_disputes
        SET resolution_status = 'reversed', resolved_by = v_caller_id, resolved_at = CURRENT_TIMESTAMP, resolution_notes = p_notes
        WHERE id = p_dispute_id;
    ELSE
        RAISE EXCEPTION 'Invalid Resolution: Must be upheld or reversed';
    END IF;

    UPDATE public.rule_violations
    SET status = v_new_status, updated_at = CURRENT_TIMESTAMP
    WHERE id = v_dispute.violation_id;

    INSERT INTO public.violation_audit_logs (
        society_id, violation_id, actor_id, event_type, old_status, new_status, details
    ) VALUES (
        v_caller_society, v_dispute.violation_id, v_caller_id, 'DISPUTE_RESOLVED', 'disputed', v_new_status,
        jsonb_build_object('dispute_id', p_dispute_id, 'resolution', p_resolution, 'notes', p_notes)
    );

    RETURN v_new_status;
END;
$$;

-- RPC 5A: Internal Post Violation Penalty Routine (Core Financial Mutation with Correct Lock Hierarchy)
CREATE OR REPLACE FUNCTION public.fn_post_violation_penalty_internal(
    p_violation_id UUID,
    p_actor_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_violation public.rule_violations%ROWTYPE;
    v_penalty public.violation_penalties%ROWTYPE;
    v_charge_id UUID;
    v_ledger_id UUID;
    v_idempotency_key VARCHAR;
BEGIN
    IF p_actor_id IS NULL THEN
        RAISE EXCEPTION 'Actor ID Required';
    END IF;

    -- Preview Violation Row to obtain property_id
    SELECT * INTO v_violation FROM public.rule_violations WHERE id = p_violation_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Violation Record Not Found';
    END IF;

    -- MANDATORY STEP 1: Acquire Property Row Lock FIRST (Rank 1 — Slice 2 Financial Serialization Anchor)
    PERFORM 1 FROM public.properties WHERE id = v_violation.property_id FOR UPDATE;

    -- MANDATORY STEP 2: Lock Violation Row SECOND (Rank 3)
    SELECT * INTO v_violation FROM public.rule_violations WHERE id = p_violation_id FOR UPDATE;

    -- MANDATORY STEP 3: Lock Penalty Row THIRD (Rank 4)
    SELECT * INTO v_penalty FROM public.violation_penalties WHERE violation_id = p_violation_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Penalty Record Not Found';
    END IF;

    IF v_penalty.is_posted THEN
        RAISE EXCEPTION 'Duplicate Operation: Penalty has already been posted to financial ledger';
    END IF;

    -- Precondition Validation: Must be penalty_assessed (with expired deadline) OR dispute_upheld
    IF v_violation.status = 'penalty_assessed' THEN
        IF CURRENT_TIMESTAMP <= v_penalty.appeal_deadline THEN
            RAISE EXCEPTION 'Posting Blocked: Appeal window is still active. Fine cannot be posted until appeal deadline expires';
        END IF;
    ELSIF v_violation.status = 'dispute_upheld' THEN
        -- Allowed to post after dispute upheld
        NULL;
    ELSE
        RAISE EXCEPTION 'Posting Blocked: Violation is not in a postable financial status';
    END IF;

    -- Create Maintenance Charge Record (Rank 6)
    INSERT INTO public.maintenance_charges (
        society_id, policy_id, property_id, unit_id, billing_period, amount, status, billing_basis_snapshot, created_by
    ) VALUES (
        v_violation.society_id, NULL, v_violation.property_id, NULL, to_char(CURRENT_DATE, 'YYYY-MM'), 
        v_penalty.penalty_amount, 'posted', jsonb_build_object('basis', 'fine_penalty', 'penalty_id', v_penalty.id), p_actor_id
    ) RETURNING id INTO v_charge_id;

    -- Server-Controlled Idempotency Key
    v_idempotency_key := 'violation_penalty:' || v_penalty.id::text;

    -- Create Ledger Transaction Record (Rank 7)
    INSERT INTO public.ledger_transactions (
        society_id, scope, property_id, unit_id, amount, direction, transaction_type, source_charge_id, description, created_by
    ) VALUES (
        v_violation.society_id, 'property', v_violation.property_id, NULL, v_penalty.penalty_amount, 'debit', 'charge', v_charge_id, 'Fine Penalty for Violation ' || v_violation.id::text, p_actor_id
    ) RETURNING id INTO v_ledger_id;

    -- Update Penalty & Violation Status
    UPDATE public.violation_penalties
    SET is_posted = TRUE, posted_at = CURRENT_TIMESTAMP, charge_id = v_charge_id
    WHERE id = v_penalty.id;

    UPDATE public.rule_violations
    SET status = 'financially_posted', updated_at = CURRENT_TIMESTAMP
    WHERE id = p_violation_id;

    -- Log Financial Audit Event
    INSERT INTO public.violation_audit_logs (
        society_id, violation_id, actor_id, event_type, old_status, new_status, details
    ) VALUES (
        v_violation.society_id, p_violation_id, p_actor_id, 'PENALTY_FINANCIALLY_POSTED', v_violation.status, 'financially_posted',
        jsonb_build_object('penalty_id', v_penalty.id, 'charge_id', v_charge_id, 'ledger_id', v_ledger_id, 'amount', v_penalty.penalty_amount)
    );

    RETURN v_charge_id;
END;
$$;

-- RPC 5B: Post Violation Penalty Public Wrapper (JWT Admin Authenticated)
CREATE OR REPLACE FUNCTION public.fn_post_violation_penalty(
    p_violation_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_caller_id UUID;
    v_caller_society UUID;
    v_violation_society UUID;
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Authentication Required';
    END IF;

    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access Denied: Administrative authority required';
    END IF;

    v_caller_society := public.get_user_society_id(v_caller_id);

    SELECT society_id INTO v_violation_society FROM public.rule_violations WHERE id = p_violation_id;
    IF v_violation_society IS NULL THEN
        RAISE EXCEPTION 'Violation Record Not Found';
    END IF;

    IF v_violation_society != v_caller_society THEN
        RAISE EXCEPTION 'Access Denied: Cross-society penalty posting blocked';
    END IF;

    RETURN public.fn_post_violation_penalty_internal(p_violation_id, v_caller_id);
END;
$$;

-- RPC 6: Process Expired Violation Appeals (Background Worker Routine with Structured Observability)
CREATE OR REPLACE FUNCTION public.process_expired_violation_appeals()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_rec RECORD;
    v_processed_count INT := 0;
    v_sentinel_actor UUID := '00000000-0000-0000-0000-000000000000'::uuid;
    v_sqlstate TEXT;
    v_sqlerrm TEXT;
BEGIN
    FOR v_rec IN 
        SELECT p.violation_id, v.society_id
        FROM public.violation_penalties p
        JOIN public.rule_violations v ON v.id = p.violation_id
        WHERE p.is_posted = FALSE 
          AND v.status = 'penalty_assessed'
          AND p.appeal_deadline < CURRENT_TIMESTAMP
        ORDER BY p.appeal_deadline ASC
        LIMIT 50
    LOOP
        BEGIN
            PERFORM public.fn_post_violation_penalty_internal(v_rec.violation_id, v_sentinel_actor);
            v_processed_count := v_processed_count + 1;
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS 
                v_sqlstate = RETURNED_SQLSTATE,
                v_sqlerrm = MESSAGE_TEXT;
            
            INSERT INTO public.violation_audit_logs (
                society_id, violation_id, actor_id, event_type, old_status, new_status, details
            ) VALUES (
                v_rec.society_id, v_rec.violation_id, v_sentinel_actor, 'WORKER_POSTING_ERROR', 'penalty_assessed', 'penalty_assessed',
                jsonb_build_object('sqlstate', v_sqlstate, 'message', v_sqlerrm, 'penalty_id', v_rec.violation_id)
            );
        END;
    END LOOP;

    RETURN v_processed_count;
END;
$$;

-- ----------------------------------------------------------------------------
-- 4. ROW LEVEL SECURITY (RLS) & PRIVILEGE ENFORCEMENT
-- ----------------------------------------------------------------------------

ALTER TABLE public.rule_violations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rule_violations FORCE ROW LEVEL SECURITY;

ALTER TABLE public.violation_penalties ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.violation_penalties FORCE ROW LEVEL SECURITY;

ALTER TABLE public.violation_disputes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.violation_disputes FORCE ROW LEVEL SECURITY;

ALTER TABLE public.violation_rate_limits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.violation_rate_limits FORCE ROW LEVEL SECURITY;

ALTER TABLE public.violation_audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.violation_audit_logs FORCE ROW LEVEL SECURITY;

-- RLS SELECT Policies
CREATE POLICY pol_rule_violations_select ON public.rule_violations
    FOR SELECT TO authenticated
    USING (
        society_id = public.get_user_society_id(auth.uid()) AND (
            public.is_admin() OR reporter_id = auth.uid() OR subject_user_id = auth.uid()
        )
    );

CREATE POLICY pol_violation_penalties_select ON public.violation_penalties
    FOR SELECT TO authenticated
    USING (
        society_id = public.get_user_society_id(auth.uid()) AND (
            public.is_admin() OR EXISTS (
                SELECT 1 FROM public.rule_violations v 
                WHERE v.id = violation_id AND (v.reporter_id = auth.uid() OR v.subject_user_id = auth.uid())
            )
        )
    );

-- Corrected Cross-Society Admin RLS Isolation for Disputes
CREATE POLICY pol_violation_disputes_select ON public.violation_disputes
    FOR SELECT TO authenticated
    USING (
        disputed_by = auth.uid() OR (
            public.is_admin() AND EXISTS (
                SELECT 1 FROM public.rule_violations v 
                WHERE v.id = violation_id AND v.society_id = public.get_user_society_id(auth.uid())
            )
        )
    );

CREATE POLICY pol_violation_audit_logs_select ON public.violation_audit_logs
    FOR SELECT TO authenticated
    USING (
        society_id = public.get_user_society_id(auth.uid()) AND public.is_admin()
    );

-- Revoke Direct DML to force mutation via hardened SECURITY DEFINER RPCs
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.rule_violations FROM authenticated, anon, PUBLIC;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.violation_penalties FROM authenticated, anon, PUBLIC;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.violation_disputes FROM authenticated, anon, PUBLIC;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.violation_rate_limits FROM authenticated, anon, PUBLIC;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.violation_audit_logs FROM authenticated, anon, PUBLIC;

-- Revoke EXECUTE ON ALL Slice 22 Functions from PUBLIC and anon
REVOKE EXECUTE ON FUNCTION public.fn_is_valid_evidence_urls(JSONB) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.fn_report_rule_violation(UUID, UUID, VARCHAR, TEXT, JSONB) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.fn_review_rule_violation(UUID, VARCHAR, NUMERIC, TEXT) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.fn_dispute_rule_violation(UUID, TEXT) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.fn_resolve_violation_dispute(UUID, VARCHAR, TEXT) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.fn_post_violation_penalty(UUID) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.fn_post_violation_penalty_internal(UUID, UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.process_expired_violation_appeals() FROM PUBLIC, anon, authenticated;

-- Grant EXECUTE privileges to authenticated role for public RPCs
GRANT EXECUTE ON FUNCTION public.fn_is_valid_evidence_urls(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_report_rule_violation(UUID, UUID, VARCHAR, TEXT, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_review_rule_violation(UUID, VARCHAR, NUMERIC, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_dispute_rule_violation(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_resolve_violation_dispute(UUID, VARCHAR, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_post_violation_penalty(UUID) TO authenticated;

-- Grant EXECUTE privileges to service_role for internal & worker functions
GRANT EXECUTE ON FUNCTION public.fn_post_violation_penalty_internal(UUID, UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.process_expired_violation_appeals() TO service_role;
