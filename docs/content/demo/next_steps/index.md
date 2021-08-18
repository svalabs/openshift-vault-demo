---
title: '6. Where to go now'
date: 2018-11-28T15:14:39+10:00
weight: 7
---

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