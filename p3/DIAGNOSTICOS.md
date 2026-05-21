# Diagnósticos y comandos útiles — Parte 3 (K3d + Argo CD)

Guía rápida con los comandos que usamos para depurar conectividad DNS, Argo CD y sincronización del repo. Ejecuta los comandos en orden cuando estés dentro de la VM (`vagrant ssh mlezcanoS`). Usa `sudo` cuando se indique.

## Acceso a la VM

```bash
vagrant ssh mlezcanoS
```

## Comprobaciones básicas desde la VM (fuera del cluster)

```bash
# Probar resolución DNS desde la VM
nslookup github.com

# Ver el resolv.conf de la VM
cat /etc/resolv.conf

# Comprobar que Docker/k3d/kubectl funcionan (si hace falta con sudo)
sudo k3d cluster list
sudo kubectl get nodes
```

## CoreDNS — verificar estado y logs

```bash
# Listar pods de kube-system (buscar coredns)
sudo kubectl get pods -n kube-system | grep coredns

# Ver logs de CoreDNS (últimas 50 líneas)
sudo kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50 || true

# Reiniciar CoreDNS si hay problemas de resolución
sudo kubectl rollout restart deployment/coredns -n kube-system
sudo kubectl rollout status deployment/coredns -n kube-system --timeout=60s
sleep 30
```

## Probar DNS desde DENTRO del cluster (pod temporal)

```bash
# Crear un pod temporal con Alpine y entrar
sudo kubectl run -it --rm --restart=Never --image=alpine dns-test -- sh

# Dentro del pod (/ #) ejecutar:
nslookup github.com
ping -c 2 github.com
curl -I https://github.com
exit

# Si nslookup devuelve IPs, DNS funciona desde el cluster
```

## Argo CD — logs y estado del repo-server

```bash
# Ver logs recientes del repo-server
sudo kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server --tail=200

# Ver pods y estado en el namespace argocd
sudo kubectl get pods -n argocd -o wide

# Describir el deployment del repo-server para ver eventos/errores
sudo kubectl describe deployment argocd-repo-server -n argocd
```

## Probar acceso al Git remoto desde dentro del repo-server (si hace falta)

```bash
# Ejecutar un comando git desde dentro del pod repo-server
POD=$(sudo kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-repo-server -o jsonpath='{.items[0].metadata.name}')
sudo kubectl -n argocd exec -it $POD -- sh -c "apk add --no-cache git ca-certificates >/dev/null 2>&1 || true; git ls-remote https://github.com/mikelezc/miguel-iot-argocd.git"

# Ajusta la URL del repo en el comando anterior si usas otra
```

## Comprobar la Application `iot-app` en Argo CD (CR)

```bash
# Listar aplicaciones Argo CD
sudo kubectl get applications.argoproj.io -n argocd

# Mostrar el YAML de la Application (verifica spec.source)
sudo kubectl get applications.argoproj.io iot-app -n argocd -o yaml

# Fíjate en:
# spec.source.repoURL
# spec.source.path
# spec.source.targetRevision
```

## Forzar un REFRESH (equivalente al botón REFRESH en UI)

```bash
# Anotar la Application para forzar refresh
sudo kubectl -n argocd annotate application iot-app argocd.argoproj.io/refresh="true" --overwrite

# O reiniciar el pod repo-server para forzar re-clone
sudo kubectl -n argocd delete pod -l app.kubernetes.io/name=argocd-repo-server

# Ver eventos recientes en argocd para detectar errores
sudo kubectl get events -n argocd --sort-by=.metadata.creationTimestamp | tail -n 50
```

## Observación en tiempo real y verificación del repo

Estos comandos permiten forzar un refresh, seguir los logs del repo-server en tiempo real y verificar el contenido del repo desde la VM.

```bash
# Forzar refresh (anotación)
sudo kubectl -n argocd annotate application iot-app argocd.argoproj.io/refresh="true" --overwrite

# Seguir logs del repo-server en tiempo real (mientras se procesa el refresh)
sudo kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server -f

# Obtener solo el bloque status de la Application (útil para inspección rápida)
sudo kubectl get applications.argoproj.io iot-app -n argocd -o yaml | sed -n '/^status:/,$p'

# Clonar el repo desde la VM y mostrar deployment.yaml (verifica ruta y tag)
git clone https://github.com/mikelezc/miguel-iot-argocd.git /tmp/test-repo || true
ls -la /tmp/test-repo
sed -n '1,200p' /tmp/test-repo/deployment.yaml || true

# Ver eventos recientes en argocd para detectar errores durante el refresh
sudo kubectl get events -n argocd --sort-by=.metadata.creationTimestamp | tail -n 50
```

## Probar que la app sirve en el puerto local

```bash
# Desde tu máquina host (fuera de la VM), comprobar la app en el puerto 8888
curl -s http://localhost:8888/ | jq .

# Comprobar Argo CD UI en http://localhost:8080
```

## Diagnóstico Git adicional

```bash
# Si sospechas de permisos o firewall, prueba clonar desde la VM (fuera del cluster)
git clone https://github.com/mikelezc/miguel-iot-argocd.git /tmp/test-repo || true
ls -la /tmp/test-repo || true
```

## Notas rápidas
- Asegúrate de que `spec.source.path` apunte correctamente al directorio que contiene `deployment.yaml` en tu repo.
- Usa `sudo` para kubectl/k3d si el usuario no tiene permiso al socket Docker.
- Si cambias el tag en GitHub (v1→v2) y no ves diff, revisa los logs del repo-server y la `spec.source`.

## Parcheo rápido y forzado de refresh

Si necesitas actualizar `repoURL` para añadir `.git` o forzar un refresh desde la línea de comandos, usa estos comandos:

```bash
# Parchear la Application para ajustar repoURL (añade .git si falta)
sudo kubectl -n argocd patch application iot-app --type='json' -p '[{"op":"replace","path":"/spec/source/repoURL","value":"https://github.com/mikelezc/miguel-iot-argocd.git"}]'

# Forzar un refresh equivalente al botón REFRESH
sudo kubectl -n argocd annotate application iot-app argocd.argoproj.io/refresh="true" --overwrite

# Reiniciar el pod repo-server si quieres forzar re-clone desde cero
sudo kubectl -n argocd delete pod -l app.kubernetes.io/name=argocd-repo-server

# Ver eventos recientes para diagnosticar resultados
sudo kubectl get events -n argocd --sort-by=.metadata.creationTimestamp | tail -n 50
```





# Ver el Corefile actual
sudo kubectl -n kube-system get configmap coredns -o yaml | sed -n '1,240p'

# Editar el ConfigMap (reemplaza 'forward . /etc/resolv.conf' por 'forward . 8.8.8.8 1.1.1.1')
sudo kubectl -n kube-system edit configmap coredns

# Reiniciar CoreDNS y esperar
sudo kubectl rollout restart deployment/coredns -n kube-system
sudo kubectl rollout status deployment/coredns -n kube-system --timeout=60s
sleep 10

# Verificar resolución desde argocd-repo-server y forzar refresh
POD=$(sudo kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-repo-server -o jsonpath='{.items[0].metadata.name}')
sudo kubectl -n argocd exec -it $POD -- sh -c "git ls-remote https://github.com/mikelezc/miguel-iot-argocd.git"

# Forzar refresh de la Application
sudo kubectl -n argocd annotate application iot-app argocd.argoproj.io/refresh="true" --overwrite

# Seguir logs del repo-server para confirmar éxito
sudo kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server -f

# Revertir (si quieres volver a la configuración original)
sudo kubectl -n kube-system edit configmap coredns
# (restaurar 'forward . /etc/resolv.conf') y luego:
sudo kubectl rollout restart deployment/coredns -n kube-system
---
Creado para agilizar comprobaciones durante la defensa y depuración.
