#!/bin/bash

# Script de instalación de un cluster k3d, Argo CD y la aplicación de ejemplo.
# Maneja tanto despliegues dentro de Vagrant como en un entorno local (Linux y macOS ARM).

CYAN='\033[0;36m'
NC='\033[0m'

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"	# Directorio del script
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"					# Directorio raíz del proyecto

# Determinamos si estamos dentro de Vagrant o en un entorno local
if [[ -f "/vagrant/confs/argocd.yaml" ]]; then
  REPO_ROOT="/vagrant"
else
  REPO_ROOT="$ROOT_DIR"
fi
CLUSTER_NAME="iot-cluster"
ARGOCD_VERSION="v3.4.5"

log() {
  printf '\n%b==> %s%b\n' "$CYAN" "$1" "$NC"
}

banner() {
  echo -e "${CYAN}=========================================================${NC}"
  echo -e "${CYAN} $1${NC}"
  echo -e "${CYAN}=========================================================${NC}"
}

# Configuramos DNS en el host para que pueda resolver nombres externos
configure_host_dns() {
  printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\n' > /etc/resolv.conf
  if [ -f /etc/dhcpcd.conf ] && ! grep -q '^nohook resolv.conf' /etc/dhcpcd.conf; then
    echo 'nohook resolv.conf' >> /etc/dhcpcd.conf
  fi
}

# Instalamos las herramientas necesarias en Linux (Docker, kubectl, k3d)
install_linux_tools() {
  configure_host_dns

  if ! command -v docker >/dev/null 2>&1; then
    curl -fsSL https://get.docker.com | sudo sh
  fi

  if id vagrant >/dev/null 2>&1 && ! id -nG vagrant 2>/dev/null | grep -qw docker; then
    usermod -aG docker vagrant
  fi

  if ! command -v kubectl >/dev/null 2>&1; then
    arch="$(uname -m)"
    case "$arch" in
      x86_64) k8s_arch="amd64" ;;
      aarch64|arm64) k8s_arch="arm64" ;;
      *) echo "Arquitectura no soportada: $arch" >&2; exit 1 ;;
    esac
    tmpdir="$(mktemp -d)"
    for attempt in 1 2 3; do
      curl -L "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${k8s_arch}/kubectl" -o "$tmpdir/kubectl" && break
      echo "Fallo descargando kubectl, reintentando (intento $attempt/3)..." >&2
      sleep 3
    done
    sudo install -o root -g root -m 0755 "$tmpdir/kubectl" /usr/local/bin/kubectl
    rm -rf "$tmpdir"
  fi

  if ! command -v k3d >/dev/null 2>&1; then
    for attempt in 1 2 3; do
      curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash && break
      echo "Fallo instalando k3d, reintentando (intento $attempt/3)..." >&2
      sleep 3
    done
    command -v k3d >/dev/null 2>&1 || { echo "No se pudo instalar k3d tras 3 intentos." >&2; exit 1; }
  fi

  configure_docker_dns
}

# Configuramos DNS en Docker para Linux 
# Contenedores puedan resolver nombres externos para que Argo CD funcione correctamente
configure_docker_dns() {
  local daemon_json="/etc/docker/daemon.json"
  if [ -f "$daemon_json" ] && command -v python3 >/dev/null 2>&1; then
    python3 - "$daemon_json" <<'PY'
import json, sys
path = sys.argv[1]
try:
    with open(path) as f:
        config = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    config = {}
config["dns"] = ["8.8.8.8", "1.1.1.1"]
with open(path, "w") as f:
    json.dump(config, f, indent=2)
PY
  else
    printf '{\n  "dns": ["8.8.8.8", "1.1.1.1"]\n}\n' > "$daemon_json"
  fi
  systemctl restart docker
}

# En caso de necesitar instalar herramientas en macOS, se requiere Homebrew y Docker Desktop.
install_macos_tools() {
  if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew no está instalado. Instálalo antes de continuar." >&2
    exit 1
  fi

  if ! command -v kubectl >/dev/null 2>&1; then
    brew install kubectl
  fi

  if ! command -v k3d >/dev/null 2>&1; then
    brew install k3d
  fi

  if ! command -v docker >/dev/null 2>&1; then
    echo "Docker Desktop no está disponible. Instálalo y arráncalo antes de continuar." >&2
    exit 1
  fi
}

# Verificamos que Docker esté listo antes de continuar
ensure_docker_ready() {
  for attempt in 1 2 3 4 5; do
    docker info >/dev/null 2>&1 && return 0
    echo "Docker todavía no responde, reintentando (intento $attempt/5)..."
    sleep 2
  done
  echo "El daemon de Docker no responde. Arranca Docker Desktop o verifica permisos sobre el socket." >&2
  exit 1
}

# Parcheo de los pods de CoreDNS para que hagan forward a servidores DNS públicos 
# El DNS de k3d es inestable y a veces falla en la resolución de nombres externos.
patch_coredns() {
  kubectl -n kube-system get configmap coredns -o yaml | \
    sed 's/forward \. \/etc\/resolv.conf/forward . 8.8.8.8 1.1.1.1/' | \
    kubectl apply -f - >/dev/null
  kubectl rollout restart deployment/coredns -n kube-system >/dev/null
  kubectl rollout status deployment/coredns -n kube-system --timeout=120s >/dev/null
}

# Comprobamos que el DNS externo resuelve justo antes del momento crítico 
# (cuando Argo CD intenta el primer git fetch). Reaplicamos el parche si fuera necesario.
wait_for_dns() {
  for attempt in 1 2 3 4 5 6; do
    if kubectl run "dns-check-${attempt}" --rm -i --restart=Never \
        --image=busybox:1.36 --timeout=20s \
        --command -- nslookup github.com >/dev/null 2>&1; then
      return 0
    fi
    echo "DNS externo aún no responde, reaplicando el parche de CoreDNS (intento $attempt/6)..."
    patch_coredns
    sleep 3
  done
  return 1
}

wait_for_argocd() {
  echo "Esperando que se creen los pods de ArgoCD..."
  timeout=120
  while ! kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server 2>/dev/null | grep -q argocd-server; do
    timeout=$((timeout - 2))
    if [ "$timeout" -le 0 ]; then
      echo "El pod de argocd-server no se creó a tiempo. Estado actual:" >&2
      kubectl get pods -n argocd -o wide
      kubectl get events -n argocd --sort-by=.lastTimestamp | tail -20
      exit 1
    fi
    sleep 2
  done
  kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s >/dev/null
}

main() {
  banner "1/5 Instalando dependencias (Docker, kubectl, k3d)"
  case "$(uname -s)" in
    Darwin) install_macos_tools ;;
    Linux) install_linux_tools ;;
    *) echo "Sistema operativo no soportado" >&2; exit 1 ;;
  esac
  ensure_docker_ready

  banner "2/5 Creando el clúster k3d"
  k3d cluster delete "$CLUSTER_NAME" >/dev/null 2>&1 || true
  k3d cluster create "$CLUSTER_NAME" \
    --servers 1 \
    --agents 0 \
    --api-port 6550 \
    -p "8080:80@loadbalancer" \
    -p "8888:30080@server:0" \
    --k3s-arg '--disable=metrics-server@server:0' >/dev/null

  log "Esperando a que los nodos estén listos"
  kubectl wait --for=condition=Ready node --all --timeout=180s >/dev/null

  if [ -d /home/vagrant ]; then				# Despliegue dentro de Vagrant
    log "Exportando kubeconfig para el usuario vagrant"
    mkdir -p /home/vagrant/.kube
    k3d kubeconfig get "$CLUSTER_NAME" > /home/vagrant/.kube/config
    chown -R vagrant:vagrant /home/vagrant/.kube
  fi										# Despliegue en local

  log "Ajustando CoreDNS para salida estable a Internet"
  patch_coredns

  banner "3/5 Creando namespaces"
  kubectl apply -f "$REPO_ROOT/confs/namespaces.yaml" >/dev/null
  log "Namespaces creados: $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}')"

  banner "4/5 Instalando Argo CD"
  kubectl apply -n argocd --server-side --force-conflicts -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml" >/dev/null
  wait_for_argocd

  log "Ajustando la reconciliación de Argo CD (a pocos segundos)"
  kubectl patch configmap argocd-cm -n argocd --type merge --patch-file "$REPO_ROOT/confs/argocd-reconciliation-patch.yaml" >/dev/null
  kubectl rollout restart statefulset/argocd-application-controller -n argocd >/dev/null
  kubectl rollout status statefulset/argocd-application-controller -n argocd --timeout=180s >/dev/null

  log "Exponiendo Argo CD por HTTP"
  kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge --patch-file "$REPO_ROOT/confs/argocd-insecure-patch.yaml" >/dev/null
  kubectl rollout restart deployment/argocd-server -n argocd >/dev/null
  kubectl rollout status deployment/argocd-server -n argocd --timeout=180s >/dev/null
  kubectl apply -n argocd -f "$REPO_ROOT/confs/argocd-ingress.yaml" >/dev/null

  banner "5/5 Desplegando la Application de Argo CD"
  log "Verificando resolución DNS externa antes de aplicar la Application"
  if ! wait_for_dns; then
    echo "[WARN] El DNS externo sigue sin responder tras varios intentos; Argo CD podría fallar al sincronizar" >&2
  fi
  kubectl apply -f "$REPO_ROOT/confs/argocd.yaml" >/dev/null

  echo ""
  echo "============================================================"
  echo "=================== Instalación completada ================="
  echo "============================================================"
  echo ""
  echo ""
  echo "Puedes acceder a Argo CD en: http://localhost:8080"
  echo "    - usuario: admin"
  echo "    - contraseña: $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
  echo ""
  echo "Puedes ver la app en: http://localhost:8888"
  echo ""
}

main "$@"
