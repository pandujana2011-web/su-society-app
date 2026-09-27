# STAGE 10U-T PHASE B — CONTROLLED PRODUCTION DEPLOYMENT EXECUTION REPORT

**TARGET REPOSITORY**: `D:\Clients Applications\SU Society App`  
**TARGET SUPABASE PROJECT**: `fsegpxqoozxmicxcxjun` (`pandujana2011-web's Project`, Region: `ap-south-1`, PostgreSQL 17.6.1.166)  
**DATE & TIME**: `2026-09-13T16:32:00+05:30`  
**EXECUTION MODE**: `CONTROLLED PRODUCTION DEPLOYMENT (POST HUMAN AUTHORIZATION)`

---

## 1. EXECUTIVE STATUS & FINAL CLASSIFICATION

- **Final Classification**: `C. DEPLOYMENT FAILED — NO UNSCRIPTED RECOVERY PERFORMED`
- **Mandatory Governance Statement**:
  > **STAGE 10U-T PRODUCTION DEPLOYMENT FAILED OR DID NOT COMPLETE AS EXPECTED. NO UNSCRIPTED RECOVERY OR MIGRATION REPAIR WAS PERFORMED. HUMAN RECOVERY AUTHORIZATION IS REQUIRED.**
- **Deployment Summary**:
  1. **Slice 5 APPLIED**: `20260912000005_slice5.sql` executed all 444 lines (including normalized `-- \set ON_ERROR_STOP on`) and **COMMITTED TO PRODUCTION** successfully!
  2. **Slice 6 FAILED**: `20260912000006_slice6.sql` failed at **Statement 41** with `SQLSTATE 42P01` (`ERROR: missing FROM-clause entry for table "old"`). Slice 6 rolled back atomically prior to committing any DDL/DML.
  3. **Current Remote State**: Exactly **9 migrations** are committed and applied in production (`000001` through `000005`). Exactly **18 migrations** remain pending (`000006` through `000023`).
  4. **Zero Unscripted Recovery**: No migration repair, no manual SQL, no file edits, and no reset were executed.

---

## 2. HUMAN AUTHORIZATION EVIDENCE

- **Authorization Received**: `YES`
- **Authorization Phrase Recorded**:
  > *"I AUTHORIZE STAGE 10U-T PRODUCTION DEPLOYMENT TO SUPABASE PROJECT fsegpxqoozxmicxcxjun."*
- **Authorized Target Project**: `fsegpxqoozxmicxcxjun`
- **Authorized Deployment Command**: `npx supabase db push`

---

## 3. PRE-DEPLOYMENT REVALIDATION RESULTS

Prior to invoking the deployment command, Phase B final read-only revalidation was executed and passed 100%:
- Repository path confirmed: `D:\Clients Applications\SU Society App`
- All 7 transport-normalized pending migrations re-verified (`-- \set ON_ERROR_STOP on`)
- `SLICE23_SECURITY_LOCK.md` hash re-verified: `47A7093CB842BB10179D529E85452BBD8B463E3057725B28E69A5E99AC614448`
- Total local migration files re-verified: 27

---

## 4. DEPLOYMENT EXECUTION TIMELINE & LOGS

- **Deployment Command**: `npx supabase db push`
- **Deployment Start Timestamp**: `2026-09-13T16:31:37Z`
- **Deployment Completion Timestamp**: `2026-09-13T16:31:49Z`
- **Exit Status**: Exit Code `1` (Failed)

### Command Execution Terminal Output Log

```text
Initialising login role...
Connecting to remote database...
Applying migration 20260912000005_slice5.sql...
Applying migration 20260912000006_slice6.sql...
{"_tag":"Error","error":{"code":"LegacyDbPushApplyError","message":"ERROR: missing FROM-clause entry for table \"old\" (SQLSTATE 42P01)\nAt statement: 41\n-- Block manual UPDATE via RLS for gate_passes for ordinary users (Admins use the generic policy which allows it, but wait, admins should ALSO use the transition function!)\n-- The instructions say: \"Direct user UPDATE of the status column must not bypass these rules.\"\n-- If RLS allows UPDATE for admins, they can bypass.\n-- Let's just create a trigger that checks if it was invoked via the function.\n-- Actually, the cleanest way to prevent bypass is just blocking UPDATE on the `status` column explicitly via a BEFORE trigger, unless a session variable is set (which SECURITY DEFINER can set).\n-- OR, since we want to be foolproof, let's use the session variable approach!\n-- Or even simpler: RLS UPDATE policy requires OLD.status = NEW.status for EVERYONE, and then since fn_transition_gate_pass_state is SECURITY DEFINER, it bypasses RLS and can change the status! YES!\n\nCREATE POLICY pol_gate_passes_admin_update ON public.gate_passes FOR UPDATE\nUSING (public.is_admin() AND society_id = public.get_user_society_id(auth.uid()))\nWITH CHECK (status = OLD.status)"}}
```

---

## 5. FAILING STATEMENT FORENSIC ANALYSIS

- **Failing Migration File**: `supabase/migrations/20260912000006_slice6.sql`
- **Failing Statement Index**: Statement 41
- **Error Code**: `SQLSTATE 42P01` (`ERROR: missing FROM-clause entry for table "old"`)
- **Failing SQL Statement**:
```sql
CREATE POLICY pol_gate_passes_admin_update ON public.gate_passes FOR UPDATE
USING (public.is_admin() AND society_id = public.get_user_society_id(auth.uid()))
WITH CHECK (status = OLD.status);
```
- **Technical Root Cause**:
  In PostgreSQL, `OLD` and `NEW` are PL/pgSQL record variables defined exclusively inside BEFORE/AFTER trigger functions. Row Level Security (RLS) `CREATE POLICY ... WITH CHECK (...)` expressions are evaluated in plain SQL context and cannot reference `OLD`. Referencing `OLD` in a policy definition causes PostgreSQL to look for a table named `old` in the FROM clause, returning SQLSTATE 42P01.

---

## 6. POST-DEPLOYMENT REMOTE MIGRATION HISTORY

Read-only remote inspection (`npx supabase migration list`) confirms the current remote database state:

| Index | Migration Filename | Remote State | Timestamp / Deployment Status |
| :--- | :--- | :--- | :--- |
| **01** | `20260912000001_slice1.sql` | **APPLIED** | `2026-09-12 00:00:01` |
| **02** | `202609120000015_prereq_uuid_function.sql` | **APPLIED** | `202609120000015` |
| **03** | `20260912000002_slice2.sql` | **APPLIED** | `2026-09-12 00:00:02` |
| **04** | `202609120000025_prereq_slice3_constraints.sql` | **APPLIED** | `202609120000025` |
| **05** | `20260912000003_slice3.sql` | **APPLIED** | `2026-09-12 00:00:03` |
| **06** | `202609120000035_prereq_slice4_is_property_owner_overload.sql` | **APPLIED** | `202609120000035` |
| **07** | `202609120000036_prereq_slice4_payments_user_id_column.sql` | **APPLIED** | `202609120000036` |
| **08** | `20260912000004_slice4.sql` | **APPLIED** | `2026-09-12 00:00:04` |
| **09** | **`20260912000005_slice5.sql`** | **APPLIED** | **`2026-09-12 00:00:05` *(Slice 5 Applied in Stage 10U-T!)*** |
| **10** | **`20260912000006_slice6.sql`** | **PENDING** | ***(Failed at Statement 41 - Rolled Back)*** |
| **11–27** | `20260912000007_slice7.sql` .. `20260912000023_slice23.sql` | **PENDING** | *(Unapplied)* |

---

## 7. PROTECTED ARTIFACT IMMUTABILITY & BASELINE PRESERVATION

- **Authoritative Schemas (`database/schema_slice1–23.sql`)**: 100% UNTOUCHED.
- **Security Lock Document (`SLICE23_SECURITY_LOCK.md`)**: SHA-256 matched `47A7093CB842BB10179D529E85452BBD8B463E3057725B28E69A5E99AC614448` (100% UNTOUCHED).
- **Historical Security Baseline**: `931 / 931 PASS — PRESERVED`.
- **Migration Files**: Zero local migration files were edited or repaired during Phase B execution.

---

## 8. STATEMENTS OF COMPLIANCE

1. **DEPLOYMENT WAS EXECUTED ONLY AFTER EXPLICIT HUMAN AUTHORIZATION.**
2. **NO UNSCRIPTED RECOVERY OR MIGRATION REPAIR WAS PERFORMED.**
3. **NO MANUAL SQL WAS EXECUTED AGAINST PRODUCTION.**
4. **NO MIGRATION FILE WAS EDIT OR ALTERED IN PHASE B.**
5. **SLICE 5 HAS BEEN SUCCESSFULLY APPLIED AND COMMITTED TO PRODUCTION.**

---
**END OF STAGE 10U-T PHASE B EXECUTION REPORT**
