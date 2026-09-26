# SLICE 3 IMPLEMENTATION PLAN

## A. Scope
Implement Society Operations: Amenity Bookings, Helpdesk Tickets, and Gatekeeper/Visitor Logs.
This slice builds on the Slice 1 (Governance/Identity) and Slice 2 (Financial Ledger) locked architecture.

## B. Entities/tables
1. `amenities`: Defines bookable facilities (slot_based or day_based).
2. `amenity_bookings`: Records member bookings, integrated with the financial ledger (if paid).
3. `helpdesk_tickets`: Records member complaints/requests.
4. `ticket_comments`: Communication thread for tickets.
5. `visitor_logs`: Records guest/delivery/service entries handled by gatekeepers.

## C. Columns and constraints
- `amenities`: `society_id`, `name`, `booking_type`, `hourly_rate` (>= 0), `is_active`. Unique `(society_id, name)`.
- `amenity_bookings`: `amenity_id`, `property_id`, `booked_by`, `start_time`, `end_time`, `total_charges` (>= 0), `status` (pending_approval, approved, rejected, cancelled, completed), `payment_status` (unpaid, paid, refunded). Check `start_time < end_time`.
- `helpdesk_tickets`: `society_id`, `unit_id`, `created_by`, `category`, `title`, `description`, `priority`, `status`, `assigned_to`, `resolved_at`.
- `ticket_comments`: `ticket_id`, `author_id`, `comment_text`.
- `visitor_logs`: `society_id`, `unit_id` (nullable for society-level visits), `visitor_name`, `visitor_mobile`, `purpose`, `check_in`, `check_out`, `pre_auth_code`, `vehicle_number`, `registered_by`.

## D. Foreign-key relationships
All references strictly bound to `societies`, `properties`, `units`, and `users`. Deletions RESTRICT where history must be preserved (bookings, tickets, visitors), and CASCADE only for internal sub-entities (ticket_comments -> tickets).

## E. State machines
- **Amenity Bookings**: `pending_approval` -> `approved` | `rejected` | `cancelled`. `approved` -> `completed` | `cancelled`. 
- **Helpdesk Tickets**: `open` -> `assigned` -> `in_progress` -> `resolved` -> `closed`. 
- **Visitor Logs**: Checked-in (`check_out IS NULL`) -> Checked-out (`check_out IS NOT NULL`).

## F. Temporal rules where applicable
- Amenity bookings cannot overlap for the same amenity (exclusion trigger).
- Pre-auth codes must be unique among currently active (non-checked-out) visitors within a society.

## G. RLS SELECT policies
- Admin/Gatekeeper/Helpdesk roles: See relevant society-wide records.
- Members (Owner/Tenant): See only their property's bookings, tickets, and visitors.
- Unrelated users: See 0 records.

## H. RLS INSERT/UPDATE/DELETE policies
- **Default Deny**: Clients cannot directly INSERT, UPDATE, or DELETE records where state changes trigger financial or security implications (e.g., Amenity Bookings requiring ledger integration, or Visitor check-ins).
- Users can INSERT tickets and comments directly via RLS if authorized for the property.

## I. SECURITY DEFINER functions
- `fn_create_amenity_booking`: Enforces concurrency locks, verifies authorization, calculates exact charges, and creates booking.
- `fn_process_booking_action`: Handles state transitions (approve/reject/cancel) and integrates with the immutable financial ledger (generating charges/reversals).
- `fn_visitor_check_in` & `fn_visitor_check_out`: Handled by Gatekeeper, strictly logging time and preventing duplicate active pre-auth codes.

## J. search_path security
All SECURITY DEFINER functions will use `SET search_path = public, pg_temp` to prevent search path hijacking.

## K. Authorization checks
Explicit verification inside functions:
- `is_admin()`, `has_role('gatekeeper')`, `has_role('helpdesk')`.
- Ensure operators and targets belong to the same `society_id`.

## L. Cross-society isolation
All tables possess a direct or implicitly verified `society_id`. RLS and function logic strictly enforce `society_id = get_user_society_id(auth.uid())`.

## M. Audit logging
All state transitions via SECURITY DEFINER functions write to `audit_logs`:
- Booking creation, approval, cancellation.
- Visitor check-in, check-out.
- Ticket status changes (if moved to SECURITY DEFINER).

## N. Idempotency requirements
- Visitor check-out must be idempotent (if already checked out, no-op or reject).
- Booking approval must reject if already approved.

## O. Atomicity requirements
Booking approval must atomically generate the ledger charge if `total_charges > 0`. If the charge generation fails, the booking approval rolls back.

## P. Reversal/correction strategy where applicable
If a booking is cancelled after approval, an automatic reversal transaction (credit) must be generated against the `maintenance_charges` ledger entry for the booking.

## Q. Notification/event requirements if applicable
State changes trigger PostgreSQL NOTIFY (or Supabase Realtime) for frontend synchronization (e.g., gatekeeper visitor arrival notifying the resident).

## R. Index strategy
- Active visitor logs: `WHERE check_out IS NULL`.
- Booking overlap checks: GIST index on timestamps, or triggers if complex.

## S. Performance considerations
Using `FOR UPDATE` locks when processing booking overlaps or payment statuses to prevent race conditions.

## T. Migration/apply order
Applies as `schema_slice3.sql` immediately after `schema_slice2.sql`.

## U. Rollback strategy
Drop Slice 3 tables and functions if deployment fails.

## V. Verification strategy
`verify_slice3.sql` will perform a full live database audit covering schema, concurrency, RLS isolation, cross-society prevention, and atomicity, running strictly after Slice 1 and Slice 2 tests to ensure no regressions.
