#!/bin/bash
set -euo pipefail

# Este script crea un proyecto en el GitLab local y pushea un commit inicial con un manifiesto de Kubernetes.
# Luego configura Argo CD para usar ese repo privado y despliega la aplicación de ejemplo.
# El script detecta si se está ejecutando dentro de la VM y, si no, intenta reejecutarse dentro de la VM usando Vagrant.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BONUS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
KUBECONFIG_DEFAULT="/home/vagrant/.kube/config"

if [ -z "${BONUS_INSIDE_VM:-}" ] && [ ! -s "$KUBECONFIG_DEFAULT" ]; then
  if command -v vagrant >/dev/null 2>&1 && [ -f "${BONUS_ROOT}/Vagrantfile" ]; then
    cd "$BONUS_ROOT"
    BONUS_INSIDE_VM=1 vagrant ssh -c 'cd /vagrant && BONUS_INSIDE_VM=1 bash /vagrant/scripts/create-gitlab-project-and-push.sh'
    exit $?
  fi

  echo "No encuentro el kubeconfig de la VM. Ejecuta primero 'vagrant up' y luego lanza este script dentro de la VM."
  exit 1
fi

export KUBECONFIG="${KUBECONFIG:-$KUBECONFIG_DEFAULT}"

GITLAB_PUBLIC_HOST="localhost"
GITLAB_PUBLIC_PORT="8081"
GITLAB_PUBLIC_URL="http://${GITLAB_PUBLIC_HOST}:${GITLAB_PUBLIC_PORT}"
GITLAB_URL="${GITLAB_PUBLIC_URL}"
GITLAB_VM_URL="http://gitlab.localhost"
GITLAB_CLUSTER_BASE_URL="http://gitlab-webservice-default.gitlab.svc:8181"
PROJECT_NAMESPACE="root"
PROJECT_PATH="mlezcano-gitlab-demo"
PROJECT_FULL_PATH="${PROJECT_NAMESPACE}/${PROJECT_PATH}"
PROJECT_URL_PUBLIC="${GITLAB_PUBLIC_URL}/${PROJECT_FULL_PATH}"
PROJECT_REPO_URL_PUSH="${GITLAB_VM_URL}/${PROJECT_FULL_PATH}.git"
PROJECT_REPO_URL_INTERNAL="${GITLAB_CLUSTER_BASE_URL}/${PROJECT_FULL_PATH}.git"
ARGO_REPO_URL="${PROJECT_REPO_URL_INTERNAL}"
ARGO_PUBLIC_HOST="localhost"
ARGO_PUBLIC_URL="http://${ARGO_PUBLIC_HOST}:8081"
K3D_CLUSTER_NAME="iot-bonus"
PLAYGROUND_IMAGE="mikelezc/playground:v2"
PROJECT_URL=""
PROJECT_REPO_URL=""
GITLAB_PAT_NAME="mlezcano-argo"

log() {
  echo "[$1] $2"
}

wait_for_gitlab_ui() {
  log "1/6" "Esperando GitLab disponible dentro del clúster..."
  kubectl -n gitlab wait --for=condition=ready pod -l app=webservice,release=gitlab --timeout=900s >/dev/null 2>&1 || true
}

create_gitlab_pat() {
  local toolbox_pod pat_output
  toolbox_pod=$(get_toolbox_pod)

  if [ -z "$toolbox_pod" ]; then
    echo "No encuentro el pod toolbox de GitLab dentro del clúster."
    exit 1
  fi

  log "3/6" "Creando token de acceso de GitLab para Git y Argo CD..."
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

  log "2/6" "Creando proyecto '${PROJECT_PATH}' en GitLab..."
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

  PROJECT_URL="$PROJECT_URL_PUBLIC"
  PROJECT_REPO_URL="$PROJECT_REPO_URL_PUSH"
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
        image: ${PLAYGROUND_IMAGE}
        imagePullPolicy: IfNotPresent
        env:
        - name: VERSION
          value: "v2"
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

La imagen usada es `mikelezc/playground:v2`, la misma que se publica y valida en la Parte 3.
EOF
}

ensure_playground_image() {
  if ! sudo docker image inspect "$PLAYGROUND_IMAGE" >/dev/null 2>&1; then
    sudo docker pull "$PLAYGROUND_IMAGE" >/dev/null
  fi
}

start_playground_port_forward() {
  kubectl -n dev wait --for=condition=available deployment/mlezcano-playground --timeout=180s >/dev/null
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

configure_argocd_ingress() {
  kubectl -n argocd apply -f - >/dev/null <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
  namespace: argocd
spec:
  ingressClassName: traefik
  rules:
  - host: ${ARGO_PUBLIC_HOST}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 80
EOF
}

configure_argocd_insecure() {
  kubectl -n argocd patch configmap argocd-cmd-params-cm --type merge -p '{"data":{"server.insecure":"true"}}' >/dev/null
  kubectl -n argocd rollout restart deployment argocd-server >/dev/null
  kubectl -n argocd rollout status deployment argocd-server --timeout=180s >/dev/null
}

refresh_argocd() {
  kubectl -n argocd rollout restart deployment argocd-repo-server >/dev/null
  kubectl -n argocd rollout status deployment argocd-repo-server --timeout=180s >/dev/null
  kubectl -n argocd annotate application iot-app argocd.argoproj.io/refresh=hard --overwrite >/dev/null
}

print_next_steps() {
  cat <<EOF

============================================================
=================== Instalación completada =================
============================================================

Puedes acceder a Argo CD en: ${ARGO_PUBLIC_URL}
    - usuario: admin
  - contraseña: $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)

Puedes acceder al repositorio de GitLab en: ${PROJECT_URL}

Puedes acceder a la aplicación en: http://localhost:8889

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
ensure_playground_image
log "4/6" "Proyecto listo: ${PROJECT_URL}"
write_repo_files
log "5/6" "Creando commit inicial y empujando a main..."
push_commit
log "6/6" "Configurando Argo CD con el repo privado y la Application..."
configure_argocd_repo
configure_argocd_insecure
configure_argocd_ingress
configure_argocd_application
refresh_argocd
start_playground_port_forward
log "6/6" "Proyecto, repo privado de Argo CD y Application creados correctamente."
print_next_steps
