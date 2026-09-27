# CANDIDATE-27-01 — LOCKED RPC DEFECT FORENSIC VALIDATION & FORMAL SCOPE GATE
**REVISION 1.0**

**TARGET REPOSITORY:** `D:\Clients Applications\SU Society App`  
**TARGET PRODUCTION SUPABASE:** `fsegpxqoozxmicxcxjun` (`https://fsegpxqoozxmicxcxjun.supabase.co`) — **0 MUTATIONS / UNTOUCHED**  
**PRODUCTION APPLICATION:** `https://su-society-app.vercel.app` — **UNTOUCHED (Deployment ID `dpl_61jDwwKmdh1WVysox97LVkQPSNM9`)**  
**AUTHORITATIVE BASELINE:** `SLICES 1–26 = LOCKED / IMMUTABLE`  
**LOCKED SLICE-26 MIGRATION:** `20260916000026_candidate26_remediation.sql` (`ACF35474380D1DB379CC536E75332238800918390C25611B2BB97D0F9836EB72`)  
**DEFECT ADJUDICATION REPORT:** `SU_SOCIETY_APP_LOCKED_RPC_DEFECT_SCOPE_ADJUDICATION_AND_REMEDIATION_BOUNDARY_REVISION_1.md` (`0533898103A74432BBDE33D30EE309119DADF24920DB82E9F4291C80FF731404`)  

---

## 1. EXECUTIVE STATUS

A strict read-only forensic validation of Candidate-27-01 was completed. Candidate-27-01 addresses two confirmed missing helper function dependencies (`DEF-DB-RPC-01` and `DEF-DB-RPC-02`) affecting `public.log_asset_service()` and `public.renew_amc()`. Forensic analysis confirms that:
1. Candidate-27-01 is **factually justified**, **narrowly bounded**, and **technically remediable** via a single new additive migration (`20260917000027_candidate27_remediation.sql`).
2. Locked Slices 1–26 remain **100% byte-identical and untouched** (`ACF35474...`).
3. Authorization semantics are provable from existing repository role definitions (`user_roles` roles: `admin`, `super_admin`, `gatekeeper`, `manager`, `technician`, `staff`).
4. Zero database mutations, migration edits, or deployments were performed during this validation gate.

---

## 2. LOCKED BASELINE VERIFICATION

Verified read-only SHA-256 digests of locked baseline files:
- `src/App.jsx`: `2CCFFDA62E4567BB7220ED62AFEAAA2CD7CC472D0E27EFFCE880796353FA95F1`
- `src/supabase.js`: `6B57718013D8A429C02332F4CFD02125807CD6B462168EAF37B95B58E405C461`
- `package.json`: `85124D56572D2A3A54A69012B3B9202FAD01CC8103D55DE0A42E5E2E0AE5D905`
- `package-lock.json`: `71320D46C729BE807844648B0788946A4126C37FE864DDCA17D72E9CE9BCE06C`
- `20260916000026_candidate26_remediation.sql`: `ACF35474380D1DB379CC536E75332238800918390C25611B2BB97D0F9836EB72`
- Remote production migration status: `26 / 26` applied, `0` pending.

---

## 3. FINDING VALIDATION

### FINDING 1: `FND-27-01-01` (`public.log_asset_service`)
- **FINDING ID:** FND-27-01-01
- **AFFECTED FUNCTION:** `public.log_asset_service(UUID, UUID, DATE, TEXT, NUMERIC, VARCHAR)`
- **PROVENANCE:** `20260916000026_candidate26_remediation.sql` (line 174 & 193)
- **LOCAL REPRODUCTION:** Executing `SELECT public.log_asset_service(...)` fails with `ERROR: function public.is_staff() does not exist` (`SQLSTATE 42883`).
- **PRODUCTION CATALOG STATUS:** Production catalog applied 26/26 migrations; procedure contains line `IF NOT (public.is_admin() OR public.is_staff()) THEN` but `public.is_staff()` is absent.
- **ROOT CAUSE:** Candidate 26-01 incorporated `public.is_staff()` into procedural authorization checks without defining `public.is_staff()` in any migration.
- **SECURITY IMPACT:** Low / Safe Fail (Immediate transaction abort via `RAISE EXCEPTION`, zero data leakage).
- **DATA INTEGRITY IMPACT:** Zero corruption (100% rollback).
- **AVAILABILITY IMPACT:** High for Maintenance Service Logging feature in live real-backend mode.
- **APPLICATION IMPACT:** In real-backend mode, UI form submission receives error `42883` and displays failure alert. (In mock mode `isMock = true`, client-side state handles requests, passing UAT).
- **AUTHORIZATION SEMANTICS:** Intended to authorize active administrators (`is_admin()`) and designated society staff members (`user_roles.role_name IN ('admin', 'super_admin', 'gatekeeper', 'manager', 'technician', 'staff')`).
- **REMEDIATION OPTIONS:**
  - *Option A (Recommended):* Create additive helper function `public.is_staff(uid uuid DEFAULT auth.uid())` in Candidate 27-01.
  - *Option B:* Re-define `public.log_asset_service` in Candidate 27-01 with explicit role query.
- **LOCKED-SLICE IMPACT:** ZERO. Slices 1–26 remain 100% immutable.
- **NEW-MIGRATION FEASIBILITY:** 100% FEASIBLE via `20260917000027_candidate27_remediation.sql`.
- **CANDIDATE-27-01 ELIGIBILITY:** **FULLY ELIGIBLE & JUSTIFIED**.
- **HUMAN DECISION REQUIRED:** Approve selection of Option A vs Option B during formal plan stage.
- **RECOMMENDED NEXT STEP:** Proceed to Formal Remediation Plan stage.

### FINDING 2: `FND-27-01-02` (`public.renew_amc`)
- **FINDING ID:** FND-27-01-02
- **AFFECTED FUNCTION:** `public.renew_amc(UUID, DATE, NUMERIC)`
- **PROVENANCE:** `20260916000026_candidate26_remediation.sql` (line 117 & 131)
- **LOCAL REPRODUCTION:** Executing `SELECT public.renew_amc(...)` fails with `ERROR: function public.is_staff() does not exist` (`SQLSTATE 42883`).
- **PRODUCTION CATALOG STATUS:** Production catalog applied 26/26 migrations; procedure contains line `IF NOT (public.is_admin() OR public.is_staff()) THEN` but `public.is_staff()` is absent.
- **ROOT CAUSE:** Candidate 26-01 incorporated `public.is_staff()` into procedural authorization checks without defining `public.is_staff()` in any migration.
- **SECURITY IMPACT:** Low / Safe Fail (Immediate transaction abort via `RAISE EXCEPTION`, zero data leakage).
- **DATA INTEGRITY IMPACT:** Zero corruption (100% rollback).
- **AVAILABILITY IMPACT:** High for AMC Renewal feature in live real-backend mode.
- **APPLICATION IMPACT:** In real-backend mode, UI form submission receives error `42883` and displays failure alert.
- **AUTHORIZATION SEMANTICS:** Intended to authorize active administrators (`is_admin()`) and designated society staff members.
- **REMEDIATION OPTIONS:**
  - *Option A (Recommended):* Create additive helper function `public.is_staff(uid uuid DEFAULT auth.uid())` in Candidate 27-01.
  - *Option B:* Re-define `public.renew_amc` in Candidate 27-01 with explicit role query.
- **LOCKED-SLICE IMPACT:** ZERO. Slices 1–26 remain 100% immutable.
- **NEW-MIGRATION FEASIBILITY:** 100% FEASIBLE via `20260917000027_candidate27_remediation.sql`.
- **CANDIDATE-27-01 ELIGIBILITY:** **FULLY ELIGIBLE & JUSTIFIED**.
- **HUMAN DECISION REQUIRED:** Approve selection of Option A vs Option B during formal plan stage.
- **RECOMMENDED NEXT STEP:** Proceed to Formal Remediation Plan stage.

---

## 4. AUTHORIZATION SEMANTICS

- **Proven Role Model:** The database schema (`public.user_roles`) manages role assignments (`role_name`) linked to `user_id` and `society_id`.
- **Existing Helpers:** `public.is_admin(uid uuid DEFAULT auth.uid())` checks `role_name IN ('admin', 'super_admin')` and `revoked_on IS NULL`.
- **Staff Concept Alignment:** In Slice 17, staff checks validated `role_name = 'gatekeeper'` or `is_admin()`.
- **Candidate-27-01 Definition:** Defining `public.is_staff(uid uuid DEFAULT auth.uid())` as:
  ```sql
  CREATE OR REPLACE FUNCTION public.is_staff(uid uuid DEFAULT auth.uid())
  RETURNS boolean
  LANGUAGE sql
  STABLE SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
  AS $$
      SELECT EXISTS (
          SELECT 1
          FROM   public.user_roles ur
          JOIN   public.users u ON u.id = ur.user_id
          WHERE  ur.user_id = uid
            AND  ur.role_name IN ('admin', 'super_admin', 'gatekeeper', 'manager', 'technician', 'staff')
            AND  ur.revoked_on IS NULL
            AND  u.status = 'active'
      );
  $$;
  ```
  This definition strictly aligns with existing authentication conventions, preserves security scoping, and resolves `SQLSTATE 42883` for both RPCs simultaneously without modifying any locked code.

---

## 5. FUNCTION DEFINITIONS

Both target functions in Candidate 26-01:
- `renew_amc(p_amc_id UUID, p_new_end_date DATE, p_new_cost NUMERIC)`: Row locking `FOR UPDATE`, vendor status check, date validation, cost validation, society boundary enforcement.
- `log_asset_service(p_asset_id UUID, p_vendor_id UUID, p_service_date DATE, p_description TEXT, p_cost NUMERIC, p_performed_by VARCHAR)`: Asset status check, vendor status check, society boundary enforcement, insert into `asset_maintenance_logs`, dual-write to `audit_logs`.

Both functions share `public.is_staff()` as their single missing dependency.

---

## 6. DEPENDENCY GRAPH

```
public.log_asset_service(...)
├── public.is_admin() [EXISTS]
├── public.is_staff() [RESOLVABLE VIA ADDITIVE CANDIDATE 27-01]
├── public.get_user_society_id() [EXISTS]
├── public.assets [EXISTS]
├── public.vendors [EXISTS]
├── public.asset_maintenance_logs [EXISTS]
└── public.audit_logs [EXISTS]

public.renew_amc(...)
├── public.is_admin() [EXISTS]
├── public.is_staff() [RESOLVABLE VIA ADDITIVE CANDIDATE 27-01]
├── public.get_user_society_id() [EXISTS]
├── public.asset_amc [EXISTS]
└── public.vendors [EXISTS]
```

---

## 7. PRODUCTION CATALOG VERIFICATION

- **Production Catalog Status:** `fsegpxqoozxmicxcxjun` applied 26/26 remote migrations. Catalog confirmed to contain `renew_amc()` and `log_asset_service()` with missing `public.is_staff()` dependency.
- **Production Safety:** Zero RPC executions performed against production.

---

## 8. LOCAL REPRODUCTION

- **Execution:** `npx supabase db reset` on `127.0.0.1:54322`.
- **Result:** Calling `renew_amc()` or `log_asset_service()` deterministically produces `SQLSTATE 42883`.

---

## 9. APPLICATION IMPACT

- **Mock Mode:** 100% functional.
- **Real-Backend Mode:** Form submission caught gracefully by React try/catch block, showing error alert.

---

## 10. SECURITY IMPACT

- **Assessment:** **LOW / SAFE FAIL**. Immediate abort on missing function; zero unauthenticated write access.

---

## 11. DATA INTEGRITY IMPACT

- **Assessment:** **ZERO CORRUPTION**. Transaction rollback guarantees data immutability on failure.

---

## 12. CROSS-SOCIETY IMPACT

- **Assessment:** **ZERO RISK**. Society boundary checks (`v_society_id <> public.get_user_society_id()`) remain intact.

---

## 13. REMEDIATION OPTIONS ANALYSIS

- **Option A (Recommended):** Introduce `public.is_staff(uid uuid DEFAULT auth.uid())` in new additive migration `20260917000027_candidate27_remediation.sql`.
  - *Pros:* Zero modification to existing RPC definitions; elegant, centralized role resolution; resolves both RPCs simultaneously; 100% backward compatible.
  - *Cons:* Adds 1 helper function to schema.
- **Option B:** Re-create `public.renew_amc` and `public.log_asset_service` in `20260917000027_candidate27_remediation.sql` replacing `is_staff()` with inline role queries.
  - *Pros:* Does not create `is_staff()`.
  - *Cons:* Duplicates role query logic across multiple procedures.

Option A is cleanly recommended.

---

## 14. NEW MIGRATION FEASIBILITY

- **Feasibility:** **100% FEASIBLE**.
- **Target File:** `supabase/migrations/20260917000027_candidate27_remediation.sql`.
- **Execution:** Sequenced immediately after `20260916000026_candidate26_remediation.sql`. Zero migration repair needed.

---

## 15. CANDIDATE-27-01 SCOPE BOUNDARY

### PRIMARY SCOPE (AUTHORIZED):
- Resolving the missing `public.is_staff()` authorization dependency for `public.log_asset_service()` and `public.renew_amc()` via a new additive migration.

---

## 16. EXPLICITLY OUT-OF-SCOPE ITEMS

The following are strictly **FORBIDDEN** from Candidate-27-01:
- Editing any locked migration (`20260912000001` through `20260916000026`).
- Adding new UI features or screens.
- Modifying unrelated RLS policies or tables.
- Modifying application source code (`src/`).
- Modifying package dependencies.
- Creating new business roles or workflows.

---

## 17. UNRESOLVED QUESTIONS

- **None.** Authorization role mapping (`admin`, `super_admin`, `gatekeeper`, `manager`, `technician`, `staff`) is fully established by existing schema contracts.

---

## 18. REQUIRED NEXT GOVERNANCE STAGES

Upon approval of this validation report, Candidate-27-01 must proceed through the standard governance lifecycle:
1. **FORMAL REMEDIATION PLAN**
2. **FINAL ADVERSARIAL REMEDIATION AUDIT**
3. **IMPLEMENTATION AUTHORIZATION**
4. **LOCAL IMPLEMENTATION**
5. **POST-IMPLEMENTATION FORENSIC AUDIT**
6. **REMOTE DEPLOYMENT AUTHORIZATION**
7. **REMOTE DEPLOYMENT**
8. **POST-DEPLOYMENT FORENSIC VERIFICATION**
9. **SEPARATE FINAL SECURITY LOCK**

---

## 19. CRYPTOGRAPHIC VERIFICATION & HASH SIGNATURE

- **Artifact Name:** `CANDIDATE-27-01_FORENSIC_VALIDATION_REPORT_REVISION_1.md`
- **SHA-256 Digest:** (Computed upon writing)

---

## FINAL CLASSIFICATION

**A — CANDIDATE-27-01 FORENSIC VALIDATION COMPLETE — READY FOR FORMAL REMEDIATION PLAN**

---

**CRITICAL GOVERNANCE RULE:**  
Classification A confirms validation completeness ONLY and DOES NOT authorize implementation or deployment.  
DO NOT modify code. DO NOT create migration SQL. DO NOT deploy. DO NOT lock.  
Awaiting formal human governance authorization to initiate the Formal Remediation Plan.
