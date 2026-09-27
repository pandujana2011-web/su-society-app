-- ==============================================================================
-- SU SOCIETY APP - SLICE 10: SOCIETY GOVERNANCE (MEETINGS & RESOLUTIONS)
-- ==============================================================================

-- 1. TABLES & CONSTRAINTS

CREATE TABLE IF NOT EXISTS public.meetings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id),
    title VARCHAR(255) NOT NULL,
    description TEXT,
    meeting_type VARCHAR(50) NOT NULL,
    location VARCHAR(255),
    scheduled_at TIMESTAMPTZ NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'scheduled',
    created_by UUID NOT NULL REFERENCES public.users(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    CONSTRAINT chk_meeting_type CHECK (meeting_type IN ('AGM', 'EGM', 'committee_meeting')),
    CONSTRAINT chk_meeting_status CHECK (status IN ('scheduled', 'in_progress', 'completed', 'cancelled'))
);

CREATE TABLE IF NOT EXISTS public.meeting_agendas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    meeting_id UUID NOT NULL REFERENCES public.meetings(id) ON DELETE CASCADE,
    item_number INTEGER NOT NULL,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    CONSTRAINT uq_meeting_agenda_item UNIQUE (meeting_id, item_number),
    CONSTRAINT chk_item_number CHECK (item_number > 0)
);

CREATE TABLE IF NOT EXISTS public.meeting_resolutions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    meeting_id UUID NOT NULL REFERENCES public.meetings(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    status VARCHAR(50) NOT NULL DEFAULT 'proposed',
    poll_id UUID REFERENCES public.polls(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    CONSTRAINT chk_resolution_status CHECK (status IN ('proposed', 'adopted', 'rejected'))
);

CREATE TABLE IF NOT EXISTS public.meeting_attendance (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    meeting_id UUID NOT NULL REFERENCES public.meetings(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id),
    attended_at TIMESTAMPTZ DEFAULT NOW(),
    
    CONSTRAINT uq_meeting_attendance_user UNIQUE (meeting_id, user_id)
);

-- 2. CROSS-SOCIETY VALIDATIONS

-- Trigger to ensure meeting_resolutions.poll_id belongs to the same society as the meeting
CREATE OR REPLACE FUNCTION public.fn_validate_resolution_poll_society()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_meeting_society UUID;
    v_poll_society UUID;
BEGIN
    IF NEW.poll_id IS NOT NULL THEN
        SELECT society_id INTO v_meeting_society FROM public.meetings WHERE id = NEW.meeting_id;
        SELECT society_id INTO v_poll_society FROM public.polls WHERE id = NEW.poll_id;
        
        IF v_meeting_society != v_poll_society THEN
            RAISE EXCEPTION 'Poll society must match Meeting society';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_validate_resolution_poll_society
BEFORE INSERT OR UPDATE ON public.meeting_resolutions
FOR EACH ROW EXECUTE FUNCTION public.fn_validate_resolution_poll_society();

-- 3. STATE MACHINES (SECURITY DEFINER FUNCTIONS)

-- Meeting State Machine
CREATE OR REPLACE FUNCTION public.fn_transition_meeting_state(
    p_meeting_id UUID,
    p_new_status VARCHAR
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
    v_caller_society UUID;
    v_meeting RECORD;
BEGIN
    v_caller_society := public.get_user_society_id(auth.uid());
    IF v_caller_society IS NULL THEN RAISE EXCEPTION 'Not part of a society'; END IF;
    
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access Denied: Only admins can transition meetings';
    END IF;

    SELECT * INTO v_meeting FROM public.meetings WHERE id = p_meeting_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Meeting not found'; END IF;
    IF v_meeting.society_id != v_caller_society THEN RAISE EXCEPTION 'Cross-society denied'; END IF;

    IF p_new_status = 'in_progress' AND v_meeting.status = 'scheduled' THEN
        -- allowed
    ELSIF p_new_status = 'completed' AND v_meeting.status = 'in_progress' THEN
        -- allowed
    ELSIF p_new_status = 'cancelled' AND v_meeting.status = 'scheduled' THEN
        -- allowed
    ELSE
        RAISE EXCEPTION 'Invalid transition from % to %', v_meeting.status, p_new_status;
    END IF;

    PERFORM set_config('app.meeting_transition', p_meeting_id::text, true);
    
    UPDATE public.meetings SET status = p_new_status WHERE id = p_meeting_id;
END;
$$;

-- Resolution State Machine
CREATE OR REPLACE FUNCTION public.fn_transition_resolution_state(
    p_resolution_id UUID,
    p_new_status VARCHAR,
    p_poll_id UUID DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
    v_caller_society UUID;
    v_resolution RECORD;
    v_meeting RECORD;
BEGIN
    v_caller_society := public.get_user_society_id(auth.uid());
    IF v_caller_society IS NULL THEN RAISE EXCEPTION 'Not part of a society'; END IF;
    
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access Denied: Only admins can transition resolutions';
    END IF;

    SELECT * INTO v_resolution FROM public.meeting_resolutions WHERE id = p_resolution_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Resolution not found'; END IF;
    
    SELECT * INTO v_meeting FROM public.meetings WHERE id = v_resolution.meeting_id;
    IF v_meeting.society_id != v_caller_society THEN RAISE EXCEPTION 'Cross-society denied'; END IF;

    IF p_new_status = 'adopted' AND v_resolution.status = 'proposed' THEN
        -- allowed
    ELSIF p_new_status = 'rejected' AND v_resolution.status = 'proposed' THEN
        -- allowed
    ELSE
        RAISE EXCEPTION 'Invalid transition from % to %', v_resolution.status, p_new_status;
    END IF;

    PERFORM set_config('app.resolution_transition', p_resolution_id::text, true);
    
    IF p_poll_id IS NOT NULL THEN
        UPDATE public.meeting_resolutions SET status = p_new_status, poll_id = p_poll_id WHERE id = p_resolution_id;
    ELSE
        UPDATE public.meeting_resolutions SET status = p_new_status WHERE id = p_resolution_id;
    END IF;
END;
$$;

-- Member Self Check-In
CREATE OR REPLACE FUNCTION public.fn_meeting_self_check_in(
    p_meeting_id UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
    v_caller_society UUID;
    v_meeting RECORD;
BEGIN
    v_caller_society := public.get_user_society_id(auth.uid());
    IF v_caller_society IS NULL THEN RAISE EXCEPTION 'Not part of a society'; END IF;

    SELECT * INTO v_meeting FROM public.meetings WHERE id = p_meeting_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Meeting not found'; END IF;
    IF v_meeting.society_id != v_caller_society THEN RAISE EXCEPTION 'Cross-society denied'; END IF;
    
    IF v_meeting.status != 'in_progress' THEN 
        RAISE EXCEPTION 'Can only check in to an in_progress meeting'; 
    END IF;

    -- The unique constraint on (meeting_id, user_id) will prevent duplicates.
    INSERT INTO public.meeting_attendance (meeting_id, user_id)
    VALUES (p_meeting_id, auth.uid());
END;
$$;

-- Admin Manual Attendance
CREATE OR REPLACE FUNCTION public.fn_meeting_admin_check_in(
    p_meeting_id UUID,
    p_user_id UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
    v_caller_society UUID;
    v_meeting RECORD;
    v_target_user_society UUID;
BEGIN
    v_caller_society := public.get_user_society_id(auth.uid());
    IF v_caller_society IS NULL THEN RAISE EXCEPTION 'Not part of a society'; END IF;
    
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access Denied: Only admins can log attendance';
    END IF;

    SELECT * INTO v_meeting FROM public.meetings WHERE id = p_meeting_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Meeting not found'; END IF;
    IF v_meeting.society_id != v_caller_society THEN RAISE EXCEPTION 'Cross-society denied'; END IF;
    
    IF v_meeting.status != 'in_progress' THEN 
        RAISE EXCEPTION 'Can only check in to an in_progress meeting'; 
    END IF;

    v_target_user_society := public.get_user_society_id(p_user_id);
    IF v_target_user_society != v_caller_society THEN RAISE EXCEPTION 'Target user not in this society'; END IF;

    INSERT INTO public.meeting_attendance (meeting_id, user_id)
    VALUES (p_meeting_id, p_user_id) ON CONFLICT DO NOTHING;
END;
$$;


-- 4. TRIGGERS TO PREVENT DIRECT STATE MUTATIONS

-- Prevent meeting update
CREATE OR REPLACE FUNCTION public.fn_prevent_direct_meeting_update()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        IF current_setting('app.meeting_transition', true) IS DISTINCT FROM NEW.id::text THEN
            RAISE EXCEPTION 'Direct updates blocked. Use fn_transition_meeting_state';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_prevent_direct_meeting_update BEFORE UPDATE ON public.meetings
FOR EACH ROW EXECUTE FUNCTION public.fn_prevent_direct_meeting_update();

-- Prevent resolution update
CREATE OR REPLACE FUNCTION public.fn_prevent_direct_resolution_update()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        IF current_setting('app.resolution_transition', true) IS DISTINCT FROM NEW.id::text THEN
            RAISE EXCEPTION 'Direct updates blocked. Use fn_transition_resolution_state';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_prevent_direct_resolution_update BEFORE UPDATE ON public.meeting_resolutions
FOR EACH ROW EXECUTE FUNCTION public.fn_prevent_direct_resolution_update();


-- 5. ROW LEVEL SECURITY (RLS)

ALTER TABLE public.meetings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meetings FORCE ROW LEVEL SECURITY;

ALTER TABLE public.meeting_agendas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meeting_agendas FORCE ROW LEVEL SECURITY;

ALTER TABLE public.meeting_resolutions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meeting_resolutions FORCE ROW LEVEL SECURITY;

ALTER TABLE public.meeting_attendance ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meeting_attendance FORCE ROW LEVEL SECURITY;

-- meetings RLS
CREATE POLICY pol_meetings_admin ON public.meetings FOR ALL USING (public.is_admin() AND society_id = public.get_user_society_id(auth.uid()));
CREATE POLICY pol_meetings_select_member ON public.meetings FOR SELECT USING (
    society_id = public.get_user_society_id(auth.uid())
);

-- meeting_agendas RLS
CREATE POLICY pol_agendas_admin ON public.meeting_agendas FOR ALL USING (
    public.is_admin() AND EXISTS (SELECT 1 FROM public.meetings m WHERE m.id = meeting_id AND m.society_id = public.get_user_society_id(auth.uid()))
);
CREATE POLICY pol_agendas_select_member ON public.meeting_agendas FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.meetings m WHERE m.id = meeting_id AND m.society_id = public.get_user_society_id(auth.uid()))
);

-- meeting_resolutions RLS
CREATE POLICY pol_resolutions_admin ON public.meeting_resolutions FOR ALL USING (
    public.is_admin() AND EXISTS (SELECT 1 FROM public.meetings m WHERE m.id = meeting_id AND m.society_id = public.get_user_society_id(auth.uid()))
);
CREATE POLICY pol_resolutions_select_member ON public.meeting_resolutions FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.meetings m WHERE m.id = meeting_id AND m.society_id = public.get_user_society_id(auth.uid()))
);

-- meeting_attendance RLS
-- Admin ALL
CREATE POLICY pol_attendance_admin ON public.meeting_attendance FOR ALL USING (
    public.is_admin() AND EXISTS (SELECT 1 FROM public.meetings m WHERE m.id = meeting_id AND m.society_id = public.get_user_society_id(auth.uid()))
);
-- User can view own attendance
CREATE POLICY pol_attendance_select_own ON public.meeting_attendance FOR SELECT USING (user_id = auth.uid());
-- Wait, can users see attendance of others? The requirement says "Members see their own, Admins see all"
-- We will restrict it to their own. 


-- 6. INDEXES
CREATE INDEX idx_meetings_society_id ON public.meetings(society_id);
CREATE INDEX idx_agendas_meeting_id ON public.meeting_agendas(meeting_id);
CREATE INDEX idx_resolutions_meeting_id ON public.meeting_resolutions(meeting_id);
CREATE INDEX idx_attendance_meeting_id ON public.meeting_attendance(meeting_id);
CREATE INDEX idx_attendance_user_id ON public.meeting_attendance(user_id);

-- 7. AUDIT TRIGGERS
CREATE TRIGGER trg_audit_meetings AFTER INSERT OR UPDATE OR DELETE ON public.meetings FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger_func();
CREATE TRIGGER trg_audit_meeting_agendas AFTER INSERT OR UPDATE OR DELETE ON public.meeting_agendas FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger_func();
CREATE TRIGGER trg_audit_meeting_resolutions AFTER INSERT OR UPDATE OR DELETE ON public.meeting_resolutions FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger_func();
CREATE TRIGGER trg_audit_meeting_attendance AFTER INSERT OR UPDATE OR DELETE ON public.meeting_attendance FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger_func();

-- 8. GRANTS
GRANT SELECT, INSERT, UPDATE, DELETE ON public.meetings TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.meeting_agendas TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.meeting_resolutions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.meeting_attendance TO authenticated;
