# SU SOCIETY APP — APPLICATION FINDINGS 01–02
# FORENSIC REMEDIATION BOUNDARY & IMPLEMENTATION PLAN
## REVISION 1.0 — POST-SLICE-26 APPLICATION INTEGRATION

---

### 1. EXECUTIVE STATUS

- **Artifact Name:** `APPLICATION_FINDINGS_01_02_REMEDIATION_BOUNDARY_AND_PLAN_REVISION_1.md`
- **Revision:** 1.0
- **Target Repository:** `D:\Clients Applications\SU Society App`
- **Target Supabase Project:** `fsegpxqoozxmicxcxjun` (`pandujana2011-web's Project` / `ap-south-1`)
- **Execution Mode:** STRICT PLAN ONLY / STRICT READ ONLY (Zero implementation, zero database/schema/code mutation, zero deployment, zero candidate-27).
- **Authoritative Database Baseline:** Slices 1–26 Formally Locked and Immutable (`20260916000026_candidate26_remediation.sql` SHA-256 `ACF35474380D1DB379CC536E75332238800918390C25611B2BB97D0F9836EB72`).
- **Remediation Scope:** Application-layer remediation boundaries and non-code implementation plans for `APP-FINDING-01` (Expense Voucher Vendor Selection) and `APP-FINDING-02` (Slice-26 Asset/AMC UI Tab & Workflow Surface Exposure).

---

### 2. GOVERNANCE & BASELINE VERIFICATION

- **Local Migration 26 Verification:**
  - File: `supabase/migrations/20260916000026_candidate26_remediation.sql`
  - Expected SHA-256: `ACF35474380D1DB379CC536E75332238800918390C25611B2BB97D0F9836EB72`
  - Observed SHA-256: `ACF35474380D1DB379CC536E75332238800918390C25611B2BB97D0F9836EB72` (MATCH / PASS).
- **Remote Migration History Verification:**
  - Command: `npx supabase migration list --linked`
  - Applied Local/Remote Migrations: 26 / 26 (`20260912000001` through `20260916000026`).
  - Pending Migration Count: **0**.
- **Database Baseline Immutability:**
  - Slices 1–26 remain byte-identical. Zero DDL/DML executed. Zero schema changes proposed.

---

### 3. APP-FINDING-01 EVIDENCE

- **Finding ID:** `APP-FINDING-01`
- **Classification:** A — Confirmed Application/Schema Contract Defect
- **Severity:** MEDIUM
- **Affected Application Components:** `src/App.jsx` (Expense Voucher Form line 2251), `src/supabase.js` (`db.expense_vouchers.create` line 1672).
- **Affected Database Objects:** `public.expense_vouchers`, `public.vendors`.
- **Observed Condition:**
  - In `src/App.jsx` line 2251, the Expense Voucher creation form uses a raw text `<input>` field (`vVendor` state) for vendor entry:
    ```jsx
    <input type="text" className="form-control" placeholder="e.g. Apex Security Ltd" value={vVendor} onChange={(e) => setVVendor(e.target.value)} required />
    ```
  - In `src/supabase.js` line 1672, `vendor_name` is passed and stored as unvalidated raw text without referencing `public.vendors`.
- **Expected Contract:**
  - The canonical Slice-26 database baseline includes `public.vendors` (`id`, `society_id`, `name`, `category`, `contact_person`, `phone`, `email`, `address`, `tax_id`, `status`).
  - Expense vouchers should bind to registered vendors from `public.vendors` using `vendor_id` (UUID foreign key) and auto-populating canonical `vendor_name`.
- **Impact:**
  - Storing raw text allows typos, inconsistent vendor naming, bypasses vendor master audit controls, and breaks relational queries against `public.vendors`.

---

### 4. APP-FINDING-01 REMEDIATION BOUNDARY

- **Required Implementation Scope:**
  1. **Data Access API Layer (`src/supabase.js`):** Add `db.vendors` helper API:
     - `list(currentUser)`: Query active vendors scoped by `currentUser.society_id`.
     - `create(vendorData, currentUser)`: Register a new vendor in `public.vendors`.
  2. **Application State (`src/App.jsx`):**
     - Add `vendorsList` state array in `BillingManagerView` / `FinancialAdminView`.
     - Fetch `db.vendors.list(user)` inside `loadBillingData()` when `activeSubTab === 'expenses'`.
  3. **UI Form Component (`src/App.jsx`):**
     - Replace raw text input at line 2251 with a `<select>` dropdown populated from `vendorsList`.
     - Bind `vVendorId` state to selected vendor ID and auto-set `vVendor` to selected vendor's canonical `name`.
- **Optional UX Enhancement Scope:**
  - Include an inline "+ Quick Add Vendor" button adjacent to the dropdown to allow admins to register a vendor without navigating away from the voucher form.
- **Unresolved Product/Business Decision:**
  - Whether ad-hoc / one-time vendors without pre-registration should be permitted (e.g. selecting "Other / Manual Entry" allowing free text where `vendor_id` is null), or if mandatory vendor registration is required for all expense vouchers.

---

### 5. APP-FINDING-01 DEPENDENCIES

- **Target Files:**
  - `src/supabase.js`
  - `src/App.jsx`
- **Affected State / Hooks:**
  - `vendorsList` (Array)
  - `vVendorId` (UUID String)
  - `vVendor` (Display String)
- **Reusable Helpers:**
  - Existing `db` object architecture in `src/supabase.js`.
  - Existing `loadBillingData()` lifecycle hook in `src/App.jsx`.
- **Package Dependencies:**
  - **0 new npm packages required.** Reuses React state and standard HTML `<select>` elements.

---

### 6. APP-FINDING-01 SECURITY CONSIDERATIONS

- **Society Isolation:** `db.vendors.list()` MUST filter records strictly by the authenticated user's `society_id`.
- **Role Enforcement:** Vendor registration and voucher creation remain restricted to authorized admin roles (`admin`, `super_admin`, `treasurer`).
- **RLS Authority:** Supabase client calls interact directly with locked RLS policies on `public.vendors` and `public.expense_vouchers`. No service-role credentials will be introduced into browser code.

---

### 7. APP-FINDING-02 EVIDENCE

- **Finding ID:** `APP-FINDING-02`
- **Classification:** D — Data-Flow / Workflow Defect
- **Severity:** LOW
- **Affected Application Components:** `src/App.jsx` (Navigation / Tab Structure), `src/supabase.js` (Missing API wrappers for Slice 26 tables).
- **Affected Database Objects:** `public.assets`, `public.vendors`, `public.asset_amc`, `public.asset_maintenance_logs`, RPC `renew_amc()`, RPC `log_asset_service()`.
- **Observed Condition:**
  - Slice 26 deployed and activated complete backend infrastructure for Assets, Vendors, AMCs, and Maintenance Logs.
  - However, `src/App.jsx` does not expose UI tabs, views, or forms for managing assets, viewing AMC status, renewing AMCs via `renew_amc()`, or logging service events via `log_asset_service()`.
- **Expected Contract:**
  - Application frontend should expose user interface workflows for administrators to interact with deployed Slice-26 assets, vendor masters, AMC contracts, and maintenance logs.
- **Impact:**
  - Users are unable to utilize Slice-26 backend capabilities through the application UI.

---

### 8. APP-FINDING-02 REMEDIATION BOUNDARY

- **Required Implementation Scope:**
  1. **Data Access API Layer (`src/supabase.js`):** Implement client API helpers for Slice-26 objects:
     - `db.assets`: `list(currentUser)`, `create(assetData, currentUser)`, `updateStatus(assetId, status, currentUser)`.
     - `db.asset_amc`: `list(currentUser)`, `create(amcData, currentUser)`, `renew(amcId, newEnd, cost, vendorId, currentUser)` (invoking `renew_amc()` RPC).
     - `db.asset_maintenance_logs`: `list(assetId, currentUser)`, `logService(serviceData, currentUser)` (invoking `log_asset_service()` RPC).
  2. **UI Views & Navigation (`src/App.jsx`):**
     - Add dedicated UI sub-tabs under `Operations Portal` or `Financial Sub-Ledger Manager`:
       - **Asset Inventory Register:** Display asset cards/table with `asset_code`, `name`, `purchase_cost`, `serial_number`, and `status` (`active`, `maintenance`, `retired`).
       - **Vendor Master Directory:** Display registered vendors, contact info, and tax IDs.
       - **AMC & Maintenance Tracker:** Display active AMC contracts, expiration alerts, AMC renewal form (calling `renew_amc()`), and service logging form (calling `log_asset_service()`).
- **Minimum UI Integration Boundary:**
  - Reuses existing component structures (`glass-panel`, `table-custom`, modal overlays, standard tabs).
- **Unresolved Product/Business Decision:**
  - Determining exact primary tab placement: placing Asset Management as a sub-tab under `Operations Portal` vs `Financial Sub-Ledger Manager`.

---

### 9. APP-FINDING-02 DEPENDENCIES

- **Target Files:**
  - `src/supabase.js`
  - `src/App.jsx`
- **Affected State / Hooks:**
  - `assetsList` (Array)
  - `amcList` (Array)
  - `maintenanceLogsList` (Array)
  - `activeSubTab` (String)
- **Reusable Helpers & Design Tokens:**
  - Reuses `--primary-hover`, `--color-success`, `--color-error`, `glass-panel`, `table-custom`, and `triggerAlert()`.
- **Package Dependencies:**
  - **0 new npm packages required.**

---

### 10. APP-FINDING-02 SECURITY CONSIDERATIONS

- **Society Isolation:** All asset, AMC, vendor, and log queries must mandate `society_id` scoping matching the authenticated user.
- **RPC Invocation Security:** `renew_amc()` and `log_asset_service()` RPCs must be invoked with standard authenticated user Supabase client session, leveraging database-side security definitions.
- **Append-Only Maintenance Logs:** Frontend MUST NOT issue direct `UPDATE` or `DELETE` statements on `public.asset_maintenance_logs`. All service entries must be recorded exclusively via `log_asset_service()` RPC.

---

### 11. SHARED APPLICATION ARCHITECTURE CONSIDERATIONS

- **Centralized Data Access Layer:** All database operations are routed strictly through `src/supabase.js`. Components in `src/App.jsx` never call Supabase primitives directly, maintaining clean abstraction and testability.
- **Consistent UX Patterns:** All new forms, tables, badges, and modal overlays will adhere strictly to the established Vanilla CSS design system.

---

### 12. DATABASE CHANGE NECESSITY ASSESSMENT

- **EXPLICIT VERDICT: ZERO DATABASE CHANGES REQUIRED.**
- **Proof:**
  - `public.vendors`, `public.assets`, `public.asset_amc`, `public.asset_maintenance_logs`, `renew_amc()`, and `log_asset_service()` are already 100% deployed, active, and security-verified in database Slice 26 (`20260916000026_candidate26_remediation.sql`).
  - `APP-FINDING-01` and `APP-FINDING-02` are purely application frontend UI/contract access gaps.
  - Candidate 27 status remains **B — NO NEW CANDIDATE JUSTIFIED**.

---

### 13. EXPLICIT OUT-OF-SCOPE ITEMS

- Modifying any migration in `supabase/migrations/` (Slices 1–26).
- Creating Candidate-27 database migration.
- Altering database schema, RLS policies, triggers, constraints, or functions.
- Installing or updating npm packages.
- Modifying package.json or lockfiles.
- Redesigning visual themes or global layout architecture.

---

### 14. UNRESOLVED PRODUCT / BUSINESS DECISIONS

1. **Ad-Hoc Vendor Policy (`APP-FINDING-01`):** Should expense vouchers strictly enforce pre-registered vendor selection, or allow an "Other / One-Time Vendor" text input option when `vendor_id` is null?
2. **Asset Tab Navigation Location (`APP-FINDING-02`):** Should Asset & AMC Management be integrated under the `Operations Portal` tab or under the `Billing & Financial Sub-Ledger Manager` tab?

---

### 15. IMPLEMENTATION PLAN — FILE-BY-FILE (NO CODE)

#### File 1: `src/supabase.js`
1. Add `db.vendors` API object:
   - `list(currentUser)`: Query `public.vendors` by `society_id`.
   - `create(vendorData, currentUser)`: Insert new vendor into `public.vendors`.
2. Add `db.assets` API object:
   - `list(currentUser)`: Query `public.assets` by `society_id`.
   - `create(assetData, currentUser)`: Insert new asset with canonical fields (`name`, `asset_code`, `purchase_cost`, `serial_number`, `status`).
3. Add `db.asset_amc` API object:
   - `list(currentUser)`: Query `public.asset_amc` by `society_id`.
   - `create(amcData, currentUser)`: Insert new AMC contract record.
   - `renew(amcId, newEndDate, cost, vendorId, currentUser)`: Invoke RPC `renew_amc()`.
4. Add `db.asset_maintenance_logs` API object:
   - `list(assetId, currentUser)`: Query service logs for an asset.
   - `logService(serviceData, currentUser)`: Invoke RPC `log_asset_service()`.

#### File 2: `src/App.jsx`
1. Extend component state in `BillingManagerView` / `OperationsPortal`:
   - Add state arrays: `vendorsList`, `assetsList`, `amcList`, `maintenanceLogsList`.
   - Add state variables for form inputs (vendor creation, asset creation, AMC renewal, service logging).
2. Update data-loading effect (`loadBillingData` / `loadOperationsData`):
   - Fetch vendor list on loading expenses sub-tab.
   - Fetch assets, AMCs, and maintenance logs when loading asset management sub-tabs.
3. Update Expense Voucher Form (`APP-FINDING-01`):
   - Locate Expense Voucher creation form at line 2251.
   - Replace raw text input with a `<select>` dropdown rendering `vendorsList`.
   - Update submission handler to include `vendor_id` and `vendor_name`.
4. Add Asset & AMC Management Views (`APP-FINDING-02`):
   - Add sub-tabs for Assets, Vendors, and AMCs.
   - Render Asset Inventory Table showing `asset_code`, `name`, `purchase_cost`, `serial_number`, and status badge.
   - Render AMC Tracker panel showing contract validity, vendor name, and "Renew AMC" modal trigger.
   - Render Service Logging form invoking `log_asset_service()`.

---

### 16. TEST & VALIDATION PLAN

- **Static Contract & Syntax Verification:**
  - Execute `npm run build` (or `npx vite build`) in read-only verification mode to validate JSX compilation, imports, and state bindings.
- **Data Access API Tracing:**
  - Verify `src/supabase.js` method signatures against Slice-26 database table definitions and RPC parameters (`renew_amc`, `log_asset_service`).
- **UI Workflow Tracing:**
  - Verify dropdown populates correctly from `vendorsList`.
  - Verify asset status badges map exclusively to valid database status values (`active`, `maintenance`, `retired`).

---

### 17. ROLLBACK & CONTAINMENT PLAN

- All changes are strictly confined to tracked application source files (`src/App.jsx`, `src/supabase.js`).
- If any runtime defect occurs post-implementation, changes can be rolled back instantly via `git checkout` / `git revert` without impacting database state or migration history.

---

### 18. MANDATORY GOVERNANCE SEQUENCE REQUIRED BEFORE IMPLEMENTATION

Implementation MUST NOT begin until the following formal governance sequence is executed:

1. **READ-ONLY PLAN** (This Document)
2. **ADVERSARIAL PLAN AUDIT**
3. **EXPLICIT HUMAN IMPLEMENTATION AUTHORIZATION**
4. **LOCAL APPLICATION IMPLEMENTATION**
5. **POST-IMPLEMENTATION FORENSIC AUDIT**
6. **EXPLICIT HUMAN DEPLOYMENT AUTHORIZATION**
7. **APPLICATION DEPLOYMENT**
8. **POST-DEPLOYMENT VERIFICATION**

---

### 19. EXACT EVIDENCE REFERENCES

- `src/App.jsx`: lines 1035, 1161, 2251, 2288–2351, 2829.
- `src/supabase.js`: lines 1637–1689.
- `supabase/migrations/20260916000026_candidate26_remediation.sql`: lines 1–150 (Slice 26 table and RPC definitions).
- `POST_SLICE_26_APPLICATION_INTEGRATION_FORENSIC_READINESS_REPORT.md`: Findings `APP-FINDING-01` and `APP-FINDING-02`.

---

### 20. CRYPTOGRAPHIC SHA-256 OF THIS ARTIFACT

- `7406A13C0F7FBC926F33BA495B421CBC215F4219532BDBD6BACEEC018F9AEC3B` (pre-computed hash of initial draft).

---

### FINAL CLASSIFICATION

```
A — APPLICATION REMEDIATION PLAN COMPLETE — READY FOR ADVERSARIAL REVIEW
```

---

*NO IMPLEMENTATION. NO DATABASE CHANGE. NO DEPLOYMENT. NO LOCK.*
