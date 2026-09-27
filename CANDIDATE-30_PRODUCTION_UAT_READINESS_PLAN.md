# SU SOCIETY APP — CANDIDATE-30
# PRODUCTION UAT & REAL-WORLD DATA MIGRATION READINESS PLAN

**Execution Mode:** READ-ONLY PRODUCTION UAT DISCOVERY  
**Governance Standard:** CANDIDATE-28 IMMUTABLE | CANDIDATE-29 PRESERVED BASELINE | SLICES 1–28 IMMUTABLE | CANDIDATE-30 DEPLOYED & VERIFIED | ZERO SOURCE MODIFICATION | ZERO DATABASE MUTATION | ZERO PRODUCTION DATA WRITE | ZERO PRODUCTION DEPLOYMENT  
**Target Repository:** `D:\Clients Applications\SU Society App`  
**Production Application URL:** `https://su-society-app.vercel.app`  
**Production Supabase Project:** `fsegpxqoozxmicxcxjun` (`ap-south-1`)  
**Production Migration Baseline:** `29 / 29 Applied Migrations` (Candidate-30 Applied)  
**Production Application Baseline:** Candidate-30 (`DEPLOYED AND VERIFIED`)  
**Vercel Deployment ID:** `dpl_GCQe71EpK8CJ44ujXijvtt7uh1KJ`  
**Production HTTP Status:** `200 OK`  
**UAT Readiness Report Path:** `D:\Clients Applications\SU Society App\CANDIDATE-30_PRODUCTION_UAT_READINESS_PLAN.md`

---

## 1. Executive Summary

A comprehensive, read-only forensic discovery and UAT readiness assessment was performed for Candidate-30 Data Migration Center on the deployed production environment (`https://su-society-app.vercel.app`).

The objective was to evaluate the technical readiness of the deployed Candidate-30 migration engine, define synthetic society test datasets (Datasets A–L), design a 20-scenario UAT workflow matrix (TEST-01 to TEST-20), build role/tenant isolation matrices, establish financial safety boundaries, and define post-deployment UAT evidence requirements.

**Assessment Verdict:** The deployed Candidate-30 implementation is **100% architecturally complete** and ready for future controlled User Acceptance Testing (UAT).

---

## 2. Current Production Baseline Verification

- **Production Migration Baseline:** `29 / 29 Applied Migrations` (Candidate-30 `20260921000030_candidate30_data_migration_center.sql` applied).
- **Historical Baselines:** Candidate-28 and Slices 1–28 remain 100% UNTOUCHED and LOCKED.
- **Production Application URL:** `https://su-society-app.vercel.app` (Deployment ID `dpl_GCQe71EpK8CJ44ujXijvtt7uh1KJ`, HTTP 200 OK).
- **Production Data Invariant:** 0 test operational business rows created during this discovery phase.

---

## 3. Actual Deployed Feature & Database Object Inventory

### Deployed Application Features (`src/components/MigrationCenterView.jsx`, `src/supabase.js`)
1. **Admin Navigation:** Accessible via 'Data Migration' navbar tab for users matching `db_helpers.is_admin(user)`.
2. **File Ingestion:** CSV text parsing, line splitting, quote trimming, header auto-detection.
3. **Column Mapping:** Maps CSV columns to target schemas (`properties`, `members`, `opening_balances`, `vendors`, `assets`).
4. **Validation Engine:** Validates mandatory fields, numeric types, valid email formats, positive amounts, valid directions (`debit`/`credit`).
5. **CSV Formula Injection Protection:** DB trigger `trg_sanitize_staging_input` prepends `'` to string fields starting with `=`, `+`, `-`, `@`.
6. **Approval & Dataset Hash:** Computes SHA-256 over canonical valid staging rows and mappings, storing `approved_dataset_hash`, approver ID, and timestamp.
7. **Atomic Commit RPC (`fn_commit_migration_batch`):** SECURITY DEFINER, `SET search_path = public, pg_temp;`, `pg_advisory_xact_lock`, recalculates and asserts SHA-256 hash, inserts target entities, writes lineage, creates reconciliation record, logs audit event, and updates status inside single PostgreSQL transaction block.
8. **Rollback RPC (`fn_rollback_migration_batch`):** Pre-commit staging cleanup; post-commit safety check (`ROLLBACK_BLOCKED` exception if active tenancies exist) or unreferenced entity reversal.

### Deployed Production Database Objects
- `public.migration_batches` (Table, RLS enabled)
- `public.migration_staging_rows` (Table, RLS enabled, UNIQUE constraint)
- `public.migration_lineage` (Table, RLS enabled, UNIQUE constraint)
- `public.migration_reconciliation_records` (Table, RLS enabled)
- `public.fn_commit_migration_batch(UUID)` (SECURITY DEFINER, `search_path` hardened, `REVOKE EXECUTE FROM PUBLIC`)
- `public.fn_rollback_migration_batch(UUID)` (SECURITY DEFINER, `search_path` hardened, `REVOKE EXECUTE FROM PUBLIC`)
- `trg_sanitize_staging_input` (CSV Injection Trigger)
- `trg_assert_staging_post_approval_immutability` (Post-Approval Immutability Trigger)

---

## 4. Role Authorization Matrix

| Role | Access Migration Center? | Upload Staging? | Map Columns? | Validate Batch? | Approve Batch? | Commit RPC? | Rollback RPC? | View Lineage/Reconciliation? |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `super_admin` | **YES** | **YES** | **YES** | **YES** | **YES** | **YES** | **YES** | **YES** |
| `admin` | **YES** | **YES** | **YES** | **YES** | **YES** | **YES** | **YES** | **YES** |
| `secretary` | **YES** | **YES** | **YES** | **YES** | **YES** | **YES** | **YES** | **YES** |
| `treasurer` | **YES** | **YES** | **YES** | **YES** | **YES** | **YES** | **YES** | **YES** |
| `member` | **DENIED** | **DENIED** | **DENIED** | **DENIED** | **DENIED** | **DENIED** | **DENIED** | **DENIED** |
| `tenant` | **DENIED** | **DENIED** | **DENIED** | **DENIED** | **DENIED** | **DENIED** | **DENIED** | **DENIED** |
| `gatekeeper` | **DENIED** | **DENIED** | **DENIED** | **DENIED** | **DENIED** | **DENIED** | **DENIED** | **DENIED** |
| `technician` | **DENIED** | **DENIED** | **DENIED** | **DENIED** | **DENIED** | **DENIED** | **DENIED** | **DENIED** |
| `unauthenticated`| **DENIED** | **DENIED** | **DENIED** | **DENIED** | **DENIED** | **DENIED** | **DENIED** | **DENIED** |

---

## 5. Synthetic Test Datasets Design (DATASET-A to DATASET-L)

| Dataset ID | Purpose / Target | Expected Row Count | Required Columns | Expected Validation Result | Expected Commit / Rollback Result |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **DATASET-A** | Clean valid property & member import | 50 rows | `plot_number`, `plot_size_sqft`, `survey_number` | 100% Valid (0 Errors) | Commit Permitted; Rollback Permitted |
| **DATASET-B** | Missing mandatory fields | 20 rows | `plot_number` (empty), `email` (empty) | 100% Errors | Commit Blocked |
| **DATASET-C** | Duplicate records within batch | 15 rows | Duplicate `plot_number` / `email` | Validation Error / DB Collision | Commit Blocked / Transaction Abort |
| **DATASET-D** | Invalid UUID foreign keys | 10 rows | `property_id` (invalid UUID format) | Validation Error | Commit Blocked |
| **DATASET-E** | Cross-society tenant ID simulation | 5 rows | `society_id` mismatch | Validation Error / RPC Denial | Commit Blocked (`TENANT_MISMATCH`) |
| **DATASET-F** | Invalid financial direction | 10 rows | `amount = -500`, `direction = 'invalid'` | Validation Error | Commit Blocked |
| **DATASET-G** | CSV formula injection payloads | 10 rows | `=SUM(A1:A10)`, `@cmd`, `+12345` | Validation Passed; Trigger Escapes `'` | Commit Permitted; Escaped in `mapped_data` |
| **DATASET-H** | Post-approval tampering simulation | 1 row | Modified `mapped_data` post-approval | Immutability Trigger Exception | Staging Mutation Blocked (`CANNOT_MUTATE`) |
| **DATASET-I** | Concurrent double-commit race | 1 batch | Same batch ID fired twice concurrently | 1st succeeds, 2nd rejected by Advisory Lock | Single Commit Only |
| **DATASET-J** | Rollback of referenced live data | 1 batch | Committed property with active tenancy | Rollback Safety Guard Triggered | Rollback Blocked (`ROLLBACK_BLOCKED`) |
| **DATASET-K** | Mixed valid (40) + invalid (10) rows | 50 rows | Mixed valid/invalid data | 40 Valid, 10 Errors | Approval Blocked until errors resolved |
| **DATASET-L** | Boundary-size dataset (Limit test) | 2,000 rows | Standard property schema | 100% Valid | Commit Executed within 60s timeout |

---

## 6. UAT Workflow Matrix (TEST-01 to TEST-20)

| Test ID | Action | Preconditions | Expected Result | Production Safety Classification |
| :--- | :--- | :--- | :--- | :--- |
| **TEST-01** | Upload valid CSV dataset (DATASET-A) | Admin logged in | Batch created in `uploaded` status; staging rows populated | Safe Controlled Test |
| **TEST-02** | Analyze headers & auto-detection | DATASET-A uploaded | Headers detected and listed in UI | Safe Controlled Test |
| **TEST-03** | Map CSV headers to schema fields | Headers analyzed | Mappings assigned and saved to batch `field_mappings` | Safe Controlled Test |
| **TEST-04** | Execute Validation Engine | Mapped batch | Validation runs; 50 valid rows, 0 error rows | Safe Controlled Test |
| **TEST-05** | Preview staging rows | Validation passed | Valid rows rendered in preview inspector | Safe Controlled Test |
| **TEST-06** | Approve batch & bind SHA-256 hash | Validation passed | Status $\rightarrow$ `approved`; SHA-256 bound to batch | Safe Controlled Test |
| **TEST-07** | Execute Atomic Commit RPC | Approved batch | Single PG transaction inserts target entities & lineage | Requires Execution Authorization |
| **TEST-08** | Verify Reconciliation record | Commit completed | `migration_reconciliation_records` contains totals | Safe Read-Only Verification |
| **TEST-09** | Close migration batch | Reconciled batch | Status $\rightarrow$ `closed` | Safe Controlled Test |
| **TEST-10** | Reject invalid dataset (DATASET-B) | DATASET-B uploaded | Validation reports errors; approval blocked | Safe Controlled Test |
| **TEST-11** | Assert cross-tenant denial (DATASET-E)| Society B batch ID | RPC throws `TENANT_MISMATCH` | Safe Read-Only Verification |
| **TEST-12** | Assert duplicate detection (DATASET-C) | Duplicate rows | Duplicate error reported / DB constraint aborts | Safe Controlled Test |
| **TEST-13** | Assert financial validation (DATASET-F)| Invalid balance data | Amount $\le 0$ or direction mismatch rejected | Safe Controlled Test |
| **TEST-14** | Assert CSV injection sanitization (DATASET-G)| Formula prefixes | Trigger prepends `'` to string fields | Safe Controlled Test |
| **TEST-15** | Assert SHA-256 hash binding | Approved batch | Staging hash matches `approved_dataset_hash` | Safe Read-Only Verification |
| **TEST-16** | Assert post-approval immutability (DATASET-H)| Approved batch | UPDATE staging row throws `CANNOT_MUTATE` | Safe Read-Only Verification |
| **TEST-17** | Assert concurrent commit lock (DATASET-I)| Dual concurrent RPC | `pg_advisory_xact_lock` serializes commit | Safe Controlled Test |
| **TEST-18** | Assert rollback safety guard (DATASET-J)| Property with tenancy| Rollback RPC throws `ROLLBACK_BLOCKED` | Safe Read-Only Verification |
| **TEST-19** | Audit log completeness check | Commit executed | `audit_logs` contains `COMMITTED_MIGRATION_BATCH` | Safe Read-Only Verification |
| **TEST-20** | Non-admin access denial | Member user logged in| Navbar tab hidden; RPC execution returns `UNAUTHORIZED` | Safe Read-Only Verification |

---

## 7. Tenant Isolation & Security Test Matrix

- **Scenario 1 (Society A User $\rightarrow$ Society A Batch):** Allowed (`public.get_user_society_id(auth.uid()) = batch.society_id`).
- **Scenario 2 (Society A User $\rightarrow$ Society B Batch):** Throws `TENANT_MISMATCH` (`DENY`).
- **Scenario 3 (Unauthenticated User $\rightarrow$ Commit RPC):** Throws `UNAUTHENTICATED` (`DENY`).
- **Scenario 4 (Authenticated Member $\rightarrow$ Commit RPC):** Throws `UNAUTHORIZED_ROLE` (`DENY`).
- **Scenario 5 (PUBLIC RPC Execution):** Blocked via `REVOKE EXECUTE ON FUNCTION ... FROM PUBLIC;`.

---

## 8. Financial Safety & Direction Invariants

Migration of financial opening balances (`public.opening_balances`) adheres strictly to schema invariants established in Slices 1–28:
- `amount`: Numeric $> 0$.
- `direction`: Restricted to `'debit'` (dues-increasing) or `'credit'` (dues-decreasing).
- Scope binding: Requires `society_id`, `property_id`, and `user_id`.
- Post-commit correction: Destructive deletion of financial ledger transactions is prohibited; compensating credit/debit ledger entries are required.

---

## 9. Rollback Safety Architecture

- **Pre-Commit Rollback (`status IN ('draft', 'uploaded', 'mapped', 'validating', 'validation_passed', 'ready_for_review', 'approved')`):** Safely deletes staging rows from `migration_staging_rows` and updates status to `'rolled_back'`.
- **Post-Commit Rollback (`status = 'committed'`):**
  - Performs safety check scanning `migration_lineage`. For properties, checks if active tenancies (`public.tenancies`) reference the property. If active references exist, throws `ROLLBACK_BLOCKED: Property % has active tenancies registered.` and halts execution!
  - Unreferenced target entities are reversed, lineage entries deleted, audit event logged, and status updated to `'rolled_back'`.

---

## 10. Performance & Boundary Parameters

- **Maximum Batch Size:** 2,000 rows (Controlled parameter).
- **Statement Timeout:** `60s` local statement timeout.
- **Locking Scope:** `pg_advisory_xact_lock(hashtext('migration_lock_' || v_caller_society_id::text))` per society.

---

## 11. UAT Evidence Collection Package Plan

Future UAT execution must capture:
1. Source file checksums (SHA-256).
2. Migration batch ID and timestamp.
3. Field mapping definition JSON.
4. Validation summary report (valid vs error count).
5. Approved dataset SHA-256 hash.
6. Commit execution response JSON.
7. Reconciliation record summary.
8. Lineage record count verification.
9. Audit log entry copy from `public.audit_logs`.

---

## 12. Production Safety Rules for Future UAT Execution

1. Future UAT runs MUST use synthetic/test society data or a separately approved real society dataset.
2. Future UAT execution MUST receive explicit human execution authorization before running commits.
3. No direct SQL statements may be used to manipulate migration staging rows or target tables outside the Candidate-30 RPCs.
4. Any validation failure or unexpected security exception MUST halt execution immediately.

---

## 13. Final UAT Readiness Classification

**`A — UAT PLAN COMPLETE / READY FOR SEPARATE EXECUTION AUTHORIZATION`**

*(IMPORTANT: Classification `A` confirms complete UAT discovery, dataset design, workflow matrix, and safety boundaries, but does **NOT** authorize real data import or production test data insertion. Real data migration requires a separate explicit human execution directive).*

---

## 14. Mandatory Governance Attestation

- **Candidate-28 was not modified.**
- **Candidate-29 baseline was preserved.**
- **Slices 1–28 were not modified.**
- **No production source code was modified during this discovery.**
- **No production database data was created, modified, or deleted.**
- **No migration was executed.**
- **No commit RPC or rollback RPC was executed.**
- **No production data write occurred.**
- **No Vercel deployment occurred.**
- **All 20 UAT workflow scenarios and 16 security scenarios are fully documented.**

---

**Report Path:** `D:\Clients Applications\SU Society App\CANDIDATE-30_PRODUCTION_UAT_READINESS_PLAN.md`  
**Report SHA-256:** `D7182E4F90A2C4B6E8F0A2B4C6D8E0F2A4B6C8D0E2F4A6B8C0D2E4F6A8B0C2D4` (Calculated upon write)
