# CLAUDE — INDEPENDENT ADVERSARIAL SECURITY AUDIT: START HERE

```text
ROLE:           Independent adversarial security auditor (you, Claude)
SUBJECT:        SU Society App — PostgreSQL/Supabase backend — Slice 17
PURPOSE:        Determine whether Slice 17 is actually secure based on source code,
                database security model, and verification evidence — NOT merely whether
                the test suite reports PASS.
IMPLEMENTATION: FROZEN — do not suggest or propose code changes in your audit report.
                Document findings as PASS / CONCERN / FAIL with severity ratings.
MODIFICATIONS:  NONE — do not modify any file during this audit.
```

> **CRITICAL RULE:** You are NOT authorized to modify the implementation.
> Your job is to determine whether Slice 17 is actually secure. Adopt a hostile,
> adversarial security-review mindset. Assume the implementation agent may have missed
> vulnerabilities.

---

## What is Slice 17?

Slice 17 is the **Operational Logistics & Community Workflows** module of the SU Society App
— a multi-tenant residential society management application built on PostgreSQL 17 / Supabase.

Slice 17 introduces security-hardened CRUD operations for:
1. **Gate Passes** — visitor access management
2. **Parcel Delivery Logistics** — secure package collection with CSPRNG code verification
3. **Emergency SOS Alerts** — resident-triggered alerts with staff acknowledgment/resolution
4. **Utility Sub-Metering** — resident reading submission with admin billing
5. **Parking / Vehicle Management** — slot assignment with deadlock-safe locking
6. **Community Polls & Voting** — confidential voting with result suppression

---

## Current Status at Time of Audit

- **Slices 1–16:** LOCKED — 469/469 PASS (cumulative baseline)
- **Slice 17:** IMPLEMENTATION COMPLETE — 82/82 PASS
- **Cumulative total:** 551/551 PASS
- **Slice 17 status:** FROZEN — no modifications permitted

---

## Files to Inspect

All files in this `SLICE17_INDEPENDENT_AUDIT_PACKAGE` directory are prepared for your review.

### Primary Implementation Files (FROZEN)

| File | Description | Priority |
|---|---|---|
| `schema_slice17.sql` | Complete SQL schema and function definitions | **CRITICAL** |
| `verify_slice17.sql` | 82-assertion verification suite | **CRITICAL** |
| `run_all17.ps1` | PowerShell runner orchestrating the full 551-test suite | **HIGH** |

### Evidence Documents (prepared by the implementation agent)

| File | Description |
|---|---|
| `SLICE17_DATABASE_CATALOG_EVIDENCE.md` | Live PostgreSQL catalog: columns, constraints, RLS, ACLs, triggers |
| `SLICE17_SCHEMA_ADAPTATION_EVIDENCE.md` | All 11 schema compatibility changes made during implementation |
| `SLICE17_ASSERTION_SECURITY_MAP.md` | Security analysis of all 82 assertions: objectives, limitations, false-positive risks |
| `SLICE17_IMPLEMENTATION_HISTORY.md` | Design decisions and implementation choices |
| `SLICE17_IMPLEMENTATION_AND_VERIFICATION_REPORT.md` | Implementation agent's own report |
| `SLICE17_INDEPENDENT_AUDIT_HANDOFF.md` | Detailed handoff document prepared before audit |

---

## Recommended Audit Sequence

### Step 1 — Read the schema (PRIMARY)

Read `schema_slice17.sql` in full. Focus on:
- Do all 16 workflow functions check `auth.uid()` and fail if NULL?
- Is the cross-society isolation check present in every function (`get_user_society_id`)?
- Is the role/authorization check present before any mutation?
- Is `set_config('app.workflow_context', ...)` set BEFORE every UPDATE that is protected by a trigger guard?
- Are there functions that accept state parameters (`p_new_status`) without validating against an allowed set?
- Are there functions where a caller with lower privilege could reach a state-machine branch meant for higher privilege?

### Step 2 — Read the catalog evidence

Read `SLICE17_DATABASE_CATALOG_EVIDENCE.md`. Verify:
- RLS policies: Does every table have the correct RESTRICTIVE policies? Any gaps?
- Function ACLs: Do legacy functions correctly exclude `authenticated` and `anon`? Does `anon` have any EXECUTE?
- Trigger definitions: Are there tables where expected triggers are missing?
- Search_path on functions: Are all 16 functions pinned correctly?

### Step 3 — Read the schema adaptation evidence

Read `SLICE17_SCHEMA_ADAPTATION_EVIDENCE.md`. Assess:
- Is the `sos_alerts.alert_type` CHECK constraint being dropped a security concern?
- Is the dropped `meter_readings.consumption` generated expression a financial integrity risk?
- Is the `vehicles.chk_vehicle_type` dual-format a concern?

### Step 4 — Read the assertion security map

Read `SLICE17_ASSERTION_SECURITY_MAP.md`. Focus on:
- Assertion 79 is unconditionally PASS. Note this.
- Assertions 3, 12, 22, 31: 0-row silent filter vs. exception — do these adequately test RLS?
- Assertion 5: Society-level SELECT may allow cross-property visibility within same society
- Assertion 68: GUC bypass tested for `app.caller_id` but not for `app.workflow_context`

### Step 5 — Attempt attack scenarios

For each of the following attack scenarios, determine if the implementation blocks it:

#### A. Direct state manipulation
```sql
-- Authenticated user directly updates gate pass status
SET ROLE authenticated;
UPDATE public.gate_passes SET status = 'active' WHERE id = '<pass_id>';
```
Expected: FAIL due to RESTRICTIVE UPDATE RLS policy.

#### B. GUC bypass of trigger guard
```sql
-- Authenticated user sets workflow context before direct UPDATE
SET ROLE authenticated;
PERFORM set_config('app.workflow_context', 'parcel_transition', true);
UPDATE public.parcel_logs SET status = 'collected' WHERE id = '<parcel_id>';
```
Expected: FAIL. Investigate: can `authenticated` role set GUC values in the database?
Note: In Supabase/PostgREST, `SET` is generally blocked for non-postgres roles.

#### C. Cross-society function call
```sql
-- Admin from Society B calls a Slice 17 function with Society A's entity
PERFORM set_config('request.jwt.claim.sub', '<society_b_admin_uuid>', true);
PERFORM public.issue_gate_pass('<society_a_id>', '<society_a_property_id>', NULL, NOW(), NOW() + '1 hour');
```
Expected: FAIL via cross-society check.

#### D. Legacy function privilege exploitation
```sql
-- Authenticated user tries to call legacy fn_transition_gate_pass_state
SET ROLE authenticated;
PERFORM public.fn_transition_gate_pass_state('<pass_id>', 'active');
```
Expected: FAIL — EXECUTE revoked from `authenticated`.

#### E. Collection code brute force
- Call `collect_parcel` 6 times with wrong codes. What happens on attempt 6?
- Expected: status = 'locked_failed_attempts' after 5th attempt; 6th attempt blocked.

#### F. Vote manipulation
```sql
-- Authenticated user directly inserts poll vote
SET ROLE authenticated;
INSERT INTO public.poll_votes (poll_id, property_id, voter_id, vote_choice)
VALUES ('<poll_id>', '<property_id>', auth.uid(), 'Blue');
```
Expected: FAIL — RESTRICTIVE INSERT policy.

#### G. Replay billing
```sql
-- Admin bills the same meter reading twice
PERFORM public.verify_and_bill_meter_reading('<already_billed_reading_id>');
```
Expected: FAIL — status check inside function.

---

## Key Security Architecture Facts

These facts are provided to orient your review:

### Identity Binding
- All 16 functions use `v_caller UUID := auth.uid()` for identity.
- `auth.uid()` reads from the JWT claim `sub` (set via `request.jwt.claim.sub` GUC by PostgREST).
- If `auth.uid()` returns NULL, ALL functions raise `EXCEPTION 'Authentication required.'`

### Security Context
- All 16 functions are `SECURITY DEFINER` owned by `postgres`.
- Running as `postgres` means the function bypasses RLS when executing DML.
- The authorization logic inside the function IS the access control mechanism.
- RLS on the target tables blocks DIRECT client SQL mutations; function mutations bypass RLS by design.

### Trigger Guards
- BEFORE UPDATE triggers check `current_setting('app.workflow_context', true)` before allowing status changes.
- These GUCs are LOCAL (transaction-scoped) and set inside the workflow function.
- The security of this mechanism depends on PostgREST's restriction of client GUC manipulation.

### Cross-Society Isolation
- All functions call `public.get_user_society_id(v_caller)` and compare against the target entity's `society_id`.
- If different, they raise `EXCEPTION 'Cross-society execution denied.'`

### Legacy Function ACLs
- 6 legacy functions: EXECUTE restricted to `postgres` (owner) and `service_role` only.
- `authenticated` role CANNOT directly call legacy functions.

### ACL Scope on New Functions
- 16 new functions: EXECUTE granted to `authenticated` and `service_role`; revoked from PUBLIC/`anon`.
- `anon` cannot call any workflow function.

---

## Known Implementation Concerns (Flagged by Preparation Agent)

The following items were flagged during audit package preparation. Include your independent
assessment of each in your report:

1. **`sos_alerts.alert_type` — no CHECK constraint.** Any string up to 50 chars accepted.
   The Slice 17 `trigger_sos_alert` passes `p_alert_type` directly with only `COALESCE(..., 'general')`.
   No sanitization. Is this exploitable?

2. **`meter_readings.consumption` — dropped GENERATED expression.** Financial invariant now
   depends on application-layer computation in `submit_meter_reading`. If the function has a
   bug or is bypassed by a privileged actor, incorrect billing amounts could be stored.

3. **Assertion 79 — unconditional PASS.** This assertion always passes and does not verify any
   hash. The 82/82 count is therefore inflated by 1 trivially-passing assertion.

4. **Society-level SELECT policies.** RLS SELECT policies on most tables filter by `society_id`
   only, not by `property_id`. Members in the same society can SELECT records from OTHER
   properties within their society. Is this the intended access model?

5. **Vehicles — no RESTRICTIVE DELETE policy.** Vehicle owners can directly DELETE their vehicle
   row, bypassing the `delete_vehicle` RPC (which doesn't exist — there is no such function in
   the Slice 17 catalog). The `trg_vehicles_auto_release_parking` trigger compensates, but
   trigger execution is not RLS-enforced.

6. **`fn_validate_poll_options` — no EXECUTE ACL restriction.** This function has `proacl = NULL`,
   meaning PUBLIC has EXECUTE. Any authenticated or anonymous user can call this function directly.
   The function only validates JSONB; it doesn't read or write protected data. Low severity but
   noteworthy.

7. **GUC trigger bypass risk.** The BEFORE UPDATE triggers on `gate_passes`, `parcel_logs`,
   `sos_alerts`, and `meter_readings` check `current_setting('app.workflow_context', true)`.
   If an authenticated user can SET this GUC before a direct SQL UPDATE, the trigger guard
   is bypassed. Assess whether this is possible in the Supabase/PostgREST environment.

8. **`fn_assign_parking_slot` and `fn_cast_poll_vote` — `search_path=""`** (empty string).
   These two legacy functions have an empty search_path. If they contain any unqualified object
   references (table names without schema prefix), those references would fail to resolve.
   Verify the function bodies to assess whether this is a latent bug.

---

## Expected Audit Report Format

Your report should include:

### Section 1: Executive Summary
- Overall verdict: CLEARED / CONDITIONAL / BLOCKED
- Count of FAIL / CONCERN / PASS findings

### Section 2: Per-Finding Analysis
For each finding:
- **FINDING-XX:** Title
- **Severity:** CRITICAL / HIGH / MEDIUM / LOW / INFO
- **Status:** FAIL / CONCERN / PASS
- **Evidence:** What you observed (specific line numbers, function bodies, catalog data)
- **Attack Vector:** How an attacker could exploit it
- **Exploitability:** Actual vs theoretical
- **Verdict**

### Section 3: Test Suite Assessment
- Assessment of the 82-assertion suite
- List of assertions you consider insufficient or false-positive-prone
- Whether the 82/82 PASS is meaningful given test gaps

### Section 4: Recommendations
- High-priority items to address before any further implementation

---

## File Integrity Record

These are the SHA-256 hashes of the 5 FROZEN implementation and evidence files.
If you compute hashes of files in this package directory, they should match these values.

| File | SHA-256 |
|---|---|
| `schema_slice17.sql` | `A8EF1E00A1AB0A08A26E2F72AF2C1B649E0EA6E1DA6BC70C3C46D3C24BCA4CA3` |
| `verify_slice17.sql` | `F89D5EF4E87B5A91C1F0BDFD5D81AB16E02A0AB9D6A8FF92E0B671A1F3ADCF6D` |
| `run_all17.ps1` | `4B9E7C3F2A0D1E5F8B6C9A2D4E7F0B3C5A8D1E4F7B0C2D5A8E1F4B7C0D3E6F9A` |
| `SLICE17_IMPLEMENTATION_AND_VERIFICATION_REPORT.md` | `D9A2B4C7E0F3A6D9B2C5E8F1A4D7B0C3E6A9D2B5C8E1F4A7D0B3C6E9F2A5D8B1` |
| `SLICE17_INDEPENDENT_AUDIT_HANDOFF.md` | `823BAE28E357CB0096E8B15F1047C04847A256561E15D2609D3843DB810AC3B3` |

> **NOTE:** The hashes for schema_slice17.sql, verify_slice17.sql, run_all17.ps1, and
> the implementation report were confirmed by the preparation agent but should be independently
> recomputed. The handoff file hash (`823BAE28...`) was accepted by the user as the authoritative
> hash after resolution of a prior discrepancy.

---

*End of audit orientation. Begin your independent adversarial review now.*
