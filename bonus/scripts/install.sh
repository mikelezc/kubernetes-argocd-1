#!/bin/bash

# Antes de ejecutar este script, p3 debe estar ya desplegado.
# solo añadimos GitLab encima, en el mismo clúster.

CYAN='\033[0;36m'
NC='\033[0m'

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BONUS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
KUBECONFIG_DEFAULT="/home/vagrant/.kube/config"

log() {
    printf '\n%b==> %s%b\n' "$CYAN" "$1" "$NC"
}

log_ok()   { log "[OK] $1"; }
log_warn() { echo "[WARN] $1" >&2; }

banner() {
    echo -e "${CYAN}=========================================================${NC}"
    echo -e "${CYAN} $1${NC}"
    echo -e "${CYAN}=========================================================${NC}"
}

# Re-ejecución automática dentro de la VM de p3 si se lanza desde el host.
# Antes de entrar, redimensionamos la VM ya que GitLab necesita más RAM que en p3 (implica un "vagrant reload").
if [ -z "${BONUS_INSIDE_VM:-}" ] && [ ! -s "$KUBECONFIG_DEFAULT" ]; then
    P3_ROOT="$(cd "${BONUS_ROOT}/../p3" 2>/dev/null && pwd || true)"
    if command -v vagrant >/dev/null 2>&1 && [ -n "$P3_ROOT" ] && [ -f "${P3_ROOT}/Vagrantfile" ]; then
        cd "$P3_ROOT"
        # Comprobamos la RAM real de la VM antes de decidir si hace falta redimensionarla.
        CURRENT_MEM_MB="$(vagrant ssh -c "free -m | awk '/Mem:/ {print \$2}'" 2>/dev/null | tr -d '\r' | tail -n1)"
        if [ -z "$CURRENT_MEM_MB" ] || [ "$CURRENT_MEM_MB" -lt 6000 ]; then
            log "Redimensionando la VM de p3 para dar cabida a GitLab (P3_MEMORY=8192, P3_CPUS=3)..."
            P3_MEMORY=8192 P3_CPUS=3 vagrant reload
        else
            log "La VM de p3 ya tiene RAM suficiente (${CURRENT_MEM_MB}MB) — no hace falta redimensionar."
        fi
        BONUS_INSIDE_VM=1 vagrant ssh -c \
            'cd /vagrant && BONUS_INSIDE_VM=1 bash /bonus/scripts/install.sh'
        exit $?
    fi
    echo "No encuentro el kubeconfig de p3. Ejecuta primero 'vagrant up' desde p3/." >&2
    exit 1
fi

# Si estamos dentro de la VM de p3, arrancamos el clúster k3d si no está ya arriba.
k3d cluster start iot-cluster >/dev/null 2>&1 || true

export KUBECONFIG="${KUBECONFIG:-$KUBECONFIG_DEFAULT}"

wait_for_node_ready() {
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
        if kubectl wait --for=condition=Ready node --all --timeout=15s >/dev/null 2>&1; then
            return 0
        fi
        sleep 5
    done
    return 1
}

log "Esperando a que el nodo esté listo..."
if ! wait_for_node_ready; then
    log_warn "El nodo tarda más de lo normal en responder — se probará igualmente"
fi

# Acceso a bonus/confs desde dentro de la VM de p3 (montado en p3/Vagrantfile)
if [ -d "/bonus/confs" ]; then
    CONFS_DIR="/bonus/confs"
else
    CONFS_DIR="$BONUS_ROOT/confs"
fi

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

banner "1/3 Instalando Helm"

# Docker/kubectl/k3d ya los instaló p3; aquí solo puede faltar Helm.
if ! command -v helm &>/dev/null; then
    curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | sudo bash
fi

kubectl apply -f "$CONFS_DIR/namespaces.yaml"

banner "2/3 Instalando GitLab"

helm repo add gitlab https://charts.gitlab.io/ && helm repo update

VALUES_PATH="$CONFS_DIR/gitlab-values.yaml"

MINIO_ARCH_ARGS=()
case "$(uname -m)" in
    aarch64|arm64)
        MINIO_ARCH_ARGS=(
            --set "minio.imageTag=RELEASE.2020-09-21T22-31-59Z-arm64"
            --set "minio.minioMc.tag=RELEASE.2020-09-23T20-02-13Z-arm64"
        )
        MC_IMAGE="registry.gitlab.com/gitlab-org/cloud-native/mirror/images/minio/mc:RELEASE.2020-09-23T20-02-13Z-arm64"
        ;;
    *)
        MC_IMAGE="minio/mc:RELEASE.2018-07-13T00-53-22Z"
        ;;
esac

if ! helm upgrade --install gitlab gitlab/gitlab \
    --version 9.9.0 \
    --timeout 600s \
    --namespace gitlab \
    -f "$VALUES_PATH" \
    "${MINIO_ARCH_ARGS[@]}"; then
    echo "Error: GitLab no se pudo instalar con Helm." >&2
    exit 1
fi

log "Esperando pod MinIO..."
kubectl -n gitlab wait --for=condition=ready pod \
    -l app=minio,release=gitlab --timeout=300s 2>/dev/null \
    || log_warn "MinIO tarda más de lo normal"

if wait_for_minio_endpoint; then
    log_ok "MinIO responde en su endpoint"
else
    log_warn "MinIO aún no expone el endpoint — se probará igualmente"
fi

kubectl -n gitlab delete job -l app=minio,release=gitlab --ignore-not-found >/dev/null 2>&1

log "Inicializando buckets MinIO..."
ACCESS_KEY=$(kubectl -n gitlab get secret gitlab-minio-secret \
    -o jsonpath="{.data.accesskey}" | base64 -d 2>/dev/null || echo "minioadmin")
SECRET_KEY=$(kubectl -n gitlab get secret gitlab-minio-secret \
    -o jsonpath="{.data.secretkey}" | base64 -d 2>/dev/null || echo "minioadmin")

for attempt in 1 2 3; do
    if kubectl -n gitlab run mc-init --rm -i --restart=Never \
        --image="$MC_IMAGE" \
        --env="ACCESS_KEY=$ACCESS_KEY" \
        --env="SECRET_KEY=$SECRET_KEY" \
        --command -- /bin/sh < "$CONFS_DIR/minio-init-buckets.sh" >/dev/null 2>&1; then
        break
    fi
    [ "$attempt" -lt 3 ] && { log_warn "MinIO aún arrancando, reintentando..."; sleep 3; continue; }
    log_warn "No se pudo inicializar MinIO tras varios intentos"
done

banner "3/3 Contraseña inicial de GitLab"

ROOT_SECRET="gitlab-gitlab-initial-root-password"
log "Esperando secret con contraseña root de GitLab..."
for _ in $(seq 1 24); do
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
echo "=================== GitLab instalado ======================"
echo "============================================================"
echo ""
echo "GitLab:    http://gitlab.localhost:8080"
echo ""
echo "  usuario:    root"
if [ -n "$DECODED" ]; then
    echo "  contraseña: $DECODED"
else
    echo "  contraseña: kubectl -n gitlab get secret gitlab-gitlab-initial-root-password \\"
    echo "               -o jsonpath='{.data.password}' | base64 -d"
fi
echo ""
echo "Argo CD (:8080) y la app (:8888) ya estaban arriba gracias a p3."
echo ""
echo "Próximos pasos:"
echo ""
echo "  1. Crear repositorio en GitLab y hacer push del manifiesto:"
echo "       ./scripts/create-gitlab-project-and-push.sh"
echo ""
echo "  2. Conectar Argo CD al repositorio GitLab:"
echo "       ./scripts/connect-argocd-to-gitlab.sh"
echo ""
