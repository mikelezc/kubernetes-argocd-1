## Sobre este proyecto

Este proyecto es una introducción práctica a Kubernetes a través de cuatro entornos que van incrementando su complejidad progresivamente.

Cada parte añade una capa nueva sobre la anterior: primero Vagrant y K3s, luego Ingress, después GitOps con Argo CD, y finalmente GitOps 100% local con GitLab on-premise.

## Estructura del repositorio

| Carpeta | Parte | Tecnologías | Qué hace |
|---------|-------|-------------|----------|
| [p1/](p1/) | Parte 1 | Vagrant + K3s | Dos VMs: un nodo maestro K3s y un nodo worker |
| [p2/](p2/) | Parte 2 | Vagrant + K3s + Ingress | Una VM con tres apps web enrutadas por nombre de host |
| [p3/](p3/) | Parte 3 | K3d + Argo CD + GitHub | GitOps: Argo CD sincroniza manifests desde GitHub |
| [bonus/](bonus/) | Bonus | K3d + Argo CD + GitLab | GitOps 100% local: Argo CD sincroniza desde GitLab on-premise |

Cada carpeta tiene su propio README con los detalles de arranque, verificación y comprobaciones para cada módulo.

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


**Kubernetes**: 

Es un orquestador de contenedores sobre el que se monta todo el proyecto. Agrupa los contenedores en `Pods`, organiza los `Pods` en `Namespaces`, y usa objetos declarativos (`Deployment`, `Service`, `Ingress`...) para mantenerlos corriendo y accesibles. 

Un objeto de Kubernetes es un recurso o entidad persistente en el clúster que representa el estado deseado de tu infraestructura.
Son básicamente registros de configuración guardados en la base de datos de Kubernetes (etcd).

`K3s`es una versión ligera de Kubernetes, y `K3d` es una herramienta para ejecutar K3s dentro de Docker en tu equipo local. Más adelante veremos cómo se usan y en qué se diferencian.

---

**Namespace vs Pod**: 

Un `Namespace` es una división lógica dentro del clúster que permite organizar, aislar y gestionar permisos (RBAC) o límites de recursos para un grupo de objetos (por ejemplo, separar el entorno de `dev` de las herramientas como `argocd`).

Un Pod es la unidad mínima de ejecución en Kubernetes, compuesta por uno o más contenedores que se despliegan juntos.

El `Namespace` es la "carpeta" que organiza el clúster, el `Pod` es la carga de trabajo real que corre dentro de ella. Todo Pod vive dentro de un único Namespace.

---

**Vagrant** (p1, p2, bonus):

Es una herramienta para crear y gestionar entornos de desarrollo basados en máquinas virtuales reproducibles mediante un archivo de configuración declarativo `Vagrantfile`, donde se definen parámetros como la imagen base (box), red, RAM/CPU y scripts de provisión.

Al ejecutar `vagrant up`, la VM se crea y arranca automáticamente, ejecutando el script de instalación inicial dentro de ella con permisos de root. Esto permite destruir y reconstruir exactamente el mismo entorno en cualquier máquina con un solo comando.

---

**K3s** (p1, p2):

Es una distribución ligera de Kubernetes (en un único binario) pensada para máquinas con pocos recursos o para aprender sin la complejidad de un clúster tradicional.

En este proyecto, la máquina Server arranca como nodo de Control Plane `k3s server`, mientras que la máquina Worker `ServerWorker` actúa como nodo de trabajo ejecutando k3s agent y uniéndose al servidor mediante el token que este genera en la carpeta compartida de Vagrant.

---

**Traefik** (p1, p2): 

Es un proxy inverso y balanceador de carga (capa 7 modelo OSI) que actúa como el `Ingress Controller` por defecto de K3s. Su función es recibir todo el tráfico HTTP/HTTPS que llega al clúster desde el exterior y, según las reglas definidas en los objetos Ingress, redirigirlo dinámicamente al Service interno que corresponda (el cual se encarga de balancear el tráfico hacia los Pods finales). El service es otro balanceador intemedio, este de capa 4 (TCP/UDP).

---

**Ingress** (p2): 

El objeto de Kubernetes que le dice a Traefik *cómo* enrutar el tráfico. A qué `Host` ir (`app1.com`, `app2.com`o cualquier otro por defecto) y qué ruta corresponde a cada `Service`. 

Sin un Ingress, Traefik no tendría forma de distinguir a cuál de las tres apps enviar cada petición si todas comparten la misma IP del nodo.

---

**Deployment, Service y réplicas** (p2): 

Un `Deployment` describe qué imagen ejecutar y cuántas copias (`replicas`) mantener siempre vivas (si una cae, Kubernetes la reemplaza sola, sin intervención manual). 

Un `Service` da a esas copias una IP estable y un nombre interno, para que el Ingress (o cualquier otro Pod) las alcance sin necesitar la IP real de cada Pod, que cambia cada vez que se recrea.

---

**K3d** (p3, bonus): 

Ejecuta K3s dentro de contenedores Docker en lugar de máquinas virtuales tradicionales. Cada "nodo" del clúster es, en realidad, un contenedor. 

Por eso un clúster completo arranca en segundos y el único prerrequisito real es tener Docker funcionando, sin necesidad de provisionar ni configurar máquinas virtuales pesadas.

---

**GitOps** (p3, bonus): 

Paradigma en el que un repositorio Git es la única fuente de verdad del estado deseado de la infraestructura. 

Nadie ejecuta `kubectl apply` a mano: se edita el manifiesto, se hace commit y push, y un controlador dentro del clúster se encarga de que el estado real converja con lo declarado en el repo.

---

**Argo CD** (p3, bonus): 

El controlador GitOps del proyecto. Corre dentro del propio clúster, vigila continuamente un repositorio (GitHub en la Parte 3, GitLab local en el bonus) y reconcilia: si detecta diferencias entre el manifiesto del repo y lo desplegado, las corrige automáticamente (`selfHeal`) y elimina lo que ya no está declarado (`prune`). 

En la UI, `Sync` indica si el clúster coincide con el repo y `Health` si los recursos desplegados están realmente sanos (no solo "creados", sino funcionando).

---

**Docker Hub y versionado de imágenes** (p3, bonus): 

El registro público donde se publica la imagen de la app (`mikelezc/playground`) con dos tags, `v1` y `v2`. 

Para desplegar una nueva versión no hace falta interactuar manualmente con el clúster: basta con actualizar el tag en el campo `image` del manifiesto en Git, hacer commit, y dejar que el flujo GitOps (Argo CD) detecte el cambio y actualice los Pods en el clúster automáticamente.

---

**Helm** (bonus): 

Gestor de paquetes para Kubernetes. Un `chart` (paquete) de Helm empaqueta decenas de manifiestos (Deployments, Services, Secrets, ConfigMaps...) de una aplicación compleja como GitLab, para instalarlos con un solo comando y un fichero de valores (`values.yaml`) en vez de aplicarlos uno a uno a mano.
