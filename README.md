# OpenShift & Vault Demo
> [15. OpenShift Anwendertreffen](https://www.openshift-anwender.de/) 30.6.2021

This demo will create two OpenShifts project (`vault` and `psql`). The goal is to rotate postgres db passwords using Vaults [postgres-plugin](https://www.vaultproject.io/docs/secrets/databases/postgresql)Vault will be installed using hashicorps Vault [helm-chart](https://github.com/hashicorp/vault-helm). Postgres will be installed via OpenShifts app store.

---
## ToC
<!--ts-->
   * [OpenShift &amp; Vault Demo](#openshift--vault-demo)
      * [ToC](#toc)
   * [Prerequisites](#prerequisites)
   * [Usage](#usage)
   * [Vault](#vault)
      * [Project creation](#project-creation)
      * [Installation](#installation)
      * [Initialization](#initialization)
      * [Unsealing](#unsealing)
      * [Configuration](#configuration)
      * [Kubernetes Auth](#kubernetes-auth)
         * [create policy](#create-policy)
         * [bind policy to role](#bind-policy-to-role)
         * [write secret](#write-secret)
         * [verify](#verify)
   * [Postgres](#postgres)
      * [Project creation](#project-creation-1)
      * [Deployment](#deployment)
      * [Enable kubernetes auth](#enable-kubernetes-auth)
      * [Verify](#verify-1)
   * [Vault Postgresql Plugin](#vault-postgresql-plugin)
      * [vault databse plugin configuration](#vault-databse-plugin-configuration)
      * [role mapping](#role-mapping)
      * [psql policy](#psql-policy)
      * [psql role](#psql-role)
      * [verify in psql](#verify-in-psql)
   * [Resources](#resources)

<!-- Added by: morelly_t1, at: Mon 28 Jun 2021 04:51:29 PM CEST -->

<!--te-->

# Prerequisites
Tested with
* OpenShift v4.7.8
* `oc` v4.7.8
* `vault` v1.5.4

You will need a user who is able to create:
* `ClusterRole`,
* `ClusterRolebinding`,
* `MutatingWebhookConfiguration`,
* `Deployment`,
* `ServiceAccount`,
* `ConfigMap`,
* `Statefulset`,
* `Route`,
* `NetworkPolicy`,
* `PersistentVolumeClaim`

# Usage
Clone this repository and follow the instructions:
```bash
git clone --recurse-submodules https://github.com/FalcoSuessgott/openshift-vault-demo
```

# Vault
We will create a role `demo-role` which uses the `kubernetes` auth method by using the service accounts JWT. This role then gets binded to a [`demo-policy`](demo-policy.hcl) which is allowed to read and list secrets at `openshift/anwendertreffen` in Vaults KV2 store.

## Project creation
```bash
oc new-project vault
```

## Installation
```bash
helm install vault vault-helm/ -f override-valus.yaml
```

## Initialization
```bash
POD=$(oc get pods -lapp.kubernetes.io/name=vault --no-headers -o custom-columns=NAME:.metadata.name)
oc rsh $POD
vault operator init --tls-skip-verify -key-shares=1 -key-threshold=1 # in vault pod
```

## Unsealing
```bash
# save generated keys and token
export KEYS=QzlUGvdPbIcM83UxyjuGd2ws7flZdNimQVCNbUvI2aU=
export ROOT_TOKEN=s.UPBPfhDXYOtnv8mELhPA4br7
export VAULT_TOKEN=${ROOT_TOKEN}
vault operator unseal --tls-skip-verify $KEYS
```

## Configuration
```bash
# in $POD with env vars exported see step Unsealing
JWT=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
KUBERNETES_HOST=https://${KUBERNETES_PORT_443_TCP_ADDR}:443
vault auth enable --tls-skip-verify kubernetes
vault write --tls-skip-verify auth/kubernetes/config token_reviewer_jwt=$JWT kubernetes_host=$KUBERNETES_HOST kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
```

## Kubernetes Auth
### create policy
```bash
# from local cli
export VAULT_SKIP_VERIFY=true
export VAULT_ADDR=https://$(oc get route vault --no-headers -o custom-columns=HOST:.spec.host)
export VAULT_TOKEN=${ROOT_TOKEN} # from vault operator init output
vault policy write demo-policy demo-policy.hcl
```

### bind policy to role
```bash
vault write --tls-skip-verify auth/kubernetes/role/demo-role \
    bound_service_account_names=default bound_service_account_namespaces='app' \
    policies=demo-policy \
    ttl=2h
```

### write secret
```bash
vault secrets enable -path=openshift kv
vault write openshift/anwendertreffen password=FooBar42!
```

### verify
```bash
vault kv get openshift/anwendertreffen
    ====== Data ======
    Key         Value
    ---         -----
    password    FooBar42!
```

# Postgres
We will create a new project `psql` containing a postgres application with `psql` databse initialized.
Afterwards we configure and verify the postgres db can authenticate to `vault` using the serviceaccounts JWT.

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
    --param POSTGRESQL_USER=user --param POSTGRESQL_PASSWORD=redhat \
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
export VAULT_TOKEN=s.mCgDQH1SvtWT2lxdiqO2dvHj # from output before
vault read openshift/anwendertreffen
    ====== Data ======
    Key         Value
    ---         -----
    password    FooBar42!
```

# Vault Postgresql Plugin
We will enable and configure Vaults Postgresql database plugin with a maximum ttl of 24h. For this we add a new role `psql-role`. The role is binded to the [`psql-policy`](psql-policy.hcl). The role `demo-role` gets extends about the newly created policy. Finally, we verify the rotation of database passwords in the postgres shell.

## vault databse plugin configuration
```bash
vault secrets enable database
vault write database/config/postgresql \
    plugin_name=postgresql-database-plugin \
    allowed_roles="pg-readwrite" \
    connection_url="postgresql://{{username}}:{{password}}@postgresql.app.svc:5432/anwenderdb?sslmode=disable" \
    username="postgres" \
    password="postgres"
```

## role mapping
```bash
vault write database/roles/psql-role \
    db_name=postgresql \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
        GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
    default_ttl="1h" \
    max_ttl="24h"
```


## psql policy
```bash
vault policy write psql-polciy psql-policy.hcl
```

## psql role
```bash
vault write auth/kubernetes/role/demo-role \
    bound_service_account_names=default bound_service_account_namespaces='psql' \
    policies=psql-polciy \
    ttl=2h
```

## verify in psql
```bash
POD=$(oc get po --no-headers -o custom-columns=NAME:.metadata.name -lname=postgresql)
oc rsh $POD # in postgres pod shell
psql # in psql shell
\du
```

---
# Resources
* https://www.openshift.com/blog/integrating-hashicorp-vault-in-openshift-4
* https://www.vaultproject.io/docs/secrets/databases/postgresql
* https://github.com/openlab-red/hashicorp-vault-for-openshift

