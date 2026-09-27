# CANDIDATE-26-01 REMOTE DEPLOYMENT AND POST-DEPLOYMENT FORENSIC REPORT
## Vendor Registry, Asset Inventory & Annual Maintenance Contract (AMC) Management System
### Remote Migration Deployment Forensic Execution Report

```
================================================================================
EXECUTION CLASS:             REMOTE MIGRATION DEPLOYMENT FORENSIC EXECUTION
TARGET REPOSITORY:           D:\Clients Applications\SU Society App
TARGET SUPABASE PROJECT:     fsegpxqoozxmicxcxjun
CANDIDATE:                   CANDIDATE-26-01
CANDIDATE NAME:              Vendor Registry, Asset Inventory & AMC Management System
HUMAN AUTHORIZATION:         RECEIVED ("AUTHORIZE CANDIDATE-26-01 REMOTE DEPLOYMENT")
DEPLOYMENT COMMAND:          npx supabase db push
EXECUTION TIMESTAMP:         2026-09-16T13:01:42Z to 2026-09-16T13:01:50Z
PRE-DEPLOYMENT PENDING QUEUE: EXACTLY ONE (20260916000026_candidate26_remediation.sql)
CANDIDATE 26 MIGRATION HASH: 657B4A048562F4A111B8019B9406CFEFFAE2FBEF2BAA7C12205958A7E9E438AE
HISTORICAL MIGRATIONS:       25 / 25 UNCHANGED (100% IMMUTABLE)
DEPLOYMENT OUTCOME:          FAILED / TRANSACTION ROLLED BACK
ERROR CODE:                  LegacyDbPushApplyError (SQLSTATE 42703)
ERROR DETAILS:               ERROR: column "asset_code" named in key does not exist on table public.assets at Statement 7
REMOTE DATABASE MUTATION:    UNMUTATED / ROLLED BACK (0 DEPLOYED CHANGES)
FINAL SECURITY LOCK:         NOT PERFORMED
FINAL CLASSIFICATION:        D — DEPLOYMENT FAILED — NO UNSCRIPTED RECOVERY
================================================================================
```

---

## 1. EXECUTIVE SUMMARY

This report documents the remote deployment execution and forensic failure analysis for **CANDIDATE-26-01** (Vendor Registry, Asset Inventory & AMC Management System).

Following the successful authorization and execution of Slice-25 migration history metadata reconciliation (`npx supabase migration repair 20260912000025 --status applied --linked`), a pre-deployment safety gate confirmed that the Supabase CLI pending queue contained **EXACTLY ONE** migration ([20260916000026_candidate26_remediation.sql](file:///D:/Clients%20Applications/SU%20Society%20App/supabase/migrations/20260916000026_candidate26_remediation.sql)).

**Deployment Execution & Result:** The authorized deployment command `npx supabase db push` was executed against remote project `fsegpxqoozxmicxcxjun`. The migration aborted during statement execution with a PostgreSQL DDL exception:
`ERROR: column "asset_code" named in key does not exist (SQLSTATE 42703)` at statement 7 (`ALTER TABLE public.assets ADD CONSTRAINT uq_assets_society_asset_code UNIQUE (society_id, asset_code);`).

Per **Section 4 & Section 12 of the Absolute Governance Rules**, unscripted recovery, automatic retries, migration file modifications, manual SQL execution, or history manipulation are strictly prohibited. The transaction aborted atomically at the database engine level, leaving the remote Supabase project in its pre-deployment state.

**Final Classification:** `D — DEPLOYMENT FAILED — NO UNSCRIPTED RECOVERY`.

---

## 2. EXPLICIT HUMAN AUTHORIZATION EVIDENCE & PRE-DEPLOYMENT GATES

- **Explicit Authorization:** Received and verified (`"AUTHORIZE CANDIDATE-26-01 REMOTE DEPLOYMENT"`).
- **Target Supabase Project:** `fsegpxqoozxmicxcxjun`
- **Pre-Deployment Queue Inspection (`npx supabase db push --dry-run`):**
  ```json
  {
    "dryRun": true,
    "migrations": [
      "20260916000026_candidate26_remediation.sql"
    ],
    "upToDate": false,
    "message": "Finished supabase db push."
  }
  ```
- **Pending Migration Queue Count:** Exactly 1 migration (`20260916000026_candidate26_remediation.sql`).

---

## 3. HISTORICAL MIGRATION IMMUTABILITY VERIFICATION

- **Historical Range:** `20260912000001_slice1.sql` through `20260912000025_slice25.sql` (25 files).
- **Modification Count:** `0` (Zero historical migration files altered).
- **Baseline Integrity:** `1040 / 1040 PASS` baseline remains 100% immutable and intact.

---

## 4. EXACT DEPLOYMENT FAILURE ANALYSIS

### Execution Parameters:
- **Command:** `npx supabase db push`
- **Timestamp:** `2026-09-16T13:01:42Z`
- **Target DB:** `fsegpxqoozxmicxcxjun`
- **Migration Script:** `20260916000026_candidate26_remediation.sql`

### Captured CLI Error Response:
```json
{
  "_tag": "Error",
  "error": {
    "code": "LegacyDbPushApplyError",
    "message": "ERROR: column \"asset_code\" named in key does not exist (SQLSTATE 42703)\nAt statement: 7\n-- ============================================================================\n-- 3. FND-26-01-05: ASSET CODE UNIQUENESS CONSTRAINT (society_id, asset_code)\n-- ============================================================================\n\nDO $$\nBEGIN\n    IF NOT EXISTS (\n        SELECT 1 FROM pg_constraint WHERE conname = 'uq_assets_society_asset_code'\n    ) THEN\n        ALTER TABLE public.assets\n        ADD CONSTRAINT uq_assets_society_asset_code UNIQUE (society_id, asset_code);\n    END IF;\nEND $$"
  }
}
```

### Forensic Cause Analysis:
1. Statement 7 attempted to execute `ALTER TABLE public.assets ADD CONSTRAINT uq_assets_society_asset_code UNIQUE (society_id, asset_code);`.
2. PostgreSQL raised `SQLSTATE 42703` (`undefined_column`) because the column `asset_code` does not exist on table `public.assets` in the remote database.
3. In Statement 1, `CREATE TABLE IF NOT EXISTS public.assets (...)` was skipped because a table named `public.assets` already exists in the remote database from an earlier slice/schema definition, but that pre-existing table does not contain the column `asset_code`.
4. The migration script assumed `public.assets` was a brand-new table created in statement 1, creating a schema mismatch with the pre-existing remote `public.assets` definition.

---

## 5. REMOTE DATABASE MUTATION & TRANSACTION OUTCOME

- **PostgreSQL Transaction Handling:** The migration script was executed inside a single transaction block (`BEGIN; ... COMMIT;`).
- **Engine Transaction Rollback:** Upon encountering `SQLSTATE 42703`, PostgreSQL automatically issued a full transaction `ROLLBACK`.
- **Remote Schema State:** Zero candidate tables (`vendors`, `assets`, `asset_amcs`, `asset_maintenance_logs`), zero RPCs, and zero policies were created on remote project `fsegpxqoozxmicxcxjun`.
- **Remote `schema_migrations` Table:** `'20260916000026'` was **NOT** added to remote migration history.

---

## 6. POST-DEPLOYMENT VERIFICATION MATRIX

| Finding / Item | Requirement | Deployed Remote State | Forensic Result |
| :--- | :--- | :--- | :--- |
| `FND-26-01-01` | Multi-tenant isolation & candidate tables | Transaction Rolled Back (0 Tables Created) | **FAILED (ROLLED BACK)** |
| `FND-26-01-02` | AMC renewal `SELECT ... FOR UPDATE` locking | Transaction Rolled Back (0 RPCs Created) | **FAILED (ROLLED BACK)** |
| `FND-26-01-03` | Additive vendor link on `expense_vouchers` | Transaction Rolled Back | **FAILED (ROLLED BACK)** |
| `FND-26-01-04` | Service log append-only & audit dual-write | Transaction Rolled Back | **FAILED (ROLLED BACK)** |
| `FND-26-01-05` | Composite `UNIQUE (society_id, asset_code)` | Failed at Statement 7 (`SQLSTATE 42703`) | **FAILED (EXCEPTION)** |

---

## 7. RPC SECURITY & DIRECT PRIVILEGE VERIFICATION

- **Candidate RPCs Created:** `0` (Rolled back)
- **Direct Privilege Changes:** `0` (Rolled back)
- **Security Definer Implementations:** `0` (Rolled back)

---

## 8. NO UNSCRIPTED RECOVERY DECLARATION

Per governance rules:
- No manual SQL commands were executed on remote database `fsegpxqoozxmicxcxjun`.
- No migration file editing (`20260916000026_candidate26_remediation.sql`) was performed.
- No history manipulation or forced flag `--include-all` was used.
- The failure evidence was preserved verbatim for human adjudication.

---

## 9. BASELINE INTEGRITY & SECURITY LOCK STATUS

- **Pre-Deployment Locked Baseline:** `1040 / 1040 PASS` (Preserved).
- **Historical Migration Integrity:** 25/25 files byte-identical.
- **Candidate 26-01 Security Lock:** **NOT PERFORMED**.

---

## 10. FINAL CLASSIFICATION

```
FINAL CLASSIFICATION:
D — DEPLOYMENT FAILED — NO UNSCRIPTED RECOVERY
```

---

## 11. CRYPTOGRAPHIC VERIFICATION METADATA

- **Report Path:** `D:\Clients Applications\SU Society App\CANDIDATE-26-01_REMOTE_DEPLOYMENT_AND_POST_DEPLOYMENT_FORENSIC_REPORT.md`
- **Target Repository:** `D:\Clients Applications\SU Society App`
- **Target Supabase Project:** `fsegpxqoozxmicxcxjun`
- **Candidate 26-01 Migration Path:** `D:\Clients Applications\SU Society App\supabase\migrations\20260916000026_candidate26_remediation.sql`
- **Candidate 26-01 Migration SHA-256:** `657B4A048562F4A111B8019B9406CFEFFAE2FBEF2BAA7C12205958A7E9E438AE`
- **Authoritative Baseline Status:** `1040 / 1040 PASS` (Preserved)

---
**End of Report:** `CANDIDATE-26-01_REMOTE_DEPLOYMENT_AND_POST_DEPLOYMENT_FORENSIC_REPORT.md`
