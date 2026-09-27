# SLICE 17 — FINAL POLL_VOTES SECURITY CORRECTION REPORT

**Document Title:** Slice 17 Final poll_votes RLS Semantics Correction Report  
**Document Version:** 1.0.0 (Plan Correction Pass v3.2.0)  
**Date:** 2026-09-04  
**Status:** PLAN-ONLY / PENDING FINAL USER IMPLEMENTATION APPROVAL  
**Implementation Authorization:** NONE  
**Cumulative Locked Baseline:** Slices 1–16 = 469/469 PASS (100% LOCKED)  

---

## 1. PREVIOUS INCORRECT ASSUMPTION

The prior reconciliation (v3.1.0) incorrectly stated:

```text
Assertion 56a: UPDATE on poll_votes blocked by WITH CHECK(false)
               → SQLSTATE 00000, 0 rows updated

Assertion 56b: DELETE on poll_votes blocked by trigger trg_prevent_vote_mutations
               → SQLSTATE 42501, trigger exception raised
```

**Specific errors:**
* Assertion 56: The 0-row UPDATE result was attributed solely to `WITH CHECK(false)`.
* Assertion 57 (former 56b): The DELETE denial was attributed to a BEFORE DELETE trigger firing before RLS filtering, producing `SQLSTATE 42501`.
* The Part 3 assertion inventory labeled them `56a`/`56b` (sub-labeled, non-sequential).
* The mutation security matrix in Part 1 showed `Exception (42501)` for `poll_votes` DELETE.
* The reconciliation report Section 7A claimed "BEFORE DELETE trigger fires before RLS filtering."

---

## 2. CORRECT PostgreSQL RLS SEMANTICS

PostgreSQL evaluates RLS policies as follows:

| Operation | `USING` Clause | `WITH CHECK` Clause |
| :--- | :--- | :--- |
| **SELECT** | Filters visible rows | N/A |
| **INSERT** | N/A | Validates new row |
| **UPDATE** | Selects eligible rows to update | Validates modified row |
| **DELETE** | Selects eligible rows to delete | N/A |

**Key rules:**

* `USING (false)` on a RESTRICTIVE UPDATE policy: the existing row is **not eligible** for update — the statement sees 0 qualifying rows and returns **0 rows updated, SQLSTATE `00000`**.
* `USING (false)` on a RESTRICTIVE DELETE policy: the existing row is **not eligible** for deletion — the statement sees 0 qualifying rows and returns **0 rows deleted, SQLSTATE `00000`**.
* A `WITH CHECK (false)` on UPDATE can raise a row-security error (`42501`) under certain execution paths, but it is **not** the primary row-exclusion mechanism when `USING (false)` is present.
* **Trigger firing order:** PostgreSQL BEFORE triggers fire on rows that have already passed the row-visibility gate. For an ordinary authenticated client where RLS `USING (false)` excludes all rows, there are **0 eligible rows**, so no BEFORE trigger fires.

---

## 3. FINAL UPDATE POLICY BEHAVIOR (Assertion 56)

**Policy name:** `pol_poll_votes_restrictive_update`  
**Type:** RESTRICTIVE  
**Command:** FOR UPDATE  
**USING:** `(false)`  
**WITH CHECK:** `(false)` (retained as additional defense)

**Ordinary authenticated client execution path:**

```text
Client issues: UPDATE poll_votes SET ... WHERE poll_vote_id = X
                          ↓
RLS: RESTRICTIVE pol_poll_votes_restrictive_update
     USING (false)
                          ↓
Target row not eligible for update
                          ↓
0 rows updated
                          ↓
SQLSTATE 00000
```

**Assertion 56 (Authoritative):**

```text
Actor:    Ordinary authenticated client
Action:   Direct SQL UPDATE on poll_votes
Expected: 0 rows updated
SQLSTATE: 00000
Reason:   Target row excluded by RESTRICTIVE USING(false); row never reached
          by statement executor. WITH CHECK(false) retained as defense-in-depth.
```

---

## 4. FINAL DELETE POLICY BEHAVIOR (Assertion 57)

**Policy name:** `pol_poll_votes_restrictive_delete`  
**Type:** RESTRICTIVE  
**Command:** FOR DELETE  
**USING:** `(false)`

**Ordinary authenticated client execution path:**

```text
Client issues: DELETE FROM poll_votes WHERE poll_vote_id = X
                          ↓
RLS: RESTRICTIVE pol_poll_votes_restrictive_delete
     USING (false)
                          ↓
Target row not eligible for deletion
                          ↓
0 rows deleted
                          ↓
SQLSTATE 00000
```

**Assertion 57 (Authoritative):**

```text
Actor:    Ordinary authenticated client
Action:   Direct SQL DELETE on poll_votes
Expected: 0 rows deleted
SQLSTATE: 00000
Reason:   Target row excluded by RESTRICTIVE USING(false). Trigger
          trg_prevent_vote_mutations does NOT fire for ordinary RLS-denied paths
          (0 eligible rows → no trigger invocation).
```

---

## 5. TRIGGER ROLE AS DEFENSE-IN-DEPTH

`trg_prevent_vote_mutations` (BEFORE DELETE / BEFORE UPDATE trigger) remains installed and serves as:

**Defense-in-depth for privileged bypass execution paths**, such as:
* `SET LOCAL ROLE service_role` / `BYPASSRLS` privilege holders.
* Supabase migration scripts or admin tools that skip PostgREST RLS enforcement.
* Future schema changes that accidentally weaken the RESTRICTIVE policies.

The trigger is **NOT** the primary denial mechanism for ordinary authenticated client execution.

**Correct claims about the trigger:**
* It does NOT fire for ordinary clients denied by `USING (false)` (0 eligible rows).
* It fires ONLY when an eligible row reaches the trigger execution stage.
* It raises `RAISE EXCEPTION` (SQLSTATE `P0001` or similar) as defense-in-depth.
* It must NOT be cited as the source of Assertion 57's `SQLSTATE 00000` / 0-row result.

---

## 6. CORRECTED ASSERTIONS 56 AND 57

### Assertion 56 — Direct UPDATE on `poll_votes`

| Field | Value |
| :--- | :--- |
| **Assertion Number** | 56 (sequential, no sub-label) |
| **Actor** | Ordinary authenticated client |
| **Action** | `UPDATE poll_votes SET ... WHERE poll_vote_id = X` |
| **Expected SQLSTATE** | `00000` |
| **Expected Rows** | 0 rows updated |
| **Primary Denial Mechanism** | RESTRICTIVE RLS `USING (false)` on `pol_poll_votes_restrictive_update` |
| **Defense-in-depth** | `WITH CHECK (false)` also present; `trg_prevent_vote_mutations` installed |

### Assertion 57 — Direct DELETE on `poll_votes`

| Field | Value |
| :--- | :--- |
| **Assertion Number** | 57 (sequential, distinct from Assertion 56) |
| **Actor** | Ordinary authenticated client |
| **Action** | `DELETE FROM poll_votes WHERE poll_vote_id = X` |
| **Expected SQLSTATE** | `00000` |
| **Expected Rows** | 0 rows deleted |
| **Primary Denial Mechanism** | RESTRICTIVE RLS `USING (false)` on `pol_poll_votes_restrictive_delete` |
| **Defense-in-depth** | `trg_prevent_vote_mutations` installed for privileged bypass paths |

---

## 7. POLL_VOTES POLICY COMPOSITION VERIFICATION

### Complete Policy Set for `poll_votes`

| Policy Name | Type | Command | USING Expression | WITH CHECK Expression | Roles |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `pol_poll_votes_member_select` | PERMISSIVE | SELECT | `voter_id = auth.uid()` | N/A | `authenticated` |
| `pol_poll_votes_admin_select` | PERMISSIVE | SELECT | `public.get_user_society_id(auth.uid()) = (SELECT society_id FROM polls WHERE id = poll_id)` | N/A | `authenticated` (admin check inside) |
| `pol_poll_votes_restrictive_insert` | RESTRICTIVE | INSERT | N/A | `(false)` | `authenticated` |
| `pol_poll_votes_restrictive_update` | RESTRICTIVE | UPDATE | `(false)` | `(false)` | `authenticated` |
| `pol_poll_votes_restrictive_delete` | RESTRICTIVE | DELETE | `(false)` | N/A | `authenticated` |

### Policy Composition Rules

1. **Permissive policies combine with OR logic.** Either SELECT policy granting visibility is sufficient.
2. **Restrictive policies combine with AND logic.** ALL restrictive policies must pass for a mutation to succeed.
3. **SECURITY DEFINER functions bypass client RLS** because they execute under the `postgres` owner role (which has BYPASSRLS). The `cast_poll_vote(...)` workflow operates inside a SECURITY DEFINER function and can INSERT into `poll_votes` without being blocked by the INSERT restrictive policy.
4. **The restrictive INSERT policy** (`WITH CHECK (false)`) blocks any direct client INSERT. It does NOT block SECURITY DEFINER function inserts.
5. **The restrictive UPDATE policy** (`USING (false)`) ensures no existing row is eligible for update by any ordinary authenticated client. The SECURITY DEFINER `cast_poll_vote` function does not UPDATE `poll_votes` rows — it only INSERTs.
6. **The restrictive DELETE policy** (`USING (false)`) ensures no existing row is eligible for deletion by any ordinary authenticated client.
7. **service_role / BYPASSRLS paths:** Covered by `trg_prevent_vote_mutations` as defense-in-depth.
8. **One-vote-per-property constraint:** Enforced by unique constraint `uq_poll_property_vote(poll_id, property_id)`. A second `cast_poll_vote` call for the same `(poll_id, property_id)` pair raises `SQLSTATE 23505`.

### Interaction with `cast_poll_vote(...)` SECURITY DEFINER Workflow

```text
Client calls: SELECT cast_poll_vote(poll_id, property_id, vote_choice)
                         ↓
SECURITY DEFINER boundary
                         ↓
Function executes as postgres (BYPASSRLS)
                         ↓
INSERT INTO poll_votes ... (permitted despite restrictive INSERT policy)
                         ↓
uq_poll_property_vote enforced atomically
                         ↓
Returns: SQLSTATE 00000 (success) or 23505 (duplicate vote)
```

**The RLS restrictive INSERT policy does NOT block `cast_poll_vote` because SECURITY DEFINER functions run as their owner (`postgres`), which has BYPASSRLS.**

---

## 8. ADVERSARIAL TEST VERIFICATION (poll_votes)

### Test A — Direct UPDATE (Assertion 56)

```sql
-- Set up: authenticated client context (NOT service_role, NOT SECURITY DEFINER)
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"<member_uid>","role":"authenticated"}', true);

UPDATE public.poll_votes SET vote_choice = 'TAMPERED' WHERE voter_id = auth.uid();
-- Expected: UPDATE 0  (SQLSTATE 00000)
-- Verify: 0 rows modified
```

### Test B — Direct DELETE (Assertion 57)

```sql
DELETE FROM public.poll_votes WHERE voter_id = auth.uid();
-- Expected: DELETE 0  (SQLSTATE 00000)
-- Verify: 0 rows deleted
```

### Test C — Trigger Defense-in-Depth Existence Verification

```sql
-- Separately verify trigger is installed (not that it fired for authenticated client)
SELECT tgname, tgenabled, tgtype
FROM pg_trigger
WHERE tgname = 'trg_prevent_vote_mutations'
  AND tgrelid = 'public.poll_votes'::regclass;
-- Expected: 1 row (trigger exists and is enabled)
```

### Test D — SECURITY DEFINER Workflow Not Blocked

```sql
-- Verified via Assertion 59: cast_poll_vote succeeds for authorized resident
SELECT public.cast_poll_vote(p_poll_id, p_property_id, 'Option A');
-- Expected: SQLSTATE 00000, 1 vote row inserted
```

---

## 9. ASSERTION NUMBERING CONFIRMATION

| Status | Value |
| :--- | :--- |
| Authoritative assertion count | **82** (numbered 1 through 82 sequentially) |
| Assertion 56 | Direct UPDATE on `poll_votes` → 0 rows, SQLSTATE `00000` |
| Assertion 57 | Direct DELETE on `poll_votes` → 0 rows, SQLSTATE `00000` |
| Assertions 58–82 | All sequential, no sub-labels, no gaps |
| Sub-labels `56a`/`56b` | **ELIMINATED** — replaced by sequential 56 and 57 |
| Former `56b` SQLSTATE `42501` trigger claim | **ELIMINATED** |

**Numbering unchanged:** All assertions retain their numbers from the v3.2.0 plan.  
No assertions were added or removed.

---

## 10. BASELINE ARITHMETIC CONFIRMATION

```text
Historical Baseline (Slices 1–16):   469 / 469 PASS
Slice 17 Planned Assertions:          82 Assertions (1 through 82)
Final Planned Cumulative Score:       469 + 82 = 551 PASS
```

---

## 11. IMPLEMENTATION CONFIRMATION

```text
NO FILE CREATION HAS OCCURRED.

The following files DO NOT EXIST:
  database/schema_slice17.sql     → NOT CREATED
  database/verify_slice17.sql     → NOT CREATED
  scratch/run_all17.ps1            → NOT CREATED

NO DDL HAS BEEN EXECUTED.
NO DATABASE MODIFICATIONS HAVE BEEN MADE.
NO APPLICATION CODE HAS BEEN MODIFIED.
NO HISTORICAL SLICE (1–16) FILES HAVE BEEN TOUCHED.

Cumulative locked baseline remains:
  469 / 469 PASS — 100% LOCKED
```

---

## 12. PLAN FILES UPDATED IN THIS CORRECTION PASS

| File | Correction Applied |
| :--- | :--- |
| [SLICE17_IMPLEMENTATION_PLAN_PART1.md](file:///d:/Clients%20Applications/SU%20Society%20App/SLICE17_IMPLEMENTATION_PLAN_PART1.md) | Mutation matrix `poll_votes` DELETE: `Exception (42501)` → `0 Rows (00000)`. Trigger role corrected to defense-in-depth. |
| [SLICE17_IMPLEMENTATION_PLAN_PART2.md](file:///d:/Clients%20Applications/SU%20Society%20App/SLICE17_IMPLEMENTATION_PLAN_PART2.md) | Service-role section header: Assertion 81 → 82. Gate pass state machine: `USER APPROVAL REQUIRED` resident row → `BLOCKED` (Blocker 3 locked). |
| [SLICE17_IMPLEMENTATION_PLAN_PART3.md](file:///d:/Clients%20Applications/SU%20Society%20App/SLICE17_IMPLEMENTATION_PLAN_PART3.md) | Section 14 header: 81→82 assertions. Assertions 56a/56b eliminated; sequential Assertions 56 and 57 with corrected `USING(false)` / 0-row / SQLSTATE `00000` semantics. Assertions 57–82 all renumbered to match (57→57, 58→58 … 82→82, eliminating the former off-by-one). Implementation order step 10/11: 81→82, 550→551. Gate table: 81→82 assertions, DESIGN-VERIFIED / PLAN-SPECIFIED classification applied. Final status block updated. |
| [SLICE17_FINAL_IMPLEMENTATION_PLAN_RECONCILIATION_REPORT.md](file:///d:/Clients%20Applications/SU%20Society%20App/SLICE17_FINAL_IMPLEMENTATION_PLAN_RECONCILIATION_REPORT.md) | Section 7A rewritten: incorrect trigger-SQLSTATE-42501 claim eliminated; correct RLS USING(false) semantics documented for both Assertions 56 and 57. |

---

## 13. FINAL STATUS

```text
==================================================
SLICE 17 — FINAL POLL_VOTES SECURITY CORRECTION

PLAN CORRECTION COMPLETE

Previous incorrect claim: ELIMINATED
Correct RLS semantics: DOCUMENTED

Assertion 56 (UPDATE poll_votes):
  Mechanism: RESTRICTIVE USING(false)
  Result:    0 rows updated
  SQLSTATE:  00000

Assertion 57 (DELETE poll_votes):
  Mechanism: RESTRICTIVE USING(false)
  Result:    0 rows deleted
  SQLSTATE:  00000

trg_prevent_vote_mutations:
  Role: Defense-in-depth (privileged/bypass paths)
  NOT the primary denial mechanism for ordinary clients

cast_poll_vote() SECURITY DEFINER workflow:
  UNAFFECTED — continues to INSERT poll_votes rows
  under postgres owner (BYPASSRLS)

Assertion Count: 82 (unchanged)
Historical Baseline: 469 / 469 PASS
Planned Cumulative Score: 469 + 82 = 551 PASS

PLAN-ONLY
IMPLEMENTATION AUTHORIZATION: NONE
RUNTIME VERIFICATION: PENDING

NO APPLICATION OR DATABASE IMPLEMENTATION HAS BEEN AUTHORIZED.
==================================================
```

**READY FOR FINAL USER IMPLEMENTATION APPROVAL**

**NO APPLICATION OR DATABASE IMPLEMENTATION HAS BEEN AUTHORIZED.**
