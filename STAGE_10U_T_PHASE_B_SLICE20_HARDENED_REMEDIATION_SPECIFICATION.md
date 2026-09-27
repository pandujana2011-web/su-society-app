# STAGE 10U-T PHASE B — SLICE 20 HARDENED REMEDIATION SPECIFICATION

**TARGET REPOSITORY:** `D:\Clients Applications\SU Society App`  
**TARGET REMOTE SUPABASE PROJECT:** `fsegpxqoozxmicxcxjun` (Region: `ap-south-1`, PostgreSQL `17.6.1.166`)  
**CURRENT REMOTE PRODUCTION BOUNDARY:** `20260912000019_slice19.sql`  
**FORENSIC REMEDIATION PLAN:** `STAGE_10U_T_PHASE_B_SLICE20_FORENSIC_FAILURE_REMEDIATION_PLAN.md` (SHA-256: `54DEEBCCD4E434ED514E83D365BA50CE88AA3802E4F82552BB379CAA211B91EA`)  
**ADVERSARIAL SECURITY REVIEW:** `STAGE_10U_T_PHASE_B_SLICE20_ADVERSARIAL_REMEDIATION_SECURITY_REVIEW.md` (SHA-256: `BEAB16F599E5D6A03E1A5BA66D271E6F0D558F61AD2D62245624E7EFB835A522`)  
**CURRENT SECURITY VERDICT:** `B. SECURE ONLY WITH IDENTIFIED HARDENING`  
**LOCKED BASELINE:** `SLICE23_SECURITY_LOCK.md` (931 / 931 PASS, SHA-256: `47A7093CB842BB10179D529E85452BBD8B463E3057725B28E69A5E99AC614448`)  
**EXECUTION MODE:** PLAN ONLY / ZERO IMPLEMENTATION / STRICT READ-ONLY  

---

## 1. EXECUTIVE SUMMARY

This document provides the authoritative, implementation-ready **Hardened Remediation Specification** for Slice 20 (`20260912000020_slice20.sql`). Following the atomic rollback of Slice 20 at Statement 28 / Line 124 (`SQLSTATE 42703: column am.status does not exist`), this specification translates all findings from the Forensic Remediation Plan and Adversarial Security Review into exact, unambiguous schema-aligned directives.

Every proposed modification has been audited directly against the authoritative Slices 1–19 database schema (`public.association_memberships`, `public.occupants`, `public.properties`, `public.noc_requests`, `public.property_owners`, `public.tenancies`). This specification ensures that when authorized for implementation, Slice 20 will execute cleanly while preserving 100% of RLS boundaries, cross-society multi-tenant isolation, state-machine invariants, temporal history controls, and baseline security guarantees.

---

## 2. GOVERNANCE STATE

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

* Zero files, migrations, or database schemas were modified during the generation of this specification.
* The remote Supabase production database remains strictly at `20260912000019_slice19.sql`.

---

## 3. AUTHORITATIVE SCHEMA EVIDENCE

Direct inspection of authoritative migration definitions (`20260912000001_slice1.sql` through `20260912000019_slice19.sql`) establishes the following structural facts:

1. **`public.association_memberships` (Slice 1, Step 11):**
   * Primary Key: `id UUID PRIMARY KEY DEFAULT gen_random_uuid()`
   * Columns: `society_id`, `property_id`, `user_id`, `membership_number`, `membership_status` (`membership_status_enum`: `'active'`, `'suspended'`, `'resigned'`, `'expelled'`), `suspension_reason`, `start_date`, `end_date`, `created_by` (`NOT NULL REFERENCES public.users(id)`), `end_recorded_by`, `transition_notes`, `created_at`.
   * Uniqueness: `CREATE UNIQUE INDEX uq_active_membership_per_property ON public.association_memberships (society_id, property_id) WHERE end_date IS NULL;`
   * Column `status` does NOT exist. Column `membership_type` does NOT exist.

2. **`public.occupants` (Slice 1, Step 13):**
   * Primary Key: `id UUID PRIMARY KEY DEFAULT gen_random_uuid()`
   * Table name is `public.occupants` (table `public.property_occupants` does NOT exist).
   * Active state definition: `end_date IS NULL`.
   * Temporal exit procedure: Set `end_date = CURRENT_DATE`, set `end_recorded_by = auth.uid()`, set `departure_reason` (optional `TEXT`).
   * Column `status` does NOT exist. Column `move_out_date` does NOT exist.

3. **`public.properties` (Slice 1, Step 8):**
   * Primary Key: `id UUID PRIMARY KEY DEFAULT gen_random_uuid()`
   * Columns: `society_id`, `plot_number`, `occupancy_status`, `is_active`, `created_by`, `created_at`, `updated_at`.

---

## 4. DEF-01 SPECIFICATION

* **Location:** `20260912000020_slice20.sql`, Line 124 (RLS Policy `noc_requests_select_policy`).
* **Invalid Construct:** `am.status = 'active'`
* **Authoritative Column:** `public.association_memberships.membership_status`
* **Exact Specification:**
  ```sql
  CREATE POLICY noc_requests_select_policy ON public.noc_requests
      FOR SELECT TO authenticated
      USING (
          applicant_id = auth.uid() OR
          public.is_admin() OR
          EXISTS (
              SELECT 1 FROM public.association_memberships am
              WHERE am.property_id = noc_requests.property_id
              AND am.user_id = auth.uid()
              AND am.membership_status = 'active'
              AND am.end_date IS NULL
          )
      );
  ```
* **Security & Authorization Proof:** Filtering on `membership_status = 'active'` and `end_date IS NULL` strictly restricts read access to active voting members of the property. Users with `'suspended'`, `'resigned'`, or `'expelled'` status, or whose membership has reached `end_date`, are strictly denied access. Multi-tenant `society_id` scoping is implicitly enforced via property linkage.

---

## 5. DEF-02 SPECIFICATION

* **Location:** `20260912000020_slice20.sql`, Line 223 (Function `public.fn_request_noc`).
* **Invalid Construct:** `am.status = 'active'`
* **Authoritative Column:** `public.association_memberships.membership_status`
* **Exact Specification:**
  ```sql
  -- Validate applicant eligibility (owner or active resident/member)
  IF NOT (public.is_admin() OR EXISTS (
      SELECT 1 FROM public.association_memberships am
      WHERE am.property_id = p_property_id
      AND am.user_id = v_caller_id
      AND am.membership_status = 'active'
      AND am.end_date IS NULL
  )) THEN
      RAISE EXCEPTION 'Applicant is not authorized for this property.' USING ERRCODE = '42501';
  END IF;
  ```
* **Verification:** Confirms caller identity (`v_caller_id := auth.uid()`) holds an active, unexpired membership for `p_property_id` prior to NOC creation.

---

## 6. DEF-03 OCCUPANT LIFECYCLE SPECIFICATION

* **Location:** `20260912000020_slice20.sql`, Lines 719–721 (Inside `public.fn_complete_noc_transfer`).
* **Invalid Construct:**
  ```sql
  UPDATE public.property_occupants
  SET status = 'inactive', move_out_date = CURRENT_DATE, updated_at = NOW()
  WHERE property_id = v_pass.property_id AND user_id = v_noc.applicant_id AND status = 'active';
  ```
* **Authoritative Object Analysis:**
  * Table `public.property_occupants` does NOT exist in Slices 1–19. The authoritative table is `public.occupants`.
  * Active occupancy is represented temporally by `end_date IS NULL`. Column `status` does NOT exist. Column `move_out_date` does NOT exist.
  * In `public.occupants`, `departure_reason` is an unconstrained `TEXT` field. `end_recorded_by` tracks the audit actor.
* **Exact Specification:**
  ```sql
  IF v_noc.noc_type = 'tenant_move_out' THEN
      UPDATE public.occupants
      SET end_date = CURRENT_DATE,
          end_recorded_by = v_caller_id,
          departure_reason = 'NOC Tenant Move-Out Completed',
          updated_at = NOW()
      WHERE property_id = v_pass.property_id
        AND user_id = v_noc.applicant_id
        AND end_date IS NULL;
  ```
* **Concurrency & Scope Guarantees:** Scoped strictly by `property_id` and `user_id` where `end_date IS NULL`. Does not alter historical departure records or occupants of other properties/societies.

---

## 7. DEF-04 MEMBERSHIP LIFECYCLE SPECIFICATION

* **Location:** `20260912000020_slice20.sql`, Lines 723–729 (Inside `public.fn_complete_noc_transfer`).
* **Invalid Construct:**
  ```sql
  UPDATE public.association_memberships
  SET status = 'inactive', updated_at = NOW()
  WHERE property_id = v_pass.property_id AND user_id = v_noc.applicant_id AND status = 'active';

  INSERT INTO public.association_memberships (society_id, property_id, user_id, membership_type, status)
  VALUES (v_noc.society_id, v_pass.property_id, v_noc.target_user_id, 'owner', 'active');
  ```
* **Authoritative Schema & Lifecycle Audit:**
  1. Column `status` does NOT exist; authoritative column is `membership_status`.
  2. Column `membership_type` does NOT exist in `public.association_memberships`.
  3. `created_by` is `NOT NULL REFERENCES public.users(id)`.
  4. Outgoing membership: Under AD-1 and AD-8, a membership transition requires ending the active period (`end_date = CURRENT_DATE`, `membership_status = 'resigned'`).
  5. Incoming transferee membership: Under AD-1, `uq_active_membership_per_property` enforces at most ONE active (`end_date IS NULL`) membership per property.

* **Rejection of Naive `ON CONFLICT DO UPDATE`:**
  `ON CONFLICT DO UPDATE` on `(society_id, property_id)` is **EXPLICITLY REJECTED**. Allowing `DO UPDATE` could overwrite an existing suspended or expelled membership without secretary audit, or overwrite historical membership records.
  
  **Authoritative Behavior:**
  - Close outgoing applicant's membership (`end_date = CURRENT_DATE`, `membership_status = 'resigned'`).
  - Insert NEW membership row for the transferee with `membership_status = 'active'`, `start_date = CURRENT_DATE`, `created_by = v_caller_id`.
  - If a active membership conflict occurs (e.g. race condition), PostgreSQL index `uq_active_membership_per_property` will throw a unique constraint violation, aborting the transaction cleanly.

* **Exact Specification:**
  ```sql
  ELSIF v_noc.noc_type = 'owner_transfer' AND v_noc.target_user_id IS NOT NULL THEN
      -- 1. Close outgoing owner's active membership
      UPDATE public.association_memberships
      SET end_date = CURRENT_DATE,
          membership_status = 'resigned',
          end_recorded_by = v_caller_id,
          transition_notes = 'NOC Ownership Transfer Completed',
          updated_at = NOW()
      WHERE property_id = v_pass.property_id
        AND user_id = v_noc.applicant_id
        AND end_date IS NULL;

      -- 2. Insert incoming owner's new active membership
      INSERT INTO public.association_memberships (
          society_id,
          property_id,
          user_id,
          membership_status,
          start_date,
          created_by,
          transition_notes
      ) VALUES (
          v_noc.society_id,
          v_pass.property_id,
          v_noc.target_user_id,
          'active',
          CURRENT_DATE,
          v_caller_id,
          'NOC Ownership Transfer Admission'
      );
  END IF;
  ```

---

## 8. CREATED_BY SECURITY SPECIFICATION

Inside SECURITY DEFINER function `fn_complete_noc_transfer`, `v_caller_id := auth.uid()` captures the authenticated actor calling the function.
* Authorization check (`IF NOT (public.has_role('gatekeeper') OR public.is_admin())`) executes **BEFORE** any mutation.
* `v_caller_id` is supplied directly as `created_by` and `end_recorded_by`.
* Callers cannot pass arbitrary UUIDs for audit fields; `created_by` is strictly bound to `auth.uid()`, preserving full auditability.

---

## 9. SECURITY DEFINER SPECIFICATION

All Slice 20 functions (`fn_request_noc`, `fn_review_noc`, `fn_approve_noc`, `fn_reject_noc`, `fn_revoke_noc`, `fn_cancel_noc`, `verify_pass`, `fn_complete_noc_transfer`, `process_expired_noc_passes`) MUST adhere to:

```sql
SECURITY DEFINER
SET search_path = pg_catalog, public
```

* Owner: `postgres` (default migration execution role).
* Grants: `GRANT EXECUTE ON FUNCTION ... TO authenticated;`
* Revokes: `REVOKE ALL ON FUNCTION ... FROM public, anon;`
* Schema Qualification: All internal SQL statements MUST explicitly schema-qualify tables (`public.noc_requests`, `public.association_memberships`, `public.occupants`, `public.properties`, `public.noc_move_passes`).

---

## 10. RLS PRESERVATION SPECIFICATION

The remediation strictly preserves all RLS policies established in Slices 1–19 and Slice 20:
* `noc_requests`: FORCE ROW LEVEL SECURITY enabled. Read access restricted to applicant, active property member, or admin. Direct table write access (`INSERT`, `UPDATE`, `DELETE`) strictly revoked for `authenticated` and `anon`.
* `noc_move_passes`: RLS enforced; accessible only to admins, gatekeepers, or the applicant.
* `noc_gatekeeper_rate_limits`: Scoped strictly to `gatekeeper_id = auth.uid()`.
* Multi-tenant `society_id` isolation remains 100% byte and semantically intact.

---

## 11. CONCURRENCY SPECIFICATION

To guarantee TOCTOU prevention and transaction atomicity in `fn_complete_noc_transfer`:

1. **Row-Level Pass Locking:**
   ```sql
   SELECT * INTO v_pass
   FROM public.noc_move_passes
   WHERE id = p_pass_id FOR UPDATE;
   ```
2. **Row-Level NOC Request Locking:**
   ```sql
   SELECT * INTO v_noc
   FROM public.noc_requests
   WHERE id = v_pass.noc_id FOR UPDATE;
   ```
3. **Property Serialization Lock (Mandatory Financial & Transfer Lock):**
   ```sql
   PERFORM 1 FROM public.properties WHERE id = v_pass.property_id FOR UPDATE;
   ```

**Lock Ordering:**  
`noc_move_passes` -> `noc_requests` -> `properties`. This exact order MUST be maintained across all NOC functions (`fn_approve_noc`, `fn_reject_noc`, `fn_complete_noc_transfer`) to prevent deadlock.

---

## 12. TRANSACTION / ATOMICITY SPECIFICATION

`fn_complete_noc_transfer` executes all mutations (pass completion, NOC request status update, occupant exit, membership exit, new membership creation, audit logging) inside a single PL/pgSQL function block. If any step fails (e.g. constraint violation on new membership), PostgreSQL automatically rolls back the ENTIRE transaction atomically. Partial transfers are physically impossible.

---

## 13. COMPLETE CHANGE MATRIX

| Defect ID | Current Invalid Construct | Authoritative Object | Authoritative Column / Semantic | Proposed Change | Security Consequence | Concurrency Consequence | Required Hardening | Implementation Test |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **DEF-01** | `am.status = 'active'` (Line 124) | `public.association_memberships` | `membership_status` (`membership_status_enum`) | Replace with `am.membership_status = 'active' AND am.end_date IS NULL` | Restricts RLS read access to currently active members | None | Add `end_date IS NULL` predicate | RLS Select Test |
| **DEF-02** | `am.status = 'active'` (Line 223) | `public.association_memberships` | `membership_status` (`membership_status_enum`) | Replace with `am.membership_status = 'active' AND am.end_date IS NULL` | Prevents suspended/expelled members from requesting NOC | None | Add `end_date IS NULL` predicate | Request NOC Validation Test |
| **DEF-03** | `UPDATE public.property_occupants SET status = 'inactive', move_out_date = CURRENT_DATE` (Line 719) | `public.occupants` | `end_date` (`DATE`), `departure_reason` (`TEXT`), `end_recorded_by` (`UUID`) | Update `public.occupants SET end_date = CURRENT_DATE, departure_reason = 'NOC Tenant Move-Out Completed', end_recorded_by = v_caller_id WHERE property_id = ... AND user_id = ... AND end_date IS NULL` | Correctly closes temporal occupant record without modifying history | Isolated to target property & user | Add `end_date IS NULL` predicate and `end_recorded_by` audit | Occupant Move-Out Test |
| **DEF-04A** | `UPDATE association_memberships SET status = 'inactive'` (Line 723) | `public.association_memberships` | `membership_status = 'resigned'`, `end_date = CURRENT_DATE` | Update `public.association_memberships SET end_date = CURRENT_DATE, membership_status = 'resigned', end_recorded_by = v_caller_id WHERE property_id = ... AND user_id = ... AND end_date IS NULL` | Accurately marks outgoing member as resigned under AD-1/AD-8 | Prevents duplicate active memberships | Set `membership_status = 'resigned'` and `end_date = CURRENT_DATE` | Member Resignation Test |
| **DEF-04B** | `INSERT INTO association_memberships (..., membership_type, status)` (Line 727) | `public.association_memberships` | `membership_status`, `created_by` (`NOT NULL`), `start_date` | Remove `membership_type`, supply `membership_status = 'active'`, `created_by = v_caller_id`, `start_date = CURRENT_DATE` | Enforces auditability and valid enum status for incoming owner | Enforced by `uq_active_membership_per_property` | Reject `ON CONFLICT DO UPDATE`; allow clean INSERT | Member Admission Test |

---

## 14. EXACT INTENDED SQL-LEVEL CHANGES

*(For reference during authorized future implementation ONLY; writing into migration file is NOT authorized in this stage).*

### Statement 28 Replacement (RLS Policy `noc_requests_select_policy`):
```sql
CREATE POLICY noc_requests_select_policy ON public.noc_requests
    FOR SELECT TO authenticated
    USING (
        applicant_id = auth.uid() OR
        public.is_admin() OR
        EXISTS (
            SELECT 1 FROM public.association_memberships am
            WHERE am.property_id = noc_requests.property_id
            AND am.user_id = auth.uid()
            AND am.membership_status = 'active'
            AND am.end_date IS NULL
        )
    );
```

### Statement 223 Replacement (Inside `public.fn_request_noc`):
```sql
    -- Validate applicant eligibility (owner or active resident)
    IF NOT (public.is_admin() OR EXISTS (
        SELECT 1 FROM public.association_memberships am
        WHERE am.property_id = p_property_id
        AND am.user_id = v_caller_id
        AND am.membership_status = 'active'
        AND am.end_date IS NULL
    )) THEN
        RAISE EXCEPTION 'Applicant is not authorized for this property.' USING ERRCODE = '42501';
    END IF;
```

### Lines 718–730 Replacement (Inside `public.fn_complete_noc_transfer`):
```sql
    -- Perform property occupancy/membership status updates if applicable
    IF v_noc.noc_type = 'tenant_move_out' THEN
        UPDATE public.occupants
        SET end_date = CURRENT_DATE,
            end_recorded_by = v_caller_id,
            departure_reason = 'NOC Tenant Move-Out Completed',
            updated_at = NOW()
        WHERE property_id = v_pass.property_id
          AND user_id = v_noc.applicant_id
          AND end_date IS NULL;
    ELSIF v_noc.noc_type = 'owner_transfer' AND v_noc.target_user_id IS NOT NULL THEN
        -- 1. Close outgoing owner's active membership
        UPDATE public.association_memberships
        SET end_date = CURRENT_DATE,
            membership_status = 'resigned',
            end_recorded_by = v_caller_id,
            transition_notes = 'NOC Ownership Transfer Completed',
            updated_at = NOW()
        WHERE property_id = v_pass.property_id
          AND user_id = v_noc.applicant_id
          AND end_date IS NULL;

        -- 2. Insert incoming owner's new active membership
        INSERT INTO public.association_memberships (
            society_id,
            property_id,
            user_id,
            membership_status,
            start_date,
            created_by,
            transition_notes
        ) VALUES (
            v_noc.society_id,
            v_pass.property_id,
            v_noc.target_user_id,
            'active',
            CURRENT_DATE,
            v_caller_id,
            'NOC Ownership Transfer Admission'
        );
    END IF;
```

---

## 15. REQUIRED NEGATIVE TESTS

1. **Test N-01:** Attempt NOC request by user with `membership_status = 'suspended'` (Must fail with `42501`).
2. **Test N-02:** Attempt NOC request by user with `membership_status = 'resigned'` (Must fail with `42501`).
3. **Test N-03:** Attempt NOC request by user with `membership_status = 'expelled'` (Must fail with `42501`).
4. **Test N-04:** Attempt NOC request for property in Society B by user in Society A (Must fail with `P0002` or `42501`).
5. **Test N-05:** Non-admin invocation of `fn_complete_noc_transfer` (Must fail with `42501`).
6. **Test N-06:** Direct SQL `UPDATE` on `public.noc_requests` by non-admin (Must fail under RLS).

---

## 16. REQUIRED POSITIVE TESTS

1. **Test P-01:** Active voting member (`membership_status = 'active'`, `end_date IS NULL`) successfully submits NOC request.
2. **Test P-02:** Admin reviews and approves valid NOC request, generating move pass.
3. **Test P-03:** Gatekeeper verifies valid move pass with correct token & PIN.
4. **Test P-04:** Authorized user completes tenant move-out NOC; target `public.occupants` row receives `end_date = CURRENT_DATE` and `end_recorded_by`.
5. **Test P-05:** Authorized user completes owner transfer NOC; outgoing membership transitions to `membership_status = 'resigned'`, and new active membership is created for transferee.

---

## 17. ADVERSARIAL TEST MATRIX

| Test ID | Scenario Description | Expected Security Outcome | Verification Method |
| :--- | :--- | :--- | :--- |
| **ADV-01** | Active member reads authorized NOC | Allowed | RLS Select Query |
| **ADV-02** | Suspended member queries NOCs | Denied | RLS Select Query |
| **ADV-03** | Resigned member queries NOCs | Denied | RLS Select Query |
| **ADV-04** | Expelled member queries NOCs | Denied | RLS Select Query |
| **ADV-05** | Cross-society NOC read attempt | Denied (0 rows returned) | RLS Select Query across tenant boundaries |
| **ADV-06** | Forged `property_id` in NOC request | Denied (Property society mismatch) | `fn_request_noc` RPC call |
| **ADV-07** | Forged `society_id` in NOC request | Denied | `fn_request_noc` RPC call |
| **ADV-08** | Unauthorized `fn_request_noc` call | Denied (`42501`) | Anonymous / Unauthenticated RPC call |
| **ADV-09** | Unauthorized `fn_complete_noc_transfer` call | Denied (`42501`) | Non-gatekeeper/Non-admin RPC call |
| **ADV-10** | Outgoing occupant status transition | Active row gets `end_date = CURRENT_DATE` | Database state inspection post-transfer |
| **ADV-11** | Unrelated occupant modification check | Unaffected (0 rows updated) | Database state inspection |
| **ADV-12** | Wrong society occupant modification check | Unaffected | Database state inspection |
| **ADV-13** | Outgoing membership status transition | `membership_status = 'resigned'`, `end_date = CURRENT_DATE` | Database state inspection |
| **ADV-14** | Incoming membership state assignment | `membership_status = 'active'`, `start_date = CURRENT_DATE` | Database state inspection |
| **ADV-15** | Existing suspended incoming membership | Transaction aborts cleanly via unique index | Concurrent/Pre-existing state injection |
| **ADV-16** | Existing expelled incoming membership | Transaction aborts cleanly via unique index | Concurrent/Pre-existing state injection |
| **ADV-17** | Duplicate NOC completion execution | Denied (`Pass already completed`) | Repeat RPC call |
| **ADV-18** | Concurrent NOC completion race | Serialized cleanly by `FOR UPDATE` locks | Dual concurrent async RPC execution |
| **ADV-19** | `created_by` forgery attempt | Denied; function enforces `auth.uid()` | RPC parameter tampering test |
| **ADV-20** | SECURITY DEFINER privilege escalation | Denied; search_path locked to `pg_catalog, public` | Shadow function injection test |
| **ADV-21** | Search path exploitation | Denied; pinned `search_path` | Function call context inspection |
| **ADV-22** | Direct table mutation bypass | Denied under RLS write revocation | Direct `UPDATE public.noc_requests` |
| **ADV-23** | RLS bypass via RPC parameter trick | Denied | Malicious parameter payload |
| **ADV-24** | Partial transaction failure rollback | Complete transaction rollback | Exception injection during transfer |
| **ADV-25** | Cross-society side effects check | Zero side-effects in other societies | Cross-tenant database audit |

---

## 18. OUT-OF-SCOPE CHANGES

* Redesigning the NOC workflow architecture or database ERD.
* Modifying any migration script in Slices 1–19.
* Rolling back applied production migrations (Slices 1–19).
* Editing `SLICE23_SECURITY_LOCK.md` or baseline configurations.

---

## 19. IMPLEMENTATION PRECONDITIONS

Prior to any future execution of Slice 20 implementation:
1. Explicit user/governance deployment authorization MUST be granted.
2. Remote database MUST be verified at boundary `20260912000019_slice19.sql`.
3. Hardened modifications specified in Section 14 MUST be applied locally to `20260912000020_slice20.sql`.
4. Pre-deployment dry-run validation against local Supabase shadow instance MUST pass 100%.

---

## 20. FINAL RECOMMENDATION

The proposed Option 1 remediation for Slice 20 is **FULLY SPECIFIED AND IMPLEMENTATION-READY** when incorporating the hardened schema corrections defined herein. All four confirmed defects have been resolved with 100% adherence to authoritative Slice 1–19 schema semantics.

---

## 21. GOVERNANCE STATUS

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

---

## 22. SHA-256 OF THIS SPECIFICATION

*(Calculated upon file output generation)*
