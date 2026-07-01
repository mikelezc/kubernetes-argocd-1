#!/bin/bash
# Toolbox para p3: kubectl + k3d + docker(cliente) sin necesitar sudo en el host.
# Los contenedores que k3d crea se lanzan en el Docker del host (vía el socket
# montado abajo), no anidados dentro de este contenedor.
#
# Uso:
#   ./toolbox/run.sh ./scripts/install.sh   # instala el clúster igual que sin toolbox
#   ./toolbox/run.sh kubectl get pods -n dev
#   ./toolbox/run.sh                        # shell interactiva con las herramientas listas

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P3_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
IMAGE_NAME="iot-p3-toolbox"
KUBE_DIR="$SCRIPT_DIR/.kube"

mkdir -p "$KUBE_DIR"

if [[ -z "$(docker images -q "$IMAGE_NAME" 2>/dev/null)" ]]; then
  docker build -t "$IMAGE_NAME" "$SCRIPT_DIR"
fi

tty_flags=()
if [[ -t 0 && -t 1 ]]; then
  tty_flags=(-it)
fi

docker run --rm "${tty_flags[@]+"${tty_flags[@]}"}" \
  --network host \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$P3_DIR":/workspace \
  -v "$KUBE_DIR":/root/.kube \
  -w /workspace \
  "$IMAGE_NAME" "$@"
