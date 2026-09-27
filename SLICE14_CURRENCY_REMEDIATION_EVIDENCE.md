# SLICE 14 — CURRENCY INTEGRITY REMEDIATION EVIDENCE REPORT

**Status:** PASS — CURRENCY INTEGRITY REMEDIATION COMPLETE  
**Execution Timestamp:** 2026-09-03T01:33:00Z  
**Target:** Payment Gateway Currency Binding (`database/schema_slice14.sql`, `database/verify_slice14.sql`)

---

## 1. Existing Currency Model Inspection

* **Slices 1–13 Audit:** Inspection of locked database schemas confirmed that financial amounts (`payments.amount`, `maintenance_charges.amount`, `ledger_transactions.amount`) are stored as `NUMERIC(15,2)`. No explicit `currency` column existed in locked Slices 1–13.
* **Slice 14 Addition:** In `schema_slice14.sql`, authoritative ISO 4217 currency columns were added to support gateway integrations:
  - `payment_intents.currency VARCHAR(10) NOT NULL DEFAULT 'INR'`
  - `payments.currency VARCHAR(10) DEFAULT 'INR'` (via non-breaking `ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS currency VARCHAR(10) DEFAULT 'INR'`)

---

## 2. Authoritative Currency Source

The authoritative currency string for a payment flow is established during payment intent creation:
* `payment_intents.currency` stores the requested billing currency.
* `payments.currency` stores the underlying payment record currency.
* Gateway webhooks must match BOTH internal columns.

---

## 3. Provider Currency Extraction

In `process_verified_webhook()`, the provider's currency code is extracted directly from the verified JSON payload:

* **Stripe Payload:** `v_provider_currency := UPPER(TRIM(p_payload->'data'->'object'->>'currency'));`
* **Razorpay Payload:** `v_provider_currency := UPPER(TRIM(p_payload->'payload'->'payment'->'entity'->>'currency'));`

---

## 4. Currency Normalization Rules

* All currency codes are normalized using `UPPER(TRIM(...))`.
* Case variations (e.g. `'inr'`, `'InR'`, `'INR'`) normalize deterministically to `'INR'`.
* Empty strings (`''`) or whitespace-only strings evaluate to invalid.

---

## 5. Currency Comparison Logic

Strict binding validation executes inside `process_verified_webhook()` **before** financial settlement:

```sql
    v_intent_currency := UPPER(TRIM(v_intent.currency));
    v_payment_currency := UPPER(TRIM(v_payment.currency));

    -- Strict Currency Binding Check:
    IF v_provider_currency IS NULL OR v_provider_currency = '' OR
       v_intent_currency IS NULL OR v_intent_currency = '' OR
       v_payment_currency IS NULL OR v_payment_currency = '' OR
       v_provider_currency != v_intent_currency OR
       v_intent_currency != v_payment_currency THEN
        PERFORM public.fn_transition_payment_intent_state(p_intent_id, 'failed');
        RETURN FALSE;
    END IF;
```

---

## 6. USD-vs-INR Adversarial Result (Assertion 28)

* **Test Setup:** Internal intent and payment configured for `INR`. Webhook payload delivers `amount = 100000` ($1,000.00) in `USD`.
* **Execution Result:** `process_verified_webhook()` detects `USD != INR`, transitions intent state to `'failed'`, and returns `FALSE`.
* **Empirical DB Evidence:**
  - `payment_intents.status` = `'failed'`
  - `payments.status` = `'pending_verification'` (unverified)
  - `ledger_transactions` count = 0
  - `receipts` count = 0
  - `notifications` count = 0

---

## 7. Missing-Currency Result (Assertion 29)

* **Test Setup:** Webhook payload delivers correct amount (`100000`) but omits the `currency` field (`p_payload` currency is `NULL`).
* **Execution Result:** `v_provider_currency IS NULL` condition triggers immediate rejection.
* **Empirical DB Evidence:** Intent status set to `'failed'`, `process_verified_webhook` returns `FALSE`, zero financial side-effects committed.

---

## 8. Internal Currency Mismatch Result (Assertion 30)

* **Test Setup:** `payment_intents.currency` set to `'INR'`, but `payments.currency` set to `'USD'`. Provider sends `'INR'`.
* **Execution Result:** `v_intent_currency != v_payment_currency` condition triggers rejection.
* **Empirical DB Evidence:** Settlement aborted, zero side-effects.

---

## 9. Atomicity Evidence

All currency validations occur prior to invoking `_internal_settle_payment()`. If a currency rejection occurs:
* `payment_allocations` count = 0
* `ledger_transactions` count = 0
* `receipts` count = 0
* `notifications` count = 0
* Payment status remains `pending_verification`

---

## 10. Regression Result

Executing master pipeline runner `scratch/run_all14.ps1`:

```text
=========================================
PHASE A: Executing Slice 1-13 Regression Pipeline
=========================================
Locked Baseline: 341/341 PASS
Slice 13 Verification Completed Successfully.

=========================================
PHASE B: Executing Slice 14 Schema
=========================================
COMMIT

=========================================
PHASE C: Executing Slice 14 Verification
=========================================
NOTICE:  ==================================================
NOTICE:  STARTING SLICE 14 VERIFICATION (PAYMENT WEBHOOKS)
NOTICE:  ==================================================
NOTICE:  PASS: 1. Payment intent creation successful
NOTICE:  PASS: 2. Intent RLS user isolation strictly enforced
NOTICE:  PASS: 3. Intent RLS society isolation strictly enforced
NOTICE:  PASS: 4. Direct status update correctly blocked by trigger
NOTICE:  PASS: 5. Invalid state transition correctly rejected
NOTICE:  PASS: 6. _internal_settle_payment non-PUBLIC privilege catalog check verified
NOTICE:  PASS: 7. process_verified_webhook restricted from authenticated users
NOTICE:  PASS: 8. Amount mismatch correctly rejected by process_verified_webhook
NOTICE:  PASS: 9. Payment intent transitioned to failed status on amount mismatch
NOTICE:  PASS: 10. Duplicate webhook retry handled idempotently without error
NOTICE:  PASS: 11. Conflicting duplicate webhook payload correctly rejected
NOTICE:  PASS: 12. Valid webhook settlement execution completed successfully
NOTICE:  PASS: 13. Exactly one payment verified with SYSTEM actor (verified_by IS NULL)
NOTICE:  PASS: 14. Exactly one property subsidiary ledger credit verified (Amount: 2000.00)
NOTICE:  PASS: 15. Exactly one society cash/bank ledger debit verified (Amount: 2000.00)
NOTICE:  PASS: 16. Exactly one receipt generated for settlement
NOTICE:  PASS: 17. Exactly one notification delivered to payer
NOTICE:  PASS: 18. Audit trail correctly logged with SYSTEM actor (actor_id IS NULL)
NOTICE:  PASS: 19. Webhook retry on settled intent returned success idempotently without duplicate receipt
NOTICE:  PASS: 20. payment_webhooks UPDATE correctly blocked by immutability trigger
NOTICE:  PASS: 21. Admin isolation enforced on fn_verify_payment_with_allocation
NOTICE:  PASS: 22. Allocation boundary check (charge balance limit) verified
NOTICE:  PASS: 23. Non-positive allocation amount correctly rejected
NOTICE:  PASS: 24. Cross-society charge allocation correctly blocked
NOTICE:  PASS: 25. Payer active relationship check strictly enforced
NOTICE:  PASS: 26. Financial atomicity verified (zero side effects committed on failure)
NOTICE:  PASS: 27. Valid INR currency settlement completed successfully with receipt
NOTICE:  PASS: 28. USD currency mismatch correctly rejected (intent failed, 0 side-effects)
NOTICE:  PASS: 29. Missing provider currency correctly rejected with intent failed
NOTICE:  PASS: 30. Internal intent vs payment currency mismatch correctly rejected
NOTICE:  PASS: 31. Case-normalized currency matching (inr vs InR vs INR) verified
NOTICE:  ==================================================
NOTICE:  SLICE 14 VERIFICATION COMPLETE (31/31 TESTS PASSED)
NOTICE:  ==================================================

=========================================
PHASE D: Final Report
=========================================
Locked Baseline: 341/341 PASS
Slice 14 Assertions: 31/31 PASS
Combined Result: 372/372 PASS
Slice 14 Verification Completed Successfully.
```

---

## 11. Files Modified

* [database/schema_slice14.sql](file:///d:/Clients%20Applications/SU%20Society%20App/database/schema_slice14.sql) — Added currency column & strict currency validation logic
* [database/verify_slice14.sql](file:///d:/Clients%20Applications/SU%20Society%20App/database/verify_slice14.sql) — Added assertions 27–31 for currency integrity testing

---

## 12. Locked Baseline Integrity Confirmation

* **Slices 1–13 files:** 100% Unmodified.
* **`scratch/run_all13.ps1`:** Unmodified (**341/341 PASS**).

---

## FINAL VERDICT

`READY FOR INDEPENDENT REVIEW`
