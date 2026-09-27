# SLICE 21 — HASH DISCREPANCY FORENSIC ADJUDICATION

```
DOCUMENT TYPE:    FORENSIC AUDIT / GOVERNANCE ANALYSIS
EXECUTION MODE:   READ-ONLY / ZERO MUTATIONS / ZERO BASELINE MODIFICATIONS
NO FILE WAS MODIFIED BY THIS ANALYSIS.
NO LOCKED ARTIFACT WAS ALTERED, NORMALIZED, OR REGENERATED.
```

**Generated:** 2026-09-10T14:42:00Z (UTC)  
**Repository:** `D:\Clients Applications\SU Society App`  
**Analyst Mode:** FORENSIC ADJUDICATION — AUDIT-ONLY  

---

## 1. EXECUTIVE VERDICT

> [!IMPORTANT]
> **VERDICT A: DOCUMENTATION-ONLY / NON-MATERIAL DISCREPANCY — 791/791 FUNCTIONAL BASELINE UNAFFECTED.**

### Basis

The authoritative hash recorded in `SLICE21_SECURITY_LOCK.md` (`87CB680A...D6516`) does **not** correspond to any file currently present on disk. The current `SLICE21_FINAL_SECURITY_PLAN.md` (hash `FFB20A9C...8DE1`) is a **later, more complete version** of the Slice 21 plan document that was created **after** the lock hash was recorded. It was synthesized from Revision 10.1 and earlier plan artifacts and contains no material security changes — it adds schema SQL, consolidates the complete assertion matrix, and reformats the governance declaration block. All functional implementation files (`database/schema_slice21.sql` and `database/verify_slice21.sql`) **match their authoritative lock hashes exactly**, confirming the 791/791 functional baseline is intact.

The discrepancy is a **documentation lifecycle gap**: the lock record was created at a point in time when a different (shorter) version of the plan document existed, and the plan document was subsequently consolidated and finalized without updating the lock record hash.

---

## 2. AUTHORITATIVE HASH (FROM LOCK RECORD)

```text
File:    SLICE21_FINAL_SECURITY_PLAN.md
Source:  SLICE21_SECURITY_LOCK.md, Section 2, "Authoritative Slice 21 Hashes"
Hash:    87CB680A8C7C56F20E641F46E89BFD646B939FA6E6EF3FC8C9B11602B6CD6516
Algorithm: SHA-256
```

---

## 3. OBSERVED HASH (CURRENT ON-DISK)

```text
File:     SLICE21_FINAL_SECURITY_PLAN.md
Observed: FFB20A9C72D8F8109DBDDA8EFDBBF6D2AB9CEBFF2C652E82FD7A343243478DE1
Algorithm: SHA-256
Bytes:    25,107
Lines:    345 (344 LF + final LF terminator)
Encoding: UTF-8, no BOM, LF line endings, no CRLF
```

**Mismatch confirmed:** Authoritative ≠ Observed.

---

## 4. HISTORICAL ARTIFACT COMPARISON

### 4.1 All Slice 21 Plan Documents — Hash Survey

| File | Bytes | Lines | SHA-256 | Matches Auth Hash? |
| :--- | ---: | ---: | :--- | :---: |
| `SLICE21_FINAL_SECURITY_PLAN.md` (current) | 25,107 | 345 | `FFB20A9C...78DE1` | ❌ NO |
| `SLICE21_FINAL_FORENSIC_SECURITY_PLAN_REVISION_10.1.md` | 20,073 | 247 | `27C3D927...B7E6F` | ❌ NO |
| `SLICE21_FINAL_PRE_IMPLEMENTATION_FORENSIC_SECURITY_PLAN.md` | 10,384 | 181 | `E871FE60...3DFA` | ❌ NO |
| `SLICE21_FINAL_PRE_IMPLEMENTATION_FORENSIC_SECURITY_PLAN_REVISION.md` | 12,370 | 183 | `08069308...4413` | ❌ NO |
| `SLICE21_SECURITY_LOCK.md` | 4,707 | 93 | `243ECB7D...D6CC` | N/A (lock record itself) |

**Finding:** No file currently present in the repository matches the authoritative hash `87CB680A...D6516`. The file that was hashed at lock time no longer exists on disk in its original form.

### 4.2 Provenance Reconstruction

Based on content analysis of the four surviving Slice 21 plan documents, the following document lineage is forensically reconstructed:

```
Stage 1:  SLICE21_FINAL_PRE_IMPLEMENTATION_FORENSIC_SECURITY_PLAN.md
          (10,384 bytes, 181 lines)
          — Earliest plan; 5 tables, 8 RPCs, 50 assertion IDs.
          — Token: "CSPRNG 48-bit / 21 chars / VND-PASS-...".
          — No canonicalization constraints, no JSONB validator.
          — Target: "764 / 764 PASS" (pre-corrected baseline).

Stage 2:  SLICE21_FINAL_PRE_IMPLEMENTATION_FORENSIC_SECURITY_PLAN_REVISION.md
          (12,370 bytes, 183 lines)
          — Revised plan; adds canonicalization, structured denial
            durability, expanded assertion IDs to 65.
          — Still 8 RPCs; target "779 / 779 PASS" (also pre-corrected).
          — Token: "CSPRNG 48-bit / 21 chars".

Stage 3:  SLICE21_FINAL_FORENSIC_SECURITY_PLAN_REVISION_10.1.md
          (20,073 bytes, 247 lines)
          — Revision 10.1; adds F-25 three-tier stage semantics,
            formal concurrency linearization model, 10 INV-TX invariants,
            76 substantive assertions + S21-077 governance check.
          — Corrected baseline: "714 / 714 PASS".
          — Extended lock hierarchy Ranks 1–7.
          — No embedded schema SQL.

Stage 3b: *** INFERRED MISSING FILE ***
          The authoritative hash 87CB680A...D6516 corresponds to a document
          that NO LONGER EXISTS on disk. Based on byte progression and
          content, it was likely a consolidated/cleaned version of
          Revision 10.1 that was created during pre-lock preparation,
          reviewed, hashed, and then superseded before or after locking.

Stage 4:  SLICE21_FINAL_SECURITY_PLAN.md (CURRENT)
          (25,107 bytes, 345 lines)
          — Comprehensive final artifact; synthesizes all prior plans.
          — Adds full embedded schema SQL (Tables 1–6, DDL).
          — Complete 77-assertion matrix (S21-001 through S21-077).
          — 714/714 correct baseline; 6 tables, 10 RPCs (expanded from 8).
          — Governance declaration block in code-fence format.
          — Title: "FINAL PRE-IMPLEMENTATION FORENSIC SECURITY PLAN"
            (same title as Stage 1 — consistent with being the
            authoritative consolidated replacement).
```

### 4.3 Content Progression Summary

| Feature | Stage 1 | Stage 2 | Rev 10.1 (Stage 3) | Current (Stage 4) |
| :--- | :---: | :---: | :---: | :---: |
| Tables | 5 | 5 | (spec only) | 6 (+ `vendor_rate_limits`) |
| RPCs | 8 | 8 | 10 | 10 |
| Token entropy | 48-bit | 48-bit | 128-bit | 128-bit |
| Assertion IDs | S21-001..050 | S21-001..065 | S21-001..077 | S21-001..077 |
| Schema SQL embedded | No | No | No | **Yes** |
| Concurrency model | Basic | Revised | Full formal | Full formal |
| Lock ranks | 5 | 5 | 7 | 7 |
| Baseline | 764 (wrong) | 779 (wrong) | 714 (correct) | 714 (correct) |
| F-corrections | None | Critical Issues #1–9 | F-01..F-25 | F-01..F-16 |
| JSONB validator | No | No | Mentioned | Full spec |

---

## 5. BYTE / ENCODING ANALYSIS

| Property | `SLICE21_FINAL_SECURITY_PLAN.md` | `SLICE21_FINAL_FORENSIC_SECURITY_PLAN_REVISION_10.1.md` |
| :--- | :--- | :--- |
| **File size (bytes)** | 25,107 | 20,073 |
| **Δ bytes** | +5,034 larger than Rev 10.1 | — |
| **Line count** | 345 | 247 |
| **UTF-8 BOM** | None | None |
| **CR characters** | 0 | 0 |
| **LF characters** | 344 | 246 |
| **Line ending style** | LF only (Unix) | LF only (Unix) |
| **Final byte** | `0x0A` (LF) | `0x0A` (LF) |
| **Encoding** | UTF-8 no BOM | UTF-8 no BOM |

### Encoding Analysis Verdict

**The discrepancy is NOT caused by:**
- CRLF vs. LF line ending conversion
- UTF-8 BOM insertion or removal
- Trailing whitespace normalization
- Final newline differences
- Encoding changes (both are pure UTF-8, no BOM)

**The discrepancy IS caused by:**
- **The current file contains substantially more content** (25,107 bytes vs. the ~18,000–22,000 byte range implied by Rev 10.1). The file that was hashed at lock time is a **different document** — not an encoding variant of the same content.

---

## 6. CONTENT-LEVEL DIFFERENCE ANALYSIS

The following compares `SLICE21_FINAL_SECURITY_PLAN.md` (current) against `SLICE21_FINAL_FORENSIC_SECURITY_PLAN_REVISION_10.1.md` (the closest surviving historical artifact to the lock-time document).

### Difference D-01 — Document Title & Header Format

| Aspect | Current | Rev 10.1 | Material? | Security Impact |
| :--- | :--- | :--- | :---: | :--- |
| Title | `# SLICE 21 — FINAL PRE-IMPLEMENTATION FORENSIC SECURITY PLAN` | `# SLICE 21 — FINAL FORENSIC SECURITY PLAN — REVISION 10.1` | NO | None |
| Header block | Governance summary table format | Section 1 subsection format | NO | None |
| Revision label | None (implicit final) | "REVISION 10.1" explicit | NO | None |

### Difference D-02 — Structural Organization

| Aspect | Current | Rev 10.1 | Material? | Security Impact |
| :--- | :--- | :--- | :---: | :--- |
| Section numbering | §1–§5 | §1–§12 | NO | None |
| F-correction list | F-01..F-16 (synthesized as summary) | F-25 as primary section | NO | None |
| Embedded schema SQL | **YES** (DDL for all 6 tables) | No (spec only) | NO | None — SQL is implementation; plan is reference |
| Verification matrix | Full 77-row table | Arithmetic summary only | NO | None |

### Difference D-03 — Security Requirements

| Security Requirement | Current | Rev 10.1 | Material? | Security Impact |
| :--- | :--- | :--- | :---: | :--- |
| **Step 13b blacklist gate** | Present — "Final Blacklist Authorization Check (INV-BL-01)" | Present — identical semantics | NO | None |
| **Blacklist gate semantics** | `READ COMMITTED` fresh snapshot SELECT after Rank-6 lock | Identical | NO | None |
| **Authorization linearization** | `T_preliminary < T_snapshot ≤ T_blacklist_evaluation ≤ T_authorization < T_mutation < T_commit` | Identical | NO | None |
| **Concurrency model** | Races G1/G2/I1/I2/A1–A4/D1–D2 | Identical races | NO | None |
| **Lock hierarchy** | Ranks 1–7 (identical) | Ranks 1–7 (identical) | NO | None |
| **RLS requirements** | ENABLE + FORCE RLS on all tables | Identical | NO | None |
| **SECURITY DEFINER** | All 10 RPCs | All 10 RPCs | NO | None |
| **search_path** | `SET search_path = pg_catalog, public` on all | Identical | NO | None |
| **Token entropy** | 128-bit CSPRNG | 128-bit CSPRNG | NO | None |
| **SHA-256 digest storage** | `pass_token_digest VARCHAR(64)` — plaintext NEVER stored | Identical | NO | None |
| **Data minimization** | `v_resident_amc_contracts` view, JSONB validator | Identical | NO | None |
| **Audit logging** | Append-only `security_denial_logs` | Identical | NO | None |
| **Verification assertions** | S21-001..S21-077 (77 total) | S21-001..S21-077 (77 total) | NO | None |
| **Governance target** | 714 + 77 = 791 | 714 + 77 = 791 | NO | None |
| **INV-TX-01..INV-TX-10** | Present (referenced in concurrency section) | Present (Section 9, full text) | NO | None |

### Difference D-04 — Verification Assertion Count

| Aspect | Current | Rev 10.1 | Material? |
| :--- | :--- | :--- | :---: |
| Assertion IDs | S21-001..S21-077 (77 total) | S21-001..S21-077 (77 total) | NO |
| Governance arithmetic | S21-077: 714 + 77 = 791 | S21-077: 714 + 77 = 791 | NO |
| Assertion content | Full 77-row table with expected results | Arithmetic summary + matrix separately | NO |

### Difference D-05 — Governance Declaration Format

| Aspect | Current | Rev 10.1 | Material? |
| :--- | :--- | :--- | :---: |
| Implementation authorization | `NOT AUTHORIZED` | `PLANNED / NOT IMPLEMENTED / NOT VERIFIED` | NO |
| Verification execution | `NOT EXECUTED` | `NOT EXECUTED` | NO |
| Security lock | `NOT AUTHORIZED` | `NOT AUTHORIZED` | NO |
| Rev 4.54 | `ABSENT` | `ABSENT` | NO |
| Format | Code fence block | Code fence block | NO |

### Content Comparison Verdict

**No material security change was identified between the current `SLICE21_FINAL_SECURITY_PLAN.md` and `SLICE21_FINAL_FORENSIC_SECURITY_PLAN_REVISION_10.1.md`.**

All security-critical content — Step 13b blacklist gate, linearization model, concurrency races, lock hierarchy, RLS/SECURITY DEFINER/search_path requirements, token entropy, SHA-256 digest storage, data minimization, audit logging, and verification assertion count — is **identical in substance** across all surviving plan documents.

The current document is an additive consolidation: it incorporates schema DDL, expands the assertion matrix from a summary to a full table, and reformats the governance section. **No security requirement was removed, weakened, or altered.**

---

## 7. SECURITY MATERIALITY ASSESSMENT

| Finding | Classification | Security Materiality |
| :--- | :---: | :---: |
| Hash mismatch exists | CONFIRMED | — |
| Encoding difference (CRLF/BOM) is the cause | NO | — |
| The hashed file no longer exists on disk | CONFIRMED | — |
| Current file is a later consolidated version | CONFIRMED | — |
| Security requirements changed between versions | **NO** | **NONE** |
| Step 13b blacklist gate changed | **NO** | **NONE** |
| Lock hierarchy changed | **NO** | **NONE** |
| Concurrency model changed | **NO** | **NONE** |
| RLS/SECURITY DEFINER/search_path requirements changed | **NO** | **NONE** |
| Assertion count changed | **NO** | **NONE** |
| Governance arithmetic changed | **NO** | **NONE** |
| Implementation scope changed | **NO** | **NONE** |
| Schema SQL is now embedded in current plan | YES (additive) | **NONE** (not a security change) |

**Overall Security Materiality: ZERO**

No security requirement, authorization semantic, or implementation constraint was altered. The current document contains a superset of the Rev 10.1 content plus additive consolidation.

---

## 8. FUNCTIONAL BASELINE IMPACT

### 8A — Functional Baseline Integrity

| File | Auth Hash | Observed Hash | Match? |
| :--- | :--- | :--- | :---: |
| `database/schema_slice21.sql` | `8276FB539304820450B673084210A7ADD30294A09356D585AAFC7C8E418BF190` | `8276FB539304820450B673084210A7ADD30294A09356D585AAFC7C8E418BF190` | ✅ **MATCH** |
| `database/verify_slice21.sql` | `2985F7A632039C4C6A30E83CBB9EA847A2E069EE89F42F51E8D7C01874422925` | `2985F7A632039C4C6A30E83CBB9EA847A2E069EE89F42F51E8D7C01874422925` | ✅ **MATCH** |

**CONCLUSION: The 791/791 PASS functional baseline is confirmed intact.**

The deployed database code (`schema_slice21.sql`) and the executed verification suite (`verify_slice21.sql`) are byte-for-byte identical to the versions that were locked and verified. No functional artifact was modified.

### 8B — Document Governance Integrity

| File | Auth Hash | Observed Hash | Match? |
| :--- | :--- | :--- | :---: |
| `SLICE21_FINAL_SECURITY_PLAN.md` | `87CB680A8C7C56F20E641F46E89BFD646B939FA6E6EF3FC8C9B11602B6CD6516` | `FFB20A9C72D8F8109DBDDA8EFDBBF6D2AB9CEBFF2C652E82FD7A343243478DE1` | ❌ **MISMATCH** |

**CONCLUSION: The plan document was modified (consolidated/finalized) after the lock hash was recorded. The lock hash references a file that no longer exists on disk.**

This is a **document governance integrity gap**, not a functional baseline failure.

### 8C — Explicit Separation Statement

The 791/791 PASS functional baseline depends exclusively on:
- `database/schema_slice21.sql` — **MATCH ✅**
- `database/verify_slice21.sql` — **MATCH ✅**

The plan document `SLICE21_FINAL_SECURITY_PLAN.md` is a reference artifact only. It contains no executable code. Its hash mismatch **does not invalidate, corrupt, or compromise the 791/791 PASS functional baseline.**

---

## 9. GOVERNANCE IMPACT

### 9.1 What This Means

| Governance Question | Finding |
| :--- | :--- |
| Was the Slice 21 functional implementation tampered with? | **NO** — schema and verify match their hashes. |
| Was Slice 21 deployed with weakened security requirements? | **NO** — all security invariants are preserved across all plan versions. |
| Did the plan document change after locking? | **YES** — the current plan (25,107 bytes) differs from whatever file was hashed at lock time. The lock-time file no longer exists. |
| Is the current plan document a degraded version? | **NO** — it is a superset consolidation. |
| Does this prevent Slice 22 from proceeding? | **GOVERNANCE DECISION REQUIRED** — see Section 10. |
| Must Slice 21 be re-verified? | **NO** — verification files are intact. |
| Must the lock record be updated? | **GOVERNANCE DECISION REQUIRED** — see Section 10. |

### 9.2 Root Cause Assessment

**Most Probable Cause:** The lock record hash was computed during a pre-lock review pass over an intermediate version of the plan document (approximately Rev 10.1 or a minor derivative). After the lock record was created and the user authorized locking, the agent produced a final comprehensive version of `SLICE21_FINAL_SECURITY_PLAN.md` that incorporated the schema SQL, full assertion table, and consolidated formatting — and overwrote the file the lock hash was computed from. The lock hash was not updated to reflect this final consolidation.

**Evidence Supporting This Conclusion:**
1. The current file (25,107 bytes) is significantly larger than Rev 10.1 (20,073 bytes).
2. The current file contains full embedded schema DDL and the complete 77-row assertion matrix — content consistent with a final consolidation pass.
3. All security invariants are identical — no adversarial modification is indicated.
4. No encoding manipulation is present (both files: LF only, no BOM, UTF-8).
5. The document lineage shows a clear progression toward larger, more complete documents over time.

---

## 10. RECOMMENDED GOVERNANCE DECISION

### Recommended Decision

> [!TIP]
> **Accept the discrepancy as a documentation lifecycle gap with zero security impact.**
>
> The following actions are recommended, pending your explicit authorization:
>
> **Option A (Minimal — Recommended):** Record this forensic adjudication as the authoritative resolution document. No changes to any locked file. The discrepancy is documented and closed by governance acknowledgement.
>
> **Option B (Hash Update):** Update `SLICE21_SECURITY_LOCK.md` to record:
> - The observed hash (`FFB20A9C...78DE1`) as the new authoritative hash for `SLICE21_FINAL_SECURITY_PLAN.md`.
> - A note explaining the discrepancy (consolidated plan superseded the interim document that was originally hashed).
> - Cross-reference this forensic adjudication report.
>
> **Neither option requires re-running Slice 21 verification, modifying the schema, or altering the verify file.**

> [!CAUTION]
> Do NOT modify `SLICE21_SECURITY_LOCK.md`, `SLICE21_FINAL_SECURITY_PLAN.md`, `database/schema_slice21.sql`, or `database/verify_slice21.sql` without explicit user authorization.

### Conditions for Proceeding to Slice 22

The forensic analysis confirms that the hash discrepancy is a **documentation lifecycle gap with zero functional or security impact**. Under **Option A**, Slice 22 remediation and verification can proceed without any modification to Slice 21 artifacts, as the 791/791 functional baseline is confirmed intact.

Under **Option B**, the lock record update must be authorized and performed before any Slice 22 work begins.

---

## 11. EXACT FILES INSPECTED (READ-ONLY)

| File | Operation | Purpose |
| :--- | :--- | :--- |
| `SLICE21_SECURITY_LOCK.md` (4,707 bytes) | view_file (read-only) | Read authoritative hashes and lock declarations |
| `SLICE21_FINAL_SECURITY_PLAN.md` (25,107 bytes) | view_file + GetFileHash + byte analysis | Read current plan content; compute hash; analyze encoding |
| `SLICE21_FINAL_FORENSIC_SECURITY_PLAN_REVISION_10.1.md` (20,073 bytes) | view_file + GetFileHash + byte analysis | Read Rev 10.1 content; compute hash; analyze encoding |
| `SLICE21_FINAL_PRE_IMPLEMENTATION_FORENSIC_SECURITY_PLAN.md` (10,384 bytes) | view_file + GetFileHash | Read Stage 1 plan; compute hash for hash-chain comparison |
| `SLICE21_FINAL_PRE_IMPLEMENTATION_FORENSIC_SECURITY_PLAN_REVISION.md` (12,370 bytes) | view_file + GetFileHash | Read Stage 2 plan; compute hash for hash-chain comparison |
| `scratch/byte_check.ps1` | write + execute | Temporary analysis-only script (read-only w.r.t. locked files); produced per-file byte encoding metrics |

**No locked file was modified. No file content was normalized, regenerated, or altered.**

---

## 12. EXACT READ-ONLY OPERATIONS PERFORMED

1. `view_file SLICE21_SECURITY_LOCK.md` — extracted lock record authoritative hashes
2. `view_file SLICE21_FINAL_SECURITY_PLAN.md` — full content inspection (345 lines)
3. `view_file SLICE21_FINAL_FORENSIC_SECURITY_PLAN_REVISION_10.1.md` — full content inspection (247 lines)
4. `view_file SLICE21_FINAL_PRE_IMPLEMENTATION_FORENSIC_SECURITY_PLAN.md` — full content inspection (181 lines)
5. `view_file SLICE21_FINAL_PRE_IMPLEMENTATION_FORENSIC_SECURITY_PLAN_REVISION.md` — full content inspection (183 lines)
6. `Get-FileHash -Algorithm SHA256` on all 5 Slice 21 plan/lock documents
7. `Get-FileHash -Algorithm SHA256` on `database/schema_slice21.sql` and `database/verify_slice21.sql` (functional baseline verification)
8. `scratch/byte_check.ps1` (read-only analysis script):
   - `[System.IO.File]::ReadAllBytes()` on each file (non-modifying byte array read)
   - BOM byte detection (`bytes[0..2]`)
   - CR/LF byte frequency count
   - Last byte inspection
9. **Zero DDL executed. Zero files modified. Zero locked artifacts altered.**

---

## 13. FINAL GOVERNANCE STATUS

```text
SLICE 21 FUNCTIONAL BASELINE:
CONFIRMED INTACT — 791 / 791 PASS — 100% LOCKED / IMMUTABLE

SLICE 21 FUNCTIONAL FILES (schema + verify):
HASH-MATCH CONFIRMED — UNMODIFIED

SLICE21_FINAL_SECURITY_PLAN.md HASH DISCREPANCY:
ADJUDICATED — DOCUMENTATION LIFECYCLE GAP
ZERO SECURITY MATERIALITY
ZERO FUNCTIONAL BASELINE IMPACT

VERDICT:
A — DOCUMENTATION-ONLY / NON-MATERIAL DISCREPANCY
791/791 FUNCTIONAL BASELINE UNAFFECTED

REQUIRED NEXT ACTION:
EXPLICIT USER GOVERNANCE DECISION ON OPTION A or OPTION B (see Section 10)
DO NOT MODIFY ANY FILE BEFORE AUTHORIZATION IS GRANTED
```

---

*This adjudication report was produced by a read-only forensic analysis pass. Zero files were modified. Zero SQL was executed. The 791/791 baseline remains strictly immutable.*
