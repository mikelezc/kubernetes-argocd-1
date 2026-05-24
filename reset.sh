#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
  printf '\n==> %s\n' "$1"
}

destroy_vagrant_module() {
  local module_dir="$1"
  if [ -f "$ROOT_DIR/$module_dir/Vagrantfile" ]; then
    log "Destruyendo Vagrant en $module_dir"
    (cd "$ROOT_DIR/$module_dir" && vagrant destroy -f)
  fi
}

delete_k3d_cluster() {
  local cluster_name="$1"
  if command -v k3d >/dev/null 2>&1; then
    log "Eliminando clúster k3d $cluster_name"
    k3d cluster delete "$cluster_name" >/dev/null 2>&1 || true
  fi
}

delete_k3d_docker_artifacts() {
  local cluster_name="$1"
  if ! command -v docker >/dev/null 2>&1; then
    return 0
  fi

  log "Limpiando artefactos Docker del clúster $cluster_name"

  while IFS= read -r container_id; do
    [ -n "$container_id" ] && docker rm -f "$container_id" >/dev/null 2>&1 || true
  done < <(docker ps -aq --filter "name=k3d-${cluster_name}")

  while IFS= read -r volume_name; do
    [ -n "$volume_name" ] && docker volume rm "$volume_name" >/dev/null 2>&1 || true
  done < <(docker volume ls -q --filter "name=k3d-${cluster_name}")

  while IFS= read -r network_id; do
    [ -n "$network_id" ] && docker network rm "$network_id" >/dev/null 2>&1 || true
  done < <(docker network ls -q --filter "name=k3d-${cluster_name}")

  while IFS= read -r image_id; do
    [ -n "$image_id" ] && docker image rm -f "$image_id" >/dev/null 2>&1 || true
  done < <(docker image ls -q --filter "reference=k3d-${cluster_name}*")
}

reset_bonus() {
  destroy_vagrant_module "bonus"
}

reset_p1() {
  destroy_vagrant_module "p1"
}

reset_p2() {
  destroy_vagrant_module "p2"
}

reset_p3() {
  delete_k3d_cluster "iot-cluster"
}

reset_p3_deep() {
  delete_k3d_cluster "iot-cluster"
  delete_k3d_docker_artifacts "iot-cluster"
}

usage() {
  cat <<'EOF'
Uso:
  ./reset.sh            # limpia todo lo del repo
  ./reset.sh p1         # limpia solo p1
  ./reset.sh p2         # limpia solo p2
  ./reset.sh p3         # limpia solo p3
  ./reset.sh p3 --deep  # limpia p3 y sus artefactos Docker asociados
  ./reset.sh bonus      # limpia solo bonus
EOF
}

target="${1:-all}"
deep="${2:-}"

case "$target" in
  all)
    reset_p1
    reset_p2
    reset_p3
    reset_bonus
    ;;
  p1)
    reset_p1
    ;;
  p2)
    reset_p2
    ;;
  p3)
    if [ "$deep" = "--deep" ]; then
      reset_p3_deep
    else
      reset_p3
    fi
    ;;
  bonus)
    reset_bonus
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "Opción no válida: $target" >&2
    usage >&2
    exit 1
    ;;
esac

log "Limpieza completada"