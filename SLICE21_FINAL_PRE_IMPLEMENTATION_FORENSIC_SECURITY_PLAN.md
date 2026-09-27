# SLICE 21 — FINAL PRE-IMPLEMENTATION FORENSIC SECURITY PLAN

## EXECUTIVE SUMMARY
This artifact establishes the authoritative pre-implementation security plan for **Slice 21: Security Gate Emergency Blacklist, Gate Access Denial & Asset/Vendor AMC Management System**.

### Current Baseline & Immutability Context
- **Locked Cumulative Baseline:** **714 / 714 PASS (100%)**
  - Slices 1–19 Baseline: 639 / 639 PASS
  - Slice 2 Financial Remediation: 24 / 24 PASS
  - Slice 20 (NOC & Move-Out Management): 51 / 51 PASS (Formally Locked)
- **Slice 20 Hash Boundary:** `schema_slice20.sql` (SHA-256: `EFA25D7EFC2587A93A3A0DA75661648684BF50581C6C4A942D3F4ECF5A06B6E7`) and `verify_slice20.sql` (SHA-256: `39F96A29164FDCC94D14BE356C6887CD23A692B8D657605C354D5C692E47CF71`).
- **Scope Boundary:** Slice 21 ONLY. Zero modifications to Slices 1–20. Zero Rev 4.54.

---

## 1. DISCOVERED SLICE 21 SCOPE & GOVERNANCE BOUNDARY

Forensic audit of project architecture, prior gap analyses (`SLICE20_DISCOVERY_PRODUCT_GAP_AUDIT.md`), and security plans (`SLICE19_FINAL_IMPLEMENTATION_SECURITY_PLAN.md`) established the mandatory scope for Slice 21:

1. **Security Gate Emergency Blacklist & Gate Access Denial System:**
   - Blacklisting of flagged individuals (CNIC/passport/phone/name), vehicles (license plate/VIN), expelled contractors, and barred former residents.
   - Multi-tiered threat classification (`low`, `medium`, `high`, `critical`).
   - Automated Interception: Gatekeeper verification (`verify_pass`, visitor check-in) MUST evaluate active blacklist entries under `FOR SHARE` / `FOR UPDATE` locks. Matches trigger automatic access denial, raise `SQLSTATE 42501`, write immutable records to `security_denial_logs`, and alert security administration.
2. **Society Asset Catalog & AMC (Annual Maintenance Contract) Vendor Security Management:**
   - Registry for critical society assets (generators, elevators, CCTV, fire safety equipment, barrier gates).
   - AMC vendor contracts (vendor identification, maintenance schedules, SLA levels, contract expiration dates).
   - Temporary Vendor Staff Access Passes (CSPRNG 48-bit token generation, SHA-256 digest-only storage, time-bound gate clearance for maintenance crews).

---

## 2. REPOSITORY & BASELINE INTEGRITY AUDIT

Pre-planning verification confirmed all authoritative hashes:
- `SLICE20_REVISION_4.53_FINAL_FORENSIC_BYTE_SAFE_AUTHORITY_PRESERVATION.md`: `99F46FF7C7463E1E594F89C9C7C83FB7A15BEC8E9CBF93B9E7636D517210FE24` (**MATCH**)
- `SLICE20_REVISION_4.48_BYTE_SAFE_CLEAN_SECURITY_PLAN.md`: `A54904A4095112698FE5C5103F913C8359924480614AF3195889A2D0E29C499E` (**MATCH**)
- `SLICE2_CORRECTED_FINANCIAL_SERIALIZATION_REMEDIATION_PLAN.md`: `767656132833CE386FA02BB6F7A5556D62668210AD8E2906886978482230D9E6` (**MATCH**)
- `database/schema_slice2.sql`: `191AC5353DEED19DBBAB1AFBE1DB2A272C6D45A599760CF707ACE3D5135AFA49` (**MATCH**)
- `database/verify_slice2.sql`: `66585EB71D36FEBAC59297101598A1D56828C60AFDCDE9AD75C9063C7FF191F8` (**MATCH**)
- `SLICE2_EXPLICIT_GOVERNANCE_VARIANCE_AUTHORIZATION.md`: `75BB72D848D841EC41BBB3B83525AD16272774B142A31EA58CD77D5B765A0B2C` (**MATCH**)
- Rev 4.54: **ABSENT**.

---

## 3. THREAT MODEL & SECURITY GAP INVENTORY

| Gap ID | Security Risk | Severity | Target Mitigation in Slice 21 |
| :--- | :--- | :--- | :--- |
| **GAP-21-01** | Bypassing gate access for expelled or dangerous individuals | **CRITICAL** | Real-time mandatory blacklist evaluation during pass verification & visitor entry. |
| **GAP-21-02** | License plate spoofing or unauthorized vehicle entry | **HIGH** | Normalized vehicle registration & plate matching in `security_blacklist_records`. |
| **GAP-21-03** | Unauthorized vendor technician entry post-contract expiry | **HIGH** | Active AMC contract validation before issuing vendor staff gate passes. |
| **GAP-21-04** | Plaintext vendor pass token leakage | **HIGH** | CSPRNG 48-bit token generation & SHA-256 digest-only storage (`vendor_pass_digest`). |
| **GAP-21-05** | Direct table DML tampering on blacklist or denial logs | **HIGH** | Complete DML write revocation for `authenticated`/`anon`/`PUBLIC`; SECURITY DEFINER RPC entry. |
| **GAP-21-06** | IDOR across society asset & vendor records | **HIGH** | Strict society-level RLS & tenant isolation in RPC parameters. |

---

## 4. PROPOSED DATABASE ARCHITECTURE (SLICE 21)

### Tables To Be Created (`database/schema_slice21.sql`)
1. **`public.security_blacklist_records`**
   - `id` UUID PRIMARY KEY
   - `society_id` UUID NOT NULL REFERENCES `public.societies(id)`
   - `subject_type` VARCHAR(20) CHECK (`subject_type` IN ('individual', 'vehicle', 'vendor_staff'))
   - `full_name` VARCHAR(150)
   - `identity_number` VARCHAR(50) -- CNIC / Passport
   - `phone_number` VARCHAR(30)
   - `vehicle_plate` VARCHAR(30)
   - `severity_level` VARCHAR(20) CHECK (`severity_level` IN ('low', 'medium', 'high', 'critical'))
   - `reason` TEXT NOT NULL
   - `is_active` BOOLEAN DEFAULT TRUE
   - `created_at`, `updated_at`, `created_by`
2. **`public.security_denial_logs`**
   - `id` UUID PRIMARY KEY
   - `society_id` UUID NOT NULL REFERENCES `public.societies(id)`
   - `blacklist_id` UUID REFERENCES `public.security_blacklist_records(id)`
   - `attempted_entry_type` VARCHAR(50)
   - `gatekeeper_id` UUID NOT NULL
   - `attempt_details` JSONB
   - `denied_at` TIMESTAMPTZ DEFAULT NOW()
3. **`public.society_assets`**
   - `id` UUID PRIMARY KEY
   - `society_id` UUID NOT NULL REFERENCES `public.societies(id)`
   - `asset_name` VARCHAR(150) NOT NULL
   - `category` VARCHAR(50) CHECK (`category` IN ('generator', 'elevator', 'cctv', 'fire_safety', 'water_pump', 'barrier_gate', 'other'))
   - `location` VARCHAR(150)
   - `status` VARCHAR(20) DEFAULT 'operational'
   - `created_at`, `updated_at`
4. **`public.amc_vendor_contracts`**
   - `id` UUID PRIMARY KEY
   - `society_id` UUID NOT NULL REFERENCES `public.societies(id)`
   - `asset_id` UUID REFERENCES `public.society_assets(id)`
   - `vendor_name` VARCHAR(150) NOT NULL
   - `contact_email` VARCHAR(100)
   - `contact_phone` VARCHAR(30)
   - `contract_start` DATE NOT NULL
   - `contract_end` DATE NOT NULL
   - `status` VARCHAR(20) CHECK (`status` IN ('active', 'expired', 'terminated'))
   - `created_at`, `updated_at`
5. **`public.vendor_access_passes`**
   - `id` UUID PRIMARY KEY
   - `society_id` UUID NOT NULL REFERENCES `public.societies(id)`
   - `amc_contract_id` UUID NOT NULL REFERENCES `public.amc_vendor_contracts(id)`
   - `pass_token_digest` VARCHAR(64) NOT NULL
   - `technician_name` VARCHAR(150) NOT NULL
   - `technician_identity` VARCHAR(50) NOT NULL
   - `valid_from` TIMESTAMPTZ NOT NULL
   - `valid_until` TIMESTAMPTZ NOT NULL
   - `status` VARCHAR(20) CHECK (`status` IN ('issued', 'used', 'revoked', 'expired'))
   - `created_at`, `updated_at`

### Partial Unique Indexes
- `uq_active_blacklist_identity` ON `security_blacklist_records (society_id, identity_number)` WHERE `is_active = TRUE AND identity_number IS NOT NULL`
- `uq_active_blacklist_plate` ON `security_blacklist_records (society_id, vehicle_plate)` WHERE `is_active = TRUE AND vehicle_plate IS NOT NULL`

---

## 5. PROPOSED RPC INVENTORY & SECURITY HARDENING

All RPC routines MUST be declared with:
`SECURITY DEFINER`
`SET search_path = pg_catalog, public;`

1. `public.fn_create_blacklist_entry` (Admin only)
2. `public.fn_deactivate_blacklist_entry` (Admin only)
3. `public.fn_evaluate_access_denial` (Gatekeeper / Security Defined invocation during entry checks)
4. `public.fn_register_society_asset` (Admin only)
5. `public.fn_create_amc_contract` (Admin only)
6. `public.fn_issue_vendor_pass` (Admin only; CSPRNG 48-bit token generation, SHA-256 digest persistence)
7. `public.fn_verify_vendor_pass` (Gatekeeper verify; checks contract status and active blacklist)
8. `public.process_expired_amc_contracts` (Automated maintenance expiration worker)

---

## 6. PRIVILEGE & RLS BOUNDARIES

- **Direct Write Revocation:**
  `REVOKE INSERT, UPDATE, DELETE ON public.security_blacklist_records FROM authenticated, anon, PUBLIC;`
  `REVOKE INSERT, UPDATE, DELETE ON public.security_denial_logs FROM authenticated, anon, PUBLIC;`
  `REVOKE INSERT, UPDATE, DELETE ON public.society_assets FROM authenticated, anon, PUBLIC;`
  `REVOKE INSERT, UPDATE, DELETE ON public.amc_vendor_contracts FROM authenticated, anon, PUBLIC;`
  `REVOKE INSERT, UPDATE, DELETE ON public.vendor_access_passes FROM authenticated, anon, PUBLIC;`
- **RLS & FORCE RLS:** Enabled on all 5 tables. Admin full read access; gatekeeper read access to active blacklist and vendor passes; tenant zero read access to raw security blacklist records.

---

## 7. CONCURRENCY & LOCK ORDER HIERARCHY

To prevent deadlocks across Slices 1–21, all mutation paths MUST follow the strict locking sequence:
1. `public.properties` / `public.societies` (Step 1 Row Lock)
2. `public.security_blacklist_records`
3. `public.society_assets`
4. `public.amc_vendor_contracts`
5. `public.vendor_access_passes`

---

## 8. PROPOSED VERIFICATION MATRIX (ASSERTIONS S21-001..S21-050)

- **S21-001:** 5 New Slice 21 Tables Exist
- **S21-002:** Partial Unique Indexes `uq_active_blacklist_identity` & `plate` Exist
- **S21-003:** 8 SECURITY DEFINER RPCs Hardened with `SET search_path = pg_catalog, public;`
- **S21-004:** RLS & FORCE RLS Enabled on All 5 Tables
- **S21-005:** Direct Table DML Revoked from `authenticated`, `anon`, `PUBLIC`
- **S21-006:** Admin Valid Blacklist Entry Creation
- **S21-007:** Duplicate Active Blacklist Identity Blocked by Unique Index
- **S21-008:** Non-Admin Blacklist Creation Blocked (`SQLSTATE 42501`)
- **S21-009:** Gatekeeper Access Evaluation Triggers Automatic Denial for Blacklisted Identity
- **S21-010:** Security Denial Log Created Atomically on Blacklist Match
- **S21-011:** CSPRNG Vendor Pass Token Generation (21 chars, 48-bit entropy)
- **S21-012:** Vendor Pass SHA-256 Digest Storage (Zero Plaintext Persistence)
- **S21-013:** Expired AMC Contract Blocks Vendor Pass Generation
- **S21-014:** Gatekeeper Valid Vendor Pass Verification
- **S21-015:** Blacklisted Vendor Staff Blocks Vendor Pass Verification
- **S21-016..S21-049:** Additional Functional, Tenancy, IDOR, and Expiration Assertions
- **S21-050:** Cumulative Project Baseline Target Reached (**764 / 764 PASS**)

---

## 9. GOVERNANCE VERDICT
**SLICE 21 PLAN — READY FOR INDEPENDENT REVIEW**
