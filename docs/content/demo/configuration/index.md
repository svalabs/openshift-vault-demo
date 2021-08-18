---
title: '3. Configuration'
date: 2019-02-11T19:27:37+10:00
weight: 4
---

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