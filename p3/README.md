# Parte 3: K3d y Argo CD

## Conceptos Clave

Esta parte está pensada para una infraestructura mínima con los siguientes conceptos:

1. Ejecutaremos el script  ``./scripts/install.sh``
2. Este instala Docker, kubectl y k3d
3. Se creará un cluster K3d pequeño, con un solo server.
4. Se instalan dos namespaces: `argocd` y `dev`.
5. Argo CD mira a mi repo público de GitHub 
	``https://github.com/mikelezc/mlezcano-iot-argocd/``.
6. La aplicación que despliega Argo CD usa una imagen propia de DockerHub del grupo.
7. La versión de esta aplicación actualizará automáticamente según cambiemos el número de versión en el repo de github.

## Qué hay en esta carpeta

1. [scripts/install.sh](scripts/install.sh): bootstrap principal. Instala dependencias, crea el cluster, despliega Argo CD y aplica la Application.

2. [confs/argocd.yaml](confs/argocd.yaml): manifiesto de Argo CD que apunta al repo GitHub.

3. [repo-github/deployment.yaml](repo-github/deployment.yaml): manifiesto que ha sido subido a nuestro repo público.

4. [repo-dockerhub/deployment.yaml](repo-dockerhub/): carpeta con la aplicación que subimos a dockerhub para esta práctica.


## Requisitos previos

1. Tener Docker disponible.

2. Tener acceso a GitHub y un repo público en este caso es creado con el login de un miembro del grupo en el nombre. 
Hemos tenido que hacer la aplicación, meterla en un contenedor y subirla a dockerhub manualmente, ya que el proyecto se ha desarrollado en una Mac con M4 pro y necesitábamos un contenedor multi arquitectura que se pudiera desplegar en máquinas con AMD y ARM.

	```https://hub.docker.com/repository/docker/mikelezc/playground/general```

3. Tener una VM disponible si vas a hacer la defensa en entorno aislado.
4. Tener el repo ya clonado localmente para editar los ficheros del proyecto.

## Estructura del repo GitHub

El repo público de GitHub contiene el archivo `deployment.yaml` en la raíz.

El nombre del repo incluye el login de alguien del grupo:

```text
mlezcano-iot-argocd
```

La imagen que usa el deployment está en DockerHub bajo el login de un miembro del grupo:

```yaml
image: mlezcano/playground:v1
```

## Diferentes maneras desplegar todo

Como levantar la infraestructura:

1. En macOS, con Docker Desktop abierto y funcionando.
2. Dentro de una VM Linux ligera tal y como pide el subject.

En ambos casos usaremos el script de despliegue:

```bash
./scripts/install.sh
```

## Qué hace el script de instalación

1. Comprueba si Docker está instalado.
2. Comprueba si kubectl está instalado.
3. Comprueba si k3d está instalado.
4. Verifica que Docker responde.
5. Borra el cluster anterior si existía.
6. Crea el cluster K3d.
7. Ajusta CoreDNS para que la resolución externa sea estable.
8. Crea los namespaces `argocd` y `dev`.
9. Instala Argo CD.
10. Reduce la reconciliación de Argo CD a unos pocos segundos para que los cambios se noten rápido.
11. Expone Argo CD por HTTP para poder abrir su UI desde el host.
12. Aplica la Application que apunta al repo público.

## Despliegue paso a paso

1. Abrimos docker desktop o nos aseguramos que el daemon de docker esta activo.

2. Abrimos una terminal en este directorio.

3. Ejecutamos:

```bash
./scripts/install.sh
```

4. Esperamos a que termine.

5. Abre la UI de Argo CD en:

```bash
http://localhost:8080
```

6. Abrimos la aplicación en:

```bash
http://localhost:8888
```


7. Dentro de la VM podemos comprobar el estado del cluster con kubectl.

## Comprobaciones obligatorias

### 1. Ver namespaces

Revisamos los namespaces requeridos:

```bash
kubectl get ns
```

Resultado esperado:

```text
NAME      STATUS   AGE
argocd    Active   ...
dev       Active   ...
```

**NOTA** Además de esos dos, Kubernetes crea otros namespaces por defecto:

1. `default`: namespace general que Kubernetes crea al instalar el cluster. Si no indicas otro namespace, los recursos acaban aquí.
2. `kube-system`: donde viven los componentes internos del cluster, como CoreDNS, el proxy o partes del control plane.
3. `kube-public`: namespace público reservado para información que puede ser leída sin autenticación no lo tocamos.
4. `kube-node-lease`: lo usa Kubernetes para las leases de los nodos y saber si siguen vivos.

Lo importante es que hemos creado `argocd` y `dev`. Los demás aparecen siempre en un cluster recién creado.

### 2. Ver pods en `dev`

Comprobamos que la aplicación existe y está levantada:

```bash
kubectl get pods -n dev
```

Resultado esperado:

```text
NAME                           READY   STATUS    RESTARTS   AGE
mlezcano-playground-...        1/1     Running   0          ...
```

### 3. Ver la Application de Argo CD

```bash
kubectl get applications -n argocd
```

Comprobamos la Application `iot-app` y su estado.

```text
NAME      SYNC STATUS   HEALTH STATUS
iot-app   Synced        Healthy
```

### 4. Ver el deployment que se está usando

El archivo `deployment.yaml` del repo GitHub debe estar apuntando a la versión esperada:

```bash
        env:
        - name: VERSION
          value: "v1" # esta es la variable que tenemos que cambiar para las pruebas (v1 o v2).
```

### 5. Ver la app desde el navegador o con curl

Abrimos la aplicación en:

```bash
http://localhost:8888
```

O desde terminal:

```bash
curl http://localhost:8888/
```

La respuesta debe ser la de la versión activa de la app.

### 6. Ver la UI de Argo CD

Argo CD debe responder en:

```bash
http://localhost:8080
```

Usuario por defecto:

```text
admin
```

La contraseña inicial la imprime el script al final.

Se puede obtener manualmente, leyendo el secreto del cluster:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

## Cómo cambiar de v1 a v2

Hacemos el cambio de versión desde el repo de GitHub.
Esto demuestra que Argo CD está haciendo el pollin continuo de nuestro repo en github (requerido por el subject).

### Paso 1: editar el deployment

Abrimos el archivo `deployment.yaml` del repo público y cambiamos:

```yaml
value: "v1"
```

por:

```yaml
value: "v2"
```

La imagen puede quedarse igual. La app lee la variable de entorno `VERSION` y pinta v1 o v2 según ese valor.

### Paso 2: commit y push

Hacemos commit y push al repo público (o desde el propio GitHub).

### Paso 3: esperar o refrescar

Argo CD detecta el cambio y sincronizará solo, aunque debemos tener en cuenta que tardará en refrescar unos minutos.

También podemos refrescar la app desde la UI de Argo CD o forzar un refresh desde kubectl para no esperar.

```bash
kubectl -n argocd annotate application iot-app argocd.argoproj.io/refresh=hard --overwrite
```

Si además queremos reiniciar el despliegue en el cluster para que el pod vuelva a levantarse inmediatamente:

```bash
kubectl -n dev rollout restart deployment/mlezcano-playground
```

Ese segundo comando no suele ser necesario al estar Argo CD bien sincronizando, pero lo hemos usado como fallback en desarrollo bastante y resulta útil.

### Paso 4: verificar la nueva versión

Volvemos a entrar en la app:

```bash
curl http://localhost:8888/
```

Comprobamos el mensaje de la versión `v2`.


## Limpieza

Para limpiar el cluster y las imágenes, y archivos generados con docker ejecutaremos los siguientes comandos:

```bash
k3d cluster delete iot-cluster
```

**Nota** Ese comando borra el cluster, pero no limpia por sí solo todos los recursos que Docker puede dejar atrás.

### Limpieza completa de Docker

Para dejar el entorno totalmente limpio, borrar también contenedores, imágenes, volúmenes y redes.

Primero revisamos qué hay antes de borrar nada:

```bash
docker ps -a
docker images
docker volume ls
docker network ls
```

Borrado completo del entorno local de este proyecto:

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

Tendremos en cuenta que los comandos anteriores pueden borrar recursos de otros proyectos si los reutilizamos en la misma instalación de Docker.

