# FIXES - Soluciones Aplicadas al Setup de GitLab + ArgoCD en Bonus

## Resumen
Este documento lista las correcciones y ajustes realizados para que GitLab + ArgoCD funcione sin problemas en una VM K3d de ARM64 (Mac M4 / aarch64).

## Problemas Identificados y Soluciones

### 1. **Memoria Insuficiente (Out of Memory)**
**Problema:** El pod `gitlab-kas` quedaba en `Pending` con error "Insufficient memory".
**Solución:** 
- Aumentar `memory` en `bonus/Vagrantfile` de 6GB a 8GB
- Línea 17-18: `v.memory = 8192` y `v.vmx["memsize"] = "8192"`

**Efecto:** Todos los pods de GitLab pueden ahoraprogramarse y ejecutarse.

---

### 2. **MinIO CrashLoopBackOff - exec format error (Incompatibilidad ARM64)**
**Problema:** El contenedor `minio` fallaba con `exec /usr/bin/docker-entrypoint.sh: exec format error`.
- La imagen `registry.gitlab.com/gitlab-org/cloud-native/mirror/images/minio/minio:RELEASE.2017-12-28T01-21-00Z` no es multi-arch.
- En un Mac M4 (ARM64/aarch64), esta imagen x86 no puede ejecutarse.

**Solución:**
- Cambiar a imagen `minio/minio:latest` (multi-arch, soporta ARM64)
- En `bonus/confs/gitlab-values.yaml`, añadir:
  ```yaml
  gitlab:
    minio:
      image:
        repository: minio/minio
        tag: latest
  ```
- Aplicar cambio con: `kubectl -n gitlab set image deployment/gitlab-minio minio=minio/minio:latest`

**Efecto:** MinIO arranca correctamente en ARM64.

---

### 3. **Buckets de MinIO No Creados (Job Fallido)**
**Problema:** El job `gitlab-minio-create-buckets` falló porque:
- Usaba imagen `minio/mc:RELEASE.2018-07-13T00-53-22Z` (x86, falla en ARM)
- Usaba comando `mc config host add` (sintaxis antigua, no existe en `minio/mc:latest`)

**Solución:**
- Crear buckets manualmente con imagen `minio/mc:latest` y credenciales por defecto:
  ```bash
  mc alias set myminio http://gitlab-minio-svc.gitlab.svc:9000 minioadmin minioadmin
  mc mb myminio/registry
  mc mb myminio/git-lfs
  mc mb myminio/runner-cache
  mc mb myminio/gitlab-uploads
  mc mb myminio/gitlab-artifacts
  mc mb myminio/gitlab-backups
  mc mb myminio/gitlab-packages
  mc mb myminio/tmp
  mc mb myminio/gitlab-mr-diffs
  mc mb myminio/gitlab-terraform-state
  mc mb myminio/gitlab-ci-secure-files
  mc mb myminio/gitlab-dependency-proxy
  mc mb myminio/gitlab-pages
  ```

**Efecto:** Todos los buckets requeridos por GitLab existen y MinIO funciona como backend.

---

### 4. **Ingress GitLab No Es Ruteado por Traefik**
**Problema:** Los `Ingress` de GitLab usaban clase `gitlab-nginx`, pero el cluster solo tiene `traefik` activo.
- Traefik devolvía `404 Not Found` para `gitlab.local`.

**Solución:**
- Parchear los `Ingress` de GitLab a clase `traefik`:
  ```bash
  kubectl -n gitlab patch ingress gitlab-webservice-default --type=merge -p '{"spec":{"ingressClassName":"traefik"}}'
  kubectl -n gitlab patch ingress gitlab-kas --type=merge -p '{"spec":{"ingressClassName":"traefik"}}'
  kubectl -n gitlab patch ingress gitlab-minio --type=merge -p '{"spec":{"ingressClassName":"traefik"}}'
  ```

**Efecto:** `gitlab.local` ahora es ruteado por Traefik y responde `302 Found` → `/users/sign_in` (comportamiento correcto).

---

## Archivos Modificados

1. **`bonus/Vagrantfile`** (líneas 17-22)
   - Aumentó memory de 6GB a 8GB para vmware_desktop y virtualbox

2. **`bonus/confs/gitlab-values.yaml`** (líneas 25-34)
   - Añadió configuración de `gitlab.minio.image` con repositorio `minio/minio` y tag `latest`

## Pasos Para Futuros `vagrant up`

1. **Traer la VM arriba normalmente:**
   ```bash
   cd bonus
   vagrant up --provider=vmware_desktop
   ```

2. **La VM ejecutará `scripts/install.sh` automáticamente** (provisioner shell en Vagrantfile).
   - Instala Docker, k3d, Helm, GitLab y ArgoCD
   - Crea el cluster k3d `iot-bonus` con puertos correctos

3. **Post-install automático:**
   - `vagrant up` ejecuta también `scripts/post-install.sh` mediante un segundo provisioner.
   - Si necesitas repetirlo manualmente por diagnóstico, puedes usar:
   ```bash
   vagrant ssh -c 'bash /vagrant/scripts/post-install.sh'
   ```

4. **Acceder a GitLab:**
   - Añadir a `/etc/hosts` (en el host):
     ```
   192.168.56.111 gitlab.local
     ```
   - Abrir navegador: `http://gitlab.local`

---

## Checklist de Validación Post-`vagrant up`

- [ ] `vagrant ssh` conecta correctamente
- [ ] `kubectl cluster-info` muestra API en https://0.0.0.0:6550
- [ ] `kubectl -n gitlab get pods` muestra todos los pods en `Running` o `Completed`
- [ ] `kubectl -n gitlab get pods | grep minio` muestra `gitlab-minio-*` en `Running` (no CrashLoopBackOff)
- [ ] `mc alias set test http://gitlab-minio-svc.gitlab.svc:9000 minioadmin minioadmin` funciona
- [ ] `curl -I -H "Host: gitlab.local" http://192.168.56.110/` devuelve `302 Found` (no 404)
- [ ] Navegador en host: `http://gitlab.local` muestra login de GitLab

---

## Notas Técnicas

### Por qué `minio/minio:latest` en lugar de versión específica
- La versión espejo de GitLab (`RELEASE.2017-12-28T01-21-00Z`) es muy antigua y no recibe builds ARM64.
- `latest` de `minio/minio` es más nueva (~2024) y tiene soporte oficial para ARM64.
- Los cambios de API de MinIO entre 2017 y 2024 no rompen compatibilidad con GitLab 18.11.

### Por qué manual creación de buckets
- El ConfigMap `gitlab-minio-config-cm` contiene script `/config/initialize` que usa sintaxis de `mc` antigua (`mc config host add`).
- Actualizar el ConfigMap manualmente requeriría parchear el init script al lenguaje moderno.
- Solución pragmática: crear buckets una sola vez con `minio/mc:latest` usando `alias set`.

### Helm Release en `pending-rollback`
- Estado residual de intentos de upgrade cancelados.
- No afecta al funcionamiento de GitLab (los pods están todos en est correcto).
- Si deseas limpiarlo: `helm rollback gitlab 1 -n gitlab --wait` revertirá formalmente a revisión 1.

---

## Contacto / Cambios Futuros
Si necesitas revertir a configuración de producción o ajustar recursos, edita `bonus/confs/gitlab-values.yaml` y ejecuta:
```bash
vagrant ssh
helm upgrade --install gitlab gitlab/gitlab -f /vagrant/confs/gitlab-values.yaml -n gitlab --wait
```
