# SU SOCIETY APP — FIND-DB-TEST-01 FORENSIC ADJUDICATION & UAT REPORT INTEGRITY REVIEW
## REVISION 1.0 — READ-ONLY / ZERO MUTATION / ZERO DEPLOYMENT / ZERO LOCK CHANGE

**Target Repository:** `D:\Clients Applications\SU Society App`  
**Target Production Supabase:** `fsegpxqoozxmicxcxjun` (`https://fsegpxqoozxmicxcxjun.supabase.co`)  
**Production Application:** `https://su-society-app.vercel.app`  
**Authoritative Locked Baseline:** Slices 1–27 = LOCKED / IMMUTABLE  
**Adjudicated Finding:** `FIND-DB-TEST-01` (Vendor Society Scope in `log_asset_service`)  
**UAT Report Reference:** `SU_SOCIETY_APP_CANDIDATE_27_01_COMPLETE_END_TO_END_UAT_AND_SECURITY_TEST_REPORT.md`  

---

## 1. EXECUTIVE SUMMARY

This read-only forensic adjudication was conducted to evaluate observation `FIND-DB-TEST-01` from the Candidate-27-01 UAT report and reconcile a minor text reporting inconsistency regarding staff role counts.

**Key Adjudication Conclusions:**
1. **UAT Report Integrity & Role Count Reconciliation:** The report's 45/45 PASS total is 100% verified and internally consistent. The text phrasing "all 6 staff roles" in section narrative is a minor clerical error; the actual matrix lists and tests **7 staff roles** (`admin`, `super_admin`, `secretary`, `treasurer`, `executive_member`, `technician`, `gatekeeper`).
2. **FIND-DB-TEST-01 Adjudication:** Forensic SQL code inspection confirms that `public.log_asset_service()` checks `v_society_id <> public.get_user_society_id()` for the target asset, but does **not** check whether `vendor.society_id = asset.society_id`. Because `log_asset_service()` is `SECURITY DEFINER`, an authenticated staff user bypassing the UI can supply an active `vendor_id` belonging to a different society, resulting in a cross-society vendor link in `asset_maintenance_logs`.
3. **Classification:** **C — FIND-DB-TEST-01 CONFIRMED — NEW FORENSIC REMEDIATION CANDIDATE MAY BE JUSTIFIED**.

No database schema, migration files, application source code, or production state were modified during this adjudication.

---

## 2. UAT REPORT INTEGRITY CHECK

The detailed test matrix in `SU_SOCIETY_APP_CANDIDATE_27_01_COMPLETE_END_TO_END_UAT_AND_SECURITY_TEST_REPORT.md` was audited:

* **Reported Total Test Cases:** `45`
* **PASS Count:** `45`
* **FAIL Count:** `0`
* **BLOCKED Count:** `0`
* **Internal Consistency:** Verified 100% consistent across all 45 enumerated test IDs (`TC-PROD-01` through `TC-AUDIT-01` and `TC-FIND-01`).

---

## 3. ROLE COUNT RECONCILIATION

* **Observed Text:** Narrative text in Section 7 referred to "all 6 staff roles".
* **Actual Enumerated Staff Roles in Matrix:**
  1. `admin`
  2. `super_admin`
  3. `secretary`
  4. `treasurer`
  5. `executive_member`
  6. `technician`
  7. `gatekeeper`
* **Reconciliation Finding:** The correct number of staff roles defined in the application's RBAC model is **7**. The reference to "6" was a minor narrative typo; all 7 staff roles were individually tested and confirmed returning `is_staff() = TRUE`.

---

## 4. ASSET / VENDOR SOCIETY RELATIONSHIP ANALYSIS

The database DDL for `public.asset_maintenance_logs` in Slice 26 (`20260916000026_candidate26_remediation.sql`) establishes:

```sql
CREATE TABLE IF NOT EXISTS public.asset_maintenance_logs (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id  UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    asset_id    UUID NOT NULL REFERENCES public.assets(id) ON DELETE RESTRICT,
    vendor_id   UUID REFERENCES public.vendors(id) ON DELETE RESTRICT,
    ...
);
```

* **Foreign Key Structure:** Single-column FK `vendor_id REFERENCES public.vendors(id)`.
* **Composite Foreign Key:** There is **no** composite foreign key constraint `(society_id, vendor_id) REFERENCES public.vendors(society_id, id)`.
* **Database Guarantee:** The table definition alone does not guarantee that `vendor.society_id` matches `asset_maintenance_logs.society_id`.

---

## 5. `public.log_asset_service()` BACKEND ENFORCEMENT REVIEW

Inspecting lines 174–225 of `20260916000026_candidate26_remediation.sql`:

```sql
SELECT society_id, status INTO v_society_id, v_asset_status
FROM public.assets WHERE id = p_asset_id;

IF v_society_id <> public.get_user_society_id() THEN
    RAISE EXCEPTION 'Cross-society access denied';
END IF;

IF p_vendor_id IS NOT NULL THEN
    SELECT status INTO v_vendor_status
    FROM public.vendors WHERE id = p_vendor_id;
    ...
```

* **Asset Validation:** Strictly verifies that `asset.society_id = public.get_user_society_id()`.
* **Vendor Validation:** Queries `public.vendors` by `p_vendor_id` to check `status = 'active'`, but does **not** compare `vendor.society_id` against `v_society_id`.
* **`SECURITY DEFINER` Impact:** Because `log_asset_service` runs with owner privileges, standard Row Level Security (RLS) on `public.vendors` is bypassed during the `SELECT status` check.
* **Result:** A valid active vendor from Society B will be accepted when logging service for an asset in Society A.

---

## 6. RLS / CONSTRAINT / TRIGGER REVIEW

* **Triggers:** `trg_prevent_maintenance_log_mutation` enforces append-only rules (`UPDATE`/`DELETE` prohibited), but does not validate `vendor_id` society during `INSERT`.
* **RLS Policies:** `p_asset_maintenance_logs_society_isolation` enforces `society_id = public.get_user_society_id()` on the log row itself. The log row is correctly written with `society_id = Society A`.
* **Query Behavior:** When querying `asset_maintenance_logs` joined with `vendors`:
  ```sql
  SELECT l.*, v.name FROM asset_maintenance_logs l
  LEFT JOIN vendors v ON l.vendor_id = v.id;
  ```
  RLS on `public.vendors` filters out Society B's vendor for Society A users, resulting in `v.name IS NULL` in read queries.

---

## 7. EXPLOITABILITY & DATA INTEGRITY ANALYSIS

1. **UI Bypass:** An authenticated staff caller can bypass the frontend UI vendor dropdown and call `supabase.rpc('log_asset_service', { p_asset_id: AssetA, p_vendor_id: VendorB, ... })` directly via API.
2. **Cross-Society Record Creation:** The maintenance log is written referencing `VendorB` under `SocietyA`.
3. **Confidentiality:** `VendorB` details are masked during standard user SELECT queries due to RLS on `vendors`. However, the ID link is persisted.
4. **Data Integrity Contamination:** A maintenance log in Society A points to a vendor in Society B. If society analytics or financial reporting aggregates spending per vendor, foreign vendor IDs cause orphan or inconsistent vendor aggregations.
5. **Classification under Section 4:** **Condition D — Backend enforcement does NOT exist and a cross-society vendor relationship may be created.**

---

## 8. SECURITY & INTEGRITY ASSESSMENT SUMMARY

* **Technical Security Severity:** **LOW** (Requires authenticated staff role; RLS prevents cross-society reading of vendor details).
* **Data Integrity Severity:** **MEDIUM** (Creates cross-society reference contamination in `asset_maintenance_logs`).
* **Root Cause:** Missing explicit vendor society validation `v_vendor_society <> v_society_id` in `public.log_asset_service()`.

---

## 9. FINAL CLASSIFICATION

```
====================================================================================================================
FINAL CLASSIFICATION:
C — FIND-DB-TEST-01 CONFIRMED — NEW FORENSIC REMEDIATION CANDIDATE MAY BE JUSTIFIED
====================================================================================================================
```

---

## 10. REQUIRED NEXT GOVERNANCE ACTION

1. **Slices 1–27 Immutability:** Slices 1–27 remain permanently LOCKED and IMMUTABLE. No migration or function in Slices 1–27 may be edited.
2. **Remediation Path:** If project governance requires strict database-level vendor-society validation in `log_asset_service()`, a new additive candidate slice (e.g. Candidate-28-01 / Slice 28) must be initiated following the full pre-implementation governance lifecycle.

---

## 11. MANDATORY GOVERNANCE STATEMENT

> **NO DATABASE, MIGRATION, SOURCE, OR PRODUCTION STATE WAS MODIFIED DURING THIS ADJUDICATION.**

---

## 12. AUDIT REPORT CHECKSUM

* **Report File:** `SU_SOCIETY_APP_FIND_DB_TEST_01_FORENSIC_ADJUDICATION_REVISION_1.md`
* **Adjudication Time:** `2026-09-17T21:40:00+05:30`
* **Status:** Complete / Stopped
