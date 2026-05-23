# Parte 3: K3d y Argo CD

## Conceptos Clave

En esta parte pasamos a un flujo GitOps real:

1. Levantamos un cluster K3d ligero.
2. Instalamos Argo CD dentro del cluster.
3. Argo CD observa un repositorio GitHub publico con los manifiestos.
4. Cuando cambia el manifiesto en GitHub, Argo CD reconcilia y aplica el estado deseado en Kubernetes.
5. La app se publica con imagen en Docker Hub y se sirve en `localhost:8888`.

La idea es demostrar despliegue automatizado con trazabilidad: GitHub (estado deseado) -> Argo CD (reconciliacion) -> cluster (estado real).

## Requisitos de la practica

- Cluster K3d con namespaces `argocd` y `dev`.
- Argo CD instalado y accesible por navegador.
- Repositorio GitHub publico con login de un miembro en el nombre.
- Imagen Docker Hub con login de un miembro y dos tags requeridos (`v1`, `v2`).
- Demostracion de cambio de version `v1` -> `v2` mediante commit/push en GitHub.

## Que tenemos en esta carpeta

1. [scripts/install.sh](scripts/install.sh): bootstrap principal. Instala dependencias, crea cluster, instala Argo CD y aplica la Application.
2. [confs/argocd.yaml](confs/argocd.yaml): manifiesto de Argo CD Application (repo, rama, path y sync policy).
3. [repo-github/deployment.yaml](repo-github/deployment.yaml): manifiesto que se sube al repo publico monitorizado por Argo CD.
4. [repo-github/app.py](repo-github/app.py): aplicacion web simple con version `v1`/`v2`.
5. [repo-github/Dockerfile](repo-github/Dockerfile): imagen de la app.


## Requisitos previos

1. Docker Desktop (o daemon Docker) activo.
2. Acceso a GitHub y repo publico con nombre tipo `mlezcano-iot-argocd`.

	``https://github.com/mikelezc/mlezcano-iot-argocd/``

3. Imagen Docker Hub publica con login de miembro, por ejemplo `mikelezc/playground`.

	``https://hub.docker.com/repository/docker/mikelezc/playground/general``

	Hemos tenido que hacer la aplicación, meterla en un contenedor y subirla a dockerhub manualmente, ya que el proyecto se ha desarrollado en un Mac con M4 pro y necesitábamos un contenedor multi arquitectura que se pudiera desplegar en máquinas con AMD y ARM.

4. Tags publicados en Docker Hub: `v1` y `v2`.

Verificacion rapida de Docker Hub:

```bash
docker pull mikelezc/playground:v1
docker pull mikelezc/playground:v2
```

## Arranque de infraestructura

Desde `p3/`:

```bash
./scripts/install.sh
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
