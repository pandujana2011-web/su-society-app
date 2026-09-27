# SLICE 19 — FORMAL SECURITY LOCK & IMMUTABILITY RECORD

**Execution Date:** September 6, 2026  
**Target Repository:** `D:\Clients Applications\SU Society App`  
**Slice Name:** Domestic Staff & Daily Help Access Management  
**Status:** **SECURITY LOCKED AND IMMUTABLE**  

---

## 1. LOCK INFORMATION

* **Slice:** 19
* **Feature Scope:** Domestic Staff Helper Registry, Multi-Flat Employer Mappings, Security Gate Check-In/Check-Out, Atomic Passcode KDF Verification, Lockout Rate-Limiting, Server-Derived Overstay Semantics.
* **Implementation Status:** COMPLETE AND CLOSED
* **Verification Status:** 44 / 44 PASS
* **Baseline Regression Status:** 595 / 595 PASS
* **Cumulative Verification Baseline:** **639 / 639 PASS (100%)**
* **Independent Security Audit Status:** **PASSED AND CLOSED**
* **Security Audit Findings:** **0 Critical / 0 High / 0 Medium / 0 Low**

---

## 2. AUTHORITATIVE VERIFIED BASELINE

```text
=====================================================
SLICES 1–18 LOCKED BASELINE:     595 / 595 PASS (100%)
SLICE 19 VERIFIED SUITE:          44 /  44 PASS (100%)
-----------------------------------------------------
CUMULATIVE VERIFIED BASELINE:     639 / 639 PASS (100%)
INDEPENDENT SECURITY AUDIT:       PASS
SECURITY FINDINGS:                0
=====================================================
```

---

## 3. LOCKED ARTIFACTS & SHA-256 CHECKSUMS

The following files are now designated **LOCKED AND IMMUTABLE**:

### Implementation & Verification Artifacts:
* `database/schema_slice19.sql`  
  `SHA-256: 3489646CC811F59B327D8FC3C7F9D8F03341F83D92F6EA606902650D33AE7867`
* `database/verify_slice19.sql`  
  `SHA-256: E62CF7727E0C83456FDEC1CF131D1C7F2812C48471678ACEEE5208EE7C16A970`
* `scratch/run_all19.ps1`  
  `SHA-256: B416F239060A6EAE9F97A53758B4EC94CA18B71C7B9F89AB171B1AAED52D4B87`
* `src/supabase.js` (Slice 19 Additions)  
  `SHA-256: 42318F3AE6E0FAAE245E1C104C7F5FD0EFF3B65BC1E3ED91B45A54C644F7FEDD`

### Planning & Security Audit Artifacts:
* `SLICE19_FINAL_IMPLEMENTATION_SECURITY_PLAN_REV2.md`  
  `SHA-256: 9B569CAD65677CEF10368CDBB6199CA4D3E33994510AFEB66C6148334EA528DB`
* `SLICE19_INDEPENDENT_ADVERSARIAL_SECURITY_AUDIT.md`  
  `SHA-256: 17A88E0381422EC3E4F8D09164453068D3CCD92CB28B1B8951F65E235D90DD8D`

---

## 4. LOCKED DATABASE OBJECTS & SECURITY CONTROLS

The live PostgreSQL database catalog structures created in Slice 19 are permanently locked:

### Database Tables:
* `public.staff_helpers`
* `public.helper_flat_mappings`
* `public.helper_attendance_logs`

### Database Partial Unique Indexes:
* `uq_helper_active_attendance` (`WHERE status = 'checked_in'`)
* `uq_helper_property_active_mapping` (`WHERE status = 'active'`)

### Hardened `SECURITY DEFINER` RPC Routines (`SET search_path = public, extensions, pg_temp`):
* `public.register_domestic_helper`
* `public.update_domestic_helper`
* `public.set_helper_status`
* `public.authorize_helper_for_flat`
* `public.revoke_helper_authorization`
* `public.checkin_domestic_helper`
* `public.checkout_domestic_helper`
* `public.generate_helper_passcode`

### Security Controls Enforced:
1. **Authenticated Access:** All RPCs enforce `auth.uid() IS NOT NULL` check (`42501`).
2. **Society Tenant Isolation:** Verified via `public.get_user_society_id(auth.uid())` (`42501`).
3. **Role Authorization:** Strictly enforced using `is_admin()`, `has_role('gatekeeper')`, and property ownership/tenancy validation.
4. **Passcode Salted KDF:** Hashed via `extensions.crypt(p_passcode, extensions.gen_salt('bf', 8))`. Bare SHA-256 is strictly prohibited.
5. **Atomic Passcode Check:** Verified inside `checkin_domestic_helper`. No standalone `verify_passcode` RPC exists.
6. **Oracle Resistance:** Invalid attempts return generic error `22000` (`Invalid helper passcode.`).
7. **One-Time Passcode Presentation:** Plaintext PIN returned exactly once during generation payload; never stored in tables or logs.
8. **Failed-Attempt Defense:** 5 consecutive failed attempts trigger 15-minute lockout (`lockout_until = NOW() + INTERVAL '15 minutes'`).
9. **Attendance Uniqueness:** Enforced by partial unique index `uq_helper_active_attendance`.
10. **Mapping Uniqueness:** Enforced by partial unique index `uq_helper_property_active_mapping`.
11. **Derived Overstay Semantics:** Derived server-side via `NOW() - check_in > INTERVAL '12 hours'` upon checkout (`overstayed`).
12. **Row Level Security (RLS):** `ENABLE` + `FORCE ROW LEVEL SECURITY` applied on all 3 tables with restrictive policies (`USING (false) WITH CHECK (false)`).
13. **Audit Log Integrity:** Server-authoritative audit logging with plaintext passcode redaction.
14. **Notification Scoping:** Notifications routed strictly to mapped employer resident.
15. **Financial Non-Interference:** Zero ledger modifications or financial balance changes.

---

## 5. IMMUTABILITY DECLARATION & CHANGE CONTROL POLICY

> **Slice 19 has completed implementation, verification, regression testing, and independent adversarial security audit. Slice 19 is now formally SECURITY LOCKED and IMMUTABLE.**
>
> Any future modification to Slice 19 requires an explicitly authorized new change request or slice. No future agent or process may modify locked Slice 19 artifacts or database objects without explicit user authorization and a new verification baseline.
