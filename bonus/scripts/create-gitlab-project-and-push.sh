#!/bin/bash
set -euo pipefail

# Crea un proyecto en el GitLab local y sube un demo inicial con identidad propia.
# Se puede lanzar desde el host: el script se re-ejecuta dentro de la VM si hace falta.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BONUS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
KUBECONFIG_DEFAULT="/home/vagrant/.kube/config"

if [ -z "${BONUS_INSIDE_VM:-}" ] && [ ! -s "$KUBECONFIG_DEFAULT" ]; then
  if command -v vagrant >/dev/null 2>&1 && [ -f "${BONUS_ROOT}/Vagrantfile" ]; then
    echo "No estoy dentro de la VM. Reejecutando el helper con Vagrant..."
    cd "$BONUS_ROOT"
    BONUS_INSIDE_VM=1 vagrant ssh -c 'cd /vagrant && BONUS_INSIDE_VM=1 bash /vagrant/scripts/create-gitlab-project-and-push.sh'
    exit $?
  fi

  echo "No encuentro el kubeconfig de la VM. Ejecuta primero 'vagrant up' y luego lanza este script dentro de la VM."
  exit 1
fi

export KUBECONFIG="${KUBECONFIG:-$KUBECONFIG_DEFAULT}"

GITLAB_URL="http://gitlab.local"
PROJECT_NAMESPACE="root"
PROJECT_PATH="mlezcano-gitlab-demo"
PROJECT_FULL_PATH="${PROJECT_NAMESPACE}/${PROJECT_PATH}"
ARGO_REPO_URL="http://gitlab-webservice-default.gitlab.svc:8181/${PROJECT_FULL_PATH}.git"
K3D_CLUSTER_NAME="iot-bonus"
BRAND_IMAGE_TAG="mlezcano/playground:gitlab-badge"
PROJECT_URL=""
PROJECT_REPO_URL=""
GITLAB_PAT_NAME="mlezcano-argo"

log() {
  echo "[$1] $2"
}

wait_for_gitlab_ui() {
  log "1/6" "Esperando GitLab disponible en ${GITLAB_URL}..."
  for _ in $(seq 1 60); do
    if curl -fsS "${GITLAB_URL}/users/sign_in" >/dev/null 2>&1; then
      return 0
    fi
    sleep 3
  done

  echo "GitLab no respondió a tiempo. Revisa que la VM siga levantada y que el namespace gitlab esté Ready."
  exit 1
}

create_gitlab_pat() {
  local toolbox_pod pat_output
  toolbox_pod=$(get_toolbox_pod)

  if [ -z "$toolbox_pod" ]; then
    echo "No encuentro el pod toolbox de GitLab dentro del clúster."
    exit 1
  fi

  log "2/6" "Creando token de acceso de GitLab para Git y Argo CD..."
  pat_output=$(kubectl exec -i -n gitlab -c toolbox "$toolbox_pod" -- gitlab-rails runner - <<'RUBY' 2>/dev/null || true
user = User.find_by_username('root')
user.personal_access_tokens.where(name: 'mlezcano-argo').delete_all

response = PersonalAccessTokens::CreateService.new(
  current_user: user,
  target_user: user,
  organization_id: user.organization_id,
  params: {
    name: 'mlezcano-argo',
    scopes: [:read_repository, :write_repository]
  }
).execute

abort(response.message) unless response.success?
puts response.payload[:personal_access_token].token
RUBY
)

  PAT_TOKEN=$(printf '%s
' "$pat_output" | tail -n 1 | tr -d '\r')
  if [ -z "$PAT_TOKEN" ]; then
    echo "No pude crear el token de acceso de GitLab."
    echo "Salida de depuración:"
    echo "$pat_output"
    exit 1
  fi

  export PAT_TOKEN
}

get_toolbox_pod() {
  kubectl -n gitlab get pods -o name | grep '/gitlab-toolbox' | head -n 1 | cut -d/ -f2
}

ensure_project() {
  local toolbox_pod project_output project_web_url project_repo_url
  toolbox_pod=$(get_toolbox_pod)

  if [ -z "$toolbox_pod" ]; then
    echo "No encuentro el pod toolbox de GitLab dentro del clúster."
    exit 1
  fi

  log "3/6" "Creando proyecto '${PROJECT_PATH}' en GitLab..."
  project_output=$(kubectl exec -i -n gitlab -c toolbox "$toolbox_pod" -- gitlab-rails runner - <<'RUBY' 2>/dev/null || true
user = User.find_by_username('root')
project = Project.find_by_full_path('root/mlezcano-gitlab-demo')

if project.nil?
  project = Projects::CreateService.new(user, {
    name: 'mlezcano-gitlab-demo',
    path: 'mlezcano-gitlab-demo',
    visibility_level: Gitlab::VisibilityLevel::PRIVATE
  }).execute
end

abort(project.errors.full_messages.join(', ')) if project.respond_to?(:errors) && project.errors.any?
puts project.web_url
puts project.http_url_to_repo
RUBY
)
  project_web_url=$(printf '%s
' "$project_output" | sed -n '1p' | tr -d '\r')
  project_repo_url=$(printf '%s
' "$project_output" | sed -n '2p' | tr -d '\r')

  if [ -z "$project_repo_url" ] || [ "$project_repo_url" = "nil" ]; then
    echo "No pude crear ni leer el proyecto '${PROJECT_FULL_PATH}'."
    echo "Salida de depuración:"
    echo "$project_output"
    exit 1
  fi

  PROJECT_URL="$project_web_url"
  PROJECT_REPO_URL="$project_repo_url"
  export PROJECT_URL
  export PROJECT_REPO_URL
}

write_repo_files() {
  TMPDIR=$(mktemp -d)
  export TMPDIR
  cd "$TMPDIR"

  cat > deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mlezcano-playground
  namespace: dev
  labels:
    app: playground
    owner: mlezcano
    demo: gitlab-local
spec:
  replicas: 1
  selector:
    matchLabels:
      app: playground
  template:
    metadata:
      labels:
        app: playground
        owner: mlezcano
        demo: gitlab-local
    spec:
      containers:
      - name: mlezcano-playground
        image: ${BRAND_IMAGE_TAG}
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 8888
---
apiVersion: v1
kind: Service
metadata:
  name: mlezcano-playground
  namespace: dev
  labels:
    app: playground
    owner: mlezcano
    demo: gitlab-local
spec:
  type: NodePort
  ports:
  - port: 8888
    targetPort: 8888
    nodePort: 30080
  selector:
    app: playground
EOF

  cat > README.md <<'EOF'
# Mlezcano GitLab Local Demo

Este repositorio vive en el GitLab local del bonus y es el origen que Argo CD
usa para desplegar la aplicación de ejemplo.

Contiene:

- `deployment.yaml`: manifiesto de Kubernetes para la demo.
- `README.md`: nota visible para distinguir esta demo en GitLab.

La imagen usada es `mlezcano/playground:gitlab-badge` y muestra una insignia visible
de `Subido a GitLab` para dejar claro que la app viene del flujo local.
EOF
}

build_brand_image() {
  local build_dir
  build_dir=$(mktemp -d)

  cat > "$build_dir/Dockerfile" <<'EOF'
FROM python:3.9-slim

WORKDIR /app
COPY app.py /app/
EXPOSE 8888
CMD ["python", "/app/app.py"]
EOF

  cat > "$build_dir/app.py" <<'EOF'
#!/usr/bin/env python3
import http.server
import json
import os
import socketserver

PORT = 8888
VERSION = os.environ.get("VERSION", "v1")
BRAND = os.environ.get("BRAND", "Subido a GitLab")


def build_badge() -> str:
  return f'<div class="badge">{BRAND}</div>' if BRAND else ""


HTML_V1 = f"""
<!DOCTYPE html>
<html>
<head>
  <title>Playground - v1</title>
  <style>
    body {{ font-family: Arial; text-align: center; margin-top: 50px; background: #e8f5e9; }}
    h1 {{ color: #2e7d32; }}
    .version {{ font-size: 48px; color: #1b5e20; font-weight: bold; margin: 20px; }}
    .info {{ color: #555; margin-top: 20px; font-size: 18px; }}
    code {{ background: #f0f0f0; padding: 10px; display: inline-block; }}
    .badge {{ display: inline-block; margin-top: 14px; padding: 8px 14px; border-radius: 999px; background: #1b5e20; color: white; font-size: 14px; font-weight: bold; letter-spacing: 0.5px; }}
  </style>
</head>
<body>
  <h1>🎮 Mlezcano Playground</h1>
  {build_badge()}
  <div class="version">🟢 VERSION 1</div>
  <div class="info">Welcome to v1 - Initial Version</div>
  <code>{{"status":"ok", "message":"v1"}}</code>
</body>
</html>
"""


HTML_V2 = f"""
<!DOCTYPE html>
<html>
<head>
  <title>Playground - v2</title>
  <style>
    body {{ font-family: Arial; text-align: center; margin-top: 50px; background: #e3f2fd; }}
    h1 {{ color: #1565c0; }}
    .version {{ font-size: 48px; color: #0d47a1; font-weight: bold; margin: 20px; }}
    .info {{ color: #555; margin-top: 20px; font-size: 18px; }}
    code {{ background: #f0f0f0; padding: 10px; display: inline-block; }}
    .badge {{ display: inline-block; margin-top: 14px; padding: 8px 14px; border-radius: 999px; background: #0d47a1; color: white; font-size: 14px; font-weight: bold; letter-spacing: 0.5px; }}
  </style>
</head>
<body>
  <h1>🎮 Mlezcano Playground</h1>
  {build_badge()}
  <div class="version">🔵 VERSION 2</div>
  <div class="info">Welcome to v2 - Enhanced Version</div>
  <code>{{"status":"ok", "message":"v2"}}</code>
</body>
</html>
"""


class PlaygroundHandler(http.server.SimpleHTTPRequestHandler):
  def do_GET(self):
    if self.path == "/" or self.path == "":
      self.send_response(200)
      self.send_header("Content-type", "text/html; charset=utf-8")
      self.end_headers()
      html = HTML_V2 if VERSION == "v2" else HTML_V1
      self.wfile.write(html.encode("utf-8"))
    else:
      self.send_response(200)
      self.send_header("Content-type", "application/json")
      self.end_headers()
      self.wfile.write(json.dumps({"status": "ok", "message": VERSION}).encode())

  def log_message(self, format, *args):
    print(f"[{self.client_address[0]}] {format % args}")


if __name__ == "__main__":
  print(f"Starting Mlezcano Playground {VERSION} on port {PORT}")
  with socketserver.TCPServer(("", PORT), PlaygroundHandler) as httpd:
    print("Server running... Press Ctrl+C to stop")
    httpd.serve_forever()
EOF

  sudo docker build -t "$BRAND_IMAGE_TAG" "$build_dir" >/dev/null
  sudo k3d image import --mode direct "$BRAND_IMAGE_TAG" -c "$K3D_CLUSTER_NAME" >/dev/null
  rm -rf "$build_dir"
}

start_playground_port_forward() {
  local pf_pidfile="/tmp/mlezcano-playground-portforward.pid"
  local pf_log="/tmp/mlezcano-playground-portforward.log"

  if [ -f "$pf_pidfile" ] && kill -0 "$(cat "$pf_pidfile")" >/dev/null 2>&1; then
  kill "$(cat "$pf_pidfile")" >/dev/null 2>&1 || true
  fi

  pkill -f 'kubectl .*port-forward .*mlezcano-playground.*9999:8888' >/dev/null 2>&1 || true

  kubectl -n dev wait --for=condition=available deployment/mlezcano-playground --timeout=180s >/dev/null
  nohup kubectl -n dev port-forward svc/mlezcano-playground 9999:8888 --address 0.0.0.0 >"$pf_log" 2>&1 &
  echo $! > "$pf_pidfile"
  sleep 2
}

push_commit() {
  git init -q
  git config user.email "mlezcano@local"
  git config user.name "mlezcano"
  git add README.md deployment.yaml
  git commit -q -m "Initial mlezcano GitLab demo"
  git branch -M main

  echo "Pusheando a ${PROJECT_REPO_URL}..."
  ESC_PAT=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$PAT_TOKEN")
  AUTH_URL=$(echo "$PROJECT_REPO_URL" | sed "s#http://#http://root:${ESC_PAT}@#")

  git remote add origin "$AUTH_URL"
  if git ls-remote --exit-code --heads origin main >/dev/null 2>&1; then
    git fetch -q origin main
    git merge -q --allow-unrelated-histories -s ours -m "Sync remote main" origin/main
  fi

  git push -u origin main -q
}

configure_argocd_repo() {
  kubectl -n argocd delete secret repo-gitlab-local --ignore-not-found >/dev/null 2>&1 || true
  kubectl -n argocd create secret generic repo-gitlab-local \
    --from-literal=type=git \
    --from-literal=url="${ARGO_REPO_URL}" \
    --from-literal=username=root \
    --from-literal=password="${PAT_TOKEN}" \
    --from-literal=forceHttpBasicAuth=true \
    --from-literal=insecure=true >/dev/null
  kubectl -n argocd label secret repo-gitlab-local argocd.argoproj.io/secret-type=repository --overwrite >/dev/null
}

configure_argocd_application() {
  kubectl -n argocd apply -f - >/dev/null <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: iot-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: ${ARGO_REPO_URL}
    targetRevision: main
    path: .
  destination:
    server: https://kubernetes.default.svc
    namespace: dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
}

refresh_argocd() {
  kubectl -n argocd rollout restart deployment argocd-repo-server >/dev/null
  kubectl -n argocd rollout status deployment argocd-repo-server --timeout=180s >/dev/null
  kubectl -n argocd annotate application iot-app argocd.argoproj.io/refresh=hard --overwrite >/dev/null
}

print_argocd_login() {
  cat <<'EOF'
Si la UI de Argo CD te pide usuario y contraseña, eso es el login de Argo CD,
no las credenciales de GitLab.

Usuario: admin
Contraseña inicial:
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
EOF
}

print_next_steps() {
  cat <<EOF

=== Siguiente paso para la corrección ===
1. Fuerza Refresh o Sync en Argo CD.
2. Valida la app con:
  curl http://localhost:8889/
5. Cambia VERSION a v2 en el repo de GitLab y repite el push para mostrar la reconcilación.

URL del proyecto: ${PROJECT_URL}
Repositorio creado: ${PROJECT_REPO_URL}
URL interna para Argo CD: ${ARGO_REPO_URL}
Web del bonus: http://localhost:8889/
EOF
}

cleanup() {
  if [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ]; then
    rm -rf "$TMPDIR"
  fi
}

trap cleanup EXIT

wait_for_gitlab_ui
ensure_project
create_gitlab_pat
build_brand_image
log "4/6" "Proyecto listo: ${PROJECT_URL}"
write_repo_files
log "5/6" "Creando commit inicial y empujando a main..."
push_commit
log "6/6" "Configurando Argo CD con el repo privado y la Application..."
configure_argocd_repo
configure_argocd_application
refresh_argocd
start_playground_port_forward
log "6/6" "Proyecto, repo privado de Argo CD y Application creados correctamente."
print_argocd_login
print_next_steps
