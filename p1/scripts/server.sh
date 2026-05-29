#!/bin/bash
# scripts/server.sh
# K3s recomienda tener un comportamiento predecible del nodo usando las IPs de arriba

set -euo pipefail

SERVER_IP=$1
IFACE=$(ip -4 addr show | grep $SERVER_IP | awk '{print $NF}')


echo "========================================================="
echo " Instalando K3S en modo SERVER en mlezcanoS..."
echo "========================================================="

# Descargar e instalar k3s.
# Explicación de los flags:
# server: Inicia k3s como nodo maestro (controlador)
# --write-kubeconfig-mode 644: Permite usar kubectl al usuario de vagrant sin usar sudo.
# --node-ip=$SERVER_IP: Le dice explícitamente qué IP enrutar.
# --bind-address=$SERVER_IP: Escucha las conexiones de k3s (API) por IP privada.
# --flannel-iface=eth1: Le dice a Kubernetes (Flannel) por qué interfaz de red pasar el tráfico, eth1 suele ser la de private_network en Vagrant.

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --write-kubeconfig-mode 644 \
  --tls-san $SERVER_IP \
  --node-ip $SERVER_IP \
  --bind-address $SERVER_IP \
  --flannel-iface $IFACE" sh -

# El servidor de k3s crea un TOKEN secreto (como contraseña) que 
# usarán los workers para poder unirse a él.
echo "Esperando que k3s genere el node-token..."
while [ ! -f /var/lib/rancher/k3s/server/node-token ]; do
  sleep 2
done

# Copiamos ese token secreto a /vagrant
# IMPORTANTE: /vagrant es una carpeta compartida entre el Mac y las VMs.
# Así, el worker podrá leer el archivo `/vagrant/node-token` cuando despierte.
cp /var/lib/rancher/k3s/server/node-token /vagrant/node-token

echo "Instalación del Server k3s Completada!"
