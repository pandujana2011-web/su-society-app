# SLICE 21 — FINAL FORENSIC SECURITY PLAN — REVISION 10.1

**Target Repository:** `D:\Clients Applications\SU Society App`  
**Document Revision:** FORENSIC AUDIT & STAGE SEMANTICS REVISION 10.1  
**Execution Mode:** PLAN ONLY / ZERO IMPLEMENTATION / ZERO BASELINE MUTATION / ZERO LOCK  
**Verification Check Breakdown:** 76 Substantive Security Assertions + 1 Governance Arithmetic Check (S21-077) = **77 Total Verification Checks** (S21-001 through S21-077)  

---

## 1. EXECUTIVE GOVERNANCE & ABSOLUTE BOUNDARY

### 1.1 Current Project Baseline Status
- **Slices 1–19:** 639 / 639 PASS (LOCKED / IMMUTABLE)
- **Slice 2 Financial Remediation:** 24 / 24 PASS (LOCKED / IMMUTABLE)
- **Slice 20 NOC & Move-Out Management:** 51 / 51 PASS (LOCKED / IMMUTABLE)
- **Current Cumulative Baseline:** **714 / 714 PASS (100% LOCKED)**
- **Slice 20 Lock Rev 4.54:** **ABSENT**

### 1.2 Slice 21 Execution Boundary
- **Implementation Status:** PLANNED / NOT IMPLEMENTED / NOT VERIFIED
- **Verification Execution:** NOT EXECUTED
- **Security Lock Status:** NOT AUTHORIZED
- **Substantive Assertion Count:** 76 Substantive Security Assertions
- **Governance Check Count:** 1 Governance Arithmetic Check (S21-077)
- **Total Verification Checks:** 77 Checks
- **Future Cumulative Target:** **714 + 77 = 791** *(Future Target Only — 0 / 77 Currently Verified)*

---

## 2. IMMUTABLE HISTORICAL AUTHORITY ARTIFACT HASHES

```text
SLICE20_REVISION_4.53_FINAL_FORENSIC_BYTE_SAFE_AUTHORITY_PRESERVATION.md
SHA-256: 99F46FF7C7463E1E594F89C9C7C83FB7A15BEC8E9CBF93B9E7636D517210FE24

SLICE20_REVISION_4.48_BYTE_SAFE_CLEAN_SECURITY_PLAN.md
SHA-256: A54904A4095112698FE5C5103F913C8359924480614AF3195889A2D0E29C499E

Slice 2 remediation plan:
SHA-256: 767656132833CE386FA02BB6F7A5556D62668210AD8E2906886978482230D9E6

Slice 2 schema:
SHA-256: 191AC5353DEED19DBBAB1AFBE1DB2A272C6D45A599760CF707ACE3D5135AFA49

Slice 2 verification:
SHA-256: 66585EB71D36FEBAC59297101598A1D56828C60AFDCDE9AD75C9063C7FF191F8

Governance authorization:
SHA-256: 75BB72D848D841EC41BBB3B83525AD16272774B142A31EA58CD77D5B765A0B2C

Slice 20 schema:
SHA-256: EFA25D7EFC2587A93A3A0DA75661648684BF50581C6C4A942D3F4ECF5A06B6E7

Slice 20 verification:
SHA-256: 39F96A29164FDCC94D14BE356C6887CD23A692B8D657605C354D5C692E47CF71
```

---

## 3. F-25 — THREE-TIER STAGE SEMANTICS & PREDICATE MODEL

The Slice 21 verification and authorization sequence is formally structured into three distinct, non-overlapping tiers:

### 3.1 Tier 1 — Forensic / Preparatory Analysis (Steps 1–10)
Steps 1–10 are forensic and preparatory analysis only. They inspect repository state, inspect SQL/schema/function definitions, identify concurrency-sensitive operations, classify authorization semantics, establish expected outcomes, identify candidate invariants, prepare evidence requirements, perform static reasoning, and identify potential defects.
- **Scope:** Preparatory input parsing and preliminary non-locking snapshot reads (token format, token digest, preliminary pass lookup, preliminary blacklist lookup, preliminary asset inspection, caller authentication, society scope).
- **Non-Authority:** Tier 1 steps do NOT constitute authoritative AMC validation or pass authorization.
- **Step 4 Scoped Rank-2 Lock Exception:** Step 4 explicitly acquires a Rank-2 lock on `vendor_rate_limits` (`FOR UPDATE`) for atomic gatekeeper rate-limit tracking. This lock is strictly scoped to rate-limiting and does NOT imply that Slice 21 is locked or that baseline compliance has been granted.

### 3.2 Tier 2 — Authoritative AMC / Pass Validation (Steps 11–13a)
Steps 11–13a represent the authoritative AMC/pass-validation stage where authoritative resource locks are established:
- **Step 11 (Lock AMC Contract Row - Rank 5 Lock):** Query `amc_vendor_contracts` [Rank 5] by extracted contract ID `v_prelim_amc_id` and acquire `FOR SHARE` lock. Confirm AMC status = `'active'` and current time is within `[contract_start, contract_end_boundary)`.
- **Step 12 (Authoritative Pass Row Lock - Rank 6 Lock):** Query `vendor_access_passes` [Rank 6] by token digest and acquire exclusive row lock via `SELECT FOR UPDATE`.
- **Step 13a (Pass Attribute Revalidation):** Under the Rank 6 `FOR UPDATE` lock, revalidate `society_id`, `amc_contract_id`, `technician_identity_canonical`, `technician_phone_canonical`, status `'issued'`, and validity window.

### 3.3 Tier 3 — Final Blacklist / Decision Gate (Steps 13b & 13c)
- **Step 13b (FINAL BLACKLIST AUTHORIZATION CHECK - INV-BL-01):** Execute a fresh command Ordinary Non-Locking `SELECT` on `security_blacklist_records` [Rank 3] for the locked pass's canonical technician identity and phone. This statement acquires a fresh `READ COMMITTED` command snapshot ($T_{snapshot}$).
- **Step 13c (Final Decision Gate - T_authorization):** The logical decision point reached when Step 13a and Step 13b pass completely. All authorization predicates are linearized at $T_{authorization}$.

---

## 4. FORMAL CONCURRENCY & AUTHORIZATION LINEARIZATION MODEL

### 4.1 Formal Timeline & Linearization Hierarchy
```text
T_preliminary < T_snapshot <= T_blacklist_evaluation <= T_authorization < T_mutation < T_commit
```
1. **T_preliminary (Step 8):** Preliminary non-locking snapshot read of pass attributes by token digest to extract initial data flow.
2. **T_snapshot (Step 13b Start):** The exact instant Step 13b's SQL statement begins execution under the exclusive Rank 6 pass lock (SELECT FOR UPDATE) and acquires its fresh READ COMMITTED command snapshot.
3. **T_blacklist_evaluation (Step 13b Execution):** The execution of the Step 13b ordinary non-locking SELECT on security_blacklist_records [Rank 3] using the snapshot acquired at T_snapshot.
4. **T_authorization (Step 13c):** The logical decision point recorded after Step 13b successfully completes. T_authorization is a logical decision point based on the database state observed at T_snapshot; it is NOT a second snapshot acquisition.
5. **T_mutation (Step 14):** Execution of the atomic pass status update (issued -> used).
6. **T_commit (Step 15 Completion):** Outer framework PostgREST transaction commit upon normal RPC function return.

---

## 5. POSTGRESQL TRANSACTION SEMANTICS & FAILURE MODES

### 5.1 SQL Command Isolation & Statement Snapshots
In Supabase / PostgreSQL RPC execution under standard READ COMMITTED isolation:
- **READ COMMITTED Isolation:** Every SQL statement inside a PL/pgSQL function obtains a fresh command snapshot of all committed database records at statement start.
- **SELECT (Non-Locking):** Ordinary SELECT queries perform snapshot isolation reads and acquire NO row or table locks. The Step 13b SELECT on Rank 3 after Rank 6 is a READ DEPENDENCY ONLY, not a Rank 6 -> Rank 3 lock dependency.
- **SELECT FOR SHARE:** Row-level shared lock (Step 11 on amc_vendor_contracts [Rank 5]) preventing concurrent modification while permitting concurrent reads.
- **SELECT FOR UPDATE:** Row-level exclusive lock (Step 4 on vendor_rate_limits [Rank 2], Step 12 on vendor_access_passes [Rank 6]) serializing concurrent updates.

### 5.2 Framework-Managed RPC Transaction Boundaries & Exception Rollback Matrix
- **RPC Function Boundary:** Individual PL/pgSQL functions do NOT issue transaction-level COMMIT or ROLLBACK commands internally. The function runs inside a database transaction managed by PostgREST.
- **Structured Business Denial Durability:** Security denials insert an audit record into security_denial_logs [Rank 7] and return a structured JSONB response (e.g. jsonb_build_object('success', false, 'reason', 'blacklist_match')). The function completes normally, allowing PostgREST to commit both the denial log entry and the transaction atomically.
- **Exception Rollback Behavior:**
  - *Exception before Step 14:* Transaction aborts; pass status remains issued, no pass redemption occurs.
  - *Exception after Step 14 but before commit:* Transaction aborts; pass status update (issued -> used) rolls back cleanly to issued.
  - *Exception after success audit INSERT but before outer commit:* Transaction aborts; pass status update and success audit record both roll back cleanly.
  - *Note:* Ordinary PostgreSQL transaction rollback also rolls back denial logs if an unhandled exception occurs. Autonomous/out-of-transaction logging is not implemented; denial durability relies on structured normal returns.

---

## 6. F-09 — AUTHORITATIVE SINGLE GLOBAL LOCK HIERARCHY & RPC LOCK TRACES

### 6.1 Authoritative Global Lock Order (Ranked 1..7)
```text
RANK 1 — public.properties / public.societies
RANK 2 — public.vendor_rate_limits
RANK 3 — public.security_blacklist_records
RANK 4 — public.society_assets
RANK 5 — public.amc_vendor_contracts
RANK 6 — public.vendor_access_passes
RANK 7 — public.security_denial_logs
```
Rank order constrains lock acquisition, not ordinary snapshot-read order. The Step 13b ordinary SELECT on Rank 3 after Rank 6 is a read dependency only and introduces zero 6 -> 3 lock dependencies.

### 6.2 Per-RPC Lock Acquisition Traces

1. fn_create_blacklist_entry: Societies [1] (FOR SHARE) -> security_blacklist_records [3] (INSERT Exclusive Lock).
2. fn_deactivate_blacklist_entry: Societies [1] (FOR SHARE) -> security_blacklist_records [3] (SELECT FOR UPDATE).
3. fn_evaluate_access_denial: Societies [1] (FOR SHARE) -> vendor_rate_limits [2] (UPSERT + FOR UPDATE) -> security_blacklist_records [3] (Ordinary Non-Locking SELECT) -> security_denial_logs [7] (INSERT Exclusive Lock).
4. fn_register_society_asset: Societies [1] (FOR SHARE) -> society_assets [4] (INSERT / FOR UPDATE).
5. fn_create_amc_contract: Societies [1] (FOR SHARE) -> society_assets [4] (FOR SHARE) -> amc_vendor_contracts [5] (INSERT Exclusive Lock).
6. fn_terminate_amc_contract: Societies [1] (FOR SHARE) -> amc_vendor_contracts [5] (SELECT FOR UPDATE) -> Trigger trg_amc_shorten_update_passes -> vendor_access_passes [6] (UPDATE Exclusive Lock).
7. fn_issue_vendor_pass: Societies [1] (FOR SHARE) -> society_assets [4] (FOR SHARE) -> amc_vendor_contracts [5] (FOR SHARE) -> vendor_access_passes [6] (INSERT Exclusive Lock).
8. fn_revoke_vendor_pass: Societies [1] (FOR SHARE) -> vendor_access_passes [6] (SELECT FOR UPDATE).
9. fn_verify_vendor_pass: Societies [1] (FOR SHARE) -> vendor_rate_limits [2] (UPSERT + FOR UPDATE) -> security_blacklist_records [3] (Preliminary Non-Locking SELECT) -> society_assets [4] (Non-Locking SELECT) -> amc_vendor_contracts [5] (SELECT FOR SHARE) -> vendor_access_passes [6] (SELECT FOR UPDATE) -> security_blacklist_records [3] (Final Authoritative Non-Locking Re-check) -> security_denial_logs [7] (INSERT Exclusive Lock).
10. process_expired_amc_contracts (Cron Worker): Societies [1] (FOR SHARE) -> amc_vendor_contracts [5] (SELECT FOR UPDATE) -> vendor_access_passes [6] (UPDATE Exclusive Lock).

---

## 7. F-15 — RECONCILED VENDOR PASS VERIFICATION SEQUENCE & TRANSACTION BOUNDARIES

1. Step 1 (Authenticate Caller): Derive v_caller_id := auth.uid(). Rejects unauthenticated callers.
2. Step 2 (Derive Gatekeeper Society Context): Resolve gatekeeper society context v_society_id.
3. Step 3 (Lock Society Scope - Rank 1 Lock): Acquire FOR SHARE lock on societies [Rank 1].
4. Step 4 (Acquire Rate Limit Row Lock - Rank 2 Lock): Execute atomic UPSERT + SELECT FOR UPDATE on vendor_rate_limits [Rank 2].
5. Step 5 (Evaluate Rate Limit Lockout): If lockout_until > NOW(), write denial log [Rank 7 INSERT] and return structured lockout denial JSONB.
6. Step 6 (Validate Token Input Format): Verify 41-char VND-PASS-<32 HEX> format.
7. Step 7 (Compute Token Digest): Compute SHA-256 digest v_pass_digest := extensions.digest(p_raw_token, 'sha256').
8. Step 8 (Preliminary Pass Lookup - Non-Locking Information Read): Execute Ordinary Non-Locking SELECT on vendor_access_passes by v_pass_digest to fetch preliminary values (v_prelim_identity, v_prelim_phone, v_prelim_amc_id, v_prelim_society_id).
9. Step 9 (Preliminary Blacklist Read - Rank 3 Non-Locking Read): Execute Ordinary Non-Locking SELECT on security_blacklist_records [Rank 3] for v_prelim_identity and v_prelim_phone. If match found, log denial [Rank 7] and return structured denial JSONB.
10. Step 10 (Asset Operational Read - Rank 4 Non-Locking Read): Execute Ordinary Non-Locking SELECT on society_assets [Rank 4].
11. Step 11 (Lock AMC Contract Row - Rank 5 Lock): Query amc_vendor_contracts [Rank 5] by v_prelim_amc_id and acquire FOR SHARE lock. Confirm AMC status = 'active' and current time is within [contract_start, contract_end_boundary).
12. Step 12 (Authoritative Pass Row Lock - Rank 6 Lock): Query vendor_access_passes [Rank 6] by v_pass_digest and acquire exclusive row lock via SELECT FOR UPDATE.
13. Step 13a (Pass Attribute Revalidation): Under FOR UPDATE lock [Rank 6], re-validate society_id, amc_contract_id, technician_identity_canonical, technician_phone_canonical, status 'issued', and validity window.
14. Step 13b (FINAL BLACKLIST AUTHORIZATION CHECK - INV-BL-01): Execute a fresh command Ordinary Non-Locking SELECT on security_blacklist_records [Rank 3] for the locked pass's technician identity and phone. If an active match is found, write denial log [Rank 7 INSERT], and return structured blacklist_match denial JSONB.
15. Step 13c (FINAL_AUTHORIZATION_POINT): Logical decision point reached when Step 13a and Step 13b pass completely. All authorization predicates are linearized at T_authorization.
16. Step 14 (Execute Atomic Redemption Update - T_mutation): Update vendor_access_passes [Rank 6] setting status = 'used', redeemed_at = NOW(), redeemed_by_gatekeeper_id = v_caller_id.
17. Step 15 (Persist Log & Complete RPC - T_commit): Execute INSERT into security_denial_logs [Rank 7] recording outcome access_granted, and return structured success JSONB. Outer PostgREST framework commits the transaction atomically upon function return.

---

## 8. REBUILT COMPLETE CONCURRENCY & RACE MATRIX

### 8.1 Pass Revocation Races (G1 & G2)
- **Case G1 (Verification obtains Rank 6 FOR UPDATE lock first):**
  - Verification acquires Rank 6 lock FOR UPDATE -> Revocation attempts Rank 6 lock and waits -> Verification executes Step 13a/13b, updates pass status issued -> used at Step 14, and commits -> Revocation unblocks, reads status = 'used', and rejects revocation. Exactly one terminal transition occurs.
- **Case G2 (Revocation obtains Rank 6 FOR UPDATE lock first):**
  - Revocation acquires Rank 6 lock FOR UPDATE -> Verification attempts Step 12 Rank 6 lock and waits -> Revocation updates pass status issued -> revoked and commits -> Verification unblocks, Step 13a reads status = 'revoked' -> Verification denied.

### 8.2 AMC Termination Races (I1 & I2)
- **Case I1 (Verification obtains AMC FOR SHARE lock [Rank 5] first):**
  - Verification acquires AMC Contract FOR SHARE lock [Rank 5] -> Termination attempts AMC Contract FOR UPDATE lock [Rank 5] and waits -> Verification validates AMC state, acquires Pass lock [Rank 6], completes authorization and commits -> Termination unblocks and modifies AMC row. Current verification is governed by the AMC state observed while holding the Rank 5 lock; termination cannot modify the AMC row until verification releases the lock.
- **Case I2 (Termination obtains AMC FOR UPDATE lock [Rank 5] first):**
  - Termination acquires AMC Contract FOR UPDATE lock [Rank 5] -> Verification attempts Step 11 AMC FOR SHARE lock [Rank 5] and waits -> Termination terminates/shortens AMC and updates passes via trigger -> Termination commits -> Verification unblocks, re-evaluates authoritative AMC/pass state -> Terminated/invalid state causes denial.

### 8.3 Blacklist Activation Races (Cases A1..A4)
- **Case A1 (Activation committed BEFORE T_snapshot):** Activation commits before Step 13b start. Step 13b fresh command snapshot sees active record -> **DENIAL (INV-BL-01)**.
- **Case A2 (Activation commits after T_snapshot but before Step 13b finishes):** Activation commits after Step 13b snapshot start. The activation is ordered after the verification authorization observation at T_snapshot and therefore does not retroactively invalidate that already-linearized authorization -> **ACCESS GRANTED**. (Subsequent verifications observe active record and are denied).
- **Case A3 (Activation commits after Step 13b finishes but before Step 14):** Linearizes after T_authorization -> **ACCESS GRANTED**.
- **Case A4 (Activation commits after Step 14 begins):** Linearizes after T_authorization -> **ACCESS GRANTED**.

### 8.4 Blacklist Deactivation Races
- **Deactivation committed BEFORE T_snapshot:** Step 13b fresh command snapshot sees deactivated state -> Verification proceeds if all other predicates pass.
- **Deactivation committed AFTER T_snapshot:** The active blacklist state observed at T_snapshot remains authoritative for this verification attempt -> Verification denies.

---

## 9. TEN TRANSACTION & LINEARIZATION SECURITY INVARIANTS (INV-TX-01 through INV-TX-10)

- **INV-TX-01 (Statement Snapshot Freshness):** Under READ COMMITTED isolation, Step 13b executes a fresh command SELECT on security_blacklist_records [Rank 3] that observes all transactions committed prior to statement start (T_snapshot).
- **INV-TX-02 (Final Blacklist Visibility Boundary):** Any matching blacklist activation committed prior to T_snapshot is deterministically detected.
- **INV-TX-03 (Preliminary Non-Authority):** Preliminary snapshot reads never serve as the sole authorization basis for redemption.
- **INV-TX-04 (Logical Authorization Linearization Point):** T_authorization (Step 13c) is the logical authorization linearization point for vendor pass redemption, based strictly on state observed at T_snapshot.
- **INV-TX-05 (Lock Ceiling After Authorization):** No security-critical resource locks are newly acquired after T_authorization.
- **INV-TX-06 (Atomic Pass Mutation & Success Audit):** Pass status transition to used (T_mutation) and success audit log insertion are committed atomically by the framework upon normal function return (T_commit).
- **INV-TX-07 (Structured Denial Durability):** Denial logs are rendered durable via structured function returns without unhandled exception rollbacks.
- **INV-TX-08 (Unhandled Exception Safety):** Unhandled system errors cause complete transaction rollback; pass status remains issued without unauthorized access.
- **INV-TX-09 (Authoritative Pass Attributes):** Technician identity and phone used for Step 13b final blacklist evaluation correspond strictly to the canonical fields revalidated under the locked pass row [Rank 6].
- **INV-TX-10 (Zero Reverse Lock Dependencies):** Step 13b final blacklist check is an Ordinary Non-Locking SELECT (snapshot isolation read); it introduces zero 6 -> 3 lock dependencies or circular wait cycles.

---

## 10. SLICE 21 VERIFICATION MATRIX & ARITHMETIC

- **Substantive Security Assertions:** 76 Assertions (S21-001 through S21-076)
- **Governance Arithmetic Check:** 1 Check (S21-077 — Verifies cumulative arithmetic $714 + 77 = 791$)
- **Total Verification Checks:** **77 Checks**
- **Future Cumulative Target:** **714 + 77 = 791** *(Future Verification Target Only — 0 / 77 Currently Verified)*

---

## 11. F-25 RESOLUTION STATEMENT

> F-25 RESOLVED: Steps 1–10 are classified as forensic/preparatory analysis. Step 4 retains its explicitly scoped Rank-2 lock semantics where applicable. Authoritative AMC/pass validation begins at Steps 11–13a. Step 13b performs the final blacklist gate, and Step 13c produces the final decision. No Slice 21 lock is created by this plan-only activity.

---

## 12. FINAL GOVERNANCE DECLARATION

```text
SLICE 21 IMPLEMENTATION: PLANNED / NOT IMPLEMENTED / NOT VERIFIED

SLICE 21 VERIFICATION: NOT EXECUTED

SLICE 21 SECURITY LOCK: NOT AUTHORIZED

SLICES 1–20: LOCKED / IMMUTABLE

CURRENT LOCKED BASELINE: 714 / 714 PASS — 100% LOCKED

SLICE 21: PLAN ONLY

SLICE 21 ASSERTIONS: TARGET ONLY — NOT YET VERIFIED

REV 4.54: ABSENT

USER IMPLEMENTATION AUTHORIZATION: NOT GRANTED
```

**Final Verdict:** `READY FOR INDEPENDENT REVIEW`
