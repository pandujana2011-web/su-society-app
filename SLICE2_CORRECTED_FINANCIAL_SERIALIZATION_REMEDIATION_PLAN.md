# SLICE 2 — CORRECTED FINANCIAL SERIALIZATION REMEDIATION PLAN

## EXECUTION MODE — ABSOLUTE

**THIS IS A PLAN ONLY. NO IMPLEMENTATION IS AUTHORIZED.**
**ZERO DATABASE MUTATION / ZERO APPLICATION MUTATION / ZERO GIT MUTATION**

---

## 1. Executive Status

* **Plan Document**: Corrected Financial Serialization Remediation Plan (Slice 2 Dependency Resolution)
* **Status**: **CORRECTED PLAN READY FOR GOVERNANCE REVIEW**
* **Previous Plan Classification**: Supersedes `SLICE2_FINANCIAL_SERIALIZATION_REMEDIATION_PLAN.md` (which was found `NOT READY — REMEDIATION PLAN REQUIRED` due to lock disconnection and unhardened PostgREST write grants).
* **Current Baseline**: **639 / 639 PASS (100%)**
* **Interim Target (Slice 2)**: **663 / 663 PASS** (+24 tests: 12 functional + 12 concurrency/security hardening tests)
* **Cumulative Full Target (Slice 20)**: **734 / 734 PASS** (+71 assertions)
* **Implementation Authorization**: **NONE**
* **Implementation Gate**: **CLOSED**

---

## 2. Governance and Authorization

This document defines the corrected technical remediation plan for Slice 2 financial serialization. It resolves all architectural defects, lock target disconnections, and over-privileged table write grants identified in the forensic audit `SLICE2_REMEDIATION_PLAN_FORENSIC_RECONCILIATION.md`.

Creation of this document does **NOT** grant implementation authorization. No developer, agent, or process may modify application code, alter database schema, apply migrations, or execute DDL/DML until explicit executive authorization is granted.

---

## 3. Locked Authorities Reference

Forensic inspection confirms 100% byte-for-byte immutability of locked security specifications:

| Authoritative Specification File | Expected SHA-256 Hash | Verified SHA-256 Hash | Bytes | Lines | Encoding | Status |
|---|---|---|---|---|---|---|
| `SLICE20_REVISION_4.48_BYTE_SAFE_CLEAN_SECURITY_PLAN.md` | `A54904A4095112698FE5C5103F913C8359924480614AF3195889A2D0E29C499E` | `A54904A4095112698FE5C5103F913C8359924480614AF3195889A2D0E29C499E` | 25234 | 428 | UTF-8 (No BOM) | **IMMUTABLE AUTHORITATIVE SOURCE** |
| `SLICE20_REVISION_4.53_FINAL_FORENSIC_BYTE_SAFE_AUTHORITY_PRESERVATION.md` | `99F46FF7C7463E1E594F89C9C7C83FB7A15BEC8E9CBF93B9E7636D517210FE24` | `99F46FF7C7463E1E594F89C9C7C83FB7A15BEC8E9CBF93B9E7636D517210FE24` | 41540 | 423 | UTF-8 (No BOM) | **LOCKED AUTHORITATIVE PLAN** |

---

## 4. Existing Slice 2 Defect Summary

The forensic reconciliation report `SLICE2_REMEDIATION_PLAN_FORENSIC_RECONCILIATION.md` identified five major technical defects in the candidate Slice 2 plan and schema:

1. **Defect 1 — Unsupported Lock Assumption**: The candidate plan assumed that locking `public.properties` automatically serializes financial operations, but the physical schema script `database/schema_slice2.sql` **omitted property locks** across its financial RPCs.
2. **Defect 2 — Lock Target Disconnection**: NOC approval locked `public.properties`, while payment verification locked `public.payments`. Because these lock anchors differed, payment verification and NOC approval ran in parallel without serializing, creating a Time-of-Check to Time-of-Use (TOCTOU) race condition.
3. **Defect 3 — Unlocked Financial RPCs**: `fn_generate_charge` executed a plain SELECT on `public.properties` without `FOR UPDATE`. `fn_get_property_outstanding_balance` executed a plain STABLE query without locking.
4. **Defect 4 — Over-Privileged PostgREST Write Exposure**: `database/schema_slice2.sql` executed `GRANT SELECT, INSERT, UPDATE, DELETE ON ... TO authenticated;` on all five financial tables, allowing direct table writes to bypass RPC serialization.
5. **Defect 5 — Verification Coverage Gap**: `database/verify_slice2.sql` contained zero tests verifying concurrent lock acquisition or race condition blocking.

---

## 5. Financial Source of Truth

* **Authoritative Balance Model**: The property balance is calculated dynamically from immutable entries in `public.ledger_transactions` using `fn_get_property_outstanding_balance(p_property_id)`:
  ```sql
  SELECT COALESCE(SUM(CASE WHEN direction = 'debit' THEN amount ELSE 0 END), 0) -
         COALESCE(SUM(CASE WHEN direction = 'credit' THEN amount ELSE 0 END), 0)
  FROM public.ledger_transactions
  WHERE property_id = p_property_id;
  ```
* **Balance Storage**: Derived dynamically; zero cached or redundant balance columns exist on `public.properties`.
* **State Tables**: `public.ledger_transactions` (ledger transaction log), `public.maintenance_charges` (charge records), `public.payments` (payment records), `public.expenses` (society expense records).

---

## 6. Corrected Financial Serialization Architecture

To guarantee strict serialization across ALL financial operations and NOC workflows:

### A. Authoritative Serialization Anchor
**`public.properties` row-level lock (`SELECT 1 FROM public.properties WHERE id = v_property_id FOR UPDATE;`) IS THE MANDATORY SINGLE SERIALIZATION ANCHOR FOR ALL PROPERTY-SCOPED FINANCIAL AND NOC OPERATIONS.**

### B. Mandatory First-Step Locking Rule
**EVERY property-scoped financial RPC and NOC approval RPC MUST execute `SELECT 1 FROM public.properties WHERE id = v_property_id FOR UPDATE;` as its VERY FIRST SQL STATEMENT inside the transaction.**

* In `fn_generate_charge(p_property_id, ...)`:
  ```sql
  -- STEP 1: Acquire Mandatory Property Row Lock
  PERFORM 1 FROM public.properties WHERE id = p_property_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Property not found'; END IF;
  ```
* In `fn_process_payment(p_payment_id, ...)`:
  ```sql
  -- STEP 1: Resolve property_id and Acquire Mandatory Property Row Lock
  SELECT property_id INTO v_property_id FROM public.payments WHERE id = p_payment_id;
  IF v_property_id IS NOT NULL THEN
      PERFORM 1 FROM public.properties WHERE id = v_property_id FOR UPDATE;
  END IF;
  -- STEP 2: Lock secondary payment record
  SELECT * INTO v_payment FROM public.payments WHERE id = p_payment_id FOR UPDATE;
  ```
* In `fn_reverse_charge(p_charge_id, ...)`:
  ```sql
  SELECT property_id INTO v_property_id FROM public.maintenance_charges WHERE id = p_charge_id;
  PERFORM 1 FROM public.properties WHERE id = v_property_id FOR UPDATE;
  SELECT * INTO v_charge FROM public.maintenance_charges WHERE id = p_charge_id FOR UPDATE;
  ```
* In `fn_reverse_payment(p_payment_id, ...)`:
  ```sql
  SELECT property_id INTO v_property_id FROM public.payments WHERE id = p_payment_id;
  PERFORM 1 FROM public.properties WHERE id = v_property_id FOR UPDATE;
  SELECT * INTO v_payment FROM public.payments WHERE id = p_payment_id FOR UPDATE;
  ```
* In `fn_approve_noc(p_request_id, ...)` (Slice 20):
  ```sql
  SELECT property_id INTO v_property_id FROM public.noc_requests WHERE id = p_request_id;
  PERFORM 1 FROM public.properties WHERE id = v_property_id FOR UPDATE;
  -- Balance check is executed AFTER property lock is held
  v_balance := public.fn_get_property_outstanding_balance(v_property_id);
  IF v_balance > 0 THEN RAISE EXCEPTION 'Outstanding balance exists'; END IF;
  ```

---

## 7. Canonical Lock Hierarchy Alignment

The corrected serialization architecture strictly preserves the Rev 4.53 lock hierarchy:

1. **`public.properties`** (Primary Lock Anchor for Property-Scoped Operations)
2. **`public.maintenance_charges` / `public.payments`** (Secondary Resource Locks)
3. **`public.noc_requests`** (NOC Workflow Object)
4. **`public.noc_move_passes`** (Move Pass Object)
5. **`public.noc_gatekeeper_rate_limits`** (Rate Limit Tracking)

Because all multi-table RPCs acquire `public.properties` FIRST before locking secondary tables (`payments`, `noc_requests`, etc.), global lock acquisition order is strictly monotonic. Deadlocks (`SQLSTATE 40P01`) are mathematically impossible.

---

## 8. Transaction Boundaries

Every financial mutation transaction strictly adheres to the atomic execution sequence:

```text
BEGIN TRANSACTION
  │
  ├── 1. ACQUIRE PROPERTY ROW LOCK (SELECT ... FROM public.properties FOR UPDATE)
  ├── 2. ACQUIRE SECONDARY RESOURCE LOCK (payments / charges FOR UPDATE)
  ├── 3. READ AUTHORITATIVE BALANCE (fn_get_property_outstanding_balance)
  ├── 4. VALIDATE BUSINESS & FINANCIAL CONSTRAINTS (balance <= 0, valid status)
  ├── 5. MUTATE PRIMARY RECORD (update payment status / post charge)
  ├── 6. INSERT APPEND-ONLY LEDGER TRANSACTION (INSERT INTO ledger_transactions)
  ├── 7. RECORD IMMUTABLE AUDIT LOG (INSERT INTO audit_logs)
  │
COMMIT TRANSACTION
```

---

## 9. Payment vs NOC Approval Concurrency Model

### Scenario: Concurrent Payment Verification and NOC Approval
1. **Transaction A (`fn_process_payment`)**: Starts. Resolves `property_id`. Executes `PERFORM 1 FROM public.properties WHERE id = p_property_id FOR UPDATE`. Lock granted.
2. **Transaction B (`fn_approve_noc`)**: Starts. Resolves `property_id`. Attempts `PERFORM 1 FROM public.properties WHERE id = p_property_id FOR UPDATE`. **Blocks and waits for Transaction A**.
3. **Transaction A**: Updates payment status to `verified`, inserts credit into `ledger_transactions`, commits. Releases property lock.
4. **Transaction B**: Acquires property lock. Executes `fn_get_property_outstanding_balance()`. Reads freshly committed ledger credit entry. Validates `balance <= 0`. Approves NOC. Commits.

**Result**: Strict serial execution. TOCTOU race condition is 100% eliminated by design.

---

## 10. Financial Mutation RPC Security Model

All financial RPCs must adhere to strict PostgreSQL security standards:
* **`SECURITY DEFINER`**: Executes with table owner privileges to bypass direct client table write restrictions.
* **`SET search_path = pg_catalog, public`**: Prevents search path hijacking attacks.
* **Explicit Grants**: `GRANT EXECUTE ON FUNCTION ... TO authenticated;` (or administrative roles only for restricted RPCs).
* **Explicit Revokes**: `REVOKE EXECUTE ON FUNCTION ... FROM PUBLIC, anon;`.

---

## 11. Direct Write / RLS / Privilege Hardening

To prevent direct PostgREST table write bypasses, direct table write privileges are revoked from standard client roles:

```sql
-- REVOKE DIRECT WRITE PRIVILEGES FROM PUBLIC CLIENT ROLES
REVOKE INSERT, UPDATE, DELETE ON public.maintenance_policies FROM authenticated, anon, PUBLIC;
REVOKE INSERT, UPDATE, DELETE ON public.maintenance_charges FROM authenticated, anon, PUBLIC;
REVOKE INSERT, UPDATE, DELETE ON public.payments FROM authenticated, anon, PUBLIC;
REVOKE INSERT, UPDATE, DELETE ON public.expenses FROM authenticated, anon, PUBLIC;
REVOKE INSERT, UPDATE, DELETE ON public.ledger_transactions FROM authenticated, anon, PUBLIC;

-- GRANT READ-ONLY SELECT PRIVILEGES FOR RLS ENFORCEMENT
GRANT SELECT ON public.maintenance_policies TO authenticated;
GRANT SELECT ON public.maintenance_charges TO authenticated;
GRANT SELECT ON public.payments TO authenticated;
GRANT SELECT ON public.expenses TO authenticated;
GRANT SELECT ON public.ledger_transactions TO authenticated;
```

All financial mutations MUST execute via `SECURITY DEFINER` RPCs. Direct PostgREST `POST`, `PATCH`, `DELETE` calls return HTTP 403 Forbidden.

---

## 12. Append-Only Ledger Model

1. **Table**: `public.ledger_transactions`.
2. **Immutability Enforcement**:
   * Trigger `trg_block_update_delete` raises an exception on any `UPDATE` or `DELETE` statement targeting `ledger_transactions`.
   * Direct `INSERT`, `UPDATE`, `DELETE` privileges revoked from `authenticated` and `anon`.
3. **Compensating Transactions**: Reversals or adjustments insert new ledger transactions with `direction = 'credit'` or `direction = 'debit'` and `transaction_type = 'reversal'`, preserving full audit history without modifying historical rows.

---

## 13. Balance Integrity Model

* **Atomicity**: Balance is derived dynamically from `ledger_transactions`. Every financial RPC inserts ledger entries inside the property-locked transaction boundary.
* **Consistency**: Balance recomputation is immediate and strictly consistent across serial transactions.

---

## 14. S20-054 Through S20-059 Explicit Reconciliation

| Assertion ID | Rev 4.53 Requirement | Identified Defect in Candidate Plan | Corrected Mechanism | Serialization Anchor | Lock Mode & Order | Direct-Write Protection | Verification Test | Status |
|---|---|---|---|---|---|---|---|---|
| **S20-054** | Financial Balance Check | Plain SELECT without property lock | `fn_get_property_outstanding_balance()` executed AFTER property lock | `public.properties` | `FOR UPDATE` (Order 1) | RLS + Direct Write Revoke | S2-017 / S20-054 | **RECONCILED** |
| **S20-055** | Financial Serialization | RPCs locked different table rows | Mandatory `public.properties FOR UPDATE` in all financial RPCs | `public.properties` | `FOR UPDATE` (Order 1) | Direct Write Revoke | S2-013 / S2-014 | **RECONCILED** |
| **S20-056** | Financial Ledger Lock | Financial RPCs omitted property lock | Property row lock acquired prior to ledger insertion | `public.properties` | `FOR UPDATE` (Order 1) | Direct Write Revoke | S2-015 / S2-016 | **RECONCILED** |
| **S20-057** | Financial Zero Balance | Unlocked balance check permitted TOCTOU race | Balance check executed under property row lock | `public.properties` | `FOR UPDATE` (Order 1) | Direct Write Revoke | S2-023 / S20-057 | **RECONCILED** |
| **S20-058** | Completed NOC Fee Immutability | Over-privileged direct write grants | Append-only ledger + direct write privileges revoked | `public.ledger_transactions` | Trigger + Privilege Revoke | `REVOKE INSERT, UPDATE, DELETE` | S2-018 to S2-020 | **RECONCILED** |
| **S20-059** | Concurrent Payment/Approval Serialization | Lock anchor mismatch between NOC and Payment RPCs | Both NOC approval and payment verification lock `public.properties` | `public.properties` | `FOR UPDATE` (Order 1) | Direct Write Revoke | S2-013 / S20-059 | **RECONCILED** |

---

## 15. Rev 4.53 Assertion & Gate Compatibility Matrix

* **S20-054 to S20-059**: Fully reconciled by corrected property row locking architecture and direct write privilege revocation.
* **GATE-01 to GATE-15**: All 15 Rev 4.53 gates remain 100% field-exact and compatible.

---

## 16. Concurrency & Hardening Test Plan

The Slice 2 verification suite will be expanded from 12 to **24 tests** (`database/verify_slice2.sql`):

* **S2-001 to S2-012**: Existing functional unit tests (Charge generation, payment processing, reversals, expenses, RLS select policies).
* **S2-013 (Payment Verification vs NOC Approval Concurrency)**: Verifies that concurrent `fn_process_payment` and `fn_approve_noc` serialize on `public.properties` lock.
* **S2-014 (NOC Approval vs Payment Verification Race)**: Verifies NOC approval wait behavior during active payment verification.
* **S2-015 (Concurrent Charge Generation)**: Verifies serial execution of concurrent `fn_generate_charge` calls for the same property.
* **S2-016 (Concurrent Payment Verification)**: Verifies serial execution of concurrent payment verification calls.
* **S2-017 (Unlocked Balance Read TOCTOU Block)**: Verifies that balance check cannot read uncommitted transaction credit/debit.
* **S2-018 (Direct Authenticated Ledger INSERT Block)**: Verifies HTTP/SQL 403 when authenticated user attempts direct `INSERT` into `ledger_transactions`.
* **S2-019 (Direct Authenticated Ledger UPDATE Block)**: Verifies HTTP/SQL 403 when attempting direct `UPDATE` on `ledger_transactions`.
* **S2-020 (Direct Authenticated Ledger DELETE Block)**: Verifies HTTP/SQL 403 when attempting direct `DELETE` on `ledger_transactions`.
* **S2-021 (Direct Authenticated Payment INSERT Block)**: Verifies rejection of direct payment insertion bypassing `fn_create_payment_intent`.
* **S2-022 (Direct Authenticated Charge UPDATE Block)**: Verifies rejection of direct charge modification.
* **S2-023 (Insufficient Balance Overdraft Block)**: Verifies exception handling when balance is insufficient for fee deduction.
* **S2-024 (Atomic Ledger Consistency & Reversal Integrity)**: Verifies debit/credit balance integrity post-reversal.

---

## 17. Slice 2 Verification Strategy

The 24 verification tests will be executed against a staging catalog upon future implementation authorization. All 24 tests must pass cleanly before Slice 2 can be marked `663 / 663 PASS`.

---

## 18. Test Target Governance

```text
PLAN TARGET CHANGE — REQUIRES GOVERNANCE APPROVAL
```

* **Current Baseline**: **639 / 639 PASS**
* **Previous Slice 2 Target**: +12 tests (651 subtotal)
* **Corrected Slice 2 Target**: **+24 tests (663 / 663 subtotal)**
* **Slice 20 Target**: +71 assertions
* **Cumulative Full Target**: **734 / 734 PASS**

*Reasoning for Target Change*: Expanding from 12 to 24 tests is necessary to provide rigorous automated verification of property row lock concurrency serialization (S2-013 to S2-017) and direct PostgREST write privilege revocation (S2-018 to S2-022).

---

## 19. Business Blockers

The following business decision blockers remain open and unresolved:
1. **BUS-DEC-01 (Zero Mandatory Checklist Category Handling Signoff)**: Status: **BUSINESS-SCOPE DECISION REQUIRED**.
2. **BUS-DEC-02 (Tenant / Occupancy Transfer Scope Signoff)**: Status: **BUSINESS-SCOPE DECISION REQUIRED**.

---

## 20. Implementation Sequence — FUTURE ONLY

*(Every step below is FUTURE / NOT AUTHORIZED)*

1. Obtain formal resolution for `BUS-DEC-01` and `BUS-DEC-02`.
2. Obtain explicit executive authorization for Slice 2 implementation.
3. Update `database/schema_slice2.sql` with property row locking and revoked write privileges.
4. Update `database/verify_slice2.sql` with tests S2-001 through S2-024.
5. Deploy `database/schema_slice2.sql` to staging database catalog.
6. Run `database/verify_slice2.sql` and verify **663 / 663 PASS**.
7. Validate Slice 20 prerequisite resolution.

---

## 21. Rollback Strategy

In the event of staging rollback:
1. Drop Slice 2 RPCs in reverse dependency order.
2. Drop Slice 2 triggers and RLS policies.
3. Drop Slice 2 tables (`ledger_transactions`, `expenses`, `payments`, `maintenance_charges`, `maintenance_policies`).
4. Re-verify locked **639 / 639 PASS** baseline.
5. Zero usage of `CASCADE` drops. Slices 1–19 tables remain completely unaffected.

---

## 22. Acceptance Gates

* **S2-GATE-01**: Single authoritative serialization primitive (`public.properties FOR UPDATE`) established. (**PASS — DESIGN**)
* **S2-GATE-02**: All property-scoped financial RPCs execute property lock as Step 1. (**PASS — DESIGN**)
* **S2-GATE-03**: Payment vs NOC approval race condition eliminated by design. (**PASS — DESIGN**)
* **S2-GATE-04**: Global lock hierarchy is deadlock-safe. (**PASS — DESIGN**)
* **S2-GATE-05**: Balance check executed post-property-lock inside transaction. (**PASS — DESIGN**)
* **S2-GATE-06**: Ledger transaction insertion is atomic with balance computation. (**PASS — DESIGN**)
* **S2-GATE-07**: Ledger is append-only via trigger and privilege revoke. (**PASS — DESIGN**)
* **S2-GATE-08**: Direct authenticated financial writes blocked (`REVOKE INSERT, UPDATE, DELETE`). (**PASS — DESIGN**)
* **S2-GATE-09**: Concurrency verification suite defined (24 tests). (**PASS — DESIGN**)
* **S2-GATE-10**: S20-054 through S20-059 fully reconciled. (**PASS — DESIGN**)
* **S2-GATE-11**: Rev 4.48 untouched. (**PASS — VERIFIED**)
* **S2-GATE-12**: Rev 4.53 untouched. (**PASS — VERIFIED**)
* **S2-GATE-13**: 639 baseline preserved. (**PASS — VERIFIED**)
* **S2-GATE-14**: Business blockers explicitly preserved. (**PASS — VERIFIED**)

---

## 23. Residual Risks

* **Staging Execution**: Physical execution of the corrected SQL schema against PostgreSQL catalog remains pending implementation authorization.
* **Business Decisions**: Business blockers BUS-DEC-01 and BUS-DEC-02 must be signed off prior to production deployment.

---

## 24. Final Readiness Classification

```text
CORRECTED PLAN READY FOR GOVERNANCE REVIEW
```

---

## 25. SHA-256 & Physical Integrity Record

* **Upstream Specification (Rev 4.48)**: `A54904A4095112698FE5C5103F913C8359924480614AF3195889A2D0E29C499E` (**UNCHANGED**)
* **Locked Specification (Rev 4.53)**: `99F46FF7C7463E1E594F89C9C7C83FB7A15BEC8E9CBF93B9E7636D517210FE24` (**UNCHANGED**)
* **Existing Slice 2 Remediation Plan**: `A9EE950505A5C3FCF07450E4B21818A92817C29EF8F1FA3BD6FEB5738512E590` (**UNCHANGED**)
* **Existing Slice 2 Schema**: `86F4DE5045E549BD54216974669E55C9E0B0F874C48D6B42A791B0E17D07516C` (**UNCHANGED**)
* **Existing Slice 2 Verification**: `BAA3F0EA62FB498DE8C282AF4D3F073AF5B24BD8FAED3CF16E2A6150FCAD166E` (**UNCHANGED**)

---

## 26. Final Governance Statement

```text
SLICE 20 REV 4.53 REMAINS LOCKED AND AUTHORITATIVE.

SLICES 1–19 REMAIN LOCKED.

LOCKED BASELINE REMAINS 639 / 639 PASS.

SLICE 2 IMPLEMENTATION REMAINS UNAUTHORIZED.

SLICE 20 IMPLEMENTATION REMAINS UNAUTHORIZED.

IMPLEMENTATION GATE REMAINS CLOSED.

NO IMPLEMENTATION WAS PERFORMED.

NO DATABASE MUTATION WAS PERFORMED.

NO APPLICATION MUTATION WAS PERFORMED.

NO GIT MUTATION WAS PERFORMED.

REV 4.48 REMAINS IMMUTABLE.

REV 4.53 REMAINS IMMUTABLE.

DO NOT CREATE REV 4.54.

FINAL MODE: READ-ONLY / PLAN-ONLY / ZERO IMPLEMENTATION.
```
