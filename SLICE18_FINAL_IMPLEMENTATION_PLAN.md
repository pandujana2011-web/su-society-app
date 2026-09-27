# SLICE 18 — FINAL IMPLEMENTATION PLAN (SECURITY & VERIFICATION CLOSURE COMPLETE)

**STATUS:** FINAL SECURITY CLOSURE / ZERO IMPLEMENTATION AUTHORIZATION  
**LOCKED BASELINE:** Slices 1–17 LOCKED (**551/551 PASS**)  
**TARGET REPOSITORY:** SU Society App (`D:\Clients Applications\SU Society App`)  
**DATE:** 2026-09-06  

---

## 1. EXECUTIVE SUMMARY

Slice 18 completes the **operational lifecycle, helpdesk workflows, amenity booking completion/rejection, visitor checkout, and ledger transaction constraint widening** for the SU Society App backend and frontend.

This final planning revision closes all security verification details:
1. **Executable Traceability for Financial Tests A, B1–B3, C–H:** Test B2 explicitly inspects the signature of pre-existing `approve_amenity_booking(p_booking_id UUID)`, confirming zero caller-controlled currency inputs exist and verifying server-side derivation from `societies.currency`.
2. **Comprehensive Audit Completeness (`S18-042`):** Validates server-authoritative audit record creation across all 8 Slice 18 workflow procedures.
3. **Comprehensive Notification Completeness (`S18-044`):** Validates recipient-targeted notification creation for all required workflows, and explicitly verifies zero unintended notification creation for N/A workflows (`close_ticket`, `checkout_visitor`).
4. **Emergency Permission Rollback Wording:** Clarifies that emergency `REVOKE EXECUTE` is a containment mechanism, and grant restoration is part of controlled recovery.
5. **44 Traceable Verification Assertions (`S18-001` to `S18-044`):** Fully specified assertion inventory bringing the final cumulative target to **595/595 PASS**.

**CRITICAL RULE:** This document represents a **Plan Revision Only**. Zero implementation code, database objects, migrations, or schema changes have been or will be applied until explicit user approval is granted.

---

## 2. AUTHORITATIVE BASELINE

* **Slices 1–16 Baseline:** LOCKED (469/469 PASS)
* **Slice 17 Baseline:** LOCKED & FROZEN (82/82 PASS, SHA-256 Verified)
* **Cumulative System Baseline:** **551/551 PASS**
* **Slice 18 Audit Verdict:** **`READY FOR SLICE 18 PLANNING`**
* **Slice 17 Frozen Hashes:** 5/5 SHA-256 Match Verified
* **Implementation Authorization:** NOT STARTED / ZERO CODE EXECUTED

---

## 3. SLICE 18 SCOPE

1. **Financial Integrity:** Widen `check_transaction_type` constraint on `ledger_transactions` to permit `'amenity_fee'`.
2. **Helpdesk Workflow Procedures (5 Functions):** `assign_ticket`, `start_ticket`, `resolve_ticket`, `close_ticket`, `reopen_ticket`.
3. **Amenity Booking Workflow Procedures (2 Functions):** `reject_amenity_booking`, `complete_amenity_booking`.
4. **Visitor Workflow Procedure (1 Function):** `checkout_visitor`.
5. **Pre-Existing Amenity RPC Regression Testing:** Regression test pre-existing `approve_amenity_booking` and `cancel_amenity_booking` routines against the widened `'amenity_fee'` ledger constraint.
6. **Additive SLA Columns:** Add `assigned_at`, `started_at`, `closed_at`, `reopened_at` to `helpdesk_tickets` via `ADD COLUMN IF NOT EXISTS`.
7. **Audit & Notification Completeness:** Automated, server-authoritative audit logs and recipient-targeted notifications.
8. **Frontend Integration:** Add quick-login credentials for `gatekeeper@society.com` and `technician@society.com` in `INITIAL_MOCK_DATA` and update OperationsManagerView admin tabs.

---

## 4. LOCKED ARTIFACT PROTECTION

The following files are strictly immutable and will remain untouched:
* `database/schema_slice1.sql` through `database/schema_slice17.sql`
* `database/verify_slice1.sql` through `database/verify_slice17.sql`
* `scratch/run_all.ps1` through `scratch/run_all17.ps1`
* All prior locked implementation and security report artifacts.

---

## 5. DATABASE CHANGE PLAN

### 5.1 Ledger Transaction Type Constraint Widening (Before / After Matrix)

| Constraint Name | Before (Locked Slices 1–17) | After (Slice 18 Proposed) | Safety Analysis |
| :--- | :--- | :--- | :--- |
| `check_transaction_type` | `'charge'`, `'penalty'`, `'adjustment'`, `'waiver'`, `'payment'`, `'advance_payment'`, `'refund'`, `'reversal'`, `'expense'`, `'income'` | `'charge'`, `'penalty'`, `'adjustment'`, `'waiver'`, `'payment'`, `'advance_payment'`, `'refund'`, `'reversal'`, `'expense'`, `'income'`, `'amenity_fee'` | **SAFE.** Widens allowed set without modifying existing values. Direct DML remains 100% blocked by RLS RESTRICTIVE policy (`WITH CHECK (false)`). |

```sql
-- DDL Execution Plan in schema_slice18.sql
ALTER TABLE public.ledger_transactions DROP CONSTRAINT IF EXISTS check_transaction_type;
ALTER TABLE public.ledger_transactions ADD CONSTRAINT check_transaction_type CHECK (
    transaction_type IN (
        'charge', 'penalty', 'adjustment', 'waiver', 'payment', 'advance_payment',
        'refund', 'reversal', 'expense', 'income', 'amenity_fee'
    )
);
```

### 5.2 SLA Columns DDL
```sql
ALTER TABLE public.helpdesk_tickets
    ADD COLUMN IF NOT EXISTS assigned_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS started_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS closed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS reopened_at TIMESTAMPTZ;
```

---

## 6. HELPDESK STATE-MACHINE PLAN

### 6.1 Lifecycle & Transitions

```
               ┌───────────────────────┐
               │     open (initial)    │
               └───────────┬───────────┘
                           │ assign_ticket() [admin/committee]
                           ▼
               ┌───────────────────────┐
               │        assigned       │◄─── assign_ticket() (Reassignment)
               └───────────┬───────────┘
                           │ start_ticket() [assigned tech | admin]
                           ▼
               ┌───────────────────────┐
               │      in_progress      │
               └───────────┬───────────┘
                           │ resolve_ticket() [assigned tech | admin]
                           ▼
               ┌───────────────────────┐
               │        resolved       │
               └───────────┬───────────┘
                           │ close_ticket() [created_by resident | admin]
                           ▼
               ┌───────────────────────┐
               │    closed (terminal)  │◄─── reopen_ticket() [created_by resident | admin]
               └───────────────────────┘
```

#### Permitted Transitions:
* `open → assigned` (via `assign_ticket`)
* `assigned → assigned` (Reassignment via `assign_ticket`)
* `assigned → in_progress` (via `start_ticket`)
* `in_progress → resolved` (via `resolve_ticket`) — **`assigned → resolved` is FORBIDDEN.**
* `resolved → closed` (via `close_ticket`)
* `closed → open` (via `reopen_ticket`)

#### Forbidden Transitions:
* `open → in_progress`, `open → resolved`, `open → closed` (BLOCKED, `ERRCODE = '22000'`)
* `assigned → resolved` (STRICTLY BLOCKED — must be started first, `ERRCODE = '22000'`)
* `in_progress → closed` (BLOCKED — must be resolved first, `ERRCODE = '22000'`)
* `closed → resolved`, `closed → in_progress`, `closed → assigned` (BLOCKED, `ERRCODE = '22000'`)

### 6.2 Reassignment Security Model
`assign_ticket` explicitly supports reassignment (`assigned → assigned`):
* **Authorization:** Only Admin or Executive Committee (`is_admin()` or `role_name IN ('secretary', 'treasurer', 'executive_member')`).
* **Technician Validation:** Technician must belong to the **same society** as the ticket.
* **Audit & Metadata:** Previous technician ID logged in `audit_logs` metadata (`jsonb_build_object('old_technician', v_old_tech, 'new_technician', p_technician_id)`).
* **Timestamps:** `assigned_at` is updated to `NOW()`.
* **Notifications:** Triggers notifications to both the old technician (`"Ticket Reassigned Away"`) and the new technician (`"Ticket Assigned"`).

### 6.3 8-Step Close-Ticket Authorization Chain
1. `v_caller := auth.uid()` derivation.
2. Authentication check (`v_caller IS NOT NULL`).
3. Caller society identification (`v_caller_society := get_user_society_id(v_caller)`).
4. Society isolation check (`v_ticket.society_id = v_caller_society`).
5. Creator / Residency authorization check (`v_caller = v_ticket.created_by` OR active resident of target property).
6. Role authorization check (`v_is_admin := is_admin()`).
7. State validation check (`v_ticket.status = 'resolved'`).
8. State mutation (`UPDATE status := 'closed', closed_at := NOW()`).

---

## 7. AMENITY BOOKING STATE-MACHINE PLAN

### 7.1 Lifecycle
* `pending_approval → approved → completed`
* `pending_approval → rejected`
* `any → cancelled`

### 7.2 Pre-Existing RPC Status Clarification
`approve_amenity_booking` and `cancel_amenity_booking` are **pre-existing routines from earlier locked slices**. Slice 18 does NOT modify these routines; Slice 18 adversarially regression-tests them because Slice 18 widens the `ledger_transactions.transaction_type` CHECK constraint to include `'amenity_fee'`.

### 7.3 Society Isolation & Independent Negative Coverage
* **`reject_amenity_booking(p_booking_id UUID, p_reason TEXT)`**
  * Verifies `v_booking.society_id = get_user_society_id(auth.uid())`.
  * **Independent Cross-Society Rejection Test (`S18-027`):** Society A admin attempting `reject_amenity_booking(Society B booking)` fails with SQLSTATE `42501`, leaving status as `pending_approval`.
* **`complete_amenity_booking(p_booking_id UUID)`**
  * Verifies `v_booking.society_id = get_user_society_id(auth.uid())`.
  * **Independent Cross-Society Completion Test (`S18-028`):** Society A admin attempting `complete_amenity_booking(Society B booking)` fails with SQLSTATE `42501`, leaving status as `approved` with no financial side effects or forged audit/notification logs.

---

## 8. VISITOR CHECKOUT PLAN

### `checkout_visitor(p_log_id UUID)`
* Derives `v_caller := auth.uid()` and `v_caller_society := get_user_society_id(v_caller)`.
* Fetches `visitor_logs` record `FOR UPDATE`.
* **Society Isolation Gate:** Verifies `v_visitor.society_id = v_caller_society`. Cross-society calls raise `ERRCODE = '42501'`.
* **Role Gate:** Verifies `is_admin()` OR `user_roles` contains `gatekeeper` for `v_caller_society`.
* **State Check:** Verifies `check_out IS NULL`. If already checked out, raises `'Visitor already checked out.' USING ERRCODE = '22000'`.
* **Mutation:** Sets `check_out := NOW()`.

---

## 9. AMENITY FEE FINANCIAL INTEGRITY & ADVERSARIAL TEST PLAN

### 9.1 Executable Test Suite Specification (Tests A, B1–B3, C–H)

| Test ID | Adversarial Test Objective | Attacker Action | Expected Result | SQLSTATE / Assertion ID |
| :--- | :--- | :--- | :--- | :--- |
| **Test A** | Direct `amenity_fee` insertion | `authenticated` executes `INSERT INTO ledger_transactions (..., transaction_type) VALUES (..., 'amenity_fee')` | **FAIL** | `42501` (`S18-031`) |
| **Test B1** | Direct currency injection | Attacker executes `INSERT INTO ledger_transactions (..., currency) VALUES (..., 'USD')` | **FAIL** | `42501` (`S18-032`) |
| **Test B2** | RPC currency parameter manipulation | Attacker inspects `approve_amenity_booking(p_booking_id UUID)` signature and verifies no currency param exists | **EXECUTABLE CHECK** | RPC signature accepts ONLY `booking_uuid`; resulting ledger currency strictly derived server-side from `societies.currency` (`S18-033`) |
| **Test B3** | Legitimate currency integrity | Authorized admin approves booking | **PASS** | Posted Currency matches Society (`S18-034`) |
| **Test C** | Cross-society ledger posting | Attacker executes workflow targeting property in Society B | **FAIL** | `42501` (`S18-035`) |
| **Test D** | Legitimate fee posting | Authorized admin approves booking | **PASS** | Fee posted accurately (`S18-036`) |
| **Test E** | Authoritative amount derivation | Verify posted ledger amount matches `amenity.booking_fee * hours` | **PASS** | Authoritative Calculation (`S18-037`) |
| **Test F** | Duplicate approval rejection | Admin calls `approve_amenity_booking` twice on same booking | **FAIL** | `22000` (`S18-038`) |
| **Test G** | Cancellation reversal integrity | Admin/User cancels approved booking | **PASS** | Reversal credit matches original (`S18-039`) |
| **Test H** | Duplicate reversal defense | Attacker calls `cancel_amenity_booking` on cancelled booking | **FAIL** | `22000` (`S18-040`) |

---

## 10. AUDIT LOG SECURITY & ANTI-SPOOFING

All audit logs are generated **server-side** inside `SECURITY DEFINER` routines:
* `actor_id` is derived from `auth.uid()` (never client params).
* `society_id` is derived from target object record.
* Client attempts to submit custom audit records directly via SQL `INSERT INTO audit_logs` are blocked by RLS RESTRICTIVE policies (`S18-041`).
* **Audit Completeness Assertion (`S18-042`):** Executable check verifying that every one of the 8 Slice 18 workflow routines (`assign_ticket`, `start_ticket`, `resolve_ticket`, `close_ticket`, `reopen_ticket`, `reject_amenity_booking`, `complete_amenity_booking`, `checkout_visitor`) creates a valid audit row with server-derived `actor_id` and `society_id`.

---

## 11. NOTIFICATION SECURITY & COMPLETENESS

Notifications are created server-side inside workflow routines. Direct client insertion into `notifications` for forged workflow events is blocked by RLS policies (`S18-043`).
* **Notification Completeness Assertion (`S18-044`):** Executable check verifying that notification-required workflows (`assign_ticket`, `start_ticket`, `resolve_ticket`, `reopen_ticket`, `reject_amenity_booking`, `complete_amenity_booking`) generate correct recipient-scoped notifications, while notification-N/A workflows (`close_ticket`, `checkout_visitor`) produce zero unintended notifications.

---

## 12. GRANULAR 13-POINT SECURITY MATRIX FOR ALL 8 RPCs

For every proposed function, the 13 mandatory security properties are explicitly enforced:

| Function Name | 1. `auth.uid()` Derivation | 2. Auth Requirement | 3. Caller Society Lookup | 4. Target Entity Lookup | 5. Target Society Isolation | 6. Role Validation | 7. Residency/Ownership | 8. Source State Check | 9. `FOR UPDATE` Lock | 10. Controlled Mutation | 11. Server Audit Log | 12. Server Notification | 13. Rejection Error Behavior |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `assign_ticket` | `auth.uid()` | `v_caller IS NOT NULL` | `get_user_society_id()` | `helpdesk_tickets` FOR UPDATE | `ticket.society_id = caller_society` | Admin / Executive Committee | Tech target in same society | `status IN ('open', 'assigned')` | **YES** | `status := 'assigned'` | `'ASSIGNED helpdesk ticket'` | Notifies Tech | `RAISE EXCEPTION 42501/22000` |
| `start_ticket` | `auth.uid()` | `v_caller IS NOT NULL` | `get_user_society_id()` | `helpdesk_tickets` FOR UPDATE | `ticket.society_id = caller_society` | Tech (`assigned_to`) / Admin | N/A | `status = 'assigned'` | **YES** | `status := 'in_progress'` | `'STARTED helpdesk ticket'` | Notifies Creator | `RAISE EXCEPTION 42501/22000` |
| `resolve_ticket` | `auth.uid()` | `v_caller IS NOT NULL` | `get_user_society_id()` | `helpdesk_tickets` FOR UPDATE | `ticket.society_id = caller_society` | Tech (`assigned_to`) / Admin | N/A | `status = 'in_progress'` | **YES** | `status := 'resolved'` | `'RESOLVED helpdesk ticket'` | Notifies Creator | `RAISE EXCEPTION 42501/22000` |
| `close_ticket` | `auth.uid()` | `v_caller IS NOT NULL` | `get_user_society_id()` | `helpdesk_tickets` FOR UPDATE | `ticket.society_id = caller_society` | Admin / Ticket Creator | Resident of property | `status = 'resolved'` | **YES** | `status := 'closed'` | `'CLOSED helpdesk ticket'` | N/A | `RAISE EXCEPTION 42501/22000` |
| `reopen_ticket` | `auth.uid()` | `v_caller IS NOT NULL` | `get_user_society_id()` | `helpdesk_tickets` FOR UPDATE | `ticket.society_id = caller_society` | Admin / Ticket Creator | Resident of property | `status = 'closed'` | **YES** | `status := 'open'` | `'REOPENED helpdesk ticket'` | Notifies Admin | `RAISE EXCEPTION 42501/22000` |
| `reject_amenity_booking` | `auth.uid()` | `v_caller IS NOT NULL` | `get_user_society_id()` | `amenity_bookings` FOR UPDATE | `booking.society_id = caller_society` | Admin | N/A | `status = 'pending_approval'` | **YES** | `status := 'rejected'` | `'REJECTED amenity booking'` | Notifies User | `RAISE EXCEPTION 42501/22000` |
| `complete_amenity_booking` | `auth.uid()` | `v_caller IS NOT NULL` | `get_user_society_id()` | `amenity_bookings` FOR UPDATE | `booking.society_id = caller_society` | Admin | N/A | `status = 'approved'` | **YES** | `status := 'completed'` | `'COMPLETED amenity booking'` | Notifies User | `RAISE EXCEPTION 42501/22000` |
| `checkout_visitor` | `auth.uid()` | `v_caller IS NOT NULL` | `get_user_society_id()` | `visitor_logs` FOR UPDATE | `visitor.society_id = caller_society` | Gatekeeper / Admin | Gatekeeper in same society | `check_out IS NULL` | **YES** | `check_out := NOW()` | `'CHECKED OUT visitor'` | N/A | `RAISE EXCEPTION 42501/22000` |

---

## 13. SECURITY DEFINER REVIEW STATEMENT

All 8 functions explicitly satisfy the required `SECURITY DEFINER`, fixed `search_path = public, pg_temp`, caller identity derivation (`auth.uid()`), society isolation, authorization, state validation, row-locking, and controlled-mutation requirements. Audit logging is server-authoritative for every workflow. Notifications are generated where required by the workflow specification.

---

## 14. SLA TIMESTAMP SEMANTICS

* **`assigned_at`:** Set to `NOW()` on first assignment and updated on reassignment.
* **`started_at`:** Set to `NOW()` when technician starts work (`in_progress`). Preserved if reopened.
* **`closed_at`:** Updated to `NOW()` whenever ticket transitions to `closed`.
* **`reopened_at`:** Updated to `NOW()` whenever ticket is reopened from `closed` to `open`.

---

## 15. APPLICATION INTEGRATION PLAN

1. **Mock Data Credentials (`src/supabase.js`):** Add `gatekeeper@society.com` and `technician@society.com` to `INITIAL_MOCK_DATA.users` and `user_roles`.
2. **OperationsManagerView UI (`src/App.jsx`):** Add UI action buttons for booking reject/complete and technician ticket state transitions.

---

## 16. EXPLICIT & TRACEABLE VERIFICATION ASSERTION INVENTORY (`S18-001` to `S18-044`)

Targeting $N = 44$ new assertions. Baseline: **551 PASS**. Cumulative Target: **$551 + 44 = 595$ PASS**.

### Granular Assertion Mapping

| Assertion ID | Target Object / Function | Actor Role | Setup / Preconditions | Action / Execution | Expected Result | SQLSTATE / Boundary |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **`S18-001`** | `schema_slice18.sql` | `postgres` | Slice 17 Baseline loaded | Verify 8 new routines exist | All 8 routines present | Schema Structural |
| **`S18-002`** | `schema_slice18.sql` | `postgres` | Slice 17 Baseline loaded | Verify SECURITY DEFINER & `search_path` | `pg_proc` check passes | Routine Hardening |
| **`S18-003`** | `ledger_transactions` | `postgres` | Constraint updated | Inspect `check_transaction_type` definition | Includes `'amenity_fee'` | DDL Integrity |
| **`S18-004`** | `helpdesk_tickets` | `postgres` | Columns added | Inspect SLA timestamp columns | 4 columns exist | DDL Integrity |
| **`S18-005`** | Workflow Routines | `anon` | No JWT | Call `assign_ticket` | **FAIL** | `42501` (Auth required) |
| **`S18-006`** | Workflow Routines | `anon` | No JWT | Call `checkout_visitor` | **FAIL** | `42501` (Auth required) |
| **`S18-007`** | `assign_ticket` | Admin (Society A) | Open ticket in Society A | Assign ticket to Technician A | **PASS** (`status = 'assigned'`) | Valid Assignment |
| **`S18-008`** | `assign_ticket` | Admin (Society A) | Ticket assigned to Tech A | Reassign ticket to Tech B | **PASS** (Reassigned, `assigned_at` reset) | Reassignment |
| **`S18-009`** | `assign_ticket` | Member (Society A) | Open ticket in Society A | Unprivileged member calls `assign_ticket` | **FAIL** | `42501` (Role Check) |
| **`S18-010`** | `start_ticket` | Tech A (Society A) | Ticket assigned to Tech A | Call `start_ticket` | **PASS** (`status = 'in_progress'`) | Valid Start |
| **`S18-011`** | `start_ticket` | Tech B (Society A) | Ticket assigned to Tech A | Unassigned Tech B calls `start_ticket` | **FAIL** | `42501` (Role Check) |
| **`S18-012`** | `resolve_ticket` | Tech A (Society A) | Ticket in `in_progress` | Call `resolve_ticket` | **PASS** (`status = 'resolved'`) | Valid Resolution |
| **`S18-013`** | `resolve_ticket` | Tech A (Society A) | Ticket in `assigned` status | Call `resolve_ticket` (`assigned → resolved`) | **FAIL** | `22000` (Forbidden Jump) |
| **`S18-014`** | `close_ticket` | Creator (Society A) | Ticket in `resolved` status | Creator resident calls `close_ticket` | **PASS** (`status = 'closed'`) | 8-Step Close Chain |
| **`S18-015`** | `close_ticket` | Creator (Society A) | Ticket in `in_progress` | Creator calls `close_ticket` | **FAIL** | `22000` (State Check) |
| **`S18-016`** | `close_ticket` | Resident B (Society A) | Ticket created by Resident A | Resident B calls `close_ticket` | **FAIL** | `42501` (Ownership Check) |
| **`S18-017`** | `reopen_ticket` | Creator (Society A) | Ticket in `closed` status | Creator calls `reopen_ticket` | **PASS** (`status = 'open'`) | Valid Reopen |
| **`S18-018`** | `reopen_ticket` | Creator (Society A) | Ticket in `resolved` status | Creator calls `reopen_ticket` | **FAIL** | `22000` (State Check) |
| **`S18-019`** | `assign_ticket` | Admin (Society A) | Ticket in Society B | Admin A calls `assign_ticket` on Society B ticket | **FAIL** | `42501` (Society Isolation) |
| **`S18-020`** | `start_ticket` | Tech A (Society A) | Ticket in Society B | Tech A calls `start_ticket` on Society B ticket | **FAIL** | `42501` (Society Isolation) |
| **`S18-021`** | `resolve_ticket` | Tech A (Society A) | Ticket in Society B | Tech A calls `resolve_ticket` on Society B ticket | **FAIL** | `42501` (Society Isolation) |
| **`S18-022`** | `close_ticket` | Creator (Society A) | Ticket in Society B | Creator A calls `close_ticket` on Society B ticket | **FAIL** | `42501` (Society Isolation) |
| **`S18-023`** | `reopen_ticket` | Creator (Society A) | Ticket in Society B | Creator A calls `reopen_ticket` on Society B ticket | **FAIL** | `42501` (Society Isolation) |
| **`S18-024`** | `checkout_visitor` | Gatekeeper (Society A)| Visitor log in Society B | Gatekeeper A calls `checkout_visitor` on Society B log | **FAIL** | `42501` (Society Isolation) |
| **`S18-025`** | `reject_amenity_booking`| Admin (Society A) | Booking pending approval | Admin A calls `reject_amenity_booking` | **PASS** (`status = 'rejected'`) | Valid Rejection |
| **`S18-026`** | `complete_amenity_booking`| Admin (Society A) | Booking in `approved` status | Admin A calls `complete_amenity_booking` | **PASS** (`status = 'completed'`) | Valid Completion |
| **`S18-027`** | `reject_amenity_booking`| Admin (Society A) | Booking in Society B | Admin A calls `reject_amenity_booking` on Society B booking | **FAIL** | `42501` (Society Isolation) |
| **`S18-028`** | `complete_amenity_booking`| Admin (Society A) | Booking in Society B | Admin A calls `complete_amenity_booking` on Society B booking | **FAIL** | `42501` (Society Isolation) |
| **`S18-029`** | `checkout_visitor` | Gatekeeper (Society A)| Active visitor in Society A | Gatekeeper A calls `checkout_visitor` | **PASS** (`check_out IS NOT NULL`) | Valid Checkout |
| **`S18-030`** | `checkout_visitor` | Gatekeeper (Society A)| Visitor already checked out | Gatekeeper A calls `checkout_visitor` again | **FAIL** | `22000` (Duplicate Checkout) |
| **`S18-031`** | Financial Test A | `authenticated` | Direct SQL Insert attempt | `INSERT INTO ledger_transactions (..., 'amenity_fee')` | **FAIL** | `42501` (RLS Insert Block) |
| **`S18-032`** | Financial Test B1 | `authenticated` | Direct SQL Insert attempt | `INSERT INTO ledger_transactions (..., currency: 'USD')` | **FAIL** | `42501` (RLS Insert Block) |
| **`S18-033`** | Financial Test B2 | `authenticated` | RPC Parameter inspect | Inspect `approve_amenity_booking(p_booking_id UUID)` | **PASS** | Signature has 0 currency params; currency derived server-side |
| **`S18-034`** | Financial Test B3 | Admin (Society A) | Authorized approval | Execute `approve_amenity_booking` | **PASS** | Posted Currency matches Society |
| **`S18-035`** | Financial Test C | Admin (Society A) | Target property in Society B| Call `approve_amenity_booking` on Society B property | **FAIL** | `42501` (Society Isolation) |
| **`S18-036`** | Financial Test D | Admin (Society A) | Approved booking | Inspect ledger transaction posted by function | **PASS** | Fee posted accurately |
| **`S18-037`** | Financial Test E | Admin (Society A) | Approved booking | Verify amount matches `amenity.booking_fee * hours` | **PASS** | Authoritative Calculation |
| **`S18-038`** | Financial Test F | Admin (Society A) | Already approved booking | Call `approve_amenity_booking` a second time | **FAIL** | `22000` (Replay Rejected) |
| **`S18-039`** | Financial Test G | Admin (Society A) | Approved booking cancellation| Call `cancel_amenity_booking` on approved booking | **PASS** | Reversal credit matches original |
| **`S18-040`** | Financial Test H | Attacker (Society A) | Already cancelled booking | Call `cancel_amenity_booking` a second time | **FAIL** | `22000` (Duplicate Reversal Block)|
| **`S18-041`** | Audit Anti-Spoofing | `authenticated` | Direct SQL Insert attempt | `INSERT INTO audit_logs (...)` | **FAIL** | `42501` (RLS Insert Block) |
| **`S18-042`** | Audit Completeness | Admin / Tech / Resident | All 8 Slice 18 Workflows | Execute all 8 RPC workflows | **PASS** | Audit entries verified for all 8 routines |
| **`S18-043`** | Notification Anti-Spoofing| `authenticated` | Direct SQL Insert attempt | `INSERT INTO notifications (...)` | **FAIL** | `42501` (RLS Insert Block) |
| **`S18-044`** | Notification Completeness| Admin / Tech | All 8 Slice 18 Workflows | Verify notifications created for required RPCs & 0 for N/A RPCs | **PASS** | Recipients & zero-N/A notifications verified |

---

## 17. REGRESSION PLAN

* **Pre-Execution Check:** Run `scratch/run_all17.ps1` to confirm 551/551 PASS baseline before applying Slice 18.
* **Post-Execution Check:** Run `scratch/run_all18.ps1` to confirm Slices 1–17 (551 PASS) + Slice 18 (44 PASS) = **595/595 PASS**.

---

## 18. DUAL-PHASE ROLLBACK STRATEGY

### A. Migration Failure Rollback (Transactional Rollback)
`schema_slice18.sql` executes inside a single `BEGIN; ... COMMIT;` transaction block. Any failure during DDL or stored procedure creation causes an immediate, full transactional rollback:
* **Database State:** 0 partial Slice 18 objects survive.
* **Locked Baseline:** Slices 1–17 remain 100% untouched and green (551/551 PASS).

### B. Post-Commit Emergency Rollback
If a defect is discovered after Slice 18 migration commits:
1. **Emergency Incident Containment:** Immediately execute `REVOKE EXECUTE ON FUNCTION ... FROM authenticated, service_role` on affected Slice 18 routines to halt execution safely while preserving system data integrity.
2. **Application Layer:** Revert frontend modifications in `src/App.jsx` and `src/supabase.js` independently.
3. **Recovery & Grant Restoration:** After auditing and applying controlled fixes, restore intended execution grants (`GRANT EXECUTE ... TO authenticated, service_role`).
4. **Data & Constraint Preservation:** SLA timestamp columns and existing `amenity_fee` ledger rows will be preserved. Restoring `check_transaction_type` constraint will occur only after confirming no legitimate `amenity_fee` rows violate the restored constraint.
5. **Locked Baseline Isolation:** Zero modifications will be made to Slices 1–17 code or data.

---

## 19. INDEPENDENT ADVERSARIAL AUDIT PLAN

The post-implementation security review will test 24 hostile attack vectors:
1. Authentication bypass on RPCs
2. Cross-society ID substitution
3. Role escalation
4. Direct table DML bypass
5. RPC parameter tampering
6. Premature `assigned → resolved` jump
7. Unauthorized ticket closure
8. Unauthorized ticket reassignment
9. Cross-society visitor checkout
10. Cross-society amenity rejection/completion
11. SECURITY DEFINER search_path hijacking
12. RLS bypass attempts
13. Stale-state race conditions
14. Replay attacks
15. Duplicate execution
16. Duplicate financial posting
17. Arbitrary fee amount injection
18. Arbitrary currency injection
19. Reversal manipulation
20. Audit log spoofing
21. Notification spoofing
22. Non-existent entity references
23. Null identity handling
24. Concurrent status updates

---

## 20. EXACT FILE CHANGE MATRIX

| File Path | Action | Purpose |
| :--- | :--- | :--- |
| `database/schema_slice18.sql` | **NEW** | DDL for SLA columns, `check_transaction_type` widening, 8 SECURITY DEFINER routines. |
| `database/verify_slice18.sql` | **NEW** | 44 verification assertions (`S18-001` to `S18-044`). |
| `scratch/run_all18.ps1` | **NEW** | Test runner for Slices 1–18 (595 PASS target). |
| `src/supabase.js` | **MODIFY** | Add gatekeeper and technician demo user credentials. |
| `src/App.jsx` | **MODIFY** | Add UI buttons for booking reject/complete and ticket workflow actions. |
| `database/schema_slice1.sql` .. `schema_slice17.sql` | **LOCKED** | **UNTOUCHED** |
| `database/verify_slice1.sql` .. `verify_slice17.sql` | **LOCKED** | **UNTOUCHED** |

---

## 21. FINAL AUTHORIZATION GATE

# **SLICE 18 IMPLEMENTATION AUTHORIZATION: PENDING USER APPROVAL**

**PLAN ONLY — NO IMPLEMENTATION PERFORMED**  
**WAITING FOR EXPLICIT USER APPROVAL**  

---

**SLICE 18 PLAN STATUS: FINAL SECURITY CLOSURE COMPLETE**
