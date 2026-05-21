# Diagnósticos y comandos útiles — Parte 3 (K3d + Argo CD)

Guía completa con todos los comandos para depurar y reparar problemas de DNS, Argo CD y sincronización del repo.

## Acceso a la VM

```bash
vagrant ssh mlezcanoS
```

## Comprobaciones básicas desde la VM

```bash
# Probar resolución DNS desde la VM
nslookup github.com

# Ver el resolv.conf de la VM
cat /etc/resolv.conf

# Comprobar que Docker/k3d/kubectl funcionan
sudo k3d cluster list
sudo kubectl get nodes
```

## CoreDNS — diagnosticar y reparar DNS

### Ver estado actual
```bash
sudo kubectl get pods -n kube-system | grep coredns
sudo kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50 || true
```

### Probar DNS desde dentro del cluster
```bash
sudo kubectl run -it --rm --restart=Never --image=alpine dns-test -- sh

# Dentro del pod (/ #) ejecutar:
nslookup github.com
ping -c 2 github.com
curl -I https://github.com
exit
```

### FIX DEFINITIVO: CoreDNS con resolvers públicos

Si aparece error `lookup github.com on 10.43.0.10:53: no such host`:

```bash
# 1. Ver configuración actual de CoreDNS
sudo kubectl -n kube-system get configmap coredns -o yaml

# 2. Editar CoreDNS
sudo kubectl -n kube-system edit configmap coredns

# En el editor, busca:     forward . /etc/resolv.conf
# Y cámbiala a:              forward . 8.8.8.8 1.1.1.1
# Guardar: ESC + :wq

# 3. Reiniciar CoreDNS
sudo kubectl rollout restart deployment/coredns -n kube-system
sudo kubectl rollout status deployment/coredns -n kube-system --timeout=60s
sleep 10

# 4. Verificar que argocd-repo-server puede acceder a GitHub
POD=$(sudo kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-repo-server -o jsonpath='{.items[0].metadata.name}')
sudo kubectl -n argocd exec -it $POD -- sh -c "git ls-remote https://github.com/mikelezc/mlezcano-iot-argocd.git"
# Esperado: hash + refs/heads/main (sin errores)
```

## Argo CD — logs, estado y refresh

### Ver logs del repo-server
```bash
sudo kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server --tail=200

# En tiempo real (útil durante refresh):
sudo kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server -f
```

### Ver estado actual de la Application
```bash
sudo kubectl get applications.argoproj.io -n argocd
sudo kubectl get applications.argoproj.io iot-app -n argocd -o yaml
sudo kubectl get applications.argoproj.io iot-app -n argocd -o yaml | sed -n '/^status:/,$p'
```

### Forzar refresh
```bash
# Anotación para forzar refresh (equivalente a botón REFRESH en UI)
sudo kubectl -n argocd annotate application iot-app argocd.argoproj.io/refresh="true" --overwrite

# Si necesitas forzar limpia (re-clone completo):
sudo kubectl -n argocd delete pod -l app.kubernetes.io/name=argocd-repo-server

# Ver eventos
sudo kubectl get events -n argocd --sort-by=.metadata.creationTimestamp | tail -n 50
```

### Parchear repoURL (si cambiaste la URL del repo)
```bash
sudo kubectl -n argocd patch application iot-app --type='json' -p '[{"op":"replace","path":"/spec/source/repoURL","value":"https://github.com/mikelezc/mlezcano-iot-argocd.git"}]'
```

## Verificación del repositorio

```bash
# Clonar el repo desde la VM y ver deployment.yaml
git clone https://github.com/mikelezc/mlezcano-iot-argocd.git /tmp/test-repo || true
ls -la /tmp/test-repo
cat /tmp/test-repo/deployment.yaml
```

## Verificar aplicación en puertos locales

```bash
# Desde tu máquina host (fuera de la VM):
curl -s http://localhost:8888/ | jq .
curl http://localhost:8080/
```

## Workflow completo para sincronizar cambios de GitHub

1. **Cambiar tag en GitHub** (ej: v1→v5):
   - Abre tu repo en GitHub
   - Edita `deployment.yaml` 
   - Cambia `image: wil42/playground:v1` a `image: wil42/playground:v5`
   - Commit & Push

2. **Forzar Argo CD a detectar el cambio:**
   ```bash
   vagrant ssh mlezcanoS
   
   # Revisar logs en tiempo real
   sudo kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server -f &
   
   # Forzar refresh
   sudo kubectl -n argocd annotate application iot-app argocd.argoproj.io/refresh="true" --overwrite
   
   # Esperar unos segundos y Ctrl+C para salir de logs
   ```

3. **Verificar que Argo CD ve el diff:**
   - Abre `http://localhost:8080` en tu navegador
   - Haz clic en la aplicación `iot-app`
   - Presiona **REFRESH** (botón arriba a la derecha)
   - Debe desaparecer `ComparisonError` y mostrar el diff v1→v5

4. **Verificar auto-sync:**
   - La aplicación debe sincronizarse automáticamente
   - Abre `http://localhost:8888` y verás la versión v5 corriendo

## Notas importantes

- Asegúrate que `spec.source.path` apunta al lugar correcto en tu repo
- `deployment.yaml` debe estar en la raíz del repo (en el `.` que indica `spec.source.path`)
- Si usas `sudo` con kubectl/k3d, es porque docker socket requiere permisos
- El fix de CoreDNS es estable; puedes revertirlo después editando el ConfigMap nuevamente

---
Documentación actualizada – Creado para agilizar defensa y depuración.
