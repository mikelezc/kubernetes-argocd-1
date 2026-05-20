# Solución rápida: k3d / kubectl en la VM (bonus)

Sigue estos pasos dentro de la VM (`vagrant ssh`) en orden. Copia/pega cada bloque y pega las salidas aquí si algo falla.

## 1) Aplicar pertenencia al grupo `docker`
```bash
sudo usermod -aG docker vagrant
# Aplica sin cerrar sesión (o vuelve a reconectar):
newgrp docker || (exit && vagrant ssh miguelS)
```

## 2) Comprobar que Docker y k3d funcionan
```bash
k3d cluster list
docker ps -a
```

- Si `k3d cluster list` falla por permisos, asegúrate de que `newgrp docker` se haya aplicado o vuelve a entrar en la sesión.

## 3) Crear `~/.kube` y obtener el kubeconfig de k3d
```bash
mkdir -p /home/vagrant/.kube
sudo k3d kubeconfig get iot-bonus | sudo tee /home/vagrant/.kube/config > /dev/null
sudo chown -R vagrant:vagrant /home/vagrant/.kube
export KUBECONFIG=/home/vagrant/.kube/config
```

- Si `k3d kubeconfig get iot-bonus` no devuelve nada, pega la salida de `k3d cluster list`.

## 4) Ver la URL del API server y comprobar el cluster
```bash
kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'
kubectl cluster-info
kubectl get nodes -o wide
kubectl get pods -n gitlab -o wide
kubectl get svc -n gitlab
```

- Si la URL devuelve `http://localhost:8080` significa que `kubectl` está usando un kubeconfig inválido o vacío.

## 5) Diagnóstico adicional (si sigue apuntando a localhost:8080)
```bash
cat /home/vagrant/.kube/config
k3d kubeconfig get iot-bonus
```

Pega ambas salidas en la conversación: así puedo corregir la `server:` del kubeconfig si hace falta.

## 6) Notas y soluciones comunes
- Permisos Docker: si `docker ps` devuelve error de socket, el problema es de permisos. Verifica que `vagrant` esté en el grupo `docker` y que la sesión se haya reiniciado.
- k3d API port: el cluster se creó con `--api-port 6550`, así que el `server:` en el kubeconfig debería apuntar a `https://127.0.0.1:6550` o a la IP/puerto que k3d haya expuesto.
- Hosts: en tu Mac asegúrate de tener `192.168.56.110 gitlab.local` en `/etc/hosts` como indica la guía.
- Si GitLab UI muestra `404`, espera a que los pods estén `Ready` y revisa servicios con `kubectl get svc -n gitlab`.

---
Si quieres, puedo intentar parchear el `server:` del kubeconfig automáticamente si pegas el contenido de `/home/vagrant/.kube/config` o la salida de `k3d kubeconfig get iot-bonus`.

## 7) Comprobaciones y diagnóstico detallado (útiles ahora)

Ejecuta estos comandos para investigar pods que fallan y eventos del cluster. Pega las salidas aquí para que las analice.

Describe pods problemáticos (ejemplo `gitlab-minio`, `gitlab-kas`):
```bash
kubectl -n gitlab describe pod <POD_NAME>
```

Lista eventos ordenados por tiempo:
```bash
kubectl -n gitlab get events --sort-by='.lastTimestamp'
kubectl get events --all-namespaces --sort-by='.lastTimestamp'
```

Ver logs (actual y anterior si hay CrashLoopBackOff):
```bash
kubectl -n gitlab logs <POD_NAME> --container <CONTAINER_NAME> --tail=200
kubectl -n gitlab logs <POD_NAME> --previous
```

Comprobar PVCs y StorageClasses (problemas frecuentes con MinIO):
```bash
kubectl -n gitlab get pvc
kubectl -n gitlab describe pvc <PVC_NAME>
kubectl get sc
```

Ver servicios y endpoints (para saber qué puerto exponer):
```bash
kubectl -n gitlab get svc -o wide
kubectl -n gitlab describe svc gitlab-webservice-default
kubectl -n gitlab get endpoints
```

Si quieres ver qué nodos y direcciones internas tiene el cluster:
```bash
kubectl get nodes -o wide
kubectl -n kube-system get pods -o wide
```

## 8) Soluciones rápidas según síntomas comunes

- CrashLoopBackOff en `gitlab-minio`:
	- Revisa logs y PVCs (arriba). Si el problema es permisos o falta de espacio, corrige el `StorageClass` o elimina/recupera el PVC con cuidado.
	- Reinicia el pod para observar nuevos logs: `kubectl -n gitlab delete pod <POD_NAME>` (se recreará si tiene controlador).

- Pods Pending (sin IP / ImagePullBackOff):
	- `kubectl -n gitlab describe pod <POD_NAME>` mostrará la causa (recursos, imagen, tolerations).

## 9) Acceso a la UI de GitLab desde tu Mac

- Port-forward temporal (desde la VM):
```bash
# ejecuta esto en la VM y deja el proceso en primer plano
kubectl -n gitlab port-forward svc/gitlab-webservice-default 8080:8080
```
Luego en tu Mac abre `http://localhost:8080`.

- Usar `gitlab.local` apuntando a la VM:
	- Si usas la IP de la VM (ej. `172.16.64.161`), añade en tu Mac `/etc/hosts`:
```bash
sudo -- sh -c 'echo "172.16.64.161 gitlab.local" >> /etc/hosts'
```
	- Si prefieres usar el loadbalancer de k3d y Vagrant mapea puertos a `localhost`, apunta `gitlab.local` a `127.0.0.1` o abre `http://localhost:8080`.

## 10) Recopilación rápida para que yo actúe

Pega aquí (o súbelos):

- Salida de `kubectl -n gitlab get pods -o wide`.
- Resultado de `kubectl -n gitlab describe pod <POD_NAME>` para los pods con estado `CrashLoopBackOff` o `Pending`.
- Logs relevantes: `kubectl -n gitlab logs <POD_NAME> --previous` y `kubectl -n gitlab logs <POD_NAME>`.
- Salida de `kubectl -n gitlab get pvc` y `kubectl -n gitlab get svc -o wide`.

---
Si quieres, actualizo este documento con ejemplos de salida y soluciones propuestas según lo que pegues. También puedo aplicar parches automáticos al `server:` del kubeconfig si pegas su contenido.
