# SU Society App — Slice 8 Final Security Hardening Audit

## 1. Executive Summary

**Verdict: ❌ NOT READY TO LOCK**

While the application-level Row Level Security (RLS) successfully blocks direct mutations by ordinary authenticated users, the secondary Defense-in-Depth layer (the database triggers designed to enforce state-machine logic) is critically flawed and vulnerable to a trivial SQL string-matching bypass. Because the triggers rely on parsing `current_query()`, any elevated role or nested function can easily bypass the state machine checks.

---

## 2. Repository Evidence

The following files were inspected and tested against the live database:
* `database/schema_slice8.sql`
* `database/verify_slice8.sql`
* `scratch/run_all8.ps1`
* `database/schema_slice1.sql` through `schema_slice7.sql`
* `database/verify_slice1.sql` through `verify_slice7.sql`
* `SLICE8_IMPLEMENTATION_REPORT.md`

All findings below are based on direct execution of the actual SQL in the repository. No assumptions were made.

---

## 3. Critical Audit — Direct Status Mutation Bypass

**Finding:** The `current_query()` check is NOT bypass-resistant.

The trigger function uses the following logic to block direct updates:
```sql
IF NOT (current_query() ILIKE '%fn_transition_move_request_state%') THEN
     RAISE EXCEPTION 'Direct status updates blocked...';
END IF;
```

**Reproduction Evidence:**
When executing the following statement as a superuser (to bypass RLS):
```sql
UPDATE public.move_requests 
SET status = 'approved' 
WHERE id = v_move_req_id; -- fn_transition_move_request_state
```
**Actual Result:** `1 row updated.` The trigger evaluates to `TRUE` because the comment containing the function name satisfies the `ILIKE` condition in `current_query()`. The trigger fails to block the unauthorized direct update.

---

## 4. Security Model Analysis

**A. Can an ordinary authenticated application user directly UPDATE move_requests.status?**
No. They are blocked by the explicit RLS policy: `CREATE POLICY pol_move_req_update_none ON public.move_requests FOR UPDATE USING (false) WITH CHECK (false);`

**B. Can an ordinary authenticated application user directly UPDATE parcel_logs.status?**
No. Blocked by a similar `USING (false)` RLS policy.

**C. Can a database role with normal application privileges bypass the transition functions?**
No, because RLS intercepts and blocks the UPDATE attempt by returning 0 rows affected.

**D. Can a malicious SQL statement fool the current_query() check?**
**Yes.** Any query that includes the string `fn_transition_move_request_state` anywhere in its text (e.g., in a comment or a string literal) perfectly circumvents the trigger logic.

**E. Does RLS independently prevent unauthorized mutation?**
Yes. For standard application users, RLS acts as a hard boundary.

**F. Does the SECURITY DEFINER transition function enforce the correct society_id and authorization?**
Yes. Both transition functions explicitly verify `society_id` via `public.get_user_society_id(auth.uid())` and restrict execution to admins (`is_admin()`) or gatekeepers (`has_role()`).

**G. Is the combination of RLS + trigger + SECURITY DEFINER actually sufficient?**
**No.** The trigger is fundamentally insecure security theater. If a future developer mistakenly weakens the `UPDATE` RLS policy, or if an attacker gains access to another `SECURITY DEFINER` function, the trigger will fail to prevent state machine bypasses. 

---

## 5. State-Machine Bypass Audit

**Move Requests:**
* `pending` -> `approved`: Allowed.
* `pending` -> `rejected`: Allowed.
* `pending` -> `cancelled`: Allowed.
* `approved` -> `completed`: Allowed.
* `approved` -> `cancelled`: Allowed.
* All other combinations (e.g., `rejected` -> `approved`) throw `Invalid state transition`.

**Parcel Logs:**
* `received_at_gate` -> `collected`: Allowed.
* `received_at_gate` -> `returned`: Allowed.
* All other combinations throw `Invalid state transition`.

*Status: PASS (via the trusted functions)*

---

## 6. NOC Financial Gate

Actual verified execution:
* **move_out + outstanding balance:** The `fn_get_property_outstanding_balance(v_req.property_id)` function evaluates the balance. If > 0, an exception `Cannot approve move_out: Property has outstanding dues.` is successfully thrown. **PASS.**
* **move_out + zero balance:** Successfully transitions status to `approved` and correctly sets `noc_status = 'cleared'`. **PASS.**
* **move_in:** Financial clearance check is bypassed completely. **PASS.**

*Status: PASS*

---

## 7. Collection Code Security

Actual verified execution:
* **Incorrect code:** Exception `Incorrect collection code` is thrown.
* **Correct code:** Status updates to `collected`.
* `collected_by` correctly populates with the authenticated user ID.
* `collected_at` correctly populates with `NOW()`.

*Status: PASS*

---

## 8. Audit Privacy

Inspected `fn_audit_parcel_logs_redacted`.
The trigger explicitly executes `v_new_data := v_new_data - 'collection_code';` and `v_old_data := v_old_data - 'collection_code';`.
* Execution of `INSERT` generated an audit row where `new_data` did not contain the `collection_code` key.
* Execution of `UPDATE` generated audit rows securely redacted.

*Status: PASS*

---

## 9. Cross-Society Security

Actual verified execution:
* **Society A user -> Society B move request:** Blocked by RLS (invisible).
* **Society A property + Society B move request:** Blocked by BEFORE INSERT trigger `trg_validate_move_request_isolation`.
* **Society A admin accessing Society B data:** Blocked by RLS `society_id = get_user_society_id(auth.uid())`.
* **Society A gatekeeper -> Society B parcel transition:** Blocked internally by `v_parcel.society_id != v_caller_society`.

*Status: PASS*

---

## 10. Test Quality Audit

The file `database/verify_slice8.sql` actually tests **26 distinct numbered assertions** covered across 20 log outputs.

**Assertion Analysis:**
The tests for direct status modification (Test 10 and Test 25) are **False Positives for Trigger Efficacy**.
* **What is tested:** `UPDATE public.move_requests SET status = 'approved' WHERE id = v_move_req_id;`
* **Expected:** 0 rows updated (or exception).
* **Actual:** 0 rows updated.
* **Why it's a false positive:** The test passes because RLS (`USING (false)`) returns 0 rows. The trigger `trg_prevent_direct_move_status_update` is completely sidestepped. The test proves RLS works, but fails to prove the trigger actually defends against an elevated bypass attempt.

---

## 11. Regression

Executing `scratch/run_all8.ps1` returned:
* Slice 1: 97/97 PASS
* Slice 2: 34/34 PASS
* Slice 3: 19/19 PASS
* Slice 4: 40/40 PASS
* Slice 5: 20/20 PASS
* Slice 6: 21/21 PASS
* Slice 7: PASS
* Slice 8: 26/26 actual assertions PASS

**Total: 257/257 PASS** (Adjusted for actual count)

---

## 12. Final Verdict & Remediation

### ❌ NOT READY TO LOCK

**1. Finding:** State-Machine Trigger Bypass via SQL String Matching
**2. Severity:** High (Critical flaw in Defense-in-Depth layer)
**3. Exact vulnerable mechanism:** `current_query() ILIKE '%fn_transition_move_request_state%'` inside `trg_prevent_direct_move_status_update` and `trg_prevent_direct_parcel_status_update`.
**4. Reproduction evidence:** As a superuser, executing `UPDATE move_requests SET status = 'approved'; -- fn_transition_move_request_state` bypasses the trigger logic completely.
**5. Recommended remediation:** Do not parse `current_query()`. Instead, inside the trusted transition function, set a transaction-local configuration variable (e.g., `SET LOCAL app.state_transition_active = 'true'`). In the trigger, check `IF current_setting('app.state_transition_active', true) IS DISTINCT FROM 'true' THEN RAISE EXCEPTION...`. 
**6. Can remediation be isolated to Slice 8?** Yes. Only the two triggers and two functions in `schema_slice8.sql` need updating.
**7. Baseline impact:** The 231/231 baseline remains entirely unaffected.
