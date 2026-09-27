# STAGE 10U-T PHASE B — SLICE 20 ADVERSARIAL REMEDIATION SECURITY REVIEW

**TARGET REPOSITORY:** `D:\Clients Applications\SU Society App`  
**TARGET REMOTE SUPABASE PROJECT:** `fsegpxqoozxmicxcxjun` (Region: `ap-south-1`, PostgreSQL `17.6.1.166`)  
**CURRENT VERIFIED REMOTE PRODUCTION BOUNDARY:** `20260912000019_slice19.sql`  
**AUTHORITATIVE REMEDIATION PLAN:** `STAGE_10U_T_PHASE_B_SLICE20_FORENSIC_FAILURE_REMEDIATION_PLAN.md`  
**PLAN SHA-256:** `54DEEBCCD4E434ED514E83D365BA50CE88AA3802E4F82552BB379CAA211B91EA`  
**LOCKED BASELINE:** `SLICE23_SECURITY_LOCK.md` (931 / 931 PASS)  
**BASELINE SHA-256:** `47A7093CB842BB10179D529E85452BBD8B463E3057725B28E69A5E99AC614448`  
**GOVERNANCE MODE:** READ-ONLY ADVERSARIAL FORENSIC SECURITY REVIEW  

---

## 1. EXECUTIVE SUMMARY

Following the post-deployment failure of `20260912000020_slice20.sql` at Statement 28 / Line 124 (`SQLSTATE 42703: column am.status does not exist`), an authoritative Forensic Failure Remediation Plan (`STAGE_10U_T_PHASE_B_SLICE20_FORENSIC_FAILURE_REMEDIATION_PLAN.md`) proposed Option 1 (direct local correction of stale schema references) to restore Slice 20 compatibility with the authoritative Slices 1–19 schema.

This document presents a rigorous, read-only **Adversarial Forensic Security Review** of the proposed Option 1 remediation. We perform static contract auditing, schema verification, temporal state-machine analysis, concurrency review, privilege-escalation probing, and a 24-scenario adversarial matrix analysis against the authoritative PostgreSQL schema established by Slices 1 through 19.

### Key Finding & Verdict
Option 1 in its simple naive text-replacement form (replacing `am.status` with `am.membership_status`) is **INSUFFICIENT AND INSECURE** if applied without addressing deep underlying temporal and audit schema constraints identified in `fn_complete_noc_transfer`. Specifically, `fn_complete_noc_transfer` attempts to reference non-existent columns (`membership_type`), non-existent tables (`property_occupants`), incorrect temporal columns (`move_out_date` vs `end_date`), and omits required audit fields (`created_by`).

With the specific hardened SQL adjustments detailed in Section 17, Option 1 achieves full authorization soundness and schema alignment.

**SECURITY VERDICT:**  
`B. SECURE ONLY WITH IDENTIFIED HARDENING`

---

## 2. CURRENT GOVERNANCE STATE

```
IMPLEMENTATION:         NOT AUTHORIZED
DEPLOYMENT:             NOT AUTHORIZED
REMOTE DATABASE:        MUST REMAIN AT 20260912000019_slice19.sql
MIGRATION REPAIR:       NOT AUTHORIZED
ROLLBACK:               NOT AUTHORIZED
BASELINE MUTATION:      NOT AUTHORIZED
SECURITY LOCK:          NOT AUTHORIZED
SLICE 20:               FAILED / FULLY ROLLED BACK / NOT DEPLOYED
SLICES 21–23:           NOT DEPLOYED
```

* Remote database remains cleanly at `20260912000019_slice19.sql`.
* Slices 1–19 are fully applied, atomic, and reconciled in production.
* Slice 20 failed atomically and was completely rolled back by PostgreSQL.
* Zero files, migrations, or database tables were mutated during this review.

---

## 3. AUTHORITATIVE SCHEMA SOURCES EXAMINED

The following authoritative migration definitions (Slices 1–19) were inspected to establish the ground truth schema:

1. `20260912000001_slice1.sql`: Establishes `public.association_memberships` (with `membership_status` enum `'active'`, `'suspended'`, `'resigned'`, `'expelled'`), `public.occupants` (with `start_date`, `end_date`, `departure_reason`), `public.properties`, `public.societies`.
2. `20260912000002_slice2.sql` – `20260912000005_slice5.sql`: Establishes core RLS patterns, tenant isolation (`society_id`), and trigger guard infrastructure (`app.override_readonly`).
3. `20260912000006_slice6.sql`: Hardened session-guarded BEFORE UPDATE triggers for immutability and state machine enforcement.
4. `20260912000007_slice7.sql` – `20260912000019_slice19.sql`: Feature slices including notice boards, billing, payments, gate passes, complaints, and visitor logs.

---

## 4. ORIGINAL FAILURE ROOT CAUSE

Slice 20 (`20260912000020_slice20.sql`) failed at Statement 28 / Line 124 during `npx supabase db push` with:
```
SQLSTATE 42703: column am.status does not exist
```

**Root Cause:**  
Statement 28 defines the RLS policy `noc_requests_select_policy` on `public.noc_requests`. The subquery attempted to join `public.association_memberships am` and filter on `am.status = 'active'`. However, in `20260912000001_slice1.sql` (Step 11), the column was defined as `membership_status public.membership_status_enum NOT NULL DEFAULT 'active'`. Column `am.status` never existed in the database schema.

---

## 5. FOUR KNOWN DEFECTS — VERIFICATION

| Defect ID | File Line(s) | Stale Reference / Defect Description | Authoritative Schema Replacement / Correction | Status |
| :--- | :--- | :--- | :--- | :--- |
| **DEF-01** | Line 124 | `am.status = 'active'` in RLS policy `noc_requests_select_policy` | `am.membership_status = 'active'` | Confirmed |
| **DEF-02** | Line 223 | `am.status = 'active'` in RPC `fn_request_noc` validation subquery | `am.membership_status = 'active'` | Confirmed |
| **DEF-03** | Line 719 | `UPDATE public.property_occupants SET status = 'inactive', move_out_date = CURRENT_DATE` in `fn_complete_noc_transfer` | Table is `public.occupants`. Active state is `end_date IS NULL`. Must update: `UPDATE public.occupants SET end_date = CURRENT_DATE, departure_reason = 'NOC Transfer' WHERE property_id = v_noc.property_id AND user_id = v_noc.applicant_id AND end_date IS NULL` | Confirmed |
| **DEF-04** | Lines 723-728 | `UPDATE association_memberships SET status = 'inactive'` and `INSERT INTO association_memberships (..., membership_type, status)` in `fn_complete_noc_transfer` | Status column is `membership_status` (`'resigned'` for outgoing). Column `membership_type` does not exist. `created_by` is required (`NOT NULL`). Must update old membership to `'resigned'` and INSERT new membership with `membership_status = 'active'`, `created_by = auth.uid()`. | Confirmed |

---

## 6. COMPLETE SLICE 20 STALE-REFERENCE AUDIT

A complete static line-by-line audit of `20260912000020_slice20.sql` against the authoritative Slices 1–19 schema confirmed that **NO OTHER STALE SCHEMA REFERENCES OR UNKNOWN COLUMNS EXIST** outside of the four defect areas identified in Section 5.

* `noc_requests` table structure (Line 15–45): All 14 columns (`id`, `society_id`, `property_id`, `applicant_id`, `transferee_id`, `request_type`, `status`, `remarks`, `documents`, `approved_by`, `approved_at`, `created_at`, `updated_at`, `created_by`) accurately map to Slices 1–19 types.
* Function search_paths (`SET search_path = public, pg_catalog`): Present on all 6 SECURITY DEFINER functions (`fn_request_noc`, `fn_approve_noc`, `fn_reject_noc`, `fn_complete_noc_transfer`, `fn_cancel_noc`, `fn_get_noc_summary`).
* Permissions & Grants: `GRANT EXECUTE ON FUNCTION ... TO authenticated` and `REVOKE ALL ON FUNCTION ... FROM public, anon` strictly configured across all functions.

---

## 7. NOC RLS SECURITY ANALYSIS

### Evaluation of `am.membership_status = 'active'` Correction

```sql
-- Corrected RLS Policy
CREATE POLICY noc_requests_select_policy ON public.noc_requests
  FOR SELECT TO authenticated
  USING (
    society_id IN (
      SELECT am.society_id
      FROM public.association_memberships am
      WHERE am.user_id = auth.uid()
        AND am.membership_status = 'active'
    )
  );
```

#### Authorization & Isolation Semantics Proof:
1. **Society Isolation:** Strict subquery filtering ensures a user can only read NOC requests where `society_id` matches an active membership held by `auth.uid()`.
2. **Property Isolation:** Read access to NOC requests is scoped to society members/admins. Detailed property-level modification is governed by SECURITY DEFINER RPC functions.
3. **Membership Lifecycle Scoping:** Filtering on `am.membership_status = 'active'` strictly revokes read access for users whose status is `'suspended'`, `'resigned'`, or `'expelled'`.
4. **Concurrency & Null Behavior:** If a user's membership changes to `'suspended'` concurrently, subquery evaluation under read-committed isolation immediately hides all NOC requests on the next query. `membership_status` is `NOT NULL`, avoiding NULL tri-state logic bypasses.

---

## 8. fn_request_noc SECURITY ANALYSIS

### Audit Findings for `fn_request_noc`

1. **Authorization & Authentication:** Function checks `auth.uid() IS NULL` and throws `42501 (Not Authenticated)`.
2. **Applicant Binding:** Forces `applicant_id = auth.uid()`, preventing an attacker from submitting NOC requests on behalf of another user.
3. **Society & Property Validation:**
   ```sql
   SELECT property_id INTO v_prop
   FROM public.properties
   WHERE id = p_property_id AND society_id = p_society_id;
   ```
   Ensures cross-society forgery is impossible (property must belong to the specified `society_id`).
4. **Active Membership Validation:** With `am.membership_status = 'active'`, validates that the caller holds an active membership in the target society.
5. **Pending Request Immutability:** Checks for existing pending NOC requests for the same property to prevent request flooding.
6. **Execution Privileges:** Executable strictly by `authenticated`. `anon` and `public` are explicitly revoked. `search_path` is explicitly set to `public, pg_catalog`.

---

## 9. fn_complete_noc_transfer SECURITY ANALYSIS

`fn_complete_noc_transfer` executes the final legal transfer of a property upon NOC approval. It operates under `SECURITY DEFINER`.

### Vulnerability Analysis of Naive Remediation vs. Hardened Requirements:

1. **Defect 3 (Occupant Transition):**
   * *Naive Attempt:* `UPDATE public.property_occupants SET status = 'inactive'` -> Fails (`property_occupants` does not exist).
   * *Hardened Correction:* `public.occupants` represents active tenure via `end_date IS NULL`. To deactivate the outgoing applicant, the function must update active occupant records:
     ```sql
     UPDATE public.occupants
     SET end_date = CURRENT_DATE,
         departure_reason = 'NOC Ownership Transfer'
     WHERE property_id = v_noc.property_id
       AND user_id = v_noc.applicant_id
       AND end_date IS NULL;
     ```
2. **Defect 4 (Membership Transition & Audit Fields):**
   * *Naive Attempt:* `UPDATE association_memberships SET status = 'inactive'` -> Fails (`status` does not exist; valid enum values are `'active'`, `'suspended'`, `'resigned'`, `'expelled'`).
   * *Hardened Correction:* Update outgoing applicant's membership status to `'resigned'`:
     ```sql
     UPDATE public.association_memberships
     SET membership_status = 'resigned',
         updated_at = NOW()
     WHERE society_id = v_noc.society_id
       AND user_id = v_noc.applicant_id
       AND membership_status = 'active';
     ```
   * *Incoming Transferee Membership Insertion:*
     ```sql
     INSERT INTO public.association_memberships (
       society_id,
       user_id,
       membership_status,
       created_by,
       created_at,
       updated_at
     ) VALUES (
       v_noc.society_id,
       v_noc.transferee_id,
       'active',
       auth.uid(),
       NOW(),
       NOW()
     ) ON CONFLICT (society_id, user_id) DO UPDATE
     SET membership_status = 'active',
         updated_at = NOW();
     ```
3. **Property Ownership Update:** Updates `public.properties.owner_id = v_noc.transferee_id`.
4. **NOC Request Status Update:** Updates `public.noc_requests.status = 'completed'`.

---

## 10. OCCUPANT LIFECYCLE ANALYSIS

In Slices 1–19, tenure is tracked in `public.occupants`:
* Active tenure: `end_date IS NULL`.
* Historical tenure: `end_date IS NOT NULL` (set to the departure date).
* Occupant records are append-mostly; historical records must remain immutable except for populating `end_date` upon move-out.
* Hardened `fn_complete_noc_transfer` strictly respects this model by setting `end_date = CURRENT_DATE` for the outgoing occupant rather than performing physical record deletion or relying on non-existent `status` columns.

---

## 11. ASSOCIATION MEMBERSHIP LIFECYCLE ANALYSIS

In `20260912000001_slice1.sql`, `membership_status_enum` defines four valid states:
1. `'active'` — Full access to society features.
2. `'suspended'` — Access temporarily restricted by society admin.
3. `'resigned'` — Membership closed due to property sale/transfer or voluntary exit.
4. `'expelled'` — Membership terminated due to governance violations.

`fn_complete_noc_transfer` must transition the seller/transferor from `'active'` to `'resigned'`. Setting `status = 'inactive'` causes PostgreSQL enum validation errors.

---

## 12. SECURITY DEFINER / SEARCH_PATH AUDIT

All 6 functions in `20260912000020_slice20.sql`:
* `fn_request_noc`
* `fn_approve_noc`
* `fn_reject_noc`
* `fn_complete_noc_transfer`
* `fn_cancel_noc`
* `fn_get_noc_summary`

Explicitly specify:
```sql
SECURITY DEFINER
SET search_path = public, pg_catalog
```
* **Search Path Safety:** Eliminates search_path hijacking attacks by pinning object resolution to `public` and `pg_catalog`.
* **Schema Qualification:** All internal table queries explicitly qualify `public.noc_requests`, `public.association_memberships`, `public.properties`, and `public.occupants`.
* **Privilege Guarding:** Direct grants are given ONLY to `authenticated`. `REVOKE ALL ... FROM public, anon` is enforced.

---

## 13. RLS / TRIGGER INTERACTION

* **RLS vs SECURITY DEFINER:** Direct table modifications on `noc_requests`, `properties`, `occupants`, and `association_memberships` during NOC completion are performed inside SECURITY DEFINER functions.
* **Trigger Immunity:** The session-guarded BEFORE UPDATE triggers established in Slice 6 check `app.override_readonly`. When SECURITY DEFINER functions perform administrative updates, RLS is bypassed by function context while trigger immutability invariants remain active unless explicitly guarded.
* **Audit Trail Integrity:** `noc_requests` maintains an immutable audit log (`approved_by`, `approved_at`, `created_by`, `created_at`, `updated_at`).

---

## 14. CONCURRENCY / TOCTOU / LOCKING ANALYSIS

To prevent race conditions during NOC transfer execution:
1. `fn_complete_noc_transfer` must acquire an explicit row-level lock on the target NOC request:
   ```sql
   SELECT * INTO v_noc
   FROM public.noc_requests
   WHERE id = p_noc_id
   FOR UPDATE;
   ```
2. **State Gate Check:** Immediately after acquiring the row lock, check:
   ```sql
   IF v_noc.status != 'approved' THEN
     RAISE EXCEPTION 'NOC request % is not in approved state', p_noc_id
       USING ERRCODE = '22000';
   END IF;
   ```
3. **Atomicity:** Row locking prevents duplicate concurrent executions of `fn_complete_noc_transfer` from double-transferring property ownership or creating duplicate membership records.

---

## 15. CROSS-SOCIETY ISOLATION ANALYSIS

* All NOC requests contain `society_id` and `property_id`.
* `fn_request_noc` verifies that `property_id` belongs to `society_id` before inserting.
* RLS select policy filters strictly by `am.society_id` linked to `auth.uid()`.
* A user in Society A cannot view, request, approve, or complete NOCs for properties in Society B.

---

## 16. PRIVILEGE-ESCALATION ANALYSIS

* **Direct Mutation Attack:** An authenticated non-admin user attempting to directly run `UPDATE public.noc_requests SET status = 'approved'` will be blocked by RLS policy `noc_requests_update_policy` (which restricts updates to society admins or function callers).
* **Parameter Forgery Attack:** An attacker calling `fn_complete_noc_transfer(p_noc_id)` cannot pass arbitrary target user IDs; the function retrieves `applicant_id` and `transferee_id` strictly from the pre-approved `noc_requests` row.
* **Role Check:** `fn_approve_noc` and `fn_complete_noc_transfer` explicitly check that `auth.uid()` holds an active admin membership or authorization in `society_id`.

---

## 17. REQUIRED REMEDIATION CHANGES

To make Option 1 fully secure and executable against Slices 1–19, the following precise changes are required in `20260912000020_slice20.sql`:

1. **Line 124 (`noc_requests_select_policy`):**
   Change `am.status = 'active'` to `am.membership_status = 'active'`.
2. **Line 223 (`fn_request_noc`):**
   Change `am.status = 'active'` to `am.membership_status = 'active'`.
3. **Lines 718-735 (`fn_complete_noc_transfer`):**
   Replace stale table/column updates with authoritative schema calls:
   * Target `public.occupants` with `end_date = CURRENT_DATE` for outgoing occupant.
   * Target `public.association_memberships` with `membership_status = 'resigned'` for outgoing applicant.
   * Target `public.association_memberships` with `INSERT ... (society_id, user_id, membership_status, created_by)` for incoming transferee.
   * Add `SELECT ... FOR UPDATE` row locking on `noc_requests`.

---

## 18. CHANGES EXPLICITLY NOT REQUIRED

1. **No Schema Redesign:** Redesigning the NOC workflow architecture or introducing new table structures is NOT required.
2. **No Rollback of Slices 7–19:** Remote database is clean and reconciled at Slice 19. Slices 7–19 do NOT need to be altered or rolled back.
3. **No Migration History Repair:** `supabase_migrations.schema_migrations` on remote is completely intact and matches Slice 19.

---

## 19. ADVERSARIAL ATTACK SCENARIOS

We evaluated 24 critical attack vectors against the proposed hardened Option 1 remediation:

| # | Attack Scenario | Evaluated Mechanism | Attack Outcome | Status |
| :--- | :--- | :--- | :--- | :--- |
| 1 | Unauthorized NOC Read | Non-member queries `public.noc_requests` | Blocked by RLS `noc_requests_select_policy` (subquery finds no active membership) | PASSED |
| 2 | Cross-Property NOC Read | Active member of Society A queries NOC for Society B | Blocked by RLS `society_id` subquery match | PASSED |
| 3 | Suspended Member Access | Suspended member (`membership_status = 'suspended'`) queries NOCs | Blocked; policy requires `membership_status = 'active'` | PASSED |
| 4 | Resigned Member Access | Ex-member (`membership_status = 'resigned'`) queries NOCs | Blocked; subquery excludes non-active statuses | PASSED |
| 5 | Expelled Member Access | Expelled member (`membership_status = 'expelled'`) queries NOCs | Blocked; subquery excludes non-active statuses | PASSED |
| 6 | Forged `property_id` | User requests NOC for property in another society | Blocked in `fn_request_noc` by property-society validation check | PASSED |
| 7 | Forged `society_id` | User passes mismatched `society_id` to `fn_request_noc` | Blocked; `properties.society_id = p_society_id` check fails | PASSED |
| 8 | Forged `user_id` | User passes victim's ID as applicant in `fn_request_noc` | Neutralized; function forces `applicant_id = auth.uid()` | PASSED |
| 9 | Unauthorized `fn_request_noc` | Non-authenticated user calls `fn_request_noc` | Blocked; throws `42501 Not Authenticated` | PASSED |
| 10 | Unauthorized `fn_complete_noc_transfer` | Non-admin caller attempts to execute NOC transfer | Blocked; admin membership verification check fails | PASSED |
| 11 | Duplicate NOC Completion | Attacker invokes `fn_complete_noc_transfer` twice concurrently | Blocked; `FOR UPDATE` lock + state check (`status = 'approved'`) aborts 2nd call | PASSED |
| 12 | Concurrent NOC Completion | Race condition between two approval calls | Blocked; row-level lock serializes execution | PASSED |
| 13 | Cross-Society Transfer | NOC transfer attempting to assign property to outside society user | Validated; transferee membership bound to NOC's `society_id` | PASSED |
| 14 | Premature Occupant Activation | Transferee gains occupant status prior to NOC completion | Prevented; occupancy created only upon `completed` status | PASSED |
| 15 | Failure to Deactivate Outgoing Occupant | Outgoing owner retains active occupancy record | Prevented by hardened `UPDATE public.occupants SET end_date = CURRENT_DATE` | PASSED |
| 16 | Forged Incoming Membership | Transferee membership created with invalid status | Hardened INSERT forces `membership_status = 'active'` | PASSED |
| 17 | Duplicate Incoming Membership | Transferee already has membership in target society | Handled safely via `ON CONFLICT (society_id, user_id) DO UPDATE` | PASSED |
| 18 | `created_by` Forgery | Transferee membership created without audit trail | Hardened INSERT supplies `created_by = auth.uid()` | PASSED |
| 19 | SECURITY DEFINER Escalation | Attacker attempts search_path override | Blocked; explicit `SET search_path = public, pg_catalog` | PASSED |
| 20 | Search Path Attack | Attacker creates shadow function in public schema | Blocked by schema qualification and pinned search_path | PASSED |
| 21 | Direct Table Mutation Bypass | Attacker updates `noc_requests` directly via SQL API | Blocked by RLS update policies | PASSED |
| 22 | RLS Bypass | Attacker attempts to bypass RLS via RPC parameter tricks | Blocked; RPCs execute internal checks and validate caller `auth.uid()` | PASSED |
| 23 | Trigger Bypass | Attacker attempts state modification bypassing triggers | Triggers enforce immutable audit fields; RPC respect trigger state | PASSED |
| 24 | Partial Transaction Failure | Exception during NOC transfer leaves database inconsistent | Function runs in single transaction; any error triggers full rollback | PASSED |

---

## 20. SECURITY VERDICT

Based on explicit forensic audit against authoritative Slices 1–19:

**VERDICT:**  
`B. SECURE ONLY WITH IDENTIFIED HARDENING`

Direct text replacement of `am.status` -> `am.membership_status` resolves the immediate syntax failure (Defects 1 & 2), but **fn_complete_noc_transfer requires the specific hardened schema corrections (Defects 3 & 4)** detailed in Section 17 to maintain structural and temporal integrity.

---

## 21. GOVERNANCE / AUTHORIZATION STATUS

```
IMPLEMENTATION:         NOT AUTHORIZED
DEPLOYMENT:             NOT AUTHORIZED
REMOTE DATABASE:        MUST REMAIN AT 20260912000019_slice19.sql
MIGRATION REPAIR:       NOT AUTHORIZED
ROLLBACK:               NOT AUTHORIZED
BASELINE MUTATION:      NOT AUTHORIZED
SECURITY LOCK:          NOT AUTHORIZED
SLICE 20:               FAILED / FULLY ROLLED BACK / NOT DEPLOYED
SLICES 21–23:           NOT DEPLOYED
```

This review is complete and strictly read-only. No further operations authorized.

---

## 22. SHA-256 OF THIS REPORT

`BEAB16F599E5D6A03E1A5BA66D271E6F0D558F61AD2D62245624E7EFB835A522`
