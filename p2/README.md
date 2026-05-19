# Parte 2: K3s y 3 Aplicaciones Web Básicas

## Conceptos Clave de K8s
En la parte 1 levantamos la infraestructura básica (Nodos). En esta parte 2 damos el salto a desplegar aplicaciones reales dentro del clúster usando objetos nativos de Kubernetes. A diferencia de un simple Docker, aquí se usan varias capas de abstracción:

1. **ConfigMap**: Donde guardamos la configuración en texto plano (en nuestro caso, el código HTML plano de las webs de App1, App2 y App3). Evita tener que crear imágenes de Docker personalizadas solo para cambiar un texto.
2. **Deployment**: Es la orden de ejecución. Le decimos a Kubernetes que queremos X copias (réplicas) de tal o cuál contenedor. Kubernetes se encarga de resucitarlas si mueren. Por ejemplo, veremos que `App2` tiene **3 réplicas** funcionando simultáneamente para balancear la carga (como se exige el Subject).
3. **Service (ClusterIP)**: Un Deployment por sí solo no tiene una IP estable. El *Service* agrupa esos contenedores y les da un nombre local fijo (ej: `app1.default.svc`) dentro del clúster.
4. **Ingress (Traefik)**: Es el portero de discoteca (Proxy Inverso). Escucha en la IP pública del servidor y, leyendo la cabecera `Host` de la petición HTTP, decide a qué `Service` enviar el tráfico (hacia `App1` o hacia `App2`). K3s usa **Traefik** como controlador de Ingress por defecto.

## Requisitos de la Práctica
- Una única máquina `miguelS` (`192.168.56.110`) actuando de Server.
- Tres aplicaciones web corriendo.
- Ingress configurado para:
  - `app1.com` -> Dirige a la Aplicación 1
  - `app2.com` -> Dirige a la Aplicación 2 (3 réplicas)
  - Cualquier otro host -> Dirige a la Aplicación 3 por defecto.

## ¿Cómo levantar todo?
1.Abre tu terminal y colócate en la carpeta (`cd p2`).
2.Ejecuta:
  ```bash
  vagrant up
  ```
> **Nota**: Igual que en la Parte 1, este Vagrantfile incorpora la lógica **Multi-Arquitectura**. Automáticamente usará VMware/Parallels si detecta Mac M4, o VirtualBox si se abre en otro equipo. 

## Probarlo desde terminal
Dado que Ingress ya expone los puertos 80 hacia el exterior, podemos consultarlos directamente usando curl y modificando su cabecera (Header -> `-H`):

```bash
# Probar App1
curl -H "Host: app1.com" http://192.168.56.110

# Probar App2 (Prueba varias veces para ver cómo balancea la carga entre réplicas)
curl -H "Host: app2.com" http://192.168.56.110

# Probar App3 (Default genérico si el host se inventa o no coincide)
curl -H "Host: meloinvento.test" http://192.168.56.110
```

## Probarlo desde el navegador
Para poder probarlo desde el navegador antes necesitarás modificar el archivo `/etc/hosts` de tu máquina anfitriona para que el sistema sepa que `app1.com`, `app2.com` y `app3.com` apuntan a la IP de la máquina virtual (`192.168.56.110`).

Para ello, abre una terminal en tu Mac (no dentro de la VM) y ejecuta:

```bash
sudo nano /etc/hosts
```

Añade las siguientes líneas al final del archivo:

```
192.168.56.110 app1.com
192.168.56.110 app2.com
192.168.56.110 app3.com
```

Guarda el archivo (Ctrl+O, Enter) y sal (Ctrl+X).

Ahora ya puedes abrir tu navegador y visitar:
- `http://app1.com`
- `http://app2.com`
- `http://app3.com`

## Comandos Útiles de Kubernetes
Para poder ver el cluster por dentro debes entrar por SSH (`vagrant ssh miguelS`) y probar:

1. **Ver el Ingress y las rutas**:
   ```bash
   kubectl get ingress
   ```
   **Lo que verás**:
   ```
   NAME          CLASS    HOSTS               ADDRESS          PORTS
   iot-ingress   <none>   app1.com,app2.com   192.168.56.110   80
   ```
   *¿Por qué no aparece app3.com?* Es el misterio mejor guardado: `app3.com` **NO** existe lógicamente en nuestro archivo. Lo que nosotros le hemos dicho a Kubernetes es "Las peticiones para app1 se van a la ruta 1, las de app2 a la ruta 2 y... **TODO lo demás (sin importar el nombre)** mételo hacia la ruta 3". Como la regla 3 es un "comodín vacío" (`*` o *cláusula por defecto*), Kubernetes sólo te enlista los dominios fijos en la columna `HOSTS`.

2. **Ver los Deployments y Réplicas**:
   ```bash
   kubectl get deploy
   ```
   **Lo que verás**:
   ```
   NAME   READY   UP-TO-DATE   AVAILABLE
   app1   1/1     1            1
   app2   3/3     3            3
   app3   1/1     1            1
   ```
   *Observación clave*: Fíjate cómo la columna `READY` de `app2` dice **3/3**. Esto confirma visualmente que le dimos la orden al *Deployment* de crear 3 réplicas idénticas (escalabilidad real).

3. **Ver todos los Pods**:
   ```bash
   kubectl get pods
   ```
   **Lo que verás**: Una lista con los nombres físicos reales (largos e irrepetibles como `app2-59787df8c8-hjjdm`) de tus pequeños mini-servidores. Verás que hay exactamente 1 de app1, 3 de app2 y 1 de app3 funcionando en aislamiento absoluto.

## Limpieza y Destrucción
Al igual que en p1, es importante apagar las máquinas para no consumir RAM en tu sistema al finalizar la práctica.
```bash
vagrant destroy -f
```
