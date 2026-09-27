# SU SOCIETY APP — SLICE 25 FORMAL FORENSIC SECURITY PLAN

**Document Reference:** `SLICE25_FORMAL_FORENSIC_SECURITY_PLAN.md`  
**Target Repository:** `D:\Clients Applications\SU Society App`  
**Target Supabase Project:** `fsegpxqoozxmicxcxjun` (`ap-south-1`)  
**PostgreSQL Version:** `17.6.1.166`  
**Lifecycle Stage:** SLICE 25 FORMAL FORENSIC SECURITY PLANNING  
**Selected Scope:** Candidate A — Advanced Financial Statement Generation (Trial Balance, P&L, Balance Sheet)  
**Security Classification:** `CLASSIFICATION A`  
**Execution Mode:** `PLAN ONLY / ZERO IMPLEMENTATION / ZERO DATABASE MUTATION / ZERO DEPLOYMENT / ZERO LOCK`  

---

## 1. EXECUTIVE STATUS & GOVERNANCE BASELINE

Slice 25 establishes the **Advanced Financial Statement Generation & Reporting Phase** for the SU Society App platform, executing on explicit human scope selection of Candidate A.

* **Authorization State:** FORMAL FORENSIC SECURITY PLANNING ONLY. Zero implementation authorized.
* **Remote Migration Boundary:** `20260912000024_slice24.sql` (VERIFIED REMOTE APPLIED)
* **Candidate Migration:** `supabase/migrations/20260912000025_slice25.sql` (UNCREATED)

### Immutable Baseline Verification

| Slice / Artifact Boundary | Reference File | SHA-256 Hash | Status |
| :--- | :--- | :--- | :--- |
| **Slice 21 Lock** | `SLICE21_FINAL_GOVERNANCE_CLOSURE_AND_SECURITY_LOCK.md` | `C8F5E8742CA04391AC51889AD671CD9868710F7C5AB6CC6A9C39C84BCAF16912` | **VERIFIED UNCHANGED** |
| **Slice 22 Lock** | `SLICE22_FINAL_GOVERNANCE_CLOSURE_AND_SECURITY_LOCK.md` | `BADDA60288021729D4E46A38642ECBBAB3C89EDDCC3A8BCC603EAA6A9B36C3C7` | **VERIFIED UNCHANGED** |
| **Slice 23 Lock** | `SLICE23_FINAL_GOVERNANCE_CLOSURE_AND_SECURITY_LOCK.md` | `C05F5DB093A2C013E2C14B02CFDBAE0AF2C356935F8B4CABBEBEE720C6CB3D6E` | **VERIFIED UNCHANGED** |
| **Slice 23 Migration** | `supabase/migrations/20260912000023_slice23.sql` | `0231E69F903D3C82F273B7896B29A087D9ABA1CFA928487B6F330881F9236740` | **VERIFIED UNCHANGED** |
| **Slice 24 Lock** | `SLICE24_FINAL_GOVERNANCE_CLOSURE_AND_SECURITY_LOCK.md` | `E1B206D4F3D6149E3255D467B1ABCDA9F469E5A8730F8333C5E75E2F999AA5C9` | **VERIFIED UNCHANGED** |

---

## 2. SCOPE DEFINITION — CANDIDATE A (ADVANCED FINANCIAL STATEMENTS)

Slice 25 delivers three core, read-only financial reporting stored procedures designed for society treasurers and administrators:

1. **Trial Balance Procedure (`fn_get_trial_balance`):**
   * Computes total debits and credits across all active account categories (Maintenance Fee Receivables, Fine Receivables, Utility Charges, Amenity Fees, Cash/Bank Balances, Operating Expenses) for a specified reporting period (`p_start_date` to `p_end_date`).
   * Enforces the fundamental accounting equality: $\sum \text{Debits} = \sum \text{Credits}$.
2. **Profit & Loss Statement Procedure (`fn_get_profit_and_loss_statement`):**
   * Aggregates total Operating Income (maintenance fees, fines, penalties, amenity fees, utility charges) against total Operating Expenses (paid/approved expense vouchers categorized by `expense_categories`) within the specified date range.
   * Calculates Net Operating Surplus / Deficit ($\text{Surplus} = \text{Total Income} - \text{Total Expenses}$).
3. **Balance Sheet Procedure (`fn_get_balance_sheet`):**
   * Generates an authoritative financial snapshot as of an effective date (`p_as_of_date`).
   * **Assets:** Cash & Bank Balances (accumulated receipts minus paid expenses), Outstanding Resident Receivables (unpaid charges/fines).
   * **Liabilities:** Pending/Approved Expense Payables, Advance Resident Payments.
   * **Equity & Accumulated Reserve:** Accumulated Operating Surplus from previous financial periods.
   * Enforces the core accounting equation: $\text{Assets} = \text{Liabilities} + \text{Equity}$.

---

## 3. EXISTING FINANCIAL ARCHITECTURE INVENTORY

Inspection of existing schema files (`database/schema_phase2.sql`) establishes the authoritative data sources:

* `public.ledger_transactions`: Stores resident debit transactions (`maintenance_fee`, `fine`, `penalty`, `utility_charge`, `amenity_fee`) and credit transactions (`payment`).
* `public.payments` & `public.receipts`: Stores cash, cheque, UPI, and bank transfer receipts.
* `public.expense_vouchers` & `public.expense_categories`: Stores society operational expenditure records (`approved`, `paid`).
* `public.opening_balances`: Stores historical opening balances for properties/units.
* `public.bank_reconciliations`: Stores bank statement closing balances and reconciliation logs.

---

## 4. FINANCIAL ACCOUNTING SEMANTICS & CLASSIFICATION

### A. Debit & Credit Rules
* **Debits:** Increases Assets (Cash/Bank, Dues Receivable) and Expenses.
* **Credits:** Increases Revenue/Income (Fees, Fines) and Liabilities/Reserve.

### B. Account Classification Mapping

| Transaction / Entity | Financial Category | Financial Statement | Accounting Effect |
| :--- | :--- | :--- | :--- |
| `maintenance_fee` | Revenue (Operating Income) | Profit & Loss | Credit Revenue / Debit Receivable |
| `fine`, `penalty` | Revenue (Other Income) | Profit & Loss | Credit Revenue / Debit Receivable |
| `amenity_fee` | Revenue (Amenity Income) | Profit & Loss | Credit Revenue / Debit Receivable |
| `utility_charge` | Revenue (Utility Recovery) | Profit & Loss | Credit Revenue / Debit Receivable |
| `payment` | Asset (Cash & Bank) | Balance Sheet | Debit Cash / Credit Receivable |
| `expense_vouchers` (`paid`) | Expense (Operational Cost) | Profit & Loss | Debit Expense / Credit Cash |
| Dues Receivable (`unpaid`) | Asset (Current Assets) | Balance Sheet | Asset Balance |
| Accumulated Surplus | Equity (Reserve Fund) | Balance Sheet | Equity Balance |

---

## 5. REPORTING-PERIOD & ZERO-BALANCE HANDLING

* **Reporting Period (`p_start_date`, `p_end_date`):** Mandatory date filtering using server-side `DATE(created_at)` or `DATE(voucher_date)`.
* **As-Of Date (`p_as_of_date`):** Balance Sheet items accumulate all historical activity up to 23:59:59 UTC on `p_as_of_date`.
* **Zero-Balance Accounts:** Accounts with zero total debits and credits during the period return `0.00` balances rather than `NULL` or omitting the row, ensuring structural completeness.
* **Empty Period Behavior:** If no transactions exist in the date range, reporting RPCs return a valid JSON payload with zeroed financial totals.

---

## 6. MULTI-TENANCY & AUTHORIZATION MODEL

* **Strict Role Restriction:** Reporting RPCs are restricted strictly to `admin`, `super_admin`, and `treasurer` roles. Residents, tenants, and gatekeepers are denied access with SQLSTATE `42501` (`INSUFFICIENT_PRIVILEGE`).
* **Tenant Isolation Invariant:** Caller `society_id` is derived strictly from `public.profiles` using JWT identity `auth.uid()`. User-supplied `society_id` parameters are ignored.
* **Cross-Society Guard:** All aggregation queries include `WHERE society_id = v_caller_society_id`.

---

## 7. RPC & SECURITY DEFINER SPECIFICATIONS

All proposed financial reporting RPCs adhere to hardened database specifications:

```sql
-- Pattern for Slice 25 Financial RPCs
CREATE OR REPLACE FUNCTION public.fn_get_trial_balance(
    p_start_date DATE,
    p_end_date DATE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_actor_id UUID;
    v_actor_role TEXT;
    v_society_id UUID;
    v_result JSONB;
BEGIN
    v_actor_id := auth.uid();
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Authentication required';
    END IF;

    SELECT society_id, role INTO v_society_id, v_actor_role 
    FROM public.profiles 
    WHERE id = v_actor_id;

    IF v_actor_role IS NULL OR v_actor_role NOT IN ('admin', 'super_admin', 'treasurer') THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Financial reports restricted to treasurer or admin roles';
    END IF;

    -- Aggregate Trial Balance metrics...
    -- ...
    
    RETURN v_result;
END;
$$;
```

* **Execution Privilege:** `REVOKE EXECUTE ON FUNCTION ... FROM PUBLIC, anon;` and `GRANT EXECUTE ON FUNCTION ... TO authenticated;`.

---

## 8. THREAT MODEL (TV25-01 TO TV25-20)

| Threat Vector ID | Attack Surface | Attacker Capability | Attack Scenario | Security Invariant | Mitigation / Enforcement | Severity |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **TV25-01** | `fn_get_trial_balance` | Ordinary Resident | Resident invokes Trial Balance RPC directly | Role restriction | RPC enforces `role IN ('admin', 'treasurer')` | CRITICAL |
| **TV25-02** | `fn_get_balance_sheet` | Tenant | Tenant queries society balance sheet | Role restriction | RPC enforces `role IN ('admin', 'treasurer')` | CRITICAL |
| **TV25-03** | Financial Reporting | Gatekeeper | Gatekeeper attempts to read Profit & Loss | Role restriction | RPC raises SQLSTATE `42501` | HIGH |
| **TV25-04** | Reporting RPCs | Malicious Admin | Admin attempts to view foreign society P&L | Multi-tenancy | RPC derives `society_id` from `auth.uid()` | CRITICAL |
| **TV25-05** | Date Parameters | Malicious User | Inverting `p_start_date > p_end_date` | Input validation | RPC checks `p_start_date <= p_end_date` | MEDIUM |
| **TV25-06** | `search_path` Injection | Malicious Schema | Schema hijacking during RPC execution | Path hardening | `SET search_path = pg_catalog, public` | CRITICAL |
| **TV25-07** | RPC Grants | Anonymous User | Public invocation of reporting RPC | Execution grant | `REVOKE EXECUTE FROM PUBLIC, anon` | CRITICAL |
| **TV25-08** | Ledger Data | Direct SQL | Attacker modifies ledger entries to alter reports | Immutable ledger | Existing trigger `prevent_ledger_mutations` | CRITICAL |
| **TV25-09** | Concurrency | Concurrent User | Concurrent ledger inserts during report run | Consistent read | Read-only transactional snapshot | MEDIUM |
| **TV25-10** | Balance Sheet | Accounting Error | Imbalance where Assets != Liabilities + Equity | Accounting equation| Server-side assertion validates equation | HIGH |
| **TV25-11** | Trial Balance | Accounting Error | Imbalance where Total Debits != Total Credits | Trial balance check | Server-side validation of debit/credit equality | HIGH |
| **TV25-12** | Null Balances | Malicious Input | Malformed ledger rows with NULL amounts | Data integrity | RPC relies on `COALESCE(SUM(amount), 0.00)` | LOW |
| **TV25-13** | Reporting Period | Attacker | Passing future `p_as_of_date` | Date range boundary | RPC caps effective date at `CURRENT_DATE` | LOW |
| **TV25-14** | PII Exposure | Reporting Output | Report payload exposing individual mobile numbers | Data privacy | Report aggregates numbers without PII | MEDIUM |
| **TV25-15** | Expense Vouchers | Unapproved Voucher| Including `draft` expense vouchers in P&L | Voucher status | RPC filters strictly `status = 'paid'` | HIGH |
| **TV25-16** | Reconciliations | Bank Discrepancy | Bank balance divergence from cash book | BRS verification | Cross-verification with `bank_reconciliations` | MEDIUM |
| **TV25-17** | Duplicate Entries | Replay Attack | Re-counting payment allocations | Unique aggregation | Aggregates on primary transaction keys | HIGH |
| **TV25-18** | Frontend UI | Client State | User forces UI tab visibility to view reports | Server authority | UI tab render does NOT replace server check | HIGH |
| **TV25-19** | Audit System | System Failure | Financial statement generation un-audited | Audit completeness| Writes read-audit event to `public.audit_logs` | LOW |
| **TV25-20** | Locked Slices | Unintended DDL | RPC setup alters Slice 22 fine ledger policies | Slice immutability | 100% additive DDL only | CRITICAL |

---

## 9. VERIFICATION ASSERTION PLAN (S25-001 TO S25-050)

| Assertion ID | Domain | Assertion Description | Classification |
| :--- | :--- | :--- | :--- |
| **S25-001** | Auth | `fn_get_trial_balance` grants access to `admin` | Runtime |
| **S25-002** | Auth | `fn_get_trial_balance` grants access to `treasurer` | Runtime |
| **S25-003** | Auth | `fn_get_trial_balance` denies access to `resident` with `42501` | Runtime |
| **S25-004** | Auth | `fn_get_trial_balance` denies access to `tenant` with `42501` | Runtime |
| **S25-005** | Auth | `fn_get_trial_balance` denies access to `gatekeeper` with `42501` | Runtime |
| **S25-006** | Multi-Tenancy | `fn_get_trial_balance` strictly filters by caller's `society_id` | Runtime |
| **S25-007** | Accounting | `fn_get_trial_balance` proves `Total Debits == Total Credits` | Runtime |
| **S25-008** | Validation | `fn_get_trial_balance` rejects `p_start_date > p_end_date` | Runtime |
| **S25-009** | RPC Config | `fn_get_trial_balance` defined with `SECURITY DEFINER` | Forensic |
| **S25-010** | RPC Config | `fn_get_trial_balance` enforces `search_path = pg_catalog, public` | Forensic |
| **S25-011** | Auth | `fn_get_profit_and_loss_statement` grants access to `admin` | Runtime |
| **S25-012** | Auth | `fn_get_profit_and_loss_statement` grants access to `treasurer` | Runtime |
| **S25-013** | Auth | `fn_get_profit_and_loss_statement` denies `resident` access | Runtime |
| **S25-014** | Multi-Tenancy | `fn_get_profit_and_loss_statement` filters by caller `society_id` | Runtime |
| **S25-015** | Accounting | `fn_get_profit_and_loss_statement` calculates `Surplus = Income - Expenses` | Runtime |
| **S25-016** | Data Integrity| P&L includes only `paid` expense vouchers | Runtime |
| **S25-017** | Data Integrity| P&L includes all ledger income transaction types | Runtime |
| **S25-018** | RPC Config | `fn_get_profit_and_loss_statement` defined with `SECURITY DEFINER` | Forensic |
| **S25-019** | RPC Config | `fn_get_profit_and_loss_statement` enforces hardened `search_path` | Forensic |
| **S25-020** | Auth | `fn_get_balance_sheet` grants access to `admin` | Runtime |
| **S25-021** | Auth | `fn_get_balance_sheet` grants access to `treasurer` | Runtime |
| **S25-022** | Auth | `fn_get_balance_sheet` denies `resident` access | Runtime |
| **S25-023** | Multi-Tenancy | `fn_get_balance_sheet` filters by caller `society_id` | Runtime |
| **S25-024** | Accounting | `fn_get_balance_sheet` proves `Assets == Liabilities + Equity` | Runtime |
| **S25-025** | Data Integrity| Balance sheet assets include cash/bank and dues receivable | Runtime |
| **S25-026** | Data Integrity| Balance sheet liabilities include advance payments and payables | Runtime |
| **S25-027** | RPC Config | `fn_get_balance_sheet` defined with `SECURITY DEFINER` | Forensic |
| **S25-028** | RPC Config | `fn_get_balance_sheet` enforces hardened `search_path` | Forensic |
| **S25-029** | Security | PUBLIC execution revoked on `fn_get_trial_balance` | Forensic |
| **S25-030** | Security | anon execution revoked on `fn_get_trial_balance` | Forensic |
| **S25-031** | Security | PUBLIC execution revoked on `fn_get_profit_and_loss_statement` | Forensic |
| **S25-032** | Security | anon execution revoked on `fn_get_profit_and_loss_statement` | Forensic |
| **S25-033** | Security | PUBLIC execution revoked on `fn_get_balance_sheet` | Forensic |
| **S25-034** | Security | anon execution revoked on `fn_get_balance_sheet` | Forensic |
| **S25-035** | Security | Execution granted strictly to `authenticated` role on all 3 RPCs | Forensic |
| **S25-036** | Privacy | Statements redact all individual resident PII | Forensic |
| **S25-037** | Zero Handling| Statements return `0.00` for zero-activity accounts | Runtime |
| **S25-038** | Empty Period| Empty reporting period returns valid zeroed payload | Runtime |
| **S25-039** | Audit | Statement generation logs read event to `public.audit_logs` | Runtime |
| **S25-040** | Immutability | Statement RPCs perform zero database mutations | Runtime |
| **S25-041** | Immutability | Slice 21 lock SHA remains unchanged | Forensic |
| **S25-042** | Immutability | Slice 22 lock SHA remains unchanged | Forensic |
| **S25-043** | Immutability | Slice 23 lock SHA remains unchanged | Forensic |
| **S25-044** | Immutability | Slice 24 lock SHA remains unchanged | Forensic |
| **S25-045** | Boundary | Remote migration boundary is `20260912000025_slice25.sql` | Forensic |
| **S25-046** | Frontend | Statement UI tab restricted to Treasurer/Admin roles | Forensic |
| **S25-047** | Frontend | UI invokes backend RPCs via `supabase.rpc()` | Forensic |
| **S25-048** | Immutability | Historical ledger transactions remain un-mutated | Runtime |
| **S25-049** | Immutability | Historical expense vouchers remain un-mutated | Runtime |
| **S25-050** | Consistency | Migration `20260912000025_slice25.sql` and schema mirror byte-identical | Forensic |

---

## 10. MIGRATION BOUNDARY & EXCLUSIONS

* **Current Remote Migration Boundary:** `20260912000024_slice24.sql`
* **Candidate Slice 25 Migration:** `20260912000025_slice25.sql` (UNCREATED)
* **Explicit Exclusions:** No modification of past ledger transactions, no online payment gateway webhook setup (reserved for future Candidate B), no modification of locked Slices 21–24.

---

## 11. HUMAN DECISIONS REQUIRED

* None. Candidate A scope is fully specified by accounting standards and repository data structures.

---

## 12. PLAN CLASSIFICATION

### `CLASSIFICATION A`

* **Rationale:** Candidate A financial statement generation is completely specified, read-only, non-breaking, fully compatible with locked Slices 21–24, and protected by 50 verification assertions and 20 threat mitigations.

---

## 13. RECOMMENDED NEXT GOVERNANCE GATE

* **Recommended Gate:** `SLICE 25 ADVERSARIAL PRE-IMPLEMENTATION SECURITY REVIEW`.

---

## 14. MANDATORY GOVERNANCE STATEMENTS

```
SLICE 25 FORMAL FORENSIC SECURITY PLAN ONLY.

NO SLICE 25 IMPLEMENTATION AUTHORIZED.

NO DATABASE MUTATION PERFORMED.

NO MIGRATION EXECUTED.

NO REMOTE DEPLOYMENT PERFORMED.

NO VERCEL DEPLOYMENT PERFORMED.

NO GOVERNANCE CLOSURE PERFORMED.

NO SECURITY LOCK CREATED.

SLICES 21–24 REMAIN IMMUTABLE.
```

---
**End of Artifact:** `SLICE25_FORMAL_FORENSIC_SECURITY_PLAN.md`
