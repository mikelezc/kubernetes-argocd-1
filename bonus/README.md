# Bonus: GitLab On-Premise y GitOps local

En la Parte 3, Argo CD vigilaba un repositorio público de GitHub. En este bonus sustituimos GitHub por un **GitLab** que corre dentro de nuestro propio clúster: mismo patrón GitOps, pero sin depender de un servicio externo ni de conexión a internet para la fuente de la verdad.

A diferencia de la Parte 3, aquí levantamos un clúster K3d completamente nuevo (`iot-bonus`) dentro de una VM de Vagrant dedicada, con su propio Argo CD — no reutilizamos el de la Parte 3 (ver por qué, más abajo).

```
GitLab local (estado deseado) -> Argo CD (reconciliación) -> Cluster (estado real)
```

---

## Conceptos Clave

1. **GitLab (self-hosted)**: plataforma de Git con interfaz web, equivalente a GitHub pero corriendo en infraestructura propia en vez de en la nube de un tercero. Aquí sustituye a GitHub como la fuente de la verdad que Argo CD vigila.

2. **Helm**: gestor de paquetes para Kubernetes. Un `chart` empaqueta todos los manifiestos que necesita una aplicación compleja (Deployments, Services, Secrets, ConfigMaps...) para instalarla con un solo comando y un fichero de valores (`values.yaml`). Lo usamos porque desplegar GitLab entero (webservice, Redis, PostgreSQL, MinIO, KAS...) a mano sería inviable — el propio subject lo recomienda explícitamente.

3. **MinIO**: almacenamiento de objetos compatible con S3 que GitLab usa internamente para adjuntos, artefactos de CI, backups, etc. Hay que inicializar sus buckets a mano tras el despliegue porque el chart de Helm no lo hace por defecto.

4. **Por qué el bonus tiene su propio clúster y su propio Argo CD**: podría parecer que lo correcto sería reutilizar el clúster de la Parte 3 y cambiar el `repoURL` de Argo CD para que apunte a GitLab, pero no es viable por dos razones — **aislamiento**: la URL interna de GitLab (`gitlab-webservice-default.gitlab.svc`) solo existe dentro del clúster de esta VM, y el Argo CD de p3 (en un clúster distinto) no puede resolverla sin depender de soluciones frágiles; **recursos**: GitLab necesita 8GB de RAM, y el subject pide que el bonus sea un entorno autosuficiente, no una extensión frágil de p3.

5. **Namespaces**: `gitlab` (GitLab en sí), `argocd` (el controlador GitOps) y `dev` (la app desplegada) — misma separación lógica que en la Parte 3, ahora dentro de un único clúster autosuficiente.

6. **El bootstrap en tres scripts encadenados**: `install.sh` crea el clúster y despliega GitLab + Argo CD (sin ninguna `Application` todavía); `create-gitlab-project-and-push.sh` crea el proyecto en GitLab vía su API y sube el manifiesto inicial; `connect-argocd-to-gitlab.sh` registra ese repo en Argo CD y crea la `Application`. Es la versión "hazlo tú mismo" de lo que en la Parte 3 hacíamos a mano en la web de GitHub.

---

## Requisitos de la Práctica

- **GitLab local**: instancia de GitLab corriendo dentro del propio clúster, no en la nube.
- **Namespace `gitlab`**: dedicado a GitLab.
- **Todo lo de la Parte 3 debe seguir funcionando**: los mismos namespaces `argocd`/`dev`, Argo CD gestionando la app, y las dos versiones (`v1`/`v2`) — solo cambia la fuente, GitHub por GitLab.
- **Demostración**: crear el repositorio en GitLab, subir el manifiesto, y comprobar que Argo CD sincroniza los cambios (incluido el paso de `v1` a `v2`) igual que en la Parte 3.

---

## Contenido de la carpeta

1. [Vagrantfile](Vagrantfile): define la VM (8GB RAM / 3 CPU, detecta arquitectura ARM/AMD) y lanza `scripts/install.sh` como aprovisionador.

2. [confs/gitlab-values.yaml](confs/gitlab-values.yaml): valores de Helm para el despliegue reducido de GitLab (qué componentes activar/desactivar, recursos, etc.).

3. [confs/deployment.yaml](confs/deployment.yaml): manifiesto inicial de la app. Se usa **una sola vez**, para sembrar el repositorio en GitLab (`create-gitlab-project-and-push.sh` lo sube en el primer push); a partir de ahí, la versión que Argo CD vigila de verdad vive dentro de GitLab, y los cambios se hacen en su UI, no en este fichero.

4. [scripts/install.sh](scripts/install.sh): bootstrap principal. Instala Docker/kubectl/k3d/Helm en la VM, crea el clúster, despliega GitLab y Argo CD.

5. [scripts/create-gitlab-project-and-push.sh](scripts/create-gitlab-project-and-push.sh): crea el proyecto en GitLab vía su API y sube `confs/deployment.yaml`.

6. [scripts/connect-argocd-to-gitlab.sh](scripts/connect-argocd-to-gitlab.sh): registra el repositorio de GitLab en Argo CD y crea la `Application`.

---

## Requisitos previos

1. Vagrant instalado y funcionando.
2. VMware Desktop o VirtualBox disponible (el Vagrantfile detecta la arquitectura).
3. Al menos 8GB de RAM libre para la VM — GitLab es pesado y el primer arranque puede tardar varios minutos.

---

## Arranque de infraestructura

Desde `bonus/`:

```bash
vagrant up
```

Internamente, `scripts/install.sh` instala Docker/kubectl/k3d/Helm, crea el clúster `iot-bonus`, despliega GitLab (namespace `gitlab`) vía Helm, parchea sus Ingress a `traefik`, inicializa los buckets de MinIO, despliega Argo CD (namespace `argocd`) y ajusta su reconciliación a 5 segundos. Al terminar, GitLab está listo pero Argo CD todavía no tiene ninguna `Application`.

---

### Paso 2: creamos el repositorio en GitLab y subimos el manifiesto

```bash
./scripts/create-gitlab-project-and-push.sh
```

Espera a que el pod de GitLab esté listo, crea el proyecto `mlezcano-gitlab-demo` bajo el usuario `root`, genera un token de acceso de lectura/escritura y hace push de `confs/deployment.yaml` a la rama `main`.

---

### Paso 3: conectamos Argo CD al repositorio de GitLab

```bash
./scripts/connect-argocd-to-gitlab.sh
```

Registra el repositorio de GitLab como fuente en Argo CD, crea la `Application` `iot-app` apuntando a él, y fuerza una sincronización inicial.

---

Al terminar los tres pasos veremos:

- GitLab: `http://gitlab.localhost:8081` (usuario `root`, contraseña impresa por `vagrant up`)
- Argo CD: `http://localhost:8081` (usuario `admin`, contraseña impresa por `connect-argocd-to-gitlab.sh`)
- App: `http://localhost:8889`

---

## Checklist de verificación del Subject

1. **Verificamos los namespaces requeridos**:

   ```bash
   kubectl get ns
   ```

   Debe incluir `gitlab` (requerido por el subject), además de `argocd` y `dev`.

---

2. **Verificamos que los componentes están activos**:

   ```bash
   kubectl get pods -A
   ```

   - Los pods de GitLab (namespace `gitlab`) deben estar en `Running`.
   - Los pods de Argo CD (namespace `argocd`) deben estar en `Running`.
   - `kubectl -n argocd get application iot-app` debe mostrar `SYNC STATUS: Synced` y `HEALTH STATUS: Healthy`.

---

3. **Comprobamos que la app responde en `v1`**:

   ```bash
   curl http://localhost:8889/
   # {"status":"ok","message":"v1"}
   ```

---

4. **Verificamos que GitLab funciona de verdad**: entramos en `http://gitlab.localhost:8081` con el usuario `root` y la contraseña impresa por `vagrant up`, y navegamos hasta el proyecto `mlezcano-gitlab-demo` — ahí está el `deployment.yaml` que subió `create-gitlab-project-and-push.sh`.

---

5. **Cambiamos de `v1` a `v2`** editando `deployment.yaml` directamente en la UI de GitLab (cambiando la imagen de `mikelezc/playground:v1` a `mikelezc/playground:v2`) y haciendo commit en `main`.

---

6. **Esperamos la sincronización automática** (Argo CD reconcilia en unos 10 segundos). Si tarda, forzamos:

   ```bash
   kubectl -n argocd annotate application iot-app argocd.argoproj.io/refresh=hard --overwrite
   ```

---

7. **Verificamos la app en `v2`**:

   ```bash
   curl http://localhost:8889/
   # {"status":"ok","message":"v2"}
   ```

---

8. **Limpieza**: desde `bonus/`,

   ```bash
   vagrant destroy -f
   ```
