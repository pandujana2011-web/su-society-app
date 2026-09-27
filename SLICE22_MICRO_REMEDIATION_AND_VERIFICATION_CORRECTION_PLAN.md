# SLICE 22 — MICRO-REMEDIATION & VERIFICATION CORRECTION PLAN

**Target Repository:** `D:\Clients Applications\SU Society App`  
**Current Authoritative Baseline:** `791 / 791 PASS — 100% LOCKED / IMMUTABLE`  
**Execution Mode:** `PLAN ONLY / ZERO IMPLEMENTATION / ZERO SQL EXECUTION / ZERO BASELINE MUTATION / ZERO LOCK`  

---

## 1. EXECUTIVE STATUS

This artifact presents a comprehensive, forensically sound micro-remediation and verification-correction plan to resolve all security, concurrency, authorization, syntax, and verification defects identified in the Independent Forensic Audit of Slice 22.

- **Authoritative Locked Baseline:** **791 / 791 PASS (100% IMMUTABLE)**
- **Slice 22 Current Status:** **IMPLEMENTED / NOT VERIFIED / NOT LOCKED**
- **Micro-Remediation Plan Status:** **CREATED / READY FOR GOVERNANCE REVIEW**
- **Implementation & Database Execution:** **NOT AUTHORIZED (PLAN-ONLY MODE)**

---

## 2. CURRENT 791/791 LOCKED BASELINE

The project baseline remains strictly immutable:

- Slices 1–19: **639 / 639 PASS (LOCKED / IMMUTABLE)**
- Slice 2 Financial Remediation: **24 / 24 PASS (LOCKED / IMMUTABLE)**
- Slice 20 NOC & Move-Out: **51 / 51 PASS (LOCKED / IMMUTABLE)**
- Slice 21 Security Gate & Vendor AMC: **77 / 77 PASS (LOCKED / IMMUTABLE)**
- **Cumulative Current Baseline:** **791 / 791 PASS (100%)**

---

## 3. SLICE 22 CURRENT STATUS

- **Implementation Code:** `database/schema_slice22.sql` (Implemented / Requires Micro-Remediation)
- **Verification Suite Code:** `database/verify_slice22.sql` (Authored / Requires Verification Correction)
- **Verification Execution:** **0 Executions Performed**
- **Lock Status:** **UNLOCKED**

---

## 4. SOURCE ARTIFACTS INSPECTED

1. `SLICE22_FINAL_SECURITY_PLAN.md`
2. `SLICE22_IMPLEMENTATION_REPORT.md`
3. `SLICE22_VERIFICATION_SUITE_INDEPENDENT_FORENSIC_AUDIT.md`
4. `database/schema_slice22.sql`
5. `database/verify_slice22.sql`
6. `database/schema_slice2.sql` (Read-only financial lock inspection)
7. `database/verify_slice2.sql` (Read-only financial lock inspection)

---

## 5. FORENSIC FINDINGS SUMMARY

| Finding ID | Title / Vulnerability | Severity | Category | Required Remediation |
| :---: | :--- | :---: | :---: | :--- |
| **Finding A** | Fake Concurrency Assertions (S22-055..S22-058 hard-coded text) | **HIGH** | Verification | Replace with Node.js multi-session concurrency runner |
| **Finding B** | S22-051 Status Check Only (Does not prove Rank-1 lock) | **HIGH** | Verification | Add blocking-session lock acquisition test |
| **Finding C** | Lock Order Inversion in `fn_resolve_violation_dispute` (Rank 5 $\rightarrow$ Rank 3) | **CRITICAL** | Implementation | Lock `rule_violations` Rank 3 FIRST, then `violation_disputes` Rank 5 |
| **Finding D** | Lock Order Inversion in `fn_post_violation_penalty` (Rank 3 $\rightarrow$ 4 $\rightarrow$ 1) | **CRITICAL** | Implementation | Lock `properties` Rank 1 FIRST, then Rank 3, then Rank 4 |
| **Finding E** | Sequential Verification Cannot Detect Lock Inversions | **HIGH** | Verification | Add cross-session deadlock and serialization verifiers |
| **Finding F** | Rate Limit First-Row Creation Race on `INSERT ON CONFLICT` | **MEDIUM** | Implementation | Atomic pre-insert `ON CONFLICT DO NOTHING` before `FOR UPDATE` |
| **Finding G** | Worker Silent Error Swallowing (`EXCEPTION WHEN OTHERS THEN NULL`) | **HIGH** | Worker/Auth | Remove silent NULL, log audit error, return structured counts |
| **Finding H** | Worker Auth Incompatibility (`auth.uid()` is `NULL` in background) | **CRITICAL** | Worker/Auth | Decouple internal logic into `fn_post_violation_penalty_internal` |
| **Finding I** | Default PostgreSQL `PUBLIC` EXECUTE Privileges on RPCs | **HIGH** | Privilege | Add explicit `REVOKE EXECUTE ON FUNCTION ... FROM PUBLIC, anon;` |
| **Finding J** | `violation_rate_limits` Lacks SELECT Policy | **INFO** | RLS | Document intentional deny-all for direct SELECTs |
| **Finding K** | Cross-Society Admin RLS Leakage on `violation_disputes` | **HIGH** | RLS | Add `society_id = get_user_society_id(auth.uid())` to admin branch |
| **Finding L** | `fn_is_valid_evidence_urls` Does Not Check URL Format | **MEDIUM** | Helper | Enforce string type and `http://` / `https://` prefix checks |
| **Finding M** | Fatal PL/pgSQL Syntax Error (`END BEGIN;` line 538) | **CRITICAL** | Implementation | Replace `END BEGIN;` with `END;` |

---

## 6. IMPLEMENTATION DEFECTS & CORRECTIONS (REMEDIATION GROUP A)

### A1. Syntax Error Correction (Finding M)
In `database/schema_slice22.sql` line 538, inside `process_expired_violation_appeals()`:
```sql
-- BEFORE (FATAL SYNTAX ERROR):
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END BEGIN;

-- AFTER (CORRECT PL/pgSQL SYNTAX):
        EXCEPTION WHEN OTHERS THEN
            -- Record error state to audit log and continue
            PERFORM public.fn_log_violation_audit_event(
                v_rec.violation_id, 
                'WORKER_POSTING_FAILED', 
                SQLERRM, 
                '00000000-0000-0000-0000-000000000000'::uuid
            );
        END;
```

### A2. Lock Order Inversion in Dispute Resolution (Finding C)
In `fn_resolve_violation_dispute`:
```sql
-- CORRECTED LOCK SEQUENCE (Rank 3 FIRST, Rank 5 SECOND):
    -- Step 1: Read dispute row to find violation_id (non-locking)
    SELECT violation_id INTO v_violation_id FROM public.violation_disputes WHERE id = p_dispute_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Dispute Record Not Found'; END IF;

    -- Step 2: Lock Rule Violation Row (Rank 3) FIRST
    SELECT * INTO v_violation FROM public.rule_violations WHERE id = v_violation_id FOR UPDATE;
    IF v_violation.society_id != v_caller_society THEN
        RAISE EXCEPTION 'Access Denied: Cross-society dispute resolution blocked';
    END IF;

    -- Step 3: Lock Violation Dispute Row (Rank 5) SECOND
    SELECT * INTO v_dispute FROM public.violation_disputes WHERE id = p_dispute_id FOR UPDATE;
    IF v_dispute.resolution_status != 'pending' THEN
        RAISE EXCEPTION 'Invalid State Transition: Dispute is already resolved';
    END IF;
```

### A3. Lock Order Inversion in Financial Penalty Posting (Finding D)
In `fn_post_violation_penalty_internal`:
```sql
-- CORRECTED LOCK SEQUENCE (Rank 1 FIRST, Rank 3 SECOND, Rank 4 THIRD):
    -- Step 1: Read violation to obtain property_id and society_id (non-locking)
    SELECT property_id, society_id INTO v_property_id, v_violation_society 
    FROM public.rule_violations WHERE id = p_violation_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Violation Record Not Found'; END IF;

    -- Step 2: Lock Rank 1 Property Row FIRST (Slice 2 Financial Serialization Anchor)
    PERFORM 1 FROM public.properties WHERE id = v_property_id FOR UPDATE;

    -- Step 3: Lock Rank 3 Violation Row SECOND
    SELECT * INTO v_violation FROM public.rule_violations WHERE id = p_violation_id FOR UPDATE;

    -- Step 4: Lock Rank 4 Penalty Row THIRD
    SELECT * INTO v_penalty FROM public.violation_penalties WHERE violation_id = p_violation_id FOR UPDATE;
```

---

## 7. WORKER ARCHITECTURE & AUTHORIZATION RE-DESIGN (FINDING H & G)

### Architecture Separation:
1. **Internal Routine (`fn_post_violation_penalty_internal`):**
   - Parameters: `p_violation_id UUID`, `p_actor_id UUID`
   - Executes lock acquisition, validation, charge creation (`maintenance_charges`), debit ledger insertion (`ledger_transactions`), penalty state update (`is_posted = TRUE`), violation state update (`status = 'financially_posted'`), and audit logging (`PENALTY_FINANCIALLY_POSTED`).
   - `SECURITY DEFINER`, `search_path = pg_catalog, public`.

2. **Public RPC (`fn_post_violation_penalty`):**
   - Signature: `fn_post_violation_penalty(p_violation_id UUID) RETURNS UUID`
   - Validates `auth.uid()`, enforces `public.is_admin()`, verifies society context, and delegates to `fn_post_violation_penalty_internal(p_violation_id, auth.uid())`.

3. **Background Worker Routine (`process_expired_violation_appeals`):**
   - Signature: `process_expired_violation_appeals() RETURNS JSONB`
   - Iterates through unposted penalties past $T_{appeal\_deadline}$ where violation status is `'penalty_assessed'`.
   - Calls `fn_post_violation_penalty_internal(v_rec.violation_id, '00000000-0000-0000-0000-000000000000'::uuid)`.
   - Returns structured JSONB result: `{"processed_count": N, "failed_count": M}`.

---

## 8. RLS & PRIVILEGE RE-DESIGN (FINDINGS I, J, K)

### K1. Cross-Society Admin RLS Leakage Fix
Update `pol_violation_disputes_select`:
```sql
CREATE POLICY pol_violation_disputes_select ON public.violation_disputes
    FOR SELECT TO authenticated
    USING (
        disputed_by = auth.uid() 
        OR (public.is_admin() AND society_id = public.get_user_society_id(auth.uid()))
    );
```

### I1. Explicit Routine Privilege Revocation
Add explicit privilege management at the end of `database/schema_slice22.sql`:
```sql
REVOKE EXECUTE ON FUNCTION public.fn_report_rule_violation FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.fn_review_rule_violation FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.fn_dispute_rule_violation FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.fn_resolve_violation_dispute FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.fn_post_violation_penalty FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.process_expired_violation_appeals FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.fn_report_rule_violation TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_review_rule_violation TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_dispute_rule_violation TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_resolve_violation_dispute TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_post_violation_penalty TO authenticated;
GRANT EXECUTE ON FUNCTION public.process_expired_violation_appeals TO service_role;
```

---

## 9. RECONCILED GLOBAL LOCK HIERARCHY

| Rank | Database Object | Primary Lock Holder | Serialization Role |
| :---: | :--- | :--- | :--- |
| **Rank 1** | `public.properties` / `societies` | `fn_post_violation_penalty_internal` | Global Financial Serialization Anchor |
| **Rank 2** | `public.violation_rate_limits` | `fn_report_rule_violation` | Anti-Spam Rate Limit Counter |
| **Rank 3** | `public.rule_violations` | All Slice 22 Routines | Primary Violation State Row |
| **Rank 4** | `public.violation_penalties` | Review / Dispute / Post | Penalty Assessment Record |
| **Rank 5** | `public.violation_disputes` | Dispute / Resolve | Dispute Record |
| **Rank 6** | `public.maintenance_charges` | `fn_post_violation_penalty_internal` | Slice 2 Charge Record |
| **Rank 7** | `public.ledger_transactions` / `violation_audit_logs` | Post / All | Immutable Audit & Financial Ledger Entries |

---

## 10. CONCURRENCY HARNESS & VERIFICATION REBUILD PLAN

### Concurrency Test Scenarios (Node.js Multi-Session Harness):
1. **C1 (Concurrent Rate Limit):** 2 parallel sessions call `fn_report_rule_violation` simultaneously on a brand new reporter ID. Proves 0 primary key race errors and exact counter increment.
2. **C2 (Concurrent Review & Dispute):** Session A calls `fn_review_rule_violation` while Session B calls `fn_dispute_rule_violation` on the same violation. Proves safe row lock serialization (Rank 3) with zero deadlock.
3. **C3 (Concurrent Dispute & Resolve):** Session A calls `fn_dispute_rule_violation` while Session B calls `fn_resolve_violation_dispute`. Proves corrected lock order (Rank 3 $\rightarrow$ Rank 5) prevents deadlock.
4. **C4 (Concurrent Fine Postings):** Session A calls `fn_post_violation_penalty` while Session B calls `fn_post_violation_penalty` on the same violation. Proves exact single charge creation and zero duplicate charges.
5. **C5 (Cross-Slice Financial Serialization):** Session A calls `fn_post_violation_penalty` (Rank 1 property lock) while Session B calls Slice 2 `fn_generate_charge` on the same property. Proves complete financial serialization without deadlocks.

---

## 11. VERIFICATION ASSERTION DISPOSITION (S22-001 THROUGH S22-060)

| Assertions | Current Status | Planned Disposition | Action Required |
| :---: | :---: | :---: | :--- |
| **S22-001 .. S22-008** | Valid Schema Checks | **KEEP** | Verify object existence post schema application |
| **S22-009 .. S22-015** | Valid Auth Rejection | **MODIFY** | Add explicit checks for `PUBLIC` privilege revocation |
| **S22-016 .. S22-022** | Valid Violation Reporting | **MODIFY** | Add first-row creation race test to S22-020 |
| **S22-023 .. S22-030** | Valid Review & Penalty | **MODIFY** | Verify exact 168-hour equality on S22-027 |
| **S22-031 .. S22-038** | Valid Resident Dispute | **KEEP** | Verify dispute window boundaries |
| **S22-039 .. S22-046** | Valid Dispute Resolution | **KEEP** | Verify upheld vs reversed workflows |
| **S22-047 .. S22-054** | Valid Financial Posting | **MODIFY** | Replace status string check in S22-051 with real lock acquisition check |
| **S22-055 .. S22-058** | Static Text PASS | **REPLACE** | Replace with multi-session Node.js race verifiers C1–C5 |
| **S22-059** | Swallowed Worker Check | **REPLACE** | Replace with structured error & success worker check |
| **S22-060** | Target Arithmetic Check | **KEEP** | Governance cumulative target check ($791 + 60 = 851$) |

---

## 12. REMEDIATION GROUPS A–D

- **Group A (Mandatory Implementation Fixes):**
  - Fix Syntax Error (Finding M)
  - Fix Lock Order Inversion in `fn_resolve_violation_dispute` (Finding C)
  - Fix Lock Order Inversion in `fn_post_violation_penalty` (Finding D)
  - Fix Background Worker Auth Context & Internal Separation (Finding H & G)
  - Fix Cross-Society Admin RLS Leakage on `violation_disputes` (Finding K)
  - Fix Default `PUBLIC` EXECUTE Routine Exposure (Finding I)
  - Fix Rate Limit First-Row Creation Race (Finding F)
- **Group B (Mandatory Verification Fixes):**
  - Replace static text PASS in S22-055..S22-058 with substantive race verifiers
  - Upgrade S22-051 to prove Rank 1 lock acquisition
  - Upgrade S22-059 to prove worker error observability
- **Group C (Concurrency Harness Infrastructure):**
  - Node.js multi-session concurrency runner script (`scratch/run_slice22_concurrency_tests.js`)
- **Group D (Optional Hardening - Post-Lock):**
  - Enhanced evidence URL regex validation (Finding L)

---

## 13. REVISED FUTURE ASSERTION TARGET

- **Current Authoritative Baseline:** **791 / 791 PASS**
- **Substantive Slice 22 Assertion Count:** **60 Assertions**
- **Revised Future Cumulative Target:** **791 + 60 = 851 PASS**

*(Note: 851/851 is a FUTURE TARGET ONLY and MUST NOT be represented as achieved until execution is complete.)*

---

## 14. IMPLEMENTATION SEQUENCING PLAN

1. **Micro-Remediation Plan Creation** *(THIS TASK — COMPLETED)*
2. **Independent Forensic Audit of Micro-Remediation Plan**
3. **Pre-Implementation Authorization Gate**
4. **Explicit User Implementation Authorization**
5. **Implementation of Schema Micro-Remediation (`schema_slice22.sql`)**
6. **Implementation of Verification Suite Correction (`verify_slice22.sql`)**
7. **Execution of Verification Suite & Multi-Session Concurrency Harness**
8. **Independent Post-Implementation Forensic Audit**
9. **Lock-Readiness Gate Audit**
10. **Explicit User Lock Authorization**
11. **Slice 22 Formal Lock**

---

## 15. EXPLICIT GOVERNANCE PROHIBITIONS

### **NOT AUTHORIZED IN THIS TASK:**
- ❌ Source code implementation or modification
- ❌ Database migration or SQL execution
- ❌ Verification suite execution
- ❌ Baseline mutation (791/791 baseline remains 100% immutable)
- ❌ Slice 22 lock creation

---

## 16. FINAL VERDICT

### `A — FORENSICALLY SOUND MICRO-REMEDIATION PLAN`

This micro-remediation plan provides exact, unambiguous, forensically sound technical specifications for resolving all identified defects in Slice 22. It is completely ready for governance review and independent implementation authorization.
