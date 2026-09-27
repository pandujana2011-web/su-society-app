# SLICE 19 — CONTROLLED FINAL IMPLEMENTATION & SECURITY PLAN (REVISION 2)

**STATUS: PLAN REVISION ONLY / PENDING USER APPROVAL**  
**LOCKED BASELINE: 595/595 PASS**  
**SLICES 1–18: LOCKED / IMMUTABLE**  
**SLICE 19 IMPLEMENTATION: NOT STARTED**  
**IMPLEMENTATION AUTHORIZATION: NONE**  
**DATABASE MODIFICATIONS: NONE**  
**APPLICATION MODIFICATIONS: NONE**  

---

## 1. EXECUTIVE SUMMARY & LOCKED BASELINE PROTECTION

This document presents the **Controlled Final Implementation & Security Plan Revision 2** for Slice 19 of the SU Society App repository (`D:\Clients Applications\SU Society App`).

Slices 1 through 18 are fully implemented, verified, regression-tested, independently audited, and security-locked. The authoritative project baseline is **595/595 PASS**.

### Mandatory Baseline Rules:
1. **Slices 1–18 baseline (595/595 PASS)** remains 100% intact, immutable, and unweakened.
2. All previously locked baseline artifacts (`database/schema_slice1.sql` through `schema_slice18.sql`, `database/verify_slice1.sql` through `verify_slice18.sql`, `scratch/run_all.ps1` through `run_all18.ps1`, `SLICE18_FINAL_LOCK_RECORD.md`) are designated **LOCKED AND IMMUTABLE**.
3. Zero code, zero database execution, zero application modifications, and zero migration tasks are performed during this plan revision.
4. Slice 19 implementation will begin ONLY after explicit user authorization following review of this revised plan.

---

## 2. RECONCILIATION & KEY SECURITY REVISIONS (REV 2)

This Revision 2 resolves all security gaps and architectural contradictions from the initial plan:

1. **Passcode Hashing Architecture (Salted & Slow KDF):** Replaced bare SHA-256 with PostgreSQL `pgcrypto` `crypt(p_passcode, gen_salt('bf', 8))` (bcrypt with cost factor 8) or per-helper random 16-byte salt (`encode(gen_random_bytes(16), 'hex')`) + SHA-512. Bare SHA-256 for 6-digit numeric secrets is strictly prohibited to prevent offline dictionary/rainbow table brute-force enumeration.
2. **Atomic Passcode Verification (Oracle Elimination):** Disallowed any standalone client-callable `verify_passcode` RPC. Passcode verification occurs **atomically inside `checkin_domestic_helper`**. Authorization checks (caller society, gatekeeper role, helper status, active mapping, lockout status) are performed BEFORE passcode evaluation. Rejection messages are strictly generic (`22000` 'Invalid helper passcode.').
3. **One-Time Passcode Presentation (No Passcode Viewing):** Removed all concepts of "passcode viewing" or retrievable PIN storage. `generate_helper_passcode` generates a cryptographically random 6-digit PIN, updates the verifier hash, and returns the plaintext PIN **EXACTLY ONCE** in the function return payload. The plaintext PIN is never stored in client-readable tables, audit logs, notifications, or server logs.
4. **Failed-Attempt Defense & Temporary Lockout:** Introduced concrete rate-limiting columns (`failed_passcode_attempts INT DEFAULT 0`, `lockout_until TIMESTAMPTZ`). 5 consecutive failed passcode attempts trigger a 15-minute temporary lockout (`lockout_until = NOW() + INTERVAL '15 minutes'`). Check-in attempts during lockout fail immediately with `22000` ('Account temporarily locked due to excessive failed attempts.'). Successful check-in resets failed attempts to zero.
5. **Database-Level Attendance Concurrency Invariant:** Created a partial unique index on `helper_attendance_logs`: `CREATE UNIQUE INDEX uq_helper_active_attendance ON public.helper_attendance_logs(helper_id) WHERE status = 'checked_in';`. Guarantees at most ONE active attendance record per helper across the database even under concurrent race conditions.
6. **Database-Level Mapping Invariant:** Created a partial unique index on `helper_flat_mappings`: `CREATE UNIQUE INDEX uq_helper_property_active_mapping ON public.helper_flat_mappings(helper_id, property_id) WHERE status = 'active';`. Permits historical revoked records while enforcing at most ONE active mapping per helper/property pair.
7. **Consistent Derived Overstay Semantics:** Adopted derived server-side overstay calculations (`NOW() - check_in > INTERVAL '12 hours'`). Active attendance status remains `checked_in`. Gatekeeper checkout after 12 hours automatically records `status = 'overstayed'`.

---

## 3. SLICE 19 SCOPE DEFINITION

### IN SCOPE:
1. **Helper Registry (`staff_helpers`):** Helper demographic profiles, service category, status (`active` / `inactive`), salted passcode verifier hash, failed-attempt counters (`failed_passcode_attempts`, `lockout_until`).
2. **Multi-Flat Authorization (`helper_flat_mappings`):** Association of domestic helpers with one or more properties in the same society, employer user ID, mapping status (`active` / `revoked`), and partial unique active mapping constraint.
3. **Gate Attendance & Overstay (`helper_attendance_logs`):** Gatekeeper entry check-in with atomic passcode verification, database-enforced single active attendance invariant, checkout recording, and overstay calculation.
4. **Passcode Management:** Cryptographic 6-digit random passcode generation, bcrypt/salted-KDF hashing, one-time plaintext presentation, and passcode rotation.
5. **Security Controls:** Rate limiting, temporary lockout defense, society isolation, RLS direct-DML blocking, server-authoritative audit logging (with passcode redaction), and employer notification routing.
6. **8 Hardened SECURITY DEFINER RPCs:** `register_domestic_helper`, `update_domestic_helper`, `set_helper_status`, `authorize_helper_for_flat`, `revoke_helper_authorization`, `checkin_domestic_helper`, `checkout_domestic_helper`, `generate_helper_passcode`.

### OUT OF SCOPE (Deferred to Future Slices):
* Resident move-in / move-out digital NOC clearance requests (Slice 20).
* Society equipment asset catalog and AMC vendor contracts (Slice 21).
* Vendor procurement, purchase orders, and 3-way invoice matching (Slice 22).
* Any modification to financial ledgers, maintenance charges, or payment intent workflows.

---

## 4. ROLE AUTHORIZATION MATRIX

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

1. **Society Binding:** All tables reference `public.societies(id)` (`NOT NULL`).
2. **RPC Validation:** Every RPC verifies `v_caller_society := public.get_user_society_id(auth.uid())` matches target entity `society_id`. Mismatches throw `42501` ('Cross-society execution denied.').
3. **Cross-Society Mapping & Entry Defense:** `authorize_helper_for_flat` verifies helper and property belong to the same society. `checkin_domestic_helper` verifies gatekeeper society matches helper and property society.

---

## 6. DATA MODEL & SCHEMA DESIGN

### 6.1 `public.staff_helpers`
```sql
CREATE TABLE IF NOT EXISTS public.staff_helpers (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id              UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    full_name               VARCHAR(150) NOT NULL,
    mobile                  VARCHAR(20) NOT NULL,
    service_type            VARCHAR(50) NOT NULL CONSTRAINT chk_helper_service_type CHECK (
                                service_type IN ('maid', 'driver', 'cook', 'nanny', 'car_washer', 'tutor', 'gardener', 'other')
                            ),
    id_type                 VARCHAR(30) CONSTRAINT chk_helper_id_type CHECK (
                                id_type IS NULL OR id_type IN ('aadhaar', 'pan', 'passport', 'voter_id', 'driving_license', 'other')
                            ),
    photo_url               TEXT,
    passcode_hash           TEXT NOT NULL,              -- bcrypt or salted KDF hash
    passcode_salt           TEXT,                       -- Salt string if custom salted KDF used
    status                  VARCHAR(20) NOT NULL DEFAULT 'active' CONSTRAINT chk_helper_status CHECK (status IN ('active', 'inactive')),
    failed_passcode_attempts INT NOT NULL DEFAULT 0,    -- Failed attempt counter
    lockout_until           TIMESTAMPTZ,                -- Temporary lockout expiry
    registered_by           UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
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
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Partial Unique Index: At most ONE active mapping per helper/property pair
CREATE UNIQUE INDEX uq_helper_property_active_mapping ON public.helper_flat_mappings(helper_id, property_id) WHERE status = 'active';

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

-- Partial Unique Index: At most ONE active (checked_in) attendance record per helper across database
CREATE UNIQUE INDEX uq_helper_active_attendance ON public.helper_attendance_logs(helper_id) WHERE status = 'checked_in';

CREATE INDEX idx_helper_attendance_helper_status ON public.helper_attendance_logs(helper_id, status);
CREATE INDEX idx_helper_attendance_society_checkin ON public.helper_attendance_logs(society_id, check_in);
```

---

## 7. HELPER LIFECYCLE & STATE MACHINES

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

* **`active` $\rightarrow$ `inactive`:** Admin sets helper status to `inactive`. Inactive helpers fail gate check-in (`22000` 'Helper is currently inactive.') and cannot receive new flat mappings.
* **`inactive` $\rightarrow$ `active`:** Admin reactivates helper status.

---

## 8. PASSCODE ARCHITECTURE & RATE-LIMITING DEFENSE

1. **Server-Side Passcode Verification:** `checkin_domestic_helper` verifies passcode via `public.crypt(p_passcode, v_helper.passcode_hash) = v_helper.passcode_hash` (using `pgcrypto`).
2. **Lockout Check:** Before evaluating passcode, `checkin_domestic_helper` checks:
   ```sql
   IF v_helper.lockout_until IS NOT NULL AND v_helper.lockout_until > NOW() THEN
       RAISE EXCEPTION 'Account temporarily locked due to excessive failed attempts. Try again later.' USING ERRCODE = '22000';
   END IF;
   ```
3. **Failed-Attempt Handling:** If passcode check fails:
   ```sql
   UPDATE public.staff_helpers 
   SET failed_passcode_attempts = failed_passcode_attempts + 1,
       lockout_until = CASE WHEN failed_passcode_attempts + 1 >= 5 THEN NOW() + INTERVAL '15 minutes' ELSE lockout_until END
   WHERE id = p_helper_id;
   RAISE EXCEPTION 'Invalid helper passcode.' USING ERRCODE = '22000';
   ```
4. **Successful Verification Reset:** Upon valid passcode check-in, `failed_passcode_attempts` is reset to `0` and `lockout_until` is set to `NULL`.
5. **One-Time Passcode Generation:** `generate_helper_passcode` returns plaintext 6-digit PIN **EXACTLY ONCE** in function return payload. Plaintext is never stored in tables, audit logs, or notifications.

---

## 9. GATE ENTRY & EXIT WORKFLOWS

### Entry Workflow (`checkin_domestic_helper`):
1. Gatekeeper calls `checkin_domestic_helper(p_helper_id, p_property_id, p_passcode)`.
2. Verifies caller is active `gatekeeper` or `admin` in caller's society (`42501`).
3. Locks `staff_helpers` row with `FOR UPDATE`. Verifies helper exists, society matches, status is `active`, and `lockout_until` is not active.
4. Verifies active mapping exists in `helper_flat_mappings` (`status = 'active'`) for `p_property_id` (`42501` 'Helper is not authorized for target property.').
5. Verifies passcode using bcrypt/salted KDF. If invalid, increments failed attempts and raises `22000` ('Invalid helper passcode.').
6. Inserts `helper_attendance_logs` row (`status = 'checked_in'`). Database partial unique index `uq_helper_active_attendance` guarantees no concurrent double check-in.
7. Resets failed passcode attempts to zero, logs server audit event, and notifies flat resident(s).

### Exit Workflow (`checkout_domestic_helper`):
1. Gatekeeper calls `checkout_domestic_helper(p_attendance_id)`.
2. Verifies caller is active `gatekeeper` or `admin` in caller's society (`42501`).
3. Locks `helper_attendance_logs` row with `FOR UPDATE`.
4. Verifies `check_out IS NULL` (`22000` 'Helper is already checked out.').
5. Determines exit status: If `NOW() - check_in > INTERVAL '12 hours'`, sets `status = 'overstayed'`, else `status = 'checked_out'`.
6. Sets `check_out = NOW()`, `exit_gatekeeper_id = v_caller`.
7. Logs server audit event and notifies flat resident(s).

---

## 10. ROW-LEVEL SECURITY (RLS) & DIRECT DML MATRIX

All 3 tables enforce `FORCE ROW LEVEL SECURITY`.

| Table | Operation | Permission | Policy Mechanism |
| :--- | :--- | :--- | :--- |
| `staff_helpers` | `SELECT` | Authorized | Admin/Gatekeeper (Society) or Mapped Resident |
| `staff_helpers` | `INSERT / UPDATE / DELETE` | **DENIED** | RESTRICTIVE Policy `USING (false) WITH CHECK (false)` |
| `helper_flat_mappings` | `SELECT` | Authorized | Admin (Society) or Mapped Resident |
| `helper_flat_mappings` | `INSERT / UPDATE / DELETE` | **DENIED** | RESTRICTIVE Policy `USING (false) WITH CHECK (false)` |
| `helper_attendance_logs` | `SELECT` | Authorized | Admin/Gatekeeper (Society) or Mapped Resident |
| `helper_attendance_logs` | `INSERT / UPDATE / DELETE` | **DENIED** | RESTRICTIVE Policy `USING (false) WITH CHECK (false)` |

All table mutations MUST pass through authorized `SECURITY DEFINER` RPC functions.

---

## 11. AUDIT & NOTIFICATION SECURITY

* **Audit Logs (`audit_logs`):** Server-authoritative entry created inside SECURITY DEFINER routines. Actor derived from `auth.uid()`. Plaintext passcodes and hash salts are strictly redacted/excluded.
* **Notifications (`notifications`):** Generated server-side targeting `helper_flat_mappings.employer_user_id` residents. Direct client notification insertion or recipient manipulation is blocked by RLS.

---

## 12. FINANCIAL SAFETY GATE

> **ZERO FINANCIAL MUTATIONS PROPOSED FOR SLICE 19**

Slice 19 contains zero financial postings, ledger modifications, fee calculations, payment gateway interactions, or balance updates. All existing Slice 1–18 financial structures remain 100% immutable and uninfluenced.

---

## 13. VERIFICATION DESIGN & ASSERTION INVENTORY

Slice 19 verification (`database/verify_slice19.sql`) defines **44 new assertions** (`S19-001` through `S19-044`):

```text
S19-001 | 3 New Tables Exist (staff_helpers, helper_flat_mappings, helper_attendance_logs)
S19-002 | Partial Unique Index uq_helper_active_attendance Exists
S19-003 | Partial Unique Index uq_helper_property_active_mapping Exists
S19-004 | 8 New RPC Routines Exist
S19-005 | SECURITY DEFINER & fixed search_path Enforced on All 8 Routines
S19-006 | RLS & FORCE RLS Enabled on All 3 Tables
S19-007 | Anonymous register_domestic_helper Rejected (42501)
S19-008 | Anonymous checkin_domestic_helper Rejected (42501)
S19-009 | Valid Domestic Helper Registration Execution
S19-010 | Passcode Salt & Hash Verification (Salted KDF)
S19-011 | Admin Status Update to Inactive Execution
S19-012 | Inactive Helper Gate Check-In Blocked (22000)
S19-013 | Resident Authorize Helper for Own Property Execution
S19-014 | Resident Authorizing Another Resident's Property Blocked (42501)
S19-015 | Resident Supplying Fake Employer User ID Blocked (42501)
S19-016 | Revoke Flat Authorization Execution
S19-017 | Revoked Flat Helper Check-In Blocked (42501)
S19-018 | Valid Gatekeeper Helper Check-In Execution
S19-019 | Incorrect Passcode Gate Check-In Blocked (22000)
S19-020 | Failed Passcode Attempt Counter Increments
S19-021 | 5 Failed Passcode Attempts Triggers 15-Min Lockout (22000)
S19-022 | Successful Check-In Resets Failed Attempt Counter
S19-023 | Duplicate Active Check-In Blocked by Partial Unique Index (23505/22000)
S19-024 | Valid Gatekeeper Helper Checkout Execution
S19-025 | Duplicate Helper Checkout Blocked (22000)
S19-026 | Overstay Duration Status Calculation (overstayed if >12h)
S19-027 | One-Time Passcode Generation Execution
S19-028 | Old Passcode Fails Immediately After Rotation (22000)
S19-029 | Cross-Society register_domestic_helper Blocked (42501)
S19-030 | Cross-Society authorize_helper_for_flat Blocked (42501)
S19-031 | Cross-Society checkin_domestic_helper Blocked (42501)
S19-032 | Cross-Society checkout_domestic_helper Blocked (42501)
S19-033 | Direct staff_helpers INSERT Blocked by RLS (42501)
S19-034 | Direct staff_helpers UPDATE Blocked by RLS (42501)
S19-035 | Direct staff_helpers DELETE Blocked by RLS (42501)
S19-036 | Direct helper_flat_mappings DML Blocked by RLS (42501)
S19-037 | Direct helper_attendance_logs DML Blocked by RLS (42501)
S19-038 | Audit Log Entry Created for Helper Registration
S19-039 | Audit Log Entry Created for Helper Check-In
S19-040 | Audit Log Redaction (Passcode Excluded)
S19-041 | Real-time Notification Created for Helper Check-In
S19-042 | Notification Recipient Scoping (Mapped Employer Only)
S19-043 | Financial Non-Interference Verification (Zero Ledger Changes)
S19-044 | Cumulative Suite Regression Target Reached (639/639 PASS)
```

---

## 14. REGRESSION REQUIREMENT & TARGET BASELINE

```text
Locked Baseline (Slices 1-18):  595 / 595 PASS
New Slice 19 Assertions:         44 /  44 PASS
--------------------------------------------------
Cumulative Verification Target: 639 / 639 PASS (100%)
```

---

## 15. APPLICATION / UI INTEGRATION PLAN

* **Client SDK (`src/supabase.js`):** Additive mock client methods for helper registration, mapping, check-in, checkout, and passcode rotation.
* **UI Components (`src/App.jsx`):**
  * **Gatekeeper Dashboard:** Add 'Domestic Staff Gate Check-In' widget with passcode verification modal.
  * **Resident / Member View:** Add 'My Domestic Staff' card supporting flat mapping, revocation, and 'Generate Passcode' (showing 6-digit PIN once).
  * **Admin Operations Manager:** Add 'Staff Helper Registry' table with activation/deactivation toggles.

---

## 16. EXACT FILE CHANGE PLAN

| Artifact Path | Action | Rationale | Security Impact |
| :--- | :---: | :--- | :--- |
| `database/schema_slice19.sql` | **NEW** | DDL for 3 tables, indexes, 8 RPCs | Hardened DDL & SECURITY DEFINER routines |
| `database/verify_slice19.sql` | **NEW** | 44 Verification Assertions | Automated security & workflow testing |
| `scratch/run_all19.ps1` | **NEW** | Cumulative Test Runner | Executes 639 total tests |
| `src/supabase.js` | **MODIFY** | Additive mock SDK methods | Zero impact on existing baseline methods |
| `src/App.jsx` | **MODIFY** | Additive UI components | Zero impact on existing baseline views |
| `database/schema_slice1.sql` .. `schema_slice18.sql` | **UNTOUCHED** | Locked Baseline | Preserved 100% Immutable |
| `database/verify_slice1.sql` .. `verify_slice18.sql` | **UNTOUCHED** | Locked Baseline | Preserved 100% Immutable |
| `scratch/run_all.ps1` .. `run_all18.ps1` | **UNTOUCHED** | Locked Baseline | Preserved 100% Immutable |

---

## 17. DATABASE MIGRATION STRATEGY

1. Execute `schema_slice19.sql` inside a single transactional block (`BEGIN ... COMMIT`).
2. Execution sequence:
   * Create `staff_helpers`, `helper_flat_mappings`, `helper_attendance_logs` tables.
   * Create partial unique indexes (`uq_helper_active_attendance`, `uq_helper_property_active_mapping`).
   * Apply `FORCE ROW LEVEL SECURITY` and RESTRICTIVE policy DDL.
   * Create 8 `SECURITY DEFINER` RPC routines with `SET search_path = public, pg_temp`.
   * Grant `EXECUTE` privileges to `authenticated` and `service_role`.
3. Execute `verify_slice19.sql` via `scratch/run_all19.ps1` to validate all 639 assertions.

---

## 18. ROLLBACK STRATEGY

If Slice 19 verification fails during execution:
1. Roll back transaction or execute `DROP TABLE IF EXISTS helper_attendance_logs, helper_flat_mappings, staff_helpers CASCADE`.
2. Execute `scratch/run_all18.ps1` to confirm immediate baseline restoration to **595/595 PASS**.

---

## 19. INDEPENDENT ADVERSARIAL AUDIT PLAN

Upon completion of Slice 19 verification (639/639 PASS), an independent adversarial security audit will be commissioned to audit:
* Salted KDF passcode verification and non-plaintext exposure.
* Failed-attempt rate limiting and 15-minute lockout defense.
* Cross-society helper UUID and property UUID substitution attempts.
* Direct DML bypass attempts on attendance logs.
* Concurrent double check-in prevention via partial unique index.
* Gatekeeper role authorization boundaries.

---

## 20. LOCK CRITERIA

Slice 19 will be eligible for security lock ONLY when:
1. All 44 Slice 19 assertions pass deterministically (`44/44 PASS`).
2. Baseline regression test suite passes (`595/595 PASS`).
3. Cumulative suite achieves **639/639 PASS**.
4. Independent adversarial security audit returns verdict: **A. SECURITY PASS — READY TO LOCK**.
5. SHA-256 checksums recorded in `SLICE19_FINAL_LOCK_RECORD.md`.

---

## 21. FINAL STATUS REQUIREMENT

* **Slice 19 Plan Revision:** COMPLETE (Revision 2).
* **595/595 Baseline:** LOCKED / UNTOUCHED.
* **Slice 19 Implementation:** NOT STARTED.
* **Database Modifications:** NONE.
* **Application Modifications:** NONE.
* **Implementation Authorization:** NONE.

---

## 22. FINAL VERDICT

### **VERDICT: A — READY FOR USER APPROVAL**

**Implementation Authorization Status: NONE**

*(Implementation will begin only after explicit user approval of this revised plan.)*
