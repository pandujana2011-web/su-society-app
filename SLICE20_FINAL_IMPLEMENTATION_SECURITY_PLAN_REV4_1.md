# SLICE 20 REVISION 4.1 — FINAL SECURITY PLAN

**Execution Date:** September 7, 2026  
**Target Repository:** `D:\Clients Applications\SU Society App`  
**Mode:** **PLAN REVISION ONLY / ZERO IMPLEMENTATION AUTHORIZATION**  
**Slice:** 20  
**Feature:** Resident Move-In / Move-Out Digital NOC Clearance & Property Transfer Workflow  
**Current Locked Baseline:** **639 / 639 PASS (100%)**  
**Locked Scope:** **SLICES 1–19 — IMMUTABLE**  

---

## 1. EXECUTIVE SUMMARY & REVISION 4.1 VERDICT

This document establishes **Revision 4.1** of the **Slice 20 Implementation & Security Plan**.

Revision 4.1 completes the final security hardening, cryptographic refinement, and concurrency analysis for Slice 20 while maintaining strict fidelity to technical reality: **true financial mutual exclusion cannot be guaranteed unilaterally by Slice 20 without cross-slice lock participation from locked Slice 2 financial mutation routines**.

### Summary of Revision 4.1 Hardened Specifications:
1. **Financial Serialization Invariant & Blocker:** Reaffirms that financial serialization is an **Architectural Blocker**. Rejecting all superficial workarounds (such as final re-reads or transaction snapshot checks), it establishes that Slice 20 alone cannot prevent concurrent un-cooperating Slice 2 financial writers (`fn_generate_charge`, `fn_process_payment`) from committing dues during NOC approval. Implementation remains **NOT IMPLEMENTATION-READY** until cross-slice lock participation is authorized.
2. **Redefined Concurrency Assertions (`S20-026` & `S20-072`):** Redefines `S20-026` and `S20-072` as adversarial architectural tests that explicitly demonstrate the absence of a common serialization barrier between Slice 2 and Slice 20.
3. **CSPRNG Uniform PIN Generation (Zero Modulo Bias):** Replaces modulo reduction with rejection sampling over CSPRNG bytes (`extensions.gen_random_bytes(4)`) to produce a cryptographically uniform 6-digit decimal PIN in the range `[100000, 999999]`. Plaintext PIN returned exactly once upon creation payload; never stored, logged, or transmitted in notifications.
4. **CSPRNG 48-Bit Token Entropy:** Standardizes `pass_token` to `PASS-2026-` + 12 uppercase hexadecimal characters (`gen_random_bytes(6)`), yielding exactly $2^{48} = 281,474,976,710,656$ possible values (48 bits entropy).
5. **Option A Persistent 10-Minute Rolling-Window Rate Limiting:** Formulates Option A rate limiting using timestamped failure records in `public.noc_gatekeeper_rate_limits`. Enforces guard lockout (`15 minutes`) when `COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '10 minutes') >= 10`.
6. **Policy A Active NOC Conflict Policy:** Enforces **Policy A** — At most ONE active NOC request of ANY request type can exist for a property at a time via Partial Unique Index `uq_active_noc_request` on `(property_id)` WHERE `status IN ('submitted', 'dues_pending', 'clearance_in_progress', 'approved')`.
7. **Exact-Set Checklist Validation:** `approve_noc_request` verifies that the set of cleared checklist categories EXACTLY MATCHES the required category set for the request type before issuing NOC clearance.
8. **Cardinality Verification & Occupancy Consistency:** Tenancy mutation RPCs verify `GET DIAGNOSTICS v_rows_updated = ROW_COUNT;` to ensure exactly 1 row is modified. Owner move-out updates property occupancy status to `vacant` ONLY if no other active tenant tenancy exists for the property.
9. **RPC Function ACL Hardening with Exact Signatures:** Mandates `REVOKE ALL ON FUNCTION <signature> FROM PUBLIC;` and `GRANT EXECUTE ON FUNCTION <signature> TO authenticated;` with full argument signatures for all 9 SECURITY DEFINER RPCs.
10. **Removed Redundant Index:** Omits redundant `CREATE UNIQUE INDEX idx_noc_move_passes_token` (since `pass_token UNIQUE` inline column constraint automatically creates a unique index in PostgreSQL).
11. **71 Assertions (`S20-001` to `S20-071`):** Recalculated assertion count targeting a cumulative suite of **710 / 710 PASS Target**.

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

## 3. ARCHITECTURE INVENTORY — FINANCIAL WRITE PATHS

Read-only inspection of `database/schema_slice2.sql` confirms all active financial write paths:

| Function Name | Tables Modified | Rows Locked | Property Row Lock? | Advisory Lock? | Mutual Exclusion with Slice 20? |
| :--- | :--- | :--- | :---: | :---: | :---: |
| `public.fn_generate_charge` | `maintenance_charges`, `ledger_transactions` | None | **NO** | **NO** | **NO** |
| `public.fn_process_payment` | `payments`, `ledger_transactions` | `payments` (`FOR UPDATE`) | **NO** | **NO** | **NO** |
| `public.fn_reverse_charge` | `maintenance_charges`, `ledger_transactions` | `maintenance_charges` (`FOR UPDATE`) | **NO** | **NO** | **NO** |
| `public.fn_reverse_payment` | `payments`, `ledger_transactions` | `payments` (`FOR UPDATE`) | **NO** | **NO** | **NO** |

---

## 4. FINANCIAL SERIALIZATION ANALYSIS & ARCHITECTURAL BLOCKER STATEMENT

### The Hard Security Invariant:
> A NOC must never transition to `approved` based on a financial state that can be invalidated by a concurrent financial mutation before the NOC approval transaction commits.

### Technical Analysis of Proposed Workarounds:
1. **Final Balance Re-Read / `MAX(posted_at)` Check:**  
   In PostgreSQL Read Committed transaction isolation, executing a final balance query inside `approve_noc_request` DOES NOT prevent a concurrent transaction (`fn_generate_charge`) from committing a new debit immediately after the re-read check completes but before `approve_noc_request` commits. The TOCTOU race condition remains.
2. **Advisory Locking / Property Row Locking inside Slice 20 alone:**  
   Because Slice 2 financial routines do not participate in `FOR UPDATE` locking on `public.properties` nor acquire the advisory lock, PostgreSQL will NOT block Slice 2 financial routines when Slice 20 holds its lock.

### Mandatory Plan Position:
```text
FINANCIAL SERIALIZATION = ARCHITECTURAL BLOCKER
SLICE 20-ONLY SERIALIZATION = IMPOSSIBLE UNDER IMMUTABLE SLICES 1–19
IMPLEMENTATION = BLOCKED
```

### Future Cross-Slice Remediation Requirement:
To achieve 100% true financial mutual exclusion, a future authorized patch to Slice 2 financial mutation routines must add property row locking at the start of financial writes:
```sql
-- Future authorized patch required inside Slice 2 financial mutation routines:
PERFORM 1 FROM public.properties WHERE id = p_property_id FOR UPDATE;
```
Until cross-slice lock participation is authorized in Slice 2, Slice 20 implementation remains **BLOCKED**.

---

## 5. RE-DEFINED FINANCIAL CONCURRENCY ASSERTIONS

### S20-026 — Adversarial Financial Serialization Barrier Test
* **Redefined Purpose:** Demonstrates that a concurrent Slice 2 financial mutation (`fn_generate_charge`) can execute and commit during an NOC approval transaction because Slice 2 routines do not acquire the property lock.
* **Expected Result:** Confirms the absence of a common financial serialization barrier between Slice 2 and Slice 20, documenting the architectural blocker.

### S20-071 — Financial Serialization Barrier Verification
* **Redefined Purpose:** Verifies whether the common serialization protocol is present across all financial writers.
* **Expected Result:** `COMMON FINANCIAL SERIALIZATION BARRIER: ABSENT` -> `SECURITY STATUS: BLOCKED`.

---

## 6. CRYPTOGRAPHIC TOKEN & UNIFORM PIN SPECIFICATIONS

### 1. CSPRNG 48-Bit Token Entropy:
- Format: `PASS-2026-` + 12 uppercase hexadecimal characters (`gen_random_bytes(6)`). Example: `PASS-2026-A1B2C3D4E5F6`.
- Entropy Math: $16^{12} = 2^{48} = 281,474,976,710,656$ possible values (48 bits entropy).
- Combined with persistent rate limiting and generic verification errors, this materially eliminates online token guessing and enumeration risks.

### 2. CSPRNG Uniform PIN Generation (Zero Modulo Bias):
- Rejection Sampling Algorithm in SQL:
  ```sql
  LOOP
      v_bytes := extensions.gen_random_bytes(4);
      v_val := (get_byte(v_bytes, 0) << 24) | (get_byte(v_bytes, 1) << 16) | (get_byte(v_bytes, 2) << 8) | get_byte(v_bytes, 3);
      v_val := v_val & 2147483647; -- Positive 31-bit integer
      -- Reject values outside upper multiple of 900,000 to ensure perfect uniform distribution
      IF v_val < 2147400000 THEN
          v_pin_int := 100000 + (v_val % 900000);
          v_pin := lpad(v_pin_int::text, 6, '0');
          EXIT;
      END IF;
  END LOOP;
  ```
- Plaintext PIN is exposed **only once** in creation RPC response. Stored exclusively as bcrypt hash (`extensions.crypt(v_pin, extensions.gen_salt('bf', 8))`). Never logged or transmitted in push notifications.

---

## 7. RATE LIMITING SPECIFICATION (OPTION A — ROLLING WINDOW)

Rate limiting is implemented using **Option A — 10-Minute Rolling-Window Rate Limiting** with persistent timestamped failure events in `public.noc_gatekeeper_rate_limits`:

```sql
CREATE TABLE IF NOT EXISTS public.noc_gatekeeper_rate_limits (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id      UUID        NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    gatekeeper_id   UUID        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    pass_token      VARCHAR(50),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### Rolling-Window Evaluation in `verify_noc_move_pass`:
```sql
-- Count failures for this gatekeeper in the last 10 minutes
SELECT COUNT(*) INTO v_recent_failures 
FROM public.noc_gatekeeper_rate_limits 
WHERE society_id = v_society_id 
  AND gatekeeper_id = auth.uid() 
  AND created_at >= NOW() - INTERVAL '10 minutes';

IF v_recent_failures >= 10 THEN
    RAISE EXCEPTION 'Gatekeeper verification locked out due to excessive failed attempts.' USING ERRCODE = '22000';
END IF;
```

---

## 8. NOC STATE MACHINE & POLICY A CONFLICT RULES

### Policy A — Single Active NOC Policy:
At most ONE active NOC request of ANY request type (`move_in`, `move_out`, `property_sale_noc`) can exist for a property at a time.
* **DB Enforcement:** Partial Unique Index `uq_active_noc_request` on `(property_id)` WHERE `status IN ('submitted', 'dues_pending', 'clearance_in_progress', 'approved')`.

### Complete State Machine Transitions:
| Current State | Next State | Authorized Actor | Preconditions & Validation | DB Enforcement | Audit Event |
| :--- | :--- | :--- | :--- | :--- | :--- |
| *None* | `submitted` | Resident (Owner/Tenant) | Requester authorized for property; `property_sale_noc` requires primary owner; Policy A unique check. | Partial Unique Index `uq_active_noc_request` | `noc_request_submitted` |
| `submitted` | `dues_pending` | Treasurer / System RPC | Dues audit executed; net ledger balance > 0. | RPC `perform_financial_dues_clearance` | `noc_dues_audit_flagged` |
| `submitted` / `dues_pending` | `clearance_in_progress` | Department Roles | Net ledger balance <= 0; checklist items open. | RPC state check | `noc_clearance_started` |
| `clearance_in_progress` | `approved` | Secretary / Admin | Dues balance <= 0; exact required checklist category set cleared. | Atomic RPC transaction with `FOR UPDATE` | `noc_request_approved` |
| `submitted` / `dues_pending` / `clearance_in_progress` | `rejected` | Admin / Secretary | Dues unpaid or facility inspection failed; rejection reason provided. | RPC `reject_noc_request` | `noc_request_rejected` |
| `submitted` / `dues_pending` / `clearance_in_progress` | `cancelled` | Requester Resident | Request in non-final state; `auth.uid() = requester_id`. | Requester identity match | `noc_request_cancelled` |
| `approved` | `completed` | Gatekeeper (Guard) | Move pass validated at gate; mover truck check-in/out timestamped. | RPC `verify_noc_move_pass` | `noc_move_completed` |
| `approved` | `expired` | System RPC / Real-Time | `NOW() >= valid_until`. | Real-time gate check & batch RPC | `noc_request_expired` |

---

## 9. CHECKLIST EXACT-SET VALIDATION RULES

`approve_noc_request` verifies that the set of cleared checklist categories EXACTLY MATCHES the required category set for the request type:

```sql
-- Verify exact checklist category set
SELECT ARRAY_AGG(clearance_category ORDER BY clearance_category) INTO v_actual_categories
FROM public.noc_clearance_checklists
WHERE noc_request_id = p_noc_request_id AND status = 'cleared';

IF v_noc.request_type IN ('move_in', 'move_out') THEN
    v_required_categories := ARRAY['admin_signoff', 'facility_inspection', 'financial_dues', 'keys_access_cards'];
ELSIF v_noc.request_type = 'property_sale_noc' THEN
    v_required_categories := ARRAY['admin_signoff', 'financial_dues', 'legal_title_verification'];
END IF;

IF v_actual_categories IS DISTINCT FROM v_required_categories THEN
    RAISE EXCEPTION 'NOC Approval Denied: Checklist categories do not match required set.' USING ERRCODE = '22000';
END IF;
```

---

## 10. TENANCY & OCCUPANCY MUTATION RULES

1. **Move-In Activation (`move_direction = 'in'`):**
   - Tenant Move-In: `UPDATE public.tenancies SET status = 'active', updated_at = NOW() WHERE property_id = v_noc.property_id AND tenant_id = v_noc.requester_id AND status IN ('pending', 'approved');`
     - Cardinality Check: `GET DIAGNOSTICS v_rows = ROW_COUNT; IF v_rows <> 1 THEN RAISE EXCEPTION 'Tenancy activation failed' USING ERRCODE = '22000'; END IF;`
   - Owner Move-In: `UPDATE public.properties SET occupancy_status = 'occupied', updated_at = NOW() WHERE id = v_noc.property_id;`
2. **Move-Out Semantics (`move_direction = 'out'`):**
   - Tenant Move-Out: `UPDATE public.tenancies SET end_date = CURRENT_DATE, status = 'terminated', updated_at = NOW() WHERE property_id = v_noc.property_id AND tenant_id = v_noc.requester_id AND (end_date IS NULL OR end_date >= CURRENT_DATE);`
     - Cardinality Check: `GET DIAGNOSTICS v_rows = ROW_COUNT; IF v_rows <> 1 THEN RAISE EXCEPTION 'Tenancy termination failed' USING ERRCODE = '22000'; END IF;`
   - Owner Move-Out: Updates property `occupancy_status = 'vacant'` ONLY if no other active tenancy exists in `public.tenancies` for the property:
     ```sql
     IF NOT EXISTS (SELECT 1 FROM public.tenancies WHERE property_id = v_noc.property_id AND status = 'active') THEN
         UPDATE public.properties SET occupancy_status = 'vacant', updated_at = NOW() WHERE id = v_noc.property_id;
     END IF;
     ```
   - Property Ownership Records (`public.property_owners`): **100% UNTOUCHED** (deferred to Slice 24).

---

## 11. MOVE PASS LIFECYCLE (OPTION B)

1. **Option B Lifecycle:** Passes support multiple historical records, but Partial Unique Index `uq_active_noc_move_pass` on `(noc_request_id) WHERE status = 'active'` enforces at most ONE `active` pass per NOC request.
2. **Pass Re-issuance:** Generating a new pass revokes any existing active pass (`UPDATE public.noc_move_passes SET status = 'revoked' WHERE noc_request_id = p_noc_request_id AND status = 'active'`) and inserts the new pass.
3. **Replay Defense:** `verify_noc_move_pass` locks pass row `FOR UPDATE` and updates `status = 'active'` -> `'used'`. Re-verifying a used pass returns error `22000`.

---

## 12. RLS / SECURITY DEFINER / ACL MODEL

1. **Table RLS & FORCE RLS:** All 4 tables (`noc_requests`, `noc_clearance_checklists`, `noc_move_passes`, `noc_gatekeeper_rate_limits`) enforce `ENABLE` and `FORCE ROW LEVEL SECURITY` with restrictive DML policies (`USING (false) WITH CHECK (false)`).
2. **Permissive SELECT Policies:**
   - `noc_requests`: Requesters can view their own requests (`requester_id = auth.uid()`); society admin roles can view requests within their society.
   - `noc_clearance_checklists`: Visible to requesters and society admin roles.
   - `noc_move_passes`: Requesters can view pass metadata (excluding `pass_code_hash`); gatekeepers and admins can view pass metadata.
3. **RPC Function ACL Hardening (Exact Signatures):**
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

## 13. ROLE AUTHORIZATION MATRIX

| Category | Authorized Roles |
| :--- | :--- |
| `financial_dues` | `treasurer`, `admin`, `super_admin` |
| `facility_inspection` | `technician`, `admin`, `super_admin` |
| `keys_access_cards` | `admin`, `super_admin` |
| `legal_title_verification` | `secretary`, `admin`, `super_admin` |
| `admin_signoff` | `secretary`, `admin`, `super_admin` |

---

## 14. AUDIT / NOTIFICATION MODEL

1. **Audit Log Redaction:** Plaintext PINs, pass codes, and bcrypt hashes are strictly stripped from `old_data` and `new_data` audit JSON payloads.
2. **Notification Scoping:** Notifications are sent exclusively to `requester_id` or society admin roles. Notification bodies contain state updates only; PINs and financial amounts are excluded.

---

## 15. RECALCULATED ASSERTION MATRIX (71 ASSERTIONS)

Slice 20 Revision 4.1 defines **71 detailed test assertions (`S20-001` through `S20-071`)**:

| Test ID | Test Assertion Description | Planned Outcome |
| :--- | :--- | :---: |
| **S20-001** | 4 New NOC Tables Exist (`noc_requests`, `checklists`, `passes`, `rate_limits`) | PASS |
| **S20-002** | Policy A Partial Unique Index `uq_active_noc_request` Exists | PASS |
| **S20-003** | Partial Unique Index `uq_active_noc_move_pass` Exists | PASS |
| **S20-004** | Persistent Rate Limit Foreign Key Constraints Intact Across All 4 Tables | PASS |
| **S20-005** | 9 NOC RPC Routines Exist | PASS |
| **S20-006** | SECURITY DEFINER & `search_path` Hardened on All 9 RPCs | PASS |
| **S20-007** | RPC Function ACL Hardening (PUBLIC EXECUTE Revoked) | PASS |
| **S20-008** | RLS & FORCE RLS Enabled on All 4 Tables | PASS |
| **S20-009** | Anonymous `submit_noc_request` Blocked (`42501`) | PASS |
| **S20-010** | Cross-Society NOC Request Submission Blocked | PASS |
| **S20-011** | Anonymous `verify_noc_move_pass` Blocked (`42501`) | PASS |
| **S20-012** | Valid Resident Move-In NOC Request Submission | PASS |
| **S20-013** | Valid Resident Move-Out NOC Request Submission | PASS |
| **S20-014** | Move-In/Move-Out Initialization of 4 Physical Move Checklist Items | PASS |
| **S20-015** | Property Sale Initialization of 3 Administrative Checklist Items | PASS |
| **S20-016** | Policy A Active NOC Request Conflict Enforcement | PASS |
| **S20-017** | Property Sale NOC Submission by Non-Owner Blocked (`42501`) | PASS |
| **S20-018** | Valid Property Sale NOC Submission by Primary Owner | PASS |
| **S20-019** | Property Sale NOC Move Pass Generation Rejected (`22000`) | PASS |
| **S20-020** | Property Sale NOC Approval Does NOT Mutate `property_owners` | PASS |
| **S20-021** | Server-Authoritative Dues Audit Execution (Dues Present -> Flagged) | PASS |
| **S20-022** | Server-Authoritative Dues Audit Execution (Zero Dues -> Cleared) | PASS |
| **S20-023** | Credit Dues Balance Calculation (Negative Dues -> Cleared) | PASS |
| **S20-024** | Dues Audit Locks Parent `properties` Row (`FOR UPDATE`) | PASS |
| **S20-025** | Adversarial Financial Barrier Test: Slice 2 Writer Bypasses Slice 20 Lock | PASS |
| **S20-026** | Admin Departmental Checklist Item Clearance (`facility_inspection`) | PASS |
| **S20-027** | Category Checklist Update by Unauthorized Role Blocked (`42501`) | PASS |
| **S20-028** | Technician Role Clearance of Facility Inspection Item | PASS |
| **S20-029** | Treasurer Role Clearance of Financial Dues Item | PASS |
| **S20-030** | NOC Approval Blocked When Checklist Items Pending or Flagged | PASS |
| **S20-031** | Exact-Set Checklist Category Validation Execution | PASS |
| **S20-032** | Valid NOC Approval When 100% Checklist Items Cleared | PASS |
| **S20-033** | Non-Secretary / Non-Admin NOC Approval Blocked | PASS |
| **S20-034** | Admin NOC Rejection Execution | PASS |
| **S20-035** | Requester NOC Cancellation Execution | PASS |
| **S20-036** | CSPRNG Uniform 6-Digit PIN Generation (Zero Modulo Bias) | PASS |
| **S20-037** | CSPRNG 48-Bit Pass Token Entropy Verification (`PASS-2026-A1B2C3D4E5F6`) | PASS |
| **S20-038** | Plaintext PIN Excluded From Database Tables & Audit Logs | PASS |
| **S20-039** | Move Pass Generation Blocked for Unapproved NOC Request | PASS |
| **S20-040** | Pass Re-issuance Automatically Revokes Prior Active Pass (Option B) | PASS |
| **S20-041** | Vehicle Registration SQL Normalization Execution | PASS |
| **S20-042** | Gatekeeper Verification Supply Mismatched Vehicle Reg Blocked | PASS |
| **S20-043** | Valid Vehicle Registration Match Gatekeeper Verification | PASS |
| **S20-044** | Gatekeeper Valid Move Pass Verification Execution | PASS |
| **S20-045** | Per-Pass Lockout Defense (5 Pass Failures -> 15 Min Lockout) | PASS |
| **S20-046** | Persistent Option A Rolling-Window Guard Lockout Execution | PASS |
| **S20-047** | Generic Error (`22000`) Returned on Verification Failures | PASS |
| **S20-048** | Move Pass Replay Blocked After Status = `used` | PASS |
| **S20-049** | Expired Move Pass Verification Blocked | PASS |
| **S20-050** | Move-In Verification Activates Tenant Tenancy with Cardinality Check | PASS |
| **S20-051** | Move-In Verification Updates Property Occupancy (`occupancy_status = 'occupied'`) | PASS |
| **S20-052** | Move-Out Verification Terminates Tenant Tenancy with Cardinality Check | PASS |
| **S20-053** | Owner Move-Out Verification Occupancy Consistency Check | PASS |
| **S20-054** | Real-Time Expiration Rejection During Gate Verification | PASS |
| **S20-055** | Batch Process `process_expired_noc_passes()` Execution | PASS |
| **S20-056** | Delayed Scheduler Execution Does NOT Allow Expired Pass Access | PASS |
| **S20-057** | Direct `noc_requests` DML Blocked by Restrictive RLS | PASS |
| **S20-058** | Direct `noc_clearance_checklists` DML Blocked by Restrictive RLS | PASS |
| **S20-059** | Direct `noc_move_passes` DML Blocked by Restrictive RLS | PASS |
| **S20-060** | Direct `noc_gatekeeper_rate_limits` DML Blocked by Restrictive RLS | PASS |
| **S20-061** | Audit Log Created for NOC Request Submission & Approval | PASS |
| **S20-062** | Audit Log Redaction (Plaintext Passcode Excluded) | PASS |
| **S20-063** | Real-Time Notification Scoping (Requester & Admins Only) | PASS |
| **S20-064** | Notification Payloads Exclude PINs & Financial Amounts | PASS |
| **S20-065** | Financial Non-Interference (Zero Ledger Mutations) | PASS |
| **S20-066** | Financial Serialization Barrier Absence Verification (Blocker Test) | PASS |
| **S20-067** | Cumulative Baseline Suite Target Reached (710/710 PASS Target) | PASS |
| **S20-068** | Direct Client SELECT Access Scoping | PASS |
| **S20-069** | Multi-Tenancy Society Isolation Boundary | PASS |
| **S20-070** | Rollback Determinism Verification | PASS |
| **S20-071** | Final Architectural Dependency Status Verification | PASS |

---

## 16. DETERMINISTIC ROLLBACK PLAN

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
3. Execute `scratch/run_all19.ps1` to confirm baseline regression remains green at **639 / 639 PASS**.

---

## 17. REMAINING ARCHITECTURAL DEPENDENCIES

Implementation of Slice 20 requires a prior or simultaneous explicit user authorization for a minor patch to Slice 2 financial mutation routines (`fn_generate_charge`, `fn_process_payment`, `fn_reverse_charge`, `fn_reverse_payment`) to acquire `PERFORM 1 FROM public.properties WHERE id = p_property_id FOR UPDATE;` at the start of financial write transactions.

---

## 18. FINAL REVISION 4.1 VERDICT

```text
SLICE 20:
NOT IMPLEMENTATION-READY

REASON:
TRUE FINANCIAL SERIALIZATION REQUIRES CROSS-SLICE
LOCK PARTICIPATION FROM IMMUTABLE SLICE 2 WRITERS.

IMPLEMENTATION:
NOT AUTHORIZED

DATABASE:
NO CHANGES

APPLICATION:
NO CHANGES

SLICES 1–19:
LOCKED / UNTOUCHED

BASELINE:
639 / 639 PASS
```

---

```text
=====================================================

SLICE 20 REVISION 4.1

PLAN-ONLY / ZERO IMPLEMENTATION

IMPLEMENTATION AUTHORIZATION:
NONE

DATABASE MODIFICATIONS:
NONE

APPLICATION MODIFICATIONS:
NONE

SLICES 1–19:
LOCKED / UNTOUCHED

LOCKED BASELINE:
639 / 639 PASS

FINANCIAL SERIALIZATION:
ARCHITECTURAL BLOCKER

FINAL VERDICT:
NOT IMPLEMENTATION-READY

=====================================================

NO SLICE 20 IMPLEMENTATION MAY BEGIN.

NO DATABASE CHANGES MAY BE PERFORMED.

NO APPLICATION CHANGES MAY BE PERFORMED.

ANY FUTURE IMPLEMENTATION REQUIRES SEPARATE,
EXPLICIT USER AUTHORIZATION.

=====================================================
```
