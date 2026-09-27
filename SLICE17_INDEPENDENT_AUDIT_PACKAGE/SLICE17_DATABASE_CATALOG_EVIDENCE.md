# SLICE 17 — DATABASE CATALOG EVIDENCE

```text
EVIDENCE TYPE:    LIVE POSTGRESQL CATALOG (READ-ONLY CAPTURE)
CAPTURE DATE:     2026-09-05
SUPABASE VERSION: postgres:17.6.1.165
CONTAINER:        supabase_db_SU_Society_App
DATABASE:         postgres
METHOD:           docker exec psql queries against pg_catalog / information_schema
MODIFICATIONS:    NONE — all queries were read-only SELECT statements
```

> **IMPORTANT TO REVIEWER:** The data in this document reflects the ACTUAL live database catalog
> state at the time of package preparation. It is NOT generated from source code alone.
> Where source code claims differ from catalog evidence, the catalog is authoritative.

---

## SECTION 1 — TABLE COLUMN DEFINITIONS

All columns sourced from `information_schema.columns`.
Format: `column_name | data_type | char_max_len | is_nullable | column_default | generation_expression`

### 1.1 `public.gate_passes`

| Column | Data Type | Max Len | Nullable | Default | Generated |
|---|---|---|---|---|---|
| `id` | uuid | — | NO | `gen_random_uuid()` | — |
| `society_id` | uuid | — | NO | — | — |
| `property_id` | uuid | — | NO | — | — |
| `staff_id` | uuid | — | **YES** | — | — |
| `status` | character varying | 50 | NO | `'pending'::varchar` | — |
| `valid_from` | timestamp with time zone | — | NO | — | — |
| `valid_until` | timestamp with time zone | — | NO | — | — |
| `requested_by` | uuid | — | **YES** | — | — |
| `approved_by` | uuid | — | YES | — | — |
| `approved_at` | timestamp with time zone | — | YES | — | — |
| `created_at` | timestamp with time zone | — | NO | `now()` | — |
| `updated_at` | timestamp with time zone | — | NO | `now()` | — |
| `created_by` | uuid | — | YES | — | — |

> **AUDITOR NOTE:** `staff_id` and `requested_by` are nullable. The workflow function uses
> `created_by = v_caller` (from `auth.uid()`) for identity. `requested_by` is not populated
> by the Slice 17 `issue_gate_pass` function — it uses `created_by` instead.

---

### 1.2 `public.parcel_logs`

| Column | Data Type | Max Len | Nullable | Default | Generated |
|---|---|---|---|---|---|
| `id` | uuid | — | NO | `gen_random_uuid()` | — |
| `society_id` | uuid | — | NO | — | — |
| `property_id` | uuid | — | NO | — | — |
| `unit_id` | uuid | — | YES | — | — |
| `recipient_user_id` | uuid | — | YES | — | — |
| `carrier_name` | character varying | 150 | NO | — | — |
| `tracking_number` | character varying | 150 | YES | — | — |
| `status` | character varying | 30 | NO | `'received_at_gate'::varchar` | — |
| `collection_code` | character varying | 10 | **YES** | — | — |
| `logged_by` | uuid | — | NO | — | — |
| `collected_by` | uuid | — | YES | — | — |
| `collected_at` | timestamp with time zone | — | YES | — | — |
| `created_at` | timestamp with time zone | — | NO | `now()` | — |
| `updated_at` | timestamp with time zone | — | NO | `now()` | — |
| `collection_code_hash` | character varying | 64 | YES | — | — |
| `failed_collection_attempts` | integer | — | NO | `0` | — |

> **AUDITOR NOTE:** `collection_code` is nullable by design — the Slice 17 security model
> stores ONLY the SHA-256 hash in `collection_code_hash`. The `log_parcel_delivery` function
> explicitly passes `collection_code = NULL` at INSERT time. `collection_code_hash` itself
> is also nullable; the CHECK constraint `chk_code_stored_as_hash` (see §2) enforces that
> `collection_code IS NULL` whenever `collection_code_hash IS NOT NULL`.

---

### 1.3 `public.sos_alerts`

| Column | Data Type | Max Len | Nullable | Default | Generated |
|---|---|---|---|---|---|
| `id` | uuid | — | NO | `gen_random_uuid()` | — |
| `society_id` | uuid | — | NO | — | — |
| `property_id` | uuid | — | NO | — | — |
| `raised_by` | uuid | — | **YES** | — | — |
| `alert_type` | character varying | 50 | NO | — | — |
| `status` | character varying | 20 | NO | `'triggered'::varchar` | — |
| `acknowledged_by` | uuid | — | YES | — | — |
| `acknowledged_at` | timestamp with time zone | — | YES | — | — |
| `resolved_by` | uuid | — | YES | — | — |
| `resolved_at` | timestamp with time zone | — | YES | — | — |
| `resolution_notes` | text | — | YES | — | — |
| `created_at` | timestamp with time zone | — | NO | `now()` | — |
| `triggered_by` | uuid | — | YES | — | — |

> **AUDITOR NOTE:** Two identity columns exist: `raised_by` (legacy, nullable) and
> `triggered_by` (Slice 17 canonical, also nullable). The `trigger_sos_alert` function
> writes to `triggered_by = v_caller`. The `sos_alerts_alert_type_check` constraint was
> **DROPPED** (see Schema Adaptations §4). No alert_type CHECK constraint exists in the
> live catalog. `alert_type` is NOT NULL but unconstrained by CHECK.

---

### 1.4 `public.utility_meters`

| Column | Data Type | Max Len | Nullable | Default | Generated |
|---|---|---|---|---|---|
| `id` | uuid | — | NO | `gen_random_uuid()` | — |
| `society_id` | uuid | — | NO | — | — |
| `property_id` | uuid | — | NO | — | — |
| `utility_type` | character varying | 50 | **YES** | — | — |
| `meter_number` | character varying | 100 | NO | — | — |
| `unit_rate` | numeric | — | NO | — | — |
| `status` | character varying | 20 | NO | `'active'::varchar` | — |
| `created_at` | timestamp with time zone | — | NO | `now()` | — |
| `meter_type` | character varying | 50 | YES | `'electricity'::varchar` | — |

> **AUDITOR NOTE:** Two type columns: `utility_type` (legacy, nullable, constrained by
> `chk_meter_type` which checks `utility_type`) and `meter_type` (nullable with default).
> `chk_meter_type` applies to `utility_type` column with values `('water','electricity','gas','hvac')`.

---

### 1.5 `public.meter_readings`

| Column | Data Type | Max Len | Nullable | Default | Generated |
|---|---|---|---|---|---|
| `id` | uuid | — | NO | `gen_random_uuid()` | — |
| `meter_id` | uuid | — | NO | — | — |
| `reading_date` | date | — | NO | — | — |
| `previous_reading` | numeric | — | NO | — | — |
| `current_reading` | numeric | — | NO | — | — |
| `consumption` | numeric | — | **YES** | — | **NONE** (expression dropped) |
| `applied_unit_rate` | numeric | — | NO | — | — |
| `total_charge` | numeric | — | **YES** | — | **NONE** (expression dropped) |
| `status` | character varying | 20 | NO | `'draft'::varchar` | — |
| `ledger_transaction_id` | uuid | — | YES | — | — |
| `created_at` | timestamp with time zone | — | NO | `now()` | — |
| `created_by` | uuid | — | YES | — | — |
| `property_id` | uuid | — | YES | — | — |
| `total_amount` | numeric | — | YES | — | — |
| `submitted_by` | uuid | — | YES | — | — |
| `verified_at` | timestamp with time zone | — | YES | — | — |
| `verified_by` | uuid | — | YES | — | — |

> **AUDITOR NOTE (CRITICAL):** `consumption` and `total_charge` no longer have GENERATED
> expressions. The database does NOT enforce that `consumption = current_reading - previous_reading`.
> The `submit_meter_reading` function computes `v_consumption := p_current_reading - v_prev_val`
> in PL/pgSQL and inserts it explicitly into `consumption`. There is no database-engine guarantee
> that the stored value matches the arithmetic relationship. `total_charge` is not populated by
> the workflow — `total_amount` is used instead. `total_charge` may be NULL in all rows.

---

### 1.6 `public.parking_slots`

| Column | Data Type | Max Len | Nullable | Default | Generated |
|---|---|---|---|---|---|
| `id` | uuid | — | NO | `uuid_generate_v4()` | — |
| `society_id` | uuid | — | NO | — | — |
| `slot_number` | character varying | 50 | NO | — | — |
| `property_id` | uuid | — | **YES** | — | — |
| `is_visitor` | boolean | — | NO | `false` | — |
| `created_at` | timestamp with time zone | — | NO | `now()` | — |
| `assigned_vehicle_id` | uuid | — | YES | — | — |

> **AUDITOR NOTE:** `property_id` is nullable (visitor slots have no deeded owner).
> For resident slots, `property_id` represents permanent deeded ownership.
> The `release_parking_slot` function comment explicitly states it never modifies `property_id`.

---

### 1.7 `public.vehicles`

| Column | Data Type | Max Len | Nullable | Default | Generated |
|---|---|---|---|---|---|
| `id` | uuid | — | NO | `uuid_generate_v4()` | — |
| `society_id` | uuid | — | NO | — | — |
| `property_id` | uuid | — | NO | — | — |
| `registration_number` | character varying | 30 | NO | — | — |
| `vehicle_type` | character varying | 30 | NO | — | — |
| `parking_slot_id` | uuid | — | YES | — | — |
| `created_at` | timestamp with time zone | — | NO | `now()` | — |
| `owner_user_id` | uuid | — | YES | — | — |

---

### 1.8 `public.polls`

| Column | Data Type | Max Len | Nullable | Default | Generated |
|---|---|---|---|---|---|
| `id` | uuid | — | NO | `uuid_generate_v4()` | — |
| `society_id` | uuid | — | NO | — | — |
| `title` | character varying | 255 | NO | — | — |
| `description` | text | — | **YES** | — | — |
| `status` | character varying | 20 | NO | `'draft'::varchar` | — |
| `starts_at` | timestamp with time zone | — | NO | — | — |
| `ends_at` | timestamp with time zone | — | NO | — | — |
| `created_by` | uuid | — | NO | — | — |
| `created_at` | timestamp with time zone | — | NO | `now()` | — |
| `options` | jsonb | — | YES | — | — |

> **AUDITOR NOTE:** `description` is nullable. `options` (JSONB poll choices) is also nullable
> at the column level; enforcement of non-empty options relies on the `fn_validate_poll_options`
> trigger/function, not a column NOT NULL constraint.

---

### 1.9 `public.poll_votes`

| Column | Data Type | Max Len | Nullable | Default | Generated |
|---|---|---|---|---|---|
| `id` | uuid | — | NO | `uuid_generate_v4()` | — |
| `poll_id` | uuid | — | NO | — | — |
| `property_id` | uuid | — | NO | — | — |
| `voter_id` | uuid | — | NO | — | — |
| `vote_choice` | character varying | 100 | NO | — | — |
| `created_at` | timestamp with time zone | — | NO | `now()` | — |

---

## SECTION 2 — CONSTRAINTS

### 2.1 PRIMARY KEYS

| Table | Constraint | Columns |
|---|---|---|
| `gate_passes` | `gate_passes_pkey` | `id` |
| `parcel_logs` | `parcel_logs_pkey` | `id` |
| `sos_alerts` | `sos_alerts_pkey` | `id` |
| `utility_meters` | `utility_meters_pkey` | `id` |
| `meter_readings` | `meter_readings_pkey` | `id` |
| `parking_slots` | `parking_slots_pkey` | `id` |
| `vehicles` | `vehicles_pkey` | `id` |
| `polls` | `polls_pkey` | `id` |
| `poll_votes` | `poll_votes_pkey` | `id` |

### 2.2 UNIQUE CONSTRAINTS / INDEXES

| Table | Index Name | Columns / Predicate |
|---|---|---|
| `gate_passes` | `idx_unique_active_pass` | `(property_id, staff_id) WHERE status IN ('pending','active')` |
| `meter_readings` | `meter_readings_meter_id_reading_date_key` | `(meter_id, reading_date)` |
| `parking_slots` | `uq_society_slot` | `(society_id, slot_number)` |
| `poll_votes` | `uq_poll_property_vote` | `(poll_id, property_id)` |
| `utility_meters` | `utility_meters_society_id_meter_number_key` | `(society_id, meter_number)` |
| `vehicles` | `uq_parking_slot_assignment` | `(parking_slot_id)` |
| `vehicles` | `uq_society_vehicle` | `(society_id, registration_number)` |
| `sos_alerts` | `uq_active_sos_alert_property` | `(property_id) WHERE status IN ('triggered','acknowledged')` |

### 2.3 CHECK CONSTRAINTS

| Table | Constraint Name | Clause |
|---|---|---|
| `gate_passes` | `chk_gate_pass_status` | `status IN ('pending','active','suspended','expired')` |
| `parcel_logs` | `chk_parcel_status` | `status IN ('received_at_gate','collected','locked_failed_attempts','returned')` |
| `sos_alerts` | `sos_alerts_status_check` | `status IN ('triggered','acknowledged','resolved','false_alarm')` |
| `sos_alerts` | ~~`sos_alerts_alert_type_check`~~ | **DROPPED** — no alert_type CHECK in live catalog |
| `utility_meters` | `chk_meter_rate_positive` | `unit_rate >= 0.00` |
| `utility_meters` | `chk_meter_status` | `status IN ('active','inactive','maintenance')` |
| `utility_meters` | `chk_meter_type` | `utility_type IN ('water','electricity','gas','hvac')` |
| `meter_readings` | `chk_reading_status` | `status IN ('draft','submitted','verified','billed','rejected')` |
| `vehicles` | `chk_vehicle_type` | `vehicle_type IN ('four_wheeler','two_wheeler','2-wheeler','4-wheeler')` |
| `polls` | `chk_poll_dates` | `ends_at > starts_at` |
| `polls` | `chk_poll_status` | `status IN ('draft','active','closed')` |

---

## SECTION 3 — INDEXES (NON-UNIQUE)

| Table | Index Name | Definition |
|---|---|---|
| `meter_readings` | `idx_meter_readings_meter` | `USING btree (meter_id)` |
| `meter_readings` | `idx_meter_readings_status` | `USING btree (status)` |
| `parcel_logs` | `idx_parcel_logs_property_id` | `USING btree (property_id)` |
| `parcel_logs` | `idx_parcel_logs_society_id_status` | `USING btree (society_id, status)` |
| `parking_slots` | `idx_slots_property` | `USING btree (property_id)` |
| `parking_slots` | `idx_slots_society` | `USING btree (society_id)` |
| `poll_votes` | `idx_poll_votes_poll` | `USING btree (poll_id)` |
| `polls` | `idx_polls_society` | `USING btree (society_id)` |
| `polls` | `idx_polls_status` | `USING btree (status)` |
| `sos_alerts` | `idx_sos_alerts_property_id` | `USING btree (property_id)` |
| `sos_alerts` | `idx_sos_alerts_society_id` | `USING btree (society_id)` |
| `sos_alerts` | `idx_sos_alerts_status` | `USING btree (status)` |
| `utility_meters` | `idx_utility_meters_property` | `USING btree (property_id)` |
| `utility_meters` | `idx_utility_meters_society` | `USING btree (society_id)` |
| `vehicles` | `idx_vehicles_property` | `USING btree (property_id)` |
| `vehicles` | `idx_vehicles_society` | `USING btree (society_id)` |

---

## SECTION 4 — ROW LEVEL SECURITY STATUS

Sourced from `pg_class.relrowsecurity` and `pg_class.relforcerowsecurity`.

| Table | RLS Enabled | RLS Forced |
|---|---|---|
| `gate_passes` | YES | NO |
| `parcel_logs` | YES | NO |
| `sos_alerts` | YES | NO |
| `utility_meters` | YES | NO |
| `meter_readings` | YES | NO |
| `parking_slots` | YES | NO |
| `vehicles` | YES | NO |
| `polls` | YES | NO |
| `poll_votes` | YES | NO |

> **AUDITOR NOTE:** `relforcerowsecurity = false` for all tables means RLS is bypassed for
> the table owner (`postgres`). The SECURITY DEFINER functions run as `postgres` and therefore
> **bypass RLS entirely** when executing DML. This is by design — the workflow functions are
> the intended mutation path. Direct client DML (as `authenticated`) is controlled by RLS.

---

## SECTION 5 — RLS POLICIES

Sourced from `pg_policies`. Format: `PERMISSIVE/RESTRICTIVE | CMD | roles | USING | WITH CHECK`

### 5.1 `gate_passes`

| Policy Name | Type | Command | USING | WITH CHECK |
|---|---|---|---|---|
| `pol_gate_passes_restrictive_delete` | RESTRICTIVE | DELETE | `false` | — |
| `pol_gate_passes_restrictive_insert` | RESTRICTIVE | INSERT | — | `false` |
| `pol_gate_passes_restrictive_update` | RESTRICTIVE | UPDATE | `false` | — |
| `pol_gate_passes_select` | PERMISSIVE | SELECT | `society_id = get_user_society_id(auth.uid())` | — |

### 5.2 `parcel_logs`

| Policy Name | Type | Command | USING | WITH CHECK |
|---|---|---|---|---|
| `pol_parcel_restrictive_delete` | RESTRICTIVE | DELETE | `false` | — |
| `pol_parcel_restrictive_insert` | RESTRICTIVE | INSERT | — | `false` |
| `pol_parcel_restrictive_update` | RESTRICTIVE | UPDATE | `false` | — |
| `pol_parcel_select` | PERMISSIVE | SELECT | `society_id = get_user_society_id(auth.uid())` | — |

### 5.3 `sos_alerts`

| Policy Name | Type | Command | USING | WITH CHECK |
|---|---|---|---|---|
| `policy_sos_delete` | RESTRICTIVE | DELETE | `false` | — |
| `pol_sos_restrictive_insert` | RESTRICTIVE | INSERT | — | `false` |
| `pol_sos_restrictive_update` | RESTRICTIVE | UPDATE | `false` | — |
| `policy_sos_insert` | PERMISSIVE | INSERT | — | `society_id = get_user_society_id(auth.uid()) AND (is_property_owner OR is_property_tenant)` |
| `pol_sos_select` | PERMISSIVE | SELECT | `is_admin() OR triggered_by = auth.uid() OR gatekeeper in society` | — |
| `policy_sos_select` | PERMISSIVE | SELECT | `society_id match AND (is_admin OR gatekeeper OR owner OR tenant)` | — |
| `policy_sos_update` | PERMISSIVE | UPDATE | `false` | — |

> **AUDITOR NOTE:** Multiple overlapping SELECT policies exist on `sos_alerts`. The RESTRICTIVE
> DELETE/UPDATE policies block direct client mutations. However, `policy_sos_insert` is PERMISSIVE
> and allows direct INSERT for residents — this is a legacy policy that coexists with the
> RESTRICTIVE INSERT policy `pol_sos_restrictive_insert`. The RESTRICTIVE INSERT policy
> (`WITH CHECK false`) takes precedence and blocks all direct client INSERTs regardless.

### 5.4 `utility_meters`

| Policy Name | Type | Command | USING | WITH CHECK |
|---|---|---|---|---|
| `pol_utility_meters_restrictive_delete` | RESTRICTIVE | DELETE | `false` | — |
| `pol_utility_meters_admin` | PERMISSIVE | ALL | `is_admin() AND society_id match` | — |
| `pol_utility_meters_admin_all` | PERMISSIVE | ALL | `is_admin()` | — |
| `pol_utility_meters_member` | PERMISSIVE | SELECT | `owner or tenant of property` | — |
| `pol_utility_meters_select_member` | PERMISSIVE | SELECT | `society_id = get_user_society_id(auth.uid())` | — |

> **AUDITOR NOTE:** No RESTRICTIVE INSERT or UPDATE policies on `utility_meters`. Admin users
> (`is_admin()`) can directly INSERT/UPDATE utility meters via RLS PERMISSIVE ALL policies.
> This is an intentional design: admin users manage meter infrastructure directly.

### 5.5 `meter_readings`

| Policy Name | Type | Command | USING | WITH CHECK |
|---|---|---|---|---|
| `pol_meter_readings_restrictive_delete` | RESTRICTIVE | DELETE | `false` | — |
| `pol_meter_readings_restrictive_insert` | RESTRICTIVE | INSERT | — | `false` |
| `pol_meter_readings_restrictive_update` | RESTRICTIVE | UPDATE | `false` | — |
| `pol_meter_readings_select` | PERMISSIVE | SELECT | `society_id = get_user_society_id(auth.uid())` | — |

### 5.6 `parking_slots`

| Policy Name | Type | Command | USING | WITH CHECK |
|---|---|---|---|---|
| `pol_slots_restrictive_delete` | RESTRICTIVE | DELETE | `false` | — |
| `pol_slots_restrictive_update` | RESTRICTIVE | UPDATE | `false` | — |
| `pol_slots_admin` | PERMISSIVE | ALL | `is_admin() AND society_id match` | — |
| `pol_slots_admin_all` | PERMISSIVE | ALL | `is_admin()` | — |
| `pol_slots_select_member` | PERMISSIVE | SELECT | `society_id = get_user_society_id(auth.uid())` | — |

### 5.7 `vehicles`

| Policy Name | Type | Command | USING | WITH CHECK |
|---|---|---|---|---|
| `pol_vehicles_restrictive_insert` | RESTRICTIVE | INSERT | — | `false` |
| `pol_vehicles_restrictive_update` | RESTRICTIVE | UPDATE | `false` | — |
| `pol_vehicles_admin` | PERMISSIVE | ALL | `is_admin() AND society_id match` | — |
| `pol_vehicles_delete_resident` | PERMISSIVE | DELETE | `owner_user_id = auth.uid() OR is_admin()` | — |
| `pol_vehicles_insert_resident` | PERMISSIVE | INSERT | — | `society match AND (owner OR tenant)` |
| `pol_vehicles_select` | PERMISSIVE | SELECT | `society_id match` | — |
| `pol_vehicles_select_member` | PERMISSIVE | SELECT | `society_id match` | — |
| `pol_vehicles_update_resident` | PERMISSIVE | UPDATE | `society match AND (owner OR tenant)` | — |

> **AUDITOR NOTE:** RESTRICTIVE INSERT/UPDATE block direct INSERT/UPDATE for all clients.
> A PERMISSIVE DELETE policy (`pol_vehicles_delete_resident`) exists for `owner_user_id = auth.uid()`.
> No RESTRICTIVE DELETE policy exists on `vehicles`. This means vehicle owners CAN directly
> DELETE their own vehicle records without going through `delete_vehicle` RPC. Whether
> the `trg_vehicles_auto_release_parking` trigger fires correctly on direct DELETE must be verified.

### 5.8 `polls`

| Policy Name | Type | Command | USING | WITH CHECK |
|---|---|---|---|---|
| `pol_polls_restrictive_delete` | RESTRICTIVE | DELETE | `false` | — |
| `pol_polls_restrictive_insert` | RESTRICTIVE | INSERT | — | `false` |
| `pol_polls_restrictive_update` | RESTRICTIVE | UPDATE | `false` | — |
| `pol_polls_admin` | PERMISSIVE | ALL | `is_admin() AND society_id match` | — |
| `pol_polls_select` | PERMISSIVE | SELECT | `society_id match` | — |
| `pol_polls_select_member` | PERMISSIVE | SELECT | `society_id match` | — |

### 5.9 `poll_votes`

| Policy Name | Type | Command | USING | WITH CHECK |
|---|---|---|---|---|
| `pol_poll_votes_restrictive_delete` | RESTRICTIVE | DELETE | `false` | — |
| `pol_poll_votes_restrictive_insert` | RESTRICTIVE | INSERT | — | `false` |
| `pol_poll_votes_restrictive_update` | RESTRICTIVE | UPDATE | `false` | — |
| `pol_poll_votes_select` | PERMISSIVE | SELECT | `voter_id = auth.uid() OR is_admin()` | — |
| `pol_votes_select_admin` | PERMISSIVE | SELECT | `is_admin() AND poll in same society` | — |
| `pol_votes_select_voter` | PERMISSIVE | SELECT | `voter_id = auth.uid()` | — |

---

## SECTION 6 — TRIGGERS

All triggers sourced from `information_schema.triggers`.

| Trigger Name | Table | Events | Timing | Orientation | Function |
|---|---|---|---|---|---|
| `trg_audit_gate_passes` | `gate_passes` | INSERT, UPDATE, DELETE | AFTER | ROW | `fn_audit_trigger_func()` |
| `trg_gate_passes_force_requested_by` | `gate_passes` | INSERT | BEFORE | ROW | `fn_gate_passes_force_requested_by()` |
| `trg_gate_passes_updated_at` | `gate_passes` | UPDATE | BEFORE | ROW | `set_updated_at()` |
| `trg_prevent_direct_gate_pass_update` | `gate_passes` | UPDATE | BEFORE | ROW | `trg_prevent_direct_gate_pass_update_func()` |
| `trg_audit_meter_readings` | `meter_readings` | INSERT, UPDATE, DELETE | AFTER | ROW | `fn_audit_trigger_func()` |
| `trg_prevent_direct_meter_reading_update` | `meter_readings` | UPDATE | BEFORE | ROW | `trg_prevent_direct_meter_reading_update_func()` |
| `trg_audit_parcel_logs` | `parcel_logs` | INSERT, UPDATE, DELETE | AFTER | ROW | `fn_audit_parcel_logs_redacted()` |
| `trg_notify_parcel_insert` | `parcel_logs` | INSERT | AFTER | ROW | `fn_notify_parcel_received()` |
| `trg_notify_parcel_update` | `parcel_logs` | UPDATE | AFTER | ROW | `fn_notify_parcel_received()` |
| `trg_parcel_logs_isolation` | `parcel_logs` | INSERT, UPDATE | BEFORE | ROW | `trg_validate_parcel_isolation()` |
| `trg_parcel_logs_updated_at` | `parcel_logs` | UPDATE | BEFORE | ROW | `set_updated_at()` |
| `trg_prevent_direct_parcel_update` | `parcel_logs` | UPDATE | BEFORE | ROW | `trg_prevent_direct_parcel_update_func()` |
| `trg_prevent_vote_mutations` | `poll_votes` | UPDATE, DELETE | BEFORE | ROW | `trg_prevent_vote_mutations_func()` |
| `trg_audit_polls` | `polls` | INSERT, UPDATE, DELETE | AFTER | ROW | `fn_audit_trigger_func()` |
| `trg_poll_transitions` | `polls` | UPDATE, DELETE | BEFORE | ROW | `trg_validate_poll_transitions()` |
| `trg_audit_sos_alerts` | `sos_alerts` | INSERT, UPDATE, DELETE | AFTER | ROW | `fn_audit_trigger_func()` |
| `trg_dispatch_sos_notification` | `sos_alerts` | INSERT | AFTER | ROW | `fn_dispatch_sos_notification()` |
| `trg_prevent_sos_immutable_mutations` | `sos_alerts` | UPDATE | BEFORE | ROW | `fn_prevent_sos_immutable_mutations()` |
| `trg_protect_sos_status_update` | `sos_alerts` | UPDATE | BEFORE | ROW | `trg_protect_sos_status_update_func()` |
| `trg_validate_sos_alert_creation` | `sos_alerts` | INSERT | BEFORE | ROW | `fn_validate_sos_alert_creation()` |
| `trg_audit_utility_meters` | `utility_meters` | INSERT, UPDATE, DELETE | AFTER | ROW | `fn_audit_trigger_func()` |
| `trg_vehicles_auto_release_parking` | `vehicles` | DELETE | BEFORE | ROW | `trg_vehicles_auto_release_parking_func()` |

---

## SECTION 7 — SECURITY DEFINER FUNCTION CATALOG

All data sourced from `pg_proc` and `pg_roles`.
ACL format: `role=privilege/grantor` where `X` = EXECUTE.

### 7.1 The 16 Slice 17 Workflow Functions

All 16 functions share the following security profile:
- **Owner:** `postgres`
- **SECURITY DEFINER:** YES
- **search_path:** `{search_path=public, pg_temp}`
- **EXECUTE ACL:** `postgres=X/postgres; authenticated=X/postgres; service_role=X/postgres`

> **AUDITOR NOTE:** `anon` does NOT have EXECUTE on any workflow function. Access is limited
> to `authenticated` and `service_role`. The PUBLIC default EXECUTE grant was explicitly revoked.

| # | Function Signature |
|---|---|
| 1 | `issue_gate_pass(p_society_id uuid, p_property_id uuid, p_staff_id uuid, p_valid_from timestamptz, p_valid_until timestamptz)` |
| 2 | `transition_gate_pass_status(p_pass_id uuid, p_new_status varchar)` |
| 3 | `log_parcel_delivery(p_society_id uuid, p_property_id uuid, p_carrier_name varchar, p_tracking_number varchar, p_recipient_user_id uuid)` |
| 4 | `collect_parcel(p_parcel_id uuid, p_collection_code varchar)` |
| 5 | `trigger_sos_alert(p_society_id uuid, p_property_id uuid, p_alert_type varchar)` |
| 6 | `acknowledge_sos_alert(p_alert_id uuid)` |
| 7 | `resolve_sos_alert(p_alert_id uuid, p_resolution_status varchar, p_resolution_notes text)` |
| 8 | `submit_meter_reading(p_meter_id uuid, p_reading_date date, p_current_reading numeric)` |
| 9 | `verify_and_bill_meter_reading(p_reading_id uuid)` |
| 10 | `register_vehicle(p_society_id uuid, p_property_id uuid, p_registration_number varchar, p_vehicle_type varchar)` |
| 11 | `assign_parking_slot(p_society_id uuid, p_parking_slot_id uuid, p_vehicle_id uuid)` |
| 12 | `release_parking_slot(p_society_id uuid, p_parking_slot_id uuid)` |
| 13 | `create_community_poll(p_society_id uuid, p_title varchar, p_description text, p_options jsonb, p_starts_at timestamptz, p_ends_at timestamptz)` |
| 14 | `close_community_poll(p_poll_id uuid)` |
| 15 | `get_poll_results(p_poll_id uuid)` |
| 16 | `cast_poll_vote(p_poll_id uuid, p_property_id uuid, p_vote_choice varchar)` |

> **AUDITOR NOTE:** The catalog shows `delete_vehicle` is NOT present as a standalone function.
> The vehicle deletion path is direct DELETE via the PERMISSIVE RLS policy `pol_vehicles_delete_resident`.
> `create_poll`, `transition_poll_status` are named `create_community_poll` and `close_community_poll`
> in the live catalog. Reviewers should verify these catalog names against the handoff document's claim
> of 16 specific function names.

---

### 7.2 The 6 Hardened Legacy Functions

| Function | Owner | Security | search_path | EXECUTE ACL |
|---|---|---|---|---|
| `fn_assign_parking_slot(p_vehicle_id uuid, p_slot_id uuid)` | postgres | SECURITY DEFINER | `{"search_path=\"\""}` | `postgres=X; service_role=X` |
| `fn_cast_poll_vote(p_poll_id uuid, p_property_id uuid, p_vote_choice varchar)` | postgres | SECURITY DEFINER | `{"search_path=\"\""}` | `postgres=X; service_role=X` |
| `fn_transition_gate_pass_state(p_pass_id uuid, p_new_status varchar)` | postgres | SECURITY DEFINER | `{search_path=public, pg_temp}` | `postgres=X; service_role=X` |
| `fn_transition_meter_reading_state(p_reading_id uuid, p_new_status varchar)` | postgres | SECURITY DEFINER | `{search_path=public, pg_temp}` | `postgres=X; service_role=X` |
| `fn_transition_parcel_state(p_parcel_id uuid, p_new_status varchar, p_collection_code varchar)` | postgres | SECURITY DEFINER | `{search_path=public, pg_temp}` | `postgres=X; service_role=X` |
| `fn_transition_sos_alert(p_alert_id uuid, p_new_status varchar, p_notes text)` | postgres | SECURITY DEFINER | `{search_path=public, pg_temp}` | `postgres=X; service_role=X` |

> **AUDITOR NOTE (CRITICAL):** `fn_assign_parking_slot` and `fn_cast_poll_vote` have
> `search_path=""` (empty string) rather than `search_path=public, pg_temp`. An empty
> search_path means unqualified object references in these functions would fail to resolve.
> These functions should be inspected to verify they use fully-qualified object names or
> that the empty search_path does not cause functional failures.

---

### 7.3 Validation Function

| Function | Owner | Security | search_path | EXECUTE ACL |
|---|---|---|---|---|
| `fn_validate_poll_options(p_options jsonb)` | postgres | SECURITY INVOKER | `{search_path=public, pg_temp}` | `(none)` — no explicit ACL |

> **AUDITOR NOTE:** `fn_validate_poll_options` has no explicit ACL. In PostgreSQL, when `proacl`
> is NULL, the default EXECUTE privilege applies: PUBLIC has EXECUTE. Any authenticated or
> anonymous user can directly call `fn_validate_poll_options`. This function is used as a
> trigger validation routine; direct invocation by clients is a low-severity exposure.

---

## SECTION 8 — RELEVANT RELATED TABLE RELATIONSHIPS

The following tables from prior slices are referenced by Slice 17 functions but not directly managed:

- `public.audit_logs` — Written to by all 16 workflow functions (INSERT only via SECURITY DEFINER)
- `public.notifications` — Written to by gate pass and parcel functions
- `public.ledger_transactions` — Written to by `verify_and_bill_meter_reading`; constrained by `chk_ledger_source_exclusive`
- `public.user_roles` — Read by workflow functions to verify gatekeeper/admin roles
- `public.property_owners` — Read to verify resident ownership
- `public.tenancies` / `public.units` — Read to verify tenant residency
- `auth.users` — Read by `issue_gate_pass` and `transition_gate_pass_status` to check `raw_app_meta_data->>'verification_status'`

---

*End of Database Catalog Evidence. All data sourced from live PostgreSQL catalog via read-only queries. No database objects were created, modified, or dropped during evidence capture.*
