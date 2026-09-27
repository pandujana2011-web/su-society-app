# SLICE 22 — PRE-PLANNING FORENSIC REPOSITORY INVENTORY

```
DOCUMENT TYPE:    FORENSIC INVENTORY ONLY
ZERO IMPLEMENTATION PERFORMED
ZERO LOCKED ARTIFACTS MODIFIED
ZERO DATABASE MUTATIONS PERFORMED
SLICE 21 REMAINS IMMUTABLE
791/791 REMAINS THE AUTHORITATIVE BASELINE
SLICE 22 IS NOT YET AUTHORIZED FOR IMPLEMENTATION
```

**Generated:** 2026-09-10  
**Repository:** `D:\Clients Applications\SU Society App`  
**Mode:** READ-ONLY FORENSIC DISCOVERY — NO MUTATIONS AUTHORIZED OR PERFORMED  

---

## 1. EXECUTIVE SUMMARY

This forensic inventory was conducted in strict read-only mode against the target repository. No SQL was executed against the project database. No schema files were created or modified. No locked artifacts were altered. No baseline mutation occurred.

**Primary Finding:** The repository already contains substantial Slice 22 artifacts including a completed implementation (`database/schema_slice22.sql`), a verification suite (`database/verify_slice22.sql`), a final security plan, a forensic discovery report, an independent forensic security audit, a pre-implementation authorization gate, and multiple micro-remediation plans. Slice 22 was implemented but is **NOT YET VERIFIED** and **NOT YET LOCKED**.

**Critical Hash Discrepancy Detected:** `SLICE21_FINAL_SECURITY_PLAN.md` observed hash does NOT match the authoritative hash recorded in `SLICE21_SECURITY_LOCK.md`. This is documented below. No repair was performed. This discrepancy requires governance review.

---

## 2. REPOSITORY INVENTORY

### 2.1 Top-Level Directory Structure

| Path | Type | Purpose | Locked? | Status |
| :--- | :---: | :--- | :---: | :--- |
| `src/` | DIR | React/Vite application source | No | Active |
| `database/` | DIR | All SQL schema and verification files | Partial | Contains Slices 1–22 |
| `scratch/` | DIR | Development scripts, audit helpers, run scripts | No | Active |
| `supabase/` | DIR | Supabase project configuration | No | Active |
| `public/` | DIR | Static assets | No | Active |
| `dist/` | DIR | Build output | No | Generated |
| `node_modules/` | DIR | NPM dependencies | No | Generated |
| `_slice20_rev434_verification_tmp/` | DIR | Temporary slice 20 verification workspace | No | Historical |

### 2.2 Database Directory (`database/`) — Full File Inventory

| File | Type | Purpose | Locked? |
| :--- | :---: | :--- | :---: |
| `schema_slice1.sql` (65 KB) | Schema | Core entities | YES (Slice 1) |
| `schema_slice2.sql` (23 KB) | Schema | Financial core & ledger | YES (Slice 2 + Remediation) |
| `schema_slice3.sql` (26 KB) | Schema | Amenities & maintenance | YES |
| `schema_slice4.sql` (37 KB) | Schema | Advanced accounting | YES |
| `schema_slice5.sql` (17 KB) | Schema | Notices, polls, vehicles, documents | YES |
| `schema_slice6.sql` (16 KB) | Schema | Daily staff & gate passes | YES (refactored Slice 17) |
| `schema_slice7.sql` (19 KB) | Schema | Vendors & asset catalog | YES (replaced Slice 21) |
| `schema_slice8.sql` (16 KB) | Schema | Move requests & parcels | YES (replaced Slice 17/20) |
| `schema_slice9.sql` (13 KB) | Schema | Staff attendance & rule violations (legacy) | YES |
| `schema_slice10.sql` (13 KB) | Schema | Committee meetings | YES |
| `schema_slice11.sql` (12 KB) | Schema | Utility meters | YES (refactored Slice 17) |
| `schema_slice12.sql` (10 KB) | Schema | SOS alerts | YES (refactored Slice 17) |
| `schema_slice13.sql` (10 KB) | Schema | (Additional domain) | YES |
| `schema_slice14.sql` (24 KB) | Schema | Payment gateway & webhooks | YES |
| `schema_slice15.sql` (28 KB) | Schema | Helpdesk & SLA | YES |
| `schema_slice16.sql` (41 KB) | Schema | Committee governance & budgets | YES |
| `schema_slice17.sql` (72 KB) | Schema | Security refactoring master | YES |
| `schema_slice18.sql` (27 KB) | Schema | (Additional domain) | YES |
| `schema_slice19.sql` (29 KB) | Schema | Daily helpers & staff mappings | YES |
| `schema_slice20.sql` (27 KB) | Schema | NOC & Move-Out management | YES |
| `schema_slice21.sql` (39 KB) | Schema | Security gate, blacklist, AMC, vendor passes | YES (LOCKED) |
| `schema_slice22.sql` (26 KB) | Schema | Rule violations, fines, dispute management | **NO — IMPLEMENTED / NOT VERIFIED** |
| `verify_slice1.sql` – `verify_slice21.sql` | Verification | Sequential test suites | YES (Slices 1–21) |
| `verify_slice22.sql` (37 KB) | Verification | 60 assertions S22-001–S22-060 | **NO — AUTHORED / NOT EXECUTED** |
| `schema_phase2.sql` (83 KB) | Schema | Legacy phase 2 schema | Historical |
| `drop_tables.sql` | Utility | Table teardown | Scratch |
| `test_runner.js` (95 KB) | Runner | Node.js test executor | Active |
| `test_runner_pg.sql` (64 KB) | Runner | PostgreSQL-native test runner | Active |
| `SLICE3_IMPLEMENTATION_PLAN.md` | Plan | Slice 3 plan (inside database/) | Historical |
| `SLICE5_IMPLEMENTATION_PLAN.md` | Plan | Slice 5 plan (inside database/) | Historical |

### 2.3 Application Source (`src/`)

| File | Size | Purpose |
| :--- | :---: | :--- |
| `App.jsx` | 235 KB | Main React application — all UI and RPC calls |
| `supabase.js` | 135 KB | Supabase client configuration and RPC wrappers |
| `main.jsx` | 563 B | React entry point |
| `index.css` | 15 KB | Global styles |
| `App.css` | 51 B | App-level styles |

### 2.4 Scratch Directory (`scratch/`) — Key Files

| File | Purpose |
| :--- | :--- |
| `run_all.ps1` – `run_all20.ps1` | PowerShell verification runners for Slices 1–20 |
| `functions_inventory.txt` | Snapshot of deployed function catalog |
| `schema_inventory.txt` | Snapshot of schema objects |
| `schema_out.txt` | Schema extraction output |
| `test_all_slices.js` | Full suite orchestrator |
| Various `fix_*.js`, `restore*.js` | Historical development utility scripts |

> **OBSERVATION:** No `run_all21.ps1` or `run_all22.ps1` found in `scratch/`. Slice 21 has no runner script in this directory (Slice 21 verification was presumably run directly). Slice 22 has no runner script yet.

### 2.5 Governance & Security Plan Artifacts (Top-Level)

| File | Type | Slice | Locked? |
| :--- | :---: | :---: | :---: |
| `SLICE21_SECURITY_LOCK.md` | Lock Record | 21 | YES |
| `SLICE21_FINAL_SECURITY_PLAN.md` | Security Plan | 21 | YES (**HASH MISMATCH — SEE SECTION 3**) |
| `SLICE21_FINAL_FORENSIC_SECURITY_PLAN_REVISION_10.1.md` | Security Plan Rev | 21 | Historical |
| `SLICE21_FINAL_PRE_IMPLEMENTATION_FORENSIC_SECURITY_PLAN.md` | Pre-impl plan | 21 | Historical |
| `SLICE21_FINAL_PRE_IMPLEMENTATION_FORENSIC_SECURITY_PLAN_REVISION.md` | Pre-impl plan rev | 21 | Historical |
| `SLICE22_FINAL_SECURITY_PLAN.md` | Security Plan | 22 | No |
| `SLICE22_FORENSIC_DISCOVERY_REPORT.md` | Discovery | 22 | No |
| `SLICE22_IMPLEMENTATION_REPORT.md` | Impl Report | 22 | No |
| `SLICE22_INDEPENDENT_FORENSIC_SECURITY_AUDIT.md` | Audit | 22 | No |
| `SLICE22_PRE_IMPLEMENTATION_AUTHORIZATION_GATE.md` | Auth Gate | 22 | No |
| `SLICE22_MICRO_REMEDIATION_AND_VERIFICATION_CORRECTION_PLAN.md` | Remediation Plan | 22 | No |
| `SLICE22_MICRO_REMEDIATION_AND_VERIFICATION_CORRECTION_PLAN_FINAL.md` | Remediation Plan (final) | 22 | No |
| `SLICE22_MICRO_REMEDIATION_AND_VERIFICATION_CORRECTION_PLAN_REVISED.md` | Remediation Plan (rev) | 22 | No |
| `SLICE22_MICRO_REMEDIATION_INDEPENDENT_FORENSIC_AUDIT.md` | Micro-rem audit | 22 | No |
| `SLICE22_VERIFICATION_SUITE_INDEPENDENT_FORENSIC_AUDIT.md` | Verification audit | 22 | No |
| `SLICE20_SECURITY_LOCK.md` | Lock Record | 20 | YES |
| `SLICE19_SECURITY_LOCK.md` | Lock Record | 19 | YES |
| `SLICE20_REVISION_4.53_*` | Plan | 20 | YES (Hash locked) |
| `SLICE20_REVISION_4.48_*` | Plan | 20 | YES (Hash locked) |
| `SLICE2_CORRECTED_FINANCIAL_SERIALIZATION_REMEDIATION_PLAN.md` | Financial Plan | 2 | YES (Hash locked) |
| `SLICE2_EXPLICIT_GOVERNANCE_VARIANCE_AUTHORIZATION.md` | Governance | 2 | YES (Hash locked) |

---

## 3. LOCKED ARTIFACT HASH VERIFICATION

### 3.1 Slice 21 Authoritative Hashes (from SLICE21_SECURITY_LOCK.md)

All hashes were re-computed on 2026-09-10 using `Get-FileHash -Algorithm SHA256` on the Windows PowerShell host.

#### Slice 21 Core Files

| File | Expected Hash (from Lock Record) | Observed Hash (2026-09-10) | Result |
| :--- | :--- | :--- | :---: |
| `database/schema_slice21.sql` | `8276FB539304820450B673084210A7ADD30294A09356D585AAFC7C8E418BF190` | `8276FB539304820450B673084210A7ADD30294A09356D585AAFC7C8E418BF190` | ✅ **MATCH** |
| `database/verify_slice21.sql` | `2985F7A632039C4C6A30E83CBB9EA847A2E069EE89F42F51E8D7C01874422925` | `2985F7A632039C4C6A30E83CBB9EA847A2E069EE89F42F51E8D7C01874422925` | ✅ **MATCH** |
| `SLICE21_FINAL_SECURITY_PLAN.md` | `87CB680A8C7C56F20E641F46E89BFD646B939FA6E6EF3FC8C9B11602B6CD6516` | `FFB20A9C72D8F8109DBDDA8EFDBBF6D2AB9CEBFF2C652E82FD7A343243478DE1` | ❌ **MISMATCH** |

> [!CAUTION]
> **FORENSIC FINDING F-HASH-01 — CRITICAL HASH MISMATCH**
>
> `SLICE21_FINAL_SECURITY_PLAN.md` observed hash (`FFB20A9C...78DE1`) does NOT match the authoritative reference hash recorded in `SLICE21_SECURITY_LOCK.md` (`87CB680A...D6516`).
>
> **This is a DISCREPANCY. No repair was performed. No file was modified.**
>
> Possible explanations (in order of likelihood):
> 1. The file was updated after the lock record was created (most likely — the lock record may reference a prior revision of the plan).
> 2. Line-ending normalization occurred (CRLF vs LF conversion on Windows).
> 3. BOM insertion by a text editor.
> 4. Intentional or unintentional post-lock modification.
>
> **Required Action:** Governance review must determine whether this mismatch is acceptable (e.g., the lock record pre-dates a plan cleanup pass) or whether it constitutes a material lock violation. No mutation of any file should occur until governance has adjudicated this finding.
>
> The two immutable files `database/schema_slice21.sql` and `database/verify_slice21.sql` — which contain the actual deployed database code — **match their authoritative hashes exactly**. The functional security implementation of Slice 21 is therefore confirmed intact.

#### Historical Locked Artifacts (from SLICE21_SECURITY_LOCK.md)

| File | Expected Hash | Observed Hash | Result |
| :--- | :--- | :--- | :---: |
| `database/schema_slice20.sql` | `EFA25D7EFC2587A93A3A0DA75661648684BF50581C6C4A942D3F4ECF5A06B6E7` | `EFA25D7EFC2587A93A3A0DA75661648684BF50581C6C4A942D3F4ECF5A06B6E7` | ✅ **MATCH** |
| `database/verify_slice20.sql` | `39F96A29164FDCC94D14BE356C6887CD23A692B8D657605C354D5C692E47CF71` | `39F96A29164FDCC94D14BE356C6887CD23A692B8D657605C354D5C692E47CF71` | ✅ **MATCH** |
| `database/schema_slice2.sql` | `191AC5353DEED19DBBAB1AFBE1DB2A272C6D45A599760CF707ACE3D5135AFA49` | `191AC5353DEED19DBBAB1AFBE1DB2A272C6D45A599760CF707ACE3D5135AFA49` | ✅ **MATCH** |
| `database/verify_slice2.sql` | `66585EB71D36FEBAC59297101598A1D56828C60AFDCDE9AD75C9063C7FF191F8` | `66585EB71D36FEBAC59297101598A1D56828C60AFDCDE9AD75C9063C7FF191F8` | ✅ **MATCH** |
| `SLICE2_CORRECTED_FINANCIAL_SERIALIZATION_REMEDIATION_PLAN.md` | `767656132833CE386FA02BB6F7A5556D62668210AD8E2906886978482230D9E6` | `767656132833CE386FA02BB6F7A5556D62668210AD8E2906886978482230D9E6` | ✅ **MATCH** |
| `SLICE2_EXPLICIT_GOVERNANCE_VARIANCE_AUTHORIZATION.md` | `75BB72D848D841EC41BBB3B83525AD16272774B142A31EA58CD77D5B765A0B2C` | `75BB72D848D841EC41BBB3B83525AD16272774B142A31EA58CD77D5B765A0B2C` | ✅ **MATCH** |
| `SLICE20_REVISION_4.53_FINAL_FORENSIC_BYTE_SAFE_AUTHORITY_PRESERVATION.md` | `99F46FF7C7463E1E594F89C9C7C83FB7A15BEC8E9CBF93B9E7636D517210FE24` | `99F46FF7C7463E1E594F89C9C7C83FB7A15BEC8E9CBF93B9E7636D517210FE24` | ✅ **MATCH** |
| `SLICE20_REVISION_4.48_BYTE_SAFE_CLEAN_SECURITY_PLAN.md` | `A54904A4095112698FE5C5103F913C8359924480614AF3195889A2D0E29C499E` | `A54904A4095112698FE5C5103F913C8359924480614AF3195889A2D0E29C499E` | ✅ **MATCH** |

**Summary:** 10 of 11 locked artifact hashes match. 1 hash mismatch (`SLICE21_FINAL_SECURITY_PLAN.md`).

### 3.2 Slice 22 File Hashes (Informational — Not Yet in Lock Record)

| File | SHA-256 Hash | Status |
| :--- | :--- | :--- |
| `database/schema_slice22.sql` | `EE694DD651545CC1715F50B98C66FB9E5E1F85EE9733AD...` | Implemented / Not Locked |
| `database/verify_slice22.sql` | `639ECFAB98796A5E5ACF44FF337F9F1CC3A61CD0AC6C26...` | Authored / Not Executed |

> Note: Slice 22 hashes are recorded here for informational purposes only. These files are not yet in a locked state and their hashes are not authoritative.

---

## 4. DATABASE / SQL FORENSIC INVENTORY

### 4.1 Actual Slice 22 Implementation State (from schema_slice22.sql)

#### Tables Defined (5 new objects)

| Table | Primary Key | Key Constraints | RLS | FORCE RLS |
| :--- | :--- | :--- | :---: | :---: |
| `public.rule_violations` | `id UUID` | `chk_different_reporter_subject` (reporter ≠ subject); `status` CHECK enum (8 values); `description` length 10–2000; `violation_category` CHECK enum (7 values) | YES | YES |
| `public.violation_penalties` | `id UUID` | `violation_id UNIQUE`; `penalty_amount > 0 AND <= 50000`; `is_posted BOOLEAN` | YES | YES |
| `public.violation_disputes` | `id UUID` | `violation_id UNIQUE`; `penalty_id UNIQUE`; `resolution_status` CHECK enum (pending/upheld/reversed); `dispute_reason` length 10–2000 | YES | YES |
| `public.violation_rate_limits` | `(society_id, reporter_id)` | Composite PK | YES | YES |
| `public.violation_audit_logs` | `id UUID` | Append-only design (no UPDATE/DELETE granted) | YES | YES |

#### Helper Function

| Function | Volatility | search_path | Purpose |
| :--- | :---: | :--- | :--- |
| `public.fn_is_valid_evidence_urls(JSONB)` | IMMUTABLE | `pg_catalog, public` | Validates evidence URLs JSONB array (array type + max 10 items) |

> **OBSERVATION:** `fn_is_valid_evidence_urls` does NOT validate individual URL format (not `http://`/`https://` prefix check, not string type per element). Finding L from the micro-remediation plan identifies this as a medium-severity gap.

#### Indexes Defined

| Index | Table | Columns |
| :--- | :--- | :--- |
| `idx_rule_violations_society_status` | `rule_violations` | `(society_id, status)` |
| `idx_rule_violations_property` | `rule_violations` | `(property_id)` |
| `idx_rule_violations_subject` | `rule_violations` | `(subject_user_id)` |
| `idx_violation_penalties_deadline` | `violation_penalties` | `(appeal_deadline, is_posted)` |
| `idx_violation_audit_logs_violation` | `violation_audit_logs` | `(violation_id)` |

#### SECURITY DEFINER RPC Routines (6 routines)

| Function | SECURITY DEFINER | search_path | Caller Auth | Admin Required | Notes |
| :--- | :---: | :--- | :---: | :---: | :--- |
| `fn_report_rule_violation(...)` | YES | `pg_catalog, public` | `auth.uid()` | NO | Rate limit enforced; reporter ≠ subject |
| `fn_review_rule_violation(...)` | YES | `pg_catalog, public` | `auth.uid()` | YES | Dismiss or assess_penalty |
| `fn_dispute_rule_violation(...)` | YES | `pg_catalog, public` | `auth.uid()` | NO | Subject identity verified |
| `fn_resolve_violation_dispute(...)` | YES | `pg_catalog, public` | `auth.uid()` | YES | Upheld or reversed |
| `fn_post_violation_penalty(...)` | YES | `pg_catalog, public` | `auth.uid()` | YES | Financial posting routine |
| `process_expired_violation_appeals()` | YES | `pg_catalog, public` | `auth.uid()` | NO | **⚠ KNOWN DEFECT: auth.uid() returns NULL in background context — Finding H** |

#### RLS Policies Defined

| Policy | Table | Operation | USING Expression |
| :--- | :--- | :--- | :--- |
| `pol_rule_violations_select` | `rule_violations` | SELECT | `society_id = get_user_society_id(auth.uid()) AND (is_admin() OR reporter_id = uid OR subject_user_id = uid)` |
| `pol_violation_penalties_select` | `violation_penalties` | SELECT | `society_id = get_user_society_id(uid) AND (is_admin() OR linked to reporter/subject)` |
| `pol_violation_disputes_select` | `violation_disputes` | SELECT | `disputed_by = auth.uid() OR is_admin()` |
| `pol_violation_audit_logs_select` | `violation_audit_logs` | SELECT | `society_id = get_user_society_id(uid) AND is_admin()` |

> **OBSERVATION:** `violation_rate_limits` has NO SELECT policy — effectively deny-all for direct SELECT. `violation_disputes` admin branch has no `society_id` filter — Finding K (cross-society admin leakage).

#### Direct DML Grants/Revokes

```
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON all 5 tables FROM authenticated, anon;
GRANT EXECUTE ON all 6 RPC routines TO authenticated;
```

> **⚠ KNOWN DEFECT:** No explicit `REVOKE EXECUTE FROM PUBLIC, anon` before GRANT. PostgreSQL default PUBLIC execute may expose functions to unauthenticated callers before the GRANT re-applies. Finding I from micro-remediation plan.

#### Known CRITICAL Implementation Defects (from Micro-Remediation Audit)

| Finding | Severity | Description |
| :--- | :---: | :--- |
| **Finding C** | CRITICAL | Lock order inversion: `fn_resolve_violation_dispute` locks Rank 5 (`violation_disputes`) before Rank 3 (`rule_violations`) — deadlock risk |
| **Finding D** | CRITICAL | Lock order inversion: `fn_post_violation_penalty` acquires Rank 3 and Rank 4 BEFORE Rank 1 (`properties`) — violates global lock hierarchy |
| **Finding H** | CRITICAL | Worker `process_expired_violation_appeals` calls `fn_post_violation_penalty` which requires `auth.uid()` — returns NULL in background context |
| **Finding M** | CRITICAL | Fatal PL/pgSQL syntax error: `END BEGIN;` at line ~576 inside `process_expired_violation_appeals` — function cannot compile/execute |
| **Finding G** | HIGH | Silent error swallowing: `EXCEPTION WHEN OTHERS THEN NULL` in worker — no audit log, no failure count |
| **Finding I** | HIGH | No explicit `REVOKE EXECUTE FROM PUBLIC, anon` before grants |
| **Finding K** | HIGH | Cross-society admin RLS leakage on `violation_disputes` — no `society_id` scope in admin branch |
| **Finding F** | MEDIUM | Rate limit first-row creation race: `INSERT ON CONFLICT DO NOTHING` before `FOR UPDATE` lock |
| **Finding L** | MEDIUM | `fn_is_valid_evidence_urls` does not validate individual element string type or URL prefix |
| **Finding J** | INFO | `violation_rate_limits` lacks documented deny-all SELECT rationale |

---

## 5. VERIFICATION ARCHITECTURE

### 5.1 Framework

- Verification is **additive**: each slice's `verify_sliceN.sql` adds new assertions without destroying prior slice state.
- All verifications run inside a `BEGIN; ... COMMIT;` transaction block using a `DO $$` block.
- Results are written to a temporary table `_sliceN_test_results`.
- Each assertion is independently evaluated — a single FAIL does not abort the suite.

### 5.2 Cumulative Baseline Representation

```
Slice 1:  verify_slice1.sql  ← runs first, establishes base assertions
Slice 2:  verify_slice2.sql  ← runs after schema_slice2.sql applied
...
Slice 21: verify_slice21.sql ← 77 assertions, all PASS, LOCKED
Slice 22: verify_slice22.sql ← 60 assertions, AUTHORED, NOT EXECUTED
```

### 5.3 Slice 22 Verification Architecture Analysis

The `verify_slice22.sql` file contains 60 assertions (S22-001 through S22-060):

| Section | Assertions | Coverage | Non-Vacuous? |
| :--- | :---: | :--- | :---: |
| Schema existence | S22-001–S22-008 | Tables, indexes, functions | YES |
| Authentication blocks | S22-009–S22-015 | Unauthenticated/non-admin rejection | YES |
| Violation reporting & rate limiting | S22-016–S22-022 | Reporting workflows | YES |
| Administrative review | S22-023–S22-030 | Dismiss/assess_penalty workflows | YES |
| Resident dispute/appeal window | S22-031–S22-038 | Dispute boundaries | YES |
| Dispute resolution | S22-039–S22-046 | Upheld/reversed workflows | YES |
| Financial posting | S22-047–S22-054 | Ledger integration, idempotency | YES |
| Concurrency races F1–F5 | S22-055–S22-058 | **⚠ FAKE — hard-coded text PASS** | **NO** |
| Worker execution | S22-059 | Worker return value only | Partial |
| Governance arithmetic | S22-060 | 791 + 60 = 851 target | YES |

> **⚠ KNOWN DEFECT (Finding A):** S22-055 through S22-058 are hard-coded `INSERT INTO _slice22_test_results VALUES (..., 'PASS', ...)` statements with no actual concurrent session execution. They will always PASS regardless of whether the underlying implementation has race conditions. These are **false-pass assertions** and must be replaced before the suite can be considered non-vacuous for concurrency claims.

### 5.4 Verification Execution Status

- **Slice 21 and prior:** VERIFIED / LOCKED — 791/791 PASS confirmed.
- **Slice 22:** `verify_slice22.sql` has NOT been executed. No PASS count exists for Slice 22 yet. The target `791 + 60 = 851` is a FUTURE PLANNED target, NOT a current achieved result.

---

## 6. APPLICATION FEATURE MATRIX

| Domain | Implemented? | Security Controls | Primary DB Objects | Verification Coverage | Notes |
| :--- | :---: | :--- | :--- | :---: | :--- |
| Core entities (societies, users, properties) | YES | RLS, SECURITY DEFINER RPCs | `societies`, `users`, `user_roles`, `properties`, `units`, `tenancies` | Slice 1 | LOCKED |
| Financial core & ledger | YES | Rank-1 property lock serialization | `maintenance_charges`, `ledger_transactions`, `maintenance_policies` | Slice 2 | LOCKED |
| Amenities & maintenance | YES | SECURITY DEFINER RPCs | `amenities`, `amenity_bookings`, `technician_tickets` | Slice 3 | LOCKED |
| Advanced accounting | YES | SECURITY DEFINER RPCs | `opening_balances`, `budgets`, `bank_reconciliations` | Slice 4 | LOCKED |
| Notices, polls, vehicles, documents | YES (partial hardening) | Slice 17 refactored polls/parking | `notices`, `polls`, `parking_slots`, `vehicles`, `documents` | Slice 5 / 17 | Documents unhardened |
| Daily staff & gate passes | YES (refactored) | Slice 17 hardening | `daily_staff`, `gate_passes` | Slice 6 / 17 | LOCKED |
| Vendors & asset catalog (legacy) | YES (replaced by Slice 21) | Slice 21 replaced | `vendors`, `vendor_bank_details`, `assets`, `asset_amc` | Slice 7 / 21 | LOCKED |
| Move requests & parcels | YES (replaced) | Slice 20 / 17 replaced | `move_requests`, `parcel_logs` | Slice 8 / 17 / 20 | LOCKED |
| Staff attendance & rule violations | YES (violations legacy only) | No hardening on rule_violations | `staff_attendance_logs`, `rule_violations` | Slice 9 | **Violations unhardened — Slice 22 addresses** |
| Committee meetings | YES | SECURITY DEFINER RPCs | `meetings`, `meeting_agendas`, `meeting_resolutions` | Slice 10 | LOCKED |
| Utility meters | YES (refactored) | Slice 17 hardening | `utility_meters`, `meter_readings` | Slice 11 / 17 | LOCKED |
| SOS alerts | YES (refactored) | Slice 17 hardening | `sos_alerts` | Slice 12 / 17 | LOCKED |
| Payment gateway & webhooks | YES | SECURITY DEFINER RPCs | `payment_webhooks`, `payment_intents` | Slice 14 | LOCKED |
| Helpdesk & SLA | YES | SECURITY DEFINER RPCs | `helpdesk_tickets` | Slice 15 | LOCKED |
| Committee governance & budgets | YES | SECURITY DEFINER RPCs | `committee_resolutions`, `budget_line_items`, `facility_blackouts` | Slice 16 | LOCKED |
| Security refactoring (gate passes, parcels, SOS, meters, parking, polls) | YES | Full Slice 17 hardening | Multiple refactored objects | Slice 17 | LOCKED |
| Daily helpers & staff mappings | YES | SECURITY DEFINER RPCs | `staff_helpers`, `helper_flat_mappings`, `helper_attendance_logs` | Slice 19 | LOCKED |
| NOC & Move-Out management | YES | SECURITY DEFINER RPCs, rate limits | `noc_requests`, `noc_move_passes`, `noc_gatekeeper_rate_limits` | Slice 20 | LOCKED |
| Security gate, emergency blacklist, AMC, vendor passes | YES | SECURITY DEFINER RPCs, FORCE RLS, SHA-256 token digests | `security_blacklist_records`, `security_denial_logs`, `society_assets`, `amc_vendor_contracts`, `vendor_access_passes`, `vendor_rate_limits` | Slice 21 | LOCKED |
| Rule violations, fines, dispute management | **IMPLEMENTED / NOT VERIFIED** | SECURITY DEFINER RPCs, FORCE RLS | `rule_violations`, `violation_penalties`, `violation_disputes`, `violation_rate_limits`, `violation_audit_logs` | Slice 22 | **Known defects — micro-remediation required** |
| Digital document vault (sensitivity, access control) | NO | None | `documents` (Slice 5 legacy) | None | P1 candidate post-Slice 22 |
| SOS guard dispatch response logs | NO | None | (not implemented) | None | P2 candidate |
| Parcel pickup OTP verification | NO | None | `parcel_logs` (Slice 17 legacy) | None | P2 candidate |

---

## 7. SECURITY ARCHITECTURE INVENTORY

### 7.1 Verified Security Controls

| Control | Classification | Evidence |
| :--- | :---: | :--- |
| Society isolation via `society_id` scope on all RLS policies | VERIFIED SECURITY CONTROL | All locked slices 1–21 enforce `society_id = get_user_society_id(auth.uid())` |
| `auth.uid()` as immutable identity anchor | VERIFIED SECURITY CONTROL | All SECURITY DEFINER RPCs derive caller identity from `auth.uid()` |
| `FORCE ROW LEVEL SECURITY` on all locked tables | VERIFIED SECURITY CONTROL | Confirmed in schema_slice21.sql; pattern carried through Slices 17–21 |
| Direct DML blocked (`REVOKE INSERT/UPDATE/DELETE/TRUNCATE`) | VERIFIED SECURITY CONTROL | Applied in all Slices 17–22 |
| `SECURITY DEFINER` + `SET search_path = pg_catalog, public` | VERIFIED SECURITY CONTROL | All RPCs Slices 17–22 |
| Rank-based deadlock-free lock hierarchy | VERIFIED SECURITY CONTROL | Ranks 1–7 defined; verified in Slices 2, 21 |
| SHA-256 token digest storage (vendor passes) | VERIFIED SECURITY CONTROL | `schema_slice21.sql` — no plaintext tokens stored |
| Financial idempotency keys on `ledger_transactions` | VERIFIED SECURITY CONTROL | `schema_slice2.sql` + Slice 22 `violation_penalty:{id}` key |
| Append-only audit logs | VERIFIED SECURITY CONTROL | `violation_audit_logs`, `security_denial_logs` — no UPDATE/DELETE grants |

### 7.2 Observations

| Observation | Classification | Notes |
| :--- | :---: | :--- |
| `SLICE21_FINAL_SECURITY_PLAN.md` hash mismatch | OBSERVATION | Documented in Section 3. Functional implementation files (schema, verify) are intact. |
| No runner script for Slice 21 or Slice 22 in `scratch/` | OBSERVATION | `run_all20.ps1` exists but no `run_all21.ps1`. May indicate verification was run differently. |
| `fn_is_valid_evidence_urls` does not validate URL format per element | OBSERVATION | Finding L — medium severity; database structural validation only |
| `violation_rate_limits` lacks SELECT RLS policy | OBSERVATION | Intentional deny-all for direct table SELECT — Finding J |

### 7.3 Potential Gaps

| Gap | Classification | Severity |
| :--- | :---: | :---: |
| Slice 22 lock order inversions (Finding C, D) | POTENTIAL GAP | CRITICAL — must be fixed before verification |
| Slice 22 worker `auth.uid()` incompatibility (Finding H) | POTENTIAL GAP | CRITICAL — function will fail in background context |
| Slice 22 fatal syntax error in worker (Finding M) | POTENTIAL GAP | CRITICAL — function cannot execute |
| Slice 22 `PUBLIC` EXECUTE not explicitly revoked (Finding I) | POTENTIAL GAP | HIGH |
| Slice 22 cross-society admin RLS leakage on `violation_disputes` (Finding K) | POTENTIAL GAP | HIGH |
| Slice 22 concurrency assertions S22-055–S22-058 are non-vacuous (Finding A) | POTENTIAL GAP | HIGH — false-pass risk |
| `documents` table lacks sensitivity classification and access audit trail | POTENTIAL GAP | MEDIUM — post-Slice 22 domain |

---

## 8. CROSS-SLICE DEPENDENCY MAP

### 8.1 Shared Objects Used by Multiple Slices

| Object | Owner Slice | Used By Slices | Locked? | Future Change Risk |
| :--- | :---: | :--- | :---: | :---: |
| `public.societies` | Slice 1 | ALL | YES | HIGH — any change breaks all slices |
| `public.properties` | Slice 1 | ALL (financial anchor) | YES | CRITICAL — Rank-1 lock anchor |
| `public.users` | Slice 1 | ALL | YES | HIGH |
| `public.user_roles` | Slice 1 | ALL (is_admin(), get_user_society_id()) | YES | HIGH |
| `public.maintenance_charges` | Slice 2 | Slice 22 (fine posting) | YES | MEDIUM — Slice 22 inserts rows |
| `public.ledger_transactions` | Slice 2 | Slice 22 (idempotency key) | YES | MEDIUM — Slice 22 inserts rows |
| `public.fn_generate_charge` | Slice 2 | Slice 22 compatibility | YES | LOW — not called; compatibility only |
| `public.is_admin()` | Slice 17 (or prior) | Slices 17–22 | YES | HIGH — used in all RPC authorization checks |
| `public.get_user_society_id()` | Slice 17 (or prior) | Slices 17–22 | YES | HIGH — used in all society isolation checks |
| `public.rule_violations` | Slice 9 (legacy) / Slice 22 (hardened) | Slice 22 | NO | HIGH — Slice 22 replaces with SECURITY DEFINER model |
| `public.violation_penalties` | Slice 22 | Slice 22 | NO | N/A |
| `public.violation_disputes` | Slice 22 | Slice 22 | NO | N/A |
| `public.violation_rate_limits` | Slice 22 | Slice 22 | NO | N/A |
| `public.violation_audit_logs` | Slice 22 | Slice 22 | NO | N/A |

### 8.2 Slice 22 → Slice 2 Financial Compatibility

The `fn_post_violation_penalty` routine (once lock order is corrected per Finding D) integrates with Slice 2 by:
1. Acquiring the Rank-1 `properties` row lock first (matching `fn_generate_charge` serialization anchor).
2. Inserting into `maintenance_charges` (Rank 6) and `ledger_transactions` (Rank 7).
3. Using server-controlled idempotency key `violation_penalty:{penalty_id}`.

Zero modification to any Slice 2 object is required. The integration is additive.

---

## 9. CANDIDATE FUTURE SLICE 22+ AREAS

> Slice 22 (Rule Violations, Fines, Disputes) is already implemented. The following candidates apply to a hypothetical future Slice 23+ after Slice 22 is locked.

| Candidate | Priority | Why It Matters | Existing Coverage | Potential Security Impact | Dependencies |
| :--- | :---: | :--- | :--- | :---: | :--- |
| **Digital Document Vault** (sensitivity levels, access audit, short-lived presigned URLs) | **P1** | `documents` table has no sensitivity classification, no access audit trail, no short-lived URL issuance. Client can access documents without RPC gateway. | Slice 5 (legacy, unhardened) | HIGH | Slices 1, 5 |
| **SOS Guard Response Dispatch Logs** (`sos_responder_logs`, guard ACK tracking) | **P2** | No guard acknowledgement or dispatch tracking exists in the hardened Slice 17 SOS model | Slice 12/17 (partial) | MEDIUM | Slices 12, 17 |
| **Parcel Pickup OTP Verification** (6-digit OTP, unclaimed expiration worker) | **P2** | Slice 17 hardened parcel collection with code, but the plan noted gaps in OTP issuance to residents | Slice 8/17 (partial) | MEDIUM | Slices 8, 17 |
| **Visitor Pre-Registration & Access Token Issuance** | **P3** | `visitor_logs` (Slice 3) lacks advance registration, QR/OTP for gated entry | Slice 3 (partial) | LOW–MEDIUM | Slices 1, 3 |

---

## 10. FINDINGS / DISCREPANCIES

### F-HASH-01 — CRITICAL: Hash Mismatch on `SLICE21_FINAL_SECURITY_PLAN.md`

- **Expected:** `87CB680A8C7C56F20E641F46E89BFD646B939FA6E6EF3FC8C9B11602B6CD6516`
- **Observed:** `FFB20A9C72D8F8109DBDDA8EFDBBF6D2AB9CEBFF2C652E82FD7A343243478DE1`
- **Affected File:** `SLICE21_FINAL_SECURITY_PLAN.md`
- **Functional Impact:** NONE — `database/schema_slice21.sql` and `database/verify_slice21.sql` both match their authoritative hashes. The deployed implementation is intact.
- **Plan Impact:** The security plan document was modified after the lock hash was recorded, or the lock hash was recorded against an earlier version of the document.
- **Action Required:** Governance adjudication. Do NOT repair without explicit authorization.

### F-IMPL-01 — CRITICAL: Slice 22 Implementation Has Known Defects (Findings C, D, H, M)

- Slice 22 schema file `database/schema_slice22.sql` contains 4 CRITICAL-severity defects documented in `SLICE22_MICRO_REMEDIATION_AND_VERIFICATION_CORRECTION_PLAN.md`.
- The file exists on disk but contains a fatal PL/pgSQL syntax error (`END BEGIN;`) and lock order inversions.
- **The schema has not been executed against the live database** (verification has not passed — 0 executions recorded).
- **Action Required:** Micro-remediation must be authorized and executed before verification can run.

### F-VERIF-01 — HIGH: Fake Concurrency Assertions in `verify_slice22.sql`

- S22-055 through S22-058 are hard-coded `PASS` insertions with no actual concurrent session execution.
- These assertions will always PASS regardless of implementation correctness.
- **Action Required:** Replace with genuine multi-session concurrency harness (Node.js or coordination table mechanism).

### F-DISC-01 — OBSERVATION: No `run_all21.ps1` in `scratch/`

- The PowerShell runner series goes to `run_all20.ps1`. No `run_all21.ps1` exists.
- This may indicate Slice 21 verification was run via a different mechanism.
- **Action Required:** None mandatory. Document for completeness.

---

## 11. BASELINE INTEGRITY STATEMENT

```
POTENTIAL BASELINE MUTATION / DISCREPANCY DETECTED — SEE FINDINGS.
```

**Specifically:**

The forensic inventory identified one hash discrepancy:

- `SLICE21_FINAL_SECURITY_PLAN.md` observed hash does not match the authoritative reference hash in `SLICE21_SECURITY_LOCK.md`.

The two authoritative functional implementation files (`database/schema_slice21.sql` and `database/verify_slice21.sql`) match their locked hashes exactly. All other 8 historically locked artifacts also match their reference hashes exactly.

The 791/791 PASS baseline is based on the database implementation files, not the plan documentation. The functional integrity of Slice 21 is confirmed. The plan document discrepancy requires governance review but does not by itself invalidate the 791/791 baseline.

---

## 12. GOVERNANCE STATUS

```
SLICE 21:
FORMALLY LOCKED / IMMUTABLE (database/schema_slice21.sql and database/verify_slice21.sql confirmed intact)
PLAN DOCUMENT HASH DISCREPANCY — REQUIRES GOVERNANCE REVIEW

CURRENT PROJECT BASELINE:
791 / 791 PASS — 100% LOCKED / IMMUTABLE

SLICE 22 IMPLEMENTATION:
IMPLEMENTED (database/schema_slice22.sql exists with CRITICAL defects)
NOT VERIFIED (verify_slice22.sql authored but 0 executions performed)
NOT LOCKED

SLICE 22 MICRO-REMEDIATION:
PLAN-ONLY (SLICE22_MICRO_REMEDIATION_AND_VERIFICATION_CORRECTION_PLAN*.md)
NOT AUTHORIZED FOR EXECUTION (this inventory task does not constitute authorization)

SLICE 22 SECURITY LOCK:
NOT AUTHORIZED

BASELINE MUTATION:
PROHIBITED — NO MUTATION PERFORMED IN THIS INVENTORY
```

---

## 13. EXACT FILES INSPECTED (READ-ONLY)

1. `SLICE21_SECURITY_LOCK.md`
2. `SLICE21_FINAL_SECURITY_PLAN.md`
3. `SLICE22_FINAL_SECURITY_PLAN.md`
4. `SLICE22_IMPLEMENTATION_REPORT.md`
5. `SLICE22_FORENSIC_DISCOVERY_REPORT.md`
6. `SLICE22_INDEPENDENT_FORENSIC_SECURITY_AUDIT.md`
7. `SLICE22_PRE_IMPLEMENTATION_AUTHORIZATION_GATE.md`
8. `SLICE22_MICRO_REMEDIATION_AND_VERIFICATION_CORRECTION_PLAN.md`
9. `database/schema_slice22.sql`
10. `database/verify_slice22.sql`
11. `database/` (directory listing)
12. `src/` (directory listing)
13. `scratch/` (directory listing)
14. Root directory listing

---

## 14. READ-ONLY OPERATIONS PERFORMED

1. `list_dir` on project root — read directory structure
2. `list_dir` on `database/` — enumerate all SQL files
3. `list_dir` on `src/` — enumerate application source
4. `list_dir` on `scratch/` — enumerate scratch scripts
5. `view_file` on `SLICE21_SECURITY_LOCK.md` — read lock hashes and governance state
6. `view_file` on `SLICE22_FINAL_SECURITY_PLAN.md` — read Slice 22 plan (288 lines)
7. `view_file` on `SLICE22_IMPLEMENTATION_REPORT.md` — read implementation status
8. `view_file` on `SLICE22_FORENSIC_DISCOVERY_REPORT.md` — read discovery report
9. `view_file` on `SLICE22_INDEPENDENT_FORENSIC_SECURITY_AUDIT.md` — read audit
10. `view_file` on `SLICE22_PRE_IMPLEMENTATION_AUTHORIZATION_GATE.md` — read gate
11. `view_file` on `SLICE22_MICRO_REMEDIATION_AND_VERIFICATION_CORRECTION_PLAN.md` — read remediation findings
12. `view_file` on `database/schema_slice22.sql` — read full schema (648 lines)
13. `view_file` on `database/verify_slice22.sql` — read full verification suite (597 lines)
14. `Get-FileHash` (SHA-256) on 11 locked artifacts — hash verification only
15. `Get-FileHash` (SHA-256) on 2 Slice 22 SQL files — informational hashing

**Zero mutations performed. Zero SQL executed. Zero files created or modified by this inventory task (except this report).**

---

## 15. FINAL FORENSIC VERDICT

```
FORENSIC INVENTORY COMPLETE — 791/791 BASELINE PRESERVED.

(WITH GOVERNANCE FINDING: SLICE21_FINAL_SECURITY_PLAN.md hash discrepancy
detected and documented. No repair performed. Functional Slice 21 implementation
files confirmed intact. Requires governance adjudication before Slice 22 lock.)
```

---

*This document was produced by a read-only forensic inventory pass. It does not constitute implementation authorization, verification authorization, or lock authorization for any slice.*
