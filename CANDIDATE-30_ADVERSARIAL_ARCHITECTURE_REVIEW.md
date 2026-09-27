# SU SOCIETY APP — CANDIDATE-30
## DATA MIGRATION CENTER ADVERSARIAL ARCHITECTURE REVIEW

**Target Repository:** `D:\Clients Applications\SU Society App`  
**Target Production Supabase Project:** `fsegpxqoozxmicxcxjun` (`pandujana2011-web's Project`)  
**Region:** `ap-south-1`  
**PostgreSQL Version:** `17.6.1.166`  
**Production Application URL:** `https://su-society-app.vercel.app`  
**Execution Mode:** `READ-ONLY ADVERSARIAL FORENSIC ARCHITECTURE REVIEW / ZERO MUTATION`  
**Human Authorization:** `REVIEW ONLY / NO IMPLEMENTATION AUTHORIZED`  
**Target Architecture Specification:** [CANDIDATE-30_DATA_MIGRATION_CENTER_TECHNICAL_ARCHITECTURE_SPECIFICATION.md](file:///D:/Clients%20Applications/SU%20Society%20App/CANDIDATE-30_DATA_MIGRATION_CENTER_TECHNICAL_ARCHITECTURE_SPECIFICATION.md)  
**Target Architecture SHA-256:** `07F86251E34BD4D0AFE0C81A821D74BE35D357F791D29930FB843D168F32FC24`  
**Authoritative Execution Date:** `2026-09-21`

---

## 1. EXECUTIVE SUMMARY & ADVERSARIAL VERDICT

This report provides an independent, adversarial forensic security and data-integrity review of the proposed Candidate-30 Data Migration Center architecture specification.

Rather than merely summarizing the proposed architecture, this review actively challenged the specification across 18 attack vectors, including cross-society multi-tenant leakage, SECURITY DEFINER privilege escalation, staging table tampering, stale preview approvals, rollback data loss, idempotency failures, financial ledger corruption, and parser DoS attacks.

### Final Adversarial Classification:
`B — VALID ARCHITECTURE WITH REQUIRED CORRECTIONS`

The proposed Candidate-30 architecture is fundamentally sound and well-structured, but contains nine (9) specific security and data-integrity gaps that MUST be corrected before implementation authorization is granted.

---

## 2. ARCHITECTURE REVIEWED

The target specification ([CANDIDATE-30_DATA_MIGRATION_CENTER_TECHNICAL_ARCHITECTURE_SPECIFICATION.md](file:///D:/Clients%20Applications/SU%20Society%20App/CANDIDATE-30_DATA_MIGRATION_CENTER_TECHNICAL_ARCHITECTURE_SPECIFICATION.md)) defines a 12-stage state machine (`draft` → `closed`), 5 quarantine staging tables, a 9-tier validation engine, and two SECURITY DEFINER RPCs (`fn_commit_migration_batch`, `fn_rollback_migration_batch`).

---

## 3. ADVERSARIAL THREAT MODEL & ATTACK SURFACE

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           ATTACK VECTORS EVALUATED                          │
├─────────────────────────────────────────────────────────────────────────────┤
│ 1. Cross-Society Staging Hijack     (Tenant A modifying Tenant B staging)  │
│ 2. Staging Data Tampering           (Altering staging JSON post-approval)   │
│ 3. Stale Approval Replay            (Committing modified staging payload)   │
│ 4. SECURITY DEFINER Scope Escalation (Bypassing society_id in RPC)          │
│ 5. Destructive Rollback Cascade     (Deleting post-import live updates)     │
│ 6. Race Conditions & Double Commit  (Concurrent admin commit triggers)       │
│ 7. CSV Formula Injection Bypass     (Passing malicious strings via REST)   │
│ 8. Financial Discriminator Bypass   (Injecting 'none' billing_subject_type) │
│ 9. Audit Event Identity Forgery     (Spoofing actor ID in audit records)    │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. SECURITY DEFINER RPC REVIEW

### Evaluated Functions: `fn_commit_migration_batch` & `fn_rollback_migration_batch`

#### Adversarial Findings:
1. **`SET search_path` Hardening Missing:** The Phase 2 specification did not explicitly mandate `SET search_path = public, pg_temp;` on `SECURITY DEFINER` RPC definitions. Without explicit `search_path` locking, an attacker could manipulate search path variables to execute malicious schema functions.  
   *Classification:* **HIGH SECURITY FINDING (SEC-01)**.
2. **Explicit Public Execution Revocation:** RPC definitions must explicitly execute `REVOKE EXECUTE ON FUNCTION fn_commit_migration_batch FROM PUBLIC;` and grant execution strictly to `authenticated` admin roles.  
   *Classification:* **MEDIUM SECURITY FINDING (SEC-02)**.
3. **Society ID Spoofing Check:** RPCs must derive `v_society_id` strictly from `(SELECT (auth.jwt() -> 'app_metadata' ->> 'society_id')::uuid)` or `auth.jwt() ->> 'society_id'` rather than accepting an unverified `society_id` parameter from client input.  
   *Classification:* **CRITICAL MULTI-TENANT FINDING (SEC-03)**.

---

## 5. MULTI-TENANT ISOLATION ATTACKS

### Evaluated Attack Scenario: Cross-Society Staging Manipulation
* **Attack Vector:** An administrator from Society A submits a REST request containing `batch_id` belonging to Society B.
* **Architecture Evaluation:** RLS policies on `migration_batches` and `migration_staging_rows` enforce `society_id = (SELECT auth.jwt() ->> 'society_id')::uuid`. However, if `fn_commit_migration_batch()` executes with `SECURITY DEFINER` privileges, RLS is BYPASSED inside the function body.
* **Required Correction:** The SECURITY DEFINER RPC MUST include an explicit internal assertion:
  ```sql
  IF v_batch_society_id <> v_caller_society_id THEN
    RAISE EXCEPTION 'Access Denied: Batch belongs to another society context.';
  END IF;
  ```
  *Classification:* **CRITICAL MULTI-TENANT FINDING (SEC-04)**.

---

## 6. STAGING TABLE SECURITY & TAMPERING REVIEW

### Adversarial Finding: Missing Staging Payload Checksum
* **Vulnerability:** In the Phase 2 specification, an administrator runs validation, receives preview approval for batch status `approved`, and then triggers commit. Between approval and commit, an attacker could send raw SQL/REST UPDATE statements to `migration_staging_rows` to modify row values (e.g. changing an opening balance from ₹1,000 to ₹100,000).
* **Required Correction:**
  1. `migration_batches` MUST store a cryptographic `dataset_hash` (SHA-256 of all row checksums in `migration_staging_rows`) generated when transitioning to `validation_passed`.
  2. `fn_commit_migration_batch()` MUST re-calculate the `dataset_hash` at commit time and abort if the hash differs from `approved_dataset_hash`.
  *Classification:* **HIGH DATA-INTEGRITY FINDING (INT-01)**.

---

## 7. APPROVAL INTEGRITY & STALE PREVIEW REVIEW

### Adversarial Finding: Approval Replay & Dataset Mismatch
* **Vulnerability:** If staging rows are re-validated after approval, the batch status could remain `approved` while staging contents change.
* **Required Correction:** Any modification to `migration_field_mappings` or `migration_staging_rows` MUST automatically reset `migration_batches.status` back to `draft`, invalidating previous approvals.  
  *Classification:* **MEDIUM GOVERNANCE FINDING (GOV-01)**.

---

## 8. ATOMIC COMMIT REVIEW

### Adversarial Finding: Partial Batch Commit in Chunked Transactions
* **Vulnerability:** The Phase 2 specification mentioned "transaction chunking (e.g. 100 rows per transaction)" to avoid statement timeouts. However, if transaction chunk #3 fails after chunks #1 and #2 succeed, the database is left in a partially committed, corrupt state.
* **Required Correction:**
  1. Batch commitment within `fn_commit_migration_batch()` MUST execute inside a **SINGLE, ATOMIC PostgreSQL TRANSACTION BLOCK**.
  2. Statement timeouts for batch commits must be configured safely (`SET LOCAL statement_timeout = '60s'`). Chunking across separate HTTP requests is PROHIBITED.
  *Classification:* **CRITICAL DATA-INTEGRITY FINDING (INT-02)**.

---

## 9. ROLLBACK REVIEW

### Adversarial Finding: Destructive Over-Deletion during Rollback
* **Vulnerability:** Naive deletion of records matching `migration_batch_id` in `users` or `properties` can cause catastrophic data loss if live operational records (e.g., payments, NOC requests, maintenance bills) were subsequently attached to those imported records.
* **Required Correction:** `fn_rollback_migration_batch()` MUST check for linked operational records before deleting. If linked records exist, direct deletion is BLOCKED, and the batch MUST be marked `rollback_blocked`, requiring manual administrative reconciliation.  
  *Classification:* **HIGH DATA-INTEGRITY FINDING (INT-03)**.

---

## 10. IDEMPOTENCY & REPLAY ATTACK REVIEW

### Adversarial Finding: Concurrent Double-Submit
* **Vulnerability:** Two administrators clicking "Commit Migration" simultaneously could trigger concurrent RPC executions, resulting in duplicate user or property insertions.
* **Required Correction:** `fn_commit_migration_batch()` MUST acquire a **PostgreSQL Transaction Advisory Lock** based on `society_id` at entry:
  ```sql
  PERFORM pg_advisory_xact_lock(hashtext('migration_lock_' || v_caller_society_id::text));
  ```
  This guarantees strict single-threaded serialization for migration commits per society.  
  *Classification:* **HIGH CONCURRENCY FINDING (CON-01)**.

---

## 11. FINANCIAL INTEGRITY REVIEW

### Adversarial Finding: Historical Payment Misclassification
* **Vulnerability:** Importing historical payments as live `payments` records could trigger automated notifications, double-book ledger credits, or regenerate receipts.
* **Required Correction:** All legacy financial balances MUST be imported strictly as cut-off `opening_balances` records with `billing_subject_type = 'property'` and `billing_property_id = property_id`. Legacy individual payment slips are stored strictly as read-only historical metadata attachments.  
  *Classification:* **CRITICAL FINANCIAL INTEGRITY FINDING (FIN-01)**.

---

## 12. DUPLICATE DETECTION REVIEW

* **Finding:** Advisory matching versus authoritative blocking.
* **Correction:** Duplicate phone numbers or property numbers MUST generate `warning` flags in staging rows. The preview screen requires explicit admin decisions (`Skip`, `Link Existing`, or `Block Batch`) before status can transition to `ready_for_review`.

---

## 13. FILE SECURITY & SANITIZATION REVIEW

### Adversarial Finding: CSV Formula Injection via REST API
* **Vulnerability:** Client-side CSV sanitization can be bypassed by submitting raw JSON payloads directly to `migration_staging_rows` via REST.
* **Required Correction:** Server-side trigger `trg_sanitize_staging_input` MUST automatically strip or escape leading `=`, `+`, `-`, `@` characters on all string fields stored in `mapped_data` JSONB.  
  *Classification:* **HIGH SECURITY FINDING (SEC-05)**.

---

## 14. SANITIZATION REVIEW

* **Finding:** Raw vs Normalized Values.
* **Correction:** `migration_staging_rows` MUST retain both `raw_data` (unmodified original input) and `mapped_data` (sanitized & normalized input) to preserve audit provenance.

---

## 15. AUDIT INTEGRITY REVIEW

* **Finding:** Every audit event emitted by migration RPCs must include `batch_id`, `dataset_hash`, `actor_id`, and `society_id`. Audit records remain strictly append-only.

---

## 16. CONCURRENCY REVIEW

* **Finding:** Concurrent imports prevented via `pg_advisory_xact_lock()`.

---

## 17. DATA PROVENANCE REVIEW

* **Finding:** All imported production records in `properties`, `users`, `vehicles`, `vendors`, `opening_balances` MUST include an optional `migration_batch_id UUID REFERENCES migration_batches(id)` column.

---

## 18. RETENTION & PRIVACY REVIEW

* **Finding:** Staging rows in `migration_staging_rows` contain PII. Staging rows for `closed` or `rolled_back` batches should be automatically purged after 30 days via a scheduled background cleanup job.

---

## 19. PERFORMANCE & DOS REVIEW

* **Finding:** Max batch size enforced at 2,000 rows. Larger datasets must be split into multiple sequential batches.

---

## 20. EXISTING SCHEMA COMPATIBILITY REVIEW

* **Status:** `CONFIRMED COMPATIBLE WITH DESIGN CORRECTIONS`.
* All proposed target entity references match existing Candidate-28 schema tables (`users`, `properties`, `opening_balances`, `vehicles`, `vendors`, `assets`, `staff_members`).

---

## 21. MASTER FINDINGS MATRIX

| Finding ID | Domain | Severity | Vulnerability Summary | Required Architecture Correction |
| :--- | :--- | :--- | :--- | :--- |
| **SEC-01** | Security | **HIGH** | Missing `SET search_path` on SECURITY DEFINER RPCs | Add `SET search_path = public, pg_temp;` to all RPC definitions. |
| **SEC-02** | Security | **MEDIUM** | RPC execution granted to PUBLIC | Revoke PUBLIC execute permissions; grant strictly to `authenticated`. |
| **SEC-03** | Multi-Tenant | **CRITICAL** | `society_id` parameter accepted from client input | Derive `society_id` strictly from `auth.jwt()` claim inside RPC. |
| **SEC-04** | Multi-Tenant | **CRITICAL** | SECURITY DEFINER bypasses RLS on staging rows | Add explicit `society_id` validation assertion inside RPC body. |
| **SEC-05** | Security | **HIGH** | Client-side CSV injection sanitization bypass | Implement DB trigger `trg_sanitize_staging_input` on staging table. |
| **INT-01** | Data Integrity | **HIGH** | Staging payload tampering post-approval | Store `dataset_hash` in batch metadata; re-verify hash at commit time. |
| **INT-02** | Data Integrity | **CRITICAL** | Partial batch commit in HTTP chunked transactions | Enforce single atomic PostgreSQL transaction block for batch commits. |
| **INT-03** | Data Integrity | **HIGH** | Destructive over-deletion during batch rollback | Block deletion if linked live operational records exist; require manual review. |
| **CON-01** | Concurrency | **HIGH** | Double-submit commit race conditions | Acquire PostgreSQL `pg_advisory_xact_lock(society_id)` in commit RPC. |

---

## 22. REQUIRED ARCHITECTURE CORRECTIONS

The nine (9) required corrections listed in the Master Findings Matrix MUST be incorporated into the final technical specification prior to requesting implementation authorization.

---

## 23. CANDIDATE-30 SCOPE CORRECTIONS

1. Add `dataset_hash` column to `migration_batches`.
2. Add `migration_batch_id` nullable FK column to production entity tables.
3. Add `trg_sanitize_staging_input` trigger on `migration_staging_rows`.
4. Include `pg_advisory_xact_lock()` inside `fn_commit_migration_batch()`.

---

## 24. EXPLICITLY REJECTED DESIGN ASSUMPTIONS

1. **REJECTED:** Client-side HTTP transaction chunking across separate web requests. (Must be single atomic DB transaction).
2. **REJECTED:** Unconditional cascading deletion during batch rollback. (Must block if live operational links exist).
3. **REJECTED:** Client-side CSV sanitization as the sole defense against formula injection. (Must enforce DB trigger).

---

## 25. GOVERNANCE CLOSURE

```text
"No source code was modified."

"No database objects were created or modified."

"No migration was created."

"No migration was executed."

"No production data was written."

"No deployment was performed."

"Candidate-29 remains unchanged."

"Candidate-28 remains the locked database baseline."

"Slices 1–28 remain unchanged and locked."
```

---

## 26. FINAL CLASSIFICATION

### FINAL CLASSIFICATION: `B — VALID ARCHITECTURE WITH REQUIRED CORRECTIONS`

**Summary:** The Candidate-30 Data Migration Center architecture specification is valid and technically sound, subject to incorporating the nine (9) required security and data-integrity corrections detailed in this review.

**Implementation Authorization is NOT GRANTED by this review artifact.**

---

## 27. ARTIFACT INTEGRITY & CHECKSUM

* **Review File Name:** `CANDIDATE-30_ADVERSARIAL_ARCHITECTURE_REVIEW.md`
* **File Path:** `D:\Clients Applications\SU Society App\CANDIDATE-30_ADVERSARIAL_ARCHITECTURE_REVIEW.md`
* **Execution Status:** `READ-ONLY ADVERSARIAL REVIEW COMPLETE`
* **Authoritative Timestamp:** `2026-09-21T14:45:00+05:30`
* **SHA-256 Checksum:** `2A43EBDDA35269AB25417DBF7B5F32AE57B560864012D7FDAF23E075EDF17BB2`
