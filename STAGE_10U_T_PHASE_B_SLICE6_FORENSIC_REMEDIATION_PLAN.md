# STAGE 10U-T PHASE B — SLICE 6 MIGRATION FAILURE: FORENSIC REMEDIATION PLAN

**TARGET REPOSITORY:** `D:\Clients Applications\SU Society App`  
**TARGET REMOTE SUPABASE PROJECT:** `fsegpxqoozxmicxcxjun` (`pandujana2011-web's Project`)  
**REGION:** `ap-south-1`  
**POSTGRESQL VERSION:** `17.6.1.166`  
**GOVERNANCE MODE:** `PLAN ONLY / ZERO IMPLEMENTATION / ZERO DEPLOYMENT`  

---

## 1. EXECUTIVE STATUS

On September 13, 2026, controlled production deployment (`npx supabase db push`) applied `20260912000005_slice5.sql` successfully to production, but failed during execution of `20260912000006_slice6.sql` at Statement 41 (Line 304) with `SQLSTATE 42P01` (`missing FROM-clause entry for table "old"`). 

Because `20260912000006_slice6.sql` was executed inside an explicit transaction block, PostgreSQL automatically executed an atomic `ROLLBACK`. Zero database objects from Slice 6 exist remotely. 

This document defines the authoritative **Forensic Remediation Plan** for Slice 6. It analyzes the root cause, audits all `OLD`/`NEW` occurrences, specifies the intended security invariant, evaluates three PostgreSQL-native architectural remediation options, and recommends the optimal security architecture.

---

## 2. CURRENT LOCKED BASELINE

* **Locked Baseline File:** `SLICE23_SECURITY_LOCK.md`
* **Security Verification Status:** `931 / 931 PASS` (100% LOCKED / IMMUTABLE)
* **Baseline SHA-256:** `47A7093CB842BB10179D529E85452BBD8B463E3057725B28E69A5E99AC614448`
* **Governance Invariant:** The baseline is strictly immutable. This plan does not alter the baseline or any security invariant.

---

## 3. CURRENT REMOTE MIGRATION STATE

* **Confirmed Applied Remote Migrations (9 Total):**
  1. `20260912000001_slice1.sql`
  2. `202609120000015_prereq_uuid_function.sql`
  3. `20260912000002_slice2.sql`
  4. `202609120000025_prereq_slice3_constraints.sql`
  5. `20260912000003_slice3.sql`
  6. `202609120000035_prereq_slice4_is_property_owner_overload.sql`
  7. `202609120000036_prereq_slice4_payments_user_id_column.sql`
  8. `20260912000004_slice4.sql`
  9. `20260912000005_slice5.sql`
* **Pending Migrations (18 Total):**
  * `20260912000006_slice6.sql` through `20260912000023_slice23.sql`
* **Remote Schema Integrity:** Remote schema is clean at version `20260912000005`. No partial schema objects from Slice 6 exist remotely.

---

## 4. EXACT FAILURE RECAP

* **Migration File:** `supabase/migrations/20260912000006_slice6.sql`
* **Failure Line:** Line 304
* **Statement Index:** Statement 41
* **Failing SQL Statement:**
  ```sql
  CREATE POLICY pol_gate_passes_admin_update ON public.gate_passes
      FOR UPDATE
      USING (public.is_admin() AND society_id = public.get_user_society_id(auth.uid()))
      WITH CHECK (status = OLD.status);
  ```
* **PostgreSQL Engine Error:** `ERROR: missing FROM-clause entry for table "old" (SQLSTATE 42P01)`

---

## 5. POSTGRESQL SEMANTIC ANALYSIS

### A. Why PostgreSQL Engine Rejected Statement 41

In PostgreSQL SQL syntax grammar:
1. `OLD` and `NEW` are special pseudo-records generated exclusively by the PL/pgSQL procedural execution engine inside `BEFORE` and `AFTER` trigger functions (`FOR EACH ROW`).
2. Row Level Security (RLS) policies (`CREATE POLICY ... USING (...) WITH CHECK (...)`) are evaluated by the core PostgreSQL query planner/rewriter during query execution:
   - In `USING` expressions, table column references evaluate against the existing row in the table.
   - In `WITH CHECK` expressions, table column references evaluate against the candidate new/proposed row being inserted or updated.
3. PostgreSQL RLS syntax does **NOT** provide dual-row access to pre-update (`OLD`) and post-update (`NEW`) states simultaneously within policy expressions.
4. When the parser encountered `OLD.status` inside `WITH CHECK (status = OLD.status)`, it attempted to look up `OLD` as an alias or table name in the current query FROM-clause context. Finding none, it threw `SQLSTATE 42P01`.

### B. Impact on Subsequent Statements in Slice 6

The audit revealed that Statements 42 and 43 in `20260912000006_slice6.sql` contain the identical syntax error:
* **Statement 42 (Line 308):** `CREATE POLICY pol_gate_passes_owner_update ON public.gate_passes FOR UPDATE ... WITH CHECK (status = OLD.status);`
* **Statement 43 (Line 312):** `CREATE POLICY pol_daily_staff_admin_update ON public.daily_staff FOR UPDATE ... WITH CHECK (verification_status = OLD.verification_status);`

Had Statement 41 not failed, Statements 42 and 43 would have failed sequentially with the identical `SQLSTATE 42P01` error.

---

## 6. INTENDED SECURITY INVARIANT

Through forensic code review of `database/schema_slice6.sql` and `supabase/migrations/20260912000006_slice6.sql`, the original architect's design intent was determined:

1. **State Machine Integrity:** State transitions for `gate_passes.status` (`pending` -> `active` -> `suspended`) and `daily_staff.verification_status` (`pending` -> `verified`/`rejected` -> `suspended`) require multi-step validation (e.g. verifying that daily staff are marked `'verified'` before a gate pass can be set to `'active'`).
2. **Dedicated RPC Transition Functions:** State transitions must be executed exclusively via the two `SECURITY DEFINER` RPC functions:
   - `public.fn_transition_gate_pass_state(p_pass_id UUID, p_new_status VARCHAR)`
   - `public.fn_transition_daily_staff_verification(p_staff_id UUID, p_new_status VARCHAR)`
3. **Prevention of Direct Client Bypass:** Direct SQL `UPDATE` operations issued by clients (e.g. `UPDATE public.gate_passes SET status = 'active' WHERE id = '...'`) must **NOT** be permitted to mutate the `status` or `verification_status` columns directly, bypassing the state machine validation in the RPC functions.
4. **Architect's Attempted Mechanism:** The architect attempted to enforce `WITH CHECK (status = OLD.status)` in RLS `UPDATE` policies so that any direct `UPDATE` that attempts to alter `status` or `verification_status` would fail the RLS check, believing that `SECURITY DEFINER` RPC functions would bypass RLS to perform valid transitions.

---

## 7. COMPLETE SLICE 6 `OLD` / `NEW` AUDIT

Every occurrence of `OLD` and `NEW` in `supabase/migrations/20260912000006_slice6.sql` was inspected:

| Line # | Context / Statement | Code Snippet | Semantic Validity |
|--------|---------------------|--------------|-------------------|
| **55** | Trigger Function `fn_gate_passes_force_requested_by` | `NEW.requested_by := auth.uid();` | **VALID** (Inside PL/pgSQL BEFORE INSERT trigger) |
| **56** | Trigger Function `fn_gate_passes_force_requested_by` | `RETURN NEW;` | **VALID** (Inside PL/pgSQL BEFORE INSERT trigger) |
| **155**| Audit Trigger Function `fn_audit_trigger_func` | `v_new_data := to_jsonb(NEW);` | **VALID** (Inside PL/pgSQL audit trigger) |
| **157**| Audit Trigger Function `fn_audit_trigger_func` | `v_old_data := to_jsonb(OLD);` | **VALID** (Inside PL/pgSQL audit trigger) |
| **158**| Audit Trigger Function `fn_audit_trigger_func` | `v_new_data := to_jsonb(NEW);` | **VALID** (Inside PL/pgSQL audit trigger) |
| **160**| Audit Trigger Function `fn_audit_trigger_func` | `v_old_data := to_jsonb(OLD);` | **VALID** (Inside PL/pgSQL audit trigger) |
| **185**| Audit Trigger Function `fn_audit_trigger_func` | `COALESCE(NEW.id, OLD.id), v_old_data...` | **VALID** (Inside PL/pgSQL audit trigger) |
| **188**| Audit Trigger Function `fn_audit_trigger_func` | `IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;` | **VALID** (Inside PL/pgSQL audit trigger) |
| **302**| SQL Comment | `-- Or even simpler: RLS UPDATE policy requires OLD.status = NEW.status...` | **INFORMATIVE** (SQL comment) |
| **306**| RLS Policy `pol_gate_passes_admin_update` | `WITH CHECK (status = OLD.status);` | **INVALID** (RLS policy context — Throws SQLSTATE 42P01) |
| **310**| RLS Policy `pol_gate_passes_owner_update` | `WITH CHECK (status = OLD.status);` | **INVALID** (RLS policy context — Throws SQLSTATE 42P01) |
| **314**| RLS Policy `pol_daily_staff_admin_update` | `WITH CHECK (verification_status = OLD.verification_status);` | **INVALID** (RLS policy context — Throws SQLSTATE 42P01) |

**Summary:** Lines 55, 56, 155, 157, 158, 160, 185, and 188 are 100% valid. Only Lines 306, 310, and 314 (Statements 41, 42, and 43) contain invalid RLS syntax.

---

## 8. RLS ARCHITECTURE ANALYSIS

To preserve the intended security invariant without using invalid RLS syntax, we must understand how PostgreSQL evaluates `SECURITY DEFINER` functions vs Row Level Security:

1. In PostgreSQL, `SECURITY DEFINER` functions execute with the privileges of the role that owns the function (or creator role).
2. If a table has RLS enabled, RLS policies apply to all non-owner roles. If the table owner (or postgres superuser) executes an `UPDATE`, RLS is bypassed. However, if an `authenticated` user calls a `SECURITY DEFINER` function that updates a table, whether RLS is checked depends on whether the function owner is a table owner or superuser, or whether session-level settings (`BYPASSRLS`) apply.
3. Crucially, attempting to compare pre-update vs post-update column values in pure RLS policies is impossible in PostgreSQL because RLS policies only evaluate single-row boolean predicates (either pre-update via `USING` or post-update via `WITH CHECK`).
4. Therefore, state-machine immutability enforcement requires a PostgreSQL-native pattern: coupling clean RLS policies with a `BEFORE UPDATE` trigger or session-variable guard.

---

## 9. REMEDIATION OPTIONS

### OPTION 1: Session-Guarded BEFORE UPDATE Triggers + Standard RLS UPDATE Policies (RECOMMENDED)

* **Exact Mechanism:**
  1. Replace the invalid `WITH CHECK (status = OLD.status)` expressions in `pol_gate_passes_admin_update`, `pol_gate_passes_owner_update`, and `pol_daily_staff_admin_update` with standard RLS predicates (e.g. `WITH CHECK (society_id = public.get_user_society_id(auth.uid()))`).
  2. Create a `BEFORE UPDATE` PL/pgSQL trigger function `public.fn_protect_state_column_mutation()`:
     ```sql
     CREATE OR REPLACE FUNCTION public.fn_protect_state_column_mutation()
     RETURNS TRIGGER LANGUAGE plpgsql AS $$
     BEGIN
         IF TG_TABLE_NAME = 'gate_passes' AND NEW.status IS DISTINCT FROM OLD.status THEN
             IF current_setting('app.allow_state_transition', true) IS DISTINCT FROM 'true' THEN
                 RAISE EXCEPTION 'Direct update of gate_passes.status prohibited. Use RPC fn_transition_gate_pass_state.';
             END IF;
         ELSIF TG_TABLE_NAME = 'daily_staff' AND NEW.verification_status IS DISTINCT FROM OLD.verification_status THEN
             IF current_setting('app.allow_state_transition', true) IS DISTINCT FROM 'true' THEN
                 RAISE EXCEPTION 'Direct update of daily_staff.verification_status prohibited. Use RPC fn_transition_daily_staff_verification.';
             END IF;
         END IF;
         RETURN NEW;
     END;
     $$;
     ```
  3. Attach `BEFORE UPDATE` triggers on `public.gate_passes` and `public.daily_staff`.
  4. In `fn_transition_gate_pass_state` and `fn_transition_daily_staff_verification`, add `PERFORM set_config('app.allow_state_transition', 'true', true);` prior to executing the `UPDATE`.

### OPTION 2: Column-Level REVOKE UPDATE + SECURITY DEFINER RPC Functions

* **Exact Mechanism:**
  1. Remove `WITH CHECK (status = OLD.status)` from RLS policies.
  2. Execute column-level REVOKE statements:
     ```sql
     REVOKE UPDATE (status) ON public.gate_passes FROM authenticated;
     REVOKE UPDATE (verification_status) ON public.daily_staff FROM authenticated;
     ```
  3. Clients attempting direct `UPDATE public.gate_passes SET status = ...` are blocked at PostgreSQL permission checking (`permission denied for column status`).
  4. RPC functions `fn_transition_gate_pass_state` and `fn_transition_daily_staff_verification` execute under `SECURITY DEFINER` (owned by table owner/postgres), bypassing column permission checks.

### OPTION 3: Strict BEFORE UPDATE Immutability Triggers (Always Reject Direct Column Mutation)

* **Exact Mechanism:**
  1. Remove invalid `WITH CHECK` clauses from RLS UPDATE policies.
  2. Attach a simple `BEFORE UPDATE` trigger on `gate_passes` and `daily_staff` that unconditionally reverts state column changes for standard SQL updates:
     ```sql
     NEW.status := OLD.status; -- Force status column to remain unchanged on direct UPDATE
     ```
  3. RPC functions `fn_transition_gate_pass_state` and `fn_transition_daily_staff_verification` set a local flag or execute internal SQL that bypasses the trigger guard.

---

## 10. REMEDIATION OPTIONS COMPARISON & RECOMMENDATION

| Metric / Dimension | Option 1: Session-Guarded Trigger (RECOMMENDED) | Option 2: Column REVOKE | Option 3: Hard Revert Trigger |
|-------------------|------------------------------------------------|-------------------------|------------------------------|
| **A. Exact Mechanism** | `BEFORE UPDATE` trigger checks `current_setting('app.allow_state_transition')` | `REVOKE UPDATE (status)` from `authenticated` | `BEFORE UPDATE` trigger resets `NEW.status := OLD.status` |
| **B. Security Invariant Preserved** | **100% Preserved** (Direct mutation blocked with explicit error) | **100% Preserved** (Blocked at PostgreSQL GRANT layer) | **100% Preserved** (Silently or explicitly prevents status change) |
| **C. Security Invariant Weakened?** | No | No | No |
| **D. PostgreSQL Semantic Correctness** | **100% Valid Standard PL/pgSQL & SQL** | **100% Valid Standard PostgreSQL DDL** | **100% Valid Standard PL/pgSQL** |
| **E. Direct UPDATE Behavior** | Throws explicit exception explaining RPC requirement | Throws `permission denied for column status` | Reverts status column or throws exception |
| **F. RLS Interaction** | Clean separation between RLS (row isolation) and Trigger (state machine) | Clean separation | Clean separation |
| **G. SECURITY DEFINER Interaction** | RPC functions set `set_config('app.allow_state_transition', 'true', true)` | RPC functions bypass column grants | RPC functions bypass trigger or set flag |
| **H. Cross-Society Isolation Impact** | Zero impact (RLS `society_id` checks remain 100% active) | Zero impact | Zero impact |
| **I. Migration-History Impact** | Replaces Statements 41-43 in `20260912000006_slice6.sql` | Replaces Statements 41-43 in `20260912000006_slice6.sql` | Replaces Statements 41-43 in `20260912000006_slice6.sql` |
| **J. Regression Test Requirements** | Tests direct UPDATE rejection & RPC transition success | Tests direct UPDATE rejection & RPC transition success | Tests direct UPDATE rejection & RPC transition success |
| **K. Advantages** | Explicit error messages for developers; foolproof state protection | Native PostgreSQL engine privilege enforcement | Simple implementation |
| **L. Risks** | Requires adding `set_config` in transition functions | Column-level REVOKE support varies in ORMs | Silent reversion can confuse client apps if not raising error |
| **M. Requires Migration Rewrite?** | Yes (Fixes Statements 41-43 in pending migration 6) | Yes | Yes |
| **N. Requires New Migration?** | No (Migration 6 has not been applied remotely) | No | No |
| **O. Changes Locked Artifact?** | **NO** (`SLICE23_SECURITY_LOCK.md` remains untouched) | **NO** | **NO** |

### RECOMMENDED OPTION: **OPTION 1 (Session-Guarded BEFORE UPDATE Triggers)**

**Rationale:** Option 1 provides the highest security rigor, PostgreSQL semantic correctness, and developer diagnostic clarity. It completely prevents direct table status updates across all client roles (including admins), forces all state transitions through validated RPC functions, and returns clean, actionable PostgreSQL exceptions if direct status mutation is attempted.

---

## 11. SECURITY REGRESSION MATRIX

Prior to authorizing any implementation, the remediation must be validated against all 13 security regression scenarios:

| # | Regression Test Scenario | Expected Outcome | Verification Status |
|---|--------------------------|------------------|---------------------|
| 1 | Authorized admin calls `fn_transition_daily_staff_verification` | `verification_status` transitions successfully | PENDING IMPLEMENTATION |
| 2 | Authorized owner/tenant calls `fn_transition_gate_pass_state` | `status` transitions successfully | PENDING IMPLEMENTATION |
| 3 | Unauthorized user attempts state transition RPC | Executed RPC throws `'Access Denied'` | PENDING IMPLEMENTATION |
| 4 | User from Society A calls transition RPC for Society B | Executed RPC throws `'Cross-society denied'` | PENDING IMPLEMENTATION |
| 5 | Direct SQL `UPDATE gate_passes SET status = 'active'` | Rejected with explicit exception | PENDING IMPLEMENTATION |
| 6 | Direct SQL `UPDATE daily_staff SET verification_status = 'verified'` | Rejected with explicit exception | PENDING IMPLEMENTATION |
| 7 | Direct SQL `UPDATE gate_passes SET valid_until = NOW() + INTERVAL '1 day'` (Non-status column) | Succeeds under valid RLS policy | PENDING IMPLEMENTATION |
| 8 | Legitimate status transition sequence (`pending` -> `active` -> `suspended`) | Succeeds | PENDING IMPLEMENTATION |
| 9 | Invalid status transition sequence (`pending` -> `suspended`) | Executed RPC throws `'Invalid transition'` | PENDING IMPLEMENTATION |
| 10| Direct client API attempt to bypass RPC via REST PATCH | Blocked by trigger/RLS | PENDING IMPLEMENTATION |
| 11| RLS status on `gate_passes` and `daily_staff` | `relrowsecurity = true` confirmed | PENDING IMPLEMENTATION |
| 12| Slices 1–5 baseline security invariants | 100% preserved and untouched | **CONFIRMED INTACT** |
| 13| Migration execution from remote version `20260912000005` | `npx supabase db push` succeeds 100% | PENDING AUTHORIZATION |

---

## 12. REQUIRED VERIFICATION ASSERTIONS

Before any deployment retry:
1. `SELECT tablename, rowsecurity FROM pg_tables WHERE tablename IN ('gate_passes', 'daily_staff');` must return `true` for both tables.
2. `20260912000006_slice6.sql` must contain zero instances of `OLD` or `NEW` within `CREATE POLICY` statements.
3. SHA-256 hash of `SLICE23_SECURITY_LOCK.md` must match `47A7093CB842BB10179D529E85452BBD8B463E3057725B28E69A5E99AC614448`.

---

## 13. MIGRATION INTEGRITY REQUIREMENTS

* **DO NOT** modify `supabase/migrations/20260912000006_slice6.sql` until explicit implementation authorization is granted in a subsequent stage.
* **DO NOT** modify `database/schema_slice6.sql` until explicit authorization is granted.
* **DO NOT** run `npx supabase db push` or `supabase migration repair`.

---

## 14. DEPLOYMENT PRECONDITIONS

Deployment of remediated Slice 6 may only occur when:
1. Human review and explicit approval of this Forensic Remediation Plan is received.
2. Controlled implementation of Option 1 is executed in local files under a dedicated implementation stage.
3. Pre-deployment preflight clearance gate passes with zero errors.

---

## 15. EXPLICIT AUTHORIZATION GATE

```text
IMPLEMENTATION AUTHORIZATION:
NOT GRANTED

DEPLOYMENT AUTHORIZATION:
NOT GRANTED

MIGRATION REWRITE AUTHORIZATION:
NOT GRANTED

SECURITY LOCK:
NOT AUTHORIZED

REMOTE DATABASE:
READ-ONLY / UNCHANGED BY THIS TASK
```

---
*Plan created under Read-Only Forensic Remediation Mode on September 13, 2026.*
