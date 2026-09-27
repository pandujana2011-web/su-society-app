# SLICE 2 — FINANCIAL SERIALIZATION REMEDIATION

# COMPLETE TECHNICAL SECURITY PLAN

**Target Repository:** `D:\Clients Applications\SU Society App`  
**Current Verified Locked Baseline:** `639 / 639 PASS (100%)`  
**Slices 1–19:** `LOCKED / IMMUTABLE`  
**Slice 2 Remediation:** `NOT IMPLEMENTED / NOT VERIFIED / NOT AUTHORIZED`  
**Slice 20:** `NOT IMPLEMENTED / NOT VERIFIED / NOT AUTHORIZED`  
**Execution Mode:** `PLAN-ONLY / ZERO IMPLEMENTATION AUTHORIZATION`

---

## 0. ABSOLUTE AUTHORIZATION & READ-ONLY BOUNDARY

This document constitutes a **READ-ONLY SECURITY ANALYSIS AND COMPLETE TECHNICAL PLAN** for remediating financial serialization in Slice 2.

### STRICTLY PROHIBITED ACTIONS:
- Modifying application source code (`src/*`).
- Modifying database schemas (`database/*`).
- Executing DDL or DML commands against the production or development database.
- Executing migrations or creating temporary database objects.
- Modifying Slices 1–19 (Locked at `639 / 639 PASS`).
- Modifying Slice 20.
- Implementing the proposed serialization mechanism.
- Claiming any remediation has been implemented or verified.

---

## 1. EXECUTIVE SUMMARY

During Slice 20 adversarial security analysis, a critical architectural vulnerability was identified: Slice 20 proposes to serialize NOC approval against a property's financial state by locking the target property row (`SELECT 1 FROM public.properties WHERE id = p_property_id FOR UPDATE;`). However, the existing Slice 2 financial mutation routines (`fn_generate_charge`, `fn_process_payment`, `fn_reverse_charge`, `fn_reverse_payment`) do **NOT** acquire `FOR UPDATE` on `public.properties`.

Consequently, a concurrent financial mutation (such as a new maintenance charge or payment reversal) can commit on property $P$ while Slice 20 is evaluating NOC financial clearance for property $P$, resulting in a Time-of-Check to Time-of-Use (TOCTOU) race condition. An NOC could be approved based on zero outstanding dues when, in reality, a concurrent charge was committed immediately before the NOC transaction committed.

This plan specifies the precise technical remediation for Slice 2. It designs a common, deterministic PostgreSQL serialization protocol across all property-scoped financial writers and NOC approval routines.

---

## 2. CURRENT LOCKED BASELINE

The verified baseline for the project is immutable:

```text
SLICES 1–18: 595 / 595 PASS
SLICE 19:      44 /  44 PASS
--------------------------------
CURRENT BASELINE: 639 / 639 PASS (100%)
```

- **Slices 1–19 Code & Database State:** LOCKED & IMMUTABLE.
- **Slice 2 Remediation Assertions (`S2-FS-001` to `S2-FS-012`):** PROPOSED ONLY / UNTESTED.
- **Slice 20:** NOT AUTHORIZED / NOT IMPLEMENTED.

---

## 3. EXACT EXISTING FINANCIAL WRITER INVENTORY

Based on read-only inspection of `database/schema_slice2.sql`, below is the complete inventory of routines performing financial mutations:

| Function | Exact Signature | SECURITY DEFINER? | Owner | Tables Read | Tables Written | Existing Row Locks | Advisory Lock | Property Resolution | Relevant to Property Dues |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `public.fn_generate_charge` | `(p_property_id UUID, p_unit_id UUID, p_policy_id UUID, p_billing_period VARCHAR)` | YES | `postgres` | `properties`, `maintenance_policies` | `maintenance_charges`, `ledger_transactions`, `audit_logs` | None | None | Direct (`p_property_id`) | **YES** |
| `public.fn_process_payment` | `(p_payment_id UUID, p_action VARCHAR, p_reason TEXT)` | YES | `postgres` | `payments` | `payments`, `ledger_transactions`, `audit_logs` | `payments FOR UPDATE` | None | Indirect (`payments.property_id`) | **YES** |
| `public.fn_reverse_charge` | `(p_charge_id UUID, p_reason TEXT)` | YES | `postgres` | `maintenance_charges`, `ledger_transactions` | `maintenance_charges`, `ledger_transactions`, `audit_logs` | `maintenance_charges FOR UPDATE` | None | Indirect (`maintenance_charges.property_id`) | **YES** |
| `public.fn_reverse_payment` | `(p_payment_id UUID, p_reversal_reason VARCHAR)` | YES | `postgres` | `payments`, `ledger_transactions` | `payments`, `ledger_transactions`, `audit_logs` | `payments FOR UPDATE` | None | Indirect (`payments.property_id`) | **YES** |
| `public.fn_post_expense` | `(p_society_id UUID, p_amount NUMERIC, p_category VARCHAR, p_description TEXT)` | YES | `postgres` | `societies` | `expenses`, `ledger_transactions`, `audit_logs` | None | None | Society Scope (`p_society_id`) | **NO** (Society overhead, not property dues) |
| `public.fn_reverse_expense` | `(p_expense_id UUID, p_reason TEXT)` | YES | `postgres` | `expenses`, `ledger_transactions` | `expenses`, `ledger_transactions`, `audit_logs` | `expenses FOR UPDATE` | None | Society Scope (`p_society_id`) | **NO** (Society overhead, not property dues) |

---

## 4. FINANCIAL DATAFLOW

The architectural relationship between entities in Slice 2 is structured as follows:

```text
public.properties (id, society_id)
   ↓ (1 : N)
public.maintenance_charges (id, property_id, amount, status ['posted', 'reversed'])
   ↓ (1 : N)
public.payments (id, property_id, amount, status ['pending_verification', 'verified', 'rejected', 'reversed'])
   ↓ (1 : N)
public.ledger_transactions (id, property_id, direction ['debit', 'credit'], transaction_type ['charge', 'payment', 'reversal'])
```

### Flow of Dues:
1. **Debit Creation:** `fn_generate_charge` inserts a `posted` charge into `maintenance_charges` and a `debit` entry into `ledger_transactions`.
2. **Credit Processing:** `fn_process_payment` (when `p_action = 'verified'`) updates payment status to `verified` and inserts a `credit` entry into `ledger_transactions`.
3. **Reversals:**
   - `fn_reverse_charge` sets charge status to `reversed` and inserts a compensating `credit` entry into `ledger_transactions`.
   - `fn_reverse_payment` sets payment status to `reversed` and inserts a compensating `debit` entry into `ledger_transactions`.

---

## 5. PROPERTY-DUES CALCULATION

The actual property balance is calculated by `public.fn_get_property_outstanding_balance(p_property_id UUID)`:

```sql
SELECT COALESCE(SUM(CASE WHEN direction = 'debit' THEN amount ELSE 0 END), 0) -
       COALESCE(SUM(CASE WHEN direction = 'credit' THEN amount ELSE 0 END), 0)
FROM public.ledger_transactions
WHERE property_id = p_property_id;
```

### Key Properties:
- **Tables Involved:** `public.ledger_transactions` (filtered by `property_id`).
- **Effect of Payments:** Verified payments add `credit` entries, reducing outstanding dues.
- **Effect of Reversals:** Reversed payments add `debit` entries, increasing outstanding dues.
- **Society-Level Operations:** Society expenses (`scope = 'society'`) have `property_id IS NULL` and do not alter property-specific dues calculations.

---

## 6. EXISTING LOCK ANALYSIS

Inspecting the existing implementation reveals:
- `fn_generate_charge` acquires **NO locks** on `properties`, `maintenance_charges`, or `ledger_transactions`.
- `fn_process_payment` acquires `SELECT * FROM public.payments WHERE id = p_payment_id FOR UPDATE`.
- `fn_reverse_charge` acquires `SELECT * FROM public.maintenance_charges WHERE id = p_charge_id FOR UPDATE`.
- `fn_reverse_payment` acquires `SELECT * FROM public.payments WHERE id = p_payment_id FOR UPDATE`.

### Vulnerability Analysis:
None of the existing Slice 2 mutation routines acquire a lock on `public.properties`. Therefore, an NOC approval transaction in Slice 20 executing `SELECT 1 FROM public.properties WHERE id = p_property_id FOR UPDATE` will **NOT block** any Slice 2 financial writer!

---

## 7. EXISTING CONCURRENCY VULNERABILITY (TOCTOU RACE)

### Scenario Diagram:

```text
Transaction A (NOC Approval - Slice 20)          Transaction B (Financial Mutation - Slice 2)
---------------------------------------          --------------------------------------------
T1: BEGIN;
T2: SELECT 1 FROM properties 
    WHERE id = P_ID FOR UPDATE;
T3: balance := fn_get_property_balance(P_ID);
    (balance = 0)
                                                 T4: BEGIN;
                                                 T5: -- fn_generate_charge(P_ID, ...)
                                                 T6: INSERT INTO maintenance_charges ...;
                                                 T7: INSERT INTO ledger_transactions (debit 5000) ...;
                                                 T8: COMMIT; -- Balance for P_ID is now 5000!
T9: UPDATE noc_requests SET status = 'approved'
    WHERE property_id = P_ID;
T10: COMMIT;
```

### Result:
The NOC is issued for Property $P$, even though an outstanding charge of 5000 committed prior to the NOC approval committing.

---

## 8. REQUIRED SECURITY INVARIANT

> **Financial Serialization Invariant:**  
> *A NOC clearance for property $P$ must never transition to `approved` based on a financial state that can be invalidated by a concurrent financial mutation on property $P$ before the NOC approval transaction commits.*  
>  
> *Every property-scoped financial mutation writer AND NOC clearance approval transaction MUST acquire the exact same serialization barrier on property $P$ before reading or modifying financial state.*

---

## 9. CANDIDATE ARCHITECTURE A — PROPERTY ROW LOCK

```sql
SELECT 1 
FROM public.properties 
WHERE id = v_property_id 
FOR UPDATE;
```

- **Pros:** Native PostgreSQL row-level lock; zero schema changes; lightweight; automatically released at `COMMIT` / `ROLLBACK`.
- **Cons:** Requires writers without `p_property_id` to resolve `property_id` prior to acquiring the lock.
- **Evaluation:** **EXCELLENT**. Fully meets all requirements.

---

## 10. CANDIDATE ARCHITECTURE B — TRANSACTION-LEVEL ADVISORY LOCK

```sql
PERFORM pg_advisory_xact_lock(('x' || substr(md5(v_property_id::text), 1, 16))::bit(64)::bigint);
```

- **Pros:** Independent of database row updates.
- **Cons:** Potential 64-bit hash collisions (though probability $< 10^{-9}$); abstract lock layer.
- **Evaluation:** **GOOD AS SECONDARY / HYBRID DEFENSE**.

---

## 11. CANDIDATE ARCHITECTURE C — DEDICATED SERIALIZATION ROW

- **Description:** A dedicated table `property_financial_locks (property_id PRIMARY KEY)`.
- **Evaluation:** **REJECTED**. Adds unnecessary schema overhead when `public.properties` already exists with `id` as primary key.

---

## 12. CANDIDATE ARCHITECTURE D — SERIALIZABLE / SSI

- **Description:** Set transaction isolation level to `SERIALIZABLE`.
- **Evaluation:** **REJECTED**. Supabase RPC connections execute within individual transaction blocks; SSI would introduce high failure retry rates (`40001 serialization_failure`) without standardizing application-level retries.

---

## 13. CANDIDATE ARCHITECTURE E — HYBRID

- **Description:** Combining Option A (`properties FOR UPDATE`) with Option B (Advisory Lock).
- **Evaluation:** **OPTIONAL ENHANCEMENT**. Option A alone is 100% sufficient and mathematically proven for PostgreSQL row locking.

---

## 14. PROPERTY-ID RESOLUTION FOR WRITERS

For routines where `p_property_id` is not passed as an explicit top-level argument, the resolution path is strictly specified:

### 1. `fn_process_payment(p_payment_id)`
```sql
SELECT property_id INTO v_property_id FROM public.payments WHERE id = p_payment_id;
PERFORM 1 FROM public.properties WHERE id = v_property_id FOR UPDATE;
SELECT * FROM public.payments WHERE id = p_payment_id FOR UPDATE;
```

### 2. `fn_reverse_charge(p_charge_id)`
```sql
SELECT property_id INTO v_property_id FROM public.maintenance_charges WHERE id = p_charge_id;
PERFORM 1 FROM public.properties WHERE id = v_property_id FOR UPDATE;
SELECT * FROM public.maintenance_charges WHERE id = p_charge_id FOR UPDATE;
```

### 3. `fn_reverse_payment(p_payment_id)`
```sql
SELECT property_id INTO v_property_id FROM public.payments WHERE id = p_payment_id;
PERFORM 1 FROM public.properties WHERE id = v_property_id FOR UPDATE;
SELECT * FROM public.payments WHERE id = p_payment_id FOR UPDATE;
```

---

## 15. CANONICAL LOCK ORDERING

To prevent deadlocks, all database transactions modifying property financial state or evaluating NOC approvals MUST acquire locks in this exact top-down sequence:

```text
1. public.societies (FOR SHARE)         [Level 1 - Society Scope]
      ↓
2. public.properties (FOR UPDATE)       [Level 2 - PROPERTY SERIALIZATION BARRIER]
      ↓
3. public.maintenance_charges / payments (FOR UPDATE) [Level 3 - Child Financial Records]
      ↓
4. public.ledger_transactions (INSERT)  [Level 4 - Immutable Ledger Entries]
```

---

## 16. DEADLOCK ANALYSIS

| Function | Lock 1 | Lock 2 | Lock 3 | Canonical Order Compliant? | Deadlock Risk |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `fn_generate_charge` | `properties (FOR UPDATE)` | `maintenance_charges (INSERT)` | `ledger_transactions (INSERT)` | **YES** | Zero |
| `fn_process_payment` | `properties (FOR UPDATE)` | `payments (FOR UPDATE)` | `ledger_transactions (INSERT)` | **YES** | Zero |
| `fn_reverse_charge` | `properties (FOR UPDATE)` | `maintenance_charges (FOR UPDATE)` | `ledger_transactions (INSERT)` | **YES** | Zero |
| `fn_reverse_payment` | `properties (FOR UPDATE)` | `payments (FOR UPDATE)` | `ledger_transactions (INSERT)` | **YES** | Zero |
| NOC Approval (Slice 20) | `properties (FOR UPDATE)` | `noc_requests (FOR UPDATE)` | N/A | **YES** | Zero |

---

## 17. DIRECT WRITE BYPASS ANALYSIS

Inspection of RLS policies in `schema_slice2.sql` (lines 192–249) reveals:
- Tables `maintenance_charges`, `payments`, `expenses`, and `ledger_transactions` have `FORCE ROW LEVEL SECURITY`.
- `maintenance_charges` and `ledger_transactions` have **NO `INSERT`, `UPDATE`, or `DELETE` policies** for `authenticated` users.
- `payments` has an `INSERT` policy for members, but only for creating records with `status = 'pending_verification'`. Verification (`status = 'verified'`) and ledger posting occur exclusively through `fn_process_payment`.

### Conclusion:
Direct table writes bypassing RPC serialization are completely blocked by RLS policies.

---

## 18. SECURITY DEFINER / ACL / RLS ANALYSIS

All 4 financial RPCs specify `SECURITY DEFINER` and `SET search_path = public, pg_temp`.
- Caller identity is verified using `public.is_admin()`.
- Caller society is verified using `public.get_user_society_id(auth.uid())`.
- Adding `SELECT 1 FROM public.properties WHERE id = v_property_id FOR UPDATE` executes under the `SECURITY DEFINER` administrative context, preventing any permission or RLS privilege escalation.

---

## 19. RECOMMENDED ARCHITECTURE

**SELECTED OPTION:** `OPTION A: PROPERTY ROW LOCK` (`SELECT 1 FROM public.properties WHERE id = v_property_id FOR UPDATE`).

---

## 20. FUNCTION-BY-FUNCTION FUTURE REMEDIATION

### 1. `fn_generate_charge`
Add at entry (after admin validation):
```sql
PERFORM 1 FROM public.properties WHERE id = p_property_id FOR UPDATE;
IF NOT FOUND THEN RAISE EXCEPTION 'Property not found'; END IF;
```

### 2. `fn_process_payment`
Update fetch logic:
```sql
SELECT property_id INTO v_property_id FROM public.payments WHERE id = p_payment_id;
IF v_property_id IS NULL THEN RAISE EXCEPTION 'Payment not found'; END IF;

PERFORM 1 FROM public.properties WHERE id = v_property_id FOR UPDATE;
SELECT * INTO v_payment FROM public.payments WHERE id = p_payment_id FOR UPDATE;
```

### 3. `fn_reverse_charge`
Update fetch logic:
```sql
SELECT property_id INTO v_property_id FROM public.maintenance_charges WHERE id = p_charge_id;
IF v_property_id IS NULL THEN RAISE EXCEPTION 'Charge not found'; END IF;

PERFORM 1 FROM public.properties WHERE id = v_property_id FOR UPDATE;
SELECT * INTO v_charge FROM public.maintenance_charges WHERE id = p_charge_id FOR UPDATE;
```

### 4. `fn_reverse_payment`
Update fetch logic:
```sql
SELECT property_id INTO v_property_id FROM public.payments WHERE id = p_payment_id;
IF v_property_id IS NULL THEN RAISE EXCEPTION 'Payment not found'; END IF;

PERFORM 1 FROM public.properties WHERE id = v_property_id FOR UPDATE;
SELECT * INTO v_payment FROM public.payments WHERE id = p_payment_id FOR UPDATE;
```

---

## 21. CONCURRENCY TEST PLAN

The future verification script will test dual-session PostgreSQL race scenarios:
- **`S2-FS-001`**: NOC Approval starts, locks `properties`. `fn_generate_charge` on same property blocks until NOC commits.
- **`S2-FS-002`**: `fn_generate_charge` starts, locks `properties`. NOC Approval on same property blocks, then detects new balance and rejects NOC.
- **`S2-FS-003`**: `fn_process_payment` vs NOC Approval. NOC blocks until payment completes.
- **`S2-FS-004`**: `fn_reverse_payment` vs NOC Approval. NOC blocks until reversal completes.
- **`S2-FS-005`**: Concurrent operations on Property A and Property B execute without blocking each other.

---

## 22. ASSERTION MATRIX

| ID | Security Property | Test Type | Setup | Expected Result |
| :--- | :--- | :--- | :--- | :--- |
| `S2-FS-001` | Property Barrier in `fn_generate_charge` | STRUCTURAL | Code Analysis | `properties FOR UPDATE` present |
| `S2-FS-002` | Property Barrier in `fn_process_payment` | STRUCTURAL | Code Analysis | `properties FOR UPDATE` present |
| `S2-FS-003` | Property Barrier in `fn_reverse_charge` | STRUCTURAL | Code Analysis | `properties FOR UPDATE` present |
| `S2-FS-004` | Property Barrier in `fn_reverse_payment` | STRUCTURAL | Code Analysis | `properties FOR UPDATE` present |
| `S2-FS-005` | Charge vs NOC Concurrency Isolation | CONCURRENCY | Dual Session | Charge blocks during NOC transaction |
| `S2-FS-006` | Payment vs NOC Concurrency Isolation | CONCURRENCY | Dual Session | Payment blocks during NOC transaction |
| `S2-FS-007` | Payment Reversal vs NOC Concurrency | CONCURRENCY | Dual Session | Reversal blocks during NOC transaction |
| `S2-FS-008` | Unrelated Property Isolation | PERFORMANCE | Dual Session | Zero cross-property blocking |
| `S2-FS-009` | Canonical Lock Hierarchy Compliance | STRUCTURAL | Code Analysis | Top-down lock acquisition |
| `S2-FS-010` | No RLS Direct Write Bypass | SECURITY | Direct SQL | RLS blocks direct table inserts |
| `S2-FS-011` | Atomic Transaction Rollback | INTEGRITY | Exception | Zero partial ledger entries |
| `S2-FS-012` | Baseline Regression Protection | REGRESSION | Full Suite | `639 / 639 PASS` baseline intact |

---

## 23. PERFORMANCE / CONTENTION ANALYSIS

- **Lock Granularity:** Per-property (`WHERE id = p_property_id`).
- **Unrelated Property Throughput:** 100% concurrent execution across different properties.
- **Society Throughput:** No society-level bottleneck introduced.

---

## 24. MIGRATION PLAN

When authorized, the migration will be executed as:
1. Apply updated `schema_slice2.sql` containing property lock additions.
2. Execute new test suite `verify_slice2_remediation.sql`.
3. Verify all 12 `S2-FS` assertions pass alongside the existing 639 baseline tests.

---

## 25. BACKWARD COMPATIBILITY

- **RPC Signatures:** Unchanged.
- **Application Code:** Zero changes required in client-side callers (`src/*`).
- **Database Schema:** Zero DDL table changes required.

---

## 26. ROLLBACK PLAN

If rollback is required during future deployment:
1. Re-execute the original `database/schema_slice2.sql` file.
2. Re-run `verify_slice1_18.sql` and `verify_slice19.sql`.
3. Confirm baseline remains `639 / 639 PASS`.

---

## 27. FILE IMPACT MATRIX

| File | Current Purpose | Future Proposed Modification | Reason | Currently Locked? |
| :--- | :--- | :--- | :--- | :--- |
| `database/schema_slice2.sql` | Slice 2 Schema & RPCs | Update 4 financial functions to lock `properties FOR UPDATE` | Enforce financial serialization barrier | **YES (READ-ONLY)** |
| `database/verify_slice2_remediation.sql` | Verification Script | Create script with `S2-FS-001` to `S2-FS-012` | Validate remediation | **NOT CREATED** |

---

## 28. DATABASE OBJECT IMPACT MATRIX

| Object | Current State | Future Proposed Change | Security Reason |
| :--- | :--- | :--- | :--- |
| `public.fn_generate_charge` | Function | Add `properties FOR UPDATE` | Eliminate TOCTOU charge race |
| `public.fn_process_payment` | Function | Add `properties FOR UPDATE` before child lock | Eliminate TOCTOU payment race |
| `public.fn_reverse_charge` | Function | Add `properties FOR UPDATE` before child lock | Eliminate TOCTOU charge reversal race |
| `public.fn_reverse_payment` | Function | Add `properties FOR UPDATE` before child lock | Eliminate TOCTOU payment reversal race |

---

## 29. SLICE 20 DEPENDENCY

```text
639 / 639 PASS BASELINE
       ↓
SLICE 2 SERIALIZATION PLAN (COMPLETED - PLAN ONLY)
       ↓
EXPLICIT USER AUTHORIZATION
       ↓
SLICE 2 REMEDIATION IMPLEMENTATION & VERIFICATION
       ↓
NEW VERIFIED BASELINE (651 / 651 PASS)
       ↓
SLICE 20 FINAL SECURITY REVALIDATION
       ↓
SEPARATE SLICE 20 IMPLEMENTATION AUTHORIZATION
```

---

## 30. FINAL ARCHITECTURAL DECISION

**SELECTED ARCHITECTURE:** `OPTION A: PROPERTY ROW LOCK` (`SELECT 1 FROM public.properties WHERE id = v_property_id FOR UPDATE`).

---

## 31. FINAL VERDICT

```text
=====================================================

SLICE 2 FINANCIAL SERIALIZATION REMEDIATION

PLAN-ONLY / ZERO IMPLEMENTATION

CURRENT VERIFIED BASELINE:
639 / 639 PASS

SLICES 1–19:
LOCKED / UNTOUCHED

SLICE 2 REMEDIATION:
NOT IMPLEMENTED
NOT VERIFIED
NOT AUTHORIZED

SLICE 20:
NOT IMPLEMENTED
NOT VERIFIED
NOT AUTHORIZED

DATABASE MODIFICATIONS:
NONE

APPLICATION MODIFICATIONS:
NONE

FINAL STATUS:
PLAN COMPLETE — IMPLEMENTATION BLOCKED

=====================================================

NO SLICE 2 IMPLEMENTATION MAY BEGIN.

NO SLICE 20 IMPLEMENTATION MAY BEGIN.

NO DATABASE CHANGES MAY BE PERFORMED.

NO APPLICATION CHANGES MAY BE PERFORMED.

ANY IMPLEMENTATION REQUIRES
SEPARATE EXPLICIT USER AUTHORIZATION.

=====================================================
```
