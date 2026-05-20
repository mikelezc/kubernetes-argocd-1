#!/bin/bash
# Recopila diagnósticos k3d / kubectl en la VM y guarda en /vagrant/diagnostics-<ts>.tar.gz
set -u
TS=$(date +%Y%m%dT%H%M%S)
OUTDIR="/vagrant/diagnostics-$TS"
mkdir -p "$OUTDIR"
exec >"$OUTDIR/run.log" 2>&1

echo "Recopilando diagnósticos: $TS"

echo "== Entorno =="
uname -a || true
cat /etc/os-release || true

echo "\n== Docker y k3d =="
docker --version || true
k3d --version || true
k3d cluster list || true
sudo docker ps -a || true

echo "\n== Kubeconfig =="
echo "KUBECONFIG=$KUBECONFIG"
if [ -f /home/vagrant/.kube/config ]; then
  echo "/home/vagrant/.kube/config ->"; sed -n '1,200p' /home/vagrant/.kube/config || true
fi
k3d kubeconfig get iot-bonus > "$OUTDIR/k3d_kubeconfig" 2>/dev/null || true

echo "\n== Cluster info =="
kubectl cluster-info || true
kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' || true
kubectl get nodes -o wide || true

echo "\n== Namespaces: gitlab & argocd =="
kubectl -n gitlab get pods -o wide || true
kubectl -n gitlab get svc -o wide || true
kubectl -n gitlab get pvc || true
kubectl -n gitlab get events --sort-by='.lastTimestamp' || true
kubectl -n gitlab describe pod gitlab-minio-575f5d6c6f-twrb4 || true
kubectl -n gitlab logs gitlab-minio-575f5d6c6f-twrb4 -c minio --tail=500 || true
kubectl -n gitlab logs gitlab-minio-575f5d6c6f-twrb4 --previous || true

kubectl -n gitlab describe pod gitlab-kas-54d44cff88-vtxpr || true
kubectl -n gitlab describe pod gitlab-kas-54d44cff88-ztrr9 || true
kubectl -n gitlab logs gitlab-kas-54d44cff88-vtxpr --tail=200 || true
kubectl -n gitlab logs gitlab-kas-54d44cff88-ztrr9 --tail=200 || true

kubectl -n gitlab get jobs -o wide || true
kubectl -n gitlab get endpoints || true

echo "\n== PVCs, PVs y StorageClasses =="
kubectl -n gitlab get pvc -o yaml > "$OUTDIR/gitlab_pvc.yaml" 2>/dev/null || true
kubectl get pv -o yaml > "$OUTDIR/pvs.yaml" 2>/dev/null || true
kubectl get sc -o yaml > "$OUTDIR/sc.yaml" 2>/dev/null || true

echo "\n== kube-system =="
kubectl -n kube-system get pods -o wide || true
kubectl -n kube-system describe pod metrics-server-5985cbc9d7-s7jzf || true
kubectl -n kube-system logs metrics-server-5985cbc9d7-s7jzf || true

echo "\n== Uso de recursos en la VM =="
free -h || true
grep MemTotal /proc/meminfo || true

echo "\n== Últimos eventos (all namespaces) =="
kubectl get events --all-namespaces --sort-by='.lastTimestamp' || true

# Recopila archivos relevantes al OUTDIR
cp -a /home/vagrant/.kube "$OUTDIR/" 2>/dev/null || true

# Empaqueta
tar -czf "/vagrant/diagnostics-$TS.tar.gz" -C /vagrant "diagnostics-$TS" || true

echo "Diagnósticos guardados en: /vagrant/diagnostics-$TS.tar.gz"
ls -lh "/vagrant/diagnostics-$TS.tar.gz" || true

exit 0
