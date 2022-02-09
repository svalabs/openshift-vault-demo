# Webinar Managing Secrets in OpenShift with Hashicorp Vault 20.01.2022

<!--ts-->
   * [Webinar Managing Secrets in OpenShift with Hashicorp Vault 20.01.2022](#webinar-managing-secrets-in-openshift-with-hashicorp-vault-20012022)
   * [0. Vault Installation](#0-vault-installation)
   * [1. Read and Write Secrets](#1-read-and-write-secrets)
      * [1. enable kv engine kv](#1-enable-kv-engine-kv)
      * [2. write secret secret:](#2-write-secret-secret)
      * [3. write my_policy:](#3-write-my_policy)
      * [4. read secret using Vault CLI](#4-read-secret-using-vault-cli)
   * [2. Kubernetes Auth Method](#2-kubernetes-auth-method)
      * [1. enable kubernetes engine](#1-enable-kubernetes-engine)
      * [2. create a role that uses the policy:](#2-create-a-role-that-uses-the-policy)
      * [3. verify using vault agent injector](#3-verify-using-vault-agent-injector)
   * [3. Create postgres app](#3-create-postgres-app)
   * [4. DB Secret Engine](#4-db-secret-engine)
      * [1. Enable db secret engine](#1-enable-db-secret-engine)
      * [2. Create Connection](#2-create-connection)
      * [3. Create a Database Role:](#3-create-a-database-role)
      * [4. Update my_policy:](#4-update-my_policy)
      * [5. verify credential generation](#5-verify-credential-generation)
   * [4. Create deployment that used the dynamic db secrets](#4-create-deployment-that-used-the-dynamic-db-secrets)
      * [1. view connection in WebUI](#1-view-connection-in-webui)

<!-- Added by: morelly_t1, at: Wed 09 Feb 2022 12:12:16 PM CET -->

<!--te-->

# 0. Vault Installation

```bash
oc project vault-demo # if the project name is different, please adjust "vault-demo" everywhere it is used
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
helm install vault hashicorp/vault --set "global.openshift=true" --set "server.dev.enabled=true" # if you use another name thant "vault", you have to adjust some steps
```

access the vault UI

```bash
oc port-forward service/vault 8200:8200 # open localhost:8200
```

# 1. Read and Write Secrets
## 1. enable kv engine `kv`
## 2. write secret `secret`:

```base
database_password=passw0rd
database_username=Us3Rname
```

## 3. write `my_policy`:

```hcl
path "kv/data/secret" {
  capabilities = ["read", "list"]
}
```

## 4. read secret using Vault CLI
```bash
# generate token with my_policy attached
VAULT_ADDR="http://127.0.0.1:8200" VAULT_TOKEN="root" vault token create -policy=my_policy
Key                  Value
---                  -----
token                s.ZtU19C1yEQTGsvyy1Fw8kMDO # our new token we use for further commands
token_accessor       qHzySDOtPkCmybeN6W84l44L
token_duration       768h
token_renewable      true
token_policies       ["default" "my_policy"]
identity_policies    []
policies             ["default" "my_policy"]

# verify we got the correct policy
VAULT_ADDR="http://127.0.0.1:8200" VAULT_TOKEN="s.ZtU19C1yEQTGsvyy1Fw8kMDO" vault token lookup
Key                 Value
---                 -----
accessor            qHzySDOtPkCmybeN6W84l44L
creation_time       1644397501
creation_ttl        768h
display_name        token
entity_id           n/a
expire_time         2022-03-13T09:05:01.34468316Z
explicit_max_ttl    0s
id                  s.ZtU19C1yEQTGsvyy1Fw8kMDO
issue_time          2022-02-09T09:05:01.344687913Z
meta                <nil>
num_uses            0
orphan              false
path                auth/token/create
policies            [default my_policy] # my_policy is attached
renewable           true
ttl                 767h59m43s
type                service

# read kv secret
VAULT_ADDR="http://127.0.0.1:8200" VAULT_TOKEN="s.ZtU19C1yEQTGsvyy1Fw8kMDO" vault kv get kv/secret
======= Metadata =======
Key                Value
---                -----
created_time       2022-02-09T09:05:56.410144485Z
custom_metadata    <nil>
deletion_time      n/a
destroyed          false
version            1

========== Data ==========
Key                  Value
---                  -----
database_password    passw0rd # secrets we have written
database_username    passw0rd

# delete ends in 403 permission denied
VAULT_ADDR="http://127.0.0.1:8200" VAULT_TOKEN="s.ZtU19C1yEQTGsvyy1Fw8kMDO" vault kv delete kv/secret
Error deleting kv/secret: Error making API request.

URL: DELETE http://127.0.0.1:8200/v1/kv/data/secret
Code: 403. Errors:

* 1 error occurred:
        * permission denied # because our policy doesnt allow the delete capability
```

---
# 2. Kubernetes Auth Method
## 1. enable kubernetes engine
* kubernetes host: https://kubernetes.default.svc.cluster.local
* kubernetes CA cert: `ca.crt` from `vault` service account
* token reviewer jwt: `token` from `vault` service account

## 2. create a role that uses the policy:
Access -> Auth Methods -> View Configuration -> Roles
* Name : `my_role`
* Bound SA names: `vault` (Service account, created by helm)
* Bound SA ns: `vault-demo` (current namespace)
* Policies: `my_policy`

If you use another service account here, make sure he has the `role-tokenreview-binding`:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: role-tokenreview-binding
  namespace: vault-demo
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
  - kind: ServiceAccount
    name: vault
    namespace: vault-demo
```

## 3. verify using vault agent injector

create the following deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: static-secret
  labels:
    app: static-secret
spec:
  selector:
    matchLabels:
      app: static-secret
  replicas: 1
  template:
    metadata:
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "my_role" # kubernetes auth role
        vault.hashicorp.com/agent-inject-secret-database-config.txt: 'kv/data/secret' # path to secret
        vault.hashicorp.com/agent-inject-template-database-config.txt: |
          {{- with secret "kv/data/secret" -}}
          username={{ .Data.data.database_username }}
          password={{ .Data.data.database_password }}
          {{- end -}}
      labels:
        app: static-secret
    spec:
      serviceAccountName: vault # service account
      containers:
        - name: static-secret
          image: nicholasjackson/fake-service:v0.7.3
```

verify secret has been written to filesystem

```bash
# in the static-secret pod
cat /vault/secrets/database-config.txt
```

# 3. Create postgres app

```bash
oc new-app postgresql-persistent --name=postgresql -lname=postgresql \
  --param DATABASE_SERVICE_NAME=postgresql \
  --param POSTGRESQL_DATABASE=my_db \
  --param POSTGRESQL_USER=user \
  --param POSTGRESQL_PASSWORD=password \
  --param VOLUME_CAPACITY=1Gi \
  --env POSTGRESQL_ADMIN_PASSWORD=postgres
```

# 4. DB Secret Engine
## 1. Enable db secret engine
* Secrets -> Enable -> Database

## 2. Create Connection
* DB Plugin: `postgresql-database-plugin`
* Connection name: `my-db`
* Conection URL: `postgresql://{{username}}:{{password}}@postgresql.vault-demo.svc:5432/my_db?sslmode=disable` # note the postgresql service used here
* Username: `user`
* Password: `password`

## 3. Create a Database Role:
* Role name: `my_role`
* Database name: `my_db`
* Type of role: `dynamic`
* [x] TTL: `180 Seconds`
* [x] Max TTL: `24 hours`
* Creation Statement:

```sql
CREATE ROLE "{{name}}" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';  GRANT SELECT ON ALL TABLES IN SCHEMA public TO "{{name}}";
```

## 4. Update `my_policy`:
```hcl
path "kv/data/secret" {
  capabilities = ["read", "list"]
}

path "database/creds/my_role" {
  capabilities = ["read"]
}
```

## 5. verify credential generation
* Database -> Roles -> my_role -> new credentials

if you instead receive:
```bash
pq: permission denied to create role
```

execute in the psql pod

```sql
ALTER ROLE "user" CREATEROLE;
```

# 4. Create deployment that used the dynamic db secrets

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dynamic-secret
  labels:
    app: dynamic-secret
spec:
  selector:
    matchLabels:
      app: dynamic-secret
  replicas: 1
  template:
    metadata:
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "my_role" # kubernetes auth role
        vault.hashicorp.com/agent-inject-secret-database-config.txt: 'database/creds/my_role' # path to dynamic creds
        vault.hashicorp.com/agent-inject-template-database-config.txt: |
          {{- with secret "database/creds/my_role" -}}
            export DATABASE_URL=postgres://{{ .Data.username }}:{{ .Data.password }}@postgresql.vault-demo.svc:5432/my_db?sslmode=disable
          {{- end -}}
      labels:
        app: dynamic-secret
    spec:
      serviceAccountName: vault # service account
      containers:
        - name: dynamic-secret
          image: sosedoff/pgweb
          args:
            ['sh', '-c', 'source /vault/secrets/database-config.txt && /usr/bin/pgweb --bind=0.0.0.0 --listen=8081']
```

## 1. view connection in WebUI

```bash
oc port-forward deployment/website 8081 8081
```
