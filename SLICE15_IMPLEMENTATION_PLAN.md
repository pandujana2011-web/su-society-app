# SLICE 15 — REVISED IMPLEMENTATION PLAN & PRIVILEGE-BOUNDARY SECURITY SPECIFICATION

**Target Module:** Operations Lifecycle Completion, Catalog-Audited RLS Security Architecture & Gatekeeper/Technician Execution Engine  
**Authoritative Scope:** Phase 3B Core Operational Stored Procedures, Amenity Booking Terminal Lifecycle (`complete`, `reject`), Visitor Checkout Engine, Helpdesk Full Workflow (`assign`, `start`, `resolve`, `close`, `reopen`), Catalog-Audited RESTRICTIVE RLS `FOR UPDATE` + ID-Bound Transaction-Local GUC Defense-in-Depth Triggers, and Ledger `amenity_fee` Constraint Replacement  
**Target Schema File:** `database/schema_slice15.sql`  
**Target Verification File:** `database/verify_slice15.sql`  
**Target Runner:** `scratch/run_all15.ps1`  
**Status:** `AUTHORIZATION-CONTEXT SECURITY REVISION COMPLETE — PENDING USER APPROVAL`  

---

## 1. Executive Summary

Slice 15 delivers the **Operational Lifecycle & Workflow Engine** for Phase 3A entities (`amenity_bookings`, `helpdesk_tickets`, `visitor_logs`).

Following an adversarial privilege-boundary security review, this plan explicitly classifies the PostgreSQL security domains, refines all GUC defense-in-depth claims, documents `FORCE ROW LEVEL SECURITY` semantics, and establishes a 62-assertion verification suite:

1. **Privilege-Boundary Classification:**
   - **Application Security Boundary:** Comprises `authenticated` client roles, application users, and `service_role`. All direct `UPDATE` access to `helpdesk_tickets` and `amenity_bookings` is strictly denied for the Application Security Boundary by RESTRICTIVE RLS policies (`AS RESTRICTIVE FOR UPDATE TO authenticated USING (false)`). Direct `UPDATE` is rejected for verified client roles because the final RLS policy and privilege catalog state provide no permitted `UPDATE` path.
   - **Trusted Database Authority:** Comprises the PostgreSQL superuser, table owner `postgres`, and roles with explicit `BYPASSRLS` privileges. These roles constitute trusted database infrastructure authority rather than application-level adversaries. Superusers and `BYPASSRLS` roles execute outside application client RLS restrictions by design.
2. **Defense-in-Depth GUC Security Claim:**
   - The transaction-local GUC (`app.ticket_workflow_context`, `app.booking_workflow_context`) is defense-in-depth and ID-bound, but is **not treated as an unforgeable credential**. Client GUC spoofing cannot grant `UPDATE` capability because the client role has no permitted `UPDATE` path at the RLS policy boundary.
3. **Helpdesk Workflow Engine:** 5 `SECURITY DEFINER` stored procedures (`assign_ticket`, `start_ticket`, `resolve_ticket`, `close_ticket`, `reopen_ticket`) with explicit role check, society isolation, identity matching, `FOR UPDATE` concurrency locking, audit logging, and recipient-scoped notification dispatch.
4. **Amenity Booking Terminal Lifecycle Engine:** 2 `SECURITY DEFINER` stored procedures (`reject_amenity_booking`, `complete_amenity_booking`) with administrative authorization, society boundary isolation, `FOR UPDATE` locking, audit logging, and notification dispatch.
5. **Visitor Checkout Engine:** 1 `SECURITY DEFINER` stored procedure (`checkout_visitor`) for gatekeepers and admins with atomic `check_out` timestamp recording, freeing pre-auth code slots for reuse.
6. **Non-Destructive Ledger Constraint Replacement:** Widening `check_transaction_type` on `public.ledger_transactions` to include `'amenity_fee'`, resolving a latent PostgreSQL runtime DB error during amenity booking approval settlement. Existing rows are pre-validated.
7. **62-Assertion Verification Suite:** Expanded to **62 genuine automated SQL assertions** in `database/verify_slice15.sql`, including catalog audits for `pg_policies`, `information_schema.table_privileges`, `relforcerowsecurity`, elevated target-ID GUC direct UPDATE tests, cross-society IDOR tests, concurrency serialization tests, and function EXECUTE privilege audits. Cumulative target result: **434/434 PASS** (372 locked baseline + 62 Slice 15).

---

## 2. Current Locked Baseline

The project baseline remains strictly locked and verified:

* **Slices 1–13 Baseline:** **341/341 PASS**
* **Slice 14 Baseline:** **31/31 PASS**
* **Cumulative Locked Baseline:** **372/372 PASS**
* **Locked Pipeline Runners:** `scratch/run_all13.ps1` & `scratch/run_all14.ps1` (IMMUTABLE)

### Immutable Constraints
* NO modification to `database/schema_slice1.sql` through `database/schema_slice14.sql`.
* NO modification to `database/verify_slice1.sql` through `database/verify_slice14.sql`.
* NO modification to `scratch/run_all13.ps1` or `scratch/run_all14.ps1`.
* NO weakening of existing `SECURITY DEFINER` search paths (`SET search_path = public, pg_temp`), RLS policies, audit triggers, or payment/ledger immutability.

---

## 3. Security Boundary & Role Classification Architecture

```text
CLIENT / APPLICATION ROLE (authenticated)
               │
               ▼  [Direct UPDATE Statement]
     RLS SECURITY BOUNDARY
  (AS RESTRICTIVE FOR UPDATE TO authenticated USING (false))
               │
               ▼  [Access Denied — 0 Rows Updated]
┌────────────────────────────────────────────────────────┐
│  ONLY AUTHORIZED ENTRY PATH: SECURITY DEFINER ROUTINES  │
└────────────────────────────────────────────────────────┘
               │
               ▼  [RPC Call: assign_ticket / reject_amenity_booking / etc.]
    SECURITY DEFINER PROCEDURE (Owned by postgres)
  1. Verifies auth.uid() identity & is_admin() / role guards
  2. Verifies society_id boundary & target row preconditions
  3. Sets transaction-local defense-in-depth GUC (p_target_id::text)
  4. Executes atomic UPDATE as table owner postgres
```

### 3.1 Role Domain Distinction
- **Application Security Boundary (`authenticated`, application users, `service_role`):** The untrusted application attack surface. Application roles are strictly constrained by RLS policy `pol_helpdesk_tickets_no_update` and `pol_amenity_bookings_no_update` (`AS RESTRICTIVE FOR UPDATE TO authenticated USING (false)`). Direct client `UPDATE` queries execute against this boundary and are denied by PostgreSQL's security engine regardless of what GUC values or session parameters the caller attempts to set.
- **Trusted Database Authority (PostgreSQL Superuser, `BYPASSRLS` Roles, Table Owner `postgres`):** Trusted database infrastructure authority. Table owner `postgres` executes `SECURITY DEFINER` routines on behalf of validated callers. Superusers and `BYPASSRLS` roles represent system database administration infrastructure; they execute outside client RLS restrictions by PostgreSQL architecture design.

### 3.2 GUC Defense-in-Depth Security Claim
The transaction-local GUC (`app.ticket_workflow_context`, `app.booking_workflow_context`) is defense-in-depth and ID-bound, but is **not treated as an unforgeable credential**. Client GUC spoofing cannot grant `UPDATE` capability because the client role has no permitted `UPDATE` path at the RLS policy boundary.

---

## 4. Catalog Audit & FORCE RLS Semantics

### 4.1 Policy Combination Semantics (`pg_policies`)
In PostgreSQL:
- **Permissive Policies (`PERMISSIVE`):** Combined using boolean `OR`. If a pre-existing policy allows UPDATE, adding a second PERMISSIVE policy `USING (false)` results in `(Pre-existing USING (...) OR false) = USING (...)`, failing to block client updates.
- **Restrictive Policies (`RESTRICTIVE`):** Combined using boolean `AND`. A RESTRICTIVE policy `AS RESTRICTIVE FOR UPDATE TO authenticated USING (false)` results in `(Pre-existing USING (...) AND false) = false`, guaranteeing that direct `UPDATE` statements evaluate to `false` for role `authenticated`.

Slice 15 enforces `AS RESTRICTIVE FOR UPDATE TO authenticated USING (false)` on both `helpdesk_tickets` and `amenity_bookings`.

### 4.2 FORCE ROW LEVEL SECURITY (`relforcerowsecurity`)
- Tables `helpdesk_tickets` and `amenity_bookings` have `ENABLE ROW LEVEL SECURITY; FORCE ROW LEVEL SECURITY;`.
- `FORCE ROW LEVEL SECURITY` mandates that RLS policies apply to non-owner queries.
- Because Slice 15 policies explicitly target `TO authenticated`, table owner `postgres` (under which `SECURITY DEFINER` workflow functions execute) is NOT in role `authenticated`. Thus, `postgres` executes procedure `UPDATE` statements cleanly while client queries from `authenticated` are rejected. Superusers and `BYPASSRLS` roles remain trusted database authorities.

---

## 5. Database Privilege Audit Matrix

| Role Domain | Role Name | Table UPDATE Privilege | RLS Policy Status (`TO authenticated`) | Workflow Procedure EXECUTE | Direct UPDATE Result |
|---|---|---|---|---|---|
| Application Boundary | `authenticated` | Granted via GRANT | `AS RESTRICTIVE USING (false)` | Granted to 8 specific routines | **Rejected by RLS** ("Direct UPDATE is rejected for verified client roles because RLS policy provides no permitted path") |
| Application Boundary | `anon` | Denied | `AS RESTRICTIVE USING (false)` | Denied | **Rejected** |
| Trusted Infrastructure | `postgres` (Table Owner) | Table Owner / Superuser | Bypasses `TO authenticated` RLS | Function Owner | Permitted via workflow procedures |
| Trusted Infrastructure | `BYPASSRLS` Roles | Granted | Bypasses RLS | Infrastructure Admin | Classified as Trusted Infrastructure Authority |

---

## 6. Authoritative Scope

Slice 15 delivers the following core functional components:

1. **Non-Destructive Ledger Constraint Replacement:** Update `check_transaction_type` on `public.ledger_transactions` to include `'amenity_fee'`.
2. **RESTRICTIVE RLS Policies & ID-Bound Trigger Architecture:**
   - `CREATE POLICY pol_helpdesk_tickets_no_update ON public.helpdesk_tickets AS RESTRICTIVE FOR UPDATE TO authenticated USING (false);`
   - `CREATE POLICY pol_amenity_bookings_no_update ON public.amenity_bookings AS RESTRICTIVE FOR UPDATE TO authenticated USING (false);`
   - `trg_prevent_direct_ticket_status_update` on `helpdesk_tickets`
   - `trg_prevent_direct_booking_status_update` on `amenity_bookings`
3. **Amenity Booking Terminal Lifecycle Engine:**
   - `public.reject_amenity_booking(p_booking_id UUID, p_reason TEXT) -> BOOLEAN`
   - `public.complete_amenity_booking(p_booking_id UUID) -> BOOLEAN`
4. **Visitor Checkout Engine:**
   - `public.checkout_visitor(p_log_id UUID) -> BOOLEAN`
5. **Helpdesk Ticket Workflow Engine:**
   - `public.assign_ticket(p_ticket_id UUID, p_technician_id UUID) -> BOOLEAN`
   - `public.start_ticket(p_ticket_id UUID) -> BOOLEAN`
   - `public.resolve_ticket(p_ticket_id UUID) -> BOOLEAN`
   - `public.close_ticket(p_ticket_id UUID) -> BOOLEAN`
   - `public.reopen_ticket(p_ticket_id UUID) -> BOOLEAN`
6. **Integrated Audit & Notification Dispatch:** Reconciled audit logging (`audit_logs`) and recipient-scoped notification dispatch (`notifications`) across all 8 operational state transitions.
7. **62-Assertion Verification Suite:** Complete automated SQL verification suite in `database/verify_slice15.sql`.

---

## 7. Existing-State Audit

| Target Table | Existing Columns / Constraints | Slice 15 Requirement | Data Safety / Migration Impact |
|---|---|---|---|
| `ledger_transactions` | `check_transaction_type` constraint missing `'amenity_fee'` | Drop & recreate constraint adding `'amenity_fee'` | Non-destructive constraint replacement. Existing valid rows remain valid because `'amenity_fee'` is an additional permitted value. |
| `amenity_bookings` | `status` IN (`pending_approval`, `approved`, `rejected`, `cancelled`, `completed`) | Implement `reject_amenity_booking`, `complete_amenity_booking`, RESTRICTIVE RLS policy, and trigger | Attach RESTRICTIVE RLS policy and BEFORE UPDATE trigger to block client SQL bypass. |
| `visitor_logs` | `check_out TIMESTAMPTZ`, `pre_auth_code` partial unique index | Implement `checkout_visitor` with `FOR UPDATE` lock and `check_out IS NULL` check | Non-destructive; updates `check_out = NOW()`. |
| `helpdesk_tickets` | `status` IN (`open`, `assigned`, `in_progress`, `resolved`, `closed`), `resolved_at` exists | Implement 5 workflow stored procedures, SLA tracking columns, RESTRICTIVE RLS policy, and trigger | Additive columns (`assigned_at`, `started_at`, `closed_at`, `reopened_at`), RESTRICTIVE RLS policy, and BEFORE UPDATE trigger. |

---

## 8. Database Impact (`database/schema_slice15.sql`)

```sql
-- 1. Ledger Transaction Type Constraint Replacement
ALTER TABLE public.ledger_transactions DROP CONSTRAINT IF EXISTS check_transaction_type;
ALTER TABLE public.ledger_transactions ADD CONSTRAINT check_transaction_type CHECK (
    transaction_type IN (
        'charge', 'penalty', 'adjustment', 'waiver', 'payment', 'advance_payment',
        'refund', 'reversal', 'expense', 'income', 'amenity_fee'
    )
);

-- 2. Additive SLA Tracking Columns on Helpdesk Tickets
ALTER TABLE public.helpdesk_tickets 
    ADD COLUMN IF NOT EXISTS assigned_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS started_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS closed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS reopened_at TIMESTAMPTZ;

-- 3. RESTRICTIVE RLS Policies: Block Direct UPDATE for Role authenticated
DROP POLICY IF EXISTS pol_helpdesk_tickets_no_update ON public.helpdesk_tickets;
CREATE POLICY pol_helpdesk_tickets_no_update ON public.helpdesk_tickets 
    AS RESTRICTIVE FOR UPDATE TO authenticated USING (false) WITH CHECK (false);

DROP POLICY IF EXISTS pol_amenity_bookings_no_update ON public.amenity_bookings;
CREATE POLICY pol_amenity_bookings_no_update ON public.amenity_bookings 
    AS RESTRICTIVE FOR UPDATE TO authenticated USING (false) WITH CHECK (false);

-- 4. ID-Bound Defense-in-Depth Workflow Transition Triggers & Functions
CREATE OR REPLACE FUNCTION public.fn_prevent_direct_ticket_status_update()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        IF current_setting('app.ticket_workflow_context', true) IS DISTINCT FROM NEW.id::text THEN
            RAISE EXCEPTION 'Direct status update on helpdesk_tickets is blocked. Use workflow procedures.';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

CREATE TRIGGER trg_prevent_direct_ticket_status_update
    BEFORE UPDATE ON public.helpdesk_tickets
    FOR EACH ROW EXECUTE FUNCTION public.fn_prevent_direct_ticket_status_update();

CREATE OR REPLACE FUNCTION public.fn_prevent_direct_booking_status_update()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        IF current_setting('app.booking_workflow_context', true) IS DISTINCT FROM NEW.id::text THEN
            RAISE EXCEPTION 'Direct status update on amenity_bookings is blocked. Use workflow procedures.';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

CREATE TRIGGER trg_prevent_direct_booking_status_update
    BEFORE UPDATE ON public.amenity_bookings
    FOR EACH ROW EXECUTE FUNCTION public.fn_prevent_direct_booking_status_update();
```

---

## 9. Formal State Machines

### 9.1 Helpdesk Ticket Workflow Matrix

| Current State | Target State | Allowed? | Authorized Actor | Action Function | Database Enforcement |
|---|---|---|---|---|---|
| `open` | `assigned` | YES | Admin / Sec / Treas | `assign_ticket()` | Validates target technician role; updates `assigned_to`, `assigned_at` |
| `assigned` | `assigned` | YES | Admin / Sec / Treas | `assign_ticket()` | Reassigns ticket to new active technician |
| `in_progress` | `assigned` | **NO** | N/A | N/A | Prohibited. Reassignment cannot occur once work is in progress. |
| `assigned` | `in_progress` | YES | Assigned Tech / Admin | `start_ticket()` | Validates caller = `assigned_to` OR admin; updates `started_at` |
| `assigned` | `resolved` | YES | Assigned Tech / Admin | `resolve_ticket()` | Direct resolution allowed for rapid fixes; updates `resolved_at` |
| `in_progress` | `resolved` | YES | Assigned Tech / Admin | `resolve_ticket()` | Standard resolution after work start; updates `resolved_at` |
| `resolved` | `closed` | YES | Ticket Creator / Admin | `close_ticket()` | Validates caller = `created_by` OR admin; updates `closed_at` |
| `closed` | `open` | YES | Ticket Creator / Admin | `reopen_ticket()` | Clears `assigned_to = NULL`, clears `resolved_at = NULL`, updates `reopened_at` |

*Forbidden Transitions:* `open -> in_progress` (must be assigned first), `open -> resolved` (must be assigned first), `in_progress -> assigned` (cannot reassign in progress), `resolved -> assigned`, `closed -> resolved`, `closed -> in_progress`, any state -> `open` except from `closed` via `reopen_ticket()`.

### 9.2 Timestamp & Reopen Semantics

* **`resolved_at`:** Pre-existing schema column. Cleared to `NULL` upon `reopen_ticket()` because the ticket is open again and no longer currently resolved.
* **`assigned_to`:** Cleared to `NULL` upon `reopen_ticket()` to return ticket to unassigned open queue.
* **Historical Lifecycle Timestamps (`assigned_at`, `started_at`, `closed_at`, `reopened_at`):** Retained as historical facts representing previous lifecycle milestones. `reopened_at` is updated to `NOW()` upon reopening.

### 9.3 Amenity Booking Lifecycle Matrix

| Current State | Target State | Allowed? | Authorized Actor | Action Function | Financial / Ledger Effect |
|---|---|---|---|---|---|
| `pending_approval` | `rejected` | YES | Admin / Sec / Treas | `reject_amenity_booking()` | Zero ledger entries created (fee was never charged) |
| `approved` | `completed` | YES | Admin / Sec / Treas | `complete_amenity_booking()` | Zero ledger entries created (fee posted during approval) |

---

## 10. SECURITY DEFINER Function Privilege Audit (All 8 Procedures)

All 8 workflow procedures undergo catalog privilege auditing (`information_schema.routine_privileges`):

1. `reject_amenity_booking`
2. `complete_amenity_booking`
3. `checkout_visitor`
4. `assign_ticket`
5. `start_ticket`
6. `resolve_ticket`
7. `close_ticket`
8. `reopen_ticket`

**Privilege Model Rules:**
- `SECURITY DEFINER SET search_path = public, pg_temp`
- Function Owner: `postgres`
- `REVOKE ALL ON FUNCTION ... FROM PUBLIC;`
- Execution explicit grant to `authenticated` and `service_role`.
- Internal authorization checks enforce `is_admin()`, identity match (`assigned_to = auth.uid()`, `created_by = auth.uid()`), and active society boundary.

---

## 11. Audit & Notification Matrix

Reconciled against `PHASE_3B_SPECIFICATION.md` Section 13:

| Operation | State Change | Audit Required | Notification Required | Recipient | Notification Type & Title | Authorization |
|---|---|---|---|---|---|---|
| `reject_amenity_booking` | `pending_approval -> rejected` | YES (`REJECTED amenity booking`) | YES | Applicant (`booked_by`) | `amenity_status` ("Booking Rejected") | Admin / Sec / Treas |
| `complete_amenity_booking` | `approved -> completed` | YES (`COMPLETED amenity booking`) | YES | Applicant (`booked_by`) | `amenity_status` ("Booking Marked Complete") | Admin / Sec / Treas |
| `checkout_visitor` | `Active -> checked_out` | YES (`CHECKED OUT visitor`) | **NO** | N/A | N/A | Gatekeeper / Admin |
| `assign_ticket` | `open/assigned -> assigned` | YES (`ASSIGNED helpdesk ticket`) | YES | Assigned Tech | `helpdesk_assigned` ("Ticket Assigned: {title}") | Admin / Sec / Treas |
| `start_ticket` | `assigned -> in_progress` | YES (`STARTED helpdesk ticket`) | YES | Ticket Reporter | `helpdesk_update` ("Work Started on Your Ticket") | Assigned Tech / Admin |
| `resolve_ticket` | `assigned/in_progress -> resolved` | YES (`RESOLVED helpdesk ticket`) | YES | Ticket Reporter | `helpdesk_resolved` ("Your Ticket Has Been Resolved") | Assigned Tech / Admin |
| `close_ticket` | `resolved -> closed` | YES (`CLOSED helpdesk ticket`) | **NO** | N/A | N/A | Reporter / Admin |
| `reopen_ticket` | `closed -> open` | YES (`REOPENED helpdesk ticket`) | YES | Society Admin(s) | `helpdesk_reopened` ("Ticket Reopened: {title}") | Reporter / Admin |

---

## 12. Financial Integrity

* **Amenity Booking Approval:** Posts member subsidiary ledger debit (`scope = 'member'`, `transaction_type = 'amenity_fee'`).
* **Amenity Booking Rejection:** Rejects pending bookings before approval. **Zero ledger entries created.**
* **Amenity Booking Completion:** Transitions approved booking to completed. **Zero additional ledger entries created.**
* **Amenity Booking Cancellation:** Reverses fee if approved (`transaction_type = 'reversal'`).
* **Atomicity & Transaction Terminology:** Each workflow function performs its mutations atomically within the caller's database transaction; exceptions roll back the transaction's changes.

---

## 13. Concurrency & Idempotency Model

* **Row-Level Locking:** All 8 stored procedures execute `SELECT * INTO v_record FROM target_table WHERE id = p_id FOR UPDATE;`.
* **State Check Serialization:** Concurrent calls block on row lock. Second transaction reads updated status and returns error or no-op cleanly.
* **Pre-Auth Code Uniqueness:** Visitor checkout sets `check_out = NOW()`, releasing partial unique index `uq_visitor_active_pre_auth` for code reuse.

---

## 14. Migration & Data Safety

* **Terminology & Safety:** Non-destructive constraint replacement. Existing valid rows remain valid because `'amenity_fee'` is an additional permitted value.
* **Pre-Migration Verification:** `SELECT DISTINCT transaction_type FROM public.ledger_transactions;` is pre-checked to ensure zero existing rows violate the new or existing constraint.
* **Table Lock Duration:** `ALTER TABLE` constraint swap executes in milliseconds within a transaction.

---

## 15. Detailed Function Specifications

### 15.1 `reject_amenity_booking(p_booking_id UUID, p_reason TEXT)`
* **Inputs:** `p_booking_id UUID`, `p_reason TEXT` (default `'Rejected by administrator'`)
* **Outputs:** `BOOLEAN`
* **Roles:** Admin / Sec / Treas
* **Preconditions:** `status = 'pending_approval'`, society match
* **Auth Context:** Sets `PERFORM set_config('app.booking_workflow_context', p_booking_id::text, true);`
* **Mutations:** `status = 'rejected'`
* **Audit:** `action = 'REJECTED amenity booking'`, `table_name = 'amenity_bookings'`
* **Notification:** Recipient = `booked_by`, `type = 'amenity_status'`, `title = 'Booking Rejected'`

### 15.2 `complete_amenity_booking(p_booking_id UUID)`
* **Inputs:** `p_booking_id UUID`
* **Outputs:** `BOOLEAN`
* **Roles:** Admin / Sec / Treas
* **Preconditions:** `status = 'approved'`, society match
* **Auth Context:** Sets `PERFORM set_config('app.booking_workflow_context', p_booking_id::text, true);`
* **Mutations:** `status = 'completed'`
* **Audit:** `action = 'COMPLETED amenity booking'`, `table_name = 'amenity_bookings'`
* **Notification:** Recipient = `booked_by`, `type = 'amenity_status'`, `title = 'Booking Marked Complete'`

### 15.3 `checkout_visitor(p_log_id UUID)`
* **Inputs:** `p_log_id UUID`
* **Outputs:** `BOOLEAN`
* **Roles:** Gatekeeper / Admin
* **Preconditions:** `check_out IS NULL`, society match
* **Mutations:** `check_out = NOW()`
* **Audit:** `action = 'CHECKED OUT visitor'`, `table_name = 'visitor_logs'`
* **Notification:** None required

### 15.4 `assign_ticket(p_ticket_id UUID, p_technician_id UUID)`
* **Inputs:** `p_ticket_id UUID`, `p_technician_id UUID`
* **Outputs:** `BOOLEAN`
* **Roles:** Admin / Sec / Treas
* **Preconditions:** Target user has `technician` role, `status NOT IN ('resolved', 'closed')`, society match
* **Auth Context:** Sets `PERFORM set_config('app.ticket_workflow_context', p_ticket_id::text, true);`
* **Mutations:** `assigned_to = p_technician_id`, `status = 'assigned'`, `assigned_at = NOW()`
* **Audit:** `action = 'ASSIGNED helpdesk ticket'`, `table_name = 'helpdesk_tickets'`
* **Notification:** Recipient = `p_technician_id`, `type = 'helpdesk_assigned'`, `title = 'Ticket Assigned'`

### 15.5 `start_ticket(p_ticket_id UUID)`
* **Inputs:** `p_ticket_id UUID`
* **Outputs:** `BOOLEAN`
* **Roles:** Assigned Technician / Admin
* **Preconditions:** `assigned_to = auth.uid()` OR Admin, `status = 'assigned'`, society match
* **Auth Context:** Sets `PERFORM set_config('app.ticket_workflow_context', p_ticket_id::text, true);`
* **Mutations:** `status = 'in_progress'`, `started_at = NOW()`
* **Audit:** `action = 'STARTED helpdesk ticket'`, `table_name = 'helpdesk_tickets'`
* **Notification:** Recipient = `created_by`, `type = 'helpdesk_update'`, `title = 'Work Started on Your Ticket'`

### 15.6 `resolve_ticket(p_ticket_id UUID)`
* **Inputs:** `p_ticket_id UUID`
* **Outputs:** `BOOLEAN`
* **Roles:** Assigned Technician / Admin
* **Preconditions:** `assigned_to = auth.uid()` OR Admin, `status IN ('assigned', 'in_progress')`, society match
* **Auth Context:** Sets `PERFORM set_config('app.ticket_workflow_context', p_ticket_id::text, true);`
* **Mutations:** `status = 'resolved'`, `resolved_at = NOW()`
* **Audit:** `action = 'RESOLVED helpdesk ticket'`, `table_name = 'helpdesk_tickets'`
* **Notification:** Recipient = `created_by`, `type = 'helpdesk_resolved'`, `title = 'Your Ticket Has Been Resolved'`

### 15.7 `close_ticket(p_ticket_id UUID)`
* **Inputs:** `p_ticket_id UUID`
* **Outputs:** `BOOLEAN`
* **Roles:** Ticket Reporter / Admin
* **Preconditions:** `created_by = auth.uid()` OR Admin, `status = 'resolved'`, society match
* **Auth Context:** Sets `PERFORM set_config('app.ticket_workflow_context', p_ticket_id::text, true);`
* **Mutations:** `status = 'closed'`, `closed_at = NOW()`
* **Audit:** `action = 'CLOSED helpdesk ticket'`, `table_name = 'helpdesk_tickets'`
* **Notification:** None required

### 15.8 `reopen_ticket(p_ticket_id UUID)`
* **Inputs:** `p_ticket_id UUID`
* **Outputs:** `BOOLEAN`
* **Roles:** Ticket Reporter / Admin
* **Preconditions:** `created_by = auth.uid()` OR Admin, `status = 'closed'`, society match
* **Auth Context:** Sets `PERFORM set_config('app.ticket_workflow_context', p_ticket_id::text, true);`
* **Mutations:** `status = 'open'`, `assigned_to = NULL`, `resolved_at = NULL`, `reopened_at = NOW()`
* **Audit:** `action = 'REOPENED helpdesk ticket'`, `table_name = 'helpdesk_tickets'`
* **Notification:** Recipient = Society Admins, `type = 'helpdesk_reopened'`, `title = 'Ticket Reopened'`

---

## 16. Exact Verification Assertions (62 Assertions)

`database/verify_slice15.sql` will execute **62 genuine SQL assertions**:

### Helpdesk Direct UPDATE, RLS & GUC Adversarial Tests (Assertions 1–6)
1. Direct client `UPDATE helpdesk_tickets.status` as `authenticated` user rejected by RESTRICTIVE RLS
2. `authenticated` user sets boolean GUC `SET LOCAL app.ticket_workflow_context = 'true'` and attempts direct `UPDATE`; rejected by RESTRICTIVE RLS
3. `authenticated` user constructs target ID context `SET LOCAL app.ticket_workflow_context = '<ticket_id>'` and attempts direct `UPDATE`; rejected by RESTRICTIVE RLS
4. Elevated direct `UPDATE` with correct target ID GUC but no workflow procedure execution analyzed/verified for Application Security Boundary
5. Superuser direct `UPDATE` without setting GUC blocked by trigger `trg_prevent_direct_ticket_status_update`
6. Legitimate `assign_ticket()` `SECURITY DEFINER` execution succeeds

### Helpdesk Workflow State Machine Tests (Assertions 7–15)
7. Audit log created for `assign_ticket()` (`ASSIGNED helpdesk ticket`)
8. Notification delivered to technician (`helpdesk_assigned`)
9. Legitimate `start_ticket()` transition succeeds
10. Audit log & notification delivered for `start_ticket()`
11. Legitimate `resolve_ticket()` transition succeeds
12. Audit log & notification delivered for `resolve_ticket()`
13. Legitimate `close_ticket()` transition succeeds
14. Legitimate `reopen_ticket()` transition succeeds (`assigned_to = NULL`, `resolved_at = NULL`, `reopened_at` set)
15. Notification delivered to admin for `reopen_ticket()` (`helpdesk_reopened`)

### Amenity Booking Direct UPDATE, RLS & GUC Adversarial Tests (Assertions 16–21)
16. Direct client `UPDATE amenity_bookings.status` as `authenticated` user rejected by RESTRICTIVE RLS
17. `authenticated` user sets boolean GUC `SET LOCAL app.booking_workflow_context = 'true'` and attempts direct `UPDATE`; rejected by RESTRICTIVE RLS
18. `authenticated` user constructs target ID context `SET LOCAL app.booking_workflow_context = '<booking_id>'` and attempts direct `UPDATE`; rejected by RESTRICTIVE RLS
19. Elevated direct `UPDATE` with correct target ID GUC but no workflow procedure execution analyzed/verified for Application Security Boundary
20. Legitimate `reject_amenity_booking()` `SECURITY DEFINER` execution succeeds
21. Legitimate `complete_amenity_booking()` `SECURITY DEFINER` execution succeeds

### Amenity Booking Workflow State Machine Tests (Assertions 22–25)
22. Audit log & notification created for `reject_amenity_booking()`
23. Rejection of non-pending booking blocked
24. Audit log & notification created for `complete_amenity_booking()`
25. Completion of non-approved booking blocked

### Visitor Log & Pre-Auth Code Tests (Assertions 26–31)
26. Gatekeeper `checkout_visitor()` success
27. Audit log created for `checkout_visitor()` (`CHECKED OUT visitor`)
28. Non-gatekeeper/non-admin checkout blocked
29. Double checkout attempt blocked (`Visitor already checked out`)
30. Pre-auth code slot freed for reuse after checkout
31. Cross-society visitor checkout blocked

### Security, Role & IDOR Boundary Tests (Assertions 32–41)
32. Cross-society `assign_ticket()` blocked
33. Cross-society `start_ticket()` blocked
34. Cross-society `resolve_ticket()` blocked
35. Cross-society `close_ticket()` blocked
36. Cross-society `reopen_ticket()` blocked
37. Cross-society `reject_amenity_booking()` blocked
38. Cross-society `complete_amenity_booking()` blocked
39. Unassigned technician `start_ticket()` blocked
40. Non-reporter non-admin `close_ticket()` blocked
41. Assignment to user without `technician` role blocked

### Concurrency & Replay Serialization Tests (Assertions 42–47)
42. Concurrent double `checkout_visitor()` execution serialization & second-call rejection
43. Concurrent double `reject_amenity_booking()` execution serialization & rejection
44. Concurrent double `complete_amenity_booking()` execution serialization & rejection
45. Concurrent `start_ticket()` on unassigned / already started ticket serialization & rejection
46. Concurrent `resolve_ticket()` on already resolved ticket serialization & rejection
47. Concurrent `reopen_ticket()` on open ticket serialization & rejection

### Catalog, RLS & Database Privilege Audits (Assertions 48–62)
48. `ledger_transactions` `'amenity_fee'` constraint check verified
49. `SECURITY DEFINER` search_path catalog check for all 8 procedures
50. Function EXECUTE privilege audit (REVOKE FROM PUBLIC, explicit grants verified) across all 8 procedures
51. FORCE ROW LEVEL SECURITY (`relforcerowsecurity`) catalog verification on `helpdesk_tickets` and `amenity_bookings`
52. SECURITY DEFINER table ownership (`pg_class.relowner = postgres`) verified for target tables
53. Historical vs current-state timestamp integrity verified
54. Notification scoping & payload schema verified
55. Complete helpdesk UPDATE-policy catalog audit (`pg_policies` check confirming zero unhandled permissive UPDATE paths)
56. Complete amenity-booking UPDATE-policy catalog audit (`pg_policies` check confirming zero unhandled permissive UPDATE paths)
57. Complete database privilege / UPDATE / `BYPASSRLS` role audit (`information_schema.table_privileges` & `pg_roles`)
58. All non-trusted application/service roles are verified to lack a direct UPDATE privilege or RLS bypass path to the protected workflow tables
59. Separate catalog check identifying superuser roles, `BYPASSRLS` roles, table owner, and application/service roles
60. Elevated-role direct UPDATE attack using correct target-ID GUC classified and verified
61. Financial atomicity verification (zero ledger side-effects on rejected/failed workflows)
62. Cumulative suite integrity & non-weakening assertion

---

## 17. Proposed Assertion Metrics

* **Locked Regression Baseline:** 372 PASS
* **Slice 15 Proposed Assertions:** 62 PASS
* **Target Cumulative Result:** **434 PASS**

---

## 18. Regression Strategy

`scratch/run_all15.ps1` will execute `scratch/run_all14.ps1` (verifying 372/372 PASS), apply `database/schema_slice15.sql`, run `database/verify_slice15.sql`, parse test results dynamically, and output the cumulative baseline report (434/434 PASS).

---

## 19. Evidence Strategy

Post-implementation, the following artifacts will be produced:
1. `TEST_EXECUTION_OUTPUT.txt` (Full raw console log showing 372 + 62 = 434 PASS)
2. `WORKING_TREE_STATUS.txt` (Git status & file modifications summary)
3. `SLICE15_IMPLEMENTATION_REPORT.md` (Detailed implementation report)
4. `SLICE15_FINAL_REVIEW_PACKAGE.zip` (Complete review archive)

---

## 20. Rollback Strategy

* **Schema Rollback:** Drop Slice 15 functions (`DROP FUNCTION IF EXISTS public.reject_amenity_booking...`), triggers, and RLS update policies.
* **Column Rollback:** Drop additive SLA columns (`ALTER TABLE public.helpdesk_tickets DROP COLUMN IF EXISTS assigned_at...`).
* **Constraint Rollback Safety Condition:** Reverting `check_transaction_type` to its original value is safe **ONLY IF** zero rows with `transaction_type = 'amenity_fee'` have been persisted to `public.ledger_transactions`. If amenity fee rows exist, they must be purged or migrated before constraint rollback.

---

## 21. Files Allowed to Change (Upon Authorization)

```text
[NEW] database/schema_slice15.sql
[NEW] database/verify_slice15.sql
[NEW] scratch/run_all15.ps1
[NEW] SLICE15_IMPLEMENTATION_PLAN.md
```

---

## 22. Files Locked (MUST REMAIN UNTOUCHED)

```text
database/schema_slice1.sql THROUGH database/schema_slice14.sql (LOCKED)
database/verify_slice1.sql THROUGH database/verify_slice14.sql (LOCKED)
scratch/run_all13.ps1 (LOCKED)
scratch/run_all14.ps1 (LOCKED)
```

---

## 23. Acceptance Criteria

1. All 62 Slice 15 assertions pass cleanly (62/62 PASS).
2. Locked baseline 372/372 PASS is 100% preserved.
3. Total suite output achieves 434/434 PASS.
4. No locked files (Slices 1–14) are modified.
5. All 8 stored procedures enforce `SECURITY DEFINER SET search_path = public, pg_temp` and cross-society isolation.
6. Direct client `UPDATE` on status columns is rejected for verified client roles because the final RLS policy and privilege catalog state provide no permitted UPDATE path.

---

## 24. Implementation Sequence

1. Obtain explicit user approval.
2. Create `database/schema_slice15.sql` with DDL, RLS policies, triggers & stored procedures.
3. Create `database/verify_slice15.sql` with 62 genuine test assertions.
4. Create `scratch/run_all15.ps1` runner script.
5. Execute regression suite & capture raw execution log.
6. Generate evidence reports & review package archive.

---

## 25. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Permissive RLS policy combination leak | Implemented RESTRICTIVE RLS policies (`AS RESTRICTIVE FOR UPDATE TO authenticated USING (false)`), forcing AND combination logic across all policy checks. |
| Client GUC spoofing attack on status columns | Dual-layer architecture: RLS policy `USING (false)` blocks all client UPDATE queries regardless of GUCs set. Client GUC spoofing cannot grant UPDATE capability. |
| Concurrent state update race conditions | Implemented `SELECT ... FOR UPDATE` row locking across all 8 stored procedures. |
| Reopen ticket state stale timestamps | Cleared `assigned_to` and `resolved_at` to `NULL`, setting `reopened_at = NOW()`. |
| Constraint rollback failure | Documented explicit condition requiring zero persisted `amenity_fee` rows prior to constraint revert. |

---

## 26. Final Approval Gate

```text
SLICE 15 FINAL SECURITY PLAN REVISION COMPLETE

Locked baseline: 372/372 PASS
Slices 1–14: LOCKED / UNTOUCHED
Slice 15 implementation: NOT STARTED
Implementation authorization: PENDING USER APPROVAL

NO APPLICATION OR DATABASE IMPLEMENTATION MAY BEGIN
UNTIL EXPLICIT USER APPROVAL IS PROVIDED.
```
