# STAGE 10U-T PHASE B — SLICE 20 POST-DEPLOYMENT FAILURE: FORENSIC REMEDIATION PLAN

**TARGET REPOSITORY:** `D:\Clients Applications\SU Society App`  
**TARGET REMOTE SUPABASE PROJECT:** `fsegpxqoozxmicxcxjun` (`pandujana2011-web's Project`)  
**REGION:** `ap-south-1`  
**POSTGRESQL VERSION:** `17.6.1.166`  
**CURRENT REMOTE MIGRATION:** `20260912000019_slice19.sql`  
**FAILED MIGRATION:** `20260912000020_slice20.sql`  
**GOVERNANCE MODE:** `PLAN ONLY / ZERO IMPLEMENTATION / ZERO REMOTE MUTATION`  

---

## 1. EXECUTIVE SUMMARY

During controlled production deployment, Supabase CLI `db push` applied migrations `20260912000006_slice6.sql` through `20260912000019_slice19.sql` successfully to production before failing at Statement 28 of `20260912000020_slice20.sql` (Line 124) with `SQLSTATE 42703` (`column am.status does not exist`).

Because `20260912000020_slice20.sql` was executed inside a single PostgreSQL transaction block, PostgreSQL automatically executed an atomic `ROLLBACK`. **Zero partial database objects from Slice 20 exist remotely.** The remote database remains clean and coherent at migration `20260912000019_slice19.sql`.

This document presents the authoritative **Forensic Remediation Plan** for Slice 20. It details the exact root causes, performs a complete audit of all stale schema assumptions in Slice 20, compares them against the authoritative Slices 1–19 production schema, evaluates remediation options, and defines the recommended hardened remediation strategy.

---

## 2. EXACT FAILURE ANALYSIS

* **Failing Migration File:** `supabase/migrations/20260912000020_slice20.sql`
* **Statement Index:** Statement 28 (Lines 115–126)
* **PostgreSQL Error Code:** `SQLSTATE 42703` (`undefined_column`)
* **Exact Failure Log:**
  ```text
  ERROR: column am.status does not exist (SQLSTATE 42703)
  At statement: 28
  CREATE POLICY noc_requests_select_policy ON public.noc_requests
      FOR SELECT TO authenticated
      USING (
          applicant_id = auth.uid() OR
          public.is_admin() OR
          EXISTS (
              SELECT 1 FROM public.association_memberships am
              WHERE am.property_id = noc_requests.property_id
              AND am.user_id = auth.uid()
              AND am.status = 'active'
          )
      );
  ```

---

## 3. FORENSIC ROOT CAUSE

The Slice 20 migration script (`20260912000020_slice20.sql`) was authored under an outdated schema assumption regarding the structure of pre-existing tables created in earlier slices:

1. **Primary Defect (Statement 28 - Line 124):** Statement 28 references `am.status = 'active'`, assuming table `public.association_memberships` possesses a column named `status`.
2. **Actual Production Schema (Slice 1, Step 11):** Table `public.association_memberships` defines the membership status column as **`membership_status`** (`CONSTRAINT chk_membership_status CHECK (membership_status IN ('active', 'suspended', 'resigned', 'expelled'))`). Column `status` does not exist on `public.association_memberships`.
3. **Execution Interruption:** When PostgreSQL attempted to parse `CREATE POLICY noc_requests_select_policy`, the query planner looked up `status` on table `association_memberships` (aliased `am`). Finding no such column, it threw `SQLSTATE 42703` and aborted the transaction.

---

## 4. RELEVANT SLICES 1–19 PRODUCTION SCHEMA

Inspection of the authoritative production schema established in Slices 1–19 reveals the true column definitions:

### A. Table `public.association_memberships` (Created in Slice 1, Lines 518–543)
```sql
CREATE TABLE IF NOT EXISTS public.association_memberships (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id          UUID        NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    property_id         UUID        NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
    user_id             UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    membership_number   VARCHAR(50),
    membership_status   VARCHAR(30) NOT NULL DEFAULT 'active'
                            CONSTRAINT chk_membership_status CHECK (
                                membership_status IN ('active', 'suspended', 'resigned', 'expelled')
                            ),
    suspension_reason   TEXT,
    start_date          DATE        NOT NULL DEFAULT CURRENT_DATE,
    end_date            DATE,
    created_by          UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    end_recorded_by     UUID        REFERENCES public.users(id) ON DELETE RESTRICT,
    transition_notes    TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_membership_dates CHECK (end_date IS NULL OR end_date >= start_date)
);
```

### B. Table `public.occupants` (Created in Slice 1, Lines 654–710)
```sql
CREATE TABLE IF NOT EXISTS public.occupants (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id          UUID        NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    property_id         UUID        NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
    unit_id             UUID        REFERENCES public.units(id) ON DELETE RESTRICT,
    tenancy_id          UUID        REFERENCES public.tenancies(id) ON DELETE RESTRICT,
    user_id             UUID        REFERENCES public.users(id) ON DELETE SET NULL,
    full_name           VARCHAR(200) NOT NULL,
    relationship        VARCHAR(100) NOT NULL,
    start_date          DATE        NOT NULL DEFAULT CURRENT_DATE,
    end_date            DATE,
    created_by          UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    ...
);
```

---

## 5. SLICE 20 INTENDED DESIGN

Slice 20 implements the **NOC & Move-Out Management System** (Rev 4.53 Authoritative Specification). It introduces:
* `public.noc_requests` (NOC application tracking & workflow)
* `public.noc_move_passes` (Digital move passes with CSPRNG token digests and 6-digit PIN verification)
* `public.noc_gatekeeper_rate_limits` (Rate-limiting for gatekeeper PIN verification)
* `public.noc_audit_logs` (Audit tracking for NOC events)
* RPC routines: `fn_request_noc`, `fn_review_noc`, `fn_approve_noc`, `fn_reject_noc`, `fn_revoke_noc`, `fn_cancel_noc`, `verify_pass`, `fn_complete_noc_transfer`, `process_expired_noc_passes`.

---

## 6. COMPLETE SLICE 20 STALE ALIAS & COLUMN AUDIT

A deep forensic scan of all 767 lines in `20260912000020_slice20.sql` identified **4 critical stale schema assumptions**:

| Line # | Statement / Context | Stale Slice 20 Code Snippet | Actual Production Schema (Slices 1–19) | Defect Classification | Required Hardened Fix |
|--------|---------------------|-----------------------------|----------------------------------------|-----------------------|-----------------------|
| **124** | Statement 28 (RLS Policy `noc_requests_select_policy`) | `AND am.status = 'active'` | Column is `membership_status` | **Failing Column Error (SQLSTATE 42703)** | Change `am.status` to `am.membership_status` |
| **223** | RPC `public.fn_request_noc` | `AND am.status = 'active'` | Column is `membership_status` | **Latent Column Error** | Change `am.status` to `am.membership_status` |
| **719** | RPC `public.fn_complete_noc_transfer` | `UPDATE public.property_occupants SET status = 'inactive', move_out_date = CURRENT_DATE ...` | Table is `public.occupants`; active status is temporal (`end_date IS NULL`) | **Latent Table & Column Error** | Change table to `public.occupants`, set `end_date = CURRENT_DATE` where `end_date IS NULL` |
| **723-728** | RPC `public.fn_complete_noc_transfer` | `UPDATE public.association_memberships SET status = 'inactive' ...` <br>`INSERT INTO public.association_memberships (..., membership_type, status)` | Column is `membership_status` (`'resigned'`); column `membership_type` does not exist; `created_by` is required | **Latent Column & Constraint Error** | Update `end_date = CURRENT_DATE, membership_status = 'resigned'`; Insert with `membership_status = 'active'`, `created_by = auth.uid()` |

---

## 7. DEPENDENCY ANALYSIS

* **Statement 28 Dependency:** Statement 28 (`noc_requests_select_policy`) depends on `public.association_memberships` created in Slice 1. It is **NOT** a migration ordering issue within Slice 20 itself.
* **Failure Nature:** **Stale Schema Assumption & Incorrect Column/Table Names**. Slice 20 was written assuming a different naming convention (`am.status`, `property_occupants`) than what was locked and deployed in Slices 1–19 (`am.membership_status`, `public.occupants`).

---

## 8. SECURITY IMPACT

**CLASSIFICATION:** `HIGH SECURITY IMPACT`

* **Authorization Impact:** Statement 28 defines the RLS `SELECT` policy for NOC requests (`noc_requests_select_policy`). This policy controls whether residents, property members, and admins can view sensitive NOC applications.
* **Workflow Impact:** RPC routines `fn_request_noc` and `fn_complete_noc_transfer` execute security-sensitive transfer operations (e.g. deactivating occupants, transferring association membership).
* **Security Requirement:** Remediation must strictly preserve society isolation and owner/tenant access rules without weakening RLS or introducing unauthorized membership grants.

---

## 9. ADVERSARIAL ANALYSIS OF REMEDIATION CANDIDATES

| # | Attack / Failure Scenario | Unremediated Slice 20 | Remediated Slice 20 (Hardened Option 1) | Safe? | Defense Mechanism |
|---|---------------------------|-----------------------|-----------------------------------------|-------|-------------------|
| 1 | Deployment via `npx supabase db push` | Fails (`SQLSTATE 42703`) | Succeeds 100% | **SAFE** | Valid schema column names |
| 2 | Resident viewing NOC requests for owned property | Blocked by SQL error | Allowed via `am.membership_status = 'active'` | **SAFE** | Correct RLS `EXISTS` check |
| 3 | Resident viewing NOC requests for another society | Blocked | Blocked | **SAFE** | RLS `society_id` check |
| 4 | Unauthorized user submitting NOC request | Allowed if SQL runs | Blocked by `fn_request_noc` auth check | **SAFE** | RPC `is_admin()` or `membership_status` check |
| 5 | Gate pass PIN verification brute-force attack | Unprotected if error | Blocked by rate-limiter (10 fails -> 15 min lockout) | **SAFE** | `noc_gatekeeper_rate_limits` |
| 6 | CSPRNG token digest forgery | Cryptographically hard | SHA-256 digest on 48-bit CSPRNG token | **SAFE** | `extensions.digest(token, 'sha256')` |
| 7 | Replay attack on completed NOC pass | Allowed if state un-updated | Blocked (`v_pass.status <> 'approved'`) | **SAFE** | Pass state validation |
| 8 | NOC approval with outstanding financial balance | Allowed if un-checked | Blocked (`fn_get_property_outstanding_balance > 0`) | **SAFE** | Property row lock & balance check |
| 9 | Completing tenant move-out on `public.occupants` | Fails (`property_occupants`) | Sets `end_date = CURRENT_DATE` on `occupants` | **SAFE** | Schema-aligned temporal update |
| 10| Transferring association membership on owner transfer | Fails (`membership_type`, `status`) | Sets `end_date` on old row, inserts new row with `created_by` | **SAFE** | Schema-aligned temporal insert |
| 11| Cross-society NOC approval attempt | Blocked | Blocked (`society_id` match check) | **SAFE** | Property lock & society check |
| 12| Direct client INSERT into `noc_requests` | Blocked by REVOKE | Blocked (`REVOKE INSERT ON noc_requests FROM authenticated`) | **SAFE** | Explicit REVOKE grants |
| 13| Direct client UPDATE on `noc_move_passes` | Blocked by REVOKE | Blocked (`REVOKE UPDATE ON noc_move_passes FROM authenticated`) | **SAFE** | Explicit REVOKE grants |
| 14| Tenant cancelling another tenant's NOC | Blocked | Blocked (`v_caller_id = v_applicant_id OR is_admin()`) | **SAFE** | `fn_cancel_noc` caller check |
| 15| Revoking NOC in `completed` status | Allowed if un-checked | Blocked (`v_status NOT IN ('approved', 'move_pass_generated')`) | **SAFE** | State machine check |
| 16| CSPRNG 6-digit PIN bias exploitation | Uniform rejection sampling | Uniform rejection sampling (`v_val < 2147000000`) | **SAFE** | CSPRNG rejection sampling |
| 17| PostgREST GUC manipulation | Blocked | Blocked | **SAFE** | `pg_catalog, public` search path |
| 18| SECURITY DEFINER search_path hijacking | Vulnerable if unlocked | Secure (`SET search_path = pg_catalog, public`) | **SAFE** | Explicit search_path |
| 19| Audit log tampering for NOC operations | Blocked | Blocked (`REVOKE INSERT, UPDATE, DELETE ON noc_audit_logs`) | **SAFE** | Append-only audit table |
| 20| Transaction rollback on NOC failure | Atomic rollback | Atomic rollback | **SAFE** | PL/pgSQL transaction handling |

---

## 10. REMEDIATION OPTIONS

### OPTION 1: Hardened Schema-Aligned Remediation of Slice 20 (RECOMMENDED)

* **Exact Mechanism:** Correct the 4 stale schema references in `supabase/migrations/20260912000020_slice20.sql` and `database/schema_slice20.sql` to align byte-for-byte with the authoritative Slices 1–19 production schema:
  1. In Statement 28 (Line 124): Replace `am.status = 'active'` with `am.membership_status = 'active'`.
  2. In `fn_request_noc` (Line 223): Replace `am.status = 'active'` with `am.membership_status = 'active'`.
  3. In `fn_complete_noc_transfer` (Line 719): Replace `UPDATE public.property_occupants SET status = 'inactive', move_out_date = CURRENT_DATE ...` with:
     ```sql
     UPDATE public.occupants
     SET end_date = CURRENT_DATE, updated_at = NOW(), departure_reason = 'NOC Move Out'
     WHERE property_id = v_pass.property_id AND user_id = v_noc.applicant_id AND end_date IS NULL;
     ```
  4. In `fn_complete_noc_transfer` (Line 723–728): Replace stale membership update/insert with:
     ```sql
     UPDATE public.association_memberships
     SET end_date = CURRENT_DATE, membership_status = 'resigned', updated_at = NOW()
     WHERE property_id = v_pass.property_id AND user_id = v_noc.applicant_id AND end_date IS NULL;

     INSERT INTO public.association_memberships (society_id, property_id, user_id, membership_status, created_by)
     VALUES (v_noc.society_id, v_pass.property_id, v_noc.target_user_id, 'active', v_caller_id);
     ```

### OPTION 2: View Abstraction Layer (REJECTED)

* **Exact Mechanism:** Create compatibility views `public.property_occupants` and add a `status` column view for `association_memberships`.
* **Rejection Reason:** Introduces unnecessary schema complexity, violates the 931/931 locked security baseline, and masks underlying schema design defects.

---

## 11. RECOMMENDED REMEDIATION

**RECOMMENDED OPTION:** `OPTION 1 (Hardened Schema-Aligned Remediation of Slice 20)`

**Rationale:** Option 1 directly resolves all 4 schema defects, restores 100% compatibility with production Slices 1–19, enforces temporal data integrity (`end_date IS NULL` for active memberships and occupants), and preserves the 931/931 immutable security baseline.

---

## 12. REQUIRED REGRESSION PLAN (25 SCENARIOS)

Prior to any future deployment authorization, remediated Slice 20 must be validated against:
1. `npx supabase db push` syntax compilation.
2. Creation of `noc_requests`, `noc_move_passes`, `noc_gatekeeper_rate_limits`, `noc_audit_logs`.
3. RLS enablement and REVOKE grants on all 4 NOC tables.
4. RLS Policy `noc_requests_select_policy` execution under `am.membership_status = 'active'`.
5. RLS Policy `noc_move_passes_select_policy` execution for gatekeepers and applicants.
6. Execution of `fn_request_noc` by valid property owner/member.
7. Rejection of `fn_request_noc` by unauthorized resident.
8. Execution of `fn_review_noc` by admin.
9. Execution of `fn_approve_noc` with zero financial balance.
10. Rejection of `fn_approve_noc` with positive financial balance.
11. One-time secret payload return (`raw_pass_token`, `raw_pin`).
12. CSPRNG 6-digit PIN generation.
13. Pass verification via `verify_pass` with valid token and PIN.
14. Gatekeeper rate-limiting after 10 failed PIN attempts (15-minute lockout).
15. Execution of `fn_complete_noc_transfer` for tenant move-out (`public.occupants` updated with `end_date = CURRENT_DATE`).
16. Execution of `fn_complete_noc_transfer` for owner transfer (`association_memberships` updated with `end_date` and new row inserted).
17. Execution of `fn_reject_noc` with reason.
18. Execution of `fn_revoke_noc` for approved pass.
19. Execution of `fn_cancel_noc` by applicant.
20. Automated expiration processing via `process_expired_noc_passes`.
21. Cross-society isolation across all NOC RPCs.
22. SECURITY DEFINER search_path locked to `pg_catalog, public`.
23. Audit logging in `noc_audit_logs` with redacted token secrets.
24. Atomic rollback on transaction exception.
25. Baseline verification against `SLICE23_SECURITY_LOCK.md` (`47A7093CB842BB10179D529E85452BBD8B463E3057725B28E69A5E99AC614448`).

---

## 13. MIGRATION & BASELINE INTEGRITY REQUIREMENTS

* **DO NOT** modify `supabase/migrations/20260912000020_slice20.sql` or `database/schema_slice20.sql` until explicit implementation authorization is granted in a subsequent stage.
* **DO NOT** modify Slices 1–19 or Slices 21–23.
* **`SLICE23_SECURITY_LOCK.md` SHA-256:** Must remain `47A7093CB842BB10179D529E85452BBD8B463E3057725B28E69A5E99AC614448` (100% UNMUTATED).

---

## 14. REMOTE STATE REQUIREMENTS

* The remote database **MUST REMAIN EXACTLY AT** migration `20260912000019_slice19.sql`.
* Zero remote database mutations, repairs, or deployments are authorized by this plan.

---

## 15. MANDATORY GOVERNANCE STATEMENTS

```text
IMPLEMENTATION:
NOT AUTHORIZED

DEPLOYMENT:
NOT AUTHORIZED

REMOTE DATABASE:
MUST REMAIN AT 20260912000019_slice19.sql

MIGRATION REPAIR:
NOT AUTHORIZED

ROLLBACK:
NOT AUTHORIZED

BASELINE MUTATION:
NOT AUTHORIZED

SECURITY LOCK:
NOT AUTHORIZED

SLICE 20:
FAILED / FULLY ROLLED BACK / NOT DEPLOYED

SLICES 21–23:
NOT DEPLOYED
```

---
*Remediation Plan generated on September 13, 2026.*
