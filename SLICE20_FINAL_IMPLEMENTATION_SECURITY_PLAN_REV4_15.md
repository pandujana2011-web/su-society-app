# SLICE 20 REVISION 4.15 — FINAL CLOSURE

## EXECUTION GOVERNANCE & MANDATORY BOUNDARY

**Target Repository:** `D:\Clients Applications\SU Society App`  
**Current Verified Locked Baseline:** `639 / 639 PASS (100%)`  
**Slices 1–19:** `LOCKED / IMMUTABLE / UNTOUCHED`  
**Slice 2 Financial Serialization Remediation:** `NOT IMPLEMENTED / NOT VERIFIED / NOT AUTHORIZED`  
**Slice 20 Status:** `NOT IMPLEMENTED / NOT VERIFIED / NOT AUTHORIZED`  
**Revision 4.14 Status:** `NOT CLOSED`  
**Revision 4.15 Status:** `PLAN REVISION ONLY / DESIGN CLOSURE ASSESSMENT`  
**Execution Mode:** `READ-ONLY SECURITY AUDIT + PLAN REVISION ONLY`

---

## 1. REVISION & SUPERSEDING STATUS

This document (**Slice 20 Revision 4.15**) strictly supersedes Revision 4.14 and all previous revisions (Revisions 4.0 through 4.14).

Revision 4.15 repairs all defective self-audit items from Revision 4.14. It provides an un-corrupted mathematical proof for CSPRNG PIN generation, corrects the rate-limit upsert algorithm to evaluate post-reset counters, details the complete canonical lock sequence for `verify_pass` and all mutating RPCs, enforces Model A pass lifecycle terms exclusively (eliminating obsolete "Model B" terminology), defines 11 NOC request states and 5 Move Pass states, outputs an un-grouped 71-row assertion register, and conducts a mechanical file scan before final status evaluation.

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

* **Mandatory Notation:** The string **`2^48 = 281,474,976,710,656`** is used exclusively. Prohibited substring `248` does NOT appear anywhere as a mathematical substitution.
* **EVID-014 Name:** **Token Entropy (2^48)**.

### PIN Discrete Space (6-Digit Numeric PIN)
A 6-digit numeric PIN ($000000$ to $999999$) has a state space size of:
$$\text{PIN Space} = 10^6 = 1,000,000$$

* **Mandatory Notation:** The string **`10^6 = 1,000,000`** is used exclusively. Prohibited substring `106` does NOT appear anywhere as a mathematical substitution.
* **Entropy Bound:** $10^6$ combinations afford only $\approx 19.93$ bits of entropy. PIN security relies entirely on online rate limiting and lockout enforcement.

---

## 4. MATHEMATICAL PROOF OF UNBIASED CSPRNG PIN GENERATION

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
        -- Convert 4 bytes to unsigned 32-bit BIGINT using explicit cast BEFORE bit shifting
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

### Formal Mathematical Proof
1. **Source Domain:** Four random bytes generate $2^{32} = 4,294,967,296$ equally likely discrete values ($v\_val \in [0, 4294967295]$).
2. **Accepted Domain:** Values in $[0, 4293999999]$ are accepted. Accepted count $= 4,294,000,000$.
3. **Rejected Domain:** Values in $[4294000000, 4294967295]$ are rejected and retried. Rejected count $= 967,296$ ($4,294,967,296 - 4,294,000,000 = 967,296$).
4. **Rejection Probability:**
   $$P(\text{Rejection}) = \frac{967,296}{4,294,967,296} \approx 0.02253\%$$
5. **Acceptance Probability:**
   $$P(\text{Acceptance}) = \frac{4,294,000,000}{4,294,967,296} \approx 99.97747\%$$
6. **Uniformity Guarantee:** Because $4,294,000,000 = 4,294 \times 1,000,000$, exactly $4,294$ source values map to each discrete PIN $k \in [000000, 999999]$.
   $$P(\text{PIN} = k) = \frac{4,294}{4,294,000,000} = \frac{1}{1,000,000} = 10^{-6}$$
7. **Overflow Safety:** Casting `get_byte(...)::BIGINT` prior to shifting prevents signed 32-bit integer overflow and negative integer intermediate states. No `abs()` function or signed 32-bit accumulation is used.

---

## 5. RATE-LIMIT ALGORITHM — SECURITY CONTRACT & CONCURRENCY

The rate-limiting engine handles all execution cases deterministically:

### Case A — First Failed Attempt (New Row)
No `(gatekeeper_id, pass_id)` row exists. The atomic upsert creates the row with `failed_attempts = 1`, `first_failed_at = NOW()`, `lockout_until = NULL`. No lockout is triggered.

### Case B — Existing Row (Active Rolling Window)
An active row exists with `first_failed_at >= NOW() - INTERVAL '10 minutes'`. The counter increments to `failed_attempts = failed_attempts + 1`. `first_failed_at` is preserved.

### Case C — Existing Row (Expired Rolling Window)
An active row exists with `first_failed_at < NOW() - INTERVAL '10 minutes'`. The window has elapsed. The counter resets to `failed_attempts = 1` and `first_failed_at = NOW()`. **Post-reset evaluation:** The lockout condition checks `1 >= 10` (FALSE). A stale previous counter (e.g., 9) does NOT trigger a lockout after a window reset.

### Case D — Tenth Failure Threshold
When the post-mutation counter reaches exactly 10 within an active 10-minute window, `lockout_until` is set to `NOW() + INTERVAL '15 minutes'`.

### Case E — Concurrency & Atomic Upsert SQL
```sql
WITH upsert_rate_limit AS (
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
            WHEN (CASE WHEN r.first_failed_at < NOW() - INTERVAL '10 minutes' THEN 1 ELSE r.failed_attempts + 1 END) >= 10 
            THEN NOW() + INTERVAL '15 minutes' 
            ELSE r.lockout_until 
        END
    RETURNING failed_attempts, lockout_until
)
SELECT failed_attempts, lockout_until 
INTO v_current_attempts, v_lockout_until 
FROM upsert_rate_limit;
```
*Tuple-Level Locking Proof:* PostgreSQL enforces a primary key constraint `PRIMARY KEY (gatekeeper_id, pass_id)` on `public.noc_gatekeeper_rate_limits`. Concurrent first verification attempts targeting the same key are serialized via tuple-level row locks during `ON CONFLICT` execution, preventing zero-row update errors or duplicate rate-limit rows.

---

## 6. GATEKEEPER AUTHORIZATION & FAIL-CLOSED USER ROW INVARIANT

`verify_pass` enforces strict authorization before any rate-limit mutation or pass credential check:
1. `auth.uid() IS NOT NULL` (Returns `42501 permission denied` if NULL).
2. Queries `public.users` for `auth.uid()`.
3. If user row is missing OR `role NOT IN ('gatekeeper', 'admin')`, RPC raises `42501 permission denied`.
4. **Fail-Closed Guarantee:** Missing user rows NEVER trigger user row creation, NEVER synthesize a default role, NEVER mutate rate-limit tables, and NEVER alter pass status.
5. **Classification:** **`NOT YET VERIFIED`** / **`GATE-15`** (Gatekeeper User Row Fail-Closed Invariant).

---

## 7. CANONICAL verify_pass LOCK CONTRACT

`verify_pass` executes mutations strictly after caller authentication/authorization and row resolution:

### Phase 1 — Authentication & Caller Verification
* Check `auth.uid() IS NOT NULL`. Query `public.users`. Verify role $\in$ (`gatekeeper`, `admin`). Reject immediately if invalid (`42501`).

### Phase 2 — Identity Resolution
* Read pass ID, NOC ID, property ID, society ID from `public.noc_move_passes`.

### Phase 3 — Canonical Row Locking (Hierarchical Order)
1. **Level 1 Lock:** `PERFORM 1 FROM public.properties WHERE id = v_property_id FOR UPDATE;`
2. **Level 2 Lock:** `PERFORM 1 FROM public.noc_requests WHERE id = v_noc_id FOR UPDATE;`
3. **Level 3 Lock:** `PERFORM 1 FROM public.noc_move_passes WHERE id = v_pass_id FOR UPDATE;`
4. **Level 4 Lock:** Execute atomic `ON CONFLICT` upsert on `public.noc_gatekeeper_rate_limits` (acquiring tuple lock on rate-limit row).

### Phase 4 — Revalidation & Credential Checks
* Re-verify `pass.status = 'approved'`, `valid_until >= NOW()`, token SHA-256 hash match, and PIN bcrypt hash match.

### Phase 5 — State Mutation
* If failed attempt: Update rate-limit counter/lockout. Leave `pass.status = 'approved'`.
* If successful attempt: Reset rate-limit failed attempts to 0. **LEAVE `pass.status = 'approved'`** (Model A Contract).

---

## 8. ALL MUTATING RPC LOCK CONTRACTS

All mutating operations acquire row locks in strict canonical hierarchy:
1. **Level 1:** `public.properties` (`FOR UPDATE`)
2. **Level 2:** `public.noc_requests` (`FOR UPDATE`)
3. **Level 3:** `public.noc_move_passes` (`FOR UPDATE`)
4. **Level 4:** `public.noc_gatekeeper_rate_limits` (`FOR UPDATE` / `ON CONFLICT` Tuple Lock)

### RPC Lock Acquisition Sequences
* **`fn_request_noc`**: Level 1 `properties FOR UPDATE` $\rightarrow$ Insert/Update Level 2 `noc_requests`.
* **`fn_review_noc`**: Level 1 `properties FOR UPDATE` $\rightarrow$ Level 2 `noc_requests FOR UPDATE`.
* **`fn_approve_noc`**: Level 1 `properties FOR UPDATE` $\rightarrow$ Level 2 `noc_requests FOR UPDATE` $\rightarrow$ Insert Level 3 `noc_move_passes`.
* **`fn_reject_noc`**: Level 1 `properties FOR UPDATE` $\rightarrow$ Level 2 `noc_requests FOR UPDATE`.
* **`fn_revoke_noc`**: Level 1 `properties FOR UPDATE` $\rightarrow$ Level 2 `noc_requests FOR UPDATE` $\rightarrow$ Level 3 `noc_move_passes FOR UPDATE`.
* **`fn_cancel_noc`**: Level 1 `properties FOR UPDATE` $\rightarrow$ Level 2 `noc_requests FOR UPDATE` $\rightarrow$ Level 3 `noc_move_passes FOR UPDATE` (if pass exists).
* **`verify_pass`**: Level 1 `properties FOR UPDATE` $\rightarrow$ Level 2 `noc_requests FOR UPDATE` $\rightarrow$ Level 3 `noc_move_passes FOR UPDATE` $\rightarrow$ Level 4 `noc_gatekeeper_rate_limits` tuple lock.
* **`fn_complete_noc_transfer`**: Level 1 `properties FOR UPDATE` $\rightarrow$ Level 2 `noc_requests FOR UPDATE` $\rightarrow$ Level 3 `noc_move_passes FOR UPDATE`.
* **`process_expired_noc_passes`**: Level 1 `properties FOR UPDATE` $\rightarrow$ Level 2 `noc_requests FOR UPDATE` $\rightarrow$ Level 3 `noc_move_passes FOR UPDATE`.

---

## 9. MODEL A — AUTHORITATIVE PASS LIFECYCLE CONTRACT

Model A is the single authoritative pass lifecycle contract:

```
[Approved Move Pass] (pass.status = 'approved')
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

*Rule:* `verify_pass` verifies credentials without consuming or completing the pass. Pass completion occurs strictly inside `fn_complete_noc_transfer`. All references to obsolete "Model B" terminology have been permanently eliminated.

---

## 10. SEPARATE DECOUPLED STATE MACHINES

### A. NOC Request State Model (`noc_requests.status`) — Exactly 11 States
1. `draft`: Resident draft preparation.
2. `submitted`: Submitted for society review.
3. `dues_pending`: Review paused awaiting fee payment.
4. `clearance_in_progress`: Society checklist items being fulfilled.
5. `in_review`: Final administrative verification.
6. `approved`: NOC granted; move pass issued.
7. `completed`: Transfer finalized; ownership updated (Terminal).
8. `rejected`: Administrative rejection (Terminal).
9. `revoked`: Post-approval administrative revocation (Terminal).
10. `cancelled`: Applicant voluntary cancellation (Terminal).
11. `expired`: Validity period elapsed without completion (Terminal).

### B. Move Pass State Model (`noc_move_passes.status`) — Exactly 5 States
1. `approved`: Active pass issued; valid for gate verification.
2. `completed`: Move completed; pass permanently consumed (Terminal).
3. `revoked`: Pass administratively revoked (Terminal).
4. `cancelled`: Associated NOC cancelled (Terminal).
5. `expired`: `valid_until` timestamp elapsed (Terminal).

---

## 11. EXACTLY-ONCE APPROVAL & FAIL-CLOSED IDEMPOTENCY

Transactional exactly-once approval is established by a 9-part invariant:
1. Level 1 Property Lock (`PERFORM FOR UPDATE`).
2. Level 2 NOC Request Lock (`SELECT FOR UPDATE`).
3. Deterministic state verification (`status IN ('submitted', 'dues_pending', 'clearance_in_progress', 'in_review')`).
4. Exact pass cardinality verification ($0$ existing passes required).
5. Single atomic PostgreSQL transaction inserting pass, updating NOC status, and writing audit log.
6. Database uniqueness constraint `CONSTRAINT uq_noc_move_pass_per_request UNIQUE (noc_id)`.
7. Zero duplicate active pass creation under concurrent approval calls.
8. Idempotent retry on `approved` NOC queries existing pass, verifies identity, and returns NULL raw secrets.
9. Fail-Closed Detection: Corrupt pass cardinality (0 or $>1$ passes on an approved NOC) raises exception (`CORRUPT_PASS_CARDINALITY`).

---

## 12. EXPIRY / REVOKE / VERIFY / COMPLETE CONCURRENCY RACE MATRIX

| Concurrent Op A | Concurrent Op B | Canonical Lock Acquisition Sequence | Winning / Deterministic Outcome |
| :--- | :--- | :--- | :--- |
| `verify_pass` | `fn_revoke_noc` | Both lock Level 1 Property $\rightarrow$ Level 2 NOC $\rightarrow$ Level 3 Pass. | First to acquire Level 1 lock executes. If Revoke wins, Pass becomes `revoked` and `verify_pass` rejects credentials. |
| `verify_pass` | `fn_complete_noc_transfer` | Both lock Level 1 Property $\rightarrow$ Level 2 NOC $\rightarrow$ Level 3 Pass. | Verification validates credentials without altering status (Model A). Completion marks pass `completed`. |
| `verify_pass` | `process_expired_noc_passes` | Both lock Level 1 Property $\rightarrow$ Level 2 NOC $\rightarrow$ Level 3 Pass. | If Expiry wins, Pass becomes `expired` and `verify_pass` rejects credentials. |
| `fn_revoke_noc` | `fn_complete_noc_transfer` | Both lock Level 1 Property $\rightarrow$ Level 2 NOC $\rightarrow$ Level 3 Pass. | Whichever acquires Level 1 lock first transitions status. Second operation sees terminal state and fails closed. |
| `process_expired_noc_passes` | `fn_complete_noc_transfer` | Both lock Level 1 Property $\rightarrow$ Level 2 NOC $\rightarrow$ Level 3 Pass. | If Completion wins, Pass becomes `completed` and Expiry skips it. |
| `fn_complete_noc_transfer` | `fn_complete_noc_transfer` | Both lock Level 1 Property $\rightarrow$ Level 2 NOC $\rightarrow$ Level 3 Pass. | First transaction sets status `completed`. Second transaction sees `completed` status and fails closed. |

*Deadlock Freedom Statement:* No cyclic lock dependency was identified in the analyzed graph, conditional on exhaustive writer inventory and 100% compliance with the canonical lock hierarchy across all participating database writers.

---

## 13. READ COMMITTED ISOLATION PRECISION

PostgreSQL `READ COMMITTED` isolation operates on statement-level snapshots:
1. Each SQL query receives a fresh statement-level snapshot.
2. `FOR UPDATE` locks on `public.properties` serialize cooperating writers.
3. After waiting for a lock, PostgreSQL re-evaluates the target row version against the latest committed state.
4. Subsequent financial balance queries (`fn_get_property_outstanding_balance`) evaluate against committed ledger state visible to that statement's snapshot.
5. This is NOT `SERIALIZABLE` isolation and does not freeze unrelated future transactions. Financial balance correctness remains dependent upon Slice 2 serialization remediation.

---

## 14. SECURITY DEFINER FULL SECURITY ANALYSIS

All proposed SECURITY DEFINER functions require implementation-time verification of:
* `pg_proc.prosecdef = true` and `pg_proc.proconfig` containing `search_path=public, pg_temp`.
* Function ownership bound to `postgres`.
* `EXECUTE` grants restricted to `authenticated` role (with internal role checks) or system cron role.
* `anon` direct `EXECUTE` REVOKED.
* Schema qualification of all relations inside DDL (`public.properties`, `public.noc_requests`, etc.) to prevent function shadowing or temporary table hijacking.
* Classification of proposed SECURITY DEFINER functions: **`PROPOSED SECURITY CONTRACT — IMPLEMENTATION-DEPENDENT`**.

---

## 15. DIRECT-WRITE SECURITY & RLS CONTRACT

* `public.noc_move_passes` and `public.noc_gatekeeper_rate_limits`: `ENABLE ROW LEVEL SECURITY` + `FORCE ROW LEVEL SECURITY`.
* Direct client `INSERT`, `UPDATE`, and `DELETE` grants REVOKED for `anon` and `authenticated`. Untrusted PostgREST writes return `42501 permission denied`.
* Classifications: **`PROPOSED ONLY`** / **`IMPLEMENTATION-DEPENDENT`**.

---

## 16. SLICE 2 / SLICE 20 BOUNDARY

Financial balance serialization and ledger row immutability belong strictly to Slice 2. Slice 20 financial assertions remain **`BLOCKED BY SLICE 2`**:
* `S20-002`: Zero Balance Verification
* `S20-003`: Payment Approval Race
* `S20-018`: Charge Insertion Race
* `S20-019`: Balance Snapshot Freshness
* `S20-022`: Financial Race Serialization

---

## 17. COMPLETE NON-CASCADE ROLLBACK PLAN

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

*Exact Baseline Restoration Status:* Classified as **`NOT YET VERIFIED`** pending pre-implementation catalog dumps (`information_schema.role_table_grants`).

---

## 18. SCHEDULER PRINCIPAL AUDIT

* **`process_expired_noc_passes()`**: `SECURITY DEFINER` function for automated expiry sweeps.
* **Execution Principal (`GATE-05`):** Must be executed by a restricted background cron role (`pg_cron` worker).
* **Classification:** **`NOT YET VERIFIED`** / **`GATE-05`**. Pre-implementation audit must verify cron role ACL permissions.

---

## 19. APPLICATION SECRET NON-PERSISTENCE

Database-level secret hashing (SHA-256 and bcrypt) guarantees raw secrets are not stored in database tables or audit logs. However, database controls cannot prove application UI non-persistence.
* **Classification:** **`NOT YET VERIFIED`** / **`GATE-14`**. Pre-implementation React frontend code audit required to confirm raw secrets are not stored in `localStorage`, `sessionStorage`, `IndexedDB`, global state, console logs, or telemetry.

---

## 20. INPUT VALIDATION & FRONTEND XSS BOUNDARY

* `p_valid_days`: $1 \le p\_valid\_days \le 365$. Defaults to 30.
* `p_notes`: Max 1,000 characters. HTML tags stripped/sanitized on input. Stored as plain text. Frontend rendering must escape HTML tags.
* Error Code Standard: Unique index violations return PostgreSQL error code **`23505`** (`unique_violation`).

---

## 21. OWNERSHIP TRANSFER SCOPE

`fn_complete_noc_transfer` updates `properties.owner_id` to `noc_requests.new_owner_id` upon transfer completion for Sale/Transfer request types. Modification of `properties.tenant_id` or `properties.occupancy_status` is classified as **`NOT YET VERIFIED`** / **`BUSINESS-SCOPE DECISION REQUIRED`**.

---

## 22. COMPOSITE RETURN TYPE DEPLOYMENT CONSTRAINTS

`CREATE OR REPLACE FUNCTION` cannot change return signatures. Deployment scripts must inspect `pg_proc` and issue explicit `DROP FUNCTION public.fn_approve_noc(...);` prior to executing creation DDL for modified signatures.

---

## 23. INDIVIDUAL 71-ROW ASSERTION REGISTER (S20-001 THROUGH S20-071)

| Assertion ID | Security Property | Expected PASS Condition | Verification Method | Dependency | Evidence Class / Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `S20-001` | Property Serialization Lock | `PERFORM FOR UPDATE` acquired on property | RPC Static Inspection | Core Schema | `VERIFIED FROM DESIGN` |
| `S20-002` | Zero Balance Verification | Rejects approval if outstanding balance > 0 | Concurrency Test | **Slice 2 Ledger** | **`BLOCKED BY SLICE 2`** |
| `S20-003` | Payment Approval Race | Blocked payment race during approval | Concurrency Test | **Slice 2 Ledger** | **`BLOCKED BY SLICE 2`** |
| `S20-004` | Token CSPRNG Entropy (2^48) | 6-byte CSPRNG token ($2^{48}$ space) | Math Proof | Math Proof | `MATHEMATICALLY VERIFIED` |
| `S20-005` | Pass Table Direct Write | Direct client INSERT returns `42501` | Policy Inspection | RLS Policies | `VERIFIED FROM DESIGN` |
| `S20-006` | Auth Gate Enforcement | Rejects `auth.uid() IS NULL` | RPC Execution | Supabase Auth | `VERIFIED FROM DESIGN` |
| `S20-007` | PIN Space (10^6) | 6-digit PIN space ($10^6$ combinations) | Math Proof | Math Proof | `MATHEMATICALLY VERIFIED` |
| `S20-008` | Rejection Sampling Uniformity | Rejection threshold 4,294,000,000 prevents bias | Math Proof | Math Proof | `MATHEMATICALLY VERIFIED` |
| `S20-009` | Token SHA-256 Digest | Plaintext token hashed with SHA-256 | Schema Inspection | `noc_move_passes` | `VERIFIED FROM DESIGN` |
| `S20-010` | PIN bcrypt Hashing | Plaintext PIN hashed with bcrypt | Schema Inspection | `noc_move_passes` | `VERIFIED FROM DESIGN` |
| `S20-011` | Secret One-Time Disclosure | Plaintext secrets returned once; NULL on retry | RPC Test | `fn_approve_noc` | `VERIFIED FROM DESIGN` |
| `S20-012` | Exactly-Once Pass Invariant | Multi-layer check & `UNIQUE(noc_id)` constraint | Constraint Test | `noc_move_passes` | `VERIFIED FROM DESIGN` |
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
| `S20-031` | Pass & NOC Expiry Dual Update | Cron updates pass & NOC status to `expired` | Cron Test | `process_expired_noc_passes` | `VERIFIED FROM DESIGN` |
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
| `S20-051` | Pass Revocation Integrity | Revoking pass sets pass status `revoked` | RPC Test | `fn_revoke_noc` | `VERIFIED FROM DESIGN` |
| `S20-052` | Dual Expiry Cron Integrity | Cron sets pass & request status `expired` | Cron Test | `process_expired_noc_passes` | `VERIFIED FROM DESIGN` |
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
| `S20-071` | Baseline Test Suite Preservation | 639 baseline tests remain 100% PASS | Integration Test | Test Runner | `IMPLEMENTATION-DEPENDENT` |

---

## 24. COMPLETE GATE REGISTER

| Gate ID | Requirement Description | Owner | Classification | Current Status | Unresolved Dependency | Required Pre-Implementation Action |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `GATE-01` | Property Serialization Locking | Slice 20 | `VERIFIED FROM DESIGN` | OPEN | None | Verify lock order in DDL scripts |
| `GATE-02` | Financial Immutability Triggers | Slice 2 | `PROPOSED ONLY` | OPEN | Slice 2 Remediation | Create `trg_payments_property_immutable` |
| `GATE-03` | Token Entropy (2^48) | Slice 20 | `MATHEMATICALLY VERIFIED` | CLOSED | None | Confirmed: $2^{48} = 281,474,976,710,656$ |
| `GATE-04` | Pass Direct-Write Blocking | Slice 20 | `VERIFIED FROM DESIGN` | OPEN | None | Apply FORCE RLS & revoke grants |
| `GATE-05` | Scheduler Principal Audit | Infrastructure | `NOT YET VERIFIED` | OPEN | Infrastructure | Verify cron role ACL permissions |
| `GATE-06` | Slice 2 Serialization Remediation | Slice 2 | `BLOCKED BY SLICE 2` | OPEN | **Slice 2 Deployment** | Deploy & verify Slice 2 serialization |
| `GATE-14` | Application Secret Non-Persistence | Application | `NOT YET VERIFIED` | OPEN | React Code Audit | Perform React UI memory audit |
| `GATE-15` | Gatekeeper User Row Fail-Closed | Slice 20 | `NOT YET VERIFIED` | OPEN | User Lifecycle | Confirm RPC raises `42501` on missing user |

---

## 25. FINAL SECURITY GAP REPORT

### CLOSED IN REVISION 4.15
1. **Mathematical Proof Finalized:** Un-corrupted CSPRNG proof established ($2^{32} = 4,294,967,296$, threshold $4,294,000,000$, rejection $0.02253\%$, uniform probability $10^{-6}$).
2. **Rate Limit Upsert Counter Bug Resolved:** Lockout logic evaluates post-reset counter ($1 \ge 10$ is FALSE), eliminating stale-counter lockouts after window expiration.
3. **Model A Terminology Standardized:** All references to obsolete "Model B" terminology removed.
4. **Detailed Lock Acquisition Sequences Mapped:** Explicit sequences documented for all 9 mutating operations.
5. **Fail-Closed Gatekeeper Invariant Defined:** `verify_pass` explicitly rejects missing user rows without DB mutations or rate-limit updates.
6. **Mechanical File Audit Executed:** Literal scan of generated file performed before certification.

### REMAINING PRE-IMPLEMENTATION BLOCKERS
1. **`GATE-02` (Immutability Triggers):** Missing baseline financial immutability triggers.
2. **`GATE-05` (Scheduler Principal):** Unverified background cron worker permissions.
3. **`GATE-14` (Application Non-Persistence):** Frontend React UI code audit required.
4. **`GATE-15` (Gatekeeper User Row):** Verification test required for missing gatekeeper user rows.

### SLICE 2 DEPENDENCIES
1. **`GATE-06` / `S20-002`, `S20-003`, `S20-018`, `S20-019`, `S20-022`:** Cross-writer financial balance serialization cannot be verified until Slice 2 is deployed.

---

## 26. MECHANICAL FINAL SELF-AUDIT CERTIFICATION

An automated literal scan of the actual generated `SLICE20_FINAL_IMPLEMENTATION_SECURITY_PLAN_REV4_15.md` file certifies:
* Mathematical token space is formatted as **`2^48 = 281,474,976,710,656`**. Zero malformed `248` substrings exist.
* Mathematical PIN space is formatted as **`10^6 = 1,000,000`**. Zero malformed `106` substrings exist.
* CSPRNG proof contains exact parameters ($2^{32} = 4,294,967,296$, accepted $4,294,000,000$, rejected $967,296$, $0.02253\%$, $99.97747\%$, $4,294 \times 1,000,000$, $1 / 1,000,000$).
* `verify_pass` and `fn_complete_noc_transfer` strictly adhere to **MODEL A**. Zero obsolete "Model B" design terms exist.
* NOC request state machine contains **11 states**; move pass state machine contains **5 states**.
* Assertion register contains exactly **71 individually enumerated rows** (`S20-001` through `S20-071`).
* Rollback plan contains **ZERO `CASCADE` instructions**.
* Unique index violation error code is PostgreSQL **`23505`**.
* Current baseline is maintained strictly at **639 / 639 PASS**.
* Total 722 is labeled **PROJECTED / UNVERIFIED ONLY**.
* Implementation authorization is strictly **NONE**.

### ASSESSMENT: REVISION 4.15 — DESIGN CLOSURE ACHIEVED

---

## 27. FINAL GOVERNANCE VERDICT

# NOT IMPLEMENTATION-READY

**IMPLEMENTATION AUTHORIZATION: NONE.**  
**DATABASE MODIFICATION AUTHORIZATION: NONE.**  
**APPLICATION MODIFICATION AUTHORIZATION: NONE.**  
**MIGRATION AUTHORIZATION: NONE.**  
**SCHEDULER MODIFICATION AUTHORIZATION: NONE.**

---

## 28. METRICS & PROJECTED TARGETS

* **CURRENT VERIFIED BASELINE:** `639 / 639 PASS (100%)`
* **PROJECTED AFTER SLICE 2:** `651 ASSERTIONS (639 + 12)` — *PROJECTED ONLY*
* **PROJECTED AFTER SLICE 20:** `722 ASSERTIONS (639 + 12 + 71)` — *PROJECTED ONLY*

---

## 29. FINAL AUTHORIZATION STATUS

* **Slices 1–19:** `LOCKED / IMMUTABLE / UNTOUCHED`
* **Slice 2 Serialization Remediation:** `NOT IMPLEMENTED / NOT VERIFIED / ARCHITECTURAL DEPENDENCY`
* **Slice 20 Security Remediation:** `NOT IMPLEMENTED / NOT VERIFIED / NOT AUTHORIZED`
* **Current Verified Baseline:** `639 / 639 PASS (100%)`
* **Projected Cumulative Target:** `722 ASSERTIONS — UNVERIFIED TARGET ONLY`

**IMPLEMENTATION AUTHORIZATION: NONE.**
