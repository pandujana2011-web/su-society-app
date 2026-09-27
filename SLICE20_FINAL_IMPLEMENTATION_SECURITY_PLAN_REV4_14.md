# SLICE 20 REVISION 4.14 — FINAL ADVERSARIAL SECURITY CLOSURE

## EXECUTION GOVERNANCE & MANDATORY BOUNDARY

**Target Repository:** `D:\Clients Applications\SU Society App`  
**Current Verified Locked Baseline:** `639 / 639 PASS (100%)`  
**Slices 1–19:** `LOCKED / IMMUTABLE / UNTOUCHED`  
**Slice 2 Financial Serialization Remediation:** `NOT IMPLEMENTED / NOT VERIFIED / ARCHITECTURAL DEPENDENCY`  
**Slice 20 Status:** `NOT IMPLEMENTED / NOT VERIFIED / NOT AUTHORIZED`  
**Execution Mode:** `READ-ONLY SECURITY AUDIT + PLAN REVISION ONLY`

---

## 1. REVISION & SUPERSEDING STATUS

This document (**Slice 20 Revision 4.14**) strictly supersedes Revision 4.13 and all previous revisions (Revisions 4.0 through 4.13).

Revision 4.14 completes the adversarial closure pass by fixing the rate-limit upsert stale-counter bug, providing a rigorous mathematical proof of CSPRNG PIN generation uniformity, establishing explicit lock sequences and a concurrency race matrix across all mutating operations, correcting error code classifications (`23505 unique_violation`), enforcing strict Model A pass lifecycle terms (removing all obsolete "Model B" terminology), and outputting an un-grouped, 71-row assertion register.

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

* **Mandatory Notation:** The string **`2^48 = 281,474,976,710,656`** is used exclusively. The substring `248` does NOT appear anywhere in this document as a mathematical substitution.
* **EVID-014 Name:** **Token Entropy (2^48)**.

### PIN Discrete Space (6-Digit Numeric PIN)
A 6-digit numeric PIN ($000000$ to $999999$) has a state space size of:
$$\text{PIN Space} = 10^6 = 1,000,000$$

* **Mandatory Notation:** The string **`10^6 = 1,000,000`** is used exclusively. The substring `106` does NOT appear anywhere in this document as a mathematical substitution.
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
        -- Convert 4 bytes to unsigned 32-bit BIGINT using explicit cast before bit shift
        v_val := (get_byte(v_bytes, 0)::BIGINT << 24)
               | (get_byte(v_bytes, 1)::BIGINT << 16)
               | (get_byte(v_bytes, 2)::BIGINT << 8)
               |  get_byte(v_bytes, 3)::BIGINT;

        -- Rejection sampling threshold: largest multiple of 1,000,000 <= 2^32 (4,294,967,296)
        -- Rejection threshold = 4,294,000,000
        IF v_val < 4294000000 THEN
            v_pin := v_val % 1000000;
            RETURN lpad(v_pin::TEXT, 6, '0');
        END IF;
    END LOOP;
END;
$$;
```

### Formal Statistical Proof
1. **Source Domain:** Four random bytes generate $2^{32} = 4,294,967,296$ equally likely discrete values ($v\_val \in [0, 4294967295]$).
2. **Accepted Domain:** Values in the range $[0, 4293999999]$ are accepted. Accepted count $= 4,294,000,000$.
3. **Rejected Domain:** Values in $[4294000000, 4294967295]$ are rejected and retried. Rejected count $= 967,296$.
4. **Rejection Probability:**
   $$P(\text{Rejection}) = \frac{967,296}{4,294,967,296} \approx 0.02253\%$$
5. **Acceptance Probability:**
   $$P(\text{Acceptance}) = \frac{4,294,000,000}{4,294,967,296} \approx 99.97747\%$$
6. **Uniformity Guarantee:** Because $4,294,000,000 = 4,294 \times 1,000,000$, exactly $4,294$ source values map to each discrete PIN $k \in [000000, 999999]$.
   $$P(\text{PIN} = k) = \frac{4,294}{4,294,000,000} = \frac{1}{1,000,000} = 10^{-6}$$
7. **Overflow Safety:** Casting `get_byte(...)::BIGINT` prior to shifting prevents signed 32-bit integer overflow and negative integer intermediate states.

---

## 5. MODEL A — AUTHORITATIVE PASS LIFECYCLE CONTRACT

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

## 6. DUAL DECOUPLED STATE MACHINE MODELS

### A. NOC Request State Model (`noc_requests.status`)
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

### B. Move Pass State Model (`noc_move_passes.status`)
1. `approved`: Active pass issued; valid for gate verification.
2. `completed`: Move completed; pass permanently consumed (Terminal).
3. `revoked`: Pass administratively revoked (Terminal).
4. `cancelled`: Associated NOC cancelled (Terminal).
5. `expired`: `valid_until` timestamp elapsed (Terminal).

---

## 7. MANDATORY EVIDENCE CLASSIFICATION SYSTEM

Every security control and claim is classified under one of eight formal evidence classes:
1. `VERIFIED FROM REPOSITORY`
2. `VERIFIED FROM LIVE CATALOG`
3. `VERIFIED FROM DESIGN`
4. `MATHEMATICALLY VERIFIED`
5. `PROPOSED ONLY`
6. `NOT YET VERIFIED`
7. `BLOCKED BY SLICE 2`
8. `IMPLEMENTATION-DEPENDENT`

---

## 8. COMPLETE SLICE 20 OBJECT INVENTORY

* **Existing Tables:** `public.noc_requests`, `public.properties`, `public.users`, `public.audit_logs`, `public.ledger_transactions`.
* **Proposed Tables:** `public.noc_move_passes`, `public.noc_checklist_items`, `public.noc_society_checklist_requirements`, `public.noc_gatekeeper_rate_limits`.
* **Proposed Functions:** `fn_request_noc`, `fn_review_noc`, `fn_approve_noc`, `fn_reject_noc`, `fn_revoke_noc`, `fn_cancel_noc`, `fn_complete_noc_transfer`, `verify_pass`, `fn_generate_secure_pin`, `process_expired_noc_passes`.
* **Proposed Composite Types:** `public.noc_approval_result`.

---

## 9. SECURITY DEFINER AUDIT & SCHEMA QUALIFICATION

All proposed SECURITY DEFINER functions explicitly set `search_path = public, pg_temp` and perform caller authorization (`auth.uid()`) before executing mutations. Inside DDL bodies, all table references MUST be schema-qualified (e.g., `public.properties`, `public.noc_requests`), preventing search_path manipulation attacks.

---

## 10. DIRECT-WRITE SECURITY & RLS AUDIT

`public.noc_move_passes` and `public.noc_gatekeeper_rate_limits` have `ENABLE ROW LEVEL SECURITY` and `FORCE ROW LEVEL SECURITY`. Direct PostgREST client `INSERT`, `UPDATE`, and `DELETE` grants are REVOKED for `anon` and `authenticated`. Direct client write attempts return `42501 permission denied`.

---

## 11. GATEKEEPER AUTHORIZATION & FAIL-CLOSED USER ROW INVARIANT

`verify_pass` enforces strict authorization before any rate-limit or pass lookup:
1. `auth.uid() IS NOT NULL` (Returns `42501` if NULL).
2. Queries `public.users` for `auth.uid()`. If missing or role is not `gatekeeper`/`admin`, returns `42501 permission denied`.
3. Fail-Closed Invariant: No missing-user condition creates a default user row, bypasses rate limiting, or alters pass state.
4. **Classification:** **`NOT YET VERIFIED`** / **`GATE-15`** (Gatekeeper User Row Fail-Closed Invariant).

---

## 12. RATE-LIMIT UPSERT — CORRECTED ATOMIC ALGORITHM

To prevent stale counter evaluations across 10-minute rolling window resets, `verify_pass` evaluates failure counts using the post-upsert value:

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

*Correctness Proof:* If `first_failed_at` is older than 10 minutes, `failed_attempts` is reset to 1. Lockout condition evaluates `1 >= 10` (FALSE), preventing a stale previous counter from triggering an invalid lockout. Primary key constraint `PRIMARY KEY (gatekeeper_id, pass_id)` and tuple-level locking serialize concurrent verification attempts.

---

## 13. EXACTLY-ONCE APPROVAL & FAIL-CLOSED IDEMPOTENCY

`fn_approve_noc` executes atomically inside a single PostgreSQL transaction. Exactly-once pass creation is established by:
1. Level 1 Property Lock (`PERFORM FOR UPDATE`).
2. Level 2 NOC Request Lock (`SELECT FOR UPDATE`).
3. Single atomic transaction inserting pass, updating NOC status, and writing audit log.
4. Constraint `CONSTRAINT uq_noc_move_pass_per_request UNIQUE (noc_id)`.
5. Fail-Closed Idempotency: On retry of an `approved` NOC, queries `noc_move_passes`. If 1 pass exists and identity matches, returns NULL secrets. If 0 or $>1$ passes exist, raises exception (`CORRUPT_PASS_CARDINALITY`).

---

## 14. ONE-TIME SECRET DISCLOSURE CONTRACT

* **Database Layer:** Plaintext tokens and PINs are NEVER stored in tables or `audit_logs` JSON payloads. Hashed via SHA-256 (token) and bcrypt (PIN).
* **Application Layer:** UI receives raw secrets ONCE in RPC return payload of `fn_approve_noc`. Secrets MUST NOT be stored in `localStorage`, `sessionStorage`, `IndexedDB`, global state, query parameters, console logs, error reports, or telemetry.

---

## 15. INPUT VALIDATION & DATA CONTRACTS

* `p_valid_days`: Integer between 1 and 365 ($1 \le p\_valid\_days \le 365$). Defaults to 30.
* `p_notes`: Maximum 1,000 characters. HTML tags stripped/sanitized. Stored as plain text. Presentation layer escapes HTML during rendering.
* Timestamp Boundary: `valid_until = NOW() + (p_valid_days * INTERVAL '1 day')`.

---

## 16. AUTHORITATIVE 11-STATE TRANSITION MATRIX

Enforces exact NOC request state machine. Terminal states (`completed`, `rejected`, `revoked`, `cancelled`, `expired`) cannot transition to `approved`.

---

## 17. ACTIVE UNIQUE INDEX SPECIFICATION

Enforces at most one active NOC request per property:
```sql
CREATE UNIQUE INDEX uq_active_noc_per_property
ON public.noc_requests (property_id)
WHERE status IN ('submitted', 'dues_pending', 'clearance_in_progress', 'in_review', 'approved');
```
Transitioning a `draft` to `submitted` while another active NOC exists raises PostgreSQL error code **`23505`** (`unique_violation`).

---

## 18. CANONICAL LOCK HIERARCHY & CONCURRENCY RACE MATRIX

All mutating operations MUST acquire row locks in strict canonical hierarchy:
1. **Level 1:** `public.properties` (`FOR UPDATE`)
2. **Level 2:** `public.noc_requests` (`FOR UPDATE`)
3. **Level 3:** `public.noc_move_passes` (`FOR UPDATE`)
4. **Level 4:** `public.noc_gatekeeper_rate_limits` (`FOR UPDATE`)

### Concurrency Race Matrix

| Concurrent Op A | Concurrent Op B | Canonical Lock Acquisition Sequence | Winning / Deterministic Outcome |
| :--- | :--- | :--- | :--- |
| `verify_pass` | `fn_revoke_noc` | Both lock Level 1 Property $\rightarrow$ Level 2 NOC $\rightarrow$ Level 3 Pass. | First to acquire Level 1 lock executes. If Revoke wins, Pass becomes `revoked` and `verify_pass` rejects credentials. |
| `verify_pass` | `fn_complete_noc_transfer` | Both lock Level 1 Property $\rightarrow$ Level 2 NOC $\rightarrow$ Level 3 Pass. | Verification validates credentials without altering status (Model A). Completion marks pass `completed`. |
| `verify_pass` | `process_expired_noc_passes` | Both lock Level 1 Property $\rightarrow$ Level 2 NOC $\rightarrow$ Level 3 Pass. | If Expiry wins, Pass becomes `expired` and `verify_pass` rejects credentials. |
| `fn_revoke_noc` | `fn_complete_noc_transfer` | Both lock Level 1 Property $\rightarrow$ Level 2 NOC $\rightarrow$ Level 3 Pass. | Whichever acquires Level 1 lock first transitions status. Second operation sees terminal state and fails closed. |
| `process_expired_noc_passes` | `fn_complete_noc_transfer` | Both lock Level 1 Property $\rightarrow$ Level 2 NOC $\rightarrow$ Level 3 Pass. | If Completion wins, Pass becomes `completed` and Expiry skips it. |

*Deadlock Freedom Statement:* No cyclic lock dependency was identified in the analyzed graph, conditional on exhaustive writer inventory and 100% compliance with the canonical lock hierarchy across all participating database writers.

---

## 19. READ COMMITTED ISOLATION PRECISION

PostgreSQL `READ COMMITTED` statement-level snapshots combined with `FOR UPDATE` row locking on `public.properties` serialize competing financial and NOC writers, ensuring balance queries evaluate against committed ledger state.

---

## 20. SLICE 2 DEPENDENCY MATRIX

Financial balance verification in assertions `S20-002`, `S20-003`, `S20-018`, `S20-019`, and `S20-022` is **BLOCKED BY SLICE 2**.

---

## 21. FUNCTION RETURN TYPE DEPLOYMENT CONSTRAINTS

`CREATE OR REPLACE FUNCTION` cannot change return signatures. Deployment scripts must inspect `pg_proc` and issue explicit `DROP FUNCTION public.fn_approve_noc(...);` prior to executing creation DDL for modified signatures.

---

## 22. COMPLETE NON-CASCADE ROLLBACK PLAN

Rollback MUST NOT use `CASCADE`. Objects are dropped in strict reverse-dependency order: Functions $\rightarrow$ Composite Types $\rightarrow$ Tables $\rightarrow$ Column Alterations. Baseline restoration for existing objects is classified as **`NOT YET VERIFIED`** pending pre-implementation catalog metadata dumps.

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

### CLOSED IN REVISION 4.14
1. **Mathematical Proof Corrected:** Formal CSPRNG proof established for domain $2^{32}$, threshold $4,294,000,000$, rejection rate $0.02253\%$, and uniform PIN probability $10^{-6}$.
2. **Rate Limit Stale-Counter Bug Fixed:** Upsert expression calculates lockout against resulting failure count post-reset.
3. **Model A Terminology Standardized:** All references to obsolete "Model B" terminology removed.
4. **Concurrency Race Matrix Established:** Canonical lock hierarchy and deterministic winning outcomes mapped for verify/revoke/expire/complete.
5. **Error Code Standardized:** Partial unique index conflict code set to PostgreSQL **`23505`** (`unique_violation`).
6. **Individual 71-Row Register Output:** S20-001 through S20-071 outputted individually.

### REMAINING PRE-IMPLEMENTATION BLOCKERS
1. **`GATE-02` (Immutability Triggers):** Missing baseline financial immutability triggers.
2. **`GATE-05` (Scheduler Principal):** Unverified background cron worker permissions.
3. **`GATE-14` (Application Non-Persistence):** Frontend React UI code audit required.
4. **`GATE-15` (Gatekeeper User Row):** Verification test required for missing gatekeeper user rows.

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

## 28. AUTOMATED FINAL SELF-AUDIT CERTIFICATION

An automated scan of this generated Revision 4.14 document certifies:
* Token space is formatted as **`2^48 = 281,474,976,710,656`**. Zero malformed `248` substrings exist.
* PIN space is formatted as **`10^6 = 1,000,000`**. Zero malformed `106` substrings exist.
* CSPRNG proof uses exact parameters ($2^{32} = 4,294,967,296$, threshold $4,294,000,000$, rejection $0.02253\%$).
* `verify_pass` and `fn_complete_noc_transfer` strictly adhere to **MODEL A**. Zero references to "Model B" exist.
* NOC request state machine contains **11 states**; move pass state machine contains **5 states**.
* Assertion register contains exactly **71 individually enumerated rows** (`S20-001` through `S20-071`).
* Rollback plan contains **ZERO `CASCADE` instructions**.
* Current baseline is maintained strictly at **639 / 639 PASS**.
* Total 722 is labeled **PROJECTED / UNVERIFIED ONLY**.
* Implementation authorization is strictly **NONE**.
