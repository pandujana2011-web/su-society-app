# SU SOCIETY APP — SLICE 24 FORMAL FORENSIC SECURITY PLAN

**Document Reference:** `SLICE24_FORMAL_FORENSIC_SECURITY_PLAN.md`  
**Target Repository:** `D:\Clients Applications\SU Society App`  
**Target Supabase Project:** `fsegpxqoozxmicxcxjun` (`ap-south-1`)  
**Lifecycle Stage:** SLICE 24 FORMAL FORENSIC SECURITY PLANNING  
**Security Classification:** `CLASSIFICATION A`  
**Execution Mode:** `PLAN ONLY / ZERO IMPLEMENTATION / ZERO DATABASE MUTATION / ZERO DEPLOYMENT / ZERO LOCK`  

---

## 1. EXECUTIVE STATUS

Slice 24 represents the **Operations Lifecycle Completion & Multi-Role Operations** phase for the SU Society App platform. This document establishes the authoritative, read-only forensic security specification and formal implementation plan for Slice 24.

* **Authorization State:** NOT IMPLEMENTED / NOT DEPLOYED / NOT GOVERNANCE-CLOSED / NOT SECURITY-LOCKED.
* **Planning Scope:** Helpdesk Ticket Lifecycle, Visitor Management Lifecycle Completion, Amenity Booking Terminal Lifecycle, Ledger Constraint Alignment (`amenity_fee`), Transactional Audit Logging, User-Scoped Notifications, Multi-Role Authorization, State-Machine Security, Dynamic Concurrency Control, Cross-Society Isolation, RPC & Privilege Escalation Defenses, Frontend/Mock Parity Governance, Operational Reporting Dashboards, Threat Modeling (TV24-01 to TV24-20), and Deterministic Verification (S24-001 to S24-053).
* **Baseline Integrity:** Slices 21, 22, and 23 remain 100% frozen, intact, and immutable.

---

## 2. GOVERNANCE BASELINE

| Slice / Artifact Boundary | Reference File / Identifier | Authoritative SHA-256 Hash / Status |
| :--- | :--- | :--- |
| **Slice 21 Lock Artifact** | `SLICE21_GOVERNANCE_CLOSURE_AND_SECURITY_LOCK.md` | `C8F5E8742CA04391AC51889AD671CD9868710F7C5AB6CC6A9C39C84BCAF16912` |
| **Slice 22 Lock Artifact** | `SLICE22_GOVERNANCE_CLOSURE_AND_SECURITY_LOCK.md` | `BADDA60288021729D4E46A38642ECBBAB3C89EDDCC3A8BCC603EAA6A9B36C3C7` |
| **Slice 23 Lock Artifact** | `SLICE23_GOVERNANCE_CLOSURE_AND_SECURITY_LOCK.md` | `C05F5DB093A2C013E2C14B02CFDBAE0AF2C356935F8B4CABBEBEE720C6CB3D6E` |
| **Slice 23 Remote Migration** | `supabase/migrations/20260912000023_slice23.sql` | `0231E69F903D3C82F273B7896B29A087D9ABA1CFA928487B6F330881F9236740` |
| **Slice 23 Remote Boundary** | Remote Database Migration History | `20260912000023_slice23.sql` (Deployed M-02) |
| **Slice 24 Lifecycle Init** | `SLICE24_LIFECYCLE_INITIALIZATION_FORENSIC_SECURITY_GATE.md` | `B86F3B9A0E7A651C74AFF5731492ED807930CAA273A6214D5D2BECFB72559FCE` |

---

## 3. SCOPE DEFINITION

Slice 24 candidate technical scope is defined across seven functional pillars:

1. **Helpdesk Lifecycle Completion:**
   * Transitions: `open → assigned → in_progress → resolved → closed` and `resolved/closed → open` (reopen).
   * Proposed Functions: `fn_assign_helpdesk_ticket`, `fn_start_helpdesk_ticket`, `fn_resolve_helpdesk_ticket`, `fn_close_helpdesk_ticket`, `fn_reopen_helpdesk_ticket`.
2. **Visitor Management Lifecycle Completion:**
   * Function: `fn_checkout_visitor`.
   * Enforcements: Compound exit timestamping, status update to `checked_out`, pre-authorization validity validation, single-checkout idempotency, and concurrent checkout locking.
3. **Amenity Booking Lifecycle Completion:**
   * Functions: `fn_reject_amenity_booking`, `fn_complete_amenity_booking`.
   * Enforcements: Rejection of pending bookings with mandatory reasons, completion of confirmed bookings post-usage, terminal state immutability, and ledger refund correlation.
4. **Ledger Constraint Alignment:**
   * Candidate Change: Update `public.ledger_transactions` `check_transaction_type` CHECK constraint to include `'amenity_fee'`.
   * Enforcements: Non-disruptive migration without invalidating past accounting records (`maintenance_fee`, `fine`, `penalty`, `utility_charge`, `payment`).
5. **Transactional Audit & Notification Pipeline:**
   * Atomic logging into `public.audit_logs` for all state machine transitions.
   * Atomic generation of targeted, role-scoped notifications in `public.notifications`.
6. **Frontend / Mock Parity Governance:**
   * Formal isolation of development/demo quick-login workflows (`gatekeeper`, `technician`).
   * Strict boundary between mock functions in `src/supabase.js` and production RLS-enforced backend RPCs.
7. **Operational Reporting Dashboards:**
   * Secure, multi-tenant aggregated reporting views for open tickets, mean resolution time, active compound visitors, and amenity utilization rates without PII leakage or cross-society data bleeding.

---

## 4. REPOSITORY EVIDENCE

Forensic inspection of the local codebase (`D:\Clients Applications\SU Society App`) establishes the current technical baseline:

1. **Database Schema Baseline (`database/schema_phase2.sql` & `database/schema_slice23.sql`):**
   * `public.helpdesk_tickets` currently defines status `CHECK (status IN ('open', 'assigned', 'in_progress', 'resolved', 'closed'))`.
   * `public.visitors` defines status `CHECK (status IN ('expected', 'checked_in', 'checked_out', 'expired', 'denied'))`.
   * `public.amenity_bookings` defines status `CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled', 'completed'))`.
   * `public.ledger_transactions` constraint `check_transaction_type` is currently: `CHECK (transaction_type IN ('maintenance_fee', 'fine', 'penalty', 'utility_charge', 'payment'))`.
2. **Existing RPC Operations (`supabase/migrations/` Slices 1–23):**
   * Core RPCs rely on `SECURITY DEFINER` with explicit `search_path = pg_catalog, public`.
   * Authentication context is strictly derived from `auth.uid()`, resolving the caller's role via `public.profiles`.
3. **Frontend Application Logic (`src/App.jsx` & `src/supabase.js`):**
   * `src/App.jsx` contains UI tab routing for `helpdesk`, `visitors`, `amenities`, and `ledger`.
   * `src/supabase.js` contains client-side helper wrappers and mock implementations for offline demonstration.

---

## 5. HELPDESK LIFECYCLE SECURITY PLAN

### State Transition Matrix

```
       +--------------+
       |     open     |
       +------+-------+
              | (fn_assign_helpdesk_ticket: Admin)
              v
       +--------------+
       |   assigned   |
       +------+-------+
              | (fn_start_helpdesk_ticket: Assigned Tech / Admin)
              v
       +--------------+
       | in_progress  |
       +------+-------+
              | (fn_resolve_helpdesk_ticket: Assigned Tech / Admin)
              v
       +--------------+
       |   resolved   |
       +------+-------+
              | (fn_close_helpdesk_ticket: Ticket Creator / Admin)
              v
       +--------------+
       |    closed    |
       +--------------+
```
*Reopen Path:* `resolved` OR `closed` → `open` via `fn_reopen_helpdesk_ticket` (Ticket Creator or Admin).

### Proposed RPC Specifications

1. **`fn_assign_helpdesk_ticket(p_ticket_id UUID, p_technician_id UUID, p_notes TEXT)`**
   * **Permitted Roles:** `admin`.
   * **Preconditions:** Ticket exists; ticket belongs to caller's society; current status = `open`; target technician belongs to the same society and has role `technician`.
   * **Postconditions:** Status updated to `assigned`; `assigned_to` set to `p_technician_id`; audit log & technician notification created.
2. **`fn_start_helpdesk_ticket(p_ticket_id UUID)`**
   * **Permitted Roles:** Assigned `technician`, `admin`.
   * **Preconditions:** Ticket status = `assigned`; caller is assigned technician or admin; society matches caller.
   * **Postconditions:** Status updated to `in_progress`; `started_at` timestamp recorded.
3. **`fn_resolve_helpdesk_ticket(p_ticket_id UUID, p_resolution_notes TEXT)`**
   * **Permitted Roles:** Assigned `technician`, `admin`.
   * **Preconditions:** Ticket status = `in_progress`; `p_resolution_notes` is non-empty.
   * **Postconditions:** Status updated to `resolved`; `resolved_at` timestamp recorded; ticket creator notified.
4. **`fn_close_helpdesk_ticket(p_ticket_id UUID, p_feedback_rating INT, p_feedback_notes TEXT)`**
   * **Permitted Roles:** Ticket Creator (`resident`/`owner`/`tenant`), `admin`.
   * **Preconditions:** Ticket status = `resolved`; caller is creator or admin.
   * **Postconditions:** Status updated to `closed`; `closed_at` timestamp recorded; feedback rating persisted.
5. **`fn_reopen_helpdesk_ticket(p_ticket_id UUID, p_reopen_reason TEXT)`**
   * **Permitted Roles:** Ticket Creator, `admin`.
   * **Preconditions:** Ticket status IN (`resolved`, `closed`); `p_reopen_reason` provided.
   * **Postconditions:** Status reset to `open`; `assigned_to` cleared; `reopen_count` incremented.

---

## 6. VISITOR LIFECYCLE SECURITY PLAN

### Departure Operations (`fn_checkout_visitor`)

1. **Permitted Roles:** `gatekeeper`, `admin`.
2. **Execution Flow & Deterministic Concurrency:**
   * Acquire explicit row-level lock: `SELECT * FROM public.visitors WHERE id = p_visitor_id AND society_id = v_caller_society_id FOR UPDATE;`
   * Check status: Must be `checked_in`. If status is `checked_out`, throw SQLSTATE `45000` (`VISITOR_ALREADY_CHECKED_OUT`).
   * Validate exit timestamp: `check_out_time = NOW()`.
   * Update visitor state: Set `status = 'checked_out'`, `exit_gate = p_exit_gate`.
   * Write atomic audit log entry and notify host resident.

---

## 7. AMENITY LIFECYCLE SECURITY PLAN

### Proposed Terminal RPC Specifications

1. **`fn_reject_amenity_booking(p_booking_id UUID, p_rejection_reason TEXT)`**
   * **Permitted Roles:** `admin`.
   * **Preconditions:** Booking status = `pending`; society match confirmed.
   * **Postconditions:** Status updated to `rejected`; rejection reason recorded; applicant notified. If fee was debited, write ledger reversal record.
2. **`fn_complete_amenity_booking(p_booking_id UUID)`**
   * **Permitted Roles:** `admin`, `gatekeeper` (facility operator).
   * **Preconditions:** Booking status = `approved`; booking end time has passed (`booking_end < NOW()`).
   * **Postconditions:** Status updated to `completed`. Terminal state—no further modifications allowed.

---

## 8. LEDGER CONSTRAINT SECURITY PLAN

### Alignment Analysis for `'amenity_fee'`

1. **Existing Constraint Definition:**
   ```sql
   ALTER TABLE public.ledger_transactions 
   DROP CONSTRAINT IF EXISTS check_transaction_type;

   ALTER TABLE public.ledger_transactions 
   ADD CONSTRAINT check_transaction_type 
   CHECK (transaction_type IN ('maintenance_fee', 'fine', 'penalty', 'utility_charge', 'payment', 'amenity_fee'));
   ```
2. **Accounting Integrity Guarantees:**
   * `'amenity_fee'` is defined as a DEBIT transaction type assessing charges against resident accounts.
   * All existing balances, calculations, and financial reporting RPCs maintain strict non-breaking backwards compatibility.
   * No modification to historical transaction records.

---

## 9. AUDIT LOGGING PLAN

Every Slice 24 state transition RPC MUST write directly to `public.audit_logs` within the same database transaction.

### Audit Log Standard Payload Structure

```json
{
  "actor_id": "UUID",
  "actor_role": "admin | technician | gatekeeper | resident",
  "society_id": "UUID",
  "entity_type": "helpdesk_ticket | visitor | amenity_booking",
  "entity_id": "UUID",
  "action": "ASSIGN | START | RESOLVE | CLOSE | REOPEN | CHECKOUT | REJECT | COMPLETE",
  "previous_state": "JSONB / string",
  "new_state": "JSONB / string",
  "timestamp": "ISO8601",
  "correlation_id": "UUID",
  "client_ip": "INET"
}
```

*Atomicity Guarantee:* If audit log insertion fails for any reason (e.g. schema error, RLS breach), the entire state transition transaction MUST ABORT and rollback.

---

## 10. NOTIFICATION PLAN

Slice 24 operations automatically emit in-app notifications to affected users via `public.notifications`.

| Operation | Recipient Scope | Notification Content Summary |
| :--- | :--- | :--- |
| `fn_assign_helpdesk_ticket` | Assigned Technician | "New ticket assigned: #{ticket_id}" |
| `fn_resolve_helpdesk_ticket` | Ticket Creator | "Your ticket #{ticket_id} has been resolved." |
| `fn_checkout_visitor` | Host Resident | "Visitor {visitor_name} checked out at {time}." |
| `fn_reject_amenity_booking` | Booking Applicant | "Booking #{booking_id} rejected: {reason}." |

---

## 11. MULTI-ROLE AUTHORIZATION MATRIX

| Operation | Admin | Gatekeeper | Technician | Owner / Resident | Tenant | Verification Mechanism |
| :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| `fn_assign_helpdesk_ticket` | **ALLOW** | DENY | DENY | DENY | DENY | Server-side role check via `profiles` |
| `fn_start_helpdesk_ticket` | **ALLOW** | DENY | **ALLOW (Assigned)** | DENY | DENY | `auth.uid() = assigned_to` check |
| `fn_resolve_helpdesk_ticket` | **ALLOW** | DENY | **ALLOW (Assigned)** | DENY | DENY | `auth.uid() = assigned_to` check |
| `fn_close_helpdesk_ticket` | **ALLOW** | DENY | DENY | **ALLOW (Creator)** | **ALLOW (Creator)** | `auth.uid() = created_by` check |
| `fn_reopen_helpdesk_ticket` | **ALLOW** | DENY | DENY | **ALLOW (Creator)** | **ALLOW (Creator)** | `auth.uid() = created_by` check |
| `fn_checkout_visitor` | **ALLOW** | **ALLOW** | DENY | DENY | DENY | Gatekeeper role & society check |
| `fn_reject_amenity_booking` | **ALLOW** | DENY | DENY | DENY | DENY | Admin role & society check |
| `fn_complete_amenity_booking` | **ALLOW** | **ALLOW** | DENY | DENY | DENY | Role & society check |

---

## 12. STATE-MACHINE SECURITY MODEL

To prevent illegal state bypasses (e.g., jumping from `open` directly to `closed`), every state transition RPC strictly validates the `previous_state`.

```
Helpdesk Transitions:
open ------(assign)-----> assigned -----(start)-----> in_progress -----(resolve)-----> resolved -----(close)-----> closed
  ^                                                                                         |                             |
  +------------------------------------(reopen)---------------------------------------------+-----------------------------+
```

* **Invalid Transition Handling:** Attempting an out-of-order transition raises SQLSTATE `45000` with explicit code `ERR_INVALID_STATE_TRANSITION`.
* **Terminal States:** `closed` (for tickets/amenities) and `checked_out` (for visitors) are immutable except through explicitly authorized RPC pathways (`fn_reopen_helpdesk_ticket`).

---

## 13. CONCURRENCY MODEL

To mitigate TOCTOU (Time-of-Check to Time-of-Use) vulnerabilities in high-concurrency environments, all state-modifying RPCs enforce explicit pessimistic locking.

```
Client Transaction A                      Client Transaction B
      |                                         |
      |--- fn_checkout_visitor(V1) ----------->|
      |    (SELECT ... FOR UPDATE)              |
      |    [Lock Acquired on V1]                |--- fn_checkout_visitor(V1) --->
      |    Update V1 -> checked_out             |    (SELECT ... FOR UPDATE)
      |    Commit Transaction                   |    [BLOCKED Waiting for Lock]
      v                                         |    ...
                                                |    [Lock Released by A]
                                                |--->[Lock Acquired by B]
                                                     Evaluate State: V1 == checked_out
                                                     RAISE EXCEPTION 'VISITOR_ALREADY_CHECKED_OUT'
```

---

## 14. CROSS-SOCIETY ISOLATION MODEL

All RPCs enforce strict tenant multi-tenancy isolation using authenticated context derivation:

1. **No Untrusted Parameters:** RPCs NEVER accept `society_id` or caller `role` as user-supplied parameters.
2. **Identity & Society Resolution:**
   ```sql
   v_actor_id := auth.uid();
   SELECT society_id, role INTO v_society_id, v_actor_role 
   FROM public.profiles 
   WHERE id = v_actor_id;
   ```
3. **Cross-Tenant Guard:** Every query includes `WHERE id = p_target_id AND society_id = v_society_id`. If a record belongs to another society, the RPC raises `SQLSTATE '42501' (INSUFFICIENT_PRIVILEGE)`.

---

## 15. RPC SECURITY MODEL

All proposed PostgreSQL functions strictly enforce hardening standards:

* **Execution Paradigm:** Functions are defined as `SECURITY DEFINER`.
* **Search Path Hardening:** `SET search_path = pg_catalog, public;` is mandatory on all functions to eliminate search-path injection.
* **Revocation of Public Access:** `REVOKE EXECUTE ON FUNCTION fn_... FROM PUBLIC, anon;`.
* **Explicit Grants:** `GRANT EXECUTE ON FUNCTION fn_... TO authenticated;`.

---

## 16. FRONTEND / MOCK SECURITY MODEL

1. **Development Mock Scope:**
   * Quick-login credentials (`gatekeeper`, `technician`) in UI are strictly restricted to `import.meta.env.DEV`.
   * Production builds MUST strip quick-login demo selectors using build-time environment variable evaluation (`VITE_ALLOW_DEMO_LOGIN=false`).
2. **Mock vs Production Backend Parity:**
   * Client-side helper functions in `src/supabase.js` MUST call remote RPCs via `supabase.rpc()` when connected to a real backend.
   * Client mock state MUST NEVER be treated as an authoritative security boundary.

---

## 17. OPERATIONAL REPORTING SECURITY MODEL

Operational dashboards (e.g. active visitor counts, ticket resolution times) are implemented via `SECURITY DEFINER` reporting RPCs or RLS-protected views:

* **Aggregation Scope:** All metrics are strictly filtered by caller's `society_id`.
* **PII Redaction:** Aggregated operational metrics do not expose resident mobile numbers, gatekeeper credentials, or confidential document references.
* **Performance Optimization:** Views rely on composite indexed fields `(society_id, status, created_at)`.

---

## 18. THREAT MODEL

| Threat Vector ID | Attack Surface | Attacker Capability | Attack Scenario | Security Invariant | Mitigation / Enforcement | Severity |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **TV24-01** | `fn_assign_helpdesk_ticket` | Authenticated Resident | Tenant attempts to assign ticket to another technician | Admin-only assignment | Server RPC verifies `v_actor_role = 'admin'` | HIGH |
| **TV24-02** | `fn_start_helpdesk_ticket` | Unassigned Technician | Technician starts ticket assigned to someone else | Assignment authorization | Server verifies `assigned_to = auth.uid()` | MEDIUM |
| **TV24-03** | Helpdesk State Machine | Malicious User | Caller invokes `fn_close_helpdesk_ticket` on `open` ticket | Strict state sequence | RPC enforces `current_status = 'resolved'` | HIGH |
| **TV24-04** | Helpdesk Reopen | Unauthorized Resident | Resident reopens ticket created by another resident | Creator ownership | RPC enforces `created_by = auth.uid()` | HIGH |
| **TV24-05** | `fn_checkout_visitor` | Race Condition | Two gatekeepers trigger checkout simultaneously | Single checkout idempotency | `SELECT FOR UPDATE` pessimistic lock | HIGH |
| **TV24-06** | `fn_checkout_visitor` | Cross-Society Gatekeeper | Gatekeeper checkouts visitor in foreign society | Tenant isolation | RPC enforces `society_id = v_society_id` | CRITICAL |
| **TV24-07** | `fn_reject_amenity_booking` | Resident | Resident attempts to reject neighbor's booking | Admin-only rejection | RPC verifies `v_actor_role = 'admin'` | HIGH |
| **TV24-08** | Amenity State | Malicious Admin | Admin alters booking post-completion | Terminal immutability | RPC blocks transitions from `completed` | MEDIUM |
| **TV24-09** | `ledger_transactions` | Direct SQL / API | Insertion of invalid transaction type | Ledger integrity | `check_transaction_type` CHECK constraint | CRITICAL |
| **TV24-10** | Audit System | Malicious Actor | State transition succeeds but audit insertion is bypassed | Transactional audit | Atomic single-transaction audit execution | CRITICAL |
| **TV24-11** | Audit Payload | Client Forgery | Client supplies fake IP/actor in audit parameter | Untrusted client input | Backend derives actor/IP from context | HIGH |
| **TV24-12** | Notifications | Cross-Society Attacker | Injecting notification into another society's stream | Tenant notification barrier | RPC verifies recipient `society_id` | HIGH |
| **TV24-13** | RPC Execution | Anon User | Public caller invokes Slice 24 RPCs directly | Restricted execution | `REVOKE EXECUTE FROM anon, public` | CRITICAL |
| **TV24-14** | `search_path` Injection | Malicious Schema | Schema spoofing during RPC execution | Search path hardening | `SET search_path = pg_catalog, public` | CRITICAL |
| **TV24-15** | Role Forgery | Client Request | Client passes `role='admin'` in RPC payload | Untrusted parameter | Backend fetches role from `profiles` | CRITICAL |
| **TV24-16** | Frontend Demo Login | Production Attacker | Attacker accesses quick-login buttons in prod | Demo isolation | `VITE_ALLOW_DEMO_LOGIN=false` build gate | HIGH |
| **TV24-17** | Reporting Dashboard | Cross-Society User | Admin reads metrics of another society | Operational multi-tenancy | Reporting RPC filters by `society_id` | HIGH |
| **TV24-18** | Amenity Fee Ledger | Double-Debit Attack | Re-triggering amenity fee charge RPC | Unique booking debit | Transaction idempotency check | HIGH |
| **TV24-19** | Visitor Pre-Auth | Expired Pass Entry | Gatekeeper checks out expired/denied visitor | Pre-auth validation | RPC checks status `checked_in` | MEDIUM |
| **TV24-20** | Reopen Abuse | Malicious Resident | Infinite reopen loop on resolved tickets | Reopen threshold | RPC enforces max `reopen_count <= 3` | LOW |

---

## 19. VERIFICATION ASSERTION MATRIX

| Assertion ID | Domain | Assertion Description | Target Object / RPC | Classification |
| :--- | :--- | :--- | :--- | :--- |
| **S24-001** | Schema | Helpdesk status constraint contains `open, assigned, in_progress, resolved, closed` | `public.helpdesk_tickets` | Forensic |
| **S24-002** | Schema | Visitor status constraint contains `expected, checked_in, checked_out, expired, denied` | `public.visitors` | Forensic |
| **S24-003** | Schema | Amenity booking status constraint contains `pending, approved, rejected, cancelled, completed` | `public.amenity_bookings` | Forensic |
| **S24-004** | Schema | Ledger constraint includes `'amenity_fee'` | `public.ledger_transactions` | Forensic |
| **S24-005** | RPC | `fn_assign_helpdesk_ticket` defined with `SECURITY DEFINER` | Function Spec | Forensic |
| **S24-006** | RPC | `fn_assign_helpdesk_ticket` enforces `SET search_path = pg_catalog, public` | Function Spec | Forensic |
| **S24-007** | Auth | `fn_assign_helpdesk_ticket` restricts execution to `admin` | Function Spec | Runtime |
| **S24-008** | Auth | `fn_assign_helpdesk_ticket` rejects non-admin callers with `42501` | Function Spec | Runtime |
| **S24-009** | State | `fn_assign_helpdesk_ticket` requires current status `open` | Function Spec | Runtime |
| **S24-010** | Tenant | `fn_assign_helpdesk_ticket` verifies technician belongs to same society | Function Spec | Runtime |
| **S24-011** | RPC | `fn_start_helpdesk_ticket` defined with `SECURITY DEFINER` | Function Spec | Forensic |
| **S24-012** | RPC | `fn_start_helpdesk_ticket` enforces hardened `search_path` | Function Spec | Forensic |
| **S24-013** | Auth | `fn_start_helpdesk_ticket` restricts execution to assigned technician or admin | Function Spec | Runtime |
| **S24-014** | State | `fn_start_helpdesk_ticket` requires current status `assigned` | Function Spec | Runtime |
| **S24-015** | RPC | `fn_resolve_helpdesk_ticket` defined with `SECURITY DEFINER` | Function Spec | Forensic |
| **S24-016** | Auth | `fn_resolve_helpdesk_ticket` restricts execution to assigned technician or admin | Function Spec | Runtime |
| **S24-017** | State | `fn_resolve_helpdesk_ticket` requires current status `in_progress` | Function Spec | Runtime |
| **S24-018** | Data | `fn_resolve_helpdesk_ticket` requires non-empty resolution notes | Function Spec | Runtime |
| **S24-019** | RPC | `fn_close_helpdesk_ticket` defined with `SECURITY DEFINER` | Function Spec | Forensic |
| **S24-020** | Auth | `fn_close_helpdesk_ticket` restricts execution to ticket creator or admin | Function Spec | Runtime |
| **S24-021** | State | `fn_close_helpdesk_ticket` requires current status `resolved` | Function Spec | Runtime |
| **S24-022** | RPC | `fn_reopen_helpdesk_ticket` defined with `SECURITY DEFINER` | Function Spec | Forensic |
| **S24-023** | Auth | `fn_reopen_helpdesk_ticket` restricts execution to creator or admin | Function Spec | Runtime |
| **S24-024** | State | `fn_reopen_helpdesk_ticket` requires status `resolved` or `closed` | Function Spec | Runtime |
| **S24-025** | Data | `fn_reopen_helpdesk_ticket` increments `reopen_count` | Function Spec | Runtime |
| **S24-026** | RPC | `fn_checkout_visitor` defined with `SECURITY DEFINER` | Function Spec | Forensic |
| **S24-027** | RPC | `fn_checkout_visitor` enforces `search_path = pg_catalog, public` | Function Spec | Forensic |
| **S24-028** | Auth | `fn_checkout_visitor` permits `gatekeeper` and `admin` only | Function Spec | Runtime |
| **S24-029** | Lock | `fn_checkout_visitor` performs `SELECT ... FOR UPDATE` | Function Spec | Runtime |
| **S24-030** | State | `fn_checkout_visitor` verifies current status is `checked_in` | Function Spec | Runtime |
| **S24-031** | Idempotency| Concurrent `fn_checkout_visitor` calls throw `VISITOR_ALREADY_CHECKED_OUT` | Function Spec | Runtime |
| **S24-032** | Tenant | `fn_checkout_visitor` enforces society boundary match | Function Spec | Runtime |
| **S24-033** | RPC | `fn_reject_amenity_booking` defined with `SECURITY DEFINER` | Function Spec | Forensic |
| **S24-034** | Auth | `fn_reject_amenity_booking` restricts execution to `admin` | Function Spec | Runtime |
| **S24-035** | State | `fn_reject_amenity_booking` requires status `pending` | Function Spec | Runtime |
| **S24-036** | RPC | `fn_complete_amenity_booking` defined with `SECURITY DEFINER` | Function Spec | Forensic |
| **S24-037** | Auth | `fn_complete_amenity_booking` permits `admin` and `gatekeeper` | Function Spec | Runtime |
| **S24-038** | State | `fn_complete_amenity_booking` requires status `approved` | Function Spec | Runtime |
| **S24-039** | State | `completed` amenity booking state is immutable | Function Spec | Runtime |
| **S24-040** | Audit | All state transitions write entry to `public.audit_logs` | Audit System | Runtime |
| **S24-041** | Audit | Audit log insertion failure aborts parent transaction | Audit System | Runtime |
| **S24-042** | Audit | Audit payloads strictly derive `actor_id` from `auth.uid()` | Audit System | Runtime |
| **S24-043** | Notification| Ticket resolution writes notification to ticket creator | Notifications | Runtime |
| **S24-044** | Notification| Visitor checkout writes notification to host resident | Notifications | Runtime |
| **S24-045** | Notification| Notifications are scoped strictly to recipient's `society_id` | Notifications | Runtime |
| **S24-046** | Security | PUBLIC and anon execution revoked on all Slice 24 RPCs | Database Grants | Forensic |
| **S24-047** | Security | Execution granted strictly to `authenticated` role | Database Grants | Forensic |
| **S24-048** | Tenant | Cross-society parameter manipulation throws `42501` | Multi-tenancy | Runtime |
| **S24-049** | Frontend | Quick-login demo component disabled in production builds | Frontend App | Forensic |
| **S24-050** | Frontend | `src/supabase.js` routes operations through backend RPCs | Frontend App | Forensic |
| **S24-051** | Reporting | Operational reporting RPCs filter by caller's `society_id` | Dashboards | Runtime |
| **S24-052** | Reporting | Operational reporting views expose zero PII fields | Dashboards | Forensic |
| **S24-053** | Ledger | Insert of transaction with type `'amenity_fee'` succeeds | Ledger System | Runtime |

---

## 20. MIGRATION BOUNDARY

* **Current Remote Migration Boundary:** `20260912000023_slice23.sql`
* **Candidate Slice 24 Migration:** `20260912000024_slice24.sql` (NOT CREATED / NOT EXECUTED).
* **Isolation Rule:** Slice 25+ migrations remain completely excluded.
* **Deployment Protocol:** Future deployment MUST strictly follow the verified single-migration M-02 manual transaction pipeline. `npx supabase db push` is EXPLICITLY PROHIBITED.

---

## 21. LOCKED-SLICE COMPATIBILITY

Slice 24 design has been forensically evaluated against locked Slices 21, 22, and 23:

* **Slice 21 (Blacklist / Security):** No modifications to `public.blacklists` or security structures. `fn_checkout_visitor` strictly complements Slice 21 gatekeeper operational flows.
* **Slice 22 (Rule Violations / Fine Ledger):** `public.ledger_transactions` constraint update (`'amenity_fee'`) preserves all fine and penalty transaction types introduced in Slice 22 without breaking schema constraints.
* **Slice 23 (Document Vault):** Complete independence. No shared tables or conflicting security definer dependencies.
* **Baseline Conflicts Identified:** `ZERO (0)`.

---

## 22. ADVERSARIAL ANALYSIS

The plan addresses 20 required adversarial security questions:

1. **Can a tenant invoke any admin/gatekeeper/technician lifecycle function?**  
   *No.* Server-side RPCs inspect `public.profiles` for `auth.uid()` and reject unauthorized roles with SQLSTATE `42501`.
2. **Can a gatekeeper manipulate a helpdesk ticket outside their society?**  
   *No.* RPC queries enforce `WHERE society_id = v_caller_society_id`.
3. **Can a technician resolve tickets they are not authorized to handle?**  
   *No.* `fn_resolve_helpdesk_ticket` verifies `assigned_to = auth.uid()` or caller is `admin`.
4. **Can an attacker jump directly from `open` to `closed`?**  
   *No.* State machine validates `current_status = 'resolved'` before allowing `closed`.
5. **Can a closed ticket be modified without an explicit reopen transition?**  
   *No.* State machine blocks update RPCs on `closed` tickets.
6. **Can two concurrent checkout calls both succeed?**  
   *No.* `SELECT FOR UPDATE` locks the visitor row; the second request reads `checked_out` and throws `VISITOR_ALREADY_CHECKED_OUT`.
7. **Can two concurrent lifecycle transitions corrupt state?**  
   *No.* Row-level locking guarantees sequential state transitions.
8. **Can a caller forge `society_id`?**  
   *No.* `society_id` is derived from `public.profiles` via `auth.uid()` on the server.
9. **Can a caller forge actor/user ID?**  
   *No.* Actor identity is anchored strictly to Supabase JWT `auth.uid()`.
10. **Can a caller forge role?**  
    *No.* Role parameters passed by clients are ignored; role is fetched from `public.profiles`.
11. **Can a caller forge property ownership?**  
    *No.* Property ownership is verified against `public.property_members`.
12. **Can an attacker replay a successful transition?**  
    *No.* Transition preconditions (e.g. status MUST be `pending`) fail on replayed calls.
13. **Can notifications be injected for another society?**  
    *No.* Notification RPCs derive society boundaries from the target entity's verified `society_id`.
14. **Can audit logs be forged or attributed to another user?**  
    *No.* Audit logging is performed inside `SECURITY DEFINER` RPCs using verified `auth.uid()`.
15. **Can `'amenity_fee'` create an accounting integrity problem?**  
    *No.* It is added as an additive valid transaction type within the existing ledger debit framework.
16. **Can a frontend mock role reach production behavior?**  
    *No.* Production RLS and RPCs strictly validate backend JWT authorization regardless of UI state.
17. **Can demo credentials appear in production bundles?**  
    *No.* Demo UI components are conditionally rendered only when `import.meta.env.DEV` is true.
18. **Can dashboard aggregation leak cross-society information?**  
    *No.* Reporting RPCs mandate `WHERE society_id = v_caller_society_id`.
19. **Can a malicious client invoke RPCs directly while bypassing UI controls?**  
    *Yes, clients can invoke RPCs, BUT* server-side RPC validation prevents unauthorized execution.
20. **Can any proposed function create a `SECURITY DEFINER` privilege escalation?**  
    *No.* All RPCs enforce `SET search_path = pg_catalog, public` and perform strict role checks before executing actions.

---

## 23. SECURITY CLASSIFICATION

This forensic security plan is classified as:

### `CLASSIFICATION A`

* **Rationale:** No critical or high security defects or material planning deficiencies identified. All state transitions, multi-tenancy boundaries, role matrices, concurrency locks, and verification assertions are fully specified and compliant with platform governance.

---

## 24. REQUIRED FUTURE GOVERNANCE GATES

Before Slice 24 implementation may commence, the following sequential governance gates MUST be executed:

1. **Gate 1:** `SLICE 24 ADVERSARIAL PRE-IMPLEMENTATION SECURITY REVIEW` (Plan Audit).
2. **Gate 2:** `EXPLICIT HUMAN IMPLEMENTATION AUTHORIZATION`.
3. **Gate 3:** `LOCAL SLICE 24 MIGRATION & CODE IMPLEMENTATION`.
4. **Gate 4:** `LOCAL VERIFICATION & TEST SUITE EXECUTION` (S24-001 to S24-053).
5. **Gate 5:** `EXPLICIT HUMAN REMOTE DEPLOYMENT AUTHORIZATION` (M-02 Pipeline).

---

## 25. EXPLICIT NON-AUTHORIZATION STATEMENT

```
SLICE 24 FORMAL FORENSIC SECURITY PLAN ONLY.

NO SLICE 24 IMPLEMENTATION AUTHORIZED.

NO DATABASE MUTATION PERFORMED.

NO MIGRATION EXECUTED.

NO REMOTE DEPLOYMENT PERFORMED.

NO VERCEL DEPLOYMENT PERFORMED.

NO GOVERNANCE CLOSURE PERFORMED.

NO SECURITY LOCK CREATED.

SLICES 21–23 REMAIN IMMUTABLE.
```

---
**End of Artifact:** `SLICE24_FORMAL_FORENSIC_SECURITY_PLAN.md`
