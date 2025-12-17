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

### 5. Configurar Pod Security para namespaces

Los namespaces `test-secrets` y `openshift-cluster-csi-drivers` necesitan tener la etiqueta de seguridad de pods configurada como `privileged` para permitir que los pods con volúmenes CSI se ejecuten. Esto se aplicará automáticamente cuando se despliegue la Application de secrets-storage-csi, pero también puedes aplicarlo manualmente:

```bash
# Configurar pod security para test-secrets
oc label ns test-secrets "pod-security.kubernetes.io/enforce=privileged" --overwrite
oc label ns test-secrets "pod-security.kubernetes.io/audit=privileged" --overwrite
oc label ns test-secrets "pod-security.kubernetes.io/warn=privileged" --overwrite

# Configurar pod security para openshift-cluster-csi-drivers
oc label ns openshift-cluster-csi-drivers "pod-security.kubernetes.io/enforce=privileged" --overwrite
oc label ns openshift-cluster-csi-drivers "pod-security.kubernetes.io/audit=privileged" --overwrite
oc label ns openshift-cluster-csi-drivers "pod-security.kubernetes.io/warn=privileged" --overwrite
```

O aplicar los archivos YAML directamente:

```bash
kubectl apply -f deploy/secrets-storage/test-secrets-namespace.yaml
kubectl apply -f deploy/secrets-storage/openshift-cluster-csi-drivers-namespace.yaml
```

**Nota**: Los archivos `test-secrets-namespace.yaml` y `openshift-cluster-csi-drivers-namespace.yaml` se incluyen en la carpeta `deploy/secrets-storage` y se aplicarán automáticamente cuando se despliegue la Application de secrets-storage-csi. Sin embargo, si los namespaces ya existen (creados por otras Applications), puede que necesites aplicar las etiquetas manualmente.

### 6. Desplegar Secrets Store CSI Driver

Despliega la configuración del Secrets Store CSI Driver (CRDs, roles, providers, etc.):

```bash
kubectl apply -f applications/application-secrets-storage-csi.yaml
```

Esta Application desplegará:
- CustomResourceDefinitions para SecretProviderClass
- SecurityContextConstraint (SCC) para el Vault CSI Provider (requerido en OpenShift)
- Configuración del Vault CSI Provider (DaemonSet)
- Roles y RoleBindings necesarios
- Configuración de los namespaces `test-secrets` y `openshift-cluster-csi-drivers` con pod security `privileged`
- SecretProviderClass de ejemplo en el namespace `test-secrets`
- Deployment de demostración que usa el CSI Driver en el namespace `test-secrets`

### 7. Verificar el despliegue

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
vault write auth/kubernetes/role/webapp \
  bound_service_account_names=default \
  bound_service_account_namespaces=test-secrets \
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
kubectl get secretproviderclass -n test-secrets

# Verificar el deployment de demostración que usa el CSI Driver
kubectl get deployment -n test-secrets
kubectl get pods -n test-secrets

# Verificar los logs del deployment para ver los secretos montados
kubectl logs -n test-secrets -l app=test-secrets-store-csi-driver
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

### Error: Pod Security Policy - "uses an inline volume provided by CSIDriver"

Si encuentras el siguiente error al desplegar el deployment `test-secrets-store-csi-driver`:

```
pods "test-secrets-store-csi-driver-" is forbidden: test-secrets-store-csi-driver uses an inline volume provided by CSIDriver secrets-store.csi.k8s.io and namespace test-secrets has a pod security enforce level that is lower than privileged
```

**Solución**: El namespace `test-secrets` necesita tener la etiqueta de seguridad de pods configurada como `privileged` para permitir que los pods con volúmenes CSI se ejecuten. Aplica la siguiente configuración:

```bash
# Aplicar las etiquetas de pod security
oc label ns test-secrets "pod-security.kubernetes.io/enforce=privileged" --overwrite
oc label ns test-secrets "pod-security.kubernetes.io/audit=privileged" --overwrite
oc label ns test-secrets "pod-security.kubernetes.io/warn=privileged" --overwrite
```

O verifica que el namespace tenga las etiquetas correctas:

```bash
# Verificar las etiquetas del namespace
oc get namespace test-secrets -o yaml | grep pod-security
```

El namespace debería tener las siguientes etiquetas:
- `pod-security.kubernetes.io/enforce: privileged`
- `pod-security.kubernetes.io/audit: privileged`
- `pod-security.kubernetes.io/warn: privileged`

### Error: "provider not found: provider 'vault'"

Si encuentras el siguiente error al desplegar el deployment `test-secrets-store-csi-driver`:

```
failed to mount secrets store objects for pod test-secrets/test-secrets-store-csi-driver-, err: error connecting to provider "vault": provider not found: provider "vault"
```

**Solución**: Este error indica que el Vault CSI Provider no está disponible. Sigue estos pasos para solucionarlo:

0. **Aplicar SecurityContextConstraint (SCC) para el Vault CSI Provider** (requerido en OpenShift):

   En OpenShift, el DaemonSet del Vault CSI Provider necesita un SCC que permita contenedores privileged y volúmenes hostPath:

   ```bash
   # Aplicar el SCC y los bindings necesarios
   kubectl apply -f deploy/secrets-storage/vault-csi-provider-scc.yaml
   ```

   Esto creará:
   - Un SecurityContextConstraint personalizado `vault-csi-provider` que permite privileged y hostPath
   - Un ClusterRole y ClusterRoleBinding que asignan el SCC al service account del vault-csi-provider

1. **Verificar que el SCC esté aplicado y asignado correctamente**:

   ```bash
   # Verificar el SCC
   oc get scc vault-csi-provider

   # Verificar el ClusterRoleBinding
   oc get clusterrolebinding vault-csi-provider-scc

   # Verificar que el service account tenga acceso al SCC
   oc adm policy who-can use scc vault-csi-provider
   ```

2. **Verificar que el namespace `openshift-cluster-csi-drivers` tenga pod security `privileged`**:

   ```bash
   # Aplicar las etiquetas de pod security al namespace
   oc label ns openshift-cluster-csi-drivers "pod-security.kubernetes.io/enforce=privileged" --overwrite
   oc label ns openshift-cluster-csi-drivers "pod-security.kubernetes.io/audit=privileged" --overwrite
   oc label ns openshift-cluster-csi-drivers "pod-security.kubernetes.io/warn=privileged" --overwrite
   ```

   O aplicar el archivo YAML:

   ```bash
   kubectl apply -f deploy/secrets-storage/openshift-cluster-csi-drivers-namespace.yaml
   ```

3. **Verificar que el DaemonSet del Vault CSI Provider esté ejecutándose**:

   ```bash
   # Verificar el DaemonSet
   kubectl get daemonset vault-csi-provider -n openshift-cluster-csi-drivers

   # Verificar los pods del provider
   kubectl get pods -n openshift-cluster-csi-drivers | grep vault-csi-provider

   # Verificar los logs si hay problemas
   kubectl logs -n openshift-cluster-csi-drivers -l app.kubernetes.io/name=vault-csi-provider
   ```

4. **Verificar que el socket del provider esté disponible en los nodos**:

   El Vault CSI Provider crea un socket en `/etc/kubernetes/secrets-store-csi-providers/vault.sock` en cada nodo. Puedes verificar esto ejecutando:

   ```bash
   # Verificar en un nodo (requiere acceso SSH o debug pod)
   oc debug node/<node-name> -- chroot /host ls -la /etc/kubernetes/secrets-store-csi-providers/
   ```

5. **Verificar que el Secrets Store CSI Driver esté configurado correctamente**:

   ```bash
   # Verificar el DaemonSet del driver
   kubectl get daemonset csi-secrets-store -n kube-system

   # Verificar los pods del driver
   kubectl get pods -n kube-system | grep csi-secrets-store
   ```

6. **Reiniciar los pods del Vault CSI Provider si es necesario**:

   ```bash
   # Eliminar los pods para que se recreen
   kubectl delete pods -n openshift-cluster-csi-drivers -l app.kubernetes.io/name=vault-csi-provider
   ```

**Nota**: 
- El archivo `vault-csi-provider-scc.yaml` se incluye en la carpeta `deploy/secrets-storage` y se aplicará automáticamente cuando se despliegue la Application de secrets-storage-csi.
- El archivo `openshift-cluster-csi-drivers-namespace.yaml` se incluye en la carpeta `deploy/secrets-storage` y se aplicará automáticamente cuando se despliegue la Application de secrets-storage-csi. Sin embargo, si el namespace ya existe (creado por el operador), puede que necesites aplicar las etiquetas manualmente.

### Error: SecurityContextConstraint - "unable to validate against any security context constraint"

Si encuentras el siguiente error al desplegar el DaemonSet del Vault CSI Provider:

```
pods "vault-csi-provider-" is forbidden: unable to validate against any security context constraint: [provider "anyuid": Forbidden: not usable by user or serviceaccount, spec.volumes[0]: Invalid value: "hostPath": hostPath volumes are not allowed to be used, provider restricted-v2: .containers[0].privileged: Invalid value: true: Privileged containers are not allowed...]
```

**Solución**: En OpenShift, necesitas crear un SecurityContextConstraint (SCC) que permita contenedores privileged y volúmenes hostPath. Aplica el siguiente archivo:

```bash
# Aplicar el SCC y los bindings necesarios
kubectl apply -f deploy/secrets-storage/vault-csi-provider-scc.yaml
```

Esto creará:
- Un SecurityContextConstraint `vault-csi-provider` que permite:
  - Contenedores privileged
  - Volúmenes hostPath
  - Todas las capacidades
- Un ClusterRole y ClusterRoleBinding que asignan el SCC al service account `vault-csi-provider` en el namespace `openshift-cluster-csi-drivers`

Verifica que el SCC esté aplicado:

```bash
# Verificar el SCC
oc get scc vault-csi-provider

# Verificar el ClusterRoleBinding
oc get clusterrolebinding vault-csi-provider-scc

# Verificar que el DaemonSet pueda crear pods ahora
kubectl get daemonset vault-csi-provider -n openshift-cluster-csi-drivers
kubectl get pods -n openshift-cluster-csi-drivers | grep vault-csi-provider
```

**Nota sobre el error de patch del SCC**: Si ves un error de timeout al parchear el SCC, puede ser porque el SCC ya existe y ArgoCD está intentando actualizarlo. En este caso, puedes aplicar el SCC manualmente antes de desplegar la Application, o simplemente esperar a que ArgoCD complete la sincronización en un segundo intento. El ClusterRole `argocd-crd-manager` ya tiene permisos para crear y parchear SecurityContextConstraints.

## Estructura del Proyecto

```
.
├── applications/                          # Applications de ArgoCD
│   ├── application-argocd-vault-rbac.yaml
│   ├── application-argocd-external-secrets-rbac.yaml
│   ├── application-argocd-test-secrets-rbac.yaml
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
