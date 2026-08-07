# Usando p1 como laboratorio de práctica para el CKA

Este documento es **material de estudio personal**, no parte de la entrega del subject (para eso está `README.md`). La idea es reutilizar el clúster de 2 nodos que ya tienes montado en `p1/` para practicar de cara al examen **Certified Kubernetes Administrator (CKA)**.

---

## 1. Por qué p1 es un buen punto de partida (y qué le falta)

Ya tienes: 2 nodos reales (no todo-en-uno), `kubectl` funcionando, red entre nodos, y systemd/apt (Debian 13) — la misma base que usa `kubeadm`.

Te falta (y es importante saberlo antes de fiarte 100% de este entorno):

- **K3s no es exactamente lo que usa el examen.** El CKA se examina sobre un clúster montado con `kubeadm`. K3s te esconde cosas que en el examen sí tienes que manejar a mano: no hay `kubeadm init/join`, usa `sqlite` en vez de `etcd` real (salvo en modo HA), y trae de serie Traefik, `local-path-provisioner` y `metrics-server`, que en un clúster de `kubeadm` no existen hasta que tú los instalas.
- **Lo que SÍ es idéntico**: la API de Kubernetes, `kubectl`, los objetos (Pods, Deployments, RBAC, NetworkPolicies...) y su comportamiento. Todo lo que practiques a nivel de "objetos y comandos" aquí es 100% transferible.

Este documento se centra en aprovechar lo que ya tienes (la API, `kubectl`, los objetos) y te avisa explícitamente cuando algo es "solo de K3s" y no se comportaría igual en el examen real.

---

## 2. Igualar la versión de Kubernetes a la del examen

El CKA se examina sobre la versión estable de Kubernetes vigente en el momento del examen (Linux Foundation actualiza el entorno del examen entre 4 y 8 semanas después de cada release menor de Kubernetes). **Esta versión cambia con el tiempo** — antes de fiarte del número que doy aquí, compruébalo tú mismo:

```bash
# Página oficial con las instrucciones y FAQ del CKA (ahí confirman la versión vigente):
# https://docs.linuxfoundation.org/tc-docs/certification/faq-cka-ckad-cks

# Canales de K3s disponibles (cada uno mapea 1:1 con una versión de Kubernetes):
curl -s https://update.k3s.io/v1-release/channels | python3 -m json.tool
```

En el momento de escribir esto, la versión de referencia del examen es **Kubernetes v1.35**, y el canal de K3s equivalente es:

```
v1.35 -> v1.35.7+k3s1
```

### Cómo instalar K3s con esa versión exacta en vez de "stable"

Tanto `scripts/server.sh` como `scripts/worker.sh` instalan K3s así:

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server ..." sh -
```

Sin más variables, el instalador usa el canal `stable` (la versión más reciente de K3s, que puede ir por delante de lo que usa el examen). Para fijar la versión exacta, añade `INSTALL_K3S_VERSION` **antes** de `INSTALL_K3S_EXEC` en la misma línea del `curl`:

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.35.7+k3s1" INSTALL_K3S_EXEC="server \
  --write-kubeconfig-mode 644 \
  ...
```

Tienes que poner la **misma versión en `server.sh` y en `worker.sh`** — un clúster con nodos en versiones de Kubernetes distintas es un estado no soportado (aunque K3s no te lo impida).

Después de cambiarlo, recrea el clúster desde cero (un simple `vagrant provision` no reinstala K3s si ya está instalado):

```bash
vagrant destroy -f
vagrant up
```

Verifica la versión real que quedó corriendo:

```bash
vagrant ssh mlezcanoS -c "kubectl get nodes -o wide"
# La columna VERSION debe mostrar v1.35.7+k3s1 en ambos nodos
```

---

## 3. Tour guiado: qué mirar en el clúster y con qué comando

Todo esto se ejecuta desde el Server (`vagrant ssh mlezcanoS`), que es donde vive el kubeconfig con permisos de administrador.

### 3.1 Lo primero: cómo explorar sin memorizar nada

```bash
kubectl api-resources                     # Todo lo que existe como "tipo de objeto" en este clúster
kubectl explain pod.spec                  # Documentación oficial de cualquier campo, sin salir de la terminal
kubectl explain pod.spec.containers.resources.limits
kubectl get pods -n kube-system -o yaml   # Ver la definición completa de un objeto real, no solo el resumen
kubectl config get-contexts               # Qué cluster/usuario está usando kubectl ahora mismo
```

`kubectl explain` es probablemente el comando que más tiempo te va a ahorrar en el examen real — no hay acceso a internet, solo a la documentación oficial embebida y a `kubectl explain`.

### 3.2 Nodos y arquitectura del clúster

```bash
kubectl get nodes -o wide
kubectl describe node mlezcanoS
kubectl get pods -n kube-system -o wide   # Qué corre en el control-plane
```

En un clúster de `kubeadm` verías aquí pods estáticos como `kube-apiserver-*`, `etcd-*`, `kube-scheduler-*`, `kube-controller-manager-*` (gestionados directamente por el kubelet, no por el scheduler). **K3s los compila dentro de un solo binario/proceso** (`k3s server`), así que no verás esos pods — es la diferencia más grande frente al examen real. Compruébalo:

```bash
ps aux | grep k3s          # Un solo proceso k3s server haciendo de apiserver+scheduler+controller-manager+etcd
sudo cat /etc/rancher/k3s/k3s.yaml   # El kubeconfig de admin, equivalente a /etc/kubernetes/admin.conf en kubeadm
```

### 3.3 Namespaces y Pods

```bash
kubectl get ns
kubectl create namespace practica
kubectl run nginx-test --image=nginx:alpine -n practica
kubectl get pods -n practica -o wide
kubectl describe pod nginx-test -n practica
kubectl logs nginx-test -n practica
kubectl exec -it nginx-test -n practica -- sh
kubectl delete pod nginx-test -n practica
```

### 3.4 Workloads con control de réplicas

```bash
kubectl create deployment web --image=nginx:alpine --replicas=3 -n practica
kubectl get deployment,replicaset,pod -n practica
kubectl scale deployment web --replicas=5 -n practica
kubectl rollout status deployment/web -n practica
kubectl rollout history deployment/web -n practica
kubectl set image deployment/web nginx=nginx:1.27-alpine -n practica
kubectl rollout undo deployment/web -n practica       # Vuelve a la versión anterior
```

Otros tipos de carga de trabajo que merece la pena tener a mano (aparecen en el examen):

```bash
kubectl create job mi-job --image=busybox -n practica -- echo "hola desde un Job"
kubectl create cronjob mi-cron --image=busybox --schedule="*/2 * * * *" -n practica -- echo "tick"
# DaemonSet no tiene comando imperativo; hace falta un YAML (busca "kind: DaemonSet" en la doc de kubectl explain)
```

### 3.5 Servicios y red

```bash
kubectl expose deployment web --port=80 -n practica          # Crea un Service ClusterIP
kubectl get svc,endpoints -n practica
kubectl run curl-test --rm -it --image=curlimages/curl -n practica -- curl web.practica.svc.cluster.local
```

CoreDNS es lo que resuelve `web.practica.svc.cluster.local` — es el mismo componente que ya viste en `p2` con el Ingress. Para forzar `NodePort` en vez de `ClusterIP`:

```bash
kubectl expose deployment web --port=80 --type=NodePort -n practica
kubectl get svc web -n practica     # Mira el puerto asignado en el rango 30000-32767
```

`LoadBalancer` en K3s lo resuelve el propio K3s con su balanceador ligero (`svclb-*`, ya lo vimos en `p2`) — en el examen real (sin cloud provider) un `type: LoadBalancer` se queda en `Pending` para siempre, es importante saber reconocer esa diferencia.

### 3.6 ConfigMaps y Secrets

```bash
kubectl create configmap mi-config --from-literal=ENTORNO=practica -n practica
kubectl create secret generic mi-secreto --from-literal=password=1234 -n practica
kubectl get configmap,secret -n practica
kubectl get secret mi-secreto -n practica -o jsonpath='{.data.password}' | base64 -d
```

Practica montarlos en un pod como variable de entorno y como volumen — es de lo más preguntado en el examen (`kubectl explain pod.spec.containers.envFrom`, `kubectl explain pod.spec.volumes.configMap`).

### 3.7 Almacenamiento

```bash
kubectl get storageclass          # K3s trae "local-path" por defecto (Server -> local-path-provisioner)
kubectl get pv,pvc -A
```

Crea un PVC de prueba y verifica que K3s le asigna automáticamente un PV (a diferencia de un clúster `kubeadm` sin StorageClass, donde un PVC se queda `Pending` hasta que creas el PV a mano — practica ambos flujos).

### 3.8 RBAC (uno de los temas que más se falla en el examen)

```bash
kubectl create serviceaccount mi-sa -n practica
kubectl create role lector-pods --verb=get,list,watch --resource=pods -n practica
kubectl create rolebinding lector-pods-binding --role=lector-pods --serviceaccount=practica:mi-sa -n practica

# La forma correcta de verificar permisos sin tener que "probar y ver si falla":
kubectl auth can-i list pods --as=system:serviceaccount:practica:mi-sa -n practica     # yes
kubectl auth can-i delete pods --as=system:serviceaccount:practica:mi-sa -n practica   # no
kubectl auth can-i list pods --as=system:serviceaccount:practica:mi-sa -A              # no (el Role es solo del namespace)
```

Un `ClusterRole` + `ClusterRoleBinding` es igual pero sin `-n` — pruébalo y compara el resultado del último comando.

### 3.9 Scheduling avanzado

```bash
kubectl taint node mlezcanoSW dedicado=cka:NoSchedule
kubectl run test-toleration --image=nginx:alpine -n practica    # Se queda Pending, revisa por qué:
kubectl describe pod test-toleration -n practica | grep -A5 Events
kubectl taint node mlezcanoSW dedicado=cka:NoSchedule-           # Quita el taint
```

Practica también `resources.requests/limits` y qué pasa cuando un Pod pide más memoria de la que tiene el nodo disponible (recuerda: 512MB por VM, así que aquí es fácil provocarlo a propósito).

### 3.10 Administración de nodos

```bash
kubectl cordon mlezcanoSW              # Marca el nodo como no-programable (nuevos pods no van ahí)
kubectl drain mlezcanoSW --ignore-daemonsets --delete-emptydir-data   # Desaloja los pods existentes
kubectl get nodes                      # SchedulingDisabled
kubectl uncordon mlezcanoSW            # Lo vuelve a poner disponible
```

### 3.11 "etcd" en este clúster — la pieza que menos se parece al examen

K3s por defecto usa `sqlite` en vez de `etcd` (por eso el `README.md` del subject ya lo menciona). El backup/restore de `etcd` es un tema que **siempre** sale en el examen real, y aquí no lo puedes practicar tal cual. Dos opciones:

- **Snapshot de K3s** (no es lo mismo que `etcdctl`, pero el concepto — respaldar y restaurar el estado del clúster — es equivalente):
  ```bash
  sudo k3s etcd-snapshot save          # K3s soporta esto incluso en modo sqlite standalone... 
  # ⚠️ en la práctica, con un solo server (no HA), K3s usa sqlite y esto puede no aplicar igual
  ```
- **La forma correcta de practicar `etcdctl` de verdad**: hazlo en la migración a `kubeadm` que comentamos — ahí sí tendrás un `etcd` real corriendo como pod estático, y `etcdctl snapshot save/restore` funcionará exactamente igual que en el examen.

### 3.12 Troubleshooting (30% del examen — el bloque más grande)

```bash
kubectl get events -A --sort-by=.lastTimestamp    # Qué ha pasado últimamente en todo el clúster
kubectl describe pod <pod> -n <ns>                # Casi siempre la primera pista
kubectl logs <pod> -n <ns> --previous             # Logs del contenedor anterior si reinició
sudo journalctl -u k3s -f                         # Logs del propio control-plane (equivalente a mirar kube-apiserver)
sudo journalctl -u k3s-agent -f                    # Lo mismo pero en el Worker (kubelet)
kubectl top nodes ; kubectl top pods -A            # Requiere metrics-server (K3s lo trae de serie)
```

Ejercicio recomendado: rompe algo a propósito (para bien) — por ejemplo, edita `/etc/rancher/k3s/k3s.yaml` con una IP incorrecta y observa el error de `kubectl`, o mata el proceso `k3s` en el Worker (`sudo systemctl stop k3s-agent`) y practica diagnosticarlo con `kubectl get nodes` (verás el nodo en `NotReady` tras un rato) antes de arreglarlo.

---

## 4. Progresión sugerida, ligada a los dominios reales del examen

| Dominio del CKA | % examen | Qué practicar aquí |
|---|---|---|
| Cluster Architecture, Installation & Configuration | 25% | Apartados 2, 3.2, 3.10 — y sobre todo, migrar este mismo `p1` a `kubeadm` (ver sección 5) |
| Services & Networking | 20% | Apartado 3.5, y añade `NetworkPolicy` (necesitarás sustituir Flannel por Calico, Flannel no las aplica) |
| Workloads & Scheduling | 15% | Apartados 3.3, 3.4, 3.9 |
| Storage | 10% | Apartado 3.7 |
| Troubleshooting | 30% | Apartado 3.12 — el que más tiempo merece, por peso y porque es transversal a todo lo anterior |

---

## 5. Siguiente paso natural: lo mismo pero con `kubeadm`

Todo lo de este documento es 100% válido en un clúster de `kubeadm` sin cambiar ni un comando — la única diferencia es cómo se monta el clúster (secciones 3.2 y 3.11 son las que más cambian). Cuando quieras dar el salto, reutiliza estas mismas VMs de Vagrant cambiando el provisioning de K3s por `kubeadm init`/`kubeadm join`, e instala tú mismo un CNI real (Calico, para poder practicar `NetworkPolicy` de verdad).

No lo incluyo en detalle aquí porque merece su propio documento — pídemelo cuando quieras dar ese paso.
