# SLICE 20 — FINAL IMPLEMENTATION & SECURITY PLAN (REVISION 3)

**Execution Date:** September 7, 2026  
**Target Repository:** `D:\Clients Applications\SU Society App`  
**Mode:** **PLAN REVISION ONLY / ZERO IMPLEMENTATION AUTHORIZATION**  
**Slice:** 20  
**Feature:** Resident Move-In / Move-Out Digital NOC Clearance & Property Transfer Workflow  
**Current Locked Baseline:** **639 / 639 PASS (100%)**  
**Locked Scope:** **SLICES 1–19 — IMMUTABLE**  

---

## 1. EXECUTIVE VERDICT & REVISION 3 HIGHLIGHTS

This document establishes the final, implementation-ready **Implementation & Security Plan (Revision 3)** for **Slice 20 — Resident Move-In / Move-Out Digital NOC Clearance Requests & Property Transfer Workflow** of the SU Society App.

Revision 3 addresses and closes every remaining implementation blocker identified during independent architectural review of Revision 2.

### Critical Revision 3 Engineering Solves:
1. **True Financial Clearance Serialization (Blocker #1):** Uses parent resource locking on `public.properties` (`FOR UPDATE`) AND transactional advisory locking (`pg_advisory_xact_lock`) during financial dues evaluation and NOC approval. Completely eliminates TOCTOU (Time-of-Check to Time-of-Use) race conditions against concurrent ledger postings.
2. **Strict Pass Generation Rejection for Property Sale NOCs (Blocker #2):** `generate_noc_move_pass` RPC strictly rejects `property_sale_noc` requests at the database level. Move passes are restricted exclusively to `move_in` and `move_out`.
3. **Internally Consistent Pass Lifecycle — Option B Multiple Historical / Single Active (Blocker #3):** Implements Option B. Drops simple `noc_request_id UNIQUE` constraint on passes. Uses Partial Unique Index `uq_active_noc_move_pass` to enforce at most ONE `active` pass per NOC request. Re-issuing/replacing a pass automatically revokes the prior active pass while retaining full historical audit records.
4. **Persistent Server-Side Gatekeeper Rate Limiting (Blocker #4):** Introduces database table `public.noc_gatekeeper_rate_limits`. Tracks gatekeeper verification attempts persistently across browser sessions, IP changes, and pass tokens. Enforces 10-failure / 10-minute rolling window guard lockouts.
5. **Concrete Move-In Occupancy & Tenancy Activation (Blocker #5):** Move-in gate check-in verification atomically executes server-authoritative tenancy status updates (`status = 'active'`) or property occupancy updates (`occupancy_status = 'occupied'`).
6. **Move-Out Owner vs Tenant Semantics (Blocker #6):** Move-out check-out verification terminates tenant tenancies (`end_date = CURRENT_DATE`, `status = 'terminated'`). For owner move-outs, updates occupancy status while leaving property ownership records in `public.property_owners` **100% UNTOUCHED** (deferred to Slice 24).
7. **Two-Layer Expiration Enforcement (Blocker #7):** Real-time gate verification RPC evaluates `NOW() > valid_until` to reject expired passes instantly, complemented by batch RPC `process_expired_noc_passes()`.
8. **Request-Type-Specific Checklist & Category RBAC (Blocker #8):** `move_in`/`move_out` use physical move checklists (`financial_dues`, `facility_inspection`, `keys_access_cards`, `admin_signoff`), whereas `property_sale_noc` uses administrative transfer checklists (`financial_dues`, `legal_title_verification`, `admin_signoff`).
9. **Expanded 69 Assertion Matrix:** 69 planned assertions (`S20-001` through `S20-069`), raising the cumulative verified target to **708 / 708 PASS**.

---

## 2. LOCKED BASELINE & REPOSITORY EVIDENCE

The current project baseline is immutable and permanently locked:

```text
=====================================================

SLICES 1–18 LOCKED BASELINE:     595 / 595 PASS (100%)

SLICE 19 VERIFIED SUITE:          44 /  44 PASS (100%)

-----------------------------------------------------

CUMULATIVE LOCKED BASELINE:      639 / 639 PASS (100%)
CUMULATIVE STATUS:               100%

INDEPENDENT SECURITY AUDIT:      PASSED
SECURITY FINDINGS:               0

SLICES 1–19 STATUS:              SECURITY LOCKED
                                 AND IMMUTABLE

=====================================================
```

### Authoritative Database & Codebase Inspection Evidence:
1. **Property Infrastructure (`schema_slice1.sql`):** Table `public.properties` contains a unique primary key `id` for every registered society property. This stable row serves as the parent lock resource for financial serialization.
2. **Financial Ledger Infrastructure (`schema_slice2.sql`, `schema_slice9.sql`, `schema_slice14.sql`):** Net balance for a property is calculated via `public.fn_get_property_outstanding_balance(property_id)` as `SUM(debits) - SUM(credits)`. Charges (`public.maintenance_charges`) and payments (`public.payments`) post debits/credits to `public.ledger_transactions`.
3. **User Roles (`schema_slice1.sql`):** Supported RBAC roles in `public.user_roles`: `super_admin`, `admin`, `secretary`, `treasurer`, `member`, `tenant`, `gatekeeper`, `technician`.
4. **Passcode & Cryptographic Standards (`schema_slice19.sql`):** Uses `extensions.crypt` with `extensions.gen_salt('bf', 8)` for bcrypt KDF.

---

## 3. BLOCKER-BY-BLOCKER ENGINEERING SPECIFICATION

### BLOCKER 1: TRUE FINANCIAL CLEARANCE SERIALIZATION
* **Problem:** Simply querying `SUM(debits) - SUM(credits)` under an NOC row lock does not prevent concurrent financial posting RPCs (`fn_generate_charge`, `fn_process_payment`) from inserting new ledger rows after dues calculation but before NOC approval commits.
* **Revision 3 Solution:** Dual-layer parent serialization:
  1. *Parent Row Lock:* Before reading ledger transactions in `perform_financial_dues_clearance` or `approve_noc_request`, the RPC locks the parent property row:  
     `PERFORM 1 FROM public.properties WHERE id = v_property_id FOR UPDATE;`
  2. *Transactional Advisory Lock:* The RPC acquires a transaction-level advisory lock hashed on property ID:  
     `PERFORM pg_advisory_xact_lock(hashtext('noc_financial_lock:' || v_property_id::text));`
  This guarantees 100% mutual exclusion between NOC approval revalidation and concurrent financial ledger mutations without requiring modifications to locked Slices 1–19 SQL routines.

### BLOCKER 2: PROPERTY-SALE NOC PASS GENERATION REJECTION
* **Problem:** Property sale NOCs are administrative clearance documents and must never produce gate move passes for mover trucks.
* **Revision 3 Solution:** RPC `generate_noc_move_pass` contains an explicit server-side guard:
  ```sql
  SELECT * INTO v_noc FROM public.noc_requests WHERE id = p_noc_request_id FOR UPDATE;
  IF v_noc.request_type = 'property_sale_noc' THEN
      RAISE EXCEPTION 'Property sale NOC cannot generate gate move pass.' USING ERRCODE = '22000';
  END IF;
  IF v_noc.request_type NOT IN ('move_in', 'move_out') THEN
      RAISE EXCEPTION 'Invalid request type for move pass generation.' USING ERRCODE = '22000';
  END IF;
  ```

### BLOCKER 3: MOVE-PASS LIFECYCLE (OPTION B: MULTIPLE HISTORICAL / SINGLE ACTIVE)
* **Problem:** Ambiguity between single immutable pass vs pass replacement/regeneration.
* **Revision 3 Solution:** Implements Option B.
  - Drops simple `noc_request_id UNIQUE` constraint on `public.noc_move_passes`.
  - Enforces single active pass using Partial Unique Index:
    `CREATE UNIQUE INDEX uq_active_noc_move_pass ON public.noc_move_passes (noc_request_id) WHERE status = 'active';`
  - Pass Replacement/Re-issuance Workflow: When `generate_noc_move_pass` is called for an approved NOC:
    1. Lock NOC request row (`FOR UPDATE`).
    2. Revoke any existing active pass:  
       `UPDATE public.noc_move_passes SET status = 'revoked', updated_at = NOW() WHERE noc_request_id = p_noc_request_id AND status = 'active';`
    3. Insert new pass record with fresh CSPRNG PIN, fresh bcrypt hash, and fresh `pass_token`.

### BLOCKER 4: PERSISTENT GATEKEEPER RATE LIMITING
* **Problem:** Transient in-memory counters fail across multiple gatekeeper sessions or server restarts.
* **Revision 3 Solution:** Introduces persistent table `public.noc_gatekeeper_rate_limits`:
  ```sql
  CREATE TABLE IF NOT EXISTS public.noc_gatekeeper_rate_limits (
      id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      society_id      UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
      gatekeeper_id   UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
      failed_count    INTEGER NOT NULL DEFAULT 1,
      window_start    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      lockout_until   TIMESTAMPTZ,
      created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT uq_gatekeeper_rate_limit UNIQUE (society_id, gatekeeper_id)
  );
  ```
  During `verify_noc_move_pass`:
  - Check per-pass lockout on `noc_move_passes.lockout_until`.
  - Check per-gatekeeper lockout on `noc_gatekeeper_rate_limits.lockout_until`.
  - If a gatekeeper accumulates 10 failed pass verifications within 10 minutes, `noc_gatekeeper_rate_limits.lockout_until` is set to `NOW() + INTERVAL '15 minutes'`.

### BLOCKER 5: CONCRETE MOVE-IN OCCUPANCY & TENANCY ACTIVATION
* **Problem:** Vague description of move-in completion side-effects.
* **Revision 3 Solution:** When `verify_noc_move_pass` verifies a move-in pass (`move_direction = 'in'`) at the gate:
  ```sql
  IF v_pass.move_direction = 'in' AND v_noc.request_type = 'move_in' THEN
      -- If requester is tenant, activate tenancy
      UPDATE public.tenancies 
      SET status = 'active', updated_at = NOW() 
      WHERE property_id = v_noc.property_id 
        AND tenant_id = v_noc.requester_id 
        AND status IN ('pending', 'approved');
        
      -- Update property occupancy status
      UPDATE public.properties 
      SET occupancy_status = 'occupied', updated_at = NOW() 
      WHERE id = v_noc.property_id;
  END IF;
  ```

### BLOCKER 6: MOVE-OUT OWNER VS TENANT SEMANTICS
* **Problem:** Ambiguity in move-out handling for owners vs tenants.
* **Revision 3 Solution:** When `verify_noc_move_pass` verifies a move-out pass (`move_direction = 'out'`) at the gate:
  ```sql
  IF v_pass.move_direction = 'out' AND v_noc.request_type = 'move_out' THEN
      -- 1. Tenant Move-Out: Terminate active tenancy
      UPDATE public.tenancies 
      SET end_date = CURRENT_DATE, status = 'terminated', updated_at = NOW() 
      WHERE property_id = v_noc.property_id 
        AND tenant_id = v_noc.requester_id 
        AND (end_date IS NULL OR end_date >= CURRENT_DATE);
        
      -- 2. Owner Move-Out: Update property occupancy status to vacant
      UPDATE public.properties 
      SET occupancy_status = 'vacant', updated_at = NOW() 
      WHERE id = v_noc.property_id;
      
      -- Property Ownership records in public.property_owners are 100% UNTOUCHED!
  END IF;
  ```

### BLOCKER 7: REAL-TIME & BATCH PASS EXPIRATION MECHANISM
* **Problem:** Delayed scheduler job might allow expired passes to be verified.
* **Revision 3 Solution:** Two-layer expiration defense:
  1. *Real-Time Verification Gate:* Inside `verify_noc_move_pass`, the RPC evaluates:  
     `IF NOW() > v_pass.valid_until THEN UPDATE public.noc_move_passes SET status = 'expired' WHERE id = v_pass.id; RAISE EXCEPTION 'Pass expired' USING ERRCODE = '22000'; END IF;`
  2. *Batch Expiry RPC:* Routine `public.process_expired_noc_passes()` runs periodically:  
     `UPDATE public.noc_move_passes SET status = 'expired', updated_at = NOW() WHERE status = 'active' AND valid_until < NOW();`

### BLOCKER 8: REQUEST-TYPE-SPECIFIC CHECKLIST MODEL
* **Checklist Initialization Rules in `submit_noc_request`:**
  - `move_in` & `move_out`: Initializes 4 categories (`financial_dues`, `facility_inspection`, `keys_access_cards`, `admin_signoff`).
  - `property_sale_noc`: Initializes 3 categories (`financial_dues`, `legal_title_verification`, `admin_signoff`).

---

## 4. COMPLETE NOC STATE MACHINE

The NOC request state machine is strictly enforced server-side via RPC routines under parent row locking:

| Current State | Next State | Authorized Actor | Preconditions & Validation | DB Enforcement | Audit Event |
| :--- | :--- | :--- | :--- | :--- | :--- |
| *None* | `submitted` | Resident (Owner/Tenant) | Requester authorized for property; `property_sale_noc` requires primary owner; no active NOC exists. | Partial Unique Index `uq_active_noc_request` | `noc_request_submitted` |
| `submitted` | `dues_pending` | Treasurer / System RPC | Dues audit executed; net ledger balance > 0. | RPC `perform_financial_dues_clearance` | `noc_dues_audit_flagged` |
| `submitted` / `dues_pending` | `clearance_in_progress` | Department Roles | Net ledger balance <= 0; checklist items open. | RPC state check | `noc_clearance_started` |
| `clearance_in_progress` | `approved` | Secretary / Admin | Dues revalidated balance <= 0; 100% of checklist items status = `'cleared'`. | Atomic RPC transaction with `FOR UPDATE` | `noc_request_approved` |
| `submitted` / `dues_pending` / `clearance_in_progress` | `rejected` | Admin / Secretary | Outstanding dues unpaid or facility inspection failed; rejection reason provided. | RPC `reject_noc_request` | `noc_request_rejected` |
| `submitted` / `dues_pending` / `clearance_in_progress` | `cancelled` | Requester Resident | Request in non-final state; `auth.uid() = requester_id`. | Requester identity match | `noc_request_cancelled` |
| `approved` | `completed` | Gatekeeper (Guard) | Move pass validated at gate; mover truck check-in/out timestamped. | RPC `verify_noc_move_pass` | `noc_move_completed` |
| `approved` | `expired` | System RPC / Real-Time | `move_date` passed + 48 hours without gate verification. | Expiry state check | `noc_request_expired` |

---

## 5. DATABASE DESIGN & PROPOSED TABLES

Slice 20 introduces 4 core domain tables to `public` schema:

### 1. `public.noc_requests`
```sql
CREATE TABLE IF NOT EXISTS public.noc_requests (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id          UUID        NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    property_id         UUID        NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
    unit_id             UUID        REFERENCES public.units(id) ON DELETE RESTRICT,
    requester_id        UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    request_type        VARCHAR(30) NOT NULL CONSTRAINT chk_noc_request_type CHECK (
                                        request_type IN ('move_in', 'move_out', 'property_sale_noc')
                                    ),
    status              VARCHAR(30) NOT NULL DEFAULT 'submitted' CONSTRAINT chk_noc_status CHECK (
                                        status IN ('submitted', 'dues_pending', 'clearance_in_progress', 'approved', 'rejected', 'cancelled', 'completed', 'expired')
                                    ),
    move_date           DATE        NOT NULL,
    reason_notes        TEXT,
    evidence_reference  TEXT,
    rejection_reason    TEXT,
    certificate_number  VARCHAR(60),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### 2. `public.noc_clearance_checklists`
```sql
CREATE TABLE IF NOT EXISTS public.noc_clearance_checklists (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    noc_request_id      UUID        NOT NULL REFERENCES public.noc_requests(id) ON DELETE CASCADE,
    clearance_category  VARCHAR(50) NOT NULL CONSTRAINT chk_noc_clearance_cat CHECK (
                                        clearance_category IN ('financial_dues', 'facility_inspection', 'keys_access_cards', 'legal_title_verification', 'admin_signoff')
                                    ),
    status              VARCHAR(30) NOT NULL DEFAULT 'pending' CONSTRAINT chk_noc_clearance_status CHECK (
                                        status IN ('pending', 'cleared', 'flagged')
                                    ),
    remarks             TEXT,
    cleared_by          UUID        REFERENCES public.users(id) ON DELETE RESTRICT,
    cleared_at          TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_noc_category UNIQUE (noc_request_id, clearance_category)
);
```

### 3. `public.noc_move_passes`
```sql
CREATE TABLE IF NOT EXISTS public.noc_move_passes (
    id                          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    noc_request_id              UUID        NOT NULL REFERENCES public.noc_requests(id) ON DELETE CASCADE,
    pass_token                  VARCHAR(50) NOT NULL UNIQUE,
    pass_code_hash              VARCHAR(255) NOT NULL,
    valid_from                  TIMESTAMPTZ NOT NULL,
    valid_until                 TIMESTAMPTZ NOT NULL,
    authorized_vehicle_number   VARCHAR(30),
    mover_details               TEXT,
    move_direction              VARCHAR(10) NOT NULL DEFAULT 'out' CONSTRAINT chk_pass_direction CHECK (move_direction IN ('in', 'out')),
    status                      VARCHAR(30) NOT NULL DEFAULT 'active' CONSTRAINT chk_move_pass_status CHECK (
                                                status IN ('active', 'used', 'expired', 'revoked')
                                            ),
    failed_attempts             INTEGER     NOT NULL DEFAULT 0 CONSTRAINT chk_pass_failed_attempts CHECK (failed_attempts >= 0),
    lockout_until               TIMESTAMPTZ,
    check_in_time               TIMESTAMPTZ,
    check_out_time              TIMESTAMPTZ,
    gatekeeper_id               UUID        REFERENCES public.users(id) ON DELETE RESTRICT,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_pass_validity_window CHECK (valid_from < valid_until)
);
```

### 4. `public.noc_gatekeeper_rate_limits`
```sql
CREATE TABLE IF NOT EXISTS public.noc_gatekeeper_rate_limits (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id      UUID        NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    gatekeeper_id   UUID        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    failed_count    INTEGER     NOT NULL DEFAULT 1,
    window_start    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lockout_until   TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_gatekeeper_rate_limit UNIQUE (society_id, gatekeeper_id)
);
```

---

## 6. CONSTRAINTS & INDEXES

1. **Single Active NOC Request Per Property & Type:**
   ```sql
   CREATE UNIQUE INDEX IF NOT EXISTS uq_active_noc_request 
   ON public.noc_requests (property_id, request_type) 
   WHERE status IN ('submitted', 'dues_pending', 'clearance_in_progress', 'approved');
   ```
2. **Single Active Move Pass Per NOC Request (Option B Lifecycle):**
   ```sql
   CREATE UNIQUE INDEX IF NOT EXISTS uq_active_noc_move_pass 
   ON public.noc_move_passes (noc_request_id) 
   WHERE status = 'active';
   ```
3. **Public Pass Token Index ($O(1)$ Gate Verification Lookup):**
   ```sql
   CREATE UNIQUE INDEX IF NOT EXISTS idx_noc_move_passes_token 
   ON public.noc_move_passes (pass_token);
   ```

---

## 7. RLS & FORCE RLS POLICIES

All 4 tables strictly enforce `ENABLE` and `FORCE ROW LEVEL SECURITY`:

```sql
ALTER TABLE public.noc_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.noc_requests FORCE ROW LEVEL SECURITY;

ALTER TABLE public.noc_clearance_checklists ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.noc_clearance_checklists FORCE ROW LEVEL SECURITY;

ALTER TABLE public.noc_move_passes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.noc_move_passes FORCE ROW LEVEL SECURITY;

ALTER TABLE public.noc_gatekeeper_rate_limits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.noc_gatekeeper_rate_limits FORCE ROW LEVEL SECURITY;
```

### Restrictive DML Direct Access Blocking:
Direct DML from client connections is strictly blocked across all 4 tables:

```sql
CREATE POLICY pol_noc_requests_restrictive_insert ON public.noc_requests AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (false);
CREATE POLICY pol_noc_requests_restrictive_update ON public.noc_requests AS RESTRICTIVE FOR UPDATE TO authenticated USING (false);
CREATE POLICY pol_noc_requests_restrictive_delete ON public.noc_requests AS RESTRICTIVE FOR DELETE TO authenticated USING (false);

-- (Identical restrictive DML policies applied to noc_clearance_checklists, noc_move_passes, and noc_gatekeeper_rate_limits)
```

---

## 8. HARDENED SECURITY DEFINER RPC ROUTINES (9 RPCs TOTAL)

All business procedures specify `SET search_path = public, extensions, pg_temp`:

1. `public.submit_noc_request`: Submits NOC application; verifies property ownership/tenancy; initializes request-type-specific checklists.
2. `public.perform_financial_dues_clearance`: Evaluates net ledger balance under `public.properties` row lock (`FOR UPDATE`) and `pg_advisory_xact_lock`.
3. `public.update_clearance_checklist_item`: Enforces category-specific RBAC roles (`treasurer`, `technician`, `secretary`, `admin`).
4. `public.approve_noc_request`: Atomic approval revalidating dues under parent property row lock; generates certificate number `NOC-2026-YYYYYY`.
5. `public.reject_noc_request`: Rejects NOC request with reason.
6. `public.cancel_noc_request`: Cancels NOC request by requester resident.
7. `public.generate_noc_move_pass`: Generates move pass for `move_in`/`move_out` NOCs; strictly rejects `property_sale_noc`; revokes prior active pass; returns CSPRNG PIN once.
8. `public.verify_noc_move_pass`: Verifies `pass_token` + PIN + vehicle reg; enforces dual-tier persistent rate-limiting; updates pass status to `used`; executes tenancy termination or occupancy activation.
9. `public.process_expired_noc_passes`: Batch process marking expired passes (`valid_until < NOW()`).

---

## 9. FINANCIAL CONCURRENCY MATRIX

| Operation | Concurrent Operation | Serialization Primitive | Guaranteed Result |
| :--- | :--- | :--- | :--- |
| NOC Dues Audit | Charge Generation (`fn_generate_charge`) | `properties` row lock + `pg_advisory_xact_lock` | Charge is included in balance audit or blocked until audit commits. |
| NOC Approval Revalidation | Payment Verification (`fn_process_payment`) | `properties` row lock + `pg_advisory_xact_lock` | Approval sees exact committed ledger balance; zero stale approval. |
| NOC Approval Revalidation | Payment Reversal (`fn_reverse_payment`) | `properties` row lock + `pg_advisory_xact_lock` | Payment reversal debit is observed; approval aborts if balance > 0. |
| Pass Verification | Pass Verification (Guard A & Guard B) | `noc_move_passes` row lock `FOR UPDATE` | Exactly one verification succeeds (`status = 'used'`); second attempt fails with `22000`. |
| Pass Generation | Pass Generation (Re-issuance) | `noc_requests` row lock `FOR UPDATE` | Prior active pass revoked (`status = 'revoked'`); exactly one active pass created. |

---

## 10. THREAT MODEL & MITIGATION MATRIX

| Threat ID | Threat Vector | Severity | Mitigation Strategy | Enforcement Layer | Verification Assertion |
| :--- | :--- | :---: | :--- | :--- | :--- |
| **TM20-01** | IDOR / Unauthorized Property NOC Submission | High | RPC verifies `auth.uid()` against `property_owners` / `tenancies`. | RPC Security Gate | `S20-013` |
| **TM20-02** | Cross-Society Data Access / Manipulation | High | Strict `society_id` check via `public.get_user_society_id()`. | RPC Tenant Gate | `S20-011` |
| **TM20-03** | Fake Financial Clearance (Client Dues Bypass) | Critical | Dues clearance is 100% server-calculated in SQL from `ledger_transactions`. | SQL Ledger Query | `S20-022` |
| **TM20-04** | Stale Financial Clearance / TOCTOU Race | Critical | Approval revalidates dues under `properties` row lock & `pg_advisory_xact_lock`. | Parent Row Lock | `S20-026` |
| **TM20-05** | Property Sale Pass Generation Bypass | High | `generate_noc_move_pass` explicitly rejects `property_sale_noc` requests. | RPC Guard | `S20-020` |
| **TM20-06** | Pass Replay / Concurrent Verification | High | Atomic state transition `status = 'active'` -> `'used'` under `FOR UPDATE`. | DB Transaction | `S20-051` |
| **TM20-07** | Persistent Guard PIN Brute-Force Scanning | High | Dual-tier persistent rate limiting via `noc_gatekeeper_rate_limits` table. | Rate Limit Table | `S20-049` |
| **TM20-08** | Unauthorized Category Checklist Sign-off | Medium | Category-specific RBAC check (`treasurer`, `technician`, `secretary`). | RPC RBAC Gate | `S20-031` |
| **TM20-09** | Oracle Information Leakage via Verification | Medium | Generic error `22000` returned for all verification failure modes. | RPC Exception Handler | `S20-050` |
| **TM20-10** | Plaintext PIN Leakage in Audit Logs | High | Plaintext PINs and bcrypt hashes stripped from audit JSON payloads. | Audit Redactor | `S20-065` |
| **TM20-11** | Direct Client API Table Mutation Bypass | High | `ENABLE` & `FORCE RLS` with restrictive `USING (false)` DML policies. | PostgreSQL RLS Engine | `S20-060` |

---

## 11. REVISED S20 ASSERTION MATRIX (69 ASSERTIONS)

Slice 20 Revision 3 defines **69 detailed test assertions (`S20-001` through `S20-069`)**:

| Test ID | Test Assertion Description | Planned Outcome |
| :--- | :--- | :---: |
| **S20-001** | 4 New NOC Tables Exist (`noc_requests`, `checklists`, `passes`, `rate_limits`) | PASS |
| **S20-002** | Partial Unique Index `uq_active_noc_request` Exists | PASS |
| **S20-003** | Partial Unique Index `uq_active_noc_move_pass` Exists | PASS |
| **S20-004** | Public Token Unique Index `idx_noc_move_passes_token` Exists | PASS |
| **S20-005** | Persistent Rate Limit Unique Index `uq_gatekeeper_rate_limit` Exists | PASS |
| **S20-006** | Foreign Key Reference Constraints Intact Across All 4 Tables | PASS |
| **S20-007** | 9 NOC RPC Routines Exist | PASS |
| **S20-008** | SECURITY DEFINER & `search_path` Hardened on All 9 RPCs | PASS |
| **S20-009** | RLS & FORCE RLS Enabled on All 4 Tables | PASS |
| **S20-010** | Anonymous `submit_noc_request` Blocked (`42501`) | PASS |
| **S20-011** | Cross-Society NOC Request Submission Blocked | PASS |
| **S20-012** | Anonymous `verify_noc_move_pass` Blocked (`42501`) | PASS |
| **S20-013** | Valid Resident Move-In NOC Request Submission | PASS |
| **S20-014** | Valid Resident Move-Out NOC Request Submission | PASS |
| **S20-015** | Move-In/Move-Out Initialization of 4 Physical Move Checklist Items | PASS |
| **S20-016** | Property Sale Initialization of 3 Administrative Checklist Items | PASS |
| **S20-017** | Duplicate Active NOC Request Blocked by Index | PASS |
| **S20-018** | Property Sale NOC Submission by Non-Owner Blocked (`42501`) | PASS |
| **S20-019** | Valid Property Sale NOC Submission by Primary Owner | PASS |
| **S20-020** | Property Sale NOC Move Pass Generation Rejected (`22000`) | PASS |
| **S20-021** | Property Sale NOC Approval Does NOT Mutate `property_owners` | PASS |
| **S20-022** | Server-Authoritative Dues Audit Execution (Dues Present -> Flagged) | PASS |
| **S20-023** | Server-Authoritative Dues Audit Execution (Zero Dues -> Cleared) | PASS |
| **S20-024** | Credit Dues Balance Calculation (Negative Dues -> Cleared) | PASS |
| **S20-025** | Dues Audit Locks Parent `properties` Row (`FOR UPDATE`) | PASS |
| **S20-026** | Financial Concurrency: Concurrent Charge Posting Observed During Approval | PASS |
| **S20-027** | Financial Concurrency: Simultaneous Approvals Serialized Safely | PASS |
| **S20-028** | Financial Concurrency: Debit Created Before Approval Aborts Approval | PASS |
| **S20-029** | Financial Concurrency: Zero Balance Approval Aborts If Dues Accrue | PASS |
| **S20-030** | Admin Departmental Checklist Item Clearance (`facility_inspection`) | PASS |
| **S20-031** | Category Checklist Update by Unauthorized Role Blocked (`42501`) | PASS |
| **S20-032** | Technician Role Clearance of Facility Inspection Item | PASS |
| **S20-033** | Treasurer Role Clearance of Financial Dues Item | PASS |
| **S20-034** | NOC Approval Blocked When Checklist Items Pending or Flagged | PASS |
| **S20-035** | Valid NOC Approval When 100% Checklist Items Cleared | PASS |
| **S20-036** | Non-Secretary / Non-Admin NOC Approval Blocked | PASS |
| **S20-037** | Admin NOC Rejection Execution | PASS |
| **S20-038** | Requester NOC Cancellation Execution | PASS |
| **S20-039** | CSPRNG 6-Digit PIN Generation & Bcrypt Salted Hash Storage | PASS |
| **S20-040** | Plaintext PIN Excluded From Database Tables & Audit Logs | PASS |
| **S20-041** | Public Lookup Pass Token (`PASS-2026-XXXXX`) Generation | PASS |
| **S20-042** | Move Pass Generation Blocked for Unapproved NOC Request | PASS |
| **S20-043** | Pass Re-issuance Automatically Revokes Prior Active Pass (Option B) | PASS |
| **S20-044** | Vehicle Registration SQL Normalization Execution | PASS |
| **S20-045** | Gatekeeper Verification Supply Mismatched Vehicle Reg Blocked | PASS |
| **S20-046** | Valid Vehicle Registration Match Gatekeeper Verification | PASS |
| **S20-047** | Gatekeeper Valid Move Pass Verification Execution | PASS |
| **S20-048** | Per-Pass Lockout Defense (5 Pass Failures -> 15 Min Lockout) | PASS |
| **S20-049** | Persistent Gatekeeper Lockout (10 Failures -> 15 Min Guard Lockout) | PASS |
| **S20-050** | Generic Error (`22000`) Returned on Verification Failures | PASS |
| **S20-051** | Move Pass Replay Blocked After Status = `used` | PASS |
| **S20-052** | Expired Move Pass Verification Blocked | PASS |
| **S20-053** | Move-In Verification Activates Tenant Tenancy (`status = 'active'`) | PASS |
| **S20-054** | Move-In Verification Updates Property Occupancy (`occupancy_status = 'occupied'`) | PASS |
| **S20-055** | Move-Out Verification Terminates Tenant Tenancy (`end_date = CURRENT_DATE`) | PASS |
| **S20-056** | Owner Move-Out Verification Updates Occupancy Without Ownership Mutation | PASS |
| **S20-057** | Real-Time Expiration Rejection During Gate Verification | PASS |
| **S20-058** | Batch Process `process_expired_noc_passes()` Execution | PASS |
| **S20-059** | Delayed Scheduler Execution Does NOT Allow Expired Pass Access | PASS |
| **S20-060** | Direct `noc_requests` DML Blocked by Restrictive RLS | PASS |
| **S20-061** | Direct `noc_clearance_checklists` DML Blocked by Restrictive RLS | PASS |
| **S20-062** | Direct `noc_move_passes` DML Blocked by Restrictive RLS | PASS |
| **S20-063** | Direct `noc_gatekeeper_rate_limits` DML Blocked by Restrictive RLS | PASS |
| **S20-064** | Audit Log Created for NOC Request Submission & Approval | PASS |
| **S20-065** | Audit Log Redaction (Plaintext Passcode Excluded) | PASS |
| **S20-066** | Real-Time Notification Scoping (Requester & Admins Only) | PASS |
| **S20-067** | Notification Payloads Exclude PINs & Financial Amounts | PASS |
| **S20-068** | Financial Non-Interference (Zero Ledger Mutations) | PASS |
| **S20-069** | Cumulative Baseline Suite Target Reached (708/708 PASS) | PASS |

---

## 12. IMPLEMENTATION FILE PLAN

At eventual implementation authorization:
1. `[NEW] database/schema_slice20.sql`: DDL for 4 tables, indexes, RLS policies, and 9 hardened SECURITY DEFINER RPC routines.
2. `[NEW] database/verify_slice20.sql`: Assertion script executing 69 tests (`S20-001` through `S20-069`).
3. `[NEW] scratch/run_all20.ps1`: PowerShell test runner script executing regression Slices 1–19 followed by Slice 20.
4. `[MODIFY] src/supabase.js`: Append Slice 20 API methods (`mockClient.noc`).
5. `[MODIFY] src/App.jsx`: Integrate `NocManagerView` component and navigation tab.

---

## 13. DETERMINISTIC ROLLBACK PLAN

If Slice 20 implementation fails during execution:
1. Drop Slice 20 database objects:
   `DROP TABLE IF EXISTS public.noc_gatekeeper_rate_limits CASCADE;`
   `DROP TABLE IF EXISTS public.noc_move_passes CASCADE;`
   `DROP TABLE IF EXISTS public.noc_clearance_checklists CASCADE;`
   `DROP TABLE IF EXISTS public.noc_requests CASCADE;`
2. Drop Slice 20 RPC routines:
   `DROP FUNCTION IF EXISTS public.submit_noc_request;`
   `DROP FUNCTION IF EXISTS public.perform_financial_dues_clearance;`
   `DROP FUNCTION IF EXISTS public.update_clearance_checklist_item;`
   `DROP FUNCTION IF EXISTS public.approve_noc_request;`
   `DROP FUNCTION IF EXISTS public.reject_noc_request;`
   `DROP FUNCTION IF EXISTS public.cancel_noc_request;`
   `DROP FUNCTION IF EXISTS public.generate_noc_move_pass;`
   `DROP FUNCTION IF EXISTS public.verify_noc_move_pass;`
   `DROP FUNCTION IF EXISTS public.process_expired_noc_passes;`
3. Execute `scratch/run_all19.ps1` to confirm baseline regression remains green at **639 / 639 PASS**.

---

## 14. INDEPENDENT ADVERSARIAL AUDIT REQUIREMENTS

The future Slice 20 implementation MUST NOT be locked until an independent adversarial security audit verifies:
1. Actual source code and active PostgreSQL catalog definitions.
2. RLS & FORCE RLS policies on all 4 tables.
3. SECURITY DEFINER hardening and `search_path` locking.
4. True financial clearance serialization on parent `properties` row lock (`FOR UPDATE`) & `pg_advisory_xact_lock`.
5. Strict pass generation rejection for `property_sale_noc` requests.
6. Option B pass replacement lifecycle and single active pass index enforcement.
7. Persistent server-side gatekeeper rate limiting (`noc_gatekeeper_rate_limits`).
8. Move-in occupancy activation & move-out tenant tenancy termination.
9. Zero ownership record mutation for owner move-out and property sale NOCs.
10. Two-layer pass expiration defense.
11. Category-specific checklist RBAC segregation.
12. Audit redaction & notification scoping.
13. Pass all 69 assertions and confirm **708 / 708 PASS** cumulative target.

Final required audit result: **0 Critical / 0 High / 0 Medium / 0 Low findings**.

---

## 15. FINAL REVISION 3 VERDICT

The Slice 20 Implementation & Security Plan (Revision 3) is complete, fully specified, and closed against all known security blockers.

```text
SLICE 20 REVISION 3 PLAN COMPLETE — PENDING EXPLICIT USER IMPLEMENTATION AUTHORIZATION
```
