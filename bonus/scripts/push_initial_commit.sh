#!/bin/bash
set -euo pipefail

# Empuja deployment.yaml al proyecto ya creado en gitlab.local
ROOT_PWD=$(kubectl -n gitlab get secret gitlab-gitlab-initial-root-password -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || true)
if [ -z "$ROOT_PWD" ]; then
  echo "No pude obtener la contraseña root" >&2
  exit 1
fi

REPO="http://gitlab.local/root/playground-demo.git"

TMPDIR=$(mktemp -d)
cd "$TMPDIR"

cat > deployment.yaml <<'YAML'
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
YAML

git init -q
git config user.email "vagrant@local"
git config user.name "vagrant"
git add deployment.yaml
git commit -q -m "Initial playground v1"

ESC_PWD=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$ROOT_PWD")
AUTH_URL=$(echo "$REPO" | sed "s#http://#http://root:${ESC_PWD}@#")

git remote add origin "$AUTH_URL"
if git push -u origin master -q; then
  echo "Pushed initial commit to $REPO"
else
  echo "Push failed" >&2
  git remote -v
  exit 1
fi

cd /tmp
rm -rf "$TMPDIR"
