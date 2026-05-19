#!/bin/bash
# scripts/install.sh (Bonus)

echo "========================================================="
echo " Preparando la VM e Instalando utilidades base..."
echo "========================================================="

# Instalamos Docker si no está
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
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
echo " Instalando Helm, GitLab y Argo CD..."
echo "========================================================="

# Instalamos helm si no lo tienes
if ! command -v helm &> /dev/null; then
    curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | sudo bash
fi

# Creamos el cluster k3d
k3d cluster delete iot-bonus || true
# Importante: añadimos puertos extras para gitlab (80, 443, 22)
k3d cluster create iot-bonus --api-port 6550 -p "80:80@loadbalancer" -p "443:443@loadbalancer" -p "8080:8080@loadbalancer" -p "8888:8888@loadbalancer"

# Añadir repositorio de GitLab
helm repo add gitlab https://charts.gitlab.io/
helm repo update

# Crear namespace
kubectl create namespace gitlab
kubectl create namespace argocd
kubectl create namespace dev

echo "Instalando GitLab via Helm. Esto tomará MUCHO TIEMPO..."
# Usamos un despliegue minimalista pensado para evitar que los ordenadores exploten
# Soporte dual: Vagrant (/vagrant) o Linux Manual (..)
if [ -f "/vagrant/confs/gitlab-values.yaml" ]; then
    VALUES_PATH="/vagrant/confs/gitlab-values.yaml"
else
    VALUES_PATH="../confs/gitlab-values.yaml"
fi

helm upgrade --install gitlab gitlab/gitlab \
  --timeout 600s \
  --namespace gitlab \
  -f $VALUES_PATH

echo "Instalando Argo CD..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.10.4/manifests/install.yaml

echo "¡Instalación base completada!"
echo "Ten en cuenta que los pods de GitLab tardan mucho en mostrarse Ready."
echo "Usa: kubectl get pods -n gitlab -w"
