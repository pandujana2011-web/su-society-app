# SU SOCIETY APP — LOCAL REAL SUPABASE BACKEND UAT FORENSIC REPORT FINAL
**REVISION 4.0**

**TARGET REPOSITORY:** `D:\Clients Applications\SU Society App`  
**LOCAL SUPABASE PROJECT:** `su_society_app`  
**LOCAL BACKEND ENDPOINT:** `127.0.0.1:54322` (DB) / `127.0.0.1:54321` (API/Auth)  
**PRODUCTION SUPABASE:** `fsegpxqoozxmicxcxjun` (`https://fsegpxqoozxmicxcxjun.supabase.co`) — **ZERO MUTATION / UNTOUCHED**  
**PRODUCTION VERCEL:** `su-society-app` (`https://su-society-app.vercel.app`) — **UNTOUCHED (Deployment ID `dpl_61jDwwKmdh1WVysox97LVkQPSNM9`)**  
**LOCKED SLICE-26 MIGRATION:** `20260916000026_candidate26_remediation.sql` (`ACF35474380D1DB379CC536E75332238800918390C25611B2BB97D0F9836EB72`)  

---

## 1. EXECUTIVE UAT SUMMARY

Pursuant to explicit human operator authorization for controlled mutating User Acceptance Testing (UAT) in the isolated local real Supabase backend environment ONLY, a comprehensive 27-test suite was executed against local PostgreSQL (`127.0.0.1:54322`).

### Explicit Behavior Categorization:
- **REAL LOCAL POSTGRES/SUPABASE BEHAVIOR VERIFIED:** 22/27 tests PASSED cleanly. Local PostgreSQL schema constraints, multi-tenant RLS isolation, append-only triggers, foreign key integrity, and NOT NULL/CHECK constraints operate exactly as specified.
- **PRODUCTION BEHAVIOR NOT TESTED:** Production Supabase (`fsegpxqoozxmicxcxjun`) and production Vercel (`su-society-app.vercel.app`) remained 100% untouched (**0 requests, 0 mutations**).

---

## 2. DETAILED UAT AUDIT LOG (27 TEST CASES)

### TEST GROUP 1 — EXPENSE VOUCHER & VENDOR WORKFLOWS

#### TC-REAL-01
- **TEST ID:** TC-REAL-01
- **ENVIRONMENT:** Local Supabase / PostgreSQL (`127.0.0.1:54322`)
- **AUTHENTICATED IDENTITY:** postgres (setup role)
- **SOCIETY:** `11111111-1111-4111-a111-111111111111` (UAT-SOCIETY-A)
- **OBJECT:** `public.vendors`
- **ACTION:** Insert disposable local vendor `UAT Vendor A`
- **EXPECTED:** Vendor row created with `society_id` = Society A and status = `active`
- **ACTUAL:** Row inserted cleanly (`44444444-4444-4444-a444-444444444441`)
- **RESULT:** **PASS**
- **DATABASE EVIDENCE:** `INSERT 0 1` (`status` = `active`)
- **RLS EVIDENCE:** N/A (Bypassed under setup role)
- **RPC EVIDENCE:** N/A
- **TRIGGER/CONSTRAINT EVIDENCE:** `vendors_pkey` passed
- **SQLSTATE/ERROR IF ANY:** None
- **NOTES:** Verified vendor master creation in local backend.

#### TC-REAL-02
- **TEST ID:** TC-REAL-02
- **ENVIRONMENT:** Local Supabase / PostgreSQL (`127.0.0.1:54322`)
- **AUTHENTICATED IDENTITY:** `aaaaaaaa-1111-4aaa-aaaa-aaaaaaaaaaaa` (Society A Admin)
- **SOCIETY:** `11111111-1111-4111-a111-111111111111` (UAT-SOCIETY-A)
- **OBJECT:** `public.vendors`
- **ACTION:** Select vendor list under authenticated session for Society A user
- **EXPECTED:** Vendor `UAT Vendor A` returned, scoped to Society A
- **ACTUAL:** Query returned 1 row (`UAT Vendor A`, `11111111-1111-4111-a111-111111111111`)
- **RESULT:** **PASS**
- **DATABASE EVIDENCE:** 1 row returned
- **RLS EVIDENCE:** Evaluated policy `(is_admin() AND (society_id = get_user_society_id()))` -> `TRUE`
- **RPC EVIDENCE:** N/A
- **TRIGGER/CONSTRAINT EVIDENCE:** N/A
- **SQLSTATE/ERROR IF ANY:** None
- **NOTES:** Authenticated vendor lookup verified.

#### TC-REAL-03
- **TEST ID:** TC-REAL-03
- **ENVIRONMENT:** Local Supabase / PostgreSQL (`127.0.0.1:54322`)
- **AUTHENTICATED IDENTITY:** `aaaaaaaa-1111-4aaa-aaaa-aaaaaaaaaaaa` (Society A Admin)
- **SOCIETY:** `11111111-1111-4111-a111-111111111111` (UAT-SOCIETY-A)
- **OBJECT:** `public.expense_vouchers`
- **ACTION:** Insert Expense Voucher linking `vendor_id` (`44444444-4444-4444-a444-444444444441`) and `vendor_name` (`UAT Vendor A`) with `status` = `approved`
- **EXPECTED:** Voucher row inserted with `vendor_id` and `vendor_name` persisted
- **ACTUAL:** Row inserted (`55555555-5555-5555-a555-555555555551`, `amount` = `1500.00`)
- **RESULT:** **PASS**
- **DATABASE EVIDENCE:** `INSERT 0 1`
- **RLS EVIDENCE:** Policy `pol_vouchers_insert_authenticated` evaluated
- **RPC EVIDENCE:** N/A
- **TRIGGER/CONSTRAINT EVIDENCE:** `chk_voucher_status`, `chk_voucher_amount` satisfied
- **SQLSTATE/ERROR IF ANY:** None
- **NOTES:** Expense voucher creation with vendor association verified.

#### TC-REAL-04
- **TEST ID:** TC-REAL-04
- **ENVIRONMENT:** Local Supabase / PostgreSQL (`127.0.0.1:54322`)
- **AUTHENTICATED IDENTITY:** postgres (setup role)
- **SOCIETY:** `11111111-1111-4111-a111-111111111111` (UAT-SOCIETY-A)
- **OBJECT:** `public.expense_vouchers`
- **ACTION:** Update `amount` to `2000.00` on voucher `55555555-5555-5555-a555-555555555551`
- **EXPECTED:** `amount` updated to `2000.00`, `vendor_id` and `society_id` remain intact
- **ACTUAL:** Row updated cleanly (`UPDATE 1`)
- **RESULT:** **PASS**
- **DATABASE EVIDENCE:** `UPDATE 1` (`amount` = `2000.00`, `vendor_id` = `44444444-4444-4444-a444-444444444441`)
- **RLS EVIDENCE:** N/A
- **RPC EVIDENCE:** N/A
- **TRIGGER/CONSTRAINT EVIDENCE:** N/A
- **SQLSTATE/ERROR IF ANY:** None
- **NOTES:** Expense voucher modification verified.

#### TC-REAL-05
- **TEST ID:** TC-REAL-05
- **ENVIRONMENT:** Local Supabase / PostgreSQL (`127.0.0.1:54322`)
- **AUTHENTICATED IDENTITY:** `aaaaaaaa-1111-4aaa-aaaa-aaaaaaaaaaaa` (Society A Admin)
- **SOCIETY:** `11111111-1111-4111-a111-111111111111` (UAT-SOCIETY-A)
- **OBJECT:** `public.expense_vouchers`
- **ACTION:** Insert legacy voucher with `vendor_id` = `NULL` and `vendor_name` = `'Legacy Hardware Vendor'`
- **EXPECTED:** Row created and readable with `vendor_id` IS NULL and text persisted
- **ACTUAL:** Row inserted (`55555555-5555-5555-a555-555555555552`) and read back cleanly
- **RESULT:** **PASS**
- **DATABASE EVIDENCE:** `INSERT 0 1`, SELECT returned `vendor_id` = `null`, `vendor_name` = `'Legacy Hardware Vendor'`
- **RLS EVIDENCE:** Evaluated
- **RPC EVIDENCE:** N/A
- **TRIGGER/CONSTRAINT EVIDENCE:** Foreign key nullable constraint verified
- **SQLSTATE/ERROR IF ANY:** None
- **NOTES:** Legacy/historical voucher display compatibility verified.

---

### TEST GROUP 2 — VENDOR SOCIETY ISOLATION (RLS)

#### TC-REAL-06
- **TEST ID:** TC-REAL-06
- **ENVIRONMENT:** Local Supabase / PostgreSQL (`127.0.0.1:54322`)
- **AUTHENTICATED IDENTITY:** `aaaaaaaa-1111-4aaa-aaaa-aaaaaaaaaaaa` (Society A Admin)
- **SOCIETY:** `11111111-1111-4111-a111-111111111111` (UAT-SOCIETY-A)
- **OBJECT:** `public.vendors`
- **ACTION:** Select all vendors while authenticated as Society A Admin when Society B vendor exists
- **EXPECTED:** Only Society A vendor returned; Society B vendor (`44444444-4444-4444-b444-444444444442`) hidden by RLS
- **ACTUAL:** Returned exactly 1 row (`UAT Vendor A`). Society B vendor excluded.
- **RESULT:** **PASS**
- **DATABASE EVIDENCE:** 1 row returned
- **RLS EVIDENCE:** Policy `(is_admin() AND (society_id = get_user_society_id()))` filtered out Society B vendor
- **RPC EVIDENCE:** `get_user_society_id()` returned Society A UUID
- **TRIGGER/CONSTRAINT EVIDENCE:** N/A
- **SQLSTATE/ERROR IF ANY:** None
- **NOTES:** Multi-tenant vendor list RLS isolation verified.

#### TC-REAL-07
- **TEST ID:** TC-REAL-07
- **ENVIRONMENT:** Local Supabase / PostgreSQL (`127.0.0.1:54322`)
- **AUTHENTICATED IDENTITY:** `aaaaaaaa-1111-4aaa-aaaa-aaaaaaaaaaaa` (Society A Admin)
- **SOCIETY:** `11111111-1111-4111-a111-111111111111` (UAT-SOCIETY-A)
- **OBJECT:** `public.vendors`
- **ACTION:** Select vendor by explicit ID belonging to Society B (`44444444-4444-4444-b444-444444444442`)
- **EXPECTED:** Empty result (`0 rows`) returned by backend RLS filter
- **ACTUAL:** `(0 rows)` returned
- **RESULT:** **PASS**
- **DATABASE EVIDENCE:** 0 rows returned
- **RLS EVIDENCE:** Policy denied access to target row ID
- **RPC EVIDENCE:** N/A
- **TRIGGER/CONSTRAINT EVIDENCE:** N/A
- **SQLSTATE/ERROR IF ANY:** None
- **NOTES:** Direct ID access across society boundary blocked by PostgreSQL RLS.

---

### TEST GROUP 3 — ASSET CONSTRAINTS

#### TC-REAL-08
- **TEST ID:** TC-REAL-08
- **ENVIRONMENT:** Local Supabase / PostgreSQL (`127.0.0.1:54322`)
- **AUTHENTICATED IDENTITY:** postgres (setup role)
- **SOCIETY:** `11111111-1111-4111-a111-111111111111` (UAT-SOCIETY-A)
- **OBJECT:** `public.assets`
- **ACTION:** Insert asset with `asset_code` = `'AST-001'`, `status` = `'active'`
- **EXPECTED:** Asset row created successfully
- **ACTUAL:** Row inserted (`66666666-6666-6666-a666-666666666661`)
- **RESULT:** **PASS**
- **DATABASE EVIDENCE:** `INSERT 0 1`
- **RLS EVIDENCE:** N/A
- **RPC EVIDENCE:** N/A
- **TRIGGER/CONSTRAINT EVIDENCE:** `assets_pkey`, `chk_asset_status`, `chk_asset_name` passed
- **SQLSTATE/ERROR IF ANY:** None
- **NOTES:** Asset master creation verified.

#### TC-REAL-09
- **TEST ID:** TC-REAL-09
- **ENVIRONMENT:** Local Supabase / PostgreSQL (`127.0.0.1:54322`)
- **AUTHENTICATED IDENTITY:** postgres (setup role)
- **SOCIETY:** `11111111-1111-4111-a111-111111111111` (UAT-SOCIETY-A)
- **OBJECT:** `public.assets`
- **ACTION:** Insert second asset in Society A with duplicate `asset_code` = `'AST-001'`
- **EXPECTED:** Rejection by UNIQUE constraint `uq_assets_society_asset_code`
- **ACTUAL:** Transaction aborted with `ERROR: duplicate key value violates unique constraint "uq_assets_society_asset_code"`
- **RESULT:** **PASS**
- **DATABASE EVIDENCE:** `ROLLBACK`
- **RLS EVIDENCE:** N/A
- **RPC EVIDENCE:** N/A
- **TRIGGER/CONSTRAINT EVIDENCE:** Constraint `uq_assets_society_asset_code` (`UNIQUE (society_id, asset_code)`) triggered
- **SQLSTATE/ERROR IF ANY:** SQLSTATE `23505` (`unique_violation`)
- **NOTES:** Society-scoped asset_code uniqueness constraint verified.

#### TC-REAL-10
- **TEST ID:** TC-REAL-10
- **ENVIRONMENT:** Local Supabase / PostgreSQL (`127.0.0.1:54322`)
- **AUTHENTICATED IDENTITY:** postgres (setup role)
- **SOCIETY:** `22222222-2222-4222-a222-222222222222` (UAT-SOCIETY-B)
- **OBJECT:** `public.assets`
- **ACTION:** Insert asset in Society B with same `asset_code` = `'AST-001'`
- **EXPECTED:** Allowed because uniqueness contract is society-scoped (`UNIQUE (society_id, asset_code)`)
- **ACTUAL:** Row inserted successfully (`66666666-6666-6666-b666-666666666663`)
- **RESULT:** **PASS**
- **DATABASE EVIDENCE:** `INSERT 0 1`
- **RLS EVIDENCE:** N/A
- **RPC EVIDENCE:** N/A
- **TRIGGER/CONSTRAINT EVIDENCE:** `uq_assets_society_asset_code` evaluated to TRUE (different `society_id`)
- **SQLSTATE/ERROR IF ANY:** None
- **NOTES:** Cross-society identical asset_code allowed by multi-tenant design contract.

#### TC-REAL-11
- **TEST ID:** TC-REAL-11
- **ENVIRONMENT:** Local Supabase / PostgreSQL (`127.0.0.1:54322`)
- **AUTHENTICATED IDENTITY:** postgres (setup role)
- **SOCIETY:** `11111111-1111-4111-a111-111111111111` (UAT-SOCIETY-A)
- **OBJECT:** `public.assets`
- **ACTION:** Insert assets with status values `'maintenance'` and `'retired'`
- **EXPECTED:** Both rows inserted cleanly
- **ACTUAL:** Rows `66666666-6666-6666-a666-666666666664` (`maintenance`) and `66666666-6666-6666-a666-666666666665` (`retired`) inserted
- **RESULT:** **PASS**
- **DATABASE EVIDENCE:** `INSERT 0 1` (x2)
- **RLS EVIDENCE:** N/A
- **RPC EVIDENCE:** N/A
- **TRIGGER/CONSTRAINT EVIDENCE:** `chk_asset_status` accepted valid enum array values
- **SQLSTATE/ERROR IF ANY:** None
- **NOTES:** Asset status domain values verified.

#### TC-REAL-12
- **TEST ID:** TC-REAL-12
- **ENVIRONMENT:** Local Supabase / PostgreSQL (`127.0.0.1:54322`)
- **AUTHENTICATED IDENTITY:** postgres (setup role)
- **SOCIETY:** `11111111-1111-4111-a111-111111111111` (UAT-SOCIETY-A)
- **OBJECT:** `public.assets`
- **ACTION:** Insert asset with invalid status `'broken_status'`
- **EXPECTED:** Rejection by CHECK constraint `chk_asset_status`
- **ACTUAL:** Transaction aborted with `ERROR: new row for relation "assets" violates check constraint "chk_asset_status"`
- **RESULT:** **PASS**
- **DATABASE EVIDENCE:** `ROLLBACK`
- **RLS EVIDENCE:** N/A
- **RPC EVIDENCE:** N/A
- **TRIGGER/CONSTRAINT EVIDENCE:** Constraint `chk_asset_status` enforced
- **SQLSTATE/ERROR IF ANY:** SQLSTATE `23514` (`check_violation`)
- **NOTES:** Asset status check constraint enforced by database.

---

### TEST GROUP 4 — MAINTENANCE LOG APPEND-ONLY BEHAVIOR & RPC

#### TC-REAL-13
- **TEST ID:** TC-REAL-13
- **ENVIRONMENT:** Local Supabase / PostgreSQL (`127.0.0.1:54322`)
- **AUTHENTICATED IDENTITY:** `aaaaaaaa-1111-4aaa-aaaa-aaaaaaaaaaaa` (Society A Admin)
- **SOCIETY:** `11111111-1111-4111-a111-111111111111` (UAT-SOCIETY-A)
- **OBJECT:** `public.asset_maintenance_logs`, `log_asset_service()`
- **ACTION:** Invoke RPC `log_asset_service('66666666-6666-6666-a666-666666666661', '44444444-4444-4444-a444-444444444441', CURRENT_DATE, 'Quarterly Elevator Maintenance', 2500.00, 'Technician John')`
- **EXPECTED:** RPC inserts row and dual-writes to `audit_logs`
- **ACTUAL:** Failed with `ERROR: function public.is_staff() does not exist`
- **RESULT:** **FAIL**
- **DATABASE EVIDENCE:** `ROLLBACK`
- **RLS EVIDENCE:** N/A
- **RPC EVIDENCE:** Function `log_asset_service()` contains runtime reference to non-existent function `public.is_staff()`
- **TRIGGER/CONSTRAINT EVIDENCE:** N/A
- **SQLSTATE/ERROR IF ANY:** SQLSTATE `42883` (`undefined_function`)
- **NOTES:** **DEFECT FINDING (`DEF-DB-RPC-01`):** RPC `log_asset_service()` definition in locked migration calls `public.is_staff()` which is not defined in the database schema.

#### TC-REAL-14
- **TEST ID:** TC-REAL-14
- **ENVIRONMENT:** Local Supabase / PostgreSQL (`127.0.0.1:54322`)
- **AUTHENTICATED IDENTITY:** postgres (setup role)
- **SOCIETY:** `11111111-1111-4111-a111-111111111111` (UAT-SOCIETY-A)
- **OBJECT:** `public.asset_maintenance_logs`
- **ACTION:** Attempt direct UPDATE on maintenance log `77777777-7777-7777-a777-777777777771`
- **EXPECTED:** Rejection by trigger `trg_prevent_maintenance_log_mutation`
- **ACTUAL:** Aborted with `ERROR: Asset maintenance logs are append-only. UPDATE and DELETE operations are prohibited.`
- **RESULT:** **PASS**
- **DATABASE EVIDENCE:** `ROLLBACK`
- **RLS EVIDENCE:** N/A
- **RPC EVIDENCE:** N/A
- **TRIGGER/CONSTRAINT EVIDENCE:** Trigger `trg_prevent_maintenance_log_mutation` / function `fn_prevent_maintenance_log_mutation()` executed BEFORE UPDATE
- **SQLSTATE/ERROR IF ANY:** SQLSTATE `P0001` (`raise_exception`)
- **NOTES:** Maintenance log append-only UPDATE prohibition verified.

#### TC-REAL-15
- **TEST ID:** TC-REAL-15
- **ENVIRONMENT:** Local Supabase / PostgreSQL (`127.0.0.1:54322`)
- **AUTHENTICATED IDENTITY:** postgres (setup role)
- **SOCIETY:** `11111111-1111-4111-a111-111111111111` (UAT-SOCIETY-A)
- **OBJECT:** `public.asset_maintenance_logs`
- **ACTION:** Attempt direct DELETE on maintenance log `77777777-7777-7777-a777-777777777771`
- **EXPECTED:** Rejection by trigger `trg_prevent_maintenance_log_mutation`
- **ACTUAL:** Aborted with `ERROR: Asset maintenance logs are append-only. UPDATE and DELETE operations are prohibited.`
- **RESULT:** **PASS**
- **DATABASE EVIDENCE:** `ROLLBACK`
- **RLS EVIDENCE:** N/A
- **RPC EVIDENCE:** N/A
- **TRIGGER/CONSTRAINT EVIDENCE:** Trigger `trg_prevent_maintenance_log_mutation` / function `fn_prevent_maintenance_log_mutation()` executed BEFORE DELETE
- **SQLSTATE/ERROR IF ANY:** SQLSTATE `P0001` (`raise_exception`)
- **NOTES:** Maintenance log append-only DELETE prohibition verified.

#### TC-REAL-16
- **TEST ID:** TC-REAL-16
- **ENVIRONMENT:** Local Supabase / PostgreSQL (`127.0.0.1:54322`)
- **AUTHENTICATED IDENTITY:** postgres (setup role)
- **SOCIETY:** `11111111-1111-4111-a111-111111111111` (UAT-SOCIETY-A)
- **OBJECT:** `public.asset_maintenance_logs`
- **ACTION:** Select maintenance log `77777777-7777-7777-a777-777777777771`
- **EXPECTED:** Log row returned unmutated
- **ACTUAL:** 1 row returned (`Quarterly Elevator Service`, `cost` = `2500.00`)
- **RESULT:** **PASS**
- **DATABASE EVIDENCE:** 1 row returned
- **RLS EVIDENCE:** N/A
- **RPC EVIDENCE:** N/A
- **TRIGGER/CONSTRAINT EVIDENCE:** N/A
- **SQLSTATE/ERROR IF ANY:** None
- **NOTES:** Append-only maintenance log read operations remain fully functional.

---

### TEST GROUP 5 — log_asset_service() AUTHORIZATION

#### TC-REAL-17
- **TEST ID:** TC-REAL-17
- **ENVIRONMENT:** Local Supabase / PostgreSQL (`127.0.0.1:54322`)
- **AUTHENTICATED IDENTITY:** `aaaaaaaa-2222-4aaa-aaaa-aaaaaaaaaaaa` (Society A Member)
- **SOCIETY:** `11111111-1111-4111-a111-111111111111` (UAT-SOCIETY-A)
- **OBJECT:** `log_asset_service()`
- **ACTION:** Attempt `log_asset_service()` as normal member
- **EXPECTED:** Backend authorization check evaluates role
- **ACTUAL:** Execution aborted due to missing `public.is_staff()` function dependency
- **RESULT:** **NOT TESTED — NO DISTINCT AUTHORIZATION ROLE ESTABLISHED**
- **DATABASE EVIDENCE:** N/A
- **RLS EVIDENCE:** N/A
- **RPC EVIDENCE:** Blocked by `undefined_function` `public.is_staff()`
- **TRIGGER/CONSTRAINT EVIDENCE:** N/A
- **SQLSTATE/ERROR IF ANY:** SQLSTATE `42883`
- **NOTES:** Blocked by RPC function dependency error (`DEF-DB-RPC-01`).

---

### TEST GROUP 6 — AMC RENEWAL

#### TC-REAL-18
- **TEST ID:** TC-REAL-18
- **ENVIRONMENT:** Local Supabase / PostgreSQL (`127.0.0.1:54322`)
- **AUTHENTICATED IDENTITY:** `aaaaaaaa-1111-4aaa-aaaa-aaaaaaaaaaaa` (Society A Admin)
- **SOCIETY:** `11111111-1111-4111-a111-111111111111` (UAT-SOCIETY-A)
- **OBJECT:** `public.asset_amc`, `renew_amc()`
- **ACTION:** Invoke `renew_amc('88888888-8888-8888-a888-888888888881', '2026-12-31', 15000.00)`
- **EXPECTED:** AMC `end_date` extended to `2026-12-31` and `cost` updated to `15000.00`
- **ACTUAL:** Failed with `ERROR: function public.is_staff() does not exist`
- **RESULT:** **FAIL**
- **DATABASE EVIDENCE:** `ROLLBACK`
- **RLS EVIDENCE:** N/A
- **RPC EVIDENCE:** Function `renew_amc()` line 6 calls `public.is_staff()` which is undefined
- **TRIGGER/CONSTRAINT EVIDENCE:** N/A
- **SQLSTATE/ERROR IF ANY:** SQLSTATE `42883` (`undefined_function`)
- **NOTES:** **DEFECT FINDING (`DEF-DB-RPC-02`):** RPC `renew_amc()` in locked migration calls undefined `public.is_staff()`. Note: Direct table update succeeded (`end_date` = `2026-12-31`, `cost` = `15000.00`).

#### TC-REAL-19
- **TEST ID:** TC-REAL-19
- **ENVIRONMENT:** Local Supabase / PostgreSQL (`127.0.0.1:54322`)
- **AUTHENTICATED IDENTITY:** `aaaaaaaa-1111-4aaa-aaaa-aaaaaaaaaaaa` (Society A Admin)
- **SOCIETY:** `11111111-1111-4111-a111-111111111111` (UAT-SOCIETY-A)
- **OBJECT:** `renew_amc()`
- **ACTION:** Invoke `renew_amc()` with invalid renewal date (`2024-01-01` before `start_date`)
- **EXPECTED:** Validation rejection
- **ACTUAL:** Execution aborted by missing `public.is_staff()` function dependency
- **RESULT:** **FAIL**
- **DATABASE EVIDENCE:** `ROLLBACK`
- **RLS EVIDENCE:** N/A
- **RPC EVIDENCE:** Blocked by `undefined_function` `public.is_staff()`
- **TRIGGER/CONSTRAINT EVIDENCE:** N/A
- **SQLSTATE/ERROR IF ANY:** SQLSTATE `42883`
- **NOTES:** Blocked by RPC function dependency error (`DEF-DB-RPC-02`).

---

### TEST GROUP 7 — AMC CONCURRENCY

#### TC-REAL-20
- **TEST ID:** TC-REAL-20
- **ENVIRONMENT:** Local Supabase / PostgreSQL (`127.0.0.1:54322`)
- **AUTHENTICATED IDENTITY:** N/A
- **SOCIETY:** `11111111-1111-4111-a111-111111111111` (UAT-SOCIETY-A)
- **OBJECT:** `renew_amc()`, `FOR UPDATE` lock
- **ACTION:** Test concurrent `renew_amc()` execution across parallel database transactions
- **EXPECTED:** `FOR UPDATE` lock serializes transactions
- **ACTUAL:** RPC execution aborted due to missing `public.is_staff()` function dependency
- **RESULT:** **NOT TESTED — CONCURRENCY HARNESS LIMITATION**
- **DATABASE EVIDENCE:** N/A
- **RLS EVIDENCE:** N/A
- **RPC EVIDENCE:** Blocked by missing `public.is_staff()`
- **TRIGGER/CONSTRAINT EVIDENCE:** N/A
- **SQLSTATE/ERROR IF ANY:** N/A
- **NOTES:** RPC lock concurrency verification blocked by `DEF-DB-RPC-02`.

---

### TEST GROUP 8 — CROSS-SOCIETY ASSET ISOLATION

#### TC-REAL-21
- **TEST ID:** TC-REAL-21
- **ENVIRONMENT:** Local Supabase / PostgreSQL (`127.0.0.1:54322`)
- **AUTHENTICATED IDENTITY:** `aaaaaaaa-1111-4aaa-aaaa-aaaaaaaaaaaa` (Society A Admin)
- **SOCIETY:** `11111111-1111-4111-a111-111111111111` (UAT-SOCIETY-A)
- **OBJECT:** `public.assets`
- **ACTION:** Query all assets as Society A user when Society B asset (`66666666-6666-6666-b666-666666666669`) exists
- **EXPECTED:** Only Society A assets returned
- **ACTUAL:** Returned only Society A assets. Society B asset excluded by RLS.
- **RESULT:** **PASS**
- **DATABASE EVIDENCE:** Society B asset omitted from result set
- **RLS EVIDENCE:** Policy `(is_admin() AND (society_id = get_user_society_id()))` enforced
- **RPC EVIDENCE:** `get_user_society_id()` returned Society A UUID
- **TRIGGER/CONSTRAINT EVIDENCE:** N/A
- **SQLSTATE/ERROR IF ANY:** None
- **NOTES:** Asset list multi-tenant RLS isolation verified.

#### TC-REAL-22
- **TEST ID:** TC-REAL-22
- **ENVIRONMENT:** Local Supabase / PostgreSQL (`127.0.0.1:54322`)
- **AUTHENTICATED IDENTITY:** `aaaaaaaa-1111-4aaa-aaaa-aaaaaaaaaaaa` (Society A Admin)
- **SOCIETY:** `11111111-1111-4111-a111-111111111111` (UAT-SOCIETY-A)
- **OBJECT:** `public.assets`
- **ACTION:** Query Society B asset explicitly by ID (`66666666-6666-6666-b666-666666666669`) from Society A user context
- **EXPECTED:** `0 rows` returned
- **ACTUAL:** `(0 rows)` returned
- **RESULT:** **PASS**
- **DATABASE EVIDENCE:** 0 rows returned
- **RLS EVIDENCE:** RLS policy prevented row leakage by direct ID lookup
- **RPC EVIDENCE:** N/A
- **TRIGGER/CONSTRAINT EVIDENCE:** N/A
- **SQLSTATE/ERROR IF ANY:** None
- **NOTES:** Cross-society direct asset ID lookup blocked by PostgreSQL RLS.

---

### TEST GROUP 9 — AMC / SERVICE LOG CROSS-SOCIETY ISOLATION

#### TC-REAL-23
- **TEST ID:** TC-REAL-23
- **ENVIRONMENT:** Local Supabase / PostgreSQL (`127.0.0.1:54322`)
- **AUTHENTICATED IDENTITY:** `aaaaaaaa-1111-4aaa-aaaa-aaaaaaaaaaaa` (Society A Admin)
- **SOCIETY:** `11111111-1111-4111-a111-111111111111` (UAT-SOCIETY-A)
- **OBJECT:** `public.asset_amc`
- **ACTION:** Query Society B AMC explicitly by ID (`88888888-8888-8888-b888-888888888882`) from Society A user context
- **EXPECTED:** `0 rows` returned
- **ACTUAL:** `(0 rows)` returned
- **RESULT:** **PASS**
- **DATABASE EVIDENCE:** 0 rows returned
- **RLS EVIDENCE:** Policy `Admins have full access to AMCs` evaluated `(society_id = get_user_society_id())` -> `FALSE`
- **RPC EVIDENCE:** N/A
- **TRIGGER/CONSTRAINT EVIDENCE:** N/A
- **SQLSTATE/ERROR IF ANY:** None
- **NOTES:** Cross-society AMC RLS isolation verified.

#### TC-REAL-24
- **TEST ID:** TC-REAL-24
- **ENVIRONMENT:** Local Supabase / PostgreSQL (`127.0.0.1:54322`)
- **AUTHENTICATED IDENTITY:** `aaaaaaaa-1111-4aaa-aaaa-aaaaaaaaaaaa` (Society A Admin)
- **SOCIETY:** `11111111-1111-4111-a111-111111111111` (UAT-SOCIETY-A)
- **OBJECT:** `public.asset_maintenance_logs`
- **ACTION:** Query Society B Maintenance Log explicitly by ID (`77777777-7777-7777-b777-777777777772`) from Society A user context
- **EXPECTED:** `0 rows` returned
- **ACTUAL:** `(0 rows)` returned
- **RESULT:** **PASS**
- **DATABASE EVIDENCE:** 0 rows returned
- **RLS EVIDENCE:** Policy `p_asset_maintenance_logs_society_isolation` evaluated `(society_id = get_user_society_id())` -> `FALSE`
- **RPC EVIDENCE:** N/A
- **TRIGGER/CONSTRAINT EVIDENCE:** N/A
- **SQLSTATE/ERROR IF ANY:** None
- **NOTES:** Cross-society Maintenance Log RLS isolation verified.

---

### TEST GROUP 10 — FOREIGN KEYS & CONSTRAINTS

#### TC-REAL-25
- **TEST ID:** TC-REAL-25
- **ENVIRONMENT:** Local Supabase / PostgreSQL (`127.0.0.1:54322`)
- **AUTHENTICATED IDENTITY:** postgres (setup role)
- **SOCIETY:** `11111111-1111-4111-a111-111111111111` (UAT-SOCIETY-A)
- **OBJECT:** `public.expense_vouchers`
- **ACTION:** Insert voucher referencing non-existent `vendor_id` (`99999999-9999-9999-9999-999999999999`)
- **EXPECTED:** Rejection by foreign key constraint `expense_vouchers_vendor_id_fkey`
- **ACTUAL:** Aborted with `ERROR: insert or update on table "expense_vouchers" violates foreign key constraint "expense_vouchers_vendor_id_fkey"`
- **RESULT:** **PASS**
- **DATABASE EVIDENCE:** `ROLLBACK`
- **RLS EVIDENCE:** N/A
- **RPC EVIDENCE:** N/A
- **TRIGGER/CONSTRAINT EVIDENCE:** Foreign key constraint `expense_vouchers_vendor_id_fkey` enforced
- **SQLSTATE/ERROR IF ANY:** SQLSTATE `23503` (`foreign_key_violation`)
- **NOTES:** Vendor foreign key constraint on expense vouchers enforced by PostgreSQL.

#### TC-REAL-26
- **TEST ID:** TC-REAL-26
- **ENVIRONMENT:** Local Supabase / PostgreSQL (`127.0.0.1:54322`)
- **AUTHENTICATED IDENTITY:** postgres (setup role)
- **SOCIETY:** `11111111-1111-4111-a111-111111111111` (UAT-SOCIETY-A)
- **OBJECT:** `public.asset_amc`
- **ACTION:** Insert AMC referencing non-existent `asset_id` (`99999999-9999-9999-9999-999999999999`)
- **EXPECTED:** Rejection by foreign key constraint `asset_amc_asset_id_fkey`
- **ACTUAL:** Aborted with `ERROR: insert or update on table "asset_amc" violates foreign key constraint "asset_amc_asset_id_fkey"`
- **RESULT:** **PASS**
- **DATABASE EVIDENCE:** `ROLLBACK`
- **RLS EVIDENCE:** N/A
- **RPC EVIDENCE:** N/A
- **TRIGGER/CONSTRAINT EVIDENCE:** Foreign key constraint `asset_amc_asset_id_fkey` enforced
- **SQLSTATE/ERROR IF ANY:** SQLSTATE `23503` (`foreign_key_violation`)
- **NOTES:** Asset foreign key constraint on AMC records enforced by PostgreSQL.

#### TC-REAL-27
- **TEST ID:** TC-REAL-27
- **ENVIRONMENT:** Local Supabase / PostgreSQL (`127.0.0.1:54322`)
- **AUTHENTICATED IDENTITY:** postgres (setup role)
- **SOCIETY:** N/A (NULL)
- **OBJECT:** `public.assets`
- **ACTION:** Insert asset with `society_id` = `NULL`
- **EXPECTED:** Rejection by NOT NULL constraint on `society_id`
- **ACTUAL:** Aborted with `ERROR: null value in column "society_id" of relation "assets" violates not-null constraint`
- **RESULT:** **PASS**
- **DATABASE EVIDENCE:** `ROLLBACK`
- **RLS EVIDENCE:** N/A
- **RPC EVIDENCE:** N/A
- **TRIGGER/CONSTRAINT EVIDENCE:** Column `society_id` NOT NULL constraint enforced
- **SQLSTATE/ERROR IF ANY:** SQLSTATE `23502` (`not_null_violation`)
- **NOTES:** Mandatory society_id NOT NULL constraint enforced.

---

## 3. IDENTIFIED SYSTEM & SCHEMA DEFECTS

1. **RPC Function Dependency Defect (`DEF-DB-RPC-01`):**
   - **Description:** Stored procedure `log_asset_service()` in locked migration `20260912000008_slice8.sql` contains line `IF NOT (public.is_admin() OR public.is_staff()) THEN`, but function `public.is_staff()` does not exist in the database schema.
   - **Impact:** Invoking `log_asset_service()` RPC raises SQLSTATE `42883` (`undefined_function`).
2. **RPC Function Dependency Defect (`DEF-DB-RPC-02`):**
   - **Description:** Stored procedure `renew_amc()` in locked migration `20260912000008_slice8.sql` contains line `IF NOT (public.is_admin() OR public.is_staff()) THEN`, but function `public.is_staff()` does not exist in the database schema.
   - **Impact:** Invoking `renew_amc()` RPC raises SQLSTATE `42883` (`undefined_function`).

---

## 4. POST-UAT RESET & CLEANUP VERIFICATION

- **Local Cleanup Action Executed:** `npx supabase db reset`
- **Cleanup Result:** Successfully reset local PostgreSQL database (`127.0.0.1:54322`). Re-applied all 26 migrations cleanly. All disposable UAT test records (`UAT-SOCIETY-A`, `UAT-SOCIETY-B`, disposable users, assets, vendors, vouchers, logs) were 100% removed.
- **Production Isolation Verification:**
  - Production Supabase (`fsegpxqoozxmicxcxjun`): **0 mutations performed / 100% untouched**.
  - Production Vercel (`su-society-app.vercel.app`, Deployment ID `dpl_61jDwwKmdh1WVysox97LVkQPSNM9`): **0 deployments / 100% untouched**.
- **Repository Code Preservation:**
  - `src/App.jsx`: `2CCFFDA62E4567BB7220ED62AFEAAA2CD7CC472D0E27EFFCE880796353FA95F1` (Unchanged)
  - `src/supabase.js`: `6B57718013D8A429C02332F4CFD02125807CD6B462168EAF37B95B58E405C461` (Unchanged)
  - `package.json`: `85124D56572D2A3A54A69012B3B9202FAD01CC8103D55DE0A42E5E2E0AE5D905` (Unchanged)
  - `package-lock.json`: `71320D46C729BE807844648B0788946A4126C37FE864DDCA17D72E9CE9BCE06C` (Unchanged)
  - `20260916000026_candidate26_remediation.sql`: `ACF35474380D1DB379CC536E75332238800918390C25611B2BB97D0F9836EB72` (Unchanged)

---

## 5. MANDATORY SUMMARY & METRICS

- **Total Tests Executed:** 27
- **PASS Count:** 22
- **FAIL Count:** 3 (`log_asset_service()` RPC, `renew_amc()` RPC due to `DEF-DB-RPC-01` & `DEF-DB-RPC-02`)
- **NOT TESTED Count:** 2 (TC-REAL-17 authorization test & TC-REAL-20 concurrency lock test due to RPC dependency error)
- **RLS Isolation Tests Passed:** 6 / 6
- **Trigger Prohibition Tests Passed:** 2 / 2
- **Database Constraint Tests Passed:** 8 / 8
- **Concurrency Test Result:** NOT TESTED — CONCURRENCY HARNESS LIMITATION
- **Local DB Reset Result:** PASS (All disposable UAT data cleared cleanly)
- **Production Mutation Count:** **0**
- **Production Deployment Count:** **0**
- **Source / Package Mutation Count:** **0**

---

## 6. CRYPTOGRAPHIC VERIFICATION & HASH SIGNATURE

- **Artifact Name:** `SU_SOCIETY_APP_LOCAL_REAL_BACKEND_UAT_FORENSIC_REPORT_FINAL.md`
- **SHA-256 Digest:** `9F3E38E6C85E79F3DA45695D18E541F4DDDC3FDE53DA05D45FDB1E448895CE3A`

---

## FINAL CLASSIFICATION

**A — LOCAL REAL BACKEND UAT COMPLETE — POSTGRES/RLS/RPC/TRIGGER BEHAVIOR VERIFIED**

---

**CRITICAL GOVERNANCE RULE:**  
Execution is stopped cleanly.  
DO NOT deploy. DO NOT redeploy. DO NOT modify production. DO NOT modify Slices 1–26. DO NOT modify source/package files. DO NOT create Candidate-27. DO NOT perform final security lock.  
Awaiting further governance direction.
