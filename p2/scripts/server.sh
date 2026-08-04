#!/bin/bash

CYAN='\033[0;36m'
NC='\033[0m'

set -euo pipefail

SERVER_IP=$1
IFACE=$(ip -4 addr show | grep $SERVER_IP | awk '{print $NF}')

echo -e "${CYAN}=========================================================${NC}"
echo -e "${CYAN} Instalando K3S en modo SERVER...${NC}"
echo -e "${CYAN}=========================================================${NC}"

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --write-kubeconfig-mode 644 \
  --node-ip $SERVER_IP \
  --bind-address $SERVER_IP \
  --flannel-iface $IFACE" sh -

echo -e "${CYAN}=========================================================${NC}"
echo -e "${CYAN} Esperando a que el clúster inicie correctamente...${NC}"
echo -e "${CYAN}=========================================================${NC}"

while [ ! -f /etc/rancher/k3s/k3s.yaml ]; do
  sleep 2
done

# Esperamos a que Traefik y CoreDNS levanten para recibir configuraciones:
sleep 15

echo -e "${CYAN}=========================================================${NC}"
echo -e "${CYAN} Desplegando las 3 aplicaciones en el clúster...${NC}"
echo -e "${CYAN}=========================================================${NC}"

# Indicamos a kubectl dónde está el archivo de configuración del clúster k3s
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Usamos kubectl para desplegar cada manifesto de aplicación y el manifiesto de Ingress
kubectl apply -f /vagrant/confs/app1.yaml
kubectl apply -f /vagrant/confs/app2.yaml
kubectl apply -f /vagrant/confs/app3.yaml
kubectl apply -f /vagrant/confs/ingress.yaml

echo -e "${CYAN}Instalación del Server k3s Completada!${NC}"
