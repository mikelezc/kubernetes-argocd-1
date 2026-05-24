#!/bin/bash
# bonus/scripts/connect-argocd-to-gitlab.sh
# Responsabilidad: registrar el repo GitLab local en Argo CD y crear la
# Application que sincroniza los manifests hacia el namespace dev.
# Debe ejecutarse DESPUÉS de create-gitlab-project-and-push.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BONUS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
KUBECONFIG_DEFAULT="/home/vagrant/.kube/config"
PAT_FILE="/tmp/.gitlab-pat"

# Re-ejecución automática dentro de la VM si se lanza desde el host
if [ -z "${BONUS_INSIDE_VM:-}" ] && [ ! -s "$KUBECONFIG_DEFAULT" ]; then
    if command -v vagrant >/dev/null 2>&1 && [ -f "${BONUS_ROOT}/Vagrantfile" ]; then
        cd "$BONUS_ROOT"
        BONUS_INSIDE_VM=1 vagrant ssh -c \
            'cd /vagrant && BONUS_INSIDE_VM=1 bash /vagrant/scripts/connect-argocd-to-gitlab.sh'
        exit $?
    fi
    echo "No encuentro el kubeconfig. Ejecuta primero 'vagrant up'."
    exit 1
fi

export KUBECONFIG="${KUBECONFIG:-$KUBECONFIG_DEFAULT}"

GITLAB_CLUSTER_BASE_URL="http://gitlab-webservice-default.gitlab.svc:8181"
PROJECT_FULL_PATH="root/mlezcano-gitlab-demo"
ARGO_REPO_URL="${GITLAB_CLUSTER_BASE_URL}/${PROJECT_FULL_PATH}.git"

log() { echo "[$1] $2"; }

get_pat_token() {
    if [ ! -f "$PAT_FILE" ] || [ ! -s "$PAT_FILE" ]; then
        echo "No se encontró el token en ${PAT_FILE}."
        echo "Ejecuta primero: ./scripts/create-gitlab-project-and-push.sh"
        exit 1
    fi
    PAT_TOKEN=$(cat "$PAT_FILE")
    export PAT_TOKEN
}

configure_argocd_repo() {
    log "1/3" "Registrando repositorio GitLab en Argo CD..."
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
}

configure_argocd_application() {
    log "2/3" "Creando Application 'iot-app' apuntando a GitLab local..."
    kubectl -n argocd apply -f - >/dev/null <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: iot-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: ${ARGO_REPO_URL}
    targetRevision: main
    path: .
  destination:
    server: https://kubernetes.default.svc
    namespace: dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
}

refresh_argocd() {
    log "3/3" "Forzando sincronización inicial..."
    kubectl -n argocd rollout restart deployment argocd-repo-server >/dev/null
    kubectl -n argocd rollout status deployment argocd-repo-server --timeout=180s >/dev/null
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
echo "  Argo CD conectado a GitLab local"
echo "============================================================"
echo ""
echo "Argo CD:    http://localhost:8081"
echo "  usuario:    admin"
echo "  contraseña: ${ARGOCD_PASSWORD}"
echo ""
echo "Repositorio: http://gitlab.localhost:8081/root/mlezcano-gitlab-demo"
echo "Aplicación:  http://localhost:8889"
echo ""
echo "Para demostrar el flujo GitOps:"
echo "  1. Abre GitLab → root/mlezcano-gitlab-demo → deployment.yaml"
echo "  2. Cambia la imagen:  mikelezc/playground:v1  →  mikelezc/playground:v2"
echo "  3. Haz commit en main → Argo CD sincroniza automáticamente"
echo "  4. Verifica: curl http://localhost:8889/"
echo ""
