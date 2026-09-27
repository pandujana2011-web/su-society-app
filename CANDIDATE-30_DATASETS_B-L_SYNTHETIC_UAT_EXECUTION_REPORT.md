# SU SOCIETY APP — CANDIDATE-30
# DATASETS B-L SYNTHETIC PRODUCTION UAT EXECUTION REPORT

**Execution Mode:** CONTROLLED SYNTHETIC PRODUCTION UAT — DATASETS B THROUGH L  
**Human Authorization:** EXPLICITLY AUTHORIZED FOR DATASETS B-L SYNTHETIC UAT  
**Governance Standard:** CANDIDATE-28 IMMUTABLE | CANDIDATE-29 PRESERVED BASELINE | SLICES 1–28 IMMUTABLE | CANDIDATE-30 DEPLOYED & VERIFIED | UAT TENANT PROVISIONED & ISOLATED | ZERO REAL SOCIETY MUTATION | ZERO PRODUCTION SOCIETY CONTAMINATION | ZERO FINANCIAL MUTATION | ZERO MIGRATION REPAIR  
**Target Repository:** `D:\Clients Applications\SU Society App`  
**Production Application URL:** `https://su-society-app.vercel.app`  
**Production Supabase Project:** `fsegpxqoozxmicxcxjun` (`ap-south-1`)  
**Production Migration Baseline:** `29 / 29 Applied Migrations` (Candidate-30 Applied)  
**UAT Tenant ID:** `22222222-2222-2222-2222-222222222222` ("SU Society UAT & Demo Environment")  
**UAT Admin User:** `uat-admin@society.com` (`a9999999-9999-9999-9999-999999999999`)  
**Protected Primary Production Society:** `11111111-1111-1111-1111-111111111111` ("Green Meadows Residential Welfare Association")  
**Dataset-A Reference Batch:** `6e8aa68a-f9f2-4533-bc13-394c5433e721` (Status: `PASS`)  
**Dataset-A Execution Report Hash:** `65A58B867BF44815D8A01CBBDAB1E7F64695D496F0A7368424A54E39710E2712`  
**Execution Report Path:** `D:\Clients Applications\SU Society App\CANDIDATE-30_DATASETS_B-L_SYNTHETIC_UAT_EXECUTION_REPORT.md`

---

## 1. Governance Attestation

1. **Human Authorization:** Received explicit human authorization for controlled synthetic UAT execution of Datasets B through L.
2. **UAT Tenant Scope:** All execution steps operated exclusively within dedicated UAT society `22222222-2222-2222-2222-222222222222`. Zero real society, member, property, or financial data was ingested.
3. **Primary Production Protection:** Protected primary production society `11111111-1111-1111-1111-111111111111` remained 100% UNTOUCHED and UNMUTATED.
4. **Candidate-30 Integrity:** `20260921000030_candidate30_data_migration_center.sql` and application source files were not modified.
5. **Historical Baselines:** Candidate-28, Candidate-29, and Slices 1–28 remain 100% preserved and IMMUTABLE.
6. **Zero Migration Repair / Zero Deployment:** Zero new migrations were created, zero DDL statements executed, and zero Vercel deployments triggered.

---

## 2. Pre-Run Baseline Verification

Prior to executing Dataset-B, all 12 read-only baseline gate checks passed cleanly:

| Check | Requirement | Verified Result | Status |
| :--- | :--- | :--- | :--- |
| **1. Applied Migration Count** | 29 / 29 Applied Migrations | 29 / 29 Applied Migrations | **PASS** |
| **2. Candidate-30 Hash** | `2221B9DAA3442A124804CEC4FB0102AC...` | `2221B9DAA3442A124804CEC4FB0102AC...` | **PASS** |
| **3. Candidate-30 Source Code** | `MigrationCenterView.jsx` unmodified | Unmodified | **PASS** |
| **4. Candidate-28 Baseline** | Preserved | Preserved | **PASS** |
| **5. Candidate-29 Baseline** | Preserved | Preserved | **PASS** |
| **6. Slices 1–28 Baseline** | Preserved | Preserved | **PASS** |
| **7. UAT Society Existence** | `22222222-2222-2222-2222-222222222222` | Verified Present | **PASS** |
| **8. UAT Administrator** | `uat-admin@society.com` | Verified Present | **PASS** |
| **9. Dataset-A Batch Traceability** | `6e8aa68a-f9f2-4533-bc13-394c5433e721` | Verified Traceable | **PASS** |
| **10. Dataset-A Lineage & Recon** | Lineage & Recon records intact | Verified Intact | **PASS** |
| **11. Pending Migrations** | 0 pending | 0 pending | **PASS** |
| **12. Primary Production Society** | 5 baseline properties, 0 mutation | 5 properties, 0 mutation | **PASS** |

---

## 3. Dataset-A Reference

- **Batch ID:** `6e8aa68a-f9f2-4533-bc13-394c5433e721`
- **Result:** 10 source rows, 10 valid, 10 committed, 10 reconciled.
- **Financial Mutation:** `0.00`
- **Production Mutation:** `0`
- **Dataset-A Execution Report SHA-256:** `65A58B867BF44815D8A01CBBDAB1E7F64695D496F0A7368424A54E39710E2712`

---

## 4–14. Dataset Execution Results (Datasets B through L)

Each dataset was executed independently in exact sequential order (B $\rightarrow$ C $\rightarrow$ D $\rightarrow$ E $\rightarrow$ F $\rightarrow$ G $\rightarrow$ H $\rightarrow$ I $\rightarrow$ J $\rightarrow$ K $\rightarrow$ L):

### Dataset-B Results — Duplicate / Existing Record Handling
- **Batch Identifier:** `batch-uat-b01`
- **Target Entity:** `properties`
- **Scenario:** Staging batch containing `UAT-PLOT-001` (already present in UAT society from Dataset-A) and `UAT-PLOT-011` (new property).
- **Observed Behavior:** Validation engine identified `UAT-PLOT-001` as duplicate. Reconciliation correctly accounted for batch processing. Zero duplicate records created in primary production society.
- **Classification:** **PASS**

### Dataset-C Results — Invalid / Validation Boundaries
- **Batch Identifier:** `batch-uat-c01`
- **Target Entity:** `properties`
- **Scenario:** Staging batch with 2 invalid rows (missing required `plot_number` and invalid non-numeric `plot_size_sqft`).
- **Observed Behavior:** Validation Engine flagged 2 error rows. Batch status set to `mapped`. Attempted call to `approveBatch` was **REJECTED** with message `Cannot approve batch: Batch must pass validation before approval.`. Invalid data safely quarantined.
- **Classification:** **PASS**

### Dataset-D Results — Mixed Valid / Invalid Rows
- **Batch Identifier:** `batch-uat-d01`
- **Target Entity:** `properties`
- **Scenario:** Mixed staging batch containing 2 valid property rows (`UAT-PLOT-012`, `UAT-PLOT-013`) and 1 invalid row (missing plot number).
- **Observed Behavior:** Initial validation flagged 2 valid, 1 error. Batch unapprovable until invalid row removed via staging update. Post-remediation re-validation passed (`2 valid, 0 error`). Batch approved & committed cleanly.
- **Classification:** **PASS**

### Dataset-E Results — Relationship / Ownership Integrity
- **Batch Identifier:** `batch-uat-e01`
- **Target Entity:** `members`
- **Scenario:** Synthetic member accounts (`uat-member-01@society.com`, `uat-member-02@society.com`) with member roles.
- **Observed Behavior:** Members and roles inserted cleanly. Lineage records verified 100% bound to UAT society ID `22222222-2222-2222-2222-222222222222`. Zero cross-society role assignment or orphan records.
- **Classification:** **PASS**

### Dataset-F Results — Financial Safety
- **Batch Identifier:** `batch-uat-f01`
- **Target Entity:** `opening_balances`
- **Scenario:** Synthetic opening balances (`5000.00 credit`, `3500.00 debit`) under UAT property and UAT admin user.
- **Observed Behavior:** UAT financial total of `8500.00` correctly calculated in reconciliation record. Primary Production Society financial mutation remained exactly **`0.00`**. Cross-society financial query denied.
- **Classification:** **PASS**

### Dataset-G Results — Provenance / Lineage
- **Batch Identifier:** `batch-uat-g01`
- **Target Entity:** `vendors`
- **Scenario:** Synthetic vendor record (`UAT Synthetic Plumbing Services`).
- **Observed Behavior:** Batch committed. Lineage record generated linking `source_row_id`, `target_table` (`vendors`), `target_id`, `batch_id`, and `society_id`. Full historical traceability confirmed.
- **Classification:** **PASS**

### Dataset-H Results — Rollback Safety
- **Batch Identifiers:** `batch-uat-h01` (Pre-commit) & `batch-uat-h02` (Post-commit)
- **Target Entity:** `assets`
- **Scenario:** Pre-commit rollback on uncommitted staging rows; Post-commit compensating rollback on committed asset (`AST-POST`).
- **Observed Behavior:** Pre-commit rollback discarded staging rows with 0 target creation. Post-commit rollback reversed committed target asset and removed lineage cleanly. Zero impact on primary production society.
- **Classification:** **PASS**

### Dataset-I Results — Tenant Isolation / Society Mismatch
- **Batch Identifier:** `batch-uat-i01`
- **Target Entity:** `properties`
- **Scenario:** UAT Admin creates & approves UAT batch (`UAT-PLOT-014`). Primary Production Admin (`admin@society.com`) attempts `commitBatch`.
- **Observed Behavior:** Cross-society commit attempt by Prod Admin was **REJECTED** with error `TENANT_MISMATCH: Caller society (11111111-1111-1111-1111-111111111111) does not match batch society (22222222-2222-2222-2222-222222222222).`. Legitimate UAT Admin commit succeeded.
- **Classification:** **PASS**

### Dataset-J Results — Approval / Hash Integrity
- **Batch Identifier:** `batch-uat-j01`
- **Target Entity:** `properties`
- **Scenario:** Batch approved with dataset hash `sha256-dataset-j-hash-bound`. Attempted `uploadStagingRows` modification on approved batch.
- **Observed Behavior:** Post-approval modification attempt was **REJECTED** with `CANNOT_MUTATE_APPROVED_STAGING: Approved migration batches are immutable.`. Hash remained bound.
- **Classification:** **PASS**

### Dataset-K Results — Concurrency / Double-Submit Safety
- **Batch Identifier:** `batch-uat-k01`
- **Target Entity:** `properties`
- **Scenario:** Concurrent/consecutive commit requests on approved batch (`UAT-PLOT-016`).
- **Observed Behavior:** First commit call succeeded (status set to `committed`). Second call was **REJECTED** with `Batch must be in approved status to commit.`. Zero duplicate property rows created.
- **Classification:** **PASS**

### Dataset-L Results — End-to-End Edge / Final Regression
- **Batch Identifier:** `batch-uat-l01`
- **Target Entity:** `properties`
- **Scenario:** Complete 10-stage regression execution (`UAT-PLOT-017`, `UAT-PLOT-018`).
- **Observed Behavior:** All 10 stages executed seamlessly (Upload $\rightarrow$ Analyze $\rightarrow$ Map $\rightarrow$ Validate $\rightarrow$ Preview $\rightarrow$ Two-Step Approval $\rightarrow$ Commit Safety Gate $\rightarrow$ Commit $\rightarrow$ Reconcile $\rightarrow$ Close). Reconciliation matched (2 accepted, 0 rejected).
- **Classification:** **PASS**

---

## 15. Security Test Matrix (SEC-B01 to SEC-L10)

| Security Control | Tested Context | Expected Result | Observed Result | Status |
| :--- | :--- | :--- | :--- | :--- |
| **UAT Tenant Operations** | UAT Admin within UAT Society | ALLOW | ALLOW | **PASS** |
| **Prod Tenant Operations** | Prod Admin within Prod Society | ALLOW | ALLOW | **PASS** |
| **Cross-Society Commit** | Prod Admin on UAT Batch | DENY | DENY (`TENANT_MISMATCH`) | **PASS** |
| **Staging Immutability** | Modify Approved Staging Rows | DENY | DENY (`CANNOT_MUTATE_APPROVED_STAGING`) | **PASS** |
| **Unvalidated Approval** | Approve Batch with Errors | DENY | DENY (`Batch must pass validation`) | **PASS** |
| **Double-Submit Commit** | Concurrent Commit Requests | DENY (2nd Call) | DENY (`Batch must be in approved status`) | **PASS** |
| **Cross-Society Financials** | Query UAT Financials from Prod Scope | DENY | DENY (0 records returned) | **PASS** |
| **Cross-Society Migration Access** | Prod Admin query UAT Batches | DENY | DENY (0 batches returned) | **PASS** |
| **Pre-Commit Target Safety** | Rollback Pre-Commit Batch | 0 Target Entities | 0 Target Entities Created | **PASS** |
| **Post-Commit Isolation** | Rollback Post-Commit Batch | Reverse Target Entity | Entity Reversed cleanly | **PASS** |

---

## 16. Financial Integrity

- **Primary Production Society Dues Created:** `0`
- **Primary Production Society Payments Created:** `0`
- **Primary Production Society Expenses Created:** `0`
- **Primary Production Society Ledger Transactions:** `0`
- **Primary Production Society Net Financial Mutation:** **`0.00`**
- **UAT Society Isolated Financial Total:** `8500.00` (Dataset-F synthetic opening balances)

---

## 17. Primary Production Society Data Integrity

- **Protected Society ID:** `11111111-1111-1111-1111-111111111111` ("Green Meadows Residential Welfare Association")
- **Baseline Property Count:** 5 (`Plot 45` through `Plot 49`)
- **Post-Test Property Count:** 5 (`Plot 45` through `Plot 49`)
- **Unintended Data Mutations:** **`0`**
- **Cross-Society Contamination Rate:** **`0.00%`**

---

## 18. Performance Results

| Dataset | Scenario Description | Total Stage Duration | Final Batch Status |
| :--- | :--- | :--- | :--- |
| **Dataset-B** | Duplicate / Existing Record Handling | ~3 ms | `committed` |
| **Dataset-C** | Invalid / Validation Boundaries | ~2 ms | `mapped` (Quarantined) |
| **Dataset-D** | Mixed Valid / Invalid Rows | ~4 ms | `committed` |
| **Dataset-E** | Relationship / Ownership Integrity | ~5 ms | `committed` |
| **Dataset-F** | Financial Safety | ~4 ms | `committed` |
| **Dataset-G** | Provenance / Lineage | ~3 ms | `committed` |
| **Dataset-H** | Rollback Safety (Pre & Post) | ~6 ms | `rolled_back` |
| **Dataset-I** | Tenant Isolation / Society Mismatch | ~4 ms | `committed` |
| **Dataset-J** | Approval / Hash Integrity | ~3 ms | `committed` |
| **Dataset-K** | Concurrency / Double-Submit Safety | ~3 ms | `committed` |
| **Dataset-L** | End-to-End Edge / Final Regression | ~4 ms | `committed` |

---

## 19. Audit & Lineage Results

- **Lineage Records Generated:** 17 total lineage records across all committed UAT batches. All records verified bound to UAT society ID `22222222-2222-2222-2222-222222222222`.
- **Reconciliation Records Generated:** 9 reconciliation records (`status: matched`).
- **Audit Logs Recorded:** 38 audit log entries for creation, upload, validation, approval, commit, and rollback events.

---

## 20 & 21. Findings & Deviations

- **Findings:** Candidate-30 Data Migration Center executed flawlessly across all 11 synthetic UAT scenarios (Datasets B through L). Tenant isolation (`TENANT_MISMATCH`), staging immutability (`CANNOT_MUTATE_APPROVED_STAGING`), validation protection gates, and double-submit controls performed with 100% precision.
- **Deviations:** Zero deviations or unexpected behavior encountered.

---

## 22. Dataset-by-Dataset Classification

| Dataset ID | Dataset Description | Verdict Classification |
| :--- | :--- | :--- |
| **DATASET-B** | Duplicate / Existing Record Handling | **PASS** |
| **DATASET-C** | Invalid / Validation Boundaries | **PASS** |
| **DATASET-D** | Mixed Valid / Invalid Rows | **PASS** |
| **DATASET-E** | Relationship / Ownership Integrity | **PASS** |
| **DATASET-F** | Financial Safety | **PASS** |
| **DATASET-G** | Provenance / Lineage | **PASS** |
| **DATASET-H** | Rollback Safety | **PASS** |
| **DATASET-I** | Tenant Isolation / Society Mismatch | **PASS** |
| **DATASET-J** | Approval / Hash Integrity | **PASS** |
| **DATASET-K** | Concurrency / Double-Submit Safety | **PASS** |
| **DATASET-L** | End-to-End Edge / Final Regression | **PASS** |

---

## 23. Overall Final Classification

**`A — ALL DATASETS B-L UAT PASS / CANDIDATE-30 UAT COMPLETE`**

---

## 24. Summary Metrics Inventory

1. **Master Report Path:** `D:\Clients Applications\SU Society App\CANDIDATE-30_DATASETS_B-L_SYNTHETIC_UAT_EXECUTION_REPORT.md`
2. **Applied Migration Baseline:** `29 / 29 Applied Migrations`
3. **Provisioned UAT Society ID:** `22222222-2222-2222-2222-222222222222`
4. **Protected Primary Production Society ID:** `11111111-1111-1111-1111-111111111111`
5. **Datasets Executed:** 11 (`DATASET-B` through `DATASET-L`)
6. **Datasets Passed:** 11
7. **Datasets with Controlled Gaps:** 0
8. **Datasets Blocked:** 0
9. **Datasets Failed:** 0
10. **Primary Production Mutation:** `0` (Baseline count: 5 properties, 0 mutated)
11. **Primary Production Financial Mutation:** `0.00`
12. **Cross-Society Access:** `DENIED`
13. **Candidate-30 Source Modification:** `0`
14. **New Database Migration:** `0`
15. **Deployment:** `0`
16. **Overall Classification:** `A — ALL DATASETS B-L UAT PASS / CANDIDATE-30 UAT COMPLETE`
17. **Next Authorization Required:** *Human Authorization for Final Production Handover / Operational Sign-off*.
