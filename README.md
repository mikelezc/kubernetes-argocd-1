# Inception of Things (IoT)

## Qué es este proyecto

**Inception of Things** es una introducción práctica a Kubernetes a través de cuatro entornos progresivos.
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
- **Docker Hub**: la imagen de docker usada en el proyecto `mikelezc/playground` se fué desarrollada y se publicó como manifiesto multi-arquitectura
  con soporte para `linux/amd64` y `linux/arm64`. En el subject proyecto se hablaba de la posibilidad de usar una que nos daban ya hecha, pero había incompatibilidades con ARM y se optó por desarrollarla de esta manera finalmente.

En una máquina AMD64 con Linux, VirtualBox es el proveedor estándar de Vagrant y funciona sin
cambios adicionales.

## Recursos externos del proyecto

| Recurso | URL |
|---------|-----|
| Repositorio GitHub (p3) | `https://github.com/mikelezc/mlezcano-iot-argocd` |
| Imagen Docker Hub | `https://hub.docker.com/r/mikelezc/playground` |

## Conceptos clave por parte

**K3s** (p1, p2): Kubernetes ligero. Ideal para VMs con
pocos recursos y para aprender sin la sobrecarga de un cluster Kubernetes completo.

**Vagrant** (p1, p2, bonus): define y levanta VMs reproducibles desde un `Vagrantfile`. Con un solo comando
(`vagrant up`) se puede crear, configurar e instalar todo lo necesario dentro de la VM.

**Traefik** (p1, p2): proxy inverso y balanceador de carga moderno que enruta automáticamente el tráfico entre servicios y aplicaciones, en entornos Docker, Kubernetes y microservicios.

**Ingress** (p2): objeto de Kubernetes que enruta el tráfico HTTP entrante hacia diferentes servicios
según el `Host` header o la ruta de la URL. En K3s viene integrado con Traefik.

**K3d** (p3, bonus): ejecuta K3s dentro de contenedores Docker. Permite tener un cluster de Kubernetes
completo en la máquina local sin VMs, arrancando en segundos.

**Argo CD** (p3, bonus): controlador GitOps. Observa un repositorio Git y reconcilia continuamente
el estado del cluster con lo que describen los manifiestos en el repo. Si hay diferencias, las actualiza.

**GitOps** (p3, bonus): paradigma donde el repositorio Git es la única fuente de verdad del estado
de la infraestructura. Ningún cambio se aplica manualmente: todo pasa por un commit.

**Helm** (bonus): gestor de paquetes para Kubernetes. Permite instalar aplicaciones complejas
(como GitLab, con decenas de componentes) con un solo comando y un fichero de valores.
