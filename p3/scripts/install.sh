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

# Creamos el cluster exponiendo el puerto 8080 (Traefik/Argo CD)
# y el puerto 8888 directo al NodePort 30080 de la app playground.
k3d cluster create iot-cluster --api-port 6550 -p "8080:80@loadbalancer" -p "8888:30080@server:0"

echo "========================================================="
echo " Configurando CoreDNS para usar resolvers públicos..."
echo "========================================================="
# Esperamos a que CoreDNS esté disponible
sleep 10
kubectl wait --for=condition=Ready pods -n kube-system -l k8s-app=kube-dns --timeout=60s || true

# Parchear CoreDNS para usar Google/Cloudflare en lugar de /etc/resolv.conf
# Esto evita problemas DNS intermitentes cuando los pods intenten resolver github.com
kubectl -n kube-system get configmap coredns -o yaml | \
  sed 's/forward \. \/etc\/resolv.conf/forward . 8.8.8.8 1.1.1.1/' | \
  kubectl apply -f -

# Reiniciar CoreDNS para aplicar cambios
kubectl rollout restart deployment/coredns -n kube-system
kubectl rollout status deployment/coredns -n kube-system --timeout=60s
echo "CoreDNS configurado exitosamente."

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

# Argo CD fuerza HTTPS por defecto. Para servirlo detrás del puerto 8080 local,
# lo ponemos en modo insecure para que no redirija a https://localhost:8080.
kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p '{"data":{"server.insecure":"true"}}'
kubectl rollout restart deployment/argocd-server -n argocd
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s

# Configuramos Argo CD para que se exponga sin SSL y poder entrar por puerto 8080 localmente.
# Forzamos Argo CD a usar el entrypoint `web` para que Traefik lo sirva desde el puerto 80.
cat <<EOF | kubectl apply -n argocd -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: argocd
  annotations:
    ingress.kubernetes.io/ssl-redirect: "false"
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  ingressClassName: traefik
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

# No usamos entrypoint extra en Traefik para la app.
# La app sale por NodePort fijo (30080) y k3d lo mapea a localhost:8888.

echo "========================================================="
echo " Construyendo Imágenes Docker Locales (v1 y v2)..."
echo "========================================================="
# Obtener la ruta del Dockerfile (compatible con Vagrant y Linux manual)
if [ -f "/vagrant/app-para-tu-github/Dockerfile" ]; then
    DOCKERFILE_PATH="/vagrant/app-para-tu-github/Dockerfile"
else
    DOCKERFILE_PATH="../app-para-tu-github/Dockerfile"
fi

# Construir v1 (sin --build-arg, VERSION por defecto es v1)
echo "Construyendo imagen playground:v1..."
docker build -t playground:v1 -f "$DOCKERFILE_PATH" "$(dirname "$DOCKERFILE_PATH")"

# Construir v2 (con --build-arg VERSION=v2)
echo "Construyendo imagen playground:v2..."
docker build --build-arg VERSION=v2 -t playground:v2 -f "$DOCKERFILE_PATH" "$(dirname "$DOCKERFILE_PATH")"

# Subirlas a K3d (hacerlas disponibles en la VM)
echo "Inyectando imágenes en K3d..."
k3d image import playground:v1 -c iot-cluster
k3d image import playground:v2 -c iot-cluster

echo "Imágenes locales construidas exitosamente."

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
echo "Para entrar en la web de la app (después de hacer deploy con Argo CD):"
echo "URL: http://localhost:8888"
echo "========================================================="
