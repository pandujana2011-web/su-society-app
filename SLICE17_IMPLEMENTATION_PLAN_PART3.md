# SLICE 17 — FINAL IMPLEMENTATION PLAN (PART 3 OF 3)

**Document Title:** Slice 17 Final Implementation Plan — Part 3: Complete Assertion Inventory, Immutability & Gate Status  
**Document Version:** 3.1.0  
**Date:** 2026-09-04  
**Status:** PLAN-ONLY / PENDING FINAL USER IMPLEMENTATION APPROVAL  
**Implementation Authorization:** NONE — NO IMPLEMENTATION MAY BEGIN  
**Cumulative Locked Baseline:** Slices 1–16 = 469/469 PASS (100% LOCKED)  

---

## 14. COMPLETE AUTHORITATIVE ASSERTION INVENTORY (ASSERTIONS 1 THROUGH 82)

All 82 planned assertions are explicitly specified in exact sequential order:

1. **Assertion 1:** Authorized resident issues gate pass via `issue_gate_pass(...)`. (Actor: Resident, SQLSTATE `00000`, 1 row)
2. **Assertion 2:** Direct client SQL `INSERT` into `gate_passes` blocked by RESTRICTIVE RLS `pol_gate_passes_restrictive_insert`. (Actor: Client, SQLSTATE `42501`, 0 rows)
3. **Assertion 3:** Direct client SQL `UPDATE` on `gate_passes` status blocked by RESTRICTIVE RLS / trigger `trg_prevent_direct_gate_pass_update`. (Actor: Client, SQLSTATE `00000`, 0 rows updated)
4. **Assertion 4:** Direct client SQL `DELETE` on `gate_passes` blocked by RESTRICTIVE RLS `pol_gate_passes_restrictive_delete`. (Actor: Client, SQLSTATE `00000`, 0 rows deleted)
5. **Assertion 5:** Direct client SQL `SELECT` cross-property on `gate_passes` returns 0 rows (`pol_gate_passes_owner_select`). (Actor: Resident P1, SQLSTATE `00000`, 0 rows)
6. **Assertion 6:** Forged property gate pass issuance via function rejected. (Actor: Resident P1, SQLSTATE `42501`, 0 rows)
7. **Assertion 7:** Admin transitions gate pass status (`pending` -> `active` -> `suspended`). (Actor: Admin, SQLSTATE `00000`, 1 row)
8. **Assertion 8:** Invalid date validation (`valid_from >= valid_until`) rejected by constraint `chk_gate_pass_validity`. (Actor: Resident, SQLSTATE `23514`/`22000`, 0 rows)
9. **Assertion 9:** Cross-society gate pass transition rejected. (Actor: Admin S1, SQLSTATE `42501`, 0 rows)
10. **Assertion 10:** Gatekeeper logs parcel delivery via `log_parcel_delivery(...)` using 4-byte CSPRNG rejection sampling; SHA-256 hash stored, `collection_code` column is NULL. (Actor: Gatekeeper, SQLSTATE `00000`, 1 row)
11. **Assertion 11:** Direct client SQL `INSERT` into `parcel_logs` blocked by RESTRICTIVE RLS `pol_parcel_restrictive_insert`. (Actor: Client, SQLSTATE `42501`, 0 rows)
12. **Assertion 12:** Direct client SQL `UPDATE` on `parcel_logs` status blocked by RESTRICTIVE RLS `pol_parcel_update_none`. (Actor: Client, SQLSTATE `00000`, 0 rows updated)
13. **Assertion 13:** Direct client SQL `DELETE` on `parcel_logs` blocked by RESTRICTIVE RLS `pol_parcel_delete_none`. (Actor: Client, SQLSTATE `00000`, 0 rows deleted)
14. **Assertion 14:** Direct client SQL `SELECT` on `parcel_logs` by non-recipient member returns 0 rows. (Actor: Resident U1, SQLSTATE `00000`, 0 rows)
15. **Assertion 15:** Parcel collection attempt with wrong collection code rejected (`failed_collection_attempts = 1`). (Actor: Recipient, SQLSTATE `00000`, `p_success = false`)
16. **Assertion 16:** Parcel collection attempt by non-recipient member blocked. (Actor: Resident U2, SQLSTATE `42501`, 0 rows)
17. **Assertion 17:** Authorized recipient collects parcel with correct code (`status = 'collected'`). (Actor: Recipient U1, SQLSTATE `00000`, 1 row)
18. **Assertion 18:** Replay collection attempt on already collected parcel rejected. (Actor: Recipient U1, SQLSTATE `22000`, 0 rows)
19. **Assertion 19 (5-Attempt Brute-Force Lockout Sequence):**  
    * Attempt 1 ('000000'): `failed_attempts = 1`, `status = 'received_at_gate'`, SQLSTATE `00000`.  
    * Attempt 2 ('111111'): `failed_attempts = 2`, `status = 'received_at_gate'`, SQLSTATE `00000`.  
    * Attempt 3 ('222222'): `failed_attempts = 3`, `status = 'received_at_gate'`, SQLSTATE `00000`.  
    * Attempt 4 ('333333'): `failed_attempts = 4`, `status = 'received_at_gate'`, SQLSTATE `00000`.  
    * Attempt 5 ('444444'): `failed_attempts = 5`, `status = 'locked_failed_attempts'`, SQLSTATE `00000`.  
    * Post-Lockout: Correct code attempt rejected (`SQLSTATE 22000`, parcel remains locked).
20. **Assertion 20:** Resident triggers emergency SOS alert via `trigger_sos_alert(...)`. (Actor: Resident P1, SQLSTATE `00000`, 1 row)
21. **Assertion 21:** Direct client SQL `INSERT` into `sos_alerts` blocked by RESTRICTIVE RLS `pol_sos_restrictive_insert`. (Actor: Client, SQLSTATE `42501`, 0 rows)
22. **Assertion 22:** Direct client SQL `UPDATE` on `sos_alerts` blocked by RESTRICTIVE RLS / trigger `trg_protect_sos_status_update`. (Actor: Client, SQLSTATE `00000`, 0 rows updated)
23. **Assertion 23:** Direct client SQL `DELETE` on `sos_alerts` blocked by RESTRICTIVE RLS `policy_sos_delete`. (Actor: Client, SQLSTATE `00000`, 0 rows deleted)
24. **Assertion 24:** Direct client SQL `SELECT` on `sos_alerts` cross-society returns 0 rows. (Actor: Resident S1, SQLSTATE `00000`, 0 rows)
25. **Assertion 25:** Forged property SOS trigger attempt rejected. (Actor: Resident P1, SQLSTATE `42501`, 0 rows)
26. **Assertion 26:** Concurrent active SOS trigger race for same property serialized under `uq_active_sos_alert_property`. (Actor: Session A & B, SQLSTATE `23505`/`22000`, 1 row)
27. **Assertion 27:** Gatekeeper acknowledges SOS alert (`status = 'acknowledged'`). (Actor: Gatekeeper, SQLSTATE `00000`, 1 row)
28. **Assertion 28:** Admin resolves SOS alert with mandatory notes (`status = 'resolved'`). (Actor: Admin, SQLSTATE `00000`, 1 row)
29. **Assertion 29:** Resident submits sub-meter reading via `submit_meter_reading(...)`. (Actor: Resident, SQLSTATE `00000`, 1 row)
30. **Assertion 30:** Direct client SQL `INSERT` into `meter_readings` blocked by RESTRICTIVE RLS `pol_meter_readings_restrictive_insert`. (Actor: Client, SQLSTATE `42501`, 0 rows)
31. **Assertion 31:** Direct client SQL `UPDATE` on `meter_readings` status blocked by RESTRICTIVE RLS / trigger `trg_prevent_direct_meter_reading_update`. (Actor: Client, SQLSTATE `00000`, 0 rows updated)
32. **Assertion 32:** Direct client SQL `DELETE` on `meter_readings` blocked by RESTRICTIVE RLS `pol_meter_readings_restrictive_delete`. (Actor: Client, SQLSTATE `00000`, 0 rows deleted)
33. **Assertion 33:** Admin direct SQL `INSERT` into `utility_meters` allowed; client direct `INSERT` blocked. (Actor: Admin/Client, SQLSTATE `42501` for client, 1 row for admin)
34. **Assertion 34:** Admin direct SQL `UPDATE` on `utility_meters` allowed; client direct `UPDATE` blocked. (Actor: Admin/Client, SQLSTATE `00000`, 0 rows updated for client)
35. **Assertion 35:** Direct client SQL `DELETE` on `utility_meters` blocked by RESTRICTIVE RLS `pol_utility_meters_restrictive_delete`. (Actor: Client, SQLSTATE `00000`, 0 rows deleted)
36. **Assertion 36:** Direct client SQL `SELECT` on `meter_readings` cross-property returns 0 rows. (Actor: Resident P1, SQLSTATE `00000`, 0 rows)
37. **Assertion 37:** Admin verifies and bills reading via `verify_and_bill_meter_reading(...)`, generating `ledger_transactions` `utility_bill` debit. (Actor: Admin, SQLSTATE `00000`, 1 row)
38. **Assertion 38:** Deterministic FK failure test: Meter reading with unmapped user ID causes `ledger_transactions` FK violation (`23503`) strictly INSIDE `verify_and_bill_meter_reading(...)`, rolling back reading status to `'draft'`, 0 ledger rows. (Actor: Admin, SQLSTATE `23503`, 0 ledger rows)
39. **Assertion 39:** Concurrent meter billing race under `FOR UPDATE` lock on `meter_readings`. Session A wins (`00000`); Session B fails (`22000`). 1 ledger transaction. (Actor: Session A & B, SQLSTATE `22000`, 1 transaction)
40. **Assertion 40:** Resident registers vehicle via `register_vehicle(...)`. (Actor: Resident, SQLSTATE `00000`, 1 row)
41. **Assertion 41:** Admin direct SQL `INSERT` into `parking_slots` allowed; client direct `INSERT` blocked. (Actor: Admin/Client, SQLSTATE `42501` for client, 1 row for admin)
42. **Assertion 42:** Direct client SQL `UPDATE` on `parking_slots` blocked by RESTRICTIVE RLS `pol_slots_restrictive_update`. (Actor: Client, SQLSTATE `00000`, 0 rows updated)
43. **Assertion 43:** Direct client SQL `DELETE` on `parking_slots` blocked by RESTRICTIVE RLS `pol_slots_restrictive_delete`. (Actor: Client, SQLSTATE `00000`, 0 rows deleted)
44. **Assertion 44:** Direct client SQL `INSERT` into `vehicles` blocked by RESTRICTIVE RLS `pol_vehicles_restrictive_insert`. (Actor: Client, SQLSTATE `42501`, 0 rows)
45. **Assertion 45:** Direct client SQL `UPDATE` on `vehicles.parking_slot_id` blocked by RESTRICTIVE RLS `pol_vehicles_restrictive_update`. (Actor: Client, SQLSTATE `00000`, 0 rows updated)
46. **Assertion 46:** Resident vehicle owner direct SQL `DELETE` on `vehicles` allowed (`pol_vehicles_delete_resident`), automatically releasing parking slot via trigger `trg_vehicles_auto_release_parking`; non-owner DELETE blocked. (Actor: Resident Owner/Non-owner, SQLSTATE `00000` / `00000` 0 rows for non-owner)
47. **Assertion 47:** Parking Concurrency Race A (Slot Contention): Session A and B attempt to assign different vehicles to slot S1 concurrently. Exactly one vehicle assigned to S1 under canonical lock order (`parking_slots` then `vehicles`). (Actor: Session A & B, SQLSTATE `23505`/`22000`)
48. **Assertion 48:** Parking Concurrency Race B (Vehicle Contention): Session A and B assign vehicle V1 to slots S1 and S2 simultaneously. V1 assigned to at most one slot under canonical lock order. (Actor: Session A & B, SQLSTATE `23505`/`22000`)
49. **Assertion 49:** Parking Concurrency Race C (Release vs Assign): Session A releases S1 while Session B assigns S1. Serializes under `FOR UPDATE` lock, preserving permanent `property_id`. (Actor: Session A & B, SQLSTATE `00000`/`22000`)
50. **Assertion 50:** Admin creates community poll via `create_community_poll(...)` with validated JSONB options. (Actor: Admin, SQLSTATE `00000`, 1 row)
51. **Assertion 51:** Direct client SQL `INSERT` into `polls` blocked by RESTRICTIVE RLS `pol_polls_restrictive_insert`. (Actor: Client, SQLSTATE `42501`, 0 rows)
52. **Assertion 52:** Direct client SQL `UPDATE` on `polls` blocked by RESTRICTIVE RLS `pol_polls_restrictive_update`. (Actor: Client, SQLSTATE `00000`, 0 rows updated)
53. **Assertion 53:** Direct client SQL `DELETE` on `polls` blocked by RESTRICTIVE RLS `pol_polls_restrictive_delete`. (Actor: Client, SQLSTATE `00000`, 0 rows deleted)
54. **Assertion 54:** Poll Option Validation: Creating poll with invalid options rejected by `fn_validate_poll_options` helper function in CHECK constraint. Rejects `[]`, `["YES","yes"]`, `["   ","valid"]`, `["one",123]`. (Actor: Admin, SQLSTATE `23514`, 0 rows)
55. **Assertion 55:** Direct client SQL `INSERT` into `poll_votes` blocked by RESTRICTIVE RLS `pol_poll_votes_restrictive_insert`. (Actor: Client, SQLSTATE `42501`, 0 rows)
56. **Assertion 56 (Direct UPDATE on `poll_votes`):** Direct client SQL `UPDATE` on `poll_votes` blocked by RESTRICTIVE RLS `pol_poll_votes_restrictive_update` `USING (false)`. The existing target row is not eligible for update — RLS excludes it entirely. Result: 0 rows updated. `trg_prevent_vote_mutations` also installed as defense-in-depth. (Actor: Client, SQLSTATE `00000`, 0 rows updated)
57. **Assertion 57 (Direct DELETE on `poll_votes`):** Direct client SQL `DELETE` on `poll_votes` blocked by RESTRICTIVE RLS `pol_poll_votes_restrictive_delete` `USING (false)`. The target row is not eligible for deletion — RLS excludes it entirely. Result: 0 rows deleted. `trg_prevent_vote_mutations` also installed as defense-in-depth for privileged bypass paths. (Actor: Client, SQLSTATE `00000`, 0 rows deleted)
58. **Assertion 58:** Member direct SQL `SELECT` on `poll_votes` returns ONLY caller's own vote choice (`voter_id = auth.uid()`). (Actor: Resident U1, SQLSTATE `00000`, 1 row max)
59. **Assertion 59:** Resident casts vote for property via `cast_poll_vote(...)`. (Actor: Resident P1, SQLSTATE `00000`, 1 row)
60. **Assertion 60:** Voting for choice not in `polls.options` rejected. (Actor: Resident P1, SQLSTATE `22000`, 0 rows)
61. **Assertion 61:** Voting before start time or after end time / on closed poll rejected. (Actor: Resident P1, SQLSTATE `22000`, 0 rows)
62. **Assertion 62:** Cross-society or non-resident property vote attempt rejected. (Actor: Resident P1, SQLSTATE `42501`, 0 rows)
63. **Assertion 63:** Two occupants of Property 1 concurrently cast vote. Session A wins (`00000`); Session B hits `uq_poll_property_vote` (`23505`). (Actor: Session A & B, SQLSTATE `23505`)
64. **Assertion 64:** Member requesting aggregate results for an active poll via `get_poll_results(...)` rejected to preserve confidentiality. (Actor: Resident U1, SQLSTATE `22000`, 0 rows)
65. **Assertion 65:** Non-admin member attempting to execute `close_community_poll(...)` rejected due to admin privilege check. (Actor: Resident U1, SQLSTATE `42501`, 0 rows)
66. **Assertion 66:** Authorized admin attempting to close an active poll before `NOW() >= ends_at` rejected due to time constraint. (Actor: Admin, SQLSTATE `22000`, 0 rows)
67. **Assertion 67:** Admin calls `close_community_poll(...)` after poll reaches `ends_at`. Poll status becomes `'closed'`, closed-poll aggregate results (`get_poll_results`) become available. (Actor: Admin, SQLSTATE `00000`, 1 row)
68. **Assertion 68:** Authenticated client setting forged transaction-local GUC (`set_config('app.caller_id', ...)`). Procedure ignores GUC, evaluates `auth.uid()`, fails authorization. (Actor: Client, SQLSTATE `42501`, 0 rows)
69. **Assertion 69:** Catalog query proves all 16 Slice 17 workflow functions explicitly enforce `search_path = public, pg_temp`. (Actor: Audit Script, SQLSTATE `00000`, 16 rows)
70. **Assertion 70:** Catalog query via `has_function_privilege()` proves EXECUTE revoked from `PUBLIC`, `authenticated`, and `anon` for all 6 legacy functions. (Actor: Audit Script, SQLSTATE `00000`, 6 rows)
71. **Assertion 71:** Catalog query via `has_function_privilege()` verifies effective privileges for ALL 16 new Slice 17 functions. (Actor: Audit Script, SQLSTATE `00000`, 16 rows)
72. **Assertion 72:** Catalog query verifies `parcel_logs.failed_collection_attempts` exists (NOT NULL, default `0`) and `collection_code_hash` exists, while `collection_code` is nullable and `CHECK (collection_code IS NULL)` is enforced. (Actor: Audit Script, SQLSTATE `00000`, 1 row)
73. **Assertion 73:** Resident of Society 1 attempting `SELECT` on `sos_alerts` or `parcel_logs` in Society 2 returns 0 rows. (Actor: Resident S1, SQLSTATE `00000`, 0 rows)
74. **Assertion 74:** Trusted workflow execution (`issue_gate_pass`) automatically creates audit log row with `actor_id = auth.uid()`, `society_id`, `entity_type = 'gate_pass'`, `action = 'pass_issued'`, and payload. (Actor: Audit Script, SQLSTATE `00000`, 1 row)
75. **Assertion 75:** Direct client SQL `INSERT` into `audit_logs` blocked by RLS. (Actor: Client, SQLSTATE `42501`, 0 rows)
76. **Assertion 76:** Direct client SQL `DELETE` on `audit_logs` blocked by RLS / trigger. (Actor: Client, SQLSTATE `42501`/`00000`, 0 rows deleted)
77. **Assertion 77:** Verification query searches `audit_logs.new_data` and `notifications.body` for the raw 6-digit collection code issued in Assertion 10 and asserts zero occurrences exist. (Actor: Audit Script, SQLSTATE `00000`, 0 occurrences)
78. **Assertion 78:** Invalid parcel delivery call (e.g. invalid recipient user ID causing FK failure) aborts transaction cleanly, rolling back audit and notification rows. (Actor: Gatekeeper, SQLSTATE `23503`, 0 rows)
79. **Assertion 79:** Script verifies SHA-256 hashes of Slice 16 schema and lock files against reference manifest; Slices 1–15 reported `NO AUTHORITATIVE REFERENCE HASH`. (Actor: Audit Script, SQLSTATE `00000`, match)
80. **Assertion 80:** Direct client SQL `INSERT`/`UPDATE` on `notifications` blocked by RLS. (Actor: Client, SQLSTATE `42501`, 0 rows)
81. **Assertion 81:** Resident vehicle owner deleting vehicle row with active slot assignment triggers `trg_vehicles_auto_release_parking`, clearing `parking_slots.assigned_vehicle_id` to NULL and unlinking `vehicles.parking_slot_id` automatically, while preserving permanent `parking_slots.property_id`. (Actor: Resident Owner, SQLSTATE `00000`, 1 row)
82. **Assertion 82:** Database-layer service-role context simulation (`SET LOCAL ROLE service_role;`) verifies backend administrative workflow execution without requiring end-user `auth.uid()`. (Actor: Service Role Simulation, SQLSTATE `00000`, 1 row)

---

## 15. HISTORICAL IMMUTABILITY MANIFEST (37 FILES TOTAL)

| File Path | SHA-256 Reference Hash | Immutability Status |
| :--- | :--- | :--- |
| `database/schema_slice1.sql` | `16F8E4AC3213F131048E8C20E29A31B679553E5ED708C8AE55269D71F16BC373` | **NO AUTHORITATIVE REFERENCE HASH** |
| `database/schema_slice2.sql` | `86F4DE5045E549BD54216974669E55C9E0B0F874C48D6B42A791B0E17D07516C` | **NO AUTHORITATIVE REFERENCE HASH** |
| `database/schema_slice3.sql` | `46F2391F66B727FDD04D5DC21C48D9DB261682CBE171679B7269D2A9F496EC2C` | **NO AUTHORITATIVE REFERENCE HASH** |
| `database/schema_slice4.sql` | `9FD2607166C863EB714C3AB6A2A1746CE07C34C77AF80B1FC0C67912E65DDA85` | **NO AUTHORITATIVE REFERENCE HASH** |
| `database/schema_slice5.sql` | `3E3F2F6B579B14AFC66901BC203C1ACA6F46FF9434CB533CC4FFED5C3185ADC0` | **NO AUTHORITATIVE REFERENCE HASH** |
| `database/schema_slice6.sql` | `AF5C73AD130FEA0A9CA294E37D66C1A1AE081D6571DFAFA87FD7789EBD2B1D8C` | **NO AUTHORITATIVE REFERENCE HASH** |
| `database/schema_slice7.sql` | `6EC3BB8EF0BD25754F598BCD0AF1ECD2850F1B2A08F3F29163496745B910B1F3` | **NO AUTHORITATIVE REFERENCE HASH** |
| `database/schema_slice8.sql` | `702BAF9BEC1309970535492846E42C72D9FA437F2267C2B9CF63947F259D819D` | **NO AUTHORITATIVE REFERENCE HASH** |
| `database/schema_slice9.sql` | `2CCCFFBD56D190D36A198A9D01AD54885FF67DD350720F2F11838193F30D5261` | **NO AUTHORITATIVE REFERENCE HASH** |
| `database/schema_slice10.sql` | `5A492450FAB3983516AD620F393357C6F20CF0FB606F91E9544F96769F17D3EC` | **NO AUTHORITATIVE REFERENCE HASH** |
| `database/schema_slice11.sql` | `3C22C8F38E93465E68D84B1AE67E390E37FC246A0AFCC2D0E6EA9D8F8F203E3F` | **NO AUTHORITATIVE REFERENCE HASH** |
| `database/schema_slice12.sql` | `07156EB10D2FDDCF598D93207A66F27AEC3B996D7DECE71E9B3C0D6A458276B7` | **NO AUTHORITATIVE REFERENCE HASH** |
| `database/schema_slice13.sql` | `105ACDED8BEB58560497AEE1E05393F040AFC8374B8596C15470EAED985CA99A` | **NO AUTHORITATIVE REFERENCE HASH** |
| `database/schema_slice14.sql` | `67BB444A3BF8C200E675330E70AA80FD48F95DDC8F7F5D04CEDF912075D607A2` | **NO AUTHORITATIVE REFERENCE HASH** |
| `database/schema_slice15.sql` | `F911927046C9A914F353552F82542453BB7EDDE5ACFE925D9FA5D591723BC990` | **NO AUTHORITATIVE REFERENCE HASH** |
| `database/schema_slice16.sql` | `34D02E670C612D1F32656B49D28894D67D04F5C0C2E08B6169830AC5FD6215CC` | **MATCH (`SLICE16_REMEDIATION_LOCK_RECORD.md`)** |
| `database/verify_slice1.sql` | `142C69508D157021A67AE40594D8781C1E9B155D241BEBC93307A1484917C3E4` | **NO AUTHORITATIVE REFERENCE HASH** |
| `database/verify_slice2.sql` | `BAA3F0EA62FB498DE8C282AF4D3F073AF5B24BD8FAED3CF16E2A6150FCAD166E` | **NO AUTHORITATIVE REFERENCE HASH** |
| `database/verify_slice3.sql` | `D75CF00780B93A43396913881A4DBBB66658FC383F3B11E928DAF76FEFAD1970` | **NO AUTHORITATIVE REFERENCE HASH** |
| `database/verify_slice4.sql` | `AB7D0D3128823A4AEA8647D2BB80FAA0BD1EC9B30347D54B4CC1CE3379D28E23` | **NO AUTHORITATIVE REFERENCE HASH** |
| `database/verify_slice5.sql` | `5719A81DBF8590F2B74A0396C58CB01BB527FB09511BB8355EF2228DA360B172` | **NO AUTHORITATIVE REFERENCE HASH** |
| `database/verify_slice6.sql` | `194E9F054B76B170CD3085CD0DD0CC1D33BBC30D716E52CD59231D419F7FF9EB` | **NO AUTHORITATIVE REFERENCE HASH** |
| `database/verify_slice7.sql` | `D27C90C5871366DD020D9F52DF4955F506430CE5DE97C3089024D78EB9065BA5` | **NO AUTHORITATIVE REFERENCE HASH** |
| `database/verify_slice8.sql` | `6F4CE8892B11177A2077023DCE14FEEF8A02CCBB4D72C3593819C69C64D41C50` | **NO AUTHORITATIVE REFERENCE HASH** |
| `database/verify_slice9.sql` | `E9B071B8EA6713629AB710204C1E5679B44A13B89C663E0B0C286FA9A5A58737` | **NO AUTHORITATIVE REFERENCE HASH** |
| `database/verify_slice10.sql` | `5900B4A59AF1136B37D483897638103491FB4CDB078364DC73A6806136C3EE37` | **NO AUTHORITATIVE REFERENCE HASH** |
| `database/verify_slice11.sql` | `9DCC8AC1298B76C04729AC33FBE1959B4D280AA9C23FD1B5485E10CFE48AF417` | **NO AUTHORITATIVE REFERENCE HASH** |
| `database/verify_slice12.sql` | `76A70E7EF1A45771CA15AF348A5A9D6CB1C60962727003D433D20CB71C6D8C12` | **NO AUTHORITATIVE REFERENCE HASH** |
| `database/verify_slice13.sql` | `AD601D98A1E4F0D448725338316108C652379BA78592798D82E4F86E16C0DB4F` | **NO AUTHORITATIVE REFERENCE HASH** |
| `database/verify_slice14.sql` | `32C9985C35B35B739CBB9BB47EFBCF14F91324F8F33B070C4799466C5E50E4DE` | **NO AUTHORITATIVE REFERENCE HASH** |
| `database/verify_slice15.sql` | `6EECF7AB96F9C5BAB28174D26B946333BE141A380C143E60B583B18F6D4B9A5C` | **NO AUTHORITATIVE REFERENCE HASH** |
| `database/verify_slice16.sql` | `5FB3812A02738DE004997C597ADE0598468BC9A76AA23B5ACD0AAD7E5746C0BB` | **MATCH (`SLICE16_REMEDIATION_LOCK_RECORD.md`)** |
| `SLICE15_LOCK_RECORD.md` | `75064DFEEF6520D304AD927ABF39DE5D5C62477D11FD5BA895281782A0BC3385` | **NO AUTHORITATIVE REFERENCE HASH** |
| `SLICE16_LOCK_RECORD.md` | `6BC851EDB991E7151BC0E1F975777B84F5BA56D07F81BB8B4F23284144D4486E` | **NO AUTHORITATIVE REFERENCE HASH** |
| `SLICE16_POST_LOCK_BOOKING_OVERLAP_EVIDENCE.md` | `B458DD622AEF4F792F6FA54CA434C738A291F2919BFD3D5241C4AED76A6A9040` | **NO AUTHORITATIVE REFERENCE HASH** |
| `SLICE16_POST_LOCK_SECURITY_REVERIFICATION.md` | `43C68A8258C09B811DFCCBED3C5208381A3CC7B1682E5E963AD7DC62FEBE88A2` | **NO AUTHORITATIVE REFERENCE HASH** |
| `SLICE16_REMEDIATION_LOCK_RECORD.md` | `04E502AB4443E5AFDD283962E33EBCA244FA1E653BF18EDC03A8D0F97A247240` | **MATCH (`SLICE16_REMEDIATION_LOCK_RECORD.md`)** |

---

## 16. APPLICATION COMPATIBILITY EVIDENCE

Static code search across `src/App.jsx` and `src/supabase.js`:
* `fn_cast_poll_vote`: **0 references in application source.**
* `fn_assign_parking_slot`: **0 references in application source.**
* `fn_transition_gate_pass_state`: **0 references in application source.**
* `fn_transition_parcel_state`: **0 references in application source.**
* `fn_transition_meter_reading_state`: **0 references in application source.**
* `fn_transition_sos_alert`: **0 references in application source.**
* **Conclusion:** Hardening legacy routines and deploying 16 new RPC routines introduces zero breaking changes to existing application source code.

---

## 17. IMPLEMENTATION FILE BOUNDARY

When implementation authorization is granted by the user, EXACTLY three files will be created:
1. `[NEW]` [database/schema_slice17.sql](file:///d:/Clients%20Applications/SU%20Society%20App/database/schema_slice17.sql)
2. `[NEW]` [database/verify_slice17.sql](file:///d:/Clients%20Applications/SU%20Society%20App/database/verify_slice17.sql)
3. `[NEW]` [scratch/run_all17.ps1](file:///d:/Clients%20Applications/SU%20Society%20App/scratch/run_all17.ps1)

---

## 18. SEQUENTIAL IMPLEMENTATION ORDER

When authorized, implementation will proceed in strict order:
1. **Preflight Environment Check:** Verify test container running on `localhost:54322`.
2. **Historical Baseline Regression:** Execute `run_all16.ps1` $\rightarrow$ Confirm **469 / 469 PASS**.
3. **Historical Manifest Audit:** Verify SHA-256 hashes of Slice 16 files match reference manifest.
4. **Deploy Slice 17 Schema DDL:** Execute `database/schema_slice17.sql`.
5. **Create Helper Functions:** Deploy `public.fn_validate_poll_options(jsonb)`.
6. **Deploy Triggers & RLS Policies:** Apply RESTRICTIVE policies and mutation-blocking triggers.
7. **Deploy 16 SECURITY DEFINER Routines:** Create all 16 new workflow functions.
8. **Execute Live Catalog Hardening:** Revoke client EXECUTE on 6 legacy functions; grant to `service_role`.
9. **Grant RPC Privileges:** Grant EXECUTE on 16 new routines to `authenticated` and `service_role`.
10. **Execute Verification Test Suite:** Run `database/verify_slice17.sql` (Assertions 1–82).
11. **Final Baseline Score Verification:** Calculate cumulative score = **469 + 82 = 551 PASS**.

---

## 19. ADVERSARIAL TEST PLAN (21 THREAT VECTORS)

1. **Privilege Escalation:** Resident attempting to invoke admin RPC routines $\rightarrow$ Blocked (`42501`).
2. **Forged `auth.uid()` Identity:** Client setting `app.caller_id` GUC $\rightarrow$ Ignored; `auth.uid()` enforced.
3. **Forged Client GUC Override:** Manipulating session GUCs $\rightarrow$ Blocked.
4. **Cross-Property Access:** Resident P1 attempting gate pass/meter reading for P2 $\rightarrow$ Blocked (`42501`).
5. **Cross-Society Access:** Admin S1 attempting RPC mutation on S2 $\rightarrow$ Blocked (`42501`).
6. **Direct Table Mutations:** Direct client SQL INSERT/UPDATE/DELETE $\rightarrow$ Blocked (`42501` / 0 rows).
7. **Unauthorized Function Execution:** Invoking legacy routines directly $\rightarrow$ Blocked (`42501`).
8. **State Machine Bypass:** Direct UPDATE on status columns $\rightarrow$ Blocked by triggers / RLS.
9. **Duplicate Voting:** Concurrent vote casting for same property $\rightarrow$ Serialized under `uq_poll_property_vote` (`23505`).
10. **Active Poll Result Leakage:** Member requesting active poll tallies $\rightarrow$ Blocked (`22000`).
11. **Parcel Brute-Force Code Guessing:** 5 consecutive wrong-code collection calls $\rightarrow$ Account locked out (`status = 'locked_failed_attempts'`).
12. **Parking Race Conditions:** Concurrent slot assignment calls $\rightarrow$ Serialized under `FOR UPDATE` lock.
13. **Vehicle/Slot Inconsistency:** Releasing vehicle assignment $\rightarrow$ Preserves permanent `parking_slots.property_id`.
14. **Utility Billing Duplication:** Re-billing already billed reading $\rightarrow$ Blocked (`22000`).
15. **Ledger Integrity Failure:** Purged/unmapped user ID in billing $\rightarrow$ Atomic PL/pgSQL transaction rollback (`23503`).
16. **SECURITY DEFINER Search-Path Abuse:** Unqualified table/helper references $\rightarrow$ Blocked by `SET search_path = public, pg_temp`.
17. **SQL Injection:** Dynamic query strings $\rightarrow$ N/A (All queries use static parameterized SQL).
18. **Service-Role Authorization:** Service role context execution $\rightarrow$ Tested via database-layer context simulation.
19. **Audit Bypass:** Direct client mutation of `audit_logs` $\rightarrow$ Blocked (`42501`).
20. **Notification Leakage:** Plaintext parcel code in notifications $\rightarrow$ Verified 0 occurrences.
21. **Historical File Modification:** Altering locked Slices 1–16 $\rightarrow$ Verified 0 modifications.

---

## 20. FINAL GO / NO-GO GATE TABLE & PLAN STATUS

| Gate | Classification | Evidence |
| :--- | :--- | :--- |
| Plan completeness | **DESIGN-VERIFIED** | All 20 sections fully specified without truncation |
| Slice 1–16 immutability | **DESIGN-VERIFIED** | 37 historical files; SHA-256 hashes computed. Runtime hash re-verification pending execution |
| ACL completeness | **DESIGN-VERIFIED** | `has_function_privilege()` specified for all 22 routines; catalog queries pending runtime |
| RLS correctness (poll_votes) | **PLAN-SPECIFIED** | RESTRICTIVE `USING(false)` for UPDATE and DELETE → 0 rows, SQLSTATE `00000`; runtime verification pending |
| RLS correctness (all tables) | **PLAN-SPECIFIED** | Permissive/Restrictive RLS rules specified per PostgreSQL semantics; runtime SQLSTATE verification pending |
| SECURITY DEFINER safety | **DESIGN-VERIFIED** | Owner `postgres`, `search_path = public, pg_temp`, all schema-qualified; runtime catalog check pending |
| State machines | **DESIGN-VERIFIED** | Gate Pass (3 states) and SOS Alert (4 states) state machines locked; runtime transition test pending |
| Parcel security | **DESIGN-VERIFIED** | CSPRNG sampling, SHA-256 hash storage, 5-attempt lockout locked; runtime lockout sequence test pending |
| Parking concurrency | **DESIGN-VERIFIED** | Model A deeded property preservation & canonical lock order locked; runtime race test pending |
| Utility ledger integrity | **PLAN-SPECIFIED** | Atomic rollback on FK failure & Slice 15 ledger integration specified; runtime FK rollback test pending |
| Poll integrity | **DESIGN-VERIFIED** | IMMUTABLE option validator & active poll result confidentiality locked; runtime test pending |
| SOS security | **DESIGN-VERIFIED** | Mandatory resolution notes & duplicate alert prevention locked; runtime test pending |
| Adversarial coverage | **DESIGN-VERIFIED** | 21 threat vectors explicitly detailed |
| Verification completeness | **DESIGN-VERIFIED** | All 82 assertions explicitly specified in Section 14 |
| Historical hash evidence | **DESIGN-VERIFIED** | Slice 16 reference hashes match; Slices 1–15 reported NO AUTHORITATIVE REF HASH |

---

### **FINAL PLAN STATUS:**

```text
==================================================
SLICE 17 IMPLEMENTATION PLAN RECONCILIATION COMPLETE

STATUS: READY FOR FINAL USER IMPLEMENTATION APPROVAL

Baseline: 469/469 PASS (100% LOCKED)
User-Approved Design Decision: Parcel lockout threshold = 5 failed collection attempts.
ACL Evidence: Complete for all 22 routines.
Assertions: 82 Assertions (Assertions 1 through 82 explicitly listed).
Cumulative Planned Score: 469 + 82 = 551 PASS
Poll_votes RLS Semantics (CORRECTED v3.2.0):
  Assertion 56: UPDATE → RESTRICTIVE USING(false) → 0 rows, SQLSTATE 00000
  Assertion 57: DELETE → RESTRICTIVE USING(false) → 0 rows, SQLSTATE 00000
  trg_prevent_vote_mutations: Defense-in-depth only (not primary denial mechanism)

NO APPLICATION OR DATABASE IMPLEMENTATION HAS BEEN AUTHORIZED.
==================================================
```

**READY FOR FINAL USER REVIEW**

**NO APPLICATION OR DATABASE IMPLEMENTATION HAS BEEN AUTHORIZED.**
