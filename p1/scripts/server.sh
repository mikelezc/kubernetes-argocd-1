#!/bin/bash
# scripts/server.sh

CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Modo estricto: detiene el script ante cualquier error o variable no definida.
set -euo pipefail

# El script recibe la IP del servidor como argumento. (Vagrantfile)
SERVER_IP=$1

# Obtenemos la interfaz de red que tiene asignada la IP del servidor. (Desde la VM)
IFACE=$(ip -4 addr show | grep $SERVER_IP | awk '{print $NF}')


echo -e "${CYAN}=========================================================${NC}"
echo -e "${CYAN} Instalando K3S en modo SERVER en mlezcanoS...${NC}"
echo -e "${CYAN}=========================================================${NC}"

# Explicación de las flags:
# server                		: Inicia K3s en modo servidor (Control Plane).
# --write-kubeconfig-mode 644	: Da permisos de lectura a la configuración para usar 'kubectl' sin 'sudo'.
# --tls-san=$SERVER_IP   		: Incluye la IP privada en el certificado SSL para evitar errores de conexión segura.
# --node-ip=$SERVER_IP   		: Le indica al clúster la IP privada exacta de esta máquina.
# --bind-address=$SERVER_IP 	: Fuerza a la API de Kubernetes a escuchar conexiones solo en la IP privada.
# --flannel-iface=eth1  		: Obliga a la red de Pods (Flannel) a usar la interfaz privada de Vagrant.

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --write-kubeconfig-mode 644 \
  --tls-san $SERVER_IP \
  --node-ip $SERVER_IP \
  --bind-address $SERVER_IP \
  --flannel-iface $IFACE" sh -

# Espera a que K3s genere el token que necesitarán los workers para unirse al clúster.
echo  -e "${CYAN}Esperando el token de nodo de K3s...${NC}"
while [ ! -f /var/lib/rancher/k3s/server/node-token ]; do
  sleep 2
done

# Copia el token a /vagrant (directorio compartido con la máquina anfitriona/host).
# De este modo, los nodos worker podrán leerlo al iniciar para unirse al clúster.
cp /var/lib/rancher/k3s/server/node-token /vagrant/node-token

echo  -e "${CYAN}Instalación del Server k3s Completada!${NC}"
