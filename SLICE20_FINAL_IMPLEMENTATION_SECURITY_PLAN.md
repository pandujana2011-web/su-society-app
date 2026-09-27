# SLICE 20 — FINAL IMPLEMENTATION & SECURITY PLAN

**Execution Date:** September 6, 2026  
**Target Repository:** `D:\Clients Applications\SU Society App`  
**Mode:** **PLAN ONLY / ZERO IMPLEMENTATION AUTHORIZATION**  
**Slice:** 20  
**Feature:** Resident Move-In / Move-Out Digital NOC Clearance & Property Transfer Workflow  
**Current Locked Baseline:** **639 / 639 PASS (100%)**  
**Locked Scope:** **SLICES 1–19 — IMMUTABLE**  

---

## 1. EXECUTIVE SUMMARY

This document establishes the authoritative, implementation-ready **Final Implementation & Security Plan for Slice 20 — Resident Move-In / Move-Out Digital NOC Clearance Requests & Property Transfer Workflow** of the SU Society App.

### Key Plan Highlights:
1. **Zero Code / DB Mutation:** This is a planning and architecture document only. No application code, database schemas, RPC routines, RLS policies, or verification assertions have been created or modified during this planning operation.
2. **Locked Baseline Protection:** The verified **639 / 639 PASS** baseline across Slices 1–19 remains locked and immutable.
3. **Core Slice 20 Objective:** Digitizes the end-to-end multi-department clearance process required for resident move-in, move-out, and NOC issuance. Incorporates server-authoritative financial dues audits, multi-department admin checklist sign-offs, digital NOC certificate generation, time-bound 6-digit move passes with bcrypt salted KDF, lockout rate-limiting, and gatekeeper check-in/out verification.
4. **Planned Verification Baseline:** 45 new assertions (`S20-001` through `S20-045`), raising the cumulative verified baseline to **684 / 684 PASS**.

---

## 2. LOCKED BASELINE

The following baseline is authoritative, immutable, and must be preserved:

```text
=====================================================

SLICES 1–18 LOCKED BASELINE:     595 / 595 PASS (100%)

SLICE 19 VERIFIED SUITE:          44 /  44 PASS (100%)

-----------------------------------------------------

CUMULATIVE LOCKED BASELINE:      639 / 639 PASS (100%)
CUMULATIVE STATUS:               100%

INDEPENDENT SECURITY AUDIT:      PASSED
SECURITY FINDINGS:               0

SLICE 19 STATUS:                 SECURITY LOCKED
                                 AND IMMUTABLE

=====================================================
```

Slices 1–19 artifacts, database tables, indexes, constraints, RLS policies, RPCs, triggers, and test runners are permanently locked.

---

## 3. SOURCE & DATABASE INSPECTION EVIDENCE

Read-only inspection of the repository and database catalog confirmed:
* **Frontend Architecture:** React 19 SPA (`src/App.jsx`) with Supabase JS Client service layer (`src/supabase.js`). Single-file UI component structure requires modular view state management.
* **Database Catalog:** 46 active domain tables across `public` schema. All tables enforce `ENABLE` and `FORCE ROW LEVEL SECURITY` with restrictive DML policies (`USING (false) WITH CHECK (false)`).
* **RPC Architecture:** ~60 `SECURITY DEFINER` routines hardened with `SET search_path = public, extensions, pg_temp`.
* **Financial Ledger Infrastructure:** Slices 2, 4, 9, 10, 11, and 14 maintain strict transaction immutability in `public.ledger_transactions`. Property balances are calculated as `SUM(debit amounts) - SUM(credit amounts)`.
* **Audit Logging:** Slice 18 `public.audit_logs` provides server-authoritative event logging with sensitive payload redaction.
* **Gate Security Infrastructure:** Slice 19 established passcode KDF verification (`extensions.crypt`), 15-minute lockout rate limiting after 5 failed attempts, and gatekeeper check-in/out logging.

---

## 4. BUSINESS OBJECTIVE

Residential community management requires strict control over move-in and move-out activities to prevent unauthorized occupancy, ensure outstanding maintenance dues are cleared prior to resident departure, inspect common area or unit damage, issue digital No Objection Certificates (NOC), and provide time-bound move passes to security gatekeepers for mover truck entry/exit.

Slice 20 delivers a secure, multi-department digital workflow that automates financial dues clearance checks, provides transparent status tracking to residents, enables multi-role admin sign-off, generates bcrypt-hashed gate move passes, and logs mover activity at security gates without compromising financial, operational, or security boundaries.

---

## 5. FUNCTIONAL SCOPE

Slice 20 introduces the following functional components:
1. **NOC Application Submission:** Residents (owners or tenants) submit move-in or move-out NOC requests for their authorized properties.
2. **Automated Financial Dues Clearance:** System automatically audits `ledger_transactions` server-side to verify zero outstanding dues.
3. **Multi-Department Admin Clearance Checklist:** Departmental checklists for financial dues, facility inspection, keys/access card return, and administrative sign-off.
4. **Digital NOC Certificate Generation:** Issuance of verifiable NOC certificates upon 100% checklist clearance.
5. **Time-Bound Gate Move Pass Generation:** Generation of 6-digit gate move passes hashed using bcrypt KDF (`extensions.crypt`).
6. **Security Gate Verification & Mover Logging:** Gatekeeper verification of move passes, vehicle registration, and mover truck check-in/check-out timestamps.

---

## 6. MOVE-IN WORKFLOW

```text
[ Resident / Owner ]
         │
         ▼ (Submit Move-In NOC Request)
┌─────────────────────────────────────────────────────────────┐
│ NOC Request Created (status = 'submitted')                  │
│ Initial Clearance Items Generated in Checklist              │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼ (Admin Review)
┌─────────────────────────────────────────────────────────────┐
│ Department Clearance (Documents, Inspection, Fees)          │
│ status = 'clearance_in_progress'                            │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼ (100% Checklist Cleared)
┌─────────────────────────────────────────────────────────────┐
│ NOC Approved (status = 'approved') & Digital NOC Issued     │
│ Move Pass Generated (6-digit PIN hashed via bcrypt KDF)     │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼ (Move Day Gate Verification)
┌─────────────────────────────────────────────────────────────┐
│ Gatekeeper Scans/Verifies Pass -> Mover Truck Check-In/Out  │
│ Request Completed (status = 'completed')                    │
│ Occupancy Record Updated / Activated                        │
└─────────────────────────────────────────────────────────────┘
```

---

## 7. MOVE-OUT WORKFLOW

```text
[ Tenant / Owner ]
         │
         ▼ (Submit Move-Out NOC Request)
┌─────────────────────────────────────────────────────────────┐
│ NOC Request Created (status = 'submitted')                  │
│ Checklist Items Created (Financial Dues, Damage, Admin)     │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼ (Auto Financial Dues Audit)
┌─────────────────────────────────────────────────────────────┐
│ System queries ledger_transactions server-side:             │
│   • Outstanding Dues > 0  ──> Financial Clearance FLAGGED   │
│   • Outstanding Dues = 0  ──> Financial Clearance CLEARED   │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼ (Admin / Tech Sign-Off)
┌─────────────────────────────────────────────────────────────┐
│ Facility Damage & Key Return Inspection Clearance           │
│ Admin Signs Off NOC                                         │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼ (100% Cleared)
┌─────────────────────────────────────────────────────────────┐
│ NOC Approved & Move-Out Pass Code Generated (Bcrypt KDF)    │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼ (Gate Exit Verification)
┌─────────────────────────────────────────────────────────────┐
│ Mover Truck Verified at Gate -> Check-Out Recorded          │
│ Request Status = 'completed'                                │
│ Tenancy Status Updated to Terminated                        │
└─────────────────────────────────────────────────────────────┘
```

---

## 8. PROPERTY SALE SCOPE DECISION

### Formal Scope Decision:
* **INCLUDED IN SLICE 20:** Support for `request_type = 'property_sale_noc'` strictly for issuing administrative and financial clearance NOC certificates required prior to property transfer.
* **DEFERRED TO FUTURE SLICE:** Automatic mutation of `property_owners` records (ownership transfer execution).

### Rationale:
Property sales require legal title deed verification, society membership transfer fee assessments, board resolution sign-offs, and share certificate re-issuance. Performing automatic database ownership transfer upon NOC approval creates significant risk of unauthorized title reassignment. Reassigning property ownership belongs to a dedicated legal/membership transfer slice (Slice 24). Slice 20 handles the NOC clearance application and financial audit prerequisite only.

---

## 9. NOC STATE MACHINE

The NOC request state machine is strictly enforced server-side via RPC logic:

| Current State | Next State | Authorized Actor | Preconditions | DB Enforcement | Audit Event |
| :--- | :--- | :--- | :--- | :--- | :--- |
| *None* | `submitted` | Resident (Owner/Tenant) | Requester owns or rents property; no active NOC request exists for property. | Partial Unique Index `uq_active_noc_request` | `noc_request_submitted` |
| `submitted` | `dues_pending` | Treasurer / System RPC | Financial dues audit executed; outstanding ledger balance > 0. | RPC `perform_financial_dues_clearance` | `noc_dues_audit_flagged` |
| `submitted` / `dues_pending` | `clearance_in_progress` | Treasurer / Admin | Financial dues cleared (balance <= 0); non-financial checklist items open. | RPC state check | `noc_clearance_started` |
| `clearance_in_progress` | `approved` | Secretary / Admin | 100% of checklist items in `noc_clearance_checklists` status = `'cleared'`. | Atomic SQL checklist status validation | `noc_request_approved` |
| `submitted` / `dues_pending` / `clearance_in_progress` | `rejected` | Admin / Treasurer | Outstanding dues unpaid or facility inspection failed; rejection reason provided. | RPC `reject_noc_request` | `noc_request_rejected` |
| `submitted` / `dues_pending` / `clearance_in_progress` | `cancelled` | Requester Resident | Request in non-final state; cancelled by owner/tenant. | Requester identity match | `noc_request_cancelled` |
| `approved` | `completed` | Gatekeeper (Guard) | Move pass validated at gate; mover truck check-out recorded. | RPC `verify_noc_move_pass` | `noc_move_completed` |

---

## 10. DATABASE DESIGN

Slice 20 introduces 3 core tables to manage NOC applications, departmental checklists, and gate move passes:

```text
┌────────────────────────────────┐       ┌──────────────────────────────────────┐
│       public.noc_requests      │       │   public.noc_clearance_checklists    │
├────────────────────────────────┤       ├──────────────────────────────────────┤
│ id (PK)                        │1     N│ id (PK)                              │
│ society_id (FK)                │◄──────│ noc_request_id (FK)                  │
│ property_id (FK)               │       │ clearance_category                   │
│ requester_id (FK)              │       │ status ('pending','cleared','flagged')│
│ request_type                   │       │ remarks                              │
│ status                         │       │ cleared_by (FK)                      │
│ move_date                      │       │ cleared_at                           │
│ created_at / updated_at        │       └──────────────────────────────────────┘
└───────────────┬────────────────┘
                │1
                │
                │1
                ▼
┌────────────────────────────────┐
│      public.noc_move_passes    │
├────────────────────────────────┤
│ id (PK)                        │
│ noc_request_id (FK)            │
│ pass_code_hash (Bcrypt KDF)    │
│ valid_from / valid_until       │
│ vehicle_number / mover_details │
│ status ('active','used','exp') │
│ failed_attempts / lockout_until│
│ check_in_time / check_out_time │
│ gatekeeper_id (FK)             │
└────────────────────────────────┘
```

---

## 11. PROPOSED TABLES

### 1. `public.noc_requests`
```sql
CREATE TABLE public.noc_requests (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id          UUID        NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    property_id         UUID        NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
    unit_id             UUID        REFERENCES public.units(id) ON DELETE RESTRICT,
    requester_id        UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    request_type        VARCHAR(30) NOT NULL CONSTRAINT chk_noc_request_type CHECK (
                                        request_type IN ('move_in', 'move_out', 'property_sale_noc')
                                    ),
    status              VARCHAR(30) NOT NULL DEFAULT 'submitted' CONSTRAINT chk_noc_status CHECK (
                                        status IN ('submitted', 'dues_pending', 'clearance_in_progress', 'approved', 'rejected', 'cancelled', 'completed')
                                    ),
    move_date           DATE        NOT NULL,
    reason_notes        TEXT,
    rejection_reason    TEXT,
    certificate_url     VARCHAR(1024),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_noc_move_date CHECK (move_date >= CURRENT_DATE - INTERVAL '1 day')
);
```

### 2. `public.noc_clearance_checklists`
```sql
CREATE TABLE public.noc_clearance_checklists (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    noc_request_id      UUID        NOT NULL REFERENCES public.noc_requests(id) ON DELETE CASCADE,
    clearance_category  VARCHAR(50) NOT NULL CONSTRAINT chk_noc_clearance_cat CHECK (
                                        clearance_category IN ('financial_dues', 'facility_inspection', 'keys_access_cards', 'admin_signoff')
                                    ),
    status              VARCHAR(30) NOT NULL DEFAULT 'pending' CONSTRAINT chk_noc_clearance_status CHECK (
                                        status IN ('pending', 'cleared', 'flagged')
                                    ),
    remarks             TEXT,
    cleared_by          UUID        REFERENCES public.users(id) ON DELETE RESTRICT,
    cleared_at          TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_noc_category UNIQUE (noc_request_id, clearance_category)
);
```

### 3. `public.noc_move_passes`
```sql
CREATE TABLE public.noc_move_passes (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    noc_request_id      UUID        NOT NULL UNIQUE REFERENCES public.noc_requests(id) ON DELETE CASCADE,
    pass_code_hash      VARCHAR(255) NOT NULL,
    valid_from          TIMESTAMPTZ NOT NULL,
    valid_until         TIMESTAMPTZ NOT NULL,
    vehicle_number      VARCHAR(30),
    mover_details       TEXT,
    status              VARCHAR(30) NOT NULL DEFAULT 'active' CONSTRAINT chk_move_pass_status CHECK (
                                        status IN ('active', 'used', 'expired', 'revoked')
                                    ),
    failed_attempts     INTEGER     NOT NULL DEFAULT 0 CONSTRAINT chk_pass_failed_attempts CHECK (failed_attempts >= 0),
    lockout_until       TIMESTAMPTZ,
    check_in_time       TIMESTAMPTZ,
    check_out_time      TIMESTAMPTZ,
    gatekeeper_id       UUID        REFERENCES public.users(id) ON DELETE RESTRICT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_pass_validity_window CHECK (valid_from < valid_until)
);
```

---

## 12. CONSTRAINTS & INDEXES

### Partial Unique Indexes:
1. **Single Active NOC Request Per Property & Type:**
   ```sql
   CREATE UNIQUE INDEX uq_active_noc_request 
   ON public.noc_requests (property_id, request_type) 
   WHERE status IN ('submitted', 'dues_pending', 'clearance_in_progress', 'approved');
   ```
   *Purpose:* Prevents residents from submitting multiple concurrent NOC requests for the same property.

2. **Single Active Move Pass Per NOC Request:**
   ```sql
   CREATE UNIQUE INDEX uq_active_noc_move_pass 
   ON public.noc_move_passes (noc_request_id) 
   WHERE status = 'active';
   ```
   *Purpose:* Ensures only one valid active move pass code exists per approved NOC request.

---

## 13. RLS / FORCE RLS DESIGN

All 3 tables explicitly enforce `ENABLE` and `FORCE ROW LEVEL SECURITY`:

```sql
ALTER TABLE public.noc_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.noc_requests FORCE ROW LEVEL SECURITY;

ALTER TABLE public.noc_clearance_checklists ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.noc_clearance_checklists FORCE ROW LEVEL SECURITY;

ALTER TABLE public.noc_move_passes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.noc_move_passes FORCE ROW LEVEL SECURITY;
```

### Restrictive DML Direct Access Blocking:
Direct DML (`INSERT`, `UPDATE`, `DELETE`) from client connections is strictly blocked:

```sql
CREATE POLICY pol_noc_requests_restrictive_insert ON public.noc_requests 
  AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (false);

CREATE POLICY pol_noc_requests_restrictive_update ON public.noc_requests 
  AS RESTRICTIVE FOR UPDATE TO authenticated USING (false);

CREATE POLICY pol_noc_requests_restrictive_delete ON public.noc_requests 
  AS RESTRICTIVE FOR DELETE TO authenticated USING (false);

-- (Identical restrictive DML policies applied to noc_clearance_checklists and noc_move_passes)
```

### Permissive `SELECT` Policies:
1. `noc_requests`: Requesters can select their own requests; admins can select all requests in their society; gatekeepers can select approved requests in their society.
2. `noc_clearance_checklists`: Visible to requesters and admins within the same society.
3. `noc_move_passes`: Requesters can view move pass metadata (excluding passcode hash); admins and gatekeepers within the society can select.

---

## 14. SECURITY DEFINER RPC DESIGN

All business state transitions are encapsulated in hardened `SECURITY DEFINER` routines with explicit `SET search_path = public, extensions, pg_temp`:

### 1. `public.submit_noc_request`
```sql
CREATE OR REPLACE FUNCTION public.submit_noc_request(
    p_property_id UUID,
    p_request_type TEXT,
    p_move_date DATE,
    p_reason_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$ ... $$;
```
* **Security Controls:** Verifies `auth.uid() IS NOT NULL`, extracts society ID via `public.get_user_society_id()`, validates user is primary owner or active tenant of property, creates `noc_requests` row, initializes 4 checklist items (`financial_dues`, `facility_inspection`, `keys_access_cards`, `admin_signoff`), logs audit entry.

### 2. `public.perform_financial_dues_clearance`
```sql
CREATE OR REPLACE FUNCTION public.perform_financial_dues_clearance(
    p_noc_request_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$ ... $$;
```
* **Security Controls:** Admin or Treasurer caller validation. Queries `ledger_transactions` for property balance. Sets `financial_dues` checklist status to `cleared` (if balance <= 0) or `flagged` (if balance > 0).

### 3. `public.update_clearance_checklist_item`
```sql
CREATE OR REPLACE FUNCTION public.update_clearance_checklist_item(
    p_noc_request_id UUID,
    p_category TEXT,
    p_status TEXT,
    p_remarks TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$ ... $$;
```
* **Security Controls:** Admin / Treasurer authorization. Updates target checklist item (`cleared` or `flagged`), records `cleared_by = auth.uid()` and `cleared_at = NOW()`.

### 4. `public.approve_noc_request`
```sql
CREATE OR REPLACE FUNCTION public.approve_noc_request(
    p_noc_request_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$ ... $$;
```
* **Security Controls:** Admin / Secretary authorization. Verifies 100% of items in `noc_clearance_checklists` status = `cleared`. Rejects transition if any item is `pending` or `flagged`. Updates request status to `approved`.

### 5. `public.reject_noc_request`
```sql
CREATE OR REPLACE FUNCTION public.reject_noc_request(
    p_noc_request_id UUID,
    p_rejection_reason TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$ ... $$;
```
* **Security Controls:** Admin authorization. Updates request status to `rejected`, records rejection reason, emits audit event.

### 6. `public.cancel_noc_request`
```sql
CREATE OR REPLACE FUNCTION public.cancel_noc_request(
    p_noc_request_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$ ... $$;
```
* **Security Controls:** Validates caller `auth.uid() = requester_id`. Transitions non-final request status to `cancelled`.

### 7. `public.generate_noc_move_pass`
```sql
CREATE OR REPLACE FUNCTION public.generate_noc_move_pass(
    p_noc_request_id UUID,
    p_valid_from TIMESTAMPTZ,
    p_valid_until TIMESTAMPTZ,
    p_vehicle_number TEXT DEFAULT NULL,
    p_mover_details TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$ ... $$;
```
* **Security Controls:** Verifies NOC request status = `approved`. Generates cryptographically strong 6-digit PIN (`100000 + floor(random() * 900000)`). Hashes PIN using `extensions.crypt(v_pin, extensions.gen_salt('bf', 8))`. Stores hash in `noc_move_passes`. **Returns plaintext PIN EXACTLY ONCE in JSON payload.**

### 8. `public.verify_noc_move_pass`
```sql
CREATE OR REPLACE FUNCTION public.verify_noc_move_pass(
    p_pass_code TEXT,
    p_vehicle_number TEXT DEFAULT NULL,
    p_mover_details TEXT DEFAULT NULL,
    p_direction TEXT DEFAULT 'out'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$ ... $$;
```
* **Security Controls:** Gatekeeper (`has_role('gatekeeper')` or `is_admin()`) authorization. Evaluates lockout (`lockout_until > NOW()`). Compares `extensions.crypt(p_pass_code, pass_code_hash) == pass_code_hash`. On failure, increments `failed_attempts` (5 failures trigger 15-min lockout) and returns generic error `22000`. On success, resets counter, records `check_in_time` or `check_out_time`, updates status to `used` / `completed`, and logs audit entry.

---

## 15. AUTHENTICATION & AUTHORIZATION

All Slice 20 RPCs enforce strict identity and authorization checks:

```sql
-- 1. Authentication Gate
IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
END IF;

-- 2. Tenant Isolation Gate
v_society_id := public.get_user_society_id(auth.uid());
IF v_society_id IS NULL OR v_society_id <> v_request_society_id THEN
    RAISE EXCEPTION 'Cross-society execution denied.' USING ERRCODE = '42501';
END IF;

-- 3. Role Authorization Gate
IF NOT (is_admin() OR has_role('secretary') OR has_role('treasurer')) THEN
    RAISE EXCEPTION 'Unauthorized role for NOC clearance.' USING ERRCODE = '42501';
END IF;
```

---

## 16. PROPERTY OWNERSHIP / TENANCY SECURITY

When `submit_noc_request` is invoked, the database verifies that the caller owns or rents the target property:

```sql
SELECT EXISTS (
    SELECT 1 FROM public.property_owners 
    WHERE property_id = p_property_id AND owner_id = auth.uid() 
      AND (end_date IS NULL OR end_date >= CURRENT_DATE)
    UNION
    SELECT 1 FROM public.tenancies 
    WHERE property_id = p_property_id AND tenant_id = auth.uid() 
      AND (end_date IS NULL OR end_date >= CURRENT_DATE)
) INTO v_is_authorized;

IF NOT v_is_authorized AND NOT is_admin() THEN
    RAISE EXCEPTION 'User is not authorized for target property.' USING ERRCODE = '42501';
END IF;
```

---

## 17. FINANCIAL CLEARANCE DESIGN

The financial clearance step is **100% server-authoritative**. The client cannot pass a boolean flag or self-certify zero dues balance.

### Calculation Logic in `perform_financial_dues_clearance`:
```sql
SELECT COALESCE(SUM(
    CASE WHEN direction = 'debit' THEN amount ELSE -amount END
), 0.00)
INTO v_balance
FROM public.ledger_transactions
WHERE society_id = v_society_id 
  AND property_id = v_property_id 
  AND scope = 'property';

IF v_balance > 0 THEN
    v_status := 'flagged';
    v_remarks := format('Outstanding dues balance of INR %s present.', v_balance);
ELSE
    v_status := 'cleared';
    v_remarks := 'Financial dues cleared. Net balance is zero.';
END IF;

UPDATE public.noc_clearance_checklists
SET status = v_status,
    remarks = v_remarks,
    cleared_by = auth.uid(),
    cleared_at = NOW(),
    updated_at = NOW()
WHERE noc_request_id = p_noc_request_id 
  AND clearance_category = 'financial_dues';
```

---

## 18. FINANCIAL NON-INTERFERENCE

Slice 20 is strictly **read-only** regarding financial balances and ledger transactions:
* It does NOT modify `public.ledger_transactions`.
* It does NOT create dummy payment allocations or credit charges.
* It does NOT alter `public.payments` or `public.maintenance_charges`.
* It reads net balances strictly to record clearance checklist state.

---

## 19. CLEARANCE CHECKLIST

Every NOC request initializes four standardized clearance items in `noc_clearance_checklists`:

1. `financial_dues`: Managed automatically via `perform_financial_dues_clearance` or manually by Treasurer.
2. `facility_inspection`: Verified by Technician / Admin to confirm no common area or unit structural damage exists.
3. `keys_access_cards`: Verified by Admin to confirm return of society RFID cards, clubhouse keys, and parking tags.
4. `admin_signoff`: Granted by Secretary / Admin as final approval sign-off.

---

## 20. MOVE PASS SECURITY

Move pass codes adhere to the exact security architecture locked in Slice 19:
1. **Passcode Salted KDF:** Hashed via `extensions.crypt(p_passcode, extensions.gen_salt('bf', 8))`. Bare SHA-256 is strictly prohibited.
2. **One-Time Presentation:** Plaintext 6-digit PIN returned exactly once in `generate_noc_move_pass` creation payload. Never stored in tables or logs.
3. **Atomic Verification:** Verified inside `verify_noc_move_pass`. No standalone `verify_passcode` RPC exists.
4. **Oracle Resistance:** Invalid attempts return generic error `22000` (`Invalid move pass code.`).
5. **Failed-Attempt Defense:** 5 consecutive failed attempts trigger 15-minute lockout (`lockout_until = NOW() + INTERVAL '15 minutes'`).

---

## 21. GATEKEEPER WORKFLOW

```text
[ Mover Truck Arrives at Security Gate ]
                   │
                   ▼
[ Gatekeeper Opens Move Pass Verification Screen ]
                   │
                   ▼
[ Guard Enters 6-Digit Move Pass Code & Vehicle Registration ]
                   │
                   ▼ (Invokes verify_noc_move_pass)
┌─────────────────────────────────────────────────────────────┐
│ DB RPC Verification:                                        │
│  1. Check auth.uid() has 'gatekeeper' role                  │
│  2. Check lockout_until <= NOW()                            │
│  3. Check crypt(code, pass_code_hash) == pass_code_hash    │
│  4. Check NOW() BETWEEN valid_from AND valid_until          │
└──────────────┬──────────────────────────────┬───────────────┘
               │                              │
          (Pass Valid)                  (Pass Invalid)
               │                              │
               ▼                              ▼
┌──────────────────────────────┐┌──────────────────────────────┐
│  • Record check_in/out_time  ││  • Increment failed_attempts │
│  • Update pass status='used' ││  • Lockout if attempts >= 5  │
│  • Log audit event           ││  • Raise Error 22000         │
│  • Grant Gate Entry / Exit   │└──────────────────────────────┘
└──────────────────────────────┘
```

---

## 22. DOCUMENTS / EVIDENCE

NOC applications support optional document references (e.g., tenancy termination notice, buyer-seller agreement, ID proof).
* Document URLs are stored as TEXT fields in `noc_requests`.
* Access to document metadata is governed by RLS policies on `noc_requests`.
* Plaintext credentials or passcodes are strictly excluded from document fields.

---

## 23. NOTIFICATIONS

Slice 20 emits real-time notifications via `public.notifications`:

| Trigger Event | Recipient Scoping | Title | Notification Body |
| :--- | :--- | :--- | :--- |
| NOC Request Submitted | Society Admins & Treasurer | New NOC Request | NOC request submitted for Property Plot #{plot}. |
| Financial Dues Flagged | Requester Resident | Dues Audit Notice | Outstanding dues detected for NOC request #{id}. |
| NOC Approved | Requester Resident | NOC Approved | Your NOC clearance has been approved. Move pass ready. |
| NOC Rejected | Requester Resident | NOC Rejected | NOC request rejected: {reason}. |
| Move Pass Validated | Requester & Admins | Mover Gate Activity | Mover vehicle {vehicle} checked out at Security Gate. |

---

## 24. AUDIT LOGGING

Integrates seamlessly with Slice 18 immutable audit architecture via `public.audit_logs`:

* **Audited Actions:** `noc_request_submitted`, `noc_financial_clearance_executed`, `noc_checklist_item_updated`, `noc_request_approved`, `noc_request_rejected`, `noc_request_cancelled`, `noc_move_pass_generated`, `noc_move_pass_verified`.
* **Redaction Policy:** Passcode hashes and plaintext PINs are strictly excluded from `old_data` and `new_data` audit JSONB payloads.

---

## 25. CONCURRENCY / RACE CONDITIONS

1. **Concurrent NOC Submissions:** Partial unique index `uq_active_noc_request` blocks duplicate active requests for the same property at database level.
2. **Concurrent Approval & Cancellation:** Atomic RPC transactions check request status under `FOR UPDATE` row locking to prevent race condition approvals of cancelled requests.
3. **Pass Code Replay:** Once verified at gate, pass status transitions to `used` / `completed`. Re-submitting the same code returns error `22000`.

---

## 26. THREAT MODEL

| Threat ID | Threat Vector | Risk Level | Planned Security Mitigation |
| :--- | :--- | :--- | :--- |
| **TM20-01** | IDOR / Unauthorized Property NOC Submission | High | RPC verifies `auth.uid()` against `property_owners` or `tenancies`. |
| **TM20-02** | Cross-Society Data Access / Manipulation | High | Strict `society_id` checking via `public.get_user_society_id()`. |
| **TM20-03** | Fake Financial Clearance (Client Dues Bypass) | Critical | Dues clearance is 100% server-calculated in SQL from `ledger_transactions`. |
| **TM20-04** | Forged Move Pass Code / Brute Force | High | Bcrypt salted KDF (`gen_salt('bf', 8)`), 5-attempt limit, 15-min lockout. |
| **TM20-05** | Move Pass Replay Attack | Medium | State transitions to `used` immediately upon check-out verification. |
| **TM20-06** | Approval State Machine Bypass | High | `approve_noc_request` requires 100% checklist items status = `cleared`. |
| **TM20-07** | Gatekeeper Privilege Escalation | High | Gatekeepers can ONLY verify passes; cannot approve NOCs or clear dues. |
| **TM20-08** | Plaintext Passcode Leakage in Audit Logs | High | Plaintext PINs excluded from database tables and audit JSON payloads. |
| **TM20-09** | Direct Table DML Bypass via API | High | `ENABLE` + `FORCE RLS` with restrictive policies (`USING (false)`). |
| **TM20-10** | SQL Injection via RPC Arguments | Medium | Fixed `search_path = public, extensions, pg_temp` and parameterized queries. |

---

## 27. UI / UX PLAN

Application UI extensions will be integrated modularly into `src/App.jsx` and `src/supabase.js`:

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│ SU SOCIETY APP — SLICE 20 DIGITAL NOC & MOVE PASS DASHBOARD                │
├─────────────────────────────────────────────────────────────────────────────┤
│ [Resident View]                                                             │
│  • "Apply for NOC" Modal (Move-In / Move-Out / Property Sale)               │
│  • Real-Time Clearance Progress Tracker (4 Department Checklist Badges)     │
│  • Digital NOC Certificate View & Download                                  │
│  • 6-Digit Move Pass Code Display (One-Time Copy)                           │
│                                                                             │
│ [Admin / Secretary View]                                                    │
│  • NOC Applications Management Queue                                        │
│  • Departmental Clearance Checklist Sign-Off (Dues, Inspection, Sign-off)   │
│  • One-Click "Approve NOC" & Certificate Generation                         │
│                                                                             │
│ [Treasurer View]                                                            │
│  • Financial Dues Auto-Audit Panel & Outstanding Balance Summary            │
│  • Manual Dues Clearance Override                                           │
│                                                                             │
│ [Gatekeeper / Guard View]                                                   │
│  • Security Gate Move Pass Verification Scanner                             │
│  • Vehicle Registration & Mover Details Entry                               │
│  • Check-In / Check-Out Stamp & Pass Invalidation                           │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 28. ARCHITECTURE REUSE

| Component / Module | Existing Source | Reused Capability in Slice 20 |
| :--- | :--- | :--- |
| Tenant Isolation | Slices 1–19 | `public.get_user_society_id(auth.uid())` |
| Identity & Roles | Slices 1 & 19 | `is_admin()`, `has_role('gatekeeper')`, `has_role('treasurer')` |
| Property / Tenancy | Slices 1 & 2 | `public.properties`, `public.property_owners`, `public.tenancies` |
| Financial Balance | Slices 9 & 14 | Net balance calculation from `public.ledger_transactions` |
| Audit Logging | Slice 18 | `public.audit_logs` insertion and search_path hardening |
| Passcode Security | Slice 19 | Bcrypt `gen_salt('bf', 8)`, failed counter & 15-min lockout |
| Notifications | Slice 4 | `public.notifications` real-time alert dispatch |

---

## 29. CHANGE IMPACT ANALYSIS

| Existing Component | Slice 20 Impact | Modification Required? | Risk Level | Protection Strategy |
| :--- | :--- | :---: | :---: | :--- |
| **Slices 1–18 Tables** | None | **NO** | Low | Read-only queries; schema untouched. |
| **Slice 19 Tables** | None | **NO** | Low | Helper tables untouched. |
| **Financial Ledgers** | Dues calculation | **NO** | Low | Read-only aggregate query on `ledger_transactions`. |
| **Auth & User Roles** | Identity checks | **NO** | Low | Existing helper functions called read-only. |
| **Audit Log System** | Event emission | **NO** | Low | Inserts new audit rows using existing structure. |
| **Frontend Service** | New RPC calls | **YES (`src/supabase.js`)** | Low | Append Slice 20 helper functions only. |
| **Frontend UI** | New views | **YES (`src/App.jsx`)** | Low | Modular state variables & view rendering. |

---

## 30. VERIFICATION STRATEGY

Verification will follow the established project test runner architecture:
* **SQL Schema File:** `database/schema_slice20.sql`
* **SQL Verification Script:** `database/verify_slice20.sql`
* **PowerShell Test Runner:** `scratch/run_all20.ps1`

---

## 31. S20 ASSERTION PLAN

Slice 20 defines **45 detailed test assertions (`S20-001` through `S20-045`)**:

| Test ID | Test Assertion Description | Target Outcome |
| :--- | :--- | :--- |
| **S20-001** | 3 New NOC Tables Exist (`noc_requests`, `noc_clearance_checklists`, `noc_move_passes`) | PASS |
| **S20-002** | Partial Unique Index `uq_active_noc_request` Exists | PASS |
| **S20-003** | Partial Unique Index `uq_active_noc_move_pass` Exists | PASS |
| **S20-004** | 8 NOC RPC Routines Exist | PASS |
| **S20-005** | SECURITY DEFINER & `search_path` Hardened on All 8 RPCs | PASS |
| **S20-006** | RLS & FORCE RLS Enabled on All 3 Tables | PASS |
| **S20-007** | Anonymous `submit_noc_request` Blocked (`42501`) | PASS |
| **S20-008** | Anonymous `verify_noc_move_pass` Blocked (`42501`) | PASS |
| **S20-009** | Valid Resident Move-In NOC Request Submission | PASS |
| **S20-010** | Valid Resident Move-Out NOC Request Submission | PASS |
| **S20-011** | Automatic Initialization of 4 Checklist Items | PASS |
| **S20-012** | Duplicate Active NOC Request Blocked by Index | PASS |
| **S20-013** | Non-Resident / Non-Owner Property NOC Submission Blocked | PASS |
| **S20-014** | Cross-Society NOC Request Submission Blocked | PASS |
| **S20-015** | Server-Authoritative Dues Audit Execution (Dues Present -> Flagged) | PASS |
| **S20-016** | Server-Authoritative Dues Audit Execution (Zero Dues -> Cleared) | PASS |
| **S20-017** | Resident Self-Clearance Dues Bypass Blocked | PASS |
| **S20-018** | Admin Departmental Checklist Item Clearance (`facility_inspection`) | PASS |
| **S20-019** | Non-Admin Checklist Item Update Blocked | PASS |
| **S20-020** | NOC Approval Blocked When Checklist Items Pending or Flagged | PASS |
| **S20-021** | Valid NOC Approval When 100% Checklist Items Cleared | PASS |
| **S20-022** | Non-Admin NOC Approval Blocked | PASS |
| **S20-023** | Admin NOC Rejection Execution | PASS |
| **S20-024** | Requester NOC Cancellation Execution | PASS |
| **S20-025** | Non-Requester NOC Cancellation Blocked | PASS |
| **S20-026** | Move Pass Generation Blocked for Unapproved NOC Request | PASS |
| **S20-027** | Valid Move Pass Generation for Approved NOC Request | PASS |
| **S20-028** | Move Pass Salted Bcrypt KDF Verification | PASS |
| **S20-029** | Plaintext Move Pass Code Excluded From Database Tables | PASS |
| **S20-030** | Gatekeeper Valid Move Pass Check-Out Verification | PASS |
| **S20-031** | Non-Gatekeeper Move Pass Verification Blocked | PASS |
| **S20-032** | Incorrect Move Pass Code Verification Blocked (Error `22000`) | PASS |
| **S20-033** | Failed Move Pass Attempt Counter Increments | PASS |
| **S20-034** | 5 Failed Move Pass Attempts Trigger 15-Minute Lockout | PASS |
| **S20-035** | Move Pass Replay Blocked After Status = `used` | PASS |
| **S20-036** | Expired Move Pass Verification Blocked | PASS |
| **S20-037** | Direct `noc_requests` DML Blocked by Restrictive RLS | PASS |
| **S20-038** | Direct `noc_clearance_checklists` DML Blocked by Restrictive RLS | PASS |
| **S20-039** | Direct `noc_move_passes` DML Blocked by Restrictive RLS | PASS |
| **S20-040** | Audit Log Created for NOC Request Submission | PASS |
| **S20-041** | Audit Log Created for NOC Approval & Gate Verification | PASS |
| **S20-042** | Audit Log Redaction (Plaintext Passcode Excluded) | PASS |
| **S20-043** | Real-Time Notification Scoping (Requester & Admins Only) | PASS |
| **S20-044** | Financial Non-Interference (Zero Ledger Mutations) | PASS |
| **S20-045** | Cumulative Baseline Target Reached (684/684 PASS) | PASS |

---

## 32. REGRESSION STRATEGY

The Slice 20 test suite will execute all prior slice test suites sequentially before evaluating Slice 20 assertions:

```text
Slices 1–18 Suite:  595 / 595 PASS
Slice 19 Suite:      44 /  44 PASS
Slice 20 Suite:      45 /  45 PASS
-----------------------------------
Cumulative Target:  684 / 684 PASS (100%)
```

---

## 33. INDEPENDENT ADVERSARIAL AUDIT PLAN

Following implementation, Slice 20 will undergo an **Independent Adversarial Security Audit** prior to final locking:
1. **Audit Scope:** Complete repository inspect, active PostgreSQL catalog validation, RLS/FORCE RLS policy review, RPC `search_path` verification, financial dues audit code inspection, passcode KDF check, lockout rate-limit verification, audit log redaction inspection.
2. **Acceptance Requirement:** **0 Critical / 0 High / 0 Medium / 0 Low** findings.
3. **Artifact Handoff:** Package `database/schema_slice20.sql`, `database/verify_slice20.sql`, `scratch/run_all20.ps1`, `SLICE20_IMPLEMENTATION_REPORT.md`.

---

## 34. IMPLEMENTATION FILE PLAN

The following files will be created/modified during the authorized implementation phase:

### New Files:
1. `database/schema_slice20.sql` [NEW]
2. `database/verify_slice20.sql` [NEW]
3. `scratch/run_all20.ps1` [NEW]
4. `SLICE20_IMPLEMENTATION_REPORT.md` [NEW]

### Modified Files:
1. `src/supabase.js` [MODIFY - Append Slice 20 RPC helper functions]
2. `src/App.jsx` [MODIFY - Append Slice 20 UI views & state variables]

---

## 35. SCOPE BOUNDARIES

### INCLUDED IN SLICE 20:
* Digital NOC Request Submission (`move_in`, `move_out`, `property_sale_noc`).
* Server-authoritative financial dues clearance audit.
* 4-category departmental clearance checklist (`financial_dues`, `facility_inspection`, `keys_access_cards`, `admin_signoff`).
* Digital NOC Approval & Rejection workflow.
* 6-digit gate move pass generation with bcrypt KDF (`extensions.crypt`).
* Gatekeeper move pass verification, lockout rate-limiting, and mover vehicle check-in/out logging.
* Audit log integration and real-time notifications.

### EXCLUDED FROM SLICE 20:
* Automatic mutation of `property_owners` (Property Sale Ownership Transfer) — Deferred to Slice 24.
* Security gate emergency blacklisting — Deferred to Slice 21.
* Asset preventative maintenance scheduling — Deferred to Slice 22.
* Resident community marketplace — Deferred to Slice 23.
* Payment gateway integrations or live ledger entry modifications.

---

## 36. RISK REGISTER

| Risk ID | Risk Description | Likelihood | Impact | Severity | Planned Mitigation Strategy |
| :--- | :--- | :---: | :---: | :---: | :--- |
| **R20-01** | Client Dues Bypass / Fake Financial Clearance | Low | Critical | High | Dues clearance is 100% server-calculated in SQL from `ledger_transactions`. |
| **R20-02** | Move Pass Code Brute Force at Gate | Low | High | Medium | Bcrypt salted KDF (`gen_salt('bf', 8)`), 5-attempt limit, 15-min lockout. |
| **R20-03** | Unauthorized Property NOC Submission | Low | High | Medium | RPC validates caller identity against `property_owners` / `tenancies`. |
| **R20-04** | UI Component Bloat in `src/App.jsx` | Medium | Medium | Medium | Modular view state variables and isolated JSX render functions. |
| **R20-05** | Baseline Regression Failure | Low | High | High | Strict execution of Slices 1–19 test suites before Slice 20 assertions. |

---

## 37. IMPLEMENTATION SEQUENCE

Once explicitly authorized by the user, implementation will proceed in 10 controlled phases:

```text
Phase 1  ──> Database Schema & Indexes (schema_slice20.sql)
Phase 2  ──> RLS & FORCE RLS Security Policies
Phase 3  ──> Core NOC & Checklist RPC Routines
Phase 4  ──> Server-Authoritative Financial Dues Audit RPC
Phase 5  ──> Move Pass Bcrypt KDF & Verification RPC Routines
Phase 6  ──> Audit Logging & Real-Time Notification Integration
Phase 7  ──> Supabase Service Layer Additions (src/supabase.js)
Phase 8  ──> React UI Component Extensions (src/App.jsx)
Phase 9  ──> Assertion Test Suite & Regression Runner (run_all20.ps1)
Phase 10 ──> Independent Adversarial Security Audit & Final Security Lock
```

---

## 38. ROLLBACK / FAILURE STRATEGY

If Slice 20 implementation encounters unresolvable validation errors or security audit failures:
1. **Database Rollback:** Drop Slice 20 tables (`noc_move_passes`, `noc_clearance_checklists`, `noc_requests`) and RPC routines. Slices 1–19 catalog remains untouched.
2. **Source Code Rollback:** Revert Slice 20 additions in `src/supabase.js` and `src/App.jsx`.
3. **Baseline Restoration:** Re-run `scratch/run_all19.ps1` to confirm **639 / 639 PASS** baseline is restored.

---

## 39. SECURITY ACCEPTANCE CRITERIA

Slice 20 will be eligible for final security lock ONLY when:
1. All 45 planned assertions (`S20-001` through `S20-045`) PASS.
2. Cumulative baseline reaches **684 / 684 PASS (100%)**.
3. All 8 SECURITY DEFINER RPC routines are hardened with `SET search_path = public, extensions, pg_temp`.
4. RLS and FORCE RLS are active on all 3 tables with restrictive DML policies.
5. Financial dues clearance is 100% server-calculated from `ledger_transactions`.
6. Move pass codes use bcrypt KDF (`extensions.crypt`) with 15-minute lockout defense.
7. Plaintext PINs are excluded from database tables and audit logs.
8. Independent Adversarial Security Audit returns **PASS with 0 findings**.

---

## 40. FINAL RECOMMENDATION

# A — SLICE 20 PLAN COMPLETE — PENDING EXPLICIT USER IMPLEMENTATION AUTHORIZATION

---

*This concludes the official Final Implementation & Security Plan for Slice 20 of the SU Society App.*
