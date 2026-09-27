# SLICE 17 — FINAL IMPLEMENTATION PLAN (PART 2 OF 3)

**Document Title:** Slice 17 Final Implementation Plan — Part 2: Security Models, State Machines & Concurrency Specifications  
**Document Version:** 3.1.0  
**Date:** 2026-09-04  
**Status:** PLAN-ONLY / PENDING FINAL USER IMPLEMENTATION APPROVAL  
**Implementation Authorization:** NONE — NO IMPLEMENTATION MAY BEGIN  
**Cumulative Locked Baseline:** Slices 1–16 = 469/469 PASS (100% LOCKED)  

---

## 7. PARCEL SECURITY SPECIFICATIONS & 5-ATTEMPT SEQUENCE

* **Code Generation:** Raw collection code generated using CSPRNG 4-byte rejection sampling over 32-bit `public.gen_random_bytes(4)` calls ($v < 4,294,000,000$).
* **Hash Storage:** `collection_code` column set to `NULL` (`CHECK (collection_code IS NULL)`). Only SHA-256 hash `collection_code_hash` (`VARCHAR(64)`) is persisted.
* **Zero Log Leakage:** Plaintext collection code is never stored in `audit_logs`, `notifications`, exception text, or returned query strings.

### Explicit 5-Attempt Lockout Sequence (Assertion 19 Specification):

| Attempt # | Supplied Code | Transaction Execution | Returned `p_success` | Returned `p_status` | Database `failed_collection_attempts` | Transaction Status |
|---|---|---|---|---|---|---|
| **Attempt 1** | `'000000'` (Wrong) | Executed & Committed | `FALSE` | `'received_at_gate'` | `1` | Committed |
| **Attempt 2** | `'111111'` (Wrong) | Executed & Committed | `FALSE` | `'received_at_gate'` | `2` | Committed |
| **Attempt 3** | `'222222'` (Wrong) | Executed & Committed | `FALSE` | `'received_at_gate'` | `3` | Committed |
| **Attempt 4** | `'333333'` (Wrong) | Executed & Committed | `FALSE` | `'received_at_gate'` | `4` | Committed |
| **Attempt 5** | `'444444'` (Wrong) | Executed & Committed | `FALSE` | `'locked_failed_attempts'` | `5` | Committed |
| **Post-Lockout**| Correct Code | Executed & Rejected | `FALSE` | `'locked_failed_attempts'` | `5` (Locked) | SQLSTATE `22000` / Error Message |

---

## 8. SERVICE-ROLE CONTEXT SIMULATION SPECIFICATION (ASSERTION 82)

* **Verification Context:** In `verify_slice17.sql`, service-role context is tested by executing:
  ```sql
  SET LOCAL ROLE service_role;
  SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);
  ```
* **Security & Trust Boundary Classification:**
  * `SET LOCAL ROLE service_role` is a **Database-Layer Context Simulation**.
  * JWT claim GUCs used in the test script are test context, not cryptographic proof.
  * The test verifies database role privileges and authorization behavior.
  * It does **NOT** constitute HTTP/PostgREST end-to-end JWT verification.
  * Production trust depends on the trusted Supabase/PostgREST authentication boundary.
  * Client-controlled GUC values must never be trusted for privilege escalation in client RPC calls.

---

## 9. GATE PASS AUTHORIZATION STATE MACHINE

Inspection of `database/schema_slice6.sql` (Line 37 & 117–137) defines the exact actor matrix and state transitions.

**Blocker 3 Resolution (Security-Preferred Default — LOCKED):** Property Residents MAY suspend an active pass, but MUST NOT reactivate a suspended pass. Reactivation is granted exclusively to Admins and Gatekeepers.

| Current Status | Target Status | Authorized Roles | Prerequisite Verification Condition | Security Policy |
| :--- | :--- | :--- | :--- | :--- |
| `pending` | `active` | Admin, Gatekeeper | Staff `verification_status = 'verified'` | Production Rule |
| `active` | `suspended` | Admin, Gatekeeper, Property Resident | Target pass belongs to caller's property/society | Production Rule |
| `suspended` | `active` | Admin, Gatekeeper | Staff `verification_status = 'verified'` | Production Rule |
| `suspended` | `active` | Property Resident | N/A | **BLOCKED — Residents cannot reactivate suspended passes** |

---

## 10. PARKING / VEHICLE CONCURRENCY SPECIFICATIONS (MODEL A)

* **Deeded Property Allocation:** `parking_slots.property_id` represents permanent deeded property allocation and is **NEVER** set to `NULL` during slot release or vehicle deletion.
* **Reciprocal Pointers:** `parking_slots.assigned_vehicle_id = V1` $\iff$ `vehicles.parking_slot_id = S1`.
* **Auto-Release Trigger:** Deleting a vehicle fires `trg_vehicles_auto_release_parking`, unlinking `assigned_vehicle_id = NULL` and `parking_slot_id = NULL` while preserving `parking_slots.property_id`.
* **Canonical Lock Order:** All assignment and release operations lock `parking_slots` rows first (`FOR UPDATE ORDER BY id`), then `vehicles` rows (`FOR UPDATE ORDER BY id`) to prevent deadlocks.
* **Direct Modification Block:** Direct resident modification of `vehicles.parking_slot_id` is blocked by RESTRICTIVE RLS `pol_vehicles_restrictive_update`.

---

## 11. UTILITY BILLING & LEDGER INTEGRITY SPECIFICATIONS

* **Monotonic Readings:** `submit_meter_reading` requires `reading_date > previous_reading_date` and `current_reading >= previous_reading`.
* **Rate Capture:** `applied_unit_rate` is captured into `meter_readings` at reading creation/verification time and remains stable even if `utility_meters.unit_rate` changes later.
* **Ledger Debit Target:** `verify_and_bill_meter_reading` derives debit user target from active property occupant/owner mapping. User ID cannot be fabricated.
* **Atomic Rollback:** If posting to `ledger_transactions` fails due to FK violation (`23503`), entire PL/pgSQL transaction aborts cleanly: reading status rolls back to `'draft'`, 0 ledger rows, 0 audit rows, 0 notification rows survive.

---

## 12. COMMUNITY POLL SECURITY SPECIFICATIONS

* **Option Validation (`fn_validate_poll_options`):** Input MUST be JSON array with length $\ge 2$. Elements MUST be non-blank strings. Normalization via `lower(trim(elem_text))` rejects case/whitespace duplicates (`["YES", "yes"]`).
* **One-Vote-Per-Property:** Enforced by unique constraint `uq_poll_property_vote(poll_id, property_id)`.
* **Confidentiality:** `get_poll_results` suppresses vote tallies for active polls when invoked by non-admin members. Closed/ended polls show aggregate tallies with zero-vote option inclusion and zero-division protection.

---

## 13. EMERGENCY SOS ALERT STATE MACHINE

* **Valid States:** `'triggered'`, `'acknowledged'`, `'resolved'`, `'false_alarm'`.
* **Valid Transitions:**
  * `triggered` $\rightarrow$ `acknowledged` (By Gatekeeper or Admin via `acknowledge_sos_alert`)
  * `triggered` $\rightarrow$ `resolved` / `false_alarm` (By Gatekeeper or Admin via `resolve_sos_alert`)
  * `acknowledged` $\rightarrow$ `resolved` / `false_alarm` (By Gatekeeper or Admin via `resolve_sos_alert`)
* **Terminal States:** `'resolved'` and `'false_alarm'` are terminal.
* **Notes Rule:** `resolve_sos_alert` requires non-empty `resolution_notes`.

---

*(Continued in Part 3)*
