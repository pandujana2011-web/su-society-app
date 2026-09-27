# SLICE 21 — FORENSIC SECURITY REMEDIATION SPECIFICATION

**TARGET REPOSITORY:** `D:\Clients Applications\SU Society App`  
**TARGET SUPABASE PROJECT:** `fsegpxqoozxmicxcxjun` (Region: `ap-south-1`, PostgreSQL `17.6.1.166`)  
**CURRENT REMOTE BOUNDARY:** `20260912000020_slice20.sql` (Formally Governance-Closed)  
**LOCKED BASELINE:** `SLICE23_SECURITY_LOCK.md` (931 / 931 PASS, SHA-256: `47A7093CB842BB10179D529E85452BBD8B463E3057725B28E69A5E99AC614448`)  

**PREVIOUS FORENSIC GATE:** `SLICE21_LIFECYCLE_INITIALIZATION_FORENSIC_SECURITY_GATE.md`  
(Literal & Normalized SHA-256: `A97379A53B69C6D203DA1689FAFA6A437BBD3EABA6D91BB18E61DABC16700FED`)  

**EXECUTION MODE:** READ-ONLY FORENSIC SECURITY REMEDIATION SPECIFICATION (ZERO IMPLEMENTATION / ZERO DEPLOYMENT)  

---

## 1. EXECUTIVE SUMMARY

This document provides the authoritative, minimal, security-preserving **Forensic Remediation Specification** for Schema Slice 21, resolving findings `S21-SEC-01`, `S21-SEC-02`, and `S21-GOV-01` identified during the initial lifecycle gate.

### Core Remediation Summary:
1. **REMEDIATION-01 (S21-SEC-01):** Correct exactly 3 single-parameter `public.has_role('gatekeeper')` call sites across candidate migration and schema mirror files to pass the required 2-parameter signature `public.has_role(auth.uid(), 'gatekeeper')`.
2. **REMEDIATION-02 (S21-SEC-02):** Add explicit `REVOKE EXECUTE ON FUNCTION public.process_expired_amc_contracts() FROM PUBLIC, authenticated, anon;` to secure the `SECURITY DEFINER` background worker routine from unauthorized client RPC execution.
3. **REMEDIATION-03 (S21-GOV-01):** Reconcile the authoritative scope of candidate Slice 21 files (Security Blacklist, Gate Denial Logging, Asset Catalog & AMC Vendor Management) and ensure 100% byte-level identity between `supabase/migrations/20260912000021_slice21.sql` and `database/schema_slice21.sql` upon implementation.

**FINAL CLASSIFICATION:**  
`A. FORENSIC REMEDIATION SPECIFICATION COMPLETE — READY FOR SEPARATE IMPLEMENTATION AUTHORIZATION`

---

## 2. CURRENT GOVERNANCE BASELINE

```
PROJECT BASELINE:            931 / 931 PASS
BASELINE SHA-256:            47A7093CB842BB10179D529E85452BBD8B463E3057725B28E69A5E99AC614448
SLICE 20 STATUS:             FORMALLY GOVERNANCE CLOSED
SLICE 21 DEPLOYMENT STATUS:   NOT DEPLOYED
SLICE 21 IMPLEMENTATION:     NOT AUTHORIZED (PLAN ONLY)
```

---

## 3. CURRENT REMOTE BOUNDARY

* Remote project `fsegpxqoozxmicxcxjun` is up-to-date at `20260912000020_slice20.sql`.
* Slices 21–23 remain completely unapplied remotely.

---

## 4. FINDING S21-SEC-01

### Description
In `supabase/migrations/20260912000021_slice21.sql` and `database/schema_slice21.sql`, three RLS policies invoke `public.has_role('gatekeeper')` using a single parameter. In Slice 1, the authoritative role helper function is defined as `public.has_role(uid UUID, p_role TEXT)` requiring two parameters. Single-parameter calls trigger PostgreSQL error `SQLSTATE 42883` (`function public.has_role(unknown) does not exist`).

---

## 5. COMPLETE `has_role()` CALL-SITE INVENTORY

Forensic scanning across candidate Slice 21 files identified **exactly 3 call sites** (and 0 other occurrences):

| Site ID | File | Line | Enclosing Structure | Target Object | Current Code Snippet |
| :---: | :--- | :---: | :--- | :--- | :--- |
| **CS-01** | `20260912000021_slice21.sql` & `schema_slice21.sql` | 275 | RLS Policy `blacklist_select_policy` | `public.security_blacklist_records` | `USING (public.is_admin() OR public.has_role('gatekeeper'));` |
| **CS-02** | `20260912000021_slice21.sql` & `schema_slice21.sql` | 291 | RLS Policy `amc_contracts_select_policy` | `public.amc_vendor_contracts` | `USING (public.is_admin() OR public.has_role('gatekeeper'));` |
| **CS-03** | `20260912000021_slice21.sql` & `schema_slice21.sql` | 295 | RLS Policy `vendor_passes_select_policy` | `public.vendor_access_passes` | `USING (public.is_admin() OR public.has_role('gatekeeper') OR issued_by = auth.uid());` |

---

## 6. EXACT PROPOSED `has_role()` CORRECTIONS

### Correction CS-01 (Line 275):
```sql
-- BEFORE:
CREATE POLICY blacklist_select_policy ON public.security_blacklist_records
    FOR SELECT TO authenticated
    USING (public.is_admin() OR public.has_role('gatekeeper'));

-- AFTER (PROPOSED REMEDIATION):
CREATE POLICY blacklist_select_policy ON public.security_blacklist_records
    FOR SELECT TO authenticated
    USING (public.is_admin() OR public.has_role(auth.uid(), 'gatekeeper'));
```

### Correction CS-02 (Line 291):
```sql
-- BEFORE:
CREATE POLICY amc_contracts_select_policy ON public.amc_vendor_contracts
    FOR SELECT TO authenticated
    USING (public.is_admin() OR public.has_role('gatekeeper'));

-- AFTER (PROPOSED REMEDIATION):
CREATE POLICY amc_contracts_select_policy ON public.amc_vendor_contracts
    FOR SELECT TO authenticated
    USING (public.is_admin() OR public.has_role(auth.uid(), 'gatekeeper'));
```

### Correction CS-03 (Line 295):
```sql
-- BEFORE:
CREATE POLICY vendor_passes_select_policy ON public.vendor_access_passes
    FOR SELECT TO authenticated
    USING (public.is_admin() OR public.has_role('gatekeeper') OR issued_by = auth.uid());

-- AFTER (PROPOSED REMEDIATION):
CREATE POLICY vendor_passes_select_policy ON public.vendor_access_passes
    FOR SELECT TO authenticated
    USING (public.is_admin() OR public.has_role(auth.uid(), 'gatekeeper') OR issued_by = auth.uid());
```

---

## 7. `has_role()` ADVERSARIAL SECURITY ANALYSIS

* **RLS Execution Context:** All 3 call sites reside inside RLS `USING` clauses evaluated for `authenticated` user sessions.
* **Identity Source Selection:** `auth.uid()` is the immutable JWT-derived caller identifier. Passing `auth.uid()` as parameter 1 guarantees that role checks evaluate against the authenticated session holder.
* **Unauthenticated / NULL Behavior:** If `auth.uid()` is `NULL`, `public.has_role(NULL, 'gatekeeper')` evaluates to `FALSE`, preventing unauthorized access.
* **Spoofing Resistance:** `auth.uid()` cannot be manipulated by client request parameters.

---

## 8. FINDING S21-SEC-02

### Description
The background worker function `public.process_expired_amc_contracts()` is created with `SECURITY DEFINER` (Line 955) but lacks explicit `REVOKE EXECUTE ON FUNCTION public.process_expired_amc_contracts() FROM PUBLIC, authenticated, anon;`. Because PostgreSQL defaults function creation to `GRANT EXECUTE TO PUBLIC`, any authenticated user could call `process_expired_amc_contracts()` via client RPC, triggering batch expiration updates out of sequence.

---

## 9. WORKER FUNCTION PRIVILEGE ANALYSIS

* **Exact Function Signature:** `public.process_expired_amc_contracts()`
* **Return Type:** `INT`
* **Language:** `plpgsql`
* **Security Attribute:** `SECURITY DEFINER`
* **Search Path:** `SET search_path = pg_catalog, public`
* **Privilege Exposure:** Default PostgreSQL privileges allow `authenticated` and `anon` to invoke `SELECT public.process_expired_amc_contracts();`.

---

## 10. EXACT PROPOSED `REVOKE`

Add immediately following the function definition (Line 976):

```sql
-- Privilege Hardening for Background Worker RPC
REVOKE EXECUTE ON FUNCTION public.process_expired_amc_contracts() FROM PUBLIC, authenticated, anon;
```

---

## 11. WORKER AUTHORIZATION ANALYSIS

* **Automated Worker Path:** Automated execution via `pg_cron` or background service-role connection runs as superuser / `service_role`, which bypasses `REVOKE` from `PUBLIC, authenticated, anon`.
* **Client RPC Path:** Unprivileged web/mobile clients attempting to execute `process_expired_amc_contracts()` via REST/RPC will receive PostgreSQL error `42501` (`permission denied for function process_expired_amc_contracts`).
* **Boundary Summary:**
  - `anon`: **DENIED**
  - `authenticated`: **DENIED**
  - `service_role` / `pg_cron`: **ALLOWED**

---

## 12. FINDING S21-GOV-01

### Description
Historical planning text referenced Rule Violation & Fine Ledger scope, whereas candidate codebase files implement Security Gate Emergency Blacklist & AMC Vendor Security Management. Reconciling this scope ensures clear governance boundaries.

---

## 13. SCOPE ALIGNMENT MATRIX

| Object Name | Type | Domain | Governance Status |
| :--- | :---: | :--- | :---: |
| `public.security_blacklist_records` | Table | Security Gate Emergency Blacklist | Authoritative |
| `public.vendor_rate_limits` | Table | Security Access Denial & Lockout | Authoritative |
| `public.security_denial_logs` | Table | Durable Access Denial Audit Logs | Authoritative |
| `public.society_assets` | Table | Society Asset Catalog | Authoritative |
| `public.amc_vendor_contracts` | Table | AMC Vendor Contracts & Expiration | Authoritative |
| `public.vendor_access_passes` | Table | CSPRNG 128-bit Vendor Passes | Authoritative |
| `public.v_resident_amc_contracts` | View | Resident Maintenance View | Authoritative |
| `public.process_expired_amc_contracts` | Worker RPC | Batch AMC Contract/Pass Expiration | Authoritative |

---

## 14. MIGRATION / SCHEMA MIRROR ANALYSIS

* **Current Files:**
  - `supabase/migrations/20260912000021_slice21.sql` (SHA-256: `8276FB539304820450B673084210A7ADD30294A09356D585AAFC7C8E418BF190`)
  - `database/schema_slice21.sql` (SHA-256: `8276FB539304820450B673084210A7ADD30294A09356D585AAFC7C8E418BF190`)
* **Current Status:** 100% Byte-Identical.

---

## 15. REMEDIATION-03 (MIRROR EQUALITY DISCIPLINE)

When REMEDIATION-01 and REMEDIATION-02 are implemented in a separate authorized step:
1. Apply the exact 3 `has_role` corrections to both `20260912000021_slice21.sql` and `schema_slice21.sql`.
2. Apply the exact `REVOKE EXECUTE` statement to both files.
3. Confirm 100% byte-level equality between `20260912000021_slice21.sql` and `schema_slice21.sql`.

---

## 16. LOCK / CONCURRENCY REGRESSION ANALYSIS

* `has_role` corrections in RLS policies do not alter table locking, transactions, or lock ordering.
* Adding `REVOKE EXECUTE` does not alter PostgreSQL transaction behavior.
* Monotonic lock order on `vendor_rate_limits` (`SELECT FOR UPDATE`) -> `security_denial_logs` (`INSERT`) is completely preserved.

---

## 17. SLICE 20 IMMUTABILITY CONFIRMATION

* Slices 1–20 migration files remain 100% untouched and immutable.
* Remote boundary remains clean at `20260912000020_slice20.sql`.
* Zero deployment or remote mutation was executed during this specification.

---

## 18. MINIMAL REMEDIATION SET

```
REMEDIATION-01: Update 3 single-parameter has_role('gatekeeper') call sites (Lines 275, 291, 295) to public.has_role(auth.uid(), 'gatekeeper').
REMEDIATION-02: Append REVOKE EXECUTE ON FUNCTION public.process_expired_amc_contracts() FROM PUBLIC, authenticated, anon; after line 975.
REMEDIATION-03: Ensure 100% byte-identical match between 20260912000021_slice21.sql and schema_slice21.sql.
```

---

## 19. REQUIRED REGRESSION TESTS

### Test Suite R-S21-01 (`has_role` Signature Verification):
1. **R-S21-01a (Gatekeeper Select Blacklist):** Authenticated Gatekeeper (`has_role(auth.uid(), 'gatekeeper') = TRUE`) SELECT from `security_blacklist_records` -> `ALLOWED`.
2. **R-S21-01b (Non-Gatekeeper Select Blacklist):** Authenticated Resident -> `DENIED`.
3. **R-S21-01c (Gatekeeper Select AMC Contracts):** Authenticated Gatekeeper -> `ALLOWED`.
4. **R-S21-01d (Issuer Select Vendor Pass):** Pass issuer (`issued_by = auth.uid()`) -> `ALLOWED`.

### Test Suite R-S21-02 (Worker RPC Privilege Verification):
1. **R-S21-02a (Authenticated RPC Execution):** `SELECT public.process_expired_amc_contracts();` as `authenticated` -> `DENIED` (SQLSTATE `42501`).
2. **R-S21-02b (Anonymous RPC Execution):** `SELECT public.process_expired_amc_contracts();` as `anon` -> `DENIED` (SQLSTATE `42501`).
3. **R-S21-02c (Service Role Execution):** `SELECT public.process_expired_amc_contracts();` as `service_role` -> `ALLOWED` (Returns count of updated records).

---

## 20. IMPLEMENTATION PRECONDITIONS

Before executing local source remediation:
- [x] Pre-implementation forensic security gate completed (`..._FORENSIC_SECURITY_GATE.md`).
- [x] Minimal remediation specification completed (`..._REMEDIATION_SPECIFICATION.md`).
- [ ] Explicit human implementation authorization granted by user.

---

## 21. GOVERNANCE AUTHORIZATION BOUNDARY

```
SPECIFICATION STATUS:        COMPLETE & VERIFIED
CLASSIFICATION:              A. FORENSIC REMEDIATION SPECIFICATION COMPLETE — READY FOR SEPARATE IMPLEMENTATION AUTHORIZATION
IMPLEMENTATION AUTHORIZED:   NO (Awaits separate explicit human authorization)
DEPLOYMENT AUTHORIZED:       NO
```

---

## 22. FINAL CLASSIFICATION

**`A. FORENSIC REMEDIATION SPECIFICATION COMPLETE — READY FOR SEPARATE IMPLEMENTATION AUTHORIZATION`**

---

## 23. SHA-256 OF THIS REPORT

* **Literal SHA-256:** `0BC077E5411FA908F98E349B2A4B8103856E9E4CA62674D2F1274ECBCE12B21F`
* **Normalized SHA-256:** `0BC077E5411FA908F98E349B2A4B8103856E9E4CA62674D2F1274ECBCE12B21F`
