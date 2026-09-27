# SLICE 17 — INDEPENDENT ADVERSARIAL AUDIT HANDOFF PACKAGE

```text
IMPLEMENTATION STATUS: IMPLEMENTATION COMPLETE — 551/551 PASS
LOCKED BASELINE: SLICES 1–16 — 469/469 PASS — LOCKED & UNTOUCHED
SLICE 17 SCORE: 82/82 PASS
CUMULATIVE VERIFICATION SCORE: 551/551 PASS
PACKAGE STATUS: FROZEN FOR INDEPENDENT ADVERSARIAL SECURITY AUDIT
PACKAGE TIMESTAMP: 2026-09-05T19:29:54+05:30
```

---

## A. CURRENT IMPLEMENTATION STATUS

* **Slices 1–16 Locked Baseline:** **469/469 PASS** (100% verified, untouched).
* **Slice 17 Scope:** **82/82 PASS** (100% verified assertions).
* **Combined Cumulative Verification:** **551/551 PASS** (100% full regression pass).
* **Implementation Freeze:** **ACTIVE**. No further code, schema, function, trigger, policy, or test edits are authorized.

---

## B. EXACT FROZEN FILES AND INTEGRITY HASHES

The four files below represent the complete, frozen Slice 17 evidence package:

| File Name | Absolute Path | SHA-256 Hash | Size (Bytes) | Last Modified |
|---|---|---|---|---|
| `database/schema_slice17.sql` | `d:\Clients Applications\SU Society App\database\schema_slice17.sql` | `86CA0F54FC44289906D4EEA0F65D0B745712EC26F956F96D7DE63D696709A21D` | 71,939 | 2026-09-05 19:15:02 |
| `database/verify_slice17.sql` | `d:\Clients Applications\SU Society App\database\verify_slice17.sql` | `A40237C7A4BDD84509BF4EF1FCDE34DB0E354830763116E0EB07C1ECC05E5426` | 69,086 | 2026-09-05 19:16:35 |
| `scratch/run_all17.ps1` | `d:\Clients Applications\SU Society App\scratch\run_all17.ps1` | `2A470FB520A95172C14E33C8A6E4DAE015772B7A02D26F935D0AD38191C55D9C` | 2,755 | 2026-09-05 18:36:42 |
| `SLICE17_IMPLEMENTATION_AND_VERIFICATION_REPORT.md` | `d:\Clients Applications\SU Society App\SLICE17_IMPLEMENTATION_AND_VERIFICATION_REPORT.md` | `D745EF79016C397094874BA3C55E9D764A0BE4DE94E93E550A15439705570EC2` | 8,657 | 2026-09-05 18:37:07 |

---

## C. DATABASE CATALOG EVIDENCE SUMMARY

### 1. Tables Managed (9 Tables):
* `public.gate_passes` (RLS Enabled, RESTRICTIVE Policies: `pol_gate_passes_restrictive_insert/update/delete`, SELECT Policy: `pol_gate_passes_select`).
* `public.parcel_logs` (RLS Enabled, RESTRICTIVE Policies: `pol_parcel_restrictive_insert/update/delete`, SELECT Policy: `pol_parcel_select`).
* `public.sos_alerts` (RLS Enabled, RESTRICTIVE Policies: `pol_sos_restrictive_insert/update/delete`, SELECT Policy: `pol_sos_select`).
* `public.utility_meters` (RLS Enabled, RESTRICTIVE Policies: `pol_utility_meters_restrictive_delete`, Admin Policy: `pol_utility_meters_admin_all`, SELECT Policy: `pol_utility_meters_select_member`).
* `public.meter_readings` (RLS Enabled, RESTRICTIVE Policies: `pol_meter_readings_restrictive_insert/update/delete`, SELECT Policy: `pol_meter_readings_select`).
* `public.parking_slots` (RLS Enabled, RESTRICTIVE Policies: `pol_slots_restrictive_update/delete`, Admin Policy: `pol_slots_admin_all`, SELECT Policy: `pol_slots_select_member`).
* `public.vehicles` (RLS Enabled, RESTRICTIVE Policies: `pol_vehicles_restrictive_insert/update`, Owner Delete: `pol_vehicles_owner_delete`, SELECT Policy: `pol_vehicles_select`).
* `public.polls` (RLS Enabled, RESTRICTIVE Policies: `pol_polls_restrictive_insert/update/delete`, SELECT Policy: `pol_polls_select`).
* `public.poll_votes` (RLS Enabled, RESTRICTIVE Policies: `pol_poll_votes_restrictive_insert`, `pol_poll_votes_restrictive_update` `USING(false)`, `pol_poll_votes_restrictive_delete` `USING(false)`, SELECT Policy: `pol_poll_votes_select`).

### 2. Workflow Routines (16 SECURITY DEFINER Functions):
All functions configured with `SECURITY DEFINER`, `search_path = public, pg_temp`, `REVOKE EXECUTE FROM PUBLIC, authenticated, anon`, `GRANT EXECUTE TO authenticated, service_role`:
1. `public.issue_gate_pass(UUID, UUID, UUID, TIMESTAMPTZ, TIMESTAMPTZ)`
2. `public.transition_gate_pass_status(UUID, VARCHAR)`
3. `public.log_parcel_delivery(UUID, UUID, VARCHAR, VARCHAR, UUID)`
4. `public.collect_parcel(UUID, VARCHAR)`
5. `public.trigger_sos_alert(UUID, UUID, VARCHAR)`
6. `public.acknowledge_sos_alert(UUID)`
7. `public.resolve_sos_alert(UUID, VARCHAR, TEXT)`
8. `public.submit_meter_reading(UUID, DATE, NUMERIC)`
9. `public.verify_and_bill_meter_reading(UUID)`
10. `public.register_vehicle(UUID, UUID, VARCHAR, VARCHAR)`
11. `public.delete_vehicle(UUID)`
12. `public.assign_parking_slot(UUID, UUID, UUID)`
13. `public.release_parking_slot(UUID, UUID)`
14. `public.create_poll(UUID, VARCHAR, TEXT, JSONB, TIMESTAMPTZ, TIMESTAMPTZ)`
15. `public.transition_poll_status(UUID, VARCHAR)`
16. `public.cast_poll_vote(UUID, UUID, VARCHAR)`

### 3. Hardened Legacy Routines (6 Functions):
Configured with `REVOKE EXECUTE FROM PUBLIC, authenticated, anon; GRANT EXECUTE TO service_role`:
`fn_cast_poll_vote`, `fn_assign_parking_slot`, `fn_transition_gate_pass_state`, `fn_transition_parcel_state`, `fn_transition_meter_reading_state`, `fn_transition_sos_alert`.

### 4. Mutation Protection Triggers (5 Triggers):
* `trg_prevent_direct_gate_pass_update` on `gate_passes`
* `trg_prevent_direct_parcel_update` on `parcel_logs`
* `trg_protect_sos_status_update` on `sos_alerts`
* `trg_prevent_direct_meter_reading_update` on `meter_readings`
* `trg_vehicles_auto_release_parking` on `vehicles`
* `trg_prevent_vote_mutations` on `poll_votes`

---

## D. SECURITY ARCHITECTURE OVERVIEW

1. **Strict RLS & RESTRICTIVE Execution Boundaries:** Direct client SQL `INSERT`, `UPDATE`, and `DELETE` on operational tables are blocked by RESTRICTIVE policies (`USING(false)` or `auth.role() = 'service_role'`). Data mutations MUST flow through validated `SECURITY DEFINER` workflow functions.
2. **Identity & GUC Security:** Every procedure extracts caller identity directly via `v_caller := auth.uid()`. User-supplied or GUC claim spoofing (`app.caller_id`, etc.) is strictly ignored.
3. **Cross-Society & Tenant Isolation:** Procedures verify `get_user_society_id(v_caller) = p_society_id` and check active property ownership or tenancy via `property_owners` and `tenancies`. Cross-society queries return 0 rows.
4. **Parcel Security & Brute-Force Lockout:** 6-digit collection codes are generated using 4-byte CSPRNG rejection sampling over `extensions.gen_random_bytes(4)`. Only SHA-256 hashes (`collection_code_hash`) are stored (`collection_code = NULL` enforced by check constraint). 5 failed collection attempts permanently transition parcel status to `'locked_failed_attempts'`. Plaintext codes are never logged in `audit_logs` or `notifications`.
5. **Gate Pass Reactivation Restriction:** Property residents can suspend passes (`active -> suspended`), but are strictly forbidden from reactivating suspended passes (`suspended -> active`). Reactivation requires Admin or Gatekeeper with verified staff status.
6. **Poll Vote Confidentiality & Mutation Shield:** Direct client `UPDATE` and `DELETE` on `poll_votes` are blocked by RESTRICTIVE `USING(false)` policies. Individual vote selections are readable ONLY by the voter (`voter_id = auth.uid()`). Active poll result tallies are suppressed until the poll is closed by an admin after `ends_at`.
7. **Deeded Parking Ownership & Canonical Lock Ordering:** `parking_slots.property_id` represents permanent deeded ownership and is immutable. `assigned_vehicle_id` is dynamic and automatically unlinked via `trg_vehicles_auto_release_parking` when a vehicle is deleted. Slot allocation procedures lock `parking_slots` rows first (`FOR UPDATE ORDER BY id`), then `vehicles` rows (`FOR UPDATE ORDER BY id`) to prevent concurrency deadlocks.
8. **Sub-Meter Utility Billing Atomicity:** Meter readings require monotonic validation. `verify_and_bill_meter_reading` posts a debit transaction to `ledger_transactions`. On ledger FK failure (unmapped user), the transaction rolls back cleanly, preserving `'draft'` status without orphaned ledger entries.

---

## E. DETAILED SCHEMA ADAPTATION & COMPATIBILITY INVENTORY

The table below documents every schema adaptation made during Slice 17 implementation to reconcile pre-existing table declarations from legacy slices (Slices 5/8/11/12) with Slice 17 specifications:

| Adaptation # | Target Table / Object | Original Legacy Definition | New Slice 17 Definition | Rationale & Security / Integrity Impact |
|---|---|---|---|---|
| **1** | `gate_passes.chk_gate_pass_status` | `CHECK (status IN ('pending', 'active', 'suspended'))` | `CHECK (status IN ('pending', 'active', 'suspended', 'expired'))` | Supports pass expiration. Preserves state-machine integrity without weakening status constraints. |
| **2** | `parcel_logs.chk_parcel_status` | `CHECK (status IN ('received_at_gate', 'collected', 'returned'))` | `CHECK (status IN ('received_at_gate', 'collected', 'locked_failed_attempts', 'returned'))` | Enables brute-force lockout status `'locked_failed_attempts'`. Strengthens security against brute-force attacks. |
| **3** | `meter_readings.chk_reading_status` | `CHECK (status IN ('draft', 'verified', 'billed', 'rejected'))` | `CHECK (status IN ('draft', 'submitted', 'verified', 'billed', 'rejected'))` | Supports resident submission status `'submitted'` before admin billing. |
| **4** | `vehicles.chk_vehicle_type` | `CHECK (vehicle_type IN ('2-wheeler', '4-wheeler'))` | `CHECK (vehicle_type IN ('four_wheeler', 'two_wheeler', '2-wheeler', '4-wheeler'))` | Accommodates both legacy string formats and canonical Slice 17 enum values. |
| **5** | `sos_alerts.sos_alerts_alert_type_check` | `CHECK (alert_type IN ('security', 'medical', 'fire', 'lift_emergency', 'other'))` | Constraint dropped via `ALTER TABLE ... DROP CONSTRAINT IF EXISTS` | Allows default `'general'` alert type and custom emergency categories. |
| **6** | `gate_passes.staff_id` & `requested_by` | `NOT NULL` | `NULL` (`ALTER COLUMN DROP NOT NULL`) | Supports visitor passes (where `staff_id` is NULL) and legacy fixture rows. |
| **7** | `parcel_logs.collection_code` | `NOT NULL` | `NULL` (`ALTER COLUMN DROP NOT NULL`) | Enforces security rule storing only SHA-256 hashes (`collection_code_hash`), keeping plaintext code NULL in database. |
| **8** | `sos_alerts.raised_by`, `utility_meters.utility_type`, `meter_readings.created_by`, `polls.description` | `NOT NULL` | `NULL` (`ALTER COLUMN DROP NOT NULL`) | Accommodates optional fields and legacy column mappings (`raised_by` alongside `triggered_by`, `utility_type` alongside `meter_type`). |
| **9** | `meter_readings.consumption` & `total_charge` | `GENERATED ALWAYS AS (...) STORED` | Generated expression dropped via `ALTER COLUMN DROP EXPRESSION IF EXISTS` | Allows explicit consumption calculation and fee application inside PL/pgSQL procedures. |
| **10** | `parcel_logs` Status Trigger | Checks `app.parcel_transition = NEW.id::text` | `trg_prevent_direct_parcel_update_func` checks both `app.workflow_context = 'parcel_transition'` and `app.parcel_transition = NEW.id::text` | Maintains dual compatibility with Slice 17 workflow context and legacy Slice 8 trigger checks. |
| **11** | `ledger_transactions` Posting | `source_meter_reading_id` was omitted | `verify_and_bill_meter_reading` sets `source_meter_reading_id = p_reading_id` | Satisfies `chk_ledger_source_exclusive` constraint on `ledger_transactions`. |

---

## F. VERIFICATION MAPPING (82 ASSERTIONS)

The 82 assertions in `database/verify_slice17.sql` map to specific security properties and database enforcement mechanisms:

* **Assertions 1–9 (Gate Pass Lifecycle & Security):**
  - Asserts resident issuance, RLS direct INSERT/UPDATE/DELETE blocking, cross-property SELECT isolation, forged property issuance rejection, admin status transition, date range validation (`valid_from < valid_until`), and cross-society transition rejection.
* **Assertions 10–19 (Parcel Delivery, CSPRNG & Brute-Force Lockout):**
  - Asserts gatekeeper delivery logging, CSPRNG code generation, `collection_code = NULL` enforcement, RLS blocks, recipient SELECT isolation, wrong code attempt counter increment, non-recipient collection rejection, recipient collection, replay collection rejection, and 5-attempt brute-force lockout (`locked_failed_attempts`).
* **Assertions 20–28 (Emergency SOS Alert Workflows):**
  - Asserts resident trigger, RLS blocks, cross-society SELECT isolation, forged property trigger rejection, `uq_active_sos_alert_property` concurrency serialization, gatekeeper acknowledgment, and admin resolution with mandatory notes.
* **Assertions 29–39 (Sub-Meter Utility Billing & Ledger Integrity):**
  - Asserts resident submission, RLS blocks, admin meter creation, cross-property SELECT isolation, admin billing & debit posting to `ledger_transactions`, deterministic FK failure transaction rollback test (`session_replication_role = 'replica'`), and `FOR UPDATE` duplicate billing race rejection.
* **Assertions 40–49 (Parking Slot Allocation & Vehicle Management):**
  - Asserts vehicle registration, admin parking slot creation, RLS blocks, non-owner vehicle deletion block, owner vehicle deletion, `FOR UPDATE` slot lock ordering, `FOR UPDATE` vehicle lock ordering, and parking release preserving deeded `property_id`.
* **Assertions 50–67 (Community Polls & Voting Engine):**
  - Asserts admin poll creation, JSONB option validation (`fn_validate_poll_options`), RLS blocks, vote casting (`cast_poll_vote`), vote mutation RESTRICTIVE `USING(false)` blocks (Assertions 56–57), member vote privacy SELECT isolation, invalid choice rejection, closed poll vote rejection, cross-society/non-resident vote rejection, `uq_poll_property_vote` duplicate vote serialization, active poll result query rejection, non-admin close rejection, early close rejection, and admin poll closure with aggregate result retrieval.
* **Assertions 68–73 (Security Configuration & Catalog Audits):**
  - Asserts forged GUC claim rejection (`auth.uid()` identity enforcement), catalog `search_path = public, pg_temp` audit across all 16 routines, catalog EXECUTE revocation audit on legacy routines, catalog ACL audit on new routines, catalog parcel log constraint audit, and cross-society SELECT 0-row audit.
* **Assertions 74–80 (Audit Logs & Notifications Integrity):**
  - Asserts workflow audit log generation, direct audit log INSERT/DELETE RLS/privilege blocks, zero plaintext code leakage in audit/notification text, invalid delivery transaction rollback, immutability manifest check, and notification RLS blocks.
* **Assertions 81–82 (Triggers & Context Simulation):**
  - Asserts `trg_vehicles_auto_release_parking` execution on vehicle deletion, and database-layer service-role context simulation (`SET LOCAL ROLE service_role;`).

---

## G. KNOWN AREAS REQUIRING ADVERSARIAL SCRUTINY

The independent security reviewer is requested to pay particular attention to the following 14 areas:

1. **GUC / Session-Context Authorization:** Verify that setting session GUCs (`app.workflow_context`, `app.parcel_transition`) cannot be abused by unprivileged users via direct SQL to bypass status update triggers.
2. **SECURITY DEFINER Boundaries:** Inspect all 16 workflow functions to confirm `search_path = public, pg_temp` prevents search-path hijacking and that no dynamic SQL strings are evaluated.
3. **RLS Policy Composition:** Confirm that RESTRICTIVE policies on all 9 tables correctly restrict client SQL operations for `authenticated` and `anon` roles.
4. **Nullable Legacy Identity Columns:** Inspect legacy columns (`requested_by`, `raised_by`, `created_by`, `submitted_by`) to confirm nullability does not allow identity spoofing.
5. **Generated-Column Removal:** Verify that dropping generated column expressions on `meter_readings.consumption` and `total_charge` does not create calculation inconsistencies in financial billing.
6. **Replaced CHECK Constraints:** Review updated CHECK constraints (`chk_gate_pass_status`, `chk_parcel_status`, `chk_reading_status`, `chk_vehicle_type`) to confirm no valid state is excluded and no invalid state is permitted.
7. **Direct SQL Bypass Attempts:** Verify that direct `INSERT`, `UPDATE`, or `DELETE` statements executed by residents or gatekeepers fail cleanly under RLS.
8. **Cross-Society Isolation:** Inspect society ID checks across all workflow functions to ensure users from Society A cannot interact with resources in Society B.
9. **Concurrency & Race Conditions:** Review `FOR UPDATE` lock ordering in parking slot allocation and duplicate vote handling under `uq_poll_property_vote`.
10. **Poll Vote Confidentiality:** Verify that individual vote choices cannot be enumerated by non-voters or regular members during or after an active poll.
11. **Parcel Collection Code CSPRNG & Lockout:** Inspect the rejection-sampling CSPRNG logic (`extensions.gen_random_bytes(4)`) and verify that 5 wrong collection attempts permanently lock the parcel record.
12. **Ledger Billing Atomicity:** Confirm that any runtime failure during `verify_and_bill_meter_reading` rolls back the transaction completely without leaving orphaned debit entries.
13. **Parking Deeded Ownership Preservation:** Confirm that releasing a parking slot or deleting a vehicle never clears or alters `parking_slots.property_id`.
14. **Audit & Notification Integrity:** Verify that direct client writes to `audit_logs` and `notifications` are blocked, and that plaintext collection codes never appear in log payloads.

---

## H. INDEPENDENT REVIEWER INSTRUCTIONS

> **Slice 17 is frozen. The next reviewer must perform an independent adversarial security audit only. No implementation modifications are authorized during that review.**
>
> The independent reviewer must inspect the actual implementation files and PostgreSQL catalog state directly. The reviewer is authorized to return one of the following verdicts:
> - **PASS**
> - **FAIL**
> - **PARTIAL**
> - **SECURITY CONCERN**
> - **TEST GAP**
> - **DESIGN WEAKNESS**
>
> The reviewer must NOT modify any SQL, schema, function, trigger, policy, or test files during the audit.
