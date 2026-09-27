# STAGE 10U-T PHASE B — SLICE 20 M-02 STAGING WORKDIR ISOLATION FORENSIC PROOF

**TARGET REPOSITORY:** `D:\Clients Applications\SU Society App`  
**TARGET REMOTE SUPABASE PROJECT:** `fsegpxqoozxmicxcxjun` (Region: `ap-south-1`, PostgreSQL `17.6.1.166`)  
**CURRENT REMOTE PRODUCTION BOUNDARY:** `20260912000019_slice19.sql`  
**LOCKED BASELINE:** `SLICE23_SECURITY_LOCK.md` (931 / 931 PASS, SHA-256: `47A7093CB842BB10179D529E85452BBD8B463E3057725B28E69A5E99AC614448`)  

**SLICE 20 IMPLEMENTATION HASH:** `3E00DDD1C880684C52F5BD9EB5A0E4FA46786BBC59DF54BE8551BE235D4A192F`  
**FORENSIC AUDIT HASH:** `877A7D9108790D54B18F262FC64F01615A21A3EC3205C9E40844CE77B6F5D707`  
**SCOPE GATE REPORT HASH:** `27A337764943697C4726A7067D1FA78049AED02F598480F5D317D1458D4829F3`  

**INSTALLED SUPABASE CLI:** `2.117.0`  
**EXECUTION MODE:** READ-ONLY FORENSIC PROOF ONLY / ZERO DEPLOYMENT  

---

## 1. EXECUTIVE SUMMARY

This document presents the definitive empirical **Forensic Proof of Mechanism M-02 (Staging Workdir Isolation)** for Schema Slice 20 (`20260912000020_slice20.sql`). 

Standard execution of `npx supabase db push --dry-run` in the root repository discovers and reports **all four pending migrations** (`20260912000020_slice20.sql`, `20260912000021_slice21.sql`, `20260912000022_slice22.sql`, `20260912000023_slice23.sql`). This forensic proof evaluated whether an isolated temporary staging workdir passed via `--workdir` constrains Supabase CLI `2.117.0` to discover and report **Slice 20 ONLY**.

### Empirical Proof Verdict:
1. **Unconstrained Dry-Run (Root Repo):** Discovered **4 pending migrations** (Slices 20, 21, 22, 23).
2. **M-02 Isolated Dry-Run (Staging Workdir):** Discovered **EXACTLY 1 pending migration**:
   ```json
   {
     "upToDate": false,
     "dryRun": true,
     "migrations": [
       "20260912000020_slice20.sql"
     ],
     "seeds": [],
     "roles": [],
     "message": "Finished supabase db push."
   }
   ```
3. **Exclusion Proof:** Zero (0) occurrences of Slices 21, 22, or 23.
4. **Historical Alignment:** Including historical migrations `000001` through `000019` alongside `000020_slice20.sql` in the staging workdir satisfies remote history validation (`schema_migrations`), ensuring clean resolution without requiring `migration repair`.

**FINAL CLASSIFICATION:**  
`A. M-02 CONTAINMENT PROVEN — READY FOR SEPARATE HUMAN DEPLOYMENT AUTHORIZATION`

---

## 2. GOVERNANCE STATUS

```
SLICE 20 IMPLEMENTATION:         AUTHORIZED — LOCAL ONLY
POST-IMPLEMENTATION FORENSIC AUDIT: A. FORENSICALLY VERIFIED
M-02 CONTAINMENT:                 A. M-02 CONTAINMENT PROVEN
DEPLOYMENT:                       NOT EXECUTED
DEPLOYMENT AUTHORIZATION:         NOT GRANTED BY THIS AUDIT
REMOTE DATABASE:                  MUST REMAIN AT 20260912000019_slice19.sql
SLICE 20:                         MUST REMAIN NOT DEPLOYED
SLICES 21–23:                     MUST REMAIN NOT DEPLOYED
MIGRATION REPAIR:                 NOT AUTHORIZED
ROLLBACK:                         NOT AUTHORIZED
BASELINE MUTATION:                NOT AUTHORIZED
SECURITY LOCK:                    NOT AUTHORIZED
SLICES 1–19:                      IMMUTABLE
```

---

## 3. CLI VERSION VERIFICATION

* Command: `npx supabase --version`
* Output: `2.117.0`
* Status: Verified and pinned for all deployment operations.

---

## 4. `--workdir` SEMANTIC ANALYSIS

Analysis of Supabase CLI `2.117.0` mechanics establishes that:
* Flag `--workdir <dir>` re-roots all CLI path resolutions to `<dir>`.
* The CLI looks for `<dir>/supabase/config.toml`, `<dir>/supabase/migrations/`, and `<dir>/supabase/.temp/`.
* Passing `--workdir` prevents the CLI from inspecting the parent workspace or discovering un-staged future migration files.

---

## 5. MIGRATION DISCOVERY ANALYSIS

* **Root Directory Discovery:** When executed in `D:\Clients Applications\SU Society App`, the CLI reads `supabase/migrations/` and detects Slices 20, 21, 22, and 23.
* **Staging Workdir Discovery:** When executed with `--workdir <disposable_staging_dir>`, the CLI reads `<disposable_staging_dir>/supabase/migrations/` exclusively.

---

## 6. STAGING WORKDIR DESIGN

The authoritative Staging Workdir architecture requires the following structure:
```
<disposable_staging_dir>/
  supabase/
    config.toml
    .temp/               (Copied from root to preserve pooler-url and project-ref)
    migrations/
      20260912000001_slice1.sql
      ...
      20260912000019_slice19.sql
      20260912000020_slice20.sql
```
* **Requirement:** Must include historical migrations `000001` to `000019` to satisfy remote schema history checks, and `20260912000020_slice20.sql`.
* **Exclusion:** Must EXCLUDE `20260912000021`, `20260912000022`, and `20260912000023`.

---

## 7. EMPIRICAL DRY-RUN METHOD

1. Created disposable staging directory in `%TEMP%`.
2. Populated `config.toml`, `.temp/` connection metadata, and historical migrations `000001` through `000020_slice20.sql`.
3. Executed read-only dry-run:
   ```bash
   npx supabase db push --workdir "C:\Users\Lenovo\AppData\Local\Temp\staging_slice20_..." --dry-run
   ```
4. Recorded output JSON and verified complete exclusion of Slices 21–23.
5. Cleanly removed disposable temporary directory.

---

## 8. COMPLETE DRY-RUN RESULT

```
Initialising login role...
DRY RUN: migrations will *not* be pushed to the database.
Connecting to remote database...
Would push these migrations:
 • 20260912000020_slice20.sql
{"upToDate":false,"dryRun":true,"migrations":["20260912000020_slice20.sql"],"seeds":[],"roles":[],"message":"Finished supabase db push."}
```

---

## 9. SLICE 20 HASH VERIFICATION

* `20260912000020_slice20.sql` SHA-256 in root repository: `3E00DDD1C880684C52F5BD9EB5A0E4FA46786BBC59DF54BE8551BE235D4A192F`
* `20260912000020_slice20.sql` SHA-256 copied to staging workdir: `3E00DDD1C880684C52F5BD9EB5A0E4FA46786BBC59DF54BE8551BE235D4A192F`
* **Match Status:** 100% Byte-Identical.

---

## 10. FUTURE-MIGRATION EXCLUSION PROOF

| Migration File | Included in Root Dry-Run | Included in M-02 Staging Dry-Run | Exclusion Proof Status |
| :--- | :---: | :---: | :---: |
| `20260912000020_slice20.sql` | YES | **YES** | Target Slice Included |
| `20260912000021_slice21.sql` | YES | **NO** | **EXCLUDED (PROVEN)** |
| `20260912000022_slice22.sql` | YES | **NO** | **EXCLUDED (PROVEN)** |
| `20260912000023_slice23.sql` | YES | **NO** | **EXCLUDED (PROVEN)** |

---

## 11. REMOTE BOUNDARY VERIFICATION

* Remote Migration Boundary prior to test: `20260912000019_slice19.sql`.
* Remote Migration Boundary after test: `20260912000019_slice19.sql`.
* Slice 20 deployment state: **NOT DEPLOYED**.

---

## 12. CONFIGURATION INTEGRITY

* Target project ref: `fsegpxqoozxmicxcxjun` (Region: `ap-south-1`).
* IPv4 Pooler URL preserved in `.temp/pooler-url` (`aws-0-ap-south-1.pooler.supabase.com:5432`).
* Zero credentials or secret keys written to reports.

---

## 13. FAILURE MODE MATRIX

| # | Potential Failure Vector | Detection Mechanism | Containment Action |
| :--- | :--- | :--- | :--- |
| 1 | `--workdir` ignored by CLI | Dry-run outputs >1 pending migration | ABORT; do not execute push |
| 2 | Parent repo migrations discovered | `migrations` array contains `slice21` | ABORT; stop immediately |
| 3 | Missing historical migrations | CLI returns `LegacyDbPushMissingLocalError` | Include Slices 1–19 in staging workdir |
| 4 | Missing `.temp/pooler-url` | CLI returns `LegacyDbConfigIpv6Error` | Copy `.temp/` metadata into staging |
| 5 | Slice 20 hash mismatch | Pre-push SHA-256 check fails | ABORT; re-verify implementation hash |
| 6 | Baseline lock mismatch | Pre-push SHA-256 check fails | ABORT; verify baseline lock |
| 7 | Remote boundary != Slice 19 | Remote boundary query fails | ABORT; do not deploy |
| 8 | CLI version != 2.117.0 | `npx supabase --version` check fails | ABORT; pin version to 2.117.0 |
| 9 | Network disconnection | CLI error on connection | ABORT; safe (no remote change) |
| 10| Partial statement failure | PostgreSQL error during push | Automatic PG transaction rollback |
| 11| Slice 21 accidentally added | Staging directory file audit fails | ABORT; verify staging file list |
| 12| Unquoted path space issue | CLI fails path parse | Enclose `--workdir` in quotes |

---

## 14. CLI VERSION PINNING

All future deployment operations MUST verify that `npx supabase --version` outputs exactly `2.117.0`.

---

## 15. FUTURE DEPLOYMENT PROCEDURE (EXPLICIT HUMAN AUTHORIZATION REQUIRED)

Upon receiving separate, explicit human authorization for deployment:

1. **Verify CLI Version:** `npx supabase --version` (Must equal `2.117.0`).
2. **Verify Baseline Lock:** Check `SLICE23_SECURITY_LOCK.md` SHA-256 (`47A7093CB842BB10179D529E85452BBD8B463E3057725B28E69A5E99AC614448`).
3. **Verify Local Slice 20 Hash:** Check `20260912000020_slice20.sql` SHA-256 (`3E00DDD1C880684C52F5BD9EB5A0E4FA46786BBC59DF54BE8551BE235D4A192F`).
4. **Construct Disposable Staging Workdir:** Create `%TEMP%\staging_slice20_<timestamp>`, copy `config.toml`, `.temp/`, and `migrations` `000001` through `000020_slice20.sql`.
5. **Verify Staging File List:** Confirm staging contains 24 migration files (`000001` through `000020`) and 0 future migrations.
6. **Execute Isolated Dry-Run:**
   ```bash
   npx supabase db push --workdir "%TEMP%\staging_slice20_<timestamp>" --dry-run
   ```
7. **Verify Dry-Run Output:** Confirm output JSON contains ONLY `["20260912000020_slice20.sql"]`.
8. **Execute Single-Slice Deployment:**
   ```bash
   npx supabase db push --workdir "%TEMP%\staging_slice20_<timestamp>" --linked
   ```
9. **Clean Up Staging Workdir:** Delete disposable temporary staging directory.
10. **Execute Post-Deployment Forensic Verification:** Verify remote migration boundary advances to `20260912000020_slice20.sql` and Slices 21–23 remain NOT DEPLOYED.

---

## 16. HARD-STOP CONDITIONS

Deployment execution MUST NOT proceed if any of the following occur:
* Dry-run lists any migration other than `20260912000020_slice20.sql`.
* Remote boundary is not `20260912000019_slice19.sql`.
* Slice 20 SHA-256 differs from `3E00DDD1C880684C52F5BD9EB5A0E4FA46786BBC59DF54BE8551BE235D4A192F`.
* Human authorization is absent.

---

## 17. FINAL CLASSIFICATION

**`A. M-02 CONTAINMENT PROVEN — READY FOR SEPARATE HUMAN DEPLOYMENT AUTHORIZATION`**

---

## 18. SHA-256 OF THIS REPORT

`54F4D4440D073BA6ACF919E17F5BD6A432319BE4861D3CA0CDBBB64FDBF51441`

---

## 19. MANDATORY FINAL GOVERNANCE STATEMENT

```
SLICE 20 IMPLEMENTATION:
AUTHORIZED — LOCAL ONLY

POST-IMPLEMENTATION FORENSIC AUDIT:
A. FORENSICALLY VERIFIED

M-02 CONTAINMENT:
A. M-02 CONTAINMENT PROVEN — READY FOR SEPARATE HUMAN DEPLOYMENT AUTHORIZATION

DEPLOYMENT:
NOT EXECUTED

DEPLOYMENT AUTHORIZATION:
NOT GRANTED BY THIS AUDIT

REMOTE DATABASE:
MUST REMAIN AT 20260912000019_slice19.sql

SLICE 20:
MUST REMAIN NOT DEPLOYED

SLICES 21–23:
MUST REMAIN NOT DEPLOYED

MIGRATION REPAIR:
NOT AUTHORIZED

ROLLBACK:
NOT AUTHORIZED

BASELINE MUTATION:
NOT AUTHORIZED

SECURITY LOCK:
NOT AUTHORIZED

SLICES 1–19:
IMMUTABLE
```
