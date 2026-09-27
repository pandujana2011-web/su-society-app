# SLICE 20 REVISION 4.4 — FINAL SECURITY PLAN

**Execution Date:** September 7, 2026  
**Target Repository:** `D:\Clients Applications\SU Society App`  
**Current Verified Locked Baseline:** `639 / 639 PASS (100%)`  
**Slices 1–19 Scope:** `LOCKED / IMMUTABLE`  
**Slice 2 Serialization Remediation:** `NOT IMPLEMENTED / NOT VERIFIED / ARCHITECTURAL DEPENDENCY`  
**Slice 20 Status:** `NOT IMPLEMENTED / NOT VERIFIED / NOT AUTHORIZED`  
**Execution Mode:** `PLAN CORRECTION ONLY / ZERO IMPLEMENTATION AUTHORIZATION`

---

## 1. REVISION STATUS & SUPERSEDING DECLARATION

This document constitutes **Slice 20 Revision 4.4**, the current, authoritative, fully reconciled implementation and security plan for Slice 20.

```text
REVISION 4.2 = SUPERSEDED
REVISION 4.3 = SUPERSEDED BY REVISION 4.4
REVISION 4.4 = CURRENT AUTHORITATIVE PLAN
```

All prior plan revisions are formally superseded. Revision 4.4 incorporates all adversarial findings, mathematical CSPRNG overflow fixes, global lock-order harmonization rules, exact indirect property resolution guards, rate-limiting zero-row race solutions, and dependency-safe non-CASCADE rollback sequences.

---

## 2. EXECUTIVE VERDICT SUMMARY

```text
=====================================================
FINAL VERDICT: NOT IMPLEMENTATION-READY
=====================================================
```
**Reason for Verdict:**  
Slice 20 NOC approval (`fn_approve_noc`) relies on parent property row locking (`SELECT 1 FROM public.properties WHERE id = p_property_id FOR UPDATE`). However, the existing Slice 2 financial mutation routines (`fn_generate_charge`, `fn_process_payment`, `fn_reverse_charge`, `fn_reverse_payment`) do not currently acquire this lock. Until the **Slice 2 Financial Serialization Remediation Plan** is explicitly authorized, implemented, and verified, Slice 20 implementation remains **STRICTLY BLOCKED**.

---

## 3. CURRENT LOCKED BASELINE & METRIC ACCOUNTING

The verified baseline for the project is immutable and strictly preserved:

```text
CURRENT VERIFIED BASELINE: 639 / 639 PASS (100%)
```

### Projected Metric Accounting (Post-Implementation Targets Only):
- **Current Verified Baseline:** `639 / 639 PASS` (Slices 1–19 Verified)
- **Slice 2 Serialization Remediation:** `+12 assertions` (`S2-FS-001` to `S2-FS-012`) $\rightarrow$ Projected Post-Slice 2 = `651`
- **Slice 20 Revision 4.4:** `+71 assertions` (`S20-001` to `S20-071`) $\rightarrow$ Projected Post-Slice 20 = `722`

```text
PROJECTED CUMULATIVE TARGET: 722 ASSERTIONS (UNVERIFIED / PROJECTED ONLY)
```
*Note: The number 722 represents a projected future target after both Slice 2 and Slice 20 are authorized and executed. It MUST NOT be reported as currently passing.*

---

## 4. INCORPORATED ADVERSARIAL FINDINGS

Revision 4.4 formally incorporates the four key findings from adversarial validation:

1. **Finding A (CRITICAL - PIN CSPRNG Math Fix):** Replaced unsafe signed 32-bit bit-shifting with explicit `BIGINT` casting before left shifting: `(get_byte(v_bytes, 0)::bigint << 24)`. Eliminates `abs(-2147483648)` integer overflow crashes and removes modulo bias via rejection sampling.
2. **Finding B (PLAN CORRECTION - Lock Order Harmonization):** Reconciled lock order discrepancies across Slice 2 and Slice 20. Enforces Level 1: `properties FOR UPDATE` FIRST across ALL property-scoped routines. Removed unnecessary `societies FOR SHARE` locks.
3. **Finding C (METRIC CORRECTION - Assertion Re-alignment):** Corrected metric accounting to 639 baseline + 12 Slice 2 + 71 Slice 20 = 722 projected target.
4. **Finding D (PASS WITH CONDITION - Indirect Property Re-verification):** Added double-check validation in payment/charge routines to re-verify `child.property_id == v_property_id` *after* acquiring `properties FOR UPDATE`.

---

## 5. PIN GENERATION — FINAL CORRECTED CSPRNG DESIGN

To prevent PostgreSQL signed 32-bit integer overflow and eliminate modulo bias across the 6-digit output space (`000000` to `999999`), PIN generation MUST execute the following mathematical rejection sampling algorithm:

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
        -- Fetch 4 cryptographically secure random bytes
        v_bytes := gen_random_bytes(4);
        
        -- Explicit 64-bit BIGINT conversion BEFORE left shifting prevents 32-bit signed overflow
        v_random_bigint := (get_byte(v_bytes, 0)::bigint << 24)
                         | (get_byte(v_bytes, 1)::bigint << 16)
                         | (get_byte(v_bytes, 2)::bigint << 8)
                         |  get_byte(v_bytes, 3)::bigint;
        
        -- Rejection sampling threshold: 4,293,999,999 = 4,294 * 1,000,000
        -- Unsigned 32-bit max is 4,294,967,295. Discarding values >= 4,294,000,000 zeroes modulo bias!
        IF v_random_bigint < 4294000000 THEN
            v_pin_str := lpad((v_random_bigint % 1000000)::text, 6, '0');
            EXIT;
        END IF;
    END LOOP;
    
    RETURN v_pin_str;
END;
$$;
```

### Security & Integrity Guarantees:
- **Modulo Bias:** Zero modulo bias guaranteed by rejection boundary `4294000000`.
- **Overflow Protection:** Zero `abs()` calls; `v_random_bigint` is strictly non-negative in range $[0, 4294967295]$.
- **Plaintext Security:** Plaintext PIN is returned to gatekeeper caller exactly once and hashed with `crypt(v_pin_str, gen_salt('bf', 10))` (bcrypt) before storage in `noc_move_passes`. Plaintext PIN is **NEVER** stored, logged, or recorded in audit JSON.

---

## 6. TOKEN ENTROPY SPECIFICATION

- **Generation:** Cryptographically secure pseudo-random number generator (`gen_random_bytes(6)`).
- **Encoding:** Hexadecimal string (12 characters).
- **Entropy Space:** $2^{48} = 281,474,976,710,656$ possible token values (48 bits of CSPRNG entropy).
- **Prefix Standard:** `NOC-PASS-` (e.g., `NOC-PASS-A1B2C3D4E5F6`). Static year prefixes are removed to eliminate year-hardcoding maintenance risks.
- **Storage:** Hashed with SHA-256 (`encode(digest(v_token, 'sha256'), 'hex')`) in `noc_move_passes.pass_code`. Plaintext token is returned to user exactly once.

---

## 7. GLOBAL CANONICAL LOCK ORDERING & HARMONIZATION

To eliminate deadlock risk across all concurrent database transactions, all functions in Slice 2 and Slice 20 MUST enforce the following global top-down lock hierarchy:

$$\text{LEVEL 1: } \text{public.properties (FOR UPDATE)} \quad [\text{Canonical Property Barrier}]$$
$$\text{LEVEL 2: } \text{public.noc\_requests / maintenance\_charges / payments (FOR UPDATE)}$$
$$\text{LEVEL 3: } \text{public.ledger\_transactions (INSERT)}$$

### Reconciled Lock Ordering Protocol:
1. **Property-Direct Functions (`fn_generate_charge`):**
   `properties FOR UPDATE` $\rightarrow$ `maintenance_charges (INSERT)` $\rightarrow$ `ledger_transactions (INSERT)`.
2. **Indirect Property Functions (`fn_process_payment`, `fn_reverse_payment`, `fn_reverse_charge`):**
   Resolve `property_id` $\rightarrow$ `properties FOR UPDATE` $\rightarrow$ Re-verify `child.property_id` $\rightarrow$ `child FOR UPDATE` $\rightarrow$ `ledger_transactions (INSERT)`.
3. **Slice 20 NOC Approval (`fn_approve_noc`):**
   Resolve NOC & Property $\rightarrow$ `properties FOR UPDATE` $\rightarrow$ Re-read NOC `FOR UPDATE` $\rightarrow$ Re-evaluate Dues $\rightarrow$ Update NOC status $\rightarrow$ Audit.

*Result:* Locks are acquired in identical top-down order across all slices. `NO DEADLOCK PATH IDENTIFIED`. Unnecessary `societies FOR SHARE` locks are eliminated.

---

## 8. INDIRECT PROPERTY RESOLUTION & INVARIANT VERIFICATION

For financial functions receiving child primary keys (`p_payment_id`, `p_charge_id`), indirect property resolution enforces double-check validation:

### `fn_process_payment` Execution Protocol:
```sql
-- Step 1: Initial Property Resolution
SELECT property_id INTO v_property_id FROM public.payments WHERE id = p_payment_id;
IF v_property_id IS NULL THEN RAISE EXCEPTION 'Payment not found'; END IF;

-- Step 2: Acquire Canonical Property Serialization Lock
PERFORM 1 FROM public.properties WHERE id = v_property_id FOR UPDATE;

-- Step 3: Re-read Child Row FOR UPDATE & Re-verify Property Identity
SELECT * INTO v_payment FROM public.payments WHERE id = p_payment_id FOR UPDATE;
IF v_payment.property_id IS DISTINCT FROM v_property_id THEN
  RAISE EXCEPTION 'Concurrency anomaly: Payment property assignment changed during resolution';
END IF;

-- Step 4: Validate Status & Execute Mutation
IF v_payment.status != 'pending_verification' THEN
  RAISE EXCEPTION 'Invalid payment status %', v_payment.status;
END IF;
```
Because `payments.property_id` is an immutable foreign key reference, re-verifying `v_payment.property_id = v_property_id` *after* acquiring `properties FOR UPDATE` guarantees zero stale resolution window.

---

## 9. `fn_approve_noc` AUTHORITATIVE APPROVAL BOUNDARY

`fn_approve_noc` enforces authoritative financial dues clearance at the serialization point:

```sql
BEGIN;
  -- 1. Admin Authorization Check
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Access Denied'; END IF;

  -- 2. Initial NOC Request Resolution
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

  IF v_noc.status NOT IN ('submitted', 'clearance_in_progress', 'dues_pending') THEN
    RAISE EXCEPTION 'Invalid state transition from status %', v_noc.status;
  END IF;

  -- 5. Fresh Authoritative Financial Balance Read (AFTER Property Lock)
  v_outstanding_dues := public.fn_get_property_outstanding_balance(v_property_id);
  IF v_outstanding_dues > 0 THEN
    RAISE EXCEPTION 'Cannot approve NOC: Outstanding dues equal %', v_outstanding_dues;
  END IF;

  -- 6. Validate Exact Checklist Requirements
  -- 7. Update NOC Status to 'approved'
  -- 8. Write Immutable Audit Log
COMMIT;
```

---

## 10. TRANSACTION ISOLATION & FRESH BALANCE READ SEMANTICS

Under PostgreSQL default `READ COMMITTED` isolation mode:
- Each SQL statement inside a transaction block obtains a fresh snapshot of committed database state up to the moment that statement begins execution.
- By executing `SELECT 1 FROM public.properties WHERE id = v_property_id FOR UPDATE`, `fn_approve_noc` forces all concurrent financial writers on property `v_property_id` to block.
- The subsequent statement `v_outstanding_dues := fn_get_property_outstanding_balance(v_property_id)` executes *after* the property lock is acquired, guaranteeing it observes all committed financial transactions and zero uncommitted concurrent writes.

---

## 11. RATE-LIMITING CONCURRENCY ARCHITECTURE

To track failed pass verification attempts safely without zero-existing-row race conditions:
- **Rolling Window:** 10 minutes (`NOW() - INTERVAL '10 minutes'`).
- **Threshold:** 10 failed attempts within window.
- **Lockout Duration:** 15 minutes (`NOW() + INTERVAL '15 minutes'`).
- **Stable Serialization Lock:** Before querying failure counts, `verify_pass` locks `public.users WHERE id = auth.uid() FOR UPDATE` (or acquires 64-bit advisory lock `pg_advisory_xact_lock`). Because `public.users` row always exists for an authenticated gatekeeper, zero-row locking races are impossible.

---

## 12. CHECKLIST EXACT-SET SECURITY

To prevent checklist category manipulation, `public.noc_checklist_items` enforces:
1. Table Constraint: `CONSTRAINT uq_noc_checklist_category UNIQUE (noc_id, category)`
2. Approval Verification:
   ```sql
   SELECT ARRAY_AGG(DISTINCT category ORDER BY category) INTO v_cleared_categories
   FROM public.noc_checklist_items
   WHERE noc_id = p_noc_id AND status = 'cleared';

   SELECT ARRAY_AGG(DISTINCT category ORDER BY category) INTO v_required_categories
   FROM public.noc_society_checklist_requirements
   WHERE society_id = v_society_id AND is_mandatory = TRUE;

   IF v_cleared_categories IS DISTINCT FROM v_required_categories THEN
     RAISE EXCEPTION 'Cannot approve NOC: Mandatory checklist items incomplete';
   END IF;
   ```

---

## 13. NOC STATE MACHINE RECONCILIATION

The canonical state machine reconciles all valid, active, and terminal NOC states:

```text
┌──────────────┐      ┌──────────────┐      ┌───────────────────────┐      ┌──────────────┐      ┌──────────────┐
│    DRAFT     │ ───► │  SUBMITTED   │ ───► │ CLEARANCE_IN_PROGRESS │ ───► │   APPROVED   │ ───► │  COMPLETED   │
└──────────────┘      └──────┬───────┘      └───────────┬───────────┘      └──────┬───────┘      └──────────────┘
                             │                          │                         │
                             ▼                          ▼                         ▼
                        ┌──────────┐               ┌──────────┐              ┌──────────┐
                        │ REJECTED │               │ REJECTED │              │ REVOKED  │
                        └──────────┘               └──────────┘              └──────────┘
                             │                          │                         │
                             ▼                          ▼                         ▼
                        ┌──────────┐               ┌──────────┐              ┌──────────┐
                        │CANCELLED │               │CANCELLED │              │ EXPIRED  │
                        └──────────┘               └──────────┘              └──────────┘
```

### Policy A Active Request Unique Index:
```sql
CREATE UNIQUE INDEX uq_active_noc_per_property 
ON public.noc_requests (property_id) 
WHERE status IN ('submitted', 'dues_pending', 'clearance_in_progress', 'approved');
```

---

## 14. IDEMPOTENCY SPECIFICATION

- **`fn_approve_noc` Sequential Re-invocation:** If called on a request already in `approved` status, the function checks current status, verifies balance, and returns the existing approved NOC record without creating duplicate audit logs or issuing duplicate move passes (`controlled no-op`).
- **Concurrent Approvals:** Second transaction blocks on `properties FOR UPDATE`, then reads `status = 'approved'` and completes as a controlled no-op.

---

## 15. PROPERTY OCCUPANCY SCOPE

`fn_complete_noc_transfer` strictly modifies property occupancy attributes:
- `properties.owner_id`
- `properties.tenant_id`
- `properties.occupancy_status`

*Scope Guard:* Historical owner registry tables and financial ledger histories remain untouched, preserving strict scope boundaries. Row update cardinality is verified with `GET DIAGNOSTICS v_rows_updated = ROW_COUNT; IF v_rows_updated != 1 THEN RAISE EXCEPTION ...`.

---

## 16. SCHEDULER SECURITY & EXPIRATION RPC ACL

`process_expired_noc_passes()` is executed exclusively by automated background scheduler workers:

```sql
REVOKE ALL ON FUNCTION public.process_expired_noc_passes() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.process_expired_noc_passes() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.process_expired_noc_passes() TO service_role;
```

---

## 17. DEPENDENCY-SAFE NON-CASCADE ROLLBACK PLAN

Rollback executes in strict reverse dependency order using exact PostgreSQL signatures without `CASCADE`:

```sql
-- 1. Revoke Function Execution Permissions
REVOKE EXECUTE ON FUNCTION public.process_expired_noc_passes() FROM service_role;
REVOKE EXECUTE ON FUNCTION public.fn_complete_noc_transfer(UUID) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_approve_noc(UUID, TEXT) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_reject_noc(UUID, TEXT) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_request_noc(UUID, VARCHAR) FROM authenticated;

-- 2. Drop Functions (Exact Signatures, No CASCADE)
DROP FUNCTION IF EXISTS public.process_expired_noc_passes();
DROP FUNCTION IF EXISTS public.fn_complete_noc_transfer(UUID);
DROP FUNCTION IF EXISTS public.fn_approve_noc(UUID, TEXT);
DROP FUNCTION IF EXISTS public.fn_reject_noc(UUID, TEXT);
DROP FUNCTION IF EXISTS public.fn_request_noc(UUID, VARCHAR);

-- 3. Drop Child Tables
DROP TABLE IF EXISTS public.noc_gatekeeper_rate_limits;
DROP TABLE IF EXISTS public.noc_move_passes;
DROP TABLE IF EXISTS public.noc_checklist_items;

-- 4. Drop Parent Table
DROP TABLE IF EXISTS public.noc_requests;
```

### Slice 2 Remediation Rollback Protocol:
To rollback Slice 2 serialization additions, restore the exact baseline function definitions of `fn_generate_charge`, `fn_process_payment`, `fn_reverse_charge`, and `fn_reverse_payment` from catalog-verified hash backups in `schema_slice2.sql`.

---

## 18. FILE & DATABASE OBJECT IMPACT MATRIX

| Object / File | Type | Future Action | Reason |
| :--- | :--- | :--- | :--- |
| `database/schema_slice2.sql` | File | Modify | Add `properties FOR UPDATE` locks |
| `database/schema_slice20.sql` | File | Create | DDL & RPC definitions for Slice 20 |
| `database/verify_slice20.sql` | File | Create | 71 test assertions for Slice 20 |
| `src/App.jsx` & `src/supabase.js` | File | Modify | UI components & Supabase API bindings |
| `public.noc_requests` | Table | Create (New) | NOC clearance request repository |
| `public.noc_move_passes` | Table | Create (New) | Digital move passes & hashed secrets |
| `public.noc_gatekeeper_rate_limits` | Table | Create (New) | Gatekeeper failure tracking |
| `public.fn_approve_noc` | RPC | Create (New) | Authoritative NOC approval with property lock |

---

## 19. SLICE 2 $\rightarrow$ SLICE 20 EXECUTION SEQUENCE

```text
CURRENT BASELINE: 639 / 639 PASS (LOCKED)
       ↓
Slice 2 Serialization Plan & Slice 20 Revision 4.4 Plan (COMPLETED)
       ↓
EXPLICIT USER AUTHORIZATION FOR SLICE 2 REMEDIATION
       ↓
Execute Slice 2 Serialization Remediation & Verify (651 PASS Target)
       ↓
EXPLICIT USER AUTHORIZATION FOR SLICE 20 IMPLEMENTATION
       ↓
Execute Slice 20 Implementation & Verify (722 PASS Target)
```

---

## 20. REMAINING ARCHITECTURAL BLOCKERS

**One Cross-Slice Blocker Remains:**  
Slice 20 implementation cannot proceed safely until the **Slice 2 Financial Serialization Remediation** is explicitly authorized, implemented, and verified in `database/schema_slice2.sql`.

---

## 21. FINAL REVISION 4.4 VERDICT

```text
=====================================================

SLICE 20 REVISION 4.4
FINAL PLAN CORRECTION

CURRENT VERIFIED BASELINE:
639 / 639 PASS (100%)

SLICE 2:
PLAN CORRECTED
NOT IMPLEMENTED
NOT VERIFIED
NOT AUTHORIZED

SLICE 20:
PLAN REVISION 4.4
NOT IMPLEMENTED
NOT VERIFIED
NOT AUTHORIZED

PROJECTED CUMULATIVE TARGET:
722
UNVERIFIED

DATABASE MODIFICATIONS:
NONE

APPLICATION MODIFICATIONS:
NONE

IMPLEMENTATION AUTHORIZATION:
NONE

STATUS:
PLAN-ONLY

=====================================================

NO IMPLEMENTATION PERFORMED.
NO DATABASE CHANGES PERFORMED.
NO APPLICATION CHANGES PERFORMED.
NO AUTHORIZATION GRANTED.
```
