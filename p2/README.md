# Parte 2: K3s y 3 Aplicaciones Web Básicas

## 🧠 ¿Qué aprendemos aquí? (Conceptos Clave de K8s)
En la parte 1 levantamos la infraestructura básica (Nodos). En esta parte 2 damos el salto a desplegar aplicaciones reales dentro del clúster usando objetos nativos de Kubernetes. A diferencia de un simple Docker, aquí se usan varias capas de abstracción:

1. **ConfigMap**: Donde guardamos la configuración en texto plano (en nuestro caso, el código HTML plano de las webs de App1, App2 y App3). Evita tener que crear imágenes de Docker personalizadas solo para cambiar un texto.
2. **Deployment**: Es la orden de ejecución. Le dice a Kubernetes "Quiero X copias (réplicas) de este contenedor". Kubernetes se encarga de resucitarlas si mueren. Por ejemplo, verás que `App2` tiene **3 réplicas** funcionando simultáneamente para balancear la carga (como exige el Subject).
3. **Service (ClusterIP)**: Un Deployment por sí solo no tiene una IP estable. El *Service* agrupa esos contenedores y les da un nombre local fijo (ej: `app1.default.svc`) dentro del clúster.
4. **Ingress (Traefik)**: Es el portero de discoteca (Proxy Inverso). Escucha en la IP pública del servidor y, leyendo la cabecera `Host` de la petición HTTP, decide a qué `Service` enviar el tráfico (hacia `App1` o hacia `App2`). K3s usa **Traefik** como controlador de Ingress por defecto.

## 📝 Requisitos de la Práctica
- Una única máquina `miguelS` (`192.168.56.110`) actuando de Server.
- Tres aplicaciones web corriendo.
- Ingress configurado para:
  - `app1.com` 👉 Dirige a la Aplicación 1
  - `app2.com` 👉 Dirige a la Aplicación 2 (3 réplicas)
  - Cualquier otro host 👉 Dirige a la Aplicación 3 por defecto.

## 🚀 ¿Cómo levantar todo?
1.Abre tu terminal y colócate en la carpeta (`cd p2`).
2.Ejecuta:
  ```bash
  vagrant up
  ```
> **Nota**: Igual que en la Parte 1, este Vagrantfile incorpora la lógica **Multi-Arquitectura**. Automáticamente usará VMware/Parallels si detecta tu Mac M4, o VirtualBox si lo abre el evaluador en los ordenadores de la escuela. 

## 🎯 Probarlo desde tu Mac (¡Sin entrar por SSH!)
Dado que tu Ingress ya expone los puertos 80 hacia el exterior, puedes consultarlos directamente simulando que eres un navegador web usando curl y modificando su cabecera (Header -> `-H`):

```bash
# Probar App1
curl -H "Host: app1.com" http://192.168.56.110

# Probar App2 (Prueba varias veces para ver cómo balancea la carga entre réplicas)
curl -H "Host: app2.com" http://192.168.56.110

# Probar App3 (Default genérico si el host se inventa o no coincide)
curl -H "Host: meloinvento.test" http://192.168.56.110
```

## 🛠 Comandos Útiles de Kubernetes
Si necesitas enseñarle las entrañas al evaluador, debes entrar por SSH (`vagrant ssh miguelS`) y probar:

- **Ver el Ingress y las rutas**:
  ```bash
  kubectl get ingress
  ```
- **Ver los Deployments y Réplicas (¡Mira cuántas hay de app2!)**:
  ```bash
  kubectl get deploy
  ```
- **Ver todos los Pods (Contenedores físicos finales)**:
  ```bash
  kubectl get pods
  ```

## 🧹 Limpieza y Destrucción
Al igual que en p1, no dejes las máquinas consumiendo RAM en tu sistema.
```bash
vagrant destroy -f
```
