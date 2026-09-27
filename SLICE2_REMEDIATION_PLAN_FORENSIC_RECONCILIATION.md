# SLICE 2 — REMEDIATION PLAN FORENSIC RECONCILIATION

## EXECUTION MODE — ABSOLUTE

**READ-ONLY / PLAN-ONLY / ZERO IMPLEMENTATION / ZERO DATABASE MUTATION / ZERO APPLICATION MUTATION / ZERO GIT MUTATION**

---

## 1. Executive Verdict

```text
NOT READY — REMEDIATION PLAN REQUIRED
```

### Verdict Rationale:
A forensic challenge of `SLICE2_FINANCIAL_SERIALIZATION_REMEDIATION_PLAN.md` against the physical implementation candidate `database/schema_slice2.sql` and locked security specification `SLICE20_REVISION_4.53_FINAL_FORENSIC_BYTE_SAFE_AUTHORITY_PRESERVATION.md` reveals a critical architectural disconnect:

1. **Physical Absences of Property Locks**: `database/schema_slice2.sql` **DOES NOT PHYSICALLY CONTAIN** `SELECT 1 FROM public.properties WHERE id = p_property_id FOR UPDATE` in ANY financial function (`fn_generate_charge`, `fn_process_payment`, `fn_reverse_charge`, `fn_reverse_payment`, or `fn_get_property_outstanding_balance`).
2. **Lock Primitive Disconnection**: While Slice 20 NOC approval (`fn_approve_noc`) relies on acquiring a property-level lock (`public.properties FOR UPDATE`), Slice 2 financial functions acquire either **NO lock** (`fn_generate_charge`) or acquire locks on secondary table rows (`payments FOR UPDATE` in `fn_process_payment` and `fn_reverse_payment`, `maintenance_charges FOR UPDATE` in `fn_reverse_charge`).
3. **Concurrency Race Condition Vulnerability**: Because `fn_process_payment` locks `public.payments` while `fn_approve_noc` locks `public.properties`, concurrent payment verification and NOC balance check/approval transactions DO NOT wait on the same lock anchor. This allows payment verification and NOC balance check to interleave, creating a classic Time-of-Check to Time-of-Use (TOCTOU) race condition that violates `S20-055` (Financial Serialization) and `S20-059` (Concurrent Payment/Approval Serialization).
4. **Direct Write Exposure**: `database/schema_slice2.sql` executes `GRANT SELECT, INSERT, UPDATE, DELETE` on all financial tables (`payments`, `maintenance_charges`, `ledger_transactions`, `expenses`) to `authenticated`, relying solely on RLS policies rather than blocking direct PostgREST table writes.

---

## 2. Current Governance State

* **Locked Baseline**: **639 / 639 PASS (100%)** (covering Slices 1–19).
* **Slices 1–19 Status**: **LOCKED / IMMUTABLE / UNTOUCHED**.
* **Slice 2 Status**: **NOT IMPLEMENTED / NOT VERIFIED / NOT AUTHORIZED**.
* **Slice 20 Status**: **NOT IMPLEMENTED / NOT VERIFIED / NOT AUTHORIZED**.
* **Implementation Authorization**: **NONE**.
* **Implementation Gate**: **CLOSED**.

---

## 3. Artifact Integrity Audit

Forensic inspection of physical repository artifacts confirms zero unauthorized file modifications:

| Artifact Path | SHA-256 Hash | Byte Count | Physical Lines | Encoding | BOM Status | Unmodified Status |
|---|---|---|---|---|---|---|
| `SLICE20_REVISION_4.48_BYTE_SAFE_CLEAN_SECURITY_PLAN.md` | `A54904A4095112698FE5C5103F913C8359924480614AF3195889A2D0E29C499E` | 25234 | 428 | UTF-8 | ABSENT | **IMMUTABLE MATCH** |
| `SLICE20_REVISION_4.53_FINAL_FORENSIC_BYTE_SAFE_AUTHORITY_PRESERVATION.md` | `99F46FF7C7463E1E594F89C9C7C83FB7A15BEC8E9CBF93B9E7636D517210FE24` | 41540 | 423 | UTF-8 | ABSENT | **IMMUTABLE MATCH** |
| `database/schema_slice2.sql` | `86F4DE5045E549BD54216974669E55C9E0B0F874C48D6B42A791B0E17D07516C` | 26561 | 571 | UTF-8 | ABSENT | UNMODIFIED |
| `database/verify_slice2.sql` | `BAA3F0EA62FB498DE8C282AF4D3F073AF5B24BD8FAED3CF16E2A6150FCAD166E` | 22934 | 416 | UTF-8 | ABSENT | UNMODIFIED |
| `SLICE2_FINANCIAL_SERIALIZATION_REMEDIATION_PLAN.md` | `A9EE950505A5C3FCF07450E4B21818A92817C29EF8F1FA3BD6FEB5738512E590` | 21823 | 493 | UTF-8 | ABSENT | UNMODIFIED |
| `SLICE2_FORENSIC_READINESS_AUDIT.md` | `BCCD949846BAC547B6BE2D44BBE022D7ECD1B1E745A2ABF79F9F105F21D2A6AB` | 11180 | 222 | UTF-8 | ABSENT | UNMODIFIED |

---

## 4. Financial Source of Truth Analysis

1. **Authoritative Financial Balance**: Derived dynamically from `public.ledger_transactions` via helper function `fn_get_property_outstanding_balance(p_property_id)`:
   ```sql
   SELECT COALESCE(SUM(CASE WHEN direction = 'debit' THEN amount ELSE 0 END), 0) -
          COALESCE(SUM(CASE WHEN direction = 'credit' THEN amount ELSE 0 END), 0)
   FROM public.ledger_transactions
   WHERE property_id = p_property_id;
   ```
2. **Balance Storage Model**: Calculated dynamically from immutable append-only ledger entries (zero cached/stored balance column on `public.properties`).
3. **Financial State Tables**: `public.ledger_transactions` (ledger source of truth), `public.maintenance_charges` (charge source), `public.payments` (payment source), `public.expenses` (expense source).
4. **Target Lock Objects**:
   * *Proposed in Remediation Plan*: `public.properties` row lock (`SELECT 1 FROM public.properties WHERE id = p_property_id FOR UPDATE`).
   * *Actual in Candidate Schema*: `public.payments` row lock in `fn_process_payment`, `public.maintenance_charges` row lock in `fn_reverse_charge`, **ZERO LOCK** in `fn_generate_charge`.
5. **Mutation Paths**: Every financial event (charge generation, payment verification, charge reversal, payment reversal) inserts a new row into `public.ledger_transactions`.
6. **Property Row Function**: `public.properties` is an ownership/unit anchor table. It is intended to serve as the single serialization anchor for all property-scoped operations, but the current schema script fails to acquire it during financial mutations.

---

## 5. Serialization Primitive Analysis

* **Intended Lock Primitive**: `SELECT 1 FROM public.properties WHERE id = p_property_id FOR UPDATE`.
* **Actual Primitive in Schema Script**:
  * `fn_generate_charge`: Plain `SELECT society_id INTO v_society_id FROM public.properties WHERE id = p_property_id` (NO `FOR UPDATE` lock).
  * `fn_process_payment`: `SELECT * INTO v_payment FROM public.payments WHERE id = p_payment_id FOR UPDATE` (Locks `payments` row only).
  * `fn_reverse_charge`: `SELECT * INTO v_charge FROM public.maintenance_charges WHERE id = p_charge_id FOR UPDATE` (Locks `maintenance_charges` row only).
  * `fn_reverse_payment`: `SELECT * INTO v_payment FROM public.payments WHERE id = p_payment_id FOR UPDATE` (Locks `payments` row only).
* **Transaction Boundary**: Individual PL/pgSQL function execution block.
* **Evaluation**: **FAIL**. The physical schema script lacks uniform lock acquisition across financial mutation functions.

---

## 6. `properties FOR UPDATE` Sufficiency Verdict

```text
IS public.properties FOR UPDATE BY ITSELF SUFFICIENT TO SATISFY S20-055 AND S20-056?

ANSWER: NO
```

### Comprehensive Technical Reasoning:
1. **Absence in Implementation**: Even though `SLICE2_FINANCIAL_SERIALIZATION_REMEDIATION_PLAN.md` asserts that locking `public.properties` is the serialization anchor, `database/schema_slice2.sql` **does not contain property row locks** in its financial mutation functions.
2. **Asymmetric Lock Acquisition**:
   * In Slice 20, NOC approval (`fn_approve_noc`) acquires `SELECT 1 FROM public.properties WHERE id = p_property_id FOR UPDATE`.
   * In Slice 2, payment verification (`fn_process_payment`) acquires `SELECT * FROM public.payments WHERE id = p_payment_id FOR UPDATE`.
   * Because `fn_approve_noc` locks `public.properties` while `fn_process_payment` locks `public.payments`, PostgreSQL treats these as locks on completely distinct tables. Both transactions acquire their respective locks simultaneously without blocking each other.
3. **Race Condition Hazard**:
   * Transaction 1 (`fn_process_payment`): Verifies a payment of $500. Reads payment row, locks payment row, posts credit to ledger.
   * Transaction 2 (`fn_approve_noc`): Reads outstanding balance via `fn_get_property_outstanding_balance(p_property_id)`. Locks property row.
   * If Transaction 2 checks balance *before* Transaction 1 commits its ledger credit, NOC approval sees an unpaid balance and rejects or fails, or conversely, if Transaction 1 reverses a payment while Transaction 2 approves NOC based on pre-reversal balance, an invalid NOC is issued.
4. **Mandatory Requirement for Sufficiency**: To make property row locking sufficient, **EVERY financial mutation RPC** (`fn_generate_charge`, `fn_process_payment`, `fn_reverse_charge`, `fn_reverse_payment`) **MUST explicitly execute `SELECT 1 FROM public.properties WHERE id = v_property_id FOR UPDATE;` as its very first SQL statement** prior to reading balances or modifying financial records.

---

## 7. Concurrency & Race Condition Analysis

### Race A (Payment Verification vs NOC Approval)
* **Scenario**: Concurrent payment verification (`fn_process_payment`) and NOC approval (`fn_approve_noc`).
* **Current Schema Behavior**: `fn_process_payment` locks `public.payments`; `fn_approve_noc` locks `public.properties`. Locks do not overlap.
* **Interleaving Risk**: NOC approval reads ledger balance before payment verification commits credit entry. NOC request is falsely rejected for outstanding dues.
* **Status**: **FAIL — UNPROTECTED TOCTOU RACE**.

### Race B (Two Simultaneous NOC Approvals)
* **Scenario**: Concurrent NOC approval requests for the same property.
* **Current Schema Behavior**: Both attempt `FOR UPDATE` on `public.properties`. One wins, one waits. Partial unique index on `noc_requests(property_id) WHERE status='pending'` prevents duplicate creation.
* **Status**: **PASS — DESIGN**.

### Race C (Two Simultaneous Financial Deductions / Charges)
* **Scenario**: Concurrent execution of `fn_generate_charge` for the same property.
* **Current Schema Behavior**: Neither transaction acquires a property lock. Both insert into `maintenance_charges` and `ledger_transactions` concurrently.
* **Interleaving Risk**: Duplicate charges generated for the same billing period if unique index is absent or bypassed.
* **Status**: **FAIL — UNPROTECTED CONCURRENT MUTATION**.

### Race D (Balance Read vs Balance Mutation)
* **Scenario**: NOC balance check (`fn_get_property_outstanding_balance`) running concurrently with `fn_reverse_payment`.
* **Current Schema Behavior**: `fn_get_property_outstanding_balance` is a plain STABLE SELECT without locking.
* **Status**: **FAIL — UNLOCKED BALANCE READ**.

### Race E (Completed NOC Fee Immutability vs Subsequent Mutation)
* **Scenario**: Subsequent payment or charge reversal attempting to alter a completed NOC fee transaction.
* **Current Schema Behavior**: Ledger entries are append-only (`direction = 'debit'/'credit'`). Reversals add compensating entries without overwriting existing ledger rows. Trigger `trg_block_update_delete` blocks UPDATE/DELETE on `ledger_transactions`.
* **Status**: **PASS — IMMUTABLE LEDGER DESIGN**.

---

## 8. Deadlock Analysis

* **Lock Hierarchy Rule**: To prevent deadlocks, all multi-table transactions must acquire locks in exact canonical order.
* **Rev 4.53 Hierarchy**: `public.properties` -> `public.noc_requests` -> `public.noc_move_passes` -> `public.noc_gatekeeper_rate_limits`.
* **Slice 2 Lock Order**:
  * Proposed: `public.properties` (first).
  * Actual in Schema: Locks secondary tables (`payments` or `maintenance_charges`) without locking `properties`.
* **Deadlock Risk**: If a future RPC locks `noc_requests` first and then `properties`, while another locks `properties` first and then `noc_requests`, a PostgreSQL deadlock occurs (`SQLSTATE 40P01`).
* **Verdict**: **PARTIAL — REQUIRES UNIFORM LOCK ORDERING REINFORCEMENT**.

---

## 9. Append-Only Ledger Analysis

1. **Ledger Table**: `public.ledger_transactions`.
2. **Direct Write Prevention**:
   * Trigger `trg_block_update_delete` raises exception on any `UPDATE` or `DELETE` attempt on `ledger_transactions`.
   * RLS policies `pol_ledger_select_admin`, `pol_ledger_select_owner`, `pol_ledger_select_tenant` allow `SELECT` only. No `INSERT`, `UPDATE`, or `DELETE` policies exist for non-admin clients.
3. **Defect**: Section 7 of `database/schema_slice2.sql` executes `GRANT SELECT, INSERT, UPDATE, DELETE ON public.ledger_transactions TO authenticated;`. While RLS restricts non-admin clients, granting `UPDATE` and `DELETE` privileges to the `authenticated` role violates defense-in-depth principles.
4. **Verdict**: **PARTIAL — TRIGGER ENFORCED, BUT GRANTS OVER-PRIVILEGED**.

---

## 10. Direct Write / RLS / Privilege Analysis

* **Exposed Tables**: `maintenance_policies`, `maintenance_charges`, `payments`, `expenses`, `ledger_transactions`.
* **Grant Defect**: `GRANT SELECT, INSERT, UPDATE, DELETE ON ... TO authenticated;` is executed for ALL five Slice 2 tables.
* **RLS Defect**: `pol_payments_insert_client` allows direct `INSERT` into `public.payments` by owners/tenants with status `pending_verification`. While payment verification is restricted to RPC `fn_process_payment`, direct table grants leave API attack surfaces open to PostgREST exploitation.
* **Remediation Required**: Revoke direct `INSERT`, `UPDATE`, `DELETE` privileges from `authenticated` on financial tables, restricting mutations strictly to `SECURITY DEFINER` RPCs.

---

## 11. S20-054–S20-059 Compatibility Matrix

| Slice 20 Assertion | Required Slice 2 Capability | Proposed Mechanism | Schema Implementation Evidence | Compatibility Status |
|---|---|---|---|---|
| **S20-054** | Financial Balance Check | `fn_get_property_outstanding_balance()` post-lock read | Plain SELECT; no property lock in financial RPCs | **BLOCKED BY SLICE 2 DEFECT** |
| **S20-055** | Financial Serialization | Row lock acquired prior to financial mutation | No property lock in `fn_process_payment` or `fn_generate_charge` | **BLOCKED BY SLICE 2 DEFECT** |
| **S20-056** | Financial Ledger Lock | Property row lock acquired prior to NOC approval | NOC approval locks `properties`; payment locks `payments` | **BLOCKED BY SLICE 2 DEFECT** |
| **S20-057** | Negative / Insufficient Balance Block | Exception raised on `balance < 0` | Function exists, but unlocked read permits race condition | **BLOCKED BY SLICE 2 DEFECT** |
| **S20-058** | Completed NOC Fee Immutability | Append-only ledger transaction record | `trg_block_update_delete` trigger present; grants over-privileged | **PARTIAL — NEEDS GRANT CLEANUP** |
| **S20-059** | Concurrent Payment/Approval Serialization | Strict lock ordering: `properties` -> `noc_requests` | Unaligned lock targets between NOC and Financial RPCs | **BLOCKED BY SLICE 2 DEFECT** |

---

## 12. Slice 2 Verification Suite Assessment

Review of `database/verify_slice2.sql` (12 tests S2-001 through S2-012):
* **S2-001 to S2-004**: Test charge generation, payment processing, charge reversal, payment reversal. (Structural/Unit testing — PASS).
* **S2-005 to S2-008**: Test expense posting, expense reversal, outstanding balance calculation, audit logging. (Unit testing — PASS).
* **S2-009**: Tests append-only trigger by attempting UPDATE on `ledger_transactions`. (Immutability testing — PASS).
* **S2-010 to S2-012**: Test RLS select policies. (Security testing — PASS).
* **Defect**: **Zero tests in `database/verify_slice2.sql` test concurrent race conditions or verify property row lock acquisition during financial mutations!** The test suite passes structurally but fails to prove serialization under load.

---

## 13. Business Blockers

The following business decision blockers remain open and unresolved:
1. **BUS-DEC-01 (Zero Mandatory Checklist Category Handling Signoff)**: Defines mandatory vs optional NOC checklist taxonomy. Status: **BUSINESS-SCOPE DECISION REQUIRED**.
2. **BUS-DEC-02 (Tenant / Occupancy Transfer Scope Signoff)**: Defines tenant authorization scope and property ownership transfer boundaries. Status: **BUSINESS-SCOPE DECISION REQUIRED**.

---

## 14. Required Remediation Before Implementation

To resolve the identified defects, the Slice 2 plan and candidate schema script MUST be updated (in a future authorized task) as follows:
1. **Property Lock Insertion**: Update `fn_generate_charge`, `fn_process_payment`, `fn_reverse_charge`, `fn_reverse_payment` in `database/schema_slice2.sql` to execute `SELECT 1 FROM public.properties WHERE id = v_property_id FOR UPDATE;` as their very first statement.
2. **Privilege Hardening**: Replace `GRANT SELECT, INSERT, UPDATE, DELETE ON ... TO authenticated;` with `GRANT SELECT ON ... TO authenticated;` and restrict mutations strictly to `SECURITY DEFINER` RPCs.
3. **Concurrency Test Suite**: Add concurrency verification tests to `database/verify_slice2.sql` demonstrating property row lock serialization.

---

## 15. Final Recommendation

Slice 2 **MAY NOT** proceed to final implementation-plan preparation or database deployment until the remediation items in Section 14 are formally incorporated into `SLICE2_FINANCIAL_SERIALIZATION_REMEDIATION_PLAN.md` and `database/schema_slice2.sql`.

---

## 16. Final Immutability Check

Post-reconciliation verification confirms that authoritative specification files remain 100% byte-for-byte unchanged:

* **Rev 4.48 SHA-256**: `A54904A4095112698FE5C5103F913C8359924480614AF3195889A2D0E29C499E` (**UNCHANGED**)
* **Rev 4.53 SHA-256**: `99F46FF7C7463E1E594F89C9C7C83FB7A15BEC8E9CBF93B9E7636D517210FE24` (**UNCHANGED**)
* **Existing Slice 2 Remediation Plan SHA-256**: `A9EE950505A5C3FCF07450E4B21818A92817C29EF8F1FA3BD6FEB5738512E590` (**UNCHANGED**)
* **Existing Slice 2 Schema SHA-256**: `86F4DE5045E549BD54216974669E55C9E0B0F874C48D6B42A791B0E17D07516C` (**UNCHANGED**)

---

## 17. Final Governance Statement

```text
SLICE 20 REV 4.53 REMAINS LOCKED AND AUTHORITATIVE.

SLICES 1–19 REMAIN LOCKED.

LOCKED BASELINE REMAINS 639 / 639 PASS.

SLICE 2 IMPLEMENTATION REMAINS UNAUTHORIZED.

SLICE 20 IMPLEMENTATION REMAINS UNAUTHORIZED.

IMPLEMENTATION GATE REMAINS CLOSED.

NO IMPLEMENTATION WAS PERFORMED.

NO DATABASE MUTATION WAS PERFORMED.

NO APPLICATION MUTATION WAS PERFORMED.

NO GIT MUTATION WAS PERFORMED.

REV 4.48 REMAINS IMMUTABLE.

REV 4.53 REMAINS IMMUTABLE.

DO NOT CREATE REV 4.54.

FINAL MODE: READ-ONLY / PLAN-ONLY / ZERO IMPLEMENTATION.
```
