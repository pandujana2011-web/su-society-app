# SLICE 16 SECURITY GAP REMEDIATION PLAN

**Target Repository:** SU Society App  
**Target Slice:** Slice 16 (Society Governance, Board Resolutions, Budget Approval Engine & Facility Blackout Workflows)  
**Plan Date:** September 4, 2026 (Final Plan Correction)  
**Author:** Antigravity Security Research Group  
**Status:** **PLAN ONLY — NO IMPLEMENTATION AUTHORIZED**  

---

## 1. EXECUTIVE SUMMARY

During the post-lock security re-verification of Slice 16, an evidence and exploitability audit identified two direct SQL insertion authorization vulnerabilities and one unproven security claim:

1. **Gap 1 (Vote Insertion Bypass):** `committee_resolution_votes` has an overly permissive RLS policy `pol_resolution_votes_insert` (`WITH CHECK (true)`), allowing authenticated users to directly insert votes impersonating other voters without invoking `vote_on_resolution(...)`.
2. **Gap 2 (Budget Line Item Injection Bypass):** `budget_line_items` has an overly permissive RLS policy `pol_budget_items_insert` (`WITH CHECK (true)`), allowing authenticated users to insert unvetted budget line items outside controlled workflows.
3. **Gap 3 (Facility Blackout Direct INSERT Bypass & Overlap Protection Status):** `facility_blackouts` currently has an overly permissive RLS policy `pol_blackouts_insert_authenticated` (`WITH CHECK (true)`), allowing direct SQL insertions. Additionally, no controlled SECURITY DEFINER creation procedure (`create_facility_blackout`) exists in the repository (only `cancel_facility_blackout` exists), leaving facility blackout creation unmonitored and blackout/booking overlap protection unproven.

This document presents a comprehensive, non-destructive remediation plan. **Zero database objects, schema files, RLS policies, triggers, stored procedures, or test files have been altered.**

---

## 2. CONFIRMED VULNERABILITIES & ROOT CAUSE ANALYSIS

### Gap 1: Direct Vote Insert Impersonation
- **Root Cause:** In `database/schema_slice16.sql`, `pol_resolution_votes_insert` was defined as `FOR INSERT TO authenticated WITH CHECK (true)`.
- **Vulnerability:** While direct `UPDATE` and `DELETE` on votes are blocked by default-deny RLS, direct `INSERT` is permitted for any `voter_id` UUID.
- **Exploit Path:** An authenticated attacker can run:
  ```sql
  INSERT INTO committee_resolution_votes (resolution_id, voter_id, vote, comments)
  VALUES ('<resolution_uuid>', '<victim_user_uuid>', 'for', 'Impersonated vote');
  ```
  This bypasses committee role validation, resolution state checks (`status = 'voting'`), society membership checks, and vote counter updates.

### Gap 2: Direct Budget Line Item Injection
- **Root Cause:** In `database/schema_slice16.sql`, `pol_budget_items_insert` was defined as `FOR INSERT TO authenticated WITH CHECK (true)`.
- **Vulnerability:** Authenticated clients can insert new line items directly into any budget.
- **Exploit Path:** An attacker can insert line items into approved budgets or budgets of other societies, bypassing budget submission state validation and society ownership checks.

### Gap 3: Direct Facility Blackout INSERT Bypass & Overlap Status
- **Root Cause & Inspection Result:** `facility_blackouts` has policy `pol_blackouts_insert_authenticated` (`WITH CHECK (true)`), permitting direct client SQL inserts. Inspection of `pg_proc` confirms `create_facility_blackout` **does NOT exist** in the repository. The only blackout workflow routine implemented in Slice 16 is `cancel_facility_blackout(p_blackout_id UUID, p_reason TEXT)`.
- **Classification:** **BLACKOUT/BOOKING OVERLAP IS CURRENTLY UNPROVEN / NOT DEMONSTRATED**. Direct client `INSERT` into `facility_blackouts` must be blocked and brought under a controlled SECURITY DEFINER procedure.

---

## 3. RECOMMENDED REMEDIATION ARCHITECTURE

### Architecture Trade-Off Analysis: Restrictive WITH CHECK vs. Deny Direct INSERT

#### Option A: Declarative RLS `WITH CHECK` (e.g. `WITH CHECK (voter_id = auth.uid())`)
- *Drawbacks:* A declarative `WITH CHECK (voter_id = auth.uid())` on `committee_resolution_votes` would prevent impersonating another voter, but it **would still allow direct SQL insertion** for the user's own vote, bypassing resolution state validation (`status = 'voting'`), committee membership checks in `user_roles`, resolution society matching, server-side tally updates (`votes_for` / `votes_against`), and audit log generation.

#### Option B: Deny Direct Authenticated INSERT Entirely (RECOMMENDED)
- *Recommendation:* **Revoke direct client INSERT access entirely** by removing permissive INSERT policies or establishing RESTRICTIVE INSERT policies (`WITH CHECK (false)`).
- *Mechanism:* Require voting, line item creation, and blackout creation to occur **exclusively through SECURITY DEFINER stored procedures** (`vote_on_resolution(...)`, `add_budget_line_item(...)`, `create_facility_blackout(...)`).
- *Why Option B is Superior:* SECURITY DEFINER procedures run under trusted superuser context (`proowner = postgres`, `SET search_path = public, pg_temp`) and bypass client RLS policies during internal SQL execution. They atomically enforce:
  1. `auth.uid()` binding.
  2. Committee membership & society tenant validation via `user_roles`.
  3. Resolution/budget/blackout state machine validation.
  4. Server-side counter and tally updates under `SELECT FOR UPDATE` row locks.
  5. Audit log generation and notification delivery.
  6. Complete block of unvetted direct client SQL inserts on votes, budget line items, and facility blackouts.

---

## 4. DETAILED REMEDIATION DESIGNS

### A. Vote INSERT Remediation Design (Gap 1)
- **RLS Policy Change:**
  - Drop permissive policy `pol_resolution_votes_insert` on `committee_resolution_votes`.
  - Create RESTRICTIVE policy `pol_resolution_votes_restrictive_insert ON committee_resolution_votes AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (false);` (or leave un-granted for `authenticated`).
  - Direct authenticated `INSERT`, cross-society `INSERT`, and forged-GUC `INSERT` will be unconditionally **BLOCKED**.
- **Procedure Verification:**
  - `vote_on_resolution(p_resolution_id UUID, p_vote_value TEXT, p_comments TEXT)` (SECURITY DEFINER) continues to perform internal insertion with `voter_id = auth.uid()` after verifying active committee role, `status = 'voting'`, and `uq_resolution_voter` uniqueness constraint.

### B. Budget Line Item INSERT Remediation Design (Gap 2)
- **RLS Policy Change:**
  - Drop permissive policy `pol_budget_items_insert` on `budget_line_items`.
  - Create RESTRICTIVE policy `pol_budget_items_restrictive_insert ON budget_line_items AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (false);`.
  - Direct authenticated `INSERT`, cross-society `INSERT`, and forged-GUC `INSERT` will be unconditionally **BLOCKED**.
- **Preservation of Existing Budget Procedures:**
  - The existing signature `submit_society_budget(p_budget_id UUID)` is preserved untouched.
  - To enable budget line item creation while direct client `INSERT` is denied, a new SECURITY DEFINER helper procedure `add_budget_line_item(p_budget_id UUID, p_category TEXT, p_allocated_amount NUMERIC, p_description TEXT)` will be defined in Slice 16. It validates that `status = 'draft'` for the budget and confirms the calling user holds an active `society_admin` role for `budget.society_id` before inserting the line item.

### C. Facility Blackout Direct INSERT & Overlap Remediation Design (Gap 3)
- **RLS Policy Change:**
  - Drop permissive policy `pol_blackouts_insert_authenticated` on `facility_blackouts`.
  - Create RESTRICTIVE policy `pol_blackouts_restrictive_insert ON facility_blackouts AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (false);`.
  - Direct authenticated `INSERT`, cross-society direct `INSERT`, and forged-GUC direct `INSERT` will be unconditionally **BLOCKED**.
- **New Stored Procedure:**
  - Define `create_facility_blackout(p_society_id UUID, p_amenity_id UUID, p_title TEXT, p_reason TEXT, p_start_time TIMESTAMPTZ, p_end_time TIMESTAMPTZ)` (SECURITY DEFINER) as the controlled Slice 16 creation path.
  - Performs tenant authorization (`user_roles` check for `society_admin`), validates time range (`p_start_time < p_end_time`), and locks the `amenities` row (`SELECT id FROM amenities WHERE id = p_amenity_id FOR UPDATE`).
  - Checks for overlapping active bookings in `amenity_bookings` (`status IN ('pending', 'approved', 'confirmed')`) and existing blackouts (`status IN ('scheduled', 'active')`). Rejects overlap with exception `22000`.
- **Slice 15 Immutability & Concurrency Limitations:**
  - **Slice 15 (`amenity_bookings`, `request_amenity_booking`, `approve_amenity_booking`) is LOCKED and IMMUTABLE.** No Slice 15 schema, procedure, policy, or verification script may be modified.
  - `create_facility_blackout(...)` locking the `amenities` row can serialize concurrent blackout-creation operations that use the same locking protocol. It does **NOT** automatically serialize immutable Slice 15 booking operations unless those operations also acquire the same lock.
  - Because Slice 15 functions `request_amenity_booking(...)` and `approve_amenity_booking(...)` are immutable and MUST NOT be modified, **full bidirectional race-free enforcement between `facility_blackouts` and `amenity_bookings` remains UNPROVEN within the current Slice 16-only authorization boundary**.
  - Any modification required to Slice 15 remains classified as:  
    `ARCHITECTURAL CHANGE REQUIRED — SEPARATE AUTHORIZATION REQUIRED`.

---

## 5. CONCURRENCY & TENANT ISOLATION ANALYSIS

1. **Row Locking & Blackout Concurrency Scope:** `create_facility_blackout(...)` locking the `amenities` row serializes concurrent blackout-creation operations that use the defined locking protocol. It does **NOT** automatically serialize immutable Slice 15 booking operations (`request_amenity_booking`, `approve_amenity_booking`) which cannot be modified. Full bidirectional blackout-vs-booking race protection is NOT claimed for Slice 16 alone.
2. **Tenant Isolation:** Every procedure queries `user_roles` to verify that `auth.uid()` holds an active role (`committee_member`, `society_admin`, `treasurer`) for the exact `society_id` of the target record.
3. **Rollback Atomicity:** Any validation failure (unmet quorum, invalid state, over-budget amount, cross-society IDOR, or schedule overlap) throws a `22000` or `42501` exception, triggering complete PostgreSQL transaction rollback. Zero partial mutations occur.

---

## 6. EXACT AUTHORIZED REMEDIATION BOUNDARY & IMMUTABILITY

### Potentially Modifiable After Explicit Authorization:
- `database/schema_slice16.sql`: RLS policy updates and new helper/workflow routines (`add_budget_line_item`, `create_facility_blackout`) for Slice 16.
- `database/verify_slice16.sql`: Assertion updates for direct INSERT rejections, line item workflow additions, and blackout creation/overlap validations.

### New Remediation Artifacts That May Be Created:
- `SLICE16_REMEDIATION_IMPLEMENTATION_REPORT.md`
- `SLICE16_POST_REMEDIATION_SECURITY_AUDIT.md`
- `SLICE16_REMEDIATION_LOCK_RECORD.md`

### Immutable Historical Artifacts (MUST NOT BE EDITED, REWRITTEN, REFORMATTED, REGENERATED, OR DELETED):
- `SLICE16_IMPLEMENTATION_REPORT.md` (Historical record of initial 466/466 implementation)
- `SLICE16_POST_IMPLEMENTATION_SECURITY_AUDIT.md` (Historical record of initial audit)
- `SLICE16_LOCK_RECORD.md` (Historical record of initial lock & pre-remediation hashes)
- `SLICE16_POST_LOCK_SECURITY_REVERIFICATION.md` (Historical record of post-lock audit finding)

### Immutable Slices 1–15 Baseline:
- `database/schema_slice1.sql` through `database/schema_slice15.sql`
- `database/verify_slice1.sql` through `database/verify_slice15.sql`
- `scratch/run_all1.ps1` through `scratch/run_all15.ps1`
- `SLICE15_LOCK_RECORD.md`

---

## 7. ADVERSARIAL TEST PLAN (35 TESTS)

Upon explicit authorization of remediation, the following test cases will be executed in the updated `database/verify_slice16.sql`:

### Vote Attacks (1–11)
1. `Direct authenticated INSERT for self` -> **REJECTED / BLOCKED by RLS**.
2. `Direct authenticated INSERT for another voter` -> **REJECTED / BLOCKED by RLS**.
3. `Direct INSERT with forged society context` -> **REJECTED**.
4. `Direct INSERT into another society's resolution` -> **REJECTED**.
5. `Direct INSERT after voting closed` -> **REJECTED**.
6. `Duplicate direct INSERT` -> **REJECTED**.
7. `Direct INSERT with forged GUC` -> **REJECTED**.
8. `Direct UPDATE vote` -> **REJECTED (0 rows updated)**.
9. `Direct UPDATE voter_id` -> **REJECTED (0 rows updated)**.
10. `Direct UPDATE resolution_id` -> **REJECTED (0 rows updated)**.
11. `Direct DELETE vote` -> **REJECTED (0 rows deleted)**.

### Budget Line Item Attacks (12–20)
12. `Direct INSERT into own budget` -> **REJECTED / BLOCKED by RLS**.
13. `Direct INSERT into another society's budget` -> **REJECTED**.
14. `Direct INSERT into approved budget` -> **REJECTED**.
15. `Direct INSERT with forged GUC` -> **REJECTED**.
16. `Direct INSERT with manipulated allocated_amount` -> **REJECTED**.
17. `Direct UPDATE allocated_amount` -> **REJECTED (0 rows updated)**.
18. `Direct UPDATE spent_amount` -> **REJECTED (0 rows updated)**.
19. `Direct UPDATE budget_id` -> **REJECTED (0 rows updated)**.
20. `Direct DELETE line item` -> **REJECTED (0 rows deleted)**.

### Blackout & Overlap Attacks (21–28)
21. `Direct authenticated INSERT into facility_blackouts` -> **REJECTED / BLOCKED by RLS**.
22. `Cross-society direct INSERT into facility_blackouts` -> **REJECTED / BLOCKED by RLS**.
23. `Forged GUC direct INSERT into facility_blackouts` -> **REJECTED / BLOCKED by RLS**.
24. `Authorized create_facility_blackout procedure execution` -> **PASS**.
25. `Unauthorized create_facility_blackout procedure execution (non-admin)` -> **REJECTED (42501)**.
26. `Create blackout overlapping active amenity booking` -> **REJECTED (22000)**.
27. `Create blackout with invalid time range` -> **REJECTED (23514 / 22000)**.
28. `Concurrent blackout creation through create_facility_blackout(...)` -> **SERIALIZED BY THE DEFINED LOCKING PROTOCOL**.

### Regression & Integrity Assertions (29–35)
29. `Full Slices 1–15 regression suite` -> **434 / 434 PASS**.
30. `Slice 16 workflow procedure assertions` -> **PASS**.
31. `Audit log generation & tampering protection` -> **PASS**.
32. `Notification generation` -> **PASS**.
33. `SECURITY DEFINER catalog properties` -> `SET search_path = public, pg_temp`, `proowner = postgres`.
34. `PUBLIC EXECUTE revocation` -> `FALSE` for all routines.
35. `SHA-256 file integrity verification` -> **RECORD BEFORE/AFTER HASHES IN REMEDIATION LOCK RECORD**.

---

## 8. HASH TRANSITION & REGRESSION ACCOUNTING

### A. SHA-256 File Integrity Verification Protocol
1. **Slice 1–15 Immutable Baseline:** All Slice 1–15 schema/verify/execution files retain their original locked hashes permanently.
2. **Historical Slice 16 Hashes:** Pre-remediation baseline hashes remain permanently recorded in `SLICE16_LOCK_RECORD.md` (`schema_slice16.sql`: `7BC0488A...`, `verify_slice16.sql`: `E630271C...`, `run_all16.ps1`: `77EDFABA...`).
3. **Remediation Execution Protocol:**
   - Immediately prior to authorized modifications, capture BEFORE hashes of `schema_slice16.sql` and `verify_slice16.sql`.
   - Apply minimal approved remediation edits to `database/schema_slice16.sql` and `database/verify_slice16.sql`.
   - Capture AFTER hashes and record exact BEFORE/AFTER hash diff table in `SLICE16_REMEDIATION_LOCK_RECORD.md`.
   - Only explicitly authorized files may change. Any unexpected file modification = **STOP / FAIL**.
   - AFTER hashes become the new remediation baseline only after final verification, audit, regression, and lock.

### B. Regression Accounting
- **Historical Pre-Remediation Cumulative Baseline:** 466 / 466 PASS (Immutable historical evidence)
- **Slices 1–15 Regression Baseline:** 434 / 434 PASS (Immutable baseline)
- **Post-Remediation Slice 16 Test Count:** X / X PASS (Target: 35 / 35 PASS)
- **Post-Remediation Cumulative Total:** 434 + X = Y / Y PASS (e.g. 434 + 35 = 469 / 469 PASS)

---

## 9. EVIDENCE PRESERVATION & CHAIN OF CUSTODY

To maintain absolute evidence preservation and cryptographic chain-of-custody for Slice 16 audit and lock artifacts:

1. **Slice 16 Lock Status:** Slice 16 remains locked in its initial pre-remediation state until explicit user authorization for remediation is granted.
2. **Immutability of Historical Artifacts:** Historical reports (`SLICE16_IMPLEMENTATION_REPORT.md`, `SLICE16_POST_IMPLEMENTATION_SECURITY_AUDIT.md`, `SLICE16_LOCK_RECORD.md`, `SLICE16_POST_LOCK_SECURITY_REVERIFICATION.md`) are immutable audit evidence. They will **NOT be rewritten, edited, reformatted, regenerated, or deleted**.
3. **Hash Tracking & Verification:** Pre-remediation SHA-256 hashes remain permanently recorded. Authorized remediation will capture BEFORE and AFTER SHA-256 hashes in `SLICE16_REMEDIATION_LOCK_RECORD.md`.
4. **Slices 1–15 Baseline Integrity:** All files from Slices 1–15 (`database/schema_slice1.sql`..`15.sql`, `database/verify_slice1.sql`..`15.sql`) remain byte-for-byte identical (434/434 PASS).
5. **Database Evidence Preservation:** Live database DDL/DML state remains completely untouched during this planning phase.
6. **Chain-of-Custody Traceability:**
   ```
   Original Slice 16 Implementation
     ↓
   Original Security Audit (466/466 PASS)
     ↓
   Original Lock Record (SLICE16_LOCK_RECORD.md)
     ↓
   Post-Lock Security Re-Verification (SLICE16_POST_LOCK_SECURITY_REVERIFICATION.md)
     ↓
   Confirmed Vulnerabilities (Gap 1: Vote INSERT, Gap 2: Line Item INSERT, Gap 3: Blackout Direct INSERT & Overlap Status)
     ↓
   Final Corrected Remediation Plan (SLICE16_SECURITY_GAP_REMEDIATION_PLAN.md)
     ↓
   AWAITING EXPLICIT USER REMEDIATION AUTHORIZATION
     ↓
   Future Remediation Artifacts (SLICE16_REMEDIATION_LOCK_RECORD.md, etc.)
   ```

---

## 10. HARD-STOP CONDITIONS

**STOP IMMEDIATELY if any of the following occurs:**
1. Any modification is attempted on Slice 15 schema, functions, triggers, policies, or verification files.
2. Any modification is attempted on immutable historical artifacts (`SLICE16_IMPLEMENTATION_REPORT.md`, `SLICE16_POST_IMPLEMENTATION_SECURITY_AUDIT.md`, `SLICE16_LOCK_RECORD.md`, `SLICE16_POST_LOCK_SECURITY_REVERIFICATION.md`).
3. Any modification is attempted on Slices 1–15 files or `SLICE15_LOCK_RECORD.md`.
4. An unexpected hash change occurs on any untouched baseline file.
5. Remediation execution is initiated without explicit user authorization (`APPROVED — IMPLEMENT SLICE 16 REMEDIATION`).

---

## 11. DECLARATION OF IMMUTABILITY

**No implementation or remediation has occurred during this documentation correction phase.**  
Slice 16 remains locked in its current state until explicit user authorization is granted.

```
STATUS: SLICE 16 REMAINS LOCKED / IMMUTABLE
PLAN CORRECTED: SLICE16_SECURITY_GAP_REMEDIATION_PLAN.md
AWAITING AUTHORIZATION BEFORE ANY CODE / SCHEMA / RLS / FUNCTION MODIFICATION.
```
