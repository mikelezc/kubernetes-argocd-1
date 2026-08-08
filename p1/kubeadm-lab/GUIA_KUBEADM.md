# Montando un clúster con `kubeadm`, a mano y paso a paso

Material de estudio personal (no forma parte de la entrega del subject). El objetivo es construir **la misma arquitectura de `p1`** (1 control-plane + 1 worker) pero con las herramientas reales que usa el examen CKA, escribiendo cada comando tú mismo para entender qué hace — nada de scripts que lo hagan por ti.

Complementa a `../CKA_PRACTICE.md`: aquella guía asume que el clúster ya existe; esta te enseña a construirlo desde cero.

---

## 0. Qué vamos a construir

```
┌─────────────────────┐        ┌─────────────────────┐
│   cka-cp            │        │   cka-worker        │
│   192.168.56.120    │◄──────►│   192.168.56.121    │
│   kubeadm init      │        │   kubeadm join      │
│   (control-plane)   │        │   (worker)          │
└─────────────────────┘        └─────────────────────┘
```

Los mismos roles que en `p1` (Server ↔ control-plane, Worker ↔ agent), pero esta vez cada componente lo instalaremos y arrancaremos nosotros, uno por uno.

---

## 1. Levantar las dos VMs vacías

```bash
cd p1/kubeadm-lab
vagrant up
```

El `Vagrantfile` de este lab no tiene ningún provisioner — solo crea dos VMs con Debian 13 limpio. Fíjate en un detalle antes de seguir: el control-plane tiene **2 CPU / 2048MB**, no el mínimo de 1 CPU/512MB que usa `p1`. Es aposta: `kubeadm init` hace *preflight checks* obligatorios y rechaza arrancar con menos de 2 CPUs o menos de ~1700MB de RAM. K3s no comprueba nada de esto (es la primera diferencia real entre ambos).

Abriremos dos terminales, una por VM:

```bash
vagrant ssh cka-cp
vagrant ssh cka-worker
```

Todo lo de la **Sección 2** se repite igual en las dos VMs. Las secciones 3 (`init`) y 4 (Calico) son solo en `cka-cp`. La sección 5 (`join`) es solo en `cka-worker`.

*TIP: Podemos crear un alias para `kubectl`y que sea más fácil avanzar rápido de la siguiente manera: `alias k="kubectl"`.*

---

## 2. Preparar cada nodo

### 2.1 Desactivar swap

```bash
sudo swapoff -a
sudo sed -i '/swap/d' /etc/fstab   # para que no vuelva a activarse al reiniciar
```

**Por qué**: el kubelet necesita poder confiar en sus cálculos de memoria disponible para decidir cuándo expulsar Pods (`OOMKilled`, `Evicted`). Con swap activo, esos cálculos dejan de ser fiables, así que kubeadm lo exige desactivado por defecto.

### 2.2 Módulos de kernel y red

```bash
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system
```

**Por qué**: `br_netfilter` obliga a que el tráfico que pasa por el bridge de red de los contenedores también sea visible para `iptables` — sin esto, las reglas de red de Kubernetes (Services, NetworkPolicies) simplemente no verían ese tráfico. `overlay` es el driver de almacenamiento que usará `containerd`. `ip_forward=1` permite que el kernel reenvíe paquetes entre interfaces, necesario para que un nodo pueda enrutar tráfico hacia Pods que no están en su misma red.

Comprueba que quedó aplicado:
```bash
lsmod | grep br_netfilter
sysctl net.ipv4.ip_forward   # debe devolver 1
```

### 2.3 Instalar containerd (el runtime de contenedores)

Kubernetes ya no incluye un runtime propio (`dockershim` se eliminó en la 1.24) — hay que traer uno que hable el protocolo CRI. Usamos el mismo repo de Docker que ya conoces de `p3`:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian trixie stable" | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt-get update
sudo apt-get install -y containerd.io
```

**El paso que más gente se salta y luego le da problemas** — decirle a containerd que use el mismo *cgroup driver* (`systemd`) que usa el propio sistema operativo (Debian 13 usa `systemd` como init, así que su cgroup driver también es `systemd`):

```bash
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
```

**Por qué importa esto**: si el kubelet usa `systemd` como cgroup driver pero `containerd` usa `cgroupfs` (el valor por defecto sin este cambio), tendrás **dos gestores de cgroups compitiendo por el mismo recurso** — el síntoma típico es un nodo inestable o Pods que no arrancan bien bajo presión de memoria. Kubeadm desde 1.22 configura kubelet para `systemd` automáticamente, así que containerd tiene que casar con eso a mano.

Verifica que containerd está sano:
```bash
sudo systemctl status containerd --no-pager
sudo crictl info 2>/dev/null | head -20   # puede que aún no tengas crictl; si falla, sigue, se instala con kubeadm
```

### 2.4 Instalar `kubeadm`, `kubelet` y `kubectl`

Los instalamos desde el repositorio oficial de paquetes de Kubernetes, **pineados a la versión v1.35** — la misma que fijamos en `CKA_PRACTICE.md` para casar con el examen actual (repásalo si no lo hiciste: la versión cambia con el tiempo, comprueba cuál es la vigente antes de seguir).

```bash
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /' \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
```

Y esto es importante — evita que un `apt upgrade` cualquiera te cambie de versión de Kubernetes sin que te enteres (algo que en un clúster real de producción sería un incidente):

```bash
sudo apt-mark hold kubelet kubeadm kubectl
apt-mark showhold   # confirma que los 3 aparecen retenidos
```

Verifica versiones instaladas:
```bash
kubeadm version
kubelet --version
kubectl version --client
```

**Repite toda la Sección 2 en `cka-worker` antes de continuar.** El control-plane y el worker necesitan exactamente las mismas piezas (containerd + kubelet + kubeadm), aunque solo `kubeadm init` se ejecute en uno y `kubeadm join` en el otro.

---

**Las piezas básicas del exámen arrancarían desde aquí**

## 3. `kubeadm init` — arrancar el control-plane

Esto se ejecuta **solo en `cka-cp`**.

```bash
sudo kubeadm init \
  --apiserver-advertise-address=192.168.56.120 \
  --pod-network-cidr=192.168.0.0/16 \
  --kubernetes-version=v1.35.7
```

Tarda entre 1 y 3 minutos. Mientras corre, esto es lo que está pasando por debajo (léelo antes de que termine):

1. Genera una **CA propia** para el clúster y, a partir de ella, todos los certificados TLS que necesitan `etcd`, el `apiserver` y el resto de componentes para hablar entre sí de forma segura.
2. Escribe los **manifiestos estáticos** de `etcd`, `kube-apiserver`, `kube-scheduler` y `kube-controller-manager` en `/etc/kubernetes/manifests/` — el kubelet vigila esa carpeta y arranca cualquier Pod que encuentre ahí, sin pasar por el scheduler (por eso se llaman *static pods*, y por eso el clúster puede arrancar sin tener aún un `kube-scheduler` funcionando: el kubelet los levanta directamente).
3. Genera `/etc/kubernetes/admin.conf`, el kubeconfig con permisos de administrador.
4. Despliega `CoreDNS` y `kube-proxy` como Deployment/DaemonSet normales (estos ya no son estáticos, van vía el apiserver).
5. Al final, imprime el comando exacto de `kubeadm join` que necesitarás para el worker — **cópialo a un fichero de texto ahora**, expira a las 24h.

### Parada obligatoria: mira lo que se acaba de crear

```bash
sudo ls /etc/kubernetes/manifests/
sudo cat /etc/kubernetes/manifests/etcd.yaml
```

Compáralo mentalmente con K3s: en `p1`, ninguno de estos ficheros existe — todo ese trabajo lo hace un solo binario (`k3s server`) por debajo, sin dejar rastro en el filesystem como Pod. Aquí, en cambio, `etcd`, el `apiserver`, el `scheduler` y el `controller-manager` son Pods reales que vas a poder hacer `kubectl describe`/`kubectl logs` sobre ellos, exactamente como en el examen.

Configura `kubectl` para tu usuario:
```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

Ahora comprueba el estado:
```bash
kubectl get nodes
kubectl get pods -n kube-system -o wide
```

El nodo aparece **`NotReady`**, y si te fijas, `coredns` está en `Pending`. Averigua por qué tú mismo antes de seguir:
```bash
kubectl describe node cka-cp | grep -A5 Conditions
```
Verás algo como `KubeletNotReady ... container runtime network not ready: cni config uninitialized`. Es literal: **todavía no hay ningún CNI instalado**, así que el kubelet no puede dar red a ningún Pod. Esto lo resolvemos en el siguiente paso.

---

## 4. Instalar el CNI (Calico)

Un CNI (*Container Network Interface*) es el plugin que le da IP a cada Pod y conecta esas IPs entre nodos. Kubernetes no trae ninguno por defecto — a propósito, para que elijas el que más te convenga. Usamos **Calico** en vez de Flannel (que verías en muchos tutoriales) porque Calico sí soporta `NetworkPolicy` de verdad, y vas a querer practicar eso para el examen.

```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.1/manifests/calico.yaml
```

(Comprueba si `v3.32.1` sigue siendo la última estable en https://github.com/projectcalico/calico/releases antes de usarla — igual que con la versión de Kubernetes, esto avanza con el tiempo.)

Esto crea varios Pods nuevos en `kube-system` (`calico-node` como DaemonSet, `calico-kube-controllers`). Espera y comprueba:

```bash
kubectl get pods -n kube-system -w    # Ctrl+C cuando todos estén Running
kubectl get nodes                     # cka-cp debería pasar a Ready
```

Si `coredns` sigue sin arrancar después de un par de minutos, revisa sus logs (`kubectl logs -n kube-system -l k8s-app=kube-dns`) — normalmente se resuelve solo en cuanto Calico termina de inicializar.

---

## 5. `kubeadm join` — unir el worker

Esto se ejecuta **solo en `cka-worker`**, con `sudo`, usando el comando que te imprimió `kubeadm init` en el paso 3. Tiene esta pinta (los valores reales serán distintos):

```bash
sudo kubeadm join 192.168.56.120:6443 \
  --token abcdef.0123456789abcdef \
  --discovery-token-ca-cert-hash sha256:1234...
```

**Qué hace exactamente**: el `token` es una credencial temporal (24h) que permite al worker autenticarse ante el apiserver sin necesitar ya certificados propios; el `discovery-token-ca-cert-hash` es el hash de la CA del clúster, para que el worker pueda verificar que está hablando con el control-plane legítimo y no con un impostor haciéndose pasar por él (protección contra ataques *man-in-the-middle* en el primer contacto).

Si ya pasaron más de 24h y el token expiró, genera uno nuevo desde `cka-cp`:
```bash
kubeadm token create --print-join-command
```

Verifica desde `cka-cp`:
```bash
kubectl get nodes -o wide
```

Deberían aparecer `cka-cp` (`control-plane`) y `cka-worker` (sin *ROLES*, exactamente como viste en `p1` con K3s) — ambos `Ready`.

---

## 6. Ya tienes el clúster — compáralo con K3s

```bash
kubectl get pods -A -o wide
```

Fíjate en las diferencias reales frente a lo que documentamos en `p1/README.md` para K3s:

| | K3s (`p1`) | kubeadm (este lab) |
|---|---|---|
| `etcd` | Embebido en `sqlite`, sin Pod visible | Pod real `etcd-cka-cp` en `kube-system` |
| `kube-apiserver` | Proceso interno de `k3s server` | Pod real `kube-apiserver-cka-cp` |
| Ingress | Traefik instalado de serie | No hay ninguno — lo instalarías tú (así viviste en `p2` con Traefik, pero ahí lo trajo K3s solo) |
| Storage | `local-path-provisioner` de serie | Sin StorageClass — un PVC se queda `Pending` hasta que definas una |
| `metrics-server` | Instalado de serie | No existe — `kubectl top` fallaría hasta que lo instales |

Todo lo que practicaste en `CKA_PRACTICE.md` (Pods, Deployments, Services, RBAC, ConfigMaps...) funciona exactamente igual aquí — es la misma API. Lo único que cambia es la capa de infraestructura por debajo, que ahora sí puedes tocar directamente.

---

## 7. Practicar `etcd` de verdad (esto no se puede hacer en K3s)

Averigua qué versión de `etcd` estás corriendo (la necesitas para bajar el `etcdctl` correcto):
```bash
kubectl -n kube-system get pod etcd-cka-cp -o jsonpath='{.spec.containers[0].image}'
```

Descarga el binario de `etcdctl` (ajusta `ETCD_VER` y la arquitectura a lo que hayas visto arriba):
```bash
ETCD_VER=v3.6.5
ARCH=$(dpkg --print-architecture | sed 's/amd64/amd64/; s/arm64/arm64/')
curl -L "https://github.com/etcd-io/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-${ARCH}.tar.gz" -o /tmp/etcd.tar.gz
tar xzf /tmp/etcd.tar.gz -C /tmp
sudo mv /tmp/etcd-${ETCD_VER}-linux-${ARCH}/etcdctl /usr/local/bin/
```

Haz el backup — este comando (con estas mismas rutas de certificados) es prácticamente calcado a como se pregunta en el examen real:
```bash
sudo ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /tmp/etcd-backup.db

sudo ETCDCTL_API=3 etcdctl --write-out=table snapshot status /tmp/etcd-backup.db
```

Para practicar la restauración de verdad (opcional, más avanzado): crea algo con `kubectl` (un namespace de prueba, por ejemplo), luego borra ese namespace, y restaura el snapshot siguiendo la [documentación oficial de recuperación de desastres de etcd](https://etcd.io/docs/latest/op-guide/recovery/) — el propio proceso de parar el `kube-apiserver`, restaurar los datos y reiniciar todo es, en sí mismo, uno de los ejercicios más largos que puede caer en el examen.

---

## 8. Limpiar

```bash
cd p1/kubeadm-lab
vagrant halt          # apaga sin borrar, para retomarlo otro día
# o bien:
vagrant destroy -f    # borra las VMs por completo
```

---

## 9. Siguientes pasos

- Repite el ejercicio de `cordon`/`drain`/`taint` de `CKA_PRACTICE.md` aquí — ahora con un `kube-scheduler` real detrás, en vez del interno de K3s.
- Prueba a romper el clúster a propósito: para `containerd` en el worker (`sudo systemctl stop containerd`) y diagnostica con `kubectl describe node` qué le pasa, sin mirar antes qué hiciste.
- Cuando te sientas cómodo con 1 control-plane, el siguiente reto real es un control-plane en alta disponibilidad (3 nodos) — pero eso ya no entra en el CKA, es material de CKA... y de vida real.
