#!/bin/bash
# scripts/install.sh (Parte 3)

echo "========================================================="
echo " Instalando Docker, K3d y utilidades..."
echo "========================================================="

# Instalamos Docker si no está (orientado a Ubuntu/Debian)
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    # Aplicar cambios al grupo sin requerir logout (a veces falla, es mejor advertir al user)
    newgrp docker
fi

# Instalamos kubectl cross-platform
if ! command -v kubectl &> /dev/null; then
    ARCH=$(dpkg --print-architecture)
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH}/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
fi

# Instalamos K3d
if ! command -v k3d &> /dev/null; then
    curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
fi

echo "========================================================="
echo " Creando Cluster K3d..."
echo "========================================================="
# Borramos el cluster si ya existía de pruebas anteriores
k3d cluster delete iot-cluster || true

# Creamos el cluster exponiendo el puerto 8888 para la aplicación y 
# el puerto 8080 para la interfaz de Argo CD
k3d cluster create iot-cluster --api-port 6550 -p "8080:80@loadbalancer" -p "8888:8888@loadbalancer"

echo "========================================================="
echo " Creando Namespaces y Desplegando Argo CD..."
echo "========================================================="
kubectl create namespace argocd
kubectl create namespace dev

# Desplegamos la version oficial de Argo CD (estable)
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.10.4/manifests/install.yaml

echo "Esperando que los pods de ArgoCD se levanten (esto puede tardar 1 o 2 minutos)..."
sleep 15
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s

# Configuramos Argo CD para que se exponga sin SSL y poder entrar por puerto 8080 localmente.
# En lugar de Ingress complejo, hacemos un Ingress muy básico hacia argo-server
cat <<EOF | kubectl apply -n argocd -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: argocd
  annotations:
    ingress.kubernetes.io/ssl-redirect: "false"
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              name: http
EOF

echo "========================================================="
echo " Configurando App Local con Argo CD..."
echo "========================================================="
# Soporte dual: Vagrant (/vagrant) o Linux Manual (..)
if [ -f "/vagrant/confs/argocd.yaml" ]; then
    kubectl apply -f /vagrant/confs/argocd.yaml
else
    kubectl apply -f ../confs/argocd.yaml
fi

echo "========================================================="
echo " ¡INSTALACIÓN COMPLETADA! "
echo "========================================================="
echo "Para entrar a Argo CD (UI):"
echo "URL: http://localhost:8080"
echo "Usuario: admin"
# La contraseña por defecto de argocd está en el siguiente secret:
SECRET=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "Contraseña: $SECRET"
echo "========================================================="
