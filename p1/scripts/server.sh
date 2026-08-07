#!/bin/bash

CYAN='\033[0;36m'
NC='\033[0m'

# Modo estricto: detiene el script ante cualquier error o variable no definida.
set -euo pipefail

# El script recibe la IP del servidor como argumento desde el Vagrantfile.
SERVER_IP=$1
# Calculamos la interfaz de red que tiene asignada la IP del nodo worker. (Desde la VM)
IFACE=$(ip -4 addr show | grep $SERVER_IP | awk '{print $NF}')


echo -e "${CYAN}=========================================================${NC}"
echo -e "${CYAN} 1/2 Instalando K3S en modo SERVER en mlezcanoS...${NC}"
echo -e "${CYAN}=========================================================${NC}"

# Insatalación del nodo servidor (control plane) de K3s:
# ... server                	: Inicia K3s en modo servidor (Control Plane).
# --write-kubeconfig-mode 644	: Permisos de lectura a la configuración para usar 'kubectl' sin 'sudo'.
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

# Generamos el token de nodo de K3s para que los nodos worker puedan unirse al clúster.
echo  -e "${CYAN}Generando token de nodo de K3s...${NC}"

# Protegemos el token de nodo para que solo los nodos worker puedan unirse al clúster.
timeout=120
while [ ! -f /var/lib/rancher/k3s/server/node-token ]; do
  timeout=$((timeout - 2))
  [ "$timeout" -le 0 ] && { echo "node-token no se generó a tiempo" >&2; exit 1; }
  sleep 2
done

# Copia el token a /vagrant (directorio compartido con la máquina anfitriona/host),
# para que los nodos worker puedan leerlo al iniciar para unirse al clúster.
cp /var/lib/rancher/k3s/server/node-token /vagrant/node-token

echo  -e "${CYAN}Instalación del Server k3s Completada!${NC}"
