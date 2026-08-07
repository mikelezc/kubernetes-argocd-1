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

log_warn() { echo "[WARN] $1" >&2; }

banner() {
    echo -e "${CYAN}=========================================================${NC}"
    echo -e "${CYAN} $1${NC}"
    echo -e "${CYAN}=========================================================${NC}"
}

# Re-ejecución automática dentro de la VM de p3 si se lanza desde el host.
# Antes de entrar, redimensionamos la VM ya que GitLab necesita más RAM que en p3 si fuera necesario.
if [ -z "${BONUS_INSIDE_VM:-}" ] && [ ! -s "$KUBECONFIG_DEFAULT" ]; then
    P3_ROOT="$(cd "${BONUS_ROOT}/../p3" 2>/dev/null && pwd || true)"
    if command -v vagrant >/dev/null 2>&1 && [ -n "$P3_ROOT" ] && [ -f "${P3_ROOT}/Vagrantfile" ]; then
        cd "$P3_ROOT"

        # Comprobamos que la VM de p3 está realmente arriba.
        P3_STATE="$(vagrant status --machine-readable 2>/dev/null | awk -F, '$3 == "state" {print $4}')"
        if [ "$P3_STATE" != "running" ]; then
            echo "La VM de p3 no está levantada (estado: ${P3_STATE:-no creada}). Ejecuta 'vagrant up' desde p3/ antes de instalar el bonus." >&2
            exit 1
        fi

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

if ! k3d cluster list iot-cluster >/dev/null 2>&1; then
    echo "No se ha creado el clúster k3d 'iot-cluster'. Ejecuta primero 'vagrant up' en p3/ antes." >&2
    exit 1
fi

# Arrancamos el clúster k3d si no está ya arriba (puede haberse quedado parado tras el reload).
k3d cluster start iot-cluster >/dev/null 2>&1 || true

export KUBECONFIG="${KUBECONFIG:-$KUBECONFIG_DEFAULT}"

if [ ! -s "$KUBECONFIG" ]; then
    echo "No encuentro el kubeconfig de p3 en $KUBECONFIG. Ejecuta primero p3/scripts/install.sh." >&2
    exit 1
fi

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

# Si existe /bonus/confs, lo usamos. Si no, usamos el que está en el repo del bonus.
if [ -d "/bonus/confs" ]; then
    CONFS_DIR="/bonus/confs"
else
    CONFS_DIR="$BONUS_ROOT/confs"
fi

wait_for_vm_dns() {
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        if getent hosts raw.githubusercontent.com >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
    done
    return 1
}

log "Esperando a que el DNS de la VM esté listo..."
if ! wait_for_vm_dns; then
    echo "[ERROR] La VM no tiene salida a Internet. Prueba a recrear p3 con la RAM ya puesta desde el arranque, sin pasar por reload:" >&2
    echo "        cd p3 && vagrant destroy -f && P3_MEMORY=8192 P3_CPUS=3 vagrant up" >&2
    exit 1
fi

banner "1/2 Desplegando GitLab"

# Aplicamos los manifiestos de GitLab (namespace + deployment + service)
kubectl apply -f "$CONFS_DIR/namespaces.yaml"
kubectl apply -f "$CONFS_DIR/gitlab.yaml"

log "Esperando a que GitLab termine su primer arranque (reconfigure + migraciones, puede tardar unos minutos)..."
if ! kubectl -n gitlab rollout status deployment/gitlab --timeout=1200s; then
    echo "Error: GitLab no llegó a estar listo a tiempo. Revisa 'kubectl -n gitlab logs deploy/gitlab'." >&2
    exit 1
fi

GITLAB_POD="$(kubectl -n gitlab get pod -l app=gitlab -o jsonpath='{.items[0].metadata.name}')"

banner "2/2 Contraseña inicial de GitLab"

log "Esperando el fichero con la contraseña root..."
DECODED=""
for _ in $(seq 1 12); do
    DECODED=$(kubectl -n gitlab exec "$GITLAB_POD" -- \
        grep '^Password:' /etc/gitlab/initial_root_password 2>/dev/null | awk '{print $2}')
    [ -n "$DECODED" ] && break
    sleep 5
done

echo ""
echo -e "${CYAN}============================================================${NC}"
echo -e "${CYAN}=================== GitLab instalado ======================${NC}"
echo -e "${CYAN}============================================================${NC}"
echo ""
echo "GitLab:    http://gitlab.localhost:8080"
echo ""
echo "  usuario:    root"
if [ -n "$DECODED" ]; then
    echo "  contraseña: $DECODED"
else
    echo "  contraseña: kubectl -n gitlab exec deploy/gitlab -- grep '^Password:' /etc/gitlab/initial_root_password"
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
