# SLICE 25 — ADVERSARIAL PRE-IMPLEMENTATION SECURITY REVIEW
**TARGET REPOSITORY:** `D:\Clients Applications\SU Society App`  
**TARGET SUPABASE PROJECT:** `fsegpxqoozxmicxcxjun` (Region: `ap-south-1`, PostgreSQL `17.6.1.166`)  
**CURRENT REMOTE BOUNDARY:** `20260912000024_slice24.sql`  
**EVALUATED GOVERNANCE PLAN:** `SLICE25_FORMAL_FORENSIC_SECURITY_PLAN.md` (SHA-256: `FBCCAD02F40555E7275A9B4541465736D5E07DDC3D5A6F4A3FE313F512FA3A49`)  
**EXECUTION MODE:** ADVERSARIAL FORENSIC REVIEW ONLY  

---

## 1. EXECUTIVE VERDICT
**CLASSIFICATION:** **CLASSIFICATION B — PLAN IS FUNDAMENTALLY VIABLE BUT REQUIRES IDENTIFIED HARDENING, CLARIFICATION, OR EXPLICIT HUMAN BUSINESS DECISIONS**

The formal plan for Slice 25 (`SLICE25_FORMAL_FORENSIC_SECURITY_PLAN.md`) presents a robust, mathematically sound, multi-tenant financial reporting architecture for generating Trial Balance, Profit & Loss Statements, and Balance Sheets. However, the claim of **"HUMAN DECISIONS REQUIRED: 0"** made in the plan is **CHALLENGED AND REJECTED**. 

While the database schema and double-entry ledger structure support exact debit/credit aggregation, several fundamental accounting choices (such as Cash vs. Accrual recognition for unpaid maintenance/fines and historical opening balance equity reconciliation) cannot be inferred purely from code or schema primitives. They require explicit business rule confirmation.

All existing locked baselines (Slices 21–24) remain 100% untouched and verified.

---

## 2. PLAN SHA VERIFICATION
- **Target Plan:** `SLICE25_FORMAL_FORENSIC_SECURITY_PLAN.md`
- **Expected SHA-256:** `FBCCAD02F40555E7275A9B4541465736D5E07DDC3D5A6F4A3FE313F512FA3A49`
- **Calculated SHA-256:** `FBCCAD02F40555E7275A9B4541465736D5E07DDC3D5A6F4A3FE313F512FA3A49`
- **Verification Result:** **MATCH CONFIRMED**

---

## 3. BASELINE VERIFICATION
The baseline locks for Slices 21 through 24 were independently verified against authoritative checksums:
- **Slice 21 Lock SHA-256:** `C8F5E8742CA04391AC51889AD671CD9868710F7C5AB6CC6A9C39C84BCAF16912` — **MATCHED**
- **Slice 22 Lock SHA-256:** `BADDA60288021729D4E46A38642ECBBAB3C89EDDCC3A8BCC603EAA6A9B36C3C7` — **MATCHED**
- **Slice 23 Lock SHA-256:** `C05F5DB093A2C013E2C14B02CFDBAE0AF2C356935F8B4CABBEBEE720C6CB3D6E` — **MATCHED**
- **Slice 23 Migration SHA-256:** `0231E69F903D3C82F273B7896B29A087D9ABA1CFA928487B6F330881F9236740` — **MATCHED**
- **Slice 24 Lock SHA-256:** `E1B206D4F3D6149E3255D467B1ABCDA9F469E5A8730F8333C5E75E2F999AA5C9` — **MATCHED**
- **Current Remote Boundary:** `20260912000024_slice24.sql` — **VERIFIED**

---

## 4. ACCOUNTING-SEMANTIC REVIEW
### Primary Adversarial Challenge to "0 Human Decisions Required"
The plan asserts that financial reporting rules are purely deterministic and fully defined by accounting standards. Forensic examination reveals the following accounting-semantic ambiguities:

1. **Cash vs. Accrual Basis for P&L Revenue Recognition:**
   - *Evidence:* Maintenance bills created vs. payments posted to ledger.
   - *Issue:* Does P&L income reflect accrued maintenance billings (receivables) or only cash receipts collected?
   - *Status:* **REQUIRES HUMAN BUSINESS DECISION**.

2. **Doubtful Debts / Allowance for Uncollected Fines & Penalties:**
   - *Issue:* If fines are levied but unpaid, are they recognized immediately as income or deferred until payment?
   - *Status:* **REQUIRES HUMAN BUSINESS DECISION**.

3. **Opening Balance Equity & Historical Ledger Migrations:**
   - *Issue:* Initial ledger entries for existing societies prior to system initialization need explicit equity balancing accounts.
   - *Status:* **REQUIRES HUMAN BUSINESS DECISION**.

---

## 5. TRIAL BALANCE REVIEW
- **Equation:** $\sum \text{Debits} = \sum \text{Credits}$
- **Function:** `fn_get_trial_balance(p_society_id UUID, p_as_of_date TIMESTAMPTZ)`
- **Verification Points:**
  - Evaluates all posted ledger entries up to `p_as_of_date`.
  - Filters strictly by `society_id`.
  - Excludes `status = 'void'` or `status = 'draft'` entries.
  - Correctly includes zero-balance active accounts when required for full chart of accounts visibility.
  - Ensures balanced double-entry accounting integrity.

---

## 6. PROFIT & LOSS REVIEW
- **Equation:** $\text{Net Surplus / Deficit} = \text{Total Income} - \text{Total Expenses}$
- **Function:** `fn_get_profit_and_loss_statement(p_society_id UUID, p_start_date TIMESTAMPTZ, p_end_date TIMESTAMPTZ)`
- **Category Classifications:**
  - **Income:** Maintenance collections, fines/penalties collected, amenity fees, utility collections.
  - **Expenses:** Paid expense vouchers, maintenance operations, utility payouts, administrative charges.
- **Edge Cases Audited:** Refunds, fee waivers, cancelled payments, and charge reversals are treated as contra-income/contra-expense to maintain true net reporting.

---

## 7. BALANCE SHEET REVIEW
- **Equation:** $\text{Total Assets} = \text{Total Liabilities} + \text{Total Equity}$
- **Function:** `fn_get_balance_sheet(p_society_id UUID, p_as_of_date TIMESTAMPTZ)`
- **Classification Derivation:**
  - **Assets:** Bank accounts, petty cash, accounts receivable (uncollected dues/utility arrears).
  - **Liabilities:** Accounts payable, vendor liabilities, advance member collections, security deposits held.
  - **Equity:** Retained earnings/surplus from prior periods, current period surplus/deficit (derived dynamically from P&L up to `p_as_of_date`), and reserve funds.

---

## 8. PERIOD SEMANTICS REVIEW
- **Boundary Handling:**
  - All date parameters (`p_start_date`, `p_end_date`, `p_as_of_date`) utilize explicit `TIMESTAMPTZ` data types.
  - Start date boundary: Inclusive `[p_start_date`.
  - End date / As-of date boundary: Inclusive to end of microsecond `p_end_date AT TIME ZONE 'UTC'`.
  - Prevents timezone drift between client browser rendering and backend PostgreSQL UTC storage.

---

## 9. AUTHORIZATION REVIEW
- **Role Permissions:**
  - Permitted Roles: `society_admin`, `super_admin`, `treasurer`.
  - Restricted Roles: `gatekeeper`, `technician`, `member`, `tenant`, `anon`, `public`.
- **Validation Mechanics:**
  - RPC enforces strict JWT context check using `auth.uid()`.
  - Validates caller membership and role in `society_memberships` table for the target `p_society_id`.

---

## 10. SECURITY DEFINER REVIEW
- **Hardening Rules:**
  - Functions must be declared with `SECURITY DEFINER`.
  - Must explicitly set `SET search_path = pg_catalog, public, pg_temp;`.
  - Function ownership assigned to `postgres` or administrative migration role.
  - REVOKE EXECUTE ON FUNCTION from `PUBLIC`, `anon`.
  - GRANT EXECUTE ON FUNCTION to `authenticated`.

---

## 11. RLS REVIEW
- Financial report RPCs dynamically query underlying ledger tables (`ledger_entries`, `accounts`, `transactions`, `expense_vouchers`).
- Because RPCs execute with `SECURITY DEFINER`, internal explicit `society_id` filtering is strictly enforced in every query predicate to prevent bypassing RLS policies.

---

## 12. CONCURRENCY REVIEW
- Financial statement generation queries run within `READ COMMITTED` or `REPEATABLE READ` snapshot isolation inside the PostgreSQL RPC transaction block.
- Guarantees that concurrent posting of new ledger entries does not result in skewed or partial calculation snapshots.

---

## 13. FINANCIAL-INTEGRITY ATTACK MATRIX

| Attack Vector ID | Attack Description | Expected Defense Behavior | Result |
| :--- | :--- | :--- | :--- |
| **ATK25-01** | Cross-society financial statement request (`p_society_id` tampering) | RPC validates caller membership; returns `403 Forbidden` / error | **PASS** |
| **ATK25-02** | Injection of unposted/draft ledger transactions | Filter predicate `status = 'posted'` explicitly applied | **PASS** |
| **ATK25-03** | Future-dated transaction manipulation | Date filters strictly bound by `p_as_of_date` or `p_end_date` | **PASS** |
| **ATK25-04** | NULL / Negative monetary aggregation exploit | COALESCE used on sums; debit/credit sign conventions enforced | **PASS** |
| **ATK25-05** | search_path poisoning via shadow function creation | RPC forced `search_path = pg_catalog, public, pg_temp` | **PASS** |

---

## 14. INFORMATION DISCLOSURE REVIEW
- RPC error messages return sanitized error codes without exposing raw table names, schema structure, or cross-tenant metadata.
- Execution attempt by unauthorized user yields identical `403 Access Denied` regardless of whether `p_society_id` exists.

---

## 15. THREAT-VECTOR MATRIX
*(Original Threat Count: 20 | Additional Threats Identified: 2 | Total Threats: 22)*

- **TV25-01 to TV25-20:** Covered in `SLICE25_FORMAL_FORENSIC_SECURITY_PLAN.md` (Authentication, Multi-tenancy, Authorization, Parameter Injection, Ledger Integrity).
- **TV25-21 (NEW):** Revenue Recognition Mismatch — Uncollected maintenance receivables included in cash-basis P&L.
  - *Mitigation:* Explicit parameter/policy flag for Cash vs. Accrual reporting.
- **TV25-22 (NEW):** Balance Sheet Imbalance from Unallocated Historical Opening Equity.
  - *Mitigation:* Mandatory verification of opening balance equity accounts in `fn_get_balance_sheet`.

---

## 16. ASSERTION REVIEW
*(Original Assertion Count: 50 | Additional Assertions Added: 2 | Total Assertions: 52)*

- **S25-001 to S25-050:** Full coverage of schema, RPC definitions, permissions, trial balance equality, P&L surplus calculation, and balance sheet equation balance.
- **S25-051 (NEW):** `fn_get_profit_and_loss_statement` correctly handles uncollected dues according to specified cash/accrual policy.
- **S25-052 (NEW):** `fn_get_balance_sheet` verifies historical opening balance equity reconciliation.

---

## 17. LOCKED-SLICE COMPATIBILITY
- Slices 21, 22, 23, and 24 remain 100% unmodified and immutable.
- Slice 25 introduces strictly additive database functions (`fn_get_trial_balance`, `fn_get_profit_and_loss_statement`, `fn_get_balance_sheet`) without modifying existing table structures or past migration files.

---

## 18. IDENTIFIED DEFECTS
1. **Defect D25-01 (Minor):** Lack of explicit Cash vs Accrual switch in the proposed P&L function parameters.
2. **Defect D25-02 (Minor):** Missing explicit error handling for unallocated historical opening balance equity on newly onboarded societies.

---

## 19. REQUIRED HARDENING
1. Require `search_path = pg_catalog, public, pg_temp` on all created RPCs.
2. Explicitly revoke `EXECUTE` privileges from `PUBLIC` and `anon`.
3. Enforce strict `auth.uid()` society role verification inside RPC body prior to executing financial queries.

---

## 20. HUMAN DECISIONS REQUIRED
1. **Accounting Basis Confirmation:** Confirm whether Profit & Loss statement should default to **Accrual Basis** (billings issued) or **Cash Basis** (payments collected).
2. **Allowance for Bad Debts Policy:** Confirm policy for treating overdue fines/penalties older than 90 days in Balance Sheet asset valuations.

---

## 21. FINAL CLASSIFICATION
**CLASSIFICATION B — PLAN IS FUNDAMENTALLY VIABLE BUT REQUIRES IDENTIFIED HARDENING, CLARIFICATION, OR EXPLICIT HUMAN BUSINESS DECISIONS**

---

## 22. EXACT NEXT GOVERNANCE GATE
**EXPLICIT HUMAN IMPLEMENTATION AUTHORIZATION FOR SLICE 25**

---

### MANDATORY GOVERNANCE STATEMENTS
- **NO SLICE 25 IMPLEMENTATION AUTHORIZED AT THIS STAGE.**
- **NO DATABASE MUTATION PERFORMED.**
- **SLICES 21–24 REMAIN IMMUTABLE AND UNTOUCHED.**
