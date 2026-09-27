# SLICE 17 — FINAL IMPLEMENTATION PLAN (PART 1 OF 3)

**Document Title:** Slice 17 Final Implementation Plan — Part 1: Architecture, ACL Matrix & Function Specifications  
**Document Version:** 3.1.0  
**Date:** 2026-09-04  
**Status:** PLAN-ONLY / PENDING FINAL USER IMPLEMENTATION APPROVAL  
**Implementation Authorization:** NONE — NO IMPLEMENTATION MAY BEGIN  
**Cumulative Locked Baseline:** Slices 1–16 = 469/469 PASS (100% LOCKED)  

---

## 1. USER-APPROVED DESIGN DECISIONS & GOAL DESCRIPTION

### A. Approved Parcel Lockout Threshold Design Decision
* **User-Approved Rule:** **5 failed collection attempts — USER-APPROVED NEW DESIGN DECISION**  
  ```text
  failed_collection_attempts >= 5 → status = 'locked_failed_attempts'
  ```
* **Decision Context:** In `schema_slice8.sql`, parcel status was strictly `'received_at_gate'`, `'collected'`, `'returned'`. The addition of `failed_collection_attempts` and the lockout threshold of **5 failed attempts** ($5 / 1,000,000 = 0.0005\%$ guess probability) is formally locked as a user-approved design decision. All "3 vs 5" ambiguities are completely removed.

### B. Core Operational Goals
Slice 17 delivers security-hardened DDL, RLS policies, controlled RPC state machines, and `SECURITY DEFINER` workflow routines for six operational domains:
1. **Gate Pass Lifecycle Management (`gate_passes`)**
2. **Parcel & Package Delivery Logistics (`parcel_logs`)**
3. **Emergency SOS Alert Workflows (`sos_alerts`)**
4. **Sub-Meter Utility Consumption Billing Engine (`utility_meters`, `meter_readings`)**
5. **Parking Slot Allocation & Vehicle Registration (`parking_slots`, `vehicles`)**
6. **Digital Community Polls & Voting Engine (`polls`, `poll_votes`)**

---

## 2. LEGACY ROUTINE LIVE-CATALOG HARDENING

The six legacy routines created in Slices 5, 6, 8, 11, and 12 will receive explicit privilege hardening in `database/schema_slice17.sql`:
1. `public.fn_cast_poll_vote(UUID, UUID, VARCHAR)`
2. `public.fn_assign_parking_slot(UUID, UUID)`
3. `public.fn_transition_gate_pass_state(UUID, VARCHAR)`
4. `public.fn_transition_parcel_state(UUID, VARCHAR, VARCHAR)`
5. `public.fn_transition_meter_reading_state(UUID, VARCHAR)`
6. `public.fn_transition_sos_alert(UUID, VARCHAR, TEXT)`

### Executed DDL Statements:
```sql
REVOKE EXECUTE ON FUNCTION public.fn_cast_poll_vote(UUID, UUID, VARCHAR) FROM PUBLIC, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.fn_cast_poll_vote(UUID, UUID, VARCHAR) TO service_role;

REVOKE EXECUTE ON FUNCTION public.fn_assign_parking_slot(UUID, UUID) FROM PUBLIC, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.fn_assign_parking_slot(UUID, UUID) TO service_role;

REVOKE EXECUTE ON FUNCTION public.fn_transition_gate_pass_state(UUID, VARCHAR) FROM PUBLIC, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.fn_transition_gate_pass_state(UUID, VARCHAR) TO service_role;

REVOKE EXECUTE ON FUNCTION public.fn_transition_parcel_state(UUID, VARCHAR, VARCHAR) FROM PUBLIC, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.fn_transition_parcel_state(UUID, VARCHAR, VARCHAR) TO service_role;

REVOKE EXECUTE ON FUNCTION public.fn_transition_meter_reading_state(UUID, VARCHAR) FROM PUBLIC, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.fn_transition_meter_reading_state(UUID, VARCHAR) TO service_role;

REVOKE EXECUTE ON FUNCTION public.fn_transition_sos_alert(UUID, VARCHAR, TEXT) FROM PUBLIC, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.fn_transition_sos_alert(UUID, VARCHAR, TEXT) TO service_role;
```

> [!NOTE]
> **Live-Catalog Hardening Exception Classification:** Executing these SQL DDL statements modifies only the live database object grants in Postgres. All historical source files (`schema_slice5.sql`, `schema_slice6.sql`, etc.) remain 100% byte-for-byte immutable.

---

## 3. COMPLETE 22-ROUTINE ACL MATRIX

Catalog ACL inspection using `has_function_privilege()` across all 6 legacy routines and all 16 new routines:

| # | Routine Name | Exact Signature | PUBLIC | anon | authenticated | service_role | Identity & Authorization Rule |
|---|---|---|---|---|---|---|---|
| 1 | `fn_cast_poll_vote` | `public.fn_cast_poll_vote(uuid, uuid, varchar)` | **REVOKED** | **REVOKED** | **REVOKED** | **GRANTED** | Legacy Routine — Hardened to service_role only |
| 2 | `fn_assign_parking_slot` | `public.fn_assign_parking_slot(uuid, uuid)` | **REVOKED** | **REVOKED** | **REVOKED** | **GRANTED** | Legacy Routine — Hardened to service_role only |
| 3 | `fn_transition_gate_pass_state` | `public.fn_transition_gate_pass_state(uuid, varchar)` | **REVOKED** | **REVOKED** | **REVOKED** | **GRANTED** | Legacy Routine — Hardened to service_role only |
| 4 | `fn_transition_parcel_state` | `public.fn_transition_parcel_state(uuid, varchar, varchar)` | **REVOKED** | **REVOKED** | **REVOKED** | **GRANTED** | Legacy Routine — Hardened to service_role only |
| 5 | `fn_transition_meter_reading_state`| `public.fn_transition_meter_reading_state(uuid, varchar)` | **REVOKED** | **REVOKED** | **REVOKED** | **GRANTED** | Legacy Routine — Hardened to service_role only |
| 6 | `fn_transition_sos_alert` | `public.fn_transition_sos_alert(uuid, varchar, text)` | **REVOKED** | **REVOKED** | **REVOKED** | **GRANTED** | Legacy Routine — Hardened to service_role only |
| 7 | `issue_gate_pass` | `public.issue_gate_pass(uuid, uuid, uuid, timestamptz, timestamptz)` | **REVOKED** | **REVOKED** | **GRANTED** | **GRANTED** | `auth.uid()` active resident of property or admin |
| 8 | `transition_gate_pass_status` | `public.transition_gate_pass_status(uuid, varchar)` | **REVOKED** | **REVOKED** | **GRANTED** | **GRANTED** | `auth.uid()` gatekeeper or admin in target society |
| 9 | `log_parcel_delivery` | `public.log_parcel_delivery(uuid, uuid, varchar, varchar, uuid)` | **REVOKED** | **REVOKED** | **GRANTED** | **GRANTED** | `auth.uid()` gatekeeper or admin in target society |
| 10 | `collect_parcel` | `public.collect_parcel(uuid, varchar)` | **REVOKED** | **REVOKED** | **GRANTED** | **GRANTED** | `auth.uid()` parcel recipient user, gatekeeper, or admin |
| 11 | `trigger_sos_alert` | `public.trigger_sos_alert(uuid, uuid, varchar)` | **REVOKED** | **REVOKED** | **GRANTED** | **GRANTED** | `auth.uid()` active resident of property |
| 12 | `acknowledge_sos_alert` | `public.acknowledge_sos_alert(uuid)` | **REVOKED** | **REVOKED** | **GRANTED** | **GRANTED** | `auth.uid()` gatekeeper or admin in target society |
| 13 | `resolve_sos_alert` | `public.resolve_sos_alert(uuid, varchar, text)` | **REVOKED** | **REVOKED** | **GRANTED** | **GRANTED** | `auth.uid()` gatekeeper or admin in target society |
| 14 | `submit_meter_reading` | `public.submit_meter_reading(uuid, date, numeric)` | **REVOKED** | **REVOKED** | **GRANTED** | **GRANTED** | `auth.uid()` resident of property or staff/admin |
| 15 | `verify_and_bill_meter_reading` | `public.verify_and_bill_meter_reading(uuid)` | **REVOKED** | **REVOKED** | **GRANTED** | **GRANTED** | `auth.uid()` admin in target society |
| 16 | `register_vehicle` | `public.register_vehicle(uuid, uuid, varchar, varchar)` | **REVOKED** | **REVOKED** | **GRANTED** | **GRANTED** | `auth.uid()` property owner/tenant or admin |
| 17 | `assign_parking_slot` | `public.assign_parking_slot(uuid, uuid, uuid)` | **REVOKED** | **REVOKED** | **GRANTED** | **GRANTED** | `auth.uid()` admin in target society |
| 18 | `release_parking_slot` | `public.release_parking_slot(uuid, uuid)` | **REVOKED** | **REVOKED** | **GRANTED** | **GRANTED** | `auth.uid()` admin in target society |
| 19 | `create_community_poll` | `public.create_community_poll(uuid, varchar, text, jsonb, timestamptz, timestamptz)` | **REVOKED** | **REVOKED** | **GRANTED** | **GRANTED** | `auth.uid()` committee or admin in target society |
| 20 | `cast_poll_vote` | `public.cast_poll_vote(uuid, uuid, varchar)` | **REVOKED** | **REVOKED** | **GRANTED** | **GRANTED** | `auth.uid()` active resident of property (one vote per property) |
| 21 | `close_community_poll` | `public.close_community_poll(uuid)` | **REVOKED** | **REVOKED** | **GRANTED** | **GRANTED** | `auth.uid()` admin in target society after end date |
| 22 | `get_poll_results` | `public.get_poll_results(uuid)` | **REVOKED** | **REVOKED** | **GRANTED** | **GRANTED** | `auth.uid()` member of society (closed/ended) or admin (active) |

---

## 4. COMPLETE MUTATION SECURITY MATRIX FOR ALL 9 TABLES

PostgreSQL evaluates permissive policies with `OR` logic and restrictive policies with `AND` logic:

| Table Name | Direct SQL INSERT | Direct SQL SELECT | Direct SQL UPDATE | Direct SQL DELETE | RLS & Trigger Enforcement Mechanism |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `gate_passes` | Blocked (`42501`) | Resident / Admin Scope | 0 Rows (`00000`) | 0 Rows (`00000`) | RESTRICTIVE `WITH CHECK (false)` & `USING (false)` + Trigger `trg_prevent_direct_gate_pass_update` |
| `parcel_logs` | Blocked (`42501`) | Recipient / Gatekeeper | 0 Rows (`00000`) | 0 Rows (`00000`) | RESTRICTIVE RLS `pol_parcel_update_none` & `pol_parcel_delete_none` |
| `sos_alerts` | Blocked (`42501`) | Admin / Resident | 0 Rows (`00000`) | 0 Rows (`00000`) | RESTRICTIVE RLS `pol_sos_restrictive_insert` & Trigger `trg_protect_sos_status_update` |
| `utility_meters` | Admin (`00000`) / Client (`42501`)| Society Scope | Admin (`00000`) / Client (`00000`)| 0 Rows (`00000`) | PERMISSIVE Admin Policy + RESTRICTIVE Delete `USING (false)` |
| `meter_readings` | Blocked (`42501`) | Property Scope | 0 Rows (`00000`) | 0 Rows (`00000`) | RESTRICTIVE `WITH CHECK (false)` + Trigger `trg_prevent_direct_meter_reading_update` |
| `parking_slots` | Admin (`00000`) / Client (`42501`)| Society Scope | Admin (`00000`) / Client (`00000`)| 0 Rows (`00000`) | PERMISSIVE Admin Policy + RESTRICTIVE Update/Delete `USING (false)` |
| `vehicles` | Blocked (`42501`) | Society Scope | 0 Rows (`00000`) | Owner (`00000`) / Non-Owner (`00000`) | RESTRICTIVE Update `WITH CHECK (false)` + Auto-release trigger |
| `polls` | Blocked (`42501`) | Society Scope | 0 Rows (`00000`) | 0 Rows (`00000`) | RESTRICTIVE `pol_polls_restrictive_insert`, `update`, `delete` |
| `poll_votes` | Blocked (`42501`) | Own Vote (Member) / All (Admin)| 0 Rows (`00000`) | 0 Rows (`00000`) | RESTRICTIVE RLS `USING(false)` for UPDATE and DELETE; `trg_prevent_vote_mutations` installed as defense-in-depth for privileged bypass paths |

---

## 5. SECURITY DEFINER FUNCTION SPECIFICATIONS (ALL 16 ROUTINES)

All 16 new workflow functions enforce:
* `SECURITY DEFINER`
* Owner: `postgres`
* `SET search_path = public, pg_temp`
* Explicit schema qualification (`public.`)
* Explicit privilege revocation from `PUBLIC`, `anon`, `authenticated` (unless granted to `authenticated` / `service_role`).

### Function Specifications:

1. **`public.issue_gate_pass(p_society_id UUID, p_property_id UUID, p_staff_id UUID, p_valid_from TIMESTAMPTZ, p_valid_until TIMESTAMPTZ)`**:
   * **Purpose:** Creates a gate pass for a daily staff member/service provider.
   * **Authorization:** Verifies `auth.uid()` is active owner/tenant of `p_property_id` or society admin.
   * **Validation:** Verifies `p_staff_id` belongs to `p_society_id` and `p_valid_from < p_valid_until`.
   * **Status Determination:** Auto-approves for resident requests (`status = 'active'`) if staff is verified (`verification_status = 'verified'`); sets `pending` otherwise.
   * **Output:** Returns created `gate_passes.id`. (SQLSTATE `00000` / `42501` / `23514`).

2. **`public.transition_gate_pass_status(p_pass_id UUID, p_new_status VARCHAR)`**:
   * **Purpose:** Transitions gate pass state between `'pending'`, `'active'`, and `'suspended'`.
   * **Authorization:** Gatekeeper or Admin in target society; Resident for pass belonging to their property.
   * **State Transition Rules:** `pending` $\rightarrow$ `active` (requires verified staff), `active` $\rightarrow$ `suspended`, `suspended` $\rightarrow$ `active` (requires verified staff). (SQLSTATE `00000` / `42501` / `22000`).

3. **`public.log_parcel_delivery(p_society_id UUID, p_property_id UUID, p_carrier_name VARCHAR, p_tracking_number VARCHAR, p_recipient_user_id UUID)`**:
   * **Purpose:** Gatekeeper logs incoming parcel delivery.
   * **Authorization:** Verifies `auth.uid()` has role `'gatekeeper'`, `'admin'`, or `'super_admin'` in `p_society_id`.
   * **CSPRNG Sampling:** Generates 6-digit code via 4-byte rejection sampling over 32-bit `public.gen_random_bytes(4)` ($v < 4,294,000,000$).
   * **Storage:** Stores SHA-256 hash in `collection_code_hash`; sets `collection_code = NULL`. Returns raw code ONLY to caller. (SQLSTATE `00000` / `42501` / `23503`).

4. **`public.collect_parcel(p_parcel_id UUID, p_collection_code VARCHAR)`**:
   * **Purpose:** Validates collection code and marks parcel collected.
   * **Authorization:** Recipient user (`auth.uid() = recipient_user_id`) or Gatekeeper/Admin.
   * **Locking & Attempt Counter:** Row locked (`FOR UPDATE`). Compares `encode(digest(p_collection_code, 'sha256'), 'hex')` against `collection_code_hash`. On failure, increments `failed_collection_attempts`. At 5 failures, transitions `status = 'locked_failed_attempts'`. Counter increment commits transactionally. (SQLSTATE `00000` / `22000`).

5. **`public.trigger_sos_alert(p_society_id UUID, p_property_id UUID, p_alert_type VARCHAR)`**:
   * **Purpose:** Triggers emergency SOS alert for a property.
   * **Authorization:** `auth.uid()` active resident of `p_property_id`.
   * **Concurrency Protection:** Unique partial index `uq_active_sos_alert_property` prevents duplicate active alerts. Dispatches notifications. (SQLSTATE `00000` / `42501` / `23505`).

6. **`public.acknowledge_sos_alert(p_alert_id UUID)`**:
   * **Purpose:** Gatekeeper or Admin acknowledges an active SOS alert (`status = 'triggered'`).
   * **Authorization:** Gatekeeper or Admin in target society. Sets `status = 'acknowledged'`, `acknowledged_by = auth.uid()`, `acknowledged_at = NOW()`. (SQLSTATE `00000` / `42501` / `22000`).

7. **`public.resolve_sos_alert(p_alert_id UUID, p_resolution_status VARCHAR, p_resolution_notes TEXT)`**:
   * **Purpose:** Resolves SOS alert (`status = 'resolved'` or `'false_alarm'`).
   * **Authorization:** Gatekeeper or Admin in target society. Requires non-empty `p_resolution_notes`. Sets `resolved_by = auth.uid()`, `resolved_at = NOW()`. (SQLSTATE `00000` / `42501` / `22000`).

8. **`public.submit_meter_reading(p_meter_id UUID, p_reading_date DATE, p_current_reading NUMERIC)`**:
   * **Purpose:** Submits utility sub-meter consumption reading.
   * **Authorization:** Resident of meter property or Staff/Admin.
   * **Validation:** Verifies `reading_date > previous_reading_date` and `current_reading >= previous_reading`. Calculates `consumption` and `total_charge` using captured `utility_meters.unit_rate`. Sets `status = 'draft'`. (SQLSTATE `00000` / `42501` / `22000`).

9. **`public.verify_and_bill_meter_reading(p_reading_id UUID)`**:
   * **Purpose:** Admin verifies reading and posts debit transaction to `public.ledger_transactions`.
   * **Authorization:** Society Admin.
   * **Billing Atomicity:** Row locked (`FOR UPDATE`). Verifies `status = 'draft'`. Captures `applied_unit_rate`. Inserts debit row into `public.ledger_transactions` (`transaction_type = 'utility_bill'`). On FK failure (`23503`), PL/pgSQL transaction aborts cleanly and reading status rolls back to `'draft'`. (SQLSTATE `00000` / `42501` / `23503`).

10. **`public.register_vehicle(p_society_id UUID, p_property_id UUID, p_registration_number VARCHAR, p_vehicle_type VARCHAR)`**:
    * **Purpose:** Registers vehicle for property.
    * **Authorization:** Property Owner/Tenant or Admin. Enforces unique registration number per society. (SQLSTATE `00000` / `42501` / `23505`).

11. **`public.assign_parking_slot(p_society_id UUID, p_parking_slot_id UUID, p_vehicle_id UUID)`**:
    * **Purpose:** Admin assigns vacant parking slot to vehicle under canonical lock ordering (`parking_slots` then `vehicles`).
    * **Authorization:** Society Admin. Atomically updates `parking_slots.assigned_vehicle_id = p_vehicle_id` and `vehicles.parking_slot_id = p_parking_slot_id`. Preserves `parking_slots.property_id`. (SQLSTATE `00000` / `42501` / `23505`).

12. **`public.release_parking_slot(p_society_id UUID, p_parking_slot_id UUID)`**:
    * **Purpose:** Admin releases vehicle assignment from parking slot under canonical lock ordering (`parking_slots` then `vehicles`).
    * **Authorization:** Society Admin. Sets `vehicles.parking_slot_id = NULL` and `parking_slots.assigned_vehicle_id = NULL`. Permanent deeded `parking_slots.property_id` is **NEVER** set to NULL. (SQLSTATE `00000` / `42501`).

13. **`public.create_community_poll(p_society_id UUID, p_title VARCHAR, p_description TEXT, p_options JSONB, p_starts_at TIMESTAMPTZ, p_ends_at TIMESTAMPTZ)`**:
    * **Purpose:** Creates digital community poll with validated option set.
    * **Authorization:** Committee member or Admin in target society. Validates `p_options` via `public.fn_validate_poll_options(p_options)` helper function. (SQLSTATE `00000` / `42501` / `23514`).

14. **`public.cast_poll_vote(p_poll_id UUID, p_property_id UUID, p_vote_choice VARCHAR)`**:
    * **Purpose:** Resident casts vote for property.
    * **Authorization:** Active resident of `p_property_id`. Verifies `v_poll.status = 'active'`, `NOW() BETWEEN starts_at AND ends_at`, option validity against `v_poll.options`, and enforces `uq_poll_property_vote`. (SQLSTATE `00000` / `42501` / `23505` / `22000`).

15. **`public.close_community_poll(p_poll_id UUID)`**:
    * **Purpose:** Admin closes poll after `ends_at`.
    * **Authorization:** Society Admin. Verifies `NOW() >= ends_at`. Updates `status = 'closed'`. (SQLSTATE `00000` / `42501` / `22000`).

16. **`public.get_poll_results(p_poll_id UUID)`**:
    * **Purpose:** Returns aggregate vote choice tallies and percentages.
    * **Authorization:** Society Member (for `closed`/ended polls) or Admin (for `active` polls). Rejects active poll queries from non-admin residents with SQLSTATE `22000` to preserve confidentiality. Includes zero-vote options and zero-division protection. (SQLSTATE `00000` / `42501` / `22000`).

---

## 6. HELPER FUNCTION SPECIFICATION (`fn_validate_poll_options`)

* **Function Signature:** `public.fn_validate_poll_options(p_options JSONB) RETURNS BOOLEAN`
* **Attributes:** `IMMUTABLE`, `LANGUAGE plpgsql`, `SET search_path = public, pg_temp`
* **Validation Logic:**
  1. `jsonb_typeof(p_options) = 'array'`. Returns `FALSE` for non-arrays (objects, numbers, booleans, strings, nulls).
  2. `jsonb_array_length(p_options) >= 2`. Returns `FALSE` for 0 or 1 element arrays.
  3. Every element must be a string with non-zero length after trimming whitespace.
  4. Case and whitespace normalization via `lower(trim(elem_text))`. Unique normalized count MUST equal total element count.
* **Test Case Assertions:**
  * Rejects `[]`, `["Option A"]`, `["YES", "yes"]`, `[" YES ", "YES"]`, `["   ", "Option B"]`, `["", "Option B"]`, `["Option A", null]`, `["Option A", 123]`, `["Option A", true]`, `["Option A", {}]`, `["Option A", ["nested"]]`.
* **IMMUTABLE Validity Justification:** Operating `lower(trim(...))` on JSON text elements without locale-specific collations is an immutable string transformation in PostgreSQL C-locale/UTF-8.

---

*(Continued in Part 2 & Part 3)*
