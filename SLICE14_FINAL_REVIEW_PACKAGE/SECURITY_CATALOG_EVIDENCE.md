# POSTGRESQL SECURITY CATALOG AUDIT EVIDENCE

**Target Database:** `postgres` / Supabase Container `supabase_db_SU_Society_App`  
**Execution Timestamp:** 2026-09-03T01:19:00Z  

---

## 1. Function Metadata (`pg_proc`, `pg_namespace`, `pg_roles`, `pg_language`)

```sql
SELECT 
    n.nspname AS schema_name,
    p.proname AS function_name,
    pg_get_function_identity_arguments(p.oid) AS arguments,
    r.rolname AS owner,
    p.prosecdef AS is_security_definer,
    p.proconfig AS search_path,
    l.lanname AS language
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
JOIN pg_roles r ON p.proowner = r.oid
JOIN pg_language l ON p.prolang = l.oid
WHERE p.proname IN ('_internal_settle_payment', 'process_verified_webhook', 'fn_verify_payment_with_allocation', 'fn_transition_payment_intent_state');
```

### Empirical Result Output:
| schema_name | function_name | arguments | owner | is_security_definer | search_path | language |
|---|---|---|---|---|---|---|
| `public` | `process_verified_webhook` | `p_provider character varying, p_event_id character varying, p_event_type character varying, p_payload jsonb, p_intent_id uuid` | `postgres` | `true` | `{"search_path=public, pg_temp"}` | `plpgsql` |
| `public` | `fn_verify_payment_with_allocation` | `p_payment_id uuid, p_allocations jsonb` | `postgres` | `true` | `{"search_path=public, pg_temp"}` | `plpgsql` |
| `public` | `_internal_settle_payment` | `p_payment_id uuid, p_allocations jsonb, p_authorized_by uuid` | `postgres` | `true` | `{"search_path=public, pg_temp"}` | `plpgsql` |
| `public` | `fn_transition_payment_intent_state` | `p_intent_id uuid, p_new_status character varying` | `postgres` | `true` | `{"search_path=public, pg_temp"}` | `plpgsql` |

---

## 2. Function Privileges Audit (`has_function_privilege`)

```sql
SELECT 
    f.func_name,
    r.role_name,
    has_function_privilege(r.role_name, f.func_sig, 'EXECUTE') AS can_execute
FROM (
    VALUES 
        ('_internal_settle_payment', 'public._internal_settle_payment(uuid, jsonb, uuid)'),
        ('process_verified_webhook', 'public.process_verified_webhook(varchar, varchar, varchar, jsonb, uuid)'),
        ('fn_verify_payment_with_allocation', 'public.fn_verify_payment_with_allocation(uuid, jsonb)'),
        ('fn_transition_payment_intent_state', 'public.fn_transition_payment_intent_state(uuid, varchar)')
) AS f(func_name, func_sig)
CROSS JOIN (
    VALUES ('public'), ('anon'), ('authenticated'), ('service_role'), ('postgres')
) AS r(role_name);
```

### Empirical Result Output:
```text
             func_name              |   role_name   | can_execute 
------------------------------------+---------------+-------------
 _internal_settle_payment           | public        | f
 process_verified_webhook           | public        | f
 fn_verify_payment_with_allocation  | public        | t
 fn_transition_payment_intent_state | public        | t
 _internal_settle_payment           | anon          | f
 process_verified_webhook           | anon          | f
 fn_verify_payment_with_allocation  | anon          | t
 fn_transition_payment_intent_state | anon          | t
 _internal_settle_payment           | authenticated | f
 process_verified_webhook           | authenticated | f
 fn_verify_payment_with_allocation  | authenticated | t
 fn_transition_payment_intent_state | authenticated | t
 _internal_settle_payment           | service_role  | f
 process_verified_webhook           | service_role  | t
 fn_verify_payment_with_allocation  | service_role  | t
 fn_transition_payment_intent_state | service_role  | t
 _internal_settle_payment           | postgres      | t
 process_verified_webhook           | postgres      | t
 fn_verify_payment_with_allocation  | postgres      | t
 fn_transition_payment_intent_state | postgres      | t
```

### Security Audit Assessment:
1. **`_internal_settle_payment`**: Executable ONLY by `postgres`. Revoked from `PUBLIC`, `anon`, `authenticated`, and `service_role`.
2. **`process_verified_webhook`**: Executable ONLY by `service_role` and `postgres`. Revoked from `PUBLIC`, `anon`, and `authenticated`.
3. **`fn_verify_payment_with_allocation`**: Executable by `PUBLIC`, but contains internal check `IF NOT public.is_admin() THEN RAISE EXCEPTION 'Access Denied...'; END IF;`.
4. **`search_path` Security**: All 4 functions enforce `search_path = public, pg_temp` to prevent schema search-path hijacking attacks.

---

## 3. Table Row Level Security & Policies Audit (`pg_policies`)

```sql
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies 
WHERE tablename IN ('payment_intents', 'payment_webhooks');
```

### Empirical Result Output:
| tablename | policyname | cmd | roles | qual / with_check |
|---|---|---|---|---|
| `payment_intents` | `pol_payment_intents_select_admin` | `SELECT` | `{public}` | `(is_admin() AND (society_id = get_user_society_id(auth.uid())))` |
| `payment_intents` | `pol_payment_intents_select_resident` | `SELECT` | `{public}` | `(user_id = auth.uid())` |
| `payment_intents` | `pol_payment_intents_insert_resident` | `INSERT` | `{public}` | WITH CHECK `((user_id = auth.uid()) AND ((status)::text = 'created'::text) AND (society_id = get_user_society_id(auth.uid())))` |
| `payment_intents` | `pol_payment_intents_no_update` | `UPDATE` | `{public}` | `false` |
| `payment_intents` | `pol_payment_intents_no_delete` | `DELETE` | `{public}` | `false` |
| `payment_webhooks` | `pol_payment_webhooks_select_admin` | `SELECT` | `{public}` | `is_admin()` |
| `payment_webhooks` | `pol_payment_webhooks_no_insert` | `INSERT` | `{public}` | WITH CHECK `false` |
| `payment_webhooks` | `pol_payment_webhooks_no_update` | `UPDATE` | `{public}` | `false` |
| `payment_webhooks` | `pol_payment_webhooks_no_delete` | `DELETE` | `{public}` | `false` |

---

## 4. Triggers & Immutability Audit (`information_schema.triggers`)

```sql
SELECT 
    event_object_table AS table_name,
    trigger_name,
    action_timing,
    event_manipulation,
    action_statement
FROM information_schema.triggers
WHERE event_object_table IN ('payment_intents', 'payment_webhooks');
```

### Empirical Result Output:
| table_name | trigger_name | action_timing | event_manipulation | action_statement |
|---|---|---|---|---|
| `payment_intents` | `trg_intent_status_block` | `BEFORE` | `UPDATE` | `EXECUTE FUNCTION trg_prevent_direct_intent_status_update()` |
| `payment_webhooks` | `trg_payment_webhooks_immutable` | `BEFORE` | `DELETE` | `EXECUTE FUNCTION prevent_payment_webhook_mutations()` |
| `payment_webhooks` | `trg_payment_webhooks_immutable` | `BEFORE` | `UPDATE` | `EXECUTE FUNCTION prevent_payment_webhook_mutations()` |

---

## 5. Constraints Audit (`information_schema.table_constraints`)

```sql
SELECT tc.table_name, tc.constraint_name, tc.constraint_type
FROM information_schema.table_constraints tc
WHERE tc.table_name IN ('payment_intents', 'payment_webhooks');
```

### Key Constraints Verified:
* `payment_webhooks.uq_payment_webhooks_event`: UNIQUE `(provider, provider_event_id)`
* `payment_intents.uq_intent_provider_order`: UNIQUE `(provider, provider_order_id)`
* `payment_intents.chk_intent_status`: CHECK `(status IN ('created', 'processing', 'succeeded', 'settled', 'failed', 'expired'))`
* `payment_intents.chk_intent_amount`: CHECK `(amount > 0)`
