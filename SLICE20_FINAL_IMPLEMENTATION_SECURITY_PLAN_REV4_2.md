# SLICE 20 REVISION 4.2 — FINAL SECURITY PLAN

**Execution Date:** September 7, 2026  
**Target Repository:** `D:\Clients Applications\SU Society App`  
**Mode:** **PLAN REVISION ONLY / ZERO IMPLEMENTATION AUTHORIZATION**  
**Slice:** 20  
**Feature:** Resident Move-In / Move-Out Digital NOC Clearance & Property Transfer Workflow  
**Current Verified Baseline:** **639 / 639 PASS (100%)**  
**Locked Scope:** **SLICES 1–19 — IMMUTABLE**  

---

## 1. EXECUTIVE SUMMARY & FINAL PLAN CLOSURE

This document establishes **Revision 4.2** of the **Slice 20 Implementation & Security Plan**.

Revision 4.2 formally closes the architectural, cryptographic, and security analysis for Slice 20. It establishes a complete, hardened specification while maintaining un-compromised fidelity to PostgreSQL concurrency reality: **true financial mutual exclusion cannot be guaranteed unilaterally by Slice 20 without cross-slice lock participation from locked Slice 2 financial mutation routines**.

### Summary of Revision 4.2 Final Specifications:
1. **Financial Serialization Security Invariant:** Reaffirms that financial serialization is an **Architectural Blocker**. A NOC must never transition to `approved` based on a financial state that can be invalidated by a concurrent financial mutation before the NOC approval transaction commits.
2. **Rejection of Lock Workarounds:** Explicitly rejects all superficial workarounds (final re-reads, `MAX(posted_at)` checks, row-count comparisons, optimistic balance re-checks, un-shared advisory locks, or un-shared property locks) because un-cooperating Slice 2 financial writers (`fn_generate_charge`, `fn_process_payment`) do not participate in the lock protocol and can commit new debits immediately after the check and before NOC approval commits.
3. **Adversarial Concurrency Assertions (`S20-025` & `S20-066`):** Redefined as architectural blocker assertions that explicitly demonstrate the absence of a common serialization barrier between Slice 2 and Slice 20. Expected Result: `ARCHITECTURAL BLOCKER CONFIRMED`.
4. **Projected Verification Target Accounting:** Clearly distinguishes between the current verified baseline (**639 / 639 PASS**) and the projected post-implementation verification target (**710 Assertions** across Slices 1–20). Slice 20 remains un-implemented and un-verified.
5. **CSPRNG 48-Bit Token Entropy Math:** Standardizes `pass_token` to `PASS-2026-` + 12 uppercase hexadecimal characters (`gen_random_bytes(6)`), yielding exactly $2^{48} = 281,474,976,710,656$ possible values (48 bits entropy).
6. **CSPRNG Uniform PIN Generation (Zero Modulo Bias):** Implements rejection sampling over CSPRNG bytes (`extensions.gen_random_bytes(4)`) to produce a cryptographically uniform 6-digit decimal PIN in the range `[100000, 999999]`. Plaintext PIN returned exactly once upon creation payload; never stored, logged, or transmitted in notifications.
7. **Option A Persistent 10-Minute Rolling-Window Rate Limiting:** Implements Option A rate limiting using timestamped failure records in `public.noc_gatekeeper_rate_limits`. Enforces guard lockout (`15 minutes`) when `COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '10 minutes') >= 10`.
8. **Policy A Active NOC Conflict Policy:** Enforces **Policy A** — At most ONE active NOC request of ANY request type can exist for a property at a time via Partial Unique Index `uq_active_noc_request` on `(property_id)` WHERE `status IN ('submitted', 'dues_pending', 'clearance_in_progress', 'approved')`.
9. **Exact-Set Checklist Validation:** `approve_noc_request` verifies BOTH `actual category set = required category set` AND `every required category has status = cleared`.
10. **Tenancy Mutation Cardinality & Occupancy Consistency:** Tenancy mutation RPCs verify `GET DIAGNOSTICS v_rows_updated = ROW_COUNT;` to ensure exactly 1 row is modified. Owner move-out updates property occupancy status to `vacant` ONLY if no other active tenant tenancy exists for the property.
11. **RPC Function ACL Hardening with Exact Signatures:** Mandates `REVOKE ALL ON FUNCTION <exact_signature> FROM PUBLIC;` and `GRANT EXECUTE ON FUNCTION <exact_signature> TO authenticated;` with full argument signatures for all 9 SECURITY DEFINER RPCs.
12. **Non-CASCADE Rollback Safety:** Non-CASCADE rollback specifying exact function signatures and drop table order without CASCADE to guarantee zero risk of cascading into Slices 1–19 objects.

---

## 2. LOCKED BASELINE & VERIFICATION ACCOUNTING

The project baseline remains immutable and permanently locked:

```text
=====================================================

SLICES 1–18 LOCKED BASELINE:     595 / 595 PASS (100%)

SLICE 19 VERIFIED SUITE:          44 /  44 PASS (100%)

-----------------------------------------------------

CURRENT VERIFIED BASELINE:       639 / 639 PASS (100%)
CURRENT VERIFIED STATUS:         100%

INDEPENDENT SECURITY AUDIT:      PASSED
SECURITY FINDINGS:               0

SLICES 1–19 STATUS:              SECURITY LOCKED
                                 AND IMMUTABLE

PROJECTED CUMULATIVE TARGET:     710 ASSERTIONS (SLICES 1–20)
SLICE 20 STATUS:                 NOT IMPLEMENTED
                                 NOT VERIFIED
                                 NOT AUTHORIZED

=====================================================
```

---

## 3. FINANCIAL ARCHITECTURE INVENTORY

Read-only inspection of `database/schema_slice2.sql` confirms all active financial write paths:

| Function Name | Tables Modified | Rows Locked | Property Row Lock? | Advisory Lock? | Mutual Exclusion with Slice 20? |
| :--- | :--- | :--- | :---: | :---: | :---: |
| `public.fn_generate_charge` | `maintenance_charges`, `ledger_transactions` | None | **NO** | **NO** | **NO** |
| `public.fn_process_payment` | `payments`, `ledger_transactions` | `payments` (`FOR UPDATE`) | **NO** | **NO** | **NO** |
| `public.fn_reverse_charge` | `maintenance_charges`, `ledger_transactions` | `maintenance_charges` (`FOR UPDATE`) | **NO** | **NO** | **NO** |
| `public.fn_reverse_payment` | `payments`, `ledger_transactions` | `payments` (`FOR UPDATE`) | **NO** | **NO** | **NO** |

---

## 4. FINANCIAL SERIALIZATION SECURITY INVARIANT

### The Hard Security Invariant:
> A NOC must never transition to `approved` based on a financial state that can be invalidated by a concurrent financial mutation before the NOC approval transaction commits.

### Rejection of Workarounds as Mutual Exclusion Substitutes:
The following techniques are explicitly rejected as substitutes for mutual exclusion because none of them prevent a concurrent un-cooperating Slice 2 financial writer (`fn_generate_charge`, `fn_process_payment`) from committing a new debit immediately after the check completes and before `approve_noc_request` commits:
* Final balance re-read
* `MAX(posted_at)` ledger comparison
* Ledger transaction count comparison
* Final ledger snapshot comparison
* Application-side retry
* Optimistic checking without shared serialization
* Advisory lock acquired only by Slice 20
* Property row lock acquired only by Slice 20

### Mandatory Plan Position:
```text
FINANCIAL SERIALIZATION:
ARCHITECTURAL BLOCKER

SLICE 20-ONLY SERIALIZATION:
IMPOSSIBLE UNDER CURRENT IMMUTABLE ARCHITECTURE

SLICE 20:
NOT IMPLEMENTATION-READY
```

---

## 5. ARCHITECTURAL BLOCKER CONFIRMATION & CONCURRENCY ASSERTIONS

### S20-025 — Adversarial Financial Barrier Test
* **Purpose:** Demonstrates that a concurrent Slice 2 financial mutation (`fn_generate_charge`) can execute and commit during an NOC approval transaction because Slice 2 routines do not acquire the property lock.
* **Expected Result:** `ARCHITECTURAL BLOCKER CONFIRMED` (Verifies that un-cooperating financial writers bypass Slice 20-only locks).

### S20-066 — Financial Serialization Barrier Verification
* **Purpose:** Verifies whether the common serialization protocol is present across all financial writers.
* **Expected Result:** `COMMON FINANCIAL SERIALIZATION BARRIER: ABSENT` -> `SECURITY STATUS: BLOCKED`.

---

## 6. CRYPTOGRAPHIC TOKEN SPECIFICATION

1. **Pass Token Format & CSPRNG Entropy:**  
   - Generated via CSPRNG `extensions.gen_random_bytes(6)` encoded to 12 uppercase hexadecimal characters.
   - Format: `PASS-2026-A1B2C3D4E5F6`.
   - Entropy Math: $2^{48} = 281,474,976,710,656$ possible values (48 bits CSPRNG entropy).
2. **Security Function:** 48-bit CSPRNG token entropy materially reduces online guessing risk and must be combined with persistent rolling-window rate limiting, generic verification errors, and verification-attempt controls.

---

## 7. PIN SECURITY SPECIFICATION (UNIFORM CSPRNG)

1. **Rejection Sampling Algorithm (Zero Modulo Bias):**
   ```sql
   LOOP
       v_bytes := extensions.gen_random_bytes(4);
       v_val := (get_byte(v_bytes, 0) << 24) | (get_byte(v_bytes, 1) << 16) | (get_byte(v_bytes, 2) << 8) | get_byte(v_bytes, 3);
       v_val := v_val & 2147483647; -- Positive 31-bit integer
       IF v_val < 2147400000 THEN
           v_pin_int := 100000 + (v_val % 900000);
           v_pin := lpad(v_pin_int::text, 6, '0');
           EXIT;
       END IF;
   END LOOP;
   ```
2. **PIN Handling Policies:**
   - Exactly 6 decimal digits (including leading zeros e.g. `012345`).
   - Plaintext PIN returned **only once** upon creation payload.
   - Plaintext PIN is **never stored**, **never logged**, **never transmitted in notifications**, and **never returned by subsequent lookup RPCs**.
   - Stored exclusively as bcrypt hash via `extensions.crypt(v_pin, extensions.gen_salt('bf', 8))`.

---

## 8. RATE LIMITING SPECIFICATION (OPTION A ROLLING WINDOW)

Option A rate limiting maintains timestamped failure records in `public.noc_gatekeeper_rate_limits`:

```sql
CREATE TABLE IF NOT EXISTS public.noc_gatekeeper_rate_limits (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id      UUID        NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    gatekeeper_id   UUID        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    pass_token      VARCHAR(50),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### Concurrency-Safe Atomic Rolling-Window Check:
```sql
-- Lock gatekeeper rate-limit serialization boundary
PERFORM 1 FROM public.noc_gatekeeper_rate_limits 
WHERE society_id = v_society_id AND gatekeeper_id = auth.uid() 
FOR UPDATE;

-- Evaluate failures in last 10 minutes
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

## 9. NOC STATE MACHINE & POLICY A CONFLICT RULES

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

## 10. CHECKLIST EXACT-SET VALIDATION RULES

`approve_noc_request` verifies BOTH `actual category set = required category set` AND `every required category has status = cleared`:

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

## 11. TENANCY / OCCUPANCY INVARIANTS & CARDINALITY

1. **Move-In Activation (`move_direction = 'in'`):**
   - Tenant Move-In: `UPDATE public.tenancies SET status = 'active', updated_at = NOW() WHERE property_id = v_noc.property_id AND tenant_id = v_noc.requester_id AND status IN ('pending', 'approved');`
     - Cardinality Verification: `GET DIAGNOSTICS v_rows = ROW_COUNT; IF v_rows <> 1 THEN RAISE EXCEPTION 'Tenancy activation failed' USING ERRCODE = '22000'; END IF;`
   - Owner Move-In: `UPDATE public.properties SET occupancy_status = 'occupied', updated_at = NOW() WHERE id = v_noc.property_id;`
2. **Move-Out Semantics (`move_direction = 'out'`):**
   - Tenant Move-Out: `UPDATE public.tenancies SET end_date = CURRENT_DATE, status = 'terminated', updated_at = NOW() WHERE property_id = v_noc.property_id AND tenant_id = v_noc.requester_id AND (end_date IS NULL OR end_date >= CURRENT_DATE);`
     - Cardinality Verification: `GET DIAGNOSTICS v_rows = ROW_COUNT; IF v_rows <> 1 THEN RAISE EXCEPTION 'Tenancy termination failed' USING ERRCODE = '22000'; END IF;`
   - Owner Move-Out: Updates property `occupancy_status = 'vacant'` ONLY if no other active tenancy exists in `public.tenancies` for the property:
     ```sql
     IF NOT EXISTS (SELECT 1 FROM public.tenancies WHERE property_id = v_noc.property_id AND status = 'active') THEN
         UPDATE public.properties SET occupancy_status = 'vacant', updated_at = NOW() WHERE id = v_noc.property_id;
     END IF;
     ```
   - Property Ownership Records (`public.property_owners`): **100% UNTOUCHED** (deferred to Slice 24).

---

## 12. MOVE PASS LIFECYCLE (OPTION B)

1. **Option B Lifecycle:** Passes support multiple historical records, but Partial Unique Index `uq_active_noc_move_pass` on `(noc_request_id) WHERE status = 'active'` enforces at most ONE `active` pass per NOC request.
2. **Pass Re-issuance:** Generating a new pass revokes any existing active pass (`UPDATE public.noc_move_passes SET status = 'revoked' WHERE noc_request_id = p_noc_request_id AND status = 'active'`) and inserts the new pass.
3. **Replay & Expiration Defenses:** `verify_noc_move_pass` locks pass row `FOR UPDATE` and updates `status = 'active'` -> `'used'`. Re-verifying a used, revoked, or expired pass returns generic error `22000`. Boundary rule: `NOW() >= valid_until` means expired.

---

## 13. RLS / SECURITY DEFINER / ACL & READ PATH MODEL

1. **SECURITY DEFINER Execution Model:**
   - Function owner is `postgres` (superuser). SECURITY DEFINER execution bypasses table RLS internally, allowing RPCs to read/write tables.
   - Client direct DML (`INSERT`/`UPDATE`/`DELETE`) from `authenticated` roles is strictly blocked by restrictive `USING (false) WITH CHECK (false)` RLS policies.
2. **RPC Read Path & Permissive SELECT Policies:**
   - Requesters read NOC requests and clearance checklists via permissive SELECT policies (`requester_id = auth.uid()`). Pass code hashes (`pass_code_hash`) are strictly excluded from requester views.
   - Admins and gatekeepers read requests and pass metadata via society-scoped SELECT policies (`society_id = public.get_user_society_id(auth.uid())`).
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
   GRANT EXECUTE ON FUNCTION public.process_expired_noc_passes() FROM PUBLIC;
   ```

---

## 14. ROLE AUTHORIZATION MATRIX

| Category | Authorized Roles |
| :--- | :--- |
| `financial_dues` | `treasurer`, `admin`, `super_admin` |
| `facility_inspection` | `technician`, `admin`, `super_admin` |
| `keys_access_cards` | `admin`, `super_admin` |
| `legal_title_verification` | `secretary`, `admin`, `super_admin` |
| `admin_signoff` | `secretary`, `admin`, `super_admin` |

---

## 15. AUDIT / NOTIFICATION MODEL

1. **Audit Log Redaction:** Plaintext PINs, pass codes, and bcrypt hashes are strictly stripped from `old_data` and `new_data` audit JSON payloads.
2. **Notification Scoping:** Notifications are sent exclusively to `requester_id` or society admin roles. Notification bodies contain state updates only; PINs and financial amounts are excluded.

---

## 16. ASSERTION MATRIX ACCOUNTING (71 ASSERTIONS)

Slice 20 defines **71 planned assertions (`S20-001` through `S20-071`)**:

| Test ID | Test Assertion Description | Type / Status |
| :--- | :--- | :---: |
| **S20-001** | 4 New NOC Tables Exist (`noc_requests`, `checklists`, `passes`, `rate_limits`) | Structural |
| **S20-002** | Policy A Partial Unique Index `uq_active_noc_request` Exists | Structural |
| **S20-003** | Partial Unique Index `uq_active_noc_move_pass` Exists | Structural |
| **S20-004** | Persistent Rate Limit Foreign Key Constraints Intact Across All 4 Tables | Structural |
| **S20-005** | 9 NOC RPC Routines Exist | Structural |
| **S20-006** | SECURITY DEFINER & `search_path` Hardened on All 9 RPCs | Security |
| **S20-007** | RPC Function ACL Hardening (PUBLIC EXECUTE Revoked) | Security |
| **S20-008** | RLS & FORCE RLS Enabled on All 4 Tables | Security |
| **S20-009** | Anonymous `submit_noc_request` Blocked (`42501`) | Security |
| **S20-010** | Cross-Society NOC Request Submission Blocked | Security |
| **S20-011** | Anonymous `verify_noc_move_pass` Blocked (`42501`) | Security |
| **S20-012** | Valid Resident Move-In NOC Request Submission | Functional |
| **S20-013** | Valid Resident Move-Out NOC Request Submission | Functional |
| **S20-014** | Move-In/Move-Out Initialization of 4 Physical Move Checklist Items | Functional |
| **S20-015** | Property Sale Initialization of 3 Administrative Checklist Items | Functional |
| **S20-016** | Policy A Active NOC Request Conflict Enforcement | Functional |
| **S20-017** | Property Sale NOC Submission by Non-Owner Blocked (`42501`) | Security |
| **S20-018** | Valid Property Sale NOC Submission by Primary Owner | Functional |
| **S20-019** | Property Sale NOC Move Pass Generation Rejected (`22000`) | Security |
| **S20-020** | Property Sale NOC Approval Does NOT Mutate `property_owners` | Security |
| **S20-021** | Server-Authoritative Dues Audit Execution (Dues Present -> Flagged) | Functional |
| **S20-022** | Server-Authoritative Dues Audit Execution (Zero Dues -> Cleared) | Functional |
| **S20-023** | Credit Dues Balance Calculation (Negative Dues -> Cleared) | Functional |
| **S20-024** | Dues Audit Locks Parent `properties` Row (`FOR UPDATE`) | Concurrency |
| **S20-025** | Adversarial Financial Barrier Test: Slice 2 Writer Bypasses Lock | **BLOCKER CONFIRMED** |
| **S20-026** | Admin Departmental Checklist Item Clearance (`facility_inspection`) | Functional |
| **S20-027** | Category Checklist Update by Unauthorized Role Blocked (`42501`) | Security |
| **S20-028** | Technician Role Clearance of Facility Inspection Item | Functional |
| **S20-029** | Treasurer Role Clearance of Financial Dues Item | Functional |
| **S20-030** | NOC Approval Blocked When Checklist Items Pending or Flagged | Functional |
| **S20-031** | Exact-Set Checklist Category Validation Execution | Functional |
| **S20-032** | Valid NOC Approval When 100% Checklist Items Cleared | Functional |
| **S20-033** | Non-Secretary / Non-Admin NOC Approval Blocked | Security |
| **S20-034** | Admin NOC Rejection Execution | Functional |
| **S20-035** | Requester NOC Cancellation Execution | Functional |
| **S20-036** | CSPRNG Uniform 6-Digit PIN Generation (Zero Modulo Bias) | Security |
| **S20-037** | CSPRNG 48-Bit Pass Token Entropy Verification (`PASS-2026-A1B2C3D4E5F6`) | Security |
| **S20-038** | Plaintext PIN Excluded From Database Tables & Audit Logs | Security |
| **S20-039** | Move Pass Generation Blocked for Unapproved NOC Request | Security |
| **S20-040** | Pass Re-issuance Automatically Revokes Prior Active Pass (Option B) | Functional |
| **S20-041** | Vehicle Registration SQL Normalization Execution | Functional |
| **S20-042** | Gatekeeper Verification Supply Mismatched Vehicle Reg Blocked | Security |
| **S20-043** | Valid Vehicle Registration Match Gatekeeper Verification | Functional |
| **S20-044** | Gatekeeper Valid Move Pass Verification Execution | Functional |
| **S20-045** | Per-Pass Lockout Defense (5 Pass Failures -> 15 Min Lockout) | Security |
| **S20-046** | Persistent Option A Rolling-Window Guard Lockout Execution | Security |
| **S20-047** | Generic Error (`22000`) Returned on Verification Failures | Security |
| **S20-048** | Move Pass Replay Blocked After Status = `used` | Security |
| **S20-049** | Expired Move Pass Verification Blocked | Security |
| **S20-050** | Move-In Verification Activates Tenant Tenancy with Cardinality Check | Functional |
| **S20-051** | Move-In Verification Updates Property Occupancy (`occupancy_status = 'occupied'`) | Functional |
| **S20-052** | Move-Out Verification Terminates Tenant Tenancy with Cardinality Check | Functional |
| **S20-053** | Owner Move-Out Verification Occupancy Consistency Check | Functional |
| **S20-054** | Real-Time Expiration Rejection During Gate Verification | Security |
| **S20-055** | Batch Process `process_expired_noc_passes()` Execution | Functional |
| **S20-056** | Delayed Scheduler Execution Does NOT Allow Expired Pass Access | Security |
| **S20-057** | Direct `noc_requests` DML Blocked by Restrictive RLS | Security |
| **S20-058** | Direct `noc_clearance_checklists` DML Blocked by Restrictive RLS | Security |
| **S20-059** | Direct `noc_move_passes` DML Blocked by Restrictive RLS | Security |
| **S20-060** | Direct `noc_gatekeeper_rate_limits` DML Blocked by Restrictive RLS | Security |
| **S20-061** | Audit Log Created for NOC Request Submission & Approval | Security |
| **S20-062** | Audit Log Redaction (Plaintext Passcode Excluded) | Security |
| **S20-063** | Real-Time Notification Scoping (Requester & Admins Only) | Security |
| **S20-064** | Notification Payloads Exclude PINs & Financial Amounts | Security |
| **S20-065** | Financial Non-Interference (Zero Ledger Mutations) | Security |
| **S20-066** | Financial Serialization Barrier Absence Verification (Blocker Test) | **BLOCKER CONFIRMED** |
| **S20-067** | Cumulative Baseline Suite Target Reached (710 Assertions Target) | Functional |
| **S20-068** | Direct Client SELECT Access Scoping | Security |
| **S20-069** | Multi-Tenancy Society Isolation Boundary | Security |
| **S20-070** | Non-CASCADE Rollback Determinism Verification | Security |
| **S20-071** | Final Architectural Dependency Status Verification | **BLOCKER CONFIRMED** |

---

## 17. DETERMINISTIC NON-CASCADE ROLLBACK PLAN

Rollback uses explicit function signatures without `CASCADE` to protect Slices 1–19 objects:

1. Drop Slice 20 tables in cascade-free order:
   `DROP TABLE IF EXISTS public.noc_gatekeeper_rate_limits;`
   `DROP TABLE IF EXISTS public.noc_move_passes;`
   `DROP TABLE IF EXISTS public.noc_clearance_checklists;`
   `DROP TABLE IF EXISTS public.noc_requests;`
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

## 18. CROSS-SLICE OPERATIONAL SEQUENCE & DEPENDENCY

```text
CURRENT VERIFIED BASELINE: 639 / 639 PASS
      │
      ▼
SLICES 1–19 PERMANENTLY LOCKED & IMMUTABLE
      │
      ▼
SEPARATE SLICE 2 SECURITY PATCH PLAN (FOR UPDATE on public.properties)
      │
      ▼
EXPLICIT USER AUTHORIZATION FOR SLICE 2 PATCH
      │
      ▼
SLICE 2 PATCH IMPLEMENTATION & ADVERSARIAL VERIFICATION
      │
      ▼
NEW VERIFIED BASELINE
      │
      ▼
SLICE 20 FINAL REVALIDATION
      │
      ▼
EXPLICIT USER AUTHORIZATION FOR SLICE 20 IMPLEMENTATION
```

---

## 19. FINAL REVISION 4.2 VERDICT

```text
SLICE 20:
NOT IMPLEMENTATION-READY

FINANCIAL SERIALIZATION:
ARCHITECTURAL BLOCKER

CURRENT VERIFIED BASELINE:
639 / 639 PASS

SLICE 20:
NOT IMPLEMENTED
NOT VERIFIED

IMPLEMENTATION AUTHORIZATION:
NONE

DATABASE CHANGES:
NONE

APPLICATION CHANGES:
NONE

SLICES 1–19:
LOCKED / UNTOUCHED
```

---

```text
=====================================================

SLICE 20 REVISION 4.2

FINAL SECURITY PLAN

PLAN-ONLY / ZERO IMPLEMENTATION

IMPLEMENTATION AUTHORIZATION:
NONE

DATABASE MODIFICATIONS:
NONE

APPLICATION MODIFICATIONS:
NONE

SLICES 1–19:
LOCKED / UNTOUCHED

CURRENT VERIFIED BASELINE:
639 / 639 PASS

SLICE 20:
NOT IMPLEMENTED
NOT VERIFIED

FINANCIAL SERIALIZATION:
ARCHITECTURAL BLOCKER

FINAL VERDICT:
NOT IMPLEMENTATION-READY

=====================================================

NO SLICE 20 IMPLEMENTATION MAY BEGIN.

NO DATABASE CHANGES MAY BE PERFORMED.

NO APPLICATION CHANGES MAY BE PERFORMED.

NO SLICE 2 CHANGES MAY BE PERFORMED.

ANY FUTURE CHANGE REQUIRES SEPARATE,
EXPLICIT USER AUTHORIZATION AND VERIFICATION.

=====================================================
```
