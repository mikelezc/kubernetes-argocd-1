#!/bin/bash
set -euo pipefail

# Actualiza deployment.yaml de playground-demo a v2 y push al repo en gitlab.local
# Uso (desde host): cd p3 && vagrant ssh -c 'bash /vagrant/scripts/update-demo-to-v2.sh TOKEN'
# O: export PAT='token'; vagrant ssh -c 'bash /vagrant/scripts/update-demo-to-v2.sh'

GITLAB_URL=http://gitlab.local
PAT="${1:-${PAT:-a214cd7dc135d9264368f9f1122d530f}}"
if [ -z "$PAT" ]; then
  echo "ERROR: Token PAT no proporcionado" >&2
  exit 1
fi

REPO_HTTP="http://root:${PAT}@gitlab.local/root/playground-demo.git"

TMPDIR=$(mktemp -d)
cd "$TMPDIR"

echo "Clonando repo..."
git clone "$REPO_HTTP" repo || { echo "Git clone falló"; exit 1; }
cd repo

if [ ! -f deployment.yaml ]; then
  echo "No encuentro deployment.yaml en el repo clonado. Abortando."; exit 1
fi

sed -i.bak 's/playground:v1/playground:v2/g' deployment.yaml || true
git add deployment.yaml
git commit -m "Upgrade playground to v2" || true
git push origin master

echo "Cambio a v2 empujado. Espera a ArgoCD sincronizar (o fuerza sync)."

rm -rf "$TMPDIR"
exit 0
