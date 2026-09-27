# SU Society App — Slice 9 Pre-Implementation Audit & Discovery

## 1. Executive Summary

This report outlines the **Pre-Implementation Discovery & Audit** for Slice 9 of the SU Society App. The entire repository was audited to establish the exact, ground-truth implementation state across the database, mock data, and UI.

The locked Phase 1-3B baseline (Slices 1–8) has been rigorously verified and remains 100% intact (265/265 true assertions passing).

Based on the actual implemented backend schema, the most logical and cohesive boundary for **Slice 9** is **Security Operations & Compliance**, focusing on tracking physical staff presence (`staff_attendance_logs`) and enforcing society rules (`rule_violations` with financial penalty integration). This directly resolves two major "dangling" dependencies in the current architecture.

---

## 2. Current Repository State

**OBSERVED STATE:**
- **Database Backend:** Slices 1 through 8 are fully implemented in PostgreSQL with robust RLS, triggers, security definer functions, and comprehensive test coverage.
- **Mock / JavaScript Client:** `src/supabase.js` (`INITIAL_MOCK_DATA`) only contains data up to Phase 3A (`visitor_logs`, `helpdesk_tickets`). Slices 6, 7, and 8 have *no mock data representation*.
- **Frontend / React UI:** `src/App.jsx` has *no UI implementation* for Slices 6, 7, and 8. The frontend remains entirely unaware of Staff, Gate Passes, Vendors, Assets, Move Requests, and Parcels.

---

## 3. Locked Baseline Verification

The existing verification suite (`run_all8.ps1`) was executed against the actual database.

- **Slice 1:** 97/97 PASS
- **Slice 2:** 34/34 PASS
- **Slice 3:** 19/19 PASS
- **Slice 4:** 40/40 PASS
- **Slice 5:** 20/20 PASS
- **Slice 6:** 21/21 PASS
- **Slice 7:** PASS (100%)
- **Slice 8:** 34/34 PASS (incorporating new elevated security tests)
- **Combined:** 265/265 PASS (Confirmed)

**Result:** The locked baseline is structurally sound and secure.

---

## 4. Implemented Domain Inventory

**VERIFIED COMPLETE (Database Level):**
1. **Core:** `societies`, `users`, `user_roles`, `properties`, `units`, `property_owners`, `tenancies`, `family_groups`, `occupants`, `audit_logs`
2. **Billing:** `maintenance_policies`, `custom_billing`, `maintenance_charges`, `opening_balances`, `ledger_transactions`
3. **Payments:** `payments`, `payment_allocations`, `receipts`
4. **Expenses:** `expense_categories`, `budgets`, `expense_vouchers`, `bank_reconciliations`
5. **Community:** `notices`, `polls`, `poll_votes`, `parking_slots`, `vehicles`, `documents`
6. **Facilities & Helpdesk:** `amenities`, `amenity_bookings`, `technician_tickets`, `ticket_comments`, `visitor_logs`
7. **Staff Operations:** `daily_staff`, `gate_passes`
8. **Asset Management:** `vendors`, `vendor_bank_details`, `assets`, `asset_amc`
9. **Logistics:** `move_requests`, `parcel_logs`

---

## 5. Incomplete / Pending Functionality

**OBSERVED GAPS:**
1. **Rule Violations & Penalties:** `schema_phase2.sql` defines `penalty` and `waiver` as valid `transaction_type`s in the `ledger_transactions` table. However, there is no domain table or state machine to issue, track, or appeal rule violations.
2. **Staff Attendance:** Slice 6 introduced `daily_staff` (verification) and `gate_passes` (validity). However, there is no mechanism for the security gate to actually log the daily IN/OUT attendance of these staff members (unlike `visitor_logs`).
3. **Meetings & Governance:** No tables exist for AGM/EGM scheduling, agendas, or resolutions (often paired with `polls`).
4. **Frontend Alignment:** Huge gap between the backend schema and the React UI for all Operations modules.

---

## 6. Candidate Slice 9 Domains

1. **Candidate A: Security Operations & Compliance (Backend)**
   - Completes the physical security loop (Staff Attendance).
   - Completes the financial compliance loop (Rule Violations -> Penalties).
2. **Candidate B: Society Governance (Backend)**
   - Meetings, Agendas, Minutes, Resolutions.
3. **Candidate C: Frontend Operations Integration (Frontend/Mock)**
   - Wiring Slices 6-8 into `INITIAL_MOCK_DATA` and `App.jsx`.

---

## 7. Dependency Analysis for Candidate A (Security Operations & Compliance)

- **`staff_attendance_logs`:**
  - Depends on: `daily_staff` (staff identity), `gate_passes` (must have an active pass to check in), `societies`.
  - Security impact: Extends gatekeeper capabilities.

- **`rule_violations`:**
  - Depends on: `properties` (violator), `users` (reporter/admin), `societies`, `ledger_transactions` (for financial penalty generation).
  - Financial impact: Transitioning a violation to `penalized` must strictly insert a `penalty` ledger transaction via a `SECURITY DEFINER` function to maintain the append-only ledger invariant.

---

## 8. Recommended Slice 9 Scope

**PROPOSED:** Implement Candidate A as the backend **Slice 9**.

### Justification:
The backend must reach full functional completeness before undergoing a massive UI wiring phase. Implementing **Staff Attendance** closes the logical gap created by Slice 6 (Gate Passes). Implementing **Rule Violations** closes the architectural gap defined in Phase 2 (the `penalty` transaction type).

---

## 9. Proposed Schema Changes

**PROPOSED TABLES:**

1. **`staff_attendance_logs`**
   - `id` UUID PK
   - `society_id` UUID FK
   - `staff_id` UUID FK (`daily_staff`)
   - `gate_pass_id` UUID FK (`gate_passes`)
   - `check_in` TIMESTAMPTZ
   - `check_out` TIMESTAMPTZ (nullable)
   - `logged_by` UUID FK (gatekeeper/admin who logged entry)

2. **`rule_violations`**
   - `id` UUID PK
   - `society_id` UUID FK
   - `property_id` UUID FK (offending property)
   - `reported_by` UUID FK (resident/staff/admin)
   - `violation_type` VARCHAR (e.g., 'parking', 'noise', 'facility_abuse', 'other')
   - `description` TEXT
   - `status` VARCHAR ('reported', 'under_review', 'penalized', 'dismissed', 'resolved')
   - `penalty_amount` NUMERIC(10,2) DEFAULT 0
   - `ledger_transaction_id` UUID FK (link to financial penalty, nullable)

---

## 10. Proposed Functions / Triggers

**PROPOSED:**
- `fn_staff_check_in(staff_id)`: Verifies active gate pass, ensures no open check-in, creates log.
- `fn_staff_check_out(log_id)`: Closes the attendance log.
- `fn_transition_violation_state(violation_id, new_status, optional_amount)`: Handles state machine. If `penalized`, it safely inserts into `ledger_transactions` using existing invariants.

**Triggers:**
- `trg_prevent_direct_violation_status_update`: Blocks raw SQL `UPDATE` to the `status` column unless executed via the authorized state machine function.
- `trg_audit_rule_violations` & `trg_audit_staff_attendance_logs`: Standard audit triggers.

---

## 11. Proposed State Machines

**Rule Violations:**
- `reported` -> `under_review` (Admin acknowledges)
- `under_review` -> `penalized` (Admin levies fine -> triggers ledger insert)
- `under_review` -> `dismissed` (Admin rejects complaint)
- `penalized` -> `resolved` (Once penalty is paid, or administratively closed)
- *Illegal Transitions:* `reported` -> `resolved`, `penalized` -> `dismissed`.

**Staff Attendance:**
- Simple lifecycle: `check_in` (creation) -> `check_out` (terminal update).

---

## 12. Proposed RLS / Authorization Model

**`staff_attendance_logs`:**
- **Admin:** ALL
- **Gatekeeper:** SELECT, INSERT (via function), UPDATE (via function for checkout).
- **Resident:** SELECT (Only for staff actively assigned to their property via `gate_passes`).

**`rule_violations`:**
- **Admin:** ALL (Transitions via function).
- **Resident:** SELECT (If they are the reporter or the violator property owner/tenant). INSERT (Can report). UPDATE (None directly).

---

## 13. Proposed Audit Requirements

- All inserts, updates, and deletes to `rule_violations` must be logged in `audit_logs`.
- All inserts and updates to `staff_attendance_logs` must be logged.
- No uniquely sensitive PII requires redaction in these specific tables (staff identity is already managed and redacted in `daily_staff`).

---

## 14. Proposed Financial Integrity Rules

- Applying a penalty (`status = 'penalized'`) MUST be encapsulated within a `SECURITY DEFINER` function.
- The function MUST insert a row into `ledger_transactions` with `transaction_type = 'penalty'`, `direction = 'debit'`, and the respective `property_id`.
- The ledger transaction ID must be written back to `rule_violations.ledger_transaction_id` to prevent double-penalization.

---

## 15. Proposed Indexes / Constraints

- **Indexes:** `idx_attendance_staff_id`, `idx_attendance_society_id`, `idx_violations_property_id`, `idx_violations_status`.
- **Constraints:**
  - `chk_attendance_times`: `check_out IS NULL OR check_out >= check_in`.
  - `chk_violation_status`: Enum values restriction.
  - `chk_violation_penalty`: `penalty_amount >= 0`.

---

## 16. Security Threat Model

- **Threat:** Malicious actor modifies a rule violation to dismiss a penalty without paying.
  - **Mitigation:** RLS blocks direct updates. Status triggers block bypasses.
- **Threat:** Gatekeeper logs attendance for a suspended staff member.
  - **Mitigation:** The `fn_staff_check_in` function explicitly joins with `gate_passes` to ensure `status = 'active'` and `valid_until > NOW()`.

---

## 17. Elevated Execution Security Model

Following the strict standards established in Slice 8:
- Direct state mutations via `UPDATE` by elevated roles (or SQL comments/literal injections) will be blocked.
- The `fn_transition_violation_state` function will set a transaction-local configuration variable (`app.violation_transition = violation_id`).
- The `BEFORE UPDATE` trigger on `rule_violations` will strictly assert that `current_setting('app.violation_transition', true)` exactly matches `NEW.id::text`.

---

## 18. Proposed Verification Tests

**Functional & Negative:**
- Gatekeeper can check-in staff with active pass.
- Gatekeeper CANNOT check-in staff with suspended/expired pass.
- Double check-in blocked.
- Resident can report violation.
- Admin can transition violation to `under_review`.

**Security & RLS:**
- Cross-society isolation blocks for attendance and violations.
- Resident cannot view other properties' violations.
- Elevated Direct UPDATE blocked without context (Tests A-D strings).

**Integrity:**
- Transition to `penalized` successfully creates a `debit` `penalty` in `ledger_transactions`.
- Ensure penalty ledger entry cannot be modified (existing Slice 2 triggers backstop this).

---

## 19. Estimated Assertion Count

**ESTIMATED:**
- Staff Attendance Tests: 12
- Rule Violations & Penalty Tests: 15
- Security / Elevated Bypasses: 8
- **Total Proposed Slice 9 Assertions:** ~35

---

## 20. Regression Strategy

- Run `scratch/run_all8.ps1` before execution.
- Create `verify_slice9.sql`.
- Create `scratch/run_all9.ps1` to execute Slices 1–9 sequentially.
- Baseline must remain 265/265. Total expected outcome: ~300/300 PASS.

---

## 21. Files Expected to Change

- **NEW:** `database/schema_slice9.sql`
- **NEW:** `database/verify_slice9.sql`
- **NEW:** `scratch/run_all9.ps1`

---

## 22. Files That MUST Remain Untouched

- `database/schema_slice1.sql` through `database/schema_slice8.sql`
- `database/verify_slice1.sql` through `database/verify_slice8.sql`
- All application source files (until a dedicated Frontend slice is authorized).

---

## 23. Risks / Open Questions

- **Question:** Should a penalty waiver (`waiver` transaction type) be implemented within this slice, or should waivers remain a generic ledger adjustment operation for the Admin?
  - *Recommendation:* Keep it generic for now to constrain Slice 9 scope. If an admin dismisses a violation *after* it was penalized, they can manually issue a waiver via the existing billing module.

---

## 24. Approval Gate

### READY FOR USER APPROVAL
