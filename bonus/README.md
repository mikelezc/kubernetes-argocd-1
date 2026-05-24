# Bonus: GitLab On-Premise y GitOps local

## Conceptos Clave

En el bonus extendemos el flujo de la Parte 3 sustituyendo GitHub por un GitLab
instalado dentro del propio entorno. Argo CD sigue siendo el orquestador GitOps,
pero ahora su fuente de la verdad es un repositorio local en lugar de uno externo.

1. GitLab se despliega en la VM como repositorio Git interno (namespace `gitlab`).
2. Argo CD se instala en el mismo clúster (namespace `argocd`), sin Application inicial.
3. Un segundo script crea el proyecto en GitLab y hace push del manifiesto.
4. Un tercer script registra ese repositorio en Argo CD y crea la Application.
5. Desde ese momento, cualquier commit en GitLab dispara una sincronización automática.

Helm se usa para instalar GitLab porque el despliegue de todos sus componentes
(webservice, Redis, PostgreSQL, MinIO, kas…) sería demasiado complejo manualmente.
El subject lo recomienda explícitamente.

### Por qué el bonus tiene su propio clúster y su propio Argo CD

Podría parecer que lo correcto sería reutilizar el clúster de la Parte 3 y simplemente
cambiar el `repoURL` de Argo CD para que apunte a GitLab. Pero eso no es viable por
dos razones:

- **Aislamiento de entornos**: GitLab corre dentro de la VM Vagrant y su URL interna
  (`gitlab-webservice-default.gitlab.svc`) solo existe dentro del clúster de esa VM.
  El Argo CD de p3, que corre en un clúster distinto en el host, no puede resolver esa
  dirección. Hacerlo funcionar requeriría bindear el port-forwarding de Vagrant en
  `0.0.0.0` y depender de `host.k3d.internal`, una solución frágil y dependiente del
  entorno del evaluador.
- **Recursos**: GitLab necesita 8 GB de RAM. El subject especifica que el bonus debe
  contener `"everything needed so your entire cluster works"`, lo que implica un entorno
  autosuficiente, no una extensión frágil del de p3.

El workflow es idéntico al de la Parte 3 (Argo CD sincroniza manifests desde Git hacia
el namespace `dev`), solo cambia la fuente: GitHub → GitLab local.

## Atención: requerimientos de sistema

GitLab es pesado. La VM reserva 8 GB de RAM y 3 CPU para evitar errores por falta
de memoria. El arranque tardará varios minutos la primera vez.

## Carpetas del módulo Bonus

| Ruta | Descripción |
|------|-------------|
| [Vagrantfile](Vagrantfile) | Define la VM, arquitectura detectada y provisión automática |
| [confs/gitlab-values.yaml](confs/gitlab-values.yaml) | Valores Helm para el despliegue reducido de GitLab |
| [confs/deployment.yaml](confs/deployment.yaml) | Manifiesto inicial que se pushea a GitLab y que Argo CD sincroniza |
| [scripts/install.sh](scripts/install.sh) | Instala herramientas, crea el clúster y despliega GitLab + Argo CD |
| [scripts/create-gitlab-project-and-push.sh](scripts/create-gitlab-project-and-push.sh) | Crea el proyecto en GitLab y hace push del manifiesto |
| [scripts/connect-argocd-to-gitlab.sh](scripts/connect-argocd-to-gitlab.sh) | Registra el repo GitLab en Argo CD y crea la Application |

## Requisitos Previos

1. Vagrant instalado y funcionando.
2. VMware Desktop o VirtualBox disponible (el Vagrantfile detecta la arquitectura).
3. Al menos 8 GB de RAM libre para la VM.

## Flujo completo paso a paso

### Paso 1 — Levantar la infraestructura

```bash
vagrant up
```

Qué hace internamente [scripts/install.sh](scripts/install.sh):

- Instala Docker, kubectl, k3d y Helm dentro de la VM.
- Crea el clúster `iot-bonus` con k3d.
- Despliega GitLab en el namespace `gitlab` con Helm.
- Parchea los Ingress de GitLab para usar traefik.
- Inicializa los buckets de MinIO que necesita GitLab.
- Despliega Argo CD en el namespace `argocd`.
- Configura reconciliación rápida (5s) en Argo CD.
- Habilita el modo HTTP (insecure) y crea el Ingress de Argo CD.
- Imprime la contraseña inicial de GitLab y los próximos pasos.

Al terminar, GitLab está listo pero Argo CD todavía no tiene ninguna Application.

### Paso 2 — Crear el repositorio en GitLab y subir el manifiesto

Desde el host, dentro de la carpeta `bonus/`:

```bash
./scripts/create-gitlab-project-and-push.sh
```

O desde dentro de la VM:

```bash
vagrant ssh -c 'bash /vagrant/scripts/create-gitlab-project-and-push.sh'
```

Qué hace:

1. Espera a que el pod webservice de GitLab esté listo.
2. Crea el proyecto `mlezcano-gitlab-demo` bajo el usuario `root`.
3. Genera un Personal Access Token con permisos de lectura/escritura sobre el repo.
4. Copia [confs/deployment.yaml](confs/deployment.yaml) y hace push a la rama `main`.
5. Guarda el token en `/tmp/.gitlab-pat` para el siguiente script.
6. Imprime la URL del repositorio y el comando siguiente.

### Paso 3 — Conectar Argo CD al repositorio GitLab

```bash
./scripts/connect-argocd-to-gitlab.sh
```

Qué hace:

1. Lee el token generado en el paso anterior.
2. Registra el repositorio GitLab local como fuente en Argo CD (crea el secret con credenciales).
3. Crea la Application `iot-app` apuntando al repo interno del clúster.
4. Fuerza una sincronización inicial.
5. Imprime las URLs de acceso y las credenciales de Argo CD.

## URLs de acceso

| Servicio | URL desde el host |
|----------|-------------------|
| GitLab | `http://gitlab.localhost:8081` |
| Argo CD | `http://localhost:8081` |
| Aplicación | `http://localhost:8889` |

Credenciales GitLab: `root` / contraseña impresa por `vagrant up`.

Credenciales Argo CD: `admin` / contraseña impresa por `connect-argocd-to-gitlab.sh`.

## Demostración del flujo GitOps

Una vez completados los tres pasos, el flujo GitOps está activo. Para demostrar
el ciclo completo (equivalente a lo que se hace en la Parte 3 con GitHub):

1. Abre GitLab en `http://gitlab.localhost:8081/root/mlezcano-gitlab-demo`.
2. Edita `deployment.yaml` directamente en la UI de GitLab.
3. Cambia la imagen de `mikelezc/playground:v1` a `mikelezc/playground:v2`.
4. Haz commit en `main`.
5. Argo CD detecta el cambio en menos de 10 segundos y sincroniza.
6. Verifica el resultado:

```bash
curl http://localhost:8889/
# {"status":"ok","message":"v2"}
```

Para volver a `v1`, repite el proceso cambiando la imagen de vuelta.

## Comprobaciones Rápidas

```bash
# Estado general del clúster
kubectl get pods -A

# Pods de GitLab
kubectl -n gitlab get pods

# Pods de Argo CD
kubectl -n argocd get pods

# Estado de la Application
kubectl -n argocd get application iot-app

# App desplegada
kubectl -n dev get pods
curl http://localhost:8889/
```

Estado esperado cuando todo está correcto:

- Pods de GitLab en `Running` en el namespace `gitlab`.
- Pods de Argo CD en `Running` en el namespace `argocd`.
- Application `iot-app` con `SYNC STATUS: Synced` y `HEALTH STATUS: Healthy`.
- `curl http://localhost:8889/` devuelve `{"status":"ok","message":"v1"}`.

## Forzar sincronización manual

Si necesitas que Argo CD sincronice inmediatamente sin esperar el intervalo de 5s:

```bash
kubectl -n argocd annotate application iot-app argocd.argoproj.io/refresh=hard --overwrite
```

## Limpieza

```bash
vagrant destroy -f
```

## Puntos clave para la corrección

### GitLab funciona y acepta repositorios

```bash
vagrant ssh -c 'bash /vagrant/scripts/create-gitlab-project-and-push.sh'
```

Demuestra que GitLab está operativo, que se pueden crear repositorios y que el
push funciona correctamente.

### Argo CD sincroniza desde GitLab local

```bash
kubectl -n argocd get application iot-app -o jsonpath='{.spec.source.repoURL}{"\n"}'
```

Resultado esperado:

```
http://gitlab-webservice-default.gitlab.svc:8181/root/mlezcano-gitlab-demo.git
```

### El flujo GitOps funciona de extremo a extremo

- Cambiar `deployment.yaml` en GitLab → commit → Argo CD sincroniza → la app se actualiza.
- Verificar con `curl http://localhost:8889/` que la versión cambia de `v1` a `v2`.
