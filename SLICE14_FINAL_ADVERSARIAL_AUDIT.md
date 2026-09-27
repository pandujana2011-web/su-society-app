# SLICE 14 — FINAL ADVERSARIAL SECURITY AUDIT REPORT

**Audit Date:** September 3, 2026  
**Auditor:** Independent Adversarial Security Auditor  
**Target:** Automated Payment Gateway Integration & Webhook Settlement Engine (`database/schema_slice14.sql`, `database/verify_slice14.sql`, `scratch/run_all14.ps1`)  
**Final Verdict:** `NOT READY FOR INDEPENDENT REVIEW`

---

## 1. Executive Verdict

A comprehensive, source-level adversarial audit was performed against the Slice 14 implementation. While major security controls—such as SECURITY DEFINER privilege isolation, system-level audit attribution (`actor_id = NULL`), direct status update blocking via RLS, immutable webhook event ledgering, and Slice 5 double-entry financial settlement semantics—were successfully implemented and verified, **one critical design gap remains unresolved**:

* **Critical Finding (Currency Integrity):** The `process_verified_webhook` implementation validates dollar/rupee numerical amounts, but does NOT extract or validate currency codes (e.g., `USD` vs `INR`), nor does `payment_intents` or `payments` store an authoritative currency code column.

Per audit rules, because explicit currency validation is absent in the schema and webhook parser, the implementation is categorized as **`NOT READY FOR INDEPENDENT REVIEW`** pending currency remediation.

---

## 2. Critical Findings & Analysis

### Finding 1 (CRITICAL — Currency Code Validation Missing):
* **Vulnerability Description:** `process_verified_webhook` converts raw currency units (cents/paise) to decimal (`amount / 100.0`) and compares `v_provider_amount == intent.amount`, but fails to inspect the `currency` string in the webhook payload (e.g. `p_payload->'data'->'object'->>'currency'`). An attacker or gateway misconfiguration delivering a payment in USD ($1,000 = $1,000.00) could settle an intent created in INR (₹1,000 = ₹1,000.00), leading to severe financial exchange rate discrepancy.
* **Proposed Remediation:**
  1. Add `currency VARCHAR(3) NOT NULL DEFAULT 'INR'` column to `public.payments` and `public.payment_intents`.
  2. In `process_verified_webhook()`, extract `v_provider_currency := LOWER(p_payload->'data'->'object'->>'currency')` and enforce `v_provider_currency = LOWER(v_intent.currency)`.
  3. If currency mismatches, fail the intent transition and abort settlement.

### Finding 2 (PASSED — GUC Spoofing & State Machine Bypass):
* **Audit Test:** Adversarial script attempted setting `PERFORM set_config('app.intent_transition', '<intent-id>', true)` under the `authenticated` role and running `UPDATE public.payment_intents SET status = 'settled'`.
* **Result:** **PASSED.** The UPDATE query was rejected with `permission denied for table payment_intents`. This is because RLS policy `pol_payment_intents_no_update` enforces `FOR UPDATE USING (false)`, blocking client-initiated updates regardless of session GUC configuration.

---

## 3. State-Machine Spoofing Result

* **Direct Client UPDATE:** Blocked by RLS (`pol_payment_intents_no_update USING (false)`).
* **Spoofed GUC Setting:** Ineffective for client roles (`authenticated`, `anon`).
* **Transition Function (`fn_transition_payment_intent_state`):** Locks `payment_intents` row (`FOR UPDATE`), checks state transition domain rules (`created -> processing -> succeeded -> settled`), and manages session context safely.

---

## 4. Currency Integrity Result

* **Numerical Amount Check:** Verified (`provider_amount == intent.amount == payment.amount`).
* **Order ID Binding:** Verified (`provider_order_id == intent.provider_order_id`).
* **Currency Code Check:** **FAILED (MISSING).** Webhook payload currency parameter (e.g., `'inr'`, `'usd'`) is not extracted or validated against internal payment records.

---

## 5. Concurrency Results

1. **Same Webhook Twice Concurrently:** Database row lock `FOR UPDATE` on `payment_intents` and `payment_webhooks` unique constraint `(provider, provider_event_id)` serialize execution. Exactly 1 settlement executes; the second call hits duplicate handling and returns `TRUE` idempotently without duplicate ledger entries or receipts.
2. **Different Webhooks for Same Intent Concurrently:** `FOR UPDATE` row lock on `payment_intents` forces second transaction to wait. Once first transaction sets status to `settled`, second transaction sees `v_intent.status = 'settled'` and returns `TRUE` without re-settling.
3. **Webhook vs Admin Verification Concurrently:** Row lock on `payments` (`FOR UPDATE`) in `_internal_settle_payment` serializes verification. First commit updates payment status to `verified`. Second attempt fails validation `status != 'pending_verification'` and aborts cleanly.
4. **Retry After Failure:** If a settlement transaction fails mid-execution, PostgreSQL rolls back the entire transaction (including `payment_webhooks` insertion). The database contains zero partial side-effects, allowing clean retry.

---

## 6. Webhook Failure / Idempotency Analysis

1. **Is webhook insertion in the same transaction as settlement?** YES. `process_verified_webhook` executes inside a single database transaction.
2. **If settlement rolls back, does the webhook event also roll back?** YES. Atomic PostgreSQL transaction rollback reverts `INSERT INTO payment_webhooks`.
3. **If the event remains, how does a retry know settlement did not complete?** Since the transaction rolls back, no webhook record remains. The retry executes from a clean state.
4. **Can an event become permanently recorded as "already processed" while settlement failed?** NO. Rollback prevents orphan webhook ledger records.

---

## 7. SECURITY DEFINER Forensic Audit

Catalog evidence from `pg_proc` and `information_schema.routine_privileges`:

```text
           routine_name            |   grantee    | privilege_type 
-----------------------------------+--------------+----------------
 _internal_settle_payment          | postgres     | EXECUTE
 fn_verify_payment_with_allocation | PUBLIC       | EXECUTE
 fn_verify_payment_with_allocation | postgres     | EXECUTE
 process_verified_webhook          | postgres     | EXECUTE
 process_verified_webhook          | service_role | EXECUTE
```

* **`_internal_settle_payment`**: `prosecdef = true`, `search_path = public, pg_temp`, Owner `postgres`. Execution REVOKED from `PUBLIC`, `anon`, `authenticated`, `service_role`.
* **`process_verified_webhook`**: `prosecdef = true`, `search_path = public, pg_temp`, Owner `postgres`. Execution GRANTED exclusively to `service_role` and `postgres`.
* **`fn_verify_payment_with_allocation`**: `prosecdef = true`, `search_path = public, pg_temp`, Owner `postgres`. Internal guard enforces `is_admin()`.

---

## 8. RLS Adversarial Evidence

* **`payment_intents` RLS:** `FORCE ROW LEVEL SECURITY`.
  - Resident SELECT: Filtered by `user_id = auth.uid()`.
  - Admin SELECT: Filtered by `is_admin() AND society_id = get_user_society_id(auth.uid())`.
  - Resident INSERT: Restricted to `user_id = auth.uid() AND status = 'created'`.
  - Client UPDATE/DELETE: Blocked by policy `USING (false)`.
* **`payment_webhooks` RLS:** `FORCE ROW LEVEL SECURITY`.
  - Admin SELECT: Filtered by `is_admin()`.
  - Client INSERT/UPDATE/DELETE: Blocked by policy `USING (false)` / `WITH CHECK (false)`.

---

## 9. Slice 5 Financial Compatibility Evidence

Line-by-line comparison with `schema_slice5.sql`:
* **Row Locking:** `FOR UPDATE` on `payments` and `maintenance_charges` (schema_slice14.sql L127, L160).
* **Active Relationship:** Payer ownership or tenancy verified on property (schema_slice14.sql L138-150).
* **Advance Payments:** Unallocated payment remainder (`payment.amount > allocated_sum`) credited to property subsidiary ledger as advance payment (schema_slice14.sql L197-206). Matches Slice 5 semantics 100%.
* **Dual Ledger Posting:** Property subsidiary credit for allocations/advance, Society cash/bank debit for total payment amount.
* **Receipt & Audit:** Receipt generated with `REC-YYYYMMDD-XXXXXX` format. Audit log created.

---

## 10. Financial Cardinality Evidence

Single successful settlement produces:
* Exactly 1 payment status update (`verified`)
* Exactly 1 member property ledger credit
* Exactly 1 society cash/bank ledger debit
* Exactly 1 receipt record
* Exactly 1 notification record
* Exactly 1 audit log record (`actor_id = NULL` for webhooks)

---

## 11. Financial Atomicity Evidence

Assertion 26 in `verify_slice14.sql` tests a settlement allocating to an invalid cross-society charge. The exception causes complete transaction rollback: `payment_allocations` count = 0, `receipts` count = 0, zero partial state committed.

---

## 12. 26-Assertion Anti-Fraud Mapping

| Assertion # | Category Description | Verified SQL Implementation |
|---|---|---|
| 1 | Intent Creation | Intent inserted under member role |
| 2 | Intent RLS User Isolation | Member 2 cannot view Member 1 intent |
| 3 | Intent RLS Society Isolation | Member 2 cannot view Society 1 intent |
| 4 | Direct Status Update Block | Client UPDATE rejected by RLS |
| 5 | Invalid State Transition | Invalid status value rejected |
| 6 | Internal Helper Security | `_internal_settle_payment` non-PUBLIC catalog check |
| 7 | Webhook Role Restriction | `process_verified_webhook` blocked for `authenticated` |
| 8 | Amount Mismatch Rejection | Mismatched provider amount rejected |
| 9 | Failed State on Mismatch | Intent status transitions to `failed` |
| 10 | Duplicate Webhook Idempotency | Retried webhook returns `TRUE` cleanly |
| 11 | Conflicting Duplicate Protection | Conflicting payload duplicate rejected |
| 12 | Valid Webhook Settlement | Settlement returns `TRUE` |
| 13 | Payment Verified State | Payment status = `verified`, `verified_by IS NULL` |
| 14 | Property Ledger Credit | Exactly 1 credit matching payment amount |
| 15 | Society Ledger Debit | Exactly 1 debit matching payment amount |
| 16 | Receipt Generation | Exactly 1 receipt created |
| 17 | Notification Fan-Out | Exactly 1 notification sent to payer |
| 18 | SYSTEM Audit Actor | Audit log has `actor_id IS NULL` |
| 19 | Webhook Retry Idempotency | Retry does not produce duplicate receipt |
| 20 | Webhook Immutability | UPDATE on `payment_webhooks` blocked |
| 21 | Admin Wrapper Isolation | Member blocked from calling admin wrapper |
| 22 | Allocation Balance Boundary | Over-allocation exceeding charge balance rejected |
| 23 | Non-Positive Allocation | Negative allocation rejected |
| 24 | Cross-Society Allocation | Allocation to charge in another society blocked |
| 25 | Active Payer Relationship | Unassociated user payment rejected |
| 26 | Financial Atomicity | Multi-charge failure rolls back 100% of side effects |

*Anti-Fraud Audit:* Zero hard-coded assertion counters (`v_assertions_passed := 26`) exist in `verify_slice14.sql`. All increments are dynamically executed upon successful SQL assertion checks.

---

## 13. Runner Audit

* **`scratch/run_all14.ps1`**: Dynamically executes `scratch/run_all13.ps1`, applies `schema_slice14.sql`, executes `verify_slice14.sql`, and parses pass counts dynamically using regex (`SLICE 14 VERIFICATION COMPLETE \((\d+)/(\d+) TESTS PASS`). No hard-coded proof values are used.
* **`scratch/run_all13.ps1`**: Intact and unmodified (**341/341 PASS** baseline preserved).

---

## 14. Secret Scan

* **Scan Result:** CLEAN. No real Stripe/Razorpay private keys, webhook signing secrets, database credentials, or JWT secrets exist in `schema_slice14.sql`, `verify_slice14.sql`, or `run_all14.ps1`. Test fixtures use mock strings (`order_stripe_...`, `evt_valid_...`).

---

## 15. Locked Baseline Integrity

* **Locked Slices 1–13 Files:** 100% Unmodified.
* **Locked Baseline Regression:** 341/341 PASS.

---

## Final Verdict

**NOT READY FOR INDEPENDENT REVIEW**  
*(Reason: Currency code validation `USD` vs `INR` is missing in `process_verified_webhook` payload parsing and schema definition).*
