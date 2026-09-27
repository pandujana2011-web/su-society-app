# SLICE 25 — HUMAN ACCOUNTING DECISION & REMEDIATION RECORD

**TARGET REPOSITORY:** `D:\Clients Applications\SU Society App`  
**TARGET SUPABASE PROJECT:** `fsegpxqoozxmicxcxjun` (Region: `ap-south-1`, PostgreSQL `17.6.1.166`)  
**CURRENT REMOTE BOUNDARY:** `20260912000024_slice24.sql`  
**EVALUATED REVIEW ARTIFACT:** `SLICE25_ADVERSARIAL_PRE_IMPLEMENTATION_SECURITY_REVIEW.md` (SHA-256: `238C88BD0AC8D06EC2F1E4375431BC73ED4C42C91563FDAAF9D5E1765A1D81AB`)  
**FORMAL PLAN EVALUATED:** `SLICE25_FORMAL_FORENSIC_SECURITY_PLAN.md` (SHA-256: `FBCCAD02F40555E7275A9B4541465736D5E07DDC3D5A6F4A3FE313F512FA3A49`)  
**EXECUTION MODE:** HUMAN BUSINESS DECISION + PLAN REMEDIATION ONLY  

---

## 1. IMMUTABLE BASELINE VERIFICATION

The locked baselines for Slices 21 through 24 were re-verified and remain 100% immutable:
- **Slice 21 Security Lock SHA-256:** `C8F5E8742CA04391AC51889AD671CD9868710F7C5AB6CC6A9C39C84BCAF16912` — **UNTOUCHED / MATCHED**
- **Slice 22 Security Lock SHA-256:** `BADDA60288021729D4E46A38642ECBBAB3C89EDDCC3A8BCC603EAA6A9B36C3C7` — **UNTOUCHED / MATCHED**
- **Slice 23 Security Lock SHA-256:** `C05F5DB093A2C013E2C14B02CFDBAE0AF2C356935F8B4CABBEBEE720C6CB3D6E` — **UNTOUCHED / MATCHED**
- **Slice 23 Migration SHA-256:** `0231E69F903D3C82F273B7896B29A087D9ABA1CFA928487B6F330881F9236740` — **UNTOUCHED / MATCHED**
- **Slice 24 Security Lock SHA-256:** `E1B206D4F3D6149E3255D467B1ABCDA9F469E5A8730F8333C5E75E2F999AA5C9` — **UNTOUCHED / MATCHED**
- **Current Remote Migration Boundary:** `20260912000024_slice24.sql` — **VERIFIED**

---

## 2. HUMAN DECISION EVALUATION & EVIDENCE AUDIT

### DECISION #1 — ACCOUNTING BASIS (CASH BASIS vs. ACCRUAL BASIS)
- **Evidence Inspected:** `database/schema_phase2.sql` (lines 108–144, 240–274), `PHASE_3B_SPECIFICATION.md`.
- **Repository Reality:**
  - The database maintains a two-tiered sub-ledger architecture:
    1. `member` scope sub-ledger: Tracks member receivables (`charge`, `penalty`, `waiver`, `payment`, `advance_payment`).
    2. `society` scope sub-ledger: Tracks cash movements (`payment` receipt debit, `income` debit, `expense` credit).
  - The repository documentation does **NOT** explicitly state whether the Profit & Loss statement reporting must follow **Cash Basis** (revenue recognized upon cash receipt) or **Accrual Basis** (revenue recognized upon billing issuance).
- **Evaluation Result:** **HUMAN ACCOUNTING DECISION REQUIRED**
  - **Option A (Cash Basis):** Revenue is recognized strictly when member payments are verified/collected; expenses are recognized when vouchers are paid. Unbilled/uncollected maintenance is excluded from P&L revenue.
  - **Option B (Accrual Basis):** Revenue is recognized when maintenance charges are generated; expenses are recognized when incurred. Receivables/payables are fully recognized on the Balance Sheet.
  - *Action:* The human administrator/business stakeholder must select Option A or Option B before the formal plan can be finalized.

---

### DECISION #2 — BAD DEBT / UNCOLLECTED DUES & FINES
- **Evidence Inspected:** `database/schema_phase2.sql` (`prevent_ledger_mutations` trigger lines 278–310).
- **Repository Reality:**
  - The database schema strictly prohibits updating or deleting `ledger_transactions` and `maintenance_charges`.
  - There is no automated write-off trigger or bad debt reduction mechanism in the database.
- **Evaluation Result:** **OPTION A (ESTABLISHED BY SCHEMA IMMUTABILITY)**
  - Uncollected dues and fines remain active receivables on the Balance Sheet and are **NOT** automatically written off.
  - Any bad debt write-off or allowance must occur exclusively through explicit, authorized compensating ledger entries (`transaction_type = 'waiver'` or `'adjustment'`). Slice 25 reporting will not alter or remove unpaid records.

---

### DECISION #3 — OPENING BALANCE / EQUITY
- **Evidence Inspected:** `database/schema_phase2.sql` (lines 146–157, 312–365).
- **Repository Reality:**
  - `opening_balances` table exists: `(id, property_id, user_id, amount, direction, as_of_date, created_by, created_at)`.
  - Trigger `trigger_book_opening_balance_in_ledger` automatically books opening balances into `ledger_transactions` with `scope = 'member'`, `transaction_type = 'adjustment'`, `reference_id = opening_balances.id`.
  - Trigger `trigger_prevent_opening_balance_mutations` enforces immutability.
- **Evaluation Result:** **OPTION A (ESTABLISHED BY EXISTING SCHEMA MECHANISM)**
  - Existing member opening balances are fully represented by explicit ledger entries and aggregated into financial statements based on standard account semantics.
  - Society-level opening equity/cash balances are derived from booked opening transactions and bank reconciliation baselines.

---

## 3. MANDATORY SECURITY HARDENING REQUIREMENTS

All proposed Slice 25 RPCs (`fn_get_trial_balance`, `fn_get_profit_and_loss_statement`, `fn_get_balance_sheet`) must incorporate the following non-negotiable security controls:

1. **SECURITY DEFINER & Search Path:**
   - Must be declared with `SECURITY DEFINER`.
   - Must enforce fixed search path: `SET search_path = pg_catalog, public, pg_temp;`.
2. **Schema Qualification:**
   - All internal table references must be fully schema-qualified (e.g., `public.ledger_transactions`).
3. **Privilege Hardening:**
   - REVOKE `EXECUTE` ON FUNCTION from `PUBLIC` and `anon`.
   - GRANT `EXECUTE` ON FUNCTION strictly to `authenticated`.
4. **Server-Side Authorization & Scope Containment:**
   - Validate caller authentication using `auth.uid()`.
   - Validate caller membership and role in `public.user_roles` / `public.association_memberships` for the target `p_society_id`.
   - Permitted canonical roles: `admin`, `super_admin`, `treasurer`.
   - Direct rejection (`403 Forbidden` / exception) for unauthorized callers (`member`, `tenant`, `gatekeeper`, `technician`, `anon`).
   - Server-side `p_society_id` predicate enforcement on all SQL subqueries to prevent cross-tenant data leakage.

---

## 4. REPORTING-ONLY SAFETY INVARIANTS

The future implementation of Slice 25 is strictly bound by the following safety rules:
- ZERO modification of historical ledger entries or maintenance charges.
- ZERO automatic write-off or silent data normalization.
- ZERO deletion of financial records.
- ZERO repair of data inconsistencies during statement execution (inconsistencies must be surfaced in report output, not modified).

---

## 5. PLAN REMEDIATION STATUS & REVISED PLAN NOTICE

- **Decision #1 (Accounting Basis):** PENDING HUMAN SELECTION.
- **Revised Plan Status:** In accordance with Governance Guidelines Section 10, because Decision #1 requires explicit human business selection (Cash Basis vs. Accrual Basis), **generation of `SLICE25_FORMAL_FORENSIC_SECURITY_PLAN_REVISED.md` IS HELD AND PAUSED**.
- Once the human business selection is formally rendered, `SLICE25_FORMAL_FORENSIC_SECURITY_PLAN_REVISED.md` will be generated incorporating the selected accounting basis.

---

## 6. GOVERNANCE CLASSIFICATION

**CLASSIFICATION B — DECISION RECORD CREATED / REVISED PLAN HELD PENDING HUMAN SELECTION OF ACCOUNTING BASIS**

---

## 7. EXACT NEXT GOVERNANCE GATE

**EXPLICIT HUMAN SELECTION OF ACCOUNTING BASIS (OPTION A: CASH BASIS VS. OPTION B: ACCRUAL BASIS)**

---

### MANDATORY GOVERNANCE STATEMENTS
- **NO SLICE 25 IMPLEMENTATION AUTHORIZED.**
- **NO MIGRATION CREATED.**
- **NO DATABASE MUTATION PERFORMED.**
- **SLICES 21–24 REMAIN IMMUTABLE AND UNTOUCHED.**
