#!/bin/bash
# bonus/scripts/install.sh
# Responsabilidad: instalar herramientas, crear cluster k3d iot-bonus,
# desplegar GitLab (namespace gitlab) y Argo CD (namespace argocd).
# NO configura ninguna Application de Argo CD — eso lo hace connect-argocd-to-gitlab.sh

set -e

log_section() {
    echo ""
    echo "========================================================="
    echo " $1"
    echo "========================================================="
}

log_ok()   { echo "[OK]   $1"; }
log_warn() { echo "[WARN] $1"; }

wait_for_minio_endpoint() {
    for _ in 1 2 3 4 5 6; do
        if kubectl -n gitlab get endpoints gitlab-minio-svc \
            -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null | grep -q .; then
            return 0
        fi
        sleep 2
    done
    return 1
}

# -------------------------------------------------------
log_section "1/5 — Herramientas base (Docker, kubectl, k3d, Helm)"
# -------------------------------------------------------

if ! command -v docker &>/dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker vagrant
fi

if ! command -v kubectl &>/dev/null; then
    ARCH=$(dpkg --print-architecture)
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH}/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
fi

if ! command -v k3d &>/dev/null; then
    curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
fi

if ! command -v helm &>/dev/null; then
    curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | sudo bash
fi

# -------------------------------------------------------
log_section "2/5 — Cluster k3d iot-bonus"
# -------------------------------------------------------

k3d cluster delete iot-bonus 2>/dev/null || true
k3d cluster create iot-bonus \
    --api-port 6550 \
    -p "80:80@loadbalancer" \
    -p "443:443@loadbalancer" \
    -p "8080:8080@loadbalancer" \
    -p "8888:30080@server:0"

mkdir -p /home/vagrant/.kube
k3d kubeconfig get iot-bonus > /home/vagrant/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube
export KUBECONFIG=/home/vagrant/.kube/config

kubectl create namespace gitlab --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace dev    --dry-run=client -o yaml | kubectl apply -f -

# -------------------------------------------------------
log_section "3/5 — GitLab (Helm chart 9.9.0)"
# -------------------------------------------------------

helm repo add gitlab https://charts.gitlab.io/ && helm repo update

if [ -f "/vagrant/confs/gitlab-values.yaml" ]; then
    VALUES_PATH="/vagrant/confs/gitlab-values.yaml"
else
    VALUES_PATH="../confs/gitlab-values.yaml"
fi

if ! helm upgrade --install gitlab gitlab/gitlab \
    --version 9.9.0 \
    --timeout 600s \
    --namespace gitlab \
    -f "$VALUES_PATH"; then
    echo "Error: GitLab no se pudo instalar con Helm."
    exit 1
fi

echo "Parcheando Ingress de GitLab a clase traefik..."
for INGRESS in gitlab-webservice-default gitlab-kas gitlab-minio; do
    if kubectl -n gitlab patch ingress "$INGRESS" \
        --type=merge -p '{"spec":{"ingressClassName":"traefik"}}' 2>/dev/null; then
        log_ok "$INGRESS parcheado"
    else
        log_ok "$INGRESS ya estaba parcheado"
    fi
done

echo "Esperando pod MinIO..."
kubectl -n gitlab wait --for=condition=ready pod \
    -l app=minio,release=gitlab --timeout=300s 2>/dev/null \
    || log_warn "MinIO tarda más de lo normal"

if wait_for_minio_endpoint; then
    log_ok "MinIO responde en su endpoint"
else
    log_warn "MinIO aún no expone el endpoint — se probará igualmente"
fi

echo "Inicializando buckets MinIO..."
ACCESS_KEY=$(kubectl -n gitlab get secret gitlab-minio-secret \
    -o jsonpath="{.data.accesskey}" | base64 -d 2>/dev/null || echo "minioadmin")
SECRET_KEY=$(kubectl -n gitlab get secret gitlab-minio-secret \
    -o jsonpath="{.data.secretkey}" | base64 -d 2>/dev/null || echo "minioadmin")

for attempt in 1 2 3; do
    if kubectl -n gitlab run mc-init --rm -i --restart=Never \
        --image=minio/mc:latest \
        --command -- /bin/sh -c "
            mc alias set myminio http://gitlab-minio-svc.gitlab.svc:9000 \
                '$ACCESS_KEY' '$SECRET_KEY' >/dev/null 2>&1
            for b in registry git-lfs runner-cache gitlab-uploads gitlab-artifacts \
                      gitlab-backups gitlab-packages tmp gitlab-mr-diffs \
                      gitlab-terraform-state gitlab-ci-secure-files \
                      gitlab-dependency-proxy gitlab-pages; do
                mc mb myminio/\$b >/dev/null 2>&1 || true
                mc policy none myminio/\$b >/dev/null 2>&1 || true
            done
        " >/dev/null 2>&1; then
        break
    fi
    [ "$attempt" -lt 3 ] && { log_warn "MinIO aún arrancando, reintentando..."; sleep 3; continue; }
    log_warn "No se pudo inicializar MinIO tras varios intentos"
done

# -------------------------------------------------------
log_section "4/5 — Argo CD (modo HTTP, sin Application)"
# -------------------------------------------------------

kubectl apply -n argocd \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.10.4/manifests/install.yaml

echo "Esperando Argo CD server..."
kubectl -n argocd wait --for=condition=ready pod \
    -l app.kubernetes.io/name=argocd-server --timeout=300s >/dev/null

echo "Habilitando modo HTTP (insecure)..."
kubectl -n argocd patch configmap argocd-cmd-params-cm \
    --type merge -p '{"data":{"server.insecure":"true"}}' >/dev/null
kubectl -n argocd rollout restart deployment argocd-server >/dev/null
kubectl -n argocd rollout status deployment argocd-server --timeout=180s >/dev/null

echo "Creando Ingress para Argo CD..."
kubectl -n argocd apply -f - >/dev/null <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
  namespace: argocd
spec:
  ingressClassName: traefik
  rules:
  - host: localhost
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 80
EOF

# -------------------------------------------------------
log_section "5/5 — Contraseña inicial de GitLab"
# -------------------------------------------------------

ROOT_SECRET="gitlab-gitlab-initial-root-password"
echo "Esperando secret con contraseña root de GitLab..."
for i in $(seq 1 24); do
    kubectl -n gitlab get secret "$ROOT_SECRET" >/dev/null 2>&1 && break
    sleep 5
done

DECODED=""
if kubectl -n gitlab get secret "$ROOT_SECRET" >/dev/null 2>&1; then
    ENCODED=$(kubectl -n gitlab get secret "$ROOT_SECRET" \
        -o jsonpath='{.data.password}' 2>/dev/null || true)
    DECODED=$(echo "$ENCODED" | base64 -d 2>/dev/null || true)
fi

echo ""
echo "============================================================"
echo "=================== Instalación completada ================="
echo "============================================================"
echo ""
echo "GitLab:    http://gitlab.localhost:8081"
echo "  usuario:    root"
if [ -n "$DECODED" ]; then
    echo "  contraseña: $DECODED"
else
    echo "  contraseña: kubectl -n gitlab get secret gitlab-gitlab-initial-root-password \\"
    echo "               -o jsonpath='{.data.password}' | base64 -d"
fi
echo ""
echo "Argo CD:   http://localhost:8081  (sin Application aún)"
echo ""
echo "Próximos pasos:"
echo "  1. Crear repositorio en GitLab y hacer push del manifiesto:"
echo "       ./scripts/create-gitlab-project-and-push.sh"
echo "  2. Conectar Argo CD al repositorio GitLab:"
echo "       ./scripts/connect-argocd-to-gitlab.sh"
echo ""
