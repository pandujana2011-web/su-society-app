# SLICE 19 — FINAL IMPLEMENTATION & SECURITY PLAN

**STATUS: PLAN-ONLY / PENDING USER APPROVAL**  
**LOCKED BASELINE: 595/595 PASS**  
**SLICES 1–18: LOCKED / IMMUTABLE**  
**SLICE 19 IMPLEMENTATION: NOT STARTED**  
**IMPLEMENTATION AUTHORIZATION: NONE**  
**DATABASE MODIFICATIONS: NONE**  
**APPLICATION MODIFICATIONS: NONE**  

---

## 1. EXECUTIVE SUMMARY & LOCKED BASELINE PROTECTION

This document presents the **Final Implementation & Security Plan for Slice 19** of the SU Society App repository (`D:\Clients Applications\SU Society App`).

Slices 1 through 18 are fully implemented, verified, regression-tested, independently audited, and security-locked. The authoritative project baseline is **595/595 PASS**.

### Absolute Baseline Protection Rules:
1. **Slices 1–18 baseline (595/595 PASS)** must remain 100% intact and unweakened.
2. All previously locked files (`database/schema_slice1.sql` through `schema_slice18.sql`, `database/verify_slice1.sql` through `verify_slice18.sql`, `scratch/run_all.ps1` through `run_all18.ps1`, `SLICE18_FINAL_LOCK_RECORD.md`) are designated **LOCKED AND IMMUTABLE**.
3. Zero implementation, zero database execution, zero application modifications, and zero file creation are authorized during this planning phase.
4. Slice 19 implementation will begin ONLY after explicit user approval of this finalized plan.

---

## 2. REPOSITORY & DATABASE CATALOG AUDIT

Read-only inspection of the active codebase and database catalog confirmed:
* **Architecture Alignment:** Slice 8 implemented basic guest visitor logging (`visitor_logs`) and Slice 18 finalized gatekeeper visitor checkout (`checkout_visitor`). Slice 19 extends gatekeeper operations to regular domestic helpers (maids, drivers, cooks, nannies) who visit daily, serve multiple properties/flats, and require passcode verification.
* **RPC Pattern Parity:** All Slice 19 RPCs will follow the project's established pattern: `SECURITY DEFINER`, fixed `SET search_path = public, pg_temp`, caller derivation from `auth.uid()`, society boundary verification via `public.get_user_society_id()`, `FOR UPDATE` row locking, server audit logging (`audit_logs`), and real-time notification dispatch (`notifications`).
* **RLS Parity:** All new tables will enforce `ALTER TABLE ... FORCE ROW LEVEL SECURITY`. RESTRICTIVE RLS policies will disallow direct client `UPDATE` and `DELETE` DML, forcing administrative and state mutations through authorized RPC functions.

---

## 3. SLICE 19 SCOPE DEFINITION

### IN SCOPE:
1. **Helper Registry (`staff_helpers`):** Helper profile management (name, mobile, photo URL, service category, ID document type, status: `active` / `inactive`, encrypted/hashed security passcode).
2. **Multi-Flat Authorization (`helper_flat_mappings`):** Association of domestic helpers with one or more flats/properties in the same society, including employer user ID, service type, schedule, and mapping status (`active` / `revoked`).
3. **Security Gate Attendance (`helper_attendance_logs`):** Gatekeeper entry check-in with passcode verification, active attendance tracking, gatekeeper exit checkout, and overstay calculation.
4. **Passcode Verification & Security:** 6-digit numeric passcode generation, server-side hashing, passcode verification RPC, and failed-attempt defense.
5. **Overstay Alerting:** Server-side calculation of active attendance exceeding configurable duration threshold (e.g. 12 hours) and overstay notification dispatch.
6. **Audit & Notifications:** Server-authoritative audit logging for all helper lifecycle and gate attendance events, and real-time attendance notifications to mapped flat residents.
7. **8 New SECURITY DEFINER RPC Routines:** `register_domestic_helper`, `update_domestic_helper`, `set_helper_status`, `authorize_helper_for_flat`, `revoke_helper_authorization`, `checkin_domestic_helper`, `checkout_domestic_helper`, `generate_helper_passcode`.

### OUT OF SCOPE (Deferred to Future Slices):
* Resident move-in / move-out digital NOC clearance requests (Slice 20).
* Society equipment asset catalog and AMC vendor contracts (Slice 21).
* Vendor procurement, purchase orders, and 3-way invoice matching (Slice 22).
* Any modification to financial ledgers, maintenance charges, or payment intent workflows.

---

## 4. SECURITY OBJECTIVES & ROLE HIERARCHY

All Slice 19 operations strictly enforce server-authoritative role boundaries:

| Operation | Admin / Management | Resident / Flat Employer | Gatekeeper | Unauthenticated / Public |
| :--- | :---: | :---: | :---: | :---: |
| `register_domestic_helper` | ✅ ALLOW | ✅ ALLOW (Own Flat) | ❌ DENIED | ❌ DENIED |
| `update_domestic_helper` | ✅ ALLOW | ✅ ALLOW (Creator) | ❌ DENIED | ❌ DENIED |
| `set_helper_status` | ✅ ALLOW | ❌ DENIED | ❌ DENIED | ❌ DENIED |
| `authorize_helper_for_flat` | ✅ ALLOW | ✅ ALLOW (Own Flat) | ❌ DENIED | ❌ DENIED |
| `revoke_helper_authorization` | ✅ ALLOW | ✅ ALLOW (Own Flat) | ❌ DENIED | ❌ DENIED |
| `checkin_domestic_helper` | ✅ ALLOW | ❌ DENIED | ✅ ALLOW | ❌ DENIED |
| `checkout_domestic_helper` | ✅ ALLOW | ❌ DENIED | ✅ ALLOW | ❌ DENIED |
| `generate_helper_passcode` | ✅ ALLOW | ✅ ALLOW (Employer) | ❌ DENIED | ❌ DENIED |

---

## 5. MULTI-TENANT SOCIETY ISOLATION DESIGN

Multi-tenancy is enforced server-side in every Slice 19 table and RPC:
1. **Helper Society Binding:** `staff_helpers.society_id` references `public.societies(id)` and cannot be NULL.
2. **Flat Authorization Scoping:** `helper_flat_mappings` validates that the target property belongs to the helper's registered society. Mapping across different societies raises `42501` ('Cross-society execution denied.').
3. **Gatekeeper Attendance Scoping:** `checkin_domestic_helper` and `checkout_domestic_helper` verify that caller's society `get_user_society_id(auth.uid())` matches `helper.society_id`. Cross-society check-in attempts fail with `42501`.
4. **Notification Scoping:** Notifications are routed exclusively to employers registered within the same society.

---

## 6. DATA MODEL DESIGN

### 6.1 `public.staff_helpers`
```sql
CREATE TABLE IF NOT EXISTS public.staff_helpers (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id          UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    full_name           VARCHAR(150) NOT NULL,
    mobile              VARCHAR(20) NOT NULL,
    service_type        VARCHAR(50) NOT NULL CONSTRAINT chk_helper_service_type CHECK (
                            service_type IN ('maid', 'driver', 'cook', 'nanny', 'car_washer', 'tutor', 'gardener', 'other')
                        ),
    id_type             VARCHAR(30) CONSTRAINT chk_helper_id_type CHECK (
                            id_type IS NULL OR id_type IN ('aadhaar', 'pan', 'passport', 'voter_id', 'driving_license', 'other')
                        ),
    photo_url           TEXT,
    passcode_hash       VARCHAR(64) NOT NULL, -- SHA-256 hash of 6-digit passcode
    status              VARCHAR(20) NOT NULL DEFAULT 'active' CONSTRAINT chk_helper_status CHECK (status IN ('active', 'inactive')),
    registered_by       UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_staff_helpers_society_status ON public.staff_helpers(society_id, status);
CREATE INDEX idx_staff_helpers_mobile ON public.staff_helpers(mobile);
```

### 6.2 `public.helper_flat_mappings`
```sql
CREATE TABLE IF NOT EXISTS public.helper_flat_mappings (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id          UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    helper_id           UUID NOT NULL REFERENCES public.staff_helpers(id) ON DELETE CASCADE,
    property_id         UUID NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
    employer_user_id    UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    status              VARCHAR(20) NOT NULL DEFAULT 'active' CONSTRAINT chk_mapping_status CHECK (status IN ('active', 'revoked')),
    start_date          DATE NOT NULL DEFAULT CURRENT_DATE,
    end_date            DATE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_helper_property_active UNIQUE (helper_id, property_id, status)
);

CREATE INDEX idx_helper_flat_mappings_helper ON public.helper_flat_mappings(helper_id);
CREATE INDEX idx_helper_flat_mappings_property ON public.helper_flat_mappings(property_id);
```

### 6.3 `public.helper_attendance_logs`
```sql
CREATE TABLE IF NOT EXISTS public.helper_attendance_logs (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id          UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    helper_id           UUID NOT NULL REFERENCES public.staff_helpers(id) ON DELETE RESTRICT,
    property_id         UUID NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
    check_in            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    check_out           TIMESTAMPTZ,
    entry_gatekeeper_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    exit_gatekeeper_id  UUID REFERENCES public.users(id) ON DELETE RESTRICT,
    status              VARCHAR(20) NOT NULL DEFAULT 'checked_in' CONSTRAINT chk_attendance_status CHECK (status IN ('checked_in', 'checked_out', 'overstayed')),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_helper_attendance_helper_status ON public.helper_attendance_logs(helper_id, status);
CREATE INDEX idx_helper_attendance_society_checkin ON public.helper_attendance_logs(society_id, check_in);
```

---

## 7. HELPER LIFECYCLE STATE MACHINE

```
   [register_domestic_helper]
              |
              v
         +----------+
         |  active  | <---- (set_helper_status) ----+
         +----------+                               |
              |                                     |
    (set_helper_status)                             |
              |                                     |
              v                                     |
        +------------+                              |
        |  inactive  | -----------------------------+
        +------------+
```

* **`active` $\rightarrow$ `inactive`:** Performed by Admin via `set_helper_status(p_helper_id, 'inactive')`. Inactive helpers cannot be authorized for flats or checked in at security gates.
* **`inactive` $\rightarrow$ `active`:** Performed by Admin via `set_helper_status(p_helper_id, 'active')`.

---

## 8. MULTI-FLAT AUTHORIZATION MODEL

1. A domestic helper may serve multiple flats in the same society (e.g. a maid working in Flat 101 and Flat 102).
2. Residents can authorize a helper for their property via `authorize_helper_for_flat(p_helper_id, p_property_id)`. The function verifies that the caller is an active owner or tenant of `p_property_id`.
3. Revocation via `revoke_helper_authorization(p_mapping_id)` updates mapping status to `revoked` and records `end_date = CURRENT_DATE`. Revoked mappings prevent future gate entries for that flat.

---

## 9. GATE ENTRY WORKFLOW (`checkin_domestic_helper`)

1. Gatekeeper calls `checkin_domestic_helper(p_helper_id UUID, p_property_id UUID, p_passcode TEXT)`.
2. Validates caller holds `gatekeeper` or `admin` role in caller's society (`42501`).
3. Locks `staff_helpers` record with `FOR UPDATE`. Verifies helper exists, belongs to caller's society, and has status `active`.
4. Verifies passcode by comparing `encode(digest(p_passcode, 'sha256'), 'hex')` with `staff_helpers.passcode_hash` (`22000` 'Invalid helper passcode.').
5. Verifies active mapping exists between `p_helper_id` and `p_property_id` in `helper_flat_mappings` (`42501` 'Helper is not authorized for target property.').
6. Checks if helper currently has an open attendance record (`check_out IS NULL`). If so, raises `22000` ('Helper is already checked in.').
7. Inserts entry in `helper_attendance_logs` (`status = 'checked_in'`, `check_in = NOW()`, `entry_gatekeeper_id = v_caller`).
8. Logs server audit event and dispatches real-time attendance notification to employer(s).

---

## 10. GATE EXIT WORKFLOW (`checkout_domestic_helper`)

1. Gatekeeper calls `checkout_domestic_helper(p_attendance_id UUID)`.
2. Validates caller holds `gatekeeper` or `admin` role in caller's society (`42501`).
3. Locks `helper_attendance_logs` row with `FOR UPDATE`.
4. Verifies record belongs to caller's society (`42501`) and `check_out IS NULL` (`22000` 'Helper is already checked out.').
5. Updates `check_out = NOW()`, `status = 'checked_out'`, `exit_gatekeeper_id = v_caller`.
6. Logs server audit event and notifies flat resident(s).

---

## 11. PASSCODE SECURITY ARCHITECTURE

1. Passcodes are 6-digit numeric strings (e.g. `'482910'`).
2. **No Plaintext Storage:** Passcodes are hashed server-side using SHA-256 (`encode(digest(p_passcode, 'sha256'), 'hex')`) before storing in `staff_helpers.passcode_hash`.
3. Passcode generation/rotation is performed via `generate_helper_passcode(p_helper_id, p_new_passcode)`.
4. Plaintext passcodes are NEVER written to `audit_logs` or `notifications`.

---

## 12. OVERSTAY DETECTION SYSTEM

1. An active attendance record (`check_out IS NULL`) is considered overstayed if `NOW() - check_in > INTERVAL '12 hours'`.
2. `checkout_domestic_helper` automatically sets `status = 'overstayed'` if `check_out - check_in > INTERVAL '12 hours'`.
3. Attendance log queries flag active entries exceeding 12 hours as overdue.

---

## 13. AUDIT LOGGING STRATEGY

Server-authoritative audit log entries are generated inside SECURITY DEFINER routines:

| Operation | Entity Type | Action | Metadata Recorded |
| :--- | :--- | :--- | :--- |
| `register_domestic_helper` | `staff_helper` | `REGISTERED helper` | Helper Name, Service Type, Mobile |
| `set_helper_status` | `staff_helper` | `UPDATED helper status` | Old Status, New Status |
| `authorize_helper_for_flat` | `helper_flat_mapping` | `AUTHORIZED helper for flat` | Helper ID, Property ID |
| `revoke_helper_authorization` | `helper_flat_mapping` | `REVOKED helper authorization` | Mapping ID, Property ID |
| `checkin_domestic_helper` | `helper_attendance_log` | `CHECKED IN domestic helper` | Helper ID, Property ID |
| `checkout_domestic_helper` | `helper_attendance_log` | `CHECKED OUT domestic helper` | Attendance ID, Duration |

Plaintext passcodes are strictly excluded from audit metadata.

---

## 14. NOTIFICATION ARCHITECTURE

Notifications are generated server-side targeting mapped flat employers:
* **Helper Gate Entry:** Type `helper_attendance`, Title `'Helper Checked In'`, Body `'[Helper Name] has entered the society for your property.'`.
* **Helper Gate Exit:** Type `helper_attendance`, Title `'Helper Checked Out'`, Body `'[Helper Name] has left the society.'`.
* Recipients are derived from trusted `helper_flat_mappings.employer_user_id` records.

---

## 15. ROW-LEVEL SECURITY (RLS) DESIGN

All Slice 19 tables enforce `FORCE ROW LEVEL SECURITY`:

```sql
ALTER TABLE public.staff_helpers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staff_helpers FORCE ROW LEVEL SECURITY;

ALTER TABLE public.helper_flat_mappings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.helper_flat_mappings FORCE ROW LEVEL SECURITY;

ALTER TABLE public.helper_attendance_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.helper_attendance_logs FORCE ROW LEVEL SECURITY;
```

### Direct DML Protection Policies:
* **SELECT Policies:** Members/Tenants can view helpers mapped to their properties. Gatekeepers and Admins can view all helpers and attendance in their society.
* **INSERT/UPDATE/DELETE Blocker Policies:** Direct client DML is blocked on `staff_helpers`, `helper_flat_mappings`, and `helper_attendance_logs` (`USING (false) WITH CHECK (false)`), requiring all mutations to execute via authorized SECURITY DEFINER RPCs.

---

## 16. SECURITY DEFINER RPC SPECIFICATIONS

1. **`register_domestic_helper(p_name TEXT, p_mobile TEXT, p_service_type TEXT, p_passcode TEXT)`**: Admin/Resident registers helper profile. Hashes passcode with SHA-256.
2. **`update_domestic_helper(p_helper_id UUID, p_name TEXT, p_mobile TEXT, p_service_type TEXT)`**: Updates helper demographics.
3. **`set_helper_status(p_helper_id UUID, p_status TEXT)`**: Admin changes helper status (`active` / `inactive`).
4. **`authorize_helper_for_flat(p_helper_id UUID, p_property_id UUID)`**: Resident/Admin links helper to flat.
5. **`revoke_helper_authorization(p_mapping_id UUID)`**: Resident/Admin revokes flat authorization.
6. **`checkin_domestic_helper(p_helper_id UUID, p_property_id UUID, p_passcode TEXT)`**: Gatekeeper logs helper entry after passcode & mapping validation.
7. **`checkout_domestic_helper(p_attendance_id UUID)`**: Gatekeeper logs helper exit with `FOR UPDATE` locking.
8. **`generate_helper_passcode(p_helper_id UUID, p_new_passcode TEXT)`**: Generates/rotates helper passcode.

---

## 17. CONCURRENCY & REPLAY ANALYSIS

* `SELECT ... FOR UPDATE` row locking is enforced in `checkin_domestic_helper` on `staff_helpers` and in `checkout_domestic_helper` on `helper_attendance_logs`.
* Unique constraint `uq_helper_property_active` prevents duplicate active flat mappings.
* Active entry check (`check_out IS NULL`) prevents concurrent double check-ins.
* Idempotency checks prevent duplicate checkouts (`22000`).

---

## 18. SECURITY FAILURE MATRIX

| Attack Vector | Expected Result | Enforcement Layer |
| :--- | :--- | :--- |
| **Cross-society helper ID** | `42501 Access Denied` | DB / RPC Society Check |
| **Cross-society property ID** | `42501 Access Denied` | DB / RPC Isolation Check |
| **Invalid passcode entry** | `22000 Invalid helper passcode` | DB / RPC SHA-256 Verification |
| **Unauthorized resident mapping** | `42501 Access Denied` | DB / RPC Ownership Verification |
| **Gatekeeper check-in inactive helper** | `22000 Helper is inactive` | DB / RPC State Guard |
| **Duplicate helper check-in** | `22000 Helper is already checked in` | DB / RPC Active Entry Guard |
| **Duplicate helper checkout** | `22000 Helper is already checked out` | DB / RPC State Guard |
| **Direct client INSERT/UPDATE DML** | `42501 Permission Denied` | RESTRICTIVE RLS Policy |
| **Plaintext passcode logging** | Prevented | SHA-256 Hashing & Redaction |

---

## 19. FINANCIAL SAFETY GATE

> **NO NEW FINANCIAL MUTATION PROPOSED FOR SLICE 19**

Slice 19 contains zero financial postings, ledger modifications, fee calculations, payment gateway interactions, or balance updates. All existing Slice 1–18 financial structures remain 100% immutable and uninfluenced.

---

## 20. VERIFICATION DESIGN & ASSERTION INVENTORY

Slice 19 verification (`database/verify_slice19.sql`) will define **32 new assertions** (`S19-001` to `S19-032`):

```text
S19-001 | 3 New Tables Exist (staff_helpers, helper_flat_mappings, helper_attendance_logs)
S19-002 | 8 New RPC Routines Exist
S19-003 | SECURITY DEFINER & fixed search_path Enforced on All 8 Routines
S19-004 | RLS & FORCE RLS Enabled on All 3 Tables
S19-005 | Anonymous register_domestic_helper Rejected (42501)
S19-006 | Anonymous checkin_domestic_helper Rejected (42501)
S19-007 | Valid Domestic Helper Registration Execution
S19-008 | Passcode Hash Verification (SHA-256)
S19-009 | Admin Status Update to Inactive
S19-010 | Inactive Helper Gate Check-In Blocked (22000)
S19-011 | Resident Authorize Helper for Flat Execution
S19-012 | Unauthorized Resident Flat Mapping Blocked (42501)
S19-013 | Revoke Flat Authorization Execution
S19-014 | Revoked Flat Helper Check-In Blocked (42501)
S19-015 | Valid Gatekeeper Helper Check-In Execution
S19-016 | Incorrect Passcode Gate Check-In Blocked (22000)
S19-017 | Duplicate Gatekeeper Helper Check-In Blocked (22000)
S19-018 | Valid Gatekeeper Helper Checkout Execution
S19-019 | Duplicate Helper Checkout Blocked (22000)
S19-020 | Overstay Duration Calculation Verification
S19-021 | Cross-Society register_domestic_helper Blocked (42501)
S19-022 | Cross-Society authorize_helper_for_flat Blocked (42501)
S19-023 | Cross-Society checkin_domestic_helper Blocked (42501)
S19-024 | Cross-Society checkout_domestic_helper Blocked (42501)
S19-025 | Direct staff_helpers DML Blocked by RLS (42501)
S19-026 | Direct helper_flat_mappings DML Blocked by RLS (42501)
S19-027 | Direct helper_attendance_logs DML Blocked by RLS (42501)
S19-028 | Audit Log Entry Created for Helper Registration
S19-029 | Audit Log Entry Created for Helper Check-In
S19-030 | Audit Log Redaction (Passcode Excluded)
S19-031 | Real-time Notification Created for Helper Check-In
S19-032 | Cumulative Suite Regression Target Reached (627/627 PASS)
```

---

## 21. REGRESSION REQUIREMENT

```text
Locked Baseline (Slices 1-18):  595 / 595 PASS
Slice 19 Assertions:             32 /  32 PASS
--------------------------------------------------
Cumulative Verification Target: 627 / 627 PASS (100%)
```

---

## 22. APPLICATION / UI INTEGRATION PLAN

* **Client SDK (`src/supabase.js`):** Additive mock client services for `staff_helpers`, `helper_flat_mappings`, and `helper_attendance_logs` to support offline development and testing.
* **UI Views (`src/App.jsx`):**
  * **Gatekeeper View:** Add 'Domestic Help Check-In / Out' tab with passcode verification modal.
  * **Member / Tenant Dashboard:** Add 'My Domestic Help' management card for flat mapping and passcode viewing.
  * **Admin Operations Manager:** Add 'Staff Helper Registry' table with activation/deactivation controls.

---

## 23. EXACT FILE CHANGE PLAN

| Artifact Path | Action | Rationale | Security Impact |
| :--- | :---: | :--- | :--- |
| `database/schema_slice19.sql` | **NEW** | Schema & 8 RPC routines | Hardened DDL & SECURITY DEFINER routines |
| `database/verify_slice19.sql` | **NEW** | 32 Verification Assertions | Automated security & workflow testing |
| `scratch/run_all19.ps1` | **NEW** | Cumulative Test Runner | Executes 627 total tests |
| `src/supabase.js` | **MODIFY** | Additive mock SDK methods | Zero impact on existing baseline methods |
| `src/App.jsx` | **MODIFY** | Additive UI components | Zero impact on existing baseline views |
| `database/schema_slice1.sql` .. `schema_slice18.sql` | **UNTOUCHED** | Locked Baseline | Preserved 100% Immutable |
| `database/verify_slice1.sql` .. `verify_slice18.sql` | **UNTOUCHED** | Locked Baseline | Preserved 100% Immutable |
| `scratch/run_all.ps1` .. `run_all18.ps1` | **UNTOUCHED** | Locked Baseline | Preserved 100% Immutable |

---

## 24. DATABASE MIGRATION STRATEGY

1. Execute `schema_slice19.sql` inside a single transactional block (`BEGIN ... COMMIT`).
2. Order of execution:
   * Tables DDL (`staff_helpers`, `helper_flat_mappings`, `helper_attendance_logs`).
   * FK constraints & Indexes.
   * `FORCE ROW LEVEL SECURITY` & Policy DDL.
   * SECURITY DEFINER RPC DDL (`register_domestic_helper` through `generate_helper_passcode`).
   * Role Privilege Grants (`GRANT EXECUTE ... TO authenticated, service_role`).
3. Execute `verify_slice19.sql` via `scratch/run_all19.ps1` to validate all 627 assertions.

---

## 25. ROLLBACK STRATEGY

If Slice 19 verification fails during execution:
1. Roll back transaction block or drop Slice 19 tables (`DROP TABLE IF EXISTS helper_attendance_logs, helper_flat_mappings, staff_helpers CASCADE`).
2. Re-run `scratch/run_all18.ps1` to verify immediate baseline restoration to **595/595 PASS**.

---

## 26. INDEPENDENT ADVERSARIAL AUDIT PLAN

Upon completion of Slice 19 implementation and verification (627/627 PASS), an independent adversarial security audit will be commissioned to audit:
* Passcode SHA-256 verification and non-plaintext exposure.
* Cross-society helper UUID and property UUID substitution attempts.
* Direct DML bypass attempts on attendance logs.
* Gatekeeper role authorization boundaries.
* Overstay duration calculation and notification scoping.

---

## 27. LOCK CRITERIA

Slice 19 will be eligible for security lock ONLY when:
1. All 32 Slice 19 assertions pass deterministically (`32/32 PASS`).
2. Baseline regression test suite passes (`595/595 PASS`).
3. Cumulative suite achieves **627/627 PASS**.
4. Independent adversarial security audit returns verdict: **A. SECURITY PASS — READY TO LOCK**.
5. SHA-256 checksums recorded in `SLICE19_FINAL_LOCK_RECORD.md`.

---

## 28. FINAL STATUS REQUIREMENT

* **Slice 19 Planning:** COMPLETE.
* **595/595 Baseline:** LOCKED / UNTOUCHED.
* **Slice 19 Implementation:** NOT STARTED.
* **Database Modifications:** NONE.
* **Application Modifications:** NONE.
* **Implementation Authorization:** NONE.

---

## 29. FINAL VERDICT

### **VERDICT: A — READY FOR USER APPROVAL**

**Implementation Authorization Status: NONE**

*(Implementation will begin only after explicit user approval of this plan.)*
