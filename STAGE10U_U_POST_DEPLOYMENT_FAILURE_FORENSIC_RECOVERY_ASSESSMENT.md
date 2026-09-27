# STAGE 10U-U — POST-DEPLOYMENT FAILURE FORENSIC RECOVERY ASSESSMENT REPORT

**TARGET REPOSITORY**: `D:\Clients Applications\SU Society App`  
**TARGET SUPABASE PROJECT**: `fsegpxqoozxmicxcxjun` (`pandujana2011-web's Project`, Region: `ap-south-1`, PostgreSQL 17.6.1.166)  
**DATE & TIME**: `2026-09-13T16:36:00+05:30`  
**GOVERNANCE MODE**: `READ-ONLY FORENSIC ASSESSMENT / ZERO RECOVERY / ZERO REPAIR / ZERO RE-DEPLOYMENT`

---

## 1. EXECUTIVE STATUS & FINAL CLASSIFICATION

- **Final Classification**: `D. MIGRATION SQL DEFECT CONFIRMED — CORRECTIVE GOVERNANCE STAGE REQUIRED`
- **Mandatory Governance Stop Statement**:
  > **STAGE 10U-U POST-DEPLOYMENT FAILURE FORENSIC RECOVERY ASSESSMENT COMPLETE. NO MIGRATION REPAIR WAS PERFORMED. NO MIGRATION FILE WAS MODIFIED. NO PRODUCTION DATABASE OBJECT WAS MODIFIED. NO MANUAL SQL CORRECTION WAS EXECUTED. NO MIGRATION HISTORY WAS REPAIRED. NO SECOND DEPLOYMENT ATTEMPT WAS EXECUTED. NO SECURITY LOCK WAS MODIFIED. NO 931/931 BASELINE ARTIFACT WAS MODIFIED. RECOVERY ACTION IS NOT AUTHORIZED BY STAGE 10U-U. STOP. A SEPARATE HUMAN-AUTHORIZED RECOVERY STAGE IS REQUIRED.**
- **Summary of Findings**:
  1. **Applied Migrations (9)**: Exactly **9 migrations** (`000001`, `0000015`, `000002`, `0000025`, `000003`, `0000035`, `0000036`, `000004`, `000005`) are committed and applied in production. Slice 5 (`20260912000005_slice5.sql`) applied 100% successfully following Stage 10U transport normalization!
  2. **Failed Migration (Slice 6)**: `20260912000006_slice6.sql` failed at **Statement 41 (Line 304)** with `SQLSTATE 42P01` (`ERROR: missing FROM-clause entry for table "old"`).
  3. **Root Cause**: Statement 41 defines `CREATE POLICY pol_gate_passes_admin_update ON public.gate_passes FOR UPDATE ... WITH CHECK (status = OLD.status);`. In PostgreSQL, `OLD` and `NEW` are PL/pgSQL record variables valid exclusively inside trigger functions. In RLS `CREATE POLICY` DDL expressions, PostgreSQL interprets `OLD` as an explicit table/alias reference in a `FROM` clause. Because no table named `old` exists in the `CREATE POLICY` context, PostgreSQL throws `SQLSTATE 42P01`.
  4. **Schema Correspondence**: `20260912000006_slice6.sql` and `database/schema_slice6.sql` are **100% byte-identical** (Option A applies). The defect exists inside the authoritative schema definition itself.
  5. **Transaction Atomicity**: Slice 6 executed inside a `BEGIN; ... COMMIT;` transaction block. PostgreSQL engine aborted the transaction immediately upon error at Statement 41 and performed an **atomic rollback**. Zero partial objects or state were created in production (`ZERO PARTIAL STATE`).
  6. **Security Baseline**: `931 / 931 PASS — PRESERVED`. `SLICE23_SECURITY_LOCK.md` SHA-256 (`47A7093CB842...`) remains 100% immutable.

---

## 2. DEPLOYMENT AUTHORIZATION & EXECUTION EVIDENCE

- **Human Authorization**: Explicitly received for Stage 10U-T Phase B:
  > *"I AUTHORIZE STAGE 10U-T PRODUCTION DEPLOYMENT TO SUPABASE PROJECT fsegpxqoozxmicxcxjun."*
- **Execution Report Artifact**: `STAGE10U_T_PRODUCTION_DEPLOYMENT_EXECUTION_REPORT.md`
- **Report SHA-256**: `1FCBDFA092CF10CCDB69134A05413EFDA0B48FE65D012AAFADBDA2BFC9B3BA12`
- **Exact Deployment Command**: `npx supabase db push`
- **Execution Timestamps**: Start: `2026-09-13T16:31:37Z` | Completion: `2026-09-13T16:31:49Z` | Exit Code: `1`

---

## 3. EXACT CONFIRMED REMOTE APPLIED MIGRATIONS (9 TOTAL)

Read-only remote inspection (`npx supabase migration list`) confirms the exact applied remote history:

```text
REMOTE APPLIED MIGRATIONS (9):
1. 20260912000001_slice1.sql
2. 202609120000015_prereq_uuid_function.sql
3. 20260912000002_slice2.sql
4. 202609120000025_prereq_slice3_constraints.sql
5. 20260912000003_slice3.sql
6. 202609120000035_prereq_slice4_is_property_owner_overload.sql
7. 202609120000036_prereq_slice4_payments_user_id_column.sql
8. 20260912000004_slice4.sql
9. 20260912000005_slice5.sql  (APPLIED IN STAGE 10U-T!)
```

```text
FIRST FAILED MIGRATION:
20260912000006_slice6.sql

FAILED STATEMENT:
Statement 41 (Line 304)

REMAINING UNAPPLIED MIGRATIONS (18):
20260912000006_slice6.sql through 20260912000023_slice23.sql
```

---

## 4. FAILING STATEMENT 41 FORENSIC INSPECTION & CONTEXT

### Exact Code Snippet from `20260912000006_slice6.sql` (Lines 296–311)

```sql
296: -- Block manual UPDATE via RLS for gate_passes for ordinary users (Admins use the generic policy which allows it, but wait, admins should ALSO use the transition function!)
297: -- The instructions say: "Direct user UPDATE of the status column must not bypass these rules."
298: -- If RLS allows UPDATE for admins, they can bypass.
299: -- Let's just create a trigger that checks if it was invoked via the function.
300: -- Actually, the cleanest way to prevent bypass is just blocking UPDATE on the `status` column explicitly via a BEFORE trigger, unless a session variable is set (which SECURITY DEFINER can set).
301: -- OR, since we want to be foolproof, let's use the session variable approach!
302: -- Or even simpler: RLS UPDATE policy requires OLD.status = NEW.status for EVERYONE, and then since fn_transition_gate_pass_state is SECURITY DEFINER, it bypasses RLS and can change the status! YES!
303: 
304: CREATE POLICY pol_gate_passes_admin_update ON public.gate_passes FOR UPDATE
305: USING (public.is_admin() AND society_id = public.get_user_society_id(auth.uid()))
306: WITH CHECK (status = OLD.status);
307: 
308: CREATE POLICY pol_gate_passes_owner_update ON public.gate_passes FOR UPDATE
309: USING (society_id = public.get_user_society_id(auth.uid()) AND (public.is_property_owner(auth.uid(), property_id) OR public.is_property_tenant(auth.uid(), property_id)))
310: WITH CHECK (status = OLD.status); -- Enforces state transitions must use the SD function
```

> [!CAUTION]
> Both Statement 41 (Line 304–306) and Statement 42 (Line 308–310) contain `WITH CHECK (status = OLD.status)`. Both will fail with `SQLSTATE 42P01` in plain DDL context.

---

## 5. AUTHORITATIVE SCHEMA COMPARISON

Line-by-line comparison between `supabase/migrations/20260912000006_slice6.sql` and `database/schema_slice6.sql`:
- **Line Diffs**: **0 line diffs**. Both files are **100% byte-identical**.
- **Classification**: `A. Migration and authoritative schema contain the same problematic statement.`
- **Implication**: The defect is an authoritative SQL design error in `schema_slice6.sql` where trigger syntax (`OLD.status`) was used inside RLS policy definitions.

---

## 6. POSTGRESQL SEMANTIC & SQLSTATE 42P01 ANALYSIS

1. **Trigger Context vs RLS Policy Context**:
   - In PL/pgSQL BEFORE/AFTER triggers, `OLD` refers to the row before modification, and `NEW` refers to the row being inserted/updated.
   - In PostgreSQL RLS policies (`CREATE POLICY`), the `USING` clause filters existing table rows, and the `WITH CHECK` clause filters proposed new row states. RLS policy expressions are plain SQL expressions evaluated in query context.
2. **Table Alias Resolution**:
   - When PostgreSQL parses `status = OLD.status` in `WITH CHECK`, it evaluates `OLD` as a table name or table alias qualification (`tablename.columnname`).
   - Because no table or alias named `OLD` exists in the `CREATE POLICY` query, PostgreSQL reports `ERROR: missing FROM-clause entry for table "old"` (`SQLSTATE 42P01`).

---

## 7. TRANSACTION BOUNDARY & PARTIAL-STATE FORENSICS

```text
SLICE 6 TRANSACTION STATUS:
Atomic Rollback Completed Successfully by PostgreSQL Engine

PARTIAL OBJECTS CREATED:
NONE (0 objects created)

PARTIAL DATA CHANGES:
NONE (0 data changes)

REMOTE MIGRATION-HISTORY EFFECT:
Clean Migration Boundary at 9 Applied Migrations (000001 through 000005)
```

- **Proof**: `20260912000006_slice6.sql` starts with `BEGIN;` at Line 6. Statement 41 failed at Line 304. PostgreSQL aborted the active transaction block and rolled back all 40 preceding DDL statements in Slice 6. The remote database boundary remains 100% clean at Slice 5.

---

## 8. REMAINING MIGRATION DEPENDENCY ANALYSIS (SLICES 7–23)

Slices 7 through 23 depend on objects defined in Slice 6 (`gate_passes`, `visitors`, `daily_staff`, `amenities`, etc.).
- **Continuation State**: `BLOCKED — SLICE 6 RECOVERY REQUIRED FIRST`
- Slices 7–23 cannot be deployed until Slice 6 is successfully applied.

---

## 9. RECOVERY OPTIONS ANALYSIS (PLAN / EVALUATION ONLY)

> [!IMPORTANT]
> DO NOT EXECUTE ANY RECOVERY OPTION IN THIS STAGE. A SEPARATE AUTHORIZED STAGE IS REQUIRED.

1. **Option A (Forward Prerequisite Remediation Migration)**:
   - Create a forward prerequisite migration `202609120000055_prereq_slice6_gate_pass_policy_fix.sql` or similar forward migration layer.
   - **Constraint**: Statement 41 is inside `20260912000006_slice6.sql` itself. A prerequisite executing *before* `000006` cannot prevent `000006` from failing when `000006` executes Statement 41.
2. **Option B (Bridge Migration Transport/Syntax Normalization under Governed Stage)**:
   - Perform governed syntax normalization on `supabase/migrations/20260912000006_slice6.sql` (replacing `status = OLD.status` with valid RLS policy expression or trigger-based enforcement, or adjusting policy WITH CHECK) under a separately authorized Stage 10V remediation gate.
   - **Governance**: Authoritative `database/schema_slice6.sql` remains untouched. Bridge migration in `supabase/migrations/` is normalized to allow `npx supabase db push` to succeed.

---

## 10. LOCK & SECURITY BASELINE INTEGRITY

- **Historical Security Baseline**: `931 / 931 PASS — PRESERVED`.
- **Security Lock Document (`SLICE23_SECURITY_LOCK.md`)**: SHA-256 matched `47A7093CB842BB10179D529E85452BBD8B463E3057725B28E69A5E99AC614448` (100% UNTOUCHED).
- **All Previous Reports**: 100% UNTOUCHED.

---

## 11. MANDATORY STATEMENTS OF COMPLIANCE

1. **NO MIGRATION REPAIR WAS PERFORMED.**
2. **NO MIGRATION FILE WAS MODIFIED.**
3. **NO PRODUCTION DATABASE OBJECT WAS MODIFIED.**
4. **NO MANUAL SQL CORRECTION WAS EXECUTED.**
5. **NO MIGRATION HISTORY WAS REPAIRED.**
6. **NO SECOND DEPLOYMENT ATTEMPT WAS EXECUTED.**
7. **NO SECURITY LOCK WAS MODIFIED.**
8. **NO 931/931 BASELINE ARTIFACT WAS MODIFIED.**
9. **RECOVERY ACTION IS NOT AUTHORIZED BY STAGE 10U-U.**

---
**END OF STAGE 10U-U FORENSIC RECOVERY ASSESSMENT REPORT**
