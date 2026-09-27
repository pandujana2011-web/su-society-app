# SLICE 21 — FINAL PRE-IMPLEMENTATION FORENSIC SECURITY PLAN — REVISION

## EXECUTIVE SUMMARY
This artifact establishes the revised, forensically hardened pre-implementation security plan for **Slice 21: Security Gate Emergency Blacklist, Gate Access Denial & Asset/Vendor AMC Management System**.

### Current Baseline & Immutability Context
- **Locked Cumulative Baseline:** **714 / 714 PASS (100%)**
  - Slices 1–19 Baseline: 639 / 639 PASS
  - Slice 2 Financial Remediation: 24 / 24 PASS
  - Slice 20 NOC & Move-Out Management: 51 / 51 PASS (Formally Locked)
- **Governance Boundary:** Slices 1–20 remain 100% untouched and locked. Rev 4.54 is absent. Zero database mutations or implementation code edits performed.

---

## 1. REVISED SCOPE & GOVERNANCE BOUNDARY

The scope of Slice 21 encompasses two security-critical modules:

1. **Security Gate Emergency Blacklist & Gate Access Denial System:**
   - Blacklisting of flagged individuals (CNIC/Passport/phone/name), vehicles (license plate/VIN), expelled contractors, and barred former residents across threat severity levels (`low`, `medium`, `high`, `critical`).
   - Automated Interception: Gatekeeper check-in & pass verification (`verify_pass`, vendor entry) MUST evaluate active blacklist records under `FOR SHARE`/`FOR UPDATE` locks.
   - Structured Access Denial & Durable Logging: Reconciles PostgreSQL transaction semantics by executing structured result-returning denial evaluation (`fn_evaluate_access_denial`) so that denial audit logs in `security_denial_logs` persist cleanly without being undone by transaction rollback.
2. **Society Asset Catalog & AMC (Annual Maintenance Contract) Vendor Security Management:**
   - Registry for critical society assets (generators, elevators, CCTV, fire safety equipment, water pumps, barrier gates).
   - AMC vendor contracts (vendor identification, maintenance schedules, SLA levels, contract expiration dates).
   - Temporary Vendor Staff Access Passes (CSPRNG 48-bit token generation, SHA-256 digest-only storage, time-bound gate clearance for maintenance crews).

---

## 2. RECONCILIATION OF CRITICAL ARCHITECTURAL ISSUES

### Critical Issue #1 — Denial Logging vs SQLSTATE 42501 Transaction Semantics
- **Problem:** Raising a PostgreSQL exception (`RAISE EXCEPTION SQLSTATE '42501'`) within the same transaction that inserts into `security_denial_logs` causes PostgreSQL to abort the transaction and roll back the inserted audit row.
- **Corrected Architecture (Option A Structured Result):**
  - `fn_evaluate_access_denial` evaluates active blacklist matches under `FOR SHARE` lock.
  - On match, it inserts an immutable denial log into `security_denial_logs` AND returns a structured JSON result:
    `{"access_granted": false, "denial_reason": "Blacklisted Subject Detected", "severity": "critical", "denial_log_id": "<UUID>"}`.
  - The calling RPC or application layer receives the denial payload, denies physical access, and completes the denial logging transaction successfully without raising a transaction-unwinding exception. If an RPC wrapper requires failure status, denial logging is committed prior to error handling or executed via dedicated RPC boundary.

### Critical Issue #2 — Vendor Pass Token Cryptography & Entropy
- **Token Format:** CSPRNG generated 6 random bytes (48 bits entropy) encoded as 12 uppercase hexadecimal characters appended to prefix `VND-PASS-` (Total length: 21 characters, e.g. `VND-PASS-A1B2C3D4E5F6`).
- **Digest Storage:** Raw tokens are returned ONCE to the admin on pass generation and NEVER persisted. Database column `pass_token_digest` stores SHA-256 hex digest (`encode(extensions.digest(v_token, 'sha256'), 'hex')`).
- **Online Brute-Force Protection:** Verification RPC enforces rate limiting (maximum 3 failed verification attempts per gatekeeper within a 15-minute window before temporary lockout).

### Critical Issue #3 — Vendor Pass Replay & Concurrency Security
- **Atomic Redemption:** `fn_verify_vendor_pass` acquires row lock `SELECT status INTO v_status FROM public.vendor_access_passes WHERE id = p_pass_id FOR UPDATE;`.
- **State Transition:** Status updates atomically from `issued` to `used`. Subsequent verification attempts observe `status = 'used'` or `valid_until < NOW()` and fail closed.
- **Digest Uniqueness:** `vendor_access_passes` enforces `UNIQUE(pass_token_digest)`.

### Critical Issue #4 — Blacklist Identifier Normalization
- **Phone:** Strip non-digit characters, normalize country code to E.164 format (`+92...`).
- **CNIC / Passport:** Strip spaces/hyphens, convert to uppercase (`42101-1234567-1` -> `4210112345671`).
- **Vehicle Plate:** Strip spaces/punctuation, convert to uppercase (`ABC-1234` -> `ABC1234`).
- **Name Matching:** Normalized lowercase string comparison used as secondary advisory indicator only; primary matching strictly relies on canonical identity numbers or plates to prevent false positives.

### Critical Issue #5 — Sensitive Data Protection & RLS Scoping
- **P2/PII Protection:** Raw CNIC, phone, and reason fields protected by strict RLS.
- **Tenant Access:** Tenants/members hold **ZERO SELECT ACCESS** to `security_blacklist_records` or `security_denial_logs`.
- **Gatekeeper Access:** Gatekeepers access blacklist records only via SECURITY DEFINER evaluation RPC `fn_evaluate_access_denial`. Direct SELECT access restricted to active records in local society.
- **Admin Access:** Scoped strictly by `society_id`.

### Critical Issue #6 — Append-Only Immutable Denial Logs
- Direct `INSERT`, `UPDATE`, and `DELETE` privileges on `security_denial_logs` revoked from `authenticated`, `anon`, and `PUBLIC`.
- Updates and deletions blocked at database layer. Audit records are append-only via SECURITY DEFINER RPCs.

### Critical Issue #7 — AMC Contract Date & Status Consistency
- Contract validity derived from BOTH date bounds AND status:
  `contract_start <= CURRENT_DATE AND contract_end >= CURRENT_DATE AND status = 'active'`.
- Expiration worker `process_expired_amc_contracts` automatically marks contracts `expired` when `contract_end < CURRENT_DATE`.

### Critical Issue #8 — Cross-Society Referential Integrity
- Composite foreign keys / RPC validation constraints enforce:
  - `amc_vendor_contracts.society_id == society_assets.society_id`
  - `vendor_access_passes.society_id == amc_vendor_contracts.society_id`

### Critical Issue #9 — Lock Order Hierarchy
To eliminate deadlock risks with Slices 1–20:
1. `public.properties` / `public.societies` (Step 1 Row Lock)
2. `public.security_blacklist_records`
3. `public.society_assets`
4. `public.amc_vendor_contracts`
5. `public.vendor_access_passes`

---

## 3. REVISED DATABASE SCHEMA SPECIFICATION (`database/schema_slice21.sql`)

1. **`public.security_blacklist_records`**
   - `id` UUID PRIMARY KEY DEFAULT gen_random_uuid()
   - `society_id` UUID NOT NULL REFERENCES `public.societies(id)`
   - `subject_type` VARCHAR(20) CHECK (`subject_type` IN ('individual', 'vehicle', 'vendor_staff'))
   - `full_name` VARCHAR(150)
   - `identity_number_canonical` VARCHAR(50) -- Normalized CNIC/Passport
   - `phone_canonical` VARCHAR(30) -- Normalized E.164
   - `vehicle_plate_canonical` VARCHAR(30) -- Normalized Plate
   - `severity_level` VARCHAR(20) CHECK (`severity_level` IN ('low', 'medium', 'high', 'critical'))
   - `reason` TEXT NOT NULL
   - `is_active` BOOLEAN DEFAULT TRUE
   - `created_at` TIMESTAMPTZ DEFAULT NOW(), `updated_at` TIMESTAMPTZ DEFAULT NOW(), `created_by` UUID NOT NULL
2. **`public.security_denial_logs`**
   - `id` UUID PRIMARY KEY DEFAULT gen_random_uuid()
   - `society_id` UUID NOT NULL REFERENCES `public.societies(id)`
   - `blacklist_id` UUID REFERENCES `public.security_blacklist_records(id)`
   - `attempted_entry_type` VARCHAR(50) NOT NULL
   - `gatekeeper_id` UUID NOT NULL
   - `attempt_details` JSONB NOT NULL
   - `denied_at` TIMESTAMPTZ DEFAULT NOW()
3. **`public.society_assets`**
   - `id` UUID PRIMARY KEY DEFAULT gen_random_uuid()
   - `society_id` UUID NOT NULL REFERENCES `public.societies(id)`
   - `asset_name` VARCHAR(150) NOT NULL
   - `category` VARCHAR(50) CHECK (`category` IN ('generator', 'elevator', 'cctv', 'fire_safety', 'water_pump', 'barrier_gate', 'other'))
   - `location` VARCHAR(150)
   - `status` VARCHAR(20) DEFAULT 'operational'
   - `created_at` TIMESTAMPTZ DEFAULT NOW(), `updated_at` TIMESTAMPTZ DEFAULT NOW()
4. **`public.amc_vendor_contracts`**
   - `id` UUID PRIMARY KEY DEFAULT gen_random_uuid()
   - `society_id` UUID NOT NULL REFERENCES `public.societies(id)`
   - `asset_id` UUID NOT NULL REFERENCES `public.society_assets(id)`
   - `vendor_name` VARCHAR(150) NOT NULL
   - `contact_email` VARCHAR(100)
   - `contact_phone` VARCHAR(30)
   - `contract_start` DATE NOT NULL
   - `contract_end` DATE NOT NULL
   - `status` VARCHAR(20) CHECK (`status` IN ('active', 'expired', 'terminated'))
   - `created_at` TIMESTAMPTZ DEFAULT NOW(), `updated_at` TIMESTAMPTZ DEFAULT NOW()
5. **`public.vendor_access_passes`**
   - `id` UUID PRIMARY KEY DEFAULT gen_random_uuid()
   - `society_id` UUID NOT NULL REFERENCES `public.societies(id)`
   - `amc_contract_id` UUID NOT NULL REFERENCES `public.amc_vendor_contracts(id)`
   - `pass_token_digest` VARCHAR(64) NOT NULL UNIQUE
   - `technician_name` VARCHAR(150) NOT NULL
   - `technician_identity_canonical` VARCHAR(50) NOT NULL
   - `valid_from` TIMESTAMPTZ NOT NULL
   - `valid_until` TIMESTAMPTZ NOT NULL
   - `status` VARCHAR(20) CHECK (`status` IN ('issued', 'used', 'revoked', 'expired'))
   - `created_at` TIMESTAMPTZ DEFAULT NOW(), `updated_at` TIMESTAMPTZ DEFAULT NOW()

---

## 4. REVISED RPC INVENTORY (ALL WITH SET search_path = pg_catalog, public)

1. `public.fn_create_blacklist_entry` (Admin only; normalizes identity/plate/phone inputs)
2. `public.fn_deactivate_blacklist_entry` (Admin only)
3. `public.fn_evaluate_access_denial` (Gatekeeper / RPC evaluation; writes denial log & returns structured JSON result)
4. `public.fn_register_society_asset` (Admin only)
5. `public.fn_create_amc_contract` (Admin only; validates asset belongs to same society)
6. `public.fn_issue_vendor_pass` (Admin only; validates active AMC contract, checks technician against blacklist, generates CSPRNG token & stores SHA-256 digest)
7. `public.fn_verify_vendor_pass` (Gatekeeper verify; acquires FOR UPDATE row lock, checks active blacklist, transitions pass status to `used`)
8. `public.process_expired_amc_contracts` (Automated worker for contract and pass expiration updates)

---

## 5. EXPANDED VERIFICATION TEST MATRIX (ASSERTIONS S21-001..S21-065)

- **S21-001:** 5 New Slice 21 Tables Exist
- **S21-002:** Partial Unique Indexes & Digest Uniqueness Constraints Exist
- **S21-003:** 8 SECURITY DEFINER RPCs Hardened with `SET search_path = pg_catalog, public;`
- **S21-004:** RLS & FORCE RLS Enabled on All 5 Tables
- **S21-005:** Direct Table DML Revoked from `authenticated`, `anon`, `PUBLIC`
- **S21-006:** Canonicalization of Identity, Phone, and Vehicle Plate Inputs
- **S21-007:** Admin Valid Blacklist Entry Creation
- **S21-008:** Duplicate Active Blacklist Entry Blocked by Unique Index
- **S21-009:** Gatekeeper Access Evaluation Triggers Automatic Access Denial & Persistent Audit Log
- **S21-010:** Structured JSON Denial Result Returned Without Unwinding Denial Log Insert
- **S21-011:** CSPRNG Vendor Pass Token Generation (21 chars, 48-bit entropy)
- **S21-012:** SHA-256 Digest-Only Vendor Pass Storage (Zero Plaintext Persistence)
- **S21-013:** Expired/Terminated AMC Contract Blocks Vendor Pass Generation
- **S21-014:** Cross-Society Asset/AMC Contract Creation Blocked (`SQLSTATE 42501`)
- **S21-015:** Gatekeeper Valid Vendor Pass Verification & Atomic Transition to `used`
- **S21-016:** Replay of Used Vendor Pass Blocked
- **S21-017:** Concurrent Vendor Pass Verification Attempts (Exactly 1 succeeds, 1 fails)
- **S21-018:** Blacklisted Technician Blocks Vendor Pass Verification
- **S21-019:** Non-Admin Blacklist Mutation Blocked (`SQLSTATE 42501`)
- **S21-020:** Direct Denial Log Update/Delete Blocked (Append-Only Enforcement)
- **S21-021..S21-064:** IDOR, Cross-Society, Rate-Limiting, Expiration, and Sensitive Data Non-Leakage Assertions
- **S21-065:** Cumulative Project Baseline Target Reached (**779 / 779 PASS**)

---

## 6. GOVERNANCE VERDICT
**SLICE 21 PLAN — READY FOR INDEPENDENT REVIEW**
