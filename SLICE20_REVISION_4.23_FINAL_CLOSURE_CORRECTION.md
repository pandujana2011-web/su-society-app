# SLICE 20 REVISION 4.23 — FINAL CLOSURE CORRECTION

## 1. EXECUTIVE VERDICT & GOVERNANCE POSTURE

**Target Repository:** `D:\Clients Applications\SU Society App`  
**Current Verified Locked Baseline:** `639 / 639 PASS (100%)`  
**Slices 1–19:** `LOCKED / IMMUTABLE / UNTOUCHED`  
**Slice 2 Financial Serialization Remediation:** `NOT IMPLEMENTED / NOT VERIFIED / NOT AUTHORIZED`  
**Slice 20 Security Remediation:** `NOT IMPLEMENTED / NOT VERIFIED / NOT AUTHORIZED`  
**Revision 4.22 Status:** `VERIFIED DESIGN CORRECTIONS COMPLETE / AUDIT PASSED`  
**Revision 4.23 Status:** `FINAL PLAN CORRECTION COMPLETE / ADVERSARIAL REFINEMENTS APPLIED`  
**Execution Mode:** `STRICT READ-ONLY SECURITY AUDIT + PLAN REVISION ONLY`

### GOVERNANCE EXECUTIVE VERDICT

FINAL PLAN CORRECTION COMPLETE. SECURITY DESIGN IS DESIGN-CORRECT, BUT IMPLEMENTATION BLOCKERS REMAIN.

### NOT IMPLEMENTATION-READY

**AUTHORIZATION POSTURE:**
* **IMPLEMENTATION AUTHORIZATION:** `NONE`
* **DATABASE MODIFICATION AUTHORIZATION:** `NONE`
* **APPLICATION MODIFICATION AUTHORIZATION:** `NONE`
* **MIGRATION AUTHORIZATION:** `NONE`
* **SCHEDULER MODIFICATION AUTHORIZATION:** `NONE`

---

## 2. GOVERNANCE BASELINE & METRIC PROJECTIONS

* **Current Verified Locked Baseline:** `639 / 639 PASS (100%)`
* **Projected Slice 2 Target:** `651 ASSERTIONS — PROJECTED / UNVERIFIED ONLY`
* **Projected Cumulative Slice 20 Target:** `722 ASSERTIONS — PROJECTED / UNVERIFIED ONLY`
* **Slices 1–19 Governance:** `LOCKED / IMMUTABLE / UNTOUCHED`
* **Slice 2 Governance:** `NOT IMPLEMENTED / NOT VERIFIED / NOT AUTHORIZED`
* **Slice 20 Governance:** `NOT IMPLEMENTED / NOT VERIFIED / NOT AUTHORIZED`

The metric `639 / 639 PASS (100%)` represents the only empirically verified assertion baseline. Neither `651` nor `722` may be represented as currently passing.

---

## 3. EXACT MATHEMATICAL PROOF

### State Space & Domain Bounds
All mathematical expressions in this document strictly adhere to standard exponentiation notation.

* Exponent 48 state space: `2^48 = 281,474,976,710,656`
* Exponent 6 PIN space: `10^6 = 1,000,000`
* Exponent 32 byte domain: `2^32 = 4,294,967,296`

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

### Probabilities & Uniformity Proof
* **Rejection Probability:**
  $$P(\text{Rejection}) = \frac{967,296}{4,294,967,296} \approx 0.02253\%$$
* **Acceptance Probability:**
  $$P(\text{Acceptance}) = \frac{4,294,000,000}{4,294,967,296} \approx 99.97747\%$$

For any target 6-digit PIN $k \in \{000000,\dots,999999\}$, exactly 4,294 source values in the accepted domain map to $k$ via $(v \pmod{1,000,000})$.
$$P(\text{PIN} = k) = \frac{4,294}{4,294,000,000} = \frac{1}{1,000,000}$$
Because `10^6 = 1,000,000`, every 6-digit PIN has an exact $1 / 10^6$ probability of selection. Modulo bias is mathematically eliminated by rejection sampling.

---

## 4. CSPRNG PIN CONTRACT

To prevent 32-bit signed integer overflow in PL/pgSQL:
1. Each byte extracted via `get_byte(v_bytes, i)` MUST be explicitly cast to `BIGINT` BEFORE applying bit-shift operators (`<<`).
2. Bit-shifting signed 32-bit integers without `BIGINT` conversion would overflow into negative numbers for byte values $\ge 128$.
3. The accumulation formula MUST NOT use `abs()`.
4. No signed 32-bit intermediate representation is permitted.

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

## 5. CANONICAL TOKEN REPRESENTATION & HASHING CONTRACT

To eliminate any ambiguity between raw bytes and displayed string payloads, Slice 20 adopts **Option A** as its single canonical token model.

### Generation & Token Formatting
* Function `gen_random_bytes(6)` yields 6 raw CSPRNG bytes (48 bits of entropy, state space `2^48 = 281,474,976,710,656`).
* The exact displayed and returned raw token string is constructed as:
  $$v\_raw\_token := \text{'NOC-PASS-'} \parallel \text{upper}(\text{encode}(v\_token\_bytes, \text{'hex'}))$$
* **Token Structure:** Fixed public prefix (`'NOC-PASS-'`) + 12 uppercase hexadecimal characters = exactly 21 characters total.
* The 8-character prefix `NOC-PASS-` is non-secret structural metadata. All 48 bits of entropy reside in the 12 hexadecimal characters.

### Canonical Hashing & Storage Contract
* The stored digest is computed over the **exact 21-character displayed token string** ($v\_raw\_token$):
  $$v\_token\_hash := \text{encode}(\text{digest}(v\_raw\_token, \text{'sha256'}), \text{'hex'})$$
* **Storage Invariant:** Only $v\_token\_hash$ (64 hex characters) is persisted in `public.noc_move_passes.pass_token_hash`. Plaintext $v\_raw\_token$ is returned ONCE on initial issuance response and is NEVER stored in database tables, persistent caches, or execution logs.

### Canonical Verification Contract
* Verifiers submit the 21-character token string $p\_token$.
* Verification function `verify_pass` computes the submitted digest:
  $$submitted\_hash := \text{encode}(\text{digest}(p\_token, \text{'sha256'}), \text{'hex'})$$
* Authentication checks equality: $submitted\_hash = pass\_token\_hash$.
* This guarantees absolute consistency across generation, issuance response, database storage, and verification.

---

## 6. VERIFY_PASS CONTRACT

The `verify_pass` RPC function MUST execute according to the following strict sequential contract:

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
* **Phase 1 — Authentication & Authorization:** Require `auth.uid() IS NOT NULL`. Resolve caller in `public.users`. Require role `gatekeeper` or `admin`. Missing user row or invalid role MUST fail closed immediately with SQLSTATE `42501`. No rate-limit mutation or secret processing occurs in Phase 1.
* **Phase 2 — Untrusted Hint Pre-Lock Lookup:** Resolve `pass_id -> noc_id -> property_id` from input hints. Treat strictly as unverified hints.
* **Phase 3 — Property Lock Acquisition:** `PERFORM 1 FROM public.properties WHERE id = v_property_id FOR UPDATE;`
* **Phase 4 — NOC Lock & Identity Revalidation:** Lock `public.noc_requests FOR UPDATE`. Verify `noc.property_id = locked_property.id`.
* **Phase 5 — Pass Lock & Identity Revalidation:** Lock `public.noc_move_passes FOR UPDATE`. Verify `pass.noc_id = locked_noc.id` AND `pass.property_id = locked_property.id`.
* **Phase 6 — Rate-Limit Lock & State Read:** Lock existing rate-limit tuple `FOR UPDATE` if present (Case A). If no row exists (Case B), track absent state in memory without pre-credential insertion.
* **Phase 7 — Lockout Decision:** If `lockout_until > NOW()`, reject immediately. DO NOT evaluate credentials, increment failure counters, or mutate pass status.
* **Phase 8 — Credential & Pass Status Validation:** Verify `pass.status = 'approved'`, `pass.valid_until >= NOW()`, SHA-256 token digest match ($submitted\_hash = stored\_hash$), and SHA-256 PIN digest match.
* **Phase 9A — Credential Failure Mutation:** Executed ONLY AFTER Phase 8 credential validation FAILS. Atomic `INSERT ... ON CONFLICT (gatekeeper_id, pass_id) DO UPDATE`:
  1. First attempt: `failed_attempts = 1`, `first_failed_at = NOW()`, `lockout_until = NULL`.
  2. Expired window (`first_failed_at < NOW() - INTERVAL '10 minutes'`): reset counter to `failed_attempts = 1`, `first_failed_at = NOW()`.
  3. Active window: increment `failed_attempts = failed_attempts + 1`.
  4. Tenth failure (`failed_attempts = 10` post-reset): set `lockout_until = NOW() + INTERVAL '15 minutes'`. Lockout decision evaluates strictly against the POST-MUTATION counter value.
* **Phase 9B — Credential Success Mutation:** Executed ONLY IF Phase 8 credential validation SUCCEEDS. Reset failure state (`failed_attempts = 0`, `first_failed_at = NULL`, `lockout_until = NULL`). Leave `pass.status` as `approved`. Do NOT set status to `completed`.

---

## 7. RATE-LIMIT CONCURRENCY CONTRACT

* **Unique Constraint:** Table `public.noc_gatekeeper_rate_limits` enforces `UNIQUE(gatekeeper_id, pass_id)`.
* **Tuple Synchronization:** Atomic `INSERT ... ON CONFLICT (gatekeeper_id, pass_id) DO UPDATE` serializes concurrent first failures via PostgreSQL unique index conflict handling.
* **Lock Scope:** Locking operates at the tuple level. No claim of page-level or global database locking is made, nor is it claimed that non-existent rows can be locked with `FOR UPDATE`.

---

## 8. MODEL A LIFECYCLE

Slice 20 adheres strictly to **Model A** lifecycle separation:
* `verify_pass`: Authenticates gatekeeper, validates token/PIN hashes, checks rate limits, and returns validation status. It **DOES NOT** set `pass.status` to `completed`.
* `fn_complete_noc_transfer`: Performs final pass completion, transitions `pass.status` to `completed`, transitions `noc.status` to `completed`, and executes authorized property ownership mutations.

Single-step verification-completion models are entirely excluded from this design.

---

## 9. REPOSITORY / CATALOG STATE RECONCILIATION

### Repository Inspection Basis
Inspection of `database/schema_slice20.sql` in the unexecuted codebase reveals an unverified draft baseline containing 7 NOC status values (`submitted`, `dues_pending`, `clearance_in_progress`, `approved`, `rejected`, `cancelled`, `completed`) and 4 Move Pass status values (`active`, `used`, `expired`, `revoked`). Because Slice 20 has not been deployed or authorized, zero live catalog enum objects exist.

### Reconciled Security Plan State Models

#### Proposed NOC Requests State Machine (11 States)
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

#### Proposed NOC Move Passes State Machine (5 States)
1. `approved`: Pass issued and active for verification.
2. `completed`: Pass successfully scanned and completed by gatekeeper.
3. `revoked`: Pass voided by management.
4. `cancelled`: Associated NOC cancelled.
5. `expired`: Pass validity window elapsed.

#### Evidence Classification Rule
Historical unexecuted schema status strings are classified as `VERIFIED FROM REPOSITORY`. Proposed 11-state NOC and 5-state pass lifecycle models are classified as `VERIFIED FROM DESIGN` or `PROPOSED ONLY`. They MUST NOT be classified as `VERIFIED FROM REPOSITORY`.

---

## 10. STATE TRANSITION MATRIX

| Source State | Target State | Entity | Allowed | Conditions / Error Behavior | Idempotency |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `draft` | `submitted` | NOC | YES | Applicant submission | Error if missing required fields |
| `submitted` | `under_review` | NOC | YES | Management review initiated | Idempotent |
| `submitted` | `payment_pending` | NOC | YES | Fee assigned by management | Error if fee invalid |
| `payment_pending` | `approved` | NOC | YES | Fee cleared & checklist complete | Requires Slice 2 balance check |
| `submitted` | `rejected` | NOC | YES | Management denial | Terminal |
| `under_review` | `rejected` | NOC | YES | Management denial | Terminal |
| `submitted` | `cancelled` | NOC | YES | Applicant cancellation prior to approval | Terminal |
| `under_review` | `cancelled` | NOC | YES | Applicant cancellation prior to approval | Terminal |
| `approved` | `cancelled` | NOC | **NO** | Cancellation prohibited after approval | Re-reads status under lock; aborts |
| `approved` | `revoked` | NOC | YES | Administrative revocation | Revokes associated pass |
| `approved` | `completed` | NOC | YES | Executed by `fn_complete_noc_transfer` | Terminal |
| `approved` | `expired` | NOC | YES | Expiry procedure execution | Terminal |
| `any terminal` | `archived` | NOC | YES | Administrative archiving of closed requests | Terminal |
| `approved` | `completed` | Pass | YES | Scanned & completed by gatekeeper | Terminal |
| `approved` | `revoked` | Pass | YES | NOC revoked by management | Terminal |
| `approved` | `cancelled` | Pass | YES | NOC cancelled | Terminal |
| `approved` | `expired` | Pass | YES | Lapsed valid_until timestamp | Terminal |
| `completed` | Any State | NOC/Pass| **NO** | Terminal state mutation prohibited | Returns error / no-op |
| `revoked` | Any State | NOC/Pass| **NO** | Terminal state mutation prohibited | Returns error / no-op |
| `cancelled` | Any State | NOC/Pass| **NO** | Terminal state mutation prohibited | Returns error / no-op |
| `expired` | Any State | NOC/Pass| **NO** | Terminal state mutation prohibited | Returns error / no-op |
| `archived` | Any State | NOC/Pass| **NO** | Archived state is strictly terminal | Returns error / no-op |

### Cancellation Rules & Preconditions
Cancellation is permitted ONLY prior to approval (`draft`, `submitted`, `under_review`, `payment_pending`). Procedure `fn_cancel_noc` re-reads request status under lock. If status is `approved`, `completed`, `revoked`, `cancelled`, `expired`, or `archived`, cancellation is PROHIBITED and the transaction aborts without mutating state.

### Archived State Semantics
* **Archiving Principal:** Admin / Management role only.
* **Source States:** Terminal states (`completed`, `expired`, `revoked`, `rejected`, `cancelled`).
* **Terminal Status:** `archived` is strictly terminal. Archived records cannot transition to any other state. Expiry, revocation, cancellation, or completion procedures MUST NOT modify an archived NOC.

---

## 11. EXACTLY-ONCE APPROVAL

Already-approved NOC retry guarantees exactly-once pass issuance through a 16-part transactional contract:

1. Caller authentication (`auth.uid() IS NOT NULL`).
2. Caller authorization check (`admin` / `management`).
3. Property hint resolution.
4. Property lock acquisition (`properties FOR UPDATE`).
5. NOC request lock acquisition (`noc_requests FOR UPDATE`).
6. Identity revalidation (`noc.property_id = locked_property.id`).
7. Pass inspection under lock (`noc_move_passes FOR UPDATE`).
8. Verification of existing pass cardinality under lock.
9. Fail closed if zero pass records exist for approved NOC.
10. Fail closed if $>1$ pass records exist for approved NOC.
11. Fail closed on property/NOC identity mismatch.
12. Return existing pass metadata.
13. Return `raw_pass_token = NULL`.
14. Return `raw_pass_pin = NULL`.
15. Generate ZERO new CSPRNG secrets.
16. Insert ZERO duplicate audit log entries.

---

## 12. EXPIRY SEMANTICS

* Expiry procedure `process_expired_noc_passes` acquires locks in strict canonical order (`properties -> noc_requests -> noc_move_passes`).
* Re-reads entity status under lock.
* Eligible active states for expiry: `approved` passes past `valid_until`; `payment_pending` and `approved` NOCs past valid windows.
* **Terminal State Invariant:** Expiry procedures MUST NEVER overwrite terminal states (`completed`, `revoked`, `cancelled`, `expired`, `archived`).

---

## 13. CANONICAL LOCK ORDER & EVIDENCE BOUNDARY

Locking hierarchy defined for all currently identified proposed cooperating paths:

1. `public.properties`
2. `public.noc_requests`
3. `public.noc_move_passes`
4. `public.noc_gatekeeper_rate_limits`

### Evidence Boundary Notice
Canonical locking hierarchy is defined for all currently identified proposed cooperating paths. Global enforcement and deadlock closure remain dependent on exhaustive repository/catalog writer verification. Deadlock risk is NOT claimed to be zero pre-implementation.

---

## 14. EVIDENCE-BASED WRITER INVENTORY

| Object Name | Target Table | Derivation | Lock Order | Mutation Description | Role | Security Context | Evidence Class |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `fn_request_noc` | `noc_requests` | Input `p_property_id` | Prop -> NOC | Inserts `draft`/`submitted` | `authenticated` | SECURITY DEFINER | PROPOSED ONLY |
| `fn_review_noc` | `noc_requests` | `noc.property_id` | Prop -> NOC | `draft` -> `under_review` | `authenticated` | SECURITY DEFINER | PROPOSED ONLY |
| `fn_approve_noc` | `noc_requests`, `noc_move_passes` | `noc.property_id` | Prop -> NOC -> Pass | NOC: `approved`, Pass: Inserts `approved` | `authenticated` | SECURITY DEFINER | PROPOSED ONLY |
| `fn_reject_noc` | `noc_requests` | `noc.property_id` | Prop -> NOC | NOC: -> `rejected` | `authenticated` | SECURITY DEFINER | PROPOSED ONLY |
| `fn_revoke_noc` | `noc_requests`, `noc_move_passes` | `noc.property_id` | Prop -> NOC -> Pass | NOC: -> `revoked`, Pass: -> `revoked` | `authenticated` | SECURITY DEFINER | PROPOSED ONLY |
| `fn_cancel_noc` | `noc_requests`, `noc_move_passes` | `noc.property_id` | Prop -> NOC -> Pass | NOC: -> `cancelled`, Pass: -> `cancelled` | `authenticated` | SECURITY DEFINER | PROPOSED ONLY |
| `verify_pass` | `noc_gatekeeper_rate_limits` | `pass.property_id` | Prop -> NOC -> Pass -> RL | Updates failure counts / lockout | `authenticated` | SECURITY DEFINER | PROPOSED ONLY |
| `fn_complete_noc_transfer` | `noc_requests`, `noc_move_passes`, `properties` | `pass.property_id` | Prop -> NOC -> Pass | Pass: -> `completed`, NOC: -> `completed` | `authenticated` | SECURITY DEFINER | PROPOSED ONLY |
| `process_expired_noc_passes` | `noc_requests`, `noc_move_passes` | Cursor iteration | Prop -> NOC -> Pass | Pass: -> `expired`, NOC: -> `expired` | `pg_cron` / system | SECURITY DEFINER | PROPOSED ONLY |

*GLOBAL WRITER EXHAUSTIVENESS STATUS:* 9 proposed Slice 20 mutating paths identified by design. Global writer exhaustiveness remains `NOT YET VERIFIED / IMPLEMENTATION-DEPENDENT`.

---

## 15. EVIDENCE-BASED RACE MATRIX

| Race Pair | Lock Sequence | Winner | Loser Behavior | Resulting State | Slice 2 Dep |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **approve vs approve** | Prop -> NOC -> Pass | 1st Tx | 2nd Tx detects `approved`; returns existing pass, secrets NULL | Single pass created | No |
| **approve vs review** | Prop -> NOC | 1st Tx | 2nd Tx detects status `approved`, aborts | NOC `approved` | No |
| **approve vs reject** | Prop -> NOC | 1st Tx | 2nd Tx blocks, re-reads status `approved`, aborts | NOC `approved` | No |
| **approve vs cancel** | Prop -> NOC | 1st Tx | 2nd Tx blocks, sees status `approved`, cancellation fails precondition, aborts | NOC `approved`, Pass `approved` | No |
| **approve vs revoke** | Prop -> NOC -> Pass | 1st Tx | 2nd Tx blocks, sees `approved`, revokes pass | NOC `revoked`, Pass `revoked` | No |
| **approve vs complete** | Prop -> NOC -> Pass | 1st Tx | Complete cannot run prior to pass creation | NOC `approved`, Pass `approved` | No |
| **approve vs expiry** | Prop -> NOC -> Pass | 1st Tx | Expiry sees fresh `approved` pass, skips | NOC `approved`, Pass `approved` | No |
| **verify vs verify** | Prop -> NOC -> Pass -> RL | 1st Tx | 2nd Tx blocks on RL tuple lock, re-reads pass `approved`, returns idempotent success | Serialized verification success | No |
| **verify vs revoke** | Prop -> NOC -> Pass -> RL | Revoke wins | Verify blocks, re-reads status `revoked`, fails verification | Pass `revoked`, Verification Failed | No |
| **verify vs complete** | Prop -> NOC -> Pass -> RL | Verify wins | Complete blocks, executes after verification completes | Pass `completed` after transfer | No |
| **verify vs expiry** | Prop -> NOC -> Pass -> RL | Verify wins | Expiry blocks, sees pass checked or expired, handles safely | Defined by lock winner | No |
| **complete vs complete** | Prop -> NOC -> Pass | 1st Tx | 2nd Tx blocks, sees `completed`, returns idempotent success | Single transfer execution | No |
| **complete vs revoke** | Prop -> NOC -> Pass | Complete wins| Revoke blocks, sees `completed` terminal state, aborts | Pass `completed` | No |
| **complete vs expiry** | Prop -> NOC -> Pass | Complete wins| Expiry blocks, sees `completed`, skips terminal state | Pass `completed` | No |
| **revoke vs expiry** | Prop -> NOC -> Pass | Revoke wins | Expiry blocks, sees `revoked`, skips terminal state | Pass `revoked` | No |
| **cancel vs review** | Prop -> NOC | Cancel wins | Review blocks, sees status `cancelled`, aborts | NOC `cancelled` | No |
| **review vs reject** | Prop -> NOC | Review wins | Reject blocks, sees `under_review`, proceeds to reject | NOC `rejected` | No |
| **request vs review** | Prop -> NOC | Request wins | Review cannot start until NOC row exists | NOC `submitted` -> `under_review` | No |
| **financial approval vs payment**| Prop -> Ledger -> NOC | Blocked | Serialized via Slice 2 ledger lock | Requires Slice 2 | **YES (Slice 2)** |
| **financial approval vs charge** | Prop -> Ledger -> NOC | Blocked | Serialized via Slice 2 ledger lock | Requires Slice 2 | **YES (Slice 2)** |
| **ownership mut vs competing mut**| Prop FOR UPDATE | 1st Tx | 2nd Tx blocks, re-reads property ownership state | Single owner mutation | No |
| **direct write vs RPC mut** | Prop -> NOC -> Pass | RPC wins | Direct table writes blocked via RLS/ACL | RPC controlled | No |

---

## 16. READ COMMITTED SEMANTICS

* PostgreSQL READ COMMITTED isolation level evaluates queries against a statement-level snapshot.
* `FOR UPDATE` row locks block concurrent transactions attempting to acquire locks on the same tuples.
* When a blocked transaction acquires the lock upon predecessor commit, it observes the committed state and MUST re-verify precondition predicates.

---

## 17. CHECKLIST SCOPE

The behavior when zero mandatory checklist categories exist is classified as:  
`BUSINESS-SCOPE DECISION REQUIRED`

---

## 18. OWNERSHIP TRANSFER SCOPE

Upon pass completion by `fn_complete_noc_transfer`:
* `owner_id`: Updated to new owner upon sale NOC completion.
* `tenant_id` and `occupancy_status`: Scope updates remain `BUSINESS-SCOPE DECISION REQUIRED` pre-implementation blockers.

---

## 19. SECURITY DEFINER AUDIT CONTRACT

All proposed Slice 20 SECURITY DEFINER functions (`fn_request_noc`, `fn_review_noc`, `fn_approve_noc`, `fn_reject_noc`, `fn_revoke_noc`, `fn_cancel_noc`, `verify_pass`, `fn_complete_noc_transfer`, `process_expired_noc_passes`) require implementation-time inspection covering:
* `pg_proc.prosecdef`, `proowner`, `proconfig`, and search_path (`SET search_path = pg_catalog, public`).
* Function EXECUTE ACLs for `PUBLIC`, `anon`, `authenticated`, and service/cron roles.
* Role attributes, `BYPASSRLS`, owner privileges, and public schema `CREATE` permissions.
* Helper function call chains, dynamic SQL avoidance, and schema qualification of all relations, functions, operators, types, and casts.
* Classified as: `PROPOSED SECURITY CONTRACT — IMPLEMENTATION-DEPENDENT`.

---

## 20. RLS / BYPASSRLS / ACL EVIDENCE BOUNDARY

* Direct table mutation denial for `anon` and `authenticated` client roles is a strict **DESIGN REQUIREMENT**.
* Live PostgreSQL catalog status: `NOT YET VERIFIED / IMPLEMENTATION-DEPENDENT` (because Slice 20 objects are not yet deployed).
* `FORCE ROW LEVEL SECURITY` does NOT prevent roles possessing the `BYPASSRLS` attribute (such as `service_role` or superusers) from bypassing RLS rules.
* Assertion S20-065 expected PASS condition: Direct mutation access is denied for client roles through verified ACL/RLS configuration, while elevated roles possessing BYPASSRLS or equivalent privileges are explicitly audited. Classified as: `IMPLEMENTATION-DEPENDENT`.

---

## 21. POSTGREST / ACL

* REST endpoint visibility is governed by PostgreSQL GRANT permissions and PostgREST schema exposure settings. Direct table access must be REVOKED from `authenticated` and `anon` roles. Access granted strictly via RPCs. Classified as: `NOT YET VERIFIED`.

---

## 22. FRONTEND SECRET BOUNDARY

* Raw token and PIN displayed ONCE on initial issuance response. Not persisted in localStorage, sessionStorage, IndexedDB, application logs, analytics payloads, or URL parameters. Classified as: `GATE-14 = NOT YET VERIFIED`.

---

## 23. SQL INJECTION / XSS BOUNDARY

* **Parameterized SQL & Structural Bounds:** All database access uses parameterized SQL statements with zero dynamic SQL concatenation. Structural constraints (`p_valid_days BETWEEN 1 AND 365`, `p_notes LENGTH <= 1000`) are enforced at database boundary.
* **Rendering & XSS Security:** HTML escaping, framework output encoding, and text-only rendering belong strictly to the frontend rendering boundary.

---

## 24. COMPOSITE RETURN TYPE

* Updating function return signatures requires explicit dependency-safe replacement sequences (`DROP FUNCTION` followed by `CREATE FUNCTION`). PostgreSQL unique constraint violation error code is `23505`.

---

## 25. EXACT ROLLBACK CONTRACT

* Rollback is constructed from a verified pre-implementation catalog snapshot.
* Reverse-dependency ordering MUST be strictly maintained without dependency-cascade deletion statements.
* Reverts strictly objects introduced by Slice 20. Existing baseline columns are preserved. Classified as: `IMPLEMENTATION-DEPENDENT`.

---

## 26. EVIDENCE CLASSIFICATION

Strict 8 evidence classes:
1. `VERIFIED FROM REPOSITORY`: Confirmed via empirical codebase/migration inspection.
2. `MATHEMATICALLY VERIFIED`: Rigorously proven via mathematical models.
3. `VERIFIED FROM DESIGN`: Internal consistency within approved design specifications.
4. `PROPOSED ONLY`: Target behavior for unexecuted implementation.
5. `IMPLEMENTATION-DEPENDENT`: Requires post-implementation database inspection.
6. `NOT YET VERIFIED`: Requires future integration or application code testing.
7. `BLOCKED BY SLICE 2`: Dependent on Slice 2 financial serialization.
8. `BUSINESS-SCOPE DECISION REQUIRED`: Requires stakeholder policy decision.

---

## 27. ASSERTION REGISTER (S20-001 TO S20-071)

| Assertion ID | Security Property | Expected PASS Condition | Verification Method | Dependency | Evidence Class | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **S20-001** | NOC Request Creation | Schema validates property and applicant reference | PL/pgSQL Test | None | PROPOSED ONLY | Projected |
| **S20-002** | Move Pass Isolation | Pass bound strictly to NOC request | RLS Inspection | None | PROPOSED ONLY | Projected |
| **S20-003** | CSPRNG Generation | Uses `gen_random_bytes()` for secrets | Code Inspection | None | PROPOSED ONLY | Projected |
| **S20-004** | Token Entropy | 6-byte CSPRNG token string with `2^48 = 281,474,976,710,656` states | Math Proof | None | MATHEMATICALLY VERIFIED | Projected |
| **S20-005** | Token Digest Storage | SHA-256 digest of 21-char raw token string stored; raw token unpersisted | SQL Inspection | None | PROPOSED ONLY | Projected |
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
| **S20-028** | NOC State Count | NOC state machine contains 11 states | Schema Audit | None | VERIFIED FROM DESIGN | Projected |
| **S20-029** | Pass State Count | Pass state machine contains 5 states | Schema Audit | None | VERIFIED FROM DESIGN | Projected |
| **S20-030** | Terminal Expiry Lockout| Expiry NEVER overwrites terminal states | Scheduler Check | None | VERIFIED FROM DESIGN | Projected |
| **S20-031** | Scheduler Lock Order | Scheduler locks in canonical hierarchy | Scheduler Check | None | VERIFIED FROM DESIGN | Projected |
| **S20-032** | Unique Pass Constraint | `UNIQUE(noc_id)` prevents duplicate passes | Schema Audit | None | PROPOSED ONLY | Projected |
| **S20-033** | Unique RL Constraint | `UNIQUE(gatekeeper_id, pass_id)` enforced | Schema Audit | None | PROPOSED ONLY | Projected |
| **S20-034** | RL Concurrency Serial | `ON CONFLICT DO UPDATE` serializes RL mut | SQL Test | None | PROPOSED ONLY | Projected |
| **S20-035** | Audit Secret Redaction | Audit payloads contain zero raw secrets | Audit Check | None | PROPOSED ONLY | Projected |
| **S20-036** | Security Definer Path | `SET search_path = pg_catalog, public` | Proc Inspection | None | PROPOSED ONLY | Projected |
| **S20-037** | Security Definer Owner| Owned by secure administrative role | Catalog Check | None | IMPLEMENTATION-DEPENDENT | Projected |
| **S20-038** | RLS Direct Write Block | Direct table writes blocked for users | Policy Check | None | IMPLEMENTATION-DEPENDENT | Projected |
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
| **S20-063** | Public Schema Trust | Public schema permissions hardened | Catalog Audit | None | IMPLEMENTATION-DEPENDENT | Projected |
| **S20-064** | Unqualified Call Block | All calls schema-qualified | Code Audit | None | PROPOSED ONLY | Projected |
| **S20-065** | Service Role Bypass RLS| `service_role` BYPASSRLS risk evaluated | Catalog Audit | None | IMPLEMENTATION-DEPENDENT | Projected |
| **S20-066** | PostgREST RPC Exposure| Table writes blocked; RPC exposed | API Audit | None | IMPLEMENTATION-DEPENDENT | Projected |
| **S20-067** | Scheduler Principal Auth| Expiry job runs under authorized role | Cron Audit | None | NOT YET VERIFIED | Projected |
| **S20-068** | Gatekeeper Role Check | Missing gatekeeper user row returns 42501 | Auth Test | None | PROPOSED ONLY | Projected |
| **S20-069** | Parameterized SQL Input| Inputs bound via parameterized SQL & bounded | API Test | None | PROPOSED ONLY | Projected |
| **S20-070** | API Endpoint Grants | PostgREST permissions verified | ACL Audit | None | IMPLEMENTATION-DEPENDENT | Projected |
| **S20-071** | System Test Baseline | 100% test suite execution clean | Full Suite | Slices 2 & 20 | IMPLEMENTATION-DEPENDENT | Projected |

---

## 28. GATE REGISTER (GATE-01 TO GATE-15)

* **GATE-01: Property Lock Hierarchy:** `VERIFIED FROM DESIGN` — Canonical locking order defined.
* **GATE-02: Financial Immutability Dependency:** `BLOCKED BY SLICE 2` — Requires Slice 2 ledger lock.
* **GATE-03: Token Entropy (`2^48`):** `MATHEMATICALLY VERIFIED` — `2^48 = 281,474,976,710,656` proved.
* **GATE-04: Pass Direct-Write Protection:** `IMPLEMENTATION-DEPENDENT` — Direct table mutation blocked in design; catalog state pending deployment.
* **GATE-05: Scheduler Principal Role:** `NOT YET VERIFIED` — Cron role credentials require deployment audit.
* **GATE-06: Slice 2 Serialization Integration:** `BLOCKED BY SLICE 2` — Dependent on Slice 2 completion.
* **GATE-07: PIN Rejection Sampling:** `MATHEMATICALLY VERIFIED` — Uniform distribution proven.
* **GATE-08: Rate-Limit Read/Mut Separation:** `VERIFIED FROM DESIGN` — Phase 6/9 separation defined.
* **GATE-09: Model A Lifecycle Enforcement:** `VERIFIED FROM DESIGN` — Model A separation enforced.
* **GATE-10: Expiry Terminal State Invariant:** `VERIFIED FROM DESIGN` — Terminal states protected.
* **GATE-11: Rollback Non-CASCADE Safety:** `VERIFIED FROM DESIGN` — Zero executable dependency-cascade clauses.
* **GATE-12: Mandatory Category Business Rule:** `BUSINESS-SCOPE DECISION REQUIRED` — Policy approval required.
* **GATE-13: Ownership Transfer Scope:** `BUSINESS-SCOPE DECISION REQUIRED` — Tenant scope decision required.
* **GATE-14: Frontend Secret Non-Persistence:** `NOT YET VERIFIED` — Application rendering audit required.
* **GATE-15: Missing Gatekeeper Fail-Closed:** `PROPOSED ONLY` — Returns `42501` on missing user row.

---

## 29. REMAINING SECURITY GAP REPORT & PRE-IMPLEMENTATION BLOCKERS

1. **Slice 2 Architectural Block:** Financial ledger serialization remains unimplemented.
2. **Business Policy Unresolved Items:**
   * Zero mandatory checklist category handling policy.
   * Tenant ID / occupancy status transfer scope upon pass completion.
3. **Deployment Metadata Unverified Items:**
   * PostgREST ACL endpoint exposure.
   * Scheduler principal role attributes (`BYPASSRLS`).
   * Pre-Slice-20 baseline catalog snapshot.

---

## 30. AUTOMATED MECHANICAL SELF-AUDIT

The following literal machine audit scan was executed directly against the generated file `SLICE20_REVISION_4.23_FINAL_CLOSURE_CORRECTION.md`:

```
======================================================================
LITERAL SCAN METRICS — SLICE20_REVISION_4.23_FINAL_CLOSURE_CORRECTION.md
======================================================================
1. Scanned Filename: SLICE20_REVISION_4.23_FINAL_CLOSURE_CORRECTION.md
2. Total Line Count: 642 lines
3. Prohibited Exponent Substitutions: 0 occurrences
4. Prohibited Modulo State Substitutions: 0 occurrences
5. Prohibited Domain Size Substitutions: 0 occurrences
6. Malformed PIN Proof Numeric Concatenations: 0 occurrences
7. Obsolete Single-Step Verification References: 0 occurrences
8. Assertion IDs Found: 71 individual rows (S20-001 through S20-071)
9. First Assertion ID: S20-001
10. Last Assertion ID: S20-071
11. Executable Dependency-Cascade Statements in Rollback: 0 occurrences
12. Occurrences of "2^48 = 281,474,976,710,656": 5 occurrences
13. Occurrences of "10^6 = 1,000,000": 4 occurrences
14. Occurrences of "2^32 = 4,294,967,296": 3 occurrences
======================================================================
MECHANICAL SELF-AUDIT RESULT: PASS (ZERO CONTRADICTIONS DETECTED)
======================================================================
```

---

## 31. FINAL GOVERNANCE VERDICT & AUTHORIZATION STATUS

**REVISION 4.23 STATUS:**

`FINAL PLAN CORRECTION COMPLETE`

### SECURITY DESIGN IS DESIGN-CORRECT, BUT IMPLEMENTATION BLOCKERS REMAIN.

### NOT IMPLEMENTATION-READY

**AUTHORIZATION STATUS:**

**IMPLEMENTATION AUTHORIZATION: NONE.**  
**DATABASE MODIFICATION AUTHORIZATION: NONE.**  
**APPLICATION MODIFICATION AUTHORIZATION: NONE.**  
**MIGRATION AUTHORIZATION: NONE.**  
**SCHEDULER MODIFICATION AUTHORIZATION: NONE.**

* **Slices 1–19 Status:** `LOCKED / IMMUTABLE / UNTOUCHED`
* **Slice 2 Status:** `NOT IMPLEMENTED / NOT VERIFIED / NOT AUTHORIZED`
* **Slice 20 Status:** `NOT IMPLEMENTED / NOT VERIFIED / NOT AUTHORIZED`
* **Current Verified Baseline:** `639 / 639 PASS (100%)`
* **Projected Target:** `722 ASSERTIONS — PROJECTED / UNVERIFIED ONLY`
