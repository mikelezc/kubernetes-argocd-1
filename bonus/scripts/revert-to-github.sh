#!/bin/bash

# Revierte la Application "iot-app" de Argo CD a su fuente original de
# GitHub, reaplicando p3/confs/argocd.yaml.

CYAN='\033[0;36m'
NC='\033[0m'

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"	# Directorio del script
BONUS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"				# Directorio raíz del proyecto
KUBECONFIG_DEFAULT="/home/vagrant/.kube/config"				# Path por defecto del kubeconfig dentro de la VM

log() {
    printf '\n%b==> %s%b\n' "$CYAN" "$1" "$NC"
}

# Banner para las fases principales del script (mismo estilo que el resto de bonus/p1/p2/p3).
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
            'cd /vagrant && BONUS_INSIDE_VM=1 bash /bonus/scripts/revert-to-github.sh'
        exit $?
    fi
    echo "No encuentro el kubeconfig de p3. Ejecuta primero 'vagrant up' desde p3/." >&2
    exit 1
fi

export KUBECONFIG="${KUBECONFIG:-$KUBECONFIG_DEFAULT}"

if ! kubectl -n argocd get application iot-app >/dev/null 2>&1; then
    echo "No encuentro la Application 'iot-app' en Argo CD. Ejecuta primero 'vagrant up' en p3/ (que la crea)." >&2
    exit 1
fi

# /vagrant dentro de esta VM es la propia carpeta p3/ (la sincroniza su
# Vagrantfile), así que confs/argocd.yaml es directamente el de p3.
ARGOCD_YAML="/vagrant/confs/argocd.yaml"
[ -f "$ARGOCD_YAML" ] || ARGOCD_YAML="$(cd "${BONUS_ROOT}/../p3" && pwd)/confs/argocd.yaml"

if [ ! -f "$ARGOCD_YAML" ]; then
    echo "No encuentro ${ARGOCD_YAML} (el manifiesto original de p3). Comprueba que p3/ está intacto." >&2
    exit 1
fi

banner "1/2 Re-apuntando 'iot-app' a GitHub (p3/confs/argocd.yaml)"
log "Aplicando ${ARGOCD_YAML}..."
kubectl -n argocd apply -f "$ARGOCD_YAML" >/dev/null

banner "2/2 Forzando sincronización"
log "Forzando refresh de 'iot-app'..."
kubectl -n argocd annotate application iot-app \
    argocd.argoproj.io/refresh=hard --overwrite >/dev/null

echo ""
echo "Hecho. 'iot-app' vuelve a apuntar a GitHub."
echo ""
echo "App:          curl http://localhost:8888/"
echo ""
