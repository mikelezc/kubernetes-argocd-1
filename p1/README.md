# Parte 1: K3s y Vagrant

El objetivo de este proyecto es tener nuestro primer contacto real con **Kubernetes (K8s)**, el sistema estándar en la industria para orquestar contenedores. 

Dado que Kubernetes estándar consume muchísimos recursos para ser montado de cero de forma local, utilizamos **K3s**.

**K3s** es una distribución certificada de Kubernetes creada por *[Rancher](https://www.rancher.com)*, diseñada para ser extremadamente ligera (ocupa menos de 100MB). 

Es ideal para despliegues IoT (Internet of Things), Edge computing y aprendizaje como en nuestro caso.

---

## Arquitectura de nuestro clúster:

- **Server (Control-Plane)**: Es el nodo principal del clúster. Expone la API de Kubernetes para interactuar con el sistema y mantiene el estado general del clúster (utilizando SQLite en K3s en lugar de etcd).

- **Worker (Agent)**: En un cluster de Kubernetes, son los nodos de trabajo encargados de ejecutar las cargas de trabajo (en este proyecto implementaremos un solo nodo). No toma decisiones administrativas: obedece al Server, ejecuta los Pods (contenedores) asignados y les proporciona conectividad dentro de la red interna del clúster.

---

## Requisitos de la Práctica (Subject)

- **Máquina 1 (Server)**: Hostname `mlezcanoS`, IP: `192.168.56.110`.

- **Máquina 2 (Worker)**: Hostname `mlezcanoSW`, IP: `192.168.56.111`.

- SSH configurado en ambas máquinas sin password.

- K3s en modo *controller* en el Server, K3s en modo *agent* en el Worker.

---

## Checklist de verificación del cluster


1. **Desplegando nuestro cluster**

  - En `p1/` ejecutamos `vagrant up`.

---

2. **Verificando que el Server y el Worker tienen los nombres correctos**

  - Ejecutando `vagrant status` podemos ver las dos VM desplegadas por vagrant con los nombres requeridos por el subject.

	***-->*** El clúster de K8s está dentro de las VM deplegadas por Vagrant, así que vamos a acceder vía ssh a cada VM (donde vive cada nodo).

  - Entramos al Server con `vagrant ssh mlezcanoS` (ssh sin contraseña como requiere el subject).
  - Ejecutamos `hostname` o `hostnamectl`.
  - Este responderá con: `"mlezcanoS"` (server).
  - Si salimos de esa vm (`exit`) y entramos a la VM con el nodo worker con `vagrant ssh mlezcanoSW` (worker), podemos hacer lo mismo. Debe responder `mlezcanoSW`.

---

3. **Verificamos la interfaz de red `eth1` y sus IPs**

  - En cada máquina ejecutamos `ip addr show eth1`.
  - En el Server debe aparecer `192.168.56.110`.
  - En el Worker debe aparecer `192.168.56.111`.

---

4. **Verificamos que K3s está instalado y esta funcionando**
  
  - Entramos en el Server, porque ahí vive el control-plane. `vagrant ssh mlezcanoS`
  - Ejecutamos `kubectl cluster-info`.
  - Podemos ver que el control plane, CoreDNS y metrics-server están accesibles desde la API de K3s.

---

5. **Verificamos que ambos nodos están en el mismo clúster**
  
  - Desde el Server ejecutamos `kubectl get nodes -o wide` (la flag `-o wide`amplía la cantidad de info).
  - Deben aparecer `mlezcanoS` y `mlezcanoSW`.
  - Ambos deben estar en estado `Ready`.

---

6. **Verificamos que los pods del sistema están arriba**
  
  - Ejecuta `kubectl get pods -n kube-system`.
  - Podremos ver pods como CoreDNS, metrics-server, flannel o los componentes que use tu instalación de K3s.

***Explicación de los Pods del clúster (Componentes del sistema):***

- **`coredns-...`**: Servidor DNS interno del clúster. Permite que los Pods se comuniquen entre sí usando nombres de dominio internos (ej. `mi-servicio.default.svc.cluster.local`) en lugar de IPs efímeras.

- **`helm-install-traefik-...` y `helm-install-traefik-crd-...`**: Trabajos temporales (*Jobs*) que K3s ejecuta al arrancar para desplegar Traefik y sus definiciones de recursos personalizados (CRDs). El estado `Completed` indica que la instalación terminó con éxito y ya no consumen recursos.

- **`local-path-provisioner-...`**: Controlador de almacenamiento (*StorageClass* por defecto). Permite a los Pods solicitar almacenamiento persistente (`PersistentVolume`) reservando y gestionando directorios en el propio disco de la VM.

- **`metrics-server-...`**: Recolector de métricas en tiempo real. Mide el consumo de CPU y memoria de los nodos y Pods; es el componente que alimenta comandos como `kubectl top`.

- **`svclb-traefik-...` (Klipper Load Balancer)**: Balanceador de carga liviano integrado en K3s (*Service LB*). Mapea los puertos físicos de la VM (80/443) hacia el Ingress Controller.

- **`traefik-...`**: El *Ingress Controller* por defecto del clúster. Actúa como proxy inverso y punto de entrada unificado para enrutar el tráfico HTTP/HTTPS externo hacia los Servicios adecuados según las reglas definidas.

---

7. **Entendiendo el 401 de la URL del metrics-server**

  - Si abrimos en el navegador la URL que devuelve `kubectl cluster-info`, como `https://192.168.56.110:6443/api/v1/namespaces/kube-system/services/https:metrics-server:https/proxy`, es normal que salga `Unauthorized`.
  
  - Esa URL es un endpoint de la API de Kubernetes, no una página web pública.
  
  - El navegador no lleva las credenciales/certificados de `kubectl`, así que la respuesta 401 significa que el clúster está protegiendo correctamente el acceso.

---

8. **Comandos de limpieza y recreación de vagrant**

- Apagar las máquinas (SIN destruirlas): `vagrant halt`
- Si queremos volver a arrancarlas tras detenerlaspodemos hacer otra vez `vagrant up`.

- **Para DESTRUIR por completo el clúster (Recomendado al acabar):**

  ```bash
  vagrant destroy -f
  ```
- Borrará las VMs definitivamente recuperando el almacenamiento.
- El flag `-f` sirve para no tener que estar confirmando la destrucción de cada nodo de forma manual (full).
  

  *Nota - Al terminar, podemos borrar opcionalmente el token local generado con `rm node-token` aunque este ya está ignorado en .gitignore*
