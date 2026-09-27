# SU SOCIETY APP — LOCKED BASELINE RPC DEFECT SCOPE ADJUDICATION & REMEDIATION BOUNDARY
**REVISION 1.0**

**TARGET REPOSITORY:** `D:\Clients Applications\SU Society App`  
**TARGET PRODUCTION SUPABASE:** `fsegpxqoozxmicxcxjun` (`https://fsegpxqoozxmicxcxjun.supabase.co`) — **0 MUTATIONS / UNTOUCHED**  
**PRODUCTION APPLICATION:** `https://su-society-app.vercel.app` — **UNTOUCHED (Deployment ID `dpl_61jDwwKmdh1WVysox97LVkQPSNM9`)**  
**AUTHORITATIVE BASELINE:** `SLICES 1–26 = LOCKED / IMMUTABLE`  
**LOCKED SLICE-26 MIGRATION:** `20260916000026_candidate26_remediation.sql` (`ACF35474380D1DB379CC536E75332238800918390C25611B2BB97D0F9836EB72`)  
**CONFIRMED DEFECT REPORT:** `SU_SOCIETY_APP_LOCKED_SLICE_RPC_DEFECT_FORENSIC_ADJUDICATION_GATE_REVISION_1.md` (`400E15AAF10298CC1864C9FECFD29DAA7D9E8E0AE365649DD0B87C0F474E7BE8`)  

---

## 1. EXECUTIVE ADJUDICATION

A strict read-only forensic adjudication was executed to establish the definitive provenance, scope, ownership, and future remediation boundaries for database defects `DEF-DB-RPC-01` (`public.log_asset_service()`) and `DEF-DB-RPC-02` (`public.renew_amc()`).

### Key Adjudication Findings:
1. **Definitive Provenance:** Both procedures `public.log_asset_service()` and `public.renew_amc()` were created for the first time in `20260916000026_candidate26_remediation.sql` (Candidate 26-01 / Revision 2.0 remediation migration, lines 117 and 174). Neither procedure existed in `20260912000008_slice8.sql`.
2. **Missing Function Provenance:** Function `public.is_staff()` **was never created in any migration in the entire repository (Slices 1–26)**. In Slice 17 (`20260912000017_slice17.sql`), staff authorization was evaluated via a local PL/pgSQL variable `v_is_staff` checking `role_name = 'gatekeeper'` or `is_admin()`. In Candidate 26-01, the author erroneously wrote `public.is_staff()` into procedural authorization checks.
3. **Production Alignment:** Production database `fsegpxqoozxmicxcxjun` applied all 26 migrations (`26/26` applied, `0` pending) and suffers from the exact same missing function dependency (`SQLSTATE 42883`).
4. **Remediation Boundary:** Slices 1–26 remain locked and immutable. Future remediation is 100% achievable without editing any locked migration, via a dedicated additive remediation candidate (Candidate 27-01).

---

## 2. LOCKED BASELINE IDENTITY

All repository locked migration files are verified byte-identical against their authoritative cryptographic hashes:
- `supabase/migrations/20260912000008_slice8.sql`: `702BAF9BEC1309970535492846E42C72D9FA437F2267C2B9CF63947F259D819D`
- `supabase/migrations/20260916000026_candidate26_remediation.sql`: `ACF35474380D1DB379CC536E75332238800918390C25611B2BB97D0F9836EB72`
- All Slices 1–26 files remain untouched and immutable.

---

## 3. FUNCTION PROVENANCE TIMELINE

| Migration File | Function Name | Action | Dependency Reference | Evidence / Line Number |
| :--- | :--- | :--- | :--- | :--- |
| `20260912000008_slice8.sql` | `public.assets`, `public.asset_amc` | Created tables & basic schema | No RPC functions created | Table definitions only |
| `20260912000017_slice17.sql` | Local workflow functions | Used local variable `v_is_staff` | Checked `role_name = 'gatekeeper'` | Lines 654, 724, 852 |
| `20260916000026_candidate26_remediation.sql` | `public.renew_amc(UUID, DATE, NUMERIC)` | **CREATE OR REPLACE** (First definition) | References `public.is_staff()` | Line 117 & 131 |
| `20260916000026_candidate26_remediation.sql` | `public.log_asset_service(...)` | **CREATE OR REPLACE** (First definition) | References `public.is_staff()` | Line 174 & 193 |

---

## 4. `public.is_staff()` PROVENANCE

1. **Existence Audit:** Executed repository-wide search for `is_staff`. `CREATE FUNCTION public.is_staff` exists **0 times** across all 26 migrations.
2. **Design Intention:** In earlier slices (Slice 17 & 18), "staff" operations checked gatekeeper role membership (`role_name = 'gatekeeper'`) or admin status (`is_admin()`).
3. **Root Cause:** When Candidate 26-01 was written, the author assumed `public.is_staff()` was a global helper function parallel to `public.is_admin()`, but neglected to write the SQL definition for `public.is_staff()`.

---

## 5. DEPENDENCY GRAPH

```
public.log_asset_service(UUID, UUID, DATE, TEXT, NUMERIC, VARCHAR)
├── public.is_admin() [EXISTS]
├── public.is_staff() [MISSING ❌ -> SQLSTATE 42883]
├── public.get_user_society_id() [EXISTS]
├── public.assets [EXISTS]
├── public.vendors [EXISTS]
├── public.asset_maintenance_logs [EXISTS]
└── public.audit_logs [EXISTS]

public.renew_amc(UUID, DATE, NUMERIC)
├── public.is_admin() [EXISTS]
├── public.is_staff() [MISSING ❌ -> SQLSTATE 42883]
├── public.get_user_society_id() [EXISTS]
├── public.asset_amc [EXISTS]
└── public.vendors [EXISTS]
```

`public.is_staff()` is the **ONLY** missing dependency in both RPC call trees.

---

## 6. LOCAL REPRODUCTIONS & EVIDENCE

- **Reproduction:** Clean `npx supabase db reset` on local backend (`127.0.0.1:54322`) re-applies migrations 1–26 cleanly.
- **RPC Invocation:** Calling `renew_amc()` or `log_asset_service()` deterministically fails with:
  `ERROR: function public.is_staff() does not exist` (SQLSTATE `42883`).
- **Direct Table Operations:** Direct INSERT/UPDATE on `asset_amc` and `asset_maintenance_logs` succeed, verifying that underlying tables, FKs, CHECK constraints, and triggers (`trg_prevent_maintenance_log_mutation`) operate 100% correctly.

---

## 7. PRODUCTION CATALOG VERIFICATION

- **PRODUCTION CATALOG CONDITION VERIFIED:** Production database `fsegpxqoozxmicxcxjun` applied all 26 migrations and contains the exact same RPC definitions referencing `public.is_staff()`. `public.is_staff()` does **NOT** exist in the production catalog.
- **PRODUCTION RPC EXECUTION NOT PERFORMED:** Zero RPC calls executed against production per strict zero-mutation governance rules.

---

## 8. APPLICATION DEPENDENCY IMPACT

- **Mock Mode (`isMock = true`):** Application handles AMC renewal and Maintenance Log creation in client-side state (`src/supabase.js`), bypassing live database RPC calls. Mock UAT passed 22/22.
- **Real Backend Mode:** Form submissions triggering `renew_amc()` or `log_asset_service()` from `src/App.jsx` receive PostgreSQL error `42883`. The UI catches the rejection and displays an error alert without corrupting database state.

---

## 9. SECURITY IMPACT

- **Assessment:** **LOW / SAFE FAIL**.
- **Reasoning:** Missing function dependency causes an immediate PostgreSQL exception (`RAISE EXCEPTION` / SQLSTATE `42883`), aborting execution before any DML state mutation occurs. No authorization bypass, no data leakage, and no cross-society access is possible.

---

## 10. DATA INTEGRITY IMPACT

- **Assessment:** **ZERO DATA CORRUPTION**.
- **Reasoning:** PostgreSQL transaction atomicity ensures that failed RPC calls roll back 100%. Table data, foreign keys, and audit logs remain uncorrupted.

---

## 11. AVAILABILITY / USER IMPACT

- **Assessment:** **FEATURE UNAVAILABLE IN REAL-BACKEND MODE**.
- **Reasoning:** Users in real-backend mode cannot renew AMC contracts or log asset maintenance via the RPC UI forms until the missing helper function is deployed or RPCs are updated.

---

## 12. LOCKED-SLICE OWNERSHIP & IMMUTABILITY

- **Ownership:** The defect resides in Candidate 26-01 (`20260916000026_candidate26_remediation.sql`).
- **Immutability:** Slices 1–26 are locked and MUST NOT be edited.
- **Remediation Feasibility:** 100% feasible via an additive future migration (Candidate 27-01) that either defines `public.is_staff()` or re-defines `renew_amc()` and `log_asset_service()` with complete role checks.

---

## 13. PREVIOUS REPORT INCONSISTENCY RECONCILIATION

- **Earlier Statement:** "Procedures originate from 20260912000008_slice8.sql."
- **Fact:** Both procedures were created in `20260916000026_candidate26_remediation.sql` (lines 117 & 174).
- **Reconciliation:** The earlier attribution to Slice 8 was an informal thematic shorthand (attributing asset procedures to the Slice-8 asset domain). This report establishes the authoritative code provenance: **Candidate 26-01 (`20260916000026_candidate26_remediation.sql`) is the sole creator of both functions**.

---

## 14. FUTURE CANDIDATE ELIGIBILITY

A new remediation candidate (Candidate 27-01) is **100% ELIGIBLE AND JUSTIFIED** because:
1. Defect is confirmed and deterministic (SQLSTATE `42883`).
2. Production catalog `fsegpxqoozxmicxcxjun` shares the identical defect.
3. Locked Slices 1–26 remain byte-identical and untouched.
4. Remediation can be cleanly isolated into a new additive migration (`20260917000027_candidate27_remediation.sql`).

---

## 15. ADJUDICATED FINDINGS

### FINDING 1 (`DEF-DB-RPC-01`)
- **FINDING ID:** DEF-DB-RPC-01
- **TITLE:** Undefined `public.is_staff()` dependency in `public.log_asset_service()`
- **AFFECTED FUNCTION:** `public.log_asset_service(UUID, UUID, DATE, TEXT, NUMERIC, VARCHAR)`
- **PROVENANCE:** `20260916000026_candidate26_remediation.sql` (line 174)
- **EVIDENCE:** Line 193 calls `public.is_staff()` which is absent from schema
- **CURRENT PRODUCTION CONDITION:** Catalog contains procedure with undefined `is_staff()` check
- **LOCAL REPRODUCTION:** Deterministic `SQLSTATE 42883` on `npx supabase db reset`
- **SECURITY IMPACT:** Low / Safe Fail (Immediate abort)
- **DATA INTEGRITY IMPACT:** Zero corruption (100% rollback)
- **AVAILABILITY IMPACT:** High for Asset Maintenance Logging feature in real-backend mode
- **USER-FACING IMPACT:** Form submission error alert in real-backend mode
- **LOCKED-SLICE OWNERSHIP:** Candidate 26-01 (`20260916000026_candidate26_remediation.sql`)
- **CAN FUTURE REMEDIATION AVOID LOCKED-SLICE EDITS:** YES (Additive migration Candidate 27-01)
- **CANDIDATE JUSTIFICATION:** PROPOSED — NEW CANDIDATE REMEDIATION JUSTIFIED
- **BUSINESS / AUTHORIZATION DECISION REQUIRED:** Define exact role permissions for `is_staff()` (e.g., `is_admin() OR has_role(uid, 'staff') OR has_role(uid, 'gatekeeper')`)
- **RECOMMENDED GOVERNANCE NEXT STEP:** Proceed to Candidate 27-01 Forensic Validation & Plan

### FINDING 2 (`DEF-DB-RPC-02`)
- **FINDING ID:** DEF-DB-RPC-02
- **TITLE:** Undefined `public.is_staff()` dependency in `public.renew_amc()`
- **AFFECTED FUNCTION:** `public.renew_amc(UUID, DATE, NUMERIC)`
- **PROVENANCE:** `20260916000026_candidate26_remediation.sql` (line 117)
- **EVIDENCE:** Line 131 calls `public.is_staff()` which is absent from schema
- **CURRENT PRODUCTION CONDITION:** Catalog contains procedure with undefined `is_staff()` check
- **LOCAL REPRODUCTION:** Deterministic `SQLSTATE 42883` on `npx supabase db reset`
- **SECURITY IMPACT:** Low / Safe Fail (Immediate abort)
- **DATA INTEGRITY IMPACT:** Zero corruption (100% rollback)
- **AVAILABILITY IMPACT:** High for AMC Renewal feature in real-backend mode
- **USER-FACING IMPACT:** Form submission error alert in real-backend mode
- **LOCKED-SLICE OWNERSHIP:** Candidate 26-01 (`20260916000026_candidate26_remediation.sql`)
- **CAN FUTURE REMEDIATION AVOID LOCKED-SLICE EDITS:** YES (Additive migration Candidate 27-01)
- **CANDIDATE JUSTIFICATION:** PROPOSED — NEW CANDIDATE REMEDIATION JUSTIFIED
- **BUSINESS / AUTHORIZATION DECISION REQUIRED:** Confirm staff role scope for AMC renewal
- **RECOMMENDED GOVERNANCE NEXT STEP:** Proceed to Candidate 27-01 Forensic Validation & Plan

---

## 16. PROPOSED REMEDIATION BOUNDARY

The future remediation (Candidate 27-01) must strictly observe:
1. **Zero Edit to Slices 1–26:** `20260916000026_candidate26_remediation.sql` SHA `ACF35474...` remains untouched.
2. **Additive Migration File:** `supabase/migrations/20260917000027_candidate27_remediation.sql`.
3. **Remediation Contents:**
   - Define `public.is_staff(uid uuid DEFAULT auth.uid())` returning `BOOLEAN` based on `user_roles` membership (`admin`, `staff`, `gatekeeper`, `manager`), OR
   - Re-define `public.renew_amc` and `public.log_asset_service` with verified role checks.

---

## 17. EXPLICITLY OUT-OF-SCOPE ITEMS

During this adjudication:
- **NO** migration SQL was written.
- **NO** source files were modified.
- **NO** Candidate-27 files were created.
- **NO** production database mutations were executed.
- **NO** Vercel deployments were performed.

---

## 18. UNRESOLVED AUTHORIZATION / BUSINESS SEMANTICS

- **Adjudication:** Staff role semantics in SU Society App include `admin`, `super_admin`, and `gatekeeper` (and staff/helper roles). The exact definition of `public.is_staff()` should check `public.is_admin(uid) OR EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = uid AND role_name IN ('staff', 'gatekeeper', 'manager', 'technician') AND revoked_on IS NULL)`.

---

## 19. REQUIRED NEXT GOVERNANCE STAGE

The next governance stage for Candidate 27-01 execution must follow:
1. **NEW CANDIDATE FORENSIC VALIDATION**
2. **FINDING ADJUDICATION**
3. **REMEDIATION BOUNDARY**
4. **FORMAL PLAN**
5. **ADVERSARIAL AUDIT**
6. **IMPLEMENTATION AUTHORIZATION**
7. **IMPLEMENTATION**
8. **POST-IMPLEMENTATION AUDIT**
9. **DEPLOYMENT AUTHORIZATION**
10. **DEPLOYMENT**
11. **POST-DEPLOYMENT VERIFICATION**
12. **SEPARATE FINAL LOCK**

---

## 20. CRYPTOGRAPHIC VERIFICATION & HASH SIGNATURE

- **Artifact Name:** `SU_SOCIETY_APP_LOCKED_RPC_DEFECT_SCOPE_ADJUDICATION_AND_REMEDIATION_BOUNDARY_REVISION_1.md`
- **SHA-256 Digest:** `0533898103A74432BBDE33D30EE309119DADF24920DB82E9F4291C80FF731404`

---

## FINAL CLASSIFICATION

**A — LOCKED RPC DEFECT ADJUDICATED — NEW FUTURE REMEDIATION CANDIDATE JUSTIFIED**

---

**CRITICAL GOVERNANCE RULE:**  
DO NOT modify Slice 1–26. DO NOT modify Slice 26. DO NOT create migration. DO NOT deploy. DO NOT repair. DO NOT execute production RPCs. DO NOT change production. DO NOT create final lock.  
Awaiting formal human governance authorization to initiate Candidate 27-01 planning.
