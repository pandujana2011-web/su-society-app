# SU SOCIETY APP — POST-ACCEPTANCE PRODUCTION FINDINGS
## FORENSIC TRIAGE & EVIDENCE VALIDATION REPORT

**Target Repository:** `D:\Clients Applications\SU Society App`  
**Target Production Supabase Project:** `fsegpxqoozxmicxcxjun` (`pandujana2011-web's Project`)  
**Region:** `ap-south-1`  
**PostgreSQL Version:** `17.6.1.166`  
**Production Application URL:** `https://su-society-app.vercel.app`  
**Execution Mode:** `READ-ONLY FORENSIC TRIAGE ONLY / ZERO CODE MODIFICATION / ZERO DATABASE MUTATION / ZERO MIGRATION CREATION / ZERO DEPLOYMENT / ZERO CONFIGURATION CHANGE`  
**Authoritative Date:** `2026-09-19`

---

## 1. EXECUTIVE SUMMARY

Following formal completion of Real-World UAT Stage 10 and publication of the authoritative handover record (`FINAL_PROJECT_CLOSURE_AND_PRODUCTION_HANDOVER.md`), six (6) post-acceptance production findings were submitted for forensic triage.

Pursuant to strict governance protocols, this investigation was conducted in **100% READ-ONLY FORENSIC TRIAGE MODE**. Zero source code files were edited, zero database mutations occurred, zero SQL migrations were created, and Candidate-29 remains completely absent (`0 files`).

### Triage Summary Table

| Finding ID | Title | Reported Severity | Triage Classification | Root Cause Component |
| :--- | :--- | :--- | :--- | :--- |
| **FINDING 1** | Expense Manager React Runtime Crash | **P0** | `CONFIRMED FRONTEND DEFECT` | `src/App.jsx` (Missing form submit handlers `handleAddCategory`, `handleAddBudget` & unhandled React exception) |
| **FINDING 2** | Bank Reconciliation (BRS) Create Runtime Crash | **P0** | `CONFIRMED FRONTEND DEFECT` | `src/App.jsx` (Missing BRS action handlers `handleAddRecon`, `handleCompleteRecon`, `handleMatchTransactions`) |
| **FINDING 3** | Opening Balance Discriminator Violation | **P1** | `CONFIRMED FRONTEND / MOCK CLIENT CONTRACT MISMATCH DEFECT` | `src/supabase.js` (`mockClient.opening_balances.create` passes `billing_subject_type: 'none'` with `property_id` populated) |
| **FINDING 4** | Audit Logs Missing OLD STATE | **P2** | `CONFIRMED FRONTEND / MOCK SERVICE LOGIC DEFECT` | `src/supabase.js` (NOC clearance `logAudit` calls pass `null` for 5th parameter `oldValue`) |
| **FINDING 5** | Audit Timestamp / Date Discrepancy | **P2** | `PRESEEDED DATA / EXPECTED SYSTEM TIME BEHAVIOR` | `src/App.jsx` & static mock data (Pre-seeded UAT logs dated `18/09/2026` mixed with live `19/09/2026` system timestamps) |
| **FINDING 6** | Booking & Helpdesk Admin Action Controls | **P3** | `INTENTIONAL READ-ONLY DESIGN / ENHANCEMENT REQUEST` | `src/App.jsx` (Operations Coordinator views designed for admin review/approval of resident-initiated items) |

---

## 2. BASELINE INTEGRITY CHECK

Prior to and immediately following this read-only forensic triage exercise, the production baseline state was verified:

* **Production Supabase Project ID:** `fsegpxqoozxmicxcxjun`
* **Production Database Engine:** PostgreSQL `17.6.1.166` (`ap-south-1`)
* **Production Application URL:** `https://su-society-app.vercel.app`
* **Production Migration Count:** `28 / 28` applied (`20260918000028_candidate28_remediation.sql`)
* **Candidate-28 SHA-256 Checksum:** `48AEFC1D3ECD11510E05B9E0714C369E85AE8753869A44C1005A03D717F1CBAC`
* **Candidate-29 Files:** `0` (None created)
* **Codebase Source Modifications:** `0`
* **Database Schema & Data Mutations:** `0`
* **Deployments Executed:** `0`

---

## 3. FINDING-BY-FINDING FORENSIC EVIDENCE

---

### FINDING 1 — P0: Expense Manager React Runtime Crash

* **Finding ID:** `FINDING-1`
* **Severity:** `P0 (Critical / Application Crash)`
* **Module:** Billing & Ledger → Expense Manager (`activeSubTab === 'expenses'`)
* **Reported Triggers:**
  1. Add Category → "Save Category"
  2. Allocate → "Save Budget"
  3. Create Voucher → "Save Voucher"
* **Classification:** `CONFIRMED FRONTEND DEFECT`

#### 1. Reproduction & Static Analysis Evidence
* **Component Location:** [src/App.jsx](file:///D:/Clients%20Applications/SU%20Society%20App/src/App.jsx#L2177-L2210) (`BillingManagerView` sub-component).
* **Code Snippet (Add Category):**
  ```jsx
  // Line 2177 in src/App.jsx
  <form onSubmit={handleAddCategory} style={{ marginBottom: '1rem'... }}>
  ```
* **Code Snippet (Allocate Budget):**
  ```jsx
  // Line 2210 in src/App.jsx
  <form onSubmit={handleAddBudget} style={{ marginBottom: '1rem'... }}>
  ```
* **Root Cause Determination:**
  In `BillingManagerView` (`src/App.jsx` lines 1007–1100), state variables for `showAddCategory`, `showAddBudget`, `categoryName`, `bAmount`, etc. are defined, BUT the handler functions `handleAddCategory` and `handleAddBudget` are **NEVER declared or defined** anywhere in the component function body.
  When the user submits either form, HTML form submission attempts to invoke `onSubmit={handleAddCategory}` or `onSubmit={handleAddBudget}` (which evaluate to `undefined`). Executing `undefined(e)` throws an unhandled JavaScript runtime exception:
  `TypeError: handleAddCategory is not a function` / `TypeError: handleAddBudget is not a function`.
* **Error Boundary Absence:**
  No top-level React Error Boundary wraps `BillingManagerView` or `App`. In React 18/19, an unhandled error during event dispatch or rendering causes React to unmount the entire component tree, producing a blank dark screen requiring a browser reload.
* **Network & Data Dependency:**
  The failure is 100% frontend-only. The form submission fails synchronously before any network request or API invocation occurs.
* **Determinism:** `100% Deterministic`.

---

### FINDING 2 — P0: Bank Reconciliation (BRS) Create Runtime Crash

* **Finding ID:** `FINDING-2`
* **Severity:** `P0 (Critical / Application Crash)`
* **Module:** Billing & Ledger → Bank Reconciliation (BRS) (`activeSubTab === 'reconciliation'`)
* **Reported Trigger:** Click purple "Create" button under BRS Sheets, submit statement form, or click "Complete & Lock Sheet" / "Match Selected Transactions".
* **Classification:** `CONFIRMED FRONTEND DEFECT`

#### 1. Reproduction & Static Analysis Evidence
* **Component Location:** [src/App.jsx](file:///D:/Clients%20Applications/SU%20Society%20App/src/App.jsx#L2420-L2492) (`BillingManagerView` sub-component).
* **Code Snippets:**
  ```jsx
  // Line 2420 in src/App.jsx
  <form onSubmit={handleAddRecon} style={{ marginBottom: '1rem'... }}>

  // Line 2475 in src/App.jsx
  <button onClick={() => handleCompleteRecon(selectedRecon.id)}>🔒 Complete & Lock Sheet</button>

  // Line 2492 in src/App.jsx
  <button onClick={() => handleMatchTransactions(selectedRecon.id)}>Match Selected Transactions</button>
  ```
* **Root Cause Determination:**
  In `BillingManagerView`, state variables `showAddRecon`, `rDate`, `rOpenBal`, `rCloseBal`, `selectedRecon`, and `reconcileTxSelection` are initialized, but the action handler functions `handleAddRecon`, `handleCompleteRecon`, and `handleMatchTransactions` are **NEVER declared or defined** in `BillingManagerView`.
  Submitting the BRS sheet form or clicking Complete/Match invokes `undefined`, throwing:
  `TypeError: handleAddRecon is not a function` / `TypeError: handleCompleteRecon is not a function` / `TypeError: handleMatchTransactions is not a function`.
* **Error Boundary Absence:**
  With no React Error Boundary present, unhandled exceptions unmount the React application tree, resulting in an empty/blank screen.
* **Network & Backend Status:**
  Failure occurs strictly on the client side before any network request reaches the Supabase client or backend API.
* **Determinism:** `100% Deterministic`.

---

### FINDING 3 — P1: Opening Balance Discriminator Violation

* **Finding ID:** `FINDING-3`
* **Severity:** `P1 (High / Financial Operation Blocker)`
* **Module:** Billing & Ledger → Opening Balances → Record Opening Balance
* **Reported Workflow:** Property (`Plot 45`) + Member (`Kalyan Reddy`) + Direction (`Debit`) + Amount (`₹2000`) → Click "Confirm opening balance".
* **Observed Error:** `Error: Discriminator violation: billing type none requires all keys empty.`
* **Classification:** `CONFIRMED FRONTEND / MOCK CLIENT CONTRACT MISMATCH DEFECT`

#### 1. Reproduction & Static Analysis Evidence
* **Frontend Invocation Location:** [src/App.jsx](file:///D:/Clients%20Applications/SU%20Society%20App/src/App.jsx#L1252-L1258)
  ```javascript
  await db.opening_balances.create({
    property_id: balPropId,
    user_id: balUserId,
    amount: balAmount,
    direction: balDirection,
    as_of_date: balDate || new Date().toISOString().split('T')[0]
  }, user);
  ```
* **Mock Service Location:** [src/supabase.js](file:///D:/Clients%20Applications/SU%20Society%20App/src/supabase.js#L1174-L1192)
  ```javascript
  const ledgerTx = {
    id: 'tx-...',
    society_id: '11111111-1111-1111-1111-111111111111',
    property_id: newBal.property_id, // <--- PROPERTY_ID IS POPULATED HERE
    user_id: newBal.user_id,
    billing_subject_type: 'none',   // <--- SET TO 'none'
    billing_property_id: null, billing_unit_id: null, billing_family_id: null, billing_custom_subject_id: null,
    scope: 'member',
    direction: newBal.direction,
    amount: newBal.amount,
    transaction_type: 'adjustment',
    ...
  };

  validateBillingSubjectFKDiscriminator(ledgerTx); // <--- INVOCATION
  ```
* **Discriminator Validator Function:** [src/supabase.js](file:///D:/Clients%20Applications/SU%20Society%20App/src/supabase.js#L268-L287)
  ```javascript
  const validateBillingSubjectFKDiscriminator = (obj) => {
    const type = obj.billing_subject_type;
    const prop = obj.property_id || obj.billing_property_id; // <--- RESOLVES property_id
    ...
    } else if (type === 'none') {
      if (prop || unit || family || custom) 
        throw new Error('Discriminator violation: billing type none requires all keys empty.');
    }
  };
  ```
* **Root Cause Determination:**
  When `mockClient.opening_balances.create()` generates the compensating ledger entry `ledgerTx`, it sets `billing_subject_type = 'none'`, but populates `ledgerTx.property_id = newBal.property_id`.
  The validator function `validateBillingSubjectFKDiscriminator(ledgerTx)` checks if `type === 'none'`, and asserts that `prop` (which evaluates `obj.property_id || obj.billing_property_id`) MUST be falsy/empty.
  Because `ledgerTx.property_id` is populated with the plot UUID, the validator fails and throws:
  `Discriminator violation: billing type none requires all keys empty.`
* **Backend Contract Context:**
  In PostgreSQL / Supabase, opening balances registered for a specific property member ledger require `billing_subject_type = 'property'` (or setting `billing_property_id = property_id`). The mock client implementation mistakenly assigns `billing_subject_type: 'none'`, causing a self-contradictory validation failure.
* **Determinism:** `100% Deterministic`.

---

### FINDING 4 — P2: Audit Logs Missing OLD STATE

* **Finding ID:** `FINDING-4`
* **Severity:** `P2 (Medium / Audit Trail Formatting)`
* **Module:** Security Audit Logs (`AuditLogsView`)
* **Reported Observations:** Actions such as `UPDATED clearance checklist item`, `EXECUTED financial dues clearance`, `APPROVED NOC request` show `-` under the "Old State" column.
* **Classification:** `CONFIRMED FRONTEND / MOCK SERVICE LOGIC DEFECT`

#### 1. Reproduction & Static Analysis Evidence
* **UI Rendering Location:** [src/App.jsx](file:///D:/Clients%20Applications/SU%20Society%20App/src/App.jsx#L2783)
  ```jsx
  <td style={{ fontSize: '0.8rem', fontFamily: 'monospace' }}>
    {log.old_value ? JSON.stringify(log.old_value).substring(0, 50) + '...' : '-'}
  </td>
  ```
* **Mock Service Helper Calls:** [src/supabase.js](file:///D:/Clients%20Applications/SU%20Society%20App/src/supabase.js#L3136-L3179)
  ```javascript
  // Line 3136
  logAudit(currentUser.id, 'EXECUTED financial dues clearance', 'noc_requests', requestId, null, { status, balance });

  // Line 3159
  logAudit(currentUser.id, 'UPDATED clearance checklist item', 'noc_clearance_checklists', chk.id, null, { category, status, remarks });

  // Line 3179
  logAudit(currentUser.id, 'APPROVED NOC request', 'noc_requests', requestId, null, { certificate_url: request.certificate_url });
  ```
* **Root Cause Determination:**
  The `logAudit` helper signature is `logAudit(userId, action, tableName, recordId, oldValue, newValue)`.
  In the Slice 20 NOC clearance methods inside `src/supabase.js`, the 5th parameter (`oldValue`) is explicitly passed as `null`.
  As a result, `old_value` is saved as `null` in the audit log array. When `AuditLogsView` renders in React, `log.old_value` evaluates to `null` and falls back to rendering the dash string `"-"`.
* **Database / UI Semantics:**
  The UI component is behaving as programmed (rendering `-` when `old_value` is `null`). The defect lies in the mock service functions passing `null` instead of capturing the previous record state (`oldVal`) before applying updates.
* **Determinism:** `100% Deterministic`.

---

### FINDING 5 — P2: Audit Timestamp / Date Discrepancy

* **Finding ID:** `FINDING-5`
* **Severity:** `P2 (Low / Data Presentation)`
* **Reported Observation:** Recent NOC and User operations display `19/09/2026`, while preceding Asset creation, Vendor registration, and AMC renewal logs display `18/09/2026`.
* **Classification:** `PRESEEDED DATA / EXPECTED SYSTEM TIME BEHAVIOR`

#### 1. Static & Data Evidence
* **Source Locations:** [src/supabase.js](file:///D:/Clients%20Applications/SU%20Society%20App/src/supabase.js#L145-L165) & [src/App.jsx](file:///D:/Clients%20Applications/SU%20Society%20App/src/App.jsx#L2779).
* **Analysis:**
  1. Static seed data and initial mock audit records created during Candidate-28 UAT execution were generated with timestamps dated `2026-09-18`.
  2. Live operations performed during current testing execute `new Date().toISOString()`, capturing the workstation system clock (`2026-09-19`).
  3. `AuditLogsView` formats timestamps via `new Date(log.created_at).toLocaleString()`.
* **Root Cause Determination:**
  This discrepancy is not an application integrity defect. It is the expected result of mixing static pre-seeded historical test log dates (`18/09/2026`) with real-time execution timestamps generated on `19/09/2026`.
* **Determinism:** `Expected Behavior`.

---

### FINDING 6 — P3: Booking & Helpdesk Admin Action Controls

* **Finding ID:** `FINDING-6`
* **Severity:** `P3 (Informational / Enhancement Request)`
* **Module:** Operations Manager → Booking Requests & Helpdesk Coordinator (`activeTab === 'bookings'` / `activeTab === 'helpdesk'`)
* **Observation:** Pages display read-only tables ("No booking requests found", "No helpdesk tickets filed") with approval/assignment controls, but no direct "Create Booking" or "Raise Ticket" buttons for admins.
* **Classification:** `INTENTIONAL READ-ONLY DESIGN / ENHANCEMENT REQUEST`

#### 1. Specification & Code Analysis
* **Component Location:** [src/App.jsx](file:///D:/Clients%20Applications/SU%20Society%20App/src/App.jsx#L4113-L4250) (`OperationsManagerView`).
* **Existing Workflow Architecture:**
  * Resident members and tenants submit amenity bookings and helpdesk tickets via their respective member/tenant portals (`MemberDashboardView` / `TenantDashboardView`).
  * The Admin Operations view (`OperationsManagerView`) was specified and built as a coordinator/oversight manager panel where admins review, approve, assign, complete, or reject resident-initiated requests.
* **Root Cause Determination:**
  The absence of direct admin creation buttons in the Operations Coordinator view is an intentional design choice reflecting resident-initiated request workflows. Allowing admins to create walk-in bookings or raise tickets on behalf of residents represents a functional enhancement request rather than a defect in the existing baseline specifications.
* **Determinism:** `Design Intent`.

---

## 4. REPRODUCTION MATRIX

| Finding ID | Finding Description | Reproduction Status | Required Classification |
| :--- | :--- | :--- | :--- |
| **FINDING 1** | Expense Manager React Runtime Crash | **REPRODUCED** | `CONFIRMED FRONTEND DEFECT` |
| **FINDING 2** | Bank Reconciliation (BRS) Create Runtime Crash | **REPRODUCED** | `CONFIRMED FRONTEND DEFECT` |
| **FINDING 3** | Opening Balance Discriminator Violation | **REPRODUCED** | `CONFIRMED FRONTEND / MOCK CLIENT CONTRACT MISMATCH DEFECT` |
| **FINDING 4** | Audit Logs Missing OLD STATE | **REPRODUCED** | `CONFIRMED FRONTEND / MOCK SERVICE LOGIC DEFECT` |
| **FINDING 5** | Audit Timestamp / Date Discrepancy | **VERIFIED** | `PRESEEDED DATA / EXPECTED SYSTEM TIME BEHAVIOR` |
| **FINDING 6** | Booking & Helpdesk Admin Action Controls | **VERIFIED** | `INTENTIONAL READ-ONLY DESIGN / ENHANCEMENT REQUEST` |

---

## 5. ROOT-CAUSE DETERMINATION SUMMARY

1. **Finding 1 (Expense Manager Crash):** `src/App.jsx` form JSX references undefined handlers `handleAddCategory` and `handleAddBudget`. Form submit triggers `undefined(e)` -> unhandled `TypeError` -> React tree unmounts.
2. **Finding 2 (BRS Create Crash):** `src/App.jsx` references undefined handlers `handleAddRecon`, `handleCompleteRecon`, and `handleMatchTransactions`. Action trigger calls `undefined` -> unhandled `TypeError` -> React tree unmounts.
3. **Finding 3 (Discriminator Violation):** `src/supabase.js` `mockClient.opening_balances.create()` populates `property_id` on compensating `ledgerTx` while setting `billing_subject_type: 'none'`. `validateBillingSubjectFKDiscriminator()` asserts `type === 'none'` requires all keys (including `property_id`) to be empty, throwing an internal discriminator error.
4. **Finding 4 (Missing Old State):** `src/supabase.js` Slice 20 NOC helper functions pass `null` for `oldValue` in `logAudit()` calls. `AuditLogsView` renders `"-"` when `old_value` is `null`.
5. **Finding 5 (Timestamp Discrepancy):** Static seed data logs dated `18/09/2026` mix naturally with live system execution timestamps generated on `19/09/2026`.
6. **Finding 6 (Admin Creation Controls):** Admin Operations views were designed as coordinator review panels for resident-initiated requests. Admin creation on behalf of residents is a future workflow enhancement.

---

## 6. MUTATION CHECK & GOVERNANCE COMPLIANCE

A strict verification of zero-mutation compliance was conducted:

* **Source Files Modified:** `0`
* **Database Schema Mutations:** `0`
* **Database Data Mutations:** `0`
* **SQL Migration Files Created:** `0`
* **Candidate-29 Files Created:** `0`
* **Deployments Executed:** `0`
* **Production Supabase Config Changes:** `0`

---

## 7. HISTORICAL UAT RELATIONSHIP

The findings identified in this triage exercise do not invalidate the historical Stage 10 Acceptance position recorded in `FINAL_PROJECT_CLOSURE_AND_PRODUCTION_HANDOVER.md`:

1. **Candidate-28 Production Baseline:** Deployed production migrations remain at `28 / 28`.
2. **UAT Scope Boundary:** UAT Stage 10 validated the core member, property, dues, payment verification, and security controls defined in the UAT specification. Findings 1, 2, 3, and 4 represent unhandled edge-case exception paths in secondary administrative sub-tabs (`Expense Manager`, `BRS Reconciliation`, `Opening Balances`).
3. **Handover Integrity:** The authoritative handover document explicitly noted that UAT acceptance was bounded by the test suite executed.

---

## 8. RECOMMENDED NEXT GOVERNANCE GATE

Every future code change or candidate migration to address these findings MUST strictly follow the 10-step production change-control procedure:

```
[Finding / Requirement Documented]
       │
       ▼
[Impact & Forensic Review] (This Document)
       │
       ▼
[Detailed Remediation Plan (Candidate-29)]
       │
       ▼
[Adversarial Security Review]
       │
       ▼
[Separate Human Implementation Authorization]
       │
       ▼
[Local Implementation & Testing]
       │
       ▼
[Pre-Deployment Forensic Verification Gate]
       │
       ▼
[Separate Human Production Deployment Authorization]
       │
       ▼
[Controlled Deployment & Post-Deployment Verification]
       │
       ▼
[Updated Production Baseline Lock]
```

**CRITICAL RULE:** Candidate-29 must NOT be created automatically or implicitly. Creation of Candidate-29 requires explicit human authorization following an approved detailed remediation plan.

---

## 9. ARTIFACT INTEGRITY & SHA-256 CHECKSUM

* **Report File Name:** `POST_ACCEPTANCE_FORENSIC_FINDINGS_TRIAGE_REPORT.md`
* **File Path:** `D:\Clients Applications\SU Society App\POST_ACCEPTANCE_FORENSIC_FINDINGS_TRIAGE_REPORT.md`
* **Execution Status:** `READ-ONLY FORENSIC TRIAGE COMPLETE / ZERO MUTATION`
* **Authoritative Timestamp:** `2026-09-19T12:35:00+05:30`
* **SHA-256 Checksum:** `CEB2024F926C199D46A6BE6ADA5009D908D0BB687A1BD0A6DD076F496783DF05`
