# Allow a token to get a secret from the generic secret backend for the client role.
path "database/creds/psql-role" {
  capabilities = ["read"]
}

# allows listing and reading of secrets at path openshift/anwendertreffen
path "openshift/anwendertreffen" {
  capabilities = ["read", "list"]
}