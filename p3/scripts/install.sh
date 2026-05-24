#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
if [[ -f "/vagrant/confs/argocd.yaml" ]]; then
  REPO_ROOT="/vagrant"
else
  REPO_ROOT="$ROOT_DIR"
fi
CLUSTER_NAME="iot-cluster"
ARGOCD_VERSION="v2.10.4"

log() {
  printf '\n==> %s\n' "$1"
}

install_linux_tools() {
  if ! command -v docker >/dev/null 2>&1; then
    curl -fsSL https://get.docker.com | sudo sh
  fi

  if ! command -v kubectl >/dev/null 2>&1; then
    arch="$(uname -m)"
    case "$arch" in
      x86_64) k8s_arch="amd64" ;;
      aarch64|arm64) k8s_arch="arm64" ;;
      *) echo "Arquitectura no soportada: $arch" >&2; exit 1 ;;
    esac
    tmpdir="$(mktemp -d)"
    curl -L "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${k8s_arch}/kubectl" -o "$tmpdir/kubectl"
    sudo install -o root -g root -m 0755 "$tmpdir/kubectl" /usr/local/bin/kubectl
    rm -rf "$tmpdir"
  fi

  if ! command -v k3d >/dev/null 2>&1; then
    curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
  fi
}

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

ensure_docker_ready() {
  if ! docker info >/dev/null 2>&1; then
    echo "Docker no responde todavía. Arranca Docker Desktop o verifica permisos sobre el socket." >&2
    exit 1
  fi
}

patch_coredns() {
  kubectl -n kube-system get configmap coredns -o yaml | \
    sed 's/forward \. \/etc\/resolv.conf/forward . 8.8.8.8 1.1.1.1/' | \
    kubectl apply -f - >/dev/null
  kubectl rollout restart deployment/coredns -n kube-system >/dev/null
  kubectl rollout status deployment/coredns -n kube-system --timeout=120s >/dev/null
}

wait_for_argocd() {
  echo "Esperando que se creen los pods de ArgoCD..."
  while ! kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server 2>/dev/null | grep -q argocd-server; do
    sleep 2
  done
  kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s >/dev/null
}

main() {
  log "Instalando dependencias"
  case "$(uname -s)" in
    Darwin) install_macos_tools ;;
    Linux) install_linux_tools ;;
    *) echo "Sistema operativo no soportado" >&2; exit 1 ;;
  esac

  ensure_docker_ready

  log "Creando cluster k3d con nombre $CLUSTER_NAME"
  k3d cluster delete "$CLUSTER_NAME" >/dev/null 2>&1 || true
  k3d cluster create "$CLUSTER_NAME" \
    --servers 1 \
    --agents 0 \
    --api-port 6550 \
    -p "8080:80@loadbalancer" \
    -p "8888:30080@server:0" \
    --k3s-arg '--disable=metrics-server@server:0' >/dev/null

  log "Esperando nodos listos"
  kubectl wait --for=condition=Ready node --all --timeout=180s >/dev/null

  log "Ajustando CoreDNS para salida estable a Internet"
  patch_coredns

  log "Creando namespaces"
  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f - >/dev/null

  log "Instalando Argo CD"
  kubectl apply -n argocd -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml" >/dev/null
  wait_for_argocd

  log "Ajustando la reconciliación de Argo CD a pocos segundos"
  kubectl patch configmap argocd-cm -n argocd --type merge -p '{"data":{"timeout.reconciliation":"5s","timeout.reconciliation.jitter":"0s"}}' >/dev/null
  kubectl rollout restart statefulset/argocd-application-controller -n argocd >/dev/null
  kubectl rollout status statefulset/argocd-application-controller -n argocd --timeout=180s >/dev/null

  log "Exponiendo Argo CD por HTTP"
  kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p '{"data":{"server.insecure":"true"}}' >/dev/null
  kubectl rollout restart deployment/argocd-server -n argocd >/dev/null
  kubectl rollout status deployment/argocd-server -n argocd --timeout=180s >/dev/null
  cat <<'EOF' | kubectl apply -n argocd -f - >/dev/null
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  annotations:
    ingress.kubernetes.io/ssl-redirect: "false"
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  ingressClassName: traefik
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              name: http
EOF

  log "Aplicando la Application de Argo CD"
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
