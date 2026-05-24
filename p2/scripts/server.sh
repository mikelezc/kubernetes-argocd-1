#!/bin/bash
# scripts/server.sh (Parte 2)

SERVER_IP=$1

echo "========================================================="
echo " Instalando K3S en modo SERVER..."
echo "========================================================="

# Instalamos k3s. En K3s viene instalado "Traefik" por defecto para hacer el Ingress.
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --write-kubeconfig-mode 644 \
  --node-ip $SERVER_IP \
  --bind-address $SERVER_IP \
  --flannel-iface eth1" sh -

echo "========================================================="
echo " Esperando a que el clúster inicie correctamente..."
echo "========================================================="
while [ ! -f /etc/rancher/k3s/k3s.yaml ]; do
  sleep 2
done

# Esperamos un poco a que Traefik y CoreDNS levanten para recibir configuraciones:
sleep 15

echo "========================================================="
echo " Desplegando las 3 aplicaciones en el clúster..."
echo "========================================================="
# /vagrant aquí sigue siendo la carpeta compartida P2, así que 
# podemos aplicar los yamls de forma automática usando kubectl.
# --kubeconfig le dice donde está la autorización del clúster.

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

kubectl apply -f /vagrant/confs/app1.yaml
kubectl apply -f /vagrant/confs/app2.yaml
kubectl apply -f /vagrant/confs/app3.yaml
kubectl apply -f /vagrant/confs/ingress.yaml

echo "¡Listo! Si vas a tu Mac y usas curl probarás los hostnames app1.com y app2.com"
