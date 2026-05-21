# Parte 3: K3d y Argo CD (Concepto GitOps)

## Conceptos Clave 

El objetivo de la Parte 3 es abandonar el despliegue manual (donde alguien hace un `kubectl apply -f` o levanta los archivos a mano) y abrazar la automatización extrema y la metodología **GitOps**.

1. **K3d (K3s in Docker)**: Es una herramienta que nos permite levantar un clúster K3s completo dentro de contenedores Docker. Es decir, Docker es el único requisito. Ahorra muchísimos recursos, ya que levanta el server y los workers virtualizados en la misma máquina mediante contenedores.

2. **Argo CD y GitOps**: GitOps significa que "El repositorio de Git es la única fuente de verdad". Instalaremos **Argo CD** en nuestro clúster. Argo CD es un bot vigilante que estará mirando TODO EL RATO a nuestro repositorio público de GitHub. Si en Github escribimos que queremos que `app1` tenga la versión `v2`, Argo CD lo detecta y lo cambia automáticamente en nuestro K3s **evitamos intervenir manualmente para hacer una pull**

## Requisitos Previos

Antes de levantar la máquina, conectamos nuestro GitHub personal:

1. **Creamos un Repo Público en GitHub**:
   - Nómbralo con tu nombre de usuario de 42, por ejemplo: `miguel-iot-argocd`.
   - Entra en la carpeta `app-para-tu-github/` de este proyecto, copia el archivo `deployment.yaml` de ahí y súbelo a tu nuevo repo.
   
2. **Conectamos el Repo en tus archivos locales de P3**:
   - Entra en `confs/argocd.yaml`.
   - Busca donde dice `repoURL: ...` y cambia eso por la URL real de tu repositorio (por ejemplo: `https://github.com/TUGITHUB/miguel-iot-argocd.git`).

## ¿Cómo levantar todo?
Aunque el subject dice que P3 no necesita Vagrant y que todo se ejecuta en consola sobre Linux, hemos **demostrado un extra de sofisticación** incorporando un Vagrantfile automatizado también aquí. 

Te hemos preparado un Vagrantfile para que tu Mac (o el Linux de la escuela gracias al soporte Multi-Arquitectura) te proporcione una VM perfecta de 3GB de RAM.

1. Estando en P3, lanza el entorno:
   ```bash
   vagrant up
   ```
2. El propio archivo automatizado lanzará el script `scripts/install.sh`, el cual:
   - Instalará Docker y K3d.
   - Creará un clúster en Docker llamado `iot-cluster` vinculando los puertos locales 8888.
   - Desplegará Argo CD.
   - Desplegará tu ruta apuntando a tu Repo.

## 🎯 Probar la "Magia" GitOps
Abre tu navegador de internet (fuera de la VM) y ve a:
👉 `http://localhost:8888`
Ahí debería verse ejecutándose la versión inicial de la Web (`wil42/playground:v1`, por ejemplo).

**Ahora viene el examen (GitOps):**
1. Ve a la página de **Github** (a tu navegador de internet, en tu nube). 
2. Edita manualmente el archivo en GitHub (`deployment.yaml`).
3. Cambia `wil42/playground:v1` por `wil42/playground:v2`.
4. Guárdalo (haz commit).
5. Vuelve a mirar a `http://localhost:8888` pasados 90-120 segundos. ¡Verás cómo la página ha mutado a v2 totalmente en automático! 🤖

*(Si quieres ver cómo está el robot ArgoCD trabajando por detrás, pregúntaselo entrando a tu clúster mediante `vagrant ssh mlezcanoS` y explorando sus logs).*

## 🧹 Limpieza y Destrucción

### Destrucción Simple (Normal)
Al igual que en p1 y p2:
```bash
vagrant destroy -f
```

### Limpieza Exhaustiva (Si la VM se cuelga o queda datos colgados)
Si `vagrant up` falla repetidamente, usa este procedimiento completo:

```bash
# 1. Destruir la máquina
vagrant destroy -f

# 2. Limpiar estado de Vagrant
rm -rf .vagrant/

# 3. Verificar y limpiar procesos VMware colgados en tu Mac
ps aux | grep -E "(vmware|vagrant)" | grep -v grep

# 4. Si ves procesos viejos, matarlos (opcional, sólo si es necesario)
sudo pkill -f vmware-usbarbitrator || true
sudo pkill -f vagrant-vmware || true

# 5. Relanzar
vagrant up
```

## 🔍 Diagnósticos: Verificar Conectividad DNS del Cluster

Si Argo CD muestra error `ComparisonError` tipo `lookup github.com on 10.43.0.10:53: no such host`, significa que CoreDNS dentro del cluster no puede resolver github.com.

### Comandos de diagnóstico (ejecuta en orden):

```bash
# 1. Acceder a la VM
vagrant ssh mlezcanoS

# Ya dentro de la VM, ejecuta esto:

# 2. Comprobar DNS desde la VM (debería funcionar)
nslookup github.com

# 3. Ver si resolv.conf está bien
cat /etc/resolv.conf

# 4. Verificar que CoreDNS está corriendo
kubectl get pods -n kube-system | grep coredns

# 5. Ver logs de CoreDNS
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=20 || true

# 6. Crear un pod temporal DENTRO del cluster y probar DNS desde ahí
kubectl run -it --rm --restart=Never --image=alpine dns-test -- sh

# Una vez dentro del pod alpine (verás prompt "/ #"):
nslookup github.com
ping -c 2 github.com
curl -I https://github.com
exit
```

### Si falla en el paso 6 (DNS desde dentro del cluster):

```bash
# Reiniciar CoreDNS
kubectl rollout restart deployment/coredns -n kube-system
kubectl rollout status deployment/coredns -n kube-system --timeout=60s
sleep 30

# Repetir paso 6 para verificar que funciona

# Luego, en Argo CD UI, pulsa REFRESH para que reintente leer el repo
# O fuerza un pod nuevo del repo-server:
kubectl -n argocd delete pod -l app.kubernetes.io/name=argocd-repo-server
```
