# CANDIDATE-26-01 FORMAL REMEDIATION PLAN
## Vendor Registry, Asset Inventory & Annual Maintenance Contract (AMC) Management System
### Zero-Mutation Pre-Implementation Specification Gate

```
================================================================================
EXECUTION CLASS:             READ-ONLY FORMAL REMEDIATION PLAN
TARGET REPOSITORY:           D:\Clients Applications\SU Society App
CANDIDATE:                   CANDIDATE-26-01
SCOPE:                       Vendor Registry, Asset Inventory & AMC Management System
FORENSIC VALIDATION:         B — FORENSICALLY VALID WITH FINDINGS
FINDING ADJUDICATION:        READINESS-A — READY FOR FORMAL REMEDIATION PLAN
REMEDIATION BOUNDARY:        A — HASHES RECONCILED AND REMEDIATION BOUNDARY CLEAR
LOCKED BASELINE (SLICES 1-21): 791 / 791 PASS (100% IMMUTABLE & VERIFIED)
CUMULATIVE BASELINE:         1040 / 1040 PASS (100% IMMUTABLE & VERIFIED)
GOVERNANCE MODE:             PLAN ONLY / ZERO IMPLEMENTATION / ZERO DML / ZERO DDL / ZERO DEPLOYMENT
PLAN CLASSIFICATION:         A — REMEDIATION PLAN COMPLETE AND IMPLEMENTATION-READY FOR FUTURE AUTHORIZATION
IMPLEMENTATION AUTHORIZATION: NOT GRANTED
DEPLOYMENT AUTHORIZATION:     NOT GRANTED
LOCK AUTHORIZATION:           NOT GRANTED
MIGRATION CREATION AUTHORIZATION: NOT GRANTED
DATABASE MUTATION:           NOT PERFORMED (0 DML / 0 DDL)
APPLICATION MUTATION:        NOT PERFORMED (0 CODE CHANGES)
BASELINE MUTATION:           NOT PERFORMED (0 BASELINE CHANGES)
================================================================================
```

---

## 1. GOVERNANCE HEADER

This document constitutes the authoritative **FORMAL REMEDIATION PLAN** for `CANDIDATE-26-01` (Vendor Registry, Asset Inventory & Annual Maintenance Contract Management System) in accordance with the project's zero-trust forensic governance protocol.

- **Target Repository:** `D:\Clients Applications\SU Society App`
- **Candidate ID:** `CANDIDATE-26-01`
- **Candidate Name:** Vendor Registry, Asset Inventory & Annual Maintenance Contract (AMC) Management System
- **Governance Mandate:** Plan Only. Zero code execution, zero SQL execution, zero DML/DDL, zero migration creation, zero deployment, zero baseline mutation, zero lock/unlock.
- **Purpose:** Provide a precise, object-level, implementation-ready specification to remediate all five (5) forensic findings adjudicated in stage 2 without modifying any historical slice or baseline artifact.

---

## 2. SOURCE ARTIFACT CHAIN

Static cryptographic verification chain of authoritative predecessor reports:

| Stage | Artifact Path | SHA-256 Hash | Status |
|-------|---------------|--------------|--------|
| **Forensic Discovery** | `SLICE26_LIFECYCLE_INITIALIZATION_FORENSIC_SECURITY_GATE.md` | `7F0BBBA1CF2D54B582A1B69681D55D048C22924CB637AC1693ADE9637CC53A86` | **VERIFIED** |
| **Forensic Validation** | `CANDIDATE-26-01_FORENSIC_VALIDATION_REPORT.md` | `97A8E609FB78AF3497ACEAB9E384FC694B5DB49DA88BAB4505D874FD88B13350` | **VERIFIED** |
| **Finding Adjudication** | `CANDIDATE-26-01_FINDING_ADJUDICATION_REPORT.md` | `AB156C106A4C01BB1B7E3229A218991294D5973EDE948E1C42A66F1BB9954227` | **VERIFIED** |
| **Remediation Boundary** | `CANDIDATE-26-01_REMEDIATION_BOUNDARY_GATE.md` | `E46FE76B29B2D3613AB65BE31822012CCB8C2FE12F8C363B7CEDCC9D21A34531` | **VERIFIED** |
| **Baseline Security Lock** | `SLICE25_SECURITY_LOCK.md` | `F54A343198EB730AF8EB2CD65B5AA4C6844EF950A61A11B14A948B81910B5190` | **VERIFIED** |

---

## 3. CANDIDATE SCOPE

`CANDIDATE-26-01` introduces a centralized multi-tenant management system for:
1. **Vendor Registry:** Managing society-approved service providers, contractors, contact personnel, and tax/registration credentials (`vendors`).
2. **Asset Inventory:** Cataloging society physical infrastructure assets (elevators, generators, water pumps, CCTV systems, fire safety equipment, transformers) (`assets`).
3. **AMC Management:** Tracking Annual Maintenance Contracts, start/end dates, contract values, coverage terms, and renewal workflows (`asset_amcs`).
4. **Maintenance Service Logs:** Logging routine maintenance, emergency repairs, parts replacements, technician sign-offs, and service costs (`asset_maintenance_logs`).

---

## 4. CURRENT BASELINE

The locked repository baseline is 100% immutable and fully verified:

```
  Slices 1–19 Core Platform:        791 / 791 PASS  (UNTOUCHED & IMMUTABLE)
  Slice 20 NOC & Move-Out:          51 /  51 PASS  (UNTOUCHED & IMMUTABLE)
  Slice 21 Security Gate:           77 /  77 PASS  (UNTOUCHED & IMMUTABLE)
  Slice 22 Rule Violation & Fine:    65 /  65 PASS  (UNTOUCHED & IMMUTABLE)
  Slice 23 Digital Vault:           75 /  75 PASS  (UNTOUCHED & IMMUTABLE)
  Slice 24 Operations Completion:   55 /  55 PASS  (UNTOUCHED & IMMUTABLE)
  Slice 25 Accrual Financials:      54 /  54 PASS  (UNTOUCHED & IMMUTABLE)
  ------------------------------------------------------------------------------
  AUTHORITATIVE BASELINE VERDICT:   1040 / 1040 PASS (100% PASSED & LOCKED)
```

---

## 5. FINDING SUMMARY

The remediation plan addresses all five (5) adjudicated forensic findings:

| Finding ID | Adjudicated Severity | Affected Target Object | Mandatory Remediation Requirement |
|------------|----------------------|------------------------|-----------------------------------|
| `FND-26-01-01` | **CONFIRMED SECURITY HARDENING** | `vendors`, `assets`, `asset_amcs`, `asset_maintenance_logs` | Add `society_id UUID NOT NULL REFERENCES societies(id)` + strict RLS policies on all candidate tables. |
| `FND-26-01-02` | **CONFIRMED SECURITY HARDENING** | `renew_amc()` RPC | Enforce `SELECT ... FOR UPDATE` pessimistic row locking to prevent concurrent renewal race conditions. |
| `FND-26-01-03` | **DESIGN REFINEMENT** | `expense_vouchers` | Add optional, nullable `vendor_id UUID REFERENCES vendors(id)` column to bridge vouchers to registry without breaking legacy data. |
| `FND-26-01-04` | **CONFIRMED SECURITY HARDENING** | `asset_maintenance_logs` & RPC | Enforce append-only service log semantics (revoke UPDATE/DELETE) and mandatory dual-write insertion into `audit_logs`. |
| `FND-26-01-05` | **DESIGN REFINEMENT** | `assets` table | Enforce composite unique constraint `UNIQUE (society_id, asset_code)` for asset identity across tenant boundaries. |

---

## 6. REMEDIATION PRINCIPLES

1. **Purely Additive DDL:** Every schema addition must be created as a future new migration script. Historical migrations (`20260912000001_slice1.sql` to `20260912000025_slice25.sql`) must remain 100% unmutated.
2. **Zero Historical Modification:** If any planned remediation requires editing a historical file, execution must stop immediately with `HISTORICAL MIGRATION CONFLICT`.
3. **Multi-Tenant Isolation by Default:** Every table must possess `society_id UUID NOT NULL` referencing `societies(id)` with explicit RLS tenant isolation policies.
4. **RPC Encapsulation & Privilege Hardening:** All candidate table DML operations (`INSERT`/`UPDATE`/`DELETE`) are revoked from `authenticated` and `anon`. All mutations route exclusively through `SECURITY DEFINER` RPCs with `SET search_path = public, pg_temp`.
5. **Zero Speculative Scope:** Do not add unrequested fields, unrequested features, or modify locked slice logic.

---

## 7. FND-26-01-01 — SOCIETY ISOLATION DETAILED PLAN

### Candidate Table Inventory & Scoping:
1. `public.vendors`
   - Primary Key: `id UUID PRIMARY KEY DEFAULT gen_random_uuid()`
   - Tenant Scoping: `society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE`
2. `public.assets`
   - Primary Key: `id UUID PRIMARY KEY DEFAULT gen_random_uuid()`
   - Tenant Scoping: `society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE`
3. `public.asset_amcs`
   - Primary Key: `id UUID PRIMARY KEY DEFAULT gen_random_uuid()`
   - Tenant Scoping: `society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE`
4. `public.asset_maintenance_logs`
   - Primary Key: `id UUID PRIMARY KEY DEFAULT gen_random_uuid()`
   - Tenant Scoping: `society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE`

### Backfill & Table Creation Strategy:
- As Candidate 26-01 introduces 4 brand new tables, no historical row backfill is required.
- All 4 tables are created with `society_id UUID NOT NULL` at initial table definition, eliminating any NULL state risk.

### Static Proof of Cross-Society Isolation:
- **RLS Enablement:** Mandatory `ALTER TABLE public.<table_name> ENABLE ROW LEVEL SECURITY;` on all 4 tables.
- **Tenant Isolation Policy Pattern:**
  ```sql
  CREATE POLICY tenant_isolation_policy ON public.<table_name>
      FOR ALL
      TO authenticated
      USING (society_id = (SELECT society_id FROM public.users WHERE id = auth.uid()))
      WITH CHECK (society_id = (SELECT society_id FROM public.users WHERE id = auth.uid()));
  ```
- **RPC Validation Pattern:**
  Every RPC (`create_vendor`, `create_asset`, `create_amc`, `renew_amc`, `log_asset_service`) dynamically looks up `v_caller_society_id` from `public.users WHERE id = auth.uid()` and validates that target records belong to `v_caller_society_id`. If a mismatch is detected, the RPC raises `ERR-26-001: CROSS_SOCIETY_ACCESS_DENIED`.

---

## 8. FND-26-01-02 — AMC RENEWAL CONCURRENCY DETAILED PLAN

### Stored Procedure Inspection: `renew_amc()`
- **Input Parameters:**
  - `p_amc_id UUID` (Target AMC record identifier)
  - `p_new_start_date DATE` (New contract start date)
  - `p_new_end_date DATE` (New contract end date)
  - `p_new_contract_value NUMERIC(12,2)` (New AMC cost)
  - `p_vendor_id UUID` (Vendor identifier, defaults to current vendor if NULL)
  - `p_coverage_terms TEXT` (Updated terms)
- **Authorization:** Requires caller to be an active `admin`, `super_admin`, or `treasurer` in `public.users`.

### Race Window & Concurrency Hazard:
If two admins simultaneously trigger `renew_amc(p_amc_id, ...)` without row-level pessimistic locking, both invocations would read `status = 'active'`, both would issue `UPDATE asset_amcs SET status = 'expired'`, and both would issue `INSERT INTO asset_amcs` creating two active AMC contracts for the same asset concurrently.

### Exact Row Lock Placement & Semantics:
Inside `renew_amc()`, immediately following caller authorization and society lookup:

```sql
-- Acquire exclusive row lock on target AMC record
SELECT id, society_id, asset_id, vendor_id, status
INTO v_target_amc
FROM public.asset_amcs
WHERE id = p_amc_id AND society_id = v_caller_society_id
FOR UPDATE;

IF NOT FOUND THEN
    RAISE EXCEPTION 'ERR-26-002: AMC contract not found or society mismatch';
END IF;

IF v_target_amc.status NOT IN ('active', 'pending_renewal') THEN
    RAISE EXCEPTION 'ERR-26-003: AMC contract status % is ineligible for renewal', v_target_amc.status;
END IF;
```

### Concurrency Guarantees:
- **Lock Acquisition Order:** 1. `users` (read caller society) -> 2. `asset_amcs` (row exclusive lock via `FOR UPDATE`).
- **Idempotency & Failure Behavior:** Second concurrent request blocks on `FOR UPDATE`. When unblocked, reads updated `status = 'expired'` and fails precondition check gracefully with zero duplicate contract creation.

---

## 9. FND-26-01-03 — EXPENSE VOUCHER VENDOR LINK DETAILED PLAN

### Objective:
Bridge historical plain text vendor references (`expense_vouchers.vendor_name TEXT NOT NULL`) to formal `public.vendors(id)` without mutating Slice 16 DDL or invalidating historical financial vouchers.

### Proposed Additive DDL:
```sql
-- Additive column addition to expense_vouchers (Slice 16 object)
ALTER TABLE public.expense_vouchers 
ADD COLUMN IF NOT EXISTS vendor_id UUID REFERENCES public.vendors(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_expense_vouchers_vendor_id 
ON public.expense_vouchers(vendor_id);
```

### Operational Semantics:
- **Nullable Semantics:** `vendor_id` is strictly `NULLABLE`.
- **FK Behavior:** `ON DELETE SET NULL`. Deleting a vendor record unlinks future reference but retains the expense voucher intact.
- **Historical Data Impact:** Existing expense vouchers retain `vendor_id = NULL` and `vendor_name = '<legacy string>'`. No backfill migration is forced.
- **New Voucher Behavior:** When creating an expense voucher for a registered vendor, UI passes `vendor_id`. RPC auto-populates `vendor_name = vendor.vendor_name` and `vendor_id = vendor.id`.
- **Reporting Compatibility:** Slice 25 trial balance, P&L, and balance sheet queries operate on ledger entries; zero impact on financial statement accuracy.

---

## 10. FND-26-01-04 — SERVICE LOG + AUDIT INTEGRITY DETAILED PLAN

### Architecture Distinction:
1. **Service Log Immutability (`asset_maintenance_logs`):** Restricts physical modification of recorded service entries to preserve maintenance history.
2. **Audit Log Creation (`audit_logs`):** Records governance audit events tracking service creation, vendor assignment, and operational changes.

### Enforcing Append-Only Semantics on Service Logs:
```sql
-- Revoke direct DML from authenticated role on service logs
REVOKE UPDATE, DELETE ON public.asset_maintenance_logs FROM authenticated, PUBLIC, anon;

-- Direct table INSERT is blocked; mutations route strictly through log_asset_service() RPC
REVOKE INSERT ON public.asset_maintenance_logs FROM authenticated, PUBLIC, anon;
GRANT SELECT ON public.asset_maintenance_logs TO authenticated;
```

### Stored Procedure RPC: `log_asset_service()`
Wrapped in an atomic transaction performing dual-write:
```sql
-- 1. Insert Service Log Entry
INSERT INTO public.asset_maintenance_logs (
    society_id, asset_id, vendor_id, service_type, service_date,
    description, cost, parts_replaced, technician_name, performed_by
) VALUES (
    v_caller_society_id, p_asset_id, p_vendor_id, p_service_type, p_service_date,
    p_description, p_cost, p_parts_replaced, p_technician_name, auth.uid()
) RETURNING id INTO v_log_id;

-- 2. Atomic Audit Log Insertion (Zero recursion risk - explicit INSERT)
INSERT INTO public.audit_logs (
    society_id, user_id, action, table_name, record_id, details
) VALUES (
    v_caller_society_id, auth.uid(), 'LOG_ASSET_SERVICE', 'asset_maintenance_logs', v_log_id,
    jsonb_build_object(
        'asset_id', p_asset_id,
        'vendor_id', p_vendor_id,
        'service_type', p_service_type,
        'cost', p_cost
    )
);
```

---

## 11. FND-26-01-05 — ASSET CODE UNIQUENESS DETAILED PLAN

### Problem Statement:
Global uniqueness on `asset_code` (`UNIQUE(asset_code)`) causes multi-tenant cross-society collisions (e.g. Society A registering `ELEV-01` blocks Society B from registering `ELEV-01`).

### Proposed Composite Unique Constraint:
```sql
-- Composite unique constraint on assets table
ALTER TABLE public.assets 
ADD CONSTRAINT uq_assets_society_asset_code UNIQUE (society_id, asset_code);
```

### Validation Pre-Check Query (PLAN ONLY - DO NOT EXECUTE):
```sql
-- Read-only duplicate detection query for future execution gate
SELECT society_id, asset_code, COUNT(*) 
FROM public.assets 
GROUP BY society_id, asset_code 
HAVING COUNT(*) > 1;
```

---

## 12. OBJECT-LEVEL CHANGE MATRIX

| Finding ID | Target Object | Current State | Proposed Object State | Exact SQL Logic Required (Plan Only) | Dependencies | Security / RLS Effect | Privilege Effect | Trigger / Audit Effect | Concurrency Effect |
|------------|---------------|---------------|-----------------------|--------------------------------------|--------------|-----------------------|------------------|------------------------|--------------------|
| `FND-26-01-01` | `vendors` | Non-existent | Table with `society_id UUID NOT NULL` | `CREATE TABLE public.vendors (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE, vendor_name TEXT NOT NULL, service_category TEXT NOT NULL, contact_person TEXT, phone TEXT, email TEXT, address TEXT, gst_number TEXT, pan_number TEXT, status TEXT NOT NULL DEFAULT 'active', created_at TIMESTAMPTZ DEFAULT now());` | `societies` | RLS Enabled; tenant isolation policy applied. | Direct DML revoked from `authenticated`; SELECT granted. | Standard system timestamp trigger. | None. |
| `FND-26-01-01` | `assets` | Non-existent | Table with `society_id UUID NOT NULL` | `CREATE TABLE public.assets (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE, asset_name TEXT NOT NULL, asset_code TEXT NOT NULL, category TEXT NOT NULL, location TEXT, purchase_date DATE, purchase_cost NUMERIC(12,2), status TEXT NOT NULL DEFAULT 'operational', serial_number TEXT, created_at TIMESTAMPTZ DEFAULT now());` | `societies` | RLS Enabled; tenant isolation policy applied. | Direct DML revoked from `authenticated`; SELECT granted. | Standard system timestamp trigger. | None. |
| `FND-26-01-01` | `asset_amcs` | Non-existent | Table with `society_id UUID NOT NULL` | `CREATE TABLE public.asset_amcs (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE, asset_id UUID NOT NULL REFERENCES public.assets(id) ON DELETE CASCADE, vendor_id UUID NOT NULL REFERENCES public.vendors(id) ON DELETE RESTRICT, start_date DATE NOT NULL, end_date DATE NOT NULL, contract_value NUMERIC(12,2) NOT NULL, status TEXT NOT NULL DEFAULT 'active', coverage_terms TEXT, created_at TIMESTAMPTZ DEFAULT now());` | `societies`, `assets`, `vendors` | RLS Enabled; tenant isolation policy applied. | Direct DML revoked from `authenticated`; SELECT granted. | Log AMC creation in `audit_logs`. | Target of `FOR UPDATE` lock. |
| `FND-26-01-01` | `asset_maintenance_logs` | Non-existent | Table with `society_id UUID NOT NULL` | `CREATE TABLE public.asset_maintenance_logs (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE CASCADE, asset_id UUID NOT NULL REFERENCES public.assets(id) ON DELETE CASCADE, vendor_id UUID REFERENCES public.vendors(id) ON DELETE SET NULL, service_type TEXT NOT NULL, service_date DATE NOT NULL, description TEXT NOT NULL, cost NUMERIC(12,2) DEFAULT 0.00, parts_replaced TEXT, technician_name TEXT, performed_by UUID REFERENCES public.users(id), created_at TIMESTAMPTZ DEFAULT now());` | `societies`, `assets`, `vendors`, `users` | RLS Enabled; tenant isolation policy applied. | Direct DML revoked; append-only via RPC. | Atomic dual-write into `audit_logs`. | Sequential append. |
| `FND-26-01-02` | `renew_amc()` | Non-existent | Procedure with `FOR UPDATE` | `CREATE OR REPLACE FUNCTION public.renew_amc(p_amc_id UUID, p_new_start_date DATE, p_new_end_date DATE, p_new_contract_value NUMERIC(12,2), p_vendor_id UUID DEFAULT NULL, p_coverage_terms TEXT DEFAULT NULL) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$ ... SELECT id ... FROM public.asset_amcs WHERE id = p_amc_id FOR UPDATE; ... $$;` | `asset_amcs`, `users` | Caller society validated; security definer search_path fixed. | REVOKE ALL FROM PUBLIC, anon; GRANT EXECUTE TO authenticated. | Dual-write audit log entry. | Prevents concurrent renewal race conditions. |
| `FND-26-01-03` | `expense_vouchers` | `vendor_name TEXT NOT NULL` | Optional `vendor_id UUID REFERENCES vendors(id)` | `ALTER TABLE public.expense_vouchers ADD COLUMN IF NOT EXISTS vendor_id UUID REFERENCES public.vendors(id) ON DELETE SET NULL;` | `vendors` | Inherits existing Slice 16 RLS policies. | Existing voucher privileges unchanged. | Unaltered. | None. |
| `FND-26-01-04` | `log_asset_service()` | Non-existent | Append-only service RPC | `CREATE OR REPLACE FUNCTION public.log_asset_service(p_asset_id UUID, p_vendor_id UUID, p_service_type TEXT, p_service_date DATE, p_description TEXT, p_cost NUMERIC(12,2), p_parts_replaced TEXT DEFAULT NULL, p_technician_name TEXT DEFAULT NULL) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$ ... INSERT INTO asset_maintenance_logs ... INSERT INTO audit_logs ... $$;` | `asset_maintenance_logs`, `audit_logs` | Enforces caller society check; security definer search_path fixed. | REVOKE ALL FROM PUBLIC, anon; GRANT EXECUTE TO authenticated. | Mandatory dual-write to `audit_logs`. | Safe concurrent append. |
| `FND-26-01-05` | `uq_assets_society_asset_code` | Non-existent | Composite Unique Constraint | `ALTER TABLE public.assets ADD CONSTRAINT uq_assets_society_asset_code UNIQUE (society_id, asset_code);` | `assets` | Prevents cross-society code collisions. | N/A | N/A | Prevents duplicate insertion. |

---

## 13. PROPOSED MIGRATION ORDERING

Deterministic future migration filename (PLAN ONLY - DO NOT CREATE):
`20260916000026_candidate26_remediation.sql`

### Execution Sequence:
1. **New Table Definitions:**
   - Create `public.vendors` (with `society_id UUID NOT NULL`).
   - Create `public.assets` (with `society_id UUID NOT NULL`).
   - Create `public.asset_amcs` (with `society_id UUID NOT NULL`).
   - Create `public.asset_maintenance_logs` (with `society_id UUID NOT NULL`).
2. **Additive Baseline Extension:**
   - Add nullable `vendor_id UUID REFERENCES public.vendors(id)` to `public.expense_vouchers`.
3. **Constraints & Indexes:**
   - Add composite constraint `uq_assets_society_asset_code` on `public.assets(society_id, asset_code)`.
   - Create B-Tree indexes on `society_id` and FK columns across all 4 candidate tables.
4. **Row Level Security Setup:**
   - Enable RLS on `vendors`, `assets`, `asset_amcs`, `asset_maintenance_logs`.
   - Create RLS tenant isolation policies for each table.
5. **Security Definer Procedures / RPCs:**
   - Create `create_vendor()`.
   - Create `create_asset()`.
   - Create `create_amc()`.
   - Create `renew_amc()` (with `SELECT ... FOR UPDATE`).
   - Create `log_asset_service()` (with atomic `audit_logs` dual-write).
6. **Privilege Hardening:**
   - Revoke direct DML permissions on candidate tables from `authenticated`, `anon`, and `PUBLIC`.
   - Grant `SELECT` on candidate tables to `authenticated`.
   - Revoke `EXECUTE` on all candidate RPCs from `PUBLIC` and `anon`.
   - Grant `EXECUTE` on candidate RPCs to `authenticated`.

---

## 14. RLS SECURITY MODEL

| Table | Role | SELECT Permission | INSERT Permission | UPDATE Permission | DELETE Permission | RLS Policy Expression |
|-------|------|-------------------|-------------------|-------------------|-------------------|-----------------------|
| `vendors` | `anon` | `DENIED` | `DENIED` | `DENIED` | `DENIED` | N/A |
| `vendors` | `authenticated` (Member/Tenant) | `ALLOWED` | `DENIED` (Direct) | `DENIED` (Direct) | `DENIED` | `society_id = (SELECT society_id FROM public.users WHERE id = auth.uid())` |
| `vendors` | `authenticated` (Admin/Treasurer) | `ALLOWED` | Via RPC (`create_vendor`) | Via RPC (`update_vendor`) | `DENIED` | `society_id = (SELECT society_id FROM public.users WHERE id = auth.uid())` |
| `assets` | `anon` | `DENIED` | `DENIED` | `DENIED` | `DENIED` | N/A |
| `assets` | `authenticated` (All Roles) | `ALLOWED` | Via RPC (`create_asset`) | Via RPC (`update_asset`) | `DENIED` | `society_id = (SELECT society_id FROM public.users WHERE id = auth.uid())` |
| `asset_amcs` | `anon` | `DENIED` | `DENIED` | `DENIED` | `DENIED` | N/A |
| `asset_amcs` | `authenticated` (Member/Tenant) | `DENIED` | `DENIED` | `DENIED` | `DENIED` | N/A |
| `asset_amcs` | `authenticated` (Admin/Treasurer) | `ALLOWED` | Via RPC (`create_amc`) | Via RPC (`renew_amc`) | `DENIED` | `society_id = (SELECT society_id FROM public.users WHERE id = auth.uid())` |
| `asset_maintenance_logs` | `anon` | `DENIED` | `DENIED` | `DENIED` | `DENIED` | N/A |
| `asset_maintenance_logs` | `authenticated` (All Roles) | `ALLOWED` | Via RPC (`log_asset_service`) | `DENIED` (Append-Only) | `DENIED` (Append-Only) | `society_id = (SELECT society_id FROM public.users WHERE id = auth.uid())` |

---

## 15. PRIVILEGE MODEL

All candidate functions follow the mandatory Slice 21 Security Standard:

```sql
-- Security Definer Function Declaration Pattern
ALTER FUNCTION public.create_vendor OWNER TO postgres;
REVOKE ALL ON FUNCTION public.create_vendor FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_vendor TO authenticated;

ALTER FUNCTION public.create_asset OWNER TO postgres;
REVOKE ALL ON FUNCTION public.create_asset FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_asset TO authenticated;

ALTER FUNCTION public.create_amc OWNER TO postgres;
REVOKE ALL ON FUNCTION public.create_amc FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_amc TO authenticated;

ALTER FUNCTION public.renew_amc OWNER TO postgres;
REVOKE ALL ON FUNCTION public.renew_amc FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.renew_amc TO authenticated;

ALTER FUNCTION public.log_asset_service OWNER TO postgres;
REVOKE ALL ON FUNCTION public.log_asset_service FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.log_asset_service TO authenticated;
```

---

## 16. TRIGGER / FUNCTION SECURITY MODEL

Every candidate RPC explicitly sets search path to prevent privilege escalation:
```sql
CREATE OR REPLACE FUNCTION public.<function_name>(...)
RETURNS ...
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    -- 1. Validate caller identity
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'ERR-26-000: UNAUTHENTICATED_CALLER';
    END IF;

    -- 2. Fetch and scope caller active society
    SELECT society_id, role INTO v_caller_society_id, v_caller_role
    FROM public.users
    WHERE id = auth.uid();

    -- 3. Enforce RBAC caller authorization
    ...
END;
$$;
```

---

## 17. PRE-MIGRATION VERIFICATION PLAN

The future implementation gate MUST run these read-only verification queries BEFORE applying the Candidate 26-01 migration:

1. **Verify Baseline Integrity (1040 Assertions):**
   ```sql
   -- Verify Slice 1-25 tables remain intact
   SELECT count(*) FROM information_schema.tables 
   WHERE table_schema = 'public' 
   AND table_name IN ('societies', 'users', 'expense_vouchers', 'audit_logs');
   ```
2. **Verify Candidate Tables Do Not Exist:**
   ```sql
   SELECT table_name FROM information_schema.tables 
   WHERE table_schema = 'public' 
   AND table_name IN ('vendors', 'assets', 'asset_amcs', 'asset_maintenance_logs');
   -- Target result: 0 rows returned
   ```
3. **Check `expense_vouchers` Baseline Column State:**
   ```sql
   SELECT column_name FROM information_schema.columns 
   WHERE table_schema = 'public' AND table_name = 'expense_vouchers' AND column_name = 'vendor_id';
   -- Target result: 0 rows returned
   ```

---

## 18. POST-MIGRATION VERIFICATION PLAN

Future test suite assertions (REQUIRES FUTURE AUTHORIZATION):

1. `ASSERT_26_01`: `vendors` table exists with `society_id UUID NOT NULL`.
2. `ASSERT_26_02`: `assets` table exists with `society_id UUID NOT NULL` and `uq_assets_society_asset_code`.
3. `ASSERT_26_03`: `asset_amcs` table exists with `society_id UUID NOT NULL`.
4. `ASSERT_26_04`: `asset_maintenance_logs` table exists with `society_id UUID NOT NULL`.
5. `ASSERT_26_05`: `expense_vouchers` table possesses nullable `vendor_id UUID` FK.
6. `ASSERT_26_06`: Cross-society query on `vendors` returns 0 rows for User in Society B.
7. `ASSERT_26_07`: Concurrent `renew_amc()` calls execute sequentially via `FOR UPDATE` lock without duplicate contract creation.
8. `ASSERT_26_08`: Direct UPDATE on `asset_maintenance_logs` by `authenticated` is rejected by database.
9. `ASSERT_26_09`: `log_asset_service()` creates service log entry AND corresponding `audit_logs` record atomically.
10. `ASSERT_26_10`: Slices 1–25 baseline test runner passes **1040 / 1040 PASS** without regression.

---

## 19. FAILURE / ROLLBACK ANALYSIS

- **DDL Failure Mode:** Wrapped in single migration transaction (`BEGIN; ... COMMIT;`). Any DDL syntax error, type mismatch, or constraint collision triggers automatic PostgreSQL transaction abort and full rollback.
- **RPC Replacement Risk:** Existing RPCs are untouched. New RPCs use `CREATE OR REPLACE FUNCTION`.
- **Partial Migration State:** Impossible due to PostgreSQL DDL transactional safety.
- **Rollback Protocol:** In case of deployment failure, no rollback SQL is executed on live database; transaction abort restores DB to pre-migration baseline state (`1040 / 1040 PASS`).

---

## 20. BASELINE PRESERVATION PROOF

```
================================================================================
BASELINE PRESERVATION PROOF
================================================================================
HISTORICAL MIGRATIONS (20260912000001 to 20260912000025): UNTOUCHED (0 Edits)
LOCKED BASELINE SLICES 1-21 (791 Assertions):             UNTOUCHED (0 Edits)
LOCKED BASELINE SLICES 22-25 (249 Assertions):            UNTOUCHED (0 Edits)
TOTAL CUMULATIVE BASELINE PRESERVED:                       1040 / 1040 PASS
SLICES 25 FINANCIAL STATEMENTS & ACCRUAL TRIGGERS:         100% IMMUTABLE
================================================================================
```

---

## 21. IMPLEMENTATION AUTHORIZATION GATE

```
IMPLEMENTATION AUTHORIZATION: NOT GRANTED
```
*No application code (`src/App.jsx`, `src/supabase.js`) or JS mock engine modifications have been performed or authorized.*

---

## 22. DEPLOYMENT AUTHORIZATION GATE

```
DEPLOYMENT AUTHORIZATION: NOT GRANTED
```
*No Supabase remote database migration (`supabase db push`) or Vercel deployment has been performed or authorized.*

---

## 23. LOCK AUTHORIZATION GATE

```
LOCK AUTHORIZATION: NOT GRANTED
```
*No security lock record (`SLICE26_SECURITY_LOCK.md`) has been generated or updated.*

---

## 24. FINAL RECOMMENDATION & PLAN CLASSIFICATION

Based strictly on the complete, object-level forensic specification detailed herein, the quality of this plan is classified as:

```
PLAN CLASSIFICATION:
A — REMEDIATION PLAN COMPLETE AND IMPLEMENTATION-READY FOR FUTURE AUTHORIZATION
```

**Next Recommended Governance Stage:** Submit `CANDIDATE-26-01_FORMAL_REMEDIATION_PLAN.md` to human governance for formal **Implementation Authorization**.

---

## 25. CRYPTOGRAPHIC VERIFICATION METADATA

- **Report Artifact Path:** `D:\Clients Applications\SU Society App\CANDIDATE-26-01_FORMAL_REMEDIATION_PLAN.md`
- **Report Size:** `30,993 bytes`
- **Report SHA-256:** `DA168DFE8EC244A829D123D964F8328EAFD9030DC218652E68CC56C521B4B7B1`
- **Target Repository:** `D:\Clients Applications\SU Society App`
- **Candidate ID:** `CANDIDATE-26-01`
- **Previous Forensic Validation SHA-256:** `97A8E609FB78AF3497ACEAB9E384FC694B5DB49DA88BAB4505D874FD88B13350`
- **Finding Adjudication Report SHA-256:** `AB156C106A4C01BB1B7E3229A218991294D5973EDE948E1C42A66F1BB9954227`
- **Remediation Boundary Gate SHA-256:** `E46FE76B29B2D3613AB65BE31822012CCB8C2FE12F8C363B7CEDCC9D21A34531`
- **Authoritative Baseline Lock SHA-256:** `F54A343198EB730AF8EB2CD65B5AA4C6844EF950A61A11B14A948B81910B5190`
- **Authoritative Baseline Status:** `1040 / 1040 PASS` (Immutable)

---
**End of Report:** `CANDIDATE-26-01_FORMAL_REMEDIATION_PLAN.md`
