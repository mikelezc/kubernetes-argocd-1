FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git jq \
    && rm -rf /var/lib/apt/lists/*

# Cliente Docker (sin daemon: el daemon real es el del host, vía el socket montado en run.sh)
RUN set -eux; \
    arch="$(uname -m)"; \
    case "$arch" in \
      x86_64) docker_arch="x86_64" ;; \
      aarch64|arm64) docker_arch="aarch64" ;; \
      *) echo "Arquitectura no soportada: $arch" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://download.docker.com/linux/static/stable/${docker_arch}/docker-27.3.1.tgz" -o /tmp/docker.tgz; \
    tar xzf /tmp/docker.tgz -C /tmp; \
    mv /tmp/docker/docker /usr/local/bin/docker; \
    rm -rf /tmp/docker /tmp/docker.tgz

# kubectl (mismo mecanismo que usa p3/scripts/install.sh)
RUN set -eux; \
    arch="$(uname -m)"; \
    case "$arch" in \
      x86_64) k8s_arch="amd64" ;; \
      aarch64|arm64) k8s_arch="arm64" ;; \
      *) echo "Arquitectura no soportada: $arch" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/${k8s_arch}/kubectl"; \
    chmod +x /usr/local/bin/kubectl

# k3d
RUN curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

WORKDIR /workspace
CMD ["bash"]
