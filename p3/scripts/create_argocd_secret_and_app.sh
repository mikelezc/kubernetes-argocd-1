#!/bin/bash
set -euo pipefail

# Crea el secret de repo en ArgoCD y aplica la Application usando la contraseña root pasada
# por la variable de entorno ROOT_PWD.

KUBECONFIG="${KUBECONFIG:-/home/vagrant/.kube/config}"
export KUBECONFIG

if [ -z "${ROOT_PWD:-}" ]; then
  echo "ERROR: ROOT_PWD no definido. Ejecuta: ROOT_PWD=pa$$ bash /vagrant/scripts/create_argocd_secret_and_app.sh" >&2
  exit 1
fi

REPO_URL="http://gitlab.local/root/playground-demo.git"

cat >/tmp/repo-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: repo-gitlab-local
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  url: "${REPO_URL}"
  username: "root"
  password: "${ROOT_PWD}"
EOF

kubectl apply -f /tmp/repo-secret.yaml --validate=false || true
rm -f /tmp/repo-secret.yaml

cat >/tmp/app.yaml <<'APP'
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

kubectl apply -f /tmp/app.yaml --validate=false || true
kubectl -n argocd get application playground-demo -o yaml || true

exit 0
