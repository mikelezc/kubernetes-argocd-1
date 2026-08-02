#!/bin/bash
# Limpieza del cluster k3d de p3 y, opcionalmente, del toolbox usado para crearlo.
#
# Uso:
#   ./toolbox/reset.sh          # borra el cluster k3d
#   ./toolbox/reset.sh --deep   # además borra contenedores/volúmenes/red de ese cluster en Docker
#   ./toolbox/reset.sh --full   # --deep + borra la imagen del toolbox, su kubeconfig cacheado,
#                               # las imágenes base de K3d/K3s y el builder de Buildx usado para
#                               # publicar la imagen multi-arquitectura (todo se recrea/descarga
#                               # solo la próxima vez que haga falta; no queda nada huérfano
#                               # ocupando disco/RAM en la máquina)
#
# Cada paso es independiente: si uno falla (por ejemplo, docker no está
# disponible) el script sigue con el resto en vez de abortar entero.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_NAME="iot-cluster"
IMAGE_NAME="iot-p3-toolbox"

log() { printf '\n==> %s\n' "$1"; }

delete_k3d_cluster() {
  if command -v k3d >/dev/null 2>&1; then
    log "Eliminando clúster k3d $CLUSTER_NAME"
    k3d cluster delete "$CLUSTER_NAME" 2>/dev/null || true
  elif [ -x "$SCRIPT_DIR/run.sh" ]; then
    log "k3d no está en el host, usando el toolbox para eliminar $CLUSTER_NAME"
    "$SCRIPT_DIR/run.sh" k3d cluster delete "$CLUSTER_NAME" 2>/dev/null || true
  else
    log "No se encontró k3d ni el toolbox; nada que borrar por aquí"
  fi
}

delete_docker_artifacts() {
  if ! command -v docker >/dev/null 2>&1; then
    log "Docker no está en el host; omito la limpieza de contenedores/volúmenes/red"
    return 0
  fi

  log "Limpiando contenedores/volúmenes/red del clúster $CLUSTER_NAME"

  while IFS= read -r id; do
    [ -n "$id" ] && docker rm -f "$id" >/dev/null 2>&1
  done < <(docker ps -aq --filter "name=k3d-${CLUSTER_NAME}")

  while IFS= read -r name; do
    [ -n "$name" ] && docker volume rm "$name" >/dev/null 2>&1
  done < <(docker volume ls -q --filter "name=k3d-${CLUSTER_NAME}")

  while IFS= read -r id; do
    [ -n "$id" ] && docker network rm "$id" >/dev/null 2>&1
  done < <(docker network ls -q --filter "name=k3d-${CLUSTER_NAME}")
}

delete_toolbox_image() {
  if ! command -v docker >/dev/null 2>&1; then
    log "Docker no está en el host; omito la limpieza de la imagen del toolbox"
    return 0
  fi

  log "Eliminando imagen del toolbox ($IMAGE_NAME), capas huérfanas y kubeconfig cacheado"
  docker image rm -f "$IMAGE_NAME" >/dev/null 2>&1 || true
  docker image prune -f >/dev/null 2>&1 || true
  rm -rf "$SCRIPT_DIR/.kube"
}

delete_shared_k3d_images() {
  if ! command -v docker >/dev/null 2>&1; then
    log "Docker no está en el host; omito la limpieza de las imágenes base de K3d/K3s"
    return 0
  fi

  log "Eliminando imágenes base de K3d/K3s (k3d-tools, k3d-proxy, rancher/k3s)"
  for pattern in "ghcr.io/k3d-io/k3d-tools*" "ghcr.io/k3d-io/k3d-proxy*" "rancher/k3s*"; do
    while IFS= read -r id; do
      [ -n "$id" ] && docker image rm -f "$id" >/dev/null 2>&1
    done < <(docker images -q --filter "reference=$pattern")
  done
}

delete_buildx_builder() {
  if ! command -v docker >/dev/null 2>&1; then
    log "Docker no está en el host; omito la limpieza del builder de Buildx"
    return 0
  fi

  log "Eliminando builder de Buildx (multiarch) usado para publicar la imagen multi-arquitectura"
  docker buildx rm multiarch >/dev/null 2>&1 || true
  docker image rm -f moby/buildkit:buildx-stable-1 >/dev/null 2>&1 || true
}

usage() {
  cat <<'EOF'
Uso:
  ./toolbox/reset.sh          # borra el cluster k3d de p3
  ./toolbox/reset.sh --deep   # además borra contenedores/volúmenes/red de ese cluster en Docker
  ./toolbox/reset.sh --full   # --deep + borra la imagen del toolbox, su kubeconfig cacheado,
                              # las imágenes base de K3d/K3s y el builder de Buildx
                              # (limpieza total del laboratorio)
EOF
}

case "${1:-}" in
  "")
    delete_k3d_cluster
    ;;
  --deep)
    delete_k3d_cluster
    delete_docker_artifacts
    ;;
  --full)
    delete_k3d_cluster
    delete_docker_artifacts
    delete_toolbox_image
    delete_shared_k3d_images
    delete_buildx_builder
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    echo "Opción no válida: $1" >&2
    usage >&2
    exit 1
    ;;
esac

log "Limpieza completada"
