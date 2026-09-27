# SLICE 14 — COMPREHENSIVE SECURITY REVIEW REPORT

**Date:** 2026-09-03  
**System:** SU Society App  
**Target:** Slice 14 (Automated Payment Gateway Integration & Webhook Settlement)  
**Status:** Remediated & Fully Audited  

---

## 1. EXECUTIVE SECURITY SUMMARY

Slice 14 introduces automated external payment gateway webhooks (e.g. Stripe, Razorpay) and asynchronous payment settlement into the SU Society App database. Because payment settlement mutates ledgers, generates official financial receipts, and alters payment balances, security controls must guarantee that:
1. External webhooks cannot forge payments, amounts, or society allocations.
2. Low-privileged clients (residents, external callers) cannot invoke internal settlement helper functions directly.
3. Webhook retries and duplicate events are strictly idempotent and cannot produce double-ledger debits or duplicate receipts.
4. All database operations strictly enforce tenant (society and property) isolation and follow the immutable audit logging standards established in Slices 1–13.

---

## 2. DETAILED SECURITY BOUNDARY ANALYSIS

### 2.1 Webhook Trust Boundary & Signature Verification
* **Architecture:** External provider webhooks hit an API / Edge Function layer first, where cryptographic signatures (`Stripe-Signature` / `X-Razorpay-Signature`) are verified against the provider secret.
* **Database Trust Boundary:** The API layer invokes `public.process_verified_webhook(...)` using the database `service_role`.
* **Parameter Integrity Validation:** The database does **NOT** blindly trust payload parameters. In `process_verified_webhook`:
  ```sql
  -- Authoritative amount extraction
  v_provider_amount := (p_payload->'data'->'object'->>'amount')::NUMERIC / 100.0;
  v_provider_order_id := p_payload->'data'->'object'->>'id';

  -- Strict 3-way binding check
  IF v_provider_amount != v_intent.amount 
     OR v_intent.amount != v_payment.amount 
     OR (v_provider_order_id IS NOT NULL AND v_provider_order_id != v_intent.provider_order_id) 
  THEN
      PERFORM public.fn_transition_payment_intent_state(p_intent_id, 'failed');
      RETURN FALSE;
  END IF;
  ```
* **Evidence (Test Assertion 8 & 9):** In `verify_slice14.sql`, passing a payload with `amount = 500.00` for an intent of `1000.00` causes `process_verified_webhook` to return `FALSE` and transition the intent to `failed` without creating any ledger entries or receipts.

---

### 2.2 Security Definer & Privilege Isolation Model
* **Function Ownership:** All `SECURITY DEFINER` functions (`_internal_settle_payment`, `process_verified_webhook`, `fn_verify_payment_with_allocation`, `fn_transition_payment_intent_state`) are created under `postgres` (database owner) with `SET search_path = public, pg_temp` to prevent search_path hijacking attacks.
* **Public Privilege Revocation:**
  ```sql
  REVOKE ALL ON FUNCTION public._internal_settle_payment(UUID, JSONB, UUID) FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.process_verified_webhook(VARCHAR, VARCHAR, VARCHAR, JSONB, UUID) FROM PUBLIC;
  GRANT EXECUTE ON FUNCTION public.process_verified_webhook(VARCHAR, VARCHAR, VARCHAR, JSONB, UUID) TO service_role;
  ```
* **Catalog Evidence (Test Assertion 6 & 7):**
  * `has_function_privilege('authenticated', 'public._internal_settle_payment(uuid, jsonb, uuid)', 'EXECUTE')` yields `FALSE`.
  * Attempting to call `process_verified_webhook` as `authenticated` throws SQLSTATE `42501` (`insufficient_privilege`).

---

### 2.3 Row Level Security (RLS) & Isolation
* **`payment_webhooks` Table:** RLS enabled & forced (`FORCE ROW LEVEL SECURITY`).
  * `pol_payment_webhooks_select_admin`: Only users with `public.is_admin()` can SELECT.
  * `pol_payment_webhooks_no_insert / no_update / no_delete`: `USING (false)` / `WITH CHECK (false)`. Direct mutations by client connections are completely prohibited.
* **`payment_intents` Table:** RLS enabled & forced (`FORCE ROW LEVEL SECURITY`).
  * `pol_payment_intents_select_admin`: `public.is_admin() AND society_id = public.get_user_society_id(auth.uid())`.
  * `pol_payment_intents_select_resident`: `user_id = auth.uid()`.
  * `pol_payment_intents_insert_resident`: Allowed only for `status = 'created'`, `user_id = auth.uid()`, and `society_id = public.get_user_society_id(auth.uid())`.
  * `pol_payment_intents_no_update / no_delete`: `USING (false)` / `WITH CHECK (false)`.
* **Evidence (Test Assertion 2 & 3):**
  * Resident B querying Resident A's intent ID returns `COUNT = 0`.
  * Cross-society query returns `COUNT = 0`.

---

### 2.4 State Machine & Trigger Protection
* **Protected Transition helper:** `fn_transition_payment_intent_state(p_intent_id, p_new_status)` sets a transaction-local GUC variable: `PERFORM set_config('app.intent_transition', p_intent_id::text, true);`.
* **Trigger Enforcer:** `trg_intent_status_block` checks `current_setting('app.intent_transition', true)`. Any direct `UPDATE payment_intents SET status = ...` without calling the transition function raises `'Direct status updates blocked. Use fn_transition_payment_intent_state'`.
* **Evidence (Test Assertion 4 & 5):** Direct UPDATE attempt fails with trigger error; invalid transition (e.g. `failed` → `settled`) is rejected by the state machine.

---

### 2.5 Webhook Ledger Immutability & Idempotency
* **Append-Only Ledger:** `payment_webhooks` table stores incoming webhooks. `trg_payment_webhooks_immutable` raises `'payment_webhooks is an immutable append-only ledger'` on any UPDATE or DELETE attempt.
* **Idempotency Enforcement:** `UNIQUE(provider, provider_event_id)` constraint prevents duplicate event records. Duplicate event retries return `TRUE` without re-running settlement logic.
* **Conflicting Duplicate Detection:** If a duplicate event arrives with a mismatched payload, `process_verified_webhook` detects the discrepancy and raises `'Conflicting webhook payload for duplicate event'`.
* **Evidence (Test Assertion 10, 11, 20):**
  * Duplicate identical event retry returns `TRUE` with receipt count remaining strictly 1.
  * Duplicate event with altered payload raises conflict error.
  * Direct UPDATE to `payment_webhooks` raises immutability error.

---

### 2.6 Financial Atomicity, Audit & Notifications
* **Slice 5 Semantic Preservation:** `_internal_settle_payment` performs:
  1. Row lock on `payments` and `maintenance_charges` (`FOR UPDATE`).
  2. Active owner/tenant relationship check (`property_owners` / `tenancies`).
  3. Outstanding charge balance boundary validation.
  4. Member subsidiary ledger credit + advance payment credit.
  5. Society cash/bank ledger debit (`scope = 'society'`, `direction = 'debit'`).
  6. Receipt creation (`receipts` table).
  7. Payment status update (`verified`).
  8. Notification dispatch to payer.
  9. Audit log entry.
* **System Actor Audit Integrity:** For webhook actions, `p_authorized_by` is `NULL`. `verified_by` on `payments` and `actor_id` on `audit_logs` are set to `NULL` (representing System action), preventing payer or admin impersonation.
* **Evidence (Test Assertion 13, 14, 15, 16, 17, 18, 25, 26):**
  * `verified_by IS NULL` and `audit_logs.actor_id IS NULL`.
  * Ledger credits, society debit, receipt, and notification count are all strictly `COUNT = 1`.
  * Unassociated payer payment settlement is rejected with `'Payer has no active ownership or tenancy connection'`.
  * Invalid multi-charge settlement fails atomically with 0 partial allocations or receipts committed.

---

## 3. SECURITY MATRIX SUMMARY

| Requirement | Implementation Mechanism | Security Verification | Status |
|---|---|---|---|
| Non-PUBLIC Internal Helper | `REVOKE ALL ON _internal_settle_payment FROM PUBLIC` | Catalog check (`has_function_privilege` = FALSE) | **VERIFIED PASS** |
| Webhook Role Isolation | `GRANT EXECUTE ON process_verified_webhook TO service_role` | `authenticated` call yields `42501` | **VERIFIED PASS** |
| Webhook Immutability | `trg_payment_webhooks_immutable` BEFORE UPDATE/DELETE | UPDATE attempt raises error | **VERIFIED PASS** |
| Webhook Idempotency | `UNIQUE(provider, provider_event_id)` + transaction locks | Duplicate retries yield 0 extra side effects | **VERIFIED PASS** |
| Payload Amount Binding | 3-way check (`payload.amount == intent.amount == payment.amount`) | Mismatched payload sets intent to `failed` | **VERIFIED PASS** |
| RLS Isolation | `ENABLE ROW LEVEL SECURITY` + `FORCE ROW LEVEL SECURITY` | Resident A cannot view Resident B intents | **VERIFIED PASS** |
| State Machine Shield | `app.intent_transition` session GUC + trigger | Direct SQL update blocked | **VERIFIED PASS** |
| Slice 5 Financial Rules | Active user check, charge lock, ledger credit/debit, receipt | All financial side-effects = 1, atomicity proven | **VERIFIED PASS** |
