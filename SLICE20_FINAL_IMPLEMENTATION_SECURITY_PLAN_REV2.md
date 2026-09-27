# SLICE 20 — FINAL IMPLEMENTATION & SECURITY PLAN (REVISION 2)

**Execution Date:** September 7, 2026  
**Target Repository:** `D:\Clients Applications\SU Society App`  
**Mode:** **PLAN REVISION ONLY / ZERO IMPLEMENTATION AUTHORIZATION**  
**Slice:** 20  
**Feature:** Resident Move-In / Move-Out Digital NOC Clearance & Property Transfer Workflow  
**Current Locked Baseline:** **639 / 639 PASS (100%)**  
**Locked Scope:** **SLICES 1–19 — IMMUTABLE**  

---

## 1. EXECUTIVE SUMMARY

This document establishes the authoritative, implementation-ready **Final Implementation & Security Plan (Revision 2)** for **Slice 20 — Resident Move-In / Move-Out Digital NOC Clearance Requests & Property Transfer Workflow** of the SU Society App.

Revision 2 is the product of an exhaustive, fresh adversarial security and architectural audit of the initial Slice 20 plan. It resolves 20 critical security, financial-integrity, state-machine, cryptographic, lookup, vehicle-binding, role-segregation, and concurrency gaps.

### Key Highlights of Revision 2:
1. **Zero Code / DB Mutation:** This is a planning and architecture document only. No application source code, database schema, RPC routines, RLS policies, or verification scripts have been executed or modified during this planning revision.
2. **Locked Baseline Protection:** Slices 1–19 remain locked and immutable (**639 / 639 PASS**).
3. **Approval-Time Financial Revalidation (Staleness Protection):** Solves Critical Gap #1. `approve_noc_request` executes atomic revalidation of ledger balance under `FOR UPDATE` row locking. NOC approval is denied if dues have accrued since initial financial clearance.
4. **Authoritative Financial Balance Semantics:** Solves Critical Gap #2. Reuses `SUM(debit) - SUM(credit)` ledger semantics. Balance = 0 (cleared), > 0 (dues present / denied), < 0 (credit advance / cleared). Zero financial transaction mutations occur.
5. **CSPRNG PIN & Public Token Lookup:** Solves Critical Gaps #4 & #5. Replaces `random()` with CSPRNG `extensions.gen_random_bytes(4)` for 6-digit PIN generation. Introduces public lookup `pass_token` (`PASS-2026-XXXXX`) to eliminate high-CPU $O(N)$ bcrypt table scanning.
6. **Multi-Vector Rate Limiting:** Solves Critical Gap #6. Implements per-pass lockout (5 failed attempts -> 15 min pass lockout) AND per-gatekeeper session lockout (10 failed attempts in 10 mins across any pass -> 15 min gatekeeper lockout).
7. **Server-Authoritative Vehicle Binding:** Solves Critical Gap #7. Enforces SQL vehicle registration normalization `UPPER(REGEXP_REPLACE(vehicle, '[^A-Za-z0-9]', ''))` and mandatory gatekeeper verification match.
8. **Departmental Checklist Role Segregation:** Solves Critical Gap #8. Enforces role-based category sign-offs (`treasurer` for financial dues, `technician` for facility inspection, `admin` for keys/access, `secretary` for final sign-off).
9. **Owner-Only Property Sale NOC & Scope Boundary:** Solves Critical Gaps #10 & #29. `property_sale_noc` submission is restricted to primary property owners. Ownership transfer remains strictly deferred to Slice 24. Move-out check-out verification executes server-authoritative tenancy termination (`end_date = CURRENT_DATE`).
10. **Generic Oracle Resistance & Redaction:** Solves Critical Gaps #15 & #16. Returns generic error code `22000` on verification failures. Excludes PINs, passcodes, and hashes from audit logs and notifications.
11. **Expanded Assertion Matrix:** 52 planned assertions (`S20-001` through `S20-052`), raising the cumulative verified target to **691 / 691 PASS**.

---

## 2. REVISION 2 REASON & SECURITY GAP REMEDIATION MATRIX

Adversarial audit of the original Slice 20 plan identified 20 critical security, architectural, and financial risks. Revision 2 addresses every gap as follows:

| Gap ID | Description | Original Vulnerability | Revision 2 Architecture Remediation |
| :--- | :--- | :--- | :--- |
| **GAP-01** | Financial Clearance Staleness | NOC approved based on stale `cleared` checklist item even if new ledger dues posted. | `approve_noc_request` executes atomic revalidation of `ledger_transactions` balance under row lock. Aborts if balance > 0. |
| **GAP-02** | Balance Semantics | Ambiguous `balance <= 0` check without credit balance handling. | Authoritative formula `SUM(debit) - SUM(credit)`. Balance = 0 (cleared), > 0 (denied), < 0 (credit / cleared). |
| **GAP-03** | Move Pass Lifecycle | Single pass with ambiguous check-in vs check-out semantics. | Explicit move direction (`in` / `out`) & state machine (`issued` -> `active` -> `checked_in` / `checked_out` -> `completed`). |
| **GAP-04** | Cryptographic PIN Generation | Non-cryptographic `100000 + floor(random()*900000)` PRNG generation. | CSPRNG `extensions.gen_random_bytes(4)` derived 6-digit PIN + bcrypt `gen_salt('bf', 8)` salted KDF. |
| **GAP-05** | Pass Lookup & Brute-Force Scanning | RPC `verify_noc_move_pass(p_pass_code)` scanned all active bcrypt hashes in DB ($O(N)$ CPU exhaustion). | Public lookup `pass_token` (`PASS-2026-XXXXX`) + secret 6-digit PIN. $O(1)$ index lookup before bcrypt verification. |
| **GAP-06** | Rate Limiting Surface | Single counter per pass; vulnerable to distributed guessing. | Dual-tier rate limiting: 5 failed attempts per pass -> 15 min pass lockout; 10 failures in 10 mins per guard -> 15 min guard lockout. |
| **GAP-07** | Vehicle Registration Binding | Loose optional text field without format normalization or enforcement. | Server-side normalization `UPPER(REGEXP_REPLACE(reg, '[^A-Z0-9]', ''))`. Gatekeeper must supply exact matching vehicle reg. |
| **GAP-08** | Checklist Role Segregation | Broad Admin/Treasurer sign-off across all checklist categories. | Strict category roles: `treasurer` (dues), `technician` (facility), `admin` (keys/access), `secretary` (admin sign-off). |
| **GAP-09** | Property / Tenancy Mutation | Ambiguous tenancy state changes on move completion. | Atomic server-side tenancy termination (`end_date = CURRENT_DATE`, `status = 'terminated'`) upon move-out gate check-out. |
| **GAP-10** | Property Sale NOC Scope | Risk of unauthorized tenant submission or legal ownership mutation. | `property_sale_noc` restricted to primary property owners. Ownership transfer execution DEFERRED to Slice 24. |
| **GAP-11** | Document Security & Evidence | Storage bucket & upload complexity. | Document uploads DEFERRED. Text-based `evidence_reference` supported with strict RLS visibility and credential redaction. |
| **GAP-12** | NOC Approval Atomicity | Multi-step approval prone to partial completion or race conditions. | `approve_noc_request` executes in single atomic transaction: row lock -> revalidate dues -> check checklist -> generate NOC cert. |
| **GAP-13** | Concurrent Checklist Modification | Admin A clears while Admin B flags or Secretary approves concurrently. | All checklist modifications lock parent `noc_requests` row `FOR UPDATE` before reading or updating checklist items. |
| **GAP-14** | Pass Concurrency & Replay | Simultaneous gate verification attempts by multiple gatekeepers. | Gate verification locks `noc_move_passes` row `FOR UPDATE`. Atomic transition `status = 'active'` -> `'used'`. |
| **GAP-15** | Generic Oracle Resistance | Detailed error messages leaked pass existence, expiry, or PIN validity. | Gate verification RPC returns generic error `22000` ("Invalid move pass credentials or pass expired/locked.") for all failure modes. |
| **GAP-16** | Audit Redaction Policy | Potential logging of plaintext PINs or pass hashes. | Plaintext PINs and bcrypt hashes stripped from audit `old_data`/`new_data` JSON payloads. Only tokens and status logged. |
| **GAP-17** | Notification Security | Risk of sending sensitive PINs or financial balances in push alerts. | Notifications contain high-level status alerts only. PINs never sent via notifications. Recipient user IDs strictly scoped. |
| **GAP-18** | RLS & FORCE RLS Defense | Risk of client API direct table DML bypass. | `ENABLE` & `FORCE RLS` on all 3 tables with restrictive `USING (false) WITH CHECK (false)` policies blocking direct DML. |
| **GAP-19** | SECURITY DEFINER Hardening | Privileged escalation risk in database routines. | All 8 RPCs set `SET search_path = public, extensions, pg_temp` and validate caller `auth.uid()`, society ID, and RBAC roles. |
| **GAP-20** | State Machine Completeness | Undefined expiry, cancellation, or rejection transition paths. | Comprehensive transition matrix covering move-in, move-out, property sale, rejection, cancellation, and expiration. |

---

## 3. LOCKED BASELINE

The following project baseline is authoritative and permanently locked:

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

## 4. SOURCE & DATABASE INSPECTION EVIDENCE

Read-only inspection of the repository and active PostgreSQL catalog confirms:
1. **RBAC Infrastructure (`schema_slice1.sql`):**
   - Helper functions: `public.is_admin(uid UUID DEFAULT auth.uid())` -> `BOOLEAN`, `public.has_role(uid UUID, p_role TEXT)` -> `BOOLEAN` (2 arguments), `public.get_user_society_id(uid UUID DEFAULT auth.uid())` -> `UUID`.
   - Table `public.user_roles` supports roles: `super_admin`, `admin`, `secretary`, `treasurer`, `executive_member`, `member`, `tenant`, `gatekeeper`, `technician`.
2. **Financial Ledger Infrastructure (`schema_slice2.sql`, `schema_slice9.sql`, `schema_slice14.sql`):**
   - Property balances are calculated as `SUM(debit amount) - SUM(credit amount)` from `public.ledger_transactions`.
   - Financial ledger is strictly immutable. Slice 20 executes zero DML against ledger tables.
3. **Audit Log Infrastructure (`schema_slice18.sql`):**
   - `public.audit_logs` requires `society_id`, `actor_id`, `entity_type`, `entity_id`, `action`, `old_data`, `new_data`.
4. **Gate Security & Cryptographic Standards (`schema_slice19.sql`):**
   - Uses `extensions.crypt` with `extensions.gen_salt('bf', 8)` for salted bcrypt KDF.
   - Enforces 15-minute lockout window via `lockout_until` column.

---

## 5. BUSINESS OBJECTIVE

Residential community management requires strict digital governance over resident move-in, move-out, and property sale processes:
1. **Financial Risk Mitigation:** Prevent resident move-out prior to complete settlement of maintenance dues.
2. **Property & Asset Inspection:** Ensure common areas, building structures, RFID cards, and clubhouse keys are inspected and accounted for before resident departure.
3. **Property Sale Administrative Clearance:** Provide formal society NOC certificates for title transfers without prematurely altering legal ownership records.
4. **Secure Mover Access Control:** Provide security gatekeepers with verifiable, time-bound, cryptographically sound move passes to control mover truck entry/exit without exposing resident credentials or creating reusable gate bypass passes.

---

## 6. FINAL SLICE 20 SCOPE

### INCLUDED IN SLICE 20:
1. **NOC Application Submission:** Requesters submit NOC requests for `move_in`, `move_out`, or `property_sale_noc`. `property_sale_noc` is strictly restricted to primary property owners.
2. **Automated Financial Dues Audit & Approval-Time Revalidation:** Server-side net dues calculation from `ledger_transactions`. Mandatory approval-time revalidation under row locking to prevent stale clearance.
3. **Departmental Checklist Management & Role Segregation:** Category-specific sign-off enforcement (`treasurer` for dues, `technician` for facility inspection, `admin` for access keys, `secretary` for final sign-off).
4. **Digital NOC Certificate Generation:** Unique certificate reference (`NOC-2026-YYYYYY`) generated upon 100% checklist sign-off.
5. **CSPRNG Move Pass Code Generation:** 6-digit PIN generated via CSPRNG `extensions.gen_random_bytes(4)` and stored as bcrypt hash (`gen_salt('bf', 8)`). Public `pass_token` (`PASS-2026-XXXXX`) generated for $O(1)$ gate lookup. Plaintext PIN returned exactly once in creation RPC response.
6. **Gatekeeper Move Pass Verification & Rate-Limiting:** Verification of `pass_token` + PIN + normalized vehicle registration. Per-pass and per-gatekeeper lockout enforcement.
7. **Server-Authoritative Tenancy Termination:** Move-out gate check-out verification sets tenancy `end_date = CURRENT_DATE` and `status = 'terminated'` for departing tenants.
8. **Audit Logging & Redaction:** Audit tracking for all NOC transitions with sensitive payload redaction.

### EXCLUDED / DEFERRED FROM SLICE 20:
* **Property Ownership Record Mutation:** Mutation of `public.property_owners` is **DEFERRED to Slice 24 (Legal & Membership Transfer)**.
* **Document File Upload Management:** Storage bucket creation and file uploads are **DEFERRED**. Text evidence references supported.
* **Financial Ledger Transactions / Refunds / Deposits:** Financial ledger mutations remain strictly **EXCLUDED**.

---

## 7. MOVE-IN WORKFLOW

```text
[ Resident / Owner / Tenant ]
             │
             ▼ (Submit Move-In NOC Request)
┌─────────────────────────────────────────────────────────────┐
│ NOC Request Created (status = 'submitted')                  │
│ 4 Checklist Items Initialized (Dues, Facility, Keys, Admin) │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼ (Department Clearance)
┌─────────────────────────────────────────────────────────────┐
│ Financial Dues Audit -> Cleared (Balance <= 0)              │
│ Facility Inspection & Keys Return Clearance                 │
│ Status = 'clearance_in_progress'                            │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼ (Secretary Approval)
┌─────────────────────────────────────────────────────────────┐
│ Lock NOC Row -> Revalidate Dues -> Verify 100% Cleared      │
│ Status = 'approved', Digital NOC Certificate Issued         │
│ Move Pass Generated (CSPRNG PIN + Bcrypt Hash + Token)      │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼ (Move Day Gate Verification)
┌─────────────────────────────────────────────────────────────┐
│ Gatekeeper Scans pass_token + Enters PIN + Vehicle Reg      │
│ RPC verifies Token -> PIN Hash -> Vehicle Reg Match         │
│ Status = 'checked_in' -> Request Status = 'completed'       │
└─────────────────────────────────────────────────────────────┘
```

---

## 8. MOVE-OUT WORKFLOW

```text
[ Resident / Tenant / Owner ]
             │
             ▼ (Submit Move-Out NOC Request)
┌─────────────────────────────────────────────────────────────┐
│ NOC Request Created (status = 'submitted')                  │
│ Checklist Items Initialized (Dues, Damage, Keys, Admin)     │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼ (Automated Dues Audit & Sign-off)
┌─────────────────────────────────────────────────────────────┐
│ System queries ledger_transactions server-side:             │
│   • Outstanding Dues > 0  ──> Financial Clearance FLAGGED   │
│   • Outstanding Dues <= 0 ──> Financial Clearance CLEARED   │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼ (Facility Inspection & Keys Return)
┌─────────────────────────────────────────────────────────────┐
│ Technician clears Facility Inspection                       │
│ Admin clears Keys & Access Cards Return                     │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼ (Secretary Approval & Pass Generation)
┌─────────────────────────────────────────────────────────────┐
│ Lock NOC Row -> Revalidate Dues -> Approve NOC             │
│ Generate Move-Out Pass (pass_token + Bcrypt PIN)            │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼ (Gate Check-Out & Tenancy Termination)
┌─────────────────────────────────────────────────────────────┐
│ Mover Truck Verified at Gate (Token + PIN + Vehicle Reg)   │
│ Status = 'checked_out' -> Request Status = 'completed'      │
│ Tenancy Status Updated to 'terminated' (end_date=NOW)       │
└─────────────────────────────────────────────────────────────┘
```

---

## 9. PROPERTY SALE NOC SCOPE & DECISION

### Scope Rules:
1. **Requester Authorization:** `submit_noc_request` for `request_type = 'property_sale_noc'` strictly validates that `auth.uid()` is an active primary owner of the target property in `public.property_owners`. Submissions by tenants or unauthorized users are rejected (`42501`).
2. **Clearance-Only Certificate:** Approval of `property_sale_noc` generates an administrative clearance certificate (`NOC-2026-YYYYYY`) confirming zero financial dues and administrative clearance.
3. **Zero Ownership Mutation:** Approval or completion of `property_sale_noc` **DOES NOT** insert, delete, or update rows in `public.property_owners`. Ownership reassignment requires title deed legal verification, board resolution, and membership transfer fees, which belong exclusively to **Slice 24 (Legal Property Transfer)**.

---

## 10. COMPLETE NOC STATE MACHINE

The NOC request state machine is strictly enforced server-side via RPC routines under `FOR UPDATE` row locking:

| Current State | Next State | Authorized Actor | Preconditions & Validation | DB Enforcement | Audit Event |
| :--- | :--- | :--- | :--- | :--- | :--- |
| *None* | `submitted` | Resident (Owner/Tenant) | Requester authorized for property; `property_sale_noc` requires primary owner; no active NOC exists. | Partial Unique Index `uq_active_noc_request` | `noc_request_submitted` |
| `submitted` | `dues_pending` | Treasurer / System RPC | Dues audit executed; net ledger balance > 0. | RPC `perform_financial_dues_clearance` | `noc_dues_audit_flagged` |
| `submitted` / `dues_pending` | `clearance_in_progress` | Department Roles | Net ledger balance <= 0; checklist items open. | RPC state check | `noc_clearance_started` |
| `clearance_in_progress` | `approved` | Secretary / Admin | Dues revalidated balance <= 0; 100% of checklist items status = `'cleared'`. | Atomic RPC transaction with `FOR UPDATE` | `noc_request_approved` |
| `submitted` / `dues_pending` / `clearance_in_progress` | `rejected` | Admin / Secretary | Outstanding dues unpaid or facility inspection failed; rejection reason provided. | RPC `reject_noc_request` | `noc_request_rejected` |
| `submitted` / `dues_pending` / `clearance_in_progress` | `cancelled` | Requester Resident | Request in non-final state; `auth.uid() = requester_id`. | Requester identity match | `noc_request_cancelled` |
| `approved` | `completed` | Gatekeeper (Guard) | Move pass validated at gate; mover truck check-in/out timestamped. | RPC `verify_noc_move_pass` | `noc_move_completed` |
| `approved` | `expired` | System RPC / Cron | `move_date` passed + 48 hours without gate verification. | Expiry state check | `noc_request_expired` |

---

## 11. DATABASE MODEL & PROPOSED TABLES

Slice 20 introduces 3 core domain tables to `public` schema:

```text
┌────────────────────────────────┐       ┌──────────────────────────────────────┐
│       public.noc_requests      │       │   public.noc_clearance_checklists    │
├────────────────────────────────┤       ├──────────────────────────────────────┤
│ id (PK)                        │1     N│ id (PK)                              │
│ society_id (FK)                │◄──────│ noc_request_id (FK)                  │
│ property_id (FK)               │       │ clearance_category                   │
│ unit_id (FK)                   │       │ status ('pending','cleared','flagged')│
│ requester_id (FK)              │       │ remarks                              │
│ request_type                   │       │ cleared_by (FK)                      │
│ status                         │       │ cleared_at                           │
│ move_date                      │       └──────────────────────────────────────┘
│ reason_notes / evidence_ref    │
│ rejection_reason               │
│ certificate_number             │
│ created_at / updated_at        │
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
│ pass_token (UNIQUE INDEX)      │-- Public Lookup Token (PASS-2026-XXXXX)
│ pass_code_hash (Bcrypt KDF)    │-- Hashed 6-Digit PIN
│ valid_from / valid_until       │
│ authorized_vehicle_number      │-- Normalized Vehicle Reg (UPPER ALPHANUMERIC)
│ mover_details                  │
│ move_direction ('in', 'out')   │
│ status ('active','used','exp') │
│ failed_attempts                │
│ lockout_until                  │
│ check_in_time / check_out_time │
│ gatekeeper_id (FK)             │
└────────────────────────────────┘
```

### 1. `public.noc_requests`
```sql
CREATE TABLE IF NOT EXISTS public.noc_requests (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id          UUID        NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    property_id         UUID        NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
    unit_id             UUID        REFERENCES public.units(id) ON DELETE RESTRICT,
    requester_id        UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    request_type        VARCHAR(30) NOT NULL CONSTRAINT chk_noc_request_type CHECK (
                                        request_type IN ('move_in', 'move_out', 'property_sale_noc')
                                    ),
    status              VARCHAR(30) NOT NULL DEFAULT 'submitted' CONSTRAINT chk_noc_status CHECK (
                                        status IN ('submitted', 'dues_pending', 'clearance_in_progress', 'approved', 'rejected', 'cancelled', 'completed', 'expired')
                                    ),
    move_date           DATE        NOT NULL,
    reason_notes        TEXT,
    evidence_reference  TEXT,
    rejection_reason    TEXT,
    certificate_number  VARCHAR(60),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### 2. `public.noc_clearance_checklists`
```sql
CREATE TABLE IF NOT EXISTS public.noc_clearance_checklists (
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
CREATE TABLE IF NOT EXISTS public.noc_move_passes (
    id                          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    noc_request_id              UUID        NOT NULL UNIQUE REFERENCES public.noc_requests(id) ON DELETE CASCADE,
    pass_token                  VARCHAR(50) NOT NULL UNIQUE,
    pass_code_hash              VARCHAR(255) NOT NULL,
    valid_from                  TIMESTAMPTZ NOT NULL,
    valid_until                 TIMESTAMPTZ NOT NULL,
    authorized_vehicle_number   VARCHAR(30),
    mover_details               TEXT,
    move_direction              VARCHAR(10) NOT NULL DEFAULT 'out' CONSTRAINT chk_pass_direction CHECK (move_direction IN ('in', 'out')),
    status                      VARCHAR(30) NOT NULL DEFAULT 'active' CONSTRAINT chk_move_pass_status CHECK (
                                                status IN ('active', 'used', 'expired', 'revoked')
                                            ),
    failed_attempts             INTEGER     NOT NULL DEFAULT 0 CONSTRAINT chk_pass_failed_attempts CHECK (failed_attempts >= 0),
    lockout_until               TIMESTAMPTZ,
    check_in_time               TIMESTAMPTZ,
    check_out_time              TIMESTAMPTZ,
    gatekeeper_id               UUID        REFERENCES public.users(id) ON DELETE RESTRICT,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_pass_validity_window CHECK (valid_from < valid_until)
);
```

---

## 12. CONSTRAINTS & INDEXES

### Partial Unique Indexes:
1. **Single Active NOC Request Per Property & Request Type:**
   ```sql
   CREATE UNIQUE INDEX IF NOT EXISTS uq_active_noc_request 
   ON public.noc_requests (property_id, request_type) 
   WHERE status IN ('submitted', 'dues_pending', 'clearance_in_progress', 'approved');
   ```
2. **Single Active Move Pass Per NOC Request:**
   ```sql
   CREATE UNIQUE INDEX IF NOT EXISTS uq_active_noc_move_pass 
   ON public.noc_move_passes (noc_request_id) 
   WHERE status = 'active';
   ```
3. **Public Pass Token Index ($O(1)$ Gate Verification Lookup):**
   ```sql
   CREATE UNIQUE INDEX IF NOT EXISTS idx_noc_move_passes_token 
   ON public.noc_move_passes (pass_token);
   ```

---

## 13. RLS / FORCE RLS DESIGN

All 3 tables strictly enforce `ENABLE` and `FORCE ROW LEVEL SECURITY`:

```sql
ALTER TABLE public.noc_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.noc_requests FORCE ROW LEVEL SECURITY;

ALTER TABLE public.noc_clearance_checklists ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.noc_clearance_checklists FORCE ROW LEVEL SECURITY;

ALTER TABLE public.noc_move_passes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.noc_move_passes FORCE ROW LEVEL SECURITY;
```

### Restrictive DML Direct Access Blocking:
Direct `INSERT`, `UPDATE`, and `DELETE` from client connections are strictly blocked across all 3 tables:

```sql
CREATE POLICY pol_noc_requests_restrictive_insert ON public.noc_requests AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (false);
CREATE POLICY pol_noc_requests_restrictive_update ON public.noc_requests AS RESTRICTIVE FOR UPDATE TO authenticated USING (false);
CREATE POLICY pol_noc_requests_restrictive_delete ON public.noc_requests AS RESTRICTIVE FOR DELETE TO authenticated USING (false);

-- (Identical restrictive DML policies applied to noc_clearance_checklists and noc_move_passes)
```

### Permissive `SELECT` Policies:
* `noc_requests`: Requesters can view their own requests (`requester_id = auth.uid()`); admins/treasurers/secretaries can view requests within their society.
* `noc_clearance_checklists`: Visible to requesters and authorized society admin roles.
* `noc_move_passes`: Requesters can view pass metadata (excluding `pass_code_hash`); gatekeepers and admins can view pass metadata.

---

## 14. SECURITY DEFINER RPC ARCHITECTURE

All business logic is encapsulated in 8 hardened `SECURITY DEFINER` procedures specifying `SET search_path = public, extensions, pg_temp`:

### 1. `public.submit_noc_request`
* **Signature:** `(p_property_id UUID, p_request_type TEXT, p_move_date DATE, p_reason_notes TEXT DEFAULT NULL) -> JSONB`
* **Security Controls:** Validates `auth.uid() IS NOT NULL`. Verifies requester is owner/tenant of property. If `p_request_type = 'property_sale_noc'`, strictly validates caller is primary property owner. Inserts `noc_requests` row. Initializes 4 checklist items (`financial_dues`, `facility_inspection`, `keys_access_cards`, `admin_signoff`). Logs audit event.

### 2. `public.perform_financial_dues_clearance`
* **Signature:** `(p_noc_request_id UUID) -> JSONB`
* **Security Controls:** Caller authorization check (`treasurer`, `admin`, `super_admin`). Calculates net balance from `ledger_transactions` (`SUM(debit) - SUM(credit)`). Sets `financial_dues` checklist status to `cleared` (if balance <= 0) or `flagged` (if balance > 0).

### 3. `public.update_clearance_checklist_item`
* **Signature:** `(p_noc_request_id UUID, p_category TEXT, p_status TEXT, p_remarks TEXT DEFAULT NULL) -> JSONB`
* **Security Controls:** Category-specific RBAC segregation:
  - `financial_dues`: `treasurer`, `admin`, `super_admin`
  - `facility_inspection`: `technician`, `admin`, `super_admin`
  - `keys_access_cards`: `admin`, `super_admin`
  - `admin_signoff`: `secretary`, `admin`, `super_admin`
  Locks parent `noc_requests` row `FOR UPDATE`. Updates checklist item state.

### 4. `public.approve_noc_request`
* **Signature:** `(p_noc_request_id UUID) -> JSONB`
* **Security Controls:** Authorization check (`secretary`, `admin`, `super_admin`). Atomic transaction:
  1. Lock `noc_requests` row `FOR UPDATE`.
  2. Revalidate dues in `ledger_transactions`. Abort if balance > 0 (`22000`).
  3. Verify 100% of items in `noc_clearance_checklists` status = `'cleared'`. Abort if any item is pending/flagged (`22000`).
  4. Update request status = `'approved'`.
  5. Generate certificate number `NOC-2026-YYYYYY`.

### 5. `public.reject_noc_request`
* **Signature:** `(p_noc_request_id UUID, p_rejection_reason TEXT) -> JSONB`
* **Security Controls:** Authorization check (`admin`, `secretary`, `treasurer`). Updates request status = `'rejected'`. Logs audit entry.

### 6. `public.cancel_noc_request`
* **Signature:** `(p_noc_request_id UUID) -> JSONB`
* **Security Controls:** Validates `auth.uid() = requester_id`. Transitions non-final request status to `'cancelled'`.

### 7. `public.generate_noc_move_pass`
* **Signature:** `(p_noc_request_id UUID, p_valid_from TIMESTAMPTZ, p_valid_until TIMESTAMPTZ, p_authorized_vehicle_number TEXT DEFAULT NULL, p_mover_details TEXT DEFAULT NULL, p_direction TEXT DEFAULT 'out') -> JSONB`
* **Security Controls:** Verifies NOC request status = `'approved'`. Generates CSPRNG 6-digit PIN using `extensions.gen_random_bytes(4)`. Hashes PIN using `extensions.crypt(v_pin, extensions.gen_salt('bf', 8))`. Generates public lookup token `PASS-2026-XXXXX`. Normalizes vehicle registration. **Returns plaintext PIN EXACTLY ONCE in creation JSON payload.**

### 8. `public.verify_noc_move_pass`
* **Signature:** `(p_pass_token TEXT, p_pass_code TEXT, p_vehicle_number TEXT DEFAULT NULL, p_direction TEXT DEFAULT 'out') -> JSONB`
* **Security Controls:** Gatekeeper authorization (`has_role(auth.uid(), 'gatekeeper')` or `is_admin()`). $O(1)$ index lookup by `pass_token`. Evaluates per-pass and per-gatekeeper lockouts. Compares bcrypt hash. Validates normalized vehicle registration match. Atomic state update `status = 'active'` -> `'used'`. On move-out completion, executes server-authoritative tenancy termination (`end_date = CURRENT_DATE`). Returns generic error `22000` on any validation failure.

---

## 15. AUTHENTICATION & TENANT ISOLATION

All Slice 20 RPCs enforce strict authentication and multi-tenant society isolation:

```sql
-- 1. Authentication Check
IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
END IF;

-- 2. Multi-Tenant Society Isolation Check
v_caller_society := public.get_user_society_id(auth.uid());
IF v_caller_society IS NULL OR v_caller_society <> v_request_society_id THEN
    RAISE EXCEPTION 'Cross-society execution denied.' USING ERRCODE = '42501';
END IF;
```

---

## 16. PROPERTY OWNERSHIP / TENANCY SECURITY

When `submit_noc_request` is called, the database verifies that `auth.uid()` holds valid authorization for the target property:

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

IF NOT v_is_authorized AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'User is not authorized for target property.' USING ERRCODE = '42501';
END IF;

-- Property Sale NOC Owner-Only Rule
IF p_request_type = 'property_sale_noc' THEN
    SELECT EXISTS (
        SELECT 1 FROM public.property_owners 
        WHERE property_id = p_property_id AND owner_id = auth.uid() 
          AND (end_date IS NULL OR end_date >= CURRENT_DATE)
    ) INTO v_is_owner;
    
    IF NOT v_is_owner AND NOT public.is_admin() THEN
        RAISE EXCEPTION 'Property sale NOC can only be initiated by primary owner.' USING ERRCODE = '42501';
    END IF;
END IF;
```

---

## 17. FINANCIAL CLEARANCE & BALANCE SEMANTICS

Financial dues clearance is **100% server-authoritative**. The client cannot pass a boolean flag or self-certify dues.

### Net Balance Calculation SQL:
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
    v_remarks := 'Financial dues cleared. Net balance is zero or credit.';
END IF;
```

---

## 18. FINANCIAL STALENESS PROTECTION

To solve Critical Gap #1, `approve_noc_request` executes **approval-time revalidation**:

```sql
-- Lock NOC request row
SELECT * INTO v_noc FROM public.noc_requests WHERE id = p_noc_request_id FOR UPDATE;

-- Revalidate current property dues atomically
SELECT COALESCE(SUM(
    CASE WHEN direction = 'debit' THEN amount ELSE -amount END
), 0.00)
INTO v_current_balance
FROM public.ledger_transactions
WHERE society_id = v_noc.society_id 
  AND property_id = v_noc.property_id 
  AND scope = 'property';

IF v_current_balance > 0 THEN
    -- Automatically flag financial checklist item
    UPDATE public.noc_clearance_checklists 
    SET status = 'flagged', remarks = format('Stale clearance detected. Dues accrued: INR %s', v_current_balance)
    WHERE noc_request_id = p_noc_request_id AND clearance_category = 'financial_dues';
    
    RAISE EXCEPTION 'NOC Approval Denied: Outstanding dues detected during approval revalidation.' USING ERRCODE = '22000';
END IF;
```

---

## 19. FINANCIAL NON-INTERFERENCE

Slice 20 is strictly **read-only** regarding financial ledgers:
* Zero `INSERT`, `UPDATE`, or `DELETE` statements target `public.ledger_transactions`.
* Zero modification of `public.payments` or `public.maintenance_charges`.
* Reads net property balances strictly to evaluate checklist sign-off.

---

## 20. DEPARTMENTAL CHECKLIST ROLE SEGREGATION

Clearance checklist category sign-offs are strictly segregated by role in `update_clearance_checklist_item`:

```sql
IF p_category = 'financial_dues' AND NOT (public.has_role(v_caller, 'treasurer') OR public.is_admin()) THEN
    RAISE EXCEPTION 'Access Denied: Treasurer role required for financial dues clearance.' USING ERRCODE = '42501';
ELSIF p_category = 'facility_inspection' AND NOT (public.has_role(v_caller, 'technician') OR public.is_admin()) THEN
    RAISE EXCEPTION 'Access Denied: Technician or Admin role required for facility clearance.' USING ERRCODE = '42501';
ELSIF p_category = 'keys_access_cards' AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Access Denied: Admin role required for keys/access card return clearance.' USING ERRCODE = '42501';
ELSIF p_category = 'admin_signoff' AND NOT (public.has_role(v_caller, 'secretary') OR public.is_admin()) THEN
    RAISE EXCEPTION 'Access Denied: Secretary or Admin role required for final admin sign-off.' USING ERRCODE = '42501';
END IF;
```

---

## 21. MOVE PASS CRYPTOGRAPHY & LOOKUP MODEL

1. **CSPRNG PIN Generation:** 6-digit PIN generated via `extensions.gen_random_bytes(4)`.
2. **Salted Bcrypt KDF:** PIN stored as `extensions.crypt(v_pin, extensions.gen_salt('bf', 8))`.
3. **Public Pass Token Lookup ($O(1)$):** Pass token `pass_token` (`PASS-2026-XXXXX`) generated for fast indexed lookup, eliminating high-CPU table scans.
4. **One-Time PIN Exposure:** Plaintext PIN returned exactly once in creation payload. Never stored in tables or logs.

---

## 22. DUAL-TIER RATE LIMITING & LOCKOUT DEFENSE

1. **Per-Pass Lockout:** 5 failed verification attempts on a `pass_token` sets `lockout_until = NOW() + INTERVAL '15 minutes'`.
2. **Per-Gatekeeper Lockout:** 10 failed pass verifications within 10 minutes by a specific gatekeeper user ID locks gatekeeper verification for 15 minutes.
3. **Atomic Failure Counter:** Counter increments executed inside `FOR UPDATE` transaction. Successful verification resets `failed_attempts` to 0.

---

## 23. SERVER-AUTHORITATIVE VEHICLE BINDING

Vehicle registration numbers are normalized using SQL:
`v_norm_veh := UPPER(REGEXP_REPLACE(p_vehicle_number, '[^A-Za-z0-9]', '', 'g'));`

If `authorized_vehicle_number` is populated on the pass, gatekeeper verification MUST supply matching normalized registration. Mismatch increments `failed_attempts` and returns generic error `22000`.

---

## 24. GATEKEEPER VERIFICATION WORKFLOW

```text
[ Mover Vehicle Arrives at Security Gate ]
                   │
                   ▼
[ Guard Inputs pass_token, 6-Digit PIN & Vehicle Registration ]
                   │
                   ▼ (Invokes verify_noc_move_pass)
┌─────────────────────────────────────────────────────────────┐
│ DB RPC Verification:                                        │
│  1. Check auth.uid() has 'gatekeeper' or admin role        │
│  2. Index lookup WHERE pass_token = p_pass_token            │
│  3. Check per-pass & per-guard lockout_until <= NOW()       │
│  4. Check crypt(PIN, pass_code_hash) == pass_code_hash      │
│  5. Check normalized vehicle reg match                      │
│  6. Check NOW() BETWEEN valid_from AND valid_until          │
└──────────────┬──────────────────────────────┬───────────────┘
               │                              │
          (Pass Valid)                  (Pass Invalid)
               │                              │
               ▼                              ▼
┌──────────────────────────────┐┌──────────────────────────────┐
│  • Record check_in/out_time  ││  • Increment failed_attempts │
│  • Update pass status='used' ││  • Lockout if attempts >= 5  │
│  • Execute tenancy end_date  ││  • Log audit failure reason  │
│  • Log audit success         ││  • Raise Error 22000         │
│  • Grant Gate Entry / Exit   │└──────────────────────────────┘
└──────────────────────────────┘
```

---

## 25. PROPERTY / TENANCY MUTATION BOUNDARY

When `verify_noc_move_pass` successfully verifies a move-out pass (`move_direction = 'out'`), the RPC automatically executes server-authoritative tenancy termination:

```sql
IF v_pass.move_direction = 'out' AND v_noc.request_type = 'move_out' THEN
    UPDATE public.tenancies
    SET end_date = CURRENT_DATE,
        status = 'terminated',
        updated_at = NOW()
    WHERE property_id = v_noc.property_id 
      AND tenant_id = v_noc.requester_id 
      AND (end_date IS NULL OR end_date >= CURRENT_DATE);
END IF;
```

---

## 26. AUDIT LOGGING & REDACTION

Integrates with Slice 18 immutable audit architecture (`public.audit_logs`).
* **Audited Actions:** `noc_request_submitted`, `noc_dues_audit_executed`, `noc_checklist_updated`, `noc_request_approved`, `noc_request_rejected`, `noc_request_cancelled`, `noc_move_pass_generated`, `noc_move_pass_verified`, `noc_move_pass_failed`.
* **Redaction Policy:** Plaintext PINs and bcrypt pass code hashes are strictly stripped from `old_data` and `new_data` audit JSON payloads.

---

## 27. NOTIFICATION SECURITY

* Real-time notifications emitted via `public.notifications`.
* **Scoping:** Resident alerts sent exclusively to `requester_id`. Admin alerts sent exclusively to society `admin`/`secretary`/`treasurer` roles.
* **Redaction:** Push payload bodies contain state change descriptions only. PINs, passcodes, and financial amounts are strictly excluded.

---

## 28. CONCURRENCY & RACE CONDITION CONTROLS

1. **Concurrent NOC Submissions:** Partial unique index `uq_active_noc_request` blocks duplicate active requests at database level.
2. **Concurrent Checklist & Approval:** All checklist edits and approvals lock parent `noc_requests` row `FOR UPDATE`.
3. **Concurrent Gate Pass Verification:** `verify_noc_move_pass` locks `noc_move_passes` row `FOR UPDATE`. Atomic update `SET status = 'used' WHERE id = v_pass.id AND status = 'active'`.

---

## 29. THREAT MODEL & MITIGATION MATRIX

| Threat ID | Threat Vector | Severity | Mitigation Strategy | Enforcement Layer | Verification Assertion |
| :--- | :--- | :---: | :--- | :--- | :--- |
| **TM20-01** | IDOR / Unauthorized Property NOC Submission | High | RPC verifies `auth.uid()` against `property_owners` / `tenancies`. | RPC Security Gate | `S20-011` |
| **TM20-02** | Cross-Society Data Access / Manipulation | High | Strict `society_id` check via `public.get_user_society_id()`. | RPC Tenant Gate | `S20-010` |
| **TM20-03** | Fake Financial Clearance (Client Dues Bypass) | Critical | Dues clearance is 100% server-calculated in SQL from `ledger_transactions`. | SQL Ledger Query | `S20-017` |
| **TM20-04** | Stale Financial Clearance Attack | High | `approve_noc_request` revalidates current dues balance under row lock. | RPC Approval Gate | `S20-020` |
| **TM20-05** | PIN Brute Force / Timing Attacks | High | CSPRNG 6-digit PIN + bcrypt KDF + $O(1)$ `pass_token` lookup index. | DB Cryptography | `S20-031` |
| **TM20-06** | Multi-Vector Gate Brute-Force Attack | High | Dual-tier rate limiting (5 failures per pass; 10 failures per guard). | RPC Lockout Gate | `S20-039` |
| **TM20-07** | Move Pass Replay Attack | Medium | Atomic state transition `status = 'active'` -> `'used'` under `FOR UPDATE`. | DB Transaction | `S20-041` |
| **TM20-08** | Unauthorized Property Sale NOC Submission | High | `property_sale_noc` restricted to primary property owners in SQL. | RPC Owner Gate | `S20-015` |
| **TM20-09** | Unauthorized Category Checklist Sign-off | Medium | Category-specific RBAC check (`treasurer`, `technician`, `secretary`). | RPC RBAC Gate | `S20-023` |
| **TM20-10** | Oracle Information Leakage via Verification | Medium | Generic error `22000` returned for all verification failure modes. | RPC Exception Handler | `S20-040` |
| **TM20-11** | Plaintext PIN Leakage in Audit Logs | High | Plaintext PINs and bcrypt hashes stripped from audit JSON payloads. | Audit Redactor | `S20-049` |
| **TM20-12** | Direct Client API Table Mutation Bypass | High | `ENABLE` & `FORCE RLS` with restrictive `USING (false)` DML policies. | PostgreSQL RLS Engine | `S20-045` |

---

## 30. UI / UX INTEGRATION PLAN

Application UI extensions will be integrated modularly into `src/App.jsx` and `src/supabase.js`:

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│ SU SOCIETY APP — SLICE 20 DIGITAL NOC & MOVE PASS DASHBOARD                │
├─────────────────────────────────────────────────────────────────────────────┤
│ [Resident View]                                                             │
│  • "Apply for NOC" Modal (Move-In / Move-Out / Property Sale)               │
│  • Real-Time Clearance Progress Tracker (4 Category Badges)                 │
│  • Digital NOC Certificate View & Download                                  │
│  • 6-Digit Move Pass Display (One-Time Copy on Pass Generation)             │
│                                                                             │
│ [Admin / Secretary View]                                                    │
│  • NOC Applications Management Queue                                        │
│  • Departmental Clearance Checklist Sign-Off (Dues, Facility, Keys, Admin)  │
│  • One-Click "Approve NOC" & Certificate Generation                         │
│                                                                             │
│ [Treasurer View]                                                            │
│  • Financial Dues Auto-Audit Panel & Outstanding Balance Summary            │
│                                                                             │
│ [Gatekeeper / Guard View]                                                   │
│  • Security Gate Move Pass Scanner (Token + PIN + Vehicle Reg)              │
│  • Vehicle Registration & Mover Details Entry                               │
│  • Check-In / Check-Out Stamp & Pass Invalidation                           │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 31. ARCHITECTURE REUSE MATRIX

| Component / Module | Existing Source | Reused Capability in Slice 20 |
| :--- | :--- | :--- |
| Tenant Isolation | Slices 1–19 | `public.get_user_society_id(auth.uid())` |
| RBAC Role Helpers | Slice 1 | `public.is_admin()`, `public.has_role(uid, role)` |
| Property / Tenancy | Slices 1 & 2 | `public.properties`, `public.property_owners`, `public.tenancies` |
| Financial Ledgers | Slices 9 & 14 | Read-only dues balance query on `public.ledger_transactions` |
| Audit Logging | Slice 18 | `public.audit_logs` insertion and search_path hardening |
| Passcode Security | Slice 19 | Bcrypt `extensions.crypt(pin, gen_salt('bf', 8))` & lockout pattern |
| Notifications | Slice 4 | `public.notifications` real-time alert dispatch |

---

## 32. CHANGE IMPACT ANALYSIS

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

## 33. REVISED S20 ASSERTION MATRIX

Slice 20 defines **52 detailed test assertions (`S20-001` through `S20-052`)**:

| Test ID | Test Assertion Description | Planned Outcome |
| :--- | :--- | :---: |
| **S20-001** | 3 New NOC Tables Exist (`noc_requests`, `noc_clearance_checklists`, `noc_move_passes`) | PASS |
| **S20-002** | Partial Unique Index `uq_active_noc_request` Exists | PASS |
| **S20-003** | Partial Unique Index `uq_active_noc_move_pass` Exists | PASS |
| **S20-004** | Public Token Unique Index `idx_noc_move_passes_token` Exists | PASS |
| **S20-005** | 8 NOC RPC Routines Exist | PASS |
| **S20-006** | SECURITY DEFINER & `search_path` Hardened on All 8 RPCs | PASS |
| **S20-007** | RLS & FORCE RLS Enabled on All 3 Tables | PASS |
| **S20-008** | Anonymous `submit_noc_request` Blocked (`42501`) | PASS |
| **S20-009** | Anonymous `verify_noc_move_pass` Blocked (`42501`) | PASS |
| **S20-010** | Cross-Society NOC Request Submission Blocked | PASS |
| **S20-011** | Valid Resident Move-In NOC Request Submission | PASS |
| **S20-012** | Valid Resident Move-Out NOC Request Submission | PASS |
| **S20-013** | Automatic Initialization of 4 Checklist Items | PASS |
| **S20-014** | Duplicate Active NOC Request Blocked by Index | PASS |
| **S20-015** | Property Sale NOC Submission by Non-Owner Blocked (`42501`) | PASS |
| **S20-016** | Valid Property Sale NOC Submission by Primary Owner | PASS |
| **S20-017** | Server-Authoritative Dues Audit Execution (Dues Present -> Flagged) | PASS |
| **S20-018** | Server-Authoritative Dues Audit Execution (Zero Dues -> Cleared) | PASS |
| **S20-019** | Credit Dues Balance Calculation (Negative Dues -> Cleared) | PASS |
| **S20-020** | Approval-Time Dues Revalidation Blocked When New Dues Accrue | PASS |
| **S20-021** | Stale Dues Revalidation Automatically Flags Financial Checklist Item | PASS |
| **S20-022** | Admin Departmental Checklist Item Clearance (`facility_inspection`) | PASS |
| **S20-023** | Category Checklist Update by Unauthorized Role Blocked (`42501`) | PASS |
| **S20-024** | Technician Role Clearance of Facility Inspection Item | PASS |
| **S20-025** | Treasurer Role Clearance of Financial Dues Item | PASS |
| **S20-026** | NOC Approval Blocked When Checklist Items Pending or Flagged | PASS |
| **S20-027** | Valid NOC Approval When 100% Checklist Items Cleared | PASS |
| **S20-028** | Non-Secretary / Non-Admin NOC Approval Blocked | PASS |
| **S20-029** | Admin NOC Rejection Execution | PASS |
| **S20-030** | Requester NOC Cancellation Execution | PASS |
| **S20-031** | CSPRNG 6-Digit PIN Generation & Bcrypt Salted Hash Storage | PASS |
| **S20-032** | Plaintext PIN Excluded From Database Tables & Audit Logs | PASS |
| **S20-033** | Public Lookup Pass Token (`PASS-2026-XXXXX`) Generation | PASS |
| **S20-034** | Move Pass Generation Blocked for Unapproved NOC Request | PASS |
| **S20-035** | Vehicle Registration SQL Normalization Execution | PASS |
| **S20-036** | Gatekeeper Verification Supply Mismatched Vehicle Reg Blocked | PASS |
| **S20-037** | Valid Vehicle Registration Match Gatekeeper Verification | PASS |
| **S20-038** | Gatekeeper Valid Move Pass Verification Execution | PASS |
| **S20-039** | Dual-Tier Lockout Defense (5 Pass Failures -> 15 Min Lockout) | PASS |
| **S20-040** | Generic Error (`22000`) Returned on Verification Failures | PASS |
| **S20-041** | Move Pass Replay Blocked After Status = `used` | PASS |
| **S20-042** | Expired Move Pass Verification Blocked | PASS |
| **S20-043** | Server-Authoritative Tenancy Termination on Move-Out Completion | PASS |
| **S20-044** | Tenancy Termination Date Recorded as `CURRENT_DATE` | PASS |
| **S20-045** | Direct `noc_requests` DML Blocked by Restrictive RLS | PASS |
| **S20-046** | Direct `noc_clearance_checklists` DML Blocked by Restrictive RLS | PASS |
| **S20-047** | Direct `noc_move_passes` DML Blocked by Restrictive RLS | PASS |
| **S20-048** | Audit Log Created for NOC Request Submission & Approval | PASS |
| **S20-049** | Audit Log Redaction (Plaintext Passcode Excluded) | PASS |
| **S20-050** | Real-Time Notification Scoping (Requester & Admins Only) | PASS |
| **S20-051** | Financial Non-Interference (Zero Ledger Mutations) | PASS |
| **S20-052** | Cumulative Baseline Suite Target Reached (691/691 PASS) | PASS |

---

## 34. IMPLEMENTATION FILE PLAN

At eventual implementation authorization, the following files will be created/modified:
1. `[NEW] database/schema_slice20.sql`: DDL for 3 tables, indexes, RLS policies, and 8 hardened SECURITY DEFINER RPC routines.
2. `[NEW] database/verify_slice20.sql`: Assertion script executing 52 tests (`S20-001` through `S20-052`).
3. `[NEW] scratch/run_all20.ps1`: PowerShell test runner script executing regression Slices 1–19 followed by Slice 20.
4. `[MODIFY] src/supabase.js`: Append Slice 20 API methods (`mockClient.noc`).
5. `[MODIFY] src/App.jsx`: Integrate `NocManagerView` component and navigation tab.

---

## 35. ROLLBACK STRATEGY

If Slice 20 implementation fails during execution:
1. Drop Slice 20 database objects:
   `DROP TABLE IF EXISTS public.noc_move_passes CASCADE;`
   `DROP TABLE IF EXISTS public.noc_clearance_checklists CASCADE;`
   `DROP TABLE IF EXISTS public.noc_requests CASCADE;`
2. Drop Slice 20 RPC routines:
   `DROP FUNCTION IF EXISTS public.submit_noc_request;`
   `DROP FUNCTION IF EXISTS public.perform_financial_dues_clearance;`
   `DROP FUNCTION IF EXISTS public.update_clearance_checklist_item;`
   `DROP FUNCTION IF EXISTS public.approve_noc_request;`
   `DROP FUNCTION IF EXISTS public.reject_noc_request;`
   `DROP FUNCTION IF EXISTS public.cancel_noc_request;`
   `DROP FUNCTION IF EXISTS public.generate_noc_move_pass;`
   `DROP FUNCTION IF EXISTS public.verify_noc_move_pass;`
3. Execute `scratch/run_all19.ps1` to confirm baseline regression remains green at **639 / 639 PASS**.

---

## 36. INDEPENDENT ADVERSARIAL AUDIT PLAN

Following implementation, an independent adversarial security audit MUST verify:
1. Actual source code and active PostgreSQL catalog definitions.
2. RLS & FORCE RLS policies on all 3 tables.
3. SECURITY DEFINER hardening and `search_path` locking.
4. Approval-time dues revalidation & stale clearance defense.
5. CSPRNG 6-digit PIN generation & bcrypt salted KDF.
6. Public pass token $O(1)$ index lookup.
7. Dual-tier rate limiting & lockout defense.
8. Vehicle registration SQL normalization and matching.
9. Category-specific checklist RBAC segregation.
10. Property sale NOC owner-only rule & zero ownership mutation.
11. Server-authoritative tenancy termination on move-out check-out.
12. Audit redaction & notification scoping.
13. Pass 52 assertions and confirm 691/691 cumulative target.

Final required audit result: **0 Critical / 0 High / 0 Medium / 0 Low findings**.

---

## 37. SECURITY ACCEPTANCE CRITERIA

Slice 20 shall NOT be locked until:
1. All 52 planned assertions (`S20-001` to `S20-052`) pass.
2. Cumulative regression baseline (**691 / 691 PASS**) passes.
3. Zero implementation changes exist in Slices 1–19.
4. Independent adversarial security audit returns PASS with 0 vulnerabilities.

---

## 38. FINAL RECOMMENDATION

The Slice 20 Final Implementation & Security Plan (Revision 2) provides a complete, hardened, and adversary-resistant architecture.

**FINAL VERDICT:**
```text
A — SLICE 20 REVISED PLAN COMPLETE — PENDING EXPLICIT USER IMPLEMENTATION AUTHORIZATION
```
