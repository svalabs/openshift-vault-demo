---
title: '5. Vault Postgresql Plugin'
date: 2018-11-28T15:14:39+10:00
weight: 6
---

We will enable and configure Vaults Postgresql database plugin with a maximum ttl of 24h. For this we add a new role `psql-role`. The role is binded to the [`psql-policy`](psql-policy.hcl) which enabled creating and listing secrets at the `openshift/anwendertreffen` path. The role `demo-role` gets extends about the newly created policy. Finally, we verify the rotation of database passwords in the postgres shell.

## Configuration
```bash
vault secrets enable database
vault write database/config/postgresql \
    plugin_name=postgresql-database-plugin \
    allowed_roles="psql-role" \
    connection_url="postgresql://{{username}}:{{password}}@postgresql.psql.svc:5432/anwenderdb?sslmode=disable" \
    username="user" \
    password="password"
```

## Role
```bash
vault write database/roles/psql-role \
    db_name=postgresql \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
        GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
    default_ttl="1h" \
    max_ttl="24h"
```

# Policy
```bash
vault policy write psql-policy psql-policy.hcl
```

## Policy Role binding
We binded the policy earlier see ([policy-role-binding](#policy-role-binding)).


## Credate new PostgreSQL credientials
```bash
vault read database/creds/psql-role
```

returns:

```bash
Key                Value
---                -----
lease_id           database/creds/psql-role/5omHaI7KpbHVl9SsPRuJXkUr
lease_duration     1h
lease_renewable    true
password           A1a-rAN7ZgiGL15w8YQm
username           v-root-psql-rol-8J4RMv2vQBluii4lyuPa-1624970070
```

if you instead receive:
```bash
pq: permission denied to create role
```

execute
```sql
ALTER ROLE "user" CREATEROLE;
```

in the psql shell of the pod (see next step).


## Verify credientials have been changed
```bash
POD=$(oc get po --no-headers -o custom-columns=NAME:.metadata.name -lname=postgresql)
oc rsh $POD # in postgres pod shell
psql # in psql shell
\du
```

returns:
```bash
postgres=# \du
                                                      List of roles
                    Role name                    |                         Attributes                         | Member of
-------------------------------------------------+------------------------------------------------------------+-----------
 postgres                                        | Superuser, Create role, Create DB, Replication, Bypass RLS | {}
 user                                            | Create role                                                | {}
 v-root-psql-rol-8J4RMv2vQBluii4lyuPa-1624970070 | Password valid until 2021-06-29 13:34:35+00                | {}
 ```

