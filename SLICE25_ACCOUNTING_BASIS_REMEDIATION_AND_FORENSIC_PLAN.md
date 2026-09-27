# SLICE 25 — ACCOUNTING BASIS REMEDIATION & FORENSIC SECURITY PLAN
**TARGET REPOSITORY:** `D:\Clients Applications\SU Society App`  
**TARGET SUPABASE PROJECT:** `fsegpxqoozxmicxcxjun` (Region: `ap-south-1`, PostgreSQL `17.6.1.166`)  
**CURRENT REMOTE BOUNDARY:** `20260912000024_slice24.sql`  
**ACCOUNTING BASIS:** **ACCRUAL BASIS (HUMAN DECISION AUTHORIZED)**  
**EXECUTION MODE:** PLAN REMEDIATION ONLY  

---

## 1. HUMAN DECISION RECORD
- **Human Decision Received:** **OPTION B — ACCRUAL BASIS AUTHORIZED**
- **Authorization Boundary:** Human Accounting Basis Selection ONLY. (Does NOT authorize implementation, deployment, migration execution, governance closure, or security lock).
- **Impact on Financial Reporting Model:** Financial statements will recognize revenue when earned/billed (regardless of cash collection) and expenses when incurred/posted (regardless of payment settlement).

---

## 2. IMMUTABLE BASELINE VERIFICATION

The locked baselines for Slices 21 through 24 remain 100% immutable and verified:
- **Slice 21 Lock SHA-256:** `C8F5E8742CA04391AC51889AD671CD9868710F7C5AB6CC6A9C39C84BCAF16912` — **VERIFIED MATCH**
- **Slice 22 Lock SHA-256:** `BADDA60288021729D4E46A38642ECBBAB3C89EDDCC3A8BCC603EAA6A9B36C3C7` — **VERIFIED MATCH**
- **Slice 23 Lock SHA-256:** `C05F5DB093A2C013E2C14B02CFDBAE0AF2C356935F8B4CABBEBEE720C6CB3D6E` — **VERIFIED MATCH**
- **Slice 23 Migration SHA-256:** `0231E69F903D3C82F273B7896B29A087D9ABA1CFA928487B6F330881F9236740` — **VERIFIED MATCH**
- **Slice 24 Lock SHA-256:** `E1B206D4F3D6149E3255D467B1ABCDA9F469E5A8730F8333C5E75E2F999AA5C9` — **VERIFIED MATCH**
- **Current Remote Migration Boundary:** `20260912000024_slice24.sql` — **VERIFIED**

---

## 3. MANDATORY ACCOUNTING SEMANTICS ANALYSIS (ACCRUAL BASIS)

Forensic evaluation of `database/schema_phase2.sql` and `PHASE_3B_SPECIFICATION.md` establishes the recognition rules for all 17 financial events:

| # | Accounting Event / Category | Accrual Recognition Rule & Event Trigger | Authoritative Evidence | Classification |
| :--- | :--- | :--- | :--- | :--- |
| **1** | **Maintenance Revenue** | Recognized when `maintenance_charges` record is created and posted as a `charge` transaction (`scope = 'member'`, `direction = 'debit'`) in `ledger_transactions`. | `schema_phase2.sql` lines 73–144 | **A — Explicitly Established** |
| **2** | **Fine Revenue** | Recognized when fine transaction (`transaction_type = 'penalty'`, `scope = 'member'`, `direction = 'debit'`) is posted to `ledger_transactions`. | `schema_phase2.sql` lines 108–144 | **A — Explicitly Established** |
| **3** | **Penalty Revenue** | Recognized when penalty transaction (`transaction_type = 'penalty'`) is posted to `ledger_transactions`. | `schema_phase2.sql` lines 108–144 | **A — Explicitly Established** |
| **4** | **Utility-Fee Revenue** | Recognized when custom billing charge (`billing_subject_type = 'custom'`, `transaction_type = 'charge'`) is generated and posted to `ledger_transactions`. | `schema_phase2.sql` lines 44–71, 73–144 | **A — Explicitly Established** |
| **5** | **Amenity-Fee Revenue** | Recognized when amenity booking is approved and amenity fee (`transaction_type = 'amenity_fee'` or `'charge'`) is posted via `approve_amenity_booking`. | `schema_phase2.sql` lines 735–770, `PHASE_3B_SPECIFICATION.md` | **B — Deterministically Derivable** |
| **6** | **Expense Recognition** | Recognized when `expense_vouchers` entry is approved (`status = 'approved'`/`'posted'`) and posted as a `society` scope credit (`transaction_type = 'expense'`). | `schema_phase2.sql` lines 963–1026 | **A — Explicitly Established** |
| **7** | **Unpaid Member Dues** | Billed charges not yet paid sit in **Accounts Receivable** asset account on Balance Sheet. Recognized as revenue in P&L for period billed. | Accrual double-entry ledger logic | **B — Deterministically Derivable** |
| **8** | **Unpaid Fines / Penalties** | Recognized as P&L revenue when assessed; uncollected balance sits in Accounts Receivable asset account. | Accrual double-entry ledger logic | **B — Deterministically Derivable** |
| **9** | **Unpaid Utility/Amenity** | Recognized as P&L revenue when billed; uncollected balance sits in Accounts Receivable asset account. | Accrual double-entry ledger logic | **B — Deterministically Derivable** |
| **10** | **Prepaid Amounts / Advance** | Posted as `transaction_type = 'advance_payment'`, `scope = 'member'`, `direction = 'credit'`. Treated as **Liability (Advance Member Collections)** on Balance Sheet until allocated. | `schema_phase2.sql` lines 586–616 | **A — Explicitly Established** |
| **11** | **Receivables Treatment** | `Accounts Receivable = Total Member Debits (Charges, Penalties, Refunds) - Total Member Credits (Payments, Waivers, Advances)`. Asset on Balance Sheet. | Accrual double-entry ledger logic | **B — Deterministically Derivable** |
| **12** | **Liabilities Treatment** | `Total Liabilities = Advance Member Collections + Vendor Payables + Security Deposits Held`. | `schema_phase2.sql` payment & expense vouchers | **B — Deterministically Derivable** |
| **13** | **Opening Balances** | Member opening balances are booked via `trigger_book_opening_balance_in_ledger` as `transaction_type = 'adjustment'`, `scope = 'member'`. Included in opening receivables/equity. | `schema_phase2.sql` lines 146–157, 312–365 | **A — Explicitly Established** |
| **14** | **Historical Ledger Entries** | Immutable (`prevent_ledger_mutations` trigger). Evaluated based on immutable `transaction_date` / `created_at`. | `schema_phase2.sql` lines 278–310 | **A — Explicitly Established** |
| **15** | **Period Boundaries** | Evaluated using `TIMESTAMPTZ` boundaries `[p_start_date, p_end_date]` with inclusive upper bound `p_end_date AT TIME ZONE 'UTC'`. | Date boundary semantics | **B — Deterministically Derivable** |
| **16** | **Reversals & Adjustments** | Posted as compensating ledger entries (`transaction_type IN ('reversal', 'adjustment', 'waiver')`), acting as contra-revenue or contra-expense. | `schema_phase2.sql` ledger direction triggers | **A — Explicitly Established** |
| **17** | **Authoritative Recognition Date** | `ledger_transactions.transaction_date` (DATE) / `created_at` (TIMESTAMPTZ) serves as the primary recognition date filter for reporting periods. | `schema_phase2.sql` line 126 | **A — Explicitly Established** |

**Summary of Recognition Event Status:**  
- Category A (Explicitly Established): **10 items**  
- Category B (Deterministically Derivable): **7 items**  
- Category C (Still Requiring Human Decision): **0 items (ZERO UNRESOLVED DECISIONS)**  

---

## 4. BAD-DEBT POLICY
- **Policy:** Uncollected dues remain active receivables. No automatic write-off or silent deletion.
- **Evidence:** `prevent_ledger_mutations` trigger (`schema_phase2.sql` lines 278–310) prevents altering or deleting ledger entries.
- **Enforcement:** Bad debts require explicit, authorized compensating ledger transactions (`transaction_type = 'waiver'` or `'adjustment'`). Slice 25 RPCs will generate statements purely read-only without modifying receivable records.

---

## 5. OPENING-BALANCE POLICY
- **Policy:** `opening_balances` mechanism is authoritative and immutable.
- **Evidence:** `schema_phase2.sql` lines 146–157, 312–365 (`trigger_book_opening_balance_in_ledger` and `trigger_prevent_opening_balance_mutations`).
- **Enforcement:** Opening balances are booked into `ledger_transactions` upon insertion as `adjustment` entries and included in financial statement aggregations based on their direction (`debit` = initial member receivable, `credit` = initial member advance/prepaid).

---

## 6. FINANCIAL STATEMENT SPECIFICATIONS (ACCRUAL BASIS)

### A. TRIAL BALANCE (`fn_get_trial_balance`)
- **Objective:** Verify double-entry ledger balance ($\sum \text{Debits} = \sum \text{Credits}$).
- **Parameters:** `p_society_id UUID`, `p_as_of_date TIMESTAMPTZ`.
- **Logic:**
  1. Aggregates all posted ledger transactions up to `p_as_of_date` for `p_society_id`.
  2. Groups by account / transaction type.
  3. Calculates total debit sum and total credit sum.
  4. Returns balanced account summary table.
  5. Enforces zero ledger mutation and strict tenant isolation.

### B. PROFIT & LOSS STATEMENT (`fn_get_profit_and_loss_statement`)
- **Objective:** Calculate net operating surplus or deficit under Accrual Basis.
- **Parameters:** `p_society_id UUID`, `p_start_date TIMESTAMPTZ`, `p_end_date TIMESTAMPTZ`.
- **Revenue Categories (Earned/Billed):**
  - Maintenance Dues (`transaction_type = 'charge'`)
  - Fines & Penalties (`transaction_type = 'penalty'`)
  - Utility Charges (`billing_subject_type = 'custom'`, `transaction_type = 'charge'`)
  - Amenity Fees (`transaction_type = 'amenity_fee'`)
  - Less: Waivers & Adjustments (`transaction_type = 'waiver'`)
- **Expense Categories (Incurred/Approved):**
  - Approved Expense Vouchers (`transaction_type = 'expense'`, `status IN ('approved', 'posted')`)
  - Operating & Maintenance Expenses
- **Calculation:** $\text{Net Surplus / Deficit} = \text{Total Accrued Income} - \text{Total Accrued Expenses}$.

### C. BALANCE SHEET (`fn_get_balance_sheet`)
- **Objective:** Present society financial position as of `p_as_of_date`.
- **Parameters:** `p_society_id UUID`, `p_as_of_date TIMESTAMPTZ`.
- **Assets:**
  - Cash & Bank Accounts (Society-scope ledger debits minus credits)
  - Accounts Receivable (Uncollected member charges, penalties, utilities)
- **Liabilities:**
  - Advance Member Collections (Unallocated member `advance_payment` credits)
  - Accounts Payable (Approved expense vouchers pending cash payout)
- **Equity:**
  - Historical Opening Balance Equity
  - Retained Surplus/Deficit (Prior periods P&L accumulation)
  - Current Period Surplus/Deficit (P&L net result up to `p_as_of_date`)
- **Accounting Invariant:** $\text{Total Assets} = \text{Total Liabilities} + \text{Total Equity}$.

---

## 7. SECURITY & MULTI-TENANT HARDENING MODEL

All three statement RPCs must implement the following mandatory controls:
1. `SECURITY DEFINER` ownership.
2. Fixed search path: `SET search_path = pg_catalog, public, pg_temp;`.
3. Explicit schema qualification (`public.ledger_transactions`, `public.payments`, etc.).
4. Privilege Revocation: REVOKE `EXECUTE` ON FUNCTION from `PUBLIC` and `anon`.
5. Privilege Grant: GRANT `EXECUTE` ON FUNCTION strictly to `authenticated`.
6. Inline `auth.uid()` identity validation.
7. Role Check: Validate caller role against `public.user_roles` for canonical roles (`admin`, `super_admin`, `treasurer`).
8. Strict Tenant Isolation: Enforce `society_id = p_society_id` on all subqueries; reject unauthorized callers with `403 Forbidden`.
9. Concurrency / Snapshot Consistency: Execute inside PostgreSQL transaction block with `READ COMMITTED` or `REPEATABLE READ` snapshot isolation to guarantee deterministic, un-skewed reporting.

---

## 8. THREAT-VECTOR RECONCILIATION
*(Original: 20 | Previously Added: 2 | New Accrual Threats: 2 | Total: 24)*

- **TV25-01 to TV25-20:** Authentication, multi-tenancy, parameter validation, RLS, and ledger integrity threats.
- **TV25-21:** Revenue Recognition Mismatch (Cash vs. Accrual collision).
- **TV25-22:** Balance Sheet Imbalance from Unallocated Historical Opening Equity.
- **TV25-23 (NEW):** Accrual Revenue Duplication — Double counting billed maintenance charges and verified cash payments. *(Mitigation: Exclude payment credits from P&L revenue under Accrual Basis; payments affect Cash/AR only)*.
- **TV25-24 (NEW):** Unlinked Custom Billing Subject Mismatch in Accrual Income Aggregation. *(Mitigation: Schema-qualified join on `custom_billing_subjects`)*.

---

## 9. ASSERTION RECONCILIATION
*(Original: 50 | Previously Added: 2 | New Accrual Assertions: 2 | Total: 54)*

- **S25-001 to S25-050:** Schema, permissions, trial balance equality, P&L surplus calculation, and balance sheet equation validation.
- **S25-051:** `fn_get_profit_and_loss_statement` respects cash/accrual policy.
- **S25-052:** `fn_get_balance_sheet` verifies opening balance equity reconciliation.
- **S25-053 (NEW):** `fn_get_profit_and_loss_statement` recognizes maintenance revenue on charge billing date rather than payment date under Accrual Basis.
- **S25-054 (NEW):** `fn_get_balance_sheet` dynamically verifies $\text{Accounts Receivable} = \text{Total Billed Charges} - \text{Total Payments Applied}$.

---

## 10. GOVERNANCE CLASSIFICATION

**CLASSIFICATION A — FORENSIC PLAN REMEDIATED AND APPROVED FOR FUTURE LOCAL IMPLEMENTATION AUTHORIZATION**

---

## 11. EXACT NEXT GOVERNANCE GATE

**EXPLICIT HUMAN LOCAL IMPLEMENTATION AUTHORIZATION FOR SLICE 25**

---

### MANDATORY GOVERNANCE STATEMENTS
- **NO SLICE 25 IMPLEMENTATION EXECUTED.**
- **NO MIGRATION CREATED.**
- **NO DATABASE MUTATION PERFORMED.**
- **NO REMOTE DEPLOYMENT.**
- **SLICES 21–24 REMAIN IMMUTABLE AND UNTOUCHED.**
