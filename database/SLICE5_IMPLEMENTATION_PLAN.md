# SU SOCIETY APP — SLICE 5 PRE-IMPLEMENTATION ARCHITECTURE AUDIT & IMPLEMENTATION PLAN

## A. Repository Audit
1. **Existing database files:** `schema_slice1.sql` through `schema_slice4.sql` are the authoritative schema definition files.
2. **Existing Slice 1 files:** `schema_slice1.sql`, `verify_slice1.sql`
3. **Existing Slice 2 files:** `schema_slice2.sql`, `verify_slice2.sql`
4. **Existing Slice 3 files:** `schema_slice3.sql`, `verify_slice3.sql`
5. **Existing Slice 4 files:** `schema_slice4.sql`, `verify_slice4.sql`
6. **Verification scripts:** Node-based test runners exist in `scratch/` (e.g., `create_verify_slice4.js`, `run_all.ps1`).
7. **Teardown scripts:** `database/drop_tables.sql` and `scratch/drop_tables.sql` manage clean environments.
8. **Frontend/API:** `src/App.jsx` and `src/supabase.js` constitute the frontend, which currently operates entirely via mocked data arrays and mocked Supabase client functions. 
9. **Legacy schemas:** `schema_phase2.sql` contains deprecated unified financial architecture.
10. **Unmigrated Functionality:** All objects within `schema_phase2.sql` have been migrated into Slices 1-4. No unmigrated schema remains. However, broad product requirements like Polling, Notices, Documents, and Vehicles are visibly absent from Slices 1–4.

## B. Locked Baseline Confirmation
The authoritative database architecture is confirmed and strictly locked:
- **Slice 1:** 97/97 PASS
- **Slice 2:** 34/34 PASS
- **Slice 3:** 19/19 PASS
- **Slice 4:** 40/40 PASS
- **TOTAL:** 190/190 PASS

## C. Existing Slice 1–4 Functionality Inventory
* **Slice 1:** Identity, Societies, Properties, Units, Users, User roles, Ownerships, Tenancies, RLS, Cross-society isolation.
* **Slice 2:** Base Ledger, Maintenance policies, Maintenance charges, Payments, Expenses, Payment state machine.
* **Slice 3:** Amenities, Amenity bookings, Technician tickets, Ticket comments, Visitor logs, Booking state machine.
* **Slice 4:** Payment allocations, Receipts, Expense vouchers, Budgets, Bank reconciliations, Custom billing, Opening balances, Notifications.

## D. Legacy Schema Mapping
* `schema_phase2.sql` was exhaustively reviewed.
* **Current Status:** Deprecated / Obsolete.
* **Belongs in Slice 5?** No. 100% of the tables defined in `schema_phase2.sql` (policies, ledger, payments, custom billing, receipts) are already covered by the authoritative Slice 1–4 architecture. There is nothing to migrate from the legacy file.

## E. Slice 5 Business Scope
Based on a complete Society Management architecture, Slice 5 will strictly implement:
1. **Governance:** Secure polling and resolutions enforcing `[AD-1]` (One vote per property).
2. **Notice Board:** Society-wide and role-targeted broadcast announcements.
3. **Vehicles & Parking:** Assignment of resident vehicles to secure parking slots.
4. **Document Repository:** References for society and property-specific files (NOCs, bylaws).
5. **Reporting Layer:** Secure Database Views to support the eventual frontend migration from mock data to live API.

## F. Complete Table Design

### 1. `notices`
* **Purpose:** Society-scoped broadcast announcements.
* **Columns:**
  - `id` UUID PRIMARY KEY DEFAULT `uuid_generate_v4()`
  - `society_id` UUID NOT NULL
  - `title` VARCHAR(255) NOT NULL
  - `content` TEXT NOT NULL
  - `visibility` VARCHAR(30) NOT NULL DEFAULT 'all'
  - `attachment_url` VARCHAR(1024) NULL
  - `expires_at` TIMESTAMPTZ NULL
  - `created_by` UUID NOT NULL
  - `created_at` TIMESTAMPTZ NOT NULL DEFAULT `now()`
* **FK:** `society_id` -> `societies(id)` ON DELETE RESTRICT, `created_by` -> `users(id)` ON DELETE RESTRICT
* **CHECK:** `visibility IN ('all', 'owners', 'tenants', 'committee')`
* **CHECK:** `expires_at IS NULL OR expires_at > created_at`
* **UNIQUE:** None.
* **Indexes:** `society_id`, `created_at`
* **RLS:** Enabled, FORCE RLS.
* **Audit:** Notice creation and deletion.
* **Immutability:** Mutable by author/admin.

### 2. `polls`
* **Purpose:** Defines a society resolution or voting event.
* **Columns:**
  - `id` UUID PRIMARY KEY DEFAULT `uuid_generate_v4()`
  - `society_id` UUID NOT NULL
  - `title` VARCHAR(255) NOT NULL
  - `description` TEXT NOT NULL
  - `status` VARCHAR(20) NOT NULL DEFAULT 'draft'
  - `starts_at` TIMESTAMPTZ NOT NULL
  - `ends_at` TIMESTAMPTZ NOT NULL
  - `created_by` UUID NOT NULL
  - `created_at` TIMESTAMPTZ NOT NULL DEFAULT `now()`
* **FK:** `society_id` -> `societies(id)`, `created_by` -> `users(id)`
* **CHECK:** `status IN ('draft', 'active', 'closed')`
* **CHECK:** `ends_at > starts_at`
* **Indexes:** `society_id`, `status`
* **RLS:** Enabled, FORCE RLS.
* **Audit:** State transitions.
* **Immutability:** Core fields immutable once `status != 'draft'`.

### 3. `poll_votes`
* **Purpose:** Immutable record of a property's vote.
* **Columns:**
  - `id` UUID PRIMARY KEY DEFAULT `uuid_generate_v4()`
  - `poll_id` UUID NOT NULL
  - `property_id` UUID NOT NULL
  - `voter_id` UUID NOT NULL
  - `vote_choice` VARCHAR(100) NOT NULL
  - `created_at` TIMESTAMPTZ NOT NULL DEFAULT `now()`
* **FK:** `poll_id` -> `polls(id)` ON DELETE RESTRICT, `property_id` -> `properties(id)` ON DELETE RESTRICT, `voter_id` -> `users(id)` ON DELETE RESTRICT.
* **UNIQUE:** `(poll_id, property_id)` — **Enforces [AD-1] One vote per property.**
* **Indexes:** `poll_id`
* **RLS:** Enabled, FORCE RLS.
* **Audit:** Vote cast event.
* **Immutability:** Strictly Immutable. Deletes/Updates blocked.

### 4. `parking_slots`
* **Purpose:** Defines physical parking locations in the society.
* **Columns:**
  - `id` UUID PRIMARY KEY DEFAULT `uuid_generate_v4()`
  - `society_id` UUID NOT NULL
  - `slot_number` VARCHAR(50) NOT NULL
  - `property_id` UUID NULL
  - `is_visitor` BOOLEAN NOT NULL DEFAULT FALSE
  - `created_at` TIMESTAMPTZ NOT NULL DEFAULT `now()`
* **FK:** `society_id` -> `societies(id)`, `property_id` -> `properties(id)`
* **UNIQUE:** `(society_id, slot_number)`
* **Indexes:** `society_id`, `property_id`
* **RLS:** Enabled, FORCE RLS.
* **Audit:** None.
* **Immutability:** Mutable by Admins.

### 5. `vehicles`
* **Purpose:** Tracks vehicles and assigns them to slots.
* **Columns:**
  - `id` UUID PRIMARY KEY DEFAULT `uuid_generate_v4()`
  - `society_id` UUID NOT NULL
  - `property_id` UUID NOT NULL
  - `registration_number` VARCHAR(30) NOT NULL
  - `vehicle_type` VARCHAR(30) NOT NULL
  - `parking_slot_id` UUID NULL
  - `created_at` TIMESTAMPTZ NOT NULL DEFAULT `now()`
* **FK:** `society_id`, `property_id`, `parking_slot_id` -> `parking_slots(id)`
* **CHECK:** `vehicle_type IN ('2-wheeler', '4-wheeler')`
* **UNIQUE:** `(society_id, registration_number)`
* **UNIQUE:** `parking_slot_id` (Ensures exactly 1 vehicle per slot; NULLs allowed).
* **Indexes:** `society_id`, `property_id`
* **RLS:** Enabled, FORCE RLS.
* **Audit:** Registration and deletion.
* **Immutability:** Mutable.

### 6. `documents`
* **Purpose:** Secure metadata tracking for uploaded files.
* **Columns:**
  - `id` UUID PRIMARY KEY DEFAULT `uuid_generate_v4()`
  - `society_id` UUID NOT NULL
  - `property_id` UUID NULL
  - `title` VARCHAR(255) NOT NULL
  - `document_type` VARCHAR(50) NOT NULL
  - `file_url` VARCHAR(1024) NOT NULL
  - `uploaded_by` UUID NOT NULL
  - `created_at` TIMESTAMPTZ NOT NULL DEFAULT `now()`
* **FK:** `society_id`, `property_id`, `uploaded_by`
* **CHECK:** `document_type IN ('bylaw', 'noc', 'lease', 'financial', 'other')`
* **Indexes:** `society_id`, `property_id`
* **RLS:** Enabled, FORCE RLS.
* **Audit:** Upload events.
* **Immutability:** Mutable (deletions supported).

## G. Functions/APIs

### 1. `fn_cast_poll_vote` (SECURITY DEFINER)
* **Purpose:** Processes a vote atomically while enforcing the `[AD-1]` rule.
* **Parameters:** `p_poll_id UUID`, `p_property_id UUID`, `p_vote_choice VARCHAR`
* **Return Type:** `UUID`
* **Authorization:** 
  1. Verifies `auth.uid()` is an active owner of `p_property_id`.
  2. Verifies poll exists, `society_id` matches the property, and `status = 'active'`.
  3. Verifies `NOW()` is between `starts_at` and `ends_at`.
* **Transaction Atomicity:** Fully atomic insert.
* **Hardening:** `SET search_path = ''`. Fully schema-qualified calls.
* **Audit:** Logs the vote action to `audit_logs`.

### 2. `fn_transition_poll_state` (SECURITY DEFINER)
* **Purpose:** Safely transition polls from draft -> active -> closed.
* **Parameters:** `p_poll_id UUID`, `p_target_state VARCHAR`
* **Return Type:** `BOOLEAN`
* **Authorization:** Admin only.
* **Hardening:** `SET search_path = ''`.
* **Audit:** Logs the transition.

### 3. `fn_assign_parking_slot` (SECURITY DEFINER)
* **Purpose:** Prevents cross-property/cross-society slot assignment attacks.
* **Parameters:** `p_vehicle_id UUID`, `p_slot_id UUID`
* **Return Type:** `BOOLEAN`
* **Authorization:**
  1. Validates caller is active admin OR owner/tenant of the vehicle's property.
  2. Validates `p_slot_id` belongs to the same property OR is unassigned, and society matches.
  3. Blocks assignment to `is_visitor = TRUE` slots for resident vehicles.

## H. Views / Reporting Layer
### `vw_member_financial_statement`
* **Purpose:** Consolidates a property's financial statement.
* **Logic:** Aggregates `ledger_transactions` for a `property_id`.
* **Security:** Acts strictly as a read-only projection over `ledger_transactions`. It inherently inherits the underlying RLS policies of the ledger table. It cannot be used to bypass isolation or mutate data.

## I. RLS Policy Matrix
* **`notices`**: SELECT (All users matching visibility rules); INSERT/UPDATE/DELETE (Admins only).
* **`polls`**: SELECT (All authenticated users); INSERT/UPDATE/DELETE (Admins only).
* **`poll_votes`**: SELECT (Admins all; Voters own); INSERT/UPDATE/DELETE (Blocked. Mutated via SECURITY DEFINER only).
* **`parking_slots`**: SELECT (Admins all; Residents own property slots); INSERT/UPDATE/DELETE (Admins only).
* **`vehicles`**: SELECT (Admins all; Residents own property); INSERT/UPDATE/DELETE (Admins and Property Residents for their own).
* **`documents`**: SELECT (Admins all; Residents society-docs + own property docs); INSERT/UPDATE/DELETE (Admins + Property Residents).

*Default Deny is preserved. Revoked users automatically lose SELECT access via standard active status checks.*

## J. State Machines
**Poll State Machine:**
* `draft` -> `active` (Authorized: Admin; Validates: ends_at > now())
* `active` -> `closed` (Authorized: Admin or Auto-eval via ends_at; Validates: none)
* Invalid Transitions: Cannot return to `draft` from `active`. Cannot reverse `closed`.
* Direct UPDATEs to `status` are blocked via Trigger; must use `fn_transition_poll_state`.

## K. Audit Events
* `poll_created`, `poll_activated`, `poll_closed`
* `vote_cast` (Logs `poll_id`, `property_id`, `voter_id`)
* `notice_created`, `notice_deleted`
* `vehicle_registered`, `vehicle_deleted`
* `parking_assigned`
* `document_uploaded`
* All events logged to existing `audit_logs` table cleanly.

## L. Concurrency Design
* **Voting:** Two concurrent attempts to vote for the same property will trigger a race condition, correctly resolved by the `UNIQUE(poll_id, property_id)` constraint. The loser of the race hits a constraint violation, ensuring exactly one vote per property.
* **Parking:** Two vehicles concurrently claiming the same slot will race on the `UNIQUE(parking_slot_id)` constraint in the `vehicles` table.
* **Poll State:** Update checks within `fn_transition_poll_state` use `SELECT ... FOR UPDATE` on the poll row to prevent concurrent double activation.

## M. Idempotency Design
* **Duplicate Vote:** Calling `fn_cast_poll_vote` a second time throws a safe unique violation.
* **Duplicate Vehicle Registration:** Throws safe unique violation on `registration_number`.
* **Duplicate Parking Assignment:** Calling `fn_assign_parking_slot` with the same inputs twice is a successful NO-OP (safe idempotency).

## N. Cross-Society Attack Matrix
* **Society 2 user voting on Society 1 poll:** REJECTED (`fn_cast_poll_vote` validates user ownership of `property_id`, which fails).
* **Society 1 user voting for Society 2 property:** REJECTED (Ownership validation fails).
* **Tenant attempting to vote:** REJECTED (`fn_cast_poll_vote` explicitly demands `is_property_owner`).
* **Revoked user voting:** REJECTED (User status validation).
* **Society 2 user reading Society 1 notice:** REJECTED (RLS on `society_id`).
* **Tenant reading committee-only notice:** REJECTED (RLS on `visibility`).
* **Resident assigning another property's parking slot:** REJECTED (`fn_assign_parking_slot` explicit validation).

## O. Frontend Integration Mapping
* **Target screens:** MemberDashboardView, AdminDashboardView, GatekeeperDashboardView.
* **Future Work:** Replacing mock arrays with standard `supabase.from()` and `supabase.rpc()` calls. Slice 5 completely prepares the API surface for this migration by providing secure views and functions.

## P. Migration / Execution Order
1. Define sequence: `notices` -> `polls` -> `poll_votes` -> `parking_slots` -> `vehicles` -> `documents`.
2. Define reporting views.
3. Define SECURITY DEFINER functions.
4. Define RLS Policies & Grants.

## Q. Verification Strategy
`verify_slice5.sql` will test:
* State machine integrity (voting on closed poll).
* Concurrency logic (duplicate votes).
* Cross-society notice reading.
* Cross-property vehicle assignment.
* Valid vote casting and ledger reporting.
* Total expected assertions: ~30.

## R. Regression Strategy
```text
drop_tables.sql
schema_slice1.sql to schema_slice4.sql
schema_slice5.sql
verify_slice1.sql (Expect 97)
verify_slice2.sql (Expect 34)
verify_slice3.sql (Expect 19)
verify_slice4.sql (Expect 40)
verify_slice5.sql (Expect ~30)
```
If Slice 1-4 tests fail, SLICE 5 FAILS.

## S. Rollback Strategy
Slice 5 can be cleanly rolled back by:
1. `DROP FUNCTION fn_assign_parking_slot`
2. `DROP FUNCTION fn_transition_poll_state`
3. `DROP FUNCTION fn_cast_poll_vote`
4. `DROP VIEW vw_member_financial_statement`
5. `DROP TABLE documents, vehicles, parking_slots, poll_votes, polls, notices CASCADE`
*This impacts zero Slice 1–4 tables or core ledger semantics.*

## T. Architectural Conflicts
ARCHITECTURAL CONFLICTS / AMBIGUITIES REQUIRING USER DECISION
**None.** There are no architectural conflicts with Slices 1–4. The immutable ledger remains untouched. The existing `technician_tickets` naming drift is preserved. 

*INFO:* Supabase Storage policies for `documents` cannot be enforced via PostgreSQL SQL schema scripts alone. They require external bucket configuration.

## U. Risk Register
* **Risk (LOW):** `vw_member_financial_statement` aggregation over a massive `ledger_transactions` table.
* **Mitigation:** Existing indexes on `ledger_transactions (property_id, direction)` are sufficient for expected dataset sizes.

## V. Exact Proposed File Changes
- Add: `database/schema_slice5.sql`
- Add: `database/verify_slice5.sql`
- Add: `scratch/create_verify_slice5.js`
- Update: `scratch/drop_tables.sql` (append Slice 5 drop commands).

## W. Final Approval Gate
See final output below.
