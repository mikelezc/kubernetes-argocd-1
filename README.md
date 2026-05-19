# Inception of Things - Proyecto Explicado 🚀

Este repositorio contiene la solución completa para el proyecto **Inception of Things (IoT)**, estructurado y documentado para que alguien que no ha tocado estas tecnologías (Vagrant, Kubernetes, K3s, K3d, ArgoCD) lo entienda paso a paso.

## 🛠 Atento a tu Mac (Apple Silicon M4 Pro)
El "Subject" original habla de usar Vagrant y (normalmente implican) VirtualBox. **VirtualBox no funciona en los nuevos Mac con chips M (M1, M2, M3, M4)** de forma nativa/rendimiento decente.
Si la escuela te exige hacerlo en una máquina virtual Linux, puedes ejecutar una VM (por ejemplo en UTM, Parallels o VMware) con Ubuntu Server, y dentro de esa VM ejecutar todo este proyecto (Vagrant usa QEMU/KVM en Linux sin problemas).

Si vas a ejecutar Vagrant **directamente desde tu Mac (macOS)**, asegúrate de tener instalado un proveedor compatible con ARM64, como `vmware_desktop` o Parallels, y cambiar las `boxes` de Vagrant (`bento/ubuntu-22.04` por `bento/ubuntu-22.04-arm64`). En los scripts te lo dejo indicado.

---

## 📖 Conceptos Previos Rápidos

1. **Vagrant**: Una herramienta para crear y configurar Máquinas Virtuales (VMs) a través de un archivo de texto (`Vagrantfile`). Con un comando (`vagrant up`) levantas las máquinas, instalar programas y configurarlas sin tocar la interfaz gráfica (la UI de VirtualBox/VMware).
2. **Kubernetes (K8s)**: Es un sistema para manejar "contenedores" (piensa en Docker). Escala tus apps, las reinicia si fallan y las actualiza. Es súper completo pero *pesado*.
3. **K3s**: Es Kubernetes pero en versión "Light", súper ligero, ideal para entornos con pocos recursos, quita funciones engorrosas y deja lo esencial en un solo archivo binario.
4. **K3d**: Es K3s pero que se ejecuta ¡dentro de Docker! En vez de levantar máquinas virtuales, usas contenedores de Docker para simular nodos de Kubernetes. Más rápido.
5. **Argo CD / GitOps**: Es una herramienta que vigila un repositorio tuyo de GitHub, y si cambias algo allí (por ejemplo la versión de tu app de v1 a v2), Argo CD lo detecta y lo actualiza automáticamente en Kubernetes.

---

## 📂 Organización de este Directorio

Se han separado las 3 partes obligatorias tal y como exige el Subject:

- **p1/**: Contiene la Parte 1. Configuración de 2 VMs usando Vagrant. Una actuará de servidor K3s y otra de trabajador (Agent).
- **p2/**: Contiene la Parte 2. Configuración de 1 VM servidor K3s. Se despliegan 3 aplicaciones web de ejemplo manejadas por un **Ingress** (como un recepcionista que reparte el tráfico web).
- **p3/**: Contiene la Parte 3. Usa K3d (K3s en Docker) en lugar de Vagrant, para desplegar ArgoCD y crear un flujo de integración continua (CI/CD) conectado a GitHub.

¡Echa un vistazo a los README de cada carpeta para continuar!
