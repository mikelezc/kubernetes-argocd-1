#!/bin/bash
# scripts/install.sh (Bonus)

set -e

log_section() {
    echo ""
    echo "========================================================="
    echo " $1"
    echo "========================================================="
}

log_step() {
    echo "[$1] $2"
}

log_note() {
    echo "    $1"
}

log_ok() {
    echo "[OK] $1"
}

log_warn() {
    echo "[WARN] $1"
}

wait_for_minio_endpoint() {
    for _ in 1 2 3 4 5 6; do
        if kubectl -n gitlab get endpoints gitlab-minio-svc -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null | grep -q .; then
            return 0
        fi
        sleep 2
    done

    return 1
}

log_section "Preparando la VM y las herramientas base"

log_step "1/7" "Instalando Docker, kubectl y k3d"

# Instalamos Docker (si no lo tenemos)
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    newgrp docker
fi

# Instalamos kubectl cross-platform (si no lo tenemos)
if ! command -v kubectl &> /dev/null; then
    ARCH=$(dpkg --print-architecture)
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH}/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
fi

# Instalamos K3d cross-platform (si no lo tenemos)
if ! command -v k3d &> /dev/null; then
    curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
fi

log_step "2/7" "Instalando Helm"

# Instalamos helm cross-platform (si no lo tenemos)
if ! command -v helm &> /dev/null; then
    curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | sudo bash
fi

log_step "3/7" "Creando el clúster k3d iot-bonus"

# Eliminamos cualquier cluster previo con el mismo nombre (evitar conflictos).
k3d cluster delete iot-bonus || true
# Importante: añadimos puertos extras para gitlab (80, 443) y Argo CD (8080) para poder acceder desde el host.
k3d cluster create iot-bonus --api-port 6550 -p "80:80@loadbalancer" -p "443:443@loadbalancer" -p "8080:8080@loadbalancer" -p "8888:30080@server:0"

# Configurar kubeconfig para el usuario vagrant
mkdir -p /home/vagrant/.kube
k3d kubeconfig get iot-bonus > /home/vagrant/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube

log_section "Desplegando GitLab y Argo CD"

log_step "4/7" "Preparando repositorios y namespaces"

# Añadir repositorio de GitLab
helm repo add gitlab https://charts.gitlab.io/
helm repo update

# Crear namespace
kubectl create namespace gitlab 2>/dev/null || true
kubectl create namespace argocd 2>/dev/null || true
kubectl create namespace dev 2>/dev/null || true

log_step "5/7" "Desplegando GitLab con Helm"

# Soporte dual: Vagrant (/vagrant) o Linux Manual (..)
if [ -f "/vagrant/confs/gitlab-values.yaml" ]; then
    VALUES_PATH="/vagrant/confs/gitlab-values.yaml"
else
    VALUES_PATH="../confs/gitlab-values.yaml"
fi

# El chart 10.x endurece la configuración y exige Redis/PostgreSQL/Object Storage externos.
# Para este laboratorio fijamos una versión anterior compatible con el GitLab minimalista.
GITLAB_CHART_VERSION="9.9.0"

if ! helm upgrade --install gitlab gitlab/gitlab \
    --version "$GITLAB_CHART_VERSION" \
    --timeout 600s \
    --namespace gitlab \
    -f "$VALUES_PATH"; then
    echo "Error: GitLab no se pudo instalar con Helm. Revisa el mensaje anterior y el values.yaml."
    exit 1
fi

log_step "6/7" "Desplegando Argo CD"

echo "Aplicando manifiesto de instalación de Argo CD..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.10.4/manifests/install.yaml

log_section "Ajustando GitLab y Argo CD"

export KUBECONFIG="${KUBECONFIG:-/home/vagrant/.kube/config}"
if [ ! -s "$KUBECONFIG" ]; then
        mkdir -p "$(dirname "$KUBECONFIG")"
        k3d kubeconfig get iot-bonus > "$KUBECONFIG"
fi

log_step "7/7" "Aplicar ajustes finales y publicar accesos"

echo "Esperando namespace gitlab..."
kubectl wait --for=condition=ready ns/gitlab --timeout=300s 2>/dev/null || true

echo "Parcheando Ingress a clase traefik..."
kubectl -n gitlab patch ingress gitlab-webservice-default --type=merge -p '{"spec":{"ingressClassName":"traefik"}}' \
    || log_ok "gitlab-webservice-default ya estaba parcheado"

kubectl -n gitlab patch ingress gitlab-kas --type=merge -p '{"spec":{"ingressClassName":"traefik"}}' \
    || log_ok "gitlab-kas ya estaba parcheado"

kubectl -n gitlab patch ingress gitlab-minio --type=merge -p '{"spec":{"ingressClassName":"traefik"}}' \
    || log_ok "gitlab-minio ya estaba parcheado"

echo "Esperando pod gitlab-minio..."
kubectl -n gitlab wait --for=condition=ready pod \
    -l app=minio,release=gitlab \
    --timeout=300s 2>/dev/null || log_warn "MinIO todavía no está listo; se reintentará la inicialización"

echo "Esperando a que MinIO publique el endpoint..."
if wait_for_minio_endpoint; then
    log_ok "MinIO ya responde por su servicio"
else
    log_warn "MinIO tarda más de lo normal en exponer el servicio; se probará igualmente"
fi

echo "Preparando buckets de MinIO..."
ACCESS_KEY=$(kubectl -n gitlab get secret gitlab-minio-secret -o jsonpath="{.data.accesskey}" | base64 -d 2>/dev/null || echo "minioadmin")
SECRET_KEY=$(kubectl -n gitlab get secret gitlab-minio-secret -o jsonpath="{.data.secretkey}" | base64 -d 2>/dev/null || echo "minioadmin")

for attempt in 1 2 3; do
    if kubectl -n gitlab run mc-init --rm -i --restart=Never \
        --image=minio/mc:latest \
        --command -- /bin/sh -c "
            mc alias set myminio http://gitlab-minio-svc.gitlab.svc:9000 '$ACCESS_KEY' '$SECRET_KEY' >/dev/null 2>&1
            for bucket in registry git-lfs runner-cache gitlab-uploads gitlab-artifacts gitlab-backups gitlab-packages tmp gitlab-mr-diffs gitlab-terraform-state gitlab-ci-secure-files gitlab-dependency-proxy gitlab-pages; do
                mc mb myminio/\$bucket >/dev/null 2>&1 || true
                mc policy none myminio/\$bucket >/dev/null 2>&1 || true
            done
        " >/dev/null 2>&1; then
        break
    fi

    if [ "$attempt" -lt 3 ]; then
        log_note "MinIO aún está arrancando; reintentando una vez más..."
        sleep 3
    else
        log_warn "No se pudo inicializar MinIO tras varios intentos"
    fi
done

ROOT_SECRET_NAME="gitlab-gitlab-initial-root-password"

echo "Obteniendo contraseña inicial del usuario 'root'..."
for i in $(seq 1 24); do
    if kubectl -n gitlab get secret "$ROOT_SECRET_NAME" >/dev/null 2>&1; then
        break
    fi
    sleep 5
done

if kubectl -n gitlab get secret "$ROOT_SECRET_NAME" >/dev/null 2>&1; then
    ROOT_PASSWORD=$(kubectl -n gitlab get secret "$ROOT_SECRET_NAME" -o jsonpath='{.data.password}' 2>/dev/null || true)
    if [ -n "$ROOT_PASSWORD" ]; then
        DECODED=$(echo "$ROOT_PASSWORD" | base64 -d 2>/dev/null || true)
        if [ -n "$DECODED" ]; then
			log_ok "Contraseña inicial del usuario 'root' obtenida correctamente"
        else
            log_warn "Se encontró el secreto pero no se pudo decodificar"
        fi
    else
        log_warn "El secreto existe pero la contraseña no se pudo extraer"
    fi
else
    log_warn "El secreto con la contraseña inicial aún no está disponible"
    echo "  Puedes obtenerlo cuando esté listo con:"
    echo "  kubectl -n gitlab get secret gitlab-gitlab-initial-root-password -o jsonpath='{.data.password}' | base64 -d"
fi

echo "============================================================"
echo "=================== Instalación completada ================="
echo "============================================================"
echo ""
echo ""
echo "Próximos pasos:"
echo ""
echo "1. Puedes acceder a GitLab en: http://gitlab.localhost:8081"
echo "    - usuario: root"
echo "    - contraseña: $DECODED"
echo ""
echo "2. Para desplegar la aplicación de ejemplo y subirla a GitLab, ejecuta:"
echo "     ./scripts/create-gitlab-project-and-push.sh"
echo ""
