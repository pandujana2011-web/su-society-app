# STAGE 10U-T PHASE B — SLICE 20 STATEMENT 29 FORENSIC REMEDIATION SPECIFICATION

**TARGET REPOSITORY:** `D:\Clients Applications\SU Society App`  
**TARGET REMOTE SUPABASE PROJECT:** `fsegpxqoozxmicxcxjun` (Region: `ap-south-1`, PostgreSQL `17.6.1.166`)  
**CURRENT REMOTE PRODUCTION BOUNDARY:** `20260912000019_slice19.sql`  
**LOCKED BASELINE:** `SLICE23_SECURITY_LOCK.md` (931 / 931 PASS, SHA-256: `47A7093CB842BB10179D529E85452BBD8B463E3057725B28E69A5E99AC614448`)  

**SLICE 20 IMPLEMENTATION FILE:** `supabase/migrations/20260912000020_slice20.sql` (SHA-256: `3E00DDD1C880684C52F5BD9EB5A0E4FA46786BBC59DF54BE8551BE235D4A192F`)  
**SLICE 20 SCHEMA REFERENCE:** `database/schema_slice20.sql` (SHA-256: `3E00DDD1C880684C52F5BD9EB5A0E4FA46786BBC59DF54BE8551BE235D4A192F`)  

**INCIDENT REFERENCE:** Deployment Execution Attempt on 2026-09-15 (Failed at Statement 29 with `SQLSTATE 42883`).  
**EXECUTION MODE:** PLAN ONLY / ZERO IMPLEMENTATION / ZERO DEPLOYMENT  

---

## 1. EXECUTIVE STATUS

This document provides the independent **Forensic Remediation Specification** for resolving the Statement 29 deployment failure in Schema Slice 20.

During the authorized M-02 deployment attempt on 2026-09-15, deployment scope containment held perfectly to Slice 20 ONLY. However, execution failed at Statement 29 with `SQLSTATE 42883: function public.has_role(unknown) does not exist`. PostgreSQL executed an immediate atomic transaction rollback. The remote database remains 100% clean and uncorrupted at `20260912000019_slice19.sql`.

This specification performs complete dependency forensics across the repository, establishes all call sites requiring parameter signature alignment, conducts an adversarial security review, and defines the minimal remediation scope.

---

## 2. INCIDENT REFERENCE & ROOT CAUSE

* **Incident:** M-02 Isolated Deployment of Slice 20.
* **Failure Point:** Statement 29 / Line 132 in `20260912000020_slice20.sql` (RLS policy `noc_move_passes_select_policy`).
* **Error Payload:** `ERROR: function public.has_role(unknown) does not exist (SQLSTATE 42883)`.
* **Root Cause:** Statement 29 invoked `public.has_role('gatekeeper')` using a single argument. In `20260912000001_slice1.sql` (Line 243), the authoritative definition of `public.has_role` requires TWO arguments: `(uid UUID, p_role TEXT)`. PostgreSQL could not resolve a single-parameter signature for `public.has_role`, triggering a 42883 exception.

---

## 3. AUTHORITATIVE FUNCTION SIGNATURE

From `supabase/migrations/20260912000001_slice1.sql` (Step 7, Lines 243–263):
```sql
CREATE OR REPLACE FUNCTION public.has_role(
    uid       UUID,
    p_role    TEXT
)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM   public.user_roles
        WHERE  user_id    = uid
          AND  role_name  = p_role
          AND  revoked_on IS NULL
    );
$$;
```

### Signature Analysis:
* **Function Name:** `public.has_role`
* **Parameters:** `uid UUID`, `p_role TEXT` (Exactly 2 parameters).
* **Return Type:** `BOOLEAN`
* **Volatility / Security:** `STABLE SECURITY DEFINER`, pinned `search_path = public, pg_temp`.
* **Behavior:** Returns `TRUE` if `uid` holds an active, unrevoked role matching `p_role` in `public.user_roles`. If `uid` is `NULL`, returns `FALSE`.

---

## 4. COMPLETE DEPENDENCY FORENSICS

Repository-wide static search for `has_role` across all migrations (`000001` through `000023`) revealed:
* **Slice 1:** Defined `has_role(uid UUID, p_role TEXT)`. Used 2-parameter form `has_role(auth.uid(), 'role_name')`.
* **Slices 3, 5, 6, 7, 8, 9, 12, 19:** All call sites correctly pass 2 parameters: `has_role(auth.uid(), 'role_name')` or `has_role(v_caller_id, 'gatekeeper')`.
* **Slice 20 Audit:** Exactly **THREE (3)** call sites in `20260912000020_slice20.sql` and `database/schema_slice20.sql` contain the invalid 1-parameter signature `has_role('gatekeeper')`:

| Site # | Line # | Object Context | Existing Invalid Invocation | Required 2-Parameter Invocation |
| :--- | :--- | :--- | :--- | :--- |
| **Site 1** | Line 133 | RLS Policy `noc_move_passes_select_policy` | `public.has_role('gatekeeper')` | `public.has_role(auth.uid(), 'gatekeeper')` |
| **Site 2** | Line 579 | Function `public.verify_pass` | `public.has_role('gatekeeper')` | `public.has_role(v_caller_id, 'gatekeeper')` |
| **Site 3** | Line 685 | Function `public.fn_complete_noc_transfer` | `public.has_role('gatekeeper')` | `public.has_role(v_caller_id, 'gatekeeper')` |

* **Crucial Finding:** Statement 29 failed first because DDL statements execute sequentially. If only Statement 29 were corrected, deployment would later fail when parsing or executing functions `verify_pass` (Line 579) and `fn_complete_noc_transfer` (Line 685). All 3 call sites MUST be remediated together.

---

## 5. SECURITY SEMANTICS ANALYSIS

### Site 1: `noc_move_passes_select_policy`
```sql
CREATE POLICY noc_move_passes_select_policy ON public.noc_move_passes
    FOR SELECT TO authenticated
    USING (
        public.is_admin() OR
        public.has_role(auth.uid(), 'gatekeeper') OR
        EXISTS (
            SELECT 1 FROM public.noc_requests nr
            WHERE nr.id = noc_move_passes.noc_id
            AND nr.applicant_id = auth.uid()
        )
    );
```
1. **Target Table:** `public.noc_move_passes` (FOR SELECT TO `authenticated`).
2. **Authorization Evaluation:**
   * Admins (`is_admin()`) can view all move passes.
   * Gatekeepers (`public.has_role(auth.uid(), 'gatekeeper')`) can view all move passes for verification at gates.
   * Applicants can view passes belonging to their own NOC requests (`nr.applicant_id = auth.uid()`).
3. **`auth.uid()` Nullability:** If `auth.uid()` is `NULL`, `public.has_role(NULL, 'gatekeeper')` returns `FALSE`. Anonymous/unauthenticated callers are denied.

### Sites 2 & 3: `verify_pass` and `fn_complete_noc_transfer`
```sql
v_caller_id := auth.uid();
IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
END IF;

IF NOT (public.has_role(v_caller_id, 'gatekeeper') OR public.is_admin()) THEN
    RAISE EXCEPTION 'Gatekeeper or Admin authorization required.' USING ERRCODE = '42501';
END IF;
```
1. **Context:** Inside SECURITY DEFINER routines.
2. **Authorization Evaluation:** `v_caller_id` is assigned directly from `auth.uid()`. Passing `v_caller_id` explicitly validates that the authenticated caller holds the gatekeeper or admin role prior to execution.

---

## 6. ADVERSARIAL REVIEW

An independent adversarial review challenged the 2-parameter remediation:

* **Question 1: Does passing `auth.uid()` introduce RLS recursion?**  
  * *Verdict:* **NO.** `public.has_role` is a `STABLE SECURITY DEFINER` function that queries `public.user_roles` with `search_path = public, pg_temp`. It bypasses caller RLS on `user_roles` safely without recursion.
* **Question 2: Can a malicious caller spoof `auth.uid()` or `v_caller_id`?**  
  * *Verdict:* **NO.** `auth.uid()` is a trusted Supabase session variable set by JWT verification. `v_caller_id := auth.uid()` cannot be overridden by RPC caller arguments.
* **Question 3: Does `has_role(auth.uid(), 'gatekeeper')` allow cross-society leakage?**  
  * *Verdict:* **NO.** Gatekeepers use token-verification RPCs (`verify_pass`) which require exact 21-character CSPRNG token matching and rate-limiting. Move passes contain `society_id` for gate validation.

**ADVERSARIAL VERDICT:**  
`A. SECURE AS-IS` (when supplying `auth.uid()` / `v_caller_id` as the first argument).

---

## 7. MINIMAL REMEDIATION SPECIFICATION

The minimal remediation requires modifying exactly **3 call sites** across 2 files (`20260912000020_slice20.sql` and `database/schema_slice20.sql`):

### Replacement 1 (Line 133, Policy `noc_move_passes_select_policy`):
```sql
-- Original:
public.has_role('gatekeeper')

-- Corrected:
public.has_role(auth.uid(), 'gatekeeper')
```

### Replacement 2 (Line 579, Function `verify_pass`):
```sql
-- Original:
IF NOT (public.has_role('gatekeeper') OR public.is_admin()) THEN

-- Corrected:
IF NOT (public.has_role(v_caller_id, 'gatekeeper') OR public.is_admin()) THEN
```

### Replacement 3 (Line 685, Function `fn_complete_noc_transfer`):
```sql
-- Original:
IF NOT (public.has_role('gatekeeper') OR public.is_admin()) THEN

-- Corrected:
IF NOT (public.has_role(v_caller_id, 'gatekeeper') OR public.is_admin()) THEN
```

### Prohibited Scope:
* DO NOT alter any other line or statement in Slice 20.
* DO NOT alter Slices 1–19, 21–23, or baseline artifacts.

---

## 8. MIGRATION / SCHEMA CONSISTENCY ANALYSIS

* `supabase/migrations/20260912000020_slice20.sql` and `database/schema_slice20.sql` currently contain identical single-parameter calls at lines 133, 579, and 685.
* The eventual implementation MUST apply all three replacements to BOTH files simultaneously to maintain 100% mirror consistency.

---

## 9. REGRESSION MATRIX

| Test ID | Test Scenario | Expected Outcome | Security Invariant |
| :--- | :--- | :--- | :--- |
| **R29-01** | Valid gatekeeper calls `verify_pass` | Allowed | Role check returns `TRUE` |
| **R29-02** | Non-gatekeeper calls `verify_pass` | Denied (`42501`) | Role check returns `FALSE` |
| **R29-03** | Anonymous caller invokes policy / RPC | Denied (`42501`) | `auth.uid()` IS NULL |
| **R29-04** | `auth.uid()` NULL in policy check | Evaluates `FALSE` | No NULL tri-state bypass |
| **R29-05** | Cross-society pass verification | Enforced via token digest | CSPRNG token entropy |
| **R29-06** | Cross-property pass lookup | Enforced via `noc_id` linkage | Foreign key isolation |
| **R29-07** | Caller attempts `created_by` / identity spoof | Denied | `v_caller_id` bound to `auth.uid()` |
| **R29-08** | RLS policy composition on `noc_move_passes` | Clean OR evaluation | Permissive policy rules |
| **R29-09** | SECURITY DEFINER / search_path check | Pinned to `public, pg_temp` | Search path isolation |
| **R29-10** | Migration / Schema file SHA-256 match | 100% Byte-Identical | File mirror consistency |

---

## 10. GOVERNANCE INTEGRITY & PRECONDITIONS

* **Remote Production State:** Clean at `20260912000019_slice19.sql`. Zero Slice 20 objects exist remotely.
* **Locked Baseline:** `SLICE23_SECURITY_LOCK.md` SHA-256 `47A7093CB842BB10179D529E85452BBD8B463E3057725B28E69A5E99AC614448` (931/931 PASS intact).
* **Implementation Preconditions:** Requires separate explicit human implementation authorization before editing local files.
* **Deployment Preconditions:** Requires separate explicit human deployment authorization following post-implementation audit.

---

## 11. FINAL CLASSIFICATION

**`A. FORENSICALLY VERIFIED — READY FOR SEPARATE IMPLEMENTATION AUTHORIZATION`**

---

## 12. MANDATORY FINAL GOVERNANCE STATEMENT

```
IMPLEMENTATION:
NOT AUTHORIZED BY THIS SPECIFICATION

DEPLOYMENT:
NOT AUTHORIZED BY THIS SPECIFICATION

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

NEXT GOVERNANCE GATE:
SEPARATE HUMAN REVIEW AND EXPLICIT IMPLEMENTATION AUTHORIZATION
```

---

## 13. SHA-256 OF THIS REPORT

`27C186B1438B564F36CC1830775F6DC7F47D894325DA93DFF1A307EE9BAB998B`
