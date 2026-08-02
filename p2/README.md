# Parte 2: K3s y 3 Aplicaciones Web Básicas


A diferencia de la Parte 1 (donde desplegamos un clúster multi-nodo con Server y Worker), los requerimientos de la Parte 2 especifican la creación de **un único nodo maestro (`mlezcanoS`)**:

- **IP del servidor**: `192.168.56.110` (red privada).
- **Nombre de la VM**: `mlezcanoS` (siguiendo la nomenclatura del *Subject*: `<login>S`).
- **Rol del nodo**: Servidor K3s único (Control Plane y ejecutor de Pods).

---

## Conceptos Clave de Kubernetes

En la Parte 1 levantamos la infraestructura base (los Nodos). En esta Parte 2 damos el salto a desplegar aplicaciones dentro del clúster conectando los objetos nativos de Kubernetes en diferentes capas de abstracción:

1. **ConfigMap**: Permite desacoplar la configuración del código del contenedor. En nuestro laboratorio, lo usamos para inyectar directamente el HTML plano de las webs (`App1`, `App2` y `App3`), evitando tener que construir y publicar imágenes de Docker personalizadas para cambios simples.

2. **Deployment**: Define el estado deseado de la aplicación. Le indica a Kubernetes qué contenedor usar y cuántas copias (*réplicas*) mantener activas. Si un Pod falla, Kubernetes lo recrea automáticamente. Para cumplir con los requisitos del *Subject*, el Deployment de **`App2` cuenta con 3 réplicas** paralelas.

3. **Service (ClusterIP)**: Proporciona un punto de acceso estable a la aplicación. Dado que los Pods son efímeros y cambian de IP al reiniciarse, el Service le asigna una IP virtual fija, un nombre DNS interno (ej. `app1-service.default.svc`) y **balancea el tráfico internamente** entre todas las réplicas del Deployment.

4. **Ingress (Traefik)**: Es el punto de entrada unificado al clúster (Proxy Inverso y balanceador externo). Escucha el tráfico que llega al nodo y, analizando el dominio o la cabecera `Host` de la petición HTTP, encamina la solicitud hacia el `Service` correspondiente (`App1`, `App2` o `App3`). K3s utiliza **Traefik** como su controlador de Ingress por defecto.

---

## Requisitos de la Práctica

![Arquitectura](images/architecture.png)

- Una única máquina `mlezcanoS` (`192.168.56.110`) actuando de Server.
- Tres aplicaciones web corriendo.
- Ingress configurado para:
  - `app1.com` -> Dirige a la Aplicación 1
  - `app2.com` -> Dirige a la Aplicación 2 (3 réplicas)
  - Cualquier otro host -> Dirige a la Aplicación 3 por defecto.

---

## Checklist de verificación del Subject

1. **Confirmamos que el `Vagrantfile` está presente y solo define 1 VM**

   - Comprobamos que el fichero `p2/Vagrantfile` existe.
   - Abrimos su contenido y verificamos que solo hay `config.vm.define` para una máquina llamada `mlezcanoS`(requerido así por el subject).

---

2. **Comprobamos la distribución usada**

   - El enunciado permite usar la versión estable más reciente de la distro de tu elección. Podemos comprobar de que el `Vagrantfile` usa la `box` requerida `bento/ubuntu-26.04` (abril del 26).

---

3. **Verificamos la interfaz de red `eth1` y su IP**

   - Ejecutando `vagrant status` esta vez podemos ver la única VM requerida por el subject `mlezcanoS`.
   - Entramos al Server con `vagrant ssh mlezcanoS` (ssh sin contraseña como requiere el subject).
   - Ejecutamos `ip addr show eth1` y comprobamos que la IP es `192.168.56.110` como requiere el subject.

---

4. **Verificamos el hostname**

   - Dentro de la VM ejecutamos `hostname` y comprobamos que devuelve `mlezcanoS`.

---

5. **Comprobar K3s y `kubectl`**

	- Desde la VM ejecutamos `kubectl cluster-info` para ver el cluster.
	- Desde la VM ejecutamos `kubectl get nodes -o wide` para ver los nodes, podemos verificar que aparece `mlezcanoS` (controller) con estado `Ready`.
	- Desde la VM ejecutamos `kubectl get pods -n kube-system` para listar los Pods internos de la infraestructura de K3s (no los pods de la app).

	*- Son las mismas comprobaciones que hemos hecho en /p1*

---

6. **Como inspeccionar deployments, réplicas y pods**

   - **Comprobamos el estado general:** Ejecutamos `kubectl get deploy` y verificamos que la columna `READY` marque `1/1` para `app1` y `app3` (una réplica por app), y **`3/3` para `app2`** (3 réplicas).

   - **Confirmamos los Pods individuales:** Con `kubectl get pods`, comprobamos la lista activa: 1 Pod de `app1`, 3 Pods de `app2` y 1 Pod de `app3`. Con `kubectl get pods -o wide` podemos ver como todos están dentro del mismo nodo, la IP etc...

   - **Diagnóstico en caso de error:** Si `app2` no alcanzara las 3 réplicas listas, podemos inspeccionar los eventos del recurso para identificar el problema ejecutando:
     ```bash
     kubectl describe deployment app2
     ```

	- **Inspección de los logs de un pod:** Si ejecutamos `kubectl logs -f <NAME>` donde `NAME` ponemos el nombre del pod que queremos inspeccionar, podemos ver sus logs. El `NAME` lo obtenemos al hacer `kubectl get pods` (algo como "app1-84bc549d9d-8wvkq"). 

---

7. **Verificación del Ingress y enrutamiento por cabecera `Host`**

   - **Comprobar la regla de Ingress:** Ejecutamos `kubectl get ingress` en la VM para confirmar que el recurso está activo y asociado a la IP `192.168.56.110`.
   
   - **Configuración en el Anfitrión (Host):** Para poder probar la navegación directamente desde nuestro navegador web, añadimos las entradas DNS en el archivo `/etc/hosts` de nuestra máquina física:
     ```text
     192.168.56.110  app1.com app2.com app3.com
     ```

	- **Navegación con `app1.com`/`app2.com`/`app3.com` sin editar `/etc/hosts` (recomendado):** Si no tenemos permisos para modificar `/etc/hosts` (ej. en los equipos del campus), podemos lanzar Chrome con una regla de resolución de nombres solo para esa sesión del navegador, sin tocar ficheros del sistema ni instalar nada:

	  ```bash
	  open -a "Google Chrome" --args --host-resolver-rules="MAP app1.com 192.168.56.110, MAP app2.com 192.168.56.110, MAP app3.com 192.168.56.110"
	  ```

	  Debemos cerrar antes todas las ventanas de Chrome para que el flag se aplique. Con esto puedes navegar directamente a `http://app1.com`, `http://app2.com` y `http://app3.com`, y el propio navegador enviará el `Host` correcto sin necesidad de ninguna extensión ni regla adicional.

	- **Alternativa mediante Header Editor (si no podemos lanzar Chrome con flags):** Instalaremos la extensión **Header Editor** en el navegador y crearemos una regla nueva con esta configuración:

	  - **Tipo de regla:** `Modify request header`.
	  - **Match type:** marca `Dominio` e introduce `192.168.56.110`.
	  - **Execution → Request headers:** añade una entrada `host` → `app1.com` (o `app2.com` para la otra app).
	  - Guardamos la regla y comprobamos que queda **activada** (interruptor en el listado principal de reglas).
	  - Navegamos directamente a `http://192.168.56.110`; Traefik interpretará la cabecera `Host` inyectada e mostrará la web correspondiente.

	  A tener en cuenta:
	  - Como las reglas de `app1.com` y `app2.com` apuntan al mismo dominio de destino (`192.168.56.110`), **no pueden estar activas a la vez** (se pisarían entre sí). Crea una regla por app y activa solo la que quieras probar en cada momento.
	  - **Caché del navegador:** si tras cambiar de regla activa seguimos viendo la app anterior, fuerza una recarga con `Control+Shift+R` (o desactivaremos la caché desde las DevTools → pestaña Network), ya que el navegador puede servir la respuesta cacheada sin llegar a aplicar la nueva cabecera.

   - **Validación del enrutamiento vía CLI:** Probamos el comportamiento del Ingress enviando peticiones con la cabecera `Host` directamente contra la IP del servidor. Cada dominio debe responder con el contenido HTML de su respectiva aplicación (`App1`, `App2` o `App3`).

     ```bash
     curl -H "Host: app1.com" http://192.168.56.110
     curl -H "Host: app2.com" http://192.168.56.110
     curl -H "Host: app3.com" http://192.168.56.110
     ```
   - **Verificación del balanceo de carga en App2:** Para comprobar que Traefik y el Service distribuyen el tráfico entre las 3 réplicas del Deployment, podemos ejecutar el siguiente bucle desde la terminal anfitriona:

     ```bash
     for i in {1..6}; do curl -s -H "Host: app2.com" [http://192.168.56.110](http://192.168.56.110) | grep -o 'app2-[a-z0-9]\{10\}-[a-z0-9]\{5\}'; done
     ```

     Este comando realiza 6 peticiones consecutivas extrayendo el nombre exacto del Pod que responde. Al comparar los sufijos aleatorios generados por Kubernetes (ej. `app2-575f644dc8-8xt8n`, `...-fzrtn`, `...-rxjk2`), se confirma visualmente que las solicitudes son atendidas por diferentes réplicas de forma balanceada.

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
