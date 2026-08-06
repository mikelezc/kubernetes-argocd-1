#!/bin/bash

CYAN='\033[0;36m'
NC='\033[0m'

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"	# Directorio del script
BONUS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)" 				# Directorio raíz del proyecto
KUBECONFIG_DEFAULT="/home/vagrant/.kube/config"				# Path por defecto del kubeconfig dentro de la VM
PAT_FILE="/tmp/.gitlab-pat"									# Path del token de acceso personal (PAT) de GitLab, generado por create-gitlab-project-and-push.sh

log() {
    printf '\n%b==> %s%b\n' "$CYAN" "$1" "$NC"
}

banner() {
    echo -e "${CYAN}=========================================================${NC}"
    echo -e "${CYAN} $1${NC}"
    echo -e "${CYAN}=========================================================${NC}"
}

# Re-ejecución automática dentro de la VM de p3 si se lanza desde el host.
if [ -z "${BONUS_INSIDE_VM:-}" ] && [ ! -s "$KUBECONFIG_DEFAULT" ]; then
    P3_ROOT="$(cd "${BONUS_ROOT}/../p3" 2>/dev/null && pwd || true)"
    if command -v vagrant >/dev/null 2>&1 && [ -n "$P3_ROOT" ] && [ -f "${P3_ROOT}/Vagrantfile" ]; then
        cd "$P3_ROOT"
        BONUS_INSIDE_VM=1 vagrant ssh -c \
            'cd /vagrant && BONUS_INSIDE_VM=1 bash /bonus/scripts/connect-argocd-to-gitlab.sh'
        exit $?
    fi
    echo "No encuentro el kubeconfig de p3. Ejecuta primero 'vagrant up' desde p3/ y luego ./scripts/install.sh desde bonus/." >&2
    exit 1
fi

export KUBECONFIG="${KUBECONFIG:-$KUBECONFIG_DEFAULT}"		# Usamos el kubeconfig de la VM si no se ha especificado otro

if ! kubectl get ns gitlab >/dev/null 2>&1; then
    echo "GitLab no está instalado (no existe el namespace 'gitlab'). Ejecuta primero ./scripts/install.sh." >&2
    exit 1
fi

if ! kubectl -n argocd get application iot-app >/dev/null 2>&1; then
    echo "No encuentro la Application 'iot-app' en Argo CD. Ejecuta primero 'vagrant up' en p3/ (que la crea)." >&2
    exit 1
fi

GITLAB_CLUSTER_BASE_URL="http://gitlab.gitlab.svc"
PROJECT_FULL_PATH="root/mlezcano-gitlab-demo"
ARGO_REPO_URL="${GITLAB_CLUSTER_BASE_URL}/${PROJECT_FULL_PATH}.git"

get_pat_token() {
    if [ ! -f "$PAT_FILE" ] || [ ! -s "$PAT_FILE" ]; then
        echo "No se encontró el token en ${PAT_FILE}." >&2
        echo "Ejecuta primero: ./scripts/create-gitlab-project-and-push.sh" >&2
        exit 1
    fi
    PAT_TOKEN=$(cat "$PAT_FILE")
    export PAT_TOKEN
}

configure_argocd_repo() {
    banner "1/3 Registrando repositorio GitLab en Argo CD"
    log "Creando el secret 'repo-gitlab-local' con las credenciales del repo..."
    kubectl -n argocd delete secret repo-gitlab-local --ignore-not-found >/dev/null 2>&1 || true
    kubectl -n argocd create secret generic repo-gitlab-local \
        --from-literal=type=git \
        --from-literal=url="${ARGO_REPO_URL}" \
        --from-literal=username=root \
        --from-literal=password="${PAT_TOKEN}" \
        --from-literal=forceHttpBasicAuth=true \
        --from-literal=insecure=true >/dev/null
    kubectl -n argocd label secret repo-gitlab-local \
        argocd.argoproj.io/secret-type=repository --overwrite >/dev/null
    log "Repositorio registrado: ${ARGO_REPO_URL}"
}

configure_argocd_application() {
    banner "2/3 Re-apuntando la Application 'iot-app' a GitLab local"
    log "Aplicando ${BONUS_ROOT}/confs/argocd-application.yaml..."
    kubectl -n argocd apply -f "${BONUS_ROOT}/confs/argocd-application.yaml" >/dev/null
    log "Application actualizada."
}

refresh_argocd() {
    banner "3/3 Forzando sincronización inicial"
    log "Reiniciando argocd-repo-server para que recoja el nuevo repositorio..."
    kubectl -n argocd rollout restart deployment argocd-repo-server >/dev/null
    kubectl -n argocd rollout status deployment argocd-repo-server --timeout=180s >/dev/null
    log "Forzando refresh de 'iot-app'..."
    kubectl -n argocd annotate application iot-app \
        argocd.argoproj.io/refresh=hard --overwrite >/dev/null
}

get_pat_token
configure_argocd_repo
configure_argocd_application
refresh_argocd

ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath='{.data.password}' 2>/dev/null | base64 -d \
    || echo "(ver secret argocd-initial-admin-secret)")

echo ""
echo "============================================================"
echo "  Argo CD re-apuntado a GitLab local"
echo "============================================================"
echo ""
echo "Argo CD:    http://localhost:8080"
echo "  usuario:    admin"
echo "  contraseña: ${ARGOCD_PASSWORD}"
echo ""
echo "Repositorio: http://gitlab.localhost:8080/root/mlezcano-gitlab-demo"
echo "Aplicación:  http://localhost:8888"
echo ""
echo "Para demostrar el flujo GitOps:"
echo "  1. Abre GitLab → root/mlezcano-gitlab-demo → deployment.yaml"
echo "  2. Cambia la imagen:  mikelezc/playground:v1  →  mikelezc/playground:v2"
echo "  3. Haz commit en main → Argo CD sincroniza automáticamente"
echo "  4. Verifica: curl http://localhost:8888/"
echo ""
echo "Para volver a GitHub en cualquier momento:"
echo "  ./scripts/revert-to-github.sh"
echo ""
