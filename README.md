# Secrets Storage CSI Demo

Este proyecto demuestra el uso de **Secrets Store CSI Driver** y **External Secrets Operator** con **HashiCorp Vault** en OpenShift, gestionado mediante **ArgoCD**.

## Descripción

El proyecto incluye:
- **HashiCorp Vault Server**: Servidor Vault desplegado en OpenShift
- **External Secrets Operator (ESO)**: Operador para sincronizar secretos desde Vault a Kubernetes
- **Secrets Store CSI Driver**: Driver CSI para montar secretos como volúmenes
- **Configuración RBAC**: Permisos necesarios para que ArgoCD pueda desplegar recursos

## Prerequisitos

Antes de ejecutar este proyecto, asegúrate de tener:

1. **OpenShift Cluster** funcionando
2. **Red Hat GitOps Operator** instalado y configurado
3. **Red Hat Secrets Store CSI Driver Operator** instalado con un `ClusterCSIDriver` por defecto creado
4. Acceso al cluster con permisos de administrador o suficientes para:
   - Crear Applications en el namespace `openshift-gitops`
   - Crear Roles y RoleBindings en múltiples namespaces
   - Crear ClusterRoles y ClusterRoleBindings

### Instalación del Secrets Store CSI Driver Operator

El **Secrets Store CSI Driver Operator** es necesario para que las aplicaciones puedan montar secretos desde Vault como volúmenes. Sigue estos pasos para instalarlo:

#### 1. Instalar el Operador desde OperatorHub

1. Accede a la consola web de OpenShift
2. Ve a **Operators** → **OperatorHub**
3. Busca **"Secrets Store CSI Driver Operator"** o **"Red Hat Secrets Store CSI Driver Operator"**
4. Haz clic en **Install**
5. Selecciona el namespace donde instalar el operador (por ejemplo, `openshift-operators`)
6. Acepta los términos y haz clic en **Install**

#### 2. Verificar la instalación

Espera a que el operador esté instalado y verifica su estado:

```bash
# Verificar que el operador esté instalado
oc get csv -n openshift-operators | grep secrets-store-csi

# Verificar que el pod del operador esté ejecutándose
oc get pods -n openshift-operators | grep secrets-store-csi
```

#### 3. Crear el ClusterCSIDriver

Una vez instalado el operador, necesitas crear un `ClusterCSIDriver` para habilitar el driver CSI:

```bash
# Crear el ClusterCSIDriver
cat <<EOF | kubectl apply -f -
apiVersion: operator.openshift.io/v1
kind: ClusterCSIDriver
metadata:
  name: secrets-store.csi.k8s.io
spec:
  managementState: Managed
  logLevel: Normal
  operatorLogLevel: Normal
EOF
```

#### 4. Verificar el ClusterCSIDriver

Verifica que el ClusterCSIDriver esté creado y en estado correcto:

```bash
# Verificar el ClusterCSIDriver
oc get clustercsidriver secrets-store.csi.k8s.io

# Verificar que el DaemonSet del driver esté desplegado
oc get daemonset -n openshift-cluster-csi-drivers | grep secrets-store
```

El DaemonSet `secrets-store-csi-driver` debería estar desplegado y los pods deberían estar en estado `Running`.

## Orden de Ejecución

Es importante seguir este orden para evitar errores de permisos y dependencias:

### 1. Aplicar RBAC para ArgoCD

Primero, aplica las configuraciones RBAC que otorgan permisos al service account de ArgoCD en los namespaces necesarios:

```bash
# RBAC para namespace vault
kubectl apply -f applications/application-argocd-vault-rbac.yaml

# RBAC para namespace external-secrets
kubectl apply -f applications/application-argocd-external-secrets-rbac.yaml

# RBAC para namespace test-secrets
kubectl apply -f applications/application-argocd-test-secrets-rbac.yaml

# RBAC para namespace db-app (necesario para Secrets Store CSI Driver)
kubectl apply -f applications/application-argocd-db-app-rbac.yaml

# RBAC para namespace kube-system (necesario para Secrets Store CSI Driver)
kubectl apply -f applications/application-argocd-kube-system-rbac.yaml

# RBAC para namespace openshift-cluster-csi-drivers (necesario para Secrets Store CSI Driver)
kubectl apply -f applications/application-argocd-openshift-cluster-csi-drivers-rbac.yaml
```

**Nota**: Estas Applications tienen `sync-wave: "-1"` para asegurar que se ejecuten antes que las demás. Los namespaces `kube-system` y `openshift-cluster-csi-drivers` son namespaces del sistema, por lo que pueden requerir permisos de administrador para crear Roles en ellos.

### 2. Aplicar ClusterRole para CRDs

Aplica el ClusterRole que permite a ArgoCD gestionar CustomResourceDefinitions:

```bash
kubectl apply -f applications/application-external-secrets-operator.yaml
```

Esto aplicará el `ClusterRole` y `ClusterRoleBinding` definidos al final del archivo para gestionar CRDs.

### 3. Desplegar Vault Server

```bash
kubectl apply -f applications/application-hashicorp-vault-server.yaml
```

Espera a que Vault esté completamente desplegado y accesible antes de continuar.

### 4. Desplegar External Secrets Operator

```bash
# La aplicación ESO ya está en el mismo archivo que el ClusterRole
# Si ya aplicaste el paso 2, solo necesitas verificar que la Application se sincronice
```

O aplica directamente:

```bash
kubectl apply -f applications/application-external-secrets-operator.yaml
```

### 5. Desplegar Secrets Store CSI Driver

Despliega la configuración del Secrets Store CSI Driver (CRDs, roles, providers, etc.):

```bash
kubectl apply -f applications/application-secrets-storage-csi.yaml
```

Esta Application desplegará:
- CustomResourceDefinitions para SecretProviderClass
- Configuración del Vault CSI Provider
- Roles y RoleBindings necesarios
- SecretProviderClass de ejemplo
- Pod de demostración que usa el CSI Driver

### 6. Verificar el despliegue

Verifica que todas las Applications estén sincronizadas:

```bash
kubectl get applications -n openshift-gitops
```

## Configuración de Vault

Una vez que Vault esté desplegado, necesitas configurarlo:

### 1. Acceder a Vault

Obtén la URL de Vault desde la ruta de OpenShift:

```bash
# Obtener la ruta de Vault
oc get route -n vault

# O acceder directamente si tienes port-forward
kubectl port-forward -n vault svc/hashicorp-vault-server 8200:8200
```

Accede a Vault en modo dev (token por defecto: `root`).

### 2. Habilitar el motor KV v2

```bash
vault secrets enable -path=secret kv-v2
```

### 3. Configurar autenticación de Kubernetes

```bash
# Obtener la URL de la API del cluster
CLUSTER_API=$(oc whoami --show-server)

# Configurar autenticación de Kubernetes
vault write auth/kubernetes/config \
  kubernetes_host=${CLUSTER_API}
```

### 4. Crear políticas de Vault

```bash
# Política para la aplicación de base de datos
vault policy write database-app - <<EOF
path "secret/data/team1/db-pass" {
  capabilities = ["read"]
}
EOF
```

### 5. Crear roles de Kubernetes

```bash
vault write auth/kubernetes/role/database \
  bound_service_account_names=db-app-sa \
  bound_service_account_namespaces=db-app \
  policies=database-app \
  ttl=20m
```

### 6. Crear secretos de ejemplo en Vault

Ejecuta el script proporcionado para crear secretos de demostración:

```bash
./create_vault_secrets.sh
```

Este script creará varios secretos de ejemplo en Vault que pueden ser utilizados por las aplicaciones.

## Verificación

### Verificar Applications de ArgoCD

```bash
kubectl get applications -n openshift-gitops
```

Todas las Applications deberían estar en estado `Synced` y `Healthy`.

### Verificar Vault

```bash
# Verificar pods de Vault
kubectl get pods -n vault

# Verificar servicios
kubectl get svc -n vault
```

### Verificar External Secrets Operator

```bash
# Verificar pods de ESO
kubectl get pods -n external-secrets

# Verificar CRDs instalados
kubectl get crd | grep external-secrets
```

### Verificar SecretStore y ExternalSecret

```bash
# Verificar SecretStore
kubectl get secretstore -n test-secrets

# Verificar ExternalSecret
kubectl get externalsecret -n test-secrets

# Verificar secretos sincronizados
kubectl get secrets -n test-secrets
```

### Verificar Secrets Store CSI Driver

```bash
# Verificar que el DaemonSet del driver esté ejecutándose
kubectl get daemonset -n openshift-cluster-csi-drivers | grep secrets-store

# Verificar pods del driver
kubectl get pods -n openshift-cluster-csi-drivers | grep secrets-store

# Verificar que el Vault CSI Provider esté ejecutándose
kubectl get daemonset -n openshift-cluster-csi-drivers | grep vault-csi-provider

# Verificar pods del Vault CSI Provider
kubectl get pods -n openshift-cluster-csi-drivers | grep vault-csi-provider

# Verificar SecretProviderClass
kubectl get secretproviderclass -n db-app

# Verificar el pod de demostración que usa el CSI Driver
kubectl get pods -n db-app
```

## Troubleshooting

### Error: "cannot create resource in namespace"

Si encuentras errores de permisos como:
```
deployments.apps is forbidden: User "system:serviceaccount:openshift-gitops:openshift-gitops-argocd-application-controller" cannot create resource "deployments" in API group "apps" in the namespace "external-secrets"
```

**Solución**: Asegúrate de haber aplicado las Applications RBAC primero (paso 1). Verifica que los Roles y RoleBindings estén creados:

```bash
kubectl get role,rolebinding -n external-secrets
kubectl get role,rolebinding -n test-secrets
kubectl get role,rolebinding -n vault
kubectl get role,rolebinding -n db-app
kubectl get role,rolebinding -n kube-system
kubectl get role,rolebinding -n openshift-cluster-csi-drivers
```

Si encuentras errores al crear Roles en `kube-system` o `openshift-cluster-csi-drivers`, puede que necesites aplicar estos RBAC manualmente con permisos de administrador:

```bash
# Aplicar RBAC manualmente para kube-system
kubectl apply -f deploy/rbac/argocd-kube-system-rbac.yaml

# Aplicar RBAC manualmente para openshift-cluster-csi-drivers
kubectl apply -f deploy/rbac/argocd-openshift-cluster-csi-drivers-rbac.yaml
```

### Error: CRDs no se pueden crear

Si External Secrets Operator no puede crear sus CRDs:

**Solución**: Verifica que el ClusterRole `argocd-crd-manager` esté aplicado:

```bash
kubectl get clusterrole argocd-crd-manager
kubectl get clusterrolebinding argocd-crd-binding
```

### Vault no es accesible

Si no puedes acceder a Vault:

1. Verifica que la ruta esté creada:
   ```bash
   oc get route -n vault
   ```

2. Verifica que el servicio esté funcionando:
   ```bash
   kubectl get svc -n vault
   ```

3. Usa port-forward como alternativa:
   ```bash
   kubectl port-forward -n vault svc/hashicorp-vault-server 8200:8200
   ```

### ExternalSecret no sincroniza secretos

Si los ExternalSecrets no están sincronizando:

1. Verifica el estado del ExternalSecret:
   ```bash
   kubectl describe externalsecret <nombre> -n test-secrets
   ```

2. Verifica que el SecretStore esté correctamente configurado:
   ```bash
   kubectl describe secretstore vault -n test-secrets
   ```

3. Verifica los logs del operador ESO:
   ```bash
   kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets
   ```

## Estructura del Proyecto

```
.
├── applications/                          # Applications de ArgoCD
│   ├── application-argocd-vault-rbac.yaml
│   ├── application-argocd-external-secrets-rbac.yaml
│   ├── application-argocd-test-secrets-rbac.yaml
│   ├── application-argocd-db-app-rbac.yaml
│   ├── application-argocd-kube-system-rbac.yaml
│   ├── application-argocd-openshift-cluster-csi-drivers-rbac.yaml
│   ├── application-external-secrets-operator.yaml
│   ├── application-hashicorp-vault-server.yaml
│   └── application-secrets-storage-csi.yaml
├── deploy/
│   ├── external-secrets/                  # Configuración de ESO
│   │   ├── secretstore-vault.yaml
│   │   └── externalsecret-eso-example.yaml
│   │   ├── rbac/                              # Configuraciones RBAC
│   │   ├── argocd-vault-rbac.yaml
│   │   ├── argocd-external-secrets-rbac.yaml
│   │   ├── argocd-test-secrets-rbac.yaml
│   │   ├── argocd-db-app-rbac.yaml
│   │   ├── argocd-kube-system-rbac.yaml
│   │   └── argocd-openshift-cluster-csi-drivers-rbac.yaml
│   └── secrets-storage/                   # Configuración CSI Driver
├── create_vault_secrets.sh                # Script para crear secretos en Vault
└── README.md
```

## Referencias

- [HashiCorp Vault Documentation](https://www.vaultproject.io/docs)
- [External Secrets Operator](https://external-secrets.io/)
- [Secrets Store CSI Driver](https://secrets-store-csi-driver.sigs.k8s.io/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
