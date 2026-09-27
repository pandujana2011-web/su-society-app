# SU Society App — Phase 3B Implementation Specification
**Version:** 1.0 — 2026-08-31
**Status:** DRAFT — Pending Approval Gate
**Repository:** `D:\Clients Applications\SU Society App`

---

## 1. Executive Summary

Phase 3B builds upon the complete and locked Phase 1–3A implementation to deliver:

1. **Operational maturity** for Phase 3A entities — completing incomplete state machines, adding missing transitions, and enforcing missing authorization gates.
2. **Operational reporting and transparency dashboards** — surfacing society-wide operational KPIs to admins and transparency reports to members.
3. **Notification hardening** — ensuring all critical operational events produce structured, persistent notifications with correct recipient scoping.
4. **Amenity booking lifecycle completion** — adding the `completed` terminal state, booking rejection, and booking payment settlement.
5. **Helpdesk full workflow** — adding `in_progress` state management (not yet wired in UI), SLA timestamps, and a formal ticket-close-by-reporter workflow distinct from admin close.
6. **Pre-auth code lifecycle management** — formal expiry, invalidation, and visitor identity hardening.
7. **Gatekeeper/Technician user provisioning** — adding gatekeeper and technician demo users to the mock data, since they exist in the RBAC model but have no login credentials in `INITIAL_MOCK_DATA`.
8. **Society-level operational audit completeness** — ensuring all Phase 3A operations produce `audit_log` entries consistently.
9. **Test suite expansion** — 53 new assertions (114–166), maintaining full 113/113 regression pass.

> **Scope discipline**: Phase 3B does NOT add new database tables. All changes are additive column extensions, new stored procedures, and UI/mock/test expansions within the existing Phase 3A schema.

---

## 2. Repository Reality

The following was discovered by directly inspecting the actual repository files (no reliance on chat summaries).

### 2.1 File Inventory

| File | Lines | Bytes | Role |
|------|-------|-------|------|
| `database/schema_phase2.sql` | 2,103 | 82,163 | Authoritative DDL, triggers, RLS, stored procedures |
| `src/supabase.js` | 2,647 | 114,018 | Mock database + real Supabase client |
| `src/App.jsx` | 4,466 | 218,275 | Full React UI, all role-specific views |
| `database/test_runner.js` | 2,046 | 95,004 | JS mock test suite — 113/113 assertions |
| `database/test_runner_pg.sql` | — | 64,191 | PostgreSQL integration test runner |

### 2.2 All Tables Confirmed Present

**Phase 1 (pre-existing, not in schema_phase2.sql)**
- `societies`, `users`, `user_roles`, `properties`, `units`
- `property_owners`, `tenancies`, `family_groups`, `occupants`
- `association_memberships`, `relationships`, `audit_logs`

**Phase 2A (schema_phase2.sql lines 27–157)**
- `maintenance_policies`, `custom_billing_subjects`, `custom_billing_responsibilities`
- `maintenance_charges`, `ledger_transactions`, `opening_balances`

**Phase 2B (schema_phase2.sql lines 163–233)**
- `payments`, `payment_allocations`, `receipts`, `notifications`

**Phase 2C (schema_phase2.sql lines 963–1026)**
- `expense_categories`, `expense_vouchers`, `budgets`, `bank_reconciliations`

**Phase 3A (schema_phase2.sql lines 1554–1634)**
- `amenities`, `amenity_bookings`, `helpdesk_tickets`, `ticket_comments`, `visitor_logs`

### 2.3 Confirmed RBAC Roles (actual, from `user_roles` in INITIAL_MOCK_DATA)

| Role | Users in Mock | Notes |
|------|---------------|-------|
| `super_admin` | `admin@society.com` | |
| `admin` | `admin@society.com` | Superset — `is_admin()` checks for `admin` OR `super_admin` |
| `secretary` | `secretary@society.com` | + `member` |
| `treasurer` | `treasurer@society.com` | + `member` |
| `executive_member` | `executive@society.com` | + `member` |
| `member` | `owner1`, `owner2`, `owner3`, `secretary`, `treasurer`, `executive` | |
| `tenant` | `tenant1@society.com`, `tenant2@society.com` | |
| `gatekeeper` | **None in INITIAL_MOCK_DATA** | ⚠️ Role exists in code/tests but no login user |
| `technician` | **None in INITIAL_MOCK_DATA** | ⚠️ Role exists in code/tests but no login user |

### 2.4 Existing Phase 3A Stored Procedures

| Function | SECURITY | search_path | Description |
|----------|----------|-------------|-------------|
| `create_amenity_booking(amenity_uuid, property_uuid, start_t, end_t)` | DEFINER | ✅ set | Create booking + FOR UPDATE lock |
| `approve_amenity_booking(booking_uuid)` | DEFINER | ✅ set | Approve + post `amenity_fee` ledger |
| `cancel_amenity_booking(booking_uuid)` | DEFINER | ✅ set | Cancel + reversal ledger if approved |

### 2.5 Missing Phase 3A Stored Procedures (Gap)

The following operations exist in the **JS mock** but have **no SECURITY DEFINER counterpart** in the SQL schema:

| Operation | JS Mock | SQL Stored Procedure |
|-----------|---------|----------------------|
| `helpdesk_tickets.assign(ticketId, techId)` | ✅ | ❌ Missing |
| `helpdesk_tickets.resolve(ticketId)` | ✅ | ❌ Missing |
| `helpdesk_tickets.close(ticketId)` | ✅ | ❌ Missing |
| `helpdesk_tickets.reopen(ticketId)` | ✅ | ❌ Missing |
| `visitor_logs.checkout(logId)` | ✅ | ❌ Missing |
| `amenity_bookings.reject(booking_uuid)` | ❌ | ❌ Missing |
| `amenity_bookings.complete(booking_uuid)` | ❌ | ❌ Missing |

These stored procedures are Phase 3B deliverables.

### 2.6 Confirmed Transaction Types in Ledger

The `ledger_transactions.transaction_type` CHECK constraint allows:
```
'charge', 'penalty', 'adjustment', 'waiver', 'payment', 'advance_payment',
'refund', 'reversal', 'expense', 'income'
```

> **Critical gap**: `'amenity_fee'` is used in the mock JS (`transaction_type: 'amenity_fee'`) and in the `approve_amenity_booking` SQL function — but `'amenity_fee'` is **NOT** in the CHECK constraint. This is a latent bug. Phase 3B must fix this (see Section 5.1).

### 2.7 Helpdesk State Machine — Current Actual State

```
open → assigned → in_progress → resolved → closed
  ↕ (reopen from closed)
```

Valid state transitions (confirmed from JS mock):
- `open` → `assigned` (admin assigns technician)
- `assigned` → `in_progress` — **no UI trigger yet; state exists**
- `in_progress` → `resolved` (technician resolves)
- `resolved` → `closed` (reporter/admin closes)
- `closed` → `open` (reporter/admin reopens)
- Any → `rejected` — **not yet implemented, no UI trigger**

### 2.8 Amenity Booking State Machine — Current Actual State

```
pending_approval → approved → completed (not yet implemented)
pending_approval → rejected (not yet implemented)
any → cancelled
```

The `completed` and `rejected` states exist in the CHECK constraint but have no stored procedure.

### 2.9 Visitor Log Lifecycle — Current State

- Check-in: `visitor_logs.create()` (gatekeeper or admin)
- Check-out: `visitor_logs.checkout()` (JS mock only, no SQL stored procedure)
- Pre-auth code: 6-digit numeric, partial unique index enforces no duplicate active codes per society

### 2.10 Admin UI — OperationsManagerView Tabs (Current)

| Tab | Content |
|-----|---------|
| Booking Requests | List all bookings, approve/cancel |
| Amenities Manager | Create/list amenities |
| Helpdesk Coordinator | List tickets, assign technician via dropdown |
| Visitor Monitoring | Read-only view of visitor logs |

Missing admin operations: reject booking, mark booking complete, update ticket status to `in_progress`, reject ticket.

### 2.11 JavaScript Test Suite — Current 113 Assertions

- Assertions 1–42: Phase 2B payments, ledger, receipts, allocations
- Assertions 43–68: Phase 2C expenses, budgets, BRS, RLS
- Assertions 69–98: Phase 3A amenities, helpdesk, visitors
- Assertions 99–113: Phase 3A security fix regressions (search_path, RLS, pre-auth, FOR UPDATE)

---

## 3. Locked Architecture

The following are immutable. Phase 3B must not weaken, replace, or bypass them:

1. **Append-only ledger** — `prevent_ledger_mutations` trigger blocks UPDATE/DELETE
2. **Ledger direction invariants** — `validate_ledger_direction_invariants` trigger
3. **Payment state machine** — `validate_payment_state_transitions` trigger
4. **Opening balance immutability** — `prevent_opening_balance_mutations` trigger
5. **Receipt immutability** — `prevent_receipt_mutations` trigger
6. **Expense voucher state machine** — `validate_expense_voucher_mutations` trigger
7. **BRS lock** — `prevent_completed_reconciliation_changes` trigger
8. **RLS on all Phase 2A/2B/2C/3A tables** — all tables have RLS enabled
9. **SECURITY DEFINER + search_path** — all 8 stored procedures use `SET search_path = public, pg_temp`
10. **Booking overlap trigger** — `validate_amenity_booking_overlap` trigger with FOR UPDATE lock in `create_amenity_booking`
11. **Pre-auth digit constraint** — `CHECK (pre_auth_code IS NULL OR pre_auth_code ~ '^[0-9]{6}$')`
12. **Partial unique index** — `uq_visitor_active_pre_auth` on `(society_id, pre_auth_code) WHERE pre_auth_code IS NOT NULL AND check_out IS NULL`

---

## 4. Phase 3B Scope

Phase 3B is **operations lifecycle completion**. It delivers:

| # | Feature | Description |
|---|---------|-------------|
| 3B-1 | Ledger `transaction_type` fix | Add `'amenity_fee'` to CHECK constraint |
| 3B-2 | Helpdesk stored procedures | `assign_ticket`, `start_ticket`, `resolve_ticket`, `close_ticket`, `reopen_ticket` |
| 3B-3 | Visitor checkout stored procedure | `checkout_visitor` — moves checkout to PostgreSQL |
| 3B-4 | Amenity booking completion | `reject_amenity_booking`, `complete_amenity_booking` |
| 3B-5 | Gatekeeper/Technician users | Add demo users `gatekeeper@society.com`, `technician@society.com` to mock |
| 3B-6 | Audit completeness | All Phase 3A operations must produce `audit_logs` entries |
| 3B-7 | Notification completeness | Helpdesk and visitor operations that were missing notifications get them |
| 3B-8 | Admin Operations UI enhancements | Reject booking, complete booking, in-progress ticket, ticket reject |
| 3B-9 | Operational reporting | New "Reports" tab in admin OperationsManagerView |
| 3B-10 | Test suite expansion | 53 new assertions (114–166) |

---

## 5. Out-of-Scope Items

The following are explicitly **NOT** in Phase 3B:

- New database tables (no schema additions beyond column fix)
- Phase 4 features (payments for amenity bookings integration with payment gateway)
- Financial statement generation (out of scope — belongs to a future Reporting phase)
- Email/SMS notification delivery (notifications table stores entries; delivery infrastructure is separate)
- Multi-society features (single society MVP remains unchanged)
- File upload for voucher attachments (attachment_url is a TEXT field)
- Mobile app / PWA
- Any changes to Phase 1–3A locked stored procedures except the `amenity_fee` transaction_type fix

---

## 6. Database Changes

### 6.1 Fix: ledger_transactions CHECK Constraint — `transaction_type`

**File:** `database/schema_phase2.sql`

**Reason:** The `approve_amenity_booking` stored procedure inserts `transaction_type = 'amenity_fee'`, but `'amenity_fee'` is absent from the CHECK constraint `check_transaction_type`. This will cause a constraint violation on any real PostgreSQL database. It is the highest-priority fix in Phase 3B.

**Proposed Change:**

```sql
-- Current constraint (line 125):
CONSTRAINT check_transaction_type CHECK (transaction_type IN (
    'charge', 'penalty', 'adjustment', 'waiver', 'payment', 'advance_payment',
    'refund', 'reversal', 'expense', 'income'
))

-- Phase 3B fix — add 'amenity_fee' and 'booking_fee' for forward-compat:
CONSTRAINT check_transaction_type CHECK (transaction_type IN (
    'charge', 'penalty', 'adjustment', 'waiver', 'payment', 'advance_payment',
    'refund', 'reversal', 'expense', 'income', 'amenity_fee'
))
```

**Migration safety:** `ALTER TABLE ... DROP CONSTRAINT ... CASCADE` then `ADD CONSTRAINT` — safe because it only widens the permitted set. No existing data is invalidated. Must be run in the same transaction as any dependent stored procedure recreations.

**Backward compatibility:** No existing data uses `amenity_fee` yet (Phase 3A is not connected to live PostgreSQL). Safe to apply before any amenity booking data exists.

### 6.2 No New Tables Required

All Phase 3B functionality uses the existing tables:
- `helpdesk_tickets` — existing columns sufficient for `in_progress` state
- `amenity_bookings` — `completed` and `rejected` already exist in the CHECK constraint
- `visitor_logs` — `check_out` column already exists
- `audit_logs` — existing schema sufficient
- `notifications` — existing schema sufficient

### 6.3 Optional: SLA Timestamps on helpdesk_tickets

**Desirable but non-blocking** — these columns improve operational reporting:

| Column | Type | Default | Purpose |
|--------|------|---------|---------|
| `assigned_at` | `TIMESTAMP WITH TIME ZONE` | NULL | When ticket was first assigned |
| `started_at` | `TIMESTAMP WITH TIME ZONE` | NULL | When technician started work |
| `closed_at` | `TIMESTAMP WITH TIME ZONE` | NULL | When ticket was closed (distinct from `resolved_at`) |
| `reopened_at` | `TIMESTAMP WITH TIME ZONE` | NULL | When ticket was last reopened |

> [!NOTE]
> These are purely additive columns with `ADD COLUMN IF NOT EXISTS`. They cannot break existing queries. They are optional for Phase 3B but required if SLA reporting is desired.

**Migration:**
```sql
ALTER TABLE public.helpdesk_tickets
    ADD COLUMN IF NOT EXISTS assigned_at TIMESTAMP WITH TIME ZONE,
    ADD COLUMN IF NOT EXISTS started_at TIMESTAMP WITH TIME ZONE,
    ADD COLUMN IF NOT EXISTS closed_at TIMESTAMP WITH TIME ZONE,
    ADD COLUMN IF NOT EXISTS reopened_at TIMESTAMP WITH TIME ZONE;
```

---

## 7. Stored Procedures Specification

All new stored procedures must use:
- `SECURITY DEFINER`
- `SET search_path = public, pg_temp`
- Explicit authorization check at the start
- `FOR UPDATE` lock before state transition
- `audit_logs` INSERT on success
- `notifications` INSERT on success (where applicable)
- Idempotent state checks (reject if already in terminal state)

---

### 7.1 `assign_ticket(ticket_uuid UUID, technician_uuid UUID)`

**Purpose:** Admin assigns a helpdesk ticket to a technician.

**Parameters:**
- `ticket_uuid UUID` — the ticket to assign
- `technician_uuid UUID` — the technician to assign

**Returns:** `BOOLEAN`

**Authorization:** Caller must be admin/secretary/treasurer (active).

**State machine:**
- Source states: `open`, `assigned` (reassignment allowed)
- Target state: `assigned`
- Blocked if: `in_progress`, `resolved`, `closed`

**Transaction behavior:**
1. `SELECT ... FOR UPDATE` on ticket row
2. Verify caller is admin
3. Verify technician has role `technician` and status `active`
4. UPDATE `assigned_to = technician_uuid`, `status = 'assigned'`, `assigned_at = NOW()` (if column exists)
5. INSERT into `audit_logs`
6. INSERT into `notifications` for technician

**Locking:** `FOR UPDATE` on ticket row prevents concurrent assignments.

**Notification:** To `technician_uuid` — type `helpdesk_assigned`, title `"Ticket Assigned"`, body includes ticket title.

**Error conditions:**
- Ticket not found → exception
- Caller unauthorized → exception
- Technician not found or not active technician → exception
- Ticket in terminal state (`resolved`, `closed`) → exception

---

### 7.2 `start_ticket(ticket_uuid UUID)`

**Purpose:** Technician marks a ticket as `in_progress`.

**Parameters:** `ticket_uuid UUID`

**Returns:** `BOOLEAN`

**Authorization:** Caller must be the assigned technician (`assigned_to = auth.uid()`) OR admin.

**State machine:**
- Source state: `assigned`
- Target state: `in_progress`
- Blocked if: `open`, `in_progress`, `resolved`, `closed`

**Transaction behavior:**
1. `SELECT ... FOR UPDATE` on ticket
2. Verify source state = `assigned`
3. Verify caller is assigned technician or admin
4. UPDATE `status = 'in_progress'`, `started_at = NOW()` (if column exists)
5. INSERT `audit_logs`
6. INSERT `notifications` for ticket creator

**Error conditions:**
- Ticket not in `assigned` state → exception
- Caller is not assigned technician or admin → exception

---

### 7.3 `resolve_ticket(ticket_uuid UUID)`

**Purpose:** Technician marks a ticket as `resolved`.

**Parameters:** `ticket_uuid UUID`

**Returns:** `BOOLEAN`

**Authorization:** Caller must be the assigned technician (`assigned_to = auth.uid()`) OR admin.

**State machine:**
- Source states: `assigned`, `in_progress`
- Target state: `resolved`
- Blocked if: `open`, `resolved`, `closed`

**Transaction behavior:**
1. `SELECT ... FOR UPDATE` on ticket
2. Verify source state in (`assigned`, `in_progress`)
3. Verify caller is assigned technician or admin
4. UPDATE `status = 'resolved'`, `resolved_at = NOW()`
5. INSERT `audit_logs`
6. INSERT `notifications` for ticket creator — type `helpdesk_resolved`

**Error conditions:**
- Ticket not in a resolvable state → exception
- Caller not authorized → exception

---

### 7.4 `close_ticket(ticket_uuid UUID)`

**Purpose:** Ticket reporter or admin closes a resolved ticket.

**Parameters:** `ticket_uuid UUID`

**Returns:** `BOOLEAN`

**Authorization:** Caller must be `created_by` OR admin.

**State machine:**
- Source state: `resolved`
- Target state: `closed`
- Terminal — cannot reopen via this function

**Transaction behavior:**
1. `SELECT ... FOR UPDATE` on ticket
2. Verify source state = `resolved`
3. Verify caller is ticket creator or admin
4. UPDATE `status = 'closed'`, `closed_at = NOW()` (if column exists)
5. INSERT `audit_logs`

**Error conditions:**
- Ticket not in `resolved` state → exception
- Caller not authorized → exception

---

### 7.5 `reopen_ticket(ticket_uuid UUID)`

**Purpose:** Ticket reporter or admin reopens a closed ticket.

**Parameters:** `ticket_uuid UUID`

**Returns:** `BOOLEAN`

**Authorization:** Caller must be `created_by` OR admin.

**State machine:**
- Source state: `closed`
- Target state: `open`
- Also clears `assigned_to`, resets to open for reassignment

**Transaction behavior:**
1. `SELECT ... FOR UPDATE` on ticket
2. Verify source state = `closed`
3. Verify caller is ticket creator or admin
4. UPDATE `status = 'open'`, `assigned_to = NULL`, `reopened_at = NOW()` (if column exists)
5. INSERT `audit_logs`
6. INSERT `notifications` for admin — type `helpdesk_reopened`

**Error conditions:**
- Ticket not in `closed` state → exception
- Caller not authorized → exception

---

### 7.6 `reject_amenity_booking(booking_uuid UUID, reason TEXT)`

**Purpose:** Admin rejects a pending booking.

**Parameters:**
- `booking_uuid UUID`
- `reason TEXT` — rejection reason (stored in audit)

**Returns:** `BOOLEAN`

**Authorization:** Caller must be admin/secretary/treasurer (active).

**State machine:**
- Source state: `pending_approval`
- Target state: `rejected`
- Terminal

**Transaction behavior:**
1. `SELECT ... FOR UPDATE` on booking row
2. Verify state = `pending_approval`
3. Verify caller is admin
4. UPDATE `status = 'rejected'`
5. INSERT `audit_logs` with reason
6. INSERT `notifications` for `booked_by` — type `amenity_status`, title `"Booking Rejected"`

**Financial effect:** None (no ledger entry was created for pending bookings).

**Error conditions:**
- Booking not found → exception
- Booking not in `pending_approval` → exception
- Caller not authorized → exception

---

### 7.7 `complete_amenity_booking(booking_uuid UUID)`

**Purpose:** Admin marks an approved booking as completed after the usage period ends.

**Parameters:** `booking_uuid UUID`

**Returns:** `BOOLEAN`

**Authorization:** Caller must be admin/secretary/treasurer (active).

**State machine:**
- Source state: `approved`
- Target state: `completed`
- Terminal

**Financial effect:** Updates `payment_status` to `paid` only if `total_charges > 0` and the corresponding charge has been settled via `payments` table (checked by reference). Otherwise marks `payment_status = 'unpaid'` and triggers notification to admin about outstanding balance.

> [!IMPORTANT]
> The `complete_amenity_booking` function does NOT directly create ledger entries (the charge was already posted during `approve_amenity_booking`). It only changes status and records audit. Payment settlement is handled through the existing payments architecture.

**Transaction behavior:**
1. `SELECT ... FOR UPDATE` on booking
2. Verify state = `approved`
3. Verify caller is admin
4. UPDATE `status = 'completed'`
5. INSERT `audit_logs`
6. INSERT `notifications` for `booked_by` — type `amenity_status`, title `"Booking Completed"`

**Error conditions:**
- Booking not in `approved` state → exception
- Caller not authorized → exception

---

### 7.8 `checkout_visitor(log_uuid UUID)`

**Purpose:** Gatekeeper or admin records check-out for a visitor.

**Parameters:** `log_uuid UUID`

**Returns:** `BOOLEAN`

**Authorization:** Caller must have role `gatekeeper` OR be admin.

**Validation:**
- Log must exist
- `check_out` must be NULL (not already checked out)
- CHECK constraint `check_out >= check_in` is enforced at DB level

**Transaction behavior:**
1. `SELECT ... FOR UPDATE` on visitor_log row
2. Verify caller is gatekeeper or admin
3. Verify `check_out IS NULL`
4. UPDATE `check_out = NOW()`
5. INSERT `audit_logs`

**Idempotency:** If `check_out IS NOT NULL`, raise exception `'Visitor already checked out.'`

**Error conditions:**
- Log not found → exception
- Already checked out → exception
- Caller not authorized → exception

---

## 8. RLS Security Model

All new stored procedures are `SECURITY DEFINER` and perform authorization checks internally, so no new RLS policies are required for the stored procedures themselves.

### 8.1 Existing RLS Gaps to Acknowledge (Not Fix in Phase 3B)

The following existing RLS policies are **permissive by design** and remain unchanged:

1. `amenity_bookings` — `"Manage own bookings"` policy allows ANY insert/update by `booked_by` or property owner. The stored procedure `create_amenity_booking` enforces the proper authorization. The RLS policy is a backstop. This is acceptable for Phase 3B.

2. `helpdesk_tickets` — `"Manage tickets"` policy allows `created_by` OR `assigned_to`. This means a technician can technically UPDATE any field once assigned. Phase 3B stored procedures enforce specific field updates. The RLS policy remains unchanged.

### 8.2 New Mock RLS-Equivalent Checks Required

The mock must enforce:

| Operation | Who Can | Who Cannot |
|-----------|---------|-----------|
| `assign_ticket` | admin, secretary, treasurer | member, tenant, technician, gatekeeper |
| `start_ticket` | assigned technician, admin | other technicians, members, tenants |
| `resolve_ticket` | assigned technician, admin | other technicians, members, tenants |
| `close_ticket` | ticket creator, admin | technicians, other members |
| `reopen_ticket` | ticket creator, admin | technicians, other members |
| `reject_amenity_booking` | admin, secretary, treasurer | member, tenant, technician, gatekeeper |
| `complete_amenity_booking` | admin, secretary, treasurer | member, tenant, technician, gatekeeper |
| `checkout_visitor` | gatekeeper, admin | member, tenant, technician |

---

## 9. RBAC Matrix

### 9.1 Phase 3A Tables — Full Matrix (including Phase 3B changes)

| Table | Role | SELECT | INSERT | UPDATE | DELETE |
|-------|------|--------|--------|--------|--------|
| `amenities` | admin | all | via proc | via proc | no |
| `amenities` | secretary/treasurer | active only | no | no | no |
| `amenities` | member | active only | no | no | no |
| `amenities` | tenant | active only | no | no | no |
| `amenities` | gatekeeper | active only | no | no | no |
| `amenities` | technician | active only | no | no | no |
| `amenity_bookings` | admin | all | via proc | via proc | no |
| `amenity_bookings` | member (own property) | own | via proc | cancel only | no |
| `amenity_bookings` | tenant (own unit) | own property | via proc | cancel only | no |
| `amenity_bookings` | technician | none | no | no | no |
| `amenity_bookings` | gatekeeper | none | no | no | no |
| `helpdesk_tickets` | admin | all | any | via proc | no |
| `helpdesk_tickets` | member (created_by) | own | own unit | limited (close/reopen) | no |
| `helpdesk_tickets` | tenant (own unit) | own | own unit | limited (close/reopen) | no |
| `helpdesk_tickets` | technician (assigned_to) | assigned | no | via proc (resolve) | no |
| `helpdesk_tickets` | gatekeeper | none | no | no | no |
| `ticket_comments` | admin | all | any | no | no |
| `ticket_comments` | member (ticket visible) | visible | own ticket | no | no |
| `ticket_comments` | tenant (ticket visible) | visible | own ticket | no | no |
| `ticket_comments` | technician (assigned) | assigned | assigned ticket | no | no |
| `visitor_logs` | admin | all | any | via proc | no |
| `visitor_logs` | gatekeeper | all | any | checkout only | no |
| `visitor_logs` | member (own unit) | own | no | no | no |
| `visitor_logs` | tenant (own unit) | own | no | no | no |
| `visitor_logs` | technician | none | no | no | no |

---

## 10. State Machines

### 10.1 Helpdesk Ticket — Complete State Machine

```
                    ┌─────────────────────────────┐
                    │  open (initial)              │
                    └──────────────┬───────────────┘
                                   │ assign_ticket() [admin]
                                   ▼
                    ┌─────────────────────────────┐
                    │  assigned                    │
                    └──────────────┬───────────────┘
                                   │ start_ticket() [assigned tech | admin]
                                   ▼
                    ┌─────────────────────────────┐
                    │  in_progress                 │
                    └──────────────┬───────────────┘
                                   │ resolve_ticket() [assigned tech | admin]
                                   ▼
                    ┌─────────────────────────────┐
                    │  resolved                    │
                    └──────────────┬───────────────┘
                                   │ close_ticket() [created_by | admin]
                                   ▼
                    ┌─────────────────────────────┐
                    │  closed (terminal)           │◄───── reopen_ticket() [created_by | admin]
                    └─────────────────────────────┘
```

**Invalid transitions (must be rejected):**
- `open` → `in_progress` (must go through `assigned` first)
- `open` → `resolved` (not allowed)
- `resolved` → `assigned` (not allowed)
- `closed` → `resolved` (not allowed)
- Any → `open` except from `closed` via `reopen_ticket()`

### 10.2 Amenity Booking — Complete State Machine

```
                    ┌─────────────────────────────┐
                    │  pending_approval (initial)  │
                    └──────────┬──────────┬────────┘
                               │          │
            approve_booking()  │          │ reject_booking()
            [admin/secretary]  │          │ [admin/secretary]
                               ▼          ▼
              ┌──────────┐            ┌──────────┐
              │ approved │            │ rejected │ (terminal)
              └─────┬────┘            └──────────┘
                    │     cancel_booking() [booked_by | admin]
           ─────────┼───────────────►  ┌───────────┐
          │         │                  │ cancelled │ (terminal)
          │         │ complete_booking()└───────────┘
          │         │ [admin/secretary]
          │         ▼
          │   ┌──────────┐
          └──►│ completed│ (terminal)
              └──────────┘
```

**Payment status machine (on `amenity_bookings.payment_status`):**
```
unpaid → paid   [when corresponding payment verified]
paid → refunded [when booking cancelled after payment verified]
```

### 10.3 Visitor Log — Lifecycle

```
[check_in set on create] ──► active (check_out IS NULL)
                          │
                          └─ checkout_visitor() [gatekeeper | admin]
                             ──► checked_out (check_out IS NOT NULL, terminal)
```

---

## 11. Financial Integrity

### 11.1 Amenity Fee Ledger Flow (Phase 3B Clarification)

| Event | Ledger Entry | Direction | Scope | Type |
|-------|-------------|-----------|-------|------|
| `approve_amenity_booking` | Created | debit | member | `amenity_fee` |
| `cancel_amenity_booking` (after approval) | Created | credit | member | `reversal` |
| `complete_amenity_booking` | None | — | — | — (fee already posted) |
| `reject_amenity_booking` | None | — | — | — (no fee was posted for pending) |

### 11.2 Accounting Invariants — Amenity Fee

- The `amenity_fee` debit is posted to the **member sub-ledger** (scope=`member`) against `property_id` and `user_id` (primary owner).
- The society cash sub-ledger is **not** updated at booking approval. It will be updated when the member's payment is verified (existing payment architecture).
- This is consistent with the existing maintenance charge → payment → verify flow.
- No duplicate reversal protection required beyond the existing check already in `cancel_amenity_booking` (`IF EXISTS ledger WHERE reference_id = booking_uuid AND transaction_type = 'reversal'`).

### 11.3 No New Financial Risks

Phase 3B does not:
- Create new ledger scopes
- Create new transaction types beyond `amenity_fee` (which fixes an existing bug)
- Introduce direct ledger mutations
- Bypass the immutable ledger trigger

---

## 12. Concurrency Model

### 12.1 Existing Concurrency Controls (Preserved)

| Operation | Strategy |
|-----------|----------|
| `create_amenity_booking` | `FOR UPDATE` on amenity row + overlap trigger |
| `verify_payment` | `FOR UPDATE` on payment row |
| `approve_expense_voucher` | `FOR UPDATE` on voucher row |

### 12.2 New Concurrency Requirements

| Operation | Required Strategy |
|-----------|------------------|
| `assign_ticket` | `FOR UPDATE` on ticket row (prevents double-assignment) |
| `start_ticket` | `FOR UPDATE` on ticket row |
| `resolve_ticket` | `FOR UPDATE` on ticket row |
| `close_ticket` | `FOR UPDATE` on ticket row |
| `reopen_ticket` | `FOR UPDATE` on ticket row |
| `reject_amenity_booking` | `FOR UPDATE` on booking row |
| `complete_amenity_booking` | `FOR UPDATE` on booking row |
| `checkout_visitor` | `FOR UPDATE` on visitor_log row |

**Rationale:** All state transitions are vulnerable to race conditions. If two admin users simultaneously try to assign a ticket to different technicians, the first `FOR UPDATE` lock will force the second to wait and re-read the updated state, then fail with the state check.

### 12.3 No Advisory Locks Required

Phase 3B operations are row-level. No need for advisory locks.

---

## 13. Audit & Notifications

### 13.1 Required Audit Log Entries

| Operation | `action` string | `table_name` | `record_id` |
|-----------|----------------|--------------|-------------|
| `assign_ticket` | `'ASSIGNED helpdesk ticket'` | `helpdesk_tickets` | ticket_uuid |
| `start_ticket` | `'STARTED helpdesk ticket'` | `helpdesk_tickets` | ticket_uuid |
| `resolve_ticket` | `'RESOLVED helpdesk ticket'` | `helpdesk_tickets` | ticket_uuid |
| `close_ticket` | `'CLOSED helpdesk ticket'` | `helpdesk_tickets` | ticket_uuid |
| `reopen_ticket` | `'REOPENED helpdesk ticket'` | `helpdesk_tickets` | ticket_uuid |
| `reject_amenity_booking` | `'REJECTED amenity booking'` | `amenity_bookings` | booking_uuid |
| `complete_amenity_booking` | `'COMPLETED amenity booking'` | `amenity_bookings` | booking_uuid |
| `checkout_visitor` | `'CHECKED OUT visitor'` | `visitor_logs` | log_uuid |

### 13.2 Required Notifications

| Event | Recipient | Type | Title |
|-------|-----------|------|-------|
| Ticket assigned | Assigned technician | `helpdesk_assigned` | `"Ticket Assigned: {title}"` |
| Ticket started | Ticket creator | `helpdesk_update` | `"Work Started on Your Ticket"` |
| Ticket resolved | Ticket creator | `helpdesk_resolved` | `"Your Ticket Has Been Resolved"` |
| Ticket reopened | Admin (society) | `helpdesk_reopened` | `"Ticket Reopened: {title}"` |
| Booking rejected | Booked-by user | `amenity_status` | `"Booking Rejected"` |
| Booking completed | Booked-by user | `amenity_status` | `"Booking Marked Complete"` |

---

## 14. Frontend Changes

### 14.1 INITIAL_MOCK_DATA — Gatekeeper & Technician Users

**Problem:** `gatekeeper@society.com` and `technician@society.com` exist as test users in `test_runner.js` and in the UI code (`isGatekeeper`, `isTechnician` checks in App.jsx) but have **no login credentials** in `INITIAL_MOCK_DATA` in `supabase.js`. The login demo buttons in `LoginCard` do not include them.

**Phase 3B Fix:**

Add to `INITIAL_MOCK_DATA.users` in `src/supabase.js`:
```js
{ id: 'd1111111-1111-1111-1111-111111111111', email: 'gatekeeper@society.com', name: 'Ramaiah (Gatekeeper)', mobile: '+919876543213', status: 'active', password: 'password123' },
{ id: 'd2222222-2222-2222-2222-222222222222', email: 'technician@society.com', name: 'Suresh (Technician)', mobile: '+919876543214', status: 'active', password: 'password123' }
```

Add to `INITIAL_MOCK_DATA.user_roles`:
```js
{ user_id: 'd1111111-1111-1111-1111-111111111111', role: 'gatekeeper' },
{ user_id: 'd2222222-2222-2222-2222-222222222222', role: 'technician' }
```

Add to `LoginCard` quick-access buttons:
```jsx
<button className="btn btn-secondary btn-small" onClick={() => handleTestLogin('gatekeeper@society.com')}>Gatekeeper</button>
<button className="btn btn-secondary btn-small" onClick={() => handleTestLogin('technician@society.com')}>Technician</button>
```

### 14.2 OperationsManagerView — Admin Enhancements

**New Booking Requests tab actions:**
- "Reject" button for `pending_approval` bookings (calls `reject_amenity_booking`)
- "Mark Complete" button for `approved` bookings (calls `complete_amenity_booking`)

**Helpdesk Coordinator tab enhancements:**
- Technician assignment dropdown remains
- Add "In Progress" status badge
- Add actions: [Assign] [Start] based on state
- Show `assigned_at`, `started_at` timestamps if present

**Visitor Monitoring tab (admin read-only):**
- No changes required

### 14.3 GatekeeperDashboardView — Checkout Flow

Currently calls `db.visitor_logs.checkout(logId, user)` which already exists in the JS mock. No UI change required. The stored procedure `checkout_visitor` is a back-end addition only.

### 14.4 TechnicianDashboardView — In-Progress Action

Add "Mark In Progress" button for `assigned` tickets (calls `helpdesk_tickets.start(ticketId, user)` in mock).

Currently technician can only:
- View assigned tickets
- Add comments
- Mark resolved

Phase 3B adds:
- Mark in-progress (for `assigned` tickets)

### 14.5 ResidentOperationsWidget — Ticket Lifecycle

Member/tenant can already:
- File tickets, add comments, close resolved tickets, reopen closed tickets

No UI changes required for resident portal. The existing `db.helpdesk_tickets.close()` and `db.helpdesk_tickets.reopen()` already exist in the JS mock.

### 14.6 Admin Operations Reporting Tab

Add a new "Reports" tab to `OperationsManagerView` with:

| Widget | Description |
|--------|-------------|
| Open Ticket Count | Count of `open` + `assigned` + `in_progress` tickets |
| Average Resolution Time | `resolved_at - created_at` average for resolved tickets (last 30 days) |
| Active Amenity Bookings | Count of `approved` bookings |
| Visitors In Compound | Count of `visitor_logs WHERE check_out IS NULL` |
| Amenity Utilization | Bookings by amenity (last 30 days) |

---

## 15. Mock/Offline Parity

`src/supabase.js` must add mock implementations for all new stored procedures. Each mock function must:

1. Perform role-based authorization checks identical to the PostgreSQL stored procedure
2. Enforce state machine transitions identically
3. Create `audit_logs` entries identically
4. Create `notifications` entries identically
5. Never silently permit an operation the PostgreSQL function would reject

### 15.1 New Mock Functions Required

| Mock path | Purpose |
|-----------|---------|
| `db.helpdesk_tickets.start(ticketId, user)` | Mark in_progress |
| `db.helpdesk_tickets.reject(ticketId, user)` | Reject ticket (admin only, if needed) |
| `db.amenity_bookings.reject(bookingId, reason, user)` | Reject booking |
| `db.amenity_bookings.complete(bookingId, user)` | Complete booking |
| `db.visitor_logs.checkout(logId, user)` | Already exists — verify parity with SQL spec |

### 15.2 Parity Rules

| Rule | PostgreSQL | Mock Must Mirror |
|------|-----------|-----------------|
| `assign_ticket` only by admin | `is_admin(caller)` check | `!is_admin(currentUser)` → throw |
| `start_ticket` only by assigned tech | `assigned_to = caller` check | `ticket.assigned_to !== currentUser.id && !is_admin` → throw |
| `reject_booking` source state check | `status = 'pending_approval'` | `booking.status !== 'pending_approval'` → throw |
| `checkout_visitor` gatekeeper only | role check + `FOR UPDATE` | gatekeeper or admin check |
| All ops write audit_logs | INSERT audit_logs | push to `mockData.audit_logs` |

---

## 16. Test Plan

Phase 3B begins at assertion **114**. All 113 existing assertions must continue to pass unchanged.

### 16.1 Assertion Numbering Scheme

```
114–120: Fix — amenity_fee transaction type
121–126: assign_ticket authorization
127–131: assign_ticket state machine
132–136: start_ticket authorization
137–140: start_ticket state machine
141–145: resolve_ticket authorization
146–149: resolve_ticket state machine
150–153: close_ticket authorization
154–157: close_ticket state machine
158–161: reopen_ticket authorization
162–164: reject_amenity_booking
165–166: complete_amenity_booking (+ checkout_visitor)
```

Total new assertions: **53** (114–166)

### 16.2 Detailed Test Specifications

#### Fix Tests (114–120): `amenity_fee` Transaction Type

| # | Test | Expected |
|---|------|----------|
| 114 | Create amenity booking, approve it → ledger entry type | `transaction_type === 'amenity_fee'` |
| 115 | Ledger direction for `amenity_fee` | `direction === 'debit'`, `scope === 'member'` |
| 116 | Cancel approved amenity booking → reversal type | `transaction_type === 'reversal'` |
| 117 | Ledger direction for reversal | `direction === 'credit'`, `scope === 'member'` |
| 118 | Reject pending booking → no ledger entry created | `ledger_transactions.length === 0` for booking |
| 119 | Complete approved booking → no additional ledger entry | Ledger count unchanged |
| 120 | Schema contains `amenity_fee` in CHECK constraint | Verify SQL text |

#### Authorization Tests (121–126): `assign_ticket`

| # | Test | Expected |
|---|------|----------|
| 121 | Admin assigns ticket to technician | Succeeds, `status === 'assigned'` |
| 122 | Secretary assigns ticket | Succeeds |
| 123 | Member tries to assign ticket | Throws 'Unauthorized' |
| 124 | Technician tries to assign ticket to self | Throws 'Unauthorized' |
| 125 | Tenant tries to assign ticket | Throws 'Unauthorized' |
| 126 | Admin assigns to non-technician user | Throws error about technician role |

#### State Machine Tests (127–131): `assign_ticket`

| # | Test | Expected |
|---|------|----------|
| 127 | Assign `open` ticket → transitions to `assigned` | `status === 'assigned'` |
| 128 | Reassign `assigned` ticket | Succeeds, `assigned_to` updated |
| 129 | Assign `in_progress` ticket | Throws state exception |
| 130 | Assign `resolved` ticket | Throws state exception |
| 131 | Assign `closed` ticket | Throws state exception |

#### Authorization Tests (132–136): `start_ticket`

| # | Test | Expected |
|---|------|----------|
| 132 | Assigned technician starts ticket | Succeeds, `status === 'in_progress'` |
| 133 | Admin starts `assigned` ticket | Succeeds |
| 134 | Unassigned technician tries to start | Throws 'Unauthorized' |
| 135 | Ticket creator tries to start | Throws 'Unauthorized' |
| 136 | Ticket in `open` state, tech tries to start | Throws state exception |

#### State Machine Tests (137–140): `start_ticket`

| # | Test | Expected |
|---|------|----------|
| 137 | `assigned` → `in_progress` | Valid |
| 138 | `open` → `in_progress` | Invalid — throws |
| 139 | `in_progress` → `in_progress` | Invalid — throws (already in progress) |
| 140 | `resolved` → `in_progress` | Invalid — throws |

#### Authorization Tests (141–145): `resolve_ticket`

| # | Test | Expected |
|---|------|----------|
| 141 | Assigned technician resolves `in_progress` ticket | Succeeds |
| 142 | Assigned technician resolves `assigned` ticket (no start step) | Succeeds |
| 143 | Admin resolves ticket | Succeeds |
| 144 | Unassigned technician resolves | Throws 'Unauthorized' |
| 145 | Reporter resolves own ticket | Throws 'Unauthorized' |

#### State Machine Tests (146–149): `resolve_ticket`

| # | Test | Expected |
|---|------|----------|
| 146 | `in_progress` → `resolved` | Valid |
| 147 | `assigned` → `resolved` | Valid |
| 148 | `open` → `resolved` | Invalid — throws |
| 149 | `resolved` → `resolved` | Invalid — throws |

#### Close Ticket Tests (150–153): authorization

| # | Test | Expected |
|---|------|----------|
| 150 | Reporter closes own `resolved` ticket | Succeeds |
| 151 | Admin closes `resolved` ticket | Succeeds |
| 152 | Technician tries to close | Throws 'Unauthorized' |
| 153 | Close `in_progress` ticket | Throws state exception |

#### Close Ticket State Tests (154–157)

| # | Test | Expected |
|---|------|----------|
| 154 | `resolved` → `closed` | Valid |
| 155 | `open` → `closed` | Invalid |
| 156 | `closed` → `closed` | Invalid |
| 157 | `assigned` → `closed` | Invalid |

#### Reopen Ticket Tests (158–161)

| # | Test | Expected |
|---|------|----------|
| 158 | Reporter reopens own `closed` ticket | Succeeds, `status === 'open'`, `assigned_to === null` |
| 159 | Admin reopens `closed` ticket | Succeeds |
| 160 | Technician tries to reopen | Throws 'Unauthorized' |
| 161 | Reopen `resolved` ticket (not closed) | Throws state exception |

#### Reject/Complete Booking Tests (162–166)

| # | Test | Expected |
|---|------|----------|
| 162 | Admin rejects pending booking → `status === 'rejected'`, no ledger | Succeeds |
| 163 | Member tries to reject booking | Throws 'Unauthorized' |
| 164 | Reject already-approved booking | Throws state exception |
| 165 | Admin completes approved booking → `status === 'completed'` | Succeeds |
| 166 | Checkout visitor → `check_out !== null`, second checkout fails | Succeeds then throws |

### 16.3 Regression Requirements

All 113 existing assertions must pass unchanged after Phase 3B implementation. The test runner MUST verify this by running the full suite sequentially.

---

## 17. Migration Plan

### 17.1 Schema Migration Order

1. **Apply `amenity_fee` fix first** — this must be done before any amenity booking can be approved on a live database:
   ```sql
   BEGIN;
   ALTER TABLE public.ledger_transactions
       DROP CONSTRAINT IF EXISTS check_transaction_type;
   ALTER TABLE public.ledger_transactions
       ADD CONSTRAINT check_transaction_type CHECK (transaction_type IN (
           'charge', 'penalty', 'adjustment', 'waiver', 'payment',
           'advance_payment', 'refund', 'reversal', 'expense', 'income', 'amenity_fee'
       ));
   COMMIT;
   ```

2. **Apply optional SLA columns** (if decided to include):
   ```sql
   ALTER TABLE public.helpdesk_tickets
       ADD COLUMN IF NOT EXISTS assigned_at TIMESTAMP WITH TIME ZONE,
       ADD COLUMN IF NOT EXISTS started_at TIMESTAMP WITH TIME ZONE,
       ADD COLUMN IF NOT EXISTS closed_at TIMESTAMP WITH TIME ZONE,
       ADD COLUMN IF NOT EXISTS reopened_at TIMESTAMP WITH TIME ZONE;
   ```

3. **Create stored procedures** (in dependency order):
   - `checkout_visitor` (no dependencies)
   - `assign_ticket` (depends on technician role)
   - `start_ticket` (depends on assign_ticket having been run first in practice)
   - `resolve_ticket`
   - `close_ticket`
   - `reopen_ticket`
   - `reject_amenity_booking`
   - `complete_amenity_booking`

4. **Update `src/supabase.js`** — mock implementations
5. **Update `src/App.jsx`** — UI changes
6. **Update `database/test_runner.js`** — 53 new assertions
7. **Update `database/test_runner_pg.sql`** — PostgreSQL test equivalents

### 17.2 Backward Compatibility

- The constraint widening (adding `amenity_fee`) is backward compatible.
- SLA column additions are backward compatible (nullable, no default constraint).
- New stored procedures do not replace existing ones.
- No existing RLS policies are replaced.
- No existing triggers are replaced.
- No UI components are removed.

### 17.3 Rollback Strategy

- **Stored procedures:** `DROP FUNCTION IF EXISTS public.function_name(args)` — safe, no data loss.
- **Constraint widening:** Cannot easily roll back if `amenity_fee` entries exist. Rollback: remove entries first, then restore constraint. This is why this fix must be applied before any live booking approval.
- **SLA columns:** `ALTER TABLE ... DROP COLUMN IF EXISTS` — data loss for any populated timestamps.
- **UI/Mock changes:** Git revert to prior commit.

---

## 18. Risks

| Risk | Severity | Mitigation |
|------|----------|-----------|
| `amenity_fee` bug causes live PG failure | **Critical** | Apply constraint fix before any booking approval on live DB |
| `assign_ticket` race condition (two admins assign simultaneously) | Medium | `FOR UPDATE` lock resolves |
| Technician can update any ticket field via RLS (not just status) | Low | Stored procedures enforce specific field updates; RLS is permissive but accepts the risk |
| Gatekeeper `checkout_visitor` race (two gatekeepers check out same visitor) | Low | `FOR UPDATE` + `check_out IS NULL` check resolves |
| SLA column addition breaks existing ORM queries | None | Columns are nullable with no defaults; SELECT * queries silently gain new fields |
| Pre-auth code reuse after checkout (known, desired behavior) | Low | Documented and tested (assertion 110 confirms it works) |

---

## 19. Stop Conditions

Phase 3B implementation MUST NOT begin if any of the following are discovered:

1. ❌ The `amenity_fee` constraint fix causes data loss or integrity issues in existing ledger data.
2. ❌ A new stored procedure cannot enforce society isolation because the `helpdesk_tickets.society_id` is needed for notifications but the ticket row only contains `unit_id` (requires a JOIN — verified this is safe).
3. ❌ The `reopen_ticket` function clears `assigned_to`, which could leave an already-active technician without awareness — mitigated by notification to admin.
4. ❌ Any Phase 3B procedure creates a ledger entry that bypasses `validate_ledger_direction_invariants`.

**None of the above stop conditions apply** based on the actual repository inspection. Phase 3B is **READY FOR IMPLEMENTATION** subject to the approval gate below.

---

## 20. Phase 3B Implementation Checklist

### Database Changes
- [ ] Apply `amenity_fee` to `check_transaction_type` constraint in `schema_phase2.sql`
- [ ] Add optional SLA columns to `helpdesk_tickets` (decision required)
- [ ] Create `assign_ticket` stored procedure
- [ ] Create `start_ticket` stored procedure
- [ ] Create `resolve_ticket` stored procedure
- [ ] Create `close_ticket` stored procedure
- [ ] Create `reopen_ticket` stored procedure
- [ ] Create `reject_amenity_booking` stored procedure
- [ ] Create `complete_amenity_booking` stored procedure
- [ ] Create `checkout_visitor` stored procedure

### Mock (`src/supabase.js`)
- [ ] Add gatekeeper user to `INITIAL_MOCK_DATA.users`
- [ ] Add technician user to `INITIAL_MOCK_DATA.users`
- [ ] Add gatekeeper role to `INITIAL_MOCK_DATA.user_roles`
- [ ] Add technician role to `INITIAL_MOCK_DATA.user_roles`
- [ ] Add `db.helpdesk_tickets.start()` mock function
- [ ] Add `db.amenity_bookings.reject()` mock function
- [ ] Add `db.amenity_bookings.complete()` mock function
- [ ] Verify `db.visitor_logs.checkout()` parity with SQL spec

### Frontend (`src/App.jsx`)
- [ ] Add Gatekeeper quick-login button to `LoginCard`
- [ ] Add Technician quick-login button to `LoginCard`
- [ ] Add "Reject" action to admin Booking Requests tab
- [ ] Add "Mark Complete" action to admin Booking Requests tab
- [ ] Add "Mark In Progress" action to `TechnicianDashboardView`
- [ ] Add "Reports" tab to `OperationsManagerView`

### Tests (`database/test_runner.js`)
- [ ] Add 53 new assertions (114–166) per specification above
- [ ] Verify all 113 existing assertions still pass
- [ ] Run full 166/166 suite and confirm PASS

### PostgreSQL Test Runner (`database/test_runner_pg.sql`)
- [ ] Add equivalent PostgreSQL assertions for all 53 new tests
- [ ] Maintain existing PostgreSQL test count

---

## 21. Open Questions for Approval

Before implementation begins, the following decisions are required:

> [!IMPORTANT]
> **Decision 1 — SLA Columns:** Should Phase 3B add `assigned_at`, `started_at`, `closed_at`, `reopened_at` to `helpdesk_tickets`? These are purely additive and cannot break anything, but they increase schema scope. Recommended: **YES** — they are required for the Reports tab.

> [!IMPORTANT]
> **Decision 2 — Ticket Rejection:** Should there be a formal `reject_ticket` stored procedure for tickets that are `open` or `assigned` and cannot be serviced? This was not in the original architecture but is a common helpdesk pattern. Recommended: **Out of scope for Phase 3B** — leave for Phase 4.

> [!IMPORTANT]
> **Decision 3 — `in_progress` from `assigned` only:** Should the state machine require `assigned` → `in_progress` → `resolved`, or should `assigned` → `resolved` be allowed (skip `in_progress`)? The current JS mock allows `assigned` → `resolved` directly (technician calls `resolve` without calling `start`). Recommended: **Keep both paths valid** — `in_progress` is optional.

---

## 22. Phase 3B Approval Gate

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                      PHASE 3B APPROVAL GATE                                 ║
║                                                                              ║
║  This specification has been produced from direct inspection of the actual   ║
║  repository at D:\Clients Applications\SU Society App.                      ║
║                                                                              ║
║  Phase 3B implementation MUST NOT begin until:                               ║
║                                                                              ║
║  [ ] This specification has been reviewed and approved by the project owner  ║
║  [ ] Decision 1 (SLA columns) is resolved                                   ║
║  [ ] Decision 2 (ticket rejection) is resolved                               ║
║  [ ] Decision 3 (in_progress required vs. optional) is resolved             ║
║                                                                              ║
║  Current State:                                                              ║
║    Phase 3A:   COMPLETE AND LOCKED (113/113 JS tests pass)                  ║
║    Phase 3B:   SPECIFICATION COMPLETE — AWAITING APPROVAL                   ║
║    PostgreSQL: NOT VERIFIED (no live connection available)                   ║
║                                                                              ║
║  APPROVED: ____________    DATE: ____________                                 ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

---

*Document generated by repository inspection on 2026-08-31.*
*No application code was modified in the production of this specification.*
