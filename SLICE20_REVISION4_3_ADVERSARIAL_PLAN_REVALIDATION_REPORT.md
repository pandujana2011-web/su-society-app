# SLICE 20 REVISION 4.3 — FINAL ADVERSARIAL PLAN RE-VALIDATION REPORT

**Execution Date:** September 7, 2026  
**Target Repository:** `D:\Clients Applications\SU Society App`  
**Current Verified Locked Baseline:** `639 / 639 PASS (100%)`  
**Plans Under Review:** `Slice 2 Financial Serialization Remediation Plan` & `Slice 20 Revision 4.3 Final Security Plan Correction`  
**Mode:** `PLAN VALIDATION ONLY / ZERO IMPLEMENTATION AUTHORIZATION`

---

## 1. EXECUTIVE VERDICT

Following an exhaustive, read-only adversarial audit of the repository, database schemas, planning artifacts, lock ordering graphs, mathematical algorithms, and assertion suites, the overall verdict of this re-validation is:

```text
=====================================================
OVERALL VERDICT: NOT APPROVED — PLAN CORRECTIONS REQUIRED
=====================================================
```

### Summary of Classification Findings:
1. **PIN Generation CSPRNG Bit-Shift Bug (`CRITICAL BLOCKER`):** PL/pgSQL signed 32-bit `INT` left shift on `get_byte(v_bytes, 0) << 24` produces negative integers when bit 31 is set. Calling `abs()` on `-2147483648` (`-2^31`) causes an `integer out of range` overflow crash in PostgreSQL.
2. **Lock Order Discrepancy between Slice 2 and Slice 20 (`PLAN CORRECTION REQUIRED`):** Slice 2 proposed locking `societies FOR SHARE` before `properties FOR UPDATE`, whereas Slice 20 proposed locking `noc_requests FOR UPDATE` before `properties FOR UPDATE`. This inconsistency introduces potential cross-slice deadlock risk. Canonical hierarchy must enforce `properties FOR UPDATE` FIRST across ALL routines.
3. **Stale Assertion Count in Prior Summaries (`PLAN CORRECTION REQUIRED`):** Re-aligned assertion math: Baseline = 639; Slice 2 Remediation = 12 assertions (Projected = 651); Slice 20 Rev 4.3 = 71 assertions (Projected total post-Slice 20 = 722). Prior references to 44 / 695 were stale metrics from Revision 4.2.
4. **`fn_process_payment` Property Resolution Re-verification (`PASS WITH CONDITION`):** Resolved property ID MUST be re-verified after acquiring `properties FOR UPDATE` to prevent stale resolution races.
5. **Implementation Status (`STRICT BOUNDARY`):** ZERO database or application modifications performed. Baseline remains strictly `639 / 639 PASS`.

---

## 2. CURRENT VERIFIED BASELINE

The verified baseline for the repository is immutable:

```text
SLICES 1–18: 595 / 595 PASS
SLICE 19:      44 /  44 PASS
--------------------------------
CURRENT VERIFIED BASELINE: 639 / 639 PASS (100%)
```

- **Slices 1–19 Code & Schemas:** LOCKED / IMMUTABLE / UNTOUCHED.
- **Slice 2 Serialization Remediation:** PROJECTED (+12 assertions) / NOT IMPLEMENTED / UNVERIFIED.
- **Slice 20 Revision 4.3:** PROJECTED (+71 assertions) / NOT IMPLEMENTED / UNVERIFIED.
- **Projected Cumulative Total (Post Slice 2 & 20):** `722 assertions` (UNVERIFIED TARGET ONLY).

---

## 3. AUTHORITATIVE PLAN VERSIONS

Inspection of repository planning artifacts confirms:
- **Slice 2 Authoritative Plan:** `SLICE2_FINANCIAL_SERIALIZATION_REMEDIATION_PLAN.md` (Active).
- **Slice 20 Authoritative Plan:** `SLICE20_FINAL_IMPLEMENTATION_SECURITY_PLAN_REV4_3.md` (Active, supersedes Rev 4.2, Rev 4.1, Rev 4, Rev 3, Rev 2, Rev 1).
- **Stale/Superseded Plans Identified:** `SLICE20_FINAL_IMPLEMENTATION_SECURITY_PLAN_REV4_2.md` and prior revisions remain in root as reference logs but are formally marked **SUPERSEDED**.

---

## 4. REVISION CONSISTENCY & ASSERTION ACCOUNTING

| Metric Stage | Assertion Source | Incremental Assertions | Cumulative Verified Baseline | Cumulative Projected Total | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Current Baseline** | `verify_slice1.sql` to `verify_slice19.sql` | 639 | **639 / 639 PASS** | 639 | **VERIFIED** |
| **Slice 2 Remediation** | `verify_slice2_remediation.sql` (`S2-FS-001`..`S2-FS-012`) | +12 | 639 | **651** | **PROJECTED ONLY** |
| **Slice 20 Rev 4.3** | `verify_slice20.sql` (`S20-001`..`S20-071`) | +71 | 639 | **722** | **PROJECTED ONLY** |

*Note: The prior reference to 695 tests was based on 44 assertions in Revision 4.2. Revision 4.3 contains 71 assertions (`S20-001` to `S20-071`), yielding a projected cumulative total of 722.*

---

## 5. SLICE 2 SERIALIZATION VALIDATION

Adversarial audit of `schema_slice2.sql` routines (`fn_generate_charge`, `fn_process_payment`, `fn_reverse_charge`, `fn_reverse_payment`) confirms:
- All 4 financial mutation routines can alter property balance in `ledger_transactions`.
- To establish true mutual exclusion with Slice 20 NOC clearance (`fn_approve_noc`), every financial writer MUST acquire `SELECT 1 FROM public.properties WHERE id = v_property_id FOR UPDATE` before writing to `maintenance_charges`, `payments`, or `ledger_transactions`.

---

## 6. SLICE 20 PROPERTY LOCK VALIDATION

`fn_approve_noc` in Slice 20 Revision 4.3 specifies the following exact sequence:
1. Authenticate caller & verify `is_admin()`.
2. Fetch target `noc_requests` row.
3. Acquire `SELECT 1 FROM public.properties WHERE id = v_noc.property_id FOR UPDATE`.
4. Re-read outstanding balance: `v_outstanding_dues := fn_get_property_outstanding_balance(v_noc.property_id)`.
5. Validate balance equals `0.00` and mandatory checklist items are cleared.
6. Transition status to `approved`.

**Validation Result: PASS WITH CONDITION.**  
*Condition:* The fresh balance re-read MUST execute *after* `properties FOR UPDATE` is acquired. Snapshot isolation under `READ COMMITTED` guarantees that the re-read observes all committed financial writes up to the instant the property lock was acquired.

---

## 7. CONCURRENCY THREAT MODEL

Adversarial simulation of dual-session race conditions:

| Scenario | Transaction A | Transaction B | Serialization Point | Expected Outcome | Classification |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1** | `fn_approve_noc(P1)` | `fn_generate_charge(P1)` | `properties(P1) FOR UPDATE` | Tx B blocks until Tx A commits; NOC approves based on zero dues. Charge posts after. | `PASS` |
| **2** | `fn_generate_charge(P1)` | `fn_approve_noc(P1)` | `properties(P1) FOR UPDATE` | Tx B blocks until Tx A commits; Tx B unblocks, re-reads balance > 0, rejects NOC approval. | `PASS` |
| **3** | `fn_reverse_payment(Pay1)` | `fn_approve_noc(P1)` | `properties(P1) FOR UPDATE` | Reversal posts debit; NOC approval unblocks, detects non-zero balance, rejects approval. | `PASS` |
| **4** | `fn_approve_noc(P1)` | `fn_approve_noc(P1)` | `properties(P1) FOR UPDATE` | Second transaction observes status already `approved` and returns idempotently. | `PASS` |
| **5** | Operation on P1 | Operation on P2 | Independent Property Rows | Zero cross-property contention; 100% parallel execution. | `PASS` |

---

## 8. LOCK ORDERING / DEADLOCK ANALYSIS

### Discrepancy Identified:
- **Slice 2 Proposal:** `societies (FOR SHARE)` $\rightarrow$ `properties (FOR UPDATE)` $\rightarrow$ `payments` / `charges`.
- **Slice 20 Proposal:** `noc_requests (FOR UPDATE)` $\rightarrow$ `properties (FOR UPDATE)`.

If Transaction A locks `noc_requests` then attempts to lock `properties`, while Transaction B (e.g. background cancellation) locks `properties` then attempts to lock `noc_requests`, a deadlock cycle occurs.

### Required Lock Ordering Harmonization:
To eliminate deadlock risk across all functions, the canonical lock ordering MUST be strictly standardized as:

$$\text{LEVEL 1: } \text{public.properties (FOR UPDATE)}$$
$$\text{LEVEL 2: } \text{public.noc\_requests / maintenance\_charges / payments (FOR UPDATE)}$$
$$\text{LEVEL 3: } \text{public.ledger\_transactions (INSERT)}$$

*Society-level locking (`societies FOR SHARE`) is unnecessary and MUST be removed to eliminate society-wide lock contention.*

---

## 9. RATE-LIMIT SERIALIZATION

Revision 4.3 proposed locking `public.users WHERE id = auth.uid() FOR UPDATE` to serialize gatekeeper rate-limit updates when zero failure records exist in `noc_gatekeeper_rate_limits`.

### Validation Result: PASS.
- Every valid gatekeeper is a logged-in user in `public.users`.
- The `users` row exists permanently, guaranteeing `SELECT FOR UPDATE` always matches 1 row and acquires an exclusive lock.
- Alternatively, `pg_advisory_xact_lock(('x' || substr(md5('gatekeeper_rl_' || auth.uid()::text), 1, 16))::bit(64)::bigint)` achieves identical non-row locking mutual exclusion.

---

## 10. PIN GENERATION SECURITY — CRITICAL BLOCKER IDENTIFIED

### The Bug in Proposed PL/pgSQL Code:
```sql
v_random_int := (abs(get_byte(v_bytes, 0) << 24 | get_byte(v_bytes, 1) << 16 | get_byte(v_bytes, 2) << 8 | get_byte(v_bytes, 3))) :: BIGINT;
```

### Adversarial Failure Analysis:
1. In PL/pgSQL, bitwise `<< 24` on a byte value evaluated as a signed 32-bit `INTEGER` will set the sign bit (bit 31) whenever `get_byte(v_bytes, 0) >= 128`.
2. When bit 31 is set, the integer becomes negative (e.g., `-2147483648`).
3. In PostgreSQL, calling `abs(-2147483648)` throws a runtime error: `ERROR: integer out of range` because $+2,147,483,648$ exceeds the maximum positive 32-bit signed integer (`2147483647`).

### Mandatory Mathematical Correction (`CRITICAL BLOCKER`):
The CSPRNG integer conversion MUST cast each byte to `BIGINT` *before* shifting:
```sql
v_random_bigint := (get_byte(v_bytes, 0)::bigint << 24) |
                   (get_byte(v_bytes, 1)::bigint << 16) |
                   (get_byte(v_bytes, 2)::bigint << 8)  |
                   (get_byte(v_bytes, 3)::bigint);

IF v_random_bigint < 4294000000 THEN
  v_pin_str := lpad((v_random_bigint % 1000000)::text, 6, '0');
  EXIT;
END IF;
```
This guarantees `v_random_bigint` is always positive in range $[0, 4294967295]$, completely eliminating the overflow crash and zeroing modulo bias ($4294000000 = 4294 \times 10^6$).

---

## 11. TOKEN ENTROPY VALIDATION

- **Formatted Math:** $2^{48} = 281,474,976,710,656$ possible values for 6 CSPRNG bytes (12 hex characters).
- **Prefix Recommendation:** Replace static `PASS-2026-` prefix with generic `NOC-PASS-` to prevent year-hardcoding maintenance defects.

---

## 12. STATE MACHINE VALIDATION

The canonical state machine transitions for `noc_requests`:

```text
submitted ──► clearance_in_progress ──► approved ──► completed
    │                  │                   │
    ▼                  ▼                   ▼
 rejected           rejected            revoked
```
Forbidden transitions (`approved -> submitted`, `completed -> draft`, `rejected -> approved` without new request) are strictly guarded in RPC bodies by checking current status under `noc_requests FOR UPDATE`.

---

## 13. CHECKLIST INTEGRITY

To prevent duplicate checklist manipulation, `public.noc_checklist_items` MUST enforce a unique constraint:

```sql
CONSTRAINT uq_noc_checklist_category UNIQUE (noc_id, category)
```
Combined with `ARRAY_AGG(DISTINCT category ORDER BY category)`, this guarantees exact mandatory checklist category matching.

---

## 14. OWNERSHIP / OCCUPANCY SCOPE

`fn_complete_noc_transfer` updates `properties.owner_id`, `properties.tenant_id`, and `properties.occupancy_status`. It does **NOT** alter external historical owner registry tables, keeping scope strictly bounded to property occupancy state.

---

## 15. RLS / TENANCY

- `public.noc_requests` enforces `FORCE ROW LEVEL SECURITY`.
- `SELECT` policies restrict access to admins of the society and property owners/tenants.
- Direct client `INSERT`, `UPDATE`, and `DELETE` access is denied. All state changes occur through `SECURITY DEFINER` functions with `SET search_path = public, pg_temp`.

---

## 16. SECURITY DEFINER / ACL

- All RPCs verify caller identity (`auth.uid()`) and authorization (`is_admin()`).
- `process_expired_noc_passes()` is explicitly revoked from `PUBLIC` and `authenticated`, granted strictly to `service_role`.

---

## 17. SCHEDULER SECURITY

Automated pass expiration executes via `service_role` invocation of `process_expired_noc_passes()`. Execution under non-privileged roles is blocked by ACLs.

---

## 18. AUDIT SECURITY

Audit logs record `society_id`, `actor_id`, `entity_type`, `entity_id`, `action`, `timestamp`, and state metadata. Plaintext PINs and unhashed pass tokens are **NEVER** written to audit logs.

---

## 19. IDEMPOTENCY

- `fn_approve_noc` called on an already `approved` request returns current state without creating duplicate ledger or audit entries.
- Active NOC request duplicate submission is blocked by partial unique index `uq_active_noc_per_property`.

---

## 20. DIRECT-WRITE BYPASS ANALYSIS

Direct SQL `INSERT` or `UPDATE` into `maintenance_charges`, `payments`, or `ledger_transactions` by `authenticated` users is blocked by RLS policies lacking write rules.

---

## 21. ROLLBACK SAFETY

Rollback script executes in strict reverse-dependency order without `CASCADE`:
1. Revoke function privileges.
2. Drop RPC functions using exact signatures.
3. Drop child tables (`noc_gatekeeper_rate_limits`, `noc_move_passes`, `noc_checklist_items`).
4. Drop parent table (`noc_requests`).

---

## 22. FILE / OBJECT IMPACT

- `database/schema_slice2.sql`: Modify (Add property locks) $\rightarrow$ **FUTURE MODIFY**
- `database/schema_slice20.sql`: Create (Slice 20 schema) $\rightarrow$ **FUTURE NEW**
- `database/verify_slice20.sql`: Create (71 assertions) $\rightarrow$ **FUTURE TEST**

---

## 23. ASSERTION INVENTORY

- **Current Verified Baseline:** `639 PASS`
- **Slice 2 Remediation:** `12 Assertions` (Projected Post-Slice 2 = 651)
- **Slice 20 Rev 4.3:** `71 Assertions` (Projected Post-Slice 20 = 722)

---

## 24. REMAINING SECURITY GAPS

1. **PL/pgSQL CSPRNG Bit-Shift Integer Overflow Bug** in PIN generation (`CRITICAL BLOCKER`).
2. **Lock Order Discrepancy** between Slice 2 and Slice 20 (`PLAN CORRECTION REQUIRED`).

---

## 25. REQUIRED PLAN CORRECTIONS

1. **Fix CSPRNG PIN Generation Code:** Cast byte values to `BIGINT` before bit shifting: `(get_byte(v_bytes, 0)::bigint << 24)`.
2. **Standardize Lock Order:** Require `properties FOR UPDATE` FIRST across ALL Slice 2 and Slice 20 functions; remove `societies FOR SHARE`.
3. **Harmonize Assertion Count Metrics:** Formally document projected total as 722 assertions (639 baseline + 12 Slice 2 + 71 Slice 20).

---

## 26. FINAL AUTHORIZATION READINESS VERDICT

```text
=====================================================

SLICE 20 REVISION 4.3 — RE-VALIDATION REPORT

OVERALL VERDICT:
NOT APPROVED — PLAN CORRECTIONS REQUIRED

CURRENT VERIFIED BASELINE:
639 / 639 PASS (100%)

PROJECTED POST-REMEDIATION TARGET:
722 PASS (UNVERIFIED / PROJECTED ONLY)

SLICES 1–19:
LOCKED / IMMUTABLE

SLICE 2 FINANCIAL SERIALIZATION:
NOT IMPLEMENTED / ARCHITECTURAL DEPENDENCY

SLICE 20 IMPLEMENTATION:
NOT IMPLEMENTED / NOT AUTHORIZED

DATABASE MODIFICATIONS:
NONE

APPLICATION MODIFICATIONS:
NONE

PLAN VALIDATION:
CORRECTIONS REQUIRED BEFORE AUTHORIZATION

IMPLEMENTATION AUTHORIZATION:
NONE — IMPLEMENTATION STRICTLY PROHIBITED

=====================================================

NO IMPLEMENTATION PERFORMED.
```
