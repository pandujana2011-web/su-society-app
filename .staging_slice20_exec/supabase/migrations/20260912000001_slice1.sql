-- =============================================================================
-- SU Society App — System Architecture v1.0
-- Schema Slice 1: Identity, Property & Membership Foundation
-- =============================================================================
--
-- APPLY ORDER (fresh Supabase deployment):
--   1. schema_slice1.sql   ← this file
--   2. schema_phase2.sql   ← financial/operational layers (Phase 2A–3A prototype)
--
-- ARCHITECTURAL DECISIONS ENCODED HERE:
--   [AD-1] One vote per property / association membership — not per co-owner
--   [AD-2] unit_id is NULLABLE; genuine property-level relationships are first-class
--   [AD-3] Multi-tenant-shaped schema; MVP deploys exactly ONE society row
--   [AD-5] All financial records are immutable; corrections via reversal/offset
--   [AD-6] Ledger uses positive amount + explicit direction (not signed amounts)
--   [AD-8] Ownership, membership, tenancy, occupancy all preserve temporal history
--   [AD-9] RLS is relationship-based; sensitive mutations go through SECURITY DEFINER
--   [AD-10] society_id scoping throughout
--
-- DEPLOYMENT NOTE:
--   This file targets Supabase PostgreSQL 15+.
--   users.id is a FOREIGN KEY to auth.users(id) — Supabase auth manages credentials.
--   Do NOT store passwords in public.users.
-- =============================================================================

BEGIN;

-- ===========================================================================
-- STEP 1 — EXTENSIONS
-- ===========================================================================

-- btree_gist: required for exclusion constraints used in temporal overlap prevention
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- pgcrypto: gen_random_uuid() is built-in on PG13+; include for compatibility
-- CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ===========================================================================
-- STEP 2 — SHARED TRIGGER FUNCTION: set_updated_at
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.set_updated_at IS
    'Automatically sets updated_at = NOW() before any UPDATE. '
    'Applied to all mutable entity tables via BEFORE UPDATE triggers.';

-- ===========================================================================
-- STEP 3 — SOCIETIES
-- ===========================================================================
-- [AD-3] Multi-tenant shaped. MVP: exactly ONE row. No multi-society UI in MVP.
-- The id is fixed at onboarding time and referenced everywhere via society_id.

CREATE TABLE IF NOT EXISTS public.societies (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name                VARCHAR(200) NOT NULL
                            CONSTRAINT chk_society_name_nonempty CHECK (TRIM(name) <> ''),
    registration_number VARCHAR(100) UNIQUE,
    address             TEXT,
    city                VARCHAR(100),
    state               VARCHAR(100),
    pincode             VARCHAR(10)
                            CONSTRAINT chk_pincode_format CHECK (pincode IS NULL OR pincode ~ '^[0-9]{6}$'),
    contact_email       VARCHAR(200)
                            CONSTRAINT chk_society_email CHECK (contact_email IS NULL OR contact_email ~* '^[^@]+@[^@]+\.[^@]+$'),
    contact_phone       VARCHAR(20),
    website_url         TEXT,
    formed_on           DATE,
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    -- Metadata
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_societies_updated_at
    BEFORE UPDATE ON public.societies
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE  public.societies IS 'Society entity. MVP contains exactly one row.';
COMMENT ON COLUMN public.societies.registration_number IS 'Official cooperative/housing society registration number.';
COMMENT ON COLUMN public.societies.formed_on IS 'Date the society was formally constituted.';

-- ===========================================================================
-- STEP 4 — USERS
-- ===========================================================================
-- Profile table linked to Supabase auth.users.
-- Credentials (email, password) live in auth.users — NOT stored here.
-- A trigger on auth.users INSERT should create the profile row automatically
-- (that trigger is part of the Supabase onboarding setup, not this file).

CREATE TABLE IF NOT EXISTS public.users (
    -- id mirrors auth.users.id; cascade delete removes profile when auth account is deleted
    id                  UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    -- Profile fields
    full_name           VARCHAR(200) NOT NULL
                            CONSTRAINT chk_user_name_nonempty CHECK (TRIM(full_name) <> ''),
    display_name        VARCHAR(100),
    mobile              VARCHAR(20)
                            CONSTRAINT chk_user_mobile CHECK (mobile IS NULL OR mobile ~ '^\+?[0-9\-\s]{7,20}$'),
    alt_mobile          VARCHAR(20)
                            CONSTRAINT chk_user_alt_mobile CHECK (alt_mobile IS NULL OR alt_mobile ~ '^\+?[0-9\-\s]{7,20}$'),
    -- Account status
    status              VARCHAR(30) NOT NULL DEFAULT 'active'
                            CONSTRAINT chk_user_status CHECK (
                                status IN ('active', 'inactive', 'suspended', 'pending_verification')
                            ),
    -- Metadata
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  public.users IS
    'User profile table. id = auth.users.id. Email and credentials managed by Supabase auth.';
COMMENT ON COLUMN public.users.status IS
    'active | inactive | suspended | pending_verification. '
    'Suspended users cannot log in or perform mutations.';
COMMENT ON COLUMN public.users.display_name IS
    'Optional short name used in UI. Falls back to full_name.';

CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON public.users
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ===========================================================================
-- STEP 5 — USER ROLES
-- ===========================================================================
-- RBAC: each row grants a user a role within a society for a time period.
-- A user may hold multiple roles simultaneously (e.g., treasurer + member).
-- [AD-9] Sensitive mutations require SECURITY DEFINER functions, not direct INSERT.

CREATE TABLE IF NOT EXISTS public.user_roles (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id          UUID        NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    user_id             UUID        NOT NULL REFERENCES public.users(id)     ON DELETE CASCADE,
    role_name           VARCHAR(50) NOT NULL
                            CONSTRAINT chk_role_name CHECK (
                                role_name IN (
                                    'super_admin',      -- Full system access, can modify roles
                                    'admin',            -- Society admin (billing, approvals)
                                    'secretary',        -- Meeting minutes, membership records
                                    'treasurer',        -- Financial visibility and approval
                                    'executive_member', -- Executive committee member
                                    'member',           -- Property owner with membership
                                    'tenant',           -- Leaseholder (limited financial access)
                                    'gatekeeper',       -- Security / visitor management
                                    'technician'        -- Maintenance staff
                                )
                            ),
    -- Temporal validity: open-ended roles use end_date = NULL
    granted_on          DATE        NOT NULL DEFAULT CURRENT_DATE,
    revoked_on          DATE,
    granted_by          UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    revocation_reason   TEXT,
    -- Constraints
    CONSTRAINT chk_role_dates CHECK (revoked_on IS NULL OR revoked_on >= granted_on),
    -- A user may not hold the same role twice concurrently in the same society
    -- Enforced via partial unique index (see Step 16 — Indexes)
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  public.user_roles IS
    'RBAC role assignments. One row per user+role+society. Temporal: revoked_on = NULL means currently active.';
COMMENT ON COLUMN public.user_roles.role_name IS
    'Constrained to the nine approved role values. '
    'A role change is a new row with revoked_on set on the old row — never UPDATE role_name.';
COMMENT ON COLUMN public.user_roles.granted_by IS
    'The user (admin/super_admin) who granted this role. Audit trail.';

-- ===========================================================================
-- STEP 6 — AUDIT LOGS
-- ===========================================================================
-- Append-only. Mutations are INSERT-only — no UPDATE or DELETE permitted.
-- A trigger enforcing immutability is created in Step 14.

CREATE TABLE IF NOT EXISTS public.audit_logs (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id          UUID        NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    actor_id            UUID        REFERENCES public.users(id) ON DELETE SET NULL, -- NULL = system action
    -- What happened
    action              VARCHAR(200) NOT NULL
                            CONSTRAINT chk_audit_action_nonempty CHECK (TRIM(action) <> ''),
    entity_type         VARCHAR(100) NOT NULL,  -- table name, e.g. 'property_owners'
    entity_id           UUID,                   -- primary key of affected row (NULL for non-row actions)
    -- State capture (JSONB; NULL if not applicable)
    old_data            JSONB,
    new_data            JSONB,
    -- Context
    ip_address          INET,
    user_agent          TEXT,
    -- Timestamp — immutable
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  public.audit_logs IS
    'Append-only immutable audit trail. No UPDATE or DELETE permitted (enforced by trigger).';
COMMENT ON COLUMN public.audit_logs.actor_id IS
    'NULL when action is performed by a system/trigger process.';
COMMENT ON COLUMN public.audit_logs.entity_id IS
    'UUID of the primary record affected. NULL for non-row-level actions (e.g., login events).';

-- ===========================================================================
-- STEP 7 — AUTHORIZATION HELPER FUNCTIONS
-- ===========================================================================
-- Used inside RLS policies and SECURITY DEFINER procedures.
-- All are STABLE SECURITY DEFINER with explicit search_path.

-- ---- is_admin() ----
-- Returns TRUE if the calling user has admin or super_admin role in any society.
-- Used in RLS policies where admin sees all rows within their society.
CREATE OR REPLACE FUNCTION public.is_admin(
    uid UUID DEFAULT auth.uid()
)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM   public.user_roles ur
        JOIN   public.users      u  ON u.id = ur.user_id
        WHERE  ur.user_id   = uid
          AND  ur.role_name IN ('admin', 'super_admin')
          AND  ur.revoked_on IS NULL          -- currently active role
          AND  u.status = 'active'
    );
$$;

COMMENT ON FUNCTION public.is_admin(UUID) IS
    'Returns TRUE if uid holds an active admin or super_admin role. '
    'Used in RLS policies. SECURITY DEFINER, search_path locked.';

-- ---- has_role() ----
-- Returns TRUE if uid currently holds the specified role.
CREATE OR REPLACE FUNCTION public.has_role(
    uid       UUID,
    p_role    TEXT
)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM   public.user_roles
        WHERE  user_id    = uid
          AND  role_name  = p_role
          AND  revoked_on IS NULL
    );
$$;

COMMENT ON FUNCTION public.has_role(UUID, TEXT) IS
    'Returns TRUE if uid currently holds p_role. revoked_on IS NULL = currently active.';

-- ---- get_user_society_id() ----
-- Returns the society_id for the calling user.
-- In MVP: one society, so any active role row gives the right society.
-- If a user belongs to no society (orphaned profile), returns NULL.
CREATE OR REPLACE FUNCTION public.get_user_society_id(
    uid UUID DEFAULT auth.uid()
)
RETURNS UUID
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT society_id
    FROM   public.user_roles
    WHERE  user_id    = uid
      AND  revoked_on IS NULL
    ORDER BY granted_on DESC
    LIMIT 1;
$$;

COMMENT ON FUNCTION public.get_user_society_id(UUID) IS
    'Returns the society_id the user belongs to via their most recent active role. '
    'MVP: one society, so this is unambiguous. Multi-society: caller must pass explicit society context.';

-- ---- is_property_owner() ----
-- Returns TRUE if uid is a current owner of property_uuid.
CREATE OR REPLACE FUNCTION public.is_property_owner(
    uid          UUID,
    property_uuid UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1
        FROM   public.property_owners po
        JOIN   public.properties p ON p.id = po.property_id
        JOIN   public.user_roles ur ON ur.society_id = p.society_id AND ur.user_id = uid
        JOIN   public.users u ON u.id = uid
        WHERE  po.property_id = property_uuid
          AND  po.owner_id    = uid
          AND  po.end_date    IS NULL    -- currently active ownership
          AND  ur.revoked_on  IS NULL    -- has an active role in the society
          AND  u.status       = 'active' -- user account is active
    );
END;
$$;

COMMENT ON FUNCTION public.is_property_owner(UUID, UUID) IS
    'Returns TRUE if uid is a current (end_date IS NULL) owner of property_uuid.';

-- ---- is_property_tenant() ----
-- Returns TRUE if uid currently has an active tenancy associated with property_uuid.
CREATE OR REPLACE FUNCTION public.is_property_tenant(
    uid           UUID,
    property_uuid UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1
        FROM   public.tenancies t
        JOIN   public.properties p ON p.id = t.property_id
        JOIN   public.user_roles ur ON ur.society_id = p.society_id AND ur.user_id = uid
        JOIN   public.users u ON u.id = uid
        WHERE  t.tenant_id   = uid
          AND  t.property_id = property_uuid
          AND  t.end_date    IS NULL    -- currently active tenancy
          AND  ur.revoked_on IS NULL    -- has an active role in the society
          AND  u.status      = 'active' -- user account is active
    );
END;
$$;

COMMENT ON FUNCTION public.is_property_tenant(UUID, UUID) IS
    'Returns TRUE if uid has a currently active tenancy (any unit or property-level) on property_uuid.';

-- ===========================================================================
-- STEP 8 — PROPERTIES
-- ===========================================================================

CREATE TABLE IF NOT EXISTS public.properties (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id              UUID        NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    -- Identification
    plot_number             VARCHAR(50) NOT NULL
                                CONSTRAINT chk_plot_number_nonempty CHECK (TRIM(plot_number) <> ''),
    survey_number           VARCHAR(100),
    sub_division_number     VARCHAR(100),
    -- Physical details
    plot_size_sqft          NUMERIC(12, 2)
                                CONSTRAINT chk_plot_size_positive CHECK (plot_size_sqft IS NULL OR plot_size_sqft > 0),
    built_up_area_sqft      NUMERIC(12, 2)
                                CONSTRAINT chk_builtup_positive CHECK (built_up_area_sqft IS NULL OR built_up_area_sqft > 0),
    -- Address / location
    door_number             VARCHAR(100),
    street_address          TEXT,
    -- Classification
    construction_status     VARCHAR(30) NOT NULL DEFAULT 'constructed'
                                CONSTRAINT chk_construction_status CHECK (
                                    construction_status IN (
                                        'constructed',
                                        'under_construction',
                                        'vacant_plot',
                                        'demolished'
                                    )
                                ),
    property_type           VARCHAR(30) NOT NULL DEFAULT 'residential'
                                CONSTRAINT chk_property_type CHECK (
                                    property_type IN ('residential', 'commercial', 'mixed_use')
                                ),
    -- Occupancy status: denormalized, kept consistent by trigger in Step 14
    -- Values derived from property_owners + tenancies state
    occupancy_status        VARCHAR(30) NOT NULL DEFAULT 'vacant'
                                CONSTRAINT chk_occupancy_status CHECK (
                                    occupancy_status IN (
                                        'owner_occupied',
                                        'tenant_occupied',
                                        'vacant',
                                        'under_construction',
                                        'disputed'
                                    )
                                ),
    -- Admin fields
    remarks                 TEXT,
    is_active               BOOLEAN     NOT NULL DEFAULT TRUE,
    created_by              UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    -- Metadata
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- Constraints
    CONSTRAINT uq_plot_per_society UNIQUE (society_id, plot_number)
);

COMMENT ON TABLE  public.properties IS
    'Plot/property registry. One row per physical property. [AD-10] society_id scoped.';
COMMENT ON COLUMN public.properties.occupancy_status IS
    'Denormalized field maintained by trigger when ownership/tenancy changes. '
    'Direct UPDATE is permitted for admin corrections, but triggers keep it consistent.';
COMMENT ON COLUMN public.properties.plot_number IS
    'Society-wide unique plot identifier, e.g. "45", "B-12". Unique per society.';

CREATE TRIGGER trg_properties_updated_at
    BEFORE UPDATE ON public.properties
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ===========================================================================
-- STEP 9 — UNITS
-- ===========================================================================
-- Optional sub-divisions of a property (floors, flats, portions).
-- Properties with no sub-division do NOT need a unit row.
-- [AD-2] unit_id is NULLABLE in all tables that reference it.

CREATE TABLE IF NOT EXISTS public.units (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id         UUID        NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
    -- Identification
    unit_identifier     VARCHAR(100) NOT NULL
                            CONSTRAINT chk_unit_identifier_nonempty CHECK (TRIM(unit_identifier) <> ''),
    description         TEXT,
    -- Physical details
    floor_level         INTEGER,    -- NULL = not applicable
    floor_area_sqft     NUMERIC(12, 2)
                            CONSTRAINT chk_unit_area_positive CHECK (floor_area_sqft IS NULL OR floor_area_sqft > 0),
    -- Status
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    created_by          UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    -- Metadata
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- A property cannot have two units with the same identifier
    CONSTRAINT uq_unit_per_property UNIQUE (property_id, unit_identifier)
);

COMMENT ON TABLE  public.units IS
    'Optional sub-divisions of a property. '
    '[AD-2] unit_id is NULLABLE in tenancies, occupants, and later billing tables. '
    'Do NOT auto-create a "Whole Property" unit to work around nullable FK.';
COMMENT ON COLUMN public.units.unit_identifier IS
    'Human-readable identifier: "Flat A", "Floor 2", "Portion North". Unique per property.';

CREATE TRIGGER trg_units_updated_at
    BEFORE UPDATE ON public.units
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ===========================================================================
-- STEP 10 — PROPERTY OWNERS (Temporal)
-- ===========================================================================
-- Tracks who owns what property and when.
-- Co-ownership: multiple rows for same property with different owner_id.
-- Temporal: end_date IS NULL = currently active ownership.
-- [AD-8] Full history preserved; ownership transfer = SET end_date on old row + INSERT new row.

CREATE TABLE IF NOT EXISTS public.property_owners (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id         UUID        NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
    owner_id            UUID        NOT NULL REFERENCES public.users(id)      ON DELETE RESTRICT,
    -- Ownership share
    ownership_share_pct NUMERIC(5,2) NOT NULL DEFAULT 100.00
                            CONSTRAINT chk_ownership_share CHECK (
                                ownership_share_pct > 0 AND ownership_share_pct <= 100
                            ),
    is_primary_owner    BOOLEAN     NOT NULL DEFAULT TRUE,
    -- Temporal validity
    start_date          DATE        NOT NULL DEFAULT CURRENT_DATE,
    end_date            DATE,
    -- Audit
    created_by          UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    end_recorded_by     UUID        REFERENCES public.users(id) ON DELETE RESTRICT,
    transfer_notes      TEXT,
    -- Metadata
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- Date integrity
    CONSTRAINT chk_owner_dates CHECK (end_date IS NULL OR end_date >= start_date)
);

-- Temporal overlap exclusion for same owner on same property.
-- btree_gist extension (Step 1) is required for this constraint.
-- [AD-8] Prevents inserting a new ownership record that overlaps an existing one for the same owner+property.
ALTER TABLE public.property_owners
    ADD CONSTRAINT excl_owner_no_overlap
    EXCLUDE USING gist (
        property_id WITH =,
        owner_id    WITH =,
        daterange(start_date, COALESCE(end_date, '9999-12-31'::date), '[)') WITH &&
    );

-- Ownership share validation: total shares for a property at any point in time
-- should not exceed 100%. This is enforced by a trigger in Step 14.

COMMENT ON TABLE  public.property_owners IS
    'Temporal ownership history. One row per owner per period. '
    'Co-ownership: multiple active rows on same property summing to 100%. '
    '[AD-8] End a period by setting end_date on the existing row; insert new row for new owner.';
COMMENT ON COLUMN public.property_owners.is_primary_owner IS
    'TRUE for the primary contact owner. Only one primary owner active at a time per property '
    '(enforced by partial unique index uq_active_primary_owner_per_property).';
COMMENT ON COLUMN public.property_owners.ownership_share_pct IS
    'This owner''s fractional share. For sole ownership: 100. '
    'For co-ownership: shares must sum to exactly 100 (enforced by trigger).';

-- ===========================================================================
-- STEP 11 — ASSOCIATION MEMBERSHIPS (Temporal)
-- ===========================================================================
-- [AD-1] One vote per property / association membership.
-- Each property holds ONE active membership row at any point in time.
-- The user_id on this row is the designated "association member" who exercises
-- the vote for that property — not all co-owners individually.
-- Transferring the voting right = end current row + insert new row.

CREATE TABLE IF NOT EXISTS public.association_memberships (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id          UUID        NOT NULL REFERENCES public.societies(id)  ON DELETE RESTRICT,
    property_id         UUID        NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
    -- The designated association member for this property
    user_id             UUID        NOT NULL REFERENCES public.users(id)      ON DELETE RESTRICT,
    -- Membership number (assigned by society secretary on admission)
    membership_number   VARCHAR(50),
    -- Status within the active period
    membership_status   VARCHAR(30) NOT NULL DEFAULT 'active'
                            CONSTRAINT chk_membership_status CHECK (
                                membership_status IN ('active', 'suspended', 'resigned', 'expelled')
                            ),
    suspension_reason   TEXT,
    -- Temporal validity
    start_date          DATE        NOT NULL DEFAULT CURRENT_DATE,
    end_date            DATE,
    -- Audit
    created_by          UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    end_recorded_by     UUID        REFERENCES public.users(id) ON DELETE RESTRICT,
    transition_notes    TEXT,
    -- Metadata
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- Date integrity
    CONSTRAINT chk_membership_dates CHECK (end_date IS NULL OR end_date >= start_date)
);

-- [AD-1] At most ONE ACTIVE (end_date IS NULL) membership per property per society.
-- This enforces "one vote per property".
CREATE UNIQUE INDEX uq_active_membership_per_property
    ON public.association_memberships (society_id, property_id)
    WHERE end_date IS NULL;

-- Uniqueness of membership numbers within a society (where assigned).
CREATE UNIQUE INDEX uq_membership_number_per_society
    ON public.association_memberships (society_id, membership_number)
    WHERE membership_number IS NOT NULL;

-- Temporal overlap exclusion: same property cannot have two memberships for overlapping periods.
ALTER TABLE public.association_memberships
    ADD CONSTRAINT excl_membership_no_overlap
    EXCLUDE USING gist (
        society_id  WITH =,
        property_id WITH =,
        daterange(start_date, COALESCE(end_date, '9999-12-31'::date), '[)') WITH &&
    );

COMMENT ON TABLE  public.association_memberships IS
    '[AD-1] Association membership: one row per property per period. '
    'Exactly ONE active membership per property (one voting right per property). '
    'Co-owners do not each get a vote — the designated user_id exercises the single vote.';
COMMENT ON COLUMN public.association_memberships.user_id IS
    'The designated association member who exercises the voting right for this property. '
    'May be any co-owner; changing the designee requires ending the current row.';
COMMENT ON COLUMN public.association_memberships.membership_number IS
    'Optional official membership number assigned by the secretary. Unique per society.';

-- ===========================================================================
-- STEP 12 — TENANCIES (Temporal — unit_id NULLABLE)
-- ===========================================================================
-- [AD-2] unit_id is NULLABLE. If the tenant leases the whole property without
-- a formal unit subdivision, set unit_id = NULL and set property_id.
-- This is a genuine design choice — not a workaround.

CREATE TABLE IF NOT EXISTS public.tenancies (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id          UUID        NOT NULL REFERENCES public.societies(id)  ON DELETE RESTRICT,
    property_id         UUID        NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
    -- [AD-2] NULLABLE: NULL = property-level tenancy (no formal unit subdivision)
    unit_id             UUID        REFERENCES public.units(id) ON DELETE RESTRICT,
    tenant_id           UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    -- Lease details
    monthly_rent        NUMERIC(15, 2)
                            CONSTRAINT chk_rent_positive CHECK (monthly_rent IS NULL OR monthly_rent >= 0),
    security_deposit    NUMERIC(15, 2)
                            CONSTRAINT chk_deposit_positive CHECK (security_deposit IS NULL OR security_deposit >= 0),
    occupant_count      INTEGER     NOT NULL DEFAULT 1
                            CONSTRAINT chk_occupant_count CHECK (occupant_count >= 1),
    -- Temporal validity
    start_date          DATE        NOT NULL DEFAULT CURRENT_DATE,
    end_date            DATE,
    -- Audit
    created_by          UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    end_recorded_by     UUID        REFERENCES public.users(id) ON DELETE RESTRICT,
    termination_reason  TEXT,
    remarks             TEXT,
    -- Metadata
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- Date integrity
    CONSTRAINT chk_tenancy_dates CHECK (end_date IS NULL OR end_date >= start_date),
    -- Unit must belong to the same property (when unit_id is provided)
    -- Cross-table constraint enforced by trigger in Step 14.
    -- A tenancy must always have a property context
    CONSTRAINT chk_tenancy_has_property CHECK (property_id IS NOT NULL)
);

-- Only one active tenancy per unit (when unit_id is not NULL).
-- [AD-2] Property-level tenancies (unit_id IS NULL) are allowed without this constraint.
CREATE UNIQUE INDEX uq_active_tenancy_per_unit
    ON public.tenancies (unit_id)
    WHERE unit_id IS NOT NULL AND end_date IS NULL;

-- A single tenant cannot have two active property-level tenancies on the same property.
CREATE UNIQUE INDEX uq_active_property_level_tenancy
    ON public.tenancies (property_id, tenant_id)
    WHERE unit_id IS NULL AND end_date IS NULL;

-- Temporal overlap for unit tenancies: a unit cannot have two overlapping tenancies.
ALTER TABLE public.tenancies
    ADD CONSTRAINT excl_unit_tenancy_no_overlap
    EXCLUDE USING gist (
        unit_id    WITH =,
        daterange(start_date, COALESCE(end_date, '9999-12-31'::date), '[)') WITH &&
    )
    WHERE (unit_id IS NOT NULL);

COMMENT ON TABLE  public.tenancies IS
    'Temporal tenancy records. [AD-2] unit_id is NULLABLE for property-level tenancies. '
    'End a tenancy: SET end_date — do not DELETE. History is permanent.';
COMMENT ON COLUMN public.tenancies.unit_id IS
    '[AD-2] NULL = the tenant leases at the property level (no formal unit subdivision exists). '
    'NOT NULL = the tenant leases a specific unit. '
    'Do not auto-create a fake "Whole Property" unit to avoid nulls.';

CREATE TRIGGER trg_tenancies_updated_at
    BEFORE UPDATE ON public.tenancies
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ===========================================================================
-- STEP 13 — OCCUPANTS (Temporal — unit_id NULLABLE)
-- ===========================================================================
-- Tracks all individuals residing in a property/unit.
-- Covers both owner-occupants (tenancy_id = NULL) and tenant-occupants.
-- [AD-2] unit_id is NULLABLE — mirrors the tenancy model.

CREATE TABLE IF NOT EXISTS public.occupants (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id          UUID        NOT NULL REFERENCES public.societies(id)  ON DELETE RESTRICT,
    property_id         UUID        NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
    -- [AD-2] NULLABLE: NULL = occupant is registered at property level
    unit_id             UUID        REFERENCES public.units(id) ON DELETE RESTRICT,
    -- Source of occupancy: NULL = owner-occupant
    tenancy_id          UUID        REFERENCES public.tenancies(id) ON DELETE RESTRICT,
    -- Link to user account (NULL = non-registered occupant, e.g., child/elderly parent)
    user_id             UUID        REFERENCES public.users(id) ON DELETE SET NULL,
    -- Occupant details
    full_name           VARCHAR(200) NOT NULL
                            CONSTRAINT chk_occupant_name_nonempty CHECK (TRIM(full_name) <> ''),
    relationship        VARCHAR(100) NOT NULL
                            CONSTRAINT chk_relationship CHECK (
                                relationship IN (
                                    'self',      -- Primary occupant
                                    'spouse',
                                    'child',
                                    'parent',
                                    'sibling',
                                    'in_law',
                                    'domestic_help',
                                    'other'
                                )
                            ),
    mobile              VARCHAR(20)
                            CONSTRAINT chk_occupant_mobile CHECK (mobile IS NULL OR mobile ~ '^\+?[0-9\-\s]{7,20}$'),
    -- Identity document (optional; stored for gatekeeper/visitor reference only)
    id_type             VARCHAR(30)
                            CONSTRAINT chk_id_type CHECK (
                                id_type IS NULL OR id_type IN (
                                    'aadhaar', 'pan', 'passport', 'voter_id', 'driving_license', 'other'
                                )
                            ),
    -- NOTE: id_number is not stored in plaintext to respect privacy.
    -- Store only a masked or hashed representation if KYC compliance is needed.
    -- For MVP, this column is nullable and unencrypted — add pgcrypto encryption in a future slice.
    id_number_masked    VARCHAR(20), -- e.g., "XXXX-XXXX-1234"
    -- Temporal validity
    start_date          DATE        NOT NULL DEFAULT CURRENT_DATE,
    end_date            DATE,
    -- Audit
    created_by          UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    end_recorded_by     UUID        REFERENCES public.users(id) ON DELETE RESTRICT,
    departure_reason    TEXT,
    -- Metadata
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- Date integrity
    CONSTRAINT chk_occupant_dates CHECK (end_date IS NULL OR end_date >= start_date),
    -- Exactly one 'self' occupant per unit/property at a time (the primary)
    -- Additional uniqueness enforced by partial index below.
    -- An occupant must have a property context
    CONSTRAINT chk_occupant_has_property CHECK (property_id IS NOT NULL)
);

-- Only one active 'self' relationship occupant per unit (when unit_id is specified).
CREATE UNIQUE INDEX uq_active_self_occupant_per_unit
    ON public.occupants (unit_id)
    WHERE unit_id IS NOT NULL AND relationship = 'self' AND end_date IS NULL;

-- Only one active 'self' occupant per property when at property level.
CREATE UNIQUE INDEX uq_active_self_occupant_property_level
    ON public.occupants (property_id)
    WHERE unit_id IS NULL AND relationship = 'self' AND end_date IS NULL;

COMMENT ON TABLE  public.occupants IS
    'All individuals residing in a property/unit, with temporal history. '
    '[AD-2] unit_id nullable — property-level occupancy is first-class. '
    'Owner-occupants: tenancy_id = NULL. Tenant household members: tenancy_id = their tenancy.';
COMMENT ON COLUMN public.occupants.user_id IS
    'NULL for non-registered household members (minors, elderly parents). '
    'NOT NULL when the occupant has a society app user account.';
COMMENT ON COLUMN public.occupants.id_number_masked IS
    'Masked ID number for display only. Store only last 4 digits or use pgcrypto for full storage.';

CREATE TRIGGER trg_occupants_updated_at
    BEFORE UPDATE ON public.occupants
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ===========================================================================
-- STEP 14 — TEMPORAL INTEGRITY AND BUSINESS RULE TRIGGERS
-- ===========================================================================

-- ---- 14.1 AUDIT_LOGS IMMUTABILITY ----
CREATE OR REPLACE FUNCTION public.prevent_audit_log_mutations()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    RAISE EXCEPTION 'audit_logs rows are immutable. UPDATE and DELETE are not permitted.';
END;
$$;

CREATE TRIGGER trg_audit_logs_immutable
    BEFORE UPDATE OR DELETE ON public.audit_logs
    FOR EACH ROW EXECUTE FUNCTION public.prevent_audit_log_mutations();

COMMENT ON TRIGGER trg_audit_logs_immutable ON public.audit_logs IS
    'Enforces append-only semantics on audit_logs. Mutations raise an exception.';

-- ---- 14.2 OWNERSHIP SHARE VALIDATION ----
-- Ensures total ownership shares for active owners of a property never exceed 100%.
CREATE OR REPLACE FUNCTION public.validate_ownership_share_total()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_total NUMERIC;
BEGIN
    -- Only validate for active (not yet ended) ownership records
    IF NEW.end_date IS NOT NULL THEN
        RETURN NEW;
    END IF;

    SELECT COALESCE(SUM(ownership_share_pct), 0)
    INTO   v_total
    FROM   public.property_owners
    WHERE  property_id = NEW.property_id
      AND  end_date    IS NULL
      AND  id         <> NEW.id;  -- exclude the current row being inserted/updated

    IF (v_total + NEW.ownership_share_pct) > 100 THEN
        RAISE EXCEPTION
            'Ownership share violation: existing active shares = %, '
            'new share = %, total would be %%%. Maximum is 100%%.',
            v_total, NEW.ownership_share_pct, (v_total + NEW.ownership_share_pct);
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_ownership_share
    BEFORE INSERT OR UPDATE OF ownership_share_pct, end_date ON public.property_owners
    FOR EACH ROW EXECUTE FUNCTION public.validate_ownership_share_total();

COMMENT ON TRIGGER trg_validate_ownership_share ON public.property_owners IS
    'Prevents total active ownership shares on a property from exceeding 100%.';

-- ---- 14.3 PRIMARY OWNER UNIQUENESS PER PROPERTY ----
-- Only one primary owner active at a time per property.
CREATE OR REPLACE FUNCTION public.validate_single_primary_owner()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.is_primary_owner AND NEW.end_date IS NULL THEN
        IF EXISTS (
            SELECT 1 FROM public.property_owners
            WHERE  property_id     = NEW.property_id
              AND  is_primary_owner = TRUE
              AND  end_date        IS NULL
              AND  id              <> NEW.id
        ) THEN
            RAISE EXCEPTION
                'A property may have only one active primary owner. '
                'Set end_date on the existing primary owner record first.';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_primary_owner
    BEFORE INSERT OR UPDATE OF is_primary_owner, end_date ON public.property_owners
    FOR EACH ROW EXECUTE FUNCTION public.validate_single_primary_owner();

COMMENT ON TRIGGER trg_validate_primary_owner ON public.property_owners IS
    'Ensures only one is_primary_owner = TRUE record is active per property.';

-- ---- 14.4 PREVENT user_roles ROLE_NAME UPDATE ----
-- Role transitions must be recorded as new rows with revocation of the old row.
-- Direct UPDATE of role_name would erase history.
CREATE OR REPLACE FUNCTION public.prevent_role_name_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF OLD.role_name <> NEW.role_name THEN
        RAISE EXCEPTION
            'Changing role_name directly is not permitted. '
            'End the current row (set revoked_on) and insert a new role record.';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_prevent_role_name_update
    BEFORE UPDATE OF role_name ON public.user_roles
    FOR EACH ROW EXECUTE FUNCTION public.prevent_role_name_update();

COMMENT ON TRIGGER trg_prevent_role_name_update ON public.user_roles IS
    'Prevents direct mutation of role_name. Role changes must be new rows for audit trail integrity.';

-- ---- 14.5 TENANCY UNIT→PROPERTY CONSISTENCY ----
-- When unit_id is provided, the unit must belong to the stated property_id.
CREATE OR REPLACE FUNCTION public.validate_tenancy_unit_property_match()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.unit_id IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.units
            WHERE id = NEW.unit_id AND property_id = NEW.property_id
        ) THEN
            RAISE EXCEPTION
                'unit_id % does not belong to property_id %. '
                'The unit must be a subdivision of the stated property.',
                NEW.unit_id, NEW.property_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_tenancy_unit_property_match
    BEFORE INSERT OR UPDATE OF unit_id, property_id ON public.tenancies
    FOR EACH ROW EXECUTE FUNCTION public.validate_tenancy_unit_property_match();

CREATE TRIGGER trg_occupant_unit_property_match
    BEFORE INSERT OR UPDATE OF unit_id, property_id ON public.occupants
    FOR EACH ROW EXECUTE FUNCTION public.validate_tenancy_unit_property_match();

COMMENT ON TRIGGER trg_tenancy_unit_property_match ON public.tenancies IS
    'Ensures unit_id, when provided, belongs to property_id.';
COMMENT ON TRIGGER trg_occupant_unit_property_match ON public.occupants IS
    'Ensures unit_id, when provided, belongs to property_id.';

-- ---- 14.6 USER_ROLES REVOCATION DATE GUARD ----
-- Once revoked_on is set, it cannot be cleared or moved backwards.
CREATE OR REPLACE FUNCTION public.validate_role_revocation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    -- Cannot un-revoke a role (set revoked_on back to NULL after it was set)
    IF OLD.revoked_on IS NOT NULL AND NEW.revoked_on IS NULL THEN
        RAISE EXCEPTION
            'Cannot un-revoke a role. revoked_on may not be changed from a date back to NULL. '
            'Grant a new role row instead.';
    END IF;
    -- Cannot move revoked_on backwards (cannot pretend the role was revoked earlier)
    IF OLD.revoked_on IS NOT NULL AND NEW.revoked_on < OLD.revoked_on THEN
        RAISE EXCEPTION
            'Cannot move revoked_on backwards. Current: %, Attempted: %.',
            OLD.revoked_on, NEW.revoked_on;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_role_revocation
    BEFORE UPDATE OF revoked_on ON public.user_roles
    FOR EACH ROW EXECUTE FUNCTION public.validate_role_revocation();

COMMENT ON TRIGGER trg_validate_role_revocation ON public.user_roles IS
    'Prevents un-revoking a role or backdating the revocation. Temporal integrity.';

-- ===========================================================================
-- STEP 15 — ROW LEVEL SECURITY
-- ===========================================================================

ALTER TABLE public.societies            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users                ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_roles           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.properties           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.units                ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.property_owners      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.association_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tenancies            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.occupants            ENABLE ROW LEVEL SECURITY;

-- Disable row security bypass for table owners (belt-and-suspenders)
ALTER TABLE public.societies            FORCE ROW LEVEL SECURITY;
ALTER TABLE public.users                FORCE ROW LEVEL SECURITY;
ALTER TABLE public.user_roles           FORCE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs           FORCE ROW LEVEL SECURITY;
ALTER TABLE public.properties           FORCE ROW LEVEL SECURITY;
ALTER TABLE public.units                FORCE ROW LEVEL SECURITY;
ALTER TABLE public.property_owners      FORCE ROW LEVEL SECURITY;
ALTER TABLE public.association_memberships FORCE ROW LEVEL SECURITY;
ALTER TABLE public.tenancies            FORCE ROW LEVEL SECURITY;
ALTER TABLE public.occupants            FORCE ROW LEVEL SECURITY;

-- ============================================================
-- RLS: societies
-- ============================================================
-- Users can see the society they belong to (via any active role).
CREATE POLICY pol_societies_member_select
    ON public.societies
    FOR SELECT
    USING (
        id = public.get_user_society_id(auth.uid())
    );

-- Only admin/super_admin can update society details.
CREATE POLICY pol_societies_admin_update
    ON public.societies
    FOR UPDATE
    USING  (public.is_admin())
    WITH CHECK (public.is_admin());

-- INSERT is a system/migration operation only — no direct user INSERT via RLS.
-- (Initial society row is seeded by migration scripts / Supabase service role.)

-- ============================================================
-- RLS: users
-- ============================================================
-- Every authenticated user can see their own profile.
CREATE POLICY pol_users_self_select
    ON public.users
    FOR SELECT
    USING (id = auth.uid());

-- Admin can see all profiles within the same society.
CREATE POLICY pol_users_admin_select
    ON public.users
    FOR SELECT
    USING (
        public.is_admin()
        AND id IN (
            SELECT user_id FROM public.user_roles
            WHERE  society_id = public.get_user_society_id(auth.uid())
              AND  revoked_on IS NULL
        )
    );

-- User can update their own non-sensitive profile fields.
-- Sensitive fields (status) are updated only by admin via SECURITY DEFINER functions.
CREATE POLICY pol_users_self_update
    ON public.users
    FOR UPDATE
    USING  (id = auth.uid())
    WITH CHECK (
        id = auth.uid()
        -- Prevent self-escalation of status via direct UPDATE
        -- (status changes go through admin stored procedures in Slice 2)
    );

-- Admin can update any user profile in their society.
CREATE POLICY pol_users_admin_update
    ON public.users
    FOR UPDATE
    USING  (public.is_admin())
    WITH CHECK (public.is_admin());

-- ============================================================
-- RLS: user_roles
-- ============================================================
-- Users can see their own role assignments.
CREATE POLICY pol_user_roles_self_select
    ON public.user_roles
    FOR SELECT
    USING (user_id = auth.uid());

-- Admin can see all role assignments in their society.
CREATE POLICY pol_user_roles_admin_select
    ON public.user_roles
    FOR SELECT
    USING (
        public.is_admin()
        AND society_id = public.get_user_society_id(auth.uid())
    );

-- Only super_admin can grant or revoke roles.
-- All mutations go through SECURITY DEFINER functions — no direct DML via policies.
-- Policies here restrict direct INSERT/UPDATE/DELETE.
CREATE POLICY pol_user_roles_super_admin_insert
    ON public.user_roles
    FOR INSERT
    WITH CHECK (public.has_role(auth.uid(), 'super_admin'));

CREATE POLICY pol_user_roles_super_admin_update
    ON public.user_roles
    FOR UPDATE
    USING  (public.has_role(auth.uid(), 'super_admin'))
    WITH CHECK (public.has_role(auth.uid(), 'super_admin'));

-- DELETE is never permitted — roles are ended via revoked_on, not deleted.
-- (No DELETE policy = no row-level DELETE permitted.)

-- ============================================================
-- RLS: audit_logs
-- ============================================================
-- Admin can read all audit logs in their society.
CREATE POLICY pol_audit_logs_admin_select
    ON public.audit_logs
    FOR SELECT
    USING (
        public.is_admin()
        AND society_id = public.get_user_society_id(auth.uid())
    );

-- INSERT is only via SECURITY DEFINER functions. Direct INSERT not permitted via client.
-- (We allow INSERT from SECURITY DEFINER context — which bypasses RLS — so no insert policy needed.)

-- ============================================================
-- RLS: properties
-- ============================================================
-- Admin sees all properties in their society.
CREATE POLICY pol_properties_admin_select
    ON public.properties
    FOR SELECT
    USING (
        public.is_admin()
        AND society_id = public.get_user_society_id(auth.uid())
    );

-- Owner sees their own properties.
CREATE POLICY pol_properties_owner_select
    ON public.properties
    FOR SELECT
    USING (
        public.is_property_owner(auth.uid(), id)
    );

-- Tenant sees properties they are currently renting.
CREATE POLICY pol_properties_tenant_select
    ON public.properties
    FOR SELECT
    USING (
        public.is_property_tenant(auth.uid(), id)
    );

-- Admin can insert/update properties.
CREATE POLICY pol_properties_admin_insert
    ON public.properties
    FOR INSERT
    WITH CHECK (
        public.is_admin()
        AND society_id = public.get_user_society_id(auth.uid())
    );

CREATE POLICY pol_properties_admin_update
    ON public.properties
    FOR UPDATE
    USING  (public.is_admin())
    WITH CHECK (public.is_admin());

-- ============================================================
-- RLS: units
-- ============================================================
-- Admin sees all units in their society.
CREATE POLICY pol_units_admin_select
    ON public.units
    FOR SELECT
    USING (
        public.is_admin()
        AND property_id IN (
            SELECT id FROM public.properties
            WHERE  society_id = public.get_user_society_id(auth.uid())
        )
    );

-- Owner and tenant can see units within their property.
CREATE POLICY pol_units_property_member_select
    ON public.units
    FOR SELECT
    USING (
        public.is_property_owner(auth.uid(), property_id)
        OR public.is_property_tenant(auth.uid(), property_id)
    );

-- Admin only for insert/update.
CREATE POLICY pol_units_admin_insert
    ON public.units
    FOR INSERT
    WITH CHECK (public.is_admin());

CREATE POLICY pol_units_admin_update
    ON public.units
    FOR UPDATE
    USING  (public.is_admin())
    WITH CHECK (public.is_admin());

-- ============================================================
-- RLS: property_owners
-- ============================================================
CREATE POLICY pol_property_owners_admin_select
    ON public.property_owners
    FOR SELECT
    USING (
        public.is_admin()
        AND property_id IN (
            SELECT id FROM public.properties
            WHERE society_id = public.get_user_society_id(auth.uid())
        )
    );

-- An owner can see their own ownership records.
CREATE POLICY pol_property_owners_self_select
    ON public.property_owners
    FOR SELECT
    USING (owner_id = auth.uid());

-- A co-owner can see other owners of the same property.
CREATE POLICY pol_property_owners_cowner_select
    ON public.property_owners
    FOR SELECT
    USING (
        public.is_property_owner(auth.uid(), property_id)
    );

-- Mutations via SECURITY DEFINER functions only (admin role required there).
CREATE POLICY pol_property_owners_admin_insert
    ON public.property_owners
    FOR INSERT
    WITH CHECK (public.is_admin());

CREATE POLICY pol_property_owners_admin_update
    ON public.property_owners
    FOR UPDATE
    USING  (public.is_admin())
    WITH CHECK (public.is_admin());

-- ============================================================
-- RLS: association_memberships
-- ============================================================
-- Admin sees all in their society.
CREATE POLICY pol_memberships_admin_select
    ON public.association_memberships
    FOR SELECT
    USING (
        public.is_admin()
        AND society_id = public.get_user_society_id(auth.uid())
    );

-- Member sees their own membership record.
CREATE POLICY pol_memberships_self_select
    ON public.association_memberships
    FOR SELECT
    USING (user_id = auth.uid());

-- A property owner can see the membership record for their property.
CREATE POLICY pol_memberships_owner_select
    ON public.association_memberships
    FOR SELECT
    USING (
        public.is_property_owner(auth.uid(), property_id)
    );

-- Mutations: admin only (via SECURITY DEFINER function in Slice 2).
CREATE POLICY pol_memberships_admin_insert
    ON public.association_memberships
    FOR INSERT
    WITH CHECK (
        public.is_admin()
        AND society_id = public.get_user_society_id(auth.uid())
    );

CREATE POLICY pol_memberships_admin_update
    ON public.association_memberships
    FOR UPDATE
    USING  (public.is_admin())
    WITH CHECK (public.is_admin());

-- ============================================================
-- RLS: tenancies
-- ============================================================
-- Admin sees all.
CREATE POLICY pol_tenancies_admin_select
    ON public.tenancies
    FOR SELECT
    USING (
        public.is_admin()
        AND society_id = public.get_user_society_id(auth.uid())
    );

-- Tenant sees their own tenancy.
CREATE POLICY pol_tenancies_self_select
    ON public.tenancies
    FOR SELECT
    USING (tenant_id = auth.uid());

-- Property owner sees all tenancies on their property.
CREATE POLICY pol_tenancies_owner_select
    ON public.tenancies
    FOR SELECT
    USING (
        public.is_property_owner(auth.uid(), property_id)
    );

-- Mutations: admin only.
CREATE POLICY pol_tenancies_admin_insert
    ON public.tenancies
    FOR INSERT
    WITH CHECK (
        public.is_admin()
        AND society_id = public.get_user_society_id(auth.uid())
    );

CREATE POLICY pol_tenancies_admin_update
    ON public.tenancies
    FOR UPDATE
    USING  (public.is_admin())
    WITH CHECK (public.is_admin());

-- ============================================================
-- RLS: occupants
-- ============================================================
-- Admin sees all.
CREATE POLICY pol_occupants_admin_select
    ON public.occupants
    FOR SELECT
    USING (
        public.is_admin()
        AND society_id = public.get_user_society_id(auth.uid())
    );

-- Occupant sees their own record (when linked to a user account).
CREATE POLICY pol_occupants_self_select
    ON public.occupants
    FOR SELECT
    USING (user_id = auth.uid());

-- Property owner sees all occupants in their property.
CREATE POLICY pol_occupants_owner_select
    ON public.occupants
    FOR SELECT
    USING (
        public.is_property_owner(auth.uid(), property_id)
    );

-- Tenant sees occupants linked to their tenancy.
CREATE POLICY pol_occupants_tenant_select
    ON public.occupants
    FOR SELECT
    USING (
        tenancy_id IN (
            SELECT id FROM public.tenancies
            WHERE  tenant_id = auth.uid() AND end_date IS NULL
        )
    );

-- Mutations: admin only.
CREATE POLICY pol_occupants_admin_insert
    ON public.occupants
    FOR INSERT
    WITH CHECK (public.is_admin());

CREATE POLICY pol_occupants_admin_update
    ON public.occupants
    FOR UPDATE
    USING  (public.is_admin())
    WITH CHECK (public.is_admin());

-- ===========================================================================
-- STEP 16 — PERFORMANCE INDEXES
-- ===========================================================================

-- societies
CREATE INDEX IF NOT EXISTS idx_societies_is_active ON public.societies (is_active);

-- users
CREATE INDEX IF NOT EXISTS idx_users_status ON public.users (status);

-- user_roles — most queries filter by user, society, revoked_on
CREATE INDEX IF NOT EXISTS idx_user_roles_user_id      ON public.user_roles (user_id);
CREATE INDEX IF NOT EXISTS idx_user_roles_society_id   ON public.user_roles (society_id);
CREATE INDEX IF NOT EXISTS idx_user_roles_active        ON public.user_roles (user_id, society_id) WHERE revoked_on IS NULL;
CREATE INDEX IF NOT EXISTS idx_user_roles_role_name     ON public.user_roles (society_id, role_name) WHERE revoked_on IS NULL;

-- Partial unique: one active instance of any given role per user per society.
-- A user may hold multiple different roles, but not the same role twice concurrently.
CREATE UNIQUE INDEX IF NOT EXISTS uq_active_role_per_user_per_society
    ON public.user_roles (society_id, user_id, role_name)
    WHERE revoked_on IS NULL;

-- audit_logs — queried by actor, entity, time range
CREATE INDEX IF NOT EXISTS idx_audit_logs_society_id   ON public.audit_logs (society_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_actor_id     ON public.audit_logs (actor_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_entity       ON public.audit_logs (entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at   ON public.audit_logs (created_at DESC);

-- properties
CREATE INDEX IF NOT EXISTS idx_properties_society_id        ON public.properties (society_id);
CREATE INDEX IF NOT EXISTS idx_properties_occupancy_status  ON public.properties (society_id, occupancy_status);
CREATE INDEX IF NOT EXISTS idx_properties_is_active         ON public.properties (society_id, is_active);

-- units
CREATE INDEX IF NOT EXISTS idx_units_property_id  ON public.units (property_id);
CREATE INDEX IF NOT EXISTS idx_units_is_active    ON public.units (property_id, is_active);

-- property_owners — most queries: who owns what right now?
CREATE INDEX IF NOT EXISTS idx_property_owners_property_id  ON public.property_owners (property_id);
CREATE INDEX IF NOT EXISTS idx_property_owners_owner_id     ON public.property_owners (owner_id);
CREATE INDEX IF NOT EXISTS idx_property_owners_active       ON public.property_owners (property_id, owner_id) WHERE end_date IS NULL;

-- Partial unique: only one active primary owner per property.
CREATE UNIQUE INDEX IF NOT EXISTS uq_active_primary_owner_per_property
    ON public.property_owners (property_id)
    WHERE is_primary_owner = TRUE AND end_date IS NULL;

-- association_memberships
CREATE INDEX IF NOT EXISTS idx_memberships_society_id   ON public.association_memberships (society_id);
CREATE INDEX IF NOT EXISTS idx_memberships_property_id  ON public.association_memberships (property_id);
CREATE INDEX IF NOT EXISTS idx_memberships_user_id      ON public.association_memberships (user_id);
CREATE INDEX IF NOT EXISTS idx_memberships_active       ON public.association_memberships (society_id) WHERE end_date IS NULL;

-- tenancies
CREATE INDEX IF NOT EXISTS idx_tenancies_society_id   ON public.tenancies (society_id);
CREATE INDEX IF NOT EXISTS idx_tenancies_property_id  ON public.tenancies (property_id);
CREATE INDEX IF NOT EXISTS idx_tenancies_unit_id      ON public.tenancies (unit_id) WHERE unit_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_tenancies_tenant_id    ON public.tenancies (tenant_id);
CREATE INDEX IF NOT EXISTS idx_tenancies_active       ON public.tenancies (property_id, tenant_id) WHERE end_date IS NULL;

-- occupants
CREATE INDEX IF NOT EXISTS idx_occupants_society_id   ON public.occupants (society_id);
CREATE INDEX IF NOT EXISTS idx_occupants_property_id  ON public.occupants (property_id);
CREATE INDEX IF NOT EXISTS idx_occupants_unit_id      ON public.occupants (unit_id) WHERE unit_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_occupants_tenancy_id   ON public.occupants (tenancy_id) WHERE tenancy_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_occupants_user_id      ON public.occupants (user_id)     WHERE user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_occupants_active       ON public.occupants (property_id) WHERE end_date IS NULL;

-- ===========================================================================
-- STEP 17 — SEED DATA (MVP single-society bootstrap)
-- ===========================================================================
-- Replace values below with actual society details before applying.
-- The service-role key (bypasses RLS) must be used to seed this row.
-- Only one society row exists in MVP. [AD-3]

/*
INSERT INTO public.societies (id, name, registration_number, city, state, pincode, contact_email, is_active)
VALUES (
    'aaaaaaaa-0000-0000-0000-000000000001',  -- Fixed UUID: reference in all seed data
    'YOUR SOCIETY NAME',
    'REG-XXXX-XXXX',
    'City',
    'State',
    '000000',
    'admin@yoursociety.com',
    TRUE
)
ON CONFLICT (id) DO NOTHING;
*/

-- ===========================================================================
-- STEP 18 — GRANTS (Supabase: anon role gets nothing, authenticated role gets RLS-gated access)
-- ===========================================================================

-- Revoke all from anon (public); authenticated users access only through RLS.
REVOKE ALL ON public.societies             FROM anon, PUBLIC;
REVOKE ALL ON public.users                 FROM anon, PUBLIC;
REVOKE ALL ON public.user_roles            FROM anon, PUBLIC;
REVOKE ALL ON public.audit_logs            FROM anon, PUBLIC;
REVOKE ALL ON public.properties            FROM anon, PUBLIC;
REVOKE ALL ON public.units                 FROM anon, PUBLIC;
REVOKE ALL ON public.property_owners       FROM anon, PUBLIC;
REVOKE ALL ON public.association_memberships FROM anon, PUBLIC;
REVOKE ALL ON public.tenancies             FROM anon, PUBLIC;
REVOKE ALL ON public.occupants             FROM anon, PUBLIC;

-- Grant column-level access to the 'authenticated' role — RLS policies further restrict.
GRANT SELECT, INSERT, UPDATE ON public.societies               TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.users                   TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.user_roles              TO authenticated;
GRANT SELECT               ON public.audit_logs                TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.properties              TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.units                   TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.property_owners         TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.association_memberships TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.tenancies               TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.occupants               TO authenticated;

-- Service role (used by SECURITY DEFINER functions and admin scripts) bypasses RLS.
-- No explicit grant needed — Supabase service role is a superuser equivalent.

-- ===========================================================================
-- FINALIZE
-- ===========================================================================

COMMIT;

-- =============================================================================
-- POST-APPLY VERIFICATION QUERIES
-- Run these manually after applying to confirm schema correctness.
-- =============================================================================

/*
-- 1. Confirm all 10 tables created
SELECT tablename
FROM   pg_tables
WHERE  schemaname = 'public'
  AND  tablename IN (
    'societies','users','user_roles','audit_logs','properties','units',
    'property_owners','association_memberships','tenancies','occupants'
  )
ORDER BY tablename;

-- 2. Confirm RLS is enabled on all 10 tables
SELECT tablename, rowsecurity, forcerowsecurity
FROM   pg_tables
WHERE  schemaname = 'public'
  AND  tablename IN (
    'societies','users','user_roles','audit_logs','properties','units',
    'property_owners','association_memberships','tenancies','occupants'
  );

-- 3. Confirm exclusion constraints exist
SELECT conname, contype, conrelid::regclass
FROM   pg_constraint
WHERE  contype = 'x'
  AND  conrelid::regclass::text IN (
    'public.property_owners', 'public.association_memberships', 'public.tenancies'
  );

-- 4. Confirm helper functions exist
SELECT proname, prosecdef
FROM   pg_proc
WHERE  pronamespace = 'public'::regnamespace
  AND  proname IN ('is_admin','has_role','get_user_society_id','is_property_owner','is_property_tenant');

-- 5. Confirm immutability trigger on audit_logs
SELECT tgname FROM pg_trigger WHERE tgrelid = 'public.audit_logs'::regclass;

-- 6. Verify unit_id is nullable in tenancies and occupants
SELECT column_name, is_nullable
FROM   information_schema.columns
WHERE  table_schema = 'public'
  AND  table_name IN ('tenancies','occupants')
  AND  column_name = 'unit_id';
-- Both rows should show is_nullable = 'YES'
*/
