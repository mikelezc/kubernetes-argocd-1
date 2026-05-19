# Parte 1: K3s y Vagrant

## ¿Qué es esto y por qué lo usamos?
El objetivo de este proyecto es tener nuestro primer contacto real con **Kubernetes (K8s)**, el sistema estándar en la industria para orquestar contenedores. Dado que Kubernetes estándar consume muchísimos recursos para ser montado de cero de forma local, utilizamos **K3s**.

**K3s** es una distribución certificada de Kubernetes creada por *Rancher* diseñada para ser extremadamente ligera (ocupa menos de 100MB). Es ideal para despliegues IoT (Internet of Things), Edge computing y formación como en nuestro caso.

Arquitectura de nuestro clúster:
- **Server (Controller / Control-Plane)**: Es el "cerebro" del clúster. Expone una API para que nos comuniquemos con él y mantiene el estado general (usando SQLite en el caso de K3s en vez de etcd).
- **Worker (Agent)**: Es el "músculo". No toma decisiones, simplemente obedece al Server y ejecuta los contenedores (Pods) que el Server le asigne. A estos contenedores les da conectividad de red interna.

## 📝 Requisitos de la Práctica (Subject)
- **Máquina 1 (Server)**: Hostname `miguelS`, IP: `192.168.56.110`.
- **Máquina 2 (Worker)**: Hostname `miguelSW`, IP: `192.168.56.111`.
- K3s en modo *controller* en el Server, K3s en modo *agent* en el Worker.

## 🚀 ¿Cómo levantar el Clúster?
1.Abre tu terminal y colócate en la carpeta (`cd p1`).
2.Ejecuta Vagrant para levantar ambas máquinas:
  ```bash
  vagrant up
  ```
> **Magia Multi-Arquitectura**: Este proyecto ha sido automatizado para detectar automáticamente si el ordenador que hace el `vagrant up` es un Apple Silicon (ARM64) o un procesador x86_64 tradicional. Configurará dinámicamente el provider (VirtualBox, VMware o Parallels) sin tener que tocar código.

## 🎯 Comandos Útiles para la Evaluación (Demos)

Como el clúster existe **dentro** de las máquinas virtuales, primero debes entrar al servidor (que es donde reside el control-plane y `kubectl`):

```bash
vagrant ssh miguelS
```

Una vez dentro, usa estos comandos para la defensa:

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

## 🧹 Limpieza y Recreación
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
  *(Borra opcionalmente el token local generado con `rm node-token`)*
