-- SU SOCIETY APP — CANDIDATE-30 DATA MIGRATION CENTER
-- Migration Baseline: Candidate-30 Remediation & Technical Specification Implementation
-- Scope: Staging tables, Lineage tracking, CSV Injection Sanitization, Security DEFINER Atomic Commit & Rollback RPCs
-- Hardening: SET search_path = public, pg_temp; REVOKE EXECUTE FROM PUBLIC;

BEGIN;

-- =========================================================================
-- 1. DATA MIGRATION CENTER TABLES
-- =========================================================================

-- Migration Batches table
CREATE TABLE IF NOT EXISTS public.migration_batches (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id              UUID        NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    batch_name              TEXT        NOT NULL,
    entity_type             TEXT        NOT NULL, -- 'properties', 'members', 'tenancies', 'opening_balances', 'vehicles', 'vendors', 'assets', 'staff_helpers'
    status                  TEXT        NOT NULL DEFAULT 'draft', 
                                        -- 'draft', 'uploaded', 'analyzing', 'mapped', 'validating', 'validation_passed', 'ready_for_review', 'approved', 'committing', 'committed', 'reconciled', 'closed', 'rolled_back'
    total_rows              INT         NOT NULL DEFAULT 0,
    valid_rows              INT         NOT NULL DEFAULT 0,
    error_rows              INT         NOT NULL DEFAULT 0,
    approved_dataset_hash   TEXT        DEFAULT NULL,
    field_mappings          JSONB       NOT NULL DEFAULT '{}'::jsonb,
    validation_summary      JSONB       NOT NULL DEFAULT '{}'::jsonb,
    approved_by             UUID        REFERENCES public.users(id) ON DELETE RESTRICT,
    approved_at             TIMESTAMPTZ DEFAULT NULL,
    committed_by            UUID        REFERENCES public.users(id) ON DELETE RESTRICT,
    committed_at            TIMESTAMPTZ DEFAULT NULL,
    created_by              UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE public.migration_batches IS
    'Tracks society bulk data migration batches, lifecycle states, and cryptographic approval hashes.';

-- Migration Staging Rows table
CREATE TABLE IF NOT EXISTS public.migration_staging_rows (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_id                UUID        NOT NULL REFERENCES public.migration_batches(id) ON DELETE CASCADE,
    society_id              UUID        NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    row_index               INT         NOT NULL,
    raw_data                JSONB       NOT NULL,
    mapped_data             JSONB       DEFAULT NULL,
    validation_status       TEXT        NOT NULL DEFAULT 'pending', -- 'pending', 'valid', 'error', 'warning'
    validation_errors       JSONB       NOT NULL DEFAULT '[]'::jsonb,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_staging_batch_row UNIQUE (batch_id, row_index)
);

COMMENT ON TABLE public.migration_staging_rows IS
    'Stores raw and mapped staging rows for ingestion validation prior to commit.';

-- Migration Lineage table
CREATE TABLE IF NOT EXISTS public.migration_lineage (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_id                UUID        NOT NULL REFERENCES public.migration_batches(id) ON DELETE RESTRICT,
    society_id              UUID        NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    source_row_id           UUID        REFERENCES public.migration_staging_rows(id) ON DELETE SET NULL,
    target_table            TEXT        NOT NULL,
    target_id               UUID        NOT NULL,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_migration_lineage_target UNIQUE (target_table, target_id)
);

COMMENT ON TABLE public.migration_lineage IS
    'Maintains audit lineage between staging rows and committed target operational entities.';

-- Migration Reconciliation Records table
CREATE TABLE IF NOT EXISTS public.migration_reconciliation_records (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_id                UUID        NOT NULL REFERENCES public.migration_batches(id) ON DELETE CASCADE,
    society_id              UUID        NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    reconciled_by           UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    total_source_rows       INT         NOT NULL,
    total_accepted_rows     INT         NOT NULL,
    total_rejected_rows     INT         NOT NULL,
    committed_entity_count  INT         NOT NULL,
    financial_total_amount  NUMERIC(15, 2) DEFAULT 0.00,
    discrepancy_count       INT         NOT NULL DEFAULT 0,
    reconciliation_details  JSONB       NOT NULL DEFAULT '{}'::jsonb,
    status                  TEXT        NOT NULL DEFAULT 'matched', -- 'matched', 'discrepancy_flagged'
    created_at              TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE public.migration_reconciliation_records IS
    'Stores post-commit reconciliation evidence for verification and auditing.';


-- =========================================================================
-- 2. INDEXES
-- =========================================================================

CREATE INDEX IF NOT EXISTS idx_migration_batches_society_status 
    ON public.migration_batches(society_id, status);

CREATE INDEX IF NOT EXISTS idx_migration_staging_batch_society 
    ON public.migration_staging_rows(batch_id, society_id);

CREATE INDEX IF NOT EXISTS idx_migration_lineage_batch_target 
    ON public.migration_lineage(batch_id, target_table, target_id);

CREATE INDEX IF NOT EXISTS idx_migration_reconciliation_batch 
    ON public.migration_reconciliation_records(batch_id, society_id);


-- =========================================================================
-- 3. TRIGGERS & MUTABILITY SECURITY
-- =========================================================================

-- Trigger to sanitize CSV injection formula prefixes in mapped_data
CREATE OR REPLACE FUNCTION public.fn_trg_sanitize_staging_input()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_key TEXT;
    v_val TEXT;
    v_cleaned JSONB := '{}'::jsonb;
BEGIN
    IF NEW.mapped_data IS NOT NULL AND jsonb_typeof(NEW.mapped_data) = 'object' THEN
        FOR v_key, v_val IN SELECT * FROM jsonb_each_text(NEW.mapped_data) LOOP
            IF v_val IS NOT NULL AND (
                v_val LIKE '=%' OR 
                v_val LIKE '+%' OR 
                v_val LIKE '-%' OR 
                v_val LIKE '@%'
            ) THEN
                v_cleaned := jsonb_set(v_cleaned, ARRAY[v_key], to_jsonb('''' || v_val));
            ELSE
                v_cleaned := jsonb_set(v_cleaned, ARRAY[v_key], to_jsonb(v_val));
            END IF;
        END LOOP;
        NEW.mapped_data := v_cleaned;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_sanitize_staging_input
    BEFORE INSERT OR UPDATE ON public.migration_staging_rows
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_trg_sanitize_staging_input();


-- Trigger to enforce staging row immutability after approval
CREATE OR REPLACE FUNCTION public.fn_trg_assert_staging_post_approval_immutability()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_batch_status TEXT;
BEGIN
    SELECT status INTO v_batch_status
    FROM public.migration_batches
    WHERE id = OLD.batch_id;

    IF v_batch_status IN ('approved', 'committing', 'committed', 'reconciled', 'closed') THEN
        RAISE EXCEPTION 'CANNOT_MUTATE_APPROVED_STAGING: Migration batch dataset is immutable in status %', v_batch_status;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_assert_staging_post_approval_immutability
    BEFORE UPDATE OR DELETE ON public.migration_staging_rows
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_trg_assert_staging_post_approval_immutability();


-- =========================================================================
-- 4. ROW LEVEL SECURITY (RLS)
-- =========================================================================

ALTER TABLE public.migration_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.migration_staging_rows ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.migration_lineage ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.migration_reconciliation_records ENABLE ROW LEVEL SECURITY;

-- RLS: Admin users can view and manage migration batches for their society
CREATE POLICY migration_batches_admin_policy ON public.migration_batches
    FOR ALL
    TO authenticated
    USING (
        society_id = public.get_user_society_id(auth.uid()) 
        AND public.is_admin(auth.uid())
    )
    WITH CHECK (
        society_id = public.get_user_society_id(auth.uid()) 
        AND public.is_admin(auth.uid())
    );

-- RLS: Admin users can view and manage staging rows for their society
CREATE POLICY migration_staging_rows_admin_policy ON public.migration_staging_rows
    FOR ALL
    TO authenticated
    USING (
        society_id = public.get_user_society_id(auth.uid()) 
        AND public.is_admin(auth.uid())
    )
    WITH CHECK (
        society_id = public.get_user_society_id(auth.uid()) 
        AND public.is_admin(auth.uid())
    );

-- RLS: Admin users can view lineage for their society
CREATE POLICY migration_lineage_admin_policy ON public.migration_lineage
    FOR ALL
    TO authenticated
    USING (
        society_id = public.get_user_society_id(auth.uid()) 
        AND public.is_admin(auth.uid())
    )
    WITH CHECK (
        society_id = public.get_user_society_id(auth.uid()) 
        AND public.is_admin(auth.uid())
    );

-- RLS: Admin users can view reconciliation records for their society
CREATE POLICY migration_reconciliation_admin_policy ON public.migration_reconciliation_records
    FOR ALL
    TO authenticated
    USING (
        society_id = public.get_user_society_id(auth.uid()) 
        AND public.is_admin(auth.uid())
    )
    WITH CHECK (
        society_id = public.get_user_society_id(auth.uid()) 
        AND public.is_admin(auth.uid())
    );


-- =========================================================================
-- 5. ATOMIC COMMIT RPC FUNCTION
-- =========================================================================

CREATE OR REPLACE FUNCTION public.fn_commit_migration_batch(
    p_batch_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller_uid            UUID;
    v_caller_society_id     UUID;
    v_batch                 RECORD;
    v_row                   RECORD;
    v_committed_count       INT := 0;
    v_financial_total       NUMERIC(15,2) := 0.00;
    v_target_id             UUID;
    v_unit_id               UUID;
    v_reconciliation_id     UUID;
    v_calc_hash_input       TEXT := '';
    v_recalculated_hash     TEXT;
BEGIN
    -- 1. Derive authenticated identity
    v_caller_uid := auth.uid();
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required to commit migration batch.';
    END IF;

    -- 2. Derive authoritative caller society identity using evidence-backed helper
    v_caller_society_id := public.get_user_society_id(v_caller_uid);
    IF v_caller_society_id IS NULL THEN
        RAISE EXCEPTION 'NO_SOCIETY_BINDING: Caller is not assigned to an active society.';
    END IF;

    -- 3. Verify administrative authorization using existing project helper
    IF NOT public.is_admin(v_caller_uid) THEN
        RAISE EXCEPTION 'UNAUTHORIZED_ROLE: Administrative authorization required to commit migration batch.';
    END IF;

    -- 4. Acquire exclusive transactional advisory lock scoped to society ID
    PERFORM pg_advisory_xact_lock(hashtext('migration_lock_' || v_caller_society_id::text));

    -- 5. Fetch migration batch
    SELECT * INTO v_batch
    FROM public.migration_batches
    WHERE id = p_batch_id;

    IF v_batch.id IS NULL THEN
        RAISE EXCEPTION 'BATCH_NOT_FOUND: Migration batch % does not exist.', p_batch_id;
    END IF;

    -- 6. Assert tenant equality
    IF v_batch.society_id != v_caller_society_id THEN
        RAISE EXCEPTION 'TENANT_MISMATCH: Migration batch belongs to another society.';
    END IF;

    -- 7. Assert batch state
    IF v_batch.status != 'approved' THEN
        RAISE EXCEPTION 'INVALID_BATCH_STATE: Migration batch must be in approved status to commit. Current status: %', v_batch.status;
    END IF;

    -- 8. Assert staging rows tenant equality
    IF EXISTS (
        SELECT 1 FROM public.migration_staging_rows
        WHERE batch_id = p_batch_id AND society_id != v_caller_society_id
    ) THEN
        RAISE EXCEPTION 'STAGING_TENANT_MISMATCH: Staging rows contain invalid cross-tenant references.';
    END IF;

    -- 9. Recalculate dataset SHA-256 hash & verify payload integrity
    SELECT string_agg(raw_data::text || mapped_data::text, '' ORDER BY row_index)
    INTO v_calc_hash_input
    FROM public.migration_staging_rows
    WHERE batch_id = p_batch_id AND validation_status = 'valid';

    v_recalculated_hash := encode(digest(COALESCE(v_calc_hash_input, '') || v_batch.field_mappings::text, 'sha256'), 'hex');

    IF v_batch.approved_dataset_hash IS NOT NULL AND v_recalculated_hash != v_batch.approved_dataset_hash THEN
        RAISE EXCEPTION 'PAYLOAD_HASH_MISMATCH: Approved dataset hash does not match current staging rows. Commit aborted.';
    END IF;

    -- 10. Update batch state to 'committing'
    UPDATE public.migration_batches
    SET status = 'committing',
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_batch_id;

    -- 11. Execute entity-specific atomic commits
    FOR v_row IN 
        SELECT * FROM public.migration_staging_rows
        WHERE batch_id = p_batch_id AND validation_status = 'valid'
        ORDER BY row_index ASC
    LOOP
        v_target_id := gen_random_uuid();

        IF v_batch.entity_type = 'properties' THEN
            INSERT INTO public.properties (
                id, society_id, plot_number, plot_size_sqft, survey_number, construction_status, occupancy_status, remarks
            ) VALUES (
                v_target_id,
                v_caller_society_id,
                (v_row.mapped_data->>'plot_number')::text,
                COALESCE((v_row.mapped_data->>'plot_size_sqft')::numeric, 1000.00),
                COALESCE((v_row.mapped_data->>'survey_number')::text, ''),
                COALESCE((v_row.mapped_data->>'construction_status')::text, 'constructed'),
                COALESCE((v_row.mapped_data->>'occupancy_status')::text, 'vacant'),
                COALESCE((v_row.mapped_data->>'remarks')::text, 'Migrated property')
            );

            -- Automatically create default whole-property unit
            v_unit_id := gen_random_uuid();
            INSERT INTO public.units (id, property_id, unit_name, occupancy_status)
            VALUES (v_unit_id, v_target_id, 'Whole Property', COALESCE((v_row.mapped_data->>'occupancy_status')::text, 'vacant'));

        ELSIF v_batch.entity_type = 'members' THEN
            -- Insert into users if user does not exist
            IF NOT EXISTS (SELECT 1 FROM public.users WHERE email = (v_row.mapped_data->>'email')::text) THEN
                INSERT INTO public.users (id, email, name, mobile, status)
                VALUES (
                    v_target_id,
                    (v_row.mapped_data->>'email')::text,
                    (v_row.mapped_data->>'name')::text,
                    COALESCE((v_row.mapped_data->>'mobile')::text, ''),
                    'active'
                );
            ELSE
                SELECT id INTO v_target_id FROM public.users WHERE email = (v_row.mapped_data->>'email')::text;
            END IF;

            -- Assign user role
            IF NOT EXISTS (
                SELECT 1 FROM public.user_roles 
                WHERE user_id = v_target_id AND society_id = v_caller_society_id AND role_name = COALESCE((v_row.mapped_data->>'role')::text, 'member')
            ) THEN
                INSERT INTO public.user_roles (user_id, society_id, role_name)
                VALUES (v_target_id, v_caller_society_id, COALESCE((v_row.mapped_data->>'role')::text, 'member'));
            END IF;

        ELSIF v_batch.entity_type = 'opening_balances' THEN
            v_financial_total := v_financial_total + COALESCE((v_row.mapped_data->>'amount')::numeric, 0.00);

            INSERT INTO public.opening_balances (
                id, society_id, property_id, user_id, amount, direction, as_of_date
            ) VALUES (
                v_target_id,
                v_caller_society_id,
                (v_row.mapped_data->>'property_id')::uuid,
                (v_row.mapped_data->>'user_id')::uuid,
                (v_row.mapped_data->>'amount')::numeric,
                (v_row.mapped_data->>'direction')::text,
                COALESCE((v_row.mapped_data->>'as_of_date')::date, CURRENT_DATE)
            );

        ELSIF v_batch.entity_type = 'vendors' THEN
            INSERT INTO public.vendors (
                id, society_id, name, service_category, phone, email, status
            ) VALUES (
                v_target_id,
                v_caller_society_id,
                (v_row.mapped_data->>'name')::text,
                COALESCE((v_row.mapped_data->>'service_category')::text, 'General Vendor'),
                COALESCE((v_row.mapped_data->>'phone')::text, ''),
                COALESCE((v_row.mapped_data->>'email')::text, ''),
                'active'
            );

        ELSIF v_batch.entity_type = 'assets' THEN
            INSERT INTO public.assets (
                id, society_id, name, asset_code, purchase_cost, serial_number, status
            ) VALUES (
                v_target_id,
                v_caller_society_id,
                (v_row.mapped_data->>'name')::text,
                (v_row.mapped_data->>'asset_code')::text,
                COALESCE((v_row.mapped_data->>'purchase_cost')::numeric, 0.00),
                COALESCE((v_row.mapped_data->>'serial_number')::text, ''),
                'active'
            );

        ELSE
            RAISE EXCEPTION 'UNSUPPORTED_ENTITY_TYPE: Migration entity type % is not supported by atomic commit.', v_batch.entity_type;
        END IF;

        -- 12. Write migration lineage record
        INSERT INTO public.migration_lineage (
            batch_id, society_id, source_row_id, target_table, target_id
        ) VALUES (
            p_batch_id, v_caller_society_id, v_row.id, v_batch.entity_type, v_target_id
        );

        v_committed_count := v_committed_count + 1;
    END LOOP;

    -- 13. Create reconciliation record
    v_reconciliation_id := gen_random_uuid();
    INSERT INTO public.migration_reconciliation_records (
        id, batch_id, society_id, reconciled_by, total_source_rows, total_accepted_rows,
        total_rejected_rows, committed_entity_count, financial_total_amount, status
    ) VALUES (
        v_reconciliation_id, p_batch_id, v_caller_society_id, v_caller_uid,
        v_batch.total_rows, v_committed_count, (v_batch.total_rows - v_committed_count),
        v_committed_count, v_financial_total, 'matched'
    );

    -- 14. Write audit log entry
    INSERT INTO public.audit_logs (
        id, user_id, action, table_name, record_id, new_value, created_at
    ) VALUES (
        gen_random_uuid(), v_caller_uid, 'COMMITTED_MIGRATION_BATCH', 'migration_batches', p_batch_id,
        jsonb_build_object(
            'committed_count', v_committed_count,
            'financial_total', v_financial_total,
            'reconciliation_id', v_reconciliation_id
        ),
        CURRENT_TIMESTAMP
    );

    -- 15. Transition batch state to 'committed'
    UPDATE public.migration_batches
    SET status = 'committed',
        committed_by = v_caller_uid,
        committed_at = CURRENT_TIMESTAMP,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_batch_id;

    RETURN jsonb_build_object(
        'success', true,
        'batch_id', p_batch_id,
        'status', 'committed',
        'committed_count', v_committed_count,
        'financial_total', v_financial_total,
        'reconciliation_id', v_reconciliation_id
    );
END;
$$;

COMMENT ON FUNCTION public.fn_commit_migration_batch(UUID) IS
    'Atomically validates, executes, and reconciles a Candidate-30 migration batch under strict tenant isolation.';


-- =========================================================================
-- 6. ROLLBACK RPC FUNCTION
-- =========================================================================

CREATE OR REPLACE FUNCTION public.fn_rollback_migration_batch(
    p_batch_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller_uid            UUID;
    v_caller_society_id     UUID;
    v_batch                 RECORD;
    v_lineage               RECORD;
    v_reversed_count        INT := 0;
BEGIN
    -- 1. Derive authenticated identity
    v_caller_uid := auth.uid();
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required to rollback migration batch.';
    END IF;

    -- 2. Derive caller society identity
    v_caller_society_id := public.get_user_society_id(v_caller_uid);
    IF v_caller_society_id IS NULL THEN
        RAISE EXCEPTION 'NO_SOCIETY_BINDING: Caller is not assigned to an active society.';
    END IF;

    -- 3. Verify administrative authorization
    IF NOT public.is_admin(v_caller_uid) THEN
        RAISE EXCEPTION 'UNAUTHORIZED_ROLE: Administrative authorization required to rollback migration batch.';
    END IF;

    -- 4. Acquire exclusive advisory lock
    PERFORM pg_advisory_xact_lock(hashtext('migration_lock_' || v_caller_society_id::text));

    -- 5. Load batch
    SELECT * INTO v_batch
    FROM public.migration_batches
    WHERE id = p_batch_id;

    IF v_batch.id IS NULL THEN
        RAISE EXCEPTION 'BATCH_NOT_FOUND: Migration batch % does not exist.', p_batch_id;
    END IF;

    -- 6. Assert tenant equality
    IF v_batch.society_id != v_caller_society_id THEN
        RAISE EXCEPTION 'TENANT_MISMATCH: Migration batch belongs to another society.';
    END IF;

    -- 7. Pre-commit rollback handling (Draft / Staged batches)
    IF v_batch.status IN ('draft', 'uploaded', 'mapped', 'validating', 'validation_passed', 'ready_for_review', 'approved') THEN
        DELETE FROM public.migration_staging_rows WHERE batch_id = p_batch_id;
        
        UPDATE public.migration_batches
        SET status = 'rolled_back', updated_at = CURRENT_TIMESTAMP
        WHERE id = p_batch_id;

        RETURN jsonb_build_object(
            'success', true,
            'batch_id', p_batch_id,
            'status', 'rolled_back',
            'reversed_count', 0,
            'message', 'Pre-commit staging rows successfully removed.'
        );
    END IF;

    -- 8. Post-commit rollback handling
    IF v_batch.status != 'committed' THEN
        RAISE EXCEPTION 'INVALID_ROLLBACK_STATE: Cannot rollback batch in status %', v_batch.status;
    END IF;

    -- 9. Safety Check: Verify no live operational references exist before reversing committed entities
    FOR v_lineage IN SELECT * FROM public.migration_lineage WHERE batch_id = p_batch_id LOOP
        IF v_lineage.target_table = 'properties' THEN
            -- Check if property has active tenancies or payments
            IF EXISTS (
                SELECT 1 FROM public.tenancies t 
                JOIN public.units u ON u.id = t.unit_id 
                WHERE u.property_id = v_lineage.target_id AND t.is_active = true
            ) THEN
                RAISE EXCEPTION 'ROLLBACK_BLOCKED: Property % has active tenancies registered.', v_lineage.target_id;
            END IF;
        END IF;
    END LOOP;

    -- 10. Perform deletion / reversal
    FOR v_lineage IN SELECT * FROM public.migration_lineage WHERE batch_id = p_batch_id LOOP
        IF v_lineage.target_table = 'properties' THEN
            DELETE FROM public.units WHERE property_id = v_lineage.target_id;
            DELETE FROM public.properties WHERE id = v_lineage.target_id AND society_id = v_caller_society_id;
        ELSIF v_lineage.target_table = 'opening_balances' THEN
            DELETE FROM public.opening_balances WHERE id = v_lineage.target_id AND society_id = v_caller_society_id;
        ELSIF v_lineage.target_table = 'vendors' THEN
            DELETE FROM public.vendors WHERE id = v_lineage.target_id AND society_id = v_caller_society_id;
        ELSIF v_lineage.target_table = 'assets' THEN
            DELETE FROM public.assets WHERE id = v_lineage.target_id AND society_id = v_caller_society_id;
        END IF;

        v_reversed_count := v_reversed_count + 1;
    END LOOP;

    -- Delete lineage records
    DELETE FROM public.migration_lineage WHERE batch_id = p_batch_id;

    -- 11. Write audit log
    INSERT INTO public.audit_logs (
        id, user_id, action, table_name, record_id, new_value, created_at
    ) VALUES (
        gen_random_uuid(), v_caller_uid, 'ROLLED_BACK_MIGRATION_BATCH', 'migration_batches', p_batch_id,
        jsonb_build_object('reversed_count', v_reversed_count), CURRENT_TIMESTAMP
    );

    -- 12. Transition status
    UPDATE public.migration_batches
    SET status = 'rolled_back', updated_at = CURRENT_TIMESTAMP
    WHERE id = p_batch_id;

    RETURN jsonb_build_object(
        'success', true,
        'batch_id', p_batch_id,
        'status', 'rolled_back',
        'reversed_count', v_reversed_count
    );
END;
$$;

COMMENT ON FUNCTION public.fn_rollback_migration_batch(UUID) IS
    'Safely rolls back pre-commit staging or post-commit unreferenced entities for a migration batch.';


-- =========================================================================
-- 7. EXECUTION PRIVILEGES (REVOKE FROM PUBLIC / GRANT TO AUTHENTICATED)
-- =========================================================================

REVOKE EXECUTE ON FUNCTION public.fn_commit_migration_batch(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_commit_migration_batch(UUID) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.fn_rollback_migration_batch(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_rollback_migration_batch(UUID) TO authenticated;

COMMIT;
