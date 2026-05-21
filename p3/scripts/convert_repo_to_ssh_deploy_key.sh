#!/usr/bin/env bash
set -euo pipefail

# Convierte la configuración del repo de ArgoCD para usar SSH (deploy key).
# Uso: GITLAB_TOKEN=<your-PAT> ./convert_repo_to_ssh_deploy_key.sh [gitlab_host] [project_path]
# Ejemplo:
# GITLAB_TOKEN=abc123 ./convert_repo_to_ssh_deploy_key.sh gitlab.local root/playground-demo

GITLAB_HOST=${1:-gitlab.local}
PROJECT_PATH=${2:-root/playground-demo}

if [ -z "${GITLAB_TOKEN:-}" ]; then
  echo "Error: exporta GITLAB_TOKEN con un Personal Access Token (scope: api)." >&2
  exit 1
fi

TIMESTAMP=$(date +%s)
WORKDIR="./deploy_key_$TIMESTAMP"
mkdir -p "$WORKDIR"

echo "Generando par de claves en $WORKDIR..."
ssh-keygen -t rsa -b 4096 -N "" -f "$WORKDIR/id_rsa" >/dev/null

PUBKEY=$(cat "$WORKDIR/id_rsa.pub")

echo "Obteniendo project id de GitLab..."
ENC_PROJECT=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$PROJECT_PATH")
PROJECT_JSON=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "http://$GITLAB_HOST/api/v4/projects/$ENC_PROJECT")
PROJECT_ID=$(echo "$PROJECT_JSON" | grep -o '"id":[0-9]*' | head -n1 | sed 's/"id"://') || true
if [ -z "$PROJECT_ID" ]; then
  echo "No pude obtener project id. Respuesta de API:"
  echo "$PROJECT_JSON"
  exit 1
fi
echo "Project id: $PROJECT_ID"

echo "Creando deploy key en GitLab (solo lectura)..."
curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -X POST "http://$GITLAB_HOST/api/v4/projects/$PROJECT_ID/deploy_keys" \
  -d "title=argocd-deploy-key-$TIMESTAMP" \
  -d "key=$PUBKEY" \
  -d "can_push=false" >/dev/null

REPO_SSH_URL="git@$GITLAB_HOST:$PROJECT_PATH.git"
SECRET_NAME="gitlab-ssh-repo-$TIMESTAMP"

echo "Creando Secret de ArgoCD con la clave privada..."
# empaquetar clave privada en base64 para transferirla a la VM p3
BASE64_PRIV=$(base64 < "$WORKDIR/id_rsa" | tr -d '\n')

echo "Transferiendo y aplicando secret en la VM p3..."
cd p3
vagrant ssh -c "mkdir -p /home/vagrant/.temp && echo '$BASE64_PRIV' | base64 -d > /home/vagrant/.temp/id_rsa && chmod 600 /home/vagrant/.temp/id_rsa && kubectl -n argocd delete secret $SECRET_NAME --ignore-not-found=true && kubectl -n argocd create secret generic $SECRET_NAME --from-file=sshPrivateKey=/home/vagrant/.temp/id_rsa --from-literal=url=$REPO_SSH_URL && kubectl -n argocd label secret $SECRET_NAME argocd.argoproj.io/secret-type=repository --overwrite"
cd - >/dev/null

echo "Actualizando la Application 'playground-demo' para usar la URL SSH..."
vagrant ssh -c "export KUBECONFIG=/home/vagrant/.kube/config; kubectl -n argocd patch application playground-demo --type merge -p '{\"spec\":{\"source\":{\"repoURL\":\"$REPO_SSH_URL\"}}}'"

echo
echo "Listo. Secret en argocd: $SECRET_NAME  — repo URL: $REPO_SSH_URL"
echo "La clave privada local está en: $WORKDIR/id_rsa (puedes borrarla si quieres)."
echo "Si ArgoCD no sincroniza automáticamente, entra en http://localhost:8080 y fuerza SYNC en 'playground-demo'."
