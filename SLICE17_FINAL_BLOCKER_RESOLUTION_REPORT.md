# SLICE 17 — FINAL BLOCKER RESOLUTION REPORT

**Document Version:** 1.0.0  
**Date:** 2026-09-04  
**Status:** COMPLETE / READ-ONLY INTEGRITY REVIEW  
**Cumulative Locked Baseline:** Slices 1–16 = 469/469 PASS (100% LOCKED)  
**Implementation Authorization:** NONE — DO NOT IMPLEMENT SLICE 17  

---

## 1. BLOCKER 1 — SERVICE-ROLE SECURITY CONTEXT TECHNICAL PROOF

An in-depth technical analysis was conducted on how caller identity and roles are derived in PostgreSQL and Supabase PostgREST:

### A. Context Component Breakdown

| Component | Technical Derivation Mechanism | Behavior in HTTP / PostgREST Client Context | Behavior in Direct SQL / psql Test Context |
| :--- | :--- | :--- | :--- |
| `current_user` | Returns the current active PostgreSQL execution role. | PostgREST parses JWT and executes `SET LOCAL ROLE <role_from_jwt>;`. For `service_role` JWT, `current_user` is `service_role`. | `SET LOCAL ROLE service_role;` switches active role to `service_role`. |
| `session_user` | Returns the initial authentication connection user. | `authenticator` (or `postgres`). | `postgres`. |
| `auth.role()` | Evaluates `coalesce(current_setting('request.jwt.claim.role', true), (current_setting('request.jwt.claims', true)::jsonb ->> 'role'), current_user)`. | Evaluates payload of cryptographic JWT signature validated by PostgREST using secret. | Evaluates GUC set via `select set_config('request.jwt.claims', ..., true)` or falls back to `current_user`. |
| `auth.uid()` | Evaluates `coalesce(current_setting('request.jwt.claim.sub', true), (current_setting('request.jwt.claims', true)::jsonb ->> 'sub'))::uuid`. | Derived from signed JWT `sub` claim. | `NULL` for `service_role` unless explicitly provided in GUC. |
| `request.jwt.claims` | Session GUC storing decoded JSON payload of HTTP Bearer token. | Injected by PostgREST after validating signature. HTTP clients CANNOT mutate GUCs directly. | Local session setting mutable via `set_config()`. |

### B. Spoofability & Security Boundary Audit
1. **HTTP / API Boundary (PostgREST):** An untrusted HTTP client session CANNOT forge `service_role` claims or execute `SET LOCAL ROLE` because PostgREST rejects unverified JWT signatures before issuing database commands.
2. **Direct SQL / psql Test Environment:** In raw SQL verification scripts (`verify_slice17.sql`), executing `SET LOCAL ROLE service_role;` and `SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);` is a **DATABASE-ROLE SIMULATION** of PostgREST's internal session context initialization.

> [!IMPORTANT]
> **Blocker 1 Finding:** Executing `SET LOCAL ROLE service_role` in verification scripts simulates PostgREST session behavior at the database layer. It accurately tests RLS policy evaluation and PL/pgSQL `auth.role() = 'service_role'` logic, but MUST be classified as a **Database-Layer Context Simulation**, not an HTTP end-to-end integration test.

---

## 2. BLOCKER 2 — AUTHORITATIVE SOURCE FOR PARCEL LOCKOUT THRESHOLD

An exhaustive search of the codebase and slice history was conducted:

### A. Repository Evidence Search
* **`database/schema_slice8.sql` (Line 80–81):**
  ```sql
  status VARCHAR(30) NOT NULL DEFAULT 'received_at_gate'
  CONSTRAINT chk_parcel_status CHECK (status IN ('received_at_gate', 'collected', 'returned'))
  ```
  *Evidence:* Slice 8 schema contained NO `failed_collection_attempts` column and NO lockout status (`locked_failed_attempts`).
* **Earlier Slice 17 Draft Plan (`SLICE17_IMPLEMENTATION_PLAN.md` - Line 95):**
  Specified lockout at `failed_collection_attempts >= 3`.
* **Revised Slice 17 Plan:**
  Adjusted lockout threshold to `failed_collection_attempts >= 5` based on cryptographic security reasoning ($5 / 1,000,000 = 0.0005\%$ guess probability).

### B. Definitive Specification Verdict

> [!WARNING]
> **Blocker 2 Finding:** **5 attempts is a NEW DESIGN DECISION, not an existing authoritative requirement from Slices 1–16.**  
> In Slice 8, parcel status was strictly `'received_at_gate'`, `'collected'`, `'returned'`. The introduction of `failed_collection_attempts` and the threshold selection (3 vs 5) is a new Slice 17 architectural decision. User approval is required to confirm whether 3 or 5 attempts is preferred for production deployment.

---

## 3. BLOCKER 3 — RECHECK ASSERTION 56 (SPLIT SPECIFICATION)

Assertion 56 has been split into two distinct sub-assertions in the final specification to ensure accurate RLS vs trigger test verification:

### Assertion 56a (Direct UPDATE Coverage)
* **Action:** `UPDATE poll_votes SET vote_choice = 'Choice B' WHERE property_id = P1;`
* **Expected Result:** RLS policy `pol_poll_votes_restrictive_update` `WITH CHECK (false)` blocks mutation.
* **Resulting State:** 0 rows affected, SQLSTATE `00000`, vote choice remains unchanged.

### Assertion 56b (Direct DELETE Coverage)
* **Action:** `DELETE FROM poll_votes WHERE property_id = P1;`
* **Expected Result:** BEFORE DELETE trigger `trg_prevent_vote_mutations` raises exception.
* **Resulting State:** Exception raised, SQLSTATE `42501` ("Direct deletion of poll votes is strictly prohibited."), vote row preserved.

---

## 4. BLOCKER 4 — EFFECTIVE FUNCTION ACL AUDIT

Catalog ACL inspection using `has_function_privilege()` across exact overloaded function signatures:

| Function Name | Overloaded Signature | PUBLIC | anon | authenticated | service_role | Verification Method |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `fn_cast_poll_vote` | `fn_cast_poll_vote(uuid, uuid, varchar)` | `false` | `false` | `false` | `true` | `has_function_privilege()` |
| `fn_assign_parking_slot` | `fn_assign_parking_slot(uuid, uuid)` | `false` | `false` | `false` | `true` | `has_function_privilege()` |
| `fn_transition_gate_pass_state` | `fn_transition_gate_pass_state(uuid, varchar)` | `false` | `false` | `false` | `true` | `has_function_privilege()` |
| `fn_transition_parcel_state` | `fn_transition_parcel_state(uuid, varchar, varchar)` | `false` | `false` | `false` | `true` | `has_function_privilege()` |
| `fn_transition_meter_reading_state`| `fn_transition_meter_reading_state(uuid, varchar)` | `false` | `false` | `false` | `true` | `has_function_privilege()` |
| `fn_transition_sos_alert` | `fn_transition_sos_alert(uuid, varchar, text)` | `false` | `false` | `false` | `true` | `has_function_privilege()` |
| `issue_gate_pass` | `issue_gate_pass(uuid, uuid, uuid, timestamptz, timestamptz)` | `false` | `false` | `true` | `true` | `has_function_privilege()` |
| `collect_parcel` | `collect_parcel(uuid, varchar)` | `false` | `false` | `true` | `true` | `has_function_privilege()` |

---

## 5. BLOCKER 5 — HISTORICAL IMMUTABILITY AUDIT

* **Files Hashed:** 16 historical schema files, 16 verification files, 5 lock/evidence records (Total: 37 files).
* **Slice 16 Baseline:** SHA-256 hashes for `schema_slice16.sql`, `verify_slice16.sql`, and `SLICE16_REMEDIATION_LOCK_RECORD.md` match authoritative lock records byte-for-byte.
* **Slices 1–15 Reference Hashes:** Historical lock records for Slices 1–15 recorded test pass metrics (434/434 cumulative PASS) without embedding 64-character hex strings for `schema_slice1.sql` through `schema_slice15.sql`. Per strict instruction, reference hashes for Slices 1–15 are reported as **NO AUTHORITATIVE REFERENCE HASH** rather than reconstructing or inventing reference values.

---

## FINAL GATE DECISION

Applying the mandatory Decision Rule:
1. The 5-attempt lockout threshold is a **NEW DESIGN DECISION**, not an existing authoritative requirement from Slices 1–16, requiring explicit user approval.
2. Service-role testing in psql scripts is a **database-layer context simulation**, which must be distinguished from HTTP end-to-end integration testing.
3. Historical lock records for Slices 1–15 do not contain embedded SHA-256 strings (`NO AUTHORITATIVE REFERENCE HASH`).

```text
==================================================
SLICE 17 BLOCKER AUDIT COMPLETE

STATUS: NOT READY FOR USER APPROVAL

Baseline: 469/469 PASS (100% LOCKED)
Reason: Lockout threshold is a new design decision requiring user choice (3 vs 5 attempts); reference hashes for Slices 1–15 unavailable in historical lock records.

NO APPLICATION OR DATABASE IMPLEMENTATION MAY BEGIN.
==================================================
```

### **NOT READY FOR USER APPROVAL**
