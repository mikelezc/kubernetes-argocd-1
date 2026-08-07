#!/bin/bash

# Para más explicaciones es recomendable ver p1/scripts/server.sh primero

CYAN='\033[0;36m'
NC='\033[0m'

set -euo pipefail

SERVER_IP=$1
WORKER_IP=$2
IFACE=$(ip -4 addr show | grep $WORKER_IP | awk '{print $NF}')

echo -e "${CYAN}=========================================================${NC}"
echo -e "${CYAN} 2/2 Instalando K3S en modo AGENT en mlezcanoSW...${NC}"
echo -e "${CYAN}=========================================================${NC}"

echo -e "${CYAN}Esperando por el node-token de K3s Server para establecer conexión...${NC}"
timeout=120
while [ ! -f /vagrant/node-token ]; do
  timeout=$((timeout - 2))
  [ "$timeout" -le 0 ] && { echo "node-token no apareció a tiempo" >&2; exit 1; }
  sleep 2
done

# leemos y almacenamos el token de K3s Server para que el nodo worker pueda unirse al clúster.
TOKEN=$(cat /vagrant/node-token)

# Intalación del nodo worker (agent) de K3s:
# ... agent                		: Indica que el nodo ejecutará cargas de trabajo (Worker)
# --server https://... 			: Dirección y puerto (6443) del servidor K3s al que se unirá.
# --token $TOKEN       			: Token de autenticación para unirse al clúster de forma segura.
# --node-ip $WORKER_IP 			: Asigna la IP privada exacta de este nodo worker.
# --flannel-iface $IFACE		: Obligamos a la red interna de Pods (Flannel) usar interfaz privada calculada.

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="agent \
  --server https://$SERVER_IP:6443 \
  --token ${TOKEN} \
  --node-ip $WORKER_IP \
  --flannel-iface $IFACE" sh -

echo -e "${CYAN}Instalación del Worker Completada!${NC}"
