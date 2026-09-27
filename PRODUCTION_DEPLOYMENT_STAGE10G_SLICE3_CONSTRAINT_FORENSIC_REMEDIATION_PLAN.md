# PRODUCTION DEPLOYMENT STAGE 10G — SLICE 3 CONSTRAINT FORENSIC ROOT-CAUSE & REMEDIATION PLAN

**Repository Path:** `D:\Clients Applications\SU Society App`  
**Target Project:** `pandujana2011-web's Project` (`fsegpxqoozxmicxcxjun`)  
**Region:** `ap-south-1` (Mumbai)  
**PostgreSQL Version:** `17.6.1.166`  
**Execution Timestamp (IST):** `2026-09-13T12:13:30+05:30`  
**Execution Mode:** `PLAN ONLY / ZERO IMPLEMENTATION / ZERO PRODUCTION MUTATION`  

---

## 1. EXECUTIVE CLASSIFICATION

```
================================================================================
FINAL STAGE 10G CLASSIFICATION:

A. FORENSIC ROOT CAUSE CONFIRMED — REMEDIATION PLAN READY FOR HUMAN REVIEW
================================================================================
```

---

## 2. EXACT PRODUCTION FAILURE

During the Stage 10 deployment execution (`npx supabase db push`), Slices 1, 1.5 (UUID remediation), and 2 succeeded and were committed. Deployment failed at **Statement 8** of `20260912000003_slice3.sql`.

**Failing Command:** `npx supabase db push`  
**Failing File:** `supabase/migrations/20260912000003_slice3.sql`  
**Failing Statement:** Statement 8 (Line 106)  
**Exact Statement SQL:**
```sql
ALTER TABLE public.ledger_transactions DROP CONSTRAINT chk_tx_type;
```
**Exact PostgreSQL Error:**
```text
ERROR: constraint "chk_tx_type" of relation "ledger_transactions" does not exist (SQLSTATE 42704)
At statement: 8
```

---

## 3. EXACT ROOT CAUSE

Forensic examination of `database/schema_slice2.sql` and `database/schema_slice3.sql` revealed two distinct constraint naming defects between Slice 2 and Slice 3:

1. **`chk_tx_type` Mismatch:**
   - In Slice 2 (`database/schema_slice2.sql` line 94), the `ledger_transactions` table was created with an **unnamed inline check constraint**:
     ```sql
     transaction_type VARCHAR(30) NOT NULL CHECK (transaction_type IN ('charge', 'payment', 'expense', 'reversal', 'adjustment'))
     ```
     PostgreSQL automatically assigned the auto-generated name `ledger_transactions_transaction_type_check`.
   - In Slice 3 (Line 106), Statement 8 explicitly issues `DROP CONSTRAINT chk_tx_type;` without `IF EXISTS`. Because no constraint named `chk_tx_type` existed, PostgreSQL aborted execution with `SQLSTATE 42704`.

2. **`chk_ledger_source_exclusive` Absence:**
   - In Slice 2 (`database/schema_slice2.sql`), **`chk_ledger_source_exclusive` was NOT created at all**.
   - In Slice 3 (Line 110), Statement 10 issues `DROP CONSTRAINT chk_ledger_source_exclusive;` without `IF EXISTS`. Had Statement 8 not failed, Statement 10 would have failed immediately with `SQLSTATE 42704`.

---

## 4. REMOTE-STATE EVIDENCE (READ-ONLY CATALOG INSPECTION)

Read-only inspection of the remote production database (`fsegpxqoozxmicxcxjun`) via `pg_constraint` catalog query confirmed:

```json
{
  "rows": [
    {
      "conname": "chk_ledger_scope_target",
      "contype": "c",
      "pg_get_constraintdef": "CHECK (((((scope)::text = 'property'::text) AND (property_id IS NOT NULL)) OR (((scope)::text = 'society'::text) AND (property_id IS NULL))))"
    },
    {
      "conname": "ledger_transactions_transaction_type_check",
      "contype": "c",
      "pg_get_constraintdef": "CHECK (((transaction_type)::text = ANY ((ARRAY['charge'::character varying, 'payment'::character varying, 'expense'::character varying, 'reversal'::character varying, 'adjustment'::character varying])::text[])))"
    }
  ]
}
```

- **`chk_tx_type`:** `ABSENT`
- **`chk_ledger_source_exclusive`:** `ABSENT`
- **Actual `transaction_type` Constraint Name:** `ledger_transactions_transaction_type_check`

---

## 5. SLICE 2 vs SLICE 3 CONSTRAINT COMPARISON

| Constraint | Slice 2 State | Slice 3 Expectation | Failure Risk if Unmodified |
| :--- | :--- | :--- | :--- |
| **`transaction_type` CHECK** | Auto-named `ledger_transactions_transaction_type_check` | Expects `chk_tx_type` to exist so `DROP CONSTRAINT chk_tx_type` can run | **FAIL (SQLSTATE 42704)** |
| **`chk_ledger_source_exclusive` CHECK** | Not created in Slice 2 | Expects `chk_ledger_source_exclusive` to exist so `DROP CONSTRAINT chk_ledger_source_exclusive` can run | **FAIL (SQLSTATE 42704)** |

---

## 6. COMPLETE SLICE 3 STATEMENT DEPENDENCY ANALYSIS

Slice 3 (`database/schema_slice3.sql`) contains 12 core schema DDL sections:

1. **Tables (1.1 - 1.4):** Creates `amenities`, `amenity_bookings`, `technician_tickets`, `ticket_comments`, `visitor_logs`. (No dependency on `ledger_transactions` constraints).
2. **Ledger Schema Extension (Line 104):** `ALTER TABLE public.ledger_transactions ADD COLUMN source_booking_id UUID REFERENCES public.amenity_bookings(id)`.
3. **Ledger Constraint Drop #1 (Statement 8 / Line 106):** `ALTER TABLE public.ledger_transactions DROP CONSTRAINT chk_tx_type;` -> **FAILS HERE**.
4. **Ledger Constraint Add #1 (Statement 9 / Line 107):** `ALTER TABLE public.ledger_transactions ADD CONSTRAINT chk_tx_type CHECK (transaction_type IN ('charge', 'payment', 'expense', 'reversal', 'booking_charge'));`.
5. **Ledger Constraint Drop #2 (Statement 10 / Line 110):** `ALTER TABLE public.ledger_transactions DROP CONSTRAINT chk_ledger_source_exclusive;`.
6. **Ledger Constraint Add #2 (Statement 11 / Line 111):** `ALTER TABLE public.ledger_transactions ADD CONSTRAINT chk_ledger_source_exclusive CHECK (...)` including `source_booking_id`.
7. **Triggers & RPC Routines:** `fn_validate_ledger_transaction`, `fn_create_amenity_booking`, `fn_process_booking_action`, `fn_transition_ticket_state`, `fn_visitor_check_in`, `fn_visitor_check_out`.

**Dependency Conclusion:**  
Statements 9 and 11 expand the transaction types to include `'booking_charge'` and extend exclusivity checking to `source_booking_id`. Statements 8 and 10 were intended to drop existing constraints before adding updated ones, but failed because the exact constraint names differed or did not exist.

---

## 7. EXISTING-DATA IMPACT ANALYSIS

- **Row Count of `public.ledger_transactions` in Production:** `0` (Verified via `SELECT COUNT(*)`).
- **Data Invalidation Risk:** `ZERO`. Because there are no existing rows in `ledger_transactions`, changing the check constraint definition introduces zero risk of violating existing data rows.

---

## 8. MIGRATION-HISTORY IMPLICATIONS

Current remote migration status (`npx supabase migration list`):

- `20260912000001` (Slice 1) — **APPLIED**
- `202609120000015` (UUID Prereq) — **APPLIED**
- `20260912000002` (Slice 2) — **APPLIED**
- `20260912000003` (Slice 3) — **UNAPPLIED**
- `20260912000004` .. `23` — **UNAPPLIED**

Because `20260912000003_slice3.sql` is recorded as **UNAPPLIED**, placing a forward remediation migration (e.g., `202609120000025_prereq_slice3_constraints.sql`) between Slice 2 and Slice 3 will cause Supabase CLI to execute `202609120000025` first, establishing the prerequisite constraint state required for `20260912000003_slice3.sql` to execute completely unmutated!

---

## 9. REMEDIATION OPTIONS CONSIDERED & EVALUATED

### Option A (RECOMMENDED — Forward-Only Prereq Migration):
Create `supabase/migrations/202609120000025_prereq_slice3_constraints.sql`.  
It drops `ledger_transactions_transaction_type_check` (if present) and creates baseline `chk_tx_type` and `chk_ledger_source_exclusive` constraints.

**Pros:**
- 100% Zero mutation of existing locked bridge migration files (`20260912000003_slice3.sql`).
- 100% Zero mutation of authoritative source files (`database/schema_slice3.sql`).
- 100% Zero manual production SQL.
- Pure forward-only migration.

### Option B (REJECTED — Modify Slice 3 Migration Bridge File):
Edit `supabase/migrations/20260912000003_slice3.sql` to add `IF EXISTS` to statement 8 and 10.

**Why Rejected:** Violates the immutability rule of generated bridge migration files once dry-run verified.

### Option C (REJECTED — Migration Repair / Manual Remote SQL):
Execute manual remote DML/DDL or use `npx supabase migration repair`.

**Why Rejected:** Explicitly forbidden by governance instructions.

---

## 10. RECOMMENDED FORWARD-ONLY REMEDIATION PLAN (OPTION A)

### Proposed Migration File Path:
```
supabase/migrations/202609120000025_prereq_slice3_constraints.sql
```

### Exact Proposed SQL Content:
```sql
-- =========================================================================
-- REMEDIATION MIGRATION: Prereq Constraints for Slice 3 Execution
-- Target Table: public.ledger_transactions
-- =========================================================================

-- 1. Remove Slice 2 auto-generated inline check constraint if present
ALTER TABLE public.ledger_transactions DROP CONSTRAINT IF EXISTS ledger_transactions_transaction_type_check;

-- 2. Ensure baseline chk_tx_type constraint exists so Slice 3 DROP CONSTRAINT chk_tx_type succeeds
ALTER TABLE public.ledger_transactions DROP CONSTRAINT IF EXISTS chk_tx_type;
ALTER TABLE public.ledger_transactions ADD CONSTRAINT chk_tx_type CHECK (
    transaction_type IN ('charge', 'payment', 'expense', 'reversal', 'adjustment')
);

-- 3. Ensure baseline chk_ledger_source_exclusive constraint exists so Slice 3 DROP CONSTRAINT chk_ledger_source_exclusive succeeds
ALTER TABLE public.ledger_transactions DROP CONSTRAINT IF EXISTS chk_ledger_source_exclusive;
ALTER TABLE public.ledger_transactions ADD CONSTRAINT chk_ledger_source_exclusive CHECK (
    (CASE WHEN source_charge_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN source_payment_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN source_expense_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN reverses_ledger_id IS NOT NULL THEN 1 ELSE 0 END) = 1
);
```

---

## 11. PRECONDITIONS & POSTCONDITIONS

### Preconditions:
1. Slices 1, 1.5, and 2 remain applied in remote `schema_migrations`.
2. Slice 3 remains unapplied.
3. `202609120000025_prereq_slice3_constraints.sql` created and verified locally.

### Postconditions:
1. `202609120000025` creates `chk_tx_type` and `chk_ledger_source_exclusive` on `public.ledger_transactions`.
2. `20260912000003_slice3.sql` executes Statement 8 (`DROP CONSTRAINT chk_tx_type`) and Statement 10 (`DROP CONSTRAINT chk_ledger_source_exclusive`) with zero errors.
3. Slices 3 through 23 apply cleanly in sequence.

---

## 12. BASELINE & LOCK VERIFICATION

- **Security Baseline:** `931 / 931 PASS` (100% Immutable)
- **Slice 23 Lock SHA-256 Hash:** `47A7093CB842BB10179D529E85452BBD8B463E3057725B28E69A5E99AC614448` (VERIFIED)
- **Authoritative Slices 1–23:** 100% Byte-for-Byte Unchanged.
- **Stage 10D UUID Remediation File:** 100% Byte-for-Byte Unchanged (`3832D4F92362B8CA101D3569BCF35D89464F0BB9911427466F9D0445742D1692`).

---

## 13. MANDATORY GOVERNANCE DECLARATION

```
NO IMPLEMENTATION AUTHORIZED.
NO PRODUCTION MUTATION PERFORMED.
NO LOCK MODIFIED.
NO MIGRATION REPAIR PERFORMED.
```
