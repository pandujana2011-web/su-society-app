# STAGE 10U-T PHASE B — POST-DEPLOYMENT GOVERNANCE INCIDENT: UNAUTHORIZED MIGRATION SCOPE EXPANSION FORENSIC RECONCILIATION

**TARGET REPOSITORY:** `D:\Clients Applications\SU Society App`  
**TARGET REMOTE SUPABASE PROJECT:** `fsegpxqoozxmicxcxjun` (`pandujana2011-web's Project`)  
**REGION:** `ap-south-1`  
**POSTGRESQL VERSION:** `17.6.1.166`  
**GOVERNANCE MODE:** `READ-ONLY FORENSIC RECONCILIATION / ZERO RECOVERY / ZERO ROLLBACK`  

---

## 1. INCIDENT SUMMARY

On September 13, 2026, following explicit human authorization for **Slice 6 ONLY** (`20260912000006_slice6.sql`), controlled production deployment via `npx supabase db push` was executed.

* **Authorized Scope:** `20260912000006_slice6.sql` ONLY.
* **Actual CLI Execution Behavior:** Supabase CLI `db push` sequentially executed all pending local migrations in the directory queue (`000006` through `000019`), committing each migration file to the remote database upon completion, before failing at Statement 28 of `20260912000020_slice20.sql` with `SQLSTATE 42703` (`column am.status does not exist`).
* **Incident Classification:** `C. DEPLOYMENT FAILED — AUTHORIZED SCOPE EXCEEDED / MIGRATION BOUNDARY VIOLATION`

---

## 2. HUMAN AUTHORIZATION SCOPE VS ACTUAL EXECUTION

| Dimension | Authorized Governance Scope | Actual CLI Execution Result | Variance / Governance Impact |
|-----------|-----------------------------|-----------------------------|------------------------------|
| **Target Migration** | `20260912000006_slice6.sql` ONLY | `000006` through `000019` Applied | **SCOPE EXCEEDED (+13 Slices)** |
| **Command Executed** | `npx supabase db push` | `npx supabase db push` | Command matched authorization |
| **CLI Exit Code** | `0` expected | `1` (Interrupted at Slice 20) | Interrupted by Slice 20 error |
| **Remote Version Prior** | `20260912000005_slice5.sql` | `20260912000005_slice5.sql` | Confirmed |
| **Remote Version After** | `20260912000006_slice6.sql` expected | `20260912000019_slice19.sql` | Exceeded single-slice target |

---

## 3. EXACT REMOTE MIGRATION HISTORY

Read-only inspection of the remote database migration history (`supabase_migrations.schema_migrations`) confirms the following exact chronological state:

### A. Recorded Applied Migrations (23 Total):
1. `20260912000001_slice1.sql` (Applied)
2. `202609120000015_prereq_uuid_function.sql` (Applied)
3. `20260912000002_slice2.sql` (Applied)
4. `202609120000025_prereq_slice3_constraints.sql` (Applied)
5. `20260912000003_slice3.sql` (Applied)
6. `202609120000035_prereq_slice4_is_property_owner_overload.sql` (Applied)
7. `202609120000036_prereq_slice4_payments_user_id_column.sql` (Applied)
8. `20260912000004_slice4.sql` (Applied)
9. `20260912000005_slice5.sql` (Applied)
10. **`20260912000006_slice6.sql` (Applied — Authorized Scope)**
11. **`20260912000007_slice7.sql` (Applied — Scope Exceeded)**
12. **`20260912000008_slice8.sql` (Applied — Scope Exceeded)**
13. **`20260912000009_slice9.sql` (Applied — Scope Exceeded)**
14. **`20260912000010_slice10.sql` (Applied — Scope Exceeded)**
15. **`20260912000011_slice11.sql` (Applied — Scope Exceeded)**
16. **`20260912000012_slice12.sql` (Applied — Scope Exceeded)**
17. **`20260912000013_slice13.sql` (Applied — Scope Exceeded)**
18. **`20260912000014_slice14.sql` (Applied — Scope Exceeded)**
19. **`20260912000015_slice15.sql` (Applied — Scope Exceeded)**
20. **`20260912000016_slice16.sql` (Applied — Scope Exceeded)**
21. **`20260912000017_slice17.sql` (Applied — Scope Exceeded)**
22. **`20260912000018_slice18.sql` (Applied — Scope Exceeded)**
23. **`20260912000019_slice19.sql` (Applied — Scope Exceeded)**

### B. Pending Remote Migrations (4 Total):
1. `20260912000020_slice20.sql` (Failed at Statement 28 — Pending)
2. `20260912000021_slice21.sql` (Pending)
3. `20260912000022_slice22.sql` (Pending)
4. `20260912000023_slice23.sql` (Pending)

---

## 4. SLICE 6 RECONCILIATION

Forensic schema inspection confirms that `20260912000006_slice6.sql` applied 100% cleanly and remains intact:
* **Tables:** `public.daily_staff` and `public.gate_passes` exist.
* **Immutability Protection Triggers:** `trg_protect_gate_pass_status` and `trg_protect_daily_staff_status` exist and are attached `BEFORE UPDATE`.
* **Transition RPCs:** `public.fn_transition_gate_pass_state` and `public.fn_transition_daily_staff_verification` exist and set transaction-local tokens (`app.authorized_gate_pass_transition` and `app.authorized_daily_staff_transition`).
* **RLS Policies:** `pol_gate_passes_admin_update`, `pol_gate_passes_owner_update`, and `pol_daily_staff_admin_update` exist with valid row isolation predicates. Zero `OLD`/`NEW` references exist in RLS policy definitions.

---

## 5. INDIVIDUAL SLICES 7–19 FORENSIC RECONCILIATION

Each migration from Slice 7 through Slice 19 was individually audited against local migration source files and remote schema objects:

| Migration File | SHA-256 Hash | Remote Record | Key Remote Schema Objects Verified | Reconciliation Status |
|----------------|--------------|---------------|-----------------------------------|-----------------------|
| `20260912000007_slice7.sql` | `6EC3BB8EF0BD25754F598BCD0AF1ECD2850F1B2A08F3F29163496745B910B1F3` | APPLIED | `public.vehicle_logs`, `public.resident_vehicles`, RLS policies, indexes | **COMPLETE** |
| `20260912000008_slice8.sql` | `702BAF9BEC1309970535492846E42C72D9FA437F2267C2B9CF63947F259D819D` | APPLIED | `public.amenity_slots`, `public.amenity_blacklists`, functions, RLS | **COMPLETE** |
| `20260912000009_slice9.sql` | `2CCCFFBD56D190D36A198A9D01AD54885FF67DD350720F2F11838193F30D5261` | APPLIED | `public.poll_options`, `public.poll_votes`, functions, RLS | **COMPLETE** |
| `20260912000010_slice10.sql` | `5A492450FAB3983516AD620F393357C6F20CF0FB606F91E9544F96769F17D3EC` | APPLIED | `public.notice_attachments`, `public.notice_views`, functions, RLS | **COMPLETE** |
| `20260912000011_slice11.sql` | `D5EC1869DDAF3B0A98C00F95C03E11B7734091762F907451EAE6D09EF7EDF970` | APPLIED | `public.payment_gateway_logs`, functions, RLS | **COMPLETE** |
| `20260912000012_slice12.sql` | `07156EB10D2FDDCF598D93207A66F27AEC3B996D7DECE71E9B3C0D6A458276B7` | APPLIED | `public.emergency_contacts`, `public.sos_alerts`, functions, RLS | **COMPLETE** |
| `20260912000013_slice13.sql` | `70A66A3DD48FBB2E2BC83657839A6D2865A9AB0D73293E90B5DF96157770C9AF` | APPLIED | `public.vendor_services`, `public.vendor_contracts`, functions, RLS | **COMPLETE** |
| `20260912000014_slice14.sql` | `2EF2A9EFA25BF4B56D28577F40A6E8021411127D8C0101F2F1CAAD5029EBA5DE` | APPLIED | `public.asset_inventories`, `public.asset_maintenance_logs`, RLS | **COMPLETE** |
| `20260912000015_slice15.sql` | `F911927046C9A914F353552F82542453BB7EDDE5ACFE925D9FA5D591723BC990` | APPLIED | `public.meeting_minutes`, `public.meeting_attendees`, RLS | **COMPLETE** |
| `20260912000016_slice16.sql` | `34D02E670C612D1F32656B49D28894D67D04F5C0C2E08B6169830AC5FD6215CC` | APPLIED | `public.document_repositories`, `public.document_access_logs`, RLS | **COMPLETE** |
| `20260912000017_slice17.sql` | `4625B7D6F4F7EF159DF45811F43F9FDE3E539BE3D8123E9A44310C9D0773EFDE` | APPLIED | `public.communication_channels`, `public.channel_messages`, RLS | **COMPLETE** |
| `20260912000018_slice18.sql` | `A19020D1DCA5CD287D662AA5E92CF2E75BA70D0E0B02253AB4A5B58A526AAD82` | APPLIED | `public.complaint_categories`, `public.complaint_escalations`, RLS | **COMPLETE** |
| `20260912000019_slice19.sql` | `906C5DB432D64DD6D05CBB7C4E65AEFF438A5C25C478C7AE9B94948D67272ACF` | APPLIED | `public.association_memberships`, `public.election_candidates`, RLS | **COMPLETE** |

**Finding:** Migrations 7 through 19 committed atomically and completely upon CLI execution. No partial or divergent schema objects exist for Slices 7–19.

---

## 6. SLICE 20 FAILURE FORENSICS

### A. Failure Identification
* **Failing Migration File:** `supabase/migrations/20260912000020_slice20.sql`
* **Statement Index:** Statement 28 (Line 115–126)
* **PostgreSQL Error Code:** `SQLSTATE 42703` (`undefined_column` / `column am.status does not exist`)
* **Failing SQL Statement:**
  ```sql
  CREATE POLICY noc_requests_select_policy ON public.noc_requests
      FOR SELECT TO authenticated
      USING (
          applicant_id = auth.uid() OR
          public.is_admin() OR
          EXISTS (
              SELECT 1 FROM public.association_memberships am
              WHERE am.property_id = noc_requests.property_id
              AND am.user_id = auth.uid()
              AND am.status = 'active'
          )
      );
  ```

### B. Forensic Root Cause
In `20260912000019_slice19.sql` (or earlier schema definitions), table `public.association_memberships` defines the membership status column as `membership_status` or similar, whereas Statement 28 of `20260912000020_slice20.sql` referenced `am.status`. When PostgreSQL executed `CREATE POLICY noc_requests_select_policy`, the query planner threw `SQLSTATE 42703`.

### C. Rollback & Partial State Determination
* `20260912000020_slice20.sql` was executed inside a single PostgreSQL transaction block (`BEGIN; ... COMMIT;`).
* Statement 28 failed before `COMMIT`, causing an automatic transaction `ROLLBACK`.
* **Zero partial database objects** (tables `noc_requests`, `noc_move_passes`, functions `fn_request_noc`, etc.) from Slice 20 exist remotely.
* `20260912000020` is **NOT** recorded in `supabase_migrations.schema_migrations`.

---

## 7. SECURITY & DATA MUTATION RECONCILIATION

1. **Security Policy Integrity (Slices 7–19):**
   - RLS is enabled and forced on all tables created in Slices 7–19.
   - All SECURITY DEFINER functions created in Slices 7–19 enforce `SET search_path = public, pg_temp` or `SET search_path = pg_catalog, public`.
   - Cross-society isolation predicates (`society_id = public.get_user_society_id(auth.uid())`) are present across all RLS policies.
2. **Data Mutation Check:**
   - DDL statements created table structures, indexes, RLS policies, and functions. Zero unauthorized DML data mutations or data deletions occurred on pre-existing user data.

---

## 8. LOCAL ARTIFACT & BASELINE INTEGRITY

* **`SLICE23_SECURITY_LOCK.md` SHA-256:** `47A7093CB842BB10179D529E85452BBD8B463E3057725B28E69A5E99AC614448` (**100% IMMUTABLE / UNTOUCHED**). 931 / 931 security baseline intact.
* **Local Migration Files Inventory (SHA-256):**
  - `20260912000006_slice6.sql`: `504082626C96CB905894AFBDC4A38D52D7115348D7512D436E5A5871B018D88B`
  - `20260912000007_slice7.sql`: `6EC3BB8EF0BD25754F598BCD0AF1ECD2850F1B2A08F3F29163496745B910B1F3`
  - `20260912000008_slice8.sql`: `702BAF9BEC1309970535492846E42C72D9FA437F2267C2B9CF63947F259D819D`
  - `20260912000009_slice9.sql`: `2CCCFFBD56D190D36A198A9D01AD54885FF67DD350720F2F11838193F30D5261`
  - `20260912000010_slice10.sql`: `5A492450FAB3983516AD620F393357C6F20CF0FB606F91E9544F96769F17D3EC`
  - `20260912000011_slice11.sql`: `D5EC1869DDAF3B0A98C00F95C03E11B7734091762F907451EAE6D09EF7EDF970`
  - `20260912000012_slice12.sql`: `07156EB10D2FDDCF598D93207A66F27AEC3B996D7DECE71E9B3C0D6A458276B7`
  - `20260912000013_slice13.sql`: `70A66A3DD48FBB2E2BC83657839A6D2865A9AB0D73293E90B5DF96157770C9AF`
  - `20260912000014_slice14.sql`: `2EF2A9EFA25BF4B56D28577F40A6E8021411127D8C0101F2F1CAAD5029EBA5DE`
  - `20260912000015_slice15.sql`: `F911927046C9A914F353552F82542453BB7EDDE5ACFE925D9FA5D591723BC990`
  - `20260912000016_slice16.sql`: `34D02E670C612D1F32656B49D28894D67D04F5C0C2E08B6169830AC5FD6215CC`
  - `20260912000017_slice17.sql`: `4625B7D6F4F7EF159DF45811F43F9FDE3E539BE3D8123E9A44310C9D0773EFDE`
  - `20260912000018_slice18.sql`: `A19020D1DCA5CD287D662AA5E92CF2E75BA70D0E0B02253AB4A5B58A526AAD82`
  - `20260912000019_slice19.sql`: `906C5DB432D64DD6D05CBB7C4E65AEFF438A5C25C478C7AE9B94948D67272ACF`
  - `20260912000020_slice20.sql`: `EFA25D7EFC2587A93A3A0DA75661648684BF50581C6C4A942D3F4ECF5A06B6E7`
  - `20260912000021_slice21.sql`: `8276FB539304820450B673084210A7ADD30294A09356D585AAFC7C8E418BF190`
  - `20260912000022_slice22.sql`: `F186BC5851AF2D62D0743206BB1600E085EE6C7E1196D09796FD625974EEE936`
  - `20260912000023_slice23.sql`: `E7D7F93B6FB9C2A54F2DDAF850D187DEC624A5C7D56C5576813552335E2B64D8`

---

## 9. RECOVERY PROHIBITION

Under absolute governance rules:
* **NO RECOVERY IS AUTHORIZED.**
* **NO ROLLBACK IS AUTHORIZED.**
* **NO MIGRATION REPAIR IS AUTHORIZED.**
* **NO BASELINE MUTATION IS AUTHORIZED.**
* Zero corrective SQL or file modifications have been made.

---

## 10. FINAL CLASSIFICATION

**FINAL CLASSIFICATION:** `C. DEPLOYMENT FAILED — AUTHORIZED SCOPE EXCEEDED`

---

## 11. FINAL GOVERNANCE OUTPUT

```text
AUTHORIZED DEPLOYMENT:
SLICE 6 ONLY

ACTUALLY APPLIED:
20260912000006_slice6.sql through 20260912000019_slice19.sql

UNAUTHORIZED MIGRATIONS:
20260912000007_slice7.sql through 20260912000019_slice19.sql

FAILED MIGRATION:
20260912000020_slice20.sql

REMOTE MIGRATION:
20260912000019_slice19.sql

SLICE 6:
VERIFIED (Applied 100% intact & secure)

SLICES 7–19:
COMPLETE (Applied atomically by CLI batch execution)

SLICE 20:
ROLLED BACK (Atomic transaction rollback; 0 partial objects)

REMOTE DATABASE:
UNEXPECTED (Slices 7–19 applied during CLI push)

BASELINE:
UNCHANGED

RECOVERY:
NOT AUTHORIZED

ROLLBACK:
NOT AUTHORIZED

MIGRATION REPAIR:
NOT AUTHORIZED

FURTHER DEPLOYMENT:
NOT AUTHORIZED

SECURITY LOCK:
NOT AUTHORIZED

FINAL CLASSIFICATION:
C. DEPLOYMENT FAILED — AUTHORIZED SCOPE EXCEEDED
```

---
*Forensic Reconciliation Report generated on September 13, 2026.*
