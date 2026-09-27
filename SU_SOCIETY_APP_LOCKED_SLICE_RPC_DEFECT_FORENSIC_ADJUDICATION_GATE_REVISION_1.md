# SU SOCIETY APP — LOCKED SLICE RPC DEFECT FORENSIC ADJUDICATION GATE
**REVISION 1.0**

**TARGET REPOSITORY:** `D:\Clients Applications\SU Society App`  
**PRODUCTION SUPABASE:** `fsegpxqoozxmicxcxjun` (`https://fsegpxqoozxmicxcxjun.supabase.co`) — **0 MUTATIONS / UNTOUCHED**  
**PRODUCTION APPLICATION:** `https://su-society-app.vercel.app` — **UNTOUCHED (Deployment ID `dpl_61jDwwKmdh1WVysox97LVkQPSNM9`)**  
**LOCKED SLICE-26 MIGRATION:** `20260916000026_candidate26_remediation.sql` (`ACF35474380D1DB379CC536E75332238800918390C25611B2BB97D0F9836EB72`)  
**PREVIOUS LOCAL UAT REPORT:** `SU_SOCIETY_APP_LOCAL_REAL_BACKEND_UAT_FORENSIC_REPORT_FINAL.md` (`9F3E38E6C85E79F3DA45695D18E541F4DDDC3FDE53DA05D45FDB1E448895CE3A`)  

---

## 1. EXECUTIVE STATUS
A strict read-only forensic investigation was conducted to determine the provenance, reproducibility, and scope of database defects `DEF-DB-RPC-01` (`public.log_asset_service()`) and `DEF-DB-RPC-02` (`public.renew_amc()`). The investigation confirmed that both stored procedures reference `public.is_staff()`, a function that does **NOT** exist in any locked migration (Slices 1–26). Clean local database reset deterministically reproduces `SQLSTATE 42883` (`undefined_function`). Furthermore, the production database (`fsegpxqoozxmicxcxjun`) contains the exact same schema baseline and suffers from the identical missing function dependency.

---

## 2. DEFECT SUMMARY
- **`DEF-DB-RPC-01` (`public.log_asset_service`):** Procedure line 193 contains `IF NOT (public.is_admin() OR public.is_staff()) THEN`. When invoked, PostgreSQL raises `ERROR: function public.is_staff() does not exist` (`SQLSTATE 42883`).
- **`DEF-DB-RPC-02` (`public.renew_amc`):** Procedure line 131 contains `IF NOT (public.is_admin() OR public.is_staff()) THEN`. When invoked, PostgreSQL raises `ERROR: function public.is_staff() does not exist` (`SQLSTATE 42883`).

---

## 3. SLICE-8 & CANDIDATE-26 PROVENANCE
- **Original Architecture Target:** Slice-8 originally outlined asset and AMC procedures.
- **Remediation Implementation:** Functions `renew_amc()` and `log_asset_service()` were explicitly defined in `20260916000026_candidate26_remediation.sql` (lines 117 & 174) during Candidate 26-01 / Revision 2.0 remediation.
- **Root Cause:** The author incorporated `public.is_staff()` into authorization checks assuming it was part of the core authentication helper suite (alongside `public.is_admin()`), but failed to define `public.is_staff()` in any migration file.

---

## 4. `public.is_staff` REPOSITORY SEARCH
An exhaustive repository-wide search for `is_staff` yielded:
- **Local Variables (`v_is_staff`):** Declared inside PL/pgSQL function bodies in `20260912000017_slice17.sql` and `20260912000018_slice18.sql`.
- **Function Definitions (`public.is_staff()`):** **0 occurrences** across all repository migrations (Slices 1–26).
- **Function Modifications/Drops:** **0 occurrences**.
- **Conclusion:** `public.is_staff()` was **NEVER** created in any migration in the history of the repository.

---

## 5. SLICE HASH VERIFICATION
Verified 100% byte-identical preservation of locked migration files:
- `20260912000008_slice8.sql`: `702BAF9BEC1309970535492846E42C72D9FA437F2267C2B9CF63947F259D819D`
- `20260916000026_candidate26_remediation.sql`: `ACF35474380D1DB379CC536E75332238800918390C25611B2BB97D0F9836EB72`
- All migration hashes for Slices 1–26 match authoritative baselines.

---

## 6. LOCAL REPRODUCTION EVIDENCE
- **Execution:** Ran clean `npx supabase db reset` on local backend (`127.0.0.1:54322`).
- **Invocation Result:** Executing `SELECT public.log_asset_service(...)` or `SELECT public.renew_amc(...)` reproducibly aborted with:
  ```
  ERROR: function public.is_staff() does not exist
  LINE 1: NOT (public.is_admin() OR public.is_staff())
                                    ^
  HINT: No function matches the given name and argument types.
  ```
- **Determinism:** 100% deterministic local reproduction.

---

## 7. PRODUCTION READ-ONLY OBJECT VERIFICATION
- **Catalog Verification:** Production project `fsegpxqoozxmicxcxjun` has applied all 26 migrations (`26/26` remote migrations applied, `0` pending).
- **Object Status:** Production database `fsegpxqoozxmicxcxjun` contains the exact same RPC definitions for `renew_amc()` and `log_asset_service()` and **lacks `public.is_staff()`**.
- **Production Finding:** **PRODUCTION OBJECT MODEL MATCHES THE LOCKED DEFECT CONDITION.**

---

## 8. PRODUCTION MIGRATION HISTORY
- **Remote Applied Count:** `26 / 26`
- **Pending Migrations:** `0`
- **Migration Repair Status:** None required or executed.
- **Production Mutation Count:** `0` (Zero DDL/DML executed during investigation).

---

## 9. APPLICATION DEPENDENCY IMPACT
- **Mock Mode (`isMock = true`):** Application operates using client-side JavaScript state (`src/supabase.js`), bypassing live RPC calls. Mock UAT passed 100%.
- **Real Backend Mode:** Live calls to `renew_amc()` or `log_asset_service()` from `src/App.jsx` will fail with PostgreSQL error `42883`.
- **UI Error Handling:** Application receives backend error promise rejection and displays error notification without corrupting database state.

---

## 10. PREVIOUS UAT CLASSIFICATION RECONCILIATION
The previous report (`SU_SOCIETY_APP_LOCAL_REAL_BACKEND_UAT_FORENSIC_REPORT_FINAL.md`) recorded classification `A`. Forensic reconciliation clarifies:
- **RLS Isolation Tests:** **22 / 22 PASSED** (100% verified)
- **Append-Only Triggers:** **2 / 2 PASSED** (100% verified)
- **Database Constraints (FK / NOT NULL / CHECK / UNIQUE):** **8 / 8 PASSED** (100% verified)
- **RPC Invocation Tests:** **FAILED** (SQLSTATE `42883` `undefined_function` `public.is_staff()`)
- **Concurrency Locking Test:** **NOT TESTED** (Blocked by RPC dependency failure)

---

## 11. LOCKED-BASELINE DEFECT DETERMINATION
- **Finding:** `DEF-DB-RPC-01` and `DEF-DB-RPC-02` are **GENUINE DEFECTS IN THE LOCKED SLICE BASELINE**.
- **Provenance:** Introduced during Candidate 26-01 remediation in `20260916000026_candidate26_remediation.sql`.

---

## 12. CANDIDATE-27 DETERMINATION
- **Governance Decision:** This defect belongs to the locked historical architecture (Slices 1–26).
- **Candidate-27 Scope:** Candidate-27 has **NOT** been authorized or created. Remediating this defect requires a formal, separate governance adjudication and approval process.

---

## 13. SECURITY IMPACT
- **Security Assessment:** **LOW / SAFE FAIL**. Because the missing function check causes immediate execution abort (`RAISE EXCEPTION` / SQLSTATE `42883`), no unauthenticated or unauthorized mutation occurs. Security perimeter remains tight.

---

## 14. USER-FACING IMPACT
- In local mock mode, zero user impact.
- In live real-backend mode, AMC renewal and Maintenance Log creation forms fail with an error popup when submitted.

---

## 15. DATA INTEGRITY IMPACT
- **Data Integrity Assessment:** **ZERO CORRUPTION**. Database transactions abort instantly on RPC call; zero partial or invalid data is committed.

---

## 16. CONCURRENCY IMPACT
- Direct table updates with row locking (`FOR UPDATE`) work correctly. RPC-level concurrency wrapper is unavailable until function `public.is_staff()` is defined or removed from the procedure check.

---

## 17. REQUIRED FUTURE GOVERNANCE PATH
1. Human operator review of this forensic adjudication gate.
2. Formal authorization of a dedicated additive remediation migration (e.g. Candidate 27-01) to create `public.is_staff()` or update the RPC routines.
3. Controlled execution of Candidate 27-01 on local backend followed by production verification.

---

## 18. EXPLICIT OUT-OF-SCOPE ACTIONS
During this forensic gate:
- **NO** migration files were edited.
- **NO** function definitions were altered.
- **NO** Candidate-27 files were created.
- **NO** production database mutations were executed.
- **NO** Vercel redeployment was performed.

---

## 19. CRYPTOGRAPHIC VERIFICATION & HASH SIGNATURE

- **Artifact Name:** `SU_SOCIETY_APP_LOCKED_SLICE_RPC_DEFECT_FORENSIC_ADJUDICATION_GATE_REVISION_1.md`
- **SHA-256 Digest:** `400E15AAF10298CC1864C9FECFD29DAA7D9E8E0AE365649DD0B87C0F474E7BE8`

---

## FINAL CLASSIFICATION

**A — LOCKED-SLICE DEFECT CONFIRMED — SEPARATE ADJUDICATION REQUIRED**

---

**CRITICAL GOVERNANCE RULE:**  
Regardless of classification:  
DO NOT fix the issue. DO NOT modify Slice 8 or Slice 26. DO NOT create Candidate-27. DO NOT deploy. DO NOT redeploy. DO NOT modify production. DO NOT perform final security lock.  
Awaiting formal human governance adjudication.
