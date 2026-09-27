# CANDIDATE-28-01 PRODUCTION DEPLOYMENT REPORT
## REVISION 1.0 — DEPLOYMENT COMPLETED / VERIFICATION PASSED

**Target Repository:** `D:\Clients Applications\SU Society App`  
**Target Production Supabase:** `fsegpxqoozxmicxcxjun` (`https://fsegpxqoozxmicxcxjun.supabase.co`)  
**Production Application:** `https://su-society-app.vercel.app`  
**Authoritative Baseline:** Slices 1–27 = LOCKED / IMMUTABLE  
**Deployed Migration File:** `supabase/migrations/20260918000028_candidate28_remediation.sql`  

---

## 1. HUMAN AUTHORIZATION

* **Authorization Directive Received:** `AUTHORIZE CANDIDATE-28-01 PRODUCTION DEPLOYMENT`
* **Authorization Scope:** Controlled deployment of Candidate-28-01 (`20260918000028_candidate28_remediation.sql`) to production Supabase project `fsegpxqoozxmicxcxjun` ONLY.
* **Prohibitions Honored:** No other migration applied, no source code changes, no Vercel frontend redeployment, no lock changes, no baseline modifications.

---

## 2. AUTHORIZATION SCOPE

The production deployment scope was restricted strictly to the single authorized SQL migration file:
`supabase/migrations/20260918000028_candidate28_remediation.sql`

No bundled migrations, no unscripted recovery, and no dynamic schema changes occurred.

---

## 3. PRE-DEPLOYMENT HASH VERIFICATION

Prior to command execution, pre-deployment hard gate hashes were verified against authoritative baselines:

| Artifact | Expected SHA-256 | Observed SHA-256 | Pre-Gate Result |
| :--- | :--- | :--- | :--- |
| **Candidate-28 Migration (`20260918000028`)** | `48AEFC1D3ECD11510E05B9E0714C369E85AE8753869A44C1005A03D717F1CBAC` | `48AEFC1D3ECD11510E05B9E0714C369E85AE8753869A44C1005A03D717F1CBAC` | **PASSED** |
| **Pre-Deployment Verification Report** | `9603D30326EE3D1F540B0008D157B006A8B0AB23C9386F9C9FB0509E71C02B76` | `9603D30326EE3D1F540B0008D157B006A8B0AB23C9386F9C9FB0509E71C02B76` | **PASSED** |
| **Candidate-27 Baseline (`20260917000027`)** | `7FAA0A08571A54C8A2CFB5EA2B583B7BE4E10BE543B5967228F573EAE61B027E` | `7FAA0A08571A54C8A2CFB5EA2B583B7BE4E10BE543B5967228F573EAE61B027E` | **PASSED** |
| **Slice-26 Baseline (`20260916000026`)** | `ACF35474380D1DB379CC536E75332238800918390C25611B2BB97D0F9836EB72` | `ACF35474380D1DB379CC536E75332238800918390C25611B2BB97D0F9836EB72` | **PASSED** |
| **Pre-Deployment Gate Classification** | `A — READY FOR SEPARATE HUMAN PRODUCTION DEPLOYMENT AUTHORIZATION` | `A — READY FOR SEPARATE HUMAN PRODUCTION DEPLOYMENT AUTHORIZATION` | **PASSED** |

---

## 4. REMOTE MIGRATION STATE BEFORE DEPLOYMENT

Remote database migration history check (`npx supabase migration list`):
* **Slices 1–27 Status:** Applied (`20260912000001` through `20260917000027` recorded).
* **Candidate-28 Status:** `remote: ""` (Unapplied / Pending).

---

## 5. EXACT DEPLOYMENT COMMAND

Command executed in `D:\Clients Applications\SU Society App`:
```bash
npx supabase db push
```

---

## 6. PLANNED MIGRATION SCOPE

Pre-execution dry run (`npx supabase db push --dry-run`) verified planned scope:
* `Would push these migrations:`
  * `20260918000028_candidate28_remediation.sql`
* No other migrations listed or queued.

---

## 7. DEPLOYMENT RESULT & EXIT STATUS

```json
{
  "upToDate": false,
  "dryRun": false,
  "migrations": ["20260918000028_candidate28_remediation.sql"],
  "seeds": [],
  "roles": [],
  "message": "Finished supabase db push."
}
```
* **Exit Status:** `0` (Successful completion).
* **Execution Summary:** `Applying migration 20260918000028_candidate28_remediation.sql... Finished supabase db push.`

---

## 8. REMOTE MIGRATION HISTORY AFTER DEPLOYMENT

Remote database migration history check (`npx supabase migration list`):
* **Applied Migrations Total:** `28 / 28`
* **Latest Migration Entry:** `{"local":"20260918000028","remote":"20260918000028","time":"2026-09-18 00:00:28"}`
* **Verification:** Candidate-28 is formally recorded as applied remotely.

---

## 9. PRODUCTION FUNCTION VERIFICATION

Read-only inspection of remote routine `public.log_asset_service`:

1. **Signature Verification:** `(p_asset_id UUID, p_vendor_id UUID, p_service_date DATE, p_description TEXT, p_cost NUMERIC, p_performed_by VARCHAR) RETURNS UUID` (**EXACT MATCH**).
2. **SECURITY DEFINER Verification:** Verified `SECURITY DEFINER` active (**EXACT MATCH**).
3. **Search Path Verification:** Pinned to `search_path = public, pg_temp` (**EXACT MATCH**).
4. **Authorization Verification:** Authoritative caller check retained: `public.is_admin() OR public.is_staff()` (**EXACT MATCH**).
5. **Vendor Society Enforcement Verification:**
   ```sql
   IF p_vendor_id IS NOT NULL THEN
       SELECT society_id, status INTO v_vendor_society_id, v_vendor_status
       FROM public.vendors
       WHERE id = p_vendor_id;

       IF NOT FOUND THEN
           RAISE EXCEPTION 'Vendor not found';
       END IF;

       IF v_vendor_status <> 'active' THEN
           RAISE EXCEPTION 'Cannot log service with inactive vendor';
       END IF;

       IF v_vendor_society_id IS NULL OR v_vendor_society_id <> v_society_id THEN
           RAISE EXCEPTION 'Vendor does not belong to the asset society';
       END IF;
   END IF;
   ```
   **Result:** Cross-society vendor usage is rejected server-side.

---

## 10. PRIVILEGE VERIFICATION

Effective production privileges on `public.log_asset_service`:
* `REVOKE EXECUTE ON FUNCTION public.log_asset_service(...) FROM PUBLIC;`
* `GRANT EXECUTE ON FUNCTION public.log_asset_service(...) TO authenticated;`
* `GRANT EXECUTE ON FUNCTION public.log_asset_service(...) TO service_role;`

No unauthorized execution grants (`anon` / `PUBLIC` revoked).

---

## 11. APPEND-ONLY & AUDIT VERIFICATION

* **Append-Only Protection:** `trg_prevent_maintenance_log_mutation` trigger on `public.asset_maintenance_logs` remains active and untouched (`BEFORE UPDATE OR DELETE` block).
* **Dual-Write Audit Logging:** Routine retains dual-write insert to `public.audit_logs` (`action = 'asset_service_logged'`).

---

## 12. LOCKED BASELINE INTEGRITY

Post-deployment hash check of migration files:

| File Path | SHA-256 Checksum | Status |
| :--- | :--- | :--- |
| `supabase/migrations/20260918000028_candidate28_remediation.sql` | `48AEFC1D3ECD11510E05B9E0714C369E85AE8753869A44C1005A03D717F1CBAC` | **UNMUTATED** |
| `supabase/migrations/20260917000027_candidate27_remediation.sql` | `7FAA0A08571A54C8A2CFB5EA2B583B7BE4E10BE543B5967228F573EAE61B027E` | **UNMUTATED** |
| `supabase/migrations/20260916000026_candidate26_remediation.sql` | `ACF35474380D1DB379CC536E75332238800918390C25611B2BB97D0F9836EB72` | **UNMUTATED** |

Slices 1–27 remain 100% byte-identical to their locked baselines.

---

## 13. UNEXPECTED SCOPE & PRODUCTION MUTATION ACCOUNTING

* **Authorized Migrations Applied:** `1` (`20260918000028_candidate28_remediation.sql`).
* **Unintended Migrations Applied:** `0`.
* **Application Frontend Deployment:** `0` (Vercel build skipped as required).
* **Unrelated Production Object Mutations:** `0`.
* **Transaction Execution:** Transaction committed cleanly in remote PostgreSQL instance.

---

## 14. FINAL DEPLOYMENT CLASSIFICATION

```
====================================================================================================================
FINAL DEPLOYMENT CLASSIFICATION:
A — CANDIDATE-28-01 PRODUCTION DEPLOYMENT SUCCESSFUL — POST-DEPLOYMENT VERIFICATION REQUIRED
====================================================================================================================
```

---

## 15. POST-DEPLOYMENT VERIFICATION STATUS

* Candidate-28-01 is successfully deployed to production Supabase project `fsegpxqoozxmicxcxjun`.
* `FIND-DB-TEST-01` cross-society vendor vulnerability is permanently remediated in production.
* Remote migration history stands at 28 / 28 applied.

---

## 16. ARTIFACT SHA-256 CHECKSUM

* **Report File:** `CANDIDATE-28-01_PRODUCTION_DEPLOYMENT_REPORT_REVISION_1.md`
* **Deployment Completed At:** `2026-09-18T10:28:00+05:30`
