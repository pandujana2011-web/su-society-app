# SLICE 17 — FINAL IMPLEMENTATION PLAN v3.3

```text
STATUS:                   PLAN-ONLY / PENDING FINAL USER IMPLEMENTATION APPROVAL
IMPLEMENTATION AUTH:      NONE
LOCKED BASELINE:          SLICES 1–16 = 469/469 PASS
SLICE 17 ASSERTIONS:      82
PLANNED CUMULATIVE SCORE: 551
SECTIONS:                 20

NO APPLICATION OR DATABASE IMPLEMENTATION MAY BEGIN UNTIL EXPLICIT USER APPROVAL.
```

**Document Version:** 3.3.1 (Evidence-Quality Cleanup)  
**Date:** 2026-09-04  
**Supersedes:** v3.3.0, Parts 1/2/3 v3.1.0, Correction Reports v3.2.0  

> [!IMPORTANT]
> This is the single authoritative Slice 17 plan document. All previous part files (Part 1, Part 2, Part 3 v3.1.0) and all intermediate correction reports are superseded by this document. Do not reference prior versions.

---

## 1. USER-APPROVED DESIGN DECISIONS & GOAL DESCRIPTION

### A. Parcel Lockout Threshold — USER-APPROVED DESIGN DECISION

```text
failed_collection_attempts >= 5  →  status = 'locked_failed_attempts'
```

The threshold of **5 failed collection attempts** is explicitly user-approved. All prior "3 vs 5" ambiguities are permanently eliminated.

### B. Gate Pass Resident Reactivation — SECURITY-PREFERRED DEFAULT (LOCKED)

Property Residents **MAY** suspend an active pass. Property Residents **MUST NOT** reactivate a suspended pass. Reactivation is granted exclusively to Admins and Gatekeepers with verified staff prerequisites.

### C. poll_votes Direct Mutation Security (CORRECTED — LOCKED)

For ordinary authenticated clients:

* Direct `UPDATE` on `poll_votes` is denied by RESTRICTIVE RLS `USING (false)` → **0 rows updated, SQLSTATE `00000`**.
* Direct `DELETE` on `poll_votes` is denied by RESTRICTIVE RLS `USING (false)` → **0 rows deleted, SQLSTATE `00000`**.
* Trigger `trg_prevent_vote_mutations` is installed as **defense-in-depth** for privileged/RLS-bypass execution paths. It is **NOT** the ordinary authenticated-client denial mechanism.

### D. Core Operational Goals

Slice 17 delivers security-hardened DDL, RLS policies, controlled RPC state machines, and `SECURITY DEFINER` workflow routines for six operational domains:

1. **Gate Pass Lifecycle Management** (`gate_passes`)
2. **Parcel & Package Delivery Logistics** (`parcel_logs`)
3. **Emergency SOS Alert Workflows** (`sos_alerts`)
4. **Sub-Meter Utility Consumption Billing** (`utility_meters`, `meter_readings`)
5. **Parking Slot Allocation & Vehicle Registration** (`parking_slots`, `vehicles`)
6. **Digital Community Polls & Voting Engine** (`polls`, `poll_votes`)

---

## 2. LEGACY ROUTINE LIVE-CATALOG HARDENING

Six legacy routines created in Slices 5, 6, 8, 11, and 12 will receive explicit privilege hardening in `database/schema_slice17.sql`.

> [!NOTE]
> **Live-Catalog Hardening Exception:** These DDL statements modify only live database object grants. All historical source files (`schema_slice5.sql`, `schema_slice6.sql`, etc.) remain byte-for-byte immutable.

**Routines to harden:**

1. `public.fn_cast_poll_vote(UUID, UUID, VARCHAR)`
2. `public.fn_assign_parking_slot(UUID, UUID)`
3. `public.fn_transition_gate_pass_state(UUID, VARCHAR)`
4. `public.fn_transition_parcel_state(UUID, VARCHAR, VARCHAR)`
5. `public.fn_transition_meter_reading_state(UUID, VARCHAR)`
6. `public.fn_transition_sos_alert(UUID, VARCHAR, TEXT)`

**DDL to execute (per routine):**

```sql
REVOKE EXECUTE ON FUNCTION public.fn_cast_poll_vote(UUID, UUID, VARCHAR)
  FROM PUBLIC, authenticated, anon;
GRANT  EXECUTE ON FUNCTION public.fn_cast_poll_vote(UUID, UUID, VARCHAR)
  TO service_role;

REVOKE EXECUTE ON FUNCTION public.fn_assign_parking_slot(UUID, UUID)
  FROM PUBLIC, authenticated, anon;
GRANT  EXECUTE ON FUNCTION public.fn_assign_parking_slot(UUID, UUID)
  TO service_role;

REVOKE EXECUTE ON FUNCTION public.fn_transition_gate_pass_state(UUID, VARCHAR)
  FROM PUBLIC, authenticated, anon;
GRANT  EXECUTE ON FUNCTION public.fn_transition_gate_pass_state(UUID, VARCHAR)
  TO service_role;

REVOKE EXECUTE ON FUNCTION public.fn_transition_parcel_state(UUID, VARCHAR, VARCHAR)
  FROM PUBLIC, authenticated, anon;
GRANT  EXECUTE ON FUNCTION public.fn_transition_parcel_state(UUID, VARCHAR, VARCHAR)
  TO service_role;

REVOKE EXECUTE ON FUNCTION public.fn_transition_meter_reading_state(UUID, VARCHAR)
  FROM PUBLIC, authenticated, anon;
GRANT  EXECUTE ON FUNCTION public.fn_transition_meter_reading_state(UUID, VARCHAR)
  TO service_role;

REVOKE EXECUTE ON FUNCTION public.fn_transition_sos_alert(UUID, VARCHAR, TEXT)
  FROM PUBLIC, authenticated, anon;
GRANT  EXECUTE ON FUNCTION public.fn_transition_sos_alert(UUID, VARCHAR, TEXT)
  TO service_role;
```

---

## 3. COMPLETE 22-ROUTINE ACL MATRIX

Catalog ACL inspection using `has_function_privilege()` across all 6 legacy routines and all 16 new routines:

| # | Routine Name | Exact Signature | PUBLIC | anon | authenticated | service_role | Authorization Rule |
|---|---|---|---|---|---|---|---|
| 1 | `fn_cast_poll_vote` | `public.fn_cast_poll_vote(uuid, uuid, varchar)` | **REVOKED** | **REVOKED** | **REVOKED** | **GRANTED** | Legacy — hardened to service_role |
| 2 | `fn_assign_parking_slot` | `public.fn_assign_parking_slot(uuid, uuid)` | **REVOKED** | **REVOKED** | **REVOKED** | **GRANTED** | Legacy — hardened to service_role |
| 3 | `fn_transition_gate_pass_state` | `public.fn_transition_gate_pass_state(uuid, varchar)` | **REVOKED** | **REVOKED** | **REVOKED** | **GRANTED** | Legacy — hardened to service_role |
| 4 | `fn_transition_parcel_state` | `public.fn_transition_parcel_state(uuid, varchar, varchar)` | **REVOKED** | **REVOKED** | **REVOKED** | **GRANTED** | Legacy — hardened to service_role |
| 5 | `fn_transition_meter_reading_state` | `public.fn_transition_meter_reading_state(uuid, varchar)` | **REVOKED** | **REVOKED** | **REVOKED** | **GRANTED** | Legacy — hardened to service_role |
| 6 | `fn_transition_sos_alert` | `public.fn_transition_sos_alert(uuid, varchar, text)` | **REVOKED** | **REVOKED** | **REVOKED** | **GRANTED** | Legacy — hardened to service_role |
| 7 | `issue_gate_pass` | `public.issue_gate_pass(uuid, uuid, uuid, timestamptz, timestamptz)` | **REVOKED** | **REVOKED** | **GRANTED** | **GRANTED** | `auth.uid()` active resident of property or admin |
| 8 | `transition_gate_pass_status` | `public.transition_gate_pass_status(uuid, varchar)` | **REVOKED** | **REVOKED** | **GRANTED** | **GRANTED** | `auth.uid()` gatekeeper or admin; resident for own property (suspend only) |
| 9 | `log_parcel_delivery` | `public.log_parcel_delivery(uuid, uuid, varchar, varchar, uuid)` | **REVOKED** | **REVOKED** | **GRANTED** | **GRANTED** | `auth.uid()` gatekeeper or admin |
| 10 | `collect_parcel` | `public.collect_parcel(uuid, varchar)` | **REVOKED** | **REVOKED** | **GRANTED** | **GRANTED** | `auth.uid()` parcel recipient, gatekeeper, or admin |
| 11 | `trigger_sos_alert` | `public.trigger_sos_alert(uuid, uuid, varchar)` | **REVOKED** | **REVOKED** | **GRANTED** | **GRANTED** | `auth.uid()` active resident of property |
| 12 | `acknowledge_sos_alert` | `public.acknowledge_sos_alert(uuid)` | **REVOKED** | **REVOKED** | **GRANTED** | **GRANTED** | `auth.uid()` gatekeeper or admin |
| 13 | `resolve_sos_alert` | `public.resolve_sos_alert(uuid, varchar, text)` | **REVOKED** | **REVOKED** | **GRANTED** | **GRANTED** | `auth.uid()` gatekeeper or admin |
| 14 | `submit_meter_reading` | `public.submit_meter_reading(uuid, date, numeric)` | **REVOKED** | **REVOKED** | **GRANTED** | **GRANTED** | `auth.uid()` resident of property or staff/admin |
| 15 | `verify_and_bill_meter_reading` | `public.verify_and_bill_meter_reading(uuid)` | **REVOKED** | **REVOKED** | **GRANTED** | **GRANTED** | `auth.uid()` admin in target society |
| 16 | `register_vehicle` | `public.register_vehicle(uuid, uuid, varchar, varchar)` | **REVOKED** | **REVOKED** | **GRANTED** | **GRANTED** | `auth.uid()` property owner/tenant or admin |
| 17 | `assign_parking_slot` | `public.assign_parking_slot(uuid, uuid, uuid)` | **REVOKED** | **REVOKED** | **GRANTED** | **GRANTED** | `auth.uid()` admin in target society |
| 18 | `release_parking_slot` | `public.release_parking_slot(uuid, uuid)` | **REVOKED** | **REVOKED** | **GRANTED** | **GRANTED** | `auth.uid()` admin in target society |
| 19 | `create_community_poll` | `public.create_community_poll(uuid, varchar, text, jsonb, timestamptz, timestamptz)` | **REVOKED** | **REVOKED** | **GRANTED** | **GRANTED** | `auth.uid()` committee or admin |
| 20 | `cast_poll_vote` | `public.cast_poll_vote(uuid, uuid, varchar)` | **REVOKED** | **REVOKED** | **GRANTED** | **GRANTED** | `auth.uid()` active resident (one vote per property) |
| 21 | `close_community_poll` | `public.close_community_poll(uuid)` | **REVOKED** | **REVOKED** | **GRANTED** | **GRANTED** | `auth.uid()` admin, after `ends_at` |
| 22 | `get_poll_results` | `public.get_poll_results(uuid)` | **REVOKED** | **REVOKED** | **GRANTED** | **GRANTED** | Society member (closed) or admin (active) |

---

## 4. COMPLETE MUTATION SECURITY MATRIX FOR ALL 9 TABLES

PostgreSQL evaluates permissive policies with `OR` logic and restrictive policies with `AND` logic.

| Table | Direct SQL INSERT | Direct SQL SELECT | Direct SQL UPDATE | Direct SQL DELETE | Primary Enforcement Mechanism |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `gate_passes` | Blocked (`42501`) | Resident/Admin scope | 0 rows (`00000`) | 0 rows (`00000`) | RESTRICTIVE `USING(false)` + trigger `trg_prevent_direct_gate_pass_update` |
| `parcel_logs` | Blocked (`42501`) | Recipient/Gatekeeper | 0 rows (`00000`) | 0 rows (`00000`) | RESTRICTIVE `pol_parcel_update_none` & `pol_parcel_delete_none` (`USING(false)`) |
| `sos_alerts` | Blocked (`42501`) | Admin/Resident | 0 rows (`00000`) | 0 rows (`00000`) | RESTRICTIVE `pol_sos_restrictive_insert` + trigger `trg_protect_sos_status_update` |
| `utility_meters` | Admin (`00000`) / Client (`42501`) | Society scope | Admin (`00000`) / Client 0 rows (`00000`) | 0 rows (`00000`) | PERMISSIVE admin policy + RESTRICTIVE Delete `USING(false)` |
| `meter_readings` | Blocked (`42501`) | Property scope | 0 rows (`00000`) | 0 rows (`00000`) | RESTRICTIVE `USING(false)` + trigger `trg_prevent_direct_meter_reading_update` |
| `parking_slots` | Admin (`00000`) / Client (`42501`) | Society scope | Admin (`00000`) / Client 0 rows (`00000`) | 0 rows (`00000`) | PERMISSIVE admin policy + RESTRICTIVE Update/Delete `USING(false)` |
| `vehicles` | Blocked (`42501`) | Society scope | 0 rows (`00000`) | Owner (`00000`) / Non-owner 0 rows (`00000`) | RESTRICTIVE Update `USING(false)` + auto-release trigger on owner DELETE |
| `polls` | Blocked (`42501`) | Society scope | 0 rows (`00000`) | 0 rows (`00000`) | RESTRICTIVE `pol_polls_restrictive_insert/update/delete` (`USING(false)`) |
| `poll_votes` | Blocked (`42501`) | Own vote (member) / All (admin) | 0 rows (`00000`) | 0 rows (`00000`) | RESTRICTIVE `USING(false)` for UPDATE & DELETE; `trg_prevent_vote_mutations` installed as defense-in-depth for privileged/bypass paths |

---

## 5. SECURITY DEFINER FUNCTION SPECIFICATIONS (ALL 16 ROUTINES)

All 16 new workflow functions enforce:

* `SECURITY DEFINER` — executes as `postgres` owner (BYPASSRLS)
* `SET search_path = public, pg_temp`
* Explicit schema qualification (`public.`) for all table and helper function references
* `REVOKE EXECUTE FROM PUBLIC, anon, authenticated` (then `GRANT` to appropriate roles)

### Function Specifications

**1. `public.issue_gate_pass(p_society_id UUID, p_property_id UUID, p_staff_id UUID, p_valid_from TIMESTAMPTZ, p_valid_until TIMESTAMPTZ)`**
* **Purpose:** Creates a gate pass for a daily staff member/service provider.
* **Authorization:** `auth.uid()` is active owner/tenant of `p_property_id` or society admin.
* **Validation:** `p_staff_id` belongs to `p_society_id`; `p_valid_from < p_valid_until`.
* **Status:** Auto-approves (`status = 'active'`) if staff `verification_status = 'verified'`; sets `'pending'` otherwise.
* **Output:** Returns created `gate_passes.id`. (SQLSTATE `00000` / `42501` / `23514`)

**2. `public.transition_gate_pass_status(p_pass_id UUID, p_new_status VARCHAR)`**
* **Purpose:** Transitions gate pass state.
* **Authorization:** Gatekeeper or Admin (all transitions); Property Resident (suspend own-property pass only — reactivation BLOCKED for residents).
* **Transitions:** `pending → active` (verified staff), `active → suspended`, `suspended → active` (verified staff, admin/gatekeeper only).
* (SQLSTATE `00000` / `42501` / `22000`)

**3. `public.log_parcel_delivery(p_society_id UUID, p_property_id UUID, p_carrier_name VARCHAR, p_tracking_number VARCHAR, p_recipient_user_id UUID)`**
* **Purpose:** Gatekeeper logs incoming parcel delivery.
* **Authorization:** `auth.uid()` has role `'gatekeeper'`, `'admin'`, or `'super_admin'` in `p_society_id`.
* **CSPRNG:** 6-digit code generated via 4-byte rejection sampling (`v < 4,294,000,000`).
* **Storage:** SHA-256 hash stored in `collection_code_hash`; `collection_code = NULL`. Raw code returned to caller only.
* (SQLSTATE `00000` / `42501` / `23503`)

**4. `public.collect_parcel(p_parcel_id UUID, p_collection_code VARCHAR)`**
* **Purpose:** Validates collection code and marks parcel collected.
* **Authorization:** `auth.uid() = recipient_user_id` or Gatekeeper/Admin.
* **Locking:** Row locked (`FOR UPDATE`). Compares `encode(digest(p_collection_code, 'sha256'), 'hex')` against `collection_code_hash`. On failure: increments `failed_collection_attempts`. At 5 failures: `status = 'locked_failed_attempts'`. Each increment commits transactionally.
* (SQLSTATE `00000` / `22000`)

**5. `public.trigger_sos_alert(p_society_id UUID, p_property_id UUID, p_alert_type VARCHAR)`**
* **Purpose:** Triggers emergency SOS alert for a property.
* **Authorization:** `auth.uid()` active resident of `p_property_id`.
* **Concurrency:** Unique partial index `uq_active_sos_alert_property` prevents duplicate active alerts.
* (SQLSTATE `00000` / `42501` / `23505`)

**6. `public.acknowledge_sos_alert(p_alert_id UUID)`**
* **Purpose:** Gatekeeper or Admin acknowledges an active SOS alert (`status = 'triggered'`).
* **Authorization:** Gatekeeper or Admin in target society.
* **Action:** Sets `status = 'acknowledged'`, `acknowledged_by = auth.uid()`, `acknowledged_at = NOW()`.
* (SQLSTATE `00000` / `42501` / `22000`)

**7. `public.resolve_sos_alert(p_alert_id UUID, p_resolution_status VARCHAR, p_resolution_notes TEXT)`**
* **Purpose:** Resolves SOS alert (`'resolved'` or `'false_alarm'`).
* **Authorization:** Gatekeeper or Admin. Requires non-empty `p_resolution_notes`.
* **Action:** Sets `resolved_by = auth.uid()`, `resolved_at = NOW()`.
* (SQLSTATE `00000` / `42501` / `22000`)

**8. `public.submit_meter_reading(p_meter_id UUID, p_reading_date DATE, p_current_reading NUMERIC)`**
* **Purpose:** Submits utility sub-meter consumption reading.
* **Authorization:** Resident of meter property or Staff/Admin.
* **Validation:** `reading_date > previous_reading_date`; `current_reading >= previous_reading`. Captures `applied_unit_rate` at submission time.
* (SQLSTATE `00000` / `42501` / `22000`)

**9. `public.verify_and_bill_meter_reading(p_reading_id UUID)`**
* **Purpose:** Admin verifies reading and posts debit to `public.ledger_transactions`.
* **Authorization:** Society Admin.
* **Atomicity:** Row locked (`FOR UPDATE`). On FK failure (`23503`): entire PL/pgSQL transaction aborts; reading status rolls back to `'draft'`; 0 ledger rows, 0 audit rows, 0 notification rows survive.
* (SQLSTATE `00000` / `42501` / `23503`)

**10. `public.register_vehicle(p_society_id UUID, p_property_id UUID, p_registration_number VARCHAR, p_vehicle_type VARCHAR)`**
* **Purpose:** Registers vehicle for property.
* **Authorization:** Property Owner/Tenant or Admin. Unique registration number per society enforced.
* (SQLSTATE `00000` / `42501` / `23505`)

**11. `public.assign_parking_slot(p_society_id UUID, p_parking_slot_id UUID, p_vehicle_id UUID)`**
* **Purpose:** Admin assigns vacant parking slot to vehicle under canonical lock order.
* **Authorization:** Society Admin.
* **Action:** Atomically sets `parking_slots.assigned_vehicle_id = p_vehicle_id` and `vehicles.parking_slot_id = p_parking_slot_id`. Permanent `parking_slots.property_id` is never modified.
* (SQLSTATE `00000` / `42501` / `23505`)

**12. `public.release_parking_slot(p_society_id UUID, p_parking_slot_id UUID)`**
* **Purpose:** Admin releases vehicle assignment from parking slot.
* **Authorization:** Society Admin.
* **Action:** Sets `vehicles.parking_slot_id = NULL` and `parking_slots.assigned_vehicle_id = NULL`. `parking_slots.property_id` is **NEVER** set to NULL.
* (SQLSTATE `00000` / `42501`)

**13. `public.create_community_poll(p_society_id UUID, p_title VARCHAR, p_description TEXT, p_options JSONB, p_starts_at TIMESTAMPTZ, p_ends_at TIMESTAMPTZ)`**
* **Purpose:** Creates digital community poll with validated option set.
* **Authorization:** Committee member or Admin. Validates `p_options` via `public.fn_validate_poll_options(p_options)`.
* (SQLSTATE `00000` / `42501` / `23514`)

**14. `public.cast_poll_vote(p_poll_id UUID, p_property_id UUID, p_vote_choice VARCHAR)`**
* **Purpose:** Resident casts vote for property.
* **Authorization:** Active resident of `p_property_id`. Verifies `poll.status = 'active'`, `NOW() BETWEEN starts_at AND ends_at`, option validity against `poll.options`, enforces `uq_poll_property_vote`.
* **Note:** Runs as SECURITY DEFINER (`postgres` owner, BYPASSRLS). INSERTs into `poll_votes` despite restrictive INSERT RLS policy on the table — this is the authorized and intended workflow path.
* (SQLSTATE `00000` / `42501` / `23505` / `22000`)

**15. `public.close_community_poll(p_poll_id UUID)`**
* **Purpose:** Admin closes poll after `ends_at`.
* **Authorization:** Society Admin. Verifies `NOW() >= ends_at`. Sets `status = 'closed'`.
* (SQLSTATE `00000` / `42501` / `22000`)

**16. `public.get_poll_results(p_poll_id UUID)`**
* **Purpose:** Returns aggregate vote choice tallies and percentages.
* **Authorization:** Society member (for `closed`/ended polls) or Admin (for `active` polls). Non-admin active-poll queries rejected with SQLSTATE `22000` to preserve confidentiality. Includes zero-vote options and zero-division protection.
* (SQLSTATE `00000` / `42501` / `22000`)

---

## 6. HELPER FUNCTION SPECIFICATION (`fn_validate_poll_options`)

* **Signature:** `public.fn_validate_poll_options(p_options JSONB) RETURNS BOOLEAN`
* **Attributes:** `IMMUTABLE`, `LANGUAGE plpgsql`, `SET search_path = public, pg_temp`
* **Validation Rules:**
  1. `jsonb_typeof(p_options) = 'array'` — non-array input returns `FALSE`.
  2. `jsonb_array_length(p_options) >= 2` — arrays with fewer than 2 elements return `FALSE`.
  3. Every element must be a string with non-zero length after whitespace trimming.
  4. `lower(trim(elem_text))` normalization — case/whitespace duplicate pairs rejected.
* **Rejection Cases:** `[]`, `["Option A"]`, `["YES","yes"]`, `[" YES ","YES"]`, `["   ","B"]`, `["","B"]`, `["A",null]`, `["A",123]`, `["A",true]`, `["A",{}]`, `["A",["nested"]]`.
* **IMMUTABLE Justification:** `lower(trim(...))` on JSON text elements without locale-specific collations is an immutable string transformation under PostgreSQL C-locale/UTF-8.

---

## 7. PARCEL SECURITY SPECIFICATIONS & 5-ATTEMPT LOCKOUT SEQUENCE

* **Code Generation:** 4-byte CSPRNG rejection sampling over `public.gen_random_bytes(4)` (`v < 4,294,000,000`). Loop retries until a value in `[0, 4,294,000,000)` is obtained, giving a uniform 6-digit value in `[000000, 999999]`.
* **Hash Storage:** `collection_code` column is `NULL` (`CHECK (collection_code IS NULL)`). Only `collection_code_hash VARCHAR(64)` is persisted.
* **Zero Log Leakage:** Plaintext code is never stored in `audit_logs`, `notifications`, exception text, or returned query strings. The raw code is returned ONLY to the gatekeeper caller via RPC return value.

### Explicit 5-Attempt Lockout Sequence (Assertion 19)

| Attempt # | Supplied Code | Transaction | `p_success` | `p_status` | `failed_collection_attempts` | Committed |
|---|---|---|---|---|---|---|
| **1** | `'000000'` (Wrong) | Executed | `FALSE` | `'received_at_gate'` | `1` | Yes |
| **2** | `'111111'` (Wrong) | Executed | `FALSE` | `'received_at_gate'` | `2` | Yes |
| **3** | `'222222'` (Wrong) | Executed | `FALSE` | `'received_at_gate'` | `3` | Yes |
| **4** | `'333333'` (Wrong) | Executed | `FALSE` | `'received_at_gate'` | `4` | Yes |
| **5** | `'444444'` (Wrong) | Executed | `FALSE` | `'locked_failed_attempts'` | `5` | Yes |
| **Post-Lockout** | Correct Code | Rejected | `FALSE` | `'locked_failed_attempts'` | `5` (locked) | SQLSTATE `22000` |

---

## 8. SERVICE-ROLE CONTEXT SIMULATION SPECIFICATION (ASSERTION 82)

* **Verification Context:** In `verify_slice17.sql`, service-role execution is tested as:

```sql
SET LOCAL ROLE service_role;
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);
```

* **Trust Boundary Classification:**
  * `SET LOCAL ROLE service_role` = **Database-Layer Context Simulation**.
  * JWT GUCs in the test script are test context — not cryptographic proof.
  * The test verifies database role privileges and authorization behavior.
  * It does **NOT** constitute HTTP/PostgREST end-to-end JWT verification.
  * Production trust depends on the Supabase/PostgREST authentication boundary.
  * Client-controlled GUC values must never be trusted for privilege escalation.

---

## 9. GATE PASS AUTHORIZATION STATE MACHINE

**Blocker 3 Resolution — LOCKED (Security-Preferred Default):**  
Property Residents MAY suspend an active pass. Property Residents MUST NOT reactivate a suspended pass. Reactivation is exclusively granted to Admins and Gatekeepers.

| Current Status | Target Status | Authorized Roles | Prerequisite | Security Policy |
| :--- | :--- | :--- | :--- | :--- |
| `pending` | `active` | Admin, Gatekeeper | Staff `verification_status = 'verified'` | Production Rule |
| `active` | `suspended` | Admin, Gatekeeper, Property Resident | Target pass belongs to caller's property/society | Production Rule |
| `suspended` | `active` | Admin, Gatekeeper | Staff `verification_status = 'verified'` | Production Rule |
| `suspended` | `active` | Property Resident | N/A | **BLOCKED — Residents cannot reactivate suspended passes** |

---

## 10. PARKING / VEHICLE CONCURRENCY SPECIFICATIONS (MODEL A)

* **Deeded Property Allocation:** `parking_slots.property_id` represents permanent deeded allocation and is **NEVER** set to `NULL` during slot release or vehicle deletion.
* **Reciprocal Pointers:** `parking_slots.assigned_vehicle_id = V` $\iff$ `vehicles.parking_slot_id = S`.
* **Auto-Release Trigger:** Deleting a vehicle fires `trg_vehicles_auto_release_parking`, setting `assigned_vehicle_id = NULL` and `parking_slot_id = NULL` while preserving `parking_slots.property_id`.
* **Canonical Lock Order:** All assignment/release operations lock `parking_slots` rows first (`FOR UPDATE ORDER BY id`), then `vehicles` rows (`FOR UPDATE ORDER BY id`) — deadlock prevention.
* **Direct Modification Block:** Direct resident modification of `vehicles.parking_slot_id` blocked by RESTRICTIVE RLS `pol_vehicles_restrictive_update` (`USING(false)`).

---

## 11. UTILITY BILLING & LEDGER INTEGRITY SPECIFICATIONS

* **Monotonic Readings:** `submit_meter_reading` requires `reading_date > previous_reading_date` and `current_reading >= previous_reading`.
* **Rate Capture:** `applied_unit_rate` is captured into `meter_readings` at submission/verification time and is stable even if `utility_meters.unit_rate` changes later.
* **Ledger Debit Target:** `verify_and_bill_meter_reading` derives the debit target from the active property occupant/owner mapping. User ID cannot be fabricated by the caller.
* **Atomic Rollback:** If posting to `ledger_transactions` fails with FK violation (`23503`), the entire PL/pgSQL transaction aborts cleanly: reading status rolls back to `'draft'`, 0 ledger rows, 0 audit rows, 0 notification rows survive.

---

## 12. COMMUNITY POLL SECURITY SPECIFICATIONS

* **Option Validation:** `fn_validate_poll_options(p_options)` enforces: JSON array, ≥ 2 elements, non-blank strings, no case/whitespace duplicates.
* **One-Vote-Per-Property:** Enforced by unique constraint `uq_poll_property_vote(poll_id, property_id)`.
* **Direct Mutation Blocking (poll_votes):**
  * INSERT: RESTRICTIVE `pol_poll_votes_restrictive_insert` `WITH CHECK(false)` → blocks all direct client INSERTs (`42501`).
  * UPDATE: RESTRICTIVE `pol_poll_votes_restrictive_update` `USING(false)` → 0 eligible rows → 0 rows updated, SQLSTATE `00000`.
  * DELETE: RESTRICTIVE `pol_poll_votes_restrictive_delete` `USING(false)` → 0 eligible rows → 0 rows deleted, SQLSTATE `00000`.
  * `trg_prevent_vote_mutations` installed as defense-in-depth for privileged/bypass paths only.
* **Authorized Vote Path:** `cast_poll_vote(...)` runs as SECURITY DEFINER (`postgres` owner, BYPASSRLS) and can INSERT into `poll_votes` — this is the intended and authorized workflow.
* **Confidentiality:** `get_poll_results` suppresses vote tallies for active polls when called by non-admin members. Closed/ended polls show aggregate tallies with zero-vote option inclusion and zero-division protection.

---

## 13. EMERGENCY SOS ALERT STATE MACHINE

* **Valid States:** `'triggered'`, `'acknowledged'`, `'resolved'`, `'false_alarm'`.
* **Valid Transitions:**
  * `triggered → acknowledged` — Gatekeeper or Admin via `acknowledge_sos_alert`
  * `triggered → resolved / false_alarm` — Gatekeeper or Admin via `resolve_sos_alert`
  * `acknowledged → resolved / false_alarm` — Gatekeeper or Admin via `resolve_sos_alert`
* **Terminal States:** `'resolved'` and `'false_alarm'` are terminal; no further transitions permitted.
* **Notes Rule:** `resolve_sos_alert` requires a non-empty `resolution_notes` parameter.
* **Duplicate Alert Prevention:** Unique partial index `uq_active_sos_alert_property` prevents concurrent duplicate active alerts for the same property.

---

## 14. COMPLETE AUTHORITATIVE ASSERTION INVENTORY (ASSERTIONS 1 THROUGH 82)

All 82 planned assertions are explicitly specified in exact sequential order. No sub-labels. No gaps.

1. **Assertion 1:** Authorized resident issues gate pass via `issue_gate_pass(...)`. (Actor: Resident, SQLSTATE `00000`, 1 row)
2. **Assertion 2:** Direct client SQL `INSERT` into `gate_passes` blocked by RESTRICTIVE RLS `pol_gate_passes_restrictive_insert`. (Actor: Client, SQLSTATE `42501`, 0 rows)
3. **Assertion 3:** Direct client SQL `UPDATE` on `gate_passes` status blocked by RESTRICTIVE RLS / trigger `trg_prevent_direct_gate_pass_update`. (Actor: Client, SQLSTATE `00000`, 0 rows updated)
4. **Assertion 4:** Direct client SQL `DELETE` on `gate_passes` blocked by RESTRICTIVE RLS `pol_gate_passes_restrictive_delete`. (Actor: Client, SQLSTATE `00000`, 0 rows deleted)
5. **Assertion 5:** Direct client SQL `SELECT` cross-property on `gate_passes` returns 0 rows (`pol_gate_passes_owner_select`). (Actor: Resident P1, SQLSTATE `00000`, 0 rows)
6. **Assertion 6:** Forged property gate pass issuance via function rejected. (Actor: Resident P1, SQLSTATE `42501`, 0 rows)
7. **Assertion 7:** Admin transitions gate pass status (`pending → active → suspended`). (Actor: Admin, SQLSTATE `00000`, 1 row)
8. **Assertion 8:** Invalid date validation (`valid_from >= valid_until`) rejected by constraint `chk_gate_pass_validity`. (Actor: Resident, SQLSTATE `23514`/`22000`, 0 rows)
9. **Assertion 9:** Cross-society gate pass transition rejected. (Actor: Admin S1, SQLSTATE `42501`, 0 rows)
10. **Assertion 10:** Gatekeeper logs parcel delivery via `log_parcel_delivery(...)` using 4-byte CSPRNG rejection sampling; SHA-256 hash stored; `collection_code` column is NULL. (Actor: Gatekeeper, SQLSTATE `00000`, 1 row)
11. **Assertion 11:** Direct client SQL `INSERT` into `parcel_logs` blocked by RESTRICTIVE RLS `pol_parcel_restrictive_insert`. (Actor: Client, SQLSTATE `42501`, 0 rows)
12. **Assertion 12:** Direct client SQL `UPDATE` on `parcel_logs` status blocked by RESTRICTIVE RLS `pol_parcel_update_none`. (Actor: Client, SQLSTATE `00000`, 0 rows updated)
13. **Assertion 13:** Direct client SQL `DELETE` on `parcel_logs` blocked by RESTRICTIVE RLS `pol_parcel_delete_none`. (Actor: Client, SQLSTATE `00000`, 0 rows deleted)
14. **Assertion 14:** Direct client SQL `SELECT` on `parcel_logs` by non-recipient member returns 0 rows. (Actor: Resident U1, SQLSTATE `00000`, 0 rows)
15. **Assertion 15:** Parcel collection attempt with wrong collection code rejected (`failed_collection_attempts = 1`). (Actor: Recipient, SQLSTATE `00000`, `p_success = false`)
16. **Assertion 16:** Parcel collection attempt by non-recipient member blocked. (Actor: Resident U2, SQLSTATE `42501`, 0 rows)
17. **Assertion 17:** Authorized recipient collects parcel with correct code (`status = 'collected'`). (Actor: Recipient U1, SQLSTATE `00000`, 1 row)
18. **Assertion 18:** Replay collection attempt on already-collected parcel rejected. (Actor: Recipient U1, SQLSTATE `22000`, 0 rows)
19. **Assertion 19 (5-Attempt Brute-Force Lockout Sequence):**
    * Attempt 1 (`'000000'`): `failed_attempts = 1`, `status = 'received_at_gate'`, SQLSTATE `00000`. Committed.
    * Attempt 2 (`'111111'`): `failed_attempts = 2`, `status = 'received_at_gate'`, SQLSTATE `00000`. Committed.
    * Attempt 3 (`'222222'`): `failed_attempts = 3`, `status = 'received_at_gate'`, SQLSTATE `00000`. Committed.
    * Attempt 4 (`'333333'`): `failed_attempts = 4`, `status = 'received_at_gate'`, SQLSTATE `00000`. Committed.
    * Attempt 5 (`'444444'`): `failed_attempts = 5`, `status = 'locked_failed_attempts'`, SQLSTATE `00000`. Committed.
    * Post-Lockout (correct code): rejected, SQLSTATE `22000`, parcel remains locked.
20. **Assertion 20:** Resident triggers emergency SOS alert via `trigger_sos_alert(...)`. (Actor: Resident P1, SQLSTATE `00000`, 1 row)
21. **Assertion 21:** Direct client SQL `INSERT` into `sos_alerts` blocked by RESTRICTIVE RLS `pol_sos_restrictive_insert`. (Actor: Client, SQLSTATE `42501`, 0 rows)
22. **Assertion 22:** Direct client SQL `UPDATE` on `sos_alerts` blocked by RESTRICTIVE RLS / trigger `trg_protect_sos_status_update`. (Actor: Client, SQLSTATE `00000`, 0 rows updated)
23. **Assertion 23:** Direct client SQL `DELETE` on `sos_alerts` blocked by RESTRICTIVE RLS `policy_sos_delete`. (Actor: Client, SQLSTATE `00000`, 0 rows deleted)
24. **Assertion 24:** Direct client SQL `SELECT` on `sos_alerts` cross-society returns 0 rows. (Actor: Resident S1, SQLSTATE `00000`, 0 rows)
25. **Assertion 25:** Forged property SOS trigger attempt rejected. (Actor: Resident P1, SQLSTATE `42501`, 0 rows)
26. **Assertion 26:** Concurrent active SOS trigger race for same property serialized under `uq_active_sos_alert_property`. (Actor: Session A & B, SQLSTATE `23505`/`22000`, 1 row)
27. **Assertion 27:** Gatekeeper acknowledges SOS alert (`status = 'acknowledged'`). (Actor: Gatekeeper, SQLSTATE `00000`, 1 row)
28. **Assertion 28:** Admin resolves SOS alert with mandatory notes (`status = 'resolved'`). (Actor: Admin, SQLSTATE `00000`, 1 row)
29. **Assertion 29:** Resident submits sub-meter reading via `submit_meter_reading(...)`. (Actor: Resident, SQLSTATE `00000`, 1 row)
30. **Assertion 30:** Direct client SQL `INSERT` into `meter_readings` blocked by RESTRICTIVE RLS `pol_meter_readings_restrictive_insert`. (Actor: Client, SQLSTATE `42501`, 0 rows)
31. **Assertion 31:** Direct client SQL `UPDATE` on `meter_readings` status blocked by RESTRICTIVE RLS / trigger `trg_prevent_direct_meter_reading_update`. (Actor: Client, SQLSTATE `00000`, 0 rows updated)
32. **Assertion 32:** Direct client SQL `DELETE` on `meter_readings` blocked by RESTRICTIVE RLS `pol_meter_readings_restrictive_delete`. (Actor: Client, SQLSTATE `00000`, 0 rows deleted)
33. **Assertion 33:** Admin direct SQL `INSERT` into `utility_meters` allowed; client direct `INSERT` blocked. (Actor: Admin/Client, SQLSTATE `42501` for client, 1 row for admin)
34. **Assertion 34:** Admin direct SQL `UPDATE` on `utility_meters` allowed; client direct `UPDATE` blocked. (Actor: Admin/Client, SQLSTATE `00000`, 0 rows updated for client)
35. **Assertion 35:** Direct client SQL `DELETE` on `utility_meters` blocked by RESTRICTIVE RLS `pol_utility_meters_restrictive_delete`. (Actor: Client, SQLSTATE `00000`, 0 rows deleted)
36. **Assertion 36:** Direct client SQL `SELECT` on `meter_readings` cross-property returns 0 rows. (Actor: Resident P1, SQLSTATE `00000`, 0 rows)
37. **Assertion 37:** Admin verifies and bills reading via `verify_and_bill_meter_reading(...)`, generating `ledger_transactions` `utility_bill` debit. (Actor: Admin, SQLSTATE `00000`, 1 row)
38. **Assertion 38:** Deterministic FK failure test: Meter reading with unmapped user ID causes `ledger_transactions` FK violation (`23503`) strictly inside `verify_and_bill_meter_reading(...)`, rolling back reading status to `'draft'`, 0 ledger rows. (Actor: Admin, SQLSTATE `23503`, 0 ledger rows)
39. **Assertion 39:** Concurrent meter billing race under `FOR UPDATE` lock on `meter_readings`. Session A wins (`00000`); Session B fails (`22000`). 1 ledger transaction total. (Actor: Session A & B, SQLSTATE `22000`)
40. **Assertion 40:** Resident registers vehicle via `register_vehicle(...)`. (Actor: Resident, SQLSTATE `00000`, 1 row)
41. **Assertion 41:** Admin direct SQL `INSERT` into `parking_slots` allowed; client direct `INSERT` blocked. (Actor: Admin/Client, SQLSTATE `42501` for client, 1 row for admin)
42. **Assertion 42:** Direct client SQL `UPDATE` on `parking_slots` blocked by RESTRICTIVE RLS `pol_slots_restrictive_update`. (Actor: Client, SQLSTATE `00000`, 0 rows updated)
43. **Assertion 43:** Direct client SQL `DELETE` on `parking_slots` blocked by RESTRICTIVE RLS `pol_slots_restrictive_delete`. (Actor: Client, SQLSTATE `00000`, 0 rows deleted)
44. **Assertion 44:** Direct client SQL `INSERT` into `vehicles` blocked by RESTRICTIVE RLS `pol_vehicles_restrictive_insert`. (Actor: Client, SQLSTATE `42501`, 0 rows)
45. **Assertion 45:** Direct client SQL `UPDATE` on `vehicles.parking_slot_id` blocked by RESTRICTIVE RLS `pol_vehicles_restrictive_update`. (Actor: Client, SQLSTATE `00000`, 0 rows updated)
46. **Assertion 46:** Resident vehicle owner direct SQL `DELETE` on `vehicles` allowed (`pol_vehicles_delete_resident`), automatically releasing parking slot via trigger `trg_vehicles_auto_release_parking`; non-owner DELETE blocked. (Actor: Resident Owner/Non-owner, SQLSTATE `00000` / `00000` 0 rows for non-owner)
47. **Assertion 47:** Parking Concurrency Race A (Slot Contention): Session A and B attempt to assign different vehicles to slot S1 concurrently. Exactly one vehicle assigned under canonical lock order. (Actor: Session A & B, SQLSTATE `23505`/`22000`)
48. **Assertion 48:** Parking Concurrency Race B (Vehicle Contention): Session A and B assign vehicle V1 to slots S1 and S2 simultaneously. V1 assigned to at most one slot under canonical lock order. (Actor: Session A & B, SQLSTATE `23505`/`22000`)
49. **Assertion 49:** Parking Concurrency Race C (Release vs Assign): Session A releases S1 while Session B assigns S1. Serializes under `FOR UPDATE` lock, preserving permanent `property_id`. (Actor: Session A & B, SQLSTATE `00000`/`22000`)
50. **Assertion 50:** Admin creates community poll via `create_community_poll(...)` with validated JSONB options. (Actor: Admin, SQLSTATE `00000`, 1 row)
51. **Assertion 51:** Direct client SQL `INSERT` into `polls` blocked by RESTRICTIVE RLS `pol_polls_restrictive_insert`. (Actor: Client, SQLSTATE `42501`, 0 rows)
52. **Assertion 52:** Direct client SQL `UPDATE` on `polls` blocked by RESTRICTIVE RLS `pol_polls_restrictive_update`. (Actor: Client, SQLSTATE `00000`, 0 rows updated)
53. **Assertion 53:** Direct client SQL `DELETE` on `polls` blocked by RESTRICTIVE RLS `pol_polls_restrictive_delete`. (Actor: Client, SQLSTATE `00000`, 0 rows deleted)
54. **Assertion 54:** Poll Option Validation: Creating poll with invalid options rejected by `fn_validate_poll_options` helper in CHECK constraint. Rejects `[]`, `["YES","yes"]`, `["   ","valid"]`, `["one",123]`. (Actor: Admin, SQLSTATE `23514`, 0 rows)
55. **Assertion 55:** Direct client SQL `INSERT` into `poll_votes` blocked by RESTRICTIVE RLS `pol_poll_votes_restrictive_insert`. (Actor: Client, SQLSTATE `42501`, 0 rows)
56. **Assertion 56 — Direct UPDATE on `poll_votes`:** Direct client SQL `UPDATE` on `poll_votes` blocked by RESTRICTIVE RLS `pol_poll_votes_restrictive_update` `USING(false)`. The existing target row is not eligible for update — RLS excludes it before the statement executor touches it. Result: 0 rows updated. `trg_prevent_vote_mutations` also installed as defense-in-depth for privileged/bypass paths. (Actor: Ordinary authenticated client, SQLSTATE `00000`, 0 rows updated)
57. **Assertion 57 — Direct DELETE on `poll_votes`:** Direct client SQL `DELETE` on `poll_votes` blocked by RESTRICTIVE RLS `pol_poll_votes_restrictive_delete` `USING(false)`. The target row is not eligible for deletion — RLS excludes it before deletion. Result: 0 rows deleted. `trg_prevent_vote_mutations` also installed as defense-in-depth for privileged/bypass paths. (Actor: Ordinary authenticated client, SQLSTATE `00000`, 0 rows deleted)
58. **Assertion 58:** Member direct SQL `SELECT` on `poll_votes` returns ONLY caller's own vote choice (`voter_id = auth.uid()`). (Actor: Resident U1, SQLSTATE `00000`, 1 row max)
59. **Assertion 59:** Resident casts vote for property via `cast_poll_vote(...)`. (Actor: Resident P1, SQLSTATE `00000`, 1 row)
60. **Assertion 60:** Voting for choice not in `polls.options` rejected. (Actor: Resident P1, SQLSTATE `22000`, 0 rows)
61. **Assertion 61:** Voting before start time or after end time / on closed poll rejected. (Actor: Resident P1, SQLSTATE `22000`, 0 rows)
62. **Assertion 62:** Cross-society or non-resident property vote attempt rejected. (Actor: Resident P1, SQLSTATE `42501`, 0 rows)
63. **Assertion 63:** Two occupants of Property 1 concurrently cast vote. Session A wins (`00000`); Session B hits `uq_poll_property_vote` (`23505`). (Actor: Session A & B, SQLSTATE `23505`)
64. **Assertion 64:** Member requesting aggregate results for an active poll via `get_poll_results(...)` rejected to preserve confidentiality. (Actor: Resident U1, SQLSTATE `22000`, 0 rows)
65. **Assertion 65:** Non-admin member attempting to execute `close_community_poll(...)` rejected due to admin privilege check. (Actor: Resident U1, SQLSTATE `42501`, 0 rows)
66. **Assertion 66:** Authorized admin attempting to close an active poll before `NOW() >= ends_at` rejected due to time constraint. (Actor: Admin, SQLSTATE `22000`, 0 rows)
67. **Assertion 67:** Admin calls `close_community_poll(...)` after poll reaches `ends_at`. Poll status becomes `'closed'`; closed-poll aggregate results via `get_poll_results` become available. (Actor: Admin, SQLSTATE `00000`, 1 row)
68. **Assertion 68:** Authenticated client setting forged transaction-local GUC (`set_config('app.caller_id', ...)`). Procedure ignores GUC, evaluates `auth.uid()`, fails authorization. (Actor: Client, SQLSTATE `42501`, 0 rows)
69. **Assertion 69:** Catalog query proves all 16 Slice 17 workflow functions explicitly enforce `search_path = public, pg_temp`. (Actor: Audit Script, SQLSTATE `00000`, 16 rows)
70. **Assertion 70:** Catalog query via `has_function_privilege()` proves EXECUTE revoked from `PUBLIC`, `authenticated`, and `anon` for all 6 legacy functions. (Actor: Audit Script, SQLSTATE `00000`, 6 rows)
71. **Assertion 71:** Catalog query via `has_function_privilege()` verifies effective privileges for ALL 16 new Slice 17 functions. (Actor: Audit Script, SQLSTATE `00000`, 16 rows)
72. **Assertion 72:** Catalog query verifies `parcel_logs.failed_collection_attempts` exists (NOT NULL, default `0`) and `collection_code_hash` exists, while `collection_code` is nullable and `CHECK (collection_code IS NULL)` is enforced. (Actor: Audit Script, SQLSTATE `00000`, 1 row)
73. **Assertion 73:** Resident of Society 1 attempting `SELECT` on `sos_alerts` or `parcel_logs` in Society 2 returns 0 rows. (Actor: Resident S1, SQLSTATE `00000`, 0 rows)
74. **Assertion 74:** Trusted workflow execution (`issue_gate_pass`) automatically creates audit log row with `actor_id = auth.uid()`, `society_id`, `entity_type = 'gate_pass'`, `action = 'pass_issued'`, and payload. (Actor: Audit Script, SQLSTATE `00000`, 1 row)
75. **Assertion 75:** Direct client SQL `INSERT` into `audit_logs` blocked by RLS. (Actor: Client, SQLSTATE `42501`, 0 rows)
76. **Assertion 76:** Direct client SQL `DELETE` on `audit_logs` blocked by RLS / trigger. (Actor: Client, SQLSTATE `42501`/`00000`, 0 rows deleted)
77. **Assertion 77:** Verification query searches `audit_logs.new_data` and `notifications.body` for the raw 6-digit collection code issued in Assertion 10 and asserts zero occurrences exist. (Actor: Audit Script, SQLSTATE `00000`, 0 occurrences)
78. **Assertion 78:** Invalid parcel delivery call (invalid recipient user ID causing FK failure) aborts transaction cleanly, rolling back audit and notification rows. (Actor: Gatekeeper, SQLSTATE `23503`, 0 rows)
79. **Assertion 79:** Script verifies SHA-256 hashes of Slice 16 schema and lock files against reference manifest; Slices 1–15 reported `NO AUTHORITATIVE REFERENCE HASH`. (Actor: Audit Script, SQLSTATE `00000`, match)
80. **Assertion 80:** Direct client SQL `INSERT`/`UPDATE` on `notifications` blocked by RLS. (Actor: Client, SQLSTATE `42501`, 0 rows)
81. **Assertion 81:** Resident vehicle owner deleting vehicle row with active slot assignment triggers `trg_vehicles_auto_release_parking`, clearing `parking_slots.assigned_vehicle_id` to NULL and unlinking `vehicles.parking_slot_id` automatically, while preserving permanent `parking_slots.property_id`. (Actor: Resident Owner, SQLSTATE `00000`, 1 row)
82. **Assertion 82:** Database-layer service-role context simulation (`SET LOCAL ROLE service_role;`) verifies backend administrative workflow execution without requiring end-user `auth.uid()`. (Actor: Service Role Simulation, SQLSTATE `00000`, 1 row)

---

## 15. HISTORICAL IMMUTABILITY MANIFEST (37 FILES TOTAL)

| File Path | Immutability Status | Notes |
| :--- | :--- | :--- |
| `database/schema_slice1.sql` | **NO AUTHORITATIVE REFERENCE HASH** | Slice 1–15 lock records contain pass metrics, not embedded SHA-256 hashes |
| `database/schema_slice2.sql` | **NO AUTHORITATIVE REFERENCE HASH** | — |
| `database/schema_slice3.sql` | **NO AUTHORITATIVE REFERENCE HASH** | — |
| `database/schema_slice4.sql` | **NO AUTHORITATIVE REFERENCE HASH** | — |
| `database/schema_slice5.sql` | **NO AUTHORITATIVE REFERENCE HASH** | — |
| `database/schema_slice6.sql` | **NO AUTHORITATIVE REFERENCE HASH** | — |
| `database/schema_slice7.sql` | **NO AUTHORITATIVE REFERENCE HASH** | — |
| `database/schema_slice8.sql` | **NO AUTHORITATIVE REFERENCE HASH** | — |
| `database/schema_slice9.sql` | **NO AUTHORITATIVE REFERENCE HASH** | — |
| `database/schema_slice10.sql` | **NO AUTHORITATIVE REFERENCE HASH** | — |
| `database/schema_slice11.sql` | **NO AUTHORITATIVE REFERENCE HASH** | — |
| `database/schema_slice12.sql` | **NO AUTHORITATIVE REFERENCE HASH** | — |
| `database/schema_slice13.sql` | **NO AUTHORITATIVE REFERENCE HASH** | — |
| `database/schema_slice14.sql` | **NO AUTHORITATIVE REFERENCE HASH** | — |
| `database/schema_slice15.sql` | **NO AUTHORITATIVE REFERENCE HASH** | — |
| `database/schema_slice16.sql` | **MATCH** | SHA-256: `34D02E670C612D1F32656B49D28894D67D04F5C0C2E08B6169830AC5FD6215CC` (from `SLICE16_REMEDIATION_LOCK_RECORD.md`) |
| `database/verify_slice1.sql` | **NO AUTHORITATIVE REFERENCE HASH** | — |
| `database/verify_slice2.sql` | **NO AUTHORITATIVE REFERENCE HASH** | — |
| `database/verify_slice3.sql` | **NO AUTHORITATIVE REFERENCE HASH** | — |
| `database/verify_slice4.sql` | **NO AUTHORITATIVE REFERENCE HASH** | — |
| `database/verify_slice5.sql` | **NO AUTHORITATIVE REFERENCE HASH** | — |
| `database/verify_slice6.sql` | **NO AUTHORITATIVE REFERENCE HASH** | — |
| `database/verify_slice7.sql` | **NO AUTHORITATIVE REFERENCE HASH** | — |
| `database/verify_slice8.sql` | **NO AUTHORITATIVE REFERENCE HASH** | — |
| `database/verify_slice9.sql` | **NO AUTHORITATIVE REFERENCE HASH** | — |
| `database/verify_slice10.sql` | **NO AUTHORITATIVE REFERENCE HASH** | — |
| `database/verify_slice11.sql` | **NO AUTHORITATIVE REFERENCE HASH** | — |
| `database/verify_slice12.sql` | **NO AUTHORITATIVE REFERENCE HASH** | — |
| `database/verify_slice13.sql` | **NO AUTHORITATIVE REFERENCE HASH** | — |
| `database/verify_slice14.sql` | **NO AUTHORITATIVE REFERENCE HASH** | — |
| `database/verify_slice15.sql` | **NO AUTHORITATIVE REFERENCE HASH** | — |
| `database/verify_slice16.sql` | **MATCH** | SHA-256: `5FB3812A02738DE004997C597ADE0598468BC9A76AA23B5ACD0AAD7E5746C0BB` (from `SLICE16_REMEDIATION_LOCK_RECORD.md`) |
| `SLICE15_LOCK_RECORD.md` | **NO AUTHORITATIVE REFERENCE HASH** | — |
| `SLICE16_LOCK_RECORD.md` | **NO AUTHORITATIVE REFERENCE HASH** | — |
| `SLICE16_POST_LOCK_BOOKING_OVERLAP_EVIDENCE.md` | **NO AUTHORITATIVE REFERENCE HASH** | — |
| `SLICE16_POST_LOCK_SECURITY_REVERIFICATION.md` | **NO AUTHORITATIVE REFERENCE HASH** | — |
| `SLICE16_REMEDIATION_LOCK_RECORD.md` | **INDEPENDENTLY COMPUTED** | SHA-256: `04E502AB4443E5AFDD283962E33EBCA244FA1E653BF18EDC03A8D0F97A247240` — independently computed from the file as it exists on disk at the time of the Slice 16 hash audit. No canonical normalization procedure exists for excluding any embedded hash field; the hash is recorded as computed over the full file byte sequence. Runtime re-computation against the live file is required to confirm continued integrity. |

> [!NOTE]
> No reference hashes were fabricated or reconstructed for Slices 1–15. "NO AUTHORITATIVE REFERENCE HASH" means the historical lock records for those slices recorded cumulative test pass metrics (434/434 PASS), not embedded 64-character hex SHA-256 strings.

---

## 16. APPLICATION COMPATIBILITY EVIDENCE

Static source search across `src/App.jsx` and `src/supabase.js`:

| Legacy Function | References in App Source |
| :--- | :--- |
| `fn_cast_poll_vote` | 0 references |
| `fn_assign_parking_slot` | 0 references |
| `fn_transition_gate_pass_state` | 0 references |
| `fn_transition_parcel_state` | 0 references |
| `fn_transition_meter_reading_state` | 0 references |
| `fn_transition_sos_alert` | 0 references |

**Evidence Scope:** Static inspection of `src/App.jsx` and `src/supabase.js` found zero direct references to the six legacy routine names. Broader application compatibility — including any indirect calls, generated code, or files not inspected — remains subject to implementation-time and runtime verification.

---

## 17. IMPLEMENTATION FILE BOUNDARY

When implementation is explicitly authorized by the user, EXACTLY three files will be created:

1. `[NEW]` `database/schema_slice17.sql`
2. `[NEW]` `database/verify_slice17.sql`
3. `[NEW]` `scratch/run_all17.ps1`

No existing application or database files will be modified. No historical Slice 1–16 source files will be touched.

> [!CAUTION]
> Implementation authorization has NOT been granted. These files do NOT exist on disk.

---

## 18. SEQUENTIAL IMPLEMENTATION ORDER

When authorized, implementation will proceed in strict order:

1. **Preflight Environment Check:** Verify test container running on `localhost:54322`.
2. **Historical Baseline Regression:** Execute `run_all16.ps1` → Confirm **469 / 469 PASS**.
3. **Historical Manifest Audit:** Verify SHA-256 hashes of Slice 16 files match reference manifest.
4. **Deploy Slice 17 Schema DDL:** Execute `database/schema_slice17.sql`.
5. **Create Helper Function:** Deploy `public.fn_validate_poll_options(jsonb)`.
6. **Deploy Triggers & RLS Policies:** Apply RESTRICTIVE policies and mutation-blocking triggers for all 9 tables.
7. **Deploy 16 SECURITY DEFINER Routines:** Create all 16 new workflow functions.
8. **Execute Live Catalog Hardening:** Revoke client EXECUTE on 6 legacy functions; grant to `service_role`.
9. **Grant RPC Privileges:** Grant EXECUTE on 16 new routines to `authenticated` and `service_role`.
10. **Execute Verification Test Suite:** Run `database/verify_slice17.sql` (Assertions 1–82).
11. **Final Baseline Score Verification:** Confirm cumulative score = **469 + 82 = 551 PASS**.

---

## 19. ADVERSARIAL TEST PLAN (21 THREAT VECTORS)

1. **Privilege Escalation:** Resident attempting to invoke admin-only RPC routines → Blocked (`42501`).
2. **Forged `auth.uid()` Identity:** Client setting `app.caller_id` GUC → Ignored; `auth.uid()` enforced.
3. **Forged Client GUC Override:** Manipulating session GUCs to bypass authorization → Blocked.
4. **Cross-Property Access:** Resident P1 attempting gate pass/meter reading for P2 → Blocked (`42501`).
5. **Cross-Society Access:** Admin S1 attempting RPC mutation on S2 → Blocked (`42501`).
6. **Direct Table Mutations:** Direct client SQL INSERT/UPDATE/DELETE → Blocked (`42501` / 0 rows via RESTRICTIVE `USING(false)`).
7. **Unauthorized Function Execution:** Invoking legacy routines directly as authenticated client → Blocked (`42501`).
8. **State Machine Bypass:** Direct UPDATE on status columns → Blocked by RESTRICTIVE RLS / trigger.
9. **Duplicate Voting:** Concurrent vote casting for same property → Serialized under `uq_poll_property_vote` (`23505`).
10. **Active Poll Result Leakage:** Non-admin member requesting active poll tallies → Blocked (`22000`).
11. **Parcel Brute-Force Code Guessing:** 5 consecutive wrong-code `collect_parcel` calls → `status = 'locked_failed_attempts'`; subsequent correct code also rejected.
12. **Parking Race Conditions:** Concurrent slot assignment calls → Serialized under canonical `FOR UPDATE` lock order.
13. **Vehicle/Slot Inconsistency:** Releasing vehicle or deleting vehicle → Preserves permanent `parking_slots.property_id`; reciprocal pointers cleaned atomically.
14. **Utility Billing Duplication:** Re-billing already-billed reading → Blocked (`22000`).
15. **Ledger Integrity Failure:** Unmapped/purged user ID in billing → Atomic PL/pgSQL rollback (`23503`); reading status rolls back to `'draft'`.
16. **SECURITY DEFINER Search-Path Abuse:** Unqualified table/helper references → Prevented by `SET search_path = public, pg_temp` and explicit `public.` schema qualification.
17. **SQL Injection:** Dynamic query construction → N/A (all queries use static parameterized SQL).
18. **Service-Role Authorization:** Service-role context execution → Tested via database-layer context simulation (Assertion 82).
19. **Audit Log Bypass:** Direct client mutation of `audit_logs` → Blocked (`42501`).
20. **Notification Leakage:** Plaintext parcel code in notifications or audit logs → Verified 0 occurrences (Assertion 77).
21. **Historical File Modification:** Altering locked Slices 1–16 source files → Verified 0 modifications (Assertion 79 + historical manifest audit).

---

## 20. FINAL GO / NO-GO GATE TABLE & PLAN STATUS

| Gate | Classification | Notes |
| :--- | :--- | :--- |
| Plan completeness | **DESIGN-VERIFIED** | All 20 sections fully specified; single authoritative document |
| Slice 1–16 immutability | **DESIGN-VERIFIED / RUNTIME VERIFICATION PENDING** | 37 historical files listed; Slice 16 SHA-256 references independently computed; Slices 1–15 have no authoritative embedded hash. Runtime re-computation required to confirm continued on-disk integrity. |
| ACL completeness | **DESIGN-VERIFIED / RUNTIME VERIFICATION PENDING** | `has_function_privilege()` queries specified for all 22 routines; actual catalog state has not yet been queried — live catalog verification pending runtime execution |
| poll_votes RLS — UPDATE | **PLAN-SPECIFIED / RUNTIME VERIFICATION PENDING** | RESTRICTIVE `USING(false)` → 0 rows, SQLSTATE `00000`; actual RLS evaluation not yet confirmed against live database |
| poll_votes RLS — DELETE | **PLAN-SPECIFIED / RUNTIME VERIFICATION PENDING** | RESTRICTIVE `USING(false)` → 0 rows, SQLSTATE `00000`; actual RLS evaluation not yet confirmed against live database |
| RLS correctness (all tables) | **PLAN-SPECIFIED / RUNTIME VERIFICATION PENDING** | RESTRICTIVE/PERMISSIVE policies specified per PostgreSQL semantics; runtime SQLSTATE confirmation pending |
| SECURITY DEFINER safety | **DESIGN-VERIFIED / RUNTIME VERIFICATION PENDING** | `search_path = public, pg_temp` and explicit schema qualification specified in plan; actual `pg_proc` catalog entries not yet queried — runtime catalog check pending |
| Gate pass state machine | **DESIGN-VERIFIED** | 4-row transition table locked; resident reactivation BLOCKED |
| Parcel security | **DESIGN-VERIFIED** | CSPRNG sampling, SHA-256 storage, 5-attempt lockout, zero log leakage locked |
| Parking concurrency | **DESIGN-VERIFIED** | Model A deeded `property_id` preservation & canonical lock order locked |
| Utility ledger integrity | **PLAN-SPECIFIED / RUNTIME VERIFICATION PENDING** | Atomic FK rollback & Slice 15 ledger integration specified; runtime FK rollback test pending |
| Poll integrity | **DESIGN-VERIFIED** | IMMUTABLE option validator, active poll confidentiality, one-vote-per-property locked |
| SOS security | **DESIGN-VERIFIED** | Mandatory resolution notes, duplicate alert prevention, 4-state machine locked |
| Adversarial coverage | **DESIGN-VERIFIED** | 21 threat vectors explicitly detailed |
| Assertion inventory | **DESIGN-VERIFIED** | All 82 assertions explicitly specified in Section 14, sequentially numbered 1–82 |
| Historical hash evidence | **DESIGN-VERIFIED / RUNTIME VERIFICATION PENDING** | Slice 16 reference hashes independently computed at Slice 16 audit time; Slices 1–15 documented as NO AUTHORITATIVE REFERENCE HASH. Runtime re-computation against live files required to confirm integrity. |
| Application compatibility | **PLAN-SPECIFIED / RUNTIME VERIFICATION PENDING** | Static inspection of `src/App.jsx` and `src/supabase.js` found 0 direct legacy function references; broader compatibility subject to runtime verification |
| Implementation authorization | **NONE** | No DDL executed; no files created; baseline 469/469 PASS unchanged |

---

```text
==================================================
SLICE 17 — FINAL IMPLEMENTATION PLAN v3.3

STATUS: PLAN-ONLY / PENDING FINAL USER IMPLEMENTATION APPROVAL

LOCKED BASELINE:          469 / 469 PASS (100% LOCKED)
SLICE 17 ASSERTIONS:      82  (Assertions 1 through 82)
PLANNED CUMULATIVE SCORE: 469 + 82 = 551 PASS
SECTIONS:                 20

PARCEL LOCKOUT:    5 failed attempts — USER-APPROVED DESIGN DECISION
RESIDENT REACTIVATION: BLOCKED (security-preferred default — LOCKED)
POLL_VOTES UPDATE: RESTRICTIVE USING(false) → 0 rows, SQLSTATE 00000
POLL_VOTES DELETE: RESTRICTIVE USING(false) → 0 rows, SQLSTATE 00000
TRIGGER ROLE:      Defense-in-depth (privileged bypass paths only)
SERVICE-ROLE TEST: Assertion 82

IMPLEMENTATION AUTHORIZATION: NONE
RUNTIME VERIFICATION:         PENDING

NO APPLICATION OR DATABASE IMPLEMENTATION HAS BEEN AUTHORIZED.
==================================================
```

---

### v3.3 CONSISTENCY CHECK

- [x] **Exactly 82 assertions** — Section 14 lists Assertions 1 through 82, verified by count.
- [x] **Assertions numbered 1–82** — Sequential, no sub-labels, no gaps. Sub-labels `56a`/`56b` eliminated.
- [x] **Exactly 20 sections** — Sections 1–20 present. No Section 21.
- [x] **469 + 82 = 551** — Stated in header, Section 18 step 11, and final gate block.
- [x] **Assertion 56 uses RLS `USING(false)`** — "RESTRICTIVE RLS `pol_poll_votes_restrictive_update` `USING(false)`. The existing target row is not eligible for update — RLS excludes it before the statement executor touches it."
- [x] **Assertion 57 uses RLS `USING(false)`** — "RESTRICTIVE RLS `pol_poll_votes_restrictive_delete` `USING(false)`. The target row is not eligible for deletion — RLS excludes it before deletion."
- [x] **Both Assertions 56 and 57 expect 0 rows / SQLSTATE `00000`** — Stated explicitly in both assertion entries.
- [x] **poll_votes trigger is defense-in-depth only** — Stated in Section 1C, Section 12, and Assertions 56 and 57: "installed as defense-in-depth for privileged/bypass paths."
- [x] **Assertion 82 is service-role simulation** — "Database-layer service-role context simulation (`SET LOCAL ROLE service_role;`)..."
- [x] **Resident gate-pass reactivation is BLOCKED** — Section 9 gate table final row: "BLOCKED — Residents cannot reactivate suspended passes."
- [x] **No "USER APPROVAL REQUIRED" remains for resident reactivation** — Not present in this document.
- [x] **No superseded 81/550 assertion model remains** — Not present as authoritative claims in this document.
- [x] **No superseded `42501` poll_votes DELETE model remains** — `42501` for poll_votes DELETE not present as an authoritative outcome; `42501` appears only in unrelated assertions (blocked INSERTs, privilege denials) where it is correct.
- [x] **Historical hash claim corrected** — `SLICE16_REMEDIATION_LOCK_RECORD.md` hash annotated as independently computed over the full file byte sequence; "self-referential, authoritative" wording eliminated.
- [x] **Application compatibility claim is evidence-scoped** — "Static inspection of `src/App.jsx` and `src/supabase.js` found zero direct references..." No unsupported "zero breaking changes" assertion remains.
- [x] **Gate table uses DESIGN-VERIFIED / RUNTIME VERIFICATION PENDING correctly** — Properties requiring live catalog or runtime execution now carry the `/ RUNTIME VERIFICATION PENDING` suffix; purely structural design properties retain `DESIGN-VERIFIED`.
- [x] **No implementation has been performed** — Section 17 confirms files do not exist. No DDL was executed.
- [x] **Historical Slices 1–16 remain untouched** — Section 15 manifest; Section 17 boundary; Section 20 gate table.

**ALL CHECKS: PASS**

**READY FOR FINAL USER IMPLEMENTATION APPROVAL**

**NO APPLICATION OR DATABASE IMPLEMENTATION HAS BEEN AUTHORIZED.**
