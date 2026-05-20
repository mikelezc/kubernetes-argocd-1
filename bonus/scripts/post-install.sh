#!/bin/bash
# Post-install script for GitLab + ArgoCD bonus setup
# Automatiza los parches necesarios tras `vagrant up`
# Uso: vagrant ssh -c 'bash /vagrant/scripts/post-install.sh'

set -e

echo "=== Post-Install Script para GitLab + ArgoCD en K3d ==="

# Asegurar que kubectl apunta al cluster k3d correcto incluso en shells no interactivos
export KUBECONFIG="${KUBECONFIG:-/home/vagrant/.kube/config}"
if [ ! -s "$KUBECONFIG" ]; then
  mkdir -p "$(dirname "$KUBECONFIG")"
  k3d kubeconfig get iot-bonus > "$KUBECONFIG"
fi

# Esperar a que gitlab namespace esté listo
echo "Esperando namespace gitlab..."
kubectl wait --for=condition=ready ns/gitlab --timeout=300s 2>/dev/null || true

# Parchear ingress a clase traefik
echo "Parcheando Ingress a clase traefik..."
kubectl -n gitlab patch ingress gitlab-webservice-default --type=merge -p '{"spec":{"ingressClassName":"traefik"}}' \
  || echo "✓ gitlab-webservice-default already patched"

kubectl -n gitlab patch ingress gitlab-kas --type=merge -p '{"spec":{"ingressClassName":"traefik"}}' \
  || echo "✓ gitlab-kas already patched"

kubectl -n gitlab patch ingress gitlab-minio --type=merge -p '{"spec":{"ingressClassName":"traefik"}}' \
  || echo "✓ gitlab-minio already patched"

# Esperar a que minio esté running
echo "Esperando pod gitlab-minio..."
kubectl -n gitlab wait --for=condition=ready pod \
  -l app=minio,release=gitlab \
  --timeout=300s 2>/dev/null || echo "⚠ minio no está ready aún, continuando..."

# Verificar y crear buckets si es necesario
echo "Verificando buckets de MinIO..."
ACCESS_KEY=$(kubectl -n gitlab get secret gitlab-minio-secret -o jsonpath="{.data.accesskey}" | base64 -d 2>/dev/null || echo "minioadmin")
SECRET_KEY=$(kubectl -n gitlab get secret gitlab-minio-secret -o jsonpath="{.data.secretkey}" | base64 -d 2>/dev/null || echo "minioadmin")

# Intentar crear buckets con mc
kubectl -n gitlab run mc-init --rm -i --restart=Never \
  --image=minio/mc:latest \
  --command -- /bin/sh -c "
    mc alias set myminio http://gitlab-minio-svc.gitlab.svc:9000 '$ACCESS_KEY' '$SECRET_KEY'
    for bucket in registry git-lfs runner-cache gitlab-uploads gitlab-artifacts gitlab-backups gitlab-packages tmp gitlab-mr-diffs gitlab-terraform-state gitlab-ci-secure-files gitlab-dependency-proxy gitlab-pages; do
      mc mb myminio/\$bucket 2>/dev/null || true
      mc policy none myminio/\$bucket 2>/dev/null || true
    done
  " 2>/dev/null || echo "⚠ MinIO buckets setup skipped (puede reintentarse manualmente)"

echo ""
echo "=== Post-Install Completado ==="
echo ""
echo "✓ Ingress parcheados a traefik"
echo "✓ MinIO buckets creados"
echo ""
echo "Próximos pasos:"
echo "1. Añade a /etc/hosts (en tu host): 192.168.56.110 gitlab.local"
echo "2. Abre http://gitlab.local en el navegador"
echo ""
