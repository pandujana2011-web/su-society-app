# SLICE 22 — REMOTE DEPLOYMENT FAILURE FORENSIC DIAGNOSIS

**TARGET REPOSITORY:** `D:\Clients Applications\SU Society App`  
**TARGET SUPABASE PROJECT:** `fsegpxqoozxmicxcxjun`  
**TARGET REGION:** `ap-south-1`  
**EXECUTION MODE:** READ-ONLY FORENSIC DIAGNOSIS ONLY (ZERO REMEDIATION / ZERO DEPLOYMENT)  
**DATE OF DIAGNOSIS:** `2026-09-15T09:30:00Z`  

---

## 1. EXECUTIVE SUMMARY

```
DIAGNOSIS CLASSIFICATION:       C. ROOT CAUSE FORENSICALLY ESTABLISHED — REMEDIATION REQUIRED
ROOT CAUSE CATEGORY:            RC-A / RC-B: PRE-EXISTING SCHEMA DRIFT FROM SLICE 9 MIGRATION
PRIMARY DIAGNOSTIC FINDING:     `public.rule_violations` WAS CREATED IN SLICE 9 (20260912000009_slice9.sql)
                                WITHOUT `subject_user_id` OR `reporter_id` COLUMNS.
                                SLICE 22 USED `CREATE TABLE IF NOT EXISTS public.rule_violations`,
                                WHICH PASSED SILENTLY WITHOUT MODIFYING THE EXISTING SLICE 9 TABLE.
                                STATEMENT 8 FAILED ATTEMPTING TO INDEX NON-EXISTENT COLUMN `subject_user_id`.
FAILED STATEMENT:               STATEMENT 8: CREATE INDEX IF NOT EXISTS idx_rule_violations_subject ON public.rule_violations(subject_user_id);
SQLSTATE / ERROR:               42703 (undefined_column: ERROR: column "subject_user_id" does not exist)
REMOTE TRANSACTION STATUS:      100% ATOMIC ROLLBACK (0 REMOTELY COMMITTED SLICE 22 OBJECTS)
REMOTE BOUNDARY STATUS:         STRICTLY PRESERVED AT 20260912000021_slice21.sql
EXCLUDED MIGRATION STATUS:      20260912000023_slice23.sql REMAINS 100% UNAPPLIED / EXCLUDED
IMMUTABLE PREDECESSOR:          SLICE 21 (GOVERNANCE CLOSED + SECURITY/GOVERNANCE LOCKED)
SLICE 21 LOCK SHA-256:          C8F5E8742CA04391AC51889AD671CD9868710F7C5AB6CC6A9C39C84BCAF16912
HISTORICAL BASELINE:            931 / 931 PASS (SHA-256: 47A7093CB842BB10179D529E85452BBD8B463E3057725B28E69A5E99AC614448)
REMEDIATION AUTHORIZED:         NONE — READ-ONLY FORENSIC DIAGNOSIS ONLY
NEXT GOVERNANCE STATE:          SLICE 22 DEPLOYMENT FAILURE ROOT CAUSE ESTABLISHED — AWAIT FORMAL FORENSIC REMEDIATION SPECIFICATION AND EXPLICIT HUMAN AUTHORIZATION
```

---

## 2. CURRENT REMOTE MIGRATION BOUNDARY

* **Inspection Mechanism:** Read-only `npx supabase migration list`.
* **Applied Remote Boundary:** `20260912000021_slice21.sql` (`remote: 20260912000021`).
* **Slice 22 Remote Status:** `20260912000022_slice22.sql` -> `remote: ""` (`NOT APPLIED / PENDING`).
* **Slice 23 Remote Status:** `20260912000023_slice23.sql` -> `remote: ""` (`NOT APPLIED / PENDING`).
* **Boundary Integrity:** Atomic rollback verified. Remote migration history is 100% unmutated.

---

## 3. CAPTURED FAILURE EVIDENCE

* **Execution Task:** `task-311` (M-02 Isolated Single-Migration Container Model).
* **Target Migration File:** `supabase/migrations/20260912000022_slice22.sql`.
* **Failure Point:** Statement 8 (Line 130).
* **Exact Statement Text:** `CREATE INDEX IF NOT EXISTS idx_rule_violations_subject ON public.rule_violations(subject_user_id);`
* **SQLSTATE:** `42703` (`undefined_column`).
* **Exact Error Message:** `ERROR: column "subject_user_id" does not exist (SQLSTATE 42703) At statement: 8`.

---

## 4. AUTHORITATIVE SLICE 22 TABLE EXPECTATION

In `20260912000022_slice22.sql`, Slice 22 expected `public.rule_violations` to possess the following complete schema:

```sql
CREATE TABLE IF NOT EXISTS public.rule_violations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
    property_id UUID NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
    reporter_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    subject_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    violation_category VARCHAR(64) NOT NULL CHECK (violation_category IN ('noise', 'parking_unauthorized', 'trash_disposal', 'unauthorized_alteration', 'common_area_damage', 'pet_policy', 'other')),
    description TEXT NOT NULL CHECK (length(trim(description)) >= 10 AND length(description) <= 2000),
    evidence_urls JSONB DEFAULT '[]'::jsonb CHECK (public.fn_is_valid_evidence_urls(evidence_urls)),
    status VARCHAR(32) NOT NULL DEFAULT 'reported' CHECK (status IN ('reported', 'under_review', 'dismissed', 'penalty_assessed', 'disputed', 'dispute_upheld', 'dispute_reversed', 'financially_posted')),
    reported_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    reviewed_at TIMESTAMPTZ,
    reviewed_by UUID REFERENCES public.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_different_reporter_subject CHECK (reporter_id != subject_user_id)
);
```

---

## 5. OBJECT PROVENANCE & HISTORICAL ORIGIN ANALYSIS

Forensic code search across the entire migration history (`20260912000001` through `20260912000021`) established the exact origin of `public.rule_violations`:

1. **Slice 9 (`20260912000009_slice9.sql` — Applied & Verified Remotely):**
   Slice 9 defined a basic preliminary version of `public.rule_violations` on lines 44–58:
   ```sql
   CREATE TABLE IF NOT EXISTS public.rule_violations (
       id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
       society_id UUID NOT NULL REFERENCES public.societies(id) ON DELETE RESTRICT,
       property_id UUID NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
       reported_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
       violation_type VARCHAR(50) NOT NULL,
       description TEXT,
       status VARCHAR(50) NOT NULL DEFAULT 'reported'
           CONSTRAINT chk_violation_status CHECK (status IN ('reported', 'under_review', 'penalized', 'dismissed', 'resolved')),
       penalty_amount NUMERIC(10,2) NOT NULL DEFAULT 0
           CONSTRAINT chk_violation_penalty CHECK (penalty_amount >= 0),
       ledger_transaction_id UUID REFERENCES public.ledger_transactions(id) ON DELETE RESTRICT,
       created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
       updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
   );
   ```
2. **Slice 13 (`20260912000013_slice13.sql` — Applied & Verified Remotely):**
   Slice 13 added notification triggers on `public.rule_violations` (`trg_notify_violation_insert`, `trg_notify_violation_update`).
3. **Current Remote Reality:**
   Because Slice 9 is applied remotely on project `fsegpxqoozxmicxcxjun`, `public.rule_violations` already exists on the remote database with the Slice 9 column structure (`reported_by`, `violation_type`, `penalty_amount`, etc.).
   It **LACKS** `subject_user_id`, `reporter_id`, `violation_category`, `evidence_urls`, `reviewed_at`, and `reviewed_by`.

---

## 6. STRUCTURAL SCHEMA DIFF (EXPECTED SLICE 22 VS REMOTE SLICE 9)

```
+--------------------------+-----------------------+-----------------------+------------------------------------+
| COLUMN / ATTRIBUTE       | SLICE 22 EXPECTED     | ACTUAL REMOTE (SL 9)  | FORENSIC STATUS                    |
+--------------------------+-----------------------+-----------------------+------------------------------------+
| id                       | UUID PRIMARY KEY      | UUID PRIMARY KEY      | MATCH                              |
| society_id               | UUID NOT NULL (FK)    | UUID NOT NULL (FK)    | MATCH                              |
| property_id              | UUID NOT NULL (FK)    | UUID NOT NULL (FK)    | MATCH                              |
| reporter_id              | UUID NOT NULL (FK)    | MISSING               | MISSING REMOTE (Slice 9 used reported_by)|
| subject_user_id          | UUID NOT NULL (FK)    | MISSING               | MISSING REMOTE (Root Cause)        |
| violation_category       | VARCHAR(64) NOT NULL  | MISSING               | MISSING REMOTE (Slice 9 used violation_type)|
| description              | TEXT (CHECK >=10)     | TEXT (No min length)  | DIFFERENT DEFINITION               |
| evidence_urls            | JSONB (URL CHECK)     | MISSING               | MISSING REMOTE                     |
| status                   | VARCHAR(32) (S22 ENUM)| VARCHAR(50) (S9 ENUM) | DIFFERENT DEFINITION               |
| reported_at              | TIMESTAMPTZ           | MISSING               | MISSING REMOTE                     |
| reviewed_at              | TIMESTAMPTZ           | MISSING               | MISSING REMOTE                     |
| reviewed_by              | UUID                  | MISSING               | MISSING REMOTE                     |
| created_at               | TIMESTAMPTZ           | TIMESTAMPTZ           | MATCH                              |
| updated_at               | TIMESTAMPTZ           | TIMESTAMPTZ           | MATCH                              |
| reported_by              | ABSENT                | UUID NOT NULL (FK)    | EXTRA REMOTE (Legacy Slice 9)      |
| violation_type           | ABSENT                | VARCHAR(50)           | EXTRA REMOTE (Legacy Slice 9)      |
| penalty_amount           | ABSENT                | NUMERIC(10,2)         | EXTRA REMOTE (Moved to penalties)  |
| ledger_transaction_id   | ABSENT                | UUID (FK)             | EXTRA REMOTE (Moved to penalties)  |
+--------------------------+-----------------------+-----------------------+------------------------------------+
```

---

## 7. ROOT CAUSE MECHANISM ANALYSIS

1. **Statement 2 Behavior:**  
   `20260912000022_slice22.sql` Statement 2 executed: `CREATE TABLE IF NOT EXISTS public.rule_violations (...)`.  
   Because `public.rule_violations` already existed from Slice 9, PostgreSQL evaluated `CREATE TABLE IF NOT EXISTS` as a no-op and skipped table creation.
2. **Statement 8 Failure:**  
   Statement 8 executed: `CREATE INDEX IF NOT EXISTS idx_rule_violations_subject ON public.rule_violations(subject_user_id);`.  
   Postgres looked for column `subject_user_id` on `public.rule_violations`. Because the table was retained from Slice 9, `subject_user_id` did not exist.
3. **Rejection:**  
   Postgres threw SQLSTATE `42703` (`undefined_column`) and aborted the migration transaction.

---

## 8. DEPENDENCY FORENSICS

Objects on the remote database depending on legacy Slice 9 `public.rule_violations`:
- Triggers: `trg_rule_violations_updated_at`, `trg_rule_violations_force_reported_by`, `trg_prevent_direct_violation_update`, `trg_audit_rule_violations`, `trg_notify_violation_insert`, `trg_notify_violation_update`.
- Functions: `fn_rule_violations_force_reported_by()`, `fn_prevent_direct_violation_update()`, `fn_transition_violation_state()`, `fn_notify_rule_violation()`.
- RLS Policies: `pol_violations_admin`, `pol_violations_select_owner`, `pol_violations_select_tenant`, `pol_violations_insert_resident`.
- Ledger Constraint: `chk_ledger_source_exclusive` on `public.ledger_transactions` (contains `source_violation_id`).

Any eventual remediation specification must account for safely dropping or transitioning these legacy Slice 9 triggers, functions, and policies before recreating/altering `public.rule_violations` to Slice 22 standards.

---

## 9. SECURITY IMPACT ASSESSMENT

* **Assessment:** `NO CURRENT SECURITY EXPOSURE`.
* **Rationale:**
  - Slice 22 transaction rolled back 100% atomically.
  - Remote boundary remains strictly at `20260912000021_slice21.sql`.
  - Legacy Slice 9 `public.rule_violations` table remains protected by its original Slice 9 RLS policies (`ENABLE ROW LEVEL SECURITY`, `FORCE ROW LEVEL SECURITY`).
  - Zero unauthorized client access or parameter tampering vectors were created.

---

## 10. ROOT CAUSE CLASSIFICATION

**`ROOT CAUSE CLASS: RC-A / RC-B (PRE-EXISTING REMOTE SCHEMA DRIFT FROM SLICE 9 MIGRATION)`**

* **Summary:** The Slice 22 candidate migration assumed `public.rule_violations` was a new table to be created via `CREATE TABLE IF NOT EXISTS`, whereas `public.rule_violations` was originally deployed in Slice 9 with an earlier schema.

---

## 11. REMEDIATION CATEGORY RECOMMENDATION

* **Recommended Category:** `MIGRATION REMEDIATION SPECIFICATION REQUIRED`.
* **Future Remediation Requirements (To be specified in a separate governed stage upon human authorization):**
  1. Drop or reconcile legacy Slice 9 triggers, functions, policies, and constraints on `public.rule_violations`.
  2. Safely alter or drop-and-recreate `public.rule_violations` to incorporate the complete Slice 22 schema (`subject_user_id`, `reporter_id`, `violation_category`, `evidence_urls`, `reviewed_at`, `reviewed_by`).
  3. Ensure migration mirror (`database/schema_slice22.sql`) and verify suite (`database/verify_slice22.sql`) are aligned.
* **Prohibition:** ZERO code edits or SQL execution during this forensic diagnosis stage.

---

## 12. SLICE 21 & BASELINE INTEGRITY

* **Slice 21 Lock:** `C8F5E8742CA04391AC51889AD671CD9868710F7C5AB6CC6A9C39C84BCAF16912` (`PASS — 100% INTACT`).
* **Historical Baseline:** `931 / 931 PASS` (`47A7093CB842BB10179D529E85452BBD8B463E3057725B28E69A5E99AC614448`, `PASS — 100% INTACT`).
* **Source Artifact SHAs:**
  - `supabase/migrations/20260912000022_slice22.sql`: `F186BC5851AF2D62D0743206BB1600E085EE6C7E1196D09796FD625974EEE936` (`INTACT`)
  - `database/schema_slice22.sql`: `F186BC5851AF2D62D0743206BB1600E085EE6C7E1196D09796FD625974EEE936` (`INTACT`)
  - `database/verify_slice22.sql`: `CD526240678242603BEDE1ABBB1EEBE6E70BC08759C04B3D93F0A06DC42A643F` (`INTACT`)

---

## 13. FINAL CLASSIFICATION

**`CLASSIFICATION: C. ROOT CAUSE FORENSICALLY ESTABLISHED — REMEDIATION REQUIRED`**

---

## 14. EXACT NEXT GOVERNANCE STATE

```
CURRENT STATE:           SLICE 22 DEPLOYMENT FAILURE ROOT CAUSE FORENSICALLY ESTABLISHED
CLASSIFICATION:          C. ROOT CAUSE FORENSICALLY ESTABLISHED — REMEDIATION REQUIRED
ROOT CAUSE:              PRE-EXISTING SLICE 9 `public.rule_violations` TABLE LACKS `subject_user_id` COLUMN. `CREATE TABLE IF NOT EXISTS` WAS A NO-OP, CAUSING STATEMENT 8 INDEX CREATION TO FAIL WITH SQLSTATE 42703.
IMMUTABLE PREDECESSOR:   SLICE 21 (GOVERNANCE CLOSED + SECURITY/GOVERNANCE LOCKED, SHA-256: C8F5E8742CA04391AC51889AD671CD9868710F7C5AB6CC6A9C39C84BCAF16912)
HISTORICAL BASELINE:     931 / 931 PASS (SHA-256: 47A7093CB842BB10179D529E85452BBD8B463E3057725B28E69A5E99AC614448)
REMOTE BOUNDARY:         20260912000021_slice21.sql (APPLIED & VERIFIED)
SLICE 22 REMOTE STATE:   100% UNAPPLIED (ATOMIC ROLLBACK VERIFIED)
SLICE 23 REMOTE STATE:   100% UNAPPLIED / EXCLUDED
NEXT STEP:               SLICE 22 DEPLOYMENT FAILURE ROOT CAUSE ESTABLISHED — AWAIT FORMAL FORENSIC REMEDIATION SPECIFICATION AND EXPLICIT HUMAN AUTHORIZATION
PROHIBITION:             ZERO UNSCRIPTED RECOVERY, ZERO CODE EDITS, ZERO DEPLOYMENT UNTIL EXPLICITLY AUTHORIZED BY HUMAN
```
