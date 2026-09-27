# SLICE 24 — LIFECYCLE INITIALIZATION AND FORENSIC SECURITY PLANNING GATE REPORT

**Target Repository:** `D:\Clients Applications\SU Society App`  
**Target Supabase Project:** `fsegpxqoozxmicxcxjun`  
**Target Region:** `ap-south-1`  
**Execution Mode:** `PLAN ONLY / READ-ONLY FORENSIC SECURITY PLANNING GATE`  
**Date:** `2026-09-15T18:54:00Z`

---

## 1. EXECUTIVE STATUS & CLASSIFICATION

* **Planning Status:** `INITIALIZATION & FORENSIC PLANNING GATE COMPLETE`
* **Planning Classification:** `Classification A: CANDIDATE SCOPE IS CLEAR, INTERNALLY COHERENT, AND COMPATIBLE WITH LOCKED SLICES 21–23`
* **Implementation Authorization:** `0% — ZERO IMPLEMENTATION AUTHORIZED`
* **Deployment Authorization:** `0% — ZERO DEPLOYMENT AUTHORIZED`
* **Database State:** `100% UNMUTATED & READ-ONLY`

---

## 2. CURRENT LOCKED BASELINE & REMOTE BOUNDARY

* **Slice 21 Baseline:** `GOVERNANCE CLOSED + SECURITY LOCKED`  
  - SHA-256: `C8F5E8742CA04391AC51889AD671CD9868710F7C5AB6CC6A9C39C84BCAF16912` (`IMMUTABLE`)
* **Slice 22 Baseline:** `GOVERNANCE CLOSED + SECURITY LOCKED`  
  - SHA-256: `BADDA60288021729D4E46A38642ECBBAB3C89EDDCC3A8BCC603EAA6A9B36C3C7` (`IMMUTABLE`)
* **Slice 23 Baseline:** `GOVERNANCE CLOSED + SECURITY LOCKED`  
  - SHA-256: `C05F5DB093A2C013E2C14B02CFDBAE0AF2C356935F8B4CABBEBEE720C6CB3D6E` (`IMMUTABLE`)
* **Slice 23 Migration File:** `supabase/migrations/20260912000023_slice23.sql` (SHA-256: `0231E69F903D3C82F273B7896B29A087D9ABA1CFA928487B6F330881F9236740`)
* **Post-Slice-23 Frontend Audit:** `APPLICATION_FRONTEND_POST_SLICE23_FORENSIC_SECURITY_AUDIT.md` (SHA-256: `AF57FEC9B2E5D68474B2DD8FE0F50066CC075A9787BB865D5BF0D814824B6475`, Classification A)
* **Current Remote Migration Boundary:** `20260912000023_slice23.sql`

---

## 3. REPOSITORY DISCOVERY & EVIDENCE FOR CANDIDATE SCOPE

Direct read-only inspection of repository files (`PHASE_3B_SPECIFICATION.md`, `src/App.jsx`, `src/supabase.js`, `database/schema_phase2.sql`) reveals the authoritative evidence for the proposed Slice 24 scope:

1. **Unfinished State Machines:** Phase 3A entities (`helpdesk_tickets`, `amenity_bookings`, `visitor_logs`) have incomplete server-side state machines in SQL. While JS mocks partially simulate transitions, server-side PL/pgSQL stored procedures for ticket assignment, work start, resolution, closure, reopening, booking rejection, booking completion, and visitor check-out are absent.
2. **Ledger Constraint Mismatch:** Stored procedure `approve_amenity_booking` uses `transaction_type = 'amenity_fee'`, but `'amenity_fee'` is missing from the `ledger_transactions` `check_transaction_type` CHECK constraint.
3. **Multi-Role Frontend Gaps:** Roles `gatekeeper` and `technician` exist in the database RBAC model and React views (`isGatekeeper`, `isTechnician`), but lack demo user credentials in `INITIAL_MOCK_DATA` and server-backed RPC action triggers.
4. **Audit & Notification Completeness:** State transitions across helpdesk tickets, amenity bookings, and visitor logs do not consistently trigger structured `audit_logs` and recipient-scoped `notifications`.

---

## 4. CANDIDATE SLICE 24 SCOPE: OPERATIONS LIFECYCLE COMPLETION & MULTI-ROLE OPERATIONS (PHASE 3B)

The proposed Slice 24 candidate scope consists of 7 coherent functional pillars:

1. **Helpdesk Ticket Lifecycle Completion:**
   - Stored procedures: `fn_assign_helpdesk_ticket`, `fn_start_helpdesk_ticket`, `fn_resolve_helpdesk_ticket`, `fn_close_helpdesk_ticket`, `fn_reopen_helpdesk_ticket`.
   - Enforce state machine transitions: `open` → `assigned` → `in_progress` → `resolved` → `closed` (with reporter/admin reopening to `open`).
2. **Visitor Management Lifecycle Completion:**
   - Stored procedure: `fn_checkout_visitor`.
   - Pre-auth code expiration, invalidation, and double check-out prevention.
3. **Amenity Booking Lifecycle Completion:**
   - Stored procedures: `fn_reject_amenity_booking`, `fn_complete_amenity_booking`.
   - Complete booking state transitions to `rejected` or `completed`.
4. **Ledger Constraint Alignment:**
   - Alter `check_transaction_type` CHECK constraint on `public.ledger_transactions` to add `'amenity_fee'`.
5. **Operational Audit & Notification Completeness:**
   - Enforce structured `audit_logs` and recipient-scoped `notifications` across all Phase 3 operations.
6. **Multi-Role Frontend & Mock Parity:**
   - Add Gatekeeper and Technician credentials and UI quick-access workflows.
   - Add mock functions mirroring PostgreSQL stored procedure contracts.
7. **Operational Reporting & Transparency Dashboards:**
   - Admin Operations Reporting widgets (open ticket count, resolution time averages, active bookings, visitors in compound, amenity utilization).

---

## 5. EXISTING DEPENDENCIES VS. NEW SLICE 24 REQUIREMENTS

| Architectural Layer | Existing Locked Dependency | New Slice 24 Requirement |
|---|---|---|
| **Tables** | `societies`, `users`, `user_roles`, `properties`, `units`, `property_owners`, `tenancies`, `helpdesk_tickets`, `ticket_comments`, `amenities`, `amenity_bookings`, `visitor_logs`, `ledger_transactions`, `audit_logs`, `notifications` | Zero new tables. Additive nullable SLA columns on `helpdesk_tickets` (`assigned_at`, `started_at`, `closed_at`, `reopened_at`). |
| **Constraints** | `check_transaction_type` on `ledger_transactions` | Widen CHECK constraint to include `'amenity_fee'`. |
| **Functions** | `create_amenity_booking`, `approve_amenity_booking`, `cancel_amenity_booking` | Add 8 new `SECURITY DEFINER` routines for helpdesk, visitor checkout, and booking completion/rejection. |
| **Storage** | `society-vault` bucket (Slice 23) | No Storage changes required. |
| **Frontend** | `App.jsx`, `supabase.js`, `vaultService.js` | Update OperationsManagerView, TechnicianDashboardView, LoginCard, and mock procedures in `supabase.js`. |

---

## 6. SECURITY BOUNDARY SPECIFICATION

* **Authentication Boundary:** All RPC routines require a valid user session (`auth.uid() IS NOT NULL`).
* **Authorization Boundary:** Executed via `SECURITY DEFINER` routines with fixed `search_path = pg_catalog, public`.
* **RBAC Controls:**
  - `assign_ticket`: Restricted to Admin, Secretary, Treasurer.
  - `start_ticket` & `resolve_ticket`: Restricted to Assigned Technician or Admin.
  - `close_ticket` & `reopen_ticket`: Restricted to Ticket Reporter (`created_by`) or Admin.
  - `reject_amenity_booking` & `complete_amenity_booking`: Restricted to Admin, Secretary, Treasurer.
  - `checkout_visitor`: Restricted to Gatekeeper or Admin.
* **State Machine Protection:** `SELECT ... FOR UPDATE` locking on domain rows prevents state jump bypasses and race conditions.
* **Direct DML Protection:** Direct table DML (`INSERT`, `UPDATE`, `DELETE`) remains restricted by RLS policies; state transitions are forced through RPCs.

---

## 7. PRELIMINARY THREAT MODEL (20 THREAT VECTORS)

| Threat ID | Threat Vector Description | Severity | Attack Surface | Required Mitigation | Verification Method |
|---|---|---|---|---|---|
| **TV24-01** | Unauthorized ticket assignment by non-admin | High | RPC `assign_ticket` | PL/pgSQL role check (`fn_is_admin`) | Assertion `S24-001` |
| **TV24-02** | Technician starting unassigned or another tech's ticket | High | RPC `start_ticket` | Check `assigned_to = auth.uid()` | Assertion `S24-002` |
| **TV24-03** | Unauthorized ticket resolution | High | RPC `resolve_ticket` | Check `assigned_to = auth.uid()` or admin | Assertion `S24-003` |
| **TV24-04** | Non-reporter closing or reopening ticket | Medium | RPC `close_ticket` / `reopen_ticket` | Check `created_by = auth.uid()` or admin | Assertion `S24-004` |
| **TV24-05** | State machine bypass (jumping states) | High | All helpdesk RPCs | Re-read row `FOR UPDATE` & validate state | Assertion `S24-005` |
| **TV24-06** | Cross-society ticket access/assignment leak | Critical | RPC `assign_ticket` | Verify ticket `society_id` matches caller | Assertion `S24-006` |
| **TV24-07** | Unauthorized booking rejection/completion | High | RPC `reject`/`complete_booking` | Check caller admin role | Assertion `S24-007` |
| **TV24-08** | Booking completion without fee tracking | Medium | RPC `complete_amenity_booking` | Reconcile payment status | Assertion `S24-008` |
| **TV24-09** | Rejection of already-approved/completed booking | Medium | RPC `reject_amenity_booking` | Check `status = 'pending_approval'` | Assertion `S24-009` |
| **TV24-10** | Unauthorized visitor check-out by non-gatekeeper | High | RPC `checkout_visitor` | Check caller `gatekeeper` or admin role | Assertion `S24-010` |
| **TV24-11** | Double visitor check-out race condition | Medium | RPC `checkout_visitor` | `FOR UPDATE` + `check_out IS NULL` check | Assertion `S24-11` |
| **TV24-12** | Pre-auth visitor code brute force | High | Gatekeeper verify | Rate limit & lockout timer | Assertion `S24-12` |
| **TV24-13** | Expired pre-auth code reuse | Medium | Gatekeeper verify | Check `valid_until >= NOW()` | Assertion `S24-13` |
| **TV24-14** | Cross-society visitor check-in/out leak | Critical | RPC `checkout_visitor` | Verify `society_id` match | Assertion `S24-14` |
| **TV24-15** | SQLSTATE 42704/23514 `amenity_fee` constraint error | Critical | Ledger INSERT | Add `'amenity_fee'` to CHECK constraint | Assertion `S24-15` |
| **TV24-16** | Direct client DML state manipulation | Critical | Tables | RLS policies & DML revocation | Assertion `S24-16` |
| **TV24-17** | Concurrent state transition race condition | High | All RPCs | `SELECT ... FOR UPDATE` locking | Assertion `S24-17` |
| **TV24-18** | Audit log omission on state transition | Low | RPCs | Mandatory `audit_logs` INSERT | Assertion `S24-18` |
| **TV24-19** | Cross-society notification leakage | High | Notifications | Explicit recipient `user_id` scoping | Assertion `S24-19` |
| **TV24-20** | UI role spoofing attempting privileged RPC | High | Frontend | Backend PL/pgSQL validation | Assertion `S24-20` |

---

## 8. CROSS-SOCIETY & ROLE ISOLATION MODEL

* **Society Isolation:** Every proposed RPC resolves `society_id` via target entity joins (`properties.society_id`, `units.property_id`) and compares against `public.fn_get_user_society_id(auth.uid())`.
* **Role Separation:**
  - Admin: Overall operational management, ticket assignment, booking rejection/completion.
  - Technician: Work execution (`in_progress`, `resolved`) on assigned tickets only.
  - Gatekeeper: Visitor check-in/out and move pass verification.
  - Resident (Member/Tenant): Ticket filing, ticket closure/reopening, amenity booking request.

---

## 9. CONCURRENCY & TRANSACTION LOCKING MODEL

* All state-transition routines execute within a single PostgreSQL transaction (`BEGIN ... COMMIT`).
* Row-level pessimistic locking (`SELECT ... FOR UPDATE`) is enforced prior to state evaluation:
  - `assign_ticket`, `start_ticket`, `resolve_ticket`, `close_ticket`, `reopen_ticket` lock `helpdesk_tickets` row.
  - `reject_amenity_booking`, `complete_amenity_booking` lock `amenity_bookings` row.
  - `checkout_visitor` locks `visitor_logs` row.

---

## 10. VERIFICATION STRATEGY

* **Test Suite Expansion:** 53 new substantive assertions (`S24-001` through `S24-053`) expanding the test suite from 113 to 166 assertions.
* **Categories:**
  1. Ledger constraint widening (`amenity_fee` insertion and reversal integrity).
  2. Helpdesk state machine and RBAC role boundaries (assignment, start, resolve, close, reopen).
  3. Amenity booking rejection and completion workflows.
  4. Visitor check-out idempotency and pre-auth code validity.
  5. Audit log and notification delivery verification.
  6. Regression pass of all 113 historical assertions.

---

## 11. LOCKED-BASELINE COMPATIBILITY & CONFLICT CHECK

* **Locked Baseline Status:** Slices 21, 22, and 23 remain 100% immutable and untouched.
* **Baseline Conflict Audit:**
  - Slice 21 (`C8F5...`): Zero conflict. No changes to core schema or financial engine.
  - Slice 22 (`BADD...`): Zero conflict. No changes to rule violation or penalty structures.
  - Slice 23 (`C05F...`): Zero conflict. No changes to `vault_*` tables or storage policies.
* **Baseline Conflict Count:** `ZERO (0) BASELINE CONFLICTS IDENTIFIED`.

---

## 12. FUTURE GOVERNANCE LIFECYCLE FOR SLICE 24

1. Slice 24 Lifecycle Initialization & Forensic Security Planning Gate *(Current Stage)*
2. Slice 24 Formal Forensic Security Plan
3. Slice 24 Adversarial Pre-Implementation Security Review
4. Slice 24 Explicit Local Implementation Authorization Gate
5. Slice 24 Local Implementation
6. Slice 24 Post-Implementation Forensic Security Audit
7. Slice 24 Remote Deployment Scope Dry-Run Forensic Report
8. Slice 24 Explicit Remote Deployment Authorization Gate
9. Slice 24 M-02 Isolated Remote Deployment
10. Slice 24 Post-Deployment Forensic Verification
11. Slice 24 Post-Deployment Governance Forensic Closure Review
12. Slice 24 Final Governance Closure & Security Lock Gate Audit
13. Slice 24 Explicit Human Governance Closure & Security Lock Authorization
14. Slice 24 Final Governance Closure & Security Lock

---

## 13. MANDATORY STATEMENTS

SLICE 24 LIFECYCLE INITIALIZATION ONLY.  
NO SLICE 24 IMPLEMENTATION AUTHORIZED.  
NO DATABASE MUTATION PERFORMED.  
NO MIGRATION EXECUTED.  
NO REMOTE DEPLOYMENT PERFORMED.  
NO VERCEL DEPLOYMENT PERFORMED.  
NO GOVERNANCE CLOSURE PERFORMED.  
NO SECURITY LOCK CREATED.  
SLICES 21–23 REMAIN IMMUTABLE.

---

## 14. RECOMMENDED NEXT GATE

`SLICE 24 FORMAL FORENSIC SECURITY PLAN`  
*(To be initiated under separate explicit human authorization).*
