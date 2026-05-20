#!/bin/bash
set -euo pipefail

# Crea un proyecto en gitlab.local y pushea un deployment inicial (v1)
# Uso (desde host): cd bonus && vagrant ssh -c 'bash /vagrant/scripts/create-gitlab-project-and-push.sh'

KUBECONFIG="${KUBECONFIG:-/home/vagrant/.kube/config}"
export KUBECONFIG

GITLAB_URL="http://gitlab.local"
PROJECT_NAME="playground-demo"
NAMESPACE="root"

echo "Esperando GitLab disponible en ${GITLAB_URL}..."
for i in $(seq 1 40); do
  if curl -sSf ${GITLAB_URL}/users/sign_in >/dev/null 2>&1; then
    break
  fi
  sleep 3
done

echo "Obteniendo contraseña root desde el cluster bonus..."
ROOT_PWD=$(kubectl -n gitlab get secret gitlab-gitlab-initial-root-password -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || true)
if [ -z "$ROOT_PWD" ]; then
  echo "No pude leer la contraseña root del secreto. Asegúrate de que GitLab está listo.";
  exit 1
fi

echo "Intentando obtener token de sesión vía API..."
SESSION_JSON=$(curl -s --data "login=root&password=${ROOT_PWD}" ${GITLAB_URL}/api/v4/session || true)
TOKEN=$(echo "$SESSION_JSON" | sed -n 's/.*"private_token":"\([^"]*\)".*/\1/p' || true)

if [ -z "$TOKEN" ]; then
  echo "No se pudo obtener token vía /api/v4/session. Intentaré crear proyecto usando credenciales admin (si tu GitLab permite)."
fi

echo "Creando proyecto '${PROJECT_NAME}'..."
if [ -n "$TOKEN" ]; then
  CREATE_JSON=$(curl -s --header "PRIVATE-TOKEN: ${TOKEN}" -X POST "${GITLAB_URL}/api/v4/projects" -F "name=${PROJECT_NAME}" -F "visibility=private")
else
  CREATE_JSON=$(curl -s -u "root:${ROOT_PWD}" -X POST "${GITLAB_URL}/api/v4/projects" -F "name=${PROJECT_NAME}" -F "visibility=private" || true)
fi

REPO_URL=$(echo "$CREATE_JSON" | sed -n 's/.*"http_url_to_repo":"\([^"]*\)".*/\1/p' || true)
if [ -z "$REPO_URL" ]; then
  echo "No pude crear o leer el repo desde la API. Salida de la API:";
  echo "$CREATE_JSON";
  echo "Puedes crear el proyecto manualmente en http://gitlab.local/ (login root) y reejecutar este script.";
  exit 1
fi

echo "Repo creado: $REPO_URL"

TMPDIR=$(mktemp -d)
cd "$TMPDIR"

cat > deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wil-playground
  namespace: dev
spec:
  replicas: 1
  selector:
    matchLabels:
      app: playground
  template:
    metadata:
      labels:
        app: playground
    spec:
      containers:
      - name: wil-playground
        image: wil42/playground:v1
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 8888
---
apiVersion: v1
kind: Service
metadata:
  name: wil-playground
  namespace: dev
spec:
  type: NodePort
  ports:
  - port: 8888
    targetPort: 8888
    nodePort: 30080
  selector:
    app: playground
EOF

git init -q
git config user.email "vagrant@local"
git config user.name "vagrant"
git add deployment.yaml
git commit -q -m "Initial playground v1"

# Empujar usando auth HTTP embebida (url-encode password)
ESC_PWD=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$ROOT_PWD")
AUTH_URL=$(echo "$REPO_URL" | sed "s#http://#http://root:${ESC_PWD}@#")

echo "Pusheando a $AUTH_URL ..."
git remote add origin "$AUTH_URL"
git push -u origin master -q

echo "Proyecto y commit inicial creados en GitLab: $REPO_URL"
echo "Limpio temporales..."
cd /tmp
rm -rf "$TMPDIR"

echo "Hecho. Ahora ejecuta el script en p3 para añadir el repo a ArgoCD y crear la Application."
exit 0
