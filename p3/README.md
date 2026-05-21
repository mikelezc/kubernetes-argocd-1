# Parte 3: K3d y Argo CD

Esta parte está pensada para una infraestructura mínima, rápida y fácil de defender. La idea es muy simple:

1. Levantas una única VM o usas tu máquina con Docker Desktop.
2. El script instala Docker, kubectl y k3d si hace falta.
3. Se crea un cluster K3d pequeño, con un solo server.
4. Se instalan dos namespaces: `argocd` y `dev`.
5. Argo CD mira un repo público de GitHub.
6. La aplicación que despliega Argo CD usa una imagen propia de DockerHub del grupo.

El objetivo no es complicar el entorno, sino dejar un flujo corto, reproducible y fácil de verificar en defensa.

## Qué hay en esta carpeta

1. [scripts/install.sh](scripts/install.sh): bootstrap principal. Instala dependencias, crea el cluster, despliega Argo CD y aplica la Application.
2. [confs/argocd.yaml](confs/argocd.yaml): manifiesto de Argo CD que apunta al repo GitHub.
3. [repo-github/deployment.yaml](repo-github/deployment.yaml): manifiesto que debes subir a tu repo público.
4. [Vagrantfile](Vagrantfile): envoltorio opcional para levantar una VM de desarrollo.
5. [DIAGNOSTICOS_COMPLETO.md](DIAGNOSTICOS_COMPLETO.md): guía de ayuda si algo falla durante las comprobaciones.

## Requisitos previos

Antes de arrancar, comprueba estas condiciones:

1. Tener Docker disponible.
2. Tener acceso a GitHub y un repo público creado con el login de un miembro del grupo en el nombre.
3. Tener una VM disponible si vas a hacer la defensa en entorno aislado.
4. Tener el repo ya clonado localmente para editar los ficheros del proyecto.

## Estructura del repo GitHub

El repo público de GitHub debe contener al menos el archivo `deployment.yaml` en la raíz.

El nombre del repo debe incluir el login de alguien del grupo. Por ejemplo:

```text
mlezcano-iot-argocd
```

La imagen que debe usar el deployment debe estar en DockerHub bajo el login de un miembro del grupo:

```yaml
image: mlezcano/playground:v1
```

Para la segunda versión, no cambies la imagen: cambia `VERSION` de `v1` a `v2` en el Deployment, haz commit y push. Así evitas problemas de caché con la imagen.

Si tu login de DockerHub no es `mlezcano`, reemplázalo por el tuyo.

## Cómo desplegar todo

Tienes dos formas razonables de levantar la infraestructura:

1. En tu macOS, con Docker Desktop abierto y funcionando.
2. Dentro de una VM Linux ligera si quieres reproducir la defensa.

En ambos casos el script es el mismo:

```bash
./scripts/install.sh
```

Si prefieres usar Vagrant para la VM de desarrollo:

```bash
vagrant up
```

El Vagrantfile está pensado para preparar una VM simple y luego ejecutar el script de instalación automáticamente.

## Qué hace el script de instalación

El bootstrap sigue esta secuencia:

1. Comprueba si Docker está instalado.
2. Comprueba si kubectl está instalado.
3. Comprueba si k3d está instalado.
4. Verifica que Docker responde.
5. Borra el cluster anterior si existía.
6. Crea un cluster K3d pequeño.
7. Ajusta CoreDNS para que la resolución externa sea estable.
8. Crea los namespaces `argocd` y `dev`.
9. Instala Argo CD.
10. Reduce la reconciliación de Argo CD a unos pocos segundos para que los cambios se noten rápido.
11. Expone Argo CD por HTTP para poder abrir su UI desde el host.
12. Aplica la Application que apunta a tu repo público.

## Despliegue paso a paso

### Opción A: en macOS con Docker Desktop

1. Abre Docker Desktop y espera a que esté listo.
2. Abre una terminal en este directorio.
3. Ejecuta:

```bash
./scripts/install.sh
```

4. Espera a que termine.
5. Abre la UI de Argo CD en:

```bash
http://localhost:8080
```

6. Abre la aplicación en:

```bash
http://localhost:8888
```

### Opción B: dentro de una VM con Vagrant

1. Entra en la carpeta `p3`.
2. Arranca la VM:

```bash
vagrant up
```

3. Espera a que acabe el provisionamiento.
4. Si necesitas acceder a la VM manualmente:

```bash
vagrant ssh mlezcanoS
```

5. Dentro de la VM puedes comprobar el estado del cluster con kubectl.

## Comprobaciones obligatorias

### 1. Ver namespaces

Debes ver al menos estos dos namespaces:

```bash
kubectl get ns
```

Resultado esperado:

```text
NAME      STATUS   AGE
argocd    Active   ...
dev       Active   ...
```

### 2. Ver pods en `dev`

Comprueba que la aplicación existe y está levantada:

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

Debes ver la Application `iot-app` y su estado.

### 4. Ver el deployment que se está usando

El archivo `deployment.yaml` del repo GitHub debe apuntar a la versión esperada:

```bash
grep 'playground' repo-github/deployment.yaml
```

Debería mostrar `v1` inicialmente.

### 5. Ver la app desde el navegador o con curl

Abre la aplicación en:

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

Si no usas Vagrant y quieres obtenerla manualmente, puedes leer el secreto del cluster:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

Si prefieres ver el valor completo en un solo comando:

```bash
echo "Usuario: admin"
echo "Contraseña: $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
```

## Cómo cambiar de v1 a v2

El cambio de versión se hace desde el repo de GitHub, no desde la VM.

### Paso 1: editar el deployment

Abre el archivo `deployment.yaml` de tu repo público y cambia:

```yaml
value: "v1"
```

por:

```yaml
value: "v2"
```

La imagen puede quedarse igual. La app lee la variable de entorno `VERSION` y pinta v1 o v2 según ese valor.

### Paso 2: commit y push

Haz commit y push al repo público.

### Paso 3: esperar o refrescar

Argo CD debería detectar el cambio y sincronizar solo.

Si no lo hace de inmediato, refresca la app desde la UI de Argo CD o fuerza un refresh desde kubectl.

En este proyecto, el intervalo de reconciliación de Argo CD se deja en 5 segundos, así que el cambio suele aparecer enseguida sin intervención manual.

### Paso 4: verificar la nueva versión

Vuelve a entrar en la app:

```bash
curl http://localhost:8888/
```

Deberías ver el mensaje de la versión `v2`.

## Qué comprobar durante la defensa

Si te piden mostrar el flujo completo, lo ideal es ir en este orden:

1. Mostrar que existen `argocd` y `dev`.
2. Mostrar que hay al menos un pod en `dev`.
3. Mostrar la UI de Argo CD.
4. Mostrar la app en `v1`.
5. Cambiar `VERSION` en GitHub a `v2`.
6. Esperar la sincronización.
7. Volver a mostrar la app en `v2`.

## Limpieza

### Si usaste Vagrant

```bash
vagrant destroy -f
```

Si quieres limpiar también el estado local de Vagrant:

```bash
rm -rf .vagrant/
```

### Si usaste K3d directamente

```bash
k3d cluster delete iot-cluster
```

Ese comando borra el cluster, pero no limpia por sí solo todos los recursos que Docker puede dejar atrás.

### Limpieza completa de Docker

Si quieres dejar el entorno totalmente limpio, puedes borrar también contenedores, imágenes, volúmenes y redes que ya no uses.

Primero revisa qué hay antes de borrar nada:

```bash
docker ps -a
docker images
docker volume ls
docker network ls
```

Luego, si quieres un reset completo del entorno local de este proyecto:

```bash
docker rm -f $(docker ps -aq)
docker rmi -f $(docker images -aq)
docker volume prune -f
docker network prune -f
```

Si prefieres una limpieza menos agresiva, usa solo estos comandos:

```bash
docker container prune -f
docker image prune -a -f
docker volume prune -f
docker network prune -f
```

Ten en cuenta que los comandos anteriores pueden borrar recursos de otros proyectos si los estás reutilizando en la misma instalación de Docker.

## Si algo falla

Si la instalación no termina o Argo CD no sincroniza, revisa esta secuencia:

1. Verifica que Docker responde.
2. Verifica que el cluster existe.
3. Verifica que los pods de Argo CD están Running.
4. Verifica que `kubectl get ns` muestra `argocd` y `dev`.
5. Verifica que el repo GitHub es público y la URL del Application es correcta.
6. Verifica que `deployment.yaml` usa el login correcto en la imagen y que `VERSION` está en `v1` o `v2`.

Si necesitas más detalle de diagnóstico, usa [DIAGNOSTICOS_COMPLETO.md](DIAGNOSTICOS_COMPLETO.md).
