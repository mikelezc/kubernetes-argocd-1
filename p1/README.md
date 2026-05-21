# Parte 1: K3s y Vagrant

## ¿Qué es esto y por qué lo usamos?
El objetivo de este proyecto es tener nuestro primer contacto real con **Kubernetes (K8s)**, el sistema estándar en la industria para orquestar contenedores. Dado que Kubernetes estándar consume muchísimos recursos para ser montado de cero de forma local, utilizamos **K3s**.

**K3s** es una distribución certificada de Kubernetes creada por *Rancher* diseñada para ser extremadamente ligera (ocupa menos de 100MB). Es ideal para despliegues IoT (Internet of Things), Edge computing y formación/laboratorios como en nuestro caso.

Arquitectura de nuestro clúster:
- **Server (Controller / Control-Plane)**: Es el nodo "master" del clúster. Expone una API para que nos comuniquemos con él y mantiene el estado general (usando SQLite en el caso de K3s en vez de etcd).
- **Worker (Agent)**: Son los nodos de trabajo que realizarán las tareas (en este ejemplo es un solo nodo). No toma decisiones, simplemente obedece al Server y ejecuta los contenedores (Pods) que el Server le asigne. A estos contenedores les da conectividad de red interna.

## Requisitos de la Práctica (Subject)

- **Máquina 1 (Server)**: Hostname `miguelS`, IP: `192.168.56.110`.
- **Máquina 2 (Worker)**: Hostname `miguelSW`, IP: `192.168.56.111`.
- K3s en modo *controller* en el Server, K3s en modo *agent* en el Worker.

## Checklist de verificación del cluster

Si quieres comprobar que esta parte está bien antes de enseñar la demo, revisa esto paso a paso:

1. **Confirmar que existen las dos máquinas**
  - En `p1/` ejecuta `vagrant up`.
  - Luego comprueba que Vagrant ha levantado `miguelS` y `miguelSW`.

2. **Verificar que el Server y el Worker tienen los nombres correctos**
  - Entra al Server con `vagrant ssh miguelS`.
  - Ejecuta `hostname` o `hostnamectl`.
  - Debe responder `miguelS`.
  - Si entras al Worker con `vagrant ssh miguelSW`, debe responder `miguelSW`.

3. **Verificar la interfaz de red `eth1` y sus IPs**
  - En cada máquina ejecuta `ip addr show eth1`.
  - En el Server debe aparecer `192.168.56.110`.
  - En el Worker debe aparecer `192.168.56.111`.
  - Esta es la comprobación más importante de red para el evaluador.

4. **Verificar que K3s está instalado y funcionando**
  - Entra en el Server, porque ahí vive el control-plane. `vagrant ssh miguelS`
  - Ejecuta `kubectl cluster-info`.
  - Debes ver que el control plane, CoreDNS y metrics-server están accesibles desde la API de K3s.

5. **Verificar que ambos nodos están en el mismo clúster**
  - Desde el Server ejecuta `kubectl get nodes -o wide`.
  - Deben aparecer `miguelS` y `miguelSW`.
  - Ambos deben estar en estado `Ready`.

6. **Verificar que los pods del sistema están arriba**
  - Ejecuta `kubectl get pods -n kube-system`.
  - Debes ver pods como CoreDNS, metrics-server, flannel o los componentes que use tu instalación de K3s.

**Explicación de los diferentes PODS del cluster:**

    - `coredns-...`: servicio DNS interno del clúster. Permite resolver nombres de servicios y pods.
    - `helm-install-traefik-...` y `helm-install-traefik-crd-...`: tareas temporales de instalación que K3s usa para desplegar Traefik y sus CRDs. Que aparezcan como `Completed` es normal.
    - `local-path-provisioner-...`: provisión de almacenamiento local. Crea volúmenes persistentes simples sobre el disco de la VM.
    - `metrics-server-...`: recoge métricas básicas de CPU y memoria para el clúster.
    - `svclb-traefik-...`: balanceadores de servicio creados por K3s para exponer Traefik hacia fuera.
    - `traefik-...`: el ingress controller por defecto de K3s, encargado de enrutar tráfico HTTP/HTTPS hacia los servicios correctos.

7. **Entender el 401 de la URL del metrics-server**
  - Si abres en el navegador la URL que devuelve `kubectl cluster-info`, como `https://192.168.56.110:6443/api/v1/namespaces/kube-system/services/https:metrics-server:https/proxy`, es normal que salga `Unauthorized`.
  - Esa URL es un endpoint de la API de Kubernetes, no una página web pública.
  - El navegador no lleva las credenciales/certificados de `kubectl`, así que la respuesta 401 significa que el clúster está protegiendo correctamente el acceso.

## Comandos de uso


Ejecutamos Vagrant para levantar ambas máquinas:

  ```bash
  vagrant up
  ```

Como el clúster existe **dentro** de las máquinas virtuales, primero debes entrar al servidor (que es donde reside el control-plane y `kubectl`):

```bash
vagrant ssh miguelS
```

Una vez dentro, usaremos estos comandos:

- **1. Comprobar los nodos del clúster:**
  Se espera ver a `miguelS` (control-plane) y `miguelSW` (agent) con estado `Ready`.
  ```bash
  kubectl get nodes -o wide
  ```

- **2. Ver la información general del clúster (Dónde corre la API):**
  ```bash
  kubectl cluster-info
  ```

- **3. Ver todos los contenedores básicos del sistema (Pods del sistema):**
  Para confirmar que K3s ha levantado su propio DNS, red, métricas, etc:
  ```bash
  kubectl get pods -n kube-system
  ```

- **4. Para salir de la máquina virtual:**
  ```bash
  exit
  ```

## Limpieza y Recreación
Es fundamental saber cómo desmantelar todo para evitar que consuma recursos en segundo plano (RAM y CPU del host) y eliminar ficheros residuales generados por la máquina.

- **Apagar las máquinas (pero no destruirlas):**
  ```bash
  vagrant halt
  ```
- **Volver a arrancarlas tras detenerlas:**
  ```bash
  vagrant up
  ```
- **DESTRUIR por completo el clúster (Recomendado al acabar):**
  Borrará las VMs definitivamente recuperando el almacenamiento de tu Mac.
  ```bash
  vagrant destroy -f
  ```
  *(Podemos borrar opcionalmente el token local generado con `rm node-token`)*
