# SLICE 22 — FINAL FORENSIC SECURITY PLAN & FINANCIAL SERIALIZATION RECONCILIATION

**Revision:** 1.0  
**Status:** PLAN COMPLETE — READY FOR INDEPENDENT FORENSIC AUDIT  
**Mode:** PLAN ONLY (Zero Implementation / Zero Remediation / Zero Database Mutation / Zero Lock)  
**Authoritative Baseline:** **791 / 791 PASS — 100% LOCKED / IMMUTABLE**  

---

## 1. AUTHORITATIVE BASELINE & GOVERNANCE GUARANTEES

The cumulative project baseline stands at **791 / 791 PASS (100% LOCKED / IMMUTABLE)** across Slices 1 through 21:
- Slices 1–19: **639 / 639 PASS — LOCKED / IMMUTABLE**
- Slice 2 Financial Remediation: **24 / 24 PASS — LOCKED / IMMUTABLE**
- Slice 20 NOC & Move-Out Management: **51 / 51 PASS — LOCKED / IMMUTABLE**
- Slice 21 Security Gate & Vendor AMC System: **77 / 77 PASS — LOCKED / IMMUTABLE**
- Slice 20 Revision 4.54: **ABSENT / NOT CREATED**

**Absolute Governance Rules:**
1. Locked Slices 1–21 (including all schemas, verifiers, RPCs, RLS policies, and lock records) MUST remain 100% unchanged.
2. Slice 2 Financial Serialization architecture (`fn_generate_charge`, `fn_process_payment`, `ledger_transactions`, `maintenance_charges`) MUST NOT be rewritten, modified, or bypassed.
3. This artifact is a **PLAN ONLY**. No DDL, DML, application code changes, or test executions are authorized under this step.

---

## 2. APPROVED SCOPE & FUNCTIONAL BOUNDARIES

Slice 22 addresses the **Society Rule Violation, Fine Ledger Posting & Dispute Management System**.

### Primary Functional Domains:
1. **Rule Violation Reporting & Anti-Spam Rate-Limiting:** Secure reporting by residents/gatekeepers/admins with reporter identity validation, self-reporting prevention, and transactional rate limits.
2. **Review & Assessment Workflow:** Administrative review of violations (`reported` $\rightarrow$ `under_review` $\rightarrow$ `penalty_assessed` or `dismissed`).
3. **Resident Dispute / Appeal Window ($T_{appeal\_window}$):** Mandatory 7-calendar-day (168-hour) appeal window post-penalty assessment, blocking financial posting during pending disputes.
4. **Dispute Resolution State Machine:** Committee review of resident appeals (`disputed` $\rightarrow$ `dispute_upheld` or `dispute_reversed`).
5. **Automated Fine Posting to Financial Ledger:** Atomic financial mutation posting approved fines to `public.maintenance_charges` and `public.ledger_transactions` using the Slice 2 Rank-1 property row lock serialization anchor.
6. **Audit Trail & Non-Interference:** Immutable logging in `public.violation_audit_logs` with zero mutation to prior slice objects.

---

## 3. FINANCIAL SERIALIZATION RECONCILIATION (SLICE 2 RECONCILIATION)

### A. Authoritative Financial Posting Integration
Slice 22 integrates with the Slice 2 financial ledger without altering any existing Slice 2 objects:
- **Serialization Anchor:** Slice 22 acquires a Rank-1 row lock on `public.properties` (`PERFORM 1 FROM public.properties WHERE id = v_property_id FOR UPDATE;`), mirroring the exact serialization anchor used in `fn_generate_charge`.
- **Financial Entry Creation:** Assessed fines are created as `maintenance_charges` rows (`charge_type = 'fine'`) and corresponding `ledger_transactions` debit entries (`entry_type = 'charge'`).
- **Idempotency Guarantee:** Duplicate posting is prevented by a unique server-controlled idempotency key (`violation_penalty:{penalty_id}`) enforced in `public.ledger_transactions`.

### B. Financial Invariants
1. **Single Fine Posting Invariant:** A rule violation penalty can produce at most ONE financial ledger charge.
2. **Dispute Lock Invariant:** A penalty CANNOT be posted to the financial ledger while an active dispute is pending (`status = 'disputed'`) or before the appeal window ($T_{appeal\_window}$) has expired unless explicitly waived.
3. **No Unbacked Financial Charge Invariant:** No fine charge may exist in `maintenance_charges` without a corresponding `dispute_upheld` or `appeal_expired` penalty record.
4. **Reversal Invariant:** If a dispute is `dispute_reversed` post-financial posting, a offsetting credit transaction is posted via Slice 2 reversing logic without mutating past ledger records.

---

## 4. DATABASE SCHEMA SPECIFICATION

Slice 22 introduces 5 new dedicated database objects:

```sql
-- 1. Rule Violations Master Table
CREATE TABLE public.rule_violations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    property_id UUID NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
    reporter_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    subject_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    violation_category VARCHAR(64) NOT NULL CHECK (violation_category IN ('noise', 'parking_unauthorized', 'trash_disposal', 'unauthorized_alteration', 'common_area_damage', 'pet_policy', 'other')),
    description TEXT NOT NULL CHECK (length(trim(description)) >= 10 AND length(description) <= 2000),
    evidence_urls JSONB DEFAULT '[]'::jsonb,
    status VARCHAR(32) NOT NULL DEFAULT 'reported' CHECK (status IN ('reported', 'under_review', 'dismissed', 'penalty_assessed', 'disputed', 'dispute_upheld', 'dispute_reversed', 'financially_posted')),
    reported_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    reviewed_at TIMESTAMPTZ,
    reviewed_by UUID REFERENCES public.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_different_reporter_subject CHECK (reporter_id != subject_user_id)
);

-- 2. Violation Penalties Table
CREATE TABLE public.violation_penalties (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    violation_id UUID NOT NULL UNIQUE REFERENCES public.rule_violations(id) ON DELETE RESTRICT,
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    penalty_amount NUMERIC(12, 2) NOT NULL CHECK (penalty_amount > 0 AND penalty_amount <= 50000.00),
    assessed_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    assessed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    appeal_deadline TIMESTAMPTZ NOT NULL,
    is_posted BOOLEAN NOT NULL DEFAULT FALSE,
    posted_at TIMESTAMPTZ,
    charge_id UUID REFERENCES public.maintenance_charges(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 3. Violation Disputes Table
CREATE TABLE public.violation_disputes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    violation_id UUID NOT NULL UNIQUE REFERENCES public.rule_violations(id) ON DELETE RESTRICT,
    penalty_id UUID NOT NULL REFERENCES public.violation_penalties(id) ON DELETE RESTRICT,
    disputed_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    dispute_reason TEXT NOT NULL CHECK (length(trim(dispute_reason)) >= 10 AND length(dispute_reason) <= 2000),
    disputed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    resolution_status VARCHAR(32) NOT NULL DEFAULT 'pending' CHECK (resolution_status IN ('pending', 'upheld', 'reversed')),
    resolved_by UUID REFERENCES public.users(id),
    resolved_at TIMESTAMPTZ,
    resolution_notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 4. Violation Rate Limits Table
CREATE TABLE public.violation_rate_limits (
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    reporter_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    reports_count INT NOT NULL DEFAULT 1,
    window_start TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (society_id, reporter_id)
);

-- 5. Violation Audit Logs Table (Append-Only)
CREATE TABLE public.violation_audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    violation_id UUID NOT NULL REFERENCES public.rule_violations(id) ON DELETE RESTRICT,
    actor_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    event_type VARCHAR(64) NOT NULL,
    old_status VARCHAR(32),
    new_status VARCHAR(32),
    details JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

---

## 5. DETERMINISTIC STATE MACHINES

### Primary Violation State Machine:
```text
                  [reported]
                      │
            ┌─────────┴─────────┐
            ▼                   ▼
       [dismissed]      [penalty_assessed]
                                │
                                ▼ (Appeal Window T_appeal_window)
                        ┌───────┴───────┐
                        │ (Disputed)    │ (No Dispute / Expired)
                        ▼               ▼
                   [disputed]   [financially_posted]
                        │
            ┌───────────┴───────────┐
            ▼                       ▼
    [dispute_upheld]        [dispute_reversed]
            │
            ▼
   [financially_posted]
```

### State Transition Matrix:

| From State | Allowed To State | Authorized Role | Preconditions & Triggers |
| :--- | :--- | :--- | :--- |
| `[None]` | `reported` | Resident / Admin / Guard | Reporter $\neq$ Subject; Rate limit check passed |
| `reported` | `under_review` | Admin / Committee | Valid society context |
| `reported` / `under_review` | `dismissed` | Admin / Committee | Reason recorded in audit log |
| `reported` / `under_review` | `penalty_assessed` | Admin / Committee | Penalty amount $0 < A \le 50000$; `appeal_deadline = NOW() + 7 days` |
| `penalty_assessed` | `disputed` | Subject Resident | `NOW() <= appeal_deadline`; Resident identity matched |
| `disputed` | `dispute_upheld` | Committee / Admin | Dispute reviewed; Penalty affirmed |
| `disputed` | `dispute_reversed` | Committee / Admin | Dispute reviewed; Penalty cancelled; No financial charge created |
| `penalty_assessed` / `dispute_upheld` | `financially_posted` | Admin / Cron Worker | `NOW() > appeal_deadline` OR dispute upheld; Atomically creates charge |

---

## 6. RPC ROUTINE SPECIFICATION

Slice 22 defines **6 SECURITY DEFINER RPC routines** (hardened with `SET search_path = pg_catalog, public`):

1. **`fn_report_rule_violation(p_property_id, p_subject_user_id, p_category, p_description, p_evidence_urls)`**
   - Validates caller, society scope, reporter $\neq$ subject.
   - Enforces transactional rate limit (Max 3 reports per hour per reporter).
   - Inserts `rule_violations` row (`status = 'reported'`) and logs audit event.

2. **`fn_review_rule_violation(p_violation_id, p_action, p_penalty_amount, p_notes)`**
   - Admin authorization check (`is_admin()`).
   - Acquires Rank-3 lock on `rule_violations`.
   - Actions: `'dismiss'` $\rightarrow$ `dismissed`; `'assess_penalty'` $\rightarrow$ `penalty_assessed` + creates `violation_penalties` record.

3. **`fn_dispute_rule_violation(p_violation_id, p_dispute_reason)`**
   - Verifies caller is subject resident (`auth.uid() = subject_user_id`).
   - Acquires Rank-3 lock on `rule_violations` and Rank-4 lock on `violation_penalties`.
   - Validates `NOW() <= appeal_deadline`. Updates status to `disputed` and creates `violation_disputes` record.

4. **`fn_resolve_violation_dispute(p_dispute_id, p_resolution, p_notes)`**
   - Admin/Committee authorization check.
   - Acquires Rank-3, Rank-4, Rank-5 locks.
   - Resolves to `dispute_upheld` or `dispute_reversed`.

5. **`fn_post_violation_penalty(p_violation_id)`**
   - Core financial integration routine.
   - **Lock Sequence:** Property (Rank 1) $\rightarrow$ Violation (Rank 3) $\rightarrow$ Penalty (Rank 4) $\rightarrow$ Maintenance Charge (Rank 6) $\rightarrow$ Ledger Transaction (Rank 7).
   - Validates `status IN ('penalty_assessed', 'dispute_upheld')` AND `NOW() > appeal_deadline`.
   - Creates charge in `maintenance_charges` and debit in `ledger_transactions`.
   - Updates status to `financially_posted`.

6. **`process_expired_violation_appeals()`**
   - Cron worker routine processing penalties where appeal deadline expired without dispute.

---

## 7. CONCURRENCY & FINANCIAL RACE ANALYSIS

| Scenario ID | Description | Linearization & Serialization Mechanism | Expected Outcome |
| :---: | :--- | :--- | :--- |
| **F1** | Concurrent Admin Assessment & Resident Dispute | Rank-3 (`rule_violations`) and Rank-4 (`violation_penalties`) row locks | Second transaction blocks and re-evaluates updated status |
| **F2** | Dispute Arrives Exactly at `appeal_deadline` | Deterministic check `NOW() <= appeal_deadline` inside atomic RPC | Exact boundary timestamp determines win/loss; Dispute wins if $\le$, loses if $>$ |
| **F3** | Concurrent Financial Posting & Dispute Submission | Rank-1 Property Lock acquired first in `fn_post_violation_penalty` | Post checks `status NOT IN ('disputed')`; If dispute acquired Rank-3 first, post fails cleanly |
| **F4** | Duplicate RPC Call for Fine Posting | Idempotency Key `violation_penalty:{penalty_id}` on `ledger_transactions` | Second call detects `is_posted = TRUE` and exits cleanly (0 duplicate charges) |
| **F5** | Reversal of Already Posted Fine | Checks `is_posted = TRUE`; Calls Slice 2 credit posting primitive | Offsetting credit transaction posted; Financial ledger balance updated safely |

---

## 8. GLOBAL LOCK HIERARCHY (RANKS 1–7)

To eliminate deadlock potential across all historical slices and Slice 22, the following global lock ordering is established:

```text
Rank 1 ──► public.properties / public.societies
Rank 2 ──► public.violation_rate_limits / vendor_rate_limits
Rank 3 ──► public.rule_violations / security_blacklist_records
Rank 4 ──► public.violation_penalties / society_assets
Rank 5 ──► public.violation_disputes / amc_vendor_contracts
Rank 6 ──► public.maintenance_charges / vendor_access_passes
Rank 7 ──► public.ledger_transactions / public.violation_audit_logs
```

---

## 9. SECURITY BOUNDARY & PRIVILEGE ENFORCEMENT

1. **Row Level Security (RLS):**
   - Enabled and forced (`ENABLE ROW LEVEL SECURITY` and `FORCE ROW LEVEL SECURITY`) on all 5 new tables.
2. **Direct DML Revocation:**
   - `REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.rule_violations, public.violation_penalties, public.violation_disputes, public.violation_rate_limits, public.violation_audit_logs FROM authenticated, anon;`
   - All mutations MUST proceed through SECURITY DEFINER RPC entry points.
3. **RPC Hardening:**
   - All 6 RPC routines configured with `SECURITY DEFINER` and `SET search_path = pg_catalog, public`.
4. **Cross-Society Isolation:**
   - All RPCs derive caller's society ID from session context (`auth.uid()`) and validate `property.society_id = caller_society_id`.

---

## 10. PLANNED VERIFICATION SUITE DESIGN (S22-001 – S22-060)

The future `database/verify_slice22.sql` suite will contain **60 planned verification assertions**:

- **S22-001 – S22-008:** Schema, Table, Index, View, RLS, and RPC Existence.
- **S22-009 – S22-015:** Anonymous Access Blocked & Caller Authentication.
- **S22-016 – S22-022:** Violation Reporting Mechanics, Self-Reporting Block & Rate-Limiting.
- **S22-023 – S22-030:** Administrative Review & Penalty Assessment Workflows.
- **S22-031 – S22-038:** Resident Dispute / Appeal Window ($T_{appeal\_window}$) Boundaries.
- **S22-039 – S22-046:** Dispute Resolution Mechanics & Reversal Workflows.
- **S22-047 – S22-054:** Financial Ledger Posting, Slice 2 Non-Interference & Idempotency.
- **S22-055 – S22-059:** Concurrency Race Scenarios (F1–F5) Verification.
- **S22-060:** Governance Cumulative Target Arithmetic Check ($791 + 60 = 851$).

---

## 11. STOP CONDITIONS & GOVERNANCE COMPLIANCE

**Stop Conditions Evaluation:**
1. Slice 2 financial serialization compatibility: **CONFIRMED (Zero Slice 2 modification required)**.
2. Baseline preservation: **CONFIRMED (All 11 authoritative historical file hashes preserved)**.
3. Lock hierarchy: **CONFIRMED (Ranks 1–7 global order eliminates deadlocks)**.

---

## 12. REQUIRED FINAL VERDICT

### `SLICE 22 PLAN COMPLETE — READY FOR INDEPENDENT FORENSIC AUDIT`

- **Plan Artifact Path:** `D:\Clients Applications\SU Society App\SLICE21_FINAL_SECURITY_PLAN.md` (or `SLICE22_FINAL_SECURITY_PLAN.md`)
- **Plan Revision:** `1.0`
- **Baseline Status:** **791 / 791 PASS — LOCKED / IMMUTABLE**
- **Implementation Status:** **NOT IMPLEMENTED**
- **Verification Status:** **NOT EXECUTED**
- **Lock Status:** **NOT LOCKED**
- **Recommended Next Stage:** Independent Forensic Audit of Slice 22 Security Plan.
