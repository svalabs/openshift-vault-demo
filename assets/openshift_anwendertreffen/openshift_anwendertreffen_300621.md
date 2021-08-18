# [OpenShift & Vault Demo](https://falcosuessgott.github.io/openshift-vault-demo/)
> [15. OpenShift Anwendertreffen](https://www.openshift-anwender.de/) 30.6.2021

This repository describes how to use Vault within OpenShift. Thus it creates two OpenShifts projects(`vault` and `psql`) showing how to rotate Postgres Database credientials using Vaults [postgres-plugin](https://www.vaultproject.io/docs/secrets/databases/postgresql).

---

# Prerequisites
Tested with
* OpenShift v4.7.8
* `oc` v4.7.8
* `vault` v1.5.4
* `helm` v3.4.2

You will need a user who is able to create:
* `ClusterRole`
* `ClusterRolebinding`
* `MutatingWebhookConfiguration`
* `Deployment`
* `ServiceAccount`
* `ConfigMap`
* `Statefulset`
* `Route`
* `NetworkPolicy`
* `PersistentVolumeClaim`

# Usage
Clone this repository and follow the instructions:
```bash
git clone --recurse-submodules https://github.com/FalcoSuessgott/openshift-vault-demo
cd openshift-anwendertreffen_30062021
```

# Vault
We will create a role `demo-role` which uses the `kubernetes` auth method by using the service accounts JWT. This role then gets binded to a [`demo-policy`](demo-policy.hcl) which is allowed to read and list secrets at `openshift/anwendertreffen` in Vaults KV2 store.

## Project creation
```bash
oc new-project vault
```

## Installation
```bash
export VAULT_DOMAIN=vault.apps.tld
helm install vault vault-helm -f override-values.yml --set server.route.host=${VAULT_DOMAIN}
```

## Initialization
```bash
POD=$(oc get pods -lapp.kubernetes.io/name=vault --no-headers -o custom-columns=NAME:.metadata.name)
oc rsh $POD
vault operator init --tls-skip-verify -key-shares=1 -key-threshold=1 # in vault pod
```

## Unsealing
```bash
# save generated keys and token from output before
export KEYS=QzlUGvdPbIcM83UxyjuGd2ws7flZdNimQVCNbUvI2aU=
export ROOT_TOKEN=s.UPBPfhDXYOtnv8mELhPA4br7
export VAULT_TOKEN=${ROOT_TOKEN}
vault operator unseal --tls-skip-verify $KEYS
```

## Configure the Kubernetes Auth method
```bash
# in $POD with env vars exported (step above)
JWT=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
KUBERNETES_HOST=https://${KUBERNETES_PORT_443_TCP_ADDR}:443
vault auth enable --tls-skip-verify kubernetes
vault write --tls-skip-verify auth/kubernetes/config token_reviewer_jwt=$JWT kubernetes_host=$KUBERNETES_HOST kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
```

## Policy
```bash
# from local cli
export VAULT_SKIP_VERIFY=true
export VAULT_ADDR=https://$(oc get route vault --no-headers -o custom-columns=HOST:.spec.host)
export VAULT_TOKEN=${ROOT_TOKEN} # from vault operator init output
vault policy write demo-policy demo-policy.hcl
```

## Policy Role binding
We enable `demo-role` for the service account names `default` (`psql` namespace) and `vault` (`vault` namespace). The `psql` namespace and the `psql-policy` will be configured later.
```bash
vault write auth/kubernetes/role/demo-role \
    bound_service_account_names='vault,default' bound_service_account_namespaces='vault,psql' \
    policies='demo-policy, psql-policy' \
    ttl=2h
```

## Write secret
```bash
vault secrets enable -path=openshift kv
vault write openshift/anwendertreffen password=FooBar42!
```

## Verify using Vault Client
```bash
vault kv get openshift/anwendertreffen
```

returns:

```sh
====== Data ======
Key         Value
---         -----
password    FooBar42!
```

# Postgres
We will create a new project `psql` containing a postgres application with `psql` databse initialized.
Afterwards we configure and verify if the postgres db can authenticate towards `vault` using the serviceaccounts JWT.

## Project creation
```bash
oc new-project psql
```

## Deployment
```bash
# in psql project -> $(oc project psql)
oc new-app postgresql-persistent \
    --name=postgresql -lname=postgresql  \
    --param DATABASE_SERVICE_NAME=postgresql --param POSTGRESQL_DATABASE=anwenderdb \
    --param POSTGRESQL_USER=user --param POSTGRESQL_PASSWORD=password \
    --param VOLUME_CAPACITY=1Gi \
    --env POSTGRESQL_ADMIN_PASSWORD=postgres
```

## Enable kubernetes auth
```bash
JWT=$(oc sa get-token default -n psql)
vault write auth/kubernetes/login role=demo-role jwt=${JWT}
```

## Verify
```bash
VAULT_TOKEN=s.mCgDQH1SvtWT2lxdiqO2dvHj vault read openshift/anwendertreffen # from output before
```

returns:

```bash
Key                 Value
---                 -----
refresh_interval    768h
password            FooBar42!
```

# Vault Postgresql Plugin
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

## Policy
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

---

# Where to go now
At has been showed how vault can be configured in order to rotate postgres passwords for a certain ttl. This can easily modified for several other dbs (see https://www.vaultproject.io/docs/secrets/databases).
It is recommended to use the [Vault agent](https://www.vaultproject.io/docs/agent) to automate the initialization, unsealing and configuration of Vault. Another thing to think about is using the [Vault Injector](https://github.com/hashicorp/vault-k8s) which injects secrets in pods using sicecar container.

## Vault Agent
Lets create a Deployment, which instantiates a `vault-agent` container starting with the [`vault-agent`](vault-agent/vault-agent-config.yaml) config file:

```bash
oc project psql
oc apply -f vault-agent -n psql
```

### Verify in vault-agent pod
Now verify that the vault-agent Pod can authenticate to the vault using its ServiceAccount JWT token:

```bash
POD=$(oc get pods -lapp.kubernetes.io/name=vault-agent --no-headers -o custom-columns=NAME:.metadata.name -n psql)
oc -n psql exec $POD -- cat /var/run/secrets/vaultproject.io/token
```

returns:

```
s.1ZOURnygW4gV2IQ8TBSH08dv
```

This token could be then mounted into other Pods in order to authenticate towards Vault.

---
# Resources
* [https://www.openshift.com/blog/integrating-hashicorp-vault-in-openshift-4](https://www.openshift.com/blog/integrating-hashicorp-vault-in-openshift-4)
* [https://www.vaultproject.io/docs/secrets/databases/postgresql](https://www.vaultproject.io/docs/secrets/databases/postgresql)
* [https://github.com/openlab-red/hashicorp-vault-for-openshift](https://github.com/openlab-red/hashicorp-vault-for-openshift)
