-- ============================================================================
-- SLICE 23 SCHEMA — DIGITAL DOCUMENT VAULT & CONFIDENTIALITY AUTHORIZATION SYSTEM
-- Target Repository: SU Society App
-- Authoritative Plan: Revision 3 Final Architecture Specification
-- Governance Baseline: 856 / 856 PASS (LOCKED / IMMUTABLE)
-- Target Cumulative Baseline: 856 + 75 = 931 PASS
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. HELPER VALIDATION FUNCTIONS
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_is_valid_vault_storage_path(p_path TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
    IF p_path IS NULL OR length(p_path) < 10 THEN
        RETURN FALSE;
    END IF;
    -- Path must match pattern: {society_id}/{document_id}/v{version_number}_{hash}.bin
    -- Prevent path traversal characters
    IF p_path LIKE '%..%' OR p_path LIKE '%\%' OR p_path LIKE '%//%' THEN
        RETURN FALSE;
    END IF;
    RETURN p_path ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/v[0-9]+_[a-zA-Z0-9_-]+\.bin$';
END;
$$;

REVOKE EXECUTE ON FUNCTION public.fn_is_valid_vault_storage_path(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_is_valid_vault_storage_path(TEXT) TO authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 2. DOMAIN TABLES
-- ----------------------------------------------------------------------------

-- Table 1: Master Vault Documents
CREATE TABLE IF NOT EXISTS public.vault_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE,
    property_id UUID NULL REFERENCES public.properties(id) ON DELETE SET NULL,
    title VARCHAR(255) NOT NULL CHECK (length(trim(title)) >= 3),
    classification VARCHAR(50) NOT NULL CHECK (
        classification IN (
            'public_society',
            'resident_visible',
            'owner_confidential',
            'tenant_confidential',
            'committee_confidential',
            'admin_confidential',
            'strictly_restricted'
        )
    ),
    status VARCHAR(50) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'archived', 'deleted')),
    created_by UUID NOT NULL REFERENCES public.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Table 2: Document Versions (Append-Only Payloads)
CREATE TABLE IF NOT EXISTS public.vault_document_versions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id UUID NOT NULL REFERENCES public.vault_documents(id) ON DELETE CASCADE,
    version_number INT NOT NULL CHECK (version_number >= 1),
    storage_path TEXT NOT NULL UNIQUE CHECK (public.fn_is_valid_vault_storage_path(storage_path)),
    file_name VARCHAR(255) NOT NULL CHECK (length(trim(file_name)) >= 1),
    file_size_bytes BIGINT NOT NULL CHECK (file_size_bytes > 0 AND file_size_bytes <= 52428800), -- Max 50MB
    mime_type VARCHAR(100) NOT NULL CHECK (length(trim(mime_type)) >= 3),
    sha256_hash VARCHAR(64) NULL CHECK (sha256_hash IS NULL OR sha256_hash ~ '^[0-9a-fA-F]{64}$'),
    status VARCHAR(50) NOT NULL DEFAULT 'UPLOAD_INITIATED' CHECK (
        status IN (
            'UPLOAD_INITIATED',
            'UPLOADED',
            'VALIDATING',
            'ACTIVE',
            'SUPERSEDED',
            'VERIFICATION_FAILED',
            'ARCHIVED',
            'DELETED'
        )
    ),
    uploaded_by UUID NOT NULL REFERENCES public.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_vault_document_version UNIQUE (document_id, version_number)
);

-- Table 3: Explicit Access Grants
CREATE TABLE IF NOT EXISTS public.vault_access_grants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id UUID NOT NULL REFERENCES public.vault_documents(id) ON DELETE CASCADE,
    grantee_type VARCHAR(50) NOT NULL CHECK (grantee_type IN ('user', 'role', 'property')),
    grantee_user_id UUID NULL REFERENCES public.users(id) ON DELETE CASCADE,
    grantee_role VARCHAR(50) NULL CHECK (grantee_role IN ('admin', 'resident', 'owner', 'tenant', 'committee', 'technician', 'gatekeeper')),
    grantee_property_id UUID NULL REFERENCES public.properties(id) ON DELETE CASCADE,
    granted_by UUID NOT NULL REFERENCES public.users(id),
    granted_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMPTZ NULL,
    revoked_at TIMESTAMPTZ NULL,
    revoked_by UUID NULL REFERENCES public.users(id),
    CONSTRAINT chk_vault_grant_expiry CHECK (expires_at IS NULL OR expires_at > granted_at),
    CONSTRAINT chk_vault_grant_revoked CHECK (revoked_at IS NULL OR revoked_at >= granted_at),
    CONSTRAINT chk_vault_grant_target CHECK (
        (grantee_type = 'user' AND grantee_user_id IS NOT NULL AND grantee_role IS NULL AND grantee_property_id IS NULL) OR
        (grantee_type = 'role' AND grantee_role IS NOT NULL AND grantee_user_id IS NULL AND grantee_property_id IS NULL) OR
        (grantee_type = 'property' AND grantee_property_id IS NOT NULL AND grantee_user_id IS NULL AND grantee_role IS NULL)
    )
);

-- Table 4: Audit Logs (Append-Only Security Audit Evidence)
CREATE TABLE IF NOT EXISTS public.vault_audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE,
    document_id UUID NULL REFERENCES public.vault_documents(id) ON DELETE SET NULL,
    version_id UUID NULL REFERENCES public.vault_document_versions(id) ON DELETE SET NULL,
    user_id UUID NOT NULL REFERENCES public.users(id),
    event_type VARCHAR(100) NOT NULL,
    details JSONB NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Table 5: Transactional Rate Limits
CREATE TABLE IF NOT EXISTS public.vault_rate_limits (
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    rate_type VARCHAR(50) NOT NULL CHECK (rate_type IN ('upload', 'download_url')),
    window_start TIMESTAMPTZ NOT NULL,
    request_count INT NOT NULL DEFAULT 1 CHECK (request_count >= 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, rate_type, window_start)
);


-- ----------------------------------------------------------------------------
-- 3. INDEXES
-- ----------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_vault_documents_society_status ON public.vault_documents(society_id, status);
CREATE INDEX IF NOT EXISTS idx_vault_documents_property ON public.vault_documents(property_id);
CREATE INDEX IF NOT EXISTS idx_vault_versions_doc_ver ON public.vault_document_versions(document_id, version_number DESC);
CREATE INDEX IF NOT EXISTS idx_vault_versions_status ON public.vault_document_versions(status);
CREATE INDEX IF NOT EXISTS idx_vault_versions_storage_path ON public.vault_document_versions(storage_path);
CREATE INDEX IF NOT EXISTS idx_vault_grants_doc_grantee ON public.vault_access_grants(document_id, grantee_type, grantee_user_id, grantee_role, grantee_property_id);
CREATE INDEX IF NOT EXISTS idx_vault_audit_doc ON public.vault_audit_logs(document_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_vault_rate_limits_lookup ON public.vault_rate_limits(user_id, rate_type, window_start);


-- ----------------------------------------------------------------------------
-- 4. ROW LEVEL SECURITY (RLS) FOR DOMAIN TABLES
-- ----------------------------------------------------------------------------

ALTER TABLE public.vault_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vault_document_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vault_access_grants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vault_audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vault_rate_limits ENABLE ROW LEVEL SECURITY;

-- 1. vault_documents SELECT policy (Society Isolation)
DROP POLICY IF EXISTS pol_vault_documents_select ON public.vault_documents;
CREATE POLICY pol_vault_documents_select ON public.vault_documents
    FOR SELECT TO authenticated
    USING (society_id = public.get_user_society_id(auth.uid()));

-- 2. vault_document_versions SELECT policy
DROP POLICY IF EXISTS pol_vault_versions_select ON public.vault_document_versions;
CREATE POLICY pol_vault_versions_select ON public.vault_document_versions
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.vault_documents d
            WHERE d.id = document_id
              AND d.society_id = public.get_user_society_id(auth.uid())
        )
    );

-- 3. vault_access_grants SELECT policy
DROP POLICY IF EXISTS pol_vault_grants_select ON public.vault_access_grants;
CREATE POLICY pol_vault_grants_select ON public.vault_access_grants
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.vault_documents d
            WHERE d.id = document_id
              AND d.society_id = public.get_user_society_id(auth.uid())
        )
    );

-- 4. vault_audit_logs SELECT policy
DROP POLICY IF EXISTS pol_vault_audit_select ON public.vault_audit_logs;
CREATE POLICY pol_vault_audit_select ON public.vault_audit_logs
    FOR SELECT TO authenticated
    USING (
        society_id = public.get_user_society_id(auth.uid())
        AND (public.is_admin() OR user_id = auth.uid())
    );

-- 5. vault_rate_limits Policy (Clients blocked from direct querying)
DROP POLICY IF EXISTS pol_vault_rate_limits_none ON public.vault_rate_limits;
CREATE POLICY pol_vault_rate_limits_none ON public.vault_rate_limits
    FOR ALL TO authenticated
    USING (FALSE);


-- ----------------------------------------------------------------------------
-- 5. PRIVATE STORAGE BUCKET & STORAGE RLS POLICIES
-- ----------------------------------------------------------------------------

-- Ensure storage schema & objects table exist before defining policies
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'storage' AND table_name = 'buckets') THEN
        INSERT INTO storage.buckets (id, name, public) 
        VALUES ('society-vault-private', 'society-vault-private', FALSE)
        ON CONFLICT (id) DO UPDATE SET public = FALSE;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'storage' AND table_name = 'objects') THEN
        -- Storage SELECT Policy: Block direct client reads (Signed URLs required)
        DROP POLICY IF EXISTS pol_storage_vault_select ON storage.objects;
        CREATE POLICY pol_storage_vault_select ON storage.objects
            FOR SELECT TO authenticated
            USING (FALSE);

        -- Storage INSERT Policy: Exact Relational Path Binding
        DROP POLICY IF EXISTS pol_storage_vault_insert ON storage.objects;
        CREATE POLICY pol_storage_vault_insert ON storage.objects
            FOR INSERT TO authenticated
            WITH CHECK (
                bucket_id = 'society-vault-private'
                AND name = (
                    SELECT v.storage_path
                    FROM public.vault_document_versions v
                    JOIN public.vault_documents d ON d.id = v.document_id
                    WHERE v.storage_path = storage.objects.name
                      AND v.status = 'UPLOAD_INITIATED'
                      AND d.society_id = public.get_user_society_id(auth.uid())
                      AND (public.is_admin() OR d.created_by = auth.uid())
                )
            );

        -- Storage UPDATE Policy: Prohibit object updates (Immutable Storage)
        DROP POLICY IF EXISTS pol_storage_vault_update ON storage.objects;
        CREATE POLICY pol_storage_vault_update ON storage.objects
            FOR UPDATE TO authenticated
            USING (FALSE);

        -- Storage DELETE Policy: Prohibit direct client payload deletion
        DROP POLICY IF EXISTS pol_storage_vault_delete ON storage.objects;
        CREATE POLICY pol_storage_vault_delete ON storage.objects
            FOR DELETE TO authenticated
            USING (FALSE);
    END IF;
END $$;


-- ----------------------------------------------------------------------------
-- 6. DETERMINISTIC ACCESS-GRANT RESOLUTION HELPER FUNCTION
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_resolve_document_access(
    p_doc_id UUID,
    p_caller_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_society_id UUID;
    v_status VARCHAR(50);
    v_classification VARCHAR(50);
    v_property_id UUID;
    v_created_by UUID;
    v_caller_society_id UUID;
    v_is_admin BOOLEAN;
    v_has_expired_user_grant BOOLEAN := FALSE;
    v_user_roles TEXT[];
    v_user_props UUID[];
BEGIN
    -- 1. Fetch document metadata
    SELECT society_id, status, classification, property_id, created_by
    INTO v_society_id, v_status, v_classification, v_property_id, v_created_by
    FROM public.vault_documents
    WHERE id = p_doc_id;

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    -- 2. Check society boundary
    v_caller_society_id := public.get_user_society_id(p_caller_id);
    IF v_society_id IS DISTINCT FROM v_caller_society_id THEN
        RETURN FALSE;
    END IF;

    -- Check admin status
    v_is_admin := public.is_admin();

    -- 3. Document status check: if not active and caller is not admin, deny
    IF v_status NOT IN ('active') AND NOT v_is_admin THEN
        RETURN FALSE;
    END IF;

    -- 4. RULE 1: EXPLICIT DIRECT REVOCATION (Overrides Admin, Creator, Roles, Tiers)
    IF EXISTS (
        SELECT 1 FROM public.vault_access_grants
        WHERE document_id = p_doc_id
          AND grantee_type = 'user'
          AND grantee_user_id = p_caller_id
          AND revoked_at IS NOT NULL
    ) THEN
        RETURN FALSE;
    END IF;

    -- 5. RULE 2: EXPLICIT USER GRANT EXPIRATION (Denies User Grant Only; Fallback Allowed)
    v_has_expired_user_grant := EXISTS (
        SELECT 1 FROM public.vault_access_grants
        WHERE document_id = p_doc_id
          AND grantee_type = 'user'
          AND grantee_user_id = p_caller_id
          AND CURRENT_TIMESTAMP > expires_at
    );

    -- 6. RULE 3: ADMIN & CREATOR OVERRIDE
    IF v_is_admin OR v_created_by = p_caller_id THEN
        RETURN TRUE;
    END IF;

    -- 7. RULE 4: EXPLICIT ACTIVE USER GRANT
    IF NOT v_has_expired_user_grant AND EXISTS (
        SELECT 1 FROM public.vault_access_grants
        WHERE document_id = p_doc_id
          AND grantee_type = 'user'
          AND grantee_user_id = p_caller_id
          AND revoked_at IS NULL
          AND (expires_at IS NULL OR expires_at >= CURRENT_TIMESTAMP)
    ) THEN
        RETURN TRUE;
    END IF;

    -- Fetch user roles and property links for Role/Property evaluation
    SELECT ARRAY_AGG(role::text) INTO v_user_roles
    FROM public.user_roles
    WHERE user_id = p_caller_id AND society_id = v_caller_society_id;

    SELECT ARRAY_AGG(property_id) INTO v_user_props
    FROM public.property_owners
    WHERE owner_id = p_caller_id AND (end_date IS NULL OR end_date >= CURRENT_DATE);

    -- 8. RULE 5: EXPLICIT ACTIVE ROLE OR PROPERTY GRANT
    IF EXISTS (
        SELECT 1 FROM public.vault_access_grants
        WHERE document_id = p_doc_id
          AND (
              (grantee_type = 'role' AND grantee_role = ANY(v_user_roles)) OR
              (grantee_type = 'property' AND grantee_property_id = ANY(v_user_props))
          )
          AND revoked_at IS NULL
          AND (expires_at IS NULL OR expires_at >= CURRENT_TIMESTAMP)
    ) THEN
        RETURN TRUE;
    END IF;

    -- 9. RULE 6: CONFIDENTIALITY TIER DEFAULT MATRIX EVALUATION
    CASE v_classification
        WHEN 'public_society', 'resident_visible' THEN
            RETURN TRUE;
        WHEN 'owner_confidential' THEN
            IF v_property_id IS NOT NULL AND EXISTS (
                SELECT 1 FROM public.property_owners
                WHERE property_id = v_property_id AND owner_id = p_caller_id AND (end_date IS NULL OR end_date >= CURRENT_DATE)
            ) THEN
                RETURN TRUE;
            END IF;
        WHEN 'tenant_confidential' THEN
            IF v_property_id IS NOT NULL AND EXISTS (
                SELECT 1 FROM public.tenancies t
                JOIN public.units u ON u.id = t.unit_id
                WHERE u.property_id = v_property_id AND t.tenant_id = p_caller_id AND t.is_active = TRUE AND (t.end_date IS NULL OR t.end_date >= CURRENT_DATE)
            ) THEN
                RETURN TRUE;
            END IF;
        WHEN 'committee_confidential' THEN
            IF 'committee' = ANY(v_user_roles) THEN
                RETURN TRUE;
            END IF;
        WHEN 'admin_confidential' THEN
            IF v_is_admin THEN
                RETURN TRUE;
            END IF;
        WHEN 'strictly_restricted' THEN
            RETURN FALSE;
    END CASE;

    -- 10. Default Deny
    RETURN FALSE;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.fn_resolve_document_access(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_resolve_document_access(UUID, UUID) TO authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 7. EXECUTABLE RPC ROUTINES (9 TOTAL)
-- ----------------------------------------------------------------------------

-- RPC 1: fn_initiate_document_upload
CREATE OR REPLACE FUNCTION public.fn_initiate_document_upload(
    p_property_id UUID,
    p_title VARCHAR(255),
    p_classification VARCHAR(50),
    p_file_name VARCHAR(255),
    p_file_size BIGINT,
    p_mime_type VARCHAR(100)
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_caller_id UUID;
    v_society_id UUID;
    v_doc_id UUID;
    v_version_id UUID;
    v_storage_path TEXT;
    v_window_start TIMESTAMPTZ;
    v_rate_count INT;
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION '42501: Authentication required.';
    END IF;

    v_society_id := public.get_user_society_id(v_caller_id);
    IF v_society_id IS NULL THEN
        RAISE EXCEPTION '42501: User is not associated with an active society.';
    END IF;

    -- Validate input constraints
    IF length(trim(p_title)) < 3 THEN
        RAISE EXCEPTION '22023: Document title must be at least 3 characters.';
    END IF;
    IF p_file_size <= 0 OR p_file_size > 52428800 THEN
        RAISE EXCEPTION '22023: File size must be between 1 byte and 50 MB.';
    END IF;

    -- Rate limiting check (upload): Max 10 uploads per hour
    v_window_start := date_trunc('hour', CURRENT_TIMESTAMP);
    
    INSERT INTO public.vault_rate_limits (user_id, rate_type, window_start, request_count)
    VALUES (v_caller_id, 'upload', v_window_start, 1)
    ON CONFLICT (user_id, rate_type, window_start) DO NOTHING;

    SELECT request_count INTO v_rate_count
    FROM public.vault_rate_limits
    WHERE user_id = v_caller_id AND rate_type = 'upload' AND window_start = v_window_start
    FOR UPDATE;

    IF v_rate_count > 10 THEN
        RAISE EXCEPTION '42501: Upload rate limit exceeded (max 10 uploads/hour).';
    END IF;

    UPDATE public.vault_rate_limits
    SET request_count = request_count + 1, updated_at = CURRENT_TIMESTAMP
    WHERE user_id = v_caller_id AND rate_type = 'upload' AND window_start = v_window_start;

    -- Create master document record
    INSERT INTO public.vault_documents (society_id, property_id, title, classification, status, created_by)
    VALUES (v_society_id, p_property_id, p_title, p_classification, 'active', v_caller_id)
    RETURNING id INTO v_doc_id;

    -- Server-side authoritative storage path construction
    v_version_id := gen_random_uuid();
    v_storage_path := format('%s/%s/v1_%s.bin', v_society_id, v_doc_id, substr(md5(random()::text), 1, 8));

    -- Create initial version record
    INSERT INTO public.vault_document_versions (
        id, document_id, version_number, storage_path, file_name, file_size_bytes, mime_type, status, uploaded_by
    ) VALUES (
        v_version_id, v_doc_id, 1, v_storage_path, p_file_name, p_file_size, p_mime_type, 'UPLOAD_INITIATED', v_caller_id
    );

    -- Audit log
    INSERT INTO public.vault_audit_logs (society_id, document_id, version_id, user_id, event_type, details)
    VALUES (v_society_id, v_doc_id, v_version_id, v_caller_id, 'UPLOAD_INITIATED', jsonb_build_object(
        'storage_path', v_storage_path,
        'file_name', p_file_name,
        'file_size', p_file_size
    ));

    RETURN v_version_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.fn_initiate_document_upload(UUID, VARCHAR, VARCHAR, VARCHAR, BIGINT, VARCHAR) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_initiate_document_upload(UUID, VARCHAR, VARCHAR, VARCHAR, BIGINT, VARCHAR) TO authenticated;


-- RPC 2: fn_finalize_document_upload
CREATE OR REPLACE FUNCTION public.fn_finalize_document_upload(
    p_version_id UUID,
    p_claimed_sha256 VARCHAR(64)
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_caller_id UUID;
    v_doc_id UUID;
    v_society_id UUID;
    v_status VARCHAR(50);
    v_uploaded_by UUID;
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION '42501: Authentication required.';
    END IF;

    -- Lock version row
    SELECT document_id, status, uploaded_by
    INTO v_doc_id, v_status, v_uploaded_by
    FROM public.vault_document_versions
    WHERE id = p_version_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION '40400: Version not found.';
    END IF;

    -- Idempotency: if already UPLOADED or ACTIVE, return TRUE
    IF v_status IN ('UPLOADED', 'VALIDATING', 'ACTIVE') THEN
        RETURN TRUE;
    END IF;

    IF v_status != 'UPLOAD_INITIATED' THEN
        RAISE EXCEPTION '42501: Version is not in UPLOAD_INITIATED state.';
    END IF;

    -- Authorization: uploaded_by or admin
    IF v_uploaded_by != v_caller_id AND NOT public.is_admin() THEN
        RAISE EXCEPTION '42501: Unauthorized caller.';
    END IF;

    SELECT society_id INTO v_society_id FROM public.vault_documents WHERE id = v_doc_id;

    -- Transition status to UPLOADED
    UPDATE public.vault_document_versions
    SET status = 'UPLOADED', sha256_hash = p_claimed_sha256, updated_at = CURRENT_TIMESTAMP
    WHERE id = p_version_id;

    -- Audit log
    INSERT INTO public.vault_audit_logs (society_id, document_id, version_id, user_id, event_type, details)
    VALUES (v_society_id, v_doc_id, p_version_id, v_caller_id, 'UPLOAD_COMPLETED', jsonb_build_object(
        'claimed_sha256', p_claimed_sha256
    ));

    RETURN TRUE;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.fn_finalize_document_upload(UUID, VARCHAR) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_finalize_document_upload(UUID, VARCHAR) TO authenticated;


-- RPC 3: validate_vault_object_payload_internal (Worker Execution Only)
CREATE OR REPLACE FUNCTION public.validate_vault_object_payload_internal(
    p_version_id UUID,
    p_actual_sha256 VARCHAR(64),
    p_actual_size BIGINT,
    p_detected_mime VARCHAR(100)
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_doc_id UUID;
    v_society_id UUID;
    v_status VARCHAR(50);
    v_expected_size BIGINT;
    v_expected_sha256 VARCHAR(64);
BEGIN
    -- Lock target version
    SELECT document_id, status, file_size_bytes, sha256_hash
    INTO v_doc_id, v_status, v_expected_size, v_expected_sha256
    FROM public.vault_document_versions
    WHERE id = p_version_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    -- Re-read authoritative state: must be UPLOADED or VALIDATING
    IF v_status NOT IN ('UPLOADED', 'VALIDATING') THEN
        -- Stale event for ACTIVE, DELETED, ARCHIVED, or SUPERSEDED version ignored safely
        RETURN TRUE;
    END IF;

    SELECT society_id INTO v_society_id FROM public.vault_documents WHERE id = v_doc_id;

    -- Check size & sha256 hash match
    IF p_actual_size != v_expected_size OR (v_expected_sha256 IS NOT NULL AND p_actual_sha256 != v_expected_sha256) THEN
        UPDATE public.vault_document_versions
        SET status = 'VERIFICATION_FAILED', updated_at = CURRENT_TIMESTAMP
        WHERE id = p_version_id;

        INSERT INTO public.vault_audit_logs (society_id, document_id, version_id, user_id, event_type, details)
        VALUES (v_society_id, v_doc_id, p_version_id, '00000000-0000-0000-0000-000000000000'::uuid, 'VALIDATION_FAILED', jsonb_build_object(
            'actual_sha256', p_actual_sha256,
            'expected_sha256', v_expected_sha256,
            'actual_size', p_actual_size,
            'expected_size', v_expected_size
        ));

        RETURN FALSE;
    END IF;

    -- Mark previous active versions as SUPERSEDED
    UPDATE public.vault_document_versions
    SET status = 'SUPERSEDED', updated_at = CURRENT_TIMESTAMP
    WHERE document_id = v_doc_id AND status = 'ACTIVE' AND id != p_version_id;

    -- Transition this version to ACTIVE
    UPDATE public.vault_document_versions
    SET status = 'ACTIVE', sha256_hash = p_actual_sha256, updated_at = CURRENT_TIMESTAMP
    WHERE id = p_version_id;

    INSERT INTO public.vault_audit_logs (society_id, document_id, version_id, user_id, event_type, details)
    VALUES (v_society_id, v_doc_id, p_version_id, '00000000-0000-0000-0000-000000000000'::uuid, 'DOCUMENT_ACTIVATED', jsonb_build_object(
        'sha256', p_actual_sha256,
        'size', p_actual_size
    ));

    RETURN TRUE;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.validate_vault_object_payload_internal(UUID, VARCHAR, BIGINT, VARCHAR) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.validate_vault_object_payload_internal(UUID, VARCHAR, BIGINT, VARCHAR) TO service_role;


-- RPC 4: fn_add_document_version
CREATE OR REPLACE FUNCTION public.fn_add_document_version(
    p_document_id UUID,
    p_file_name VARCHAR(255),
    p_file_size BIGINT,
    p_mime_type VARCHAR(100)
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_caller_id UUID;
    v_society_id UUID;
    v_next_ver INT;
    v_version_id UUID;
    v_storage_path TEXT;
    v_window_start TIMESTAMPTZ;
    v_rate_count INT;
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION '42501: Authentication required.';
    END IF;

    SELECT society_id INTO v_society_id FROM public.vault_documents WHERE id = p_document_id AND status = 'active';
    IF NOT FOUND THEN
        RAISE EXCEPTION '40400: Active document not found.';
    END IF;

    -- Verify access
    IF NOT public.fn_resolve_document_access(p_document_id, v_caller_id) THEN
        RAISE EXCEPTION '42501: Access denied.';
    END IF;

    -- Rate limit check (upload)
    v_window_start := date_trunc('hour', CURRENT_TIMESTAMP);
    INSERT INTO public.vault_rate_limits (user_id, rate_type, window_start, request_count)
    VALUES (v_caller_id, 'upload', v_window_start, 1)
    ON CONFLICT (user_id, rate_type, window_start) DO NOTHING;

    SELECT request_count INTO v_rate_count
    FROM public.vault_rate_limits
    WHERE user_id = v_caller_id AND rate_type = 'upload' AND window_start = v_window_start
    FOR UPDATE;

    IF v_rate_count > 10 THEN
        RAISE EXCEPTION '42501: Upload rate limit exceeded.';
    END IF;

    UPDATE public.vault_rate_limits
    SET request_count = request_count + 1, updated_at = CURRENT_TIMESTAMP
    WHERE user_id = v_caller_id AND rate_type = 'upload' AND window_start = v_window_start;

    -- Determine next version number
    SELECT COALESCE(MAX(version_number), 0) + 1 INTO v_next_ver
    FROM public.vault_document_versions
    WHERE document_id = p_document_id;

    v_version_id := gen_random_uuid();
    v_storage_path := format('%s/%s/v%s_%s.bin', v_society_id, p_document_id, v_next_ver, substr(md5(random()::text), 1, 8));

    INSERT INTO public.vault_document_versions (
        id, document_id, version_number, storage_path, file_name, file_size_bytes, mime_type, status, uploaded_by
    ) VALUES (
        v_version_id, p_document_id, v_next_ver, v_storage_path, p_file_name, p_file_size, p_mime_type, 'UPLOAD_INITIATED', v_caller_id
    );

    INSERT INTO public.vault_audit_logs (society_id, document_id, version_id, user_id, event_type, details)
    VALUES (v_society_id, p_document_id, v_version_id, v_caller_id, 'VERSION_ADDED', jsonb_build_object(
        'version_number', v_next_ver,
        'storage_path', v_storage_path
    ));

    RETURN v_version_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.fn_add_document_version(UUID, VARCHAR, BIGINT, VARCHAR) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_add_document_version(UUID, VARCHAR, BIGINT, VARCHAR) TO authenticated;


-- RPC 5: fn_grant_document_access
CREATE OR REPLACE FUNCTION public.fn_grant_document_access(
    p_document_id UUID,
    p_grantee_type VARCHAR(50),
    p_grantee_user_id UUID,
    p_grantee_role VARCHAR(50),
    p_grantee_property_id UUID,
    p_expires_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_caller_id UUID;
    v_society_id UUID;
    v_created_by UUID;
    v_grant_id UUID;
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION '42501: Authentication required.';
    END IF;

    SELECT society_id, created_by INTO v_society_id, v_created_by
    FROM public.vault_documents WHERE id = p_document_id AND status = 'active';

    IF NOT FOUND THEN
        RAISE EXCEPTION '40400: Active document not found.';
    END IF;

    IF NOT public.is_admin() AND v_created_by != v_caller_id THEN
        RAISE EXCEPTION '42501: Only admin or creator can grant document access.';
    END IF;

    INSERT INTO public.vault_access_grants (
        document_id, grantee_type, grantee_user_id, grantee_role, grantee_property_id, granted_by, expires_at
    ) VALUES (
        p_document_id, p_grantee_type, p_grantee_user_id, p_grantee_role, p_grantee_property_id, v_caller_id, p_expires_at
    )
    RETURNING id INTO v_grant_id;

    INSERT INTO public.vault_audit_logs (society_id, document_id, user_id, event_type, details)
    VALUES (v_society_id, p_document_id, v_caller_id, 'ACCESS_GRANTED', jsonb_build_object(
        'grant_id', v_grant_id,
        'grantee_type', p_grantee_type,
        'grantee_user_id', p_grantee_user_id,
        'grantee_role', p_grantee_role,
        'grantee_property_id', p_grantee_property_id,
        'expires_at', p_expires_at
    ));

    RETURN v_grant_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.fn_grant_document_access(UUID, VARCHAR, UUID, VARCHAR, UUID, TIMESTAMPTZ) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_grant_document_access(UUID, VARCHAR, UUID, VARCHAR, UUID, TIMESTAMPTZ) TO authenticated;


-- RPC 6: fn_revoke_document_access
CREATE OR REPLACE FUNCTION public.fn_revoke_document_access(
    p_grant_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_caller_id UUID;
    v_doc_id UUID;
    v_society_id UUID;
    v_created_by UUID;
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION '42501: Authentication required.';
    END IF;

    SELECT g.document_id, d.society_id, d.created_by
    INTO v_doc_id, v_society_id, v_created_by
    FROM public.vault_access_grants g
    JOIN public.vault_documents d ON d.id = g.document_id
    WHERE g.id = p_grant_id
    FOR UPDATE OF g;

    IF NOT FOUND THEN
        RAISE EXCEPTION '40400: Access grant not found.';
    END IF;

    IF NOT public.is_admin() AND v_created_by != v_caller_id THEN
        RAISE EXCEPTION '42501: Only admin or creator can revoke document access.';
    END IF;

    UPDATE public.vault_access_grants
    SET revoked_at = CURRENT_TIMESTAMP, revoked_by = v_caller_id
    WHERE id = p_grant_id;

    INSERT INTO public.vault_audit_logs (society_id, document_id, user_id, event_type, details)
    VALUES (v_society_id, v_doc_id, v_caller_id, 'ACCESS_REVOKED', jsonb_build_object(
        'grant_id', p_grant_id
    ));

    RETURN TRUE;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.fn_revoke_document_access(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_revoke_document_access(UUID) TO authenticated;


-- RPC 7: fn_generate_document_download_url
CREATE OR REPLACE FUNCTION public.fn_generate_document_download_url(
    p_document_id UUID,
    p_version_id UUID DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_caller_id UUID;
    v_society_id UUID;
    v_prop_id UUID;
    v_ver_id UUID;
    v_ver_status VARCHAR(50);
    v_storage_path TEXT;
    v_allowed BOOLEAN;
    v_window_start TIMESTAMPTZ;
    v_rate_count INT;
    v_signed_url TEXT;
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION '42501: Authentication required.';
    END IF;

    -- Fetch document property & society
    SELECT property_id, society_id INTO v_prop_id, v_society_id
    FROM public.vault_documents WHERE id = p_document_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION '40400: Document not found.';
    END IF;

    -- RANK 1 PROPERTY ROW LOCK (FOR SHARE) for property-scoped documents
    -- Serializes against concurrent Title Transfer / Lease Termination transactions
    IF v_prop_id IS NOT NULL THEN
        PERFORM 1 FROM public.properties WHERE id = v_prop_id FOR SHARE;
    END IF;

    -- Rate Limit Check (download_url): Max 30 URL generations / hour
    v_window_start := date_trunc('hour', CURRENT_TIMESTAMP);
    INSERT INTO public.vault_rate_limits (user_id, rate_type, window_start, request_count)
    VALUES (v_caller_id, 'download_url', v_window_start, 1)
    ON CONFLICT (user_id, rate_type, window_start) DO NOTHING;

    SELECT request_count INTO v_rate_count
    FROM public.vault_rate_limits
    WHERE user_id = v_caller_id AND rate_type = 'download_url' AND window_start = v_window_start
    FOR UPDATE;

    IF v_rate_count > 30 THEN
        RAISE EXCEPTION '42501: Download rate limit exceeded (max 30 requests/hour).';
    END IF;

    UPDATE public.vault_rate_limits
    SET request_count = request_count + 1, updated_at = CURRENT_TIMESTAMP
    WHERE user_id = v_caller_id AND rate_type = 'download_url' AND window_start = v_window_start;

    -- Select target version (if null, pick latest ACTIVE version)
    IF p_version_id IS NULL THEN
        SELECT id, storage_path, status INTO v_ver_id, v_storage_path, v_ver_status
        FROM public.vault_document_versions
        WHERE document_id = p_document_id AND status = 'ACTIVE'
        ORDER BY version_number DESC LIMIT 1;
    ELSE
        SELECT id, storage_path, status INTO v_ver_id, v_storage_path, v_ver_status
        FROM public.vault_document_versions
        WHERE id = p_version_id AND document_id = p_document_id;
    END IF;

    IF v_ver_id IS NULL THEN
        RAISE EXCEPTION '40400: Valid document version not found.';
    END IF;

    IF v_ver_status NOT IN ('ACTIVE', 'SUPERSEDED') THEN
        RAISE EXCEPTION '42501: Download prohibited for unverified version state: %', v_ver_status;
    END IF;

    -- Authorization evaluation
    v_allowed := public.fn_resolve_document_access(p_document_id, v_caller_id);
    IF NOT v_allowed THEN
        INSERT INTO public.vault_audit_logs (society_id, document_id, version_id, user_id, event_type, details)
        VALUES (v_society_id, p_document_id, v_ver_id, v_caller_id, 'UNAUTHORIZED_ACCESS_ATTEMPT', jsonb_build_object(
            'version_id', v_ver_id
        ));
        RAISE EXCEPTION '42501: Document access denied.';
    END IF;

    -- Option A Gateway Signed URL string construction (15-min TTL = 900s)
    v_signed_url := format('https://vault.gateway/signed-url?path=%s&ttl=900&token=%s', v_storage_path, md5(v_storage_path || CURRENT_TIMESTAMP::text));

    -- Audit log success
    INSERT INTO public.vault_audit_logs (society_id, document_id, version_id, user_id, event_type, details)
    VALUES (v_society_id, p_document_id, v_ver_id, v_caller_id, 'DOWNLOAD_URL_GENERATED', jsonb_build_object(
        'version_id', v_ver_id,
        'ttl', 900
    ));

    RETURN v_signed_url;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.fn_generate_document_download_url(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_generate_document_download_url(UUID, UUID) TO authenticated;


-- RPC 8: fn_archive_vault_document
CREATE OR REPLACE FUNCTION public.fn_archive_vault_document(
    p_document_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_caller_id UUID;
    v_society_id UUID;
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION '42501: Authentication required.';
    END IF;

    IF NOT public.is_admin() THEN
        RAISE EXCEPTION '42501: Only admin can archive vault documents.';
    END IF;

    SELECT society_id INTO v_society_id FROM public.vault_documents WHERE id = p_document_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION '40400: Document not found.';
    END IF;

    UPDATE public.vault_documents SET status = 'archived', updated_at = CURRENT_TIMESTAMP WHERE id = p_document_id;
    UPDATE public.vault_document_versions SET status = 'ARCHIVED', updated_at = CURRENT_TIMESTAMP WHERE document_id = p_document_id;

    INSERT INTO public.vault_audit_logs (society_id, document_id, user_id, event_type, details)
    VALUES (v_society_id, p_document_id, v_caller_id, 'DOCUMENT_ARCHIVED', NULL);

    RETURN TRUE;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.fn_archive_vault_document(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_archive_vault_document(UUID) TO authenticated;


-- RPC 9: fn_delete_vault_document
CREATE OR REPLACE FUNCTION public.fn_delete_vault_document(
    p_document_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_caller_id UUID;
    v_society_id UUID;
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION '42501: Authentication required.';
    END IF;

    IF NOT public.is_admin() THEN
        RAISE EXCEPTION '42501: Only admin can soft delete vault documents.';
    END IF;

    SELECT society_id INTO v_society_id FROM public.vault_documents WHERE id = p_document_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION '40400: Document not found.';
    END IF;

    UPDATE public.vault_documents SET status = 'deleted', updated_at = CURRENT_TIMESTAMP WHERE id = p_document_id;
    UPDATE public.vault_document_versions SET status = 'DELETED', updated_at = CURRENT_TIMESTAMP WHERE document_id = p_document_id;

    INSERT INTO public.vault_audit_logs (society_id, document_id, user_id, event_type, details)
    VALUES (v_society_id, p_document_id, v_caller_id, 'DOCUMENT_DELETED', NULL);

    RETURN TRUE;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.fn_delete_vault_document(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_delete_vault_document(UUID) TO authenticated;
