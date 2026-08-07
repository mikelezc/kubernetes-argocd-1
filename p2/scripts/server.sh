#!/bin/bash

CYAN='\033[0;36m'
NC='\033[0m'

set -euo pipefail

SERVER_IP=$1
IFACE=$(ip -4 addr show | grep $SERVER_IP | awk '{print $NF}')

echo -e "${CYAN}=========================================================${NC}"
echo -e "${CYAN} 1/3 Instalando K3S en modo SERVER...${NC}"
echo -e "${CYAN}=========================================================${NC}"

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --write-kubeconfig-mode 644 \
  --node-ip $SERVER_IP \
  --bind-address $SERVER_IP \
  --flannel-iface $IFACE" sh -

echo -e "${CYAN}=========================================================${NC}"
echo -e "${CYAN} 2/3 Esperando a que el clúster inicie correctamente...${NC}"
echo -e "${CYAN}=========================================================${NC}"

timeout=120
while [ ! -f /etc/rancher/k3s/k3s.yaml ]; do
  timeout=$((timeout - 2))
  [ "$timeout" -le 0 ] && { echo "k3s.yaml no apareció a tiempo" >&2; exit 1; }
  sleep 2
done

# Indicamos a kubectl dónde está el archivo de configuración del clúster k3s
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Esperamos a que Traefik se cree (--for=create) y complete su instalación (--for=condition=complete)
kubectl wait --for=create job/helm-install-traefik -n kube-system --timeout=60s || {
  echo "El Job de Helm-Traefik no se creó a tiempo. Estado actual:" >&2
  kubectl get pods -n kube-system -o wide
  kubectl describe job/helm-install-traefik -n kube-system
  exit 1
}
kubectl wait --for=condition=complete job/helm-install-traefik -n kube-system --timeout=240s || {
  echo "El Job de Helm-Traefik no se completó a tiempo. Estado actual:" >&2
  kubectl get pods -n kube-system -o wide
  kubectl describe job/helm-install-traefik -n kube-system
  exit 1
}
kubectl wait --for=condition=available deployment/traefik -n kube-system --timeout=240s || {
  echo "El Deployment de Traefik no quedó disponible a tiempo. Estado actual:" >&2
  kubectl get pods -n kube-system -o wide
  kubectl describe deployment/traefik -n kube-system
  exit 1
}

echo -e "${CYAN}=========================================================${NC}"
echo -e "${CYAN} 3/3 Desplegando las 3 aplicaciones en el clúster...${NC}"
echo -e "${CYAN}=========================================================${NC}"

# Usamos kubectl para desplegar cada manifesto de aplicación y el manifiesto de Ingress
kubectl apply -f /vagrant/confs/app1.yaml
kubectl apply -f /vagrant/confs/app2.yaml
kubectl apply -f /vagrant/confs/app3.yaml
kubectl apply -f /vagrant/confs/ingress.yaml

echo -e "${CYAN}Instalación del Server k3s Completada!${NC}"
