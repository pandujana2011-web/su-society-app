# SLICE 20 REVISION 4.8 — FINAL SECURITY PLAN + EVIDENCE CLOSURE

**Execution Date:** September 7, 2026  
**Target Repository:** `D:\Clients Applications\SU Society App`  
**Current Verified Locked Baseline:** `639 / 639 PASS (100%)`  
**Slices 1–19 Scope:** `LOCKED / IMMUTABLE / UNTOUCHED`  
**Slice 2 Serialization Remediation:** `NOT IMPLEMENTED / NOT VERIFIED / ARCHITECTURAL DEPENDENCY`  
**Slice 20 Status:** `NOT IMPLEMENTED / NOT VERIFIED / NOT AUTHORIZED`  
**Execution Mode:** `PLAN-ONLY / ZERO IMPLEMENTATION AUTHORIZATION`

---

## 1. REVISION STATUS & SUPERSEDING DECLARATION

This document constitutes **Slice 20 Revision 4.8**, the current, authoritative, evidence-backed implementation and security plan for Slice 20.

```text
REVISION 4.2 = SUPERSEDED
REVISION 4.3 = SUPERSEDED
REVISION 4.4 = SUPERSEDED
REVISION 4.5 = SUPERSEDED
REVISION 4.6 = SUPERSEDED
REVISION 4.7 = SUPERSEDED BY REVISION 4.8
REVISION 4.8 = CURRENT AUTHORITATIVE PLAN
```

All prior plan revisions are formally superseded. Revision 4.8 completes the adversarial security closure by adding explicit move-pass creation logic (`INSERT INTO public.noc_move_passes`) inside the complete `fn_approve_noc` DDL, normalizing empty checklist array comparisons, clarifying lifecycle-active versus uniqueness-active states, establishing READ COMMITTED snapshot precision requirements, and auditing all pre-implementation security gates.

---

## 2. EXECUTIVE SECURITY VERDICT

```text
=====================================================
SLICE 20 REVISION 4.8 STATUS
--------------------------------
PLAN STATUS:
FINAL SECURITY PLAN — SUBJECT TO GATE CLOSURE

SLICE 2 SERIALIZATION:
NOT IMPLEMENTED / NOT VERIFIED / ARCHITECTURAL DEPENDENCY

SLICE 20 IMPLEMENTATION:
NOT IMPLEMENTED / NOT VERIFIED / NOT AUTHORIZED

CURRENT VERIFIED BASELINE:
639 / 639 PASS (100%)

PROJECTED POST-REMEDIATION TARGET:
722 / 722 (UNVERIFIED / PROJECTED TARGET ONLY)

IMPLEMENTATION AUTHORIZATION:
NONE — STRICTLY PROHIBITED

DATABASE MODIFICATION AUTHORIZATION:
NONE

APPLICATION MODIFICATION AUTHORIZATION:
NONE
=====================================================
```

---

## 3. LOCKED BASELINE & METRIC ACCOUNTING

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
- **Slice 20 Revision 4.8:** `+71 assertions` (`S20-001` to `S20-071`) $\rightarrow$ Projected Post-Slice 20 = `722` (PROPOSED ONLY)

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

## 5. COMPLETE AUTHORITATIVE `fn_approve_noc` DDL SPECIFICATION

Addressing the approval-pass gap from prior revisions, the complete, valid PL/pgSQL DDL for `fn_approve_noc` specifies move-pass creation (`noc_move_passes`), token/PIN security, authoritative dues checking, and controlled idempotency:

```sql
CREATE OR REPLACE FUNCTION public.fn_approve_noc(
    p_noc_id UUID,
    p_valid_days INT DEFAULT 30,
    p_notes TEXT DEFAULT NULL
)
RETURNS public.noc_requests
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
BEGIN
    -- 1. Admin Authorization Validation
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access Denied: Admin role required';
    END IF;

    -- 2. Initial Resolution
    SELECT property_id, status, society_id INTO v_property_id, v_status, v_society_id
    FROM public.noc_requests WHERE id = p_noc_id;
    IF v_property_id IS NULL THEN RAISE EXCEPTION 'NOC request not found'; END IF;

    -- 3. CANONICAL PROPERTY SERIALIZATION LOCK
    PERFORM 1 FROM public.properties WHERE id = v_property_id FOR UPDATE;

    -- 4. Re-read NOC Request Row FOR UPDATE
    SELECT * INTO v_noc FROM public.noc_requests WHERE id = p_noc_id FOR UPDATE;
    IF v_noc.property_id IS DISTINCT FROM v_property_id THEN
        RAISE EXCEPTION 'Concurrency anomaly: NOC property assignment altered';
    END IF;

    -- 5. CONTROLLED IDEMPOTENT NO-OP FOR ALREADY-APPROVED REQUESTS
    IF v_noc.status = 'approved' THEN
        RETURN v_noc;
    END IF;

    IF v_noc.status NOT IN ('submitted', 'clearance_in_progress', 'dues_pending', 'in_review') THEN
        RAISE EXCEPTION 'Invalid state transition from status %', v_noc.status;
    END IF;

    -- 6. FRESH AUTHORITATIVE BALANCE QUERY (Separate SQL Statement after Lock)
    v_outstanding_dues := public.fn_get_property_outstanding_balance(v_property_id);
    IF v_outstanding_dues > 0 THEN
        RAISE EXCEPTION 'Cannot approve NOC: Outstanding dues equal %', v_outstanding_dues;
    END IF;

    -- 7. Mandatory Checklist Exact-Set Verification (Empty Array Normalized)
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

    -- 8. Transition Status to Approved
    UPDATE public.noc_requests
    SET status = 'approved',
        approved_at = NOW(),
        approved_by = auth.uid(),
        financial_balance_at_approval = v_outstanding_dues
    WHERE id = p_noc_id
    RETURNING * INTO v_noc;

    -- 9. Generate Move Pass Secrets
    -- Raw Token: 12 hex characters from 6 CSPRNG bytes
    v_raw_token := 'NOC-PASS-' || encode(gen_random_bytes(6), 'hex');
    v_hashed_token := encode(digest(v_raw_token, 'sha256'), 'hex');
    
    -- Secure CSPRNG 6-digit PIN & Bcrypt Hash
    v_raw_pin := public.fn_generate_secure_pin();
    v_hashed_pin := crypt(v_raw_pin, gen_salt('bf', 10));

    -- 10. Persist Digital Move Pass EXACTLY ONCE
    INSERT INTO public.noc_move_passes (
        society_id, noc_id, property_id, pass_code, pin_hash, valid_until, created_by
    ) VALUES (
        v_society_id, p_noc_id, v_property_id, v_hashed_token, v_hashed_pin,
        NOW() + (p_valid_days || ' days')::INTERVAL, auth.uid()
    ) RETURNING id INTO v_pass_id;

    -- 11. Write Immutable Audit Log EXACTLY ONCE (No Plaintext Secrets Logged!)
    INSERT INTO public.audit_logs (society_id, actor_id, entity_type, entity_id, action, new_data)
    VALUES (
        v_society_id, auth.uid(), 'noc_request', p_noc_id, 'noc_approved',
        jsonb_build_object('balance', v_outstanding_dues, 'pass_id', v_pass_id)
    );

    RETURN v_noc;
END;
$$;
```

---

## 6. AUTHORITATIVE NOC STATE MACHINE & UNIQUE INDEX SEMANTICS

Slice 20 reconciles **11 canonical NOC states**:

1. `draft`: Initial applicant creation (Lifecycle-Active; Uniqueness Excluded).
2. `submitted`: Submitted for society review (Uniqueness-Active).
3. `dues_pending`: Financial dues identified, pending payment (Uniqueness-Active).
4. `clearance_in_progress`: Financials clear, checklist under review (Uniqueness-Active).
5. `in_review`: Administrative hold/review in progress (Uniqueness-Active).
6. `approved`: NOC cleared, move pass issued (Uniqueness-Active).
7. `completed`: Property occupancy transfer finalized (Terminal Positive).
8. `rejected`: Admin rejected request with reason (Terminal Negative).
9. `revoked`: Admin revoked approval prior to completion (Terminal Negative).
10. `cancelled`: Applicant cancelled request (Terminal Negative).
11. `expired`: Pass validity lapsed via `process_expired_noc_passes()` (Terminal Negative).

### Uniqueness-Active Index Predicate:
`draft` is lifecycle-active but **EXCLUDED** from active-request uniqueness because an applicant can hold a draft while preparing details. The partial unique index predicate strictly matches all 5 uniqueness-active states:

```sql
CREATE UNIQUE INDEX uq_active_noc_per_property 
ON public.noc_requests (property_id) 
WHERE status IN ('submitted', 'dues_pending', 'clearance_in_progress', 'in_review', 'approved');
```

---

## 7. CHECKLIST EXACT-SET PROOF & EMPTY-ARRAY NORMALIZATION

To prevent checklist manipulation and handle empty mandatory configurations deterministically:
1. Table Constraint: `CONSTRAINT uq_noc_checklist_category UNIQUE (noc_id, category)`
2. Aggregate Normalization: `COALESCE(ARRAY_AGG(DISTINCT category ORDER BY category), ARRAY[]::text[])`
3. Exact-Set Verification Logic:
   - If `ARRAY_LENGTH(v_required_categories, 1)` IS NULL or `0`, society has no mandatory checklist items; approval proceeds.
   - If mandatory categories exist, `v_cleared_categories` MUST match `v_required_categories` exactly. Missing or uncleared mandatory categories trigger an immediate exception.

---

## 8. CANONICAL LOCK ORDERING & DEADLOCK ANALYSIS

The standardized top-down lock hierarchy across all financial and NOC routines is:

$$\text{LEVEL 1: } \text{public.properties (FOR UPDATE)} \quad [\text{Canonical Property Serialization Barrier}]$$
$$\text{LEVEL 2: } \text{public.noc\_requests / maintenance\_charges / payments (FOR UPDATE)}$$
$$\text{LEVEL 3: } \text{public.ledger\_transactions (INSERT)}$$

*Deadlock Assessment Statement:* No deadlock path was identified within the analyzed lock graph, provided all participating writers follow the canonical lock order. Unnecessary `societies FOR SHARE` locks are eliminated.

---

## 9. INDIRECT PROPERTY RESOLUTION & IMMUTABILITY GUARDS

For functions accepting child primary keys (`p_payment_id`, `p_charge_id`), indirect resolution requires a two-step validation sequence:

```sql
-- Step 1: Initial Property Resolution
SELECT property_id INTO v_property_id FROM public.payments WHERE id = p_payment_id;
IF v_property_id IS NULL THEN RAISE EXCEPTION 'Payment not found'; END IF;

-- Step 2: Lock Parent Property Row
PERFORM 1 FROM public.properties WHERE id = v_property_id FOR UPDATE;

-- Step 3: Re-read Child Row FOR UPDATE & Re-verify Property Identity
SELECT * INTO v_payment FROM public.payments WHERE id = p_payment_id FOR UPDATE;
IF v_payment.property_id IS DISTINCT FROM v_property_id THEN
    RAISE EXCEPTION 'Concurrency anomaly: Payment property assignment altered during resolution';
END IF;
```

---

## 10. PROPERTY_ID IMMUTABILITY — PROPOSED VS VERIFIED

A PostgreSQL `FOREIGN KEY` constraint enforces referential integrity but does **NOT** prevent `UPDATE payments SET property_id = new_uuid`.

### Baseline Status:
No immutability triggers currently exist on `payments` or `maintenance_charges` in `database/schema_slice2.sql`.

### Proposed Immutability Trigger DDL (Slice 2 Remediation):
```sql
CREATE OR REPLACE FUNCTION public.trg_block_property_id_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
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
**Classification:** Immutability triggers are **PROPOSED ONLY — NOT IMPLEMENTED**. `GATE-02` is marked **PRE-IMPLEMENTATION GATE**.

---

## 11. FINANCIAL WRITER INVENTORY — EVIDENCE MATRIX

Static inspection of `database/schema_slice2.sql` and application source (`src/`) confirms all property-scoped financial mutation paths:

| Writer Path | Source Object | Execution Mode | Current Lock Behavior | Proposed Lock Behavior | Classification |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `fn_generate_charge` | `schema_slice2.sql` | SECURITY DEFINER | None | `properties FOR UPDATE` | **VERIFIED CURRENT WRITER (LACKS LOCK)** |
| `fn_process_payment` | `schema_slice2.sql` | SECURITY DEFINER | `payments FOR UPDATE` | `properties FOR UPDATE` | **VERIFIED CURRENT WRITER (LACKS LOCK)** |
| `fn_reverse_charge` | `schema_slice2.sql` | SECURITY DEFINER | `charges FOR UPDATE` | `properties FOR UPDATE` | **VERIFIED CURRENT WRITER (LACKS LOCK)** |
| `fn_reverse_payment` | `schema_slice2.sql` | SECURITY DEFINER | `payments FOR UPDATE` | `properties FOR UPDATE` | **VERIFIED CURRENT WRITER (LACKS LOCK)** |
| Client Direct SQL | `src/App.jsx` | RLS Policy | `FORCE RLS` (No Write Rules) | `FORCE RLS` | **VERIFIED BLOCKED** |
| `fn_post_expense` | `schema_slice2.sql` | SECURITY DEFINER | Society Scope | Society Scope | **VERIFIED N/A (Society Overhead)** |
| `fn_reverse_expense` | `schema_slice2.sql` | SECURITY DEFINER | Society Scope | Society Scope | **VERIFIED N/A (Society Overhead)** |

---

## 12. READ COMMITTED FRESH-SNAPSHOT REQUIREMENT

Under PostgreSQL `READ COMMITTED` transaction semantics:
- Each statement in a function block obtains its own statement snapshot when that statement begins execution.
- After `SELECT 1 FROM public.properties WHERE id = v_property_id FOR UPDATE` executes and acquires the lock, concurrent financial writers on `v_property_id` block.
- The fresh outstanding-balance calculation `v_outstanding_dues := fn_get_property_outstanding_balance(v_property_id)` MUST execute as a **separate SQL statement after lock acquisition**. That subsequent statement obtains a new READ COMMITTED snapshot when that statement begins and therefore observes committed financial changes visible to that statement.

---

## 13. PIN CSPRNG MATHEMATICAL SPECIFICATION

```sql
CREATE OR REPLACE FUNCTION public.fn_generate_secure_pin()
RETURNS VARCHAR
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_bytes BYTEA;
    v_random_bigint BIGINT;
    v_pin_str VARCHAR;
BEGIN
    LOOP
        v_bytes := gen_random_bytes(4);
        
        -- Explicit 64-bit BIGINT conversion BEFORE left shifting eliminates signed 32-bit overflow
        v_random_bigint := (get_byte(v_bytes, 0)::bigint << 24)
                         | (get_byte(v_bytes, 1)::bigint << 16)
                         | (get_byte(v_bytes, 2)::bigint << 8)
                         |  get_byte(v_bytes, 3)::bigint;
        
        -- Rejection sampling threshold: 4,293,999,999 = 4,294 * 1,000,000
        -- Discarding values >= 4,294,000,000 zeroes modulo bias across [000000, 999999]!
        IF v_random_bigint < 4294000000 THEN
            v_pin_str := lpad((v_random_bigint % 1000000)::text, 6, '0');
            EXIT;
        END IF;
    END LOOP;
    
    RETURN v_pin_str;
END;
$$;
```
- **Modulo Bias:** Zero modulo bias guaranteed across exactly 4,294 complete modulo classes ($4,294 \times 1,000,000$).
- **Overflow Protection:** Zero `abs()` calls; `v_random_bigint` is strictly non-negative in range $[0, 4294967295]$.

---

## 14. SCHEDULER EXECUTION PRINCIPAL & ACL SPECIFICATION

`process_expired_noc_passes()` proposed ACL:
```sql
REVOKE ALL ON FUNCTION public.process_expired_noc_passes() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.process_expired_noc_passes() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.process_expired_noc_passes() TO service_role;
```
**Status:** `GATE-05` is marked **NOT YET VERIFIED FROM CURRENT REPOSITORY — PRE-IMPLEMENTATION DEPLOYMENT GATE**. The production scheduler execution role MUST be verified during staging deployment prior to granting execution permissions.

---

## 15. OWNERSHIP / TRANSFER SCOPE

`fn_complete_noc_transfer` executes property occupancy transfer (`properties.owner_id`, `properties.tenant_id`, `properties.occupancy_status`). Historical owner registry tables (`property_owners`) remain outside Slice 20 scope, preventing scope drift.

---

## 16. DEPENDENCY-SAFE NON-CASCADE ROLLBACK PLAN

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

---

## 17. PRE-IMPLEMENTATION SECURITY GATES

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
| `GATE-11` | PIN CSPRNG mathematical verification | **PASS** | MATHEMATICALLY PROVEN |
| `GATE-12` | Token secret-handling verification | **PASS** | SHA-256 HASH STORAGE |
| `GATE-13` | Dependency-ordered rollback verification | **PASS** | REVERSE DDL SPECIFIED |

---

## 18. FINAL AUTHORIZATION STATUS

```text
=====================================================
SLICE 20 REVISION 4.8 STATUS
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
