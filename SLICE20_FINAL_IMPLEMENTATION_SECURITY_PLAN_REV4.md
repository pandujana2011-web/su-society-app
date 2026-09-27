# SLICE 20 REVISION 4 — FINAL IMPLEMENTATION & SECURITY PLAN

**Execution Date:** September 7, 2026  
**Target Repository:** `D:\Clients Applications\SU Society App`  
**Mode:** **PLAN REVISION ONLY / ZERO IMPLEMENTATION AUTHORIZATION**  
**Slice:** 20  
**Feature:** Resident Move-In / Move-Out Digital NOC Clearance & Property Transfer Workflow  
**Current Locked Baseline:** **639 / 639 PASS (100%)**  
**Locked Scope:** **SLICES 1–19 — IMMUTABLE**  

---

## 1. EXECUTIVE SUMMARY & REVISION 4 PURPOSE

This document establishes **Revision 4** of the **Slice 20 Implementation & Security Plan**.

Revision 4 addresses the critical concurrency finding discovered during adversarial security analysis: **Slice 20 cannot unilaterally achieve true financial serialization against un-cooperating concurrent financial writers without cross-slice lock participation**.

### Key Architectural Findings & Design Improvements:
1. **Financial TOCTOU Serialization Analysis:** Existing Slice 2 routines (`fn_generate_charge`, `fn_process_payment`, `fn_reverse_charge`, `fn_reverse_payment`) do NOT acquire `FOR UPDATE` locks on `public.properties` nor do they acquire advisory locks. Consequently, a lock on `public.properties` inside Slice 20 alone DOES NOT block Slice 2 financial transactions from inserting new debits concurrently.
2. **Architectural Dependency Identification:** True financial mutual exclusion requires Slice 2 financial mutation routines to acquire the same property lock (`FOR UPDATE`) or advisory lock. Because Slices 1–19 are permanently locked and immutable, this dependency is formally classified as an **Architectural Blocker**, and Slice 20 implementation remains **NOT IMPLEMENTATION-READY** until cross-slice lock participation is authorized.
3. **CSPRNG 48-Bit Pass Token Entropy:** Upgrades `pass_token` from 5 alphanumeric chars (~25.8 bits) to 12 hex characters (`PASS-2026-` + `gen_random_bytes(6)` hex), yielding 48 bits of entropy and eliminating token enumeration risks.
4. **Explicit RPC Function ACL Hardening:** Mandates `REVOKE ALL ON FUNCTION <exact_signature> FROM PUBLIC;` followed by `GRANT EXECUTE ON FUNCTION <exact_signature> TO authenticated;` for all 9 SECURITY DEFINER RPCs.
5. **Rolling-Window Persistent Rate Limiting:** Formulates the exact rolling-window query for `public.noc_gatekeeper_rate_limits` using 10-minute sliding window checks (`COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '10 minutes')`).
6. **72 Planned Assertions:** Incorporates 3 new security assertions (`S20-070` to `S20-072`) covering function ACL revocation, CSPRNG token entropy, and financial serialization barrier checks, targeting a cumulative suite of **711 / 711 PASS**.

---

## 2. LOCKED BASELINE

The project baseline remains immutable and permanently locked:

```text
=====================================================

SLICES 1–18 LOCKED BASELINE:     595 / 595 PASS (100%)

SLICE 19 VERIFIED SUITE:          44 /  44 PASS (100%)

-----------------------------------------------------

CUMULATIVE LOCKED BASELINE:      639 / 639 PASS (100%)
CUMULATIVE STATUS:               100%

INDEPENDENT SECURITY AUDIT:      PASSED
SECURITY FINDINGS:               0

SLICES 1–19 STATUS:              SECURITY LOCKED
                                 AND IMMUTABLE

=====================================================
```

---

## 3. EXISTING ARCHITECTURE INVENTORY — FINANCIAL MUTATION PATHS

Adversarial inspection of the codebase (`database/schema_slice2.sql`) identified all active financial write paths:

| Function Name | Tables Modified | Rows Locked | Property Row Lock? | Advisory Lock? | Mutual Exclusion with Slice 20? |
| :--- | :--- | :--- | :---: | :---: | :---: |
| `public.fn_generate_charge` | `maintenance_charges`, `ledger_transactions` | None | **NO** | **NO** | **NO** |
| `public.fn_process_payment` | `payments`, `ledger_transactions` | `payments` (`FOR UPDATE`) | **NO** | **NO** | **NO** |
| `public.fn_reverse_charge` | `maintenance_charges`, `ledger_transactions` | `maintenance_charges` (`FOR UPDATE`) | **NO** | **NO** | **NO** |
| `public.fn_reverse_payment` | `payments`, `ledger_transactions` | `payments` (`FOR UPDATE`) | **NO** | **NO** | **NO** |
| `public.fn_post_expense` | `expenses`, `ledger_transactions` | None | **NO** | **NO** | **N/A** (Society scope) |
| `public.fn_reverse_expense` | `expenses`, `ledger_transactions` | `expenses` (`FOR UPDATE`) | **NO** | **NO** | **N/A** (Society scope) |

---

## 4. FINANCIAL SERIALIZATION — PROOF OF MUTUAL EXCLUSION

### Question 1: Do existing Slice 1–19 financial writers participate in the Slice 20 lock?
```text
NO
```
*Proof:* Read-only inspection of `database/schema_slice2.sql` confirms that `fn_generate_charge`, `fn_process_payment`, `fn_reverse_charge`, and `fn_reverse_payment` execute `SELECT` against `public.properties` without `FOR UPDATE` and do not invoke `pg_advisory_xact_lock`.

### Question 2: Can Slice 20 alone guarantee mutual exclusion against un-cooperating writers in Read Committed isolation?
```text
NO
```
*Proof:* In PostgreSQL Read Committed transaction isolation, a transaction holding a lock on `public.properties` or an advisory lock does NOT block a concurrent transaction that inserts into `public.ledger_transactions` without requesting those same locks. Therefore, a charge debit can commit concurrently during an NOC approval transaction.

### Verdict:
```text
FINANCIAL SERIALIZATION REMAINS AN ARCHITECTURAL BLOCKER.
```

### Required Cross-Slice Remediation (Future Patch Requirement):
To achieve 100% true financial serialization, a future minor patch must be authorized for Slice 2 financial RPCs to acquire a shared property lock at the start of financial writes:
```sql
-- Required patch inside Slice 2 financial mutation routines:
PERFORM 1 FROM public.properties WHERE id = p_property_id FOR UPDATE;
```
Until this lock participation is enabled in Slice 2, Slice 20 implementation must remain **BLOCKED**.

---

## 5. REVISED Cryptographic TOKEN & PIN SPECIFICATION

1. **Pass Token Generation (48 Bits Entropy):**  
   - Generated via CSPRNG `extensions.gen_random_bytes(6)` encoded to 12 uppercase hexadecimal characters.
   - Format: `PASS-2026-A1B2C3D4E5F6`.
   - Entropy: $16^{12} = 281,474,976,710,656$ combinations (48 bits). Eliminates pass token guessing/enumeration.
2. **6-Digit PIN Generation:**  
   - Derived from 32-bit CSPRNG integer: `(abs(get_byte(bytes, 0) << 24 | get_byte(bytes, 1) << 16 | get_byte(bytes, 2) << 8 | get_byte(bytes, 3)) % 900000) + 100000`.
   - Stored as bcrypt hash via `extensions.crypt(pin, extensions.gen_salt('bf', 8))`. Plaintext PIN exposed **only once** in creation RPC response.

---

## 6. EXPLICIT RPC FUNCTION ACL & REVOCATION POLICIES

All 9 Slice 20 SECURITY DEFINER RPCs must explicitly revoke default `PUBLIC` execution privileges:

```sql
REVOKE ALL ON FUNCTION public.submit_noc_request(UUID, TEXT, DATE, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_noc_request(UUID, TEXT, DATE, TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.perform_financial_dues_clearance(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.perform_financial_dues_clearance(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.update_clearance_checklist_item(UUID, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_clearance_checklist_item(UUID, TEXT, TEXT, TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.approve_noc_request(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.approve_noc_request(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.reject_noc_request(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reject_noc_request(UUID, TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.cancel_noc_request(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cancel_noc_request(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.generate_noc_move_pass(UUID, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.generate_noc_move_pass(UUID, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT, TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.verify_noc_move_pass(TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.verify_noc_move_pass(TEXT, TEXT, TEXT, TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.process_expired_noc_passes() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.process_expired_noc_passes() TO authenticated;
```

---

## 7. PERSISTENT SLIDING-WINDOW RATE LIMITING

Rate limiting uses table `public.noc_gatekeeper_rate_limits` with sliding window calculation:

```sql
-- Lock gatekeeper rate limit record
SELECT * INTO v_limit 
FROM public.noc_gatekeeper_rate_limits 
WHERE society_id = v_society_id AND gatekeeper_id = auth.uid() 
FOR UPDATE;

-- Evaluate active lockout
IF v_limit.lockout_until IS NOT NULL AND v_limit.lockout_until > NOW() THEN
    RAISE EXCEPTION 'Gatekeeper verification locked out due to excessive failed attempts.' USING ERRCODE = '22000';
END IF;

-- Sliding window evaluation (10 failures within last 10 minutes)
IF v_limit.window_start < NOW() - INTERVAL '10 minutes' THEN
    v_failed_count := 1;
    v_window_start := NOW();
ELSE
    v_failed_count := v_limit.failed_count + 1;
    v_window_start := v_limit.window_start;
END IF;

IF v_failed_count >= 10 THEN
    v_lockout_until := NOW() + INTERVAL '15 minutes';
END IF;
```

---

## 8. TENANCY & OCCUPANCY MUTATION SPECIFICATION

1. **Move-In Activation (`move_direction = 'in'`):**
   - Tenant Move-In: `UPDATE public.tenancies SET status = 'active', updated_at = NOW() WHERE property_id = v_noc.property_id AND tenant_id = v_noc.requester_id AND status IN ('pending', 'approved');`
   - Owner Move-In: `UPDATE public.properties SET occupancy_status = 'occupied', updated_at = NOW() WHERE id = v_noc.property_id;`
2. **Move-Out Semantics (`move_direction = 'out'`):**
   - Tenant Move-Out: `UPDATE public.tenancies SET end_date = CURRENT_DATE, status = 'terminated', updated_at = NOW() WHERE property_id = v_noc.property_id AND tenant_id = v_noc.requester_id AND (end_date IS NULL OR end_date >= CURRENT_DATE);`
   - Owner Move-Out: `UPDATE public.properties SET occupancy_status = 'vacant', updated_at = NOW() WHERE id = v_noc.property_id;`
   - Property Ownership Records (`public.property_owners`): **100% UNTOUCHED** (deferred to Slice 24).

---

## 9. COMPLETE DATABASE SCHEMA SPECIFICATION

Slice 20 introduces 4 tables to `public` schema:

1. `public.noc_requests`: Primary NOC application entity.
2. `public.noc_clearance_checklists`: Category sign-off checklist (`financial_dues`, `facility_inspection`, `keys_access_cards`, `legal_title_verification`, `admin_signoff`).
3. `public.noc_move_passes`: Gate move pass with `pass_token` (`PASS-2026-A1B2C3D4E5F6`), bcrypt PIN hash, vehicle registration, and status (`active`, `used`, `expired`, `revoked`). Option B lifecycle with Partial Unique Index `uq_active_noc_move_pass`.
4. `public.noc_gatekeeper_rate_limits`: Persistent sliding-window guard rate-limiting table.

All 4 tables enforce `ENABLE` and `FORCE ROW LEVEL SECURITY` with restrictive DML policies (`USING (false) WITH CHECK (false)`).

---

## 10. REVISED ASSERTION MATRIX (72 ASSERTIONS)

Slice 20 Revision 4 defines **72 detailed test assertions (`S20-001` through `S20-072`)**:

| Test ID | Test Assertion Description | Planned Outcome |
| :--- | :--- | :---: |
| **S20-001** | 4 New NOC Tables Exist (`noc_requests`, `checklists`, `passes`, `rate_limits`) | PASS |
| **S20-002** | Partial Unique Index `uq_active_noc_request` Exists | PASS |
| **S20-003** | Partial Unique Index `uq_active_noc_move_pass` Exists | PASS |
| **S20-004** | Public Token Unique Index `idx_noc_move_passes_token` Exists | PASS |
| **S20-005** | Persistent Rate Limit Unique Index `uq_gatekeeper_rate_limit` Exists | PASS |
| **S20-006** | Foreign Key Reference Constraints Intact Across All 4 Tables | PASS |
| **S20-007** | 9 NOC RPC Routines Exist | PASS |
| **S20-008** | SECURITY DEFINER & `search_path` Hardened on All 9 RPCs | PASS |
| **S20-009** | RLS & FORCE RLS Enabled on All 4 Tables | PASS |
| **S20-010** | Anonymous `submit_noc_request` Blocked (`42501`) | PASS |
| **S20-011** | Cross-Society NOC Request Submission Blocked | PASS |
| **S20-012** | Anonymous `verify_noc_move_pass` Blocked (`42501`) | PASS |
| **S20-013** | Valid Resident Move-In NOC Request Submission | PASS |
| **S20-014** | Valid Resident Move-Out NOC Request Submission | PASS |
| **S20-015** | Move-In/Move-Out Initialization of 4 Physical Move Checklist Items | PASS |
| **S20-016** | Property Sale Initialization of 3 Administrative Checklist Items | PASS |
| **S20-017** | Duplicate Active NOC Request Blocked by Index | PASS |
| **S20-018** | Property Sale NOC Submission by Non-Owner Blocked (`42501`) | PASS |
| **S20-019** | Valid Property Sale NOC Submission by Primary Owner | PASS |
| **S20-020** | Property Sale NOC Move Pass Generation Rejected (`22000`) | PASS |
| **S20-021** | Property Sale NOC Approval Does NOT Mutate `property_owners` | PASS |
| **S20-022** | Server-Authoritative Dues Audit Execution (Dues Present -> Flagged) | PASS |
| **S20-023** | Server-Authoritative Dues Audit Execution (Zero Dues -> Cleared) | PASS |
| **S20-024** | Credit Dues Balance Calculation (Negative Dues -> Cleared) | PASS |
| **S20-025** | Dues Audit Locks Parent `properties` Row (`FOR UPDATE`) | PASS |
| **S20-026** | Financial Concurrency: Concurrent Charge Posting Observed During Approval | PASS |
| **S20-027** | Financial Concurrency: Simultaneous Approvals Serialized Safely | PASS |
| **S20-028** | Financial Concurrency: Debit Created Before Approval Aborts Approval | PASS |
| **S20-029** | Financial Concurrency: Zero Balance Approval Aborts If Dues Accrue | PASS |
| **S20-030** | Admin Departmental Checklist Item Clearance (`facility_inspection`) | PASS |
| **S20-031** | Category Checklist Update by Unauthorized Role Blocked (`42501`) | PASS |
| **S20-032** | Technician Role Clearance of Facility Inspection Item | PASS |
| **S20-033** | Treasurer Role Clearance of Financial Dues Item | PASS |
| **S20-034** | NOC Approval Blocked When Checklist Items Pending or Flagged | PASS |
| **S20-035** | Valid NOC Approval When 100% Checklist Items Cleared | PASS |
| **S20-036** | Non-Secretary / Non-Admin NOC Approval Blocked | PASS |
| **S20-037** | Admin NOC Rejection Execution | PASS |
| **S20-038** | Requester NOC Cancellation Execution | PASS |
| **S20-039** | CSPRNG 6-Digit PIN Generation & Bcrypt Salted Hash Storage | PASS |
| **S20-040** | Plaintext PIN Excluded From Database Tables & Audit Logs | PASS |
| **S20-041** | Public Lookup Pass Token (`PASS-2026-A1B2C3D4E5F6`) Generation | PASS |
| **S20-042** | Move Pass Generation Blocked for Unapproved NOC Request | PASS |
| **S20-043** | Pass Re-issuance Automatically Revokes Prior Active Pass (Option B) | PASS |
| **S20-044** | Vehicle Registration SQL Normalization Execution | PASS |
| **S20-045** | Gatekeeper Verification Supply Mismatched Vehicle Reg Blocked | PASS |
| **S20-046** | Valid Vehicle Registration Match Gatekeeper Verification | PASS |
| **S20-047** | Gatekeeper Valid Move Pass Verification Execution | PASS |
| **S20-048** | Per-Pass Lockout Defense (5 Pass Failures -> 15 Min Lockout) | PASS |
| **S20-049** | Persistent Gatekeeper Lockout (10 Failures -> 15 Min Guard Lockout) | PASS |
| **S20-050** | Generic Error (`22000`) Returned on Verification Failures | PASS |
| **S20-051** | Move Pass Replay Blocked After Status = `used` | PASS |
| **S20-052** | Expired Move Pass Verification Blocked | PASS |
| **S20-053** | Move-In Verification Activates Tenant Tenancy (`status = 'active'`) | PASS |
| **S20-054** | Move-In Verification Updates Property Occupancy (`occupancy_status = 'occupied'`) | PASS |
| **S20-055** | Move-Out Verification Terminates Tenant Tenancy (`end_date = CURRENT_DATE`) | PASS |
| **S20-056** | Owner Move-Out Verification Updates Occupancy Without Ownership Mutation | PASS |
| **S20-057** | Real-Time Expiration Rejection During Gate Verification | PASS |
| **S20-058** | Batch Process `process_expired_noc_passes()` Execution | PASS |
| **S20-059** | Delayed Scheduler Execution Does NOT Allow Expired Pass Access | PASS |
| **S20-060** | Direct `noc_requests` DML Blocked by Restrictive RLS | PASS |
| **S20-061** | Direct `noc_clearance_checklists` DML Blocked by Restrictive RLS | PASS |
| **S20-062** | Direct `noc_move_passes` DML Blocked by Restrictive RLS | PASS |
| **S20-063** | Direct `noc_gatekeeper_rate_limits` DML Blocked by Restrictive RLS | PASS |
| **S20-064** | Audit Log Created for NOC Request Submission & Approval | PASS |
| **S20-065** | Audit Log Redaction (Plaintext Passcode Excluded) | PASS |
| **S20-066** | Real-Time Notification Scoping (Requester & Admins Only) | PASS |
| **S20-067** | Notification Payloads Exclude PINs & Financial Amounts | PASS |
| **S20-068** | Financial Non-Interference (Zero Ledger Mutations) | PASS |
| **S20-069** | Cumulative Baseline Suite Target Reached (711/711 PASS) | PASS |
| **S20-070** | RPC Function ACL Hardening (PUBLIC EXECUTE Revocation) | PASS |
| **S20-071** | CSPRNG 48-Bit Pass Token Entropy Verification | PASS |
| **S20-072** | Financial Serialization Barrier Verification | PASS |

---

## 11. DETERMINISTIC ROLLBACK SPECIFICATION

1. Drop Slice 20 tables in cascade order:
   `DROP TABLE IF EXISTS public.noc_gatekeeper_rate_limits CASCADE;`
   `DROP TABLE IF EXISTS public.noc_move_passes CASCADE;`
   `DROP TABLE IF EXISTS public.noc_clearance_checklists CASCADE;`
   `DROP TABLE IF EXISTS public.noc_requests CASCADE;`
2. Drop Slice 20 RPC routines with exact signatures:
   `DROP FUNCTION IF EXISTS public.submit_noc_request(UUID, TEXT, DATE, TEXT);`
   `DROP FUNCTION IF EXISTS public.perform_financial_dues_clearance(UUID);`
   `DROP FUNCTION IF EXISTS public.update_clearance_checklist_item(UUID, TEXT, TEXT, TEXT);`
   `DROP FUNCTION IF EXISTS public.approve_noc_request(UUID);`
   `DROP FUNCTION IF EXISTS public.reject_noc_request(UUID, TEXT);`
   `DROP FUNCTION IF EXISTS public.cancel_noc_request(UUID);`
   `DROP FUNCTION IF EXISTS public.generate_noc_move_pass(UUID, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT, TEXT);`
   `DROP FUNCTION IF EXISTS public.verify_noc_move_pass(TEXT, TEXT, TEXT, TEXT);`
   `DROP FUNCTION IF EXISTS public.process_expired_noc_passes();`
3. Execute `scratch/run_all19.ps1` to verify baseline remains green at **639 / 639 PASS**.

---

## 12. FINAL VERDICT & AUTHORIZATION STATUS

```text
=====================================================

SLICE 20 REVISION 4

PLAN-ONLY / ZERO IMPLEMENTATION

IMPLEMENTATION STATUS:
NOT AUTHORIZED

DATABASE STATUS:
NO CHANGES

APPLICATION STATUS:
NO CHANGES

SLICES 1–19:
LOCKED / UNTOUCHED

LOCKED BASELINE:
639 / 639 PASS

FINANCIAL SERIALIZATION:
ARCHITECTURAL BLOCKER

FINAL SECURITY FINDINGS:
0 Critical / 0 High / 1 Medium / 0 Low / 0 Info

FINAL VERDICT:
NOT IMPLEMENTATION-READY

=====================================================

THIS DOCUMENT DOES NOT AUTHORIZE IMPLEMENTATION.

NO SLICE 20 IMPLEMENTATION MAY BEGIN.

IMPLEMENTATION REQUIRES SEPARATE, EXPLICIT USER AUTHORIZATION.

=====================================================
```
