## Sobre este proyecto

Esta una introducción práctica a Kubernetes a través de cuatro entornos que van incrementando su complejidad progresivamente.

Cada parte añade una capa nueva sobre la anterior: primero Vagrant y K3s, luego Ingress, después GitOps con Argo CD, y finalmente GitOps 100% local con GitLab on-premise.

## Estructura del repositorio

| Carpeta | Parte | Tecnologías | Qué hace |
|---------|-------|-------------|----------|
| [p1/](p1/) | Parte 1 | Vagrant + K3s | Dos VMs: un nodo servidor K3s y un nodo agente |
| [p2/](p2/) | Parte 2 | Vagrant + K3s + Ingress | Una VM con tres apps web enrutadas por nombre de host |
| [p3/](p3/) | Parte 3 | K3d + Argo CD + GitHub | GitOps: Argo CD sincroniza manifests desde GitHub |
| [bonus/](bonus/) | Bonus | K3d + Argo CD + GitLab | GitOps 100% local: Argo CD sincroniza desde GitLab on-premise |

Cada carpeta tiene su propio README con los detalles de arranque, verificación y comprobaciones para la corrección.

## Nota sobre multi-arquitectura (ARM vs AMD64)

Este proyecto se desarrolló mitad en Mac con Apple Silicon (ARM64) y la otra mitad en una máquina con Linux y arquitectura AMD64 (x86_64). Todos los módulos están preparados para funcionar en ambas arquitecturas:

- **p1 / p2**: el Vagrantfile detecta la arquitectura y elige el proveedor correcto
  (VMware Desktop en ARM, VirtualBox en AMD64). La box usada (`bento/ubuntu-22.04`) tiene imagen
  para ambas arquitecturas.
- **p3**: `scripts/install.sh` detecta `uname -m` y descarga el binario correcto de kubectl.
  K3d y Docker son compatibles con ambas arquitecturas de forma nativa.
- **bonus**: mismo comportamiento que p3. El Vagrantfile del bonus también detecta la arquitectura.
- **Docker Hub**: la imagen de docker usada en el proyecto `mikelezc/playground` fué desarrollada y se publicó como manifiesto multi-arquitectura
  con soporte para `linux/amd64` y `linux/arm64`. En el subject proyecto se hablaba de la posibilidad de usar una que nos daban ya hecha, pero había incompatibilidades con ARM y se optó por desarrollarla de esta manera finalmente.

En una máquina AMD64 con Linux, VirtualBox es el proveedor estándar de Vagrant y funciona sin
cambios adicionales.

## Recursos externos del proyecto

| Recurso | URL |
|---------|-----|
| Repositorio GitHub (p3) | `https://github.com/mikelezc/mlezcano-iot-argocd` |
| Imagen Docker Hub | `https://hub.docker.com/r/mikelezc/playground` |

## Conceptos clave por parte


**Kubernetes**: el orquestador de contenedores sobre el que se monta todo el proyecto. Agrupa los contenedores en `Pods`, organiza los `Pods` en `Namespaces`, y usa objetos declarativos (`Deployment`, `Service`, `Ingress`...) para mantenerlos corriendo y accesibles. K3s y K3d son solo dos formas distintas de arrancar ese mismo Kubernetes, veremos más adelante en que se diferencian.

**Namespace vs Pod**: un `Namespace` es una partición lógica del clúster para agrupar y aislar recursos — por ejemplo `argocd` y `dev` en la Parte 3, o `gitlab` en el bonus. Un `Pod` es la unidad mínima de ejecución: uno o más contenedores desplegados juntos en un mismo nodo. Un namespace puede contener muchos pods (y deployments, services...) y un pod siempre vive dentro de un único namespace.

**Vagrant** (p1, p2, bonus): herramienta que describe una máquina virtual reproducible en un `Vagrantfile` (caja base, IP, RAM/CPU, script de provisión). Con `vagrant up` crea la VM, la arranca y ejecuta automáticamente el script de instalación dentro de ella con permisos de root — así se puede reconstruir fácilente el mismo entorno con un solo comando, sin depender de los privilegios del host.

**K3s** (p1, p2): es una distribución ligera de Kubernetes (en un único binario) pensada para máquinas con pocos recursos o para aprender sin la complejidad operativa de un clúster completo. En este proyecto, el nodo *Server* arranca con `k3s server` (control-plane / controlador) y el nodo *ServerWorker* con `k3s agent` (worker), uniéndose al primero mediante un token que el servidor genera y comparte por la carpeta sincronizada de Vagrant.

**Traefik** (p1, p2): proxy inverso que K3s instala por defecto sin configuración extra. Es el componente que realmente recibe todo el tráfico HTTP que llega al clúster y decide a qué `Service` reenviarlo.

**Ingress** (p2): el objeto de Kubernetes que le dice a Traefik *cómo* enrutar — qué `Host` (`app1.com`, `app2.com`, cualquier otro por defecto) o ruta corresponde a cada `Service`. Sin un Ingress, Traefik no tendría forma de distinguir entre las tres apps que comparten la misma IP del nodo.

**Deployment, Service y réplicas** (p2): un `Deployment` describe qué imagen ejecutar y cuántas copias (`replicas`) mantener siempre vivas — si una cae, Kubernetes la reemplaza sola, sin intervención manual. Un `Service` da a esas copias una IP estable y un nombre interno, para que el Ingress (o cualquier otro Pod) las alcance sin necesitar la IP real de cada Pod, que cambia cada vez que se recrea.

**K3d** (p3, bonus): ejecuta K3s dentro de contenedores Docker en lugar de máquinas virtuales — cada "nodo" del clúster es, en realidad, un contenedor. Por eso un clúster completo arranca en segundos y el único prerrequisito real es tener Docker funcionando; no hace falta virtualización de hardware.

**GitOps** (p3, bonus): paradigma en el que un repositorio Git es la única fuente de verdad del estado deseado de la infraestructura. Nadie ejecuta `kubectl apply` a mano: se edita el manifiesto, se hace commit y push, y un controlador dentro del clúster se encarga de que el estado real converja con lo declarado en el repo.

**Argo CD** (p3, bonus): el controlador GitOps del proyecto. Corre dentro del propio clúster, vigila continuamente un repositorio (GitHub en la Parte 3, GitLab local en el bonus) y reconcilia: si detecta diferencias entre el manifiesto del repo y lo desplegado, las corrige automáticamente (`selfHeal`) y elimina lo que ya no está declarado (`prune`). En la UI, `Sync` indica si el clúster coincide con el repo y `Health` si los recursos desplegados están realmente sanos (no solo "creados", sino funcionando).

**Docker Hub y versionado de imágenes** (p3, bonus): el registro público donde se publica la imagen de la app (`mikelezc/playground`) con dos tags, `v1` y `v2`. Cambiar de versión no requiere tocar el clúster: basta con editar el campo `image` del manifiesto en Git y dejar que el flujo GitOps (Argo CD) haga el resto.

**Helm** (bonus): gestor de paquetes para Kubernetes. Un "chart" de Helm empaqueta decenas de manifiestos (Deployments, Services, Secrets, ConfigMaps...) de una aplicación compleja como GitLab, para instalarlos con un solo comando y un fichero de valores (`values.yaml`) en vez de aplicarlos uno a uno a mano.
