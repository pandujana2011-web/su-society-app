# SLICE 17 — SCHEMA ADAPTATION EVIDENCE

```text
DOCUMENT TYPE:  Schema Adaptation Inventory
PURPOSE:        Document every compatibility change made during Slice 17
                implementation that modified pre-existing table declarations
                from Slices 5 / 8 / 11 / 12.
MODIFICATIONS:  NONE MADE DURING PACKAGE PREPARATION
SOURCE:         database/schema_slice17.sql (frozen) + live catalog verification
```

---

## Overview

Slice 17 targets 9 tables that were partially defined in earlier slices. Before implementing
workflow functions and RLS, the schema required 11 compatibility adaptations to reconcile
legacy column definitions, CHECK constraints, and generated expressions with Slice 17 requirements.

Each adaptation is documented below with its original definition, final state, responsible SQL,
rationale, security consequence, integrity consequence, and invariant assessment.

---

## Adaptation 1 — `gate_passes.chk_gate_pass_status` — Added `'expired'` Status

### Original Constraint
```sql
-- From legacy slice definition:
CHECK (status IN ('pending', 'active', 'suspended'))
```

### Final Constraint (Live Catalog)
```sql
CHECK (status IN ('pending', 'active', 'suspended', 'expired'))
```

### Responsible SQL (schema_slice17.sql)
```sql
ALTER TABLE public.gate_passes
    DROP CONSTRAINT IF EXISTS chk_gate_pass_status;
ALTER TABLE public.gate_passes
    ADD CONSTRAINT chk_gate_pass_status
    CHECK (status IN ('pending', 'active', 'suspended', 'expired'));
```

### Rationale
The Slice 17 `transition_gate_pass_status` function supports `'suspended'` and `'active'`
transitions. The `'expired'` value was added to allow future pass expiration workflows.
The existing function does NOT transition to `'expired'`; it only accepts `'suspended'`
and `'active'` as valid `p_new_status` arguments.

### Security Consequence
**LOW / NEUTRAL.** The state machine inside `transition_gate_pass_status` explicitly rejects
any `p_new_status` value that is not `'suspended'` or `'active'` (the ELSE branch raises
`EXCEPTION 'Invalid target status'`). Adding `'expired'` to the CHECK constraint does not
enable `'expired'` transitions through the workflow function. However, if `fn_transition_gate_pass_state`
(legacy) or a future function passes `'expired'`, the database would accept it.

### Data Integrity Consequence
**PRESERVES.** The original constraint allowed 3 values. The new constraint allows 4 values.
No existing valid state is excluded. One new valid terminal state is added.

### Invariant Assessment
**WEAKENED SLIGHTLY** (extended state space, not exploitable via current workflow).

---

## Adaptation 2 — `parcel_logs.chk_parcel_status` — Added `'locked_failed_attempts'`

### Original Constraint
```sql
CHECK (status IN ('received_at_gate', 'collected', 'returned'))
```

### Final Constraint (Live Catalog)
```sql
CHECK (status IN ('received_at_gate', 'collected', 'locked_failed_attempts', 'returned'))
```

### Responsible SQL
```sql
ALTER TABLE public.parcel_logs
    DROP CONSTRAINT IF EXISTS chk_parcel_status;
ALTER TABLE public.parcel_logs
    ADD CONSTRAINT chk_parcel_status
    CHECK (status IN ('received_at_gate', 'collected', 'locked_failed_attempts', 'returned'));
```

### Rationale
`'locked_failed_attempts'` is the brute-force lockout terminal state set by `collect_parcel`
after 5 failed code verification attempts.

### Security Consequence
**STRENGTHENS SECURITY.** The additional status enables the brute-force lockout mechanism.
Without this status, the attempt counter could roll past 5 without an enforceable locked state.

### Data Integrity Consequence
**STRENGTHENS.** Adds a permanent lockout state that prevents further collection attempts.

### Invariant Assessment
**STRENGTHENED** — new security-critical terminal state.

---

## Adaptation 3 — `meter_readings.chk_reading_status` — Added `'submitted'`

### Original Constraint
```sql
CHECK (status IN ('draft', 'verified', 'billed', 'rejected'))
```

### Final Constraint (Live Catalog)
```sql
CHECK (status IN ('draft', 'submitted', 'verified', 'billed', 'rejected'))
```

### Responsible SQL
```sql
ALTER TABLE public.meter_readings
    DROP CONSTRAINT IF EXISTS chk_reading_status;
ALTER TABLE public.meter_readings
    ADD CONSTRAINT chk_reading_status
    CHECK (status IN ('draft', 'submitted', 'verified', 'billed', 'rejected'));
```

### Rationale
`submit_meter_reading` sets status to `'submitted'` as an intermediate state between resident
submission and admin billing. The original constraint did not include `'submitted'`.

### Security Consequence
**NEUTRAL.** Adds a status value required for the Slice 17 two-step workflow (resident submits →
admin bills). Does not bypass or weaken any existing authorization check.

### Data Integrity Consequence
**PRESERVES** the lifecycle model; adds an intermediate state.

### Invariant Assessment
**PRESERVES** — no valid state removed; adds a required workflow state.

---

## Adaptation 4 — `vehicles.chk_vehicle_type` — Dual-Format Compatibility

### Original Constraint
```sql
CHECK (vehicle_type IN ('2-wheeler', '4-wheeler'))
```

### Final Constraint (Live Catalog)
```sql
CHECK (vehicle_type IN ('four_wheeler', 'two_wheeler', '2-wheeler', '4-wheeler'))
```

### Responsible SQL
```sql
ALTER TABLE public.vehicles
    DROP CONSTRAINT IF EXISTS chk_vehicle_type;
ALTER TABLE public.vehicles
    ADD CONSTRAINT chk_vehicle_type
    CHECK (vehicle_type IN ('four_wheeler', 'two_wheeler', '2-wheeler', '4-wheeler'));
```

### Rationale
The `register_vehicle` function uses canonical Slice 17 enum values (`'four_wheeler'`,
`'two_wheeler'`). Legacy test fixtures and prior slices used `'2-wheeler'`, `'4-wheeler'`.
Both formats must be accepted to avoid constraint violations in the cumulative test suite.

### Security Consequence
**LOW.** The CHECK constraint is an input validation guard; accepting 4 values instead of 2
doubles the accepted surface but all 4 values are semantically equivalent vehicle categories.
There is no privilege or authorization decision based on `vehicle_type`.

### Data Integrity Consequence
**WEAKENED SLIGHTLY** — the format is no longer canonical. Two representations of the same
logical type coexist. This creates potential confusion in application-layer queries filtering by
`vehicle_type` but does not introduce a security vulnerability.

### Invariant Assessment
**WEAKENED (FORMAT)** — dual format increases ambiguity; no security control depends on the value.

---

## Adaptation 5 — `sos_alerts.sos_alerts_alert_type_check` — Constraint DROPPED

### Original Constraint
```sql
-- From legacy slice definition:
CHECK (alert_type IN ('security', 'medical', 'fire', 'lift_emergency', 'other'))
```

### Final State (Live Catalog)
**CONSTRAINT DOES NOT EXIST.** The live catalog shows NO CHECK constraint on `sos_alerts.alert_type`.
The column is `NOT NULL` but the value is unconstrained.

### Responsible SQL
```sql
ALTER TABLE public.sos_alerts
    DROP CONSTRAINT IF EXISTS sos_alerts_alert_type_check;
```

### Rationale
The `trigger_sos_alert` function uses `COALESCE(p_alert_type, 'general')` as the default value.
`'general'` was not in the original constraint, causing constraint violations when no type was
specified. Rather than adding `'general'` to the constraint, the constraint was dropped entirely.

### Security Consequence
**WEAKENED (INPUT VALIDATION REMOVED).** Without a CHECK constraint, any string up to 50 characters
can be stored as `alert_type`. Application-layer enumeration of emergency categories now relies
entirely on the workflow function's parameter (not enforced by the database engine). A malicious
caller with direct write access (bypassing RLS, e.g., via service_role) could inject arbitrary
alert_type strings. Via the workflow function, the caller controls `p_alert_type` which is
passed without sanitization.

### Data Integrity Consequence
**WEAKENED** — the database no longer enforces any specific set of valid emergency types.

### Invariant Assessment
**WEAKENED** — the database-engine constraint is gone. Secondary enforcement is in application logic only.

---

## Adaptation 6 — `gate_passes.staff_id` and `requested_by` — NOT NULL Dropped

### Original Definition
```sql
-- From legacy slice:
staff_id UUID NOT NULL,
requested_by UUID NOT NULL
```

### Final Definition (Live Catalog)
```sql
staff_id UUID,        -- nullable
requested_by UUID     -- nullable
```

### Responsible SQL
```sql
ALTER TABLE public.gate_passes ALTER COLUMN staff_id DROP NOT NULL;
ALTER TABLE public.gate_passes ALTER COLUMN requested_by DROP NOT NULL;
```

### Rationale
`staff_id` is NULL for visitor passes where no specific staff member is assigned.
`requested_by` is a legacy identity column; Slice 17 uses `created_by = v_caller` instead.
The `issue_gate_pass` function does not write to `requested_by`.

### Security Consequence
**MEDIUM.** `requested_by` is nullable and not populated by Slice 17 functions. If `requested_by`
was previously used as the authoritative identity column in audit queries or access-control
decisions in other code paths, those paths now see NULL. The Slice 17 functions use `created_by`
for identity. Audit logs capture `actor_id = v_caller` from `auth.uid()`. No authorization
decision in Slice 17 uses `requested_by`.

### Data Integrity Consequence
**WEAKENED** — identity field `requested_by` may be NULL for all Slice 17-issued passes.

### Invariant Assessment
**WEAKENED (IDENTITY COLUMN)** — `requested_by` is now an unreliable identity field.

---

## Adaptation 7 — `parcel_logs.collection_code` — NOT NULL Dropped

### Original Definition
```sql
-- Legacy:
collection_code VARCHAR(10) NOT NULL
```

### Final Definition (Live Catalog)
```sql
collection_code VARCHAR(10)    -- nullable
```

### Responsible SQL
```sql
ALTER TABLE public.parcel_logs ALTER COLUMN collection_code DROP NOT NULL;
```

### Rationale
The Slice 17 security model prohibits plaintext code storage. `log_parcel_delivery` inserts
`collection_code = NULL` and stores only `collection_code_hash`. This is the intended behavior.

### Security Consequence
**STRENGTHENS SECURITY.** The plaintext code is never stored in the database. Only the
SHA-256 hash is stored. If the `parcel_logs` table were compromised, collection codes
could not be extracted in plaintext.

### Data Integrity Consequence
**NEUTRAL** — the hash provides sufficient integrity for code verification.

### Invariant Assessment
**STRENGTHENED** — nullability enforces the hash-only storage model.

---

## Adaptation 8 — Multiple Columns — NOT NULL Dropped

The following columns had NOT NULL dropped:

| Table | Column | Rationale |
|---|---|---|
| `sos_alerts` | `raised_by` | Legacy identity column; Slice 17 uses `triggered_by`. Both coexist nullable. |
| `utility_meters` | `utility_type` | Legacy type column; Slice 17 uses `meter_type`. Both coexist nullable. |
| `meter_readings` | `created_by` | Optional identity; `submitted_by` used by Slice 17 workflow. |
| `polls` | `description` | Description is optional per Slice 17 specification. |

### Responsible SQL
```sql
ALTER TABLE public.sos_alerts ALTER COLUMN raised_by DROP NOT NULL;
ALTER TABLE public.utility_meters ALTER COLUMN utility_type DROP NOT NULL;
ALTER TABLE public.meter_readings ALTER COLUMN created_by DROP NOT NULL;
ALTER TABLE public.polls ALTER COLUMN description DROP NOT NULL;
```

### Security Consequence
**LOW.** None of these columns are used in authorization decisions. The nullable identity
columns (`raised_by`, `created_by`) are legacy fields not referenced by Slice 17 security checks.

### Data Integrity Consequence
**WEAKENED SLIGHTLY** — optional fields that were previously mandatory are now nullable,
allowing rows with incomplete metadata to be stored.

### Invariant Assessment
**WEAKENED (METADATA COMPLETENESS)** — identity/metadata completeness is reduced.

---

## Adaptation 9 — `meter_readings.consumption` and `total_charge` — Generated Expressions Dropped

### Original Definition
```sql
-- Legacy generated columns:
consumption NUMERIC GENERATED ALWAYS AS (current_reading - previous_reading) STORED,
total_charge NUMERIC GENERATED ALWAYS AS (consumption * applied_unit_rate) STORED
```

### Final Definition (Live Catalog)
```sql
consumption NUMERIC,    -- nullable, NOT generated
total_charge NUMERIC    -- nullable, NOT generated
```

### Responsible SQL
```sql
ALTER TABLE public.meter_readings
    ALTER COLUMN consumption DROP EXPRESSION IF EXISTS;
ALTER TABLE public.meter_readings
    ALTER COLUMN total_charge DROP EXPRESSION IF EXISTS;
```

### Rationale
GENERATED ALWAYS AS expressions prevent explicit INSERT/UPDATE of the column value. The
`submit_meter_reading` function computes `consumption` in PL/pgSQL and inserts it explicitly.
The expression had to be dropped to allow the function to set `consumption` directly.

### Security Consequence
**MEDIUM.** The database engine no longer guarantees that `consumption = current_reading - previous_reading`.
The PL/pgSQL function computes this correctly, but this is application-level enforcement, not
engine-level enforcement. A privileged actor bypassing the workflow (e.g., `service_role` direct
INSERT, or a future function with a calculation error) could insert a `meter_readings` row with
an incorrect `consumption` value, resulting in incorrect billing.

### Data Integrity Consequence
**WEAKENED.** The database no longer provides an immutable mathematical invariant for `consumption`.
The `total_charge` column is populated by the workflow as `total_amount`, not `total_charge`
(two different columns). `total_charge` may be NULL for all Slice 17-inserted rows.

### Invariant Assessment
**WEAKENED** — financial calculation invariant moved from engine layer to application layer.
The independent auditor should verify that no row can be inserted with an inconsistent
`consumption` value through any accessible code path.

---

## Adaptation 10 — `parcel_logs` Trigger — Dual GUC Context Check

### Original Trigger Guard
```sql
-- Legacy trg_prevent_direct_parcel_update_func checked:
IF current_setting('app.parcel_transition', true) = NEW.id::text THEN ...
```

### Final Implementation
```sql
-- Slice 17 trg_prevent_direct_parcel_update_func checks BOTH:
IF current_setting('app.workflow_context', true) = 'parcel_transition'
   AND current_setting('app.parcel_transition', true) = NEW.id::text THEN
    RETURN NEW;  -- allow
ELSE
    RAISE EXCEPTION 'Direct parcel update blocked';
END IF;
```

### Rationale
Slice 17 workflow functions use `app.workflow_context = 'parcel_transition'` as the primary
context signal. The legacy trigger checked only `app.parcel_transition`. The dual check maintains
compatibility with both the legacy and Slice 17 context-setting patterns.

### Security Consequence
**MEDIUM / DESIGN CONCERN.** Both GUCs are session-level variables set with `set_config(..., true)`
(transaction-scoped LOCAL setting). The security of this trigger guard depends on whether an
unprivileged caller can SET these GUC values before executing a direct UPDATE. In Supabase/PostgREST,
`authenticated` users cannot execute `SET` for arbitrary GUC parameters — `SET` requires appropriate
permissions and the parameters would need to be in `allowed_parameter` allowlists. However, if any
function grants this capability, or if a future `service_role` caller sets these GUCs before a direct
UPDATE, the trigger guard could be bypassed. The dual-condition check is SLIGHTLY STRONGER than
the legacy single-condition check.

### Data Integrity Consequence
**PRESERVES** — the trigger guard still blocks direct client UPDATE on parcel status.

### Invariant Assessment
**PRESERVES** — dual-check is at least as strong as the original single-check.

---

## Adaptation 11 — `ledger_transactions.source_meter_reading_id` — Set in Billing Function

### Context
The `ledger_transactions` table has a constraint `chk_ledger_source_exclusive` that requires
exactly one of several `source_*_id` columns to be non-NULL. Prior implementations of
`verify_and_bill_meter_reading` omitted `source_meter_reading_id`, causing the constraint to fail.

### Original Behavior
`source_meter_reading_id` was not set; INSERT failed with `chk_ledger_source_exclusive` violation.

### Final Behavior
```sql
INSERT INTO public.ledger_transactions (
    ..., source_meter_reading_id, ...
) VALUES (
    ..., p_reading_id, ...   -- explicitly set
);
```

### Responsible SQL (in verify_and_bill_meter_reading function body)
```sql
INSERT INTO public.ledger_transactions (
    society_id, scope, property_id, amount, direction, transaction_type,
    source_meter_reading_id, description, created_by
) VALUES (
    v_meter.society_id, 'property', v_reading.property_id, v_reading.total_amount,
    'debit', 'utility_bill', p_reading_id,
    'Utility bill reading for meter ' || v_meter.meter_number, v_target_user
);
```

### Security Consequence
**NEUTRAL / POSITIVE.** This is a correctness fix. Setting `source_meter_reading_id` establishes
a traceable link between the ledger transaction and the meter reading, improving auditability.
It satisfies the schema constraint.

### Data Integrity Consequence
**STRENGTHENS** — ledger entries are now correctly linked to their source meter reading.

### Invariant Assessment
**STRENGTHENED** — constraint satisfaction is now correct; audit trail is complete.

---

## Summary Table

| # | Table(s) | Change | Security Impact | Integrity Impact | Invariant |
|---|---|---|---|---|---|
| 1 | `gate_passes` | Added `'expired'` status | LOW/NEUTRAL | Preserves | Weakened (extended state) |
| 2 | `parcel_logs` | Added `'locked_failed_attempts'` | STRENGTHENS | Strengthens | Strengthened |
| 3 | `meter_readings` | Added `'submitted'` status | NEUTRAL | Preserves | Preserves |
| 4 | `vehicles` | Dual vehicle_type format | LOW | Weakened (format) | Weakened (format) |
| 5 | `sos_alerts` | Dropped alert_type CHECK | **WEAKENED** | Weakened | Weakened |
| 6 | `gate_passes` | `staff_id`, `requested_by` nullable | MEDIUM | Weakened | Weakened |
| 7 | `parcel_logs` | `collection_code` nullable | STRENGTHENS | Neutral | Strengthened |
| 8 | Multiple | Various NOT NULL dropped | LOW | Weakened | Weakened |
| 9 | `meter_readings` | Generated expressions dropped | **MEDIUM** | Weakened | Weakened |
| 10 | `parcel_logs` | Dual GUC trigger check | MEDIUM/CONCERN | Preserves | Preserves |
| 11 | `ledger_transactions` | `source_meter_reading_id` set | NEUTRAL/POSITIVE | Strengthens | Strengthened |

---

*End of Schema Adaptation Evidence. No database modifications were made during the preparation of this document.*
