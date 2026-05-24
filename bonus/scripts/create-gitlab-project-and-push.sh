#!/bin/bash
# bonus/scripts/create-gitlab-project-and-push.sh
# Responsabilidad: crear el proyecto en GitLab, generar un PAT y hacer push
# del manifiesto inicial. NO toca la configuración de Argo CD.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BONUS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
KUBECONFIG_DEFAULT="/home/vagrant/.kube/config"
PAT_FILE="/tmp/.gitlab-pat"

# Re-ejecución automática dentro de la VM si se lanza desde el host
if [ -z "${BONUS_INSIDE_VM:-}" ] && [ ! -s "$KUBECONFIG_DEFAULT" ]; then
    if command -v vagrant >/dev/null 2>&1 && [ -f "${BONUS_ROOT}/Vagrantfile" ]; then
        cd "$BONUS_ROOT"
        BONUS_INSIDE_VM=1 vagrant ssh -c \
            'cd /vagrant && BONUS_INSIDE_VM=1 bash /vagrant/scripts/create-gitlab-project-and-push.sh'
        exit $?
    fi
    echo "No encuentro el kubeconfig. Ejecuta primero 'vagrant up'."
    exit 1
fi

export KUBECONFIG="${KUBECONFIG:-$KUBECONFIG_DEFAULT}"

GITLAB_VM_URL="http://gitlab.localhost"
PROJECT_NAMESPACE="root"
PROJECT_PATH="mlezcano-gitlab-demo"
PROJECT_FULL_PATH="${PROJECT_NAMESPACE}/${PROJECT_PATH}"
PROJECT_REPO_URL_PUSH="${GITLAB_VM_URL}/${PROJECT_FULL_PATH}.git"
GITLAB_PAT_NAME="mlezcano-argo"

log() { echo "[$1] $2"; }

get_toolbox_pod() {
    kubectl -n gitlab get pods -o name | grep '/gitlab-toolbox' | head -n 1 | cut -d/ -f2
}

wait_for_gitlab_ui() {
    log "1/4" "Esperando GitLab disponible en el clúster..."
    kubectl -n gitlab wait --for=condition=ready pod \
        -l app=webservice,release=gitlab --timeout=900s >/dev/null 2>&1 || true
}

ensure_project() {
    local toolbox_pod project_output project_repo_url
    toolbox_pod=$(get_toolbox_pod)
    [ -z "$toolbox_pod" ] && { echo "No encuentro el pod toolbox de GitLab."; exit 1; }

    log "2/4" "Creando proyecto '${PROJECT_PATH}' en GitLab..."
    project_output=$(kubectl exec -i -n gitlab -c toolbox "$toolbox_pod" -- \
        gitlab-rails runner - <<'RUBY' 2>/dev/null || true
user = User.find_by_username('root')
project = Project.find_by_full_path('root/mlezcano-gitlab-demo')

if project.nil?
  project = Projects::CreateService.new(user, {
    name:             'mlezcano-gitlab-demo',
    path:             'mlezcano-gitlab-demo',
    visibility_level: Gitlab::VisibilityLevel::PRIVATE
  }).execute
end

abort(project.errors.full_messages.join(', ')) \
  if project.respond_to?(:errors) && project.errors.any?
puts project.http_url_to_repo
RUBY
)

    project_repo_url=$(printf '%s\n' "$project_output" | tail -n 1 | tr -d '\r')
    if [ -z "$project_repo_url" ] || [ "$project_repo_url" = "nil" ]; then
        echo "No pude crear el proyecto '${PROJECT_FULL_PATH}'."
        echo "Salida: $project_output"
        exit 1
    fi
}

create_gitlab_pat() {
    local toolbox_pod pat_output
    toolbox_pod=$(get_toolbox_pod)
    [ -z "$toolbox_pod" ] && { echo "No encuentro el pod toolbox de GitLab."; exit 1; }

    log "3/4" "Creando Personal Access Token '${GITLAB_PAT_NAME}'..."
    pat_output=$(kubectl exec -i -n gitlab -c toolbox "$toolbox_pod" -- \
        gitlab-rails runner - <<'RUBY' 2>/dev/null || true
user = User.find_by_username('root')
user.personal_access_tokens.where(name: 'mlezcano-argo').delete_all

response = PersonalAccessTokens::CreateService.new(
  current_user:    user,
  target_user:     user,
  organization_id: user.organization_id,
  params: { name: 'mlezcano-argo', scopes: [:read_repository, :write_repository] }
).execute

abort(response.message) unless response.success?
puts response.payload[:personal_access_token].token
RUBY
)

    PAT_TOKEN=$(printf '%s\n' "$pat_output" | tail -n 1 | tr -d '\r')
    if [ -z "$PAT_TOKEN" ]; then
        echo "No pude crear el token de acceso."
        echo "Salida: $pat_output"
        exit 1
    fi

    echo "$PAT_TOKEN" > "$PAT_FILE"
    chmod 600 "$PAT_FILE"
    export PAT_TOKEN
}

push_to_gitlab() {
    log "4/4" "Haciendo push del manifiesto a GitLab..."

    if [ -f "/vagrant/confs/deployment.yaml" ]; then
        MANIFEST_PATH="/vagrant/confs/deployment.yaml"
    else
        MANIFEST_PATH="${BONUS_ROOT}/confs/deployment.yaml"
    fi

    WORK_DIR=$(mktemp -d)
    trap 'rm -rf "$WORK_DIR"' EXIT

    cp "$MANIFEST_PATH" "$WORK_DIR/deployment.yaml"
    cat > "$WORK_DIR/README.md" <<'MD'
# mlezcano-gitlab-demo

Repositorio local en GitLab. Argo CD sincroniza desde aquí para desplegar
la aplicación de ejemplo en el namespace `dev`.

Para probar el flujo GitOps, edita `deployment.yaml` y cambia la imagen:
- `mikelezc/playground:v1`
- `mikelezc/playground:v2`

Cada commit en la rama `main` dispara una sincronización automática en Argo CD.
MD

    cd "$WORK_DIR"
    git init -q
    git config user.email "mlezcano@local"
    git config user.name "mlezcano"
    git add deployment.yaml README.md
    git commit -q -m "Initial commit: deployment manifest for Argo CD"
    git branch -M main

    ESC_PAT=$(python3 -c \
        'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' \
        "$PAT_TOKEN")
    AUTH_URL="${PROJECT_REPO_URL_PUSH/http:\/\//http://root:${ESC_PAT}@}"
    git remote add origin "$AUTH_URL"

    if git ls-remote --exit-code --heads origin main >/dev/null 2>&1; then
        git fetch -q origin main
        git merge -q --allow-unrelated-histories -s ours -m "Sync" origin/main
    fi

    git push -u origin main -q
}

wait_for_gitlab_ui
ensure_project
create_gitlab_pat
push_to_gitlab

echo ""
echo "============================================================"
echo "  Repositorio GitLab listo"
echo "============================================================"
echo ""
echo "  URL:      http://localhost:8081/${PROJECT_FULL_PATH}"
echo "  rama:     main"
echo "  manifest: deployment.yaml  (imagen: mikelezc/playground:v1)"
echo ""
echo "Próximo paso — conectar Argo CD al repositorio:"
echo "  ./scripts/connect-argocd-to-gitlab.sh"
echo ""
