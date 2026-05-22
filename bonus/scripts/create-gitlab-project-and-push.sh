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
PROJECT_URL=""
PROJECT_REPO_URL=""

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

wait_for_root_password() {
  log "2/6" "Esperando la contraseña inicial de root..."
  for _ in $(seq 1 60); do
    ROOT_PASSWORD=$(kubectl -n gitlab get secret gitlab-gitlab-initial-root-password -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || true)
    if [ -n "$ROOT_PASSWORD" ]; then
      export ROOT_PASSWORD
      return 0
    fi
    sleep 5
  done

  echo "No pude leer el secreto gitlab-gitlab-initial-root-password."
  echo "Espera unos segundos más y vuelve a lanzar el script si GitLab sigue arrancando."
  exit 1
}

get_toolbox_pod() {
  kubectl -n gitlab get pods -o name | grep '/gitlab-toolbox' | head -n 1 | cut -d/ -f2
}

ensure_project() {
  local toolbox_pod project_output project_web_url project_repo_url ruby_script
  toolbox_pod=$(get_toolbox_pod)

  if [ -z "$toolbox_pod" ]; then
    echo "No encuentro el pod toolbox de GitLab dentro del clúster."
    exit 1
  fi

  log "3/6" "Creando proyecto '${PROJECT_PATH}' en GitLab..."
  ruby_script=$(cat <<'RUBY'
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

  project_output=$(kubectl exec -n gitlab -c toolbox "$toolbox_pod" -- gitlab-rails runner "$ruby_script" 2>/dev/null || true)
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

  cat > deployment.yaml <<'EOF'
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
        image: mikelezc/playground:v1
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

La imagen usada es `mikelezc/playground:v1` y el branding deja claro que es una
aplicación cargada desde GitLab local, no el flujo antiguo de `wil42`.
EOF
}

push_commit() {
  git init -q
  git config user.email "mlezcano@local"
  git config user.name "mlezcano"
  git add README.md deployment.yaml
  git commit -q -m "Initial mlezcano GitLab demo"
  git branch -M main

  echo "Pusheando a ${PROJECT_REPO_URL}..."
  ESC_PWD=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$ROOT_PASSWORD")
  AUTH_URL=$(echo "$PROJECT_REPO_URL" | sed "s#http://#http://root:${ESC_PWD}@#")

  git remote add origin "$AUTH_URL"
  if git ls-remote --exit-code --heads origin main >/dev/null 2>&1; then
    git fetch -q origin main
    git merge -q --allow-unrelated-histories -s ours -m "Sync remote main" origin/main
  fi

  git push -u origin main -q
}

print_next_steps() {
  cat <<EOF

=== Siguiente paso para la corrección ===
1. Si Argo CD ya apunta a este repo local, abre la UI y comprueba Sync/Health.
2. Si aún no apunta al repo local, actualiza bonus/confs/argocd.yaml con:
   ${PROJECT_REPO_URL}
3. En Argo CD, fuerza Refresh o Sync si hace falta.
4. Valida la app con:
   curl http://localhost:8888/
5. Cambia VERSION a v2 en el repo de GitLab y repite el push para mostrar la reconcilación.

URL del proyecto: ${PROJECT_URL}
Repositorio creado: ${PROJECT_REPO_URL}
EOF
}

cleanup() {
  if [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ]; then
    rm -rf "$TMPDIR"
  fi
}

trap cleanup EXIT

wait_for_gitlab_ui
wait_for_root_password
ensure_project
log "4/6" "Proyecto listo: ${PROJECT_URL}"
write_repo_files
log "5/6" "Creando commit inicial y empujando a main..."
push_commit
log "6/6" "Proyecto y commit inicial creados correctamente."
print_next_steps
