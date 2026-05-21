#!/bin/bash
set -euo pipefail

# Crea un secret de repo en ArgoCD apuntando a gitlab.local y aplica una Application
# Uso (desde host): cd p3 && vagrant ssh -c 'bash /vagrant/scripts/setup-argocd-app.sh'

KUBECONFIG="${KUBECONFIG:-/home/vagrant/.kube/config}"
export KUBECONFIG

GITLAB_HOST=gitlab.local
GITLAB_IP=192.168.56.111
PROJECT_PATH="root/playground-demo.git"
REPO_URL_HTTP="http://${GITLAB_HOST}/${PROJECT_PATH}"

echo "Creando secret de repo en ArgoCD (namespace argocd)..."
ROOT_PWD=$(kubectl -n gitlab get secret gitlab-gitlab-initial-root-password -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || true)
if [ -z "$ROOT_PWD" ]; then
  echo "No pude obtener la contraseña root desde el cluster bonus" >&2
  exit 1
fi

cat > /tmp/repo-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: repo-gitlab-local
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  url: "${REPO_URL_HTTP}"
  username: "root"
  password: "${ROOT_PWD}"
EOF

kubectl apply -f /tmp/repo-secret.yaml
rm -f /tmp/repo-secret.yaml

echo "Aplicando Application de ArgoCD 'playground-demo'..."
read -r -d '' APP_YAML <<'APP'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: playground-demo
  namespace: argocd
spec:
  project: default
  source:
    repoURL: http://gitlab.local/root/playground-demo.git
    targetRevision: HEAD
    path: .
  destination:
    server: https://kubernetes.default.svc
    namespace: dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true

APP

echo "$APP_YAML" | kubectl apply -f -

echo "Esperando sincronización inicial (hasta 2 minutos)..."
for i in $(seq 1 24); do
  status=$(kubectl -n argocd get application playground-demo -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "")
  if [ "$status" = "Synced" ]; then
    echo "Application sincronizada"
    exit 0
  fi
  sleep 5
done

echo "La Application no alcanzó 'Synced' en tiempo. Revisa 'kubectl -n argocd describe application playground-demo' para errores."
exit 1
