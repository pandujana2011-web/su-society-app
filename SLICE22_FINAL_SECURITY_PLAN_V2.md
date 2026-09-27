# SLICE 22 — FINAL FORENSIC SECURITY PLAN
# Society Rule Violation, Fine Ledger Posting & Dispute Management System

```
DOCUMENT STATUS:     PLAN ONLY
IMPLEMENTATION:      NOT IMPLEMENTED (MICRO-REMEDIATION REQUIRED)
VERIFICATION:        NOT EXECUTED
LOCKED:              NO
IMPLEMENTATION AUTH: NOT GRANTED BY THIS DOCUMENT
SQL EXECUTED:        ZERO
DATABASE MUTATED:    ZERO
LOCKED ARTIFACTS:    ZERO MODIFICATIONS
```

---

## 1. GOVERNANCE VERIFICATION RESULT

### 1A. Hash Verification (Read-Only, Performed at Plan Creation)

| File | Expected SHA-256 | Observed SHA-256 | Match? |
| :--- | :--- | :--- | :---: |
| `SLICE21_HASH_DISCREPANCY_GOVERNANCE_CLOSURE_OPTION_A.md` | `123365DA7FF34D6D097FE92F1AFC8FBB82C1A8BF1570BE9B3486497F708A3C4B` | `123365DA7FF34D6D097FE92F1AFC8FBB82C1A8BF1570BE9B3486497F708A3C4B` | ✅ |
| `SLICE21_FINAL_SECURITY_PLAN.md` (current plan, lifecycle gap known) | `FFB20A9C72D8F8109DBDDA8EFDBBF6D2AB9CEBFF2C652E82FD7A343243478DE1` | `FFB20A9C72D8F8109DBDDA8EFDBBF6D2AB9CEBFF2C652E82FD7A343243478DE1` | ✅ |
| `database/schema_slice21.sql` | `8276FB539304820450B673084210A7ADD30294A09356D585AAFC7C8E418BF190` | `8276FB539304820450B673084210A7ADD30294A09356D585AAFC7C8E418BF190` | ✅ |
| `database/verify_slice21.sql` | `2985F7A632039C4C6A30E83CBB9EA847A2E069EE89F42F51E8D7C01874422925` | `2985F7A632039C4C6A30E83CBB9EA847A2E069EE89F42F51E8D7C01874422925` | ✅ |
| Historical Slice 21 plan lock hash (preserved in `SLICE21_SECURITY_LOCK.md`) | `87CB680A8C7C56F20E641F46E89BFD646B939FA6E6EF3FC8C9B11602B6CD6516` | — (file no longer on disk; governance closed under Option A) | ✅ N/A |

### 1B. Governance State

| Item | Status |
| :--- | :---: |
| Slice 21 LOCKED / IMMUTABLE | ✅ CONFIRMED |
| Slice 21 governance closure Option A | ✅ CONFIRMED |
| 791/791 authoritative functional baseline | ✅ CONFIRMED |
| No Slice 1–21 artifact modified during this task | ✅ CONFIRMED |
| SQL executed during this task | ZERO |
| Database mutated during this task | ZERO |

**Repository snapshot timestamp for this plan:** `2026-09-10T14:51:00Z`

---

## 2. CURRENT AUTHORITATIVE BASELINE

```
791 / 791 PASS — 100% LOCKED / IMMUTABLE

  Slices 1–19:              639 / 639 PASS  (LOCKED)
  Slice 2 Fin. Remediation:  24 /  24 PASS  (LOCKED)
  Slice 20 NOC & Move-Out:   51 /  51 PASS  (LOCKED)
  Slice 21 Security Gate:    77 /  77 PASS  (LOCKED)
  ────────────────────────────────────────────────────
  CUMULATIVE:               791 / 791 PASS  (LOCKED)
```

---

## 3. SLICE 1–21 IMMUTABILITY CONFIRMATION

All Slices 1–21 remain **LOCKED / IMMUTABLE**.

- Zero modifications to any locked schema, verify, plan, or lock record file.
- Zero DDL or DML executed against the live database.
- Zero governance hash updates.
- The Slice 21 plan document hash discrepancy remains adjudicated under Option A per
  `SLICE21_HASH_DISCREPANCY_GOVERNANCE_CLOSURE_OPTION_A.md`.

---

## 4. REPOSITORY DISCOVERY SUMMARY

### 4A. Repository Structure

| Component | Files / Tables | Status |
| :--- | :--- | :---: |
| Frontend (React/Vite) | `src/App.jsx`, `src/supabase.js`, `src/index.css` | Active |
| Database schemas | `database/schema_slice1.sql` → `schema_slice22.sql` (22 files) | Slices 1–21 locked; Slice 22 on-disk unverified |
| Verification suites | `database/verify_slice1.sql` → `verify_slice22.sql` (22 files) | Slices 1–21 verified; Slice 22 NOT executed |
| Governance artifacts | ~170 markdown files in root | Slices 1–21 fully documented |

### 4B. Slice 22 On-Disk State

`database/schema_slice22.sql` (26,227 bytes / 648 lines) is **physically present** in the repository.
`database/verify_slice22.sql` (36,982 bytes) is **physically present** in the repository.

**Current Slice 22 Status: IMPLEMENTED ON DISK / NOT VERIFIED / NOT LOCKED.**

**Reason verification is blocked:** 4 CRITICAL defects and 9 HIGH/MEDIUM defects identified by independent forensic audit. Execution of the verification suite in its current state is UNSAFE and would produce FALSE PASS results.

### 4C. Frontend Violation Coverage

Static inspection of `src/App.jsx` and `src/supabase.js` confirmed:
- **Zero** calls to Slice 22 RPCs (`fn_report_rule_violation`, `fn_review_rule_violation`, `fn_dispute_rule_violation`, `fn_resolve_violation_dispute`, `fn_post_violation_penalty`, `process_expired_violation_appeals`).
- The violation management module is backend-only. Frontend integration is pending and outside Slice 22 scope.

---

## 5. ALL CANDIDATE SLICE 22 GAPS — CLASSIFICATION

### Domain A: Rule Violation, Fine Ledger Posting & Dispute Management
- **Classification:** Genuine Slice 22 candidate (pre-selected, implemented on disk, awaiting remediation).
- **Sub-gaps:**
  - A-1. Fatal PL/pgSQL syntax error (`END BEGIN;` line 538) — CRITICAL
  - A-2. Lock inversion in `fn_resolve_violation_dispute` (Rank 5 → Rank 3) — CRITICAL
  - A-3. Lock inversion in `fn_post_violation_penalty` (Rank 3/4 → Rank 1) — CRITICAL
  - A-4. Worker auth incompatibility (`auth.uid()` = NULL in background) — CRITICAL
  - A-5. Fake concurrency assertions (S22-055..058 hard-coded PASS) — HIGH
  - A-6. Missing `REVOKE EXECUTE FROM PUBLIC, anon` — HIGH
  - A-7. Cross-society admin RLS leak (`pol_violation_disputes_select`) — HIGH
  - A-8. Silent error swallowing in worker (`EXCEPTION WHEN OTHERS THEN NULL`) — HIGH
  - A-9. Rate-limit first-row creation race — MEDIUM
  - A-10. Evidence URL format validation (array structure only, not URL format) — MEDIUM
  - A-11. Appeal deadline computed as `INTERVAL '7 days'` (not explicit 168 hours) — LOW

### Domain B: Digital Document Vault & Confidentiality Authorization System
- **Classification:** Future slice candidate (Rank 2 after Slice 22).
- **Gaps:** Sensitivity classification, signed URL issuance, access audit trail, approval state machine.
- **Disposition:** NOT Slice 22. Deferred.

### Domain C: SOS Guard Dispatch Logs
- **Classification:** Future slice candidate (Rank 3).
- **Gaps:** Responder ACK/dispatch tracking, false-alert rate limiting.
- **Disposition:** NOT Slice 22. Deferred.

### Domain D: Parcel Pickup OTP Verification
- **Classification:** Future slice candidate (Rank 4).
- **Gaps:** 6-digit OTP verification, unclaimed parcel expiration workers.
- **Disposition:** NOT Slice 22. Deferred.

---

## 6. CANDIDATE RANKING WITH SECURITY JUSTIFICATION

| Rank | Domain | Security Impact | Reason |
| :---: | :--- | :---: | :--- |
| 1 | **Domain A (Rule Violations — current Slice 22)** | CRITICAL | Already implemented; 4 CRITICAL defects block verification; financial serialization risk; cross-society RLS leak; worker never processes expired appeals |
| 2 | Domain B (Document Vault) | HIGH | PII exposure risk; unsigned URL leakage |
| 3 | Domain C (SOS Guard Dispatch) | MEDIUM | Emergency response accountability |
| 4 | Domain D (Parcel OTP) | MEDIUM | Gate security bypass risk |

**Recommendation confirmed: Domain A (Rule Violations) is the only appropriate Slice 22 scope.**

---

## 7. RECOMMENDED SLICE 22 SCOPE

**Society Rule Violation, Fine Ledger Posting & Dispute Management System**

This scope covers the micro-remediation of `database/schema_slice22.sql` and the corresponding upgrade of `database/verify_slice22.sql` (+ Node.js multi-session harness) to address all 4 CRITICAL and 9 HIGH/MEDIUM findings identified by the independent forensic audit. The schema tables, RPCs, RLS, and indexes already exist on disk but contain disqualifying defects.

**Scope includes:**
1. Syntax correction (Finding M — `END BEGIN;` → `END;`)
2. Lock-order correction in `fn_resolve_violation_dispute` (Finding C — Rank 3 → Rank 5)
3. Lock-order correction in `fn_post_violation_penalty_internal` (Finding D — Rank 1 → Rank 3 → Rank 4)
4. Worker architecture refactoring: split `fn_post_violation_penalty` (JWT-authenticated) from `fn_post_violation_penalty_internal` (service-role callable) (Finding H)
5. Rate-limit atomicity: atomic `INSERT ... ON CONFLICT DO NOTHING` + `SELECT FOR UPDATE` (Finding F)
6. Cross-society RLS fix: `pol_violation_disputes_select` + society scope check (Finding K)
7. `REVOKE EXECUTE FROM PUBLIC, anon` on all Slice 22 routines (Finding I)
8. Evidence URL format validation: enforce `http://`/`https://` element types (Finding L)
9. Worker error observability: replace silent `NULL` with structured JSONB error log (Finding G)
10. Verification suite upgrade: replace 5 fake/vacuous assertions with 9+2 active multi-session proofs (Findings A, B, E, G)

---

## 8. EXPLICIT NON-SCOPE

The following are explicitly excluded from Slice 22:

- Document vault (Domain B) — deferred
- SOS dispatch logs (Domain C) — deferred
- Parcel OTP verification (Domain D) — deferred
- Any modification to locked Slices 1–21 schemas or verify files
- Frontend (React) integration of violation module RPCs
- Push notification integration for violation events
- PDF/report generation for violation summaries
- Multi-society aggregated reporting

---

## 9. SECURITY THREAT MODEL

| Threat ID | Threat Description | Attack Vector | Mitigated By |
| :---: | :--- | :--- | :--- |
| T-01 | Cross-society privilege escalation via admin `is_admin()` without society filter | RLS bypass (Policy K) | Fix `pol_violation_disputes_select` to add `society_id = get_user_society_id(auth.uid())` |
| T-02 | Deadlock between dispute and resolve under concurrent Rank 5→3 / Rank 3→5 lock acquisition | Concurrency | Fix lock order to strict Rank 3→5 in both RPCs |
| T-03 | Deadlock between fine posting and Slice 2 financial operations under Rank 3/4→1 vs 1→3/4 conflict | Concurrency | Fix lock order to Rank 1→3→4 in `fn_post_violation_penalty_internal` |
| T-04 | Anonymous / unauthenticated caller invocation of violation RPCs via PostgreSQL default PUBLIC EXECUTE grant | Privilege escalation | Add `REVOKE EXECUTE FROM PUBLIC, anon` on all Slice 22 routines |
| T-05 | Worker silently fails all expired-penalty processing due to `auth.uid() = NULL` in background context | Worker auth incompatibility | Split public/internal RPC; use sentinel UUID `00000000-0000-0000-0000-000000000000` for worker actor_id |
| T-06 | Spam / harassment via unlimited violation reporting | Rate limiting abuse | Atomic rate-limit with `INSERT ON CONFLICT DO NOTHING` + `SELECT FOR UPDATE` (first-row race elimination) |
| T-07 | Stored XSS or malformed data via JSONB evidence URL injection | Input validation | Enforce URL schema (`http://`/`https://`) in `fn_is_valid_evidence_urls` |
| T-08 | Replay / duplicate financial posting of same penalty | Duplicate submission | Idempotency key `violation_penalty:{penalty_id}` on `ledger_transactions` + `is_posted` flag |
| T-09 | Resident bypasses 168-hour appeal window by exploiting server clock ambiguity | TOCTOU | Strict `CURRENT_TIMESTAMP < appeal_deadline` at dispute submission; strict `CURRENT_TIMESTAMP >= appeal_deadline` at worker posting |
| T-10 | Admin posts fine while dispute is pending (`disputed` status) | State machine bypass | Status gate check inside `fn_post_violation_penalty` rejects non-postable states |
| T-11 | IDOR: resident accessing another society's violation record via direct RPC call | Cross-society IDOR | Society scope check `v_caller_society = v_violation.society_id` inside every RPC |
| T-12 | Resident self-reports violation against themselves | Invalid report | `CHECK (reporter_id != subject_user_id)` + explicit RPC gate |
| T-13 | Silent worker exception swallowing masks persistent failures | Audit failure | Replace `EXCEPTION WHEN OTHERS THEN NULL` with structured JSONB error log to `violation_audit_logs` |
| T-14 | Non-subject resident disputes another resident's violation | Authorization bypass | `v_violation.subject_user_id != v_caller_id` gate in `fn_dispute_rule_violation` |
| T-15 | Evidence of fake concurrency tests producing false security assurance | Test integrity | Replace static S22-055..058 with active Node.js multi-session harness (C1-A..C5) |
| T-16 | Direct DML bypass of RPC security boundary on violation tables | DML bypass | `REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON ... FROM authenticated, anon` (already in schema; verify not bypassed) |

---

## 10. SECURITY INVARIANTS

| Invariant ID | Statement |
| :--- | :--- |
| INV-S22-01 | All violation state transitions are exclusively governed by SECURITY DEFINER RPCs with `SET search_path = pg_catalog, public`. Zero direct client DML is permitted. |
| INV-S22-02 | `fn_post_violation_penalty_internal` acquires locks in strict order: Rank 1 (`properties`) → Rank 3 (`rule_violations`) → Rank 4 (`violation_penalties`). No Rank 3/4 lock may be acquired before Rank 1. |
| INV-S22-03 | `fn_resolve_violation_dispute` acquires locks in strict order: Rank 3 (`rule_violations`) → Rank 5 (`violation_disputes`). No Rank 5 lock may be acquired before Rank 3. |
| INV-S22-04 | `fn_dispute_rule_violation` acquires locks in strict order: Rank 3 (`rule_violations`) → Rank 4 (`violation_penalties`) → Rank 5 (`violation_disputes`). |
| INV-S22-05 | The financial serialization anchor (Rank 1 `properties` FOR UPDATE lock) in `fn_post_violation_penalty_internal` guarantees 100% serialization with Slice 2 `fn_generate_charge` / `fn_process_payment` on the same property. |
| INV-S22-06 | A violation penalty may be financially posted ONLY when: `(violation.status = 'penalty_assessed' AND CURRENT_TIMESTAMP >= penalty.appeal_deadline) OR (violation.status = 'dispute_upheld')`. All other status combinations are rejected. |
| INV-S22-07 | A dispute may be submitted ONLY when: `violation.status = 'penalty_assessed' AND CURRENT_TIMESTAMP < penalty.appeal_deadline AND penalty.is_posted = FALSE`. |
| INV-S22-08 | The `violation_penalties.is_posted` flag and `violation_rate_limits` table are protected by `FORCE ROW LEVEL SECURITY` with no direct client SELECT/INSERT/UPDATE/DELETE policies. |
| INV-S22-09 | The background worker `process_expired_violation_appeals` uses actor_id sentinel `'00000000-0000-0000-0000-000000000000'::uuid` and NEVER calls `auth.uid()`. All errors are logged to `violation_audit_logs` as structured JSONB; no exception is silently swallowed. |
| INV-S22-10 | Idempotency key `'violation_penalty:' || penalty_id::text` on `ledger_transactions.idempotency_key` prevents duplicate financial entries even under concurrent posting attempts. |
| INV-S22-11 | `EXECUTE` privilege on all Slice 22 routines is revoked from `PUBLIC` and `anon`. Only `authenticated` (for resident/admin-callable RPCs) and `service_role` (for internal and worker routines) may invoke them. |
| INV-S22-12 | The RLS policy `pol_violation_disputes_select` restricts admin access to disputes scoped strictly to `society_id = get_user_society_id(auth.uid())`. Zero cross-society dispute visibility. |
| INV-S22-13 | `fn_is_valid_evidence_urls` validates: (a) input is NULL or JSON array; (b) array length ≤ 10; (c) every element is a JSON string; (d) every string begins with `http://` or `https://`. |
| INV-S22-14 | Violation reporting rate is limited to maximum 3 reports per reporter per society per sliding 1-hour window. The rate-limit row is created atomically via `INSERT ON CONFLICT DO NOTHING` before `SELECT FOR UPDATE` to eliminate the first-row creation race. |

---

## 11. PROPOSED VERIFICATION ASSERTIONS

**Current Authoritative Baseline:** 791 / 791 PASS
**Proposed Slice 22 Assertions:** 65
**Proposed Future Target:** 791 + 65 = 856 / 856 PASS *(future target only — ZERO currently verified)*

| Assertion ID | Category | Description | Expected Result | Security Rationale |
| :---: | :---: | :--- | :---: | :--- |
| S22-001 | Functional | `rule_violations` table exists | PASS | Schema baseline |
| S22-002 | Functional | `violation_penalties` table exists | PASS | Schema baseline |
| S22-003 | Functional | `violation_disputes` table exists | PASS | Schema baseline |
| S22-004 | Functional | `violation_rate_limits` table exists | PASS | Schema baseline |
| S22-005 | Functional | `violation_audit_logs` table exists | PASS | Schema baseline |
| S22-006 | Functional | `fn_is_valid_evidence_urls` exists with URL format check | PASS | Input validation (INV-S22-13) |
| S22-007 | Functional | All 8 Slice 22 RPC routines exist in `pg_proc` | PASS | Schema completeness |
| S22-008 | Functional | Required indexes exist (`idx_rule_violations_society_status`, etc.) | PASS | Query performance |
| S22-009 | Security | Anon call to `fn_report_rule_violation` is rejected + `REVOKE FROM PUBLIC` verified | REJECT (42501/permission denied) | INV-S22-11 |
| S22-010 | Security | Anon call to `fn_review_rule_violation` is rejected + `REVOKE FROM PUBLIC` verified | REJECT | INV-S22-11 |
| S22-011 | Security | Anon call to `fn_dispute_rule_violation` is rejected + `REVOKE FROM PUBLIC` verified | REJECT | INV-S22-11 |
| S22-012 | Security | Anon call to `fn_resolve_violation_dispute` is rejected + `REVOKE FROM PUBLIC` verified | REJECT | INV-S22-11 |
| S22-013 | Security | Anon call to `fn_post_violation_penalty` is rejected + `REVOKE FROM PUBLIC` verified | REJECT | INV-S22-11 |
| S22-014 | Security | Non-admin call to `fn_review_rule_violation` is rejected | REJECT (Access Denied) | INV-S22-01 |
| S22-015 | Security | Non-admin call to `fn_post_violation_penalty` is rejected | REJECT (Access Denied) | INV-S22-01 |
| S22-016 | Functional | Resident reports valid violation — returns violation UUID | PASS (UUID returned) | End-to-end happy path |
| S22-017 | Security | Self-reporting rejected by RPC | REJECT (Invalid Operation) | T-12 |
| S22-018 | Security | Cross-society report rejected | REJECT (Access Denied) | T-11 |
| S22-019 | Functional | Short description (< 10 chars) rejected | REJECT (check constraint) | Data integrity |
| S22-020 | Functional | Sequential rate limit — 2nd/3rd reports within window succeed | PASS | INV-S22-14 |
| S22-021 | Security | 4th report within 1-hour window is rejected | REJECT (Rate Limit Exceeded) | INV-S22-14 |
| S22-022 | Functional | Violation status = `'reported'` after submission | PASS (`'reported'`) | State machine baseline |
| S22-023 | Functional | Admin dismisses violation — status = `'dismissed'` | PASS (`'dismissed'`) | State machine transition |
| S22-024 | Functional | Admin assesses penalty — status = `'penalty_assessed'` | PASS (`'penalty_assessed'`) | State machine transition |
| S22-025 | Functional | Penalty amount ≤ 0 rejected | REJECT | Data integrity |
| S22-026 | Functional | Penalty amount > 50000 rejected | REJECT | Data integrity |
| S22-027 | Functional | Exact 168-hour (`INTERVAL '168 hours'`) appeal deadline computed | PASS (exact equality check) | INV-S22-07; T-09 |
| S22-028 | Functional | Audit log `PENALTY_ASSESSED` event written | PASS | Auditability |
| S22-029 | Security | Re-review of dismissed violation rejected | REJECT (Invalid State) | State machine guard |
| S22-030 | Security | Cross-society violation review rejected | REJECT | T-11 |
| S22-031 | Security | Non-subject resident dispute rejected | REJECT (Access Denied) | T-14 |
| S22-032 | Functional | Subject resident disputes within window — returns dispute UUID | PASS (UUID returned) | INV-S22-07 |
| S22-033 | Functional | Dispute record status = `'pending'` | PASS | State machine baseline |
| S22-034 | Security | Duplicate dispute by same resident rejected | REJECT (UNIQUE constraint) | T-08 |
| S22-035 | Security | Dispute on dismissed violation rejected | REJECT (Invalid State) | State machine guard |
| S22-036 | Functional | Short dispute reason (< 10 chars) rejected | REJECT | Data integrity |
| S22-037 | Security | Dispute after appeal deadline rejected | REJECT (Deadline Expired) | T-09; INV-S22-07 |
| S22-038 | Functional | Audit log `VIOLATION_DISPUTED` event written | PASS | Auditability |
| S22-039 | Functional | Admin upholds dispute — violation status = `'dispute_upheld'` | PASS | State machine transition |
| S22-040 | Functional | Admin reverses dispute — violation status = `'dispute_reversed'` | PASS | State machine transition |
| S22-041 | Functional | Invalid resolution value rejected | REJECT (Invalid Resolution) | Data integrity |
| S22-042 | Security | Non-admin dispute resolution rejected | REJECT (Access Denied) | INV-S22-01 |
| S22-043 | Security | Re-resolving already-resolved dispute rejected | REJECT (Already Resolved) | State machine guard |
| S22-044 | Security | Financial posting of `'dispute_reversed'` violation rejected | REJECT (Posting Blocked) | INV-S22-06 |
| S22-045 | Security | Cross-society dispute resolution rejected | REJECT (Access Denied) | T-11 |
| S22-046 | Functional | Audit log `DISPUTE_RESOLVED` event written | PASS | Auditability |
| S22-047 | Security | Financial posting blocked when appeal window still active | REJECT (Appeal Window Active) | INV-S22-06; T-09 |
| S22-048 | Security | Financial posting blocked when dispute is `'pending'` | REJECT (Posting Blocked) | INV-S22-06; T-10 |
| S22-049 | Functional | Financial posting succeeds after appeal deadline expires | PASS (charge UUID returned) | INV-S22-06 |
| S22-050 | Functional | Financial posting succeeds for `'dispute_upheld'` violation | PASS (charge UUID returned) | INV-S22-06 |
| S22-051-BLOCK | Concurrency | Causal Rank 1 property lock proof: Session A holds `properties FOR UPDATE`; Session B calling `fn_post_violation_penalty` is confirmed waiting on `pg_locks` with `granted = false`; Session A commits; Session B completes | PASS (blocking confirmed, then completion confirmed) | INV-S22-02; INV-S22-05 |
| S22-052 | Functional | Maintenance charge record created in `maintenance_charges` | PASS | Financial integration |
| S22-053 | Functional | Ledger transaction created with idempotency key | PASS | INV-S22-10 |
| S22-054 | Security | Duplicate financial posting rejected | REJECT (Duplicate Operation) | INV-S22-10; T-08 |
| S22-C1A | Concurrency | C1-A: 2 parallel sessions call `fn_report_rule_violation` for new reporter — 0 PK errors, exactly 1 rate-limit row, counter = 1 | PASS | INV-S22-14; T-06 |
| S22-C1B | Concurrency | C1-B: 3 parallel reports — all 3 succeed, counter = 3, 3 violation rows | PASS | INV-S22-14 |
| S22-C1C | Concurrency | C1-C: 4 parallel reports — exactly 3 succeed, 1 rejected, counter = 3 | PASS | INV-S22-14; T-06 |
| S22-C1D | Concurrency | C1-D: Rejected 4th report does not increment counter or create phantom violation | PASS | INV-S22-14 |
| S22-C1E | Concurrency | C1-E: Rollback of Session A during first report; Session B successfully creates rate-limit row without phantom lock | PASS | INV-S22-14; T-06 |
| S22-C2 | Concurrency | C2: `fn_review_rule_violation` vs `fn_dispute_rule_violation` on same violation — Rank 3 lock serializes; winner completes, loser fails cleanly; 0 deadlocks | PASS | INV-S22-03; INV-S22-04 |
| S22-C3 | Concurrency | C3: `fn_dispute_rule_violation` vs `fn_resolve_violation_dispute` on same violation — strict Rank 3→4→5 prevents deadlock; 0 deadlocks | PASS | INV-S22-03; INV-S22-04 |
| S22-C4 | Concurrency | C4: 2 concurrent `fn_post_violation_penalty` calls on same penalty — exactly 1 charge + 1 ledger entry created; second call rejected; 0 deadlocks | PASS | INV-S22-02; INV-S22-10 |
| S22-C5 | Concurrency | C5: Concurrent Slice 22 fine posting vs Slice 2 `fn_generate_charge` on same property — serialize on Rank 1; 0 deadlocks; 0 double-entry | PASS | INV-S22-05; T-03 |
| S22-059-WRK | Functional | Worker: per-item atomicity + structured JSONB error log (failure of item N does not roll back items 1..N-1; errors written to `violation_audit_logs`) | PASS | INV-S22-09; T-13 |
| S22-060 | Governance | Cumulative arithmetic check: `791 + 65 = 856` | PASS (856) | Governance accounting |

---

## 12. PROPOSED SCHEMA CHANGES

### 12A. Tables (All Exist On Disk — No New Tables Required for Core Scope)

Five tables are already physically present in `database/schema_slice22.sql`:
`rule_violations`, `violation_penalties`, `violation_disputes`, `violation_rate_limits`, `violation_audit_logs`.

No new tables are required for the micro-remediation scope.

> Note on `actor_id` FK in `violation_audit_logs`: The worker sentinel UUID
> `'00000000-0000-0000-0000-000000000000'::uuid` requires that the FK
> `actor_id REFERENCES public.users(id)` either be removed or replaced with a
> CHECK/NOT NULL without FK, since the sentinel UUID will not exist in `users`.
> **This is a schema change required for worker architecture correctness.**

**Proposed schema change:** Alter `violation_audit_logs.actor_id` to `UUID NOT NULL` (remove FK to `public.users(id)`) to allow sentinel worker UUID without requiring a dummy user row.

### 12B. Functions — Proposed Changes

| Function | Change Type | Description |
| :--- | :---: | :--- |
| `fn_is_valid_evidence_urls` | MODIFY | Add element string-type check + `http://`/`https://` prefix validation |
| `fn_report_rule_violation` | MODIFY | Replace bare `FOR UPDATE` + plain INSERT with atomic `INSERT ON CONFLICT DO NOTHING` + `SELECT FOR UPDATE` pattern for rate-limit first-row creation |
| `fn_resolve_violation_dispute` | MODIFY | Swap lock order: lock `rule_violations` (Rank 3) FIRST, then `violation_disputes` (Rank 5) |
| `fn_post_violation_penalty` | MODIFY | Rename to wrapper function: add `auth.uid()` / `is_admin()` check, then delegate to `fn_post_violation_penalty_internal(p_violation_id, auth.uid())` |
| `fn_post_violation_penalty_internal` | CREATE (NEW) | New internal SECURITY DEFINER function; accepts `p_violation_id UUID, p_actor_id UUID`; acquires Rank 1 FIRST, then Rank 3, then Rank 4; used by both wrapper and worker |
| `process_expired_violation_appeals` | MODIFY | Replace `auth.uid()` call with sentinel UUID; replace `fn_post_violation_penalty(...)` call with `fn_post_violation_penalty_internal(v_rec.violation_id, '00000000-0000-0000-0000-000000000000'::uuid)`; fix `END BEGIN;` to `END;`; replace `EXCEPTION WHEN OTHERS THEN NULL` with structured JSONB error logging to `violation_audit_logs` |

### 12C. Lock Hierarchy (Corrected)

```
Rank 1 — public.properties
Rank 2 — public.violation_rate_limits
Rank 3 — public.rule_violations
Rank 4 — public.violation_penalties
Rank 5 — public.violation_disputes
Rank 6 — public.maintenance_charges
Rank 7 — public.ledger_transactions / public.violation_audit_logs
```

### 12D. RLS Changes

| Policy | Change | Corrected Expression |
| :--- | :---: | :--- |
| `pol_violation_disputes_select` | MODIFY | `disputed_by = auth.uid() OR (public.is_admin() AND society_id = public.get_user_society_id(auth.uid()))` |

### 12E. Privilege Changes

```sql
-- Add these to schema_slice22.sql (currently missing):
REVOKE EXECUTE ON FUNCTION public.fn_is_valid_evidence_urls(JSONB) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.fn_report_rule_violation(UUID, UUID, VARCHAR, TEXT, JSONB) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.fn_review_rule_violation(UUID, VARCHAR, NUMERIC, TEXT) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.fn_dispute_rule_violation(UUID, TEXT) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.fn_resolve_violation_dispute(UUID, VARCHAR, TEXT) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.fn_post_violation_penalty(UUID) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.fn_post_violation_penalty_internal(UUID, UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.process_expired_violation_appeals() FROM PUBLIC, anon, authenticated;

-- Grant internal function to service_role only:
GRANT EXECUTE ON FUNCTION public.fn_post_violation_penalty_internal(UUID, UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.process_expired_violation_appeals() TO service_role;
```

---

## 13. STATE MACHINE

### 13A. Legal States

`reported` | `under_review` | `dismissed` | `penalty_assessed` | `disputed` | `dispute_upheld` | `dispute_reversed` | `financially_posted`

### 13B. Legal Transitions

| From | To | Trigger | Authorized By |
| :--- | :--- | :--- | :--- |
| `reported` | `under_review` | Admin starts review | Admin RPC |
| `reported` / `under_review` | `dismissed` | Admin dismisses | `fn_review_rule_violation(action='dismiss')` |
| `reported` / `under_review` | `penalty_assessed` | Admin assesses fine | `fn_review_rule_violation(action='assess_penalty')` |
| `penalty_assessed` | `disputed` | Resident disputes within window | `fn_dispute_rule_violation` |
| `penalty_assessed` | `financially_posted` | Admin or worker posts after deadline | `fn_post_violation_penalty` / `process_expired_violation_appeals` |
| `disputed` | `dispute_upheld` | Admin upholds dispute | `fn_resolve_violation_dispute(resolution='upheld')` |
| `disputed` | `dispute_reversed` | Admin reverses dispute | `fn_resolve_violation_dispute(resolution='reversed')` |
| `dispute_upheld` | `financially_posted` | Admin posts fine post-resolution | `fn_post_violation_penalty` |

### 13C. Forbidden Transitions

| From | To | Reason |
| :--- | :--- | :--- |
| `reported` | `financially_posted` | Must assess penalty first |
| `dismissed` | Any | Terminal state |
| `financially_posted` | Any | Terminal state |
| `dispute_reversed` | `financially_posted` | Reversed = fine cancelled |
| `penalty_assessed` | `financially_posted` | Only allowed AFTER appeal deadline |
| `disputed` | `financially_posted` | Blocked while dispute pending |

---

## 14. TRANSACTION / CONCURRENCY SEMANTICS

### 14A. Frame of Reference

PostgreSQL `READ COMMITTED` isolation throughout. All critical state checks performed under `SELECT FOR UPDATE` row-level exclusive locks.

### 14B. Per-RPC Lock Trace (Corrected)

| RPC | Lock Sequence |
| :--- | :--- |
| `fn_report_rule_violation` | Rate limit (Rank 2 INSERT ON CONFLICT / FOR UPDATE) → violation (Rank 3 INSERT implicit) → audit (Rank 7 INSERT) |
| `fn_review_rule_violation` | Violation (Rank 3 FOR UPDATE) → penalty (Rank 4 INSERT implicit) → audit (Rank 7) |
| `fn_dispute_rule_violation` | Violation (Rank 3 FOR UPDATE) → penalty (Rank 4 FOR UPDATE) → dispute (Rank 5 INSERT implicit) → audit (Rank 7) |
| `fn_resolve_violation_dispute` | Violation (Rank 3 FOR UPDATE) → dispute (Rank 5 FOR UPDATE) → audit (Rank 7) |
| `fn_post_violation_penalty_internal` | Property (Rank 1 FOR UPDATE) → violation (Rank 3 FOR UPDATE) → penalty (Rank 4 FOR UPDATE) → charge (Rank 6 INSERT) → ledger (Rank 7 INSERT) → audit (Rank 7 INSERT) |

### 14C. Deadlock Prevention

All RPCs acquire locks in strict ascending rank order. No Rank N lock may be acquired after a Rank M lock where M > N. This guarantees deadlock impossibility under any concurrency pattern within Slice 22, and guarantees serialization compatibility with Slice 2 financial operations.

---

## 15. FAILURE PATH SEMANTICS

| Failure Point | Consequence | Recovery |
| :--- | :--- | :--- |
| Pre-lock validation failure | Exception raised; transaction not yet started or rolled back cleanly | No state mutation |
| Lock acquisition failure (lock timeout) | Exception raised; partial state NOT committed | Entire transaction rolled back; violation status unchanged |
| Exception after Rank 3 lock but before Rank 4 | Transaction rolls back; penalty record NOT created | Status remains `under_review` |
| Exception after charge INSERT but before ledger INSERT | Transaction rolls back; charge NOT persisted | Penalty `is_posted` remains FALSE; re-postable |
| Worker item failure | Single-item SAVEPOINT rolled back; worker logs error to `violation_audit_logs` | Next item in loop continues; processed count excludes failed item |
| Worker fatal error (loop exception) | Worker returns JSONB with `failed_count > 0` | Caller/scheduler observes structured error; items remain pending for next scheduled run |

---

## 16. AUDIT / LEDGER SEMANTICS

- `violation_audit_logs` is append-only (REVOKE INSERT, UPDATE, DELETE, TRUNCATE from `authenticated`, `anon`).
- Every RPC transition writes one audit event with: `event_type`, `old_status`, `new_status`, `actor_id`, `details JSONB`.
- Worker errors write structured error records: `event_type = 'WORKER_ERROR'`, `details = jsonb_build_object('penalty_id', ..., 'sqlstate', ..., 'error_class', ...)`.
- `violation_audit_logs.actor_id` uses `UUID NOT NULL` without FK constraint to allow sentinel worker UUID.

---

## 17. ABUSE / RATE-LIMIT CONTROLS

- Maximum 3 violation reports per reporter per society per 1-hour sliding window.
- Rate limit stored in `violation_rate_limits` with composite PK `(society_id, reporter_id)`.
- Atomic first-row creation: `INSERT ... ON CONFLICT (society_id, reporter_id) DO NOTHING` followed by `SELECT FOR UPDATE` eliminates the initial-row creation race (Finding F).
- Window reset on `window_start` expiry via `(CURRENT_TIMESTAMP - window_start) > INTERVAL '1 hour'` check.

---

## 18. DEPENDENCY / CONCURRENCY ANALYSIS

### 18A. Cross-Slice Dependencies

| Slice | Dependency | Nature |
| :--- | :--- | :--- |
| Slice 1 | `societies`, `properties`, `users` | FK references; Rank 1 lock on `properties` |
| Slice 2 | `maintenance_charges`, `ledger_transactions`, `fn_generate_charge` | Fine posts to Slice 2 financial tables; Rank 1 `properties` lock ensures full serialization |
| Slice 9 | `rule_violations` | Legacy table; Slice 22 redefines and replaces RPCs |
| Slice 21 | `vendor_rate_limits` (Rank 2 in Slice 21) | Zero table overlap; Slice 22 Rank 2 = `violation_rate_limits` (distinct table) |

### 18B. Slice 2 Financial Serialization

Slice 2 (`fn_generate_charge`, `fn_process_payment`) acquires `SELECT 1 FROM public.properties WHERE id = p_property_id FOR UPDATE` as its first lock. Slice 22 `fn_post_violation_penalty_internal` acquires the same lock pattern first. Both operations serializing on the same property row guarantees mutual exclusion: zero double-entry risk, zero ledger balance race conditions.

### 18C. Slice 21 Compatibility

Slice 21 lock hierarchy uses distinct Rank 1 (`societies`), Rank 2 (`vendor_rate_limits`), Rank 3 (`security_blacklist_records`), Rank 4 (`society_assets`), Rank 5 (`amc_vendor_contracts`), Rank 6 (`vendor_access_passes`), Rank 7 (`security_denial_logs`). Zero table-level overlap with Slice 22. Zero deadlock potential between Slices 21 and 22.

---

## 19. REGRESSION IMPACT ON 791/791

**Zero regression risk.** All Slice 22 changes are additive:
- New function `fn_post_violation_penalty_internal` does not affect any Slice 1–21 table or RPC.
- Modified `pol_violation_disputes_select` is a Slice 22 policy only (table `violation_disputes` does not exist in Slices 1–21).
- REVOKE statements target Slice 22 routines only.
- `violation_audit_logs.actor_id` FK removal is Slice 22 table only.
- No Slice 1–21 schema, verify, or lock file is modified.

Regression verification plan: Before Slice 22 verification execution, run `database/verify_slice1.sql` through `database/verify_slice21.sql` to confirm 791/791 remains intact.

---

## 20. ROLLBACK / RECOVERY STRATEGY

If any Slice 22 micro-remediation produces an unexpected result during verification:
1. Execute a targeted `DROP FUNCTION / DROP TABLE` rollback script (prepared in advance, NOT executed here).
2. Re-run `database/verify_slice1.sql` through `database/verify_slice21.sql` to confirm 791/791 unaffected.
3. Re-examine the defect; update micro-remediation plan.
4. Seek re-authorization before retrying.

---

## 21. MIGRATION ORDERING

```
1. Apply schema_slice22.sql corrections:
   a. Drop and recreate fn_is_valid_evidence_urls (URL validation)
   b. Drop and recreate fn_report_rule_violation (rate-limit atomicity)
   c. Create fn_post_violation_penalty_internal (NEW)
   d. Drop and recreate fn_post_violation_penalty (wrapper)
   e. Drop and recreate fn_resolve_violation_dispute (lock order fix)
   f. Drop and recreate process_expired_violation_appeals (worker fix + syntax fix)
   g. ALTER TABLE violation_audit_logs DROP CONSTRAINT ... (remove actor_id FK)
   h. DROP and recreate pol_violation_disputes_select (RLS fix)
   i. REVOKE EXECUTE on all Slice 22 routines from PUBLIC, anon
   j. GRANT EXECUTE on internal routines to service_role only

2. Apply verify_slice22.sql corrections:
   a. Update S22-009..S22-013 to include REVOKE FROM PUBLIC checks
   b. Update S22-027 to verify exact 168-hour equality
   c. Replace S22-051 with S22-051-BLOCK (multi-session lock proof)
   d. Replace S22-055..S22-058 with S22-C1A..S22-C4 (multi-session harness calls)
   e. Add S22-C1B..S22-C1E, S22-C5 (new concurrency assertions)
   f. Replace S22-059 with S22-059-WRK (worker error observability test)
   g. Update S22-060 arithmetic from 851 to 856

3. Create/update scratch/run_slice22_concurrency_tests.js (Node.js harness)
```

---

## 22. SECURITY LOCK REQUIREMENTS

Before Slice 22 can be formally locked, the following gate must be cleared:

1. All micro-remediations applied to `database/schema_slice22.sql`.
2. All verification suite updates applied to `database/verify_slice22.sql`.
3. `scratch/run_slice22_concurrency_tests.js` created and all 9 multi-session tests passing.
4. Full `database/verify_slice22.sql` execution returning **856 / 856 PASS** (791 + 65 = 856).
5. Independent forensic post-remediation audit: Verdict `A — FORENSICALLY SOUND`.
6. Lock-readiness gate audit confirming no new defects introduced.
7. Explicit user lock authorization.
8. SHA-256 computation of `schema_slice22.sql`, `verify_slice22.sql`, and `SLICE22_FINAL_SECURITY_PLAN.md` at lock.

---

## 23. IMPLEMENTATION AUTHORIZATION GATE

> [!IMPORTANT]
> **The following explicit user authorizations are required before any implementation activity:**
>
> **GATE A — MICRO-REMEDIATION SCHEMA AUTHORIZATION:**
> User must explicitly authorize: "Proceed with Slice 22 micro-remediation schema implementation."
>
> **GATE B — VERIFICATION EXECUTION AUTHORIZATION:**
> User must explicitly authorize: "Proceed with Slice 22 verification execution."
>
> **GATE C — LOCK AUTHORIZATION:**
> User must explicitly authorize: "Proceed with Slice 22 formal security lock."
>
> **None of Gates A, B, or C are granted by this planning document.**

---

## 24. PLAN ARTIFACT INFORMATION

```
FILENAME:   SLICE22_FINAL_SECURITY_PLAN_V2.md
LOCATION:   D:\Clients Applications\SU Society App\SLICE22_FINAL_SECURITY_PLAN_V2.md
STATUS:     PLAN ONLY — NOT IMPLEMENTED — NOT VERIFIED — NOT LOCKED
```

*(SHA-256, byte count, and line count to be computed and reported separately.)*

---

## 25. FINAL GOVERNANCE STATUS

```
SLICE 21:
LOCKED / IMMUTABLE

CURRENT AUTHORITATIVE BASELINE:
791 / 791 PASS

SLICE 22:
PLAN ONLY / NOT IMPLEMENTED (MICRO-REMEDIATION REQUIRED) / NOT VERIFIED / NOT LOCKED

PROPOSED SLICE 22 ASSERTIONS:
65

PROPOSED FUTURE CUMULATIVE TARGET:
791 + 65 = 856 / 856 PASS
(FUTURE TARGET ONLY — ZERO CURRENTLY VERIFIED)

IMPLEMENTATION AUTHORIZATION:
NOT GRANTED BY THIS PROMPT

DATABASE MUTATION:
NONE

SQL EXECUTION:
NONE

LOCKED ARTIFACT MUTATION:
NONE

NEXT REQUIRED ACTION:
EXPLICIT USER AUTHORIZATION FOR GATE A
(Slice 22 Micro-Remediation Schema Implementation)
```
