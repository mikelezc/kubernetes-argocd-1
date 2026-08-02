# Parte 3: K3d y Argo CD

En la Parte 2 provisionamos con Vagrant una única VM y desplegábamos las aplicaciones contra un `Ingress` fijo. En esta Parte 3 el enunciado pide justo lo contrario: nada de Vagrant, y las aplicaciones se mantienen sincronizadas de forma automática, gestionadas a través un controlador **GitOps** (Argo CD) que vigila un repositorio Git.

Para esto se nos pide también cambiar la herramienta de clúster: en vez de instalar K3s como servicio dentro de una VM, usamos **K3d**, que ejecuta K3s dentro de contenedores Docker. 

El flujo completo quedaría de la siguiente manera:

1. Levantamos un clúster K3d (K3s corriendo en contenedores, sin VM).
2. Instalamos Argo CD dentro del clúster.
3. Argo CD observa un repositorio de GitHub público con los manifiestos.
4. Cuando cambia el manifiesto en GitHub, Argo CD reconcilia y aplica el estado deseado en el clúster.
5. La app se publica con una imagen en Docker Hub y se sirve en `localhost:8888`.

```
GitHub (estado deseado) -> Argo CD (reconciliación) -> Cluster (estado real)
```

---

## Conceptos Clave

1. **K3s vs K3d**: K3s es la distribución ligera de Kubernetes en sí; en las Partes 1 y 2 la instalamos directamente dentro de una VM. K3d es un *wrapper* que ejecuta ese mismo K3s dentro de contenedores Docker: cada "nodo" del clúster es, en realidad, un contenedor. El único prerrequisito real es tener Docker funcionando, por lo que un clúster completo arranca y se destruye sin provisionar ni mantener una VM dedicada.

2. **Namespace**: partición lógica del clúster para organizar y aislar recursos. En esta parte usamos dos: `argocd` (donde vive el propio controlador) y `dev` (donde Argo CD despliega nuestra aplicación).

3. **GitOps**: paradigma en el que un repositorio Git es la única fuente de verdad del estado deseado de la infraestructura. Nadie ejecuta `kubectl apply` a mano: se edita el manifiesto, se hace commit y push, y un controlador dentro del clúster (aquí, Argo CD) se encarga de que el estado real converja con lo declarado en el repo.

4. **Manifiesto (manifest)**: fichero YAML declarativo que describe un recurso de Kubernetes (`Deployment`, `Application`...). En GitOps, el manifiesto en Git es la "orden de trabajo"; el clúster solo refleja lo que ese fichero dice.

5. **Argo CD y su objeto `Application`**: es el controlador GitOps del proyecto. Corre dentro del propio clúster y usa un CRD llamado `Application` (nuestro `confs/argocd.yaml`) para saber qué repo vigilar, en qué `namespace` desplegar y con qué política de sincronización. En la UI, `Sync` indica si el clúster coincide con el repo y `Health` si los recursos desplegados están realmente sanos.

	*Un CRD (Custom Resource Definition, o Definición de Recurso Personalizado) es una característica de Kubernetes que nos permite extender la API nativa de Kubernetes creando nuestros propios tipos de objetos personalizados.*

6. **Tagging de imágenes**: versionar una imagen Docker asignándole una etiqueta (`v1`, `v2`). Aquí es lo que distingue una versión de la app de la otra; cambiar de versión es tan simple como cambiar el tag en el manifiesto.

7. **Bootstrap**: script (`scripts/install.sh`) que automatiza de principio a fin la creación del entorno: instala dependencias, crea el clúster K3d, instala Argo CD y aplica la `Application`. Es idempotente: se puede volver a ejecutar sin dejar el clúster en un estado inconsistente.

8. **Docker outside of Docker (DooD)**: patrón que usa nuestro `toolbox/` para dar `kubectl`/`k3d` en máquinas sin privilegios. En vez de correr un daemon Docker anidado dentro del contenedor (*Docker in Docker*), montamos el socket del Docker del host (`/var/run/docker.sock`). Así, los contenedores que crea K3d los lanza el Docker real del host, no uno anidado, y los puertos publicados quedan accesibles en el `localhost` de la máquina exactamente igual que sin el toolbox.

---

## Requisitos de la Práctica

- **Clúster**: `K3d` con namespaces `argocd` y `dev`.

- **Argo CD**: instalado en el clúster y accesible desde el navegador (GUI).

- **Namespace `dev`**: contiene la aplicación, desplegada por Argo CD (que vive en el namespace `argocd`).

- **Repositorio GitHub**: el manifiesto de la aplicación vive en un repo público con el login de un miembro del equipo en el nombre. Argo CD lo toma de ahí y lo mantiene sincronizado.
  - `https://github.com/mikelezc/mlezcano-iot-argocd`

- **Imagen Docker Hub**: la app tiene dos versiones. Se puede usar la imagen de Wil o una propia; en nuestro caso la hemos creado y publicado en un repositorio propio ya que al desarrollar parte del proyecto en equipos ARM (Mac Mx), nos era imposible usar las imágenes de ejemplo proporcionadas.
  - `https://hub.docker.com/r/mikelezc/playground`

- **Tags**: `v1` y `v2` publicados en Docker Hub, con diferencias visuales entre versiones para reconocer el cambio a simple vista.

- **Demostración**: cambio de versión `v1` -> `v2` mediante commit/push en GitHub, sin tocar el clúster a mano.

---

## Contenido de la carpeta

1. [scripts/install.sh](scripts/install.sh): bootstrap principal. Instala dependencias, crea el clúster, instala Argo CD y aplica la `Application`.

2. [confs/argocd.yaml](confs/argocd.yaml): manifiesto de la `Application` de Argo CD (repo, rama, path y política de sincronización).

3. [repo-github/deployment.yaml](repo-github/deployment.yaml): **copia de referencia, no está en uso**. Ningún script de esta carpeta lo lee ni lo aplica; se guarda aquí solo como muestra para poder revisarlo sin salir del repositorio. El manifiesto real, el que Argo CD monitoriza y aplica en el clúster, vive en el repo de GitHub:
   - `https://github.com/mikelezc/mlezcano-iot-argocd`

4. [repo-dockerhub/app.py](repo-dockerhub/app.py) y [repo-dockerhub/Dockerfile](repo-dockerhub/Dockerfile): **copia de referencia, no está en uso**. Es el código fuente y la receta con la que se construyó, una única vez y de forma manual, la imagen que sí corre en el clúster. Lo que descarga y ejecuta el `Deployment` es la imagen ya construida en Docker Hub, no este código:
   - `https://hub.docker.com/r/mikelezc/playground`

5. [toolbox/](toolbox/): imagen Docker con `kubectl`/`k3d` ya instalados, para máquinas sin privilegios de host (ver más abajo cuando lleguemos a la sección de arranque del proyecto).

---

## Requisitos previos

1. Docker Desktop (o daemon Docker) activo.

2. Acceso a GitHub y a un repositorio público con el login de un miembro del equipo en el nombre.
   - `https://github.com/mikelezc/mlezcano-iot-argocd`
   
3. Imagen pública en Docker Hub con el login de un miembro del equipo, por ejemplo `mikelezc/playground`.
   - `https://hub.docker.com/r/mikelezc/playground`

   Hemos construido la aplicación, la hemos metido en un contenedor y la hemos subido a Docker Hub manualmente, ya que el proyecto se ha desarrollado en un Mac con M4 Pro y necesitábamos una imagen multi-arquitectura que se pudiera desplegar tanto en máquinas AMD como ARM.

4. Tags publicados en Docker Hub: `v1` y `v2`.

Verificación rápida de Docker Hub:

```bash
docker pull mikelezc/playground:v1
docker pull mikelezc/playground:v2
```

---

## Arranque de infraestructura

Desde `p3/`:

```bash
./scripts/install.sh
```

### Alternativa sin privilegios de host (cluster de 42)

`scripts/install.sh` instala `kubectl` y `k3d` directamente en el host, lo que
requiere `sudo`. En máquinas donde `docker` funciona sin sudo pero no hay
privilegios para instalar paquetes de sistema (como en el cluster de 42), se
puede usar el toolbox en `toolbox/`: una imagen Docker con `kubectl` y `k3d`
ya instalados, que se ejecuta montando el socket de Docker del host
(`-v /var/run/docker.sock:/var/run/docker.sock`) y con `--network host`. Así,
el clúster k3d se crea igualmente como contenedores del Docker del host (no
anidados), y los puertos publicados (8080, 8888) quedan accesibles en el
`localhost` real de la máquina, exactamente igual que con la instalación
directa.

`scripts/install.sh` no cambia: sus comprobaciones `command -v kubectl/k3d`
encuentran los binarios ya presentes en la imagen del toolbox y omiten la
instalación.

```bash
./toolbox/run.sh ./scripts/install.sh
```

También sirve para lanzar comandos sueltos con las herramientas ya listas:

```bash
./toolbox/run.sh kubectl get pods -n dev
./toolbox/run.sh   # shell interactiva con kubectl/k3d/docker(cliente)/git/jq
```

Al terminar el script veremos lo siguiente:

- Argo CD: `http://localhost:8080`
- App: `http://localhost:8888`
- Usuario Argo CD: `admin`
- Password: la imprime el script al final

Para obtener password de argocd manualmente en caso de necesitarlo:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

## Checklist para la Configuración

1. Arranque de infraestructura con ayuda del grupo.

```bash
./scripts/install.sh
```

2. Revisar ficheros de configuracion en `p3/` y explicar su contenido.

3. Verificar namespaces requeridos:

```bash
kubectl get ns
```

Debe incluir `argocd` y `dev` (requeridos por el subject).

Namespaces adicionales normales del sistema:

- `default`: namespace por defecto.
- `kube-system`: componentes internos (CoreDNS, etc).
- `kube-public`: datos publicos del cluster.
- `kube-node-lease`: leases de salud de nodos.

4. Verificamos el único pod requerido por el subject en `dev`:

```bash
kubectl get pods -n dev
```

### Diferencias entre namespace y pod:

- Namespace: particion logica del cluster para organizar y aislar recursos.
- Pod: unidad minima de ejecucion (uno o mas contenedores) que corre en un nodo.

5. Verificar servicios/componentes en running:

```bash
# Comprobamos la Application `iot-app` y su estado (sync / health)
kubectl get applications -n argocd

# Listamos los pods de Argo CD (repo-server, server, application-controller, ...)
# Estos los veremos de forma mucho más gráfica en la UI de Argocd más adelante.
kubectl get pods -n argocd

# Listamos los servicios en el namespace `dev` para ver el puerto que expone la app
kubectl get svc -n dev
```

## Explicación rápida

- `kubectl get applications -n argocd` : muestra la Application (por ejemplo `iot-app`) con columnas como `NAME`, `SYNC` y `HEALTH`.
	- Qué esperar: `Synced` y `Healthy` cuando Argo CD aplicó correctamente los manifiestos.
	- Si viéramos `OutOfSync` o `ComparisonError`: comprueba que `confs/argocd.yaml` tenga el `repoURL` y `targetRevision` correctos y que el repositorio sea público/accessible.

- `kubectl get pods -n argocd` : lista los pods que componen Argo CD (argocd-server, argocd-repo-server, argocd-application-controller, etc.).
	- Qué esperar: STATUS `Running` y READY `1/1` (o `2/2` según el pod).
	- Si hay errores (CrashLoopBackOff, Pending): usa `kubectl -n argocd describe pod <pod>` y `kubectl -n argocd logs <pod>` para ver eventos y logs.

- `kubectl get svc -n dev` : muestra los servicios en `dev` (buscar el Service que expone la app, normalmente NodePort o ClusterIP).
	- Qué esperar: un Service que mapea al puerto de la app; con k3d normalmente puedes acceder en `http://localhost:8888`.
	- Si no es accesible: usa `kubectl -n dev port-forward svc/<service-name> 8888:<target-port>` o revisa que el pod asociado esté `Running`.


6. Verificamos Argo CD accesible por web y login/password.

``http://localhost:8080``

7. Verificamos nombre del repo GitHub con login de 42.

	``https://github.com/mikelezc/mlezcano-iot-argocd/``

8. Verificamos Docker Hub con login de 42 y tags `v1` y `v2`.

	``https://hub.docker.com/repository/docker/mikelezc/playground/general``


## Checklist de uso del cluster

1. Navegamos Argo CD y revisamos la interface (source, target, sync, health, history).

**Qué significa cada campo en la UI de Argo CD**

- **Source**: el repositorio Git (URL), la rama y la ruta dentro del repo que Argo CD usa como "fuente de la verdad". Aquí están los manifiestos que describen el estado deseado del clúster.
- **Target**: el destino donde se aplican los manifiestos (cluster y `namespace`). Permite desplegar el mismo código en varios entornos cambiando sólo el target.
- **Sync**: indica si el estado aplicado en el clúster coincide con el `Source`. Valores habituales: `Synced` (ya aplicado) o `OutOfSync` (hay diferencias).
- **Health**: resume la salud de los recursos de la aplicación (`Healthy`, `Progressing`, `Degraded`, `Unknown`). Argo CD agrega checks sobre Deployments, Pods, Services, etc.
- **History**: historial de sincronizaciones y cambios aplicados desde el repo; permite ver cuándo se aplicó cada commit y hacer rollback a una versión anterior si es necesario.

## Guia de comprobaciones:

- Si la Application aparece `OutOfSync`, revisamos la rama/path en `confs/argocd.yaml` y pulsamos `Sync` en la UI o fuerza una comprobación con:

```bash
kubectl -n argocd annotate application iot-app argocd.argoproj.io/refresh=hard --overwrite
```

- Para investigar fallos en `Health` o pods con errores, eventos y logs:

```bash
kubectl -n dev get pods
kubectl -n dev describe pod <pod-name>
kubectl -n dev logs <pod-name>
```


2. Comprobar que `v1` es accesible desde esta maquina:

```bash
curl http://localhost:8888/
```


3. Confirmamos que la app usa Docker Hub y repo de Github

Desde el repositorio local (prueba rápida):

```bash
# 1) Verificamos el campo `image` en el manifiesto que Argo CD monitoriza
grep -n "image:" repo-github/deployment.yaml || sed -n '1,160p' repo-github/deployment.yaml
```

En la configuración de Argo CD (confirmamos el repo que se está monitorizando):

```bash
grep -n "repoURL" confs/argocd.yaml || sed -n '1,120p' confs/argocd.yaml
```

Comprobación desde Docker/Docker Hub:

```bash
# 2) Descargamos las imágenes públicas
docker pull mikelezc/playground:v1
docker pull mikelezc/playground:v2

# 3) Comprobar tags desde la API pública de Docker Hub (salida JSON)
curl -s https://hub.docker.com/v2/repositories/mikelezc/playground/tags/ | jq '.results[].name'
```

Comprobación en el clúster (evidencia de que Kubernetes usa la imagen de Docker Hub):

```bash
# 4) Imagen usada por el Deployment en el namespace `dev`
kubectl -n dev get deployment mlezcano-playground -o jsonpath='{.spec.template.spec.containers[*].image}'; echo

# 5) Imagen(es) usadas por los pods
kubectl -n dev get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].image}{"\n"}{end}'
```

4. Cambiamos a `v2` editando manifiesto en GitHub y hacer commit/push.

5. Esperamos sincronizacion automatica (tarda unos minutos en reflejarse). 
	Podemos forzarla manualmente si tarda en actualizar.

	```bash
	kubectl -n argocd annotate application iot-app argocd.argoproj.io/refresh=hard --overwrite
	```

6. Verificar app en `v2`.

## Cambio de v1 a v2 (flujo recomendado)

El cambio se hace en el repo de GitHub monitorizado por Argo CD.

En `deployment.yaml`, cambiar:

```yaml
- name: VERSION
  value: "v1"
```

por:

```yaml
- name: VERSION
  value: "v2"
```

Luego commit y push.

Comprobacion:

```bash
curl http://localhost:8888/
```

## Sincronizacion automatica y fallback manual

Argo CD tiene reconciliacion frecuente (configurada a pocos segundos), pero puede haber retraso breve segun ciclo/controlador.

Si no sincroniza al momento, forzaremos refresh:

```bash
kubectl -n argocd annotate application iot-app argocd.argoproj.io/refresh=hard --overwrite
```

Si ademas queremos recrear el pod de app inmediatamente:

```bash
kubectl -n dev rollout restart deployment/mlezcano-playground
```

## Comandos utiles durante demo

```bash
kubectl get ns
kubectl get pods -n dev
kubectl get applications -n argocd
kubectl get pods -n argocd
kubectl get deploy,svc -n dev
curl http://localhost:8888/
```

## Limpieza y destruccion

Borrado de cluster:

```bash
k3d cluster delete iot-cluster
```

Limpieza completa Docker (agresiva):

```bash
docker rm -f $(docker ps -aq)
docker rmi -f $(docker images -aq)
docker volume prune -f
docker network prune -f
```

Limpieza menos agresiva:

```bash
docker container prune -f
docker image prune -a -f
docker volume prune -f
docker network prune -f
```

Nota: estos comandos pueden borrar recursos de otros proyectos si comparten la misma instalacion Docker.
