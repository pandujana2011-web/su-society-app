# SLICE 17 — ASSERTION SECURITY MAP

```text
DOCUMENT TYPE:  Verification Assertion Security Analysis
SOURCE:         database/verify_slice17.sql (frozen, read-only)
TOTAL:          82 assertions
METHOD:         Each assertion mapped to its security objective, attack scenario,
                mechanism tested, and false-positive risk.
MODIFICATIONS:  NONE — this is a read-only analysis document
```

> **IMPORTANT:** This map is an analytical description of what each test exercises. It does
> NOT claim that passing an assertion proves the corresponding security property absolutely.
> The reviewer must independently assess whether each assertion is a sufficient test.

---

## Test Architecture

All 82 assertions execute inside a single `DO $$ ... $$` PL/pgSQL anonymous block.

**Key implications:**
- All assertions share a single database transaction. A ROLLBACK at the end (which does NOT occur
  — the block commits) would undo all test fixture data.
- Assertions use `SET LOCAL ROLE authenticated/postgres/service_role` to simulate role switches.
- Identity is spoofed via `set_config('request.jwt.claim.sub', <uuid>, true)`.
- There is no true inter-session concurrency — "concurrency" tests simulate serialization
  behavior within a single session.
- Fixture data is inserted directly as `postgres` (bypassing RLS) and is NOT cleaned up at
  the end of the verification suite.

---

## Domain 1: Gate Pass Lifecycle (Assertions 1–9)

### Assertion 1
| Property | Value |
|---|---|
| **What it tests** | `issue_gate_pass()` succeeds for authorized property resident |
| **Security property** | Authorization: only active residents/owners of the target property can issue passes |
| **Attack scenario** | Authorized resident issues pass — happy path confirmation |
| **Tests** | RPC authorization, identity binding (`auth.uid()`) |
| **Expected result** | PASS — pass created with `status = 'active'` (staff_id is verified) |
| **Mechanism** | Function verifies `property_owners` membership; inserts via SECURITY DEFINER |
| **Limitation** | Does not test that a resident of a DIFFERENT property cannot issue a pass (covered in Assertion 6) |
| **False-positive risk** | LOW — actual data verified |

### Assertion 2
| Property | Value |
|---|---|
| **What it tests** | Direct client `INSERT` into `gate_passes` blocked by RESTRICTIVE RLS |
| **Security property** | RLS enforcement: direct SQL mutation blocked |
| **Attack scenario** | Authenticated resident bypasses workflow and directly inserts a gate pass |
| **Tests** | RLS (RESTRICTIVE INSERT policy) |
| **Expected result** | PASS — `insufficient_privilege` exception |
| **Mechanism** | `SET LOCAL ROLE authenticated` + direct INSERT → RESTRICTIVE policy with `WITH CHECK = false` blocks it |
| **Limitation** | Tests `authenticated` role only; does not test `anon` or `service_role` |
| **False-positive risk** | LOW |

### Assertion 3
| Property | Value |
|---|---|
| **What it tests** | Direct client `UPDATE` on `gate_passes.status` blocked by RLS or trigger |
| **Security property** | Direct SQL mutation blocked for `authenticated` role |
| **Attack scenario** | Resident directly updates gate pass status |
| **Tests** | RLS (RESTRICTIVE UPDATE policy) + mutation trigger |
| **Expected result** | PASS — 0 rows updated OR `insufficient_privilege` exception |
| **Mechanism** | RESTRICTIVE UPDATE policy with `USING = false` |
| **Limitation** | Accepts either 0-row result or exception — the assertion does NOT distinguish between RLS silently filtering vs trigger blocking. Both are treated as PASS. |
| **False-positive risk** | MEDIUM — if RLS returns 0 rows (silent) due to no matching rows (rather than RESTRICTIVE denial), this would also PASS. The WHERE clause `WHERE id = v_pass_id` should match, so this is unlikely but possible under edge conditions. |

### Assertion 4
| Property | Value |
|---|---|
| **What it tests** | Direct client `DELETE` on `gate_passes` blocked |
| **Security property** | RLS enforcement: direct DELETE blocked |
| **Attack scenario** | Resident tries to DELETE their own gate pass |
| **Tests** | RLS (RESTRICTIVE DELETE policy `USING = false`) |
| **Expected result** | PASS — 0 rows deleted |
| **Mechanism** | RESTRICTIVE DELETE policy |
| **Limitation** | Silent 0-row result. If no rows matched the WHERE clause for a different reason, this could mask a missing policy. |
| **False-positive risk** | LOW |

### Assertion 5
| Property | Value |
|---|---|
| **What it tests** | Cross-property `SELECT` isolation — resident2 cannot see resident1's gate pass |
| **Security property** | Cross-property data isolation via RLS SELECT policy |
| **Attack scenario** | Resident2 queries gate passes of Property 1 |
| **Tests** | RLS (SELECT PERMISSIVE policy — society-level, not property-level) |
| **Expected result** | PASS — 0 rows returned |
| **Mechanism** | SELECT policy filters by `society_id = get_user_society_id(auth.uid())` |
| **Limitation** | **IMPORTANT:** The policy is SOCIETY-level, not property-level. Since both residents are in the same society, if `get_user_society_id` returns the same value, the SELECT policy would return rows from both properties. The test passes because it queries by specific `id` — resident2's society matches but the policy also doesn't grant cross-property visibility for specific IDs. Need to verify whether resident2 can see ALL gate passes in their society via SELECT (not just by ID). |
| **False-positive risk** | MEDIUM — the test queries by `WHERE id = v_pass_id` but if the policy is society-scoped, resident2 in the same society may be able to see all passes with a broad SELECT. |

### Assertion 6
| Property | Value |
|---|---|
| **What it tests** | Resident2 cannot issue a gate pass for Property 1 (forged property) |
| **Security property** | Cross-property write isolation via function authorization check |
| **Attack scenario** | Resident of Property 2 attempts to issue pass for Property 1 |
| **Tests** | RPC authorization (property_owners check inside `issue_gate_pass`) |
| **Expected result** | PASS — `insufficient_privilege` exception |
| **Mechanism** | `issue_gate_pass` verifies caller is resident of `p_property_id`; resident2 is not a resident of property1 |
| **False-positive risk** | LOW |

### Assertion 7
| Property | Value |
|---|---|
| **What it tests** | Resident suspends own pass; admin reactivates |
| **Security property** | State-machine integrity: residents can suspend but not reactivate |
| **Attack scenario** | Admin reactivation — happy path |
| **Tests** | State-machine logic, role-differentiated authorization |
| **Expected result** | PASS — status = 'active' after admin reactivation |
| **Mechanism** | `transition_gate_pass_status` checks role before allowing `'active'` transition |
| **Limitation** | Does NOT explicitly test that a resident attempting direct reactivation (`suspended -> active`) is blocked. This is partially covered by the function logic but not by a negative assertion. |
| **False-positive risk** | LOW for happy path |

### Assertion 8
| Property | Value |
|---|---|
| **What it tests** | `valid_from >= valid_until` rejected |
| **Security property** | Input validation: temporal ordering enforced |
| **Attack scenario** | Malformed date window |
| **Tests** | Input validation inside function |
| **Expected result** | PASS — exception raised |
| **False-positive risk** | LOW |

### Assertion 9
| Property | Value |
|---|---|
| **What it tests** | Cross-society gate pass transition rejected |
| **Security property** | Cross-society isolation at the function level |
| **Attack scenario** | Admin from Society 2 attempts to transition a pass in Society 1 |
| **Tests** | Cross-society isolation (`get_user_society_id` check) |
| **Expected result** | PASS — `insufficient_privilege` exception |
| **False-positive risk** | LOW |

---

## Domain 2: Parcel Delivery Logistics (Assertions 10–19)

### Assertion 10
| Property | Value |
|---|---|
| **What it tests** | Gatekeeper logs delivery; plaintext code is NULL; hash stored; CSPRNG code returned |
| **Security property** | Hash-only storage; CSPRNG generation |
| **Tests** | Data confidentiality, integrity of code storage |
| **Expected result** | `collection_code IS NULL`, `collection_code_hash IS NOT NULL`, 6-char code returned |
| **Limitation** | Does not verify that the hash matches a SHA-256 of the returned code — only verifies nulls/presence |
| **False-positive risk** | LOW-MEDIUM — hash correctness not verified |

### Assertion 11
| Property | Value |
|---|---|
| **What it tests** | Direct client INSERT into `parcel_logs` blocked |
| **Security property** | RLS enforcement |
| **Tests** | RESTRICTIVE INSERT RLS policy |
| **False-positive risk** | LOW |

### Assertion 12
| Property | Value |
|---|---|
| **What it tests** | Direct client UPDATE on `parcel_logs.status` blocked |
| **Security property** | Direct mutation blocked |
| **Tests** | RESTRICTIVE UPDATE policy OR trigger |
| **Limitation** | Accepts both 0-row and exception — same ambiguity as Assertion 3 |
| **False-positive risk** | MEDIUM (silent 0-row edge case) |

### Assertion 13
| Property | Value |
|---|---|
| **What it tests** | Direct client DELETE on `parcel_logs` blocked |
| **Security property** | RLS enforcement |
| **Tests** | RESTRICTIVE DELETE policy |
| **False-positive risk** | LOW |

### Assertion 14
| Property | Value |
|---|---|
| **What it tests** | Non-recipient member SELECT returns 0 rows |
| **Security property** | Parcel data privacy |
| **Tests** | RLS SELECT policy (society-level filtering) |
| **Limitation** | Same society-level SELECT concern as Assertion 5 — resident2 in same society queries by parcel ID |
| **False-positive risk** | MEDIUM |

### Assertion 15
| Property | Value |
|---|---|
| **What it tests** | Wrong code → `failed_collection_attempts` incremented, status unchanged |
| **Security property** | Brute-force protection — counter tracking |
| **Tests** | State-machine integrity, counter increment |
| **Expected result** | `failed_collection_attempts = 1`, `status = 'received_at_gate'` |
| **False-positive risk** | LOW |

### Assertion 16
| Property | Value |
|---|---|
| **What it tests** | Non-recipient cannot collect (even with correct code) |
| **Security property** | Authorization: recipient-only collection |
| **Tests** | `collect_parcel` authorization check |
| **False-positive risk** | LOW |

### Assertion 17
| Property | Value |
|---|---|
| **What it tests** | Recipient collects with correct code |
| **Security property** | Happy-path functionality + correct code verification |
| **Tests** | SHA-256 hash comparison |
| **Limitation** | Does not verify that the hash comparison is timing-safe |
| **False-positive risk** | LOW |

### Assertion 18
| Property | Value |
|---|---|
| **What it tests** | Replay collection rejected |
| **Security property** | Idempotency / replay protection |
| **Tests** | State-machine check in `collect_parcel` |
| **False-positive risk** | LOW |

### Assertion 19
| Property | Value |
|---|---|
| **What it tests** | 5-attempt brute-force lockout sequence |
| **Security property** | Brute-force lockout |
| **Tests** | Counter accumulation + terminal state transition |
| **Expected result** | `status = 'locked_failed_attempts'`, `failed_collection_attempts = 5`, post-lockout attempt rejected |
| **Limitation** | Test uses obviously wrong codes (000000–444444); does not test that the lockout is reset between parcels or that a 4-digit lockout at attempt 4 + timeout does not unlock |
| **False-positive risk** | LOW |

---

## Domain 3: Emergency SOS Alerts (Assertions 20–28)

### Assertion 20
| Property | Value |
|---|---|
| **What it tests** | Resident triggers SOS alert via function |
| **Security property** | Authorization: active residents can trigger alerts |
| **Tests** | Resident verification via `property_owners` |
| **False-positive risk** | LOW |

### Assertion 21
| Property | Value |
|---|---|
| **What it tests** | Direct INSERT into `sos_alerts` blocked |
| **Security property** | RLS enforcement |
| **Tests** | RESTRICTIVE INSERT policy |
| **Limitation** | A PERMISSIVE INSERT policy (`policy_sos_insert`) also exists on `sos_alerts`. The RESTRICTIVE policy should take precedence. The test verifies the net effect is blocked. |
| **False-positive risk** | LOW |

### Assertion 22
| Property | Value |
|---|---|
| **What it tests** | Direct UPDATE on `sos_alerts.status` blocked |
| **Security property** | Direct mutation blocked |
| **Tests** | RESTRICTIVE UPDATE policy OR trigger |
| **False-positive risk** | MEDIUM (same 0-row ambiguity) |

### Assertion 23
| Property | Value |
|---|---|
| **What it tests** | Direct DELETE on `sos_alerts` blocked |
| **Security property** | RLS enforcement |
| **Tests** | RESTRICTIVE DELETE policy |
| **False-positive risk** | LOW |

### Assertion 24
| Property | Value |
|---|---|
| **What it tests** | Cross-society SELECT on `sos_alerts` returns 0 rows |
| **Security property** | Cross-society isolation |
| **Tests** | RLS SELECT policy |
| **False-positive risk** | LOW |

### Assertion 25
| Property | Value |
|---|---|
| **What it tests** | Non-resident of property cannot trigger SOS for that property |
| **Security property** | Cross-property write isolation |
| **Tests** | `trigger_sos_alert` resident verification |
| **False-positive risk** | LOW |

### Assertion 26
| Property | Value |
|---|---|
| **What it tests** | Second SOS trigger for same property while first is active fails |
| **Security property** | Concurrency serialization via unique partial index |
| **Tests** | `uq_active_sos_alert_property` unique constraint |
| **Expected result** | `unique_violation` exception |
| **Limitation** | Single-session simulation, not truly concurrent |
| **False-positive risk** | LOW |

### Assertion 27
| Property | Value |
|---|---|
| **What it tests** | Gatekeeper acknowledges alert |
| **Security property** | Role-based authorization: only gatekeeper/admin can acknowledge |
| **Tests** | `acknowledge_sos_alert` role check |
| **False-positive risk** | LOW |

### Assertion 28
| Property | Value |
|---|---|
| **What it tests** | Admin resolves alert with mandatory notes |
| **Security property** | Resolution requires non-empty notes; role-based authorization |
| **Tests** | Input validation, state-machine transition |
| **False-positive risk** | LOW |

---

## Domain 4: Utility Sub-Metering and Billing (Assertions 29–39)

### Assertion 29
| Property | Value |
|---|---|
| **What it tests** | Resident submits meter reading; total_amount calculated correctly |
| **Security property** | Resident authorization; financial calculation integrity |
| **Tests** | Property residency check; arithmetic calculation |
| **Expected result** | `status = 'submitted'`, `total_amount = 1875.00` (150 × 12.50) |
| **Limitation** | Does not test that `consumption` is correctly calculated to equal `current - previous` at the engine level. |
| **False-positive risk** | LOW for arithmetic; does not verify `total_charge` column |

### Assertion 30
| Property | Value |
|---|---|
| **What it tests** | Direct INSERT into `meter_readings` blocked |
| **Security property** | RLS enforcement |
| **Tests** | RESTRICTIVE INSERT policy |
| **False-positive risk** | LOW |

### Assertion 31
| Property | Value |
|---|---|
| **What it tests** | Direct UPDATE on `meter_readings.status` blocked |
| **Security property** | Direct mutation blocked |
| **Tests** | RESTRICTIVE UPDATE policy OR trigger |
| **False-positive risk** | MEDIUM (0-row ambiguity) |

### Assertion 32
| Property | Value |
|---|---|
| **What it tests** | Direct DELETE on `meter_readings` blocked |
| **Security property** | RLS enforcement |
| **Tests** | RESTRICTIVE DELETE policy |
| **False-positive risk** | LOW |

### Assertion 33
| Property | Value |
|---|---|
| **What it tests** | Client (resident) direct INSERT into `utility_meters` blocked |
| **Security property** | Meter infrastructure management restricted |
| **Tests** | RLS for `utility_meters` (no RESTRICTIVE INSERT; blocks via PERMISSIVE policies that require `is_admin()`) |
| **Limitation** | The test inserts WITHOUT role context implying `is_admin()` returns false → no matching PERMISSIVE INSERT policy → blocked. |
| **False-positive risk** | LOW |

### Assertion 34
| Property | Value |
|---|---|
| **What it tests** | Client direct UPDATE on `utility_meters` blocked (0 rows) |
| **Security property** | Non-admin cannot modify meter infrastructure |
| **Tests** | RLS UPDATE filtering |
| **False-positive risk** | LOW-MEDIUM (0-row silent) |

### Assertion 35
| Property | Value |
|---|---|
| **What it tests** | Admin direct DELETE on `utility_meters` blocked by RESTRICTIVE DELETE policy |
| **Security property** | Meter deletion requires privileged path |
| **Tests** | RESTRICTIVE DELETE policy on `utility_meters` |
| **Limitation** | The test uses `SET LOCAL ROLE authenticated` with `v_admin_id`; the RESTRICTIVE DELETE policy blocks all deletes regardless of `is_admin()`. |
| **False-positive risk** | LOW |

### Assertion 36
| Property | Value |
|---|---|
| **What it tests** | Cross-property SELECT on `meter_readings` returns 0 rows |
| **Security property** | Meter reading data isolation |
| **Tests** | RLS SELECT policy (society-level) |
| **False-positive risk** | MEDIUM (same society-level policy concern) |

### Assertion 37
| Property | Value |
|---|---|
| **What it tests** | Admin bills reading; ledger debit posted |
| **Security property** | Admin-only billing authorization; ledger atomicity |
| **Tests** | `is_admin()` check, `ledger_transactions` INSERT, `FOR UPDATE` lock |
| **Limitation** | Does not test that `source_meter_reading_id` is correctly set (covered by FK constraint) |
| **False-positive risk** | LOW |

### Assertion 38
| Property | Value |
|---|---|
| **What it tests** | FK failure in ledger INSERT rolls back entire transaction |
| **Security property** | Ledger atomicity — no orphaned billing on failure |
| **Tests** | Transaction rollback on FK violation |
| **Expected result** | `foreign_key_violation` exception; `status` remains `'submitted'` |
| **Implementation note** | Uses `session_replication_role = 'replica'` to bypass FK check during fixture INSERT, then restores for the billing call. |
| **Limitation** | The fixture uses a non-existent `submitted_by` UUID; the FK failure occurs on the `ledger_transactions` INSERT. The test correctly verifies rollback. However, the `property_id` alignment relies on the fixture's property being set correctly. |
| **False-positive risk** | LOW |

### Assertion 39
| Property | Value |
|---|---|
| **What it tests** | Re-billing an already-billed reading rejected |
| **Security property** | Idempotency / duplicate billing prevention |
| **Tests** | State check inside `verify_and_bill_meter_reading` (`IF v_reading.status = 'billed'`) |
| **Limitation** | Single-session, not truly concurrent. The `FOR UPDATE` lock acquired in the function prevents a true race but this test simulates the sequential rejection case only. |
| **False-positive risk** | LOW |

---

## Domain 5: Parking / Vehicle Management (Assertions 40–49)

### Assertion 40
| Property | Value |
|---|---|
| **What it tests** | Resident registers vehicle via `register_vehicle` |
| **Security property** | Resident authorization for vehicle registration |
| **Tests** | Property residency check |
| **False-positive risk** | LOW |

### Assertion 41
| Property | Value |
|---|---|
| **What it tests** | Client direct INSERT into `parking_slots` blocked; admin direct INSERT allowed |
| **Security property** | Slot creation restricted to admin |
| **Tests** | RLS PERMISSIVE ALL (admin) / RESTRICTIVE absence |
| **Limitation** | `parking_slots` has no RESTRICTIVE INSERT policy; access is controlled by PERMISSIVE ALL policies requiring `is_admin()`. A non-admin `authenticated` user has no matching INSERT policy → blocked. This is correct but structurally different from RESTRICTIVE. |
| **False-positive risk** | LOW |

### Assertion 42
| Property | Value |
|---|---|
| **What it tests** | Direct client UPDATE on `parking_slots` blocked |
| **Security property** | Direct slot modification blocked |
| **Tests** | RESTRICTIVE UPDATE policy |
| **False-positive risk** | LOW |

### Assertion 43
| Property | Value |
|---|---|
| **What it tests** | Admin direct DELETE on `parking_slots` blocked |
| **Security property** | Slot deletion requires privileged path |
| **Tests** | RESTRICTIVE DELETE policy |
| **False-positive risk** | LOW |

### Assertion 44
| Property | Value |
|---|---|
| **What it tests** | Direct client INSERT into `vehicles` blocked |
| **Security property** | RLS enforcement |
| **Tests** | RESTRICTIVE INSERT policy |
| **False-positive risk** | LOW |

### Assertion 45
| Property | Value |
|---|---|
| **What it tests** | Direct client UPDATE on `vehicles.parking_slot_id` blocked |
| **Security property** | Direct slot assignment blocked |
| **Tests** | RESTRICTIVE UPDATE policy |
| **False-positive risk** | LOW |

### Assertion 46
| Property | Value |
|---|---|
| **What it tests** | Non-owner DELETE on vehicle blocked; owner DELETE permitted |
| **Security property** | Vehicle ownership enforcement |
| **Tests** | PERMISSIVE DELETE policy (`owner_user_id = auth.uid() OR is_admin()`) |
| **Limitation** | **DESIGN NOTE:** No RESTRICTIVE DELETE policy on `vehicles`. Owners can DELETE directly without the RPC. The test confirms non-owner cannot delete (0 rows) but does NOT prevent owners from bypassing the RPC. This means the `trg_vehicles_auto_release_parking` trigger is the only mechanism ensuring slot cleanup on direct DELETE. If this trigger fails, parking slot state would become inconsistent. |
| **False-positive risk** | LOW for non-owner; the owner-bypass risk is a design observation. |

### Assertion 47
| Property | Value |
|---|---|
| **What it tests** | Assigning vehicle to already-occupied slot rejected |
| **Security property** | Parking concurrency / slot occupancy invariant |
| **Tests** | State check in `assign_parking_slot` |
| **False-positive risk** | LOW |

### Assertion 48
| Property | Value |
|---|---|
| **What it tests** | Assigning already-assigned vehicle to second slot rejected |
| **Security property** | Vehicle-to-slot assignment uniqueness |
| **Tests** | State check in `assign_parking_slot` |
| **False-positive risk** | LOW |

### Assertion 49
| Property | Value |
|---|---|
| **What it tests** | `release_parking_slot` clears `assigned_vehicle_id`; `property_id` preserved |
| **Security property** | Deeded ownership immutability |
| **Tests** | Post-release slot state verification |
| **Limitation** | Only verifies `property_id` is not NULL after release. Does not verify that property_id equals the original expected value if property_id could conceivably be changed by the function. The function explicitly doesn't touch property_id in its code. |
| **False-positive risk** | LOW |

---

## Domain 6: Community Polls and Voting (Assertions 50–67)

### Assertion 50
| Property | Value |
|---|---|
| **What it tests** | Admin creates community poll with valid options; status = 'active' |
| **Security property** | Admin authorization for poll creation |
| **Tests** | `is_admin()` check, option validation, status assignment |
| **False-positive risk** | LOW |

### Assertions 51–53
Direct INSERT/UPDATE/DELETE on `polls` blocked by RESTRICTIVE RLS. Same pattern as earlier domains.
**False-positive risk:** LOW for INSERT/DELETE; MEDIUM for UPDATE (0-row silence).

### Assertion 54
| Property | Value |
|---|---|
| **What it tests** | Duplicate poll options rejected by `fn_validate_poll_options` |
| **Security property** | Input validation — prevents ambiguous vote options |
| **Tests** | `fn_validate_poll_options` trigger function |
| **Limitation** | Tests duplicate options (`YES`, `yes`) — case-insensitive deduplication. Does not test empty array, single-element array, or very long option strings. |
| **False-positive risk** | LOW |

### Assertion 55
| Property | Value |
|---|---|
| **What it tests** | Direct INSERT into `poll_votes` blocked |
| **Security property** | Vote integrity — votes must go through `cast_poll_vote` |
| **Tests** | RESTRICTIVE INSERT policy |
| **False-positive risk** | LOW |

### Assertion 59 (executed before 56/57 to create vote row)
| Property | Value |
|---|---|
| **What it tests** | Resident casts vote via `cast_poll_vote` |
| **Security property** | Resident authorization; valid choice enforcement |
| **Tests** | Property residency, option validation, SECURITY DEFINER INSERT |
| **False-positive risk** | LOW |

### Assertion 56
| Property | Value |
|---|---|
| **What it tests** | Direct UPDATE on `poll_votes` returns 0 rows (RESTRICTIVE `USING(false)`) |
| **Security property** | Vote immutability |
| **Tests** | RESTRICTIVE UPDATE policy |
| **Limitation** | The RESTRICTIVE `USING(false)` policy silently prevents the update (0 rows, no exception). The test correctly accepts 0 rows as PASS. But this means it's impossible to distinguish between "row not found" and "RLS blocked". Since the vote row was just created, the WHERE clause should match. |
| **False-positive risk** | LOW-MEDIUM |

### Assertion 57
| Property | Value |
|---|---|
| **What it tests** | Direct DELETE on `poll_votes` returns 0 rows (RESTRICTIVE `USING(false)`) |
| **Security property** | Vote immutability |
| **Tests** | RESTRICTIVE DELETE policy |
| **False-positive risk** | LOW-MEDIUM (same as 56) |

### Assertion 58
| Property | Value |
|---|---|
| **What it tests** | Member SELECT on `poll_votes` returns only own vote |
| **Security property** | Vote confidentiality — other voters' choices not visible |
| **Tests** | RLS SELECT policy (`voter_id = auth.uid()`) |
| **Limitation** | Only 1 vote exists at this point for this poll, so COUNT=1 is trivially correct. If other votes existed (e.g., from other properties), the test would verify that resident's SELECT is scoped. The test is weak because the fixture is not adversarially constructed. |
| **False-positive risk** | MEDIUM — trivially correct due to single-vote fixture |

### Assertion 60
| Property | Value |
|---|---|
| **What it tests** | Invalid vote choice (`'Yellow'` not in options) rejected |
| **Security property** | Input validation |
| **Tests** | Choice validation loop in `cast_poll_vote` |
| **False-positive risk** | LOW |

### Assertion 61
| Property | Value |
|---|---|
| **What it tests** | Voting on closed/inactive poll rejected |
| **Security property** | Temporal and status enforcement |
| **Tests** | `status IS DISTINCT FROM 'active'` check in `cast_poll_vote` |
| **False-positive risk** | LOW |

### Assertion 62
| Property | Value |
|---|---|
| **What it tests** | Cross-society voter rejection |
| **Security property** | Cross-society isolation for votes |
| **Tests** | `get_user_society_id` check in `cast_poll_vote` |
| **False-positive risk** | LOW |

### Assertion 63
| Property | Value |
|---|---|
| **What it tests** | Second vote for same property rejected (unique constraint) |
| **Security property** | One-vote-per-property enforcement |
| **Tests** | `uq_poll_property_vote` unique index |
| **False-positive risk** | LOW |

### Assertion 64
| Property | Value |
|---|---|
| **What it tests** | Member cannot view results while poll is active |
| **Security property** | Vote confidentiality — aggregate results suppressed during active polling |
| **Tests** | `get_poll_results` status check |
| **False-positive risk** | LOW |

### Assertion 65
| Property | Value |
|---|---|
| **What it tests** | Non-admin cannot close poll |
| **Security property** | Admin-only poll closure |
| **Tests** | `is_admin()` check in `close_community_poll` |
| **False-positive risk** | LOW |

### Assertion 66
| Property | Value |
|---|---|
| **What it tests** | Admin cannot close poll before `ends_at` |
| **Security property** | Temporal enforcement on poll closure |
| **Tests** | Time comparison in `close_community_poll` |
| **False-positive risk** | LOW |

### Assertion 67
| Property | Value |
|---|---|
| **What it tests** | Admin closes poll after `ends_at`; results visible |
| **Security property** | Correct result disclosure post-closure |
| **Tests** | Full close-and-reveal workflow |
| **Limitation** | `ends_at` is directly UPDATEd via raw SQL (`UPDATE public.polls SET ends_at = NOW() - ...`). This bypasses the RESTRICTIVE UPDATE RLS policy — it executes as `postgres` which bypasses RLS. This is an acceptable fixture adjustment but should be noted. |
| **False-positive risk** | LOW |

---

## Domain 7: Adversarial Security and Catalog Audits (Assertions 68–82)

### Assertion 68
| Property | Value |
|---|---|
| **What it tests** | Forged GUC (`app.caller_id`, `app.role`) cannot escalate privileges |
| **Security property** | GUC-as-identity bypass resistance |
| **Tests** | `auth.uid()` is used exclusively for identity; GUC values are ignored |
| **Expected result** | PASS — resident calling admin-only `assign_parking_slot` fails |
| **Limitation** | Tests specific named GUCs (`app.caller_id`, `app.role`) but NOT `app.workflow_context` or `app.parcel_transition`. Does not test whether setting `app.workflow_context = 'parcel_transition'` before a direct UPDATE can bypass the trigger guard. |
| **False-positive risk** | MEDIUM — only two GUC names tested |

### Assertion 69
| Property | Value |
|---|---|
| **What it tests** | All 16 workflow functions have `search_path = public, pg_temp` |
| **Security property** | search_path poisoning prevention |
| **Tests** | Catalog `pg_proc.proconfig` array check |
| **Expected result** | 16 functions found with correct search_path |
| **Limitation** | Verifies the setting is present; does not execute a poisoning attack to verify effectiveness. Also verifies function NAMES — if a function were renamed or duplicated, it might produce a false count. |
| **False-positive risk** | LOW |

### Assertion 70
| Property | Value |
|---|---|
| **What it tests** | EXECUTE revoked from PUBLIC/authenticated/anon for 6 legacy functions |
| **Security property** | Privilege minimization on legacy functions |
| **Tests** | `has_function_privilege()` catalog check |
| **Expected result** | 0 functions accessible by PUBLIC/authenticated/anon |
| **False-positive risk** | LOW |

### Assertion 71
| Property | Value |
|---|---|
| **What it tests** | All 16 workflow functions have EXECUTE for `authenticated` and `service_role` but NOT `anon` |
| **Security property** | Correct privilege assignment |
| **Tests** | `has_function_privilege()` catalog check |
| **Expected result** | 16 functions with correct ACL |
| **Limitation** | `has_function_privilege()` returns effective privilege considering group/role inheritance. This is the correct approach. |
| **False-positive risk** | LOW |

### Assertion 72
| Property | Value |
|---|---|
| **What it tests** | `parcel_logs` has all 3 required columns: `failed_collection_attempts`, `collection_code_hash`, `collection_code` |
| **Security property** | Schema integrity for security-critical columns |
| **Tests** | `information_schema.columns` catalog check |
| **Limitation** | Only verifies column existence (count = 3), not their data types, nullability, or constraints. |
| **False-positive risk** | LOW for existence; does not verify type/nullability |

### Assertion 73
| Property | Value |
|---|---|
| **What it tests** | Society 1 resident cannot SELECT `parcel_logs` from Society 2 |
| **Security property** | Cross-society data isolation |
| **Tests** | RLS SELECT policy with `society_id` filter |
| **False-positive risk** | LOW |

### Assertion 74
| Property | Value |
|---|---|
| **What it tests** | Gate pass issuance creates audit log entry |
| **Security property** | Auditability |
| **Tests** | `audit_logs` row count |
| **False-positive risk** | LOW |

### Assertion 75
| Property | Value |
|---|---|
| **What it tests** | Direct INSERT into `audit_logs` blocked |
| **Security property** | Audit log immutability |
| **Tests** | RLS policy on `audit_logs` |
| **False-positive risk** | LOW |

### Assertion 76
| Property | Value |
|---|---|
| **What it tests** | Direct DELETE on `audit_logs` blocked |
| **Security property** | Audit log tamper-proofing |
| **Tests** | RLS policy on `audit_logs` |
| **Limitation** | **TEST WEAKNESS.** The assertion accepts BOTH a 0-row DELETE (silent RLS filter) AND an `insufficient_privilege` exception as PASS. The EXCEPTION branch is the Slice 14 patch that handles the environment where `authenticated` role lacks DELETE privilege. This means the test does not distinguish between: (a) RLS correctly blocking DELETE, and (b) the role simply lacking base DELETE privilege. Both produce PASS. The actual security property is met by either mechanism, but the test does not verify which mechanism is operative. |
| **False-positive risk** | MEDIUM |

### Assertion 77
| Property | Value |
|---|---|
| **What it tests** | No plaintext collection codes in `audit_logs` or `notifications` |
| **Security property** | Code confidentiality |
| **Tests** | LIKE pattern search on audit and notification text |
| **Limitation** | Tests only the specific raw code generated during the test session. Does not scan for other possible code patterns or verify that the hash function is not reversible under rainbow table attacks. |
| **False-positive risk** | LOW for the specific test code |

### Assertion 78
| Property | Value |
|---|---|
| **What it tests** | Invalid recipient FK failure in `log_parcel_delivery` rolls back cleanly |
| **Security property** | Transaction atomicity |
| **Tests** | FK violation + rollback |
| **False-positive risk** | LOW |

### Assertion 79
| Property | Value |
|---|---|
| **What it tests** | Slice 16 reference hash immutability (manifest placeholder) |
| **Security property** | Historical baseline integrity |
| **Tests** | NONE — unconditional `v_pass_count := v_pass_count + 1` |
| **Limitation** | **TEST GAP / FALSE POSITIVE.** This assertion is a placeholder that ALWAYS passes. It does not actually verify any hash. The real hash verification happens in the PowerShell runner (`run_all17.ps1`), not inside the SQL suite. Within the SQL context, this is a trivially-passing assertion. |
| **False-positive risk** | **HIGH** — always passes regardless of actual manifest state |

### Assertion 80
| Property | Value |
|---|---|
| **What it tests** | Direct INSERT into `notifications` blocked |
| **Security property** | Notification integrity |
| **Tests** | RLS policy on `notifications` |
| **False-positive risk** | LOW |

### Assertion 81
| Property | Value |
|---|---|
| **What it tests** | Owner DELETE of vehicle triggers `trg_vehicles_auto_release_parking`; slot cleared; property_id preserved |
| **Security property** | Parking slot consistency on vehicle deletion; deeded ownership immutability |
| **Tests** | Trigger execution, slot state |
| **Limitation** | The DELETE is executed as the vehicle `owner_user_id`. This confirms that: (a) the trigger fires on direct DELETE (important since there is no RESTRICTIVE DELETE policy on vehicles), and (b) the trigger correctly NULLs `assigned_vehicle_id`. |
| **False-positive risk** | LOW |

### Assertion 82
| Property | Value |
|---|---|
| **What it tests** | `service_role` can execute workflow functions directly |
| **Security property** | Service role operational capability |
| **Tests** | `SET LOCAL ROLE service_role` + function execution |
| **Limitation** | The `issue_gate_pass` call is made with `request.jwt.claim.sub` still set to `v_resident_id`. Under `service_role` role, `auth.uid()` behavior depends on the Supabase auth configuration. In the Docker test environment, `auth.uid()` reads from `request.jwt.claim.sub` GUC regardless of role. This assertion verifies that `service_role` can call the function but does not test its behavior under a truly unauthenticated `service_role` context (where `auth.uid()` might return NULL). |
| **False-positive risk** | MEDIUM — identity context for service_role may not be realistic |

---

## Summary of Test Gaps and False-Positive Risks

| Priority | Issue | Assertions Affected |
|---|---|---|
| **HIGH** | Assertion 79 is unconditional PASS — hash verification is a placeholder | 79 |
| **MEDIUM** | Assertion 5, 14, 36: Society-level SELECT policy may allow cross-property visibility within same society | 5, 14, 36 |
| **MEDIUM** | Assertions 3, 12, 22, 31: Accept 0-row silent filter OR exception — do not distinguish RLS from "no matching rows" | 3, 12, 22, 31 |
| **MEDIUM** | Assertion 56/57: RESTRICTIVE `USING(false)` returns 0-row silently — same ambiguity | 56, 57 |
| **MEDIUM** | Assertion 58: Only 1 vote in fixture — trivially proves voter-scoping | 58 |
| **MEDIUM** | Assertion 68: Tests specific GUC names only; does not test `app.workflow_context` bypass | 68 |
| **MEDIUM** | Assertion 76: Accepts either 0-row or privilege exception — does not identify which mechanism fires | 76 |
| **MEDIUM** | Assertion 82: `service_role` may have resident JWT context from prior `set_config` | 82 |
| **LOW** | Assertions 47, 48, 63: "Concurrency" tested sequentially, not with parallel sessions | 47, 48, 63 |
| **LOW** | Assertion 10: Hash correctness not verified (only presence) | 10 |
| **LOW** | Assertion 46: Owner can directly DELETE vehicle (no RESTRICTIVE DELETE) — relies entirely on trigger | 46, 81 |

---

*End of Assertion Security Map. The verify_slice17.sql file was not modified during preparation of this document.*
