-- Refactored Financial Core (Moved from Slice 4)
CREATE OR REPLACE FUNCTION public._internal_settle_payment(
    p_payment_id UUID,
    p_allocations JSONB,
    p_authorized_by UUID
)
RETURNS UUID
LANGUAGE plpgsql 
-- NO SECURITY DEFINER, runs in caller's context
SET search_path = public, pg_temp
AS $$
DECLARE
    v_payment RECORD;
    v_alloc_item RECORD;
    v_charge RECORD;
    v_alloc_sum NUMERIC(15, 2) := 0;
    v_already_allocated NUMERIC(15, 2);
    v_outstanding NUMERIC(15, 2);
    v_receipt_num VARCHAR;
    v_receipt_id UUID;
    v_payer_info JSONB;
BEGIN
    -- 1. Lock payment
    SELECT * INTO v_payment FROM public.payments WHERE id = p_payment_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Payment not found.'; END IF;

    -- We do not validate status here because webhooks can be processed when status is pending_verification
    -- Wait, process_verified_webhook validates pending_verification anyway.
    
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
        v_payment.society_id, 'property', v_payment.property_id, v_payment.unit_id, v_payment.amount, 'credit', 'payment', p_payment_id, 'Verified payment', p_authorized_by
    );
    
    -- 9. Generate Receipt
    v_receipt_num := 'REC-' || TO_CHAR(CURRENT_DATE, 'YYYYMMDD') || '-' || LPAD(nextval('public.receipt_number_seq')::text, 6, '0');
    v_payer_info := jsonb_build_object('user_id', v_payment.created_by, 'property_id', v_payment.property_id);
    
    INSERT INTO public.receipts (
        society_id, payment_id, receipt_number, amount, allocation_snapshot, payer_snapshot, generated_by
    ) VALUES (
        v_payment.society_id, p_payment_id, v_receipt_num, v_payment.amount, p_allocations, v_payer_info, p_authorized_by
    ) RETURNING id INTO v_receipt_id;
    
    -- Update payment state
    UPDATE public.payments SET status = 'verified', posted_at = NOW(), verified_by = p_authorized_by WHERE id = p_payment_id;
    
    -- 10. Audit
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (v_payment.society_id, p_authorized_by, 'payment', p_payment_id, 'payment_verified_with_allocation', 
        jsonb_build_object('receipt_number', v_receipt_num, 'allocations', p_allocations));
        
    -- 11. Notification
    INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
    VALUES (v_payment.society_id, v_payment.created_by, 'payment_verified', 'Payment Verified', 
        'Your payment of ' || v_payment.amount || ' has been verified. Receipt: ' || v_receipt_num, 'payments', p_payment_id);
        
    RETURN v_receipt_id;
END;
$$;

-- B. Re-create the Admin-facing API
CREATE OR REPLACE FUNCTION public.fn_verify_payment_with_allocation(
    p_payment_id UUID,
    p_allocations JSONB
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller_society UUID;
    v_payment RECORD;
    v_receipt_id UUID;
BEGIN
    v_caller_society := public.get_user_society_id(auth.uid());
    
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access Denied: Only admins can verify payments.';
    END IF;

    -- Verify society isolation before delegating
    SELECT * INTO v_payment FROM public.payments WHERE id = p_payment_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Payment not found.'; END IF;
    
    IF v_payment.society_id != v_caller_society THEN
        RAISE EXCEPTION 'Cross-society denied';
    END IF;

    IF v_payment.status != 'pending_verification' THEN
        RAISE EXCEPTION 'Invalid transition: Payment must be pending verification.';
    END IF;

    -- Delegate to internal settler
    v_receipt_id := public._internal_settle_payment(p_payment_id, p_allocations, auth.uid());
    
    RETURN v_receipt_id;
END;
$$;
