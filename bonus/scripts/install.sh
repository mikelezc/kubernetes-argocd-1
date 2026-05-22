#!/bin/bash
# scripts/install.sh (Bonus)

set -e

progress_step() {
    echo ""
    echo "[$1] $2"
}

echo "========================================================="
echo " Preparando la VM e Instalando utilidades base..."
echo "========================================================="

progress_step "1/6" "Instalando Docker, kubectl y k3d"

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

progress_step "2/6" "Instalando Helm"

# Instalamos helm si no lo tienes
if ! command -v helm &> /dev/null; then
    curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | sudo bash
fi

progress_step "3/6" "Creando el cluster k3d iot-bonus"

# Creamos el cluster k3d
k3d cluster delete iot-bonus || true
# Importante: añadimos puertos extras para gitlab (80, 443, 22)
k3d cluster create iot-bonus --api-port 6550 -p "80:80@loadbalancer" -p "443:443@loadbalancer" -p "8080:8080@loadbalancer" -p "8888:8888@loadbalancer"

# Dejamos el kubeconfig disponible para futuras sesiones de vagrant ssh
mkdir -p /home/vagrant/.kube
k3d kubeconfig get iot-bonus > /home/vagrant/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube

progress_step "4/6" "Añadiendo el repo de GitLab y namespaces"

# Añadir repositorio de GitLab
helm repo add gitlab https://charts.gitlab.io/
helm repo update

# Crear namespace
kubectl create namespace gitlab 2>/dev/null || true
kubectl create namespace argocd 2>/dev/null || true
kubectl create namespace dev 2>/dev/null || true

echo "Instalando GitLab via Helm. Esto tomará MUCHO TIEMPO..."
progress_step "5/6" "Desplegando GitLab con Helm"
# Usamos un despliegue minimalista pensado para evitar que los ordenadores exploten
# Soporte dual: Vagrant (/vagrant) o Linux Manual (..)
if [ -f "/vagrant/confs/gitlab-values.yaml" ]; then
    VALUES_PATH="/vagrant/confs/gitlab-values.yaml"
else
    VALUES_PATH="../confs/gitlab-values.yaml"
fi

# El chart 10.x endurece la configuración y exige Redis/PostgreSQL/Object Storage externos.
# Para este laboratorio fijamos una versión anterior compatible con el values minimalista.
GITLAB_CHART_VERSION="9.9.0"

if ! helm upgrade --install gitlab gitlab/gitlab \
    --version "$GITLAB_CHART_VERSION" \
    --timeout 600s \
    --namespace gitlab \
    -f "$VALUES_PATH"; then
    echo "Error: GitLab no se pudo instalar con Helm. Revisa el mensaje anterior y el values.yaml."
    exit 1
fi

progress_step "6/6" "Desplegando Argo CD"

echo "Instalando Argo CD..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.10.4/manifests/install.yaml

echo "¡Instalación base completada!"
echo ""
echo "========================================================="
echo " GUIA RAPIDA DE USO"
echo "========================================================="
echo "1) Asegura este mapeo en tu Mac: 192.168.56.110 gitlab.local"
echo "2) Abre GitLab en: http://gitlab.local"
echo "3) Comprueba el estado de los pods con: kubectl get pods -n gitlab -w"
echo "4) Comprueba Argo CD con: kubectl get pods -n argocd -w"
echo "5) Si la UI no responde aun, espera a que GitLab pase a Ready; tarda bastante"
echo "6) La app de ejemplo queda expuesta en: http://localhost:8888"
echo ""
echo "Comandos utiles dentro de la VM:"
echo "- kubectl get pods -A"
echo "- kubectl get svc -n gitlab"
echo "- kubectl logs -n gitlab -l app=webservice --tail=50"
