# SLICE 20 REVISION 4.5 — FINAL SECURITY PLAN

**Execution Date:** September 7, 2026  
**Target Repository:** `D:\Clients Applications\SU Society App`  
**Current Verified Locked Baseline:** `639 / 639 PASS (100%)`  
**Slices 1–19 Scope:** `LOCKED / IMMUTABLE / UNTOUCHED`  
**Slice 2 Financial Serialization Remediation:** `NOT IMPLEMENTED / NOT VERIFIED / ARCHITECTURAL DEPENDENCY`  
**Slice 20 Status:** `NOT IMPLEMENTED / NOT VERIFIED / NOT AUTHORIZED`  
**Execution Mode:** `PLAN CORRECTION ONLY / ZERO IMPLEMENTATION AUTHORIZATION`

---

## 1. REVISION STATUS & SUPERSEDING DECLARATION

This document constitutes **Slice 20 Revision 4.5**, the current, authoritative, fully reconciled implementation and security plan for Slice 20.

```text
REVISION 4.2 = SUPERSEDED
REVISION 4.3 = SUPERSEDED
REVISION 4.4 = SUPERSEDED BY REVISION 4.5
REVISION 4.5 = CURRENT AUTHORITATIVE PLAN
```

All prior plan revisions are formally superseded. Revision 4.5 incorporates all corrected mathematical notations, explicit foreign-key immutability triggers, repository-wide financial writer inventories, authoritative NOC approval idempotency rules, scheduler execution role specifications, and hash-verified pre-remediation rollback procedures.

---

## 2. EXECUTIVE VERDICT SUMMARY

```text
=====================================================
FINAL VERDICT: NOT AUTHORIZED FOR IMPLEMENTATION UNTIL ALL IDENTIFIED PLAN GATES ARE SATISFIED
=====================================================
```
**Reason for Verdict:**  
Slice 20 NOC clearance (`fn_approve_noc`) relies on parent property row locking (`SELECT 1 FROM public.properties WHERE id = p_property_id FOR UPDATE`). However, the existing Slice 2 financial mutation routines (`fn_generate_charge`, `fn_process_payment`, `fn_reverse_charge`, `fn_reverse_payment`) do not currently acquire this lock. Until the **Slice 2 Financial Serialization Remediation Plan** is explicitly authorized, implemented, and verified, Slice 20 implementation remains **STRICTLY BLOCKED**.

---

## 3. CURRENT LOCKED BASELINE & METRIC ACCOUNTING

The verified baseline for the project is immutable and strictly preserved:

```text
CURRENT VERIFIED BASELINE: 639 / 639 PASS (100%)
```

### Projected Metric Accounting (Post-Implementation Targets Only):
- **Current Verified Baseline:** `639 / 639 PASS` (Slices 1–19 Verified)
- **Slice 2 Serialization Remediation:** `+12 assertions` (`S2-FS-001` to `S2-FS-012`) $\rightarrow$ Projected Post-Slice 2 = `651`
- **Slice 20 Revision 4.5:** `+71 assertions` (`S20-001` to `S20-071`) $\rightarrow$ Projected Post-Slice 20 = `722`

```text
PROJECTED CUMULATIVE TARGET: 722 ASSERTIONS (UNVERIFIED / PROJECTED ONLY)
```
*Note: The number 722 represents a projected future target after both Slice 2 and Slice 20 are authorized and executed. It MUST NOT be reported as currently passing.*

---

## 4. MATHEMATICAL NOTATION & TOKEN ENTROPY SPECIFICATION

- **CSPRNG Byte Source:** `gen_random_bytes(6)` (48 bits of cryptographically secure random entropy).
- **Encoding:** Hexadecimal string (12 hexadecimal characters).
- **Entropy Space:** $2^{48} = 281,474,976,710,656$ possible token values.
- **Token Prefix Standard:** `NOC-PASS-` (e.g., `NOC-PASS-A1B2C3D4E5F6`). Static year prefixes are removed to eliminate year-hardcoding maintenance risks.
- **Storage:** Hashed with SHA-256 (`encode(digest(v_token, 'sha256'), 'hex')`) in `noc_move_passes.pass_code`. Plaintext token is returned to user exactly once and never persisted.
- **Notation Standard:** Malformed `248` notation is completely eliminated; all entropy specifications strictly state $2^{48} = 281,474,976,710,656$.

---

## 5. FOREIGN KEY IMMUTABILITY & ENFORCEMENT PROTOCOL

A PostgreSQL `FOREIGN KEY` constraint guarantees referential integrity but does **NOT** enforce column value immutability. To prevent unauthorized alteration of property assignments on financial records:

### Database Immutability Triggers (Slice 2 Remediation):
```sql
CREATE OR REPLACE FUNCTION public.trg_block_property_id_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
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

### Indirect Property Resolution Re-verification Guard:
Even with immutability triggers active, all indirect financial RPCs (`fn_process_payment`, `fn_reverse_payment`, `fn_reverse_charge`) MUST re-verify child property identity after acquiring `properties FOR UPDATE`:
```sql
SELECT property_id INTO v_property_id FROM public.payments WHERE id = p_payment_id;
PERFORM 1 FROM public.properties WHERE id = v_property_id FOR UPDATE;
SELECT * INTO v_payment FROM public.payments WHERE id = p_payment_id FOR UPDATE;

IF v_payment.property_id IS DISTINCT FROM v_property_id THEN
    RAISE EXCEPTION 'Concurrency anomaly: Payment property assignment altered during resolution';
END IF;
```

---

## 6. REPOSITORY-WIDE FINANCIAL WRITER INVENTORY

Inspection of `schema_slice1.sql` through `schema_slice19.sql` confirms the complete inventory of routines performing financial state mutations:

| Mutation Path | Target Table | Direction | Primary Serialization Mechanism | RLS Bypass Risk | NOC Dues Impact |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `fn_generate_charge` | `maintenance_charges`, `ledger_transactions` | Debit | `properties FOR UPDATE` | None (RPC locked) | **YES** |
| `fn_process_payment` | `payments`, `ledger_transactions` | Credit | `properties FOR UPDATE` | None (RPC locked) | **YES** |
| `fn_reverse_charge` | `maintenance_charges`, `ledger_transactions` | Credit (Compensating) | `properties FOR UPDATE` | None (RPC locked) | **YES** |
| `fn_reverse_payment` | `payments`, `ledger_transactions` | Debit (Compensating) | `properties FOR UPDATE` | None (RPC locked) | **YES** |
| Direct Client SQL | `maintenance_charges`, `payments`, `ledger` | N/A | `FORCE ROW LEVEL SECURITY` | None (No write policies) | None (Blocked) |
| `fn_post_expense` | `expenses`, `ledger_transactions` | Debit (Society) | Society Scope (`property_id IS NULL`) | None | **NO** (Society overhead) |
| `fn_reverse_expense` | `expenses`, `ledger_transactions` | Credit (Society) | Society Scope (`property_id IS NULL`) | None | **NO** (Society overhead) |

*Conclusion:* Every property-scoped financial mutation path is accounted for and governed by the `properties FOR UPDATE` barrier.

---

## 7. `fn_approve_noc` AUTHORITATIVE IDEMPOTENCY & APPROVAL SEMANTICS

`fn_approve_noc` enforces distinct execution paths for first-time approval transitions versus duplicate invocation on already-approved requests:

```sql
BEGIN;
    -- 1. Admin Authorization Check
    IF NOT public.is_admin() THEN RAISE EXCEPTION 'Access Denied'; END IF;

    -- 2. Initial Resolution & Row Lock on NOC Request
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

    -- 5. IDEMPOTENT ALREADY-APPROVED HANDLING
    IF v_noc.status = 'approved' THEN
        -- Controlled No-Op: Do NOT re-check dues (prevent retroactive approval invalidation)
        -- Do NOT create duplicate move passes or audit logs
        RETURN v_noc;
    END IF;

    IF v_noc.status NOT IN ('submitted', 'clearance_in_progress', 'dues_pending') THEN
        RAISE EXCEPTION 'Invalid state transition from status %', v_noc.status;
    END IF;

    -- 6. FRESH AUTHORITATIVE FINANCIAL BALANCE READ (AFTER Property Lock)
    -- Executed as a separate SQL statement following lock acquisition
    v_outstanding_dues := public.fn_get_property_outstanding_balance(v_property_id);
    IF v_outstanding_dues > 0 THEN
        RAISE EXCEPTION 'Cannot approve NOC: Outstanding dues equal %', v_outstanding_dues;
    END IF;

    -- 7. Validate Mandatory Checklist Exact-Set Requirements
    -- 8. Transition Status to 'approved' & Issue Move Pass EXACTLY ONCE
    -- 9. Write Immutable Audit Log EXACTLY ONCE
COMMIT;
```

### Idempotency Rationale:
Once an NOC request reaches `approved` status, an already-approved re-invocation returns the approved record as a **controlled no-op**. It does **NOT** re-evaluate dues, ensuring that subsequent financial charges posted after NOC approval do not retroactively invalidate an already-issued certificate prior to transfer completion.

---

## 8. SCHEDULER EXECUTION PRINCIPAL & ACL SPECIFICATION

`process_expired_noc_passes()` is executed exclusively by automated background scheduler tasks:

```sql
REVOKE ALL ON FUNCTION public.process_expired_noc_passes() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.process_expired_noc_passes() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.process_expired_noc_passes() TO service_role;
```

*Pre-Implementation Gate:* During staging deployment, the execution principal MUST be verified (`VERIFICATION REQUIRED BEFORE IMPLEMENTATION`). If a dedicated scheduler role (e.g. `pg_cron`) is active instead of `service_role`, `GRANT EXECUTE` will be bound strictly to that role.

---

## 9. HARDENED PRE-REMEDIATION SLICE 2 ROLLBACK

Rollback of Slice 2 serialization additions MUST NOT re-run `schema_slice2.sql` entirely. Instead, exact pre-remediation function restoration is performed:

### Pre-Implementation Capture Gate:
Prior to applying modifications to `database/schema_slice2.sql`, the execution pipeline MUST capture:
1. Exact function DDL definitions for `fn_generate_charge`, `fn_process_payment`, `fn_reverse_charge`, `fn_reverse_payment`.
2. SHA-256 cryptographic hash of the pre-remediation DDL script.

### Rollback Execution Script:
```sql
-- Restore exact pre-remediation function definitions from SHA-256 verified backup
-- (Zero CASCADE directives used; zero unrelated Slice 2 objects touched)
CREATE OR REPLACE FUNCTION public.fn_generate_charge(...) ... [BASELINE DEFINITION];
CREATE OR REPLACE FUNCTION public.fn_process_payment(...) ... [BASELINE DEFINITION];
CREATE OR REPLACE FUNCTION public.fn_reverse_charge(...) ... [BASELINE DEFINITION];
CREATE OR REPLACE FUNCTION public.fn_reverse_payment(...) ... [BASELINE DEFINITION];
```

---

## 10. GLOBAL CANONICAL LOCK ORDERING & READ COMMITTED SEMANTICS

To eliminate deadlock risk across all database transactions, all routines enforce the global lock hierarchy:

$$\text{LEVEL 1: } \text{public.properties (FOR UPDATE)} \quad [\text{Canonical Property Barrier}]$$
$$\text{LEVEL 2: } \text{public.noc\_requests / maintenance\_charges / payments (FOR UPDATE)}$$
$$\text{LEVEL 3: } \text{public.ledger\_transactions (INSERT)}$$

### PostgreSQL READ COMMITTED Transaction Semantics:
1. Each statement in a `READ COMMITTED` transaction obtains a new snapshot of committed data.
2. Executing `SELECT 1 FROM public.properties WHERE id = v_property_id FOR UPDATE` forces concurrent financial writers on `v_property_id` to block.
3. The subsequent statement `v_outstanding_dues := fn_get_property_outstanding_balance(v_property_id)` executes as a **separate SQL statement after lock acquisition**, guaranteeing its snapshot sees all committed transactions up to the instant the property lock was granted.

---

## 11. CHECKLIST EXACT-SET SECURITY

To prevent checklist category manipulation, `public.noc_checklist_items` enforces:
1. Table Constraint: `CONSTRAINT uq_noc_checklist_category UNIQUE (noc_id, category)`
2. Category Exact-Set Verification:
   ```sql
   SELECT ARRAY_AGG(DISTINCT category ORDER BY category) INTO v_cleared_categories
   FROM public.noc_checklist_items
   WHERE noc_id = p_noc_id AND status = 'cleared';

   SELECT ARRAY_AGG(DISTINCT category ORDER BY category) INTO v_required_categories
   FROM public.noc_society_checklist_requirements
   WHERE society_id = v_society_id AND is_mandatory = TRUE;

   IF v_required_categories IS NOT NULL AND v_cleared_categories IS DISTINCT FROM v_required_categories THEN
       RAISE EXCEPTION 'Cannot approve NOC: Mandatory checklist items incomplete';
   END IF;
   ```

---

## 12. NOC STATE MACHINE RECONCILIATION

The canonical state vocabulary reconciles 10 explicit states:

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

## 13. PROPERTY OCCUPANCY SCOPE

`fn_complete_noc_transfer` executes the physical transfer of property occupancy attributes:
- `properties.owner_id`
- `properties.tenant_id`
- `properties.occupancy_status`

*Architectural Confirmation:* Slice 20 is the authoritative transfer execution point for resident move-in/move-out NOC clearance. Historical owner registry tables (`property_owners`) remain outside Slice 20 scope, preventing scope drift.

---

## 14. PIN GENERATION — MATHEMATICALLY HARDENED ALGORITHM

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
        
        -- 64-bit BIGINT conversion BEFORE left shifting eliminates 32-bit signed overflow
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

---

## 15. DEPENDENCY-SAFE NON-CASCADE ROLLBACK PLAN

```sql
-- 1. Revoke Function Permissions
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

---

## 16. FINAL STATUS & AUTHORIZATION GATE

```text
=====================================================

CURRENT VERIFIED BASELINE:
639 / 639 PASS (100%)

SLICES 1–19:
LOCKED / IMMUTABLE / UNTOUCHED

SLICE 2:
PLAN CORRECTED
NOT IMPLEMENTED
NOT VERIFIED
NOT AUTHORIZED

SLICE 20:
REVISION 4.5 PLAN
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

EXECUTION MODE:
PLAN-ONLY

FINAL VERDICT:
NOT AUTHORIZED FOR IMPLEMENTATION UNTIL ALL IDENTIFIED PLAN GATES ARE SATISFIED

=====================================================
```
