#!/bin/bash

# Vault configuration
VAULT_ADDR="$(oc get route hashicorp-vault-server -n vault --template='https://{{.spec.host}}')"
VAULT_TOKEN="root"                  # Default token in dev mode


echo -e "\n========================="
echo -e "= Create Static Secrets ="
echo -e "=========================\n"

# Inline JSON definition of secrets
SECRETS_JSON='[
    {
        "path": "secret/data/demo1",
        "data": {
            "key1": "value1",
            "key2": "value2"
        }
    },
    {
        "path": "secret/data/demo2",
        "data": {
            "key1": "value3",
            "key2": "value4"
        }
    },
    {
        "path": "secret/data/demo3",
        "data": {
            "key1": "value5",
            "key2": "value6"
        }
    }
]'

# Parse JSON and upload secrets
echo -e "\nCreating static Secrets..."
for row in $(echo "$SECRETS_JSON" | jq -c '.[]'); do
    path=$(echo "$row" | jq -r '.path')
    data=$(echo "$row" | jq -c '.data')

    echo "Writing secret to $path"
    curl -s \
        --header "X-Vault-Token: $VAULT_TOKEN" \
        --request POST \
        --data "{\"data\":$data}" \
        "$VAULT_ADDR/v1/$path" > /dev/null

    if [ $? -eq 0 ]; then
        echo "Successfully wrote secret to $path"
    else
        echo "Failed to write secret to $path"
    fi
done


echo -e "\n==================="
echo -e "= Create Policies ="
echo -e "===================\n"

echo -e "\nCreating policy demo-get..."
read -r -d '' DEMO_GET_POLICY << EOM
path "secret/data/*" {
  capabilities = ["read"]
}
EOM
curl -s \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request PUT \
    --data "{\"policy\": $(echo "$DATABASE_CREATE_POLICY" | jq -R -s .)}" \ \
    "$VAULT_ADDR/v1/sys/policies/acl/demo-get" > /dev/null

if [ $? -eq 0 ]; then
    echo "Policy demo-get created"
else
    echo "Failed to create policy demo-get"
fi


# This is for External Secrets Operator PushSecret
echo -e "\nCreating policy database-create..."
read -r -d '' DATABASE_CREATE_POLICY << EOM
path "secret/data/*" {
  capabilities = ["create", "read", "update"]
}

path "secret/metadata/*" {
  capabilities = ["create", "read", "update"]
}
EOM
curl -s \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request PUT \
    --data "{\"policy\": $(echo "$DATABASE_CREATE_POLICY" | jq -R -s .)}" \
    "$VAULT_ADDR/v1/sys/policies/acl/database-create" > /dev/null

if [ $? -eq 0 ]; then
    echo "Policy database-create created"
else
    echo "Failed to create policy database-create"
fi



echo -e "\nCreating policy pki-mgmt..."
read -r -d '' PKI_MGMT_POLICY << EOM
# Work with transform secrets engine
# path "sys/managed-keys/*" {
#   capabilities = [ "create", "read", "update", "list" ]
# }

# Enable secrets engine
path "pki/*" {
  capabilities = [ "create", "read", "update", "delete", "list" ]
}

# List enabled secrets engine
path "sys/mounts" {
  capabilities = [ "read", "list" ]
}

# Tune mounts
path "sys/mounts/pki/tune" {
  capabilities = ["create", "update"]
}
EOM
curl -s \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request PUT \
    --data "{\"policy\": $(echo "$PKI_MGMT_POLICY" | jq -R -s .)}" \
    "$VAULT_ADDR/v1/sys/policies/acl/pki-mgmt" > /dev/null

if [ $? -eq 0 ]; then
    echo "Policy pki-mgmt created"
else
    echo "Failed to create policy pki-mgmt"
fi


echo -e "\nCreating policy dynamic-db..."
read -r -d '' DYNAMIC_POLICY << EOM
# Allow reading dynamic secrets
path "database/*" {
  capabilities = ["read", "list"]
}

# Allow creating dynamic credentials (if needed)
path "database/creds/*" {
  capabilities = ["read", "list"]
}
EOM
curl -s \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request PUT \
    --data "{\"policy\": $(echo "$DYNAMIC_POLICY" | jq -R -s .)}" \
    "$VAULT_ADDR/v1/sys/policies/acl/dynamic-db" > /dev/null

if [ $? -eq 0 ]; then
    echo "Policy dynamic-db created"
else
    echo "Failed to create policy dynamic-db"
fi


echo -e "\n======================"
echo -e "= K8s Authentication ="
echo -e "======================\n"

# Enable Kubernetes authentication
echo -e "\nEnabling Kubernetes authentication..."
curl -s \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data '{"type": "kubernetes"}' \
    "$VAULT_ADDR/v1/sys/auth/kubernetes" > /dev/null

if [ $? -eq 0 ]; then
    echo "Kubernetes authentication enabled"
else
    echo "Failed to enable Kubernetes authentication"
fi


# Configure the Kubernetes authentication method
echo -e "\nConfiguring Kubernetes authentication..."
KUBERNETES_SERVICE_HOST=172.30.0.1
KUBERNETES_SERVICE_PORT=443
curl -s \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data "{
        \"kubernetes_host\": \"https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT\"
    }" \
    "$VAULT_ADDR/v1/auth/kubernetes/config" > /dev/null

if [ $? -eq 0 ]; then
    echo "Kubernetes authentication configured"
else
    echo "Failed to configure Kubernetes authentication"
fi


# Create a role binding Kubernetes service account to the policy
echo -e "\nCreating role webapp..."
read -r -d '' WEBAPP_ROLE << EOM
{
  "bound_service_account_names": ["*"],
  "bound_service_account_namespaces": ["*"],
  "policies": ["demo-get", "database-create", "pki-mgmt", "dynamic-db"],
  "ttl": "1h"
}
EOM
curl -s \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data "$WEBAPP_ROLE" \
    "$VAULT_ADDR/v1/auth/kubernetes/role/webapp" > /dev/null

if [ $? -eq 0 ]; then
    echo "Role webapp created"
else
    echo "Failed to create role webapp"
fi


echo -e "\n=========================="
echo -e "= AppRole Authentication ="
echo -e "==========================\n"

# Enable AppRole authentication
echo -e "\nEnabling AppRole authentication..."
curl -k -s \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data '{"type": "approle"}' \
    "$VAULT_ADDR/v1/sys/auth/approle" > /dev/null

if [ $? -eq 0 ]; then
    echo "AppRole authentication enabled"
else
    echo "Failed to enable AppRole authentication"
fi


# Binding an AppRole approle to demo-get policy
echo -e "\nBinding an AppRole approle to demo-get policy..."
read -r -d '' ARGOCD_APPROLE << EOM
{
  "secret_id_ttl": "120h",
  "token_num_uses": 1000,
  "token_ttl": "120h",
  "token_max_ttl": "120h",
  "secret_id_num_uses": 4000,
  "policies": ["demo-get"]
}
EOM
curl -k -s \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data "$ARGOCD_APPROLE" \ \
    "$VAULT_ADDR/v1/auth/approle/role/argocd" > /dev/null

if [ $? -eq 0 ]; then
    echo "AppRole argocd created"
else
    echo "Failed to create AppRole argocd"
fi

# Retrieve the role_id for argocd
echo -e "\nRetrieving role_id for AppRole argocd..."
ROLE_ID=$(curl -k -s \
            --header "X-Vault-Token: $VAULT_TOKEN" \
            "$VAULT_ADDR/v1/auth/approle/role/argocd/role-id" | jq -r '.data.role_id')

if [ $? -eq 0 ] && [ ! -z "$ROLE_ID" ]; then
    echo "Retrieved role_id for argocd: $ROLE_ID"
else
    echo "Failed to retrieve role_id for argocd"
fi

# Generate a secret_id for argocd
echo -e "\nGenerating secret_id for AppRole argocd..."
SECRET_ID=$(curl -k -s \
              --header "X-Vault-Token: $VAULT_TOKEN" \
              --request POST \
              "$VAULT_ADDR/v1/auth/approle/role/argocd/secret-id" | jq -r '.data.secret_id')

if [ $? -eq 0 ] && [ ! -z "$SECRET_ID" ]; then
    echo "Generated secret_id for argocd: $SECRET_ID"
else
    echo "Failed to generate secret_id for argocd"
fi



echo -e "\n============================"
echo -e "= Setup PKI secrets engine ="
echo -e "============================\n"
# This section is based on the official documentation
# https://developer.hashicorp.com/vault/docs/secrets/pki/setup

# Enable PKI secrets engine
echo -e "\nEnabling PKI secrets engine..."
curl -s \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data '{"type":"pki"}' \
    "$VAULT_ADDR/v1/sys/mounts/pki" > /dev/null

if [ $? -eq 0 ]; then
    echo "PKI secrets engine enabled"
else
    echo "Failed to enable PKI secrets engine"
fi

# Tune PKI TTL
echo -e "\nTuning PKI TTL..."
curl -s \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data '{"max_lease_ttl":"8760h"}' \
    "$VAULT_ADDR/v1/sys/mounts/pki/tune" > /dev/null

if [ $? -eq 0 ]; then
    echo "PKI TTL tuned to 1 year"
else
    echo "Failed to tune PKI TTL"
fi

# Generate Root CA
echo -e "\nGenerating Root CA..."
read -r -d '' ROOT_CA << EOM
{
    "common_name": "my-website.com",
    "ttl": "8760h"
}
EOM

curl -s \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data "$ROOT_CA" \
    "$VAULT_ADDR/v1/pki/root/generate/internal" > /dev/null

if [ $? -eq 0 ]; then
    echo "Root CA generated"
else
    echo "Failed to generate Root CA"
fi

# Configure URLs
echo -e "\nConfiguring URLs..."
read -r -d '' URLS << EOM
{
    "issuing_certificates": ["http://127.0.0.1:8200/v1/pki/ca"],
    "crl_distribution_points": ["http://127.0.0.1:8200/v1/pki/crl"]
}
EOM

curl -s \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data "$URLS" \
    "$VAULT_ADDR/v1/pki/config/urls" > /dev/null

if [ $? -eq 0 ]; then
    echo "URLs configured"
else
    echo "Failed to configure URLs"
fi

# Create PKI role
echo -e "\nCreating PKI role..."
read -r -d '' PKI_ROLE << EOM
{
    "allowed_domains": "my-website.com",
    "allow_subdomains": true,
    "max_ttl": "72h"
}
EOM

curl -s \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data "$PKI_ROLE" \
    "$VAULT_ADDR/v1/pki/roles/example-dot-com" > /dev/null

if [ $? -eq 0 ]; then
    echo "PKI role example-dot-com created"
else
    echo "Failed to create PKI role"
fi


echo -e "\n============================"
echo -e "= Setup DB secrets engine  ="
echo -e "============================\n"
# This section is based on the official documentation
# https://developer.hashicorp.com/vault/docs/secrets/databases

# Enable DB secrets engine
echo -e "\nEnabling DB secrets engine..."
curl -s \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data '{"type":"database"}' \
    "$VAULT_ADDR/v1/sys/mounts/database" > /dev/null

if [ $? -eq 0 ]; then
    echo "DB secrets engine enabled"
else
    echo "Failed to enable DB secrets engine"
fi

# Configure MySQL connection
echo -e "\nConfiguring MySQL connection..."
read -r -d '' DB_CONFIG << EOM
{
    "plugin_name": "mysql-database-plugin",
    "connection_url": "{{username}}:{{password}}@tcp(mysql.vault.svc:3306)/",
    "allowed_roles": "my-db-role",
    "username": "mysql-user",
    "password": "mysql-password",
    "tls_skip_verify": true,
    "max_open_connections": 5,
    "max_idle_connections": 2
}
EOM

curl -s \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data "$DB_CONFIG" \
    "$VAULT_ADDR/v1/database/config/my-mysql" > /dev/null

if [ $? -eq 0 ]; then
    echo "MySQL connection configured"
else
    echo "Failed to configure MySQL connection"
fi

# Rotate root credentials
echo -e "\nRotating MySQL root credentials..."
curl -s \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    "$VAULT_ADDR/v1/database/rotate-root/my-mysql" > /dev/null

if [ $? -eq 0 ]; then
    echo "MySQL root credentials rotated"
else
    echo "Failed to rotate MySQL credentials"
fi

# Create MySQL role
echo -e "\nCreating MySQL role..."
read -r -d '' DB_ROLE << EOM
{
    "db_name": "my-mysql",
    "creation_statements": [
        "CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}';",
        "GRANT SELECT, INSERT, UPDATE, DELETE ON myapp.* TO '{{name}}'@'%';",
        "ALTER USER '{{name}}'@'%' WITH MAX_USER_CONNECTIONS 3"
    ],
    "default_ttl": "1h",
    "max_ttl": "24h",
    "revocation_statements": [
        "DROP USER '{{name}}'@'%';"
    ]
}
EOM

curl -s \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data "$DB_ROLE" \
    "$VAULT_ADDR/v1/database/roles/my-db-role" > /dev/null

if [ $? -eq 0 ]; then
    echo "MySQL role my-db-role created"
else
    echo "Failed to create MySQL role"
fi
