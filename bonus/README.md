# Bonus: GitLab On-Premise y GitOps local

En la Parte 3, Argo CD vigilaba un repositorio público de GitHub. En este bonus sustituimos GitHub por un **GitLab** que corre dentro del mismo clúster: mismo patrón GitOps, pero sin depender de un servicio externo ni de conexión a internet para la fuente de la verdad.

Para ello instalaremos GitLab dentro del mismo clúster K3d que ya crea `p3/` (misma VM, mismo `iot-cluster`, mismo Argo CD). 
El subject del bonus lo pide así literalmente — *"add GitLab to the lab you completed in Part 3"*, *"everything you did in Part 3 must work with your local Gitlab"* — por lo tanto se trata de extender el laboratorio de la Parte 3.

```
GitLab local (estado deseado) -> Argo CD (reconciliación) -> Cluster (estado real)
```

> **Requisito previo importante**: `p3/` tiene que estar levantada con `vagrant up` antes de usar el contenido de esta parte `bonus`. 

---

## Conceptos Clave

1. **GitLab (self-hosted)**: plataforma de Git con interfaz web, equivalente a GitHub pero corriendo en infraestructura propia en vez de en la nube de un tercero. Aquí sustituye a GitHub como la fuente de la verdad que Argo CD vigila.

2. **Helm**: gestor de paquetes para Kubernetes. Un `chart` empaqueta todos los manifiestos que necesita una aplicación compleja (Deployments, Services, Secrets, ConfigMaps...) para instalarla con un solo comando y un fichero de valores (`values.yaml`). Lo usamos porque desplegar GitLab entero (webservice, Redis, PostgreSQL, MinIO, KAS...) a mano sería inviable. De hecho el propio subject lo recomienda explícitamente.

3. **MinIO**: almacenamiento de objetos compatible con S3 que GitLab usa internamente para adjuntos, artefactos de CI (continuous integration), backups, etc. Hay que inicializar sus buckets "manualmente" tras el despliegue porque el chart de Helm no lo hace por defecto.

4. **Por qué bonus comparte el clúster de p3 en vez de tener uno propio**: el DNS interno de GitLab (`gitlab-webservice-default.gitlab.svc`) solo resuelve dentro de su propio clúster, si Argo CD viviera en un clúster distinto, no podría resolverlo sin depender de soluciones demasiado frágiles. 

Como **p3 corre dentro de su propia VM de Vagrant** (ver `p3/README.md`), instalar GitLab en ese mismo clúster resuelve esto de raíz: todo comparte el mismo DNS interno, y no hace falta duplicar Argo CD ni el clúster.

   Lo único que sí exige atención: GitLab necesita bastante más RAM que p3 por sí solo (~8GB frente a los ~2GB por defecto de p3). Por eso `scripts/install.sh` redimensiona la VM de p3 (`vagrant reload`) la primera vez que hace falta (ver más abajo).

5. **Namespaces**: `gitlab` (lo crea este bonus), `argocd` y `dev` ya existen, previamente creados por p3.

6. **Bootstrap en cuatro scripts para entender el funcionamiento del despliegue**:

	- `install.sh` redimensiona la VM de p3 si hace falta, y despliega GitLab (Argo CD y el clúster ya los puso p3).
	- `create-gitlab-project-and-push.sh` crea el proyecto en GitLab vía su API y sube el manifiesto inicial.
	- `connect-argocd-to-gitlab.sh` re-apunta la `Application` `iot-app` (la misma que usa p3, no una nueva) de GitHub a este repo de GitLab local.
	- `revert-to-github.sh` la vuelve a apuntar a GitHub, para poder demostrar el cambio en los dos sentidos.

---

## Requisitos de la Práctica

- **GitLab local**: instancia de GitLab corriendo dentro del propio clúster, no en la nube.

- **Namespace `gitlab`**: dedicado a GitLab.

- **Todo lo de la Parte 3 debe seguir funcionando**: el mismo namespace `dev`, la misma `Application` `iot-app` gestionando la app, y las dos versiones (`v1`/`v2`) — solo cambia la fuente, GitHub por GitLab.

- **Demostración GitOps**: crear el repositorio en GitLab, subir el manifiesto, y comprobar que Argo CD sincroniza los cambios (incluido el paso de `v1` a `v2`) igual que en la Parte 3.

---

## Contenido de la carpeta

1. [confs/gitlab-values.yaml](confs/gitlab-values.yaml): valores de Helm para el despliegue reducido de GitLab (qué componentes activar/desactivar, recursos, etc.).

2. [confs/deployment.yaml](confs/deployment.yaml): manifiesto inicial de la app. Se usa **una sola vez**, para sembrar el repositorio en GitLab (`create-gitlab-project-and-push.sh` lo sube en el primer push).
A partir de ahí, la versión que Argo CD vigila de verdad vive dentro de GitLab, y los cambios se hacen en su UI, no en este fichero.

3. [confs/argocd-application.yaml](confs/argocd-application.yaml): mismo nombre/namespace/destino que `p3/confs/argocd.yaml` (`iot-app`/`argocd`/`dev`). Aplicarlo no crea una `Application` nueva, parchea en sitio la que ya existe, cambiando solo su `repoURL` de GitHub a GitLab.

4. [confs/gitlab-create-project.rb](confs/gitlab-create-project.rb) y [confs/gitlab-create-pat.rb](confs/gitlab-create-pat.rb): scripts de Ruby que `create-gitlab-project-and-push.sh` ejecuta dentro del pod `toolbox` de GitLab (vía `gitlab-rails runner`) para crear el proyecto inicial y su token de acceso, sin depender de credenciales previas.

5. [confs/namespaces.yaml](confs/namespaces.yaml): el namespace `gitlab` (`argocd`/`dev` ya existen gracias a p3).

6. [confs/minio-init-buckets.sh](confs/minio-init-buckets.sh): script que crea los buckets que necesita GitLab en MinIO. `install.sh` lo ejecuta dentro de un pod `mc` de usar y tirar, pasándole las credenciales como variables de entorno (para no interpolarlas en el propio script).

7. [scripts/install.sh](scripts/install.sh): redimensiona la VM de p3 (`vagrant reload`) si hace falta y despliega GitLab encima del clúster ya existente.

8. [scripts/create-gitlab-project-and-push.sh](scripts/create-gitlab-project-and-push.sh): crea el proyecto en GitLab vía su API y sube `confs/deployment.yaml`.

9. [scripts/connect-argocd-to-gitlab.sh](scripts/connect-argocd-to-gitlab.sh): re-apunta `iot-app` de GitHub a este repositorio de GitLab.

10. [scripts/revert-to-github.sh](scripts/revert-to-github.sh): vuelve a apuntar `iot-app` a GitHub (`p3/confs/argocd.yaml`), para demostrar el swap en ambos sentidos.

---

## Requisitos previos

1. `p3/` ya levantada con `vagrant up` (ver `p3/README.md`) — este bonus no crea ninguna VM ni clúster propios.

2. Vagrant instalado y funcionando.

3. Al menos 8GB de RAM libre en la máquina. GitLab es pesado, y `install.sh` redimensiona la VM de p3 a ese tamaño automáticamente.

---

## Arranque de infraestructura

Desde `bonus/`, con `p3/` ya levantada:

```bash
./scripts/install.sh
```

Este script detecta que no hay kubeconfig local y entra en la VM de p3 (`vagrant ssh`). 

Antes de instalar nada comprueba la RAM real de esa VM: si no llega a lo que necesita GitLab, la redimensiona (`P3_MEMORY=8192 P3_CPUS=3 vagrant reload`, esto reinicia la VM, tarda un poco). 

Si ya está al tamaño correcto (por ejemplo, en una segunda ejecución), se lo salta. Ya dentro, instala GitLab (namespace `gitlab`) vía Helm e inicializa sus buckets de MinIO. Argo CD y el clúster ya estaban arriba gracias a p3. Al terminar, GitLab está listo pero `iot-app` todavía apunta a GitHub.

---

### Paso 2: creamos el repositorio en GitLab y subimos el manifiesto

```bash
./scripts/create-gitlab-project-and-push.sh
```

*Este script espera a que el pod de GitLab esté listo, crea el proyecto `mlezcano-gitlab-demo` bajo el usuario `root`, genera un token de acceso de lectura/escritura y hace push de `confs/deployment.yaml` a la rama `main`.*

---

### Paso 3: re-apuntamos Argo CD al repositorio de GitLab

```bash
./scripts/connect-argocd-to-gitlab.sh
```

*Este script registra el repositorio de GitLab como fuente en Argo CD y re-apunta la `Application` `iot-app` — la misma que usa p3, no una nueva — de GitHub a este repo local. Fuerza además una sincronización inicial.*

---

Al terminar los tres pasos veremos:

- GitLab: `http://gitlab.localhost:8080` (usuario `root`, contraseña impresa por `install.sh`)

- Argo CD: `http://localhost:8080` (usuario `admin`, contraseña impresa por `connect-argocd-to-gitlab.sh`) — mismo puerto que GitLab, distinguidos por el header `Host` (`gitlab.localhost` vs `localhost`), igual que hace Traefik con `app1.com`/`app2.com`/`app3.com` en la Parte 2.

- App: `http://localhost:8888` — mismo puerto que en p3, ahora sincronizada desde GitLab.

Para volver a GitHub en cualquier momento (y demostrar el swap en los dos sentidos):

```bash
./scripts/revert-to-github.sh
```

---

## Checklist de verificación del Subject


1. **Accedemos a la VM**:

   ```bash
   cd ../p3 && vagrant ssh
   ```

---

2. **Verificamos los namespaces requeridos**:

   ```bash
   kubectl get ns
   ```

   *Debe incluir `gitlab` (requerido por el subject), además de `argocd` y `dev` (ya existentes, de p3).*

---

3. **Verificamos que los componentes están activos**:

   ```bash
   kubectl get pods -A
   ```

   - Los pods de GitLab (namespace `gitlab`) deben estar en `Running`.
   - Los pods de Argo CD (namespace `argocd`) deben estar en `Running` (los mismos de p3, no unos nuevos).
   - `kubectl -n argocd get application iot-app` debe mostrar `SYNC STATUS: Synced` y `HEALTH STATUS: Healthy`.

---

4. **Confirmamos que `iot-app` apunta de verdad a GitLab, no a GitHub**:

   ```bash
   kubectl -n argocd get application iot-app -o jsonpath='{.spec.source.repoURL}'; echo
   ```

   Debe mostrar la URL interna de GitLab (`http://gitlab-webservice-default.gitlab.svc:8181/...`), no la de GitHub.

---

5. **Comprobamos que la app responde en `v1`**:

   En la terminal de la máquina host (no dentro de la VM):

   ```bash
   curl http://localhost:8888/
   # {"status":"ok","message":"v1"}
   ```

   O en el navegador: `http://localhost:8888/`

---

6. **Verificamos que GitLab funciona de verdad**:

   Entramos en `http://gitlab.localhost:8080/root/mlezcano-gitlab-demo` con el usuario `root` y la contraseña impresa por `install.sh`.

   *En caso de haberla "perdido" en la terminal, podemos recuperarla dentro de la VM con el mismo comando ya usado en p3:*

   ```bash
   kubectl -n gitlab get secret gitlab-gitlab-initial-root-password -o jsonpath='{.data.password}' | base64 -d && printf "\n"
   ```

---

7. **Cambiamos de `v1` a `v2`** editando `deployment.yaml` directamente en la UI de GitLab (cambiando la imagen de `mikelezc/playground:v1` a `mikelezc/playground:v2`) y haciendo commit en `main`.

---

8. **Esperamos la sincronización automática** (Argo CD reconcilia en unos 10 segundos). Si tarda, forzamos:

   ```bash
   kubectl -n argocd annotate application iot-app argocd.argoproj.io/refresh=hard --overwrite
   ```

---

9. **Verificamos la app en `v2`**:

   ```bash
   curl http://localhost:8888/
   # {"status":"ok","message":"v2"}
   ```

    O por supuesto, dentro de nuestro navegador 

   `http://localhost:8888/`

---

10. **Limpieza**: desde `p3/` (la VM es suya; destruirla se lleva por delante GitLab también),

    ```bash
    vagrant destroy -f
    ```
