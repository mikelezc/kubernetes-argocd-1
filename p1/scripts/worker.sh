#!/bin/bash
# scripts/worker.sh
# Este script se ejecuta tras la instalación del servidor K3s. (server.sh)

# script basado en p1/scripts/server.sh
# para más explicaciones sobre las diferentes partes del script, 
# es recomendable consultar el archivo p1/scripts/server.sh

CYAN='\033[0;36m'
NC='\033[0m' # No Color

set -euo pipefail

# Se pasan ambas IPs como argumentos desde el Vagrantfile.
SERVER_IP=$1
WORKER_IP=$2
IFACE=$(ip -4 addr show | grep $WORKER_IP | awk '{print $NF}')

echo -e "${CYAN}=========================================================${NC}"
echo -e "${CYAN} Instalando K3S en modo AGENT en mlezcanoSW...${NC}"
echo -e "${CYAN}=========================================================${NC}"

# Espera a que el server node genere el token de conexión en la carpeta compartida
echo -e "${CYAN}Esperando por el node-token de K3s Server...${NC}"
while [ ! -f /vagrant/node-token ]; do
  sleep 2
done

# Leemos el token guardado por el servidor
TOKEN=$(cat /vagrant/node-token)

# Explicación de las flags:
# agent                			: Indica que el nodo ejecutará cargas de trabajo (Worker)
# --server https://... 			: Dirección y puerto (6443) del servidor K3s al que se unirá.
# --token $TOKEN       			: Clave de autenticación para unirse al clúster de forma segura.
# --node-ip $WORKER_IP 			: Asigna la IP privada exacta de este nodo worker.
# --flannel-iface $IFACE		: Obliga a la red interna de Pods (Flannel) a usar la interfaz privada calculada.

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="agent \
  --server https://$SERVER_IP:6443 \
  --token ${TOKEN} \
  --node-ip $WORKER_IP \
  --flannel-iface $IFACE" sh -

echo -e "${CYAN}Instalación del Worker Completada!${NC}"
