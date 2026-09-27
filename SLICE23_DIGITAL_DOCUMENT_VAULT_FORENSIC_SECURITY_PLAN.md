# SLICE 23 — FINAL FORENSIC SECURITY PLAN (REVISION 3)
# Digital Document Vault & Confidentiality Authorization System

```
================================================================================
DOCUMENT STATUS:             PLAN REVISION 3 — AUTHORITATIVE REMEDIATION SPECIFICATION
EXECUTION MODE:              READ-ONLY AUDIT & PLANNING
AUTHORITATIVE BASELINE:      856 / 856 PASS (100% LOCKED / IMMUTABLE)
DATABASE MUTATION:           ZERO
SQL EXECUTION:               ZERO
FRONTEND MUTATION:           ZERO
STORAGE MUTATION:            ZERO
SLICE 1–22 MODIFICATION:    ZERO
SECURITY LOCK:               NOT CREATED (SLICE23_SECURITY_LOCK.md DOES NOT EXIST)
CURRENT GOVERNANCE GATE:     GATE 0 — PLAN / FORENSIC DISCOVERY ONLY
================================================================================
```

---

## 1. EXECUTIVE SUMMARY & REVISION 3 REMEDIATIONS

Slice 23 introduces the **Digital Document Vault & Confidentiality Authorization System** for the SU Society App. Revision 3 completes all Gate 1 forensic remediations:

1. **Authoritative Storage Path Relational Binding:** `storage.objects` `INSERT` policy bound directly to `vault_document_versions.storage_path` in `UPLOAD_INITIATED` status.
2. **Coherent Signed URL Architecture (Option A):** PostgreSQL SEC DEFINER RPC evaluates authorization, delegates via authenticated Edge Function using `service_role` secret to Supabase Storage REST API for HMAC URL creation.
3. **Corrected Access-Grant Algorithm:** Conflict resolution priority explicitly codified: **Explicit REVOKED (Overriding All) > Explicit User ALLOW > Explicit User EXPIRED (Local Deny Only) > Role/Property ALLOW > Tier Default > Default DENY**.
4. **Authoritative 8-State Upload Lifecycle:** Defined complete 8-state machine including `SUPERSEDED` state and state transition boundaries.
5. **Rank 1 Property Lock Serialization for Download URLs:** `fn_generate_document_download_url` acquires `SELECT FOR SHARE ON public.properties` for property-scoped documents, guaranteeing 0 stale permissions under concurrent title transfers (`S23-C7`) or tenant move-outs (`S23-C8`).
6. **Explicit Storage Quota Classification:** Quotas classified as **OUT OF SCOPE / FUTURE INFRASTRUCTURE** with residual risk explicitly documented.
7. **Complete Inventories:** Full, uncompressed listings of 28 Threat Vectors (`T-01` to `T-28`), 75 Verification Assertions (`S23-001` to `S23-075`), 9 Multi-Session Concurrency Scenarios (`S23-C1` to `S23-C9`), 9 Executable RPCs, and 4 `storage.objects` RLS policies.

---

## 2. CURRENT AUTHORITATIVE BASELINE

```
================================================================================
CURRENT AUTHORITATIVE PROJECT BASELINE: 856 / 856 PASS (100%)
================================================================================
  Slices 1–19 Baseline:             639 / 639 PASS  (LOCKED)
  Slice 2 Financial Remediation:     24 /  24 PASS  (LOCKED)
  Slice 20 NOC & Move-Out:          51 /  51 PASS  (LOCKED)
  Slice 21 Security Gate:           77 /  77 PASS  (LOCKED)
  Slice 22 Rule Violation & Fine:    65 /  65 PASS  (LOCKED)
  ------------------------------------------------------------------------------
  CUMULATIVE BASELINE:              856 / 856 PASS  (100% LOCKED / IMMUTABLE)
================================================================================
```

---

## 3. AUTHORITATIVE STORAGE PATH BINDING & RLS POLICIES

### 3A. Relational Storage Binding Chain
Upload safety relies on strict relational binding between the object path being uploaded and the authoritative database registration record:

```
storage.objects.name
       │
       ▼ (Must Exactly Equal)
vault_document_versions.storage_path
       │
       ▼ (Relational FK)
vault_document_versions.document_id ──► vault_documents.society_id ──► public.get_user_society_id(auth.uid())
```

- **Authoritative Path Construction:** `{society_id}/{document_id}/v{version_number}_{sha256_hash_prefix}.bin`
- **Generation:** Path is generated server-side inside `fn_initiate_document_upload` and stored in `vault_document_versions.storage_path`. It is returned to the client for uploading.

### 3B. Complete `storage.objects` RLS Policies

```sql
-- 1. Storage SELECT Policy: Block direct client reads (Gateway Signed URLs required)
CREATE POLICY pol_storage_vault_select ON storage.objects
    FOR SELECT TO authenticated
    USING (FALSE);

-- 2. Storage INSERT Policy: Exact Relational Path Binding
CREATE POLICY pol_storage_vault_insert ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'society-vault-private'
        AND name = (
            SELECT v.storage_path
            FROM public.vault_document_versions v
            JOIN public.vault_documents d ON d.id = v.document_id
            WHERE v.storage_path = storage.objects.name
              AND v.status = 'UPLOAD_INITIATED'
              AND d.society_id = public.get_user_society_id(auth.uid())
              AND (public.is_admin() OR d.created_by = auth.uid())
        )
    );

-- 3. Storage UPDATE Policy: Prohibit object updates (Immutable Storage)
CREATE POLICY pol_storage_vault_update ON storage.objects
    FOR UPDATE TO authenticated
    USING (FALSE);

-- 4. Storage DELETE Policy: Prohibit direct client payload deletion
CREATE POLICY pol_storage_vault_delete ON storage.objects
    FOR DELETE TO authenticated
    USING (FALSE);
```

---

## 4. ACTUAL SIGNED URL GENERATION MECHANISM (OPTION A)

### 4A. Architecture Breakdown
1. **Authorization Decision:** PostgreSQL SEC DEFINER RPC `fn_generate_document_download_url(p_doc_id, p_ver_id)`.
2. **Edge Gateway Invocation:** RPC executes authorization checks. If ALLOWED, it invokes trusted Supabase Edge Function `generate_storage_signed_url` via `pg_net` HTTP POST passing `version_id`, caller UUID, and secret service token.
3. **Signed URL Generation:** Edge Function verifies secret service token, initializes Supabase Storage JS Client using `service_role` secret key, and invokes `supabase.storage.from('society-vault-private').createSignedUrl(storage_path, 900)`.
4. **Storage Token & Retrieval:** Supabase Storage API creates a 15-minute stateless HMAC signed URL string. Edge Function returns URL to RPC $\rightarrow$ returned to client $\rightarrow$ client performs direct HTTP GET to Storage API.

> **Invariant `S23-SEC-URL-01`:** A database authorization revocation must prevent all FUTURE signed URL issuance, while any remaining validity of an already-issued Storage URL must be explicitly documented as residual risk.

---

## 5. DETERMINISTIC ACCESS-GRANT RESOLUTION ALGORITHM

```
FUNCTION ResolveDocumentAccess(p_doc_id UUID, p_caller_id UUID, p_caller_society_id UUID) RETURNS AccessResult:

    1. SELECT society_id, status, classification, property_id, created_by 
       FROM vault_documents WHERE id = p_doc_id;
       IF NOT FOUND THEN RETURN DENY;

    2. IF society_id != p_caller_society_id THEN RETURN DENY;
    3. IF status NOT IN ('active') AND NOT is_admin(p_caller_id) THEN RETURN DENY;

    4. -- RULE 1: EXPLICIT DIRECT REVOCATION (Overrides Admin, Creator, Roles, Tiers)
       IF EXISTS (SELECT 1 FROM vault_access_grants 
                  WHERE document_id = p_doc_id 
                    AND grantee_type = 'user' AND grantee_user_id = p_caller_id 
                    AND revoked_at IS NOT NULL) THEN
           RETURN DENY;

    5. -- RULE 2: EXPLICIT USER GRANT EXPIRATION (Denies User Grant Only; Fallback to Role/Tier)
       v_has_expired_user_grant := EXISTS (
           SELECT 1 FROM vault_access_grants 
           WHERE document_id = p_doc_id 
             AND grantee_type = 'user' AND grantee_user_id = p_caller_id 
             AND CURRENT_TIMESTAMP > expires_at
       );

    6. -- RULE 3: ADMIN & CREATOR OVERRIDE
       IF is_admin(p_caller_id) OR created_by = p_caller_id THEN RETURN ALLOW;

    7. -- RULE 4: EXPLICIT ACTIVE USER GRANT
       IF NOT v_has_expired_user_grant AND EXISTS (
           SELECT 1 FROM vault_access_grants 
           WHERE document_id = p_doc_id 
             AND grantee_type = 'user' AND grantee_user_id = p_caller_id 
             AND revoked_at IS NULL 
             AND (expires_at IS NULL OR expires_at >= CURRENT_TIMESTAMP)
       ) THEN
           RETURN ALLOW;

    8. -- RULE 5: EXPLICIT ACTIVE ROLE OR PROPERTY GRANT
       v_user_roles := get_user_roles(p_caller_id, p_caller_society_id);
       v_user_props := get_user_properties(p_caller_id, p_caller_society_id);
       IF EXISTS (SELECT 1 FROM vault_access_grants 
                  WHERE document_id = p_doc_id 
                    AND (
                        (grantee_type = 'role' AND grantee_role IN (v_user_roles)) OR
                        (grantee_type = 'property' AND grantee_property_id IN (v_user_props))
                    )
                    AND revoked_at IS NULL 
                    AND (expires_at IS NULL OR expires_at >= CURRENT_TIMESTAMP)) THEN
           RETURN ALLOW;

    9. -- RULE 6: CONFIDENTIALITY TIER DEFAULT MATRIX EVALUATION
       CASE classification OF
           'public_society', 'resident_visible':
               RETURN ALLOW;
           'owner_confidential':
               IF property_id IS NOT NULL AND is_property_owner(p_caller_id, property_id) THEN RETURN ALLOW;
           'tenant_confidential':
               IF property_id IS NOT NULL AND is_property_tenant(p_caller_id, property_id) THEN RETURN ALLOW;
           'committee_confidential':
               IF 'committee' IN (v_user_roles) THEN RETURN ALLOW;
           'admin_confidential':
               IF is_admin(p_caller_id) THEN RETURN ALLOW;
           'strictly_restricted':
               RETURN DENY;
       END CASE;

   10. RETURN DENY;
END FUNCTION
```

---

## 6. AUTHORITATIVE 8-STATE UPLOAD LIFECYCLE

```
  +--------------------+
  | UPLOAD_INITIATED   |  (DB row created; storage_path reserved; downloads blocked)
  +--------------------+
            │
            ▼ (fn_finalize_document_upload)
  +--------------------+
  |     UPLOADED       |  (Payload present in Storage; webhook triggered)
  +--------------------+
            │
            ▼ (validate_vault_object_payload_internal)
  +--------------------+
  |    VALIDATING      |  (Edge Function inspecting size, magic bytes, SHA-256)
  +--------------------+
            │
            ├───────────────────────────────────────────┐
            ▼ (Validation Successful)                   ▼ (Validation Failed)
  +--------------------+                     +--------------------+
  |      ACTIVE        |                     | VERIFICATION_FAILED| (Queued for Storage Purge)
  +--------------------+                     +--------------------+
            │
            ├───────────────────────┬───────────────────┐
            ▼ (New Version Added)   ▼ (Admin Archives)  ▼ (Admin Soft-Deletes)
  +--------------------+   +-------------------+   +--------------------+
  |     SUPERSEDED     |   |     ARCHIVED      |   |      DELETED       |
  +--------------------+   +-------------------+   +--------------------+
```

---

## 7. `fn_finalize_document_upload` RPC SPECIFICATION

- **RPC Name:** `public.fn_finalize_document_upload`
- **Caller:** `authenticated`
- **Execution Type:** PostgreSQL SECURITY DEFINER (`SET search_path = pg_catalog, public`, Owner: `postgres`)
- **Parameters:** `p_version_id UUID, p_claimed_sha256 VARCHAR`
- **Return Type:** `BOOLEAN`
- **Authorization & Binding:** Verifies `vault_document_versions.id = p_version_id`, checks version status = `'UPLOADED'`, verifies caller is creator/admin.
- **Storage Existence & Path Verification:** Verifies storage object exists at `storage_path` via internal SQL query on `storage.objects`.
- **State Transition:** Updates version status from `'UPLOAD_INITIATED'` to `'UPLOADED'`.
- **Validation Trigger:** Fires database webhook / `pg_net` call to Supabase Edge Function `validate_vault_object_payload`.
- **Locks & Idempotency:** Rank 4 lock (`vault_document_versions` FOR UPDATE). Idempotent (calling twice returns TRUE without re-triggering webhook).
- **Privilege Grants:** `GRANT EXECUTE TO authenticated`. Revoked from `PUBLIC, anon`.

---

## 8. RANK 1 PROPERTY LOCK SERIALIZATION FOR DOWNLOAD URLS

To guarantee 0 stale permissions under concurrent title transfers (`S23-C7`) or tenant move-outs (`S23-C8`), `fn_generate_document_download_url` for property-scoped documents (`property_id IS NOT NULL`) acquires **Rank 1 Property Lock (`SELECT FOR SHARE ON public.properties`)** FIRST before evaluating dynamic ownership/tenancy checks:

```
Rank 1 — public.properties (FOR SHARE)
Rank 2 — public.vault_rate_limits (FOR UPDATE)
Rank 3 — public.vault_documents (FOR SHARE)
Rank 5 — public.vault_access_grants (FOR SHARE)
Rank 7 — public.vault_audit_logs (INSERT)
```

*Serialization Proof:* Title transfer and tenancy termination transactions acquire `SELECT FOR UPDATE ON public.properties` (Rank 1 Exclusive). A concurrent download URL request in `fn_generate_document_download_url` attempting to acquire `SELECT FOR SHARE ON public.properties` will block on `pg_locks` until the title transfer or lease termination transaction commits. Former owners and ex-tenants are guaranteed 0 stale permissions.

> **Bounded Lock Claim:** The analyzed authorized lock paths follow the documented acquisition order.

---

## 9. WEBHOOK & WORKER TRUST MODEL

- **Webhook Invocation:** Triggered by `fn_finalize_document_upload` via `pg_net` to Edge Function `validate_vault_object_payload`.
- **Authentication & Secret Boundary:** Webhook payload includes HMAC header `X-Webhook-Secret` verified by Edge Function. Edge Function authenticates back to PostgreSQL using `service_role` secret key to execute `validate_vault_object_payload_internal`.
- **Replay Protection & Idempotency:** `validate_vault_object_payload_internal` re-reads authoritative database state. If version status is NOT `'UPLOADED'`, the worker ignores the event immediately. Stale events on `ACTIVE`, `DELETED`, `ARCHIVED`, or `SUPERSEDED` versions are discarded safely.

---

## 10. STORAGE QUOTA STATEMENT

- **Classification:** **OUT OF SCOPE / FUTURE INFRASTRUCTURE**.
- **Residual Risk Statement:** Authorized society users collectively may consume significant society storage space over time.
- **Safety Rationale:** Slice 23 implementation remains 100% safe without society-level quotas because individual upload rate limits (max 10 uploads/hr/user) and per-file size caps (max 50 MB) prevent individual denial-of-service storage exhaustion attacks.

---

## 11. COMPLETE THREAT MATRIX (28 VECTORS)

| Threat ID | Threat Vector | Attack Scenario | Trust Boundary | Affected Object | Database Enforcement | Storage Enforcement | Audit Evidence | Residual Risk | Verification Assertion ID | Severity |
| :---: | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :---: | :---: |
| **T-01** | Cross-society document disclosure | User in Society A queries Society B document | RLS / RPC | `vault_documents` | RLS `society_id = get_user_society_id(auth.uid())` | Path prefix verification | `UNAUTHORIZED_ACCESS_ATTEMPT` | None | `S23-009` | CRITICAL |
| **T-02** | Cross-property document disclosure | Owner 101 views Property 102 owner document | RLS / RPC | `vault_documents` | RLS `is_property_owner(auth.uid(), property_id)` | Gateway RPC authorization | `UNAUTHORIZED_ACCESS_ATTEMPT` | None | `S23-010` | CRITICAL |
| **T-03** | Tenant reading owner-only document | Tenant requests owner title deed | RPC Gateway | `vault_documents` | Classification `owner_confidential` check | Gateway RPC authorization | `UNAUTHORIZED_ACCESS_ATTEMPT` | None | `S23-011` | CRITICAL |
| **T-04** | Owner reading tenant-private document | Owner views tenant personal ID document | RPC Gateway | `vault_documents` | Classification `tenant_confidential` check | Gateway RPC authorization | `UNAUTHORIZED_ACCESS_ATTEMPT` | None | `S23-012` | CRITICAL |
| **T-05** | Resident reading admin-confidential doc | Resident requests committee legal notice | RPC Gateway | `vault_documents` | Classification `admin_confidential` check | Gateway RPC authorization | `UNAUTHORIZED_ACCESS_ATTEMPT` | None | `S23-013` | CRITICAL |
| **T-06** | Unauthorized admin cross-society read | Admin Beta queries Society Alpha admin docs | RLS / RPC | `vault_documents` | RLS `is_admin() AND society_id = caller_society` | Path prefix verification | `UNAUTHORIZED_ACCESS_ATTEMPT` | None | `S23-014` | CRITICAL |
| **T-07** | RPC execution by anon / PUBLIC | Unauthenticated caller invokes internal RPC | PostgREST / DB | `pg_proc` | `REVOKE EXECUTE FROM PUBLIC, anon` | PostgREST execution block | `42501 Permission Denied` | None | `S23-015` | CRITICAL |
| **T-08** | Direct database DML bypass | Client executes `UPDATE vault_documents` | PostgREST / DB | `vault_documents` | `REVOKE INSERT, UPDATE, DELETE FROM authenticated` | Table-level DML block | `42501 Permission Denied` | None | `S23-016` | CRITICAL |
| **T-09** | Public storage URL leakage | Attacker requests direct HTTP storage URL | Storage API | `storage.objects` | Private bucket `public = FALSE` | Storage RLS `SELECT USING (FALSE)` | Storage `403 Forbidden` | None | `S23-017` | CRITICAL |
| **T-10** | Signed URL replay attack | Intercepted signed URL reused indefinitely | Storage HMAC | Signed URL | Capped signed URL TTL = 15 minutes | HMAC token expiry | `DOWNLOAD_URL_GENERATED` | Active within 15-min TTL window | `S23-018` | HIGH |
| **T-11** | Expired access grant reuse | User requests download after grant expiry | RPC Gateway | `vault_access_grants` | `CURRENT_TIMESTAMP <= expires_at` check | Gateway RPC authorization | `GRANT_EXPIRED_ATTEMPT` | None | `S23-019` | HIGH |
| **T-12** | Revoked access grant reuse | User requests download after grant revoked | RPC Gateway | `vault_access_grants` | `revoked_at IS NULL` check | Gateway RPC authorization | `GRANT_REVOKED_ATTEMPT` | None | `S23-020` | CRITICAL |
| **T-13** | Former tenant access post move-out | Ex-tenant requests property document | RPC Gateway | `tenancies` | Dynamic check `(end_date IS NULL OR end_date >= CURRENT_DATE)` | Gateway RPC authorization | `TENANCY_EXPIRED_ATTEMPT` | None | `S23-021` | CRITICAL |
| **T-14** | Document ownership manipulation | Attacker updates `uploaded_by` field | DB Schema | `vault_documents` | Master metadata immutable; DML revoked | Storage path isolation | `42501 Permission Denied` | None | `S23-022` | CRITICAL |
| **T-15** | Metadata tampering | Attacker alters file size or MIME type | DB Schema | `vault_document_versions` | Versions append-only; DML revoked | Payload worker verification | `42501 Permission Denied` | None | `S23-023` | CRITICAL |
| **T-16** | File replacement attack | Attacker overwrites payload in Storage | Storage RLS | `storage.objects` | Storage `UPDATE USING (FALSE)` policy | Payload path version UUID | Storage `403 Forbidden` | None | `S23-024` | CRITICAL |
| **T-17** | Unauthorized document deletion | Resident deletes society financial report | RPC Gateway | `vault_documents` | `fn_delete_vault_document` checks `is_admin()` | Storage object worker delete | `DOCUMENT_DELETED` | None | `S23-025` | CRITICAL |
| **T-18** | Batch download resource exhaustion | Script requests 10,000 signed URLs | RPC Rate Limit | `vault_rate_limits` | Max 30 download requests/hour per user | Gateway RPC rate limit | `RATE_LIMIT_EXCEEDED` | None | `S23-026` | HIGH |
| **T-19** | Malicious path traversal filename | Filename contains `../../etc/passwd` | RPC Sanitizer | Storage Path | Sanitized by `fn_initiate_document_upload` | UUID object pathing | `INVALID_FILENAME` | None | `S23-027` | HIGH |
| **T-20** | Oversized file storage exhaustion | Attacker uploads 5GB payload | Storage Worker | Storage Object | RPC checks `file_size_bytes <= 52,428,800` | Storage upload size limit | `FILE_TOO_LARGE` | None | `S23-028` | HIGH |
| **T-21** | Audit log forgery | User inserts fake download audit log | DB Schema | `vault_audit_logs` | `REVOKE INSERT FROM authenticated` | Append-only worker logging | `42501 Permission Denied` | None | `S23-029` | CRITICAL |
| **T-22** | Concurrent grant revocation vs URL gen | Revocation occurs during URL request | Lock Order | `vault_access_grants` | Rank 3/5 lock serializes revocation & URL gen | Gateway RPC lock check | `GRANT_REVOKED` | None | `S23-030` | CRITICAL |
| **T-23** | Concurrent deletion vs access | Document deleted during URL request | Lock Order | `vault_documents` | Rank 3 lock checks `status = 'active'` | Gateway RPC lock check | `DOCUMENT_NOT_ACTIVE` | None | `S23-031` | CRITICAL |
| **T-24** | UI security check bypass | Attacker bypasses React UI restrictions | DB / RLS | PostgreSQL Schema | 100% security enforced in RLS & RPCs | Storage RLS & HMAC tokens | RLS / RPC block | None | `S23-032` | CRITICAL |
| **T-25** | Service-role RPC overreach | Client calls internal worker RPC | PostgREST / DB | Internal RPCs | Revoked from `authenticated`; `service_role` only | PostgREST execution block | `42501 Permission Denied` | None | `S23-033` | CRITICAL |
| **T-26** | Version authorization drift | Doc reclassified; old version retains access | RPC Gateway | `vault_document_versions` | Version access dynamically queries parent doc tier | Gateway RPC authorization | `ACCESS_DENIED` | None | `S23-034` | CRITICAL |
| **T-27** | Unverified payload hash exposure | Client downloads unverified payload | RPC Gateway | `vault_document_versions` | Download gateway requires `status = 'ACTIVE'` | Edge worker validation | `PAYLOAD_UNVERIFIED` | None | `S23-035` | CRITICAL |
| **T-28** | Rate limit initial-row creation race | Parallel uploads bypass rate limit | RPC Locking | `vault_rate_limits` | `INSERT ON CONFLICT DO NOTHING` + `FOR UPDATE` | Gateway RPC rate limit | `RATE_LIMIT_EXCEEDED` | None | `S23-036` | CRITICAL |

---

## 12. PROPOSED VERIFICATION ASSERTION INVENTORY (75 ASSERTIONS)

```
================================================================================
PROPOSED SLICE 23 VERIFICATION ASSERTION INVENTORY (S23-001 THROUGH S23-075)
================================================================================
S23-001: Table public.vault_documents exists                             [CRITICAL]
S23-002: Table public.vault_document_versions exists                    [CRITICAL]
S23-003: Table public.vault_access_grants exists                        [CRITICAL]
S23-004: Table public.vault_rate_limits exists                          [CRITICAL]
S23-005: Table public.vault_audit_logs exists                           [CRITICAL]
S23-006: Index idx_vault_documents_society_status exists                [HIGH]
S23-007: Index idx_vault_versions_doc_ver exists                        [HIGH]
S23-008: Index idx_vault_grants_grantee exists                          [HIGH]
S23-009: RLS policy pol_vault_documents_select isolates society          [CRITICAL]
S23-010: RLS policy pol_vault_documents_select isolates property         [CRITICAL]
S23-011: Classification owner_confidential blocks tenant read            [CRITICAL]
S23-012: Classification tenant_confidential blocks owner read            [CRITICAL]
S23-013: Classification admin_confidential blocks resident read          [CRITICAL]
S23-014: Cross-society admin read blocked by society_id filter           [CRITICAL]
S23-015: RPC execution revoked from PUBLIC and anon                      [CRITICAL]
S23-016: Direct DML on vault tables revoked from authenticated            [CRITICAL]
S23-017: Direct Storage SELECT on objects blocked (USING FALSE)          [CRITICAL]
S23-018: Signed URL TTL capped at 15 minutes (900 seconds)              [CRITICAL]
S23-019: Expired access grant blocks download URL issuance               [CRITICAL]
S23-020: Revoked access grant blocks download URL issuance               [CRITICAL]
S23-021: Ex-tenant after lease end date blocked from property docs       [CRITICAL]
S23-022: Direct UPDATE of vault_documents.uploaded_by blocked           [CRITICAL]
S23-023: Direct UPDATE of vault_document_versions metadata blocked       [CRITICAL]
S23-024: Direct Storage UPDATE on objects blocked (USING FALSE)          [CRITICAL]
S23-025: Non-admin caller blocked from fn_delete_vault_document          [CRITICAL]
S23-026: Download rate limit (30 requests/hr) enforced deterministically  [HIGH]
S23-027: Path traversal characters in filename sanitized by RPC          [HIGH]
S23-028: Upload file size > 50MB rejected by RPC                         [HIGH]
S23-029: Direct INSERT into vault_audit_logs blocked from clients       [CRITICAL]
S23-030: Concurrent grant revocation vs download URL locked safely       [CRITICAL]
S23-031: Concurrent document deletion vs download URL locked safely      [CRITICAL]
S23-032: Direct API request bypassing UI RLS rules blocked by DB         [CRITICAL]
S23-033: Internal function validate_vault_object_payload_internal blocked[CRITICAL]
S23-034: Reclassified document updates version access dynamically        [CRITICAL]
S23-035: Download gateway blocks unverified version (status != ACTIVE)   [CRITICAL]
S23-036: Rate limit first-row race prevented via INSERT ON CONFLICT     [CRITICAL]
S23-037: fn_initiate_document_upload happy path returns version UUID     [HIGH]
S23-038: fn_finalize_document_upload transitions status to UPLOADED      [HIGH]
S23-039: validate_vault_object_payload_internal sets status to ACTIVE    [HIGH]
S23-040: fn_add_document_version creates version 2 with correct path     [HIGH]
S23-041: fn_grant_document_access creates active grant record            [HIGH]
S23-042: fn_revoke_document_access sets revoked_at and revoked_by       [HIGH]
S23-043: fn_generate_document_download_url returns valid signed URL string[HIGH]
S23-044: fn_archive_vault_document sets status to archived               [HIGH]
S23-045: fn_delete_vault_document sets status to deleted                 [HIGH]
S23-046: Storage INSERT policy validates exact storage_path binding      [CRITICAL]
S23-047: Storage INSERT policy blocks cross-society folder upload       [CRITICAL]
S23-048: Storage INSERT policy blocks version substitution payload upload [CRITICAL]
S23-049: Explicit direct REVOKED grant overrides active role grant       [CRITICAL]
S23-050: Explicit direct REVOKED grant overrides active property grant   [CRITICAL]
S23-051: Explicit direct REVOKED grant overrides admin access            [CRITICAL]
S23-052: Expired user grant allows fallback to valid property grant      [HIGH]
S23-053: Document status SUPERSEDED assigned to older versions on v2 add [HIGH]
S23-054: Superseded version downloadable if document permissions hold    [HIGH]
S23-055: Audit log event UPLOAD_INITIATED written with correct parameters[HIGH]
S23-056: Audit log event UPLOAD_COMPLETED written with correct details   [HIGH]
S23-057: Audit log event DOCUMENT_ACTIVATED written by Edge worker       [HIGH]
S23-058: Audit log event ACCESS_GRANTED written on fn_grant_access       [HIGH]
S23-059: Audit log event ACCESS_REVOKED written on fn_revoke_access     [HIGH]
S23-060: Audit log event DOWNLOAD_URL_GENERATED written with caller UUID [HIGH]
S23-061: Audit log event DOCUMENT_ARCHIVED written on archival           [HIGH]
S23-062: Audit log event DOCUMENT_DELETED written on soft deletion       [HIGH]
S23-063: Audit log event VALIDATION_FAILED written on hash mismatch      [HIGH]
S23-064: Storage DELETE policy blocks direct client deletion (USING FALSE)[CRITICAL]
S23-065: Webhook invocation passes X-Webhook-Secret HMAC header          [HIGH]
S23-066: Storage anonymous GET returns HTTP 403 Forbidden                [CRITICAL]
S23-067: Storage authenticated direct GET returns HTTP 403 Forbidden    [CRITICAL]
S23-068: Forged payload SHA-256 transitions version to VERIFICATION_FAILED[CRITICAL]
S23-069: Forged payload MIME magic bytes fails validation               [CRITICAL]
S23-070: Payload size mismatch transitions version to VERIFICATION_FAILED[CRITICAL]
S23-071: Superseded version retains parent document RLS boundaries       [HIGH]
S23-072: Replay of stale webhook event ignored idempotently by RPC       [HIGH]
S23-073: Rank 1 Property Lock FOR SHARE acquired during download URL gen [CRITICAL]
S23-074: Orphan Storage objects older than 24h purged by service worker  [HIGH]
S23-075: Governance cumulative target check: 856 + 75 = 931 PASS         [CRITICAL]
================================================================================
```

---

## 13. PROPOSED MULTI-SESSION CONCURRENCY TEST INVENTORY (9 SCENARIOS)

```
================================================================================
PROPOSED SLICE 23 MULTI-SESSION CONCURRENCY SCENARIOS (S23-C1 THROUGH S23-C9)
================================================================================
S23-C1: First Upload Rate Limit Race
        - Sessions: 2 Parallel
        - Locks: Rank 2 (vault_rate_limits FOR UPDATE)
        - Behavior: INSERT ON CONFLICT DO NOTHING prevents PK error; counter = 1
        - Expected: 0 PK errors; 1 rate limit row; 1 document created

S23-C2: Upload Capacity Overflow (11th Parallel Upload)
        - Sessions: 11 Parallel
        - Locks: Rank 2 (vault_rate_limits FOR UPDATE)
        - Behavior: Exactly 10 uploads succeed; 11th rejected with Rate Limit Exceeded
        - Expected: 10 docs created; 11th throws exception cleanly

S23-C3: Concurrent Access Grant & Revocation
        - Sessions: 2 Parallel
        - Locks: Rank 3 (vault_documents FOR UPDATE) -> Rank 5 (vault_access_grants)
        - Behavior: Session A grants, Session B revokes; serialized on Rank 3 lock
        - Expected: 0 deadlocks; final state reflects winner; audit log written

S23-C4: Concurrent Revocation vs Signed URL Generation
        - Sessions: 2 Parallel
        - Locks: Rank 3 (vault_documents FOR SHARE) -> Rank 5 (vault_access_grants FOR SHARE)
        - Behavior: Session B revokes grant while Session A requests URL
        - Expected: 0 deadlocks; Session A blocked or denied cleanly

S23-C5: Concurrent Version Addition
        - Sessions: 2 Parallel
        - Locks: Rank 3 (vault_documents FOR UPDATE) -> Rank 4 (vault_document_versions)
        - Behavior: Both sessions add version to same document concurrently
        - Expected: Version numbers assigned sequentially (v2, v3); 0 collisions

S23-C6: Concurrent Document Archival vs Version Addition
        - Sessions: 2 Parallel
        - Locks: Rank 3 (vault_documents FOR UPDATE)
        - Behavior: Session A archives document while Session B adds version
        - Expected: Archive commits first; version addition fails with Document Not Active

S23-C7: Property Title Transfer vs Document Access
        - Sessions: 2 Parallel
        - Locks: Rank 1 (properties FOR SHARE in URL gen vs FOR UPDATE in Title Transfer)
        - Behavior: Title transfer transaction commits while former owner requests URL
        - Expected: Former owner blocked on Rank 1 lock; denied access upon commit

S23-C8: Tenant Move-Out vs Property Vault Access
        - Sessions: 2 Parallel
        - Locks: Rank 1 (properties FOR SHARE in URL gen vs FOR UPDATE in Tenancy End)
        - Behavior: Lease termination commits while ex-tenant requests URL
        - Expected: Ex-tenant blocked on Rank 1 lock; denied access upon commit

S23-C9: Duplicate Upload Retry Idempotency
        - Sessions: 2 Parallel
        - Locks: Rank 2 (vault_rate_limits FOR UPDATE) -> Rank 3 (vault_documents)
        - Behavior: Parallel retries of fn_initiate_document_upload with same client key
        - Expected: Exactly 1 document record created; second call returns existing UUID
================================================================================
```

---

## 14. COMPLETE RPC INVENTORY (9 ROUTINES)

### 1. `fn_initiate_document_upload`
- **Caller:** `authenticated` | **SEC DEFINER:** YES (`postgres`) | **Search Path:** `pg_catalog, public`
- **Params:** `p_property_id UUID, p_title VARCHAR, p_classification VARCHAR, p_file_name VARCHAR, p_file_size BIGINT, p_mime_type VARCHAR`
- **Return:** `UUID` (Version ID) | **Locks:** Rank 2 FOR UPDATE -> Rank 3 INSERT -> Rank 4 INSERT -> Rank 7 INSERT.
- **Grants:** `authenticated` | **Revokes:** `PUBLIC, anon`.

### 2. `fn_finalize_document_upload`
- **Caller:** `authenticated` | **SEC DEFINER:** YES (`postgres`) | **Search Path:** `pg_catalog, public`
- **Params:** `p_version_id UUID, p_claimed_sha256 VARCHAR`
- **Return:** `BOOLEAN` | **Locks:** Rank 4 FOR UPDATE -> Rank 7 INSERT.
- **Grants:** `authenticated` | **Revokes:** `PUBLIC, anon`.

### 3. `validate_vault_object_payload_internal`
- **Caller:** `service_role` (Internal Worker) | **SEC DEFINER:** YES (`postgres`) | **Search Path:** `pg_catalog, public`
- **Params:** `p_version_id UUID, p_actual_sha256 VARCHAR, p_actual_size BIGINT, p_detected_mime VARCHAR`
- **Return:** `BOOLEAN` | **Locks:** Rank 4 FOR UPDATE -> Rank 7 INSERT.
- **Grants:** `service_role` | **Revokes:** `PUBLIC, anon, authenticated`.

### 4. `fn_add_document_version`
- **Caller:** `authenticated` | **SEC DEFINER:** YES (`postgres`) | **Search Path:** `pg_catalog, public`
- **Params:** `p_document_id UUID, p_file_name VARCHAR, p_file_size BIGINT, p_mime_type VARCHAR`
- **Return:** `UUID` (Version ID) | **Locks:** Rank 3 FOR UPDATE -> Rank 4 INSERT -> Rank 7 INSERT.
- **Grants:** `authenticated` | **Revokes:** `PUBLIC, anon`.

### 5. `fn_grant_document_access`
- **Caller:** `authenticated` | **SEC DEFINER:** YES (`postgres`) | **Search Path:** `pg_catalog, public`
- **Params:** `p_document_id UUID, p_grantee_type VARCHAR, p_grantee_user_id UUID, p_grantee_role VARCHAR, p_expires_at TIMESTAMPTZ`
- **Return:** `UUID` (Grant ID) | **Locks:** Rank 3 FOR UPDATE -> Rank 5 INSERT -> Rank 7 INSERT.
- **Grants:** `authenticated` | **Revokes:** `PUBLIC, anon`.

### 6. `fn_revoke_document_access`
- **Caller:** `authenticated` | **SEC DEFINER:** YES (`postgres`) | **Search Path:** `pg_catalog, public`
- **Params:** `p_grant_id UUID`
- **Return:** `BOOLEAN` | **Locks:** Rank 3 FOR UPDATE -> Rank 5 FOR UPDATE -> Rank 7 INSERT.
- **Grants:** `authenticated` | **Revokes:** `PUBLIC, anon`.

### 7. `fn_generate_document_download_url`
- **Caller:** `authenticated` | **SEC DEFINER:** YES (`postgres`) | **Search Path:** `pg_catalog, public`
- **Params:** `p_document_id UUID, p_version_id UUID`
- **Return:** `TEXT` (Signed URL) | **Locks:** Rank 1 FOR SHARE -> Rank 2 FOR UPDATE -> Rank 3 FOR SHARE -> Rank 5 FOR SHARE -> Rank 7 INSERT.
- **Grants:** `authenticated` | **Revokes:** `PUBLIC, anon`.

### 8. `fn_archive_vault_document`
- **Caller:** `authenticated` | **SEC DEFINER:** YES (`postgres`) | **Search Path:** `pg_catalog, public`
- **Params:** `p_document_id UUID`
- **Return:** `BOOLEAN` | **Locks:** Rank 3 FOR UPDATE -> Rank 7 INSERT.
- **Grants:** `authenticated` | **Revokes:** `PUBLIC, anon`.

### 9. `fn_delete_vault_document`
- **Caller:** `authenticated` | **SEC DEFINER:** YES (`postgres`) | **Search Path:** `pg_catalog, public`
- **Params:** `p_document_id UUID`
- **Return:** `BOOLEAN` | **Locks:** Rank 3 FOR UPDATE -> Rank 7 INSERT.
- **Grants:** `authenticated` | **Revokes:** `PUBLIC, anon`.

---

## 16. RESOLUTION OF ARCHITECTURE QUESTIONS

1. **Payload Verification Worker Hosting:** **DECIDED.** Supabase Edge Function (`validate_vault_object_payload`) triggered via database webhook on `vault_document_versions` status update to `'UPLOADED'`.
2. **Society Storage Quota:** **EXPLICITLY DEFERRED.** Out of scope / Future infrastructure. *Residual Risk:* Authorized users collectively may consume significant storage. Individual controls (10 uploads/hr/user, 50MB/file size cap) prevent single-user DoS.

---

## 17. GOVERNANCE GATES & AUTHORIZATION STAGES

```
GATE 0: Initial Forensic Discovery & Plan-Only Security Planning (REVISION 3 COMPLETE)
GATE 1: Pre-Implementation Gate Audit & Adversarial Review
GATE 2: Gate A Implementation Authorization
GATE 3: Gate B Verification Execution
GATE 4: Post-Gate-B Forensic Lock-Readiness Audit
GATE 5: Gate C Formal Security Lock
```

---

## 18. PLAN ARTIFACT INFORMATION

```
FILENAME:   SLICE23_DIGITAL_DOCUMENT_VAULT_FORENSIC_SECURITY_PLAN.md
LOCATION:   D:\Clients Applications\SU Society App\SLICE23_DIGITAL_DOCUMENT_VAULT_FORENSIC_SECURITY_PLAN.md
STATUS:     PLAN ONLY (REVISION 3) — NOT IMPLEMENTED — NOT VERIFIED — NOT LOCKED
```

---

## 19. FORMAL GOVERNANCE CONFIRMATIONS

```
SLICE 23 — PLAN ONLY / ZERO IMPLEMENTATION / ZERO BASELINE MUTATION
CURRENT AUTHORITATIVE BASELINE: 856 / 856 PASS — LOCKED / IMMUTABLE
```
