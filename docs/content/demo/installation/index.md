---
title: '2. Installation'
date: 2019-02-11T19:27:37+10:00
weight: 3
---

We will create a role `demo-role` which uses the `kubernetes` auth method by using the service accounts JWT. This role then gets binded to a [`demo-policy`](demo-policy.hcl) which is allowed to read and list secrets at `openshift/anwendertreffen` in Vaults KV2 store.

## Usage
Clone this repository and follow the instructions:
```bash
git clone --recurse-submodules https://github.com/FalcoSuessgott/openshift-vault-demo
```

## Project creation
```bash
oc new-project vault
```

## Installation
```bash
export VAULT_DOMAIN=vault.apps.tld
helm install vault vault-helm -f override-values.yml --set server.route.host=${VAULT_DOMAIN}
```