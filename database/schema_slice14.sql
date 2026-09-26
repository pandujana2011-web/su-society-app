-- =========================================================================
-- SU SOCIETY APP - SLICE 14 (Automated Payment Gateway Integration & Webhook Settlement)
-- =========================================================================

\set ON_ERROR_STOP on

BEGIN;

-- =========================================================================
-- 1. TABLES
-- =========================================================================

-- 1.1 Payment Webhooks Table (Immutable Event Ledger)
CREATE TABLE IF NOT EXISTS public.payment_webhooks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider VARCHAR(50) NOT NULL,
    provider_event_id VARCHAR(255) NOT NULL,
    event_type VARCHAR(100) NOT NULL,
    payload JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_payment_webhooks_event UNIQUE (provider, provider_event_id)
);

-- Protect Webhooks immutability (No UPDATE or DELETE permitted)
CREATE OR REPLACE FUNCTION public.prevent_payment_webhook_mutations()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    RAISE EXCEPTION 'payment_webhooks is an immutable append-only ledger. UPDATE and DELETE are not permitted.';
END;
$$;

DROP TRIGGER IF EXISTS trg_payment_webhooks_immutable ON public.payment_webhooks;
CREATE TRIGGER trg_payment_webhooks_immutable
    BEFORE UPDATE OR DELETE ON public.payment_webhooks
    FOR EACH ROW EXECUTE FUNCTION public.prevent_payment_webhook_mutations();


-- 1.2 Payment Intents Table (Intent bounded to existing payment)
CREATE TABLE IF NOT EXISTS public.payment_intents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    property_id UUID REFERENCES public.properties(id) ON DELETE RESTRICT,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    payment_id UUID NOT NULL REFERENCES public.payments(id) ON DELETE RESTRICT,
    allocations JSONB NOT NULL, -- Stored snapshot of allocations for settlement
    amount NUMERIC(15, 2) NOT NULL CONSTRAINT chk_intent_amount CHECK (amount > 0),
    currency VARCHAR(10) NOT NULL DEFAULT 'INR',
    provider VARCHAR(50) NOT NULL,
    provider_order_id VARCHAR(255) NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'created'
        CONSTRAINT chk_intent_status CHECK (status IN ('created', 'processing', 'succeeded', 'settled', 'failed', 'expired')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ,
    CONSTRAINT uq_intent_provider_order UNIQUE (provider, provider_order_id)
);

ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS currency VARCHAR(10) DEFAULT 'INR';


-- =========================================================================
-- 2. STATE MACHINE PROTECTION
-- =========================================================================

-- 2.1 Intent State Transition Function
CREATE OR REPLACE FUNCTION public.fn_transition_payment_intent_state(
    p_intent_id UUID,
    p_new_status VARCHAR
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_intent RECORD;
    v_caller_role TEXT;
BEGIN
    -- Security Authorization Check:
    -- Must be executed in service_role or postgres context (e.g. via process_verified_webhook)
    v_caller_role := COALESCE(
        current_setting('request.jwt.claim.role', true),
        session_user
    );

    IF v_caller_role NOT IN ('service_role', 'postgres', 'supabase_admin') AND current_user NOT IN ('postgres', 'service_role') THEN
        RAISE EXCEPTION 'Access Denied: fn_transition_payment_intent_state may only be called by service_role'
            USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_intent FROM public.payment_intents WHERE id = p_intent_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Payment intent not found';
    END IF;

    -- Valid state machine transitions
    IF v_intent.status = 'created' AND p_new_status IN ('processing', 'succeeded', 'settled', 'failed', 'expired') THEN
        -- OK
    ELSIF v_intent.status = 'processing' AND p_new_status IN ('succeeded', 'settled', 'failed') THEN
        -- OK
    ELSIF v_intent.status = 'succeeded' AND p_new_status IN ('settled') THEN
        -- OK
    ELSIF v_intent.status = p_new_status THEN
        -- No-op idempotency
        RETURN;
    ELSE
        RAISE EXCEPTION 'Invalid state transition from % to %', v_intent.status, p_new_status;
    END IF;

    -- Establish trusted transition context
    PERFORM set_config('app.intent_transition', p_intent_id::text, true);

    UPDATE public.payment_intents 
    SET status = p_new_status
    WHERE id = p_intent_id;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_transition_payment_intent_state(UUID, VARCHAR) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_transition_payment_intent_state(UUID, VARCHAR) FROM anon;
REVOKE ALL ON FUNCTION public.fn_transition_payment_intent_state(UUID, VARCHAR) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_transition_payment_intent_state(UUID, VARCHAR) TO service_role;


-- 2.2 Block Direct Intent Status Mutation Trigger
CREATE OR REPLACE FUNCTION public.trg_prevent_direct_intent_status_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.status IS DISTINCT FROM OLD.status THEN
        IF current_setting('app.intent_transition', true) IS DISTINCT FROM NEW.id::text THEN
             RAISE EXCEPTION 'Direct status updates blocked. Use fn_transition_payment_intent_state';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_intent_status_block ON public.payment_intents;
CREATE TRIGGER trg_intent_status_block
    BEFORE UPDATE ON public.payment_intents
    FOR EACH ROW 
    EXECUTE FUNCTION public.trg_prevent_direct_intent_status_update();

-- =========================================================================
-- 3. FINANCIAL CORE (INTERNAL SETTLEMENT HELPER)
-- =========================================================================

-- Internal settlement logic fully preserving Slice 5 semantics
CREATE OR REPLACE FUNCTION public._internal_settle_payment(
    p_payment_id UUID,
    p_allocations JSONB,
    p_authorized_by UUID -- NULL for System (Webhook) actions
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_payment RECORD;
    v_alloc_item RECORD;
    v_charge RECORD;
    v_alloc_sum NUMERIC(15, 2) := 0;
    v_already_allocated NUMERIC(15, 2);
    v_outstanding NUMERIC(15, 2);
    v_advance_amt NUMERIC(15, 2);
    v_receipt_num VARCHAR(50);
    v_receipt_id UUID;
    v_payer_info JSONB;
    v_effective_actor UUID;
BEGIN
    -- 1. Lock payment row to prevent race conditions
    SELECT * INTO v_payment FROM public.payments WHERE id = p_payment_id FOR UPDATE;
    IF NOT FOUND THEN 
        RAISE EXCEPTION 'Payment record not found.'; 
    END IF;

    -- 2. Confirm status is pending_verification
    IF v_payment.status != 'pending_verification' THEN
        RAISE EXCEPTION 'Invalid transition: Payment must be pending verification.';
    END IF;

    -- 3. Validate active relationship (Payer active owner or tenant connection on property)
    -- Note: payments table uses created_by as the payer user_id
    IF NOT EXISTS (
        SELECT 1 FROM public.property_owners po
        WHERE po.property_id = v_payment.property_id 
          AND po.owner_id = v_payment.created_by 
          AND (po.end_date IS NULL OR po.end_date >= CURRENT_DATE)
    ) AND NOT EXISTS (
        SELECT 1 FROM public.tenancies t
        JOIN public.units u ON t.unit_id = u.id
        WHERE u.property_id = v_payment.property_id 
          AND t.tenant_id = v_payment.created_by 
          AND (t.end_date IS NULL OR t.end_date >= CURRENT_DATE)
    ) THEN
        RAISE EXCEPTION 'Invalid relationship: Payer has no active ownership or tenancy connection on this property.';
    END IF;

    -- 4. Validate allocations and recalculate outstanding balances
    FOR v_alloc_item IN SELECT * FROM jsonb_to_recordset(p_allocations) AS x(charge_id UUID, amount NUMERIC) LOOP
        IF v_alloc_item.amount <= 0 THEN
            RAISE EXCEPTION 'Allocation amount must be greater than zero.';
        END IF;
        
        v_alloc_sum := v_alloc_sum + v_alloc_item.amount;
        
        -- Lock target charge
        SELECT * INTO v_charge FROM public.maintenance_charges WHERE id = v_alloc_item.charge_id FOR UPDATE;
        IF NOT FOUND THEN 
            RAISE EXCEPTION 'Charge % not found.', v_alloc_item.charge_id; 
        END IF;
        
        -- Validate society and property isolation
        IF v_charge.society_id != v_payment.society_id THEN 
            RAISE EXCEPTION 'Charge belongs to a different society.'; 
        END IF;
        IF v_charge.property_id != v_payment.property_id THEN 
            RAISE EXCEPTION 'Charge belongs to a different property.'; 
        END IF;
        
        -- Calculate outstanding balance against verified payments
        SELECT COALESCE(SUM(pa.amount), 0) INTO v_already_allocated
        FROM public.payment_allocations pa
        JOIN public.payments p ON pa.payment_id = p.id
        WHERE pa.charge_id = v_alloc_item.charge_id AND p.status = 'verified';
        
        v_outstanding := v_charge.amount - v_already_allocated;
        IF v_alloc_item.amount > v_outstanding THEN
            RAISE EXCEPTION 'Allocation exceeds outstanding charge balance. Outstanding: %', v_outstanding;
        END IF;
    END LOOP;
    
    IF v_alloc_sum > v_payment.amount THEN
        RAISE EXCEPTION 'Sum of allocations (%) exceeds payment amount (%).', v_alloc_sum, v_payment.amount;
    END IF;
    
    -- Actor for ledger entries
    v_effective_actor := COALESCE(p_authorized_by, v_payment.created_by);

    -- 5. Insert allocations and member subsidiary ledger credits
    FOR v_alloc_item IN SELECT * FROM jsonb_to_recordset(p_allocations) AS x(charge_id UUID, amount NUMERIC) LOOP
        INSERT INTO public.payment_allocations (payment_id, charge_id, amount)
        VALUES (p_payment_id, v_alloc_item.charge_id, v_alloc_item.amount);

        INSERT INTO public.ledger_transactions (
            society_id, scope, property_id, unit_id, amount, direction, transaction_type, source_payment_id, description, created_by
        ) VALUES (
            v_payment.society_id, 'property', v_payment.property_id, v_payment.unit_id, v_alloc_item.amount, 'credit', 'payment',
            p_payment_id, 'Verified payment allocation against charge ' || v_alloc_item.charge_id, v_effective_actor
        );
    END LOOP;
    
    -- 6. Advance payment handling (unallocated portion credited as advance)
    v_advance_amt := v_payment.amount - v_alloc_sum;
    IF v_advance_amt > 0 THEN
        INSERT INTO public.ledger_transactions (
            society_id, scope, property_id, unit_id, amount, direction, transaction_type, source_payment_id, description, created_by
        ) VALUES (
            v_payment.society_id, 'property', v_payment.property_id, v_payment.unit_id, v_advance_amt, 'credit', 'payment',
            p_payment_id, 'Unallocated payment portion credited as advance', v_effective_actor
        );
    END IF;

    -- 7. Post society cash/bank ledger receipt
    INSERT INTO public.ledger_transactions (
        society_id, scope, property_id, unit_id, amount, direction, transaction_type, source_payment_id, description, created_by
    ) VALUES (
        v_payment.society_id, 'society', NULL, NULL, v_payment.amount, 'debit', 'payment',
        p_payment_id, 'Member payment receipt ref: ' || COALESCE(v_payment.reference_number, p_payment_id::text), v_effective_actor
    );
    
    -- 8. Generate receipt document
    v_receipt_num := 'REC-' || TO_CHAR(CURRENT_DATE, 'YYYYMMDD') || '-' || LPAD(nextval('public.receipt_number_seq')::text, 6, '0');
    v_payer_info := jsonb_build_object('user_id', v_payment.created_by, 'property_id', v_payment.property_id);
    
    INSERT INTO public.receipts (
        society_id, payment_id, receipt_number, amount, allocation_snapshot, payer_snapshot, generated_by
    ) VALUES (
        v_payment.society_id, p_payment_id, v_receipt_num, v_payment.amount, p_allocations, v_payer_info, p_authorized_by
    ) RETURNING id INTO v_receipt_id;
    
    -- 9. Update payment state to verified
    UPDATE public.payments 
    SET status = 'verified', posted_at = NOW(), verified_by = p_authorized_by 
    WHERE id = p_payment_id;
    
    -- 10. Audit Log (p_authorized_by IS NULL for System/Webhook actions)
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_payment.society_id, p_authorized_by, 'payment', p_payment_id, 'payment_verified_with_allocation', 
        jsonb_build_object('receipt_number', v_receipt_num, 'allocations', p_allocations));
        
    -- 11. Dispatch Notification to Payer
    INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
    VALUES (v_payment.society_id, v_payment.created_by, 'payment_verified', 'Payment Verified', 
        'Your payment of ' || v_payment.amount || ' has been verified. Receipt: ' || v_receipt_num, 'payments', p_payment_id);
        
    RETURN v_receipt_id;
END;
$$;

-- Protect internal settler from public/authenticated execution
REVOKE ALL ON FUNCTION public._internal_settle_payment(UUID, JSONB, UUID) FROM PUBLIC;

-- =========================================================================
-- 4. ADMIN WRAPPER (Slice 5 Signature Preserved)
-- =========================================================================

CREATE OR REPLACE FUNCTION public.fn_verify_payment_with_allocation(
    p_payment_id UUID,
    p_allocations JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller_society UUID;
    v_payment RECORD;
    v_receipt_id UUID;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access Denied: Only admins can verify payments.';
    END IF;

    v_caller_society := public.get_user_society_id(auth.uid());

    -- Verify society isolation before delegating
    SELECT * INTO v_payment FROM public.payments WHERE id = p_payment_id;
    IF NOT FOUND THEN 
        RAISE EXCEPTION 'Payment record not found.'; 
    END IF;
    
    IF v_payment.society_id != v_caller_society THEN
        RAISE EXCEPTION 'Cross-society denied';
    END IF;

    -- Delegate to internal settler passing auth.uid() as explicit admin actor
    v_receipt_id := public._internal_settle_payment(p_payment_id, p_allocations, auth.uid());
    
    RETURN v_receipt_id;
END;
$$;

-- =========================================================================
-- 5. WEBHOOK WRAPPER
-- =========================================================================

CREATE OR REPLACE FUNCTION public.process_verified_webhook(
    p_provider VARCHAR,
    p_event_id VARCHAR,
    p_event_type VARCHAR,
    p_payload JSONB,
    p_intent_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_intent RECORD;
    v_payment RECORD;
    v_webhook_id UUID;
    v_receipt_id UUID;
    v_provider_amount NUMERIC(15,2);
    v_provider_order_id VARCHAR(255);
    v_provider_currency VARCHAR(10);
    v_intent_currency VARCHAR(10);
    v_payment_currency VARCHAR(10);
    v_existing_webhook RECORD;
    v_current_status VARCHAR;
BEGIN
    -- 1. Idempotency Check & Event Ledger Record FIRST
    BEGIN
        INSERT INTO public.payment_webhooks (provider, provider_event_id, event_type, payload)
        VALUES (p_provider, p_event_id, p_event_type, p_payload)
        RETURNING id INTO v_webhook_id;
    EXCEPTION WHEN unique_violation THEN
        -- Handle duplicate provider event cleanly
        SELECT * INTO v_existing_webhook 
        FROM public.payment_webhooks 
        WHERE provider = p_provider AND provider_event_id = p_event_id;

        -- If duplicate event payload conflicts, raise error
        IF v_existing_webhook.payload IS DISTINCT FROM p_payload OR v_existing_webhook.event_type IS DISTINCT FROM p_event_type THEN
            RAISE EXCEPTION 'Conflicting webhook payload for duplicate event %', p_event_id;
        END IF;

        -- Duplicate retry of identical event: check intent status
        SELECT status INTO v_current_status FROM public.payment_intents WHERE id = p_intent_id;
        IF v_current_status = 'settled' THEN
            RETURN TRUE;
        END IF;
    END;

    -- 2. Lock intent for update
    SELECT * INTO v_intent FROM public.payment_intents WHERE id = p_intent_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Intent not found.';
    END IF;

    -- Idempotency: If intent is already settled, return TRUE
    IF v_intent.status = 'settled' THEN
        RETURN TRUE;
    END IF;

    IF v_intent.status = 'failed' THEN
        RETURN FALSE;
    END IF;

    -- 3. Fetch and Lock Payment
    SELECT * INTO v_payment FROM public.payments WHERE id = v_intent.payment_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Associated payment not found.';
    END IF;

    -- 4. Extract & Validate Authoritative Provider Parameters from Payload
    IF p_provider = 'stripe' THEN
        v_provider_amount := (p_payload->'data'->'object'->>'amount')::NUMERIC / 100.0;
        v_provider_order_id := p_payload->'data'->'object'->>'id';
        v_provider_currency := UPPER(TRIM(p_payload->'data'->'object'->>'currency'));
    ELSIF p_provider = 'razorpay' THEN
        v_provider_amount := (p_payload->'payload'->'payment'->'entity'->>'amount')::NUMERIC / 100.0;
        v_provider_order_id := p_payload->'payload'->'payment'->'entity'->>'order_id';
        v_provider_currency := UPPER(TRIM(p_payload->'payload'->'payment'->'entity'->>'currency'));
    ELSE
        RAISE EXCEPTION 'Unsupported provider %', p_provider;
    END IF;

    IF v_provider_amount IS NULL THEN 
        RAISE EXCEPTION 'Amount not found in payload.'; 
    END IF;

    v_intent_currency := UPPER(TRIM(v_intent.currency));
    v_payment_currency := UPPER(TRIM(v_payment.currency));

    -- Strict Currency Binding Check:
    -- provider currency != NULL AND intent currency != NULL AND payment currency != NULL
    -- AND provider currency == intent currency == payment currency
    IF v_provider_currency IS NULL OR v_provider_currency = '' OR
       v_intent_currency IS NULL OR v_intent_currency = '' OR
       v_payment_currency IS NULL OR v_payment_currency = '' OR
       v_provider_currency != v_intent_currency OR
       v_intent_currency != v_payment_currency THEN
        PERFORM public.fn_transition_payment_intent_state(p_intent_id, 'failed');
        RETURN FALSE;
    END IF;

    -- Binding Check: provider amount == intent amount == payment amount AND provider_order_id matches
    IF v_provider_amount != v_intent.amount OR v_intent.amount != v_payment.amount OR (v_provider_order_id IS NOT NULL AND v_provider_order_id != v_intent.provider_order_id) THEN
        PERFORM public.fn_transition_payment_intent_state(p_intent_id, 'failed');
        RETURN FALSE;
    END IF;

    -- 5. Transition Intent to Processing -> Succeeded
    PERFORM public.fn_transition_payment_intent_state(p_intent_id, 'processing');
    PERFORM public.fn_transition_payment_intent_state(p_intent_id, 'succeeded');

    -- 6. Execute Settlement (actor = NULL for System action)
    v_receipt_id := public._internal_settle_payment(v_intent.payment_id, v_intent.allocations, NULL);

    -- 7. Transition Intent to Settled
    PERFORM public.fn_transition_payment_intent_state(p_intent_id, 'settled');

    RETURN TRUE;
END;
$$;

-- Revoke execute from public and authenticated, grant exclusively to service_role
REVOKE ALL ON FUNCTION public.process_verified_webhook(VARCHAR, VARCHAR, VARCHAR, JSONB, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.process_verified_webhook(VARCHAR, VARCHAR, VARCHAR, JSONB, UUID) TO service_role;

-- =========================================================================
-- 6. RLS POLICIES
-- =========================================================================

ALTER TABLE public.payment_webhooks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_webhooks FORCE ROW LEVEL SECURITY;

ALTER TABLE public.payment_intents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_intents FORCE ROW LEVEL SECURITY;

-- Webhooks RLS: Only admins can SELECT. Insert/Update/Delete blocked for normal clients.
DROP POLICY IF EXISTS pol_payment_webhooks_select_admin ON public.payment_webhooks;
CREATE POLICY pol_payment_webhooks_select_admin ON public.payment_webhooks FOR SELECT
    USING (public.is_admin());

DROP POLICY IF EXISTS pol_payment_webhooks_no_insert ON public.payment_webhooks;
CREATE POLICY pol_payment_webhooks_no_insert ON public.payment_webhooks FOR INSERT
    WITH CHECK (false);

DROP POLICY IF EXISTS pol_payment_webhooks_no_update ON public.payment_webhooks;
CREATE POLICY pol_payment_webhooks_no_update ON public.payment_webhooks FOR UPDATE 
    USING (false);

DROP POLICY IF EXISTS pol_payment_webhooks_no_delete ON public.payment_webhooks;
CREATE POLICY pol_payment_webhooks_no_delete ON public.payment_webhooks FOR DELETE 
    USING (false);

-- Intents RLS: Admin sees all in society, resident sees own. Resident can INSERT status 'created'.
DROP POLICY IF EXISTS pol_payment_intents_select_admin ON public.payment_intents;
CREATE POLICY pol_payment_intents_select_admin ON public.payment_intents FOR SELECT
    USING (public.is_admin() AND society_id = public.get_user_society_id(auth.uid()));

DROP POLICY IF EXISTS pol_payment_intents_select_resident ON public.payment_intents;
CREATE POLICY pol_payment_intents_select_resident ON public.payment_intents FOR SELECT
    USING (user_id = auth.uid());

DROP POLICY IF EXISTS pol_payment_intents_insert_resident ON public.payment_intents;
CREATE POLICY pol_payment_intents_insert_resident ON public.payment_intents FOR INSERT
    WITH CHECK (
        user_id = auth.uid() AND
        status = 'created' AND
        society_id = public.get_user_society_id(auth.uid())
    );

DROP POLICY IF EXISTS pol_payment_intents_no_update ON public.payment_intents;
CREATE POLICY pol_payment_intents_no_update ON public.payment_intents FOR UPDATE 
    USING (false);

DROP POLICY IF EXISTS pol_payment_intents_no_delete ON public.payment_intents;
CREATE POLICY pol_payment_intents_no_delete ON public.payment_intents FOR DELETE 
    USING (false);

-- =========================================================================
-- 7. INDEXES & GRANTS
-- =========================================================================

CREATE UNIQUE INDEX IF NOT EXISTS idx_payment_intents_unique_active_payment 
    ON public.payment_intents(payment_id) WHERE status NOT IN ('failed', 'expired');
CREATE INDEX IF NOT EXISTS idx_payment_webhooks_event ON public.payment_webhooks(provider, provider_event_id);
CREATE INDEX IF NOT EXISTS idx_payment_intents_payment ON public.payment_intents(payment_id);
CREATE INDEX IF NOT EXISTS idx_payment_intents_user ON public.payment_intents(user_id);

GRANT SELECT ON public.payment_webhooks TO authenticated;
GRANT SELECT, INSERT ON public.payment_intents TO authenticated;

-- Service Role Grants for Webhook Execution Context
GRANT ALL ON TABLE public.payment_webhooks TO service_role;
GRANT ALL ON TABLE public.payment_intents TO service_role;
GRANT ALL ON TABLE public.payments TO service_role;
GRANT ALL ON TABLE public.payment_allocations TO service_role;
GRANT ALL ON TABLE public.receipts TO service_role;
GRANT ALL ON TABLE public.ledger_transactions TO service_role;
GRANT ALL ON TABLE public.notifications TO service_role;
GRANT ALL ON TABLE public.audit_logs TO service_role;

COMMIT;
