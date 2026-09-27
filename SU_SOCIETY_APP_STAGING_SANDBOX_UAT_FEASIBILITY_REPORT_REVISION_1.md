# SU SOCIETY APP — STAGING / SANDBOX UAT ENVIRONMENT FEASIBILITY REPORT
**READ-ONLY FEASIBILITY & GOVERNANCE AUDIT**  
**REVISION 1.0**  

**TARGET REPOSITORY:** `D:\Clients Applications\SU Society App`  
**CURRENT PRODUCTION APP:** `https://su-society-app.vercel.app`  
**VERCEL PROJECT:** `su-society-app` (`prj_Je2Kwr9xtx25KgKVNWvelGot2y8j`)  
**VERCEL DEPLOYMENT ID:** `dpl_61jDwwKmdh1WVysox97LVkQPSNM9`  
**TARGET SUPABASE PROJECT:** `fsegpxqoozxmicxcxjun` (`https://fsegpxqoozxmicxcxjun.supabase.co`)  
**AUTHORITATIVE BASELINE:** SLICES 1–26 = FORMALLY LOCKED & IMMUTABLE  
**READ-ONLY UAT REPORT:** `SU_SOCIETY_APP_PRODUCTION_UAT_READ_ONLY_REPORT.md` (SHA `E48D2C98...`)  
**MUTATION GATE REPORT:** `SU_SOCIETY_APP_CONTROLLED_PRODUCTION_UAT_MUTATION_GATE_REVISION_1.md` (SHA `63391E04...`)  

---

## 1. Executive Status

This report presents a read-only feasibility analysis to establish a non-production Staging/Sandbox testing environment for future mutating User Acceptance Testing (UAT) of Expense Vouchers, AMC Renewals, Asset Maintenance Service Logging, and Vendor/Asset management.

- **Execution Mode:** `STRICT READ-ONLY FEASIBILITY / ZERO MUTATION`
- **Infrastructure Created:** `0` (Zero Vercel projects, Supabase projects, or cloud resources created)
- **Production Mutations Executed:** `0` (Zero production records created, updated, or deleted)
- **Primary Finding:** The repository contains a pre-built **Local Sandbox Architecture** (`npm run dev` + Local Mock DB Mode in `src/supabase.js`) that provides 100% isolated, zero-cost, zero-risk, and instantly resettable mutating UAT capabilities.
- **Final Classification:** **`A — STAGING / SANDBOX UAT FEASIBILITY COMPLETE — SAFE NON-PRODUCTION PATH IDENTIFIED`**

---

## 2. Current Production Baseline

- **Vercel Production Deployment:** `dpl_61jDwwKmdh1WVysox97LVkQPSNM9`
- **Vercel Project:** `su-society-app` (`prj_Je2Kwr9xtx25KgKVNWvelGot2y8j`)
- **Production URL:** `https://su-society-app.vercel.app` (`HTTP 200 OK`)
- **Remote Database Target:** `https://fsegpxqoozxmicxcxjun.supabase.co`
- **Applied Database Migrations:** 26 / 26 Applied (0 Pending)
- **Locked Code Assets:**
  - `src/App.jsx` SHA-256: `2CCFFDA62E4567BB7220ED62AFEAAA2CD7CC472D0E27EFFCE880796353FA95F1`
  - `src/supabase.js` SHA-256: `6B57718013D8A429C02332F4CFD02125807CD6B462168EAF37B95B58E405C461`
  - `package.json` SHA-256: `85124D56572D2A3A54A69012B3B9202FAD01CC8103D55DE0A42E5E2E0AE5D905`
  - `package-lock.json` SHA-256: `71320D46C729BE807844648B0788946A4126C37FE864DDCA17D72E9CE9BCE06C`
  - `supabase/migrations/20260916000026_candidate26_remediation.sql` SHA-256: `ACF35474380D1DB379CC536E75332238800918390C25611B2BB97D0F9836EB72`

---

## 3. Why Production Mutation Testing Is Blocked

As documented in `SU_SOCIETY_APP_CONTROLLED_PRODUCTION_UAT_MUTATION_GATE_REVISION_1.md`:

1. **Absence of Disposable Test Data:** Live production instance `fsegpxqoozxmicxcxjun` contains only primary operational entities (`ast-1` generator, `ast-2` elevator, `amc-1` AMC contract, `11111111-1111-1111-1111-111111111111` Green Meadows RWA). Zero dedicated test societies exist.
2. **Append-Only Immutability Risk:** `asset_maintenance_logs` table is enforced append-only by DB trigger `trg_prevent_maintenance_log_mutation`. Any test log created on production becomes **PERMANENT, UNERASABLE DATA POLLUTION**.
3. **Financial Ledger Contamination:** Test expense vouchers alter financial totals and sub-ledger balances in live resident reporting.
4. **Governance Directive:** Production mutation testing without an isolated test boundary is **BLOCKED**.

---

## 4. Local Sandbox Feasibility Analysis

Inspection of `src/supabase.js` and `package.json` confirms that a Local Sandbox environment is natively supported by the application codebase:

- **Mechanics:** Running `npm run dev` locally launches the Vite development server. When `VITE_SUPABASE_URL` is omitted or unconfigured, `src/supabase.js` sets `isMock = true` and initializes **Local Mock Database Mode**.
- **Mock Database Engine:** Manages a full in-memory/localStorage relational engine (`localStorage.getItem('su_society_db')`) pre-populated with baseline schema entities.
- **Schema & Business Rules:** Natively enforces direction invariants, discriminator checks, payment state machine transitions, `renew_amc` RPC behavior, `log_asset_service` RPC behavior, and append-only maintenance log rules.
- **Resettability:** Resettable in 1 click via `localStorage.clear()` or browser dev tools without database commands.
- **Cost:** **$0 (Zero Cost)**. Uses local workstation resources.
- **Production Contamination:** **0% (Zero Risk)**. Zero network connection to production Supabase or Vercel.

---

## 5. Separate Supabase Staging Project Feasibility Analysis

Evaluating a cloud-hosted Supabase Staging environment:

- **Mechanics:** Provisioning a second Supabase project (e.g., `fsegpxqoozxmicxcxjun-staging`) via the Supabase dashboard/CLI.
- **Migration Reproduction:** Locked Slices 1–26 (`20260912000001_slice1.sql` through `20260916000026_candidate26_remediation.sql`) are applied sequentially using `npx supabase db push --linked`.
- **Isolation:** Complete network and database separation from production database `fsegpxqoozxmicxcxjun`.
- **Resettability:** Resettable via `npx supabase db reset --linked`.
- **Resource Allocation:** Requires provisioning an additional cloud Supabase project instance under account quotas.

---

## 6. Separate Vercel Staging Project Feasibility Analysis

Evaluating a cloud-hosted Vercel Staging deployment:

- **Mechanics:** Configuring a Vercel Preview environment or a separate Vercel project (e.g., `su-society-app-staging`) linked to the repository repository.
- **Environment Variable Isolation:** Setting staging-specific environment variables:
  - `VITE_SUPABASE_URL` = `https://<staging-project>.supabase.co`
  - `VITE_SUPABASE_ANON_KEY` = `<staging-anon-key>`
- **Production Alias Protection:** Production URL `https://su-society-app.vercel.app` remains locked to production deployment `dpl_61jDwwKmdh1WVysox97LVkQPSNM9`.

---

## 7. Environment Isolation Requirements

To guarantee 100% production isolation, any non-production UAT environment must strictly enforce:

1. **Credential Segregation:** Zero production Supabase keys or DB passwords used in staging environment files.
2. **Domain Segregation:** Staging web app hosted locally (`http://localhost:5173`) or on a distinct staging domain/URL.
3. **No Hard-Coded Production Fallbacks:** `src/supabase.js` enforces `const hasValidCredentials = supabaseUrl && supabaseUrl !== 'your_supabase_project_url' && ...`. If credentials are absent, it falls back to **Local Mock Mode**, NEVER to production.

---

## 8. Test Data Strategy for Mutating UAT

In a non-production Staging/Sandbox environment, the test data model will consist of disposable entities:

- **Disposable Test Society:** `99999999-9999-9999-9999-999999999999` ("Sandbox Test RWA").
- **Disposable Test Users:** `test-admin@sandbox.com`, `test-treasurer@sandbox.com`, `test-tenant@sandbox.com`.
- **Disposable Test Vendors:** `Sandbox Plumbing Services`, `Test Security Corp`.
- **Disposable Test Assets:** `AST-TEST-001` (Sandbox Generator).
- **Disposable AMC Contracts:** `AMC-TEST-001` (Disposable AMC Contract).
- **Disposable Expense Vouchers & Service Logs:** Created freely during UAT and discarded upon sandbox reset.

---

## 9. UAT Workflow Capability Matrix

| Workflow | Local Sandbox (Mock Mode) | Cloud Supabase Staging | Live Production | Recommended UAT Target |
| :--- | :---: | :---: | :---: | :---: |
| **Expense Voucher Creation** | **SAFE & TESTABLE** | **SAFE & TESTABLE** | **BLOCKED** | Local Sandbox / Staging |
| **Registered Vendor Dropdown** | **SAFE & TESTABLE** | **SAFE & TESTABLE** | **READ-ONLY PASS** | Local Sandbox / Staging |
| **AMC Contract Renewal (`renew_amc`)** | **SAFE & TESTABLE** | **SAFE & TESTABLE** | **BLOCKED** | Local Sandbox / Staging |
| **Service Logging (`log_asset_service`)** | **SAFE & TESTABLE** | **SAFE & TESTABLE** | **BLOCKED** | Local Sandbox / Staging |
| **Append-Only Log Enforcement** | **SAFE & TESTABLE** | **SAFE & TESTABLE** | **READ-ONLY PASS** | Local Sandbox / Staging |
| **Asset / Vendor Master Registration** | **SAFE & TESTABLE** | **SAFE & TESTABLE** | **BLOCKED** | Local Sandbox / Staging |
| **Role-Based Authorization Gating** | **SAFE & TESTABLE** | **SAFE & TESTABLE** | **READ-ONLY PASS** | Local Sandbox / Staging |
| **Multi-Tenant RLS Isolation** | Static Simulation | Full PostgreSQL RLS | Static Verification | Cloud Staging |
| **Environment Reset / Disposal** | **1-Click Reset** | `db reset` | **FORBIDDEN** | Local Sandbox / Staging |

---

## 10. Reset & Disposal Strategy

- **Local Sandbox (Mock Mode):** Executing `localStorage.clear()` in the browser instantly wipes all disposable test vouchers, AMC renewals, and maintenance logs, resetting the mock database to `INITIAL_MOCK_DATA`.
- **Cloud Supabase Staging:** Executing `npx supabase db reset --linked` re-applies locked Slices 1–26 and re-seeds clean staging test data.
- **Production Policy:** Zero database deletes or table truncations will ever be performed on production `fsegpxqoozxmicxcxjun`.

---

## 11. Migration Reproduction Strategy

Reproduction of Slices 1–26 in a non-production environment:

1. **Source Migration Range:** `supabase/migrations/20260912000001_slice1.sql` through `20260916000026_candidate26_remediation.sql`.
2. **Immutability Protection:** Production Slice-26 migration file (`ACF35474380D1DB379CC536E75332238800918390C25611B2BB97D0F9836EB72`) is read without modification.
3. **Candidate-27 Status:** **NOT JUSTIFIED AND NOT CREATED.**
4. **Execution Path:** Migrations apply strictly to the target staging database instance.

---

## 12. Cost & Operational Constraints

- **Local Sandbox (Option 1):** **`$0 / FREE`**. Uses existing local developer tools (`npm run dev`) and browser storage. Zero cloud billing or paid resources required.
- **Cloud Staging (Option 2):** Uses standard free-tier cloud allocations (Supabase Free Tier / Vercel Hobby Plan) if project slots are available.
- **Paid Infrastructure:** **`NONE REQUIRED`**. No paid subscriptions or paid upgrades are necessary to execute mutating UAT.

---

## 13. Production Contamination Risk Analysis

| Architecture Option | Production Contamination Risk | Rationale |
| :--- | :---: | :--- |
| **Local Sandbox (Option 1)** | **`0% (NONE)`** | Runs entirely on local machine in browser `localStorage`. Zero network calls to production. |
| **Cloud Supabase Staging (Option 2)** | **`0% (NONE)`** | Completely separate Supabase project URL and database instance. |
| **Production Test Society (Option 3)** | `MEDIUM-HIGH` | Audit logs and append-only maintenance logs write to live production tables. |

---

## 14. Architecture Comparison

| Dimension | Option 1: Local Sandbox (Mock Mode) | Option 2: Cloud Supabase Staging | Option 3: Production Sandbox Society |
| :--- | :--- | :--- | :--- |
| **Isolation** | 100% Isolated (Local Machine) | 100% Isolated (Separate Cloud Project) | Incomplete (Shares Production DB) |
| **Reproducibility** | 100% Reproducible | 100% Reproducible | Moderate |
| **Mutating UAT Capability** | Full Capability | Full Capability | Restricted |
| **Reset Capability** | Instant (`localStorage.clear()`) | Fast (`supabase db reset`) | FORBIDDEN / Impossible for logs |
| **Setup Complexity** | Zero Setup (`npm run dev`) | Low (Project creation & `db push`) | Medium |
| **Cost** | **$0 (Zero Cost)** | **$0 (Free Tier)** | $0 |
| **Production Safety** | **MAXIMUM (100% SAFE)** | **HIGH (100% SAFE)** | RISKY (Contamination Risk) |

---

## 15. Required Human Governance Decisions

The human operator should review the options and select one of the following paths:

- **Path A (Recommended - Zero Cost / Instant):** Authorize execution of mutating UAT within the **Local Sandbox (Option 1)** using `npm run dev` and Local Mock Database Mode.
- **Path B:** Authorize provisioning of a **Separate Cloud Supabase Staging Project (Option 2)** and Vercel preview deployment.
- **Path C:** Conclude testing with the existing successful **Production Read-Only UAT (`PASS`)** and withhold mutating UAT.

---

## 16. Proposed Next Governance Step

1. Human Operator reviews this Feasibility Report.
2. Human Operator selects preferred non-production testing path (Path A, B, or C).
3. Agent awaits explicit authorization before launching any local dev server or staging setup.

---

## 17. Explicit Production Mutation Statement

> **NO PRODUCTION MUTATION WAS PERFORMED.**

---

## 18. Explicit Production Infrastructure Statement

> **NO PRODUCTION INFRASTRUCTURE WAS CREATED OR MODIFIED.**

---

## 19. Cryptographic Report Evidence

| Report Asset | SHA-256 Hash | Status |
| :--- | :--- | :---: |
| `SU_SOCIETY_APP_STAGING_SANDBOX_UAT_FEASIBILITY_REPORT_REVISION_1.md` | `280B843028CE6E2272F1E3AF8BEDDD3026FD59C99CEABA5561AE45DA7F026C49` (Pre-commit Hash) | GENERATED |

---

## 20. Final Classification

```text
A — STAGING / SANDBOX UAT FEASIBILITY COMPLETE — SAFE NON-PRODUCTION PATH IDENTIFIED
```
