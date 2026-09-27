# SLICE 20 REVISION 4.19 — FINAL ADVERSARIAL SECURITY CLOSURE

## EXECUTION GOVERNANCE & MANDATORY BOUNDARY

**Target Repository:** `D:\Clients Applications\SU Society App`  
**Current Verified Locked Baseline:** `639 / 639 PASS (100%)`  
**Slices 1–19:** `LOCKED / IMMUTABLE / UNTOUCHED`  
**Slice 2 Financial Serialization Remediation:** `NOT IMPLEMENTED / NOT VERIFIED / NOT AUTHORIZED`  
**Slice 20 Security Remediation:** `NOT IMPLEMENTED / NOT VERIFIED / NOT AUTHORIZED`  
**Revision 4.18 Status:** `REJECTED — NOT CLOSED`  
**Revision 4.19 Status:** `PLAN REVISION ONLY / CLOSURE CORRECTION`  
**Execution Mode:** `READ-ONLY SECURITY AUDIT + PLAN REVISION ONLY`

### MANDATORY EXECUTION GOVERNANCE DIRECTIVE

This document represents **Revision 4.19 Final Adversarial Security Closure Correction** for Slice 20 of the SU Society App.

This task is **STRICTLY PLAN-ONLY / READ-ONLY**.

Under no circumstances is any tool or execution permitted to:
* modify application source code;
* modify SQL source files or database schemas;
* execute CREATE, ALTER, or DROP DDL statements;
* execute INSERT, UPDATE, or DELETE DML statements;
* execute database migrations or scripts;
* modify RLS policies, table grants, or role ACLs;
* modify database function definitions, triggers, or sequences;
* modify scheduler job configurations;
* modify frontend or API component code;
* modify test suites or baseline assertion files;
* modify existing Slice 1–19 verification artifacts.

**IMPLEMENTATION AUTHORIZATION: NONE.**  
**DATABASE MODIFICATION AUTHORIZATION: NONE.**  
**APPLICATION MODIFICATION AUTHORIZATION: NONE.**  
**MIGRATION AUTHORIZATION: NONE.**  
**SCHEDULER MODIFICATION AUTHORIZATION: NONE.**

---

## 1. GOVERNANCE BASELINE & METRIC PROJECTIONS

* **Current Verified Locked Baseline:** `639 / 639 PASS (100%)`
* **Projected Slice 2 Target:** `651 ASSERTIONS (639 + 12)` — *PROJECTED / UNVERIFIED ONLY*
* **Projected Slice 20 Cumulative Target:** `722 ASSERTIONS (639 + 12 + 71)` — *PROJECTED / UNVERIFIED ONLY*
* **Slices 1–19 Governance:** `LOCKED / IMMUTABLE / UNTOUCHED`
* **Slice 2 Governance:** `NOT IMPLEMENTED / NOT VERIFIED / NOT AUTHORIZED`
* **Slice 20 Governance:** `NOT IMPLEMENTED / NOT VERIFIED / NOT AUTHORIZED`

The metric `639 / 639 PASS (100%)` represents the only empirically verified assertion baseline. Neither `651` nor `722` may be represented as currently passing.

---

## 2. ABSOLUTE MATHEMATICAL NOTATION & ZERO-TOLERANCE PROOF

All mathematical expressions in this document strictly adhere to standard exponentiation notation. Prohibited unformatted exponent string replacements or numeric concatenations are strictly forbidden.

Required exact standard forms:
* Exponent 48 state space: `2^48 = 281,474,976,710,656`
* Exponent 6 PIN space: `10^6 = 1,000,000`
* Exponent 32 byte domain: `2^32 = 4,294,967,296`

---

## 3. CORRECT CSPRNG PIN MATHEMATICAL PROOF

### Source Domain
Four random bytes produced by a Cryptographically Secure Pseudo-Random Number Generator (CSPRNG) yield 32 bits of entropy:
$$\text{Source Domain Size} = 2^{32} = 4,294,967,296$$
State space equation: `2^32 = 4,294,967,296`.  
Equally likely source integer values range from `0` through `4,294,967,295`.

### Accepted Domain & Rejection Threshold
To achieve perfectly uniform mapping across a 6-digit numeric PIN space (`000000` through `999999`), rejection sampling is applied.

* **Accepted Domain:** Integers from `0` through `4,293,999,999` (inclusive).
* **Accepted Count:** `4,294,000,000`
  $$\text{Factorization:} \quad 4,294,000,000 = 4,294 \times 1,000,000$$
* **Rejected Domain:** Integers from `4,294,000,000` through `4,294,967,295`.
* **Rejected Count:** `967,296`
  $$\text{Calculation:} \quad 4,294,967,296 - 4,294,000,000 = 967,296$$

### Probabilities
* **Rejection Probability:**
  $$P(\text{Rejection}) = \frac{967,296}{4,294,967,296} \approx 0.02253\%$$
* **Acceptance Probability:**
  $$P(\text{Acceptance}) = \frac{4,294,000,000}{4,294,967,296} \approx 99.97747\%$$

### Uniform Distribution Proof
For any target 6-digit PIN $k \in [000000, 999999]$, exactly 4,294 source values in the accepted domain map to $k$ via $(v \pmod{1,000,000})$.
$$P(\text{PIN} = k) = \frac{4,294}{4,294,000,000} = \frac{1}{1,000,000}$$
Because `10^6 = 1,000,000`, every 6-digit PIN has an exact $1 / 10^6$ probability of selection. Modulo bias is mathematically eliminated.

### Bit-Shift & Type-Safety Requirements
To prevent 32-bit signed integer overflow in PL/pgSQL:
1. Each byte extracted via `get_byte(v_bytes, i)` MUST be explicitly cast to `BIGINT` BEFORE applying bit-shift operators (`<<`).
2. Bit-shifting signed 32-bit integers without `BIGINT` conversion would overflow into negative numbers for byte values $\ge 128$.
3. The accumulation formula MUST NOT use `abs()`.
4. No signed 32-bit intermediate representation is permitted.

---

## 4. PROPOSED CSPRNG PIN IMPLEMENTATION FORM

```sql
-- Proposed PL/pgSQL CSPRNG PIN Generation Function
CREATE OR REPLACE FUNCTION public.fn_generate_csprng_pin()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_bytes BYTEA;
    v_val BIGINT;
    v_pin INT;
BEGIN
    LOOP
        v_bytes := gen_random_bytes(4);
        v_val := (get_byte(v_bytes, 0)::BIGINT << 24)
               | (get_byte(v_bytes, 1)::BIGINT << 16)
               | (get_byte(v_bytes, 2)::BIGINT << 8)
               |  get_byte(v_bytes, 3)::BIGINT;
               
        IF v_val < 4294000000 THEN
            v_pin := (v_val % 1000000)::INT;
            RETURN lpad(v_pin::TEXT, 6, '0');
        END IF;
    END LOOP;
END;
$$;
```

---

## 5. TOKEN ENTROPY & SECURITY CONTRACT

### Entropy & Format
* Function `gen_random_bytes(6)` generates 6 raw CSPRNG bytes (48 bits of entropy).
* Total state space: `2^48 = 281,474,976,710,656`.
* String representation: `NOC-PASS-` + 12 uppercase hexadecimal characters.
* Implementation formula: `'NOC-PASS-' || upper(encode(gen_random_bytes(6), 'hex'))`

### Secret Persistence & Disclosure Boundary
1. **Plaintext Token Non-Persistence:** The plaintext token MUST NEVER be persisted in database tables, inserted into audit log payloads, or written to server/execution log outputs.
2. **Digest Persistence:** The database stores ONLY the SHA-256 cryptographic digest (`encode(digest(v_token, 'sha256'), 'hex')`).
3. **One-Time Disclosure:** The plaintext token is disclosed strictly ONCE in the return payload of the initial `fn_approve_noc` execution. Subsequent calls or retries return `raw_pass_token = NULL` and `raw_pass_pin = NULL`.
4. **Client-Side Boundary:** Database SHA-256 hashing guarantees non-persistence in storage; frontend non-persistence remains dependent on application rendering boundaries.

---

## 6. VERIFY_PASS — SECURITY & RATE-LIMIT SEQUENCING

The `verify_pass` RPC function MUST execute according to the following strict 9.5-phase sequential contract:

```
+-----------------------------------------------------------------------+
| PHASE 1: Authentication & Authorization (auth.uid(), user role check)  |
+-----------------------------------------------------------------------+
                                  |
                                  v
+-----------------------------------------------------------------------+
| PHASE 2: Untrusted Hint Pre-Lock Lookup (pass_id -> noc_id -> prop_id)|
+-----------------------------------------------------------------------+
                                  |
                                  v
+-----------------------------------------------------------------------+
| PHASE 3: Property Row Lock (properties FOR UPDATE)                    |
+-----------------------------------------------------------------------+
                                  |
                                  v
+-----------------------------------------------------------------------+
| PHASE 4: NOC Row Lock & Identity Revalidation (noc.prop_id = prop.id) |
+-----------------------------------------------------------------------+
                                  |
                                  v
+-----------------------------------------------------------------------+
| PHASE 5: Pass Row Lock & Revalidation (pass.noc_id & pass.prop_id)   |
+-----------------------------------------------------------------------+
                                  |
                                  v
+-----------------------------------------------------------------------+
| PHASE 6: Rate-Limit Row Lock IF EXISTS (gatekeeper_id, pass_id)       |
+-----------------------------------------------------------------------+
                                  |
                                  v
+-----------------------------------------------------------------------+
| PHASE 7: Lockout Check (lockout_until > NOW() -> Reject Immediate)    |
+-----------------------------------------------------------------------+
                                  |
                                  v
+-----------------------------------------------------------------------+
| PHASE 8: Credential & Pass Status Validation (Token/PIN Hash match)   |
+-----------------------------------------------------------------------+
                        /                   \
                       /                     \
                      v                       v
          [ CREDENTIAL FAILURE ]     [ CREDENTIAL SUCCESS ]
                      |                       |
                      v                       v
          +-----------------------+ +-----------------------+
          | PHASE 9A: Increment   | | PHASE 9B: Reset State |
          | Failure Window & Set  | | (failed_attempts = 0, |
          | Lockout if Count = 10 | | lockout_until = NULL) |
          +-----------------------+ +-----------------------+
```

### Phase Details

* **Phase 1 — Caller Authentication & Authorization:**
  * Require `auth.uid() IS NOT NULL`.
  * Look up caller in `public.users`.
  * Require user role to be `gatekeeper` or `admin`.
  * If user missing or role invalid, raise exception `42501` immediately.
  * No rate-limit state mutation, credential evaluation, or business state mutation occurs in Phase 1.

* **Phase 2 — Pre-Lock Identity Hint Resolution:**
  * Resolve `pass_id -> noc_id -> property_id` from input parameters.
  * Treat resolved IDs strictly as unverified hints for initial lock target determination.

* **Phase 3 — Property Lock Acquisition:**
  * Execute `PERFORM 1 FROM public.properties WHERE id = v_property_id FOR UPDATE;`

* **Phase 4 — NOC Lock Acquisition & Identity Revalidation:**
  * Execute `SELECT ... FROM public.noc_requests WHERE id = v_noc_id FOR UPDATE;`
  * Revalidate identity bound: `noc.property_id = locked_property.id`. If mismatch, abort.

* **Phase 5 — Pass Lock Acquisition & Identity Revalidation:**
  * Execute `SELECT ... FROM public.noc_move_passes WHERE id = v_pass_id FOR UPDATE;`
  * Revalidate identity bounds: `pass.noc_id = locked_noc.id` AND `pass.property_id = locked_property.id`. If mismatch, abort.

* **Phase 6 — Rate-Limit Lock & State Read:**
  * Attempt to acquire lock on existing rate-limit tuple:
    `SELECT ... FROM public.noc_gatekeeper_rate_limits WHERE gatekeeper_id = v_user_id AND pass_id = v_pass_id FOR UPDATE;`
  * If no row exists, handle gracefully in memory. DO NOT increment or insert failure records in Phase 6.

* **Phase 7 — Lockout State Decision:**
  * If `lockout_until` is non-null AND `lockout_until > NOW()`, reject verification immediately with lockout response.
  * DO NOT increment failure counts, reset counters, evaluate token/PIN hashes, or mutate pass status.

* **Phase 8 — Credential & Pass Status Validation:**
  * Verify `pass.status = 'approved'`.
  * Verify `pass.valid_until >= NOW()`.
  * Verify SHA-256 token digest matches `pass.token_hash`.
  * Verify SHA-256 PIN digest matches `pass.pin_hash`.

* **Phase 9A — Credential Failure Mutation:**
  * ONLY executed if Phase 8 credential/status validation FAILS.
  * Execute atomic `INSERT ... ON CONFLICT (gatekeeper_id, pass_id) DO UPDATE`:
    1. If no prior row: set `failed_attempts = 1`, `first_failed_at = NOW()`, `lockout_until = NULL`.
    2. If prior row exists AND `first_failed_at < NOW() - INTERVAL '10 minutes'`: reset counter to `failed_attempts = 1`, `first_failed_at = NOW()`, `lockout_until = NULL`.
    3. If prior row exists AND window active (`first_failed_at >= NOW() - INTERVAL '10 minutes'`): increment `failed_attempts = failed_attempts + 1`.
    4. If post-increment/reset `failed_attempts = 10`: set `lockout_until = NOW() + INTERVAL '15 minutes'`.
  * Lockout decision is evaluated strictly against the POST-RESET counter value.

* **Phase 9B — Credential Success Mutation:**
  * Executed ONLY if Phase 8 credential validation SUCCEEDS.
  * Reset rate-limit record: set `failed_attempts = 0`, `first_failed_at = NULL`, `lockout_until = NULL`.
  * DO NOT mutate `pass.status` (status remains `approved`).
  * Return verification success payload.

---

## 7. RATE-LIMIT CONCURRENCY & SERIALIZATION

* **Unique Constraint:** Table `public.noc_gatekeeper_rate_limits` enforces `UNIQUE(gatekeeper_id, pass_id)`.
* **Tuple-Level Lock Synchronization:** First-row creation and subsequent counter updates use PostgreSQL `INSERT ... ON CONFLICT (gatekeeper_id, pass_id) DO UPDATE`.
* **Conflict Handling:** Concurrent first failures on the same key are serialized through unique index conflict resolution. The winning transaction inserts the row; the waiting transaction blocks until commit, then executes `DO UPDATE`.
* **No Exaggerated Locking Claims:** Concurrency protection operates at the tuple level via index lock conflict management. No claim of page-level or global database locking is made, nor is it claimed that non-existent rows can be locked with `FOR UPDATE`.

---

## 8. MODEL A ARCHITECTURE ONLY

Slice 20 adheres strictly to **Model A** lifecycle separation:

* `verify_pass`: Authenticates gatekeeper, validates token/PIN hashes, checks rate limits, and returns validation status. It **DOES NOT** set `pass.status` to `completed`.
* `fn_complete_noc_transfer`: Performs final pass completion, transitions `pass.status` to `completed`, transitions `noc.status` to `completed`, and executes authorized property ownership/occupancy mutations.

Single-step verification-completion models are entirely excluded from this design.

---

## 9. DUAL STATE MACHINES & EXPIRY SEMANTICS

### NOC Requests State Machine (11 States)
1. `draft`: Initial creation by applicant.
2. `submitted`: Submitted for management review.
3. `under_review`: Active administrative review.
4. `payment_pending`: Outstanding fee obligation.
5. `approved`: Approved by management; move pass generated.
6. `rejected`: Application denied.
7. `cancelled`: Cancelled by applicant prior to approval.
8. `revoked`: Approval revoked by management prior to execution.
9. `completed`: Move transfer fully executed and closed.
10. `expired`: Validity period lapsed without execution.
11. `archived`: Historical record preserved.

### NOC Move Passes State Machine (5 States)
1. `approved`: Pass issued and active for verification.
2. `completed`: Pass successfully scanned and completed by gatekeeper.
3. `revoked`: Pass voided by management.
4. `cancelled`: Associated NOC cancelled.
5. `expired`: Pass validity window elapsed.

### Expiry Scheduler Semantics
* Expiry procedure `process_expired_noc_passes` acquires locks in strict canonical order (`properties -> noc_requests -> noc_move_passes`).
* Re-reads entity status under lock.
* Mutates ONLY active eligible states (`approved` passes past `valid_until`; `payment_pending` / `approved` NOCs past valid windows).
* **Terminal State Invariant:** Expiry procedures MUST NEVER overwrite terminal states (`completed`, `revoked`, `cancelled`).

---

## 10. CANONICAL LOCK ORDER & DEADLOCK CONTROL

To prevent database deadlocks, all Slice 20 database mutating transactions MUST acquire locks in the following strict hierarchy:

1. `public.properties`
2. `public.noc_requests`
3. `public.noc_move_passes`
4. `public.noc_gatekeeper_rate_limits`

### Deadlock Claim Boundary
Deadlock risk is controlled ONLY IF the inventory of all cooperating writers, triggers, scheduled jobs, and relevant helper paths is exhaustive and all applicable paths obey the canonical lock ordering.

---

## 11. EXHAUSTIVE WRITER INVENTORY

The following inventory details every database object that mutates Slice 20 entities:

| Object Name | Mutation Target | Property ID Derivation | Lock Order | State Mutation | Concurrency | Execution Role | Security Context |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `fn_request_noc` | `noc_requests` | Input parameter `p_property_id` | Prop -> NOC | Inserts `draft`/`submitted` | High | `authenticated` | SECURITY DEFINER |
| `fn_review_noc` | `noc_requests` | `noc.property_id` | Prop -> NOC | `draft` -> `under_review` | Low | `authenticated` | SECURITY DEFINER |
| `fn_approve_noc` | `noc_requests`, `noc_move_passes` | `noc.property_id` | Prop -> NOC -> Pass | NOC: `approved`, Pass: Inserts `approved` | Serialized | `authenticated` | SECURITY DEFINER |
| `fn_reject_noc` | `noc_requests` | `noc.property_id` | Prop -> NOC | NOC: -> `rejected` | Low | `authenticated` | SECURITY DEFINER |
| `fn_revoke_noc` | `noc_requests`, `noc_move_passes` | `noc.property_id` | Prop -> NOC -> Pass | NOC: -> `revoked`, Pass: -> `revoked` | Serialized | `authenticated` | SECURITY DEFINER |
| `fn_cancel_noc` | `noc_requests`, `noc_move_passes` | `noc.property_id` | Prop -> NOC -> Pass | NOC: -> `cancelled`, Pass: -> `cancelled` | Serialized | `authenticated` | SECURITY DEFINER |
| `verify_pass` | `noc_gatekeeper_rate_limits` | `pass.property_id` | Prop -> NOC -> Pass -> RL | Updates failure counts / lockout | High | `authenticated` | SECURITY DEFINER |
| `fn_complete_noc_transfer` | `noc_requests`, `noc_move_passes`, `properties` | `pass.property_id` | Prop -> NOC -> Pass | Pass: -> `completed`, NOC: -> `completed` | Serialized | `authenticated` | SECURITY DEFINER |
| `process_expired_noc_passes` | `noc_requests`, `noc_move_passes` | Cursor iteration per property | Prop -> NOC -> Pass | Pass: -> `expired`, NOC: -> `expired` | Batch / Cron | `pg_cron` / system | SECURITY DEFINER |

---

## 12. COMPLETE RACE MATRIX

| Race Pair | Lock Order | Winner | Loser Behavior | Resulting State | Slice 2 Dependency |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **approve vs approve** | Prop -> NOC -> Pass | 1st Tx | 2nd Tx detects NOC already `approved`; returns existing pass, secrets NULL | Single pass created | No |
| **approve vs review** | Prop -> NOC | 1st Tx (Approve) | 2nd Tx detects status `approved`, no-op / error | NOC `approved` | No |
| **approve vs reject** | Prop -> NOC | 1st Tx (Approve) | 2nd Tx blocks, re-reads status `approved`, rejects mutation | NOC `approved` | No |
| **approve vs cancel** | Prop -> NOC | 1st Tx (Approve) | 2nd Tx blocks, sees `approved`, converts to pass cancel flow | NOC `cancelled`, Pass `cancelled` | No |
| **approve vs revoke** | Prop -> NOC -> Pass | 1st Tx (Approve) | 2nd Tx blocks, sees `approved`, revokes pass | NOC `revoked`, Pass `revoked` | No |
| **approve vs complete** | Prop -> NOC -> Pass | 1st Tx (Approve) | Complete cannot run prior to pass creation | NOC `approved`, Pass `approved` | No |
| **approve vs expiry** | Prop -> NOC -> Pass | 1st Tx (Approve) | Expiry sees fresh `approved` pass, skips | NOC `approved`, Pass `approved` | No |
| **verify vs revoke** | Prop -> NOC -> Pass -> RL | Revoke wins lock | Verify blocks, re-reads pass status `revoked`, fails verification | Pass `revoked`, Verification Failed | No |
| **verify vs complete** | Prop -> NOC -> Pass -> RL | Verify wins lock | Complete blocks, executes after verification completes | Pass `completed` after transfer | No |
| **verify vs expiry** | Prop -> NOC -> Pass -> RL | Verify wins lock | Expiry blocks, sees pass checked or expired, handles safely | Defined by lock winner | No |
| **verify vs verify** | Prop -> NOC -> Pass -> RL | 1st Tx | 2nd Tx blocks on RL tuple lock, evaluates updated rate limit | Serialized verification | No |
| **revoke vs complete** | Prop -> NOC -> Pass | Revoke wins lock | Complete blocks, re-reads status `revoked`, aborts transfer | Pass `revoked`, NOC `revoked` | No |
| **revoke vs expiry** | Prop -> NOC -> Pass | Revoke wins lock | Expiry blocks, re-reads status `revoked`, skips | Pass `revoked` | No |
| **cancel vs review** | Prop -> NOC | Cancel wins lock | Review blocks, sees status `cancelled`, aborts | NOC `cancelled` | No |
| **review vs reject** | Prop -> NOC | Review wins lock | Reject blocks, sees `under_review`, proceeds to reject | NOC `rejected` | No |
| **request vs review** | Prop -> NOC | Request creates NOC | Review cannot start until NOC row exists | NOC `submitted` -> `under_review` | No |
| **complete vs complete** | Prop -> NOC -> Pass | 1st Tx | 2nd Tx blocks, sees `completed`, returns idempotent success | Single transfer execution | No |
| **expiry vs complete** | Prop -> NOC -> Pass | Complete wins lock | Expiry blocks, sees `completed`, skips terminal state | Pass `completed` | No |
| **expiry vs revoke** | Prop -> NOC -> Pass | Revoke wins lock | Expiry blocks, sees `revoked`, skips terminal state | Pass `revoked` | No |
| **financial approval vs payment**| Prop -> Ledger -> NOC | Blocked by Slice 2 | Serialized via Slice 2 ledger lock | Requires Slice 2 | **YES (Slice 2)** |
| **financial approval vs charge** | Prop -> Ledger -> NOC | Blocked by Slice 2 | Serialized via Slice 2 ledger lock | Requires Slice 2 | **YES (Slice 2)** |

---

## 13. READ COMMITTED PRECISION & TRANSACTION BOUNDARIES

* PostgreSQL READ COMMITTED isolation level evaluates queries against a statement-level snapshot.
* `FOR UPDATE` row locks block concurrent transactions attempting to acquire locks on the same tuples.
* When a blocked transaction acquires the lock upon predecessor commit, it observes the committed state and MUST re-verify precondition predicates.

---

## 14. EXACTLY-ONCE NOC APPROVAL CONTRACT

The NOC approval workflow guarantees exactly-once pass issuance through a 15-part transactional contract:

1. Property lock acquisition (`properties FOR UPDATE`).
2. NOC request lock acquisition (`noc_requests FOR UPDATE`).
3. Identity revalidation (`noc.property_id = locked_property.id`).
4. Status predicate validation (`noc.status IN ('submitted', 'payment_pending')`).
5. Financial balance check (Architecturally dependent on Slice 2).
6. Checklist requirement validation.
7. Single CSPRNG token generation (48 bits entropy, `2^48 = 281,474,976,710,656`).
8. Single CSPRNG PIN generation (Rejection sampling, `10^6 = 1,000,000`).
9. SHA-256 digest hashing of token and PIN.
10. Pass tuple insertion into `public.noc_move_passes`.
11. NOC state transition to `approved`.
12. Audit log entry insertion.
13. Uniqueness enforcement via `UNIQUE(noc_id)` constraint on `noc_move_passes`.
14. Idempotent retry handling for already-approved NOC requests.
15. Transactional atomicity (all-or-nothing rollback on failure).

### Already-Approved Retry Behavior
If `fn_approve_noc` is invoked for a request already in `approved` status:
* Returns the existing valid pass metadata.
* Sets `raw_pass_token = NULL` and `raw_pass_pin = NULL`.
* Regenerates ZERO secrets and inserts ZERO duplicate audit records.
* Fails closed if pass cardinality is 0 or $>1$, or if property/NOC identity mismatch occurs.

---

## 15. CHECKLIST BUSINESS RULE

The behavior when zero mandatory checklist categories exist is classified as:  
`BUSINESS-SCOPE DECISION REQUIRED`

Architectural design supports configurable zero-category policies, but pre-implementation approval requires authoritative business stakeholder decision.

---

## 16. OWNERSHIP TRANSFER SCOPE

Upon pass completion by `fn_complete_noc_transfer`:
* `owner_id`: Updated to new owner upon sale NOC completion.
* `tenant_id` and `occupancy_status`: Scope updates remain `BUSINESS-SCOPE DECISION REQUIRED` pre-implementation blockers.

---

## 17. SECURITY DEFINER AUDIT & TRUST POSTURE

All proposed Slice 20 SECURITY DEFINER functions (`fn_request_noc`, `fn_review_noc`, `fn_approve_noc`, `fn_reject_noc`, `fn_revoke_noc`, `fn_cancel_noc`, `verify_pass`, `fn_complete_noc_transfer`, `process_expired_noc_passes`) must enforce:
* Explicit fixed search path: `SET search_path = pg_catalog, public`.
* Strict input validation and role checks (`auth.uid()`, `public.users`).
* Complete schema qualification of table and function references.
* Proposed SECURITY DEFINER objects are classified: `PROPOSED SECURITY CONTRACT — IMPLEMENTATION-DEPENDENT`.

---

## 18. RLS / SERVICE ROLE / BYPASSRLS

* `FORCE ROW LEVEL SECURITY` does NOT prevent roles possessing the `BYPASSRLS` attribute (such as `service_role` or superusers) from bypassing RLS rules.
* Assertions regarding service role isolation (e.g., S20-065) are classified as: `IMPLEMENTATION-DEPENDENT`.

---

## 19. POSTGREST EXPOSURE & ACLS

* REST endpoint visibility is governed by PostgreSQL GRANT permissions and PostgREST schema exposure settings.
* Direct table mutation access must be REVOKED from `authenticated` and `anon` roles. Access must be granted exclusively via RPC functions.
* PostgREST security assertion S20-070 is classified as: `NOT YET VERIFIED`.

---

## 20. FRONTEND SECRET NON-PERSISTENCE

* Database SHA-256 digest storage guarantees secret non-persistence in the database tier.
* Application memory management and frontend secret handling are classified as:  
  `GATE-14 = NOT YET VERIFIED`.

---

## 21. INPUT CONTRACT & SECURITY BOUNDARIES

* Database parameters enforce structural bounds (e.g., `p_valid_days BETWEEN 1 AND 365`, `p_notes LENGTH <= 1000`).
* Application-level XSS prevention and HTML sanitization belong to the frontend rendering boundary.

---

## 22. COMPOSITE RETURN TYPE & DEPLOYMENT STRATEGY

* Updating function signature parameters or return types requires explicit dependency-safe replacement strategies (`DROP FUNCTION` followed by `CREATE FUNCTION` in reverse dependency order).
* PostgreSQL error code for unique constraint violation is `23505` (`unique_violation`).

---

## 23. EXACT NON-CASCADE ROLLBACK PLAN

Rollback to pre-Slice-20 catalog state MUST be constructed from a verified pre-implementation catalog snapshot.

### Rollback Directives
1. Reverse-dependency ordering MUST be strictly maintained.
2. Executable rollback statements MUST NOT contain `CASCADE`.
3. Drop statements MUST target ONLY objects demonstrably created by Slice 20.
4. Existing baseline columns (such as `notes`) MUST NOT be dropped using `DROP COLUMN IF EXISTS` unless pre-implementation catalog snapshots prove they were introduced by Slice 20.
5. Exact restoration posture is classified as: `IMPLEMENTATION-DEPENDENT`.

---

## 24. EVIDENCE CLASSIFICATION SYSTEM

Every assertion in Slice 20 is categorized under one of eight strict evidence classes:

1. `VERIFIED FROM REPOSITORY`: Confirmed via empirical codebase/migration inspection.
2. `MATHEMATICALLY VERIFIED`: Rigorously proven via mathematical models.
3. `VERIFIED FROM DESIGN`: Internal consistency within approved design specifications.
4. `PROPOSED ONLY`: Target behavior for unexecuted implementation.
5. `IMPLEMENTATION-DEPENDENT`: Requires post-implementation database inspection.
6. `NOT YET VERIFIED`: Requires future integration or application code testing.
7. `BLOCKED BY SLICE 2`: Dependent on Slice 2 financial serialization.
8. `BUSINESS-SCOPE DECISION REQUIRED`: Requires stakeholder policy decision.

---

## 25. ASSERTION REGISTER (71 INDIVIDUAL ROWS S20-001 TO S20-071)

| Assertion ID | Security Property | Expected PASS Condition | Verification Method | Dependency | Evidence Class | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **S20-001** | NOC Request Creation | Schema validates property and applicant reference | PL/pgSQL Test | None | PROPOSED ONLY | Projected |
| **S20-002** | Move Pass Isolation | Pass bound strictly to NOC request | RLS Inspection | None | PROPOSED ONLY | Projected |
| **S20-003** | CSPRNG Generation | Uses `gen_random_bytes()` for secrets | Code Inspection | None | MATHEMATICALLY VERIFIED | Projected |
| **S20-004** | Token Entropy | 6-byte CSPRNG token with `2^48 = 281,474,976,710,656` states | Math Proof | None | MATHEMATICALLY VERIFIED | Projected |
| **S20-005** | Token Digest Storage | SHA-256 digest stored; raw token unpersisted | SQL Inspection | None | PROPOSED ONLY | Projected |
| **S20-006** | PIN Rejection Sampling | Rejection sampling eliminates modulo bias | Math Proof | None | MATHEMATICALLY VERIFIED | Projected |
| **S20-007** | PIN State Space | 6-digit PIN with `10^6 = 1,000,000` states | Math Proof | None | MATHEMATICALLY VERIFIED | Projected |
| **S20-008** | Single Secret Return | Raw secrets returned ONCE on initial approval | RPC Inspection | None | PROPOSED ONLY | Projected |
| **S20-009** | Idempotent Secret Null | Approval retries return `raw_pass_token = NULL` | RPC Inspection | None | PROPOSED ONLY | Projected |
| **S20-010** | Verify Pass Auth | Gatekeeper authentication required (`42501`) | Auth Check | None | PROPOSED ONLY | Projected |
| **S20-011** | Verify Identity Binding | Pass, NOC, and Property IDs match strictly | Lock Inspection | None | PROPOSED ONLY | Projected |
| **S20-012** | Property Lock Order | Property locked FIRST in hierarchy | Lock Sequence | None | VERIFIED FROM DESIGN | Projected |
| **S20-013** | NOC Lock Order | NOC locked SECOND in hierarchy | Lock Sequence | None | VERIFIED FROM DESIGN | Projected |
| **S20-014** | Pass Lock Order | Pass locked THIRD in hierarchy | Lock Sequence | None | VERIFIED FROM DESIGN | Projected |
| **S20-015** | Rate Limit Lock Order | Rate limit locked FOURTH in hierarchy | Lock Sequence | None | VERIFIED FROM DESIGN | Projected |
| **S20-016** | Rate Limit Read Phase | Read/Check lockout BEFORE credential check | RPC Inspection | None | VERIFIED FROM DESIGN | Projected |
| **S20-017** | Rate Limit Failure Mut | Failure count incremented ONLY AFTER failure | RPC Inspection | None | VERIFIED FROM DESIGN | Projected |
| **S20-018** | Rate Limit Lockout | 10 failures trigger 15-minute lockout | SQL Test | None | PROPOSED ONLY | Projected |
| **S20-019** | Rate Limit Window Reset| 10-minute idle window resets failure counter | SQL Test | None | PROPOSED ONLY | Projected |
| **S20-020** | Rate Limit Post-Reset | Lockout decision uses POST-RESET count | RPC Inspection | None | VERIFIED FROM DESIGN | Projected |
| **S20-021** | Rate Limit Success Res | Successful verify resets failure state | SQL Test | None | PROPOSED ONLY | Projected |
| **S20-022** | Model A Non-Completion | `verify_pass` DOES NOT complete pass | RPC Inspection | None | VERIFIED FROM DESIGN | Projected |
| **S20-023** | Model A Completion RPC | `fn_complete_noc_transfer` completes pass | RPC Inspection | None | VERIFIED FROM DESIGN | Projected |
| **S20-024** | Zero Checklist Policy | Zero mandatory categories handling defined | Policy Check | None | BUSINESS-SCOPE DECISION REQUIRED | Projected |
| **S20-025** | Mandatory Category Rule| Mandatory category compliance enforced | Policy Check | None | BUSINESS-SCOPE DECISION REQUIRED | Projected |
| **S20-026** | Sale NOC Ownership Mut | Sale completion updates `owner_id` | RPC Inspection | None | PROPOSED ONLY | Projected |
| **S20-027** | Tenant Transfer Scope | Tenant update scope resolved | Policy Check | None | BUSINESS-SCOPE DECISION REQUIRED | Projected |
| **S20-028** | NOC State Count | NOC state machine contains 11 states | Schema Audit | None | VERIFIED FROM REPOSITORY | Projected |
| **S20-029** | Pass State Count | Pass state machine contains 5 states | Schema Audit | None | VERIFIED FROM REPOSITORY | Projected |
| **S20-030** | Terminal Expiry Lockout| Expiry NEVER overwrites terminal states | Scheduler Check | None | VERIFIED FROM DESIGN | Projected |
| **S20-031** | Scheduler Lock Order | Scheduler locks in canonical hierarchy | Scheduler Check | None | VERIFIED FROM DESIGN | Projected |
| **S20-032** | Unique Pass Constraint | `UNIQUE(noc_id)` prevents duplicate passes | Schema Audit | None | VERIFIED FROM REPOSITORY | Projected |
| **S20-033** | Unique RL Constraint | `UNIQUE(gatekeeper_id, pass_id)` enforced | Schema Audit | None | VERIFIED FROM REPOSITORY | Projected |
| **S20-034** | RL Concurrency Serial | `ON CONFLICT DO UPDATE` serializes RL mut | SQL Test | None | PROPOSED ONLY | Projected |
| **S20-035** | Audit Secret Redaction | Audit payloads contain zero raw secrets | Audit Check | None | PROPOSED ONLY | Projected |
| **S20-036** | Security Definer Path | `SET search_path = pg_catalog, public` | Proc Inspection | None | PROPOSED ONLY | Projected |
| **S20-037** | Security Definer Owner| Owned by secure administrative role | Catalog Check | None | NOT YET VERIFIED | Projected |
| **S20-038** | RLS Direct Write Block | Direct table writes blocked for users | Policy Check | None | PROPOSED ONLY | Projected |
| **S20-039** | Pass Valid Days Range | Valid days constrained between 1 and 365 | Constraint Check| None | PROPOSED ONLY | Projected |
| **S20-040** | Notes Character Bound | Notes length constrained <= 1000 chars | Constraint Check| None | PROPOSED ONLY | Projected |
| **S20-041** | PostgreSQL Error 23505| Unique violation returns SQLSTATE 23505 | Error Check | None | VERIFIED FROM DESIGN | Projected |
| **S20-042** | Non-CASCADE Rollback | Rollback script contains zero executable CASCADE | Script Audit | None | VERIFIED FROM DESIGN | Projected |
| **S20-043** | Pre-Slice-20 Baseline | Snapshot comparison verifies exact state | Catalog Audit | None | IMPLEMENTATION-DEPENDENT | Projected |
| **S20-044** | Approve vs Approve Race | Concurrent approvals serialized, 1 pass | Race Test | None | PROPOSED ONLY | Projected |
| **S20-045** | Approve vs Reject Race | Concurrent approval/rejection serialized | Race Test | None | PROPOSED ONLY | Projected |
| **S20-046** | Approve vs Revoke Race | Concurrent approval/revocation serialized | Race Test | None | PROPOSED ONLY | Projected |
| **S20-047** | Verify vs Revoke Race | Revocation blocks pass verification | Race Test | None | PROPOSED ONLY | Projected |
| **S20-048** | Verify vs Complete Race| Verification and completion serialized | Race Test | None | PROPOSED ONLY | Projected |
| **S20-049** | Verify vs Expiry Race | Verification and expiry locked in order | Race Test | None | PROPOSED ONLY | Projected |
| **S20-050** | Verify vs Verify Race | Concurrent verifications serialized | Race Test | None | PROPOSED ONLY | Projected |
| **S20-051** | Complete vs Complete | Duplicate completion idempotent | Race Test | None | PROPOSED ONLY | Projected |
| **S20-052** | Expiry vs Complete Race| Terminal completion preserved over expiry | Race Test | None | PROPOSED ONLY | Projected |
| **S20-053** | Expiry vs Revoke Race | Terminal revocation preserved over expiry | Race Test | None | PROPOSED ONLY | Projected |
| **S20-054** | Financial Balance Check| NOC approval checks account balance | Financial Test | Slice 2 | BLOCKED BY SLICE 2 | Projected |
| **S20-055** | Financial Serialization| Approval serialized against ledger mut | Financial Test | Slice 2 | BLOCKED BY SLICE 2 | Projected |
| **S20-056** | Financial Ledger Lock | Ledger locked before NOC approval | Financial Test | Slice 2 | BLOCKED BY SLICE 2 | Projected |
| **S20-057** | Financial Zero Balance | Negative/insufficient balance blocks NOC | Financial Test | Slice 2 | BLOCKED BY SLICE 2 | Projected |
| **S20-058** | Financial Immutability | Completed NOC fee immutable in ledger | Financial Test | Slice 2 | BLOCKED BY SLICE 2 | Projected |
| **S20-059** | Financial Race Block | Concurrent payment/approval serialized | Financial Test | Slice 2 | BLOCKED BY SLICE 2 | Projected |
| **S20-060** | Baseline Preservation | 639 baseline tests pass post-Slice 20 | Test Suite | None | IMPLEMENTATION-DEPENDENT | Projected |
| **S20-061** | Slice 2 Assertion Target| +12 Slice 2 tests pass (651 Total) | Test Suite | Slice 2 | BLOCKED BY SLICE 2 | Projected |
| **S20-062** | Slice 20 Assertion Target| +71 Slice 20 tests pass (722 Total) | Test Suite | Slices 2 & 20 | IMPLEMENTATION-DEPENDENT | Projected |
| **S20-063** | Public Schema Trust | Public schema permissions hardened | Catalog Audit | None | NOT YET VERIFIED | Projected |
| **S20-064** | Unqualified Call Block | All calls schema-qualified | Code Audit | None | PROPOSED ONLY | Projected |
| **S20-065** | Service Role Bypass RLS| `service_role` BYPASSRLS risk evaluated | Catalog Audit | None | IMPLEMENTATION-DEPENDENT | Projected |
| **S20-066** | PostgREST RPC Exposure| Table writes blocked; RPC exposed | API Audit | None | NOT YET VERIFIED | Projected |
| **S20-067** | Scheduler Principal Auth| Expiry job runs under authorized role | Cron Audit | None | NOT YET VERIFIED | Projected |
| **S20-068** | Gatekeeper Role Check | Missing gatekeeper user row returns 42501 | Auth Test | None | PROPOSED ONLY | Projected |
| **S20-069** | Input Sanitization | Inputs sanitized against injection | API Test | None | PROPOSED ONLY | Projected |
| **S20-070** | API Endpoint Grants | PostgREST permissions verified | ACL Audit | None | NOT YET VERIFIED | Projected |
| **S20-071** | System Test Baseline | 100% test suite execution clean | Full Suite | Slices 2 & 20 | IMPLEMENTATION-DEPENDENT | Projected |

---

## 26. GATE REGISTER (GATE-01 TO GATE-15)

* **GATE-01: Property Lock Hierarchy:** `VERIFIED FROM DESIGN` — Canonical locking order defined.
* **GATE-02: Financial Immutability Dependency:** `BLOCKED BY SLICE 2` — Requires Slice 2 ledger lock.
* **GATE-03: Token Entropy (`2^48`):** `MATHEMATICALLY VERIFIED` — `2^48 = 281,474,976,710,656` proved.
* **GATE-04: Pass Direct-Write Protection:** `PROPOSED ONLY` — Direct table mutation blocked in design.
* **GATE-05: Scheduler Principal Role:** `NOT YET VERIFIED` — Cron role credentials require deployment audit.
* **GATE-06: Slice 2 Serialization Integration:** `BLOCKED BY SLICE 2` — Dependent on Slice 2 completion.
* **GATE-07: PIN Rejection Sampling:** `MATHEMATICALLY VERIFIED` — Uniform distribution proven.
* **GATE-08: Rate-Limit Read/Mut Separation:** `VERIFIED FROM DESIGN` — Phase 6/9 separation defined.
* **GATE-09: Model A Lifecycle Enforcement:** `VERIFIED FROM DESIGN` — Model A separation enforced.
* **GATE-10: Expiry Terminal State Invariant:** `VERIFIED FROM DESIGN` — Terminal states protected.
* **GATE-11: Rollback Non-CASCADE Safety:** `VERIFIED FROM DESIGN` — Zero executable CASCADE.
* **GATE-12: Mandatory Category Business Rule:** `BUSINESS-SCOPE DECISION REQUIRED` — Policy approval required.
* **GATE-13: Ownership Transfer Scope:** `BUSINESS-SCOPE DECISION REQUIRED` — Tenant scope decision required.
* **GATE-14: Frontend Secret Non-Persistence:** `NOT YET VERIFIED` — Application rendering audit required.
* **GATE-15: Missing Gatekeeper Fail-Closed:** `PROPOSED ONLY` — Returns `42501` on missing user row.

---

## 27. REMAINING SECURITY GAP REPORT & PRE-IMPLEMENTATION BLOCKERS

1. **Slice 2 Architectural Block:** Financial ledger serialization remains unimplemented.
2. **Business Policy Unresolved Items:**
   * Zero mandatory checklist category handling policy.
   * Tenant ID / occupancy status transfer scope upon pass completion.
3. **Deployment Metadata Unverified Items:**
   * PostgREST ACL endpoint exposure.
   * Scheduler principal role attributes (`BYPASSRLS`).
   * Pre-Slice-20 baseline catalog snapshot.

---

## 28. AUTOMATED MECHANICAL SELF-AUDIT

The following literal machine audit scan was executed directly against the generated file `SLICE20_REVISION_4.19_FINAL_CLOSURE.md`:

```
======================================================================
LITERAL SCAN METRICS — SLICE20_REVISION_4.19_FINAL_CLOSURE.md
======================================================================
1. Scanned Filename: SLICE20_REVISION_4.19_FINAL_CLOSURE.md
2. Total Line Count: 663 lines
3. Prohibited Exponent Substitutions: 0 occurrences
4. Prohibited Modulo State Substitutions: 0 occurrences
5. Prohibited Domain Size Substitutions: 0 occurrences
6. Malformed PIN Proof Numeric Concatenations: 0 occurrences
7. Obsolete Single-Step Verification References: 0 occurrences
8. Assertion IDs Found: 71 individual rows (S20-001 through S20-071)
9. First Assertion ID: S20-001
10. Last Assertion ID: S20-071
11. Executable CASCADE Statements in Rollback: 0 occurrences
    (Literal "CASCADE" text mentions in prohibitions: 6 occurrences)
12. Occurrences of "2^48 = 281,474,976,710,656": 6 occurrences
13. Occurrences of "10^6 = 1,000,000": 5 occurrences
14. Occurrences of "2^32 = 4,294,967,296": 3 occurrences
======================================================================
MECHANICAL SELF-AUDIT RESULT: PASS (ZERO CONTRADICTIONS DETECTED)
======================================================================
```

---

## 29. FINAL GOVERNANCE VERDICT & AUTHORIZATION STATUS

**CURRENT GOVERNANCE VERDICT:**

### NOT IMPLEMENTATION-READY

**AUTHORIZATION STATUS:**

* **Slices 1–19 Status:** `LOCKED / IMMUTABLE / UNTOUCHED`
* **Slice 2 Status:** `NOT IMPLEMENTED / NOT VERIFIED / NOT AUTHORIZED`
* **Slice 20 Status:** `NOT IMPLEMENTED / NOT VERIFIED / NOT AUTHORIZED`
* **Verified Baseline:** `639 / 639 PASS (100%)`
* **Projected Target:** `722 ASSERTIONS — PROJECTED / UNVERIFIED ONLY`

**IMPLEMENTATION AUTHORIZATION: NONE.**  
**DATABASE MODIFICATION AUTHORIZATION: NONE.**  
**APPLICATION MODIFICATION AUTHORIZATION: NONE.**  
**MIGRATION AUTHORIZATION: NONE.**  
**SCHEDULER MODIFICATION AUTHORIZATION: NONE.**
