#!/bin/bash
# scripts/worker.sh

SERVER_IP=$1
WORKER_IP=$2

echo "========================================================="
echo " Instalando K3S en modo AGENT en miguelSW..."
echo "========================================================="

# Recuperamos el TOKEN secreto que el servidor guardó en la carpeta compartida:
TOKEN=$(cat /vagrant/node-token)

# Descargar e instalar k3s pero ahora en modo AGENT
# Explicación de los flags:
# agent: indica que esta máquina sólo trabajará, no dirigirá el clúster.
# --server https://$SERVER_IP:6443: le dice dónde está el jefe (el Server) y su puerto.
# --token $TOKEN: es la contraseña que sacamos antes.
# --node-ip=$WORKER_IP: fuerza k3s a usar esta IP para la red privada.

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="agent \
  --server https://$SERVER_IP:6443 \
  --token ${TOKEN} \
  --node-ip $WORKER_IP \
  --flannel-iface eth1" sh -

echo "Instalación del Worker Completada! SRevisa el server para ver este nuevo nodo."
