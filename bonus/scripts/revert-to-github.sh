#!/bin/bash

# Revierte la Application "iot-app" de Argo CD a su fuente original de
# GitHub, reaplicando p3/confs/argocd.yaml.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"	# Directorio del script
BONUS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"				# Directorio raíz del proyecto
KUBECONFIG_DEFAULT="/home/vagrant/.kube/config"				# Path por defecto del kubeconfig dentro de la VM

# Re-ejecución automática dentro de la VM de p3 si se lanza desde el host.
if [ -z "${BONUS_INSIDE_VM:-}" ] && [ ! -s "$KUBECONFIG_DEFAULT" ]; then
    P3_ROOT="$(cd "${BONUS_ROOT}/../p3" 2>/dev/null && pwd || true)"
    if command -v vagrant >/dev/null 2>&1 && [ -n "$P3_ROOT" ] && [ -f "${P3_ROOT}/Vagrantfile" ]; then
        cd "$P3_ROOT"
        BONUS_INSIDE_VM=1 vagrant ssh -c \
            'cd /vagrant && BONUS_INSIDE_VM=1 bash /bonus/scripts/revert-to-github.sh'
        exit $?
    fi
    echo "No encuentro el kubeconfig de p3. Ejecuta primero 'vagrant up' desde p3/."
    exit 1
fi

export KUBECONFIG="${KUBECONFIG:-$KUBECONFIG_DEFAULT}"

# /vagrant dentro de esta VM es la propia carpeta p3/ (la sincroniza su
# Vagrantfile), así que confs/argocd.yaml es directamente el de p3.
ARGOCD_YAML="/vagrant/confs/argocd.yaml"
[ -f "$ARGOCD_YAML" ] || ARGOCD_YAML="$(cd "${BONUS_ROOT}/../p3" && pwd)/confs/argocd.yaml"

echo "[1/2] Re-apuntando 'iot-app' a GitHub (p3/confs/argocd.yaml)..."
kubectl -n argocd apply -f "$ARGOCD_YAML" >/dev/null

echo "[2/2] Forzando sincronización..."
kubectl -n argocd annotate application iot-app \
    argocd.argoproj.io/refresh=hard --overwrite >/dev/null

echo ""
echo "Hecho. 'iot-app' vuelve a apuntar a GitHub."
echo "Verifica con: kubectl -n argocd get application iot-app -o jsonpath='{.spec.source.repoURL}'"
echo "App:          curl http://localhost:8888/"
echo ""
