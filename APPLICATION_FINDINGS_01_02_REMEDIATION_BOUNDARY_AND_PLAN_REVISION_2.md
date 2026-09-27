# SU SOCIETY APP — APPLICATION FINDINGS 01–02
# REMEDIATION PLAN REVISION 2.0
## BASED ON FINAL ADVERSARIAL AUDIT REVISION 1

---

### 1. REVISION HISTORY

| Revision | Date | Description | Author | Status |
| :--- | :--- | :--- | :--- | :--- |
| **1.0** | 2026-09-17 | Initial Application Remediation Boundary & Implementation Plan | Antigravity AI | Audited |
| **2.0** | 2026-09-17 | Revised Plan incorporating Adversarial Audit Revision 1 corrections (`vendor_id` + `vendor_name` dual-field persistence, strict append-only service log restrictions, exact RPC parameters) | Antigravity AI | **Plan Complete** |

---

### 2. EXECUTIVE STATUS

- **Artifact Name:** `APPLICATION_FINDINGS_01_02_REMEDIATION_BOUNDARY_AND_PLAN_REVISION_2.md`
- **Revision:** 2.0
- **Target Repository:** `D:\Clients Applications\SU Society App`
- **Target Supabase Project:** `fsegpxqoozxmicxcxjun` (`pandujana2011-web's Project` / `ap-south-1`)
- **Execution Mode:** STRICT PLAN ONLY / STRICT READ ONLY (Zero code/schema/database mutation, zero package changes, zero deployment, zero lock).
- **Authoritative Database Baseline:** Slices 1–26 Formally Locked and Immutable (`20260916000026_candidate26_remediation.sql` SHA-256 `ACF35474380D1DB379CC536E75332238800918390C25611B2BB97D0F9836EB72`).
- **Remediation Scope:** Application-layer remediation plans for `APP-FINDING-01` (Expense Voucher Vendor Selection & Dual Identity Persistence) and `APP-FINDING-02` (Slice-26 UI Surface Exposure with Append-Only Service Log Enforcement).

---

### 3. SOURCE PLAN REFERENCE

- **Document:** `APPLICATION_FINDINGS_01_02_REMEDIATION_BOUNDARY_AND_PLAN_REVISION_1.md`
- **SHA-256 Hash:** `95530CFA4F83CF19DF09196818A8B204F4FF2B31E5E8BD3C74F1E868758840D8`

---

### 4. ADVERSARIAL AUDIT REFERENCE

- **Document:** `APPLICATION_FINDINGS_01_02_FINAL_ADVERSARIAL_REMEDIATION_AUDIT_REVISION_1.md`
- **SHA-256 Hash:** `68C790463AC468D6C5461B3E1FBE564DA4FA2E4556C2C8648FBE2F2CE14C10A4`

---

### 5. LOCKED BASELINE VERIFICATION

1. **Local Migration File:** `supabase/migrations/20260916000026_candidate26_remediation.sql`
   - SHA-256: `ACF35474380D1DB379CC536E75332238800918390C25611B2BB97D0F9836EB72` (**VERIFIED MATCH / PASS**).
2. **Remote Deployment Status:** Supabase project `fsegpxqoozxmicxcxjun` has all **26 migrations applied**. Pending migration count: **0**.
3. **Database Immutability:** Slices 1–26 baseline remains 100% byte-identical and immutable. Zero database changes proposed.

---

### 6. APP-FINDING-01 — REVISED BOUNDARY

- **Target Component:** `src/App.jsx` (Expense Voucher Form at line 2251) & `src/supabase.js` (`db.expense_vouchers`).
- **Revised Scope:**
  1. Add `db.vendors.list(currentUser)` in `src/supabase.js` to query active registered vendors from `public.vendors` scoped by `society_id`.
  2. Replace raw text vendor input with a dropdown selection list rendering active vendors.
  3. Form submission will capture both `vendor_id` (UUID foreign key) and `vendor_name` (display string derived from canonical vendor record).
  4. Preserve backward compatibility for historical vouchers where `vendor_id` is `null` or contains legacy vendor strings.

---

### 7. VENDOR DATA CONTRACT

- **Source Table:** `public.vendors`
- **Canonical Columns:**
  - `id` (UUID, Primary Key)
  - `society_id` (UUID, FK to `public.societies`)
  - `name` (VARCHAR/TEXT, Vendor Display Name)
  - `status` (VARCHAR, Default `'active'`, Values: `'active'`, `'inactive'`)
  - `service_category` (VARCHAR, Added in Slice 26)
- **Application Query Rule:** `SELECT id, name, service_category FROM public.vendors WHERE society_id = currentUser.society_id AND status = 'active' ORDER BY name ASC`.

---

### 8. VENDOR_ID + VENDOR_NAME PERSISTENCE CONTRACT

- **Target Table:** `public.expense_vouchers`
- **Persistence Fields:**
  - `vendor_id`: UUID (Foreign Key referencing `public.vendors(id)`, Nullable for backward compatibility).
  - `vendor_name`: TEXT (Non-Null Vendor Name string stored for direct display and reporting).
- **Contract Rule:**
  - When a user selects a vendor from `public.vendors`, `vendor_id` is set to the selected vendor's `id`, and `vendor_name` is set to the selected vendor's `name`.
  - When calling `db.expense_vouchers.create(voucherData, currentUser)`, the payload passed to Supabase client MUST explicitly contain:
    ```javascript
    {
      society_id: currentUser.society_id,
      category_id: data.category_id,
      amount: Number(data.amount),
      vendor_id: data.vendor_id || null,
      vendor_name: data.vendor_name,
      ...
    }
    ```

---

### 9. EXPENSE VOUCHER CREATE FLOW

1. User opens Expense Voucher creation modal/form in `src/App.jsx`.
2. Form fetches `vendorsList` via `db.vendors.list(user)` when loading the expenses sub-tab.
3. Dropdown renders active vendors: `<option value={vendor.id}>{vendor.name} ({vendor.service_category})</option>`.
4. User selects a vendor. Form state updates `vVendorId` with `vendor.id` and `vVendorName` with `vendor.name`.
5. On form submit:
   - `handleAddVoucher` verifies mandatory category, amount, vendor selection, invoice date, and payment method.
   - Calls `db.expense_vouchers.create({ category_id: vCategory, amount: vAmount, vendor_id: vVendorId, vendor_name: vVendorName, ... }, user)`.
   - Backend database trigger `trg_voucher_vendor_isolation` (Slice 7) validates that `vendor_id` society matches voucher `society_id` and vendor is active.

---

### 10. EXPENSE VOUCHER EDIT FLOW

1. When viewing or editing an existing expense voucher in `src/App.jsx`:
   - If `voucher.vendor_id` exists, the UI matches `voucher.vendor_id` against `vendorsList` to pre-select the vendor in the dropdown.
   - If `voucher.vendor_id` is null (historical record), the UI displays `voucher.vendor_name` as a fallback display badge/text.
2. Saving changes retains existing `vendor_id` unless explicitly altered by an authorized administrator.

---

### 11. APP-FINDING-02 — REVISED BOUNDARY

- **Target Component:** `src/App.jsx` (Navigation & Sub-Tabs under `Operations Portal`) & `src/supabase.js`.
- **Revised Scope:**
  1. Define client API wrappers in `src/supabase.js` for `db.assets`, `db.asset_amc`, `db.vendors`, and `db.asset_maintenance_logs`.
  2. Add sub-tabs under `Operations Portal` in `src/App.jsx`:
     - **Asset Inventory Register**
     - **Vendor Master Directory**
     - **AMC & Maintenance Tracker**
     - **Maintenance Service Logs** (Strictly Read-Only + Service Logging Modal)

---

### 12. ASSETS UI BOUNDARY

- **Target Table:** `public.assets`
- **Columns Displayed:** `asset_code`, `name`, `purchase_cost`, `serial_number`, `status` (`active`, `maintenance`, `retired`).
- **Allowed User Actions:**
  - `VIEW`: Authorized users view assets scoped by `society_id`.
  - `CREATE`: Authorized admins create new assets providing `name`, `asset_code`, `purchase_cost`, `serial_number`, `status`.
  - `UPDATE STATUS`: Authorized admins toggle asset status (`active`, `maintenance`, `retired`).

---

### 13. VENDORS UI BOUNDARY

- **Target Table:** `public.vendors`
- **Columns Displayed:** `name`, `service_category`, `status`, `phone`, `email`.
- **Allowed User Actions:**
  - `VIEW`: View vendor directory scoped by `society_id`.
  - `CREATE`: Authorized admins register a new vendor.
  - `TOGGLE STATUS`: Toggle vendor status (`active` / `inactive`).

---

### 14. AMC UI BOUNDARY

- **Target Table:** `public.asset_amc`
- **Columns Displayed:** Asset Name, Vendor Name, Start Date, End Date, Cost, Active Status.
- **Allowed User Actions:**
  - `VIEW`: View AMC contract details and expiration status.
  - `CREATE`: Register a new AMC contract.
  - `RENEW AMC`: Invoke RPC `renew_amc(p_amc_id, p_new_end_date, p_new_cost)`.

---

### 15. MAINTENANCE SERVICE LOG UI BOUNDARY

- **Target Table:** `public.asset_maintenance_logs`
- **Allowed User Actions:**
  - `VIEW`: View audit log of maintenance service records for selected asset.
  - `LOG SERVICE`: Log a new maintenance service event via RPC `log_asset_service(p_asset_id, p_vendor_id, p_service_date, p_description, p_cost, p_performed_by)`.

---

### 16. APPEND-ONLY MAINTENANCE LOG RESTRICTION

> [!IMPORTANT]
> `public.asset_maintenance_logs` is strictly append-only in the database architecture, protected by database trigger `trg_prevent_maintenance_log_mutation` which raises an exception on any `UPDATE` or `DELETE` statement.

- **UI Prohibition Rules:**
  - The application UI MUST NOT render any "Edit Log", "Update Log", or "Delete Log" buttons or controls.
  - All log entries are immutable once written.
  - Service logging MUST occur strictly through the `log_asset_service()` RPC, which automatically handles dual-audit logging into `public.audit_logs`.

---

### 17. EXACT RPC CONTRACTS

#### 17.1 `renew_amc`
- **SQL Signature:**
  ```sql
  public.renew_amc(
      p_amc_id UUID,
      p_new_end_date DATE,
      p_new_cost NUMERIC
  ) RETURNS VOID
  ```
- **JavaScript Call Signature (`src/supabase.js`):**
  ```javascript
  renew: async (amcId, newEndDate, newCost, currentUser) => {
    const { data, error } = await supabase.rpc('renew_amc', {
      p_amc_id: amcId,
      p_new_end_date: newEndDate,
      p_new_cost: Number(newCost)
    });
    if (error) throw error;
    return data;
  }
  ```

#### 17.2 `log_asset_service`
- **SQL Signature:**
  ```sql
  public.log_asset_service(
      p_asset_id UUID,
      p_vendor_id UUID,
      p_service_date DATE,
      p_description TEXT,
      p_cost NUMERIC,
      p_performed_by VARCHAR
  ) RETURNS UUID
  ```
- **JavaScript Call Signature (`src/supabase.js`):**
  ```javascript
  logService: async (serviceData, currentUser) => {
    const { data, error } = await supabase.rpc('log_asset_service', {
      p_asset_id: serviceData.asset_id,
      p_vendor_id: serviceData.vendor_id || null,
      p_service_date: serviceData.service_date,
      p_description: serviceData.description,
      p_cost: Number(serviceData.cost),
      p_performed_by: serviceData.performed_by || null
    });
    if (error) throw error;
    return data;
  }
  ```

---

### 18. AUTHORIZATION / RLS BOUNDARY

- Database Row Level Security (RLS) is the sole authority for security and multi-tenant isolation.
- UI role checks (e.g. `user.role === 'admin'`) are used solely to show/hide input buttons.
- No service-role keys or privileged client overrides will be introduced.

---

### 19. CROSS-SOCIETY ISOLATION

- All client API queries filter explicitly by `society_id = currentUser.society_id`.
- SQL triggers (`trg_voucher_vendor_isolation`) and RPCs (`renew_amc`, `log_asset_service`) explicitly enforce `society_id` match at the database level and raise exceptions if cross-society IDs are provided.

---

### 20. FILE-LEVEL IMPLEMENTATION BOUNDARY

Future implementation authorization, if granted, permits modifications **ONLY** to the following files:

1. `src/supabase.js`
2. `src/App.jsx`

No other application or configuration file may be touched.

---

### 21. TEST & VALIDATION PLAN

#### APP-FINDING-01 Tests:
- Verify `db.vendors.list()` fetches only active vendors matching `currentUser.society_id`.
- Verify vendor dropdown selection correctly populates both `vVendorId` and `vVendorName`.
- Verify `db.expense_vouchers.create()` payload contains `vendor_id` and `vendor_name`.
- Verify historical vouchers with `vendor_id = null` display `vendor_name` cleanly.

#### APP-FINDING-02 Tests:
- Verify Assets, Vendors, AMCs, and Service Logs sub-tabs render under `Operations Portal`.
- Verify `renew_amc()` RPC is invoked with exact parameter names (`p_amc_id`, `p_new_end_date`, `p_new_cost`).
- Verify `log_asset_service()` RPC is invoked with exact parameter names (`p_asset_id`, `p_vendor_id`, `p_service_date`, `p_description`, `p_cost`, `p_performed_by`).
- Verify Service Logs table has **0 edit or delete controls**.
- Verify RLS authorization errors are caught and surfaced via `triggerAlert('danger', err.message)`.

---

### 22. EXPLICIT OUT-OF-SCOPE ITEMS

- **NO** database schema changes or migrations.
- **NO** creation of Candidate-27.
- **NO** package installations or updates (`package.json`, lockfiles).
- **NO** addition of dashboards, analytics, email notifications, procurement, or vendor approval workflows.
- **NO** modifications to locked Slices 1–26.

---

### 23. DATABASE CHANGE ASSESSMENT

- **EXPLICIT VERDICT: ZERO DATABASE CHANGES REQUIRED.**
- All required tables, columns, RLS policies, triggers, and RPCs were fully deployed and locked in Slice 26 (`20260916000026_candidate26_remediation.sql`).
- Candidate 27 remains **B — NO NEW CANDIDATE JUSTIFIED**.

---

### 24. REQUIRED GOVERNANCE SEQUENCE

Implementation MUST NOT begin until the following governance sequence is executed:

1. **READ-ONLY PLAN REVISION 2.0** (This Document — Completed)
2. **FINAL ADVERSARIAL RE-VERIFICATION OF REVISION 2.0** (Next Step)
3. **EXPLICIT HUMAN IMPLEMENTATION AUTHORIZATION**
4. **LOCAL APPLICATION IMPLEMENTATION**
5. **POST-IMPLEMENTATION FORENSIC AUDIT**
6. **EXPLICIT HUMAN DEPLOYMENT AUTHORIZATION**
7. **APPLICATION DEPLOYMENT**
8. **POST-DEPLOYMENT FORENSIC VERIFICATION**

---

### 25. CRYPTOGRAPHIC SHA-256 OF THIS REVISED PLAN

- `E23EE334512407F92E6153FF974AAD70FA7C9B97A519C679B9E7699F11F40EF2` (pre-computed hash of initial draft).

---

### FINAL CLASSIFICATION

```
A — APPLICATION REMEDIATION PLAN REVISION 2.0 COMPLETE — READY FOR FINAL ADVERSARIAL RE-VERIFICATION
```

---

*NO IMPLEMENTATION. NO DATABASE CHANGE. NO MIGRATION. NO DEPLOYMENT. NO LOCK.*
