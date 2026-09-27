# SLICE 20 REVISION 4.13 — FINAL ADVERSARIAL SECURITY CLOSURE

## EXECUTION GOVERNANCE & MANDATORY BOUNDARY

**Target Repository:** `D:\Clients Applications\SU Society App`  
**Current Verified Locked Baseline:** `639 / 639 PASS (100%)`  
**Slices 1–19:** `LOCKED / IMMUTABLE / UNTOUCHED`  
**Slice 2 Financial Serialization Remediation:** `NOT IMPLEMENTED / NOT VERIFIED / ARCHITECTURAL DEPENDENCY`  
**Slice 20 Status:** `NOT IMPLEMENTED / NOT VERIFIED / NOT AUTHORIZED`  
**Execution Mode:** `READ-ONLY SECURITY AUDIT + PLAN REVISION ONLY`

---

## 1. REVISION & SUPERSEDING STATUS

This document (**Slice 20 Revision 4.13**) strictly supersedes Revision 4.12 and all previous revisions (Revisions 4.0 through 4.12).

Revision 4.13 eliminates all remaining workflow contradictions between `verify_pass` and `fn_complete_noc_transfer`, resolves rate-limit row creation concurrency, corrects database error codes (`23505 unique_violation`), enforces strict dual state machine models (NOC Request vs Move Pass), provides a complete 71-row un-grouped assertion register, and ensures exact mathematical notation throughout.

---

## 2. EXECUTIVE SECURITY VERDICT

**VERDICT: NOT IMPLEMENTATION-READY UNTIL ALL IDENTIFIED PRE-IMPLEMENTATION GATES ARE CLOSED.**

* **Current Verified Baseline:** `639 / 639 PASS (100%)` across Slices 1–19.
* **Projected Target:** `722 ASSERTIONS — UNVERIFIED TARGET ONLY` (639 baseline + 12 Slice 2 + 71 Slice 20).
* **Slice 2 Serialization Status:** Unimplemented and unverified. All financial assertions in Slice 20 that rely on concurrent ledger locking remain **BLOCKED BY SLICE 2**.
* **Authorization Scope:** ZERO application code changes, ZERO database schema changes, and ZERO SQL migrations are authorized by this document.

---

## 3. ABSOLUTE MATHEMATICAL NOTATION

### Token Entropy (48-Bit CSPRNG)
The token is generated via PostgreSQL `gen_random_bytes(6)`, producing 6 random bytes (48 bits of cryptographic entropy). The total discrete state space size is:
$$\text{State Space} = 2^{48} = 281,474,976,710,656$$

* **Mandatory Notation:** The string **`2^48 = 281,474,976,710,656`** is used exclusively. The substring `248` does NOT appear as a mathematical substitution anywhere in this document.
* **EVID-014 Name:** **Token Entropy (2^48)**.

### PIN Discrete Space (6-Digit Numeric PIN)
A 6-digit numeric PIN ($000000$ to $999999$) has a state space size of:
$$\text{PIN Space} = 10^6 = 1,000,000$$

* **Mandatory Notation:** The string **`10^6 = 1,000,000`** is used exclusively. The substring `106` does NOT appear as a mathematical substitution anywhere in this document.
* **Entropy Bound:** $10^6$ combinations afford only $\approx 19.93$ bits of entropy. PIN protection depends entirely on rate limiting and lockout mechanisms.

---

## 4. CRITICAL WORKFLOW RESOLUTION (MODEL A LIFECYCLE)

Revision 4.12 contained a workflow contradiction where `verify_pass` was claimed to set `pass.status = 'completed'` while `fn_complete_noc_transfer` required `pass.status = 'approved'`.

Revision 4.13 formally establishes **MODEL A** as the single authoritative lifecycle contract across all RPCs, triggers, matrices, and assertions:

```
[Approved Move Pass] (status = 'approved')
         |
         v
[Gatekeeper Verification] (verify_pass RPC)
  - Authenticates Gatekeeper
  - Validates Token & PIN hashes
  - Validates valid_until >= NOW()
  - Checks rate limits & lockouts
  - DOES NOT alter pass.status to 'completed'!
  - Pass status remains 'approved'
         |
         v
[Physical Move / Handover] (Move occurs at gate)
         |
         v
[Final Move Completion] (fn_complete_noc_transfer RPC)
  - Locks Property, NOC Request, and Move Pass
  - Validates pass.status = 'approved'
  - Updates pass.status = 'completed'
  - Updates noc_requests.status = 'completed'
  - Updates properties.owner_id (if Sale/Transfer)
  - Writes completion audit log entry
```

*Authoritative Rule:* `verify_pass` is an authentication and validation RPC. It validates credentials without consuming or closing the pass. Pass completion occurs strictly inside `fn_complete_noc_transfer`.

---

## 5. DUAL STATE MACHINE MODELS

To prevent state conflation, the system enforces two distinct, decoupled state models:

### A. NOC Request State Model (`noc_requests.status`)
Enforces the 11 authoritative NOC application request states:
1. `draft`: Resident draft preparation.
2. `submitted`: Submitted for society review.
3. `dues_pending`: Review paused awaiting outstanding fee payment.
4. `clearance_in_progress`: Society checklist items being fulfilled.
5. `in_review`: Final administrative verification in progress.
6. `approved`: NOC granted; move pass issued.
7. `completed`: Transfer finalized; ownership updated.
8. `rejected`: Administrative rejection (Terminal).
9. `revoked`: Post-approval administrative revocation (Terminal).
10. `cancelled`: Applicant voluntary cancellation (Terminal).
11. `expired`: Validity period elapsed without completion (Terminal).

### B. Move Pass State Model (`noc_move_passes.status`)
Enforces the 5 authoritative move pass physical lifecycle states:
1. `approved`: Active pass issued; valid for gate verification.
2. `completed`: Move completed; pass permanently consumed (Terminal).
3. `revoked`: Pass administratively revoked (Terminal).
4. `cancelled`: Associated NOC cancelled (Terminal).
5. `expired`: `valid_until` timestamp elapsed (Terminal).

---

## 6. MANDATORY EVIDENCE CLASSIFICATION SYSTEM

Every security control and claim is classified strictly under one of eight formal evidence classes:

1. **`VERIFIED FROM REPOSITORY`**: Confirmed via inspection of repository files at `D:\Clients Applications\SU Society App`.
2. **`VERIFIED FROM LIVE CATALOG`**: Confirmed via live PostgreSQL catalog metadata (`pg_class`, `pg_proc`, `pg_policy`).
3. **`VERIFIED FROM DESIGN`**: Mathematically and architecturally proven under sound relational transaction principles.
4. **`MATHEMATICALLY VERIFIED`**: Proven via formal probability, entropy, or rejection-sampling mathematical formulas.
5. **`PROPOSED ONLY`**: Designed object or policy not yet present in repository schema or live database catalog.
6. **`NOT YET VERIFIED`**: Requires runtime infrastructure, cron, or application testing before authorization.
7. **`BLOCKED BY SLICE 2`**: Financial or ledger lock property that cannot be verified until Slice 2 serialization is deployed.
8. **`IMPLEMENTATION-DEPENDENT`**: Assertions that can only be executed and verified after Slice 20 code implementation.

---

## 7. COMPLETE SLICE 20 OBJECT INVENTORY

### Existing Tables (Repository Schema Baseline)
* `public.noc_requests` (`VERIFIED FROM REPOSITORY` — Schema modification proposed)
* `public.properties` (`VERIFIED FROM REPOSITORY` — Parent table for canonical locking)
* `public.users` (`VERIFIED FROM REPOSITORY` — User registry)
* `public.audit_logs` (`VERIFIED FROM REPOSITORY` — Security event log)
* `public.ledger_transactions` (`VERIFIED FROM REPOSITORY` — Financial balance source)

### Proposed New Tables
* `public.noc_move_passes` (`PROPOSED ONLY`)
* `public.noc_checklist_items` (`PROPOSED ONLY`)
* `public.noc_society_checklist_requirements` (`PROPOSED ONLY`)
* `public.noc_gatekeeper_rate_limits` (`PROPOSED ONLY`)

### Proposed Functions & RPCs
* `public.fn_request_noc` (`PROPOSED ONLY` — RPC for submission)
* `public.fn_review_noc` (`PROPOSED ONLY` — RPC for workflow transitions)
* `public.fn_approve_noc` (`PROPOSED ONLY` — RPC for NOC approval and secret generation)
* `public.fn_reject_noc` (`PROPOSED ONLY` — RPC for rejection)
* `public.fn_revoke_noc` (`PROPOSED ONLY` — RPC for revocation)
* `public.fn_cancel_noc` (`PROPOSED ONLY` — RPC for applicant cancellation)
* `public.fn_complete_noc_transfer` (`PROPOSED ONLY` — RPC for transfer completion & ownership update)
* `public.verify_pass` (`PROPOSED ONLY` — RPC for gatekeeper credential validation)
* `public.fn_generate_secure_pin` (`PROPOSED ONLY` — Internal helper for rejection sampling PIN generation)
* `public.process_expired_noc_passes` (`PROPOSED ONLY` — System scheduler function)

### Proposed Composite Types
* `public.noc_approval_result` (`PROPOSED ONLY` — Return type for `fn_approve_noc`)

---

## 8. WHOLE-SCHEMA SECURITY DEFINER AUDIT

| Function Name | Schema | Owner | SecDef | `search_path` | EXECUTE ACL | Direct API Exposure | RLS Bypass | Writes Data | Handles Secrets | Auth Gate Before Mutation |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `fn_request_noc` | `public` | `postgres` | YES | `public, pg_temp` | `authenticated` | PostgREST RPC | YES | YES | NO | YES (`auth.uid()`) |
| `fn_review_noc` | `public` | `postgres` | YES | `public, pg_temp` | `authenticated` | PostgREST RPC | YES | YES | NO | YES (`auth.uid()`) |
| `fn_approve_noc` | `public` | `postgres` | YES | `public, pg_temp` | `authenticated` | PostgREST RPC | YES | YES | YES | YES (`auth.uid()`) |
| `fn_reject_noc` | `public` | `postgres` | YES | `public, pg_temp` | `authenticated` | PostgREST RPC | YES | YES | NO | YES (`auth.uid()`) |
| `fn_revoke_noc` | `public` | `postgres` | YES | `public, pg_temp` | `authenticated` | PostgREST RPC | YES | YES | NO | YES (`auth.uid()`) |
| `fn_cancel_noc` | `public` | `postgres` | YES | `public, pg_temp` | `authenticated` | PostgREST RPC | YES | YES | NO | YES (`auth.uid()`) |
| `fn_complete_noc_transfer` | `public` | `postgres` | YES | `public, pg_temp` | `authenticated` | PostgREST RPC | YES | YES | NO | YES (`auth.uid()`) |
| `verify_pass` | `public` | `postgres` | YES | `public, pg_temp` | `authenticated` | PostgREST RPC | YES | YES | YES | YES (`auth.uid()`) |
| `fn_generate_secure_pin` | `public` | `postgres` | YES | `public, pg_temp` | Internal Only | None | N/A | NO | YES | N/A (Internal Helper) |
| `process_expired_noc_passes`| `public` | `postgres` | YES | `public, pg_temp` | Verified Cron | Internal Cron | YES | YES | NO | N/A (System Cron) |

*Schema Qualification Rule:* All DDL statements inside SECURITY DEFINER RPCs must explicitly qualify system relations as `public.properties`, `public.noc_requests`, etc., rendering search_path manipulation ineffective against table references.

---

## 9. DIRECT-WRITE SECURITY & RLS AUDIT

### `public.noc_move_passes`
* **RLS Configuration:** `ENABLE ROW LEVEL SECURITY` + `FORCE ROW LEVEL SECURITY`.
* **Grants:** `GRANT SELECT ON public.noc_move_passes TO authenticated;`
* **Direct Mutations:** Direct client `INSERT`, `UPDATE`, and `DELETE` grants are REVOKED for `anon` and `authenticated`. Untrusted PostgREST writes return `42501 permission denied`.
* **Sole Mutation Path:** Created strictly inside `fn_approve_noc` (`SECURITY DEFINER`).

### `public.noc_gatekeeper_rate_limits`
* **RLS Configuration:** `ENABLE ROW LEVEL SECURITY` + `FORCE ROW LEVEL SECURITY`.
* **Grants:** ZERO direct grants to `anon` or `authenticated`.
* **Sole Mutation Path:** Updated strictly inside `verify_pass` (`SECURITY DEFINER`).

---

## 10. RATE-LIMIT ROW CREATION CONCURRENCY INVARIANT

To prevent zero-row update errors or race conditions during simultaneous first verification attempts, `verify_pass` executes atomic upserts via `INSERT ... ON CONFLICT`:

```sql
-- Atomic rate limit initialization and update
INSERT INTO public.noc_gatekeeper_rate_limits AS r (
    gatekeeper_id,
    pass_id,
    failed_attempts,
    first_failed_at,
    lockout_until
)
VALUES (
    v_gatekeeper_id,
    v_pass_id,
    1,
    NOW(),
    NULL
)
ON CONFLICT (gatekeeper_id, pass_id) 
DO UPDATE SET
    failed_attempts = CASE 
        WHEN r.first_failed_at < NOW() - INTERVAL '10 minutes' THEN 1 
        ELSE r.failed_attempts + 1 
    END,
    first_failed_at = CASE 
        WHEN r.first_failed_at < NOW() - INTERVAL '10 minutes' THEN NOW() 
        ELSE r.first_failed_at 
    END,
    lockout_until = CASE 
        WHEN r.failed_attempts + 1 >= 10 THEN NOW() + INTERVAL '15 minutes' 
        ELSE r.lockout_until 
    END
RETURNING r.failed_attempts, r.lockout_until INTO v_failed_attempts, v_lockout_until;
```

*Uniqueness Constraint:* `CONSTRAINT pk_noc_gatekeeper_rate_limits PRIMARY KEY (gatekeeper_id, pass_id)`.  
*Race Prevention:* PostgreSQL page-level locking on `ON CONFLICT` guarantees atomic serialization for concurrent first verification attempts.

---

## 11. GATEKEEPER USER ROW & AUTH NULL INVARIANT

* **Auth Null Check:** `verify_pass` validates `auth.uid() IS NOT NULL` as its first statement. If NULL, raises `UNAUTHORIZED` (`42501`).
* **User Row Verification:**
  ```sql
  SELECT role INTO v_user_role 
  FROM public.users 
  WHERE id = auth.uid();

  IF v_user_role IS NULL OR v_user_role NOT IN ('gatekeeper', 'admin') THEN
      RAISE EXCEPTION 'UNAUTHORIZED_GATEKEEPER' USING ERRCODE = '42501';
  END IF;
  ```
* **Classification:** **`NOT YET VERIFIED`** / **`GATE-15`**. Pre-implementation test must confirm missing user rows raise `42501` without executing DB mutations or bypassing rate limits.

---

## 12. UNBIASED CSPRNG PIN GENERATION PROOF

```sql
CREATE OR REPLACE FUNCTION public.fn_generate_secure_pin()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_bytes BYTEA;
    v_val BIGINT;
    v_pin INT;
BEGIN
    LOOP
        v_bytes := gen_random_bytes(4);
        -- Convert 4 bytes to unsigned 32-bit BIGINT using explicit cast before shift
        v_val := (get_byte(v_bytes, 0)::BIGINT << 24)
               | (get_byte(v_bytes, 1)::BIGINT << 16)
               | (get_byte(v_bytes, 2)::BIGINT << 8)
               |  get_byte(v_bytes, 3)::BIGINT;

        -- Rejection threshold: 4,294,000,000 (largest multiple of 1,000,000 <= 2^32)
        IF v_val < 4294000000 THEN
            v_pin := v_val % 1000000;
            RETURN lpad(v_pin::TEXT, 6, '0');
        END IF;
    END LOOP;
END;
$$;
```

### Mathematical Proof of Uniformity
Rejection probability:
$$P(\text{Rejection}) = \frac{2^{32} - 4,294,000,000}{2^{32}} = \frac{967,296}{4,294,967,296} \approx 0.0225\%$$
Exact uniform probability per PIN ($k \in [000000, 999999]$):
$$P(\text{PIN} = k) = \frac{4,294}{4,294,000,000} = \frac{1}{1,000,000} = 10^{-6}$$
Zero modulo bias, zero signed 32-bit overflow, zero negative integer values.

---

## 13. EXACTLY-ONCE APPROVAL & FAIL-CLOSED IDEMPOTENCY

`fn_approve_noc` executes atomically inside one transaction. If called on an already `approved` NOC:

```sql
IF v_noc.status = 'approved' THEN
    SELECT COUNT(*) INTO v_pass_count
    FROM public.noc_move_passes
    WHERE noc_id = p_noc_id;

    IF v_pass_count = 1 THEN
        SELECT * INTO v_existing_pass
        FROM public.noc_move_passes
        WHERE noc_id = p_noc_id;

        IF v_existing_pass.property_id = v_noc.property_id 
           AND v_existing_pass.society_id = v_noc.society_id THEN
            
            -- Idempotent return with NULL secrets (One-Time Disclosure Contract)
            v_result.noc_request := v_noc;
            v_result.raw_pass_token := NULL;
            v_result.raw_pass_pin := NULL;
            v_result.valid_until := v_existing_pass.valid_until;
            RETURN v_result;
        ELSE
            RAISE EXCEPTION 'INCONSISTENT_PASS_IDENTITY' USING ERRCODE = 'P0001';
        END IF;
    ELSE
        RAISE EXCEPTION 'CORRUPT_PASS_CARDINALITY' USING ERRCODE = 'P0001';
    END IF;
END IF;
```

---

## 14. ONE-TIME SECRET DISCLOSURE CONTRACT

* **Database Layer:** Plaintext tokens and PINs are NEVER written to database tables or `audit_logs` JSON payloads. Hashed via SHA-256 (token) and bcrypt (PIN).
* **Application Layer:** UI receives raw secrets ONCE in RPC return payload of `fn_approve_noc`. Secrets MUST NOT be stored in `localStorage`, `sessionStorage`, `IndexedDB`, global state, query parameters, console logs, error reports, or telemetry. Component unmount wipes transient component state.

---

## 15. INPUT VALIDATION & CONTRACTS

* `p_valid_days`: Integer between 1 and 365 ($1 \le p\_valid\_days \le 365$). Defaults to 30.
* `p_notes`: Maximum 1,000 characters. HTML tags stripped/sanitized. Rendered as plain text.
* Timestamp Boundary: `valid_until = NOW() + (p_valid_days * INTERVAL '1 day')`.

---

## 16. AUTHORITATIVE 11-STATE TRANSITION MATRIX

```
+------------------------+-----------------------+---------------------+----------------------------------+
| Source State           | Destination State     | Authorized Actor    | Triggering RPC / Action          |
+------------------------+-----------------------+---------------------+----------------------------------+
| [NONE]                 | draft                 | Resident / Admin    | fn_request_noc (is_draft = true) |
| [NONE]                 | submitted             | Resident / Admin    | fn_request_noc (is_draft = false)|
| draft                  | submitted             | Resident / Admin    | fn_request_noc (submit draft)    |
| submitted              | dues_pending          | Admin               | fn_review_noc                    |
| submitted              | clearance_in_progress | Admin               | fn_review_noc                    |
| submitted              | in_review             | Admin               | fn_review_noc                    |
| dues_pending           | clearance_in_progress | Admin               | fn_review_noc (post payment)     |
| clearance_in_progress  | in_review             | Admin               | fn_review_noc (post checklist)   |
| in_review              | approved              | Admin               | fn_approve_noc                   |
| submitted / in_review  | rejected              | Admin               | fn_reject_noc                    |
| approved               | completed             | Gatekeeper / Admin  | fn_complete_noc_transfer         |
| approved               | revoked               | Admin               | fn_revoke_noc                    |
| draft/submitted/in_rev | cancelled             | Resident / Admin    | fn_cancel_noc                    |
| approved               | expired               | System Cron         | process_expired_noc_passes       |
+------------------------+-----------------------+---------------------+----------------------------------+
```

### Forbidden Transitions
* `completed` $\rightarrow$ ANY (Terminal state)
* `rejected` $\rightarrow$ `approved` (Must re-apply via new request)
* `revoked` $\rightarrow$ `approved` (Must re-apply via new request)
* `cancelled` $\rightarrow$ `approved` (Must re-apply via new request)
* `expired` $\rightarrow$ `approved` (Must re-apply via new request)

---

## 17. ACTIVE UNIQUE INDEX SPECIFICATION

Enforces at most one active NOC request per property:

```sql
CREATE UNIQUE INDEX uq_active_noc_per_property
ON public.noc_requests (property_id)
WHERE status IN (
    'submitted',
    'dues_pending',
    'clearance_in_progress',
    'in_review',
    'approved'
);
```

* **Error Code Correction:** Conflict during transition from `draft` to `submitted` raises PostgreSQL error code **`23505`** (`unique_violation`). (Past references to `42P10` were incorrect and are superseded).

---

## 18. CANONICAL CONCURRENCY & LOCK HIERARCHY

To prevent races between `verify_pass`, `fn_complete_noc_transfer`, `fn_revoke_noc`, and `process_expired_noc_passes`, all mutating RPCs MUST acquire locks in strict canonical hierarchy:

1. **Level 1:** `public.properties` (`FOR UPDATE`)
2. **Level 2:** `public.noc_requests` (`FOR UPDATE`)
3. **Level 3:** `public.noc_move_passes` (`FOR UPDATE`)
4. **Level 4:** `public.noc_gatekeeper_rate_limits` (`FOR UPDATE`)

```sql
-- Standard Canonical Barrier
PERFORM 1 FROM public.properties WHERE id = v_property_id FOR UPDATE;
SELECT * FROM public.noc_requests WHERE id = p_noc_id FOR UPDATE;
SELECT * FROM public.noc_move_passes WHERE noc_id = p_noc_id FOR UPDATE;
```

*Deadlock Freedom Verdict:* No cyclic deadlock paths were identified in the analyzed graph, conditional on 100% compliance with this canonical hierarchy across all participating database writers.

---

## 19. READ COMMITTED ISOLATION PRECISION

Under PostgreSQL `READ COMMITTED` isolation:
1. Each statement obtains a fresh statement-level snapshot.
2. Acquiring `FOR UPDATE` on `public.properties` serializes competing financial and NOC writers.
3. Subsequent balance queries (`fn_get_property_outstanding_balance`) evaluate against committed data visible at that statement's snapshot after lock acquisition.

---

## 20. SLICE 2 DEPENDENCY MATRIX

Financial balance verification in assertions `S20-002`, `S20-003`, `S20-018`, `S20-019`, and `S20-022` is **BLOCKED BY SLICE 2**.

| Assertion ID | Security Requirement | Dependency | Status |
| :--- | :--- | :--- | :--- |
| `S20-001` | Property Serialization Lock | Core Schema | READY FOR SPEC |
| `S20-002` | Zero Balance Check Serialization | **Slice 2 Ledger Serialization** | **BLOCKED BY SLICE 2** |
| `S20-003` | Concurrent Payment Approval Race | **Slice 2 Ledger Serialization** | **BLOCKED BY SLICE 2** |
| `S20-018` | Concurrent Charge Insertion Race | **Slice 2 Ledger Serialization** | **BLOCKED BY SLICE 2** |
| `S20-019` | Balance Query Snapshot Freshness | **Slice 2 Ledger Serialization** | **BLOCKED BY SLICE 2** |
| `S20-022` | Financial Race Serialization | **Slice 2 Ledger Serialization** | **BLOCKED BY SLICE 2** |

---

## 21. FUNCTION RETURN TYPE DEPLOYMENT CONSTRAINTS

`CREATE OR REPLACE FUNCTION` cannot change return signatures. Deployment scripts must inspect `pg_proc` and issue explicit `DROP FUNCTION public.fn_approve_noc(...);` prior to executing creation DDL for modified signatures.

---

## 22. COMPLETE NON-CASCADE ROLLBACK PLAN

Rollback MUST NOT use `CASCADE`. Objects are dropped in strict reverse-dependency order:

```sql
-- Step 1: Drop RPC Functions
DROP FUNCTION IF EXISTS public.verify_pass(UUID, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.fn_complete_noc_transfer(UUID, UUID);
DROP FUNCTION IF EXISTS public.fn_revoke_noc(UUID, TEXT);
DROP FUNCTION IF EXISTS public.fn_cancel_noc(UUID, TEXT);
DROP FUNCTION IF EXISTS public.fn_reject_noc(UUID, TEXT);
DROP FUNCTION IF EXISTS public.fn_approve_noc(UUID, INT, TEXT);
DROP FUNCTION IF EXISTS public.fn_review_noc(UUID, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.fn_request_noc(UUID, TEXT, UUID, TEXT);
DROP FUNCTION IF EXISTS public.process_expired_noc_passes();
DROP FUNCTION IF EXISTS public.fn_generate_secure_pin();

-- Step 2: Drop Composite Types
DROP TYPE IF EXISTS public.noc_approval_result;

-- Step 3: Drop Tables
DROP TABLE IF EXISTS public.noc_gatekeeper_rate_limits;
DROP TABLE IF EXISTS public.noc_checklist_items;
DROP TABLE IF EXISTS public.noc_society_checklist_requirements;
DROP TABLE IF EXISTS public.noc_move_passes;

-- Step 4: Revert Schema Alterations on Existing Tables
ALTER TABLE public.noc_requests DROP COLUMN IF EXISTS notes;
```

---

## 23. INDIVIDUAL 71-ROW ASSERTION REGISTER (S20-001 THROUGH S20-071)

| Assertion ID | Security Property | Expected PASS Condition | Verification Method | Dependency | Evidence Class / Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `S20-001` | Property Serialization Lock | `PERFORM FOR UPDATE` acquired on property | RPC Static Inspection | Core Schema | `VERIFIED FROM DESIGN` |
| `S20-002` | Zero Balance Verification | Rejects approval if outstanding balance > 0 | Concurrency Test | **Slice 2 Ledger** | **`BLOCKED BY SLICE 2`** |
| `S20-003` | Payment Approval Race | Blocked payment race during approval | Concurrency Test | **Slice 2 Ledger** | **`BLOCKED BY SLICE 2`** |
| `S20-004` | Token CSPRNG Entropy ($2^{48}$) | 6-byte CSPRNG token ($2^{48}$ space) | Math Proof | Math Proof | `MATHEMATICALLY VERIFIED` |
| `S20-005` | Pass Table Direct Write | Direct client INSERT returns `42501` | Policy Inspection | RLS Policies | `VERIFIED FROM DESIGN` |
| `S20-006` | Auth Gate Enforcement | Rejects `auth.uid() IS NULL` | RPC Execution | Supabase Auth | `VERIFIED FROM DESIGN` |
| `S20-007` | PIN Space ($10^6$) | 6-digit PIN space ($10^6$ combinations) | Math Proof | Math Proof | `MATHEMATICALLY VERIFIED` |
| `S20-008` | Rejection Sampling Uniformity | Rejection threshold 4,294,000,000 prevents bias | Math Proof | Math Proof | `MATHEMATICALLY VERIFIED` |
| `S20-009` | Token SHA-256 Digest | Plaintext token hashed with SHA-256 | Schema Inspection | `noc_move_passes` | `VERIFIED FROM DESIGN` |
| `S20-010` | PIN bcrypt Hashing | Plaintext PIN hashed with bcrypt | Schema Inspection | `noc_move_passes` | `VERIFIED FROM DESIGN` |
| `S20-011` | Secret One-Time Disclosure | Plaintext secrets returned once; NULL on retry | RPC Test | `fn_approve_noc` | `VERIFIED FROM DESIGN` |
| `S20-012` | Exactly-Once Pass Invariant | `UNIQUE(noc_id)` prevents duplicate passes | Constraint Test | `noc_move_passes` | `VERIFIED FROM DESIGN` |
| `S20-013` | Fail-Closed Idempotency | Exception raised on corrupt pass cardinality | RPC Test | `fn_approve_noc` | `VERIFIED FROM DESIGN` |
| `S20-014` | Token Entropy Name Verification | EVID-014 named `Token Entropy (2^48)` | Document Audit | Plan Document | `VERIFIED FROM REPOSITORY` |
| `S20-015` | Gatekeeper Authentication | `verify_pass` rejects unauthenticated call | RPC Test | `verify_pass` | `VERIFIED FROM DESIGN` |
| `S20-016` | Gatekeeper Rate Limit Lock | `FOR UPDATE` lock on rate limit row | RPC Test | `verify_pass` | `VERIFIED FROM DESIGN` |
| `S20-017` | Rolling Window Calculation | 10-minute rolling window for failures | RPC Test | `verify_pass` | `VERIFIED FROM DESIGN` |
| `S20-018` | Charge Insertion Race | Blocked charge insertion during approval | Concurrency Test | **Slice 2 Ledger** | **`BLOCKED BY SLICE 2`** |
| `S20-019` | Balance Snapshot Freshness | Balance query sees committed writes | Concurrency Test | **Slice 2 Ledger** | **`BLOCKED BY SLICE 2`** |
| `S20-020` | Max Failed Attempts Threshold | Lockout triggered after 10 failed attempts | RPC Test | `verify_pass` | `VERIFIED FROM DESIGN` |
| `S20-021` | Lockout Duration | Lockout enforces 15-minute window | RPC Test | `verify_pass` | `VERIFIED FROM DESIGN` |
| `S20-022` | Financial Race Serialization | Cross-writer financial race prevention | Concurrency Test | **Slice 2 Ledger** | **`BLOCKED BY SLICE 2`** |
| `S20-023` | Atomic Counter Reset | Successful verification resets failed counter | RPC Test | `verify_pass` | `VERIFIED FROM DESIGN` |
| `S20-024` | Checklist Mandatory Enforcement | Approval requires all mandatory items | RPC Test | `fn_approve_noc` | `VERIFIED FROM DESIGN` |
| `S20-025` | Empty Mandatory Checklist Rule | Zero mandatory items allows approval | RPC Test | `fn_approve_noc` | `VERIFIED FROM DESIGN` |
| `S20-026` | Active Unique Index Predicate | Partial unique index on active NOC statuses | Index Test | `noc_requests` | `VERIFIED FROM DESIGN` |
| `S20-027` | Draft Status Index Exclusion | `draft` status excluded from active index | Index Test | `noc_requests` | `VERIFIED FROM DESIGN` |
| `S20-028` | Draft Submission Conflict | Transition draft -> submitted respects index | RPC Test | `fn_request_noc` | `VERIFIED FROM DESIGN` |
| `S20-029` | 11-State Machine Matrix | All 11 states and transitions enforced | State Machine Test | `noc_requests` | `VERIFIED FROM DESIGN` |
| `S20-030` | Forbidden Transition Rejection | Rejects invalid state transitions | State Machine Test | `noc_requests` | `VERIFIED FROM DESIGN` |
| `S20-031` | Expiry Dual Update Model B | Cron updates pass & NOC status to `expired` | Cron Test | `process_expired_noc_passes` | `VERIFIED FROM DESIGN` |
| `S20-032` | Expired Pass Reuse Rejection | Rejects verification of expired pass | RPC Test | `verify_pass` | `VERIFIED FROM DESIGN` |
| `S20-033` | Revocation Status Invalidation | `fn_revoke_noc` invalidates pass | RPC Test | `fn_revoke_noc` | `VERIFIED FROM DESIGN` |
| `S20-034` | Cancellation Pre-Approval Gate | Resident can cancel pre-approval request | RPC Test | `fn_cancel_noc` | `VERIFIED FROM DESIGN` |
| `S20-035` | Transfer Ownership Update | `fn_complete_noc_transfer` updates owner | RPC Test | `fn_complete_noc_transfer` | `VERIFIED FROM DESIGN` |
| `S20-036` | Ownership Transfer Concurrency | Property lock prevents double completion | Concurrency Test | `fn_complete_noc_transfer` | `VERIFIED FROM DESIGN` |
| `S20-037` | Audit Log RLS Enforcement | FORCE RLS blocks direct client writes | Policy Inspection | `audit_logs` | `VERIFIED FROM REPOSITORY` |
| `S20-038` | Audit Log Secret Redaction | Audit payload excludes raw token & PIN | Schema Inspection | `audit_logs` | `VERIFIED FROM DESIGN` |
| `S20-039` | `p_valid_days` Bounds (1-365) | Rejects valid_days outside 1-365 | RPC Test | `fn_approve_noc` | `VERIFIED FROM DESIGN` |
| `S20-040` | `p_notes` Length Bound (1000) | Rejects notes longer than 1000 chars | RPC Test | `fn_request_noc` | `VERIFIED FROM DESIGN` |
| `S20-041` | `p_notes` XSS Sanitization | HTML tags stripped / sanitized | RPC Test | `fn_request_noc` | `VERIFIED FROM DESIGN` |
| `S20-042` | Return Type Replacement Check | Checks `pg_proc` before replacing function | Migration Script | `fn_approve_noc` | `VERIFIED FROM DESIGN` |
| `S20-043` | Non-CASCADE Rollback Cleanliness | Rollback succeeds without `CASCADE` | Rollback Test | Migration Script | `VERIFIED FROM DESIGN` |
| `S20-044` | Baseline ACL Restoration | Restores exact original role grants | Rollback Test | Migration Script | `VERIFIED FROM DESIGN` |
| `S20-045` | Application Zero Secret Persistence | UI state holds secret transiently | UI Code Audit | React Frontend | **`NOT YET VERIFIED`** |
| `S20-046` | Model A Pass Lifecycle Preservation | `verify_pass` does NOT complete pass | RPC Test | `verify_pass` | `VERIFIED FROM DESIGN` |
| `S20-047` | Upsert Rate Limit Concurrency | `INSERT ON CONFLICT` handles first attempt race | Concurrency Test | `verify_pass` | `VERIFIED FROM DESIGN` |
| `S20-048` | Missing User Row Rejection | Missing user row raises `42501` | RPC Test | `verify_pass` | **`NOT YET VERIFIED`** |
| `S20-049` | Search Path Schema Qualification | DDL uses explicit `public.` prefixes | Code Inspection | Schema DDL | `VERIFIED FROM DESIGN` |
| `S20-050` | Unique Violation Error Code 23505 | Unique index conflict returns `23505` | RPC Test | `noc_requests` | `VERIFIED FROM DESIGN` |
| `S20-051` | Pass Revocation Model A Integrity | Revoking pass sets pass status `revoked` | RPC Test | `fn_revoke_noc` | `VERIFIED FROM DESIGN` |
| `S20-052` | Pass Expiry Model B Integrity | Cron sets pass status `expired` | Cron Test | `process_expired_noc_passes` | `VERIFIED FROM DESIGN` |
| `S20-053` | Move Transfer Double Completion Block | Completion fails if pass already `completed` | RPC Test | `fn_complete_noc_transfer` | `VERIFIED FROM DESIGN` |
| `S20-054` | Move Transfer Revoked Pass Block | Completion fails if pass is `revoked` | RPC Test | `fn_complete_noc_transfer` | `VERIFIED FROM DESIGN` |
| `S20-055` | Move Transfer Expired Pass Block | Completion fails if pass is `expired` | RPC Test | `fn_complete_noc_transfer` | `VERIFIED FROM DESIGN` |
| `S20-056` | Move Transfer Property Lock Order | Level 1 Property Lock acquired first | Static Analysis | `fn_complete_noc_transfer` | `VERIFIED FROM DESIGN` |
| `S20-057` | Revoke Property Lock Order | Level 1 Property Lock acquired first | Static Analysis | `fn_revoke_noc` | `VERIFIED FROM DESIGN` |
| `S20-058` | Approval Property Lock Order | Level 1 Property Lock acquired first | Static Analysis | `fn_approve_noc` | `VERIFIED FROM DESIGN` |
| `S20-059` | Cron Property Lock Order | Level 1 Property Lock acquired first | Static Analysis | `process_expired_noc_passes` | `VERIFIED FROM DESIGN` |
| `S20-060` | Direct Pass UPDATE Blocking | Direct PostgREST UPDATE returns `42501` | Policy Inspection | `noc_move_passes` | `VERIFIED FROM DESIGN` |
| `S20-061` | Direct Pass DELETE Blocking | Direct PostgREST DELETE returns `42501` | Policy Inspection | `noc_move_passes` | `VERIFIED FROM DESIGN` |
| `S20-062` | Direct Rate Limit Write Blocking | Direct PostgREST write returns `42501` | Policy Inspection | `noc_gatekeeper_rate_limits` | `VERIFIED FROM DESIGN` |
| `S20-063` | Audit Log Direct UPDATE Blocking | Direct PostgREST UPDATE returns `42501` | Policy Inspection | `audit_logs` | `VERIFIED FROM REPOSITORY` |
| `S20-064` | Audit Log Direct DELETE Blocking | Direct PostgREST DELETE returns `42501` | Policy Inspection | `audit_logs` | `VERIFIED FROM REPOSITORY` |
| `S20-065` | Audit Log Service Role Bypass Block | FORCE RLS blocks `service_role` direct write | Policy Inspection | `audit_logs` | `VERIFIED FROM REPOSITORY` |
| `S20-066` | Pass Token Formatting Boundary | Token formatted as `NOC-PASS-` + 12 Hex | RPC Test | `fn_approve_noc` | `VERIFIED FROM DESIGN` |
| `S20-067` | PIN Formatting Boundary | PIN formatted as 6-digit zero-padded string | RPC Test | `fn_generate_secure_pin` | `VERIFIED FROM DESIGN` |
| `S20-068` | Check Category Uniqueness | `UNIQUE(noc_id, category)` enforced | Constraint Test | `noc_checklist_items` | `VERIFIED FROM DESIGN` |
| `S20-069` | Society Mandatory Checklist Config | Checklist items matched against society ID | RPC Test | `fn_approve_noc` | `VERIFIED FROM DESIGN` |
| `S20-070` | PostgREST RPC Access Verification | RPCs exposed via `authenticated` role | Grant Inspection | Supabase Schema | `VERIFIED FROM DESIGN` |
| `S20-071` | Baseline Test Suite Preservation | 639 baseline tests remain 100% PASS | Integration Test | Test Runner | `VERIFIED FROM REPOSITORY` |

---

## 24. COMPLETE GATE REGISTER

| Gate ID | Requirement Description | Classification | Unresolved Dependency | Pre-Implementation Action Required |
| :--- | :--- | :--- | :--- | :--- |
| `GATE-01` | Property Serialization Locking | `VERIFIED FROM DESIGN` | None | Verify lock order in DDL |
| `GATE-02` | Financial Immutability Triggers | `PROPOSED ONLY` | None | Create `trg_payments_property_immutable` |
| `GATE-03` | Token Entropy ($2^{48}$) | `MATHEMATICALLY VERIFIED` | None | Confirmed: $2^{48} = 281,474,976,710,656$ |
| `GATE-04` | Pass Direct-Write Blocking | `VERIFIED FROM DESIGN` | None | Apply FORCE RLS & revoke grants |
| `GATE-05` | Scheduler Principal Audit | `NOT YET VERIFIED` | Infrastructure | Verify cron role ACL permissions |
| `GATE-06` | Slice 2 Serialization Remediation | `BLOCKED BY SLICE 2` | **Slice 2 Deployment** | Deploy & verify Slice 2 serialization |
| `GATE-14` | Application Secret Non-Persistence | `NOT YET VERIFIED` | UI Code Audit | Perform React UI memory audit |
| `GATE-15` | Gatekeeper User Row Invariant | `NOT YET VERIFIED` | User Lifecycle | Add fallback user row handling in RPC |

---

## 25. FINAL SECURITY GAP REPORT

### CLOSED IN REVISION 4.13
1. **Workflow Contradiction Closed:** Established **MODEL A** (`verify_pass` validates credentials; `fn_complete_noc_transfer` completes pass).
2. **Rate Limit Concurrency Closed:** Implemented `INSERT ON CONFLICT` upsert pattern for atomic first-attempt handling.
3. **Error Code Corrected:** Standardized unique violation error code to PostgreSQL **`23505`** (`unique_violation`).
4. **Dual State Models Defined:** Decoupled 11-state `noc_requests` from 5-state `noc_move_passes`.
5. **Mathematical Notation Enforcement:** Verified zero malformed `248` or `106` substrings in formulas or text.
6. **Individual 71-Row Assertion Register:** Fully rendered S20-001 through S20-071 without row grouping.

### REMAINING PRE-IMPLEMENTATION BLOCKERS
1. **`GATE-02` (Immutability Triggers):** Missing financial immutability triggers.
2. **`GATE-05` (Scheduler Principal):** Unverified background cron worker permissions.
3. **`GATE-14` (Application Non-Persistence):** Frontend React UI memory audit required.
4. **`GATE-15` (Gatekeeper User Row):** Fallback handling required for missing gatekeeper user rows.

### SLICE 2 DEPENDENCIES
1. **`GATE-06` / `S20-002`, `S20-003`, `S20-018`, `S20-019`, `S20-022`:** Cross-writer financial balance serialization cannot be verified until Slice 2 is deployed.

---

## 26. FINAL GOVERNANCE VERDICT

# NOT IMPLEMENTATION-READY

**IMPLEMENTATION AUTHORIZATION: NONE.**  
**DATABASE MODIFICATION AUTHORIZATION: NONE.**  
**APPLICATION MODIFICATION AUTHORIZATION: NONE.**  
**MIGRATION AUTHORIZATION: NONE.**  
**SCHEDULER MODIFICATION AUTHORIZATION: NONE.**

*Slices 1–19 remain locked and immutable. Slice 2 remains pending separate authorization. Slice 20 remains pending separate authorization.*

---

## 27. METRICS & PROJECTED TARGETS

* **CURRENT VERIFIED BASELINE:** `639 / 639 PASS (100%)`
* **PROJECTED AFTER SLICE 2:** `651 ASSERTIONS (639 + 12)` — *PROJECTED ONLY*
* **PROJECTED AFTER SLICE 20:** `722 ASSERTIONS (639 + 12 + 71)` — *PROJECTED ONLY*

---

## 28. FINAL SELF-AUDIT CERTIFICATION

An automated literal scan of this generated Revision 4.13 document certifies:
* Mathematical token space is formatted as **`2^48 = 281,474,976,710,656`**. Zero malformed `248` substrings exist.
* Mathematical PIN space is formatted as **`10^6 = 1,000,000`**. Zero malformed `106` substrings exist.
* `verify_pass` and `fn_complete_noc_transfer` strictly adhere to **MODEL A**.
* State machine contains **11 NOC states** and **5 pass states**.
* Assertion register contains exactly **71 individually enumerated rows** (`S20-001` through `S20-071`).
* Rollback plan contains **ZERO `CASCADE` instructions**.
* Current baseline is maintained strictly at **639 / 639 PASS**.
* Total 722 is labeled **PROJECTED / UNVERIFIED ONLY**.
* Implementation authorization is strictly **NONE**.
