# secrets-storage-csi-demo
secrets-storage-csi-demo demo


Prerequisitos

- Red Hat Secrets Storage CIS Operator
- Red Hat GitOps Operator

Steps

An OpenShift cluster
OpenShift Secrets Store CSI Driver Operator deployed and a default ClusterCSIDriver created
A Vault server deployed on the that OpenShift Cluster


Run create_vault_secrets.sh for filling Vault demo secrets

Kubernetes authentication:
vault write auth/kubernetes/config kubernetes_host=https://{cluster API}:6443

Create a Vault policy
vault policy write database-app - <<EOF
path "kv/data/team1/db-pass" {
  capabilities = ["read"]
}
EOF

Create a user:
vault write auth/kubernetes/role/database bound_service_account_names=db-app-sa bound_service_account_namespaces=db-app policies=database-app ttl=20m

