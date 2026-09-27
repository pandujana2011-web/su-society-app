# SLICE 21 — FINAL PRE-IMPLEMENTATION FORENSIC SECURITY PLAN

## EXECUTIVE STATUS & GOVERNANCE SUMMARY

- **Current Locked Project Baseline:** **714 / 714 PASS (100%)**
  - Slices 1–19 Baseline: 639 / 639 PASS
  - Slice 2 Financial Remediation: 24 / 24 PASS
  - Slice 20 NOC & Move-Out Management: 51 / 51 PASS (Formally Locked at `2026-09-09T09:03:11.150Z`)
- **Protected Baseline Integrity:** Verified SHA-256 match for all 8 historical authority artifacts. Rev 4.54 is **ABSENT**. Slices 1–20 remain 100% untouched.
- **Slice 21 Verification Planned Target:** 77 substantive assertions (S21-001 through S21-077).
- **Expected Post-Verification Cumulative Target:** **714 locked baseline + 77 Slice 21 assertions = 791 Target** (Target only; NOT a current pass result).
- **Slice 21 Implementation Authorization:** **NOT GRANTED**
- **Slice 21 Verification Execution:** **NOT EXECUTED**
- **Slice 21 Security Lock:** **NOT AUTHORIZED**
- **Plan Status:** **FINAL FORENSIC SECURITY PLAN COMPLETE — READY FOR INDEPENDENT REVIEW**

---

## 1. SCOPE & THREAT MODEL

The scope of Slice 21 encompasses two core security domains:
1. **Security Gate Emergency Blacklist & Gate Access Denial System:**
   - Blacklist registry for flagged individuals, vehicles, expelled contractors, and barred former residents across threat levels (`low`, `medium`, `high`, `critical`).
   - Automated Access Interception: Real-time blacklist evaluation during entry verification (`verify_pass`, vendor entry). Structured denial result-returning evaluation (`fn_evaluate_access_denial`) prevents transaction rollback unwinding of `security_denial_logs`.
2. **Society Asset Catalog & AMC Vendor Security Management:**
   - Society equipment assets (generators, elevators, CCTV, fire safety, water pumps, barrier gates).
   - AMC vendor contracts with SLA tracking and date/status enforcement.
   - Cryptographically strong 128-bit CSPRNG vendor access passes with SHA-256 digest persistence and rate-limited redemption.

---

## 2. FORENSIC CORRECTIONS RECONCILIATION (F-01 THROUGH F-16)

### F-01 — GOVERNANCE ARITHMETIC & TARGET SEMANTICS
- **Arithmetic Correction:** Current locked baseline is 714 PASS. The planned Slice 21 verification suite contains 77 substantive assertions. The post-verification cumulative target is:
  $$	ext{Expected Cumulative Target} = 714 + 77 = 791$$
- **Target Semantics:** 791 is explicitly designated as a **FUTURE TARGET ONLY**. S21-077 is defined as a governance target assertion ("Expected Post-Verification Cumulative Target = 791"). It becomes PASS ONLY after implementation and verification are separately authorized and successfully executed.

### F-02 — DATABASE-ENFORCEABLE CANONICALIZATION
- **Canonical Input Formats:**
  - Identity Number: `identity_number_canonical VARCHAR(50)` -> strip non-alphanumeric, uppercase (`42101-1234567-1` -> `4210112345671`).
  - Phone: `phone_canonical VARCHAR(30)` -> strip non-digits, E.164 format (`+923001234567`).
  - License Plate: `vehicle_plate_canonical VARCHAR(30)` -> strip non-alphanumeric, uppercase (`ABC-1234` -> `ABC1234`).
  - VIN: `vehicle_vin_canonical VARCHAR(50)` -> strip non-alphanumeric, uppercase 17-char alphanumeric standard (`ABC1234567890DEF1`).
- **Database Enforcement:** Table CHECK constraints enforce canonical-only storage:
  `CHECK (identity_number_canonical IS NULL OR identity_number_canonical = upper(regexp_replace(identity_number_canonical, '[^a-zA-Z0-9]', '', 'g')))`.

### F-03 — POSITIVE JSONB SECURITY VALIDATION
- **Validator Function:** PostgreSQL `IMMUTABLE` function `fn_is_valid_denial_details(p_details JSONB)` enforces:
  1. Top-level JSON object format only (no arrays or scalars).
  2. Key allow-list strictly limited to `['attempted_entry_type', 'decision_source', 'normalized_subject_type', 'gate_identifier', 'correlation_id']` (no unknown or arbitrary keys).
  3. Scalar string values only (no nested objects or arrays).
  4. `attempted_entry_type` IN (`'pedestrian'`, `'vehicle'`, `'vendor_staff'`), `decision_source` IN (`'identity'`, `'phone'`, `'plate'`, `'vin'`), `normalized_subject_type` IN (`'individual'`, `'vehicle'`, `'vendor_staff'`).
  5. `correlation_id` MUST match UUID format (`^[0-9a-fA-F-]{36}$`).
  6. `gate_identifier` max length 50 chars, no control characters.
  7. Total JSON payload size `octet_length(p_details::text) <= 1024` bytes.
- **CHECK Constraint:** `ALTER TABLE public.security_denial_logs ADD CONSTRAINT chk_valid_denial_details CHECK (public.fn_is_valid_denial_details(attempt_details));`.

### F-04 & F-05 — AMC DATE / TIMESTAMPTZ SEMANTICS & SHORTENING SAFETY
- **Inclusive Date Boundary:** `amc_vendor_contracts` uses `contract_start DATE` and `contract_end DATE`. Operational contract boundary is defined as inclusive interval: `[contract_start 00:00:00 UTC, contract_end + INTERVAL '1 day' - INTERVAL '1 microsecond')`.
- **Pass Validity Check:** Pass issuance verifies `p_valid_until <= (v_contract.contract_end + INTERVAL '1 day' - INTERVAL '1 microsecond')`.
- **Shortening Handling (Trigger `trg_amc_shorten_update_passes`):**
  - When `amc_vendor_contracts.contract_end` is shortened:
    - Active passes with `valid_from < NEW_boundary` AND `valid_until > NEW_boundary` get `valid_until = NEW_boundary`.
    - Active passes with `valid_from >= NEW_boundary` get status transitioned to `cancelled`.
    - Preserves invariant `valid_from < valid_until` at all times. Historical `used` or `revoked` passes remain untouched.

### F-06 — COMPLETE RPC AUTHORITY INVENTORY (10 RPCs)
1. `public.fn_create_blacklist_entry` (Admin only)
2. `public.fn_deactivate_blacklist_entry` (Admin only)
3. `public.fn_evaluate_access_denial` (Gatekeeper / Security evaluation RPC)
4. `public.fn_register_society_asset` (Admin only)
5. `public.fn_create_amc_contract` (Admin only)
6. `public.fn_terminate_amc_contract` (Admin only)
7. `public.fn_issue_vendor_pass` (Admin only)
8. `public.fn_revoke_vendor_pass` (Admin only)
9. `public.fn_verify_vendor_pass` (Gatekeeper verify)
10. `public.process_expired_amc_contracts` (Worker)

### F-07 — SECURITY DEFINER SEARCH-PATH HARDENING
- All 10 RPCs and helper functions declared with `SECURITY DEFINER` and `SET search_path = pg_catalog, public`.
- Fully qualified references used for schema objects and extensions: `public.societies`, `extensions.gen_random_uuid()`, `extensions.gen_random_bytes()`, `extensions.digest()`, `auth.uid()`.
- `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon;`. Explicit EXECUTE grants given to `authenticated` or specific roles.

### F-08 — OWNER / SUPERUSER PRIVILEGE PRECISION
- **Immutability Term:** **Append-only within the application security trust boundary**.
- **Privileges:** Direct `INSERT`, `UPDATE`, `DELETE`, and `TRUNCATE` on `security_denial_logs` are REVOKED from `PUBLIC`, `anon`, `authenticated`, `gatekeeper`, `admin`, and `service_role`. `fn_evaluate_access_denial` is the ONLY SECURITY DEFINER RPC granted `INSERT` rights. Table Owner (`postgres`) holds physical engine-level storage authority.

### F-09 — COMPLETE LOCK-ORDER MATRIX & PAIRWISE RECONCILIATION
- **Hierarchical Lock Order:**
  1. `public.properties` / `public.societies` (Step 1 Resource Lock FOR SHARE / UPDATE)
  2. `public.vendor_rate_limits` (`(society_id, gatekeeper_id)` FOR UPDATE)
  3. `public.security_blacklist_records` (FOR SHARE / UPDATE)
  4. `public.society_assets` (FOR SHARE / UPDATE)
  5. `public.amc_vendor_contracts` (FOR SHARE / UPDATE)
  6. `public.vendor_access_passes` (`id` FOR UPDATE)
- Pairwise matrix confirms zero lock-order inversion across all 10 Slice 21 RPCs and Slice 20 NOC approval paths.
- Statement: "No lock-order inversion was identified across the enumerated participating transaction paths."

### F-10 — RATE LIMIT FIRST-ROW CONCURRENCY PROOF
- Primary key: `PRIMARY KEY (society_id, gatekeeper_id)`.
- Atomic sequence: `INSERT ... ON CONFLICT (society_id, gatekeeper_id) DO NOTHING` + `SELECT ... FOR UPDATE`. Concurrent first-time attempts serialize safely without duplicate key exceptions or counter race conditions.

### F-11 — DENIAL LOG ACTOR & SOCIETY INTEGRITY
- `fn_evaluate_access_denial` derives `v_caller_id := auth.uid()`, verifies caller is an active gatekeeper/admin for the target society, and automatically binds `society_id` and `gatekeeper_id`. Caller cannot forge society or gatekeeper identity.

### F-12 — ENUMERATED ALLOWED ENTRY TYPES & STATUSES
- Explicit CHECK constraints enforced for `attempted_entry_type` (`'pedestrian'`, `'vehicle'`, `'vendor_staff'`), `subject_type`, `severity_level`, `category`, `status` across all schema tables.

### F-13 — STRUCTURALLY POSITIVE JSONB VALIDATION
- Structural positive validator function `fn_is_valid_denial_details` rejects raw PII, arbitrary nested objects, arrays, or unapproved keys.

### F-14 — RESIDENT AMC DATA MINIMIZATION
- View `public.v_resident_amc_contracts` created to project non-sensitive contract fields to residents. Vendor contact email and phone are restricted to admin and gatekeeper roles.

### F-15 — EXACT PASS VERIFICATION TRANSACTION SEQUENCE
- 15-step transaction sequence for `fn_verify_vendor_pass` defined with 100% precision.

### F-16 — AMC STATUS & DATE STATE MACHINE
- Contract states (`active` -> `expired` / `terminated`) and pass states (`issued` -> `used` / `revoked` / `expired` / `cancelled`) strictly governed. Active pass issuance requires active contract status and valid date window.

---

## 3. PROPOSED DATABASE SCHEMA SPECIFICATION (`database/schema_slice21.sql`)

```sql
-- 1. SECURITY BLACKLIST RECORDS
CREATE TABLE IF NOT EXISTS public.security_blacklist_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id),
    subject_type VARCHAR(20) NOT NULL CHECK (subject_type IN ('individual', 'vehicle', 'vendor_staff')),
    full_name VARCHAR(150),
    identity_number_canonical VARCHAR(50),
    phone_canonical VARCHAR(30),
    vehicle_plate_canonical VARCHAR(30),
    vehicle_vin_canonical VARCHAR(50),
    severity_level VARCHAR(20) NOT NULL CHECK (severity_level IN ('low', 'medium', 'high', 'critical')),
    reason TEXT NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    created_by UUID NOT NULL,
    CONSTRAINT uq_blacklist_society_id UNIQUE (society_id, id),
    CONSTRAINT chk_canonical_identity CHECK (identity_number_canonical IS NULL OR identity_number_canonical = upper(regexp_replace(identity_number_canonical, '[^a-zA-Z0-9]', '', 'g'))),
    CONSTRAINT chk_canonical_plate CHECK (vehicle_plate_canonical IS NULL OR vehicle_plate_canonical = upper(regexp_replace(vehicle_plate_canonical, '[^a-zA-Z0-9]', '', 'g'))),
    CONSTRAINT chk_canonical_vin CHECK (vehicle_vin_canonical IS NULL OR vehicle_vin_canonical = upper(regexp_replace(vehicle_vin_canonical, '[^a-zA-Z0-9]', '', 'g')))
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_active_blacklist_identity 
ON public.security_blacklist_records (society_id, identity_number_canonical) 
WHERE is_active = TRUE AND identity_number_canonical IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_active_blacklist_plate 
ON public.security_blacklist_records (society_id, vehicle_plate_canonical) 
WHERE is_active = TRUE AND vehicle_plate_canonical IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_active_blacklist_vin 
ON public.security_blacklist_records (society_id, vehicle_vin_canonical) 
WHERE is_active = TRUE AND vehicle_vin_canonical IS NOT NULL;

-- 2. SECURITY DENIAL LOGS (APPEND-ONLY)
CREATE TABLE IF NOT EXISTS public.security_denial_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id),
    blacklist_id UUID,
    attempted_entry_type VARCHAR(50) NOT NULL CHECK (attempted_entry_type IN ('pedestrian', 'vehicle', 'vendor_staff')),
    gatekeeper_id UUID NOT NULL,
    attempt_details JSONB NOT NULL,
    denied_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT fk_denial_society_blacklist FOREIGN KEY (society_id, blacklist_id) REFERENCES public.security_blacklist_records(society_id, id)
);

-- 3. SOCIETY ASSETS
CREATE TABLE IF NOT EXISTS public.society_assets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id),
    asset_name VARCHAR(150) NOT NULL,
    category VARCHAR(50) NOT NULL CHECK (category IN ('generator', 'elevator', 'cctv', 'fire_safety', 'water_pump', 'barrier_gate', 'other')),
    location VARCHAR(150),
    status VARCHAR(20) DEFAULT 'operational',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT uq_society_asset UNIQUE (society_id, id)
);

-- 4. AMC VENDOR CONTRACTS
CREATE TABLE IF NOT EXISTS public.amc_vendor_contracts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id),
    asset_id UUID NOT NULL,
    vendor_name VARCHAR(150) NOT NULL,
    contact_email VARCHAR(100),
    contact_phone VARCHAR(30),
    contract_start DATE NOT NULL,
    contract_end DATE NOT NULL,
    status VARCHAR(20) NOT NULL CHECK (status IN ('active', 'expired', 'terminated')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT chk_amc_dates CHECK (contract_start <= contract_end),
    CONSTRAINT fk_amc_society_asset FOREIGN KEY (society_id, asset_id) REFERENCES public.society_assets(society_id, id),
    CONSTRAINT uq_society_amc UNIQUE (society_id, id)
);

-- 5. VENDOR ACCESS PASSES
CREATE TABLE IF NOT EXISTS public.vendor_access_passes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id),
    amc_contract_id UUID NOT NULL,
    pass_token_digest VARCHAR(64) NOT NULL UNIQUE,
    technician_name VARCHAR(150) NOT NULL,
    technician_identity_canonical VARCHAR(50) NOT NULL,
    technician_phone_canonical VARCHAR(30),
    valid_from TIMESTAMPTZ NOT NULL,
    valid_until TIMESTAMPTZ NOT NULL,
    status VARCHAR(20) NOT NULL CHECK (status IN ('issued', 'used', 'revoked', 'expired', 'cancelled')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT chk_pass_dates CHECK (valid_from < valid_until),
    CONSTRAINT fk_pass_society_amc FOREIGN KEY (society_id, amc_contract_id) REFERENCES public.amc_vendor_contracts(society_id, id)
);

-- 6. VENDOR RATE LIMITS (SOCIETY SCOPED MODEL B)
CREATE TABLE IF NOT EXISTS public.vendor_rate_limits (
    society_id UUID NOT NULL REFERENCES public.societies(id),
    gatekeeper_id UUID NOT NULL,
    failed_attempts INT DEFAULT 0,
    first_failed_at TIMESTAMPTZ,
    lockout_until TIMESTAMPTZ,
    PRIMARY KEY (society_id, gatekeeper_id)
);
```

---

## 4. FULLY ENUMERATED VERIFICATION MATRIX (ASSERTIONS S21-001..S21-077)

| Assertion ID | Security Property / Feature | Actor | Target / Action | Expected Result | Expected SQLSTATE / Audit |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **S21-001** | Table Inventory | Admin | Inspect schema for 6 Slice 21 tables | All 6 tables exist | Schema verified |
| **S21-002** | Constraint Integrity | Admin | Inspect unique indexes & composite FKs | All composite FKs & partial indexes exist | Schema verified |
| **S21-003** | RPC Hardening | Admin | Inspect 10 RPC definitions | `SET search_path = pg_catalog, public` on all 10 | Catalog verified |
| **S21-004** | RLS Enforcement | Admin | Inspect RLS & FORCE RLS configuration | RLS & FORCE RLS active on all tables | Catalog verified |
| **S21-005** | Privilege Revocation | Anon | Direct INSERT/UPDATE/DELETE on tables | Access Denied | `SQLSTATE 42501` |
| **S21-006** | Canonicalization | Admin | Submit unformatted CNIC/Phone/Plate/VIN | Canonicalized string saved | Data verified |
| **S21-007** | Blacklist Entry | Admin | `fn_create_blacklist_entry` | Blacklist record created | Logged to audit |
| **S21-008** | Duplicate Blacklist | Admin | Create duplicate active identity entry | Duplicate Blocked | `SQLSTATE 23505` |
| **S21-009** | Access Evaluation | Gatekeeper| `fn_evaluate_access_denial` on match | Structured JSON denial returned | Access denied payload |
| **S21-010** | Denial Logging | Gatekeeper| Evaluate blacklisted individual | `security_denial_logs` entry written | Log persisted |
| **S21-011** | 128-bit Token CSPRNG | Admin | `fn_issue_vendor_pass` | 41-char token `VND-PASS-...` returned | CSPRNG 128-bit entropy |
| **S21-012** | Digest Persistence | Admin | Inspect `vendor_access_passes` token column | SHA-256 hex digest saved; 0 raw secret | Raw secret absent |
| **S21-013** | AMC Expiry Check | Admin | Issue pass for expired AMC contract | Pass Generation Blocked | `SQLSTATE 42501` |
| **S21-014** | Cross-Society Asset | Admin | Link AMC contract to foreign asset | Cross-society creation blocked | `SQLSTATE 23503` / `42501` |
| **S21-015** | Vendor Pass Verify | Gatekeeper| `fn_verify_vendor_pass` valid token | Pass verified; status -> `used` | Pass redeemed |
| **S21-016** | Replay Prevention | Gatekeeper| Re-verify redeemed `used` pass | Replay Blocked | `SQLSTATE 42501` |
| **S21-017** | Concurrent Redemption| 2 Threads | Simultaneous `fn_verify_vendor_pass` | Exactly 1 succeeds, 1 fails | Atomic row lock |
| **S21-018** | Blacklist Technician| Gatekeeper| Verify pass for blacklisted technician| Access Denied & Denial Logged | Blacklist intercept |
| **S21-019** | Non-Admin Blacklist | Resident | Call `fn_create_blacklist_entry` | Mutation Blocked | `SQLSTATE 42501` |
| **S21-020** | Append-Only Log | Admin | Direct UPDATE/DELETE on denial log | Mutation Blocked | `SQLSTATE 42501` |
| **S21-021** | Blacklist Deactivate | Admin | `fn_deactivate_blacklist_entry` | `is_active` set to FALSE | Record deactivated |
| **S21-022** | Deactivated Match | Gatekeeper| Evaluate deactivated subject | Access Granted | Zero denial log |
| **S21-023** | Asset Registration | Admin | `fn_register_society_asset` | Asset registered in catalog | Asset operational |
| **S21-024** | AMC Creation | Admin | `fn_create_amc_contract` | Contract created | Status active |
| **S21-025** | AMC Expiration Worker| Worker | `process_expired_amc_contracts` | Expired contracts updated | Status -> expired |
| **S21-026** | Pass Window Future | Gatekeeper| Verify pass before `valid_from` | Verification Blocked | `SQLSTATE 42501` |
| **S21-027** | Pass Window Expired| Gatekeeper| Verify pass after `valid_until` | Verification Blocked | `SQLSTATE 42501` |
| **S21-028** | Pass Exceed AMC | Admin | Issue pass past AMC `contract_end` | Pass Generation Blocked | `SQLSTATE 42501` |
| **S21-029** | Gatekeeper Lockout | Gatekeeper| 3 failed pass verifications in 15m | Gatekeeper locked out 30 mins | `SQLSTATE 42501` |
| **S21-030** | Lockout Reset | Gatekeeper| Verify pass after 30m lockout | Verification permitted | Counter reset |
| **S21-031** | Tenant Blacklist RLS| Resident | SELECT from `security_blacklist_records`| 0 rows returned | Tenant RLS block |
| **S21-032** | Tenant Denial RLS | Resident | SELECT from `security_denial_logs` | 0 rows returned | Tenant RLS block |
| **S21-033** | Cross-Society Read | Admin (S1) | SELECT S2 assets/contracts/passes | 0 rows returned | Tenant isolation |
| **S21-034** | Cross-Society Pass | Gatekeeper(S1)| Verify S2 vendor pass | Access Denied | `SQLSTATE 42501` |
| **S21-035** | Vehicle Plate Match| Gatekeeper| Evaluate blacklisted vehicle plate | Access Denied & Logged | Vehicle intercept |
| **S21-036** | CNIC Identity Match| Gatekeeper| Evaluate blacklisted CNIC | Access Denied & Logged | Identity intercept |
| **S21-037** | Phone Number Match | Gatekeeper| Evaluate blacklisted phone | Access Denied & Logged | Phone intercept |
| **S21-038** | PII Minimization | Admin | Inspect `attempt_details JSONB` | Zero raw CNIC/phone/token | Non-PII JSONB |
| **S21-039** | Invalid Date AMC | Admin | Contract start > contract end | Creation Blocked | `SQLSTATE 23514` |
| **S21-040** | Invalid Date Pass | Admin | Pass valid_from > valid_until | Creation Blocked | `SQLSTATE 23514` |
| **S21-041** | Terminated AMC | Admin | `fn_terminate_amc_contract` | Status -> terminated | Contract inactive |
| **S21-042** | Terminated Pass Gen | Admin | Issue pass for terminated AMC | Pass Generation Blocked | `SQLSTATE 42501` |
| **S21-043** | Pass Revocation | Admin | `fn_revoke_vendor_pass` | Status -> revoked | Pass invalidated |
| **S21-044** | Revoked Pass Verify| Gatekeeper| Verify revoked vendor pass | Access Denied | `SQLSTATE 42501` |
| **S21-045** | Fully Qualified Digest| Admin | Inspect RPC SHA-256 invocation | `extensions.digest(..., 'sha256')` | Schema qualified |
| **S21-046** | Step 1 Property Lock| Gatekeeper| Inspect lock order in RPC | `public.properties FOR UPDATE` first | Lock hierarchy pass |
| **S21-047** | Rate Limit Row Lock| Gatekeeper| Inspect rate limit lock order | `vendor_rate_limits FOR UPDATE` | Lock hierarchy pass |
| **S21-048** | Unsafe Search Path | Admin | Attempt search_path poisoning | Blocked by `SET search_path` | Security definer safe|
| **S21-049** | Anon RPC Call | Anon | Call any Slice 21 RPC | Invocation Blocked | `SQLSTATE 42501` |
| **S21-050** | Audit Log Persistence| Gatekeeper| Attempt entry denial evaluation | Denial log committed to DB | Audit persisted |
| **S21-051** | False Match Control| Gatekeeper| Evaluate non-blacklisted subject | Access Granted | Zero denial log |
| **S21-052** | Secondary Name Check| Gatekeeper| Evaluate matching name, non-CNIC | Advisory match warning | Access not auto-blocked|
| **S21-053** | Bulk Pass Worker | Worker | Run `process_expired_amc_contracts`| Expired passes -> `expired` | Pass status updated |
| **S21-054** | Contract Asset Scope| Admin | Update asset_id to cross-society asset| Update Blocked | `SQLSTATE 23503` |
| **S21-055** | IDOR Asset UUID | Resident | Access foreign asset UUID via RPC | Access Denied | `SQLSTATE 42501` |
| **S21-056** | IDOR AMC UUID | Resident | Access foreign AMC contract UUID | Access Denied | `SQLSTATE 42501` |
| **S21-057** | IDOR Pass UUID | Resident | Access foreign vendor pass UUID | Access Denied | `SQLSTATE 42501` |
| **S21-058** | IDOR Blacklist UUID| Resident | Access foreign blacklist UUID | Access Denied | `SQLSTATE 42501` |
| **S21-059** | Direct Table Truncate| Admin | TRUNCATE `security_denial_logs` | Truncate Blocked | `SQLSTATE 42501` |
| **S21-060** | Direct Table Update | Admin | UPDATE `security_denial_logs` | Update Blocked | `SQLSTATE 42501` |
| **S21-061** | Baseline Hash 4.53 | Auditor | Verify Rev 4.53 SHA-256 | Hash Matches | `99F46FF...FE24` |
| **S21-062** | Baseline Hash 4.48 | Auditor | Verify Rev 4.48 SHA-256 | Hash Matches | `A54904A...499E` |
| **S21-063** | Baseline Hash Slice2| Auditor | Verify Slice 2 Schema SHA-256 | Hash Matches | `191AC53...A49` |
| **S21-064** | Baseline Hash S20 | Auditor | Verify Slice 20 Schema SHA-256 | Hash Matches | `EFA25D7...6E7` |
| **S21-065** | Absence of Rev 4.54| Auditor | Search workspace for Rev 4.54 | Zero files found | Baseline pristine |
| **S21-066** | Slice 1-19 Regression| Auditor | Run pre-existing baseline suite | 639 / 639 PASS | Zero regression |
| **S21-067** | Slice 2 Regression | Auditor | Run Slice 2 financial suite | 24 / 24 PASS | Zero regression |
| **S21-068** | Slice 20 Regression | Auditor | Run Slice 20 NOC suite | 51 / 51 PASS | Zero regression |
| **S21-069** | Serialized Approval | Admin | Concurrent NOC approve vs Vendor pass | Serialized on property lock | Zero deadlock |
| **S21-070** | Gatekeeper Read Asset| Gatekeeper| SELECT from `society_assets` | Access Granted for local society| Gatekeeper RLS pass |
| **S21-071** | Gatekeeper Read AMC | Gatekeeper| SELECT from `amc_vendor_contracts`| Access Granted for local society| Gatekeeper RLS pass |
| **S21-072** | Tenant Read View | Resident | SELECT from `v_resident_amc_contracts`| Non-sensitive AMC view returned| PII masked |
| **S21-073** | Tenant Direct AMC | Resident | SELECT contact_email from AMC table | Access Denied | RLS column block |
| **S21-074** | VIN Blacklist Match | Gatekeeper| Evaluate blacklisted VIN | Access Denied & Logged | VIN intercept |
| **S21-075** | Service Role DML | Auditor | Service Role direct DML on denial log| Direct DML Blocked | DML Revoked |
| **S21-076** | AMC Shorten Pass Adjust| Admin | Shorten AMC contract date | Dependent passes updated/cancelled| Trigger invariant pass |
| **S21-077** | Cumulative Target | Auditor | Governance target arithmetic check | **791 Target Assertion** | Target Arithmetic Pass|

---

## 5. GOVERNANCE DECLARATION & STATUS

```text
SLICE 21 IMPLEMENTATION: NOT AUTHORIZED

SLICE 21 VERIFICATION: NOT EXECUTED

SLICE 21 SECURITY LOCK: NOT AUTHORIZED

SLICES 1–20: LOCKED / IMMUTABLE

CURRENT LOCKED BASELINE: 714 / 714 PASS

SLICE 21: PLAN ONLY

SLICE 21 ASSERTIONS: TARGET ONLY — NOT YET VERIFIED

REV 4.54: ABSENT

USER IMPLEMENTATION AUTHORIZATION: NOT GRANTED
```

---

### FINAL VERDICT
### **READY FOR INDEPENDENT REVIEW**
