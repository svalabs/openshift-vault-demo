---
title: '4. PostgresDB Setup'
date: 2018-11-28T15:14:39+10:00
weight: 5
---

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