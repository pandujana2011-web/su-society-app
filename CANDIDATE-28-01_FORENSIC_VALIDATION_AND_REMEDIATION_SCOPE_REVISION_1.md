# CANDIDATE-28-01 FORENSIC VALIDATION & REMEDIATION SCOPE DISCOVERY
## REVISION 1.0 — READ-ONLY / ZERO IMPLEMENTATION / ZERO MUTATION / ZERO DEPLOYMENT / ZERO LOCK CHANGE

**Target Repository:** `D:\Clients Applications\SU Society App`  
**Target Production Supabase:** `fsegpxqoozxmicxcxjun` (`https://fsegpxqoozxmicxcxjun.supabase.co`)  
**Production Application:** `https://su-society-app.vercel.app`  
**Authoritative Locked Baseline:** Slices 1–27 = LOCKED / IMMUTABLE  
**Candidate-27 Status:** Formally LOCKED (`20260917000027_candidate27_remediation.sql` SHA-256: `7FAA0A08571A54C8A2CFB5EA2B583B7BE4E10BE543B5967228F573EAE61B027E`)  
**Confirmed Finding:** `FIND-DB-TEST-01` (Vendor Society Scope in `log_asset_service`)  
**Finding Adjudication Reference:** `SU_SOCIETY_APP_FIND_DB_TEST_01_FORENSIC_ADJUDICATION_REVISION_1.md` (SHA-256: `9ADBEBD9E281B1BE2B96BC4965E229543347BC8F0FE6C9328C2D5A08C63FEA72`)  

---

## 1. EXECUTIVE SUMMARY

This read-only forensic validation and remediation scope discovery evaluated confirmed finding `FIND-DB-TEST-01` to determine whether a new additive remediation candidate (Candidate-28-01 / Slice 28) is technical and governance justified, and to establish the minimum safe remediation boundary.

**Key Findings:**
1. **Provenance:** The flaw in vendor validation within `public.log_asset_service()` was introduced in Slice 26 (`20260916000026_candidate26_remediation.sql`). Candidate-27-01 strictly restored the missing `is_staff()` dependency without altering `log_asset_service()`'s internal vendor validation logic.
2. **Root Cause:** `public.log_asset_service()` is a `SECURITY DEFINER` routine that validates `asset.society_id = public.get_user_society_id()`, but queries `public.vendors` by `id = p_vendor_id` checking only `status = 'active'`, without checking `vendor.society_id`.
3. **Exploitability & Impact:** An authenticated staff user invoking the RPC directly can supply an active vendor ID from a foreign society (Society B) for an asset in Society A. The RPC succeeds and records the cross-society vendor reference in `asset_maintenance_logs`.
4. **Remediation Boundary:** A new additive candidate migration (Candidate-28-01 / Slice 28) is fully justified to add explicit vendor society matching `v_vendor_society_id <> v_society_id` without altering function signatures or caller contracts.

---

## 2. FINDING PROVENANCE

* **Introducing Migration:** `20260916000026_candidate26_remediation.sql` (Slice 26).
* **Step / Component:** Step 6.2 — RPC: Atomic Service Logging with Dual-Write Audit (`public.log_asset_service`).
* **Candidate-27 Impact:** Candidate-27-01 (`20260917000027_candidate27_remediation.sql`) introduced `public.is_staff()`, but made **zero** changes to `log_asset_service()`.
* **Baseline Status:** Slices 1–27 are formally LOCKED and IMMUTABLE.

---

## 3. EXACT ROOT CAUSE ANALYSIS

In `20260916000026_candidate26_remediation.sql`, lines 197–220:

```sql
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
```

**Root Cause Checklist:**
* **A. Asset Society Retrieval:** `SELECT society_id INTO v_society_id FROM public.assets WHERE id = p_asset_id;` — **YES**
* **B. Asset Authorization Check:** `IF v_society_id <> public.get_user_society_id() THEN RAISE EXCEPTION ...` — **YES**
* **C. Vendor Existence Check:** `SELECT status INTO v_vendor_status FROM public.vendors WHERE id = p_vendor_id;` — **YES**
* **D. Vendor Status Check:** `IF v_vendor_status <> 'active' THEN ...` — **YES**
* **E. Vendor Society Retrieval:** `vendor.society_id` is **NOT** retrieved. — **NO**
* **F. Asset/Vendor Society Equality Enforcement:** `v_vendor_society_id <> v_society_id` is **NOT** checked. — **NO**
* **G. SECURITY DEFINER Effect:** Execution context runs with table owner privileges, bypassing standard RLS checks on `public.vendors` during the `SELECT status` query. — **YES**
* **H. RLS Bypass:** RLS on `vendors` is bypassed inside the function. — **YES**

---

## 4. EXPLOITABILITY ANALYSIS

1. **Direct RPC Execution:** An authenticated staff user (e.g. `admin` or `technician`) can bypass UI vendor dropdown filtering and invoke `supabase.rpc('log_asset_service', { p_asset_id: AssetA, p_vendor_id: VendorB, ... })`.
2. **Cross-Society Record Creation:** The database permits the insert into `asset_maintenance_logs` with `society_id = Society A` and `vendor_id = Vendor B`.
3. **Data Integrity Impact:** Cross-society vendor reference contamination in `asset_maintenance_logs`.
4. **Confidentiality / Exposure:** Standard user queries on `asset_maintenance_logs` joined with `vendors` return `NULL` for vendor details due to RLS on `vendors`. However, foreign key linkage is persisted.
5. **Caller Privileges:** Requires valid staff/admin credentials. Standard member or tenant roles cannot exploit this because `is_staff()` rejects them prior to vendor validation.

---

## 5. EXISTING CONTROLS AUDIT

| Control Layer | Control Type | Description | Status |
| :--- | :--- | :--- | :--- |
| **Frontend UI** | UI Control | Vendor dropdown filters options by `society_id` | Present (UI only) |
| **Foreign Key** | Database Control | `vendor_id REFERENCES public.vendors(id)` | Present (Single-column FK; doesn't enforce society) |
| **RLS Policies** | Database Control | RLS on `vendors` enforces `society_id` on SELECT | Present (Bypassed by `SECURITY DEFINER` RPC) |
| **Function Checks** | Database Control | `v_vendor_society_id <> v_society_id` check | **MISSING** |

---

## 6. MINIMUM SAFE REMEDIATION BOUNDARY

The minimal safe additive remediation conceptual change for a future Candidate-28-01:

1. In `public.log_asset_service()`, modify the vendor query to retrieve both `society_id` and `status`:
   ```sql
   SELECT society_id, status INTO v_vendor_society_id, v_vendor_status
   FROM public.vendors
   WHERE id = p_vendor_id;
   ```
2. Add an explicit society equality check:
   ```sql
   IF v_vendor_society_id <> v_society_id THEN
       RAISE EXCEPTION 'Vendor does not belong to the asset society';
   END IF;
   ```
3. Preserve all existing parameters, return types (`RETURNS UUID`), authorization checks (`is_admin() OR is_staff()`), append-only triggers, and dual-write audit logs intact.

---

## 7. FUNCTION CONTRACT PRESERVATION

Any future Candidate-28-01 remediation **MUST** maintain the exact RPC contract:

```sql
public.log_asset_service(
    p_asset_id UUID,
    p_vendor_id UUID,
    p_service_date DATE,
    p_description TEXT,
    p_cost NUMERIC,
    p_performed_by VARCHAR
)
RETURNS UUID
```

* **No Parameter Changes:** Zero added, removed, or renamed arguments.
* **No Return Type Changes:** Remains `RETURNS UUID`.
* **No Role Model Changes:** Preserves `is_staff()` and `is_admin()`.

---

## 8. PRODUCTION SAFETY VERIFICATION

* **Production Database State:** Production Supabase `fsegpxqoozxmicxcxjun` remains 100% untouched at 27/27 applied migrations.
* **Locked Baseline:** Slices 1–27 remain byte-identical and locked.
* **Source & Vercel:** Zero application source code modifications; zero Vercel redeployments.

---

## 9. CANDIDATE JUSTIFICATION & FINAL CLASSIFICATION

```
====================================================================================================================
FINAL CLASSIFICATION:
A — NEW CANDIDATE-28-01 IS JUSTIFIED — BACKEND VENDOR-SOCIETY INTEGRITY GAP CONFIRMED
====================================================================================================================
```

---

## 10. MANDATORY GOVERNANCE STATEMENT

> **NO DATABASE, MIGRATION, SOURCE, PRODUCTION DATA, OR LOCKED BASELINE WAS MODIFIED DURING THIS FORENSIC VALIDATION.**

---

## 11. REPORT CHECKSUM

* **Report File:** `CANDIDATE-28-01_FORENSIC_VALIDATION_AND_REMEDIATION_SCOPE_REVISION_1.md`
* **Validation Completed At:** `2026-09-17T21:48:00+05:30`
* **Status:** Complete / Stopped
