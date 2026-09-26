-- SU SOCIETY APP - SLICE 13 SCHEMA
-- Notification Completeness & Operational Transparency

\set ON_ERROR_STOP on

BEGIN;

-- =========================================================================
-- 1. UTILITY FUNCTIONS FOR RECIPIENT RESOLUTION
-- =========================================================================

-- Get active occupants (owners + tenants) for a given property
CREATE OR REPLACE FUNCTION public.fn_get_property_occupants(p_property_id UUID)
RETURNS SETOF UUID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    RETURN QUERY
    -- Active property owners
    SELECT owner_id FROM public.property_owners 
    WHERE property_id = p_property_id 
      AND (end_date IS NULL OR end_date >= CURRENT_DATE)
    UNION
    -- Active tenants
    SELECT tenant_id FROM public.tenancies 
    WHERE property_id = p_property_id 
      AND (end_date IS NULL OR end_date >= CURRENT_DATE);
END;
$$;

-- Get active members for a given society
CREATE OR REPLACE FUNCTION public.fn_get_active_society_members(p_society_id UUID)
RETURNS SETOF UUID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    RETURN QUERY
    SELECT user_id FROM public.association_memberships
    WHERE society_id = p_society_id
      AND membership_status = 'active'
      AND (end_date IS NULL OR end_date >= CURRENT_DATE);
END;
$$;

-- =========================================================================
-- 2. NOTIFICATION DISPATCHER FUNCTIONS & TRIGGERS
-- =========================================================================

-- 2.1 Visitor Check-in (AFTER INSERT / UPDATE)
CREATE OR REPLACE FUNCTION public.fn_notify_visitor_checkin()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
    v_recipient UUID;
    v_count INT := 0;
BEGIN
    RAISE NOTICE 'Trigger fired for visitor_logs. OP: %, check_in: %', TG_OP, NEW.check_in;
    IF (TG_OP = 'INSERT' AND NEW.check_in IS NOT NULL) OR (TG_OP = 'UPDATE' AND NEW.check_in IS NOT NULL AND OLD.check_in IS NULL) THEN
        FOR v_recipient IN SELECT * FROM public.fn_get_property_occupants(NEW.property_id)
        LOOP
            v_count := v_count + 1;
            RAISE NOTICE 'Inserting notification for recipient: %', v_recipient;
            INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
            VALUES (NEW.society_id, v_recipient, 'visitor_arrival', 'Visitor Arrived', NEW.visitor_name || ' has arrived at the gate.', 'visitor_logs', NEW.id);
        END LOOP;
        RAISE NOTICE 'Inserted % notifications for visitor %', v_count, NEW.id;
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_notify_visitor_insert AFTER INSERT ON public.visitor_logs FOR EACH ROW EXECUTE FUNCTION public.fn_notify_visitor_checkin();
CREATE TRIGGER trg_notify_visitor_update AFTER UPDATE OF check_in ON public.visitor_logs FOR EACH ROW EXECUTE FUNCTION public.fn_notify_visitor_checkin();

-- 2.2 Helpdesk Status (AFTER UPDATE)
CREATE OR REPLACE FUNCTION public.fn_notify_helpdesk_status()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
    IF NEW.status IN ('assigned', 'resolved', 'closed') AND NEW.status IS DISTINCT FROM OLD.status THEN
        INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
        VALUES (NEW.society_id, NEW.created_by, 'ticket_' || NEW.status, 'Ticket ' || initcap(NEW.status), 'Your ticket "' || NEW.title || '" is now ' || NEW.status || '.', 'technician_tickets', NEW.id);
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_notify_helpdesk_update AFTER UPDATE OF status ON public.technician_tickets FOR EACH ROW EXECUTE FUNCTION public.fn_notify_helpdesk_status();

-- 2.3 Amenity Booking Status (AFTER UPDATE)
CREATE OR REPLACE FUNCTION public.fn_notify_amenity_status() RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status != NEW.status THEN
        INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
        SELECT a.society_id, NEW.booked_by, 'booking_' || NEW.status, 'Booking ' || initcap(NEW.status), 'Your amenity booking has been ' || NEW.status || '.', 'amenity_bookings', NEW.id
        FROM public.amenities a
        WHERE a.id = NEW.amenity_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;
CREATE TRIGGER trg_notify_amenity_update AFTER UPDATE OF status ON public.amenity_bookings FOR EACH ROW EXECUTE FUNCTION public.fn_notify_amenity_status();

-- 2.4 Notice Published (AFTER INSERT)
CREATE OR REPLACE FUNCTION public.fn_notify_notice_published()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
    v_recipient UUID;
BEGIN
    FOR v_recipient IN SELECT * FROM public.fn_get_active_society_members(NEW.society_id)
    LOOP
        INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
        VALUES (NEW.society_id, v_recipient, 'notice_published', 'New Notice', 'Notice: ' || NEW.title, 'notices', NEW.id);
    END LOOP;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_notify_notice_insert AFTER INSERT ON public.notices FOR EACH ROW EXECUTE FUNCTION public.fn_notify_notice_published();

-- 2.5 Meetings (AFTER INSERT / UPDATE)
CREATE OR REPLACE FUNCTION public.fn_notify_meeting()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
    v_recipient UUID;
    v_title VARCHAR;
    v_body TEXT;
    v_type VARCHAR;
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_title := 'New Meeting Scheduled';
        v_body := 'A new meeting has been scheduled: ' || NEW.title;
        v_type := 'meeting_scheduled';
    ELSIF TG_OP = 'UPDATE' AND NEW.status IS DISTINCT FROM OLD.status THEN
        v_title := 'Meeting ' || initcap(NEW.status);
        v_body := 'Meeting "' || NEW.title || '" is now ' || NEW.status || '.';
        v_type := 'meeting_' || NEW.status;
    ELSE
        RETURN NEW;
    END IF;

    FOR v_recipient IN SELECT * FROM public.fn_get_active_society_members(NEW.society_id)
    LOOP
        INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
        VALUES (NEW.society_id, v_recipient, v_type, v_title, v_body, 'meetings', NEW.id);
    END LOOP;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_notify_meeting_insert AFTER INSERT ON public.meetings FOR EACH ROW EXECUTE FUNCTION public.fn_notify_meeting();
CREATE TRIGGER trg_notify_meeting_update AFTER UPDATE OF status ON public.meetings FOR EACH ROW EXECUTE FUNCTION public.fn_notify_meeting();

-- 2.6 Parcel Received (AFTER INSERT/UPDATE)
CREATE OR REPLACE FUNCTION public.fn_notify_parcel_received()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
    v_recipient UUID;
BEGIN
    IF (TG_OP = 'INSERT' AND NEW.status = 'received_at_gate') OR (TG_OP = 'UPDATE' AND NEW.status = 'received_at_gate' AND OLD.status IS DISTINCT FROM NEW.status) THEN
        FOR v_recipient IN SELECT * FROM public.fn_get_property_occupants(NEW.property_id)
        LOOP
            INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
            VALUES (NEW.society_id, v_recipient, 'parcel_received', 'Parcel Received', 'A parcel from ' || NEW.carrier_name || ' has arrived at the gate.', 'parcel_logs', NEW.id);
        END LOOP;
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_notify_parcel_insert AFTER INSERT ON public.parcel_logs FOR EACH ROW EXECUTE FUNCTION public.fn_notify_parcel_received();
CREATE TRIGGER trg_notify_parcel_update AFTER UPDATE OF status ON public.parcel_logs FOR EACH ROW EXECUTE FUNCTION public.fn_notify_parcel_received();

-- 2.7 Move Request Approved (AFTER UPDATE)
CREATE OR REPLACE FUNCTION public.fn_notify_move_approved()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
    IF NEW.status = 'approved' AND NEW.status IS DISTINCT FROM OLD.status THEN
        INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
        VALUES (NEW.society_id, NEW.primary_user_id, 'move_approved', 'Move Request Approved', 'Your move request has been approved.', 'move_requests', NEW.id);
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_notify_move_update AFTER UPDATE OF status ON public.move_requests FOR EACH ROW EXECUTE FUNCTION public.fn_notify_move_approved();

-- 2.8 Rule Violation (AFTER INSERT / UPDATE)
CREATE OR REPLACE FUNCTION public.fn_notify_rule_violation()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
    v_recipient UUID;
    v_title VARCHAR;
    v_body TEXT;
    v_type VARCHAR;
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_title := 'Rule Violation Reported';
        v_body := 'A rule violation (' || NEW.violation_type || ') has been reported against your property.';
        v_type := 'violation_reported';
    ELSIF TG_OP = 'UPDATE' AND NEW.status = 'penalized' AND OLD.status IS DISTINCT FROM NEW.status THEN
        v_title := 'Rule Violation Penalty';
        v_body := 'A penalty of ' || NEW.penalty_amount || ' has been levied for a rule violation.';
        v_type := 'violation_penalized';
    ELSE
        RETURN NEW;
    END IF;

    FOR v_recipient IN SELECT * FROM public.fn_get_property_occupants(NEW.property_id)
    LOOP
        INSERT INTO public.notifications (society_id, recipient_user_id, type, title, body, related_entity_type, related_entity_id)
        VALUES (NEW.society_id, v_recipient, v_type, v_title, v_body, 'rule_violations', NEW.id);
    END LOOP;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_notify_violation_insert AFTER INSERT ON public.rule_violations FOR EACH ROW EXECUTE FUNCTION public.fn_notify_rule_violation();
CREATE TRIGGER trg_notify_violation_update AFTER UPDATE OF status ON public.rule_violations FOR EACH ROW EXECUTE FUNCTION public.fn_notify_rule_violation();

COMMIT;
