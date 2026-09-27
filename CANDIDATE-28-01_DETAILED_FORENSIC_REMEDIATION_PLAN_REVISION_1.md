# SU SOCIETY APP — CANDIDATE-28-01 DETAILED FORENSIC REMEDIATION PLAN
## REVISION 1.0 — READ-ONLY / ZERO IMPLEMENTATION / ZERO MUTATION / ZERO DEPLOYMENT / ZERO LOCK CHANGE

**Target Repository:** `D:\Clients Applications\SU Society App`  
**Target Production Supabase:** `fsegpxqoozxmicxcxjun` (`https://fsegpxqoozxmicxcxjun.supabase.co`)  
**Production Application:** `https://su-society-app.vercel.app`  
**Authoritative Locked Baseline:** Slices 1–27 = LOCKED / IMMUTABLE  
**Candidate-27 Migration:** `supabase/migrations/20260917000027_candidate27_remediation.sql` (SHA-256: `7FAA0A08571A54C8A2CFB5EA2B583B7BE4E10BE543B5967228F573EAE61B027E`)  
**Adjudicated Finding:** `FIND-DB-TEST-01` (Vendor Society Scope in `log_asset_service`)  
**Adjudication Reference:** `SU_SOCIETY_APP_FIND_DB_TEST_01_FORENSIC_ADJUDICATION_REVISION_1.md` (SHA-256: `9ADBEBD9E281B1BE2B96BC4965E229543347BC8F0FE6C9328C2D5A08C63FEA72`)  
**Scope Discovery Reference:** `CANDIDATE-28-01_FORENSIC_VALIDATION_AND_REMEDIATION_SCOPE_REVISION_1.md` (SHA-256: `585B42D844AF9A509E9A7CF1632EBD8F3250319970DCD152BE35779B215533BF`)  

---

## 1. EXECUTIVE SUMMARY

This document provides the formal **Remediation Plan** for Candidate-28-01 / Slice 28 to resolve `FIND-DB-TEST-01` in `public.log_asset_service()`.

`FIND-DB-TEST-01` identified that while `public.log_asset_service()` correctly validates that the target asset belongs to the caller's active society (`v_society_id = public.get_user_society_id()`), it does not verify that `vendor.society_id = asset.society_id`. Because `log_asset_service()` runs with `SECURITY DEFINER` privileges, standard table Row Level Security (RLS) on `public.vendors` is bypassed during function execution. An authenticated staff member directly invoking the RPC via API can link an active vendor from a foreign society (Society B) to an asset in Society A.

This plan details:
1. Exact root cause analysis of `public.log_asset_service()`.
2. Cross-society trust-boundary threat model (20 threat scenarios).
3. Minimal safe remediation boundary preserving function signatures, append-only triggers, and audit logging.
4. Safe three-valued NULL logic handling.
5. Complete adversarial test matrix and acceptance criteria.
6. Formal readiness classification for a separate human implementation authorization gate.

> [!IMPORTANT]
> **READ-ONLY REMEDIATION PLAN:** This report is a governance plan only. No database DDL/DML, source code, migration files, or production/local state have been modified.

---

## 2. PROVENANCE RECONCILIATION

* **Defect Origin:** Introduced in Slice 26 (`20260916000026_candidate26_remediation.sql` Step 6.2).
* **Candidate-27 Action:** Candidate-27-01 (`20260917000027_candidate27_remediation.sql`) strictly restored `public.is_staff()`, leaving `public.log_asset_service()`'s vendor validation logic unmodified.
* **Current Status:** Slices 1–27 are formally **LOCKED** and **IMMUTABLE**. The current `log_asset_service()` routine in production and local database retains the vendor-society gap.

---

## 3. CURRENT FUNCTION FORENSICS

```sql
CREATE OR REPLACE FUNCTION public.log_asset_service(
    p_asset_id UUID,
    p_vendor_id UUID,
    p_service_date DATE,
    p_description TEXT,
    p_cost NUMERIC,
    p_performed_by VARCHAR
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_society_id UUID;
    v_asset_status VARCHAR;
    v_vendor_status VARCHAR;
    v_log_id UUID;
BEGIN
    IF NOT (public.is_admin() OR public.is_staff()) THEN
        RAISE EXCEPTION 'Access Denied: Only Admins or Staff can log asset services';
    END IF;

    SELECT society_id, status INTO v_society_id, v_asset_status
    FROM public.assets
    WHERE id = p_asset_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Asset not found';
    END IF;

    IF v_society_id <> public.get_user_society_id() THEN
        RAISE EXCEPTION 'Cross-society access denied';
    END IF;

    IF p_vendor_id IS NOT NULL THEN
        SELECT status INTO v_vendor_status
        FROM public.vendors
        WHERE id = p_vendor_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Vendor not found';
        END IF;

        IF v_vendor_status <> 'active' THEN
            RAISE EXCEPTION 'Cannot log service with inactive vendor';
        END IF;
    END IF;

    INSERT INTO public.asset_maintenance_logs (
        society_id, asset_id, vendor_id, service_date, description, cost, performed_by, created_by
    ) VALUES (
        v_society_id, p_asset_id, p_vendor_id, p_service_date, p_description, p_cost, p_performed_by, auth.uid()
    ) RETURNING id INTO v_log_id;

    INSERT INTO public.audit_logs (
        society_id, actor_id, action, entity_type, entity_id, details
    ) VALUES (
        v_society_id, auth.uid(), 'asset_service_logged', 'asset_maintenance_logs', v_log_id,
        jsonb_build_object('asset_id', p_asset_id, 'vendor_id', p_vendor_id, 'cost', p_cost, 'service_date', p_service_date)
    );

    RETURN v_log_id;
END;
$$;
```

**Forensic Breakdown of Statements:**
* **Line 193:** Authorization check (`is_admin() OR is_staff()`) — **INTACT**
* **Lines 197–207:** Asset lookup and caller society check (`v_society_id <> get_user_society_id()`) — **INTACT**
* **Lines 209–220 (DEFECT STATEMENT):** `SELECT status INTO v_vendor_status FROM public.vendors WHERE id = p_vendor_id;`
  * *Defect:* Fails to retrieve `society_id` from `public.vendors`.
  * *Defect:* Fails to assert `vendor.society_id = v_society_id`.
* **Lines 222–242:** Dual-write insert to `asset_maintenance_logs` and `audit_logs` — **INTACT**

---

## 4. CROSS-SOCIETY TRUST-BOUNDARY ANALYSIS

```
Authenticated Caller (Staff / Admin)
       │
       ▼
log_asset_service(p_asset_id, p_vendor_id, ...) [SECURITY DEFINER]
       │
       ├─► Check caller role: is_admin() OR is_staff() (Passed)
       ├─► Fetch Asset A -> asset.society_id = Society A (Passed)
       ├─► Validate Asset A society == Caller active society (Passed)
       │
       ├─► Fetch Vendor B (by p_vendor_id) [SECURITY DEFINER Bypasses RLS]
       │   ├─► Check vendor status == 'active' (Passed)
       │   └─► MISSING CHECK: vendor.society_id == Society A? (Bypassed!)
       │
       └─► INSERT asset_maintenance_logs (society_id = Society A, vendor_id = Vendor B) -> SUCCESS
```

* **SECURITY DEFINER Impact:** Standard table RLS on `public.vendors` (`USING (society_id = public.get_user_society_id())`) is not evaluated inside a `SECURITY DEFINER` function executing under the table owner role.
* **Backend Enforcement Void:** The database routine contains zero logical assertion matching vendor society to asset society.

---

## 5. MINIMAL REMEDIATION BOUNDARY

The smallest, additive remediation required for a future Candidate-28-01:

1. Declare local variable `v_vendor_society_id UUID;`.
2. Update vendor query to retrieve `society_id` alongside `status`:
   ```sql
   SELECT society_id, status INTO v_vendor_society_id, v_vendor_status
   FROM public.vendors
   WHERE id = p_vendor_id;
   ```
3. Insert explicit vendor-society match validation immediately after existence check:
   ```sql
   IF v_vendor_society_id IS NULL OR v_vendor_society_id <> v_society_id THEN
       RAISE EXCEPTION 'Vendor does not belong to the asset society';
   END IF;
   ```
4. Order of checks inside `IF p_vendor_id IS NOT NULL THEN`:
   * Step 1: Check existence (`IF NOT FOUND THEN RAISE EXCEPTION 'Vendor not found';`).
   * Step 2: Check status (`IF v_vendor_status <> 'active' THEN RAISE EXCEPTION 'Cannot log service with inactive vendor';`).
   * Step 3: Check society match (`IF v_vendor_society_id IS NULL OR v_vendor_society_id <> v_society_id THEN RAISE EXCEPTION 'Vendor does not belong to the asset society';`).

---

## 6. SECURITY INVARIANTS

| Invariant # | Security Invariant | Planned Action |
| :-: | :--- | :--- |
| `INV-01` | Require Admin or Staff role (`is_admin() OR is_staff()`) | **PRESERVE** |
| `INV-02` | Require Asset society match to caller active society | **PRESERVE** |
| `INV-03` | Require Active Vendor status (`status = 'active'`) | **PRESERVE** |
| `INV-04` | Require Vendor society match to Asset society | **ADD / ENFORCE** |
| `INV-05` | Append-only maintenance log trigger (`trg_prevent_maintenance_log_mutation`) | **MUST NOT CHANGE** |
| `INV-06` | Immutable audit log trigger (`audit_logs`) | **MUST NOT CHANGE** |
| `INV-07` | Dual-write audit record creation (`asset_service_logged`) | **PRESERVE** |
| `INV-08` | Function Signature `log_asset_service(UUID, UUID, DATE, TEXT, NUMERIC, VARCHAR)` | **MUST NOT CHANGE** |
| `INV-09` | Return Type `UUID` | **MUST NOT CHANGE** |
| `INV-10` | `SECURITY DEFINER` with pinned `search_path = public, pg_temp` | **PRESERVE** |
| `INV-11` | Explicit REVOKE EXECUTE FROM PUBLIC, GRANT TO authenticated & service_role | **PRESERVE** |
| `INV-12` | Slices 1–27 Immutability Baseline | **MUST NOT CHANGE** |

---

## 7. ADVERSARIAL THREAT MODEL

| Threat ID | Threat Scenario / Input | Current Result | Expected Secure Result | Required Verification Test |
| :--- | :--- | :--- | :--- | :--- |
| `T1` | Staff A + Asset A + Vendor A (Same Society A) | Success | Success (Log created) | `TC-ADV-01` |
| `T2` | Staff A + Asset A + Vendor B (Foreign Society B) | **Success (DEFECT)** | **Rejected: 'Vendor does not belong to the asset society'** | `TC-ADV-02` |
| `T3` | Staff A + Asset B (Foreign Society B) + Vendor A | Rejected ('Cross-society access denied') | Rejected ('Cross-society access denied') | `TC-ADV-03` |
| `T4` | Staff A + Asset B + Vendor B (Both Foreign) | Rejected ('Cross-society access denied') | Rejected ('Cross-society access denied') | `TC-ADV-04` |
| `T5` | Admin A + Foreign Vendor B | **Success (DEFECT)** | **Rejected: 'Vendor does not belong to the asset society'** | `TC-ADV-05` |
| `T6` | Nonexistent Vendor UUID | Rejected ('Vendor not found') | Rejected ('Vendor not found') | `TC-ADV-06` |
| `T7` | Inactive Vendor (Same Society) | Rejected ('Cannot log service with inactive vendor') | Rejected ('Cannot log service with inactive vendor') | `TC-ADV-07` |
| `T8` | Vendor with `NULL` `society_id` | N/A (Schema `NOT NULL`) | Rejected ('Vendor does not belong to the asset society') | `TC-ADV-08` |
| `T9` | Asset with `NULL` `society_id` | N/A (Schema `NOT NULL`) | Rejected ('Asset not found') | `TC-ADV-09` |
| `T10` | `p_vendor_id IS NULL` | Success (`vendor_id = NULL`) | Success (`vendor_id = NULL`) | `TC-ADV-10` |
| `T11` | Direct PostgREST RPC Invocation (API Bypass) | **Success (DEFECT)** | **Rejected at RPC boundary** | `TC-ADV-11` |
| `T12` | Direct SQL invocation under `authenticated` | **Success (DEFECT)** | **Rejected at RPC boundary** | `TC-ADV-12` |
| `T13` | Concurrent service logging requests | Success (Isolated inserts) | Success (Isolated inserts) | `TC-ADV-13` |
| `T14` | Repeated malicious RPC invocation | **Success (DEFECT)** | **Rejected repeatedly** | `TC-ADV-14` |
| `T15` | Malformed UUID strings | PostgreSQL Syntax Error | PostgreSQL Syntax Error | `TC-ADV-15` |
| `T16` | Audit logging dual-write failure | Atomic Rollback | Atomic Rollback | `TC-ADV-16` |
| `T17` | Trigger failure on maintenance logs | Abort & Rollback | Abort & Rollback | `TC-ADV-17` |
| `T18` | Resident / Member role invocation | Rejected ('Access Denied') | Rejected ('Access Denied') | `TC-ADV-18` |
| `T19` | Search-path hijacking attempt | Pinned to `public, pg_temp` | Pinned to `public, pg_temp` | `TC-ADV-19` |
| `T20` | Inactive Vendor from Foreign Society | Rejected ('Cannot log service with inactive vendor') | Rejected ('Cannot log service with inactive vendor') | `TC-ADV-20` |

---

## 8. NULL AND ERROR SEMANTICS

PostgreSQL uses three-valued logic (`TRUE`, `FALSE`, `UNKNOWN`). Evaluating `NULL <> v_society_id` yields `UNKNOWN` (treated as false in `IF` statements), which could lead to security bypasses if not explicitly handled.

**Safe Null Handling Rules for Candidate-28-01:**
1. **Optional Vendor Input (`p_vendor_id IS NULL`):** If `p_vendor_id` is `NULL`, the entire vendor validation block is skipped. The log is inserted with `vendor_id = NULL` (valid optional vendor logging).
2. **Mandatory Vendor Society Check (`v_vendor_society_id`):** When `p_vendor_id IS NOT NULL`, `v_vendor_society_id` is fetched. If `v_vendor_society_id` is `NULL` (defensive schema edge-case), or if `v_vendor_society_id <> v_society_id`, the check must explicitly evaluate to `TRUE` for rejection:
   ```sql
   IF v_vendor_society_id IS NULL OR v_vendor_society_id <> v_society_id THEN
       RAISE EXCEPTION 'Vendor does not belong to the asset society';
   END IF;
   ```
3. Using `IS NULL OR v_vendor_society_id <> v_society_id` ensures three-valued logic never allows a `NULL` `society_id` to bypass security enforcement.

---

## 9. DEPENDENCY FORENSICS

* **Callers:** Frontend application calls `supabase.rpc('log_asset_service', ...)`.
* **RPC Signature:** Unchanged.
* **Audit Triggers & Logs:** Unchanged.
* **RLS Policies:** Unchanged.
* **Database Objects Bounded:** Modifies strictly the body of `public.log_asset_service()`. Zero changes required for tables, indexes, triggers, or secondary RPCs.

---

## 10. LOCKED BASELINE PROTECTION

* **Slices 1–27 Immutability:** All migration files `20260912000001` through `20260917000027` remain byte-identical and untouched.
* **Candidate-27 Lock:** `20260917000027_candidate27_remediation.sql` SHA-256 (`7FAA0A08571A54C8A2CFB5EA2B583B7BE4E10BE543B5967228F573EAE61B027E`) remains unchanged.
* **Additive Migration Bounding:** Candidate-28-01 will be created as a new standalone migration file `20260918000028_candidate28_remediation.sql`.

---

## 11. FUTURE MIGRATION DESIGN (PLAN ONLY)

* **Proposed Filename:** `supabase/migrations/20260918000028_candidate28_remediation.sql`
* **Migration Scope:**
  1. `CREATE OR REPLACE FUNCTION public.log_asset_service(...)` with vendor society check.
  2. `REVOKE EXECUTE ON FUNCTION public.log_asset_service FROM PUBLIC;`
  3. `GRANT EXECUTE ON FUNCTION public.log_asset_service TO authenticated;`
  4. `GRANT EXECUTE ON FUNCTION public.log_asset_service TO service_role;`
* **Data Migration:** Zero required (no historical schema or column changes).
* **Rollback Plan:** Standalone SQL script restoring Slice 26 function body if ever needed.

---

## 12. ADVERSARIAL TEST MATRIX (POST-IMPLEMENTATION PLAN)

| Test ID | Test Category | Precondition | Action | Expected Result | Pass/Fail Criterion |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `TC-ADV-01` | Valid Service Log | Staff A active | `log_asset_service(AssetA, VendorA, ...)` | Log ID returned | Non-null UUID returned |
| `TC-ADV-02` | Cross-Society Vendor | Staff A active | `log_asset_service(AssetA, VendorB, ...)` | Exception raised | Exception: 'Vendor does not belong to the asset society' |
| `TC-ADV-03` | Cross-Society Asset | Staff A active | `log_asset_service(AssetB, VendorA, ...)` | Exception raised | Exception: 'Cross-society access denied' |
| `TC-ADV-05` | Admin Cross-Vendor | Admin A active | `log_asset_service(AssetA, VendorB, ...)` | Exception raised | Exception: 'Vendor does not belong to the asset society' |
| `TC-ADV-10` | NULL Vendor ID | Staff A active | `log_asset_service(AssetA, NULL, ...)` | Log ID returned | Non-null UUID, `vendor_id IS NULL` |
| `TC-ADV-18` | Resident Call | Member A active | `log_asset_service(AssetA, VendorA, ...)` | Exception raised | Exception: 'Access Denied' |
| `TC-ADV-16` | Audit Dual-Write | Staff A active | `log_asset_service(AssetA, VendorA, ...)` | Audit row inserted | `audit_logs` has matching row |

---

## 13. ACCEPTANCE CRITERIA

Candidate-28-01 shall be considered accepted ONLY if:
1. Root cause in `log_asset_service()` is resolved by validating `v_vendor_society_id = v_society_id`.
2. Direct RPC invocation with a foreign society vendor is strictly rejected.
3. Slices 1–27 remain byte-identical.
4. Function signature and return type remain unchanged.
5. `p_vendor_id IS NULL` behavior remains functional.
6. Three-valued NULL logic cannot bypass vendor-society validation.
7. Append-only triggers and dual-write audit logs execute cleanly.
8. 100% of planned adversarial test cases pass.

---

## 14. IMPLEMENTATION AUTHORIZATION GATE

```
====================================================================================================================
GATE CLASSIFICATION:
A — READY FOR SEPARATE IMPLEMENTATION AUTHORIZATION
====================================================================================================================
```

> [!CAUTION]
> **Implementation is NOT authorized by this report.**
> Proceeding to authoring `20260918000028_candidate28_remediation.sql` or applying changes requires a separate, explicit human authorization directive.

---

## 15. GOVERNANCE INTEGRITY STATEMENT

| Metric / Question | Value / Status |
| :--- | :--- |
| **Was the production database modified?** | **NO** |
| **Was production data modified?** | **NO** |
| **Was local schema or database modified?** | **NO** |
| **Were application source files modified?** | **NO** |
| **Were migration files created or modified?** | **NO** |
| **Was Vercel or production deployed?** | **NO** |
| **Was locked baseline (Slices 1–27) altered?** | **NO** |
| **Was Candidate-27 altered?** | **NO** |
| **Were database locks modified?** | **NO** |

---

## 16. EVIDENCE & HASH SUMMARY

* **Candidate-27 Migration Hash:** `7FAA0A08571A54C8A2CFB5EA2B583B7BE4E10BE543B5967228F573EAE61B027E`
* **Finding Adjudication Report Hash:** `9ADBEBD9E281B1BE2B96BC4965E229543347BC8F0FE6C9328C2D5A08C63FEA72`
* **Scope Discovery Report Hash:** `585B42D844AF9A509E9A7CF1632EBD8F3250319970DCD152BE35779B215533BF`
* **Remediation Plan File:** `CANDIDATE-28-01_DETAILED_FORENSIC_REMEDIATION_PLAN_REVISION_1.md`
* **Status:** Plan Complete / Awaiting Human Implementation Authorization
