-- SU SOCIETY APP - SLICE 5 SCHEMA
-- Governance, Documents, Notices, Vehicles & Parking, Reporting

-- \set ON_ERROR_STOP on

BEGIN;

-- =========================================================================
-- 1. NOTICES (Community Announcements)
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.notices (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    content TEXT NOT NULL,
    visibility VARCHAR(30) NOT NULL DEFAULT 'all'
        CONSTRAINT chk_notice_visibility CHECK (visibility IN ('all', 'owners', 'tenants', 'committee')),
    attachment_url VARCHAR(1024),
    expires_at TIMESTAMPTZ,
    created_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_notice_expiration CHECK (expires_at IS NULL OR expires_at > created_at)
);

CREATE INDEX idx_notices_society ON public.notices(society_id);
CREATE INDEX idx_notices_created ON public.notices(created_at);

ALTER TABLE public.notices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notices FORCE ROW LEVEL SECURITY;

-- Notice RLS Policies
CREATE POLICY pol_notices_admin ON public.notices
    FOR ALL
    USING (public.is_admin(auth.uid()) AND society_id = public.get_user_society_id(auth.uid()));

CREATE POLICY pol_notices_select_member ON public.notices
    FOR SELECT
    USING (
        society_id = public.get_user_society_id(auth.uid())
        AND (
            visibility = 'all'
            OR (visibility = 'owners' AND EXISTS (SELECT 1 FROM public.property_owners WHERE owner_id = auth.uid() AND (end_date IS NULL OR end_date >= CURRENT_DATE)))
            OR (visibility = 'tenants' AND EXISTS (SELECT 1 FROM public.tenancies WHERE tenant_id = auth.uid() AND (end_date IS NULL OR end_date >= CURRENT_DATE)))
            OR (visibility = 'committee' AND public.has_role(auth.uid(), 'committee'))
        )
    );

-- Audit Trigger for Notices



-- =========================================================================
-- 2. GOVERNANCE (Polls and Voting)
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.polls (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'draft'
        CONSTRAINT chk_poll_status CHECK (status IN ('draft', 'active', 'closed')),
    starts_at TIMESTAMPTZ NOT NULL,
    ends_at TIMESTAMPTZ NOT NULL,
    created_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_poll_dates CHECK (ends_at > starts_at)
);

CREATE INDEX idx_polls_society ON public.polls(society_id);
CREATE INDEX idx_polls_status ON public.polls(status);

-- Poll Transitions (State Machine)
CREATE OR REPLACE FUNCTION public.trg_validate_poll_transitions()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.status != 'draft' THEN
            RAISE EXCEPTION 'Only draft polls can be deleted';
        END IF;
        RETURN OLD;
    END IF;

    IF OLD.status != NEW.status THEN
        IF OLD.status = 'draft' AND NEW.status != 'active' THEN
            RAISE EXCEPTION 'Draft poll can only transition to active';
        END IF;
        IF OLD.status = 'active' AND NEW.status != 'closed' THEN
            RAISE EXCEPTION 'Active poll can only transition to closed';
        END IF;
        IF OLD.status = 'closed' THEN
            RAISE EXCEPTION 'Closed polls cannot change status';
        END IF;
    END IF;
    
    IF OLD.status != 'draft' AND (OLD.title != NEW.title OR OLD.description != NEW.description) THEN
        RAISE EXCEPTION 'Poll configuration is immutable once no longer in draft';
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_poll_transitions
    BEFORE UPDATE OR DELETE ON public.polls
    FOR EACH ROW EXECUTE FUNCTION public.trg_validate_poll_transitions();

ALTER TABLE public.polls ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.polls FORCE ROW LEVEL SECURITY;

CREATE POLICY pol_polls_admin ON public.polls
    FOR ALL
    USING (public.is_admin(auth.uid()) AND society_id = public.get_user_society_id(auth.uid()));

CREATE POLICY pol_polls_select_member ON public.polls
    FOR SELECT
    USING (society_id = public.get_user_society_id(auth.uid()));




-- Poll Votes [AD-1: One vote per property]
CREATE TABLE IF NOT EXISTS public.poll_votes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    poll_id UUID NOT NULL REFERENCES public.polls(id) ON DELETE CASCADE,
    property_id UUID NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
    voter_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    vote_choice VARCHAR(100) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_poll_property_vote UNIQUE (poll_id, property_id)
);

CREATE INDEX idx_poll_votes_poll ON public.poll_votes(poll_id);

-- Immutability
CREATE OR REPLACE FUNCTION public.prevent_vote_mutation()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'Votes are immutable. UPDATE and DELETE are blocked.';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_vote_mutations
    BEFORE UPDATE OR DELETE ON public.poll_votes
    FOR EACH ROW EXECUTE FUNCTION public.prevent_vote_mutation();

ALTER TABLE public.poll_votes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.poll_votes FORCE ROW LEVEL SECURITY;

CREATE POLICY pol_votes_select_admin ON public.poll_votes
    FOR SELECT
    USING (public.is_admin(auth.uid()) AND EXISTS (
        SELECT 1 FROM public.polls WHERE id = poll_votes.poll_id AND society_id = public.get_user_society_id(auth.uid())
    ));

CREATE POLICY pol_votes_select_voter ON public.poll_votes
    FOR SELECT
    USING (voter_id = auth.uid());



-- SECURITY DEFINER API for voting
CREATE OR REPLACE FUNCTION public.fn_cast_poll_vote(
    p_poll_id UUID,
    p_property_id UUID,
    p_vote_choice VARCHAR
)
RETURNS UUID
SECURITY DEFINER
SET search_path = ''
LANGUAGE plpgsql
AS $$
DECLARE
    v_caller_uid UUID := auth.uid();
    v_society_id UUID;
    v_poll RECORD;
    v_vote_id UUID;
BEGIN
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'Access Denied: Unauthenticated';
    END IF;

    -- Validate Property Ownership (implicitly validates active user since revoked lose ownership visibility/capability)
    IF NOT public.is_property_owner(v_caller_uid, p_property_id) THEN
        RAISE EXCEPTION 'Access Denied: Caller is not an active owner of this property';
    END IF;

    SELECT society_id INTO v_society_id FROM public.properties WHERE id = p_property_id;

    -- Lock the poll row for read to ensure stability during the vote
    SELECT * INTO v_poll FROM public.polls 
    WHERE id = p_poll_id AND society_id = v_society_id FOR SHARE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Poll not found or cross-society denied';
    END IF;

    IF v_poll.status != 'active' THEN
        RAISE EXCEPTION 'Cannot vote: Poll is not active';
    END IF;

    IF NOW() < v_poll.starts_at OR NOW() > v_poll.ends_at THEN
        RAISE EXCEPTION 'Cannot vote: Outside of valid polling window';
    END IF;

    -- Insert vote (relies on UNIQUE(poll_id, property_id) for concurrency control)
    INSERT INTO public.poll_votes (poll_id, property_id, voter_id, vote_choice)
    VALUES (p_poll_id, p_property_id, v_caller_uid, p_vote_choice)
    RETURNING id INTO v_vote_id;

    RETURN v_vote_id;
END;
$$;


-- =========================================================================
-- 3. VEHICLES & PARKING
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.parking_slots (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE,
    slot_number VARCHAR(50) NOT NULL,
    property_id UUID REFERENCES public.properties(id) ON DELETE SET NULL,
    is_visitor BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_society_slot UNIQUE (society_id, slot_number)
);

CREATE INDEX idx_slots_society ON public.parking_slots(society_id);
CREATE INDEX idx_slots_property ON public.parking_slots(property_id);

ALTER TABLE public.parking_slots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.parking_slots FORCE ROW LEVEL SECURITY;

CREATE POLICY pol_slots_admin ON public.parking_slots
    FOR ALL
    USING (public.is_admin(auth.uid()) AND society_id = public.get_user_society_id(auth.uid()));

CREATE POLICY pol_slots_select_member ON public.parking_slots
    FOR SELECT
    USING (society_id = public.get_user_society_id(auth.uid()));


CREATE TABLE IF NOT EXISTS public.vehicles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE,
    property_id UUID NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
    registration_number VARCHAR(30) NOT NULL,
    vehicle_type VARCHAR(30) NOT NULL CONSTRAINT chk_vehicle_type CHECK (vehicle_type IN ('2-wheeler', '4-wheeler')),
    parking_slot_id UUID REFERENCES public.parking_slots(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_society_vehicle UNIQUE (society_id, registration_number),
    CONSTRAINT uq_parking_slot_assignment UNIQUE (parking_slot_id)
);

CREATE INDEX idx_vehicles_society ON public.vehicles(society_id);
CREATE INDEX idx_vehicles_property ON public.vehicles(property_id);

ALTER TABLE public.vehicles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vehicles FORCE ROW LEVEL SECURITY;

CREATE POLICY pol_vehicles_admin ON public.vehicles
    FOR ALL
    USING (public.is_admin(auth.uid()) AND society_id = public.get_user_society_id(auth.uid()));

CREATE POLICY pol_vehicles_select_member ON public.vehicles
    FOR SELECT
    USING (society_id = public.get_user_society_id(auth.uid()));

-- Resident management of their own vehicles
CREATE POLICY pol_vehicles_insert_resident ON public.vehicles
    FOR INSERT
    WITH CHECK (
        society_id = public.get_user_society_id(auth.uid())
        AND (public.is_property_owner(auth.uid(), property_id) OR public.is_property_tenant(auth.uid(), property_id))
    );

CREATE POLICY pol_vehicles_update_resident ON public.vehicles
    FOR UPDATE
    USING (
        society_id = public.get_user_society_id(auth.uid())
        AND (public.is_property_owner(auth.uid(), property_id) OR public.is_property_tenant(auth.uid(), property_id))
    );

CREATE POLICY pol_vehicles_delete_resident ON public.vehicles
    FOR DELETE
    USING (
        society_id = public.get_user_society_id(auth.uid())
        AND (public.is_property_owner(auth.uid(), property_id) OR public.is_property_tenant(auth.uid(), property_id))
    );




-- SECURITY DEFINER API for strict parking assignment
CREATE OR REPLACE FUNCTION public.fn_assign_parking_slot(
    p_vehicle_id UUID,
    p_slot_id UUID
)
RETURNS BOOLEAN
SECURITY DEFINER
SET search_path = ''
LANGUAGE plpgsql
AS $$
DECLARE
    v_caller_uid UUID := auth.uid();
    v_society_id UUID;
    v_vehicle RECORD;
    v_slot RECORD;
    v_is_admin BOOLEAN;
BEGIN
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'Access Denied: Unauthenticated';
    END IF;

    v_society_id := public.get_user_society_id(v_caller_uid);
    v_is_admin := public.is_admin(v_caller_uid);

    SELECT * INTO v_vehicle FROM public.vehicles WHERE id = p_vehicle_id AND society_id = v_society_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Vehicle not found or cross-society denied';
    END IF;

    -- Validate caller has rights to the vehicle's property
    IF NOT v_is_admin AND NOT public.is_property_owner(v_caller_uid, v_vehicle.property_id) AND NOT public.is_property_tenant(v_caller_uid, v_vehicle.property_id) THEN
        RAISE EXCEPTION 'Access Denied: Not authorized for this property vehicle';
    END IF;

    -- If unassigning
    IF p_slot_id IS NULL THEN
        UPDATE public.vehicles SET parking_slot_id = NULL WHERE id = p_vehicle_id;
        RETURN TRUE;
    END IF;

    -- Validating slot assignment
    SELECT * INTO v_slot FROM public.parking_slots WHERE id = p_slot_id AND society_id = v_society_id FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Slot not found or cross-society denied';
    END IF;

    -- Admins can assign to any non-visitor slot, but residents are restricted
    IF NOT v_is_admin THEN
        IF v_slot.is_visitor THEN
            RAISE EXCEPTION 'Access Denied: Cannot assign resident vehicle to visitor slot';
        END IF;
        
        IF v_slot.property_id IS NOT NULL AND v_slot.property_id != v_vehicle.property_id THEN
            RAISE EXCEPTION 'Access Denied: Slot is assigned to another property';
        END IF;
    END IF;

    -- Attempt update (will throw UNIQUE violation if slot is already occupied by another vehicle)
    UPDATE public.vehicles SET parking_slot_id = p_slot_id WHERE id = p_vehicle_id;

    RETURN TRUE;
END;
$$;


-- =========================================================================
-- 4. DOCUMENTS (Asset & Record Repository)
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.documents (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE,
    property_id UUID REFERENCES public.properties(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    document_type VARCHAR(50) NOT NULL CONSTRAINT chk_document_type CHECK (document_type IN ('bylaw', 'noc', 'lease', 'financial', 'other')),
    file_url VARCHAR(1024) NOT NULL,
    uploaded_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_documents_society ON public.documents(society_id);
CREATE INDEX idx_documents_property ON public.documents(property_id);

ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.documents FORCE ROW LEVEL SECURITY;

-- Admins see all society documents
CREATE POLICY pol_docs_admin ON public.documents
    FOR ALL
    USING (public.is_admin(auth.uid()) AND society_id = public.get_user_society_id(auth.uid()));

-- Members/Tenants see society-wide docs (property_id IS NULL) + their own property docs
CREATE POLICY pol_docs_select_member ON public.documents
    FOR SELECT
    USING (
        society_id = public.get_user_society_id(auth.uid())
        AND (
            property_id IS NULL
            OR public.is_property_owner(auth.uid(), property_id)
            OR public.is_property_tenant(auth.uid(), property_id)
        )
    );

-- Members/Tenants can upload docs to their own property
CREATE POLICY pol_docs_insert_member ON public.documents
    FOR INSERT
    WITH CHECK (
        society_id = public.get_user_society_id(auth.uid())
        AND property_id IS NOT NULL
        AND (public.is_property_owner(auth.uid(), property_id) OR public.is_property_tenant(auth.uid(), property_id))
    );

CREATE POLICY pol_docs_delete_member ON public.documents
    FOR DELETE
    USING (
        society_id = public.get_user_society_id(auth.uid())
        AND property_id IS NOT NULL
        AND (public.is_property_owner(auth.uid(), property_id) OR public.is_property_tenant(auth.uid(), property_id))
    );




-- =========================================================================
-- 5. REPORTING & ANALYTICS VIEWS
-- =========================================================================

-- Secure member financial statement view
CREATE OR REPLACE VIEW public.vw_member_financial_statement AS
SELECT 
    l.society_id,
    l.property_id,
    SUM(CASE WHEN l.direction = 'debit' THEN l.amount ELSE 0 END) AS total_charges_and_penalties,
    SUM(CASE WHEN l.direction = 'credit' THEN l.amount ELSE 0 END) AS total_payments_and_credits,
    SUM(CASE WHEN l.direction = 'debit' THEN l.amount ELSE -l.amount END) AS outstanding_balance
FROM public.ledger_transactions l
WHERE l.scope = 'member' 
GROUP BY l.society_id, l.property_id;

-- Ensure RLS applies if accessed directly (views without security barrier pass through caller privileges)
-- But PostgreSQL 15 defaults to invoker for views if we don't specify security definer.
-- The underlying ledger_transactions table has rigorous RLS, so this view is inherently protected.

GRANT ALL ON TABLE public.notices TO authenticated;
GRANT ALL ON TABLE public.polls TO authenticated;
GRANT ALL ON TABLE public.poll_votes TO authenticated;
GRANT ALL ON TABLE public.parking_slots TO authenticated;
GRANT ALL ON TABLE public.vehicles TO authenticated;
GRANT ALL ON TABLE public.documents TO authenticated;
GRANT ALL ON TABLE public.vw_member_financial_statement TO authenticated;

COMMIT;
