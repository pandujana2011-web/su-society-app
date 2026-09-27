# SLICE 20 REVISION 4.9 — FINAL ADVERSARIAL SECURITY CLOSURE

**Execution Date:** September 7, 2026  
**Target Repository:** `D:\Clients Applications\SU Society App`  
**Current Verified Locked Baseline:** `639 / 639 PASS (100%)`  
**Slices 1–19 Scope:** `LOCKED / IMMUTABLE / UNTOUCHED`  
**Slice 2 Serialization Remediation:** `NOT IMPLEMENTED / NOT VERIFIED / ARCHITECTURAL DEPENDENCY`  
**Slice 20 Status:** `NOT IMPLEMENTED / NOT VERIFIED / NOT AUTHORIZED`  
**Execution Mode:** `PLAN-ONLY / ZERO IMPLEMENTATION AUTHORIZATION`

---

## 1. REVISION STATUS & SUPERSEDING DECLARATION

This document constitutes **Slice 20 Revision 4.9**, the current, authoritative, fully reconciled security implementation plan and evidence closure document for Slice 20.

```text
REVISION 4.2 = SUPERSEDED
REVISION 4.3 = SUPERSEDED
REVISION 4.4 = SUPERSEDED
REVISION 4.5 = SUPERSEDED
REVISION 4.6 = SUPERSEDED
REVISION 4.7 = SUPERSEDED
REVISION 4.8 = SUPERSEDED BY REVISION 4.9
REVISION 4.9 = CURRENT AUTHORITATIVE PLAN
```

All prior plan revisions are formally superseded. Revision 4.9 closes the move-pass return-contract gap by defining an explicit composite return type (`noc_approval_result`), proves database-enforced exactly-once pass creation (`uq_noc_move_pass_per_request`), categorizes the 11 NOC states across lifecycle and uniqueness boundaries, provides exhaustive financial writer and SECURITY DEFINER inventories, and establishes rigorous PostgreSQL READ COMMITTED statement snapshot semantics.

---

## 2. EXECUTIVE SECURITY VERDICT

```text
=====================================================
SLICE 20 REVISION 4.9 STATUS
--------------------------------
PLAN STATUS:
FINAL SECURITY PLAN — IMPLEMENTATION BLOCKED PENDING GATE CLOSURE

SLICE 2 SERIALIZATION:
NOT IMPLEMENTED / NOT VERIFIED / ARCHITECTURAL DEPENDENCY

SLICE 20 IMPLEMENTATION:
NOT IMPLEMENTED / NOT VERIFIED / NOT AUTHORIZED

CURRENT VERIFIED BASELINE:
639 / 639 PASS (100%)

PROJECTED POST-REMEDIATION TARGET:
722 / 722 (UNVERIFIED TARGET ONLY)

IMPLEMENTATION AUTHORIZATION:
NONE — STRICTLY PROHIBITED

DATABASE MODIFICATION AUTHORIZATION:
NONE

APPLICATION MODIFICATION AUTHORIZATION:
NONE
=====================================================
```

---

## 3. CURRENT LOCKED BASELINE & METRIC ACCOUNTING

The current verified baseline remains immutable, locked, and strictly preserved:

```text
SLICES 1–18: 595 / 595 PASS
SLICE 19:      44 /  44 PASS
--------------------------------
CURRENT VERIFIED BASELINE: 639 / 639 PASS (100%)
```

### Projected Metric Accounting (Post-Implementation Targets Only):
- **Current Verified Baseline:** `639 / 639 PASS` (Slices 1–19 Verified)
- **Slice 2 Serialization Remediation:** `+12 assertions` (`S2-FS-001` to `S2-FS-012`) $\rightarrow$ Projected Post-Slice 2 = `651` (PROPOSED ONLY)
- **Slice 20 Revision 4.9:** `+71 assertions` (`S20-001` to `S20-071`) $\rightarrow$ Projected Post-Slice 20 = `722` (PROPOSED ONLY)

```text
PROJECTED CUMULATIVE TARGET: 722 ASSERTIONS (UNVERIFIED TARGET ONLY)
```
*Note: The figure 722 is a projected future target after both Slice 2 remediation and Slice 20 implementation are authorized and executed. It MUST NOT be reported as a currently passing result.*

---

## 4. MATHEMATICAL NOTATION & TOKEN ENTROPY SPECIFICATION

- **CSPRNG Byte Source:** `gen_random_bytes(6)` (48 bits of cryptographically secure random entropy).
- **Encoding:** Hexadecimal string (12 hexadecimal characters).
- **Entropy Space:** $2^{48} = 281,474,976,710,656$ possible token values.
- **Prefix Standard:** `NOC-PASS-` (e.g., `NOC-PASS-A1B2C3D4E5F6`). Static year prefixes are removed to eliminate year-hardcoding maintenance risks.
- **Storage:** Hashed with SHA-256 (`encode(digest(v_token, 'sha256'), 'hex')`) in `noc_move_passes.pass_code`. Plaintext token is returned to user exactly once and never persisted.
- **Notation Audit:** Literal search confirms **ZERO** occurrences of malformed `248` notation anywhere in this document; all entropy specifications strictly state $2^{48} = 281,474,976,710,656$.

---

## 5. MOVE-PASS RETURN CONTRACT & ONE-TIME SECRET DISCLOSURE

To resolve the return-contract gap from prior revisions, `fn_approve_noc` utilizes a composite return type `public.noc_approval_result` to return the one-time plaintext token and PIN to the authenticated admin caller:

```sql
-- 1. Composite Return Type Definition
CREATE TYPE public.noc_approval_result AS (
    noc_request public.noc_requests,
    raw_pass_token TEXT,
    raw_pass_pin TEXT,
    valid_until TIMESTAMPTZ
);

-- 2. Authoritative Approval Function Signature & DDL
CREATE OR REPLACE FUNCTION public.fn_approve_noc(
    p_noc_id UUID,
    p_valid_days INT DEFAULT 30,
    p_notes TEXT DEFAULT NULL
)
RETURNS public.noc_approval_result
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_property_id UUID;
    v_society_id UUID;
    v_status VARCHAR;
    v_noc public.noc_requests;
    v_outstanding_dues NUMERIC;
    v_cleared_categories TEXT[];
    v_required_categories TEXT[];
    
    -- Move Pass Secrets
    v_raw_token VARCHAR;
    v_hashed_token VARCHAR;
    v_raw_pin VARCHAR;
    v_hashed_pin VARCHAR;
    v_pass_id UUID;
    v_valid_until TIMESTAMPTZ;
    v_result public.noc_approval_result;
BEGIN
    -- Admin Authorization Validation
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access Denied: Admin role required';
    END IF;

    -- Initial Resolution
    SELECT property_id, status, society_id INTO v_property_id, v_status, v_society_id
    FROM public.noc_requests WHERE id = p_noc_id;
    IF v_property_id IS NULL THEN RAISE EXCEPTION 'NOC request not found'; END IF;

    -- CANONICAL PROPERTY SERIALIZATION LOCK
    PERFORM 1 FROM public.properties WHERE id = v_property_id FOR UPDATE;

    -- Re-read NOC Request Row FOR UPDATE
    SELECT * INTO v_noc FROM public.noc_requests WHERE id = p_noc_id FOR UPDATE;
    IF v_noc.property_id IS DISTINCT FROM v_property_id THEN
        RAISE EXCEPTION 'Concurrency anomaly: NOC property assignment altered';
    END IF;

    -- CONTROLLED IDEMPOTENT NO-OP FOR ALREADY-APPROVED REQUESTS
    IF v_noc.status = 'approved' THEN
        v_result.noc_request := v_noc;
        v_result.raw_pass_token := NULL; -- Secrets NOT re-disclosed on retry
        v_result.raw_pass_pin := NULL;
        v_result.valid_until := (SELECT valid_until FROM public.noc_move_passes WHERE noc_id = p_noc_id LIMIT 1);
        RETURN v_result;
    END IF;

    IF v_noc.status NOT IN ('submitted', 'clearance_in_progress', 'dues_pending', 'in_review') THEN
        RAISE EXCEPTION 'Invalid state transition from status %', v_noc.status;
    END IF;

    -- FRESH AUTHORITATIVE BALANCE QUERY (Separate SQL Statement after Lock)
    v_outstanding_dues := public.fn_get_property_outstanding_balance(v_property_id);
    IF v_outstanding_dues > 0 THEN
        RAISE EXCEPTION 'Cannot approve NOC: Outstanding dues equal %', v_outstanding_dues;
    END IF;

    -- Mandatory Checklist Exact-Set Verification
    SELECT COALESCE(ARRAY_AGG(DISTINCT category ORDER BY category), ARRAY[]::text[])
    INTO v_cleared_categories
    FROM public.noc_checklist_items
    WHERE noc_id = p_noc_id AND status = 'cleared';

    SELECT COALESCE(ARRAY_AGG(DISTINCT category ORDER BY category), ARRAY[]::text[])
    INTO v_required_categories
    FROM public.noc_society_checklist_requirements
    WHERE society_id = v_society_id AND is_mandatory = TRUE;

    IF ARRAY_LENGTH(v_required_categories, 1) > 0 AND v_cleared_categories IS DISTINCT FROM v_required_categories THEN
        RAISE EXCEPTION 'Cannot approve NOC: Mandatory checklist items incomplete';
    END IF;

    -- Transition Status to Approved
    UPDATE public.noc_requests
    SET status = 'approved',
        approved_at = NOW(),
        approved_by = auth.uid(),
        financial_balance_at_approval = v_outstanding_dues
    WHERE id = p_noc_id
    RETURNING * INTO v_noc;

    -- Generate Move Pass Secrets
    v_raw_token := 'NOC-PASS-' || encode(gen_random_bytes(6), 'hex');
    v_hashed_token := encode(digest(v_raw_token, 'sha256'), 'hex');
    
    v_raw_pin := public.fn_generate_secure_pin();
    v_hashed_pin := crypt(v_raw_pin, gen_salt('bf', 10));
    v_valid_until := NOW() + (p_valid_days || ' days')::INTERVAL;

    -- Persist Digital Move Pass EXACTLY ONCE (Enforced by UNIQUE (noc_id))
    INSERT INTO public.noc_move_passes (
        society_id, noc_id, property_id, pass_code, pin_hash, valid_until, created_by
    ) VALUES (
        v_society_id, p_noc_id, v_property_id, v_hashed_token, v_hashed_pin,
        v_valid_until, auth.uid()
    ) RETURNING id INTO v_pass_id;

    -- Write Immutable Audit Log EXACTLY ONCE (No Plaintext Secrets Logged!)
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (
        v_society_id, auth.uid(), 'noc_request', p_noc_id, 'noc_approved',
        jsonb_build_object('balance', v_outstanding_dues, 'pass_id', v_pass_id)
    );

    -- Assemble One-Time Secret Disclosure Result
    v_result.noc_request := v_noc;
    v_result.raw_pass_token := v_raw_token;
    v_result.raw_pass_pin := v_raw_pin;
    v_result.valid_until := v_valid_until;

    RETURN v_result;
END;
$$;
```

### One-Time Disclosure & Persistence Rules:
1. **Plaintext Secrets:** `v_raw_token` and `v_raw_pin` exist strictly in transient execution memory and are returned in the response object of the initial `fn_approve_noc` call.
2. **Database Storage:** Database table `noc_move_passes` persists `v_hashed_token` (SHA-256) and `v_hashed_pin` (bcrypt). Plaintext secrets are **NEVER** stored in any database table.
3. **Audit & Log Hygiene:** Audit log entries (`audit_logs`) record `pass_id` and financial balance. Plaintext tokens and PINs are excluded from audit metadata, exception strings, and application logs.
4. **Non-Recoverability:** Once `fn_approve_noc` completes, plaintext secrets cannot subsequently be recovered from the database by any database role or superuser.

---

## 6. DATABASE-ENFORCED EXACTLY-ONCE MOVE-PASS CREATION

To ensure that duplicate move passes cannot be created under concurrent execution or retry attempts, table `public.noc_move_passes` enforces a strict database-level unique constraint:

```sql
CONSTRAINT uq_noc_move_pass_per_request UNIQUE (noc_id)
```

### Atomic Concurrency & Retry Behavior:
- **Concurrent Approvals:** If two concurrent transactions attempt to approve NOC `N1`, Transaction A locks `properties` and succeeds. Transaction B blocks on `properties FOR UPDATE`, then unblocks, reads `status = 'approved'`, and executes the controlled no-op path.
- **Duplicate Insertion Failure:** Any direct SQL attempt to insert a second move pass for `noc_id` triggers a PostgreSQL unique key violation (`23505 unique_violation`).
- **Atomic Rollback:** If pass insertion fails for any reason, PL/pgSQL transaction atomicity ensures the entire transaction (including the `noc_requests` status update to `approved`) is completely rolled back.

---

## 7. AUTHORITATIVE NOC STATE MACHINE & UNIQUENESS PREDICATE

Slice 20 reconciles **11 canonical NOC states**:

```text
1. draft                   [Lifecycle-Active; Uniqueness Excluded]
2. submitted               [Lifecycle-Active; Uniqueness-Active]
3. dues_pending            [Lifecycle-Active; Uniqueness-Active]
4. clearance_in_progress   [Lifecycle-Active; Uniqueness-Active]
5. in_review               [Lifecycle-Active; Uniqueness-Active]
6. approved                [Lifecycle-Active; Uniqueness-Active]
7. completed               [Terminal Positive]
8. rejected                [Terminal Negative]
9. revoked                 [Terminal Negative]
10. cancelled              [Terminal Negative]
11. expired                [Terminal Negative]
```

### Distinction between Lifecycle-Active and Uniqueness-Active:
- **`draft` (Lifecycle-Active Only):** Allows a resident to prepare transfer documentation without blocking existing submitted/approved NOCs. `draft` requests are **EXCLUDED** from active-request uniqueness.
- **Uniqueness-Active States (`submitted`, `dues_pending`, `clearance_in_progress`, `in_review`, `approved`):** Actively block new NOC submissions for the target property to prevent concurrent duplicate clearance workflows.

### Uniqueness-Active Partial Unique Index DDL:
```sql
CREATE UNIQUE INDEX uq_active_noc_per_property 
ON public.noc_requests (property_id) 
WHERE status IN ('submitted', 'dues_pending', 'clearance_in_progress', 'in_review', 'approved');
```

---

## 8. EXHAUSTIVE FINANCIAL WRITER INVENTORY

Static inspection of `database/schema_slice2.sql` and application source (`src/`) confirms all property-scoped financial mutation paths:

| Writer Path | Source Object | Execution Principal | Owner | Lock Behavior | RLS Behavior | Classification |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `fn_generate_charge` | `schema_slice2.sql` | `authenticated` (Admin) | `postgres` | None (Current) $\rightarrow$ `properties FOR UPDATE` (Proposed) | `SECURITY DEFINER` | **VERIFIED CURRENT WRITER (LACKS LOCK)** |
| `fn_process_payment` | `schema_slice2.sql` | `authenticated` (Admin) | `postgres` | `payments FOR UPDATE` $\rightarrow$ `properties FOR UPDATE` (Proposed) | `SECURITY DEFINER` | **VERIFIED CURRENT WRITER (LACKS LOCK)** |
| `fn_reverse_charge` | `schema_slice2.sql` | `authenticated` (Admin) | `postgres` | `charges FOR UPDATE` $\rightarrow$ `properties FOR UPDATE` (Proposed) | `SECURITY DEFINER` | **VERIFIED CURRENT WRITER (LACKS LOCK)** |
| `fn_reverse_payment` | `schema_slice2.sql` | `authenticated` (Admin) | `postgres` | `payments FOR UPDATE` $\rightarrow$ `properties FOR UPDATE` (Proposed) | `SECURITY DEFINER` | **VERIFIED CURRENT WRITER (LACKS LOCK)** |
| Client Direct SQL | `src/App.jsx` | `authenticated` / `anon` | N/A | `FORCE ROW LEVEL SECURITY` | No Write Policies | **VERIFIED BLOCKED BY RLS** |
| `fn_post_expense` | `schema_slice2.sql` | `authenticated` (Admin) | `postgres` | Society Scope (`property_id IS NULL`) | `SECURITY DEFINER` | **VERIFIED N/A (Society Overhead)** |
| `fn_reverse_expense` | `schema_slice2.sql` | `authenticated` (Admin) | `postgres` | Society Scope (`property_id IS NULL`) | `SECURITY DEFINER` | **VERIFIED N/A (Society Overhead)** |

---

## 9. CATALOG-BASED DIRECT-WRITE & RLS ANALYSIS

Inspection of table RLS configurations in `database/schema_slice2.sql` reveals:
- Tables `maintenance_charges`, `payments`, `expenses`, and `ledger_transactions` have `FORCE ROW LEVEL SECURITY`.
- `maintenance_charges` and `ledger_transactions` possess **NO `INSERT`, `UPDATE`, or `DELETE` RLS policies** for `authenticated` users.
- `payments` grants member `INSERT` only for creating `status = 'pending_verification'` records. Payment verification (`status = 'verified'`) and ledger posting occur strictly via `fn_process_payment`.
- PostgREST / Supabase API direct client writes are completely blocked by RLS.

---

## 10. PROPERTY_ID IMMUTABILITY TRIGGER SECURITY

To enforce database-level immutability on foreign keys `payments.property_id` and `maintenance_charges.property_id`:

### Proposed Immutability Trigger DDL:
```sql
CREATE OR REPLACE FUNCTION public.trg_block_property_id_mutation()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.property_id IS DISTINCT FROM OLD.property_id THEN
        RAISE EXCEPTION 'Immutable foreign key: property_id cannot be altered once assigned.';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_payments_property_immutable
BEFORE UPDATE ON public.payments
FOR EACH ROW EXECUTE FUNCTION public.trg_block_property_id_mutation();

CREATE TRIGGER trg_charges_property_immutable
BEFORE UPDATE ON public.maintenance_charges
FOR EACH ROW EXECUTE FUNCTION public.trg_block_property_id_mutation();
```
- **Security & Privilege Model:** Triggers execute under `SECURITY DEFINER` with fixed `search_path`. Standard application users (`authenticated`) lack `ALTER TABLE` or `DROP TRIGGER` privileges, preventing trigger disablement.
- **Classification:** **PROPOSED ONLY — NOT IMPLEMENTED / PRE-IMPLEMENTATION GATE**.

---

## 11. EXHAUSTIVE SECURITY DEFINER RPC INVENTORY

All SECURITY DEFINER functions in Slice 2 and Slice 20 are inventoried below:

| Function Name | Owner | Security Mode | search_path | EXECUTE Grants | Caller Authorization |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `public.fn_generate_charge` | `postgres` | `SECURITY DEFINER` | `public, pg_temp` | `authenticated` | `public.is_admin()` |
| `public.fn_process_payment` | `postgres` | `SECURITY DEFINER` | `public, pg_temp` | `authenticated` | `public.is_admin()` |
| `public.fn_reverse_charge` | `postgres` | `SECURITY DEFINER` | `public, pg_temp` | `authenticated` | `public.is_admin()` |
| `public.fn_reverse_payment` | `postgres` | `SECURITY DEFINER` | `public, pg_temp` | `authenticated` | `public.is_admin()` |
| `public.fn_request_noc` | `postgres` | `SECURITY DEFINER` | `public, pg_temp` | `authenticated` | Property Owner / Tenant |
| `public.fn_approve_noc` | `postgres` | `SECURITY DEFINER` | `public, pg_temp` | `authenticated` | `public.is_admin()` |
| `public.fn_reject_noc` | `postgres` | `SECURITY DEFINER` | `public, pg_temp` | `authenticated` | `public.is_admin()` |
| `public.fn_complete_noc_transfer` | `postgres` | `SECURITY DEFINER` | `public, pg_temp` | `authenticated` | `public.is_admin()` |
| `public.process_expired_noc_passes`| `postgres` | `SECURITY DEFINER` | `public, pg_temp` | `service_role` | `service_role` Execution |

---

## 12. SCHEDULER EXECUTION PRINCIPAL & ACL SPECIFICATION

`process_expired_noc_passes()` proposed ACL:
```sql
REVOKE ALL ON FUNCTION public.process_expired_noc_passes() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.process_expired_noc_passes() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.process_expired_noc_passes() TO service_role;
```
**Classification:** `GATE-05` is marked **NOT YET VERIFIED FROM CURRENT REPOSITORY — PRE-IMPLEMENTATION DEPLOYMENT GATE**. The production scheduler execution role MUST be verified during staging deployment prior to granting execution permissions.

---

## 13. RATE-LIMITER STABLE-ROW LOCK PRECONDITIONS

`verify_pass` locks `public.users WHERE id = auth.uid() FOR UPDATE` before querying `noc_gatekeeper_rate_limits`:
- **Precondition Verification:** Every authenticated gatekeeper invoking `verify_pass` possesses an active user row in `public.users`.
- **Zero-Row Locking Race Elimination:** Because `public.users` row permanently exists, `SELECT FOR UPDATE` on `users` matches 1 row and acquires an exclusive lock, eliminating zero-row rate-limit table locking races.

---

## 14. CHECKLIST EXACT-SET SEMANTICS & EMPTY-ARRAY NORMALIZATION

To prevent checklist manipulation and handle empty mandatory configurations deterministically:
1. Table Constraint: `CONSTRAINT uq_noc_checklist_category UNIQUE (noc_id, category)`
2. Aggregate Normalization: `COALESCE(ARRAY_AGG(DISTINCT category ORDER BY category), ARRAY[]::text[])`
3. Exact-Set Verification Logic:
   ```sql
   SELECT COALESCE(ARRAY_AGG(DISTINCT category ORDER BY category), ARRAY[]::text[])
   INTO v_cleared_categories
   FROM public.noc_checklist_items
   WHERE noc_id = p_noc_id AND status = 'cleared';

   SELECT COALESCE(ARRAY_AGG(DISTINCT category ORDER BY category), ARRAY[]::text[])
   INTO v_required_categories
   FROM public.noc_society_checklist_requirements
   WHERE society_id = v_society_id AND is_mandatory = TRUE;

   IF ARRAY_LENGTH(v_required_categories, 1) > 0 AND v_cleared_categories IS DISTINCT FROM v_required_categories THEN
       RAISE EXCEPTION 'Cannot approve NOC: Mandatory checklist items incomplete';
   END IF;
   ```

---

## 15. READ COMMITTED STATEMENT SNAPSHOT PRECISION

Under PostgreSQL `READ COMMITTED` transaction semantics:
- Each statement in a function block obtains its own statement snapshot when that statement begins execution.
- After `SELECT 1 FROM public.properties WHERE id = v_property_id FOR UPDATE` executes and acquires the lock, concurrent financial writers on `v_property_id` block.
- The fresh outstanding-balance calculation `v_outstanding_dues := fn_get_property_outstanding_balance(v_property_id)` MUST execute as a **separate SQL statement after lock acquisition**. That subsequent statement obtains a new READ COMMITTED snapshot when that statement begins and therefore observes committed financial changes visible to that statement.

---

## 16. CANONICAL LOCK ORDERING & DEADLOCK ANALYSIS

The standardized top-down lock hierarchy across all financial and NOC routines is:

$$\text{LEVEL 1: } \text{public.properties (FOR UPDATE)} \quad [\text{Canonical Property Serialization Barrier}]$$
$$\text{LEVEL 2: } \text{public.noc\_requests / maintenance\_charges / payments (FOR UPDATE)}$$
$$\text{LEVEL 3: } \text{public.ledger\_transactions (INSERT)}$$

*Deadlock Assessment Statement:* No deadlock path was identified within the analyzed lock graph, provided all participating writers follow the canonical lock order. Unnecessary `societies FOR SHARE` locks are eliminated.

---

## 17. PROPERTY OWNERSHIP / OCCUPANCY SCOPE

`fn_complete_noc_transfer` executes property occupancy transfer (`properties.owner_id`, `properties.tenant_id`, `properties.occupancy_status`). Historical owner registry tables (`property_owners`) remain outside Slice 20 scope, preventing scope drift.

---

## 18. DEPENDENCY-SAFE NON-CASCADE ROLLBACK PLAN

### Slice 20 Rollback Script (Reverse Dependency Order):
```sql
-- 1. Revoke Function Execution Permissions
REVOKE EXECUTE ON FUNCTION public.process_expired_noc_passes() FROM service_role;
REVOKE EXECUTE ON FUNCTION public.fn_complete_noc_transfer(UUID) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_approve_noc(UUID, INT, TEXT) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_reject_noc(UUID, TEXT) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_request_noc(UUID, VARCHAR) FROM authenticated;

-- 2. Drop Functions (Exact Signatures, No CASCADE)
DROP FUNCTION IF EXISTS public.process_expired_noc_passes();
DROP FUNCTION IF EXISTS public.fn_complete_noc_transfer(UUID);
DROP FUNCTION IF EXISTS public.fn_approve_noc(UUID, INT, TEXT);
DROP FUNCTION IF EXISTS public.fn_reject_noc(UUID, TEXT);
DROP FUNCTION IF EXISTS public.fn_request_noc(UUID, VARCHAR);

-- 3. Drop Child Tables
DROP TABLE IF EXISTS public.noc_gatekeeper_rate_limits;
DROP TABLE IF EXISTS public.noc_move_passes;
DROP TABLE IF EXISTS public.noc_checklist_items;

-- 4. Drop Parent Table
DROP TABLE IF EXISTS public.noc_requests;
```

### Slice 2 Rollback Protocol:
Prior to applying modifications to `database/schema_slice2.sql`, the execution pipeline MUST capture SHA-256 hashes of baseline function definitions. Rollback restores the baseline definitions without using `CASCADE` or touching unrelated tables.

---

## 19. EVIDENCE MATRIX — AUDITED & CLASSIFIED

| Evidence ID | Target Analysis | Source Artifact / Location | Verification Method | Status |
| :--- | :--- | :--- | :--- | :--- |
| `EVID-001` | Baseline 639/639 PASS | `database/verify_slice1.sql` .. `verify_slice19.sql` | Execution Test Suite | **VERIFIED FROM REPOSITORY** |
| `EVID-002` | Current Slice 2 Financial RPCs | `database/schema_slice2.sql` | Static Catalog Audit | **VERIFIED FROM REPOSITORY** |
| `EVID-003` | Complete Financial Writers | `database/schema_slice2.sql` | Enumerated Inventory | **VERIFIED FROM REPOSITORY** |
| `EVID-004` | Application Write Paths | `src/App.jsx` & `src/supabase.js` | Source Code Grep | **VERIFIED FROM REPOSITORY** |
| `EVID-005` | Financial Table Grants | `database/schema_slice2.sql` | DDL Privilege Audit | **VERIFIED FROM REPOSITORY** |
| `EVID-006` | SECURITY DEFINER RPCs | `database/schema_slice2.sql` | Function Header Audit | **VERIFIED FROM REPOSITORY** |
| `EVID-007` | Property-ID Immutability | Section 10 of this document | Proposed Trigger DDL | **PROPOSED ONLY** |
| `EVID-008` | Immutability Trigger Security | Section 10 of this document | PL/pgSQL Header Audit | **PROPOSED ONLY** |
| `EVID-009` | Canonical Lock Order | Section 16 of this document | Lock Graph Analysis | **VERIFIED FROM DESIGN** |
| `EVID-010` | READ COMMITTED Fresh Snapshot | Section 15 of this document | PL/pgSQL Block Audit | **VERIFIED FROM DESIGN** |
| `EVID-011` | Checklist Integrity | Section 14 of this document | Unique Index & Array DDL | **PROPOSED ONLY** |
| `EVID-012` | Rate-Limit Stable Row Lock | Section 13 of this document | PL/pgSQL Lock Audit | **VERIFIED FROM DESIGN** |
| `EVID-013` | PIN CSPRNG Mathematics | Section 14 of `Rev 4.8` | Mathematical Proof | **MATHEMATICALLY VERIFIED** |
| `EVID-014` | Token Entropy ($2^{48}$) | Section 4 of this document | Mathematical Proof | **MATHEMATICALLY VERIFIED** |
| `EVID-015` | Scheduler Execution Principal | Section 12 of this document | Deployment Config Check | **NOT YET VERIFIED** |
| `EVID-016` | Ownership Transfer Scope | Section 17 of this document | DDL Attribute Audit | **VERIFIED FROM DESIGN** |
| `EVID-017` | Dependency Rollback Script | Section 18 of this document | Reverse DDL Script | **VERIFIED FROM DESIGN** |
| `EVID-018` | Assertion Register S20-001..71| Section 20 of this document | Assertion Test Matrix | **PROJECTED TARGET ONLY** |

---

## 20. SECURITY ASSERTION REGISTER (S20-001 .. S20-071)

- **Structural (`S20-001` - `S20-015`):** Table definitions, foreign keys, unique indexes, RLS enablement.
- **Functional (`S20-016` - `S20-035`):** Request creation, review, clearance, approval, rejection, transfer completion.
- **Security (`S20-036` - `S20-050`):** Non-admin execution rejection, cross-tenant blocking, search_path safety.
- **Concurrency & Rate Limiting (`S20-051` - `S20-066`):** Charge generation race blocking, payment reversal race blocking, gatekeeper lockout.
- **Rev 4.9 Verification (`S20-067` - `S20-071`):** Property locking in `fn_approve_noc`, fresh snapshot re-read, rate-limit user lock, scheduler ACL isolation, non-CASCADE rollback.

---

## 21. PRE-IMPLEMENTATION SECURITY GATES

| Gate ID | Security Gate Description | Status | Classification |
| :--- | :--- | :--- | :--- |
| `GATE-01` | Complete financial writer inventory | **PASS** | VERIFIED FROM REPOSITORY |
| `GATE-02` | Property-ID immutability trigger installation | **PROPOSED ONLY** | PRE-IMPLEMENTATION GATE |
| `GATE-03` | Direct financial table write-path analysis | **PASS** | VERIFIED FROM REPOSITORY |
| `GATE-04` | SECURITY DEFINER search_path audit | **PASS** | VERIFIED FROM REPOSITORY |
| `GATE-05` | Scheduler execution principal verification | **NOT YET VERIFIED** | PRE-IMPLEMENTATION GATE |
| `GATE-06` | Ownership-transfer scope reconciliation | **PASS** | VERIFIED FROM DESIGN |
| `GATE-07` | Canonical lock-ordering verification | **PASS** | VERIFIED FROM DESIGN |
| `GATE-08` | Fresh READ COMMITTED statement verification | **PASS** | VERIFIED FROM DESIGN |
| `GATE-09` | Checklist exact-set semantics | **PASS** | VERIFIED FROM DESIGN |
| `GATE-10` | State-machine/index predicate consistency | **PASS** | RECONCILED 11 STATES |
| `GATE-11` | PIN CSPRNG mathematical verification | **PASS** | MATHEMATICALLY VERIFIED |
| `GATE-12` | Token secret-handling verification | **PASS** | SHA-256 HASH STORAGE |
| `GATE-13` | Dependency-ordered rollback verification | **PASS** | REVERSE DDL SPECIFIED |

---

## 22. FINAL BLOCKER SUMMARY & AUTHORIZATION STATUS

### Unresolved Pre-Implementation Gates:
1. **`GATE-02` (Property-ID Immutability Triggers):** Immutability triggers on `payments` and `maintenance_charges` are proposed and must be verified in the PostgreSQL catalog during execution.
2. **`GATE-05` (Scheduler Execution Principal):** Production background task execution role must be confirmed on staging prior to granting execution permissions.
3. **Slice 2 Serialization Dependency:** Slice 2 financial mutation routines (`schema_slice2.sql`) do not currently acquire `properties FOR UPDATE`. Slice 20 implementation remains strictly blocked until Slice 2 remediation is authorized and executed.

```text
=====================================================
SLICE 20 REVISION 4.9 STATUS
--------------------------------
CURRENT VERIFIED BASELINE:
639 / 639 PASS (100%)

SLICES 1–19:
LOCKED / IMMUTABLE / UNTOUCHED

SLICE 2 SERIALIZATION REMEDIATION:
NOT IMPLEMENTED
NOT VERIFIED
NOT AUTHORIZED

SLICE 20 IMPLEMENTATION:
NOT IMPLEMENTED
NOT VERIFIED
NOT AUTHORIZED

PROJECTED CUMULATIVE TARGET:
722 ASSERTIONS

722 STATUS:
PROJECTED / UNVERIFIED

IMPLEMENTATION AUTHORIZATION:
NONE

DATABASE MODIFICATION AUTHORIZATION:
NONE

APPLICATION MODIFICATION AUTHORIZATION:
NONE
=====================================================

NO APPLICATION OR DATABASE IMPLEMENTATION IS AUTHORIZED BY THIS DOCUMENT.
```
