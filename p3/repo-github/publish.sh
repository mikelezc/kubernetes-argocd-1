#!/usr/bin/env bash
set -euo pipefail

# publish.sh - build and push playground images (multi-arch if possible)
# Usage:
# DOCKER_USER=mikelezc ./publish.sh v1
# or set DOCKER_USER env var and call without args to publish v1 and v2

DOCKER_USER=${DOCKER_USER:-mikelezc}
PLATFORMS=${PLATFORMS:-linux/amd64,linux/arm64}
BUILD_TAGS=("v1" "v2")

if ! command -v docker >/dev/null 2>&1; then
  echo "docker CLI not found" >&2
  exit 1
fi

echo "Docker user: $DOCKER_USER"

# verify login by checking docker info (best-effort)
if docker info | grep -q Username; then
  echo "Logged in:" $(docker info | grep Username)
else
  echo "No Username shown in docker info; ensure you're logged in as $DOCKER_USER"
fi

run_build_push() {
  local tag=$1
  local img=${DOCKER_USER}/playground:${tag}

  if docker buildx version >/dev/null 2>&1; then
    echo "Using buildx to build and push $img for platforms: $PLATFORMS"
    docker buildx build --platform "$PLATFORMS" --build-arg VERSION="$tag" -t "$img" --push .
  else
    echo "buildx not available, building local image and pushing as single-arch"
    docker build --build-arg VERSION="$tag" -t "$img" .
    docker push "$img"
  fi
}

if [ "$#" -gt 0 ]; then
  for arg in "$@"; do
    run_build_push "$arg"
  done
else
  for t in "${BUILD_TAGS[@]}"; do
    run_build_push "$t"
  done
fi

echo "Done."
