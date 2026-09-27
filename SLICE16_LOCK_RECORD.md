# SLICE 16 LOCK RECORD

**Slice Title:** Slice 16 — Society Governance, Board Resolutions, Budget Approval Engine & Facility Blackout Workflows  
**Lock Status:** **LOCKED / IMMUTABLE**  
**Lock Date:** September 4, 2026  
**Auditor / System:** Antigravity Security Research Group  
**Security Verdict:** **SECURE**  

---

## 1. VERIFICATION SUMMARY & ASSERTION RECONCILIATION

```
Locked Baseline (Slices 1–15): 434 / 434 PASS (100%)
Slice 16 Assertions:           32 / 32 PASS (100%)
--------------------------------------------------
FINAL CUMULATIVE SCORE:        466 / 466 PASS (100%)
```

Pre-lock verification executed successfully against PostgreSQL (`supabase_db_SU_Society_App`) on September 4, 2026. Zero failures, zero regressions.

---

## 2. IMMUTABLE BASELINE PRESERVATION

Slices 1–15 remain completely untouched, immutable, and preserved:
- `database/schema_slice1.sql` through `database/schema_slice15.sql`: **UNTOUCHED / IMMUTABLE**
- `database/verify_slice1.sql` through `database/verify_slice15.sql`: **UNTOUCHED / IMMUTABLE**
- `scratch/run_all1.ps1` through `scratch/run_all15.ps1`: **UNTOUCHED / IMMUTABLE**
- Baseline score: **434 / 434 PASS (100%)**

---

## 3. AUDITED FILES & REPOSITORY INTEGRITY EVIDENCE

The locked Slice 16 implementation consists strictly of the following audited artifacts:

| File Path | Description | SHA-256 Hash |
|---|---|---|
| `database/schema_slice16.sql` | DDL, tables, constraints, RLS policies, triggers, 8 SECURITY DEFINER procedures | `7BC0488AAB7D91047C69600E59DD361274A0B9A1A637D9F919BF4EA021707708` |
| `database/verify_slice16.sql` | 32 executable SQL security & state machine assertions | `E630271C459EEF63B4E39AE378A23D8FA4E740E747FA99B988C8D3E8E5C0D62C` |
| `scratch/run_all16.ps1` | Master regression runner for Slices 1–16 | `77EDFABA3886985B5DE6763C19B214F1CDBA2AF9220744737F410986B2637F8D` |

---

## 4. DATABASE OBJECTS INTRODUCED

### A. Schema Tables (6)
1. `public.committee_resolutions`: State machine for board resolutions (`draft` -> `voting` -> `passed` / `rejected`).
2. `public.committee_resolution_votes`: Votes registry with `uq_resolution_voter UNIQUE (resolution_id, voter_id)` and `chk_vote_value CHECK (vote_value IN ('for', 'against', 'abstain'))`.
3. `public.society_budgets`: Society fiscal budget master table with `uq_society_fiscal_year UNIQUE (society_id, fiscal_year)`.
4. `public.budget_line_items`: Budget allocations with `chk_allocated_positive CHECK (allocated_amount > 0)`.
5. `public.expense_vouchers`: Expense reimbursement vouchers linked to budget line items with `chk_voucher_status CHECK (status IN ('pending', 'approved', 'rejected', 'disbursed'))`.
6. `public.facility_blackouts`: Amenity maintenance blackouts with `chk_blackout_times CHECK (start_time < end_time)`.

### B. Security Policies & Triggers
- **FORCE ROW LEVEL SECURITY:** Enabled and forced on all 6 Slice 16 tables.
- **RESTRICTIVE RLS Policies:**
  - `pol_resolutions_restrictive_update` ON `committee_resolutions` `AS RESTRICTIVE FOR UPDATE TO authenticated USING (false) WITH CHECK (false)`
  - `pol_budgets_restrictive_update` ON `society_budgets` `AS RESTRICTIVE FOR UPDATE TO authenticated USING (false) WITH CHECK (false)`
  - `pol_vouchers_restrictive_update` ON `expense_vouchers` `AS RESTRICTIVE FOR UPDATE TO authenticated USING (false) WITH CHECK (false)`
  - `pol_blackouts_restrictive_update` ON `facility_blackouts` `AS RESTRICTIVE FOR UPDATE TO authenticated USING (false) WITH CHECK (false)`
- **BEFORE UPDATE GUC-Binding Triggers:**
  - `trg_prevent_direct_resolution_update` calling `fn_prevent_direct_resolution_update()`
  - `trg_prevent_direct_budget_update` calling `fn_prevent_direct_budget_update()`
  - `trg_prevent_direct_voucher_update` calling `fn_prevent_direct_voucher_update()`
  - `trg_prevent_direct_blackout_update` calling `fn_prevent_direct_blackout_update()`

### C. Hardened Stored Procedures (8 SECURITY DEFINER Routines)
1. `public.table_resolution(p_resolution_id UUID)`
2. `public.vote_on_resolution(p_resolution_id UUID, p_vote_value TEXT, p_comments TEXT)`
3. `public.close_resolution_voting(p_resolution_id UUID)`
4. `public.submit_society_budget(p_budget_id UUID)`
5. `public.approve_society_budget(p_budget_id UUID)`
6. `public.approve_expense_voucher(p_voucher_id UUID)`
7. `public.disburse_expense_voucher(p_voucher_id UUID)`
8. `public.cancel_facility_blackout(p_blackout_id UUID, p_reason TEXT)`

All 8 procedures are configured with `SECURITY DEFINER`, `SET search_path = public, pg_temp`, `proowner = postgres`, `REVOKE EXECUTE ON FUNCTION FROM PUBLIC`, and `GRANT EXECUTE ON FUNCTION TO authenticated`.

---

## 5. LOCKED SECURITY INVARIANTS

### Resolution & Voting Invariants
- **State Machine:** `draft` -> `voting` -> `passed` / `rejected`. State skipping or post-terminal mutation strictly prevented.
- **Server-Side Tallying:** Quorum verification (`COUNT(*) >= quorum_required`) and vote tallying (`votes_for > votes_against`) calculated server-side in `close_resolution_voting`. Direct mutation of tally columns blocked by RESTRICTIVE RLS.
- **Duplicate Vote Prevention:** Database constraint `uq_resolution_voter` blocks multiple votes by the same user.
- **Voter Identity Binding:** `voter_id` implicitly bound to `auth.uid()`.
- **Tenant Isolation:** Committee membership validated via `user_roles` matching `society_id`. Cross-society calls raise `42501`.

### Budget & Financial Integrity Invariants
- **Budget Lifecycle:** `draft` -> `submitted` -> `approved`. Submitting empty budgets raises `22000`.
- **Fiscal Year Uniqueness:** `uq_society_fiscal_year` enforces unique budgets per society/year.
- **Disbursement Protection:** `disburse_expense_voucher` locks `budget_line_items` with `SELECT FOR UPDATE` and validates `spent_amount + voucher.amount <= allocated_amount`. Over-budget disbursement raises `22000`.
- **Atomic Ledger Integration:** Successful disbursement generates an atomic credit entry in `ledger_transactions` (`scope = 'society'`, `transaction_type = 'expense'`, `direction = 'credit'`). Failed disbursements roll back atomically, creating 0 ledger entries and leaving `spent_amount` unchanged.
- **Currency & Precision Integrity:** Inherited from Slice 14 decimal structures.

### Facility Blackout Invariants
- **Blackout State Machine:** `scheduled` / `active` -> `cancelled`.
- **Time Window Validation:** `chk_blackout_times CHECK (start_time < end_time)` prevents invalid time windows.
- **Cancellation Audit:** Cancellation appends reason and logs audit event.

### Database Architecture & GUC Defense-in-Depth
- **FORCE RLS:** Enabled and forced on all tables.
- **RESTRICTIVE RLS:** Direct client SQL `UPDATE` operations evaluate `USING (false)` and are unconditionally blocked.
- **GUC Target-ID Binding:** Triggers validate `current_setting('app.*_workflow_context', true) = NEW.id::text`. GUC settings provide defense-in-depth within trusted procedures and cannot be forged by authenticated client queries to bypass RLS.
- **Catalog Hardening:** All procedures run under `SET search_path = public, pg_temp`, `proowner = postgres`, with `PUBLIC EXECUTE` revoked.

### Audit & Notification Integrity
- Every state transition logs an immutable audit record to `public.audit_logs`.
- Required notifications emitted to `public.notifications`.
- Failed transactions roll back entirely, leaving zero orphaned audit records or partial financial mutations.

---

## 6. FINAL LOCK CONFIRMATION

Slice 16 implementation is hereby **LOCKED and IMMUTABLE**.

No further modifications, refactorings, optimizations, or schema alterations may be performed on Slices 1–16 without a formal change authorization.

```
SLICE 16 — LOCKED
FINAL VERIFIED SCORE: 466 / 466 PASS (100%)
SECURITY STATUS: SECURE
```
