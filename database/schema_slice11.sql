-- ==============================================================================
-- SU SOCIETY APP - SLICE 11: METERED UTILITIES
-- ==============================================================================
-- Adds support for variable, usage-based consumption billing (water, gas, electricity).
-- Integrates directly with the Phase 1 immutable ledger.

\set ON_ERROR_STOP on

BEGIN;

-- ------------------------------------------------------------------------------
-- 1. UTILITY METERS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.utility_meters (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id          UUID        NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    property_id         UUID        NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
    utility_type        VARCHAR(50) NOT NULL CONSTRAINT chk_meter_type CHECK (utility_type IN ('water', 'electricity', 'gas', 'hvac')),
    meter_number        VARCHAR(100) NOT NULL,
    unit_rate           NUMERIC(10,2) NOT NULL CONSTRAINT chk_meter_rate_positive CHECK (unit_rate >= 0.00),
    status              VARCHAR(20) NOT NULL DEFAULT 'active' CONSTRAINT chk_meter_status CHECK (status IN ('active', 'inactive', 'maintenance')),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(society_id, meter_number) -- A meter number should be unique within a society
);

-- ------------------------------------------------------------------------------
-- 2. METER READINGS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.meter_readings (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    meter_id            UUID        NOT NULL REFERENCES public.utility_meters(id) ON DELETE RESTRICT,
    reading_date        DATE        NOT NULL,
    previous_reading    NUMERIC(12,2) NOT NULL CONSTRAINT chk_prev_reading_positive CHECK (previous_reading >= 0.00),
    current_reading     NUMERIC(12,2) NOT NULL CONSTRAINT chk_curr_reading_positive CHECK (current_reading >= previous_reading),
    
    -- Derived calculations (Database enforced, not trusted from client)
    consumption         NUMERIC(12,2) GENERATED ALWAYS AS (current_reading - previous_reading) STORED,
    
    -- Historical snapshot of the rate applied at the moment of billing
    applied_unit_rate   NUMERIC(10,2) NOT NULL CONSTRAINT chk_applied_rate_positive CHECK (applied_unit_rate >= 0.00),
    
    -- Derived financial payload
    total_charge        NUMERIC(12,2) GENERATED ALWAYS AS ((current_reading - previous_reading) * applied_unit_rate) STORED,
    
    -- State machine
    status              VARCHAR(20) NOT NULL DEFAULT 'draft' CONSTRAINT chk_reading_status CHECK (status IN ('draft', 'verified', 'billed', 'rejected')),
    
    -- Cross-reference to the generated ledger transaction (only populated if billed)
    ledger_transaction_id UUID        REFERENCES public.ledger_transactions(id) ON DELETE RESTRICT,
    
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by          UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    
    -- Prevent multiple readings on the exact same date for the same meter
    UNIQUE(meter_id, reading_date)
);


-- ------------------------------------------------------------------------------
-- 3. STATE MACHINE & ELEVATED EXECUTION SECURITY
-- ------------------------------------------------------------------------------

-- Prevent Direct Updates to Meter Readings Status
CREATE OR REPLACE FUNCTION public.trg_enforce_meter_reading_state()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_context TEXT;
BEGIN
    IF NEW.status IS DISTINCT FROM OLD.status THEN
        v_context := current_setting('app.meter_transition', true);
        
        -- MUST have valid context
        IF v_context IS NULL OR v_context = '' THEN
            RAISE EXCEPTION 'Direct updates blocked. Use fn_transition_meter_reading_state';
        END IF;

        -- Context MUST exactly match the row ID being modified
        IF v_context != NEW.id::text THEN
            RAISE EXCEPTION 'Invalid transition context for this reading';
        END IF;
        
        -- Enforce Immutaiblity of billed
        IF OLD.status = 'billed' THEN
            RAISE EXCEPTION 'Billed meter readings are immutable';
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_prevent_direct_meter_reading_update
    BEFORE UPDATE OF status ON public.meter_readings
    FOR EACH ROW EXECUTE FUNCTION public.trg_enforce_meter_reading_state();

-- Transition function with SECURITY DEFINER
CREATE OR REPLACE FUNCTION public.fn_transition_meter_reading_state(
    p_reading_id UUID,
    p_new_status VARCHAR
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_old_status VARCHAR;
    v_society_id UUID;
    v_property_id UUID;
    v_total_charge NUMERIC;
    v_primary_owner UUID;
    v_txn_id UUID;
BEGIN
    -- 1. Caller Authorization (Must be Admin)
    IF NOT public.is_admin(v_uid) THEN
        RAISE EXCEPTION 'Only administrators can transition meter readings';
    END IF;

    -- 2. Fetch record and lock it
    SELECT mr.status, um.society_id, um.property_id, mr.total_charge
    INTO v_old_status, v_society_id, v_property_id, v_total_charge
    FROM public.meter_readings mr
    JOIN public.utility_meters um ON um.id = mr.meter_id
    WHERE mr.id = p_reading_id
    FOR UPDATE OF mr; -- Row-level lock to prevent concurrent double billing

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Meter reading not found';
    END IF;

    -- 3. Cross-Society Validation
    IF v_society_id != public.get_user_society_id(v_uid) THEN
        RAISE EXCEPTION 'Cross-society denied';
    END IF;

    -- 4. State Machine Validation
    IF p_new_status = 'verified' AND v_old_status != 'draft' THEN
        RAISE EXCEPTION 'Invalid transition from % to verified', v_old_status;
    END IF;
    
    IF p_new_status = 'billed' AND v_old_status NOT IN ('draft', 'verified') THEN
        RAISE EXCEPTION 'Invalid transition from % to billed', v_old_status;
    END IF;
    
    IF p_new_status = 'rejected' AND v_old_status != 'draft' THEN
        RAISE EXCEPTION 'Invalid transition from % to rejected', v_old_status;
    END IF;

    -- 5. Financial Integration (Billing)
    IF p_new_status = 'billed' THEN
        -- Find primary owner
        SELECT owner_id INTO v_primary_owner
        FROM public.property_owners
        WHERE property_id = v_property_id
          AND is_primary_owner = TRUE
          AND end_date IS NULL;
          
        IF v_primary_owner IS NULL THEN
            RAISE EXCEPTION 'Cannot bill reading: Property has no active primary owner';
        END IF;
        
        -- Insert into ledger
        INSERT INTO public.ledger_transactions (
            society_id,
            property_id,
            scope,
            direction,
            amount,
            transaction_type,
            source_meter_reading_id,
            description,
            created_by
        ) VALUES (
            v_society_id,
            v_property_id,
            'property',
            'debit',
            v_total_charge,
            'charge',
            p_reading_id,
            'Utility Bill Generated',
            v_uid
        ) RETURNING id INTO v_txn_id;
    END IF;

    -- 6. Apply Transition via Local Context
    PERFORM set_config('app.meter_transition', p_reading_id::text, true);

    IF p_new_status = 'billed' THEN
        UPDATE public.meter_readings
        SET status = p_new_status,
            ledger_transaction_id = v_txn_id
        WHERE id = p_reading_id;
    ELSE
        UPDATE public.meter_readings
        SET status = p_new_status
        WHERE id = p_reading_id;
    END IF;

    PERFORM set_config('app.meter_transition', '', true);
END;
$$;

-- ------------------------------------------------------------------------------
-- 3.5 LEDGER TRANSACTIONS EXTENSION
-- ------------------------------------------------------------------------------
ALTER TABLE public.ledger_transactions ADD COLUMN IF NOT EXISTS source_meter_reading_id UUID REFERENCES public.meter_readings(id) ON DELETE RESTRICT;

ALTER TABLE public.ledger_transactions DROP CONSTRAINT IF EXISTS chk_ledger_source_exclusive;
ALTER TABLE public.ledger_transactions ADD CONSTRAINT chk_ledger_source_exclusive CHECK (
    (CASE WHEN source_charge_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN source_payment_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN source_expense_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN reverses_ledger_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN source_booking_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN source_voucher_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN source_opening_balance_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN source_violation_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN source_meter_reading_id IS NOT NULL THEN 1 ELSE 0 END) = 1
);

-- ------------------------------------------------------------------------------
-- 4. ROW LEVEL SECURITY
-- ------------------------------------------------------------------------------
ALTER TABLE public.utility_meters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.utility_meters FORCE ROW LEVEL SECURITY;

ALTER TABLE public.meter_readings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meter_readings FORCE ROW LEVEL SECURITY;

-- utility_meters RLS
CREATE POLICY pol_utility_meters_admin ON public.utility_meters FOR ALL USING (
    public.is_admin() AND society_id = public.get_user_society_id(auth.uid())
);
CREATE POLICY pol_utility_meters_member ON public.utility_meters FOR SELECT USING (
    EXISTS (
        SELECT 1 FROM public.property_owners po WHERE po.property_id = utility_meters.property_id AND po.owner_id = auth.uid() AND po.end_date IS NULL
        UNION
        SELECT 1 FROM public.tenancies t WHERE t.property_id = utility_meters.property_id AND t.tenant_id = auth.uid() AND t.end_date IS NULL
    )
);

-- meter_readings RLS
CREATE POLICY pol_meter_readings_admin ON public.meter_readings FOR ALL USING (
    public.is_admin() AND EXISTS (SELECT 1 FROM public.utility_meters um WHERE um.id = meter_id AND um.society_id = public.get_user_society_id(auth.uid()))
);
CREATE POLICY pol_meter_readings_member ON public.meter_readings FOR SELECT USING (
    EXISTS (
        SELECT 1 FROM public.utility_meters um
        WHERE um.id = meter_readings.meter_id
        AND (
            EXISTS (SELECT 1 FROM public.property_owners po WHERE po.property_id = um.property_id AND po.owner_id = auth.uid() AND po.end_date IS NULL)
            OR 
            EXISTS (SELECT 1 FROM public.tenancies t WHERE t.property_id = um.property_id AND t.tenant_id = auth.uid() AND t.end_date IS NULL)
        )
    )
);


-- ------------------------------------------------------------------------------
-- 5. INDEXES & AUDIT TRIGGERS
-- ------------------------------------------------------------------------------

CREATE INDEX idx_utility_meters_society ON public.utility_meters(society_id);
CREATE INDEX idx_utility_meters_property ON public.utility_meters(property_id);
CREATE INDEX idx_meter_readings_meter ON public.meter_readings(meter_id);
CREATE INDEX idx_meter_readings_status ON public.meter_readings(status);

CREATE TRIGGER trg_audit_utility_meters
    AFTER INSERT OR UPDATE OR DELETE ON public.utility_meters
    FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger_func();

CREATE TRIGGER trg_audit_meter_readings
    AFTER INSERT OR UPDATE OR DELETE ON public.meter_readings
    FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger_func();

-- ------------------------------------------------------------------------------
-- 6. GRANTS
-- ------------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE ON public.utility_meters TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.meter_readings TO authenticated;

COMMIT;
