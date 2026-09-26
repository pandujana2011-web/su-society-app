-- =============================================================================
-- SU Society App — System Architecture v1.0
-- Schema Slice 12: Emergency Operations & SOS Alerts
-- =============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.sos_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE,
    property_id UUID NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
    raised_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    alert_type VARCHAR(50) NOT NULL CHECK (alert_type IN ('security', 'medical', 'fire', 'lift_emergency', 'other')),
    status VARCHAR(20) NOT NULL DEFAULT 'triggered' CHECK (status IN ('triggered', 'acknowledged', 'resolved', 'false_alarm')),
    acknowledged_by UUID NULL REFERENCES public.users(id) ON DELETE SET NULL,
    acknowledged_at TIMESTAMPTZ NULL,
    resolved_by UUID NULL REFERENCES public.users(id) ON DELETE SET NULL,
    resolved_at TIMESTAMPTZ NULL,
    resolution_notes TEXT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Active alert constraint: A property can only have one active (triggered/acknowledged) alert at a time.
CREATE UNIQUE INDEX IF NOT EXISTS uq_active_sos_alert_property
ON public.sos_alerts (property_id)
WHERE status IN ('triggered', 'acknowledged');

CREATE INDEX IF NOT EXISTS idx_sos_alerts_society_id ON public.sos_alerts(society_id);
CREATE INDEX IF NOT EXISTS idx_sos_alerts_property_id ON public.sos_alerts(property_id);
CREATE INDEX IF NOT EXISTS idx_sos_alerts_status ON public.sos_alerts(status);

-- 1. Validate property belongs to society and raised_by is current user
CREATE OR REPLACE FUNCTION public.fn_validate_sos_alert_creation()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_property_society_id UUID;
BEGIN
    SELECT society_id INTO v_property_society_id FROM public.properties WHERE id = NEW.property_id;
    IF v_property_society_id IS NULL OR v_property_society_id != NEW.society_id THEN
        RAISE EXCEPTION 'Property % does not belong to society %', NEW.property_id, NEW.society_id;
    END IF;

    -- Ensure raised_by is strictly bound to auth.uid()
    IF NEW.raised_by != auth.uid() THEN
        RAISE EXCEPTION 'Cannot spoof raised_by. Must match authenticated user.';
    END IF;

    IF NOT public.is_property_owner(auth.uid(), NEW.property_id) AND NOT public.is_property_tenant(auth.uid(), NEW.property_id) THEN
        RAISE EXCEPTION 'User must be an active owner or tenant of the property to raise an SOS alert.';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_sos_alert_creation
BEFORE INSERT ON public.sos_alerts
FOR EACH ROW EXECUTE FUNCTION public.fn_validate_sos_alert_creation();

-- 2. Prevent mutation of immutable fields
CREATE OR REPLACE FUNCTION public.fn_prevent_sos_immutable_mutations()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.society_id IS DISTINCT FROM OLD.society_id THEN
        RAISE EXCEPTION 'society_id is immutable';
    END IF;
    IF NEW.property_id IS DISTINCT FROM OLD.property_id THEN
        RAISE EXCEPTION 'property_id is immutable';
    END IF;
    IF NEW.raised_by IS DISTINCT FROM OLD.raised_by THEN
        RAISE EXCEPTION 'raised_by is immutable';
    END IF;
    IF NEW.alert_type IS DISTINCT FROM OLD.alert_type THEN
        RAISE EXCEPTION 'alert_type is immutable';
    END IF;
    IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN
        RAISE EXCEPTION 'created_at is immutable';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_sos_immutable_mutations
BEFORE UPDATE ON public.sos_alerts
FOR EACH ROW EXECUTE FUNCTION public.fn_prevent_sos_immutable_mutations();

-- 3. Notification dispatch trigger (Fan-out to admins and gatekeepers)
CREATE OR REPLACE FUNCTION public.fn_dispatch_sos_notification()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    INSERT INTO public.notifications (society_id, recipient_user_id, title, body, type)
    SELECT NEW.society_id, ur.user_id, 'EMERGENCY: ' || NEW.alert_type, 'SOS Alert raised from property ' || NEW.property_id, 'alert'
    FROM public.user_roles ur
    JOIN public.users u ON u.id = ur.user_id
    WHERE ur.society_id = NEW.society_id
      AND ur.revoked_on IS NULL
      AND u.status = 'active'
      AND ur.role_name IN ('admin', 'super_admin', 'gatekeeper');
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_dispatch_sos_notification
AFTER INSERT ON public.sos_alerts
FOR EACH ROW EXECUTE FUNCTION public.fn_dispatch_sos_notification();

-- 4. Direct UPDATE protection via Transaction-local context
CREATE OR REPLACE FUNCTION public.fn_protect_sos_status_update()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.status IS DISTINCT FROM OLD.status THEN
        IF current_setting('app.sos_alert_transition', true) IS NULL OR current_setting('app.sos_alert_transition', true) != NEW.id::text THEN
            RAISE EXCEPTION 'Direct updates blocked. Use fn_transition_sos_alert.';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_protect_sos_status_update
BEFORE UPDATE OF status ON public.sos_alerts
FOR EACH ROW EXECUTE FUNCTION public.fn_protect_sos_status_update();

-- 5. Transition State Machine
CREATE OR REPLACE FUNCTION public.fn_transition_sos_alert(
    p_alert_id UUID,
    p_new_status VARCHAR,
    p_notes TEXT DEFAULT NULL
)
RETURNS VOID
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_alert RECORD;
    v_is_authorized BOOLEAN;
BEGIN
    -- Retrieve and lock the alert for concurrency-safe transition
    SELECT * INTO v_alert FROM public.sos_alerts WHERE id = p_alert_id FOR UPDATE NOWAIT;
    
    IF v_alert IS NULL THEN
        RAISE EXCEPTION 'SOS alert not found.';
    END IF;

    -- Terminal state check
    IF v_alert.status IN ('resolved', 'false_alarm') THEN
        RAISE EXCEPTION 'Alert is in a terminal state and cannot be transitioned.';
    END IF;

    -- Authorization check (caller must be active admin or gatekeeper in the alert's society)
    IF v_alert.society_id != public.get_user_society_id(auth.uid()) THEN
        RAISE EXCEPTION 'Unauthorized: Cross-society denied.';
    END IF;
    
    v_is_authorized := public.is_admin(auth.uid()) OR public.has_role(auth.uid(), 'gatekeeper');
    IF NOT v_is_authorized THEN
        RAISE EXCEPTION 'Unauthorized. Only society admins or gatekeepers can transition SOS alerts.';
    END IF;

    -- Valid Transitions:
    -- triggered -> acknowledged
    -- triggered -> false_alarm
    -- acknowledged -> resolved
    -- acknowledged -> false_alarm

    IF p_new_status = 'acknowledged' THEN
        IF v_alert.status != 'triggered' THEN
            RAISE EXCEPTION 'Invalid transition to acknowledged from %', v_alert.status;
        END IF;
        
        PERFORM set_config('app.sos_alert_transition', p_alert_id::text, true);
        UPDATE public.sos_alerts 
        SET status = 'acknowledged', acknowledged_by = auth.uid(), acknowledged_at = now()
        WHERE id = p_alert_id;

    ELSIF p_new_status = 'resolved' THEN
        IF v_alert.status != 'acknowledged' THEN
            RAISE EXCEPTION 'Invalid transition to resolved from %', v_alert.status;
        END IF;

        PERFORM set_config('app.sos_alert_transition', p_alert_id::text, true);
        UPDATE public.sos_alerts 
        SET status = 'resolved', resolved_by = auth.uid(), resolved_at = now(), resolution_notes = p_notes
        WHERE id = p_alert_id;

    ELSIF p_new_status = 'false_alarm' THEN
        IF v_alert.status NOT IN ('triggered', 'acknowledged') THEN
            RAISE EXCEPTION 'Invalid transition to false_alarm from %', v_alert.status;
        END IF;

        PERFORM set_config('app.sos_alert_transition', p_alert_id::text, true);
        UPDATE public.sos_alerts 
        SET status = 'false_alarm', resolved_by = auth.uid(), resolved_at = now(), resolution_notes = p_notes
        WHERE id = p_alert_id;
    ELSE
        RAISE EXCEPTION 'Unknown target status %', p_new_status;
    END IF;

END;
$$ LANGUAGE plpgsql;

-- 6. Attach Audit Logs
-- Ensure audit_trigger_func is attached to log changes.
CREATE TRIGGER trg_audit_sos_alerts
AFTER INSERT OR UPDATE OR DELETE ON public.sos_alerts
FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger_func();


-- 7. RLS
ALTER TABLE public.sos_alerts ENABLE ROW LEVEL SECURITY;

CREATE POLICY policy_sos_select ON public.sos_alerts
    FOR SELECT
    USING (
        society_id = public.get_user_society_id(auth.uid())
        AND (
            public.is_admin(auth.uid())
            OR public.has_role(auth.uid(), 'gatekeeper')
            OR public.is_property_owner(auth.uid(), property_id)
            OR public.is_property_tenant(auth.uid(), property_id)
        )
    );

CREATE POLICY policy_sos_insert ON public.sos_alerts
    FOR INSERT
    WITH CHECK (
        society_id = public.get_user_society_id(auth.uid())
        AND (
            public.is_property_owner(auth.uid(), property_id)
            OR public.is_property_tenant(auth.uid(), property_id)
        )
    );

CREATE POLICY policy_sos_update ON public.sos_alerts
    FOR UPDATE
    USING (false);

CREATE POLICY policy_sos_delete ON public.sos_alerts
    FOR DELETE
    USING (false);

-- Grant perms
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sos_alerts TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_transition_sos_alert(UUID, VARCHAR, TEXT) TO authenticated;

COMMIT;
