# SU SOCIETY APP — HUMAN OPERATOR LIVE PRODUCTION PREFLIGHT CHECKLIST

**Target Repository:** `D:\Clients Applications\SU Society App`  
**Execution Timestamp:** 2026-09-12T09:40:00+05:30  
**Authoritative Baseline:** 931 / 931 PASS (100% Locked & Immutable)  
**Authoritative Storage Bucket:** `society-vault-private`  
**Current Baseline Status:** `CODEBASE READY — PRODUCTION ENVIRONMENT NOT VERIFIED`  
**Execution Mode:** STRICT READ-ONLY DOCUMENTATION CORRECTION ONLY  

---

> [!CAUTION]
> THIS ARTIFACT IS A READ-ONLY OPERATOR CHECKLIST. IT DOES NOT PROVISION, MODIFY, OR DEPLOY ANY RESOURCE. ALL QUERIES SUPPLIED HEREIN ARE STRICTLY READ-ONLY (`SELECT` ONLY). MISSING CLOUD RESOURCES MUST BE REPORTED AS: **"REQUIRES SEPARATE HUMAN-AUTHORIZED DEPLOYMENT ACTION."**

---

## SECTION 1 — SUPABASE PROJECT IDENTITY VERIFICATION

The human operator must verify target project identity before running any preflight queries. **Do NOT paste secret credentials into chat or logs.**

### 1.1 Dashboard Verification
1. Log into the [Supabase Cloud Console](https://supabase.com/dashboard).
2. Select the target production project for the SU Society App.
3. Navigate to **Project Settings** $\rightarrow$ **General**.
4. Confirm and record the following public parameters:
   * **Project Name:** `[ RECORD PRODUCTION PROJECT NAME ]`
   * **Project Reference ID:** `[ RECORD 20-CHARACTER REF ID, e.g. abcdefghijklmnopqrst ]`
   * **Project Region:** `[ RECORD AWS REGION, e.g. ap-south-1 ]`

### 1.2 API Endpoint & Database Host Verification
1. Navigate to **Project Settings** $\rightarrow$ **API**.
2. Confirm the Project URL pattern matches: `https://<PROJECT_REF_ID>.supabase.co`.
3. Navigate to **Project Settings** $\rightarrow$ **Database**.
4. Confirm Host pattern: `db.<PROJECT_REF_ID>.supabase.co`.

* **Match Rule:** If the Project Ref ID in your connection string does NOT match the production project ref ID recorded above, **STOP IMMEDIATELY**.

---

## SECTION 2 — AUTHORITATIVE REPOSITORY-DERIVED DATABASE STATE AUDIT

The human operator must execute the following **READ-ONLY** SQL query suite to reconcile live database metadata against the EXACT, authoritative Slice 1–23 repository inventory.

### 2.1 Authoritative Repository Object Inventory (Slices 1–23)

| Object Category | Exact Required Count | Authoritative Repository Objects |
| :--- | :--- | :--- |
| **Domain Tables** | **34 Tables** | `societies`, `users`, `properties`, `units`, `property_owners`, `tenancies`, `user_roles`, `maintenance_policies`, `custom_billing_subjects`, `custom_billing_responsibilities`, `maintenance_charges`, `ledger_transactions`, `opening_balances`, `payments`, `payment_allocations`, `receipts`, `notifications`, `utility_readings`, `billing_invoices`, `tickets`, `ticket_comments`, `domestic_staff`, `staff_passes`, `visitor_passes`, `gate_logs`, `noc_requests`, `fine_ledger`, `rule_violations`, `disputes`, `vault_documents`, `vault_document_versions`, `vault_access_grants`, `vault_audit_logs`, `vault_rate_limits` |
| **Core RPC Routines** | **14 Routines** | `verify_payment`, `reject_payment`, `reverse_payment`, `_internal_settle_payment`, `fn_initiate_document_upload`, `fn_finalize_document_upload`, `fn_add_document_version`, `fn_grant_document_access`, `fn_revoke_document_access`, `fn_generate_document_download_url`, `fn_archive_vault_document`, `fn_delete_vault_document`, `validate_vault_object_payload_internal`, `fn_resolve_document_access` |
| **Financial & Vault Triggers** | **8 Triggers** | `trigger_validate_ledger_direction_invariants`, `trigger_prevent_ledger_mutations`, `trigger_prevent_opening_balance_mutations`, `trigger_book_opening_balance_in_ledger`, `trigger_validate_payment_state_transitions`, `trigger_prevent_payment_deletes`, `trigger_prevent_receipt_mutations`, `trigger_prevent_verified_allocation_mutations` |
| **Storage Metadata** | **1 Bucket / 4 Policies** | Bucket `society-vault-private`; Policies `pol_storage_vault_select`, `pol_storage_vault_insert`, `pol_storage_vault_update`, `pol_storage_vault_delete` |

---

### 2.2 Object-Classification Categories

When evaluating live database objects, distinguish:
* **A. EXPECTED APPLICATION OBJECT:** Belongs to the 34 domain tables, 14 RPC routines, 8 triggers, or `society-vault-private` bucket/policies listed above.
* **B. NON-APPLICATION / PLATFORM OBJECT:** Internal PostgreSQL or Supabase platform schemas (`auth`, `storage`, `realtime`, `graphql`, `vault`, `extensions`, `supabase_migrations`). These are ignored during application reconciliation.
* **C. UNEXPECTED APPLICATION OBJECT:** An alien table or routine created in the `public` schema that does NOT belong to the authoritative Slice 1–23 inventory.
* **D. CONFLICTING APPLICATION OBJECT:** An object with an identical name to an application object but possessing conflicting column types, constraints, or signature parameters.

---

### 2.3 Read-Only SQL Inspection Suite

#### Query 2.3.1: Engine & Connection Identity Inspection (READ-ONLY)
```sql
-- READ-ONLY: Inspect PostgreSQL version, current database name, and connected host
SELECT 
    current_database() AS database_name,
    current_user AS connected_user,
    inet_server_addr() AS server_ip,
    version() AS postgresql_version;
```

#### Query 2.3.2: Migration History Inspection (READ-ONLY)
```sql
-- READ-ONLY: Inspect Supabase migration history table if present
SELECT 
    version,
    inserted_at
FROM supabase_migrations.schema_migrations
ORDER BY version ASC;
```
* **Migration History Note:** If `supabase_migrations.schema_migrations` does NOT exist, report:  
  **"MIGRATION HISTORY NOT AVAILABLE — OBJECT-LEVEL RECONCILIATION REQUIRED."** *(Do NOT create a migration table).*

#### Query 2.3.3: Exact Object Matching Reconciliation Query (READ-ONLY)
```sql
-- READ-ONLY: Exact identity matching of domain tables, RPC routines, and triggers
WITH domain_tables AS (
    SELECT count(DISTINCT table_name) AS table_count
    FROM information_schema.tables 
    WHERE table_schema = 'public' 
      AND table_name IN (
        'societies', 'users', 'properties', 'units', 'property_owners', 'tenancies',
        'user_roles', 'maintenance_policies', 'custom_billing_subjects', 'custom_billing_responsibilities',
        'maintenance_charges', 'ledger_transactions', 'opening_balances', 'payments', 'payment_allocations',
        'receipts', 'notifications', 'utility_readings', 'billing_invoices', 'tickets',
        'ticket_comments', 'domestic_staff', 'staff_passes', 'visitor_passes', 'gate_logs',
        'noc_requests', 'fine_ledger', 'rule_violations', 'disputes', 'vault_documents',
        'vault_document_versions', 'vault_access_grants', 'vault_audit_logs', 'vault_rate_limits'
      )
),
rpc_routines AS (
    SELECT count(DISTINCT routine_name) AS rpc_count
    FROM information_schema.routines
    WHERE routine_schema = 'public'
      AND routine_name IN (
        'verify_payment', 'reject_payment', 'reverse_payment', '_internal_settle_payment',
        'fn_initiate_document_upload', 'fn_finalize_document_upload', 'fn_add_document_version',
        'fn_grant_document_access', 'fn_revoke_document_access', 'fn_generate_document_download_url',
        'fn_archive_vault_document', 'fn_delete_vault_document', 'validate_vault_object_payload_internal',
        'fn_resolve_document_access'
      )
),
database_triggers AS (
    SELECT count(DISTINCT trigger_name) AS trigger_count
    FROM information_schema.triggers
    WHERE event_object_schema = 'public'
      AND trigger_name IN (
        'trigger_validate_ledger_direction_invariants', 'trigger_prevent_ledger_mutations',
        'trigger_prevent_opening_balance_mutations', 'trigger_book_opening_balance_in_ledger',
        'trigger_validate_payment_state_transitions', 'trigger_prevent_payment_deletes',
        'trigger_prevent_receipt_mutations', 'trigger_prevent_verified_allocation_mutations'
      )
),
unexpected_public_tables AS (
    SELECT count(*) AS alien_count
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_type = 'BASE TABLE'
      AND table_name NOT IN (
        'societies', 'users', 'properties', 'units', 'property_owners', 'tenancies',
        'user_roles', 'maintenance_policies', 'custom_billing_subjects', 'custom_billing_responsibilities',
        'maintenance_charges', 'ledger_transactions', 'opening_balances', 'payments', 'payment_allocations',
        'receipts', 'notifications', 'utility_readings', 'billing_invoices', 'tickets',
        'ticket_comments', 'domestic_staff', 'staff_passes', 'visitor_passes', 'gate_logs',
        'noc_requests', 'fine_ledger', 'rule_violations', 'disputes', 'vault_documents',
        'vault_document_versions', 'vault_access_grants', 'vault_audit_logs', 'vault_rate_limits',
        '_slice23_test_results', 'schema_migrations'
      )
)
SELECT 
    t.table_count AS found_tables_out_of_34,
    r.rpc_count AS found_rpcs_out_of_14,
    g.trigger_count AS found_triggers_out_of_8,
    u.alien_count AS unexpected_public_tables,
    CASE 
        WHEN u.alien_count > 0 THEN 'UNKNOWN / INCONSISTENT'
        WHEN t.table_count = 0 AND r.rpc_count = 0 AND g.trigger_count = 0 THEN 'EMPTY'
        WHEN t.table_count = 34 AND r.rpc_count = 14 AND g.trigger_count = 8 THEN 'INITIALIZED'
        WHEN t.table_count > 0 OR r.rpc_count > 0 OR g.trigger_count > 0 THEN 'PARTIAL'
        ELSE 'UNKNOWN / INCONSISTENT'
    END AS database_state_classification
FROM domain_tables t, rpc_routines r, database_triggers g, unexpected_public_tables u;
```

---

### 2.4 EXACT DATABASE CLASSIFICATION RULES

Based strictly on exact object matching from Query 2.3.3:

* **A. `EMPTY`**:  
  `found_tables = 0` AND `found_rpcs = 0` AND `found_triggers = 0` AND `unexpected_public_tables = 0`.  
  *(No application objects exist; clean initial migration deployment permitted upon explicit human authorization).*
* **B. `PARTIAL`**:  
  At least one application object exists (`found_tables > 0` OR `found_rpcs > 0`), BUT one or more required objects are missing (`found_tables < 34` OR `found_rpcs < 14` OR `found_triggers < 8`).  
  *(Action: Report **"PARTIAL DATABASE STATE DETECTED — REQUIRES HUMAN RECONCILIATION."**).*
* **C. `INITIALIZED`**:  
  `found_tables = 34` AND `found_rpcs = 14` AND `found_triggers = 8` AND `unexpected_public_tables = 0`.  
  *(ALL authoritative application objects are present and zero conflicting/unexpected public tables exist).*
* **D. `UNKNOWN / INCONSISTENT`**:  
  `unexpected_public_tables > 0` OR object identity/definitions conflict with the authoritative repository state.  
  *(**PREFLIGHT BLOCKED — DEPLOYMENT HALTED.** An `UNKNOWN / INCONSISTENT` state MUST BLOCK deployment).*

---

## SECTION 3 — STORAGE BUCKET READ-ONLY VERIFICATION

Authoritative Bucket Target: **`society-vault-private`**

### 3.1 SQL Bucket Existence Check
```sql
-- READ-ONLY: Inspect storage.buckets for society-vault-private
SELECT 
    id AS bucket_id,
    name AS bucket_name,
    public AS is_public,
    created_at
FROM storage.buckets
WHERE id = 'society-vault-private';
```

### 3.2 SQL Storage Policy Inspection
```sql
-- READ-ONLY: Verify RLS policies on storage.objects for society-vault-private
SELECT 
    policyname,
    cmd AS permission_type,
    roles
FROM pg_policies
WHERE schemaname = 'storage' AND tablename = 'objects';
```

### 3.3 Classification Outcomes:
* **If Bucket Exists & `public = false`:** Mark `society-vault-private` as **VERIFIED**.
* **If Bucket Is Absent:** Report: **"REQUIRES SEPARATE HUMAN-AUTHORIZED DEPLOYMENT ACTION."**
* **If Conflicting Bucket (`vault-documents`) Exists:** Report: **"CONFLICTING BUCKET PRESENT — REMEDIATION REQUIRED."**

---

## SECTION 4 — EDGE FUNCTIONS READ-ONLY VERIFICATION

Required Deno Edge Functions:
1. `generate_storage_signed_url`
2. `validate_vault_object_payload`

### 4.1 Read-Only Supabase CLI Status Command
Run in your local terminal (does NOT deploy or mutate):
```bash
# READ-ONLY STATUS CHECK — DOES NOT DEPLOY
supabase functions list
```

### 4.2 Dashboard Status Inspection
1. Open Supabase Dashboard $\rightarrow$ **Edge Functions**.
2. Verify if `generate_storage_signed_url` and `validate_vault_object_payload` are listed.

### 4.3 Classification Outcomes:
* **If Both Functions Listed & ACTIVE:** Mark Edge Functions as **VERIFIED**.
* **If Either Function Absent:** Report: **"REQUIRES SEPARATE HUMAN-AUTHORIZED DEPLOYMENT ACTION."**

---

## SECTION 5 — SECRETS & TRUST BOUNDARY VERIFICATION

Required Secret Names:
* `SUPABASE_SERVICE_ROLE_KEY`
* `EDGE_FUNCTION_HMAC_SECRET`

> [!SECURITY BLOCKER]
> NEVER PRINT OR DISPLAY ACTUAL SECRET VALUES. VERIFY EXISTENCE ONLY.

### 5.1 Read-Only Secrets Check via Supabase CLI
```bash
# READ-ONLY SECRETS LIST — PRINTS NAMES ONLY, NEVER VALUES
supabase secrets list
```

### 5.2 Dashboard Secrets Inspection
1. Navigate to **Project Settings** $\rightarrow$ **Edge Functions** (or Secrets Manager).
2. Confirm `EDGE_FUNCTION_HMAC_SECRET` is present in the secret keys list.

### 5.3 Classification Outcomes:
* **If Secret Names Confirmed Bound:** Mark Secret Names as **VERIFIED**.
* **If Secret Binding Cannot Be Proven:** Classify: **RUNTIME SECRET BINDING NOT VERIFIED.**

---

## SECTION 6 — VERCEL FRONTEND HOSTING READ-ONLY VERIFICATION

### 6.1 Vercel Dashboard Inspection
1. Log into [Vercel Dashboard](https://vercel.com/dashboard).
2. Select the production project associated with the SU Society App repository.
3. Confirm the following configuration settings:
   * **Framework Preset:** `Vite`
   * **Build Command:** `npm run build`
   * **Output Directory:** `dist`
   * **Production Branch:** `main` (or designated deployment tag)

### 6.2 Client Environment Variable Audit
1. Navigate to **Project Settings** $\rightarrow$ **Environment Variables**.
2. Confirm presence of PUBLIC client variables:
   * `VITE_SUPABASE_URL` (Public HTTPS Endpoint)
   * `VITE_SUPABASE_ANON_KEY` (Public Client Anon Key)
3. **Security Audit Check:** Confirm `SUPABASE_SERVICE_ROLE_KEY` is **ABSENT** from Vercel environment variables.

---

## SECTION 7 — BACKUP & PITR RECOVERY VERIFICATION

### 7.1 Point-In-Time Recovery (PITR) Inspection
1. Open Supabase Dashboard $\rightarrow$ **Project Settings** $\rightarrow$ **Database**.
2. Scroll to **Database Backups** / **Point-in-Time Recovery**.
3. Verify PITR Status:
   * **PITR Status:** `[ RECORD ACTIVE / INACTIVE ]`
   * **Retention Period:** `[ RECORD RETENTION DAYS, e.g. 7 days / 30 days ]`

### 7.2 Restore Capability Classification:
* **PITR Enabled:** Classify as **PITR ENABLED**.
* **Daily Backups Visible:** Classify as **DAILY BACKUP AVAILABLE**.
* **Restore Test Status:** Classify as **RESTORE TEST NOT VERIFIED** (unless an actual test restoration has been executed on a staging database).

---

## SECTION 8 — HUMAN STOP GATE CHECKPOINT

Before ANY production deployment or database mutation is authorized, the human operator MUST review and check off all 15 preflight items:

* [ ] **1. Supabase Project Ref ID Confirmed:** Matches production project ID.
* [ ] **2. Database Connection Host Confirmed:** Host string matches target DB.
* [ ] **3. Environment Confirmed:** Environment is explicitly PRODUCTION.
* [ ] **4. Repository Revision SHA Confirmed:** Git commit matches approved release.
* [ ] **5. Baseline Intact:** 931 / 931 PASS security assertions verified.
* [ ] **6. Database State Classified via Exact Match:** Classified as `EMPTY` or `INITIALIZED` (All 34 tables, 14 RPCs, 8 triggers matched; zero unexpected tables).
* [ ] **7. PostgreSQL Version Compatibility Known:** DB engine version recorded.
* [ ] **8. Extension Availability Known:** `pgcrypto` & `uuid-ossp` availability recorded.
* [ ] **9. Bucket `society-vault-private` Verified:** Private storage bucket state recorded.
* [ ] **10. Edge Functions Verified:** Status of Deno edge functions recorded.
* [ ] **11. Secret Bindings Verified:** Secret names verified without exposing values.
* [ ] **12. Vercel Project Association Verified:** Repo and build settings recorded.
* [ ] **13. PITR / Backup Status Recorded:** Backup retention documented.
* [ ] **14. Rollback / Recovery Plan Understood:** Operator understands recovery steps.
* [ ] **15. Zero Unexpected Application Tables:** `unexpected_public_tables = 0`.

```
   ┌─────────────────────────────────────────────────────────────┐
   │                    STOP — HUMAN REVIEW REQUIRED             │
   │                                                             │
   │   EXPLICIT HUMAN AUTHORIZATION IS REQUIRED BEFORE PROCEEDING  │
   │   WITH ANY PRODUCTION DATABASE MIGRATION OR DEPLOYMENT.     │
   └─────────────────────────────────────────────────────────────┘
```

---

## SECTION 9 — FINAL CLASSIFICATION & REPORTING RULES

After completing the read-only queries in Sections 1–7 and the checklist in Section 8:

1. **If Database State is `EMPTY` or `INITIALIZED` AND ALL 15 Stop Gate items are checked:**
   Select: **`PREFLIGHT PASS — READY FOR HUMAN DEPLOYMENT AUTHORIZATION`**  
   *(Note: This verdict authorizes preflight completion, NOT automated deployment).*

2. **If Database State is `UNKNOWN / INCONSISTENT` OR ANY preflight item is missing:**
   Select: **`PREFLIGHT BLOCKED — DO NOT DEPLOY`**  
   For each missing or absent resource, report:  
   **"REQUIRES SEPARATE HUMAN-AUTHORIZED DEPLOYMENT ACTION."**

---
**END OF OPERATOR CHECKLIST — ZERO MUTATIONS PERFORMED**
