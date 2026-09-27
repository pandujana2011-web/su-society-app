# SLICE 23 — FORMAL FORENSIC SECURITY PLAN

**Target Repository:** `D:\Clients Applications\SU Society App`  
**Target Supabase Project:** `fsegpxqoozxmicxcxjun`  
**Execution Mode:** `PLAN ONLY` (ZERO implementation, ZERO remote mutation, ZERO deployment, ZERO SQL/DML execution, ZERO baseline mutation, ZERO lock creation, ZERO governance closure)

---

## 1. AUTHORITATIVE PREDECESSOR STATE & BOUNDARIES

### Slice 21 Predecessor:
* **Status:** `SECURITY / GOVERNANCE LOCKED — IMMUTABLE`
* **Lock SHA-256:** `C8F5E8742CA04391AC51889AD671CD9868710F7C5AB6CC6A9C39C84BCAF16912`
* **Integrity:** `100% TOUCHLESS & VERIFIED`

### Slice 22 Predecessor:
* **Status:** `APPLIED / GOVERNANCE CLOSED / SECURITY & GOVERNANCE LOCKED — IMMUTABLE`
* **Lock SHA-256:** `BADDA60288021729D4E46A38642ECBBAB3C89EDDCC3A8BCC603EAA6A9B36C3C7`
* **Lock Creation Timestamp:** `2026-09-15T13:30:00Z`
* **Remote Boundary Migration:** `20260912000022_slice22.sql`
* **Integrity:** `100% TOUCHLESS & VERIFIED`

### Baseline Assertion Accounting:
* **Historical Baseline (Pre-Slice 22):** `931 / 931 PASS` (Baseline SHA-256: `47A7093CB842BB10179D529E85452BBD8B463E3057725B28E69A5E99AC614448`)
* **Slice 22 Verified Substantive Assertions:** `65 assertions`
* **Current Post-Slice-22 Verified Baseline:** `996 / 996 PASS` (`931 + 65`)

### Slice 23 Lifecycle Initialization Gate:
* **Artifact:** `SLICE23_LIFECYCLE_INITIALIZATION_FORENSIC_SECURITY_GATE.md`
* **SHA-256:** `5A3F036742A7405BE058BBEA363AC2C9AF9886305644EAB2B8AE8C59DC854F85`
* **Classification:** `A. SLICE 23 LIFECYCLE INITIALIZATION FORENSIC GATE PASSED`

### Slice 23 Current Authorization & Remote State:
* **Authorization State:** `NOT AUTHORIZED / NOT IMPLEMENTED / NOT DEPLOYED / NOT LOCKED`
* **Remote Deployment Status:** `100% UNAPPLIED / EXCLUDED`

---

## 2. DISCOVERED SLICE 23 SCOPE & RECONCILIATION

Independently reconciled from repository source files (`supabase/migrations/20260912000023_slice23.sql`, `database/schema_slice23.sql`, and `database/verify_slice23.sql`):

### Domain Scope:
Digital Document Vault & Confidentiality Authorization System.

### Detailed Inventory Reconciliation:
1. **Five (5) Domain Tables:**
   - `public.vault_documents` (Master confidential document records, classification, tenant isolation)
   - `public.vault_document_versions` (Append-only storage payload tracking, SHA-256 integrity, size/MIME validation)
   - `public.vault_access_grants` (Explicit granular access delegations for users, roles, and properties)
   - `public.vault_audit_logs` (Immutable append-only forensic audit trails for upload, view, grant, revoke, download, archive, delete)
   - `public.vault_rate_limits` (Transactional rate limiting counters for upload and download URL generation)

2. **Eleven (11) Functions:**
   - `fn_is_valid_vault_storage_path(text)` (Storage path structure & traversal validation)
   - `fn_resolve_document_access(uuid, uuid)` (Multi-tier confidentiality authorization engine)
   - `fn_initiate_document_upload(uuid, varchar, varchar, varchar, bigint, varchar)` (Secure upload ticket & version initialization)
   - `fn_finalize_document_upload(uuid, varchar)` (Payload upload finalization & integrity check)
   - `validate_vault_object_payload_internal(uuid, varchar, bigint, varchar)` (Webhook/Storage callback validation RPC)
   - `fn_add_document_version(uuid, varchar, bigint, varchar)` (Append new version to existing document)
   - `fn_grant_document_access(uuid, varchar, uuid, varchar, uuid, timestamptz)` (Delegate access grant)
   - `fn_revoke_document_access(uuid)` (Explicitly revoke active access grant)
   - `fn_generate_document_download_url(uuid)` (Rate-limited, authorization-verified signed URL generation ticket)
   - `fn_archive_vault_document(uuid)` (Archive document and invalidate active grants)
   - `fn_delete_vault_document(uuid)` (Soft/Hard purge document and associated version metadata)

3. **Two (2) Triggers:**
   - `trg_vault_documents_updated_at` (Auto-updates `updated_at` on `vault_documents`)
   - `trg_vault_document_versions_updated_at` (Auto-updates `updated_at` on `vault_document_versions`)

4. **Four (4) Storage Policies on `storage.objects` (Bucket `society-vault`):**
   - `pol_vault_storage_select` (Strict SELECT policy: Service role or signed URL path matching only)
   - `pol_vault_storage_insert` (Strict INSERT policy: Service role or staging upload matching active version ticket)
   - `pol_vault_storage_update` (Strict UPDATE policy: USING FALSE / 100% Blocked for direct clients)
   - `pol_vault_storage_delete` (Strict DELETE policy: USING FALSE / 100% Blocked for direct clients)

5. **Seventy-Five (75) Substantive Verification Assertions:**
   - Test assertions `S23-001` through `S23-075` in `database/verify_slice23.sql`.

---

## 3. ABSOLUTE LOCKED-PREDECESSOR PROTECTION
Slices 21 and 22 are locked and immutable.
* ZERO modification allowed to `20260912000021_slice21.sql` or `20260912000022_slice22.sql`.
* ZERO alteration allowed to predecessor schema mirrors, verification scripts, governance records, or security locks.
* If any feature in Slice 23 requires predecessor changes, it must be flagged immediately as a critical blocker; no silent modification or repair is permitted.

---

## 4. DIGITAL DOCUMENT VAULT THREAT & SECURITY MODEL

### Confidentiality Tiers & Access Controls:
1. `public_society`: Accessible to all active members of the target society.
2. `resident_visible`: Accessible to any active resident, owner, or tenant within the society.
3. `owner_confidential`: Accessible strictly to the primary property owner, society admins, or explicitly granted users.
4. `tenant_confidential`: Accessible strictly to active tenants of the specific unit/property, property owners, admins, or explicit grantees.
5. `committee_confidential`: Accessible strictly to verified committee members or admins.
6. `admin_confidential`: Accessible strictly to active society administrators.
7. `strictly_restricted`: Accessible strictly via explicit entry in `vault_access_grants`.

### Storage Security vs. Database RLS Boundaries:
* **Database RLS:** Protects document metadata, titles, versions, and access grants. Direct client queries to `vault_documents` or `vault_document_versions` are filtered by society membership and confidentiality tier authorization.
* **Storage Bucket (`society-vault`):** Object payload files are stored in `storage.objects`. Direct client READ, UPDATE, and DELETE operations are 100% blocked (`USING FALSE`). Access to raw files is permitted **only** via short-lived, HMAC-signed URLs generated server-side by `fn_generate_document_download_url(uuid)` after strict authorization checks and rate-limit enforcement.

---

## 5. STORAGE SECURITY FORENSICS & BUCKET POLICIES

### Bucket Configuration:
* Bucket Name: `society-vault`
* Public Read: `FALSE` (Private bucket)

### Policy Analysis:
1. `pol_vault_storage_select`:
   - **Target Operation:** `SELECT`
   - **Target Role:** `authenticated`
   - **USING Condition:** Enforces that download requests match authorized storage path patterns or valid signed URL claims. Direct unauthorized object browsing is completely prevented.
2. `pol_vault_storage_insert`:
   - **Target Operation:** `INSERT`
   - **Target Role:** `authenticated`
   - **WITH CHECK Condition:** Enforces path validation via `fn_is_valid_vault_storage_path` and matches the user's initiated upload session (`UPLOAD_INITIATED` status).
3. `pol_vault_storage_update`:
   - **Target Operation:** `UPDATE`
   - **Target Role:** `authenticated`
   - **USING Condition:** `FALSE` (Object payloads are immutable; version updates require inserting a new version record).
4. `pol_vault_storage_delete`:
   - **Target Operation:** `DELETE`
   - **Target Role:** `authenticated`
   - **USING Condition:** `FALSE` (Direct client object deletion is forbidden; purging must occur through server-side cleanup routines).

---

## 6. RLS / MULTI-TENANT ISOLATION MODEL

### Row Level Security Enforcement:
All 5 domain tables (`vault_documents`, `vault_document_versions`, `vault_access_grants`, `vault_audit_logs`, `vault_rate_limits`) require:
* `ALTER TABLE ... ENABLE ROW LEVEL SECURITY;`
* `ALTER TABLE ... FORCE ROW LEVEL SECURITY;`

### Multi-Tenant Isolation Controls:
* Every query evaluation strictly verifies society isolation via `fn_is_society_member(auth.uid(), society_id)`.
* Cross-society reads and writes are blocked at the RLS layer even if a user knows valid document UUIDs from another society.
* Direct client `INSERT`, `UPDATE`, and `DELETE` queries on vault tables are blocked or tightly restricted; state mutations must occur through dedicated `SECURITY DEFINER` RPC functions that validate caller identity via `auth.uid()`.

---

## 7. CONFIDENTIALITY AUTHORIZATION ENGINE

### Access Resolution (`fn_resolve_document_access`):
When a user requests access to a document (or download URL generation), `fn_resolve_document_access(p_document_id, p_user_id)` evaluates authorization in the following order:
1. **Null/System Guard:** If `p_user_id IS NULL` or user is inactive, return `FALSE`.
2. **Society Boundary Guard:** If `p_user_id` is not an active member of `document.society_id`, return `FALSE`.
3. **Admin Exemption:** If user is a verified `admin` in the target society, return `TRUE`.
4. **Explicit Access Grants:** If an unrevoked, unexpired record exists in `vault_access_grants` matching `p_user_id`, caller's active role, or caller's linked property, return `TRUE`.
5. **Confidentiality Tier Evaluation:**
   - `public_society`: `TRUE` for any active society member.
   - `resident_visible`: `TRUE` for active residents, owners, tenants.
   - `owner_confidential`: `TRUE` if user is verified primary property owner via `fn_is_property_owner`.
   - `tenant_confidential`: `TRUE` if user is active tenant of the linked unit or primary property owner.
   - `committee_confidential`: `TRUE` if user holds `committee` role in target society.
   - `admin_confidential`: `TRUE` only for society admins.
   - `strictly_restricted`: `FALSE` (requires explicit grant).
6. **Default Fallback:** Return `FALSE` (Fail-closed).

---

## 8. AUDIT & IMMUTABILITY MODEL

### Append-Only Forensic Audit Log (`vault_audit_logs`):
* Every security-sensitive document lifecycle event writes an immutable audit record:
  - `UPLOAD_INITIATED`, `UPLOAD_COMPLETED`, `DOCUMENT_ACTIVATED`
  - `ACCESS_GRANTED`, `ACCESS_REVOKED`
  - `DOWNLOAD_URL_GENERATED`
  - `DOCUMENT_ARCHIVED`, `DOCUMENT_DELETED`
  - `VALIDATION_FAILED` (on payload SHA-256 or size mismatch)
* `vault_audit_logs` RLS permits `INSERT` and `SELECT` by society admins/auditors. Direct `UPDATE` and `DELETE` operations are strictly prohibited.

---

## 9. SECURITY DEFINER FUNCTION FORENSICS & HARDENING

All 11 Slice 23 functions must strictly adhere to the project security standards:
1. **Search Path Hardening:** Explicitly declared `SET search_path = public, pg_temp;` (or `SET search_path = pg_catalog, public;` for pure utility functions).
2. **Caller Identity Verification:** Mandatory check `v_caller_id := auth.uid();` with immediate `RAISE EXCEPTION 'UNAUTHORIZED'` if `NULL`.
3. **Explicit Revokes & Grants:**
   - `REVOKE ALL ON FUNCTION ... FROM PUBLIC, anon;`
   - `GRANT EXECUTE ON FUNCTION ... TO authenticated, service_role;`
4. **Parameter Qualification:** Zero 1-parameter `has_role` calls; all role checks must be 2-parameter (`fn_is_society_admin(v_caller_id, v_society_id)`).

---

## 10. CONCURRENCY, LOCK ORDERING & SERIALIZATION

### Rank 1 Lock Ordering:
To eliminate deadlock hazards when resolving permissions across property structures:
1. Lock society membership (`user_roles`) in deterministic user ID order.
2. Lock property record (`properties FOR SHARE`) in UUID order prior to evaluating property ownership/tenancy.
3. Lock `vault_documents FOR UPDATE` prior to updating document status or adding versions.
4. Rate limit check uses atomic counter updates (`ON CONFLICT DO UPDATE`) on `vault_rate_limits`.

---

## 11. PRIVILEGE & GRANT SPECIFICATION

| Target Object | PUBLIC | anon | authenticated | service_role |
|---|---|---|---|---|
| `vault_documents` | REVOKE ALL | REVOKE ALL | SELECT (RLS) | ALL |
| `vault_document_versions` | REVOKE ALL | REVOKE ALL | SELECT (RLS) | ALL |
| `vault_access_grants` | REVOKE ALL | REVOKE ALL | SELECT (RLS) | ALL |
| `vault_audit_logs` | REVOKE ALL | REVOKE ALL | SELECT (RLS Admin) | ALL |
| `vault_rate_limits` | REVOKE ALL | REVOKE ALL | NO DIRECT ACCESS | ALL |
| All 11 Functions | REVOKE ALL | REVOKE ALL | EXECUTE (Gated) | EXECUTE |

---

## 12. ATTACK-SURFACE RISK & MITIGATION MATRIX

| ID | Attack Vector | Affected Component | Risk | Planned Mitigation Control | Verification ID |
|---|---|---|---|---|---|
| **R23-01** | Cross-society document metadata read | `vault_documents` | High | `pol_vault_documents_select` checks `fn_is_society_member` | `S23-009` |
| **R23-02** | Cross-society storage object download | `storage.objects` | Critical | Direct storage GET blocked (`USING FALSE`); download via RPC | `S23-066` |
| **R23-03** | Unauthorized document upload ticket | `fn_initiate_document_upload` | High | Validates society membership & role authorization before ticket issuance | `S23-015` |
| **R23-04** | Payload forgery (SHA-256 mismatch) | `validate_vault_object_payload_internal` | Critical | Server-side hash check; marks `VERIFICATION_FAILED` & logs audit | `S23-068` |
| **R23-05** | Payload size / MIME type spoofing | `validate_vault_object_payload_internal` | High | Strict byte size & MIME magic header validation | `S23-069`, `S23-070` |
| **R23-06** | Ex-tenant accessing tenant-confidential doc | `fn_resolve_document_access` | High | Re-evaluates active tenancy status on every access check | `S23-012` |
| **R23-07** | Revoked grant re-use | `vault_access_grants` | High | Filters `revoked_at IS NULL AND (expires_at IS NULL OR expires_at > now())` | `S23-026` |
| **R23-08** | Storage path traversal (`../`) | `fn_is_valid_vault_storage_path` | Critical | Strict regex pattern matching & traversal string rejection | `S23-031` |
| **R23-09** | Rate limit DoS (URL generation flooding) | `vault_rate_limits` | Medium | Max 60 download URL requests per 15-minute window | `S23-048` |
| **R23-10** | Unauthenticated anon function call | All 11 RPCs | High | `REVOKE ... FROM anon, PUBLIC` & strict `auth.uid()` checks | `S23-040` |
| **R23-11** | Direct table row deletion by client | `vault_documents` | High | RLS DELETE policy set to `FALSE` for clients; RPC soft delete required | `S23-052` |
| **R23-12** | Direct storage payload deletion by client | `storage.objects` | High | `pol_vault_storage_delete` USING condition set to `FALSE` | `S23-064` |
| **R23-13** | Search path hijacking in SECURITY DEFINER | All 11 RPCs | High | Explicit `SET search_path = public, pg_temp;` on all functions | `S23-038` |
| **R23-14** | Audit log record alteration/deletion | `vault_audit_logs` | High | Direct client UPDATE/DELETE blocked by RLS | `S23-055` |
| **R23-15** | Self-authorization grant injection | `fn_grant_document_access` | High | Validates caller is document owner or society admin | `S23-024` |
| **R23-16** | Unauthorised version incrementing | `fn_add_document_version` | Medium | Validates caller write permissions on parent document | `S23-021` |
| **R23-17** | Expired access grant usage | `vault_access_grants` | Medium | Strict timestamp check `expires_at > CURRENT_TIMESTAMP` | `S23-027` |
| **R23-18** | Stale signed URL reuse after revocation | Storage API | Medium | Signed URL lifetime limited to 300 seconds (5 mins) | `S23-046` |
| **R23-19** | Property owner confidentiality bypass | `fn_resolve_document_access` | High | Restricts `owner_confidential` docs to verified active owner | `S23-010` |
| **R23-20** | Committee confidential doc leak to tenant | `fn_resolve_document_access` | High | Enforces committee role check | `S23-013` |
| **R23-21** | Admin confidential doc leak to resident | `fn_resolve_document_access` | High | Enforces admin role check | `S23-014` |
| **R23-22** | Concurrent grant race condition | `vault_access_grants` | Medium | Unique constraint `(document_id, grantee_type, grantee_user_id...)` | `S23-029` |
| **R23-23** | Concurrent upload race condition | `fn_finalize_document_upload` | Medium | `SELECT FOR UPDATE` on version record during finalization | `S23-073` |
| **R23-24** | Webhook request forgery | `validate_vault_object_payload_internal` | High | Validates HMAC signature with `X-Webhook-Secret` header | `S23-065` |
| **R23-25** | Orphaned storage object accumulation | Service Worker | Low | Automated 24h cleanup worker purges unfinalized payloads | `S23-074` |
| **R23-26** | Document title / metadata exposure | `vault_documents` | Medium | Metadata RLS applies exact same access resolution as downloads | `S23-009` |
| **R23-27** | Unrestricted `public_society` doc deletion | `fn_delete_vault_document` | High | Purge requires society admin privileges regardless of doc tier | `S23-054` |
| **R23-28** | Replay attack on upload callback | Callback RPC | Medium | Idempotent status check ignores already-activated versions | `S23-072` |
| **R23-29** | Inactive user accessing active grant | `fn_resolve_document_access` | High | Checks `users.status = 'active'` before honoring grant | `S23-028` |
| **R23-30** | Superseded version leaking updated secrets | `vault_document_versions` | High | Historical versions retain parent document access boundaries | `S23-071` |

---

## 13. VERIFICATION ASSERTION PLAN

`database/verify_slice23.sql` contains 75 substantive verification assertions (`S23-001` through `S23-075`):
* **Domain Structure & Existence (S23-001 to S23-008):** Verifies existence of 5 tables and 3 core indexes.
* **Access Resolution & Tiers (S23-009 to S23-014):** Tests society, property, owner, tenant, committee, and admin access resolution.
* **Document Lifecycle RPCs (S23-015 to S23-023):** Tests initiation, versioning, finalization, and archiving.
* **Access Delegation & Revocation (S23-024 to S23-030):** Tests user/role/property access grants, revocation, and expiry.
* **Storage Path & Utility Security (S23-031 to S23-039):** Tests path traversal protection, regex pattern matching, and search path safety.
* **RPC Privilege Controls (S23-040 to S23-047):** Tests anonymous blocking, role gating, and rate limiting.
* **Audit Logging & Edge Cases (S23-048 to S23-074):** Tests audit log insertion across all events, storage bucket policy enforcement, payload validation failure handling, and concurrency locks.
* **Cumulative Target Check (S23-075):** Verifies all prior 74 assertions passed cleanly.

*Note on Comment Text Reconciliation:* Line 5 of `database/verify_slice23.sql` contains legacy header comment text (`856 + 75 = 931 PASS`) written prior to Slices 20-22. The authoritative baseline post-Slice 22 is `996 PASS`.

---

## 14. CUMULATIVE ASSERTION ACCOUNTING
* **Historical Baseline (through Slice 21):** `931 / 931 PASS`
* **Slice 22 Verified Additions:** `65 assertions`
* **Post-Slice 22 Verified Total:** `996 / 996 PASS`
* **Slice 23 Planned Additions:** `75 assertions`
* **Planned Post-Slice-23 Cumulative Target:** `996 + 75 = 1071 PASS`

*CRITICAL NOTICE:* `1071 PASS` is strictly a planning target. Zero Slice 23 assertions have been executed or marked as PASS.

---

## 15. DEPLOYMENT GOVERNANCE & GATES

Slice 23 lifecycle must strictly follow the required 12-stage sequential governance process:
1. `[x]` Lifecycle Initialization Forensic Security Gate (`SLICE23_LIFECYCLE_INITIALIZATION_FORENSIC_SECURITY_GATE.md`)
2. `[x]` Formal Forensic Security Plan (Current Artifact: `SLICE23_FORMAL_FORENSIC_SECURITY_PLAN.md`)
3. `[ ]` Adversarial Security Review & Vulnerability Assessment
4. `[ ]` Local Implementation Authorization Gate
5. `[ ]` Slice 23 Local Implementation & Verification Execution
6. `[ ]` Post-Implementation Forensic Security Audit Gate
7. `[ ]` Remote Deployment Scope Dry-Run Gate
8. `[ ]` Explicit Human Remote Deployment Authorization
9. `[ ]` Isolated M-02 Remote Migration Execution (`20260912000023_slice23.sql`)
10. `[ ]` Post-Deployment Forensic Verification Audit
11. `[ ]` Governance Closure Authorization
12. `[ ]` Security & Governance Lock Creation

---

## 16. REQUIRED HUMAN AUTHORIZATION BOUNDARIES
This formal plan authorizes **ONLY** the creation of this planning document.
* NO authorization for local implementation.
* NO authorization for remote migration or SQL push.
* NO authorization for data modification.
* NO authorization for verification execution.
* NO authorization for security lock creation or governance closure.

---

## 17. PLAN CLASSIFICATION
**CLASSIFICATION:**
`Classification A: SLICE 23 FORMAL FORENSIC SECURITY PLAN COMPLETE — READY FOR ADVERSARIAL SECURITY REVIEW`
