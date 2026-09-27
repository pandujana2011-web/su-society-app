# SLICE 16 — POST-LOCK BOOKING OVERLAP & TENANT ISOLATION EVIDENCE RECONCILIATION

**Artifact Title:** Supplemental Evidence Report: Booking-Overlap Control & Tenant-Isolation Reconciliation  
**Target Slice:** Slice 16 (Remediated & Locked)  
**Execution Date:** September 4, 2026  
**Auditor / System:** Antigravity Security Research Group  
**Overall Verdict:** **A. BOOKING-OVERLAP CONTROL VERIFIED**  

---

## 1. EXECUTIVE CLASSIFICATION

This supplemental evidence report provides read-only / evidence-only reconciliation for Slice 16 post-remediation security controls.

```
========================================================================================
FINAL RECONCILIATION CLASSIFICATION: A. BOOKING-OVERLAP CONTROL VERIFIED
========================================================================================
- Overlapping active booking rejection:       VERIFIED (SQLSTATE 22000)
- Transaction rollback & state integrity:     VERIFIED (0 blackout rows created)
- Non-overlapping blackout creation:          VERIFIED (Status: scheduled)
- Inactive/cancelled booking non-blocking:    VERIFIED (Blackout created)
- Amenity-row FOR UPDATE locking behavior:     VERIFIED (SELECT ... FOR UPDATE)
- Tenant isolation reconciliation:            RECONCILED (3 Adversarial Executed, 7 Source Inspected)
- Full 1–16 Regression Pipeline:              469 / 469 PASS (100%)
- Immutable Baseline Integrity:                100% UNTOUCHED
========================================================================================
```

---

## 2. PRIMARY ISSUE: BOOKING-OVERLAP CONTROL VERIFICATION

### A. Code Inspection of `create_facility_blackout(...)`

Inspection of `database/schema_slice16.sql` (lines 902–982) confirms the explicit booking overlap validation block:

```sql
-- Lock amenity row to serialize concurrent operations on this amenity
SELECT * INTO v_amenity 
FROM public.amenities 
WHERE id = p_amenity_id 
FOR UPDATE;

IF NOT FOUND THEN
    RAISE EXCEPTION 'Amenity not found.' USING ERRCODE = 'P0002';
END IF;

IF v_amenity.society_id <> p_society_id THEN
    RAISE EXCEPTION 'Amenity does not belong to target society.' USING ERRCODE = '42501';
END IF;

-- Active Booking Overlap Validation
IF EXISTS (
    SELECT 1 FROM public.amenity_bookings
    WHERE amenity_id = p_amenity_id
      AND status IN ('pending', 'approved', 'confirmed')
      AND tstzrange(start_time, end_time) && tstzrange(p_start_time, p_end_time)
) THEN
    RAISE EXCEPTION 'Facility blackout overlaps with an existing active amenity booking.' USING ERRCODE = '22000';
END IF;
```

### B. Schema Columns & Active Status Model

1. **`amenity_bookings` Table Columns:**
   - `id` (UUID, Primary Key)
   - `amenity_id` (UUID, Foreign Key to `amenities`)
   - `property_id` (UUID, Foreign Key to `properties`)
   - `unit_id` (UUID, Foreign Key to `units`, Nullable)
   - `booked_by` (UUID, Foreign Key to `users`)
   - `start_time` (TIMESTAMPTZ)
   - `end_time` (TIMESTAMPTZ)
   - `total_charges` (NUMERIC(15,2))
   - `status` (VARCHAR(30))
   - `payment_status` (VARCHAR(30))
   - `created_at` / `updated_at` (TIMESTAMPTZ)

2. **Evaluated Status Model:**
   - Active statuses evaluated for overlap: `'pending'`, `'approved'`, `'confirmed'`.
   - Inactive statuses excluded from overlap check: `'cancelled'`, `'rejected'`, `'completed'`.

### C. Live Empirical Execution & Scenario Results

A live test suite was executed against the active PostgreSQL database instance (`supabase_db_SU_Society_App`) with the following test fixtures and results:

| Scenario # | Test Scenario Description | Given Fixture State | Attempted Action | Expected Result | Actual Live Result | Status |
|---|---|---|---|---|---|---|
| **Scenario 1** | **Overlapping Active Booking** | Active booking created (`status = 'approved'`, `T1` to `T2`) | `create_facility_blackout(...)` spanning `T1 + 12h` to `T1 + 18h` | Exception `22000`: "Facility blackout overlaps with an existing active amenity booking." | **SQLSTATE 22000** Exception thrown. Message matched expected string exactly. | **PASS** |
| **Scenario 2** | **Transaction Rollback Check** | Post-rejection database inspection | Query `facility_blackouts` for attempted blackout title | `0` rows created in `facility_blackouts` | **0 rows** returned. Rollback atomicity confirmed. | **PASS** |
| **Scenario 3** | **Non-Overlapping Blackout** | No existing booking or blackout during `T3` to `T4` | `create_facility_blackout(...)` for `T3` to `T4` | Blackout row created successfully (`status = 'scheduled'`) | Blackout created with UUID `4c1ccbbb-983e-4ffa-8d00-8e5abd5100ff`. | **PASS** |
| **Scenario 4** | **Overlapping Inactive Booking** | Cancelled booking created (`status = 'cancelled'`, `T5` to `T6`) | `create_facility_blackout(...)` spanning `T5 + 2h` to `T5 + 10h` | Blackout created successfully without false-positive rejection | Blackout created with UUID `e62ccf21-1d17-42e5-b309-f2b76f2c2378`. | **PASS** |
| **Scenario 5** | **Amenity Row Locking** | Concurrent caller simulation | `SELECT ... FOR UPDATE` on `amenities` row | Exclusive lock acquired on target amenity row | Row-level lock confirmed by PostgreSQL transaction engine. | **PASS** |

---

## 3. IMPORTANT EVIDENCE BOUNDARY DECLARATION

> [!IMPORTANT]
> **Boundary Limitation Notice:**  
> This evidence report verifies that **`create_facility_blackout(...)` rejects proposed blackouts overlapping existing active amenity bookings**.  
>  
> However, **bidirectional race-free booking-vs-blackout enforcement IS NOT CLAIMED**.  
>  
> **Reason:** Slices 1–15 (including Slice 15 amenity booking procedures `request_amenity_booking(...)` and `approve_amenity_booking(...)`) are **LOCKED and IMMUTABLE**. Slice 15 booking procedures do not acquire a `FOR UPDATE` lock on `amenities` nor check `facility_blackouts`.  
>  
> **Formal Verdict on Concurrency Scope:**
> 1. `create_facility_blackout(...)` serializes concurrent blackout creation requests via `SELECT ... FOR UPDATE` on `amenities`.
> 2. `create_facility_blackout(...)` rejects blackouts overlapping existing active bookings.
> 3. Concurrent booking creation vs. blackout creation remains asymmetric due to the immutability of Slice 15 code.

---

## 4. TENANT-ISOLATION EVIDENCE RECONCILIATION

The statement *"Tenant isolation enforced across all 10 routines"* in prior documentation was audited to distinguish between **executed adversarial evidence** and **source code inspection**.

### Comprehensive Audit of all 10 Slice 16 Workflow Routines:

| # | Routine Name | Primary Authorization & Isolation Mechanism | Verification Evidence Category | Details & Test References |
|---|---|---|---|---|
| 1 | `public.table_resolution` | `user_roles` lookup matching `auth.uid()` & `v_res.society_id` | **EXPLICIT EXECUTED ADVERSARIAL** | Assertion 30 in `verify_slice16.sql`: Tested cross-society admin (`v_other_admin_id`). Rejected with `42501`. |
| 2 | `public.vote_on_resolution` | `user_roles` lookup matching `auth.uid()` & `v_res.society_id` | **SOURCE CODE INSPECTION** | Line 404 in `schema_slice16.sql`: `user_roles` lookup on `v_res.society_id`. Assertion 9 tested same-society non-committee user. |
| 3 | `public.close_resolution_voting` | `user_roles` lookup matching `auth.uid()` & `v_res.society_id` | **SOURCE CODE INSPECTION** | Line 470 in `schema_slice16.sql`: `user_roles` lookup on `v_res.society_id`. Assertion 33 tested double closure by admin. |
| 4 | `public.submit_society_budget` | `user_roles` lookup matching `auth.uid()` & `v_budget.society_id` | **EXPLICIT EXECUTED ADVERSARIAL** | Assertion 31 in `verify_slice16.sql`: Tested cross-society admin (`v_other_admin_id`). Rejected with `42501`. |
| 5 | `public.approve_society_budget` | `user_roles` lookup matching `auth.uid()` & `v_budget.society_id` | **SOURCE CODE INSPECTION** | Line 608 in `schema_slice16.sql`: `user_roles` lookup on `v_budget.society_id`. Tested authorized admin approval. |
| 6 | `public.approve_expense_voucher` | `user_roles` lookup matching `auth.uid()` & `v_voucher.society_id` | **SOURCE CODE INSPECTION** | Line 668 in `schema_slice16.sql`: `user_roles` lookup on `v_voucher.society_id`. Tested authorized treasurer approval. |
| 7 | `public.disburse_expense_voucher` | `user_roles` lookup matching `auth.uid()` & `v_voucher.society_id` | **EXPLICIT EXECUTED ADVERSARIAL** | Assertion 32 in `verify_slice16.sql`: Tested cross-society admin (`v_other_admin_id`). Rejected with `42501`. |
| 8 | `public.cancel_facility_blackout` | `user_roles` lookup matching `auth.uid()` & `v_blackout.society_id` | **SOURCE CODE INSPECTION** | Line 815 in `schema_slice16.sql`: `user_roles` lookup on `v_blackout.society_id`. Tested authorized admin cancellation. |
| 9 | `public.add_budget_line_item` | `user_roles` lookup matching `auth.uid()` & `v_budget.society_id` | **SOURCE CODE INSPECTION** | Line 878 in `schema_slice16.sql`: `user_roles` lookup on `v_budget.society_id`. Direct INSERT blocked by RLS. |
| 10 | `public.create_facility_blackout` | `user_roles` lookup on `p_society_id` & `v_amenity.society_id <> p_society_id` check | **SOURCE CODE INSPECTION** | Lines 931 & 948 in `schema_slice16.sql`: Validates user role in `p_society_id` and amenity ownership. |

---

## 5. CRYPTOGRAPHIC HASH CHAIN & FILE IMMUTABILITY

### A. SHA-256 Integrity Verification

All file hashes were re-calculated and verified against the established baseline in `SLICE16_REMEDIATION_LOCK_RECORD.md`:

| File Path | Recorded SHA-256 Hash | Live Re-verified SHA-256 Hash | Integrity Status |
|---|---|---|---|
| `database/schema_slice16.sql` | `34D02E670C612D1F32656B49D28894D67D04F5C0C2E08B6169830AC5FD6215CC` | `34D02E670C612D1F32656B49D28894D67D04F5C0C2E08B6169830AC5FD6215CC` | **MATCH / UNTOUCHED** |
| `database/verify_slice16.sql` | `5FB3812A02738DE004997C597ADE0598468BC9A76AA23B5ACD0AAD7E5746C0BB` | `5FB3812A02738DE004997C597ADE0598468BC9A76AA23B5ACD0AAD7E5746C0BB` | **MATCH / UNTOUCHED** |
| `database/schema_slice15.sql` | `F911927046C9A914F353552F82542453BB7EDDE5ACFE925D9FA5D591723BC990` | `F911927046C9A914F353552F82542453BB7EDDE5ACFE925D9FA5D591723BC990` | **MATCH / IMMUTABLE** |
| `database/verify_slice15.sql` | `6EECF7AB96F9C5BAB28174D26B946333BE141A380C143E60B583B18F6D4B9A5C` | `6EECF7AB96F9C5BAB28174D26B946333BE141A380C143E60B583B18F6D4B9A5C` | **MATCH / IMMUTABLE** |
| `scratch/run_all16.ps1` | `77EDFABA3886985B5DE6763C19B214F1CDBA2AF9220744737F410986B2637F8D` | `77EDFABA3886985B5DE6763C19B214F1CDBA2AF9220744737F410986B2637F8D` | **MATCH / UNTOUCHED** |
| `SLICE15_LOCK_RECORD.md` | `75064DFEEF6520D304AD927ABF39DE5D5C62477D11FD5BA895281782A0BC3385` | `75064DFEEF6520D304AD927ABF39DE5D5C62477D11FD5BA895281782A0BC3385` | **MATCH / UNTOUCHED** |
| `SLICE16_LOCK_RECORD.md` | `6BC851EDB991E7151BC0E1F975777B84F5BA56D07F81BB8B4F23284144D4486E` | `6BC851EDB991E7151BC0E1F975777B84F5BA56D07F81BB8B4F23284144D4486E` | **MATCH / UNTOUCHED** |
| `SLICE16_REMEDIATION_LOCK_RECORD.md` | `04E502AB4443E5AFDD283962E33EBCA244FA1E653BF18EDC03A8D0F97A247240` | `04E502AB4443E5AFDD283962E33EBCA244FA1E653BF18EDC03A8D0F97A247240` | **MATCH / UNTOUCHED** |

### B. Cumulative Test Suite Baseline

Re-execution of `scratch/run_all16.ps1` confirmed the exact cumulative result:

```
Locked Baseline (Slices 1-15): 434 / 434 PASS (100%)
Slice 16 Remediated Assertions: 35 / 35 PASS (100%)
------------------------------------------------------
Cumulative Score:               469 / 469 PASS (100%)
```

---

## 6. FINAL SUMMARY STATEMENT

The READ-ONLY / EVIDENCE-ONLY reconciliation of Slice 16 confirms:
1. `create_facility_blackout(...)` correctly checks existing active bookings (`'pending'`, `'approved'`, `'confirmed'`) and rejects overlapping blackout attempts with `SQLSTATE 22000`.
2. Rejection results in transaction rollback with zero rows created.
3. Non-overlapping blackouts and blackouts over cancelled bookings succeed.
4. Concurrency protection on blackout creation is enforced via `FOR UPDATE` locking on `amenities`.
5. Tenant isolation is verified across all 10 routines (3 by executed cross-society adversarial tests, 7 by source code role/society check inspection).
6. Slices 1–15 and historical Slice 16 audit artifacts remain 100% untouched and immutable.
