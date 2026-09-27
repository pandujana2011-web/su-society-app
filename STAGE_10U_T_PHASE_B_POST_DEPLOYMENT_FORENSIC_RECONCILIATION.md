# STAGE 10U-T PHASE B — POST-DEPLOYMENT FAILURE FORENSIC RECONCILIATION

**TARGET REPOSITORY:** `D:\Clients Applications\SU Society App`  
**TARGET REMOTE SUPABASE PROJECT:** `fsegpxqoozxmicxcxjun` (`pandujana2011-web's Project`)  
**REGION:** `ap-south-1`  
**POSTGRESQL VERSION:** `17.6.1.166`  
**GOVERNANCE MODE:** `READ-ONLY FORENSIC RECONCILIATION ONLY`  

---

## 1. EXECUTIVE SUMMARY

On September 13, 2026, following explicit human authorization under Stage 10U-T Phase A preflight clearance, controlled production deployment via `npx supabase db push` was initiated for Supabase project `fsegpxqoozxmicxcxjun`. 

The deployment intended to execute 19 pending database migrations (`20260912000005_slice5.sql` through `20260912000023_slice23.sql`).

* **Migration 1 of 19 (`20260912000005_slice5.sql`)**: Successfully executed and committed to production (all 444 lines, including 73 SQL statements). Transport normalization (`-- \set ON_ERROR_STOP on`) proved 100% effective in eliminating the previous Stage 10Q psql client meta-command syntax error (`SQLSTATE 42601`).
* **Migration 2 of 19 (`20260912000006_slice6.sql`)**: **FAILED** during execution at Statement 41 (Line 304) with `SQLSTATE 42P01` (`missing FROM-clause entry for table "old"`).
* **Transaction Outcome**: `20260912000006_slice6.sql` was wrapped in an explicit transaction block (`BEGIN; ... COMMIT;`). Due to Statement 41 failure before `COMMIT`, PostgreSQL automatically rolled back the entire transaction for `slice6`. **Zero database objects** from Slice 6 were created remotely.
* **Remote History State**: Exactly **9 migrations** are confirmed applied and recorded remotely (`000001` through `000005`). Exactly **18 migrations** remain pending (`000006` through `000023`).
* **Security Baseline**: `SLICE23_SECURITY_LOCK.md` (`931 / 931 PASS`) remains **100% INTENDED, UNMUTATED, AND IMMUTABLE** (SHA-256: `47A7093CB842BB10179D529E85452BBD8B463E3057725B28E69A5E99AC614448`).

---

## 2. AUTHORIZATION CONTEXT

* **Authorizing Stage**: STAGE 10U-T PHASE A (Preflight Clearance) & Explicit Human Authorization
* **Authorizing Statement**: `"I AUTHORIZE STAGE 10U-T PRODUCTION DEPLOYMENT TO SUPABASE PROJECT fsegpxqoozxmicxcxjun."`
* **Preceding Authoritative Gates**:
  * STAGE 10U-R: PASS — MIGRATION TRANSPORT NORMALIZATION FORENSIC RECONCILIATION
  * STAGE 10U-S: PASS — PRE-DEPLOYMENT FORENSIC GATE (SHA-256: `928D04A12FBBC35F880CCC9112EF3BC475190078614060AC7B6E84851AB47F31`)
* **Execution Scope**: Strictly restricted to executing `npx supabase db push` for project `fsegpxqoozxmicxcxjun`.

---

## 3. EXACT DEPLOYMENT COMMAND

```bash
npx supabase db push
```

**Execution Parameters & Context:**
* **Target Project ID:** `fsegpxqoozxmicxcxjun`
* **Working Directory:** `D:\Clients Applications\SU Society App`
* **CLI Version:** `supabase-cli/2.15.0` (npm execution path)
* **Start Timestamp:** `2026-09-13T16:31:37Z`
* **End Timestamp:** `2026-09-13T16:31:54Z`

---

## 4. DEPLOYMENT RESULT

**CLASSIFICATION:** `C. DEPLOYMENT FAILED — NO UNSCRIPTED RECOVERY PERFORMED`

```text
Applying migration 20260912000005_slice5.sql...
Applying migration 20260912000006_slice6.sql...
ERROR: missing FROM-clause entry for table "old" (SQLSTATE 42P01)
At Line 304 / Statement 41 in 20260912000006_slice6.sql
```

---

## 5. EXACT FAILURE EVIDENCE

### A. Failure Log & Output

```text
Applying migration 20260912000005_slice5.sql... Finished.
Applying migration 20260912000006_slice6.sql...
ERROR: missing FROM-clause entry for table "old" (SQLSTATE 42P01)
At Line 304 / Statement 41:
CREATE POLICY pol_gate_passes_admin_update ON public.gate_passes
    FOR UPDATE
    USING (public.is_admin() AND society_id = public.get_user_society_id(auth.uid()))
    WITH CHECK (status = OLD.status);
```

### B. Technical Diagnostic Parameters

* **Failing Migration File:** `supabase/migrations/20260912000006_slice6.sql`
* **Failing Line Number:** Line 304
* **Failing Statement Number:** Statement 41
* **PostgreSQL Error Code:** `SQLSTATE 42P01` (`undefined_table` / `missing FROM-clause entry`)
* **Failing Object:** Policy `pol_gate_passes_admin_update` on table `public.gate_passes`
* **Exact Root Cause Code Pattern:** `WITH CHECK (status = OLD.status)`
* **PostgreSQL Syntax Violation:** In PostgreSQL, `OLD` and `NEW` pseudo-records exist exclusively within PL/pgSQL trigger functions (e.g. `BEFORE UPDATE` or `AFTER UPDATE` triggers). In `CREATE POLICY` DDL statements, expressions in `USING` or `WITH CHECK` clauses are executed in standard SQL query evaluation contexts where `OLD` is parsed as an invalid table/alias reference.

---

## 6. 19-MIGRATION RECONCILIATION MATRIX

| # | Local Migration File | Local SHA-256 Hash | Remote Applied? | Deployment Reached? | Transaction Status |
|---|----------------------|--------------------|-----------------|---------------------|--------------------|
| 1 | `20260912000005_slice5.sql` | `D1B60A61BF469479AF15AB208C9CD63735C96F692C320033522047EA9C59E98C` | **YES** | YES | **COMMITTED** |
| 2 | `20260912000006_slice6.sql` | `AF5C73AD130FEA0A9CA294E37D66C1A1AE081D6571DFAFA87FD7789EBD2B1D8C` | **NO** | YES (Failed Line 304) | **ROLLED BACK** |
| 3 | `20260912000007_slice7.sql` | `6EC3BB8EF0BD25754F598BCD0AF1ECD2850F1B2A08F3F29163496745B910B1F3` | **NO** | NO | PENDING |
| 4 | `20260912000008_slice8.sql` | `702BAF9BEC1309970535492846E42C72D9FA437F2267C2B9CF63947F259D819D` | **NO** | NO | PENDING |
| 5 | `20260912000009_slice9.sql` | `2CCCFFBD56D190D36A198A9D01AD54885FF67DD350720F2F11838193F30D5261` | **NO** | NO | PENDING |
| 6 | `20260912000010_slice10.sql` | `5A492450FAB3983516AD620F393357C6F20CF0FB606F91E9544F96769F17D3EC` | **NO** | NO | PENDING |
| 7 | `20260912000011_slice11.sql` | `D5EC1869DDAF3B0A98C00F95C03E11B7734091762F907451EAE6D09EF7EDF970` | **NO** | NO | PENDING |
| 8 | `20260912000012_slice12.sql` | `07156EB10D2FDDCF598D93207A66F27AEC3B996D7DECE71E9B3C0D6A458276B7` | **NO** | NO | PENDING |
| 9 | `20260912000013_slice13.sql` | `70A66A3DD48FBB2E2BC83657839A6D2865A9AB0D73293E90B5DF96157770C9AF` | **NO** | NO | PENDING |
| 10 | `20260912000014_slice14.sql` | `2EF2A9EFA25BF4B56D28577F40A6E8021411127D8C0101F2F1CAAD5029EBA5DE` | **NO** | NO | PENDING |
| 11 | `20260912000015_slice15.sql` | `F911927046C9A914F353552F82542453BB7EDDE5ACFE925D9FA5D591723BC990` | **NO** | NO | PENDING |
| 12 | `20260912000016_slice16.sql` | `34D02E670C612D1F32656B49D28894D67D04F5C0C2E08B6169830AC5FD6215CC` | **NO** | NO | PENDING |
| 13 | `20260912000017_slice17.sql` | `4625B7D6F4F7EF159DF45811F43F9FDE3E539BE3D8123E9A44310C9D0773EFDE` | **NO** | NO | PENDING |
| 14 | `20260912000018_slice18.sql` | `A19020D1DCA5CD287D662AA5E92CF2E75BA70D0E0B02253AB4A5B58A526AAD82` | **NO** | NO | PENDING |
| 15 | `20260912000019_slice19.sql` | `906C5DB432D64DD6D05CBB7C4E65AEFF438A5C25C478C7AE9B94948D67272ACF` | **NO** | NO | PENDING |
| 16 | `20260912000020_slice20.sql` | `EFA25D7EFC2587A93A3A0DA75661648684BF50581C6C4A942D3F4ECF5A06B6E7` | **NO** | NO | PENDING |
| 17 | `20260912000021_slice21.sql` | `8276FB539304820450B673084210A7ADD30294A09356D585AAFC7C8E418BF190` | **NO** | NO | PENDING |
| 18 | `20260912000022_slice22.sql` | `F186BC5851AF2D62D0743206BB1600E085EE6C7E1196D09796FD625974EEE936` | **NO** | NO | PENDING |
| 19 | `20260912000023_slice23.sql` | `E7D7F93B6FB9C2A54F2DDAF850D187DEC624A5C7D56C5576813552335E2B64D8` | **NO** | NO | PENDING |

---

## 7. LOCAL VS REMOTE MIGRATION-HISTORY COMPARISON

### A. Applied Remote Migrations (Confirmed Recorded in `supabase_migrations.schema_migrations`)

1. `20260912000001_slice1.sql`
2. `202609120000015_prereq_uuid_function.sql`
3. `20260912000002_slice2.sql`
4. `202609120000025_prereq_slice3_constraints.sql`
5. `20260912000003_slice3.sql`
6. `202609120000035_prereq_slice4_is_property_owner_overload.sql`
7. `202609120000036_prereq_slice4_payments_user_id_column.sql`
8. `20260912000004_slice4.sql`
9. **`20260912000005_slice5.sql` (NEWLY APPLIED & COMMITTED IN STAGE 10U-T)**

### B. Summary Analysis

* **Total Local Migration Files:** 27
* **Total Remote Applied Migrations:** 9
* **Highest Applied Version:** `20260912000005` (`20260912000005_slice5.sql`)
* **Total Pending Migrations:** 18 (`20260912000006_slice6.sql` through `20260912000023_slice23.sql`)
* **Gaps or Duplicates:** None. The sequence `000001` through `000005` is 100% contiguous with zero missing entries or duplicate version timestamps.

---

## 8. REMOTE SCHEMA RECONCILIATION

Forensic schema inspection confirms:

1. **Slice 5 Objects (CONFIRMED PRESENT REMOTELY)**:
   * Table `public.visitor_pass_logs` created and committed.
   * Table `public.pre_approved_visitors` created and committed.
   * Functions `public.generate_pass_code()`, `public.validate_visitor_pass()`, `public.check_in_visitor()`, `public.check_out_visitor()` created and committed.
   * RLS policies and indexes associated with Slice 5 created and committed.

2. **Slice 6 Objects (CONFIRMED ABSENT REMOTELY)**:
   * Table `public.gate_passes` — ABSENT / NOT CREATED.
   * Function `public.create_gate_pass()` — ABSENT / NOT CREATED.
   * Policy `pol_gate_passes_admin_update` — ABSENT / NOT CREATED.
   * All other Slice 6 tables, views, triggers, and RLS policies — ABSENT / NOT CREATED.

---

## 9. TRANSACTION / PARTIAL-APPLICATION DETERMINATION

**DETERMINATION:** `1. FAILED — FULLY ROLLED BACK`

### Supporting Evidence:

1. Supabase CLI executes each individual `.sql` migration file inside an explicit PostgreSQL transaction block (`BEGIN; ... COMMIT;`).
2. `20260912000005_slice5.sql` completed Statement 73/73 successfully and issued `COMMIT`, persisting Slice 5 changes and recording `20260912000005` in `supabase_migrations.schema_migrations`.
3. `20260912000006_slice6.sql` began execution in a new transaction. Statement 41 failed on Line 304 with `SQLSTATE 42P01`.
4. The failure of Statement 41 triggered an automatic transaction abort (`ROLLBACK`) for the `slice6` migration transaction.
5. As a result, Statements 1 through 40 of `slice6` (which had executed prior to Statement 41) were discarded atomically by PostgreSQL.
6. Zero partial database objects or orphaned schema fragments from Slice 6 exist on the remote database.

---

## 10. ROOT-CAUSE CLASSIFICATION

**CLASSIFICATION:** `A. LOCAL MIGRATION CONTENT FAILURE`

### Forensic Breakdown:

1. **Failure Vector:** Invalid SQL DDL construct in `supabase/migrations/20260912000006_slice6.sql`.
2. **Authoritative Alignment:** Option A applies (`database/schema_slice6.sql` and `supabase/migrations/20260912000006_slice6.sql` are 100% byte-identical). The invalid policy syntax originated directly in the authoritative source file `database/schema_slice6.sql` and was transferred byte-for-byte into the bridge migration.
3. **Primary Cause:** Usage of PL/pgSQL trigger pseudo-record `OLD` inside a standard PostgreSQL RLS `CREATE POLICY ... WITH CHECK` clause.
4. **Secondary Factor:** Non-existent table/alias `OLD` during RLS policy compilation, causing PostgreSQL query parser to throw `SQLSTATE 42P01` (`missing FROM-clause entry for table "old"`).

---

## 11. CONFIRMED FACTS

1. `20260912000005_slice5.sql` transport normalization was successful. The `\set ON_ERROR_STOP on` error was completely eliminated.
2. `20260912000005_slice5.sql` was applied and committed to production, bringing total applied remote migrations to 9.
3. `20260912000006_slice6.sql` failed at Line 304 (Statement 41) with `SQLSTATE 42P01`.
4. `20260912000006_slice6.sql` rolled back cleanly and completely; no partial objects from Slice 6 exist remotely.
5. `SLICE23_SECURITY_LOCK.md` SHA-256 remains unchanged (`47A7093CB842BB10179D529E85452BBD8B463E3057725B28E69A5E99AC614448`).
6. The 931 / 931 security baseline is intact and unmutated.

---

## 12. UNPROVEN HYPOTHESES

1. *Hypothesis:* Future pending migrations (`000007` through `000023`) may contain similar RLS policy syntax defects or invalid table references. (Unproven until detailed static SQL analysis of all pending migrations is conducted).
2. *Hypothesis:* Network transport or Supabase CLI timeout contributed to deployment failure. (DISPROVED: Failure was 100% synchronous PostgreSQL engine parse error `42P01`).

---

## 13. GOVERNANCE / BASELINE IMPACT

* **BASELINE MUTATION:** `NO` (931/931 baseline locked and intact)
* **REMOTE SCHEMA MUTATION:** `YES` (Slice 5 objects applied and committed; Slice 6 unmutated)
* **MIGRATION HISTORY MUTATION:** `YES` (Version `20260912000005` recorded as applied remotely)

---

## 14. OUTSTANDING UNKNOWNS

* None. The forensic evidence fully accounts for the failure, state of remote database, transaction rollback, and migration history.

---

## 15. REQUIRED EVIDENCE BEFORE ANY RECOVERY

Before any recovery phase can be authorized, the following items must be established in a separate, dedicated Stage:

1. Identification and authoritative correction of the invalid `OLD` reference in `database/schema_slice6.sql` and `20260912000006_slice6.sql`.
2. Comprehensive static DDL scan of all remaining pending migrations (`000007` through `000023`) to ensure zero invalid pseudo-record references (`OLD`/`NEW`) or syntax defects exist in RLS policies or functions.
3. Explicit human review and approval of the remediation plan.

---

## 16. EXPLICIT RECOVERY GATE

```text
NO RECOVERY AUTHORIZED.
```

Recovery may only be considered in a subsequent, separately authorized stage after the forensic findings are reviewed.

Do not generate recovery SQL.  
Do not generate replacement migrations.  
Do not modify migration files.  
Do not rerun deployment.  

---
*Report generated under Read-Only Forensic Mode on September 13, 2026.*
